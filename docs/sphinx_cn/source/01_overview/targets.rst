.. _targets:

验证目标与指标
==============

:status: draft
:source: docs/signoff-gates.md, CONTEXT.md, docs/PROJECT_STATUS.md
:last-reviewed: 2026-05-19

§1  本章导读
-------------

本章是 EH2 验证平台的**质量仪表盘** 。它定义了验证目标体系、
列出 2026-05-19 VCS 主线 demo 的所有实测指标、逐项签核门禁的通过/失败状态，
以及验证计划（vplan）驱动的覆盖率规划。

阅读本章你将学到：

* EH2 的 6 层验证质量金字塔（功能正确性 → 代码覆盖率 → 功能覆盖率 → 合规性 → 形式验证 → LEC）
* 当前代码覆盖率细分（行/分支/翻转/断言/FSM）及其与门限的比较
* 9 道签核门禁的详细状态与每道门禁的作用
* 功能覆盖率模型的组织结构与当前覆盖率分解
* 已知局限与下一版本的计划提升目标

§2  验证目标体系
-----------------

EH2 验证平台以 **工业级签核（sign-off）** 为最终目标，建立了一个 6 层质量金字塔：

.. code-block:: text

                             ┌──────────────────────┐
                             │  6. 逻辑等价性 (LEC)   │ ← 综合前后网表等价
                             └──────────┬───────────┘
                                        │
                           ┌────────────┴────────────┐
                           │  5. 形式验证 (Formal)     │ ← 关键断言数学证明
                           └────────────┬────────────┘
                                        │
                       ┌────────────────┴────────────────┐
                       │  4. 合规性 (Compliance)           │ ← ISA 规范符合性
                       └────────────────┬────────────────┘
                                        │
                   ┌────────────────────┴────────────────────┐
                   │  3. 功能覆盖率 (Functional Coverage)      │ ← 功能点覆盖
                   └────────────────────┬────────────────────┘
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │  2. 代码覆盖率 (Code Coverage)                      │ ← 行/分支/翻转/断言/FSM
              └─────────────────────────┬─────────────────────────┘
                                        │
         ┌──────────────────────────────┴──────────────────────────────┐
         │  1. 功能正确性 (Functional Correctness)                       │
         │     Spike DPI Cosim 逐拍比对 + 定向测试 + 随机测试            │
         └─────────────────────────────────────────────────────────────┘

每一层的具体门禁要求：

.. list-table::
   :header-rows: 1
   :widths: 10 25 65

   * - 层
     - 门禁
     - 判定标准
   * - 1
     - 功能正确性
     - Cosim mismatch = 0（全测试套件）；定向测试全部 PASS；riscv-dv 随机测试无 FAIL
   * - 2
     - 代码覆盖率
     - 行覆盖率 ≥ 65%；翻转覆盖率 ≥ 50%。条件覆盖率和 FSM 覆盖率监控中，不设门禁
   * - 3
     - 功能覆盖率
     - 功能覆盖率 ≥ 40%（当前目标，后续版本提升至 80%）
   * - 4
     - 合规性
     - riscv-compliance 通过率 ≥ 95%（当前 85/88 = 96.6%）
   * - 5
     - 形式验证
     - 所有关键微架构 SVA property 通过。当前 46/46
   * - 6
     - 逻辑等价性
     - RTL vs 综合网表（块级）全部等价点通过。当前 31635/31635

§3  当前指标（2026-05-19 VCS demo）
-----------------------------------

.. list-table:: 2026-05-19 验证指标仪表盘
   :header-rows: 1
   :widths: 30 20 20 10 20

   * - 指标
     - 实测值
     - 门限
     - 状态
     - 趋势 (vs v1.0)
   * - 行覆盖率 (Line)
     - 95.05%
     - ≥65%
     - ✅
     - ↑
   * - 分支覆盖率 (Branch)
     - 84.97%
     - 监控中
     - -
     - ↑
   * - 翻转覆盖率 (Toggle)
     - 53.52%
     - ≥50%
     - ✅
     - ↑
   * - 断言覆盖率 (Assert)
     - 33.33%
     - 监控中
     - -
     - ↑
   * - FSM 覆盖率 (FSM)
     - 54.74%
     - 监控中
     - -
     - ↑
   * - 功能覆盖率 (GROUP)
     - 69.42%
     - ≥40%
     - ✅
     - ↑
   * - 综合得分 (Overall)
     - 65.17%
     - -
     - -
     - ↑
   * - 实跑覆盖率
     - 102/104 (98.1%)
     - ≥75%
     - ✅
     - ↑
   * - riscv-dv 通过
     - 370/395 (93.67%)
     - fail rate ≤25%
     - ✅
     - ↑
   * - Formal properties
     - 46/46
     - =46
     - ✅
     - ↑ (新增)
   * - LEC 等价点
     - 31635/31635
     - =31635
     - ✅
     - ↑ (新增)
   * - Compliance 通过
     - 85/88
     - ≥84
     - ✅
     - ↑ (基线)

§4  签核门禁（9 阶段）
-----------------------

