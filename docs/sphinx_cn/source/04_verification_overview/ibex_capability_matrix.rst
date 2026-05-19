.. _ibex_capability_matrix:
.. _04_verification_overview/ibex_capability_matrix:

与 Ibex 验证平台的能力对比
===========================

:status: draft
:source: README.md; CONTEXT.md; docs/PROJECT_STATUS.md; docs/release-notes-v1.1.md; docs/adr/INDEX.md; dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; dv/uvm/core_eh2/env/core_eh2_env.sv; dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv; dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv; dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh; dv/cosim/spike_cosim.cc; dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv; dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv; dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv; dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv; dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml; dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: bddb61be0a5bc43140245c8f5617c25925eacf3d

§1  本章边界
-------------

本章只比较当前 EH2-Veri v1.1 仓库与本机 Ibex 参考验证平台在验证能力上的可回溯差异。
比较依据分为三类：

* EH2 当前 release/status 文档，用于固定 v1.1 sign-off 数字。
* EH2 UVM、cosim、riscv-dv、coverage 源码，用于说明能力来自哪些实现。
* `/home/host/ibex/dv/uvm/core_ibex/` 下的 Ibex 参考文件，用于说明本章中提到的
  Ibex 侧接口形态。

本章不从历史审计结论推导当前状态；如果旧审计和 v1.1 status 冲突，以
`docs/PROJECT_STATUS.md`、`docs/release-notes-v1.1.md` 和当前源码为准。

关键代码（`README.md:L1-L18`）：

.. code-block:: bash

   # EH2 Verification Platform
   
   EH2 Verification Platform is a UVM, cosim, coverage, formal, and sign-off
   environment for the VeeR EH2 RISC-V core.
   
   This repository is not a marketing wrapper around a few smoke tests. It is a
   release-oriented verification workspace that collects RTL simulation,
   Spike-based instruction lockstep, directed assembly, riscv-dv stimulus,
   coverage, CSR unit checks, RISC-V compliance, lint, formal proof, and
   block-level LEC into one sign-off record.
   
   Current release: **v1.1**.
   
   Current sign-off result: **PASS**.
   
   Current formal result: **46/46 PASS**.
   
   Current LEC result: **31635/31635 PASS**.

逐段解释：

* 第 L1-L4 行：README 把平台范围限定为 VeeR EH2 的 UVM、cosim、coverage、
  formal 和 sign-off 环境。
* 第 L6-L10 行：当前仓库的 sign-off 不是单个 smoke 流程，而是把 RTL 仿真、
  Spike lockstep、directed assembly、riscv-dv、coverage、CSR、compliance、
  lint、formal 和 block-level LEC 收敛到同一份 sign-off record。
* 第 L12-L18 行：本章保留 v1.1、46/46 和 31635/31635 三个 release-facing 数字，
  不使用旧审计中已经被 v1.1 状态更新取代的数值。

接口关系：

* 被调用：本章被验证概览、架构评审和迁移评估使用。
* 调用：:ref:`goals_scope`、:ref:`quickstart`、
  :ref:`cosim_scoreboard`、:ref:`functional_coverage`。
* 共享状态：release status、ADR 索引、EH2 UVM 源码、本机 Ibex 参考源码。

§2  DUT 与验证对象差异
-----------------------

EH2 与 Ibex 的验证平台目录形态相近，但验证对象不同。EH2 的 README 明确列出
自定义 CSR、DCCM/ICCM、PIC、debug、AXI/AHB 集成点和双线程能力；Ibex
参考 testbench 则实例化 `ibex_top_tracing`，并通过参数打开或关闭 PMP、RV32M、
RV32B、ICache 等配置。

关键代码（`README.md:L20-L41`）：

.. code-block:: bash

   ## Project Scope
   
   VeeR EH2 is a 32-bit RISC-V processor core with RV32IMAC support, EH2-specific
   custom CSRs, tightly coupled memories, programmable interrupt control, debug
   logic, AXI/AHB-facing integration points, and a dual-thread-capable
   microarchitecture.
   
   This platform verifies the EH2 core through:
   
   - UVM testbench infrastructure under `dv/uvm/core_eh2`;
   - Spike DPI cosim under `dv/cosim`;
   - directed assembly tests under `dv/uvm/core_eh2/tests/asm`;
   - riscv-dv integration under `dv/uvm/core_eh2/riscv_dv_extension`;
   - functional coverage under `dv/uvm/core_eh2/fcov`;
   - formal properties and IFV scripts under `dv/formal`;
   - synthesis and LEC summaries under `syn`;
   - sign-off reporting under `build/<release>/`.

逐段解释：

* 第 L20-L25 行：EH2 的验证对象包含 RV32IMAC、EH2 自定义 CSR、DCCM/ICCM、
  PIC、debug、AXI/AHB-facing 集成点和 dual-thread-capable microarchitecture。
* 第 L27-L36 行：README 将平台能力分散到 `dv/uvm/core_eh2`、`dv/cosim`、
  `dv/formal`、`syn` 和 `build/<release>/`。因此本章比较不能只看 UVM 目录，
  还必须覆盖 cosim、formal、LEC 和 sign-off collector。
* 第 L38-L41 行：README 明确说明 EH2 平台 modeled after lowRISC Ibex flow，
  但不是 line-for-line port；差异来自 bus topology、trace behavior、CSR surface、
  debug topology、memory error paths 和 multi-thread support。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/tb/core_ibex_tb_top.sv:L55-L80`）：

.. code-block:: systemverilog

     // Ibex Parameters
     parameter bit          PMPEnable        = 1'b0;
     parameter int unsigned PMPGranularity   = 0;
     parameter int unsigned PMPNumRegions    = 4;
     parameter int unsigned MHPMCounterNum   = 0;
     parameter int unsigned MHPMCounterWidth = 40;
     parameter bit RV32E                     = 1'b0;
     parameter ibex_pkg::rv32m_e RV32M       = `IBEX_CFG_RV32M;
     parameter ibex_pkg::rv32b_e RV32B       = `IBEX_CFG_RV32B;
     parameter ibex_pkg::regfile_e RegFile   = `IBEX_CFG_RegFile;
     parameter bit BranchTargetALU           = 1'b0;
     parameter bit WritebackStage            = 1'b0;
     parameter bit ICache                    = 1'b0;
     parameter bit ICacheECC                 = 1'b0;
     parameter bit ICacheTweakInfection      = 1'b0;
     parameter bit BranchPredictor           = 1'b0;
     parameter bit SecureIbex                = 1'b0;
     parameter int unsigned LockstepOffset   = 1;
     parameter bit ICacheScramble            = 1'b0;
     parameter bit DbgTriggerEn              = 1'b0;
     parameter int unsigned DmBaseAddr       = 32'h`DM_ADDR;
     parameter int unsigned DmAddrMask       = 32'h`DM_ADDR_MASK;
     parameter int unsigned DmHaltAddr       = 32'h`DEBUG_MODE_HALT_ADDR;
     parameter int unsigned DmExceptionAddr  = 32'h`DEBUG_MODE_EXCEPTION_ADDR;
     // Ibex Inputs
     parameter int unsigned BootAddr         = 32'h`BOOT_ADDR; // ResetVec = BootAddr/256b + 0x80

逐段解释：

* 第 L55-L64 行：Ibex testbench 以参数方式配置 PMP、RV32M、RV32B、RegFile 和
  WritebackStage；本章只据此说明 Ibex 参考 TB 的参数面，不推导 EH2 参数。
* 第 L65-L80 行：Ibex 还通过参数控制 ICache、branch predictor、secure Ibex、
  debug module base、halt/exception 地址和 boot 地址。
* 与 EH2 README 的差异是：EH2 侧当前文档把自定义 CSR、DCCM/ICCM、PIC、
  AXI/AHB-facing 集成点和 dual-thread-capable microarchitecture 作为平台范围；
  Ibex 侧从 `core_ibex_tb_top.sv` 中看到的是参数化的 `ibex_top_tracing` 环境。

接口关系：

* 被调用：能力矩阵的 DUT 行、riscv-dv 配置行、coverage 行。
* 调用：EH2 顶层 TB、Ibex 顶层 TB、EH2 riscv-dv setting。
* 共享状态：`RV32IMAC`、`RV32ZBA`/`RV32ZBB`/`RV32ZBC`/`RV32ZBS`、DCCM、
  ICCM、PIC、NUM_THREADS。

§3  顶层 TB 结构对比
---------------------

EH2 的 top testbench 直接实例化 `eh2_veer_wrapper`，同时连接 trace、LSU AXI4、
IFU AXI4、SB AXI4、DMA AXI4、JTAG 和 interrupt 信号。Ibex 参考 top testbench
实例化 `ibex_top_tracing`，并暴露 instruction/data memory interface、IRQ、
RVFI、CSR 和 ifetch monitor interface。

