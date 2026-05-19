.. _agent_cosim:
.. _05_verification_arch/agent_cosim:

Cosim Agent — 架构参考
=======================

:status: draft
:source: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
----------------

读懂本章前，建议先确认你已经掌握以下内容：

* :doc:`/04_verification_overview/quickstart` — 已能跑通一次 ``make smoke``，知道
  ``build/smoke_vcs/`` 下的 ``sim_*.log`` 和 ``result.yaml`` 分别记录什么。
* :doc:`/05_verification_arch/tb_top` — 理解 ``core_eh2_tb_top`` 如何启动
  ``run_test()``、如何把虚接口（virtual interface）交给 UVM。
* :doc:`/05_verification_arch/env` — 知道 env 在 ``build_phase`` 创建 agent，并在
  ``connect_phase`` 连接 analysis port。
* :doc:`/05_verification_arch/agent_trace` — 知道 retire trace 与 DUT probe 是两条
  不同的数据流。
* 基础 UVM 1.2：``uvm_agent``、``uvm_analysis_port``、``uvm_tlm_analysis_fifo``、
  ``build_phase``、``connect_phase`` 和 ``run_phase``。

如果你还不熟悉 Spike DPI（DPI-C, direct programming interface）是什么，可以先把
本章当作"连线图"阅读：先看 ``eh2_cosim_agent`` 只负责封装和转发，再到
:doc:`/05_verification_arch/cosim_scoreboard` 学真正的逐指令 diff。

学完本章你应该能够：

1. 解释 cosim agent、trace monitor、DUT probe monitor、AXI4 monitor 和
   ``eh2_cosim_scoreboard`` 之间的连接关系。
2. 在 ``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv`` 中指出
   ``dmem_port.connect(scoreboard.lsu_axi_fifo.analysis_export)`` 为什么只连接 LSU
   AXI4，而不直接连接 trace/probe。
3. 说明 ``eh2_cosim_cfg`` 如何描述 EH2 的 memory map，以及这些 region 为什么必须在
   Spike 初始化前注册。
4. 跑 ``make smoke`` 后，在 ``build/smoke_vcs/smoke_s1/sim_*.log`` 中搜索
   ``cosim``，判断当前 smoke 是否真的启用了 Spike lock-step，还是走了
   ``+disable_cosim=1`` 的冒烟路径。
5. 当 cosim 启动失败、DPI symbol 找不到或 binary loader 报错时，知道先检查
   ``libcosim.so``、``+enable_cosim=1``、``+signature_addr`` 和 scoreboard 初始化日志。

§1  本章边界
------------

本章解释 ``eh2_cosim_agent`` 在验证架构中的位置：它不是指令比对算法本身，
而是把 env 层的 trace、DUT probe 和 LSU AXI4 三路数据汇入
``eh2_cosim_scoreboard`` 的 UVM agent wrapper。scoreboard 的逐函数源码字典见
:ref:`appendix_b_uvm_cosim_agent`，scoreboard 的数据流标杆说明见
:ref:`cosim_scoreboard`；本章只覆盖架构连接、生命周期和跨模块接口。

cosim agent 目录包含 6 个 SystemVerilog 源文件：

* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`

§2  Package 汇入顺序
--------------------

职责：``eh2_cosim_agent_pkg`` 建立 cosim agent 的编译可见性。它先导入 trace
agent 与 AXI4 agent，再 include 配置类、DPI 声明、scoreboard 和 wrapper。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv:L7-L24``）：

.. code-block:: systemverilog

   package eh2_cosim_agent_pkg;
   
     `include "uvm_macros.svh"
     import uvm_pkg::*;
     import eh2_trace_agent_pkg::*;
     import axi4_agent_pkg::*;
   
     // Configuration object
     `include "eh2_cosim_cfg.sv"
   
     // DPI declarations
     `include "cosim_dpi.svh"
   
     // Co-simulation scoreboard
     `include "eh2_cosim_scoreboard.sv"
   
     // Top-level agent
     `include "eh2_cosim_agent.sv"

逐段解释：

* 第 7 行：声明 ``eh2_cosim_agent_pkg``，后续 env 通过 package import 使用其中的类。
* 第 9~12 行：导入 UVM、trace agent 和 AXI4 agent。scoreboard 的 FIFO 类型直接使用
  ``eh2_trace_seq_item`` 与 ``axi4_seq_item``，因此这两个 package 是编译期依赖。
* 第 15~18 行：先 include ``eh2_cosim_cfg.sv`` 和 ``cosim_dpi.svh``。scoreboard
  build phase 使用 ``eh2_cosim_cfg``，运行期通过 DPI 调用 ``riscv_cosim_*``。
* 第 21~24 行：scoreboard 先于 ``eh2_cosim_agent.sv`` include，因为 wrapper
  内部声明 ``eh2_cosim_scoreboard scoreboard``。

接口关系：

* 被调用：:file:`dv/uvm/core_eh2/env/core_eh2_env_pkg.sv` import 本 package。
* 调用：SystemVerilog ``include`` 与 package import。
* 共享状态：无运行期共享状态；这里只建立类和 DPI 声明的可见性。

