.. _appendix_a_rtl_mem:
.. _appendix_a_rtl/mem:

存储器子系统（MEM）
================================================================================

:status: draft
:source: rtl/design/eh2_mem.sv
:last-reviewed: 2026-05-19

§1  范围和数据流
----------------

`eh2_mem` 是 EH2 RTL 中的存储器聚合 wrapper。它不做 DCCM/ICCM 地址 decode 本身，而是把
来自 LSU、IFU、I-cache、BTB 和外部 test packet 的端口汇总后，按参数开关实例化
`eh2_lsu_dccm_mem`、`eh2_ifu_ic_mem`、`eh2_ifu_iccm_mem` 和 `eh2_ifu_btb_mem`。

本文只描述当前源文件中可以直接回溯的行为：顶层 `eh2_mem` 端口、参数化实例化、disable
分支、DCCM/ICCM bank 选择、I-cache data/tag wrapper、BTB SRAM 和 `mem_lib.sv`
中的仿真 RAM 原语。旧文档中“地址译码由 `eh2_mem` 根据 `DCCM_SADR` 与 `DCCM_SIZE`
决定”的说法没有出现在 `eh2_mem.sv` 中；DCCM/ICCM 地址命中与外部总线 bypass 属于
LSU/IFU 控制模块的职责，本文不把它写成本模块行为。

数据流如下::

   LSU DCCM ports
        |
        v
   eh2_mem -- pt.DCCM_ENABLE --> eh2_lsu_dccm_mem --> ram_<depth>x39 / eh2_ram

   IFU ICCM ports
        |
        v
   eh2_mem -- pt.ICCM_ENABLE --> eh2_ifu_iccm_mem --> ram_<depth>x39 / eh2_ram

   I-cache data/tag ports
        |
        v
   eh2_mem -- pt.ICACHE_ENABLE --> eh2_ifu_ic_mem --> EH2_IC_DATA + EH2_IC_TAG

   BTB ports
        |
        v
   eh2_mem -- pt.BTB_USE_SRAM --> eh2_ifu_btb_mem

§2  ``eh2_mem`` 顶层接口
------------------------

§2.1  模块头和时钟控制输入
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 MEM wrapper 的参数化模块边界，并接收 DCCM、ICM、BTB 的 clock override
以及 core ECC disable 控制。

关键代码（``rtl/design/eh2_mem.sv:L18-L30``）：

.. code-block:: systemverilog

   module eh2_mem
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
   (
      input logic         clk,
      input logic         rst_l,
      input logic         dccm_clk_override,
      input logic         icm_clk_override,
      input logic         dec_tlu_core_ecc_disable,
      input logic         btb_clk_override,

逐段解释：

* 第 L18-L22 行：`eh2_mem` import `eh2_pkg::*`，并通过 include `eh2_param.vh`
  获取 `pt` 参数结构。
* 第 L24-L30 行：顶层输入包括 `clk`、`rst_l`、三个 memory clock override 和
  `dec_tlu_core_ecc_disable`。其中 `dccm_clk_override` 只传给 DCCM wrapper，
  `icm_clk_override` 同时传给 I-cache/ICCM wrapper，`btb_clk_override` 传给 BTB
  wrapper。

接口关系：

* 被调用：`eh2_veer` 顶层实例化 MEM wrapper。
* 调用：后续条件实例化的 DCCM、ICCM、I-cache 和 BTB wrapper。
* 共享状态：`pt` 参数结构、`clk`、`rst_l` 和 clock override 输入。

§2.2  DCCM 端口
~~~~~~~~~~~~~~~

职责：把 LSU DCCM 的读写使能、低/高 bank 地址、写数据、读数据和外部 test packet
暴露到 MEM wrapper。

关键代码（``rtl/design/eh2_mem.sv:L31-L45``）：

.. code-block:: systemverilog

      //DCCM ports
      input logic         dccm_wren,
      input logic         dccm_rden,
      input logic [pt.DCCM_BITS-1:0]  dccm_wr_addr_lo,
      input logic [pt.DCCM_BITS-1:0]  dccm_wr_addr_hi,
      input logic [pt.DCCM_BITS-1:0]  dccm_rd_addr_lo,
      input logic [pt.DCCM_BITS-1:0]  dccm_rd_addr_hi,
      input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_wr_data_lo,
      input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_wr_data_hi,

      output logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_rd_data_lo,
      output logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_rd_data_hi,

      input eh2_dccm_ext_in_pkt_t  [pt.DCCM_NUM_BANKS-1:0] dccm_ext_in_pkt,

逐段解释：

* 第 L32-L39 行：DCCM 写入和读取各自有 lo/hi 两套地址与写数据接口。hi 地址和 hi
  数据用于跨 bank 或未对齐访问的第二部分。
* 第 L41-L42 行：读数据同样分 lo/hi 两路返回，宽度是 `pt.DCCM_FDATA_WIDTH`。
* 第 L44 行：`dccm_ext_in_pkt` 按 `pt.DCCM_NUM_BANKS` 展开，后续在 DCCM bank SRAM
  实例中接到 test/repair/power 相关端口。

接口关系：

* 被调用：LSU DCCM 控制路径驱动这些端口。
* 调用：`eh2_lsu_dccm_mem` 通过 `.*` 接收这些端口。
* 共享状态：`pt.DCCM_BITS`、`pt.DCCM_FDATA_WIDTH`、`pt.DCCM_NUM_BANKS`。

§2.3  ICCM 端口
~~~~~~~~~~~~~~~

职责：把 IFU/ICCM 的读写地址、ECC correction 状态、写数据、读数据和外部 test packet
传给 ICCM wrapper。

关键代码（``rtl/design/eh2_mem.sv:L46-L64``）：

.. code-block:: systemverilog

      //ICCM ports
      input eh2_ccm_ext_in_pkt_t   [pt.ICCM_NUM_BANKS/4-1:0][1:0][1:0]  iccm_ext_in_pkt,

      input logic [pt.ICCM_BITS-1:1]  iccm_rw_addr,
      input logic [pt.NUM_THREADS-1:0]iccm_buf_correct_ecc_thr,            // ICCM is doing a single bit error correct cycle
      input logic                     iccm_correction_state,               // We are under a correction - This is needed to guard replacements when hit
      input logic                     iccm_stop_fetch,                     // Squash any lru updates on the red hits as we have fetched ahead
      input logic                     iccm_corr_scnd_fetch,                // dont match on middle bank when under correction


      input logic         ifc_select_tid_f1,
      input logic         iccm_wren,
      input logic         iccm_rden,
      input logic [2:0]   iccm_wr_size,
      input logic [77:0]  iccm_wr_data,

逐段解释：

* 第 L47 行：ICCM 外部 test packet 的维度是 `[pt.ICCM_NUM_BANKS/4-1:0][1:0][1:0]`；
  `eh2_mem` 顶层在实例化 ICCM 时通过 `.*` 传递。
* 第 L49-L54 行：`iccm_rw_addr` 是 ICCM 读写地址；`iccm_buf_correct_ecc_thr`、
  `iccm_correction_state`、`iccm_stop_fetch` 和 `iccm_corr_scnd_fetch` 都参与 ICCM
  ECC correction / redundant row 逻辑。
* 第 L56-L60 行：`ifc_select_tid_f1` 选择 thread；`iccm_wren/rden` 控制写读；
  `iccm_wr_size` 和 78-bit `iccm_wr_data` 传给 ICCM bank write data 选择。

关键代码（``rtl/design/eh2_mem.sv:L62-L64``）：

.. code-block:: systemverilog

      output logic [63:0]  iccm_rd_data,
      output logic [116:0] iccm_rd_data_ecc,
      // Icache and Itag Ports

逐段解释：

* 第 L62-L63 行：ICCM 输出 64-bit instruction data 以及 117-bit ECC data 组合结果。
* 第 L64 行：后续接口转入 I-cache data/tag 端口；ICCM 和 I-cache 共享 IFU 侧主题，
  但实例化的是不同 wrapper。

接口关系：

* 被调用：IFU memory control 与 ECC correction 逻辑驱动这些端口。
* 调用：`eh2_ifu_iccm_mem`。
* 共享状态：`pt.ICCM_BITS`、`pt.ICCM_NUM_BANKS`、`pt.NUM_THREADS`。

§2.4  I-cache 和 BTB 端口
~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接收 I-cache data/tag 的读写/debug/ECC 端口以及 BTB SRAM 端口，并将这些端口
传递给 IFU memory wrapper。

关键代码（``rtl/design/eh2_mem.sv:L65-L95``）：

.. code-block:: systemverilog

      input  logic [31:1]  ic_rw_addr,
      input  logic [pt.ICACHE_NUM_WAYS-1:0]   ic_tag_valid,
      input  logic [pt.ICACHE_NUM_WAYS-1:0]          ic_wr_en  ,         // Which way to write
      input  logic         ic_rd_en,
      input  logic [63:0]  ic_premux_data,     // Premux data to be muxed with each way of the Icache.
      input  logic         ic_sel_premux_data, // Premux data sel

      input eh2_ic_data_ext_in_pkt_t   [pt.ICACHE_NUM_WAYS-1:0][pt.ICACHE_BANKS_WAY-1:0]         ic_data_ext_in_pkt,
      input eh2_ic_tag_ext_in_pkt_t    [pt.ICACHE_NUM_WAYS-1:0]              ic_tag_ext_in_pkt,

      input logic [pt.ICACHE_BANKS_WAY-1:0] [70:0]               ic_wr_data,           // Data to fill to the Icache. With ECC
      output logic [63:0]               ic_rd_data ,          // Data read from Icache. 2x64bits + parity bits. F2 stage. With ECC
      output logic [70:0]               ic_debug_rd_data ,    // Data read from Icache. 2x64bits + parity bits. F2 stage. With ECC

逐段解释：

* 第 L65-L70 行：I-cache data/tag wrapper 接收 31:1 地址、way valid、write enable、
  read enable 和 premux data 选择。
* 第 L72-L73 行：data SRAM 和 tag SRAM 各自有外部 test packet。
* 第 L75-L77 行：写入数据按 I-cache bank 展开，每个 bank 71 bit；普通读返回 64 bit，
  debug data 返回 71 bit。

关键代码（``rtl/design/eh2_mem.sv:L78-L95``）：

.. code-block:: systemverilog

      output logic [25:0]               ictag_debug_rd_data,  // Debug icache tag.
      input  logic [70:0]               ic_debug_wr_data,     // Debug wr cache.


      input logic [pt.ICACHE_INDEX_HI:3]           ic_debug_addr,      // Read/Write addresss to the Icache.
      input  logic                                 ic_debug_rd_en,     // Icache debug rd
      input  logic                                 ic_debug_wr_en,     // Icache debug wr
      input  logic                                 ic_debug_tag_array, // Debug tag array
      input  logic [pt.ICACHE_NUM_WAYS-1:0]        ic_debug_way,       // Debug way. Rd or Wr.


      output  logic [pt.ICACHE_BANKS_WAY-1:0]       ic_eccerr,
      output  logic [pt.ICACHE_BANKS_WAY-1:0]       ic_parerr,


      output logic [pt.ICACHE_NUM_WAYS-1:0]   ic_rd_hit,
      output logic         ic_tag_perr,        // Icache Tag parity error

逐段解释：

* 第 L78-L86 行：debug path 包括 tag debug read data、debug write data、debug address、
  read/write enable、tag array 选择和 way 选择。
* 第 L89-L94 行：I-cache 输出每 bank ECC/parity error、每 way read hit 和 tag parity
  error。

关键代码（``rtl/design/eh2_mem.sv:L96-L113``）：

.. code-block:: systemverilog

      // BTB ports
    input eh2_ccm_ext_in_pkt_t   [1:0] btb_ext_in_pkt,

    input logic                         btb_wren,
    input logic                         btb_rden,
    input logic [1:0] [pt.BTB_ADDR_HI:1] btb_rw_addr,  // per bank
    input logic [1:0] [pt.BTB_ADDR_HI:1] btb_rw_addr_f1,  // per bank
    input logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0]         btb_sram_wr_data,
    input logic [1:0] [pt.BTB_BTAG_SIZE-1:0] btb_sram_rd_tag_f1,

    output eh2_btb_sram_pkt btb_sram_pkt,

    output logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0]      btb_vbank0_rd_data_f1,

