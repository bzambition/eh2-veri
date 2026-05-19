.. _decisions_index:
.. _07_decisions/index:

设计决策与质量
==============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本部分把 EH2 UVM 验证平台的设计决策、风险闭环、覆盖率策略和已知限制集中
在同一个索引下，供验证负责人、release owner、工具流维护者和新加入的
验证工程师使用。前面的章节解释「系统如何工作」；本部分解释「为什么这样
工作」「哪些历史风险已经关闭」「哪些剩余风险仍需要工程化管理」。因此，
这里既不是代码参考的重复，也不是 release note 的流水账，而是 sign-off
判断的决策账本。

当前结论以 2026-05-19 01:02 VCS 主线 demo 为准：9/9 stages PASS，实跑覆盖率
102/104 (98.1%)，block-level Formality LEC 31635/31635 PASS。覆盖率只使用
VCS/URG 主线，编译维度是 ``-cm line+tgl+assert+fsm+branch``，编译期
``cover.cfg`` scope 为 ``core_eh2_tb_top.dut``。NC/Incisive 仅保留
``make smoke|regress SIMULATOR=nc WAVES=1`` 单测波形调试用途，不参与本部分
的 sign-off 决策口径。

设计目标与约束
--------------

决策层文档承担 4 个目标。第一，给每个流程选择建立可追溯依据，例如为什么
主线回到 VCS、为什么 coverage 由 URG 原生 dashboard 给出、为什么 LEC 采用
block-level closure。第二，把 ADR、风险登记、coverage plan 和限制清单对齐到
同一套数字，避免同一个 release 中出现互相矛盾的覆盖率和 stage 统计。第三，
把历史风险和当前限制分开，历史文档可以保留问题来源，但不能被误读为当前状态。
第四，让后续阶段有明确的改进入口：低 ASSERT/FSM 覆盖、PMP/CSR 组合覆盖、
cosim waiver 到期复审、compliance 差异分析和工具版本升级。

.. warning::

   本部分不使用历史 NC 迁移阶段的 coverage 结果作为当前证据。若旧报告把
   condition coverage 当成主 gate、把 Cadence 覆盖率合成报表当成 release
   dashboard、使用旧层次 scope，或把 NC 写成主线入口，应视为历史背景而非当前实现。

.. list-table:: 决策层文档的强制口径
   :header-rows: 1
   :widths: 24 38 38

   * - 主题
     - 当前事实
     - 文档处理方式
   * - simulator
     - 顶层 ``Makefile`` 默认 ``SIMULATOR ?= vcs``，``signoff`` 接受 ``vcs``/``nc``
     - release 参考默认 VCS；NC/Incisive 作为完整备选 simulator 与 cross-check 路径
   * - coverage
     - ``VCS_COV_METRICS := line+tgl+assert+fsm+branch``
     - 不把 ``cond`` 作为当前 sign-off 维度或未来必须 gate
   * - coverage scope
     - ``cover.cfg`` 包含 ``+tree core_eh2_tb_top.dut``
     - dashboard 数字均解释为 DUT subtree 的 URG 原生结果
   * - sign-off
     - full profile 为 9 stage：smoke、directed、cosim、riscvdv、lint、csr_unit、compliance、formal、syn
     - 章节间统一引用 2026-05-19 demo 数据
   * - waiver
     - stage waiver eligibility 受 25% fail-rate ceiling 限制
     - cosim-disabled 必须通过 YAML waiver，不接受 testlist 内联理由作为正式豁免
   * - LEC
     - 当前 closure 为 block-level Formality，31635/31635 PASS
     - ADR-0019 作为历史 tool limitation，ADR-0020 作为当前闭环路径

架构与组成
----------

决策层由 5 个章节组成。``adr_summary`` 汇总 20 条 ADR，给出每条决策当前落地
位置和 sign-off 影响；``risk_register`` 把 release-readiness 早期审计中的
P0/P1 风险映射到已关闭项和剩余项；``coverage_plan`` 说明 VCS/URG coverage
闭门策略；``known_limitations`` 明确当前 release 仍需复审的限制；本索引负责
把这些章节和前后文连接起来。

