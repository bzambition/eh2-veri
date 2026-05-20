.. _appendix_b_uvm_halt_run_agent:
.. _appendix_b_uvm/halt_run_agent:

Halt/Run Agent 源码字典
=======================

:status: draft
:source: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/common/halt_run_agent/` 下的 Halt/Run UVM agent。
该 agent 通过 ``eh2_halt_run_intf`` 驱动 ``mpc_debug_halt_req``、
``mpc_debug_run_req``、``mpc_reset_run_req``、``i_cpu_halt_req`` 和
``i_cpu_run_req``，并读取 ``o_cpu_halt_ack``、``o_cpu_run_ack``、
``o_cpu_halt_status`` 与 ``o_debug_mode_status``。当前 env 将该 agent 配置为
``UVM_ACTIVE``，并把它的 sequencer 暴露给 virtual sequencer。

本章覆盖 6 个 agent 源文件，以及 env、tb 和 base test 中与 Halt/Run 相关的连接点：

* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_base_test.sv`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Halt/Run 路径由 tb 顶层创建 virtual interface，并通过 ``uvm_config_db`` 分发给
driver、monitor 和 base test。driver 从 sequencer 接收 ``eh2_halt_run_seq_item``，
按 ``action`` 枚举选择请求信号；monitor 每个 ``core_clk`` 周期读取 ack/status
并打印 UVM log。源码中 monitor 创建了 ``item_port``，但当前 ``run_phase`` 没有
调用 ``item_port.write``，因此本章不把它描述为事务发布路径。

::

   core_eh2_tb_top.sv
      |
      +-- eh2_halt_run_intf halt_run_vif
            |
            +-- uvm_config_db["halt_run_vif"]
                  |
                  +-- eh2_halt_run_driver  <-- sequencer <-- core_eh2_vseqr.halt_run_seqr
                  |
                  +-- eh2_halt_run_monitor --> UVM log
                  |
                  +-- core_eh2_base_test helper tasks

接口关系：

* 被调用：``core_eh2_env`` 在 build phase 创建 ``halt_run_agt``，并在 connect phase
  把 ``halt_run_agt.sequencer`` 赋给 ``vseqr.halt_run_seqr``。
* 调用：driver 读取 ``seq_item_port``，驱动 ``eh2_halt_run_intf.driver_cb``，并轮询
  ``o_cpu_halt_ack`` 或 ``o_cpu_run_ack``。
* 共享状态：virtual ``eh2_halt_run_intf``、``halt_run_vif`` config_db 条目、
  ``eh2_halt_run_seq_item.action`` 和 ``delay``。

§2  ``eh2_halt_run_agent_pkg.sv`` — package 汇入顺序
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_halt_run_agent_pkg`` 定义 Halt/Run agent 的编译单元，并按依赖关系 include
事务、driver、monitor 和 top-level agent。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv:L4-L14``）：

