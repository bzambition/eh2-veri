:orphan:

架构决策记录（ADR）
==========================================================================================

本章汇总 EH2 UVM 验证平台落地过程中跨多个文件、影响多个组件的关键架构决策。
每条决策对应仓库 ``docs/adr/`` 下一份独立的 Markdown 文档，文件按四位数字
顺序编号，从 ``0001`` 开始递增。

ADR 体系简介
------------------------------------------------------------------------------------------

ADR（Architecture Decision Record）的目的不是事后写文档，而是 **把一次决策
固定下来**：让后来者看到当时的上下文、备选方案、选择的理由和已知后果。
EH2 验证平台采用以下约定：

* **粒度** ：一条 ADR 描述一个会跨越多个文件（RTL / UVM / Spike / 脚本）
  的设计决策。仅影响单文件的局部实现选择不需要写 ADR。
* **位置** ：``docs/adr/NNNN-<title>.md`` 。``NNNN`` 是四位数字。
* **状态字段** ：每条 ADR 顶部声明状态。常用状态如下表。
* **不可重排** ：编号一旦分配不再变更；废弃的决策保留原文件，状态字段标
  ``Superseded by ADR-NNNN`` 。

.. list-table:: ADR 状态字段
   :header-rows: 1
   :widths: 20 80

   * - 状态
     - 含义
   * - ``Proposed``
     - 提案中，还未实施。可以在 PR 评审中修改。
   * - ``Accepted``
     - 已经被采纳并落地，当前实现遵循该决策。
   * - ``Superseded``
     - 决策已被新的 ADR 取代，但保留作历史。
   * - ``Rejected``
     - 经评估后未采纳，留作"曾经讨论过"的记录。
   * - ``Deprecated``
     - 实施过但已废弃，需要逐步从代码中清理。

ADR 与 ``CONTEXT.md`` 的关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

仓库根的 ``CONTEXT.md`` 是 **顶层语境** ：定义术语、模型、目录约定与当前
风险一览。它回答 *"项目长什么样"*。

ADR 是 **单独决策点** ：每条只解释一个变化。它回答 *"为什么这样做、
当时考虑过什么备选"*。

两者关系：

* ``CONTEXT.md`` 在每次 Phase 完成时更新，反映 *当前真相*。
* ADR 在做出决策时写下，反映 *当时真相*，之后只有状态字段会变。
* 风险编号（``RISK-N`` ）在 ``CONTEXT.md`` 维护，ADR 在标题或链接里
  引用风险编号建立交叉索引。

当前 ADR 一览
------------------------------------------------------------------------------------------

.. list-table:: ADR 列表（截至 2026-05-07）
   :header-rows: 1
   :widths: 8 36 18 38

   * - 编号
     - 标题
     - 状态
     - 涉及范围
   * - 0001
     - cosim 数据通路 — trace 包 + probe 接口
     - Accepted（部分被 ADR-0004 取代）
     - cosim 双通道、scoreboard
   * - 0002
     - AXI4 总线 passive monitoring + slave behavioral mem
     - Accepted
     - axi4_agent、tb_top
   * - 0003
     - NUM_THREADS=1 cosim 边界
     - Accepted（短期）
     - cosim 范围、testlist 标签
   * - 0004
     - RTL trace 包增加 verification-only rd_addr/rd_wdata
     - Proposed（Phase 1 实施完成，待状态更新）
     - RTL trace、scoreboard 简化
   * - 0005
     - Spike-cosim 接受 EH2 store wider WSTRB
     - Accepted
     - ``dv/cosim/spike_cosim.cc``

.. note::

   ADR-0004 文件中的状态字段当前仍写 ``Proposed`` ，但 Phase 1 已经完成，
   ``CONTEXT.md`` 中 RISK-3 标记为"已修"。下一次接触该文件时应把状态
   字段更新为 ``Accepted`` 。

ADR-0001：cosim 数据通路 — trace 包 + probe 接口
------------------------------------------------------------------------------------------

* 文件：``docs/adr/0001-cosim-via-trace-and-probe.md``
* 日期：2026-05-04
* 状态：Accepted（被 ADR-0004 部分取代）

**问题**

