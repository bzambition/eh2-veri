.. _risk_register:
.. _07_decisions/risk_register:

风险登记册
==========

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

风险登记册记录 EH2 UVM 验证平台从早期 release-readiness 审计到当前 VCS 主线
sign-off 的风险演进。它的重点不是重复历史批评，而是回答 3 个问题：哪些风险已经
通过代码、流程或 ADR 关闭；哪些风险仍保留为 release 限制；哪些指标应在后续
版本继续跟踪。当前结论以 2026-05-19 01:02 demo 为准：Status PASS，9/9 stages
PASS，实跑覆盖率 102/104 (98.1%)，LEC 31635/31635 PASS。

风险状态分 4 类：``closed`` 表示已有代码实现和 sign-off 证据；``controlled``
表示风险仍存在但有 gate、waiver 或文档化边界；``watch`` 表示不阻断当前 release，
但应在后续版本提升；``historical`` 表示只作为早期审计背景保留。不要把早期
release-readiness 文档中的「不能发版」结论直接套到当前工作区；那些结论催生了
后续 ADR、脚本 gate、子环境和 LEC flow，当前状态必须以 HEAD 加工作区事实为准。

设计目标与约束
--------------

风险登记需要和 sign-off gate 保持一致。一个风险只有在以下条件同时满足时才可
标记为 closed：有明确的代码路径或配置文件；有自动化 stage 或报告证据；没有
依赖手工编辑报告；没有通过隐藏失败来达成 PASS。对于不可由 ISS 建模的硬件
fault injection，登记册不会强行要求 cosim，而是要求 waiver schema、到期复审和
RTL-only self-check/formal 补强。

.. warning::

   风险登记不接受「因为最小通过数达标所以任意失败都可忽略」的解释。
   ``signoff.py`` 对 stage waiver 加了 25% fail-rate ceiling，超过这个比例的失败
   不能被最小通过数掩盖。

架构与组成
----------

风险闭环由 4 层组成：历史审计提出风险；ADR 定义策略；代码和配置落实策略；
sign-off stage 给出证据。下面的图说明一个风险从 open 到 closed 的最低证据链。