::

   07_decisions
      |
      +-- adr_summary
      |     `-- docs/adr/0001..0020 -> 决策、实现、结果
      |
      +-- risk_register
      |     |-- historical audit -> 已关闭风险
      |     `-- current residuals -> owner/evidence/mitigation
      |
      +-- coverage_plan
      |     |-- Makefile VCS_COV_METRICS
      |     |-- cover.cfg DUT-only scope
      |     `-- merge_cov.py -> urg -> dashboard.txt
      |
      `-- known_limitations
            |-- cosim-disabled waiver
            |-- ASSERT/FSM informational coverage
            |-- compliance residuals
            `-- NC waveform-only boundary

.. list-table:: 章节导航
   :header-rows: 1
   :widths: 22 42 36

   * - 章节
     - 读者问题
     - 主要证据
   * - :ref:`adr_summary`
     - 为什么采用 trace/probe、RVFI adapter、formal/LEC、compliance 和 waiver 策略
     - :file:`docs/adr/INDEX.md` 与 ADR-0001 到 ADR-0020
   * - :ref:`risk_register`
     - 哪些早期 release 风险已经关闭，哪些仍需要复审
     - :file:`docs/release-readiness-assessment.md`、:file:`docs/cosim-known-limitations.md`
   * - :ref:`coverage_plan`
     - coverage 如何收集、合并、解释和闭门
     - :file:`Makefile`、:file:`cover.cfg`、:file:`merge_cov.py`
   * - :ref:`known_limitations`
     - 当前 PASS 之后还有哪些不应被掩盖的限制
     - waiver YAML、demo 数据、formal/LEC/compliance 结果
   * - :ref:`signoff_flow`
     - 9 stage gate 如何把这些决策变成机器可执行判定
     - :file:`signoff.py`、report JSON/Markdown/HTML

实现细节
--------

决策层并不执行工具，但它必须引用能改变 release 判定的真实代码。以下片段是
当前流程的关键事实来源，后续 4 个子章节会分别展开。

``Makefile`` 中 simulator、coverage 和 LEC 默认值定义了本手册的主线口径：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 135-154
   :caption: Makefile:135-154 - VCS、coverage gate 与 LEC 默认值

``Makefile`` 中 VCS coverage 配置显式采用 Ibex 风格 5 维度，并通过
``-cm_hier`` 引入 DUT-only scope：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 169-190
   :caption: Makefile:169-190 - VCS coverage 维度和 hierarchy 配置

``cover.cfg`` 是 coverage 真实性的最小边界。它只把 DUT 子树纳入 line/branch/
assert/FSM 等统计，并在 toggle 章节排除 DUT 下大规模信号翻转噪声：

.. literalinclude:: ../../../../dv/uvm/core_eh2/cover.cfg
   :language: text
   :caption: dv/uvm/core_eh2/cover.cfg - DUT-only coverage scope

``signoff.py`` 中 full profile 的 9 stage 是 release gate 的执行顺序：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 37-55
   :caption: signoff.py:37-55 - profile stage 与最小通过数

配置与使用
----------

本部分最常用的阅读方式不是从头到尾读完，而是带着问题定位。下面给出 5 个
典型入口。

.. code-block:: bash

   # 查看当前决策目录
   ls docs/sphinx_cn/source/07_decisions

   # 查询某个 ADR 的当前摘要
   rg -n "ADR-0017|cosim waiver|waiver" docs/sphinx_cn/source/07_decisions docs/adr

   # 核对 coverage 主线是否仍是 VCS/URG 5 维度
   rg -n "VCS_COV_METRICS|cover.cfg|merge_cov.py" Makefile dv/uvm/core_eh2

   # 运行完整签核，使用当前默认 VCS 主线
   make signoff

   # 只做 NC 单测波形调试，不把结果作为签核覆盖率
   make smoke SIMULATOR=nc WAVES=1

预期 sign-off 摘要应与 2026-05-19 demo 口径一致：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   real run coverage: 102/104 (98.1%)
   LEC: 31635/31635 PASS
   LINE 95.05%  BRANCH 84.97%  TOGGLE 53.52%
   ASSERT 33.33%  FSM 54.74%  GROUP 69.42%  OVERALL 65.17%

与 Ibex 工业实现对照
--------------------

EH2 决策层的写法对齐 lowRISC Ibex 的工程原则：自动化 flow 是权威入口，coverage
由 simulator 原生数据库和官方报告工具产生，waiver 必须文件化，历史限制必须和
当前 gate 分开。差异来自 EH2 自身微架构：双线程、双发射、AXI4、多内存域、
PIC、DMA、DMI/JTAG 和 block-level LEC。

.. list-table:: 决策层与 Ibex 的对照
   :header-rows: 1
   :widths: 24 34 42

   * - 维度
     - Ibex 参考
     - EH2 当前实现
   * - coverage merge
     - :file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py` 使用 URG 合并 VCS ``test.vdb``
     - :file:`dv/uvm/core_eh2/scripts/merge_cov.py` 保留 Ibex 风格 URG 路径；standalone
       入口也支持 NC ``cov_work`` 走 IMC 生成兼容 dashboard
   * - simulator yaml
     - :file:`/home/host/ibex/dv/uvm/core_ibex/yaml/rtl_simulation.yaml`
     - EH2 的 :file:`dv/uvm/core_eh2/yaml/rtl_simulation.yaml` 保留多 simulator 模板；
       Makefile 当前默认 VCS，同时允许 NC 备选签核
   * - RVFI/cosim
     - Ibex design 原生 RVFI，scoreboard 直接消费 retire 信息
     - EH2 通过 trace/probe/RVFI adapter 组合形成等价 retire 视图，相关决策见 ADR-0001、ADR-0004、ADR-0015、ADR-0018
   * - waiver
     - Ibex 使用 waiver 文件和 testlist 元数据管理不可比场景
     - EH2 将 cosim-disabled 统一收敛到 :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
   * - LEC
     - Ibex 规模较小，综合/等价路径更直接
     - EH2 受 O-2018 Formality packed-port 限制影响，采用 ADR-0020 block-level closure