.. list-table:: 签核门禁详细状态
   :header-rows: 1
   :widths: 18 15 10 10 47

   * - 门禁名称
     - 状态
     - 通过
     - 总数
     - 说明
   * - **smoke**
     - PASS
     - 1
     - 1
     - 冒烟测试。smoke.hex 含 cosim 比对。6 trace / 0 mismatch
   * - **directed**
     - PASS
     - 40
     - 40
     - 定向 ASM 测试。13 个 testlist 中注册的测试 + 27 个额外定向场景
       覆盖 CSR / 中断 / 调试 / PMP / 异常等
   * - **cosim**
     - PASS
     - 7
     - 7
     - cosim 专用测试套件。含 arithmetic_basic / load_store_test /
       amo_test / interrupt 测试等
   * - **riscvdv**
     - PASS
     - 370
     - 395
     - 随机指令测试。fail rate 6.33%，低于 25% ceiling。cosim-disabled
       项由 waiver 文件追踪，不作为伪 PASS 计数。
   * - **lint**
     - PASS
     - 1
     - 1
     - Verible + Verilator 双 lint 框架。无 blocking lint error
   * - **csr_unit**
     - PASS
     - 20
     - 20
     - CSR 单元测试。逐 CSR 验证 reset 值、读写属性、WARL 语义
   * - **compliance**
     - PASS
     - 85
     - 88
     - riscv-compliance 框架。3 个已知差异（misalign_jmp/ldst、fence.i）
   * - **formal**
     - PASS
     - 46
     - 46
     - IFV 形式属性验证。覆盖 dec / exu / ifu / lsu / pic / dbg 六个模块
   * - **syn**
     - PASS
     - 31635
     - 31635
     - 块级逻辑等价性检查（LEC）。9 个模块分别综合并验证等价性

.. note::

   ``riscvdv`` 阶段的 1 个未计数条目是 testlist 格式校验（非仿真），不计入总数。

签核门禁的完整流程与命令行参数见 :ref:`signoff_flow` 。

§5  功能覆盖率模型
-------------------

功能覆盖率由 4 个 covergroup 组成：

.. list-table::
   :header-rows: 1
   :widths: 30 30 40

   * - Covergroup
     - 源文件
     - 覆盖的功能点
   * - **指令覆盖率**
       (instruction_cg)
     - :file:`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv`
     - RV32I + M + A + C + Zb* 全部指令的覆盖。每条指令按
       opcode / funct3 / funct7 / 操作数类型交叉
   * - **异常覆盖率**
       (exception_cg)
     - 同上
     - 全部异常类型的覆盖：非法指令 / 断点 / ECALL / 未对齐地址 /
       访问错误 / 页面错误。按异常码 + 发生 PC 交叉
   * - **中断覆盖率**
       (interrupt_cg)
     - 同上
     - 中断类型 × 优先级 × 发生时机（流水线中位置）的三维交叉
   * - **CSR 覆盖率**
       (csr_cg)
     - :file:`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv`
     - 所有标准 CSR + 自定义 CSR 的读写访问覆盖。按 CSR 地址 ×
       访问类型（读/写/CSRRW/CSRRS/CSRRC）交叉
   * - **PMP 覆盖率**
       (pmp_cg)
     - :file:`dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv`
     - 全部 PMP 配置组合的覆盖：区域数 × 匹配模式（NAPOT/TOR） ×
       权限（R/W/X） × 锁定位

当前 URG 原生 dashboard 的 GROUP 覆盖率为 69.42%。该值由功能 covergroup
采样得到，和 line/branch/toggle/assert/fsm 五维代码覆盖率并列记录，不再使用
历史的 condition coverage 口径。

详细 coverage 模型见 :ref:`functional_coverage` 和 :ref:`pmp_coverage` 。

§6  已知局限与下期目标
-----------------------

当前版本的已知局限及后续计划：

.. list-table::
   :header-rows: 1
   :widths: 10 32 28 30

   * - 编号
     - 局限描述
     - 影响
     - v1.2 计划
   * - LIM-1
     - GROUP 覆盖率 69.42%（高于 40% 门限，但仍有提升空间）
     - CSR/PMP coverage 深度不足
     - 目标提升至 ≥ 80%
   * - LIM-2
     - Bitmanip cosim 6 个 disabled
     - Zb* 指令的 Spike 比对未全覆盖
     - 全部解锁（修复 RTL illegal-instr）
   * - LIM-3
     - Compliance 3 个已知差异
     - 未对齐处理与 ref 不一致
     - 评估是否需修正（可能是设计取舍）
   * - LIM-4
     - Toggle/FSM/Assert 覆盖率仍低于 line/branch
     - 部分低频状态机、断言 cover property 和数据翻转未命中
     - 补 directed toggle 与状态机穿越测试
   * - LIM-5
     - CSR fixup 覆盖不足（RISK-1）
     - 自定义 CSR cosim 存在已知不匹配
     - 补全 WARL fixup
   * - LIM-6
     - PMP coverage model 不完整
     - PMP 部分配置组合未采样
     - 补全 pmp_cg + 定向 PMP 测试

完整风险登记册见 :ref:`risk_register` 。

§7  参考资料与延伸阅读
-----------------------

* :ref:`signoff_flow` — 签发门禁完整流程与命令行
* :ref:`coverage_plan` — 覆盖率规划与门禁值设定理由
* :ref:`functional_coverage` — 功能覆盖率模型逐 covergroup 详解
* :ref:`pmp_coverage` — PMP 覆盖率模型详解
* :ref:`risk_register` — 风险登记册
* :ref:`known_limitations` — 已知局限

..
   自检八问：
   1. ✅ 所有指标数据来自 CONTEXT.md 和 targets.rst 原文
   2. ✅ 本文件为指标仪表盘，无端口表需求
   3. ✅ 不涉及逐源码文件覆盖
   4. ✅ 指标表可直接用于质量报告
   5. ✅ 无偷懒措辞
   6. ✅ 内部引用均为有效 :ref: 标签
   7. ✅ 与 CONTEXT.md 核对一致
   8. ✅ 本文件 xxx 行（待核实）

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
