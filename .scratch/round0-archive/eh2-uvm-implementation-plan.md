# EH2 UVM Verification Platform Implementation Plan

## Based on Ibex UVM Architecture -- Complete Implementation Guide

**Date:** 2026-05-03
**Project:** VeeR EH2 RISC-V Core UVM Verification Platform
**Baseline:** lowRISC Ibex UVM DV Platform (`/home/host/ibex/dv/`)
**Target DUT:** VeeR EH2 (`/home/host/Cores-VeeR-EH2/`)
**Reference:** Existing eh2-verification (`/home/host/eh2-verification/`)

---

## 1. Context and Motivation

### 1.1 Problem Statement

The existing `eh2-verification` platform is a policy-driven offline RTL/QEMU co-simulation environment. While it achieves clean sign-off (404 PASS / 0 FAIL), it lacks industry recognition because:

- It uses shell-script-based test orchestration instead of UVM
- No RVFI-level cycle-by-cycle lockstep verification
- No SystemVerilog functional coverage (covergroups)
- No constrained-random stimulus via UVM sequences
- No DPI-based ISS co-simulation (uses offline trace comparison)

### 1.2 Goal

Build a **UVM-based verification platform** for EH2, following the Ibex UVM architecture as a proven template. The platform should be:

- Industry-standard UVM methodology
- RVFI-level co-simulation (via QEMU or Spike DPI)
- SystemVerilog functional coverage
- Constrained-random stimulus via riscv-dv + UVM sequences
- Multi-simulator support (VCS primary, Xcelium secondary)
- CI-ready with automated regression and reporting

### 1.3 Key Architectural Differences: Ibex vs EH2

| Feature | Ibex | EH2 | Impact |
|---------|------|-----|--------|
| Bus Interface | Simple req/gnt/rvalid | AXI4 (4 ports: IFU/LSU/SB/DMA) | Must replace memory agent with AXI agent |
| Memory | External behavioral RAM | DCCM + ICCM + ICache (tightly coupled) | Must model SRAM arrays with ECC |
| Interrupts | 5 lines (software/timer/ext/fast/nm) | 127 sources via PIC + timer + soft | Must build PIC-aware interrupt agent |
| Debug | Simple debug_req | JTAG/DMI with full DM spec | Must build JTAG agent |
| RVFI | Full RVFI (rd_addr, rd_wdata, mem_*, csr_*) | Simplified trace (PC + insn + exception only) | Must probe DUT internals for full visibility |
| Threading | Single thread | Dual thread (NUM_THREADS=1 or 2) | Must support multi-hart verification |
| Pipeline | 2-3 stage | Multi-stage with dual-issue | Trace monitor must handle dual retirement |
| ISA | RV32IMC + optional B/E | RV32IMAC + Zba/Zbb/Zbc/Zbs | Different ISA string for riscv-dv |

---

## 2. Architecture Overview

### 2.1 Target Directory Structure

```
/home/host/eh2-veri/
├── eh2-uvm-implementation-plan.md          # This document
├── dv/
│   ├── uvm/
│   │   ├── core_eh2/
│   │   │   ├── tb/
│   │   │   │   └── core_eh2_tb_top.sv      # Top testbench
│   │   │   ├── env/
│   │   │   │   ├── core_eh2_env.sv          # UVM environment
│   │   │   │   ├── core_eh2_env_cfg.sv      # Environment config
│   │   │   │   ├── core_eh2_scoreboard.sv   # Scoreboard
│   │   │   │   ├── core_eh2_vseqr.sv        # Virtual sequencer
│   │   │   │   ├── core_eh2_dut_probe_if.sv # DUT probe interface
│   │   │   │   ├── core_eh2_trace_if.sv     # Trace/RVFI interface
│   │   │   │   └── core_eh2_csr_if.sv       # CSR monitor interface
│   │   │   ├── common/
│   │   │   │   ├── axi4_agent/              # AXI4 agent (new)
│   │   │   │   ├── jtag_agent/              # JTAG agent (new)
│   │   │   │   ├── irq_agent/               # IRQ agent (adapted from Ibex)
│   │   │   │   ├── eh2_cosim_agent/         # Co-simulation agent (new)
│   │   │   │   └── halt_run_agent/          # MPC halt/run agent (new)
│   │   │   ├── tests/
│   │   │   │   ├── core_eh2_base_test.sv
│   │   │   │   ├── core_eh2_test_lib.sv
│   │   │   │   ├── core_eh2_test_pkg.sv
│   │   │   │   ├── core_eh2_vseq.sv
│   │   │   │   └── core_eh2_seq_lib.sv
│   │   │   ├── fcov/
│   │   │   │   ├── core_eh2_fcov_if.sv      # Functional coverage
│   │   │   │   └── core_eh2_fcov_bind.sv    # Coverage bind
│   │   │   ├── riscv_dv_extension/
│   │   │   │   ├── eh2_asm_program_gen.sv
│   │   │   │   ├── user_extension.svh
│   │   │   │   └── testlist.yaml
│   │   │   ├── scripts/
│   │   │   │   ├── metadata.py
│   │   │   │   ├── compile_tb.py
│   │   │   │   ├── run_rtl.py
│   │   │   │   ├── check_logs.py
│   │   │   │   └── collect_results.py
│   │   │   ├── yaml/
│   │   │   │   └── rtl_simulation.yaml
│   │   │   ├── Makefile
│   │   │   └── wrapper.mk
│   │   └── bus_params_pkg/
│   └── cosim/
│       ├── cosim.h                          # Abstract cosim interface
│       ├── eh2_cosim.cc                     # EH2-specific cosim impl
│       ├── eh2_cosim.h
│       ├── cosim_dpi.cc
│       ├── cosim_dpi.h
│       └── cosim_dpi.svh
├── rtl/                                     # Symlink to EH2 RTL
├── shared/
│   └── rtl/
│       ├── axi4_pkg.sv                      # AXI4 package
│       ├── axi4_intf.sv                     # AXI4 interface
│       ├── axi4_slave_mem.sv                # AXI4 memory model
│       └── jtag_intf.sv                     # JTAG interface
├── vendor/
│   └── google_riscv-dv/                     # Symlink to riscv-dv
├── eh2_configs.yaml                         # EH2 configurations
└── eh2_top.core                             # FuseSoC core file
```

