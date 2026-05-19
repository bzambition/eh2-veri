.. _agent_trace:
.. _05_verification_arch/agent_trace:

Trace Agent — 架构参考
======================

:status: draft
:source: dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  本章边界
------------

本章解释 EH2 UVM 环境中的 trace/probe 退休观测路径。逐类源码字典见
:ref:`appendix_b_uvm_trace_agent`；这里聚焦 ``eh2_trace_monitor``、
``eh2_dut_probe_monitor``、``eh2_trace_intf``、``eh2_dut_probe_if`` 与
cosim scoreboard 的架构边界。当前目录没有 ``eh2_trace_agent.sv`` top-level
agent；env 直接创建 trace monitor 和 DUT probe monitor。

Trace 路径覆盖以下源文件：

* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
* :file:`dv/uvm/core_eh2/env/eh2_dut_probe_if.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`

本章使用 ``trace pkt`` 指 RTL trace packet，使用 ``probe`` 指
``eh2_dut_probe_if`` 暴露的 DUT 内部观测信号。``trace pkt`` 负责 regular retire
和 regular ``wb``；``probe`` 负责 DIV、NB-load、interrupt/NMI/debug、CSR mirror
和 ``wb_seq``。

§2  架构数据流
--------------

Trace 架构分成两条 analysis 流。第一条从 DUT ``trace_rv_i_*`` 端口进入
``eh2_trace_intf``，由 ``eh2_trace_monitor`` 每个有效 slot 产生一笔
``eh2_trace_seq_item``。第二条从 DUT 内部层级信号进入 ``eh2_dut_probe_if``，
由 ``eh2_dut_probe_monitor`` 只发布异步写回提示。两条流在 cosim scoreboard
中汇合，trace FIFO 按退休顺序推动 Spike step，DUT probe FIFO 只为 DIV 和
NB-load 补充 async ``wb`` 信息。

::

   DUT trace_rv_i_* ports
          |
          v
   eh2_trace_intf
          |
          v
   eh2_trace_monitor.ap
          |
          +--> cosim_agt.scoreboard.trace_fifo
          |
          `--> dfd_scoreboard.trace_fifo

   DUT hierarchical probe signals
          |
          v
   eh2_dut_probe_if
          |
          v
   eh2_dut_probe_monitor.ap
          |
          `--> cosim_agt.scoreboard.dut_probe_fifo

接口关系：

* 被调用：``core_eh2_env`` 在 build phase 直接创建两个 monitor。
* 调用：``trace_monitor.ap.write(txn)`` 写 trace FIFO；``dut_probe_monitor.ap.write(txn)``
  写 DUT probe FIFO。
* 共享状态：``probe_vif.wb_seq`` 由 DUT probe monitor 写入，由 trace monitor 采样到
  ``txn.wb_tag``。

§3  Package 边界与 writeback source
------------------------------------

职责：``eh2_trace_agent_pkg`` 提供 trace item、trace monitor、DUT probe monitor，
并定义三类 ``wb_source``。source 分类是 cosim 区分 regular ``wb`` 与 async
``wb`` 的入口。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv:L7-L21``）：

.. code-block:: systemverilog

   package eh2_trace_agent_pkg;
   
     `include "uvm_macros.svh"
     import uvm_pkg::*;
   
     localparam int EH2_WB_SRC_REGULAR = 0;
     localparam int EH2_WB_SRC_DIV     = 1;
     localparam int EH2_WB_SRC_NB_LOAD = 2;
   
     // Trace agent components
     `include "eh2_trace_seq_item.sv"
     `include "eh2_trace_monitor.sv"
     `include "eh2_dut_probe_monitor.sv"
   
   endpackage

逐段解释：

* 第 7 行：声明 ``eh2_trace_agent_pkg``。
* 第 9~10 行：引入 UVM 宏和 ``uvm_pkg``，使本 package 内 include 的 class 可以使用
  UVM component、object 和 analysis port。
* 第 12~14 行：给 regular trace ``wb``、DIV async ``wb``、NB-load async ``wb``
  分配整数编码。trace monitor 写 ``EH2_WB_SRC_REGULAR``，DUT probe monitor 写
  ``EH2_WB_SRC_DIV`` 或 ``EH2_WB_SRC_NB_LOAD``。
* 第 17~19 行：include 顺序先给出 ``eh2_trace_seq_item``，再给出使用该 item 的两个
  monitor。
* 第 21 行：结束 package；源码没有 include top-level ``eh2_trace_agent.sv``。

接口关系：

* 被调用：env、cosim scoreboard 和 test package import ``eh2_trace_agent_pkg``。
* 调用：SystemVerilog include 机制。
* 共享状态：``EH2_WB_SRC_*`` 常量在 trace monitor、DUT probe monitor 和 cosim
  scoreboard 间保持一致。

§4  ``eh2_trace_intf`` 的 trace pkt 字段
----------------------------------------

职责：``eh2_trace_intf`` 把 DUT trace ports 组织成 monitor 可读的 virtual
interface。源码注释说明它是 EH2 简化 trace interface，不是标准 RVFI；实际字段包含
retire 指令、PC、valid、异常、interrupt、``tval``，以及 verification-only 的
``rd_valid``、``rd_addr``、``rd_wdata``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L19-L38``）：

.. code-block:: systemverilog

   interface eh2_trace_intf #(
     parameter NUM_THREADS = 1
   )(
     input logic clk,
     input logic rst_n
   );
   
     // Trace signals
     logic [NUM_THREADS-1:0][63:0] insn;
     logic [NUM_THREADS-1:0][63:0] address;
     logic [NUM_THREADS-1:0][1:0]  valid;
     logic [NUM_THREADS-1:0][1:0]  exception;
     logic [NUM_THREADS-1:0][4:0]  ecause;
     logic [NUM_THREADS-1:0][1:0]  interrupt;
     logic [NUM_THREADS-1:0][31:0] tval;
     // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
     logic [NUM_THREADS-1:0][1:0]  rd_valid;
     logic [NUM_THREADS-1:0][9:0]  rd_addr;
     logic [NUM_THREADS-1:0][63:0] rd_wdata;

逐段解释：

* 第 19~24 行：interface 以 ``NUM_THREADS`` 参数化，并接收 ``clk`` 与 ``rst_n``。
* 第 27~33 行：``insn`` 和 ``address`` 各为 64 bit，按每线程两个 slot 打包；``valid``、
  ``exception`` 和 ``interrupt`` 是每线程 2 bit；``ecause`` 与 ``tval`` 是每线程共享字段。
* 第 34~37 行：``rd_valid``、``rd_addr``、``rd_wdata`` 是 verification-only
  writeback view。``rd_addr`` 用 10 bit 容纳 i0/i1 两个 5 bit 目的寄存器，``rd_wdata``
  用 64 bit 容纳两个 32 bit 写回值。

接口关系：

* 被调用：``core_eh2_tb_top`` 实例化该 interface 并赋值 DUT trace signals。
* 调用：无任务或函数调用，只声明信号。
* 共享状态：``eh2_trace_monitor`` 通过 ``vif`` 读取这些信号。

§5  Thread 0 双 slot 便捷解码
-----------------------------

职责：interface 内部把 thread 0 的 i0/i1 trace pkt 切成 monitor 直接读取的
``t0_i0_*`` 和 ``t0_i1_*`` 信号。当前便捷解码只覆盖 thread 0 与两个 slot。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L60-L77``）：

.. code-block:: systemverilog

   // Decode convenience signals
   assign t0_i0_pc        = address[0][31:0];
   assign t0_i0_insn      = insn[0][31:0];
   assign t0_i0_valid     = valid[0][0];
   assign t0_i0_exception = exception[0][0];
   assign t0_i0_ecause    = ecause[0][4:0];
   assign t0_i0_wb_valid  = rd_valid[0][0];
   assign t0_i0_wb_addr   = rd_addr[0][4:0];
   assign t0_i0_wb_data   = rd_wdata[0][31:0];
   
   assign t0_i1_pc        = address[0][63:32];
   assign t0_i1_insn      = insn[0][63:32];
   assign t0_i1_valid     = valid[0][1];
   assign t0_i1_exception = exception[0][1];
   assign t0_i1_ecause    = ecause[0][4:0];
   assign t0_i1_wb_valid  = rd_valid[0][1];
   assign t0_i1_wb_addr   = rd_addr[0][9:5];
   assign t0_i1_wb_data   = rd_wdata[0][63:32];

逐段解释：