§3  Agent wrapper 的最小职责
----------------------------

职责：``eh2_cosim_agent`` 持有 scoreboard，并把外部 ``dmem_port`` 连接到
scoreboard 的 ``lsu_axi_fifo.analysis_export``。它不直接消费 trace 或 probe；
这两路在 env ``connect_phase`` 中直接连入 scoreboard。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv:L14-L39``）：

.. code-block:: systemverilog

   class eh2_cosim_agent extends uvm_agent;
   
     `uvm_component_utils(eh2_cosim_agent)
   
     // Co-simulation scoreboard
     eh2_cosim_scoreboard scoreboard;
   
     // External analysis exports for memory traffic
     // (connected by env to AXI4 agent monitors)
     uvm_analysis_export #(axi4_seq_item) dmem_port;
   
     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       scoreboard = eh2_cosim_scoreboard::type_id::create("scoreboard", this);
       dmem_port  = new("dmem_port", this);
     endfunction
   
     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       // Connect external memory port to scoreboard's LSU AXI FIFO
       dmem_port.connect(scoreboard.lsu_axi_fifo.analysis_export);
     endfunction

逐段解释：

* 第 14~19 行：wrapper 是 ``uvm_agent``，成员只有 scoreboard 和一个外部 memory
  analysis export。
* 第 23 行：``dmem_port`` 的 item 类型是 ``axi4_seq_item``，对应 LSU AXI4 monitor
  发出的 transaction。
* 第 29~33 行：build phase 创建 scoreboard 和 ``dmem_port``。scoreboard 的三个 FIFO
  在 scoreboard 自己的 build phase 中创建。
* 第 35~39 行：connect phase 只建立 LSU AXI4 路径：
  ``dmem_port -> scoreboard.lsu_axi_fifo.analysis_export``。

接口关系：

* 被调用：``core_eh2_env`` 在 ``cfg.enable_cosim`` 为真时创建 ``cosim_agt``。
* 调用：UVM factory、TLM analysis export connect。
* 共享状态：``scoreboard`` 句柄和 ``dmem_port``，没有独立时序线程。

§4  Env 层创建与配置注入
------------------------

职责：env 负责决定是否启用 cosim，并在创建 agent 前把 ``eh2_cosim_cfg`` 放入
scoreboard 的 config_db 路径。DCCM/ICCM base 和 size 可通过 plusarg 覆盖后同步到
``mem_region_t`` 字段。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L105-L123``）：

.. code-block:: systemverilog

   // Co-simulation agent (only if enabled)
   if (cfg.enable_cosim) begin
     // Create and inject cosim_cfg from config_db so the scoreboard receives
     // memory region mappings (issue 65).  Plusargs MEM_ICCM_BASE,
     // MEM_DCCM_BASE etc. override the defaults set in eh2_cosim_cfg.
     begin
       eh2_cosim_cfg cosim_cfg;
       cosim_cfg = eh2_cosim_cfg::type_id::create("cosim_cfg");
       // Read plusarg overrides for DCCM/ICCM base addresses
       void'($value$plusargs("MEM_ICCM_BASE=%h", cosim_cfg.iccm_base));
       void'($value$plusargs("MEM_ICCM_SIZE=%h", cosim_cfg.iccm_size));
       void'($value$plusargs("MEM_DCCM_BASE=%h", cosim_cfg.dccm_base));
       void'($value$plusargs("MEM_DCCM_SIZE=%h", cosim_cfg.dccm_size));
       // Sync flat fields into struct fields so scoreboard mem_region_t paths work
       cosim_cfg.sync_mem_regions();
       uvm_config_db#(eh2_cosim_cfg)::set(this, "cosim_agt.scoreboard", "cosim_cfg", cosim_cfg);
     end
     cosim_agt = eh2_cosim_agent::type_id::create("cosim_agt", this);
   end

逐段解释：

* 第 106 行：``cfg.enable_cosim`` 是 env 层的创建门控；关闭时不创建
  ``cosim_agt``。
* 第 111~112 行：env 创建 ``eh2_cosim_cfg`` 对象，而不是由 scoreboard 自行 new。
* 第 114~117 行：``MEM_ICCM_BASE``、``MEM_ICCM_SIZE``、``MEM_DCCM_BASE`` 和
  ``MEM_DCCM_SIZE`` plusarg 覆盖 flat 字段。
* 第 119~120 行：``sync_mem_regions`` 把 flat 字段同步到 ``mem_iccm`` 和
  ``mem_dccm``，随后 config_db 路径精确指向 ``cosim_agt.scoreboard``。
* 第 122 行：config_db 设置完成后才创建 agent，使 scoreboard build phase 能读取配置。

接口关系：

* 被调用：UVM build phase 调用 ``core_eh2_env.build_phase``。
* 调用：``eh2_cosim_cfg::type_id::create``、``sync_mem_regions``、
  ``uvm_config_db::set`` 和 ``eh2_cosim_agent::type_id::create``。
* 共享状态：``cfg.enable_cosim``、ICCM/DCCM plusarg、``cosim_cfg``。

§5  三路 analysis 数据流
------------------------

职责：env ``connect_phase`` 把 trace、DUT probe 和 LSU AXI4 三路 analysis 数据接入
cosim。trace 与 probe 直接连接 scoreboard FIFO；LSU AXI4 通过 wrapper 的
``dmem_port`` 再转接到 ``lsu_axi_fifo``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L164``）：

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

逐段解释：

* 第 152~154 行：trace monitor 的 ``ap`` 写入 ``trace_fifo``，trace item 是
  retire/trace pkt 的架构视图。
* 第 157~159 行：DUT probe monitor 的 ``ap`` 写入 ``dut_probe_fifo``，用于
  NB-load、DIV cancel 等异步写回提示。
* 第 162~164 行：LSU AXI4 monitor 的 ``ap`` 连接到 agent ``dmem_port``，再由
  wrapper 连接到 ``lsu_axi_fifo``。

接口关系：

* 被调用：UVM connect phase 调用 ``core_eh2_env.connect_phase``。
* 调用：TLM ``analysis_port.connect``。
* 共享状态：``cfg.enable_cosim``、``cosim_agt`` 句柄和三个 FIFO 的 analysis export。

三路数据在 cosim agent 边界上的流向如下：

.. code-block:: text

   eh2_trace_monitor.ap ---------------> scoreboard.trace_fifo
   eh2_dut_probe_monitor.ap -----------> scoreboard.dut_probe_fifo
   lsu_agent.ap --> cosim_agt.dmem_port -> scoreboard.lsu_axi_fifo
                                            |
                                            v
                                      Spike DPI step/notify

§6  Scoreboard 运行线程
-----------------------

职责：scoreboard 在 ``run_phase`` 初始化 Spike cosim handle，然后并行启动 trace、
probe、LSU AXI4 和 reset monitor 四个任务。这里的并行关系解释了为什么 agent
本身只负责连接：真正的时序仲裁发生在 scoreboard 内部。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L153-L163``）：

.. code-block:: systemverilog

   task run_phase(uvm_phase phase);
     if (enable_cosim) begin
       init_cosim();
       fork
         run_cosim_trace();
         run_cosim_probe_async();
         run_cosim_dmem();
         run_reset_monitor();
       join
     end
   endtask

逐段解释：

* 第 154 行：``enable_cosim`` 是 scoreboard 运行期门控，与 env 创建门控共同决定
  cosim 是否实际执行。
* 第 155 行：``init_cosim`` 创建或重建 Spike cosim handle，并注册 memory/CSR。
* 第 156~161 行：四个 task 并行运行。trace task 消费 retire item；probe task 消费
  async writeback hint；dmem task 消费 LSU AXI4 memory transaction；reset monitor
  观察 ``probe_vif.rst_n``。

接口关系：

* 被调用：UVM run phase。
* 调用：``init_cosim``、``run_cosim_trace``、``run_cosim_probe_async``、
  ``run_cosim_dmem``、``run_reset_monitor``。
* 共享状态：``cosim_handle``、``initialized``、三个 FIFO 和 pending queue。

时序关系如下：

.. code-block:: text

   run_phase
      |
      +-- init_cosim()
      |
      +-- fork
            |-- run_cosim_trace()        trace_fifo -> pending_trace_q[tid]
            |-- run_cosim_probe_async()  dut_probe_fifo -> async_wb_q[tid]
            |-- run_cosim_dmem()         lsu_axi_fifo -> pending_mem_access_q
            `-- run_reset_monitor()      rst_n edge -> flush/init

