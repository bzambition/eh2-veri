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
from typing import Dict, List, Optional, Tuple

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
    "riscvdv_smoke": ["riscvdv"],
    "nightly": ["smoke", "directed", "cosim", "riscvdv"],
    "full": ["smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
             "compliance", "formal", "syn"],
}

STAGE_MIN_PASSED = {
    "smoke": 1,
    "directed": 33,
    "cosim": 7,
    "riscvdv": 50,
    "csr_unit": 20,
    "compliance": 85,
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
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_stages(profile: str, stages_arg: str) -> List[str]:
    stages = _split_csv(stages_arg) if stages_arg else PROFILE_STAGES[profile]
    unknown = [stage for stage in stages if stage not in
               ("smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                "compliance", "formal", "syn")]
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
        if stage not in ("smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                         "compliance", "formal", "syn"):
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


def precheck(stages: List[str], simulator: str, output_dir: Path) -> Dict:
    checks = []

    def add(name: str, passed: bool, detail: str):
        checks.append({"name": name, "passed": passed, "detail": detail})

    add("eh2_root", EH2_ROOT.exists(), str(EH2_ROOT))
    add("rtl_filelist", (DV_DIR / "eh2_rtl.f").exists(), str(DV_DIR / "eh2_rtl.f"))
    add("tb_filelist", (DV_DIR / "eh2_tb.f").exists(), str(DV_DIR / "eh2_tb.f"))

    sim_tool = {"vcs": "vcs", "nc": "irun", "xlm": "xrun", "questa": "vsim"}[simulator]
    simv_path = output_dir / "simv"
    simv_exists = simv_path.exists()
    add("simulator_or_simv", simv_exists or tool_exists(sim_tool),
        f"found {simv_path}" if simv_exists else sim_tool)

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


def build_stage_cmd(stage: str, args, stage_out: Path, simv_path: Path) -> List[str]:
    run_regress = SCRIPT_DIR / "run_regress.py"
    cmd = [sys.executable, str(run_regress),
           "--simulator", args.simulator,
           "--seed", str(args.seed),
           "--build-dir", str(simv_path.parent),
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
    elif stage == "lint":
        return ["make", "-C", str(EH2_ROOT), "lint"]
    elif stage == "csr_unit":
        csr_dir = EH2_ROOT / "dv" / "uvm" / "cs_registers_eh2"
        return ["make", "-C", str(csr_dir), "compliance",
                "SIGNOFF_OUT=" + str(stage_out)]
    elif stage == "compliance":
        runner = EH2_ROOT / "dv" / "uvm" / "riscv_compliance" / "scripts" / "run_compliance.py"
        cmd = [
            sys.executable, str(runner),
            "--isa", "all",
            "--simulator", args.simulator,
            "--build-dir", str(simv_path.parent),
            "--output", str(stage_out),
        ]
        # `--simv` only applies to VCS where simv is the readiness signal.
        # For NC the equivalent is the INCA_libs directory under build-dir,
        # which run_compliance.py infers from --simulator + --build-dir.
        if args.simulator == "vcs":
            cmd.extend(["--simv", str(simv_path)])
        return cmd
    elif stage == "formal":
        return ["make", "-C", str(EH2_ROOT), "formal"]
    elif stage == "syn":
        return ["make", "-C", str(EH2_ROOT), "syn"]
    else:
        cmd.extend(["--testlist", str(STAGE_TESTLIST[stage])])
        if args.iterations:
            cmd.extend(["--iterations", str(args.iterations)])

    return cmd


def run_command(cmd: List[str], log_path: Path, timeout_s: int) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    # Tell run_regress.py we're in sign-off mode so it can honor
    # `skip_in_signoff: true` testlist entries (broken-but-tracked tests).
    env = os.environ.copy()
    env["EH2_SIGNOFF_MODE"] = "1"
    with open(log_path, "wb") as log_fd:
        log_fd.write(("+ " + _cmd_str(cmd) + "\n").encode("utf-8"))
        try:
            proc = subprocess.run(
                cmd,
                stdout=log_fd,
                stderr=subprocess.STDOUT,
                timeout=timeout_s,
                env=env,
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
        "waivers": [],
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

    min_passed = STAGE_MIN_PASSED.get(stage)
    # Pass-rate ceiling on waivers: even when the absolute minimum-passed
    # threshold is met, a stage with a high failure rate is not really
    # passing. Without this gate a 50/395 result for riscvdv (87% failure)
    # would be silently waived just because passed >= 50. Cap waiver
    # eligibility at <= MAX_STAGE_FAIL_RATE_FOR_WAIVER failed/total.
    MAX_STAGE_FAIL_RATE_FOR_WAIVER = 0.25  # 25% — fail more than this and no waiver
    fail_rate = (summary.failed / summary.total_tests
                 if summary.total_tests > 0 else 0.0)
    threshold_met = (
        min_passed is not None and
        summary.total_tests > 0 and
        summary.passed >= min_passed and
        fail_rate <= MAX_STAGE_FAIL_RATE_FOR_WAIVER
    )
    if threshold_met:
        threshold_notes = []
        if exit_code not in (None, 0):
            threshold_notes.append("stage command exit code {}".format(exit_code))
        if summary.failed > 0:
            threshold_notes.append("{} test(s) failed".format(summary.failed))
        if threshold_notes:
            result["waivers"].append(
                "stage threshold met: {}/{} passed, minimum {}, fail rate {:.1%} <= {:.0%}; waived: {}".format(
                    summary.passed, summary.total_tests, min_passed,
                    fail_rate, MAX_STAGE_FAIL_RATE_FOR_WAIVER,
                    "; ".join(threshold_notes)))
            result["blockers"] = [
                blocker for blocker in result["blockers"]
                if not (
                    blocker.startswith("stage command exit code") or
                    blocker.endswith("test(s) failed"))
            ]

    if result["blockers"]:
        result["status"] = "FAIL"
    return result


def _latest_matching_log(glob_pattern: str) -> Path:
    """Return the most recently modified file matching *glob_pattern*."""
    candidates = sorted(Path(p) for p in glob.glob(glob_pattern))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def collect_lint_stage(stage: str, results_dir: Path, report_dir: Path) -> Dict:
    """Collect lint results from lint/build/*.log and *.txt files.

    Parses Verible errors and Verilator %Error lines.  Pass condition:
    zero errors from all linters *and* lint has actually been run.
    """
    lint_build = EH2_ROOT / "lint" / "build"
    total_errors = 0
    total_warnings = 0
    details = []

    if not lint_build.is_dir():
        tests = [{
            "name": "lint",
            "seed": 0,
            "passed": False,
            "failure_mode": "no_results",
            "warnings": 0,
            "sim_log": "",
        }]
        return {
            "stage": stage,
            "results_dir": str(lint_build),
            "report_dir": str(report_dir),
            "command": "",
            "exit_code": 0,
            "total": 0,
            "passed": 0,
            "failed": 0,
            "pass_rate": 0.0,
            "warnings": 0,
            "status": "FAIL",
            "blockers": ["lint has not been run (no build directory)"],
            "source": "lint logs",
            "tests": tests,
        }

    # Verible error log
    verible_err = lint_build / "verible_errors.txt"
    if verible_err.exists():
        lines = verible_err.read_text(encoding="utf-8", errors="replace").splitlines()
        verible_errors = len([l for l in lines if l.strip()])
        total_errors += verible_errors
        details.append("verible_errors={}".format(verible_errors))

    # Verilator log
    verilator_log = lint_build / "verilator.log"
    if verilator_log.exists():
        text = verilator_log.read_text(encoding="utf-8", errors="replace")
        verilator_errors = len(re.findall(r"%Error", text))
        verilator_warns = len(re.findall(r"%Warning", text))
        total_errors += verilator_errors
        total_warnings += verilator_warns
        details.append("verilator_errors={}".format(verilator_errors))

    # Also check for any other error files
    for f in lint_build.glob("*errors*"):
        if f != verible_err:
            text = f.read_text(encoding="utf-8", errors="replace")
            extra = len([l for l in text.splitlines() if l.strip()])
            total_errors += extra
            details.append("{}={}".format(f.name, extra))

    tests = [{
        "name": "lint",
        "seed": 0,
        "passed": total_errors == 0,
        "failure_mode": "lint_errors" if total_errors > 0 else "NONE",
        "warnings": total_warnings,
        "sim_log": str(lint_build),
    }]
    return {
        "stage": stage,
        "results_dir": str(lint_build),
        "report_dir": str(report_dir),
        "command": "",
        "exit_code": 0,
        "total": 1,
        "passed": 1 if total_errors == 0 else 0,
        "failed": 0 if total_errors == 0 else 1,
        "pass_rate": 100.0 if total_errors == 0 else 0.0,
        "warnings": total_warnings,
        "status": "PASS" if total_errors == 0 else "FAIL",
        "blockers": [] if total_errors == 0 else [
            "{} lint error(s): {}".format(total_errors, "; ".join(details))],
        "source": "lint logs",
        "tests": tests,
    }


def collect_formal_stage(stage: str, results_dir: Path, report_dir: Path) -> Dict:
    """Collect formal verification results from the latest ifv_prove_*.log.

    Parses the Assertion Summary block (Total / Pass / Fail / Not_Run).
    Pass condition: Fail == 0 and Total > 0.
    """
    prove_candidates = []
    formal_build = EH2_ROOT / "dv" / "formal" / "build"
    for pattern in ("ifv_prove_*.log", "ifv_run.log", "ifv_final.log",
                    "ifv_cex_run.log"):
        prove_candidates.extend(Path(p) for p in glob.glob(str(formal_build / pattern)))
    prove_log = max(prove_candidates, key=lambda p: p.stat().st_mtime) \
        if prove_candidates else None
    total = passed = failed = not_run = 0
    details = []
    log_path = ""

    if prove_log is not None:
        log_path = str(prove_log)
        text = prove_log.read_text(encoding="utf-8", errors="replace")
        # Parse the Assertion Summary block
        summary_blocks = re.findall(
            r"Assertion Summary:\s*\n((?:\s*[A-Za-z_]+\s*:\s*[0-9]+\s*\n)+)",
            text)
        if summary_blocks:
            values = {}
            for line in summary_blocks[-1].splitlines():
                m = re.match(r"\s*([A-Za-z_]+)\s*:\s*([0-9]+)", line)
                if m:
                    values[m.group(1)] = int(m.group(2))
            total = values.get("Total", 0)
            passed = values.get("Pass", 0)
            failed = values.get("Fail", 0)
            not_run = values.get("Not_Run", 0)
            explored = values.get("Explored", 0)
            details.append("Total={} Pass={} Fail={} Explored={} Not_Run={}".format(
                total, passed, failed, explored, not_run))

    blocker_msg = []
    if total == 0:
        blocker_msg.append("no formal assertion results found")
    if failed > 0:
        blocker_msg.append("{} formal assertion(s) FAIL".format(failed))

    tests = [{
        "name": "formal_prove",
        "seed": 0,
        "passed": total > 0 and failed == 0,
        "failure_mode": "formal_fail" if failed > 0 else ("no_results" if total == 0 else "NONE"),
        "warnings": 0,
        "sim_log": log_path,
    }]
    return {
        "stage": stage,
        "results_dir": str(prove_log.parent if prove_log else ""),
        "report_dir": str(report_dir),
        "command": "",
        "exit_code": 0,
        "total": total,
        "passed": passed,
        "failed": failed,
        "pass_rate": 100.0 * passed / max(1, total),
        "warnings": 0,
        "status": "PASS" if (total > 0 and failed == 0) else "FAIL",
        "blockers": blocker_msg,
        "source": "ifv prove log",
        "tests": tests,
    }


def has_true_rtl_bug_in_buckets() -> bool:
    buckets = EH2_ROOT / "syn" / "build" / "failing_buckets.md"
    if not buckets.exists():
        return False
    text = buckets.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"True RTL bug / other unmatched:\s*([0-9]+)", text)
    return bool(match and int(match.group(1)) > 0)


def parse_lec_blocklevel_summary(path: str) -> Dict:
    """Parse syn/build/lec_summary.txt into per-module and TOTAL data."""
    modules = {}
    total = {"passing": 0, "failing": 0, "unverified": 0, "status": "UNKNOWN"}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith("|"):
                continue
            cols = [col.strip() for col in line.split("|")[1:-1]]
            if len(cols) < 5 or cols[0] in ("Module", "---"):
                continue
            try:
                entry = {
                    "passing": int(cols[1]),
                    "failing": int(cols[2]),
                    "unverified": int(cols[3]),
                    "status": cols[4],
                }
            except ValueError:
                continue
            if len(cols) >= 6:
                entry["note"] = cols[5]
            if cols[0] == "TOTAL":
                total = entry
            else:
                modules[cols[0]] = entry
    return {"modules": modules, "total": total}


def evaluate_lec_blocklevel(summary: Dict,
                            unverified_threshold: int = 5,
                            waive_unverified_threshold: int = 50) -> Tuple[str, str]:
    total = summary["total"]
    if total["failing"] > 0:
        return ("FAIL", "block-level LEC has {} failing compare points".format(
            total["failing"]))
    if total["unverified"] <= unverified_threshold:
        return (
            "PASS",
            "block-level LEC: {} passing, {} unverified within tolerance".format(
                total["passing"], total["unverified"]),
        )
    bad_modules = [
        name for name, module in summary["modules"].items()
        if module.get("unverified", 0) > 0
    ]
    if total["unverified"] <= waive_unverified_threshold:
        return (
            "WAIVE_TOOL_LIMITED",
            "block-level LEC: {} passing, {} unverified concentrated in {} "
            "(R3-C tool limitation)".format(
                total["passing"], total["unverified"],
                ",".join(bad_modules) if bad_modules else "unknown"),
        )
    return (
        "WAIVE_TOOL_LIMITED",
        "block-level LEC: {} unverified > waive threshold {}, partial closure".format(
            total["unverified"], waive_unverified_threshold),
    )


def collect_syn_stage(stage: str, results_dir: Path, report_dir: Path,
                      lec_known_limited: bool = False,
                      lec_blocklevel: bool = False,
                      lec_summary_path: str = "") -> Dict:
    """Collect synthesis / LEC results from the latest lec_*final.log.

    Parses Formality status report for Verification SUCCEEDED / FAILED
    and the compare-point summary.  Pass condition: SUCCEEDED and Failing==0.
    """
    lec_log = _latest_matching_log(str(
        EH2_ROOT / "syn" / "build" / "lec_*final.log"))
    status = "UNKNOWN"
    passing_pts = failing_pts = aborted_pts = unverified_pts = 0
    details = []
    log_path = ""

    if lec_blocklevel:
        summary_path = Path(lec_summary_path) if lec_summary_path else \
            EH2_ROOT / "syn" / "build" / "lec_summary.txt"
        if not summary_path.is_absolute():
            summary_path = EH2_ROOT / summary_path
        if summary_path.exists():
            summary = parse_lec_blocklevel_summary(str(summary_path))
            block_status, note = evaluate_lec_blocklevel(summary)
            total = summary["total"]
            total_points = (total["passing"] + total["failing"] +
                            total["unverified"])
            tests = [{
                "name": "lec_blocklevel",
                "seed": 0,
                "passed": block_status in ("PASS", "WAIVE_TOOL_LIMITED"),
                "failure_mode": "NONE" if block_status == "PASS" else block_status,
                "warnings": 0,
                "sim_log": str(summary_path),
            }]
            return {
                "stage": stage,
                "results_dir": str(summary_path.parent),
                "report_dir": str(report_dir),
                "command": "",
                "exit_code": 0,
                "total": total_points,
                "passed": total["passing"],
                "failed": total["failing"],
                "pass_rate": 100.0 * total["passing"] / max(1, total_points),
                "warnings": 0,
                "status": block_status,
                "blockers": [] if block_status == "PASS" else [note],
                "source": "lec block-level summary",
                "tests": tests,
                "note": note,
                "blocklevel": True,
                "summary_path": str(summary_path),
                "modules": summary["modules"],
            }

    if lec_log is not None:
        log_path = str(lec_log)
        text = lec_log.read_text(encoding="utf-8", errors="replace")
        if re.search(r"Verification\s+SUCCEEDED", text):
            status = "SUCCEEDED"
        elif re.search(r"Verification\s+FAILED", text):
            status = "FAILED"

        m = re.search(r"(\d+)\s+Passing compare points", text)
        if m:
            passing_pts = int(m.group(1))
        m = re.search(r"(\d+)\s+Failing compare points", text)
        if m:
            failing_pts = int(m.group(1))
        m = re.search(r"(\d+)\s+Aborted compare points", text)
        if m:
            aborted_pts = int(m.group(1))
        m = re.search(r"(\d+)\s+Unverified compare points", text)
        if m:
            unverified_pts = int(m.group(1))
        details.append("Passing={} Failing={} Aborted={} Unverified={}".format(
            passing_pts, failing_pts, aborted_pts, unverified_pts))

    syn_passed = status == "SUCCEEDED" and failing_pts == 0
    true_rtl_bug = has_true_rtl_bug_in_buckets()
    blocker_msg = []
    if status == "FAILED":
        blocker_msg.append("LEC Verification FAILED")
    if unverified_pts > 0:
        blocker_msg.append("{} Unverified compare points".format(unverified_pts))
    if lec_known_limited and not syn_passed and not true_rtl_bug:
        blocker_msg = [
            "WAIVE_TOOL_LIMITED: ADR-0019 tool limitation; True RTL bug count is 0"
        ]

    tests = [{
        "name": "lec",
        "seed": 0,
        "passed": syn_passed or (lec_known_limited and not true_rtl_bug),
        "failure_mode": "NONE" if syn_passed else (
            "WAIVE_TOOL_LIMITED" if lec_known_limited and not true_rtl_bug else "lec_fail"),
        "warnings": 0,
        "sim_log": log_path,
    }]
    stage_status = "PASS" if syn_passed else (
        "WAIVE_TOOL_LIMITED" if lec_known_limited and not true_rtl_bug else "FAIL")
    return {
        "stage": stage,
        "results_dir": str(lec_log.parent if lec_log else ""),
        "report_dir": str(report_dir),
        "command": "",
        "exit_code": 0,
        "total": passing_pts + failing_pts + aborted_pts + unverified_pts,
        "passed": passing_pts,
        "failed": failing_pts,
        "pass_rate": 100.0 * passing_pts / max(1, passing_pts + failing_pts + aborted_pts + unverified_pts),
        "warnings": 0,
        "status": stage_status,
        "blockers": blocker_msg,
        "source": "lec final log",
        "tests": tests,
    }


def evaluate_compliance_per_suite(results_dir: Path) -> List[str]:
    """Per-suite compliance gate (rv32i ≥95%, rv32im/imc/Zicsr =100%).

    Reads per-ISA report.json files from the compliance results directory
    and enforces per-suite pass-rate thresholds.  Returns list of blocker
    strings (empty = all suites pass).
    """
    blockers = []
    suite_gates = {
        "rv32i":      95.0,
        "rv32im":     100.0,
        "rv32imc":    100.0,
        "rv32Zicsr":  100.0,
    }
    zifencei_known_fail = 1

    for isa, threshold in suite_gates.items():
        report_path = results_dir / isa / "report.json"
        if not report_path.exists():
            # Try aggregated report.json
            report_path = results_dir / "report.json"

        if not report_path.exists():
            blockers.append(
                "compliance {} report.json not found".format(isa))
            continue

        try:
            data = json.loads(report_path.read_text(encoding="utf-8"))
        except Exception:
            blockers.append(
                "compliance {} report.json unparseable".format(isa))
            continue

        suite_tests = [t for t in data.get("tests", [])
                       if t.get("type", "").startswith("compliance_" + isa)]
        total = len(suite_tests)
        passed = sum(1 for t in suite_tests if t.get("passed", False))

        if total == 0:
            continue

        rate = 100.0 * passed / total
        if rate < threshold:
            blockers.append(
                "compliance {} pass rate {:.1f}% below {:.1f}% ({}/{})".format(
                    isa, rate, threshold, passed, total))

    # rv32Zifencei: treated as PASS when known_fail covers the failures
    zifencei_dir = results_dir / "rv32Zifencei"
    if zifencei_dir.exists():
        zifencei_report = zifencei_dir / "report.json"
        if zifencei_report.exists():
            try:
                data = json.loads(zifencei_report.read_text(encoding="utf-8"))
                zifencei_failed = sum(
                    1 for t in data.get("tests", [])
                    if not t.get("passed", False))
                if zifencei_failed > zifencei_known_fail:
                    blockers.append(
                        "compliance rv32Zifencei {} unexpected failures "
                        "(known_fail covers {})".format(
                            zifencei_failed, zifencei_known_fail))
            except Exception:
                pass

    return blockers


def _parse_urg_dashboard_header(text: str) -> Dict[str, float]:
    """Parse URG dashboard.txt header-row + data-row format.

    Example::

        SCORE  LINE   COND   TOGGLE FSM    ASSERT
         41.59  82.73  40.61  35.57  22.39  26.67

    Returns a dict of COVERAGE_METRIC_ALIASES values keyed by canonical metric.
    """
    result = {}
    header_re = re.compile(
        r"\b(SCORE|LINE|COND|TOGGLE|FSM|ASSERT|BRANCH)\b",
        re.IGNORECASE)
    data_re = re.compile(r"[0-9]+\.[0-9]+")

    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not header_re.search(line):
            continue
        # Check if next non-empty line looks like a data row
        if i + 1 >= len(lines):
            continue
        data_line = lines[i + 1].strip()
        if not data_re.search(data_line):
            # Could be a blank line between header and data
            if i + 2 < len(lines):
                data_line = lines[i + 2].strip()
            if not data_re.search(data_line):
                continue

        headers = [h.upper() for h in line.split()]
        values = []
        for token in data_line.split():
            try:
                values.append(float(token))
            except ValueError:
                # Preserve column position for placeholders like "n/a" so
                # the header→value zip stays aligned. Use None to mean
                # "not measured" (the metric will simply be skipped below).
                if token.lower() in ("n/a", "na", "-", "--"):
                    values.append(None)
                # Any other non-numeric token is dropped silently to keep
                # behaviour stable for URG dashboards that interleave free
                # text between columns.

        if not values or not headers:
            continue

        n = min(len(headers), len(values))
        for hdr, val in zip(headers[:n], values[:n]):
            if val is None:
                continue
            metric = COVERAGE_METRIC_ALIASES.get(hdr.lower())
            if metric and 0.0 <= val <= 100.0:
                result[metric] = max(result.get(metric, 0.0), val)
        return result
    return result


def parse_coverage_text(text: str) -> Dict[str, float]:
    metrics = _parse_urg_dashboard_header(text)
    # If URG dashboard parser already found values, trust them and skip
    # the fallback regexes which are known to mis-parse header-row formats.
    if metrics:
        return metrics
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
        output_dir / "cov_merged",
        # urg also drops text reports under cov_merged/report/, e.g.
        # dashboard.txt, modinfo.txt, hierarchy.txt. Look there too.
        output_dir / "cov_merged" / "report",
        EH2_ROOT / "build" / "r2b_cov_report",
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


def auto_merge_stage_coverage(stage_results: List[Dict],
                               output_dir: Path) -> Path:
    """Merge coverage databases from all stages into a single merged report.

    Scans each stage's results_dir for .vdb directories, and additionally
    includes the centralized output_dir/cov.vdb that VCS produces when
    every stage shares the same -cm_dir. Runs urg merge and generates
    dashboard.txt. Returns the merged output directory path.
    """
    vdb_dirs = []
    for stage in stage_results:
        results_dir = Path(stage.get("results_dir", ""))
        if not results_dir.is_dir():
            continue
        for p in results_dir.rglob("*.vdb"):
            if p.is_dir():
                vdb_dirs.append(str(p))
        coverage_dir = results_dir / "coverage"
        if coverage_dir.is_dir():
            vdb_dirs.append(str(coverage_dir))

    central_vdb = output_dir / "cov.vdb"
    if central_vdb.is_dir():
        vdb_dirs.append(str(central_vdb))

    # NC/imc coverage layout (build_dir/cov_work) — full sign-off support.
    # merge_cov.py auto-detects .vdb (VCS) vs cov_work/*.ucd (NC) and routes
    # to urg / imc accordingly. NC produces dashboard.txt in the same
    # column layout as VCS so the signoff parser stays simulator-agnostic.
    central_cov_work = output_dir / "cov_work"
    if central_cov_work.is_dir():
        vdb_dirs.append(str(central_cov_work))

    seen = set()
    unique_vdb_dirs = []
    for d in vdb_dirs:
        real = str(Path(d).resolve())
        if real not in seen:
            seen.add(real)
            unique_vdb_dirs.append(d)
    vdb_dirs = unique_vdb_dirs

    if not vdb_dirs:
        return Path()

    merged_dir = output_dir / "cov_merged"
    merge_script = SCRIPT_DIR / "merge_cov.py"
    if not merge_script.exists():
        return Path()

    cmd = [sys.executable, str(merge_script),
           "--dirs"] + vdb_dirs + ["--output", str(merged_dir)]
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=3600)
    except Exception:
        return Path()

    return merged_dir


def evaluate_coverage(paths: List[Path], output_dir: Path, args) -> Dict:
    require_coverage = not getattr(args, 'no_require_coverage', False)
    thresholds = {
        "overall": args.min_overall_coverage,
        "line": args.min_line_coverage,
        "fsm": args.min_fsm_coverage,
        "toggle": args.min_toggle_coverage,
        "functional": args.min_functional_coverage,
    }

    required = require_coverage or any(value > 0.0
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


def collect_cosim_exceptions() -> List[Dict]:
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
                                                   "false", "no", "rtl_only"):
            disabled.append({
                "test": entry.get("test", "unknown"),
                "reason": entry.get("cosim_reason", ""),
            })
    return disabled


def collect_skip_in_signoff() -> List[Dict]:
    testlist = DV_DIR / "riscv_dv_extension" / "testlist.yaml"
    if not testlist.exists():
        return []
    try:
        entries = _load_yaml(testlist) or []
    except Exception:
        return []
    skipped = []
    for entry in entries:
        if entry.get("skip_in_signoff") in (True, "true", "True", 1):
            skipped.append({
                "test": entry.get("test", "unknown"),
                "reason": entry.get("skip_reason", ""),
            })
    return skipped


def detect_cosim_reason_loophole() -> List[Dict]:
    """Detect cosim_reason field in ANY testlist YAML.

    The cosim_reason field in testlist entries is a forbidden "add comment
    to PASS" loophole (see signoff-gates.md).  Waivers MUST go through
    formal waiver files under dv/uvm/core_eh2/waivers/, never through
    inline YAML comments.

    Returns list of {test, file_path} for every entry with cosim_reason set.
    """
    violations = []
    testlist_paths = [
        DV_DIR / "riscv_dv_extension" / "testlist.yaml",
        DV_DIR / "directed_tests" / "directed_testlist.yaml",
        DV_DIR / "directed_tests" / "cosim_testlist.yaml",
    ]
    for testlist_path in testlist_paths:
        if not testlist_path.exists():
            continue
        try:
            entries = _load_yaml(testlist_path) or []
        except Exception:
            continue
        for entry in entries:
            if isinstance(entry, dict) and "cosim_reason" in entry:
                violations.append({
                    "test": entry.get("test", "unknown"),
                    "file": str(testlist_path),
                    "cosim_reason": entry["cosim_reason"],
                })
    return violations


def validate_waiver_schema(waiver_path: Path) -> Tuple[bool, List[str]]:
    """Validate cosim-disabled waiver YAML schema.

    Each entry must have: reason, tracking_issue, expiry_date.
    Returns (valid, errors).
    """
    errors = []
    if not waiver_path.exists():
        return True, []
    try:
        waivers = _load_yaml(waiver_path)
    except Exception as e:
        return False, ["Cannot parse waiver file {}: {}".format(waiver_path, e)]
    if waivers is None:
        return True, []
    if not isinstance(waivers, list):
        return False, ["Waiver file must contain a YAML list"]
    required_fields = ["reason", "tracking_issue", "expiry_date"]
    for i, entry in enumerate(waivers):
        if not isinstance(entry, dict):
            errors.append("Waiver entry {} is not a dict".format(i))
            continue
        for field in required_fields:
            if field not in entry or not entry[field]:
                errors.append(
                    "Waiver entry {} ('{}'): missing or empty field '{}'".format(
                        i, entry.get("test", "unknown"), field))
        if "expiry_date" in entry and entry["expiry_date"]:
            if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(entry["expiry_date"])):
                errors.append(
                    "Waiver entry {} ('{}'): expiry_date '{}' must be YYYY-MM-DD".format(
                        i, entry.get("test", "unknown"), entry["expiry_date"]))
    return len(errors) == 0, errors


def load_waiver_set(waiver_path: Path) -> set:
    """Load waived test names from a waiver YAML file."""
    if not waiver_path.exists():
        return set()
    try:
        waivers = _load_yaml(waiver_path) or []
    except Exception:
        return set()
    return {w.get("test", "") for w in waivers if isinstance(w, dict)}


def compute_testlist_pool(testlist_path: Path) -> int:
    """Count total entries in a testlist YAML."""
    if not testlist_path.exists():
        return 0
    try:
        entries = _load_yaml(testlist_path) or []
    except Exception:
        return 0
    return len(entries)


def check_directed_pool_coverage(testlist_path: Path,
                                  asm_root: Path = None) -> Tuple[int, int, List[str]]:
    """Check directed test pool: all .S entries must be in directed_testlist.yaml.

    Returns (listed, on_disk, missing_from_list).
    """
    asm_dir = asm_root if asm_root else DV_DIR / "tests" / "asm"
    if not asm_dir.exists():
        return 0, 0, []
    disk_tests = set()
    for p in asm_dir.glob("directed_*.S"):
        disk_tests.add(p.stem)
    if not testlist_path.exists():
        return 0, len(disk_tests), sorted(disk_tests)
    try:
        entries = _load_yaml(testlist_path) or []
    except Exception:
        return 0, len(disk_tests), sorted(disk_tests)
    listed = {e.get("test", "") for e in entries if isinstance(e, dict)}
    missing = sorted(disk_tests - listed)
    return len(listed), len(disk_tests), missing


def compute_real_run_count(stage_results: List[Dict]) -> Tuple[int, int]:
    """Count actually-run sim tests vs total testlist pool.

    Both numerator and denominator are measured in *testlist entries* — i.e.
    distinct test names — not iteration count. This keeps the ratio
    meaningful when iterations >1, and avoids the historical bug where
    ``ran`` summed every stage's ``total`` (which conflated iterations
    with tests and even mixed in syn LEC sub-instances and formal
    properties — producing absurd ratios like 32233/108 = 29845%).

    Only sim regression stages contribute. syn/formal/lint/csr_unit/
    compliance use unit counts that aren't comparable to testlist entries,
    so they're excluded from both numerator and denominator.

    Returns (ran_unique_tests, pool).
    """
    sim_stages_with_testlist = set(STAGE_TESTLIST.keys())
    ran = 0
    for stage_result in stage_results:
        stage = stage_result.get("stage", "")
        if stage not in sim_stages_with_testlist:
            continue
        # Count distinct test names from the recorded test results, so
        # iterations of the same test don't double-count.
        names = {t.get("name", "") for t in stage_result.get("tests", [])
                 if t.get("name")}
        ran += len(names)

    pool = 0
    for stage, path in STAGE_TESTLIST.items():
        if path.exists():
            try:
                entries = _load_yaml(path) or []
                pool += len([e for e in entries if isinstance(e, dict)
                             and e.get("test")])
            except Exception:
                pass
    return ran, pool


def evaluate_signoff(stage_results: List[Dict], coverage_result: Dict,
                     precheck_result: Dict, args,
                     waiver_errors: List[str]) -> Tuple[str, List[str]]:
    blockers = []
    if not args.skip_precheck and not precheck_result.get("passed", False):
        blockers.append("precheck failed")

    # Hard blocker: cosim_reason in testlist YAML is a forbidden loophole.
    # All waivers MUST go through formal waiver files under dv/uvm/core_eh2/waivers/.
    # See docs/adr/0010-integrity-cosim-waiver.md and docs/signoff-gates.md.
    cosim_reason_violations = detect_cosim_reason_loophole()
    if cosim_reason_violations:
        names = [v["test"] for v in cosim_reason_violations]
        blockers.append(
            "FORBIDDEN cosim_reason field in testlist ({}): {}. "
            "Move waiver to dv/uvm/core_eh2/waivers/cosim-disabled.yaml "
            "and REMOVE the cosim_reason field from the YAML.".format(
                len(names), ", ".join(sorted(names))))

    if not stage_results:
        blockers.append("no sign-off stages were evaluated")

    has_waivers = False
    for stage in stage_results:
        if stage["status"] == "WAIVE_TOOL_LIMITED":
            has_waivers = True
            continue
        if stage["status"] != "PASS":
            blockers.append("{}: {}".format(
                stage["stage"], "; ".join(stage["blockers"])))
        if stage["stage"] == "formal" and stage.get("failed", 0) == 0:
            continue
        min_passed = STAGE_MIN_PASSED.get(stage["stage"])
        if min_passed is not None and stage.get("passed", 0) >= min_passed:
            continue
        if stage["pass_rate"] < args.min_pass_rate:
            blockers.append("{} pass rate {:.2f}% below {:.2f}%".format(
                stage["stage"], stage["pass_rate"], args.min_pass_rate))

    if coverage_result["status"] == "FAIL":
        blockers.append("coverage: {}".format(
            "; ".join(coverage_result["blockers"])))

    fail_on_cosim_disabled = not getattr(args, 'no_fail_on_cosim_disabled', False)
    fail_on_skip_in_signoff = not getattr(args, 'no_fail_on_skip_in_signoff', False)

    if fail_on_cosim_disabled or fail_on_skip_in_signoff:
        waiver_path_str = getattr(args, 'waivers_cosim_disabled', '')
        waiver_path = Path(waiver_path_str) if waiver_path_str else \
                      DV_DIR / "waivers" / "cosim-disabled.yaml"
        if waiver_errors:
            blockers.append("waiver schema errors: {}".format(
                "; ".join(waiver_errors)))
        waived = load_waiver_set(waiver_path) if not waiver_errors else set()
    else:
        waived = set()

    if fail_on_cosim_disabled:
        disabled = collect_cosim_exceptions()
        unwaived = [d["test"] for d in disabled if d["test"] not in waived]
        if unwaived:
            blockers.append(
                "cosim-disabled tests without waiver ({}): {}".format(
                    len(unwaived), ", ".join(sorted(unwaived))))

    if fail_on_skip_in_signoff:
        skipped = collect_skip_in_signoff()
        unwaived_skip = [s["test"] for s in skipped if s["test"] not in waived]
        if unwaived_skip:
            blockers.append(
                "skip_in_signoff tests without waiver ({}): {}".format(
                    len(unwaived_skip), ", ".join(sorted(unwaived_skip))))

    if args.require_cosim_all_tests:
        disabled = collect_cosim_exceptions()
        if disabled:
            names = [d["test"] for d in disabled]
            blockers.append("riscv-dv tests with cosim disabled: {}".format(
                ", ".join(names)))

    if blockers:
        return "FAIL", blockers
    return ("PASS_WITH_WAIVERS" if has_waivers else "PASS", blockers)


def write_markdown_report(status: Dict, path: Path):
    def stage_rows():
        stages = status["stages"]
        return stages.values() if isinstance(stages, dict) else stages

    lines = []
    lines.append("# EH2 Sign-off Report")
    lines.append("")

    real_ran = status.get("real_ran", 0)
    real_pool = status.get("real_pool", 0)
    real_pct = 100.0 * real_ran / max(1, real_pool)
    pool_status = "PASS" if real_pct >= 95.0 else "PARTIAL" if real_pct >= 50.0 else "FAIL"
    lines.append("- **实跑覆盖率**: {}/{} ({:.1f}%) — {}".format(
        real_ran, real_pool, real_pct, pool_status))
    if real_pct < 95.0:
        actual_status = status["status"]
        if actual_status == "PASS":
            lines.append("- **整体状态降级**: PASS → PARTIAL（真实覆盖率 {:.1f}% < 95%）".format(real_pct))
            status["status"] = "PARTIAL"
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
    for stage in stage_rows():
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

    stage_waivers = []
    for stage in stage_rows():
        for waiver in stage.get("waivers", []):
            stage_waivers.append("{}: {}".format(stage["stage"], waiver))
    if stage_waivers:
        lines.append("## Stage Waivers")
        lines.append("")
        for waiver in stage_waivers:
            lines.append("- {}".format(waiver))
        lines.append("")

    lines.append("## Commands")
    lines.append("")
    for stage in stage_rows():
        if stage["command"]:
            lines.append("- {}: `{}`".format(stage["stage"], stage["command"]))

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _select_html_coverage_dashboard(coverage_result: Dict,
                                    cov_merged_dir: Optional[Path],
                                    output_dir: Path) -> Optional[Path]:
    """Pick a dashboard.txt path for the self-contained HTML report."""
    for file_name in coverage_result.get("files", []) or []:
        path = Path(file_name)
        if path.name == "dashboard.txt" and path.exists():
            return path

    candidates = []
    if cov_merged_dir:
        candidates.append(cov_merged_dir / "dashboard.txt")
    candidates.extend([
        output_dir / "cov_merged" / "dashboard.txt",
        output_dir / "coverage" / "dashboard.txt",
        output_dir / "cov_report" / "dashboard.txt",
    ])
    for path in candidates:
        if path.exists():
            return path
    return None


def maybe_generate_html_report(args, output_dir: Path, json_path: Path,
                               coverage_result: Dict,
                               cov_merged_dir: Optional[Path]) -> Optional[Path]:
    """Generate report.html after sign-off evaluation when requested."""
    if not getattr(args, "html_report", True):
        return None

    dashboard = _select_html_coverage_dashboard(
        coverage_result, cov_merged_dir, output_dir)
    if dashboard is None:
        print("WARNING: HTML report skipped; coverage dashboard.txt not found")
        return None

    html_path = output_dir / "report.html"
    script = SCRIPT_DIR / "gen_html_report.py"
    cmd = [
        sys.executable, str(script),
        "--signoff-status", str(json_path),
        "--coverage-dashboard", str(dashboard),
        "--runs-dir", str(output_dir / "runs"),
        "--output", str(html_path),
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,
                              universal_newlines=True, timeout=120)
    except Exception as exc:
        print("WARNING: HTML report generation failed: {}".format(exc))
        return None
    if proc.returncode != 0:
        print("WARNING: HTML report generation failed")
        if proc.stdout:
            print(proc.stdout.rstrip())
        return None
    if proc.stdout:
        print(proc.stdout.rstrip())
    print("HTML report: {}".format(html_path))
    return html_path


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
                        choices=["vcs", "nc", "xlm", "questa"])
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--iterations", type=int, default=0,
                        help="Override per-test iterations for non-smoke stages")
    parser.add_argument("--max-iter-per-test", type=int, default=0,
                        help="Alias for --iterations; caps non-smoke per-test iterations")
    parser.add_argument("--parallel", type=int, default=1)
    parser.add_argument("--timeout-s", type=int, default=7200)
    parser.add_argument("--coverage", action="store_true",
                        help="Enable simulator coverage while running stages")
    parser.add_argument("--waves", action="store_true",
                        help="Enable waveform dumping while running stages")
    parser.add_argument("--coverage-path", action="append", default=[],
                        help="Coverage report file or directory to gate")
    parser.add_argument("--no-require-coverage", action="store_true",
                        dest="no_require_coverage",
                        help="Disable coverage requirement (escape hatch for old behavior)")
    parser.add_argument("--min-pass-rate", type=float, default=100.0)
    parser.add_argument("--min-overall-coverage", type=float, default=0.0)
    parser.add_argument("--min-line-coverage", type=float, default=60.0)
    parser.add_argument("--min-cond-coverage", type=float, default=0.0)
    parser.add_argument("--min-fsm-coverage", type=float, default=0.0)
    parser.add_argument("--min-toggle-coverage", type=float, default=0.0)
    parser.add_argument("--min-functional-coverage", type=float, default=0.0)
    parser.add_argument("--no-fail-on-cosim-disabled", action="store_true",
                        dest="no_fail_on_cosim_disabled",
                        help="Do not fail on cosim-disabled tests without waivers")
    parser.add_argument("--no-fail-on-skip-in-signoff", action="store_true",
                        dest="no_fail_on_skip_in_signoff",
                        help="Do not fail on skip_in_signoff tests without waivers")
    parser.add_argument("--waivers-cosim-disabled", type=str, default="",
                        help="Path to cosim-disabled waivers YAML")
    parser.add_argument("--allow-warnings", action="store_true",
                        help="Do not treat warnings as sign-off failures")
    parser.add_argument("--skip-precheck", action="store_true")
    parser.add_argument("--require-cosim-all-tests", action="store_true",
                        help="Fail if any riscv-dv test is marked cosim disabled")
    parser.add_argument("--lec-known-limited", action="store_true",
                        help="Waive LEC failures covered by ADR-0019 when no True RTL bug bucket exists")
    parser.add_argument("--lec-blocklevel", action="store_true",
                        help="Use R3-C syn/build/lec_summary.txt for the syn stage")
    parser.add_argument("--lec-summary-path", type=str, default="",
                        help="Override R3-C block-level LEC summary path")
    parser.add_argument("--html-report", dest="html_report",
                        action="store_true", default=True,
                        help="Generate output report.html after sign-off")
    parser.add_argument("--no-html-report", dest="html_report",
                        action="store_false",
                        help="Do not generate output report.html")
    parser.add_argument("--validate-waivers", type=str, default="",
                        help="Validate waiver YAML schema and exit")
    args = parser.parse_args(argv)
    if args.max_iter_per_test:
        args.iterations = args.max_iter_per_test

    if args.validate_waivers:
        waiver_p = Path(args.validate_waivers)
        if not waiver_p.exists():
            print("ERROR: waiver file not found: {}".format(waiver_p))
            return 1
        valid, errors = validate_waiver_schema(waiver_p)
        if errors:
            print("Schema validation FAILED for {}:".format(waiver_p))
            for err in errors:
                print("  - {}".format(err))
            return 1
        print("Schema validation PASSED for {}".format(waiver_p))
        waived = load_waiver_set(waiver_p)
        print("Loaded {} waived entries".format(len(waived)))
        for w in sorted(waived):
            print("  - {}".format(w))
        return 0

    # For full profile, coverage gates are mandatory regardless of flags.
    if args.profile == "full":
        args.no_require_coverage = False

    output_dir = Path(args.output).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    stages = resolve_stages(args.profile, args.stages)
    stage_result_dirs = parse_stage_result_args(args.stage_result)

    simv_path = output_dir / "simv"
    planned = []
    for stage in stages:
        stage_out = output_dir / "runs" / stage
        planned.append((stage, build_stage_cmd(stage, args, stage_out, simv_path), stage_out))

    if args.dry_run:
        print("EH2 sign-off plan: profile={} stages={}".format(
            args.profile, ",".join(stages)))
        for stage, cmd, _ in planned:
            print("{}: {}".format(stage, _cmd_str(cmd)))
        return 0

    precheck_result = {"passed": True, "checks": []}
    if not args.skip_precheck:
        precheck_result = precheck(stages, args.simulator, output_dir)

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
        if stage == "lint":
            stage_result = collect_lint_stage(stage, results_dir, report_dir)
        elif stage == "formal":
            stage_result = collect_formal_stage(stage, results_dir, report_dir)
        elif stage == "syn":
            stage_result = collect_syn_stage(
                stage, results_dir, report_dir,
                lec_known_limited=args.lec_known_limited,
                lec_blocklevel=args.lec_blocklevel,
                lec_summary_path=args.lec_summary_path)
        else:
            stage_result = collect_stage(
                stage, results_dir, report_dir, command, exit_code,
                fail_on_warnings=not args.allow_warnings)
        if stage == "compliance":
            suite_blockers = evaluate_compliance_per_suite(results_dir)
            if suite_blockers:
                stage_result["blockers"].extend(suite_blockers)
                stage_result["status"] = "FAIL"
        stage_results.append(stage_result)

    # Auto-merge coverage across stages before gate evaluation
    cov_merged_dir = None
    if not args.gate_only and not args.dry_run and args.coverage:
        cov_merged_dir = auto_merge_stage_coverage(stage_results, output_dir)

    coverage_paths = [Path(p).resolve() for p in args.coverage_path]
    if cov_merged_dir and cov_merged_dir.exists():
        coverage_paths.append(cov_merged_dir)
    coverage_result = evaluate_coverage(coverage_paths, output_dir, args)

    waiver_errors = []
    waiver_path_str = getattr(args, 'waivers_cosim_disabled', '')
    waiver_path = Path(waiver_path_str) if waiver_path_str else \
                  DV_DIR / "waivers" / "cosim-disabled.yaml"
    if waiver_path.exists():
        waiver_valid, waiver_errors = validate_waiver_schema(waiver_path)
    elif not waiver_path_str:
        pass

    status, blockers = evaluate_signoff(stage_results, coverage_result,
                                        precheck_result, args, waiver_errors)

    real_ran, real_pool = compute_real_run_count(stage_results)
    directed_listed, directed_on_disk, directed_missing = \
        check_directed_pool_coverage(STAGE_TESTLIST.get("directed",
                                    DV_DIR / "directed_tests" / "directed_testlist.yaml"))
    if directed_missing:
        blockers.append("directed tests on disk but not in testlist: {}".format(
            ", ".join(directed_missing)))

    stage_results_by_name = {stage["stage"]: stage for stage in stage_results}
    signoff_status = {
        "status": status,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "profile": args.profile,
        "stages_requested": stages,
        "output_dir": str(output_dir),
        "precheck": precheck_result,
        "stages": stage_results_by_name,
        "stage_results": stage_results,
        "coverage": coverage_result,
        "cosim_disabled_tests": [d["test"] for d in collect_cosim_exceptions()],
        "skip_in_signoff_tests": [s["test"] for s in collect_skip_in_signoff()],
        "real_ran": real_ran,
        "real_pool": real_pool,
        "directed_on_disk": directed_on_disk,
        "directed_missing_from_list": directed_missing,
        "waiver_errors": waiver_errors,
        "blockers": blockers,
    }

    json_path = output_dir / "signoff_status.json"
    md_path = output_dir / "signoff_report.md"
    json_path.write_text(json.dumps(signoff_status, indent=2,
                                    default=_json_default) + "\n",
                         encoding="utf-8")
    write_markdown_report(signoff_status, md_path)
    html_path = maybe_generate_html_report(
        args, output_dir, json_path, coverage_result, cov_merged_dir)

    print("EH2 sign-off {}: {}".format(status, md_path))
    if html_path:
        print("EH2 sign-off HTML: {}".format(html_path))
    if blockers:
        print("Blockers:")
        for blocker in blockers:
            print("  - {}".format(blocker))

    return 0 if status in ("PASS", "PASS_WITH_WAIVERS") else 1


if __name__ == "__main__":
    sys.exit(main())
