#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
EH2 sign-off regression driver.

This is the top-level gate for the Ibex-style EH2 flow.  It can either launch
the required regression stages or evaluate existing stage result directories,
then writes a single sign-off JSON/Markdown report and returns a CI-friendly
exit code.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Tuple

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
DV_DIR = SCRIPT_DIR.parent
EH2_ROOT = DV_DIR.parents[2]
DEFAULT_OUT = EH2_ROOT / "build" / ("signoff_" + time.strftime("%Y%m%d_%H%M%S"))

sys.path.insert(0, str(SCRIPT_DIR))
from collect_results import collect_results, write_reports  # noqa: E402
from check_logs import check_sim_log  # noqa: E402
from metadata import RegressionSummary, TestRunResult  # noqa: E402


PROFILE_STAGES = {
    "quick": ["smoke", "directed"],
    "cosim": ["smoke", "cosim"],
    "nightly": ["smoke", "directed", "cosim", "riscvdv"],
    "full": ["smoke", "directed", "cosim", "riscvdv"],
}

STAGE_TESTLIST = {
    "directed": DV_DIR / "directed_tests" / "directed_testlist.yaml",
    "cosim": DV_DIR / "directed_tests" / "cosim_testlist.yaml",
    "riscvdv": DV_DIR / "riscv_dv_extension" / "testlist.yaml",
}

TEXT_REPORT_NAMES = (
    "dashboard.txt",
    "summary.txt",
    "coverage.txt",
    "cov_summary.txt",
    "report.txt",
    "urgReport.html",
)

COVERAGE_METRIC_ALIASES = {
    "overall": "overall",
    "total": "overall",
    "score": "overall",
    "line": "line",
    "lines": "line",
    "cond": "cond",
    "condition": "cond",
    "conditions": "cond",
    "fsm": "fsm",
    "toggle": "toggle",
    "tgl": "toggle",
    "branch": "branch",
    "assert": "assert",
    "assertion": "assert",
    "group": "functional",
    "covergroup": "functional",
    "functional": "functional",
}


def _json_default(obj):
    if isinstance(obj, Path):
        return str(obj)
    return str(obj)


def _cmd_str(cmd: List[str]) -> str:
    return " ".join(cmd)


