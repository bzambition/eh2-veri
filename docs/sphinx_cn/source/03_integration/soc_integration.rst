.. _soc_integration:
.. _03_integration/soc_integration:

SoC 集成指南
============

:status: draft
:source: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh; shared/rtl/axi4_intf.sv; shared/rtl/axi4_slave_mem.sv; rtl/eh2_veer_wrapper_rvfi.sv; /home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv; /home/host/Cores-VeeR-EH2/snapshots/default/common_defines.vh; /home/host/Cores-VeeR-EH2/snapshots/default/eh2_pdef.vh
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章边界
-------------

本章说明 EH2 在验证平台中的 SoC 级连接边界：上游 design RTL 的
``eh2_veer_wrapper`` 暴露哪些端口，当前 UVM testbench 如何把这些端口接到
AXI4 memory model、IRQ/JTAG/halt-run virtual interface、trace/RVFI sidecar
和 UVM config DB。本文不描述 PLL、SoC fabric 仲裁、实际芯片复位控制器或板级时钟；
当前源码中没有这些实现，因此不能把 testbench 的 `#5` clock 和 3+3 cycle reset
写成真实 SoC 约束。

当前验证平台的参考拓扑来自 `core_eh2_tb_top.sv` 顶部注释：

.. code-block:: bash

   core_eh2_tb_top
   +-- eh2_veer_wrapper (DUT)
   |   +-- dmi_wrapper
   |   +-- eh2_veer
   |   +-- eh2_mem
   +-- axi4_slave_mem (LSU)
   +-- axi4_slave_mem (IFU)
   +-- axi4_slave_mem (SB)
   +-- UVM virtual interfaces
   +-- eh2_veer_wrapper_rvfi sidecar

逐段解释：

* `core_eh2_tb_top` 是验证平台 top module，不是 SoC 顶层。它实例化 DUT、
  三个 AXI4 slave memory、若干 virtual interface 和 RVFI sidecar。
* DUT 名称为 ``eh2_veer_wrapper``。该 wrapper 的源码不在验证仓库的
  :file:`rtl/design/` 目录中，而在上游 RTL 工作区
  :file:`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv`。
* `axi4_slave_mem` 是行为级 memory model，用于验证环境。真实 SoC 可以把相同 AXI4
  master/slave 端口接到 fabric、SRAM、DDR 或调试总线，但本文只记录源码已经出现的连接。

接口关系：

* 被调用：SoC 集成者、UVM testbench 维护者、调试 RVFI/trace 连接的验证工程师。
* 调用：本章引用 :ref:`tb_top`、:ref:`bus_axi_ahb`、:ref:`dccm_iccm`、
  :ref:`rvfi_trace`、:ref:`adr-0002`、:ref:`adr-0004`、:ref:`adr-0015`。
* 共享状态：`core_clk`、`rst_l`、`porst_l`、AXI4 channel wires、trace signals、
  IRQ/JTAG/halt-run virtual interface 和 `uvm_config_db`。

§2  wrapper 基础端口
--------------------

`eh2_veer_wrapper` 的 module header 先导入 `eh2_pkg`，再 include
`eh2_param.vh`，最后声明 clock、reset、reset vector、NMI vector 和 JTAG ID。
这些端口是验证平台和 SoC 侧都必须显式连接的基础输入。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L23-L35`）：

.. code-block:: systemverilog

   module eh2_veer_wrapper
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
      input logic                       clk,
      input logic                       rst_l,
      input logic                       dbg_rst_l,
      input logic [31:1]                rst_vec,
      input logic                       nmi_int,
      input logic [31:1]                nmi_vec,
      input logic [31:1]                jtag_id,

逐段解释：

* 第 L23-L27 行：wrapper 使用参数化形式，并把 `eh2_param.vh` 作为参数 include。
  文档中提到 `NUM_THREADS`、AXI tag width、PIC interrupt count 等派生宽度时，
  都应回到该参数体系，而不是手写固定宽度。
* 第 L28-L30 行：`clk`、`rst_l` 和 `dbg_rst_l` 是 wrapper 的基本时序输入。
  当前 testbench 把 `dbg_rst_l` 接到 `porst_l`，这说明 debug reset 与 core reset
  在验证环境中分开驱动。
* 第 L31-L34 行：`rst_vec`、`nmi_vec`、`jtag_id` 都是 `[31:1]`。验证 top 使用
  `[31:1]` 片段接入，低 bit 不直接进入 wrapper。

接口关系：

* 被调用：`core_eh2_tb_top.sv` 中的 DUT 实例化，以及真实 SoC wrapper 实例化。
* 调用：`eh2_param.vh` 提供 wrapper 参数。
* 共享状态：`clk`、`rst_l`、`dbg_rst_l`、`rst_vec`、`nmi_int`、`nmi_vec`、`jtag_id`。

§3  trace 与 verification-only 写回视图
----------------------------------------

EH2 wrapper 暴露 trace packet，同时增加 verification-only 的写回视图：
`trace_rv_i_rd_valid_ip`、`trace_rv_i_rd_addr_ip` 和 `trace_rv_i_rd_wdata_ip`。
这些字段用于 RVFI-equivalent trace 和 cosim 对齐，属于验证端观察面，不是完整 RVFI
总线直接进入 design RTL。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L37-L47`）：

.. code-block:: systemverilog

      output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_insn_ip,
      output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_address_ip,
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_valid_ip,
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_exception_ip,
      output logic [pt.NUM_THREADS-1:0] [4:0]  trace_rv_i_ecause_ip,
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_interrupt_ip,
      output logic [pt.NUM_THREADS-1:0] [31:0] trace_rv_i_tval_ip,
      // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_rd_valid_ip,
      output logic [pt.NUM_THREADS-1:0] [9:0]  trace_rv_i_rd_addr_ip,
      output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_rd_wdata_ip,

逐段解释：

* 第 L37-L43 行：每个 trace 字段都以 `pt.NUM_THREADS` 为第一维，第二维覆盖双发射
  lane 或对应 payload。`trace_rv_i_valid_ip` 的 `[1:0]` 表示一个 thread 内的 i0/i1
  retire lane。
* 第 L44-L47 行：写回视图把 i0/i1 的目的寄存器和写回数据打包在 trace 输出中。
  这与 :ref:`adr-0004` 的方向一致：增加 retire trace 字段，而不是把完整 RVFI
  port 放进 design RTL。
* 这些端口在 UVM top 中被接到 `eh2_trace_intf` 和 `eh2_veer_wrapper_rvfi`。
  后者由 :ref:`adr-0015` 记录为 sidecar 适配层。

接口关系：

* 被调用：`eh2_trace_intf`、`eh2_veer_wrapper_rvfi`、cosim trace monitor。
* 调用：无函数调用；这些是 wrapper output ports。
* 共享状态：`trace_rv_i_*` 信号族、`pt.NUM_THREADS`、i0/i1 lane 编码。

§4  AXI4、DMA 与 AHB-Lite 条件端口
-----------------------------------

当前 wrapper 在 `RV_BUILD_AXI4` 条件下暴露 LSU、IFU、SB 三组 AXI4 master 端口和
DMA AXI4 slave 端口；在 `RV_BUILD_AHB_LITE` 条件下暴露 AHB-Lite 端口。验证平台当前
`core_eh2_tb_top.sv` 连接的是 AXI4 分支。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L49-L65`）：

.. code-block:: systemverilog

      // Bus signals

   `ifdef RV_BUILD_AXI4
      //-------------------------- LSU AXI signals--------------------------
      // AXI Write Channels
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