§3.1  EH2 `core_eh2_tb_top` 的 DUT 包装
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 TB 将 DUT、DCCM/ICCM/ICache、AXI4 slave memory、mailbox 和
trace commit 放在同一个顶层仿真外壳中。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L8-L20`）：

.. code-block:: systemverilog

   // Architecture:
   //   core_eh2_tb_top
   //     +-- eh2_veer_wrapper (DUT)
   //     |     +-- dmi_wrapper (JTAG-to-DMI bridge)
   //     |     +-- eh2_veer (core)
   //     |     +-- eh2_mem (internal memory: DCCM/ICCM/ICache)
   //     +-- axi4_slave_mem (LSU memory - data)
   //     +-- axi4_slave_mem (IFU memory - instruction)
   //     +-- axi4_slave_mem (SB memory - debug system bus)
   //
   // Mailbox convention (from VeeR testbench):
   //   Address 0xD0580000: write 0xFF = PASS, 0x01 = FAIL
   //   Other printable chars are console output

逐段解释：

* 第 L8-L13 行：EH2 TB 的 DUT 是 `eh2_veer_wrapper`，wrapper 内含 `dmi_wrapper`、
  `eh2_veer` 和 `eh2_mem`。注释直接把 `eh2_mem` 标成 internal memory，
  包括 DCCM、ICCM 和 ICache。
* 第 L14-L17 行：EH2 TB 为 LSU、IFU 和 debug system bus 分别放置
  `axi4_slave_mem`，说明 EH2 验证环境不是 Ibex 的单一 memory interface 拓扑。
* 第 L18-L20 行：mailbox 约定把 `0xD0580000` 上的 `0xFF` 和 `0x01`
  解释为 PASS/FAIL，后续 UVM 测试会以此作为自检出口之一。

接口关系：

* 被调用：`core_eh2_base_test`、directed assembly、riscv-dv 生成程序和 mailbox
  监听逻辑。
* 调用：`eh2_veer_wrapper`、`axi4_slave_mem`、UVM env 接口。
* 共享状态：`mailbox_write`、`mailbox_addr`、`trace_rv_i_valid_ip`、AXI4 bus 信号。

§3.2  EH2 trace 与 AXI4 端口连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 top TB 把 trace pkt 端口和多组 AXI4 端口全部连接到 DUT wrapper，
为后续 `trace_monitor`、AXI4 monitor 和 cosim scoreboard 提供输入。

关键代码（`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L172-L191`）：

.. code-block:: systemverilog

     eh2_veer_wrapper dut (
       .clk                    (core_clk),
       .rst_l                  (rst_l),
       .dbg_rst_l              (porst_l),
       .rst_vec                (reset_vector[31:1]),
       .nmi_int                (nmi_int),
       .nmi_vec                (nmi_vector[31:1]),
       .jtag_id                (jtag_id[31:1]),
   
       // Trace
       .trace_rv_i_insn_ip      (trace_rv_i_insn_ip),
       .trace_rv_i_address_ip   (trace_rv_i_address_ip),
       .trace_rv_i_valid_ip     (trace_rv_i_valid_ip),
       .trace_rv_i_exception_ip (trace_rv_i_exception_ip),
       .trace_rv_i_ecause_ip    (trace_rv_i_ecause_ip),
       .trace_rv_i_interrupt_ip (trace_rv_i_interrupt_ip),
       .trace_rv_i_tval_ip      (trace_rv_i_tval_ip),
       .trace_rv_i_rd_valid_ip  (trace_rv_i_rd_valid_ip),
       .trace_rv_i_rd_addr_ip   (trace_rv_i_rd_addr_ip),
       .trace_rv_i_rd_wdata_ip  (trace_rv_i_rd_wdata_ip),

逐段解释：

* 第 L172-L179 行：TB 用 `core_clk`、`rst_l`、`porst_l`、reset vector、NMI vector
  和 `jtag_id` 实例化 `eh2_veer_wrapper`。
* 第 L181-L191 行：trace 端口不仅包括 insn、address、valid、exception、ecause、
  interrupt 和 tval，还包括 `trace_rv_i_rd_valid_ip`、`trace_rv_i_rd_addr_ip`、
  `trace_rv_i_rd_wdata_ip`。这些写回字段是 EH2 cosim 与原始 trace-only 形态的关键差异。

接口关系：

* 被调用：`eh2_trace_intf` 绑定和 `eh2_trace_monitor` 采样。
* 调用：DUT wrapper trace 输出。
* 共享状态：trace pkt、wb、slot、exception/interrupt 状态。

§3.3  Ibex `core_ibex_tb_top` 的参考结构
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：给出 Ibex 参考平台的 top-level 接口集合，作为 EH2 多端口拓扑的对照。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/tb/core_ibex_tb_top.sv:L17-L37`）：

.. code-block:: systemverilog

     clk_rst_if     ibex_clk_if(.clk(clk), .rst_n(rst_n));
     irq_if         irq_vif(.clk(clk));
     ibex_mem_intf  data_mem_vif(.clk(clk));
     ibex_mem_intf  instr_mem_vif(.clk(clk));
   
   
     // DUT probe interface
     core_ibex_dut_probe_if dut_if(.clk(clk));
   
     // Instruction monitor interface
     core_ibex_instr_monitor_if instr_monitor_if(.clk(clk));
   
     // RVFI interface
     core_ibex_rvfi_if rvfi_if(.clk(clk));
   
     // CSR access interface
     core_ibex_csr_if csr_if(.clk(clk));
   
     core_ibex_ifetch_if ifetch_if(.clk(clk));
   
     core_ibex_ifetch_pmp_if ifetch_pmp_if(.clk(clk));

逐段解释：

* 第 L17-L20 行：Ibex 参考 TB 使用 `clk_rst_if`、`irq_if`、`ibex_mem_intf`
  data/instr 两个 memory interface。
* 第 L23-L37 行：Ibex 参考 TB 显式实例化 DUT probe、instruction monitor、
  RVFI、CSR、ifetch 和 ifetch PMP interface。这里的 `core_ibex_rvfi_if`
  是 Ibex cosim 的主输入之一。
* 与 EH2 §3.2 的区别是：EH2 当前主 cosim 输入来自 trace pkt 加写回字段与 probe hint；
  Ibex 参考平台则直接把 RVFI interface 作为 retired instruction 快照来源。

接口关系：

* 被调用：Ibex cosim agent、Ibex scoreboard、Ibex memory response agent。
* 调用：`ibex_top_tracing`、Ibex RVFI monitor。
* 共享状态：RVFI、dmem/imem transactions、IRQ、CSR。

§4  cosim 数据路对比
--------------------

Ibex 参考路径是 RVFI-centered：`ibex_rvfi_monitor` 从 `core_ibex_rvfi_if`
采样 `pc`、`rd_addr`、`rd_wdata`、`order`、interrupt/debug/NMI 状态，再送入
`ibex_cosim_scoreboard`。EH2 当前路径是 trace/probe-centered：trace pkt
携带 i0/i1 退休信息和 verification-only writeback view，probe 只保留 NB-load
和 DIV cancel 等异步 wb hint。

§4.1  EH2 trace interface：非标准 RVFI，但带写回视图
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 的 trace interface 本身不是标准 RVFI，但已经加入 verification-only
写回字段，供 `trace_monitor` 生成 `eh2_trace_seq_item`。

关键代码（`dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L4-L17`）：

.. code-block:: systemverilog

   // EH2 provides a simplified trace interface (NOT standard RVFI):
   //   - trace_rv_i_insn_ip:      [NUM_THREADS-1:0][63:0] - Instructions (2 per thread)
   //   - trace_rv_i_address_ip:   [NUM_THREADS-1:0][63:0] - PC addresses (2 per thread)
   //   - trace_rv_i_valid_ip:     [NUM_THREADS-1:0][1:0]  - Valid flags (2 per thread)
   //   - trace_rv_i_exception_ip: [NUM_THREADS-1:0][1:0]  - Exception flags
   //   - trace_rv_i_ecause_ip:    [NUM_THREADS-1:0][4:0]  - Exception cause
   //   - trace_rv_i_interrupt_ip: [NUM_THREADS-1:0][1:0]  - Interrupt flags
   //   - trace_rv_i_tval_ip:      [NUM_THREADS-1:0][31:0] - Trap value
   //
   // Limitations vs RVFI:
   //   - No rd_addr/rd_wdata (register writeback not directly visible)
   //   - No mem_addr/mem_wdata/mem_rdata (memory access not directly visible)
   //   - No CSR updates
   //   - Only 2 instructions per cycle per thread

逐段解释：

* 第 L4-L11 行：源码明确写出 EH2 trace interface 不是标准 RVFI；它的基础字段覆盖
  insn、address、valid、exception、ecause、interrupt 和 tval。
* 第 L13-L17 行：注释记录了与 RVFI 相比的限制，包括 memory access 和 CSR update
  不直接在 trace interface 上表达。这个限制解释了 EH2 为什么仍需要 AXI4 monitor、
  CSR fixup 和 DUT probe hint。
* 这段注释位于当前 `rd_valid` 字段声明之前；当前实现随后在 L34-L37 加入
  verification-only writeback view，因此文档应描述为“非标准 RVFI，带 RVFI-equivalent
  写回视图”，而不是“没有写回数据”。

关键代码（`dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L34-L37`）：

.. code-block:: systemverilog

     // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
     logic [NUM_THREADS-1:0][1:0]  rd_valid;
     logic [NUM_THREADS-1:0][9:0]  rd_addr;
     logic [NUM_THREADS-1:0][63:0] rd_wdata;

逐段解释：

* 第 L34 行：写回字段被标成 verification-only RVFI-equivalent writeback view。
* 第 L35-L37 行：`rd_valid` 每线程 2 bit，对应 i0/i1 两个 slot；`rd_addr`
  每线程 10 bit，包含两个 5-bit rd；`rd_wdata` 每线程 64 bit，包含两个 32-bit 数据。
* 这说明 EH2 的主退休数据仍不是完整 RVFI bus，但 cosim 比对所需的寄存器写回已通过
  trace pkt lane 表达。

接口关系：

* 被调用：`eh2_trace_monitor`。
* 调用：DUT trace 端口。
* 共享状态：NUM_THREADS、slot、trace pkt、wb。

§4.2  EH2 trace monitor：i0/i1 分槽生成 trace item
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 monitor 在同一周期分别处理 i0 和 i1 slot，并把写回字段填入
`eh2_trace_seq_item`。

关键代码（`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L82-L107`）：

.. code-block:: systemverilog

         // Monitor thread 0, instruction 0 (i0)
         if (vif.t0_i0_valid) begin
           txn = eh2_trace_seq_item::type_id::create("trace_txn");
           txn.thread_id   = 0;
           txn.slot        = 0;
           txn.pc          = vif.t0_i0_pc;
           txn.insn        = vif.t0_i0_insn;
           txn.exception   = vif.t0_i0_exception;
           txn.ecause      = vif.t0_i0_ecause;
           txn.interrupt   = vif.interrupt[0][0];
           txn.tval        = vif.tval[0];
           txn.commit_time = $time;
           txn.cycle_count = cycle_count;
   
           // RVFI-equivalent writeback view from RTL trace packet (lane 0).
           txn.wb_valid    = vif.t0_i0_wb_valid;
           txn.wb_dest     = vif.t0_i0_wb_addr;
           txn.wb_data     = vif.t0_i0_wb_data;
           txn.wb_suppress = 0;
           txn.wb_source   = EH2_WB_SRC_REGULAR;
   
           // Sample interrupt/debug/NMI/mcycle state for Spike notification
           populate_cosim_state(txn);
   
           // Capture current wb_seq for async-wb correlation (issue 66)
           if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;

逐段解释：

* 第 L82-L95 行：i0 有效时，monitor 创建 `trace_txn`，写入 `thread_id=0`、
  `slot=0`、PC、insn、exception、ecause、interrupt、tval、commit time 和 cycle count。
* 第 L96-L101 行：i0 的 `wb_valid`、`wb_dest` 和 `wb_data` 来自 trace pkt lane 0，
  并标记为 `EH2_WB_SRC_REGULAR`。
* 第 L103-L107 行：monitor 还采样 interrupt/debug/NMI/mcycle 状态，并在存在
  `probe_vif` 时记录 `wb_tag`，给异步写回匹配使用。

关键代码（`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L129-L154`）：