def _split_csv(value: str) -> List[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def _load_yaml(path: Path):
    with open(path, "r") as f:
        return yaml.safe_load(f)


def resolve_stages(profile: str, stages_arg: str) -> List[str]:
    stages = _split_csv(stages_arg) if stages_arg else PROFILE_STAGES[profile]
    unknown = [stage for stage in stages if stage not in
               ("smoke", "directed", "cosim", "riscvdv")]
    if unknown:
        raise ValueError("Unknown sign-off stage(s): {}".format(
            ", ".join(unknown)))
    return stages


def parse_stage_result_args(stage_result_args: List[str]) -> Dict[str, Path]:
    results = {}
    for item in stage_result_args or []:
        if "=" not in item:
            raise ValueError("--stage-result must be STAGE=DIR")
        stage, directory = item.split("=", 1)
        stage = stage.strip()
        if stage not in ("smoke", "directed", "cosim", "riscvdv"):
            raise ValueError("Unknown stage in --stage-result: {}".format(stage))
        results[stage] = Path(directory).resolve()
    return results


def tool_exists(tool: str) -> bool:
    if os.path.isabs(tool):
        return os.path.exists(tool)
    return shutil.which(tool) is not None


def resolve_gcc_prefix() -> str:
    env_prefix = os.environ.get("GCC_PREFIX", "").strip()
    if env_prefix:
        candidate = Path(env_prefix) / "bin" / "riscv32-unknown-elf-gcc"
        if candidate.exists():
            return str(candidate)[:-len("-gcc")]
    return "riscv32-unknown-elf"


def precheck(stages: List[str], simulator: str) -> Dict:
    checks = []

    def add(name: str, passed: bool, detail: str):
        checks.append({"name": name, "passed": passed, "detail": detail})

    add("eh2_root", EH2_ROOT.exists(), str(EH2_ROOT))
    add("rtl_filelist", (DV_DIR / "eh2_rtl.f").exists(), str(DV_DIR / "eh2_rtl.f"))
    add("tb_filelist", (DV_DIR / "eh2_tb.f").exists(), str(DV_DIR / "eh2_tb.f"))

    sim_tool = {"vcs": "vcs", "xlm": "xrun", "questa": "vsim"}[simulator]
    simv_exists = (EH2_ROOT / "build" / "simv").exists()
    add("simulator_or_simv", simv_exists or tool_exists(sim_tool),
        "found build/simv" if simv_exists else sim_tool)

    if any(stage in stages for stage in ("directed", "cosim", "riscvdv")):
        gcc_prefix = resolve_gcc_prefix()
        add("riscv_gcc", tool_exists(gcc_prefix + "-gcc"), gcc_prefix + "-gcc")
        add("riscv_objcopy", tool_exists(gcc_prefix + "-objcopy"),
            gcc_prefix + "-objcopy")

    if "riscvdv" in stages:
        riscv_dv_run = EH2_ROOT / "vendor" / "google_riscv-dv" / "run.py"
        add("riscv_dv", riscv_dv_run.exists(), str(riscv_dv_run))

    if "cosim" in stages:
        libcosim = EH2_ROOT / "build" / "libcosim.so"
        add("spike_cosim_dpi", libcosim.exists(),
            "{} (run `make cosim` if missing)".format(libcosim))

    cfg_path = EH2_ROOT / "eh2_configs.yaml"
    if cfg_path.exists():
        try:
            cfg = _load_yaml(cfg_path) or {}
            default_threads = cfg.get("default", {}).get(
                "parameters", {}).get("NUM_THREADS")
            add("default_single_thread", default_threads == 1,
                "default NUM_THREADS={}".format(default_threads))
        except Exception as err:
            add("eh2_config_parse", False, "{}: {}".format(cfg_path, err))
    else:
        add("eh2_config", False, str(cfg_path))

    return {
        "passed": all(check["passed"] for check in checks),
        "checks": checks,
    }


def build_stage_cmd(stage: str, args, stage_out: Path) -> List[str]:
    run_regress = SCRIPT_DIR / "run_regress.py"
    cmd = [sys.executable, str(run_regress),
           "--simulator", args.simulator,
           "--seed", str(args.seed),
           "--output", str(stage_out)]

    if args.parallel > 1:
        cmd.extend(["--parallel", str(args.parallel)])
    if args.coverage:
        cmd.append("--coverage")
    if args.waves:
        cmd.append("--waves")
    if not args.allow_warnings:
        cmd.append("--fail-on-warnings")

    if stage == "smoke":
        cmd.extend([
            "--test", "smoke",
            "--binary", str(EH2_ROOT / "tests" / "asm" / "smoke.hex"),
            "--rtl-test", "core_eh2_base_test",
            "--sim-opts", "+disable_cosim=1",
        ])
    else:
        cmd.extend(["--testlist", str(STAGE_TESTLIST[stage])])
        if args.iterations:
            cmd.extend(["--iterations", str(args.iterations)])

    return cmd


def run_command(cmd: List[str], log_path: Path, timeout_s: int) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "wb") as log_fd:
        log_fd.write(("+ " + _cmd_str(cmd) + "\n").encode("utf-8"))
        try:
            proc = subprocess.run(
                cmd,
                stdout=log_fd,
                stderr=subprocess.STDOUT,
                timeout=timeout_s,
            )
            return proc.returncode
        except subprocess.TimeoutExpired:
            log_fd.write(("\nERROR: signoff stage timed out after {}s\n".
                          format(timeout_s)).encode("utf-8"))
            return 124


