.. _agent_halt_run:
.. _05_verification_arch/agent_halt_run:

Halt/Run Agent — 架构参考
==========================

:status: draft
:source: dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  本章边界
------------

本章解释 Halt/Run agent 在 EH2 UVM 环境中的信号路径和时序角色。逐类源码字典见
:ref:`appendix_b_uvm_halt_run_agent`；这里聚焦三件事：env 如何把 agent 配成
``UVM_ACTIVE``，testbench 如何把 ``eh2_halt_run_intf`` 接到 DUT，driver 如何把
``eh2_halt_run_seq_item.action`` 转换成 MPC/CPU halt-run 请求。

Halt/Run agent 目录包含 6 个源文件：

* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv`
* :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv`

§2  架构数据流
--------------

Halt/Run agent 是一个 active stimulus agent。它的 driver 从 sequencer 取
``eh2_halt_run_seq_item``，通过 virtual interface 的 driver clocking block 驱动
请求；monitor 通过 monitor clocking block 读取 ack/status 并写 UVM log。源码中
monitor 创建了 ``item_port``，但当前 ``run_phase`` 没有调用 ``item_port.write``，
所以本章不把它描述为已连接的事务发布通道。

.. code-block:: text

   core_eh2_vseqr.halt_run_seqr
              |
              v
   eh2_halt_run_agent.sequencer
              |
              v
   eh2_halt_run_driver.seq_item_port
              |
              v
   eh2_halt_run_intf.driver_cb
              |
              +--> mpc_debug_halt_req / mpc_debug_run_req / mpc_reset_run_req
              +--> i_cpu_halt_req / i_cpu_run_req
              |
              v
            DUT
              |
              v
   eh2_halt_run_intf.monitor_cb
              |
              v
   eh2_halt_run_monitor -> UVM log

接口关系：

* 被调用：virtual sequence 通过 ``core_eh2_vseqr.halt_run_seqr`` 启动
  ``eh2_halt_run_seq_item``。
* 调用：driver 调用 ``seq_item_port.get_next_item``，然后写
  ``eh2_halt_run_intf.driver_cb``。
* 共享状态：``halt_run_vif``、``action``、``delay``、ack/status 信号。

§3  Env 中的 active agent 配置
-------------------------------

职责：``core_eh2_env`` 创建 Halt/Run agent，并显式把 ``is_active`` 设置为
``UVM_ACTIVE``。connect phase 再把 agent sequencer 暴露到 virtual sequencer。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L91-L97``）：

