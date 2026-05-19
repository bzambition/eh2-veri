.. _changelog:
.. _08_appendix/changelog:

手册变更日志
============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本章记录中文 Sphinx 手册的重写进度和口径变化。它不是 EH2 RTL、UVM 平台或
release note 的替代品；它只说明手册哪些章节已经从 stub 或旧稿变成当前主线参考。
当前手册以 2026-05-19 VCS 主线 demo 为基准：9/9 stages PASS，实跑覆盖率
102/104 (98.1%)，LEC 31635/31635 PASS，URG dashboard 为 LINE 95.05%、
BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、GROUP 69.42%、
OVERALL 65.17%。

设计目标与约束
--------------

changelog 的目标是帮助维护者接续长周期文档任务。每条记录应说明影响范围、证据
口径和验证命令，不把旧 release 数字重新传播为当前状态。阶段提交记录以 Git commit
为准，进度账本以 :file:`docs/sphinx_cn/.progress.md` 为准。

架构与组成
----------

当前手册重写节奏按大章节推进：

::

   00_about / 01_overview       已完成风格基线
   02_core_reference            RTL 架构参考
   03_integration               集成与配置
   04_verification_overview     验证总览
   05_verification_arch         UVM 组件
   06_flows                     工具流程
   07_decisions                 ADR、风险、coverage、限制
   08_appendix                  基础附录
   appendix_a..f                深度附录，后续继续

实现细节
--------

进度账本是 changelog 的主要数据源：

.. literalinclude:: ../../../../docs/sphinx_cn/.progress.md
   :language: text
   :lines: 1-20
   :caption: .progress.md:1-20 - 进度账本头部

阶段 6 到阶段 8 的状态行展示了当前完成边界：

.. literalinclude:: ../../../../docs/sphinx_cn/.progress.md
   :language: text
   :lines: 55-78
   :caption: .progress.md:55-78 - 流程、决策和附录进度

Sphinx 配置中的 release 字段只表示文档版本标签，不覆盖本章的 sign-off demo 口径：

.. literalinclude:: ../../../../docs/sphinx_cn/source/conf.py
   :language: python
   :lines: 14-24
   :caption: source/conf.py:14-24 - project/release 元数据

配置与使用
----------

维护 changelog 的常用命令：

.. code-block:: bash

   # 查看最近文档提交
   git log --oneline -- docs/sphinx_cn | head

   # 查看当前阶段行数
   wc -l docs/sphinx_cn/source/08_appendix/*.rst

   # 查看进度账本
   sed -n '1,120p' docs/sphinx_cn/.progress.md

   # 构建手册
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

阶段记录
--------

.. list-table:: 当前已完成阶段
   :header-rows: 1
   :widths: 16 30 34 20

   * - 日期
     - 阶段
     - 主要内容
     - 验证
   * - 2026-05-19
     - 02_core_reference
     - pipeline、CSR、PIC、debug、RVFI/trace、mailbox 等 RTL 架构参考
     - Sphinx build
   * - 2026-05-19
     - 03_integration
     - 系统需求、快速入门、配置、SoC 集成和示例
     - Sphinx build
   * - 2026-05-19
     - 04_verification_overview
     - 验证目标、quickstart、Ibex 能力矩阵
     - Sphinx build
   * - 2026-05-19
     - 05_verification_arch
     - TB top、env、agents、scoreboard、coverage、tests、riscv-dv extension
     - Sphinx build
   * - 2026-05-19
     - 06_flows
     - build/regression/signoff/CI/lint/formal/synthesis/LEC/compliance/scripts
     - Sphinx build 无 warning
   * - 2026-05-19
     - 07_decisions
     - ADR 汇总、风险登记、coverage plan、known limitations
     - Sphinx build 无 warning
   * - 2026-05-19
     - 08_appendix
     - 目录、术语、排障、issue tracker、资料索引、changelog
     - 本阶段构建验证

当前口径变更
------------

.. list-table:: 当前手册口径
   :header-rows: 1
   :widths: 24 38 38

   * - 主题
     - 当前写法
     - 原因
   * - simulator
     - VCS 是 sign-off 主线；NC 只用于单测波形调试
     - 与 Makefile 和 Ibex 工业主线对齐
   * - coverage
     - ``line+tgl+assert+fsm+branch`` 加 GROUP/OVERALL dashboard
     - 与 VCS/URG 和 ``cover.cfg`` 当前实现一致
   * - coverage scope
     - ``core_eh2_tb_top.dut`` DUT-only
     - 防止 TB stub 或接口层污染数字
   * - LEC
     - block-level Formality，31635/31635 PASS
     - ADR-0020 是当前 closure 路径
   * - waiver
     - cosim-disabled 必须通过 YAML schema
     - 防止 testlist 内联说明绕过 gate

与 Ibex 工业实现对照
--------------------

Ibex 文档长期保持「代码、脚本、配置、文档」互相可追溯。EH2 中文手册的 changelog
同样不追求漂亮叙事，而是记录哪些章节已经对齐当前实现、哪些深度附录仍待扩写。

测试与验证
----------

每次 changelog 更新前后应运行：

.. code-block:: bash

   rg -n "旧默认入口|旧覆盖率数字|旧产物路径" docs/sphinx_cn/source/08_appendix
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html
   git diff -- docs/sphinx_cn/.progress.md docs/sphinx_cn/source/08_appendix

提交记录规范
------------

.. list-table:: 阶段提交记录要求
   :header-rows: 1
   :widths: 24 38 38

   * - 字段
     - 写法
     - 目的
   * - subject
     - ``docs(sphinx_cn): 阶段 N - <章节名> 完成``
     - 让后续维护者能按阶段追溯
   * - 文件数和行数
     - 写入 subject 或 body
     - 和 :file:`.progress.md` 互相校验
   * - 口径声明
     - VCS 主线、DUT-only coverage、Ibex 5 维度
     - 防止历史 coverage 口径回流
   * - 验证声明
     - 记录实际运行的 Sphinx build
     - 为后续 resume 提供可信状态

已知限制与未来工作
------------------

基础附录完成后，后续工作进入深度附录：appendix A 剩余 RTL 模块、appendix B UVM
类字典、appendix C 工具源码、appendix D ADR 全文扩写、appendix E 配置矩阵、
appendix F 脚本深度解析。每个阶段完成后应继续更新本 changelog 和 `.progress.md`。

参考资料
--------

* :file:`docs/sphinx_cn/.progress.md` - 手册进度账本。
* :ref:`appendix_index` - 附录入口。
* :ref:`signoff_flow` - 当前 demo 口径。
* :ref:`coverage_plan` - coverage 口径。
* :ref:`known_limitations` - 限制口径。
