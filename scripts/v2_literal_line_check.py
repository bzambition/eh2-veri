#!/usr/bin/env python3
"""Audit literalinclude line coverage for the Chinese Sphinx manual.

``v2_source_explain_check.py`` proves that every source asset is mentioned, has
at least one source snippet, and has paragraph-explanation text nearby. This
checker is stricter: it measures how many source lines are actually covered by
``.. literalinclude::`` ranges.

Default mode is a baseline audit and exits 0. Use ``--strict`` when a selected
asset set must meet ``--min-percent``. Use ``--focus`` repeatedly to gate a
small batch of critical long files before the whole tree is ready.
"""

import argparse
import re
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


REPO = Path(__file__).resolve().parents[1]
DOC_ROOT = REPO / "docs" / "sphinx_cn" / "source"
UPSTREAM_RTL = Path("/home/host/Cores-VeeR-EH2/design")

SOURCE_SUFFIXES = {
    ".S",
    ".cc",
    ".ccf",
    ".cfg",
    ".f",
    ".h",
    ".mk",
    ".py",
    ".sby",
    ".sh",
    ".sv",
    ".svh",
    ".tcl",
    ".v",
    ".vh",
    ".yaml",
    ".yml",
}

SOURCE_FILENAMES = {
    "Makefile",
    "env.mk",
    "env.sh",
    "lint.yml",
}

SKIP_DIR_NAMES = {
    ".formalrun",
    ".git",
    "__pycache__",
    "INCA_libs",
    "build",
    "hex",
}


class Asset:
    def __init__(self, area: str, path: Path, label: str) -> None:
        self.area = area
        self.path = path
        self.label = label


class LiteralHit:
    def __init__(self, start: int, end: int, page: str) -> None:
        self.start = start
        self.end = end
        self.page = page


def should_skip(path: Path) -> bool:
    return any(part in SKIP_DIR_NAMES for part in path.parts)


def is_source_file(path: Path) -> bool:
    return path.name in SOURCE_FILENAMES or path.suffix in SOURCE_SUFFIXES


def line_count(path: Path) -> int:
    return sum(1 for _ in path.open(encoding="utf-8", errors="ignore"))


def collect_under(area: str, root: Path, label_prefix: str = "") -> List[Asset]:
    assets: List[Asset] = []
    if not root.exists():
        return assets
    for path in sorted(root.rglob("*")):
        if not path.is_file() or should_skip(path) or not is_source_file(path):
            continue
        if label_prefix:
            label = f"{label_prefix}/{path.relative_to(root).as_posix()}"
        else:
            label = path.relative_to(REPO).as_posix()
        assets.append(Asset(area, path.resolve(), label))
    return assets


def collect_assets() -> List[Asset]:
    assets: List[Asset] = []
    assets.extend(collect_under("upstream_rtl", UPSTREAM_RTL, "Cores-VeeR-EH2/design"))
    for area, rel in (
        ("dv_cosim", "dv/cosim"),
        ("uvm_core", "dv/uvm/core_eh2"),
        ("uvm_csr", "dv/uvm/cs_registers_eh2"),
        ("uvm_compliance", "dv/uvm/riscv_compliance"),
        ("formal", "dv/formal"),
        ("synthesis", "syn"),
        ("lint", "lint"),
        ("repo_rtl", "rtl"),
        ("top_scripts", "scripts"),
        ("asm_tests", "tests"),
    ):
        assets.extend(collect_under(area, REPO / rel))

    for rel in ("Makefile", "env.mk", "env.sh", ".github/workflows/lint.yml"):
        path = (REPO / rel).resolve()
        if path.exists():
            assets.append(Asset("top_level", path, rel))
    dedup = {asset.path: asset for asset in assets}
    return sorted(dedup.values(), key=lambda asset: asset.label)


def parse_lines_option(value: str, total: int) -> List[Tuple[int, int]]:
    ranges: List[Tuple[int, int]] = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start_s, end_s = part.split("-", 1)
            start = int(start_s.strip())
            end = int(end_s.strip())
        else:
            start = end = int(part)
        start = max(1, start)
        end = min(total, end)
        if start <= end:
            ranges.append((start, end))
    return ranges