EH2 RTL **没有 RVFI 接口** 。Ibex 的 cosim 闭环依赖 RVFI：每条 retired
指令一个完整快照（rd_addr / rd_wdata / mem_* / csr_* 全部 27 个信号），
scoreboard 直接拿 RVFI item 喂 Spike 一比一对照。

EH2 RTL 只有 trace 包（PC + insn + exception + interrupt + tval），
**没有 rd_addr / rd_wdata** 。要做 cosim 必须从其它地方拿到寄存器写回数据。

**决策**

通过两条独立通道在 UVM monitor 层重建 RVFI 等价信息：

1. **trace 通道** ：``eh2_trace_monitor`` 监视 RTL trace 包，给出
   PC + insn + exception。
2. **probe 通道** ：``eh2_dut_probe_monitor`` 通过 hierarchical reference
   直接读 DUT 内部写回信号 (``wbd.i0v/i1v``、``i0_result_wb``)，再加
   div cancel / NB-load 异步通道。
3. **scoreboard** 在两条通道之间做 per-slot 队列匹配。

**后果**

* 优点：不需要改 RTL，工作量集中在 UVM 层。
* 缺点：同周期同步靠 ``#0`` 延迟硬撑、wb 与 trace 对应关系靠启发式
  ``wb_search_depth`` 窗口、scoreboard 复杂度爆炸（1026 行 vs Ibex
  等价 361 行）。

**演进** ：ADR-0004 提议在 RTL trace 包中增加 rd_addr / rd_wdata，
让 trace 通道直接携带写回信息，废弃 probe 通道的写回主路径。

ADR-0002：AXI4 总线 passive monitoring
------------------------------------------------------------------------------------------

* 文件：``docs/adr/0002-axi4-passive-monitoring.md``
* 日期：2026-05-03
* 状态：Accepted

**问题**

EH2 有 4 个 AXI4 端口（IFU 取指、LSU 读写、SB 调试系统总线、DMA），
数据宽度 64-bit。Ibex 用简单 ``req/gnt/rvalid`` ，由
``mem_intf_response_agent`` 主动驱动响应。EH2 的 4 通道 AXI4 在工业
仿真里通常配合行为级 slave，激励测试主要靠总线握手时序，对错误注入
需求暂不强烈。

**决策**

* AXI4 agent 设为 **passive 模式** ，仅监视器，不驱动。
* TB top 实例化 4 个 ``axi4_slave_mem`` 行为级模型，地址空间预映射。
* monitor 把 AW/AR 与 W/R/B 通道按事务关联，发出 ``axi4_seq_item``
  （包含 burst 全部 beats）。
* LSU 通道挂到 cosim agent 的 ``dmem_port`` ，给 Spike 通知内存访问。

**后果**

* 优点：行为级 mem 简化 TB；passive agent 跟真实 SoC 解耦；64-bit
  beat 数据完整保留（cosim 通知时按 32-bit 分两次调用）。
* 缺点：不能注入 AXI 错误响应、不支持 lock / exclusive、无协议合规
  assertion。
* 待办：Phase 5 增加 active driver（详见
  ``.scratch/platform-industrialization/issues/40-axi4-active-driver.md`` ）。

ADR-0003：NUM_THREADS=1 cosim 边界
------------------------------------------------------------------------------------------

* 文件：``docs/adr/0003-num-threads-cosim-scope.md``
* 日期：2026-05-04
* 状态：Accepted（短期）

**问题**

EH2 可配置 NUM_THREADS=1 或 NUM_THREADS=2（两个硬件线程，每个 hart
独立 PC / regfile / CSR）。

Spike 的 ``processor_t`` 实例只能模型一个 hart。``SpikeCosim`` 当前只
创建一个 processor，无法同时跟踪两个 hart。

**决策**

短期：cosim **仅支持 NUM_THREADS=1** 。

* ``eh2_configs.yaml`` 的 ``dual_thread`` profile 必须 ``+disable_cosim=1`` 。
* testlist 里多线程 test 必须标 ``cosim: disabled`` 。
* signoff full 在 dual_thread 配置下不要求 cosim stage。

**备选方案**

