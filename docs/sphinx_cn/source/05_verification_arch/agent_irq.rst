.. _agent_irq:
.. _05_verification_arch/agent_irq:

IRQ Agent — 架构参考
=====================

:status: draft
:source: dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章边界
------------

本章解释 IRQ agent 在 EH2 UVM 环境中的 stimulus 路径。逐类源码字典见
:ref:`appendix_b_uvm_irq_agent`；这里聚焦 agent 与 DUT interrupt pins、DUT probe
和 cosim 通知之间的边界。当前源码目录没有 IRQ monitor 类，``eh2_irq_agent`` 也没有
monitor 成员，因此本章只描述 driver/sequencer 路径。

IRQ agent 目录包含 7 个源文件：

* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_sequencer.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv`

§2  架构数据流
--------------

IRQ agent 的主路径是 ``eh2_irq_seq_item`` 从 sequencer 到 driver，再到
``eh2_irq_intf``。testbench 把 interface 内部信号连续赋值到 DUT 的 interrupt
端口，同时把这些信号映射到 ``dut_probe_intf``，供 trace/cosim 侧采样 mip/NMI
状态。

.. code-block:: text

   core_eh2_vseqr.irq_seqr
          |
          v
   eh2_irq_sequencer
          |
          v
   eh2_irq_driver.seq_item_port
          |
          v
   eh2_irq_intf
          |
          +--> timer_int[NUM_THREADS-1:0]
          +--> soft_int[NUM_THREADS-1:0]
          +--> extintsrc_req[PIC_TOTAL_INT:1]
          +--> nmi_int
          |
          +--> DUT interrupt inputs
          |
          `--> dut_probe_intf.mip / nmi / nmi_int

接口关系：

* 被调用：virtual sequence 或 helper sequence 通过 ``irq_seqr`` 启动 IRQ item。
* 调用：driver 调 ``drive_interrupt``，按 ``irq_type`` 写 interface 信号。
* 共享状态：``irq_vif``、``irq_type``、``irq_id``、``irq_val``、``duration``。

§3  Package 与类组成
--------------------

职责：``eh2_irq_agent_pkg`` 汇入事务、driver、sequencer、sequence 和 top-level
agent。这个 package 没有 include monitor 文件。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent_pkg.sv:L4-L15``）：

.. code-block:: systemverilog

   package eh2_irq_agent_pkg;
   
     `include "uvm_macros.svh"
     import uvm_pkg::*;
   
     `include "eh2_irq_seq_item.sv"
     `include "eh2_irq_driver.sv"
     `include "eh2_irq_sequencer.sv"
     `include "eh2_irq_seq.sv"
     `include "eh2_irq_agent.sv"
   
   endpackage

逐段解释：

* 第 4 行：声明 ``eh2_irq_agent_pkg``。
* 第 6~7 行：引入 UVM 宏和 ``uvm_pkg``。
* 第 9~13 行：include 顺序先给出 ``eh2_irq_seq_item``，再给出 driver、sequencer、
  sequence 和 agent。driver、sequencer 和 sequence 都依赖 ``eh2_irq_seq_item``。

接口关系：

* 被调用：env package import IRQ agent package。
* 调用：SystemVerilog include。
* 共享状态：无运行期状态。

§4  Env active 配置与 virtual sequencer
---------------------------------------

职责：env 创建 IRQ agent，并把 ``is_active`` 配置为 ``UVM_ACTIVE``。connect phase
把 ``irq_agent.sequencer`` 暴露给 virtual sequencer。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L87-L89``）：

