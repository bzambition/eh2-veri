# EH2 UVM Verification Platform Architecture

## 1. Platform Overview

The EH2 UVM Verification Platform is a UVM-based functional verification environment for the VeeR EH2 RISC-V processor core. It is designed following the lowRISC Ibex UVM DV methodology, adapted for EH2's unique architecture.

### 1.1 Verification Goals

1. **ISA Compliance**: Verify RV32IMAC + Zba/Zbb/Zbc/Zbs instructions
2. **Pipeline Correctness**: Verify dual-issue pipeline with hazard handling
3. **Memory Subsystem**: Verify DCCM, ICCM, ICache, and AXI4 bus
4. **Interrupt Handling**: Verify PIC with 127 interrupt sources
5. **Debug Functionality**: Verify JTAG/DMI debug interface
6. **Multi-threading**: Verify dual-thread operation (future)

### 1.2 Verification Methodology

```
Test Generation (riscv-dv)
        |
        v
Test Compilation (GCC)
        |
        v
RTL Simulation (VCS)  <------>  Reference Model (QEMU)
        |                              |
        v                              v
Trace Collection              Trace Collection
        |                              |
        +-------> Comparison <---------+
                    |
                    v
              Pass/Fail Report
```

## 2. UVM Architecture

### 2.1 Component Hierarchy

```
core_eh2_tb_top
├── clk_rst_if                          # Clock and reset
├── axi4_intf ifu_axi_vif              # IFU AXI4
├── axi4_intf lsu_axi_vif              # LSU AXI4
├── axi4_intf sb_axi_vif               # SB AXI4
├── axi4_intf dma_axi_vif              # DMA AXI4
├── jtag_intf jtag_vif                 # JTAG
├── irq_if irq_vif                     # Interrupts
├── core_eh2_dut_probe_if dut_if       # DUT probes
├── core_eh2_trace_if trace_if         # Trace
├── halt_run_if halt_run_vif           # Halt/run
│
└── eh2_veer_wrapper DUT
    ├── dmi_wrapper
    ├── eh2_veer
    └── eh2_mem

core_eh2_env
├── axi4_response_agent ifu_axi_agent
├── axi4_response_agent lsu_axi_agent
├── axi4_response_agent sb_axi_agent
├── axi4_master_agent dma_axi_agent
├── jtag_agent jtag_agt
├── irq_request_agent irq_agt
├── halt_run_agent halt_run_agt
├── eh2_cosim_agent cosim_agt
├── core_eh2_vseqr vseqr
├── core_eh2_scoreboard scoreboard
└── core_eh2_env_cfg cfg
```

### 2.2 Interface Summary

| Interface | Direction | Description |
|-----------|-----------|-------------|
| `clk_rst_if` | TB -> DUT | Clock (100MHz) and active-low reset |
| `axi4_intf` (IFU) | DUT -> TB | Instruction fetch AXI4 master |
| `axi4_intf` (LSU) | DUT -> TB | Load/store AXI4 master |
| `axi4_intf` (SB) | DUT -> TB | Debug system bus AXI4 master |
| `axi4_intf` (DMA) | TB -> DUT | DMA AXI4 slave |
| `jtag_intf` | TB -> DUT | JTAG TAP signals |
| `irq_if` | TB -> DUT | 127 external + timer + soft interrupts |
| `halt_run_if` | TB -> DUT | MPC halt/run control |
| `core_eh2_trace_if` | DUT -> TB | Instruction retirement trace |
| `core_eh2_dut_probe_if` | DUT -> TB | Internal pipeline signals |

## 3. Bus Architecture

### 3.1 AXI4 Configuration

| Port | Type | ID Width | Data Width | Description |
|------|------|----------|------------|-------------|
| IFU | Master | 4 | 64-bit | Instruction fetch |
| LSU | Master | 4 | 64-bit | Data load/store |
| SB | Master | 1 | 64-bit | Debug system bus |
| DMA | Slave | 1 | 64-bit | External DMA |

### 3.2 Memory Map

```
0x0000_0000 ┬───────────────────── External Memory (AXI4 agent)
             │
0xEE00_0000 ┬───────────────────── ICCM (64KB, internal)
0xEE01_0000 ┘
             │
0xF000_0000 ┬───────────────────── PIC Registers
0xF004_0000 ┬───────────────────── DCCM (64KB, internal)
0xF008_0000 ┘
             │
0xFFFF_FFFF ┘
```

## 4. Co-simulation Architecture

### 4.1 Trace-based Comparison

Since EH2 does not have standard RVFI, we use a two-level approach:

**Level 1: Trace Monitor (Online)**
- Monitors `trace_rv_i_*` ports for instruction retirement
- Captures PC, instruction, exception per pipe
- Maintains instruction order counter

**Level 2: DUT Probing (Online)**
- Probes internal signals for register writeback
- Captures `i0_result_wb`, `i1_result_wb`, `i0_waddr_wb`, `i1_waddr_wb`
- Links to trace items via pipeline stage tracking

**Level 3: QEMU Comparison (Offline)**
- Run QEMU with same binary
- Compare final architectural state (GPR + CSR)
- Or compare per-instruction traces (post-processing)

### 4.2 DPI Interface

```c
// Cosim abstract interface
class Cosim {
  virtual void add_memory(uint32_t base, size_t size) = 0;
  virtual bool step(uint32_t rd, uint32_t rd_data, uint32_t pc, bool trap) = 0;
  virtual void set_mip(uint32_t mip) = 0;
  virtual void set_nmi(bool nmi) = 0;
  virtual void set_debug_req(bool req) = 0;
  virtual const vector<string>& get_errors() = 0;
};
```

## 5. Functional Coverage Model

### 5.1 Coverage Groups

| Group | Coverage Points | Target |
|-------|----------------|--------|
| `instr_cg` | Instruction categories (ALU/Mul/Div/Branch/Load/Store/CSR/Atomic/Bitmanip) | 100% |
| `pipeline_cg` | Dual-pipe retirement, stalls, hazards | 90% |
| `interrupt_cg` | All 127 interrupts, priority levels, nesting | 100% |
| `debug_cg` | Entry sources, single-step, abstract commands | 100% |
| `memory_cg` | DCCM/ICCM/ICache access patterns, AXI4 bursts | 90% |
| `csr_cg` | All EH2 CSRs, WARL behavior | 90% |
| `bitmanip_cg` | Zba/Zbb/Zbc/Zbs instructions | 80% |

### 5.2 Coverage Collection

- Simulator-native coverage (VCS -cm line+cond+fsm+tgl)
- Merge with URG for HTML reports
- Export to XML for CI integration

## 6. Test Flow

### 6.1 Test Execution

```
make smoke TEST=riscv_arithmetic_basic_test SEED=1

1. Generate test assembly (riscv-dv)
2. Compile to ELF (GCC)
3. Convert to HEX (objcopy)
4. Compile testbench (VCS)
5. Run simulation
6. Check logs (UVM_FATAL, timeout)
7. Compare traces (if cosim enabled)
8. Generate report
```

### 6.2 Regression

```
make nightly          # 50 tests, ~2 hours
make weekly           # 200 tests, ~12 hours
make cov              # Collect coverage
make report           # Generate HTML/JUnit
```
