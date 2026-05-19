.. _appendix_d_adr_index:

附录 D — ADR 全文
==================

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本附录转载 20 条架构决策记录（ADR）的全文内容。每一条 ADR 原文在 :file:`docs/adr/NNNN-<title>.md` 中。
这些页面保留原 ADR 的历史语义，同时在每条末尾补充 2026-05-19 当前实现映射、
sign-off 证据和阅读边界。ADR 不是测试报告，不能用来替代
:ref:`signoff_flow` 或 :ref:`scripts_reference` 的脚本说明。

当前主线口径
------------

.. list-table::
   :header-rows: 1
   :widths: 24 36 40

   * - 项目
     - 当前值
     - 说明
   * - 默认 simulator
     - VCS
     - 与 Ibex UVM 主线一致；NC 仅用于单测波形调试
   * - coverage metrics
     - ``line+tgl+assert+fsm+branch``
     - 不使用 cond 维度
   * - coverage scope
     - ``+tree core_eh2_tb_top.dut``
     - 编译时 :file:`cover.cfg` DUT-only scope
   * - sign-off
     - ``9/9`` stages PASS
     - 2026-05-19 01:02 demo
   * - LEC
     - ``31635/31635`` PASS
     - block-level Formality gate
   * - coverage dashboard
     - OVERALL ``65.17%``
     - LINE ``95.05%``、BRANCH ``84.97%``、TOGGLE ``53.52%``、ASSERT ``33.33%``、FSM ``54.74%``

目录
----

* :ref:`adr-0001` — Cosim via trace and probe
* :ref:`adr-0002` — AXI4 passive monitoring
* :ref:`adr-0003` — NUM_THREADS cosim scope
* :ref:`adr-0004` — RTL RVFI-equivalent trace
* :ref:`adr-0005` — Spike cosim store wider WSTRB
* :ref:`adr-0006` — Atomic cosim fixup
* :ref:`adr-0007` — Interrupt cosim closure
* :ref:`adr-0008` — Debug cosim closure
* :ref:`adr-0009` — PMP/ePMP cosim closure
* :ref:`adr-0010` — CSR register model
* :ref:`adr-0011` — Compliance framework
* :ref:`adr-0012` — Formal verification strategy
* :ref:`adr-0013` — Synthesis toolchain
* :ref:`adr-0014` — Formal real runs
* :ref:`adr-0015` — RVFI adapter layer
* :ref:`adr-0016` — Multi-hart cosim
* :ref:`adr-0017` — Integrity cosim waiver
* :ref:`adr-0018` — wb_tag strict matching
* :ref:`adr-0019` — LEC tool-version limitation
* :ref:`adr-0020` — Block-level LEC closure
* :ref:`adr-template` — 后续 ADR 模板

.. note::

   每一条 ADR 的 :status: 字段与原 Markdown 文件中的状态一致。
   ADR 汇总见 :ref:`adr_summary` 。

与 Ibex 工业实现对照
--------------------

EH2 的 ADR 体系沿用 lowRISC Ibex 的核心工程习惯：把 simulator、coverage、
cosim、formal、compliance、lint 和 synthesis 的关键取舍写成可追溯决策，
而不是散落在脚本注释中。主要对照路径为
:file:`/home/host/ibex/dv/uvm/core_ibex/README.md`、
:file:`/home/host/ibex/dv/uvm/core_ibex/cover.cfg`、
:file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py` 和
:file:`/home/host/ibex/dv/uvm/core_ibex/yaml/rtl_simulation.yaml`。

EH2 的合理差异集中在双线程、AXI4、PIC/DMA/DMI/JTAG、RVFI adapter、CSR unit
子环境和 block-level LEC。阅读 ADR 时应优先区分「沿用 Ibex 模式」和「EH2
特有结构」：前者包括 VCS 主线、URG coverage、riscv-dv extension 和 UVM 1.2
testbench；后者包括 per-hart Spike 路由、trace/probe 混合数据源、PMP/ePMP
覆盖率、完整性 cosim waiver 和 Formality block-level closure。
