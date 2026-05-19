.. _icache:
.. _02_core_reference/icache:

指令缓存（ICache）与 ICCM
================================================================================

:status: draft
:source: syn/include/eh2_param.vh; rtl/design/eh2_mem.sv; rtl/design/ifu/eh2_ifu.sv; rtl/design/ifu/eh2_ifu_mem_ctl.sv; rtl/design/ifu/eh2_ifu_ic_mem.sv; dv/formal/properties/eh2_ifu_assert.sv; dv/uvm/core_eh2/fcov/eh2_fcov_if.sv; dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv; docs/adr/0017-integrity-cosim-waiver.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界与当前结论
--------------------------------------------------------------------------------

本章只描述当前仓库源码中可以直接回溯的指令侧存储行为。当前参数文件
:file:`syn/include/eh2_param.vh` 使能 ICache 和 ICCM，并把 ICache 配置为
``ICACHE_NUM_WAYS=7'h04``、``ICACHE_BANKS_WAY=7'h02``、``ICACHE_LN_SZ=11'h040``、
``ICACHE_NUM_BEATS=8'h08``、``ICACHE_ECC=5'h01``、``ICACHE_WAYPACK=5'h01``。
因此，本章不会沿用旧文档中的 2 way、32 B line 或 1 bank/way 描述。

可见数据流如下：

.. code-block:: bash

   fetch_addr_f1 / ifc_fetch_req_f1
      |
      v
   eh2_ifu_mem_ctl
      |-- ifc_iccm_access_f1=1 --> ICCM read path
      |-- uncacheable fetch -----> miss buffer / bus read / bypass path
      `-- cacheable fetch -------> I$ tag+data read
               |
               v
         eh2_ifu_ic_mem
            |-- EH2_IC_TAG  : tag SRAM, valid, ECC/parity detect
            `-- EH2_IC_DATA : data SRAM, fill, bank mux, ECC/parity detect
               |
               v
         ic_data_f2 / ic_hit_f2 / PMU hit-miss / error-start

**接口关系** ：

* **上游** ：``eh2_ifu`` 暴露 I$、ITAG、ICCM 端口；``eh2_ifu_mem_ctl`` 接收 F1 取指请求、
  flush、``FENCE.I``、DMA 和 AXI read response。
* **下游** ：``eh2_mem`` 根据参数实例化 ``eh2_ifu_ic_mem`` 和 ``eh2_ifu_iccm_mem``。
* **共享状态** ：``ic_tag_valid``、``way_status``、miss buffer、ECC/parity 错误状态、
  PMU hit/miss 事件和 integrity error counter 路径。

§2  参数事实：ICache 当前配置
--------------------------------------------------------------------------------

**职责** ：把 ICache 的路数、bank、line、ECC、bypass 和 tag/data 深度固定到当前
release 参数实例。文档中所有结构性判断均以这些参数为起点。

**关键代码** （``syn/include/eh2_param.vh:L84-L99``）：

.. code-block:: systemverilog

       ICACHE_2BANKS          : 5'h01         ,
       ICACHE_BANK_BITS       : 7'h01         ,
       ICACHE_BANK_HI         : 7'h03         ,
       ICACHE_BANK_LO         : 6'h03         ,
       ICACHE_BANK_WIDTH      : 8'h08         ,
       ICACHE_BANKS_WAY       : 7'h02         ,
       ICACHE_BEAT_ADDR_HI    : 8'h05         ,
       ICACHE_BEAT_BITS       : 8'h03         ,
       ICACHE_BYPASS_ENABLE   : 5'h01         ,
       ICACHE_DATA_DEPTH      : 18'h00200      ,
       ICACHE_DATA_INDEX_LO   : 7'h04         ,
       ICACHE_DATA_WIDTH      : 11'h040        ,
       ICACHE_ECC             : 5'h01         ,
       ICACHE_ENABLE          : 5'h01         ,
       ICACHE_FDATA_WIDTH     : 11'h047        ,
       ICACHE_INDEX_HI        : 9'h00C        ,

**逐段解释** ：

* 第 L84-L89 行：当前实例启用 2-bank 形式，并把 ``ICACHE_BANKS_WAY`` 设为
  ``7'h02``。因此，一个 way 内部不是单 bank；后续 ``EH2_IC_DATA`` 的 bank 循环使用
  ``pt.ICACHE_BANKS_WAY`` 展开。
* 第 L90-L91 行：``ICACHE_BEAT_ADDR_HI=8'h05`` 与 ``ICACHE_BEAT_BITS=8'h03``
  一起定义 miss/fill 相关 beat 计数的地址位宽。``eh2_ifu_mem_ctl`` 后续用这些参数计算
  ``req_addr_count``、``bus_data_beat_count`` 和 line 内 offset。
* 第 L92-L95 行：``ICACHE_BYPASS_ENABLE`` 允许 data SRAM read-after-write bypass；
  ``ICACHE_DATA_DEPTH``、``ICACHE_DATA_INDEX_LO``、``ICACHE_DATA_WIDTH`` 约束 data SRAM
  宏选择和 index 切片。
* 第 L96-L99 行：``ICACHE_ECC=5'h01`` 选择 ECC 路径；``ICACHE_ENABLE=5'h01``
  使 ``eh2_mem`` 实例化 ICache；``ICACHE_INDEX_HI`` 是 tag valid、status 和 data
  SRAM 地址切片的高位。

**关键代码** （``syn/include/eh2_param.vh:L100-L115``）：

.. code-block:: systemverilog

       ICACHE_LN_SZ           : 11'h040        ,
       ICACHE_NUM_BEATS       : 8'h08         ,
       ICACHE_NUM_BYPASS      : 8'h04         ,
       ICACHE_NUM_BYPASS_WIDTH : 8'h03         ,
       ICACHE_NUM_WAYS        : 7'h04         ,
       ICACHE_ONLY            : 5'h00         ,
       ICACHE_SCND_LAST       : 8'h06         ,
       ICACHE_SIZE            : 13'h0020       ,
       ICACHE_STATUS_BITS     : 7'h03         ,
       ICACHE_TAG_BYPASS_ENABLE : 5'h01         ,
       ICACHE_TAG_DEPTH       : 17'h00080      ,
       ICACHE_TAG_INDEX_LO    : 7'h06         ,
       ICACHE_TAG_LO          : 9'h00D        ,
       ICACHE_TAG_NUM_BYPASS  : 8'h02         ,
       ICACHE_TAG_NUM_BYPASS_WIDTH : 8'h02         ,
       ICACHE_WAYPACK         : 5'h01         ,

**逐段解释** ：

* 第 L100-L104 行：当前 line size 参数为 ``11'h040``，fill beat 数为
  ``8'h08``，data bypass entry 数为 ``8'h04``，way 数为 ``7'h04``。因此当前
  ICache 行为必须按 4 way、8 beat 和 data bypass 逻辑解释。
* 第 L105-L108 行：``ICACHE_ONLY=0`` 表示当前配置不是纯 ICache 形态；``ICACHE_SCND_LAST``
  被 uncacheable miss 的 command beat reset 逻辑使用；``ICACHE_STATUS_BITS=7'h03``
  对应 4 way PLRU 的 3-bit status。
* 第 L109-L115 行：tag bypass 启用，tag depth 为 ``17'h00080``，tag index/tag
  low 位分别为 ``7'h06`` 和 ``9'h00D``；``ICACHE_WAYPACK=5'h01`` 使 data/tag
  模块走 way-packed SRAM 生成分支。

**接口关系** ：

* **被调用** ：所有 ``#(`include "eh2_param.vh")`` 的 ICache/ICCM 模块实例读取这些参数。
* **调用** ：参数自身不调用逻辑，但被 ``eh2_mem``、``eh2_ifu_mem_ctl``、
  ``eh2_ifu_ic_mem`` 的 generate 分支消费。
* **共享状态** ：参数决定 ``ic_wr_en``、``ic_rd_hit``、``ic_wr_data``、
  ``way_status`` 等向量宽度。

§3  参数事实：ICCM 当前配置
--------------------------------------------------------------------------------

**职责** ：限定 ICCM 是否存在、地址 region、bank 数和地址宽度。ICCM 在取指侧与
ICache 共用 ``eh2_ifu_mem_ctl``，但命中判断和数据 mux 走独立路径。

**关键代码** （``syn/include/eh2_param.vh:L116-L127``）：

.. code-block:: systemverilog

       ICCM_BANK_BITS         : 7'h02         ,
       ICCM_BANK_HI           : 9'h003        ,
       ICCM_BANK_INDEX_LO     : 9'h004        ,
       ICCM_BITS              : 9'h010        ,
       ICCM_ENABLE            : 5'h01         ,
       ICCM_ICACHE            : 5'h01         ,
       ICCM_INDEX_BITS        : 8'h0C         ,
       ICCM_NUM_BANKS         : 9'h004        ,
       ICCM_ONLY              : 5'h00         ,
       ICCM_REGION            : 8'h0E         ,
       ICCM_SADR              : 36'h0EE000000  ,
       ICCM_SIZE              : 14'h0040       ,

**逐段解释** ：

* 第 L116-L123 行：ICCM 当前有 4 个 bank（``ICCM_NUM_BANKS=9'h004``），地址宽度由
  ``ICCM_BITS=9'h010`` 和 ``ICCM_INDEX_BITS=8'h0C`` 约束。
* 第 L120-L121 行：``ICCM_ENABLE=1`` 且 ``ICCM_ICACHE=1``，因此
  ``eh2_ifu_mem_ctl`` 使用 ICache+ICCM 组合数据 mux 分支。
* 第 L124-L127 行：``ICCM_ONLY=0``，region 参数为 ``8'h0E``，起始地址参数为
  ``36'h0EE000000``，大小参数为 ``14'h0040``。本章只记录这些参数原值，不把它们扩展为
  未在代码中出现的地址映射表。

**接口关系** ：

* **被调用** ：``eh2_ifu_mem_ctl`` 的 ICCM read/write/ECC 分支和 ``eh2_mem`` 的
  ``eh2_ifu_iccm_mem`` 实例化分支读取这些参数。
* **调用** ：无。
* **共享状态** ：``iccm_rw_addr``、``iccm_rden``、``iccm_wren``、
  ``iccm_rd_data``、``iccm_rd_data_ecc``。

§4  ``eh2_mem`` — ICache/ICCM 实例化边界
--------------------------------------------------------------------------------

**职责** ：在统一 memory wrapper 中根据 ``pt.ICACHE_ENABLE`` 和 ``pt.ICCM_ENABLE``
决定是否实例化 ICache data/tag wrapper 与 ICCM memory。

**关键代码** （``rtl/design/eh2_mem.sv:L64-L94``）：

.. code-block:: systemverilog

      // Icache and Itag Ports
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
      output logic [25:0]               ictag_debug_rd_data,  // Debug icache tag.
      input  logic [70:0]               ic_debug_wr_data,     // Debug wr cache.

**逐段解释** ：

* 第 L64-L70 行：``eh2_mem`` 的 ICache 端口把地址、valid、写使能、读使能和 premux
  数据都显式列出。``ic_premux_data`` 与 ``ic_sel_premux_data`` 后续来自
  ``eh2_ifu_mem_ctl`` 的 bypass 或 ICCM mux。
* 第 L72-L75 行：data/tag external input packet 透传到 SRAM wrapper；``ic_wr_data``
  宽度按 ``ICACHE_BANKS_WAY`` 展开，每个 bank 写入 71 bit，当前 ECC 参数下为
  64 bit data 加 7 bit ECC。
* 第 L76-L94 行：读数据、debug 数据、ECC/parity 错误、per-way hit 和 tag parity
  error 都从 ``eh2_ifu_ic_mem`` 回到 IFU 控制侧。

**关键代码** （``rtl/design/eh2_mem.sv:L130-L149``）：

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

   if (pt.ICCM_ENABLE == 1) begin : iccm
      eh2_ifu_iccm_mem  #(.pt(pt)) iccm (.*,

**逐段解释** ：

* 第 L130 行：仿真启动时打印 ICache、ICCM、DCCM 三个 enable 参数，便于日志确认参数实例。
* 第 L131-L135 行：``pt.ICACHE_ENABLE == 1`` 时实例化 ``eh2_ifu_ic_mem``，并用
  ``.*`` 接通前一段端口。
* 第 L137-L142 行：ICache 关闭时，hit、tag error、read data 和 tag debug data
  明确置 0。当前参数启用 ICache，因此这是关闭配置的保护分支。
* 第 L144-L149 行：``pt.ICCM_ENABLE == 1`` 时实例化 ``eh2_ifu_iccm_mem``，并把
  ``iccm_rw_addr`` 切到 ``[pt.ICCM_BITS-1:1]``。

**接口关系** ：

* **被调用** ：core top 通过 memory hierarchy 实例化 ``eh2_mem``。
* **调用** ：``eh2_mem`` 调用 ``eh2_ifu_ic_mem`` 和 ``eh2_ifu_iccm_mem``。
* **共享状态** ：``ic_rd_hit``、``ic_tag_perr``、``ic_rd_data``、``ictag_debug_rd_data``。

§5  ``eh2_ifu`` — IFU 顶层 I$ 与 ICCM 端口
--------------------------------------------------------------------------------

**职责** ：在 IFU 顶层公开 ICache/ITAG 与 ICCM 端口，使 ``eh2_ifu_mem_ctl`` 能够连接
``eh2_mem`` 的物理存储 wrapper。

**关键代码** （``rtl/design/ifu/eh2_ifu.sv:L139-L169``）：

.. code-block:: systemverilog

   //   I$ & ITAG Ports
      output logic [31:1]               ic_rw_addr,         // Read/Write addresss to the Icache.
      output logic [pt.ICACHE_NUM_WAYS-1:0]                ic_wr_en,           // Icache write enable, when filling the Icache.
      output logic                      ic_rd_en,           // Icache read  enable.

      output logic [pt.ICACHE_BANKS_WAY-1:0] [70:0]               ic_wr_data,           // Data to fill to the Icache. With ECC
      input  logic [63:0]               ic_rd_data ,          // Data read from Icache. 2x64bits + parity bits. F2 stage. With ECC
      input  logic [70:0]               ic_debug_rd_data ,    // Data read from Icache. 2x64bits + parity bits. F2 stage. With ECC
      input  logic [25:0]               ictag_debug_rd_data,  // Debug icache tag.
      output logic [70:0]               ic_debug_wr_data,     // Debug wr cache.
      output logic [70:0]               ifu_ic_debug_rd_data, // debug data read

      input  logic [pt.ICACHE_BANKS_WAY-1:0] ic_eccerr,    //
      input  logic [pt.ICACHE_BANKS_WAY-1:0] ic_parerr,

**逐段解释** ：

* 第 L139-L143 行：IFU 输出 ICache 地址、write enable 和 read enable。``ic_wr_en``
  宽度由 ``ICACHE_NUM_WAYS`` 决定，当前为 4 bit。
