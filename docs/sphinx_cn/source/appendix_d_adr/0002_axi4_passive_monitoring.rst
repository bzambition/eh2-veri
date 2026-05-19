.. _adr-0002:

ADR-0002: AXI4 总线 passive monitoring + slave behavioral mem
==============================================================

:status: Accepted
:source: docs/adr/0002-axi4-passive-monitoring.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 有 4 个 AXI4 端口（IFU 取指、LSU 读写、SB 调试系统总线、DMA），
数据宽度 64-bit。Ibex 使用的是简单的 req/gnt/rvalid 接口，其
mem_intf_response_agent 会主动驱动响应。EH2 需要一套完整的 AXI4 验证方案。

§2  决策
---------

将 AXI4 agent 设为 passive 模式，仅作监视器，不驱动总线。在 TB top
实例化 4 个 ``axi4_slave_mem`` 行为级模型，各自拥有独立内存区且地址空间预映射。
monitor 将 AW/AR 与 W/R/B 通道按事务关联，发出 ``axi4_seq_item`` ，包含 burst
的全部 beats。LSU 通道挂接到 cosim agent 的 ``dmem_port`` ，用于给 Spike 通知
内存访问。

§3  后果
---------

**优点：**
- 行为级 mem 简化了 testbench，不需要建模 cache 一致性
- passive agent 与真实 SoC 完全解耦，AXI 主控由 DUT 完全决定
- 64-bit beat 数据完整保留，cosim 通知时 split 为两个 32-bit 调用

**局限：**
- 不能注入 AXI 错误响应和退避
- 没有 AXI 协议合规检查 assertion
- 不支持 AXI lock / exclusive access 验证

§4  Monitor 双线程架构细节
----------------------------

``axi4_monitor`` 使用 ``fork...join`` 双线程并行监视读写通道：

**写监视器（``monitor_writes()`` ）：**
1. ``@(posedge clk iff awvalid && awready)`` — AW 握手
2. 分配 data/strb 数组（beat_count = awlen + 1）
3. For 循环收集 W beats — 不等 B 响应即发送事务（EH2 在 B 可见前 retire store）
4. ``ap.write(txn)`` — 立即发送到 cosim scoreboard
5. 延迟 drain B 响应 — 仅更新 resp，不阻塞

**读监视器（``monitor_reads()`` ）：**
1. ``@(posedge clk iff arvalid && arready)`` — AR 握手
2. For 循环收集 R beats — 每 beat 捕获 rdata/rresp
3. 所有 beat 完成后 ``ap.write(txn)``

§5  4 个 slave mem 的地址映射
-------------------------------

- ``lsu_axi_slave_mem`` ：外部数据存储（含 mailbox 地址 0xD058_0000）
- ``ifu_axi_slave_mem`` ：外部指令存储（测试程序加载目标）
- ``sb_axi_slave_mem`` ：调试系统总线存储
- ``dma_axi_slave_mem`` ：DMA 访问目标（可选）

§6  参考资料
-------------

* :ref:`agent_axi4` — AXI4 Agent 详解
* :file:`dv/uvm/core_eh2/common/axi4_agent/`
* :file:`shared/rtl/axi4_slave_mem.sv`

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - AXI4 passive monitor 与行为内存
     - :file:`docs/adr/0002-*`
   * - 代码路径 1
     - :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
     - 当前仓库实际文件


签核与边界
----------

当前 env 创建 LSU、IFU、SB 三个 AXI4 agent，LSU analysis port 接入 cosim dmem_port；TB 顶层用 axi4_slave_mem 建模总线响应，DMA AXI4 在顶层保持空闲。

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
