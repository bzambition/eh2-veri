.. _cosim_scoreboard:
.. _05_verification_arch/cosim_scoreboard:

Cosim Scoreboard — 详细参考
============================

:status: draft
:source: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
-------------

本章详细讲解 EH2 验证平台的**协同仿真核心** — ``eh2_cosim_scoreboard`` 。
这个 854 行的 UVM scoreboard 是验证平台中**最关键的单一组件** 。
它用 3 个输入 FIFO + 3 个并行 run task 实现了 DUT vs Spike ISS
的逐拍指令比对，覆盖 PC、GPR 写回、CSR 写回、内存访问四大比对域。

阅读本章你将学到：

* Cosim 的 3 路数据输入（trace / probe / AXI）和它们之间的时序关系
* 3 个并行 run task 的 fork-join 架构与 ``#0`` yield 调度
* 5 类指令的比对流程：普通 / store / AMO / DIV / NB-load
* Spike DPI 的 7 步通知序列（set_debug_req → set_nmi → set_nmi_int → set_mip → set_mcycle）
* ``pending_wb_q`` 的 wb_tag 入队/匹配/作废机制
* Compare 函数的三层比对（PC / GPR + CSR / Memory）
* 多 hart 支持（per-thread trace 队列 + Spike processor_t 路由）
* Report phase 的 pass/fail 判定

§2  数据流架构
---------------

.. code-block:: text

   ┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
   │ eh2_trace_monitor   │     │ eh2_dut_probe_monitor│     │ axi4_monitor (LSU)  │
   │ (退役指令)           │     │ (异步写回)            │     │ (AXI4 内存事务)       │
   └──────────┬──────────┘     └──────────┬──────────┘     └──────────┬──────────┘
              │ ap.write()                │ ap.write()                │ ap.write()
              ▼                           ▼                           ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │                         eh2_cosim_scoreboard                                 │
   │                                                                              │
   │  trace_fifo (uvm_tlm_analysis_fifo)   dut_probe_fifo   lsu_axi_fifo          │
   │       │                                      │                │               │
   │       ▼                                      ▼                ▼               │
   │  run_cosim_trace()               run_cosim_probe()    run_cosim_dmem()        │
   │       │                                      │                │               │
   │       │  (1) #0 yield to probe               │                │               │
   │       │  (2) 等待 store/AMO AXI 事务          │                │               │
   │       │  (3) 等待 DIV/NB-load probe hint     │                │               │
   │       │  (4) riscv_cosim_step()              │                │               │
   │       │  (5) compare_instruction()           │                │               │
   │       └──────────────┬───────────────────────┘                │               │
   │                      ▼                                         │               │
   │               pending_wb_q[slot] (wb_tag → 写回数据)             │               │
   └──────────────────────────────────────────────────────────────────────────────┘

§3  Trace FIFO 消费流程（``run_cosim_trace`` ）
-----------------------------------------------

**5 类指令的差异化处理：**

.. list-table::
   :header-rows: 1
   :widths: 15 85

   * - 指令类型
     - 处理流程
   * - **普通指令**
       （ALU/分支/CSR读）
     - (1) ``trace_fifo.get()`` → trace_seq_item
       (2) ``#0`` yield（让 probe task 先跑）
       (3) 调用 Spike 通知序列（debug_req/nmi/nmi_int/mip/mcycle）
       (4) ``riscv_cosim_step(hart_id)`` → Spike 执行指令
       (5) ``compare_instruction()`` → 比对 PC/GPR/CSR
   * - **Store 指令**
     - 在 step 之前等待 LSU AXI 事务到达：
       while (``lsu_axi_fifo`` 中无匹配事务) ``@(posedge clk)``
       → 拿到 AXI 事务后通知 Spike：``riscv_cosim_notify_dside_access()``
       → 然后 step + compare
   * - **AMO 指令**
     - 类似 Store，需要等待 AXI 事务（AMO 在外部总线上做 read-modify-write）
   * - **DIV 指令**
     - 指令已 retire 但结果在除法器完成后异步写回。
       while (``pending_wb_q[slot]`` 中无匹配的 DIV wb_tag) 等待 probe
       → 取出写回数据 → 写入 Spike 的 GPR → step（Spike 不执行 DIV，
       仅比对 retire 时的 PC 和 mcycle）
   * - **NB-Load 指令**
     - 类似 DIV，等待 ``pending_wb_q`` 中的 NB-load hint
       → 写回数据到达后填入 Spike GPR → step + compare

**``#0`` yield 的必要性：** trace monitor 和 probe monitor 都在
``posedge clk`` 触发。如果 trace task 先于 probe task 消费了
trace FIFO 中的指令，probe 的异步写回事件尚未入队，导致 DIV/NB-load
指令的 wb_tag 匹配失败。``#0`` 延迟让 SV 调度器先执行 probe task

§4  Probe FIFO 消费流程（``run_cosim_probe`` ）
-----------------------------------------------

**Probe 监视的 DUT 内部信号（通过 ``eh2_dut_probe_if`` ）：**

- ``wbd.i0v/i1v`` ：i0/i1 写回有效
- ``wbd.i0_result_wb`` / ``wbd.i1_result_wb`` ：写回数据
- ``wbd.i0_wb_tag`` / ``wbd.i1_wb_tag`` ：写回标签
- ``div_wren`` / ``div_cancel`` ：除法写回/取消
- ``nb_load_wen`` / ``nb_load_tag`` / ``nb_load_data`` ：非阻塞 load

**处理逻辑：**

1. ``dut_probe_fifo.get()`` → 取出 probe 事件
2. 按事件类型分类：
   - ``div_wren`` → ``pending_wb_q[slot].push_back({wb_tag, data})``
   - ``div_cancel`` → 从 ``pending_wb_q[slot]`` 中删除对应 wb_tag 的条目
   - ``nb_load_wen`` → 同 DIV 写入
   - 普通写回 → 也入队（用于 trace 的 RVFI 等价字段比对）

§5  LSU AXI FIFO 消费流程（``run_cosim_dmem`` ）
------------------------------------------------

1. ``lsu_axi_fifo.get()`` → ``axi4_seq_item``
2. 调用 ``riscv_cosim_notify_dside_access()`` 通知 Spike 有内存访问
3. Store 事务：Spike 内部执行 store，与 DUT 的 AXI 事务比对 addr/data/wstrb
4. AMO 事务：Spike 执行 AMO，比对 read-data 和 write-data

****Store Buffer 合并旁路：** EH2 的 store buffer 可能将多次 store 合并为
一个 AXI 事务。Scoreboard 需要将 trace 中的多条 store 指令与单个 AXI
事务匹配。匹配逻辑通过比较地址范围和数据合并值来建立关联。

**AMO 特殊处理（:ref:`adr-0006` ）：**
AMO 指令在外部总线上执行 read-modify-write。Scoreboard 需要：
1. 等待 AXI 事务（AMO 在 LSU 中作为 store 发出）
2. 通知 Spike 有 AMO 访问
3. Step Spike → 比对 read-data（AMO 返回的旧值）
4. 比对 write-data（AMO 写入的新值）

**SC.W 特殊处理（:ref:`adr-0006` ）：**
EH2 SC.W 成功时写回 0，失败时写回非 0。Spike 的行为可能不同——
scoreboard 中有专门的 ``atomic_store_fixup()`` 修正此差异。

§6  Compare 函数详解
---------------------

**``compare_instruction()`` 的三层比对：**

**第 1 层：PC 比对**

- DUT trace 的 PC vs Spike step 后的 PC
- 不匹配 → ``UVM_ERROR`` ，记录 mismatch
- 特殊豁免：interrupt-only item（无 PC 比对，Spike 未 step）

**第 2 层：GPR 写回比对**

