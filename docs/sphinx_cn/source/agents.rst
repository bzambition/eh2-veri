:orphan:

Agent 参考
==========================================================================================

本章按目录说明 ``dv/uvm/core_eh2/common`` 下的 agent。平台遵循 Ibex
风格：每个 agent 封装一个协议或一种 DUT 侧控制面；env 只做创建与连接。

Agent 总览
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 16 18 46

   * - Agent
     - 模式
     - 主要文件
     - 职责
   * - ``axi4_agent``
     - passive
     - ``axi4_monitor.sv``
     - 监控 IFU / LSU / SB AXI4 事务，LSU 事务送 cosim。
   * - ``trace_agent``
     - passive
     - ``eh2_trace_monitor.sv``
     - 采样 retired instruction trace，生成 ``eh2_trace_seq_item`` 。
   * - ``cosim_agent``
     - scoreboard owner
     - ``eh2_cosim_scoreboard.sv``
     - 持有 Spike DPI handle，执行 lockstep 比对。
   * - ``irq_agent``
     - active
     - ``eh2_irq_driver.sv``
     - 驱动 timer、software、127 路 external interrupt。
   * - ``jtag_agent``
     - active
     - ``eh2_jtag_driver.sv``
     - 驱动 JTAG DTM / DMI 访问 debug module。
   * - ``halt_run_agent``
     - active
     - ``eh2_halt_run_driver.sv``
     - 驱动 MPC halt/run 控制面。

AXI4 Agent
------------------------------------------------------------------------------------------

``axi4_agent`` 是参数化 agent，ID 宽度由端口 tag 宏决定。核心对象：

* ``axi4_seq_item`` ：保存读 / 写事务、地址、burst、size、data、strb、
  resp 等字段。
* ``axi4_monitor`` ：关联 AW/W/B 或 AR/R channel，按事务发 analysis item。
* ``axi4_driver`` / ``axi4_sequencer`` ：当前保留，但 env 将 agent 配成
  ``UVM_PASSIVE`` ，不主动驱动。

LSU monitor 的 analysis port 连接到 ``cosim_agt.dmem_port`` 。scoreboard
收到 AXI4 事务后按 64-bit beat 拆成 32-bit Spike dside notification。

Trace Agent
------------------------------------------------------------------------------------------

``trace_agent`` 实际是一组 monitor / item，不含 driver：

* ``eh2_trace_intf`` ：由 TB top 接入 RTL trace 与 verification-only wb 字段。
* ``eh2_trace_monitor`` ：同周期按 program order 采样 i0 / i1 retire。
* ``eh2_trace_seq_item`` ：统一封装 PC、insn、slot、exception、interrupt、
  tval、mcycle、mip、debug/nmi、wb_valid、rd、rd_data 等字段。
* ``eh2_dut_probe_monitor`` ：从 ``eh2_dut_probe_if`` 采样 NB-load、DIV
  async hint，不再承担普通写回主路径。

ADR-0004 之后，普通 rd 写回已随 trace item 传输，probe monitor 只保留
异步补充职责。

Cosim Agent
------------------------------------------------------------------------------------------

``eh2_cosim_agent`` 自身很薄：build phase 创建 ``eh2_cosim_scoreboard`` ，
并导出三个 analysis export：

* ``trace_port`` / ``trace_fifo`` ：retired instruction。
* ``dut_probe_port`` / ``dut_probe_fifo`` ：async writeback hint。
* ``dmem_port`` / ``lsu_axi_fifo`` ：LSU AXI4 memory access。

测试或 TB top 可以通过 ``write_mem_byte`` 给 scoreboard 的 Spike handle
做 backdoor binary load。实际比对策略见 :doc:`cosim_scoreboard` 。

IRQ Agent
------------------------------------------------------------------------------------------

``eh2_irq_agent`` 是 active agent。``eh2_irq_intf`` 参数包括：

* ``NUM_THREADS`` ：timer / software interrupt 宽度。
* ``PIC_TOTAL_INT`` ：外部中断源数量，默认 127。

``eh2_irq_seq_item`` 描述一次中断事务，字段包括中断类型、IRQ id、值、
持续时间、是否 pulse。driver 根据类型驱动 ``timer_int``、``soft_int``
或 ``extintsrc_req[irq_id]`` 。

JTAG Agent
------------------------------------------------------------------------------------------

``eh2_jtag_agent`` 通过 ``eh2_jtag_intf`` 驱动 TCK/TMS/TDI/TDO 等信号。
driver 内部实现 TAP state machine、DMI read/write、busy retry 与 response
采集。sequence 层提供 ``eh2_jtag_seq::send_write`` 等静态 helper，供
debug sequence 或 directed test 快速写 debug module 寄存器。

由于 debug 路径会改变 core 的控制流，相关 riscv-dv 测试大多标记
``cosim: disabled`` ，直到 scoreboard 对 debug/trap frame 有完整建模。

Halt/Run Agent
------------------------------------------------------------------------------------------

``eh2_halt_run_agent`` 驱动 MPC halt/run 请求，用于覆盖 core 暂停、恢复、
fetch enable 等控制面。它与 JTAG debug 不同：JTAG 走调试模块和 DMI；
halt/run agent 面向 SoC 控制端口。

命名约定与遗留例外
------------------------------------------------------------------------------------------

Phase 2 已将大多数类名前缀统一为 ``eh2_*`` 或 ``core_eh2_*`` 。当前仍有
两个历史例外：

* 目录名 ``common/cosim_agent`` 未改成 ``eh2_cosim_agent`` ，因为 filelist
  与 include path 已稳定。
* ``axi4_agent`` 保持通用命名，便于后续复用到其它 core 或 bus wrapper。

新增 agent 时，应优先采用 ``eh2_<domain>_agent`` 目录与类名前缀。

