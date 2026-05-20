.. _appendix_a_rtl_dbg:
.. _appendix_a_rtl/dbg:

调试单元（DBG）- 详细参考
=========================

:status: draft
:source: rtl/design/dbg/eh2_dbg.sv
:last-reviewed: 2026-05-19

§1  文件边界与实例位置
----------------------

``eh2_dbg`` 是 EH2 core 内部的 debug mode 控制模块。它接收来自 DMI
寄存器接口的读写请求，维护 Debug Module 可见的 ``dmcontrol``、
``dmstatus``、``abstractcs``、``command``、``data0``、``data1`` 和 system
bus 相关寄存器；同时向 DEC / DMA / AXI system bus 发出 abstract command、
halt、resume 和 system bus 请求。

本章只描述 ``rtl/design/dbg/eh2_dbg.sv`` 的实际实现。JTAG TAP、DMI
跨时钟同步和 wrapper 连接属于 :doc:`dmi` 与顶层 wrapper 范围，本章仅在接口关系中说明
它们如何把 DMI 请求送到 ``eh2_dbg``。

§1.1  Filelist 中的 Debug 与 DMI 文件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：确认 ``eh2_dbg.sv`` 在 EH2 UVM RTL filelist 中的归属，并区分 Debug
核心逻辑与 DMI wrapper 文件。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L62-L68``）：

.. code-block:: systemverilog

   // Debug
   rtl/design/dbg/eh2_dbg.sv

   // DMI (Verilog)
   rtl/design/dmi/dmi_jtag_to_core_sync.v
   rtl/design/dmi/dmi_wrapper.v
   rtl/design/dmi/rvjtag_tap.v

逐段解释：

* 第 L62-L63 行：filelist 将 ``eh2_dbg.sv`` 单独放在 ``Debug`` 分组下，说明本章的主源文件是 core 内部 debug 控制器，而不是 JTAG TAP 或 DMI wrapper。
* 第 L65-L68 行：``dmi_jtag_to_core_sync.v``、``dmi_wrapper.v`` 和 ``rvjtag_tap.v`` 属于 DMI 路径，它们负责把 JTAG 侧访问转换为 ``dmi_reg_*`` 信号。``eh2_dbg`` 从这些信号开始处理 Debug Module 寄存器语义。

接口关系：

* 被调用：``dv/uvm/core_eh2/Makefile`` 及仿真构建通过 ``eh2_rtl.f`` 纳入这些 RTL 文件。
* 调用：本片段没有模块调用，只声明编译顺序。
* 共享状态：Debug 与 DMI 文件在顶层共享 ``dmi_reg_en``、``dmi_reg_addr``、``dmi_reg_wr_en``、``dmi_reg_wdata`` 和 ``dmi_reg_rdata`` 接口。

§1.2  ``eh2_veer`` 中的实例化与复位合成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 ``eh2_dbg`` 在 core 顶层的位置，以及它如何参与 ``core_rst_l`` 的生成。

关键代码（``rtl/design/eh2_veer.sv:L1024-L1050``）：

.. code-block:: systemverilog

   assign core_dbg_cmd_done = dma_dbg_cmd_done | dec_dbg_cmd_done;
   assign core_dbg_cmd_fail = dma_dbg_cmd_fail | dec_dbg_cmd_fail;
   assign core_dbg_rddata[31:0] = dma_dbg_cmd_done ? dma_dbg_rddata[31:0] : dec_dbg_rddata[31:0];

   eh2_dbg #(.pt(pt)) dbg (
                            .rst_l(core_rst_l),
                            .clk(free_l2clk),
                            .clk_override(dec_tlu_misc_clk_override),

                            // AXI signals
                            .sb_axi_awready(sb_axi_awready_int),
                            .sb_axi_wready(sb_axi_wready_int),
                            .sb_axi_bvalid(sb_axi_bvalid_int),
                            .sb_axi_bresp(sb_axi_bresp_int[1:0]),

                            .sb_axi_arready(sb_axi_arready_int),
                            .sb_axi_rvalid(sb_axi_rvalid_int),
                            .sb_axi_rdata(sb_axi_rdata_int[63:0]),
                            .sb_axi_rresp(sb_axi_rresp_int[1:0]),

                            .*
                            );


   // -----------------   DEBUG END -----------------------------

   assign core_rst_l = rst_l & (dbg_core_rst_l | scan_mode);

逐段解释：

* 第 L1024-L1026 行：顶层把 DMA debug memory command 与 DEC debug command 的完成、失败和读数据汇聚成 ``core_dbg_*``。``eh2_dbg`` 不直接区分这两个响应源，而是消费顶层合成后的 ``core_dbg_cmd_done``、``core_dbg_cmd_fail`` 和 ``core_dbg_rddata``。
* 第 L1028-L1045 行：``eh2_dbg`` 在 ``eh2_veer`` 内实例化，显式连接 ``core_rst_l``、``free_l2clk``、``dec_tlu_misc_clk_override`` 和 system bus AXI 响应信号，其余端口通过 ``.*`` 绑定到同名顶层信号。
* 第 L1050 行：``dbg_core_rst_l`` 参与 core reset 合成。``eh2_dbg`` 内部由 ``dmcontrol_reg[1]`` 生成该信号，因此 Debug Module 写 ``ndmreset`` 可以影响 core 复位路径；``scan_mode`` 会旁路该复位门控。

接口关系：

* 被调用：``eh2_veer`` 直接实例化 ``eh2_dbg``。
* 调用：``eh2_dbg`` 内部调用 ``rvoclkhdr``、``rvsyncss``、``rvdff``、``rvdffs`` 和 ``rvdffe``。
* 共享状态：``dbg_core_rst_l``、``core_dbg_*``、``sb_axi_*`` 和 ``dmi_reg_*`` 是 ``eh2_veer`` 与 ``eh2_dbg`` 之间的主要共享接口。

§1.3  Wrapper 中的 DMI 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 JTAG/DMI wrapper 如何把外部 JTAG 访问转成 ``eh2_dbg`` 可见的 DMI 寄存器接口。

关键代码（``rtl/design/eh2_veer_wrapper.sv:L776-L795``）：

