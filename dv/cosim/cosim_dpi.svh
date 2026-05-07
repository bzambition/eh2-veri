// SPDX-License-Identifier: Apache-2.0
// EH2 Co-simulation DPI Declarations
//
// SystemVerilog DPI-C import declarations for co-simulation functions.
// Based on Ibex's cosim_dpi.svh pattern.

// Initialize co-simulation
import "DPI-C" function chandle riscv_cosim_init(
  input string config
);

// Destroy co-simulation instance
import "DPI-C" function void riscv_cosim_destroy(
  input chandle handle
);

// Add memory region
import "DPI-C" function void riscv_cosim_add_memory(
  input chandle handle,
  input int     base_addr,
  input int     size
);

// Step one instruction
// Returns 1 on match, 0 on mismatch
import "DPI-C" function int riscv_cosim_step(
  input chandle handle,
  input int     write_reg,
  input int     write_reg_data,
  input int     pc,
  input int     sync_trap,
  input int     suppress_reg_write
);

// Set MIP (pre and post values)
import "DPI-C" function void riscv_cosim_set_mip(
  input chandle handle,
  input int     pre_mip,
  input int     post_mip
);

// Set NMI
import "DPI-C" function void riscv_cosim_set_nmi(
  input chandle handle,
  input int     nmi
);

// Set NMI internal
import "DPI-C" function void riscv_cosim_set_nmi_int(
  input chandle handle,
  input int     nmi_int
);

// Set debug request
import "DPI-C" function void riscv_cosim_set_debug_req(
  input chandle handle,
  input int     debug_req
);

// Set mcycle
import "DPI-C" function void riscv_cosim_set_mcycle(
  input chandle handle,
  input longint mcycle
);

// Set CSR
import "DPI-C" function void riscv_cosim_set_csr(
  input chandle handle,
  input int     csr_num,
  input int     new_val
);

// Notify dside access
import "DPI-C" function void riscv_cosim_notify_dside_access(
  input chandle handle,
  input int     store,
  input int     data,
  input int     addr,
  input int     be,
  input int     error,
  input int     misaligned_first,
  input int     misaligned_second,
  input int     misaligned_first_saw_error,
  input int     m_mode_access,
  input int     widened_load
);

// Set iside error
import "DPI-C" function void riscv_cosim_set_iside_error(
  input chandle handle,
  input int     addr
);

// Write a single byte to co-simulation memory (for binary loading)
import "DPI-C" function void riscv_cosim_write_mem_byte(
  input chandle handle,
  input int     addr,
  input int     data
);

// Get error count
import "DPI-C" function int riscv_cosim_get_num_errors(
  input chandle handle
);

// Get error message at index
import "DPI-C" function string riscv_cosim_get_error(
  input chandle handle,
  input int     index
);

// Get result (0 = pass, non-zero = fail)
import "DPI-C" function int riscv_cosim_get_result(
  input chandle handle
);

// Clear errors (call after retrieving errors to prepare for next step)
import "DPI-C" function void riscv_cosim_clear_errors(
  input chandle handle
);

// Get instruction count
import "DPI-C" function int riscv_cosim_get_insn_cnt(
  input chandle handle
);

// Trap CSR queries (RISK-9: mcause/mepc/mtvec comparison)
import "DPI-C" function int unsigned riscv_cosim_get_mcause(
  input chandle handle
);

import "DPI-C" function int unsigned riscv_cosim_get_mepc(
  input chandle handle
);

import "DPI-C" function int unsigned riscv_cosim_get_mtvec(
  input chandle handle
);
