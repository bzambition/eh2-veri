.. _adr-0016:

ADR-0016: NUM_THREADS=2 Co-simulation Support
================================================

:status: Accepted
:source: docs/adr/0016-multi-hart-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：ADR-0003 记录了 NUM_THREADS=2 cosim 不可行的限制。随着平台成熟，需要
正式支持 EH2 的双线程 cosim。此前 SpikeCosim 仅创建一个 processor 实例，无法同时
跟踪两个 hart。多线程验证只能依赖 mailbox + 自检 cooperative test，验证完整性
弱于 single_thread。

**决策** ：第一，SpikeCosim 创建 2 个 ``processor_t`` 实例（当 num_threads==2）。
第二，每个 hart 独立维护 processor state、pending_dside_accesses、mip/prev_mip。
第三，DPI 接口通过 thread_id 参数路由到对应 hart。第四，scoreboard 按
``trace_seq_item.thread_id`` 路由到对应比对路径。第五，每个 hart 独立维护
pending_trace_q 和 async_wb_q。

**后果** ：双线程配置现在有完整的 cosim 闭环，与单线程路径共用同一 scoreboard 逻辑。
但 Spike 内存仍然共享——两个 hart 看同一个地址空间。PIC 中断仲裁在 Spike 中不模型，
每个 hart 独立调用 set_mip。这一决策使得 signoff full 在 dual_thread 配置下可以
要求 cosim stage 通过，与 single_thread 配置达到同等的验证完整性水平。该 ADR 替代
了 ADR-0003 中的方案 C（持续禁用），选择了类似方案 A（多 hart Spike）的路径，将
之前估计的 5--10 天工作量付诸实施。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - NUM_THREADS=2 per-hart Spike 路由
     - :file:`docs/adr/0016-*`
   * - 代码路径 1
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/cosim/spike_cosim.h`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv`
     - 当前仓库实际文件


签核与边界
----------

当前 SpikeCosim 可以按 thread_id 维护 per-hart state；不过 2026-05-19 sign-off 主线对 cosim-disabled 条目仍通过 waiver 管控，相关风险在 ADR-0017 和 waiver 文件中登记。

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

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：确认本页 ADR 编号、标题和 Sphinx 页面都能在索引中找到。

.. code-block:: bash

   sed -n "1,160p" docs/adr/INDEX.md
   ls docs/sphinx_cn/source/appendix_d_adr

**进阶题**：检查 ADR 是否说明状态、决策后果，以及后续修订时应新增 superseding ADR。

.. code-block:: bash

   rg -n "Status:|Date:|Decision|Consequences|supersed" docs/adr docs/sphinx_cn/source/appendix_d_adr | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 这条 ADR 的状态、日期和决策边界是什么？
2. 它解决的是 cosim、coverage、formal、synthesis、LEC、RVFI 还是 waiver 问题？
3. 该 ADR 对应的实现文件或 sign-off gate 是哪一个？
4. 当前 VCS/URG 默认 release 参考与 NC/Incisive 备选路径是否被正确区分？
5. 若该 ADR 需要修订，是否应新增 superseding ADR 而不是静默改写历史？
