.. _coverage_plan:
.. _07_decisions/coverage_plan:

覆盖率规划
==========

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
----------------

读懂本章前，请先确认：

* :ref:`glossary_pretest` — 能解释 :term:`LINE`、:term:`BRANCH`、:term:`TOGGLE`、
  :term:`ASSERT`、:term:`FSM`、:term:`GROUP` 和 :term:`OVERALL`；
* :ref:`functional_coverage` — 知道 covergroup 与 code coverage 的区别；
* :ref:`signoff_flow` — 知道 coverage gate 如何进入最终 PASS/FAIL；
* :ref:`build_flow` — 知道 :term:`VCS` 使用 :term:`cover.cfg`，:term:`NC/Incisive`
  使用 :term:`cov_full_nc.ccf`；
* 基础 coverage closure 概念：coverage hole、bin、waiver、unreachable。

学完本章你应该能够：

1. 说明为什么当前 VCS 维度是 ``line+tgl+assert+fsm+branch``，不把 ``cond`` 写成主线维度。
2. 解释为什么 LINE gate 是 65、GROUP/functional gate 是 40，而不是机械追求 80/60。
3. 区分 :term:`VCS` URG dashboard 和 :term:`NC/Incisive` :term:`IMC` 统一 dashboard 的口径差异。
4. 把一个 coverage hole 分流到 directed test、riscv-dv constraint、SVA bind 或 waiver。
5. 在 review 中阻止“扩大 scope、关采样、改 dashboard”这类虚假提升。

§1  概述
--------

EH2 覆盖率规划的核心原则是「先保证真实，再追求更高」。当前平台默认 simulator 是
:term:`VCS`，主线 release 口径采用 Synopsys VCS/URG 路径，对齐 lowRISC Ibex 工业实现；
:term:`NC/Incisive` 作为完整备选 simulator 也可收 :term:`coverage`，并通过
:term:`IMC` 合并生成与 URG 兼容的 ``dashboard.txt``。:term:`VCS` code coverage 维度固定为
``line+tgl+assert+fsm+branch``，功能覆盖以 SystemVerilog covergroup 在 URG
dashboard 中显示为 :term:`GROUP`，总体分显示为 :term:`OVERALL`。本章不把 ``cond`` 作为
当前 VCS sign-off 维度。

2026-05-19 01:02 demo 的 coverage 证据为：:term:`LINE` 95.05%、:term:`BRANCH`
84.97%、:term:`TOGGLE` 53.52%、:term:`ASSERT` 33.33%、:term:`FSM` 54.74%、
:term:`GROUP` 69.42%、:term:`OVERALL` 65.17%。这些数字来自
DUT subtree 的 URG 原生 dashboard，scope 由 :term:`cover.cfg` 编译期限定到
``core_eh2_tb_top.dut``。同一 demo 的实跑覆盖率字段为 102/104 (98.1%)，它表示
sign-off 报告中实际运行项目占计划项目的比例，不等同于 URG coverage 百分比。

§2  设计目标与约束
------------------

coverage plan 有 5 个目标。第一，所有 sign-off coverage 必须来自真实 simulator
coverage database：:term:`VCS` 使用 ``.vdb`` 和 URG，:term:`NC/Incisive` 使用
``cov_work`` 和 :term:`IMC`，不允许通过
脚本凭空合成看似漂亮的 dashboard。第二，scope 必须是 DUT-only，
防止 testbench interface、stub 或未驱动信号污染结果。第三，gate 只使用当前
Makefile 和 ``signoff.py`` 真正执行的阈值。第四，低覆盖项要被记录为改进方向，
但不能伪装成已关闭。第五，EH2 与 Ibex 的一致性要体现在工具路径和数据语义上，
而不是复制 Ibex 数字。