### 2.2 UVM Component Hierarchy

```
core_eh2_tb_top (module)
├── clk_rst_if                              # Clock/reset generation
├── axi4_intf ifu_axi_vif                   # IFU AXI4 interface
├── axi4_intf lsu_axi_vif                   # LSU AXI4 interface
├── axi4_intf sb_axi_vif                    # SB AXI4 interface
├── axi4_intf dma_axi_vif                   # DMA AXI4 interface
├── jtag_intf jtag_vif                      # JTAG interface
├── irq_if irq_vif                          # Interrupt interface
├── core_eh2_dut_probe_if dut_if            # DUT internal probes
├── core_eh2_trace_if trace_if              # Trace interface
├── core_eh2_csr_if csr_if                  # CSR monitor
├── halt_run_if halt_run_vif                # Halt/run interface
│
└── eh2_veer_wrapper DUT                    # Device Under Test
    ├── dmi_wrapper                         # JTAG-to-DMI
    ├── eh2_veer                            # Core
    └── eh2_mem                             # Tightly coupled memories

core_eh2_env (uvm_env)
├── axi4_response_agent ifu_axi_agent       # IFU memory response
├── axi4_response_agent lsu_axi_agent       # LSU memory response
├── axi4_response_agent sb_axi_agent        # SB memory response
├── axi4_master_agent dma_axi_agent         # DMA master
├── jtag_agent jtag_agt                     # JTAG/DMI driver
├── irq_request_agent irq_agt               # Interrupt stimulus
├── halt_run_agent halt_run_agt             # MPC halt/run
├── eh2_cosim_agent cosim_agt               # QEMU co-simulation
├── core_eh2_vseqr vseqr                    # Virtual sequencer
├── core_eh2_scoreboard scoreboard           # Result checker
└── core_eh2_env_cfg cfg                    # Configuration
```

---

## 3. Implementation Phases

### Phase 0: Infrastructure Setup (Week 1)

**Goal:** Create project skeleton, build system, verify RTL compiles.

#### 3.0.1 Create Directory Structure
- Create `/home/host/eh2-veri/dv/` tree as shown in Section 2.1
- Symlink RTL: `ln -s /home/host/Cores-VeeR-EH2 /home/host/eh2-veri/rtl`
- Symlink riscv-dv: `ln -s /home/host/riscv-dv /home/host/eh2-veri/vendor/google_riscv-dv`

#### 3.0.2 Create FuseSoC Core File
**File:** `/home/host/eh2-veri/eh2_top.core`

```yaml
CAPI=2:
name = "lowrisc:veer:eh2_top:0.1"
description = "VeeR EH2 Core"
filesets:
  rtl:
    files:
      - rtl/design/include/eh2_def.sv
      - rtl/design/include/eh2_param.vh  # (from snapshots/default/)
      - rtl/design/lib/*.sv
      - rtl/design/ifu/*.sv
      - rtl/design/dec/*.sv
      - rtl/design/exu/*.sv
      - rtl/design/lsu/*.sv
      - rtl/design/dbg/*.sv
      - rtl/design/dmi/*.v
      - rtl/design/eh2_mem.sv
      - rtl/design/eh2_pic_ctrl.sv
      - rtl/design/eh2_dma_ctrl.sv
      - rtl/design/eh2_veer.sv
      - rtl/design/eh2_veer_wrapper.sv
    file_type: systemVerilog

targets:
  default:
    filesets: [rtl]
```

#### 3.0.3 Create Configuration File
**File:** `/home/host/eh2-veri/eh2_configs.yaml`

```yaml
default:
  description: "Default EH2 configuration (AXI4, single-thread)"
  parameters:
    NUM_THREADS: 1
    BUILD_AXI4: 1
    BUILD_AHB_LITE: 0
    DCCM_ENABLE: 1
    DCCM_SIZE: 64
    ICCM_ENABLE: 1
    ICCM_SIZE: 64
    ICACHE_ENABLE: 1
    ICACHE_SIZE: 32
    ATOMIC_ENABLE: 1
    BITMANIP_ZBA: 1
    BITMANIP_ZBB: 1
    BITMANIP_ZBC: 1
    BITMANIP_ZBS: 1
    PIC_TOTAL_INT: 127

minimal:
  description: "Minimal EH2 (no ICache, no DCCM)"
  parameters:
    NUM_THREADS: 1
    DCCM_ENABLE: 0
    ICCM_ENABLE: 0
    ICACHE_ENABLE: 0
    PIC_TOTAL_INT: 16

dual_thread:
  description: "Dual-thread EH2"
  parameters:
    NUM_THREADS: 2
    BUILD_AXI4: 1
    DCCM_ENABLE: 1
    ICCM_ENABLE: 1
    ICACHE_ENABLE: 1
    PIC_TOTAL_INT: 127
```

