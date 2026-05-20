.. _appendix_a_rtl_dmi:
.. _appendix_a_rtl/dmi:

JTAG / DMI 模块 — 详细参考
===========================

:status: draft
:source: rtl/design/dmi/
:last-reviewed: 2026-05-19

§1  源文件边界与数据流
----------------------

本章描述 :file:`rtl/design/dmi/` 目录下实际存在的三个 Verilog 文件：
``dmi_wrapper.v``、``dmi_jtag_to_core_sync.v`` 和 ``rvjtag_tap.v``。旧文档中提到的
``eh2_dmi_jtag.sv``、``eh2_dmi_top.sv``、``eh2_dmi_wrapper.sv`` 在当前工作区不存在，
因此本章不沿用这些文件名。

DMI 路径在 wrapper 层的实际数据流如下：

.. code-block:: text

   JTAG pads
   trst_n/tck/tms/tdi
          │
          ▼
   dmi_wrapper
          │
          ├── rvjtag_tap
          │       ├── wr_addr / wr_data
          │       ├── wr_en / rd_en
          │       ├── tdo / tdoEnable
          │       └── dmi_reset / dmi_hard_reset
          │
          └── dmi_jtag_to_core_sync
                  ├── reg_en
                  └── reg_wr_en
                         │
                         ▼
   eh2_veer_wrapper local DMI wires
                         │
                         ▼
   eh2_veer / eh2_dbg dmi_reg_* interface

该图只表达源码中的实例化和连线：``rvjtag_tap`` 解析 JTAG TAP 状态、IR/DR、shift
register 和 DMI data/control 字段；``dmi_jtag_to_core_sync`` 将 JTAG 侧 ``rd_en``、
``wr_en`` 同步成 core clock 下的单周期 ``reg_en``、``reg_wr_en``；``eh2_dbg`` 再按
``dmi_reg_addr`` 选择 debug module 寄存器读写。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L62-L68``）：

.. code-block:: text

   // Debug
   rtl/design/dbg/eh2_dbg.sv

   // DMI (Verilog)
   rtl/design/dmi/dmi_jtag_to_core_sync.v
   rtl/design/dmi/dmi_wrapper.v
   rtl/design/dmi/rvjtag_tap.v

逐段解释：

* 第 L62-L63 行：``eh2_dbg.sv`` 作为 Debug RTL 编译输入出现。DMI wrapper 最终输出的
  ``dmi_reg_*`` 信号由该 debug 模块消费。
* 第 L65-L68 行：DMI 目录下三个文件被标记为 Verilog 输入。本文不会描述不存在的
  ``eh2_dmi_*`` SystemVerilog 文件。

接口关系：

* 被引用：:file:`dv/uvm/core_eh2/eh2_rtl.f` 将 DMI 文件纳入 RTL 编译列表。
* 调用：filelist 不调用逻辑，只决定编译输入。
* 共享状态：DMI 与 Debug 的共享接口是 ``dmi_reg_en``、``dmi_reg_addr``、
  ``dmi_reg_wr_en``、``dmi_reg_wdata`` 和 ``dmi_reg_rdata``。

§2  ``dmi_wrapper`` 顶层封装
-----------------------------

``dmi_wrapper`` 是 JTAG pad 与 core DMI 寄存器接口之间的封装层。它实例化
``rvjtag_tap`` 和 ``dmi_jtag_to_core_sync``，并把 TAP 侧生成的地址、写数据、读写 enable
转换成处理器侧 ``reg_*`` 信号。

§2.1  ``dmi_wrapper`` 端口 — JTAG pad 与 processor signals
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明外部 JTAG 五线接口、processor clock/reset、JTAG ID、DMI 读写数据和 hard reset
输出。该模块本身不解析 debug register 地址，地址解析在 ``rvjtag_tap`` 和 ``eh2_dbg`` 中完成。

关键代码（``rtl/design/dmi/dmi_wrapper.v:L24-L44``）：

.. code-block:: systemverilog

   module dmi_wrapper(

     // JTAG signals
     input              trst_n,              // JTAG reset
     input              tck,                 // JTAG clock
     input              tms,                 // Test mode select
     input              tdi,                 // Test Data Input
     output             tdo,                 // Test Data Output
     output             tdoEnable,           // Test Data Output enable

     // Processor Signals
     input              core_rst_n,          // Core reset
     input              core_clk,            // Core clock
     input [31:1]       jtag_id,             // JTAG ID
     input [31:0]       rd_data,             // 32 bit Read data from  Processor
     output [31:0]      reg_wr_data,         // 32 bit Write data to Processor
     output [6:0]       reg_wr_addr,         // 7 bit reg address to Processor
     output             reg_en,              // 1 bit  Read enable to Processor
     output             reg_wr_en,           // 1 bit  Write enable to Processor
     output             dmi_hard_reset
   );

逐段解释：

* 第 L24 行：模块名为 ``dmi_wrapper``，与 :file:`eh2_veer_wrapper.sv` 中的实例名相同。
* 第 L27-L32 行：JTAG 侧端口包括 ``trst_n``、``tck``、``tms``、``tdi``、``tdo`` 和
  ``tdoEnable``。这些信号直接连接到 ``rvjtag_tap``。
* 第 L35-L43 行：processor 侧端口包括 core reset/clock、``jtag_id``、32-bit 读数据、
  32-bit 写数据、7-bit 地址、access enable、write enable 和 ``dmi_hard_reset``。
* 第 L41 行注释写作 “Read enable”，但源码后续第 L86 行把该端口连接到
  ``dmi_jtag_to_core_sync.reg_en``；该信号实际由读或写脉冲 OR 生成。

接口关系：

* 被实例化：``eh2_veer_wrapper`` 在 wrapper 顶层实例化 ``dmi_wrapper``。
* 调用：本模块实例化 ``rvjtag_tap`` 和 ``dmi_jtag_to_core_sync``。
* 共享状态：``rd_data`` 来自处理器 debug 读数据，``reg_wr_data``、``reg_wr_addr``、
  ``reg_en`` 和 ``reg_wr_en`` 进入处理器 debug 接口。

§2.2  ``rvjtag_tap`` 实例 — JTAG 侧解析与固定 DMI 参数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：连接 JTAG pad、DMI 写地址/写数据、读写 enable、读数据和 DMI control/status 参数。
该实例把 ``rd_status``、``idle``、``dmi_stat`` 固定为 0，把 ``version`` 固定为 ``4'h1``。