.. list-table::
   :header-rows: 1
   :widths: 8 50 14 28

   * - 方案
     - 描述
     - 工作量
     - 评估
   * - A
     - SpikeCosim 创建两个 ``processor_t`` ，按 thread_id 路由 trace item
     - 5–10 天
     - Phase 5 评估
   * - B
     - 双实例 SpikeCosim 并行，trace_monitor 按 tid 分流
     - 3–5 天
     - Phase 5 评估
   * - C
     - 持续禁用，dual_thread 仅靠 mailbox + 自检 cooperative test
     - 0 天
     - **当前选择**

**升级触发条件**

* 真实部署需要 dual_thread 量产，或
* single_thread 已通过 sign-off，或
* 出现 dual_thread 特有 bug 通过其它手段无法定位。

ADR-0004：RTL trace 包增加 verification-only rd_addr/rd_wdata
------------------------------------------------------------------------------------------

* 文件：``docs/adr/0004-rtl-rvfi-equivalent-trace.md``
* 日期：2026-05-06
* 状态：Proposed（Phase 1 已实施，待文档同步）
* 取代：ADR-0001（部分）

**问题**

ADR-0001 的双通道架构在实践中产生 cosim 闭环不收敛问题：

* ``eh2_cosim_scoreboard.sv`` 膨胀到 1026 行（Ibex 等价仅 361 行）。
* 引入 ``WB_SEARCH_DEPTH`` band-aid 限制启发式搜索。
* NB-load / DIV cancel / interrupt-killed wb 等异步事件需要专门 corner
  处理。

根因：trace 通道与 wb 通道 **没有可靠对应关系** ，靠 ``#0`` 延迟 + rd
匹配 + 搜索窗口启发式。

**决策**

参考 Ibex ``ibex_top_tracing.sv`` 的做法，在 EH2 RTL 层把
verification-only 信号引出到 trace 包：

1. ``rtl/design/include/eh2_def.sv`` 中 ``eh2_trace_pkt_t`` 增加：
   ``trace_rv_i_rd_addr_ip`` / ``trace_rv_i_rd_wdata_ip`` /
   ``trace_rv_i_rd_valid_ip`` （每个 slot 一份）。
2. ``rtl/design/dec/eh2_dec_decode_ctl.sv`` 增加 wb1 阶段的 wdata /
   waddr / wen 寄存器（4 个 ``rvdffe`` ，与现有 ``i0wb1instff`` /
   ``i1wb1instff`` 流水对齐）。
3. ``rtl/design/dec/eh2_dec.sv`` tracep 块新增 assign：将 wb1 寄存器
   输出连入 trace_pkt 新字段。
4. UVM 侧：``eh2_trace_intf.sv`` 增加同名信号，``eh2_trace_monitor.sv``
   直接采样 rd_addr / rd_wdata 填入 trace_seq_item，scoreboard 删除
   ``pending_wb_q``、``wb_search_depth``、``run_cosim_probe`` 主路径。

**影响评估**

.. list-table::
   :header-rows: 1
   :widths: 18 52 18

   * - 维度
     - 影响
     - 风险
   * - 功能行为
     - 0（纯组合 + 已有信号 + verification 输出）
     - 无
   * - 时序
     - 4 个新 ``rvdffe`` （wb1 阶段）
     - 低
   * - 综合面积
     - 约 +150 FF（4 × 37 bit）
     - 可忽略
   * - 验证
     - 大幅简化 cosim scoreboard
     - 正向
   * - 上游兼容
     - trace_pkt 是内部 struct
     - 低（可用 ``RV_DV_VERIFICATION`` ifdef 包裹）

**验证标准**

* ``make compile SIMULATOR=vcs`` 通过。
* smoke + 5 个 riscv-dv 随机 test cosim 全部 ``mismatch_count == 0`` 。
* ``make signoff PROFILE=full`` 全 stage PASS。
* ``WB_SEARCH_DEPTH`` 从代码中删除。
* ``pending_wb_q`` 从 scoreboard 中删除（仅留 nb_load 异步队列）。

ADR-0005：Spike-cosim 接受 EH2 store wider WSTRB
------------------------------------------------------------------------------------------

* 文件：``docs/adr/0005-spike-cosim-store-wider-wstrb.md``
* 日期：2026-05-06
* 状态：Accepted（Phase 3 实施）

**问题**

