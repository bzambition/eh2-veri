.. _appendix_b_uvm_irq_agent:
.. _appendix_b_uvm/irq_agent:

IRQ Agent 源码字典
==================

:status: draft
:source: dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/common/irq_agent/` 下的 IRQ UVM agent。当前源码实现的是
active interrupt stimulus 路径：sequence 产生 ``eh2_irq_seq_item``，driver 根据
``irq_type`` 驱动 ``timer_int``、``soft_int``、``extintsrc_req`` 或 ``nmi_int``。该目录
没有 monitor 源文件，top-level ``eh2_irq_agent`` 也没有 monitor 成员，因此本章不写
IRQ monitor 行为。

本章覆盖 7 个 agent 源文件，以及 env、tb、test 中的调用点：

* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_sequencer.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv`
* :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_test_lib.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_vseq.sv`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

IRQ agent 的主路径是 UVM sequencer 到 driver，再到 ``eh2_irq_intf``。tb 顶层实例化
``irq_intf``，把 interface 内部信号连续赋值到 DUT 输入，并把 ``irq_vif`` 放入
``uvm_config_db``。directed test 既可以通过 ``eh2_irq_seq::send_irq`` 走 agent
sequencer/driver，也可以通过 virtual sequence 直接取得 ``irq_vif`` 后写 interface。

::

   core_eh2_tb_top.sv
      |
      +-- eh2_irq_intf irq_intf
            |
            +-- uvm_config_db["irq_vif"]
                  |
                  +-- eh2_irq_driver <-- eh2_irq_sequencer <-- eh2_irq_seq::send_irq()
                  |
                  +-- core_eh2_vseq.get_irq_vif() --> irq_raise_* direct sequences

接口关系：

* 被调用：``core_eh2_env`` 创建 active ``irq_agent``，并把 ``irq_agent.sequencer`` 接到
  ``vseqr.irq_seqr``。
* 调用：driver 调 ``drive_interrupt``，``eh2_irq_seq::send_irq`` 调 ``seq.start``。
* 共享状态：virtual ``eh2_irq_intf``、``irq_vif`` config_db 条目、
  ``eh2_irq_seq_item.irq_type``、``irq_id``、``irq_val`` 和 ``duration``。

§2  ``eh2_irq_agent_pkg.sv`` — package 汇入顺序
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_agent_pkg`` 汇入 IRQ agent 的事务、driver、sequencer、sequence 和
top-level agent。

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

* 第 4 行：声明 ``eh2_irq_agent_pkg``，test package 和 env package 通过 import 使用其中类型。
* 第 6~7 行：引入 UVM 宏和 ``uvm_pkg``。
* 第 9 行：先 include ``eh2_irq_seq_item.sv``，因为 driver、sequencer 和 sequence 都依赖
  ``eh2_irq_seq_item``。
* 第 10~13 行：随后 include driver、sequencer、sequence 和 top-level agent。agent 内部声明
  driver/sequencer 类型，所以放在最后。
* 第 15 行：结束 package；该文件不保存运行期状态。

接口关系：

* 被调用：``core_eh2_env_pkg.sv``、``core_eh2_test_pkg.sv`` 和 test 文件 import 该 package。
* 调用：SystemVerilog include。
* 共享状态：无运行期共享状态。

§3  ``eh2_irq_intf.sv`` — interrupt interface
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_intf`` 定义 timer、software、external 和 NMI interrupt 信号，并提供 driver
与 monitor clocking block。

§3.1  参数、信号与默认值
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 7~13 行：interface 参数化 ``NUM_THREADS`` 和 ``PIC_TOTAL_INT``，端口只有 ``clk`` 与
  ``rst_n``。
* 第 15~19 行：信号包括按 thread 编址的 ``timer_int``、``soft_int``，按 PIC interrupt ID
  编址的 ``extintsrc_req[PIC_TOTAL_INT:1]``，以及单 bit ``nmi_int``。
* 第 21~27 行：initial block 把 4 类 interrupt 信号清零，给仿真初态提供明确默认值。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 以 ``RV_NUM_THREADS`` 和 ``RV_PIC_TOTAL_INT`` 实例化
  ``irq_intf``。
* 调用：无函数调用。
* 共享状态：这些信号由 driver 或 direct virtual sequence 写入，再由 tb 顶层连接到 DUT。

§3.2  clocking block 与 modport
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv:L29-L57``）：

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
     );

   endinterface

逐段解释：

* 第 29~35 行：``driver_cb`` 在 ``posedge clk`` 处定义 4 类 interrupt 信号的 output 方向。
* 第 37~43 行：``monitor_cb`` 在同一时钟边界观察 4 类 interrupt 信号。
* 第 45~49 行：``driver`` modport 暴露 ``clk``、``rst_n`` 和 ``driver_cb``。
* 第 51~55 行：``monitor`` modport 暴露 ``clk``、``rst_n`` 和 ``monitor_cb``。当前
  ``common/irq_agent`` 目录没有 monitor 类使用该 modport。
* 第 57 行：结束 interface。

接口关系：

* 被调用：driver 当前持有 ``virtual eh2_irq_intf``，没有使用显式 modport 类型。
* 调用：SystemVerilog clocking block 和 modport 机制。
* 共享状态：``clk`` 是 driver duration 计数和 direct sequence 间隔的共同时间基准。

§4  ``eh2_irq_seq_item.sv`` — interrupt transaction
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_seq_item`` 封装一笔 interrupt stimulus，包括类型、外部 interrupt ID、取值和持续周期。

§4.1  ``irq_type_e`` 与事务字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv:L7-L22``）：

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

* 第 7 行：该类继承 ``uvm_sequence_item``，可以通过 UVM sequence/driver 事务握手传递。
* 第 10~15 行：``irq_type_e`` 定义 4 种 interrupt 类型：timer、software、external 和
  NMI。
* 第 18 行：``irq_type`` 决定 driver 中 ``case (txn.irq_type)`` 的分支。
* 第 19 行：``irq_id`` 是 7-bit 外部 interrupt ID，注释写明范围 0~126；driver 对
  external interrupt 使用 ``extintsrc_req[txn.irq_id]``。
* 第 20 行：``irq_val`` 是写入目标 interrupt 信号的值。
* 第 21 行：``duration`` 是持续周期；注释写明 0 表示 one-shot。

接口关系：

* 被调用：``eh2_irq_driver``、``eh2_irq_seq`` 和多个 test class 创建或消费该对象。
* 调用：无。
* 共享状态：事务字段在 test/sequence 与 driver 之间传递。

§4.2  UVM field、约束与字符串化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv:L23-L49``）：

.. code-block:: systemverilog

     `uvm_object_utils_begin(eh2_irq_seq_item)
       `uvm_field_enum(irq_type_e, irq_type, UVM_ALL_ON)
       `uvm_field_int(irq_id, UVM_ALL_ON)
       `uvm_field_int(irq_val, UVM_ALL_ON)
       `uvm_field_int(duration, UVM_ALL_ON)
     `uvm_object_utils_end

     function new(string name = "eh2_irq_seq_item");
       super.new(name);
     endfunction

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

* 第 23~28 行：UVM object macro 注册 ``irq_type``、``irq_id``、``irq_val`` 和 ``duration``。
* 第 30~32 行：constructor 只调用父类 constructor，默认对象名是 ``eh2_irq_seq_item``。
* 第 34~37 行：``c_valid_id`` 把 ``irq_id`` 约束到 0~126。
* 第 39~42 行：``c_reasonable_duration`` 把 ``duration`` 约束到 0~255。
* 第 44~47 行：``convert2string`` 输出 interrupt 类型名、ID、值和持续周期。

接口关系：

* 被调用：UVM factory、sequence 和 test class。
* 调用：``irq_type.name()`` 和 ``$sformatf``。
* 共享状态：无全局状态。

§5  ``eh2_irq_driver.sv`` — interrupt 驱动器
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_driver`` 从 sequencer 接收 ``eh2_irq_seq_item``，按类型驱动 interrupt
信号，并在 duration 到期或 one-shot 下一个时钟后清除信号。

§5.1  connect phase 获取 ``irq_vif``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L8-L27``）：

.. code-block:: systemverilog

   class eh2_irq_driver extends uvm_driver #(eh2_irq_seq_item);

     `uvm_component_utils(eh2_irq_driver)

     // Virtual interface
     virtual eh2_irq_intf vif;

     // Process handle for background de-assert threads (killable on reset)
     process bg_process;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (!uvm_config_db#(virtual eh2_irq_intf)::get(this, "", "irq_vif", vif)) begin
         `uvm_fatal("irq_driver", "Could not get IRQ virtual interface")
       end
     endfunction

逐段解释：

* 第 8 行：driver 参数化为 ``uvm_driver #(eh2_irq_seq_item)``。
* 第 10 行：``uvm_component_utils`` 注册 driver 类型。
* 第 13 行：``vif`` 保存 virtual ``eh2_irq_intf``。
* 第 16 行：``bg_process`` 保存后台清除线程的 process handle，用于 reset phase kill。
* 第 18~20 行：constructor 只调用父类 constructor。
* 第 22~27 行：connect phase 从 config_db 获取 key ``irq_vif``；失败时用
  ``uvm_fatal`` 停止仿真。

接口关系：

* 被调用：``eh2_irq_agent.build_phase`` 在 active 模式创建 driver 后，UVM connect phase
  调用该函数。
* 调用：``uvm_config_db::get`` 和 ``uvm_fatal``。
* 共享状态：读取 config_db 中的 ``irq_vif``。

§5.2  run phase 事务循环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L29-L37``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       eh2_irq_seq_item txn;

       forever begin
         seq_item_port.get_next_item(txn);
         drive_interrupt(txn);
         seq_item_port.item_done();
       end
     endtask

逐段解释：

* 第 29~30 行：run phase 声明 ``eh2_irq_seq_item txn``。
* 第 32~33 行：forever 循环阻塞等待 sequencer 下发 item。
* 第 34 行：收到 item 后调用 ``drive_interrupt(txn)``，实际驱动逻辑集中在该 task。
* 第 35 行：驱动 task 返回后调用 ``seq_item_port.item_done()``，完成 UVM item 握手。
* 第 36~37 行：循环和 task 结束；driver 会继续等待下一笔 interrupt transaction。

接口关系：

* 被调用：UVM phase 调度。
* 调用：``seq_item_port.get_next_item``、``drive_interrupt``、``seq_item_port.item_done``。
* 共享状态：UVM sequencer/driver item 握手状态。

§5.3  ``IRQ_TIMER`` — timer interrupt
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 42~44 行：``drive_interrupt`` 按 ``txn.irq_type`` 分支，第一类是
  ``IRQ_TIMER``。
* 第 45 行：driver 把 ``txn.irq_val`` 写入 ``vif.timer_int``。该信号宽度由 interface
  的 ``NUM_THREADS`` 参数决定。
* 第 46~54 行：当 ``duration > 0`` 时，driver fork 一个后台线程，记录
  ``process::self()``，等待 ``duration`` 个 ``vif.clk`` 上升沿后清零 ``timer_int``；
  ``join_none`` 让 driver 不阻塞到清除完成。
* 第 55~59 行：当 ``duration == 0`` 时，driver 等待一个 ``vif.clk`` 上升沿后清零
  ``timer_int``，形成 one-shot pulse。
* 第 60 行：结束 ``IRQ_TIMER`` 分支。

接口关系：

* 被调用：``run_phase`` 调 ``drive_interrupt`` 后进入该分支。
* 调用：``process::self``、clock wait、fork/join_none。
* 共享状态：写 ``vif.timer_int`` 和 ``bg_process``。

§5.4  ``IRQ_SOFTWARE`` — software interrupt
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L62-L76``）：

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

逐段解释：

* 第 62 行：该分支匹配 ``IRQ_SOFTWARE``。
* 第 63 行：driver 把 ``txn.irq_val`` 写入 ``vif.soft_int``。
* 第 64~71 行：``duration > 0`` 时 fork 后台清除线程，等待指定周期后把 ``soft_int`` 清零。
* 第 72~75 行：``duration == 0`` 时等待一个时钟上升沿后把 ``soft_int`` 清零。
* 第 76 行：结束 software interrupt 分支。

接口关系：

* 被调用：``drive_interrupt`` 的 ``case``。
* 调用：``process::self``、clock wait、fork/join_none。
* 共享状态：写 ``vif.soft_int`` 和 ``bg_process``。

§5.5  ``IRQ_EXTERNAL`` — PIC external interrupt source
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L78-L92``）：

.. code-block:: systemverilog

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
           end else begin
             @(posedge vif.clk);
             vif.extintsrc_req[txn.irq_id] <= 1'b0;
           end
         end

逐段解释：

* 第 78 行：该分支匹配 ``IRQ_EXTERNAL``。
* 第 79 行：driver 以 ``txn.irq_id`` 作为 bit index，写 ``vif.extintsrc_req[txn.irq_id]``。
  源码没有在 driver 中额外检查 ``irq_id``，合法范围来自 seq item 约束和 test 赋值。
* 第 80~87 行：``duration > 0`` 时后台线程等待指定周期后清除同一个 interrupt bit。
* 第 88~91 行：``duration == 0`` 时等待一个时钟上升沿后清除同一个 interrupt bit。
* 第 92 行：结束 external interrupt 分支。

接口关系：

* 被调用：``drive_interrupt`` 的 ``case``。
* 调用：``process::self``、clock wait、fork/join_none。
* 共享状态：写 ``vif.extintsrc_req[txn.irq_id]`` 和 ``bg_process``。

§5.6  ``IRQ_NMI`` — NMI interrupt
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L94-L110``）：

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
     endtask

逐段解释：

* 第 94 行：该分支匹配 ``IRQ_NMI``。
* 第 95 行：driver 把 ``txn.irq_val`` 写入 ``vif.nmi_int``。
* 第 96~103 行：``duration > 0`` 时后台线程等待指定周期后清零 ``nmi_int``。
* 第 104~107 行：``duration == 0`` 时等待一个时钟上升沿后清零 ``nmi_int``。
* 第 109~110 行：结束 ``case`` 和 ``drive_interrupt`` task；源码没有 ``default`` 分支。

接口关系：

* 被调用：``drive_interrupt`` 的 ``case``。
* 调用：``process::self``、clock wait、fork/join_none。
* 共享状态：写 ``vif.nmi_int`` 和 ``bg_process``。

§5.7  ``pre_reset_phase()`` — reset 期间清理后台线程和信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L112-L126``）：

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

   endclass

逐段解释：

* 第 112~113 行：``pre_reset_phase`` 是 driver 的 reset 处理入口。
* 第 114~117 行：如果 ``bg_process`` 非空，driver 调 ``kill()`` 终止后台清除线程，然后把句柄置空。
* 第 118~123 行：如果 ``vif`` 非空，driver 清零 timer、software、external 和 NMI interrupt 信号。
* 第 124~126 行：结束 task 和 class。

接口关系：

* 被调用：UVM reset phase 调度。
* 调用：``process.kill``。
* 共享状态：``bg_process`` 和 ``vif`` 上的 interrupt 信号。

§6  ``eh2_irq_sequencer.sv`` — 类型化 sequencer
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_sequencer`` 是 ``eh2_irq_seq_item`` 的类型化 UVM sequencer，供
``eh2_irq_agent`` 和 env virtual sequencer 持有。

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_sequencer.sv:L4-L12``）：

.. code-block:: systemverilog

   class eh2_irq_sequencer extends uvm_sequencer #(eh2_irq_seq_item);

     `uvm_component_utils(eh2_irq_sequencer)

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

   endclass

逐段解释：

* 第 4 行：该类继承 ``uvm_sequencer #(eh2_irq_seq_item)``，事务类型与 driver 匹配。
* 第 6 行：注册 sequencer component 类型。
* 第 8~10 行：constructor 只调用父类 constructor。
* 第 12 行：结束 class；源码没有新增 field、phase 或 arbitration 逻辑。

接口关系：

* 被调用：``eh2_irq_agent.build_phase`` 创建 ``sequencer``。
* 调用：无。
* 共享状态：UVM sequencer 内部队列和 item 握手状态。

§7  ``eh2_irq_seq.sv`` — 单事务 sequence 包装
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_seq`` 是一个轻量 sequence：如果 ``txn`` 非空，就把该 transaction 发送给
sequencer；静态 ``send_irq`` 用于 test 侧快捷发送。

§7.1  ``body()`` — 发送 ``txn``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv:L6-L21``）：

.. code-block:: systemverilog

   class eh2_irq_seq extends uvm_sequence #(eh2_irq_seq_item);

     `uvm_object_utils(eh2_irq_seq)

     eh2_irq_seq_item txn;

     function new(string name = "eh2_irq_seq");
       super.new(name);
     endfunction

     virtual task body();
       if (txn != null) begin
         start_item(txn);
         finish_item(txn);
       end
     endtask

逐段解释：

* 第 6 行：sequence 参数化为 ``eh2_irq_seq_item``。
* 第 8 行：注册 sequence object 类型。
* 第 10 行：``txn`` 是由外部赋值的一笔 interrupt transaction。
* 第 12~14 行：constructor 默认名是 ``eh2_irq_seq``。
* 第 16~20 行：``body`` 只在 ``txn != null`` 时调用 ``start_item`` 和 ``finish_item``；
  如果 ``txn`` 为空，sequence 不发送任何 item。
* 第 21 行：结束 body task。

接口关系：

* 被调用：``seq.start(seqr)`` 调度 body。
* 调用：``start_item`` 和 ``finish_item``。
* 共享状态：``txn`` 字段。

§7.2  ``send_irq()`` — 静态快捷入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv:L23-L30``）：

.. code-block:: systemverilog

     // Convenience: send an interrupt transaction
     static task send_irq(uvm_sequencer_base seqr, eh2_irq_seq_item irq_txn);
       eh2_irq_seq seq = new("irq_seq");
       seq.txn = irq_txn;
       seq.start(seqr);
     endtask

   endclass

逐段解释：

* 第 23~24 行：``send_irq`` 是静态 task，参数是 sequencer base 句柄和要发送的
  ``eh2_irq_seq_item``。
* 第 25 行：task 创建一个临时 ``eh2_irq_seq``，对象名为 ``irq_seq``。
* 第 26 行：把调用者传入的 ``irq_txn`` 赋给 sequence 的 ``txn`` 字段。
* 第 27 行：在调用者指定的 ``seqr`` 上启动 sequence。
* 第 28~30 行：结束 task 和 class。

接口关系：

* 被调用：``core_eh2_test_lib.sv`` 中多个 IRQ test 直接调用。
* 调用：``new`` 和 ``seq.start``。
* 共享状态：调用者传入的 transaction 对象。

§8  ``eh2_irq_agent.sv`` — top-level agent
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_irq_agent`` 在 active 模式下创建 driver 和 sequencer，并连接二者的 item 通路。

§8.1  build phase 创建 active 组件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv:L7-L25``）：

.. code-block:: systemverilog

   class eh2_irq_agent extends uvm_agent;

     `uvm_component_utils(eh2_irq_agent)

     eh2_irq_driver    driver;
     eh2_irq_sequencer sequencer;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);

       if (get_is_active() == UVM_ACTIVE) begin
         driver    = eh2_irq_driver::type_id::create("driver", this);
         sequencer = eh2_irq_sequencer::type_id::create("sequencer", this);
       end
     endfunction