逐段解释：

* 第 L97-L104 行：BTB wrapper 接收两路 external test packet、write/read enable、两个
  per-bank 地址、写数据和 f1 阶段读 tag。
* 第 L106-L108 行：BTB 命中信息通过 `eh2_btb_sram_pkt` 输出；virtual bank 0 的 read
  data 是四个 virtual bank 输出之一。

关键代码（``rtl/design/eh2_mem.sv:L108-L113``）：

.. code-block:: systemverilog

    output logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0]      btb_vbank0_rd_data_f1,
    output logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0]      btb_vbank1_rd_data_f1,
    output logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0]      btb_vbank2_rd_data_f1,
    output logic [pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5-1:0]      btb_vbank3_rd_data_f1,

    input  logic         scan_mode

逐段解释：

* 第 L108-L111 行：BTB 输出四个 virtual bank read data，每个宽度是
  `pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5`。
* 第 L113 行：`scan_mode` 进入 MEM wrapper，并通过 `.*` 传给子模块。

接口关系：

* 被调用：IFU I-cache/BTB 控制路径驱动这些端口。
* 调用：`eh2_ifu_ic_mem` 和 `eh2_ifu_btb_mem`。
* 共享状态：`pt.ICACHE_*`、`pt.BTB_*`、`scan_mode`。

§3  ``eh2_mem`` 子模块选择
--------------------------

§3.1  active clock 和 DCCM enable 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 MEM wrapper 内部 active clock，并按 `pt.DCCM_ENABLE` 决定是否实例化 DCCM
memory。

关键代码（``rtl/design/eh2_mem.sv:L116-L128``）：

.. code-block:: systemverilog

      logic  active_clk;
      rvoclkhdr active_cg   ( .en(1'b1),         .l1clk(active_clk), .* );

      // DCCM Instantiation
      if (pt.DCCM_ENABLE == 1) begin: Gen_dccm_enable
         eh2_lsu_dccm_mem #(.pt(pt)) dccm (
            .clk_override(dccm_clk_override),
            .*
         );
      end else begin: Gen_dccm_disable
         assign dccm_rd_data_lo = '0;
         assign dccm_rd_data_hi = '0;
      end

逐段解释：

* 第 L116-L117 行：`rvoclkhdr` 以常量 enable `1'b1` 生成 `active_clk`。该 clock 通过
  `.*` 传入 DCCM/ICCM/I-cache/BTB wrapper。
* 第 L120-L124 行：当 `pt.DCCM_ENABLE == 1` 时实例化 `eh2_lsu_dccm_mem`，参数结构
  `pt` 原样传入，`clk_override` 显式连接到 `dccm_clk_override`。
* 第 L125-L128 行：DCCM disable 时不实例化 memory，并把 lo/hi 读数据输出清零。

接口关系：

* 被调用：由参数 `pt.DCCM_ENABLE` 在 elaboration 时选择。
* 调用：`rvoclkhdr`、`eh2_lsu_dccm_mem`。
* 共享状态：`active_clk`、DCCM read data 输出。

§3.2  I-cache enable 分支
~~~~~~~~~~~~~~~~~~~~~~~~~

职责：打印 memory 配置，并按 `pt.ICACHE_ENABLE` 决定是否实例化 I-cache data/tag wrapper。

关键代码（``rtl/design/eh2_mem.sv:L130-L142``）：

.. code-block:: systemverilog

   initial $display("EH2_MEM: ICACHE_ENABLE=%0d ICCM_ENABLE=%0d DCCM_ENABLE=%0d", pt.ICACHE_ENABLE, pt.ICCM_ENABLE, pt.DCCM_ENABLE);
   if (pt.ICACHE_ENABLE == 1) begin : icache
      eh2_ifu_ic_mem #(.pt(pt)) icm  (
         .clk_override(icm_clk_override),
         .*
      );
   end
   else begin
      assign   ic_rd_hit[3:0] = '0;
      assign   ic_tag_perr    = '0 ;
      assign   ic_rd_data  = '0 ;
      assign   ictag_debug_rd_data  = '0 ;
   end

逐段解释：

* 第 L130 行：elaboration/runtime 初始块打印 `ICACHE_ENABLE`、`ICCM_ENABLE` 和
  `DCCM_ENABLE` 三个参数值。
* 第 L131-L135 行：I-cache enable 时实例化 `eh2_ifu_ic_mem`，并把 `clk_override`
  连接为 `icm_clk_override`。
* 第 L137-L142 行：I-cache disable 时，read hit、tag parity error、read data 和
  tag debug data 输出被清零。该分支没有给 `ic_debug_rd_data`、`ic_eccerr`、`ic_parerr`
  显式赋值；本文只按源码列出已有赋值。

接口关系：

* 被调用：由参数 `pt.ICACHE_ENABLE` 在 elaboration 时选择。
* 调用：`eh2_ifu_ic_mem`。
* 共享状态：I-cache read hit、tag parity、read data 和 debug tag data 输出。

§3.3  ICCM enable 分支
~~~~~~~~~~~~~~~~~~~~~~

职责：按 `pt.ICCM_ENABLE` 选择 ICCM wrapper，并在实例化时显式截取 ICCM 地址与 64-bit
读数据。

关键代码（``rtl/design/eh2_mem.sv:L144-L154``）：

.. code-block:: systemverilog

   if (pt.ICCM_ENABLE == 1) begin : iccm
      eh2_ifu_iccm_mem  #(.pt(pt)) iccm (.*,
                     .clk_override(icm_clk_override),
                     .iccm_rw_addr(iccm_rw_addr[pt.ICCM_BITS-1:1]),
                     .iccm_rd_data(iccm_rd_data[63:0])
                      );
   end
   else  begin
      assign iccm_rd_data     = '0 ;
      assign iccm_rd_data_ecc = '0 ;
   end

逐段解释：

* 第 L144-L149 行：ICCM enable 时实例化 `eh2_ifu_iccm_mem`。除 `.*` 外，显式覆盖
  `clk_override`、`iccm_rw_addr` 和 `iccm_rd_data` 连接。
* 第 L151-L154 行：ICCM disable 时把普通读数据和 ECC 读数据都清零。

接口关系：

* 被调用：由参数 `pt.ICCM_ENABLE` 在 elaboration 时选择。
* 调用：`eh2_ifu_iccm_mem`。
* 共享状态：`iccm_rd_data`、`iccm_rd_data_ecc`。

§3.4  BTB SRAM enable 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 `pt.BTB_USE_SRAM` 选择是否实例化 BTB SRAM wrapper。

关键代码（``rtl/design/eh2_mem.sv:L156-L164``）：

.. code-block:: systemverilog

   // BTB sram
   if (pt.BTB_USE_SRAM == 1) begin : btb
      eh2_ifu_btb_mem #(.pt(pt)) btb  (
         .clk_override(btb_clk_override),
         .*
      );
   end


   endmodule

逐段解释：

* 第 L156-L161 行：`pt.BTB_USE_SRAM == 1` 时实例化 `eh2_ifu_btb_mem`，并把
  `clk_override` 连接到 `btb_clk_override`。
* 第 L162-L164 行：源码没有提供 `else` 分支；当 `pt.BTB_USE_SRAM != 1` 时，本文件
  不对 BTB 输出赋默认值。

接口关系：

* 被调用：由参数 `pt.BTB_USE_SRAM` 在 elaboration 时选择。
* 调用：`eh2_ifu_btb_mem`。
* 共享状态：BTB SRAM packet 和 virtual bank read data 输出。

§4  ``eh2_lsu_dccm_mem``：DCCM bank wrapper
-------------------------------------------

§4.1  DCCM 模块接口和 localparam
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 DCCM 单端口 memory wrapper 的输入输出，并从参数结构推导 bank index depth。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L42-L66``）：

.. code-block:: systemverilog

   module eh2_lsu_dccm_mem
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )(
      input logic         clk,                                             // clock
      input logic         active_clk,                                        // clock
      input logic         rst_l,
      input logic         clk_override,                                    // clock override

      input logic         dccm_wren,                                       // write enable
      input logic         dccm_rden,                                       // read enable
      input logic [pt.DCCM_BITS-1:0]  dccm_wr_addr_lo,                     // write address
      input logic [pt.DCCM_BITS-1:0]  dccm_wr_addr_hi,                     // write address

逐段解释：

* 第 L42-L46 行：DCCM wrapper 与 `eh2_mem` 一样 import `eh2_pkg::*` 并 include
  `eh2_param.vh`。
* 第 L47-L50 行：wrapper 接收 `clk`、`active_clk`、reset 和 clock override。
* 第 L52-L55 行：DCCM 有写使能、读使能和 lo/hi 写地址。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L56-L72``）：

.. code-block:: systemverilog

      input logic [pt.DCCM_BITS-1:0]  dccm_rd_addr_lo,                     // read address
      input logic [pt.DCCM_BITS-1:0]  dccm_rd_addr_hi,                     // read address for the upper bank in case of a misaligned access
      input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_wr_data_lo,              // write data
      input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_wr_data_hi,              // write data
      input eh2_dccm_ext_in_pkt_t  [pt.DCCM_NUM_BANKS-1:0] dccm_ext_in_pkt,    // the dccm packet from the soc

      output logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_rd_data_lo,              // read data from the lo bank
      output logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_rd_data_hi,              // read data from the hi bank

      input  logic         scan_mode
   );


   localparam DCCM_WIDTH_BITS = $clog2(pt.DCCM_BYTE_WIDTH);

逐段解释：

* 第 L56-L63 行：DCCM read/write data 同样区分 lo/hi，external packet 按 bank 展开。
* 第 L65-L66 行：`scan_mode` 进入 wrapper。
* 第 L69 行：`DCCM_WIDTH_BITS` 由 `pt.DCCM_BYTE_WIDTH` 取 `clog2` 得到。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L69-L80``）：

.. code-block:: systemverilog

   localparam DCCM_WIDTH_BITS = $clog2(pt.DCCM_BYTE_WIDTH);
   localparam DCCM_INDEX_BITS = (pt.DCCM_BITS - pt.DCCM_BANK_BITS - pt.DCCM_WIDTH_BITS);
   localparam DCCM_INDEX_DEPTH = (((pt.DCCM_SIZE)*1024)>>($clog2(pt.DCCM_BYTE_WIDTH)))>>$clog2((pt.DCCM_NUM_BANKS));  // Depth of memory bank


   logic [pt.DCCM_NUM_BANKS-1:0]                                        wren_bank;
   logic [pt.DCCM_NUM_BANKS-1:0]                                        rden_bank;
   logic [pt.DCCM_NUM_BANKS-1:0] [pt.DCCM_BITS-1:(pt.DCCM_BANK_BITS+2)] addr_bank;
   logic [pt.DCCM_BITS-1:(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)]           rd_addr_even, rd_addr_odd;
   logic                                                                rd_unaligned, wr_unaligned;
   logic [pt.DCCM_NUM_BANKS-1:0] [pt.DCCM_FDATA_WIDTH-1:0]              dccm_bank_dout;