* 第 61~68 行：i0 使用 ``address[0][31:0]``、``insn[0][31:0]``、``valid[0][0]``
  和 ``exception[0][0]``。i0 的 ``wb`` 目的寄存器来自 ``rd_addr[0][4:0]``，写回数据来自
  ``rd_wdata[0][31:0]``。
* 第 70~77 行：i1 使用同一线程打包字段的高 32 bit 和第二个 valid bit。i1 的 ``wb`` 目的寄存器来自
  ``rd_addr[0][9:5]``，写回数据来自 ``rd_wdata[0][63:32]``。
* 第 65 行与第 74 行：i0/i1 都读取 ``ecause[0][4:0]``。源码没有为两个 slot 分拆独立
  ``ecause``。

接口关系：

* 被调用：``eh2_trace_monitor.monitor_trace`` 直接读取 ``t0_i0_*`` 和 ``t0_i1_*``。
* 调用：连续赋值。
* 共享状态：只读 DUT trace pkt，未写入状态。

§6  Testbench trace interface 绑定
----------------------------------

职责：``core_eh2_tb_top`` 实例化 ``eh2_trace_intf``，并把 DUT trace ports 逐字段接入
interface。该绑定决定 monitor 看到的是 DUT 顶层 trace bus，而不是 probe 重构出的 retire
事件。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L731-L744``）：

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

* 第 731~732 行：testbench 用 ``RV_NUM_THREADS`` 参数实例化 ``trace_intf``，时钟接
  ``core_clk``，复位接 ``rst_l``。
* 第 735~741 行：退休指令、PC、valid、异常、cause、interrupt 与 ``tval`` 从 DUT trace
  ports 进入 interface。
* 第 742~744 行：verification-only 写回 view 从 ``trace_rv_i_rd_valid_ip``、
  ``trace_rv_i_rd_addr_ip`` 和 ``trace_rv_i_rd_wdata_ip`` 进入 interface，供 trace monitor
  写入 ``eh2_trace_seq_item.wb_*``。

接口关系：

* 被调用：testbench elaboration。
* 调用：``eh2_trace_intf`` 实例化与连续赋值。
* 共享状态：``trace_intf`` 后续通过 UVM config DB 交给 ``trace_monitor``。

§7  DUT probe interface 的职责边界
----------------------------------

职责：``eh2_dut_probe_if`` 不再承载 regular pipeline ``wb`` 主路径。它保留 DIV/NB-load
异步写回、interrupt/NMI/debug、CSR mirror、trap flags 和 ``wb_seq``，用于补足
``trace pkt`` 无法及时表达的状态。

关键代码（``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L19-L44``）：

.. code-block:: systemverilog

     // Division unit signals
     logic             div_cancel;             // Division canceled (any kind)
     logic             div_cancel_overwrite;   // Cancel due to younger same-rd write (paired with retired div trace)
     logic [4:0]       div_rd;                 // Division destination register
     logic [31:0]      div_result;             // Division raw result (pre-qualify)
     logic             div_wren;               // Division writeback valid (exu_div_wren)
     logic [31:0]      div_wdata;              // Division writeback data (exu_div_result)
   
     // Non-block load signals
     logic             nb_load_wen;
     logic [4:0]       nb_load_waddr;
     logic [31:0]      nb_load_data;
   
     // Interrupt/NMI/debug state (sampled each cycle for cosim notification)
     logic [31:0]      mip;           // Machine interrupt pending
     logic             nmi;           // NMI mode
     logic             nmi_int;       // NMI interrupt pending
     logic             debug_req;     // Debug request active
     logic [63:0]      mcycle;        // Cycle counter
   
     // CSR mirror state (for directed tests and coverage)
     logic [31:0]      mstatus;
     logic [31:0]      mtvec;
     logic [31:0]      mepc;
     logic [31:0]      mcause;
     logic [31:0]      mtval;

逐段解释：

* 第 19~25 行：DIV probe 字段包含 cancel 类型、目的寄存器、原始结果、写回 valid 和写回数据。
* 第 27~30 行：NB-load probe 字段包含完成 valid、目的寄存器和数据。
* 第 32~37 行：interrupt/NMI/debug 状态和 ``mcycle`` 每周期可被 trace monitor 采样，随后用于
  Spike 通知。
* 第 39~44 行：CSR mirror 提供 ``mstatus``、``mtvec``、``mepc``、``mcause`` 和 ``mtval``；
  trace monitor 在异常或 interrupt item 上采样 trap CSR snapshot。

接口关系：

* 被调用：``core_eh2_tb_top`` 实例化并用 DUT 层级引用赋值。
* 调用：无函数调用。
* 共享状态：``eh2_trace_monitor`` 读 interrupt/debug/CSR mirror；``eh2_dut_probe_monitor``
  读 DIV/NB-load 并写 ``wb_seq``。

§8  Testbench DUT probe 绑定
----------------------------

职责：testbench 把 DUT 内部 DIV、NB-load、interrupt、debug 和 CSR mirror 信号接到
``dut_probe_intf``。源码注释明确 regular ``wb_valid/wb_dest/wb_data/wb_suppress`` 不再从
probe 暴露，而是经 RTL trace packet 传递。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L818-L835``）：

