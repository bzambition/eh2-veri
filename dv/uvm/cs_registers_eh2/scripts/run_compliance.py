#!/usr/bin/env python3
"""
EH2 CSR Unit Compliance Runner
Runs 4 tests x 5 seeds, collects results into report.json.
"""
import json
import os
import subprocess
import sys
import time

CSR_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
OUT_DIR = os.path.join(CSR_DIR, "out")

TESTS = [
    "cs_registers_test",
    "cs_registers_access_matrix_test",
    "cs_registers_illegal_test",
    "cs_registers_hazard_test",
]
SEEDS = [1, 2, 3, 4, 5]


def run_one(test_name, seed, signoff_out):
    """Run one simulation. Returns (passed, log_path)."""
    log_name = "{}_seed{}.log".format(test_name, seed)
    log_path = os.path.join(OUT_DIR, log_name)

    cmd = [
        "make", "-C", CSR_DIR, "sim",
        "TEST=" + test_name,
        "SEED=" + str(seed),
    ]

    print("  [{} seed={}] ".format(test_name, seed), end="", flush=True)

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=600,
            cwd=CSR_DIR,
        )
    except subprocess.TimeoutExpired:
        print("TIMEOUT")
        return False, log_path

    # Check log for pass/fail (mimics signoff check_uvm_log logic)
    passed = True
    failure_mode = ""
    if os.path.exists(log_path):
        with open(log_path, "r") as f:
            content = f.read()
        if "TEST PASSED" in content:
            passed = True
        elif "TEST FAILED" in content:
            passed = False
            failure_mode = "test_failed"
        elif "UVM_FATAL" in content:
            # Only count real UVM_FATAL lines, not summary lines with count 0
            has_real_fatal = False
            for line in content.splitlines():
                if line.startswith("UVM_FATAL") and "UVM_FATAL :" not in line:
                    has_real_fatal = True
                    break
            if has_real_fatal:
                passed = False
                failure_mode = "uvm_fatal"
        elif "UVM_ERROR" in content and "UVM_ERROR :    0" not in content:
            passed = False
            failure_mode = "uvm_error"

    if result.returncode != 0:
        passed = False
        if not failure_mode:
            failure_mode = "sim_exit_" + str(result.returncode)

    status = "PASS" if passed else "FAIL"
    if failure_mode:
        status += " (" + failure_mode + ")"
    print(status)

    return passed, log_path, failure_mode


def main():
    signoff_out = os.environ.get("SIGNOFF_OUT", os.path.join(CSR_DIR, "out"))
    if not os.path.isdir(signoff_out):
        os.makedirs(signoff_out)

    print("=" * 60)
    print("EH2 CSR Unit Signoff: {} tests x {} seeds = {} simulations".format(
        len(TESTS), len(SEEDS), len(TESTS) * len(SEEDS)))
    print("=" * 60)

    results = []
    total = len(TESTS) * len(SEEDS)
    passed_count = 0
    t_start = time.time()

    for seed in SEEDS:
        for test in TESTS:
            ok, log_path, failure_mode = run_one(test, seed, signoff_out)
            results.append({
                "name": test,
                "seed": seed,
                "type": "csr_unit",
                "passed": ok,
                "failure_mode": failure_mode,
                "sim_log": log_path,
                "uvm_log": "",
                "trace": "",
                "assembly": "",
                "binary": "",
                "coverage": "",
                "uvm_errors": 0 if ok else 1,
                "uvm_warnings": 0,
                "instructions": 0,
                "cycles": 0,
                "ipc": 0.0,
                "gen_time_sec": 0.0,
                "compile_time_sec": 0.0,
                "sim_time_sec": 0.0,
            })
            if ok:
                passed_count += 1

    elapsed = time.time() - t_start
    report = {
        "total_time_sec": elapsed,
        "tests": results,
    }

    report_path = os.path.join(signoff_out, "report.json")
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    print("\nSummary: {}/{} PASS ({:.1f}s)".format(passed_count, total, elapsed))
    print("Report: {}".format(report_path))

    return 0 if passed_count == total else 1


if __name__ == "__main__":
    sys.exit(main())