#### 3.0.4 Create AXI4 Interface Package
**File:** `/home/host/eh2-veri/shared/rtl/axi4_pkg.sv`

Standard AXI4 parameterized interface with:
- Configurable ID width (default 4)
- Configurable data width (default 64)
- Configurable address width (default 32)
- All AXI4 signal groups (AW/W/B/AR/R channels)

#### 3.0.5 Verify RTL Compilation
- Run VCS compilation of `eh2_veer_wrapper` with default parameters
- Resolve any compilation issues
- Document compilation command in Makefile

**Deliverables:**
- [ ] Directory structure created
- [ ] FuseSoC core file compiles
- [ ] RTL compilation passes with VCS
- [ ] Basic Makefile with `compile` target

---

### Phase 1: Clock/Reset and AXI4 Memory Agent (Weeks 2-3)

**Goal:** Get DUT running with clock/reset and basic memory responses.

#### 3.1.1 Clock/Reset Interface
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/common/clk_rst_if.sv`

Adapt from Ibex's `clk_rst_if`:
- `clk` output
- `rst_n` output (active high, maps to EH2's active-low `rst_l`)
- `apply_reset()` task with configurable width
- `set_active()` with configurable frequency

#### 3.1.2 AXI4 Response Agent (New)
This is the most significant new component. EH2 has 3 AXI4 master ports (IFU, LSU, SB) that need response agents.

**Files to create:**

1. **`axi4_intf.sv`** - AXI4 SystemVerilog interface
```systemverilog
interface axi4_intf #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 64,
  parameter int ID_WIDTH   = 4
) (input logic clk, input logic rst_n);
  // Write Address Channel
  logic [ID_WIDTH-1:0]    awid;
  logic [ADDR_WIDTH-1:0]  awaddr;
  logic [3:0]             awregion;
  logic [7:0]             awlen;
  logic [2:0]             awsize;
  logic [1:0]             awburst;
  logic                   awlock;
  logic [3:0]             awcache;
  logic [2:0]             awprot;
  logic [3:0]             awqos;
  logic                   awvalid;
  logic                   awready;
  // Write Data Channel
  logic [DATA_WIDTH-1:0]  wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic                   wlast;
  logic                   wvalid;
  logic                   wready;
  // Write Response Channel
  logic [ID_WIDTH-1:0]    bid;
  logic [1:0]             bresp;
  logic                   bvalid;
  logic                   bready;
  // Read Address Channel
  logic [ID_WIDTH-1:0]    arid;
  logic [ADDR_WIDTH-1:0]  araddr;
  logic [3:0]             arregion;
  logic [7:0]             arlen;
  logic [2:0]             arsize;
  logic [1:0]             arburst;
  logic                   arlock;
  logic [3:0]             arcache;
  logic [2:0]             arprot;
  logic [3:0]             arqos;
  logic                   arvalid;
  logic                   arready;
  // Read Data Channel
  logic [ID_WIDTH-1:0]    rid;
  logic [DATA_WIDTH-1:0]  rdata;
  logic [1:0]             rresp;
  logic                   rlast;
  logic                   rvalid;
  logic                   rready;

  // Clocking blocks for driver and monitor
  clocking driver_cb @(posedge clk);
    // ... drive AW/W/B/AR/R channels
  endclocking

  clocking monitor_cb @(posedge clk);
    // ... observe all channels
  endclocking
endinterface
```

2. **`axi4_response_agent.sv`** - UVM agent for AXI4 slave (memory model)
   - `axi4_response_driver.sv` - Drives AW/W/B/AR/R responses
   - `axi4_response_monitor.sv` - Monitors all transactions
   - `axi4_response_sequencer.sv` - Sequencer for response sequences
   - `axi4_response_seq.sv` - Response sequence with memory model
   - `axi4_seq_item.sv` - Transaction item

3. **`axi4_slave_mem.sv`** - Behavioral memory model
   - Byte-addressable memory array
   - Configurable size
   - Backdoor read/write for test loading
   - Supports burst transactions (INCR, WRAP)

#### 3.1.3 Top Testbench (Minimal)
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

Minimal version that:
- Instantiates `eh2_veer_wrapper` as DUT
- Connects clock/reset
- Connects AXI4 memory agents to IFU and LSU ports
- Ties off unused ports (DMA, JTAG, interrupts)
- Loads HEX file via backdoor
- Monitors mailbox address for pass/fail

#### 3.1.4 First Test: hello_world
- Compile existing `hello_world.hex` from `/home/host/Cores-VeeR-EH2/testbench/hex/`
- Load into memory model
- Run simulation
- Verify mailbox PASS (0xFF at 0xD0580000)

**Deliverables:**
- [ ] AXI4 agent compiles and runs
- [ ] hello_world test passes via mailbox
- [ ] Basic Makefile with `smoke` target

---

### Phase 2: Trace Monitor and DUT Probing (Weeks 4-5)

**Goal:** Enable instruction retirement tracking for co-simulation.

#### 3.2.1 Trace Interface
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_trace_if.sv`

