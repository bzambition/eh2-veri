// LEC-ONLY wrapper. Not for simulation and not for production synthesis.
// Old Formality O-2018.06-SP1 mishandles selected 2D packed-array top ports.
// This wrapper exposes the trace/RVFI-style outputs as 1D vectors while keeping
// the inner eh2_veer instance unchanged.

module eh2_veer_lec_pack
import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
   input logic                  clk,
   input logic                  rst_l,
   input logic                  dbg_rst_l,
   input logic [31:1]           rst_vec,
   input logic                  nmi_int,
   input logic [31:1]           nmi_vec,

   output logic                 core_rst_l,
   output logic                 active_l2clk,
   output logic                 free_l2clk,

   output logic [pt.NUM_THREADS*64-1:0] trace_rv_i_insn_ip_flat,
   output logic [pt.NUM_THREADS*64-1:0] trace_rv_i_address_ip_flat,
   output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_valid_ip_flat,
   output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_exception_ip_flat,
   output logic [pt.NUM_THREADS*5-1:0]  trace_rv_i_ecause_ip_flat,
   output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_interrupt_ip_flat,
   output logic [pt.NUM_THREADS*32-1:0] trace_rv_i_tval_ip_flat,
   output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_rd_valid_ip_flat,
   output logic [pt.NUM_THREADS*10-1:0] trace_rv_i_rd_addr_ip_flat,
   output logic [pt.NUM_THREADS*64-1:0] trace_rv_i_rd_wdata_ip_flat,

   output logic                 dccm_clk_override,
   output logic                 icm_clk_override,
   output logic                 dec_tlu_core_ecc_disable,
   output logic                 btb_clk_override,

   output logic [pt.NUM_THREADS-1:0] dec_tlu_mhartstart,

   input logic  [pt.NUM_THREADS-1:0] i_cpu_halt_req,
   input logic  [pt.NUM_THREADS-1:0] i_cpu_run_req,
   output logic [pt.NUM_THREADS-1:0] o_cpu_halt_status,
   output logic [pt.NUM_THREADS-1:0] o_cpu_halt_ack,
   output logic [pt.NUM_THREADS-1:0] o_cpu_run_ack,
   output logic [pt.NUM_THREADS-1:0] o_debug_mode_status,

   input logic [31:4]     core_id,

   input logic  [pt.NUM_THREADS-1:0] mpc_debug_halt_req,
   input logic  [pt.NUM_THREADS-1:0] mpc_debug_run_req,
   input logic  [pt.NUM_THREADS-1:0] mpc_reset_run_req,
   output logic [pt.NUM_THREADS-1:0] mpc_debug_halt_ack,
   output logic [pt.NUM_THREADS-1:0] mpc_debug_run_ack,
   output logic [pt.NUM_THREADS-1:0] debug_brkpt_status,

   output logic [pt.NUM_THREADS-1:0] [1:0] dec_tlu_perfcnt0,
   output logic [pt.NUM_THREADS-1:0] [1:0] dec_tlu_perfcnt1,
   output logic [pt.NUM_THREADS-1:0] [1:0] dec_tlu_perfcnt2,
   output logic [pt.NUM_THREADS-1:0] [1:0] dec_tlu_perfcnt3,

   output logic                           dccm_wren,
   output logic                           dccm_rden,
   output logic [pt.DCCM_BITS-1:0]        dccm_wr_addr_lo,
   output logic [pt.DCCM_BITS-1:0]        dccm_wr_addr_hi,
   output logic [pt.DCCM_BITS-1:0]        dccm_rd_addr_lo,
   output logic [pt.DCCM_BITS-1:0]        dccm_rd_addr_hi,
   output logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_wr_data_lo,
   output logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_wr_data_hi,

   input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_rd_data_lo,
   input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_rd_data_hi,

   output logic [pt.ICCM_BITS-1:1]  iccm_rw_addr,
   output logic [pt.NUM_THREADS-1:0]iccm_buf_correct_ecc_thr,
   output logic                     iccm_correction_state,
   output logic                     iccm_stop_fetch,
   output logic                     iccm_corr_scnd_fetch,
   output logic                  ifc_select_tid_f1,
   output logic                  iccm_wren,
   output logic                  iccm_rden,
   output logic [2:0]            iccm_wr_size,
   output logic [77:0]           iccm_wr_data,

   input  logic [63:0]           iccm_rd_data,
   input  logic [116:0]          iccm_rd_data_ecc,

   output logic [31:1]           ic_rw_addr,
   output logic [pt.ICACHE_NUM_WAYS-1:0] ic_tag_valid,
   output logic [pt.ICACHE_NUM_WAYS-1:0] ic_wr_en,
   output logic                  ic_rd_en,

   output logic [pt.ICACHE_BANKS_WAY-1:0] [70:0] ic_wr_data,
   input  logic [63:0]           ic_rd_data,
   input  logic [70:0]           ic_debug_rd_data,
   input  logic [25:0]           ictag_debug_rd_data,
   output logic [70:0]           ic_debug_wr_data,

   input  logic [pt.ICACHE_BANKS_WAY-1:0] ic_eccerr,
   input  logic [pt.ICACHE_BANKS_WAY-1:0] ic_parerr,

   output logic [63:0]           ic_premux_data,
   output logic                  ic_sel_premux_data,

   output logic [pt.ICACHE_INDEX_HI:3] ic_debug_addr,
   output logic                  ic_debug_rd_en,
   output logic                  ic_debug_wr_en,
   output logic                  ic_debug_tag_array,
   output logic [pt.ICACHE_NUM_WAYS-1:0] ic_debug_way,

   input  logic [pt.ICACHE_NUM_WAYS-1:0] ic_rd_hit,
   input  logic                  ic_tag_perr,

   input eh2_btb_sram_pkt btb_sram_pkt,

   input logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_vbank0_rd_data_f1,
   input logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_vbank1_rd_data_f1,
   input logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_vbank2_rd_data_f1,
   input logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_vbank3_rd_data_f1,

   output logic                         btb_wren,
   output logic                         btb_rden,
   output logic [1:0] [pt.BTB_ADDR_HI:1] btb_rw_addr,
   output logic [1:0] [pt.BTB_ADDR_HI:1] btb_rw_addr_f1,
   output logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0] btb_sram_wr_data,
   output logic [1:0] [pt.BTB_BTAG_SIZE-1:0] btb_sram_rd_tag_f1,

   output logic                            lsu_axi_awvalid,
   input  logic                            lsu_axi_awready,
   output logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_awid,
   output logic [31:0]                     lsu_axi_awaddr,
   output logic [3:0]                      lsu_axi_awregion,
   output logic [7:0]                      lsu_axi_awlen,
   output logic [2:0]                      lsu_axi_awsize,
   output logic [1:0]                      lsu_axi_awburst,
   output logic                            lsu_axi_awlock,
   output logic [3:0]                      lsu_axi_awcache,
   output logic [2:0]                      lsu_axi_awprot,
   output logic [3:0]                      lsu_axi_awqos,

   output logic                            lsu_axi_wvalid,
   input  logic                            lsu_axi_wready,
   output logic [63:0]                     lsu_axi_wdata,
   output logic [7:0]                      lsu_axi_wstrb,
   output logic                            lsu_axi_wlast,

   input  logic                            lsu_axi_bvalid,
   output logic                            lsu_axi_bready,
   input  logic [1:0]                      lsu_axi_bresp,
   input  logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_bid,

   output logic                            lsu_axi_arvalid,
   input  logic                            lsu_axi_arready,
   output logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_arid,
   output logic [31:0]                     lsu_axi_araddr,
   output logic [3:0]                      lsu_axi_arregion,
   output logic [7:0]                      lsu_axi_arlen,
   output logic [2:0]                      lsu_axi_arsize,
   output logic [1:0]                      lsu_axi_arburst,
   output logic                            lsu_axi_arlock,
   output logic [3:0]                      lsu_axi_arcache,
   output logic [2:0]                      lsu_axi_arprot,
   output logic [3:0]                      lsu_axi_arqos,

   input  logic                            lsu_axi_rvalid,
   output logic                            lsu_axi_rready,
   input  logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_rid,
   input  logic [63:0]                     lsu_axi_rdata,
   input  logic [1:0]                      lsu_axi_rresp,
   input  logic                            lsu_axi_rlast,

   output logic                            ifu_axi_awvalid,
   input  logic                            ifu_axi_awready,
   output logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_awid,
   output logic [31:0]                     ifu_axi_awaddr,
   output logic [3:0]                      ifu_axi_awregion,
   output logic [7:0]                      ifu_axi_awlen,
   output logic [2:0]                      ifu_axi_awsize,
   output logic [1:0]                      ifu_axi_awburst,
   output logic                            ifu_axi_awlock,
   output logic [3:0]                      ifu_axi_awcache,
   output logic [2:0]                      ifu_axi_awprot,
   output logic [3:0]                      ifu_axi_awqos,

   output logic                            ifu_axi_wvalid,
   input  logic                            ifu_axi_wready,
   output logic [63:0]                     ifu_axi_wdata,
   output logic [7:0]                      ifu_axi_wstrb,
   output logic                            ifu_axi_wlast,

   input  logic                            ifu_axi_bvalid,
   output logic                            ifu_axi_bready,
   input  logic [1:0]                      ifu_axi_bresp,
   input  logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_bid,

   output logic                            ifu_axi_arvalid,
   input  logic                            ifu_axi_arready,
   output logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_arid,
   output logic [31:0]                     ifu_axi_araddr,
   output logic [3:0]                      ifu_axi_arregion,
   output logic [7:0]                      ifu_axi_arlen,
   output logic [2:0]                      ifu_axi_arsize,
   output logic [1:0]                      ifu_axi_arburst,
   output logic                            ifu_axi_arlock,
   output logic [3:0]                      ifu_axi_arcache,
   output logic [2:0]                      ifu_axi_arprot,
   output logic [3:0]                      ifu_axi_arqos,

   input  logic                            ifu_axi_rvalid,
   output logic                            ifu_axi_rready,
   input  logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_rid,
   input  logic [63:0]                     ifu_axi_rdata,
   input  logic [1:0]                      ifu_axi_rresp,
   input  logic                            ifu_axi_rlast,

   output logic                            sb_axi_awvalid,
   input  logic                            sb_axi_awready,
   output logic [pt.SB_BUS_TAG-1:0]        sb_axi_awid,
   output logic [31:0]                     sb_axi_awaddr,
   output logic [3:0]                      sb_axi_awregion,
   output logic [7:0]                      sb_axi_awlen,
   output logic [2:0]                      sb_axi_awsize,
   output logic [1:0]                      sb_axi_awburst,
   output logic                            sb_axi_awlock,
   output logic [3:0]                      sb_axi_awcache,
   output logic [2:0]                      sb_axi_awprot,
   output logic [3:0]                      sb_axi_awqos,

   output logic                            sb_axi_wvalid,
   input  logic                            sb_axi_wready,
   output logic [63:0]                     sb_axi_wdata,
   output logic [7:0]                      sb_axi_wstrb,
   output logic                            sb_axi_wlast,

   input  logic                            sb_axi_bvalid,
   output logic                            sb_axi_bready,
   input  logic [1:0]                      sb_axi_bresp,
   input  logic [pt.SB_BUS_TAG-1:0]        sb_axi_bid,

   output logic                            sb_axi_arvalid,
   input  logic                            sb_axi_arready,
   output logic [pt.SB_BUS_TAG-1:0]        sb_axi_arid,
   output logic [31:0]                     sb_axi_araddr,
   output logic [3:0]                      sb_axi_arregion,
   output logic [7:0]                      sb_axi_arlen,
   output logic [2:0]                      sb_axi_arsize,
   output logic [1:0]                      sb_axi_arburst,
   output logic                            sb_axi_arlock,
   output logic [3:0]                      sb_axi_arcache,
   output logic [2:0]                      sb_axi_arprot,
   output logic [3:0]                      sb_axi_arqos,

   input  logic                            sb_axi_rvalid,
   output logic                            sb_axi_rready,
   input  logic [pt.SB_BUS_TAG-1:0]        sb_axi_rid,
   input  logic [63:0]                     sb_axi_rdata,
   input  logic [1:0]                      sb_axi_rresp,
   input  logic                            sb_axi_rlast,

   input  logic                         dma_axi_awvalid,
   output logic                         dma_axi_awready,
   input  logic [pt.DMA_BUS_TAG-1:0]    dma_axi_awid,
   input  logic [31:0]                  dma_axi_awaddr,
   input  logic [2:0]                   dma_axi_awsize,
   input  logic [2:0]                   dma_axi_awprot,
   input  logic [7:0]                   dma_axi_awlen,
   input  logic [1:0]                   dma_axi_awburst,

   input  logic                         dma_axi_wvalid,
   output logic                         dma_axi_wready,
   input  logic [63:0]                  dma_axi_wdata,
   input  logic [7:0]                   dma_axi_wstrb,
   input  logic                         dma_axi_wlast,

   output logic                         dma_axi_bvalid,
   input  logic                         dma_axi_bready,
   output logic [1:0]                   dma_axi_bresp,
   output logic [pt.DMA_BUS_TAG-1:0]    dma_axi_bid,

   input  logic                         dma_axi_arvalid,
   output logic                         dma_axi_arready,
   input  logic [pt.DMA_BUS_TAG-1:0]    dma_axi_arid,
   input  logic [31:0]                  dma_axi_araddr,
   input  logic [2:0]                   dma_axi_arsize,
   input  logic [2:0]                   dma_axi_arprot,
   input  logic [7:0]                   dma_axi_arlen,
   input  logic [1:0]                   dma_axi_arburst,

   output logic                         dma_axi_rvalid,
   input  logic                         dma_axi_rready,
   output logic [pt.DMA_BUS_TAG-1:0]    dma_axi_rid,
   output logic [63:0]                  dma_axi_rdata,
   output logic [1:0]                   dma_axi_rresp,
   output logic                         dma_axi_rlast,

   output logic [31:0]           haddr,
   output logic [2:0]            hburst,
   output logic                  hmastlock,
   output logic [3:0]            hprot,
   output logic [2:0]            hsize,
   output logic [1:0]            htrans,
   output logic                  hwrite,

   input  logic [63:0]           hrdata,
   input  logic                  hready,
   input  logic                  hresp,

   output logic [31:0]          lsu_haddr,
   output logic [2:0]           lsu_hburst,
   output logic                 lsu_hmastlock,
   output logic [3:0]           lsu_hprot,
   output logic [2:0]           lsu_hsize,
   output logic [1:0]           lsu_htrans,
   output logic                 lsu_hwrite,
   output logic [63:0]          lsu_hwdata,

   input  logic [63:0]          lsu_hrdata,
   input  logic                 lsu_hready,
   input  logic                 lsu_hresp,

   output logic [31:0]          sb_haddr,
   output logic [2:0]           sb_hburst,
   output logic                 sb_hmastlock,
   output logic [3:0]           sb_hprot,
   output logic [2:0]           sb_hsize,
   output logic [1:0]           sb_htrans,
   output logic                 sb_hwrite,
   output logic [63:0]          sb_hwdata,

   input  logic [63:0]          sb_hrdata,
   input  logic                 sb_hready,
   input  logic                 sb_hresp,

   input logic [31:0]            dma_haddr,
   input logic [2:0]             dma_hburst,
   input logic                   dma_hmastlock,
   input logic [3:0]             dma_hprot,
   input logic [2:0]             dma_hsize,
   input logic [1:0]             dma_htrans,
   input logic                   dma_hwrite,
   input logic [63:0]            dma_hwdata,
   input logic                   dma_hreadyin,
   input logic                   dma_hsel,

   output  logic [63:0]          dma_hrdata,
   output  logic                 dma_hreadyout,
   output  logic                 dma_hresp,

   input   logic                 lsu_bus_clk_en,
   input   logic                 ifu_bus_clk_en,
   input   logic                 dbg_bus_clk_en,
   input   logic                 dma_bus_clk_en,

   input logic                   dmi_reg_en,
   input logic [6:0]             dmi_reg_addr,
   input logic                   dmi_reg_wr_en,
   input logic [31:0]            dmi_reg_wdata,
   output logic [31:0]           dmi_reg_rdata,

   input logic [pt.PIC_TOTAL_INT:1] extintsrc_req,
   input logic [pt.NUM_THREADS-1:0] timer_int,
   input logic [pt.NUM_THREADS-1:0] soft_int,
   input logic                      scan_mode
);

   logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_insn_ip_2d;
   logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_address_ip_2d;
   logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_valid_ip_2d;
   logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_exception_ip_2d;
   logic [pt.NUM_THREADS-1:0] [4:0]  trace_rv_i_ecause_ip_2d;
   logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_interrupt_ip_2d;
   logic [pt.NUM_THREADS-1:0] [31:0] trace_rv_i_tval_ip_2d;
   logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_rd_valid_ip_2d;
   logic [pt.NUM_THREADS-1:0] [9:0]  trace_rv_i_rd_addr_ip_2d;
   logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_rd_wdata_ip_2d;

   for (genvar tid = 0; tid < pt.NUM_THREADS; tid++) begin : gen_trace_flatten
      assign trace_rv_i_insn_ip_flat[tid*64 +: 64]     = trace_rv_i_insn_ip_2d[tid];
      assign trace_rv_i_address_ip_flat[tid*64 +: 64]  = trace_rv_i_address_ip_2d[tid];
      assign trace_rv_i_valid_ip_flat[tid*2 +: 2]      = trace_rv_i_valid_ip_2d[tid];
      assign trace_rv_i_exception_ip_flat[tid*2 +: 2]  = trace_rv_i_exception_ip_2d[tid];
      assign trace_rv_i_ecause_ip_flat[tid*5 +: 5]     = trace_rv_i_ecause_ip_2d[tid];
      assign trace_rv_i_interrupt_ip_flat[tid*2 +: 2]  = trace_rv_i_interrupt_ip_2d[tid];
      assign trace_rv_i_tval_ip_flat[tid*32 +: 32]     = trace_rv_i_tval_ip_2d[tid];
      assign trace_rv_i_rd_valid_ip_flat[tid*2 +: 2]   = trace_rv_i_rd_valid_ip_2d[tid];
      assign trace_rv_i_rd_addr_ip_flat[tid*10 +: 10]  = trace_rv_i_rd_addr_ip_2d[tid];
      assign trace_rv_i_rd_wdata_ip_flat[tid*64 +: 64] = trace_rv_i_rd_wdata_ip_2d[tid];
   end

   eh2_veer u_inner (
      .trace_rv_i_insn_ip(trace_rv_i_insn_ip_2d),
      .trace_rv_i_address_ip(trace_rv_i_address_ip_2d),
      .trace_rv_i_valid_ip(trace_rv_i_valid_ip_2d),
      .trace_rv_i_exception_ip(trace_rv_i_exception_ip_2d),
      .trace_rv_i_ecause_ip(trace_rv_i_ecause_ip_2d),
      .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip_2d),
      .trace_rv_i_tval_ip(trace_rv_i_tval_ip_2d),
      .trace_rv_i_rd_valid_ip(trace_rv_i_rd_valid_ip_2d),
      .trace_rv_i_rd_addr_ip(trace_rv_i_rd_addr_ip_2d),
      .trace_rv_i_rd_wdata_ip(trace_rv_i_rd_wdata_ip_2d),
      .*
   );

endmodule
