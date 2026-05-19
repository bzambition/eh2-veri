.. _adr-0015:

ADR-0015: RVFI 适配层（不改 design RTL）
===========================================

:status: Accepted
:source: docs/adr/0015-rvfi-adapter-layer.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 design 没有标准 RVFI 接口，当前 cosim 走 trace_pkt 路径。
工业级对比：Ibex 走 RVFI → riscv-formal + sail-riscv 等价证明，
而 EH2 当前只有 trace_pkt → spike_cosim。

§2  决策
---------

在 :file:`rtl/eh2_veer_wrapper_rvfi.sv` 中增加 trace-to-RVFI 适配层，
RVFI 信号从现有 trace_pkt + probe_if 信号推导，不改 design RTL。
双 channel（i0/i1）对应 EH2 双发射架构。

§3  RVFI 字段对齐
-------------------

.. list-table::
   :header-rows: 1
   :widths: 25 40 35

   * - RVFI 字段
     - 来源
     - 说明
   * - ``rvfi_valid``
     - trace_i0_valid / trace_i1_valid
     - 指令退休有效
   * - ``rvfi_order``
     - wb_seq counter（probe_monitor）
     - 全局指令序号
   * - ``rvfi_insn[31:0]``
     - trace_i0_insn / trace_i1_insn
     - 指令编码
   * - ``rvfi_pc_rdata[31:0]``
     - trace_i0_pc / trace_i1_pc
     - 指令 PC
   * - ``rvfi_pc_wdata[31:0]``
     - 计算 next-PC（pc + 2/4）
     - 下一条 PC（用于自洽性检查）
   * - ``rvfi_rd_addr[4:0]``
     - trace.rd_addr
     - 目标寄存器地址
   * - ``rvfi_rd_wdata[31:0]``
     - trace.rd_wdata（来自 probe wb result）
     - 写回数据
   * - ``rvfi_mem_addr/wdata/wmask``
     - LSU AXI4 monitor
     - 内存访问信息
   * - ``rvfi_trap``
     - trace.exception
     - 异常标志
   * - ``rvfi_intr``
     - trace.interrupt
     - 中断标志
   * - ``rvfi_mode[1:0]``
     - 固定为 M-mode (2'b11)
     - 特权模式

§4  后果
---------

- 不破坏现有 trace 路径（向后兼容）
- 为后续接入 riscv-formal / sail-riscv 等价证明铺标准接口
- 双 channel 时序对齐（i0/i1 retire 顺序）需额外验证

§5  参考资料
-------------

* :ref:`adr-0004` — RTL RVFI Equivalent Trace
* :file:`rtl/eh2_veer_wrapper_rvfi.sv`

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - 不改 design RTL 的 RVFI adapter
     - :file:`docs/adr/0015-*`
   * - 代码路径 1
     - :file:`rtl/eh2_veer_wrapper_rvfi.sv`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`rtl/lec_shim`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/env/eh2_rvfi_if.sv`
     - 当前仓库实际文件


签核与边界
----------

RVFI adapter 位于项目 rtl/ 目录，作为验证层和 LEC shim 的一部分维护；该决策降低上游 RTL merge 风险，同时保留 RVFI smoke 与 future riscv-formal 对接空间。

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