.. code-block:: systemverilog

         // Monitor thread 0, instruction 1 (i1)
         if (vif.t0_i1_valid) begin
           txn = eh2_trace_seq_item::type_id::create("trace_txn");
           txn.thread_id   = 0;
           txn.slot        = 1;
           txn.pc          = vif.t0_i1_pc;
           txn.insn        = vif.t0_i1_insn;
           txn.exception   = vif.t0_i1_exception;
           txn.ecause      = vif.t0_i1_ecause;
           txn.interrupt   = vif.interrupt[0][1];
           txn.tval        = vif.tval[0];
           txn.commit_time = $time;
           txn.cycle_count = cycle_count;
   
           // RVFI-equivalent writeback view from RTL trace packet (lane 1).
           txn.wb_valid    = vif.t0_i1_wb_valid;
           txn.wb_dest     = vif.t0_i1_wb_addr;
           txn.wb_data     = vif.t0_i1_wb_data;
           txn.wb_suppress = 0;
           txn.wb_source   = EH2_WB_SRC_REGULAR;
   
           // Sample interrupt/debug/NMI/mcycle state for Spike notification
           populate_cosim_state(txn);
   
           // Capture current wb_seq for async-wb correlation (issue 66)
           if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;

逐段解释：

* 第 L129-L141 行：i1 也生成独立 `trace_txn`，但 `slot=1`。这就是 EH2 双发射
  在 UVM 层展开成 per-slot trace item 的位置。
* 第 L143-L148 行：i1 写回视图来自 trace pkt lane 1。
* 第 L150-L154 行：i1 与 i0 使用相同的 Spike 通知状态和 `wb_tag` 采样规则。

接口关系：

* 被调用：`core_eh2_env.connect_phase()` 将 `trace_monitor.ap` 连接到 cosim scoreboard。
* 调用：`eh2_trace_intf`、`populate_cosim_state()`、DUT probe interface。
* 共享状态：trace FIFO、slot、wb_tag、interrupt/debug/NMI/mcycle。

§4.3  Ibex RVFI monitor：直接采样 RVFI item
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 Ibex 参考平台将 RVFI interface 直接转换成 `ibex_rvfi_seq_item`，
因此 scoreboard 不需要从 trace pkt 与 probe hint 拼装同样的退休信息。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_rvfi_monitor.sv:L29-L47`）：

.. code-block:: systemverilog

         // Wait for a retired instruction
         while(!(vif.monitor_cb.valid || vif.monitor_cb.ext_irq_valid)) vif.wait_clks(1);
   
         // Read instruction details from RVFI interface
         trans_collected                  = ibex_rvfi_seq_item::type_id::create("trans_collected");
         trans_collected.irq_only         = !vif.monitor_cb.valid && vif.monitor_cb.ext_irq_valid;
         trans_collected.trap             = vif.monitor_cb.trap;
         trans_collected.pc               = vif.monitor_cb.pc_rdata;
         trans_collected.rd_addr          = vif.monitor_cb.rd_addr;
         trans_collected.rd_wdata         = vif.monitor_cb.rd_wdata;
         trans_collected.order            = vif.monitor_cb.order;
         trans_collected.pre_mip          = vif.monitor_cb.ext_pre_mip;
         trans_collected.post_mip         = vif.monitor_cb.ext_post_mip;
         trans_collected.nmi              = vif.monitor_cb.ext_nmi;
         trans_collected.nmi_int          = vif.monitor_cb.ext_nmi_int;
         trans_collected.debug_req        = vif.monitor_cb.ext_debug_req;
         trans_collected.rf_wr_suppress   = vif.monitor_cb.ext_rf_wr_suppress;
         trans_collected.mcycle           = vif.monitor_cb.ext_mcycle;
         trans_collected.ic_scr_key_valid = vif.monitor_cb.ext_ic_scr_key_valid;

逐段解释：

* 第 L29-L30 行：Ibex RVFI monitor 等待 `valid` 或 `ext_irq_valid`，即以 RVFI
  retire/interrupt notification 为触发源。
* 第 L32-L39 行：monitor 直接读取 `pc_rdata`、`rd_addr`、`rd_wdata` 和 `order`，
  不需要额外 probe 匹配才能拿到寄存器写回。
* 第 L40-L47 行：pre/post MIP、NMI、debug request、RF write suppress、mcycle
  和 icache scramble key valid 都随 RVFI 扩展字段进入 seq item。

接口关系：

* 被调用：`ibex_cosim_scoreboard.run_cosim_rvfi()`。
* 调用：`core_ibex_rvfi_if`。
* 共享状态：RVFI order、rd、interrupt/debug 状态。

§4.4  EH2 scoreboard：Spike step 前的异步 wb 修正
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 scoreboard 在调用 `riscv_cosim_step` 前，先处理 interrupt-only、
regular wb、NB-load、DIV cancel 和 trap CSR 比对。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L573-L609`）：