::

   risk source
      |
      +-- release-readiness audit / cosim-known-limitations / user issue
      |
      v
   ADR or implementation decision
      |
      +-- docs/adr/0001..0020
      +-- waiver YAML when ISS cannot model the behavior
      |
      v
   executable control
      |
      +-- signoff.py gate
      +-- Makefile target
      +-- testlist / coverage / LEC summary
      |
      v
   evidence
      |
      +-- 9/9 stages PASS
      +-- coverage dashboard
      +-- formal 46/46
      `-- LEC 31635/31635

实现细节
--------

release-readiness 早期审计是风险来源，但其中的数字已经不是当前状态。本章只把
它作为「风险发现」证据：

.. literalinclude:: ../../../../docs/release-readiness-assessment.md
   :language: text
   :lines: 1-30
   :caption: docs/release-readiness-assessment.md:1-30 - 早期审计背景

cosim remaining limitation 文档解释了部分 disabled 测试的技术原因：

.. literalinclude:: ../../../../docs/cosim-known-limitations.md
   :language: text
   :lines: 1-30
   :caption: docs/cosim-known-limitations.md:1-40 - cosim remaining disabled 来源

当前 waiver 的权威入口是 YAML 文件，不是 testlist 中的临时字段：

.. literalinclude:: ../../../../dv/uvm/core_eh2/waivers/cosim-disabled.yaml
   :language: yaml
   :lines: 1-26
   :caption: cosim-disabled.yaml:1-26 - waiver schema 和 CSR waiver 示例

stage fail-rate ceiling 是防止「高失败率被最小通过数掩盖」的关键控制：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 397-425
   :caption: signoff.py:397-425 - 25% fail-rate ceiling

配置与使用
----------

风险 review 常用命令如下：

.. code-block:: bash

   # 查看所有当前 waiver，确认每条都有 tracking_issue 和 expiry_date
   python3 dv/uvm/core_eh2/scripts/signoff.py \
     --validate-waivers dv/uvm/core_eh2/waivers/cosim-disabled.yaml

   # 查找是否有人在 testlist 中重新引入非正式 cosim_reason
   rg -n "cosim_reason|cosim: disabled|skip_in_signoff" dv/uvm/core_eh2

   # 查看 riscv-dv、directed、cosim 三类 testlist 的当前池
   rg -n "test:|cosim:|iterations|skip_in_signoff" \
     dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml \
     dv/uvm/core_eh2/directed_tests/*.yaml

   # gate-only 复核历史 stage 目录，仍使用 VCS 口径
   make signoff_replay STAGE_DATA_DIR=build/demo

   # 完整重跑，以当前代码生成风险闭环证据
   make signoff COV=1 PARALLEL=4

预期 waiver schema 校验输出应包含 schema pass 和加载的 waiver entry 数量。若
出现缺少 ``expiry_date``、YAML 解析失败或 testlist 中存在未登记 disabled 项，
应视为 release blocker。

与 Ibex 工业实现对照
--------------------

Ibex 的风险管理依赖 testlist、waiver、coverage、ISS compare 和 formal/lint
多层 gate。EH2 与其一致之处是：不把单个脚本返回 0 作为唯一 sign-off 证据；
coverage、waiver、stage pass rate 和工具报告都必须进入最终判定。差异在于 EH2
微架构更复杂，尤其是双线程、AXI4、PIC、DMI/JTAG、DMA、ICCM/DCCM ECC 和
block-level LEC。

.. list-table:: 风险管理对照
   :header-rows: 1
   :widths: 22 36 42

   * - 维度
     - Ibex 参考
     - EH2 当前策略
   * - testlist 完整性
     - Ibex core_ibex testlist 与 regression metadata 绑定
     - EH2 sign-off 检查 directed/riscv-dv/cosim 池，并对 disabled/skip 要求 waiver
   * - coverage
     - Ibex VCS 使用 URG，Xcelium 有独立商业覆盖率合并路径
     - EH2 默认 release 参考是 VCS/URG；NC/Incisive 作为完整备选 simulator，
       通过 IMC 生成兼容 dashboard，用于 cross-check 和备选签核证据
   * - ISS 不可比场景
     - Ibex 通过 testlist/waiver 标明不可比
     - EH2 对硬件完整性 fault injection 使用 ADR-0017 和 YAML waiver
   * - LEC 风险
     - Ibex LEC 路径受规模影响较小
     - EH2 用 ADR-0020 block-level LEC 关闭 packed-port 工具限制
   * - 双线程
     - Ibex 是单 hart core
     - EH2 需要额外管理 NUM_THREADS、per-hart Spike state 和 thread_id 路由风险

风险总表
--------

.. list-table:: 当前风险登记
   :header-rows: 1
   :widths: 10 13 25 30 22

   * - ID
     - 状态
     - 风险
     - 证据
     - 后续动作
   * - R-01
     - closed
     - sign-off 默认 simulator 口径漂移
     - ``Makefile`` 默认 VCS，``signoff`` 接受 ``vcs``/``nc`` 并提示 VCS 是默认
     - 文档统一写成 VCS 默认主线、NC 完整备选 simulator
   * - R-02
     - closed
     - coverage scope 包含 TB stub 导致数字失真
     - ``cover.cfg`` 只包含 ``core_eh2_tb_top.dut``
     - 新增 coverage 配置必须保留 DUT-only 原则
   * - R-03
     - closed
     - coverage 维度混入过时 ``cond`` 口径
     - ``VCS_COV_METRICS`` 为 ``line+tgl+assert+fsm+branch``
     - 文档和 dashboard 统一 5 维 code coverage 加 GROUP/OVERALL
   * - R-04
     - closed
     - stage 最小通过数掩盖高失败率
     - 25% fail-rate ceiling 已在 ``signoff.py`` 中实现
     - 若扩展 stage，必须设置合理最小通过数和 fail-rate 策略
   * - R-05
     - closed
     - LEC top-level packed-port 工具限制阻断 release
     - ADR-0020 block-level LEC，31635/31635 PASS
     - 工具升级后复测 top-level LEC
   * - R-06
     - closed
     - formal 只有脚手架没有实跑证据
     - formal stage demo 46/46 PASS
     - 后续补 RTL-level/Sail 更强 proof
   * - R-07
     - closed
     - CSR 子环境缺失导致自定义 CSR 风险不可控
     - ``csr_unit`` stage 20/20 PASS
     - 继续扩展 WARL/WPRI/WLRL 组合
   * - R-08
     - closed
     - RISC-V compliance 未纳入 full profile
     - compliance stage 85/88 PASS
     - 追踪剩余 3 项差异
   * - R-09
     - controlled
     - CSR-directed 和 integrity fault injection 不适合 Spike lockstep
     - ``cosim-disabled.yaml`` 正式 waiver，含原因、issue、expiry
     - 到期复审，能自检的补 RTL-only coverage
   * - R-10
     - controlled
     - riscv-dv 仍存在失败项但达到当前 gate
     - demo riscvdv 370/395 (93.67%)，fail-rate 低于 ceiling
     - 按失败分类增加 directed/riscv-dv 约束
   * - R-11
     - watch
     - ASSERT coverage 33.33% 较低
     - URG dashboard 已显示，不作为当前 blocker
     - 增加 assertion bind 和触发场景
   * - R-12
     - watch
     - FSM coverage 54.74% 较低
     - URG dashboard 已显示，不作为当前 blocker
     - 添加状态机定向测试和 reset/filter 复核
   * - R-13
     - watch
     - GROUP coverage 69.42%，PMP/CSR/异常 cross 仍可提升
     - functional/pmp coverage 章节已有模型
     - 优先补 PMP lock/TOR/NAPOT/异常 cross
   * - R-14
     - historical
     - 早期 release-readiness 认为 v1.0 不能 GA
     - 后续 ADR、子环境、coverage gate、LEC flow 已补齐
     - 仅作为风险来源保留，不覆盖当前 demo 结论
   * - R-15
     - controlled
     - NC 迁移历史产生覆盖率真实性 bug
     - 当前 release 参考仍以 VCS/URG demo 数据为准；NC 走 ``cov_full_nc.ccf`` + IMC
       独立 dashboard，不复用早期错误数据
     - 保留 NC cross-check、sign-off/demo 和 wave_debug 入口，同时标明 branch 口径差异
   * - R-16
     - watch
     - 双线程场景仍需要更多 per-hart stress
     - ADR-0016 定义 multi-hart cosim 路由
     - 扩展 NUM_THREADS=2 directed、mailbox 和 interrupt stress

测试与验证
----------

风险登记的验证来自两个层面。第一层是静态检查：无过时口径、无未登记 waiver、
ADR 索引连续、文档能构建。第二层是 sign-off 数据：9/9 stage PASS、coverage gate
PASS、waiver schema PASS、formal 46/46、LEC 31635/31635。

.. code-block:: text

   Demo 2026-05-19 01:02
   Status: PASS
   9/9 Stages PASS
   real run coverage: 102/104 (98.1%)
   riscvdv: 370/395 (93.67%)
   compliance: 85/88 (96.59%)
   formal: 46/46 (100%)
   LEC: 31635/31635 PASS

已知限制与未来工作
------------------

当前 residual risk 的优先级不是「把所有百分比一次拉满」，而是先保证真实性和可追溯。
短期工作应集中在 4 个方向：waiver 到期复审、riscv-dv 失败分类、低 ASSERT/FSM
覆盖分析、compliance 剩余 3 项定位。中期工作包括 NUM_THREADS=2 扩展、RVFI/Sail
更强一致性检查、top-level LEC 工具升级复测。

风险升级规则
------------

当后续回归出现下列情况时，应把对应 watch 或 controlled 项升级为 release blocker。
升级动作包括：在本页修改状态、在 :ref:`known_limitations` 增加影响说明、在
相关 ADR 或 issue 中记录根因，并在 sign-off 报告中保留失败证据。

.. list-table:: 风险升级触发条件
   :header-rows: 1
   :widths: 26 36 38

   * - 触发条件
     - 影响
     - 必需动作
   * - coverage gate 低于阈值
     - ``make signoff`` 应失败
     - 不允许降低阈值绕过；先分析 coverage dashboard 和 testlist 变化
   * - waiver schema 失败
     - cosim-disabled gate 不可信
     - 修复 YAML 字段、expiry 或测试名映射后重跑 schema 校验
   * - LEC 出现 failing compare point
     - syn stage 不能签发
     - 定位到 block report，确认不是手工报告污染
   * - riscv-dv fail rate 超过 ceiling
     - stage waiver 失效
     - 分类失败模式，增加 directed repro 或修复生成约束
   * - NC 调试结果被误用为 release coverage
     - coverage 真实性受损
     - 区分 VCS/URG release 参考与 NC/IMC 备选 dashboard；需要 release 参考时重新生成
       VCS/URG dashboard

参考资料
--------

* :ref:`adr_summary` - 关闭风险所依赖的 ADR。
* :ref:`coverage_plan` - coverage 风险的工程化闭门策略。
* :ref:`known_limitations` - controlled/watch 项的展开。
* :ref:`signoff_flow` - stage gate 与 fail-rate ceiling。
* :file:`docs/cosim-known-limitations.md` - cosim remaining limitations。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页的决策、风险或 coverage 结论依赖哪一条 ADR、脚本或 sign-off 证据？
2. 该结论是否区分当前事实、历史背景和未来工作？
3. 是否避免了旧 coverage 维度、旧 NC 口径和伪 dashboard 叙述？
4. 如果该决策被修改，最先需要同步哪些 Makefile、YAML、脚本或章节？
5. reviewer 能否从本页追到 2026-05-19 demo 的统一数字和 LEC 证据？