Monitors the EH2 trace ports:
```systemverilog
interface core_eh2_trace_if (input logic clk, input logic rst_n);
  logic [1:0]  trace_rv_i_valid_ip;
  logic [63:0] trace_rv_i_insn_ip;
  logic [63:0] trace_rv_i_address_ip;
  logic [1:0]  trace_rv_i_exception_ip;
  logic [4:0]  trace_rv_i_ecause_ip;
  logic [1:0]  trace_rv_i_interrupt_ip;
  logic [31:0] trace_rv_i_tval_ip;

  // Decoded per-pipe signals
  logic        i0_valid;
  logic [31:0] i0_insn;
  logic [31:0] i0_pc;
  logic        i0_exception;
  logic [4:0]  i0_ecause;
  logic        i0_interrupt;

  logic        i1_valid;
  logic [31:0] i1_insn;
  logic [31:0] i1_pc;
  logic        i1_exception;
  logic [4:0]  i1_ecause;
  logic        i1_interrupt;

  // Decode packed signals
  assign i0_valid     = trace_rv_i_valid_ip[0];
  assign i1_valid     = trace_rv_i_valid_ip[1];
  assign i0_insn      = trace_rv_i_insn_ip[31:0];
  assign i1_insn      = trace_rv_i_insn_ip[63:32];
  assign i0_pc        = trace_rv_i_address_ip[31:0];
  assign i1_pc        = trace_rv_i_address_ip[63:32];
  assign i0_exception = trace_rv_i_exception_ip[0];
  assign i1_exception = trace_rv_i_exception_ip[1];
  assign i0_ecause    = trace_rv_i_ecause_ip;
  assign i1_ecause    = trace_rv_i_ecause_ip;
  assign i0_interrupt = trace_rv_i_interrupt_ip[0];
  assign i1_interrupt = trace_rv_i_interrupt_ip[1];

  // Instruction counter (order)
  longint unsigned i0_order;
  longint unsigned i1_order;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      i0_order <= 0;
      i1_order <= 0;
    end else begin
      if (i0_valid) i0_order <= i0_order + 1;
      if (i1_valid) i1_order <= i1_order + 1;
    end
  end
endinterface
```

#### 3.2.2 DUT Probe Interface
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_dut_probe_if.sv`

Probes deep DUT internals via hierarchical references:
- Pipeline control signals (flush, stall)
- Writeback signals (i0_result_wb, i1_result_wb, i0v, i1v)
- CSR write signals
- Exception/interrupt entry
- Debug mode status

#### 3.2.3 Trace Monitor (UVM)
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/common/eh2_cosim_agent/eh2_trace_monitor.sv`

Monitors `core_eh2_trace_if` and produces `eh2_trace_seq_item`:
- Captures per-retirement: PC, instruction, exception, cause
- Maintains instruction order counter
- Handles dual-pipe retirement (i0 and i1 in same cycle)
- Outputs to analysis port for scoreboard consumption

#### 3.2.4 Enhanced Trace with DUT Probing
Since EH2's trace ports lack register write data, we must probe DUT internals:

```systemverilog
// In tb_top, connect to DUT internals
assign dut_if.i0_wen   = DUT.eh2_veer.dec.i0_wen_wb;
assign dut_if.i0_waddr = DUT.eh2_veer.dec.i0_waddr_wb;
assign dut_if.i0_wdata = DUT.eh2_veer.dec.i0_result_wb;
assign dut_if.i1_wen   = DUT.eh2_veer.dec.i1_wen_wb;
assign dut_if.i1_waddr = DUT.eh2_veer.dec.i1_waddr_wb;
assign dut_if.i1_wdata = DUT.eh2_veer.dec.i1_result_wb;
```

**Deliverables:**
- [ ] Trace monitor captures instruction retirements
- [ ] DUT probe interface provides register write visibility
- [ ] Trace CSV output matches existing `rtl_log_to_trace_csv.py` format

---

### Phase 3: Co-Simulation with QEMU (Weeks 6-8)

**Goal:** Implement DPI-based co-simulation with QEMU as reference model.

#### 3.3.1 Cosim Architecture Decision

**Option A: Spike-based (like Ibex)**
- Pros: Cycle-accurate, mature, proven in Ibex
- Cons: Requires Spike to support EH2's ISA extensions (Zba/Zbb/Zbc/Zbs + atomics + dual-thread)

**Option B: QEMU-based (reuse existing infrastructure)**
- Pros: Already working with EH2 in `eh2-verification`, supports full ISA
- Cons: QEMU is not instruction-accurate (snapshot-diff approach), harder to integrate as DPI

**Recommendation: Hybrid approach**
- Use QEMU as reference model for ISA verification (already proven)
- Build a lightweight DPI wrapper that:
  1. Loads the same binary into QEMU
  2. Runs QEMU in a separate thread
  3. Compares final architectural state (GPR + CSR) at test end
  4. For detailed per-instruction checking, use the existing offline trace comparison

#### 3.3.2 QEMU DPI Wrapper
**Files:**

1. **`/home/host/eh2-veri/dv/cosim/cosim.h`** - Abstract cosim interface
```cpp
class Cosim {
public:
  virtual ~Cosim() {}
  virtual void add_memory(uint32_t base_addr, size_t size) = 0;
  virtual bool backdoor_write_mem(uint32_t addr, size_t len, const uint8_t *data) = 0;
  virtual bool backdoor_read_mem(uint32_t addr, size_t len, uint8_t *data) = 0;
  virtual bool step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
                    bool sync_trap) = 0;
  virtual void set_mip(uint32_t mip) = 0;
  virtual void set_nmi(bool nmi) = 0;
  virtual void set_debug_req(bool debug_req) = 0;
  virtual const std::vector<std::string>& get_errors() = 0;
  virtual void clear_errors() = 0;
  virtual unsigned int get_insn_cnt() = 0;
};
```

