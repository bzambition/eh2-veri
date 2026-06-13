#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${ROOT_DIR}/scripts/clean_workspace.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_exists() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || fail "expected path to exist: $path"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" && ! -L "$path" ]] || fail "expected path to be absent: $path"
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local needle="$1"
  local file="$2"
  if grep -Fq "$needle" "$file"; then
    fail "expected $file not to contain: $needle"
  fi
}

make_dir() {
  mkdir -p "$1"
  printf 'fixture\n' > "$1/marker.txt"
}

make_file() {
  mkdir -p "$(dirname "$1")"
  printf 'fixture\n' > "$1"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"
mkdir -p scripts build .scratch
cp "$SCRIPT_SRC" scripts/clean_workspace.sh

for dir in \
  r3b_final r4a_final nightly cov.vdb cov simv.daidir simv.vdb \
  simv_compliance.daidir spike_objs csrc archive_signoffs_20260101 \
  verify_riscv_amo_test sweep_riscv_arithmetic_basic_test issue12_5seed \
  cosim_19_seed1 dryrun_pmp post_unlock r2b_cov_report r3b_cov_report \
  r5_verify cov_after_pump cov_smoke.vdb smoke final_smoke final_signoff_old
do
  make_dir "build/$dir"
done

for file in \
  simv simv_compliance libcosim.so compile.log compliance_tb_compile.log \
  div_test.log ls_sweep.log smoke_cov.log signoff_rc6.log nightly_rc6.log \
  r2b_regress.log r3b_final.log r4a_final.log post_unlock.log
do
  make_file "build/$file"
done

bash scripts/clean_workspace.sh --dry-run > dry.out

for item in \
  build/verify_riscv_amo_test \
  build/sweep_riscv_arithmetic_basic_test \
  build/issue12_5seed \
  build/cosim_19_seed1 \
  build/dryrun_pmp \
  build/post_unlock \
  build/r2b_cov_report \
  build/r3b_cov_report \
  build/r5_verify \
  build/cov_after_pump \
  build/cov_smoke.vdb \
  build/smoke \
  build/final_smoke \
  build/final_signoff_old \
  build/div_test.log \
  build/ls_sweep.log \
  build/smoke_cov.log \
  build/signoff_rc6.log \
  build/nightly_rc6.log \
  build/r2b_regress.log \
  build/r3b_final.log \
  build/r4a_final.log \
  build/post_unlock.log
do
  assert_contains "$item" dry.out
done

for item in \
  build/r3b_final \
  build/r4a_final \
  build/nightly \
  build/cov.vdb \
  build/cov \
  build/simv \
  build/simv.daidir \
  build/simv.vdb \
  build/simv_compliance \
  build/simv_compliance.daidir \
  build/libcosim.so \
  build/spike_objs \
  build/csrc \
  build/compile.log \
  build/compliance_tb_compile.log \
  build/archive_signoffs_20260101
do
  assert_not_contains "archive $item ->" dry.out
  assert_exists "$item"
done

bash scripts/clean_workspace.sh --lck-only > lck.out
assert_exists build/verify_riscv_amo_test
assert_exists build/div_test.log

bash scripts/clean_workspace.sh > run.out

stamp="$(date +%Y%m%d)"
archive=".scratch/r5_build_archive_${stamp}"
assert_exists "build/archive_signoffs_${stamp}"

for item in \
  verify_riscv_amo_test \
  sweep_riscv_arithmetic_basic_test \
  issue12_5seed \
  cosim_19_seed1 \
  dryrun_pmp \
  post_unlock \
  r2b_cov_report \
  r3b_cov_report \
  r5_verify \
  cov_after_pump \
  cov_smoke.vdb \
  smoke \
  final_smoke \
  final_signoff_old \
  div_test.log \
  ls_sweep.log \
  smoke_cov.log \
  signoff_rc6.log \
  nightly_rc6.log \
  r2b_regress.log \
  r3b_final.log \
  r4a_final.log \
  post_unlock.log
do
  assert_exists "$archive/$item"
  assert_not_exists "build/$item"
done

for item in \
  r3b_final \
  r4a_final \
  nightly \
  cov.vdb \
  cov \
  simv \
  simv.daidir \
  simv.vdb \
  simv_compliance \
  simv_compliance.daidir \
  libcosim.so \
  spike_objs \
  csrc \
  compile.log \
  compliance_tb_compile.log \
  archive_signoffs_20260101
do
  assert_exists "build/$item"
done

echo "clean_workspace legacy archive tests passed"