.. code-block:: systemverilog

   package eh2_halt_run_agent_pkg;

     `include "uvm_macros.svh"
     import uvm_pkg::*;

     `include "eh2_halt_run_seq_item.sv"
     `include "eh2_halt_run_driver.sv"
     `include "eh2_halt_run_monitor.sv"
     `include "eh2_halt_run_agent.sv"

   endpackage

逐段解释：

* 第 4 行：声明 ``eh2_halt_run_agent_pkg``，后续 env 和 test package 通过该 package
  访问 agent 类型。
* 第 6~7 行：引入 UVM 宏和 ``uvm_pkg``，为 ``uvm_component_utils``、
  ``uvm_object_utils_begin``、``uvm_driver`` 和 ``uvm_monitor`` 等类型提供定义。
* 第 9 行：先 include ``eh2_halt_run_seq_item.sv``，因为 driver、monitor 的类型声明
  都引用 ``eh2_halt_run_seq_item``。
* 第 10~12 行：include driver、monitor 和 top-level agent。``eh2_halt_run_agent.sv``
  内部声明 driver、monitor、sequencer 成员，所以它被放在最后。
* 第 14 行：结束 package；该文件没有运行期逻辑，也不持有全局配置。

接口关系：

* 被调用：``core_eh2_env_pkg.sv`` 和 ``core_eh2_test_pkg.sv`` import 该 package。
* 调用：SystemVerilog include 机制。
* 共享状态：无运行期共享状态。

§3  ``eh2_halt_run_intf.sv`` — 信号边界
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_halt_run_intf`` 是 tb 与 DUT Halt/Run 信号之间的边界，定义请求信号、ack/status
信号、clocking block 和 modport。

§3.1  接口端口与请求默认值
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L7-L22``）：

.. code-block:: systemverilog

   interface eh2_halt_run_intf (
     input logic clk,
     input logic rst_n
   );

     // MPC debug halt/run requests (active high)
     logic mpc_debug_halt_req = 1'b0;
     logic mpc_debug_run_req  = 1'b1;
     logic mpc_reset_run_req  = 1'b1;

     // CPU halt/run requests (active high)
     // Note: i_cpu_run_req=0 matches reference testbench (no active run request,
     // let core run based on mpc_reset_run_req)
     logic i_cpu_halt_req = 1'b0;
     logic i_cpu_run_req  = 1'b0;

逐段解释：

* 第 7~10 行：接口只接收 ``clk`` 和 ``rst_n``，没有在接口内部生成时钟或复位。
* 第 12~15 行：MPC debug 请求信号在声明处给出初值；``mpc_debug_halt_req`` 为 0，
  ``mpc_debug_run_req`` 和 ``mpc_reset_run_req`` 为 1。
* 第 17~21 行：CPU 请求信号同样给出初值；``i_cpu_halt_req`` 为 0，
  ``i_cpu_run_req`` 为 0。注释明确说明该默认值匹配 reference testbench，并让 core
  基于 ``mpc_reset_run_req`` 运行。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 实例化 ``halt_run_vif`` 并把这些信号 assign 到 DUT
  侧 wire。
* 调用：无子函数调用。
* 共享状态：请求信号由 driver、base test helper 或接口默认值驱动，并被 tb 顶层连接到 DUT。

§3.2  ack/status 与 clocking block
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L23-L49``）：

.. code-block:: systemverilog

     // Acknowledgment signals (active high)
     logic o_cpu_halt_ack;
     logic o_cpu_run_ack;
     logic o_cpu_halt_status;
     logic o_debug_mode_status;

     // Driver clocking block
     clocking driver_cb @(posedge clk);
       output mpc_debug_halt_req;
       output mpc_debug_run_req;
       output mpc_reset_run_req;
       output i_cpu_halt_req;
       output i_cpu_run_req;
     endclocking

     // Monitor clocking block
     clocking monitor_cb @(posedge clk);
       input mpc_debug_halt_req;
       input mpc_debug_run_req;
       input mpc_reset_run_req;
       input i_cpu_halt_req;
       input i_cpu_run_req;
       input o_cpu_halt_ack;
       input o_cpu_run_ack;
       input o_cpu_halt_status;
       input o_debug_mode_status;
     endclocking

逐段解释：

* 第 23~27 行：ack/status 信号在接口中声明为普通 ``logic``，由 tb 顶层把 DUT 输出反馈到
  ``halt_run_vif``。
* 第 29~36 行：``driver_cb`` 以 ``posedge clk`` 为采样/驱动边界，只声明请求信号为
  output；driver 使用该 clocking block 写请求。
* 第 38~49 行：``monitor_cb`` 以同一 ``posedge clk`` 为观察边界，把请求信号和 ack/status
  都声明为 input；monitor 通过该 clocking block 读取状态。

接口关系：

* 被调用：driver 使用 ``vif.driver_cb``；monitor 使用 ``vif.monitor_cb``。
* 调用：SystemVerilog clocking block 机制。
* 共享状态：``clk`` 是 driver 与 monitor 的共同时间基准。

§3.3  modport 暴露方向
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L51-L56``）：

.. code-block:: systemverilog

     // Modports
     modport driver  (clocking driver_cb, input clk, rst_n,
                      input o_cpu_halt_ack, o_cpu_run_ack, o_cpu_halt_status, o_debug_mode_status);
     modport monitor (clocking monitor_cb, input clk, rst_n);

   endinterface

逐段解释：

* 第 51~53 行：``driver`` modport 暴露 ``driver_cb``，并允许直接读取 ``clk``、``rst_n``
  以及 4 个 ack/status 信号。源码中的 driver 实际直接轮询 ``vif.o_cpu_halt_ack`` 和
  ``vif.o_cpu_run_ack``。
* 第 54 行：``monitor`` modport 暴露 ``monitor_cb``，并提供 ``clk``、``rst_n`` 输入。
* 第 56 行：结束接口；该文件没有 task 或 function。

接口关系：

* 被调用：当前 driver、monitor 成员类型是 ``virtual eh2_halt_run_intf``，不是显式
  ``virtual eh2_halt_run_intf.driver`` 或 ``monitor``，但 modport 定义了接口方向约束。
* 调用：无。
* 共享状态：modport 不新增状态，只限制 interface 视图。

§4  ``eh2_halt_run_seq_item.sv`` — transaction 对象
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_halt_run_seq_item`` 表达一次 Halt/Run 操作，包括动作类型和动作前延迟。

§4.1  ``action_e`` — 四类动作
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv:L4-L15``）：

.. code-block:: systemverilog

   class eh2_halt_run_seq_item extends uvm_sequence_item;

     // Action type
     typedef enum bit [1:0] {
       HALT_CORE    = 2'b00,
       RUN_CORE     = 2'b01,
       RESET_RUN    = 2'b10,
       CPU_HALT     = 2'b11
     } action_e;

     rand action_e action;
     rand int unsigned delay;  // Delay before applying (clock cycles)

逐段解释：

* 第 4 行：该类继承 ``uvm_sequence_item``，因此可以通过 UVM sequencer/driver 事务路径传递。
* 第 7~12 行：``action_e`` 是 2-bit 枚举，列出 ``HALT_CORE``、``RUN_CORE``、
  ``RESET_RUN`` 和 ``CPU_HALT`` 四类动作。
* 第 14 行：``action`` 是随机化字段，driver 的 ``case (item.action)`` 使用它选择实际驱动逻辑。
* 第 15 行：``delay`` 是随机化字段，单位在注释中标为 clock cycles；driver 在执行动作前按它
  repeat ``@(posedge vif.clk)``。

接口关系：

* 被调用：``eh2_halt_run_driver`` 通过 ``seq_item_port.get_next_item(item)`` 接收该类型。
* 调用：无。
* 共享状态：``action`` 和 ``delay`` 是 sequencer 与 driver 之间的事务字段。

§4.2  延迟约束、factory 注册与字符串化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv:L17-L34``）：

.. code-block:: systemverilog

     constraint c_reasonable_delay {
       delay inside {[0:100]};
     }

     `uvm_object_utils_begin(eh2_halt_run_seq_item)
       `uvm_field_enum(action_e, action, UVM_ALL_ON)
       `uvm_field_int(delay, UVM_ALL_ON)
     `uvm_object_utils_end

     function new(string name = "eh2_halt_run_seq_item");
       super.new(name);
     endfunction

     function string convert2string();
       return $sformatf("action=%s delay=%0d", action.name(), delay);
     endfunction

逐段解释：

* 第 17~19 行：``c_reasonable_delay`` 把 ``delay`` 限制到 0 到 100 个周期。
* 第 21~24 行：UVM field macro 注册 ``action`` 和 ``delay``，使对象支持 factory、
  print、copy、compare 等 UVM field 自动化能力。
* 第 26~28 行：constructor 只调用父类 ``new``，默认对象名是
  ``eh2_halt_run_seq_item``。
* 第 30~32 行：``convert2string`` 返回动作名和延迟值；该字符串可用于 log 或调试输出。

接口关系：

* 被调用：UVM factory、sequence、driver 可创建和消费该对象。
* 调用：``action.name()`` 和 ``$sformatf``。
* 共享状态：无全局状态；只格式化当前对象字段。

§5  ``eh2_halt_run_driver.sv`` — 请求驱动
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_halt_run_driver`` 从 sequencer 接收 ``eh2_halt_run_seq_item``，按动作驱动
Halt/Run 请求信号，并等待对应 ack 或固定周期结束。

§5.1  build phase 获取 virtual interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L6-L21``）：

.. code-block:: systemverilog

   class eh2_halt_run_driver extends uvm_driver #(eh2_halt_run_seq_item);

     `uvm_component_utils(eh2_halt_run_driver)

     virtual eh2_halt_run_intf vif;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(this, "", "halt_run_vif", vif)) begin
         `uvm_fatal("halt_run_drv", "Failed to get halt_run interface")
       end
     endfunction

逐段解释：

* 第 6 行：driver 参数化为 ``uvm_driver #(eh2_halt_run_seq_item)``，事务类型与 seq item 文件一致。
* 第 8 行：``uvm_component_utils`` 注册该 driver 类型，供 agent build phase 通过 factory 创建。
* 第 10 行：``vif`` 保存 virtual ``eh2_halt_run_intf``，后续 run phase 只通过这个句柄访问接口。
* 第 12~14 行：constructor 仅调用父类 constructor。
* 第 16~21 行：build phase 从 ``uvm_config_db`` 读取 key ``halt_run_vif``；读取失败时触发
  ``uvm_fatal``，因此没有 interface 时仿真不会继续执行该 driver。

接口关系：

* 被调用：``eh2_halt_run_agent.build_phase`` 在 active 模式创建 driver。
* 调用：``uvm_config_db::get`` 和 ``uvm_fatal``。
* 共享状态：读取 config_db 中的 ``halt_run_vif``。

§5.2  run phase 默认驱动与事务循环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L23-L40``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       eh2_halt_run_seq_item item;

       // Default: no halt request, run request active
       vif.driver_cb.mpc_debug_halt_req <= 1'b0;
       vif.driver_cb.mpc_debug_run_req  <= 1'b1;
       vif.driver_cb.mpc_reset_run_req  <= 1'b1;
       vif.driver_cb.i_cpu_halt_req     <= 1'b0;
       vif.driver_cb.i_cpu_run_req      <= 1'b1;

       forever begin
         seq_item_port.get_next_item(item);

         if (item.delay > 0) begin
           repeat (item.delay) @(posedge vif.clk);
         end

         case (item.action)

逐段解释：

* 第 23~24 行：run phase 声明一个 ``eh2_halt_run_seq_item`` 局部变量，用于接收 sequencer
  下发的 item。
* 第 26~31 行：进入 forever 循环前先驱动默认请求值；这里 ``i_cpu_run_req`` 被 driver 置为
  1，这与 interface 声明处的初值 0 不同，表示 driver 接管后采用自己的运行默认值。
* 第 33~34 行：forever 循环通过 ``seq_item_port.get_next_item(item)`` 阻塞等待下一笔事务。
* 第 36~38 行：如果 ``delay`` 大于 0，则等待对应数量的 ``vif.clk`` 上升沿。
* 第 40 行：driver 根据 ``item.action`` 进入四个动作分支之一。

接口关系：

* 被调用：UVM phase 调度 ``run_phase``。
* 调用：``seq_item_port.get_next_item`` 和 ``@(posedge vif.clk)``。
* 共享状态：写 ``vif.driver_cb`` 请求信号；读 ``item.delay`` 和 ``item.action``。

§5.3  ``HALT_CORE`` — MPC debug halt 请求
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L41-L50``）：

.. code-block:: systemverilog

         eh2_halt_run_seq_item::HALT_CORE: begin
           `uvm_info("halt_run_drv", "Asserting MPC debug halt", UVM_MEDIUM)
           vif.driver_cb.mpc_debug_halt_req <= 1'b1;
           vif.driver_cb.mpc_debug_run_req  <= 1'b0;
           // Wait for acknowledgment
           repeat (100) begin
             @(posedge vif.clk);
             if (vif.o_cpu_halt_ack) break;
           end
         end

