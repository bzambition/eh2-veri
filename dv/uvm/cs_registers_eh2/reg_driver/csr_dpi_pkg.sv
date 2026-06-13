// SPDX-License-Identifier: Apache-2.0
// EH2 CSR DPI Package (Issue 56)
//
// DPI-C function declarations for CSR read/write from UVM to the
// DUT register file.  Imported into $unit scope by cs_registers_tb.sv
// before all other includes.

package csr_dpi_pkg;

  // ----------------------------------------------------------------
  // CSR operation types — matches RISC-V CSR instructions
  // ----------------------------------------------------------------
  localparam int CSR_OP_READ  = 0;
  localparam int CSR_OP_WRITE = 1;
  localparam int CSR_OP_SET   = 2;
  localparam int CSR_OP_CLEAR = 3;

endpackage
