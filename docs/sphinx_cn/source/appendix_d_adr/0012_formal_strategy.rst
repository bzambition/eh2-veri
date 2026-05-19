.. _adr-0012:

ADR-0012: Formal Verification Strategy for EH2
=================================================

:status: Proposed
:source: docs/adr/0012-formal-strategy.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 验证复杂度不断增长，30+ RTL 模块。模拟验证无法穷举 pipeline hazards、
PMP 地址匹配、debug FSM 和中断优先级仲裁等 corner case。

§2  决策
---------

部署多模块形式验证策略，4 个独立 property set：
- ``eh2_pmp_assert.sv`` ：PMP/MPU 地址检查（7 assert + 1 cover）
- ``eh2_dec_assert.sv`` ：pipeline 解码和 CSR 合法性（5+1）
- ``eh2_dbg_assert.sv`` ：debug FSM 和 halt/resume（5+1）
- ``eh2_pic_assert.sv`` ：中断优先级树和 claim/complete（5+1）
- ``sail_bridge.sv`` ：架构不变量（3 SAIL-REF assert）

总计 25 assertions + 4 cover points。
引擎：Symbiyosys ``smtbmc z3`` （Z3 BMC）。depth=20-25。

§3  后果
---------

4 个独立可证明的 property set 可并行运行。通过 sail-riscv 验证架构不变量。
但 BMC depth（20-30）可能遗漏深层时序 bug。后续可通过 k-induction 扩展。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - IFV/Symbiyosys 双流形式验证
     - :file:`docs/adr/0012-*`
   * - 代码路径 1
     - :file:`dv/formal/Makefile`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/formal/eh2_veer_sva.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/formal/properties`
     - 当前仓库实际文件


签核与边界
----------

当前 formal stage 使用 Cadence IFV 主线，并保留 Symbiyosys 配置作为开源辅助路径。2026-05-19 demo 中 formal 为 46/46 PASS。

统一签核口径为 2026-05-19 01:02 VCS 主线 demo：``9/9`` stages PASS，实跑覆盖率
``102/104`` （98.1%），LEC ``31635/31635`` PASS。覆盖率由 VCS ``simv.vdb``
经 URG 原生 dashboard 生成，编译时 :file:`dv/uvm/core_eh2/cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，指标为 ``line+tgl+assert+fsm+branch`` 五维，
不包含 cond 维度。NC/Incisive 是完整备选 simulator，可运行 smoke、regress、sign-off、demo 与覆盖率 cross-check；默认 release 参考仍为 VCS/URG。

参考章节
--------

* :ref:`adr_summary`
* :ref:`signoff_flow`
* :ref:`appendix_b_uvm/index`
* :ref:`appendix_c_tools/index`
