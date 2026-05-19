.. _adr-0007:

ADR-0007: Interrupt Cosim Closure
====================================

:status: Accepted
:source: docs/adr/0007-interrupt-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：EH2 有 8 个中断相关的 riscv-dv 测试均 ``cosim: disabled`` ，整个中断
子系统从未对 Spike ISS 进行过验证。中断入口/出口是 RTL 中最 corner-case 丰富的
路径，是 P0 发布阻塞项。gap 涵盖了通用中断注入（interrupt_test）、单中断
（irq_single_test）、WFI 唤醒（irq_wfi_test）、中断期间 CSR 交互
（irq_csr_test）、嵌套中断（irq_nest_test）、stress 测试、复位中段测试
（reset_test）以及中断中调试测试（irq_in_debug_test）。

**决策** ：第一，利用已有的中断-only trace item 识别机制——scoreboard 已经区分了
interrupt-only trace item（``interrupt=1 && exception=0`` ）和 exception trace
item。对于 interrupt-only item，Spike 的 ``set_mip()`` 被调用来更新中断 pending
位，Spike 不执行 ``step()`` ，因为没有指令被执行。mcause/mepc 比较使用
UVM_ERROR + mismatch_count。第二，PIC CSR 注册——28 个 EH2 custom CSR，包括所有
PIC 寄存器（meivt, meipt, meicurpl, meicidpl, meihap）在 spike_cosim.cc 中通过
``initial_proc_setup()`` 注册，并在 ``fixup_csr()`` 中做 WARL fixup。第三，嵌套
中断 mstatus 栈——EH2 仅支持 M-mode，mstatus.mpp 总是解码为 M。嵌套中断在硬件栈
上 push/pop mstatus.mpie/mie/mpp，cosim scoreboard 依赖 set_csr fixup 保持 Spike
的 mstatus 与 DUT 对齐。第四，测试解锁策略——所有 8 个中断测试均移除
``cosim: disabled`` ，任何 cosim 失败的测试将生成子 issue 而非重新禁用。

**后果** ：8 个中断测试现在尝试 cosim lockstep。mcause/mepc mismatch 现在正确处理
为测试失败（之前为 silent INFO）。PIC 行为通过 set_csr 注册建模，而非完整的 PIC
仿真。如果嵌套中断 mstatus 栈不一致，Spike fixup_csr 处理对齐。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - interrupt cosim 与 PIC CSR 同步
     - :file:`docs/adr/0007-*`
   * - 代码路径 1
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/tests/asm/directed_irq_basic.S`
     - 当前仓库实际文件


签核与边界
----------

当前 IRQ agent 负责 timer/software/external/NMI stimulus，Spike DPI 负责 mip/mcause/mepc 与 custom PIC CSR 对齐。sign-off 的 formal stage 还以 PIC property 补充中断优先级与 claim/complete 不变量。

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
