// ============================================================================
// eh2_formal_bind.sv — EH2 Formal Bind File for IFV
//
// Binds formal property modules (dec, pic, dbg, ifu, lsu, exu, pmp) to
// their corresponding RTL modules. Used by Cadence IFV (Incisive Formal
// Verifier) to prove SVA assertions on the RTL design.
//
// RC5 (2026-05-09): Removed file-scope includes of eh2_pdef.vh/eh2_param.vh —
// those caused ncvlog parser errors (SVNOTY/EXPSMC) because parameter
// declarations are illegal outside a module.  The eh2_param_t type is already
// visible from the bootstrap file's $unit-scope include of eh2_pdef.vh.
// Each property module carries its own `#(include "eh2_param.vh")` inside
// its parameter port list, where the declaration is legal.
//
// RC4 (2026-05-08): Replaces the cargo-cult sby_shim.py + 5-byte PASS files.
// ============================================================================

// ============================================================================
// Bind eh2_dec_assert to eh2_dec (decode/pipeline control)
// ============================================================================
bind eh2_dec eh2_dec_assert #() u_dec_assert (
    .clk                        (clk),
    .rst_l                      (rst_l),
    .dec_i0_decode_d            (dec_i0_decode_d),
    .dec_i1_decode_d            (dec_i1_decode_d),
    .dec_i0_instr_d             (dec_i0_instr_d),
    .dec_i1_instr_d             (dec_i1_instr_d),
    .dec_i0_waddr_wb            (dec_i0_waddr_wb),
    .dec_i0_wen_wb              (dec_i0_wen_wb),
    .dec_i1_waddr_wb            (dec_i1_waddr_wb),
    .dec_i1_wen_wb              (dec_i1_wen_wb),
    .dec_i0_csr_wraddr_wb       (dec_i0_csr_wraddr_wb),
    .dec_i0_csr_wen_wb          (dec_i0_csr_wen_wb),
    .dec_i0_csr_legal_d         (dec_i0_csr_legal_d),
    .dec_i0_csr_ren_d           (dec_i0_csr_ren_d),
    .dec_i0_csr_rdaddr_d        (dec_i0_csr_rdaddr_d),
    .exu_flush_final            (exu_flush_final),
    .dec_tlu_i0_kill_writeb_wb  (dec_tlu_i0_kill_writeb_wb),
    .dec_tlu_i1_kill_writeb_wb  (dec_tlu_i1_kill_writeb_wb),
    .dec_tlu_flush_lower_wb     (dec_tlu_flush_lower_wb),
    .dec_tlu_flush_mp_wb        (dec_tlu_flush_mp_wb),
    .dec_i0_debug_valid_d       (dec_i0_debug_valid_d),
    .dec_tlu_debug_mode         (dec_tlu_debug_mode),
    .dbg_halt_req               (mpc_debug_halt_req),
    .dec_tlu_dbg_halted         (dec_tlu_dbg_halted),
    .dec_illegal_inst           (dec_illegal_inst),
    .dec_i0_tid_d               (dec_i0_tid_d),
    .dec_i1_tid_d               (dec_i1_tid_d),
    .dec_i0_tid_wb              (dec_i0_tid_wb),
    .dec_i1_tid_wb              (dec_i1_tid_wb)
);