§7  Trace、probe 和 LSU 的门控关系
----------------------------------

职责：scoreboard 不在 trace item 到达时无条件 step Spike。它先把 trace item 放入
per-thread pending 队列，再按 memory 和 async writeback 条件决定是否可以调用
``compare_instruction``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L205-L224``）：

.. code-block:: systemverilog

   // Process trace items - each carries its own wb data from the RTL trace pkt.
   task run_cosim_trace();
     eh2_trace_seq_item trace_item;
   
     forever begin
       trace_fifo.get(trace_item);
       trace_item_count++;
   
       if (cosim_handle != null && initialized) begin
         pending_trace_t pending;
         int tid = int'(trace_item.thread_id);
         pending.item = trace_item;
         pending_trace_q[tid].push_back(pending);
         if (pending_trace_q[tid].size() > pending_trace_high_watermark) begin
           pending_trace_high_watermark = pending_trace_q[tid].size();
         end
         process_pending_trace(tid);
       end
     end
   endtask

逐段解释：

* 第 210~211 行：trace FIFO 是阻塞式消费；每个 item 到达后递增 ``trace_item_count``。
* 第 213 行：只有 ``cosim_handle`` 非空且 ``initialized`` 为真时才进入比对路径。
* 第 215~217 行：``thread_id`` 决定写入 ``pending_trace_q[tid]``，对应 NUM_THREADS
  场景下的 per-thread 队列。