逐段解释：

* 第 L49-L51 行：AXI4 端口只在 `RV_BUILD_AXI4` 宏打开时出现。文档不能把 AXI4 和
  AHB-Lite 同时写成无条件端口。
* 第 L52-L65 行：LSU write address channel 由 DUT 输出 `awvalid`、`awid`、`awaddr`
  等请求信号，并从 slave 侧输入 `awready`。这符合 master 端口方向。
* 宽度 `pt.LSU_BUS_TAG` 来自 wrapper 参数包，不应在 SoC 文档中手写成固定数字。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L193-L231`）：

.. code-block:: systemverilog

      //-------------------------- DMA AXI signals--------------------------
      // AXI Write Channels
      input  logic                         dma_axi_awvalid,
      output logic                         dma_axi_awready,
      input  logic [pt.DMA_BUS_TAG-1:0]    dma_axi_awid,
      input  logic [31:0]                  dma_axi_awaddr,
      input  logic [2:0]                   dma_axi_awsize,
      input  logic [2:0]                   dma_axi_awprot,
      input  logic [7:0]                   dma_axi_awlen,
      input  logic [1:0]                   dma_axi_awburst,

逐段解释：

* 第 L193-L203 行：DMA AXI write address channel 的方向与 LSU/IFU/SB master 相反。
  `dma_axi_awvalid`、`dma_axi_awid`、`dma_axi_awaddr` 是输入，说明外部 DMA master
  可以向 EH2 wrapper 的 DMA slave 端口发起访问。
* 同一 DMA 分组还包含 W/B/AR/R channel。验证 top 当前把 DMA 输入 tie off，而不是实例化
  外部 DMA master。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L236-L249`）：

.. code-block:: systemverilog

   `ifdef RV_BUILD_AHB_LITE
    //// AHB LITE BUS
      output logic [31:0]               haddr,
      output logic [2:0]                hburst,
      output logic                      hmastlock,
      output logic [3:0]                hprot,
      output logic [2:0]                hsize,
      output logic [1:0]                htrans,
      output logic                      hwrite,

      input logic [63:0]                hrdata,
      input logic                       hready,
      input logic                       hresp,

逐段解释：

* 第 L236 行：AHB-Lite 端口由 `RV_BUILD_AHB_LITE` 控制，和 AXI4 分支并列存在。
* 第 L237-L249 行：AHB-Lite 分支暴露 `haddr`、`hburst`、`htrans`、`hwrite`
  等 master request，以及 `hrdata`、`hready`、`hresp` 等 response 输入。
* 当前 UVM top 的实例化片段没有连接这些 AHB-Lite ports，因此本验证平台的 SoC
  参考连接以 AXI4 为主；AHB-Lite 只作为 wrapper 条件接口记录。

接口关系：

* 被调用：SoC fabric 集成、`core_eh2_tb_top.sv` 的 AXI4 DUT 实例化。
* 调用：`axi4_slave_mem` 响应 LSU/IFU/SB master；DMA slave 在当前 TB 被 tie off。
* 共享状态：`RV_BUILD_AXI4`、`RV_BUILD_AHB_LITE`、`pt.*_BUS_TAG`、AXI4 channel wires。

§5  其他 SoC 可见控制端口
--------------------------

wrapper 在 bus 端口之后继续暴露 bus clock enable、external memory packet、interrupt、
JTAG、halt/run、debug status、scan 和 MBIST 端口。这些信号在真实 SoC 中通常由
clock/reset controller、interrupt controller、debug module 或 DFT 逻辑驱动；当前
testbench 只给出验证参考连接。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L296-L312`）：

.. code-block:: systemverilog

      // clk ratio signals
      input logic                       lsu_bus_clk_en, // Clock ratio b/w cpu core clk & AHB master interface
      input logic                       ifu_bus_clk_en, // Clock ratio b/w cpu core clk & AHB master interface
      input logic                       dbg_bus_clk_en, // Clock ratio b/w cpu core clk & AHB master interface
      input logic                       dma_bus_clk_en, // Clock ratio b/w cpu core clk & AHB slave interface

    // all of these test inputs are brought to top-level; must be tied off based on usage by physical design (ie. icache or not, iccm or not, dccm or not)

      input                             eh2_dccm_ext_in_pkt_t  [pt.DCCM_NUM_BANKS-1:0] dccm_ext_in_pkt,
      input                             eh2_ccm_ext_in_pkt_t  [pt.ICCM_NUM_BANKS/4-1:0][1:0][1:0] iccm_ext_in_pkt,
      input                             eh2_ccm_ext_in_pkt_t  [1:0] btb_ext_in_pkt,
      input                             eh2_ic_data_ext_in_pkt_t  [pt.ICACHE_NUM_WAYS-1:0][pt.ICACHE_BANKS_WAY-1:0] ic_data_ext_in_pkt,
      input                             eh2_ic_tag_ext_in_pkt_t   [pt.ICACHE_NUM_WAYS-1:0]                        ic_tag_ext_in_pkt,

      input logic [pt.NUM_THREADS-1:0]  timer_int,
      input logic [pt.NUM_THREADS-1:0]  soft_int,
      input logic [pt.PIC_TOTAL_INT:1] extintsrc_req,

逐段解释：

* 第 L296-L300 行：四个 bus clock enable 是 wrapper 输入。当前 TB 将它们初始化为
  `1`，表示验证环境不建模 bus clock ratio 关闭路径。
* 第 L302-L308 行：external memory packet 被带到顶层，注释要求 physical design
  根据 ICache、ICCM、DCCM 使用方式决定 tie off 或连接。当前 TB 将这些端口全部接到
  `'0`。
* 第 L310-L312 行：`timer_int`、`soft_int` 和 `extintsrc_req` 都按 `NUM_THREADS`
  或 `PIC_TOTAL_INT` 参数定宽。当前 TB 通过 `eh2_irq_intf` 驱动这些输入。

关键代码（`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv:L319-L346`）：

.. code-block:: systemverilog

      // ports added by the soc team
      input logic                       jtag_tck,    // JTAG clk
      input logic                       jtag_tms,    // JTAG TMS
      input logic                       jtag_tdi,    // JTAG tdi
      input logic                       jtag_trst_n, // JTAG Reset
      output logic                      jtag_tdo,    // JTAG TDO

      input logic [31:4]     core_id, // Core ID


      // external MPC halt/run interface
      input logic  [pt.NUM_THREADS-1:0] mpc_debug_halt_req, // Async halt request
      input logic  [pt.NUM_THREADS-1:0] mpc_debug_run_req,  // Async run request
      input logic  [pt.NUM_THREADS-1:0] mpc_reset_run_req,  // Run/halt after reset
      output logic [pt.NUM_THREADS-1:0] mpc_debug_halt_ack, // Halt ack
      output logic [pt.NUM_THREADS-1:0] mpc_debug_run_ack,  // Run ack
      output logic [pt.NUM_THREADS-1:0] debug_brkpt_status, // debug breakpoint

      output logic [pt.NUM_THREADS-1:0] dec_tlu_mhartstart, // running harts

      input logic          [pt.NUM_THREADS-1:0]         i_cpu_halt_req,      // Async halt req to CPU
      output logic         [pt.NUM_THREADS-1:0]         o_cpu_halt_ack,      // core response to halt
      output logic         [pt.NUM_THREADS-1:0]         o_cpu_halt_status,   // 1'b1 indicates core is halted
      output logic         [pt.NUM_THREADS-1:0]         o_debug_mode_status, // Core to the PMU that core is in debug mode. When core is in debug mode, the PMU should refrain from sendng a halt or run request
      input logic          [pt.NUM_THREADS-1:0]         i_cpu_run_req, // Async restart req to CPU
      output logic         [pt.NUM_THREADS-1:0]         o_cpu_run_ack, // Core response to run req
      input logic                       scan_mode, // To enable scan mode
      input logic                       mbist_mode // to enable mbist