逐段解释：

* 第 41 行：该分支匹配 seq item 中的 ``HALT_CORE`` 枚举值。
* 第 42 行：driver 打印 ``Asserting MPC debug halt``，verbosity 是 ``UVM_MEDIUM``。
* 第 43~44 行：driver 拉高 ``mpc_debug_halt_req``，同时拉低 ``mpc_debug_run_req``。
* 第 46~49 行：driver 最多等待 100 个 ``vif.clk`` 上升沿；如果 ``vif.o_cpu_halt_ack``
  为真则提前跳出等待循环。

接口关系：

* 被调用：``run_phase`` 的 ``case (item.action)``。
* 调用：UVM log macro、clock wait、SystemVerilog ``break``。
* 共享状态：写 ``mpc_debug_halt_req``、``mpc_debug_run_req``，读 ``o_cpu_halt_ack``。

§5.4  ``RUN_CORE`` — MPC debug run 请求
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L52-L61``）：

.. code-block:: systemverilog

         eh2_halt_run_seq_item::RUN_CORE: begin
           `uvm_info("halt_run_drv", "Asserting MPC debug run", UVM_MEDIUM)
           vif.driver_cb.mpc_debug_halt_req <= 1'b0;
           vif.driver_cb.mpc_debug_run_req  <= 1'b1;
           // Wait for acknowledgment
           repeat (100) begin
             @(posedge vif.clk);
             if (vif.o_cpu_run_ack) break;
           end
         end

逐段解释：

* 第 52 行：该分支匹配 ``RUN_CORE`` 枚举值。
* 第 53 行：driver 打印 ``Asserting MPC debug run``。
* 第 54~55 行：driver 拉低 ``mpc_debug_halt_req``，拉高 ``mpc_debug_run_req``。
* 第 57~60 行：driver 最多等待 100 个时钟周期；如果 ``vif.o_cpu_run_ack`` 为真则提前
  跳出等待。

接口关系：

* 被调用：``run_phase`` 的 ``case (item.action)``。
* 调用：UVM log macro、clock wait、SystemVerilog ``break``。
* 共享状态：写 ``mpc_debug_halt_req``、``mpc_debug_run_req``，读 ``o_cpu_run_ack``。

§5.5  ``RESET_RUN`` — reset run 请求脉冲
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L63-L68``）：

.. code-block:: systemverilog

         eh2_halt_run_seq_item::RESET_RUN: begin
           `uvm_info("halt_run_drv", "Asserting MPC reset run", UVM_MEDIUM)
           vif.driver_cb.mpc_reset_run_req <= 1'b0;
           repeat (5) @(posedge vif.clk);
           vif.driver_cb.mpc_reset_run_req <= 1'b1;
         end

