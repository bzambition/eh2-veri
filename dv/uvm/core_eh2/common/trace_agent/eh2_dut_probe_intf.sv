// SPDX-License-Identifier: Apache-2.0
// EH2 DUT Probe Interface - Internal DUT signal probing
//
// Provides hierarchical access to internal DUT signals for:
//   - Register writeback monitoring (rd_addr, rd_wdata)
//   - CSR update monitoring
//   - Memory access monitoring
//
// These signals are probed from the DUT hierarchy and are NOT
// part of the official DUT interface. They are used for
// verification purposes only.
//
// Usage:
//   Connect to DUT internal signals via hierarchical references
//   in the testbench top module.

interface eh2_dut_probe_intf(
  input logic clk,
  input logic rst_n
);

  // Register writeback signals
  // These are probed from the decode unit's writeback stage
  logic [1:0]       wb_valid;      // Writeback valid (per slot)
  logic [1:0][4:0]  wb_dest;       // Destination register (per slot)
  logic [1:0][31:0] wb_data;       // Writeback data (per slot)
  logic [1:0]       wb_tid;        // Thread ID (per slot)

  // Register writeback suppress (load killed by interrupt/debug)
  logic [1:0]       wb_suppress;   // Writeback suppressed (per slot)

  // Writeback sequence counter for precise trace-to-writeback correlation
  // Incremented by the probe monitor on each writeback event.
  // The trace monitor reads this counter to stamp each trace item.
  logic [31:0]      wb_seq;        // Current writeback sequence number

  // Division unit signals
  logic             div_cancel;     // Division canceled
  logic             div_cancel_overwrite;  // Cancel due to younger same-rd write (paired with retired div trace)
  logic [4:0]       div_rd;         // Division destination register
  logic [31:0]      div_result;     // Division raw result (pre-qualify)
  logic             div_wren;       // Division writeback valid (exu_div_wren)
  logic [31:0]      div_wdata;      // Division writeback data (exu_div_result)

  // Non-block load signals
  logic             nb_load_wen;
  logic [4:0]       nb_load_waddr;
  logic [31:0]      nb_load_data;

  // Interrupt/NMI/debug state (sampled each cycle for cosim notification)
  logic [31:0]      mip;           // Machine interrupt pending
  logic             nmi;           // NMI mode
  logic             nmi_int;       // NMI interrupt pending
  logic             debug_req;     // Debug request active
  logic [63:0]      mcycle;        // Cycle counter

  // CSR signals
  logic [31:0]      mstatus;
  logic [31:0]      mtvec;
  logic [31:0]      mepc;
  logic [31:0]      mcause;

  // Exception/trap signals at E4 stage (for directed tests and coverage)
  logic             mret_e4;            // MRET instruction at E4
  logic             illegal_e4;         // Illegal instruction at E4
  logic             ecall_e4;           // ECALL at E4
  logic             ebreak_e4;          // EBREAK at E4 (exception)
  logic             ebreak_to_debug_e4; // EBREAK entering debug mode at E4
  logic             inst_acc_e4;        // Instruction access fault at E4

  // Exception/trap signals at writeback stage
  logic             mret_wb;
  logic             illegal_wb;
  logic             ecall_wb;
  logic             ebreak_wb;

  // Debug state
  logic             debug_mode;         // Core is in debug mode
  logic             dbg_halted;         // Core is halted in debug

  // Interrupt tracking
  logic             interrupt_valid;    // Interrupt being taken
  logic             take_ext_int;       // Taking external interrupt
  logic             take_timer_int;     // Taking timer interrupt
  logic             take_soft_int;      // Taking software interrupt
  logic             take_nmi;           // Taking NMI

  // Monitor clocking block
  clocking monitor_cb @(posedge clk);
    input wb_valid;
    input wb_dest;
    input wb_data;
    input wb_tid;
    input wb_suppress;
    input wb_seq;
    input div_cancel;
    input div_rd;
    input div_result;
    input div_wren;
    input div_wdata;
    input nb_load_wen;
    input nb_load_waddr;
    input nb_load_data;
    input mip;
    input nmi;
    input nmi_int;
    input debug_req;
    input mcycle;
    input mstatus;
    input mtvec;
    input mepc;
    input mcause;
    input mret_e4;
    input illegal_e4;
    input ecall_e4;
    input ebreak_e4;
    input ebreak_to_debug_e4;
    input inst_acc_e4;
    input mret_wb;
    input illegal_wb;
    input ecall_wb;
    input ebreak_wb;
    input debug_mode;
    input dbg_halted;
    input interrupt_valid;
    input take_ext_int;
    input take_timer_int;
    input take_soft_int;
    input take_nmi;
  endclocking

endinterface