.. list-table:: 当前 coverage gate 与观测项
   :header-rows: 1
   :widths: 22 18 20 40

   * - 指标
     - demo 数字
     - 当前 gate
     - 说明
   * - LINE
     - 95.05%
     - ``SIGNOFF_MIN_LINE_COV=65``
     - sign-off 阻断项之一，当前裕量充足
   * - BRANCH
     - 84.97%
     - 观测
     - 反映分支路径激励质量，当前不单独设阈值
   * - TOGGLE
     - 53.52%
     - 可选阈值
     - 受 DUT 大量配置/低功耗/未用端口影响，当前用于趋势分析
   * - ASSERT
     - 33.33%
     - 观测
     - 需要增加 assertion bind 和触发场景
   * - FSM
     - 54.74%
     - 可选阈值
     - 需要结合 ``cov_fsm.cfg`` 和 reset filter 分析
   * - GROUP
     - 69.42%
     - ``SIGNOFF_MIN_FUNCTIONAL_COV=40``
     - URG dashboard 名称为 GROUP，脚本内部历史键名为 ``functional``
   * - OVERALL
     - 65.17%
     - 可选阈值
     - URG 综合分，不替代 LINE/GROUP 分项 gate

§3  架构与组成
--------------

默认 coverage 数据流从 VCS compile 开始，到 URG dashboard 结束。NC 数据流使用
``cov_full_nc.ccf`` 和 IMC，最终同样输出 ``dashboard.txt`` 供 sign-off parser 使用。
两条路径都不允许脱离真实数据库伪造百分比。