- 如果 ``trace.rd_valid[i]=1`` （指令写了目标寄存器）：
  DUT ``rd_data`` vs Spike ``gpr[rd_addr]``
- 注意：DUT 的除法和 NB-load 的 rd_data 来自 probe 而非 trace。
  Scoreboard 用 ``pending_wb_q`` 中的 probe 数据覆盖 trace 的 rd_data
- 不匹配 → ``UVM_ERROR``
- **跨 slot 搜索：** 当 trace 的 rd_valid 与 pending_wb_q 的 slot 不一致时，
  scoreboard 在跨 slot 队列中搜索匹配的 wb_tag。这发生在 NB-load 写回
  被路由到非预期 slot 时

**第 3 层：CSR 写回比对**

- 如果指令是 CSR 写：DUT CSR 值 vs Spike CSR 值
- 通过 ``eh2_csr_if`` 读取 DUT CSR → 与 Spike 的 ``get_csr()`` 比对
- 特殊处理：EH2 自定义 CSR（Spike 不原生支持）→ 通过 ``fixup_csr()``
  将 DUT 值写入 Spike 后再比对

**内存访问比对（Store/AMO）：**

- Store：比对 AXI 事务的 addr + wdata + wstrb
- AMO：比对 read-data（旧值）+ write-data（新值）
- ``notify_memory_access()`` → 将 AXI 事务信息传给 Spike → Spike 执行对应
  的内存操作 → 比对结果

**mcause/mepc 的特殊处理：**

- 异常/中断发生时，比对 mcause（Interrupt bit + Exception Code）和 mepc
- **Phase 1 升级：** mcause/mepc mismatch 从 ``UVM_WARNING`` 升级为 ``UVM_ERROR``
  （零值豁免已删除）。这意味着 cosim 对异常路径的比对是严格的

**Spike 通知序列（step 之前，按顺序）：**

.. code-block:: text

   1. riscv_cosim_set_debug_req(hart_id, debug_req)    // 同步调试请求
   2. riscv_cosim_set_nmi(hart_id, nmi)                // 同步 NMI 状态
   3. riscv_cosim_set_nmi_int(hart_id, nmi_int)        // 同步 NMI 中断
   4. riscv_cosim_set_mip(hart_id, mip)                // 同步中断挂起位
   5. riscv_cosim_set_mcycle(hart_id, mcycle)           // 同步周期计数器
   6. riscv_cosim_step(hart_id)                        // 执行 Spike 指令
   7. compare_instruction()                            // 比对结果

§7  pending_wb_q 管理详解
--------------------------

``pending_wb_q[hart][slot]`` 是 scoreboard 中管理异步写回的核心数据结构。

**入队条件：**

- ``dut_probe_fifo`` 中的 probe 事件到达 → 按 wb_tag 入队对应 slot 的队列
- DIV 写回（``div_wren`` ）→ 入队 slot 0（DIV 始终在 slot 0）
- NB-load 写回（``nb_load_wen`` ）→ 入队 slot 0（NB-load 也始终在 slot 0）
- 普通写回 → 入队对应 slot

**出队/匹配条件：**

- ``run_cosim_trace()`` 处理 DIV/NB-load 指令时，在 ``pending_wb_q[slot]``
  中搜索匹配的 wb_tag
- 匹配成功 → 取出写回数据 → 写入 Spike GPR → 删除队列条目
- 匹配超时（如 100 周期未匹配）→ ``UVM_ERROR`` ：wb_tag timeout

**DIV Cancel 处理：**

- probe 事件中的 ``div_cancel`` 标志 → 从 ``pending_wb_q[slot]`` 中
  删除对应 wb_tag 的条目
- 这防止了被取消的除法结果被错误地用于 GPR 比对

§8  多 Hart 支持（NUM_THREADS=2）
---------------------------------

双线程时 scoreboard 维护 per-thread 的数据结构：

- ``trace_fifo[2]`` ：每个 hart 独立的 trace 队列
- ``pending_wb_q[2][2]`` ：per-hart per-slot 的写回队列
- Spike 端：2 个独立的 ``processor_t`` 实例，共享内存空间
- ``riscv_cosim_step(hart_id)`` ：按 hart_id 路由到正确的 Spike 实例

**线程间同步：** 两个线程的 Spike 实例通过共享的 ``memory_t`` 对象
保持内存一致性。Store 可见性遵循 RISC-V 的 PMA（Physical Memory Attributes）
约定。多 hart 的详细实现见 :ref:`adr-0016` 。

§9  Report Phase
-----------------

在 ``report_phase`` 中：

- 检查 ``mismatch_count`` ：>0 → 仿真结果标记为 FAIL
- 检查 mailbox 状态：PASS/FAIL/超时
- 输出 cosim 统计：总指令数 / mismatch 数 / 比对覆盖率
- Cosim 的 FAIL 优先级高于 mailbox PASS——即使测试程序写入 TEST_PASS，
  如果有 cosim mismatch，最终结果仍为 FAIL

§10  典型故障与调试
-------------------

**故障 1：wb_tag 匹配超时**

- 现象：scoreboard log 显示 "wb_tag timeout"
- 根因：DIV 或 NB-load 的写回 hint 未到达 probe FIFO。
  可能原因：probe monitor 的 hierarchical reference 路径错误、
  DIV cancel 过早作废了写回、NB-load 数据返回路径被 hang
- 调试：在波形中跟踪 ``exu_div_wren`` / ``lsu_nonblock_load_data_valid``

**故障 2：Store buffer 合并导致 AXI 事务不匹配**

- 现象：scoreboard 在等待 AXI 事务时超时，或 AXI addr 与 trace store addr 不一致
- 根因：store buffer 将多次小 store 合并为一个大 AXI burst，
  scoreboard 的合并检测逻辑遗漏了某些合并模式
- 调试：在波形中对比 ``store_stbuf_reqvld_dc5`` 和 ``lsu_axi_awaddr``

**故障 3：Interrupt-only item 被当作普通指令 step**

- 现象：Spike PC 与 DUT trace PC 持续不匹配（偏移越来越大）
- 根因：``trace.interrupt=1 && trace.exception=0`` 的 item 应该只更新
  Spike 的 mip/mie，不应该调用 ``riscv_cosim_step()`` 。
  Scoreboard 错误地调用了 step，导致 Spike 多执行了一条指令

**故障 4：Spike CSR 未预注册**

- 现象：``riscv_cosim_set_csr()`` 返回错误
- 根因：``eh2_cosim_csr_preregister.svh`` 中遗漏了某个 CSR。
  检查 28 个 CSR 列表是否完整

**故障 5：#0 yield 失效**

- 现象：DIV/NB-load 指令的 wb_tag 匹配失败，但波形显示 probe 信号正确
- 根因：SystemVerilog scheduler 在特定 corner case 下未保证
  trace monitor 和 probe monitor 的执行顺序。#0 延迟不是强保证。
  参见 :ref:`adr-0001` 中关于此 race condition 的详细分析

§11  Scoreboard 初始化流程
----------------------------

Cosim scoreboard 在 ``build_phase`` 和仿真开始时执行以下初始化：

1. 创建 3 个 ``uvm_tlm_analysis_fifo`` （trace_fifo / dut_probe_fifo / lsu_axi_fifo）
2. 从 ``uvm_config_db`` 获取 ``eh2_cosim_cfg`` 配置对象
3. 调用 ``riscv_cosim_init()`` DPI 函数：
   - 创建 ``processor_t`` 实例（每 hart 一个）
   - 设置 ISA string（RV32IMACZbaZbbZbcZbs）
   - 配置 PMP 区域数和粒度
   - 设置 mhpm_counter_num
