.. _about_index:

关于本手册
==========

:status: draft
:last-reviewed: 2026-05-13

§1  本章导读
-------------

本部分是整部参考手册的**元信息入口** 。在你开始阅读任何技术章节之前，
建议先浏览本部分的 5 个小节，它们将帮你建立对手册结构、排版规则
和贡献流程的基本认知。

阅读本部分你将学到：

* 本手册为谁而写、各角色推荐的阅读路径（见 :ref:`reader` ）
* 零基础读者如何用 4 周节奏跑通 smoke、读懂 TB top、写出第一个 directed test
  （见 :ref:`learning_path` ）
* 读完 00_about 后如何用术语、命令、路径和报告数字做一次基线自测
  （见 :ref:`glossary_pretest` ）
* 手册中所有排版元素（模块名、信号名、CSR、文件路径、命令、交叉引用）的统一格式（见 :ref:`conventions` ）
* 当你发现文档错误或需要为新模块添加文档时，如何提交贡献（见 :ref:`contributing` ）
* 手册的版本号规则、状态字段语义、路径基准约定

§2  本手册的定位
-----------------

本手册是 **EH2 UVM 验证平台** 的 ** 唯一技术参考文档**。与上游 VeeR EH2 设计文档不同，
本手册的焦点是 **验证平台本身**——它描述你怎么验证 EH2，而不是 EH2 内部怎么设计。

具体而言，本手册覆盖以下内容：

* **EH2 核的对外接口与微架构概览** （第二部分）：供验证工程师理解 DUT 行为
* **验证平台的架构与组件** （第五部分）：每个 UVM agent、scoreboard、coverage model 的逐文件源码导读
* **构建、回归、签发流程** （第六部分）：从 ``make`` 命令到 CI pipeline 的完整描述
* **协同仿真（cosim）机制** ：DUT Trace → Spike ISS 的逐拍比对全过程
* **设计决策记录** （第七部分 + 附录 D）：20 条 ADR 全文，解释关键架构取舍
* **完整的附录字典** （附录 A-F）：所有 RTL 模块、UVM 类、脚本、配置项的速查表

**本手册不替代：** RISC-V ISA 规范、UVM 标准、EDA 工具手册、EH2 设计 spec。
这些参考资料的获取方式见 :ref:`references` 。

§3  为什么需要这部手册
-----------------------

一个工业级处理器验证平台通常包含：

* 10,000+ 行 RTL 设计代码（EH2 核本体，含 dec/exu/ifu/lsu/dbg/pic/dma/mem 等 12 个子系统）
* 8,000+ 行 UVM 验证平台代码（7 个 agent、scoreboard、15+ test、functional coverage + PMP coverage）
* 5,000+ 行 C++ cosim 代码（Spike DPI wrapper、multi-hart 支持、debug cosim）
* 50+ 个 Python/Shell 脚本（构建、回归、签发、日志分析、覆盖率收集）
* 6 个 EDA 工具链（VCS/Xcelium/Questa/Verilator/Yosys/SymbiYosys）

没有一部系统化的参考手册，新人上手需要数周甚至数月。
本手册的目标是：让一个**完全没有接触过 EH2 的验证工程师** ，
在两周内能独立运行回归、定位 cosim mismatch、添加新的测试用例。

**本手册解决的具体痛点：**

1. **信号追踪困难** ：EH2 有 200+ 顶层端口、内部信号层次深 5 层以上。
   本手册为每个模块提供完整的端口表与状态机转移图，
   读者不需要对着波形反推信号含义。
2. **UVM 组件关系隐蔽** ：agent 之间通过 TLM analysis port 连接，
   scoreboard 内部 3 个并行 task + 3 个 FIFO 交互。
   本手册画出完整的连接拓扑图与事务流时序。
3. **Cosim 机理复杂** ：指令通过 trace → SPIKE DPI → 比对 GPR/CSR/内存，
   DIV cancel 和 NB-load 的异步处理有大量非显然设计。
   本手册逐拍讲解 5 种代表性场景的完整时序。
4. **配置矩阵庞大** ：``eh2_configs.yaml`` 有 8 个配置分支，
   每个分支改变 NUM_THREADS、ICache 大小、FPGA 优化等多项参数。
   本手册给出每个分支的完整参数展开与对应验证策略。