.. code-block:: systemverilog

     // EH2: When interrupt=1 and exception=0, the trace item is only an
     // interrupt notification (no instruction executed at this PC).
     if (item.interrupt && !item.exception) begin
       riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req), tid);
       riscv_cosim_set_nmi(cosim_handle, int'(item.nmi), tid);
       riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int), tid);
       riscv_cosim_set_mip(cosim_handle, int'(prev_mip[tid]), int'(item.mip), tid);
       prev_mip[tid] = item.mip;
       riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle), tid);
       `uvm_info("cosim", $sformatf("T%0d IRQ-ONLY: PC=%08x", tid, item.pc), UVM_HIGH)
   
       // Compare trap CSRs on interrupt path — upgraded to mismatch (issue 51)
       begin
         int unsigned spike_mcause, spike_mepc;
         spike_mcause = riscv_cosim_get_mcause(cosim_handle, tid);
         spike_mepc   = riscv_cosim_get_mepc(cosim_handle, tid);
   
         if (spike_mcause != item.dut_mcause) begin
           mismatch_count[tid]++;
           `uvm_error("cosim", $sformatf(
             "T%0d IRQ mcause MISMATCH: DUT=%08x Spike=%08x PC=%08x",

逐段解释：

* 第 L573-L581 行：当 `interrupt=1 && exception=0` 时，EH2 scoreboard 把该 trace item
  视为 interrupt-only notification，不执行 Spike step，只同步 debug/NMI/MIP/mcycle。
* 第 L584-L589 行：scoreboard 读取 Spike 侧 `mcause` 和 `mepc`，准备与 DUT trap CSR
  快照比较。
* 第 L590-L609 行：`mcause` 或 `mepc` 不一致时递增 `mismatch_count[tid]`
  并发出 `uvm_error`。这说明 EH2 interrupt-only 路径仍是硬比对路径，不是简单忽略。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L612-L656`）：

.. code-block:: systemverilog

     // Pull writeback view directly from the trace packet (RVFI-equivalent).
     if (item.wb_valid && item.wb_dest != 0) begin
       write_reg          = item.wb_dest;
       write_reg_data     = item.wb_data;
       suppress_reg_write = 0;
     end else begin
       write_reg          = 0;
       write_reg_data     = 0;
       suppress_reg_write = 0;
     end
   
     // Async overrides
     if (try_consume_async_wb(tid, item, async_hint)) begin
       if (async_hint.suppress) begin
         suppress_reg_write = 1;
         write_reg          = 0;
         write_reg_data     = 0;
       end else begin
         write_reg          = async_hint.rd;
         write_reg_data     = async_hint.rd_data;
         suppress_reg_write = 0;
       end
     end else if (item.is_div()) begin
       suppress_reg_write = 1;
       write_reg          = 0;
       write_reg_data     = 0;

逐段解释：

* 第 L612-L621 行：普通写回优先从 trace pkt 的 RVFI-equivalent 字段进入
  `write_reg` 和 `write_reg_data`。
* 第 L623-L633 行：如果 `try_consume_async_wb()` 找到同一 `wb_tag` 的异步 hint，
  则用 hint 覆盖普通写回；当 hint 标记 `suppress` 时，scoreboard 抑制寄存器写回。
* 第 L634-L638 行：如果指令是 DIV 且没有可消费的异步写回，scoreboard 默认抑制该次
  reg write，避免把未到达的长延迟写回误送给 Spike。
* 第 L640-L656 行：随后才计算 `sync_trap`、同步 debug/NMI/MIP/mcycle/iside error，
  并调用 `riscv_cosim_step()`。

接口关系：

* 被调用：`run_cosim_trace()` 从 trace FIFO 取 item 后调用。
* 调用：`riscv_cosim_set_debug_req`、`riscv_cosim_set_mip`、
  `riscv_cosim_step`、`try_consume_async_wb()`。
* 共享状态：`prev_mip`、`mismatch_count`、`async_wb_q`、`cosim_handle`。

§4.5  严格 `wb_tag` 匹配
~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 当前异步 wb 不再用 `rd` 启发式回退，而是要求 `wb_tag`
严格对应。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L391-L447`）：

.. code-block:: systemverilog

     // Try to consume an async writeback hint that matches this instruction.
     // Strict wb_tag-only matching (issue 66). No rd-based fallback.
     function bit try_consume_async_wb(int tid, eh2_trace_seq_item item,
                                       output async_wb_hint_t hint);
       bit [4:0] expected_rd;
       bit       found_wrong_tag;
       int       wrong_tag_val;
       if (!item.writes_rd()) return 1'b0;
       expected_rd = item.get_write_rd();
   
       if (item.is_div()) begin
         found_wrong_tag = 0;
         foreach (async_wb_q[tid][i]) begin
           if (async_wb_q[tid][i].source != EH2_WB_SRC_DIV) continue;
           if (async_wb_q[tid][i].wb_tag == item.wb_tag) begin
             hint = async_wb_q[tid][i];
             async_wb_q[tid].delete(i);
             return 1'b1;
           end
           if (!found_wrong_tag) begin
             found_wrong_tag = 1;

逐段解释：

* 第 L391-L399 行：函数头注释直接声明 strict `wb_tag`-only matching，且无 `rd` fallback。
  `expected_rd` 只用于错误信息，不作为匹配条件。
* 第 L401-L408 行：DIV hint 必须满足 source 为 `EH2_WB_SRC_DIV` 且 `hint.wb_tag == item.wb_tag`
  才会被消费。
* 第 L415-L421 行：如果队列中有 DIV hint 但 `wb_tag` 错误，scoreboard 递增
  `mismatch_count[tid]` 并报 `uvm_error`。
* 第 L424-L443 行：NB-load 路径同样要求 `hint.wb_tag > 0` 且等于 `item.wb_tag`；
  错误 tag 会被报告为 mismatch。

接口关系：

* 被调用：`compare_instruction()`。
* 调用：`async_wb_q[tid]`。
* 共享状态：`wb_tag`、`mismatch_count`、NB-load、DIV cancel。

§4.6  DUT probe monitor：仅保留异步 wb 事件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明当前 probe monitor 已经不承担普通写回主路径，只发送 DIV 和 NB-load
异步 hint。

关键代码（`dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L1-L12`）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 DUT Probe Monitor — async writeback events only.
   //
   // Phase 1 (ADR-0004) note: regular pipeline writebacks now ride along the
   // trace channel inside eh2_trace_seq_item.wb_*. This monitor exists only to
   // surface async events that the trace packet cannot describe in time:
   //   - DIV writeback / DIV cancel (long latency, separate writeback port)
   //   - Non-blocking load completion (writeback arrives after retire)
   //
   // The cosim scoreboard treats these as overrides/suppressions for the
   // matching trace item.

逐段解释：

* 第 L2 行：文件注释把职责限定为 async writeback events only。
* 第 L4-L8 行：普通 pipeline writeback 已经在 trace channel 的
  `eh2_trace_seq_item.wb_*` 中传递；probe monitor 只补充 DIV writeback /
  DIV cancel 和 NB-load completion。
* 第 L10-L12 行：scoreboard 将这些事件作为对 matching trace item 的覆盖或抑制，
  这对应 §4.4 的 `try_consume_async_wb()`。

接口关系：

* 被调用：`core_eh2_env.connect_phase()` 连接到 `cosim_agt.scoreboard.dut_probe_fifo`。
* 调用：`eh2_dut_probe_if`、analysis port。
* 共享状态：`wb_seq_counter`、`wb_tag`、DIV、NB-load。

§5  env 与 agent 拓扑对比
--------------------------

EH2 env 的 agent 集合比 Ibex 参考 env 覆盖更多 EH2-specific 接口：LSU/IFU/SB AXI4、
IRQ、JTAG、halt/run、trace、DUT probe 和 cosim agent。Ibex 参考 env 则围绕
data/instr memory response agent、IRQ、cosim agent、scrambling key agent、
virtual sequencer 和 scoreboard 组织。

§5.1  EH2 env agent 清单
~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 `core_eh2_env` 中真实创建的 agent/monitor/scoreboard 成员。

关键代码（`dv/uvm/core_eh2/env/core_eh2_env.sv:L28-L52`）：

.. code-block:: systemverilog

     // AXI4 agents (passive - monitor only)
     axi4_agent#(`RV_LSU_BUS_TAG) lsu_agent;
     axi4_agent#(`RV_IFU_BUS_TAG) ifu_agent;
     axi4_agent#(`RV_SB_BUS_TAG) sb_agent;
   
     // Interrupt agent (active - drives interrupts)
     eh2_irq_agent irq_agent;
   
     // JTAG agent (active - drives debug)
     eh2_jtag_agent jtag_agent;
   
     // Halt/Run agent (active - drives halt/run)
     eh2_halt_run_agent halt_run_agt;
   
     // Trace monitor
     eh2_trace_monitor trace_monitor;
   
     // DUT probe monitor
     eh2_dut_probe_monitor dut_probe_monitor;
   
     // Co-simulation agent (owns scoreboard + backdoor loading)
     eh2_cosim_agent cosim_agt;
   
     // Double-fault detection scoreboard
     core_eh2_scoreboard dfd_scoreboard;

逐段解释：

* 第 L28-L31 行：EH2 env 有 LSU、IFU、SB 三个 AXI4 agent，对应 top TB 中三组
  AXI4 memory。
* 第 L33-L40 行：IRQ、JTAG、halt/run 都是 active agent，分别驱动 interrupt、
  debug 和 halt/run 控制。
* 第 L42-L49 行：trace monitor、DUT probe monitor 和 cosim agent 共同构成
  EH2 cosim 数据路。
* 第 L51-L52 行：`core_eh2_scoreboard` 用于 double-fault detection，与 cosim
  scoreboard 并列存在。

接口关系：

* 被调用：UVM build/connect phase。
* 调用：AXI4、IRQ、JTAG、halt/run、trace、probe、cosim 子组件。
* 共享状态：env cfg、virtual sequencer、analysis FIFO。

§5.2  EH2 env 连接关系
~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 env 如何把 trace、probe 和 LSU AXI4 monitor 连接到 cosim agent。

关键代码（`dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L172`）：

.. code-block:: systemverilog

     // Connect trace monitor to co-simulation agent's scoreboard
     if (cfg.enable_cosim && cosim_agt != null) begin
       trace_monitor.ap.connect(cosim_agt.scoreboard.trace_fifo.analysis_export);
     end
   
     // Connect DUT probe monitor to co-simulation agent's scoreboard
     if (cfg.enable_cosim && cosim_agt != null) begin
       dut_probe_monitor.ap.connect(cosim_agt.scoreboard.dut_probe_fifo.analysis_export);
     end
   
     // Connect LSU AXI4 monitor to co-simulation agent
     if (cfg.enable_cosim && cosim_agt != null) begin
       lsu_agent.ap.connect(cosim_agt.dmem_port);
     end
   
     // Connect trace monitor to double-fault detection scoreboard
     trace_monitor.ap.connect(dfd_scoreboard.trace_fifo.analysis_export);
   
     // Wire sub-sequencers to virtual sequencer
     vseqr.irq_seqr      = irq_agent.sequencer;
     vseqr.jtag_seqr     = jtag_agent.sequencer;
     vseqr.halt_run_seqr = halt_run_agt.sequencer;

逐段解释：

* 第 L151-L154 行：trace monitor 的 analysis port 连接到 cosim scoreboard 的
  `trace_fifo`。
* 第 L156-L159 行：DUT probe monitor 的 analysis port 连接到 `dut_probe_fifo`，
  只在 `enable_cosim` 时参与。
* 第 L161-L164 行：LSU AXI4 monitor 连接到 cosim agent 的 `dmem_port`，用于 D-side
  memory access 通知。
* 第 L166-L172 行：trace monitor 同时接入 double-fault detection scoreboard；
  IRQ、JTAG、halt/run sequencer 接入 virtual sequencer。

接口关系：

* 被调用：UVM connect phase。
* 调用：analysis port connect、virtual sequencer wiring。
* 共享状态：`cfg.enable_cosim`、trace FIFO、DUT probe FIFO、dmem port。

§5.3  Ibex env 参考结构
~~~~~~~~~~~~~~~~~~~~~~~

职责：给出 Ibex 参考 env 的组件清单和与 cosim agent 的连接方式。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_env.sv:L10-L18`）：

.. code-block:: systemverilog

     ibex_mem_intf_response_agent   data_if_response_agent;
     ibex_mem_intf_response_agent   instr_if_response_agent;
     irq_request_agent              irq_agent;
     ibex_cosim_agent               cosim_agent;
     core_ibex_vseqr                vseqr;
     core_ibex_env_cfg              cfg;
     scrambling_key_agent           scrambling_key_agent_h;
     core_ibex_scoreboard           scoreboard;

逐段解释：

* 第 L10-L13 行：Ibex env 有 data/instr memory response agent、IRQ agent 和
  `ibex_cosim_agent`。
* 第 L14-L18 行：Ibex env 同样有 virtual sequencer、cfg、scrambling key agent
  和 scoreboard。
* 对比 EH2 §5.1，Ibex 参考 env 没有 EH2 的三组 AXI4 agent、JTAG agent、
  halt/run agent、trace monitor 和 DUT probe monitor 成员。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_env.sv:L55-L65`）：

.. code-block:: systemverilog

     vseqr.data_if_seqr = data_if_response_agent.sequencer;
     vseqr.instr_if_seqr = instr_if_response_agent.sequencer;
     vseqr.irq_seqr = irq_agent.sequencer;
     data_if_response_agent.monitor.item_collected_port.connect(
       cosim_agent.dmem_port);
     instr_if_response_agent.monitor.item_collected_port.connect(
       cosim_agent.imem_port);
     if (cfg.enable_double_fault_detector) begin
       cosim_agent.rvfi_monitor.item_collected_port.connect(
         scoreboard.rvfi_port.analysis_export);
     end

逐段解释：

* 第 L55-L57 行：Ibex virtual sequencer 连接 data/instr memory response sequencer
  和 IRQ sequencer。
* 第 L58-L61 行：data/instr memory monitors 分别进入 cosim agent 的 dmem/imem port。
* 第 L62-L65 行：当 double-fault detector 开启时，RVFI monitor 的 item port
  接入 scoreboard 的 RVFI analysis export。

接口关系：

* 被调用：Ibex UVM connect phase。
* 调用：Ibex memory response agents、cosim agent、scoreboard。
* 共享状态：RVFI port、dmem/imem port、IRQ sequencer。

§6  EH2-specific agent 能力
---------------------------

EH2 的能力差异不只是 agent 数量更多，而是这些 agent 对应真实 EH2 接口：AXI4
error injection、PIC interrupt source、JTAG TAP/DMI、halt/run 控制和 trace/probe
cosim 数据路。

§6.1  AXI4 agent：默认 passive，错误注入时 active
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 AXI4 driver 并不替代 `axi4_slave_mem`，只在需要时通过 sideband
覆盖 response。

关键代码（`dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L4-L21`）：

.. code-block:: systemverilog

   // Acts as an AXI4 slave error injector, controlling the axi4_slave_mem's
   // response via the error_inject_mode / force_bresp / force_rresp sideband
   // signals on the axi4_intf.
   //
   // The driver does NOT replace the RTL slave_mem for address/data handling.
   // Instead, it piggybacks on slave_mem's existing state machine, only
   // overriding the resp field when an error should be injected.
   //
   //   - Passive mode (default, enable_error_inject=0):
   //       error_inject_mode stays 0; slave_mem drives OKAY on its own.
   //   - Active mode (enable_error_inject=1):
   //       The driver watches AR/AW handshakes and randomly sets
   //       error_inject_mode + force_bresp/force_rresp to SLVERR/DECERR
   //       with configurable probability (error_pct, default 5%).
   //       After the response handshake completes, error_inject_mode is
   //       cleared so the next transaction defaults to OKAY.
   //
   // Based on Ibex's ibex_mem_intf_response_driver pattern.

逐段解释：

* 第 L4-L10 行：AXI4 driver 控制 `axi4_slave_mem` 的 response sideband，
  不负责 address/data 存储语义。
* 第 L12-L19 行：默认 passive；active 时监视 AR/AW handshake，并按 `error_pct`
  随机把 response 设成 SLVERR/DECERR，response handshake 结束后清除 sideband。
* 第 L21 行：实现模式来源于 Ibex memory response driver pattern，但 bus protocol
  是 EH2 的 AXI4-facing 接口。

接口关系：

* 被调用：`core_eh2_env` 在 `enable_axi4_error_inject` 时把 LSU agent 设为 active。
* 调用：`axi4_intf` sideband。
* 共享状态：`error_inject_mode`、`force_bresp`、`force_rresp`、`error_pct`。

§6.2  IRQ agent：PIC source 宽度
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 IRQ interface 建模 timer、software、external PIC source 和 NMI。

关键代码（`dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv:L7-L19`）：

.. code-block:: systemverilog

   interface eh2_irq_intf #(
     parameter NUM_THREADS = 1,
     parameter PIC_TOTAL_INT = 127
   )(
     input logic clk,
     input logic rst_n
   );
   
     // Interrupt signals
     logic [NUM_THREADS-1:0]   timer_int;
     logic [NUM_THREADS-1:0]   soft_int;
     logic [PIC_TOTAL_INT:1]   extintsrc_req;
     logic                     nmi_int;

逐段解释：

* 第 L7-L10 行：IRQ interface 参数包含 `NUM_THREADS` 和 `PIC_TOTAL_INT=127`。
* 第 L15-L19 行：timer/software interrupt 按 thread 编址，external interrupt 使用
  `[PIC_TOTAL_INT:1]`，NMI 以单独 `nmi_int` 表示。
* 该接口解释了 EH2 与 Ibex 外部 interrupt 形态的差异：EH2 验证平台必须覆盖 PIC
  source vector，而不是只处理少量通用 IRQ 线。

接口关系：

* 被调用：`eh2_irq_agent` driver/sequence。
* 调用：DUT `timer_int`、`soft_int`、`extintsrc_req`、`nmi_int`。
* 共享状态：NUM_THREADS、PIC、interrupt。

§6.3  JTAG agent：TAP FSM 与 DMI scan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 JTAG driver 中实际实现了 TAP state machine，并非只提供空 agent。

关键代码（`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L265-L284`）：

.. code-block:: systemverilog

     // Update TAP state based on TMS value (mirrors hardware TAP FSM)
     task update_tap_state(bit tms);
       case (tap_state)
         TEST_LOGIC_RESET: tap_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
         RUN_TEST_IDLE:    tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
         SELECT_DR_SCAN:   tap_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
         CAPTURE_DR:       tap_state = tms ? EXIT1_DR         : SHIFT_DR;
         SHIFT_DR:         tap_state = tms ? EXIT1_DR         : SHIFT_DR;
         EXIT1_DR:         tap_state = tms ? UPDATE_DR        : PAUSE_DR;
         PAUSE_DR:         tap_state = tms ? EXIT2_DR         : PAUSE_DR;
         EXIT2_DR:         tap_state = tms ? UPDATE_DR        : SHIFT_DR;
         UPDATE_DR:        tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
         SELECT_IR_SCAN:   tap_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
         CAPTURE_IR:       tap_state = tms ? EXIT1_IR         : SHIFT_IR;
         SHIFT_IR:         tap_state = tms ? EXIT1_IR         : SHIFT_IR;
         EXIT1_IR:         tap_state = tms ? UPDATE_IR        : PAUSE_IR;
         PAUSE_IR:         tap_state = tms ? EXIT2_IR         : PAUSE_IR;
         EXIT2_IR:         tap_state = tms ? UPDATE_IR        : SHIFT_IR;
         UPDATE_IR:        tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

逐段解释：

* 第 L265-L267 行：`update_tap_state()` 以 TMS 值更新 TAP 状态。
* 第 L268-L284 行：case 覆盖 TEST_LOGIC_RESET、RUN_TEST_IDLE、SELECT_DR_SCAN、
  CAPTURE/SHIFT/EXIT/PAUSE/UPDATE DR、SELECT_IR_SCAN、CAPTURE/SHIFT/EXIT/PAUSE/UPDATE IR。
* 该实现支撑 EH2 debug agent 的 DMI 路径；本章不声称 Ibex 没有 debug 功能，只说明
  本地 Ibex `core_ibex_env.sv` 中没有与 EH2 `eh2_jtag_agent` 同名的 active JTAG agent。

接口关系：

* 被调用：`write_ir()`、DR scan task 和 JTAG sequences。
* 调用：`tck_nav()`、`tck_cycle()`、JTAG virtual interface。
* 共享状态：`tap_state`、TMS、TDI、TDO、DMI scan width。

§7  riscv-dv 配置对比
----------------------

EH2 与 Ibex 都使用 riscv-dv，但 EH2 的 setting 文件固定为 machine-only、
RV32IMAC 加 bitmanip groups，并声明 EH2 custom CSR 数值列表。Ibex 的模板则保留
USER_MODE、RV32B 模板分支、PMPEnable 模板分支等 Ibex 配置项。

§7.1  EH2 ISA 与 privilege 配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 riscv-dv setting 中的 hart 数、privilege mode、ISA group 和 debug/PMP
开关。

关键代码（`dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L20-L48`）：

.. code-block:: systemverilog

   parameter int NUM_HARTS = 1;
   parameter satp_mode_t SATP_MODE = BARE;
   
   privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE};
   
   riscv_instr_name_t unsupported_instr[] = {};
   
   bit support_unaligned_load_store = 1'b1;
   
   // EH2 supports RV32IMAC plus configuration-selected bitmanip groups.
   riscv_instr_group_t supported_isa[$] = {
     RV32I,
     RV32M,
     RV32A,
     RV32C
     ,RV32ZBA
     ,RV32ZBB
     ,RV32ZBC
     ,RV32ZBS
   };
   
   mtvec_mode_t supported_interrupt_mode[$] = {DIRECT, VECTORED};
   int max_interrupt_vector_num = 32;
   
   bit support_pmp = 0;
   bit support_epmp = 0;
   bit support_debug_mode = 1;
   bit support_umode_trap = 0;
   bit support_sfence = 0;

