#!/usr/bin/env python3
"""Audit Sphinx coverage for source-level paragraph explanations.

The v2 documentation goal is stricter than "a file name appears somewhere".
For every relevant RTL, UVM, script, config, formal, lint and synthesis asset,
the Chinese Sphinx manual should eventually provide three levels of evidence:

* reference: the source file path or basename is mentioned in a page;
* snippet: the page includes a literalinclude or code-block caption for it;
* explanation: the same page contains a paragraph-level explanation marker.

Default mode is an audit baseline and exits 0. Use ``--strict`` to turn any
missing snippet/explanation into a failing gate once the backlog is cleared.
"""

import argparse
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple


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

EXPLAIN_MARKERS = (
    "逐段精读",
    "逐段解释",
    "逐段源码解读",
    "逐行讲解",
    "源码逐段",
    "源码解读",
    "源码精读",
    "文件全貌",
    "为什么这么写",
)

SNIPPET_MARKERS = (
    "literalinclude::",
    ":caption:",
)


class Asset:
    def __init__(self, area, path, label):
        # type: (str, Path, str) -> None
        self.area = area
        self.path = path
        self.label = label

    @property
    def basename(self):
        # type: () -> str
        return self.path.name

    def __hash__(self):
        # type: () -> int
        return hash(self.label)

    def __eq__(self, other):
        # type: (object) -> bool
        return isinstance(other, Asset) and self.label == other.label


class Hit:
    def __init__(self):
        # type: () -> None
        self.referenced = False
        self.snippet = False
        self.explained = False
        self.pages = set()  # type: Set[str]


def should_skip(path):
    # type: (Path) -> bool
    return any(part in SKIP_DIR_NAMES for part in path.parts)


def is_source_file(path):
    # type: (Path) -> bool
    return path.name in SOURCE_FILENAMES or path.suffix in SOURCE_SUFFIXES


def collect_under(area, root, label_prefix=None):
    # type: (str, Path, str) -> List[Asset]
    assets = []  # type: List[Asset]
    if not root.exists():
        return assets
    for path in sorted(root.rglob("*")):
        if not path.is_file() or should_skip(path) or not is_source_file(path):
            continue
        if label_prefix:
            label = f"{label_prefix}/{path.relative_to(root).as_posix()}"
        else:
            label = path.relative_to(REPO).as_posix()
        assets.append(Asset(area=area, path=path, label=label))
    return assets


def collect_assets():
    # type: () -> List[Asset]
    assets = []  # type: List[Asset]
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
        path = REPO / rel
        if path.exists():
            assets.append(Asset(area="top_level", path=path, label=rel))
    return sorted({asset.label: asset for asset in assets}.values(), key=lambda a: a.label)


def load_docs():
    # type: () -> Dict[str, str]
    docs = {}  # type: Dict[str, str]
    for path in sorted(DOC_ROOT.rglob("*.rst")):
        docs[path.relative_to(DOC_ROOT).as_posix()] = path.read_text(encoding="utf-8")
    return docs


def page_mentions_asset(page_text, asset):
    # type: (str, Asset) -> bool
    return asset.label in page_text or asset.basename in page_text


def page_has_snippet_for_asset(page_text, asset):
    # type: (str, Asset) -> bool
    if not page_mentions_asset(page_text, asset):
        return False
    return any(marker in page_text for marker in SNIPPET_MARKERS)


def page_explains_asset(page_text, asset):
    # type: (str, Asset) -> bool
    if not page_mentions_asset(page_text, asset):
        return False
    return any(marker in page_text for marker in EXPLAIN_MARKERS)


def audit(assets, docs):
    # type: (Iterable[Asset], Dict[str, str]) -> Dict[Asset, Hit]
    result = {}  # type: Dict[Asset, Hit]
    for asset in assets:
        hit = Hit()
        for page, text in docs.items():
            if page_mentions_asset(text, asset):
                hit.referenced = True
                hit.pages.add(page)
            if page_has_snippet_for_asset(text, asset):
                hit.snippet = True
                hit.pages.add(page)
            if page_explains_asset(text, asset):
                hit.explained = True
                hit.pages.add(page)
        result[asset] = hit
    return result


def print_summary(results, max_missing):
    # type: (Dict[Asset, Hit], int) -> int
    by_area = defaultdict(list)  # type: Dict[str, List[Tuple[Asset, Hit]]]
    for asset, hit in results.items():
        by_area[asset.area].append((asset, hit))

    total = len(results)
    referenced = sum(1 for hit in results.values() if hit.referenced)
    snippet = sum(1 for hit in results.values() if hit.snippet)
    explained = sum(1 for hit in results.values() if hit.explained)
    missing_explained = total - explained

    print("=== v2 source paragraph explanation audit ===")
    print(f"doc_root: {DOC_ROOT}")
    print(f"asset_total: {total}")
    print(f"referenced: {referenced}")
    print(f"with_snippet: {snippet}")
    print(f"with_paragraph_explanation: {explained}")
    print(f"missing_paragraph_explanation: {missing_explained}")
    print("---")
    print("area,total,referenced,with_snippet,with_paragraph_explanation,missing")
    for area in sorted(by_area):
        rows = by_area[area]
        area_total = len(rows)
        area_ref = sum(1 for _, hit in rows if hit.referenced)
        area_snippet = sum(1 for _, hit in rows if hit.snippet)
        area_explained = sum(1 for _, hit in rows if hit.explained)
        print(
            f"{area},{area_total},{area_ref},{area_snippet},"
            f"{area_explained},{area_total - area_explained}"
        )

    missing = [(asset, hit) for asset, hit in results.items() if not hit.explained]
    if missing:
        print("---")
        print(f"first_missing_paragraph_explanations (limit {max_missing})")
        for asset, hit in missing[:max_missing]:
            status = []
            if not hit.referenced:
                status.append("no_reference")
            if not hit.snippet:
                status.append("no_snippet")
            status.append("no_paragraph_explanation")
            print(f"{asset.area}: {asset.label} [{', '.join(status)}]")
    return missing_explained


def main():
    # type: () -> int
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit non-zero when any source asset lacks paragraph explanation",
    )
    parser.add_argument(
        "--max-missing",
        type=int,
        default=120,
        help="maximum missing assets printed in the detail section",
    )
    args = parser.parse_args()

    assets = collect_assets()
    docs = load_docs()
    missing = print_summary(audit(assets, docs), args.max_missing)
    if args.strict and missing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