逐段解释：

* 第 63 行：该分支匹配 ``RESET_RUN`` 枚举值。
* 第 64 行：driver 打印 ``Asserting MPC reset run``。
* 第 65 行：driver 将 ``mpc_reset_run_req`` 置为 0。
* 第 66 行：driver 等待 5 个 ``vif.clk`` 上升沿。
* 第 67 行：driver 将 ``mpc_reset_run_req`` 置回 1。源码没有在该分支等待 ack。

接口关系：

* 被调用：``run_phase`` 的 ``case (item.action)``。
* 调用：UVM log macro 和 clock wait。
* 共享状态：写 ``mpc_reset_run_req``。

§5.6  ``CPU_HALT`` — CPU halt 请求
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L70-L78``）：

.. code-block:: systemverilog

         eh2_halt_run_seq_item::CPU_HALT: begin
           `uvm_info("halt_run_drv", "Asserting CPU halt request", UVM_MEDIUM)
           vif.driver_cb.i_cpu_halt_req <= 1'b1;
           vif.driver_cb.i_cpu_run_req  <= 1'b0;
           repeat (100) begin
             @(posedge vif.clk);
             if (vif.o_cpu_halt_ack) break;
           end
         end

逐段解释：

* 第 70 行：该分支匹配 ``CPU_HALT`` 枚举值。
* 第 71 行：driver 打印 ``Asserting CPU halt request``。
* 第 72~73 行：driver 拉高 ``i_cpu_halt_req``，同时拉低 ``i_cpu_run_req``。
* 第 74~77 行：driver 最多等待 100 个时钟周期；如果 ``vif.o_cpu_halt_ack`` 为真则提前
  跳出等待。

接口关系：

* 被调用：``run_phase`` 的 ``case (item.action)``。
* 调用：UVM log macro、clock wait、SystemVerilog ``break``。
* 共享状态：写 ``i_cpu_halt_req``、``i_cpu_run_req``，读 ``o_cpu_halt_ack``。

§5.7  item 完成握手
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L79-L85``）：

.. code-block:: systemverilog

         endcase

         seq_item_port.item_done();
       end
     endtask

   endclass

逐段解释：

* 第 79 行：结束 ``case``；源码没有 ``default`` 分支，因此合法动作集合来自
  ``action_e`` 枚举。
* 第 81 行：driver 在完成动作分支后调用 ``seq_item_port.item_done()``，向 sequencer
  释放当前 item。
* 第 82~85 行：forever 循环、task 和 class 结束；driver 会继续等待下一笔 seq item。

接口关系：

* 被调用：四个动作分支执行完后进入该公共路径。
* 调用：``seq_item_port.item_done``。
* 共享状态：UVM sequencer/driver item 握手状态。

§6  ``eh2_halt_run_monitor.sv`` — ack/status 观察
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_halt_run_monitor`` 获取同一个 virtual interface，每个 ``clk`` 上升沿读取
ack/status，并在状态为真时打印 UVM log。

§6.1  build phase 与 analysis port
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv:L6-L25``）：

.. code-block:: systemverilog

   class eh2_halt_run_monitor extends uvm_monitor;

     `uvm_component_utils(eh2_halt_run_monitor)

     virtual eh2_halt_run_intf vif;

     // Analysis port for halt/run events
     uvm_analysis_port #(eh2_halt_run_seq_item) item_port;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       item_port = new("item_port", this);
       if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(this, "", "halt_run_vif", vif)) begin
         `uvm_fatal("halt_run_mon", "Failed to get halt_run interface")
       end
     endfunction

逐段解释：

* 第 6 行：monitor 继承 ``uvm_monitor``。
* 第 8 行：``uvm_component_utils`` 注册 monitor 类型，供 agent build phase 创建。
* 第 10 行：``vif`` 保存 virtual ``eh2_halt_run_intf``。
* 第 12~13 行：源码声明并创建 ``uvm_analysis_port #(eh2_halt_run_seq_item) item_port``。
  需要注意的是，后续 ``run_phase`` 没有调用 ``item_port.write``。
* 第 15~17 行：constructor 只调用父类 constructor。
* 第 19~25 行：build phase 创建 ``item_port``，并从 config_db 获取 ``halt_run_vif``；
  获取失败时触发 ``uvm_fatal``。

接口关系：

* 被调用：``eh2_halt_run_agent.build_phase`` 总是创建 monitor。
* 调用：``uvm_config_db::get``、``uvm_fatal`` 和 analysis port constructor。
* 共享状态：读取 config_db 中的 ``halt_run_vif``；持有 ``item_port`` 句柄。

§6.2  run phase 状态日志
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv:L27-L48``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       forever begin
         @(posedge vif.clk);

         // Monitor halt acknowledgment
         if (vif.monitor_cb.o_cpu_halt_ack) begin
           `uvm_info("halt_run_mon", "CPU halt acknowledged", UVM_HIGH)
         end

         // Monitor run acknowledgment
         if (vif.monitor_cb.o_cpu_run_ack) begin
           `uvm_info("halt_run_mon", "CPU run acknowledged", UVM_HIGH)
         end

         // Monitor halt status change
         if (vif.monitor_cb.o_cpu_halt_status) begin
           `uvm_info("halt_run_mon", "CPU is in halt state", UVM_HIGH)
         end
       end
     endtask

   endclass