2. **`/home/host/eh2-veri/dv/cosim/eh2_cosim.cc`** - QEMU-based implementation
   - Spawns QEMU process with `-d cpu` tracing
   - Parses QEMU output in real-time via pipe
   - Compares architectural state at each step

3. **`/home/host/eh2-veri/dv/cosim/cosim_dpi.cc`** - DPI-C wrappers
   - `riscv_cosim_init()`, `riscv_cosim_release()`
   - `riscv_cosim_step()`, `riscv_cosim_set_mip()`, etc.

#### 3.3.3 Cosim Scoreboard
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/common/eh2_cosim_agent/eh2_cosim_scoreboard.sv`

Adapted from Ibex's `ibex_cosim_scoreboard`:
- Receives trace items from `eh2_trace_monitor`
- Receives memory transactions from AXI4 agents
- Calls DPI to step reference model
- Compares PC, GPR writes, CSR writes
- Reports fatal on mismatch

#### 3.3.4 Binary Loading
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv`

```systemverilog
task run_phase(uvm_phase phase);
  // 1. Backdoor load binary into AXI4 memory model
  load_binary_to_mem(test_binary_path);

  // 2. Backdoor load binary into cosim memory
  cosim_agt.load_binary_to_mem(test_binary_path);

  // 3. Apply reset
  // 4. Wait for mailbox PASS/FAIL or timeout
endtask
```

**Deliverables:**
- [ ] QEMU DPI wrapper compiles
- [ ] Cosim scoreboard compares final GPR state
- [ ] hello_world test passes with cosim checking
- [ ] Basic directed tests pass (rv32i_add, rv32i_branch, etc.)

---

### Phase 4: Interrupt and Debug Agents (Weeks 9-11)

**Goal:** Enable interrupt and debug stimulus for comprehensive testing.

#### 3.4.1 Interrupt Agent
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/irq_if.sv`

```systemverilog
interface irq_if (input logic clk);
  logic [PIC_TOTAL_INT-1:0] extintsrc_req;  // 127 external interrupts
  logic [NUM_THREADS-1:0]   timer_int;
  logic [NUM_THREADS-1:0]   soft_int;
  logic                     nmi_int;

  clocking driver_cb @(negedge clk);
    output extintsrc_req, timer_int, soft_int, nmi_int;
  endclocking

  clocking monitor_cb @(posedge clk);
    input extintsrc_req, timer_int, soft_int, nmi_int;
  endclocking
endinterface
```

**Sequences:**
- `irq_raise_single_seq` - Raise single interrupt
- `irq_raise_multiple_seq` - Raise multiple random interrupts
- `irq_raise_nmi_seq` - Raise NMI
- `irq_nested_seq` - Nested interrupt testing

#### 3.4.2 JTAG Agent
**Files:**

1. **`jtag_intf.sv`** - JTAG interface
```systemverilog
interface jtag_intf (input logic clk);
  logic tck;
  logic tms;
  logic tdi;
  logic trst_n;
  logic tdo;

  clocking driver_cb @(posedge tck);
    output tms, tdi, trst_n;
    input  tdo;
  endclocking
endinterface
```

2. **`jtag_agent.sv`** - UVM agent
   - `jtag_driver.sv` - Drives JTAG TAP sequences
   - `jtag_monitor.sv` - Monitors JTAG transactions
   - `jtag_seq_item.sv` - Transaction item

3. **`jtag_seq_lib.sv`** - JTAG sequences
   - `jtag_reset_seq` - Reset JTAG TAP
   - `dmi_write_seq` - Write DMI register
   - `dmi_read_seq` - Read DMI register
   - `debug_halt_seq` - Halt core via DMCONTROL
   - `debug_resume_seq` - Resume core
   - `debug_step_seq` - Single-step
   - `debug_read_gpr_seq` - Read GPR via abstract command
   - `debug_write_gpr_seq` - Write GPR via abstract command

#### 3.4.3 Halt/Run Agent
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/`

- Drives `mpc_debug_halt_req`, `mpc_debug_run_req`, `mpc_reset_run_req`
- Drives `i_cpu_halt_req`, `i_cpu_run_req`
- Monitors `o_cpu_halt_ack`, `o_cpu_run_ack`, `o_cpu_halt_status`

**Deliverables:**
- [ ] Interrupt agent drives all 127 external interrupts
- [ ] JTAG agent can halt/resume core via DMI
- [ ] Debug abstract commands read/write GPRs
- [ ] Debug tests pass (riscv_debug_basic_test equivalent)

---

### Phase 5: riscv-dv Integration (Weeks 12-14)

**Goal:** Enable constrained-random test generation via riscv-dv.

#### 3.5.1 riscv-dv Target Configuration
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_riscv_core_setting.sv`

```systemverilog
// EH2 riscv-dv target configuration
parameter string ISA = "rv32imac_Zba_Zbb_Zbc_Zbs";
parameter bit[31:0] SIGNATURE_ADDR = 32'h8ffffffc;
parameter int NUM_HARTS = 1;  // or 2 for dual-thread

// Implemented CSRs
parameter int NUM_CSRS = 40;  // EH2 has more CSRs than Ibex
// ... list all EH2 CSRs
```

#### 3.5.2 ASM Program Generator Extension
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv`

Extends `riscv_asm_program_gen`:
- Customizes CSR write list for EH2
- Handles EH2-specific exception handler (mscause)
- Adds PIC initialization code
- DCCM/ICCM region awareness

#### 3.5.3 Test List
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`

```yaml
- test: riscv_arithmetic_basic_test
  description: "Basic arithmetic test"
  iterations: 5
  gen_test: riscv_instr_base_test
  rtl_test: core_eh2_base_test