.. code-block:: systemverilog

   eh2_dut_probe_if dut_probe_intf (.clk(core_clk), .rst_n(rst_l));
   
   // Connect DUT probe signals to internal DUT hierarchy.
   // Phase 1 note: regular wb_valid/wb_dest/wb_data/wb_suppress fields are no
   // longer probed here — they ride along the RTL trace packet now (ADR-0004).
   // Only async writeback (DIV / NB-load) and CSR/exception mirror state are
   // exposed via this interface.
   
   assign dut_probe_intf.div_cancel = `DEC.dec_div_cancel;
   assign dut_probe_intf.div_cancel_overwrite = `DEC.dec_div_cancel_overwrite;
   assign dut_probe_intf.div_rd     = `DEC.decode.div_rd;
   assign dut_probe_intf.div_result = `EXU.div_e1.out_raw[31:0];
   assign dut_probe_intf.div_wren   = dut.veer.exu_div_wren;
   assign dut_probe_intf.div_wdata  = dut.veer.exu_div_result[31:0];
   
   assign dut_probe_intf.nb_load_wen   = `DEC.dec_nonblock_load_wen[0];
   assign dut_probe_intf.nb_load_waddr = `DEC.dec_nonblock_load_waddr[0];
   assign dut_probe_intf.nb_load_data  = `DEC.lsu_nonblock_load_data;

逐段解释：

* 第 818 行：实例化 ``dut_probe_intf``，时钟和复位与 core 使用同一 ``core_clk``、``rst_l``。
* 第 820~824 行：注释给出边界：regular ``wb`` 不再由 probe 暴露，probe 只负责 async
  writeback 与 CSR/exception mirror。
* 第 826~831 行：DIV cancel、overwrite cancel、目的寄存器、raw result、write enable 和
  write data 从 ``DEC``、``EXU`` 与 ``dut.veer`` 层级引用进入 probe。
* 第 833~835 行：NB-load 完成 valid、目的寄存器和数据从 ``DEC`` 层级引用进入 probe。

接口关系：

* 被调用：testbench elaboration。
* 调用：``eh2_dut_probe_if`` 实例化与连续赋值。
* 共享状态：``dut_probe_intf`` 通过 UVM config DB 同时交给 ``dut_probe_monitor``、
  ``trace_monitor`` 和 cosim agent。

§9  Probe 中断、debug 与 CSR mirror 绑定
----------------------------------------

职责：``dut_probe_intf`` 还把 interrupt pending、NMI、debug request、``mcycle`` 和 trap
CSR 从 DUT 内部寄存器映射出来。trace monitor 用这组字段补充 ``eh2_trace_seq_item``，
使 cosim scoreboard 可以按 Spike 通知顺序处理 debug/NMI/mip/mcycle。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L837-L865``）：

.. code-block:: systemverilog

   // Interrupt/NMI/debug state for cosim notification
   // Construct MIP from external interrupt sources:
   //   bit 11 = MEIP (external), bit 7 = MTIP (timer), bit 3 = MSIP (software)
   assign dut_probe_intf.mip        = {20'b0, extintsrc_req[1], 3'b0, timer_int[0], 3'b0, soft_int[0], 3'b0};
   assign dut_probe_intf.nmi        = nmi_int;
   assign dut_probe_intf.nmi_int    = nmi_int;
   assign dut_probe_intf.debug_req  = mpc_debug_halt_req[0];
   // mcycle: 64-bit cycle counter from TLU CSR registers
   // Path: dut.veer.dec.tlu.tlumt[0].tlu.mcycleh/mcyclel
   assign dut_probe_intf.mcycle     = {dut.veer.dec.tlu.tlumt[0].tlu.mcycleh[31:0],
                                       dut.veer.dec.tlu.tlumt[0].tlu.mcyclel[31:0]};
   
   // CSR signals - probed from TLU internal registers
   // mstatus: only bits [1:0] stored (MPIE, MIE), MPP hardcoded to 2'b11
   assign dut_probe_intf.mstatus = {19'b0, 2'b11, 3'b0,
                                    dut.veer.dec.tlu.tlumt[0].tlu.mstatus[1],
                                    3'b0,
                                    dut.veer.dec.tlu.tlumt[0].tlu.mstatus[0],
                                    3'b0};
   // mtvec: 31 bits stored {BASE[31:2], MODE[0]}, bit 1 reserved
   assign dut_probe_intf.mtvec   = {dut.veer.dec.tlu.tlumt[0].tlu.mtvec[30:1],
                                    1'b0,
                                    dut.veer.dec.tlu.tlumt[0].tlu.mtvec[0]};
   // mepc: 31 bits stored, bit 0 always 0
   assign dut_probe_intf.mepc    = {dut.veer.dec.tlu.tlumt[0].tlu.mepc[31:1], 1'b0};
   // mcause: full 32 bits
   assign dut_probe_intf.mcause  = dut.veer.dec.tlu.tlumt[0].tlu.mcause[31:0];
   // mtval: full 32 bits (issue 64 — from RTL TLU mtval register)
   assign dut_probe_intf.mtval   = dut.veer.dec.tlu.tlumt[0].tlu.mtval[31:0];

逐段解释：

* 第 837~840 行：``mip`` 由 external、timer、software interrupt 源拼接而成，注释标明
  MEIP、MTIP、MSIP 的 bit 位置。
* 第 841~843 行：``nmi``、``nmi_int`` 和 ``debug_req`` 分别来自 ``nmi_int`` 与
  ``mpc_debug_halt_req[0]``。
* 第 844~847 行：``mcycle`` 从 TLU 的 ``mcycleh`` 和 ``mcyclel`` 拼成 64 bit。
* 第 849~865 行：``mstatus``、``mtvec``、``mepc``、``mcause``、``mtval`` 均从
  ``dut.veer.dec.tlu.tlumt[0].tlu`` 路径采样。

接口关系：

* 被调用：testbench 连续赋值。
* 调用：无任务或函数调用。
* 共享状态：trace monitor 读这些 probe 字段写入 trace item；directed tests 和 coverage
  也可读 CSR mirror 状态。

§10  UVM config DB 分发
-----------------------

职责：testbench 通过 UVM config DB 把 ``trace_intf`` 和 ``dut_probe_intf`` 分发到
对应 monitor，并额外把 ``dut_probe_intf`` 交给 trace monitor 与 cosim agent。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1112-L1120``）：

.. code-block:: systemverilog

   // Store trace and DUT probe interfaces
   uvm_config_db#(virtual eh2_trace_intf)::set(null, "*trace_monitor*", "vif", trace_intf);
   uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*dut_probe_monitor*", "vif", dut_probe_intf);
   
   // Also provide DUT probe interface to trace monitor (for interrupt/debug state sampling)
   uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*trace_monitor*", "probe_vif", dut_probe_intf);
   
   // Provide DUT probe interface to cosim agent's scoreboard (for reset monitoring)
   uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*cosim_agt*", "probe_vif", dut_probe_intf);

逐段解释：

* 第 1113 行：``trace_monitor`` 的 ``vif`` 字段得到 ``trace_intf``。
* 第 1114 行：``dut_probe_monitor`` 的 ``vif`` 字段得到 ``dut_probe_intf``。
* 第 1117 行：``trace_monitor`` 的 ``probe_vif`` 字段也得到 ``dut_probe_intf``，用于采样
  interrupt/debug/CSR mirror 与 ``wb_seq``。
* 第 1120 行：cosim agent 得到 ``probe_vif``，scoreboard 可用该 interface 监测 reset。

接口关系：

* 被调用：testbench initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：``trace_monitor.vif``、``trace_monitor.probe_vif``、``dut_probe_monitor.vif``、
  ``cosim_agt.probe_vif``。

§11  Env 创建与 analysis 连接
------------------------------

职责：env 不是创建 top-level trace agent，而是直接创建两个 monitor；connect phase
把 trace monitor 连接到 cosim scoreboard 和 double-fault detection scoreboard，把 DUT
probe monitor 连接到 cosim scoreboard。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L99-L103``）：

.. code-block:: systemverilog

   // Trace monitor
   trace_monitor = eh2_trace_monitor::type_id::create("trace_monitor", this);
   
   // DUT probe monitor
   dut_probe_monitor = eh2_dut_probe_monitor::type_id::create("dut_probe_monitor", this);

逐段解释：

* 第 100 行：env 通过 factory 创建 ``trace_monitor``。
* 第 103 行：env 通过 factory 创建 ``dut_probe_monitor``。
* 第 99~103 行：源码没有创建 ``trace_agent`` wrapper；trace/probe 两条 monitor 路径是 env
  的直接子组件。

接口关系：

* 被调用：UVM build phase。
* 调用：``eh2_trace_monitor::type_id::create`` 与 ``eh2_dut_probe_monitor::type_id::create``。
* 共享状态：env 成员 ``trace_monitor`` 与 ``dut_probe_monitor``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L167``）：

.. code-block:: systemverilog

   // Connect trace monitor to co-simulation agent's scoreboard
   if (cfg.enable_cosim && cosim_agt != null) begin
     trace_monitor.ap.connect(cosim_agt.scoreboard.trace_fifo.analysis_export);
   end
   
   // Connect DUT probe monitor to co-simulation agent's scoreboard
   if (cfg.enable_cosim && cosim_agt != null) begin
     dut_probe_monitor.ap.connect(cosim_agt.scoreboard.dut_probe_fifo.analysis_export);
   end
   
   // Connect LSU AXI4 monitor to co-simulation agent
   if (cfg.enable_cosim && cosim_agt != null) begin
     lsu_agent.ap.connect(cosim_agt.dmem_port);
   end
   
   // Connect trace monitor to double-fault detection scoreboard
   trace_monitor.ap.connect(dfd_scoreboard.trace_fifo.analysis_export);

逐段解释：

* 第 151~154 行：启用 cosim 且 ``cosim_agt`` 非空时，trace monitor analysis port 连接到
  cosim scoreboard 的 ``trace_fifo``。
* 第 156~159 行：同一条件下，DUT probe monitor analysis port 连接到 cosim scoreboard 的
  ``dut_probe_fifo``。
* 第 161~164 行：LSU AXI monitor 也连接到 cosim agent，用于 memory access 通知；它与 trace
  路径在 scoreboard 中共同决定指令何时可以 step。
* 第 166~167 行：trace monitor 同时连接 double-fault detection scoreboard 的 ``trace_fifo``。

接口关系：

* 被调用：UVM connect phase。
* 调用：UVM analysis port ``connect``。
* 共享状态：``cfg.enable_cosim``、``cosim_agt.scoreboard.trace_fifo``、
  ``cosim_agt.scoreboard.dut_probe_fifo``、``dfd_scoreboard.trace_fifo``。

§12  Trace monitor 组件接口
---------------------------

职责：``eh2_trace_monitor`` 是 passive monitor。它持有 trace virtual interface、
可选的 DUT probe interface、analysis port 和统计计数器。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L14-L29``）：

.. code-block:: systemverilog

   class eh2_trace_monitor extends uvm_monitor;
   
     `uvm_component_utils(eh2_trace_monitor)
   
     // Virtual interfaces
     virtual eh2_trace_intf #(.NUM_THREADS(1)) vif;
     virtual eh2_dut_probe_if probe_vif;
   
     // Analysis port
     uvm_analysis_port #(eh2_trace_seq_item) ap;
   
     // Statistics
     int commit_count;
     int exception_count;
     int cycle_count;

逐段解释：

* 第 14 行：``eh2_trace_monitor`` 继承 ``uvm_monitor``，没有 driver 或 sequencer 行为。
* 第 16 行：注册 UVM factory。
* 第 19~20 行：``vif`` 绑定 trace interface；``probe_vif`` 绑定 DUT probe interface。
* 第 23 行：analysis port 的 item 类型是 ``eh2_trace_seq_item``。
* 第 26~28 行：monitor 统计 commit、exception 和 cycle 数。