4. 预注册 28 个 EH2 自定义 CSR（``eh2_cosim_csr_preregister.svh`` ）
5. 加载测试程序到 Spike 内存（``load_binary_to_mem()`` ）
6. 在 ``run_phase`` 中 fork 3 个并行 task

**复位重初始化：** TB top 在 ``rst_l`` 释放时通过 ``reset()`` 函数
重新执行步骤 3-5，确保 Spike 状态与 DUT 复位后的状态一致。

§12  Scoreboard 代码结构（854 行分解）
---------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 15 10 75

   * - 区域
     - 行数
     - 内容
   * - 类声明+FIFO
     - ~50
     - 3 个 analysis_fifo 声明、配置句柄、统计计数器
   * - build_phase
     - ~30
     - FIFO 创建、config_db get
   * - run_phase
     - ~20
     - fork 3 个 task + reset monitoring
   * - run_cosim_trace
     - ~200
     - 主比对循环：trace_fifo.get → 分类处理 → step → compare
   * - run_cosim_probe
     - ~80
     - probe 事件消费 → pending_wb_q 管理
   * - run_cosim_dmem
     - ~60
     - AXI 事务消费 → notify_dside_access
   * - compare_instruction
     - ~100
     - PC/GPR/CSR 三层比对
   * - handle_nb_load/div_cancel
     - ~80
     - 异步写回处理
   * - notify_memory_access
     - ~50
     - Store/AMO 内存访问通知
   * - report_phase
     - ~40
     - mismatch_count 检查 + 统计输出
   * - 辅助函数
     - ~144
     - CSR fixup、debug check、复位处理等

§13  Performance Considerations
-------------------------------

**Scoreboard 性能瓶颈：**
- ``riscv_cosim_step()`` 是最大开销（Spike ISS 单步执行）
- 3 个 FIFO 的 ``get()`` 阻塞等待是次大开销
- AXI4 事务等待（store/AMO）可能引入长延迟

**优化建议：**
- 使用 ``+disable_cosim=1`` 跳过 cosim（纯 RTL 回归时）
- 减少 cosim 使能的测试的随机种子数（当前 riscvdv 阶段 37/43 使能）
- Store buffer 合并减少 AXI4 事务等待

§14  Scoreboard 调试技巧
-------------------------

**启用详细日志：**
.. code-block:: bash

   make run TEST=riscv_smoke_test +enable_cosim_debug=1

**关键 UVM 日志等级：**
- ``UVM_HIGH`` ：每条指令的 step + compare 细节
- ``UVM_MEDIUM`` ：trace/probe/AXI 事件入队通知
- ``UVM_LOW`` ：pending_wb_q 状态变化
- ``UVM_NONE`` ：仅 mismatch 报告

**波形调试的关键信号：**
- ``cosim_scoreboard.mismatch_count`` ：比对错误计数
- ``cosim_scoreboard.trace_fifo.size()`` ：trace 积压
- ``cosim_scoreboard.pending_wb_q[0][0].size()`` ：写回队列深度

§15  参考资料
-------------

