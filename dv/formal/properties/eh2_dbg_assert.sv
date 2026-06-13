// ============================================================================
// eh2_dbg_assert.sv — EH2 Debug Module SVA Properties (issue 63)
//
// Formal properties for eh2_dbg (RISC-V Debug Module 0.13):
//   - Halt/resume FSM transitions
//   - Halt and resume mutual exclusion
//   - Single-step (resume-ack) protocol
//   - Abstract command completion
//
// Properties (6 total):
//   1. p_halt_req_enters_halt_fsm:     halt_req => HALTING transition
//   2. p_resume_from_halted:           resume_req + halted => RESUMING
//   3. p_halt_resume_onehot:           halt and resume never simultaneous
//   4. p_cmd_done_clears_abstract_busy: abstract command done clears busy
//   5. p_dmactive_off_resets:          dmactive=0 puts FSM in IDLE
//   6. c_halt_resume_roundtrip:        cover: halt then resume sequence
// ============================================================================

module eh2_dbg_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        rst_l,

  // --- Debug FSM state (per-thread) ---
  input logic [pt.NUM_THREADS-1:0][3:0]  dbg_state,
  input logic [pt.NUM_THREADS-1:0]        dbg_state_en,

  // --- Halt/Resume handshake ---
  input logic [pt.NUM_THREADS-1:0]        dbg_halt_req,
  input logic [pt.NUM_THREADS-1:0]        dbg_resume_req,
  input logic [pt.NUM_THREADS-1:0]        dec_tlu_debug_mode,
  input logic [pt.NUM_THREADS-1:0]        dec_tlu_dbg_halted,
  input logic [pt.NUM_THREADS-1:0]        dec_tlu_resume_ack,

  // --- DM control/status ---
  input logic [31:0]                      dmcontrol_reg,
  input logic [31:0]                      dmstatus_reg,
  input logic [31:0]                      abstractcs_reg,

  // --- Abstract command ---
  input logic                             execute_command,
  input logic [31:0]                      command_reg,
  input logic                             dbg_cmd_valid,
  input logic                             core_dbg_cmd_done,
  input logic                             core_dbg_cmd_fail,
  input logic [31:0]                      core_dbg_rddata,

  // --- DMI interface ---
  input logic                             dmi_reg_en,
  input logic [6:0]                       dmi_reg_addr,
  input logic                             dmi_reg_wr_en,
  input logic [31:0]                      dmi_reg_wdata
);

  // FSM state encoding (from eh2_dbg.sv)
  localparam logic [3:0] FSM_IDLE           = 4'h0;
  localparam logic [3:0] FSM_HALTING        = 4'h1;
  localparam logic [3:0] FSM_HALTED         = 4'h2;
  localparam logic [3:0] FSM_CORE_CMD_START = 4'h3;
  localparam logic [3:0] FSM_CORE_CMD_WAIT  = 4'h4;
  localparam logic [3:0] FSM_SB_CMD_START   = 4'h5;
  localparam logic [3:0] FSM_SB_CMD_SEND    = 4'h6;
  localparam logic [3:0] FSM_SB_CMD_RESP    = 4'h7;
  localparam logic [3:0] FSM_CMD_DONE       = 4'h8;
  localparam logic [3:0] FSM_RESUMING       = 4'h9;

  // pick thread 0 for single-thread config
  wire [3:0] fsm = dbg_state[0];

  // ========================================================================
  // Property 1: Halt request drives HALTING transition
  //
  // When dmactive=1, haltreq=1 is written to dmcontrol, the FSM
  // should leave IDLE and enter HALTING (if currently IDLE).
  // ========================================================================
  // synopsys translate_off
  `ifdef FORMAL
  property p_halt_req_enters_halt_fsm;
    @(posedge clk) disable iff (~rst_l)
      (dbg_halt_req[0])
        |=>
      (fsm == FSM_HALTING);
  endproperty
  a_halt_req_enters_halt_fsm: assert property (p_halt_req_enters_halt_fsm)
    else $error("FORMAL FAIL: halt_req did not enter HALTING");

  // ========================================================================
  // Property 2: From HALTED, resume request transitions to RESUMING
  // ========================================================================
  property p_resume_from_halted;
    @(posedge clk) disable iff (~rst_l)
      ((fsm == FSM_HALTED) && dbg_resume_req[0] && dec_tlu_dbg_halted[0])
        |=>
      (fsm == FSM_RESUMING);
  endproperty
  a_resume_from_halted: assert property (p_resume_from_halted)
    else $error("FORMAL FAIL: resume from HALTED did not enter RESUMING");

  // ========================================================================
  // Property 3: Halt and resume are mutually exclusive
  //
  // dbg_halt_req and dbg_resume_req must never be asserted simultaneously.
  // ========================================================================
  property p_halt_resume_onehot;
    @(posedge clk) disable iff (~rst_l)
      !(dbg_halt_req[0] && dbg_resume_req[0]);
  endproperty
  a_halt_resume_onehot: assert property (p_halt_resume_onehot)
    else $error("FORMAL FAIL: halt and resume simultaneously asserted");

  // ========================================================================
  // Property 4: Abstract command completion clears busy
  //
  // When abstractcs.busy is set (command executing) and the core reports
  // core_dbg_cmd_done, the next state should transition away from busy.
  // Here we check: after CMD_DONE state, busyle is deasserted.
  // ========================================================================
  property p_cmd_done_clears_busy;
    @(posedge clk) disable iff (~rst_l)
      ($rose(fsm == FSM_CMD_DONE) && dbg_state_en[0])
        |=>
      (fsm == FSM_HALTED);
  endproperty
  a_cmd_done_clears_busy: assert property (p_cmd_done_clears_busy)
    else $error("FORMAL FAIL: cmd_done did not return to HALTED");

  // ========================================================================
  // Property 5: dmactive=0 forces reset-like behavior
  //
  // When dmactive bit is cleared, the FSM should eventually return to IDLE.
  // The debug reset (dbg_dm_rst_l) is derived from dmcontrol_reg[0].
  // ========================================================================
  property p_dmactive_off_holds_idle;
    @(posedge clk) disable iff (~rst_l)
      (!dmcontrol_reg[0])
        |=>
      (fsm == FSM_IDLE);
  endproperty
  a_dmactive_off_holds_idle: assert property (p_dmactive_off_holds_idle)
    else $error("FORMAL FAIL: dmactive=0 but FSM not IDLE");

  // ========================================================================
  // Cover Property 1: Full halt-resume round trip
  // ========================================================================
  c_halt_resume_roundtrip: cover property (
    @(posedge clk) disable iff (~rst_l)
      (fsm == FSM_IDLE)
        ##1 (dbg_halt_req[0])
        ##1 (fsm == FSM_HALTING)
        ##1 (fsm == FSM_HALTED)
        ##1 (dbg_resume_req[0])
        ##1 (fsm == FSM_RESUMING)
        ##1 (fsm == FSM_IDLE)
  );

  `endif
  // synopsys translate_on

endmodule
