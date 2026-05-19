.. _adr-0019:

ADR-0019: LEC Tool Version Limitation
========================================

:status: Open（已被 ADR-0020 关闭）
:source: docs/adr/0019-lec-tool-version-limitation.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

Formality O-2018.06-SP1 处理 2D packed array port flattening 时产生
194 个 failing points（全部 unmatched reference ports）。
工具升级到 2020.09+ 可解决。

§2  根因
---------

194 个 failing points 来自 2D packed array：``ic_wr_data`` （142）、
``btb_rw_addr`` （18+18）、``btb_sram_rd_tag_f1`` （10）、trace 2D ports（6）。
非 RTL bug，纯工具匹配问题。

§3  决策
---------

**不使用** ``set_dont_verify_points`` 豁免。这些不是语义差异而是工具限制。
首选关闭路径：工具升级。

§4  后果
---------

后续 ADR-0020 通过 block-level LEC 路径关闭此限制。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - Formality 工具版本限制
     - :file:`docs/adr/0019-*`
   * - 代码路径 1
     - :file:`syn/scripts/lec_run.tcl`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`syn/scripts/lec_rc4_fix.tcl`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`syn/scripts/lec_blocklevel`
     - 当前仓库实际文件


签核与边界
----------

该 ADR 是历史问题记录，当前不再用 tool-version waiver 宣称通过。sign-off 使用 ADR-0020 的 block-level LEC，结果为 31635/31635 PASS。

统一签核口径为 2026-05-19 01:02 VCS 主线 demo：``9/9`` stages PASS，实跑覆盖率
``102/104`` （98.1%），LEC ``31635/31635`` PASS。覆盖率由 VCS ``simv.vdb``
经 URG 原生 dashboard 生成，编译时 :file:`dv/uvm/core_eh2/cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，指标为 ``line+tgl+assert+fsm+branch`` 五维，
不包含 cond 维度。NC 仅保留 ``SIMULATOR=nc WAVES=1`` 的单测波形调试用途。

参考章节
--------

* :ref:`adr_summary`
* :ref:`signoff_flow`
* :ref:`appendix_b_uvm/index`
* :ref:`appendix_c_tools/index`