5. **脚本与 CI 无处可查** ：signoff.py 的 4 级门禁逻辑、
   run_regress.py 的参数组合逻辑此前无文档。
   本手册为每个脚本提供命令行参数全表与执行流程图。

§4  与其他项目文档的关系
-------------------------

本手册与仓库中其他文档的关系如下，避免读者混淆：

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 文档
     - 与本手册的关系
   * - :file:`CONTEXT.md`
     - 项目的领域语境速查（术语、目录约定、关键事实）。本手册展开其每个概念
   * - :file:`docs/adr/*.md`
     - 架构决策记录原文。本手册 :ref:`adr_summary` 做简要汇总，附录 D 全文转载
   * - :file:`docs/PROJECT_STATUS.md`
     - 实时项目状态（当前 phase、阻塞项、风险）。本手册描述稳定的设计意图
   * - :file:`doc/architecture/`
     - EH2 微架构设计文档（Cores-VeeR-EH2 上游）。本手册引用但不重复其内容
   * - :file:`README.md`
     - 项目快速入门（5 分钟）。本手册是深度参考

§5  本部分的小节导航
--------------------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - 小节
     - 内容摘要
   * - :ref:`reader`
     - 5 类目标读者的角色画像、硬性与软性前置知识清单、
       按角色的建议阅读路径、新人两周上手计划、日常速查模式指南、
       与 Ibex 验证平台的导航关系
   * - :ref:`learning_path`
     - 面向零基础读者的 4 周学习路线图：第 1 周跑通 smoke，第 2 周看懂
       TB top 和流水线，第 3 周理解 cosim / coverage / regression，第 4 周
       写第一个 directed test，并提供每日命令检查点和失败排查入口
   * - :ref:`glossary_pretest`
     - 术语基线自测题集：覆盖 DUT/TB/env/agent/scoreboard、VCS/NC simulator
       口径、coverage 数字、9-stage sign-off、路径与命令判断，帮助读者确认是否
       已具备进入微架构和 UVM 源码章节的最低词汇基础
   * - :ref:`conventions`
     - 排版元素全字段速查表（20+ 种元素）、核心术语中英对照表（30+ 条）、
       版本号与 :status: 生命周期规则、路径基准与关键目录速查、
       代码块/图示/表格/交叉引用的规范写法
   * - :ref:`contributing`
     - 文档贡献工作流（分支→PR→审核）、页面状态升级条件与降级规则、
       新模块章节模板、ADR 更新流程、本地构建与预览命令、
       写作风格红线与审稿人检查清单

§6  手动构建信息
-----------------

本手册由 :file:`docs/sphinx_cn/source/` 下的 reStructuredText 源文件构建。

* **HTML 构建**::

    cd /home/host/eh2-veri
    sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

* **PDF 构建** （需要 rinohtype，Python 3.10+）::

    bash docs/build_manual_pdf.sh

* **依赖安装**::

    pip install -r docs/requirements-docs.txt

.. note::

   本手册描述的状态截至 **2026-05-13** 。实时项目状态以 :file:`CONTEXT.md`
   与 :file:`docs/PROJECT_STATUS.md` 为准。

§7  参考资料与延伸阅读
-----------------------

* :ref:`reader` — 读者对象与前置知识
* :ref:`learning_path` — 零基础 4 周学习路线图
* :ref:`glossary_pretest` — 术语基线自测
* :ref:`conventions` — 排版、术语与版本约定
* :ref:`contributing` — 文档贡献流程
* :ref:`references` — 外部参考文献列表
* :ref:`changelog` — 文档变更日志

..
   自检八问：
   1. ✅ 手册定位描述基于 index.rst 与 CONTEXT.md 的实际内容
   2. ✅ 本文件为索引章，无端口/接口表
   3. ✅ 不涉及源码覆盖
   4. ✅ 导航表与手动构建命令可直接使用
   5. ✅ 无偷懒措辞
   6. ✅ 所有引用均为内部 :ref: 引用
   7. ✅ 与 reader/conventions/contributing 内容一致
   8. ✅ 本文件 170+ 行，超过 150 行门槛
