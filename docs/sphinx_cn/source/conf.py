# Sphinx configuration — EH2 UVM 验证平台（中文参考手册）
#
# 构建命令：
#   sphinx-build -b html source build/html
#   或 bash docs/build_manual_pdf.sh  # PDF via rinohtype
#
# HTML 主题：sphinx_book_theme（类似 lowRISC Ibex readthedocs 风格）
# PDF 输出：docs/sphinx_cn/build/rinoh/EH2_UVM_Verification_Platform.pdf

import sys
from pathlib import Path

SOURCE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
sys.path.insert(0, str(SOURCE_DIR / "_ext"))

project = "EH2 UVM 验证平台"
copyright = "2026, EH2 验证团队"
author = "EH2 验证团队"
release = "1.1"

def _requested_builder():
    if "-b" in sys.argv:
        idx = sys.argv.index("-b")
        if idx + 1 < len(sys.argv):
            return sys.argv[idx + 1]
    return ""

extensions = [
    "sphinx.ext.intersphinx",
    "sphinx.ext.todo",
    "sphinx.ext.viewcode",
]

# 可选扩展 - 未安装时静默跳过
for ext in ["sphinx_copybutton", "myst_parser"]:
    try:
        __import__(ext)
        extensions.append(ext)
    except ImportError:
        pass

# sphinx-tabs 是 v2 手册的交互式分流入口；本地旧环境未安装时使用兼容 fallback。
try:
    __import__("sphinx_tabs.tabs")
    extensions.append("sphinx_tabs.tabs")
except ImportError:
    extensions.append("eh2_tabs_fallback")

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

# -- HTML 主题配置 -----------------------------------------------------------
html_static_path = ["_static"]

# 尝试 sphinx_book_theme，未安装时回退到 alabaster
try:
    import sphinx_book_theme  # noqa: F401
    html_theme = "sphinx_book_theme"
    html_theme_options = {
        "repository_url": "https://github.com/chipsalliance/Cores-VeeR-EH2",
        "use_repository_button": True,
        "use_download_button": True,
        "use_fullscreen_button": True,
        "toc_title": "本页目录",
        "show_navbar_depth": 2,
    }
except ImportError:
    html_theme = "alabaster"
    html_theme_options = {}

# -- 章节编号 ---------------------------------------------------------------
numfig = True

# -- todo 指令 --------------------------------------------------------------
todo_include_todos = True

# -- intersphinx ------------------------------------------------------------
intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
}

# -- Copybutton -------------------------------------------------------------
copybutton_prompt_text = r"\$ "

# -- rinohtype PDF 配置 -----------------------------------------------------
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

rinoh_paper_size = "A4"