* 第 L144-L150 行：IFU 输出 fill 写数据和 debug 写数据，同时接收 data/tag debug 读数据。
  ``ic_wr_data`` 的 bank 维度来自 ``ICACHE_BANKS_WAY``。
* 第 L151-L153 行：data array 的 ECC/parity 错误从 memory wrapper 回到 IFU 控制器。

**关键代码** （``rtl/design/ifu/eh2_ifu.sv:L156-L169``）：

.. code-block:: systemverilog

      output logic [63:0]               ic_premux_data,     // Premux data to be muxed with each way of the Icache.
      output logic                      ic_sel_premux_data, // Select the premux data.

      output logic [pt.ICACHE_INDEX_HI:3]  ic_debug_addr,      // Read/Write addresss to the Icache.
      output logic                         ic_debug_rd_en,     // Icache debug rd
      output logic                         ic_debug_wr_en,     // Icache debug wr
      output logic                         ic_debug_tag_array, // Debug tag array
      output logic [pt.ICACHE_NUM_WAYS-1:0]ic_debug_way,       // Debug way. Rd or Wr.


      output logic [pt.ICACHE_NUM_WAYS-1:0]                ic_tag_valid,       // Valid bits when accessing the Icache. One valid bit per way. F2 stage

      input  logic [pt.ICACHE_NUM_WAYS-1:0]                ic_rd_hit,          // Compare hits from Icache tags. Per way.  F2 stage
      input  logic                      ic_tag_perr,        // Icache Tag parity error

**逐段解释** ：

* 第 L156-L157 行：premux 通道用于把 bypass 或 ICCM 数据送入 data wrapper 的 per-way
  mux，而不是只依赖 SRAM 读出的 ``ic_rd_data``。
* 第 L159-L163 行：debug 地址、读写使能、tag/data 选择和 way 选择全部由 IFU 输出。
* 第 L166-L169 行：``ic_tag_valid`` 由 ``eh2_ifu_mem_ctl`` 管理，``ic_rd_hit`` 与
  ``ic_tag_perr`` 由 ``EH2_IC_TAG`` 返回。

**接口关系** ：

* **被调用** ：core top 实例化 ``eh2_ifu``。
* **调用** ：IFU 内部调用 ``eh2_ifu_mem_ctl``，并把这些端口向 ``eh2_mem`` 暴露。
* **共享状态** ：I$ data/tag/debug/error 信号是 IFU 与 memory wrapper 的接口契约。

§6  ``eh2_ifu_mem_ctl`` — 取指侧控制器职责
--------------------------------------------------------------------------------

**职责** ：把 F1 取指请求分类为 ICache、ICCM、uncacheable 或 access fault；驱动 miss
state machine、bus command、ICache fill、ICCM DMA 和错误处理。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L19-L64``）：

.. code-block:: systemverilog

   //********************************************************************************
   // Function: Icache , iccm  control
   // BFF -> F1 -> F2 -> A
   //********************************************************************************

   module eh2_ifu_mem_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )
     (
      input logic clk,
      input logic active_clk,
      input logic [pt.NUM_THREADS-1:0] active_thread_l2clk,
      input logic rst_l,

      input logic  [pt.NUM_THREADS-1:0] exu_flush_final,               // Flush from the pipeline.
      input logic  [pt.NUM_THREADS-1:0] dec_tlu_flush_lower_wb,        // Flush from the pipeline.
      input logic  [pt.NUM_THREADS-1:0] dec_tlu_flush_err_wb,          // Flush from the pipeline due to perr.

**逐段解释** ：

* 第 L19-L22 行：文件注释明确该模块控制 ICache 与 ICCM，并标出 BFF、F1、F2、A 的流水级。
* 第 L24-L33 行：模块引入 ``eh2_pkg`` 并包含 ``eh2_param.vh``，所有 ICache/ICCM 宽度均来自
  当前参数实例。
* 第 L35-L38 行：flush、lower flush、error flush 与 halt 是后续 miss FSM、error FSM 和
  read/write qualify 的共同控制条件。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L40-L64``）：

.. code-block:: systemverilog

      input logic [31:1]                fetch_addr_f1,                 // Fetch Address byte aligned always.      F1 stage.
      input logic                       fetch_tid_f1,
      input logic                       ifc_fetch_uncacheable_f1,      // The fetch request is uncacheable space. F1 stage
      input logic                       ifc_fetch_req_f1,              // Fetch request. Comes with the address.  F1 stage
      input logic                       ifc_fetch_req_f1_raw,          // Fetch request without some qualifications. Used for clock-gating. F1 stage
      input logic                       ifc_iccm_access_f1,            // This request is to the ICCM. Do not generate misses to the bus.
      input logic                       ifc_region_acc_fault_f1,       // Access fault. in ICCM region but offset is outside defined ICCM.
      input logic                       ifc_dma_access_ok,             // It is OK to give dma access to the ICCM. (ICCM is not busy this cycle).
      input logic  [pt.NUM_THREADS-1:0] dec_tlu_fence_i_wb,            // Fence.i instruction is committing. Clear all Icache valids.
      input logic                       ifu_bp_kill_next_f2,           // Branch is predicted taken. Kill the fetch next cycle.
      input logic   [3:0]               ifu_fetch_val,                 // valids on a 2B boundary
      input logic   [3:1]               ifu_bp_inst_mask_f2,            // tell ic which valids to kill because of a taken branch, right justified

      output logic [pt.NUM_THREADS-1:0] ifu_ic_mb_empty_thr,           // Continue with normal fetching. This does not mean that miss is finished.
      output logic                      ic_dma_active  ,               // In the middle of servicing dma request to ICCM. Do not make any new requests.

**逐段解释** ：

* 第 L40-L48 行：F1 级输入已经区分 ``ifc_fetch_uncacheable_f1``、``ifc_iccm_access_f1`` 和
  ``ifc_region_acc_fault_f1``。后续 ICache read enable 和 miss 生成都会使用这些 qualifier。
* 第 L48 行：``dec_tlu_fence_i_wb`` 的注释直接说明 ``FENCE.I`` commit 时清空所有 ICache valid。
* 第 L53-L64 行：模块输出 miss buffer empty、DMA active、write stall、miss idle、I$ error、
  ICCM single-bit ECC error 和 PMU 事件。

**接口关系** ：

* **被调用** ：``eh2_ifu`` 内部实例化。
* **调用** ：控制 ICache wrapper、ICCM wrapper、IFU AXI read channel 和错误状态机。
* **共享状态** ：F1/F2 fetch 请求、miss buffer、bus response、tag valid、way status、PMU 事件。

§7  ICache/ICCM 请求分类与 F1→F2 搬运
--------------------------------------------------------------------------------

**职责** ：在 F2 级把取指请求分成 ICache path 和 ICCM path，并把 F1 的 thread、uncacheable、
ICCM access、region fault 信息打拍。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L515-L523``）：

.. code-block:: systemverilog

      assign fetch_req_icache_f2   = ifc_fetch_req_f2 & ~ifc_iccm_access_f2 & ~ifc_region_acc_fault_f2;
      assign fetch_req_iccm_f2     = ifc_fetch_req_f2 &  ifc_iccm_access_f2;



      rvdffie #(8) bundle1_ff (.*,
                               .din( {fetch_tid_f1,fetch_tid_f2,   fetch_tid_f2_p1,ifu_bus_rsp_tid,ifc_fetch_uncacheable_f1,ifc_iccm_access_f1,ifc_region_acc_fault_final_f1,ifc_region_acc_fault_f1}),
                               .dout({fetch_tid_f2,fetch_tid_f2_p1,fetch_tid_f2_p2,rsp_tid_ff,         fetch_uncacheable_ff,ifc_iccm_access_f2,ifc_region_acc_fault_f2,      ifc_region_acc_fault_only_f2})
                               );

**逐段解释** ：

* 第 L515 行：ICache 请求必须满足 ``ifc_fetch_req_f2``，并且不是 ICCM access，也不是 region
  access fault。
* 第 L516 行：ICCM 请求只要求 ``ifc_fetch_req_f2`` 与 ``ifc_iccm_access_f2`` 同时为 1。
* 第 L520-L523 行：``bundle1_ff`` 把 F1 级 qualifier 和 thread 信息打到 F2/P1/P2 或
  bus response 相关寄存器；后续命中、错误上报和 PMU 都基于这些寄存器化信号。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L526-L538``）：

.. code-block:: systemverilog

      rvdffpcie #(31) ifu_fetch_addr_f2_ff (.*,
                                            .en(ifc_fetch_req_f1),
                                            .din ({fetch_addr_f1[31:1]}),
                                            .dout({ifu_fetch_addr_int_f2[31:1]})
                                            );
      assign vaddr_f2[pt.ICACHE_BEAT_ADDR_HI:1] = ifu_fetch_addr_int_f2[pt.ICACHE_BEAT_ADDR_HI:1] ;




     assign ic_rw_addr[31:1]      = ifu_ic_rw_int_addr[31:1] ;

**逐段解释** ：

* 第 L526-L530 行：F1 地址只在 ``ifc_fetch_req_f1`` 有效时进入 F2 地址寄存器。
* 第 L532 行：``vaddr_f2`` 只保留 beat 地址相关低位，用于 fetch valid、wrap 和 alignment
  相关逻辑。
* 第 L538 行：对外 ICache 地址 ``ic_rw_addr`` 来自内部选择后的 ``ifu_ic_rw_int_addr``；
  该内部地址会在正常取指地址和 miss buffer 写地址之间切换。

**接口关系** ：

* **被调用** ：F1/F2 取指流水每拍执行。
* **调用** ：驱动后续 hit/miss、ICCM mux、miss buffer 地址选择。
* **共享状态** ：``fetch_tid_f2``、``fetch_uncacheable_ff``、``ifc_iccm_access_f2``、
  ``ifc_region_acc_fault_f2``、``ifu_fetch_addr_int_f2``。

§8  ICache read enable 与真实读条件
--------------------------------------------------------------------------------

**职责** ：确保 ICCM 和 uncacheable 取指不发 ICache data/tag read；同时在 flush 条件下保留
必要的 read 行为。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2348-L2361``）：

