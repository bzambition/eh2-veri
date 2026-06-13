// ============================================================================
// eh2_ifu_assert.sv — EH2 IFU (Instruction Fetch Unit) SVA Properties
// Formal properties on eh2_ifu: BTB, ICache, PC alignment, fetch control
//
// Properties (8 total):
//   1. p_btb_taken_implies_branch:       BTB hit+taken → instruction was branch
//   2. p_ic_hit_addr_match:              I$ hit → tag addr matches request
//   3. p_fetch_pc_aligned:               Fetch PC always 2-byte aligned
//   4. p_bht_ghr_update_on_taken:        Taken branch updates GHR
//   5. p_btb_no_ras_on_non_call:         Non-call instructions don't push RAS
//   6. p_icache_bypass_no_stale:         Bypass data matches current request
//   7. p_fetch_no_overflow:              Fetch buffer never overflows
//   8. c_btb_hit_taken_reachable:        Cover: BTB hit with taken branch
// ============================================================================

module eh2_ifu_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        rst_l,

  // --- IFU control signals ---
  input logic [31:0] ifu_fetch_pc_f,
  input logic        ifu_fetch_req_f,
  input logic        ifu_fetch_ack_f,

  // --- BTB signals ---
  input logic        btb_hit_f,
  input logic        btb_taken_f,
  input logic [31:0] btb_target_pc_f,

  // --- BHT/GHR signals ---
  input logic [pt.BHT_GHR_SIZE-1:0] bht_ghr_f,
  input logic                         bht_ghr_update_f,

  // --- RAS signals ---
  input logic        ras_push_f,
  input logic        ras_pop_f,
  input logic        ras_is_call_f,
  input logic        ras_is_ret_f,

  // --- ICache signals ---
  input logic        ic_hit_f,
  input logic [31:0] ic_tag_addr_f,
  input logic [31:0] ic_req_addr_f,
  input logic        ic_bypass_f,
  input logic [31:0] ic_bypass_data_f,
  input logic [31:0] ic_fetch_data_f,

  // --- Decode feedback ---
  input logic        dec_i0_branch_d,
  input logic        dec_i1_branch_d,
  input logic [31:0] dec_i0_pc_d,
  input logic [31:0] dec_i1_pc_d
);

  // ========================================================================
  // Property 1: BTB hit + taken → the instruction later decodes as a branch
  // ========================================================================
  property p_btb_taken_implies_branch;
    @(posedge clk) disable iff (!rst_l)
    (btb_hit_f && btb_taken_f)
    |=>
    (dec_i0_branch_d || dec_i1_branch_d);
  endproperty
  a_btb_taken_implies_branch: assert property(p_btb_taken_implies_branch);

  // ========================================================================
  // Property 2: I$ hit → tag address matches request
  // ========================================================================
  property p_ic_hit_addr_match;
    @(posedge clk) disable iff (!rst_l)
    (ic_hit_f)
    |->
    (ic_tag_addr_f == ic_req_addr_f);
  endproperty
  a_ic_hit_addr_match: assert property(p_ic_hit_addr_match);

  // ========================================================================
  // Property 3: Fetch PC always 2-byte aligned (RISC-V compressed)
  // ========================================================================
  property p_fetch_pc_aligned;
    @(posedge clk) disable iff (!rst_l)
    (ifu_fetch_req_f)
    |->
    (ifu_fetch_pc_f[0] == 1'b0);
  endproperty
  a_fetch_pc_aligned: assert property(p_fetch_pc_aligned);

  // ========================================================================
  // Property 4: Taken branch updates GHR in the next cycle
  // ========================================================================
  property p_bht_ghr_update_on_taken;
    @(posedge clk) disable iff (!rst_l)
    ((dec_i0_branch_d || dec_i1_branch_d) && btb_taken_f)
    |=>
    (bht_ghr_update_f);
  endproperty
  a_bht_ghr_update_on_taken: assert property(p_bht_ghr_update_on_taken);

  // ========================================================================
  // Property 5: Non-call instructions don't push RAS
  // ========================================================================
  property p_btb_no_ras_on_non_call;
    @(posedge clk) disable iff (!rst_l)
    (!ras_is_call_f)
    |->
    (!ras_push_f);
  endproperty
  a_btb_no_ras_on_non_call: assert property(p_btb_no_ras_on_non_call);

  // ========================================================================
  // Property 6: Bypass data matches current request when bypass active
  // ========================================================================
  property p_icache_bypass_no_stale;
    @(posedge clk) disable iff (!rst_l)
    (ic_bypass_f && ic_hit_f)
    |->
    (ic_bypass_data_f == ic_fetch_data_f);
  endproperty
  a_icache_bypass_no_stale: assert property(p_icache_bypass_no_stale);

  // ========================================================================
  // Property 7: Fetch does not overflow — ack arrives within bounded cycles
  // ========================================================================
  property p_fetch_no_overflow;
    @(posedge clk) disable iff (!rst_l)
    (ifu_fetch_req_f)
    |->
    ##[1:32] (ifu_fetch_ack_f);
  endproperty
  a_fetch_no_overflow: assert property(p_fetch_no_overflow);

  // ========================================================================
  // Cover: BTB hit with taken branch
  // ========================================================================
  c_btb_hit_taken_reachable: cover property(
    @(posedge clk) (btb_hit_f && btb_taken_f)
  );

  // Cover: I$ hit
  c_ic_hit_reachable: cover property(
    @(posedge clk) (ic_hit_f)
  );

  // Cover: RAS push
  c_ras_push_reachable: cover property(
    @(posedge clk) (ras_push_f && ras_is_call_f)
  );

endmodule