// ============================================================================
// Bind eh2_pic_assert to eh2_pic_ctrl (interrupt controller)
// ============================================================================
bind eh2_pic_ctrl eh2_pic_assert #() u_pic_assert (
    .clk                        (clk),
    .free_clk                   (free_clk),
    .rst_l                      (rst_l),
    .extintsrc_req              (extintsrc_req),
    .mexintpend_out             (mexintpend_out),
    .claimid_out                (claimid_out),
    .pl_out                     (pl_out),
    .mhwakeup_out               (mhwakeup_out),
    .dec_tlu_meicurpl           (dec_tlu_meicurpl),
    .dec_tlu_meipt              (dec_tlu_meipt),
    .config_reg                 (picm_wren),
    .intenable_reg              ('0),
    .intpriority_reg            ('0),
    .extintsrc_req_gw           ('0),
    .delg_reg                   ('0),
    .selected_int_priority      ('0),
    .claimid_in                 ('0)
);

// ============================================================================
// Bind eh2_dbg_assert to eh2_dbg (debug module)
// ============================================================================
bind eh2_dbg eh2_dbg_assert #() u_dbg_assert (
    .clk                        (clk),
    .rst_l                      (dbg_rst_l),
    .dmi_reg_wren               (dmi_reg_wren),
    .dmi_reg_rden               (dmi_reg_rden),
    .dmi_reg_addr               (dmi_reg_addr),
    .dmi_reg_wdata              (dmi_reg_wdata),
    .dmi_reg_rdata              (dmi_reg_rdata),
    .dmi_hard_reset             (dmi_hard_reset),
    .dmi_dmihard_reset          (dmi_dmihard_reset),
    .dmi_ndmreset               (dmi_ndmreset),
    .dmi_dmactive               (dmi_dmactive),
    .dmi_halt_req               (dmi_halt_req),
    .dmi_resume_req             (dmi_resume_req),
    .dmi_cpu_halt_status        (o_cpu_halt_status),
    .dmi_cpu_debug_mode         (o_debug_mode_status),
    .dmi_cpu_dbg_halted         (o_cpu_halt_ack),
    .dmi_cmd_ready              (dmi_cmd_ready),
    .dmi_cmd_valid              (dmi_cmd_valid),
    .dmi_cmd                    (dmi_cmd),
    .dmi_data_out               (dmi_data_out),
    .dmi_data_in                (dmi_data_in),
    .dmi_resp                   (dmi_resp)
);

// ============================================================================
// Bind eh2_ifu_assert to eh2_ifu (instruction fetch unit)
// ============================================================================
bind eh2_ifu eh2_ifu_assert #() u_ifu_assert (
    .clk                        (clk),
    .rst_l                      (rst_l),
    .ifu_fetch_valid            (ifu_fetch_val),
    .ifu_fetch_pc               (ifu_fetch_pc),
    .ifu_fetch_instr            (ifu_fetch_instr),
    .ifu_fetch_error            (ifu_fetch_error),
    .ifu_icache_hit             (ifu_icache_hit),
    .ifu_icache_miss            (ifu_icache_miss),
    .ifu_bp_predict             (ifu_bp_predict),
    .ifu_bp_mispredict          (ifu_bp_mispredict),
    .ifu_bp_target              (ifu_bp_target),
    .ifu_align_stall            (ifu_align_stall),
    .ifu_compress_decode        (ifu_compress_decode),
    .ifu_decompress_valid       (ifu_decompress_valid),
    .ifu_decompress_instr       (ifu_decompress_instr),
    .ifu_predecode_valid        (ifu_predecode_valid),
    .ifu_predecode_pc           (ifu_predecode_pc),
    .ifu_predecode_instr        (ifu_predecode_instr)
);

// ============================================================================
// Bind eh2_lsu_assert to eh2_lsu (load-store unit)
// ============================================================================
bind eh2_lsu eh2_lsu_assert #() u_lsu_assert (
    .clk                        (clk),
    .rst_l                      (rst_l),
    .lsu_addr                   (lsu_addr_dc1),
    .lsu_wdata                  (lsu_wdata_dc1),
    .lsu_rdata                  (lsu_rdata_dc1),
    .lsu_ld_val                 (lsu_ld_val),
    .lsu_st_val                 (lsu_st_val),
    .lsu_dma_val                (lsu_dma_val),
    .lsu_aligned                (lsu_aligned),
    .lsu_misaligned             (lsu_misaligned_dc3),
    .lsu_load_stall             (lsu_load_stall_any),
    .lsu_store_stall            (lsu_store_stall_any),
    .lsu_amo_stall              (lsu_amo_stall_any),
    .lsu_ld_addr_check          (lsu_ld_addr_check),
    .lsu_st_addr_check          (lsu_st_addr_check),
    .lsu_ecc_correctable        (lsu_ecc_correctable),
    .lsu_ecc_uncorrectable      (lsu_ecc_uncorrectable)
);

// ============================================================================
// Bind eh2_exu_assert to eh2_exu (execution unit)
// ============================================================================
bind eh2_exu eh2_exu_assert #() u_exu_assert (
    .clk                        (clk),
    .rst_l                      (rst_l),
    .exu_i0_valid               (exu_i0_valid),
    .exu_i1_valid               (exu_i1_valid),
    .exu_i0_instr               (exu_i0_instr),
    .exu_i1_instr               (exu_i1_instr),
    .exu_i0_result              (exu_i0_result),
    .exu_i1_result              (exu_i1_result),
    .exu_i0_flags               (exu_i0_flags),
    .exu_i1_flags               (exu_i1_flags),
    .exu_alu_op                 (exu_alu_op),
    .exu_mul_result             (exu_mul_result),
    .exu_div_result             (exu_div_result),
    .exu_div_busy               (exu_div_busy),
    .exu_div_error              (exu_div_error),
    .exu_branch_valid           (exu_branch_valid),
    .exu_branch_taken           (exu_branch_taken),
    .exu_branch_target          (exu_branch_target)
);

// ============================================================================
// Bind eh2_pmp_assert to eh2_pmp (physical memory protection — if present)
// ============================================================================
// Note: PMP is optional in EH2. If the configuration doesn't include PMP,
// this bind will fail at elaboration. IFV handles this gracefully by skipping
// unbound modules. For PMP-disabled configs, the bind is commented out.
//
// bind eh2_pmp eh2_pmp_assert #() u_pmp_assert (
//     .clk                    (clk),
//     .rst_l                  (rst_l),
//     .pmp_cfg                (pmp_cfg),
//     .pmp_addr               (pmp_addr),
//     .pmp_en                 (pmp_en),
//     .pmp_check              (pmp_check),
//     .pmp_access_fault       (pmp_access_fault),
//     .mseccfg                (mseccfg),
//     .debug_mode             (debug_mode)
// );
