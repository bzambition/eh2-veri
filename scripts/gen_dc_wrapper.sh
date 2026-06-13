#!/bin/bash
# Generate syn/build/eh2_dc_wrapper.sv for Design Compiler / Formality LEC.
#
# Per ADR-0013 (RC3 fix): DC O-2018.06 treats each `analyze` invocation as a
# separate compilation unit; the eh2_param_t typedef in eh2_pdef.vh therefore
# is not visible to other files that `include "eh2_param.vh"`. The fix is a
# single-file wrapper that `\`include`s every RTL piece in dependency order,
# so analyze sees one big compilation unit.
#
# File order (mandatory): common_defines.vh -> eh2_pdef.vh -> eh2_def.sv ->
#                         lib/*.sv -> design/*.sv
#
# Output: syn/build/eh2_dc_wrapper.sv (idempotent; regenerated on every call)
#
# Triggered automatically as a prerequisite of `make -C syn syn-dc` and
# `make -C syn block_lec`. Also runnable standalone.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RV_ROOT="${RV_ROOT:-/home/host/Cores-VeeR-EH2}"
FLIST="${RV_ROOT}/design/flist"
OUT="${ROOT_DIR}/syn/build/eh2_dc_wrapper.sv"

if [[ ! -f "$FLIST" ]]; then
  echo "ERROR: flist not found: $FLIST" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

# Resolve flist into absolute paths and split into lib/design buckets.
mapfile -t ABS_PATHS < <(sed "s|\$RV_ROOT|${RV_ROOT}|" "$FLIST")

LIB_FILES=()
DESIGN_FILES=()
for path in "${ABS_PATHS[@]}"; do
  [[ -z "$path" ]] && continue
  case "$path" in
    */design/include/eh2_def.sv) ;;            # included by name below
    */design/lib/*) LIB_FILES+=("$path") ;;
    *) DESIGN_FILES+=("$path") ;;
  esac
done

# Required: eh2_lib.sv must precede beh_lib.sv (eh2_lib defines macros used by
# behavioural primitives). Force the order regardless of flist position.
ORDERED_LIB=()
for prio in eh2_lib.sv beh_lib.sv mem_lib.sv ahb_to_axi4.sv axi4_to_ahb.sv; do
  for f in "${LIB_FILES[@]}"; do
    if [[ "$(basename "$f")" == "$prio" ]]; then
      ORDERED_LIB+=("$f")
      break
    fi
  done
done

{
  cat <<'HEADER'
// =============================================================================
// EH2 DC Synthesis Wrapper — AUTO-GENERATED, DO NOT EDIT
// =============================================================================
// Regenerate via:  bash scripts/gen_dc_wrapper.sh
// Documented at:   docs/adr/0013-synthesis-toolchain.md (RC3 fix)
//
// Why this file exists:
//   Design Compiler O-2018.06 treats each `analyze` invocation as a separate
//   compilation unit. The eh2_param_t typedef declared in eh2_pdef.vh is then
//   invisible to any other file that `\`include`s eh2_param.vh, producing
//   ELAB-210 errors. Merging all RTL via `\`include`s into ONE compilation
//   unit avoids the issue.
//
// Order (mandatory):
//   1. TEC_RV_ICG explicit `\`define (DC include path does not propagate it)
//   2. common_defines.vh
//   3. eh2_pdef.vh   — declares eh2_param_t
//   4. eh2_def.sv    — package eh2_pkg + trace_pkt_t etc.
//   5. lib/*.sv      — behavioural primitives, mem libs, bus bridges
//   6. design/*.sv   — pipeline modules; eh2_veer is the synthesis top
// =============================================================================

`define TEC_RV_ICG clockhdr

`include "common_defines.vh"
`include "eh2_pdef.vh"
`include "eh2_def.sv"

HEADER

  echo "// ----- lib modules (ordered) -----"
  for f in "${ORDERED_LIB[@]}"; do
    echo "\`include \"${f}\""
  done

  echo
  echo "// ----- design modules (flist order, eh2_veer is the synthesis top) -----"
  for f in "${DESIGN_FILES[@]}"; do
    echo "\`include \"${f}\""
  done

  echo
  echo "// =============================================================================="
  echo "// End of auto-generated wrapper"
  echo "// =============================================================================="
} > "$OUT"

LINES=$(wc -l < "$OUT")
echo "[gen_dc_wrapper] generated $OUT ($LINES lines)"
echo "[gen_dc_wrapper] flist: $FLIST"
echo "[gen_dc_wrapper] lib modules: ${#ORDERED_LIB[@]}"
echo "[gen_dc_wrapper] design modules: ${#DESIGN_FILES[@]}"
