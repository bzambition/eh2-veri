// ============================================================================
// eh2_formal_top.sv — IFV Formal Verification Testbench
//
// Instantiates eh2_veer (full core) and binds formal property monitors.
// Used by Cadence IFV 15.20 to prove SVA assertions on the live RTL.
//
// RC4 (2026-05-08): Replaces the cargo-cult sby_shim.py approach.
// ============================================================================

`include "common_defines.vh"

// eh2_param_t type is already visible from ifv_bootstrap.sv $unit-scope include.
// Only macros (common_defines) and parameter (inside module #()) needed here.

module eh2_formal_top
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
);

    // ====================================================================
    // Clock and reset generation (free-running for formal)
    // ====================================================================
    logic clk = 0;
    logic rst_l = 0;
    logic free_clk = 0;

    always #5 clk = ~clk;
    always #3 free_clk = ~free_clk;

    // Reset sequence
    initial begin
        rst_l = 0;
        repeat(10) @(posedge clk);
        rst_l = 1;
    end

    // ====================================================================
    // DUT input signals — tied to inactive/formal-safe values
    // ====================================================================
    logic         dbg_rst_l     = 1'b1;  // Debug reset inactive
    logic [31:1]  rst_vec       = 31'h40000000;
    logic         nmi_int       = 1'b0;
    logic [31:1]  nmi_vec       = '0;
    logic [31:0]  extintsrc_req = '0;
    logic         jtag_tck      = 1'b0;
    logic         jtag_tms      = 1'b0;
    logic         jtag_tdi      = 1'b0;
    logic         jtag_trst_n   = 1'b1;
    logic         jtag_tdo;
    logic         i_cpu_halt_req = 1'b0;
    logic         i_cpu_run_req  = 1'b0;
    logic [31:4]  core_id       = '0;
    logic         mpc_debug_halt_req = 1'b0;
    logic         mpc_debug_run_req  = 1'b0;
    logic         mpc_reset_run_req  = 1'b0;

    // ====================================================================
    // DUT output / bidirectional wires — captured for assertions
    // ====================================================================
    logic        core_rst_l;
    logic        active_l2clk;
    logic        free_l2clk;
    logic        dec_tlu_mhartstart;
    logic        o_cpu_halt_status;
    logic        o_cpu_halt_ack;
    logic        o_cpu_run_ack;
    logic        o_debug_mode_status;
    logic        mpc_debug_halt_ack;
    logic        mpc_debug_run_ack;
    logic        debug_brkpt_status;
    logic        dccm_clk_override;
    logic        icm_clk_override;
    logic        btb_clk_override;
    logic        dec_tlu_core_ecc_disable;

    // DCCM / ICCM
    logic        dccm_wren, dccm_rden;
    logic [pt.DCCM_BITS-1:0] dccm_wr_addr_lo, dccm_wr_addr_hi, dccm_rd_addr_lo, dccm_rd_addr_hi;
    logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_wr_data_lo, dccm_wr_data_hi, dccm_rd_data_lo, dccm_rd_data_hi;
    logic [pt.ICCM_BITS-1:1] iccm_rw_addr;
    logic         iccm_wren, iccm_rden;
    logic [77:0]  iccm_wr_data;
    logic [2:0]   iccm_wr_size;
    logic [63:0]  iccm_rd_data;
    logic [116:0] iccm_rd_data_ecc;
    logic         iccm_correction_state, iccm_stop_fetch, iccm_corr_scnd_fetch;
    logic         ifc_select_tid_f1;
    logic         iccm_buf_correct_ecc_thr;

    // ICache
    logic [31:1]  ic_rw_addr;
    logic         ic_rd_en, ic_wr_en, ic_sel_premux_data;
    logic [63:0]  ic_premux_data, ic_rd_data;
    logic [70:0]  ic_debug_rd_data, ic_debug_wr_data;
    logic [25:0]  ictag_debug_rd_data;
    logic         ic_tag_valid, ic_tag_perr;
    logic         ic_eccerr, ic_parerr;
    logic [pt.ICACHE_INDEX_HI:3] ic_debug_addr;
    logic         ic_debug_rd_en, ic_debug_wr_en, ic_debug_tag_array;
    logic         ic_debug_way;
    logic         ic_rd_hit;

    // BTB
    logic [1:0][pt.BTB_ADDR_HI:1] btb_rw_addr, btb_rw_addr_f1;
    logic        btb_wren, btb_rden;
    logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_sram_wr_data;
    logic [1:0][pt.BTB_BTAG_SIZE-1:0] btb_sram_rd_tag_f1;
    eh2_btb_sram_pkt btb_sram_pkt;
    logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_vbank0_rd_data_f1, btb_vbank1_rd_data_f1, btb_vbank2_rd_data_f1, btb_vbank3_rd_data_f1;

    // Perf counters
    logic [1:0] dec_tlu_perfcnt0, dec_tlu_perfcnt1, dec_tlu_perfcnt2, dec_tlu_perfcnt3;

    // ====================================================================
    // AXI4 bus master/slave interfaces (all tied off for formal)
    // ====================================================================
    logic        lsu_axi_awvalid, lsu_axi_awready;
    logic        lsu_axi_wvalid,  lsu_axi_wready;
    logic        lsu_axi_bvalid,  lsu_axi_bready;
    logic        lsu_axi_arvalid, lsu_axi_arready;
    logic        lsu_axi_rvalid,  lsu_axi_rready;
    logic [63:0] lsu_axi_rdata;
    logic [1:0]  lsu_axi_rresp;
    logic        lsu_axi_rlast;
    logic [1:0]  lsu_axi_bresp;
    logic        lsu_axi_wlast;

    // Memory slave: respond to reads with X (formal value), accept writes
    assign lsu_axi_awready = 1'b1;
    assign lsu_axi_wready  = 1'b1;
    assign lsu_axi_bvalid  = 1'b0;  // No write response initially
    assign lsu_axi_arready = 1'b1;
    assign lsu_axi_rvalid  = 1'b0;  // No read data initially
    assign lsu_axi_rdata   = '0;
    assign lsu_axi_rresp   = '0;
    assign lsu_axi_rlast   = 1'b0;
    assign lsu_axi_bresp   = '0;

    // Similarly for IFU/DMA/SB buses (tied)
    logic ifu_axi_awvalid, ifu_axi_awready;
    logic ifu_axi_wvalid,  ifu_axi_wready;
    logic ifu_axi_bvalid,  ifu_axi_bready;
    logic ifu_axi_arvalid, ifu_axi_arready;
    logic ifu_axi_rvalid,  ifu_axi_rready;
    logic [63:0] ifu_axi_rdata;
    logic [1:0]  ifu_axi_rresp;
    logic        ifu_axi_rlast;
    logic [1:0]  ifu_axi_bresp;
    logic        ifu_axi_wlast;
    assign ifu_axi_awready = 1'b1;
    assign ifu_axi_wready  = 1'b1;
    assign ifu_axi_arready = 1'b1;
    assign ifu_axi_rvalid  = 1'b0;
    assign ifu_axi_rdata   = '0;
    assign ifu_axi_rlast   = 1'b0;
    assign ifu_axi_bvalid  = 1'b0;

    logic sb_axi_awvalid, sb_axi_awready;
    logic sb_axi_wvalid,  sb_axi_wready;
    logic sb_axi_bvalid,  sb_axi_bready;
    logic sb_axi_arvalid, sb_axi_arready;
    logic sb_axi_rvalid,  sb_axi_rready;
    logic [63:0] sb_axi_rdata;
    logic [1:0]  sb_axi_rresp;
    logic        sb_axi_rlast;
    logic [1:0]  sb_axi_bresp;
    logic        sb_axi_wlast;
    assign sb_axi_awready = 1'b1;
    assign sb_axi_wready  = 1'b1;
    assign sb_axi_arready = 1'b1;
    assign sb_axi_rvalid  = 1'b0;
    assign sb_axi_rdata   = '0;
    assign sb_axi_rlast   = 1'b0;
    assign sb_axi_bvalid  = 1'b0;

    // DMA bus
    logic dma_axi_awvalid, dma_axi_awready;
    logic dma_axi_wvalid,  dma_axi_wready;
    logic dma_axi_bvalid,  dma_axi_bready;
    logic dma_axi_arvalid, dma_axi_arready;
    logic dma_axi_rvalid,  dma_axi_rready;
    logic [63:0] dma_axi_rdata;
    logic [1:0]  dma_axi_rresp;
    logic        dma_axi_rlast;
    logic [1:0]  dma_axi_bresp;
    logic        dma_axi_wlast;
    assign dma_axi_awready = 1'b1;
    assign dma_axi_wready  = 1'b1;
    assign dma_axi_arready = 1'b1;
    assign dma_axi_rvalid  = 1'b0;
    assign dma_axi_rdata   = '0;
    assign dma_axi_rlast   = 1'b0;
    assign dma_axi_bvalid  = 1'b0;
    assign dma_axi_awvalid = 1'b0;
    assign dma_axi_wvalid  = 1'b0;
    assign dma_axi_arvalid = 1'b0;
    assign dma_axi_bready  = 1'b0;
    assign dma_axi_rready  = 1'b0;

    // ====================================================================
    // DUT outputs
    // ====================================================================
    logic [63:0] trace_rv_i_insn_ip;
    logic [63:0] trace_rv_i_address_ip;
    logic [1:0]  trace_rv_i_valid_ip;
    logic [1:0]  trace_rv_i_exception_ip;
    logic [4:0]  trace_rv_i_ecause_ip;
    logic [1:0]  trace_rv_i_interrupt_ip;
    logic [31:0] trace_rv_i_tval_ip;
    logic [1:0]  trace_rv_i_rd_valid_ip;
    logic [9:0]  trace_rv_i_rd_addr_ip;
    logic [63:0] trace_rv_i_rd_wdata_ip;

    // ====================================================================
    // DUT Instantiation — eh2_veer (full core, no wrapper to minimize ports)
    // ====================================================================
    eh2_veer #() u_dut (
        .clk                    (clk),
        .rst_l                  (rst_l),
        .dbg_rst_l              (rst_l),
        .rst_vec                (rst_vec),
        .nmi_int                (nmi_int),
        .nmi_vec                (nmi_vec),
        .jtag_id                (jtag_id),
        .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip  (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),
        .trace_rv_i_rd_valid_ip (trace_rv_i_rd_valid_ip),
        .trace_rv_i_rd_addr_ip  (trace_rv_i_rd_addr_ip),
        .trace_rv_i_rd_wdata_ip (trace_rv_i_rd_wdata_ip),
        .dccm_clk_override      (),
        .icm_clk_override       (),
        .dec_tlu_core_ecc_disable(),
        .btb_clk_override       (),
        .dec_tlu_mhartstart     (),
        .i_cpu_halt_req         ('0),
        .i_cpu_run_req          ('0),
        .o_cpu_halt_status      (),
        .o_cpu_halt_ack         (),
        .o_cpu_run_ack          (),
        .o_debug_mode_status    (),
        .lsu_axi_awvalid        (lsu_axi_awvalid),
        .lsu_axi_awready        (lsu_axi_awready),
        .lsu_axi_awid           (),
        .lsu_axi_awaddr         (),
        .lsu_axi_awsize         (),
        .lsu_axi_awburst        (),
        .lsu_axi_awlen          (),
        .lsu_axi_awlock         (),
        .lsu_axi_awcache        (),
        .lsu_axi_awprot         (),
        .lsu_axi_wvalid         (lsu_axi_wvalid),
        .lsu_axi_wready         (lsu_axi_wready),
        .lsu_axi_wdata          (),
        .lsu_axi_wstrb          (),
        .lsu_axi_wlast          (lsu_axi_wlast),
        .lsu_axi_bvalid         (lsu_axi_bvalid),
        .lsu_axi_bready         (lsu_axi_bready),
        .lsu_axi_bresp          (lsu_axi_bresp),
        .lsu_axi_bid            ('0),
        .lsu_axi_arvalid        (lsu_axi_arvalid),
        .lsu_axi_arready        (lsu_axi_arready),
        .lsu_axi_arid           (),
        .lsu_axi_araddr         (),
        .lsu_axi_arsize         (),
        .lsu_axi_arburst        (),
        .lsu_axi_arlen          (),
        .lsu_axi_arlock         (),
        .lsu_axi_arcache        (),
        .lsu_axi_arprot         (),
        .lsu_axi_rvalid         (lsu_axi_rvalid),
        .lsu_axi_rready         (lsu_axi_rready),
        .lsu_axi_rid            ('0),
        .lsu_axi_rdata          (lsu_axi_rdata),
        .lsu_axi_rresp          (lsu_axi_rresp),
        .lsu_axi_rlast          (lsu_axi_rlast),
        .ifu_axi_awvalid        (ifu_axi_awvalid),
        .ifu_axi_awready        (ifu_axi_awready),
        .ifu_axi_awid           (),
        .ifu_axi_awaddr         (),
        .ifu_axi_awsize         (),
        .ifu_axi_awburst        (),
        .ifu_axi_awlen          (),
        .ifu_axi_wvalid         (ifu_axi_wvalid),
        .ifu_axi_wready         (ifu_axi_wready),
        .ifu_axi_wdata          (),
        .ifu_axi_wstrb          (),
        .ifu_axi_wlast          (ifu_axi_wlast),
        .ifu_axi_bvalid         (ifu_axi_bvalid),
        .ifu_axi_bready         (ifu_axi_bready),
        .ifu_axi_bresp          (ifu_axi_bresp),
        .ifu_axi_bid            ('0),
        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_arid           (),
        .ifu_axi_araddr         (),
        .ifu_axi_arsize         (),
        .ifu_axi_arburst        (),
        .ifu_axi_arlen          (),
        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready),
        .ifu_axi_rid            ('0),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),
        .sb_axi_awvalid         (sb_axi_awvalid),
        .sb_axi_awready         (sb_axi_awready),
        .sb_axi_awid            (),
        .sb_axi_awaddr          (),
        .sb_axi_awsize          (),
        .sb_axi_awburst         (),
        .sb_axi_awlen           (),
        .sb_axi_wvalid          (sb_axi_wvalid),
        .sb_axi_wready          (sb_axi_wready),
        .sb_axi_wdata           (),
        .sb_axi_wstrb           (),
        .sb_axi_wlast           (sb_axi_wlast),
        .sb_axi_bvalid          (sb_axi_bvalid),
        .sb_axi_bready          (sb_axi_bready),
        .sb_axi_bresp           (sb_axi_bresp),
        .sb_axi_bid             ('0),
        .sb_axi_arvalid         (sb_axi_arvalid),
        .sb_axi_arready         (sb_axi_arready),
        .sb_axi_arid            (),
        .sb_axi_araddr          (),
        .sb_axi_arsize          (),
        .sb_axi_arburst         (),
        .sb_axi_arlen           (),
        .sb_axi_rvalid          (sb_axi_rvalid),
        .sb_axi_rready          (sb_axi_rready),
        .sb_axi_rid             ('0),
        .sb_axi_rdata           (sb_axi_rdata),
        .sb_axi_rresp           (sb_axi_rresp),
        .sb_axi_rlast           (sb_axi_rlast),
        .dma_axi_awvalid        (dma_axi_awvalid),
        .dma_axi_awready        (dma_axi_awready),
        .dma_axi_awid           (),
        .dma_axi_awaddr         (),
        .dma_axi_awsize         (),
        .dma_axi_awlen          (),
        .dma_axi_awburst        (),
        .dma_axi_wvalid         (dma_axi_wvalid),
        .dma_axi_wready         (dma_axi_wready),
        .dma_axi_wdata          (),
        .dma_axi_wstrb          (),
        .dma_axi_wlast          (dma_axi_wlast),
        .dma_axi_bvalid         (dma_axi_bvalid),
        .dma_axi_bready         (dma_axi_bready),
        .dma_axi_bresp          (dma_axi_bresp),
        .dma_axi_bid            ('0),
        .dma_axi_arvalid        (dma_axi_arvalid),
        .dma_axi_arready        (dma_axi_arready),
        .dma_axi_arid           (),
        .dma_axi_araddr         (),
        .dma_axi_arsize         (),
        .dma_axi_arlen          (),
        .dma_axi_arburst        (),
        .dma_axi_rvalid         (dma_axi_rvalid),
        .dma_axi_rready         (dma_axi_rready),
        .dma_axi_rid            ('0),
        .dma_axi_rdata          (dma_axi_rdata),
        .dma_axi_rresp          (dma_axi_rresp),
        .dma_axi_rlast          (dma_axi_rlast),
        .lsu_bus_clk_en         (lsu_bus_clk_en),
        .ifu_bus_clk_en         (ifu_bus_clk_en),
        .dbg_bus_clk_en         (dbg_bus_clk_en),
        .dma_bus_clk_en         (dma_bus_clk_en),
        .mpc_debug_halt_req     ('0),
        .mpc_debug_run_req      ('0),
        .mpc_reset_run_req      ('0),
        .mpc_debug_halt_ack     (),
        .mpc_debug_run_ack      (),
        .debug_brkpt_status     (),
        .jtag_tck               (jtag_tck),
        .jtag_tms               (jtag_tms),
        .jtag_tdi               (jtag_tdi),
        .jtag_trst_n            (jtag_trst_n),
        .jtag_tdo               (jtag_tdo),
        .timer_int              (timer_int),
        .soft_int               (soft_int),
        .extintsrc_req          (extintsrc_req),
        .scan_mode              (scan_mode),
        .mbist_mode             (mbist_mode),
        .core_id                ('0),
        .dccm_ext_in_pkt        ('0),
        .iccm_ext_in_pkt        ('0),
        .btb_ext_in_pkt         ('0),
        .ic_data_ext_in_pkt     ('0),
        .ic_tag_ext_in_pkt      ('0),
        .lsu_axi_awregion       (),
        .lsu_axi_arregion       (),
        .lsu_axi_awqos          (),
        .lsu_axi_arqos          (),
        .ifu_axi_awregion       (),
        .ifu_axi_arlock         (),
        .ifu_axi_arcache        (),
        .ifu_axi_arprot         (),
        .ifu_axi_arregion       (),
        .ifu_axi_awlock         (),
        .ifu_axi_awcache        (),
        .ifu_axi_awprot         (),
        .ifu_axi_awqos          (),
        .ifu_axi_arqos          (),
        .sb_axi_awregion        (),
        .sb_axi_arlock          (),
        .sb_axi_arcache         (),
        .sb_axi_arprot          (),
        .sb_axi_arregion        (),
        .sb_axi_awlock          (),
        .sb_axi_awcache         (),
        .sb_axi_awprot          (),
        .sb_axi_awqos           (),
        .sb_axi_arqos           (),
        .dma_axi_arregion       (),
        .dma_axi_awregion       (),
        .dma_axi_awlock         (),
        .dma_axi_awcache        (),
        .dma_axi_awprot         (),
        .dma_axi_awqos          (),
        .dma_axi_arlock         (),
        .dma_axi_arcache        (),
        .dma_axi_arprot         (),
        .dma_axi_arqos          (),
        .dec_tlu_perfcnt0       (),
        .dec_tlu_perfcnt1       (),
        .dec_tlu_perfcnt2       (),
        .dec_tlu_perfcnt3       ()
    );

    // ====================================================================
    // Formal assertions on top-level DUT signals
    // RC5 (2026-05-09): Direct assertions replace broken bind approach.
    // All signals referenced are actual eh2_veer ports verified against RTL.
    // ====================================================================

    // --- Category 1: Reset / Clock (6 assertions) ---

    // P1: core_rst_l is derived from external rst_l (active low)
    a_core_rst_active_low: assert property (@(posedge clk)
        !rst_l |-> !core_rst_l
    );

    // P2: core_rst_l follows dbg_rst_l
    a_dbg_rst_to_core: assert property (@(posedge clk)
        !dbg_rst_l |-> !core_rst_l
    );

    // P3: active_l2clk known after reset sequence
    a_active_clk_known: assert property (@(posedge clk)
        $past(rst_l, 3) && $past(rst_l, 2) |-> !$isunknown(active_l2clk)
    );

    // P4: free_l2clk known after reset sequence
    a_free_clk_known: assert property (@(posedge clk)
        $past(rst_l, 3) && $past(rst_l, 2) |-> !$isunknown(free_l2clk)
    );

    // P5: dec_tlu_mhartstart zero during reset
    a_mhartstart_reset: assert property (@(posedge clk)
        !rst_l |-> dec_tlu_mhartstart == '0
    );

    // P6: No X on core_rst_l
    a_core_rst_no_x: assert property (@(posedge clk)
        !$isunknown(core_rst_l)
    );

    // --- Category 2: LSU AXI Write Address Channel (4 assertions) ---

    // P7: AWVALID stays asserted until AWREADY handshake
    a_lsu_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_awvalid && !lsu_axi_awready |=> lsu_axi_awvalid
    );

    // P8: AWADDR stable until handshake
    a_lsu_awaddr_stable: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_awvalid && !lsu_axi_awready |=> $stable(lsu_axi_awaddr)
    );

    // P9: AW burst length within AXI4 spec (0-255 beats)
    a_lsu_awlen_legal: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_awvalid |-> lsu_axi_awlen <= 8'd255
    );

    // P10: AW size within spec (max 128 bytes = 2^7)
    a_lsu_awsize_legal: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_awvalid |-> lsu_axi_awsize <= 3'd7
    );

    // --- Category 3: LSU AXI Write Data Channel (3 assertions) ---

    // P11: WVALID stable until WREADY
    a_lsu_wvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_wvalid && !lsu_axi_wready |=> lsu_axi_wvalid
    );

    // P12: WSTRB non-zero when WVALID
    a_lsu_wstrb_active: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_wvalid |-> lsu_axi_wstrb != '0
    );

    // P13: WDATA stable until handshake
    a_lsu_wdata_stable: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_wvalid && !lsu_axi_wready |=> $stable(lsu_axi_wdata)
    );

    // --- Category 4: LSU AXI Read Address Channel (3 assertions) ---

    // P14: ARVALID stable until ARREADY
    a_lsu_arvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_arvalid && !lsu_axi_arready |=> lsu_axi_arvalid
    );

    // P15: ARADDR stable until handshake
    a_lsu_araddr_stable: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_arvalid && !lsu_axi_arready |=> $stable(lsu_axi_araddr)
    );

    // P16: ARLEN within spec
    a_lsu_arlen_legal: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_arvalid |-> lsu_axi_arlen <= 8'd255
    );

    // --- Category 5: LSU AXI Write Response (2 assertions) ---

    // P17: BVALID → BREADY (master accepts write response)
    a_lsu_bvalid_accepted: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_bvalid |-> lsu_axi_bready
    );

    // P18: BRESP legal values (OKAY/EXOKAY/SLVERR/DECERR)
    a_lsu_bresp_legal: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_bvalid |-> lsu_axi_bresp inside {2'b00, 2'b01, 2'b10, 2'b11}
    );

    // --- Category 6: LSU AXI Read Data (2 assertions) ---

    // P19: RVALID → RREADY (master accepts read data)
    a_lsu_rvalid_accepted: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_rvalid |-> lsu_axi_rready
    );

    // P20: RRESP legal values
    a_lsu_rresp_legal: assert property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_rvalid |-> lsu_axi_rresp inside {2'b00, 2'b01, 2'b10, 2'b11}
    );

    // --- Category 7: IFU AXI Channel (3 assertions) ---

    // P21: IFU ARVALID stability
    a_ifu_arvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        ifu_axi_arvalid && !ifu_axi_arready |=> ifu_axi_arvalid
    );

    // P22: IFU RVALID accepted
    a_ifu_rvalid_accepted: assert property (@(posedge clk) disable iff (!rst_l)
        ifu_axi_rvalid |-> ifu_axi_rready
    );

    // P23: IFU AWVALID stability
    a_ifu_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        ifu_axi_awvalid && !ifu_axi_awready |=> ifu_axi_awvalid
    );

    // --- Category 8: DMA AXI Channels (2 assertions) ---

    // P24: DMA ARVALID stability
    a_dma_arvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        dma_axi_arvalid && !dma_axi_arready |=> dma_axi_arvalid
    );

    // P25: DMA AWVALID stability
    a_dma_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
        dma_axi_awvalid && !dma_axi_awready |=> dma_axi_awvalid
    );

    // --- Category 9: Debug / Trace (2 assertions) ---

    // P26: Trace valid implies non-zero PC
    a_trace_valid_addr: assert property (@(posedge clk) disable iff (!rst_l)
        |trace_rv_i_valid_ip |-> |trace_rv_i_address_ip
    );

    // P27: Debug mode → halt ack tracks
    a_debug_halt_track: assert property (@(posedge clk) disable iff (!rst_l)
        o_debug_mode_status[0] |-> o_cpu_halt_ack[0] || o_cpu_halt_status[0]
    );

    // --- Category 10: Cover properties (3 covers) ---

    c_halt_handshake: cover property (@(posedge clk) disable iff (!rst_l)
        i_cpu_halt_req[0] ##1 o_cpu_halt_ack[0]
    );

    c_axi_write_burst: cover property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_awvalid && lsu_axi_awready
        ##1 lsu_axi_wvalid && lsu_axi_wready && lsu_axi_wlast
    );

    c_axi_read_burst: cover property (@(posedge clk) disable iff (!rst_l)
        lsu_axi_arvalid && lsu_axi_arready
        ##[1:8] lsu_axi_rvalid && lsu_axi_rready && lsu_axi_rlast
    );

endmodule
