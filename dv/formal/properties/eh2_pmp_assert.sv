// ============================================================================
// eh2_pmp_assert.sv — MPU/PMP 占位 SVA 骨架
//
// EH2 使用 DATA_ACCESS_ENABLEn / DATA_ACCESS_ADDRn / DATA_ACCESS_MASKn
// 参数在 eh2_lsu_addrcheck 模块中实现类 PMP 的 MPU 访问保护。
// 当地址不在任何已启用的 region 内时，mpu_access_fault_dc2 置高。
//
// 本文件包含 3 条占位 SVA，需由验证工程师替换为真正的属性。
// ============================================================================

module eh2_pmp_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        rst_l,

  // --- eh2_lsu_addrcheck 关键信号 ---
  input logic [31:0] start_addr_dc2,
  input logic        access_fault_dc2,
  input logic        mpu_access_fault_dc2,
  input logic        unmapped_access_fault_dc2,
  input logic        lsu_pkt_dc2_valid,       // lsu_pkt_dc2.valid
  input logic        lsu_pkt_dc2_dma,         // lsu_pkt_dc2.dma
  input logic        non_dccm_access_ok,
  input logic        start_addr_in_dccm_region_dc2,
  input logic        start_addr_in_pic_region_dc2
);

  // ========================================================================
  // Property 1: MPU region 全部禁用时，外部地址不应产生 MPU fault
  //
  // 当所有 DATA_ACCESS_ENABLEn == 0 时，non_dccm_access_ok 恒为 1，
  // 因此 mpu_access_fault_dc2 不应触发。
  //
  // TODO: real property by human — 需根据实际参数配置细化约束
  // ========================================================================
  // synopsys translate_off
  `ifdef FORMAL
  property p_mpu_all_disabled_no_fault;
    @(posedge clk) disable iff (~rst_l)
      // TODO: real property by human
      // Placeholder: 当 non_dccm_access_ok 为高时，mpu_access_fault 不应触发
      (non_dccm_access_ok && lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> !mpu_access_fault_dc2;
  endproperty
  a_mpu_all_disabled_no_fault: assert property (p_mpu_all_disabled_no_fault)
    else $error("FORMAL FAIL: MPU fault fired when region access was OK");
  `endif
  // synopsys translate_on

  // ========================================================================
  // Property 2: 地址落在 DCCM/PIC region 内时，不应触发 MPU fault
  //
  // mpu_access_fault_dc2 仅在地址不在 dccm_region 且不在 pic_region 时触发。
  //
  // TODO: real property by human — 需补充 DCCM_ENABLE 条件分支
  // ========================================================================
  // synopsys translate_off
  `ifdef FORMAL
  property p_internal_region_no_mpu_fault;
    @(posedge clk) disable iff (~rst_l)
      // TODO: real property by human
      // Placeholder: 地址在 DCCM 或 PIC region 内 → 无 MPU fault
      ((start_addr_in_dccm_region_dc2 || start_addr_in_pic_region_dc2) &&
        lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> !mpu_access_fault_dc2;
  endproperty
  a_internal_region_no_mpu_fault: assert property (p_internal_region_no_mpu_fault)
    else $error("FORMAL FAIL: MPU fault in DCCM/PIC region");
  `endif
  // synopsys translate_on

  // ========================================================================
  // Property 3: 外部地址不在任何 enabled region 时，必须触发 access fault
  //
  // 当地址不在 DCCM/PIC region，且 non_dccm_access_ok == 0 时，
  // access_fault_dc2 必须置高（经 mpu_access_fault_dc2 贡献）。
  //
  // TODO: real property by human — 需排除 DMA 事务和其他 fault 源
  // ========================================================================
  // synopsys translate_off
  `ifdef FORMAL
  property p_unmapped_external_triggers_fault;
    @(posedge clk) disable iff (~rst_l)
      // TODO: real property by human
      // Placeholder: 外部地址 + region 不可达 → access fault
      (!start_addr_in_dccm_region_dc2 && !start_addr_in_pic_region_dc2 &&
       !non_dccm_access_ok &&
       lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
        |-> access_fault_dc2;
  endproperty
  a_unmapped_external_triggers_fault: assert property (p_unmapped_external_triggers_fault)
    else $error("FORMAL FAIL: no access fault for unmapped external address");
  `endif
  // synopsys translate_on

endmodule
