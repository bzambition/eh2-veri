.. _adr-0006:

ADR-0006: Atomic (A-subset) Cosim Fixup
==========================================

:status: Accepted
:source: docs/adr/0006-atomic-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：EH2 名义上支持 RV32IMA**C** + Zb*，但原子指令（A 子集）从未对 Spike
ISS 做过验证。``amo_test`` 自始至终都是 ``cosim: disabled`` ，``spike_cosim.cc``
没有任何原子指令特定的 fixup，RISK-11 追踪了"atomic SC.W RTL writeback 和 Spike
divergence"问题。ISA 字符串声称支持"A"，但对 LR/SC/AMO 指令没有任何 ISS 黄金参考
比较——这是一个发布阻塞级别的 gap。

**决策** ：在 ``spike_cosim.cc`` 中增加原子指令特定 fixup，包含两个部分。第一部分
是 SC.W GPR writeback fixup：SC.W 的成功/失败由 reservation 状态决定，Spike 的
内部 reservation 跟踪基于其自身的 memory model，而 EH2 的 reservation 在 LSU AXI
层面跟踪，两者可能合法地不一致（例如另一个线程的 store 清除了 Spike 的 reservation
但未清除 EH2 的）。fixup 使得当最后一条提交指令是 SC.W 且 rd writeback 值不一致
时，DUT 为 authoritative，Spike 的 GPR 被 DUT 的 SC 结果覆盖以保持后续指令执行的
一致性。第二部分是 LR reservation 跟踪：LR.W 设置 reservation 地址，fixup 在
``PerThreadState::lr_reservation_addr`` 中记录该地址，用于检测需要 fixup 的 SC.W
操作。SC.W 执行时无论结果如何都清除 reservation（符合 RISC-V 规范：SC.W 清除任何
未决 LR reservation）。

**后果** ：``amo_test`` cosim 启用，新增 ``cosim_atomic_basic.S`` 作为定向 cosim
证明测试。Spike 的 GPR 状态可能在 SC.W divergence 后被修改
（DUT-authoritative fixup）。reservation 跟踪最小化且仅用于 SC.W 检测。
备选方案中的"禁用 SC.W 随机生成""set_csr 绕过"均被否决，理由是违反了不允许用
set_csr fixup 绕过原子实现的底线要求。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - Atomic/LR-SC cosim fixup
     - :file:`docs/adr/0006-*`
   * - 代码路径 1
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/tests/asm/cosim_atomic_basic.S`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
     - 当前仓库实际文件


签核与边界
----------

当前测试池包含 cosim_atomic_basic.S，SpikeCosim 为每个 hart 维护 LR reservation 与 SC.W 结果对齐逻辑。该策略只在 LR/SC 语义允许分歧时进行状态修正。

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
