.. _known_limitations:
.. _07_decisions/known_limitations:

已知限制
========

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

已知限制页记录当前 release 在 PASS 之后仍需要诚实披露的边界。它不否定
2026-05-19 demo 的 sign-off 结论：Status PASS，9/9 stages PASS，实跑覆盖率
102/104 (98.1%)，LEC 31635/31635 PASS。它的作用是防止把「通过当前 gate」误读为
「所有技术债都已经消失」。当前限制主要集中在 5 类：coverage 深度、ISS 不可比
测试、compliance 剩余差异、NC 调试路径边界、以及未来工具/形式化增强。

本章使用 ``controlled``、``watch`` 和 ``future`` 3 种状态。``controlled`` 表示
已有 gate 或 waiver 管理，当前不阻断 release；``watch`` 表示数字偏低或覆盖洞需要
持续提升；``future`` 表示需要工具升级、标准接口或更大工程量支撑，不能在当前
release 中临时补齐。

设计目标与约束
--------------

限制清单必须满足两个约束。第一，限制必须可追溯到代码、配置、报告或 ADR，不能
写成抽象担忧。第二，限制不能引入过时事实；比如把 NC 写成主线 simulator、把
condition coverage 写成当前硬门限，或沿用旧 release 数字，均不能作为当前限制描述。
对于 ISS 不可比的 integrity fault
injection，限制的核心不是「测试没做」，而是「Spike 作为 ISA simulator 不建模
微架构 fault injection，因此需要 waiver、self-check 和 formal/RTL coverage 共同
管理」。

.. note::

   本章的限制都是当前工程边界，不是文档缺口。后续阶段扩写附录时，应继续引用
   同一套 VCS/URG/sign-off 数字，避免章节间口径分裂。

架构与组成
----------

当前限制与 sign-off gate 的关系如下：

