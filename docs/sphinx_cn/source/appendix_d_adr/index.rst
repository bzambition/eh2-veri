.. _appendix_d_adr_index:

附录 D — ADR 全文
==================

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本附录转载 20 条架构决策记录（ADR）的全文内容。每一条 ADR 原文在 :file:`docs/adr/NNNN-<title>.md` 中。
这些页面保留原 ADR 的历史语义，同时在每条末尾补充 2026-05-19 当前实现映射、
sign-off 证据和阅读边界。ADR 不是测试报告，不能用来替代
:ref:`signoff_flow` 或 :ref:`scripts_reference` 的脚本说明。

当前主线口径
------------

.. list-table::
   :header-rows: 1
   :widths: 24 36 40

   * - 项目
     - 当前值
     - 说明
   * - 默认 simulator
     - VCS
     - 与 Ibex UVM 主线一致；NC/Incisive 是完整备选 simulator，默认 release 参考仍为 VCS/URG
   * - coverage metrics
     - ``line+tgl+assert+fsm+branch``
     - 不使用 cond 维度
   * - coverage scope
     - ``+tree core_eh2_tb_top.dut``
     - 编译时 :file:`cover.cfg` DUT-only scope
   * - sign-off
     - ``9/9`` stages PASS
     - 2026-05-19 01:02 demo
   * - LEC
     - ``31635/31635`` PASS
     - block-level Formality gate
   * - coverage dashboard
     - OVERALL ``65.17%``
     - LINE ``95.05%``、BRANCH ``84.97%``、TOGGLE ``53.52%``、ASSERT ``33.33%``、FSM ``54.74%``

目录
----

* :ref:`adr-0001` — Cosim via trace and probe
* :ref:`adr-0002` — AXI4 passive monitoring
* :ref:`adr-0003` — NUM_THREADS cosim scope
* :ref:`adr-0004` — RTL RVFI-equivalent trace
* :ref:`adr-0005` — Spike cosim store wider WSTRB
* :ref:`adr-0006` — Atomic cosim fixup
* :ref:`adr-0007` — Interrupt cosim closure
* :ref:`adr-0008` — Debug cosim closure
* :ref:`adr-0009` — PMP/ePMP cosim closure
* :ref:`adr-0010` — CSR register model
* :ref:`adr-0011` — Compliance framework
* :ref:`adr-0012` — Formal verification strategy
* :ref:`adr-0013` — Synthesis toolchain
* :ref:`adr-0014` — Formal real runs
* :ref:`adr-0015` — RVFI adapter layer
* :ref:`adr-0016` — Multi-hart cosim
* :ref:`adr-0017` — Integrity cosim waiver
* :ref:`adr-0018` — wb_tag strict matching
* :ref:`adr-0019` — LEC tool-version limitation
* :ref:`adr-0020` — Block-level LEC closure
* :ref:`adr-template` — 后续 ADR 模板

.. note::

   每一条 ADR 的 :status: 字段与原 Markdown 文件中的状态一致。
   ADR 汇总见 :ref:`adr_summary` 。

与 Ibex 工业实现对照
--------------------

EH2 的 ADR 体系沿用 lowRISC Ibex 的核心工程习惯：把 simulator、coverage、
cosim、formal、compliance、lint 和 synthesis 的关键取舍写成可追溯决策，
而不是散落在脚本注释中。主要对照路径为
:file:`/home/host/ibex/dv/uvm/core_ibex/README.md`、
:file:`/home/host/ibex/dv/uvm/core_ibex/cover.cfg`、
:file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py` 和
:file:`/home/host/ibex/dv/uvm/core_ibex/yaml/rtl_simulation.yaml`。

EH2 的合理差异集中在双线程、AXI4、PIC/DMA/DMI/JTAG、RVFI adapter、CSR unit
子环境和 block-level LEC。阅读 ADR 时应优先区分「沿用 Ibex 模式」和「EH2
特有结构」：前者包括 VCS 主线、URG coverage、riscv-dv extension 和 UVM 1.2
testbench；后者包括 per-hart Spike 路由、trace/probe 混合数据源、PMP/ePMP
覆盖率、完整性 cosim waiver 和 Formality block-level closure。

v2-9 ADR 代码追溯方法
---------------------

每条 ADR 页保留原始决策语义，同时补充当前实现映射和签核证据。v2-9 统一修正了
NC/Incisive 口径：当前默认 release 参考是 VCS/URG，NC/Incisive 是完整备选
simulator，可运行 smoke、regress、sign-off、demo 和 coverage cross-check。

阅读任一 ADR 时按下面顺序追溯代码：

.. list-table::
   :header-rows: 1
   :widths: 24 36 40

   * - 步骤
     - 命令或章节
     - 目的
   * - 查看原始 ADR
     - ``sed -n '1,220p' docs/adr/<编号>-*.md``
     - 确认历史问题、备选方案和最终决策。
   * - 查看当前实现映射
     - 本附录对应 ``appendix_d_adr/<编号>_*.rst``
     - 确认代码路径、测试路径和 sign-off 证据。
   * - 查看代码改动
     - ``git log --oneline -- <path>``；``git show <commit> -- <path>``
     - 找到执行该 ADR 的真实 diff，而不是凭 ADR 文本推断。
   * - 查看当前 gate
     - :ref:`signoff_flow`、:ref:`coverage_plan`
     - 确认最新 VCS demo 数字和 waiver/gate 口径。

关键代码（``docs/adr/INDEX.md:L1-L18``）：

.. literalinclude:: ../../../../docs/adr/INDEX.md
   :language: text
   :lines: 1-18
   :caption: /home/host/eh2-veri/docs/adr/INDEX.md:L1-L18

逐段解释：

* 第 L1-L4 行：ADR index 是 Markdown 源索引，Sphinx 附录只是中文化/结构化入口。
* 第 L6-L18 行：索引列出 ADR 编号、主题和状态；Sphinx 页中的当前实现映射必须和该源索引
  一起使用，不能把某一页的摘要当成唯一证据。

关键代码（``docs/signoff-gates.md:L1-L18``）：

.. literalinclude:: ../../../../docs/signoff-gates.md
   :language: text
   :lines: 1-18
   :caption: /home/host/eh2-veri/docs/signoff-gates.md:L1-L18

逐段解释：

* 第 L1-L5 行：sign-off gates 文档定义 release gate 的分层含义。
* 第 L7-L18 行：gate 文档把 smoke、directed、cosim、riscv-dv、lint、CSR、compliance、
  formal 和 synthesis/LEC 串成同一签核口径；ADR 页引用 gate 数字时以这里和
  :ref:`signoff_flow` 为准。

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