测试与验证
----------

决策层本身通过文档构建和红线扫描验证。更重要的是，它引用的数字必须能由
sign-off 产物解释。2026-05-19 demo 的关键数据如下：

.. list-table:: 当前 release 决策输入
   :header-rows: 1
   :widths: 25 25 50

   * - 项目
     - 数字
     - 解释
   * - stage
     - 9/9 PASS
     - full profile 全部通过
   * - 实跑覆盖率
     - 102/104 (98.1%)
     - report 中实际执行项目数，不等同于 URG coverage 百分比
   * - directed
     - 40/40 (100%)
     - 定向 ASM 与平台定向测试全部通过
   * - riscv-dv
     - 370/395 (93.67%)
     - 随机 ISA 流达到 fail-rate ceiling 和最小通过数要求
   * - compliance
     - 85/88 (96.59%)
     - RISC-V compliance 子环境达到当前 gate
   * - formal
     - 46/46 (100%)
     - IFV/formal stage 全部 property PASS
   * - LEC
     - 31635/31635 PASS
     - block-level Formality compare point 全部闭合

已知限制与未来工作
------------------

当前 PASS 不表示所有覆盖洞都已经消失。低 ASSERT/FSM coverage、cosim-disabled
waiver 到期复审、compliance 剩余 3 项、NC 调试路径与主线 coverage 的隔离、
以及工具版本升级，仍需要在后续 release 中持续跟踪。详细列表见
:ref:`known_limitations`；覆盖率提升路线见 :ref:`coverage_plan`。

参考资料
--------

* :ref:`adr_summary` - 20 条 ADR 的当前摘要。
* :ref:`risk_register` - 风险登记与 residual risk。
* :ref:`coverage_plan` - VCS/URG coverage 策略。
* :ref:`known_limitations` - 当前已知限制。
* :ref:`signoff_flow` - 9 stage sign-off gate。
* :ref:`scripts_reference` - `signoff.py`、`merge_cov.py`、`gen_html_report.py` 脚本说明。

维护检查清单
------------

每次更新本部分时，维护者应完成下面的检查。它们不是额外流程，而是防止决策层
和实际工具流逐渐分叉的最低成本做法。

.. list-table:: 决策层维护检查
   :header-rows: 1
   :widths: 12 42 46

   * - 序号
     - 检查项
     - 通过标准
   * - 1
     - 核对 :file:`Makefile` 的 simulator、coverage 和 sign-off 变量
     - 本章没有与 ``SIMULATOR ?= vcs``、``VCS_COV_METRICS`` 或 LEC 默认值冲突的叙述
   * - 2
     - 核对 :file:`docs/adr/INDEX.md`
     - ADR 编号、状态和 topic map 与 :ref:`adr_summary` 一致
   * - 3
     - 核对 waiver YAML
     - 每条 cosim-disabled 测试都有 reason、tracking_issue 和 expiry_date
   * - 4
     - 核对最新 sign-off 报告
     - stage、coverage、formal、LEC 和 compliance 数字在本部分各页一致
   * - 5
     - 构建中文手册
     - ``sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html`` 无 error

这些检查也给后续自动化留下清晰接口：若某个变量或 gate 在代码中改变，文档更新
应先改事实表，再改叙述段落，最后运行构建验证交叉引用。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：把本页决策、风险或 coverage 计划追溯到 ADR 索引和 Sphinx 决策页。

.. code-block:: bash

   sed -n "1,120p" docs/adr/INDEX.md
   rg -n "ADR|waiver|LEC|coverage|cosim" docs/sphinx_cn/source/07_decisions docs/sphinx_cn/source/appendix_d_adr | head -80

**进阶题**：确认决策页没有回到旧 coverage 维度或旧 NC 口径。

.. code-block:: bash

   rg -n "line\+tgl\+assert\+fsm\+branch|31635/31635|95.05|NC/Incisive" docs/sphinx_cn/source/07_decisions docs/sphinx_cn/source/appendix_d_adr

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页的决策、风险或 coverage 结论依赖哪一条 ADR、脚本或 sign-off 证据？
2. 该结论是否区分当前事实、历史背景和未来工作？
3. 是否避免了旧 coverage 维度、旧 NC 口径和伪 dashboard 叙述？
4. 如果该决策被修改，最先需要同步哪些 Makefile、YAML、脚本或章节？
5. reviewer 能否从本页追到 2026-05-19 demo 的统一数字和 LEC 证据？