* 第 218~221 行：更新 pending trace 高水位后调用 ``process_pending_trace``。

接口关系：

* 被调用：``run_phase`` fork 后长期运行。
* 调用：``trace_fifo.get``、``process_pending_trace``。
* 共享状态：``trace_item_count``、``pending_trace_q``、``pending_trace_high_watermark``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L226-L258``）：

.. code-block:: systemverilog

   // Async writeback hints (NB-load wb / DIV completion / DIV cancel).
   task run_cosim_probe_async();
     eh2_trace_seq_item probe_item;
     async_wb_hint_t hint;
   
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

逐段解释：

* 第 232~233 行：probe FIFO 同样阻塞式消费，并统计 ``probe_item_count``。
* 第 236 行：regular writeback 被丢弃，因为 trace pkt 已经携带普通写回信息。
* 第 238~242 行：NB-load、DIV 和 DIV cancel 等 async writeback 被转换成
  ``async_wb_hint_t``，其中 ``wb_tag`` 用于严格关联 pending trace item。

接口关系：

* 被调用：``run_phase`` fork 后长期运行。
* 调用：``dut_probe_fifo.get``，后续将 hint 推入 ``async_wb_q[tid]``。
* 共享状态：``probe_item_count``、``async_wb_q``、``wb_tag``。

§8  LSU AXI4 到 Spike memory notify
-----------------------------------

职责：LSU AXI4 transaction 先进入 ``pending_mem_access_q``。当 trace item 需要
对应 memory access 时，scoreboard 弹出匹配 transaction，并通过
``riscv_cosim_notify_dside_access`` 通知 Spike。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L260-L275``）：

.. code-block:: systemverilog

   // Monitor LSU AXI4 transactions for memory access notification
   task run_cosim_dmem();
     axi4_seq_item axi_txn;
   
     forever begin
       lsu_axi_fifo.get(axi_txn);
       axi_item_count++;
   
       if (cosim_handle != null && initialized) begin
         enqueue_memory_accesses(axi_txn);
         // Try to unblock both threads
         process_pending_trace(0);
         process_pending_trace(1);
       end
     end
   endtask

逐段解释：

* 第 265~266 行：``lsu_axi_fifo`` 接收来自 LSU AXI4 monitor 的 transaction，并统计
  ``axi_item_count``。
* 第 268~269 行：cosim 初始化完成后，transaction 被 ``enqueue_memory_accesses``
  放入 pending memory 队列。
* 第 270~272 行：LSU AXI4 是共享 memory bus；任意 AXI transaction 到达后同时尝试
  解锁 thread 0 和 thread 1 的 pending trace。

接口关系：

* 被调用：``run_phase`` fork 后长期运行。
* 调用：``lsu_axi_fifo.get``、``enqueue_memory_accesses``、``process_pending_trace``。
* 共享状态：``pending_mem_access_q``、``axi_item_count``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L506-L535``）：