逐段解释：

* 第 L319-L324 行：JTAG pins 是 SoC 可见 debug 接口，`jtag_tdo` 是 wrapper 输出，
  其余 JTAG pins 是输入。
* 第 L326 行：`core_id` 是 `[31:4]` 输入。当前 TB 将该端口接 `'0`。
* 第 L329-L344 行：MPC 和 CPU halt/run 接口按 `NUM_THREADS` 定宽。请求类信号为输入，
  ack/status/debug mode 为输出。
* 第 L345-L346 行：`scan_mode` 和 `mbist_mode` 是 DFT 相关输入。当前 TB 将它们固定为
  `1'b0`。

接口关系：

* 被调用：SoC JTAG/debug/PMU/DFT 集成，UVM halt-run 和 JTAG agents。
* 调用：当前 TB 通过 `eh2_jtag_intf` 和 `eh2_halt_run_intf` 驱动这些端口。
* 共享状态：`timer_int`、`soft_int`、`extintsrc_req`、`jtag_*`、
  `mpc_*`、`i_cpu_*`、`o_cpu_*`、`scan_mode`、`mbist_mode`。

§6  TB 时钟、复位与默认向量
----------------------------

验证 top 生成 `core_clk`，并分两段释放 `porst_l` 和 `rst_l`。这只是 UVM TB
行为：源码没有把该 `#5` delay 或 3+3 cycle reset 写成 SoC 集成要求。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L38-L49`）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Clock and Reset
     //--------------------------------------------------------------------------
     bit core_clk;
     initial begin
       core_clk = 0;
       forever #5 core_clk = ~core_clk;  // 100MHz
     end

     logic rst_l;       // Active-low reset
     logic porst_l;     // Power-on reset (active-low)

逐段解释：

* 第 L38-L45 行：TB 用 `forever #5` 翻转 `core_clk`，注释标成 100 MHz。该 clock
  只用于仿真参考环境。
* 第 L47-L49 行：`rst_l` 和 `porst_l` 都是低有效 reset。后续 DUT 实例化把
  `rst_l` 接 wrapper `rst_l`，把 `porst_l` 接 wrapper `dbg_rst_l`。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L122-L147`）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Reset Generation
     //--------------------------------------------------------------------------
     initial begin
       rst_l   = 0;
       porst_l = 0;
       repeat (3) @(posedge core_clk);
       porst_l = 1;
       repeat (3) @(posedge core_clk);
       rst_l   = 1;
     end

     //--------------------------------------------------------------------------
     // Default Signal Values
     //--------------------------------------------------------------------------
     initial begin
       reset_vector       = 32'h80000000;
       nmi_vector         = 32'h00000000;
       jtag_id            = 31'h1;
       // mpc_debug_halt_req/run_req/reset_run_req driven by eh2_halt_run_intf (assign below)
       // i_cpu_halt_req/run_req driven by eh2_halt_run_intf (assign below)
       lsu_bus_clk_en     = 1;
       ifu_bus_clk_en     = 1;
       dbg_bus_clk_en     = 1;
       dma_bus_clk_en     = 1;
     end

逐段解释：

* 第 L125-L131 行：TB 先同时拉低 `rst_l` 和 `porst_l`，3 个 `core_clk` 上升沿后释放
  `porst_l`，再等 3 个上升沿释放 `rst_l`。
* 第 L137-L140 行：TB 默认 reset vector 为 `32'h80000000`，NMI vector 为
  `32'h00000000`，JTAG ID 为 `31'h1`。
* 第 L141-L146 行：halt/run 请求由 `eh2_halt_run_intf` 驱动，bus clock enable
  在初始块中全部置 `1`。

接口关系：

* 被调用：`eh2_veer_wrapper dut` 实例化、AXI4 interface、memory model、各 virtual
  interface。
* 调用：无函数调用；该段是 TB initial block。
* 共享状态：`core_clk`、`rst_l`、`porst_l`、`reset_vector`、`nmi_vector`、`jtag_id`、
  `*_bus_clk_en`。

§7  DUT 实例化与端口分组
-------------------------

`core_eh2_tb_top` 的 DUT 实例化是验证平台最直接的 SoC 连接参考。该实例化把基础控制、
trace、LSU/IFU/SB/DMA AXI4、JTAG、IRQ、clock enable、external memory packet、
halt/run、debug status、performance counters、core_id、scan 和 mbist 全部显式接线。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L170-L191`）：

.. code-block:: systemverilog

     // DUT Instantiation
     //--------------------------------------------------------------------------
     eh2_veer_wrapper dut (
       .clk                    (core_clk),
       .rst_l                  (rst_l),
       .dbg_rst_l              (porst_l),
       .rst_vec                (reset_vector[31:1]),
       .nmi_int                (nmi_int),
       .nmi_vec                (nmi_vector[31:1]),
       .jtag_id                (jtag_id[31:1]),

       // Trace
       .trace_rv_i_insn_ip      (trace_rv_i_insn_ip),
       .trace_rv_i_address_ip   (trace_rv_i_address_ip),
       .trace_rv_i_valid_ip     (trace_rv_i_valid_ip),
       .trace_rv_i_exception_ip (trace_rv_i_exception_ip),
       .trace_rv_i_ecause_ip    (trace_rv_i_ecause_ip),
       .trace_rv_i_interrupt_ip (trace_rv_i_interrupt_ip),
       .trace_rv_i_tval_ip      (trace_rv_i_tval_ip),
       .trace_rv_i_rd_valid_ip  (trace_rv_i_rd_valid_ip),
       .trace_rv_i_rd_addr_ip   (trace_rv_i_rd_addr_ip),
       .trace_rv_i_rd_wdata_ip  (trace_rv_i_rd_wdata_ip),

逐段解释：

* 第 L172-L179 行：TB 把 `core_clk`、`rst_l`、`porst_l`、reset vector、NMI 和 JTAG ID
  接到 wrapper 基础端口。向量字段都使用 `[31:1]` 切片。
* 第 L181-L191 行：trace 与 verification-only 写回字段全部接到本地 signals。
  这些 signals 之后同时喂给 trace interface 和 RVFI sidecar。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L356-L402`，节选）：