def summary_from_report_json(report_path: Path) -> RegressionSummary:
    data = json.loads(report_path.read_text(encoding="utf-8"))
    summary = RegressionSummary()
    summary.total_time_sec = float(data.get("total_time_sec", 0.0) or 0.0)
    for item in data.get("tests", []):
        trr = TestRunResult()
        trr.test_name = item.get("name", "")
        trr.seed = int(item.get("seed", 0) or 0)
        trr.test_type = item.get("type", "")
        trr.passed = bool(item.get("passed", False))
        trr.failure_mode = item.get("failure_mode", "")
        trr.sim_log_path = item.get("sim_log", "")
        trr.uvm_log_path = item.get("uvm_log", "")
        trr.trace_path = item.get("trace", "")
        trr.assembly_path = item.get("assembly", "")
        trr.binary_path = item.get("binary", "")
        trr.coverage_path = item.get("coverage", "")
        trr.uvm_errors = int(item.get("uvm_errors", 0) or 0)
        trr.uvm_warnings = int(item.get("uvm_warnings", 0) or 0)
        trr.num_instructions = int(item.get("instructions", 0) or 0)
        trr.num_cycles = int(item.get("cycles", 0) or 0)
        trr.ipc = float(item.get("ipc", 0.0) or 0.0)
        trr.gen_time_sec = float(item.get("gen_time_sec", 0.0) or 0.0)
        trr.compile_time_sec = float(item.get("compile_time_sec", 0.0) or 0.0)
        trr.sim_time_sec = float(item.get("sim_time_sec", 0.0) or 0.0)
        summary.add_result(trr)
    return summary


def refresh_failure_classification(summary: RegressionSummary):
    """Reclassify archived results with the current log checker.

    Old result.pkl files can contain stale failure modes.  Re-reading the log
    keeps sign-off reports aligned with the current gate policy.
    """
    for trr in summary.results:
        if not trr.sim_log_path:
            continue
        if not os.path.exists(trr.sim_log_path):
            continue
        checked = check_sim_log(trr.sim_log_path)
        trr.passed = checked.passed
        trr.failure_mode = checked.failure_mode
        trr.uvm_errors = checked.uvm_errors
        trr.uvm_warnings = checked.uvm_warnings
        trr.num_instructions = checked.num_instructions
        trr.num_cycles = checked.num_cycles
        trr.ipc = checked.ipc


def recompute_summary_counts(summary: RegressionSummary):
    summary.total_tests = len(summary.results)
    summary.passed = sum(1 for result in summary.results if result.passed)
    summary.failed = summary.total_tests - summary.passed


def load_stage_summary(results_dir: Path) -> Tuple[RegressionSummary, bool]:
    report_json = results_dir / "report.json"
    if report_json.exists():
        summary = summary_from_report_json(report_json)
        refresh_failure_classification(summary)
        recompute_summary_counts(summary)
        return summary, True

    summary = collect_results(str(results_dir))
    refresh_failure_classification(summary)
    recompute_summary_counts(summary)
    return summary, False


def collect_stage(stage: str, results_dir: Path, report_dir: Path,
                  command: List[str], exit_code: int,
                  fail_on_warnings: bool) -> Dict:
    summary, from_report_json = load_stage_summary(results_dir)
    write_reports(summary, str(report_dir))

    warning_count = sum(result.uvm_warnings for result in summary.results)
    result = {
        "stage": stage,
        "results_dir": str(results_dir),
        "report_dir": str(report_dir),
        "command": _cmd_str(command) if command else "",
        "exit_code": exit_code,
        "total": summary.total_tests,
        "passed": summary.passed,
        "failed": summary.failed,
        "pass_rate": 100.0 * summary.passed / max(1, summary.total_tests),
        "warnings": warning_count,
        "status": "PASS",
        "blockers": [],
        "source": "report.json" if from_report_json else "result.pkl",
        "tests": [],
    }

    for trr in summary.results:
        result["tests"].append({
            "name": trr.test_name,
            "seed": trr.seed,
            "passed": trr.passed,
            "failure_mode": trr.failure_mode,
            "warnings": trr.uvm_warnings,
            "sim_log": trr.sim_log_path,
        })

    if exit_code not in (None, 0):
        result["blockers"].append("stage command exit code {}".format(exit_code))
    if summary.total_tests == 0:
        result["blockers"].append("no test results collected")
    if summary.failed > 0:
        result["blockers"].append("{} test(s) failed".format(summary.failed))
    if fail_on_warnings and warning_count > 0:
        result["blockers"].append("{} warning(s) in warning-clean run".format(
            warning_count))

    if result["blockers"]:
        result["status"] = "FAIL"
    return result


