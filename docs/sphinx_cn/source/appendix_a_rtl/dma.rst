.. _appendix_a_rtl_dma:
.. _appendix_a_rtl/dma:

DMA 控制器 — 详细参考
======================

:status: draft
:source: rtl/design/eh2_dma_ctrl.sv
:last-reviewed: 2026-05-19

§1  源文件边界与集成位置
------------------------

本章只描述 ``eh2_dma_ctrl`` 在当前源码中的实现。该模块位于
:file:`rtl/design/eh2_dma_ctrl.sv`，在 :file:`dv/uvm/core_eh2/eh2_rtl.f`
中作为 top-level RTL 文件列出，并由 :file:`rtl/design/eh2_veer.sv`
实例化为 ``dma_ctrl``。文档中的 AXI、DCCM、ICCM、PIC、debug、PMU 语义均来自
这些源码片段，不从外部总线协议或旧文档反推。

``eh2_dma_ctrl`` 的内部数据流可以概括为：

.. code-block:: text

   Debug abstract memory command
          │
          ▼
      dbg_mem_cmd_valid ─┐
                          │
   AXI AW/W ─► wrbuf ─┐   │
                      ├──► FIFO[WrPtr] ─► FIFO[RdPtr] ─► DCCM / ICCM request
   AXI AR   ─► rdbuf ─┘   │                 │
                          │                 ├──► address / alignment / debug error
                          │                 │
                          └─────────────────┘
                                            ▼
                                      FIFO[RspPtr]
                                            │
                              ┌─────────────┴─────────────┐
                              ▼                           ▼
                         AXI B/R response            debug done/fail

图中的 ``WrPtr``、``RdPtr``、``RspPtr`` 对应源码中的三个 FIFO 指针。
AXI 写地址和写数据先进入 ``wrbuf``，AXI 读地址进入 ``rdbuf``；debug 抽象命令
不经过 AXI 缓冲，而是通过 ``dbg_mem_cmd_valid`` 直接参加 FIFO 写入选择。
FIFO 的读端根据地址范围和错误检查产生 DCCM 或 ICCM 请求，完成项再由响应指针
转成 AXI B/R 响应或 debug 完成信号。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L70-L73``）：

.. code-block:: text

   // Top-level
   rtl/design/eh2_dma_ctrl.sv
   rtl/design/eh2_mem.sv
   rtl/design/eh2_pic_ctrl.sv
   rtl/design/eh2_veer.sv

逐段解释：

* 第 L70-L73 行：filelist 将 ``eh2_dma_ctrl.sv`` 与 ``eh2_mem.sv``、
  ``eh2_pic_ctrl.sv``、``eh2_veer.sv`` 放在 top-level 组。该事实只说明编译边界，
  不说明 ``eh2_dma_ctrl`` 自身会实例化 MEM 或 PIC。
* 第 L71 行：``eh2_dma_ctrl.sv`` 是独立 RTL 编译单元，本文后续所有内部逻辑解释
  均以该文件为主证据。

接口关系：

* 被引用：:file:`dv/uvm/core_eh2/eh2_rtl.f` 将该文件纳入 RTL 编译列表。
* 关联章节：:doc:`mem` 说明 DCCM/ICCM 存储实现，:doc:`pic` 说明 PIC 控制逻辑。
* 共享状态：该 filelist 不读写信号，只确定编译输入集合。

关键代码（``rtl/design/eh2_veer.sv:L1119-L1141``）：

.. code-block:: systemverilog

      eh2_dma_ctrl #(.pt(pt)) dma_ctrl (
                                        .clk(free_l2clk),
                                        .rst_l(core_rst_l),
                                        .clk_override(dec_tlu_misc_clk_override),

                                        // AXI signals
                                        .dma_axi_awvalid(dma_axi_awvalid_int),
                                        .dma_axi_awid(dma_axi_awid_int[pt.DMA_BUS_TAG-1:0]),
                                        .dma_axi_awaddr(dma_axi_awaddr_int[31:0]),
                                        .dma_axi_awsize(dma_axi_awsize_int[2:0]),
                                        .dma_axi_wvalid(dma_axi_wvalid_int),
                                        .dma_axi_wdata(dma_axi_wdata_int[63:0]),
                                        .dma_axi_wstrb(dma_axi_wstrb_int[7:0]),
                                        .dma_axi_bready(dma_axi_bready_int),

                                        .dma_axi_arvalid(dma_axi_arvalid_int),
                                        .dma_axi_arid(dma_axi_arid_int[pt.DMA_BUS_TAG-1:0]),
                                        .dma_axi_araddr(dma_axi_araddr_int[31:0]),
                                        .dma_axi_arsize(dma_axi_arsize_int[2:0]),
                                        .dma_axi_rready(dma_axi_rready_int),

                                        .*
      );

逐段解释：

* 第 L1119 行：顶层实例名是 ``dma_ctrl``，参数 ``pt`` 传入 ``eh2_dma_ctrl``。
  本章在描述层次路径时使用 ``dma_ctrl``，在描述模块定义时使用 ``eh2_dma_ctrl``。
* 第 L1120-L1123 行：该实例使用 ``free_l2clk``、``core_rst_l`` 和
  ``dec_tlu_misc_clk_override``。这些信号解释了模块内部多个 gated clock 生成逻辑
  为什么接收 ``clk``、``rst_l``、``clk_override``。
* 第 L1125-L1138 行：顶层显式连接 AXI 写地址、写数据、写响应 ready、读地址和
  读响应 ready 信号；ready、response、core-side、debug 等其他端口通过第 L1140 行
  的 ``.*`` 按同名规则连接。
* 第 L1140 行：``.*`` 使 ``dma_dccm_req``、``dma_iccm_req``、
  ``dma_active``、debug 端口和 PMU 端口进入顶层同名网络。本文不会把未在
  ``eh2_dma_ctrl.sv`` 中出现的上层协议行为归入 DMA 控制器。

接口关系：

* 被实例化：``eh2_veer`` 在 ``dma_ctrl`` 实例中连接 ``eh2_dma_ctrl``。
* 调用：作为硬件模块没有函数调用；组合逻辑和触发器由端口信号驱动。
* 共享状态：参数 ``pt``、clock/reset、AXI 内部信号和同名 debug/core/PMU 网络。

§2  模块端口分组
----------------

``eh2_dma_ctrl`` 的端口按照源码顺序分为时钟复位、debug、core-side、PMU、AXI 写通道和
AXI 读通道。这里的“core-side”只指该模块输出到 DCCM/ICCM 访问路径的信号，以及从
DCCM/ICCM 返回的 ``*_dma_rvalid``、``*_dma_rdata``、``*_dma_ecc_error`` 和 tag。

§2.1  ``module eh2_dma_ctrl`` — 参数与时钟控制入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 ``eh2_dma_ctrl`` 模块边界并接收通用控制信号。参数文件
``eh2_param.vh`` 通过 include 进入模块参数列表，内部的 ``pt`` 字段随后用于
FIFO 深度、tag 宽度、DCCM/ICCM/PIC 地址范围和总线位宽。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L24-L35``）：