EH2 LSU 对子字节存储（SB / SH）在 AXI4 输出�� **不是** 只 set 对应
字节的 WSTRB 位，而是：

* 把整个 4 字节 word 的 WSTRB 都置 1 (``4'b1111``)。
* 通过内部 read-modify-write 把 *非目标字节* 填回原 mem 内容。
* 输出 64-bit beat data 时只有目标字节是新值。

这是合法硬件设计——AXI4 协议允许整 word write 不影响其它字节内容
（因为 RMW 已经把它们设回旧值）。但 spike-cosim 默认假设 store 的
WSTRB **严格等于** ISA 期望的 byte mask。

具体表现：执行 ``sb a2,-217(t0)`` ，DUT 在 AXI4 上发出
``wstrb=4'b1111`` ，cosim 把它传给 spike 的 ``mmio_store`` ，spike
报错：

.. code-block:: text

   Cosim mismatch: DUT generated store at address 81000844
                   with BE f but BE 1 was expected

**决策**

修改 ``dv/cosim/spike_cosim.cc:check_mem_access`` 的 store-side BE
检查，采用与 load-side 一致的 *超集判断* 语义：

.. code-block:: cpp

   // 之前（store 严格相等）：
   if (store && expected_be != top_pending_access_info.be) {
     // error: BE mismatch
   }

   // 现在（store 超集容忍）：
   if (store && ((expected_be & ~top_pending_access_info.be) != 0)) {
     // error: ISA expected bytes not covered by DUT BE
   }

也就是说：只要 DUT BE **包含** ISA 期望的 byte mask 就接受。多出
的字节认为是 EH2 LSU 的内部 RMW 行为，不影响架构正确性。

**后果**

* 优点：EH2 SB / SH 不再误报 BE mismatch；BE 检查 load / store
  对称化。
* 缺点：失去对"DUT 多写额外字节但内容错"的检测能力——但 data 检查
  仍然工作（``data & expected_be_bits`` mask 后比对），ISA 期望字节
  的内容仍严格验证。
* 已知 trade-off：假设 EH2 RTL 的 RMW 不破坏额外字节。

写新 ADR 的指南
------------------------------------------------------------------------------------------

发起一条新 ADR 的步骤：

1. **判断粒度** ：影响是否跨多个文件、是否涉及 RTL / cosim / 流程？
   只动单个 UVM 类不需要 ADR，写 commit message 即可。
2. **分配编号** ：``ls docs/adr/`` 找最大编号 +1。
3. **复制模板** ：以现有 ADR 为模板，填写以下字段。

   .. code-block:: text

      # ADR-NNNN: <一句话标题>

      - 状态：Proposed
      - 日期：YYYY-MM-DD
      - 相关：<可选，关联 RISK-N / 其它 ADR / issue>

      ## 上下文
      <为什么需要做决策？现状有什么问题？>

      ## 决策
      <选择了什么？>

      ## 备选方案
      <考虑过哪些方案？为什么没选？>

      ## 后果
      ### 正面
      ### 负面

      ## 验证标准
      <怎么知道决策落地正确？>

4. **PR 评审** ：在 PR 描述中链接 ADR 文件，要求至少一位 reviewer
   approve 状态从 ``Proposed`` → ``Accepted`` 。
5. **状态维护** ：决策实施后改 ``Accepted`` ；被取代时改
   ``Superseded by ADR-NNNN`` 并同步更新新 ADR 的"取代"字段。

.. note::

   ADR **不是** progress log。Phase 完成报告写在
   ``.scratch/platform-industrialization/PHASEN_PROGRESS.md`` 。
   ADR 只记录 *决策点*，不记录 *实施过程*。

ADR 与 issue tracker 的衔接
------------------------------------------------------------------------------------------

* 一条 ADR 可以引用一个或多个 issue 作为 *实施载体*——例如 ADR-0004
  的实施全部追踪在 ``.scratch/platform-industrialization/issues/01``
  到 ``06`` 这 6 张 ticket。
* issue 是 *任务*，ADR 是 *决策*。同一个决策可能拆分到 N 张 issue 上
  并行推进。
* issue 标题与 ADR 编号建立交叉引用，方便 ``grep -r ADR-000N`` 找到
  全部相关变更。