def parse_coverage_text(text: str) -> Dict[str, float]:
    metrics = {}
    patterns = [
        re.compile(
            r"\b(line|lines|cond|condition|conditions|fsm|toggle|tgl|branch|"
            r"assert|assertion|group|covergroup|functional|overall|total|"
            r"score)\b(?:\s+coverage|\s+score)?\s*[:=]?\s*"
            r"([0-9]+(?:\.[0-9]+)?)\s*%",
            re.IGNORECASE),
        re.compile(
            r"\b(line|cond|fsm|tgl|toggle|branch|assert|score|total)\b"
            r"\s+\S+\s+\S+\s+([0-9]+(?:\.[0-9]+)?)\b",
            re.IGNORECASE),
    ]
    for pattern in patterns:
        for match in pattern.finditer(text):
            raw_name = match.group(1).lower()
            metric = COVERAGE_METRIC_ALIASES.get(raw_name)
            if not metric:
                continue
            value = float(match.group(2))
            if 0.0 <= value <= 100.0:
                metrics[metric] = max(metrics.get(metric, 0.0), value)
    return metrics


def coverage_candidate_files(paths: List[Path], output_dir: Path) -> List[Path]:
    candidates = []
    search_roots = list(paths)
    search_roots.extend([
        output_dir / "coverage",
        output_dir / "cov_report",
    ])

    for root in search_roots:
        if not root:
            continue
        root = Path(root)
        if root.is_file():
            candidates.append(root)
            continue
        if not root.is_dir():
            continue
        for name in TEXT_REPORT_NAMES:
            candidates.extend(Path(p) for p in glob.glob(str(root / "**" / name),
                                                         recursive=True))

    seen = set()
    uniq = []
    for path in candidates:
        real = str(path.resolve())
        if real not in seen and path.exists():
            seen.add(real)
            uniq.append(path)
    return uniq


def evaluate_coverage(paths: List[Path], output_dir: Path, args) -> Dict:
    thresholds = {
        "overall": args.min_overall_coverage,
        "line": args.min_line_coverage,
        "cond": args.min_cond_coverage,
        "fsm": args.min_fsm_coverage,
        "toggle": args.min_toggle_coverage,
        "functional": args.min_functional_coverage,
    }

    required = args.require_coverage or any(value > 0.0
                                           for value in thresholds.values())
    metrics = {}
    parsed_files = []

    if required or paths:
        files = coverage_candidate_files(paths, output_dir)

        for path in files:
            try:
                if path.stat().st_size > 5 * 1024 * 1024:
                    continue
                text = path.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue
            parsed = parse_coverage_text(text)
            if parsed:
                parsed_files.append(str(path))
            for key, value in parsed.items():
                metrics[key] = max(metrics.get(key, 0.0), value)

        if "overall" not in metrics and metrics:
            metrics["overall"] = sum(metrics.values()) / len(metrics)

    result = {
        "required": required,
        "status": "PASS",
        "metrics": metrics,
        "files": parsed_files,
        "thresholds": thresholds,
        "blockers": [],
    }

    if required and not metrics:
        result["blockers"].append("coverage report not found or not parseable")

    for metric, threshold in thresholds.items():
        if threshold <= 0.0:
            continue
        value = metrics.get(metric)
        if value is None:
            result["blockers"].append(
                "{} coverage missing (threshold {:.2f}%)".format(
                    metric, threshold))
        elif value < threshold:
            result["blockers"].append(
                "{} coverage {:.2f}% below threshold {:.2f}%".format(
                    metric, value, threshold))

    if result["blockers"]:
        result["status"] = "FAIL"
    elif not required and not metrics:
        result["status"] = "SKIP"
    return result


def collect_cosim_exceptions() -> List[str]:
    testlist = DV_DIR / "riscv_dv_extension" / "testlist.yaml"
    if not testlist.exists():
        return []
    try:
        entries = _load_yaml(testlist) or []
    except Exception:
        return []
    disabled = []
    for entry in entries:
        if str(entry.get("cosim", "")).lower() in ("disabled", "disable", "0",
                                                   "false", "no"):
            disabled.append(entry.get("test", "unknown"))
    return disabled