逐段解释：

* 第 27~29 行：monitor run phase 是无限循环，每个 ``vif.clk`` 上升沿观察一次状态。
* 第 31~34 行：当 ``vif.monitor_cb.o_cpu_halt_ack`` 为真时打印
  ``CPU halt acknowledged``，verbosity 为 ``UVM_HIGH``。
* 第 36~39 行：当 ``vif.monitor_cb.o_cpu_run_ack`` 为真时打印
  ``CPU run acknowledged``。
* 第 41~44 行：当 ``vif.monitor_cb.o_cpu_halt_status`` 为真时打印
  ``CPU is in halt state``。
* 第 45~48 行：结束循环、task 和 class。源码没有读取 ``o_debug_mode_status`` 生成 log，
  也没有向 ``item_port`` 发布事务。

接口关系：

* 被调用：UVM phase 调度 ``run_phase``。
* 调用：UVM log macro 和 clock wait。
* 共享状态：读 ``vif.monitor_cb`` 中的 ack/status。

§7  ``eh2_halt_run_agent.sv`` — top-level agent
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_halt_run_agent`` 组合 monitor、driver 和 sequencer；在 active 模式下连接
driver 与 sequencer。

§7.1  成员声明与 build phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv:L6-L27``）：

.. code-block:: systemverilog

   class eh2_halt_run_agent extends uvm_agent;

     `uvm_component_utils(eh2_halt_run_agent)

     eh2_halt_run_driver  driver;
     eh2_halt_run_monitor monitor;
     uvm_sequencer #(eh2_halt_run_seq_item) sequencer;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);

       monitor = eh2_halt_run_monitor::type_id::create("monitor", this);

       if (get_is_active() == UVM_ACTIVE) begin
         driver    = eh2_halt_run_driver::type_id::create("driver", this);
         sequencer = uvm_sequencer#(eh2_halt_run_seq_item)::type_id::create("sequencer", this);
       end
     endfunction

逐段解释：

* 第 6 行：top-level agent 继承 ``uvm_agent``，因此支持 active/passive 配置。
* 第 8 行：``uvm_component_utils`` 注册 agent 类型。
* 第 10~12 行：agent 声明 driver、monitor 和参数化 sequencer 成员。
* 第 14~16 行：constructor 只调用父类 constructor。
* 第 18~21 行：build phase 总是创建 monitor，不依赖 active/passive 模式。
* 第 23~26 行：只有 ``get_is_active() == UVM_ACTIVE`` 时才创建 driver 和 sequencer。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 创建 ``halt_run_agt``。
* 调用：UVM factory ``type_id::create`` 和 ``get_is_active``。
* 共享状态：``is_active`` config_db 设置决定 driver/sequencer 是否存在。

§7.2  connect phase sequencer 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv:L29-L36``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (get_is_active() == UVM_ACTIVE) begin
         driver.seq_item_port.connect(sequencer.seq_item_export);
       end
     endfunction

   endclass

逐段解释：

* 第 29~30 行：connect phase 先调用父类 connect phase。
* 第 31 行：连接动作同样受 ``UVM_ACTIVE`` 条件保护。
* 第 32 行：driver 的 ``seq_item_port`` 连接到 sequencer 的 ``seq_item_export``，形成
  ``get_next_item``/``item_done`` 的事务通路。
* 第 34~36 行：结束 function 和 class。

接口关系：

* 被调用：UVM connect phase 调度。
* 调用：``driver.seq_item_port.connect``。
* 共享状态：driver/sequencer 连接状态。

§8  Env、vseqr 与 tb 顶层连接
------------------------------------------------------------------------------------------------------------------------

职责：Halt/Run agent 的运行依赖 env 实例化、virtual sequencer 暴露、tb 顶层 interface
连接和 config_db 注入。

§8.1  env 中创建 active agent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L87-L100``）：

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

       // Trace monitor
       trace_monitor = eh2_trace_monitor::type_id::create("trace_monitor", this);

逐段解释：

* 第 87~93 行：env 对 irq 和 jtag agent 也设置 ``UVM_ACTIVE``；这给 Halt/Run agent
  的 active 配置提供上下文。
* 第 95~97 行：env 创建 ``halt_run_agt``，并用 config_db 把该实例的 ``is_active`` 设为
  ``UVM_ACTIVE``。
* 第 99~100 行：trace monitor 在 Halt/Run agent 后创建；该片段不显示二者直接连接。

接口关系：

* 被调用：``core_eh2_env.build_phase``。
* 调用：UVM factory 和 ``uvm_config_db::set``。
* 共享状态：``halt_run_agt`` 实例和其 ``is_active`` 配置。

§8.2  virtual sequencer 句柄
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L20``）：

.. code-block:: systemverilog

   class core_eh2_vseqr extends uvm_sequencer;

     `uvm_component_utils(core_eh2_vseqr)

     // Sub-sequencers (use specific types for type-safe access)
     eh2_irq_sequencer              irq_seqr;
     eh2_jtag_sequencer             jtag_seqr;
     uvm_sequencer #(eh2_halt_run_seq_item) halt_run_seqr;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

   endclass