逐段解释：

* 第 L70-L71 行：index bit 数和每个 bank 的 depth 都由 DCCM 总大小、byte width 和
  bank 数推导。
* 第 L74-L80 行：wrapper 为每个 bank 维护 write enable、read enable、bank address 和
  bank read data。

接口关系：

* 被调用：`eh2_mem` 在 `pt.DCCM_ENABLE == 1` 时实例化。
* 调用：`ram_<depth>x39` 或 Verilator `eh2_ram`。
* 共享状态：DCCM lo/hi 地址、bank 选择、`pt.DCCM_*` 参数。

§4.2  DCCM bank 选择和时钟门控
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 lo/hi 地址判断未对齐访问，为每个 bank 生成读写使能、地址、写数据和 clock
enable。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L95-L115``）：

.. code-block:: systemverilog

   assign rd_unaligned = (dccm_rd_addr_lo[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS] != dccm_rd_addr_hi[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]);
   assign wr_unaligned = (dccm_wr_addr_lo[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS] != dccm_wr_addr_hi[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]);


   // 8 Banks, 16KB each (2048 x 72)
   for (genvar i=0; i<pt.DCCM_NUM_BANKS; i++) begin: mem_bank
      assign  wren_bank[i]        = dccm_wren & ((dccm_wr_addr_hi[2+:pt.DCCM_BANK_BITS] == i) | (dccm_wr_addr_lo[2+:pt.DCCM_BANK_BITS] == i));
      assign  rden_bank[i]        = dccm_rden & ((dccm_rd_addr_hi[2+:pt.DCCM_BANK_BITS] == i) | (dccm_rd_addr_lo[2+:pt.DCCM_BANK_BITS] == i));
      assign  addr_bank[i][(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] = rden_bank[i] ? (((dccm_rd_addr_hi[2+:pt.DCCM_BANK_BITS] == i) & rd_unaligned) ?

逐段解释：

* 第 L95-L96 行：读/写未对齐判断比较 lo 和 hi 地址中的 bank bit 字段。
* 第 L100-L102 行：每个 bank 的 write/read enable 由全局 enable 与 lo/hi 地址是否命中该
  bank 共同决定。
* 第 L103 行：bank 地址在读路径和写路径之间选择；后续条件表达式区分 hi 地址和 lo 地址。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L103-L115``）：

.. code-block:: systemverilog

      assign  addr_bank[i][(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] = rden_bank[i] ? (((dccm_rd_addr_hi[2+:pt.DCCM_BANK_BITS] == i) & rd_unaligned) ?
                                                                                                           dccm_rd_addr_hi[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] :
                                                                                                           dccm_rd_addr_lo[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS]) :
                                                                                                     (((dccm_wr_addr_hi[2+:pt.DCCM_BANK_BITS] == i) & wr_unaligned) ?
                                                                                                           dccm_wr_addr_hi[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] :
                                                                                                           dccm_wr_addr_lo[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS]);


      assign wr_data_bank[i]     = ((dccm_wr_addr_hi[2+:pt.DCCM_BANK_BITS] == i) & wr_unaligned) ? dccm_wr_data_hi[pt.DCCM_FDATA_WIDTH-1:0] : dccm_wr_data_lo[pt.DCCM_FDATA_WIDTH-1:0];

      // clock gating section
      assign  dccm_clken[i] = (wren_bank[i] | rden_bank[i] | clk_override) ;

逐段解释：

* 第 L103-L108 行：读 bank 地址优先选择 hi 地址且未对齐命中该 bank 的情况，否则选择 lo
  地址；写路径同理。
* 第 L111 行：写数据在 hi/lo 写数据之间选择，只有 hi 地址未对齐命中该 bank 时使用
  `dccm_wr_data_hi`。
* 第 L113-L115 行：bank clock enable 是 write enable、read enable 或 clock override
  的 OR。

接口关系：

* 被调用：DCCM bank generate loop。
* 调用：无子函数；组合逻辑驱动 SRAM 实例。
* 共享状态：`dccm_wren/rden`、lo/hi 地址、lo/hi 写数据、`clk_override`。

§4.3  DCCM SRAM depth 选择
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 Verilator 下使用参数化 `eh2_ram`，在其他仿真/综合路径下按
`DCCM_INDEX_DEPTH` 选择固定深度的 `ram_<depth>x39`。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L117-L130``）：

.. code-block:: systemverilog

   `ifdef VERILATOR
         eh2_ram #(DCCM_INDEX_DEPTH,39)  ram (
                                   // Primary ports
                                   .ME(dccm_clken[i]),
                                   .CLK(clk),
                                   .WE(wren_bank[i]),
                                   .ADR(addr_bank[i]),
                                   .D(wr_data_bank[i][pt.DCCM_FDATA_WIDTH-1:0]),
                                   .Q(dccm_bank_dout[i][pt.DCCM_FDATA_WIDTH-1:0]),
                                   .ROP ( ),
                                   // These are used by SoC
                                   `EH2_LOCAL_DCCM_RAM_TEST_PORTS
                                   .*
                                   );

逐段解释：

* 第 L117-L130 行：`VERILATOR` 宏存在时实例化 `eh2_ram #(DCCM_INDEX_DEPTH,39)`。
  主端口连接 bank clock enable、clock、write enable、bank address、write data 和
  read data；test ports 通过 `EH2_LOCAL_DCCM_RAM_TEST_PORTS` 宏展开。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L132-L161``）：

.. code-block:: systemverilog

   `else
      if (DCCM_INDEX_DEPTH == 32768) begin : dccm
         ram_32768x39  dccm_bank (
                                  // Primary ports
                                  .ME(dccm_clken[i]),
                                  .CLK(clk),
                                  .WE(wren_bank[i]),
                                  .ADR(addr_bank[i]),
                                  .D(wr_data_bank[i][pt.DCCM_FDATA_WIDTH-1:0]),
                                  .Q(dccm_bank_dout[i][pt.DCCM_FDATA_WIDTH-1:0]),
                                  .ROP ( ),
                                  // These are used by SoC
                                  `EH2_LOCAL_DCCM_RAM_TEST_PORTS
                                  .*
                                  );
      end
      else if (DCCM_INDEX_DEPTH == 16384) begin : dccm
         ram_16384x39  dccm_bank (

逐段解释：

* 第 L132-L147 行：非 Verilator 路径下，`DCCM_INDEX_DEPTH == 32768` 时使用
  `ram_32768x39`，端口连接与 `eh2_ram` 路径一致。
* 第 L148-L161 行：`DCCM_INDEX_DEPTH == 16384` 时使用 `ram_16384x39`。后续代码继续
  对 8192、4096、3072、2048、1024、512、256、128 做同类分支。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L208-L283``）：

.. code-block:: systemverilog

      else if (DCCM_INDEX_DEPTH == 2048) begin : dccm
         ram_2048x39  dccm_bank (
                                 // Primary ports
                                 .ME(dccm_clken[i]),
                                 .CLK(clk),
                                 .WE(wren_bank[i]),
                                 .ADR(addr_bank[i]),
                                 .D(wr_data_bank[i][pt.DCCM_FDATA_WIDTH-1:0]),
                                 .Q(dccm_bank_dout[i][pt.DCCM_FDATA_WIDTH-1:0]),
                                 .ROP ( ),
                                 // These are used by SoC
                                 `EH2_LOCAL_DCCM_RAM_TEST_PORTS
                                 .*

逐段解释：

* 第 L208-L221 行：2048-depth 分支实例化 `ram_2048x39`。
* 第 L223-L281 行：源码继续列出 1024、512、256 和 128-depth 分支，端口模式与前面
  完全相同。
* 第 L283-L284 行：结束 `VERILATOR` 条件和 `mem_bank` generate block。

接口关系：

* 被调用：每个 DCCM bank 的 generate block。
* 调用：`eh2_ram`、`ram_32768x39`、`ram_16384x39`、`ram_8192x39` 等。
* 共享状态：`DCCM_INDEX_DEPTH`、`dccm_ext_in_pkt[i]`、`dccm_bank_dout[i]`。

§4.4  DCCM read data mux 和 LOAD_TO_USE_PLUS1
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：记录读地址 bank bit，并根据 `pt.LOAD_TO_USE_PLUS1` 选择一拍或两拍后的读数据 mux
路径。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L286-L315``）：

.. code-block:: systemverilog

   // Flops
   rvdffs  #(pt.DCCM_BANK_BITS) rd_addr_lo_ff (.*, .din(dccm_rd_addr_lo[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .dout(dccm_rd_addr_lo_q[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .en(1'b1), .clk(active_clk));
   rvdffs  #(pt.DCCM_BANK_BITS) rd_addr_hi_ff (.*, .din(dccm_rd_addr_hi[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .dout(dccm_rd_addr_hi_q[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .en(1'b1), .clk(active_clk));

   // For Plus1 --> Read data comes out 2 cycle after dccm_rden since we need to flop the bank data and then mux between the banks
   if (pt.LOAD_TO_USE_PLUS1 == 1) begin: GenL2U_1
      logic                                                          dccm_rden_q;
      logic [pt.DCCM_NUM_BANKS-1:0] [pt.DCCM_FDATA_WIDTH-1:0]        dccm_bank_dout_q;
      logic [(DCCM_WIDTH_BITS+pt.DCCM_BANK_BITS-1):DCCM_WIDTH_BITS]  dccm_rd_addr_lo_q2;
      logic [(DCCM_WIDTH_BITS+pt.DCCM_BANK_BITS-1):DCCM_WIDTH_BITS]  dccm_rd_addr_hi_q2;

逐段解释：

* 第 L286-L288 行：lo/hi read address 的 bank bit 被 `rvdffs` 打入 `active_clk`
  时钟域。
* 第 L290-L295 行：当 `pt.LOAD_TO_USE_PLUS1 == 1` 时，代码声明第二级 read enable、
  bank dout 和地址寄存器；注释说明 read data 会在 `dccm_rden` 后两拍输出。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L297-L315``）：

.. code-block:: systemverilog

      // Mux out the read data
      assign dccm_rd_data_lo[pt.DCCM_FDATA_WIDTH-1:0]  = dccm_bank_dout_q[dccm_rd_addr_lo_q2[pt.DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]][pt.DCCM_FDATA_WIDTH-1:0];
      assign dccm_rd_data_hi[pt.DCCM_FDATA_WIDTH-1:0]  = dccm_bank_dout_q[dccm_rd_addr_hi_q2[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]][pt.DCCM_FDATA_WIDTH-1:0];

      for (genvar i=0; i<pt.DCCM_NUM_BANKS; i++) begin: GenBanks
         rvdffe #(pt.DCCM_FDATA_WIDTH) dccm_bank_dout_ff(.*, .din(dccm_bank_dout[i]), .dout(dccm_bank_dout_q[i]), .en(dccm_rden_q | clk_override));
      end

      rvdff  #(1)                  dccm_rden_ff  (.*, .din(dccm_rden), .dout(dccm_rden_q), .clk(active_clk));
      rvdffs  #(pt.DCCM_BANK_BITS) rd_addr_lo_ff (.*, .din(dccm_rd_addr_lo_q[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .dout(dccm_rd_addr_lo_q2[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .en(1'b1), .clk(active_clk));

逐段解释：

* 第 L297-L299 行：lo/hi read data 从二级 bank dout 阵列中按二级地址 bank bit 选择。
* 第 L301-L303 行：每个 bank 的 output 在 `dccm_rden_q` 或 `clk_override` 为真时进入
  `dccm_bank_dout_q`。
* 第 L305-L307 行：read enable 和 lo/hi bank bit 都再打一拍，形成第二级选择条件。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L308-L316``）：

.. code-block:: systemverilog

   end else begin
      // mux out the read data
      assign dccm_rd_data_lo[pt.DCCM_FDATA_WIDTH-1:0]  = dccm_bank_dout[dccm_rd_addr_lo_q[pt.DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]][pt.DCCM_FDATA_WIDTH-1:0];
      assign dccm_rd_data_hi[pt.DCCM_FDATA_WIDTH-1:0]  = dccm_bank_dout[dccm_rd_addr_hi_q[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]][pt.DCCM_FDATA_WIDTH-1:0];

      assign dccm_rd_addr_lo_q2 = '0;
      assign dccm_rd_addr_hi_q2 = '0;
   end
   `undef EH2_LOCAL_DCCM_RAM_TEST_PORTS

逐段解释：

* 第 L308-L311 行：非 plus1 路径直接从 `dccm_bank_dout` 按一级 bank bit 选择 lo/hi
  read data。
* 第 L313-L315 行：未使用的二级地址信号被清零。
* 第 L316 行：文件末尾取消 DCCM RAM test port 宏定义，避免影响后续编译单元。

接口关系：

* 被调用：DCCM read response path。
* 调用：`rvdff`、`rvdffs`、`rvdffe`。
* 共享状态：`pt.LOAD_TO_USE_PLUS1`、`dccm_bank_dout`、lo/hi read address bank bit。

§5  ``eh2_ifu_iccm_mem``：ICCM bank wrapper
-------------------------------------------

§5.1  ICCM 接口和 bank 写数据
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 ICCM wrapper 的读写、ECC correction、thread 选择和 external test packet
端口，并把 78-bit write data 拆成 39-bit bank write data。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L21-L50``）：

.. code-block:: systemverilog

   module eh2_ifu_iccm_mem
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )(
      input logic                                        clk,
      input logic                                        active_clk,
      input logic                                        rst_l,
      input logic                                        clk_override,

      input logic                                        ifc_select_tid_f1,
      input logic                                        iccm_wren,
      input logic                                        iccm_rden,
      input logic [pt.ICCM_BITS-1:1]                     iccm_rw_addr,
      input logic [pt.NUM_THREADS-1:0]                   iccm_buf_correct_ecc_thr,            // ICCM is doing a single bit error correct cycle

逐段解释：

* 第 L21-L25 行：ICCM wrapper 是参数化模块，并 include `eh2_param.vh`。
* 第 L26-L34 行：模块接收 clock、active clock、reset、clock override、thread select、
  write/read enable 和 ICCM read/write address。
* 第 L35 行：`iccm_buf_correct_ecc_thr` 按 thread 展开，用于单 bit ECC correction cycle。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L35-L48``）：

.. code-block:: systemverilog

      input logic [pt.NUM_THREADS-1:0]                   iccm_buf_correct_ecc_thr,            // ICCM is doing a single bit error correct cycle
      input logic                                        iccm_correction_state,               // We are under a correction - This is needed to guard replacements when hit
      input logic                                        iccm_stop_fetch,                     // We have fetched more than needed for 4 bytes. Need to squash any further hits for plru updates
      input logic                                        iccm_corr_scnd_fetch,                // dont match on middle bank when under correction

      input logic [2:0]                                  iccm_wr_size,
      input logic [77:0]                                 iccm_wr_data,


      input  eh2_ccm_ext_in_pkt_t   [pt.ICCM_NUM_BANKS-1:0] iccm_ext_in_pkt,

      output logic [63:0]                                iccm_rd_data,
      output logic [116:0]                               iccm_rd_data_ecc,

逐段解释：

* 第 L35-L38 行：ECC correction 相关输入控制 redundant row 命中、replacement 和 LRU
  更新。
* 第 L40-L41 行：写大小是 3 bit，写数据是 78 bit，即两个 39-bit bank payload。
* 第 L44-L48 行：ICCM external test packet 按 bank 展开；输出是 64-bit data 和
  117-bit ECC data。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L51-L87``）：

.. code-block:: systemverilog

      logic [pt.ICCM_NUM_BANKS-1:0]                                        wren_bank;
      logic [pt.ICCM_NUM_BANKS-1:0]                                        rden_bank;
      logic [pt.ICCM_NUM_BANKS-1:0]                                        iccm_clken;
      logic [pt.ICCM_NUM_BANKS-1:0] [pt.ICCM_BITS-1:pt.ICCM_BANK_INDEX_LO] addr_bank;

      logic [pt.ICCM_NUM_BANKS-1:0] [38:0] iccm_bank_dout, iccm_bank_dout_fn;
      logic [pt.ICCM_NUM_BANKS-1:0] [38:0] iccm_bank_wr_data;
      logic [pt.ICCM_BITS-1:1]             addr_hi_bank;
      logic [pt.ICCM_BITS-1:1]             addr_md_bank;

逐段解释：

* 第 L51-L57 行：ICCM 为每个 bank 维护 write enable、read enable、clock enable、address、
  raw dout、final dout 和 write data。
* 第 L58-L63 行：`addr_hi_bank`、`addr_md_bank` 与多个 read address flop 用于 64-bit
  instruction data 拼接。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L81-L93``）：

.. code-block:: systemverilog

   assign addr_hi_bank[pt.ICCM_BITS-1 :1] = iccm_rw_addr[pt.ICCM_BITS-1 : 1] + 2'b11;
   assign addr_md_bank[pt.ICCM_BITS-1: 1] = iccm_rw_addr[pt.ICCM_BITS-1 : 1] + 2'b10;

   for (genvar i=0; i<pt.ICCM_NUM_BANKS/2; i++) begin: mem_bank_data
      assign iccm_bank_wr_data_vec[(2*i)]   = iccm_wr_data[38:0];
      assign iccm_bank_wr_data_vec[(2*i)+1] = iccm_wr_data[77:39];
   end

   for (genvar i=0; i<pt.ICCM_NUM_BANKS; i++) begin: mem_bank
      assign wren_bank[i]         = iccm_wren & ((iccm_rw_addr[pt.ICCM_BANK_HI:2] == i) | ((addr_hi_bank[pt.ICCM_BANK_HI:2] == i) & (iccm_wr_size[1:0] == 2'b11)));

逐段解释：

* 第 L81-L82 行：hi bank 地址是当前地址加 3，middle bank 地址是当前地址加 2。
* 第 L84-L87 行：78-bit write data 被拆成两个 39-bit entry，分别送到偶数/奇数 bank
  write data vector。
* 第 L89-L90 行：每个 bank 的 write enable 由 `iccm_wren`、当前 bank 命中和双字写
  `iccm_wr_size[1:0] == 2'b11` 的 hi bank 命中共同决定。

接口关系：

* 被调用：`eh2_mem` 在 `pt.ICCM_ENABLE == 1` 时实例化。
* 调用：后续 SRAM 分支和 redundant row logic。
* 共享状态：ICCM bank address、write size、thread select 和 ECC correction 状态。

§5.2  ICCM SRAM depth 选择
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 Verilator/非 Verilator 路径选择参数化 RAM 或固定 depth 的 39-bit RAM。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L89-L123``）：

.. code-block:: systemverilog

   for (genvar i=0; i<pt.ICCM_NUM_BANKS; i++) begin: mem_bank
      assign wren_bank[i]         = iccm_wren & ((iccm_rw_addr[pt.ICCM_BANK_HI:2] == i) | ((addr_hi_bank[pt.ICCM_BANK_HI:2] == i) & (iccm_wr_size[1:0] == 2'b11)));
      assign iccm_bank_wr_data[i] = iccm_bank_wr_data_vec[i];
      assign rden_bank[i]         = iccm_rden & ((iccm_rw_addr[pt.ICCM_BANK_HI:2] == i) | (iccm_rw_addr[pt.ICCM_BANK_HI:2] == 2'(i-1)) | (addr_hi_bank[pt.ICCM_BANK_HI:2] == i) | (addr_md_bank[pt.ICCM_BANK_HI:2] == i));
      assign iccm_clken[i]        =  wren_bank[i] | rden_bank[i] | clk_override;
      assign addr_bank[i][pt.ICCM_BITS-1 : pt.ICCM_BANK_INDEX_LO] = wren_bank[i] ? iccm_rw_addr[pt.ICCM_BITS-1 : pt.ICCM_BANK_INDEX_LO] :

逐段解释：

* 第 L91-L93 行：read enable 可以由当前 bank、前一 bank、hi bank 或 middle bank 命中触发；
  clock enable 是 read/write/override 的 OR。
* 第 L94-L98 行：bank address 在 write address、hi address、middle address 和当前地址
  之间选择。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L101-L123``）：

.. code-block:: systemverilog

    `ifdef VERILATOR

       eh2_ram #(.depth(1<<pt.ICCM_INDEX_BITS), .width(39)) iccm_bank (
                                        // Primary ports
                                        .ME(iccm_clken[i]),
                                        .CLK(clk),
                                        .WE(wren_bank[i]),
                                        .ADR(addr_bank[i]),
                                        .D(iccm_bank_wr_data[i][38:0]),
                                        .Q(iccm_bank_dout[i][38:0]),
                                        .ROP ( ),
                                        // These are used by SoC
                                        .TEST1(iccm_ext_in_pkt[i].TEST1),
                                        .RME(iccm_ext_in_pkt[i].RME),
                                        .RM(iccm_ext_in_pkt[i].RM),

逐段解释：

* 第 L101-L110 行：Verilator 路径使用 `eh2_ram`，depth 是 `1<<pt.ICCM_INDEX_BITS`，
  width 是 39。
* 第 L112-L121 行：SoC test/repair/power 相关端口从 `iccm_ext_in_pkt[i]` 接入。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L125-L170``）：

.. code-block:: systemverilog

    `else
        if (pt.ICCM_INDEX_BITS == 6 ) begin : iccm
                  ram_64x39 iccm_bank (
                                        // Primary ports
                                        .ME(iccm_clken[i]),
                                        .CLK(clk),
                                        .WE(wren_bank[i]),
                                        .ADR(addr_bank[i]),
                                        .D(iccm_bank_wr_data[i][38:0]),
                                        .Q(iccm_bank_dout[i][38:0]),
                                        .ROP ( ),
                                        // These are used by SoC
                                        .TEST1(iccm_ext_in_pkt[i].TEST1),

逐段解释：

* 第 L125-L147 行：`pt.ICCM_INDEX_BITS == 6` 时实例化 `ram_64x39`。
* 第 L149-L170 行：`pt.ICCM_INDEX_BITS == 7` 时实例化 `ram_128x39`。后续分支继续覆盖
  256、512、1024、2048、4096、8192、16384 和 default 32768。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L288-L357``）：

.. code-block:: systemverilog

        else if (pt.ICCM_INDEX_BITS == 13 ) begin : iccm
                  ram_8192x39 iccm_bank (
                                        // Primary ports
                                        .ME(iccm_clken[i]),
                                        .CLK(clk),
                                        .WE(wren_bank[i]),
                                        .ADR(addr_bank[i]),
                                        .D(iccm_bank_wr_data[i][38:0]),
                                        .Q(iccm_bank_dout[i][38:0]),
                                        .ROP ( ),
                                        // These are used by SoC
                                        .TEST1(iccm_ext_in_pkt[i].TEST1),

逐段解释：

* 第 L288-L309 行：index bits 为 13 时实例化 `ram_8192x39`。
* 第 L311-L333 行：index bits 为 14 时实例化 `ram_16384x39`。
* 第 L334-L357 行：其他情况落到 `ram_32768x39`。

接口关系：

* 被调用：ICCM per-bank generate block。
* 调用：`eh2_ram`、`ram_64x39` 到 `ram_32768x39`。
* 共享状态：`pt.ICCM_INDEX_BITS`、`iccm_ext_in_pkt[i]`、`iccm_bank_dout[i]`。

§5.3  ICCM redundant row 与输出拼接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 ECC correction 后用 per-thread redundant row 替代命中 bank data，并把多个
bank 的 39-bit 数据拼成 64-bit instruction data 与 117-bit ECC data。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L358-L419``）：

.. code-block:: systemverilog

    if (pt.NUM_THREADS > 1) begin: more_than_1
          // T0
          assign sel_red1[0][i]  = (redundant_valid[0][1] & (((iccm_rw_addr[pt.ICCM_BITS-1:2] == redundant_address[0][1][pt.ICCM_BITS-1:2]) & (iccm_rw_addr[3:2] == i)) |
                                                             ((addr_md_bank[pt.ICCM_BITS-1:2] == redundant_address[0][1][pt.ICCM_BITS-1:2]) & (addr_md_bank[3:2] == i))  |
                                                             ((addr_hi_bank[pt.ICCM_BITS-1:2] == redundant_address[0][1][pt.ICCM_BITS-1:2]) & (addr_hi_bank[3:2] == i)))) & ~ifc_select_tid_f1;

          assign sel_red0[0][i]  = (redundant_valid[0][0] & (((iccm_rw_addr[pt.ICCM_BITS-1:2] == redundant_address[0][0][pt.ICCM_BITS-1:2]) & (iccm_rw_addr[3:2] == i)) |

逐段解释：

* 第 L358-L366 行：多线程配置下，T0 的 redundant row 1/0 命中条件比较当前地址、
  middle 地址、hi 地址和 redundant address，并要求 `~ifc_select_tid_f1`。
* 第 L376-L391 行：同一区块还为 T1 生成 redundant 命中和 LRU 命中条件，要求
  `ifc_select_tid_f1`。
* 第 L393-L411 行：T0/T1 的 `sel_red0/sel_red1` 被打一拍到 `sel_red*_q`。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L413-L455``）：

.. code-block:: systemverilog

         // muxing out the memory data with the redundant data if the address matches
           assign iccm_bank_dout_fn[i][38:0] = ({39{sel_red1_q[0][i]}}                 & redundant_data[0][1][38:0]) |                                 // T0 , redundant data 1
                                               ({39{sel_red0_q[0][i]}}                 & redundant_data[0][0][38:0]) |                                 // T0 , redundant data 0
                                               ({39{sel_red1_q[pt.NUM_THREADS-1][i]}}  & redundant_data[pt.NUM_THREADS-1][1][38:0]) |                  // T1 , redundant data 1
                                               ({39{sel_red0_q[pt.NUM_THREADS-1][i]}}  & redundant_data[pt.NUM_THREADS-1][0][38:0]) |                  // T1 , redundant data 0
                                               ({39{~sel_red0_q[0][i] & ~sel_red1_q[0][i] &
                                                    ~sel_red0_q[pt.NUM_THREADS-1][i] & ~sel_red1_q[pt.NUM_THREADS-1][i]}} & iccm_bank_dout[i][38:0]);// Bank data

    end
    else begin: one_th

逐段解释：

* 第 L413-L419 行：多线程路径下，`iccm_bank_dout_fn` 在 T0/T1 redundant row data 和
  raw bank data 之间选择。
* 第 L422-L455 行：单线程路径生成同类选择逻辑，但只使用 `pt.NUM_THREADS-1` 这一组
  redundant row。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L461-L527``）：

.. code-block:: systemverilog

   if (pt.NUM_THREADS > 1) begin: more_than_1
   //////////////////////////
   /// T0 T0 T0  T0 T0 T0 //
   //////////////////////////

      assign r0_addr_en[0]        = ~redundant_lru[0] & iccm_buf_correct_ecc_thr[0];
      assign r1_addr_en[0]        =  redundant_lru[0] & iccm_buf_correct_ecc_thr[0];

      assign redundant_lru_en[0]  = iccm_buf_correct_ecc_thr[0] | (((|sel_red0_lru[0][pt.ICCM_NUM_BANKS-1:0]) | (|sel_red1_lru[0][pt.ICCM_NUM_BANKS-1:0])) & iccm_rden & iccm_correction_state & ~iccm_stop_fetch & ~ifc_select_tid_f1);
      assign redundant_lru_in[0]  = iccm_buf_correct_ecc_thr[0] ? ~redundant_lru[0] : (|sel_red0_lru[0][pt.ICCM_NUM_BANKS-1:0]) ? 1'b1 : 1'b0;

逐段解释：

* 第 L461-L470 行：T0 的 redundant row replacement 由 `iccm_buf_correct_ecc_thr[0]`
  触发；LRU 在 correction 或 correction-state read hit 时更新。
* 第 L472-L500 行：T0 的 LRU、redundant address 和 valid bit 通过 `rvdffs` 保存。
* 第 L507-L527 行：T0 redundant data 在后续写同一地址或 correction cycle 时更新。

关键代码（``rtl/design/ifu/eh2_ifu_iccm_mem.sv:L663-L670``）：

.. code-block:: systemverilog

      rvdffs  #(pt.ICCM_BANK_HI)   rd_addr_lo_ff (.*, .clk(active_clk), .din(iccm_rw_addr [pt.ICCM_BANK_HI:1]), .dout(iccm_rd_addr_lo_q[pt.ICCM_BANK_HI:1]), .en(1'b1));   // bit 0 of address is always 0
      rvdffs  #(pt.ICCM_BANK_BITS) rd_addr_md_ff (.*, .clk(active_clk), .din(addr_md_bank[pt.ICCM_BANK_HI:2]),  .dout(iccm_rd_addr_md_q[pt.ICCM_BANK_HI:2]), .en(1'b1));
      rvdffs  #(pt.ICCM_BANK_BITS) rd_addr_hi_ff (.*, .clk(active_clk), .din(addr_hi_bank[pt.ICCM_BANK_HI:2]),  .dout(iccm_rd_addr_hi_q[pt.ICCM_BANK_HI:2]), .en(1'b1));

      assign iccm_rd_data_pre[95:0] = {iccm_bank_dout_fn[iccm_rd_addr_hi_q][31:0], iccm_bank_dout_fn[iccm_rd_addr_md_q][31:0], iccm_bank_dout_fn[iccm_rd_addr_lo_q[pt.ICCM_BANK_HI:2]][31:0]};
      assign iccm_data[63:0]        = 64'({16'b0, (iccm_rd_data_pre[95:0] >> (16*iccm_rd_addr_lo_q[1]))});
      assign iccm_rd_data[63:0]    = iccm_data[63:0];
      assign iccm_rd_data_ecc[116:0]= {iccm_bank_dout_fn[iccm_rd_addr_hi_q][38:0], iccm_bank_dout_fn[iccm_rd_addr_md_q][38:0], iccm_bank_dout_fn[iccm_rd_addr_lo_q[pt.ICCM_BANK_HI:2]][38:0]};

逐段解释：

* 第 L663-L665 行：lo、middle、hi bank address 被打拍，用于读数据选择。
* 第 L667 行：ICCM 先把 hi、middle、lo 三个 bank 的 32-bit data 拼成 96-bit
  `iccm_rd_data_pre`。
* 第 L668-L669 行：根据 `iccm_rd_addr_lo_q[1]` 选择 16-bit 对齐位置，形成 64-bit
  `iccm_rd_data`。
* 第 L670 行：ECC data 输出保留三个 39-bit bank payload，总宽度 117 bit。

接口关系：

* 被调用：ICCM read path 和 ECC correction path。
* 调用：`rvdffs`、`rvdff`。
* 共享状态：`redundant_*`、`iccm_bank_dout_fn`、lo/md/hi bank address。

§6  ``eh2_ifu_ic_mem``：I-cache data/tag wrapper
--------------------------------------------------------------------------------

§6.1  I-cache wrapper 实例化 data 和 tag 子模块
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 I-cache 顶层端口拆给 `EH2_IC_TAG` 与 `EH2_IC_DATA` 两个内部模块。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L20-L60``）：

.. code-block:: systemverilog

   module eh2_ifu_ic_mem
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )
     (

         input logic                                   clk,
         input logic                                   active_clk,
         input logic                                   rst_l,
         input logic                                   clk_override,
         input logic                                   dec_tlu_core_ecc_disable,

         input logic [31:1]                            ic_rw_addr,
         input logic [pt.ICACHE_NUM_WAYS-1:0]          ic_wr_en  ,         // Which way to write

逐段解释：

* 第 L20-L24 行：I-cache memory wrapper 是参数化模块。
* 第 L27-L32 行：输入包括 clock、active clock、reset、clock override 和 core ECC disable。
* 第 L33-L40 行：wrapper 接收 I-cache 地址、way write enable、read enable 和 debug
  control。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L44-L59``）：

.. code-block:: systemverilog

         input  logic [pt.ICACHE_BANKS_WAY-1:0][70:0]  ic_wr_data,         // Data to fill to the Icache. With ECC
         output logic [63:0]                           ic_rd_data ,        // Data read from Icache. 2x64bits + parity bits. F2 stage. With ECC
         output logic [70:0]                           ic_debug_rd_data ,  // Data read from Icache. 2x64bits + parity bits. F2 stage. With ECC
         output logic [25:0]                           ictag_debug_rd_data,// Debug icache tag.
         input logic  [70:0]                           ic_debug_wr_data,   // Debug wr cache.

         output logic [pt.ICACHE_BANKS_WAY-1:0]        ic_eccerr,                 // ecc error per bank
         output logic [pt.ICACHE_BANKS_WAY-1:0]        ic_parerr,                 // ecc error per bank
         input logic [pt.ICACHE_NUM_WAYS-1:0]          ic_tag_valid,              // Valid from the I$ tag valid outside (in flops).

逐段解释：

* 第 L44-L48 行：data write 是按 bank 的 71-bit payload；普通 read 是 64-bit；
  data debug read/write 是 71-bit；tag debug read 是 26-bit。
* 第 L50-L52 行：data side 输出每 bank ECC/parity error；tag valid 由外部 flop 输入。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L63-L79``）：

.. code-block:: systemverilog

      EH2_IC_TAG #(.pt(pt)) ic_tag_inst
             (
              .*,
              .ic_wr_en     (ic_wr_en[pt.ICACHE_NUM_WAYS-1:0]),
              .ic_debug_addr(ic_debug_addr[pt.ICACHE_INDEX_HI:3]),
              .ic_rw_addr   (ic_rw_addr[31:3])
              ) ;

      EH2_IC_DATA #(.pt(pt)) ic_data_inst
             (
              .*,
              .ic_wr_en     (ic_wr_en[pt.ICACHE_NUM_WAYS-1:0]),
              .ic_debug_addr(ic_debug_addr[pt.ICACHE_INDEX_HI:3]),

逐段解释：

* 第 L63-L69 行：`EH2_IC_TAG` 接收 `ic_wr_en`、debug address 和 `ic_rw_addr[31:3]`。
* 第 L71-L77 行：`EH2_IC_DATA` 接收同一组 write enable/debug address，但 data side
  使用 `ic_rw_addr[31:1]`。
* 第 L79 行：`eh2_ifu_ic_mem` 本身只作为 data/tag wrapper，不直接展开 SRAM。

接口关系：

* 被调用：`eh2_mem` 在 `pt.ICACHE_ENABLE == 1` 时实例化。
* 调用：`EH2_IC_TAG`、`EH2_IC_DATA`。
* 共享状态：I-cache top-level 端口、debug 控制、ECC disable。

§6.2  ``EH2_IC_DATA`` read/write enable 和 debug path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 I-cache data RAM 生成 per-bank/per-way read/write enable、debug write data 选择、
clock enable 和 read address。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L190-L218``）：

.. code-block:: systemverilog

   //-----------------------------------------------------------
   // ----------- Logic section starts here --------------------
   //-----------------------------------------------------------
      assign  ic_debug_rd_way_en[pt.ICACHE_NUM_WAYS-1:0] =  {pt.ICACHE_NUM_WAYS{ic_debug_rd_en & ~ic_debug_tag_array}} & ic_debug_way[pt.ICACHE_NUM_WAYS-1:0] ;
      assign  ic_debug_wr_way_en[pt.ICACHE_NUM_WAYS-1:0] =  {pt.ICACHE_NUM_WAYS{ic_debug_wr_en & ~ic_debug_tag_array}} & ic_debug_way[pt.ICACHE_NUM_WAYS-1:0] ;

      always_comb begin : clkens
         ic_bank_way_clken   = '0;

         for ( int i=0; i<pt.ICACHE_BANKS_WAY; i++) begin: wr_ens

逐段解释：

* 第 L193-L194 行：debug data array read/write way enable 只在 `~ic_debug_tag_array`
  时有效，并按 `ic_debug_way` 选择 way。
* 第 L196-L199 行：`clkens` 组合块先把所有 bank/way clock enable 清零，再进入 bank
  loop。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L199-L218``）：

.. code-block:: systemverilog

         for ( int i=0; i<pt.ICACHE_BANKS_WAY; i++) begin: wr_ens
          ic_b_sb_wren[i]        =  ic_wr_en[pt.ICACHE_NUM_WAYS-1:0]  |
                                          (ic_debug_wr_way_en[pt.ICACHE_NUM_WAYS-1:0] & {pt.ICACHE_NUM_WAYS{ic_debug_addr[pt.ICACHE_BANK_HI : pt.ICACHE_BANK_LO] == i}}) ;
          ic_debug_sel_sb[i]     = (ic_debug_addr[pt.ICACHE_BANK_HI : pt.ICACHE_BANK_LO] == i );
          ic_sb_wr_data[i]       = (ic_debug_sel_sb[i] & ic_debug_wr_en) ? ic_debug_wr_data : ic_bank_wr_data[i] ;
          ic_b_rden[i]           =  ic_rd_en_with_debug & ( ( ~ic_rw_addr_q[pt.ICACHE_BANK_HI] & (i==0)) |
                                                            (( ic_rw_addr_q[pt.ICACHE_BANK_HI] & ic_rw_addr_q[2:1] != 2'b00) & (i==0)) |
                                                            (  ic_rw_addr_q[pt.ICACHE_BANK_HI] & (i==1)) |
                                                            ((~ic_rw_addr_q[pt.ICACHE_BANK_HI] & ic_rw_addr_q[2:1] != 2'b00) & (i==1)) ) ;

逐段解释：

* 第 L200-L203 行：每个 bank 的 write enable 是正常 I-cache way write 或 debug write
  命中该 bank；写数据在 debug write data 和正常 bank write data 之间选择。
* 第 L204-L207 行：read enable 根据 `ic_rd_en_with_debug`、bank high bit 和低地址 bit
  决定是否读 bank 0 或 bank 1。
* 第 L211-L216 行：每个 bank/way 的 clock enable 是 read enable、clock override 或 write
  enable 的 OR。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L220-L239``）：

.. code-block:: systemverilog

   // bank read enables
    assign ic_rd_en_with_debug                          = ((ic_rd_en   | ic_debug_rd_en ) & ~(|ic_wr_en));
    assign ic_rw_addr_q[pt.ICACHE_INDEX_HI:1] = (ic_debug_rd_en | ic_debug_wr_en) ?
                                                {ic_debug_addr[pt.ICACHE_INDEX_HI:3],2'b0} :
                                                ic_rw_addr[pt.ICACHE_INDEX_HI:1] ;

      assign ic_rw_addr_q_inc[pt.ICACHE_TAG_LO-1:pt.ICACHE_DATA_INDEX_LO] = ic_rw_addr_q[pt.ICACHE_TAG_LO-1 : pt.ICACHE_DATA_INDEX_LO] + 1 ;
      assign ic_rw_addr_wrap                                        = ic_rw_addr_q[pt.ICACHE_BANK_HI] & ic_rd_en_with_debug & ~(|ic_wr_en[pt.ICACHE_NUM_WAYS-1:0]);
      assign ic_cacheline_wrap_ff                                   = ic_rw_addr_ff[pt.ICACHE_TAG_INDEX_LO-1:pt.ICACHE_BANK_LO] == {(pt.ICACHE_TAG_INDEX_LO - pt.ICACHE_BANK_LO){1'b1}};

逐段解释：

* 第 L221-L224 行：read with debug 只在没有 write enable 时成立；debug 操作使用
  debug address，正常路径使用 `ic_rw_addr`。
* 第 L226-L228 行：代码计算地址增量、wrap 条件和 cacheline wrap 状态。
* 第 L235-L239 行：bank read enable 被打拍，供后续 data mux 使用。

接口关系：

* 被调用：`EH2_IC_DATA` 内部组合逻辑。
* 调用：`rvdff`。
* 共享状态：`ic_rd_en`、`ic_wr_en`、debug 控制、per-bank clock enable。

§6.3  ``EH2_IC_DATA`` SRAM macro 和 bypass 逻辑
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：通过 `EH2_IC_DATA_SRAM` 宏实例化 I-cache data RAM，并在 bypass enable 时保存 read
data 以覆盖同 index hazard。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L267-L287``）：

.. code-block:: systemverilog

   `define EH2_IC_DATA_SRAM(depth,width)                                                                               \
              ram_``depth``x``width ic_bank_sb_way_data (                                                               \
                                        .ME(ic_bank_way_clken_final_up[i][k]),                                          \
                                        .WE (ic_b_sb_wren[k][i]),                                                       \
                                        .D  (ic_sb_wr_data[k][``width-1:0]),                                            \
                                        .ADR(ic_rw_addr_bank_q[k][pt.ICACHE_INDEX_HI:pt.ICACHE_DATA_INDEX_LO]),         \
                                        .Q  (wb_dout_pre_up[i][k]),                                                     \
                                        .CLK (clk),                                                                     \
                                        .ROP ( ),                                                                       \
                                        .TEST1(ic_data_ext_in_pkt[i][k].TEST1),                                         \
                                        .RME(ic_data_ext_in_pkt[i][k].RME),                                             \

逐段解释：

* 第 L267-L274 行：data SRAM 宏按 depth 和 width 实例化 `ram_<depth>x<width>`，连接
  final clock enable、write enable、write data、address、read data、clock 和 ROP。
* 第 L276-L286 行：external packet 中的 TEST1/RME/RM/LS/DS/SD/TEST_RNM/BC1/BC2
  连接到 SRAM test ports。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L288-L334``）：

.. code-block:: systemverilog

   if (pt.ICACHE_BYPASS_ENABLE == 1) begin \
                    assign wrptr_in_up[i][k] = (wrptr_up[i][k] == (pt.ICACHE_NUM_BYPASS-1)) ? '0 : (wrptr_up[i][k] + 1'd1);                                    \
                    rvdffs  #(pt.ICACHE_NUM_BYPASS_WIDTH)  wrptr_ff(.*, .clk(active_clk),  .en(|write_bypass_en_up[i][k]), .din (wrptr_in_up[i][k]), .dout(wrptr_up[i][k])) ;     \
                    assign ic_b_sram_en_up[i][k]              = ic_bank_way_clken[k][i];                             \
                    assign ic_b_read_en_up[i][k]              =  ic_b_sram_en_up[i][k]  &  ic_b_sb_rden[k][i];       \
                    assign ic_b_write_en_up[i][k]             =  ic_b_sram_en_up[i][k] &   ic_b_sb_wren[k][i];       \
                    assign ic_bank_way_clken_final_up[i][k]   =  ic_b_sram_en_up[i][k] &    ~(|sel_bypass_up[i][k]); \

逐段解释：

* 第 L288-L294 行：bypass enable 时，write pointer 循环递增；read/write enable 和 final
  SRAM clock enable 由 bank/way clock enable 与 bypass 选择共同决定。
* 第 L297-L317 行：宏内部对每个 bypass entry 比较 full index、index-only match，生成
  clear、select 和 write bypass enable。
* 第 L321-L329 行：有 bypass 命中时，`wb_dout` 使用 hold data，否则使用 SRAM raw output。
* 第 L331-L334 行：bypass 关闭时，`wb_dout` 直接等于 SRAM raw output，final clock enable
  直接等于原 bank/way clock enable。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L340-L360``）：

.. code-block:: systemverilog

   for (genvar i=0; i<pt.ICACHE_NUM_WAYS; i++) begin: WAYS
      for (genvar k=0; k<pt.ICACHE_BANKS_WAY; k++) begin: BANKS_WAY   // 16B subbank
      if (pt.ICACHE_ECC) begin : ECC1
        logic [pt.ICACHE_NUM_WAYS-1:0][pt.ICACHE_BANKS_WAY-1:0] [71-1:0]        wb_dout_pre_up;           // data and its bit enables
        logic [pt.ICACHE_NUM_WAYS-1:0][pt.ICACHE_BANKS_WAY-1:0] [pt.ICACHE_NUM_BYPASS-1:0] [71-1:0]  wb_dout_hold_up;

        if ($clog2(pt.ICACHE_DATA_DEPTH) == 13 )   begin : size_8192
           `EH2_IC_DATA_SRAM(8192,71)
        end
        else if ($clog2(pt.ICACHE_DATA_DEPTH) == 12 )   begin : size_4096
           `EH2_IC_DATA_SRAM(4096,71)
        end

逐段解释：

* 第 L340-L342 行：data RAM 按 way 和 bank 双重 generate。
* 第 L342-L344 行：ECC enable 时 data width 是 71。
* 第 L346-L360 行：data depth 由 `$clog2(pt.ICACHE_DATA_DEPTH)` 选择，示例中 8192 和
  4096 depth 使用 71-bit RAM；后续分支覆盖更小 depth。

接口关系：

* 被调用：`EH2_IC_DATA` 的 data SRAM generate。
* 调用：`ram_<depth>x71`、`rvdff/rvdffs/rvdffe`。
* 共享状态：`pt.ICACHE_BYPASS_ENABLE`、`pt.ICACHE_DATA_DEPTH`、per-way/per-bank bypass
  arrays。

§6.4  ``EH2_IC_TAG`` tag RAM 和 hit/parity 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：I-cache tag 子模块生成 tag write data、tag SRAM、ECC/parity 检查、debug tag 输出和
read hit。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L1050-L1069``）：

.. code-block:: text

                                 ram_``depth``x``width  ic_way_tag (                                                                           \
                               .ME(ic_tag_clken_final[i]),                                                                                     \
                               .WE (ic_tag_wren_q[i]),                                                                                         \
                               .D  (ic_tag_wr_data[``width-1:0]),                                                                              \
                               .ADR(ic_rw_addr_q[pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO]),                                                  \
                               .Q  (ic_tag_data_raw_pre[i][``width-1:0]),                                                                      \
                               .CLK (clk),                                                                                                     \
                               .ROP ( ),                                                                                                       \
                               .TEST1(ic_tag_ext_in_pkt[i].TEST1),                                                                             \
                               .RME(ic_tag_ext_in_pkt[i].RME),                                                                                 \

逐段解释：

* 第 L1050-L1057 行：tag SRAM 宏实例化 `ram_<depth>x<width>`，连接 final clock enable、
  tag write enable、tag write data、tag index address 和 raw tag data。
* 第 L1059-L1069 行：tag external packet 接到 TEST1/RME/RM/LS/DS/SD/TEST_RNM/BC1/BC2。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L1168-L1189``）：

.. code-block:: systemverilog

      for (genvar i=0; i<pt.ICACHE_NUM_WAYS; i++) begin
         assign w_tout[i][31:pt.ICACHE_TAG_LO] = ic_tag_data_raw[i][31-pt.ICACHE_TAG_LO:0] ;
         assign w_tout[i][32]                  =  1'b0 ; // Unused in this context

         rvdff #(26) ic_tag_data_raw_ff (.*,
                                  .clk(active_clk),
                                  .din ({ic_tag_data_raw[i][25:0]}),
                                  .dout({ic_tag_data_raw_ff[i][25:0]})
                                  );

         rvecc_decode  ecc_decode        (

逐段解释：

* 第 L1168-L1175 行：每个 way 的 raw tag data 被映射到 `w_tout`，并打一拍。
* 第 L1182-L1187 行：ECC enable path 中，`rvecc_decode` 对 tag data 和 ECC bits 做
  decode，输出 single/double ECC error。
* 第 L1189 行：tag way parity error 由 single 或 double ECC error 生成。

关键代码（``rtl/design/ifu/eh2_ifu_ic_mem.sv:L1570-L1582``）：

.. code-block:: systemverilog

      ictag_debug_rd_data[25:0] = '0;
      for ( int j=0; j<pt.ICACHE_NUM_WAYS; j++) begin: debug_rd_out
         ictag_debug_rd_data[25:0] |=  pt.ICACHE_ECC ? ({26{ic_debug_rd_way_en_ff[j]}} & ic_tag_data_raw[j] ) : {4'b0, ({22{ic_debug_rd_way_en_ff[j]}} & ic_tag_data_raw[j][21:0])};
      end
   end

   for (genvar i=0; i<pt.ICACHE_NUM_WAYS; i++) begin : HIT
      assign ic_rd_hit[i] = (w_tout[i][31:pt.ICACHE_TAG_LO] == ic_rw_addr_ff[31:pt.ICACHE_TAG_LO]) & ic_tag_valid[i] & ~ic_wr_en_ff;
   end

   assign  ic_tag_perr  = | (ic_tag_way_perr[pt.ICACHE_NUM_WAYS-1:0] & ic_tag_valid_ff[pt.ICACHE_NUM_WAYS-1:0] ) ;
   endmodule // EH2_IC_TAG

逐段解释：

* 第 L1570-L1573 行：debug tag read data 按 debug selected way OR 聚合；ECC path 使用
  26-bit raw tag，非 ECC path 将 22-bit raw tag 扩展到 26 bit。
* 第 L1576-L1578 行：每个 way 的 `ic_rd_hit` 比较 tag output 与 registered read address，
  同时要求该 way valid 且没有 write enable。
* 第 L1581-L1582 行：tag parity error 是 valid way 上 tag way error 的 OR。

接口关系：

* 被调用：`eh2_ifu_ic_mem`。
* 调用：tag SRAM macros、`rvecc_decode`、parity checker。
* 共享状态：`ic_tag_valid`、`ic_rw_addr_ff`、`ic_tag_way_perr`、debug way enable。

§7  ``eh2_ifu_btb_mem``：BTB SRAM wrapper
-----------------------------------------

§7.1  BTB 接口和 read tag match
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 BTB SRAM 的 bank/way data path，基于 valid bit 和 tag match 生成 way hit。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L21-L48``）：

.. code-block:: systemverilog

   module eh2_ifu_btb_mem
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )(
      input logic                                        clk,
      input logic                                        active_clk,
      input logic                                        rst_l,
      input logic                                        clk_override,

      input  eh2_ccm_ext_in_pkt_t   [1:0] btb_ext_in_pkt,

      input logic                         btb_wren,
      input logic                         btb_rden,
      input logic [1:0] [pt.BTB_ADDR_HI:1] btb_rw_addr,  // per bank read addr, bank0 has write addr

逐段解释：

* 第 L21-L25 行：BTB SRAM wrapper 是参数化模块。
* 第 L26-L34 行：输入包括 clock、active clock、reset、clock override、external test packet
  以及 BTB write/read enable。
* 第 L35-L38 行：`btb_rw_addr` 和 `btb_rw_addr_f1` 都是两路 per-bank 地址；写数据宽度由
  BTB offset/tag/控制位之和决定。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L52-L84``）：

.. code-block:: systemverilog

   localparam BTB_DWIDTH =  pt.BTB_TOFFSET_SIZE+pt.BTB_BTAG_SIZE+5;

   `define RV_TAG BTB_DWIDTH-1:BTB_DWIDTH-pt.BTB_BTAG_SIZE
      localparam PC4=4;
      localparam BOFF=3;
      localparam BV=0;

      logic [1:0][1:0] [2*BTB_DWIDTH-1:0] btb_rd_data, btb_rd_data_raw;

      logic [BTB_DWIDTH-1:0]          btb_bank0e_rd_data_f1, btb_bank0e_rd_data_p1_f1;
      logic [BTB_DWIDTH-1:0]          btb_bank1e_rd_data_f1, btb_bank1e_rd_data_p1_f1;

逐段解释：

* 第 L52-L57 行：BTB entry width 是 target offset、BTB tag 和 5 个控制 bit 的和；`RV_TAG`
  宏定义 tag slice；`PC4/BOFF/BV` 是 entry 内部 bit 位置。
* 第 L59-L68 行：read data 按 bank、way 和 current/plus-one fetch 组织成多组中间信号。
* 第 L80-L84 行：`fetch_start_f1` 由 `btb_rw_addr_f1[1][2:1]` 生成 one-hot。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L117-L133``）：

.. code-block:: systemverilog

   // 2 -way SA, figure out the way hit and mux accordingly
   assign tag_match_way0_f1[1:0] = {btb_bank1_rd_data_way0_f1[BV] & (btb_bank1_rd_data_way0_f1[`RV_TAG] == btb_sram_rd_tag_f1[0][pt.BTB_BTAG_SIZE-1:0]),
                                    btb_bank0_rd_data_way0_f1[BV] & (btb_bank0_rd_data_way0_f1[`RV_TAG] == btb_sram_rd_tag_f1[0][pt.BTB_BTAG_SIZE-1:0])} &
                                   {2{btb_rden_f1}};

   assign tag_match_way1_f1[1:0] = {btb_bank1_rd_data_way1_f1[BV] & (btb_bank1_rd_data_way1_f1[`RV_TAG] == btb_sram_rd_tag_f1[0][pt.BTB_BTAG_SIZE-1:0]),
                                    btb_bank0_rd_data_way1_f1[BV] & (btb_bank0_rd_data_way1_f1[`RV_TAG] == btb_sram_rd_tag_f1[0][pt.BTB_BTAG_SIZE-1:0])} &
                                   {2{btb_rden_f1}};


   assign tag_match_way0_p1_f1[1:0] = {btb_bank1_rd_data_way0_p1_f1[BV] & (btb_bank1_rd_data_way0_p1_f1[`RV_TAG] == btb_sram_rd_tag_f1[1][pt.BTB_BTAG_SIZE-1:0]),

逐段解释：

* 第 L117-L124 行：way0/way1 的 current fetch tag match 同时要求 valid bit `BV`、tag
  相等和 `btb_rden_f1`。
* 第 L127-L133 行：plus-one fetch 的 tag match 使用 `btb_sram_rd_tag_f1[1]` 和
  plus-one read data。

接口关系：

* 被调用：`eh2_mem` 在 `pt.BTB_USE_SRAM == 1` 时实例化。
* 调用：后续 BTB SRAM data mux 和 valid-bit logic。
* 共享状态：`btb_sram_rd_tag_f1`、`btb_rden_f1`、BTB valid bit。

§7.2  BTB virtual bank 输出和写入 valid bit
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 fetch start 重新排列四个 virtual bank 输出，并在写入时维护 per-entry valid
bit。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L158-L165``）：

.. code-block:: systemverilog

      assign btb_sram_pkt.wayhit_f1[3:0] = tag_match_way0_expanded_f1[3:0] | tag_match_way1_expanded_f1[3:0];
      assign btb_sram_pkt.wayhit_p1_f1[3:0] = tag_match_way0_expanded_p1_f1[3:0] | tag_match_way1_expanded_p1_f1[3:0];
      assign btb_sram_pkt.tag_match_way0_f1[1:0] = tag_match_way0_f1[1:0];
      assign btb_sram_pkt.tag_match_way0_p1_f1[1:0] = tag_match_way0_p1_f1[1:0];
      assign btb_sram_pkt.tag_match_vway1_expanded_f1[3:0] = ( ({4{fetch_start_f1[0]}} & {tag_match_way1_expanded_f1[3:0]}) |
                                                               ({4{fetch_start_f1[1]}} & {tag_match_way1_expanded_p1_f1[0], tag_match_way1_expanded_f1[3:1]}) |

逐段解释：

* 第 L158-L161 行：BTB packet 输出 current 和 plus-one 的 wayhit，以及 way0 tag match。
* 第 L162-L165 行：virtual way1 expanded tag match 根据 fetch start 旋转 current/plus-one
  match bits。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L188-L203``）：

.. code-block:: systemverilog

      assign btb_vbank0_rd_data_f1[BTB_DWIDTH-1:0] = ( ({BTB_DWIDTH{fetch_start_f1[0]}} &  btb_bank0e_rd_data_f1[BTB_DWIDTH-1:0]) |
                                                        ({BTB_DWIDTH{fetch_start_f1[1]}} &  btb_bank0o_rd_data_f1[BTB_DWIDTH-1:0]) |
                                                        ({BTB_DWIDTH{fetch_start_f1[2]}} &  btb_bank1e_rd_data_f1[BTB_DWIDTH-1:0]) |
                                                        ({BTB_DWIDTH{fetch_start_f1[3]}} &  btb_bank1o_rd_data_f1[BTB_DWIDTH-1:0]) );
      assign btb_vbank1_rd_data_f1[BTB_DWIDTH-1:0] = ( ({BTB_DWIDTH{fetch_start_f1[0]}} &  btb_bank0o_rd_data_f1[BTB_DWIDTH-1:0]) |
                                                        ({BTB_DWIDTH{fetch_start_f1[1]}} &  btb_bank1e_rd_data_f1[BTB_DWIDTH-1:0]) |

逐段解释：

* 第 L188-L191 行：virtual bank 0 在四种 fetch start 下分别选择 bank0 even、bank0 odd、
  bank1 even、bank1 odd。
* 第 L192-L203 行：virtual bank 1/2/3 继续按 fetch start 旋转选择 current 或 plus-one
  read data。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L209-L233``）：

.. code-block:: systemverilog

      // only write sram if validating entry
      assign wren_bank[1:0] = {btb_wren & btb_rw_addr[0][3] & btb_sram_wr_data[0], btb_wren & ~btb_rw_addr[0][3] & btb_sram_wr_data[0]};

      assign wr_way0_en = btb_wren & ~btb_rw_addr[0][1];
      assign wr_way1_en = btb_wren &  btb_rw_addr[0][1];
      // Way 0, addr 0
      assign btb_bit_en_vec[BTB_DWIDTH-1:0]              = {BTB_DWIDTH{wr_way0_en & ~btb_rw_addr[0][2]}};
      // Way 1, addr 0
      assign btb_bit_en_vec[2*BTB_DWIDTH-1:BTB_DWIDTH]   = {BTB_DWIDTH{wr_way1_en & ~btb_rw_addr[0][2]}};
      // Way 0, addr 4

逐段解释：

* 第 L209-L210 行：只有写入 entry valid bit (`btb_sram_wr_data[0]`) 时，SRAM bank write
  enable 才打开。
* 第 L212-L219 行：write way 和 bit enable 根据地址 bit [1]、[2] 选择 way0/way1 与
  addr0/addr4 区域。

关键代码（``rtl/design/ifu/eh2_ifu_btb_mem.sv:L225-L243``）：

.. code-block:: systemverilog

      assign btb_write_entry[pt.BTB_SIZE-1:0] = ({{pt.BTB_SIZE-1{1'b0}},1'b1} << btb_rw_addr_f1[0]);
      assign btb_valid_ns[pt.BTB_SIZE-1:0] = (btb_wren_f1 & btb_sram_wr_datav_f1) ?
                                             (btb_valid[pt.BTB_SIZE-1:0] | btb_write_entry[pt.BTB_SIZE-1:0]) :
                                             ((btb_wren_f1 & ~btb_sram_wr_datav_f1) ? (btb_valid[pt.BTB_SIZE-1:0] & ~btb_write_entry[pt.BTB_SIZE-1:0]) :
                                              btb_valid[pt.BTB_SIZE-1:0]);
      rvdffe #(pt.BTB_SIZE) btb_valid_ff (.*, .clk(clk),
                                            .en(btb_wren_f1),
                                            .din  (btb_valid_ns[pt.BTB_SIZE-1:0]),
                                            .dout (btb_valid[pt.BTB_SIZE-1:0]));

逐段解释：

* 第 L225-L229 行：`btb_valid_ns` 在 write valid 时 set entry，在 write invalid 时 clear
  entry，否则保持。
* 第 L230-L233 行：`btb_valid` 只在 `btb_wren_f1` 时更新。
* 第 L235-L243 行：read valid bits 从 `btb_valid` 中按 read address 的高位和低 3-bit
  entry 组合取出。

接口关系：

* 被调用：BTB read/write path。
* 调用：`rvdffe`。
* 共享状态：`btb_valid`、`btb_sram_wr_data[0]`、`fetch_start_f1`。

§8  ``mem_lib.sv``：仿真 RAM 原语
---------------------------------

§8.1  RAM test IO 宏
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：统一定义所有 generated RAM module 的 test/repair/power 端口集合。

关键代码（``rtl/design/lib/mem_lib.sv:L16-L29``）：

.. code-block:: systemverilog

   `define EH2_LOCAL_RAM_TEST_IO          \
   input logic WE,              \
   input logic ME,              \
   input logic CLK,             \
   input logic TEST1,           \
   input logic RME,             \
   input logic  [3:0] RM,       \
   input logic LS,              \
   input logic DS,              \
   input logic SD,              \
   input logic TEST_RNM,        \
   input logic BC1,             \
   input logic BC2,             \
   output logic ROP

逐段解释：

* 第 L16-L29 行：宏定义了 RAM module 的通用端口，包括 write enable、memory enable、
  clock、TEST1、RME、RM、LS、DS、SD、TEST_RNM、BC1、BC2 和 ROP。

接口关系：

* 被调用：`EH2_RAM`、`EH2_RAM_BE`、`eh2_ram` 模块定义。
* 调用：无运行时调用。
* 共享状态：SRAM wrapper external packet 端口最终连接到这些端口。

§8.2  ``EH2_RAM`` 和 ``EH2_RAM_BE`` 行为模型
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用宏生成固定 depth/width 的仿真 RAM；普通 RAM 整字写，BE RAM 按 write mask 合并。

关键代码（``rtl/design/lib/mem_lib.sv:L34-L61``）：

.. code-block:: systemverilog

   `define EH2_RAM(depth, width)              \
   module ram_``depth``x``width(               \
      input logic [$clog2(depth)-1:0] ADR,     \
      input logic [(width-1):0] D,             \
      output logic [(width-1):0] Q,            \
       `EH2_LOCAL_RAM_TEST_IO                 \
   );                                          \
   reg [(width-1):0] ram_core [(depth-1):0];   \
   `ifdef GTLSIM                               \
   integer i;                                  \
   initial begin                               \
      Q = '0;                                  \
      for (i=0; i<depth; i=i+1)                \

逐段解释：

* 第 L34-L41 行：`EH2_RAM` 生成名为 `ram_<depth>x<width>` 的 module，地址宽度是
  `clog2(depth)`，存储数组是 `ram_core[depth]`。
* 第 L42-L49 行：`GTLSIM` 下初始化 Q 和每个 memory entry 为 0。

关键代码（``rtl/design/lib/mem_lib.sv:L50-L61``）：

.. code-block:: systemverilog

   always @(posedge CLK) begin                 \
   `ifdef GTLSIM                               \
      if (ME && WE)       ram_core[ADR] <= D;        \
   `else                                       \
      if (ME && WE) begin ram_core[ADR] <= D; Q <= 'x; end  \
   `endif                                      \
      if (ME && ~WE) Q <= ram_core[ADR];       \
   end                                         \
                                               \
   assign ROP = ME;                            \
                                               \
   endmodule

逐段解释：

* 第 L50-L56 行：posedge clock 上，`ME && WE` 写入；非 GTLSIM 写入时还把 Q 置 X；
  `ME && ~WE` 时读出 `ram_core[ADR]`。
* 第 L59-L61 行：ROP 直接等于 ME，随后结束 generated module。

关键代码（``rtl/design/lib/mem_lib.sv:L63-L90``）：

.. code-block:: systemverilog

   `define EH2_RAM_BE(depth, width)           \
   module ram_be_``depth``x``width(            \
      input logic [$clog2(depth)-1:0] ADR,     \
      input logic [(width-1):0] D, WEM,        \
      output logic [(width-1):0] Q,            \
       `EH2_LOCAL_RAM_TEST_IO                 \
   );                                          \
   reg [(width-1):0] ram_core [(depth-1):0];   \
   `ifdef GTLSIM                               \
   integer i;                                  \
   initial begin                               \
      Q = '0;                                  \

逐段解释：

* 第 L63-L70 行：`EH2_RAM_BE` 生成带 `WEM` write enable mask 的
  `ram_be_<depth>x<width>`。
* 第 L71-L78 行：GTLSIM 初始化模式与普通 RAM 一样。
* 第 L79-L86 行：写入时使用 `D & WEM | ~WEM & ram_core[ADR]` 合并新旧数据；读路径仍然是
  `Q <= ram_core[ADR]`。

接口关系：

* 被调用：DCCM、ICCM、I-cache、BTB 等 wrapper 按 depth/width 实例化固定 RAM。
* 调用：无子模块。
* 共享状态：`GTLSIM` 宏影响初始化和写入时 Q 行为。

§8.3  ``eh2_ram`` 和固定 RAM 列表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 Verilator 提供参数化 RAM，同时用宏展开固定深度/宽度的 RAM module。

关键代码（``rtl/design/lib/mem_lib.sv:L92-L117``）：

.. code-block:: systemverilog

   // parameterizable RAM for verilator sims
   module eh2_ram #(depth=2, width=1) (
   input logic [$clog2(depth)-1:0] ADR,
   input logic [(width-1):0] D,
   output logic [(width-1):0] Q,
    `EH2_LOCAL_RAM_TEST_IO
   );
   reg [(width-1):0] ram_core [(depth-1):0];
   `ifdef GTLSIM
   integer i;
   initial begin
      Q = '0;

逐段解释：

* 第 L92-L99 行：`eh2_ram` 是参数化 module，给 Verilator 路径使用。
* 第 L100-L107 行：GTLSIM 下初始化 Q 和 memory。
* 第 L109-L116 行：posedge clock 上执行与普通 `EH2_RAM` 相同的写入和读出规则。

关键代码（``rtl/design/lib/mem_lib.sv:L119-L158``）：

.. code-block:: systemverilog

   `EH2_RAM(32768, 39)
   `EH2_RAM(16384, 39)
   `EH2_RAM(8192, 39)
   `EH2_RAM(4096, 39)
   `EH2_RAM(3072, 39)
   `EH2_RAM(2048, 39)
   `EH2_RAM(1536, 39)//need this for the 48KB DCCM option)
   `EH2_RAM(1024, 39)
   `EH2_RAM(768, 39)
   `EH2_RAM(512, 39)
   `EH2_RAM(256, 39)
   `EH2_RAM(128, 39)
   `EH2_RAM(1024, 20)

逐段解释：

* 第 L119-L130 行：文件生成多个 39-bit RAM，覆盖 32768 到 128 depth，并额外包含
  1536/768 等 DCCM option。
* 第 L131-L158 行：文件继续生成 20/34/68/71-bit 等 width 的普通 RAM，供 tag/data/BTB 等
  wrapper 使用。

关键代码（``rtl/design/lib/mem_lib.sv:L182-L256``）：

.. code-block:: systemverilog

   `EH2_RAM_BE(8192, 142)
   `EH2_RAM_BE(4096, 142)
   `EH2_RAM_BE(2048, 142)
   `EH2_RAM_BE(1024, 142)
   `EH2_RAM_BE(512, 142)
   `EH2_RAM_BE(256, 142)
   `EH2_RAM_BE(128, 142)
   `EH2_RAM_BE(64, 142)
   `EH2_RAM_BE(8192, 284)
   `EH2_RAM_BE(4096, 284)

逐段解释：

* 第 L182-L213 行：文件生成 142、284、136、272-bit 等 byte-enable RAM。
* 第 L214-L252 行：继续生成 52、104、88、44、120、60、62-bit 等 byte-enable RAM。
* 第 L254-L256 行：取消 `EH2_RAM`、`EH2_RAM_BE` 和 `EH2_LOCAL_RAM_TEST_IO` 宏定义。

接口关系：

* 被调用：`eh2_lsu_dccm_mem`、`eh2_ifu_iccm_mem`、`eh2_ifu_ic_mem`、`eh2_ifu_btb_mem`。
* 调用：无子模块。
* 共享状态：固定 RAM module 名称必须与 wrapper 中的 `ram_<depth>x<width>` 引用一致。

§9  参考资料
------------

关联章节：

* :ref:`dccm_iccm` — DCCM/ICCM 功能说明。
* :ref:`appendix_a_rtl_lsu` — LSU DCCM 控制侧。
* :ref:`appendix_a_rtl_ifu` — IFU、I-cache、ICCM 和 BTB 控制侧。

源文件绝对路径：

* :file:`/home/host/eh2-veri/rtl/design/eh2_mem.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_dccm_mem.sv`
* :file:`/home/host/eh2-veri/rtl/design/ifu/eh2_ifu_iccm_mem.sv`
* :file:`/home/host/eh2-veri/rtl/design/ifu/eh2_ifu_ic_mem.sv`
* :file:`/home/host/eh2-veri/rtl/design/ifu/eh2_ifu_btb_mem.sv`
* :file:`/home/host/eh2-veri/rtl/design/lib/mem_lib.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：核对本页关联的 RTL 名称是否能在上游 design 目录和中文手册代码引用中同时找到。

.. code-block:: bash

   rg -n "module |input |output |parameter" /home/host/Cores-VeeR-EH2/design | head -40
   rg -n "literalinclude::|code-block:: verilog" docs/sphinx_cn/source/02_core_reference docs/sphinx_cn/source/appendix_a_rtl | head -40

**进阶题**：确认该 RTL 主题没有脱离当前 VCS/URG coverage 和 LEC 证据口径。

.. code-block:: bash

   rg -n "core_eh2_tb_top.dut|cover.cfg|31635/31635|95.05" docs/sphinx_cn/source/02_core_reference docs/sphinx_cn/source/appendix_a_rtl

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
