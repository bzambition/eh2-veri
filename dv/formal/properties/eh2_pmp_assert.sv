// ============================================================================
// eh2_pmp_assert.sv — EH2 PMP/LSU Address Check SVA Properties (issue 63)
//
// Formal properties for eh2_lsu_addrcheck PMP region access protection.
// Verified via Symbiyosys (smtbmc z3) flow.
//
// Properties (8 total):
//   1. p_all_disabled_no_fault:       no MPU fault when all regions disabled
//   2. p_internal_region_no_fault:    no MPU fault for DCCM/PIC addresses
//   3. p_unmapped_ext_triggers_fault: access fault for unmapped external addr
//   4. p_atomic_in_dccm_no_fault:     AMO in DCCM region does not fault on addr
//   5. p_sidefx_aligned_no_misalign:  side-effects aligned access no misaligned
//   6. p_dma_never_access_faults:     DMA transactions never trigger access fault
//   7. p_fault_cause_consistency:     access_fault implies valid mscause
//   8. c_external_addr_stimulus:      cover external address with valid transaction
// ============================================================================

module eh2_pmp_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        rst_l,

  // --- eh2_lsu_addrcheck key signals ---
  input logic [31:0] start_addr_dc2,
  input logic [31:0] end_addr_dc2,
  input logic        access_fault_dc2,
  input logic        mpu_access_fault_dc2,
  input logic        unmapped_access_fault_dc2,
  input logic        amo_access_fault_dc2,
  input logic        misaligned_fault_dc2,
  input logic [3:0]  exc_mscause_dc2,
  input logic        is_sideeffects_dc2,
  input logic        lsu_pkt_dc2_valid,
  input logic        lsu_pkt_dc2_dma,
  input logic        lsu_pkt_dc2_word,
  input logic        lsu_pkt_dc2_atomic,
  input logic        non_dccm_access_ok,
  input logic        start_addr_in_dccm_region_dc2,
  input logic        start_addr_in_pic_region_dc2,
  input logic        addr_in_dccm_dc2,
  input logic        addr_in_pic_dc2,
  input logic        addr_external_dc2
);

  // ========================================================================
  // Property 1: When all PMP regions are disabled, MPU fault never fires
  // ========================================================================
  // synopsys translate_off
  `ifdef FORMAL
  property p_all_disabled_no_fault;
    @(posedge clk) disable iff (~rst_l)
      (non_dccm_access_ok && lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> !mpu_access_fault_dc2;
  endproperty
  a_all_disabled_no_fault: assert property (p_all_disabled_no_fault)
    else $error("FORMAL FAIL: MPU fault with all regions disabled");

  // ========================================================================
  // Property 2: DCCM/PIC region addresses never trigger MPU fault
  // ========================================================================
  property p_internal_region_no_fault;
    @(posedge clk) disable iff (~rst_l)
      ((start_addr_in_dccm_region_dc2 || start_addr_in_pic_region_dc2) &&
        lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> !mpu_access_fault_dc2;
  endproperty
  a_internal_region_no_fault: assert property (p_internal_region_no_fault)
    else $error("FORMAL FAIL: MPU fault in internal region");

  // ========================================================================
  // Property 3: External unmapped address triggers access fault
  // ========================================================================
  property p_unmapped_ext_triggers_fault;
    @(posedge clk) disable iff (~rst_l)
      (!start_addr_in_dccm_region_dc2 && !start_addr_in_pic_region_dc2 &&
       !non_dccm_access_ok &&
       lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> access_fault_dc2;
  endproperty
  a_unmapped_ext_triggers_fault: assert property (p_unmapped_ext_triggers_fault)
    else $error("FORMAL FAIL: no access fault for unmapped external addr");

  // ========================================================================
  // Property 4: AMO in DCCM region does not cause addr fault
  //
  // AMO operations to valid DCCM addresses pass addrcheck.
  // ========================================================================
  property p_atomic_in_dccm_no_fault;
    @(posedge clk) disable iff (~rst_l)
      (lsu_pkt_dc2_valid && lsu_pkt_dc2_atomic && addr_in_dccm_dc2)
        |-> !amo_access_fault_dc2;
  endproperty
  a_atomic_in_dccm_no_fault: assert property (p_atomic_in_dccm_no_fault)
    else $error("FORMAL FAIL: AMO in DCCM wrongly faulted");

  // ========================================================================
  // Property 5: Side-effects region, aligned access = no misaligned fault
  //
  // If address is in a side-effects region and bus is word-aligned,
  // no misaligned fault should fire.
  // ========================================================================
  property p_sidefx_aligned_no_misalign;
    @(posedge clk) disable iff (~rst_l)
      (is_sideeffects_dc2 && addr_external_dc2 &&
       lsu_pkt_dc2_word && (start_addr_dc2[1:0] == 2'b00) &&
       lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> !misaligned_fault_dc2;
  endproperty
  a_sidefx_aligned_no_misalign: assert property (p_sidefx_aligned_no_misalign)
    else $error("FORMAL FAIL: misaligned fault on aligned side-effects access");

  // ========================================================================
  // Property 6: DMA transactions never trigger access faults
  //
  // DMA bypasses PMP/MPU checks entirely.
  // ========================================================================
  property p_dma_never_access_faults;
    @(posedge clk) disable iff (~rst_l)
      (lsu_pkt_dc2_valid && lsu_pkt_dc2_dma)
        |-> !access_fault_dc2;
  endproperty
  a_dma_never_access_faults: assert property (p_dma_never_access_faults)
    else $error("FORMAL FAIL: DMA transaction triggered access fault");

  // ========================================================================
  // Property 7: Access fault implies valid mscause encoding
  //
  // When access_fault_dc2 fires, exc_mscause_dc2 must be non-zero and
  // within legal range (1-7).
  // ========================================================================
  property p_fault_cause_consistency;
    @(posedge clk) disable iff (~rst_l)
      (access_fault_dc2)
        |-> (exc_mscause_dc2 != 4'h0) && (exc_mscause_dc2 <= 4'h7);
  endproperty
  a_fault_cause_consistency: assert property (p_fault_cause_consistency)
    else $error("FORMAL FAIL: access fault with invalid mscause");

  // ========================================================================
  // Cover Property 1: Exercise external address with valid transaction
  // ========================================================================
  c_external_addr_covered: cover property (
    @(posedge clk) disable iff (~rst_l)
      (lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma &&
       addr_external_dc2 && !start_addr_in_dccm_region_dc2 &&
       !start_addr_in_pic_region_dc2)
  );
  `endif
  // synopsys translate_on

endmodule