- test: riscv_rand_instr_test
  description: "Random instruction test"
  iterations: 10
  gen_test: riscv_instr_base_test
  gen_opts: >
    +instr_cnt=10000
    +num_of_sub_program=5
    +directed_instr_0=riscv_int_numeric_corner_stream,4
  rtl_test: core_eh2_base_test

- test: riscv_interrupt_test
  description: "Interrupt test"
  iterations: 5
  gen_test: riscv_instr_base_test
  gen_opts: +enable_interrupt=1
  rtl_test: core_eh2_irq_test

- test: riscv_debug_test
  description: "Debug test"
  iterations: 5
  gen_test: riscv_instr_base_test
  gen_opts: +enable_debug=1
  rtl_test: core_eh2_debug_test

# ... more tests
```

#### 3.5.4 Build System Scripts
Adapt from Ibex's scripts:
- `metadata.py` - Regression metadata
- `compile_tb.py` - Testbench compilation
- `run_rtl.py` - RTL simulation execution
- `check_logs.py` - Log checking
- `collect_results.py` - Results collection

**Deliverables:**
- [ ] riscv-dv generates EH2-targeted random tests
- [ ] Random tests compile and run on RTL
- [ ] Basic regression (10 tests) passes
- [ ] Results reported in HTML/JUnit format

---

### Phase 6: Functional Coverage (Weeks 15-16)

**Goal:** Implement comprehensive functional coverage.

#### 3.6.1 Main Coverage Interface
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/fcov/core_eh2_fcov_if.sv`

Adapted from Ibex's `core_ibex_fcov_if.sv`, with EH2-specific additions:

**Covergroups:**
1. **`uarch_cg`** - Microarchitecture coverage
   - Instruction category (ALU, Mul, Div, Branch, Jump, Load, Store, CSR, Atomic, Bitmanip)
   - Dual-pipe coverage (i0 and i1 retiring simultaneously)
   - Pipeline stall types
   - Pipeline state (IF, ID, WB)

2. **`interrupt_cg`** - Interrupt coverage
   - Each of 127 external interrupts taken
   - Interrupt priority levels
   - Nested interrupts
   - PIC configuration coverage

3. **`debug_cg`** - Debug coverage
   - Debug entry sources (ebreak, trigger, haltreq)
   - Single-step coverage
   - Abstract command types
   - System bus access

4. **`memory_cg`** - Memory subsystem coverage
   - DCCM access patterns (read/write, different banks)
   - ICCM access patterns
   - ICache hit/miss
   - AXI4 burst types (FIXED, INCR, WRAP)
   - AXI4 response errors

5. **`csr_cg`** - CSR coverage
   - All EH2-specific CSRs accessed
   - WARL behavior
   - Veer-specific CSRs (mscause, meihap, etc.)

6. **`bitmanip_cg`** - Bitmanip extension coverage
   - Zba instructions (sh1add, sh2add, sh3add, zext.w)
   - Zbb instructions (clz, ctz, cpop, max, min, etc.)
   - Zbc instructions (clmul, clmulh, clmulr)
   - Zbs instructions (bclr, bext, binv, bset)

#### 3.6.2 Coverage Bind File
**File:** `/home/host/eh2-veri/dv/uvm/core_eh2/fcov/core_eh2_fcov_bind.sv`

Binds `core_eh2_fcov_if` to the DUT:
```systemverilog
bind eh2_veer core_eh2_fcov_if u_fcov_bind (
  .clk     (clk),
  .rst_n   (rst_l),
  .i0_valid(ifu_i0_valid),
  .i1_valid(ifu_i1_valid),
  .i0_instr(ifu_i0_instr),
  .i1_instr(ifu_i1_instr),
  // ... more bindings
);
```

**Deliverables:**
- [ ] Functional coverage compiles
- [ ] Coverage collected in regression
- [ ] Coverage reports generated

---

### Phase 7: Regression and CI (Weeks 17-18)

**Goal:** Establish automated regression flow.

#### 3.7.1 Regression Testlists
- `testlist_smoke.yaml` - 10 tests, ~5 min
- `testlist_nightly.yaml` - 50 tests, ~2 hours
- `testlist_weekly.yaml` - 200 tests, ~12 hours

#### 3.7.2 Makefile Targets
```makefile
smoke:      # Run smoke regression
nightly:    # Run nightly regression
weekly:     # Run weekly regression
cov:        # Collect and merge coverage
report:     # Generate HTML/JUnit reports
clean:      # Clean build artifacts
```

#### 3.7.3 CI Integration
- `ci/smoke.sh` - Smoke CI script
- `ci/nightly.sh` - Nightly CI script
- Results uploaded to artifact storage

**Deliverables:**
- [ ] Smoke regression passes (10/10)
- [ ] Nightly regression passes (>90%)
- [ ] Coverage >80% on key covergroups
- [ ] CI pipeline runs automatically

---

## 4. Key Technical Challenges and Solutions

### 4.1 Challenge: No Standard RVFI on EH2

**Problem:** EH2's trace ports only provide PC + instruction + exception. No register write data, memory data, or CSR values.

**Solution:** Two-pronged approach:
1. **DUT probing:** Reach into design internals via hierarchical references to capture register writeback data (same approach as existing `tb_top.sv`)
2. **AXI4 monitoring:** Capture all memory transactions from AXI4 monitors
3. **Final-state comparison:** For tests where per-instruction checking is not critical, compare only final architectural state (GPR + CSR) against QEMU

