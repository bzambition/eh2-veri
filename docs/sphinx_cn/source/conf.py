# Sphinx configuration — EH2 UVM 验证平台（中文参考手册）
#
# 输出：PDF via rinohtype（不需 LaTeX）。
# 构建命令：bash docs/build_manual_pdf.sh
# 输出位置：docs/sphinx_cn/build/rinoh/EH2_UVM_Verification_Platform.pdf

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

project = "EH2 UVM 验证平台"
copyright = "2026, EH2 验证团队"
author = "EH2 验证团队"
release = "1.0"

def _requested_builder():
    if "-b" in sys.argv:
        idx = sys.argv.index("-b")
        if idx + 1 < len(sys.argv):
            return sys.argv[idx + 1]
    return ""


extensions = []
if _requested_builder() == "rinoh":
    try:
        import rinoh.frontend.sphinx  # noqa: F401
    except Exception as exc:
        raise RuntimeError(
            "rinohtype is required for the rinoh PDF builder. "
            "Use Python 3.10+ and install docs/requirements-docs.txt, "
            "or build HTML/source docs without -b rinoh."
        ) from exc
    extensions.append("rinoh.frontend.sphinx")

templates_path = ["_templates"]
exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
]

language = "zh_CN"

html_theme = "alabaster"
html_static_path = ["_static"]

# rinohtype PDF 配置
rinoh_documents = [
    {
        "doc": "index",
        "target": "EH2_UVM_Verification_Platform",
        "title": "EH2 UVM 验证平台 — 参考手册",
        "subtitle": "VeeR EH2 双线程 RV32IMAC 处理器 UVM 验证框架",
        "author": author,
        "template": "book",
    }
]

# Sphinx 默认中文字体（rinohtype 通过 fonts list 处理）
rinoh_paper_size = "A4"
