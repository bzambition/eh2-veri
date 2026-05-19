.. _adr-0020:

ADR-0020: Block-level LEC and Packed-port Mitigation
=======================================================

:status: Accepted
:source: docs/adr/0020-blocklevel-lec.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

ADR-0019 记录了顶层 LEC 的 194 个 failing points（2D packed-array port）。
需要在不升级 EDA 工具的情况下关闭。

§2  决策
---------

使用 block-level LEC 流程作为关闭路径：
- 将整体 EXU 分解为子 block（alu_ctl/mul_ctl/div_ctl）
- 不使用 waiver（``set_dont_verify_points`` ）
- 每个 block 使用有效的 per-block SVF 文件

§3  结果
---------

**31635 passing, 0 failing, 0 unverified compare points**
- eh2_dec、eh2_lsu、eh2_pic_ctrl、eh2_dma_ctrl、eh2_dbg、eh2_ifu：Verification SUCCEEDED
- EXU 子 block：alu_ctl 294/0/0, mul_ctl 272/0/0, div_ctl 181/0/0

§4  后果
---------

通过非 waiving 的 block-level 路径关闭了原始 194 个顶层 failure。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - block-level LEC closure
     - :file:`docs/adr/0020-*`
   * - 代码路径 1
     - :file:`syn/scripts/lec_blocklevel`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`syn/scripts/lec_summary.py`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`syn/build/lec_summary.txt`
     - 当前仓库实际文件


签核与边界
----------

当前 syn stage 以 block-level LEC 为 gate。2026-05-19 demo 中 9 个模块 total 31635 passing、0 failing、0 unverified，LEC 31635/31635 PASS。

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