::

   Current PASS
      |
      +-- hard gates already passed
      |     |-- 9/9 stages
      |     |-- LINE >= 65
      |     |-- GROUP >= 40
      |     |-- formal 46/46
      |     `-- LEC 31635/31635
      |
      +-- controlled limitations
      |     |-- cosim-disabled waiver YAML
      |     |-- compliance 85/88
      |     `-- NC waveform-only
      |
      +-- watch metrics
      |     |-- ASSERT 33.33%
      |     |-- FSM 54.74%
      |     `-- GROUP holes by covergroup/cross
      |
      `-- future strengthening
            |-- stronger RVFI/Sail integration
            |-- more NUM_THREADS=2 stress
            `-- top-level LEC after tool upgrade

实现细节
--------

waiver 文件说明了哪些 tests 因 Spike 不可比而不能进入 lockstep cosim：

.. literalinclude:: ../../../../dv/uvm/core_eh2/waivers/cosim-disabled.yaml
   :language: yaml
   :lines: 28-75
   :caption: cosim-disabled.yaml:28-75 - CSR hazard 与 integrity waiver 示例

``signoff.py`` 在最终 gate 中检查 cosim-disabled 和 skip-in-signoff 是否有正式
waiver：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 1302-1385
   :caption: signoff.py:1302-1385 - final sign-off waiver gate

coverage parser 保留 ``cond`` alias 是为了兼容旧文本解析，不表示当前 VCS compile
重新启用该维度。真正的 threshold 字典不包含 ``cond``：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 1046-1055
   :caption: signoff.py:1046-1055 - 当前 coverage threshold 字典

``merge_cov.py`` 目前有两个入口，边界不同：metadata-driven legacy 模式仍保持
Ibex-compatible VCS-only no-op 语义；``signoff.py`` 调用的 standalone 模式会自动识别
VCS ``.vdb`` 与 NC ``cov_work/*.ucd``，并分别走 URG 或 IMC：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/merge_cov.py
   :language: python
   :lines: 289-365
   :caption: merge_cov.py:289-365 - legacy metadata 与 standalone coverage merge 入口

配置与使用
----------

限制复审时应先跑检查命令，而不是直接编辑文档：

.. code-block:: bash

   # waiver schema 必须先过
   python3 dv/uvm/core_eh2/scripts/signoff.py \
     --validate-waivers dv/uvm/core_eh2/waivers/cosim-disabled.yaml

   # 查看当前 disabled 或 skip 条目，确认都能映射到 waiver 或 ADR
   rg -n "cosim: disabled|skip_in_signoff|cosim_reason" dv/uvm/core_eh2

   # 查看 coverage dashboard，确认低覆盖项来自 URG 原生报告
   sed -n '1,120p' build/signoff/cov_merged/dashboard.txt

   # 完整重跑当前 gate
   make signoff COV=1 PARALLEL=4

   # NC 备选路径：生成 cov_work，经 IMC 合并为兼容 dashboard
   make signoff SIMULATOR=nc COV=1 PARALLEL=4

与 Ibex 工业实现对照
--------------------

Ibex 文档通常把已知限制、coverage holes 和 waiver 与 testlist/sign-off 脚本绑定。
EH2 采用同样的工程化方式，但限制类型不同。Ibex 主要面对单 hart、Ibex 原生 RVFI
和较小 SoC 边界；EH2 要额外处理双线程、AXI4、多内存域、PIC、DMI/JTAG、DMA、
ECC/integrity fault injection 和 block-level LEC。

.. list-table:: 已知限制对照
   :header-rows: 1
   :widths: 24 34 42

   * - 限制类型
     - Ibex
     - EH2
   * - ISS 不可比测试
     - 通过 testlist/waiver 管理特殊场景
     - integrity fault injection 和部分 CSR hazard 使用正式 waiver YAML
   * - coverage holes
     - 通过 covergroup report 和 directed tests 迭代
     - ASSERT/FSM/GROUP 作为 watch metrics，优先补 PMP/CSR/异常 cross
   * - simulator fallback
     - 多 simulator 支持，但 sign-off 有明确主线
     - 当前默认 release 参考是 VCS/URG；NC/Incisive 是完整备选 simulator，
       使用 ``cov_full_nc.ccf`` 和 IMC dashboard 做 cross-check/备选签核
   * - LEC
     - top-level 路径更直接
     - EH2 用 block-level LEC 关闭 O-2018 packed-port 限制
   * - RVFI
     - 原生 design RVFI
     - EH2 使用 wrapper RVFI adapter，未来仍需更强 riscv-formal/Sail 接入

限制总表
--------

.. list-table:: 当前已知限制
   :header-rows: 1
   :widths: 10 14 30 28 18

   * - ID
     - 状态
     - 限制
     - 当前控制
     - 后续方向
   * - LIM-01
     - watch
     - ASSERT coverage 为 33.33%
     - 作为 URG dashboard watch metric 披露，不作为当前 hard gate
     - 增加 SVA bind 和触发场景
   * - LIM-02
     - watch
     - FSM coverage 为 54.74%
     - 使用 ``cov_fsm.cfg`` 和 reset filter 管理报告
     - 增加状态机定向测试
   * - LIM-03
     - watch
     - GROUP coverage 为 69.42%，PMP/CSR/异常 cross 可继续提升
     - 当前高于 40% gate
     - 补 PMP lock、NAPOT/TOR、CSR WARL cross
   * - LIM-04
     - controlled
     - riscv-dv 为 370/395 (93.67%)，仍有失败项
     - fail-rate 低于 25% ceiling，stage PASS
     - 对失败项分类并补约束/定向测试
   * - LIM-05
     - controlled
     - compliance 为 85/88 (96.59%)，剩余 3 项差异
     - compliance stage PASS，差异不隐藏
     - 对 suite 期望、环境模型和 EH2 行为逐项分析
   * - LIM-06
     - controlled
     - 部分 CSR-directed 和 integrity tests 无法与 Spike lockstep
     - ``cosim-disabled.yaml`` 正式 waiver，含 expiry
     - 到期复审；补 self-check、formal 或专用模型
   * - LIM-07
     - controlled
     - NC/Incisive coverage 与 VCS/URG 口径不完全同构，尤其 branch 在 NC 152 IMC 中
       与 block/LINE 口径相关
     - Makefile 支持 ``SIMULATOR=nc``，``merge_cov.py`` standalone 模式用 IMC 输出兼容 dashboard
     - 保留 VCS 作为默认 release 参考；NC 报告必须标注 IMC 与 branch 口径差异
   * - LIM-08
     - future
     - RVFI adapter 仍是 sidecar，不是 EH2 design 原生接口
     - ADR-0015 定义 wrapper 边界
     - 接入 riscv-formal/Sail 时做独立一致性验证
   * - LIM-09
     - future
     - top-level Formality 在旧工具上受 packed-port 限制
     - ADR-0020 block-level LEC 已闭合 release gate
     - 工具升级后复测 top-level LEC
   * - LIM-10
     - watch
     - NUM_THREADS=2 stress 和 per-hart corner 仍需扩大
     - ADR-0016 定义 multi-hart cosim 支撑方向
     - 增加双线程 mailbox、中断、debug、PMP 组合测试

测试与验证
----------

限制清单的验证要求是「每条限制都有当前证据」。下面是 release review 时应核对的
最小证据集合：

.. code-block:: text

   Sign-off:
     Status: PASS
     9/9 Stages PASS
     real run coverage: 102/104 (98.1%)

   Coverage:
     LINE     95.05%
     BRANCH   84.97%
     TOGGLE   53.52%
     ASSERT   33.33%
     FSM      54.74%
     GROUP    69.42%
     OVERALL  65.17%

   Stage detail:
     directed   40/40 (100%)
     riscvdv    370/395 (93.67%)
     compliance 85/88 (96.59%)
     formal     46/46 (100%)
     LEC        31635/31635 PASS

如果后续 demo 更新了这些数字，应一次性更新本页、:ref:`coverage_plan`、
:ref:`risk_register` 和 :ref:`signoff_flow`，避免跨章节不一致。

已知限制与未来工作
------------------

当前限制的推荐处理顺序如下。第一，持续保持 VCS/URG coverage 真实性，任何新工具路径
都必须先证明不会污染 DUT-only scope。第二，复审 waiver expiry，能用 RTL-only
self-check 或 formal property 证明的场景应补充证据。第三，把 ASSERT/FSM 低覆盖项
转化为具体 SVA 和 directed test。第四，分析 compliance 剩余 3 项的根因。第五，
在工具条件允许时复测 top-level LEC，并评估是否继续保留 block-level gate 作为
release 主线。

限制关闭规则
------------

关闭一条限制需要同时满足 3 个条件：有代码或配置变更，有自动化证据，有文档同步。
例如，若未来要关闭 LIM-04，不能只把 riscv-dv 失败项从报告里移除；必须给出失败项
减少的 testlist 或 RTL/scoreboard 修复、重新运行 sign-off，并更新 demo 数字。若要
关闭 LIM-06，必须证明对应测试可由 Spike 或其它 golden model 正确建模，或者补充
等价强度的 RTL-only/formal 证据并更新 waiver 策略。

.. list-table:: 限制关闭检查
   :header-rows: 1
   :widths: 24 38 38

   * - 限制类型
     - 关闭证据
     - 不能接受的做法
   * - coverage watch
     - 新 URG dashboard、命中 bin 分析、对应测试入口
     - 修改报告文本或扩大 scope 制造提升
   * - waiver controlled
     - waiver 删除或缩小后 ``make signoff`` 仍 PASS
     - 仅删除 YAML entry 而不运行 gate
   * - compliance residual
     - compliance stage 数字更新且失败日志消失
     - 改 wrapper 让测试静默跳过
   * - NC 边界
     - 若未来变成签核路径，需提供完整 coverage merge、gate 和 Ibex 对照
     - 把单测波形成功当作 release 证据
   * - LEC future
     - top-level 或 block-level Formality 报告均可追溯且无 failing/unverified blocker
     - 使用 ``set_dont_verify_points`` 掩盖真实差异

参考资料
--------

* :ref:`coverage_plan` - coverage 限制与提升路线。
* :ref:`risk_register` - residual risk 管理。
* :ref:`adr-0017` - integrity cosim waiver。
* :ref:`adr-0020` - block-level LEC closure。
* :ref:`signoff_flow` - 当前 demo 和 gate 细节。

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