.. code-block:: systemverilog

   // Notify Spike about a memory access from the AXI4 bus.
   // AXI4 bus is 64-bit; split 64-bit beats into two 32-bit notifications.
   function void notify_memory_access(int tid, axi4_seq_item txn);
     if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
       bit write_error = (txn.resp[0] != axi4_seq_item::AXI4_RESP_OKAY);
   
       for (int i = 0; i < txn.get_beat_count(); i++) begin
         bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
         bit [63:0] beat_data = txn.data[i];
         bit [7:0]  beat_strb = txn.strb[i];
         int beat_bytes = (1 << txn.size);
   
         if (beat_strb[3:0] != 4'b0) begin
           riscv_cosim_notify_dside_access(cosim_handle,
             1, int'(beat_data[31:0]), int'(beat_addr),
             int'({4'b0, beat_strb[3:0]}),
             int'(write_error), 0, 0, 0, 1, 0, tid);
           `uvm_info("cosim", $sformatf("T%0d MEM WR: addr=%08x data=%08x be=%04b",
             tid, beat_addr, beat_data[31:0], beat_strb[3:0]), UVM_HIGH)
         end

逐段解释：

* 第 506~508 行：函数边界说明 AXI4 bus 是 64-bit，而 Spike notify 以 32-bit
  数据片段表达。
* 第 509~516 行：write transaction 逐 beat 计算 address、data、strobe 和 beat size。
* 第 518~524 行：低 32-bit lane 的 strobe 非零时调用
  ``riscv_cosim_notify_dside_access``，并把 write 标志、data、address、byte enable、
  error 状态和 ``tid`` 传给 Spike。
* 高 32-bit lane 的处理在同一函数后续分支中完成，源码按 ``beat_bytes > 4`` 与
  ``beat_strb[7:4]`` 判断是否需要第二次 notify。

接口关系：

* 被调用：``pop_matching_memory_access``。
* 调用：``riscv_cosim_notify_dside_access``。
* 共享状态：``cosim_handle`` 和从 AXI4 monitor 捕获的 ``axi4_seq_item``。

§9  Reset 期间的状态清理与重建
-------------------------------

职责：testbench 把 ``eh2_dut_probe_if`` 提供给 cosim agent，用于 reset 监控。
reset 拉低时 scoreboard 清空 FIFO、pending queue 和计数；reset 释放后重新
初始化 Spike cosim model。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1116-L1120``）：

.. code-block:: systemverilog

   // Also provide DUT probe interface to trace monitor (for interrupt/debug state sampling)
   uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*trace_monitor*", "probe_vif", dut_probe_intf);
   
   // Provide DUT probe interface to cosim agent's scoreboard (for reset monitoring)
   uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*cosim_agt*", "probe_vif", dut_probe_intf);

逐段解释：

* 第 1117 行：同一个 ``dut_probe_intf`` 也提供给 trace monitor，用于中断/debug
  状态采样。
* 第 1120 行：config_db 路径 ``*cosim_agt*`` 让 scoreboard connect phase 能读取
  ``probe_vif``，从而观察 reset。

接口关系：

* 被调用：testbench initial 配置块。
* 调用：``uvm_config_db::set``。
* 共享状态：``dut_probe_intf`` virtual interface。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L165-L183``）：

.. code-block:: systemverilog

   // Monitor reset and re-initialize cosim model after reset de-assertion
   task run_reset_monitor();
     if (probe_vif == null) return;
   
     forever begin
       @(negedge probe_vif.rst_n);
       reset_active = 1;
       `uvm_info("cosim", "Reset asserted - flushing state", UVM_LOW)
       flush_state();
   
       @(posedge probe_vif.rst_n);
       reset_active = 0;
       `uvm_info("cosim", "Reset de-asserted - re-initializing cosim", UVM_LOW)
   
       if (enable_cosim) begin
         init_cosim();
       end

逐段解释：

* 第 167 行：没有 ``probe_vif`` 时 reset monitor 直接返回，不执行 reset 重建逻辑。
* 第 170~173 行：``rst_n`` 下降沿表示 reset asserted；scoreboard 设置
  ``reset_active`` 并调用 ``flush_state``。
* 第 175~180 行：``rst_n`` 上升沿表示 reset de-asserted；若 ``enable_cosim`` 仍为真，
  则再次调用 ``init_cosim``。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：``flush_state``、``init_cosim``。
* 共享状态：``probe_vif.rst_n``、``reset_active``、FIFO 和 pending queue。

§10  Cosim 配置对象与 memory region
------------------------------------

职责：``eh2_cosim_cfg`` 保存 Spike 初始化所需的 ISA string、start PC、PMP 参数、
relax 开关和 memory region。env 注入后，scoreboard ``init_cosim`` 使用这些
region 调用 ``riscv_cosim_add_memory``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L14-L33``）：

.. code-block:: systemverilog

   // RISC-V ISA string passed to Spike (e.g. "rv32imac_zba_zbb_zbc_zbs")
   string isa_string = "rv32imac_zba_zbb_zbc_zbs";
   
   // Initial program counter for the cosim
   bit [31:0] start_pc = 32'h8000_0000;
   
   // Initial machine trap-vector base address
   bit [31:0] start_mtvec = 32'h0;
   
   // Number of PMP regions
   bit [31:0] pmp_num_regions = 16;
   
   // PMP granularity (log2 of minimum region size)
   bit [31:0] pmp_granularity = 0;
   
   // Number of MHPM performance counters
   bit [31:0] mhpm_counter_num = 0;
   
   // When set, mismatches are logged as UVM_LOW instead of UVM_FATAL
   bit relax_cosim_check = 0;

逐段解释：

* 第 15 行：默认 ISA string 是 ``rv32imac_zba_zbb_zbc_zbs``。
* 第 18~21 行：``start_pc`` 默认为 ``32'h8000_0000``，``start_mtvec`` 默认为 0。
* 第 24~30 行：PMP region 数量、PMP granularity 和 MHPM counter 数量在 cfg 中保存。
* 第 33 行：``relax_cosim_check`` 影响 scoreboard 的 mismatch 严格程度。

接口关系：

* 被调用：env 创建并注入，scoreboard build phase 读取。
* 调用：无外部函数；是 UVM object 配置字段。
* 共享状态：``isa_string``、``start_pc``、``pmp_num_regions``、
  ``relax_cosim_check``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L49-L65``）：

.. code-block:: systemverilog

   mem_region_t mem_boot      = '{base: 32'h8000_0000, size: 32'h0400_0000};
   mem_region_t mem_debug_sb  = '{base: 32'hA058_0000, size: 32'h0400_0000};
   mem_region_t mem_ext_data1 = '{base: 32'hB000_0000, size: 32'h0400_0000};
   mem_region_t mem_ext_data2 = '{base: 32'hC058_0000, size: 32'h0400_0000};
   mem_region_t mem_iccm      = '{base: 32'hEE00_0000, size: 32'h0001_0000};
   mem_region_t mem_dccm      = '{base: 32'hF004_0000, size: 32'h0001_0000};
   
   // Explicit DCCM/ICCM base/size fields for env injection from RTL parameters
   // (issue 65). These mirror mem_dccm/mem_iccm but provide flat access for
   // testbench wiring and plusarg override.
   bit [31:0] dccm_base = 32'hF004_0000;
   bit [31:0] dccm_size = 32'h0001_0000;
   bit [31:0] iccm_base = 32'hEE00_0000;
   bit [31:0] iccm_size = 32'h0001_0000;
   mem_region_t mem_pic       = '{base: 32'hF00C_0000, size: 32'h0000_8000};
   mem_region_t mem_mailbox   = '{base: 32'hD058_0000, size: 32'h0000_1000};
   mem_region_t mem_nmi_vec   = '{base: 32'h1111_0000, size: 32'h0000_1000};

逐段解释：

* 第 49~54 行：cfg 定义 boot、debug SB、外部数据、ICCM 和 DCCM region。
* 第 59~62 行：DCCM/ICCM 还有 flat 字段，供 env plusarg 覆盖和同步。
* 第 63~65 行：PIC、mailbox 和 NMI vector region 也作为 Spike memory 注册输入。

接口关系：

* 被调用：``init_cosim`` 在 ``cfg != null`` 时读取这些字段。
* 调用：``sync_mem_regions`` 会同步 ICCM/DCCM flat 字段到 struct 字段。
* 共享状态：``mem_boot``、``mem_iccm``、``mem_dccm``、``mem_pic``、
  ``mem_mailbox``、``mem_nmi_vec``。

§11  Spike 初始化、CSR 预注册和 binary loader
---------------------------------------------

职责：``init_cosim`` 创建 Spike cosim handle，注册 memory region，include CSR
预注册 header，并处理 pending/stored binary load。binary loader 通过
``riscv_cosim_write_mem_byte`` 写入 Spike memory model。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L719-L757``）：

.. code-block:: systemverilog

   protected function void init_cosim();
     cleanup_cosim();
   
     if (enable_cosim) begin
       cosim_handle = riscv_cosim_init(cosim_config);
       if (cosim_handle == null) begin
         `uvm_fatal("cosim", "Failed to initialize co-simulation")
       end
       initialized = 1;
   
       // Register all DUT-accessible memory regions with Spike (from cfg — issue 65).
       if (cfg != null) begin
         riscv_cosim_add_memory(cosim_handle, cfg.mem_boot.base,      cfg.mem_boot.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_debug_sb.base,  cfg.mem_debug_sb.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_ext_data1.base, cfg.mem_ext_data1.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_ext_data2.base, cfg.mem_ext_data2.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_iccm.base,      cfg.mem_iccm.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_dccm.base,      cfg.mem_dccm.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_pic.base,       cfg.mem_pic.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_mailbox.base,   cfg.mem_mailbox.size);
         riscv_cosim_add_memory(cosim_handle, cfg.mem_nmi_vec.base,   cfg.mem_nmi_vec.size);