逐段解释：

* 第 L20-L23 行：当前 EH2 riscv-dv setting 使用 `NUM_HARTS=1`、`SATP_MODE=BARE`，
  并只列出 `MACHINE_MODE`。
* 第 L25-L39 行：`supported_isa` 包含 RV32I、RV32M、RV32A、RV32C、
  RV32ZBA、RV32ZBB、RV32ZBC 和 RV32ZBS。
* 第 L41-L48 行：interrupt mode 包含 DIRECT 和 VECTORED；PMP/ePMP 在该 setting
  中为 0，debug mode 为 1，umode trap 和 sfence 为 0。

接口关系：

* 被调用：riscv-dv generator、`compile_test.py`、riscv-dv extension tests。
* 调用：riscv-dv type definitions。
* 共享状态：ISA group、privilege mode、interrupt mode、debug support。

§7.2  EH2 custom CSR 列表
~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 riscv-dv extension 显式列出 upstream riscv-dv 没有符号名的
EH2 custom CSR。

关键代码（`dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L100-L120`）：

.. code-block:: systemverilog

   // EH2 custom CSRs are generated numerically because upstream riscv-dv does not
   // define symbolic names for the VeeR/EH2 machine CSRs.
   const bit [11:0] custom_csr[] = {
     12'h7FF,  // mscause
     12'h7C0,  // mrac
     12'h7C9,  // mfdc
     12'h7F8,  // mcgc
     12'h7C6,  // mpmc
     12'h7C2,  // mcpc
     12'h7C4,  // dmst
     12'h7CE,  // mfdht
     12'h7CF,  // mfdhs
     12'hFC4,  // mhartnum
     12'h7FC,  // mhartstart
     12'h7FE,  // mnmipdel
     12'h7D2,  // mitcnt0
     12'h7D5,  // mitcnt1
     12'h7D3,  // mitb0
     12'h7D6,  // mitb1
     12'h7D4,  // mitctl0
     12'h7D7,  // mitctl1

逐段解释：

* 第 L100-L102 行：注释说明 custom CSR 使用数值生成，因为 upstream riscv-dv
  不定义 VeeR/EH2 machine CSR 符号名。
* 第 L103-L120 行：数组列出 `mscause`、`mrac`、`mfdc`、`mcgc`、`mpmc`、
  `mcpc`、`dmst`、`mfdht`、`mfdhs`、`mhartnum`、`mhartstart`、`mnmipdel`
  和多组 timer/PIC 相关 CSR。
* 这解释了为什么 EH2 与 Ibex 使用相同 riscv-dv 框架时，CSR 空间仍需 EH2-specific
  extension。

接口关系：

* 被调用：riscv-dv CSR generator、CSR directed streams。
* 调用：EH2 custom CSR 数值表。
* 共享状态：custom CSR、CSR waiver、Spike CSR preregistration。

§7.3  Ibex riscv-dv 模板
~~~~~~~~~~~~~~~~~~~~~~~~

职责：给出 Ibex 参考 setting 模板中的 privilege 和 ISA 配置形式。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/riscv_dv_extension/riscv_core_setting.tpl.sv:L37-L64`）：

.. code-block:: systemverilog

   // Number of harts
   parameter int NUM_HARTS = 1;
   
   // Parameter for SATP mode, set to BARE if address translation is not supported
   parameter satp_mode_t SATP_MODE = BARE;
   
   // Supported Privileged mode
   privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE, USER_MODE};
   
   // Unsupported instructions
   // Avoid generating these instructions in regular regression
   // FENCE.I is intentionally treated as illegal instruction by ibex core
   riscv_instr_name_t unsupported_instr[] = {};
   
   // Specify whether processor supports unaligned loads and stores
   bit support_unaligned_load_store = 1'b1;
   
   riscv_instr_group_t supported_isa[$] = {RV32I, RV32M, RV32C
   % if ibex_config['RV32B'] == 'ibex_pkg::RV32BNone':
       };
   % else:
       ,RV32ZBA, RV32ZBB, RV32ZBC, RV32ZBS, RV32B};
   % endif
   
   // Interrupt mode support
   mtvec_mode_t supported_interrupt_mode[$] = {VECTORED};

逐段解释：

* 第 L37-L44 行：Ibex 模板同样设置 `NUM_HARTS=1` 和 `SATP_MODE=BARE`，
  但 supported privileged mode 包含 MACHINE_MODE 和 USER_MODE。
* 第 L46-L52 行：模板保留 unsupported instruction 和 unaligned load/store 设置。
* 第 L56-L61 行：Ibex 的 `supported_isa` 由模板条件决定 RV32B 相关 groups；
  基础集合为 RV32I、RV32M、RV32C。
* 第 L63-L64 行：Ibex 模板的 interrupt mode 为 VECTORED。

接口关系：

* 被调用：Ibex config template renderer。
* 调用：Ibex `ibex_config` 模板变量。
* 共享状态：Ibex RV32B config、privilege mode、riscv-dv generator。

§8  Spike DPI 与 CSR 模型差异
------------------------------

EH2 的 Spike DPI 实现从 Ibex cosim 适配而来，但增加了 NUM_THREADS、EH2 ISA
默认字符串、EH2 custom CSR preregistration、PMP/atomic/debug/interrupt fixup
等路径。Ibex 参考 scoreboard 则直接调用 `spike_cosim_init()` 和
`riscv_cosim_step()`，使用 RVFI item 中的 rd/PC/trap 信息。

§8.1  EH2 SpikeCosim 多线程构造
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 `SpikeCosim` 按 `num_threads` 创建多个 Spike `processor_t`。

关键代码（`dv/cosim/spike_cosim.cc:L24-L54`）：

.. code-block:: cpp

   SpikeCosim::SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                          uint32_t start_mtvec, const std::string &trace_log_path,
                          uint32_t pmp_num_regions, uint32_t pmp_granularity,
                          uint32_t mhpm_counter_num, int num_threads)
       : num_threads(num_threads), active_thread(0) {
     assert(num_threads >= 1 && num_threads <= COSIM_MAX_THREADS);
   
     FILE *log_file = nullptr;
     if (trace_log_path.length() != 0) {
       log = std::make_unique<log_file_t>(trace_log_path.c_str());
       log_file = log->get();
     }
   
     isa_parser = std::make_unique<isa_parser_t>(isa_string.c_str(), "MU");
   
     for (int t = 0; t < num_threads; ++t) {
       processors[t] = std::make_unique<processor_t>(
           isa_parser.get(), DEFAULT_VARCH, this, t, false, log_file, std::cerr);
   
       processors[t]->set_pmp_num(pmp_num_regions);
       processors[t]->set_mhpm_counter_num(mhpm_counter_num);
       processors[t]->set_pmp_granularity(1 << (pmp_granularity + 2));

逐段解释：

* 第 L24-L29 行：构造函数接收 `num_threads`，并断言范围在 1 到
  `COSIM_MAX_THREADS`。
* 第 L31-L37 行：如果配置了 trace log，就创建 Spike log file；随后根据 ISA 字符串
  创建 `isa_parser_t`。
* 第 L39-L47 行：循环为每个 thread 创建一个 `processor_t`，并设置 PMP region、
  MHPM counter 和 PMP granularity。
* 第 L49-L53 行：启用 log 时，每个 processor 都打开 debug 和 commit log。

接口关系：

* 被调用：`riscv_cosim_init()`。
* 调用：Spike `processor_t`、`isa_parser_t`、PMP/MHPM setup。
* 共享状态：NUM_THREADS、active_thread、per-hart processor state。

§8.2  EH2 `riscv_cosim_init()` 默认 ISA
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 DPI 工厂函数默认使用 RV32IMAC 加 Zba/Zbb/Zbc/Zbs，并允许配置覆盖。

关键代码（`dv/cosim/spike_cosim.cc:L1608-L1622`）：

.. code-block:: cpp

   extern "C" void *riscv_cosim_init(const char *config) {
     // Parse config string: "isa=<ISA>;pc=<PC>;mtvec=<MTVEC>;pmp_regions=<N>;"
     //                       "pmp_granularity=<G>;mhpm_counters=<N>;trace=<PATH>"
     //                       ";num_threads=<N>"
     std::string config_str(config);
     // Default ISA string includes Zba/Zbb/Zbc/Zbs per default EH2 config.
     // If the config string contains ``isa=...`` the parsed value overrides this.
     std::string isa_string = "rv32imac_zba_zbb_zbc_zbs";
     uint32_t start_pc = 0;
     uint32_t start_mtvec = 0;
     uint32_t pmp_num_regions = 0;
     uint32_t pmp_granularity = 0;
     uint32_t mhpm_counter_num = 0;
     int num_threads = 1;
     std::string trace_log_path;

逐段解释：

* 第 L1608-L1612 行：DPI 入口接收 config string，语法包含 ISA、PC、mtvec、
  PMP region/granularity、MHPM counter、trace path 和 `num_threads`。
* 第 L1613-L1615 行：默认 ISA 是 `rv32imac_zba_zbb_zbc_zbs`，与 EH2 默认
  bitmanip 配置一致；如果 config string 中有 `isa=...`，则后续 parser 覆盖默认值。
* 第 L1616-L1622 行：PC、mtvec、PMP、MHPM、thread count 和 trace path 有默认值。

接口关系：

* 被调用：SV DPI `riscv_cosim_init` import。
* 调用：配置 parser 和 `SpikeCosim` 构造。
* 共享状态：ISA string、NUM_THREADS、start PC、mtvec、PMP 配置。

§8.3  EH2 custom CSR preregistration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 scoreboard 在 cosim 初始化时预注册 28 个 EH2 custom CSR，避免
Spike 将其当成 illegal CSR。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh:L1-L18`）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 Custom CSR Pre-registration
   //
   // EH2 implements 28 vendor-specific CSRs that Spike's csrmap does not know
   // about. Pre-register them as zero-initialized so that any CSR access
   // instruction Spike sees is treated as a legal CSR operation rather than
   // triggering an illegal-instruction trap.
   //
   // Future work: model these CSRs' WARL behavior in Spike's fixup_csr() so
   // reads/writes match the EH2 RTL semantics. See ADR (TBD).
   //
   // Included from inside eh2_cosim_scoreboard's init_cosim function.
   
         riscv_cosim_set_csr(cosim_handle, 32'h7FF, 0, 0);  // mscause
         riscv_cosim_set_csr(cosim_handle, 32'h7C0, 0, 0);  // mrac
         riscv_cosim_set_csr(cosim_handle, 32'h7F9, 0, 0);  // mfdc
         riscv_cosim_set_csr(cosim_handle, 32'h7F8, 0, 0);  // mcgc

逐段解释：

* 第 L2-L7 行：注释说明 EH2 实现 28 个 vendor-specific CSR，Spike 的 `csrmap`
  不认识这些 CSR；预注册后，Spike 在执行 CSR 指令时不会将其作为 illegal CSR。
* 第 L9-L12 行：该 header 从 `eh2_cosim_scoreboard` 的 `init_cosim()` 内部 include。
* 第 L14-L18 行：示例预注册 `mscause`、`mrac`、`mfdc`、`mcgc` 等 CSR。

接口关系：

* 被调用：`eh2_cosim_scoreboard.init_cosim()`。
* 调用：DPI `riscv_cosim_set_csr`。
* 共享状态：EH2 custom CSR、Spike CSR model、cosim initialization。

§8.4  Ibex scoreboard 的 RVFI step 路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 Ibex 参考 scoreboard 直接使用 RVFI seq item 中的 rd、PC、trap 和
RF suppress 信息调用 Spike step。

关键代码（`/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_cosim_scoreboard.sv:L147-L176`）：

.. code-block:: systemverilog

         // Note these must be called in this order to ensure debug vs nmi vs normal interrupt are
         // handled with the correct priority when they occur together.
         riscv_cosim_set_debug_req(cosim_handle, rvfi_instr.debug_req);
         riscv_cosim_set_nmi(cosim_handle, rvfi_instr.nmi);
         riscv_cosim_set_nmi_int(cosim_handle, rvfi_instr.nmi_int);
         riscv_cosim_set_mip(cosim_handle, rvfi_instr.pre_mip, rvfi_instr.post_mip);
         riscv_cosim_set_mcycle(cosim_handle, rvfi_instr.mcycle);
   
         // Set performance counters through a pseudo-backdoor write
         for (int i=0; i < 10; i++) begin
           riscv_cosim_set_csr(cosim_handle,
                               ibex_pkg::CSR_MHPMCOUNTER3 + i, rvfi_instr.mhpmcounters[i]);
           riscv_cosim_set_csr(cosim_handle,
                               ibex_pkg::CSR_MHPMCOUNTER3H + i, rvfi_instr.mhpmcountersh[i]);
         end
   
         riscv_cosim_set_ic_scr_key_valid(cosim_handle, rvfi_instr.ic_scr_key_valid);
   
         if (!riscv_cosim_step(cosim_handle, rvfi_instr.rd_addr, rvfi_instr.rd_wdata, rvfi_instr.pc,
                               rvfi_instr.trap, rvfi_instr.rf_wr_suppress)) begin

逐段解释：

* 第 L147-L153 行：Ibex 参考 scoreboard 按固定顺序同步 debug、NMI、interrupt 和 mcycle。
* 第 L155-L161 行：Ibex 通过 pseudo-backdoor 写入 performance counter CSR。
* 第 L163-L166 行：Ibex 使用 `rvfi_instr.rd_addr`、`rvfi_instr.rd_wdata`、
  `rvfi_instr.pc`、`rvfi_instr.trap` 和 `rvfi_instr.rf_wr_suppress`
  调用 `riscv_cosim_step()`。
* 对比 EH2 §4.4：EH2 需要在 step 前处理 trace pkt 写回视图和异步 wb hint；Ibex
  参考路径直接信任 RVFI item。

接口关系：

* 被调用：`run_cosim_rvfi()`。
* 调用：Ibex DPI `riscv_cosim_*` 函数。
* 共享状态：RVFI item、Spike cosim handle、performance counter CSR。

§9  coverage 能力对比
---------------------

EH2 coverage 文件直接覆盖 dual-issue、i0/i1 instruction category、stall、branch、
exception、interrupt、debug、ICache、LSU external access 和 cross coverage。Ibex
同样有 coverage infrastructure，但本章的 EH2 能力只引用当前 EH2 源码和 release
coverage 数字。

§9.1  EH2 uarch covergroup
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 的 `uarch_cg` 分别采样 i0 和 i1 instruction category。

关键代码（`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L212-L253`）：

.. code-block:: systemverilog

     covergroup uarch_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = "uarch_cg";
   
       // -----------------------------------------------------------------------
       // Instruction categories at decode
       // -----------------------------------------------------------------------
       cp_i0_instr_category: coverpoint get_i0_instr_category() {
         bins alu         = {InstrCategoryALU};
         bins mul         = {InstrCategoryMul};
         bins div         = {InstrCategoryDiv};
         bins branch      = {InstrCategoryBranch};
         bins jump        = {InstrCategoryJump};
         bins load        = {InstrCategoryLoad};
         bins store       = {InstrCategoryStore};
         bins csr_access  = {InstrCategoryCSRAccess};
         bins ebreak      = {InstrCategoryEBreak};
         bins ecall       = {InstrCategoryECall};
         bins mret        = {InstrCategoryMRet};
         bins fence       = {InstrCategoryFence};
         bins atomic      = {InstrCategoryAtomic};
         bins illegal     = {InstrCategoryIllegal};
         ignore_bins none = {InstrCategoryNone};

逐段解释：

* 第 L212-L214 行：`uarch_cg` 在 `posedge clk_i` 采样，per-instance 打开，名字为
  `uarch_cg`。
* 第 L217-L235 行：i0 coverpoint 覆盖 ALU、MUL、DIV、branch、jump、load、store、
  CSR、EBREAK、ECALL、MRET、fence、atomic 和 illegal。
* 第 L237-L253 行：源码随后定义 i1 instruction category coverpoint，bin 集合与 i0
  对齐，这对应 EH2 双发射 slot coverage。

接口关系：

* 被调用：fcov bind/top TB 实例化路径。
* 调用：`get_i0_instr_category()`、`get_i1_instr_category()`。
* 共享状态：i0/i1 decode、instruction category、slot。

§9.2  EH2 cross coverage
~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EH2 coverage 不只统计单点 coverpoint，还定义 instruction/stall、branch、
interrupt/debug、dual-issue 和 compressed/dual-issue cross。

关键代码（`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L386-L414`）：

.. code-block:: systemverilog

       // -----------------------------------------------------------------------
       // Crosses
       // -----------------------------------------------------------------------
   
       // Instruction category x stall type
       stall_cross: cross cp_i0_instr_category, cp_stall_type {
         ignore_bins illegal_stall = binsof(cp_i0_instr_category.illegal);
       }
   
       // Branch taken x mispredict
       branch_cross: cross cp_i0_branch_taken, cp_i0_branch_mispredict;
   
       // Interrupt x debug mode
       interrupt_debug_cross: cross cp_interrupt_taken, cp_debug_mode;
   
       // Dual-issue x I0 category
       dual_issue_cross: cross cp_dual_issue, cp_i0_instr_category;
   
       // Exception x stall
       exception_stall_cross: cross cp_exception_type, cp_stall_type;
   
       // I0 x I1 instruction categories (for dual-issue coverage)
       pipe_cross: cross cp_i0_instr_category, cp_i1_instr_category {
         // Only meaningful when both pipes are active
         ignore_bins i1_empty = binsof(cp_i1_instr_category) intersect {InstrCategoryNone};
       }
   
       // Compressed x dual-issue
       compressed_dual_cross: cross cp_i0_compressed, cp_i1_compressed, cp_dual_issue;

逐段解释：

* 第 L390-L397 行：coverage 交叉 instruction category/stall 和 branch taken/mispredict。
* 第 L398-L405 行：interrupt/debug、dual-issue/i0 category 和 exception/stall
  都是显式 cross。
* 第 L407-L414 行：`pipe_cross` 交叉 i0/i1 instruction category，并忽略 i1 empty；
  `compressed_dual_cross` 交叉 i0/i1 compressed 状态与 dual-issue。

接口关系：

* 被调用：coverage merge 和 sign-off coverage gate。
* 调用：coverpoint 和 cross bins。
* 共享状态：dual_issue、interrupt/debug、stall、branch、exception。

§9.3  release coverage 数字
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 coverage 模型和 2026-05-19 VCS 主线 release-facing coverage result 分开记录。

实测覆盖率摘要：

.. code-block:: text

   Coverage (dut subtree, urg 原生 dashboard):
     LINE     95.05%
     BRANCH   84.97%
     TOGGLE   53.52%
     ASSERT   33.33%
     FSM      54.74%
     GROUP    69.42%
     OVERALL  65.17%

逐段解释：

* 第 1 行：覆盖率统计限定在 `core_eh2_tb_top.dut` 子树，报告由 Synopsys URG 原生生成。
* 第 2-8 行：当前 release-facing 数字包括 line、branch、toggle、assert、fsm、
  group 和 overall；不再使用旧 NC/IMC 迁移阶段的条件覆盖维度。

接口关系：

* 被调用：:ref:`goals_scope`、:ref:`coverage_plan`、:ref:`functional_coverage`。
* 调用：coverage dashboard 和 sign-off collector output。
* 共享状态：line、branch、toggle、assert、fsm、group、overall coverage。

§10  sign-off 能力矩阵
----------------------

本节把 EH2 v1.1 的 release result 与能力矩阵绑定。所有数字来自
2026-05-19 01:02 VCS 主线 demo，并保持跨章节字面一致。

.. list-table::
   :header-rows: 1
   :widths: 24 28 28 20

   * - 维度
     - EH2 v1.1 证据
     - Ibex 参考点
     - 本章结论
   * - UVM env
     - `core_eh2_env` 创建 AXI4、IRQ、JTAG、halt/run、trace、probe、cosim 组件
     - `core_ibex_env` 创建 memory response、IRQ、cosim、scrambling key 和 scoreboard
     - 目录形态相近，接口覆盖不同
   * - Retire 输入
     - trace pkt + RVFI-equivalent wb fields + async probe hint
     - `core_ibex_rvfi_if` 到 `ibex_rvfi_seq_item`
     - EH2 适配 trace/probe，Ibex 参考路径 RVFI-centered
   * - Spike DPI
     - `riscv_cosim_init` 默认 `rv32imac_zba_zbb_zbc_zbs`，支持 `num_threads`
     - Ibex scoreboard 直接以 RVFI rd/PC/trap 调 `riscv_cosim_step`
     - 两者都用 Spike，EH2 增加 EH2-specific 补偿
   * - Directed
     - 40/40
     - Ibex 有 directed testlist
     - EH2 v1.1 release gate PASS
   * - Cosim
     - 7/7
     - Ibex RVFI cosim
     - EH2 Spike DPI cosim gate PASS
   * - riscv-dv
     - 370/395
     - Ibex riscv-dv template
     - EH2 stage threshold closure
   * - CSR unit
     - 20/20
     - Ibex CSR/privileged support由参考环境提供
     - EH2 CSR unit gate PASS
   * - Compliance
     - 85/88
     - Ibex compliance framework不在本章展开
     - EH2 compliance gate PASS
   * - Formal
     - 46/46
     - Ibex formal stack不在本章展开
     - EH2 IFV result closed
   * - LEC
     - 31635/31635
     - Ibex synthesis checks不在本章展开
     - EH2 block-level Formality closure
   * - Coverage
     - line 95.05%、branch 84.97%、group 69.42%、overall 65.17%
     - Ibex coverage infrastructure
     - EH2 release coverage gate PASS

实测 sign-off 摘要：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   实跑覆盖率: 102/104 (98.1%)
   LEC: 31635/31635 PASS

   riscvdv  370/395 (93.67%)
   compliance  85/88 (96.59%)
   directed 40/40 (100%)
   formal 46/46 (100%)

逐段解释：

* 第 1-4 行：EH2 在当前 demo 中完成 9/9 stage PASS，LEC compare point 为
  31635/31635。
* 第 6-9 行：riscv-dv、compliance、directed 和 formal 是与 Ibex 能力矩阵最直接
  对照的 release-facing 数字。

接口关系：

* 被调用：能力矩阵、release report、用户验收门。
* 调用：`signoff.py` collector 和各 stage evidence。
* 共享状态：stage passed/total、coverage、formal、LEC。

§11  formal 与 LEC 对比边界
----------------------------

本章只记录 EH2 v1.1 当前 formal/LEC sign-off 状态，不扩展 Ibex formal stack 的细节。
原因是本章目标是 EH2-Veri 与 Ibex DV 平台能力对比，而 formal/LEC 的工具栈、版本和
证据路径由 EH2 release/status 文档定义。

§11.1  IFV formal 46/46
~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 v1.1 的 formal 结果来自 IFV log 和 top-level sign-off JSON。

关键代码（`docs/PROJECT_STATUS.md:L110-L148`）：

.. code-block:: bash

   ## Formal Status
   
   Formal source: `dv/formal/build/ifv_final.log`
   
   Formal sign-off collector source: `dv/uvm/core_eh2/scripts/signoff.py`
   
   Formal stage output: `build/demo/signoff_status.json`
   
   Formal result:
   
   ```text
   Total   : 46
   Pass    : 46
   Not_Run : 0
   Status  : PASS
   ```
   
   R3-A baseline:

逐段解释：

* 第 L110-L116 行：status 文档给出 formal source、collector source 和 stage output。
* 第 L118-L125 行：formal result 为 Total 46、Pass 46、Not_Run 0、Status PASS。
* 第 L127-L148 行：后续文本记录 R3-A baseline/final 变化，并说明 closure theme
  与 LSU、IFU、DMA、DCCM、ICCM、trace 和 debug status signal hookup 有关。

接口关系：

* 被调用：formal flow、sign-off report、能力矩阵 formal 行。
* 调用：`dv/formal/build/ifv_final.log`、`signoff.py` formal collector。
* 共享状态：formal 46/46、R3-A baseline/final。

§11.2  Block-level LEC 31635/31635
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 v1.1 的 LEC closure 是 block-level Formality 结果。

关键代码（`docs/PROJECT_STATUS.md:L85-L108`）：

.. code-block:: bash

   ## LEC Block-Level Status
   
   LEC source: `syn/build/lec_summary.txt`
   
   LEC stage in v1.1: `31635/31635 PASS`
   
   All 9 modules are closed:
   
   | Module | Passing | Failing | Unverified | Status |
   |---|---:|---:|---:|---:|
   | `eh2_dec` | 7160 | 0 | 0 | PASS |
   | `eh2_exu_alu_ctl` | 294 | 0 | 0 | PASS |
   | `eh2_exu_mul_ctl` | 272 | 0 | 0 | PASS |
   | `eh2_exu_div_ctl` | 181 | 0 | 0 | PASS |
   | `eh2_lsu` | 3565 | 0 | 0 | PASS |
   | `eh2_pic_ctrl` | 1573 | 0 | 0 | PASS |
   | `eh2_dma_ctrl` | 967 | 0 | 0 | PASS |

逐段解释：

* 第 L85-L90 行：LEC source 是 `syn/build/lec_summary.txt`，v1.1 stage 为
  31635/31635 PASS。
* 第 L91-L104 行：status 文档列出 9 个 closed module；摘录中显示 dec、EXU
  三个子块、LSU、PIC、DMA 等模块均为 0 failing、0 unverified。
* 第 L106-L108 行：status 文档还说明 R3-C block-level strategy 是 accepted closure
  path，且 summary 不使用 `set_dont_verify_points` waiver。

接口关系：

* 被调用：LEC flow、sign-off report、能力矩阵 syn 行。
* 调用：block-level Formality reports 和 `lec_summary.py`。
* 共享状态：31635/31635、module passing/failing/unverified。

§12  waiver 与能力边界
-----------------------

能力矩阵必须同时列出通过项和边界项。EH2 v1.1 当前 cosim-disabled count 为 6；
这些项通过 waiver 文件审查，不使用 inline `cosim_reason` 作为豁免入口。

关键代码（`docs/PROJECT_STATUS.md:L150-L173`）：

.. code-block:: bash

   ## Cosim Disabled Status
   
   Cosim disabled count: **6**
   
   All 6 are waiver-reviewed through:
   
   ```text
   dv/uvm/core_eh2/waivers/cosim-disabled.yaml
   ```
   
   Active cosim-disabled tests:
   
   | Test | Reason class |
   |---|---|
   | `riscv_csr_test` | EH2 custom CSR / WARL behavior not fully modeled by Spike |
   | `riscv_csr_hazard_test` | EH2 CSR pipeline hazard timing not represented by Spike |
   | `riscv_rf_addr_intg_test` | RTL integrity fault injection has no ISS equivalent |
   | `riscv_ram_intg_test` | RAM ECC/parity injection has no ISS equivalent |
   | `riscv_icache_intg_test` | ICache parity/tag fault injection has no ISS equivalent |

逐段解释：

* 第 L150-L158 行：status 文档把 cosim-disabled count 固定为 6，并指定 waiver 文件。
* 第 L160-L169 行：active disabled tests 包括 CSR、CSR hazard、RF address integrity、
  RAM integrity、ICache integrity 和 memory integrity error 等类别。
* 第 L171-L173 行：inline `cosim_reason` 不被接受，`signoff.py` 会把它作为 release-gate
  loophole 阻断。

关键代码（`dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L1-L15`）：

.. code-block:: yaml

   # EH2 Cosim-Disabled Waivers
   #
   # Each waiver corresponds to a test with `cosim: disabled` in the testlist
   # (riscv_dv_extension/testlist.yaml). Only waived tests pass the
   # --fail-on-cosim-disabled gate.
   #
   # Schema (per entry):
   #   test:            test name (must match testlist exactly)
   #   reason:          technical explanation of why cosim cannot run
   #   tracking_issue:  reference to issue tracker or ADR
   #   expiry_date:     YYYY-MM-DD — after this date the waiver is invalid
   #
   # cosim_reason fields in testlist.yaml are NOT waivers — only this file confers
   # formal waiver status. The gate is enforced by signoff.py.

逐段解释：

* 第 L1-L5 行：waiver 文件只对应 testlist 中 `cosim: disabled` 的测试，并且只有
  waiver 审查过的测试能通过 `--fail-on-cosim-disabled` gate。
* 第 L7-L11 行：每个条目必须有 test、reason、tracking_issue 和 expiry_date。
* 第 L13-L15 行：`cosim_reason` 字段不构成 waiver；formal waiver status 只来自
  `cosim-disabled.yaml`。

接口关系：

* 被调用：`signoff.py` waiver validation 和 release gate。
* 调用：`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`。
* 共享状态：cosim-disabled count、waiver schema、skip/gate policy。

§13  ADR 对应关系
------------------

本章引用的能力差异都有 ADR 或 status 记录支撑。当前 ADR 索引声明 canonical 文件号
从 `0001` 到 `0020`，因此本章使用 ADR 编号锚点引用，而不引用历史草稿
中的旧编号。

关键代码（`docs/adr/INDEX.md:L24-L45`）：

.. code-block:: bash

   | ADR | File | Status | Summary |
   |---:|---|---|---|
   | 0001 | `0001-cosim-via-trace-and-probe.md` | Accepted | Defines the trace-packet plus DUT-probe cosim data path that replaces fragile writeback reconstruction. |
   | 0002 | `0002-axi4-passive-monitoring.md` | Accepted | Chooses passive AXI4 monitoring and behavioral memory as the first EH2 bus strategy. |
   | 0003 | `0003-num-threads-cosim-scope.md` | Accepted | Sets the original single-thread cosim sign-off boundary and documents NUM_THREADS constraints. |
   | 0004 | `0004-rtl-rvfi-equivalent-trace.md` | Accepted | Adds verification-oriented retire fields to EH2 trace rather than forcing a full RVFI bus into design RTL. |
   | 0005 | `0005-spike-cosim-store-wider-wstrb.md` | Accepted | Records the EH2 store wider-WSTRB handling accepted by the Spike cosim bridge. |
   | 0006 | `0006-atomic-cosim.md` | Accepted | Documents A-subset atomic cosim fixups and the LR/SC/AMO verification direction. |
   | 0007 | `0007-interrupt-cosim.md` | Accepted | Captures interrupt cosim closure strategy and Spike synchronization constraints. |
   | 0008 | `0008-debug-cosim.md` | Accepted | Captures debug-mode cosim closure, including debug CSR and DRET-sensitive behavior. |
   | 0009 | `0009-pmp-cosim.md` | Accepted | Captures PMP/ePMP cosim closure strategy and model boundaries. |
   | 0010 | `0010-csr-register-model.md` | Accepted | Defines the EH2 CSR register model based on `uvm_reg` over `csr_desc_t`. |
   | 0011 | `0011-compliance-framework.md` | Accepted | Documents the RISC-V compliance framework integrated into the sign-off profile. |
   | 0012 | `0012-formal-strategy.md` | Accepted | Defines the multi-module formal verification strategy and property ownership. |
   | 0013 | `0013-synthesis-toolchain.md` | Accepted | Records synthesis toolchain choices and the open-source versus commercial tradeoff. |
   | 0014 | `0014-formal-real-runs.md` | Accepted | Records the transition from formal scaffolding to real formal runs and their limitations. |
   | 0015 | `0015-rvfi-adapter-layer.md` | Accepted | Defines the RVFI adapter layer that avoids modifying upstream design RTL. |
   | 0016 | `0016-multi-hart-cosim.md` | Accepted | Records the NUM_THREADS=2 cosim support path and per-hart Spike routing. |
   | 0017 | `0017-integrity-cosim-waiver.md` | Accepted | Documents why integrity fault-injection tests remain cosim-disabled with formal waivers. |
   | 0018 | `0018-wb-tag-strict-matching.md` | Accepted | Replaces asynchronous writeback `rd` heuristics with strict `wb_tag` association. |
   | 0019 | `0019-lec-tool-version-limitation.md` | Accepted | Documents the Formality tool-version limitation that affected earlier top-level LEC runs. |
   | 0020 | `0020-blocklevel-lec.md` | Accepted | Defines the R3-C block-level LEC closure path and packed-port mitigation. |

逐段解释：

* 第 L24-L29 行：ADR-0001 到 ADR-0004 覆盖 trace/probe 数据路、AXI4 passive
  monitoring、NUM_THREADS 早期边界和 retire trace fields。
* 第 L30-L35 行：ADR-0005 到 ADR-0010 覆盖 wider WSTRB、atomic、interrupt、
  debug、PMP 和 CSR register model。
* 第 L36-L45 行：ADR-0011 到 ADR-0020 覆盖 compliance、formal、synthesis、
  real formal runs、RVFI adapter、multi-hart cosim、integrity waiver、strict
  `wb_tag`、LEC tool limitation 和 block-level LEC closure。

接口关系：

* 被调用：能力矩阵所有结论引用。
* 调用：:ref:`adr-0001`、:ref:`adr-0002`、:ref:`adr-0004`、:ref:`adr-0016`、
  :ref:`adr-0017`、:ref:`adr-0018`、:ref:`adr-0020`。
* 共享状态：ADR 0001-0020。

§14  结论
----------

EH2-Veri v1.1 与 Ibex 参考平台的关系可以概括为：目录组织和 UVM/cosim/riscv-dv
方法论对齐，但 EH2 的 DUT surface 需要不同的数据通路和更多 EH2-specific agent。

* Ibex 参考 cosim 路径以 RVFI item 为中心；EH2 当前路径以 trace pkt、RVFI-equivalent
  writeback fields、async probe hint 和 AXI4 D-side notification 组合为中心。
* Ibex 参考 env 以 memory response、IRQ、cosim 和 RVFI monitor 组织；EH2 env 增加
  AXI4、JTAG、halt/run、trace、probe 和 double-fault detection scoreboard。
* EH2 v1.1 release 数字是 formal 46/46、LEC 31635/31635、compliance 85/88、
  riscv-dv 370/395、directed 40/40、实跑覆盖率 102/104、line 95.05%、
  branch 84.97%、group 69.42%、overall 65.17%。
* EH2 的 cosim-disabled 边界是 6 个 waiver-reviewed 测试，主要来自 EH2 custom CSR
  / WARL timing 和 integrity fault-injection 与 Spike ISA model 的不可比性。

§15  参考资料
--------------

关联章节：

* :ref:`goals_scope` — v1.1 验证目标、范围和 sign-off 数字。
* :ref:`quickstart` — 当前 smoke/regress/signoff 命令入口。
* :ref:`cosim_scoreboard` — EH2 cosim scoreboard 数据路和 Spike 通知顺序。
* :ref:`functional_coverage` — EH2 functional coverage 结构。
* :doc:`../05_verification_arch/cosim_scoreboard` — 逐段 scoreboard 深度说明。

关联 ADR：

* :ref:`adr-0001` — trace + probe cosim 数据路。
* :ref:`adr-0002` — AXI4 passive monitoring。
* :ref:`adr-0004` — RVFI-equivalent retire trace fields。
* :ref:`adr-0016` — NUM_THREADS=2 cosim support。
* :ref:`adr-0017` — integrity cosim waiver boundary。
* :ref:`adr-0018` — strict `wb_tag` matching。
* :ref:`adr-0020` — block-level LEC closure。

源文件绝对路径：

* `/home/host/eh2-veri/README.md`
* `/home/host/eh2-veri/CONTEXT.md`
* `/home/host/eh2-veri/docs/PROJECT_STATUS.md`
* `/home/host/eh2-veri/docs/release-notes-v1.1.md`
* `/home/host/eh2-veri/docs/adr/INDEX.md`
* `/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`
* `/home/host/eh2-veri/dv/cosim/spike_cosim.cc`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv`
* `/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`
* `/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_if.sv`
* `/home/host/ibex/dv/uvm/core_ibex/tb/core_ibex_tb_top.sv`
* `/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_env.sv`
* `/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_rvfi_monitor.sv`
* `/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_rvfi_seq_item.sv`
* `/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_cosim_scoreboard.sv`
* `/home/host/ibex/dv/uvm/core_ibex/riscv_dv_extension/riscv_core_setting.tpl.sv`
