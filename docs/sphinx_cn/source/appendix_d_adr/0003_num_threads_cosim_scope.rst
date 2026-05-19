.. _adr-0003:

ADR-0003: NUM_THREADS=1 cosim 边界
====================================

:status: Accepted（短期，已被 ADR-0008/0016 取代）
:source: docs/adr/0003-num-threads-cosim-scope.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 可配置 NUM_THREADS=1 或 2（双硬件线程，每个 hart 拥有独立的 PC/regfile/CSR）。
Spike 的 ``processor_t`` 实例只能模型一个 hart。

§2  决策
---------

短期内 cosim 仅支持 NUM_THREADS=1。dual_thread profile 设 ``+disable_cosim=1`` ，
testlist 里多线程 test 标 ``cosim: disabled`` 。

**三种备选方案：**
- A：多 hart Spike（两个 processor_t，按 thread_id 路由，5-10 天工作量）
- B：双实例 SpikeCosim（两套实例并行，trace_monitor 按 tid 分流，3-5 天）
- C：持续禁用（0 天）— **初始选择**

§3  后果
---------

简化了短期工作量，但 dual_thread 验证完整性弱于 single_thread。
后续 **ADR-0016 已解锁 NUM_THREADS=2 cosim** ，此 ADR 已过期。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - NUM_THREADS cosim 历史边界
     - :file:`docs/adr/0003-*`
   * - 代码路径 1
     - :file:`docs/adr/0016-multi-hart-cosim.md`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
     - 当前仓库实际文件


签核与边界
----------

该 ADR 是历史约束记录，当前能力由 ADR-0016 更新。文档阅读时应把它理解为从 single-thread 限制过渡到 per-hart Spike 路由的背景，而不是当前 sign-off 限制。

统一签核口径为 2026-05-19 01:02 VCS 主线 demo：``9/9`` stages PASS，实跑覆盖率
``102/104`` （98.1%），LEC ``31635/31635`` PASS。覆盖率由 VCS ``simv.vdb``
经 URG 原生 dashboard 生成，编译时 :file:`dv/uvm/core_eh2/cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，指标为 ``line+tgl+assert+fsm+branch`` 五维，
不包含 cond 维度。NC/Incisive 是完整备选 simulator，可运行 smoke、regress、sign-off、demo 与覆盖率 cross-check；默认 release 参考仍为 VCS/URG。

参考章节
--------

* :ref:`adr_summary`
* :ref:`signoff_flow`
* :ref:`appendix_b_uvm/index`
* :ref:`appendix_c_tools/index`