逐段解释：

* 第 719~720 行：初始化前先调用 ``cleanup_cosim``，避免旧 handle 残留。
* 第 722~727 行：``riscv_cosim_init`` 返回 ``cosim_handle``；返回 null 时触发
  ``uvm_fatal``，成功后设置 ``initialized``。
* 第 730~739 行：当 ``cfg`` 存在时，用 cfg 内的 memory region 注册 Spike 可访问
  地址空间。
* 第 754~757 行在同一函数后续 include ``eh2_cosim_csr_preregister.svh``，并记录
  预注册 28 个 EH2 custom CSR 的日志。

接口关系：

* 被调用：``run_phase`` 启动时和 reset de-assert 后。
* 调用：``cleanup_cosim``、``riscv_cosim_init``、``riscv_cosim_add_memory``、
  ``riscv_cosim_set_csr``。
* 共享状态：``cosim_handle``、``initialized``、``cfg``、``pending_bin_path``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh:L14-L30``）：

.. code-block:: systemverilog

   function void load_binary(string bin_path, bit [31:0] base_addr);
     `uvm_info("cosim", $sformatf("Loading binary: %s at 0x%08x", bin_path, base_addr), UVM_LOW)
   
     if (cosim_handle == null) begin
       `uvm_error("cosim", "Cannot load binary: cosim not initialized")
       return;
     end
   
     if (bin_path.len() > 4 && bin_path.substr(bin_path.len()-4, bin_path.len()-1) == ".hex") begin
       load_hex(bin_path, base_addr);
     end else begin
       load_raw_binary(bin_path, base_addr);
     end
   
     stored_bin_path = bin_path;
     stored_base_addr = base_addr;
   endfunction

逐段解释：

* 第 15~20 行：binary load 需要已初始化的 ``cosim_handle``；未初始化时记录错误并返回。
* 第 22~26 行：``.hex`` 后缀走 ``load_hex``，其它路径走 ``load_raw_binary``。
* 第 28~29 行：保存路径和 base address，供 reset recovery 之后重新加载。

接口关系：