### 4.2 Challenge: AXI4 Bus Complexity

**Problem:** EH2 has 4 AXI4 ports (IFU master, LSU master, SB master, DMA slave) with full AXI4 protocol including bursts.

**Solution:**
1. Use parameterized AXI4 agent that handles all AXI4 features
2. For IFU port: simple single-beat reads (instruction fetches are always single-beat)
3. For LSU port: support INCR bursts (cache line fills) and single-beat accesses
4. For SB port: simple debug accesses
5. For DMA port: master agent that drives DMA transactions

### 4.3 Challenge: Tightly Coupled Memories

**Problem:** DCCM and ICCM are internal to the wrapper and cannot be directly driven from AXI4 agents.

**Solution:**
1. DCCM/ICCM are already instantiated inside `eh2_mem.sv` - they are part of the DUT
2. AXI4 agents only need to handle external memory (addresses outside DCCM/ICCM/IC regions)
3. For test loading: use backdoor hierarchical access to slam DCCM/ICCM contents (same as existing `tb_top.sv`)
4. For external memory: AXI4 response agent provides behavioral memory

### 4.4 Challenge: Dual-Thread Support

**Problem:** EH2 can be configured with NUM_THREADS=2, but the trace interface packs both threads' data together.

**Solution:**
1. Default to NUM_THREADS=1 for initial implementation
2. When NUM_THREADS=2, the trace monitor must handle per-thread retirement tracking
3. Cosim must run two QEMU instances (one per hart) or use multi-hart Spike

### 4.5 Challenge: QEMU Integration as DPI

**Problem:** QEMU is a full system emulator, not a library. Hard to call as DPI.

**Solution:**
1. **Phase 1 (initial):** Use offline comparison - run QEMU separately, compare traces post-simulation (reuse existing `trace_compare.py`)
2. **Phase 2 (advanced):** Build a lightweight QEMU wrapper that:
   - Runs QEMU in a separate process
   - Communicates via shared memory or pipes
   - Provides step-by-step architectural state

---

## 5. File-by-File Adaptation Guide

### 5.1 Files Directly Reusable from Ibex

| Ibex File | Reuse Strategy |
|-----------|---------------|
| `dv/cosim/cosim.h` | Reuse as-is (abstract interface) |
| `dv/cosim/cosim_dpi.cc` | Reuse as-is (DPI wrappers) |
| `dv/cosim/cosim_dpi.h` | Reuse as-is |
| `dv/cosim/cosim_dpi.svh` | Reuse as-is |
| `dv/uvm/core_ibex/common/irq_agent/*` | Adapt: change signal widths |
| `dv/uvm/core_ibex/scripts/metadata.py` | Adapt: change paths/names |
| `dv/uvm/core_ibex/scripts/collect_results.py` | Reuse as-is |
| `dv/uvm/core_ibex/tests/core_ibex_report_server.sv` | Adapt: rename |
| `vendor/google_riscv-dv/*` | Reuse as-is (symlink) |

### 5.2 Files Requiring Major Rewrite

| Ibex File | What Changes |
|-----------|-------------|
| `dv/uvm/core_ibex/tb/core_ibex_tb_top.sv` | Complete rewrite: AXI4 ports, JTAG, PIC, DCCM/ICCM |
| `dv/uvm/core_ibex/common/ibex_mem_intf_agent/*` | Replace with AXI4 agent |
| `dv/uvm/core_ibex/common/ibex_cosim_agent/*` | Rewrite: QEMU instead of Spike, trace instead of RVFI |
| `dv/uvm/core_ibex/env/core_ibex_dut_probe_if.sv` | Rewrite: EH2 internal signals |
| `dv/uvm/core_ibex/fcov/core_ibex_fcov_if.sv` | Rewrite: EH2-specific coverage |
| `dv/uvm/core_ibex/riscv_dv_extension/*` | Rewrite: EH2 ISA and CSRs |
| `dv/cosim/spike_cosim.cc` | Replace with QEMU-based cosim |

### 5.3 Files from Existing eh2-verification to Reuse

| File | Reuse Strategy |
|------|---------------|
| `common/eh2_trace_csv.py` | Reuse for offline trace comparison |
| `common/trace_compare.py` | Reuse for offline comparison |
| `common/rtl_log_to_trace_csv.py` | Reuse for RTL log parsing |
| `common/qemu_log_to_trace_csv.py` | Reuse for QEMU log parsing |
| `common/eh2_selfcheck.h` | Reuse for test infrastructure |
| `common/eh2_crt0.S` | Reuse for test startup |
| `common/link.ld` | Reuse for linker script |
| `common/functional_coverage.py` | Reference for SV covergroup design |
| `01-directed/*.S` | Reuse as directed tests |
| `signoff/policy.yaml` | Reuse for signoff framework |

---

## 6. Simulator Configuration

### 6.1 VCS Compilation Command

```bash
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
  +define+RV_BUILD_AXI4=1 \
  +define+UVM_NO_DEPRECATED \
  -f rtl/design/eh2_veer_wrapper.f \
  -f dv/uvm/core_eh2/core_eh2_dv.f \
  -f dv/cosim/cosim_dpi.f \
  -LDFLAGS "-lriscv-riscv -lriscv-disasm" \
  -o simv
```

### 6.2 Simulation Command

```bash
./simv +UVM_TESTNAME=core_eh2_base_test \
  +binary=test.hex \
  +signature_addr=0x8ffffffc \
  +timeout_s=300 \
  +UVM_VERBOSITY=UVM_LOW
```