def collect_literal_hits(assets: Iterable[Asset]) -> Dict[Path, List[LiteralHit]]:
    by_path = {asset.path: asset for asset in assets}
    hits: Dict[Path, List[LiteralHit]] = {path: [] for path in by_path}
    include_re = re.compile(r"^\.\. literalinclude::\s+(.+?)\s*$")
    lines_re = re.compile(r"^\s+:lines:\s+(.+?)\s*$")

    for rst in sorted(DOC_ROOT.rglob("*.rst")):
        page = rst.relative_to(DOC_ROOT).as_posix()
        text = rst.read_text(encoding="utf-8").splitlines()
        idx = 0
        while idx < len(text):
            match = include_re.match(text[idx])
            if not match:
                idx += 1
                continue

            include_path = match.group(1).strip()
            target = (rst.parent / include_path).resolve()
            option_lines: List[str] = []
            idx += 1
            while idx < len(text) and (not text[idx].strip() or text[idx].startswith("   ")):
                option_lines.append(text[idx])
                idx += 1

            if target not in by_path:
                continue

            total = line_count(target)
            selected: List[Tuple[int, int]] = [(1, total)]
            for option in option_lines:
                lines_match = lines_re.match(option)
                if lines_match:
                    selected = parse_lines_option(lines_match.group(1), total)
                    break
            for start, end in selected:
                hits[target].append(LiteralHit(start, end, page))
    return hits


def merge_ranges(hits: Sequence[LiteralHit], total: int) -> Tuple[int, List[Tuple[int, int]]]:
    ranges = sorted((max(1, hit.start), min(total, hit.end)) for hit in hits if hit.start <= hit.end)
    merged: List[List[int]] = []
    for start, end in ranges:
        if not merged or start > merged[-1][1] + 1:
            merged.append([start, end])
        else:
            merged[-1][1] = max(merged[-1][1], end)
    frozen = [(start, end) for start, end in merged]
    covered = sum(end - start + 1 for start, end in frozen)
    return covered, frozen


def matches_focus(asset: Asset, focus: Sequence[str]) -> bool:
    if not focus:
        return True
    return any(pattern in asset.label or pattern in asset.path.as_posix() for pattern in focus)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--focus", action="append", default=[], help="substring of asset label/path to include")
    parser.add_argument("--min-percent", type=float, default=100.0, help="minimum literal line coverage")
    parser.add_argument("--strict", action="store_true", help="exit non-zero when selected assets are below threshold")
    parser.add_argument("--max-report", type=int, default=40, help="maximum partial/no-literal rows to print")
    args = parser.parse_args()

    assets = [asset for asset in collect_assets() if matches_focus(asset, args.focus)]
    hits = collect_literal_hits(assets)
    rows = []
    full = partial = no_literal = 0
    for asset in assets:
        total = line_count(asset.path)
        covered, merged = merge_ranges(hits.get(asset.path, []), total)
        percent = 100.0 if total == 0 else (covered * 100.0 / total)
        pages = sorted({hit.page for hit in hits.get(asset.path, [])})
        rows.append((percent, covered, total, asset, merged, pages))
        if covered == 0:
            no_literal += 1
        elif covered >= total:
            full += 1
        else:
            partial += 1

    print("=== v2 literalinclude line coverage audit ===")
    print(f"doc_root: {DOC_ROOT}")
    print(f"asset_total: {len(assets)}")
    print(f"full_literal_line_coverage: {full}")
    print(f"partial_literal_line_coverage: {partial}")
    print(f"no_literalinclude: {no_literal}")
    print(f"min_percent: {args.min_percent:.2f}")

    failing = [row for row in rows if row[0] < args.min_percent]
    if failing:
        print("---")
        print(f"first_assets_below_threshold (limit {args.max_report})")
        for percent, covered, total, asset, merged, pages in sorted(failing, key=lambda row: (row[0], row[3].label))[:args.max_report]:
            page_text = ",".join(pages[:3]) if pages else "-"
            range_text = ",".join(f"{start}-{end}" for start, end in merged[:4]) if merged else "-"
            print(
                f"{asset.area}: {asset.label} "
                f"[{covered}/{total} lines, {percent:.2f}%, pages={page_text}, ranges={range_text}]"
            )

    if args.strict and failing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
