.. _issue_tracker:
.. _08_appendix/issue_tracker:

Issue 跟踪系统
==============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

EH2 验证平台使用本地 Markdown issue tracker 记录 PRD、实现任务、release-readiness
整改和 agent 工作流状态。它不是 GitHub issue 的镜像；权威路径在 `.scratch/` 下。
本章说明 issue 文件放在哪里、状态字段如何读取、triage label 如何解释，以及这些
issue 如何和 ADR、waiver、sign-off gate 关联。

本章只解释 tracker 机制，不把旧 issue 文件中的历史状态当成当前 release 结论。
当前 sign-off 事实仍以 2026-05-19 demo、:ref:`signoff_flow`、:ref:`risk_register`
和 :ref:`known_limitations` 为准。

设计目标与约束
--------------

issue tracker 的目标是让本地长任务可拆分、可审查、可恢复。每个 issue 应有明确
路径、状态、优先级和上下文；完成状态应由代码、测试或文档证据支撑。若 issue
内容与当前代码冲突，应更新 issue 或在手册中标明它是历史来源，不能把它直接写成
当前事实。

架构与组成
----------

tracker 的目录规则如下：

::

   .scratch/
      |
      +-- <feature-slug>/
      |     +-- PRD.md
      |     `-- issues/
      |           +-- 01-<slug>.md
      |           `-- 02-<slug>.md
      |
      `-- release-readiness/
            `-- issues/
                  +-- 50-signoff-gates.md
                  +-- ...
                  `-- 68-pmp-fcov-signals.md

实现细节
--------

本地 issue tracker 规则由 :file:`docs/agents/issue-tracker.md` 定义：

.. literalinclude:: ../../../../docs/agents/issue-tracker.md
   :language: text
   :lines: 1-19
   :caption: docs/agents/issue-tracker.md:1-19 - 本地 Markdown issue 规则

triage label 字典由 :file:`docs/agents/triage-labels.md` 定义：

.. literalinclude:: ../../../../docs/agents/triage-labels.md
   :language: text
   :lines: 1-14
   :caption: docs/agents/triage-labels.md:1-14 - triage label 字典

waiver 文件中的 `tracking_issue` 字段把 waiver 与 ADR 或 issue 关联起来：

.. literalinclude:: ../../../../dv/uvm/core_eh2/waivers/cosim-disabled.yaml
   :language: yaml
   :lines: 17-40
   :caption: cosim-disabled.yaml:17-40 - tracking_issue 示例

配置与使用
----------

常用 tracker 命令：

.. code-block:: bash

   # 列出 release-readiness issue
   find .scratch/release-readiness/issues -maxdepth 1 -type f | sort

   # 查看 issue 顶部状态
   sed -n '1,12p' .scratch/release-readiness/issues/50-signoff-gates.md

   # 查找所有 Status 字段
   rg -n "^\\*\\*Status\\*\\*|^Status:" .scratch

   # 查找 waiver 追踪来源
   rg -n "tracking_issue|expiry_date" dv/uvm/core_eh2/waivers

   # 查找某个 ADR 与 issue 的交叉引用
   rg -n "ADR-0017|Issue 61|cosim-disabled" docs dv .scratch

.. list-table:: triage 状态
   :header-rows: 1
   :widths: 24 30 46

   * - 状态
     - 中文解释
     - 使用场景
   * - ``needs-triage``
     - 需要分诊
     - 刚记录的问题，owner、优先级或复现路径不清楚
   * - ``needs-info``
     - 等待更多材料
     - 缺日志、命令、失败路径或期望结果
   * - ``ready-for-agent``
     - 可交给 agent 执行
     - 范围清楚、输入完整、验收标准明确
   * - ``ready-for-human``
     - 需要人工处理
     - 需要 license、硬件访问、架构判断或外部批准
   * - ``wontfix``
     - 不处理
     - 明确不属于当前目标或已有替代方案

与 ADR 和 waiver 的关系
-----------------------

issue、ADR 和 waiver 是 3 类不同记录：

.. list-table:: issue/ADR/waiver 区分
   :header-rows: 1
   :widths: 18 34 48

   * - 类型
     - 路径
     - 作用
   * - Issue
     - :file:`.scratch/<feature>/issues/*.md`
     - 记录任务、缺陷、复现路径、状态和 owner
   * - ADR
     - :file:`docs/adr/NNNN-*.md`
     - 记录架构或流程决策，形成长期参考
   * - Waiver
     - :file:`dv/uvm/core_eh2/waivers/*.yaml`
     - 记录当前 gate 允许的例外，必须可校验、可到期复审

例如 integrity fault injection 不适合 Spike lockstep，这一事实由 ADR-0017 解释，
由 waiver YAML 管理具体测试，由 issue 或 tracking string 承载后续复审入口。

与 Ibex 工业实现对照
--------------------

Ibex 更依赖公开 issue、PR 和代码 review 记录；EH2 当前工作区使用本地 Markdown
tracker 承载长任务和 agent 工作流。两者共同点是：不可把 issue 描述当作自动完成
证据，必须回到测试、构建和 sign-off 产物。

测试与验证
----------

tracker 自检命令：

.. code-block:: bash

   # waiver schema 校验
   python3 dv/uvm/core_eh2/scripts/signoff.py \
     --validate-waivers dv/uvm/core_eh2/waivers/cosim-disabled.yaml

   # 检查 issue 是否仍引用过时 sign-off 口径
   rg -n "coverage|LEC|formal|PASS_WITH" .scratch/release-readiness/issues

   # 文档构建
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

维护检查清单
------------

.. list-table:: issue tracker 维护检查
   :header-rows: 1
   :widths: 18 40 42

   * - 检查项
     - 命令或资料
     - 通过标准
   * - 路径规则
     - :file:`docs/agents/issue-tracker.md`
     - 新 issue 位于 `.scratch/<feature>/issues/`
   * - 状态字段
     - ``rg -n "^\\*\\*Status\\*\\*|^Status:" .scratch``
     - issue 顶部状态可被直接读取
   * - waiver 关联
     - :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
     - tracking_issue 指向 ADR、issue 或可追踪字符串
   * - 手册引用
     - 本章和 :ref:`risk_register`
     - 不把旧 issue 描述写成当前 sign-off 事实

已知限制与未来工作
------------------

`.scratch/` 是本地工作区目录，可能包含实验、旧 prompt 和未整理记录。本章只把
稳定规则写入手册，不把每个本地 scratch 文件都纳入索引。若未来迁移到外部 issue
系统，应保留本地 Markdown 到外部编号的映射。

参考资料
--------

* :ref:`adr_summary` - ADR 汇总。
* :ref:`risk_register` - 风险登记。
* :ref:`known_limitations` - waiver 和限制。
* :file:`docs/agents/issue-tracker.md` - tracker 规则。
* :file:`docs/agents/triage-labels.md` - label 字典。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：确认索引、术语、附录或兼容旧入口不会破坏整本手册构建。

.. code-block:: bash

   sphinx-build -W --keep-going -b html docs/sphinx_cn/source /tmp/eh2-doc-practice-check
   rg -n "自检 5 问|动手练习" docs/sphinx_cn/source | head -80

**进阶题**：抽查参考页是否使用当前统一平台口径。

.. code-block:: bash

   rg -n "95.05|31635/31635|line\+tgl\+assert\+fsm\+branch|NC/Incisive" docs/sphinx_cn/source | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