.. code-block:: systemverilog

   // Interrupt agent (active)
   irq_agent = eh2_irq_agent::type_id::create("irq_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "irq_agent", "is_active", UVM_ACTIVE);

逐段解释：

* 第 88 行：env 通过 factory 创建 ``irq_agent``。
* 第 89 行：``irq_agent`` 的 ``is_active`` 被设置成 ``UVM_ACTIVE``，使其 build phase
  创建 driver 和 sequencer。

接口关系：

* 被调用：UVM build phase。
* 调用：``eh2_irq_agent::type_id::create``、``uvm_config_db::set``。
* 共享状态：``irq_agent`` 与 ``is_active``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L171``）：

.. code-block:: systemverilog

   // Wire sub-sequencers to virtual sequencer
   vseqr.irq_seqr      = irq_agent.sequencer;
   vseqr.jtag_seqr     = jtag_agent.sequencer;

逐段解释：

* 第 170 行：``irq_agent.sequencer`` 被赋给 ``vseqr.irq_seqr``，virtual sequence
  通过该句柄提交 IRQ transaction。
* 第 171 行：JTAG sequencer 在相邻代码中以同样方式接入，说明 env 以句柄赋值而非
  TLM 端口连接方式组织 virtual sequencer。

接口关系：

* 被调用：UVM connect phase。
* 调用：普通句柄赋值。
* 共享状态：``vseqr.irq_seqr``。

§5  Agent 内部组件
------------------

职责：``eh2_irq_agent`` 在 active 模式创建 driver 与 typed sequencer，并连接
``seq_item_port`` 与 ``seq_item_export``。源码没有 monitor 成员。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv:L7-L33``）：

.. code-block:: systemverilog

   class eh2_irq_agent extends uvm_agent;
   
     `uvm_component_utils(eh2_irq_agent)
   
     eh2_irq_driver    driver;
     eh2_irq_sequencer sequencer;
   
     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
   
       if (get_is_active() == UVM_ACTIVE) begin
         driver    = eh2_irq_driver::type_id::create("driver", this);
         sequencer = eh2_irq_sequencer::type_id::create("sequencer", this);
       end
     endfunction
   
     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
   
       if (get_is_active() == UVM_ACTIVE) begin
         driver.seq_item_port.connect(sequencer.seq_item_export);
       end
     endfunction

逐段解释：

* 第 11~12 行：agent 只有 ``driver`` 和 ``sequencer`` 两个成员。
* 第 21~24 行：active 模式下创建 driver 和 sequencer。
* 第 30~31 行：active 模式下把 driver 的 seq item port 连接到 sequencer export。

接口关系：

* 被调用：env 创建 agent 后由 UVM phase 调用。
* 调用：UVM factory 与 seq item port/export connect。
* 共享状态：``is_active``、``driver``、``sequencer``。

§6  IRQ interface 信号集合
--------------------------

职责：``eh2_irq_intf`` 定义四类 interrupt stimulus 信号，并提供 driver/monitor
clocking block。虽然当前 agent 没有 monitor 类，interface 仍保留 monitor modport。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv:L7-L27``）：

.. code-block:: systemverilog

   interface eh2_irq_intf #(
     parameter NUM_THREADS = 1,
     parameter PIC_TOTAL_INT = 127
   )(
     input logic clk,
     input logic rst_n
   );
   
     // Interrupt signals
     logic [NUM_THREADS-1:0]   timer_int;
     logic [NUM_THREADS-1:0]   soft_int;
     logic [PIC_TOTAL_INT:1]   extintsrc_req;
     logic                     nmi_int;
   
     // Default values
     initial begin
       timer_int     = '0;
       soft_int      = '0;
       extintsrc_req = '0;
       nmi_int       = 1'b0;
     end

逐段解释：

* 第 7~13 行：interface 参数化 ``NUM_THREADS`` 和 ``PIC_TOTAL_INT``，并绑定 clock/reset。
* 第 16~19 行：``timer_int`` 与 ``soft_int`` 按 thread 数展开，
  ``extintsrc_req`` 的索引范围是 ``[PIC_TOTAL_INT:1]``，NMI 是单 bit。
* 第 22~27 行：initial block 把四类 interrupt 信号清零。

接口关系：

* 被调用：testbench 实例化 ``irq_intf``。
* 调用：无函数调用。
* 共享状态：``timer_int``、``soft_int``、``extintsrc_req``、``nmi_int``。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv:L29-L55``）：

.. code-block:: systemverilog

   // Driver clocking block
   clocking driver_cb @(posedge clk);
     output timer_int;
     output soft_int;
     output extintsrc_req;
     output nmi_int;
   endclocking
   
   // Monitor clocking block
   clocking monitor_cb @(posedge clk);
     input timer_int;
     input soft_int;
     input extintsrc_req;
     input nmi_int;
   endclocking
   
   // Modport for driver
   modport driver (
     input clk, rst_n,
     clocking driver_cb
   );
   
   // Modport for monitor
   modport monitor (
     input clk, rst_n,
     clocking monitor_cb

逐段解释：

* 第 30~35 行：driver clocking block 将四类 interrupt 信号声明为 output。
* 第 38~43 行：monitor clocking block 将同一组信号声明为 input。
* 第 46~55 行：driver/monitor modport 暴露不同 clocking block 和 clock/reset。

接口关系：

* 被调用：driver 通过 virtual interface 写信号。
* 调用：SystemVerilog clocking block。
* 共享状态：``driver_cb`` 与 ``monitor_cb``。

§7  Testbench 与 DUT 接线
-------------------------

职责：testbench 用 RTL 宏参数实例化 ``irq_intf``，然后把 interface 信号接到 DUT 的
interrupt 输入端口，并通过 config_db 发布 ``irq_vif``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L893-L904``）：

.. code-block:: systemverilog

   // IRQ Interface Instance (for interrupt stimulus)
   //--------------------------------------------------------------------------
   eh2_irq_intf #(
     .NUM_THREADS  (`RV_NUM_THREADS),
     .PIC_TOTAL_INT(`RV_PIC_TOTAL_INT)
   ) irq_intf (.clk(core_clk), .rst_n(rst_l));
   
   // Connect IRQ interface to DUT interrupt signals
   assign timer_int     = irq_intf.timer_int;
   assign soft_int      = irq_intf.soft_int;
   assign extintsrc_req = irq_intf.extintsrc_req;
   assign nmi_int       = irq_intf.nmi_int;

逐段解释：

* 第 895~898 行：``irq_intf`` 的参数来自 ``RV_NUM_THREADS`` 和
  ``RV_PIC_TOTAL_INT``，clock/reset 分别是 ``core_clk`` 和 ``rst_l``。
* 第 901~904 行：interface 的 timer/software/external/NMI 信号连续赋值到 DUT
  interrupt 输入。

接口关系：

* 被调用：testbench elaboration。
* 调用：SystemVerilog parameterized interface 实例化与 continuous assignment。
* 共享状态：``irq_intf``、``timer_int``、``soft_int``、``extintsrc_req``、
  ``nmi_int``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1121-L1123``）：

.. code-block:: systemverilog

   // Store IRQ interface
   uvm_config_db#(virtual eh2_irq_intf)::set(null, "*", "irq_vif", irq_intf);

逐段解释：

* 第 1123 行：testbench 用字段名 ``irq_vif`` 发布 virtual interface。driver 的
  connect phase 正是用这个字段名读取接口。

接口关系：

* 被调用：testbench initial 配置块。
* 调用：``uvm_config_db::set``。
* 共享状态：virtual ``eh2_irq_intf``。

§8  DUT probe 与 cosim 中断视图
-------------------------------

职责：IRQ agent 直接驱动 DUT interrupt pins；cosim 并不直接读取 driver item，而是通过
trace/probe 路径获取中断状态。testbench 把 IRQ 信号组合成 ``dut_probe_intf.mip``，
并把 NMI 同时映射到 ``nmi`` 和 ``nmi_int``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L838-L842``）：

.. code-block:: systemverilog

   // Construct MIP from external interrupt sources:
   //   bit 11 = MEIP (external), bit 7 = MTIP (timer), bit 3 = MSIP (software)
   assign dut_probe_intf.mip        = {20'b0, extintsrc_req[1], 3'b0, timer_int[0], 3'b0, soft_int[0], 3'b0};
   assign dut_probe_intf.nmi        = nmi_int;
   assign dut_probe_intf.nmi_int    = nmi_int;

逐段解释：

* 第 838~839 行：注释定义 ``mip`` 中 MEIP、MTIP 和 MSIP 的 bit 位置。
* 第 840 行：``dut_probe_intf.mip`` 由 ``extintsrc_req[1]``、``timer_int[0]`` 和
  ``soft_int[0]`` 拼接生成。
* 第 841~842 行：``nmi_int`` 同时驱动 probe 的 ``nmi`` 与 ``nmi_int`` 字段。

接口关系：

* 被调用：testbench continuous assignment。
* 调用：无函数调用。
* 共享状态：``dut_probe_intf``、``extintsrc_req``、``timer_int``、``soft_int``、
  ``nmi_int``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L886-L890``）：

.. code-block:: systemverilog

   assign dut_probe_intf.interrupt_valid = dut.veer.dec.tlu.tlumt[0].tlu.interrupt_valid;
   assign dut_probe_intf.take_ext_int    = dut.veer.dec.tlu.tlumt[0].tlu.take_ext_int;
   assign dut_probe_intf.take_timer_int  = dut.veer.dec.tlu.tlumt[0].tlu.take_timer_int;
   assign dut_probe_intf.take_soft_int   = dut.veer.dec.tlu.tlumt[0].tlu.take_soft_int;
   assign dut_probe_intf.take_nmi        = dut.veer.dec.tlu.tlumt[0].tlu.take_nmi;

逐段解释：

* 第 886 行：probe 暴露 RTL TLU 的 ``interrupt_valid``。
* 第 887~890 行：probe 暴露 external、timer、software 和 NMI 的 take 信号。
  这些字段供 trace/cosim 路径采样中断状态，而不是 IRQ driver 直接写入。

接口关系：

* 被调用：testbench continuous assignment。
* 调用：DUT hierarchy signal reference。
* 共享状态：``dut_probe_intf`` 与 RTL TLU interrupt/take 信号。

§9  Sequence item 字段
----------------------

职责：``eh2_irq_seq_item`` 把一次 interrupt 操作抽象成类型、external interrupt ID、
置位/清零值和持续时间。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv:L7-L21``）：

.. code-block:: systemverilog

   class eh2_irq_seq_item extends uvm_sequence_item;
   
     // Interrupt type
     typedef enum bit [2:0] {
       IRQ_TIMER    = 3'b000,
       IRQ_SOFTWARE = 3'b001,
       IRQ_EXTERNAL = 3'b010,
       IRQ_NMI      = 3'b011
     } irq_type_e;
   
     // Interrupt fields
     rand irq_type_e irq_type;
     rand bit [6:0]  irq_id;       // External interrupt ID (0-126)
     rand bit        irq_val;      // Interrupt value (1=set, 0=clear)
     rand bit [7:0]  duration;     // Duration in clock cycles (0=one-shot)

逐段解释：

* 第 10~15 行：``irq_type_e`` 包含 timer、software、external 和 NMI 四类。
* 第 18 行：``irq_type`` 决定 driver case 分支。
* 第 19 行：``irq_id`` 用于 external interrupt 的 ``extintsrc_req[irq_id]``。
* 第 20~21 行：``irq_val`` 决定置位/清零，``duration`` 决定自动撤销时序。

接口关系：

* 被调用：``eh2_irq_seq`` 或 virtual sequence 创建并提交该 item。
* 调用：无外部函数。
* 共享状态：``irq_type``、``irq_id``、``irq_val``、``duration``。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv:L34-L47``）：

.. code-block:: systemverilog

   // Constraint: valid interrupt ID
   constraint c_valid_id {
     irq_id inside {[0:126]};
   }
   
   // Constraint: reasonable duration
   constraint c_reasonable_duration {
     duration inside {[0:255]};
   }
   
   function string convert2string();
     return $sformatf("%s id=%0d val=%0b dur=%0d",
       irq_type.name(), irq_id, irq_val, duration);
   endfunction

逐段解释：

* 第 35~37 行：``irq_id`` 被约束在 0 到 126。
* 第 40~42 行：``duration`` 被约束在 0 到 255 个 clock cycle。
* 第 44~47 行：``convert2string`` 输出 interrupt 类型、ID、值和持续时间。

接口关系：

* 被调用：UVM randomize/print/log 路径。
* 调用：``irq_type.name`` 与 ``$sformatf``。
* 共享状态：transaction 字段。

§10  Driver 消费循环与四类驱动
------------------------------

职责：driver 在 connect phase 读取 ``irq_vif``，run phase 循环取 item 并调用
``drive_interrupt``。``drive_interrupt`` 按 ``irq_type`` 写不同 interface 信号。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L22-L37``）：

.. code-block:: systemverilog

   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
     if (!uvm_config_db#(virtual eh2_irq_intf)::get(this, "", "irq_vif", vif)) begin
       `uvm_fatal("irq_driver", "Could not get IRQ virtual interface")
     end
   endfunction
   
   task run_phase(uvm_phase phase);
     eh2_irq_seq_item txn;
   
     forever begin
       seq_item_port.get_next_item(txn);
       drive_interrupt(txn);
       seq_item_port.item_done();
     end
   endtask

逐段解释：

* 第 24~26 行：driver 通过字段名 ``irq_vif`` 读取 virtual interface；读取失败触发
  ``uvm_fatal``。
* 第 32~36 行：driver 永久循环，从 sequencer 取 item，驱动 interrupt，再调用
  ``item_done``。

接口关系：

* 被调用：active IRQ agent 的 driver phase。
* 调用：``uvm_config_db::get``、``seq_item_port.get_next_item``、
  ``drive_interrupt``、``seq_item_port.item_done``。
* 共享状态：``vif``、``seq_item_port``。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L42-L60``）：

.. code-block:: systemverilog

   task drive_interrupt(eh2_irq_seq_item txn);
     case (txn.irq_type)
       eh2_irq_seq_item::IRQ_TIMER: begin
         vif.timer_int <= txn.irq_val;
         if (txn.duration > 0) begin
           // Non-blocking: schedule de-assert in background
           fork
             begin
               bg_process = process::self();
               repeat (txn.duration) @(posedge vif.clk);
               vif.timer_int <= 1'b0;
             end
           join_none
         end else begin
           // Pulse: de-assert on next clock edge
           @(posedge vif.clk);
           vif.timer_int <= 1'b0;
         end
       end

逐段解释：

* 第 42~44 行：``IRQ_TIMER`` 分支写 ``vif.timer_int``。
* 第 46~54 行：``duration > 0`` 时 fork 一个后台线程，等待 ``duration`` 个 clock
  后清零 ``timer_int``，主线程不等待该 fork 完成。
* 第 55~59 行：``duration == 0`` 时等待下一个 clock edge 后清零，形成 one-shot pulse。

接口关系：

* 被调用：``run_phase``。
* 调用：SystemVerilog fork/join_none、``process::self``、clock wait。
* 共享状态：``vif.timer_int``、``bg_process``。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L62-L92``）：

.. code-block:: systemverilog

   eh2_irq_seq_item::IRQ_SOFTWARE: begin
     vif.soft_int <= txn.irq_val;
     if (txn.duration > 0) begin
       fork
         begin
           bg_process = process::self();
           repeat (txn.duration) @(posedge vif.clk);
           vif.soft_int <= 1'b0;
         end
       join_none
     end else begin
       @(posedge vif.clk);
       vif.soft_int <= 1'b0;
     end
   end
   
   eh2_irq_seq_item::IRQ_EXTERNAL: begin
     vif.extintsrc_req[txn.irq_id] <= txn.irq_val;
     if (txn.duration > 0) begin
       fork
         begin
           bg_process = process::self();
           repeat (txn.duration) @(posedge vif.clk);
           vif.extintsrc_req[txn.irq_id] <= 1'b0;
         end
       join_none

逐段解释：

* 第 62~75 行：``IRQ_SOFTWARE`` 写 ``soft_int``，持续时间逻辑与 timer 分支一致。
* 第 78~86 行：``IRQ_EXTERNAL`` 写 ``extintsrc_req[txn.irq_id]``，因此 ``irq_id`` 只在
  external 分支参与信号索引。
* 第 80~87 行：external interrupt 的持续时间也用后台线程自动撤销。
* 第 88~90 行在同一分支后续处理 ``duration == 0`` 的 one-shot 清零。

接口关系：

* 被调用：``drive_interrupt``。
* 调用：SystemVerilog fork/join_none、clock wait。
* 共享状态：``soft_int``、``extintsrc_req``、``irq_id``、``bg_process``。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L94-L109``）：

.. code-block:: systemverilog

   eh2_irq_seq_item::IRQ_NMI: begin
     vif.nmi_int <= txn.irq_val;
     if (txn.duration > 0) begin
       fork
         begin
           bg_process = process::self();
           repeat (txn.duration) @(posedge vif.clk);
           vif.nmi_int <= 1'b0;
         end
       join_none
     end else begin
       @(posedge vif.clk);
       vif.nmi_int <= 1'b0;
     end
   end
 endcase

逐段解释：

* 第 94~95 行：``IRQ_NMI`` 写 ``nmi_int``。
* 第 96~103 行：``duration > 0`` 时后台线程延迟清零 ``nmi_int``。
* 第 104~107 行：``duration == 0`` 时下一个 clock edge 清零。
* 第 109 行：结束 ``case``。

接口关系：

* 被调用：``drive_interrupt``。
* 调用：SystemVerilog fork/join_none、clock wait。
* 共享状态：``nmi_int``、``duration``、``bg_process``。

§11  Reset 清理
---------------

职责：driver 的 ``pre_reset_phase`` 负责杀掉后台撤销线程，并清空所有 interrupt
信号，避免 reset 后仍保留旧 stimulus。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L112-L124``）：

.. code-block:: systemverilog

   // Reset handling: kill background threads and clear all IRQ signals
   task pre_reset_phase(uvm_phase phase);
     if (bg_process != null) begin
       bg_process.kill();
       bg_process = null;
     end
     if (vif != null) begin
       vif.timer_int     <= '0;
       vif.soft_int      <= '0;
       vif.extintsrc_req <= '0;
       vif.nmi_int       <= 1'b0;
     end
   endtask

逐段解释：

* 第 113~117 行：如果存在后台 de-assert 线程，driver 调 ``kill`` 并清空
  ``bg_process`` 句柄。
* 第 118~123 行：若 ``vif`` 已获取，则把 timer、software、external 和 NMI 全部清零。

接口关系：

* 被调用：UVM reset phase。
* 调用：``process.kill``。
* 共享状态：``bg_process``、``vif`` 中所有 IRQ 信号。

§12  Helper sequence
--------------------

职责：``eh2_irq_seq`` 是薄封装 sequence。它若持有 ``txn``，就在 body 中
``start_item``/``finish_item``；静态 ``send_irq`` helper 创建 sequence 并在指定
sequencer 上启动。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv:L16-L28``）：

.. code-block:: systemverilog

   virtual task body();
     if (txn != null) begin
       start_item(txn);
       finish_item(txn);
     end
   endtask
   
   // Convenience: send an interrupt transaction
   static task send_irq(uvm_sequencer_base seqr, eh2_irq_seq_item irq_txn);
     eh2_irq_seq seq = new("irq_seq");
     seq.txn = irq_txn;
     seq.start(seqr);
   endtask

逐段解释：

* 第 17~20 行：只有 ``txn`` 非空时才发送 item。
* 第 24~28 行：``send_irq`` 接收任意 ``uvm_sequencer_base`` 和 IRQ item，创建
  ``eh2_irq_seq``，赋值 ``txn`` 后调用 ``start``。

接口关系：

* 被调用：tests 或 virtual sequences 的 IRQ helper 路径。
* 调用：``start_item``、``finish_item``、``seq.start``。
* 共享状态：``txn``。

§13  参考资料
-------------

* :ref:`appendix_b_uvm_irq_agent` — IRQ agent 逐类源码字典。
* :doc:`env` — env 中 active agent 与 virtual sequencer 的连接。
* :doc:`tb_top` — testbench 顶层 interface 分发和 DUT probe 连接。
* :ref:`cosim_scoreboard` — cosim 如何消费 interrupt/debug 状态。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent_pkg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_sequencer.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

§14  与 Ibex 工业实现对照
-------------------------

Ibex 也有独立 IRQ agent，路径为
``/home/host/ibex/dv/uvm/core_ibex/common/irq_agent``。两者都采用 active driver
驱动外部中断 stimulus，但 EH2 的中断表面更宽：除 timer/software/NMI 外，还要覆盖
``extintsrc_req[126:0]``、PIC claim/priority 状态、CE interrupt 和 TLU/PIC 之间的
EH2-specific 观察点。当前 EH2 IRQ agent 没有 monitor 成员，反馈主要来自 DUT probe、
trace item 和 cosim scoreboard。

.. list-table:: IRQ agent 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - agent 路径
     - ``common/irq_agent/irq_request_agent.sv``
     - ``common/irq_agent/eh2_irq_agent.sv``
   * - interface
     - ``irq_if``
     - ``eh2_irq_intf``
   * - 外部中断宽度
     - Ibex core interrupt set
     - EH2 PIC 127 路外部中断输入
   * - monitor
     - Ibex 有 IRQ monitor/seq item 组合
     - 当前 EH2 agent 仅 driver + sequencer，状态由 trace/probe 观察
   * - cosim
     - RVFI item 携带 irq 状态
     - trace item 通过 ``populate_cosim_state`` 携带 debug/NMI/MIP/mcycle

§15  Sign-off 关联
------------------

IRQ agent 影响 interrupt directed、riscv-dv interrupt generator 组合和 cosim interrupt
priority。2026-05-19 demo 中 directed 40/40、riscv-dv 370/395、formal 46/46 PASS。
若修改 ``eh2_irq_intf`` 字段、driver reset 清理或 virtual sequencer 句柄，应重点复跑
interrupt directed、nested interrupt riscv-dv 子集和 cosim exception/interrupt compare。

§16  中断优先级验证闭环
-----------------------

IRQ agent 只负责把 timer/software/external/NMI pin 驱动到 DUT。中断是否真正被接收、
优先级是否正确、trap entry 是否匹配 Spike，需要 trace/probe/cosim 三条路径共同闭环。

.. code-block:: text

   IRQ sequence
      |
      v
   eh2_irq_driver -> irq_intf -> DUT pins
                              |
                              +--> TLU/PIC take_* signals
                                      |
                                      v
                                 dut_probe_intf.mip/nmi/take_*
                                      |
                                      v
                                 trace item / cosim set_mip
                                      |
                                      v
                                 Spike trap/PC/mcause compare

.. list-table:: 中断闭环观察点
   :header-rows: 1
   :widths: 26 34 40

   * - 观察点
     - 来源
     - 验证意义
   * - ``timer_int`` / ``soft_int``
     - IRQ driver
     - local interrupt stimulus 是否发出
   * - ``extintsrc_req[id]``
     - IRQ driver
     - PIC 外部中断输入是否置位
   * - ``nmi_int``
     - IRQ driver
     - NMI pin 是否触发
   * - ``dut_probe_intf.mip``
     - TB top 拼接
     - Spike ``set_mip`` 的输入
   * - ``take_ext/timer/soft/nmi``
     - RTL TLU hierarchy
     - DUT 是否真正选择该中断
   * - ``mcause`` / ``mepc``
     - trace/cosim compare
     - architectural trap 结果是否匹配

§17  Duration 与后台撤销线程
----------------------------

IRQ driver 对 ``duration`` 的处理是非阻塞后台撤销。``duration > 0`` 时，driver fork
一个线程在指定 cycle 后清零 interrupt，主线程立即返回 sequencer；``duration == 0``
时，driver 等待一个 clock edge 后撤销，形成 one-shot pulse。

.. list-table:: Duration 行为
   :header-rows: 1
   :widths: 22 34 44

   * - ``duration``
     - 行为
     - 风险
   * - ``0``
     - 下一个 clock edge 清零
     - 若 DUT 采样条件较窄，可能只形成一拍刺激
   * - ``1..255``
     - 后台线程延迟清零
     - back-to-back item 可能与上一个后台撤销交叠
   * - reset 期间
     - ``pre_reset_phase`` kill 后台线程并清零
     - 若 reset phase 未触发，可能残留 interrupt

.. warning::

   当前 driver 只有一个 ``bg_process`` 句柄。若 sequence 快速发送多个 duration-based
   interrupt，后一个后台线程可能覆盖前一个句柄。复杂 nested interrupt 测试应谨慎
   设计 item 间隔，或后续把后台线程句柄扩展为 per-interrupt 队列。

§18  External interrupt ID 约定
-------------------------------

``eh2_irq_seq_item.irq_id`` 约束为 0 到 126，但 interface 的 ``extintsrc_req`` 声明为
``[PIC_TOTAL_INT:1]``。这意味着 external interrupt ID 的索引语义需要在 sequence 和
driver 中保持一致。文档维护时不要凭直觉把它改成 1-based 或 0-based；应以当前 driver
对 ``vif.extintsrc_req[txn.irq_id]`` 的实际索引为准，并通过 directed test 覆盖边界。

.. list-table:: External IRQ 边界检查
   :header-rows: 1
   :widths: 26 34 40

   * - 场景
     - 检查
     - 目的
   * - ``irq_id=0``
     - 波形中对应 bit 是否存在/有效
     - 捕获 interface range 与 constraint 不一致
   * - ``irq_id=1``
     - ``dut_probe_intf.mip`` 使用 ``extintsrc_req[1]``
     - 验证 MEIP 拼接路径
   * - ``irq_id=126``
     - 高位 external interrupt
     - 覆盖 PIC 宽度边界
   * - reset 后 external
     - ``extintsrc_req`` 是否清零
     - 防止旧 external interrupt 残留

§19  与 PIC coverage 的关系
---------------------------

IRQ agent 驱动 external interrupt pin，但 PIC 相关 coverage 还需要 RTL 内部 claim、
priority、level 和 gateway 状态。也就是说，看到 ``extintsrc_req`` 置位并不等价于
PIC coverage hole 已关闭。PIC directed 应同时检查 pin stimulus、PIC 内部状态、TLU
take signal 和 cosim trap compare。

.. list-table:: IRQ 到 PIC coverage 的路径
   :header-rows: 1
   :widths: 26 34 40

   * - 阶段
     - 观察
     - Coverage/compare 意义
   * - Pin stimulus
     - ``extintsrc_req[id]``
     - external interrupt 输入到达
   * - PIC arbitration
     - claim ID、priority level
     - PIC 优先级和屏蔽逻辑覆盖
   * - TLU take
     - ``take_ext_int``
     - core 选择 external interrupt
   * - Trap result
     - ``mcause`` / ``mepc``
     - Spike architectural compare
   * - Return path
     - ``mret``、mie/mip 恢复
     - interrupt return coverage

§20  调试命令与波形信号
-----------------------

IRQ 相关失败建议先跑 VCS directed，再用单测波形看 pin 和 TLU take 信号。

.. code-block:: bash

   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make smoke SIMULATOR=nc WAVES=1

推荐波形信号：

.. code-block:: text

   irq_intf.timer_int
   irq_intf.soft_int
   irq_intf.extintsrc_req
   irq_intf.nmi_int
   dut_probe_intf.mip
   dut_probe_intf.interrupt_valid
   dut_probe_intf.take_ext_int
   dut_probe_intf.take_timer_int
   dut_probe_intf.take_soft_int
   dut_probe_intf.take_nmi

§21  维护建议
-------------

后续增强 IRQ agent 时，优先考虑增加 monitor 和 analysis port，把 pin-level interrupt
事件发布成 transaction。这样 coverage、scoreboard debug 和 virtual sequence 自检可以
直接消费 IRQ event，而不必全部依赖 hierarchy probe。第二步再把后台撤销线程改成
per-source 管理，支持多个同时存在的 duration-based interrupt。第三步补充 external ID
边界 directed，明确 ``extintsrc_req`` 的索引约定。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
