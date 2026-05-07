#!/bin/bash
# 构建 EH2 UVM 验证平台中文手册（PDF）
#
# 依赖：sphinx + rinohtype（pip install -r docs/requirements-docs.txt）
# 输出：docs/sphinx_cn/build/rinoh/EH2_UVM_Verification_Platform.pdf
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/docs/sphinx_cn/source"
OUT="$ROOT/docs/sphinx_cn/build/rinoh"

# 把本地 ~/.local/bin 加进 PATH（pip install --user 后 sphinx-build 在那里）
export PATH="$HOME/.local/bin:$PATH"

if ! command -v sphinx-build >/dev/null 2>&1; then
    cat <<EOF
错误：未找到 sphinx-build。请先安装依赖：

    pip install --user -r $ROOT/docs/requirements-docs.txt

然后将 ~/.local/bin 加入 PATH。
EOF
    exit 1
fi

mkdir -p "$OUT"
sphinx-build -b rinoh "$SRC" "$OUT"

PDF="$OUT/EH2_UVM_Verification_Platform.pdf"
if [[ -f "$PDF" ]]; then
    echo ""
    echo "PDF 已生成：$PDF"
    ls -la "$PDF"
else
    echo "未找到 PDF。输出目录："
    ls -la "$OUT" || true
    exit 1
fi
