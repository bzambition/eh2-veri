.. _agent_axi4:
.. _05_verification_arch/agent_axi4:

AXI4 Agent — 架构参考
=====================

:status: draft
:source: dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
----------------

读懂本章前，你需要先知道：

* :doc:`/03_integration/soc_integration` — EH2 对外通过 IFU、LSU 和 system bus 等端口
  访问外部 memory/peripheral。
* :doc:`/05_verification_arch/env` — env 创建 ``lsu_agent``、``ifu_agent`` 和
  ``sb_agent``，并决定它们是 passive 监视还是 active 驱动。
* :doc:`/05_verification_arch/agent_cosim` — LSU AXI4 monitor 的事务会送入 cosim
  scoreboard，用于 store/AMO memory notify。
* AXI4 基本握手：``VALID`` 与 ``READY`` 同周期为 1 才算一次 beat；``AW``/``W``/``B``
  是写通道，``AR``/``R`` 是读通道。
* 基础 UVM：``uvm_sequence_item`` 表示一笔 transaction，monitor 通过
  ``uvm_analysis_port`` 发布观测结果。

如果你只熟悉 C 语言，可以先把 AXI4 理解成"五条带握手的结构体通道"：地址通道告诉
对方要访问哪里，数据通道携带 payload，response 通道告诉访问是否成功。本章的重点
不是完整 AXI4 规范，而是 EH2 平台如何把总线拍级信号整理成可被 scoreboard、coverage
和 debug 日志消费的 transaction。

学完本章你应该能够：

1. 区分 ``axi4_agent`` 在 passive 模式和 active 模式下分别创建哪些子组件。
2. 在 ``axi4_monitor.sv`` 中找到写事务与读事务的采样任务，并解释它们如何等待
   ``VALID && READY``。
3. 说明 ``axi4_seq_item`` 中 address、data、strb、id、resp 字段如何对应 AXI4
   通道信号。
4. 知道 ``lsu_agent.ap`` 为什么要连接到 ``cosim_agent.dmem_port``，以及 IFU/SB 端口
   为什么不走同一条 memory notify 路径。