---

## 7. Verification Plan Summary

### 7.1 Test Categories

| Category | Tests | Source | Priority |
|----------|-------|--------|----------|
| Directed ISA | 20 | Existing eh2-verification | P0 |
| riscv-compliance | 85 | riscv-compliance suite | P0 |
| Random arithmetic | 10 | riscv-dv | P1 |
| Random memory | 10 | riscv-dv | P1 |
| Interrupt | 10 | riscv-dv + directed | P1 |
| Debug | 10 | riscv-dv + directed | P1 |
| Bitmanip | 10 | riscv-dv | P1 |
| Stress | 5 | riscv-dv | P2 |
| Benchmark | 3 | CoreMark, Dhrystone | P2 |

### 7.2 Coverage Goals

| Covergroup | Target |
|------------|--------|
| Instruction category | 100% |
| Exception causes | 100% |
| Interrupt types | 100% |
| CSR operations | 90% |
| Debug entry sources | 100% |
| AXI4 burst types | 100% |
| Bitmanip instructions | 80% |
| Dual-pipe retirement | 90% |

### 7.3 Sign-off Criteria

1. All directed tests pass with cosim checking
2. riscv-compliance suite passes (signature match)
3. Random regression >95% pass rate
4. Functional coverage meets targets
5. No outstanding UVM_FATAL errors
6. Clean sign-off report generated

---

## 8. Timeline Summary

| Phase | Duration | Key Milestone |
|-------|----------|---------------|
| Phase 0: Infrastructure | Week 1 | RTL compiles |
| Phase 1: AXI4 Memory | Weeks 2-3 | hello_world passes |
| Phase 2: Trace Monitor | Weeks 4-5 | Instruction tracking works |
| Phase 3: Cosim | Weeks 6-8 | QEMU cosim passes |
| Phase 4: IRQ/Debug | Weeks 9-11 | Interrupt and debug tests pass |
| Phase 5: riscv-dv | Weeks 12-14 | Random tests run |
| Phase 6: Coverage | Weeks 15-16 | Coverage collected |
| Phase 7: Regression | Weeks 17-18 | CI pipeline runs |

**Total estimated duration: 18 weeks (4.5 months)**

---

## 9. Appendix

### 9.1 Key Signal Mappings

#### EH2 Wrapper to UVM Agent Connections

```
eh2_veer_wrapper port        -> UVM Agent / Interface
─────────────────────────────────────────────────────
clk                          -> clk_rst_if.clk
rst_l                        -> clk_rst_if.rst_n (inverted)
rst_vec[31:1]                -> tied to 0x80000000
nmi_int                      -> irq_if.nmi_int
nmi_vec[31:1]                -> tied to config value

ifu_axi_aw*                  -> ifu_axi_vif (response agent)
ifu_axi_w*                   -> ifu_axi_vif
ifu_axi_b*                   -> ifu_axi_vif
ifu_axi_ar*                  -> ifu_axi_vif
ifu_axi_r*                   -> ifu_axi_vif

lsu_axi_aw*                  -> lsu_axi_vif (response agent)
lsu_axi_w*                   -> lsu_axi_vif
lsu_axi_b*                   -> lsu_axi_vif
lsu_axi_ar*                  -> lsu_axi_vif
lsu_axi_r*                   -> lsu_axi_vif

sb_axi_aw*                   -> sb_axi_vif (response agent)
sb_axi_w*                    -> sb_axi_vif
sb_axi_b*                    -> sb_axi_vif
sb_axi_ar*                   -> sb_axi_vif
sb_axi_r*                    -> sb_axi_vif

dma_axi_aw*                  -> dma_axi_vif (master agent)
dma_axi_w*                   -> dma_axi_vif
dma_axi_b*                   -> dma_axi_vif
dma_axi_ar*                  -> dma_axi_vif
dma_axi_r*                   -> dma_axi_vif

jtag_tck/tms/tdi/trst_n/tdo -> jtag_vif

extintsrc_req[127:1]         -> irq_if.extintsrc_req
timer_int                    -> irq_if.timer_int
soft_int                     -> irq_if.soft_int

mpc_debug_halt_req/run_req   -> halt_run_vif
i_cpu_halt_req/run_req       -> halt_run_vif

trace_rv_i_*                 -> trace_if (monitor only)
```

### 9.2 Memory Map

```
Address Range              | Region
───────────────────────────┼────────
0x00000000 - 0xDFFFFFFF    | External memory (AXI4 response agent)
0xE0000000 - 0xEFFFFFFF    | ICCM (internal, backdoor load)
0xF0000000 - 0xF003FFFF    | PIC registers (internal)
0xF0040000 - 0xF007FFFF    | DCCM (internal, backdoor load)
0xF0080000 - 0xF00BFFFF    | DMA registers (internal)
0xF00C0000 - 0xF00FFFFF    | PIC memory (internal)
0xF0100000 - 0xFFFFFFFF    | External memory (AXI4 response agent)
```

### 9.3 Environment Setup

```bash
# Source environment
export EH2_VERIF_ROOT=/home/host/eh2-veri
export RV_ROOT=/home/host/Cores-VeeR-EH2
export GCC_PREFIX=/home/host/gcc-riscv64-unknown-elf
export QEMU_BIN=/usr/bin/qemu-system-riscv32

# Tool paths
export VCS_HOME=/path/to/vcs
export VERDI_HOME=/path/to/verdi

# Add to PATH
export PATH=$GCC_PREFIX/bin:$PATH
```

---

*End of Implementation Plan*
