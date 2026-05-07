风险登记册
==========

本章登记 EH2 UVM 验证平台已识别的全部风险。每条风险有唯一编号
``RISK-N``，从 1 开始递增；编号一旦分配不再回收。``CONTEXT.md`` 是单一
真相源，本章是 ``CONTEXT.md`` 风险表的 RST 化扩展，提供修复路径与
验证证据。

跟踪机制
--------

* **登记位置**：``CONTEXT.md`` 的 §6（已知 Risk）。
* **新风险归档**：在 ``CONTEXT.md`` 表中追加一行，编号 = 现有最大编号 + 1。
* **状态字段**：``OPEN`` / ``RESOLVED`` / ``BLOCKING`` / ``HIGH partial``
  等。RESOLVED 表示已修复并经过验证；OPEN 表示待解决；BLOCKING 表示
  影响 sign-off 范围（但有书面接受方案）。
* **修复证据**：每条 RESOLVED 风险都附 commit ID、PHASE_PROGRESS 文档、
  或测试通过率截图（保存在 ``.scratch/snapshots/``）。
* **风险与 ADR 的关系**：当某条风险通过架构调整解决时，在 ADR 中显式
  引用风险编号；反之，``CONTEXT.md`` 风险条目里也写明对应 ADR。

风险一览
--------

下表列出截至 2026-05-07 已识别的全部 14 条风险。

.. list-table:: 风险登记总表
   :header-rows: 1
   :widths: 8 12 14 36 30

   * - ID
     - 严重度
     - 状态
     - 描述
     - 缓解 / 修复
   * - RISK-1
     - HIGH
     - partial
     - EH2 自定义 CSR 18+ 个，Spike fixup 仅 4 个
     - 已 28 个 ``set_csr`` 静态注册；WARL fixup 待做（issue 14 ready-for-agent）
   * - RISK-2
     - MEDIUM
     - RESOLVED
     - AXI4 64-bit 数据 → cosim 截到 32-bit
     - 已 mitigate（split lower/upper word，每 beat 两次 mmio 调用）
   * - RISK-2b
     - MEDIUM
     - RESOLVED
     - EH2 sub-byte store 用 wider WSTRB（read-modify-write）
     - Phase 3 spike_cosim BE 语义放宽（见 ADR-0005）
   * - RISK-3
     - MEDIUM
     - RESOLVED
     - wb 与 trace 对齐脆弱，靠 ``wb_search_depth`` band-aid
     - Phase 1 RTL trace 加 RVFI 等价信号（见 ADR-0004）
   * - RISK-4
     - HIGH
     - BLOCKING
     - NUM_THREADS=2 不能 cosim
     - 已知限制；Phase 5 解锁（wontfix-now，见 ADR-0003）
   * - RISK-5
     - LOW
     - RESOLVED
     - NB-load wb 跨 slot 可能脱节
     - Phase 1 scoreboard 等 ``nb_load`` hint
   * - RISK-6
     - LOW
     - RESOLVED
     - interrupt 状态采样按 item 而非 cycle
     - RTL 设计上已正确（采样点选择正确）
   * - RISK-7
     - MEDIUM
     - RESOLVED
     - EH2 推测 div cancel 与架构 retire 区分
     - Phase 1 RTL ``dec_div_cancel_overwrite`` 信号 + scoreboard FIFO 消费
   * - RISK-8
     - MEDIUM
     - RESOLVED
     - load_store_test data RF 不同步
     - Phase 3 BE 语义放宽 + stream 修复后，1848 trace / 0 mismatch
   * - RISK-9
     - MEDIUM
     - OPEN
     - random_instr_test 中断 / 异常 cosim
     - 标 ``cosim:disabled``，需扩展 scoreboard 处理 mcause/mepc/mtval
   * - RISK-10
     - MEDIUM
     - OPEN
     - bitmanip zba/zbb 触发 RTL illegal-instr 异常率高
     - 标 ``cosim:disabled`` （exception 路径 cosim step 与 trace 速率不匹配）
   * - RISK-11
     - MEDIUM
     - OPEN
     - atomic SC.W RTL 写回与 Spike 分歧
     - 标 ``cosim:disabled`` （需 spike_cosim 加 atomic-store fixup）
   * - RISK-12
     - LOW
     - RESOLVED
     - 8 个 EH2 directed stream 全部生成空 ``instr_list``
     - Phase 3 新增 ``eh2_base_directed_stream``，post_randomize → gen_instr 桥接
   * - RISK-13
     - LOW
     - RESOLVED
     - ``check_logs`` 把 VCS banner overlap 误判为 UVM_FATAL
     - ``UVM_SUMMARY_LINE_RE`` 识别 summary 行的两种损坏形态
   * - RISK-14
     - HIGH
     - RESOLVED
     - ``libcosim.so`` 静默缺失 → 仿真启动报 DPI-DIFNF
     - ``compile_vcs`` 硬依赖 + ``NO_COSIM=1`` escape hatch

