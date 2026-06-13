// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Access Functions (Issue 56)
//
// $unit-scope wrapper functions that forward CSR reads/writes to
// the testbench module's hierarchical access functions.
//
// The TB module (cs_registers_tb) has tb_csr_read/tb_csr_write that
// directly access the DUT register file (u_dut.csr_storage).

`ifndef CSR_ACCESS_DEFINED
`define CSR_ACCESS_DEFINED

function automatic int csr_dpi_read(input int addr);
  return int'(cs_registers_tb.tb_csr_read(addr));
endfunction

function automatic int csr_dpi_write(input int addr, input int wdata, input int op);
  return cs_registers_tb.tb_csr_write(addr, wdata[31:0], op);
endfunction

function automatic void csr_dpi_reset();
  // No-op — handled by DUT rst_ni
endfunction

function automatic int csr_dpi_warl(input int addr, input int wdata);
  return int'(cs_registers_tb.tb_csr_warl(addr, wdata[31:0]));
endfunction

`endif