关键代码（``rtl/design/dmi/dmi_wrapper.v:L50-L76``）：

.. code-block:: systemverilog

     //Wire Declaration
     wire                     rd_en;
     wire                     wr_en;
     wire                     dmireset;


     //jtag_tap instantiation
    rvjtag_tap i_jtag_tap(
      .trst(trst_n),                      // dedicated JTAG TRST (active low) pad signal or asynchronous active low power on reset
      .tck(tck),                          // dedicated JTAG TCK pad signal
      .tms(tms),                          // dedicated JTAG TMS pad signal
      .tdi(tdi),                          // dedicated JTAG TDI pad signal
      .tdo(tdo),                          // dedicated JTAG TDO pad signal
      .tdoEnable(tdoEnable),              // enable for TDO pad
      .wr_data(reg_wr_data),              // 32 bit Write data
      .wr_addr(reg_wr_addr),              // 7 bit Write address
      .rd_en(rd_en),                      // 1 bit  read enable
      .wr_en(wr_en),                      // 1 bit  Write enable
      .rd_data(rd_data),                  // 32 bit Read data
      .rd_status(2'b0),
      .idle(3'h0),                         // no need to wait to sample data
      .dmi_stat(2'b0),                     // no need to wait or error possible
      .version(4'h1),                      // debug spec 0.13 compliant
      .jtag_id(jtag_id),
      .dmi_hard_reset(dmi_hard_reset),
      .dmi_reset(dmireset)
   );

逐段解释：

* 第 L51-L53 行：wrapper 内部只声明三个中间线：``rd_en``、``wr_en`` 和 ``dmireset``。
  ``dmireset`` 只连接 TAP 输出，没有在 wrapper 中继续使用。
* 第 L57-L63 行：JTAG pad 直接穿入 TAP，并由 TAP 输出 ``tdo`` 与 ``tdoEnable``。
* 第 L64-L68 行：TAP 输出 ``wr_data``、``wr_addr``、``rd_en``、``wr_en``，并接收处理器侧
  ``rd_data``。
* 第 L69-L72 行：``rd_status``、``idle``、``dmi_stat`` 被固定为 0，``version`` 固定为
  ``4'h1``。文档只能据此说明本实例没有从 wrapper 外部传入这些状态。
* 第 L73-L75 行：``jtag_id``、``dmi_hard_reset`` 和 ``dmi_reset`` 连接到 TAP；其中
  ``dmi_hard_reset`` 是 wrapper 输出，``dmi_reset`` 仅在本地接线。

接口关系：

* 被调用：``dmi_wrapper`` 实例化 ``rvjtag_tap``。
* 调用：TAP 内部使用 JTAG TAP 状态机、IR、DR、shift register。
* 共享状态：``rd_en``、``wr_en`` 是 TAP 到 core synchronizer 的跨 clock 事件源。

§2.3  ``dmi_jtag_to_core_sync`` 实例 — 读写事件进入 core clock
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 JTAG TAP 产生的 ``rd_en`` 和 ``wr_en`` 同步到 ``core_clk``，输出处理器侧
``reg_en`` 和 ``reg_wr_en``。

关键代码（``rtl/design/dmi/dmi_wrapper.v:L79-L88``）：

.. code-block:: systemverilog

     // dmi_jtag_to_core_sync instantiation
     dmi_jtag_to_core_sync i_dmi_jtag_to_core_sync(
       .wr_en(wr_en),                          // 1 bit  Write enable
       .rd_en(rd_en),                          // 1 bit  Read enable

       .rst_n(core_rst_n),
       .clk(core_clk),
       .reg_en(reg_en),                          // 1 bit  Write interface bit
       .reg_wr_en(reg_wr_en)                          // 1 bit  Write enable
     );

逐段解释：

* 第 L80 行：实例名是 ``i_dmi_jtag_to_core_sync``，实例化模块为
  ``dmi_jtag_to_core_sync``。
* 第 L81-L82 行：输入 ``wr_en`` 和 ``rd_en`` 来自 TAP，在 JTAG ``tck`` 域产生。
* 第 L84-L85 行：同步器使用 processor 侧 ``core_rst_n`` 和 ``core_clk``。
* 第 L86-L87 行：输出 ``reg_en`` 和 ``reg_wr_en`` 接到 wrapper 端口，再进入
  ``eh2_dbg`` 的 DMI 寄存器接口。

接口关系：

* 被调用：``dmi_wrapper`` 实例化同步器。
* 调用：同步器内部使用两个 3-bit shift register 做边沿检测。
* 共享状态：``reg_en`` 由读或写事件生成，``reg_wr_en`` 只由写事件生成。

§3  ``dmi_jtag_to_core_sync`` 同步器
------------------------------------

``dmi_jtag_to_core_sync`` 的实现很小，但它定义了 DMI 读写事件跨入 core clock 的方式。
它不传递地址和数据，地址/数据在 TAP 的 ``dr`` 输出上直接作为组合输出连接到 wrapper；
同步器只负责 ``rd_en`` 和 ``wr_en`` 的 enable 脉冲。

§3.1  同步器端口 — 只同步读写 enable
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 JTAG 侧 ``rd_en``、``wr_en``，core 侧 reset/clock，以及处理器侧
``reg_en``、``reg_wr_en``。

关键代码（``rtl/design/dmi/dmi_jtag_to_core_sync.v:L25-L36``）：

.. code-block:: systemverilog

   module dmi_jtag_to_core_sync (
   // JTAG signals
   input       rd_en,      // 1 bit  Read Enable from JTAG
   input       wr_en,      // 1 bit  Write enable from JTAG

   // Processor Signals
   input       rst_n,      // Core reset
   input       clk,        // Core clock

   output      reg_en,     // 1 bit  Write interface bit to Processor
   output      reg_wr_en   // 1 bit  Write enable to Processor
   );

逐段解释：

* 第 L25 行：模块名为 ``dmi_jtag_to_core_sync``。
* 第 L27-L28 行：输入 ``rd_en``、``wr_en`` 来自 JTAG TAP。
* 第 L31-L32 行：同步目标域使用 ``rst_n`` 和 ``clk``，在 wrapper 实例中分别连接
  ``core_rst_n`` 和 ``core_clk``。
* 第 L34-L35 行：输出是处理器侧的 access enable 与 write enable；没有地址或数据端口。

接口关系：

* 被实例化：``dmi_wrapper`` 中的 ``i_dmi_jtag_to_core_sync``。
* 调用：内部没有子模块，只使用 always block 和组合赋值。
* 共享状态：内部 ``rden``、``wren`` shift register 保存最近三拍 enable 采样。

§3.2  边沿检测 — ``reg_en`` 与 ``reg_wr_en`` 的生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 core clock 下采样 JTAG 读写 enable，并把上升沿转成单周期 core-side 脉冲。

关键代码（``rtl/design/dmi/dmi_jtag_to_core_sync.v:L38-L61``）：

.. code-block:: systemverilog

   wire        c_rd_en;
   wire        c_wr_en;
   reg [2:0]   rden, wren;


   // Outputs
   assign reg_en    = c_wr_en | c_rd_en;
   assign reg_wr_en = c_wr_en;


   // synchronizers
   always @ ( posedge clk or negedge rst_n) begin
       if(!rst_n) begin
           rden <= '0;
           wren <= '0;
       end
       else begin
           rden <= {rden[1:0], rd_en};
           wren <= {wren[1:0], wr_en};
       end
   end

   assign c_rd_en = rden[1] & ~rden[2];
   assign c_wr_en = wren[1] & ~wren[2];

逐段解释：

* 第 L38-L40 行：``c_rd_en``、``c_wr_en`` 是 core clock 域的边沿检测结果；
  ``rden``、``wren`` 是 3-bit shift register。
* 第 L44-L45 行：``reg_en`` 是读或写事件的 OR；``reg_wr_en`` 只在写事件上置位。
* 第 L49-L58 行：异步低有效 reset 清零 ``rden`` 和 ``wren``；否则每个 ``clk`` 上升沿
  将 JTAG 侧 ``rd_en``、``wr_en`` 移入 shift register。
* 第 L60-L61 行：``rden[1] & ~rden[2]`` 和 ``wren[1] & ~wren[2]`` 对采样后的 enable
  做上升沿检测。输出脉冲宽度由 core clock 采样逻辑决定。

接口关系：

* 被调用：``eh2_dbg`` 观察 ``reg_en`` 和 ``reg_wr_en``。
* 调用：无子模块调用。
* 共享状态：``reg_en`` 使能 debug 读数据寄存器，``reg_wr_en`` 参与 debug 寄存器写入条件。

§4  ``rvjtag_tap`` TAP 控制器
-----------------------------

``rvjtag_tap`` 包含 JTAG TAP 状态机、IR 寄存器、DR/shift register、TDO retiming、
DMI CS 更新和 DMI DR 输出。其参数 ``AWIDTH`` 默认为 7，因此 ``USER_DR_LENGTH`` 为
``AWIDTH + 34``，也就是地址宽度加 32-bit data、write enable、read enable。

§4.1  端口与内部状态 — ``AWIDTH`` 和 ``USER_DR_LENGTH``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 TAP 的 JTAG pad、DMI 数据端口、reset 输出、status/control 输入和内部状态。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L16-L54``）：

.. code-block:: systemverilog

   module rvjtag_tap #(
   parameter AWIDTH = 7
   )
   (
   input               trst,
   input               tck,
   input               tms,
   input               tdi,
   output   reg        tdo,
   output              tdoEnable,

   output [31:0]       wr_data,
   output [AWIDTH-1:0] wr_addr,
   output              wr_en,
   output              rd_en,

   input   [31:0]      rd_data,
   input   [1:0]       rd_status,

   output  reg         dmi_reset,
   output  reg         dmi_hard_reset,

   input   [2:0]       idle,
   input   [1:0]       dmi_stat,
   /*
   --  revisionCode        : 4'h0;
   --  manufacturersIdCode : 11'h45;
   --  deviceIdCode        : 16'h0001;
   --  order MSB .. LSB -> [4 bit version or revision] [16 bit part number] [11 bit manufacturer id] [value of 1'b1 in LSB]
   */
   input   [31:1]      jtag_id,
   input   [3:0]       version
   );

   localparam USER_DR_LENGTH = AWIDTH + 34;

逐段解释：

* 第 L16-L18 行：``AWIDTH`` 默认值为 7，对应 wrapper 中 ``reg_wr_addr[6:0]``。
* 第 L20-L25 行：JTAG pad 输入输出包括 ``trst``、``tck``、``tms``、``tdi``、``tdo``、
  ``tdoEnable``。
* 第 L27-L34 行：DMI 数据端口包括写数据、写地址、写 enable、读 enable、读数据和读状态。
* 第 L35-L39 行：TAP 输出 ``dmi_reset``、``dmi_hard_reset``，并接收 ``idle`` 与
  ``dmi_stat``。在 wrapper 实例中后两者固定为 0。
* 第 L46-L47 行：``jtag_id`` 与 ``version`` 作为 device ID 和 DTMCS 捕获数据来源。
* 第 L50-L54 行：``USER_DR_LENGTH`` 定义为 ``AWIDTH + 34``，``sr``、``nsr``、``dr`` 在
  后续声明中使用该宽度。34 位由 32-bit data 加 ``wr_en``、``rd_en`` 构成，最终第 L219 行解包。

接口关系：

* 被实例化：``dmi_wrapper`` 的 ``i_jtag_tap``。
* 调用：内部不实例化子模块。
* 共享状态：``sr`` 是 shift register，``dr`` 是更新后的 DMI data register。

§4.2  TAP 16 状态转移 — ``tms`` 驱动 next state
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实现 JTAG TAP 状态机的 next-state 组合逻辑，并在 ``tck`` 上寄存状态。
源码列出 16 个状态 localparam，状态转移完全由当前 state 和 ``tms`` 决定。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L76-L119``）：

.. code-block:: systemverilog

   localparam TEST_LOGIC_RESET_STATE = 0;
   localparam RUN_TEST_IDLE_STATE    = 1;
   localparam SELECT_DR_SCAN_STATE   = 2;
   localparam CAPTURE_DR_STATE       = 3;
   localparam SHIFT_DR_STATE         = 4;
   localparam EXIT1_DR_STATE         = 5;
   localparam PAUSE_DR_STATE         = 6;
   localparam EXIT2_DR_STATE         = 7;
   localparam UPDATE_DR_STATE        = 8;
   localparam SELECT_IR_SCAN_STATE   = 9;
   localparam CAPTURE_IR_STATE       = 10;
   localparam SHIFT_IR_STATE         = 11;
   localparam EXIT1_IR_STATE         = 12;
   localparam PAUSE_IR_STATE         = 13;
   localparam EXIT2_IR_STATE         = 14;
   localparam UPDATE_IR_STATE        = 15;

   always_comb  begin
       nstate = state;
       case(state)
       TEST_LOGIC_RESET_STATE: nstate = tms ? TEST_LOGIC_RESET_STATE : RUN_TEST_IDLE_STATE;
       RUN_TEST_IDLE_STATE:    nstate = tms ? SELECT_DR_SCAN_STATE   : RUN_TEST_IDLE_STATE;
       SELECT_DR_SCAN_STATE:   nstate = tms ? SELECT_IR_SCAN_STATE   : CAPTURE_DR_STATE;
       CAPTURE_DR_STATE:       nstate = tms ? EXIT1_DR_STATE         : SHIFT_DR_STATE;
       SHIFT_DR_STATE:         nstate = tms ? EXIT1_DR_STATE         : SHIFT_DR_STATE;

逐段解释：

* 第 L76-L91 行：源码显式声明 16 个 TAP 状态编号，覆盖 reset、idle、DR scan 和 IR scan
  路径。
* 第 L93-L100 行：reset、idle、select/capture/shift DR 的 next state 由 ``tms`` 选择。
  例如 ``SHIFT_DR_STATE`` 在 ``tms`` 为 0 时保持 shift，为 1 时进入 ``EXIT1_DR_STATE``。

接口关系：

* 被调用：状态解码信号 ``shift_dr``、``capture_dr``、``update_dr`` 等读取 ``state``。
* 调用：读取 JTAG ``tms``。
* 共享状态：``state`` 在 ``tck`` 上更新，直接控制 IR/DR shift 和 TDO enable。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L101-L132``）：

.. code-block:: systemverilog

       EXIT1_DR_STATE:         nstate = tms ? UPDATE_DR_STATE        : PAUSE_DR_STATE;
       PAUSE_DR_STATE:         nstate = tms ? EXIT2_DR_STATE         : PAUSE_DR_STATE;
       EXIT2_DR_STATE:         nstate = tms ? UPDATE_DR_STATE        : SHIFT_DR_STATE;
       UPDATE_DR_STATE:        nstate = tms ? SELECT_DR_SCAN_STATE   : RUN_TEST_IDLE_STATE;
       SELECT_IR_SCAN_STATE:   nstate = tms ? TEST_LOGIC_RESET_STATE : CAPTURE_IR_STATE;
       CAPTURE_IR_STATE:       nstate = tms ? EXIT1_IR_STATE         : SHIFT_IR_STATE;
       SHIFT_IR_STATE:         nstate = tms ? EXIT1_IR_STATE         : SHIFT_IR_STATE;
       EXIT1_IR_STATE:         nstate = tms ? UPDATE_IR_STATE        : PAUSE_IR_STATE;
       PAUSE_IR_STATE:         nstate = tms ? EXIT2_IR_STATE         : PAUSE_IR_STATE;
       EXIT2_IR_STATE:         nstate = tms ? UPDATE_IR_STATE        : SHIFT_IR_STATE;
       UPDATE_IR_STATE:        nstate = tms ? SELECT_DR_SCAN_STATE   : RUN_TEST_IDLE_STATE;
       default:                nstate = TEST_LOGIC_RESET_STATE;
       endcase
   end

   always @ (posedge tck or negedge trst) begin
       if(!trst) state <= TEST_LOGIC_RESET_STATE;
       else state <= nstate;
   end

   assign jtag_reset = state == TEST_LOGIC_RESET_STATE;
   assign shift_dr   = state == SHIFT_DR_STATE;
   assign pause_dr   = state == PAUSE_DR_STATE;
   assign update_dr  = state == UPDATE_DR_STATE;
   assign capture_dr = state == CAPTURE_DR_STATE;
   assign shift_ir   = state == SHIFT_IR_STATE;
   assign pause_ir   = state == PAUSE_IR_STATE;
   assign update_ir  = state == UPDATE_IR_STATE;
   assign capture_ir = state == CAPTURE_IR_STATE;

   assign tdoEnable = shift_dr | shift_ir;

逐段解释：

* 第 L101-L112 行：exit、pause、update 和 IR scan 相关状态完成 next-state 表。default
  回到 ``TEST_LOGIC_RESET_STATE``。
* 第 L116-L119 行：``state`` 在 ``tck`` 上升沿更新；``trst`` 低有效时强制进入 reset 状态。
* 第 L121-L129 行：状态解码为 ``jtag_reset``、``shift_dr``、``update_dr``、
  ``capture_dr``、``shift_ir``、``update_ir`` 等控制信号。
* 第 L131 行：``tdoEnable`` 只在 DR shift 或 IR shift 状态为真。

接口关系：

* 被调用：IR 寄存器、shift register、DMI CS、DR 寄存器和 TDO retiming 都读取这些状态解码。
* 调用：读取 ``tck``、``trst``、``tms``。
* 共享状态：``tdoEnable`` 直接作为 wrapper 的 JTAG output enable。

§4.3  IR 寄存器与 DR 选择 — ``devid_sel``、``dr_en[0]``、``dr_en[1]``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 IR update 时装载指令，并根据 IR 值选择 device ID、DTMCS 或 DMI access 数据寄存器。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L137-L149``）：

.. code-block:: systemverilog

   always @ (negedge tck or negedge trst) begin
      if (!trst) ir <= 5'b1;
      else begin
         if (jtag_reset) ir <= 5'b1;
         else if (update_ir) ir <= (sr[4:0] == '0) ? 5'h1f :sr[4:0];
      end
   end


   assign devid_sel  = ir == 5'b00001;
   assign dr_en[0]   = ir == 5'b10000;
   assign dr_en[1]   = ir == 5'b10001;

逐段解释：

* 第 L137-L142 行：IR 在 ``negedge tck`` 上更新。reset 或 ``jtag_reset`` 时 IR 为
  ``5'b1``；``update_ir`` 时，如果 ``sr[4:0]`` 为 0，则 IR 写入 ``5'h1f``，否则写入
  ``sr[4:0]``。
* 第 L146 行：``devid_sel`` 在 IR 等于 ``5'b00001`` 时有效。
* 第 L147-L148 行：``dr_en[0]`` 和 ``dr_en[1]`` 分别对应 IR ``5'b10000`` 和
  ``5'b10001``。源码没有给这两个 IR 值命名，本文只按信号名描述。

接口关系：

* 被调用：shift register 的 capture/shift 分支读取 ``devid_sel`` 和 ``dr_en``。
* 调用：读取 ``sr``、``update_ir``、``jtag_reset``。
* 共享状态：IR 决定 DR capture 内容和 shift 长度行为。

§4.4  Shift register — DR/IR capture 与 shift
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 ``tck`` 上维护 ``sr``，并根据当前 TAP 状态、IR 选择和 TDI 生成 ``nsr``。
DR capture 时可装入 DTMCS 字段、DMI read data/status 或 JTAG ID。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L153-L186``）：

.. code-block:: systemverilog

   always @ (posedge tck or negedge trst) begin
       if(!trst)begin
           sr <= '0;
       end
       else begin
           sr <= nsr;
       end
   end

   // SR next value
   always_comb begin
       nsr = sr;
       case(1)
       shift_dr:   begin
                       case(1)
                       dr_en[1]:   nsr = {tdi, sr[USER_DR_LENGTH-1:1]};

                       dr_en[0],
                       devid_sel:  nsr = {{USER_DR_LENGTH-32{1'b0}},tdi, sr[31:1]};
                       default:    nsr = {{USER_DR_LENGTH-1{1'b0}},tdi}; // bypass
                       endcase
                   end
       capture_dr: begin
                       nsr[0] = 1'b0;
                       case(1)
                       dr_en[0]:   nsr = {{USER_DR_LENGTH-15{1'b0}}, idle, dmi_stat, abits, version};
                       dr_en[1]:   nsr = {{AWIDTH{1'b0}}, rd_data, rd_status};
                       devid_sel:  nsr = {{USER_DR_LENGTH-32{1'b0}}, jtag_id, 1'b1};
                       endcase
                   end
       shift_ir:   nsr = {{USER_DR_LENGTH-5{1'b0}},tdi, sr[4:1]};
       capture_ir: nsr = {{USER_DR_LENGTH-1{1'b0}},1'b1};

逐段解释：

* 第 L153-L160 行：``sr`` 在 ``tck`` 上升沿采样 ``nsr``；``trst`` 低有效时清零。
* 第 L163-L173 行：DR shift 时，``dr_en[1]`` 使用完整 ``USER_DR_LENGTH`` shift；
  ``dr_en[0]`` 和 ``devid_sel`` 只保留 32-bit 低段 shift；其他 IR 走 bypass 形式。
* 第 L175-L181 行：DR capture 时，``dr_en[0]`` 装入 ``idle``、``dmi_stat``、``abits``、
  ``version``；``dr_en[1]`` 装入 ``rd_data`` 和 ``rd_status``；``devid_sel`` 装入
  ``jtag_id`` 和最低位 ``1'b1``。
* 第 L183-L184 行：IR shift 只使用低 5 bit；IR capture 把最低位置 1。

接口关系：

* 被调用：TDO retiming 输出 ``sr[0]``，IR update 读取 ``sr[4:0]``，DR update 读取 ``sr``。
* 调用：读取 ``tdi``、DR/IR 状态解码、``rd_data``、``rd_status``、``idle``、
  ``dmi_stat``、``abits``、``version`` 和 ``jtag_id``。
* 共享状态：``sr`` 是 IR 和 DR 共用移位寄存器，宽度由 ``USER_DR_LENGTH`` 决定。

§4.5  TDO retiming 与 DMI CS reset 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 ``negedge tck`` 输出 ``sr[0]`` 到 ``tdo``，并在 DTMCS 更新时生成
``dmi_hard_reset`` 和 ``dmi_reset`` 单拍输出。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L188-L205``）：

.. code-block:: systemverilog

   // TDO retiming
   always @ (negedge tck ) tdo <= sr[0];

   // DMI CS register
   always @ (posedge tck or negedge trst) begin
       if(!trst) begin
           dmi_hard_reset <= 1'b0;
           dmi_reset      <= 1'b0;
       end
       else if (update_dr & dr_en[0]) begin
           dmi_hard_reset <= sr[17];
           dmi_reset      <= sr[16];
       end
       else begin
           dmi_hard_reset <= 1'b0;
           dmi_reset      <= 1'b0;
       end
   end

逐段解释：

* 第 L189 行：``tdo`` 在 ``tck`` 下降沿更新为 ``sr[0]``，与 ``tdoEnable`` 的 shift 状态配合输出。
* 第 L192-L196 行：``trst`` 低有效时 ``dmi_hard_reset`` 和 ``dmi_reset`` 清零。
* 第 L197-L200 行：当 ``update_dr`` 且 ``dr_en[0]`` 有效时，``dmi_hard_reset`` 来自
  ``sr[17]``，``dmi_reset`` 来自 ``sr[16]``。
* 第 L201-L204 行：其他周期这两个 reset 输出回到 0，因此它们是由 DTMCS update 触发的
  pulse 型输出。

接口关系：

* 被调用：wrapper 输出 ``dmi_hard_reset``；``dmi_reset`` 在 wrapper 内部接到 ``dmireset``。
* 调用：读取 ``sr``、``update_dr``、``dr_en[0]``、``tck``、``trst``。
* 共享状态：``dmi_hard_reset`` 在 :file:`eh2_veer_wrapper.sv` 当前实例中未连接到外部逻辑。

§4.6  DMI DR register — 解包 ``wr_addr``、``wr_data``、``wr_en``、``rd_en``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 DMI access DR update 时保存整个 shift register，并将 ``dr`` 组合解包为地址、
写数据、写 enable 和读 enable。

关键代码（``rtl/design/dmi/rvjtag_tap.v:L207-L220``）：

.. code-block:: systemverilog

   // DR register
   always @ (posedge tck or negedge trst) begin
       if(!trst)
           dr <=  '0;
       else begin
           if (update_dr & dr_en[1])
               dr <= sr;
           else
               dr <= {dr[USER_DR_LENGTH-1:2],2'b0};
       end
   end

   assign {wr_addr, wr_data, wr_en, rd_en} = dr;

逐段解释：

* 第 L208-L216 行：``dr`` 在 ``tck`` 上升沿更新。reset 时清零；当 ``update_dr`` 且
  ``dr_en[1]`` 有效时装入 ``sr``；其他周期把低两位清 0，同时右侧拼接形式保持高位。
* 第 L219 行：``dr`` 被解包成 ``wr_addr``、``wr_data``、``wr_en``、``rd_en``。
  结合 ``USER_DR_LENGTH = AWIDTH + 34`` 可见，地址宽度由 ``AWIDTH`` 决定，数据宽度为
  32 bit，末两位是写/读 enable。

接口关系：

* 被调用：wrapper 把 ``wr_addr``、``wr_data`` 接到处理器侧地址/写数据，把 ``wr_en``、
  ``rd_en`` 接到同步器。
* 调用：读取 ``sr``、``update_dr`` 和 ``dr_en[1]``。
* 共享状态：``dr`` 是 JTAG ``tck`` 域状态，enable 通过同步器进入 core clock 域。

§5  Wrapper 与 core/debug 的连接
--------------------------------

DMI wrapper 不在 ``eh2_veer`` 内部实例化，而是在 ``eh2_veer_wrapper`` 中实例化。它的
``reg_*`` 输出连接到本地 ``dmi_reg_*`` wires，再连接到 ``eh2_veer`` 的 DMI 端口，最终由
``eh2_dbg`` 消费。

§5.1  ``eh2_veer_wrapper`` 本地 DMI wires
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 wrapper 内部连接 ``dmi_wrapper`` 与 ``eh2_veer`` 的 DMI 信号。

关键代码（``rtl/design/eh2_veer_wrapper.sv:L431-L436``）：

.. code-block:: systemverilog

      // DMI signals
      logic                   dmi_reg_en;                // read or write
      logic [6:0]             dmi_reg_addr;              // address of DM register
      logic                   dmi_reg_wr_en;             // write enable
      logic [31:0]            dmi_reg_wdata;             // write data
      logic [31:0]            dmi_reg_rdata;             // read data

逐段解释：

* 第 L431 行：注释明确这些是 DMI signals。
* 第 L432-L436 行：本地信号包括 access enable、7-bit 地址、write enable、32-bit 写数据和
  32-bit 读数据，与 ``dmi_wrapper`` 端口和 ``eh2_veer`` 端口宽度一致。

接口关系：

* 被调用：``dmi_wrapper`` 驱动或读取这些本地 wires，``eh2_veer`` 通过同名端口连接。
* 调用：该段只声明信号。
* 共享状态：``dmi_reg_rdata`` 从 core/debug 返回到 TAP，其他 ``dmi_reg_*`` 进入 core/debug。

§5.2  ``dmi_wrapper`` 实例 — JTAG pads 到 DMI wires
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把外部 JTAG pad、debug reset、core clock 和 DMI wires 接入 ``dmi_wrapper``。
当前实例中 ``tdoEnable`` 和 ``dmi_hard_reset`` 没有继续连接。

关键代码（``rtl/design/eh2_veer_wrapper.sv:L776-L796``）：

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
       );

逐段解释：

* 第 L776 行：实例名也叫 ``dmi_wrapper``，模块名与实例名相同。
* 第 L779-L785 行：JTAG ID、reset、clock、mode select、data in/out 接入实例；
  ``tdoEnable`` 明确为空连接。
* 第 L788-L795 行：processor 侧 reset 使用 ``dbg_rst_l``，clock 使用 ``clk``；
  DMI read data 返回到 wrapper，write data/address/enable 输出到本地 DMI wires；
  ``dmi_hard_reset`` 为空连接。

接口关系：

* 被调用：``eh2_veer_wrapper`` 实例化 ``dmi_wrapper``。
* 调用：实例内部调用 TAP 和同步器。
* 共享状态：``dbg_rst_l`` 决定同步器 reset；``clk`` 是 DMI enable 脉冲进入 core/debug 的 clock。

§5.3  ``eh2_veer`` DMI 端口 — core 顶层暴露 debug register bus
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 core 顶层声明 DMI register bus 端口，使 wrapper 的 DMI wires 可以进入 core 内部
debug 模块。

关键代码（``rtl/design/eh2_veer.sv:L399-L403``）：

.. code-block:: systemverilog

      input logic                   dmi_reg_en,                // access enable
      input logic [6:0]             dmi_reg_addr,              // DM register address
      input logic                   dmi_reg_wr_en,             // write enable
      input logic [31:0]            dmi_reg_wdata,             // write data
      output logic [31:0]           dmi_reg_rdata,             // read data

逐段解释：

* 第 L399 行：``dmi_reg_en`` 是 access enable。
* 第 L400 行：``dmi_reg_addr`` 是 7-bit debug module register address。
* 第 L401-L402 行：``dmi_reg_wr_en`` 和 ``dmi_reg_wdata`` 表示写访问及写数据。
* 第 L403 行：``dmi_reg_rdata`` 是 core 返回给 DMI wrapper/TAP 的读数据。

接口关系：

* 被调用：``eh2_veer_wrapper`` 通过同名 wires 连接这些端口。
* 调用：core 内部 debug 模块消费这些端口。
* 共享状态：这些信号与 ``eh2_dbg`` 端口同名同宽。

§6  ``eh2_dbg`` 对 DMI register bus 的消费
------------------------------------------

``eh2_dbg`` 是 DMI register bus 的主要消费者。DMI wrapper 只负责传输和同步读写事件；
具体 debug module register 的写入条件、读数据 mux 和读数据寄存器都在 ``eh2_dbg.sv`` 中。

§6.1  ``eh2_dbg`` DMI 输入输出端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 debug module 内部接收的 DMI register bus。该端口组与 ``eh2_veer`` 顶层 DMI
端口一致。

关键代码（``rtl/design/dbg/eh2_dbg.sv:L55-L61``）：

.. code-block:: systemverilog

      // inputs from the JTAG
      input logic                         dmi_reg_en, // read or write
      input logic [6:0]                   dmi_reg_addr, // address of DM register
      input logic                         dmi_reg_wr_en, // write instruction
      input logic [31:0]                  dmi_reg_wdata, // write data
      // output
      output logic [31:0]                 dmi_reg_rdata, // read data

逐段解释：

* 第 L55 行：源码注释把该组输入标为 “from the JTAG”，对应 wrapper/TAP 进入 debug 模块的路径。
* 第 L56-L59 行：``dmi_reg_en``、``dmi_reg_addr``、``dmi_reg_wr_en``、``dmi_reg_wdata``
  共同定义一次 DMI register access。
* 第 L61 行：``dmi_reg_rdata`` 是返回 JTAG/TAP 的 32-bit read data。

接口关系：

* 被调用：``eh2_veer`` 内部实例化 debug 模块时连接这些 DMI 端口。
* 调用：debug 模块内部的寄存器写入条件和读 mux 大量读取这些信号。
* 共享状态：``dmi_reg_en`` 也参与 debug 模块 clock enable 生成。

§6.2  DMI read mux — 地址到 debug register 数据
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 ``dmi_reg_addr`` 选择 ``data0``、``data1``、``dmcontrol``、``dmstatus``、
``abstractcs``、``command``、``sbcs``、``sbaddress0``、``sbdata0``、``sbdata1`` 等寄存器，
并在 ``dmi_reg_en`` 有效时把结果寄存到 ``dmi_reg_rdata``。

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

* 第 L612-L624 行：读 mux 用 one-hot mask 方式根据 ``dmi_reg_addr`` 选择 debug register。
  地址包括 ``7'h4``、``7'h5``、``7'h10``、``7'h11``、``7'h15``、``7'h16``、``7'h17``、
  ``7'h18``、``7'h40``、``7'h38``、``7'h39``、``7'h3c``、``7'h3d``。
* 第 L614 行：读取 ``dmcontrol`` 时，源码把部分 write-only bit 读为 0，这是由拼接表达式
  ``{2'b0,dmcontrol_reg[29],1'b0,dmcontrol_reg[27:0]}`` 直接体现的。
* 第 L628 行：``dmi_rddata_reg`` 在 ``dmi_reg_en`` 有效时把 mux 结果寄存到
  ``dmi_reg_rdata``，reset 使用 ``dbg_dm_rst_l``，clock 使用 ``clk``。

接口关系：

* 被调用：TAP 在 DR capture 且 ``dr_en[1]`` 有效时读取 ``rd_data``，wrapper 中该信号来自
  ``dmi_reg_rdata``。
* 调用：读取 debug 模块内部寄存器和 ``dmi_reg_addr``。
* 共享状态：``dmi_reg_en`` 是读数据寄存器 enable，也是 DMI access 的总有效脉冲。

§7  ADR 与签核上下文
--------------------

DMI 文件本身不直接给出 release sign-off 数字。与本章相关的已存在 ADR 是
:ref:`adr-0008` 和 :ref:`adr-0013`：前者记录 debug cosim 背景，后者记录早期 synthesis
结果曾误把 ``rvjtag_tap`` 当作 EH2 core 的问题，并说明 ``rvjtag_tap`` 不代表 core 综合结果。

关键代码（``docs/adr/INDEX.md:L33-L33``）：

.. code-block:: text

   | 0008 | `0008-debug-cosim.md` | Accepted | Captures debug-mode cosim closure, including debug CSR and DRET-sensitive behavior. |

逐段解释：

* 第 L33 行：ADR-0008 存在且状态为 Accepted，主题是 debug-mode cosim closure。DMI wrapper
  是 JTAG 到 debug register bus 的硬件入口，但 ADR-0008 的具体 cosim 决策不等同于
  ``rvjtag_tap`` 的 RTL 实现细节。

接口关系：

* 被调用：debug、JTAG agent、cosim 相关章节可引用该 ADR。
* 调用：本文只引用 ADR 索引确认编号存在。
* 共享状态：无 RTL 共享状态。

关键代码（``docs/adr/0013-synthesis-toolchain.md:L9-L13``）：

.. code-block:: text

   The RC2 `syn_yosys.log` showed `Top module: \rvjtag_tap` (38 cells), implying synthesis
   was performed on the EH2 core. In reality, the synthesized design was the JTAG TAP unit
   only, not the EH2 core.

   Root cause:

逐段解释：

* 第 L9-L11 行：ADR-0013 明确指出早期 ``syn_yosys.log`` 的 top module 是
  ``rvjtag_tap``，这只代表 JTAG TAP 单元，不代表 EH2 core。
* 第 L13 行：后续 ADR 内容进入 root cause 分析；本文引用该 ADR 是为了防止把
  ``rvjtag_tap`` 的综合结果误写成 core 级结果。

接口关系：

* 被调用：综合工具章节引用 :ref:`adr-0013`。
* 调用：本文不从 ADR-0013 推导 DMI RTL 行为，只引用它约束综合语义。
* 共享状态：无 RTL 共享状态。

§8  DMI/JTAG 常见失败模式与排查
-------------------------------

DMI 目录是 Verilog ``.v`` 代码，不是 ``.sv``，但它直接决定 JTAG agent 能否把请求送到
debug module。排查时不要只盯 ``eh2_dbg.sv``，需要同时看 TAP 状态机、JTAG-to-core
同步桥和 wrapper 连线。

.. list-table:: DMI/JTAG 失败模式
   :header-rows: 1
   :widths: 24 32 28 16

   * - 现象
     - 可能根因
     - 排查命令
     - 阅读入口
   * - JTAG agent 一直读不到 IDCODE
     - ``trst_n`` 未释放、TAP 仍在 TEST_LOGIC_RESET_STATE，或 ``jtag_id`` 连线错误
     - ``rg -n "jtag_id|TEST_LOGIC_RESET_STATE|trst" /home/host/Cores-VeeR-EH2/design/dmi``
     - 本章 §2 与 §5
   * - TDO 没有翻转
     - ``tdoEnable`` 只在 ``shift_dr`` / ``shift_ir`` 时打开，仿真序列未进入 shift 状态
     - ``rg -n "tdoEnable|shift_dr|shift_ir|tdo" /home/host/Cores-VeeR-EH2/design/dmi/rvjtag_tap.v``
     - 本章 §5
   * - DMI 写入到 debug module 后无响应
     - ``dmi_jtag_to_core_sync`` CDC 握手未把 JTAG 域请求同步到 core clock
     - ``rg -n "dmi_reg_en|core_dmi|jtag" /home/host/Cores-VeeR-EH2/design/dmi``
     - 本章 §3 与 :ref:`appendix_a_rtl/dbg`
   * - 读 ``dmcontrol`` 时 write-only bit 看起来丢失
     - ``eh2_dbg.sv`` 读 mux 显式把部分 write-only bit 读 0
     - ``rg -n "dmcontrol_reg|dmi_reg_rdata" /home/host/Cores-VeeR-EH2/design/dbg/eh2_dbg.sv``
     - 本章 §6
   * - 早期综合报告显示 top 是 ``rvjtag_tap``
     - 只综合了 JTAG TAP，不代表 EH2 core 综合结果
     - ``rg -n "rvjtag_tap|Top module" docs/adr syn``
     - :ref:`adr-0013`
   * - debug directed test 与 cosim 行为不一致
     - debug halt/resume 改变退役流，Spike 状态同步需要额外约束
     - ``rg -n "debug|dret|halt" docs/adr dv/uvm/core_eh2/tests``
     - :ref:`adr-0008`

§9  参考资料
------------

* 源文件：:file:`/home/host/eh2-veri/rtl/design/dmi/dmi_wrapper.v`
* 源文件：:file:`/home/host/eh2-veri/rtl/design/dmi/dmi_jtag_to_core_sync.v`
* 源文件：:file:`/home/host/eh2-veri/rtl/design/dmi/rvjtag_tap.v`
* Debug 源文件：:file:`/home/host/eh2-veri/rtl/design/dbg/eh2_dbg.sv`
* Wrapper 连接：:file:`/home/host/eh2-veri/rtl/design/eh2_veer_wrapper.sv`
* Core 端口：:file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* RTL filelist：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* 关联 ADR：:ref:`adr-0008`、:ref:`adr-0013`
* 关联章节：:doc:`dbg`

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

§11  v2-23 DMI/JTAG 全文段落级精读
--------------------------------------------------------------------------------

v2-23 将 DMI 目录 3 个 Verilog 文件全部纳入 ``literalinclude``。DMI wrapper、
JTAG-to-core 同步桥和 TAP 状态机共同构成外部 JTAG agent 到 ``eh2_dbg`` 的访问链，
缺少其中任一段都会让 debug directed test、JTAG agent 或综合排查出现断点。

§11.1  ``dmi_wrapper.v`` — JTAG TAP 与 core debug 端口胶合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dmi/dmi_wrapper.v
   :language: text
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dmi/dmi_wrapper.v:全文

逐段精读：

* L1-L23：文件头和注释。该 wrapper 是 DMI/JTAG 目录对外的顶层连接点。
* L24-L42：模块端口。输入是 JTAG ``trst_n``、``tck``、``tms``、``tdi``、core clock/reset
  和 DMI read data；输出是 ``tdo``、``tdoEnable``、``dmi_reg_en``、write enable、地址和数据。
* L43-L58：内部 JTAG 域信号声明。``jtag_reg_wr_en``、``jtag_reg_rd_en``、``jtag_reg_addr``
  和 ``jtag_reg_wdata`` 是 TAP 到 CDC 桥的接口。
* L59-L76：``rvjtag_tap`` 实例。TAP 负责 JTAG state machine、IR/DR shift、IDCODE 和 DMI
  request 打包。
* L77-L89：``dmi_jtag_to_core_sync`` 实例。该桥把 TAP 产生的 JTAG 域脉冲同步到 core
  clock 域，形成 ``dmi_reg_en`` 与 ``dmi_reg_wr_en``。
* L90：module 结束。wrapper 本身不保存 debug architectural state。

§11.2  ``dmi_jtag_to_core_sync.v`` — JTAG 到 core clock CDC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dmi/dmi_jtag_to_core_sync.v
   :language: text
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dmi/dmi_jtag_to_core_sync.v:全文

逐段精读：

* L1-L24：文件头。该模块只处理 CDC pulse 同步，不解释 DMI register semantics。
* L25-L43：模块端口和同步寄存器声明。输入是 JTAG 域 read/write pulse、地址、wdata 和
  core clock/reset；输出是 core 域 register enable、write enable、地址和 wdata。
* L44-L48：组合输出。``reg_en`` 是 read/write pulse 的 OR，``reg_wr_en`` 只来自 write pulse。
* L49-L59：三拍同步寄存器。``rd_en``、``wr_en``、地址和 wdata 在 core clock 上采样，
  reset 时全部清零。
* L60-L64：边沿检测和 module 结束。``rden[1] & ~rden[2]``、``wren[1] & ~wren[2]`` 把
  JTAG 域脉冲转换为 core 域单拍事件。

§11.3  ``rvjtag_tap.v`` — JTAG TAP state machine 与 DMI DR
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dmi/rvjtag_tap.v
   :language: text
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dmi/rvjtag_tap.v:全文

逐段精读：

* L1-L15：文件头和说明。该 TAP 实现 JTAG instruction/data register shift，不包含
  ``eh2_dbg`` 的 debug register state。
* L16-L49：模块参数与端口。``AWIDTH`` 控制 DMI address width，JTAG pins 与 core read data
  在这里进入 TAP。
* L50-L75：USER DR length、device ID、BYPASS、IDCODE、DTMCS、DMI DR 和 address bits
  定义。``USER_DR_LENGTH = AWIDTH + 34`` 对应 address、data、wr_en、rd_en 打包。
* L76-L129：JTAG 16 状态 TAP FSM。``TEST_LOGIC_RESET`` 到 ``UPDATE_IR/DR`` 的跳转由
  ``tms`` 和 ``trst`` 控制，并派生 ``shift_dr``、``capture_dr``、``update_dr`` 等信号。
* L131-L148：``tdoEnable``、IR shift/capture/update 和 DR 选择。IDCODE、DTMCS、DMI DR
  和 bypass 的选择由当前 IR 决定。
* L153-L188：DR shift register。capture 阶段装入 IDCODE/DTMCS/DMI read data，shift 阶段
  串行移动 ``tdi``，DMI DR 捕获 address/data/read/write 请求。
* L189-L207：TDO 输出和 DMI read data staging。``tdo`` 在 ``negedge tck`` 输出 ``sr[0]``，
  读数据在 update/capture 时保持。
* L208-L224：``dr`` 输出寄存和 module 结束。最终 ``wr_addr``、``wr_data``、``wr_en`` 和
  ``rd_en`` 送入 CDC 同步桥。
