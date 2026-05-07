// SPDX-License-Identifier: Apache-2.0
// EH2 DUT Probe Interface — internal DUT signal probing for verification
//
// Phase 1 (ADR-0004) note: regular pipeline writebacks are now carried by the
// RTL trace packet (rd_valid/rd_addr/rd_wdata fields), so this interface no
// longer needs to expose i0/i1 wb_valid/wb_dest/wb_data. What remains:
//   - DIV unit async writebacks + cancel-overwrite annotation
//   - NB-load async writeback completion
//   - Interrupt/NMI/debug state for cosim notification
//   - CSR mirror state and exception flags (used by directed tests + fcov)
//
// Connect to DUT internal signals via hierarchical references in tb_top.

interface eh2_dut_probe_if(
  input logic clk,
  input logic rst_n
);

  // Division unit signals
  logic             div_cancel;             // Division canceled (any kind)
  logic             div_cancel_overwrite;   // Cancel due to younger same-rd write (paired with retired div trace)
  logic [4:0]       div_rd;                 // Division destination register
  logic [31:0]      div_result;             // Division raw result (pre-qualify)
  logic             div_wren;               // Division writeback valid (exu_div_wren)
  logic [31:0]      div_wdata;              // Division writeback data (exu_div_result)

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

  // CSR mirror state (for directed tests and coverage)
  logic [31:0]      mstatus;
  logic [31:0]      mtvec;
  logic [31:0]      mepc;
  logic [31:0]      mcause;

  // Exception/trap signals at E4 stage (for directed tests and coverage)
  logic             mret_e4;
  logic             illegal_e4;
  logic             ecall_e4;
  logic             ebreak_e4;
  logic             ebreak_to_debug_e4;
  logic             inst_acc_e4;

  // Exception/trap signals at writeback stage
  logic             mret_wb;
  logic             illegal_wb;
  logic             ecall_wb;
  logic             ebreak_wb;

  // Debug state
  logic             debug_mode;
  logic             dbg_halted;

  // Interrupt tracking
  logic             interrupt_valid;
  logic             take_ext_int;
  logic             take_timer_int;
  logic             take_soft_int;
  logic             take_nmi;

  // Monitor clocking block
  clocking monitor_cb @(posedge clk);
    input div_cancel;
    input div_cancel_overwrite;
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
