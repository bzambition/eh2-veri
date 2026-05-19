.. _appendix_index:
.. _08_appendix/index:

附录
====

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本部分是中文手册的基础附录，服务于日常查阅、排障、术语统一和资料索引。它不
替代前面架构、验证组件、流程和决策章节；它的职责是把常用入口压缩成可快速
定位的参考页。读者在不知道某个目录属于哪个子系统、某个缩写首次出现在哪里、
某类失败应先看哪份日志、某条 issue 或 ADR 应如何引用时，应从本部分进入。

当前附录以 2026-05-19 VCS 主线 demo 为准：Status PASS，9/9 stages PASS，实跑
覆盖率 102/104 (98.1%)，LEC 31635/31635 PASS；coverage 使用
``line+tgl+assert+fsm+branch``、``cover.cfg`` DUT-only scope 和 URG 原生
dashboard。NC/Incisive 只作为单测波形调试路径出现。

设计目标与约束
--------------

附录页有 4 个约束。第一，所有路径必须能在当前工作区找到；第二，所有数字必须与
当前 sign-off 口径一致；第三，所有命令必须是当前 Makefile 或脚本实际支持的入口；
第四，术语解释要服务排障和阅读，不做无边界扩展。若 README、历史 release notes
或旧 status 文件中的数字与当前 sign-off 口径冲突，本附录优先采用
:ref:`signoff_flow`、:ref:`coverage_plan` 和 :ref:`known_limitations` 中的当前事实。

.. warning::

   本附录不把历史 release artifact 路径或旧 coverage 表当作当前证据。需要引用
   历史资料时，应明确写成历史背景，并避免和当前 demo 数字混用。

架构与组成
----------

本部分共有 7 个页面。每个页面都有独立职责，也都链接回主手册的正式章节。

.. list-table:: 附录页面导航
   :header-rows: 1
   :widths: 22 34 44

   * - 页面
     - 用途
     - 主要证据
   * - :ref:`directory_layout`
     - 仓库目录、构建产物、Sphinx source 映射
     - :file:`Makefile`、:file:`eh2_tb.f`、:file:`docs/dir-conventions.md`
   * - :ref:`glossary`
     - 中英术语、缩写、工具名和 EH2 专有名词
     - RTL/UVM/flow 章节的统一用词
   * - :ref:`troubleshooting`
     - 编译、仿真、cosim、coverage、formal、LEC 常见失败定位
     - :file:`signoff.py`、:file:`merge_cov.py`、waiver YAML
   * - :ref:`issue_tracker`
     - 本地 Markdown issue tracker 使用规则
     - :file:`docs/agents/issue-tracker.md`、:file:`triage-labels.md`
   * - :ref:`references`
     - 内部资料、外部规范、Ibex 对照和工具文档入口
     - ADR 索引、Ibex 路径、RISC-V 规范类别
   * - :ref:`changelog`
     - 中文手册阶段性变更记录
     - :file:`docs/sphinx_cn/.progress.md`、阶段提交记录

本附录在全书中的位置如下：

::

   source/index.rst
      |
      +-- 02_core_reference      RTL 架构参考
      +-- 05_verification_arch   UVM 组件参考
      +-- 06_flows               工具流程和脚本
      +-- 07_decisions           ADR、风险、coverage 和限制
      `-- 08_appendix            快速查阅与维护索引

实现细节
--------

Sphinx 总目录把本附录作为第八部分，并在后面继续挂载 RTL、UVM、工具、ADR、配置
和脚本深度附录：

.. literalinclude:: ../../../../docs/sphinx_cn/source/index.rst
   :language: rst
   :lines: 98-122
   :caption: source/index.rst:98-122 - 第八部分 toctree

Sphinx 配置定义了中文手册的主题、扩展和语言：

.. literalinclude:: ../../../../docs/sphinx_cn/source/conf.py
   :language: python
   :lines: 1-40
   :caption: source/conf.py:1-40 - Sphinx 中文手册配置

顶层 Makefile 的文档 target 是本附录构建检查的执行入口：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 1163-1174
   :caption: Makefile:1163-1174 - manual target

配置与使用
----------

构建和检查附录最常用的命令如下：

.. code-block:: bash

   # 构建整本中文手册
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

   # 使用 Makefile 包装入口
   make manual FORMAT=html

   # 检查本附录是否仍有过时口径关键词
   rg -n "condition coverage|旧层次 scope|历史 release artifact" \
     docs/sphinx_cn/source/08_appendix

   # 查看进度账本中附录状态
   sed -n '60,90p' docs/sphinx_cn/.progress.md

   # 查看当前 HTML 输出
   ls docs/sphinx_cn/build/html/08_appendix

预期构建输出以 ``build succeeded`` 结束，HTML 输出目录中应包含
``index.html``、``directory_layout.html``、``glossary.html``、
``troubleshooting.html``、``issue_tracker.html``、``references.html`` 和
``changelog.html``。

与 Ibex 工业实现对照
--------------------

Ibex 官方文档把规范、工具流和实现细节拆成多个可交叉引用页面。EH2 中文手册采用
类似结构，但附录职责更偏向工程现场：既要给读者导航，也要避免历史口径回流到
当前签核叙事。

.. list-table:: 附录设计与 Ibex 对照
   :header-rows: 1
   :widths: 24 36 40

   * - 维度
     - Ibex
     - EH2
   * - 目录索引
     - 官方文档与 `core_ibex` 源码保持清晰映射
     - 本附录用 :ref:`directory_layout` 映射 EH2 多子环境和产物目录
   * - 术语
     - Ibex 文档保留 RVFI、CSR、ISS 等英文术语
     - EH2 术语表首次给出中文解释，后续保留英文缩写
   * - 排障
     - Ibex 依赖成熟 regression metadata 和日志约定
     - EH2 排障页覆盖 VCS、URG、Spike DPI、IFV、Formality 和 waiver gate
   * - 决策引用
     - Ibex 文档强调实现与规范链接
     - EH2 使用 20 条 ADR 和本地 issue tracker 管理工程决策

测试与验证
----------

本附录本身的验证包括 3 项：

.. list-table:: 附录验证项
   :header-rows: 1
   :widths: 24 38 38

   * - 验证
     - 命令
     - 通过标准
   * - Sphinx 构建
     - ``sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html``
     - 无 error；本阶段提交前修复本目录 warning
   * - 过时口径扫描
     - ``rg`` 扫描旧 simulator、旧 coverage、旧产物路径关键词
     - 本目录无命中，或命中仅出现在明确的历史说明中
   * - 进度账本
     - ``wc -l docs/sphinx_cn/source/08_appendix/*.rst``
     - 每页达到目标行数并在 :file:`.progress.md` 标记 done

已知限制与未来工作
------------------

本部分是基础附录，不承担附录 A 到 F 的深度展开任务。RTL 模块逐文件解释在
:ref:`appendix_a_rtl/index`，UVM 类字典在 :ref:`appendix_b_uvm/index`，工具源码
字典在 :ref:`appendix_c_tools/index`，ADR 全文在 :ref:`appendix_d_adr_index`，
配置矩阵在 ``appendix_e_config``，脚本深度解析在 ``appendix_f_scripts``。基础
附录只提供导航、排障和术语入口。

参考资料
--------

* :ref:`directory_layout` - 仓库结构与产物目录。
* :ref:`glossary` - 统一术语。
* :ref:`troubleshooting` - 常见问题排查。
* :ref:`issue_tracker` - 本地 issue tracker。
* :ref:`references` - 资料索引。
* :ref:`changelog` - 手册变更日志。
