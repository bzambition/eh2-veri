.. _adr-0005:

ADR-0005: Spike-cosim 接受 EH2 store wider WSTRB
===================================================

:status: Accepted
:source: docs/adr/0005-spike-cosim-store-wider-wstrb.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 LSU 对子字节存储（SB/SH）在 AXI4 输出时把整个 4 字节 word 的 WSTRB 全部置 1
（``4'b1111`` ），通过内部 RMW 将非目标字节填回原值。Spike 默认假设 store 的 WSTRB
严格等于 ISA 期望的 byte mask，导致误报 BE mismatch。

§2  决策
---------

修改 ``spike_cosim.cc:check_mem_access`` 的 store-side BE 检查，采用超集容忍：
只要 DUT BE **包含** ISA 期望的 byte mask 即接受。多出的字节认为是 RTL RMW 行为，
不影响架构正确性。Store 和 load 的 BE 检查实现对称（load 此前已容忍超集）。

§3  后果
---------

- SB/SH 不再误报 BE mismatch
- **已知 trade-off** ：失去了对"DUT 多写额外字节但内容错误"的检测能力。
  但 data 检查仍通过 mask 后比对确保 ISA 期望字节的内容正确。
- 前提是 EH2 RTL 的 RMW 不破坏额外字节

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - Spike store byte-enable 容忍策略
     - :file:`docs/adr/0005-*`
   * - 代码路径 1
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/cosim/spike_cosim.h`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv`
     - 当前仓库实际文件


签核与边界
----------

当前 C++ cosim 仍以 EH2 LSU 的 AXI4 strobes 作为观测输入；store-side 比较只要求 DUT strobe 覆盖 ISA 期望字节，避免把 RTL 内部 RMW 行为误报为架构错误。

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

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 这条 ADR 的状态、日期和决策边界是什么？
2. 它解决的是 cosim、coverage、formal、synthesis、LEC、RVFI 还是 waiver 问题？
3. 该 ADR 对应的实现文件或 sign-off gate 是哪一个？
4. 当前 VCS/URG 默认 release 参考与 NC/Incisive 备选路径是否被正确区分？
5. 若该 ADR 需要修订，是否应新增 superseding ADR 而不是静默改写历史？
