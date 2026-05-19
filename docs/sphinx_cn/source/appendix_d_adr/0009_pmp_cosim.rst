.. _adr-0009:

ADR-0009: PMP/ePMP Cosim Closure
===================================

:status: Accepted
:source: docs/adr/0009-pmp-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：``spike_cosim.cc`` 中的 ``misaligned_pmp_fixup`` 函数是一个空 stub，
导致全部 6 个 PMP/ePMP 测试均为 ``cosim: disabled`` 。PMP 是隔离内存区域的安全关键
功能，ePMP（增强 PMP 带 MML/MMWP/RLB）增加了 Machine-Mode Whitelist Policy。没有
ISS 黄金参考的 PMI（Physical Memory Integrity）验证对工业发布来说是不充分的。

**决策** ：第一，实现 ``misaligned_pmp_fixup``——检查是否有任何 PMP 区域启用（通过
pmpcfg L 位），扫描 pending dside accesses 中标记为错误的条目（PMP fault 路径），
移除 faulting access 条目使 Spike 的内存比较不会 stall。这处理了常见情况：未对齐
load/store 跨越 PMP 区域边界，其中一半 fault 而另一半成功。第二，PMP CSR
pass-through——PMP 配置寄存器（pmpcfg0-3）和地址寄存器（pmpaddr0-15）通过
``put_csr()`` 原生转发到 Spike。Spike 的 TLB/mmu 层已实现标准 PMP 匹配。ePMP
特定位（pmpcfg 高字节的 mml/mmwp/rlb）由 Spike 的 put_csr 保留。第三，测试解锁——
全部 6 个 PMP 测试移除 ``cosim: disabled`` ，包括 pmp_basic（4 区域基本 PMP）、
pmp_disable_all、pmp_random（8 个随机区域）、epmp_mml、epmp_mmwp、epmp_rlb。

**已知限制** ：Spike 中未建模完整的 ePMP 状态机（mml/mmwp/rlb 交互），测试这些
扩展可能看到 divergence。未建模带 cacheability 属性（mrac 交互）的未对齐 PMP
访问。复杂的 PMP 区域重叠行为在 EH2 和 Spike 之间可能不同。

**后果** ：6 个 PMP 测试尝试 cosim lockstep。PMP CSR 写入传播到 Spike 进行原生
PMP 匹配。misaligned_pmp_fixup 处理常见的跨边界 fault 情况。ePMP 特定 divergence
通过子 issue 追踪。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - PMP/ePMP cosim 与覆盖率
     - :file:`docs/adr/0009-*`
   * - 代码路径 1
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/formal/properties/eh2_pmp_assert.sv`
     - 当前仓库实际文件


签核与边界
----------

PMP 相关验证由三层组成：Spike CSR/访问比较、functional coverage 的 PMP covergroup，以及 formal property 对区域匹配和 fault 行为的断言。当前 formal stage 为 46/46 PASS。

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