5. 当日志出现 AXI4 timeout、store data mismatch 或 write strobe 异常时，能先定位
   ``build/*/sim_*.log``、``axi4_monitor`` 打印和 scoreboard 的 dmem 统计。

§1  本章边界
------------

本章解释 AXI4 agent 在验证架构中的角色。逐类源码字典见
:ref:`appendix_b_uvm_axi4_agent`；这里聚焦 env 如何使用 AXI4 agent、monitor 如何
形成 transaction、driver 何时参与 error injection。

AXI4 agent 目录包含 6 个源文件：

* :file:`axi4_agent_pkg.sv`
* :file:`axi4_agent.sv`
* :file:`axi4_driver.sv`
* :file:`axi4_monitor.sv`
* :file:`axi4_seq_item.sv`
* :file:`axi4_sequencer.sv`

§2  Agent 组件结构
------------------

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv:L17-L27``）：

.. code-block:: systemverilog

   class axi4_agent #(int ID_WIDTH = 4) extends uvm_agent;
   
     `uvm_component_param_utils(axi4_agent#(ID_WIDTH))
   
     // Components
     axi4_driver#(ID_WIDTH) driver;
     axi4_monitor#(ID_WIDTH) monitor;
     axi4_sequencer sequencer;
   
     // Analysis port (from monitor)
     uvm_analysis_port #(axi4_seq_item) ap;

逐段解释：

* 第 17 行：``axi4_agent`` 是带 ``ID_WIDTH`` 参数的 ``uvm_agent``，用于复用到 LSU、
  IFU、SB 等不同 AXI4 ID 宽度端口。
* 第 22~24 行：agent 包含 driver、monitor 和 sequencer 三类子组件。
* 第 27 行：agent 对外暴露 ``ap`` analysis port，实际由 monitor 的 ``ap`` 提供。

接口关系：

* 被调用：``core_eh2_env`` 创建 ``lsu_agent``、``ifu_agent`` 和 ``sb_agent``。
* 调用：``axi4_monitor``、``axi4_driver``、``axi4_sequencer``。
* 共享状态：``is_active`` 决定 driver/sequencer 是否创建。

§3  Passive / Active 行为
-------------------------

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv:L36-L59``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
   
     // Always create monitor
     monitor = axi4_monitor#(ID_WIDTH)::type_id::create("monitor", this);
   
     // Create driver and sequencer only if active
     if (get_is_active() == UVM_ACTIVE) begin
       driver    = axi4_driver#(ID_WIDTH)::type_id::create("driver", this);
       sequencer = axi4_sequencer::type_id::create("sequencer", this);
     end
   endfunction
   
   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
   
     // Connect monitor analysis port
     ap = monitor.ap;
   
     // Connect driver to sequencer (if active)
     if (get_is_active() == UVM_ACTIVE) begin
       driver.seq_item_port.connect(sequencer.seq_item_export);
     end
   endfunction

逐段解释：

* 第 39~40 行：monitor 永远创建，因此 passive agent 仍能采集 AXI4 transaction。
* 第 43~46 行：只有 ``get_is_active() == UVM_ACTIVE`` 时才创建 driver 和 sequencer。
* 第 52~53 行：agent 的 analysis port 指向 monitor 的 analysis port。
* 第 56~58 行：active 模式下 driver 连接 sequencer；passive 模式不建立这条连接。

接口关系：

* 被调用：UVM ``build_phase`` 和 ``connect_phase``。
* 调用：UVM factory 和 TLM seq item port/export connect。
* 共享状态：``is_active``、monitor analysis port、driver/sequencer 句柄。

§4  Monitor 双线程
------------------

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L45-L51``）：

.. code-block:: systemverilog

   task run_phase(uvm_phase phase);
     if (vif == null) return;  // No interface - skip monitoring
     fork
       monitor_writes();
       monitor_reads();
     join
   endtask

逐段解释：

* 第 46 行：如果 virtual interface 未配置，monitor 直接返回，不采集 transaction。
* 第 47~50 行：write channel 与 read channel 分成两个并行 task。
* ``monitor_writes`` 采集 AW/W，并在地址和数据完成后发布 transaction；源码中注释说明
  EH2 store 可能在 B response 对 monitor 可见之前 retire，因此不阻塞等待 B。
* ``monitor_reads`` 采集 AR/R，把所有 R beat 收齐后发布 transaction。

接口关系：

* 被调用：UVM ``run_phase``。
* 调用：``monitor_writes``、``monitor_reads``。
* 共享状态：``vif``、``ap`` 和 ``axi4_seq_item`` transaction。

§5  Write transaction 发布时间
-------------------------------

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L89-L117``）：

.. code-block:: systemverilog

   // Collect W channel data beats
   for (int i = 0; i < beat_count; i++) begin
     // AW and W are independent AXI channels and EH2 can handshake both on
     // the same clock. If W is already valid on the AW sample edge, consume
     // it immediately instead of waiting for a later edge and losing the
     // beat.
     if (!(vif.wvalid && vif.wready)) begin
       @(posedge vif.clk iff (vif.wvalid && vif.wready));
     end
     txn.data[i] = vif.wdata;
     txn.strb[i] = vif.wstrb;
   end
   
   txn.resp = new[1];
   txn.resp[0] = axi4_seq_item::AXI4_RESP_OKAY;
   txn.end_time = $time;
   
   // Send to analysis port as soon as address and data are complete. EH2
   // may retire the store before the write response handshake is visible to
   // the monitor; waiting for B can starve the cosim scoreboard.
   `uvm_info(agent_name, $sformatf("Write txn: %s", txn.convert2string()), UVM_HIGH)
   ap.write(txn);

逐段解释：

* 第 90~100 行：monitor 逐 beat 采集 W channel data 和 strobe。若 AW 采样边沿上 W
  已 valid/ready，则立即消费当前 beat，避免等下一拍导致丢 beat。
* 第 102~104 行：在 B response 可见前先给 transaction 一个 OKAY 默认 response 和
  end time。
* 第 106~110 行：transaction 在 address 和 data 完成后立即通过 ``ap.write`` 发布。
  这条行为直接服务 cosim scoreboard：store 可能已经 retire，scoreboard 需要 memory
  access 信息继续 Spike step。

接口关系：

* 被调用：``monitor_writes``。
* 调用：``ap.write``。
* 共享状态：``txn.data``、``txn.strb``、``txn.resp``、``txn.end_time``。

§6  Active 模式 error injection
-------------------------------

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L64-L85``）：

.. code-block:: systemverilog

   task run_phase(uvm_phase phase);
     // Ensure sideband signals are inactive at start
     vif.error_inject_mode <= 1'b0;
     vif.force_bresp       <= 2'b00;
     vif.force_rresp       <= 2'b00;
   
     if (!enable_error_inject) begin
       // Passive mode - error injection disabled; slave_mem handles everything.
       `uvm_info(agent_name, "Running in PASSIVE mode (no error injection)", UVM_LOW)
       forever begin
         @(posedge vif.clk);
       end
     end else begin
       // Active mode - monitor AXI handshakes, inject errors probabilistically.
       `uvm_info(agent_name, $sformatf(
         "Running in ACTIVE mode: error_pct=%0d%%", error_pct), UVM_LOW)
       fork
         inject_read_errors();
         inject_write_errors();
       join
     end
   endtask

逐段解释：

* 第 66~68 行：driver 启动时清零 error injection sideband。
* 第 70~75 行：未启用 error injection 时，driver 不替代 memory model，只保持时钟等待。
* 第 77~83 行：启用 error injection 时，driver 并行监控 read 和 write handshake，
  按 ``error_pct`` 注入 read/write response error。

接口关系：

* 被调用：active AXI4 agent 的 driver ``run_phase``。
* 调用：``inject_read_errors``、``inject_write_errors``。
* 共享状态：``vif.error_inject_mode``、``vif.force_bresp``、``vif.force_rresp``、
  ``enable_error_inject``、``error_pct``。

§7  Transaction 字段
--------------------

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv:L38-L56``）：

.. code-block:: systemverilog

   // Transaction fields
   rand tx_type_e    tx_type;
   rand bit [31:0]   addr;
   rand bit [3:0]    id;
   rand bit [7:0]    len;      // Burst length (0-255)
   rand bit [2:0]    size;     // Beat size (0=1B, 1=2B, 2=4B, 3=8B)
   rand burst_type_e burst;
   
   // Write data (for write transactions)
   rand bit [63:0]   data[];
   rand bit [7:0]    strb[];
   
   // Response data (for read transactions)
   bit [63:0]        rdata[];
   resp_type_e       resp[];
   
   // Metadata
   time              start_time;
   time              end_time;

逐段解释：

* 第 39~44 行：transaction 记录读写类型、地址、ID、burst length、beat size 和 burst
  type。
* 第 47~48 行：write transaction 保存每个 beat 的 data 和 strobe。
* 第 51~52 行：read transaction 保存每个 R beat 的 data 和 response。
* 第 55~56 行：start/end time 用于日志和调试。

接口关系：

* 被调用：monitor 创建 transaction，driver/sequencer 可使用同一 item 类型。
* 调用：UVM field automation、``convert2string``。
* 共享状态：cosim scoreboard 和 coverage 消费这些 transaction 字段。

§8  参考资料
------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`

关联章节：

* :ref:`appendix_b_uvm_axi4_agent`
* :ref:`env`
* :ref:`cosim_scoreboard`

§9  三端口 AXI4 agent 拓扑
--------------------------

EH2 UVM 环境中有三组 AXI4 agent：``lsu_agent``、``ifu_agent`` 和 ``sb_agent``。
它们使用同一个参数化 ``axi4_agent#(ID_WIDTH)`` 类，但 ID width 来自不同 DUT
tag 参数。默认情况下三者都是 passive monitor；只有 ``cfg.enable_axi4_error_inject``
置位时，``lsu_agent`` 会切换成 active，让 driver 通过 sideband 注入 SLVERR/DECERR。

.. code-block:: text

   core_eh2_tb_top
      |
      +-- lsu_axi_intf ---- lsu_agent.monitor ----+
      +-- ifu_axi_intf ---- ifu_agent.monitor ----+--> env analysis consumers
      +-- sb_axi_intf  ---- sb_agent.monitor  ----+
                                         |
                                         +--> cosim_agt.dmem_port (LSU only)

.. list-table:: AXI4 agent 使用矩阵
   :header-rows: 1
   :widths: 18 20 18 44

   * - Agent
     - DUT 端口
     - 默认模式
     - 当前用途
   * - ``lsu_agent``
     - LSU AXI4
     - ``UVM_PASSIVE``
     - 采集 load/store/AMO 事务；cosim scoreboard 用于 d-side access notification
   * - ``ifu_agent``
     - IFU AXI4
     - ``UVM_PASSIVE``
     - 采集取指总线活动；当前不进入 cosim d-side FIFO
   * - ``sb_agent``
     - debug system bus AXI4
     - ``UVM_PASSIVE``
     - 观察 debug system-bus 访问，服务 debug directed 和波形排查
   * - ``lsu_agent.driver``
     - LSU AXI4 response sideband
     - 条件 ``UVM_ACTIVE``
     - 只做 error injection，不替代 memory model

关键代码（env 中 active/passive 配置）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/env/core_eh2_env.sv
   :language: systemverilog
   :lines: 64-84
   :caption: dv/uvm/core_eh2/env/core_eh2_env.sv:64-84

逐段解释：

* LSU agent 根据 ``cfg.enable_axi4_error_inject`` 选择 active/passive。
* IFU 和 SB agent 在当前 env 中固定 passive。
* 这个策略把常规 memory response 留给 TB 的 ``axi4_slave_mem``，只在需要负向测试时
  让 driver 接管 response error sideband。

§10  Monitor 事务边界
---------------------

AXI4 monitor 把 channel-level handshake 组装成 ``axi4_seq_item``。write 线程按
AW → W beats 组包，并在地址和数据完成后立即发布 transaction；read 线程按
AR → R beats 组包。write 事务不等待 B channel 才发布，这是 EH2 cosim 的关键设计：
store 可能先退休，scoreboard 若等待 B response，容易在 store buffer 或 reset 边界卡住。

关键代码（monitor write/read 线程）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv
   :language: systemverilog
   :lines: 38-150
   :caption: dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:38-150

.. list-table:: ``axi4_seq_item`` 字段语义
   :header-rows: 1
   :widths: 22 24 54

   * - 字段
     - 来源
     - 消费方式
   * - ``tx_type``
     - AW/AR 线程
     - scoreboard 区分 read/write，write 进入 store/AMO notification
   * - ``addr``
     - ``awaddr`` / ``araddr``
     - 用于 d-side access 地址，64-bit beat 会拆成两个 32-bit notification
   * - ``len`` / ``size``
     - AXI burst metadata
     - 计算 beat 数和每 beat 字节数
   * - ``data[]`` / ``strb[]``
     - W channel
     - store/AMO 写数据与 byte enable
   * - ``rdata[]`` / ``resp[]``
     - R/B response
     - load data 和 access error 观察
   * - ``start_time`` / ``end_time``
     - monitor 采样时刻
     - debug log、波形定位

§11  Error injection 模式
-------------------------

AXI4 driver 的名字容易误导：它不是一个完整 AXI4 slave driver。当前实现基于 Ibex
``ibex_mem_intf_response_driver`` 的思路，只通过 ``error_inject_mode``、
``force_bresp`` 和 ``force_rresp`` sideband 影响行为级 memory model 的 response。
地址、数据、burst 和 memory array 仍由 TB memory model 处理。

关键代码（driver 运行模式和注入线程）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv
   :language: systemverilog
   :lines: 64-146
   :caption: dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:64-146

.. warning::

   不要把 ``lsu_agent`` active mode 理解成“UVM 接管 AXI4 slave”。它只覆盖 response
   error；若需要验证 wait-state、outstanding transaction 或乱序 response，应该扩展
   memory model 或新增 agent 功能，而不是在现有 driver 中隐式改变语义。

§12  与 Ibex 工业实现对照
-------------------------

Ibex 使用 ``ibex_mem_intf_response_agent`` 处理 data/instr memory response，并把
monitor item 送入 cosim dmem/imem path。EH2 使用 AXI4 agent，是因为 VeeR EH2 wrapper
对外暴露 AXI4 LSU/IFU/SB 总线，且 store/AMO cosim 需要观察真实 AXI4 byte strobe。
两者一致的工程原则是：memory agent 默认服务于协议观察和 response 控制，不在 scoreboard
里重建总线协议。

.. list-table:: AXI4 vs Ibex memory agent
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - 源码路径
     - ``/home/host/ibex/dv/uvm/core_ibex/common/ibex_mem_intf_agent``
     - ``dv/uvm/core_eh2/common/axi4_agent``
   * - 协议
     - Ibex core memory interface
     - AXI4 AW/W/B/AR/R 五通道
   * - cosim 数据
     - dmem/imem monitor item
     - LSU AXI4 transaction，拆成 Spike d-side notification
   * - error injection
     - response driver pattern
     - sideband ``force_bresp`` / ``force_rresp`` pattern
   * - EH2 差异
     - 单核 Ibex memory surface 较窄
     - EH2 需要 LSU、IFU、debug system-bus 三组 agent 和不同 ID width

§13  Sign-off 关联
------------------

AXI4 agent 影响 ``directed``、``riscvdv`` 和 ``cosim`` stage。当前 2026-05-19 demo
中 directed 为 40/40，riscv-dv 为 370/395，LEC 为 31635/31635 PASS。AXI4 monitor
的 transaction 发布时序直接影响 cosim 是否能在 store/AMO 前拿到 d-side access，因此
本页中 “AW+W 后立即发布 write txn” 是 sign-off 相关行为，不是日志优化。

.. tip::

   若 cosim 在 store 指令处等待，先看 ``lsu_agent.monitor`` 是否已发布 write txn，
   再看 ``eh2_cosim_scoreboard.pending_mem_access_q``。如果 AW/W 已完成但 scoreboard
   没收到，多半是 env connect phase 或 TLM FIFO 连接问题；如果 scoreboard 收到但仍等待，
   再看 store coalescing 计数和 byte strobe 拆分逻辑。

§14  协议采样细节
-----------------

AXI4 monitor 的工程目标不是实现完整协议 checker，而是把 DUT 对外可见的 AXI4
handshake 转换成稳定的 ``axi4_seq_item``。因此它关心 transaction 边界、beat 数、
byte strobe 和 response，而不在本类中维护 reorder buffer 或 outstanding scoreboard。
EH2 当前外部 memory model 的行为较规整，这个简化可以满足 cosim 和 coverage 需求。

.. list-table:: 采样点与 transaction 字段
   :header-rows: 1
   :widths: 24 28 48

   * - AXI4 信号
     - 采样条件
     - 写入字段
   * - ``awvalid && awready``
     - write address handshake
     - ``tx_type=AXI4_WRITE``、``addr``、``id``、``len``、``size``、``burst``
   * - ``wvalid && wready``
     - write data beat handshake
     - ``data[i]``、``strb[i]``
   * - ``bvalid && bready``
     - write response handshake
     - 当前 write txn 可提前发布，B response 主要用于日志/扩展
   * - ``arvalid && arready``
     - read address handshake
     - ``tx_type=AXI4_READ``、``addr``、``id``、``len``、``size``、``burst``
   * - ``rvalid && rready``
     - read data beat handshake
     - ``rdata[i]``、``resp[i]``，收满 beat 后发布

.. note::

   write channel 提前发布是 EH2 cosim 的显式设计，不是协议遗漏。store retirement
   与 B response 可见时序之间存在差异，scoreboard 需要在 Spike step 前知道地址、
   数据和 byte enable；等待 B channel 会把一个真实 store 误判成 memory access 缺失。

§15  64-bit AXI4 到 32-bit ISS 语义
-----------------------------------

EH2 外部 AXI4 data beat 是 64-bit，而 Spike d-side notify 使用 32-bit 数据片段表达。
scoreboard 在 ``notify_memory_access`` 中按 ``strb[3:0]`` 和 ``strb[7:4]`` 拆成最多
两次 32-bit notify。AXI4 agent 必须完整保留 64-bit ``data`` 和 8-bit ``strb``，否则
store byte enable 会在 cosim 层丢失。

.. code-block:: text

   AXI beat:
      addr = A
      data = {upper32, lower32}
      strb = {upper_be[3:0], lower_be[3:0]}

   Spike notify:
      if lower_be != 0: notify(addr=A,   data=lower32, be=lower_be)
      if upper_be != 0: notify(addr=A+4, data=upper32, be=upper_be)

.. list-table:: Byte strobe 对 cosim 的影响
   :header-rows: 1
   :widths: 22 30 48

   * - Store 类型
     - 典型 strobe
     - 关注点
   * - byte store
     - ``0000_0001`` 或 lane-shift 后单 bit
     - 地址低位和 strobe 必须一致，否则 Spike 写错 byte
   * - half store
     - 两个相邻 bit
     - misaligned 或跨 32-bit lane 时需要两段 notify
   * - word store
     - ``0000_1111`` 或 ``1111_0000``
     - 低/高 32-bit lane 选择必须正确
   * - doubleword-like burst beat
     - ``1111_1111``
     - 拆成低/高两次 32-bit notify
   * - masked AMO/store
     - 非连续或特殊 strobe
     - 需要结合 AMO/scatter 场景看 scoreboard 支持边界

§16  Reset、flush 与 monitor 鲁棒性
-----------------------------------

AXI4 monitor 是纯运行期采样组件。reset 期间如果 DUT 或 memory model 仍有半截
transaction，monitor 不应把 reset 前后的 beat 拼成一个 item。当前实现主要依赖
ready/valid handshake 的事务完整性；如果后续引入 wait-state、error injection 或
reset-in-flight 测试，需要补强 reset-aware queue flush。

.. list-table:: AXI4 monitor 风险点
   :header-rows: 1
   :widths: 26 34 40

   * - 风险点
     - 触发场景
     - 建议处理
   * - AW 已采样、W 未采样
     - reset 或 memory backpressure
     - reset phase 清理 write 临时 item
   * - AR 已采样、R 未收满
     - read burst 被 reset 打断
     - reset 后丢弃 partial read transaction
   * - B response 延迟
     - store buffer 或 memory response 慢
     - 保持当前 AW+W 后发布策略，B 仅作为扩展信息
   * - 多 outstanding transaction
     - 后续扩展乱序 memory model
     - 按 ID 建立 outstanding map，而不是单一临时 item
   * - error injection 与 normal response 竞争
     - driver sideband 与 memory model 同周期更新
     - 明确 sideband 生效时序并增加 directed 覆盖

§17  Debug 检查命令
-------------------

AXI4 agent 问题通常需要同时看 UVM log 和波形。文档侧推荐的最小命令如下：

.. code-block:: bash

   make smoke SIMULATOR=vcs
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make smoke SIMULATOR=nc WAVES=1

预期检查点：

.. code-block:: text

   UVM_INFO ... lsu_agent.monitor ... Write txn
   mailbox write addr=0xD0580000 data=0x000000ff
   cosim MEM WR: addr=<store address> data=<store data> be=<byte enable>

若 VCS 回归 PASS 但单个 store cosim hang，优先打开 NC 或 VCS 波形查看 AW/W 是否在同一拍
handshake。EH2 monitor 已显式处理 AW 和 W 同拍完成的情况；如果波形显示同拍握手但
transaction 未发布，应该检查 monitor 中对当前采样边沿的消费逻辑，而不是修改
scoreboard 等待超时。

§18  覆盖率与可观测性
---------------------

AXI4 agent 本身没有大量 covergroup；它对覆盖率的贡献主要是间接的。LSU external
load/store、AMO、misaligned、access error、mailbox 和 debug system-bus 访问都需要
AXI4 transaction 正确完成，才能在 functional coverage、trace/cosim 和 directed
自检中呈现为有效场景。

.. list-table:: AXI4 transaction 到 coverage/sign-off 的映射
   :header-rows: 1
   :widths: 28 32 40

   * - AXI4 场景
     - 主要消费者
     - 对 sign-off 的意义
   * - IFU read
     - ICache/IFU coverage、程序执行
     - smoke 和 riscv-dv 能否启动
   * - LSU load
     - trace/cosim、LSU coverage
     - load data 与 Spike 状态一致
   * - LSU store
     - mailbox、cosim d-side notify
     - 测试结束条件和 memory side effect 正确
   * - AMO write-like access
     - cosim scoreboard
     - atomic extension 行为可比对
   * - SB access
     - debug directed、JTAG/DMI 路径
     - debug system-bus 行为可观察
   * - Response error
     - exception/interrupt coverage
     - access fault 和 trap path 被触发

§19  后续扩展建议
-----------------

如果后续需要把 AXI4 agent 从“采样 + response error sideband”扩展为更完整的协议验证组件，
建议按以下顺序推进：

1. 先增加 reset-aware partial transaction flush，保证 reset-in-flight 不污染 FIFO。
2. 再增加 lightweight protocol assertion 或 bind，覆盖 ready/valid 稳定性、last beat
   和 burst length。
3. 然后按 ID 建立 outstanding transaction map，支持多 outstanding 和乱序 response。
4. 最后再考虑完整 UVM slave driver；在此之前不要让 driver 隐式替代 TB memory model。

这些扩展都应保持与 Ibex 方法论一致：agent 负责协议面，scoreboard 负责 architectural
compare，coverage/report 负责质量度量，三者边界清晰。

§20  ``axi4_seq_item`` 约束与 helper
------------------------------------

``axi4_seq_item`` 是 monitor、driver、sequencer 和 scoreboard 共享的 transaction 类型。
它把 AXI4 burst metadata 与 data/response array 放在同一个对象中，并提供 beat/byte
计算 helper。scoreboard 后续 ``notify_memory_access`` 依赖这些 helper 判断 beat 数和
每 beat 字节数。

关键代码（``axi4_seq_item`` helper）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv
   :language: systemverilog
   :lines: 74-103
   :caption: dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv:74-103

.. list-table:: ``axi4_seq_item`` helper 语义
   :header-rows: 1
   :widths: 24 30 46

   * - Helper / constraint
     - 语义
     - 消费方
   * - ``c_reasonable_len``
     - 随机 burst 最多 16 beats
     - 后续 active sequence 或 error-injection 扩展
   * - ``c_valid_size``
     - beat size 不超过 8 bytes
     - 匹配当前 64-bit AXI4 data width
   * - ``get_beat_count``
     - ``len + 1``
     - monitor array 分配、scoreboard notify loop
   * - ``get_beat_bytes``
     - ``1 << size``
     - 计算 lane、address stride
   * - ``get_total_bytes``
     - beat count × beat bytes
     - burst 边界检查和后续 coverage 扩展
   * - ``convert2string``
     - transaction 摘要
     - UVM log/debug

§21  Error injection 统计
-------------------------

AXI4 driver 保留 read/write total 与 error 计数，并在 report phase 输出。这些统计不是
coverage gate，但对负向测试很有用：如果 test 期望注入 error，而 report 中
``num_read_errors`` 和 ``num_write_errors`` 都为 0，说明要么 agent 没进入 active，
要么握手没有发生，要么 ``error_pct`` 太低。

关键代码（driver report 和随机 error）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv
   :language: systemverilog
   :lines: 155-183
   :caption: dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:155-183

.. list-table:: Error injection 调试检查
   :header-rows: 1
   :widths: 26 34 40

   * - 检查项
     - 预期
     - 异常含义
   * - ``enable_axi4_error_inject``
     - LSU agent 被设置为 ``UVM_ACTIVE``
     - driver/sequencer 未创建或不运行
   * - ``enable_error_inject``
     - driver run phase 进入 active branch
     - sideband 永远保持 OKAY
   * - ``error_pct``
     - 0-100 的概率
     - 太低时短测试可能没有注入
   * - ``num_read_total`` / ``num_write_total``
     - 至少有目标方向 transaction
     - stimulus 未触发对应 AXI4 channel
   * - ``force_rresp`` / ``force_bresp``
     - 注入期间为 SLVERR/DECERR
     - memory model 未看到 sideband

§22  AXI4 agent 与 DMI/SB debug
-------------------------------

SB AXI4 agent 当前默认 passive，主要观察 debug system-bus 访问。JTAG agent 负责 TAP/DMI
transaction，SB AXI4 agent 负责 DMI 触发后 DUT 对 system bus 的 AXI4 行为。二者不要
混淆：JTAG transaction 正确不代表 SB AXI4 访问一定发生，SB AXI4 访问正确也不能替代
DMI scan chain 检查。

.. code-block:: text

   JTAG driver
      |
      v
   TAP / DMI
      |
      v
   DUT debug module
      |
      v
   SB AXI4 master ----> sb_axi_intf ----> sb_agent.monitor

.. list-table:: Debug 相关分工
   :header-rows: 1
   :widths: 26 34 40

   * - 组件
     - 观察/驱动对象
     - Debug 验证意义
   * - JTAG agent
     - TCK/TMS/TDI/TDO/TRST
     - JTAG/DMI 协议和 debug command 输入
   * - Halt/Run agent
     - MPC/CPU halt-run pins
     - pin-level halt/run stimulus
   * - SB AXI4 agent
     - debug system-bus AXI4
     - debug module 发出的 system-bus memory access
   * - Trace/probe monitor
     - debug mode、retire、trap
     - debug entry/exit 的 architectural 结果

§23  与 ``cover.cfg`` 的边界
----------------------------

AXI4 agent 是 UVM/TB 组件，不应进入 DUT-only coverage scope。当前 ``cover.cfg`` 把
coverage 限定到 ``core_eh2_tb_top.dut``，因此 agent class、interface helper 和 memory
model 的代码覆盖率不会抬高 release line/branch 数字。AXI4 agent 对覆盖率的影响来自
它驱动或观察 DUT 走到目标路径，而不是 agent 自身被统计。

.. code-block:: text

   VCS coverage scope:
      +tree core_eh2_tb_top.dut

   Not included:
      axi4_agent.sv
      axi4_monitor.sv
      axi4_driver.sv
      UVM scoreboard classes

   Indirectly affected:
      LSU/IFU/SB RTL line/branch
      load/store/AMO covergroup bins
      access error / exception paths

§24  典型失败时间线
-------------------

AXI4 相关失败可按时间线定位：

.. list-table:: AXI4 失败时间线
   :header-rows: 1
   :widths: 20 34 46

   * - 时间点
     - 观察
     - 说明
   * - build phase
     - monitor warning 或 driver fatal
     - virtual interface 未配置或类型不匹配
   * - reset 后取指
     - IFU AR/R 无活动
     - binary 未加载、reset vector 错或 IFU 被 stall
   * - mailbox 前
     - LSU AW/W 无活动
     - 程序未执行到 store 或 LSU/memory handshake 卡住
   * - cosim store
     - monitor 有 txn，scoreboard 等待
     - TLM connect、memory queue 或匹配逻辑问题
   * - access error
     - response error 未触发 trap
     - sideband 时序或 RTL exception path 问题
   * - report phase
     - error injection count 为 0
     - active 配置、概率或 stimulus 不充分

§25  最小源码审查清单
---------------------

修改 AXI4 agent 时，代码审查至少覆盖以下问题：

* monitor 是否仍在 AW+W 完成后发布 write txn。
* read transaction 是否收满所有 R beat 后再发布。
* ``axi4_seq_item`` 是否完整保存 64-bit data 和 8-bit strobe。
* driver 是否仍只通过 sideband 注入 response error，不接管 memory array。
* env 中 LSU/IFU/SB active/passive 配置是否符合预期。
* ``lsu_agent.ap`` 是否仍连接到 ``cosim_agt.dmem_port``。
* Ibex 对照是否仍准确：方法论对齐，但协议表面不同。

这些检查能防止最常见的两类回归：一类是 cosim 因 store/AMO 事务未及时发布而 hang，
另一类是 error injection 无意中改变了正常 memory model 行为。

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
