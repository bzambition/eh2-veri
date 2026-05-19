#!/bin/bash
# scripts/v2_coverage_check.sh
set -u

echo "=== v2 强制覆盖核对 ==="
missing=0

for asset in \
  "Cores-VeeR-EH2/design/eh2_veer.sv" \
  "Cores-VeeR-EH2/design/ifu/eh2_ifu.sv" \
  "Cores-VeeR-EH2/design/dec/eh2_dec.sv" \
  "Cores-VeeR-EH2/design/exu/eh2_exu.sv" \
  "Cores-VeeR-EH2/design/lsu/eh2_lsu.sv" \
  "eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv" \
  "eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv" \
  "eh2-veri/dv/cosim/spike_cosim.cc" \
  "eh2-veri/dv/uvm/core_eh2/scripts/signoff.py" \
  "eh2-veri/dv/uvm/core_eh2/scripts/merge_cov.py" \
  "eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml" \
  "eh2-veri/dv/uvm/core_eh2/cover.cfg" \
  "eh2-veri/dv/uvm/core_eh2/cov_full_nc.ccf" \
  ; do
  bn=$(basename "$asset")
  hits=$(grep -rl "$bn" /home/host/eh2-veri/docs/sphinx_cn/source/ 2>/dev/null | wc -l)
  if [ "$hits" -eq 0 ]; then
    echo "❌ MISSING: $asset 在 sphinx_cn 中无任何引用"
    missing=$((missing+1))
  fi
done

# 检查 directed tests 是否每个 .S 都有 §5.NN 单独章节。
for s in /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/*.S /home/host/eh2-veri/tests/asm/*.S; do
  [ -e "$s" ] || continue
  bn=$(basename "$s" .S)
  hits=$(grep -rl "${bn}.S" /home/host/eh2-veri/docs/sphinx_cn/source/appendix_b_uvm/tests.rst 2>/dev/null || true)
  if [ -z "$hits" ]; then
    echo "❌ MISSING directed test: $bn 在 tests.rst 中无 §5.NN 小节"
    missing=$((missing+1))
  fi
done

echo "---"
echo "未覆盖资产数：$missing"
[ "$missing" -eq 0 ] && echo "✅ 通过" || { echo "❌ 失败"; exit 1; }
