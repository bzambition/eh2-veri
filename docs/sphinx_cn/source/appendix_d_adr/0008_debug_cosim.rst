.. _adr-0008:

ADR-0008: Debug Cosim Closure
================================

:status: Accepted
:source: docs/adr/0008-debug-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：EH2 有 10 多个 debug 相关的 riscv-dv 测试均 ``cosim: disabled`` ，
整个调试子系统（通过 ebreak、single_step、trigger、halt_run 的进入/退出）从未
对 Spike ISS 进行过验证。Ibex 有 13 多个 debug 测试全部通过 cosim，EH2 在安全
关键子系统上存在显著的验证差距。

**决策** ：利用 Spike 已有的 debug 支持——Spike 原生支持通过 ebreak / haltreq 进入
debug mode、dret（debug return）指令、dcsr.step 单步模式以及 debug CSR 读写
（dcsr, dpc, dscratch0/1）。cosim scoreboard 已有 ``pc_is_debug_ebreak()``、
``check_debug_ebreak()`` 和 ``set_debug_req()`` ，这些从 Ibex 移植而来。在
``fixup_csr()`` 中增加 dcsr/dpc/dscratch0/1 的 WARL fixup：dcsr 的 WARL mask 允许
写入 step、ebreakm、ebreaku、nmip、mprven，ebreaks 硬连线为 0（EH2 没有 S-mode），
cause 和 prv 为只读；dpc 完全可写，低 2 位硬连线 0（4 字节对齐）；dscratch0/1 完全
32 位可写。

**Debug 进入/退出流程** ：ebreak 进入通过 ``pc_is_debug_ebreak()`` 检测后调用
``check_debug_ebreak()`` ，Spike 进入 debug mode。halt_req（JTAG）通过
``set_debug_req(true)`` 让 Spike 进入 debug mode。single_step 通过 dcsr.step=1
让 Spike 每条指令后重新进入 debug。退出方式包括 dret（Spike 原生执行 dret，退出
debug mode 并在 dpc 处恢复执行）和 resume_req（JTAG）通过
``set_debug_req(false)`` 恢复。所有 10 多个 debug 测试已经移除
``cosim: disabled`` 和 ``skip_in_signoff`` 。

**已知限制** ：Trigger module（mcontrol/etrigger 同步到 Spike）尚未完成，可能导致
breakpoint_test 因 trigger match divergence 失败。JTAG halt_run_agent 驱动的时序
差异可能导致 divergence。debug_in_irq / irq_in_debug 等嵌套组合需要 interrupt 和
debug 两条路径同时就绪。

**后果** ：10 多个 debug 测试现在尝试 cosim lockstep。dcsr/dpc/dscratch WARL fixup
将 Spike 与 EH2 对齐。ebreak-to-debug 进入路径已从 Ibex 移植就绪。Trigger module
同步推迟到后续工作。任何失败测试将生成子 issue 而非重新禁用。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - debug cosim 与 JTAG/HaltRun 边界
     - :file:`docs/adr/0008-*`
   * - 代码路径 1
     - :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/cosim/spike_cosim.cc`
     - 当前仓库实际文件


签核与边界
----------

当前 debug stimulus 由 JTAG agent、Halt/Run agent 与手写 directed 程序共同覆盖；Spike 负责 debug CSR、dret、ebreak 和 halt request 的架构状态对齐。trigger 细节仍按已知限制跟踪。

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

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：确认本页 ADR 编号、标题和 Sphinx 页面都能在索引中找到。

.. code-block:: bash

   sed -n "1,160p" docs/adr/INDEX.md
   ls docs/sphinx_cn/source/appendix_d_adr

**进阶题**：检查 ADR 是否说明状态、决策后果，以及后续修订时应新增 superseding ADR。

.. code-block:: bash

   rg -n "Status:|Date:|Decision|Consequences|supersed" docs/adr docs/sphinx_cn/source/appendix_d_adr | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 这条 ADR 的状态、日期和决策边界是什么？
2. 它解决的是 cosim、coverage、formal、synthesis、LEC、RVFI 还是 waiver 问题？
3. 该 ADR 对应的实现文件或 sign-off gate 是哪一个？
4. 当前 VCS/URG 默认 release 参考与 NC/Incisive 备选路径是否被正确区分？
5. 若该 ADR 需要修订，是否应新增 superseding ADR 而不是静默改写历史？