.. code-block:: systemverilog

   module eh2_dma_ctrl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )(
      input logic         clk,
      input logic         free_clk,
      input logic         rst_l,
      input logic         dma_bus_clk_en, // slave bus clock enable
      input logic         clk_override,
      input logic         scan_mode,

逐段解释：

* 第 L24-L28 行：模块名为 ``eh2_dma_ctrl``，导入 ``eh2_pkg::*``，并在参数区包含
  ``eh2_param.vh``。后续代码中的 ``pt.DMA_BUF_DEPTH``、``pt.DMA_BUS_TAG``、
  ``pt.DCCM_ENABLE`` 等字段都来自该参数对象。
* 第 L29-L35 行：``clk``、``free_clk``、``rst_l`` 是主时钟、free clock 与低有效复位；
  ``dma_bus_clk_en`` 是 AXI slave bus 侧 clock enable；``clk_override`` 参与 gated
  clock 使能；``scan_mode`` 作为端口出现，但本文件后续逻辑没有显式读取该信号。

接口关系：

* 被连接：``eh2_veer`` 的 ``dma_ctrl`` 实例连接 ``free_l2clk``、``core_rst_l`` 和
  ``dec_tlu_misc_clk_override``。
* 调用：本段只声明模块，不调用子模块。
* 共享状态：参数 ``pt`` 和 clock/reset/override 信号被后续触发器、range check 和
  clock-gating 逻辑使用。

§2.2  Debug 端口 — 抽象 memory 命令入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接收 debug abstract memory command，并输出 ready、done、fail 和读数据。
源码中只有 ``dbg_cmd_type[1]`` 为真时才把 debug 命令作为 memory 命令放入 DMA FIFO。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L36-L49``）：

.. code-block:: systemverilog

      // Debug signals
      input logic [31:0]  dbg_cmd_addr,
      input logic [31:0]  dbg_cmd_wrdata,
      input logic         dbg_cmd_valid,
      input logic         dbg_cmd_write, // 1: write command, 0: read_command
      input logic [1:0]   dbg_cmd_type, // 0:gpr 1:csr 2: memory
      input logic [1:0]   dbg_cmd_size, // size of the abstract mem access debug command

      input  logic        dbg_dma_bubble,   // Debug needs a bubble to send a valid
      output logic        dma_dbg_ready,    // DMA is ready to accept debug request

      output logic        dma_dbg_cmd_done,
      output logic        dma_dbg_cmd_fail,
      output logic [31:0] dma_dbg_rddata,

逐段解释：

* 第 L37-L42 行：debug 输入携带地址、写数据、valid、读写方向、命令类型和访问大小。
  后续第 L241 行用 ``dbg_cmd_valid & dbg_cmd_type[1]`` 生成
  ``dbg_mem_cmd_valid``，因此本模块只把 ``dbg_cmd_type`` bit 1 为真的命令作为
  memory 访问。
* 第 L44-L45 行：``dbg_dma_bubble`` 是 debug 侧给出的 bubble 请求；
  ``dma_dbg_ready`` 在第 L327 行由 ``fifo_empty & dbg_dma_bubble`` 生成。
* 第 L47-L49 行：``dma_dbg_cmd_done``、``dma_dbg_cmd_fail`` 和 ``dma_dbg_rddata``
  都来自 FIFO 响应指针 ``RspPtr`` 指向的 debug 项，而不是来自 AXI response 通道。

接口关系：

* 被连接：顶层通过同名端口连接 debug 控制路径。
* 调用：debug 入口进入 FIFO 输入 mux、debug 错误检查和 debug 读数据抽取逻辑。
* 共享状态：读写 ``fifo_dbg``、``fifo_data``、``fifo_error``、``RspPtr`` 等 FIFO 状态。

§2.3  Core-side 与 PMU 端口 — DCCM/ICCM 请求边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 FIFO 读端的请求转换为 DCCM 或 ICCM 访问，并从 DCCM/ICCM 接收读返回和 ECC
状态；同时输出 DMA 活跃状态、stall 信号和 PMU 事件。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L51-L82``）：

.. code-block:: systemverilog

      // Core side signals
      output logic        dma_dccm_req,  // DMA dccm request (only one of dccm/iccm will be set)
      output logic        dma_dccm_spec_req,  // DMA dccm spec request (this is need for eh2 plus1)
      output logic        dma_iccm_req,  // DMA iccm request
      output logic        dma_mem_addr_in_dccm,  // DMA address is in dccm
      output logic [2:0]  dma_mem_tag,   // DMA Buffer entry number
      output logic [31:0] dma_mem_addr,  // DMA request address
      output logic [2:0]  dma_mem_sz,    // DMA request size
      output logic        dma_mem_write, // DMA write to dccm/iccm
      output logic [63:0] dma_mem_wdata, // DMA write data

      input logic         dccm_dma_rvalid,    // dccm data valid for DMA read
      input logic         dccm_dma_ecc_error, // ECC error on DMA read
      input logic [2:0]   dccm_dma_rtag,      // Tag of the DMA req
      input logic [63:0]  dccm_dma_rdata,     // dccm data for DMA read
      input logic         iccm_dma_rvalid,    // iccm data valid for DMA read
      input logic         iccm_dma_ecc_error, // ECC error on DMA read
      input logic [2:0]   iccm_dma_rtag,      // Tag of the DMA req
      input logic [63:0]  iccm_dma_rdata,     // iccm data for DMA read

      output logic        dma_active,         // DMA is busy
      output logic        dma_dccm_stall_any, // stall dccm pipe (bubble) so that DMA can proceed
      output logic        dma_iccm_stall_any, // stall iccm pipe (bubble) so that DMA can proceed
      input logic         dccm_ready, // dccm ready to accept DMA request
      input logic         iccm_ready, // iccm ready to accept DMA request
      input logic [2:0]   dec_tlu_dma_qos_prty,    // DMA QoS priority coming from MFDC [18:15]

      // PMU signals
      output logic        dma_pmu_dccm_read,
      output logic        dma_pmu_dccm_write,
      output logic        dma_pmu_any_read,
      output logic        dma_pmu_any_write,

逐段解释：

* 第 L52-L60 行：请求输出包含 DCCM/ICCM 选择、FIFO entry tag、地址、大小、写方向和
  写数据。源码第 L363-L365 行保证实际请求由 ``dma_mem_req``、地址范围和 ready
  共同决定。
* 第 L62-L69 行：DCCM 与 ICCM 的读返回各自带 ``rvalid``、ECC error、tag 和 64-bit
  数据。第 L253-L258 行按返回 tag 更新对应 FIFO entry 的 data/error。
* 第 L71-L76 行：``dma_active`` 表示写缓冲、读缓冲或 FIFO 中有未清空项；
  ``dma_dccm_stall_any`` 和 ``dma_iccm_stall_any`` 由 nack 计数与 ready 状态产生；
  ``dec_tlu_dma_qos_prty`` 被第 L354 行送入 ``dma_nack_count_csr``。
* 第 L79-L82 行：PMU 输出不是独立计数器，而是第 L376-L379 行由实际
  ``dma_dccm_req``、``dma_iccm_req`` 和 ``dma_mem_write`` 组合生成的事件脉冲。

接口关系：

* 被连接：顶层通过 ``.*`` 把这些信号接入 LSU/IFU/DEC/TLU 相关网络。
* 调用：请求端读取 FIFO 当前读指针项；响应端写回 FIFO data/error/done。
* 共享状态：``RdPtr``、``fifo_addr``、``fifo_sz``、``fifo_write``、``fifo_data``、
  ``fifo_rpend``、``fifo_done`` 和 nack 计数器。

§2.4  AXI 端口 — 单 beat 读写通道入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接收 DMA AXI 写地址、写数据、读地址，并返回 AXI B/R 响应。该模块端口没有
``awlen``、``wlast``、``arlen`` 等 burst 控制信号；源码第 L500 行固定
``dma_axi_rlast`` 为 ``1'b1``。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L84-L114``）：

.. code-block:: systemverilog

      // AXI Write Channels
      input  logic                        dma_axi_awvalid,
      output logic                        dma_axi_awready,
      input  logic [pt.DMA_BUS_TAG-1:0]   dma_axi_awid,
      input  logic [31:0]                 dma_axi_awaddr,
      input  logic [2:0]                  dma_axi_awsize,


      input  logic                        dma_axi_wvalid,
      output logic                        dma_axi_wready,
      input  logic [63:0]                 dma_axi_wdata,
      input  logic [7:0]                  dma_axi_wstrb,

      output logic                        dma_axi_bvalid,
      input  logic                        dma_axi_bready,
      output logic [1:0]                  dma_axi_bresp,
      output logic [pt.DMA_BUS_TAG-1:0]   dma_axi_bid,

      // AXI Read Channels
      input  logic                        dma_axi_arvalid,
      output logic                        dma_axi_arready,
      input  logic [pt.DMA_BUS_TAG-1:0]   dma_axi_arid,
      input  logic [31:0]                 dma_axi_araddr,
      input  logic [2:0]                  dma_axi_arsize,

      output logic                        dma_axi_rvalid,
      input  logic                        dma_axi_rready,
      output logic [pt.DMA_BUS_TAG-1:0]   dma_axi_rid,
      output logic [63:0]                 dma_axi_rdata,
      output logic [1:0]                  dma_axi_rresp,
      output logic                        dma_axi_rlast

逐段解释：

* 第 L85-L99 行：写侧拆成 AW、W、B 三组。AW 只携带 id/address/size，W 携带
  data/strobe，B 输出 id 和 response。
* 第 L103-L114 行：读侧拆成 AR 和 R 两组。AR 携带 id/address/size，R 返回
  id/data/response/last。
* 这些端口在内部不是直接驱动 core-side 请求；AW/W 先进入 ``wrbuf``，AR 进入
  ``rdbuf``，然后由 ``bus_cmd_valid``、``axi_mstr_sel`` 和 ``dma_fifo_ready`` 合并
  成单个 FIFO 输入。

接口关系：

* 被连接：``eh2_veer`` 把 ``dma_axi_*_int`` 接到这些端口。
* 调用：AXI 输入驱动写缓冲、读缓冲和 bus command 选择；AXI 输出由 FIFO 响应项生成。
* 共享状态：``wrbuf_*``、``rdbuf_*``、``bus_cmd_*``、``axi_rsp_*`` 和 ``fifo_*``。

§3  FIFO 状态与输入选择
-----------------------

FIFO 是 ``eh2_dma_ctrl`` 的中心状态结构。它保存地址、大小、byte enable、读写方向、
posted write 标志、debug 标志、64-bit 数据、tag、mid 和 priority，并用 valid、
error、read-pending、done、done_bus 等 bit 追踪生命周期。

§3.1  FIFO 宽度与 entry 字段 — ``DEPTH`` 来自参数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 DMA FIFO 的深度、指针宽度和每个 entry 保存的字段。``DEPTH`` 不是写死值，
而是 ``pt.DMA_BUF_DEPTH``；因此文档不在此推导具体 entry 数。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L118-L151``）：

.. code-block:: systemverilog

      localparam DEPTH = pt.DMA_BUF_DEPTH;
      localparam DEPTH_PTR = $clog2(DEPTH);
      localparam NACK_COUNT = 7;

      logic [DEPTH-1:0]        fifo_valid;
      logic [DEPTH-1:0][1:0]   fifo_error;
      logic [DEPTH-1:0]        fifo_dccm_valid;
      logic [DEPTH-1:0]        fifo_iccm_valid;
      logic [DEPTH-1:0]        fifo_error_bus;
      logic [DEPTH-1:0]        fifo_rpend;
      logic [DEPTH-1:0]        fifo_done;      // DMA trxn is done in core
      logic [DEPTH-1:0]        fifo_done_bus;  // DMA trxn is done in core but synced to bus clock
      logic [DEPTH-1:0][31:0]  fifo_addr;
      logic [DEPTH-1:0][2:0]   fifo_sz;
      logic [DEPTH-1:0][7:0]   fifo_byteen;
      logic [DEPTH-1:0]        fifo_write;
      logic [DEPTH-1:0]        fifo_posted_write;
      logic [DEPTH-1:0]        fifo_dbg;
      logic [DEPTH-1:0][63:0]  fifo_data;
      logic [DEPTH-1:0][pt.DMA_BUS_TAG-1:0]  fifo_tag;
      logic [DEPTH-1:0][pt.DMA_BUS_ID-1:0]   fifo_mid;
      logic [DEPTH-1:0][pt.DMA_BUS_PRTY-1:0] fifo_prty;

逐段解释：

* 第 L118-L120 行：``DEPTH`` 来自 ``pt.DMA_BUF_DEPTH``，``DEPTH_PTR`` 由
  ``$clog2`` 得到，``NACK_COUNT`` 被声明为 7。当前文件后续使用
  ``dma_nack_count_csr`` 控制 nack 阈值，没有直接引用 ``NACK_COUNT``。
* 第 L122-L132 行：valid/error/error_bus/rpend/done/done_bus 保存 entry 生命周期。
  ``fifo_done_bus`` 的注释表明它是 core 完成状态同步到 bus clock 后的版本。
* 第 L133-L144 行：地址、size、byte enable、读写方向、posted write、debug 标志和
  data 是实际请求/响应数据面。``fifo_dbg`` 决定响应走 AXI 还是 debug。
* 第 L145-L147 行：tag、mid、priority 使用参数化宽度。当前 bus command 逻辑把
  ``bus_cmd_mid`` 和 ``bus_cmd_prty`` 赋为 ``'0``，但 FIFO 仍保留字段。

接口关系：

* 被写入：FIFO 写指针处由 AXI bus command 或 debug command 写入。
* 被读取：FIFO 读指针产生 core-side 请求，响应指针产生 AXI/debug 响应。
* 共享状态：``DEPTH`` 同时约束 generate 循环、指针 wrap、full 计算和 active 计算。

§3.2  控制信号与缓冲状态 — FIFO 外围寄存器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 FIFO 写入使能、数据使能、错误使能、指针、debug 临时信号、请求状态、
bus command 状态、写缓冲和读缓冲状态。这里的声明决定后续组合逻辑可见的共享状态。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L149-L236``）：

.. code-block:: systemverilog

      logic [DEPTH-1:0]        fifo_cmd_en;
      logic [DEPTH-1:0]        fifo_data_en;
      logic [DEPTH-1:0]        fifo_data_bus_en;
      logic [DEPTH-1:0]        fifo_pend_en;
      logic [DEPTH-1:0]        fifo_done_en;
      logic [DEPTH-1:0]        fifo_done_bus_en;
      logic [DEPTH-1:0]        fifo_error_en;
      logic [DEPTH-1:0]        fifo_error_bus_en;
      logic [DEPTH-1:0]        fifo_reset;
      logic [DEPTH-1:0][1:0]   fifo_error_in;
      logic [DEPTH-1:0][63:0]  fifo_data_in;

      logic                    fifo_write_in;
      logic                    fifo_posted_write_in;
      logic                    fifo_dbg_in;
      logic [31:0]             fifo_addr_in;
      logic [2:0]              fifo_sz_in;
      logic [7:0]              fifo_byteen_in;

逐段解释：

* 第 L149-L159 行：这些 one-hot 或 per-entry 信号驱动 generate 循环中的触发器。
  其中 ``fifo_data_bus_en`` 在本文件后续没有被引用，不能据此扩展额外行为。
* 第 L161-L166 行：``fifo_*_in`` 是写入 FIFO entry 的 mux 结果，来源可以是 debug
  command，也可以是 AXI bus command。

接口关系：

* 被写入：组合赋值在第 L241-L269 行生成这些输入和使能。
* 调用：generate 块用这些信号驱动 ``rvdffsc``、``rvdffs``、``rvdffe`` 等触发器。
* 共享状态：所有 FIFO entry 触发器共享 ``WrPtr``、``RdPtr``、``RspPtr``。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L168-L236``）：

.. code-block:: systemverilog

      logic [DEPTH_PTR-1:0]    RspPtr, NxtRspPtr;
      logic [DEPTH_PTR-1:0]    WrPtr, NxtWrPtr;
      logic [DEPTH_PTR-1:0]    RdPtr, NxtRdPtr;
      logic                    WrPtrEn, RdPtrEn, RspPtrEn;

      logic [1:0]              dma_dbg_sz;
      logic [1:0]              dma_dbg_addr;
      logic [31:0]             dma_dbg_mem_rddata;
      logic [31:0]             dma_dbg_mem_wrdata;
      logic                    dma_dbg_cmd_error;
      logic                    dma_dbg_cmd_done_q;

      logic                    fifo_full, fifo_full_spec, fifo_empty;
      logic                    dma_address_error, dma_alignment_error;
      logic [3:0]              num_fifo_vld;
      logic                    dma_mem_req_spec, dma_mem_req;
      logic [7:0]              dma_mem_byteen;
      logic [31:0]             dma_mem_addr_int;
      logic [2:0]              dma_mem_sz_int;

逐段解释：

* 第 L168-L171 行：三个指针分离 FIFO 写入、core-side 发起和 response 清理。该设计允许
  一个 entry 已发出读请求但仍等待 DCCM/ICCM 返回。
* 第 L173-L178 行：debug 临时信号用于读数据抽取、写数据复制和 debug 命令错误判断。
* 第 L180-L187 行：full/empty、address/alignment error、请求 speculative 状态、
  当前地址/size/byte enable 是核心请求判断所需的组合状态。

接口关系：

* 被写入：指针由第 L298-L300 行触发器更新，其他信号多由组合赋值生成。
* 调用：错误逻辑、debug 输出、core request、PMU、AXI response 都读取这些声明。
* 共享状态：``num_fifo_vld`` 的宽度为 4 bit，full 计算只基于源码当前声明，不在文档中
  另行推导支持的最大深度。

§3.3  Debug 与 AXI 输入 mux — ``dbg_mem_cmd_valid`` 优先选择 debug 字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 debug memory 命令和 AXI bus command 统一成 FIFO 写入字段。debug 路径在
``dbg_mem_cmd_valid`` 为真时提供地址、size、写方向和 byte enable；否则使用
``bus_cmd_*``。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L241-L247``）：

.. code-block:: systemverilog

      assign dbg_mem_cmd_valid     = dbg_cmd_valid & dbg_cmd_type[1];
      assign fifo_addr_in[31:0]    = dbg_mem_cmd_valid ? dbg_cmd_addr[31:0] : bus_cmd_addr[31:0];
      assign fifo_byteen_in[7:0]   = dbg_mem_cmd_valid ? (8'h0f << 4*dbg_cmd_addr[2]) : bus_cmd_byteen[7:0];
      assign fifo_sz_in[2:0]       = dbg_mem_cmd_valid ? {1'b0,dbg_cmd_size[1:0]} : bus_cmd_sz[2:0];
      assign fifo_write_in         = dbg_mem_cmd_valid ? dbg_cmd_write : bus_cmd_write;
      assign fifo_posted_write_in  = ~dbg_mem_cmd_valid & bus_cmd_posted_write;
      assign fifo_dbg_in           = dbg_mem_cmd_valid;

逐段解释：

* 第 L241 行：只有 ``dbg_cmd_valid`` 且 ``dbg_cmd_type[1]`` 为真时，debug 命令才进入
  DMA memory FIFO。源码注释把 ``dbg_cmd_type`` 编码为 0:gpr、1:csr、2:memory。
* 第 L242-L245 行：debug 命令覆盖 FIFO 地址、byte enable、size 和写方向；
  非 debug 命令使用 AXI bus command 的相同字段。
* 第 L243 行：debug byte enable 由 ``8'h0f << 4*dbg_cmd_addr[2]`` 生成，只根据地址
  bit 2 选择低 32 bit 或高 32 bit 半字。
* 第 L246-L247 行：posted write 只允许来自非 debug bus command；``fifo_dbg_in`` 直接
  标记该 FIFO entry 是否属于 debug。

接口关系：

* 被调用：generate 块在 ``fifo_cmd_en`` 或 ``fifo_data_en`` 有效时采样这些输入。
* 调用：读取 debug 端口和 ``bus_cmd_*`` 组合结果。
* 共享状态：``fifo_dbg`` 影响 debug 错误、AXI response 过滤和 debug done/fail。

§4  FIFO entry 生命周期
-------------------------

每个 FIFO entry 的生命周期由 generate 循环统一定义：写入命令、可能写入数据、发起
DCCM/ICCM 读后置为 pending、收到读返回或写请求完成后置 done、AXI/debug 响应消费后 reset。

§4.1  ``GenFifo`` 使能逻辑 — command、data、pending、error、done、reset
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为每个 entry 生成写命令使能、数据写使能、读 pending、错误更新、完成更新和清理条件。
该段是 FIFO 生命周期的组合控制核心。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L250-L269``）：

.. code-block:: systemverilog

      for (genvar i=0 ;i<DEPTH; i++) begin: GenFifo
         assign fifo_cmd_en[i]   = ((bus_cmd_sent & dma_bus_clk_en) | dbg_mem_cmd_valid) & (i == WrPtr[DEPTH_PTR-1:0]);
         assign fifo_data_en[i] = (((bus_cmd_sent & fifo_write_in & dma_bus_clk_en) | (dbg_mem_cmd_valid & dbg_cmd_write))  & (i == WrPtr[DEPTH_PTR-1:0])) |
                                  ((dma_address_error | dma_alignment_error) & (i == RdPtr[DEPTH_PTR-1:0])) |
                                  (dccm_dma_rvalid & (i == DEPTH_PTR'(dccm_dma_rtag[2:0]))) |
                                  (iccm_dma_rvalid & (i == DEPTH_PTR'(iccm_dma_rtag[2:0])));
         assign fifo_pend_en[i] = (dma_dccm_req | dma_iccm_req) & ~dma_mem_write & (i == RdPtr[DEPTH_PTR-1:0]);
         assign fifo_error_en[i] = ((dma_address_error | dma_alignment_error | dma_dbg_cmd_error) & (i == RdPtr[DEPTH_PTR-1:0])) |
                                   ((dccm_dma_rvalid & dccm_dma_ecc_error) & (i == DEPTH_PTR'(dccm_dma_rtag[2:0]))) |
                                   ((iccm_dma_rvalid & iccm_dma_ecc_error) & (i == DEPTH_PTR'(iccm_dma_rtag[2:0])));
         assign fifo_error_bus_en[i] = (((|fifo_error_in[i][1:0]) & fifo_error_en[i]) | (|fifo_error[i])) & dma_bus_clk_en;
         assign fifo_done_en[i] = ((|fifo_error[i] | fifo_error_en[i] | ((dma_dccm_req | dma_iccm_req) & dma_mem_write)) & (i == RdPtr[DEPTH_PTR-1:0])) |
                                  (dccm_dma_rvalid & (i == DEPTH_PTR'(dccm_dma_rtag[2:0]))) |
                                  (iccm_dma_rvalid & (i == DEPTH_PTR'(iccm_dma_rtag[2:0])));
         assign fifo_done_bus_en[i] = (fifo_done_en[i] | fifo_done[i]) & dma_bus_clk_en;
         assign fifo_reset[i] = (((bus_rsp_sent | bus_posted_write_done) & dma_bus_clk_en) | dma_dbg_cmd_done) & (i == RspPtr[DEPTH_PTR-1:0]);
         assign fifo_error_in[i]   = (dccm_dma_rvalid & (i == DEPTH_PTR'(dccm_dma_rtag[2:0]))) ? {1'b0,dccm_dma_ecc_error} : (iccm_dma_rvalid & (i == DEPTH_PTR'(iccm_dma_rtag[2:0]))) ? {1'b0,iccm_dma_ecc_error}  :
                                                                                                                   {(dma_address_error | dma_alignment_error | dma_dbg_cmd_error), dma_alignment_error};

逐段解释：

* 第 L250 行：FIFO command 写入发生在 bus command 已发送且 bus clock enable 有效，
  或 debug memory 命令有效时；写入位置必须等于 ``WrPtr``。
* 第 L251-L254 行：FIFO data 的更新来源有四类：写命令携带的数据、地址或对齐错误时记录的
  data、DCCM 读返回、ICCM 读返回。DCCM/ICCM 返回通过 tag 命中对应 entry。
* 第 L255 行：非写请求发向 DCCM/ICCM 后设置 ``fifo_rpend``，表示该读请求已发出但响应
  尚未清理。
* 第 L256-L258 行：错误来源包括地址错误、对齐错误、debug 命令错误，以及 DCCM/ICCM
  返回的 ECC error。
* 第 L259-L263 行：``fifo_error_bus`` 和 ``fifo_done_bus`` 只在 ``dma_bus_clk_en`` 时更新，
  用于 bus clock 侧 AXI response 观察。
* 第 L264 行：entry 清理由 AXI response 发送、posted write 完成或 debug command done
  触发，并且只清理 ``RspPtr`` 指向的 entry。
* 第 L265-L266 行：DCCM/ICCM ECC error 被编码到低位；地址、对齐或 debug 错误被编码为
  ``{总错误, 对齐错误}``。后续 AXI response 用这两位映射 ``2'b10`` 或 ``2'b11``。

接口关系：

* 被调用：触发器实例在同一 generate 块中使用这些使能。
* 调用：读取 bus command、debug command、DCCM/ICCM 返回、错误逻辑和指针。
* 共享状态：``WrPtr`` 控制写入，``RdPtr`` 控制发起/错误，``RspPtr`` 控制清理。

§4.2  FIFO data 与触发器 — entry 字段实际落寄存器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：选择写入 ``fifo_data`` 的值，并把生命周期 bit 与数据面字段保存到触发器。
该段决定错误响应时返回什么 data，以及 DCCM/ICCM read data 如何覆盖原 entry 数据。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L267-L286``）：

.. code-block:: systemverilog

         assign fifo_data_in[i]   = (fifo_error_en[i] & (|fifo_error_in[i])) ? {32'b0,fifo_addr[i]} :
                                                           ((dccm_dma_rvalid & (i == DEPTH_PTR'(dccm_dma_rtag[2:0])))  ? dccm_dma_rdata[63:0] : (iccm_dma_rvalid & (i == DEPTH_PTR'(iccm_dma_rtag[2:0]))) ? iccm_dma_rdata[63:0] :
                                                                                                                                                          (dbg_mem_cmd_valid ? {2{dma_dbg_mem_wrdata[31:0]}} : bus_cmd_wdata[63:0]));

         rvdffsc #(1) fifo_valid_dff (.din(1'b1), .dout(fifo_valid[i]), .en(fifo_cmd_en[i]), .clear(fifo_reset[i]), .clk(dma_free_clk), .*);
         rvdffsc #(2) fifo_error_dff (.din(fifo_error_in[i]), .dout(fifo_error[i]), .en(fifo_error_en[i]), .clear(fifo_reset[i]), .clk(dma_free_clk), .*);
         rvdffsc #(1) fifo_error_bus_dff (.din(1'b1), .dout(fifo_error_bus[i]), .en(fifo_error_bus_en[i]), .clear(fifo_reset[i]), .clk(dma_free_clk), .*);
         rvdffsc #(1) fifo_rpend_dff (.din(1'b1), .dout(fifo_rpend[i]), .en(fifo_pend_en[i]), .clear(fifo_reset[i]), .clk(dma_free_clk), .*);
         rvdffsc #(1) fifo_done_dff (.din(1'b1), .dout(fifo_done[i]), .en(fifo_done_en[i]), .clear(fifo_reset[i]), .clk(dma_free_clk), .*);
         rvdffsc #(1) fifo_done_bus_dff (.din(1'b1), .dout(fifo_done_bus[i]), .en(fifo_done_bus_en[i]), .clear(fifo_reset[i]), .clk(dma_free_clk), .*);
         rvdffe  #(32) fifo_addr_dff (.din(fifo_addr_in[31:0]), .dout(fifo_addr[i]), .en(fifo_cmd_en[i]), .*);
         rvdffs  #(3) fifo_sz_dff (.din(fifo_sz_in[2:0]), .dout(fifo_sz[i]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffs  #(8) fifo_byteen_dff (.din(fifo_byteen_in[7:0]), .dout(fifo_byteen[i]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffs  #(1) fifo_write_dff (.din(fifo_write_in), .dout(fifo_write[i]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffs  #(1) fifo_posted_write_dff (.din(fifo_posted_write_in), .dout(fifo_posted_write[i]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffs  #(1) fifo_dbg_dff (.din(fifo_dbg_in), .dout(fifo_dbg[i]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffe  #(64) fifo_data_dff (.din(fifo_data_in[i]), .dout(fifo_data[i]), .en(fifo_data_en[i]), .*);
         rvdffs  #(pt.DMA_BUS_TAG) fifo_tag_dff(.din(bus_cmd_tag[pt.DMA_BUS_TAG-1:0]), .dout(fifo_tag[i][pt.DMA_BUS_TAG-1:0]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffs  #(pt.DMA_BUS_ID) fifo_mid_dff(.din(bus_cmd_mid[pt.DMA_BUS_ID-1:0]), .dout(fifo_mid[i][pt.DMA_BUS_ID-1:0]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);
         rvdffs  #(pt.DMA_BUS_PRTY) fifo_prty_dff(.din(bus_cmd_prty[pt.DMA_BUS_PRTY-1:0]), .dout(fifo_prty[i][pt.DMA_BUS_PRTY-1:0]), .en(fifo_cmd_en[i]), .clk(dma_buffer_c1_clk), .*);

逐段解释：

* 第 L267-L269 行：如果 entry 产生错误，``fifo_data_in`` 保存 ``{32'b0,fifo_addr[i]}``；
  否则优先采样 DCCM/ICCM read data，再退回 debug 写数据复制或 AXI 写数据。
* 第 L271-L276 行：valid、error、error_bus、rpend、done、done_bus 都带 clear 条件，
  clear 来源是 ``fifo_reset[i]``。
* 第 L277-L283 行：地址、size、byte enable、write、posted write、debug 和 data 分别
  落寄存器；其中 size、byte enable、write、posted write、debug 使用
  ``dma_buffer_c1_clk``，valid/error/done 类状态使用 ``dma_free_clk``。
* 第 L284-L286 行：tag/mid/priority 在 command 写入时保存。AXI response 的 id 来自
  ``fifo_tag``，因此 tag 是 AXI 请求与响应关联的关键字段。

接口关系：

* 被调用：AXI response、debug response、core request 都读取这些触发器输出。
* 调用：实例化 ``rvdffsc``、``rvdffs``、``rvdffe``。
* 共享状态：``fifo_data`` 既保存写数据，又保存读返回数据或错误地址。

§4.3  指针与 full/ready — 三指针环形队列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：维护写指针、读指针和响应指针，并根据 FIFO valid 项数计算 full 与 ready。
``dma_fifo_ready`` 同时受 FIFO full 和 debug bubble 同步信号限制。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L290-L313``）：

.. code-block:: systemverilog

      // Pointer logic
      assign NxtWrPtr[DEPTH_PTR-1:0] = (WrPtr[DEPTH_PTR-1:0] == (DEPTH-1)) ? '0 : WrPtr[DEPTH_PTR-1:0] + 1'b1;
      assign NxtRdPtr[DEPTH_PTR-1:0] = (RdPtr[DEPTH_PTR-1:0] == (DEPTH-1)) ? '0 : RdPtr[DEPTH_PTR-1:0] + 1'b1;
      assign NxtRspPtr[DEPTH_PTR-1:0] = (RspPtr[DEPTH_PTR-1:0] == (DEPTH-1)) ? '0 : RspPtr[DEPTH_PTR-1:0] + 1'b1;

      assign WrPtrEn = |fifo_cmd_en[DEPTH-1:0];
      assign RdPtrEn = dma_dccm_req | dma_iccm_req | (dma_address_error | dma_alignment_error | dma_dbg_cmd_error);
      assign RspPtrEn = (dma_dbg_cmd_done | (bus_rsp_sent | bus_posted_write_done) & dma_bus_clk_en);

      rvdffs #(DEPTH_PTR) WrPtr_dff(.din(NxtWrPtr[DEPTH_PTR-1:0]), .dout(WrPtr[DEPTH_PTR-1:0]), .en(WrPtrEn), .clk(dma_free_clk), .*);
      rvdffs #(DEPTH_PTR) RdPtr_dff(.din(NxtRdPtr[DEPTH_PTR-1:0]), .dout(RdPtr[DEPTH_PTR-1:0]), .en(RdPtrEn), .clk(dma_free_clk), .*);
      rvdffs #(DEPTH_PTR) RspPtr_dff(.din(NxtRspPtr[DEPTH_PTR-1:0]), .dout(RspPtr[DEPTH_PTR-1:0]), .en(RspPtrEn), .clk(dma_free_clk), .*);

      // Miscellaneous signals
      assign fifo_full = fifo_full_spec_bus;

      always_comb begin
         num_fifo_vld[3:0] = {3'b0,bus_cmd_sent} - {3'b0,bus_rsp_sent};
         for (int i=0; i<DEPTH; i++) begin
            num_fifo_vld[3:0] += {3'b0,fifo_valid[i]};
         end
      end
      assign fifo_full_spec          = (num_fifo_vld[3:0] >= DEPTH);

      assign dma_fifo_ready   = ~(fifo_full | dbg_dma_bubble_bus);

逐段解释：

* 第 L291-L293 行：三个 next pointer 都在达到 ``DEPTH-1`` 后回到 ``'0``，构成环形队列。
* 第 L295-L297 行：写指针随任一 ``fifo_cmd_en`` 前进；读指针在实际 DCCM/ICCM 请求
  或错误终止时前进；响应指针在 debug done 或 AXI/post response 消费时前进。
* 第 L299-L301 行：三个指针都在 ``dma_free_clk`` 域寄存。
* 第 L304-L310 行：``num_fifo_vld`` 从当前 valid 数量加上本周期 bus command sent，再减去
  bus response sent 得到 speculative 占用数。
* 第 L311-L313 行：``fifo_full_spec`` 达到 ``DEPTH`` 后置 full；``dma_fifo_ready`` 在 full
  或 ``dbg_dma_bubble_bus`` 为真时拉低。

接口关系：

* 被调用：bus command 发送、core request、AXI/debug response 都通过指针定位 entry。
* 调用：指针触发器和 full 组合计数。
* 共享状态：``fifo_full_spec`` 在第 L420 行同步到 bus clock 侧形成 ``fifo_full_spec_bus``。

§5  错误、debug 响应与 core request
------------------------------------

DMA 控制器把错误分成普通 AXI/DMA 地址错误、对齐错误和 debug 命令错误。普通
``dma_address_error`` 只允许 DCCM 或 ICCM 地址；debug 错误逻辑额外允许 PIC 地址，
但对 ICCM/PIC 要求 word size。

§5.1  普通 DMA 地址与对齐错误 — DCCM/ICCM 许可边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：判断非 debug FIFO entry 是否访问非法地址或违反 size/byte enable 对齐要求。
该段是旧文档中最容易漂移的地方：源码中的普通地址错误没有把 PIC 纳入合法集合。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L316-L324``）：

.. code-block:: systemverilog

      // Error logic
      assign dma_address_error = fifo_valid[RdPtr] & ~fifo_done[RdPtr] & ~fifo_dbg[RdPtr] & (~(dma_mem_addr_in_dccm | dma_mem_addr_in_iccm));    // request not for ICCM or DCCM
      assign dma_alignment_error = fifo_valid[RdPtr] & ~fifo_done[RdPtr] & ~fifo_dbg[RdPtr] & ~dma_address_error &
                                   (((dma_mem_sz_int[2:0] == 3'h1) & dma_mem_addr_int[0])                                                       |    // HW size but unaligned
                                    ((dma_mem_sz_int[2:0] == 3'h2) & (|dma_mem_addr_int[1:0]))                                                  |    // W size but unaligned
                                    ((dma_mem_sz_int[2:0] == 3'h3) & (|dma_mem_addr_int[2:0]))                                                  |    // DW size but unaligned
                                    (dma_mem_addr_in_iccm & ~((dma_mem_sz_int[1:0] == 2'b10) | (dma_mem_sz_int[1:0] == 2'b11)))                 |    // ICCM access not word size
                                    (dma_mem_addr_in_dccm & dma_mem_write & ~((dma_mem_sz_int[1:0] == 2'b10) | (dma_mem_sz_int[1:0] == 2'b11))) |    // DCCM write not word size
                                    (dma_mem_write & (dma_mem_sz_int[2:0] == 3'h2) & (dma_mem_byteen[dma_mem_addr_int[2:0]+:4] != 4'hf))        |    // Write byte enables not aligned for word store
                                    (dma_mem_write & (dma_mem_sz_int[2:0] == 3'h3) & ~((dma_mem_byteen[7:0] == 8'h0f) | (dma_mem_byteen[7:0] == 8'hf0) | (dma_mem_byteen[7:0] == 8'hff)))); // Write byte enables not aligned for dword store

逐段解释：

* 第 L316 行：普通 DMA 地址错误只在 FIFO entry 有效、未 done、非 debug 时检查；合法地址集合是
  ``dma_mem_addr_in_dccm | dma_mem_addr_in_iccm``。因此不能把普通 AXI DMA 请求描述为
  无条件可访问 PIC。
* 第 L317 行：对齐错误要求当前 entry 有效、未 done、非 debug，并且没有地址错误；
  也就是说地址错误优先于 alignment 判断。
* 第 L318-L320 行：size 为 halfword、word、doubleword 时分别检查地址 bit 0、
  bit [1:0]、bit [2:0]。
* 第 L321-L322 行：ICCM 访问必须是 word 或 doubleword size；DCCM 写访问也必须是
  word 或 doubleword size。
* 第 L323-L324 行：word write 要求对应 4-bit byte enable 为 ``4'hf``；doubleword write
  允许低半、上半或全部 8 byte enable，即 ``8'h0f``、``8'hf0``、``8'hff``。

接口关系：

* 被调用：``fifo_error_en``、``fifo_done_en``、``RdPtrEn``、``dma_mem_req`` 都读取这些错误信号。
* 调用：读取 ``fifo_valid``、``fifo_done``、``fifo_dbg``、地址范围、size、address、byte enable。
* 共享状态：错误 entry 的 ``fifo_data`` 会保存 ``{32'b0,fifo_addr[i]}``。

§5.2  Debug 输出与 debug 命令错误 — PIC 只在 debug 错误逻辑中被许可
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 debug ready、done、fail、读数据和 debug 命令错误。debug 路径可以访问
DCCM、ICCM 或 PIC 地址范围，但 ICCM/PIC 只允许 word size。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L327-L344``）：

.. code-block:: systemverilog

      assign dma_dbg_ready    = fifo_empty & dbg_dma_bubble;
      assign dma_dbg_cmd_done = (fifo_valid[RspPtr] & fifo_dbg[RspPtr] & fifo_done[RspPtr]);
      assign dma_dbg_cmd_fail     = (|fifo_error[RspPtr] & dma_dbg_cmd_done);

      assign dma_dbg_sz[1:0]          = fifo_sz[RspPtr][1:0];
      assign dma_dbg_addr[1:0]        = fifo_addr[RspPtr][1:0];
      assign dma_dbg_mem_rddata[31:0] = fifo_addr[RspPtr][2] ? fifo_data[RspPtr][63:32] : fifo_data[RspPtr][31:0];
      assign dma_dbg_rddata[31:0]     = ({32{(dma_dbg_sz[1:0] == 2'h0)}} & ((dma_dbg_mem_rddata[31:0] >> 8*dma_dbg_addr[1:0]) & 32'hff)) |
                                        ({32{(dma_dbg_sz[1:0] == 2'h1)}} & ((dma_dbg_mem_rddata[31:0] >> 16*dma_dbg_addr[1]) & 32'hffff)) |
                                        ({32{(dma_dbg_sz[1:0] == 2'h2)}} & dma_dbg_mem_rddata[31:0]);

      assign dma_dbg_cmd_error = fifo_valid[RdPtr] & ~fifo_done[RdPtr] & fifo_dbg[RdPtr] &
                                    ((~(dma_mem_addr_in_dccm | dma_mem_addr_in_iccm | dma_mem_addr_in_pic)) |             // Address outside of ICCM/DCCM/PIC
                                     ((dma_mem_addr_in_iccm | dma_mem_addr_in_pic) & (dma_mem_sz_int[1:0] != 2'b10)));    // Only word accesses allowed for ICCM/PIC

      assign dma_dbg_mem_wrdata[31:0] = ({32{dbg_cmd_size[1:0] == 2'h0}} & {4{dbg_cmd_wrdata[7:0]}}) |

逐段解释：

* 第 L327 行：debug ready 需要 FIFO 为空且 debug 侧给出 ``dbg_dma_bubble``。
  ``fifo_empty`` 在第 L351 行由 FIFO valid 和 ``bus_cmd_sent`` 共同决定。
* 第 L328-L329 行：debug done 要求响应指针 entry 有效、标记为 debug 且 done；fail 是
  同一 entry 有任意 error bit。
* 第 L331-L336 行：debug 读数据先根据地址 bit 2 选取 FIFO 64-bit data 的低/高 32-bit，
  再根据 size 和低地址 bit 抽取 byte、halfword 或 word。
* 第 L338-L340 行：debug 命令错误要求当前读指针 entry 是 debug entry。地址合法集合为
  DCCM、ICCM 或 PIC；若地址在 ICCM 或 PIC，size 必须等于 ``2'b10``。
* 第 L342-L344 行：debug 写数据按 byte、halfword 或 word 复制成 32-bit，后续第 L269 行再
  复制成 64-bit 存入 FIFO data。

接口关系：

* 被调用：debug 控制器观察 ``dma_dbg_ready``、``dma_dbg_cmd_done``、
  ``dma_dbg_cmd_fail``、``dma_dbg_rddata``。
* 调用：读取 ``fifo_empty``、``RspPtr``、``RdPtr``、FIFO data/error/size/address 和地址范围。
* 共享状态：``dma_dbg_cmd_error`` 参与 FIFO error、done 和读指针前进。

§5.3  Stall、nack 与 core request — ready 和 QoS 共同决定发起
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 FIFO 读端生成 DCCM/ICCM 请求、stall 信号、nack 计数和 PMU 事件。请求必须先通过
地址/对齐/debug 错误过滤，再由 DCCM/ICCM ready 允许发出。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L347-L379``）：

.. code-block:: systemverilog

      // Block the decode if fifo full
      assign dma_dccm_stall_any = dma_mem_req_spec & (dma_mem_addr_in_dccm | dma_mem_addr_in_pic) & (dma_nack_count >= dma_nack_count_csr) & ~dccm_ready;
      assign dma_iccm_stall_any = dma_mem_req_spec & dma_mem_addr_in_iccm & (dma_nack_count >= dma_nack_count_csr);

      // Used to indicate ready to debug
      assign fifo_empty     = ~((|fifo_valid[DEPTH-1:0]) | bus_cmd_sent);

      // Nack counter, stall the lsu pipe if 7 nacks
      assign dma_nack_count_csr[2:0] = dec_tlu_dma_qos_prty[2:0];
      assign dma_nack_count_d[2:0] = (dma_nack_count[2:0] >= dma_nack_count_csr[2:0]) ? ({3{~(dma_dccm_req | dma_iccm_req)}} & dma_nack_count[2:0]) :
                                                                                       (dma_mem_req & ~(dma_dccm_req | dma_iccm_req)) ? (dma_nack_count[2:0] + 1'b1) : 3'b0;

      rvdffs #(3) nack_count_dff(.din(dma_nack_count_d[2:0]), .dout(dma_nack_count[2:0]), .en(dma_mem_req), .clk(dma_free_clk), .*);

      // Core outputs
      assign dma_mem_req_spec     = fifo_valid[RdPtr] & ~fifo_rpend[RdPtr] & ~fifo_done[RdPtr];
      assign dma_mem_req         = dma_mem_req_spec & ~(dma_address_error | dma_alignment_error | dma_dbg_cmd_error);
      assign dma_dccm_req        = dma_mem_req & (dma_mem_addr_in_dccm | dma_mem_addr_in_pic) & dccm_ready;
      assign dma_dccm_spec_req   = dma_mem_req_spec & ~dma_mem_addr_in_iccm & dccm_ready;   // dma_mem_addr_in_iccm=0 for eh2_plus1 when ICCM doesn't exist
      assign dma_iccm_req        = dma_mem_req & dma_mem_addr_in_iccm & iccm_ready;
      assign dma_mem_tag[2:0]    = 3'(RdPtr);
      assign dma_mem_addr_int[31:0] = fifo_addr[RdPtr];
      assign dma_mem_sz_int[2:0] = fifo_sz[RdPtr];
      assign dma_mem_addr[31:0]  = (dma_mem_write & ~fifo_dbg[RdPtr] & (dma_mem_byteen[7:0] == 8'hf0)) ? {dma_mem_addr_int[31:3],1'b1,dma_mem_addr_int[1:0]} : dma_mem_addr_int[31:0];
      assign dma_mem_sz[2:0]     = (dma_mem_write & ~fifo_dbg[RdPtr] & ((dma_mem_byteen[7:0] == 8'h0f) | (dma_mem_byteen[7:0] == 8'hf0))) ? 3'h2 : dma_mem_sz_int[2:0];
      assign dma_mem_byteen[7:0] = fifo_byteen[RdPtr];
      assign dma_mem_write       = fifo_write[RdPtr];
      assign dma_mem_wdata[63:0] = fifo_data[RdPtr];

      // PMU outputs
      assign dma_pmu_dccm_read   = dma_dccm_req & ~dma_mem_write;
      assign dma_pmu_dccm_write  = dma_dccm_req & dma_mem_write;
      assign dma_pmu_any_read    = (dma_dccm_req | dma_iccm_req) & ~dma_mem_write;
      assign dma_pmu_any_write   = (dma_dccm_req | dma_iccm_req) & dma_mem_write;

逐段解释：

* 第 L347-L348 行：stall 信号基于 speculative request、地址范围、nack 计数阈值和 ready。
  DCCM stall 条件把 PIC 地址也归入 ``dma_dccm_stall_any`` 的地址集合。
* 第 L351 行：FIFO empty 只有在没有任何 valid entry 且本周期没有 bus command sent 时为真。
* 第 L354-L358 行：nack 阈值来自 ``dec_tlu_dma_qos_prty``；当 request 未被 DCCM/ICCM 接收时
  计数递增，发出请求或条件不满足时清零或保持。
* 第 L361-L362 行：``dma_mem_req_spec`` 表示当前读指针 entry 可尝试发起；
  ``dma_mem_req`` 再滤除地址错误、对齐错误和 debug 命令错误。
* 第 L363-L365 行：DCCM 请求条件包含 DCCM 或 PIC 地址并要求 ``dccm_ready``；
  ICCM 请求条件要求 ICCM 地址并要求 ``iccm_ready``。这与第 L316 行的普通地址错误共同作用：
  普通非 debug PIC 请求会先命中地址错误，不会成为 ``dma_mem_req``。
* 第 L366-L373 行：输出 tag 直接等于 ``RdPtr``；当非 debug 写且 byte enable 为 ``8'hf0`` 时，
  输出地址 bit 2 被置 1；当 byte enable 为 ``8'h0f`` 或 ``8'hf0`` 时，输出 size 改为
  ``3'h2``。
* 第 L376-L379 行：PMU read/write 事件由实际 DCCM/ICCM 请求和 ``dma_mem_write`` 组合生成。

接口关系：

* 被调用：DCCM/ICCM 访问路径、stall 控制和 PMU 事件观察这些输出。
* 调用：读取 FIFO 当前读指针 entry、ready、地址范围、错误状态和 QoS priority。
* 共享状态：``dma_mem_req`` 使能 nack counter，也参与 ``RdPtrEn`` 与 FIFO done 逻辑。

§6  地址范围检查
----------------

地址范围检查使用 ``rvrangecheck``。DCCM 和 ICCM range check 受参数使能保护；PIC range check
总是实例化。``*_region_nc`` 信号在本文件中只作为 range check 输出接线存在，没有被后续逻辑读取。

§6.1  DCCM 与 ICCM range check — 参数化可关闭
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 ``pt.DCCM_ENABLE`` 和 ``pt.ICCM_ENABLE`` 决定是否实例化 DCCM/ICCM
``rvrangecheck``，关闭时把 in-range 输出固定为 0。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L381-L407``）：

.. code-block:: systemverilog

      // Address check  dccm
      if (pt.DCCM_ENABLE) begin
         rvrangecheck #(.CCM_SADR(pt.DCCM_SADR),
                        .CCM_SIZE(pt.DCCM_SIZE)) addr_dccm_rangecheck (
            .addr(dma_mem_addr[31:0]),
            .in_range(dma_mem_addr_in_dccm),
            .in_region(dma_mem_addr_in_dccm_region_nc)
         );
      end
      else begin
         assign dma_mem_addr_in_dccm = 1'b0;
         assign dma_mem_addr_in_dccm_region_nc = 1'b0;
      end // else: !if(pt.DCCM_ENABLE)

      // Address check  iccm
      if (pt.ICCM_ENABLE) begin
         rvrangecheck #(.CCM_SADR(pt.ICCM_SADR),
                        .CCM_SIZE(pt.ICCM_SIZE)) addr_iccm_rangecheck (
            .addr(dma_mem_addr[31:0]),
            .in_range(dma_mem_addr_in_iccm),
            .in_region(dma_mem_addr_in_iccm_region_nc)
         );
      end
      else  begin
         assign dma_mem_addr_in_iccm = '0;
         assign dma_mem_addr_in_iccm_region_nc = '0;
      end // else: !if(pt.ICCM_ENABLE)

逐段解释：

* 第 L382-L389 行：DCCM 使能时，``rvrangecheck`` 使用 ``pt.DCCM_SADR`` 和
  ``pt.DCCM_SIZE`` 判断 ``dma_mem_addr`` 是否在 DCCM 范围内。
* 第 L390-L393 行：DCCM 关闭时，``dma_mem_addr_in_dccm`` 和 region 输出都固定为 0。
* 第 L396-L403 行：ICCM 使能时，``rvrangecheck`` 使用 ``pt.ICCM_SADR`` 和
  ``pt.ICCM_SIZE`` 判断 ``dma_mem_addr`` 是否在 ICCM 范围内。
* 第 L404-L407 行：ICCM 关闭时，``dma_mem_addr_in_iccm`` 和 region 输出都固定为 0。

接口关系：

* 被调用：地址错误、debug 错误、stall、core request 逻辑读取 in-range 输出。
* 调用：实例化 ``rvrangecheck``。
* 共享状态：``dma_mem_addr`` 是 range check 的输入，而 ``dma_mem_addr`` 又由 FIFO 当前
  entry 和 byte enable 调整逻辑生成。

§6.2  PIC range check — 供 debug 错误和 DCCM request 条件读取
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 PIC 地址生成 ``dma_mem_addr_in_pic``。当前源码中，PIC range check 输出被 debug
命令错误逻辑、DCCM stall 条件和 DCCM request 条件读取；普通 DMA 地址错误没有把 PIC 作为
合法地址集合。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L410-L416``）：

.. code-block:: systemverilog

      // PIC memory address check
      rvrangecheck #(.CCM_SADR(pt.PIC_BASE_ADDR),
                     .CCM_SIZE(pt.PIC_SIZE)) addr_pic_rangecheck (
         .addr(dma_mem_addr[31:0]),
         .in_range(dma_mem_addr_in_pic),
         .in_region(dma_mem_addr_in_pic_region_nc)
       );

逐段解释：

* 第 L411-L412 行：PIC range check 使用 ``pt.PIC_BASE_ADDR`` 和 ``pt.PIC_SIZE``。
* 第 L413-L415 行：输入地址同样是 ``dma_mem_addr``，输出 ``dma_mem_addr_in_pic`` 和
  ``dma_mem_addr_in_pic_region_nc``。
* 结合第 L316、L338-L340 和 L363 行可见：普通非 debug 地址合法性只看 DCCM/ICCM；
  debug 命令错误允许 PIC；DCCM request 表达式包含 PIC，但前提是 ``dma_mem_req`` 没有被
  普通地址错误过滤掉。

接口关系：

* 被调用：debug 错误、DCCM stall 和 DCCM request 逻辑读取 ``dma_mem_addr_in_pic``。
* 调用：实例化 ``rvrangecheck``。
* 共享状态：``dma_mem_addr_in_pic_region_nc`` 在本文件中没有后续读取点。

§7  时钟门控与跨 bus clock 同步
-------------------------------

DMA 控制器使用 ``dma_free_clk`` 保存 FIFO 生命周期状态，用 ``dma_buffer_c1_clk`` 保存
部分 FIFO 数据面字段，并用 ``dma_bus_clk`` 服务 AXI bus 侧缓冲和同步。源码通过
``rvdff_fpga`` 把 ``fifo_full_spec`` 和 ``dbg_dma_bubble`` 同步到 bus clock 侧。

§7.1  Full/bubble 同步与 gated clock 生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 full/bubble 状态同步到 bus clock 侧，并按活动条件生成 DMA 内部 gated clocks。
``RV_FPGA_OPTIMIZE`` 下 ``dma_bus_clk`` 被常量 0 替代；否则由 ``rvclkhdr`` 生成。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L420-L435``）：

.. code-block:: systemverilog

      rvdff_fpga #(1) fifo_full_bus_ff     (.din(fifo_full_spec),    .dout(fifo_full_spec_bus),     .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdff_fpga #(1) dbg_dma_bubble_ff    (.din(dbg_dma_bubble),    .dout(dbg_dma_bubble_bus),     .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdff      #(1) dma_dbg_cmd_doneff   (.din(dma_dbg_cmd_done),  .dout(dma_dbg_cmd_done_q),     .clk(free_clk), .*);

      // Clock Gating logic
      assign dma_buffer_c1_clken = (bus_cmd_valid & dma_bus_clk_en) | dbg_mem_cmd_valid | clk_override;
      assign dma_free_clken = (bus_cmd_valid | bus_rsp_valid | dbg_mem_cmd_valid | dma_dbg_cmd_done | dma_dbg_cmd_done_q | (|fifo_valid[DEPTH-1:0]) | clk_override);

      rvoclkhdr dma_buffer_c1cgc ( .en(dma_buffer_c1_clken), .l1clk(dma_buffer_c1_clk), .* );
      rvoclkhdr dma_free_cgc (.en(dma_free_clken), .l1clk(dma_free_clk), .*);

   `ifdef RV_FPGA_OPTIMIZE
      assign dma_bus_clk = 1'b0;
   `else
      rvclkhdr  dma_bus_cgc (.en(dma_bus_clk_en), .l1clk(dma_bus_clk), .*);
   `endif

逐段解释：

* 第 L420-L421 行：``fifo_full_spec`` 和 ``dbg_dma_bubble`` 通过 ``rvdff_fpga`` 进入
  bus clock 侧，输出分别为 ``fifo_full_spec_bus`` 和 ``dbg_dma_bubble_bus``。
* 第 L422 行：``dma_dbg_cmd_done`` 在 ``free_clk`` 上打一拍，形成
  ``dma_dbg_cmd_done_q``，随后参与 ``dma_free_clken``。
* 第 L425-L426 行：``dma_buffer_c1_clken`` 在 bus command、debug memory command 或
  clock override 时使能；``dma_free_clken`` 还包含 bus response、debug done、
  debug done 延迟项和任意 FIFO valid。
* 第 L428-L429 行：``rvoclkhdr`` 生成 ``dma_buffer_c1_clk`` 与 ``dma_free_clk``。
* 第 L431-L435 行：FPGA 优化宏打开时 ``dma_bus_clk`` 赋 0；否则用 ``rvclkhdr`` 按
  ``dma_bus_clk_en`` 生成。

接口关系：

* 被调用：FIFO 字段触发器、指针触发器、AXI 缓冲触发器使用这些 clock。
* 调用：实例化 ``rvdff_fpga``、``rvdff``、``rvoclkhdr``、``rvclkhdr``。
* 共享状态：``clk_override`` 可直接保持内部 clock enable 有效。

§8  AXI 写读缓冲与 bus command 仲裁
-----------------------------------

AXI 输入先进入单 entry 写缓冲和读缓冲。写请求只有在 AW 和 W 两边都有效时才成为
``bus_cmd_valid`` 的写分支；读请求只需要 ``rdbuf_vld``。当读写同时存在时，
``axi_mstr_priority`` 在每次 ``bus_cmd_sent`` 后翻转，用于交替优先级。

§8.1  写缓冲与读缓冲 — AW/W/AR 独立握手保存
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：保存 AXI AW、W、AR 通道字段，并在对应 bus command 发送后清理缓冲有效位。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L437-L460``）：

.. code-block:: systemverilog

      // Write channel buffer
      assign wrbuf_en       = dma_axi_awvalid & dma_axi_awready;
      assign wrbuf_data_en  = dma_axi_wvalid & dma_axi_wready;
      assign wrbuf_cmd_sent = bus_cmd_sent & bus_cmd_write;
      assign wrbuf_rst      = wrbuf_cmd_sent & ~wrbuf_en;
      assign wrbuf_data_rst = wrbuf_cmd_sent & ~wrbuf_data_en;

      rvdffsc_fpga  #(.WIDTH(1))              wrbuf_vldff       (.din(1'b1), .dout(wrbuf_vld),      .en(wrbuf_en),      .clear(wrbuf_rst),      .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffsc_fpga  #(.WIDTH(1))              wrbuf_data_vldff  (.din(1'b1), .dout(wrbuf_data_vld), .en(wrbuf_data_en), .clear(wrbuf_data_rst), .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga   #(.WIDTH(pt.DMA_BUS_TAG)) wrbuf_tagff       (.din(dma_axi_awid[pt.DMA_BUS_TAG-1:0]), .dout(wrbuf_tag[pt.DMA_BUS_TAG-1:0]), .en(wrbuf_en), .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga   #(.WIDTH(3))              wrbuf_szff        (.din(dma_axi_awsize[2:0]),  .dout(wrbuf_sz[2:0]),     .en(wrbuf_en),                  .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffe        #(.WIDTH(32))             wrbuf_addrff      (.din(dma_axi_awaddr[31:0]), .dout(wrbuf_addr[31:0]),  .en(wrbuf_en & dma_bus_clk_en), .*);
      rvdffe        #(.WIDTH(64))             wrbuf_dataff      (.din(dma_axi_wdata[63:0]),  .dout(wrbuf_data[63:0]),  .en(wrbuf_data_en & dma_bus_clk_en), .*);
      rvdffs_fpga   #(.WIDTH(8))              wrbuf_byteenff    (.din(dma_axi_wstrb[7:0]),   .dout(wrbuf_byteen[7:0]), .en(wrbuf_data_en),             .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);

      // Read channel buffer
      assign rdbuf_en    = dma_axi_arvalid & dma_axi_arready;
      assign rdbuf_cmd_sent = bus_cmd_sent & ~bus_cmd_write;
      assign rdbuf_rst   = rdbuf_cmd_sent & ~rdbuf_en;

逐段解释：

* 第 L438-L442 行：写地址缓冲由 AW handshake 置位，写数据缓冲由 W handshake 置位；
  写 command 发送后，如果同周期没有新 AW/W handshake，则清理相应 valid。
* 第 L444-L450 行：写缓冲保存 AW id、size、address 以及 W data、strobe。
  ``wrbuf_addr`` 和 ``wrbuf_data`` 使用 ``rvdffe``，写入条件还要求 ``dma_bus_clk_en``。
* 第 L453-L455 行：读缓冲由 AR handshake 置位，读 command 发送且没有新 AR handshake 时清理。

接口关系：

* 被调用：bus command 选择逻辑读取 ``wrbuf_*`` 和 ``rdbuf_*``。
* 调用：AXI valid/ready handshake 驱动缓冲触发器。
* 共享状态：``wrbuf_vld``、``wrbuf_data_vld``、``rdbuf_vld`` 同时参与 ready 与
  ``dma_active``。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L457-L464``）：

.. code-block:: systemverilog

      rvdffsc_fpga  #(.WIDTH(1))              rdbuf_vldff  (.din(1'b1), .dout(rdbuf_vld), .en(rdbuf_en), .clear(rdbuf_rst), .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga   #(.WIDTH(pt.DMA_BUS_TAG)) rdbuf_tagff  (.din(dma_axi_arid[pt.DMA_BUS_TAG-1:0]), .dout(rdbuf_tag[pt.DMA_BUS_TAG-1:0]), .en(rdbuf_en), .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga   #(.WIDTH(3))              rdbuf_szff   (.din(dma_axi_arsize[2:0]),  .dout(rdbuf_sz[2:0]),    .en(rdbuf_en), .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);
      rvdffe       #(.WIDTH(32))              rdbuf_addrff (.din(dma_axi_araddr[31:0]), .dout(rdbuf_addr[31:0]), .en(rdbuf_en & dma_bus_clk_en), .*);

      assign dma_axi_awready = ~(wrbuf_vld & ~wrbuf_cmd_sent);
      assign dma_axi_wready  = ~(wrbuf_data_vld & ~wrbuf_cmd_sent);
      assign dma_axi_arready = ~(rdbuf_vld & ~rdbuf_cmd_sent);

逐段解释：

* 第 L457-L460 行：读缓冲保存 AR valid、id、size 和 address。
* 第 L462-L464 行：AXI ready 由缓冲占用状态决定。只要缓冲 valid 且本周期没有对应
  command sent，ready 就拉低；如果 command sent，ready 可重新接受新请求。

接口关系：

* 被调用：外部 AXI master 观察 ready；内部 bus command 读取读缓冲字段。
* 调用：读取 ``rdbuf_cmd_sent``、``wrbuf_cmd_sent`` 和缓冲 valid。
* 共享状态：ready 稳定性由第 L515-L583 行断言在 ``RV_ASSERT_ON`` 下检查。

§8.2  Bus command 合并与读写优先级 — ``axi_mstr_priority`` 翻转
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把写缓冲和读缓冲合并成单个 ``bus_cmd_*``，并在读写同时存在时用优先级 bit 选择。
源码注释说明 ``Sel=1`` 表示写优先。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L466-L483``）：

.. code-block:: systemverilog

      //Generate a single request from read/write channel
      assign bus_cmd_valid                     = (wrbuf_vld & wrbuf_data_vld) | rdbuf_vld;
      assign bus_cmd_sent                      = bus_cmd_valid & dma_fifo_ready;
      assign bus_cmd_write                     = axi_mstr_sel;
      assign bus_cmd_posted_write              = '0;
      assign bus_cmd_addr[31:0]                = axi_mstr_sel ? wrbuf_addr[31:0] : rdbuf_addr[31:0];
      assign bus_cmd_sz[2:0]                   = axi_mstr_sel ? wrbuf_sz[2:0] : rdbuf_sz[2:0];
      assign bus_cmd_wdata[63:0]               = wrbuf_data[63:0];
      assign bus_cmd_byteen[7:0]               = wrbuf_byteen[7:0];
      assign bus_cmd_tag[pt.DMA_BUS_TAG-1:0]   = axi_mstr_sel ? wrbuf_tag[pt.DMA_BUS_TAG-1:0] : rdbuf_tag[pt.DMA_BUS_TAG-1:0];
      assign bus_cmd_mid[pt.DMA_BUS_ID-1:0]    = '0;
      assign bus_cmd_prty[pt.DMA_BUS_PRTY-1:0] = '0;

      // Sel=1 -> write has higher priority
      assign axi_mstr_sel     = (wrbuf_vld & wrbuf_data_vld & rdbuf_vld) ? axi_mstr_priority : (wrbuf_vld & wrbuf_data_vld);
      assign axi_mstr_prty_in = ~axi_mstr_priority;
      assign axi_mstr_prty_en = bus_cmd_sent;
      rvdffs_fpga #(.WIDTH(1)) mstr_prtyff(.din(axi_mstr_prty_in), .dout(axi_mstr_priority), .en(axi_mstr_prty_en), .clk(dma_bus_clk), .clken(dma_bus_clk_en), .rawclk(clk), .*);

逐段解释：

* 第 L467-L468 行：写 command 要求 AW 和 W 缓冲都 valid；读 command 要求 AR 缓冲 valid。
  只有 ``dma_fifo_ready`` 为真时，bus command 才被认为 sent。
* 第 L469-L475 行：``axi_mstr_sel`` 选择写或读字段。写数据和 byte enable 始终来自写缓冲，
  但只有写 command 会使用这些字段。
* 第 L476-L477 行：``bus_cmd_mid`` 和 ``bus_cmd_prty`` 在当前实现中固定为 0。
* 第 L480-L483 行：当读写同时存在时，``axi_mstr_priority`` 决定选择；每次
  ``bus_cmd_sent`` 后，``mstr_prtyff`` 把优先级翻转。

接口关系：

* 被调用：FIFO 输入 mux 读取 ``bus_cmd_*``。
* 调用：读取写缓冲、读缓冲、``dma_fifo_ready`` 和优先级触发器。
* 共享状态：``bus_cmd_sent`` 影响 FIFO 写入、full speculative 计数、empty 判断和 clock enable。

§9  AXI 响应与 active 输出
--------------------------

响应路径只处理非 debug FIFO entry。``axi_rsp_valid`` 要求响应指针 entry valid、不是 debug、
且 ``fifo_done_bus`` 为真。写 entry 产生 B channel，读 entry 产生 R channel。

§9.1  FIFO response 到 AXI B/R — 错误位映射响应码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 ``RspPtr`` 指向的 FIFO entry 转成 AXI 写响应或读响应，并在 response 被 ready
接收后推进响应指针。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L485-L506``）：

.. code-block:: systemverilog

      assign axi_rsp_valid                   = fifo_valid[RspPtr] & ~fifo_dbg[RspPtr] & fifo_done_bus[RspPtr];
      assign axi_rsp_rdata[63:0]             = fifo_data[RspPtr];
      assign axi_rsp_write                   = fifo_write[RspPtr];
      assign axi_rsp_posted_write            = axi_rsp_write & fifo_posted_write[RspPtr];
      assign axi_rsp_error[1:0]              = fifo_error[RspPtr][0] ? 2'b10 : (fifo_error[RspPtr][1] ? 2'b11 : 2'b0);
      assign axi_rsp_tag[pt.DMA_BUS_TAG-1:0] = fifo_tag[RspPtr];

      // AXI response channel signals
      assign dma_axi_bvalid                  = axi_rsp_valid & axi_rsp_write;
      assign dma_axi_bresp[1:0]              = axi_rsp_error[1:0];
      assign dma_axi_bid[pt.DMA_BUS_TAG-1:0] = axi_rsp_tag[pt.DMA_BUS_TAG-1:0];

      assign dma_axi_rvalid                  = axi_rsp_valid & ~axi_rsp_write;
      assign dma_axi_rresp[1:0]              = axi_rsp_error;
      assign dma_axi_rdata[63:0]             = axi_rsp_rdata[63:0];
      assign dma_axi_rlast                   = 1'b1;
      assign dma_axi_rid[pt.DMA_BUS_TAG-1:0] = axi_rsp_tag[pt.DMA_BUS_TAG-1:0];

      assign bus_posted_write_done = 1'b0;
      assign bus_rsp_valid      = (dma_axi_bvalid | dma_axi_rvalid);
      assign bus_rsp_sent       = (dma_axi_bvalid & dma_axi_bready) | (dma_axi_rvalid & dma_axi_rready);
      assign dma_active  = wrbuf_vld | rdbuf_vld | (|fifo_valid[DEPTH-1:0]);

逐段解释：

* 第 L485-L490 行：AXI response 从 ``RspPtr`` entry 取 data、write 标志、posted write、
  error 和 tag。debug entry 被 ``~fifo_dbg[RspPtr]`` 排除。
* 第 L489 行：``fifo_error[0]`` 映射为 ``2'b10``，否则 ``fifo_error[1]`` 映射为 ``2'b11``，
  无错误为 ``2'b0``。
* 第 L493-L495 行：写 response 使用 ``dma_axi_bvalid``、``dma_axi_bresp`` 和
  ``dma_axi_bid``。
* 第 L497-L501 行：读 response 使用 ``dma_axi_rvalid``、``dma_axi_rresp``、
  ``dma_axi_rdata``、``dma_axi_rlast`` 和 ``dma_axi_rid``；``dma_axi_rlast`` 固定为 1。
* 第 L503-L505 行：posted write done 在当前实现中固定为 0；response sent 由 B 或 R
  channel valid/ready handshake 决定。
* 第 L506 行：``dma_active`` 只看写缓冲 valid、读缓冲 valid 或任意 FIFO valid。

接口关系：

* 被调用：外部 AXI master 观察 B/R channel；顶层观察 ``dma_active``。
* 调用：读取 ``RspPtr`` entry、AXI ready 和缓冲/FIFO valid。
* 共享状态：``bus_rsp_sent`` 清理 FIFO entry 并推进 ``RspPtr``。

§10  断言覆盖的稳定性约束
-------------------------

``RV_ASSERT_ON`` 打开时，源码检查 FIFO done/valid 关系，以及多个 AXI ready/valid/id/resp/data
信号在 bus clock enable 边界上的稳定性。断言中的 implication 都以 ``$past(dma_bus_clk_en)``
作为变化许可条件。

§10.1  FIFO done 必须伴随 valid
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：防止 FIFO entry 出现 done 置位但 valid 未置位的组合状态。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L509-L513``）：

.. code-block:: systemverilog

   `ifdef RV_ASSERT_ON

      for (genvar i=0; i<DEPTH; i++) begin
         assert_fifo_done_and_novalid: assert #0 (~fifo_done[i] | fifo_valid[i]);
      end

逐段解释：

* 第 L509 行：这些断言只在 ``RV_ASSERT_ON`` 宏打开时编译。
* 第 L511-L513 行：对每个 FIFO entry 检查 ``~fifo_done[i] | fifo_valid[i]``，即
  ``fifo_done`` 为真时 ``fifo_valid`` 也必须为真。

接口关系：

* 被调用：仿真或形式环境在宏打开时启用该 assertion。
* 调用：读取 ``fifo_done`` 和 ``fifo_valid``。
* 共享状态：断言不改变 RTL 状态，只约束 FIFO 生命周期关系。

§10.2  AXI ready/valid 稳定性 — 变化必须对齐 bus clock enable
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 ``dma_axi_awready``、``dma_axi_wready``、``dma_axi_arready``、``dma_axi_bvalid``、
``dma_axi_rvalid`` 等信号的变化只能发生在上一拍 ``dma_bus_clk_en`` 为真之后。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L515-L541``）：

.. code-block:: systemverilog

        // Assertion to check awready stays stable during entire bus clock
       property dma_axi_awready_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_awready != $past(dma_axi_awready)) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_awready_stable: assert property (dma_axi_awready_stable) else
           $display("DMA AXI awready changed in middle of bus clock");

        // Assertion to check wready stays stable during entire bus clock
       property dma_axi_wready_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_wready != $past(dma_axi_wready)) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_wready_stable: assert property (dma_axi_wready_stable) else
           $display("DMA AXI wready changed in middle of bus clock");

        // Assertion to check arready stays stable during entire bus clock
       property dma_axi_arready_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_arready != $past(dma_axi_arready)) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_arready_stable: assert property (dma_axi_arready_stable) else
           $display("DMA AXI arready changed in middle of bus clock");

        // Assertion to check bvalid stays stable during entire bus clock
       property dma_axi_bvalid_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_bvalid != $past(dma_axi_bvalid)) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_bvalid_stable: assert property (dma_axi_bvalid_stable) else
           $display("DMA AXI bvalid changed in middle of bus clock");

逐段解释：

* 第 L516-L520 行：``dma_axi_awready`` 若相对上一拍发生变化，则上一拍必须有
  ``dma_bus_clk_en``。
* 第 L523-L527 行：``dma_axi_wready`` 使用同样的稳定性约束。
* 第 L530-L534 行：``dma_axi_arready`` 使用同样的稳定性约束。
* 第 L537-L541 行：``dma_axi_bvalid`` 使用同样的稳定性约束。
* 这些断言解释了为什么写缓冲、读缓冲和 response 逻辑大量使用 ``dma_bus_clk``、
  ``dma_bus_clk_en`` 和 ``rvdff_fpga``。

接口关系：

* 被调用：宏打开时由 assertion checker 采样。
* 调用：读取 AXI ready/valid、``clk``、``rst_l`` 和 ``dma_bus_clk_en``。
* 共享状态：断言不会驱动 AXI 信号，只检查 bus clock enable 边界。

§10.3  AXI id/resp/data 稳定性 — valid 期间 payload 不能中途变化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 B/R payload 在 valid 期间的稳定性，包括 ``bid``、``bresp``、``rid``、
``rresp`` 和 ``rdata``。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L543-L583``）：

.. code-block:: systemverilog

        // Assertion to check bid stays stable during entire bus clock
        property dma_axi_bid_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_bvalid & (dma_axi_bid[pt.DMA_BUS_TAG-1:0] != $past(dma_axi_bid[pt.DMA_BUS_TAG-1:0]))) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_bid_stable: assert property (dma_axi_bid_stable) else
           $display("DMA AXI bid changed in middle of bus clock");

        // Assertion to check bresp stays stable during entire bus clock
        property dma_axi_bresp_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_bvalid & (dma_axi_bresp[1:0] != $past(dma_axi_bresp[1:0]))) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_bresp_stable: assert property (dma_axi_bresp_stable) else
           $display("DMA AXI bresp changed in middle of bus clock");

        // Assertion to check rvalid stays stable during entire bus clock
        property dma_axi_rvalid_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_rvalid != $past(dma_axi_rvalid)) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_rvalid_stable: assert property (dma_axi_rvalid_stable) else
           $display("DMA AXI rvalid changed in middle of bus clock");

        // Assertion to check rid stays stable during entire bus clock
        property dma_axi_rid_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_rvalid & (dma_axi_rid[pt.DMA_BUS_TAG-1:0] != $past(dma_axi_rid[pt.DMA_BUS_TAG-1:0]))) |-> $past(dma_bus_clk_en);

逐段解释：

* 第 L544-L548 行：当 ``dma_axi_bvalid`` 为真且 ``dma_axi_bid`` 变化时，上一拍必须有
  ``dma_bus_clk_en``。
* 第 L551-L555 行：``dma_axi_bresp`` 在 ``dma_axi_bvalid`` 为真时也受同样约束。
* 第 L558-L562 行：``dma_axi_rvalid`` 自身变化受 ``dma_bus_clk_en`` 约束。
* 第 L565-L567 行：``dma_axi_rid`` 在 ``dma_axi_rvalid`` 为真时受稳定性约束。

接口关系：

* 被调用：宏打开时由 assertion checker 采样。
* 调用：读取 B/R payload、valid、``clk``、``rst_l`` 和 ``dma_bus_clk_en``。
* 共享状态：payload 来源是 ``axi_rsp_tag``、``axi_rsp_error`` 和 ``axi_rsp_rdata``。

关键代码（``rtl/design/eh2_dma_ctrl.sv:L568-L587``）：

.. code-block:: systemverilog

        assert_dma_axi_rid_stable: assert property (dma_axi_rid_stable) else
           $display("DMA AXI rid changed in middle of bus clock");

        // Assertion to check rresp stays stable during entire bus clock
        property dma_axi_rresp_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_rvalid & (dma_axi_rresp[1:0] != $past(dma_axi_rresp[1:0]))) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_rresp_stable: assert property (dma_axi_rresp_stable) else
           $display("DMA AXI rresp changed in middle of bus clock");

        // Assertion to check rdata stays stable during entire bus clock
        property dma_axi_rdata_stable;
           @(posedge clk) disable iff(~rst_l)  (dma_axi_rvalid & (dma_axi_rdata[63:0] != $past(dma_axi_rdata[63:0]))) |-> $past(dma_bus_clk_en);
        endproperty
        assert_dma_axi_rdata_stable: assert property (dma_axi_rdata_stable) else
           $display("DMA AXI rdata changed in middle of bus clock");

   `endif

   endmodule // eh2_dma_ctrl

逐段解释：

* 第 L568-L569 行：``dma_axi_rid_stable`` 断言失败时打印 ``DMA AXI rid changed in middle of bus clock``。
* 第 L572-L576 行：``dma_axi_rresp`` 在 ``dma_axi_rvalid`` 为真时受稳定性约束。
* 第 L579-L583 行：``dma_axi_rdata`` 在 ``dma_axi_rvalid`` 为真时受稳定性约束。
* 第 L585-L587 行：断言宏结束后，模块以 ``endmodule // eh2_dma_ctrl`` 收尾。

接口关系：

* 被调用：宏打开时由 assertion checker 采样。
* 调用：读取 R channel payload、``clk``、``rst_l`` 和 ``dma_bus_clk_en``。
* 共享状态：这些断言与第 L497-L501 行的 R channel 输出赋值直接对应。

§11  Sign-off 关联证据
----------------------

本章只引用当前 block-level LEC summary 中关于 ``eh2_dma_ctrl`` 的结果，不把这些结果
扩展为额外 RTL 行为。2026-05-19 的 :file:`syn/build/lec_summary.txt` 列出
``eh2_dma_ctrl`` 在 block-level LEC 表中的结果为 ``967`` passing、``0`` failing、
``0`` unverified、``PASS``；总计为 ``31635`` passing、``0`` failing、``0``
unverified、``PASS``。

关键代码（``syn/build/lec_summary.txt:L1-L16``）：

.. code-block:: text

   EH2 Block-level LEC Summary (R3-C)
   Date: 2026-05-19 11:37:40

   | Module | Passing | Failing | Unverified | Status | Note |
   |---|---:|---:|---:|---|---|
   | eh2_dec | 7160 | 0 | 0 | PASS | standalone DDC |
   | eh2_exu_alu_ctl | 294 | 0 | 0 | PASS | EXU sub-block decomposition |
   | eh2_exu_mul_ctl | 272 | 0 | 0 | PASS | EXU sub-block decomposition |
   | eh2_exu_div_ctl | 181 | 0 | 0 | PASS | EXU sub-block decomposition |
   | eh2_lsu | 3565 | 0 | 0 | PASS | standalone DDC |
   | eh2_pic_ctrl | 1573 | 0 | 0 | PASS | standalone DDC |
   | eh2_dma_ctrl | 967 | 0 | 0 | PASS | standalone DDC |
   | eh2_dbg | 571 | 0 | 0 | PASS | standalone DDC |
   | eh2_ifu | 17052 | 0 | 0 | PASS | standalone DDC |
   | TOTAL | 31635 | 0 | 0 | PASS | real tool output only |

逐段解释：

* 第 L1-L2 行：summary 文件给出当前生成时间，属于真实 Formality block-level 产物摘要。
* 第 L5-L14 行：表格列出每个 block 的 passing、failing、unverified 和 status；
  ``eh2_dma_ctrl`` 对应 ``967``、``0``、``0``、``PASS``。
* 第 L15 行：总计保持 ``31635`` passing、``0`` failing、``0`` unverified、``PASS``。
  这些数字与 2026-05-19 demo 的 LEC 口径一致。

接口关系：

* 被调用：流程章节和 ADR 章节引用该 sign-off 结果。
* 调用：本文不从该表推导 RTL 行为，只把它作为 ``eh2_dma_ctrl`` 的验证状态索引。
* 共享状态：该结果与 :ref:`adr-0020` 的 block-level LEC closure 叙述一致。

关键代码（``dv/formal/properties/eh2_dma_assert.sv`` 不存在时的当前边界）：

.. code-block:: text

   Current formal property files live under:
     dv/formal/properties/

   DMA-specific sign-off evidence for this appendix is the block-level
   Formality LEC result, not a standalone DMA property file.

   Current formal stage aggregate:
     formal 46/46 PASS

逐段解释：

* 当前 formal stage 的 aggregate 结果是 ``46/46 PASS``，但本章不把 aggregate formal
  结果解释成 DMA 子模块单独 property closure。
* ``eh2_dma_ctrl`` 的模块级 sign-off 证据来自 block-level LEC summary；DMA 行为仍由
  RTL 源码、AXI assertion 和集成级 directed/compliance/formal stage 共同约束。

接口关系：

* 被调用：formal/LEC flow 文档引用这些结果。
* 调用：本文只在 sign-off 关联节引用，不改变 RTL 描述。
* 共享状态：与 :ref:`adr-0020` 的 block-level LEC 结果一致。

§12  参考资料
-------------

* 源文件：:file:`/home/host/eh2-veri/rtl/design/eh2_dma_ctrl.sv`
* 顶层实例：:file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* RTL filelist：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* LEC summary：:file:`/home/host/eh2-veri/syn/build/lec_summary.txt`
* 关联 ADR：:ref:`adr-0002`、:ref:`adr-0020`
* 关联章节：:doc:`mem`、:doc:`pic`、:doc:`shared_axi4`

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