逐段解释：

* 第 7 行：``core_eh2_vseqr`` 继承 ``uvm_sequencer``，作为虚拟序列协调入口。
* 第 9 行：注册 virtual sequencer 类型。
* 第 11~14 行：virtual sequencer 保存 irq、jtag 和 halt/run 三类 sub-sequencer 句柄；
  Halt/Run 使用普通 ``uvm_sequencer #(eh2_halt_run_seq_item)``。
* 第 16~18 行：constructor 只调用父类 constructor。
* 第 20 行：结束 class；该文件没有 run phase 或额外连接逻辑。

接口关系：

* 被调用：``core_eh2_env`` 创建并填充 ``vseqr``。
* 调用：无。
* 共享状态：``halt_run_seqr`` 被 env connect phase 赋值，供 virtual sequence 使用。

§8.3  env connect phase 暴露 Halt/Run sequencer
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
* 第 170~171 行：irq 和 jtag sequencer 先被赋给 virtual sequencer。
* 第 172 行：``halt_run_agt.sequencer`` 被赋给 ``vseqr.halt_run_seqr``。由于 env build
  phase 已把 ``halt_run_agt`` 设为 ``UVM_ACTIVE``，agent build phase 会创建该 sequencer。
* 第 173 行：结束 connect phase。

接口关系：

* 被调用：UVM connect phase 调度。
* 调用：无函数调用，只做句柄赋值。
* 共享状态：``vseqr.halt_run_seqr`` 指向 ``halt_run_agt.sequencer``。

§8.4  tb 顶层信号连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L920-L934``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
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

* 第 920~921 行：tb 顶层实例化 ``eh2_halt_run_intf``，时钟接 ``core_clk``，复位接
  ``rst_l``。
* 第 923~928 行：interface 内的 5 个请求信号被连续赋值到 DUT 侧 Halt/Run 输入 wire。
* 第 930~934 行：DUT 输出的 ack/status 数组第 0 项被反馈到 interface。源码片段只连接
  ``[0]``，本章不推断其它 thread 的 Halt/Run agent 连接。

接口关系：

* 被调用：tb 顶层 elaboration。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``halt_run_vif`` 是 driver、monitor、base test helper 与 DUT 之间的共享接口。

§8.5  config_db 注入 virtual interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1124-L1132``）：

.. code-block:: systemverilog


       // Store JTAG interface
       uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);

       // Store Halt/Run interface
       uvm_config_db#(virtual eh2_halt_run_intf)::set(null, "*", "halt_run_vif", halt_run_vif);

       // Store fetch enable interface
       uvm_config_db#(virtual fetch_enable_intf)::set(null, "*", "fetch_vif", fetch_en_intf);

逐段解释：

* 第 1125~1126 行：tb 顶层先把 JTAG interface 存入 config_db。
* 第 1128~1129 行：``halt_run_vif`` 以 key ``halt_run_vif`` 存入 config_db，instance pattern
  是 ``"*"``，因此 driver、monitor 和 base test 可以从各自上下文读取。
* 第 1131~1132 行：fetch enable interface 随后也被存入 config_db；该片段显示 Halt/Run
  interface 与其它 tb virtual interface 一起注册。

接口关系：

* 被调用：tb 顶层 initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：config_db 中的 ``halt_run_vif``。

§9  Base Test 直接使用 ``halt_run_vif``
------------------------------------------------------------------------------------------------------------------------

职责：除 agent driver 外，``core_eh2_base_test`` 也从 config_db 获取 ``halt_run_vif``，
并在 binary loading 前后直接驱动 MPC debug halt/run 信号。

§9.1  ``halt_core_for_loading()`` — 加载前 halt
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L158-L179``）：