.. code-block:: systemverilog

   // JTAG agent (active)
   jtag_agent = eh2_jtag_agent::type_id::create("jtag_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "jtag_agent", "is_active", UVM_ACTIVE);
   
   // Halt/Run agent (active)
   halt_run_agt = eh2_halt_run_agent::type_id::create("halt_run_agt", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "halt_run_agt", "is_active", UVM_ACTIVE);

逐段解释：

* 第 92~93 行：相邻代码显示 JTAG agent 也被配置为 active；Halt/Run 不是唯一主动
  stimulus agent。
* 第 96 行：env 用 UVM factory 创建 ``halt_run_agt``。
* 第 97 行：config_db 把 ``halt_run_agt`` 的 ``is_active`` 设置成 ``UVM_ACTIVE``，
  这会让 agent build phase 创建 driver 和 sequencer。

接口关系：

* 被调用：UVM build phase。
* 调用：``eh2_halt_run_agent::type_id::create`` 和 ``uvm_config_db::set``。
* 共享状态：``halt_run_agt`` 句柄与 ``is_active`` 配置项。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L172``）：

.. code-block:: systemverilog

   // Wire sub-sequencers to virtual sequencer
   vseqr.irq_seqr      = irq_agent.sequencer;
   vseqr.jtag_seqr     = jtag_agent.sequencer;
   vseqr.halt_run_seqr = halt_run_agt.sequencer;

逐段解释：

* 第 170~171 行：IRQ 与 JTAG sequencer 也接入 virtual sequencer。
* 第 172 行：``halt_run_agt.sequencer`` 赋给 ``vseqr.halt_run_seqr``，virtual
  sequence 由此获得 Halt/Run stimulus 入口。

接口关系：

* 被调用：UVM connect phase。
* 调用：普通句柄赋值，不调用 TLM connect。
* 共享状态：``vseqr.halt_run_seqr``。

§4  Agent 内部组件
------------------

职责：``eh2_halt_run_agent`` 总是创建 monitor；只有 active 模式才创建 driver 和
sequencer，并把 driver 的 seq item port 连接到 sequencer export。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv:L6-L34``）：

.. code-block:: systemverilog

   class eh2_halt_run_agent extends uvm_agent;
   
     `uvm_component_utils(eh2_halt_run_agent)
   
     eh2_halt_run_driver  driver;
     eh2_halt_run_monitor monitor;
     uvm_sequencer #(eh2_halt_run_seq_item) sequencer;
   
     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
   
       monitor = eh2_halt_run_monitor::type_id::create("monitor", this);
   
       if (get_is_active() == UVM_ACTIVE) begin
         driver    = eh2_halt_run_driver::type_id::create("driver", this);
         sequencer = uvm_sequencer#(eh2_halt_run_seq_item)::type_id::create("sequencer", this);
       end
     endfunction
   
     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (get_is_active() == UVM_ACTIVE) begin
         driver.seq_item_port.connect(sequencer.seq_item_export);
       end
     endfunction

逐段解释：

* 第 10~12 行：agent 由 driver、monitor 和 typed sequencer 三类组件组成。
* 第 21 行：monitor 不受 active/passive 模式影响，总是创建。
* 第 23~26 行：``get_is_active() == UVM_ACTIVE`` 时才创建 driver 和 sequencer。
* 第 31~32 行：active 模式下建立 ``driver.seq_item_port`` 到
  ``sequencer.seq_item_export`` 的连接。

接口关系：

* 被调用：env 创建 agent 后，UVM 调用 build/connect phase。
* 调用：UVM factory 和 TLM seq item port/export connect。
* 共享状态：``is_active``、``driver``、``monitor``、``sequencer``。

§5  Virtual interface 信号边界
------------------------------

职责：``eh2_halt_run_intf`` 定义 driver 写入的请求信号和 monitor 读取的状态信号。
它同时提供 driver 与 monitor 两个 clocking block，避免直接在 class 中使用裸信号采样。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L7-L27``）：

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
   
     // Acknowledgment signals (active high)
     logic o_cpu_halt_ack;
     logic o_cpu_run_ack;
     logic o_cpu_halt_status;
     logic o_debug_mode_status;

逐段解释：

* 第 7~10 行：interface 使用 ``clk`` 和 ``rst_n``，与 testbench 的 core clock/reset
  绑定。
* 第 13~15 行：MPC debug halt/run/reset-run 请求有默认值：
  ``halt_req=0``、``run_req=1``、``reset_run_req=1``。
* 第 20~21 行：CPU halt/run 请求默认 ``i_cpu_halt_req=0``、
  ``i_cpu_run_req=0``；注释说明该默认 run 请求取值匹配 reference testbench。
* 第 24~27 行：ack/status 由 DUT 输出再回灌 interface。

接口关系：

* 被调用：testbench 实例化 ``halt_run_vif``。
* 调用：无函数调用；定义 wire/logic 与 clocking block 的边界。
* 共享状态：MPC 请求、CPU 请求、ack/status。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L29-L54``）：

.. code-block:: systemverilog

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
   
   // Modports
   modport driver  (clocking driver_cb, input clk, rst_n,
                    input o_cpu_halt_ack, o_cpu_run_ack, o_cpu_halt_status, o_debug_mode_status);
   modport monitor (clocking monitor_cb, input clk, rst_n);

逐段解释：

* 第 30~36 行：driver clocking block 只把请求信号声明为 output。
* 第 39~49 行：monitor clocking block 同时采样请求与 ack/status。
* 第 52~54 行：modport 为 driver 提供 clocking block、clock/reset 和 ack/status，
  为 monitor 提供 monitor clocking block、clock/reset。

接口关系：

* 被调用：driver 和 monitor 通过 config_db 获取该 virtual interface。
* 调用：SystemVerilog clocking block。
* 共享状态：``driver_cb``、``monitor_cb`` 与 modport 声明的信号集合。

§6  Testbench 信号接线
----------------------

职责：testbench 实例化 ``eh2_halt_run_intf``，把请求信号连到 DUT 输入，把
DUT ack/status 输出回灌到 interface，并通过 config_db 发布 virtual interface。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L919-L934``）：

.. code-block:: systemverilog

   // Halt/Run Interface Instance (for halt/run stimulus)
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

逐段解释：

* 第 921 行：``halt_run_vif`` 绑定 ``core_clk`` 和 ``rst_l``。
* 第 924~928 行：interface 请求信号驱动 DUT 的 MPC debug halt/run/reset-run 以及
  CPU halt/run 输入。
* 第 931~934 行：DUT thread 0 的 CPU halt ack、run ack、halt status 和 debug mode
  status 回灌到 interface。

接口关系：

* 被调用：testbench elaboration。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``halt_run_vif``、DUT halt/run 顶层信号。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1128-L1129``）：

.. code-block:: systemverilog

   // Store Halt/Run interface
   uvm_config_db#(virtual eh2_halt_run_intf)::set(null, "*", "halt_run_vif", halt_run_vif);

逐段解释：

* 第 1129 行：config_db 使用全局 ``"*"`` scope 发布 ``halt_run_vif``，driver、
  monitor 和其它需要该接口的组件都通过字段名 ``halt_run_vif`` 获取它。

接口关系：

* 被调用：testbench initial 配置块。
* 调用：``uvm_config_db::set``。
* 共享状态：virtual ``eh2_halt_run_intf``。

§7  Sequence item 动作集合
--------------------------

职责：``eh2_halt_run_seq_item`` 用 ``action`` 枚举表达四种操作，并用 ``delay``
控制操作前等待的 clock cycle 数。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv:L4-L19``）：

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
   
     constraint c_reasonable_delay {
       delay inside {[0:100]};
     }

逐段解释：

* 第 4 行：transaction 类型继承自 ``uvm_sequence_item``。
* 第 7~12 行：``action_e`` 枚举定义四个动作：``HALT_CORE``、``RUN_CORE``、
  ``RESET_RUN``、``CPU_HALT``。
* 第 14~15 行：``action`` 与 ``delay`` 都是随机字段。
* 第 17~19 行：``delay`` 被约束在 0 到 100 个 clock cycle。

接口关系：

* 被调用：sequencer 向 driver 提供该 item。
* 调用：无外部函数。
* 共享状态：``action`` 和 ``delay``。

§8  Driver 默认状态与取 item 循环
---------------------------------

职责：driver 从 config_db 获取 ``halt_run_vif``，在 run phase 先设置默认请求状态，
然后循环消费 sequence item。每个 item 可先等待 ``delay`` 个 clock cycle，再按
``action`` 驱动请求。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L16-L38``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(this, "", "halt_run_vif", vif)) begin
       `uvm_fatal("halt_run_drv", "Failed to get halt_run interface")
     end
   endfunction
   
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

逐段解释：

* 第 18~20 行：driver 必须获得 ``halt_run_vif``；获取失败触发 ``uvm_fatal``。
* 第 27~31 行：run phase 初始默认状态为 MPC halt 请求不置位，MPC run/reset-run
  置位，CPU halt 不置位，CPU run 置位。
* 第 33~34 行：driver 永久循环，从 sequencer 获取下一个 item。
* 第 36~38 行：若 ``item.delay`` 大于 0，则等待对应数量的 ``vif.clk`` 上升沿。

接口关系：

* 被调用：active agent 的 driver run phase。
* 调用：``uvm_config_db::get``、``seq_item_port.get_next_item``。
* 共享状态：``vif``、``seq_item_port``、``item.delay``。

§9  Driver 的四类动作
---------------------

职责：driver 用 ``case (item.action)`` 将四种抽象动作映射为 interface 请求和 ack
等待。源码没有单独处理 default 分支，因此文档只列出枚举中存在的四种动作。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L40-L68``）：

.. code-block:: systemverilog

   case (item.action)
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
   
     eh2_halt_run_seq_item::RESET_RUN: begin
       `uvm_info("halt_run_drv", "Asserting MPC reset run", UVM_MEDIUM)
       vif.driver_cb.mpc_reset_run_req <= 1'b0;

逐段解释：

* 第 41~49 行：``HALT_CORE`` 置位 ``mpc_debug_halt_req``、清零
  ``mpc_debug_run_req``，最多等待 100 个 clock cycle，期间看到 ``o_cpu_halt_ack``
  即跳出等待。
* 第 52~60 行：``RUN_CORE`` 清零 ``mpc_debug_halt_req``、置位 ``mpc_debug_run_req``，
  最多等待 100 个 clock cycle，期间看到 ``o_cpu_run_ack`` 即跳出等待。
* 第 63~68 行：``RESET_RUN`` 将 ``mpc_reset_run_req`` 拉低，等待 5 个 clock cycle
  后重新拉高。

接口关系：

* 被调用：``eh2_halt_run_driver.run_phase``。
* 调用：``uvm_info``、clock wait。
* 共享状态：``item.action``、``vif.driver_cb``、``vif.o_cpu_halt_ack``、
  ``vif.o_cpu_run_ack``。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L70-L82``）：

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
   endcase
   
   seq_item_port.item_done();

逐段解释：

* 第 70~78 行：``CPU_HALT`` 置位 ``i_cpu_halt_req``、清零 ``i_cpu_run_req``，最多等待
  100 个 clock cycle，期间看到 ``o_cpu_halt_ack`` 即跳出等待。
* 第 79 行：结束 ``case``。
* 第 81 行：driver 调用 ``item_done``，通知 sequencer 当前 item 已处理完成。

接口关系：

* 被调用：``eh2_halt_run_driver.run_phase``。
* 调用：``seq_item_port.item_done``。
* 共享状态：``i_cpu_halt_req``、``i_cpu_run_req``、``o_cpu_halt_ack``。

§10  Monitor 观察点
-------------------

职责：monitor 从 config_db 获取同一个 ``halt_run_vif``，每个 clock 采样 ack/status。
当前实现只输出 UVM log，不向外发布 transaction。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv:L19-L45``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     item_port = new("item_port", this);
     if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(this, "", "halt_run_vif", vif)) begin
       `uvm_fatal("halt_run_mon", "Failed to get halt_run interface")
     end
   endfunction
   
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

逐段解释：

* 第 21 行：monitor 创建 ``item_port``，但该端口在当前文件后续代码中没有
  ``write`` 调用。
* 第 22~24 行：monitor 也从 config_db 获取 ``halt_run_vif``；获取失败触发
  ``uvm_fatal``。
* 第 27~29 行：monitor 永久循环，每个 ``vif.clk`` 上升沿采样。
* 第 32~39 行：看到 ``o_cpu_halt_ack`` 或 ``o_cpu_run_ack`` 时分别输出 UVM log。

接口关系：

* 被调用：agent build phase 创建 monitor，UVM run phase 启动 monitor。
* 调用：``uvm_config_db::get``、``uvm_info``。
* 共享状态：``vif.monitor_cb.o_cpu_halt_ack``、``vif.monitor_cb.o_cpu_run_ack``。

关键代码（``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv:L41-L45``）：

.. code-block:: systemverilog

   // Monitor halt status change
   if (vif.monitor_cb.o_cpu_halt_status) begin
     `uvm_info("halt_run_mon", "CPU is in halt state", UVM_HIGH)
   end

逐段解释：

* 第 42~43 行：monitor 看到 ``o_cpu_halt_status`` 为真时记录 CPU 处于 halt 状态。
  源码没有保存前一拍状态，因此这是电平观察，而不是边沿变化检测。

接口关系：

* 被调用：``eh2_halt_run_monitor.run_phase`` 的每拍循环。
* 调用：``uvm_info``。
* 共享状态：``vif.monitor_cb.o_cpu_halt_status``。

§11  与 JTAG debug 的边界
-------------------------

Halt/Run agent 与 JTAG agent 都是 active agent，但源码边界不同：Halt/Run agent
只驱动 ``eh2_halt_run_intf`` 中的 MPC/CPU halt-run 请求；JTAG agent 使用
``eh2_jtag_intf`` 和 JTAG/DMI 信号。本章不把 Halt/Run 描述为 JTAG DMI 事务通道。
在 testbench 中，Halt/Run 请求连接到 ``mpc_debug_halt_req``、
``mpc_debug_run_req``、``mpc_reset_run_req``、``i_cpu_halt_req`` 和
``i_cpu_run_req``；JTAG interface 通过独立 ``jtag_vif`` 发布。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1126-L1129``）：

.. code-block:: systemverilog

   uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);
   
   // Store Halt/Run interface
   uvm_config_db#(virtual eh2_halt_run_intf)::set(null, "*", "halt_run_vif", halt_run_vif);

逐段解释：

* 第 1126 行：JTAG virtual interface 以字段名 ``jtag_vif`` 发布。
* 第 1129 行：Halt/Run virtual interface 以字段名 ``halt_run_vif`` 发布。
  两者在 config_db 中使用不同类型和字段名。

接口关系：

* 被调用：testbench initial 配置块。
* 调用：``uvm_config_db::set``。
* 共享状态：``jtag_vif`` 与 ``halt_run_vif`` 是不同 virtual interface。

§12  参考资料
-------------

* :ref:`appendix_b_uvm_halt_run_agent` — Halt/Run agent 逐类源码字典。
* :doc:`env` — env 中 active/passive agent 与 virtual sequencer 的连接。
* :doc:`tb_top` — testbench 顶层 virtual interface 分发。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_monitor.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

§13  与 Ibex 工业实现对照
-------------------------

Ibex 中 halt/debug 主要通过 debug request、RVFI trap/debug 状态和 cosim scoreboard
路径闭合。EH2 额外提供 ``eh2_halt_run_agent``，因为 VeeR EH2 wrapper 暴露
``mpc_debug_halt_req``、``mpc_debug_run_req``、``mpc_reset_run_req``、
``i_cpu_halt_req`` 和 ``i_cpu_run_req`` 等直接 halt/run 控制面。这个 agent 不替代
JTAG/DMI；它用于验证 MPC/CPU halt-run pin-level 行为和 debug 状态握手。

.. list-table:: Halt/Run 与 Ibex debug 路径对照
   :header-rows: 1
   :widths: 26 34 40

   * - 维度
     - Ibex
     - EH2
   * - debug 入口
     - debug req/RVFI/debug CSR 路径
     - JTAG agent + Halt/Run agent 双入口
   * - pin-level halt/run
     - 不是主要独立 agent
     - ``eh2_halt_run_intf`` 直接驱动 MPC/CPU request
   * - monitor
     - 通过 RVFI/debug state 观察
     - ``o_cpu_halt_ack``、``o_cpu_run_ack``、``o_cpu_halt_status`` 电平观察
   * - 与 cosim 关系
     - scoreboard 处理 debug priority
     - trace/probe 携带 debug state，Halt/Run agent 只负责 stimulus

§14  Sign-off 关联
------------------

Halt/Run agent 主要服务 debug directed、integration tests 和波形调试。它不是所有
riscv-dv 测试的默认 stimulus，但它的 config_db 字段和 DUT 接线会影响 debug/halt
相关 directed 的稳定性。当前 2026-05-19 demo 已完成 directed 40/40 和 formal 46/46；
若修改 halt/run interface 或 driver 时序，应至少补跑 debug directed、smoke 和 cosim
debug 场景。

.. warning::

   Halt/Run agent 的 driver 使用 level-style request 加 cycle delay。若 sequence 在
   reset 期间发起请求，pre-reset/reset phase 必须清理 request 信号，否则 DUT 可能在
   reset deassert 第一拍看到残留 halt/run。当前 driver/monitor 的 reset 行为是本章
   需要保留的接口语义。

§15  时序与 ack 语义
--------------------

Halt/Run agent 的四类动作都采用 level-style request，并等待最多 100 个 clock cycle
观察 ack。这个等待不是严格的 protocol assertion，而是 stimulus driver 的同步机制；
若超时，当前 driver 不主动报 fatal，因此 directed test 或后续 scoreboard 仍需检查
debug/halt 状态是否符合预期。

.. list-table:: Halt/Run 动作语义
   :header-rows: 1
   :widths: 24 30 46

   * - 动作
     - 请求
     - 期望观察
   * - ``HALT_CORE``
     - ``mpc_debug_halt_req=1``、``mpc_debug_run_req=0``
     - ``o_cpu_halt_ack`` 或 ``o_cpu_halt_status``
   * - ``RUN_CORE``
     - ``mpc_debug_halt_req=0``、``mpc_debug_run_req=1``
     - ``o_cpu_run_ack``，随后 core 继续 retire
   * - ``RESET_RUN``
     - ``mpc_reset_run_req`` 短暂拉低后拉高
     - reset-run 相关状态恢复
   * - ``CPU_HALT``
     - ``i_cpu_halt_req=1``、``i_cpu_run_req=0``
     - ``o_cpu_halt_ack`` 和 halt status

.. tip::

   若 directed 只发送 Halt/Run item 而不检查 ack/status，测试可能 mailbox PASS 但没有
   验证 halt/run 行为。debug 场景应同时检查 trace 退休停止/恢复、probe debug state
   和 DUT ack/status。

§16  与 trace/cosim 的组合验证
-------------------------------

Halt/Run agent 本身不进入 cosim scoreboard 的 TLM FIFO，但它改变 DUT debug/halt 状态，
进而影响 trace/probe item。scoreboard 在 step 前通知 Spike debug request 和 debug
priority，因此 halt/run stimulus 的最终验证闭环在 trace/cosim 路径中完成。

.. code-block:: text

   Halt/Run driver
      |
      v
   DUT mpc/cpu halt-run pins
      |
      +--> ack/status --> halt_run_monitor log
      |
      +--> debug/halt state in TLU/probe
              |
              v
        trace/probe item
              |
              v
        cosim scoreboard -> Spike debug priority compare

.. list-table:: 组合验证观察点
   :header-rows: 1
   :widths: 26 34 40

   * - 观察点
     - 位置
     - 意义
   * - ``o_cpu_halt_ack``
     - ``eh2_halt_run_intf``
     - DUT 已接受 halt 请求
   * - ``o_cpu_run_ack``
     - ``eh2_halt_run_intf``
     - DUT 已接受 run 请求
   * - ``o_cpu_halt_status``
     - ``eh2_halt_run_intf``
     - CPU 当前处于 halt 状态
   * - debug mode
     - DUT probe / trace item
     - Spike debug priority compare 的输入
   * - retire 停止/恢复
     - trace monitor
     - halt/run 对流水线的实际影响

§17  负向场景与限制
-------------------

当前 Halt/Run driver 没有实现复杂的随机 back-to-back request、ack timeout error 或
多线程 per-hart halt 控制。文档中应如实描述这些边界，避免把它写成完整 debug
subsystem verifier。

.. list-table:: 当前边界
   :header-rows: 1
   :widths: 28 36 36

   * - 边界
     - 当前行为
     - 后续扩展
   * - Ack timeout
     - 最多等待 100 cycle 后继续
     - 增加 sequence-level check 或 driver error
   * - 多线程 halt
     - TB top 回灌 thread 0 ack/status
     - 扩展 per-thread interface 或数组化 status
   * - Back-to-back request
     - 由 sequence 控制 delay
     - 增加 protocol sequence 和 coverage
   * - Reset in flight
     - 依赖 phase/reset 清理默认状态
     - 补 reset-aware directed
   * - DMI/JTAG 组合
     - 与 JTAG agent 分离
     - 增加 coordinated virtual sequence

§18  调试命令
-------------

Halt/Run 相关问题通常需要波形。推荐先用 VCS smoke 确认平台可运行，再用单测波形看
pin-level 请求和 ack。

.. code-block:: bash

   make smoke SIMULATOR=vcs
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make smoke SIMULATOR=nc WAVES=1

波形建议加入：

.. code-block:: text

   halt_run_vif.mpc_debug_halt_req
   halt_run_vif.mpc_debug_run_req
   halt_run_vif.mpc_reset_run_req
   halt_run_vif.i_cpu_halt_req
   halt_run_vif.i_cpu_run_req
   halt_run_vif.o_cpu_halt_ack
   halt_run_vif.o_cpu_run_ack
   halt_run_vif.o_cpu_halt_status
   dut_probe_intf.debug_mode

§19  维护建议
-------------

后续若增强 Halt/Run agent，建议优先补三个能力：ack timeout 显式报错、monitor 通过
analysis port 发布状态 item、per-thread ack/status 支持。这样可以把 halt/run 从
“主动 stimulus + log”提升为完整可观测 agent，并让 coverage 和 scoreboard 更容易
消费 debug/halt 状态。