.. note::

   ``CONTEXT.md`` 中 RISK-7 的"状态"列写 ``OPEN``，但描述列已写"已修"
   并附 Phase 1 的实施路径。本章按"已修"处理（即 ``RESOLVED``），后续
   清理 ``CONTEXT.md`` 表格时同步更新该列。

按状态分类
----------

RESOLVED 风险（10 条）
~~~~~~~~~~~~~~~~~~~~~~

每条 RESOLVED 风险都有可复现的验证证据。下表给出修复路径与
验证方式。

.. list-table::
   :header-rows: 1
   :widths: 10 24 36 30

   * - ID
     - 修复路径
     - 验证证据
     - 关联文档
   * - RISK-2
     - cosim notify 拆 lower/upper 32-bit
     - smoke 6 trace / 0 mismatch
     - ADR-0002
   * - RISK-2b
     - ``spike_cosim.cc:check_mem_access`` BE 超集语义
     - ``load_store_test`` 1848 trace / 0 mismatch
     - ADR-0005、PHASE3_PROGRESS.md
   * - RISK-3
     - RTL trace 包加 ``rd_addr_ip`` / ``rd_wdata_ip`` /
       ``rd_valid_ip``；scoreboard 删除 ``WB_SEARCH_DEPTH`` /
       ``pending_wb_q``
     - sign-off full PASS（4/4 cosim，32/32 riscvdv）
     - ADR-0004、PHASE1_PROGRESS.md
   * - RISK-5
     - scoreboard 消费 nb_load hint 异步通道
     - ``arithmetic_basic`` 5/5 seed PASS
     - PHASE1_PROGRESS.md
   * - RISK-6
     - 采样点选 retire 时刻而非 cycle 边界
     - 中断测试稳定通过
     - cosim-correctness-analysis.md
   * - RISK-7
     - RTL 暴露 ``dec_div_cancel_overwrite``，scoreboard FIFO 消费
     - 推测 div cancel 不再误判 mismatch
     - PHASE1_PROGRESS.md
   * - RISK-8
     - 上游修复（Phase 3 BE 放宽）后不再复现
     - ``load_store_test`` 1848 trace / 0 mismatch
     - PHASE3_PROGRESS.md
   * - RISK-12
     - 新增 ``eh2_base_directed_stream``，post_randomize 桥接
     - directed_testlist 8/8 PASS
     - PHASE3_PROGRESS.md
   * - RISK-13
     - ``UVM_SUMMARY_LINE_RE`` 加两种损坏形态
     - regression 不再因 banner 误报 FATAL
     - PHASE3_SWEEP_PROGRESS.md
   * - RISK-14
     - ``compile_vcs`` 硬依赖 ``LIBCOSIM`` 文件 target
     - 缺 ``libcosim.so`` 时直接编译失败，不再静默
     - Makefile §192–248

OPEN 风险（3 条）
~~~~~~~~~~~~~~~~~

下面 3 条风险属于 cosim 范围外的 *已知差异*，目前以 ``cosim:disabled``
标签隔离 ，不阻塞 sign-off。每条都有对应的工作项追踪在
``.scratch/cosim-correctness/issues/`` 下。

.. list-table::
   :header-rows: 1
   :widths: 8 14 50 28

   * - ID
     - 影响范围
     - 工作项
     - 解锁条件
   * - RISK-9
     - random_instr_test 中断 / 异常路径
     - 扩展 scoreboard 处理 ``mcause`` / ``mepc`` / ``mtval`` 同步采样；
       考虑增加 trap-frame 比对逻辑
     - 风险消除并撤销 ``cosim:disabled``
   * - RISK-10
     - bitmanip zba / zbb illegal-instr
     - 调查 RTL illegal 检测时序与 cosim step 节拍的差距；
       可能需要 spike_cosim 在 illegal 路径上跳过 step
     - bitmanip suite 全部 PASS
   * - RISK-11
     - atomic SC.W
     - 在 ``spike_cosim`` 的 store-side fixup 中处理
       atomic-store 写回（Spike 默认 SC 永远 success
       的语义与 RTL 推测取消有出入）
     - atomic suite 全部 PASS

partial / BLOCKING 风险（2 条）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

有两条风险既不能简单标 RESOLVED 也不能拖到全部 OPEN —— 它们
**部分缓解**，但完整解决需要 Phase 5 阶段性投入。两者都已经过
工程评审并书面记录于 ADR。

