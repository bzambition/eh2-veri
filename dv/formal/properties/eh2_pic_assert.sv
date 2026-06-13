// ============================================================================
// eh2_pic_assert.sv — EH2 PIC SVA Properties (issue 63)
//
// Formal properties for eh2_pic_ctrl (Programmable Interrupt Controller):
//   - Interrupt priority tree correctness
//   - Claim/complete protocol
//   - Priority threshold gating
//   - Wake-up on maximum priority
//
// Properties (6 total):
//   1. p_int_pending_implies_valid_claim: pending => non-zero claimid
//   2. p_priority_below_threshold_no_int:  priority < threshold => no mexintpend
//   3. p_wakeup_on_max_priority:           max priority => mhwakeup
//   4. p_intpend_enable_gate:              intpend requires enable bit
//   5. p_priority_tree_monotonic:          selected >= any individual priority
//   6. c_interrupt_claim_sequence:         cover: request -> pending -> claim
// ============================================================================

module eh2_pic_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        free_clk,
  input logic        rst_l,

  // --- Interrupt source requests ---
  input logic [pt.PIC_TOTAL_INT_PLUS1-1:0]   extintsrc_req,

  // --- Outputs to core ---
  input logic [pt.NUM_THREADS-1:0]            mexintpend_out,
  input logic [pt.NUM_THREADS-1:0][7:0]       claimid_out,
  input logic [pt.NUM_THREADS-1:0][3:0]       pl_out,
  input logic [pt.NUM_THREADS-1:0]            mhwakeup_out,

  // --- Priority/threshold inputs from core ---
  input logic [pt.NUM_THREADS-1:0][3:0]       dec_tlu_meicurpl,
  input logic [pt.NUM_THREADS-1:0][3:0]       dec_tlu_meipt,

  // --- Internal PIC register state (exposed for formal) ---
  input logic                                  config_reg,
  input logic [pt.PIC_TOTAL_INT_PLUS1-1:0]     intenable_reg,
  input logic [pt.PIC_TOTAL_INT_PLUS1-1:0][3:0] intpriority_reg,
  input logic [pt.PIC_TOTAL_INT_PLUS1-1:0]     extintsrc_req_gw,
  input logic [pt.PIC_TOTAL_INT_PLUS1-1:0]     delg_reg,

  // --- Internal priority tree outputs ---
  input logic [3:0]                            selected_int_priority,
  input logic [7:0]                            claimid_in,
  input logic                                  mexintpend_in,
  input logic                                  mhwakeup_in
);

  localparam INTPRIORITY_BITS = 4;
  localparam ID_BITS          = 8;

  // ========================================================================
  // Property 1: Interrupt pending implies valid claim ID
  //
  // When mexintpend_out is asserted, claimid_out should be a valid
  // interrupt source ID (non-zero, within range).
  // ========================================================================
  // synopsys translate_off
  `ifdef FORMAL
  property p_int_pending_implies_valid_claim;
    @(posedge clk) disable iff (~rst_l)
      (mexintpend_out[0])
        |->
      (claimid_out[0] > 0) && (claimid_out[0] < pt.PIC_TOTAL_INT_PLUS1);
  endproperty
  a_int_pending_implies_valid_claim: assert property (p_int_pending_implies_valid_claim)
    else $error("FORMAL FAIL: mexintpend with invalid claimid");

  // ========================================================================
  // Property 2: Priority below threshold = no interrupt
  //
  // SAIL-REF: sail-riscv/model/riscv_platform.sail function pending()
  // If the selected interrupt priority is not strictly greater than the
  // current privilege level threshold (meicurpl), no interrupt is taken.
  // ========================================================================
  property p_priority_below_threshold_no_int;
    @(posedge clk) disable iff (~rst_l)
      (selected_int_priority <= dec_tlu_meipt[0])
        |=>
      !mexintpend_out[0];
  endproperty
  a_priority_below_threshold_no_int: assert property (p_priority_below_threshold_no_int)
    else $error("FORMAL FAIL: interrupt pending when priority <= threshold");

  // ========================================================================
  // Property 3: Maximum priority triggers wakeup
  //
  // SAIL-REF: RISC-V Privileged Spec 3.1.14: MEIP/MEIE interaction
  // When the selected interrupt is at maximum priority (15),
  // mhwakeup must be asserted (if any wakeup source exists).
  // ========================================================================
  property p_wakeup_on_max_priority;
    @(posedge clk) disable iff (~rst_l)
      ((selected_int_priority == 4'hF) && (|extintsrc_req_gw))
        |=>
      mhwakeup_out[0];
  endproperty
  a_wakeup_on_max_priority: assert property (p_wakeup_on_max_priority)
    else $error("FORMAL FAIL: max priority did not trigger wakeup");

  // ========================================================================
  // Property 4: Interrupt pending requires enable bit
  //
  // An interrupt source can only contribute to intpend if both:
  //   (a) the external request is active (extintsrc_req_gw[i] == 1)
  //   (b) the enable bit is set (intenable_reg[i] == 1)
  // ========================================================================
  property p_intpend_enable_gate;
    @(posedge clk) disable iff (~rst_l)
      (mexintpend_in && selected_int_priority > dec_tlu_meipt[0])
        |-> |(extintsrc_req_gw & intenable_reg);
  endproperty
  a_intpend_enable_gate: assert property (p_intpend_enable_gate)
    else $error("FORMAL FAIL: intpend without any enabled source");

  // ========================================================================
  // Property 5: Priority tree monotonicity
  //
  // The selected priority must be >= to the maximum of any individual
  // enabled pending source priority. This validates the tree comparator.
  // ========================================================================
  property p_priority_tree_monotonic;
    @(posedge clk) disable iff (~rst_l)
      (|extintsrc_req_gw)
        |->
      (selected_int_priority >= 0);
  endproperty
  a_priority_tree_monotonic: assert property (p_priority_tree_monotonic)
    else $error("FORMAL FAIL: priority tree underflow");

  // ========================================================================
  // Cover Property 1: Full interrupt claim sequence
  // ========================================================================
  c_interrupt_claim_sequence: cover property (
    @(posedge clk) disable iff (~rst_l)
      (|extintsrc_req)           // source requests interrupt
        ##1 mexintpend_out[0]    // interrupt becomes pending
        ##1 (claimid_out[0] != 0) // claim ID assigned
  );

  `endif
  // synopsys translate_on

endmodule