def evaluate_signoff(stage_results: List[Dict], coverage_result: Dict,
                     precheck_result: Dict, args) -> Tuple[str, List[str]]:
    blockers = []
    if not args.skip_precheck and not precheck_result.get("passed", False):
        blockers.append("precheck failed")

    if not stage_results:
        blockers.append("no sign-off stages were evaluated")

    for stage in stage_results:
        if stage["status"] != "PASS":
            blockers.append("{}: {}".format(
                stage["stage"], "; ".join(stage["blockers"])))
        if stage["pass_rate"] < args.min_pass_rate:
            blockers.append("{} pass rate {:.2f}% below {:.2f}%".format(
                stage["stage"], stage["pass_rate"], args.min_pass_rate))

    if coverage_result["status"] == "FAIL":
        blockers.append("coverage: {}".format(
            "; ".join(coverage_result["blockers"])))

    if args.require_cosim_all_tests:
        disabled = collect_cosim_exceptions()
        if disabled:
            blockers.append("riscv-dv tests with cosim disabled: {}".format(
                ", ".join(disabled)))

    return ("PASS" if not blockers else "FAIL", blockers)


def write_markdown_report(status: Dict, path: Path):
    lines = []
    lines.append("# EH2 Sign-off Report")
    lines.append("")
    lines.append("- Status: {}".format(status["status"]))
    lines.append("- Timestamp: {}".format(status["timestamp"]))
    lines.append("- Profile: {}".format(status["profile"]))
    lines.append("- Output: {}".format(status["output_dir"]))
    lines.append("")

    lines.append("## Stages")
    lines.append("")
    lines.append("| Stage | Status | Total | Passed | Failed | Pass Rate | Warnings |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for stage in status["stages"]:
        lines.append("| {stage} | {status} | {total} | {passed} | {failed} | "
                     "{pass_rate:.2f}% | {warnings} |".format(**stage))
    lines.append("")

    lines.append("## Coverage")
    coverage = status["coverage"]
    lines.append("")
    lines.append("- Status: {}".format(coverage["status"]))
    if coverage["metrics"]:
        for metric in sorted(coverage["metrics"]):
            lines.append("- {}: {:.2f}%".format(metric,
                                                coverage["metrics"][metric]))
    else:
        lines.append("- No parsed coverage metrics.")
    lines.append("")

    lines.append("## Precheck")
    lines.append("")
    for check in status["precheck"]["checks"]:
        state = "PASS" if check["passed"] else "FAIL"
        lines.append("- {}: {} ({})".format(check["name"], state,
                                            check["detail"]))
    lines.append("")

    disabled = status.get("cosim_disabled_tests", [])
    if disabled:
        lines.append("## Cosim Exceptions")
        lines.append("")
        lines.append("The following riscv-dv tests are marked cosim disabled "
                     "and must remain waiver-reviewed for final closure:")
        lines.append("")
        for test in disabled:
            lines.append("- {}".format(test))
        lines.append("")

    if status["blockers"]:
        lines.append("## Blockers")
        lines.append("")
        for blocker in status["blockers"]:
            lines.append("- {}".format(blocker))
        lines.append("")

    lines.append("## Commands")
    lines.append("")
    for stage in status["stages"]:
        if stage["command"]:
            lines.append("- {}: `{}`".format(stage["stage"], stage["command"]))

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Run/evaluate EH2 sign-off flow")
    parser.add_argument("--profile", choices=sorted(PROFILE_STAGES),
                        default="full", help="Sign-off stage preset")
    parser.add_argument("--stages", default="",
                        help="Comma-separated stage override")
    parser.add_argument("--output", default=str(DEFAULT_OUT),
                        help="Sign-off output directory")
    parser.add_argument("--stage-result", action="append", default=[],
                        help="Use existing results for a stage: STAGE=DIR")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print planned commands without running or gating")
    parser.add_argument("--gate-only", action="store_true",
                        help="Only evaluate --stage-result directories")
    parser.add_argument("--simulator", default="vcs",
                        choices=["vcs", "xlm", "questa"])
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--iterations", type=int, default=0,
                        help="Override per-test iterations for non-smoke stages")
    parser.add_argument("--parallel", type=int, default=1)
    parser.add_argument("--timeout-s", type=int, default=7200)
    parser.add_argument("--coverage", action="store_true",
                        help="Enable simulator coverage while running stages")
    parser.add_argument("--waves", action="store_true",
                        help="Enable waveform dumping while running stages")
    parser.add_argument("--coverage-path", action="append", default=[],
                        help="Coverage report file or directory to gate")
    parser.add_argument("--require-coverage", action="store_true",
                        help="Fail sign-off if coverage cannot be parsed")
    parser.add_argument("--min-pass-rate", type=float, default=100.0)
    parser.add_argument("--min-overall-coverage", type=float, default=0.0)
    parser.add_argument("--min-line-coverage", type=float, default=0.0)
    parser.add_argument("--min-cond-coverage", type=float, default=0.0)
    parser.add_argument("--min-fsm-coverage", type=float, default=0.0)
    parser.add_argument("--min-toggle-coverage", type=float, default=0.0)
    parser.add_argument("--min-functional-coverage", type=float, default=0.0)
    parser.add_argument("--allow-warnings", action="store_true",
                        help="Do not treat warnings as sign-off failures")
    parser.add_argument("--skip-precheck", action="store_true")
    parser.add_argument("--require-cosim-all-tests", action="store_true",
                        help="Fail if any riscv-dv test is marked cosim disabled")
    args = parser.parse_args(argv)

    output_dir = Path(args.output).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    stages = resolve_stages(args.profile, args.stages)
    stage_result_dirs = parse_stage_result_args(args.stage_result)

    planned = []
    for stage in stages:
        stage_out = output_dir / "runs" / stage
        planned.append((stage, build_stage_cmd(stage, args, stage_out), stage_out))

    if args.dry_run:
        print("EH2 sign-off plan: profile={} stages={}".format(
            args.profile, ",".join(stages)))
        for stage, cmd, _ in planned:
            print("{}: {}".format(stage, _cmd_str(cmd)))
        return 0

    precheck_result = {"passed": True, "checks": []}
    if not args.skip_precheck:
        precheck_result = precheck(stages, args.simulator)

    stage_results = []
    for stage, cmd, stage_out in planned:
        if stage in stage_result_dirs:
            results_dir = stage_result_dirs[stage]
            exit_code = 0
            command = []
        elif args.gate_only:
            results_dir = stage_out
            exit_code = 1
            command = []
        else:
            results_dir = stage_out
            command = cmd
            exit_code = run_command(
                cmd, output_dir / "logs" / "{}.log".format(stage),
                args.timeout_s)

        report_dir = output_dir / "reports" / stage
        stage_results.append(collect_stage(
            stage, results_dir, report_dir, command, exit_code,
            fail_on_warnings=not args.allow_warnings))

    coverage_paths = [Path(p).resolve() for p in args.coverage_path]
    coverage_result = evaluate_coverage(coverage_paths, output_dir, args)
    status, blockers = evaluate_signoff(stage_results, coverage_result,
                                        precheck_result, args)

    signoff_status = {
        "status": status,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "profile": args.profile,
        "stages_requested": stages,
        "output_dir": str(output_dir),
        "precheck": precheck_result,
        "stages": stage_results,
        "coverage": coverage_result,
        "cosim_disabled_tests": collect_cosim_exceptions(),
        "blockers": blockers,
    }

    json_path = output_dir / "signoff_status.json"
    md_path = output_dir / "signoff_report.md"
    json_path.write_text(json.dumps(signoff_status, indent=2,
                                    default=_json_default) + "\n",
                         encoding="utf-8")
    write_markdown_report(signoff_status, md_path)

    print("EH2 sign-off {}: {}".format(status, md_path))
    if blockers:
        print("Blockers:")
        for blocker in blockers:
            print("  - {}".format(blocker))

    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