::

   make signoff COV=1
      |
      +-- make compile BUILD_SUBDIR=build/signoff COV=1
      |     |
      |     +-- vcs -cm line+tgl+assert+fsm+branch
      |     +-- -cm_hier dv/uvm/core_eh2/cover.cfg
      |     `-- simv + cov directory
      |
      +-- signoff.py --coverage
      |     |
      |     +-- smoke / directed / cosim / riscvdv collect .vdb
      |     +-- auto_merge_stage_coverage()
      |     `-- merge_cov.py --dirs ... --output cov_merged
      |
      +-- urg -full64 -format both
      |     |
      |     +-- cov_merged/merged.vdb
      |     +-- cov_merged/report/dashboard.txt
      |     `-- cov_merged/dashboard.txt
      |
      `-- evaluate_coverage()
            |
            +-- LINE >= 65
            +-- GROUP(functional key) >= 40
            `-- report.html coverage section

NC 备选路径的关键差异是编译期使用 ``cov_full_nc.ccf``，数据库写入 ``cov_work``，
``merge_cov.py`` 在 standalone mode 中自动识别 ``cov_work/*.ucd`` 并调用 IMC 生成
兼容 dashboard。由于 Incisive 152 对 branch 的独立 metric 支持有限，NC dashboard
会诚实标注 BRANCH 为 ``n/a`` 或合并口径说明，VCS 仍是拆分 branch 指标的默认参考。

§4  实现细节
------------

Makefile 中的 coverage 主线配置是本章最重要的代码证据：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 169-190
   :caption: Makefile:169-190 - VCS 5 维 coverage 与 hierarchy scope

``cover.cfg`` 的 DUT-only scope 很短，但它决定了 coverage 数字的真实性：

.. literalinclude:: ../../../../dv/uvm/core_eh2/cover.cfg
   :language: text
   :caption: dv/uvm/core_eh2/cover.cfg - coverage scope

``merge_cov.py`` 的 VCS 路径保持 Ibex 风格 URG wrapper；standalone mode 同时能识别
NC ``cov_work`` 并调用 IMC：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/merge_cov.py
   :language: python
   :lines: 1-25
   :caption: merge_cov.py:1-25 - coverage merge 调用模式

URG 调用保持原生输出，生成 ``merged.vdb``、``report`` 和根目录 dashboard 镜像：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/merge_cov.py
   :language: python
   :lines: 45-84
   :caption: merge_cov.py:45-84 - urg -full64 合并命令

``merge_cov.py`` 的 NC 路径通过 IMC 输出兼容 dashboard：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/merge_cov.py
   :language: python
   :lines: 102-180
   :caption: merge_cov.py:102-180 - NC/IMC dashboard 生成

``signoff.py`` 合并 stage coverage 时同时扫描 VCS ``.vdb`` 和 NC ``cov_work``：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 989-1028
   :caption: signoff.py:989-1028 - 自动合并 VCS/NC coverage database

coverage gate 只检查当前实现中真正支持的 canonical 指标：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 1046-1107
   :caption: signoff.py:1046-1107 - coverage threshold evaluation

§5  配置与使用
--------------

日常使用分 3 类：快速回归、完整签核、coverage 分析。

.. code-block:: bash

   # 快速 smoke，默认 VCS，默认 COV=1 由顶层 Makefile 控制
   make smoke

   # 完整 sign-off，默认 VCS + coverage + URG dashboard
   make signoff COV=1 PARALLEL=4

   # NC 备选 sign-off，coverage 由 cov_full_nc.ccf + IMC 输出统一 dashboard
   make signoff SIMULATOR=nc COV=1 PARALLEL=4

   # 只复用已有 stage 数据重新 gate，适合 release review
   make signoff_replay STAGE_DATA_DIR=build/demo

   # 手动合并若干 coverage 目录，输出 URG dashboard
   python3 dv/uvm/core_eh2/scripts/merge_cov.py \
     --dirs build/signoff/runs/smoke build/signoff/runs/directed \
     --output build/manual_cov

   # 查看 dashboard 头部
   sed -n '1,80p' build/signoff/cov_merged/dashboard.txt

预期关键输出如下：

.. code-block:: text

   Coverage (dut subtree, urg native dashboard):
     LINE     95.05%
     BRANCH   84.97%
     TOGGLE   53.52%
     ASSERT   33.33%
     FSM      54.74%
     GROUP    69.42%
     OVERALL  65.17%

§6  覆盖率闭门流程
------------------

coverage closure 不应从「提高 OVERALL 一个数字」出发，而应从具体未覆盖对象出发。
推荐步骤如下：

.. list-table:: 覆盖率闭门步骤
   :header-rows: 1
   :widths: 10 30 35 25

   * - 步骤
     - 输入
     - 动作
     - 退出条件
   * - 1
     - URG dashboard
     - 确认 LINE/GROUP gate 是否满足
     - release blocker 列表明确
   * - 2
     - URG group/detail report
     - 找最低 covergroup、coverpoint 和 cross
     - 形成可激励场景列表
   * - 3
     - riscv-dv testlist 与 directed tests
     - 判断应通过随机约束、定向 ASM 还是 UVM sequence 覆盖
     - 每个 hole 有 owner 和测试入口
   * - 4
     - fcov/pmp coverage 源码
     - 检查 bin 是否真实可达，排除配置不可达或 reset-only bin
     - 不可达项记录 waiver 或过滤策略
   * - 5
     - ``make signoff COV=1``
     - 重新生成 VCS ``.vdb`` 和 URG dashboard
     - 数字提升且没有引入新 fail

.. tip::

   ASSERT 和 FSM 当前是改进重点，但不要通过关闭采样、扩大 scope 或改写 dashboard
   来制造提升。正确路径是增加可触发场景、补充 SVA bind、复核 FSM reset filter。

§7  与 Ibex 工业实现对照
------------------------

EH2 coverage 路径与 Ibex 的关键一致点是 VCS/URG 原生 merge。下面的 Ibex 代码片段
显示同样的 ``urg -full64 -format both -dbname ... -report ... -dir`` 模式：

.. literalinclude:: ../../../../../ibex/dv/uvm/core_ibex/scripts/merge_cov.py
   :language: python
   :lines: 31-47
   :caption: Ibex merge_cov.py:31-47 - VCS URG merge

.. list-table:: EH2 与 Ibex coverage 对照
   :header-rows: 1
   :widths: 22 36 42

   * - 维度
     - Ibex
     - EH2
   * - simulator 主线
     - VCS/Xcelium 均有成熟路径，VCS 用 URG
     - 默认主线是 VCS；NC/Incisive 是完整备选 simulator，覆盖率通过 IMC 生成兼容 dashboard
   * - merge 工具
     - VCS coverage 由 URG 合并
     - VCS 采用 URG；NC 采用 IMC，二者都来自真实数据库
   * - scope
     - DUT hierarchy 由 metadata/config 控制
     - ``cover.cfg`` 编译期限定 ``core_eh2_tb_top.dut``
   * - code coverage 维度
     - Ibex 工业配置强调 line/toggle/branch/assert/FSM 等主要维度
     - EH2 当前固定 ``line+tgl+assert+fsm+branch``
   * - functional coverage
     - covergroup 汇入 simulator report
     - EH2 dashboard 写 ``GROUP``，脚本内部兼容键为 ``functional``

§8  测试与验证
--------------

coverage plan 的验证以 demo 数据和构建检查为准：

.. list-table:: 2026-05-19 coverage 证据
   :header-rows: 1
   :widths: 20 20 20 40

   * - 项目
     - 数字
     - 状态
     - 解释
   * - LINE
     - 95.05%
     - PASS
     - 高于 65% gate
   * - GROUP
     - 69.42%
     - PASS
     - 高于 40% gate
   * - OVERALL
     - 65.17%
     - 观测
     - 用于趋势，不替代分项 gate
   * - ASSERT
     - 33.33%
     - watch
     - 后续补 assertion 触发
   * - FSM
     - 54.74%
     - watch
     - 后续补状态机场景
   * - 实跑覆盖率
     - 102/104 (98.1%)
     - PASS
     - sign-off 报告中的 test execution coverage

§9  已知限制与未来工作
----------------------

短期 coverage 工作应按收益排序。第一优先级是 ASSERT/FSM：它们当前较低，且能通过
定向场景、SVA bind 和 reset filter 复核持续提升。第二优先级是 GROUP 中的 PMP、
CSR、异常、中断、debug cross。第三优先级是 toggle 空洞，需要区分真实低激励、
配置不可达端口和 tie-off 逻辑。第四优先级是 compliance 剩余项目与 directed/riscv-dv
失败分类联动，避免只提升覆盖率而忽略行为差异。

§10  动手练习与自检
-------------------

入门题（5 分钟）：

.. code-block:: bash

   rg -n "VCS_COV_METRICS|NC_COV_CCF|SIGNOFF_MIN_LINE_COV|SIGNOFF_MIN_FUNCTIONAL_COV" Makefile

写下 VCS 5 维 coverage、NC CCF 文件、LINE gate 和 GROUP/functional gate。

进阶题（30 分钟）：

.. code-block:: bash

   sed -n '1,120p' dv/uvm/core_eh2/cover.cfg
   sed -n '1,120p' dv/uvm/core_eh2/cov_full_nc.ccf

比较 VCS 与 NC 如何限定 DUT-only scope。重点看 ``core_eh2_tb_top.dut`` 与
``-inst core_eh2_tb_top.dut...`` 的语义是否一致。

挑战题（2 小时）：

从 :ref:`functional_coverage` 任选一个长期低覆盖 coverpoint，写一页 closure 计划：
现象、可能不可达条件、推荐 directed/riscv-dv/formal 补法、验收命令和不允许使用的
虚假提升手段。

自检 5 问：

1. 为什么 EH2 不把 ``cond`` 写进当前 VCS coverage 维度？
2. 为什么 LINE gate 是 65，而 GROUP gate 是 40？
3. ``GROUP`` 与 ``OVERALL`` 的区别是什么？
4. NC coverage dashboard 中 BRANCH 口径为什么需要特别说明？
5. coverage 提升后必须同时检查哪些 regression 或 sign-off blocker？

§11  参考资料
-------------

* :ref:`functional_coverage` - EH2 functional coverage 模型。
* :ref:`pmp_coverage` - PMP coverage 深入说明。
* :ref:`signoff_flow` - coverage gate 与 sign-off 报告。
* :ref:`scripts_reference` - ``merge_cov.py``、``gen_html_report.py`` 和 ``signoff.py``。
* :ref:`risk_register` - coverage 相关风险登记。