.. code-block:: systemverilog

     // Halt core during binary loading (prevent partial execution)
     virtual task halt_core_for_loading();
       if (halt_run_vif == null) begin
         `uvm_warning(test_name, "Cannot halt core for loading: halt_run_vif is null")
         return;
       end
       `uvm_info(test_name, "Halting core for binary loading", UVM_LOW)
       halt_run_vif.mpc_debug_halt_req <= '1;
       halt_run_vif.mpc_debug_run_req  <= '0;
       // Wait for halt acknowledgment (with timeout)
       fork
         begin
           wait (halt_run_vif.o_cpu_halt_ack !== '0);
         end
         begin
           tb_vif.wait_clks(100);
           `uvm_warning(test_name, "Timeout waiting for mpc_debug_halt_ack")
         end
       join_any
       disable fork;
       tb_vif.wait_clks(2);
     endtask

逐段解释：

* 第 158~163 行：task 先检查 ``halt_run_vif`` 是否为空；为空时打印 warning 并返回。
* 第 164~166 行：task 打印 loading 前 halt log，随后拉高 ``mpc_debug_halt_req``、拉低
  ``mpc_debug_run_req``。
* 第 168~176 行：task 用 ``fork``/``join_any`` 同时等待 ``o_cpu_halt_ack`` 非 0 和 100
  个 ``tb_vif`` clock timeout；任一路完成后退出。
* 第 177~178 行：``disable fork`` 终止未完成分支，然后额外等待 2 个 clock。
* 第 179 行：结束 task。

接口关系：

* 被调用：base test 的 binary loading 流程可以调用该 helper。
* 调用：``uvm_warning``、``uvm_info``、``wait``、``tb_vif.wait_clks``。
* 共享状态：直接写 ``halt_run_vif.mpc_debug_halt_req`` 和 ``mpc_debug_run_req``，读
  ``halt_run_vif.o_cpu_halt_ack``。

§9.2  ``release_core_after_loading()`` — 加载后 run
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L181-L191``）：

.. code-block:: systemverilog

     // Release core after binary loading
     virtual task release_core_after_loading();
       if (halt_run_vif == null) begin
         `uvm_warning(test_name, "Cannot release core after loading: halt_run_vif is null")
         return;
       end
       `uvm_info(test_name, "Releasing core after binary loading", UVM_LOW)
       halt_run_vif.mpc_debug_halt_req <= '0;
       halt_run_vif.mpc_debug_run_req  <= '1;
       tb_vif.wait_clks(5);
     endtask

逐段解释：

* 第 181~186 行：release helper 同样先检查 ``halt_run_vif`` 是否为空；为空则 warning 后返回。
* 第 187~189 行：task 打印 release log，拉低 ``mpc_debug_halt_req`` 并拉高
  ``mpc_debug_run_req``。
* 第 190 行：task 等待 5 个 ``tb_vif`` clock；源码没有在 release helper 中等待
  ``o_cpu_run_ack``。
* 第 191 行：结束 task。

接口关系：

* 被调用：base test 的 binary loading 流程可以调用该 helper。
* 调用：``uvm_warning``、``uvm_info`` 和 ``tb_vif.wait_clks``。
* 共享状态：直接写 ``halt_run_vif.mpc_debug_halt_req`` 和 ``mpc_debug_run_req``。

§10  运行时行为边界
------------------------------------------------------------------------------------------------------------------------

职责：本节把前面的代码片段合并成可执行行为边界，避免把未实现的协议能力写进文档。

§10.1  Driver 与 base test 是两条驱动路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

driver 和 base test helper 都能写 ``halt_run_vif`` 的请求信号，但来源不同：

* driver 通过 ``vif.driver_cb`` 写请求，触发条件是 sequencer 下发
  ``eh2_halt_run_seq_item``。
* base test helper 直接写 ``halt_run_vif.mpc_debug_halt_req`` 和
  ``halt_run_vif.mpc_debug_run_req``，触发条件是 test 的加载流程调用 helper task。

源码没有在 ``eh2_halt_run_driver.sv`` 与 ``core_eh2_base_test.sv`` 之间提供仲裁器；因此文档只说明
两处都能驱动同一 interface，不推断并发调用时的仲裁策略。

接口关系：

* 被调用：driver 路径来自 UVM sequence；helper 路径来自 base test task。
* 调用：driver 调 ``seq_item_port``；helper 调 ``tb_vif.wait_clks``。
* 共享状态：``halt_run_vif`` 请求信号。

§10.2  Monitor 目前是日志观察者
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``eh2_halt_run_monitor`` 的 build phase 创建了 ``item_port``，这说明类型上预留了 analysis port。
但该文件第 27~48 行的 run phase 只包含 clock wait、3 个 ``if`` 和 3 条 ``uvm_info``。
源码没有 ``item_port.write``，也没有构造新的 ``eh2_halt_run_seq_item``。因此当前文档把 monitor
描述为 ack/status 日志观察者，而不是 scoreboard 输入源。

接口关系：

* 被调用：agent build phase 创建 monitor，UVM phase 调度 monitor run phase。
* 调用：``uvm_info``。
* 共享状态：``vif.monitor_cb.o_cpu_halt_ack``、``o_cpu_run_ack`` 和
  ``o_cpu_halt_status``。

§11  参考资料
------------------------------------------------------------------------------------------------------------------------

* :ref:`agent_halt_run` — verification architecture 中的 Halt/Run agent 说明。
* :ref:`appendix_b_uvm_axi4_agent` — env 中另一个 passive/active 混合 agent 的源码字典。
* :doc:`../05_verification_arch/cosim_scoreboard` — cosim scoreboard 数据路径背景。
* :ref:`adr-0001` — cosim via trace and probe，解释 trace/probe cosim 总体决策。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv``。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv``。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv``。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv``。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv``。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv``。

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

§12  v2-17 源码片段闭环
--------------------------------------------------------------------------------

本节补齐 Halt/Run agent 中缺少 ``literalinclude`` 的 package、agent wrapper 和
monitor 文件。前文已经说明 base test helper 与 driver 都能写同一 virtual interface；
这里用源码片段固定当前 monitor 只是日志观察者的事实。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv
   :language: systemverilog
   :lines: 1-14
   :linenos:
   :caption: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv:L1-L14

逐段精读：L4-L7 建立 package 与 UVM 依赖；L9-L13 include seq item、driver、
monitor 和 agent。monitor 被纳入 package，但并不等于它向 scoreboard 发布 transaction。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv
   :language: systemverilog
   :lines: 1-36
   :linenos:
   :caption: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv:L1-L36

逐段精读：L4-L12 声明 driver、sequencer 和 monitor；L18-L30 在 active 模式创建
driver/sequencer，并始终创建 monitor；L32-L34 只连接 driver 到 sequencer。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv
   :language: systemverilog
   :lines: 1-48
   :linenos:
   :caption: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv:L1-L48

逐段精读：L5-L13 声明 virtual interface 和 ``item_port``；L19-L25 从
``uvm_config_db`` 取得 ``vif`` 并创建 analysis port；L27-L47 的 run phase 只观察
ack/status 并打印 ``uvm_info``，没有 ``item_port.write``。

§13  v2-29 Halt/Run interface、item 与 driver 全源码精读
--------------------------------------------------------------------------------

本节补齐 Halt/Run agent 目录中此前未全文覆盖的 interface、sequence item 和 driver。
这些文件决定 active stimulus 如何写 MPC debug halt/run、reset-run 和 CPU halt 请求。

§13.1  ``eh2_halt_run_intf.sv`` — halt/run 信号束与 clocking block
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv
   :language: text
   :linenos:
   :caption: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:全文

逐段精读：

* L1-L5：文件头说明该 interface 负责驱动 MPC halt/run、CPU halt/run，并观察对应
  acknowledge/status 信号。
* L7-L10：interface 端口只接收 ``clk`` 和 ``rst_n``，具体请求与响应信号在 interface
  内声明，由 TB 顶层连接到 DUT。
* L12-L21：请求信号分为 MPC debug halt/run/reset-run 和 CPU halt/run 两组。默认值让
  debug run/reset-run 为高，halt 请求为低，CPU run request 注释说明参考 testbench
  中保持为 0。
* L23-L28：ack/status 信号包括 CPU halt ack、CPU run ack、CPU halt status 和 debug mode
  status，供 driver 等待和 monitor 打 log。
* L29-L36：driver clocking block 声明可输出的请求信号，统一在 ``posedge clk`` 驱动。
* L38-L49：monitor clocking block 只读请求与响应信号，用于 observation path。
* L51-L56：driver modport 允许 driver 通过 clocking block 写请求并直接读 ack/status；
  monitor modport 只暴露只读 clocking block。

§13.2  ``eh2_halt_run_seq_item.sv`` — halt/run 动作编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv
   :language: text
   :linenos:
   :caption: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv:全文

逐段精读：

* L1-L4：文件头与 class 声明表明该 item 是 Halt/Run agent 的 UVM transaction 类型。
* L6-L15：``action_e`` 定义 4 种动作：halt core、run core、reset run 和 CPU halt；
  item 还包含一个随机 delay 字段，用于发起动作前等待若干 clock。
* L17-L24：约束把 delay 限制在 0 到 100 个周期，并用 UVM field macro 注册 action
  与 delay，便于随机化、打印和比较。
* L26-L34：constructor 只调用父类；``convert2string`` 输出 action 名称与 delay，
  是 driver log 的 transaction 摘要。

§13.3  ``eh2_halt_run_driver.sv`` — active halt/run 请求驱动
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv
   :language: text
   :linenos:
   :caption: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:全文

逐段精读：

* L1-L6：文件头说明 driver 通过 Halt/Run interface 向 DUT 驱动 halt/run 信号；class
  继承 ``uvm_driver#(eh2_halt_run_seq_item)``。
* L8-L21：注册 component 类型，保存 virtual interface，并在 build phase 从 config DB
  读取 ``halt_run_vif``。读取失败为 fatal，因为 active driver 无法无接口运行。
* L23-L31：run phase 开始时给请求信号设置默认值：不请求 halt，debug run/reset-run
  为高，CPU halt 为低，CPU run 为高。
* L33-L39：主循环从 sequencer 获取 item，并按 item 的 delay 等待对应数量的 clock。
* L40-L50：``HALT_CORE`` 拉高 ``mpc_debug_halt_req``、拉低 ``mpc_debug_run_req``，
  最多等待 100 个 clock 直到 ``o_cpu_halt_ack``。
* L52-L61：``RUN_CORE`` 清 halt、拉高 debug run，并最多等待 100 个 clock 直到
  ``o_cpu_run_ack``。
* L63-L68：``RESET_RUN`` 短暂拉低 ``mpc_reset_run_req`` 5 个周期，再拉回高电平。
* L70-L78：``CPU_HALT`` 走 CPU halt 请求线，拉高 ``i_cpu_halt_req``、拉低
  ``i_cpu_run_req``，并等待 halt ack。
* L80-L85：每个 case 完成后调用 ``item_done``，driver 不生成 response item。