.. code-block:: systemverilog

   dmi_wrapper  dmi_wrapper (

    // JTAG signals
        .jtag_id        (jtag_id),          // JTAG ID
        .trst_n         (jtag_trst_n),      // JTAG reset
        .tck            (jtag_tck),         // JTAG clock
        .tms            (jtag_tms),         // Test mode select
        .tdi            (jtag_tdi),         // Test Data Input
        .tdo            (jtag_tdo),         // Test Data Output
        .tdoEnable      (),                 // Test Data Output enable, NC

    // Processor Signals
        .core_rst_n     (dbg_rst_l),        // DM reset, active low
        .core_clk       (clk),              // Core clock
        .rd_data        (dmi_reg_rdata),    // Read data from  Processor
        .reg_wr_data    (dmi_reg_wdata),    // Write data to Processor
        .reg_wr_addr    (dmi_reg_addr),     // Write address to Processor
        .reg_en         (dmi_reg_en),       // access enable
        .reg_wr_en      (dmi_reg_wr_en),    // Write enable to Processor
        .dmi_hard_reset ()                  // hard reset of the DTM, NC

逐段解释：

* 第 L776-L785 行：``dmi_wrapper`` 连接 JTAG 侧 ``jtag_id``、``trst_n``、``tck``、``tms``、``tdi`` 和 ``tdo``，这是外部调试器进入 EH2 的物理调试接口。
* 第 L788-L795 行：wrapper 把 core 时钟复位和 DMI 寄存器读写信号送入 core 侧。``eh2_dbg`` 看到的是 ``dmi_reg_en``、``dmi_reg_wr_en``、``dmi_reg_addr``、``dmi_reg_wdata`` 和 ``dmi_reg_rdata``，不直接处理 JTAG TAP 状态。

接口关系：

* 被调用：SoC 或 testbench 通过 wrapper 的 JTAG 端口驱动 ``dmi_wrapper``。
* 调用：``dmi_wrapper`` 内部包含 JTAG TAP 和同步逻辑，本章不展开。
* 共享状态：``dmi_reg_*`` 是 wrapper 与 ``eh2_veer`` 内部 ``eh2_dbg`` 的桥接状态。

§2  端口与内部状态分组
----------------------

``eh2_dbg`` 的端口可以分成 6 组：DEC/DMA abstract command 输出、core command
响应、DMA bubble 握手、per-hart halt/resume、DMI 寄存器访问、system bus AXI 访问。
内部状态则分成 Debug 主 FSM、system bus FSM、Debug Module 寄存器和 system bus
寄存器。

§2.1  模块头部与 DEC/DMA command 接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 Debug Module 向 core 内部发送 abstract command 所需的地址、数据、类型、线程和 size 信号。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L24-L45``）：

.. code-block:: systemverilog

   module eh2_dbg #(
   `include "eh2_param.vh"
    )(
      // outputs to the core for command and data interface
      output logic [31:0]                 dbg_cmd_addr,
      output logic [31:0]                 dbg_cmd_wrdata,
      output logic                        dbg_cmd_valid,
      output logic                        dbg_cmd_tid,     // thread for debug register read
      output logic                        dbg_cmd_write,   // 1: write command, 0: read_command
      output logic [1:0]                  dbg_cmd_type,    // 0:gpr 1:csr 2: memory
      output logic [1:0]                  dbg_cmd_size,    // size of the abstract mem access debug command
      output logic                        dbg_core_rst_l,  // Debug reset

      // inputs back from the core/dec
      input logic [31:0]                  core_dbg_rddata,
      input logic                         core_dbg_cmd_done, // This will be treated like a valid signal
      input logic                         core_dbg_cmd_fail, // Exception during command run

      // Signals to dma to get a bubble
      output logic                        dbg_dma_bubble,   // Debug needs a bubble to send a valid
      input  logic                        dma_dbg_ready,    // DMA is ready to accept debug request

逐段解释：

* 第 L24-L26 行：模块通过 ``eh2_param.vh`` 引入参数结构 ``pt``，因此线程数、地址 region、system bus tag 宽度等均从同一参数包取得。
* 第 L28-L35 行：``dbg_cmd_*`` 是发给 DEC/DMA command 路径的抽象命令载荷。``dbg_cmd_type`` 明确编码为 GPR、CSR 或 memory；``dbg_cmd_tid`` 选中目标 hart；``dbg_core_rst_l`` 输出给顶层参与 core 复位。
* 第 L38-L40 行：``core_dbg_*`` 是 abstract command 返回通道。顶层已经把 DEC 和 DMA 的返回合并，因此 ``eh2_dbg`` 只需要根据 done/fail/rddata 更新 ``data0`` 或 ``abstractcs.cmderr``。
* 第 L43-L45 行：``dbg_dma_bubble`` 与 ``dma_dbg_ready`` 专门服务 abstract memory command。代码后续在 memory 命令期间拉起 bubble，并在 DMA ready 之前阻止 ``dbg_cmd_valid`` 发出。

接口关系：

* 被调用：``eh2_veer`` 通过 ``.*`` 和显式连接接入这些端口。
* 调用：本片段不调用子模块，只声明接口。
* 共享状态：``dbg_cmd_valid``、``dbg_cmd_type``、``core_dbg_cmd_done``、``core_dbg_cmd_fail`` 和 ``dma_dbg_ready`` 决定主 FSM 是否进入等待或完成状态。

§2.2  Halt/Resume、DMI 与 AXI 端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 Debug Module 与 TLU、DMI wrapper 和 system bus AXI 的外部边界。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L46-L115``）：

.. code-block:: systemverilog

      // interface with the rest of the core to halt/resume handshaking
      output logic [pt.NUM_THREADS-1:0]   dbg_halt_req, // This is a pulse
      output logic [pt.NUM_THREADS-1:0]   dbg_resume_req, // Debug sends a resume requests. Pulse
      input  logic [pt.NUM_THREADS-1:0]   dec_tlu_debug_mode,        // Core is in debug mode
      input  logic [pt.NUM_THREADS-1:0]   dec_tlu_dbg_halted, // The core has finished the queiscing sequence. Core is halted now
      input  logic [pt.NUM_THREADS-1:0]   dec_tlu_mpc_halted_only,   // Only halted due to MPC
      input  logic [pt.NUM_THREADS-1:0]   dec_tlu_resume_ack, // core sends back an ack for the resume (pulse)
      input  logic [pt.NUM_THREADS-1:0]   dec_tlu_mhartstart, // running harts

      // inputs from the JTAG
      input logic                         dmi_reg_en, // read or write
      input logic [6:0]                   dmi_reg_addr, // address of DM register
      input logic                         dmi_reg_wr_en, // write instruction
      input logic [31:0]                  dmi_reg_wdata, // write data
      // output
      output logic [31:0]                 dmi_reg_rdata, // read data

逐段解释：

* 第 L47-L53 行：halt/resume 是 per-hart 向量接口，宽度来自 ``pt.NUM_THREADS``。``dbg_halt_req`` 与 ``dbg_resume_req`` 是 pulse 输出，``dec_tlu_dbg_halted`` 和 ``dec_tlu_resume_ack`` 是 TLU 返回的状态与 ack。
* 第 L56-L61 行：DMI 入口是简单寄存器访问接口，地址宽度为 7 bit，数据宽度为 32 bit。Debug Module 的寄存器映射全部通过 ``dmi_reg_addr`` 解码。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L63-L115``）：

.. code-block:: systemverilog

      // AXI Write Channels
      output logic                        sb_axi_awvalid,
      input  logic                        sb_axi_awready,
      output logic [pt.SB_BUS_TAG-1:0]    sb_axi_awid,
      output logic [31:0]                 sb_axi_awaddr,
      output logic [3:0]                  sb_axi_awregion,
      output logic [7:0]                  sb_axi_awlen,
      output logic [2:0]                  sb_axi_awsize,
      output logic [1:0]                  sb_axi_awburst,
      output logic                        sb_axi_awlock,
      output logic [3:0]                  sb_axi_awcache,
      output logic [2:0]                  sb_axi_awprot,
      output logic [3:0]                  sb_axi_awqos,

      output logic                        sb_axi_wvalid,
      input  logic                        sb_axi_wready,
      output logic [63:0]                 sb_axi_wdata,
      output logic [7:0]                  sb_axi_wstrb,
      output logic                        sb_axi_wlast,

      input  logic                        sb_axi_bvalid,
      output logic                        sb_axi_bready,
      input  logic [1:0]                  sb_axi_bresp,

      // AXI Read Channels
      output logic                        sb_axi_arvalid,

逐段解释：

* 第 L63-L85 行：system bus 写路径包含 AW、W、B 三个 AXI channel。``eh2_dbg`` 作为 master 发地址、数据和 strobe，并常拉 ready 接收写响应。
* 第 L87-L104 行：读路径包含 AR 与 R channel。``eh2_dbg`` 发出单 beat read，并在响应返回后根据 size 与地址低位抽取 ``sb_bus_rdata``。
* 第 L106-L115 行：``dbg_bus_clk_en`` 控制 system bus 相关状态推进；``clk``、``free_clk``、``rst_l``、``dbg_rst_l``、``clk_override`` 和 ``scan_mode`` 参与本模块内部 clock gating 与复位。

接口关系：

* 被调用：``eh2_veer`` 把 system bus 信号接到内部 AXI fabric。
* 调用：本片段没有子模块实例。
* 共享状态：``dec_tlu_*``、``dmi_reg_*``、``sb_axi_*``、``dbg_bus_clk_en`` 是后续所有 FSM 的输入条件。

§2.3  Debug 主 FSM 与 system bus FSM 编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义两套状态机的状态编码，以及 Debug Module 内部可见寄存器。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L118-L145``）：

.. code-block:: systemverilog

   typedef enum logic [3:0] {IDLE=4'h0, HALTING=4'h1, HALTED=4'h2, CORE_CMD_START=4'h3, CORE_CMD_WAIT=4'h4, SB_CMD_START=4'h5, SB_CMD_SEND=4'h6, SB_CMD_RESP=4'h7, CMD_DONE=4'h8, RESUMING=4'h9} state_t;
   typedef enum logic [3:0] {SBIDLE=4'h0, WAIT_RD=4'h1, WAIT_WR=4'h2, CMD_RD=4'h3, CMD_WR=4'h4, CMD_WR_ADDR=4'h5, CMD_WR_DATA=4'h6, RSP_RD=4'h7, RSP_WR=4'h8, DONE=4'h9} sb_state_t;

   state_t [pt.NUM_THREADS-1:0]  dbg_state;
   state_t [pt.NUM_THREADS-1:0]  dbg_nxtstate;
   logic   [pt.NUM_THREADS-1:0]  dbg_state_en;
   // these are the registers that the debug module implements
   logic [31:0]  dmstatus_reg;        // [26:24]-dmerr, [17:16]-resume ack, [9:8]-halted, [3:0]-version
   logic [31:0]  dmcontrol_reg;       // dmcontrol register has only 6 bits implemented. 31: haltreq, 30: resumereq, 29: haltreset, 28: ackhavereset, 1: ndmreset, 0: dmactive.
   logic [31:0]  command_reg;
   logic [31:0]  abstractcs_reg;      // bits implemted are [12] - busy and [10:8]= command error
   logic [31:0]  hawindow_reg;
   logic [31:0]  haltsum0_reg;
   logic [31:0]  data0_reg;
   logic [31:0]  data1_reg;

逐段解释：

* 第 L118 行：Debug 主 FSM 覆盖 halt 进入、halted 停留、core command、system bus command、command done 和 resume。数组化的 ``dbg_state`` 后续按 ``pt.NUM_THREADS`` 为每个 hart 生成一份状态。
* 第 L119 行：system bus FSM 独立于 Debug 主 FSM，负责 DMI system bus 直接访问和 abstract memory command 复用同一 AXI master。
* 第 L121-L123 行：``dbg_state``、``dbg_nxtstate`` 和 ``dbg_state_en`` 都是 per-hart 向量，说明 halt/resume 与 command 调度按照 hart 维度进行。
* 第 L125-L133 行：``dmstatus_reg``、``dmcontrol_reg``、``command_reg``、``abstractcs_reg``、``hawindow_reg``、``haltsum0_reg``、``data0_reg`` 和 ``data1_reg`` 是 Debug Module 对 DMI 暴露的主要寄存器。

接口关系：

* 被调用：DMI 读写解码和两个 FSM 使用这些状态与寄存器。
* 调用：状态寄存器稍后通过 ``rvdffs`` 实例实现。
* 共享状态：``dmcontrol_reg`` 选择 hart、发起 halt/resume 和 reset；``command_reg`` 与 ``data0/1`` 决定 abstract command 载荷；``abstractcs_reg`` 记录 busy 和 cmderr。

§2.4  System bus 内部寄存器与地址分类信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 system bus 寄存器、busy/error 状态、abstract memory command 缓冲和本地/外部地址分类。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L181-L260``）：

.. code-block:: systemverilog

   //System bus section
   logic              sbcs_wren;
   logic              sbcs_sbbusy_wren;
   logic              sbcs_sbbusy_din;
   logic              sbcs_sbbusyerror_wren;
   logic              sbcs_sbbusyerror_din;

   logic              sbcs_sberror_wren;
   logic [2:0]        sbcs_sberror_din;
   logic              sbcs_unaligned;
   logic              sbcs_illegal_size;
   logic [19:15]      sbcs_reg_int;

   // data
   logic              sbdata0_reg_wren0;
   logic              sbdata0_reg_wren1;
   logic              sbdata0_reg_wren;
   logic [31:0]       sbdata0_din;

   logic              sbdata1_reg_wren0;
   logic              sbdata1_reg_wren1;

逐段解释：

* 第 L181-L193 行：``sbcs`` 相关信号跟踪 system bus control/status 的写使能、busy、busyerror、sberror、未对齐和非法 size。后续 system bus FSM 会根据这些信号允许或拒绝发起 AXI 事务。
* 第 L195-L203 行：``sbdata0`` 与 ``sbdata1`` 既可由 DMI 写入，也可由 system bus read response 更新，因此每个 data 寄存器都有两类写使能。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L214-L260``）：

.. code-block:: systemverilog

   logic [pt.NUM_THREADS-1:0]  sb_abmem_cmd_done_in, sb_abmem_data_done_in;
   logic [pt.NUM_THREADS-1:0]  sb_abmem_cmd_done_en, sb_abmem_data_done_en;
   logic [pt.NUM_THREADS-1:0]  sb_abmem_cmd_done, sb_abmem_data_done;
   logic [31:0]       abmem_addr;
   logic              abmem_addr_in_dccm_region, abmem_addr_in_iccm_region, abmem_addr_in_pic_region;
   logic              abmem_addr_core_local;
   logic              abmem_addr_external;

   logic              sb_cmd_pending, sb_abmem_cmd_pending;
   logic              sb_abmem_cmd_write;
   logic [2:0]        sb_abmem_cmd_size;
   logic [31:0]       sb_abmem_cmd_addr;
   logic [31:0]       sb_abmem_cmd_wdata;

   logic [2:0]        sb_cmd_size;
   logic [31:0]       sb_cmd_addr;
   logic [63:0]       sb_cmd_wdata;

逐段解释：

* 第 L214-L220 行：abstract memory command 通过 per-hart done 标志拆分命令 channel 与 data channel 完成状态；``abmem_addr_*`` 判断地址是否落在 DCCM、ICCM 或 PIC 本地 region。
* 第 L222-L226 行：``sb_abmem_cmd_*`` 是 abstract memory command 进入 AXI system bus 路径前的载荷缓存。
* 第 L228-L235 行：``sb_cmd_*`` 是 DMI system bus 直接访问的载荷，``sb_bus_cmd_*`` 与 ``sb_bus_rsp_*`` 表示 AXI 握手事件和响应错误。
* 第 L237-L260 行：``sbcs_reg``、``sbaddress0_reg``、``sbdata0_reg``、``sbdata1_reg`` 是 system bus DMI 寄存器；``dbg_free_clk`` 与 ``sb_free_clk`` 是 Debug Module 和 system bus 子路径的 gated clock。

接口关系：

* 被调用：system bus 寄存器逻辑、主 FSM 的 ``SB_CMD_*`` 状态和 AXI 输出逻辑共同使用这些信号。
* 调用：后续用 ``rvdffe`` 保存寄存器，用 ``rvoclkhdr`` 生成 gated clock。
* 共享状态：``abmem_addr_external`` 决定 abstract memory command 是走 core command path 还是 system bus path。

§3  时钟、复位与 Debug Module 激活
----------------------------------

``eh2_dbg`` 内部有两条 gated clock：``dbg_free_clk`` 用于 Debug Module 寄存器和主 FSM，
``sb_free_clk`` 用于 system bus 寄存器和 system bus FSM。复位也分成 Debug Module
reset 与 core reset 输出：``dbg_dm_rst_l`` 由外部 ``dbg_rst_l`` 和 ``dmactive`` 控制，
``dbg_core_rst_l`` 由 ``dmcontrol.ndmreset`` 控制。

§3.1  Debug clock enable
~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 DMI 访问、halted/debug mode、halt request、command 执行或状态机非 idle 时打开 Debug Module 时钟。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L263-L276``）：

.. code-block:: systemverilog

   // clocking
   // used for the abstract commands.
   always_comb begin
      dbg_free_clken  = dmi_reg_en | clk_override;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         dbg_free_clken |= dec_tlu_dbg_halted[i] | dec_tlu_mpc_halted_only[i] | dec_tlu_debug_mode[i] | dbg_halt_req[i] | execute_command | dbg_state_en[i] | (dbg_state[i] != IDLE);
      end
   end

   // used for the system bus
   assign sb_free_clken = dmi_reg_en | execute_command | sb_state_en | (sb_state != SBIDLE) | clk_override;

   rvoclkhdr dbg_free_cgc     (.en(dbg_free_clken), .l1clk(dbg_free_clk), .*);
   rvoclkhdr sb_free_cgc     (.en(sb_free_clken), .l1clk(sb_free_clk), .*);

逐段解释：

* 第 L265-L270 行：``dbg_free_clken`` 的初始条件是 DMI 访问或 clock override。循环中只要任一 hart halted、MPC halted、处于 debug mode、发起 halt、执行命令、状态机推进或状态不为 ``IDLE``，Debug Module 时钟都会保持打开。
* 第 L273 行：``sb_free_clken`` 的条件更窄，主要覆盖 DMI 访问、abstract command、system bus FSM 推进、FSM 非 ``SBIDLE`` 或 clock override。
* 第 L275-L276 行：两个 ``rvoclkhdr`` 分别生成 ``dbg_free_clk`` 和 ``sb_free_clk``。这意味着 Debug Module 寄存器与 system bus 寄存器虽在同一模块内，但时钟使能条件不同。

接口关系：

* 被调用：所有 ``rvdff`` / ``rvdffs`` / ``rvdffe`` 寄存器实例使用 ``dbg_free_clk`` 或 ``sb_free_clk``。
* 调用：实例化 ``rvoclkhdr``。
* 共享状态：``dmi_reg_en``、``execute_command``、``dbg_state_en`` 和 ``sb_state_en`` 同时影响时钟打开与 FSM 状态推进。

§3.2  Debug Module reset 与 core reset 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 ``dmactive``、``ndmreset``、``scan_mode`` 和外部复位生成内部 Debug Module reset 与输出给 core 的复位。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L280-L285``）：

.. code-block:: systemverilog

   // Reset logic
   assign dbg_dm_rst_l = dbg_rst_l & (dmcontrol_reg[0] | scan_mode);
   assign dbg_core_rst_l = ~dmcontrol_reg[1] | scan_mode;

   // synchronize the rst
   rvsyncss #(1) rstl_syncff (.din(rst_l), .dout(rst_l_sync), .clk(free_clk), .rst_l(dbg_rst_l));

逐段解释：

* 第 L281 行：``dbg_dm_rst_l`` 要求外部 ``dbg_rst_l`` 有效，并且 ``dmcontrol_reg[0]``（``dmactive``）为 1；``scan_mode`` 可绕过 ``dmactive`` 对 Debug Module reset 的限制。
* 第 L282 行：``dbg_core_rst_l`` 是 ``~dmcontrol_reg[1]`` 或 ``scan_mode``。代码注释在第 L346 行说明 bit 1 是 ``ndmreset``，因此该输出在 ``ndmreset`` 置位时拉低，再由顶层组合到 ``core_rst_l``。
* 第 L285 行：``rst_l`` 通过 ``rvsyncss`` 同步到 ``free_clk`` 域，生成 ``rst_l_sync``。后续 ``dbg_unavailable`` 用它判断 hart 是否可用。

接口关系：

* 被调用：``dbg_dm_rst_l`` 驱动多数 Debug Module 寄存器复位；``dbg_core_rst_l`` 输出到 ``eh2_veer``。
* 调用：实例化 ``rvsyncss``。
* 共享状态：``dmcontrol_reg[0]`` 和 ``dmcontrol_reg[1]`` 分别控制 Debug Module 激活和 core reset。

§4  Debug Module 寄存器实现
---------------------------

本节描述 DMI 地址空间中由 ``eh2_dbg`` 实现的寄存器。寄存器地址和位域均来自
``eh2_dbg.sv`` 中的解码逻辑，不从外部规格推导。

§4.1  ``dmcontrol`` - halt、resume、hartsel 与 reset
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解码 DMI 地址 ``7'h10`` 的写访问，保存 haltreq、resumereq、ackhavereset、hasel、hartsel、ndmreset 和 dmactive。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L345-L360``）：

.. code-block:: systemverilog

   // memory mapped registers
   // dmcontrol register has only 6 bits implemented. 31: haltreq, 30: resumereq, 28: ackhavereset, 26: hasel, 6:hartsel, 1: ndmreset, 0: dmactive.
   // rest all the bits are zeroed out
   // dmactive flop is reset based on core rst_l, all other flops use dm_rst_l
   assign dmcontrol_wren      = (dmi_reg_addr ==  7'h10) & dmi_reg_en & dmi_reg_wr_en;
   assign dmcontrol_reg[29]   = '0;
   assign dmcontrol_reg[27]   = '0;
   assign dmcontrol_reg[25:17] = '0;
   assign dmcontrol_reg[15:2]  = '0;
   assign dmcontrol_hasel_in  = (pt.NUM_THREADS > 1) & dmi_reg_wdata[26];   // hasel tied to 0 for single thread
   assign dmcontrol_hartsel_in = (pt.NUM_THREADS > 1) & dmi_reg_wdata[16];   // hartsel tied to 0 for single thread
   assign resumereq           = dmcontrol_reg[30] & ~dmcontrol_reg[31] & dmcontrol_wren_Q;
   rvdffs #(6) dmcontrolff (.din({dmi_reg_wdata[31:30],dmi_reg_wdata[28],dmcontrol_hasel_in,dmcontrol_hartsel_in,dmi_reg_wdata[1]}),
                            .dout({dmcontrol_reg[31:30],dmcontrol_reg[28],dmcontrol_reg[26],dmcontrol_reg[16],dmcontrol_reg[1]}), .en(dmcontrol_wren), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));
   rvdffs #(1) dmcontrol_dmactive_ff (.din(dmi_reg_wdata[0]), .dout(dmcontrol_reg[0]), .en(dmcontrol_wren), .rst_l(dbg_rst_l), .clk(dbg_free_clk));
   rvdff  #(1) dmcontrol_wrenff(.din(dmcontrol_wren), .dout(dmcontrol_wren_Q), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));

逐段解释：

* 第 L345-L349 行：``dmcontrol_wren`` 只在 DMI 写 ``7'h10`` 时有效。注释列出实现位：31、30、28、26、16、1 和 0。
* 第 L350-L353 行：未实现位直接绑 0，包括 bit 29、27、25:17 和 15:2。
* 第 L354-L355 行：``hasel`` 与 ``hartsel`` 只有在 ``pt.NUM_THREADS > 1`` 时接收 DMI 写数据；单线程配置下两者固定为 0。
* 第 L356 行：``resumereq`` 是由上一拍写使能 ``dmcontrol_wren_Q`` 和已保存的 ``dmcontrol_reg[30]`` 生成的内部脉冲，并要求 ``haltreq`` 不同时为 1。
* 第 L357-L360 行：``dmcontrolff`` 保存除 ``dmactive`` 外的 6 个实现位；``dmactive`` 单独用 ``dbg_rst_l`` 复位，因此其复位域与其它 ``dmcontrol`` 位不同。

接口关系：

* 被调用：主 FSM 使用 ``dmcontrol_reg[31]`` 发起 halt，使用 ``resumereq`` 发起 resume，使用 ``dmcontrol_reg[16]`` 和 ``dmcontrol_reg[26]`` 选择 hart。
* 调用：实例化 ``rvdffs`` 与 ``rvdff``。
* 共享状态：``dmcontrol_reg[0]`` 控制 ``dbg_dm_rst_l``；``dmcontrol_reg[1]`` 控制 ``dbg_core_rst_l``；``dmcontrol_reg[31:30]`` 驱动 halt/resume 流程。

§4.2  ``dmstatus`` 与 ``haltsum0`` - hart 状态汇总
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 per-hart halted、running、resumeack、havereset 和 unavailable 状态聚合成 DMI 可读寄存器。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L362-L385``）：

.. code-block:: systemverilog

   // dmstatus register bits that are implemented
   // [19:18]-havereset,[17:16]-resume ack, [15:14]-available, [9]-allhalted, [8]-anyhalted, [3:0]-version
   // rest all the bits are zeroed out
   assign dmstatus_reg[31:20] = '0;
   assign dmstatus_reg[19]    = &(dbg_havereset[pt.NUM_THREADS-1:0] | ~hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[18]    = |(dbg_havereset[pt.NUM_THREADS-1:0] & hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[17]    = &(dbg_resumeack[pt.NUM_THREADS-1:0] | ~hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[16]    = |(dbg_resumeack[pt.NUM_THREADS-1:0] & hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[15:14] = '0;
   assign dmstatus_reg[13]    = &(dbg_unavailable[pt.NUM_THREADS-1:0] | ~hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[12]    = |(dbg_unavailable[pt.NUM_THREADS-1:0] & hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[11]    = &(dbg_running[pt.NUM_THREADS-1:0] | ~hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[10]    = |(dbg_running[pt.NUM_THREADS-1:0] & hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[9]     = &(dbg_halted[pt.NUM_THREADS-1:0] | ~hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[8]     = |(dbg_halted[pt.NUM_THREADS-1:0] & hart_sel[pt.NUM_THREADS-1:0]);
   assign dmstatus_reg[7]     = '1;
   assign dmstatus_reg[6:4]   = '0;
   assign dmstatus_reg[3:0]   = 4'h2;

逐段解释：

* 第 L362-L364 行：注释列出实现位，未列出的高位和中间位被置 0。
* 第 L366-L379 行：``dmstatus`` 以 ``hart_sel`` 作为 mask 计算 all/any 风格状态。all 位使用按位或 ``~hart_sel`` 后再 reduce-and，any 位使用 ``hart_sel`` mask 后 reduce-or。
* 第 L377-L379 行：bit 7 固定为 1，bit 3:0 固定为 ``4'h2``；这些值直接来自 RTL 赋值。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L381-L385``）：

.. code-block:: systemverilog

   // haltsum0 register
   assign haltsum0_reg[31:pt.NUM_THREADS] = '0;
   for (genvar i=0; i<pt.NUM_THREADS; i++) begin: Gen_haltsum
      assign haltsum0_reg[i]  = dbg_halted[i];
   end

逐段解释：

* 第 L381-L385 行：``haltsum0`` 的低 ``pt.NUM_THREADS`` 位直接映射每个 hart 的 ``dbg_halted``，高位清 0。没有额外编码或压缩逻辑。

接口关系：

* 被调用：DMI 读 mux 在 ``7'h11`` 返回 ``dmstatus_reg``，在 ``7'h40`` 返回 ``haltsum0_reg``。
* 调用：本节是组合赋值，没有子模块实例。
* 共享状态：``dbg_halted``、``dbg_running``、``dbg_resumeack``、``dbg_havereset``、``dbg_unavailable`` 和 ``hart_sel`` 是状态汇总输入。

§4.3  ``abstractcs`` - busy 与 command error
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：维护 abstract command 的 busy bit 和 ``cmderr``，并对非法访问、非法命令、core exception、未 halted、bus error 与未对齐 memory command 编码错误。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L387-L422``）：

.. code-block:: systemverilog

   // abstractcs register
   // bits implemted are [12] - busy and [10:8]= command error
   assign        abstractcs_reg[31:13] = '0;
   assign        abstractcs_reg[11]    = '0;
   assign        abstractcs_reg[7:4]   = '0;
   assign        abstractcs_reg[3:0]   = 4'h2;    // One data register


   assign        abstractcs_error_sel0 = abstractcs_reg[12] & ~(|abstractcs_reg[10:8]) & dmi_reg_en & ((dmi_reg_wr_en & ((dmi_reg_addr == 7'h16) | (dmi_reg_addr == 7'h17)) | (dmi_reg_addr == 7'h18)) |
                                                                                                       (dmi_reg_addr == 7'h4) | (dmi_reg_addr == 7'h5));
   assign        abstractcs_error_sel1 = execute_command & ~(|abstractcs_reg[10:8]) &
                                         ((~((command_reg[31:24] == 8'b0) | (command_reg[31:24] == 8'h2)))                      |   // Illegal command
                                          (((command_reg[22:20] == 3'b011) | (command_reg[22])) & (command_reg[31:24] == 8'h2)) |   // Illegal abstract memory size (can't be DW or higher)
                                          ((command_reg[22:20] != 3'b010) & ((command_reg[31:24] == 8'h0) & command_reg[17]))   |   // Illegal abstract reg size
                                          ((command_reg[31:24] == 8'h0) & command_reg[18]));                                          //postexec for abstract register access
   assign        abstractcs_error_sel2 = ((core_dbg_cmd_done & core_dbg_cmd_fail) |                   // exception from core
                                          (execute_command & (command_reg[31:24] == 8'h0) &           // unimplemented regs

逐段解释：

* 第 L387-L392 行：``abstractcs`` 只实现 busy、cmderr 和 data register 数量。``abstractcs_reg[3:0]`` 固定为 ``4'h2``。
* 第 L395-L396 行：``abstractcs_error_sel0`` 在 busy 且无既有错误时捕捉对 ``abstractcs``、``command``、``abstractauto``、``data0`` 或 ``data1`` 的访问。
* 第 L397-L401 行：``abstractcs_error_sel1`` 捕捉非法命令类型、非法 abstract memory size、非法 abstract register size 以及 register access 的 ``postexec``。
* 第 L402 行开始：``abstractcs_error_sel2`` 把 core command fail 或未实现 register 编码成错误，完整条件在下一片段继续。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L402-L422``）：

.. code-block:: systemverilog

   assign        abstractcs_error_sel2 = ((core_dbg_cmd_done & core_dbg_cmd_fail) |                   // exception from core
                                          (execute_command & (command_reg[31:24] == 8'h0) &           // unimplemented regs
                                                (((command_reg[15:12] == 4'h1) & (command_reg[11:5] != 0)) | (command_reg[15:13] != 0)))) & ~(|abstractcs_reg[10:8]);
   assign        abstractcs_error_sel3 = execute_command & ~(|abstractcs_reg[10:8]) & ~(|(command_sel[pt.NUM_THREADS-1:0] & dbg_halted[pt.NUM_THREADS-1:0]));  //(dbg_state != HALTED);;
   assign        abstractcs_error_sel4 = (|dbg_sb_bus_error[pt.NUM_THREADS-1:0]) & dbg_bus_clk_en & ~(|abstractcs_reg[10:8]);// sb bus error for abstract memory command
   assign        abstractcs_error_sel5 = execute_command & (command_reg[31:24] == 8'h2) & ~(|abstractcs_reg[10:8]) &
                                         (((command_reg[22:20] == 3'b001) & data1_reg[0]) | ((command_reg[22:20] == 3'b010) & (|data1_reg[1:0])));  //Unaligned address for abstract memory
   assign        abstractcs_error_sel6 = (dmi_reg_addr ==  7'h16) & dmi_reg_en & dmi_reg_wr_en;

   assign        abstractcs_error_din[2:0]  = abstractcs_error_sel0 ? 3'b001 :                  // writing command or abstractcs while a command was executing. Or accessing data0
                                                    abstractcs_error_sel1 ? 3'b010 :               // writing a illegal command type to cmd field of command
                                                       abstractcs_error_sel2 ? 3'b011 :            // exception while running command
                                                          abstractcs_error_sel3 ? 3'b100 :         // writing a comnand when not in the halted state
                                                             abstractcs_error_sel4 ? 3'b101 :      // Bus error
                                                                abstractcs_error_sel5 ? 3'b111 :   // unaligned or illegal size abstract memory command
                                                                   abstractcs_error_sel6 ? (~dmi_reg_wdata[10:8] & abstractcs_reg[10:8]) :   //W1C
                                                                                           abstractcs_reg[10:8];                             //hold

   assign abstractcs_reg[12] = |abstractcs_busy[pt.NUM_THREADS-1:0];

   rvdff  #(3) dmabstractcs_error_reg (.din(abstractcs_error_din[2:0]), .dout(abstractcs_reg[10:8]), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));

逐段解释：

* 第 L402-L405 行：``abstractcs_error_sel2`` 处理 core exception 或未实现 register 编码；``abstractcs_error_sel3`` 处理目标 hart 未 halted 时写 command 的情况。
* 第 L406-L409 行：``abstractcs_error_sel4`` 来自 system bus error；``abstractcs_error_sel5`` 来自 abstract memory 地址未对齐；``abstractcs_error_sel6`` 是对 ``abstractcs`` 地址 ``7'h16`` 的写访问，用于 W1C 清错误。
* 第 L411-L418 行：错误优先级由三元链固定，编码依次为 ``3'b001``、``3'b010``、``3'b011``、``3'b100``、``3'b101``、``3'b111``，最后对 ``cmderr`` 做 W1C 或保持。
* 第 L420-L422 行：busy bit 是所有 hart ``abstractcs_busy`` 的 OR；``cmderr`` 通过 ``rvdff`` 保存。

接口关系：

* 被调用：主 FSM 在发起和完成 command 时写 ``abstractcs_busy``；DMI read mux 返回 ``abstractcs_reg``。
* 调用：实例化 ``rvdff`` 保存 ``cmderr``。
* 共享状态：``abstractcs_reg[10:8]`` 会阻止后续 command 执行；``abstractcs_reg[12]`` 会阻止部分 DMI 写入。

§4.4  ``command`` 与 ``abstractauto``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解码 command 写入、自动执行条件、postincrement 地址更新，以及 abstractauto 对 ``data0`` / ``data1`` 访问的触发。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L424-L445``）：

.. code-block:: systemverilog

    // abstract auto reg
   assign abstractauto_reg_wren  = dmi_reg_en & dmi_reg_wr_en & (dmi_reg_addr == 7'h18) & ~abstractcs_reg[12];
   rvdffs #(2) dbg_abstractauto_reg (.*, .din(dmi_reg_wdata[1:0]), .dout(abstractauto_reg[1:0]), .en(abstractauto_reg_wren), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));

   // command register - implemented all the bits in this register
   // command[16] = 1: write, 0: read
   assign execute_command_ns = command_wren |
                                (dmi_reg_en & ~abstractcs_reg[12] & (((dmi_reg_addr == 7'h4) & abstractauto_reg[0]) | ((dmi_reg_addr == 7'h5) & abstractauto_reg[1])));
   always_comb begin
      command_wren = 1'b0;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         command_wren |= ((dmi_reg_addr == 7'h17) & dmi_reg_en & dmi_reg_wr_en & command_sel[i]);
      end
   end
   assign command_regno_wren = command_wren | ((command_reg[31:24] == 8'h0) & command_reg[19] & (dbg_state == CMD_DONE) & ~(|abstractcs_reg[10:8]));  // aarpostincrement
   assign command_postexec_din = (dmi_reg_wdata[31:24] == 8'h0) & dmi_reg_wdata[18];
   assign command_transfer_din = (dmi_reg_wdata[31:24] == 8'h0) & dmi_reg_wdata[17];
   assign command_din[31:16] = {dmi_reg_wdata[31:24],1'b0,dmi_reg_wdata[22:19],command_postexec_din,command_transfer_din, dmi_reg_wdata[16]};
   assign command_din[15:0] =  command_wren ? dmi_reg_wdata[15:0] : dbg_cmd_next_addr[15:0];

逐段解释：

* 第 L424-L426 行：``abstractauto`` 只能在 not busy 时写，且只保存 DMI 写数据低 2 位。
* 第 L430-L431 行：``execute_command_ns`` 可由 ``command_wren`` 直接触发，也可由 ``abstractauto`` 在访问 ``data0`` 或 ``data1`` 时触发。
* 第 L432-L437 行：``command_wren`` 要求 DMI 写 ``7'h17``，并且目标 hart 的 ``command_sel`` 为 1。
* 第 L438-L442 行：``command_regno_wren`` 除了正常 command 写入，还支持 abstract register access 的 ``aarpostincrement``；``command_din`` 会强制 ``postexec`` 和 ``transfer`` 只对 command type ``8'h0`` 生效。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L443-L445``）：

.. code-block:: systemverilog

   rvdff  #(1)  execute_commandff   (.*, .din(execute_command_ns), .dout(execute_command), .clk(dbg_free_clk), .rst_l(dbg_dm_rst_l));
   rvdffe #(16) dmcommand_reg       (.*, .din(command_din[31:16]), .dout(command_reg[31:16]), .en(command_wren), .rst_l(dbg_dm_rst_l));
   rvdffe #(16) dmcommand_regno_reg (.*, .din(command_din[15:0]),  .dout(command_reg[15:0]),  .en(command_regno_wren), .rst_l(dbg_dm_rst_l));

逐段解释：

* 第 L443 行：``execute_command`` 是 ``execute_command_ns`` 的寄存版本，用于主 FSM 判断是否开始执行。
* 第 L444-L445 行：``command_reg[31:16]`` 只在 command 写入时更新；``command_reg[15:0]`` 可在 command 写入或 postincrement 时更新。

接口关系：

* 被调用：主 FSM 在 ``HALTED`` 状态根据 ``execute_command`` 和 ``command_reg`` 进入 ``CORE_CMD_START`` 或 ``SB_CMD_START``。
* 调用：实例化 ``rvdff`` 和 ``rvdffe``。
* 共享状态：``abstractauto_reg`` 影响 ``execute_command``，``command_reg`` 影响错误检测、command 载荷和地址自增。

§4.5  ``hawindow``、``data0`` 与 ``data1``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：维护 hart array window、abstract command 数据寄存器，以及 command 完成后的读数据回写和地址 postincrement。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L447-L486``）：

.. code-block:: systemverilog

   // hawindow reg
   assign hawindow_wren = dmi_reg_en & dmi_reg_wr_en & (dmi_reg_addr == 7'h15);
   assign hawindow_reg[31:pt.NUM_THREADS] = '0;

   for (genvar i=0; i<pt.NUM_THREADS; i++) begin: GenHAWindow
      rvdffs #(1) dbg_hawindow_reg (.*, .din(dmi_reg_wdata[i]), .dout(hawindow_reg[i]), .en(hawindow_wren), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));
   end

   // data0 reg
   always_comb begin
      data0_reg_wren0 = 1'b0;
      data0_reg_wren1 = 1'b0;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         data0_reg_wren0   |= (dmi_reg_en & dmi_reg_wr_en & (dmi_reg_addr == 7'h4) & command_sel[i] & (dbg_state[i] == HALTED) & ~abstractcs_reg[12]);
         data0_reg_wren1   |= (core_dbg_cmd_done & (dbg_state[i] == CORE_CMD_WAIT) & ~command_reg[16]);
      end
   end
   assign data0_reg_wren    = data0_reg_wren0 | data0_reg_wren1 | (|data0_reg_wren2[pt.NUM_THREADS-1:0]);

逐段解释：

* 第 L447-L453 行：``hawindow`` 由 DMI 地址 ``7'h15`` 写入，低 ``pt.NUM_THREADS`` 位按 hart 保存，高位清 0。后续 ``hart_sel`` 会在 ``hasel`` 置位时使用 ``hawindow_reg``。
* 第 L456-L464 行：``data0`` 有三类写入：DMI 在目标 hart halted 且 not busy 时写入、core read command 完成时写入、system bus read abstract memory command 完成时写入。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L466-L486``）：

.. code-block:: systemverilog

   assign data0_din[31:0]   = ({32{data0_reg_wren0}} & dmi_reg_wdata[31:0])   |
                              ({32{data0_reg_wren1}} & core_dbg_rddata[31:0]) |
                              ({32{|data0_reg_wren2}} & sb_bus_rdata[31:0]);

   rvdffe #(32) dbg_data0_reg (.*, .din(data0_din[31:0]), .dout(data0_reg[31:0]), .en(data0_reg_wren), .rst_l(dbg_dm_rst_l));

   // data 1
   always_comb begin
      data1_reg_wren0 = 1'b0;
      data1_reg_wren1 = 1'b0;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         data1_reg_wren0   |= (dmi_reg_en & dmi_reg_wr_en & (dmi_reg_addr == 7'h5) & command_sel[i] & (dbg_state[i] == HALTED));
         data1_reg_wren1   |= ((dbg_state[i] == CMD_DONE) & (command_reg[31:24] == 8'h2) & command_reg[19] & ~(|abstractcs_reg[10:8]));   // aampostincrement
      end
   end
   assign data1_reg_wren    = data1_reg_wren0 | data1_reg_wren1;

   assign data1_din[31:0]   = ({32{data1_reg_wren0}} & dmi_reg_wdata[31:0]) |
                              ({32{data1_reg_wren1}} & dbg_cmd_next_addr[31:0]);

   rvdffe #(32)    dbg_data1_reg    (.*, .din(data1_din[31:0]), .dout(data1_reg[31:0]), .en(data1_reg_wren), .rst_l(dbg_dm_rst_l));

逐段解释：

* 第 L466-L470 行：``data0_din`` 在 DMI 写、core read 返回、system bus read 返回之间选择；``dbg_data0_reg`` 使用 ``rvdffe`` 保存。
* 第 L473-L481 行：``data1`` 由 DMI 写 ``7'h5`` 或 abstract memory command 完成后的 ``aampostincrement`` 更新。
* 第 L483-L486 行：``data1_din`` 在 DMI 写数据与 ``dbg_cmd_next_addr`` 之间选择，后者用于 memory command 地址自增。

接口关系：

* 被调用：``dbg_cmd_wrdata`` 直接取 ``data0_reg``；abstract memory 地址取 ``data1_reg``。
* 调用：实例化 ``rvdffs`` 和 ``rvdffe``。
* 共享状态：``data0_reg`` 与 ``data1_reg`` 是 command 载荷、DMI 可读数据和 system bus 读写数据之间的共享寄存器。

§4.6  DMI read mux
~~~~~~~~~~~~~~~~~~

职责：把 DMI 地址映射到 Debug Module 寄存器读数据，并在 DMI 访问时打一拍输出。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L612-L628``）：

.. code-block:: systemverilog

   assign dmi_reg_rdata_din[31:0] = ({32{dmi_reg_addr == 7'h4}}  & data0_reg[31:0])      |
                                    ({32{dmi_reg_addr == 7'h5}}  & data1_reg[31:0])      |
                                    ({32{dmi_reg_addr == 7'h10}} & {2'b0,dmcontrol_reg[29],1'b0,dmcontrol_reg[27:0]})  |  // Read0 to Write only bits
                                    ({32{dmi_reg_addr == 7'h11}} & dmstatus_reg[31:0])   |
                                    ({32{dmi_reg_addr == 7'h15}} & hawindow_reg[31:0]) |
                                    ({32{dmi_reg_addr == 7'h16}} & abstractcs_reg[31:0]) |
                                    ({32{dmi_reg_addr == 7'h17}} & command_reg[31:0])    |
                                    ({32{dmi_reg_addr == 7'h18}} & {30'h0,abstractauto_reg[1:0]})    |
                                    ({32{dmi_reg_addr == 7'h40}} & haltsum0_reg[31:0])   |
                                    ({32{dmi_reg_addr == 7'h38}} & sbcs_reg[31:0])       |
                                    ({32{dmi_reg_addr == 7'h39}} & sbaddress0_reg[31:0]) |
                                    ({32{dmi_reg_addr == 7'h3c}} & sbdata0_reg[31:0])    |
                                    ({32{dmi_reg_addr == 7'h3d}} & sbdata1_reg[31:0]);


   // Ack will use the power on reset only otherwise there won't be any ack until dmactive is 1
   rvdffe #(32)             dmi_rddata_reg   (.din(dmi_reg_rdata_din[31:0]), .dout(dmi_reg_rdata[31:0]), .en(dmi_reg_en), .rst_l(dbg_dm_rst_l), .clk(clk), .*);

逐段解释：

* 第 L612-L624 行：read mux 覆盖 ``data0``、``data1``、``dmcontrol``、``dmstatus``、``hawindow``、``abstractcs``、``command``、``abstractauto``、``haltsum0``、``sbcs``、``sbaddress0``、``sbdata0`` 和 ``sbdata1``。每个地址通过重复 32 bit 的地址匹配 mask 与寄存器值相与后再 OR。
* 第 L614 行：读 ``dmcontrol`` 时返回 ``{2'b0, dmcontrol_reg[29], 1'b0, dmcontrol_reg[27:0]}``，注释说明 write-only 位按 0 读出。
* 第 L628 行：``dmi_reg_rdata`` 在 ``dmi_reg_en`` 时由 ``rvdffe`` 采样输出，复位使用 ``dbg_dm_rst_l``，时钟是模块输入 ``clk``。

接口关系：

* 被调用：``dmi_wrapper`` 通过 wrapper 读取 ``dmi_reg_rdata``。
* 调用：实例化 ``rvdffe``。
* 共享状态：所有 Debug Module 寄存器都通过这一 mux 暴露到 DMI 读路径。

§5  Per-hart 状态派生与主 FSM
-----------------------------

Debug 主 FSM 每个 hart 一份。每个 hart 根据 ``dmcontrol``、``hart_sel``、
``command_sel``、TLU halted/resume ack、abstract command 和 system bus 响应推进。

主 FSM 数据流如下：::

   DMI dmcontrol/command/data
          |
          v
   hart_sel / command_sel
          |
          v
   IDLE -> HALTING -> HALTED -> CORE_CMD_START -> CORE_CMD_WAIT -> CMD_DONE
                         |             |
                         |             +-> SB_CMD_START -> SB_CMD_SEND -> SB_CMD_RESP
                         |
                         +-> RESUMING -> IDLE

§5.1  Per-hart 选择与状态寄存器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成目标 hart mask、resumeack、havereset、unavailable、running、halted 和 per-hart FSM 寄存器。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L488-L515``）：

.. code-block:: systemverilog

   // Generate the per thread sel and state
   for (genvar i=0; i<pt.NUM_THREADS; i++) begin

      logic [pt.NUM_THREADS-1:0] dbg_resumeack_wren, dbg_resumeack_din;
      logic [pt.NUM_THREADS-1:0] dbg_haveresetn_wren, dbg_haveresetn;
      logic [pt.NUM_THREADS-1:0] abstractcs_busy_wren, abstractcs_busy_din;

      assign hart_sel[i] = (dmcontrol_reg[16] == 1'(i)) | (dmcontrol_reg[26] & hawindow_reg[i]);
      assign command_sel[i] = (dmcontrol_reg[16] == 1'(i));

      // Per thread halted/resumeack/havereset signal
      assign dbg_resumeack_wren[i] = ((dbg_state[i] == RESUMING) & dec_tlu_resume_ack[i]) | (dbg_resumeack[i] & resumereq & dbg_halted[i] & hart_sel[i]);
      assign dbg_resumeack_din[i]  = (dbg_state[i] == RESUMING) & dec_tlu_resume_ack[i];

      assign dbg_haveresetn_wren[i] = (dmi_reg_addr == 7'h10) & dmi_reg_wdata[28] & dmi_reg_en & dmi_reg_wr_en & ((dmi_reg_wdata[16] == 1'(i)) | (dmi_reg_wdata[26] & hawindow_reg[i])) & dmcontrol_reg[0];
      assign dbg_havereset[i]      = ~dbg_haveresetn[i];

逐段解释：

* 第 L488-L493 行：per-hart generate 块内部声明 resumeack、havereset 和 busy 的写使能与输入信号。
* 第 L495-L496 行：``hart_sel`` 支持直接 ``hartsel`` 匹配或 ``hasel`` 加 ``hawindow``；``command_sel`` 只使用 ``hartsel``。
* 第 L499-L500 行：``dbg_resumeack`` 在 ``RESUMING`` 状态收到 ``dec_tlu_resume_ack`` 时置位，在新的 ``resumereq`` 且 hart halted 时清除。
* 第 L502-L503 行：``dbg_havereset`` 是 ``dbg_haveresetn`` 的反相；写 ``dmcontrol`` bit 28 且目标 hart 匹配时更新 reset-ack 状态。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L505-L515``）：

.. code-block:: systemverilog

      assign dbg_unavailable[i] = ~rst_l_sync | dmcontrol_reg[1] | ~dec_tlu_mhartstart[i];
      assign dbg_running[i]     = ~(dbg_unavailable[i] | dbg_halted[i]);

      rvdff  #(1) dbg_halted_reg       (.din(dec_tlu_dbg_halted[i] & ~dec_tlu_mpc_halted_only[i]), .dout(dbg_halted[i]), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));
      rvdffs #(1) dbg_resumeack_reg    (.din(dbg_resumeack_din[i]), .dout(dbg_resumeack[i]), .en(dbg_resumeack_wren[i]), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));
      rvdffs #(1) dbg_haveresetn_reg   (.din(1'b1), .dout(dbg_haveresetn[i]), .en(dbg_haveresetn_wren[i]), .rst_l(rst_l), .clk(dbg_free_clk));
      rvdffs #(1) abstractcs_busy_reg  (.din(abstractcs_busy_din[i]), .dout(abstractcs_busy[i]), .en(abstractcs_busy_wren[i]), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk));
      rvdffs #($bits(state_t)) dbg_state_reg    (.din(dbg_nxtstate[i]), .dout({dbg_state[i]}), .en(dbg_state_en[i]), .rst_l(dbg_dm_rst_l & rst_l), .clk(dbg_free_clk));
      rvdffs #(1) sb_abmem_cmd_doneff  (.din(sb_abmem_cmd_done_in[i]),  .dout(sb_abmem_cmd_done[i]),  .en(sb_abmem_cmd_done_en[i]),  .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk), .*);
      rvdffs #(1) sb_abmem_data_doneff (.din(sb_abmem_data_done_in[i]), .dout(sb_abmem_data_done[i]), .en(sb_abmem_data_done_en[i]), .rst_l(dbg_dm_rst_l), .clk(dbg_free_clk), .*);

逐段解释：

* 第 L505-L506 行：hart unavailable 条件为同步后的 core reset 无效、``ndmreset`` 置位或 ``dec_tlu_mhartstart`` 未置位；running 是 not unavailable 且 not halted。
* 第 L508-L512 行：``dbg_halted`` 采样 ``dec_tlu_dbg_halted``，但排除 ``dec_tlu_mpc_halted_only``；busy 与主 FSM 状态都使用 ``dbg_free_clk`` 保存。
* 第 L513-L514 行：abstract memory command 的 command channel done 和 data channel done 分开保存，供 ``SB_CMD_SEND`` 判断 AW/W/AR 是否已经完成。

接口关系：

* 被调用：``dmstatus``、``haltsum0``、主 FSM 和 AXI abstract memory command 逻辑读取这些 per-hart 状态。
* 调用：实例化 ``rvdff``、``rvdffs``。
* 共享状态：``hart_sel`` 和 ``command_sel`` 是 DMI hart 选择到 FSM 执行的桥梁。

§5.2  ``IDLE``、``HALTING`` 与 ``HALTED``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：处理 halt request、MPC-only halted 状态、halted 停留、resume 触发和新 command 触发。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L516-L551``）：

.. code-block:: systemverilog

      // FSM to control the debug mode entry, command send/recieve, and Resume flow.
      always_comb begin
         dbg_nxtstate[i]         = IDLE;
         dbg_state_en[i]         = 1'b0;
         abstractcs_busy_wren    = 1'b0;
         abstractcs_busy_din     = 1'b0;
         dbg_halt_req[i]   = dmcontrol_wren_Q & dmcontrol_reg[31] & hart_sel[i];      // single pulse output to the core. Need to drive every time this register is written since core might be halted due to MPC
         dbg_resume_req[i] = 1'b0;                                                                        // single pulse output to the core
         dbg_sb_bus_error[i]     = 1'b0;
         data0_reg_wren2[i]      = 1'b0;
         sb_abmem_cmd_done_in[i] = 1'b0;
         sb_abmem_data_done_in[i]= 1'b0;
         sb_abmem_cmd_done_en[i] = 1'b0;
         sb_abmem_data_done_en[i]= 1'b0;


         case (dbg_state[i])
            IDLE: begin
                     dbg_nxtstate[i]      = (dbg_halted[i] | dec_tlu_mpc_halted_only[i]) ? HALTED : HALTING;         // initiate the halt command to the core
                     dbg_state_en[i]      = (dmcontrol_reg[31] & hart_sel[i]) | dbg_halted[i] | dec_tlu_mpc_halted_only[i];      // when the jtag writes the halt bit in the DM register, OR when the status indicates MPC halted

逐段解释：

* 第 L516-L530 行：FSM 每次组合计算先给所有输出默认值。默认 ``dbg_halt_req`` 由上一拍 ``dmcontrol_wren_Q``、``haltreq`` 和 ``hart_sel`` 生成，用于对 core 发送单周期 halt pulse。
* 第 L532-L536 行：``IDLE`` 在目标 hart 已 halted 或 MPC-only halted 时直接进入 ``HALTED``，否则在 ``haltreq`` 与 hart 选择命中时进入 ``HALTING``。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L536-L551``）：

.. code-block:: systemverilog

                     dbg_halt_req[i]       = dmcontrol_reg[31] & hart_sel[i];      // only when jtag has written the halt_req bit in the control. Removed debug mode qualification during MPC changes
            end
            HALTING : begin
                     dbg_nxtstate[i]      = HALTED;                                       // Goto HALTED once the core sends an ACK
                     dbg_state_en[i]      = dbg_halted[i] | dec_tlu_mpc_halted_only[i];   // core indicates halted
            end
            HALTED: begin
                     // wait for halted to go away before send to resume. Else start of new command
                      dbg_nxtstate[i]      = dbg_halted[i] ? ((resumereq & hart_sel[i]) ? RESUMING :
                                                                 (((command_reg[31:24] == 8'h2) & abmem_addr_external & hart_sel[i]) ? SB_CMD_START : CORE_CMD_START)) :
                                                                                   ((dmcontrol_reg[31] & hart_sel[i]) ? HALTING : IDLE);       // This is MPC halted case
                     dbg_state_en[i]      = (dbg_halted[i] & resumereq & hart_sel[i]) | (execute_command & command_sel[i]) | ~(dbg_halted[i] | dec_tlu_mpc_halted_only[i]);         // need to be exclusive ???
                     abstractcs_busy_wren[i] = dbg_state_en[i] & ((dbg_nxtstate[i] == CORE_CMD_START) | (dbg_nxtstate[i] == SB_CMD_START));                      // write busy when a new command was written by jtag
                     abstractcs_busy_din[i]  = 1'b1;
                     dbg_resume_req[i] = dbg_state_en[i] & (dbg_nxtstate[i] == RESUMING);                       // single cycle pulse to core if resuming
            end

逐段解释：

* 第 L536-L540 行：``HALTING`` 等待 ``dbg_halted`` 或 ``dec_tlu_mpc_halted_only``，收到后进入 ``HALTED``。
* 第 L542-L547 行：``HALTED`` 是分派点：``resumereq`` 命中目标 hart 时进入 ``RESUMING``；abstract memory command 且地址外部时进入 ``SB_CMD_START``；其它 command 进入 ``CORE_CMD_START``。如果 halted 状态消失，则根据是否还有 haltreq 回到 ``HALTING`` 或 ``IDLE``。
* 第 L548-L550 行：进入 command start 状态时置 ``abstractcs_busy``；进入 resume 时发出 ``dbg_resume_req`` 单周期 pulse。

接口关系：

* 被调用：``dmcontrol`` 写入和 TLU halted 状态驱动这一段状态转移。
* 调用：本段是组合 FSM，没有子模块实例。
* 共享状态：``resumereq``、``execute_command``、``command_reg``、``abmem_addr_external``、``hart_sel`` 和 ``command_sel`` 共同决定 ``HALTED`` 的下一跳。

§5.3  Core command、system bus command 与 resume 完成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 command 执行阶段等待 core/DMA/system bus 响应，写回 read data 或错误，并在 ``CMD_DONE`` 清 busy。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L552-L592``）：

.. code-block:: systemverilog

            CORE_CMD_START: begin
                     // Don't execute the command if cmderror or transfer=0 for abstract register access
                     dbg_nxtstate[i]      = ((|abstractcs_reg[10:8]) | ((command_reg[31:24] == 8'h0) & ~command_reg[17])) ? CMD_DONE : CORE_CMD_WAIT;     // new command sent to the core
                     dbg_state_en[i]      = dbg_cmd_valid | (|abstractcs_reg[10:8]) | ((command_reg[31:24] == 8'h0) & ~command_reg[17]);
            end
            CORE_CMD_WAIT: begin
                     dbg_nxtstate[i]      = CMD_DONE;
                     dbg_state_en[i]      = core_dbg_cmd_done;                   // go to done state for one cycle after completing current command
            end
            SB_CMD_START: begin
                     dbg_nxtstate[i]      = (|abstractcs_reg[10:8]) ? CMD_DONE : SB_CMD_SEND;
                     dbg_state_en[i]      = (dbg_bus_clk_en & ~sb_cmd_pending) | (|abstractcs_reg[10:8]);
            end
            SB_CMD_SEND: begin
                     sb_abmem_cmd_done_in[i]  = 1'b1;
                     sb_abmem_data_done_in[i] = 1'b1;
                     sb_abmem_cmd_done_en[i]  = (sb_bus_cmd_read | sb_bus_cmd_write_addr) & dbg_bus_clk_en;
                     sb_abmem_data_done_en[i] = (sb_bus_cmd_read | sb_bus_cmd_write_data) & dbg_bus_clk_en;

逐段解释：

* 第 L552-L556 行：``CORE_CMD_START`` 在已有 ``cmderr`` 或 abstract register ``transfer=0`` 时直接进入 ``CMD_DONE``；否则等 ``dbg_cmd_valid`` 成功发出后进入 ``CORE_CMD_WAIT``。
* 第 L557-L560 行：``CORE_CMD_WAIT`` 等 ``core_dbg_cmd_done``，完成后进入 ``CMD_DONE``。
* 第 L561-L564 行：``SB_CMD_START`` 等 system bus 时钟允许且普通 system bus command 不 pending，或在已有错误时直接结束。
* 第 L565-L569 行：``SB_CMD_SEND`` 分别记录 command channel 和 data channel 的完成情况。读命令用 ``sb_bus_cmd_read``，写命令拆成地址和数据两个握手。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L570-L592``）：

.. code-block:: systemverilog

                     dbg_nxtstate[i]          = SB_CMD_RESP;
                     dbg_state_en[i]          = (sb_abmem_cmd_done[i] | sb_abmem_cmd_done_en[i]) & (sb_abmem_data_done[i] | sb_abmem_data_done_en[i]) & dbg_bus_clk_en;
            end
            SB_CMD_RESP: begin
                     dbg_nxtstate[i]         = CMD_DONE;
                     dbg_state_en[i]         = (sb_bus_rsp_read | sb_bus_rsp_write) & dbg_bus_clk_en;
                     dbg_sb_bus_error[i]     = (sb_bus_rsp_read | sb_bus_rsp_write) & sb_bus_rsp_error & dbg_bus_clk_en;
                     data0_reg_wren2[i]      = dbg_state_en[i] & ~sb_abmem_cmd_write & ~dbg_sb_bus_error[i];
            end
            CMD_DONE: begin
                     dbg_nxtstate[i]         = HALTED;
                     dbg_state_en[i]         = 1'b1;
                     abstractcs_busy_wren[i] = dbg_state_en[i];                    // remove the busy bit from the abstracts ( bit 12 )
                     abstractcs_busy_din[i]  = 1'b0;
                     sb_abmem_cmd_done_in[i] = 1'b0;
                     sb_abmem_data_done_in[i]= 1'b0;
                     sb_abmem_cmd_done_en[i] = 1'b1;
                     sb_abmem_data_done_en[i]= 1'b1;
            end
            RESUMING : begin
                     dbg_nxtstate[i]      = IDLE;
                     dbg_state_en[i]      = dbg_resumeack[i];
            end

逐段解释：

* 第 L570-L572 行：``SB_CMD_SEND`` 只有在 command channel 与 data channel 都完成后才进入 ``SB_CMD_RESP``。
* 第 L573-L578 行：``SB_CMD_RESP`` 等 read 或 write 响应；若 ``sb_bus_rsp_error`` 置位则记录 ``dbg_sb_bus_error``，否则 read abstract memory command 把返回数据写入 ``data0``。
* 第 L579-L588 行：``CMD_DONE`` 固定回到 ``HALTED``，清 ``abstractcs_busy``，并清 abstract memory channel done 标志。
* 第 L589-L592 行：``RESUMING`` 等 ``dbg_resumeack`` 后回到 ``IDLE``。

接口关系：

* 被调用：``HALTED`` 分派进入这些状态。
* 调用：本段是组合 FSM，没有子模块实例。
* 共享状态：``abstractcs_reg[10:8]``、``core_dbg_cmd_done``、``sb_bus_*`` 和 ``dbg_bus_clk_en`` 是 command 完成路径的关键输入。

§6  Abstract command 载荷生成
-----------------------------

``eh2_dbg`` 将 DMI ``command`` 与 ``data`` 寄存器转换为 core abstract command。
register access 和 memory access 的地址来源不同：register access 使用 ``command_reg``
低位，memory access 使用 ``data1_reg``。

§6.1  本地与外部 abstract memory 地址
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 ``data1_reg`` 判断 abstract memory address 是否在 DCCM、ICCM 或 PIC 本地 region。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L630-L636``）：

.. code-block:: systemverilog

   assign abmem_addr[31:0]      = data1_reg[31:0];
   assign abmem_addr_core_local = (abmem_addr_in_dccm_region | abmem_addr_in_iccm_region | abmem_addr_in_pic_region);
   assign abmem_addr_external   = ~abmem_addr_core_local;

   assign abmem_addr_in_dccm_region = (abmem_addr[31:28] == pt.DCCM_REGION) & pt.DCCM_ENABLE;
   assign abmem_addr_in_iccm_region = (abmem_addr[31:28] == pt.ICCM_REGION) & pt.ICCM_ENABLE;
   assign abmem_addr_in_pic_region  = (abmem_addr[31:28] == pt.PIC_REGION);

逐段解释：

* 第 L630 行：abstract memory address 直接来自 ``data1_reg``。
* 第 L631-L632 行：地址命中 DCCM、ICCM 或 PIC 时归类为 core-local；否则 ``abmem_addr_external`` 为 1。
* 第 L634-L636 行：DCCM 和 ICCM region 判断还受 ``pt.DCCM_ENABLE``、``pt.ICCM_ENABLE`` 控制；PIC region 只比较 ``pt.PIC_REGION``。

接口关系：

* 被调用：主 FSM 在 ``HALTED`` 状态用 ``abmem_addr_external`` 决定走 ``SB_CMD_START`` 还是 ``CORE_CMD_START``。
* 调用：本段没有子模块实例。
* 共享状态：``data1_reg`` 是 DMI ``data1``、abstract memory address 和 postincrement 的共享寄存器。

§6.2  ``dbg_cmd_*`` 输出
~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 ``command_reg``、``data0_reg``、``data1_reg``、DMA ready 和错误状态生成发给 core 的 command 输出。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L638-L655``）：

.. code-block:: systemverilog

   // interface for the core
   assign dbg_cmd_addr[31:0]    = (command_reg[31:24] == 8'h2) ? data1_reg[31:0]  : {20'b0, command_reg[11:0]};
   assign dbg_cmd_wrdata[31:0]  = data0_reg[31:0];
   always_comb begin
      dbg_cmd_valid = 1'b0;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         dbg_cmd_valid  |= (dbg_state[i] == CORE_CMD_START) & ~((|abstractcs_reg[10:8]) | ((command_reg[31:24] == 8'h0) & ~command_reg[17]) | ((command_reg[31:24] == 8'h2) & abmem_addr_external)) &
                           ~((command_reg[31:24] == 8'h2) & ~dma_dbg_ready);
      end
   end
   assign dbg_cmd_tid           = dmcontrol_reg[16];
   assign dbg_cmd_write         = command_reg[16];
   assign dbg_cmd_type[1:0]     = (command_reg[31:24] == 8'h2) ? 2'b10 : {1'b0, (command_reg[15:12] == 4'b0)};
   assign dbg_cmd_size[1:0]     = command_reg[21:20];

逐段解释：

* 第 L639-L640 行：memory command 的地址来自 ``data1_reg``，register command 的地址来自 ``command_reg[11:0]``；写数据始终来自 ``data0_reg``。
* 第 L641-L647 行：``dbg_cmd_valid`` 只在某个 hart 位于 ``CORE_CMD_START`` 时可能置位，并且要求没有 ``cmderr``、register access 的 ``transfer`` 有效、memory access 不是外部地址、memory command 时 ``dma_dbg_ready`` 为 1。
* 第 L648-L651 行：``dbg_cmd_tid`` 直接来自 ``dmcontrol_reg[16]``，``dbg_cmd_write`` 来自 ``command_reg[16]``，``dbg_cmd_type`` 对 command type ``8'h2`` 输出 memory，否则根据 ``command_reg[15:12] == 4'b0`` 区分 GPR 与 CSR。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L653-L663``）：

.. code-block:: systemverilog

   assign dbg_cmd_addr_incr[3:0]  = (command_reg[31:24] == 8'h2) ? (4'h1 << sb_abmem_cmd_size[1:0]) : 4'h1;
   assign dbg_cmd_curr_addr[31:0] = (command_reg[31:24] == 8'h2) ? data1_reg[31:0]  : {16'b0, command_reg[15:0]};
   assign dbg_cmd_next_addr[31:0] = dbg_cmd_curr_addr[31:0] + {28'h0,dbg_cmd_addr_incr[3:0]};

   // Ask DMA to stop taking bus trxns since debug memory request is done
   always_comb begin
      dbg_dma_bubble = 1'b0;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         dbg_dma_bubble     |= ((((dbg_state[i] == CORE_CMD_START) & ~(|abstractcs_reg[10:8])) | (dbg_state[i] == CORE_CMD_WAIT)) & (command_reg[31:24] == 8'h2));
      end
   end

逐段解释：

* 第 L653-L655 行：postincrement 的步长对 memory command 使用 ``1 << sb_abmem_cmd_size``，对 register command 固定为 1。
* 第 L657-L663 行：``dbg_dma_bubble`` 在 memory command 的 ``CORE_CMD_START`` 或 ``CORE_CMD_WAIT`` 阶段置位，条件还要求 command type 为 ``8'h2``。这与端口注释中 "Debug needs a bubble" 对应。

接口关系：

* 被调用：DEC/DMA command 接收端消费 ``dbg_cmd_*`` 和 ``dbg_dma_bubble``。
* 调用：本段没有子模块实例。
* 共享状态：``command_reg``、``data0_reg``、``data1_reg``、``abstractcs_reg``、``dma_dbg_ready`` 和 ``dbg_state`` 共同决定 command 是否真正发出。

§7  System bus 寄存器与 FSM
---------------------------

System bus 路径有两种入口：DMI 直接访问 ``sbaddress0`` / ``sbdata0`` / ``sbcs``，
以及 abstract memory command 访问外部地址。两者最终复用同一 AXI master。

§7.1  ``sbcs``、``sbdata`` 与 ``sbaddress0`` 寄存器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实现 system bus control/status、data 和 address 寄存器，以及 readonaddr/readondata/write-data 触发条件。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L287-L315``）：

.. code-block:: systemverilog

   // system bus register
   // sbcs[31:29], sbcs - [22]:sbbusyerror, [21]: sbbusy, [20]:sbreadonaddr, [19:17]:sbaccess, [16]:sbautoincrement, [15]:sbreadondata, [14:12]:sberror, sbsize=32, 128=0, 64/32/16/8 are legal
   assign        sbcs_reg[31:29] = 3'b1;
   assign        sbcs_reg[28:23] = '0;
   assign        sbcs_reg[19:15] = {sbcs_reg_int[19], ~sbcs_reg_int[18], sbcs_reg_int[17:15]};
   assign        sbcs_reg[11:5]  = 7'h20;
   assign        sbcs_reg[4:0]   = 5'b01111;
   assign        sbcs_wren = (dmi_reg_addr ==  7'h38) & dmi_reg_en & dmi_reg_wr_en & (sb_state == SBIDLE); // & (sbcs_reg[14:12] == 3'b000);
   assign        sbcs_sbbusyerror_wren = (sbcs_wren & dmi_reg_wdata[22]) |
                                         (sbcs_reg[21] & dmi_reg_en & ((dmi_reg_wr_en & (dmi_reg_addr == 7'h39)) | (dmi_reg_addr == 7'h3c) | (dmi_reg_addr == 7'h3d)));
   assign        sbcs_sbbusyerror_din = ~(sbcs_wren & dmi_reg_wdata[22]);   // Clear when writing one

   rvdffs #(1) sbcs_sbbusyerror_reg  (.din(sbcs_sbbusyerror_din),  .dout(sbcs_reg[22]),    .en(sbcs_sbbusyerror_wren), .rst_l(dbg_dm_rst_l), .clk(sb_free_clk));
   rvdffs #(1) sbcs_sbbusy_reg       (.din(sbcs_sbbusy_din),       .dout(sbcs_reg[21]),    .en(sbcs_sbbusy_wren),      .rst_l(dbg_dm_rst_l), .clk(sb_free_clk));
   rvdffs #(1) sbcs_sbreadonaddr_reg (.din(dmi_reg_wdata[20]),     .dout(sbcs_reg[20]),    .en(sbcs_wren),             .rst_l(dbg_dm_rst_l), .clk(sb_free_clk));
   rvdffs #(5) sbcs_misc_reg         (.din({dmi_reg_wdata[19],~dmi_reg_wdata[18],dmi_reg_wdata[17:15]}),
                                      .dout(sbcs_reg_int[19:15]), .en(sbcs_wren),             .rst_l(dbg_dm_rst_l), .clk(sb_free_clk));

逐段解释：

* 第 L287-L293 行：``sbcs`` 的固定位和可写位在组合赋值中展开。``sbaccess`` 通过内部 ``sbcs_reg_int`` 保存，其中 bit 18 在写入和读出之间取反。
* 第 L294-L298 行：``sbcs`` 只在 system bus FSM 为 ``SBIDLE`` 时可写；忙时访问 ``sbaddress0``、``sbdata0`` 或 ``sbdata1`` 会设置 ``sbbusyerror``。
* 第 L299-L304 行：``sbbusyerror``、``sbbusy``、``sbreadonaddr``、``sbaccess``、``sbautoincrement``、``sbreadondata`` 和 ``sberror`` 通过 ``rvdffs`` 保存，时钟为 ``sb_free_clk``。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L306-L343``）：

.. code-block:: systemverilog

   assign sbcs_unaligned =    ((sbcs_reg[19:17] == 3'b001) &  sbaddress0_reg[0]) |
                              ((sbcs_reg[19:17] == 3'b010) &  (|sbaddress0_reg[1:0])) |
                              ((sbcs_reg[19:17] == 3'b011) &  (|sbaddress0_reg[2:0]));

   assign sbcs_illegal_size = sbcs_reg[19];    // Anything bigger than 64 bits is illegal

   assign sbaddress0_incr[3:0] = ({4{(sbcs_reg[19:17] == 3'h0)}} &  4'b0001) |
                                 ({4{(sbcs_reg[19:17] == 3'h1)}} &  4'b0010) |
                                 ({4{(sbcs_reg[19:17] == 3'h2)}} &  4'b0100) |
                                 ({4{(sbcs_reg[19:17] == 3'h3)}} &  4'b1000);

   // sbdata
   assign        sbdata0_reg_wren0   = dmi_reg_en & dmi_reg_wr_en & (dmi_reg_addr == 7'h3c);   // write data only when single read is 0
   assign        sbdata0_reg_wren1   = (sb_state == RSP_RD) & sb_state_en & ~sbcs_sberror_wren;
   assign        sbdata0_reg_wren    = sbdata0_reg_wren0 | sbdata0_reg_wren1;

逐段解释：

* 第 L306-L310 行：未对齐根据 ``sbaccess`` 与 ``sbaddress0`` 低位判断；非法 size 直接取 ``sbcs_reg[19]``。
* 第 L312-L315 行：地址自增步长随 ``sbaccess`` 为 1、2、4 或 8 字节。
* 第 L317-L324 行：``sbdata0`` 与 ``sbdata1`` 可由 DMI 写入，也可在 ``RSP_RD`` 且无错误时由 read response 更新。
* 第 L326-L343 行：``sbdata`` 的输入在 DMI 写数据与 ``sb_bus_rdata`` 之间选择；``sbaddress0`` 可由 DMI 写入或在 autoincrement 时增加。

接口关系：

* 被调用：system bus FSM 使用 ``sbreadonaddr_access``、``sbreadondata_access`` 和 ``sbdata0wr_access`` 触发事务。
* 调用：实例化 ``rvdffs`` 和 ``rvdffe``。
* 共享状态：``sbcs_reg`` 控制 size、autoincrement、readonaddr、readondata 和错误状态。

§7.2  System bus FSM 前半段
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 idle 接收 system bus 触发，检查未对齐和非法 size，并发出读写命令。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L665-L704``）：

.. code-block:: systemverilog

   assign sb_cmd_pending       = (sb_state == CMD_RD) | (sb_state == CMD_WR) | (sb_state == CMD_WR_ADDR) | (sb_state == CMD_WR_DATA) | (sb_state == RSP_RD) | (sb_state == RSP_WR);
   assign sb_abmem_cmd_pending = (dbg_state == SB_CMD_START) | (dbg_state == SB_CMD_SEND) | (dbg_state== SB_CMD_RESP);

  // system bus FSM
  always_comb begin
      sb_nxtstate            = SBIDLE;
      sb_state_en            = 1'b0;
      sbcs_sbbusy_wren       = 1'b0;
      sbcs_sbbusy_din        = 1'b0;
      sbcs_sberror_wren      = 1'b0;
      sbcs_sberror_din[2:0]  = 3'b0;
      sbaddress0_reg_wren1   = 1'b0;
      case (sb_state)
            SBIDLE: begin
                     sb_nxtstate            = sbdata0wr_access ? WAIT_WR : WAIT_RD;
                     sb_state_en            = (sbdata0wr_access | sbreadondata_access | sbreadonaddr_access) & ~(|sbcs_reg[14:12]) & ~sbcs_reg[22];
                     sbcs_sbbusy_wren       = sb_state_en;                                                 // set the single read bit if it is a singlread command
                     sbcs_sbbusy_din        = 1'b1;
                     sbcs_sberror_wren      = sbcs_wren & (|dmi_reg_wdata[14:12]);                                            // write to clear the error bits
                     sbcs_sberror_din[2:0]  = ~dmi_reg_wdata[14:12] & sbcs_reg[14:12];

逐段解释：

* 第 L665-L666 行：``sb_cmd_pending`` 表示普通 DMI system bus FSM 正在命令或响应阶段；``sb_abmem_cmd_pending`` 表示 Debug 主 FSM 正在处理外部 abstract memory command。
* 第 L669-L677 行：system bus FSM 先设置默认输出，避免组合锁存。
* 第 L678-L685 行：``SBIDLE`` 在 ``sbdata0`` 写、readondata 或 readonaddr 触发且没有 ``sberror``、没有 ``sbbusyerror`` 时进入读或写等待，并设置 ``sbbusy``。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L686-L704``）：

.. code-block:: systemverilog

            WAIT_RD: begin
                     sb_nxtstate           = (sbcs_unaligned | sbcs_illegal_size) ? DONE : CMD_RD;
                     sb_state_en           = (dbg_bus_clk_en & ~sb_abmem_cmd_pending) | sbcs_unaligned | sbcs_illegal_size;
                     sbcs_sberror_wren     = sbcs_unaligned | sbcs_illegal_size;
                     sbcs_sberror_din[2:0] = sbcs_unaligned ? 3'b011 : 3'b100;
            end
            WAIT_WR: begin
                     sb_nxtstate           = (sbcs_unaligned | sbcs_illegal_size) ? DONE : CMD_WR;
                     sb_state_en           = (dbg_bus_clk_en & ~sb_abmem_cmd_pending) | sbcs_unaligned | sbcs_illegal_size;
                     sbcs_sberror_wren     = sbcs_unaligned | sbcs_illegal_size;
                     sbcs_sberror_din[2:0] = sbcs_unaligned ? 3'b011 : 3'b100;
            end
            CMD_RD : begin
                     sb_nxtstate           = RSP_RD;
                     sb_state_en           = sb_bus_cmd_read & dbg_bus_clk_en;
            end
            CMD_WR : begin
                     sb_nxtstate           = (sb_bus_cmd_write_addr & sb_bus_cmd_write_data) ? RSP_WR : (sb_bus_cmd_write_data ? CMD_WR_ADDR : CMD_WR_DATA);
                     sb_state_en           = (sb_bus_cmd_write_addr | sb_bus_cmd_write_data) & dbg_bus_clk_en;

逐段解释：

* 第 L686-L697 行：读写等待状态都会先检查未对齐和非法 size；若有错误则直接进入 ``DONE`` 并写 ``sberror`` 为 ``3'b011`` 或 ``3'b100``。
* 第 L698-L701 行：``CMD_RD`` 在 AXI AR 握手 ``sb_bus_cmd_read`` 时进入 ``RSP_RD``。
* 第 L702-L704 行：``CMD_WR`` 支持 AW 与 W 同拍完成；若只有一边完成，则进入 ``CMD_WR_ADDR`` 或 ``CMD_WR_DATA`` 等待另一边。

接口关系：

* 被调用：``sbcs`` 触发信号进入本 FSM。
* 调用：本段是组合 FSM，没有子模块实例。
* 共享状态：``dbg_bus_clk_en`` 和 ``sb_abmem_cmd_pending`` 保证普通 DMI system bus 访问不会和外部 abstract memory command 同时推进。

§7.3  System bus FSM 后半段
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：等待剩余写 channel、处理读写响应、清 busy，并在成功时执行 ``sbaddress0`` 自增。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L706-L745``）：

.. code-block:: systemverilog

            CMD_WR_ADDR : begin
                     sb_nxtstate           = RSP_WR;
                     sb_state_en           = sb_bus_cmd_write_addr & dbg_bus_clk_en;
            end
            CMD_WR_DATA : begin
                     sb_nxtstate           = RSP_WR;
                     sb_state_en           = sb_bus_cmd_write_data & dbg_bus_clk_en;
            end
            RSP_RD: begin
                     sb_nxtstate           = DONE;
                     sb_state_en           = sb_bus_rsp_read & dbg_bus_clk_en;
                     sbcs_sberror_wren     = sb_state_en & sb_bus_rsp_error;
                     sbcs_sberror_din[2:0] = 3'b010;
            end
            RSP_WR: begin
                     sb_nxtstate           = DONE;
                     sb_state_en           = sb_bus_rsp_write & dbg_bus_clk_en;
                     sbcs_sberror_wren     = sb_state_en & sb_bus_rsp_error;
                     sbcs_sberror_din[2:0] = 3'b010;
            end
            DONE: begin
                     sb_nxtstate            = SBIDLE;

逐段解释：

* 第 L706-L713 行：如果写命令的 AW 或 W 未同拍完成，FSM 会分别在 ``CMD_WR_ADDR`` 或 ``CMD_WR_DATA`` 等待剩余 channel 握手。
* 第 L714-L724 行：``RSP_RD`` 和 ``RSP_WR`` 在读/写响应握手后进入 ``DONE``；若 ``sb_bus_rsp_error`` 为 1，则 ``sberror`` 写入 ``3'b010``。
* 第 L726 行开始：``DONE`` 负责收尾，完整清 busy 与地址自增逻辑在下一片段继续。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L726-L745``）：

.. code-block:: systemverilog

            DONE: begin
                     sb_nxtstate            = SBIDLE;
                     sb_state_en            = 1'b1;
                     sbcs_sbbusy_wren       = 1'b1;                           // reset the single read
                     sbcs_sbbusy_din        = 1'b0;
                     sbaddress0_reg_wren1   = sbcs_reg[16] & (sbcs_reg[14:12] == 3'b0);    // auto increment was set and no error. Update to new address after completing the current command
            end
            default : begin
                     sb_nxtstate            = SBIDLE;
                     sb_state_en            = 1'b0;
                     sbcs_sbbusy_wren       = 1'b0;
                     sbcs_sbbusy_din        = 1'b0;
                     sbcs_sberror_wren      = 1'b0;
                     sbcs_sberror_din[2:0]  = 3'b0;
                     sbaddress0_reg_wren1   = 1'b0;
           end
         endcase
   end // always_comb begin

   rvdffs #($bits(sb_state_t)) sb_state_reg (.din(sb_nxtstate), .dout({sb_state}), .en(sb_state_en), .rst_l(dbg_dm_rst_l), .clk(sb_free_clk));

逐段解释：

* 第 L726-L732 行：``DONE`` 无条件推进回 ``SBIDLE``，清 ``sbbusy``，并在 ``sbautoincrement`` 置位且没有 ``sberror`` 时写回递增后的 ``sbaddress0``。
* 第 L733-L741 行：default 分支把 FSM 拉回 ``SBIDLE``，同时清除所有写使能。
* 第 L745 行：``sb_state`` 通过 ``rvdffs`` 保存，复位为 ``dbg_dm_rst_l``，时钟为 ``sb_free_clk``。

接口关系：

* 被调用：AXI 输出逻辑读取 ``sb_state`` 生成 valid。
* 调用：实例化 ``rvdffs`` 保存 system bus FSM 状态。
* 共享状态：``sb_state``、``sbcs_reg``、``sb_bus_rsp_error`` 和 ``sbaddress0_reg_wren1`` 决定 system bus 事务完成后的寄存器状态。

§8  AXI system bus 输出
-----------------------

``eh2_dbg`` 的 system bus AXI master 同时服务普通 DMI system bus 命令和外部 abstract
memory command。选择逻辑优先使用 abstract memory command 的 valid/pending 状态，
否则使用 ``sb_state`` 生成的普通 system bus 命令。

§8.1  普通命令与 abstract memory command 复用
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 abstract memory command 与普通 system bus command 合成为 AXI 地址、size 和写数据。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L747-L776``）：

.. code-block:: systemverilog

   assign sb_abmem_cmd_write      = command_reg[16];
   assign sb_abmem_cmd_size[2:0]  = {1'b0, command_reg[21:20]};
   assign sb_abmem_cmd_addr[31:0] = abmem_addr[31:0];
   assign sb_abmem_cmd_wdata[31:0] = data0_reg[31:0];

   assign sb_cmd_size[2:0]   = sbcs_reg[19:17];
   assign sb_cmd_wdata[63:0] = {sbdata1_reg[31:0], sbdata0_reg[31:0]};
   assign sb_cmd_addr[31:0]  = sbaddress0_reg[31:0];

   always_comb begin
      sb_abmem_cmd_awvalid = 1'b0;
      sb_abmem_cmd_wvalid  = 1'b0;
      sb_abmem_cmd_arvalid = 1'b0;
      sb_abmem_read_pend   = 1'b0;
      for (int i=0; i<pt.NUM_THREADS; i++) begin
         sb_abmem_cmd_awvalid    |= (dbg_state[i] == SB_CMD_SEND) & sb_abmem_cmd_write & ~sb_abmem_cmd_done[i];
         sb_abmem_cmd_wvalid     |= (dbg_state[i] == SB_CMD_SEND) & sb_abmem_cmd_write & ~sb_abmem_data_done[i];
         sb_abmem_cmd_arvalid    |= (dbg_state[i] == SB_CMD_SEND) & ~sb_abmem_cmd_write & ~sb_abmem_cmd_done[i] & ~sb_abmem_data_done[i];

逐段解释：

* 第 L747-L750 行：abstract memory command 的 write、size、address 和 wdata 分别来自 ``command_reg``、``abmem_addr`` 和 ``data0_reg``。
* 第 L752-L754 行：普通 DMI system bus command 的 size、wdata 和 address 来自 ``sbcs_reg``、``sbdata1/0`` 和 ``sbaddress0_reg``。
* 第 L756-L766 行：abstract memory command 在 ``SB_CMD_SEND`` 状态产生 AW/W/AR valid，并用 per-hart ``sb_abmem_cmd_done`` 与 ``sb_abmem_data_done`` 避免重复发出已完成 channel。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L769-L776``）：

.. code-block:: systemverilog

   assign sb_cmd_awvalid     = ((sb_state == CMD_WR) | (sb_state == CMD_WR_ADDR));
   assign sb_cmd_wvalid      = ((sb_state == CMD_WR) | (sb_state == CMD_WR_DATA));
   assign sb_cmd_arvalid     = (sb_state == CMD_RD);
   assign sb_read_pend       = (sb_state == RSP_RD);

   assign sb_axi_size[2:0]    = (sb_abmem_cmd_awvalid | sb_abmem_cmd_wvalid | sb_abmem_cmd_arvalid | sb_abmem_read_pend) ? sb_abmem_cmd_size[2:0] : sb_cmd_size[2:0];
   assign sb_axi_addr[31:0]   = (sb_abmem_cmd_awvalid | sb_abmem_cmd_wvalid | sb_abmem_cmd_arvalid | sb_abmem_read_pend) ? sb_abmem_cmd_addr[31:0] : sb_cmd_addr[31:0];
   assign sb_axi_wrdata[63:0] = (sb_abmem_cmd_awvalid | sb_abmem_cmd_wvalid) ? {2{sb_abmem_cmd_wdata[31:0]}} : sb_cmd_wdata[63:0];

逐段解释：

* 第 L769-L772 行：普通 system bus command 的 valid 由 ``sb_state`` 直接决定，读响应 pending 用 ``RSP_RD`` 表示。
* 第 L774-L776 行：当 abstract memory command 发起或 read pending 时，AXI size/address 使用 abstract memory command 载荷；否则使用普通 DMI system bus 载荷。abstract memory write data 是 32 bit 数据复制两次组成 64 bit。

接口关系：

* 被调用：AXI channel 输出逻辑读取 ``sb_axi_size``、``sb_axi_addr`` 和 ``sb_axi_wrdata``。
* 调用：本段没有子模块实例。
* 共享状态：``dbg_state`` 与 ``sb_state`` 同时参与 AXI master 的 valid 生成。

§8.2  AXI 握手、请求与响应
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 AXI AW/W/AR 请求、常拉 B/R ready，并从 AXI 响应中提取 bus error 与读数据。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L778-L809``）：

.. code-block:: systemverilog

   // Generic bus response signals
   assign sb_bus_cmd_read       = sb_axi_arvalid & sb_axi_arready;
   assign sb_bus_cmd_write_addr = sb_axi_awvalid & sb_axi_awready;
   assign sb_bus_cmd_write_data = sb_axi_wvalid  & sb_axi_wready;

   assign sb_bus_rsp_read  = sb_axi_rvalid & sb_axi_rready;
   assign sb_bus_rsp_write = sb_axi_bvalid & sb_axi_bready;
   assign sb_bus_rsp_error = (sb_bus_rsp_read & (|(sb_axi_rresp[1:0]))) | (sb_bus_rsp_write & (|(sb_axi_bresp[1:0])));

   // AXI Request signals
   assign sb_axi_awvalid              = sb_abmem_cmd_awvalid | sb_cmd_awvalid;
   assign sb_axi_awaddr[31:0]         = sb_axi_addr[31:0];
   assign sb_axi_awid[pt.SB_BUS_TAG-1:0] = '0;
   assign sb_axi_awsize[2:0]          = sb_axi_size[2:0];
   assign sb_axi_awprot[2:0]          = 3'b001;
   assign sb_axi_awcache[3:0]         = 4'b1111;
   assign sb_axi_awregion[3:0]        = sb_axi_addr[31:28];
   assign sb_axi_awlen[7:0]           = '0;
   assign sb_axi_awburst[1:0]         = 2'b01;
   assign sb_axi_awqos[3:0]           = '0;
   assign sb_axi_awlock               = '0;

逐段解释：

* 第 L778-L785 行：AXI 握手事件被归一化为 ``sb_bus_cmd_read``、``sb_bus_cmd_write_addr``、``sb_bus_cmd_write_data``、``sb_bus_rsp_read``、``sb_bus_rsp_write`` 和 ``sb_bus_rsp_error``。
* 第 L787-L799 行：AW channel valid 是 abstract memory AW 与普通 system bus AW 的 OR；AW id 固定 0，region 来自地址高 4 bit，burst 固定 ``2'b01``，len 固定 0。
* 第 L800-L809 行：W channel valid 同样 OR 两类来源；``sb_axi_wdata`` 根据 size 扩展 byte、halfword、word 或 doubleword；``sb_axi_wstrb`` 根据 size 和地址低位生成 byte lane mask。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L811-L830``）：

.. code-block:: systemverilog

   assign sb_axi_arvalid              = sb_abmem_cmd_arvalid | sb_cmd_arvalid;
   assign sb_axi_araddr[31:0]         = sb_axi_addr[31:0];
   assign sb_axi_arid[pt.SB_BUS_TAG-1:0] = '0;
   assign sb_axi_arsize[2:0]          = sb_axi_size[2:0];
   assign sb_axi_arprot[2:0]          = 3'b001;
   assign sb_axi_arcache[3:0]         = 4'b0;
   assign sb_axi_arregion[3:0]        = sb_axi_addr[31:28];
   assign sb_axi_arlen[7:0]           = '0;
   assign sb_axi_arburst[1:0]         = 2'b01;
   assign sb_axi_arqos[3:0]           = '0;
   assign sb_axi_arlock               = '0;

   // AXI Response signals
   assign sb_axi_bready = 1'b1;

   assign sb_axi_rready = 1'b1;
   assign sb_bus_rdata[63:0] = ({64{sb_axi_size == 3'h0}} & ((sb_axi_rdata[63:0] >>  8*sb_axi_addr[2:0]) & 64'hff))       |
                               ({64{sb_axi_size == 3'h1}} & ((sb_axi_rdata[63:0] >> 16*sb_axi_addr[2:1]) & 64'hffff))    |
                               ({64{sb_axi_size == 3'h2}} & ((sb_axi_rdata[63:0] >> 32*sb_axi_addr[2]) & 64'hffff_ffff)) |
                               ({64{sb_axi_size == 3'h3}} & sb_axi_rdata[63:0]);

逐段解释：

* 第 L811-L821 行：AR channel 的 valid 是 abstract memory AR 与普通 system bus AR 的 OR；AR id 固定 0，region 也来自地址高 4 bit，cache 固定 ``4'b0``。
* 第 L823-L826 行：B 和 R ready 都固定为 1，因此 ``eh2_dbg`` 不对 system bus 响应施加 backpressure。
* 第 L827-L830 行：``sb_bus_rdata`` 根据 size 和地址低位右移、掩码或直接取 64 bit，用于写回 ``sbdata`` 或 ``data0``。

接口关系：

* 被调用：system bus FSM 和 Debug 主 FSM 读取 ``sb_bus_*`` 握手与响应信号。
* 调用：本段没有子模块实例。
* 共享状态：``sb_axi_size`` 与 ``sb_axi_addr`` 同时影响 write strobe 和 read data extraction。

§9  RTL 断言
------------

``eh2_dbg`` 在 ``RV_ASSERT_ON`` 打开时包含 3 类断言：resume ack 不能与 halted 同时有效、
halt request 不能连续保持、halt request 与 resume request 不能同拍同时为 1。

§9.1  ``RV_ASSERT_ON`` 断言块
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在仿真或形式环境启用断言时约束 halt/resume 握手的基本互斥与 pulse 行为。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L833-L843``）：

.. code-block:: systemverilog

   `ifdef RV_ASSERT_ON
   // assertion.
   //  when the resume_ack is asserted then the dec_tlu_dbg_halted should be 0
      for (genvar i=0; i<pt.NUM_THREADS; i++) begin
         dm_check_resume_and_halted: assert property (@(posedge clk)  disable iff(~rst_l) (~dec_tlu_resume_ack[i] | ~dec_tlu_dbg_halted[i]));

         assert_b2b_haltreq: assert property (@(posedge clk) disable iff (~rst_l) (##1 dbg_halt_req[i] |=> ~dbg_halt_req[i]));
         assert_halt_resume_onehot: assert #0 ($onehot0({dbg_halt_req[i], dbg_resume_req[i]}));
      end

   `endif

逐段解释：

* 第 L833-L836 行：断言块只在 ``RV_ASSERT_ON`` 宏定义时编译；断言按 ``pt.NUM_THREADS`` 为每个 hart 生成。
* 第 L837 行：``dm_check_resume_and_halted`` 要求 ``dec_tlu_resume_ack[i]`` 为 1 时 ``dec_tlu_dbg_halted[i]`` 为 0。
* 第 L839 行：``assert_b2b_haltreq`` 检查 ``dbg_halt_req[i]`` 不能在下一拍继续为 1，符合前文端口注释中的 pulse 语义。
* 第 L840 行：``assert_halt_resume_onehot`` 用 ``$onehot0`` 检查 ``dbg_halt_req`` 与 ``dbg_resume_req`` 不同时有效。

接口关系：

* 被调用：启用 ``RV_ASSERT_ON`` 的仿真或形式构建会编译这些断言。
* 调用：SystemVerilog assertion 原语。
* 共享状态：断言读取 ``dec_tlu_resume_ack``、``dec_tlu_dbg_halted``、``dbg_halt_req`` 和 ``dbg_resume_req``。

§10  行为汇总
-------------

``eh2_dbg`` 的整体行为可以按 DMI 访问类型归纳：

* 写 ``dmcontrol`` 地址 ``7'h10``：保存 ``haltreq``、``resumereq``、``ackhavereset``、``hasel``、``hartsel``、``ndmreset`` 和 ``dmactive``，并通过 per-hart FSM 发起 halt 或 resume。
* 写 ``command`` 地址 ``7'h17``：在目标 hart halted 且无 busy/error 条件满足时触发 ``execute_command``，随后由 ``HALTED`` 分派到 core command 或外部 system bus command。
* 访问 ``data0`` / ``data1``：作为 abstract command 数据寄存器，也可在 ``abstractauto`` bit 置位时触发 command。
* 访问 ``sbcs`` / ``sbaddress0`` / ``sbdata0`` / ``sbdata1``：驱动独立 system bus FSM，最终通过 AXI single-beat 读写外部 system bus。
* memory abstract command：若地址命中 DCCM、ICCM 或 PIC region，则作为 core-local memory command 发给 core/DMA 路径；若是外部地址，则走 ``SB_CMD_*`` 状态和 AXI system bus 路径。

§11  参考资料
-------------

* 关联章节：:ref:`debug`、:doc:`dmi`、:doc:`wrapper`
* 关联 ADR：:ref:`adr-0008`、:ref:`adr-0012`、:ref:`adr-0020`
* 源文件：``/home/host/eh2-veri/rtl/design/dbg/eh2_dbg.sv``
* 顶层实例：``/home/host/eh2-veri/rtl/design/eh2_veer.sv``
* DMI wrapper 连接：``/home/host/eh2-veri/rtl/design/eh2_veer_wrapper.sv``
* RTL filelist：``/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f``

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

§12  v2-23 ``eh2_dbg.sv`` 全文段落级精读
--------------------------------------------------------------------------------

v2-23 将 debug module 顶层 RTL 全文纳入本页。前文已经按 DMI register、hart FSM、
abstract command、system bus 和 assertion 分段解释，本节提供完整源码视图，确保
debug 路径不只停留在片段级引用。

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dbg/eh2_dbg.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dbg/eh2_dbg.sv:全文

逐段精读：

* L1-L23：文件头和模块注释。``eh2_dbg`` 是 RISC-V debug module 的 core 侧实现，
  DMI/JTAG wrapper 只负责把访问送进这里。
* L24-L130：模块参数与端口。输入覆盖 DMI register access、core halted/running/reset、
  abstract command completion、DCCM/ICCM/PIC region 和 system bus AXI response；输出覆盖
  halt/resume/reset、core debug command、DMI read data 和 system bus AXI master。
* L131-L264：DMI register、DMCONTROL/DMSTATUS、abstract command、system bus、
  per-hart state 和 clock/reset 内部信号声明。debug 行为的持久状态都在这里建立。
* L265-L348：复位同步、clock enable、debug module reset、``sbcs``、``sbaddress``、
  ``sbdata`` 和 system bus auto-read/write 组合逻辑。该段解释 system bus register 访问
  如何触发 AXI 事务。
* L349-L429：``dmcontrol``、``dmstatus``、``abstractcs``、``command`` 和 ``abstractauto``。
  busy/error、hart selection、postincrement、postexec 和 command trigger 都在这里形成。
* L430-L494：execute command、hawindow、data0/data1 写入和 core return data 合并。abstract
  register/memory command 的数据通路从这一段进入后续 FSM。
* L495-L609：每线程 debug hart FSM。``IDLE``、``HALTING``、``HALTED``、``RESUMING``、
  ``CMD_*`` 和 ``SB_CMD_*`` 状态决定 halt/resume、core-local command 与 system bus command
  的优先级。
* L612-L657：DMI read mux、abstract memory 地址 region 判断和 core debug command 打包。
  读 ``dmcontrol``、``dmstatus``、``data0``、``sbcs`` 等 register 的返回值由这段确定。
* L658-L743：system bus FSM。它处理 ``sbreadonaddr``、``sbreadondata``、``sbdata0`` 写触发、
  read/write response、error 和 busy 状态。
* L747-L830：abstract memory command 与普通 system bus command 合流成 AXI AW/W/AR/R/B
  single-beat 端口，并按 ``sb_axi_size`` 生成 write strobe 与 read data 对齐。
* L833-L844：``RV_ASSERT_ON`` 断言和 module 结束。断言约束 resume/halted 互斥、
  halt request pulse 行为和 halt/resume one-hot。