逐段解释：

* 第 7 行：top-level agent 继承 ``uvm_agent``。
* 第 9 行：注册 agent component 类型。
* 第 11~12 行：agent 只有 driver 和 sequencer 两个成员；没有 monitor 成员。
* 第 14~16 行：constructor 只调用父类 constructor。
* 第 18~25 行：build phase 只在 ``get_is_active() == UVM_ACTIVE`` 时创建 driver 和
  sequencer。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 创建 ``irq_agent``。
* 调用：UVM factory 和 ``get_is_active``。
* 共享状态：``is_active`` 配置决定 driver/sequencer 是否存在。

§8.2  connect phase 连接 sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv:L27-L35``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);

       if (get_is_active() == UVM_ACTIVE) begin
         driver.seq_item_port.connect(sequencer.seq_item_export);
       end
     endfunction

   endclass

逐段解释：

* 第 27~28 行：connect phase 先调用父类 connect phase。
* 第 30 行：连接逻辑受 active 模式保护。
* 第 31 行：driver 的 ``seq_item_port`` 连接到 sequencer 的 ``seq_item_export``。
* 第 33~35 行：结束 function 和 class。

接口关系：

* 被调用：UVM connect phase 调度。
* 调用：``driver.seq_item_port.connect``。
* 共享状态：sequencer/driver item 通路。

