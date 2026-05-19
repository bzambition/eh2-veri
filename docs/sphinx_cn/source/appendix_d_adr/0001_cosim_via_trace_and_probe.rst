.. _adr-0001:

ADR-0001: Cosim 数据通路 -- trace 包 + probe 接口
=====================================================

:status: Accepted（后续被 ADR-0004 取代）
:source: docs/adr/0001-cosim-via-trace-and-probe.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 RTL 没有 RVFI 接口。Ibex 的 cosim 闭环依赖 RVFI 为每条 retired
指令提供完整快照（rd_addr、rd_wdata、mem_*、csr_* 共 27 个信号），scoreboard
直接拿 RVFI item 喂 Spike 一比一对照。EH2 RTL 只有 trace 包（PC + insn +
exception + interrupt + tval），没有 rd_addr/rd_wdata，因此必须从其他地方拿到
寄存器写回数据。

§2  决策
---------

通过两条独立通道在 UVM monitor 层重建 RVFI 等价信息：

**通道 1 — Trace 通道（``eh2_trace_monitor`` ）：**
监视 RTL trace 包，给出 PC + insn + exception。
每周期采样 ``trace_rv_trace_pkt`` ，双槽位 i0/i1 同周期输出。

**通道 2 — Probe 通道（``eh2_dut_probe_monitor`` ）：**
通过 hierarchical reference 直接读取 DUT 内部写回信号：
- ``wbd.i0v/i1v`` ：i0/i1 写回有效
- ``i0_result_wb`` ：写回数据
- ``div_wren/div_cancel`` ：除法写回/取消
- ``nb_load_wen/nb_load_tag/nb_load_data`` ：非阻塞 load 数据

Scoreboard 在两条通道之间做 per-slot 队列匹配。

§3  后果
---------

**优点：**

- 不需要改 RTL，保持了与 chipsalliance 上游的兼容性
- 工作集中在 UVM 层，不影响综合/时序

**缺点：**

- 同周期同步依赖 ``#0`` 延迟硬撑，SystemVerilog scheduler 在某些 corner
  不保证两个 monitor 的严格顺序
- wb 与 trace 的对应关系靠启发式方法（rd 匹配 + wb_search_depth 窗口），
  是典型的 band-aid 方案
- scoreboard 膨胀到 1026 行，而 Ibex 等价实现仅 361 行
- NB-load / DIV cancel 等异步事件需要专门通道，导致多分支逻辑

**已尝试的修补：**

- 加 ``wb_seq_counter`` 全局序号（半成品状态）
- 加 ``wb_search_depth`` 限制搜索范围（仅缓解症状）
- 加 ``#0`` 延迟保证 probe 先入队（双发射 + NB-load 场景仍有 race）

§4  Spike CSR Model Extension Strategy
---------------------------------------

EH2 有 18+ 个自定义 CSR（PIC/DCCM/ICCM/时钟门控）。Spike 不原生支持。
策略分为三层：

**第 1 层：静态注册（set_csr）**
28 个 CSR 通过 ``riscv_cosim_set_csr()`` 在初始化时注册。
Spike 仅知道"该地址有一个 CSR"，不理解其硬件语义

**第 2 层：动态修正（fixup_csr）**
每步 step 后从 DUT probe 读取 CSR 值 → ``fixup_csr()`` → 写入 Spike。
WARL 相关的位反转逻辑在 Spike 中无法完全模拟

**第 3 层：语义豁免**
PIC 中断优先级逻辑（meicurpl/meihap 的动态更新）在 Spike 中无等价物。
Scoreboard 宽松比对或豁免这些 CSR

§5  DIV Cancel Fix（Phase 1）
------------------------------

**问题：** EH2 的除法器在 E1 级启动后独立迭代。如果后续指令写同一个
rd（Write-After-Write），在飞的除法被 cancel。原始 RTL 的 ``dec_div_cancel``
信号仅在推测层面上 cancel，可能与实际架构 cancel 不一致。

**修复：** Phase 1 在 RTL 中添加了 ``dec_div_cancel_overwrite`` 信号——
仅当 cancel 原因是更年轻的同 rd 写（而非除法异常）时置位。
Scoreboard 用此信号与 retired div trace 配对，正确作废 pending_wb_q
中对应的除法写回。

§6  后续演进
-------------

ADR-0004 提议在 RTL trace 包中增加 rd_addr/rd_wdata 字段（RVFI 等价信号），
让 trace 通道直接携带写回信息，废弃 probe 通道的写回主路径。
这将 scoreboard 简化到约 500 行，消除 #0 race condition 和 wb_search_depth band-aid。

Phase 1 实际实施了此方案：trace packet 的 ``trace_rv_i_rd_*_ip`` 字段
从 RTL 写回信号直接导出，供 UVM monitor 使用。

§7  参考资料
-------------

* :ref:`cosim_scoreboard` — Cosim Scoreboard 详解
* :ref:`adr-0004` — RTL RVFI Equivalent Trace
* :ref:`adr-0015` — RVFI Adapter Layer
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - trace/probe cosim 数据通路
     - :file:`docs/adr/0001-*`
   * - 代码路径 1
     - :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
     - 当前仓库实际文件


签核与边界
----------

当前主线仍保留 trace packet 与 DUT probe 两条 analysis 流。regular retire 由 trace monitor 进入 cosim scoreboard，DIV 与 NB-load 等异步写回由 DUT probe monitor 进入 async writeback 队列。

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
