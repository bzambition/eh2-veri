// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Registers Testbench Top (Issue 56 / PROMPT-A)
//
// Instantiates the CSR DUT wrapper (csr_dut.sv, which in turn
// instantiates the real eh2_dec_csr RTL), drives a free-running
// clock + reset, and launches the UVM test.  DUT access is via
// DPI functions that call the wrapper's hierarchical access
// functions.
//
// Modeled after lowRISC Ibex dv/cs_registers/tb/tb_cs_registers.sv.

`include "csr_dpi_imports.svh"
`include "uvm_macros.svh"

module cs_registers_tb;

  import uvm_pkg::*;
  import csr_dpi_pkg::*;

  // Clock and reset
  logic        clk;
  logic        rst_n;

  // DUT CSR access signals
  logic        csr_access;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata;
  logic [1:0]  csr_op;
  logic        csr_op_en;
  logic [31:0] csr_rdata;
  logic        illegal_csr;

  // Test pass/fail
  bit          test_passed;

  // Clock generation (10 ns period = 100 MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset generation
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // --- DUT instantiation ---
  csr_dut #(
    .PMPEnable       (1),
    .PMPNumRegions   (16),
    .PMPGranularity  (0),
    .MHPMCounterNum  (4),
    .MHPMCounterWidth(40)
  ) u_dut (
    .clk_i               (clk),
    .rst_ni              (rst_n),
    .csr_access_i        (csr_access),
    .csr_addr_i          (csr_addr),
    .csr_wdata_i         (csr_wdata),
    .csr_op_i            (csr_op),
    .csr_op_en_i         (csr_op_en),
    .csr_rdata_o         (csr_rdata),
    .illegal_csr_insn_o  (illegal_csr)
  );

  // --- CSR access functions (called from UVM via $unit wrappers) ---
  // These call the DUT wrapper's hierarchical access functions.
  // No direct access to DUT internals.  Access via DUT wrapper functions.
  function automatic bit [31:0] tb_csr_read(int unsigned addr);
    return u_dut.dut_read(addr[11:0]);
  endfunction

  function automatic int tb_csr_write(int unsigned addr, bit [31:0] wdata, int unsigned op);
    return u_dut.dut_write(addr[11:0], wdata, op);
  endfunction

  function automatic bit [31:0] tb_csr_warl(int unsigned addr, bit [31:0] wdata);
    // WARL is defined in reg_model, not in DUT.
    // This function exists for backward compatibility and returns wdata unmodified.
    // The WARL sequence uses reg_model masks directly.
    return wdata;
  endfunction

  // --- UVM test entry ---
  initial begin
    `uvm_info("csr_tb", "Starting EH2 CSR Registers Unit Test (PROMPT-A: real RTL)", UVM_LOW)
    run_test("cs_registers_test");
  end

  // --- Simulation finish reporting ---
  final begin
    $display("=== EH2 CSR Registers Unit Test Complete ===");
  end

  // Dump
  initial begin
    $dumpfile("cs_registers_tb.vcd");
    $dumpvars(0, cs_registers_tb);
  end

  // Timeout (1M cycles = 10ms at 100MHz)
  initial begin
    #10000000;
    $display("FATAL: cs_registers_tb timed out after 10ms");
    $finish;
  end

endmodule
