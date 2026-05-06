#!/bin/bash
# EH2 UVM Verification Platform - Environment Setup
# Source this file: source env.sh

# Project root
export EH2_VERIF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# RTL source
export RV_ROOT="/home/host/Cores-VeeR-EH2"

# RISC-V GCC toolchain
export GCC_PREFIX="/home/host/gcc-riscv64-unknown-elf"
export PATH="${GCC_PREFIX}/bin:${PATH}"

# QEMU (for co-simulation)
export QEMU_BIN="/home/host/eh2-verification/qemu-eh2/build/qemu-system-riscv32"

# Simulator selection (vcs/xlm/questa)
export EH2_SIMULATOR="vcs"

# Architecture flags
export ABI="-mabi=ilp32 -march=rv32imac"

# Verification platform paths
export EH2_DV_ROOT="${EH2_VERIF_ROOT}/dv"
export EH2_UVM_ROOT="${EH2_DV_ROOT}/uvm/core_eh2"
export EH2_SHARED_ROOT="${EH2_VERIF_ROOT}/shared"
export EH2_VENDOR_ROOT="${EH2_VERIF_ROOT}/vendor"

echo "=========================================="
echo "EH2 UVM Verification Platform"
echo "=========================================="
echo "EH2_VERIF_ROOT: ${EH2_VERIF_ROOT}"
echo "RV_ROOT:        ${RV_ROOT}"
echo "GCC_PREFIX:     ${GCC_PREFIX}"
echo "SIMULATOR:      ${EH2_SIMULATOR}"
echo "=========================================="