* 被调用：agent wrapper 的 ``load_binary_to_mem`` 和 ``init_cosim`` 的 pending/stored
  binary 分支。
* 调用：``load_hex``、``load_raw_binary``。
* 共享状态：``cosim_handle``、``stored_bin_path``、``stored_base_addr``。

§12  参考资料
-------------

* :ref:`appendix_b_uvm_cosim_agent` — cosim agent 与 scoreboard 的源码字典。
* :ref:`cosim_scoreboard` — scoreboard 数据流和 Spike step 时序说明。
* :doc:`../appendix_c_tools/cosim_cpp` — C++/DPI 侧 ``riscv_cosim_*`` 实现说明。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

§13  与 Ibex 工业实现对照
-------------------------

Ibex 的 ``ibex_cosim_agent`` 以 RVFI monitor 为中心，scoreboard 消费 RVFI item、
dmem/imem item、ifetch/PMP sideband。EH2 的 ``eh2_cosim_agent`` 更像一个 wrapper：
它拥有 scoreboard、binary loader 和 memory/CSR 初始化路径，真正的比对算法仍在
``eh2_cosim_scoreboard``。这种差异来自 EH2 trace/probe 观测方式，而不是工具链差异。

.. list-table:: Cosim agent 对照
   :header-rows: 1
   :widths: 26 34 40

   * - 维度
     - Ibex
     - EH2
   * - 源码路径
     - ``/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent``
     - ``dv/uvm/core_eh2/common/cosim_agent``
   * - 主输入
     - RVFI monitor item
     - trace monitor item + DUT probe hint + LSU AXI4 item
   * - 初始化
     - ``spike_cosim_init`` 使用 Ibex cfg
     - ``riscv_cosim_init`` + EH2 memory region + 28 个 custom CSR preregister
   * - 二进制加载
     - 由 Ibex flow 与 memory agent 协作
     - ``eh2_cosim_binary_loader.svh`` 支持 hex/raw 和 reset 后重载
   * - 多线程
     - Ibex 以单 hart 路径为主
     - EH2 scoreboard 维护 per-thread queue/counter，支持 NUM_THREADS=2

§14  Sign-off 关联
------------------

Cosim agent 是 ``cosim`` 和 ``riscvdv`` stage 的架构参考入口。当前 2026-05-19 demo
中 riscv-dv 为 370/395 (93.67%)，directed 为 40/40，formal 为 46/46。对 cosim agent
的修改若影响 memory region 注册、custom CSR preregister、binary reload 或 reset
re-init，都必须重新跑至少 smoke、cosim directed 和一组 riscv-dv smoke。

.. tip::

   Spike 初始化失败时不要先看 scoreboard mismatch。先确认 ``cosim_config``、
   ``eh2_cosim_cfg`` memory region、``libcosim.so``、binary load 路径和 reset monitor；
   这些都正常后，再看 ``compare_instruction`` 的 PC/GPR/trap mismatch。

§15  配置与 plusarg 契约
------------------------

cosim agent 的配置来源有两层：``eh2_cosim_cfg`` 给出默认值，env 在创建 agent 前读取
plusarg 并覆盖 ICCM/DCCM flat 字段。这个顺序是契约，因为 scoreboard build phase
只从 ``cosim_agt.scoreboard`` 路径读取一次 cfg。

.. list-table:: Cosim 配置字段
   :header-rows: 1
   :widths: 24 28 48

   * - 字段
     - 默认值
     - 用途
   * - ``isa_string``
     - ``rv32imac_zba_zbb_zbc_zbs``
     - 传给 Spike，定义 EH2 当前支持的 ISA extension
   * - ``start_pc``
     - ``0x8000_0000``
     - Spike 初始 PC，应与程序加载和 reset vector 保持一致
   * - ``start_mtvec``
     - ``0x0``
     - 初始 trap vector
   * - ``pmp_num_regions``
     - ``16``
     - Spike PMP 配置，与 EH2 PMP/ePMP 计划相关
   * - ``dccm_base`` / ``dccm_size``
     - ``0xF004_0000`` / ``0x0001_0000``
     - DCCM memory region，可由 plusarg 覆盖
   * - ``iccm_base`` / ``iccm_size``
     - ``0xEE00_0000`` / ``0x0001_0000``
     - ICCM memory region，可由 plusarg 覆盖
   * - ``mem_mailbox``
     - ``0xD058_0000`` / ``0x1000``
     - Spike 可访问 mailbox region，服务 test end marker

.. code-block:: bash

   make smoke SIMULATOR=vcs EXTRA_SIM_OPTS="+MEM_ICCM_BASE=ee000000 +MEM_DCCM_BASE=f0040000"

.. warning::

   修改 DCCM/ICCM 地址时必须同时考虑 RTL 参数、TB memory map、binary linker script
   和 cosim cfg。只改其中一处，会造成 DUT 能访问但 Spike 不能访问，或 Spike 与 DUT
   访问不同地址空间。

§16  Binary loader 语义
-----------------------