§9  Env、vseqr 与 tb 顶层连接
------------------------------------------------------------------------------------------------------------------------

职责：IRQ agent 在 env 中被设为 active，tb 顶层负责把 interface 连接到 DUT 并注入 config_db。

§9.1  env 创建 active ``irq_agent``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L87-L97``）：

.. code-block:: systemverilog

       // Interrupt agent (active)
       irq_agent = eh2_irq_agent::type_id::create("irq_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "irq_agent", "is_active", UVM_ACTIVE);

       // JTAG agent (active)
       jtag_agent = eh2_jtag_agent::type_id::create("jtag_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "jtag_agent", "is_active", UVM_ACTIVE);

       // Halt/Run agent (active)
       halt_run_agt = eh2_halt_run_agent::type_id::create("halt_run_agt", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "halt_run_agt", "is_active", UVM_ACTIVE);

逐段解释：

* 第 87~89 行：env 创建 ``irq_agent``，并对该实例设置 ``is_active=UVM_ACTIVE``。
* 第 91~97 行：jtag 和 halt/run agent 也以 active 模式创建；该片段显示 IRQ agent
  与其它主动 stimulus agent 处于同一 env build phase。

接口关系：

* 被调用：``core_eh2_env.build_phase``。
* 调用：UVM factory 和 ``uvm_config_db::set``。
* 共享状态：``irq_agent`` 实例和 ``is_active`` 配置。

§9.2  vseqr 保存 IRQ sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L15``）：

.. code-block:: systemverilog

   class core_eh2_vseqr extends uvm_sequencer;

     `uvm_component_utils(core_eh2_vseqr)

     // Sub-sequencers (use specific types for type-safe access)
     eh2_irq_sequencer              irq_seqr;
     eh2_jtag_sequencer             jtag_seqr;
     uvm_sequencer #(eh2_halt_run_seq_item) halt_run_seqr;

逐段解释：

* 第 7 行：``core_eh2_vseqr`` 是 env 的 virtual sequencer 类型。
* 第 9 行：注册 virtual sequencer。
* 第 11~15 行：``irq_seqr`` 是类型化 ``eh2_irq_sequencer``，与 IRQ agent 的 sequencer
  类型一致。

接口关系：

* 被调用：env 创建并填充 ``vseqr``。
* 调用：无。
* 共享状态：``irq_seqr`` 句柄。

§9.3  env connect phase 暴露 ``irq_seqr``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L173``）：

.. code-block:: systemverilog

       // Wire sub-sequencers to virtual sequencer
       vseqr.irq_seqr      = irq_agent.sequencer;
       vseqr.jtag_seqr     = jtag_agent.sequencer;
       vseqr.halt_run_seqr = halt_run_agt.sequencer;
     endfunction

逐段解释：

* 第 169 行：注释说明该段把 sub-sequencer 接到 virtual sequencer。
* 第 170 行：``irq_agent.sequencer`` 被赋给 ``vseqr.irq_seqr``。
* 第 171~172 行：jtag 与 halt/run sequencer 也在同一位置赋值。
* 第 173 行：结束 connect phase。

接口关系：

* 被调用：UVM connect phase 调度。
* 调用：无函数调用，只做句柄赋值。
* 共享状态：``vseqr.irq_seqr``。

§9.4  tb 顶层实例化并连接 ``irq_intf``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L892-L904``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
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

* 第 892~898 行：tb 顶层以 ``RV_NUM_THREADS`` 和 ``RV_PIC_TOTAL_INT`` 实例化
  ``eh2_irq_intf``，时钟接 ``core_clk``，复位接 ``rst_l``。
* 第 900~904 行：interface 中的 4 类 interrupt 信号通过连续赋值接到 tb/DUT 信号。
* 第 904 行：``nmi_int`` 也由 ``irq_intf.nmi_int`` 驱动；tb 顶层其它位置把 ``nmi_int``
  接入 DUT wrapper 和 DUT probe。

接口关系：

* 被调用：tb 顶层 elaboration。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``irq_intf`` 是 driver、direct sequence 和 DUT 之间的共享 interface。

§9.5  tb 顶层 DUT 与 cosim probe 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L172-L179``）：

.. code-block:: systemverilog

     eh2_veer_wrapper dut (
       .clk                    (core_clk),
       .rst_l                  (rst_l),
       .dbg_rst_l              (porst_l),
       .rst_vec                (reset_vector[31:1]),
       .nmi_int                (nmi_int),
       .nmi_vec                (nmi_vector[31:1]),
       .jtag_id                (jtag_id[31:1]),

逐段解释：

* 第 172 行：tb 顶层实例化 ``eh2_veer_wrapper``。
* 第 173~176 行：连接 core clock、reset 和 reset vector。
* 第 177 行：``nmi_int`` 接到 DUT wrapper 的 ``nmi_int`` 端口。
* 第 178~179 行：``nmi_vec`` 和 ``jtag_id`` 也在相邻端口处连接。

接口关系：

* 被调用：tb 顶层 elaboration。
* 调用：DUT wrapper 端口连接。
* 共享状态：``nmi_int`` 来自 ``irq_intf.nmi_int``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L837-L842``）：

.. code-block:: systemverilog

     // Interrupt/NMI/debug state for cosim notification
     // Construct MIP from external interrupt sources:
     //   bit 11 = MEIP (external), bit 7 = MTIP (timer), bit 3 = MSIP (software)
     assign dut_probe_intf.mip        = {20'b0, extintsrc_req[1], 3'b0, timer_int[0], 3'b0, soft_int[0], 3'b0};
     assign dut_probe_intf.nmi        = nmi_int;
     assign dut_probe_intf.nmi_int    = nmi_int;

逐段解释：

* 第 837~840 行：tb 顶层构造 DUT probe 的 ``mip`` 字段，其中 bit 11 来自
  ``extintsrc_req[1]``，bit 7 来自 ``timer_int[0]``，bit 3 来自 ``soft_int[0]``。
* 第 841~842 行：``nmi`` 和 ``nmi_int`` probe 字段都连接到 ``nmi_int``。

接口关系：

* 被调用：tb 顶层 continuous assignment。
* 调用：无。
* 共享状态：DUT probe 将 interrupt/NMI 状态提供给 trace/cosim 路径。

§9.6  config_db 注入 ``irq_vif``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1119-L1126``）：

.. code-block:: systemverilog

       // Provide DUT probe interface to cosim agent's scoreboard (for reset monitoring)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*cosim_agt*", "probe_vif", dut_probe_intf);

       // Store IRQ interface
       uvm_config_db#(virtual eh2_irq_intf)::set(null, "*", "irq_vif", irq_intf);

       // Store JTAG interface
       uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);

逐段解释：

* 第 1119~1120 行：tb 顶层把 DUT probe interface 注入给 cosim agent 的 scoreboard。
* 第 1122~1123 行：``irq_intf`` 以 key ``irq_vif`` 注入 config_db，instance pattern 是
  ``"*"``。
* 第 1125~1126 行：JTAG virtual interface 随后以 ``jtag_vif`` 注入。

接口关系：

* 被调用：tb 顶层 initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：config_db 中的 ``irq_vif``。

§10  Test 侧调用方式
------------------------------------------------------------------------------------------------------------------------

职责：test library 中的 IRQ tests 使用 ``eh2_irq_seq_item`` 和 ``eh2_irq_seq::send_irq`` 产生
interrupt；sequence library 中也有直接写 ``irq_vif`` 的后台序列。

§10.1  ``core_eh2_irq_test`` — 随机 external IRQ 后台刺激
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L503-L522``）：

.. code-block:: systemverilog

     // Override start_vseq: fork a background IRQ stimulus so the test
     // doesn't complete before interrupts are generated.
     virtual task start_vseq();
       fork
         begin
           eh2_irq_seq_item txn;
           #10000ns;  // Wait for reset
           forever begin
             #($urandom_range(500, 5000) * 10ns);
             txn = eh2_irq_seq_item::type_id::create("txn");
             txn.irq_type = eh2_irq_seq_item::IRQ_EXTERNAL;
             txn.irq_id = $urandom_range(1, 127);
             txn.irq_val = 1'b1;
             txn.duration = $urandom_range(10, 100);
             eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);
           end
         end
       join_none
       super.start_vseq();
     endtask

逐段解释：

* 第 503~505 行：该 test 覆盖 ``start_vseq``，注释说明 fork 后台 IRQ stimulus。
* 第 506~510 行：fork 的线程声明 ``txn``，先等待 ``#10000ns``。
* 第 511~517 行：forever 中按随机间隔创建 external IRQ transaction，``irq_id`` 在
  1~127 之间随机，``duration`` 在 10~100 之间随机。
* 第 517 行：调用 ``eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn)``，走 agent
  sequencer/driver 路径。
* 第 520~521 行：后台线程 ``join_none`` 后调用父类 ``start_vseq``。

接口关系：

* 被调用：test run flow 调 ``start_vseq``。
* 调用：``eh2_irq_seq::send_irq``、UVM factory、``$urandom_range``。
* 共享状态：``env.irq_agent.sequencer`` 和 transaction 对象。

§10.2  Timer 与 software IRQ tests
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L663-L674``）：

.. code-block:: systemverilog

     virtual task run_timer_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       forever begin
         #($urandom_range(1000, 5000) * 10ns);
         txn = eh2_irq_seq_item::type_id::create("txn");
         txn.irq_type = eh2_irq_seq_item::IRQ_TIMER;
         txn.irq_val = 1'b1;
         txn.duration = $urandom_range(5, 20);
         eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);
       end
     endtask

逐段解释：

* 第 663~665 行：timer stimulus task 声明 transaction 并等待 ``#10000ns``。
* 第 666~671 行：forever 循环按随机间隔创建 timer IRQ transaction，``irq_val`` 固定为
  1，``duration`` 在 5~20 之间随机。
* 第 672 行：通过 ``env.irq_agent.sequencer`` 发送到 IRQ driver。
* 第 674 行：结束 task。

接口关系：

* 被调用：``core_eh2_timer_irq_test.run_phase`` fork 该 task。
* 调用：``eh2_irq_seq::send_irq``、UVM factory、``$urandom_range``。
* 共享状态：``env.irq_agent.sequencer``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L702-L713``）：

.. code-block:: systemverilog

     virtual task run_soft_irq_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       forever begin
         #($urandom_range(500, 3000) * 10ns);
         txn = eh2_irq_seq_item::type_id::create("txn");
         txn.irq_type = eh2_irq_seq_item::IRQ_SOFTWARE;
         txn.irq_val = 1'b1;
         txn.duration = $urandom_range(5, 30);
         eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);
       end
     endtask

逐段解释：

* 第 702~704 行：software IRQ stimulus task 声明 transaction 并等待 ``#10000ns``。
* 第 705~710 行：forever 中创建 ``IRQ_SOFTWARE`` transaction，持续周期在 5~30 之间随机。
* 第 711 行：调用 ``eh2_irq_seq::send_irq`` 把 transaction 送到 IRQ agent sequencer。
* 第 713 行：结束 task。

接口关系：

* 被调用：``core_eh2_soft_irq_test.run_phase`` fork 该 task。
* 调用：``eh2_irq_seq::send_irq``、UVM factory、``$urandom_range``。
* 共享状态：``env.irq_agent.sequencer``。

§10.3  Nested/debug IRQ tests
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1593-L1611``）：

.. code-block:: systemverilog

     virtual task run_nested_irq_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       forever begin
         #($urandom_range(1000, 5000) * 10ns);
         // Send multiple rapid interrupts to trigger nesting
         for (int i = 0; i < $urandom_range(2, 5); i++) begin
           txn = eh2_irq_seq_item::type_id::create($sformatf("txn_%0d", i));
           txn.irq_type = eh2_irq_seq_item::IRQ_EXTERNAL;
           txn.irq_id = $urandom_range(1, 127);
           txn.irq_val = 1'b1;
           txn.duration = $urandom_range(5, 20);
           fork
             eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);
           join_none
         end
         #1000ns;

逐段解释：

* 第 1593~1595 行：nested IRQ stimulus task 声明 transaction 并等待 ``#10000ns``。
* 第 1596~1599 行：forever 中先等待随机时间，然后用 for loop 产生 2~5 个快速 external
  interrupts。
* 第 1600~1604 行：每个 transaction 使用不同对象名，设置 external IRQ、随机 ID、置位值和
  5~20 周期 duration。
* 第 1605~1607 行：每笔 transaction 通过 fork/join_none 调 ``send_irq``，使多笔发送可以重叠。
* 第 1609~1611 行：一组 nested stimulus 后等待 ``#1000ns`` 并结束 task 片段。

接口关系：

* 被调用：``core_eh2_irq_nest_test.run_phase`` fork 该 task。
* 调用：``eh2_irq_seq::send_irq``、UVM factory、``$urandom_range``、``$sformatf``。
* 共享状态：``env.irq_agent.sequencer``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1646-L1658``）：

.. code-block:: systemverilog

     virtual task run_irq_in_debug_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       forever begin
         #($urandom_range(2000, 8000) * 10ns);
         // Enter debug mode first, then fire interrupt
         txn = eh2_irq_seq_item::type_id::create("dbg_irq_txn");
         txn.irq_type = eh2_irq_seq_item::IRQ_EXTERNAL;
         txn.irq_id = $urandom_range(1, 127);
         txn.irq_val = 1'b1;
         txn.duration = $urandom_range(10, 50);
         eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);
       end
     endtask

逐段解释：

* 第 1646~1648 行：debug 场景 stimulus task 声明 transaction 并等待 ``#10000ns``。
* 第 1649~1656 行：forever 中按 2000~8000 个 10 ns 的随机间隔创建 external IRQ
  transaction，duration 在 10~50 之间随机。
* 第 1657 行：调用 ``send_irq`` 走 IRQ agent sequencer。
* 第 1658 行：结束 forever 中的发送片段。

接口关系：

* 被调用：``core_eh2_irq_in_debug_test.run_phase`` fork 该 task。
* 调用：``eh2_irq_seq::send_irq``、UVM factory、``$urandom_range``。
* 共享状态：``env.irq_agent.sequencer``。

§10.4  Direct ``irq_vif`` sequences
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L66-L95``）：

.. code-block:: systemverilog

   class irq_raise_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_raise_seq)

     // Virtual interface to drive interrupts
     virtual eh2_irq_intf irq_vif;

     int unsigned max_irq_id = 127;  // Max external interrupt ID
     int unsigned num_irqs = 3;      // Number of interrupts to raise per event

     function new(string name = "irq_raise_seq");
       super.new(name);
     endfunction

     virtual task body();
       int id;
       rand_delay();
       forever begin
         if (stopped) return;
         // Raise multiple random interrupts
         repeat (num_irqs) begin
           id = $urandom_range(1, max_irq_id);
           irq_vif.extintsrc_req[id] <= 1'b1;
         end
         rand_interval();
         // Drop all

逐段解释：

* 第 66~74 行：``irq_raise_seq`` 直接持有 virtual ``eh2_irq_intf``，并配置最大 external
  IRQ ID 与每次置位数量。
* 第 76~78 行：constructor 只调用父类 constructor。
* 第 80~84 行：body 先调用 ``rand_delay``，然后进入可由 ``stopped`` 退出的 forever 循环。
* 第 85~89 行：重复 ``num_irqs`` 次随机选择 ID，并直接写
  ``irq_vif.extintsrc_req[id] <= 1'b1``。
* 第 90 行：调用 ``rand_interval``，为后续 drop all 留出时间间隔。

接口关系：

* 被调用：``core_eh2_vseq.start_irq_raise_seq`` 创建并启动该 sequence。
* 调用：``rand_delay``、``rand_interval`` 和 ``$urandom_range``。
* 共享状态：直接写 ``irq_vif.extintsrc_req``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L102-L125``）：

.. code-block:: systemverilog

   class irq_raise_single_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_raise_single_seq)

     virtual eh2_irq_intf irq_vif;

     int unsigned max_irq_id = 127;

     function new(string name = "irq_raise_single_seq");
       super.new(name);
     endfunction

     virtual task body();
       int id;
       rand_delay();
       forever begin
         if (stopped) return;
         id = $urandom_range(1, max_irq_id);
         irq_vif.extintsrc_req[id] <= 1'b1;
         rand_interval();
         irq_vif.extintsrc_req[id] <= 1'b0;
         rand_interval();

逐段解释：

* 第 102~108 行：``irq_raise_single_seq`` 也直接持有 ``irq_vif``，最大 ID 默认为 127。
* 第 110~112 行：constructor 只调用父类 constructor。
* 第 114~120 行：body 先随机延迟，再在 forever 中选择一个随机 external IRQ ID 并置 1。
* 第 121~123 行：等待随机间隔后清除同一个 bit，再等待下一轮随机间隔。

接口关系：

* 被调用：``core_eh2_vseq.start_irq_raise_single_seq`` 创建并启动该 sequence。
* 调用：``rand_delay``、``rand_interval`` 和 ``$urandom_range``。
* 共享状态：直接写 ``irq_vif.extintsrc_req``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L132-L179``）：

.. code-block:: systemverilog

   class irq_raise_nmi_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_raise_nmi_seq)

     virtual eh2_irq_intf irq_vif;

     function new(string name = "irq_raise_nmi_seq");
       super.new(name);
     endfunction

     virtual task body();
       rand_delay();
       forever begin
         if (stopped) return;
         irq_vif.nmi_int <= 1'b1;
         rand_interval();
         irq_vif.nmi_int <= 1'b0;
         rand_interval();
       end
     endtask

逐段解释：

* 第 132~136 行：``irq_raise_nmi_seq`` 直接持有 ``irq_vif``，用于写 NMI。
* 第 138~140 行：constructor 只调用父类 constructor。
* 第 142~150 行：body 随机延迟后进入 forever；每轮置位 ``irq_vif.nmi_int``，等待随机间隔，
  再清零并等待下一轮。

接口关系：

* 被调用：``core_eh2_vseq.start_nmi_raise_seq`` 创建并启动该 sequence。
* 调用：``rand_delay`` 和 ``rand_interval``。
* 共享状态：直接写 ``irq_vif.nmi_int``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L158-L179``）：

.. code-block:: systemverilog

   class irq_drop_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_drop_seq)

     virtual eh2_irq_intf irq_vif;

     function new(string name = "irq_drop_seq");
       super.new(name);
     endfunction

     virtual task body();
       rand_delay();
       forever begin
         if (stopped) return;
         // Drop all interrupts
         irq_vif.extintsrc_req <= '0;
         irq_vif.timer_int <= '0;
         irq_vif.soft_int <= '0;
         irq_vif.nmi_int <= 1'b0;
         rand_interval();
       end
     endtask

逐段解释：

* 第 158~162 行：``irq_drop_seq`` 直接持有 ``irq_vif``。
* 第 164~166 行：constructor 只调用父类 constructor。
* 第 168~177 行：body 在每轮循环中清零 external、timer、software 和 NMI interrupt 信号，
  然后等待随机间隔。
* 第 179 行：结束 task；该 sequence 通过 ``stopped`` 退出。

接口关系：

* 被调用：``core_eh2_vseq.start_irq_drop_seq`` 创建并启动该 sequence。
* 调用：``rand_delay`` 和 ``rand_interval``。
* 共享状态：直接写 ``irq_vif`` 的 4 类 interrupt 信号。

§10.5  virtual sequence 获取 ``irq_vif``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L130-L162``）：

.. code-block:: systemverilog

     // Helper: get IRQ virtual interface from config_db
     function virtual eh2_irq_intf get_irq_vif();
       virtual eh2_irq_intf vif;
       if (!uvm_config_db#(virtual eh2_irq_intf)::get(null, "*", "irq_vif", vif)) begin
         `uvm_warning("vseq", "Could not get IRQ virtual interface")
       end
       return vif;
     endfunction

     // Helper tasks for directed stimulus (called from tests)
     virtual task start_irq_raise_single_seq();
       irq_single_h = irq_raise_single_seq::type_id::create("irq_single_h");
       irq_single_h.irq_vif = get_irq_vif();
       irq_single_h.start(null);
     endtask

     virtual task start_irq_raise_seq();
       irq_multi_h = irq_raise_seq::type_id::create("irq_multi_h");
       irq_multi_h.irq_vif = get_irq_vif();
       irq_multi_h.start(null);
     endtask

     virtual task start_nmi_raise_seq();
       irq_nmi_h = irq_raise_nmi_seq::type_id::create("irq_nmi_h");
       irq_nmi_h.irq_vif = get_irq_vif();
       irq_nmi_h.start(null);

逐段解释：

* 第 130~137 行：``get_irq_vif`` 从 config_db 读取 ``irq_vif``；失败时打印 warning 并返回
  当前 ``vif`` 值。
* 第 140~144 行：``start_irq_raise_single_seq`` 创建 single IRQ sequence，把
  ``irq_vif`` 字段设置为 ``get_irq_vif()``，并以 ``start(null)`` 启动。
* 第 146~150 行：``start_irq_raise_seq`` 对多 IRQ sequence 执行相同流程。
* 第 152~156 行：``start_nmi_raise_seq`` 对 NMI sequence 执行相同流程。
* 第 158~162 行：``start_irq_drop_seq`` 的片段在源码紧随其后，同样获取 ``irq_vif`` 并启动
  direct drop sequence。

接口关系：

* 被调用：directed tests 调 virtual sequence helper task。
* 调用：``uvm_config_db::get``、UVM factory ``type_id::create`` 和 ``start(null)``。
* 共享状态：config_db 中的 ``irq_vif``，以及 direct sequence 的 ``irq_vif`` 字段。

§11  运行时行为边界
------------------------------------------------------------------------------------------------------------------------

职责：本节列出源码中明确存在的 IRQ agent 边界，防止把其它中断验证能力误归因到该 agent。

§11.1  没有 IRQ monitor component
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``dv/uvm/core_eh2/common/irq_agent/`` 目录只有 package、interface、seq item、driver、
sequencer、sequence 和 agent 7 个文件。``eh2_irq_agent.sv`` 第 11~12 行只声明
``driver`` 与 ``sequencer``，build phase 也只创建这两个 component。因此当前源码没有
``eh2_irq_monitor``，也没有 analysis port 或响应时间统计逻辑。

接口关系：

* 被调用：agent build/connect phase。
* 调用：无 monitor 调用。
* 共享状态：IRQ 状态可被 DUT probe 和 direct sequence 观察/驱动，但不是 IRQ agent monitor 发布。

§11.2  Driver 与 direct sequence 是两种写接口方式
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``eh2_irq_driver`` 写 interface 的路径是 ``eh2_irq_seq_item`` -> ``eh2_irq_seq`` ->
``eh2_irq_sequencer`` -> ``eh2_irq_driver.drive_interrupt``。``core_eh2_seq_lib.sv`` 中的
``irq_raise_seq``、``irq_raise_single_seq``、``irq_raise_nmi_seq`` 和 ``irq_drop_seq``
则直接持有 ``irq_vif`` 并写 interface。源码没有在这两条路径之间提供仲裁器；因此本章只说明
两者都能写 ``irq_intf``，不推断同时运行时的仲裁策略。

接口关系：

* 被调用：test class 或 virtual sequence helper。
* 调用：driver 路径调用 ``send_irq``；direct 路径调用 ``get_irq_vif`` 和 ``start(null)``。
* 共享状态：``irq_intf`` 的 interrupt 信号。

§12  参考资料
------------------------------------------------------------------------------------------------------------------------

* :ref:`agent_irq` — verification architecture 中的 IRQ agent 说明。
* :ref:`appendix_b_uvm_halt_run_agent` — active agent 与 tb virtual interface 连接的相邻例子。
* :doc:`../05_verification_arch/cosim_scoreboard` — DUT probe 中断状态进入 cosim 的背景。
* :ref:`adr-0007` — interrupt cosim 决策背景。
* :ref:`adr-0001` — cosim via trace and probe。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent_pkg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_sequencer.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_vseq.sv``。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从真实 UVM 源码中找出本页组件所属 class、interface 或 covergroup。

.. code-block:: bash

   rg -n "class .*extends|uvm_component_utils|uvm_object_utils|phase" dv/uvm/core_eh2 | head -60
   rg -n "interface|analysis_port|scoreboard|covergroup" dv/uvm/core_eh2 | head -60

**进阶题**：检查本页是否把 EH2 和 Ibex 的一致点、差异点分开描述。

.. code-block:: bash

   rg -n "core_ibex|Ibex|与 Ibex" docs/sphinx_cn/source/05_verification_arch docs/sphinx_cn/source/appendix_b_uvm | head -80

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
