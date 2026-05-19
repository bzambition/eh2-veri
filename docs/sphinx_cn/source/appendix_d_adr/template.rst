.. _adr-template:

ADR 模板与编写规范
==================

:status: review
:source: docs/adr/INDEX.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本页不是空白模板，而是 EH2 验证平台新增架构决策记录（Architecture Decision
Record，ADR）时必须遵循的写作规范。ADR 的 Markdown 原文存放在
:file:`docs/adr/`，Sphinx 中文页存放在 :file:`docs/sphinx_cn/source/appendix_d_adr/`。
新增 ADR 必须同时更新 :file:`docs/adr/INDEX.md`、本附录目录和
:ref:`adr_summary`。

编号规则
--------

新 ADR 使用下一个四位编号，不复用旧编号，不因标题变化重命名已发布文件。历史上
ADR 编号曾出现草稿重复，当前 :file:`docs/adr/INDEX.md` 已将 ``0001`` 到
``0020`` 作为 canonical 列表。若未来确实需要废弃某条 ADR，应在新 ADR 中声明
「supersedes」关系，而不是删除旧文件。

推荐骨架
--------

.. code-block:: text

   # ADR-NNNN: <标题>

   Status: Proposed | Accepted | Superseded
   Date: YYYY-MM-DD

   ## Context

   说明做出该决策的技术背景、约束、风险和现有实现。

   ## Decision

   明确陈述选定方案、适用范围、受影响文件和拒绝的备选方案。

   ## Consequences

   列出正面影响、负面影响、后续工作和验证证据。

   ## Links

   引用相关代码路径、Sphinx 章节、issue、sign-off 报告和后续 ADR。

当前签核口径
------------

ADR 中引用平台状态时必须使用当前主线事实：默认 simulator 为 VCS，覆盖率使用
``-cm line+tgl+assert+fsm+branch`` 五维口径，编译时 :file:`cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，报告由 URG 原生生成。2026-05-19 01:02 demo 的
统一数字为 ``9/9`` stages PASS、实跑覆盖率 ``102/104`` （98.1%）、
LINE ``95.05%``、BRANCH ``84.97%``、TOGGLE ``53.52%``、ASSERT ``33.33%``、
FSM ``54.74%``、GROUP ``69.42%``、OVERALL ``65.17%``，LEC 为
``31635/31635`` PASS。

审查清单
--------

.. list-table::
   :header-rows: 1
   :widths: 24 42 34

   * - 检查项
     - 要求
     - 证据
   * - 编号
     - 与 :file:`docs/adr/INDEX.md` 不冲突
     - ``rg "NNNN-" docs/adr``
   * - 状态
     - ``Proposed`` 只能用于未签核决策；已进入 sign-off 路径后改为 ``Accepted``
     - ADR header
   * - 当前事实
     - 不把 NC 写成主线，不引用旧 coverage 数字或 waiver 成功假象
     - :ref:`signoff_flow`
   * - 代码链接
     - 至少列出一个真实源码或脚本路径
     - ``:file:`` 或 literal block
   * - 验证链接
     - 说明进入哪个 sign-off stage 或哪个单测
     - :ref:`scripts_reference`

.. note::

   ADR 记录的是决策和边界，不是临时调试日志。若某条信息只是一次工具运行输出，
   应放在 sign-off 报告、release readiness 或对应 flow 章节，而不是新增 ADR。

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