.. code-block:: systemverilog

       // Interrupts
       .timer_int         (timer_int),
       .soft_int          (soft_int),
       .extintsrc_req     (extintsrc_req),

       // Clock enables
       .lsu_bus_clk_en    (lsu_bus_clk_en),
       .ifu_bus_clk_en    (ifu_bus_clk_en),
       .dbg_bus_clk_en    (dbg_bus_clk_en),
       .dma_bus_clk_en    (dma_bus_clk_en),

       // External memory packets (tied off - internal memories used)
       .dccm_ext_in_pkt   ('0),
       .iccm_ext_in_pkt   ('0),
       .btb_ext_in_pkt    ('0),
       .ic_data_ext_in_pkt('0),
       .ic_tag_ext_in_pkt ('0),

       // MPC halt/run
       .mpc_debug_halt_req (mpc_debug_halt_req),
       .mpc_debug_run_req  (mpc_debug_run_req),
       .mpc_reset_run_req  (mpc_reset_run_req),
       .mpc_debug_halt_ack (mpc_debug_halt_ack),

逐段解释：

* 第 L356-L365 行：interrupt inputs 和 bus clock enable inputs 被分组连接，和
  wrapper 端口分组保持一致。
* 第 L367-L372 行：所有 external memory packet 在当前 TB 中接 `'0`。这不表示真实
  SoC 必须 tie off，只说明当前验证配置使用 wrapper 内部 memory 结构和外部 AXI memory model。
* 第 L374-L379 行：MPC halt/run 请求和 ack 被接到本地 signals，后续由
  `eh2_halt_run_intf` 驱动或采样。

接口关系：

* 被调用：`core_eh2_tb_top` elaboration 阶段。
* 调用：实例化上游 `eh2_veer_wrapper`。
* 共享状态：所有 `core_eh2_dut_signals.svh` 声明的 DUT 连接 signals。

§8  DUT signal 声明文件
------------------------

`core_eh2_tb_top.sv` 通过 include 引入 `core_eh2_dut_signals.svh`。该文件把 reset
vector、JTAG、trace、debug/control、interrupt、clock enable 和四组 AXI4 wires
集中声明，避免 top module 内部重复定义。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:L1-L25`）：

.. code-block:: systemverilog

     // Reset vector and NMI
     logic [31:0]  reset_vector;
     logic [31:0]  nmi_vector;
     logic         nmi_int;

     // JTAG
     logic         jtag_tck;
     logic         jtag_tms;
     logic         jtag_tdi;
     logic         jtag_trst_n;
     logic         jtag_tdo;
     logic [31:1]  jtag_id;

     // Trace
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_insn_ip;
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_address_ip;
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_valid_ip;
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_exception_ip;
     logic [`RV_NUM_THREADS-1:0][4:0]  trace_rv_i_ecause_ip;
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_interrupt_ip;
     logic [`RV_NUM_THREADS-1:0][31:0] trace_rv_i_tval_ip;
     // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_rd_valid_ip;
     logic [`RV_NUM_THREADS-1:0][9:0]  trace_rv_i_rd_addr_ip;
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_rd_wdata_ip;

逐段解释：

* 第 L1-L12 行：reset vector、NMI、JTAG pins 和 JTAG ID 在 TB 本地声明。
* 第 L14-L25 行：trace signals 使用 `RV_NUM_THREADS` 宏定第一维，和 wrapper 中的
  `pt.NUM_THREADS` 对应。写回视图保留 lane 0 = i0、lane 1 = i1 的注释。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:L187-L216`，节选）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // AXI4 Signals - DMA Port (tied off)
     //--------------------------------------------------------------------------
     wire                            dma_axi_awvalid;
     wire                            dma_axi_awready;
     wire [`RV_DMA_BUS_TAG-1:0]     dma_axi_awid;
     wire [31:0]                     dma_axi_awaddr;
     wire [2:0]                      dma_axi_awsize;
     wire [2:0]                      dma_axi_awprot;
     wire [7:0]                      dma_axi_awlen;
     wire [1:0]                      dma_axi_awburst;
     wire                            dma_axi_wvalid;
     wire                            dma_axi_wready;
     wire [63:0]                     dma_axi_wdata;
     wire [7:0]                      dma_axi_wstrb;
     wire                            dma_axi_wlast;
     wire                            dma_axi_bvalid;
     wire                            dma_axi_bready;
     wire [1:0]                      dma_axi_bresp;
     wire [`RV_DMA_BUS_TAG-1:0]     dma_axi_bid;
     wire                            dma_axi_arvalid;
     wire                            dma_axi_arready;
     wire [`RV_DMA_BUS_TAG-1:0]     dma_axi_arid;
     wire [31:0]                     dma_axi_araddr;
     wire [2:0]                      dma_axi_arsize;
     wire [2:0]                      dma_axi_arprot;
     wire [7:0]                      dma_axi_arlen;
     wire [1:0]                      dma_axi_arburst;
     wire                            dma_axi_rvalid;
     wire                            dma_axi_rready;

逐段解释：

* 第 L187-L190 行：DMA 分组在声明文件中明确标注为 tied off，和 TB 后续 assign
  保持一致。
* 第 L191-L216 行：DMA AXI4 的 AW、W、B、AR 和部分 R channel wires 在同一分组中声明，
  即使当前验证环境没有外部 DMA master。
* 第 L217-L220 行：剩余 R channel payload 和 response wires 紧随其后声明。
  外部 DMA master。这样 DUT 端口仍完整连接，避免未连接端口。

接口关系：

* 被调用：`core_eh2_tb_top.sv` 第 L57 行 include。
* 调用：无；该文件只声明信号。
* 共享状态：`RV_NUM_THREADS`、`RV_*_BUS_TAG` 宏和 DUT 实例化端口。

§9  AXI4 memory model 与 DMA tie-off
------------------------------------

当前 TB 为 LSU、IFU 和 SB 三个 AXI4 master 各实例化一个 `axi4_slave_mem`。三个 memory
实例都使用 32-bit address、64-bit data、各自的 DUT tag width，并设置 `MEM_SIZE`
为 `64 * 1024 * 1024`。DMA 端口没有外部 master，因此 TB 只 tie off DMA 输入，
DUT 输出不由 TB 赋值。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L409-L436`）：

.. code-block:: systemverilog

     // LSU memory (data) - connected to LSU AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_LSU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) lsu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (lsu_axi_intf.error_inject_mode),
       .force_bresp       (lsu_axi_intf.force_bresp),
       .force_rresp       (lsu_axi_intf.force_rresp),
       .awid     (lsu_axi_awid),
       .awaddr   (lsu_axi_awaddr),
       .awlen    (lsu_axi_awlen),
       .awsize   (lsu_axi_awsize),
       .awburst  (lsu_axi_awburst),
       .awvalid  (lsu_axi_awvalid),
       .awready  (lsu_axi_awready),
       .wdata    (lsu_axi_wdata),
       .wstrb    (lsu_axi_wstrb),
       .wlast    (lsu_axi_wlast),
       .wvalid   (lsu_axi_wvalid),
       .wready   (lsu_axi_wready),
       .bid      (lsu_axi_bid),
       .bresp    (lsu_axi_bresp),
       .bvalid   (lsu_axi_bvalid),
       .bready   (lsu_axi_bready),

逐段解释：

* 第 L409-L415 行：LSU memory 是 `axi4_slave_mem`，参数和 DUT LSU AXI tag width
  对齐。
* 第 L416-L420 行：memory 与 `core_clk`、`rst_l` 同步，并接入 UVM AXI interface
  的 error injection 控制。
* 第 L421-L436 行：LSU write address、write data 和 write response channel
  逐字段连接到 DUT LSU AXI wires。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L452-L500`，节选）：

.. code-block:: systemverilog

     // IFU memory (instruction) - connected to IFU AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_IFU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) ifu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (ifu_axi_intf.error_inject_mode),

逐段解释：

* 第 L452-L458 行：IFU memory 与 LSU memory 结构相同，但 `ID_WIDTH` 使用
  `RV_IFU_BUS_TAG`。
* 第 L459-L463 行：IFU memory 也接收自己的 AXI interface error injection 控制，
  因此 IFU、LSU、SB 的错误注入状态彼此独立。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L538-L564`）：

.. code-block:: systemverilog

     // DMA port: no external DMA master — tie all inputs to inactive values.
     // OUTPUTS are driven by the DUT only (do NOT assign — that caused multi-driver X).
     // AW channel inputs
     assign dma_axi_awvalid = 1'b0;
     assign dma_axi_awid    = '0;
     assign dma_axi_awaddr  = '0;
     assign dma_axi_awsize  = '0;
     assign dma_axi_awprot  = '0;
     assign dma_axi_awlen   = '0;
     assign dma_axi_awburst = '0;
     // W channel inputs
     assign dma_axi_wvalid  = 1'b0;
     assign dma_axi_wdata   = '0;
     assign dma_axi_wstrb   = '0;
     assign dma_axi_wlast   = '0;
     // B channel input
     assign dma_axi_bready  = 1'b0;
     // AR channel inputs
     assign dma_axi_arvalid = 1'b0;
     assign dma_axi_arid    = '0;
     assign dma_axi_araddr  = '0;
     assign dma_axi_arsize  = '0;
     assign dma_axi_arprot  = '0;
     assign dma_axi_arlen   = '0;
     assign dma_axi_arburst = '0;
     // R channel input
     assign dma_axi_rready  = 1'b0;

逐段解释：

* 第 L538-L539 行：注释明确区分 DMA 输入和 DUT 输出。TB 只 tie off 外部 DMA master
  会驱动的输入。
* 第 L541-L554 行：AW/W/B 输入侧被置为 inactive 或零值。
* 第 L556-L564 行：AR/R 输入侧同样被置 inactive。该段避免对 `dma_axi_*ready`、
  `dma_axi_*valid` 的 DUT 输出产生多驱动。

接口关系：

* 被调用：DUT AXI4 master ports、UVM AXI agents、binary loader backdoor memory 写入。
* 调用：`axi4_slave_mem` 内部 write/read FSM。
* 共享状态：`lsu_mem.mem`、`ifu_mem.mem`、`sb_mem.mem`、`*_axi_intf.error_inject_mode`。

§10  AXI4 interface 与协议观察
-------------------------------

`axi4_intf` 是 UVM agent 与 DUT wires 之间的 virtual interface。它定义 AXI4 五个
channel、error injection 控制、response/master/monitor clocking block，以及
valid/ready 稳定性断言。:ref:`adr-0002` 记录当前 bus 策略是 passive monitoring
配合 behavioral memory。

关键代码（`shared/rtl/axi4_intf.sv:L8-L29`）：

.. code-block:: systemverilog

   interface axi4_intf #(
     parameter int ADDR_WIDTH = 32,
     parameter int DATA_WIDTH = 64,
     parameter int ID_WIDTH   = 4
   ) (
     input logic clk,
     input logic rst_n
   );

     // Write Address Channel
     logic [ID_WIDTH-1:0]     awid;
     logic [ADDR_WIDTH-1:0]   awaddr;
     logic [3:0]              awregion;
     logic [7:0]              awlen;
     logic [2:0]              awsize;
     logic [1:0]              awburst;
     logic                    awlock;
     logic [3:0]              awcache;
     logic [2:0]              awprot;
     logic [3:0]              awqos;
     logic                    awvalid;
     logic                    awready;

逐段解释：

* 第 L8-L15 行：interface 参数化 address width、data width 和 ID width，并接收
  `clk`、`rst_n`。
* 第 L17-L29 行：AW channel 信号完整声明，包括 ID、地址、burst 属性、cache/prot/qos
  以及 valid/ready。

关键代码（`shared/rtl/axi4_intf.sv:L66-L76`）：

.. code-block:: systemverilog

     // Error injection control (driven by UVM axi4_driver, consumed by axi4_slave_mem)
     logic                    error_inject_mode;
     logic [1:0]              force_bresp;
     logic [1:0]              force_rresp;

     // Default: error injection inactive
     initial begin
       error_inject_mode = 1'b0;
       force_bresp       = 2'b00;
       force_rresp       = 2'b00;
     end

逐段解释：

* 第 L66-L69 行：error injection 控制在 interface 上定义，UVM AXI driver 可写这些字段，
  `axi4_slave_mem` 读取它们决定 B/R response。
* 第 L71-L76 行：默认关闭错误注入，并把 forced response 置为 `2'b00`。

关键代码（`shared/rtl/axi4_intf.sv:L161-L199`，节选）：

.. code-block:: systemverilog

     // AWVALID must remain asserted until AWREADY
     property aw_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       awvalid && !awready |=> awvalid;
     endproperty
     assert property (aw_valid_stable) else
       $error("AXI4: AWVALID deasserted before AWREADY");

     // WVALID must remain asserted until WREADY
     property w_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       wvalid && !wready |=> wvalid;
     endproperty
     assert property (w_valid_stable) else
       $error("AXI4: WVALID deasserted before WREADY");

逐段解释：

* 第 L161-L167 行：AWVALID 在 AWREADY 到来前必须保持，违反时触发 `$error`。
* 第 L169-L175 行：WVALID 同样在 WREADY 到来前保持。该断言只在非 synthesis 区域内有效。
* 同一文件后续还定义 ARVALID、BVALID、RVALID 的稳定性检查。

接口关系：

* 被调用：`core_eh2_tb_top.sv` 中 LSU/IFU/SB 三个 `axi4_intf` 实例。
* 调用：SystemVerilog assertion 和 UVM clocking block。
* 共享状态：AXI4 channel signals、`error_inject_mode`、`force_bresp`、`force_rresp`。

§11  UVM virtual interface 绑定
--------------------------------

TB 为 LSU、IFU、SB 分别创建 `axi4_intf`，再用 continuous assign 把 DUT wires 映射到
interface 字段。trace、IRQ、JTAG、halt-run、coverage、CSR、instruction monitor 和
RVFI 也通过 `uvm_config_db` 下发给 UVM 层。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L591-L604`）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // AXI4 Interface Instances (for UVM agents)
     // Use DUT's actual tag widths to avoid truncation/extension issues
     //--------------------------------------------------------------------------
     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_LSU_BUS_TAG))
       lsu_axi_intf (.clk(core_clk), .rst_n(rst_l));

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_IFU_BUS_TAG))
       ifu_axi_intf (.clk(core_clk), .rst_n(rst_l));

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_SB_BUS_TAG))
       sb_axi_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect interface signals to DUT wires

逐段解释：

* 第 L591-L594 行：注释说明 interface 使用 DUT 实际 tag width，避免截断或扩展。
* 第 L595-L602 行：三个 AXI4 interface 都使用 32-bit address 和 64-bit data，
  ID width 分别取 `RV_LSU_BUS_TAG`、`RV_IFU_BUS_TAG`、`RV_SB_BUS_TAG`。
* 第 L604 行之后，TB 把每个 interface 字段逐项 assign 到对应 DUT wire。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L731-L744`）：

.. code-block:: systemverilog

     eh2_trace_intf #(.NUM_THREADS(`RV_NUM_THREADS))
       trace_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect trace interface to DUT trace signals
     assign trace_intf.insn      = trace_rv_i_insn_ip;
     assign trace_intf.address   = trace_rv_i_address_ip;
     assign trace_intf.valid     = trace_rv_i_valid_ip;
     assign trace_intf.exception = trace_rv_i_exception_ip;
     assign trace_intf.ecause    = trace_rv_i_ecause_ip;
     assign trace_intf.interrupt = trace_rv_i_interrupt_ip;
     assign trace_intf.tval      = trace_rv_i_tval_ip;
     assign trace_intf.rd_valid  = trace_rv_i_rd_valid_ip;
     assign trace_intf.rd_addr   = trace_rv_i_rd_addr_ip;
     assign trace_intf.rd_wdata  = trace_rv_i_rd_wdata_ip;

逐段解释：

* 第 L731-L732 行：trace interface 按 `RV_NUM_THREADS` 参数化，并接 `core_clk`、
  `rst_l`。
* 第 L735-L744 行：trace packet 和 verification-only 写回字段逐项进入
  `trace_intf`，供 trace monitor 和 cosim scoreboard 使用。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1105-L1120`）：

.. code-block:: systemverilog

     initial begin
       // Store interface references for UVM agents
       uvm_config_db#(virtual core_eh2_tb_intf)::set(null, "*", "tb_vif", tb_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_LSU_BUS_TAG)))::set(null, "*lsu_agent*", "vif", lsu_axi_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_IFU_BUS_TAG)))::set(null, "*ifu_agent*", "vif", ifu_axi_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_SB_BUS_TAG)))::set(null, "*sb_agent*",  "vif", sb_axi_intf);

       // Store trace and DUT probe interfaces
       uvm_config_db#(virtual eh2_trace_intf)::set(null, "*trace_monitor*", "vif", trace_intf);
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*dut_probe_monitor*", "vif", dut_probe_intf);

       // Also provide DUT probe interface to trace monitor (for interrupt/debug state sampling)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*trace_monitor*", "probe_vif", dut_probe_intf);

       // Provide DUT probe interface to cosim agent's scoreboard (for reset monitoring)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*cosim_agt*", "probe_vif", dut_probe_intf);

逐段解释：

* 第 L1105-L1110 行：TB、LSU、IFU、SB virtual interface 通过 `uvm_config_db`
  下发给匹配的 UVM 组件。
* 第 L1112-L1117 行：trace monitor 和 DUT probe monitor 分别取得自己的 vif；
  trace monitor 还额外取得 `probe_vif` 以采样 interrupt/debug 状态。
* 第 L1119-L1120 行：cosim agent 的 scoreboard 取得 `probe_vif`，用于 reset 监视。

接口关系：

* 被调用：UVM build/connect/run phase 中的 agents、monitors、scoreboard。
* 调用：`uvm_config_db::set`。
* 共享状态：`tb_vif`、`vif`、`probe_vif`、`irq_vif`、`jtag_vif`、`halt_run_vif`、
  `rvfi_vif`。

§12  IRQ、JTAG 与 halt-run 参考连接
------------------------------------

IRQ、JTAG 和 halt-run 都通过专用 virtual interface 接入 DUT signals。真实 SoC
集成时，这些 signals 的上游来源不同；当前 TB 的作用是给 UVM agent 提供可控驱动面。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L895-L916`）：

.. code-block:: systemverilog

     eh2_irq_intf #(
       .NUM_THREADS  (`RV_NUM_THREADS),
       .PIC_TOTAL_INT(`RV_PIC_TOTAL_INT)
     ) irq_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect IRQ interface to DUT interrupt signals
     assign timer_int     = irq_intf.timer_int;
     assign soft_int      = irq_intf.soft_int;
     assign extintsrc_req = irq_intf.extintsrc_req;
     assign nmi_int       = irq_intf.nmi_int;

     //--------------------------------------------------------------------------
     // JTAG Interface Instance (for debug stimulus)
     //--------------------------------------------------------------------------
     eh2_jtag_intf jtag_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect JTAG interface to DUT JTAG signals
     assign jtag_tck    = jtag_intf.tck;
     assign jtag_tms    = jtag_intf.tms;
     assign jtag_tdi    = jtag_intf.tdi;
     assign jtag_trst_n = jtag_intf.trst_n;
     assign jtag_intf.tdo = jtag_tdo;

逐段解释：

* 第 L895-L898 行：IRQ interface 用 `RV_NUM_THREADS` 和 `RV_PIC_TOTAL_INT`
  参数化，匹配 wrapper interrupt widths。
* 第 L900-L904 行：timer、soft、external interrupt 和 NMI 从 `irq_intf` 驱动到
  DUT inputs。
* 第 L909-L916 行：JTAG input pins 从 `jtag_intf` 驱动，DUT 输出 `jtag_tdo`
  回写到 interface。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L921-L934`）：

.. code-block:: systemverilog

     eh2_halt_run_intf halt_run_vif (.clk(core_clk), .rst_n(rst_l));

     // Connect halt/run interface to DUT signals
     assign mpc_debug_halt_req = halt_run_vif.mpc_debug_halt_req;
     assign mpc_debug_run_req  = halt_run_vif.mpc_debug_run_req;
     assign mpc_reset_run_req  = halt_run_vif.mpc_reset_run_req;
     assign i_cpu_halt_req     = halt_run_vif.i_cpu_halt_req;
     assign i_cpu_run_req      = halt_run_vif.i_cpu_run_req;

     // Feed acknowledgment signals back to interface
     assign halt_run_vif.o_cpu_halt_ack     = o_cpu_halt_ack[0];
     assign halt_run_vif.o_cpu_run_ack      = o_cpu_run_ack[0];
     assign halt_run_vif.o_cpu_halt_status  = o_cpu_halt_status[0];
     assign halt_run_vif.o_debug_mode_status = o_debug_mode_status[0];

逐段解释：

* 第 L921 行：halt/run interface 与 `core_clk`、`rst_l` 同步。
* 第 L924-L928 行：request signals 从 virtual interface 驱动到 DUT。
* 第 L930-L934 行：ack/status signals 从 DUT thread 0 回写到 interface。该代码只取
  `[0]`，因此当前 halt-run agent 参考连接聚焦 thread 0。

接口关系：

* 被调用：IRQ agent、JTAG agent、halt-run sequences。
* 调用：continuous assign。
* 共享状态：`irq_vif`、`jtag_vif`、`halt_run_vif` 与对应 DUT pins。

§13  RVFI sidecar 连接
-----------------------

`eh2_veer_wrapper_rvfi` 是 sidecar，不替换 DUT wrapper。TB 将 wrapper trace outputs
和从 LSU AXI4 事务派生出的 memory probe 输入到 sidecar，sidecar 输出标准化的
RVFI-equivalent fields 到 `eh2_rvfi_if`。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L749-L767`）：

.. code-block:: systemverilog

     eh2_rvfi_if rvfi_intf (.clk(core_clk), .rst_l(rst_l));

     //--------------------------------------------------------------------------
     // LSU bus valid signal (derived from AXI4 LSU transactions)
     //--------------------------------------------------------------------------
     logic lsu_bus_valid;
     logic [31:0] lsu_bus_addr;
     logic [31:0] lsu_bus_rdata;
     logic [31:0] lsu_bus_wdata;
     logic [3:0]  lsu_bus_wmask;
     logic        lsu_bus_write;

     assign lsu_bus_valid = (lsu_axi_awvalid && lsu_axi_awready) || (lsu_axi_arvalid && lsu_axi_arready) || (lsu_axi_wvalid && lsu_axi_wready) || (lsu_axi_rvalid && lsu_axi_rready);
     assign lsu_bus_addr  = lsu_axi_awvalid ? lsu_axi_awaddr : lsu_axi_araddr;
     assign lsu_bus_rdata = lsu_axi_rdata[31:0];
     assign lsu_bus_wdata = lsu_axi_wdata[31:0];
     assign lsu_bus_wmask = lsu_axi_wstrb[3:0];
     assign lsu_bus_write = lsu_axi_awvalid && lsu_axi_awready;

逐段解释：

* 第 L749 行：TB 创建 `eh2_rvfi_if`，供 RVFI monitor 或 formal 相关路径观察。
* 第 L754-L759 行：LSU bus probe 信号只保留 32-bit address/data 和 4-bit mask。
* 第 L761-L767 行：`lsu_bus_valid` 由 AW、AR、W、R channel handshake 组合而来；
  write 判断基于 AW handshake。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L771-L793`）：

.. code-block:: systemverilog

     eh2_veer_wrapper_rvfi u_rvfi_converter (
       .clk              (core_clk),
       .rst_n            (rst_l),

       // Trace inputs from DUT
       .trace_insn       (trace_rv_i_insn_ip[0]),
       .trace_address    (trace_rv_i_address_ip[0]),
       .trace_valid      (trace_rv_i_valid_ip[0]),
       .trace_exception  (trace_rv_i_exception_ip[0]),
       .trace_ecause     (trace_rv_i_ecause_ip[0]),
       .trace_interrupt  (trace_rv_i_interrupt_ip[0]),
       .trace_tval       (trace_rv_i_tval_ip[0]),
       .trace_rd_valid   (trace_rv_i_rd_valid_ip[0]),
       .trace_rd_addr    (trace_rv_i_rd_addr_ip[0]),
       .trace_rd_wdata   (trace_rv_i_rd_wdata_ip[0]),

       // LSU bus inputs
       .lsu_bus_valid    (lsu_bus_valid),
       .lsu_bus_addr     (lsu_bus_addr),
       .lsu_bus_rdata    (lsu_bus_rdata),
       .lsu_bus_wdata    (lsu_bus_wdata),
       .lsu_bus_wmask    (lsu_bus_wmask),
       .lsu_bus_write    (lsu_bus_write),

逐段解释：

* 第 L771-L773 行：sidecar 与 TB clock/reset 同步。
* 第 L775-L785 行：trace inputs 只取 `trace_rv_i_*[0]`，即第 0 个 thread 的 trace
  packet。
* 第 L787-L793 行：LSU bus probe 由前一段派生信号提供。

关键代码（`rtl/eh2_veer_wrapper_rvfi.sv:L18-L40`）：

.. code-block:: systemverilog

   module eh2_veer_wrapper_rvfi (
       input  logic        clk,
       input  logic        rst_n,

       // Trace inputs (from DUT trace ports, live in tb_top)
       input  logic [63:0] trace_insn,
       input  logic [63:0] trace_address,
       input  logic [1:0]  trace_valid,
       input  logic [1:0]  trace_exception,
       input  logic [4:0]  trace_ecause,
       input  logic [1:0]  trace_interrupt,
       input  logic [31:0] trace_tval,
       input  logic [1:0]  trace_rd_valid,
       input  logic [9:0]  trace_rd_addr,
       input  logic [63:0] trace_rd_wdata,

       // LSU bus inputs (from AXI4 bus signals in tb_top)
       input  logic        lsu_bus_valid,
       input  logic [31:0] lsu_bus_addr,
       input  logic [31:0] lsu_bus_rdata,
       input  logic [31:0] lsu_bus_wdata,
       input  logic [3:0]  lsu_bus_wmask,
       input  logic        lsu_bus_write,

逐段解释：

* 第 L18-L32 行：sidecar module 输入 trace packet 和写回字段，这些字段来自 DUT
  trace output ports。
* 第 L34-L40 行：sidecar 还接收 TB 派生的 LSU bus probe，用于填充 RVFI memory
  fields。

关键代码（`rtl/eh2_veer_wrapper_rvfi.sv:L107-L122`）：

.. code-block:: systemverilog

       assign trace_i0_valid      = trace_valid[0];
       assign trace_i1_valid      = trace_valid[1];
       assign trace_i0_pc         = trace_address[31:0];
       assign trace_i1_pc         = trace_address[63:32];
       assign trace_i0_insn       = trace_insn[31:0];
       assign trace_i1_insn       = trace_insn[63:32];
       assign trace_i0_exception  = trace_exception[0];
       assign trace_i1_exception  = trace_exception[1];
       assign trace_i0_interrupt  = trace_interrupt[0];
       assign trace_i1_interrupt  = trace_interrupt[1];
       assign trace_i0_exc_cause  = trace_ecause[3:0];
       assign trace_i1_exc_cause  = trace_ecause[3:0];
       assign trace_i0_rd_addr    = trace_rd_addr[4:0];
       assign trace_i1_rd_addr    = trace_rd_addr[9:5];
       assign trace_i0_rd_wdata   = trace_rd_wdata[31:0];
       assign trace_i1_rd_wdata   = trace_rd_wdata[63:32];

逐段解释：

* 第 L107-L112 行：64-bit trace address 和 instruction 被拆成 i0 低 32 bit、i1 高
  32 bit。
* 第 L113-L118 行：exception、interrupt 和 cause 按 lane 派生。`trace_ecause`
  在当前实现中同一 `[3:0]` 同时供 i0/i1 使用。
* 第 L119-L122 行：`trace_rd_addr[4:0]` 是 i0，`trace_rd_addr[9:5]` 是 i1；
  写回数据同样按低/高 32 bit 拆分。

接口关系：

* 被调用：`core_eh2_tb_top.sv` 实例化 `u_rvfi_converter`。
* 调用：无 DPI；全部为 SystemVerilog assign 和 `always_ff`。
* 共享状态：`rvfi_intf`、trace packet、LSU bus probe、`wb_seq`。

§14  地址常量与 mailbox 约定
-----------------------------

地址常量来自上游 default snapshot 的 `common_defines.vh`。本文只列源码中存在的
reset vector、ICCM、DCCM、PIC、external data、serial IO 和 debug SB memory 常量。
旧文档中把 ICCM 默认写成 `0x0000_0000` 的说法不符合当前 `common_defines.vh`。

关键代码（`/home/host/Cores-VeeR-EH2/snapshots/default/common_defines.vh:L72-L88`）：

.. code-block:: systemverilog

   `define RV_PIC_BASE_ADDR 32'hf00c0000
   `define RV_PIC_MEIGWCTRL_COUNT 127
   `define RV_PIC_BITS 15
   `define RV_PIC_MEITP_MASK 'h0
   `define RV_PIC_MEIGWCLR_OFFSET 'h5000
   `define RV_PIC_MEIDELS_MASK 'h1
   `define RV_PIC_2CYCLE 1
   `define RV_PIC_MEIDELS_COUNT 127
   `define RV_PIC_MEIP_OFFSET 'h1000
   `define RV_PIC_OFFSET 10'hc0000
   `define RV_PIC_SIZE 32
   `define RV_PIC_MEIE_OFFSET 'h2000
   `define RV_PIC_INT_WORDS 4
   `define RV_PIC_MEITP_OFFSET 'h1800
   `define RV_PIC_MEIPL_COUNT 127
   `define RV_PIC_MEIGWCTRL_OFFSET 'h4000
   `define RV_RESET_VEC 'h80000000

逐段解释：

* 第 L72 行：PIC base address 是 `32'hf00c0000`。
* 第 L81-L82 行：PIC offset 和 size 分别是 `10'hc0000`、`32`。
* 第 L88 行：reset vector 常量是 `'h80000000`，与 TB 默认 `reset_vector`
  `32'h80000000` 一致。

关键代码（`/home/host/Cores-VeeR-EH2/snapshots/default/common_defines.vh:L100-L118`）：

.. code-block:: systemverilog

   `define RV_ICCM_SADR 32'hee000000
   `define RV_ICCM_SIZE 64
   `define RV_ICCM_SIZE_64 
   `define RV_ICCM_BITS 16
   `define RV_ICCM_DATA_CELL ram_4096x39
   `define RV_ICCM_EADR 32'hee00ffff
   `define RV_UNUSED_REGION7 'h00000000
   `define RV_EXTERNAL_DATA 'hc0580000
   `define RV_SERIALIO 'hd0580000
   `define RV_UNUSED_REGION3 'h40000000
   `define RV_UNUSED_REGION2 'h50000000
   `define RV_UNUSED_REGION1 'h60000000
   `define RV_UNUSED_REGION4 'h30000000
   `define RV_EXTERNAL_MEM_HOLE 'h90000000
   `define RV_UNUSED_REGION5 'h20000000
   `define RV_UNUSED_REGION0 'h70000000
   `define RV_UNUSED_REGION6 'h10000000
   `define RV_EXTERNAL_DATA_1 'hb0000000
   `define RV_DEBUG_SB_MEM 'ha0580000

逐段解释：

* 第 L100-L105 行：ICCM start/end address 是 `32'hee000000` 到 `32'hee00ffff`，
  size 为 `64`。
* 第 L107-L108 行：external data 和 serial IO 常量分别是 `'hc0580000` 与
  `'hd0580000`。TB mailbox 注释使用 `0xD0580000`，与 `RV_SERIALIO` 一致。
* 第 L118 行：debug system bus memory 常量是 `'ha0580000`。

关键代码（`/home/host/Cores-VeeR-EH2/snapshots/default/common_defines.vh:L129-L134`）：

.. code-block:: systemverilog

   `define RV_DCCM_SIZE 64
   `define RV_DCCM_SADR 32'hf0040000
   `define RV_DCCM_ECC_WIDTH 7
   `define RV_DCCM_DATA_CELL ram_2048x39
   `define RV_DCCM_BITS 16
   `define RV_DCCM_EADR 32'hf004ffff

逐段解释：

* 第 L129-L130 行：DCCM size 是 `64`，start address 是 `32'hf0040000`。
* 第 L131-L134 行：DCCM ECC width、data cell、address bits 和 end address 都在同一
  snapshot 中定义，end address 是 `32'hf004ffff`。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L18-L20`）：

.. code-block:: systemverilog

   // Mailbox convention (from VeeR testbench):
   //   Address 0xD0580000: write 0xFF = PASS, 0x01 = FAIL
   //   Other printable chars are console output

逐段解释：

* 第 L18-L20 行：TB mailbox 使用 `0xD0580000`；写 `0xFF` 表示 PASS，写 `0x01`
  表示 FAIL，其他可打印字符作为 console output。
* mailbox 是验证约定，不等同于完整 SoC address map。本文不推导“其余地址空间均为外部总线”，
  因为当前源码没有这样的 decoder 说明。

接口关系：

* 被调用：DUT reset、ICCM/DCCM/PIC 配置、mailbox pass/fail monitor。
* 调用：无函数调用；这些是宏定义和 TB 注释。
* 共享状态：`RV_RESET_VEC`、`RV_ICCM_*`、`RV_DCCM_*`、`RV_PIC_*`、`RV_SERIALIO`。

§15  集成检查清单
------------------

下面的检查项只由本章引用的源码推出，用于避免把验证参考环境误写成真实 SoC 约束。

.. list-table::
   :header-rows: 1
   :widths: 28 36 36

   * - 检查项
     - 源码证据
     - 集成含义
   * - DUT wrapper 路径
     - `/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv`
     - 当前验证仓库没有 `rtl/design/eh2_veer_wrapper.sv` 作为 DUT 源。
   * - AXI4 条件端口
     - `RV_BUILD_AXI4`
     - LSU、IFU、SB 是 master；DMA 是 slave。
   * - AHB-Lite 条件端口
     - `RV_BUILD_AHB_LITE`
     - 只有宏打开时 wrapper 才暴露 AHB-Lite 分支。
   * - TB clock
     - `forever #5 core_clk = ~core_clk`
     - 这是仿真时钟，不是 SoC 频率要求。
   * - TB reset
     - `repeat (3)` 后释放 `porst_l`，再 `repeat (3)` 后释放 `rst_l`
     - 这是 TB 序列，不是真实 reset controller 规格。
   * - external memory packets
     - DUT 实例化中全部接 `'0`
     - 当前 TB 不建模外部 SRAM macro packet。
   * - DMA
     - DMA 输入全部 tie off，DUT 输出不赋值
     - 当前 basic tests 没有外部 DMA master。
   * - RVFI
     - `eh2_veer_wrapper_rvfi u_rvfi_converter`
     - RVFI 是 sidecar 适配层，不替换 DUT wrapper。
   * - ICCM address
     - `RV_ICCM_SADR 32'hee000000`
     - 不能写成 `0x0000_0000`。

接口关系：

* 被调用：SoC 集成 review、testbench bring-up、文档抽检。
* 调用：本章前面各节的源码证据。
* 共享状态：wrapper 条件宏、TB connection、address constants、RVFI sidecar。

§16  参考资料
--------------

关联 ADR：

* :ref:`adr-0002` — AXI4 passive monitoring 与 behavioral memory 策略。
* :ref:`adr-0004` — RTL trace 增加 verification-only retire 字段。
* :ref:`adr-0015` — RVFI adapter layer，不修改上游 design RTL。
* :ref:`adr-0016` — `NUM_THREADS=2` cosim 支持路径。

关联章节：

* :ref:`tb_top` — UVM top 的 DUT、interface 和 config DB 连接。
* :ref:`bus_axi_ahb` — AXI4/AHB bus 背景说明。
* :ref:`dccm_iccm` — ICCM/DCCM 紧耦合存储。
* :ref:`rvfi_trace` — RVFI-equivalent trace 和 sidecar。
* :ref:`cosim_scoreboard` — trace/probe/AXI 输入如何进入 cosim scoreboard。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`
* :file:`/home/host/eh2-veri/shared/rtl/axi4_intf.sv`
* :file:`/home/host/eh2-veri/shared/rtl/axi4_slave_mem.sv`
* :file:`/home/host/eh2-veri/rtl/eh2_veer_wrapper_rvfi.sv`
* :file:`/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv`
* :file:`/home/host/Cores-VeeR-EH2/snapshots/default/common_defines.vh`
* :file:`/home/host/Cores-VeeR-EH2/snapshots/default/eh2_pdef.vh`