.. code-block:: systemverilog

      assign   ic_rd_en    =  (ifc_fetch_req_tid_q_f1 & ~ifc_fetch_uncacheable_f1 & ~ifc_iccm_access_f1 ) |
                              (exu_flush_final  & ~ifc_fetch_uncacheable_f1 & ~ifc_iccm_access_f1 )     ;

      assign  ic_real_rd_wp  =  (ifc_fetch_req_tid_q_f1 &  ~ifc_iccm_access_f1  &  ~ifc_region_acc_fault_final_f1 & ~dec_tlu_fence_i_wb & ~stream_miss_f2 & ~ic_act_miss_f2 &
                                  ~ic_miss_under_miss_killf1_f2 &
                                  ~(((miss_state == STREAM) & ~miss_state_en) |
                                 ((miss_state == CRIT_BYP_OK) & ~miss_state_en & ~(miss_nxtstate == MISS_WAIT)) |
                                 ((miss_state == MISS_WAIT) & ~miss_state_en) |
                                 ((miss_state == STALL_SCND_MISS) & ~miss_state_en)  |
                                 ((miss_state == CRIT_WRD_RDY) & ~miss_state_en)  |
                                 ((miss_nxtstate == STREAM) &  miss_state_en)  |
                                 ((miss_nxtstate == DUPL_MISS_WAIT) &  miss_state_en)  |

**逐段解释** ：

* 第 L2348-L2349 行：``ic_rd_en`` 对 uncacheable 和 ICCM access 都取反。因此 ICCM fetch
  不读 ICache，uncacheable fetch 也不读 ICache。
* 第 L2351-L2361 行：``ic_real_rd_wp`` 进一步排除 region fault、``FENCE.I``、stream miss、
  当前 miss、miss-under-miss kill 和多个 miss FSM 停顿状态。这个信号是替换状态/way status
  更新的更严格读条件。

**接口关系** ：

* **被调用** ：每个 F1 取指请求周期计算。
* **调用** ：驱动 ``EH2_IC_DATA`` 和 ``EH2_IC_TAG`` 的 read enable，并参与 way status 更新。
* **共享状态** ：``ifc_fetch_uncacheable_f1``、``ifc_iccm_access_f1``、``dec_tlu_fence_i_wb``、
  ``miss_state``。

§9  ICache、ICCM 与 bypass 数据 mux
--------------------------------------------------------------------------------

**职责** ：在 F2 级决定最终送到 aligner 的 ``ic_data_f2`` 来自 SRAM read、miss bypass 还是
ICCM read data。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L650-L659``）：

.. code-block:: systemverilog

    if (pt.ICCM_ICACHE==1) begin: iccm_icache
     assign sel_iccm_data    =  fetch_req_iccm_f2  ;

     assign ic_final_data[63:0]  = ({64{sel_byp_data | sel_iccm_data | sel_ic_data}} & {ic_rd_data_only[63:0]} ) ;

     assign ic_premux_data[63:0] = ({64{sel_byp_data }} & ic_byp_data_only_new[63:0]) |
                                   ({64{sel_iccm_data}} & iccm_rd_data[63:0]);

     assign ic_sel_premux_data = sel_iccm_data | sel_byp_data ;
    end

**逐段解释** ：

* 第 L650-L652 行：当前参数 ``ICCM_ICACHE=1``，因此此分支为当前组合形态。ICCM 数据选择由
  ``fetch_req_iccm_f2`` 直接驱动。
* 第 L653 行：``ic_final_data`` 仍从 ``ic_rd_data_only`` 取值，但前一拍 ``ic_premux_data``
  可被送入 ICache data wrapper 的 per-way mux。
* 第 L655-L658 行：premux 数据在 bypass 和 ICCM 之间选择；``ic_sel_premux_data`` 为 1 时，
  data wrapper 输出不再只依赖 SRAM 原始读数。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L661-L683``）：

.. code-block:: systemverilog

   if (pt.ICCM_ONLY == 1 ) begin: iccm_only
     assign sel_iccm_data    =  fetch_req_iccm_f2  ;
     assign ic_final_data[63:0]  = ({64{sel_byp_data }} & {ic_byp_data_only_new[63:0]} ) |
                                   ({64{sel_iccm_data}} & iccm_rd_data[63:0]);
     assign ic_premux_data = '0 ;
     assign ic_sel_premux_data = '0 ;
   end

   if (pt.ICACHE_ONLY == 1 ) begin: icache_only
     assign ic_final_data[63:0]  = ({64{sel_byp_data | sel_ic_data}} & {ic_rd_data_only[63:0]} ) ;
     assign ic_premux_data[63:0] = ({64{sel_byp_data }} & {ic_byp_data_only_new[63:0]} ) ;
     assign ic_sel_premux_data =  sel_byp_data ;
   end


   if (pt.NO_ICCM_NO_ICACHE == 1 ) begin: no_iccm_no_icache
     assign ic_final_data[63:0]  = ({64{sel_byp_data }} & {ic_byp_data_only_new[63:0]} ) ;
     assign ic_premux_data = 0 ;
     assign ic_sel_premux_data = '0 ;
   end

     assign ifc_bus_acc_fault_f2[3:0]   =  {4{ic_byp_hit_f2}} & ifu_byp_data_err_f2[3:0] ;
     assign ic_data_f2[63:0]       = ic_final_data[63:0];

**逐段解释** ：

* 第 L661-L679 行：源码保留 ICCM-only、ICache-only 和无 ICCM/ICache 的配置分支；当前参数不会
  进入这些分支，但它们说明 mux 结构由参数控制。
* 第 L682 行：bypass hit 且 bypass data 有错误时，bus access fault mask 会进入
  ``ifc_bus_acc_fault_f2``。
* 第 L683 行：最终对 aligner 可见的数据为 ``ic_data_f2``。

**接口关系** ：

* **被调用** ：F2 数据返回路径每拍计算。
* **调用** ：消费 ``ic_rd_data``、``iccm_rd_data`` 和 miss bypass buffer。
* **共享状态** ：``sel_byp_data``、``sel_iccm_data``、``sel_ic_data``、``ic_premux_data``。

§10  ICCM read/write、DMA 与 ECC 检查
--------------------------------------------------------------------------------

**职责** ：在 ICCM 使能时支持取指读、DMA 读写、单 bit ECC 修正和 double bit error 上报。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L824-L839``）：

.. code-block:: systemverilog

            assign ic_dma_active_in   =  ifc_dma_access_q_ok  & dma_iccm_req ;
            assign iccm_wren          =  (ifc_dma_access_q_ok & dma_iccm_req &  dma_mem_write) | iccm_correct_ecc;
            assign iccm_rden          =  (ifc_dma_access_q_ok & dma_iccm_req & ~dma_mem_write) | (ifc_iccm_access_f1 & ifc_fetch_req_f1);
            assign iccm_dma_rden      =  (ifc_dma_access_q_ok & dma_iccm_req & ~dma_mem_write)                     ;
            assign iccm_wr_size[2:0]  =  {3{dma_iccm_req}}    & dma_mem_sz[2:0] ;

            rvecc_encode  iccm_ecc_encode0 (
                              .din(dma_mem_wdata[31:0]),
                              .ecc_out(dma_mem_ecc[6:0]));

            rvecc_encode  iccm_ecc_encode1 (
                              .din(dma_mem_wdata[63:32]),
                              .ecc_out(dma_mem_ecc[13:7]));

           assign iccm_wr_data[77:0]   =  (iccm_correct_ecc & ~(ifc_dma_access_q_ok & dma_iccm_req)) ?  {iccm_ecc_corr_data_ff[38:0], iccm_ecc_corr_data_ff[38:0]} :
                                          {dma_mem_ecc[13:7],dma_mem_wdata[63:32], dma_mem_ecc[6:0],dma_mem_wdata[31:0]};

**逐段解释** ：

* 第 L824-L827 行：ICCM write 由 DMA write 或 ECC correction 触发；ICCM read 由 DMA read 或
  ``ifc_iccm_access_f1 & ifc_fetch_req_f1`` 触发。
* 第 L828-L839 行：DMA 写数据分为两个 32-bit word，各自生成 7-bit ECC；ECC correction
  路径则写回 ``iccm_ecc_corr_data_ff``。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L856-L883``）：

.. code-block:: systemverilog

            assign iccm_rw_addr[pt.ICCM_BITS-1:1]    = (  ifc_dma_access_q_ok & dma_iccm_req  & ~iccm_correct_ecc) ? dma_mem_addr[pt.ICCM_BITS-1:1] :
                                                    (~(ifc_dma_access_q_ok & dma_iccm_req) &  iccm_correct_ecc) ? {iccm_ecc_corr_index_ff[pt.ICCM_BITS-1:2],1'b0} : fetch_addr_f1[pt.ICCM_BITS-1:1] ;




   /////////////////////////////////////////////////////////////////////////////////////
   // ECC checking logic for ICCM data.                                               //
   /////////////////////////////////////////////////////////////////////////////////////

     assign ic_fetch_val_int_f2[5:0]      = {2'b00, ic_fetch_val_f2[3:0]};
     assign ic_fetch_val_shift_right[5:0] = {ic_fetch_val_int_f2 << ifu_fetch_addr_int_f2[1] } ;
     assign iccm_dma_rd_en[2:0]           = ({1'b0 , (dma_mem_sz_ff[1:0] == 2'b11) , 1'b1 } & {3{iccm_dma_rvalid_in}}) ;

      assign iccm_rdmux_data[116:0] = iccm_rd_data_ecc[116:0];
      for (genvar i=0; i < 3 ; i++) begin : ICCM_ECC_CHECK
         assign iccm_ecc_word_enable[i] = ((|ic_fetch_val_shift_right[(2*i+1):(2*i)] & ~exu_flush_final[fetch_tid_f2] & sel_iccm_data) | iccm_dma_rd_en[i]) & ~dec_tlu_core_ecc_disable;
      rvecc_decode  ecc_decode (

**逐段解释** ：

* 第 L856-L857 行：ICCM 地址在 DMA、ECC correction 和普通 fetch 地址之间选择。
* 第 L866-L872 行：fetch valid 根据 fetch 地址低位移位，再与 DMA read enable 合并，决定哪几个
  32-bit ECC word 需要检查。
* 第 L873 行开始：``rvecc_decode`` 对 ICCM read data 做 ECC decode；是否使能还受
  ``dec_tlu_core_ecc_disable`` 控制。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L873-L904``）：

.. code-block:: systemverilog

      rvecc_decode  ecc_decode (
                              .en(iccm_ecc_word_enable[i]),
                              .sed_ded ( 1'b0 ),    // 1 : means only detection
                              .din(iccm_rdmux_data[(39*i+31):(39*i)]),
                              .ecc_in(iccm_rdmux_data[(39*i+38):(39*i+32)]),
                              .dout(iccm_corrected_data[i][31:0]),
                              .ecc_out(iccm_corrected_ecc[i][6:0]),
                              .single_ecc_error(iccm_single_ecc_error[i]),
                              .double_ecc_error(iccm_double_ecc_error[i]));
     end
       assign iccm_rd_ecc_single_err  = (|iccm_single_ecc_error[2:0]) & ifc_iccm_access_f2 & ifc_fetch_req_f2;
     if (pt.NUM_THREADS > 1) begin: more_than_1_th
       assign ifu_iccm_rd_ecc_single_err[pt.NUM_THREADS-1:0]  = {((|iccm_single_ecc_error[2:0]) & ifc_iccm_access_f2 & ifc_fetch_req_f2 &  fetch_tid_f2),
                                                                 ((|iccm_single_ecc_error[2:0]) & ifc_iccm_access_f2 & ifc_fetch_req_f2 & ~fetch_tid_f2)};
      end  else begin: one_thr
       assign ifu_iccm_rd_ecc_single_err[pt.NUM_THREADS-1:0]  = ((|iccm_single_ecc_error[2:0]) & ifc_iccm_access_f2 & ifc_fetch_req_f2 );
     end

**逐段解释** ：

* 第 L873-L881 行：每个 ECC word 输出 corrected data、corrected ECC、single error 和 double
  error。
* 第 L883-L889 行：single-bit ECC error 只在 ICCM access fetch 有效时产生；多线程配置下按
  ``fetch_tid_f2`` 分配到 per-thread 向量，当前单线程配置走 ``one_thr`` 分支。
* 第 L891-L904 行：double error 生成 fetch byte mask；single error 选择 correction index 并打拍。

**接口关系** ：

* **被调用** ：ICCM access、DMA access 和 ECC correction 周期执行。
* **调用** ：``rvecc_encode``、``rvecc_decode``、ICCM memory wrapper。
* **共享状态** ：``iccm_correct_ecc``、``iccm_single_ecc_error``、``iccm_double_ecc_error``、
  ``iccm_ecc_corr_index_ff``。

§11  ``FENCE.I``、tag valid 与全 cache invalidation
--------------------------------------------------------------------------------

**职责** ：在 ``FENCE.I`` commit、miss reset 或 parity/ECC error invalidate 时清除 tag valid，
避免旧 tag 继续参与 hit 判断。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L925-L938``）：

.. code-block:: systemverilog

      assign reset_all_tags_in =  |dec_tlu_fence_i_wb[pt.NUM_THREADS-1:0] ;
      rvdff #(1) reset_all_tag_ff  (.*, .clk(active_clk),  .din(reset_all_tags_in), .dout(reset_all_tags));
      rvdff #(1) reset_all_tag_ff2 (.*, .clk(active_clk),  .din(reset_all_tags),    .dout(reset_all_tags_ff));

   ///////////////////////////////////////////////////////////////
   // Icache status and LRU
   ///////////////////////////////////////////////////////////////
   if (pt.ICACHE_ENABLE == 1 ) begin: icache_enabled
      logic [(pt.ICACHE_TAG_DEPTH/8)-1 : 0] way_status_clken;
      logic [(pt.ICACHE_TAG_DEPTH/8)-1 : 0] way_status_clk;
      logic [pt.ICACHE_NUM_WAYS-1:0] [pt.ICACHE_TAG_DEPTH-1:0]      ic_tag_valid_out ;
      logic [(pt.ICACHE_TAG_DEPTH/32)-1:0] [pt.ICACHE_NUM_WAYS-1:0] tag_valid_clken ;
      logic [(pt.ICACHE_TAG_DEPTH/32)-1:0] [pt.ICACHE_NUM_WAYS-1:0] tag_valid_clk   ;
      assign  ic_valid  = ~ifu_wr_cumulative_err_data & ~(reset_ic_in | reset_ic_ff | reset_all_tags | reset_all_tags_ff) ;

**逐段解释** ：

* 第 L925-L927 行：任一 thread 的 ``dec_tlu_fence_i_wb`` 置位都会进入 ``reset_all_tags``，
  并保留两级打拍版本。
* 第 L932-L938 行：ICache 使能时维护 per-way/per-index ``ic_tag_valid_out`` 和
  ``way_status``；新 valid 写入必须同时排除 cumulative bus error、miss reset 和
  ``reset_all_tags``。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1028-L1055``）：

.. code-block:: systemverilog

      for (genvar i=0 ; i<pt.ICACHE_TAG_DEPTH/32 ; i++) begin : CLK_GRP_TAG_VALID
         for (genvar j=0; j<pt.ICACHE_NUM_WAYS; j++) begin : way_clken
         if (pt.ICACHE_TAG_DEPTH == 32 ) begin
           assign tag_valid_clken[i][j] =  ifu_tag_wren_ff[j] | perr_err_inv_way[j] | ifu_tag_miss_wren[j] | reset_all_tags;
         end else begin
            assign tag_valid_clken[i][j] = (((ifu_ic_rw_int_addr_ff [pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO+5] == i ) &  ifu_tag_wren_ff[j] )  |
                                           ((perr_ic_index_ff       [pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO+5] == i ) &  perr_err_inv_way[j])     |
                                           ((ifu_tag_miss_addr_f2_p2[pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO+5] == i ) &  ifu_tag_miss_wren[j])    | reset_all_tags); // miss on this index or reset
         end

        `ifdef RV_FPGA_OPTIMIZE
           assign tag_valid_clk[i][j] = 1'b0;
        `else
         rvclkhdr way_status_cgc ( .en(tag_valid_clken[i][j]),   .l1clk(tag_valid_clk[i][j]), .* );
        `endif

**逐段解释** ：

* 第 L1028-L1035 行：tag valid clock enable 在 fill、parity/ECC invalidate、miss invalidate
  或 ``reset_all_tags`` 时打开。
* 第 L1038-L1042 行：非 FPGA optimize 分支用 ``rvclkhdr`` 生成 tag valid 局部时钟。
* 第 L1045-L1055 行：具体 valid bit 只在对应 index 和 way fill 时写入；perr、miss 或
  ``reset_all_tags`` 会清除该 bit。

**接口关系** ：

* **被调用** ：``FENCE.I``、miss fill、miss reset 和 parity/ECC invalidate 事件触发。
* **调用** ：``rvdff``、``rvdffsc_fpga``、``rvclkhdr``。
* **共享状态** ：``reset_all_tags``、``ic_tag_valid_out``、``ic_tag_valid_unq``。

§12  way status 与替换策略
--------------------------------------------------------------------------------

**职责** ：根据当前 way valid 和 hit/fill 情况更新 replacement status；当前 4 way 配置使用
3-bit decision-tree 状态，源码注释将其描述为 4-way set associative replacement。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1071-L1090``）：

.. code-block:: systemverilog

   //   four-way set associative - three bits
   //   each bit represents one branch point in a binary decision tree; let 1
   //   represent that the left side has been referenced more recently than the
   //   right side, and 0 vice-versa
   //
   //              are all 4 ways valid?
   //                   /       \
   //                  |        no, use an invalid way.
   //                  |
   //                  |
   //             bit_0 == 0?             state | replace      ref to | next state
   //               /       \             ------+--------      -------+-----------
   //              y         n             x00  |  way_0      way_0 |    _11
   //             /           \            x10  |  way_1      way_1 |    _01
   //      bit_1 == 0?    bit_2 == 0?      0x1  |  way_2      way_2 |    1_0
   //        /    \          /    \        1x1  |  way_3      way_3 |    0_0
   //       y      n        y      n
   //      /        \      /        \        ('x' means don't care       ('_' means unchanged)
   //    way_0    way_1  way_2     way_3      don't care)

**逐段解释** ：

* 第 L1071-L1074 行：源码明确 4 way replacement status 是 3 个 bit，每个 bit 是 binary
  decision tree 的分支点。
* 第 L1076-L1089 行：若 4 个 way 未全 valid，优先使用 invalid way；全部 valid 时按
  status bit 选择 replacement way，并在 reference 后更新状态。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1091-L1119``）：

.. code-block:: systemverilog

      if (pt.ICACHE_NUM_WAYS == 4) begin: four_way_plru
      assign replace_way_mb_wr_any[3] = ( way_status_mb_wr_ff[2]  & way_status_mb_wr_ff[0] & (&tagv_mb_wr_ff[3:0])) |
                                     (~tagv_mb_wr_ff[3]& tagv_mb_wr_ff[2] &  tagv_mb_wr_ff[1] &  tagv_mb_wr_ff[0]) ;
      assign replace_way_mb_wr_any[2] = (~way_status_mb_wr_ff[2]  & way_status_mb_wr_ff[0] & (&tagv_mb_wr_ff[3:0])) |
                                     (~tagv_mb_wr_ff[2]& tagv_mb_wr_ff[1] &  tagv_mb_wr_ff[0]) ;
      assign replace_way_mb_wr_any[1] = ( way_status_mb_wr_ff[1] & ~way_status_mb_wr_ff[0] & (&tagv_mb_wr_ff[3:0])) |
                                     (~tagv_mb_wr_ff[1]& tagv_mb_wr_ff[0] ) ;
      assign replace_way_mb_wr_any[0] = (~way_status_mb_wr_ff[1] & ~way_status_mb_wr_ff[0] & (&tagv_mb_wr_ff[3:0])) |
                                     (~tagv_mb_wr_ff[0] ) ;

      assign replace_way_mb_ms_any[3] = ( way_status_mb_ms_ff[2]  & way_status_mb_ms_ff[0] & (&tagv_mb_ms_ff[3:0])) |
                                     (~tagv_mb_ms_ff[3]& tagv_mb_ms_ff[2] &  tagv_mb_ms_ff[1] &  tagv_mb_ms_ff[0]) ;
      assign replace_way_mb_ms_any[2] = (~way_status_mb_ms_ff[2]  & way_status_mb_ms_ff[0] & (&tagv_mb_ms_ff[3:0])) |
                                     (~tagv_mb_ms_ff[2]& tagv_mb_ms_ff[1] &  tagv_mb_ms_ff[0]) ;

**逐段解释** ：

* 第 L1091-L1099 行：当前 ``ICACHE_NUM_WAYS=4``，因此使用 ``four_way_plru`` 分支。
  ``replace_way_mb_wr_any`` 在所有 way valid 时按 status bit 选择，否则选择 invalid way。
* 第 L1101-L1108 行：``replace_way_mb_ms_any`` 对 miss-state 保存的 tag valid/status 做同类选择。
* 第 L1110-L1118 行：hit 或 replacement 后的新 ``way_status`` 由命中的 way 或 replacement way
  反向编码生成。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1120-L1149``）：

.. code-block:: systemverilog

      else begin : two_ways_plru
         assign replace_way_mb_wr_any[0]                      = (~way_status_mb_wr_ff  & tagv_mb_wr_ff[0] & tagv_mb_wr_ff[1]) | ~tagv_mb_wr_ff[0];
         assign replace_way_mb_wr_any[1]                      = ( way_status_mb_wr_ff  & tagv_mb_wr_ff[0] & tagv_mb_wr_ff[1]) | ~tagv_mb_wr_ff[1] & tagv_mb_wr_ff[0];

         assign replace_way_mb_ms_any[0]                      = (~way_status_mb_ms_ff  & tagv_mb_ms_ff[0] & tagv_mb_ms_ff[1]) | ~tagv_mb_ms_ff[0];
         assign replace_way_mb_ms_any[1]                      = ( way_status_mb_ms_ff  & tagv_mb_ms_ff[0] & tagv_mb_ms_ff[1]) | ~tagv_mb_ms_ff[1] & tagv_mb_ms_ff[0];

         assign way_status_hit_new[pt.ICACHE_STATUS_BITS-1:0] = ic_rd_hit[0];
         assign way_status_rep_new[pt.ICACHE_STATUS_BITS-1:0] = replace_way_mb_wr_any[0];

      end

     // Make sure to select the way_status_hit_new even when in hit_under_miss.
     assign way_status_wr[pt.ICACHE_STATUS_BITS-1:0]     = (bus_ifu_wr_en_ff_q  & last_beat)  ? way_status_rep_new[pt.ICACHE_STATUS_BITS-1:0] :
                                                             way_status_hit_new[pt.ICACHE_STATUS_BITS-1:0] ;

     assign way_status_up[pt.ICACHE_STATUS_BITS-1:0]     = way_status_hit_new[pt.ICACHE_STATUS_BITS-1:0] ;


     assign way_status_wr_en  = (bus_ifu_wr_en_ff_q  & last_beat)  ;
     assign way_status_up_en  =  ic_act_hit_f2;

**逐段解释** ：

* 第 L1120-L1129 行：源码也保留 2 way replacement 分支；当前参数不走此分支。
* 第 L1132-L1140 行：fill 最后一个 beat 写入 replacement status；普通 hit 更新 hit status。
* 第 L1142-L1149 行：``bus_wren`` 和 ``ifu_tag_wren`` 依据 replacement way 和 bus 最后一个
  data beat 产生。

**接口关系** ：

* **被调用** ：ICache hit、miss fill、tag valid reset 时执行。
* **调用** ：tag valid/status flop 阵列。
* **共享状态** ：``way_status``、``tagv_mb_wr_ff``、``replace_way_mb_wr_any``、``bus_ic_wr_en``。

§13  miss state machine 与关键 word bypass
--------------------------------------------------------------------------------

**职责** ：在 ICache miss、uncacheable miss、hit-under-miss、second miss 和 duplicate miss
之间切换，并在 bus data 返回后允许 critical word 或 stream bypass。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1857-L1874``）：

.. code-block:: systemverilog

      assign miss_done      = ( bus_ifu_wr_en_ff  & last_beat) |   (miss_state ==  DUPL_MISS_WAIT);   // Duplicate miss state should also say miss_done as we dont to lock up both threads on this state
      assign address_match  = (miss_address_other[pt.ICACHE_INDEX_HI : pt.ICACHE_TAG_INDEX_LO] == imb_ff[pt.ICACHE_INDEX_HI : pt.ICACHE_TAG_INDEX_LO] ) & ((miss_state != IDLE) | ic_act_miss_f2_raw)  &  ~uncacheable_miss_ff ;

      //////////////////////////////////// Create Miss State Machine ///////////////////////
      //                                   Create Miss State Machine                      //
      //                                   Create Miss State Machine                      //
      //                                   Create Miss State Machine                      //
      //////////////////////////////////// Create Miss State Machine ///////////////////////
      // FIFO state machine
      always_comb begin : MISS_SM
         miss_nxtstate   = IDLE;
         miss_state_en   = 1'b0;
         case (miss_state)
            IDLE: begin : idle
                     miss_nxtstate = ( exu_flush_final                                  ) ? HIT_U_MISS :
                                     ( address_match_other & ~uncacheable_miss_ff) ? DUPL_MISS_WAIT : (scnd_miss_req_other) ? PRE_CRIT_BYP : CRIT_BYP_OK ;
                     miss_state_en = ic_act_miss_f2_raw  & ~dec_tlu_force_halt;

**逐段解释** ：

* 第 L1857 行：miss 完成条件包括 bus 最后一个 beat 写入，也包括 duplicate miss wait 状态。
* 第 L1858 行：``address_match`` 比较 miss buffer 与 other miss 的 index/tag-index 范围，并排除
  uncacheable miss。
* 第 L1866-L1874 行：``IDLE`` 遇到 active miss 后，根据 flush、duplicate miss 或 second miss
  选择下一状态。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1875-L1893``）：

.. code-block:: systemverilog

            end
            PRE_CRIT_BYP : begin : pre_crit_byp
                     miss_nxtstate =  dec_tlu_force_halt ? IDLE : exu_flush_final ? HIT_U_MISS : CRIT_BYP_OK ;
                     miss_state_en =  1'b1;
            end
            DUPL_MISS_WAIT: begin : dupl_miss_wait
                     miss_nxtstate =  IDLE ;
                     miss_state_en =  exu_flush_final | miss_done_other | miss_done_other_ff | dec_tlu_force_halt;
            end
            CRIT_BYP_OK: begin : crit_byp_ok
                     miss_nxtstate = (dec_tlu_force_halt ) ?                                                                               IDLE :
                                     ( ic_byp_hit_f2 &  (last_data_recieved_ff | (bus_ifu_wr_en_ff & last_beat)) &  uncacheable_miss_ff) ? IDLE :
                                     ( ic_byp_hit_f2 &  ~last_data_recieved_ff                                   &  uncacheable_miss_ff) ? MISS_WAIT :
                                     (~ic_byp_hit_f2 &  ~exu_flush_final &  (bus_ifu_wr_en_ff & last_beat)       &  uncacheable_miss_ff) ? CRIT_WRD_RDY :
                                     (                                      (bus_ifu_wr_en_ff & last_beat)       & ~uncacheable_miss_ff) ? IDLE :
                                     ( ic_byp_hit_f2  &  ~exu_flush_final & ~(bus_ifu_wr_en_ff & last_beat)      & ~ifu_bp_hit_taken_q_f2   & ~uncacheable_miss_ff) ? STREAM :
                                     ( bus_ifu_wr_en_ff &  ~exu_flush_final & ~(bus_ifu_wr_en_ff & last_beat)    & ~ifu_bp_hit_taken_q_f2   & ~uncacheable_miss_ff) ? STREAM :

**逐段解释** ：

* 第 L1875-L1878 行：``PRE_CRIT_BYP`` 是进入 critical bypass 前的过渡状态，halt 回到
  ``IDLE``，flush 转入 ``HIT_U_MISS``。
* 第 L1879-L1882 行：duplicate miss 等 other miss 完成或 flush/halt 后释放。
* 第 L1883-L1893 行：``CRIT_BYP_OK`` 根据 bypass hit、last beat、uncacheable、branch kill
  和 flush 决定进入 ``IDLE``、``MISS_WAIT``、``CRIT_WRD_RDY``、``STREAM`` 或
  ``HIT_U_MISS``。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1907-L1922``）：

.. code-block:: systemverilog

            HIT_U_MISS: begin : hit_u_miss
                     miss_nxtstate =  ic_miss_under_miss_f2 & ~(bus_ifu_wr_en_ff & last_beat) & ~dec_tlu_force_halt & ~address_match_other ? SCND_MISS :
                                      ic_miss_under_miss_f2 & ~(bus_ifu_wr_en_ff & last_beat) & ~dec_tlu_force_halt &  address_match_other ? STALL_SCND_MISS :
                                      ic_ignore_2nd_miss_f2 & ~(bus_ifu_wr_en_ff & last_beat) & ~dec_tlu_force_halt ? STALL_SCND_MISS : IDLE  ;
                     miss_state_en = (bus_ifu_wr_en_ff & last_beat) | ic_miss_under_miss_f2 | ic_ignore_2nd_miss_f2 | dec_tlu_force_halt;
            end
            SCND_MISS: begin : scnd_miss  // If the bus has returned last beat and it is not my thread in f2, will need to wait and sync back for invalidations and stuff to work
               miss_nxtstate   =  dec_tlu_force_halt ? IDLE  :
                                  exu_flush_final ?  ((bus_ifu_wr_en_ff & last_beat) ? IDLE : HIT_U_MISS) : address_match_other ? DUPL_MISS_WAIT : CRIT_BYP_OK;
                     miss_state_en   = (bus_ifu_wr_en_ff & last_beat) | exu_flush_final | dec_tlu_force_halt;
            end
            STALL_SCND_MISS: begin : stall_scnd_miss
                     miss_nxtstate   = dec_tlu_force_halt ? IDLE :
                                       exu_flush_final ?  ((bus_ifu_wr_en_ff & last_beat) ? IDLE : HIT_U_MISS) : IDLE;

**逐段解释** ：

* 第 L1907-L1912 行：``HIT_U_MISS`` 处理 hit-under-miss 下的新 miss。新 miss 与 other miss
  地址不同则进入 ``SCND_MISS``，地址相同或应忽略则 stall。
* 第 L1913-L1917 行：``SCND_MISS`` 在 flush、halt、last beat 和 duplicate address 上分流。
* 第 L1918-L1922 行：``STALL_SCND_MISS`` 等待 last beat 或 flush/halt 后回到安全状态。

**接口关系** ：

* **被调用** ：``ic_act_miss_f2_raw``、bus response、flush、branch kill 驱动。
* **调用** ：miss buffer、bus command、bypass data ready、write fill 控制。
* **共享状态** ：``miss_state``、``imb_ff``、``imb_scnd_ff``、``uncacheable_miss_ff``。

§14  hit/miss 判定、second miss 与 miss buffer 保持
--------------------------------------------------------------------------------

**职责** ：在 F2 级综合 tag hit、ICCM hit、bypass hit、reset tags、miss pending 和 second miss
条件，得到 ``ic_hit_f2``、``ic_act_miss_f2`` 等核心控制信号。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1955-L1974``）：

.. code-block:: systemverilog

      assign  fetch_req_icache_tid_f2  = fetch_req_icache_f2 & fetch_tid_f2 ;
      assign  fetch_req_iccm_tid_f2    = fetch_req_iccm_f2   & fetch_tid_f2 ;
      assign ifu_fetch_val_q_f2[1:0]   = ifu_fetch_val[1:0] & {2{fetch_tid_f2}} ;

      assign ic_req_addr_bits_hi_3[pt.ICACHE_BEAT_ADDR_HI:3] = req_addr_count[pt.ICACHE_BEAT_BITS-1:0] ;
      assign ic_wr_addr_bits_hi_3[pt.ICACHE_BEAT_ADDR_HI:3]  = ifu_bus_rid_ff[pt.ICACHE_BEAT_BITS-1:0] & {pt.ICACHE_BEAT_BITS{bus_ifu_wr_en_ff}};

      assign ic_iccm_hit_f2        = fetch_req_iccm_tid_f2  &  (~miss_pending | (miss_state==HIT_U_MISS) | (miss_state==STREAM)) ;
      assign ic_byp_hit_f2         = (crit_byp_hit_f2 | stream_hit_f2)  & fetch_req_icache_tid_f2 &  miss_pending  ;
      assign ic_act_hit_f2         = (|ic_rd_hit[pt.ICACHE_NUM_WAYS-1:0]) & fetch_req_icache_tid_f2 & ~reset_all_tags & (~miss_pending | (miss_state==HIT_U_MISS)) & ~sel_mb_addr_ff ;
      assign ic_act_miss_f2_raw    = (((~(|ic_rd_hit[pt.ICACHE_NUM_WAYS-1:0]) | reset_all_tags) & fetch_req_icache_tid_f2 & ~miss_pending & ~ifc_region_acc_fault_f2) | scnd_miss_req)  ;
      assign ic_act_miss_f2        = ic_act_miss_f2_raw & (miss_nxtstate != DUPL_MISS_WAIT);
      assign ic_miss_under_miss_f2 = (~(|ic_rd_hit[pt.ICACHE_NUM_WAYS-1:0]) | reset_all_tags) & fetch_req_icache_tid_f2 & (miss_state == HIT_U_MISS) &
                                      (imb_ff[31:pt.ICACHE_TAG_INDEX_LO] != ifu_fetch_addr_int_f2[31:pt.ICACHE_TAG_INDEX_LO]) & ~uncacheable_miss_ff & ~sel_mb_addr_ff & ~ifc_region_acc_fault_f2 ;

**逐段解释** ：

* 第 L1955-L1960 行：请求先按 thread qualifier 过滤，并拆出 read/write address 的 beat
  地址片段。
* 第 L1962-L1964 行：``ic_iccm_hit_f2`` 把 ICCM access 视为 hit；``ic_byp_hit_f2`` 表示 critical
  或 stream bypass 命中；``ic_act_hit_f2`` 要求 per-way tag hit、非 reset_all_tags、miss 状态允许。
* 第 L1965-L1966 行：tag miss 或 reset_all_tags 会生成 raw miss；duplicate miss wait 会抑制
  ``ic_act_miss_f2``。
* 第 L1967-L1974 行：hit-under-miss 下的新 miss 会比较 miss buffer 地址与 F2 地址，并在
  uncacheable、region fault、miss buffer select 等条件下被抑制或 kill。

**接口关系** ：

* **被调用** ：F2 tag/data 返回后计算。
* **调用** ：miss FSM、PMU hit/miss、write stall、bus request。
* **共享状态** ：``ic_rd_hit``、``reset_all_tags``、``miss_state``、``imb_ff``。

§15  miss buffer 数据、critical word 与 stream hit
--------------------------------------------------------------------------------

**职责** ：把 AXI read response 写入 miss buffer，按 line 内 offset 判断关键 word 是否就绪，
并为 critical bypass/stream bypass 生成数据和错误 mask。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2046-L2072``）：

.. code-block:: systemverilog

      assign ic_miss_buff_data_in[63:0] = ifu_bus_rsp_rdata[63:0];

      for (genvar i=0; i<pt.ICACHE_NUM_BEATS; i++) begin :  wr_flop
        assign write_fill_data[i]        =   bus_ifu_wr_en & (  (pt.IFU_BUS_TAG-1)'(i)  == ifu_bus_rsp_tag[pt.IFU_BUS_TAG-2:0]);

        rvdffe #(32) byp_data_0_ff (.*,
                  .en (write_fill_data[i]),
                  .din (ic_miss_buff_data_in[31:0]),
                  .dout(ic_miss_buff_data[i*2][31:0]));

        rvdffe #(32) byp_data_1_ff (.*,
                  .en (write_fill_data[i]),
                  .din (ic_miss_buff_data_in[63:32]),
                  .dout(ic_miss_buff_data[i*2+1][31:0]));

         assign ic_miss_buff_data_valid_in[i]  = write_fill_data[i] ? 1'b1  : (ic_miss_buff_data_valid[i]  & ~ic_act_miss_f2) ;
         rvdff #(1) byp_data_valid_ff (.*,
                   .clk (active_clk),
                   .din (ic_miss_buff_data_valid_in[i]),
                   .dout(ic_miss_buff_data_valid[i]));

**逐段解释** ：

* 第 L2046-L2049 行：bus response data 进入 miss buffer；``write_fill_data[i]`` 用 response tag
  的 beat index 选择具体 entry。
* 第 L2051-L2059 行：64-bit response 被拆成两个 32-bit word 存入 ``ic_miss_buff_data``。
* 第 L2061-L2072 行：每个 beat 的 valid 和 error bit 独立打拍；新 active miss 会清除旧 valid/error。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2078-L2091``）：

.. code-block:: systemverilog

      assign bypass_index[pt.ICACHE_BEAT_ADDR_HI:1]         = imb_ff[pt.ICACHE_BEAT_ADDR_HI:1] ;
      assign bypass_index_5_3_inc[pt.ICACHE_BEAT_ADDR_HI:3] = bypass_index[pt.ICACHE_BEAT_ADDR_HI:3] + 1 ;

      assign bypass_data_ready_in = ((ic_miss_buff_data_valid_in[bypass_index[pt.ICACHE_BEAT_ADDR_HI:3]]                                                    & (bypass_index[2:1] == 2'b00)))   |
                                    ((ic_miss_buff_data_valid_in[bypass_index[pt.ICACHE_BEAT_ADDR_HI:3]] & ic_miss_buff_data_valid_in[bypass_index_5_3_inc[pt.ICACHE_BEAT_ADDR_HI:3]] & (bypass_index[2:1] != 2'b00))) |
                                    ((ic_miss_buff_data_valid_in[bypass_index[pt.ICACHE_BEAT_ADDR_HI:3]] & (bypass_index[pt.ICACHE_BEAT_ADDR_HI:3] == {pt.ICACHE_BEAT_ADDR_HI{1'b1}})))   ;



      assign    ic_crit_wd_rdy_new_in = ( bypass_data_ready_in & crit_wd_byp_ok_ff   &  uncacheable_miss_ff &  ~exu_flush_final ) |
                                        ( (miss_state==STREAM) & crit_wd_byp_ok_ff   & ~uncacheable_miss_ff &  ~exu_flush_final & ~ifu_bp_hit_taken_q_f2) |
                                        (ic_crit_wd_rdy_new_ff & ~fetch_req_icache_tid_f2 & crit_wd_byp_ok_ff    &  ~exu_flush_final) ;

**逐段解释** ：

* 第 L2078-L2083 行：critical word ready 根据 miss buffer valid 和 line 内 offset 判定；非
  0 offset 可能需要当前 beat 与下一 beat 都有效。
* 第 L2087-L2089 行：uncacheable miss、stream 状态或保留的 ready 状态都可使
  ``ic_crit_wd_rdy_new_in`` 置位，但 flush 和 branch kill 会抑制它。
* 第 L2091 行：ready 状态打拍到 ``ic_crit_wd_rdy_new_ff``。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2124-L2137``）：

.. code-block:: systemverilog

     assign miss_wrap_f2      =  (imb_ff[pt.ICACHE_TAG_INDEX_LO] != ifu_fetch_addr_int_f2[pt.ICACHE_TAG_INDEX_LO] ) ;

     assign miss_buff_hit_unq_f2  = ((ic_miss_buff_data_valid[byp_fetch_index[pt.ICACHE_BEAT_ADDR_HI:3]]                                                     & (byp_fetch_index[2:1] == 2'b00)) |
                                    ((ic_miss_buff_data_valid[byp_fetch_index[pt.ICACHE_BEAT_ADDR_HI:3]] & ic_miss_buff_data_valid[byp_fetch_index_inc[pt.ICACHE_BEAT_ADDR_HI:3]] & (byp_fetch_index[2:1]!= 2'b00))) |
                                    ((ic_miss_buff_data_valid[byp_fetch_index[pt.ICACHE_BEAT_ADDR_HI:3]] & (byp_fetch_index[pt.ICACHE_BEAT_ADDR_HI:3] == {pt.ICACHE_BEAT_BITS{1'b1}})))) & fetch_tid_f2   ;

     logic  previous_state_is_stream;
     rvdff  #((1))  prev_st_strm_ff  (.clk(active_clk), .din((miss_state==STREAM)),   .dout(previous_state_is_stream),   .*);
     assign stream_hit_f2     =  (miss_buff_hit_unq_f2 & ~miss_wrap_f2 ) & ((miss_state==STREAM) | ((miss_state==IDLE) & previous_state_is_stream)) ;
     assign stream_miss_f2    = ~(miss_buff_hit_unq_f2 & ~miss_wrap_f2 ) & ((miss_state==STREAM) | ((miss_state==IDLE) & previous_state_is_stream)) & ifc_fetch_req_f2 ;
     assign stream_eol_f2     =  (byp_fetch_index[pt.ICACHE_BEAT_ADDR_HI:2] == {pt.ICACHE_BEAT_BITS+1{1'b1}}) & ifc_fetch_req_f2 & stream_hit_f2;

     assign crit_byp_hit_f2   =  (miss_buff_hit_unq_f2 ) & ((miss_state == CRIT_WRD_RDY) | (miss_state==CRIT_BYP_OK)) ;

**逐段解释** ：

* 第 L2124 行：``miss_wrap_f2`` 判断当前 fetch 是否跨过 miss buffer 保存的 tag-index boundary。
* 第 L2126-L2128 行：``miss_buff_hit_unq_f2`` 判断 miss buffer 是否已经覆盖当前 fetch 需要的数据。
* 第 L2130-L2137 行：stream 状态可在连续 fetch 中复用 miss buffer；critical bypass 只在
  ``CRIT_WRD_RDY`` 或 ``CRIT_BYP_OK`` 状态使用。

**接口关系** ：

* **被调用** ：bus response、critical bypass、stream fetch 周期执行。
* **调用** ：``rvdffe``、``rvdff`` 保存 miss buffer 数据和 valid/error 状态。
* **共享状态** ：``ic_miss_buff_data``、``ic_miss_buff_data_valid``、``ic_crit_wd_rdy_new_ff``。

§16  bus beat 计数与 ICache fill 写使能
--------------------------------------------------------------------------------

**职责** ：在 miss pending 时统计 bus command/data beat，判断最后一个 beat，并只在 16 bytes
数据凑齐时写 ICache data array。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2257-L2267``）：

.. code-block:: systemverilog

      // Create write signals so we can write to the miss-buffer directly from the bus.
      assign bus_cmd_sent               = ifu_bus_arvalid     & ifu_bus_arready   & miss_pending & ifu_selected_miss_thr & ~dec_tlu_force_halt;
      assign bus_inc_data_beat_cnt      = bus_ifu_wr_en_ff       & ~bus_last_data_beat & ~dec_tlu_force_halt;
      assign bus_reset_data_beat_cnt    = ic_act_miss_f2         | (bus_ifu_wr_en_ff &  bus_last_data_beat) | dec_tlu_force_halt;
      assign bus_hold_data_beat_cnt     = ~bus_inc_data_beat_cnt & ~bus_reset_data_beat_cnt ;

      assign bus_new_data_beat_count[pt.ICACHE_BEAT_BITS-1:0] = ({pt.ICACHE_BEAT_BITS{bus_reset_data_beat_cnt}} & (pt.ICACHE_BEAT_BITS)'(0)) |
                                                                ({pt.ICACHE_BEAT_BITS{bus_inc_data_beat_cnt}}   & (bus_data_beat_count[pt.ICACHE_BEAT_BITS-1:0] + {{pt.ICACHE_BEAT_BITS-1{1'b0}},1'b1})) |
                                                                ({pt.ICACHE_BEAT_BITS{bus_hold_data_beat_cnt}}  &  bus_data_beat_count[pt.ICACHE_BEAT_BITS-1:0]);

      rvdff #(pt.ICACHE_BEAT_BITS)  bus_mb_beat_count_ff (.*, .clk(active_clk), .din ({bus_new_data_beat_count[pt.ICACHE_BEAT_BITS-1:0]}), .dout({bus_data_beat_count[pt.ICACHE_BEAT_BITS-1:0]}));

**逐段解释** ：

* 第 L2258-L2261 行：command sent、data beat increment、reset 和 hold 条件都被
  ``dec_tlu_force_halt`` 保护。
* 第 L2263-L2267 行：data beat count 在新 miss 或最后一个 beat 后清零，在非最后 data beat
  返回时递增，否则保持。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2317-L2328``）：

.. code-block:: systemverilog

       assign bus_last_data_beat     =  uncacheable_miss_ff ? (bus_data_beat_count[pt.ICACHE_BEAT_BITS-1:0] == {{pt.ICACHE_BEAT_BITS-1{1'b0}},1'b1}) : (&bus_data_beat_count[pt.ICACHE_BEAT_BITS-1:0]);

      assign  bus_ifu_wr_en            =  ifu_bus_rvalid     & miss_pending & (ifu_bus_rsp_tag[pt.IFU_BUS_TAG-1] == tid);
      assign  bus_ifu_wr_en_ff         =  ifu_bus_rvalid_ff  & miss_pending & rsp_miss_thr_ff;
      assign  bus_ifu_wr_en_ff_q       =  ifu_bus_rvalid_ff  & miss_pending & rsp_miss_thr_ff & ~uncacheable_miss_ff & ~(|ifu_bus_rresp_ff[1:0]) & write_ic_16_bytes; // qualify with no-error conditions ;
      assign  bus_ifu_wr_en_ff_wo_err  =  ifu_bus_rvalid_ff  & miss_pending & rsp_miss_thr_ff & ~uncacheable_miss_ff;


      rvdff #(1)  act_miss_ff (.*, .clk(active_clk), .din (ic_act_miss_f2), .dout(ic_act_miss_f2_delayed));
      assign    reset_tag_valid_for_miss = ((ic_act_miss_f2_delayed & (miss_state == CRIT_BYP_OK)) | ifu_miss_state_pre_crit_ff) & ~uncacheable_miss_ff  ;
      assign    bus_ifu_wr_data_error    = |ifu_bus_rsp_opc[1:0]  &  ifu_bus_rvalid     & miss_pending & (ifu_bus_rsp_tag[pt.IFU_BUS_TAG-1] == tid);
      assign    bus_ifu_wr_data_error_ff = |ifu_bus_rresp_ff[1:0] &  ifu_bus_rvalid_ff  & miss_pending & rsp_miss_thr_ff;

**逐段解释** ：

* 第 L2317 行：uncacheable miss 的 last beat 判断不同于 cacheable miss；cacheable path 用
  data beat count 全 1 表示最后 beat。
* 第 L2319-L2323 行：``bus_ifu_wr_en_ff_q`` 要求 response valid、miss pending、thread 匹配、
  非 uncacheable、无 response error 且 ``write_ic_16_bytes`` 为 1。
* 第 L2325-L2328 行：新 miss 会延迟一拍参与 tag valid reset；bus response opcode/response
  error 进入 cumulative error 路径。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L2367-L2370``）：

.. code-block:: systemverilog

       assign ic_wr_en[pt.ICACHE_NUM_WAYS-1:0] = bus_ic_wr_en[pt.ICACHE_NUM_WAYS-1:0] & {pt.ICACHE_NUM_WAYS{write_ic_16_bytes}};
      assign ic_write_stall_self              =  write_ic_16_bytes &  ~(((miss_state== CRIT_BYP_OK) & ~(bus_ifu_wr_en_ff & last_beat & ~uncacheable_miss_ff))) &
                                                                      ~(((miss_state==STREAM)       & ~(bus_ifu_wr_en_ff & last_beat & ~uncacheable_miss_ff) & ~(exu_flush_final | ifu_bp_hit_taken_q_f2 | stream_eol_f2)));
      assign ic_write_stall_other             =  write_ic_16_bytes & ~uncacheable_miss_ff;   // if this thread is writing - it must block the other thread from accessing the cache.

**逐段解释** ：

* 第 L2367 行：``ic_wr_en`` 只有在 replacement way 选择出的 ``bus_ic_wr_en`` 与
  ``write_ic_16_bytes`` 同时有效时才写 ICache。
* 第 L2368-L2370 行：写 ICache 时会对当前 thread 或 other thread 产生 stall，避免读写冲突。

**接口关系** ：

* **被调用** ：AXI read response 和 miss fill 周期执行。
* **调用** ：驱动 ``EH2_IC_DATA`` 和 ``EH2_IC_TAG`` 写使能。
* **共享状态** ：``bus_data_beat_count``、``bus_ifu_wr_en_ff_q``、``write_ic_16_bytes``、
  ``ic_wr_en``。

§17  ``eh2_ifu_ic_mem`` — tag/data wrapper
--------------------------------------------------------------------------------

**职责** ：把 ICache 对外端口拆到 ``EH2_IC_TAG`` 与 ``EH2_IC_DATA`` 两个子模块，并保持同一套
地址、debug、hit、ECC/parity 信号。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L20-L59``）：

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
         input logic                                   ic_rd_en  ,         // Read enable

**逐段解释** ：

* 第 L20-L24 行：wrapper 使用相同参数集展开 ICache tag/data。
* 第 L27-L35 行：clock、reset、ECC disable、地址、写使能和读使能是 tag/data 共同输入。
* 第 L36-L59 行：debug、premux、write data、read data、ECC/parity error、tag valid、
  external SRAM packet、hit 和 tag parity error 在 wrapper 边界统一声明。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L63-L77``）：

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
              .ic_rw_addr   (ic_rw_addr[31:1])
              ) ;

**逐段解释** ：

* 第 L63-L69 行：tag 子模块只接收 ``ic_rw_addr[31:3]``，不需要 data halfword/byte offset。
* 第 L71-L77 行：data 子模块接收 ``ic_rw_addr[31:1]``，因为 data mux 和 bank wrap 需要更低位。
* 两个实例都显式传入 ``ic_wr_en`` 和 ``ic_debug_addr``，其余端口通过 ``.*`` 对接。

**接口关系** ：

* **被调用** ：``eh2_mem`` 在 ``pt.ICACHE_ENABLE == 1`` 时实例化。
* **调用** ：``EH2_IC_TAG``、``EH2_IC_DATA``。
* **共享状态** ：``ic_rd_hit`` 从 tag 返回后又作为 data mux 选择条件进入 data 子模块。

§18  ``EH2_IC_DATA`` — bank 读使能与地址 wrap
--------------------------------------------------------------------------------

**职责** ：根据读地址低位和 bank 位决定每个 bank/way 的读写使能，处理跨 bank 的 64-bit
取数，并支持 debug read/write。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L193-L207``）：

.. code-block:: systemverilog

      assign  ic_debug_rd_way_en[pt.ICACHE_NUM_WAYS-1:0] =  {pt.ICACHE_NUM_WAYS{ic_debug_rd_en & ~ic_debug_tag_array}} & ic_debug_way[pt.ICACHE_NUM_WAYS-1:0] ;
      assign  ic_debug_wr_way_en[pt.ICACHE_NUM_WAYS-1:0] =  {pt.ICACHE_NUM_WAYS{ic_debug_wr_en & ~ic_debug_tag_array}} & ic_debug_way[pt.ICACHE_NUM_WAYS-1:0] ;

      always_comb begin : clkens
         ic_bank_way_clken   = '0;

         for ( int i=0; i<pt.ICACHE_BANKS_WAY; i++) begin: wr_ens
          ic_b_sb_wren[i]        =  ic_wr_en[pt.ICACHE_NUM_WAYS-1:0]  |
                                          (ic_debug_wr_way_en[pt.ICACHE_NUM_WAYS-1:0] & {pt.ICACHE_NUM_WAYS{ic_debug_addr[pt.ICACHE_BANK_HI : pt.ICACHE_BANK_LO] == i}}) ;
          ic_debug_sel_sb[i]     = (ic_debug_addr[pt.ICACHE_BANK_HI : pt.ICACHE_BANK_LO] == i );
          ic_sb_wr_data[i]       = (ic_debug_sel_sb[i] & ic_debug_wr_en) ? ic_debug_wr_data : ic_bank_wr_data[i] ;
          ic_b_rden[i]           =  ic_rd_en_with_debug & ( ( ~ic_rw_addr_q[pt.ICACHE_BANK_HI] & (i==0)) |
                                                            (( ic_rw_addr_q[pt.ICACHE_BANK_HI] & ic_rw_addr_q[2:1] != 2'b00) & (i==0)) |

**逐段解释** ：

* 第 L193-L194 行：debug data array 操作只在 ``~ic_debug_tag_array`` 时选择 way。
* 第 L196-L203 行：每个 bank 的 write enable 合并正常 fill 写和 debug 写；debug 写时用
  ``ic_debug_wr_data`` 替换正常 fill data。
* 第 L204-L207 行：bank read enable 根据 bank high 位和 ``ic_rw_addr_q[2:1]`` 判断是否需要读
  当前 bank 或相邻 bank。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L220-L229``）：

.. code-block:: systemverilog

   // bank read enables
     assign ic_rd_en_with_debug                          = ((ic_rd_en   | ic_debug_rd_en ) & ~(|ic_wr_en));
     assign ic_rw_addr_q[pt.ICACHE_INDEX_HI:1] = (ic_debug_rd_en | ic_debug_wr_en) ?
                                                 {ic_debug_addr[pt.ICACHE_INDEX_HI:3],2'b0} :
                                                 ic_rw_addr[pt.ICACHE_INDEX_HI:1] ;

      assign ic_rw_addr_q_inc[pt.ICACHE_TAG_LO-1:pt.ICACHE_DATA_INDEX_LO] = ic_rw_addr_q[pt.ICACHE_TAG_LO-1 : pt.ICACHE_DATA_INDEX_LO] + 1 ;
      assign ic_rw_addr_wrap                                        = ic_rw_addr_q[pt.ICACHE_BANK_HI] & ic_rd_en_with_debug & ~(|ic_wr_en[pt.ICACHE_NUM_WAYS-1:0]);
      assign ic_cacheline_wrap_ff                                   = ic_rw_addr_ff[pt.ICACHE_TAG_INDEX_LO-1:pt.ICACHE_BANK_LO] == {(pt.ICACHE_TAG_INDEX_LO - pt.ICACHE_BANK_LO){1'b1}};

**逐段解释** ：

* 第 L221 行：正常读和 debug 读共用读路径，但写 ICache 时禁止同时读。
* 第 L222-L224 行：debug 操作使用 debug 地址并强制低两位为 0，正常路径使用 ``ic_rw_addr``。
* 第 L226-L229 行：跨 bank 读时计算递增地址；``ic_cacheline_wrap_ff`` 记录是否跨 cache line 边界。

**接口关系** ：

* **被调用** ：``EH2_IC_DATA`` 每次 read/write/debug 周期执行。
* **调用** ：后续 SRAM macro、read mux 和 ECC/parity checker。
* **共享状态** ：``ic_b_sb_wren``、``ic_b_rden``、``ic_rw_addr_q``、``ic_cacheline_wrap_ff``。

§19  ``EH2_IC_DATA`` — way-packed SRAM 与 data bypass
--------------------------------------------------------------------------------

**职责** ：当前 ``ICACHE_WAYPACK=1`` 时，为每个 bank 生成 way-packed data SRAM，并在读写同地址时
用 bypass entry 避免 stale read。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L421-L429``）：

.. code-block:: bash

   `define EH2_PACKED_IC_DATA_SRAM(depth,width,waywidth)                                                                                                 \
               ram_be_``depth``x``width  ic_bank_sb_way_data (                                                                                           \
                               .CLK   (clk),                                                                                                             \
                               .WE    (|ic_b_sb_wren[k]),                                                    // OR of all the ways in the bank           \
                               .WEM   (ic_b_sb_bit_en_vec[k]),                                               // 284 bits of bit enables                  \
                               .D     ({pt.ICACHE_NUM_WAYS{ic_sb_wr_data[k][``waywidth-1:0]}}),                                                          \
                               .ADR   (ic_rw_addr_bank_q[k][pt.ICACHE_INDEX_HI:pt.ICACHE_DATA_INDEX_LO]),                                                \
                               .Q     (wb_packeddout_pre[k]),                                                                                            \
                               .ME    (|ic_bank_way_clken_final[k]),                                                                                     \

**逐段解释** ：

* 第 L421-L429 行：way-packed data SRAM macro 使用 byte-enable SRAM ``ram_be_*``，同一个 bank
  内 OR 所有 way 的 write enable，并用 ``WEM`` 区分具体 way 的 bit enable。
* ``D`` 端口复制 ``ICACHE_NUM_WAYS`` 份写数据，真实写入哪些 way 由 ``ic_b_sb_bit_en_vec`` 控制。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L444-L456``）：

.. code-block:: systemverilog

                 if (pt.ICACHE_BYPASS_ENABLE == 1) begin                                                                                                                                                 \
                                                                                                                                                                                                         \
                    assign wrptr_in[k] = (wrptr[k] == (pt.ICACHE_NUM_BYPASS-1)) ? '0 : (wrptr[k] + 1'd1);                                                                                                \
                                                                                                                                                                                                         \
                    rvdffs  #(pt.ICACHE_NUM_BYPASS_WIDTH)  wrptr_ff(.*, .clk(active_clk), .en(|write_bypass_en[k]), .din (wrptr_in[k]), .dout(wrptr[k])) ;                                               \
                                                                                                                                                                                                         \
                    assign ic_b_sram_en[k]              = |ic_bank_way_clken[k];                                                                                                                         \
                                                                                                                                                                                                         \
                                                                                                                                                                                                         \
                    assign ic_b_read_en[k]              =  ic_b_sram_en[k] &   (|ic_b_sb_rden[k]);                                                                                                       \
                    assign ic_b_write_en[k]             =  ic_b_sram_en[k] &   (|ic_b_sb_wren[k]);                                                                                                       \
                    assign ic_bank_way_clken_final[k]   =  ic_b_sram_en[k] &    ~(|sel_bypass[k]);                                                                                                       \

**逐段解释** ：

* 第 L444-L448 行：data bypass enable 时，每个 bank 维护 round-robin write pointer。
* 第 L450-L456 行：读写 SRAM enable 由 bank/way clock enable 聚合；若命中 bypass entry，
  ``ic_bank_way_clken_final`` 会关闭真实 SRAM access，转而使用保存的数据。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L508-L523``）：

.. code-block:: systemverilog

    // generate IC DATA PACKED SRAMS for 2/4 ways
     for (genvar k=0; k<pt.ICACHE_BANKS_WAY; k++) begin: BANKS_WAY   // 16B subbank
        if (pt.ICACHE_ECC) begin : ECC1
           logic [pt.ICACHE_BANKS_WAY-1:0] [(71*pt.ICACHE_NUM_WAYS)-1:0]        wb_packeddout, ic_b_sb_bit_en_vec, wb_packeddout_pre;           // data and its bit enables

           logic [pt.ICACHE_BANKS_WAY-1:0] [pt.ICACHE_NUM_BYPASS-1:0] [(71*pt.ICACHE_NUM_WAYS)-1:0]  wb_packeddout_hold;

           for (genvar i=0; i<pt.ICACHE_NUM_WAYS; i++) begin: BITEN
              assign ic_b_sb_bit_en_vec[k][(71*i)+70:71*i] = {71{ic_b_sb_wren[k][i]}};
           end

           // SRAMS with ECC (single/double detect; no correct)
           if ($clog2(pt.ICACHE_DATA_DEPTH) == 13 )   begin : size_8192
              if (pt.ICACHE_NUM_WAYS == 4) begin : WAYS
                 `EH2_PACKED_IC_DATA_SRAM(8192,284,71)    // 64b data + 7b ecc

**逐段解释** ：

* 第 L508-L510 行：当前 way-packed 分支按 ``ICACHE_BANKS_WAY`` 展开 bank；注释说明支持 2/4 way。
* 第 L511-L517 行：ECC 模式下每个 way 使用 71 bit，4 way 时 packed width 为 284 bit。
* 第 L519-L523 行：SRAM macro 选择受 ``ICACHE_DATA_DEPTH`` 和 ``ICACHE_NUM_WAYS`` 控制；
  当前 ``ICACHE_NUM_WAYS=4`` 时使用 4 way width。

**接口关系** ：

* **被调用** ：``EH2_IC_DATA`` generate elaboration 和每次 data SRAM access。
* **调用** ：``ram_be_*`` SRAM macro、``rvdffs``、``rvdffe``。
* **共享状态** ：``wb_packeddout``、``wb_packeddout_hold``、``write_bypass_en``、``sel_bypass``。

§20  ``EH2_IC_DATA`` — read mux、ECC 与 parity
--------------------------------------------------------------------------------

**职责** ：从 per-way/per-bank SRAM 输出中按 hit way 和 offset 选出 64-bit fetch data，并在
ECC 模式或 parity 模式下生成错误输出。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L702-L731``）：

.. code-block:: systemverilog

      always_comb begin : rd_mux
        wb_dout_way_pre[pt.ICACHE_NUM_WAYS-1:0] = '0;

        for ( int i=0; i<pt.ICACHE_NUM_WAYS; i++) begin : num_ways
          for ( int j=0; j<pt.ICACHE_BANKS_WAY; j++) begin : banks
           wb_dout_way_pre[i][70:0]      |=  ({71{(ic_rw_addr_ff[pt.ICACHE_BANK_HI : pt.ICACHE_BANK_LO] == (pt.ICACHE_BANK_BITS)'(j))}}   &  wb_dout[i][j]);
           wb_dout_way_pre[i][141 : 71]  |=  ({71{(ic_rw_addr_ff[pt.ICACHE_BANK_HI : pt.ICACHE_BANK_LO] == (pt.ICACHE_BANK_BITS)'(j-1))}} &  wb_dout[i][j]);
          end
        end
      end

      for ( genvar i=0; i<pt.ICACHE_NUM_WAYS; i++) begin : num_ways_mux1
        assign wb_dout_way[i][63:0] = (ic_rw_addr_ff[2:1] == 2'b00) ? wb_dout_way_pre[i][63:0]   :
                                      (ic_rw_addr_ff[2:1] == 2'b01) ?{wb_dout_way_pre[i][86:71], wb_dout_way_pre[i][63:16]} :
                                      (ic_rw_addr_ff[2:1] == 2'b10) ?{wb_dout_way_pre[i][102:71],wb_dout_way_pre[i][63:32]} :
                                                                     {wb_dout_way_pre[i][119:71],wb_dout_way_pre[i][63:48]};

        assign wb_dout_way_with_premux[i][63:0]  =  ic_sel_premux_data ? ic_premux_data[63:0] : wb_dout_way[i][63:0] ;
     end

**逐段解释** ：

* 第 L702-L711 行：先按 bank 选择拼出每个 way 的 142-bit 窗口；当前 ECC 模式下每个 bank
  71 bit。
* 第 L713-L720 行：再按 ``ic_rw_addr_ff[2:1]`` 选择 64-bit 数据窗口；若 ``ic_sel_premux_data``
  为 1，则用 premux data 替代 SRAM 读出。
* 第 L722-L731 行：最终 ``ic_rd_data`` 按 ``ic_rd_hit_q`` 选择 hit way；debug read 和 ECC
  check 也从同一份 per-way 数据中派生。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L734-L760``）：

.. code-block:: systemverilog

    for (genvar i=0; i < pt.ICACHE_BANKS_WAY ; i++) begin : ic_ecc_error
       assign bank_check_en[i]    = |ic_rd_hit[pt.ICACHE_NUM_WAYS-1:0] & ((i==0) | (~ic_cacheline_wrap_ff & (ic_b_rden_ff[pt.ICACHE_BANKS_WAY-1:0] == {pt.ICACHE_BANKS_WAY{1'b1}})));  // always check the lower address bank, and drop the upper a
       assign wb_dout_ecc_bank[i] = wb_dout_ecc[(71*i)+70:(71*i)];

      rvdff #(1) encod_en_ff (.*,
                              .clk(active_clk),
                              .din (bank_check_en[i]),
                              .dout(bank_check_en_ff[i])
                              );

      rvdffe #(71) bank_data_ff (.*,
                                .en  (bank_check_en[i]),
                                .din (wb_dout_ecc_bank[i][70:0]),
                                .dout(wb_dout_ecc_bank_ff[i][70:0])
                                );

      rvecc_decode_64  ecc_decode_64 (
                                      .en               (bank_check_en_ff[i]),
                                      .din              ((bank_check_en_ff[i])?wb_dout_ecc_bank_ff[i][63:0]:64'd0),                  // [134:71],  [63:0]
                                      .ecc_in           ((bank_check_en_ff[i])?wb_dout_ecc_bank_ff[i][70:64]:7'd0),               // [141:135] [70:64]

**逐段解释** ：

* 第 L734-L736 行：ECC check 只在有 hit way 时启用；bank 1 在 cacheline wrap 时可能不检查。
* 第 L738-L748 行：check enable 和 bank data 各打一拍，保证 ECC decoder 看到稳定输入。
* 第 L750-L755 行：``rvecc_decode_64`` 检查 64-bit data 和 7-bit ECC，并输出 ``ic_eccerr[i]``。
* 第 L760 行：ECC 模式下 data parity error 输出固定为 0。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L801-L829``）：

.. code-block:: systemverilog

      logic [pt.ICACHE_BANKS_WAY-1:0][3:0] ic_parerr_bank;

     for (genvar i=0; i < pt.ICACHE_BANKS_WAY ; i++) begin : ic_par_error
         assign bank_check_en[i]    = |ic_rd_hit[pt.ICACHE_NUM_WAYS-1:0] & ((i==0) | (~ic_cacheline_wrap_ff & (ic_b_rden_ff[pt.ICACHE_BANKS_WAY-1:0] == {pt.ICACHE_BANKS_WAY{1'b1}})));  // always check the lower address bank, and drop the upper a

         rvdff #(1) encod_en_ff (.*,
                                 .clk(active_clk),
                                 .din (bank_check_en[i]),
                                 .dout(bank_check_en_ff[i])
                                 );

         rvdffe #(68) bank_data_ff (.*,
                                   .en  (bank_check_en[i]),
                                   .din (wb_dout_ecc_bank[i][67:0]),
                                   .dout(wb_dout_ecc_bank_ff[i][67:0])
                                   );

        for (genvar j=0; j<4; j++)  begin : parity
         rveven_paritycheck pchk (
                              .data_in   (wb_dout_ecc_bank_ff[i][16*(j+1)-1: 16*j]),
                              .parity_in (wb_dout_ecc_bank_ff[i][64+j]),
                              .parity_err(ic_parerr_bank[i][j])

**逐段解释** ：

* 第 L801-L816 行：当 ``ICACHE_ECC`` 为 0 时，data path 使用 68-bit data/parity 格式并把每
  个 bank 数据打一拍。
* 第 L818-L823 行：每个 bank 被拆成 4 个 16-bit parity check。
* 第 L827-L829 行：parity 模式下 ``ic_parerr`` 聚合 parity bank 错误，而 ``ic_eccerr`` 固定为 0。
  当前参数 ``ICACHE_ECC=1``，因此这是备用配置分支。

**接口关系** ：

* **被调用** ：data SRAM read 返回后执行。
* **调用** ：``rvecc_decode_64`` 或 ``rveven_paritycheck``。
* **共享状态** ：``ic_rd_hit_q``、``ic_sel_premux_data``、``ic_eccerr``、``ic_parerr``。

§21  ``EH2_IC_TAG`` — tag write、read 与 hit
--------------------------------------------------------------------------------

**职责** ：维护 tag SRAM、tag debug access、tag ECC/parity，并输出 per-way ``ic_rd_hit`` 和
``ic_tag_perr``。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L915-L941``）：

.. code-block:: systemverilog

      assign ecc_decode_enable = ~dec_tlu_core_ecc_disable & ic_rd_en_ff2;


      assign  ic_tag_wren [pt.ICACHE_NUM_WAYS-1:0]  = ic_wr_en[pt.ICACHE_NUM_WAYS-1:0] & {pt.ICACHE_NUM_WAYS{(ic_rw_addr[pt.ICACHE_BEAT_ADDR_HI:4] == {pt.ICACHE_BEAT_BITS-1{1'b1}})}} ;
      assign  ic_tag_clken[pt.ICACHE_NUM_WAYS-1:0]  = {pt.ICACHE_NUM_WAYS{ic_rd_en | clk_override}} | ic_wr_en[pt.ICACHE_NUM_WAYS-1:0] | ic_debug_wr_way_en[pt.ICACHE_NUM_WAYS-1:0] | ic_debug_rd_way_en[pt.ICACHE_NUM_WAYS-1:0];

      rvdff #(32-pt.ICACHE_TAG_LO) adr_ff (.*,
                                           .clk(active_clk),
                                           .din ({ic_rw_addr[31:pt.ICACHE_TAG_LO]}),
                                           .dout({ic_rw_addr_ff[31:pt.ICACHE_TAG_LO]})
                                           );

      rvdff #(pt.ICACHE_NUM_WAYS) tg_val_ff (.*,
                                             .clk(active_clk),
                                             .din ((ic_tag_valid[pt.ICACHE_NUM_WAYS-1:0] & {pt.ICACHE_NUM_WAYS{~ic_wr_en_ff}})),
                                             .dout(ic_tag_valid_ff[pt.ICACHE_NUM_WAYS-1:0])
                                             );

      localparam PAD_BITS = 21 - (32 - pt.ICACHE_TAG_LO);  // sizing for a max tag width.

      // tags
      assign  ic_debug_rd_way_en[pt.ICACHE_NUM_WAYS-1:0] =  {pt.ICACHE_NUM_WAYS{ic_debug_rd_en & ic_debug_tag_array}} & ic_debug_way[pt.ICACHE_NUM_WAYS-1:0] ;
      assign  ic_debug_wr_way_en[pt.ICACHE_NUM_WAYS-1:0] =  {pt.ICACHE_NUM_WAYS{ic_debug_wr_en & ic_debug_tag_array}} & ic_debug_way[pt.ICACHE_NUM_WAYS-1:0] ;

**逐段解释** ：

* 第 L915 行：tag ECC decode 只在 core ECC 未关闭且 read enable 延迟两拍后进行。
* 第 L918-L919 行：tag write enable 只在 ``ic_wr_en`` 有效且 fill 到最后 tag write 位置时产生；
  tag clock enable 合并 read、write、debug 和 clock override。
* 第 L921-L931 行：tag 地址和 tag valid 都打一拍；写 tag 时 ``ic_wr_en_ff`` 会屏蔽 valid 打拍。
* 第 L933-L941 行：``PAD_BITS`` 约束 tag 写数据 padding；debug tag access 只在
  ``ic_debug_tag_array`` 为 1 时选择 way。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L943-L961``）：

.. code-block:: systemverilog

   if (pt.ICACHE_TAG_LO == 11) begin: SMALLEST
    if (pt.ICACHE_ECC) begin : ECC1_W
              rvecc_encode  tag_ecc_encode (
                                     .din    ({{pt.ICACHE_TAG_LO{1'b0}}, ic_rw_addr[31:pt.ICACHE_TAG_LO]}),
                                     .ecc_out({ ic_tag_ecc[6:0]}));

      assign  ic_tag_wr_data[25:0] = (ic_debug_wr_en & ic_debug_tag_array) ?
                                     {ic_debug_wr_data[68:64], ic_debug_wr_data[31:11]} :
                                     {ic_tag_ecc[4:0], ic_rw_addr[31:pt.ICACHE_TAG_LO]} ;
    end

    else begin : ECC0_W
              rveven_paritygen #(32-pt.ICACHE_TAG_LO) pargen  (.data_in   (ic_rw_addr[31:pt.ICACHE_TAG_LO]),
                                                    .parity_out(ic_tag_parity));

      assign  ic_tag_wr_data[21:0] = (ic_debug_wr_en & ic_debug_tag_array) ?
                                     {ic_debug_wr_data[64], ic_debug_wr_data[31:11]} :
                                     {ic_tag_parity, ic_rw_addr[31:pt.ICACHE_TAG_LO]} ;

**逐段解释** ：

* 第 L943-L951 行：当 ``ICACHE_TAG_LO==11`` 且 ECC 开启时，tag 写数据由 tag address 和 ECC
  组成；debug write 可直接写入 debug packet 中的 ECC/tag 位。
* 第 L954-L960 行：ECC 关闭时使用 even parity 生成 tag parity。当前参数 ``ICACHE_ECC=1``，
  因此当前实例使用 ECC 写 tag 分支。

**关键代码** （``rtl/design/ifu/eh2_ifu_ic_mem.sv:L1569-L1581``）：

.. code-block:: systemverilog

      always_comb begin : tag_rd_out
         ictag_debug_rd_data[25:0] = '0;
         for ( int j=0; j<pt.ICACHE_NUM_WAYS; j++) begin: debug_rd_out
            ictag_debug_rd_data[25:0] |=  pt.ICACHE_ECC ? ({26{ic_debug_rd_way_en_ff[j]}} & ic_tag_data_raw[j] ) : {4'b0, ({22{ic_debug_rd_way_en_ff[j]}} & ic_tag_data_raw[j][21:0])};
         end
      end


      for ( genvar i=0; i<pt.ICACHE_NUM_WAYS; i++) begin : ic_rd_hit_loop
         assign ic_rd_hit[i] = (w_tout[i][31:pt.ICACHE_TAG_LO] == ic_rw_addr_ff[31:pt.ICACHE_TAG_LO]) & ic_tag_valid[i] & ~ic_wr_en_ff;
      end

      assign  ic_tag_perr  = | (ic_tag_way_perr[pt.ICACHE_NUM_WAYS-1:0] & ic_tag_valid_ff[pt.ICACHE_NUM_WAYS-1:0] ) ;

**逐段解释** ：

* 第 L1569-L1574 行：debug tag read 按 debug way 选择 raw tag data；ECC 模式返回 26 bit，
  parity 模式返回低 22 bit 并补 4 bit 0。
* 第 L1577-L1579 行：per-way hit 条件为 tag 地址相等、该 way valid 且当前不是写 tag。
* 第 L1581 行：tag parity/ECC error 只在对应 way valid 打拍后参与 ``ic_tag_perr`` 聚合。

**接口关系** ：

* **被调用** ：``eh2_ifu_ic_mem`` 实例化。
* **调用** ：tag SRAM macro、``rvecc_encode``、``rvecc_decode``、``rveven_paritygen``、
  ``rveven_paritycheck``。
* **共享状态** ：``ic_rd_hit``、``ic_tag_perr``、``ictag_debug_rd_data``。

§22  ICache data/tag 错误上报
--------------------------------------------------------------------------------

**职责** ：把 data ECC/parity error 和 tag parity/ECC error 汇总为 ``ifu_ic_error_start``，
供 TLU/integrity counter 路径消费。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L541-L557``）：

.. code-block:: systemverilog

   if (pt.ICACHE_ECC == 1) begin: icache_ecc_1
      logic [6:0]       ic_wr_ecc;
      logic [6:0]       ic_miss_buff_ecc;
      logic [141:0]     ic_wr_16bytes_data ;
      logic [70:0]      ifu_ic_debug_rd_data_in   ;

                   rvecc_encode_64  ic_ecc_encode_64_bus (
                              .din    (ifu_bus_rdata_ff[63:0]),
                              .ecc_out(ic_wr_ecc[6:0]));
                   rvecc_encode_64  ic_ecc_encode_64_buff (
                              .din    (ic_miss_buff_half[63:0]),
                              .ecc_out(ic_miss_buff_ecc[6:0]));

      assign ic_rd_data_only[63:0]= {ic_rd_data[63:0]} ;
      for (genvar i=0; i < pt.ICACHE_BANKS_WAY ; i++) begin : ic_wr_data_loop
         assign ic_wr_data[i][70:0]  =  ic_wr_16bytes_data[((71*i)+70): (71*i)];

**逐段解释** ：

* 第 L541-L545 行：当前 ECC 模式声明 bus data 和 miss buffer half 的 ECC。
* 第 L547-L552 行：bus 返回数据和 miss buffer half 都用 ``rvecc_encode_64`` 生成 7-bit ECC。
* 第 L554-L557 行：``ic_wr_data`` 按 bank 切片写入 data wrapper。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L572-L577``）：

.. code-block:: systemverilog

     if (pt.NUM_THREADS > 1) begin: more_than_1_th
       assign ifu_ic_error_start[pt.NUM_THREADS-1:0]           = {((((|ic_eccerr[pt.ICACHE_BANKS_WAY-1:0]) & ic_act_hit_f2_ff )  | ic_rd_parity_final_err) & ~exu_flush_final[1] & fetch_tid_f2_p1 &  ~perr_state_wff_thr[1] & ~(err_stop_state_thr_ff[1] == 2'b11)) ,
                                                                  ((((|ic_eccerr[pt.ICACHE_BANKS_WAY-1:0]) & ic_act_hit_f2_ff)  | ic_rd_parity_final_err) & ~exu_flush_final[0] & ~fetch_tid_f2_p1 &  ~perr_state_wff_thr[0] & ~(err_stop_state_thr_ff[0] == 2'b11))};
     end  else begin: one_thr
   assign ifu_ic_error_start[pt.NUM_THREADS-1:0]           = {((((|ic_eccerr[pt.ICACHE_BANKS_WAY-1:0]) & ic_act_hit_f2_ff)  | ic_rd_parity_final_err) ) & ~exu_flush_final[0] & ~perr_state_wff_thr[pt.NUM_THREADS-1:0] & ~(err_stop_state_thr_ff[pt.NUM_THREADS-1] == 2'b11)}   ;
     end

**逐段解释** ：

* 第 L572-L574 行：多线程配置按 ``fetch_tid_f2_p1`` 将 ICache error start 路由到对应 thread。
* 第 L576 行：当前单线程配置把 data ECC error 或 tag error 聚合到唯一 thread，并受 flush、
  pending error state 和 stop-fetch state 抑制。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L699-L705``）：

.. code-block:: systemverilog

   assign two_byte_instr_f2    =  (ic_data_f2[1:0] != 2'b11 )  ;
   /////////////////////////////////////////////////////////////////////////////////////
   // Parity checking logic for Icache logic.                                         //
   /////////////////////////////////////////////////////////////////////////////////////

   assign ic_rd_parity_final_err = ic_tag_perr & sel_ic_data_ff  & tag_err_qual  ; // & ic_rd_en_ff & ifc_fetch_req_f2  & ~(ifc_region_acc_fault_memory_f2 | ifc_region_acc_fault_only_f2) ;

**逐段解释** ：

* 第 L699 行：两字节指令判断来自最终 ``ic_data_f2`` 低两位。
* 第 L705 行：tag parity/ECC error 只有在选择 ICache data 且 ``tag_err_qual`` 成立时进入
  ``ic_rd_parity_final_err``，再由上一段汇总为 ``ifu_ic_error_start``。

**接口关系** ：

* **被调用** ：ICache read hit、fill write 和 error check 周期执行。
* **调用** ：``rvecc_encode_64``、错误 stop-fetch FSM、TLU error path。
* **共享状态** ：``ic_eccerr``、``ic_parerr``、``ic_tag_perr``、``ifu_ic_error_start``。

§23  PMU hit/miss 事件
--------------------------------------------------------------------------------

**职责** ：把 ICache hit、miss、bus error、bus busy 和 bus transaction 汇总为 per-thread PMU
信号。

**关键代码** （``rtl/design/ifu/eh2_ifu_mem_ctl.sv:L1167-L1192``）：

.. code-block:: systemverilog

      assign ic_tag_valid[pt.ICACHE_NUM_WAYS-1:0] = ic_tag_valid_unq[pt.ICACHE_NUM_WAYS-1:0]   & {pt.ICACHE_NUM_WAYS{(~fetch_uncacheable_ff & ifc_fetch_req_f2) }} ;
      assign ic_debug_tag_val_rd_out           = |(ic_tag_valid_unq[pt.ICACHE_NUM_WAYS-1:0] &  ic_debug_way_ff[pt.ICACHE_NUM_WAYS-1:0]   & {pt.ICACHE_NUM_WAYS{ic_debug_rd_en_ff}}) ;
   ///////////////////////////////////////////
   // PMU signals
   ///////////////////////////////////////////

    assign ifu_pmu_ic_miss_in   = ic_act_miss_f2_thr[pt.NUM_THREADS-1:0] ;
    assign ifu_pmu_ic_hit_in    = ic_act_hit_f2_thr[pt.NUM_THREADS-1:0]  ;
    assign ifu_pmu_bus_error_in = ifc_bus_acc_fault_f2_thr[pt.NUM_THREADS-1:0];
    assign ifu_pmu_bus_trxn_in  = bus_cmd_sent_thr[pt.NUM_THREADS-1:0] ;
    assign ifu_pmu_bus_busy_in  = {pt.NUM_THREADS{ifu_bus_arvalid_ff & ~ifu_bus_arready_ff}} & miss_pending_thr[pt.NUM_THREADS-1:0] ;

      rvdff #(5*pt.NUM_THREADS) ifu_pmu_sigs_ff (.*,
                       .clk (active_clk),
                       .din ({ifu_pmu_ic_miss_in[pt.NUM_THREADS-1:0],
                              ifu_pmu_ic_hit_in[pt.NUM_THREADS-1:0],
                              ifu_pmu_bus_error_in[pt.NUM_THREADS-1:0],
                              ifu_pmu_bus_busy_in[pt.NUM_THREADS-1:0],
                              ifu_pmu_bus_trxn_in[pt.NUM_THREADS-1:0]
                             }),
                       .dout({ifu_pmu_ic_miss[pt.NUM_THREADS-1:0],
                              ifu_pmu_ic_hit[pt.NUM_THREADS-1:0],
                              ifu_pmu_bus_error[pt.NUM_THREADS-1:0],

**逐段解释** ：

* 第 L1167 行：tag valid 对 uncacheable fetch 取反，避免 uncacheable path 被当作 cache hit。
* 第 L1173-L1177 行：PMU hit/miss 直接来自 ``ic_act_hit_f2_thr`` 和 ``ic_act_miss_f2_thr``；
  bus transaction、busy 和 error 也在同一位置聚合。
* 第 L1179-L1192 行：五类 PMU 信号一起打拍输出，宽度按 ``NUM_THREADS`` 展开。

**接口关系** ：

* **被调用** ：F2 hit/miss、bus command 和 bus wait 周期执行。
* **调用** ：PMU 输出寄存器。
* **共享状态** ：``ifu_pmu_ic_miss``、``ifu_pmu_ic_hit``、``ifu_pmu_bus_error``、
  ``ifu_pmu_bus_busy``、``ifu_pmu_bus_trxn``。

§24  Formal IFU 属性覆盖 ICache hit 与 bypass
--------------------------------------------------------------------------------

**职责** ：用 SVA 对 ICache hit 地址匹配和 bypass 数据非 stale 做形式化约束，同时 cover I$
hit 可达。

**关键代码** （``dv/formal/properties/eh2_ifu_assert.sv:L73-L79``）：

.. code-block:: systemverilog

     property p_ic_hit_addr_match;
       @(posedge clk) disable iff (!rst_l)
       (ic_hit_f)
       |->
       (ic_tag_addr_f == ic_req_addr_f);
     endproperty
     a_ic_hit_addr_match: assert property(p_ic_hit_addr_match);

**逐段解释** ：

* 第 L73-L79 行：当 ``ic_hit_f`` 为真时，属性要求 tag 地址等于 request 地址。该属性不描述
  replacement 或 fill，只约束 hit 事件的地址一致性。

**关键代码** （``dv/formal/properties/eh2_ifu_assert.sv:L117-L123``）：

.. code-block:: systemverilog

     property p_icache_bypass_no_stale;
       @(posedge clk) disable iff (!rst_l)
       (ic_bypass_f && ic_hit_f)
       |->
       (ic_bypass_data_f == ic_fetch_data_f);
     endproperty
     a_icache_bypass_no_stale: assert property(p_icache_bypass_no_stale);

**逐段解释** ：

* 第 L117-L123 行：当 bypass 与 hit 同时有效时，bypass 数据必须等于 fetch 数据，防止 bypass
  返回 stale data。

**关键代码** （``dv/formal/properties/eh2_ifu_assert.sv:L143-L146``）：

.. code-block:: systemverilog

     // Cover: I$ hit
     c_ic_hit_reachable: cover property(
       @(posedge clk) (ic_hit_f)
     );

**逐段解释** ：

* 第 L143-L146 行：cover property 要求 formal run 能到达 I$ hit 场景，用于避免相关 assertion
  只在不可达状态下 vacuous pass。

**接口关系** ：

* **被调用** ：formal top 连接 IFU 抽象信号后运行。
* **调用** ：SVA assertion/cover property。
* **共享状态** ：``ic_hit_f``、``ic_tag_addr_f``、``ic_req_addr_f``、``ic_bypass_f``、
  ``ic_bypass_data_f``、``ic_fetch_data_f``。

§25  功能覆盖：Icache hit/miss coverpoint
--------------------------------------------------------------------------------

**职责** ：在 UVM functional coverage 中记录 ICache hit 与 miss PMU 事件是否出现。

**关键代码** （``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L94-L96``）：

.. code-block:: systemverilog

     // -- PMU --
     input logic        ifu_pmu_ic_miss,
     input logic        ifu_pmu_ic_hit

**逐段解释** ：

* 第 L94-L96 行：coverage interface 把 ``ifu_pmu_ic_miss`` 和 ``ifu_pmu_ic_hit`` 作为输入，
  与 RTL 中的 PMU 输出同名。

**关键代码** （``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L360-L369``）：

.. code-block:: systemverilog

       // -----------------------------------------------------------------------
       // Cache events
       // -----------------------------------------------------------------------
       cp_icache_hit: coverpoint ifu_pmu_ic_hit {
         bins hit  = {1};
       }

       cp_icache_miss: coverpoint ifu_pmu_ic_miss {
         bins miss = {1};
       }

**逐段解释** ：

* 第 L360-L365 行：``cp_icache_hit`` 在 PMU hit 信号为 1 时命中 ``hit`` bin。
* 第 L367-L369 行：``cp_icache_miss`` 在 PMU miss 信号为 1 时命中 ``miss`` bin。
* 该 coverage 只证明事件被观察到；它不替代 RTL 中 hit/miss 判定逻辑的逐条件验证。

**接口关系** ：

* **被调用** ：UVM coverage interface 采样。
* **调用** ：covergroup coverpoint。
* **共享状态** ：``ifu_pmu_ic_hit``、``ifu_pmu_ic_miss``。

§26  UVM integrity 测试与 cosim waiver 边界
--------------------------------------------------------------------------------

**职责** ：ICache integrity 测试通过 RTL force/release 注入 ``ifu_ic_error_start[0]``，并检查
``micect`` 计数器变化；该类 fault injection 不走 cosim 比对，边界由 :ref:`adr-0017` 记录。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L229-L249``）：

.. code-block:: systemverilog

   class core_eh2_icache_intg_test extends core_eh2_base_test;

     `uvm_component_utils(core_eh2_icache_intg_test)

     string ic_error_path = "core_eh2_tb_top.dut.veer.ifu_ic_error_start[0]";
     string counter_path  = "core_eh2_tb_top.dut.veer.dec.tlu.micect";
     string fetch_path    = "core_eh2_tb_top.dut.veer.ifu.mem_ctl.ifc_fetch_req_f1";

     function new(string name = "core_eh2_icache_intg_test",
                  uvm_component parent = null);
       super.new(name, parent);
       test_name = name;
     endfunction

     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       env_cfg.enable_cosim = 0;
       env_cfg.disable_cosim = 1;
       env_cfg.timeout_ns = 64'd5_000_000_000;
       env_cfg.max_cycles = 500_000;
     endfunction

**逐段解释** ：

* 第 L229-L235 行：测试类绑定三个 HDL path：I$ error start、``micect`` counter 和 F1 fetch
  request。
* 第 L243-L249 行：build phase 显式设置 ``enable_cosim=0`` 与 ``disable_cosim=1``，说明该测试
  是 RTL-only integrity 场景。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L267-L307``）：

.. code-block:: systemverilog

       if (!core_eh2_intg_path_exists(ic_error_path)) begin
         `uvm_fatal(test_name, $sformatf("Missing ICache error path %s", ic_error_path))
       end
       if (!core_eh2_intg_path_exists(counter_path)) begin
         `uvm_fatal(test_name, $sformatf("Missing MICECT path %s", counter_path))
       end

       saw_fetch = 0;
       for (i = 0; i < 3000; i++) begin
         if (core_eh2_intg_path_exists(fetch_path)) begin
           core_eh2_intg_read_or_fatal(test_name, fetch_path, fetch_req);
           if (fetch_req[0]) begin
             saw_fetch = 1;
             break;
           end
         end

**逐段解释** ：

* 第 L267-L272 行：测试先检查 error path 和 counter path 是否存在，不存在则 fatal。
* 第 L274-L284 行：测试最多等待 3000 个 cycle 观察 fetch request，作为注入窗口前的活动性检查。
* 第 L289-L307 行：测试读取 ``micect`` 初值，force ``ifu_ic_error_start[0]`` 一个周期，release 后
  最多等待 30 个 cycle 检查 counter 是否变化；若未变化则 fatal。

**关键代码** （``docs/adr/0017-integrity-cosim-waiver.md:L38-L46``）：

.. code-block:: yaml

   ### 1. Integrity tests are permanently cosim: disabled

   These tests are waived from cosim comparison via the formal waiver file at
   `dv/uvm/core_eh2/waivers/cosim-disabled.yaml`, NOT via `cosim_reason` fields in
   the testlist YAML.

   The `cosim_reason` field in testlist entries is a **forbidden loophole** (Issue
   50 red line). `signoff.py` blocks signoff if any `cosim_reason` field is

**逐段解释** ：

* 第 L38-L42 行：ADR-0017 要求 integrity tests 通过正式 waiver 文件关闭 cosim comparison，
  而不是在 testlist 中写 ``cosim_reason``。
* 第 L44-L46 行：``cosim_reason`` 被 signoff gate 视为 forbidden loophole。
* 本章引用 ADR-0017 只用于说明 ICache integrity fault injection 的 cosim 边界；ICache RTL
  行为仍以前述 SystemVerilog 源码为准。

**接口关系** ：

* **被调用** ：UVM regression 运行 ``core_eh2_icache_intg_test`` 时执行。
* **调用** ：``core_eh2_intg_path_exists``、``core_eh2_intg_read_or_fatal``、
  ``core_eh2_intg_force_or_fatal``、``core_eh2_intg_release_or_fatal``。
* **共享状态** ：``ifu_ic_error_start[0]``、``dec.tlu.micect``、``env_cfg.disable_cosim``。

§27  参考资料
--------------------------------------------------------------------------------

* :ref:`appendix_a_rtl/ifu` — IFU RTL 字典章节，包含 ``eh2_ifu`` 与 ``eh2_ifu_mem_ctl`` 的更大范围上下文。
* :ref:`adr-0017` — integrity fault injection 测试的 cosim waiver 边界。
* :file:`syn/include/eh2_param.vh` — 当前 ICache/ICCM 参数实例。绝对路径：
  ``/home/host/eh2-veri/syn/include/eh2_param.vh``。
* :file:`rtl/design/eh2_mem.sv` — ICache/ICCM memory wrapper 实例化。绝对路径：
  ``/home/host/eh2-veri/rtl/design/eh2_mem.sv``。
* :file:`rtl/design/ifu/eh2_ifu.sv` — IFU 顶层 I$、ITAG、ICCM 端口。绝对路径：
  ``/home/host/eh2-veri/rtl/design/ifu/eh2_ifu.sv``。
* :file:`rtl/design/ifu/eh2_ifu_mem_ctl.sv` — ICache/ICCM 控制、miss FSM、fill、bypass、ECC 与 PMU。
  绝对路径：``/home/host/eh2-veri/rtl/design/ifu/eh2_ifu_mem_ctl.sv``。
* :file:`rtl/design/ifu/eh2_ifu_ic_mem.sv` — ICache data/tag SRAM wrapper、data/tag ECC/parity 与 hit 比较。
  绝对路径：``/home/host/eh2-veri/rtl/design/ifu/eh2_ifu_ic_mem.sv``。
* :file:`dv/formal/properties/eh2_ifu_assert.sv` — IFU formal 属性，包括 I$ hit 地址匹配和 bypass 数据一致性。
  绝对路径：``/home/host/eh2-veri/dv/formal/properties/eh2_ifu_assert.sv``。
* :file:`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv` — ICache hit/miss 功能覆盖点。
  绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_if.sv``。
* :file:`dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv` — ``core_eh2_icache_intg_test``。
  绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv``。
* :file:`docs/adr/0017-integrity-cosim-waiver.md` — integrity cosim waiver 决策记录。绝对路径：
  ``/home/host/eh2-veri/docs/adr/0017-integrity-cosim-waiver.md``。