接口关系：

* 被调用：env factory create。
* 调用：UVM component registration。
* 共享状态：``vif``、``probe_vif``、``ap``、``commit_count``、``exception_count``、
  ``cycle_count``。

§13  ``connect_phase`` 获取 interface
-------------------------------------

职责：trace monitor 必须拿到 ``vif`` 才能运行；``probe_vif`` 是可选输入，缺失时 monitor
仍可产生退休 item，但 interrupt/debug state 被置零，异常 trap CSR snapshot 只能退回到
``tval``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L34-L48``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     ap = new("ap", this);
   endfunction
   
   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
     if (!uvm_config_db#(virtual eh2_trace_intf)::get(this, "", "vif", vif)) begin
       `uvm_fatal("trace_monitor", "Could not get trace virtual interface")
     end
     // DUT probe interface is optional - cosim notifications won't work without it
     if (!uvm_config_db#(virtual eh2_dut_probe_if)::get(this, "", "probe_vif", probe_vif)) begin
       `uvm_warning("trace_monitor", "Could not get DUT probe interface - interrupt/debug state will be zero")
     end
   endfunction

逐段解释：

* 第 34~37 行：build phase 创建 analysis port ``ap``。
* 第 39~43 行：connect phase 从 config DB 读取 ``vif``。如果读取失败，monitor 报
  ``uvm_fatal``，因为没有 trace interface 就无法采样退休指令。
* 第 44~47 行：读取 ``probe_vif`` 失败只报 ``uvm_warning``。源码注释说明缺少 DUT probe
  时 cosim notifications 不工作，interrupt/debug state 会为 0。

接口关系：

* 被调用：UVM build/connect phase。
* 调用：``uvm_config_db::get``、``uvm_fatal``、``uvm_warning``。
* 共享状态：``ap``、``vif``、``probe_vif``。

§14  ``populate_cosim_state()`` 采样 Spike 通知状态
---------------------------------------------------

职责：``populate_cosim_state`` 把 DUT probe 中的 debug/NMI/interrupt pending 与
``mcycle`` 拷入 trace item。如果没有 ``probe_vif``，这些字段被显式置零。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L56-L71``）：

.. code-block:: systemverilog

   // Populate trace item with interrupt/debug/NMI state from DUT probe
   function void populate_cosim_state(eh2_trace_seq_item txn);
     if (probe_vif != null) begin
       txn.debug_req = probe_vif.debug_req;
       txn.nmi       = probe_vif.nmi;
       txn.nmi_int   = probe_vif.nmi_int;
       txn.mip       = probe_vif.mip;
       txn.mcycle    = probe_vif.mcycle;
     end else begin
       txn.debug_req = 0;
       txn.nmi       = 0;
       txn.nmi_int   = 0;
       txn.mip       = 0;
       txn.mcycle    = 0;
     end
   endfunction

逐段解释：

* 第 57 行：函数接受已经创建好的 ``eh2_trace_seq_item`` 句柄。
* 第 58~63 行：``probe_vif`` 存在时，从 DUT probe 采样 ``debug_req``、``nmi``、
  ``nmi_int``、``mip`` 和 ``mcycle``。
* 第 64~70 行：``probe_vif`` 不存在时，逐字段写 0，避免 item 携带未初始化状态。
* 第 71 行：函数结束；它不调用 DPI，也不写 analysis port。

接口关系：

* 被调用：``monitor_trace`` 在 i0 与 i1 item 构造路径中调用。
* 调用：只读 ``probe_vif`` 字段。
* 共享状态：``txn.debug_req``、``txn.nmi``、``txn.nmi_int``、``txn.mip``、``txn.mcycle``。

§15  Trace monitor 时序循环
---------------------------

职责：``monitor_trace`` 在复位释放后的每个 ``vif.clk`` 上升沿采样 trace pkt，并对 i0/i1
两个 slot 分别创建 item。它不会把同周期两个 slot 合并成一个 transaction。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L73-L95``）：

.. code-block:: systemverilog

   // Monitor trace interface
   task monitor_trace();
     eh2_trace_seq_item txn;
   
     forever begin
       @(posedge vif.clk iff vif.rst_n);
   
       cycle_count++;
   
       // Monitor thread 0, instruction 0 (i0)
       if (vif.t0_i0_valid) begin
         txn = eh2_trace_seq_item::type_id::create("trace_txn");
         txn.thread_id   = 0;
         txn.slot        = 0;
         txn.pc          = vif.t0_i0_pc;
         txn.insn        = vif.t0_i0_insn;
         txn.exception   = vif.t0_i0_exception;
         txn.ecause      = vif.t0_i0_ecause;
         txn.interrupt   = vif.interrupt[0][0];
         txn.tval        = vif.tval[0];
         txn.commit_time = $time;
         txn.cycle_count = cycle_count;

逐段解释：

* 第 74~75 行：声明任务和本地 ``txn`` 句柄。
* 第 77~80 行：无限循环等待 ``posedge vif.clk iff vif.rst_n``；只有复位释放时才递增
  ``cycle_count``。
* 第 82~84 行：i0 valid 时创建一笔新的 ``eh2_trace_seq_item``。
* 第 85~94 行：i0 item 固定 ``thread_id=0``、``slot=0``，并从 ``t0_i0_*``、``interrupt[0][0]``、
  ``tval[0]``、``$time`` 和 ``cycle_count`` 填充退休字段。

接口关系：

* 被调用：``run_phase`` fork ``monitor_trace``。
* 调用：``eh2_trace_seq_item::type_id::create``。
* 共享状态：``cycle_count``、``vif``、``txn``。

§16  i0 regular wb 与 trap CSR snapshot
---------------------------------------

职责：i0 item 的 regular ``wb`` 来自 trace pkt 的 verification-only 字段。若该 item
携带 exception 或 interrupt，monitor 额外从 probe 采样 trap CSR snapshot。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L96-L127``）：

.. code-block:: systemverilog

   // RVFI-equivalent writeback view from RTL trace packet (lane 0).
   txn.wb_valid    = vif.t0_i0_wb_valid;
   txn.wb_dest     = vif.t0_i0_wb_addr;
   txn.wb_data     = vif.t0_i0_wb_data;
   txn.wb_suppress = 0;
   txn.wb_source   = EH2_WB_SRC_REGULAR;
   
   // Sample interrupt/debug/NMI/mcycle state for Spike notification
   populate_cosim_state(txn);
   
   // Capture current wb_seq for async-wb correlation (issue 66)
   if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;
   
   commit_count++;
   if (txn.exception) exception_count++;
   
   // Snapshot trap CSRs when exception or interrupt
   if (txn.exception || txn.interrupt) begin
     if (probe_vif != null) begin
       txn.dut_mtvec  = probe_vif.mtvec;
       txn.dut_mepc   = probe_vif.mepc;
       txn.dut_mcause = probe_vif.mcause;
       txn.dut_mtval  = probe_vif.mtval;  // from RTL TLU mtval register (issue 64)
     end else begin
       txn.dut_mtval  = txn.tval;  // fallback from RTL trace packet
     end
   end
   
   `uvm_info("trace_monitor", $sformatf("Commit: %s wb=%0b rd=x%0d wdata=%08x",
     txn.convert2string(), txn.wb_valid, txn.wb_dest, txn.wb_data), UVM_HIGH)
   ap.write(txn);

逐段解释：

* 第 96~101 行：lane 0 regular writeback 直接来自 ``vif.t0_i0_wb_*``，``wb_suppress`` 被置
  0，``wb_source`` 被标记为 ``EH2_WB_SRC_REGULAR``。
* 第 103~107 行：先调用 ``populate_cosim_state``，再在 ``probe_vif`` 存在时把当前
  ``probe_vif.wb_seq`` 采样到 ``txn.wb_tag``。
* 第 109~110 行：递增 commit 计数；若 item 标记异常，则递增 exception 计数。
* 第 112~121 行：exception 或 interrupt item 从 ``probe_vif`` 采样 ``mtvec``、``mepc``、
  ``mcause``、``mtval``；若没有 probe，则只用 ``txn.tval`` 填 ``dut_mtval`` fallback。
* 第 124~126 行：打印 UVM_HIGH 日志，并通过 ``ap.write(txn)`` 发布 i0 trace item。

接口关系：

* 被调用：``monitor_trace`` 的 i0 valid 分支。
* 调用：``populate_cosim_state``、``txn.convert2string``、``ap.write``。
* 共享状态：``commit_count``、``exception_count``、``probe_vif.wb_seq``、``txn.wb_*``、
  ``txn.dut_*``。

§17  i1 item 构造与发布
-----------------------

职责：i1 使用与 i0 相同的 item 类型和发布路径，但 slot、PC/insn、interrupt bit 和 writeback
lane 都来自第二个 slot。源码对 i1 也采样同一个 ``probe_vif.wb_seq``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L129-L158``）：

.. code-block:: systemverilog

   // Monitor thread 0, instruction 1 (i1)
   if (vif.t0_i1_valid) begin
     txn = eh2_trace_seq_item::type_id::create("trace_txn");
     txn.thread_id   = 0;
     txn.slot        = 1;
     txn.pc          = vif.t0_i1_pc;
     txn.insn        = vif.t0_i1_insn;
     txn.exception   = vif.t0_i1_exception;
     txn.ecause      = vif.t0_i1_ecause;
     txn.interrupt   = vif.interrupt[0][1];
     txn.tval        = vif.tval[0];
     txn.commit_time = $time;
     txn.cycle_count = cycle_count;
   
     // RVFI-equivalent writeback view from RTL trace packet (lane 1).
     txn.wb_valid    = vif.t0_i1_wb_valid;
     txn.wb_dest     = vif.t0_i1_wb_addr;
     txn.wb_data     = vif.t0_i1_wb_data;
     txn.wb_suppress = 0;
     txn.wb_source   = EH2_WB_SRC_REGULAR;
   
     // Sample interrupt/debug/NMI/mcycle state for Spike notification
     populate_cosim_state(txn);
   
     // Capture current wb_seq for async-wb correlation (issue 66)
     if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;
   
     commit_count++;
     if (txn.exception) exception_count++;

逐段解释：

* 第 129~141 行：i1 valid 时创建 item，固定 ``thread_id=0``、``slot=1``，从 ``t0_i1_*`` 和
  ``interrupt[0][1]`` 填写退休字段。
* 第 143~148 行：lane 1 regular writeback 来自 ``vif.t0_i1_wb_*``，source 同样标记为
  ``EH2_WB_SRC_REGULAR``。
* 第 150~154 行：i1 也采样 interrupt/debug/NMI/mcycle 状态，并把当前 ``wb_seq`` 写入
  ``txn.wb_tag``。
* 第 156~158 行：递增 commit 与 exception 统计。

接口关系：

* 被调用：``monitor_trace`` 的 i1 valid 分支。
* 调用：``eh2_trace_seq_item::type_id::create``、``populate_cosim_state``。
* 共享状态：``commit_count``、``exception_count``、``probe_vif.wb_seq``、``txn.wb_*``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L159-L176``）：

.. code-block:: systemverilog

   // Snapshot trap CSRs when exception or interrupt
   if (txn.exception || txn.interrupt) begin
     if (probe_vif != null) begin
       txn.dut_mtvec  = probe_vif.mtvec;
       txn.dut_mepc   = probe_vif.mepc;
       txn.dut_mcause = probe_vif.mcause;
       txn.dut_mtval  = probe_vif.mtval;  // from RTL TLU mtval register (issue 64)
     end else begin
       txn.dut_mtval  = txn.tval;  // fallback from RTL trace packet
     end
   end
   
   `uvm_info("trace_monitor", $sformatf("Commit: %s wb=%0b rd=x%0d wdata=%08x",
     txn.convert2string(), txn.wb_valid, txn.wb_dest, txn.wb_data), UVM_HIGH)
   ap.write(txn);
         end
       end
     endtask

逐段解释：

* 第 159~168 行：i1 exception/interrupt 的 trap CSR snapshot 逻辑与 i0 相同。
* 第 171~173 行：i1 item 记录日志并写入 analysis port。
* 第 174~176 行：结束 i1 分支、循环与 ``monitor_trace`` 任务。

接口关系：

* 被调用：``monitor_trace`` 的 i1 valid 分支。
* 调用：``txn.convert2string``、``ap.write``。
* 共享状态：``probe_vif.mtvec``、``probe_vif.mepc``、``probe_vif.mcause``、
  ``probe_vif.mtval``、``txn.dut_*``。

§18  DUT probe monitor 组件接口
-------------------------------

职责：``eh2_dut_probe_monitor`` 是 async writeback monitor。源码头部注释说明 regular
pipeline writebacks 已经随 ``eh2_trace_seq_item.wb_*`` 进入 trace channel；本 monitor 只发布
DIV writeback、DIV cancel 和 NB-load completion。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L13-L26``）：

.. code-block:: systemverilog

   class eh2_dut_probe_monitor extends uvm_monitor;
   
     `uvm_component_utils(eh2_dut_probe_monitor)
   
     virtual eh2_dut_probe_if vif;
     uvm_analysis_port #(eh2_trace_seq_item) ap;
   
     int wb_count;
     int wb_seq_counter;  // global writeback sequence (issue 66)
   
     function new(string name, uvm_component parent);
       super.new(name, parent);
       wb_seq_counter = 1;  // start from 1 so wb_tag >= 1 always (issue 66)
     endfunction

逐段解释：

* 第 13 行：``eh2_dut_probe_monitor`` 继承 ``uvm_monitor``。
* 第 17~18 行：monitor 读取 ``eh2_dut_probe_if``，并通过 ``ap`` 发布
  ``eh2_trace_seq_item`` 类型的 async hint。
* 第 20~21 行：``wb_count`` 统计 async ``wb`` 数量，``wb_seq_counter`` 是全局 writeback
  sequence。
* 第 23~26 行：构造函数把 ``wb_seq_counter`` 初始化为 1，使后续 ``wb_tag`` 从非零值开始。

接口关系：

* 被调用：env factory create。
* 调用：``super.new``。
* 共享状态：``vif``、``ap``、``wb_count``、``wb_seq_counter``。

§19  DUT probe monitor 启动两条并行采样任务
--------------------------------------------

职责：DUT probe monitor 只有在拿到 ``vif`` 时才 fork DIV 与 NB-load 两条采样任务。缺少
``vif`` 时，它只报警并禁用 async writeback monitoring。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L28-L47``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     ap = new("ap", this);
   endfunction
   
   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
     if (!uvm_config_db#(virtual eh2_dut_probe_if)::get(this, "", "vif", vif)) begin
       `uvm_warning("dut_probe", "Could not get DUT probe virtual interface - async writeback monitoring disabled")
     end
   endfunction
   
   task run_phase(uvm_phase phase);
     if (vif != null) begin
       fork
         monitor_division();
         monitor_nb_load();
       join
     end
   endtask

逐段解释：

* 第 28~31 行：build phase 创建 analysis port ``ap``。
* 第 33~38 行：connect phase 从 config DB 获取 ``vif``，失败时只报 warning。
* 第 40~47 行：run phase 在 ``vif`` 非空时 fork ``monitor_division`` 和 ``monitor_nb_load``。
  两个任务长期运行，因此这里使用 ``join`` 等待两条 forever 任务。

接口关系：

* 被调用：UVM build/connect/run phase。
* 调用：``uvm_config_db::get``、``monitor_division``、``monitor_nb_load``。
* 共享状态：``vif`` 与 ``ap``。

§20  DIV writeback async item
-----------------------------

职责：``monitor_division`` 在每个复位释放后的上升沿检测 DIV writeback。只有
``div_wren`` 有效且 ``div_rd`` 非零时才发布 async item。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L49-L70``）：

.. code-block:: systemverilog

   // Monitor DIV writebacks and DIV-cancel events.
   task monitor_division();
     eh2_trace_seq_item txn;
   
     forever begin
       @(posedge vif.clk iff vif.rst_n);
   
       if (vif.div_wren && vif.div_rd != 5'b0) begin
         txn = eh2_trace_seq_item::type_id::create("div_wb_txn");
         txn.slot      = 0;  // Divides are i0-only
         txn.wb_valid  = 1;
         txn.wb_dest   = vif.div_rd;
         txn.wb_data   = vif.div_wdata;
         txn.wb_source = EH2_WB_SRC_DIV;
         txn.wb_tag    = wb_seq_counter;
         vif.wb_seq    = wb_seq_counter;  // write to interface for trace_monitor (issue 66)
         ap.write(txn);
         `uvm_info("dut_probe", $sformatf("DIV WB: x%0d = %08x wb_tag=%0d",
           vif.div_rd, vif.div_wdata, wb_seq_counter), UVM_HIGH)
         wb_count++;
         wb_seq_counter++;
       end

逐段解释：

* 第 50~54 行：任务声明本地 item，并在 ``posedge vif.clk iff vif.rst_n`` 上采样。
* 第 56 行：DIV writeback 只在 ``div_wren`` 且目的寄存器不是 x0 时进入发布路径。
* 第 57~63 行：创建 ``div_wb_txn``，写 ``slot=0``、``wb_valid=1``、目的寄存器、数据、
  ``EH2_WB_SRC_DIV`` 和当前 ``wb_seq_counter``。
* 第 64~65 行：把同一个 ``wb_seq_counter`` 写入 ``vif.wb_seq`` 供 trace monitor 采样，
  并通过 analysis port 发布 item。
* 第 66~69 行：记录日志，递增 ``wb_count`` 和 ``wb_seq_counter``。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：``eh2_trace_seq_item::type_id::create``、``ap.write``。
* 共享状态：``vif.div_*``、``vif.wb_seq``、``wb_count``、``wb_seq_counter``。

§21  DIV overwrite cancel 与 speculative cancel
------------------------------------------------

职责：DIV cancel 分成两类。``div_cancel && div_cancel_overwrite`` 会发布
``wb_suppress=1`` 的 suppress item；``div_cancel && !div_cancel_overwrite`` 只记录日志并丢弃，
因为源码注释说明 speculative-flush cancel 没有匹配 trace。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L71-L96``）：

.. code-block:: systemverilog

   else if (vif.div_cancel && vif.div_cancel_overwrite && vif.div_rd != 5'b0) begin
     // Only forward "overwrite" cancels: these pair with a retired div
     // trace whose architectural writeback was killed by a younger same-rd
     // write. Speculative-flush cancels (no matching trace) are dropped.
     txn = eh2_trace_seq_item::type_id::create("div_cancel_txn");
     txn.slot        = 0;
     txn.wb_valid    = 1;
     txn.wb_dest     = vif.div_rd;
     txn.wb_data     = vif.div_result;
     txn.wb_suppress = 1;
     txn.wb_source   = EH2_WB_SRC_DIV;
     txn.wb_tag      = wb_seq_counter;
     vif.wb_seq      = wb_seq_counter;
     ap.write(txn);
     `uvm_info("dut_probe", $sformatf("DIV OVERWRITE-CANCEL: x%0d = %08x wb_tag=%0d",
       vif.div_rd, vif.div_result, wb_seq_counter), UVM_HIGH)
     wb_count++;
     wb_seq_counter++;
   end
   else if (vif.div_cancel && !vif.div_cancel_overwrite) begin
     `uvm_info("dut_probe", $sformatf(
       "DIV SPEC-CANCEL: x%0d (dropped, no paired trace)",
       vif.div_rd), UVM_HIGH)
   end

逐段解释：

* 第 71 行：overwrite cancel 路径要求 ``div_cancel``、``div_cancel_overwrite`` 同时有效，且
  ``div_rd`` 不是 x0。
* 第 72~74 行：源码注释说明只有 overwrite cancel 与已退休 DIV trace 配对，speculative
  flush cancel 没有 matching trace。
* 第 75~83 行：创建 ``div_cancel_txn``，写 ``wb_valid=1``、``wb_suppress=1``、source 为
  ``EH2_WB_SRC_DIV``，并用当前 sequence 作为 ``wb_tag`` 和 ``vif.wb_seq``。
* 第 84~88 行：发布 item、记录日志、递增计数器。
* 第 90~94 行：speculative cancel 只写日志，不发布 analysis item。

接口关系：

* 被调用：``monitor_division``。
* 调用：``eh2_trace_seq_item::type_id::create``、``ap.write``、``uvm_info``。
* 共享状态：``vif.div_cancel``、``vif.div_cancel_overwrite``、``vif.div_result``、
  ``vif.wb_seq``、``wb_seq_counter``。

§22  NB-load async item
-----------------------

职责：``monitor_nb_load`` 检测 non-blocking load completion。只有 ``nb_load_wen`` 有效且
目的寄存器不是 x0 时才发布 ``EH2_WB_SRC_NB_LOAD`` item。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L98-L121``）：

.. code-block:: systemverilog

   // Monitor non-blocking load completions.
   task monitor_nb_load();
     eh2_trace_seq_item txn;
   
     forever begin
       @(posedge vif.clk iff vif.rst_n);
   
       if (vif.nb_load_wen && vif.nb_load_waddr != 5'b0) begin
         txn = eh2_trace_seq_item::type_id::create("nb_load_txn");
         txn.slot      = 0;
         txn.wb_valid  = 1;
         txn.wb_dest   = vif.nb_load_waddr;
         txn.wb_data   = vif.nb_load_data;
         txn.wb_source = EH2_WB_SRC_NB_LOAD;
         txn.wb_tag    = wb_seq_counter;
         vif.wb_seq    = wb_seq_counter;  // issue 66
         ap.write(txn);
         `uvm_info("dut_probe", $sformatf("NB LOAD: x%0d = %08x wb_tag=%0d",
           vif.nb_load_waddr, vif.nb_load_data, wb_seq_counter), UVM_HIGH)
         wb_count++;
         wb_seq_counter++;
       end
     end
   endtask

逐段解释：

* 第 99~103 行：任务在复位释放后的每个 ``vif.clk`` 上升沿采样。
* 第 105 行：NB-load completion 路径要求 ``nb_load_wen`` 有效且 ``nb_load_waddr`` 非 x0。
* 第 106~113 行：创建 ``nb_load_txn``，写 ``wb_valid``、目的寄存器、数据、
  ``EH2_WB_SRC_NB_LOAD``、``wb_tag``，并把 ``wb_seq`` 写回 interface。
* 第 114~118 行：发布 item、记录日志、递增 ``wb_count`` 与 ``wb_seq_counter``。
* 第 119~121 行：结束条件分支与 forever 任务。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：``eh2_trace_seq_item::type_id::create``、``ap.write``。
* 共享状态：``vif.nb_load_*``、``vif.wb_seq``、``wb_count``、``wb_seq_counter``。

§23  ``wb_seq`` 与 ``wb_tag`` 的严格关联
----------------------------------------

职责：``wb_seq`` 是 DUT probe interface 中的全局 writeback sequence。DUT probe monitor
在 DIV/NB-load async event 上写 ``vif.wb_seq``；trace monitor 在 retire item 上采样为
``txn.wb_tag``；cosim scoreboard 用 strict ``wb_tag`` 匹配 async hint。

关键代码（``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L71-L75``）：

.. code-block:: systemverilog

   // Global writeback sequence counter (issue 66: strict wb_seq ordering)
   // Incremented by probe_monitor for each non-suppressed wb event.
   // Read by trace_monitor to tag trace items for async_wb matching.
   logic [15:0]      wb_seq;

逐段解释：

* 第 71 行：源码注释把该计数器命名为 strict ``wb_seq`` ordering。
* 第 72 行：注释说明计数器由 probe monitor 在 writeback event 上递增。
* 第 73 行：注释说明 trace monitor 读取该值，用于 async ``wb`` matching。
* 第 74 行：``wb_seq`` 是 16 bit logic 字段。

接口关系：

* 被调用：``eh2_dut_probe_monitor`` 写该字段，``eh2_trace_monitor`` 读该字段。
* 调用：无函数调用。
* 共享状态：``wb_seq`` 是 probe monitor、trace monitor 和 cosim scoreboard 的关联键来源。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L91-L100``）：

.. code-block:: systemverilog

   // Async writeback hints from the dut probe (NB-load wb / DIV cancel).
   // Per-thread queues. wb_tag enables strict ordering match (issue 66).
   typedef struct {
     bit [4:0]  rd;
     bit [31:0] rd_data;
     bit        suppress;
     int        source;
     int        wb_tag;       // global wb_seq from probe_monitor
   } async_wb_hint_t;
   async_wb_hint_t async_wb_q[2][$];

逐段解释：

* 第 91~92 行：scoreboard 把 DUT probe 进入的 NB-load/DIV cancel 视作 async writeback hint，
  并声明 ``wb_tag`` 支持 strict ordering match。
* 第 93~99 行：``async_wb_hint_t`` 保存目的寄存器、数据、suppress 标志、source 和 ``wb_tag``。
* 第 100 行：``async_wb_q`` 是两个线程各自的队列。

接口关系：

* 被调用：scoreboard async probe path 与 pending trace path。
* 调用：SystemVerilog typedef。
* 共享状态：``async_wb_q`` 保存来自 DUT probe FIFO 的 hint。

§24  Scoreboard 接收 DUT probe FIFO
-----------------------------------

职责：cosim scoreboard 的 ``run_cosim_probe_async`` 从 ``dut_probe_fifo`` 取 item，丢弃
regular source，只把 DIV/NB-load hint 推入 ``async_wb_q``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L231-L258``）：

.. code-block:: systemverilog

   forever begin
     dut_probe_fifo.get(probe_item);
     probe_item_count++;
   
     // Drop regular writebacks - the trace channel already carries them.
     if (probe_item.wb_source == EH2_WB_SRC_REGULAR) continue;
   
     hint.rd       = probe_item.wb_dest;
     hint.rd_data  = probe_item.wb_data;
     hint.suppress = probe_item.wb_suppress;
     hint.source   = probe_item.wb_source;
     hint.wb_tag   = probe_item.wb_tag;  // strict ordering tag (issue 66)
   
     begin
       int tid = int'(probe_item.thread_id);
       async_wb_q[tid].push_back(hint);
   
       `uvm_info("cosim", $sformatf(
         "ASYNC_WB: T%0d src=%s rd=x%0d data=%08x suppress=%0b qsize=%0d",
         tid, wb_source_name(probe_item.wb_source), probe_item.wb_dest,
         probe_item.wb_data, probe_item.wb_suppress, async_wb_q[tid].size()), UVM_HIGH)
   
       if (cosim_handle != null && initialized) begin
         process_pending_trace(tid);
       end
     end
   end

逐段解释：

* 第 231~233 行：scoreboard 阻塞读取 ``dut_probe_fifo``，并递增 ``probe_item_count``。
* 第 235~236 行：regular writeback 被跳过，因为 trace channel 已经携带 regular ``wb``。
* 第 238~242 行：从 probe item 填充 async hint，并把 ``probe_item.wb_tag`` 作为 strict
  ordering tag。
* 第 245~246 行：按 ``thread_id`` 选择队列，把 hint push 到 ``async_wb_q[tid]``。
* 第 248~255 行：记录日志；如果 Spike 句柄已初始化，则立即尝试处理对应线程的 pending trace。

接口关系：

* 被调用：scoreboard run phase 的 async probe 线程。
* 调用：``dut_probe_fifo.get``、``async_wb_q.push_back``、``process_pending_trace``。
* 共享状态：``probe_item_count``、``async_wb_q``、``cosim_handle``、``initialized``。

§25  Scoreboard 对 async wb 的阻塞条件
--------------------------------------

职责：pending trace 只有在 memory access 与 async ``wb`` 条件满足后才 step。DIV 或
NB-load trace item 如果需要 async ``wb``，且当前没有 matching hint，则留在队列头等待。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L277-L286``）：

.. code-block:: systemverilog

   // True if the trace item describes an instruction whose architectural
   // writeback arrives on an async channel (DIV unit / NB-load) instead of
   // the regular pipeline. Wait for the matching async hint before stepping.
   function bit needs_async_wb(eh2_trace_seq_item item);
     if (item.exception || item.interrupt) return 1'b0;
     if (!item.writes_rd()) return 1'b0;
     if (item.is_div()) return 1'b1;
     if (needs_nb_load_async_wb(item)) return 1'b1;
     return 1'b0;
   endfunction

逐段解释：

* 第 277~279 行：注释说明该函数判断 architectural writeback 是否来自 DIV/NB-load async
  channel。
* 第 280~282 行：exception、interrupt 和不写 GPR 的指令不等待 async ``wb``。
* 第 283 行：DIV 指令需要 async ``wb``。
* 第 284 行：``needs_nb_load_async_wb`` 判断 NB-load async 场景。
* 第 285~286 行：其它指令不等待 async ``wb``，函数结束。

接口关系：

* 被调用：``process_pending_trace``。
* 调用：``item.writes_rd``、``item.is_div``、``needs_nb_load_async_wb``。
* 共享状态：只读 trace item。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L288-L327``）：

.. code-block:: systemverilog

   // Drain pending_trace_q[tid] in order. Gates:
   //   - stores/AMOs wait for matching LSU AXI access (with coalescing bypass)
   //   - DIV / NB-load trace items wait for the matching async writeback hint
   function void process_pending_trace(int tid);
     while (pending_trace_q[tid].size() > 0) begin
       pending_trace_t pending = pending_trace_q[tid][0];
   
       if (must_wait_for_memory_access(pending.item) &&
           !has_matching_memory_access(pending.item)) begin
         if (store_trace_stepped > store_axi_delivered) begin
           `uvm_info("cosim", $sformatf(
             "T%0d Store at PC=%08x insn=%08x — coalesced (stepped=%0d > axi=%0d), proceeding without AXI",
             tid, pending.item.pc, pending.item.insn, store_trace_stepped, store_axi_delivered), UVM_LOW)
         end else begin
           `uvm_info("cosim", $sformatf(
             "T%0d Waiting for LSU AXI access before stepping store/AMO PC=%08x insn=%08x (stepped=%0d, axi=%0d)",

逐段解释：

* 第 288~291 行：注释列出两个 gate：store/AMO 等待 LSU AXI access，DIV/NB-load 等待
  async writeback hint。
* 第 292~293 行：只处理 ``pending_trace_q[tid]`` 队头，保证每线程 trace 顺序。
* 第 295~305 行：memory instruction 需要 AXI access 时，如果没有 matching memory access，
  除 store coalescing bypass 外会停止处理。
* 第 307 行之后的源码继续检查 async ``wb`` gate；本片段只展示前半段 memory gate。

接口关系：

* 被调用：trace FIFO 线程、DUT probe FIFO 线程和 LSU AXI 线程在新输入到来时调用。
* 调用：``must_wait_for_memory_access``、``has_matching_memory_access``、``uvm_info``。
* 共享状态：``pending_trace_q``、``store_trace_stepped``、``store_axi_delivered``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L309-L327``）：

.. code-block:: systemverilog

   if (needs_async_wb(pending.item) && !has_matching_async_wb(tid, pending.item)) begin
     `uvm_info("cosim", $sformatf(
       "T%0d Waiting for async wb (DIV) before stepping PC=%08x insn=%08x rd=x%0d",
       tid, pending.item.pc, pending.item.insn, pending.item.get_write_rd()), UVM_HIGH)
     break;
   end
   
   pending_trace_q[tid].pop_front();
   if (is_memory_instruction(pending.item) &&
       has_matching_memory_access(pending.item)) begin
     pop_matching_memory_access(pending.item);
   end
   // Track store trace items stepped (for coalescing detection).
   if (is_store_or_amo_instruction(pending.item)) begin
     store_trace_stepped++;
   end
   compare_instruction(tid, pending.item);
     end
   endfunction

逐段解释：

* 第 309~314 行：如果 item 需要 async ``wb`` 且 ``has_matching_async_wb`` 为假，函数
  ``break``，保留该 item 在 pending queue 队头。
* 第 316~320 行：gate 满足后弹出队头；若是 memory instruction 且存在 matching memory
  access，则弹出对应 memory access。
* 第 322~324 行：store/AMO 被 step 前递增 ``store_trace_stepped``。
* 第 325 行：调用 ``compare_instruction``，真正进入 Spike/DUT 比对路径。
* 第 326~327 行：结束 while 与函数。

接口关系：

* 被调用：``process_pending_trace`` 内部。
* 调用：``needs_async_wb``、``has_matching_async_wb``、``pop_matching_memory_access``、
  ``compare_instruction``。
* 共享状态：``pending_trace_q``、``store_trace_stepped``。

§26  Trace item 字段与 helper 谓词
----------------------------------

职责：``eh2_trace_seq_item`` 是 trace/probe 两条 analysis 流的共同 item 类型。它同时保存
retire 信息、writeback 信息、Spike 通知状态、trap CSR snapshot 和时间戳。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L7-L32``）：

.. code-block:: systemverilog

   class eh2_trace_seq_item extends uvm_sequence_item;
   
     // Thread ID
     rand bit thread_id;
   
     // Instruction slot (0 or 1 - EH2 can commit 2 per cycle)
     rand bit slot;
   
     // Instruction information
     bit [31:0] pc;
     bit [31:0] insn;
   
     // Exception information
     bit        exception;
     bit [4:0]  ecause;
     bit        interrupt;
     bit [31:0] tval;
   
     // Register writeback (from DUT probe)
     bit        wb_valid;
     bit [4:0]  wb_dest;
     bit [31:0] wb_data;
     bit        wb_suppress;  // Writeback suppressed (killed load or canceled DIV)
     int        wb_tag;       // Writeback sequence tag for trace-to-wb correlation
     int        wb_source;    // EH2_WB_SRC_*: regular, DIV, or non-blocking load

逐段解释：

* 第 7 行：item 继承 ``uvm_sequence_item``，可通过 UVM factory 创建。
* 第 10~13 行：``thread_id`` 和 ``slot`` 描述该 item 对应的线程与指令槽。
* 第 16~23 行：``pc``、``insn``、exception、``ecause``、interrupt 和 ``tval`` 来自
  trace pkt。
* 第 26~31 行：``wb_valid``、``wb_dest``、``wb_data``、``wb_suppress``、``wb_tag`` 和
  ``wb_source`` 表达 regular 或 async writeback 信息。

接口关系：

* 被调用：trace monitor 和 DUT probe monitor 创建该 item；scoreboard 消费该 item。
* 调用：无函数调用。
* 共享状态：item 字段跨 monitor 与 scoreboard 传递。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L167-L224``）：

.. code-block:: systemverilog

   // Check if instruction is a DIV/REM operation. MUL operations use the same
   // opcode/funct7 but write through the normal pipeline, not the DIV monitor.
   function bit is_div();
     if (is_compressed()) return 1'b0;
     return (get_opcode() == 7'b0110011 &&
             insn[31:25] == 7'b0000001 &&
             insn[14:12] inside {3'b100, 3'b101, 3'b110, 3'b111});
   endfunction
   
   // Check if instruction is compressed
   function bit is_compressed();
     return (insn[1:0] != 2'b11);
   endfunction
   
   // Check if compressed instruction performs a load/store.
   // RV32C memory opcodes: C.LW/C.SW in quadrant 0, C.LWSP/C.SWSP in quadrant 2.
   function bit is_compressed_load_store();
     bit [2:0] funct3;
     bit [1:0] quadrant;

逐段解释：

* 第 167~174 行：``is_div`` 排除 compressed instruction，然后匹配 R-type opcode
  ``7'b0110011``、M extension ``funct7`` 和 DIV/REM 系列 ``funct3``。
* 第 176~179 行：``is_compressed`` 通过 ``insn[1:0] != 2'b11`` 判断 compressed instruction。
* 第 181~187 行：``is_compressed_load_store`` 先声明 ``funct3``、``quadrant``，再排除非
  compressed instruction。
* 第 189 行之后的源码继续按 quadrant 和 ``funct3`` 判断 C.LW/C.SW/C.LWSP/C.SWSP。

接口关系：

* 被调用：cosim scoreboard 的 async gate 与 memory gate 使用这些 helper。
* 调用：``is_div`` 调 ``is_compressed`` 与 ``get_opcode``。
* 共享状态：只读 ``insn`` 字段。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L202-L224``）：

.. code-block:: systemverilog

   // Get architectural destination register for instructions that write GPRs.
   function bit [4:0] get_write_rd();
     if (is_compressed()) return get_compressed_rd();
     return get_rd();
   endfunction
   
   // Check if instruction writes to register
   function bit writes_rd();
     if (is_compressed()) begin
       return get_compressed_rd() != 5'b0;
     end
   
     if (get_rd() == 5'b0) return 1'b0;
   
     if (get_opcode() inside {7'b0110011, 7'b0010011, 7'b0110111,
                              7'b0010111, 7'b1101111, 7'b1100111,
                              7'b0000011, 7'b0101111}) begin
       return 1'b1;
     end
   
     // CSR instructions write rd when funct3 is nonzero.
     return (get_opcode() == 7'b1110011 && insn[14:12] != 3'b000);
   endfunction

逐段解释：

* 第 202~206 行：``get_write_rd`` 对 compressed instruction 调 ``get_compressed_rd``，
  其它 instruction 调 ``get_rd``。
* 第 208~214 行：``writes_rd`` 对 compressed instruction 判断 compressed destination 是否
  非 x0；对非 compressed instruction 先排除 ``rd=x0``。
* 第 216~220 行：R/I/U/J/load/AMO 等 opcode 被视为写 GPR。
* 第 222~223 行：CSR instruction 只有 ``funct3`` 非 0 时写 ``rd``。

接口关系：

* 被调用：scoreboard ``needs_async_wb`` 和日志路径使用。
* 调用：``is_compressed``、``get_compressed_rd``、``get_rd``、``get_opcode``。
* 共享状态：只读 ``insn``。

§27  端到端时序关系
-------------------

Trace/probe 路径的关键时序是：DUT probe monitor 看到 async ``wb`` 时先写
``vif.wb_seq`` 并发布 async hint；trace monitor 在 retire item 上采样当前 ``wb_seq``；
scoreboard 只在 ``wb_tag`` 匹配时消费 async hint。regular ``wb`` 不走 DUT probe FIFO，
而是已经在 trace item 的 ``wb_*`` 字段内。

::

   posedge core_clk, rst_l=1
      |
      +-- DUT trace pkt updates t0_i0/t0_i1 retire fields
      |
      +-- trace_monitor:
      |      create trace_txn
      |      fill pc/insn/exception/interrupt/tval
      |      fill wb_valid/wb_dest/wb_data from trace pkt
      |      sample probe_vif.wb_seq into txn.wb_tag
      |      ap.write(txn)
      |
      +-- dut_probe_monitor:
             if DIV/NB-load event:
                fill async txn wb_* fields
                write vif.wb_seq
                ap.write(txn)

Scoreboard 接收顺序由两个 FIFO 解耦：``trace_fifo`` 接收 retire item，``dut_probe_fifo``
接收 async hint。``process_pending_trace`` 在需要 async ``wb`` 的 item 上等待
``has_matching_async_wb``，因此 trace item 和 async hint 即使先后到达不同，也通过
``wb_tag`` 统一关联。

§28  参考资料
--------------

* :ref:`appendix_b_uvm_trace_agent` — trace monitor 与 DUT probe monitor 源码字典。
* :ref:`agent_cosim` — cosim scoreboard 架构说明。
* :ref:`rvfi_trace` — RTL RVFI-equivalent trace 背景。
* :ref:`appendix_a_rtl_dec` — DEC 侧 trace 生成逻辑参考。
* :ref:`adr-0004` — RTL RVFI-equivalent trace。
* :ref:`adr-0018` — strict ``wb_tag`` matching。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_dut_probe_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv``。

§29  与 Ibex 工业实现对照
-------------------------

Ibex cosim 使用 ``ibex_rvfi_monitor`` 和 ``ibex_rvfi_seq_item``，RVFI item 本身携带
指令、PC、trap、rd/wdata、interrupt/debug sideband。EH2 不能直接复用该路径，因为
上游 EH2 RTL 没有原生 Ibex 风格 RVFI bus；当前平台采用 trace packet + DUT probe
组合，并在 TB top 中额外实例化 ``eh2_veer_wrapper_rvfi`` 作为 RVFI sidecar。这个设计
保持上游 RTL 最小侵入，同时给 cosim 和 formal/RVFI smoke 提供各自合适的观察面。

.. list-table:: Trace/RVFI 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - 主监视器
     - ``ibex_rvfi_monitor``
     - ``eh2_trace_monitor`` + ``eh2_dut_probe_monitor``
   * - 主 item
     - ``ibex_rvfi_seq_item``
     - ``eh2_trace_seq_item``
   * - 写回来源
     - RVFI rd/wdata 字段
     - trace packet regular wb + probe async hint
   * - 异步补偿
     - RVFI/scoreboard 内部处理
     - strict ``wb_tag`` 匹配 DIV/NB-load hint
   * - 双线程
     - 单 hart 路径为主
     - ``thread_id`` 和 per-thread scoreboard queue

§30  Sign-off 关联
------------------

trace/probe 是 EH2 cosim 可信度的核心。2026-05-19 demo 中 riscv-dv 370/395、
directed 40/40、formal 46/46 和 LEC 31635/31635 都依赖 trace/RVFI/probe 口径一致。
修改 trace item 字段、``wb_tag`` 生成、trap CSR snapshot 或 probe interface 后，应复跑
rvfi smoke、cosim directed、interrupt/debug directed 和至少一组 riscv-dv random。
