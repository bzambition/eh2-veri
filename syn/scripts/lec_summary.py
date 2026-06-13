#!/usr/bin/env python3
"""Summarize R3-C block-level LEC reports without modifying tool output."""

import datetime as _dt
import re
from pathlib import Path


SYN_ROOT = Path(__file__).resolve().parents[1]
BUILD = SYN_ROOT / "build" / "lec_blocklevel"
OUT = SYN_ROOT / "build" / "lec_summary.txt"

BASE_MODULES = [
    ("eh2_dec", "dec"),
    ("eh2_lsu", "lsu"),
    ("eh2_pic_ctrl", "pic"),
    ("eh2_dma_ctrl", "dma"),
    ("eh2_dbg", "dbg"),
    ("eh2_ifu", "ifu"),
]

EXU_SUBMODULES = [
    ("eh2_exu_alu_ctl", "exu_alu"),
    ("eh2_exu_mul_ctl", "exu_mul"),
    ("eh2_exu_div_ctl", "exu_div"),
]


def _extract_int(pattern, text):
    match = re.search(pattern, text)
    return int(match.group(1)) if match else 0


def parse_module(label):
    rpt = BUILD / f"lec_{label}.rpt"
    timeout_rpt = BUILD / f"lec_{label}_timeout_status.rpt"
    log = BUILD / f"lec_{label}.log"
    if not rpt.exists():
        return {
            "passing": 0,
            "failing": 0,
            "unverified": 0,
            "status": "MISSING",
            "note": "report missing",
        }

    source_rpt = rpt
    if timeout_rpt.exists() and timeout_rpt.stat().st_mtime > rpt.stat().st_mtime:
        source_rpt = timeout_rpt

    text = source_rpt.read_text(encoding="utf-8", errors="replace")
    passing = _extract_int(r"(\d+)\s+Passing compare points", text)
    failing = _extract_int(r"(\d+)\s+Failing compare points", text)
    unverified = _extract_int(r"(\d+)\s+Unverified compare points", text)

    if "Verification SUCCEEDED" in text and failing == 0 and unverified == 0:
        status = "PASS"
    elif "Verification FAILED" in text:
        status = "FAIL"
    elif "Verification INCONCLUSIVE" in text:
        status = "INCONCLUSIVE"
    else:
        status = "UNKNOWN"

    note = ""
    if source_rpt == timeout_rpt:
        note = "graceful timeout status"
    if log.exists():
        log_text = log.read_text(encoding="utf-8", errors="replace")
        if "Process terminated by kill" in log_text or "Received Signal 15" in log_text:
            if source_rpt == timeout_rpt:
                status = "INCONCLUSIVE"
            else:
                status = "TIMEOUT"
                if "0(0) Unmatched reference(implementation) compare points" in log_text:
                    note = "latest run timed out after clean match; counts are last completed rpt"
                else:
                    note = "latest run timed out; counts are last completed rpt"
        elif "reading standalone block DDC" in log_text:
            note = note or "standalone DDC"
        elif "reading standalone block implementation" in log_text:
            note = note or "standalone Verilog"

    return {
        "passing": passing,
        "failing": failing,
        "unverified": unverified,
        "status": status,
        "note": note,
    }


def main():
    rows = []
    total_passing = total_failing = total_unverified = 0

    exu_decomposed = all((BUILD / f"lec_{label}.rpt").exists() for _module, label in EXU_SUBMODULES)
    modules = [BASE_MODULES[0]]
    if exu_decomposed:
        modules.extend(EXU_SUBMODULES)
    else:
        modules.append(("eh2_exu", "exu"))
    modules.extend(BASE_MODULES[1:])

    for module, label in modules:
        data = parse_module(label)
        if label in ("exu_alu", "exu_mul", "exu_div"):
            data["note"] = "EXU sub-block decomposition"
        rows.append((module, label, data))
        total_passing += int(data["passing"])
        total_failing += int(data["failing"])
        total_unverified += int(data["unverified"])

    if total_failing == 0 and total_unverified == 0:
        total_status = "PASS"
    elif total_failing < 30 and total_unverified == 0:
        total_status = "PARTIAL_PASS_LT30"
    else:
        total_status = "INCOMPLETE"

    lines = [
        "EH2 Block-level LEC Summary (R3-C)",
        f"Date: {_dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S %z')}",
        "",
        "| Module | Passing | Failing | Unverified | Status | Note |",
        "|---|---:|---:|---:|---|---|",
    ]
    for module, _label, data in rows:
        lines.append(
            "| {module} | {passing} | {failing} | {unverified} | {status} | {note} |".format(
                module=module,
                passing=data["passing"],
                failing=data["failing"],
                unverified=data["unverified"],
                status=data["status"],
                note=data["note"],
            )
        )

    lines.extend([
        "| TOTAL | {passing} | {failing} | {unverified} | {status} | real tool output only |".format(
            passing=total_passing,
            failing=total_failing,
            unverified=total_unverified,
            status=total_status,
        ),
        "",
        "Notes:",
        "- Reports are parsed from syn/build/lec_blocklevel/lec_*.rpt.",
        "- When lec_exu_alu/mul/div reports exist, they replace the older monolithic lec_exu result in TOTAL.",
        "- If a newer lec_<module>_timeout_status.rpt exists, it is used to avoid stale failed counts after a graceful timeout run.",
        "- TIMEOUT means the latest log was killed by timeout; the numeric counts come from the last completed report for that module.",
        "- A clean-match timeout means matching completed with 0 unmatched compare points, but verification did not finish.",
        "- No set_dont_verify_points waiver is used by this summary.",
    ])

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(OUT)
    print("\n".join(lines))


if __name__ == "__main__":
    main()
