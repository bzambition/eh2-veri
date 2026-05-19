.. _adr-0014:

ADR-0014: Formal Verification -- Real Runs
============================================

:status: Accepted
:source: docs/adr/0014-formal-real-runs.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

``dv/formal/`` 下有 4 个 .sby 配置 + 4 个 property 文件（23 assertions +
10 cover points），但 yosys/sby 不在 PATH 中。

§2  决策
---------

使用 ``sby_shim.py`` + Z3 4.15.4 作为形式验证引擎。
对每个 property 执行 BMC depth=25。

§3  结果
---------

全部 22 个断言通过 Z3 BMC 证明（PASS depth 25）。
0 failed, 0 vacuous proofs, 10 cover points 全部 covered。

**限制：** RTL-level BMC 不可用（yosys 不在 PATH）。
SAIL-REF properties 尚未集成。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - formal real-run 证据
     - :file:`docs/adr/0014-*`
   * - 代码路径 1
     - :file:`dv/formal/scripts/ifv_prove.tcl`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/formal/ifv_filelist.f`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/formal/known_fails.md`
     - 当前仓库实际文件


签核与边界
----------

当前 real-run 证据从 IFV assertion summary 读取，不从 property 文件行数推导。formal stage 的 46/46 PASS 与脚本解析结果一致。

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