``eh2_cosim_binary_loader.svh`` 的任务是把与 DUT 相同的程序镜像加载到 Spike memory。
它支持 ``.hex`` 和 raw binary 两类路径，并保存最近一次加载的路径/base address，以便
reset 后重新加载。这个行为解决了 reset recovery 后 Spike memory 丢失或仍保留旧镜像的
问题。

.. list-table:: Binary loader 行为
   :header-rows: 1
   :widths: 26 34 40

   * - 场景
     - Loader 行为
     - 调试检查
   * - ``.hex`` 文件
     - 调用 ``load_hex``
     - 检查 hex 行地址和 base address 是否一致
   * - raw binary
     - 调用 ``load_raw_binary``
     - 检查 ELF 转 binary 的 endian 和 entry point
   * - cosim 未初始化
     - 记录错误并返回
     - 先看 ``init_cosim`` 是否成功
   * - reset 后重载
     - 使用 ``stored_bin_path`` 和 ``stored_base_addr``
     - 检查 reset deassert 后是否有 reload 日志
   * - pending load
     - 初始化后处理 pending binary
     - 检查 build/run phase 顺序

§17  Spike DPI 链接边界
-----------------------

cosim agent 在 SystemVerilog 层只声明 DPI 函数；真正的 ISS 行为在 C++/Spike 侧。排查
cosim 初始化失败时，需要把 UVM 配置问题和 DPI 链接问题分开。

.. list-table:: DPI 问题分类
   :header-rows: 1
   :widths: 26 34 40

   * - 现象
     - 可能原因
     - 首选检查
   * - ``riscv_cosim_init`` 返回 null
     - ISA string、Spike 初始化或 shared library 问题
     - VCS load log、``cosim_config`` 字符串
   * - ``riscv_cosim_add_memory`` 无效
     - memory region base/size 错
     - ``eh2_cosim_cfg.convert2string`` 和 env plusarg
   * - CSR set/get 失败
     - custom CSR 未预注册
     - ``eh2_cosim_csr_preregister.svh``
   * - step 后 PC 偏移
     - binary 未加载或 entry point 不一致
     - DUT memory load 与 Spike load 日志
   * - memory notify 不生效
     - AXI4 transaction 未到或 32-bit 拆分错误
     - ``agent_axi4`` 与 ``cosim_scoreboard`` memory notify 小节

§18  与 waiver 和关闭 cosim 的关系
----------------------------------

``cfg.enable_cosim``、plusarg 或 testlist 可以关闭 cosim；waiver 文件可以登记某些
case 的 cosim 限制。这些机制是流程层决策，不属于 agent 自己的通过条件。agent 只负责
在启用时严格连接 scoreboard 和 Spike。

.. list-table:: Cosim 启停路径
   :header-rows: 1
   :widths: 24 34 42

   * - 路径
     - 作用位置
     - 文档口径
   * - ``cfg.enable_cosim``
     - env build/connect
     - 决定是否创建 ``cosim_agt`` 和连接 FIFO
   * - ``enable_cosim``
     - scoreboard run phase
     - 决定是否初始化 Spike 和启动 compare
   * - testlist waiver
     - signoff/regress 脚本
     - 影响统计口径，不改变 scoreboard 语义
   * - ``+disable_cosim``
     - 运行参数或 test cfg
     - 用于纯 RTL 或已登记限制场景

.. note::

   关闭 cosim 的测试仍可能 mailbox PASS，但这不是 architectural lockstep PASS。报告中
   必须区分“RTL self-check 通过”和“Spike cosim 通过”。

§19  修改后的验证建议
---------------------

cosim agent 修改的最小验证组合取决于改动面：

.. list-table:: 改动面到验证组合
   :header-rows: 1
   :widths: 28 36 36

   * - 改动
     - 必跑
     - 追加建议
   * - ``eh2_cosim_cfg``
     - VCS smoke + cosim smoke
     - 覆盖 ICCM/DCCM plusarg 的 directed
   * - Binary loader
     - smoke、reset recovery case
     - ``.hex`` 和 raw binary 各一例
   * - CSR preregister
     - CSR directed、cosim CSR compare
     - CSR unit test 交叉确认
   * - Agent wrapper connect
     - UVM build/connect、store cosim case
     - 查看 ``lsu_agent.ap`` 到 ``lsu_axi_fifo`` 的连接日志
   * - Reset monitor
     - reset-in-test directed
     - interrupt/debug 场景下 reset 后继续执行

命令示例：

.. code-block:: bash

   make smoke SIMULATOR=vcs
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make signoff PROFILE=smoke SIMULATOR=vcs COV=1

§20  Sign-off 数据解释
----------------------

2026-05-19 01:02 demo 中 riscv-dv 370/395 (93.67%) 和 directed 40/40 的价值，来自
cosim agent 将 trace、probe 和 LSU AXI4 三路输入送入同一个 Spike reference model。
如果关闭 cosim 或绕过 memory notify，riscv-dv 的通过数仍可能较高，但它不再代表同一
级别的架构比对。因此本章把 cosim agent 描述为“架构参考入口”，而不是普通 debug
辅助组件。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