* :ref:`adr-0001` — Cosim via trace and probe
* :ref:`adr-0006` — Atomic Cosim
* :ref:`adr-0007` — Interrupt Cosim
* :ref:`adr-0008` — Debug Cosim
* :ref:`appendix_c_tools/cosim_cpp` — Spike DPI C++ 源码
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`

§16  当前 scoreboard 的真实数据入口
------------------------------------

当前 ``eh2_cosim_scoreboard`` 有 3 个 TLM FIFO，分别对应退休 trace、DUT probe hint
和 LSU AXI4 transaction。它不再依赖旧式“trace item + 独立写回 FIFO”的脆弱关联，
因为 trace packet 已携带 RVFI-equivalent 写回字段；DUT probe 只负责异步写回抑制、
DIV/NB-load hint、reset monitor 和 debug/interrupt 辅助状态。

.. code-block:: text

   trace_monitor.ap
      |
      v
   trace_fifo --------------+
                            |
   dut_probe_monitor.ap ----+--> process_pending_trace(tid)
      |                     |       |
      v                     |       +--> riscv_cosim_set_*()
   dut_probe_fifo ----------+       +--> riscv_cosim_step()
                            |
   lsu_agent.ap ------------+
      |
      v
   lsu_axi_fifo --> pending_mem_access_q --> notify_memory_access()

.. list-table:: FIFO 与队列职责
   :header-rows: 1
   :widths: 25 30 45

   * - 对象
     - 来源
     - 职责
   * - ``trace_fifo``
     - ``eh2_trace_monitor``
     - 退休指令、PC、trap、rd/wdata、线程 ID
   * - ``dut_probe_fifo``
     - ``eh2_dut_probe_monitor``
     - DIV/NB-load async writeback hint、strict ``wb_tag`` 匹配、reset 观察
   * - ``lsu_axi_fifo``
     - ``lsu_agent.ap``
     - store/AMO d-side access、byte strobe 和 error notification
   * - ``pending_trace_q[2]``
     - scoreboard 内部
     - 双线程 per-thread 退休顺序保持
   * - ``async_wb_q[2]``
     - scoreboard 内部
     - per-thread DIV/NB-load hint 等待队列
   * - ``pending_mem_access_q``
     - scoreboard 内部
     - shared LSU memory access 队列

关键代码（FIFO、双线程队列和 run phase）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 35-178
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:35-178

逐段解释：

* 第 38-41 行声明 3 个 analysis FIFO。
* 第 72-93 行声明 per-thread pending trace、shared memory access 和 per-thread
  async writeback hint。
* 第 164-172 行并行启动 trace、probe、dmem 和 reset monitor 四条任务。

§17  Step 前的三个等待条件
--------------------------

scoreboard 不会收到 trace item 就立即调用 Spike。它先检查 3 类等待条件：

1. store/AMO 需要 LSU AXI4 write transaction，除非 store coalescing 计数允许绕过。
2. DIV 和 NB-load 需要匹配 ``wb_tag`` 的 async writeback hint。
3. reset active 时 FIFO 和内部队列会被 flush，reset deassert 后重新初始化 Spike。

关键代码（pending trace drain）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 268-337
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:268-337

逐段解释：

* ``must_wait_for_memory_access`` 把 load 与 store/AMO 分开处理，load 不等待 AXI4
  write transaction。
* ``has_matching_async_wb`` 使用 source 和 ``wb_tag``，不再回退到 rd-based heuristic。
* ``compare_instruction`` 只在所有必要 side effect 都已观察后执行，减少 Spike 与 DUT
  在 store buffer、DIV cancel、NB-load 延迟上的伪 mismatch。

§18  Spike 通知顺序
-------------------

EH2 scoreboard 继承 Ibex 的 ISS 通知顺序：debug request 优先，然后 NMI、NMI interrupt、
MIP、mcycle，最后 ``riscv_cosim_step``。这个顺序不能随意调整，因为 debug/interrupt
同时出现时，Spike 的 privilege/exception 入口必须和 RTL trace 的优先级一致。

关键代码（memory notification 和 instruction compare）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 520-699
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:520-699

.. list-table:: ``compare_instruction`` 输入到 Spike 的映射
   :header-rows: 1
   :widths: 24 32 44

   * - Spike API
     - EH2 来源
     - 说明
   * - ``riscv_cosim_set_debug_req``
     - trace/probe debug state
     - debug 优先级最高
   * - ``riscv_cosim_set_nmi``
     - ``item.nmi``
     - NMI level
   * - ``riscv_cosim_set_nmi_int``
     - ``item.nmi_int``
     - NMI interrupt edge/状态
   * - ``riscv_cosim_set_mip``
     - ``prev_mip[tid]`` 与 ``item.mip``
     - 传递 pre/post interrupt pending
   * - ``riscv_cosim_set_mcycle``
     - ``item.mcycle``
     - 性能计数器同步
   * - ``riscv_cosim_step``
     - rd、rd_wdata、PC、trap、suppress
     - 每条退休指令的主比对点

§19  与 Ibex 工业实现对照
-------------------------

Ibex 的 ``ibex_cosim_scoreboard`` 以 RVFI seq item 为主输入，同时消费 dmem、imem、
ifetch 和 PMP sideband。EH2 的 scoreboard 以 trace packet 为主输入，并组合 DUT probe
和 LSU AXI4 transaction。差异来自 DUT 可观测接口，而不是方法论差异：两者都把 Spike
作为 architectural reference model，都在 UVM scoreboard 内完成 step/compare，都把
debug/NMI/MIP/mcycle 放在 step 前通知。

.. list-table:: Cosim scoreboard 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - 主退休输入
     - ``ibex_rvfi_seq_item``
     - ``eh2_trace_seq_item``，含 RVFI-equivalent rd/wdata
   * - memory 输入
     - ``ibex_mem_intf_seq_item`` dmem/imem
     - ``axi4_seq_item`` LSU d-side transaction
   * - 多线程
     - 单 hart 为主
     - ``pending_trace_q[2]``、``async_wb_q[2]``、per-thread ``mismatch_count``
   * - 异步写回
     - RVFI item 已封装大多数写回状态
     - DIV/NB-load 通过 DUT probe hint 和 strict ``wb_tag`` 补偿
   * - reset
     - reset event 后重启 scoreboard loop
     - probe reset monitor flush FIFO/队列并重新 ``init_cosim``

§20  Sign-off 关联
------------------

scoreboard 是 ``cosim``、``directed`` 和 ``riscvdv`` 质量门的核心组件。2026-05-19
VCS 主线 demo 中，riscv-dv 为 370/395 (93.67%)，directed 为 40/40，formal 为
46/46，LEC 为 31635/31635 PASS。若 scoreboard 放宽 mismatch 或跳过 LSU notification，
这些数字就不再具有 architectural reference 含义。

.. warning::

   ``fatal_on_mismatch`` 可以控制 mismatch 是 ``UVM_FATAL`` 还是 ``UVM_ERROR``，
   但不能把 mismatch 当成通过。sign-off gate 仍应从 scoreboard 统计、日志检查和
   waiver 机制共同判定结果。

§21  严格 ``wb_tag`` 策略
-------------------------

EH2 的 DIV 和 NB-load 写回可能晚于 trace retire item 到达。scoreboard 不能简单按
``rd`` 寄存器号匹配，因为同一个目的寄存器可能在短时间内被多条指令写入；也不能只按
slot 匹配，因为双发射和 replay 可能改变写回路径。因此当前实现以 ``wb_tag`` 和
``wb_source`` 作为严格关联键。

.. list-table:: Async writeback 匹配键
   :header-rows: 1
   :widths: 24 30 46

   * - 字段
     - 来源
     - 作用
   * - ``wb_source``
     - DUT probe / trace item
     - 区分 regular、DIV、NB-load、cancel 等来源
   * - ``wb_tag``
     - DUT probe / writeback path
     - strict ordering tag，避免 rd-based heuristic
   * - ``rd``
     - trace/probe
     - 作为比对输出寄存器，不作为唯一匹配键
   * - ``rd_data``
     - async hint
     - 在 Spike step/compare 前补入 expected architectural value
   * - ``suppress``
     - async hint
     - 表示该写回被取消或不应参与 GPR compare

严格 ``wb_tag`` 策略的好处是错误更早暴露：如果 RTL probe 路径或 trace item 丢了 tag，
scoreboard 会等待超时，而不是把后续同 rd 的写回误配成当前指令结果。对 sign-off 而言，
这种“宁可报错，不做启发式猜测”的行为比提高通过率更重要。

§22  Store/AMO memory access 匹配
---------------------------------

store 和 AMO 的 architectural side effect 不能只靠 trace item 判断，因为 byte strobe、
AXI beat、write error 和 store buffer 合并都发生在 LSU/总线边界。scoreboard 的策略是：
trace item 说明“哪条指令退休”，LSU AXI4 transaction 说明“对外写了什么”，二者都具备
后才调用 Spike step 或 memory notification。

.. code-block:: text

   trace store item
      |
      +-- needs memory access? yes
              |
              v
      pending_mem_access_q has compatible AXI txn?
              |
              +-- no  -> keep pending trace
              |
              +-- yes -> pop AXI txn
                        notify_memory_access()
                        riscv_cosim_step()
                        compare_instruction()

.. list-table:: Store/AMO 匹配维度
   :header-rows: 1
   :widths: 24 30 46

   * - 维度
     - 来源
     - 说明
   * - 线程 ID
     - trace item
     - 用于选择 Spike hart；AXI4 bus 本身是共享资源
   * - 地址
     - trace item / AXI4 txn
     - 用于判断 transaction 是否对应当前 store/AMO
   * - strobe
     - AXI4 W channel
     - 决定 byte enable 和 32-bit lane 拆分
   * - data
     - AXI4 W channel
     - 传给 Spike memory model
   * - error
     - AXI4 response
     - access fault/exception compare 的输入
   * - coalescing
     - scoreboard 内部计数/队列
     - 处理 store buffer 合并带来的多 trace 对一 AXI 事务

§23  Reset flush 规则
---------------------

reset 是 cosim scoreboard 的强边界。reset asserted 时，任何尚未 step 的 trace item、
未消费的 memory access、未匹配的 async writeback hint 都不应跨 reset 保留。reset
deassert 后，Spike 必须重新初始化并重新加载已保存的 binary，否则 DUT 和 Spike 从不同
architectural state 起跑。

.. list-table:: Reset 时清理的状态
   :header-rows: 1
   :widths: 26 34 40

   * - 状态
     - 清理原因
     - 若未清理的症状
   * - ``pending_trace_q``
     - reset 前退休队列失效
     - reset 后第一条指令与旧 PC 比对
   * - ``async_wb_q``
     - reset 前 DIV/NB-load hint 失效
     - 旧写回被用于新指令 GPR compare
   * - ``pending_mem_access_q``
     - reset 前 AXI4 side effect 不应延续
     - 新 store 错配旧 AXI transaction
   * - ``trace_fifo`` / ``dut_probe_fifo`` / ``lsu_axi_fifo``
     - TLM FIFO 可能已有 reset 前 item
     - reset 后立刻处理 stale item
   * - ``cosim_handle``
     - Spike architectural state 需要重建
     - PC/CSR/GPR 长串 mismatch
   * - statistics
     - 视统计用途保留或归零
     - 报告中 reset 前后计数难以解释

.. tip::

   reset 相关问题优先看 ``run_reset_monitor`` 日志，而不是第一个 PC mismatch。第一个
   mismatch 往往只是后果；真正的问题通常是 reset edge 未被 probe_vif 捕获、binary
   未重载，或某个 pending queue 没有 flush。

§24  Scoreboard 日志分级
------------------------

scoreboard 日志需要在“可定位”和“不过度拖慢回归”之间平衡。建议按下面的分级打开：

.. list-table:: 日志等级使用建议
   :header-rows: 1
   :widths: 22 38 40

   * - 等级
     - 适用内容
     - 使用场景
   * - ``UVM_NONE``
     - mismatch、fatal、最终统计
     - CI 和 sign-off 默认
   * - ``UVM_LOW``
     - reset、init、memory region、binary load
     - Spike 初始化或 reset 重建问题
   * - ``UVM_MEDIUM``
     - trace/probe/AXI item 入队、关键状态转换
     - 单个 directed 调试
   * - ``UVM_HIGH``
     - 每条指令 step、GPR/CSR compare、memory notify
     - 短程序 cosim mismatch 定位
   * - 自定义 plusarg
     - ``+enable_cosim_debug=1`` 等
     - 局部打开详细日志，避免全回归日志爆炸

调试命令示例：

.. code-block:: bash

   make smoke SIMULATOR=vcs EXTRA_SIM_OPTS="+enable_cosim_debug=1"
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make smoke SIMULATOR=nc WAVES=1

§25  Mismatch 分类与处理
------------------------

scoreboard mismatch 不是同一种错误。triage 时应先分类，再决定看 trace、probe、AXI4、
Spike DPI 还是 RTL。

.. list-table:: Mismatch 分类
   :header-rows: 1
   :widths: 24 34 42

   * - 类型
     - 常见根因
     - 首选检查点
   * - PC mismatch
     - branch/exception/debug/interrupt 优先级不同步
     - trace item PC、Spike step 前通知顺序、flush/trap 字段
   * - GPR mismatch
     - rd_data 错、async hint 错配、load data 错
     - ``wb_tag``、``rd``、``rd_data``、LSU read/write transaction
   * - CSR mismatch
     - custom CSR 未预注册、WARL fixup 不完整
     - ``eh2_cosim_csr_preregister.svh``、CSR interface、Spike CSR API
   * - Trap mismatch
     - mcause/mepc/mtval 优先级或异常类型不同
     - trace trap fields、TLU exception path、Spike privilege state
   * - Memory mismatch
     - strobe/addr/data/error notify 错
     - AXI4 monitor item、``notify_memory_access`` 32-bit 拆分
   * - Timeout
     - pending trace 等待 memory 或 async writeback
     - ``pending_trace_q``、``pending_mem_access_q``、``async_wb_q``

.. warning::

   不要通过降低 mismatch 等级来“修复”cosim。只有在 ADR 明确记录为 waiver 的情况下，
   才能把某类已知差异从 release gate 中剔除；普通 mismatch 必须定位到 RTL、test、
   Spike model 或 scoreboard 逻辑之一。

§26  与 waiver 的关系
---------------------

当前平台存在 ``cosim-disabled`` waiver 机制，用于管理部分 riscv-dv case 暂不启用
cosim 或可接受失败的历史边界。scoreboard 文档不应把 waiver 描述成 cosim 通过；它
只是 sign-off 统计中的例外登记。2026-05-19 demo 的总体口径是 Status PASS、9/9 stages
PASS、实跑覆盖率 102/104 (98.1%)，其中 fail-rate ceiling 为 25%。

.. list-table:: Waiver 与 scoreboard 的边界
   :header-rows: 1
   :widths: 28 32 40

   * - 对象
     - 能做什么
     - 不能做什么
   * - scoreboard
     - 报告 architectural mismatch、统计 trace/probe/AXI item
     - 自行判定某个 test 在 sign-off 中豁免
   * - ``cosim-disabled.yaml``
     - 声明哪些 test/case 不启用 cosim 或有 waiver
     - 改写 scoreboard 比对结果
   * - ``signoff.py``
     - 计算 fail-rate ceiling、汇总 stage 状态
     - 把未登记 mismatch 当成通过
   * - ADR
     - 解释为什么存在 waiver 和退出条件
     - 替代真实回归数据

§27  代码变更后的最小验证
-------------------------

scoreboard 变更属于高风险修改。建议至少跑以下组合：

.. code-block:: bash

   make smoke SIMULATOR=vcs
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make signoff PROFILE=smoke SIMULATOR=vcs COV=1

若改动涉及 memory notify 或 async writeback，应再选一组包含 store/AMO、DIV、NB-load、
interrupt/debug 的 directed 或 riscv-dv 子集。验收时不仅看 mailbox PASS，还要看
scoreboard mismatch_count、pending queue high watermark、reset re-init 日志和
``riscv_cosim_*`` DPI 返回状态。

§28  工业实现原则
-----------------

EH2 scoreboard 与 Ibex scoreboard 的共同原则可以概括为三条。第一，ISS 是架构参考模型，
不能让 RTL 的错误反向污染 Spike state，除非这是明确的 custom CSR fixup 或已登记的
模型差异。第二，scoreboard 消费已观察到的 DUT side effect，而不是在内部重新模拟总线、
pipeline 或 interrupt controller。第三，任何放宽都必须通过 cfg、waiver 或 ADR 显式
表达，不能埋在 compare 函数的特殊分支中。

这些原则使 2026-05-19 的 riscv-dv 370/395 (93.67%)、directed 40/40 和 formal
46/46 能被解释为同一套验证策略下的结果，而不是多个互不相关的脚本数字。

§29  ``init_cosim`` 与 ``report_phase`` 源码锚点
------------------------------------------------

scoreboard 的生命周期由 ``init_cosim``、``cleanup_cosim``、``report_phase`` 和
``final_phase`` 收尾。理解这几个函数可以解释为什么 reset 后可以恢复、为什么 pending
trace 不一定立即视为失败，以及为什么 mismatch 总数是 release-facing 判据。

关键代码（初始化、统计和清理）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 719-853
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:719-853

逐段解释：

* 第 719-727 行：初始化前清理旧 handle，再调用 ``riscv_cosim_init``，失败即 fatal。
* 第 730-739 行：从 ``eh2_cosim_cfg`` 注册 boot、debug SB、external data、ICCM、
  DCCM、PIC、mailbox 和 NMI vector region。
* 第 754-757 行：include CSR 预注册表，并记录 28 个 EH2 custom CSR。
* 第 759-768 行：处理 pending binary 或 reset recovery 后的 stored binary reload。
* 第 771-784 行：重置计数器和 pending queue，这是 reset 后避免 stale item 的关键。
* 第 795-837 行：report phase 汇总 trace/probe/AXI、pending queue、step 和 mismatch。
* 第 839-851 行：final/pre_abort 均调用 ``cleanup_cosim``，避免 DPI handle 泄漏。

§30  Report 结果判定细节
------------------------

``report_phase`` 的 PASS 条件不是 mailbox PASS，而是 scoreboard 自身看到至少一次 step
且 total mismatch 为 0。pending trace 或 pending LSU access 在特定 EH2 nb-load/store
buffer timing 下可能以 note 形式出现；但 mismatch 非零时必须报 FAIL。

.. list-table:: Scoreboard report 字段
   :header-rows: 1
   :widths: 28 32 40

   * - 字段
     - 含义
     - 解读
   * - ``Trace items received``
     - trace FIFO 收到的 item 数
     - 为 0 说明 DUT 未退休或 trace monitor 未连接
   * - ``Probe items received``
     - async-only probe item 数
     - DIV/NB-load/debug/reset 相关诊断
   * - ``AXI items received``
     - LSU AXI4 transaction 数
     - store/AMO/load 总线活动诊断
   * - ``Pending trace items``
     - 未 step 的 per-thread trace
     - 可能等待 memory/async hint，也可能是结束边界
   * - ``Pending LSU accesses``
     - 未消费的 memory access
     - 可能由 store buffer timing 或 test end 边界导致
   * - ``Pending async wb hints``
     - 未匹配的 async writeback hint
     - 需要排查 ``wb_tag`` 或 trace/hint 顺序
   * - ``Steps executed``
     - Spike step 次数
     - 为 0 时不能宣称 cosim pass
   * - ``Mismatches``
     - per-thread mismatch 计数
     - release-facing 失败判据

§31  多线程顺序模型
-------------------

EH2 双线程 scoreboard 的基本策略是 per-thread retire 顺序独立、LSU memory access
共享。``pending_trace_q[0]`` 和 ``pending_trace_q[1]`` 分别保存两个线程的退休队列；
``pending_mem_access_q`` 是共享队列，因为外部 LSU AXI4 不天然携带与 trace 等价的
hart-local 顺序。

.. code-block:: text

   T0 trace_fifo item -> pending_trace_q[0] --+
                                             +--> process_pending_trace(tid)
   T1 trace_fifo item -> pending_trace_q[1] --+

   LSU AXI txn -> pending_mem_access_q ------> matching store/AMO trace

.. list-table:: 多线程状态
   :header-rows: 1
   :widths: 26 34 40

   * - 状态
     - 粒度
     - 原因
   * - ``pending_trace_q``
     - per-thread
     - retire order 对每个 hart 独立
   * - ``async_wb_q``
     - per-thread
     - DIV/NB-load hint 需要回到对应 hart
   * - ``prev_mip``
     - per-thread
     - interrupt pending 状态按 hart 同步
   * - ``mismatch_count``
     - per-thread
     - report 中定位 T0/T1 问题
   * - ``pending_mem_access_q``
     - shared
     - LSU AXI4 是共享 d-side 观察面
   * - ``cosim_handle``
     - shared handle 内部多 hart
     - Spike C++ 层路由到 processor_t

§32  Store buffer timing note 的含义
------------------------------------

report phase 在 total mismatch 为 0 但存在 pending trace 或 pending LSU access 时，会输出
note，而不是直接 fail。这不是放宽 architectural compare，而是承认 EH2 的 nb-load /
store-buffer timing 可能在 test end 边界留下尚未消费的 sideband。真正的 gate 仍看
mismatch、step_count、stage status 和脚本 log check。

.. warning::

   这个 note 不能被用来掩盖中途的 memory mismatch。如果 pending queue 持续增长、
   high watermark 异常，或测试在 store/AMO 处卡住，应按失败处理，而不是引用 report
   note 作为 waiver。

§33  Cosim scoreboarding 与 formal 的边界
-----------------------------------------

Cosim scoreboard 是动态仿真 reference compare；formal stage 证明的是选定 property
在给定约束下成立。二者互补但不能替代。2026-05-19 demo 中 formal 46/46 PASS，说明
当前 formal property 全部通过；scoreboard 的 riscv-dv/direct/cosim 结果说明动态程序
路径与 Spike reference 一致。

.. list-table:: Cosim 与 formal 对照
   :header-rows: 1
   :widths: 26 34 40

   * - 维度
     - Cosim scoreboard
     - Formal
   * - 输入
     - trace/probe/AXI transaction
     - SVA property、assume/assert、bounded/unbounded proof
   * - 参考
     - Spike ISS
     - property specification
   * - 强项
     - 长程序、真实 instruction stream、CSR/memory side effect
     - corner case exhaustive proof、协议不变量
   * - 弱项
     - 受测试 stimulus 覆盖限制
     - 受 property 范围和环境约束限制
   * - 报告
     - mismatch、step、pending queue
     - proof pass/fail、counterexample

§34  Scoreboard 代码审查清单
----------------------------

修改 scoreboard 前后，至少检查：

* 是否保留 debug/NMI/MIP/mcycle 在 step 前的通知顺序。
* 是否仍用 ``wb_tag`` 匹配 async writeback，避免退回 rd-based heuristic。
* 是否仍在 store/AMO 前等待必要的 LSU AXI4 transaction。
* reset asserted 时是否 flush trace、probe、memory 和 async queue。
* ``init_cosim`` 是否注册所有 DUT 可访问 memory region。
* custom CSR preregister 数量和列表是否与 Spike 侧支持一致。
* report phase 是否仍把 mismatch 非零作为 FAIL。
* waiver 是否只在流程层处理，没有埋入 compare 函数。

这些检查的目标不是让 scoreboard 更宽松，而是保持它作为 architectural reference gate
的可信度。

§35  ``count_observed_memory_accesses`` 与 split 逻辑
-----------------------------------------------------

scoreboard 在等待 store/AMO memory access 时，需要知道一个 AXI4 transaction 对应多少个
可观察的 32-bit memory access。64-bit beat、byte strobe 和 burst length 会影响这个
计数。若计数偏小，Spike 可能少收到一次写；若计数偏大，trace 可能长时间等待不存在的
memory side effect。

关键代码（memory access 计数与 notify 入口）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 458-535
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:458-535

.. list-table:: 计数与拆分风险
   :header-rows: 1
   :widths: 26 34 40

   * - 风险
     - 触发条件
     - 检查
   * - 低 32-bit strobe 丢失
     - ``strb[3:0]`` 非零但未 notify
     - byte/half/word store 到低 lane
   * - 高 32-bit strobe 丢失
     - ``strb[7:4]`` 非零但未 notify
     - word store 到高 lane 或 64-bit beat
   * - beat address 错
     - burst ``size`` 或 ``len`` 处理错误
     - ``beat_addr = addr + i * (1 << size)``
   * - read/write 方向误判
     - ``tx_type`` 错或 monitor 发布错误
     - AXI4 monitor item 字段
   * - error flag 丢失
     - ``resp`` 未更新或默认 OKAY
     - access fault directed

§36  Instruction compare 的职责边界
-----------------------------------

``compare_instruction`` 负责把 trace item、Spike step 结果和必要的 DUT sideband 做一次
architectural compare。它不应该重新解码 RTL pipeline，也不应该把 UVM sequence 的期望
硬编码进去。sequence 负责产生 stimulus，trace/probe/AXI monitor 负责观察，scoreboard
只比较已经退休或已经对外可见的 side effect。

.. list-table:: Compare 输入来源
   :header-rows: 1
   :widths: 26 34 40

   * - 输入
     - 来源
     - 用途
   * - PC/insn
     - trace item
     - 与 Spike step 后 PC/commit 对齐
   * - rd/rd_wdata
     - trace item 或 async hint
     - GPR compare
   * - trap/exception
     - trace item、probe CSR
     - mcause/mepc/mtval compare
   * - debug/NMI/MIP
     - trace/probe
     - step 前同步 Spike external state
   * - memory access
     - LSU AXI4 item
     - store/AMO side effect
   * - CSR value
     - DUT CSR probe / Spike CSR API
     - CSR compare 和 custom CSR fixup

§37  Spike 状态污染防护
-----------------------

scoreboard 在少数情况下会把 DUT 信息写入 Spike，例如 custom CSR 预注册、某些 CSR fixup
或 async writeback 值同步。这些操作必须受限于“Spike 模型缺少 EH2-specific 状态”或
“DUT side effect 已经确认发生”的场景。若无约束地把 DUT 结果写入 Spike，会把 RTL
错误变成 reference model 状态，从而掩盖 mismatch。

.. list-table:: 允许与不允许的 Spike state 更新
   :header-rows: 1
   :widths: 28 34 38

   * - 操作
     - 是否允许
     - 条件
   * - 注册 EH2 custom CSR
     - 允许
     - Spike 原生不支持，必须在 init 阶段补齐
   * - 同步 debug/NMI/MIP/mcycle
     - 允许
     - step 前外部状态输入
   * - async writeback hint
     - 允许
     - 通过 strict ``wb_tag`` 匹配后
   * - 修正任意 GPR mismatch
     - 不允许
     - 会掩盖 RTL 或 Spike 差异
   * - 跳过 PC mismatch
     - 不允许
     - 除非 ADR/waiver 明确登记
   * - 任意写 CSR 让 compare 通过
     - 不允许
     - 只能用于明确 custom CSR/model gap

§38  性能与日志成本
-------------------

cosim 是动态回归中最昂贵的组件之一。每条退休指令都可能触发 Spike step、状态同步和
compare；打开 ``UVM_HIGH`` 后，日志量会随指令数线性增长。回归策略上应把详细日志留给
短 directed 或单个 failing seed，批量 sign-off 使用默认日志等级。

.. list-table:: 成本来源
   :header-rows: 1
   :widths: 26 34 40

   * - 成本
     - 来源
     - 控制方式
   * - Spike step
     - 每条退休指令
     - 控制 cosim-enabled test 数量和 seed 数
   * - TLM FIFO
     - trace/probe/AXI transaction
     - 避免无意义 monitor spam
   * - UVM log
     - per-instruction ``UVM_HIGH``
     - failing seed 局部打开
   * - Memory notify
     - store/AMO/AXI beat split
     - 保持 monitor transaction 简洁
   * - Reset recovery
     - cleanup/init/reload
     - 只在需要 reset-in-test 时触发

§39  与 riscv-dv 的关系
-----------------------

riscv-dv 生成的是指令流，scoreboard 提供的是架构参考比较。riscv-dv case mailbox PASS
只能说明程序自检通过；cosim scoreboard PASS 才说明同一指令流在 DUT 和 Spike 上的
architectural state 一致。当前 riscv-dv 370/395 (93.67%) 应按这个口径解读。

.. list-table:: riscv-dv 到 cosim 的数据链
   :header-rows: 1
   :widths: 28 34 38

   * - 阶段
     - 输出
     - scoreboard 依赖
   * - instr gen
     - ASM/ELF/HEX
     - binary loader 和 early load
   * - RTL sim
     - trace/probe/AXI/log
     - 三路 FIFO 输入
   * - Spike cosim
     - step/CSR/memory state
     - architectural reference
   * - log check
     - pass/fail/mismatch
     - sign-off stage 统计
   * - waiver
     - cosim-disabled 或 known limitation
     - fail-rate ceiling 和例外解释

§40  本章维护结论
-----------------

cosim scoreboard 是 EH2 UVM 验证平台中最重要的动态质量门。它把 trace、probe 和 AXI4
三种观察面统一到 Spike reference model，覆盖 PC、GPR、CSR、trap、debug/interrupt 和
memory side effect。文档维护时应优先保护三件事：输入队列的真实性、Spike 状态不被
错误污染、report 结果与 sign-off gate 口径一致。只要这三件事成立，scoreboard 的
失败就是有价值的失败，而不是脚本噪声。

§41  Debug/interrupt 优先级样例
-------------------------------

debug、NMI、regular interrupt 和 synchronous exception 同时出现时，scoreboard 的任务
不是重新实现 RTL TLU，而是把 DUT 已观察到的状态按 Spike 需要的顺序送入 ISS。若顺序
错误，最常见表现是第一条 trap PC 还对得上，但后续 ``mcause``、``mepc`` 和 debug mode
持续漂移。

.. list-table:: 优先级相关输入
   :header-rows: 1
   :widths: 26 34 40

   * - 输入
     - 采样来源
     - compare 风险
   * - debug request
     - trace/probe debug state
     - debug entry 优先级错会造成 PC/mcause mismatch
   * - NMI level
     - ``item.nmi``
     - NMI 与 regular interrupt 竞争
   * - NMI interrupt
     - ``item.nmi_int``
     - edge/level 解释错误导致重复 trap
   * - MIP
     - ``prev_mip`` / ``item.mip``
     - pending 位不同步导致 Spike trap 时机不同
   * - mcycle
     - trace item
     - 性能计数器相关 CSR compare

§42  CSR compare 与 custom CSR
------------------------------

EH2 custom CSR 是 cosim 的重点差异域。Spike 原生不一定认识 EH2 vendor CSR，因此
scoreboard 初始化阶段预注册 28 个 custom CSR；compare 阶段再按 trace/probe 中的 CSR
行为同步或检查。这个机制必须有明确边界：预注册是模型补齐，不是 mismatch 豁免。

.. list-table:: CSR compare 风险
   :header-rows: 1
   :widths: 28 34 38

   * - 风险
     - 表现
     - 处理
   * - CSR 未预注册
     - Spike CSR API 返回错误
     - 更新 preregister header 和文档
   * - WARL 掩码差异
     - 写后读值不同
     - 明确 WARL mask/fixup，不直接放宽 compare
   * - debug CSR 时序
     - debug entry/exit 附近 mismatch
     - 查 debug request 通知顺序
   * - counter CSR
     - mcycle/minstret 不一致
     - 查 step 前 ``set_mcycle`` 和 retire count
   * - PMP CSR
     - PMP/ePMP 配置差异
     - 与 PMP coverage/formal 交叉确认

§43  End-of-test 边界
---------------------

mailbox PASS、trace queue drain 和 scoreboard report 并非同一时刻发生。裸机程序写入
PASS 后，DUT 可能仍有少量 sideband 或 monitor item 在 TLM FIFO 中。scoreboard 因此在
report phase 统一判断 mismatch 和 pending queue，而不是在 mailbox event 触发时立即
结束 compare。

.. code-block:: text

   DUT store mailbox PASS
      |
      +-- TB top event
      |
      +-- LSU AXI4 monitor publishes txn
      |
      +-- trace/probe monitor may still drain item
      |
      v
   UVM report_phase -> scoreboard summary -> final status

.. list-table:: End-of-test 检查
   :header-rows: 1
   :widths: 28 34 38

   * - 检查
     - 预期
     - 异常
   * - mailbox done
     - PASS event 出现
     - 程序未到结束 marker
   * - mismatch count
     - total 0
     - architectural compare 失败
   * - step count
     - 大于 0
     - cosim 未实际运行
   * - pending trace
     - 可解释或为 0
     - 可能等待 memory/async hint
   * - pending LSU
     - 可解释或为 0
     - 可能有未消费 store side effect

§44  与 log checker 的配合
--------------------------

scoreboard 在 UVM log 中输出 RESULT 和 mismatch；脚本 ``check_logs.py`` 再从仿真日志
提取 pass/fail、fatal/error、mailbox 和 simulator-specific 结果。二者分工不同：
scoreboard 判断 architectural compare，log checker 负责把仿真输出转成回归统计。

.. list-table:: Scoreboard 与 log checker
   :header-rows: 1
   :widths: 28 34 38

   * - 对象
     - 负责
     - 不负责
   * - Scoreboard
     - Spike step/compare、mismatch report
     - 解析 simulator pass banner
   * - TB mailbox
     - PASS/FAIL event 和 console 输出
     - 判断 cosim 是否匹配
   * - ``check_logs.py``
     - 日志模式匹配、NC/VCS banner 差异
     - 解释每条指令 mismatch 根因
   * - ``signoff.py``
     - stage 汇总、fail-rate ceiling
     - 替代 UVM 组件内部 compare

§45  Checklist：scoreboard failure triage
------------------------------------------

遇到 scoreboard failure 时，按以下顺序收集证据：

1. 保存 failing seed、test name、binary path 和 simulator 命令。
2. 查看 scoreboard report：trace/probe/AXI counts、step count、mismatch count。
3. 定位第一条 mismatch，而不是最后一屏日志。
4. 判断类型：PC、GPR、CSR、trap、memory、timeout。
5. 打开对应波形：trace packet、DUT probe、LSU AXI4、debug/interrupt pins。
6. 对照 Spike notify 顺序和 memory notify 32-bit 拆分。
7. 若是已知限制，确认 waiver/ADR 是否存在且仍适用。

这个 checklist 的目的，是把 scoreboard 失败转化为可修复的问题陈述，而不是把它归类为
“随机失败”。

§46  Release 摘要中的 scoreboard 口径
--------------------------------------

在 release note 或管理层摘要中，scoreboard 不应被写成“仿真脚本的一部分”。更准确的
表述是：scoreboard 是动态 architectural reference gate，负责把 DUT 退休 trace、
内部 probe hint 和 LSU AXI4 side effect 与 Spike ISS 逐条对齐。

.. code-block:: text

   Cosim scoreboard consumed EH2 trace/probe/LSU AXI4 streams and compared
   PC, GPR, CSR, trap/debug/interrupt state, and memory side effects against
   Spike. The 2026-05-19 VCS demo reported riscv-dv 370/395 (93.67%) and
   directed 40/40 with the documented waiver policy.

中文摘要可写为：

.. code-block:: text

   Cosim scoreboard 将 EH2 trace、DUT probe 和 LSU AXI4 三路观察面送入 Spike
   参考模型，逐条比对 PC、GPR、CSR、trap/debug/interrupt 和 memory side effect。
   当前 VCS demo 的 riscv-dv 结果为 370/395 (93.67%)，directed 为 40/40。

§47  Scoreboard 与可重现实验
-----------------------------

scoreboard failure 必须能被可重现实验支撑。报告失败时至少记录 seed、binary、testlist、
plusarg、cosim cfg 和 git SHA。若只保存末尾日志，后续很难重建 Spike memory map 或
trace/probe/AXI 的相对时序。

.. list-table:: 可重现实验要素
   :header-rows: 1
   :widths: 28 34 38

   * - 要素
     - 示例
     - 用途
   * - Test name
     - ``riscv_arithmetic_basic_test``
     - 找到 test class/sequence
   * - Seed
     - ``--seed <n>``
     - 重现 riscv-dv stream 和 UVM randomization
   * - Binary path
     - ``+bin=...hex``
     - 重载 DUT/Spike memory
   * - Plusargs
     - ``MEM_ICCM_BASE``、debug/cosim flags
     - 还原 memory map 和日志等级
   * - Simulator
     - VCS
     - 对齐 sign-off 主线
   * - Git SHA
     - 当前 workspace commit
     - 区分源码版本

§48  Scoreboard 退出条件
------------------------

一个 scoreboard issue 可以关闭，至少要满足以下条件之一：

* RTL bug 已修复，并有 failing seed 重新通过。
* Scoreboard bug 已修复，并通过负向/正向样例证明不会掩盖 mismatch。
* Spike model gap 已通过 custom CSR/model fixup 解决，并有 ADR 记录边界。
* Test stimulus 错误已修复，原失败不再出现。
* 已确认不可支持或阶段性限制，并进入 waiver/ADR，且 sign-off fail-rate ceiling 仍满足。

关闭 issue 时应附上 Sphinx 章节链接和命令输出摘要，避免后续复审只能依赖口头结论。

§49  与 double-fault detection scoreboard 的边界
-------------------------------------------------

env 中 trace monitor 除了连接 cosim scoreboard，还连接 double-fault detection
scoreboard。两者都消费 trace item，但验证意图不同：cosim scoreboard 做 Spike
architectural compare；double-fault detection scoreboard 关注特定异常/故障模式的
trace 序列合法性。本章只覆盖 cosim scoreboard，不把 DFD 逻辑混入 Spike compare。

.. list-table:: Cosim 与 DFD scoreboard 对照
   :header-rows: 1
   :widths: 28 34 38

   * - 维度
     - Cosim scoreboard
     - DFD scoreboard
   * - 输入
     - trace/probe/LSU AXI4
     - trace monitor
   * - 参考
     - Spike ISS
     - EH2 double-fault 规则
   * - 输出
     - mismatch、step count、pending queue
     - double-fault sequence error
   * - 主要 stage
     - cosim、riscvdv、directed
     - directed、fault/exception 场景
   * - 失败定位
     - PC/GPR/CSR/trap/memory
     - exception ordering 和 fault nesting

§50  多源输入的 backpressure 风险
---------------------------------

scoreboard 的三个 FIFO 都是 analysis FIFO。producer 侧 monitor 不应因为 scoreboard
暂时等待 memory 或 async hint 而阻塞 DUT 仿真；consumer 侧通过 pending queue 管理
乱序到达。这个结构降低了 monitor 对仿真时序的干扰，但引入了队列积压风险，因此
report 中 high watermark 和 pending count 必须保留。

.. list-table:: 队列积压含义
   :header-rows: 1
   :widths: 28 34 38

   * - 队列
     - 积压原因
     - 处理
   * - ``trace_fifo``
     - scoreboard 处理慢或 reset 边界
     - 看 step rate 和 reset flush
   * - ``pending_trace_q``
     - 等待 memory/async hint
     - 看对应 LSU AXI4 或 ``wb_tag``
   * - ``dut_probe_fifo``
     - probe hint 产生密集
     - 看 async-only 过滤是否正确
   * - ``async_wb_q``
     - hint 已到但 trace 未匹配
     - 检查 thread/source/tag
   * - ``lsu_axi_fifo``
     - AXI4 monitor 活动多于 trace 消费
     - 检查 store coalescing 和 memory matching
   * - ``pending_mem_access_q``
     - memory side effect 未被 trace 消费
     - 检查 end-of-test 或 address/strobe 匹配

§51  Negative test 的 scoreboard 期望
-------------------------------------

负向测试不是让 scoreboard 静默通过所有异常，而是让 DUT 和 Spike 在相同异常语义下
一致。例如 access fault、illegal instruction、debug halt、NMI 或 PMP fault，DUT
应退休或 trap 到与 Spike 一致的 architectural state。scoreboard 需要看到相同的 PC、
trap cause、CSR side effect 和必要的 memory error notification。

.. list-table:: 负向场景 compare 重点
   :header-rows: 1
   :widths: 28 34 38

   * - 场景
     - compare 重点
     - 常见问题
   * - Illegal instruction
     - mcause、mepc、mtval
     - trace exception code 与 Spike 解码不同
   * - Access fault
     - AXI4 error notify、trap cause
     - response error 未进入 Spike notify
   * - Debug halt
     - debug priority、PC、dcsr/dpc
     - halt/run pin 与 trace debug state 不一致
   * - NMI
     - NMI vector、mepc、mcause
     - NMI level/edge 同步错误
   * - PMP fault
     - iside/dside fault、CSR/PMP state
     - PMP cfg 与 Spike model 不一致

§52  与随机稳定性的关系
-----------------------

riscv-dv 随机回归中的 scoreboard failure 要先确认是否 deterministic。若同一 seed 稳定
复现，优先按真实 bug 处理；若 seed 不稳定，需要排查 reset race、UVM sequence 并发、
AXI4 monitor 同拍采样和 DPI 初始化状态。不要把不稳定失败直接登记为 waiver。

.. list-table:: 随机稳定性检查
   :header-rows: 1
   :widths: 28 34 38

   * - 检查
     - 方法
     - 结论
   * - 同 seed 重跑
     - 连续运行 3 次
     - 判断 deterministic
   * - 开详细日志
     - ``+enable_cosim_debug=1``
     - 定位首个漂移点
   * - 开波形
     - 单测波形通道
     - 查看 trace/probe/AXI 相对时序
   * - 固定 plusarg
     - memory map、binary、verbosity
     - 排除配置漂移
   * - 对比 non-cosim
     - 关闭 cosim 观察 mailbox
     - 区分 DUT hang 和 compare 问题

§53  最终维护摘要
-----------------

本页达到阶段 5 完成标准时，应满足：数据流图能解释三路输入，源码片段覆盖 FIFO、
pending trace、memory notify、Spike step、init/report，Ibex 对照说明 RVFI-centered
和 trace/probe/AXI-centered 的差异，sign-off 数据使用 2026-05-19 VCS demo 口径，并且
不包含会把 mismatch 静默放过的描述。后续任何 scoreboard 文档修改都应先问一个问题：
这段文字是否仍能帮助工程师定位第一条 architectural divergence。