**RISK-1 — EH2 自定义 CSR fixup 不全（HIGH partial）**

* 现状：18+ 个 EH2 自定义 CSR（``mscause`` / ``mrac`` / ``mfdc`` /
  ``meivt`` / ``meipt`` / ``mfdht`` / ``mfdhs`` / ``mhartstart`` /
  ``mnmipdel`` / ``mcgc`` / ``mpmc`` / ``mcpc`` / ``dmst`` /
  PIC CSRs / ...）。
* 已做：Phase 1+2 中已用 ``set_csr`` 静态注册 28 个，覆盖只读 / 常用
  写场景。
* 未做：WARL（write-any-read-legal）字段的位级 fixup —— 当 RTL
  把某些 bit 强制为 0/1，Spike 不模型该约束。
* 影响：CSR-密集 test（如 mrac 区域配置 / debug 控制流）可能产生
  cosim mismatch。
* 缓解策略：相关 test 通过 ``cosim:disabled`` 标签隔离。
* 解决方案：Phase 5 的"EH2 CSR fixup 设计"工单
  （``.scratch/cosim-correctness/issues/08-eh2-csr-fixup-design.md``）
  规划完整 WARL fixup 框架。

**RISK-4 — NUM_THREADS=2 不能 cosim（BLOCKING / wontfix-now）**

* 现状：``SpikeCosim`` 只创建一个 ``processor_t``，无法跟踪两个 hart。
* 接受方案：dual_thread 配置在 sign-off 中 *不要求* cosim stage，
  仅靠 mailbox + cooperative test 自检（详见 ADR-0003）。
* Release 影响：sign-off ``full`` profile 在 dual_thread 配置下
  缺失 cosim 闭环；single_thread 配置完整覆盖。
* 解锁触发：详见 ADR-0003 的"升级触发条件"，目前不阻塞 single_thread
  量产。

风险等级定义
------------

平台采用 5 级严重度：

.. list-table::
   :header-rows: 1
   :widths: 14 86

   * - 级别
     - 含义
   * - BLOCKING
     - 阻塞 sign-off 主路径，必须有书面接受方案才能保留 OPEN
   * - HIGH
     - 影响多个 test 的正确性，需要 Phase 内解决
   * - MEDIUM
     - 影响某个特定 test 类别，可用 ``cosim:disabled`` 隔离
   * - LOW
     - 仅影响告警 / 日志 / 边角行为，不影响 sign-off
   * - INFO
     - 已知差异，仅留作记录（当前没有此级别的条目）

定级原则：

1. **看影响范围**：是否跨 multiple test？是否影响主路径？
2. **看可隔离性**：能否通过 testlist 标签隔离？
3. **看修复成本**：能否在当前 Phase 内修复？

升降级流程
~~~~~~~~~~

* **升级**：发现新的影响面（如原以为只影响 1 个 test，调查后发现
  影响整个 suite），在 ``CONTEXT.md`` 表中改严重度并加注 *"升级
  原因 + 日期"*。
* **降级**：mitigation 后实际影响降低（如已有标签隔离），同样在
  ``CONTEXT.md`` 表中改严重度。
* **关闭**：找到根因 + 修复 + 验证证据，状态改 ``RESOLVED``，
  在风险条目末尾加 commit ID 与验证 test 名。

新风险登记模板
--------------

.. code-block:: text

   | RISK-N | <严重度> | <状态> | <一句话描述> | <已知缓解> |

记录后在 PR 评审里讨论以下三点：

1. 是否已经覆盖在已有 RISK-* 中？避免重复登记。
2. 是否需要立即缓解（如打 ``cosim:disabled`` 标签）？
3. 是否需要新开 issue 追踪修复？

风险与 sign-off 的关系
----------------------

sign-off ``full`` profile 要求 4 个 stage 全部 PASS：

.. list-table::
   :header-rows: 1
   :widths: 14 18 68

   * - Stage
     - 当前状态（2026-05-07）
     - 风险关联
   * - smoke
     - PASS
     - 无 OPEN 风险阻塞
   * - directed
     - PASS
     - RISK-12 已修
   * - cosim
     - PASS（4/4）
     - RISK-2/2b/3/5/7/8 全部 RESOLVED
   * - riscvdv
     - PASS（32/32）
     - RISK-9/10/11 用 ``cosim:disabled`` 隔离；
       11 个测试 ``skip_in_signoff`` 留 issue（RTL/binary 层 hang，
       不属 cosim 问题）

OPEN 风险通过 ``cosim:disabled`` 标签 *隔离* 而非 *忽略*——sign-off
通过不代表风险消失，仅代表风险 **当前不影响主路径正确性**。
