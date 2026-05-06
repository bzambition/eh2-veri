# Co-simulation Correctness Analysis

**Date:** 2026-05-04
**Scope:** Spike-based co-simulation scoreboard (`eh2_cosim_scoreboard`) and its full data path
**Status:** Analysis complete, cosim correctness NOT yet proven by simulation

---

## 1. Current Cosim Data Path

The co-simulation system compares each DUT-retired instruction against the Spike ISS in lockstep. The data flows through three independent channels that converge in the scoreboard.

### 1.1 Channel Overview

```
RTL (eh2_dec.sv)                     UVM Monitors                    Scoreboard
─────────────────                    ─────────────                   ──────────

trace_rv_trace_pkt[i]                eh2_trace_monitor
  ├─ i0 insn/pc/valid ──posedge──►  ├─ i0 item ──ap.write()──┐
  └─ i1 insn/pc/valid ────────────►  └─ i1 item ──ap.write()──┤
                                    │                          │
                                    │              TLM FIFO ◄──┘
                                    │                          │
                                    │              trace_fifo.get() ──► compare_instruction()
                                    │                          │         ├─ dequeue wb from pending_wb_q[slot]
                                    │                          │         ├─ set_debug_req / set_nmi / set_mip
                                    │                          │         ├─ set_mcycle
                                    │                          │         └─ step() ──► Spike
                                    │
wb_valid/wb_dest/wb_data            eh2_dut_probe_monitor
  ├─ slot 0 wb ──── posedge ──────► ├─ wb item 0 ──ap.write()──┐
  └─ slot 1 wb ────────────────────► └─ wb item 1 ──ap.write()──┤
                                    │                            │
                                    │              dut_probe_fifo.get()
                                    │                            │
                                    │              run_cosim_probe() ──► pending_wb_q[slot].push_back()
                                    │
mip/nmi/debug_req/mcycle            (sampled by trace_monitor)
  ── posedge ──────────────────────► populate_cosim_state(txn)

LSU AXI4 monitor                    axi4_agent monitor
  ── transaction complete ──────────► lsu_axi_fifo ──────────────► notify_memory_access()
```

### 1.2 Trace Channel

Source: `eh2_dec.sv` generates `trace_rv_trace_pkt` (lines 1001-1013).

| Signal | Encoding | Description |
|--------|----------|-------------|
| `trace_rv_i_insn_ip` | `{i1_insn[31:0], i0_insn[31:0]}` | Packed instructions |
| `trace_rv_i_address_ip` | `{i1_pc[31:1], 1'b0, i0_pc[31:1], 1'b0}` | Packed PCs |
| `trace_rv_i_valid_ip` | `{i1_valid, i0_valid}` | Per-pipe valid |
| `trace_rv_i_exception_ip` | `{i1_exc_valid, i0_exc_valid}` | Per-pipe exception |
| `trace_rv_i_ecause_ip` | `dec_tlu_exc_cause_wb1[4:0]` | **Replicated** for both pipes |
| `trace_rv_i_interrupt_ip` | `{1'b0, dec_tlu_int_valid_wb1}` | Interrupt flag (i0 only) |

Monitor: `eh2_trace_monitor` (common/trace_agent/eh2_trace_monitor.sv)

### 1.3 Probe Channel

Source: `core_eh2_tb_top.sv` hierarchical references (lines 892-914).

| Signal | Source | Qualification |
|--------|--------|---------------|
| `wb_valid[0]` | `wbd.i0v & ~kill_writeb & ~i0div & ~load_kill` | Kill/div/load-kill excluded |
| `wb_valid[1]` | `wbd.i1v & ~kill_writeb & ~load_kill` | Kill/load-kill excluded |
| `wb_dest` | `{wbd.i1rd, wbd.i0rd}` | Destination register |
| `wb_data` | `{i1_result_wb, i0_result_wb}` | Writeback data |
| `wb_suppress` | `{dec_tlu_i1_kill_writeb_wb, dec_tlu_i0_kill_writeb_wb}` | Suppressed by interrupt/debug |

Monitor: `eh2_dut_probe_monitor` (common/trace_agent/eh2_dut_probe_monitor.sv)

### 1.4 Memory Channel

Source: LSU AXI4 monitor (passive `axi4_agent`).

The scoreboard calls `riscv_cosim_notify_dside_access()` for each AXI4 beat. Spike's `mmio_load`/`mmio_store` then checks against the `pending_dside_accesses` queue.

### 1.5 Scoreboard Consumption

File: `eh2_cosim_scoreboard.sv` (common/cosim_agent/eh2_cosim_scoreboard.sv)

Three parallel tasks consume the channels:

| Task | FIFO | Action |
|------|------|--------|
| `run_cosim_trace()` | `trace_fifo` | Calls `compare_instruction()` for each trace item |
| `run_cosim_probe()` | `dut_probe_fifo` | Enqueues writeback into `pending_wb_q[slot]` |
| `run_cosim_dmem()` | `lsu_axi_fifo` | Calls `notify_memory_access()` |

A fourth task `run_reset_monitor()` watches for reset and flushes all state.

---

## 2. i0/i1 Retire Item Order

### 2.1 RTL Guarantee

Both i0 and i1 valid bits are set simultaneously in the same combinational assignment (eh2_dec.sv:1004-1007):

```systemverilog
assign trace_rv_trace_pkt[i].trace_rv_i_valid_ip = {
    dec_tlu_i1_valid_wb1[i] | dec_tlu_i1_exc_valid_wb1[i],         // bit[1] = i1
    dec_tlu_int_valid_wb1[i] | dec_tlu_i0_valid_wb1[i] | dec_tlu_i0_exc_valid_wb1[i]  // bit[0] = i0
};
```

Both bits appear on the same clock edge. The RTL does not guarantee any ordering between i0 and i1 retirement -- they retire simultaneously.

### 2.2 Monitor Guarantee

The trace monitor (eh2_trace_monitor.sv:83-128) checks i0 before i1 within a single `forever` iteration:

```systemverilog
@(posedge vif.clk iff vif.rst_n);
if (vif.t0_i0_valid) begin ... ap.write(txn); end   // i0 first
if (vif.t0_i1_valid) begin ... ap.write(txn); end   // i1 second
```

Both `ap.write()` calls happen in the same simulation timestep. i0 always enters the analysis port before i1.

### 2.3 FIFO Ordering

The TLM analysis FIFO is a SystemVerilog queue (FIFO semantics). Items written first are retrieved first. Since i0 is written before i1, `trace_fifo.get()` returns i0 before i1.

### 2.4 Verdict

**i0 always reaches `compare_instruction()` before i1. Program order within a cycle is preserved.**

---

## 3. Scoreboard Consumption Order

### 3.1 The Synchronization Problem

Both `eh2_trace_monitor` and `eh2_dut_probe_monitor` fire on the same `posedge clk`. They push items to separate FIFOs (`trace_fifo` and `dut_probe_fifo`). The scoreboard consumes from both FIFOs in separate parallel tasks.

The concern: when `run_cosim_trace()` calls `compare_instruction()`, is the corresponding probe writeback already in `pending_wb_q[slot]`?

### 3.2 The #0 Delay Mechanism

```systemverilog
task run_cosim_trace();
  forever begin
    trace_fifo.get(trace_item);
    #0;  // Yield to run_cosim_probe
    compare_instruction(trace_item);
  end
endtask
```

The `#0` delay yields control within the same simulation timestep. UVM's simulation cycle within a timestep:

1. **Active region:** Both monitors fire. `ap.write()` pushes items into TLM FIFOs (non-blocking queue push).
2. **#0 in run_cosim_trace:** Yields control. The SystemVerilog scheduler resumes other ready processes.
3. **run_cosim_probe:** Its `dut_probe_fifo.get()` returns because data is available. It calls `push_back()` on `pending_wb_q[slot]`.
4. **run_cosim_trace resumes:** Calls `compare_instruction()`. Probe data is now in the queue.

### 3.3 Why This Works

- TLM `ap.write()` is a non-blocking queue push. It completes in the Active region.
- TLM `get()` is a blocking task that suspends until data is available. Since data was pushed in Active, `get()` returns immediately when resumed.
- The `#0` delay ensures `run_cosim_probe` runs before `compare_instruction` for the same cycle's data.

### 3.4 Edge Case: Multiple Writebacks Per Slot Per Cycle

If both `wb_valid[0]` and a non-block load `nb_load_wen` fire in the same cycle for slot 0, two probe items are pushed to `pending_wb_q[0]`. The trace monitor would only produce one i0 item. The scoreboard would consume one writeback, leaving a stale entry in the queue.

**Current handling:** The `nb_load_wen` probe item has `slot=0` hardcoded (eh2_dut_probe_monitor.sv:112). This could cause a mismatch with the next i0 instruction that doesn't write a register.

### 3.5 Verdict

**Ordering is correct for the normal case. The #0 delay ensures probe data is available before trace consumption. Edge cases involving non-block loads need verification.**

---

## 4. Spike Step Order

### 4.1 Notification Sequence

For each instruction, `compare_instruction()` calls Spike in this order (matching Ibex):

```
1. set_debug_req(item.debug_req)    // Highest priority
2. set_nmi(item.nmi)                // NMI mode
3. set_nmi_int(item.nmi_int)        // NMI interrupt pending
4. set_mip(prev_mip, item.mip)      // MIP pre/post value
5. set_mcycle(item.mcycle)          // Cycle counter
6. set_iside_error(pc)              // If instruction access fault
7. step(write_reg, write_reg_data, pc, sync_trap, suppress)
```

### 4.2 Dual-Issue Step Sequence

When i0 and i1 retire in the same cycle:

```
Cycle N:
  i0: set_mip(prev_mip_old, mip_new) → step(i0)   // prev_mip updated to mip_new
  i1: set_mip(mip_new, mip_new)       → step(i1)   // pre==post, no re-trigger
```

After i0's step, `prev_mip` is updated to `item.mip`. Since i1 has the same `item.mip`, `set_mip` is effectively a no-op for i1. This is correct because any interrupt triggered by the MIP change should only be taken once (by i0, which is first in program order).

### 4.3 Interrupt Handling Between i0 and i1

If an interrupt arrives and i0 takes it:
- RTL: i1 is killed (valid=0). Trace monitor produces only i0 item.
- Spike: Steps once for i0, takes interrupt. Correct.

If an interrupt arrives and i1 takes it (i0 completes normally):
- RTL: i0 valid=1 (no exception), i1 valid=1 (interrupt=1).
- Trace monitor: Produces two items. i0 has interrupt=0, i1 has interrupt=1.
- Spike: Steps for i0 (normal), then steps for i1 (interrupt).
- Issue: `ecause` is shared between i0 and i1 in RTL. i0 gets the interrupt's ecause even though i0 didn't have an exception. But i0's `exception` bit is 0, so `sync_trap=0` and ecause is ignored.

### 4.4 Verdict

**Step ordering is correct for normal execution. The shared ecause signal is protected by per-pipe exception valid bits.**

---

## 5. Risk Summary

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| RISK-1 | **HIGH** | Spike does not model EH2 custom CSRs | Unmitigated |
| RISK-2 | **MEDIUM** | 64-bit AXI4 data truncated to 32-bit | Unmitigated |
| RISK-3 | **MEDIUM** | Writeback probe and trace item alignment fragile | Partially mitigated by #0 delay |
| RISK-4 | **BLOCKING** | NUM_THREADS=2 cannot be verified with current cosim | Not addressed |
| RISK-5 | **LOW** | Non-block load writeback may desync probe queue | Unverified |
| RISK-6 | **LOW** | Interrupt state sampled per-item, not per-cycle | Correct by RTL design |

---

## 6. HIGH Risk: EH2 Custom CSRs vs Spike

### 6.1 Problem

The `fixup_csr()` function in `spike_cosim.cc` (line 687-724) only handles 4 CSRs:

| CSR | Fixup Applied |
|-----|---------------|
| `mstatus` | Mask to M-mode bits only, force MPP=M |
| `misa` | Hardwire to RV32IMAC (0x40001104) |
| `mtvec` | MODE=0, 256-byte aligned BASE |
| `mcause` | WARL: keep bit[31], mask lower bits |

EH2 implements many more CSRs that Spike does not natively support:

| CSR | Description | Risk |
|-----|-------------|------|
| `mscause` (0x7FF) | Secondary exception cause | Spike doesn't have this CSR |
| `mrac` (0x7C0) | Region access control | Spike doesn't model memory regions |
| `mfdc` (0x7C1) | Fetch/DCCM control | No Spike equivalent |
| `mcgc` (0x7F8) | Clock gating control | No Spike equivalent |
| `mpmc` (0x7FC) | Power management | No Spike equivalent |
| `mcpc` (0x7F3) | Core pause control | No Spike equivalent |
| `dmst` (0x7C4) | Debug module status | No Spike equivalent |
| `mfdht` (0x7C6) | Fetch halt threshold | No Spike equivalent |
| `mfdhs` (0x7C7) | Fetch halt status | No Spike equivalent |
| `mhartstart` (0x7E0) | Hart start (multi-thread) | No Spike equivalent |
| `mnmipdel` (0x7E2) | NMI delay | No Spike equivalent |
| `meivt` (0xBC0) | PIC: interrupt vector table | No Spike equivalent |
| `meipt` (0xBC4) | PIC: interrupt priority threshold | No Spike equivalent |
| `meicidpl` (0xBC5) | PIC: interrupt current ID priority level | No Spike equivalent |
| `meihap` (0xFC0) | PIC: highest active interrupt priority | No Spike equivalent |
| `meicpct` (0xBC6) | PIC: claim/priority threshold | No Spike equivalent |

### 6.2 Impact

The riscv-dv extension includes `eh2_csr_access_stream` (eh2_directed_instr_lib.sv) that generates random CSRRW/CSRRS/CSRRC on 18 EH2 custom CSRs. Any test using this stream will cause Spike to either:
- Fail to recognize the CSR address and report an error
- Silently ignore the write, causing state divergence on subsequent reads

Tests affected:
- `riscv_csr_test` (testlist.yaml)
- Any test with `+directed_instr_3=eh2_csr_access_stream,4`
- `riscv_csr_hazard_test`
- `riscv_exception_stream_test` (touches mscause)

### 6.3 Mitigation Options

| Option | Description | Tradeoff |
|--------|-------------|----------|
| **(A) Full fixup** | Add fixup_csr() cases for all EH2 CSRs | Most correct, significant effort, must match RTL WARL behavior |
| **(B) Read-only suppression** | Make unrecognized CSRs read-only in Spike | Prevents errors, but doesn't verify CSR write behavior |
| **(C) Per-test cosim disable** | Add `cosim: disabled` flag to testlist for affected tests | Pragmatic short-term, delays full verification |
| **(D) Spike extension** | Add EH2 CSR definitions to Spike | Correct long-term, requires Spike source modification |

**Recommendation:** (C) for current phase, (A) for sign-off.

---

## 7. MEDIUM Risk: 64-bit AXI4 Data Handling

### 7.1 Problem

EH2's data bus is 64-bit (`RV_EXT_DATAWIDTH=64`). The cosim notification truncates to 32-bit:

```systemverilog
// eh2_cosim_scoreboard.sv:237
riscv_cosim_notify_dside_access(cosim_handle,
  1,                              // store
  int'(beat_data[31:0]),          // Only lower 32 bits!
  int'(beat_addr),
  int'({4'b0, beat_strb[3:0]}),  // Only lower 4 bits of strobe!
  ...);
```

### 7.2 When 64-bit Data Matters

- RV32IMAC instructions produce at most 32-bit loads/stores (LW/SW, LH/SH, LB/SB, and atomic LR/SC).
- Cache line fills (ICache, DCCM) may produce 64-bit AXI4 bursts, but these are transparent to the instruction-level cosim.
- The concern is whether a 32-bit instruction load/store could appear as a 64-bit transaction on the AXI4 bus due to ECC or alignment.

### 7.3 Impact

If the DUT performs a 64-bit bus transaction for a 32-bit instruction access:
- The AXI4 monitor captures the full 64-bit transaction.
- The scoreboard reports only the lower 32 bits to Spike.
- Spike's `mmio_load`/`mmio_store` expects the full data.
- Mismatch on data comparison.

### 7.4 Mitigation

1. Verify that RV32IMAC loads/stores always produce 32-bit or narrower AXI4 transactions.
2. If 64-bit bursts occur for cache fills, filter them out (only notify Spike for instruction-level accesses).
3. If 32-bit accesses are split into 64-bit bus transactions, handle both halves.

---

## 8. MEDIUM Risk: Writeback Probe and Trace Item Alignment

### 8.1 Problem

The trace monitor and probe monitor use **different signal qualifications** to determine valid instructions:

| Monitor | Signal Source | Qualification |
|---------|-------------|---------------|
| Trace | `dec_tlu_i0_valid_wb1` | Includes interrupt/exception valid |
| Probe | `wbd.i0v & ~kill_writeb & ~i0div & ~load_kill` | Excludes killed/div/load-killed |

These are fundamentally different signals from different pipeline stages. The correlation assumes one writeback per trace item that writes a register, and zero writebacks per trace item that doesn't.

### 8.2 Scenarios Where Alignment Could Break

**Scenario A: Exception instruction with register write**
- Trace: valid=1 (exception), produces item
- Probe: wb_valid=0 (writeback killed by exception)
- Scoreboard: pending_wb_q is empty, sets write_reg=0
- Spike: Exception instruction doesn't write register either
- Result: **Correct** (both agree: no register write)

**Scenario B: Non-block load writeback**
- Trace: i0 valid=1, produces item for load instruction
- Probe: wb_valid=1 (normal), PLUS nb_load_wen=1 (delayed writeback)
- Scoreboard: Gets two probe items for the same instruction slot
- Result: **Potential desync** -- second writeback stays in queue, consumed by next instruction

**Scenario C: Division instruction**
- Trace: i0 valid=1, produces item
- Probe: wb_valid=0 (excluded by `~i0div`), but div_cancel fires later
- Scoreboard: No writeback consumed. Division result goes to nb_load channel.
- Result: **Needs verification** -- does the div result come through nb_load or wb_valid?

### 8.3 Current Mitigation

The `#0` delay ensures same-cycle probe items are enqueued before trace items are consumed. The per-slot queue (`pending_wb_q[2][$]`) prevents cross-slot contamination.

### 8.4 Remaining Risk

The alignment relies on the assumption that probe writeback count matches trace item count (per slot, per cycle). This assumption is not verified and could break for:
- Non-block loads (extra writeback)
- Divisions (delayed writeback)
- Interrupt-killed instructions (suppressed writeback with `wb_suppress`)

---

## 9. BLOCKING Risk: NUM_THREADS=2

### 9.1 Problem

`SpikeCosim` creates a single `processor_t` instance:

```cpp
// spike_cosim.cc:34
processor = std::make_unique<processor_t>(
    isa.get(), DEFAULT_VARCH, this, 0, false, log_file, std::cerr);
```

EH2 with NUM_THREADS=2 has two independent hardware threads (harts), each with its own PC, register file, and CSR state. The single Spike processor can only model one hart.

### 9.2 Impact

- Tests with NUM_THREADS=2 configuration cannot be verified with cosim.
- The `dual_thread` configuration in `eh2_configs.yaml` is not cosim-verifiable.
- Multi-thread tests (e.g., `core_eh2_dual_issue_test` with NUM_THREADS=2) must rely on other verification methods.

### 9.3 Mitigation Options

| Option | Description | Tradeoff |
|--------|-------------|----------|
| **(A) Multi-hart Spike** | Create two processor_t instances, route trace items by thread_id | Correct, requires significant SpikeCosim refactoring |
| **(B) Per-hart cosim** | Run two separate SpikeCosim instances, one per thread | Simpler, but requires thread-aware trace routing |
| **(C) Disable cosim for dual-thread** | Accept cosim limitation, verify dual-thread by other means | Pragmatic, delays full verification |

**Recommendation:** (C) for current phase. Dual-thread is a secondary configuration.

---

## 10. Minimal Cosim Verification Test Plan

These tests verify the cosim infrastructure itself, not the DUT. They should be run before any cosim-dependent regression.

### Test 1: Cosim Initialization

```
Goal: Spike initializes and accepts configuration
Binary: hello_world.hex
Config: +enable_cosim=1 +cosim_fatal_on_mismatch=0
Steps:
  1. Run simulation with cosim enabled
  2. Check log for "Co-simulation Scoreboard Report"
  3. Verify step_count > 0
Pass: Spike initializes, binary loads, at least one step completes
Fail: cosim_handle == null, or init_cosim() UVM_FATAL
```

### Test 2: Basic Instruction Match

```
Goal: Single ALU instruction matches between DUT and Spike
Binary: Minimal: addi x1, x0, 42; addi x2, x1, 1; <mailbox PASS>
Config: +enable_cosim=1 +cosim_fatal_on_mismatch=1
Steps:
  1. Run simulation
  2. Check log for "MATCH: PC=... insn=..." messages
  3. Verify mismatch_count == 0
Pass: All steps match, no mismatch errors
Fail: Any MISMATCH error in log
```

### Test 3: Load/Store Match

```
Goal: Memory access notification works correctly
Binary: sw x1, 0(x2); lw x3, 0(x2); <compare x1==x3>
Config: +enable_cosim=1 +cosim_fatal_on_mismatch=1
Steps:
  1. Run simulation
  2. Check for "MEM WR" and "MEM RD" log messages
  3. Verify no memory access mismatch
Pass: Store and load match, no pending_dside_accesses error
Fail: "ISS generated load but no DUT memory access was pending"
```

### Test 4: Dual-Issue Ordering

```
Goal: i0 and i1 are processed in correct order
Binary: Two independent ALU ops that dual-issue: addi x1,x0,1; addi x2,x0,2
Config: +enable_cosim=1 +cosim_fatal_on_mismatch=1
Steps:
  1. Run simulation
  2. Check log for two consecutive MATCH messages in same cycle
  3. Verify x1=1, x2=2 (order matters if they share state)
Pass: Both instructions match in order
Fail: PC mismatch or register data mismatch
```

### Test 5: Interrupt Handling

```
Goal: MIP notification and interrupt entry match
Binary: Simple program with timer_int raised after N cycles
Config: +enable_cosim=1 +cosim_fatal_on_mismatch=0
Steps:
  1. Run simulation with IRQ agent active
  2. Check for interrupt-related step messages
  3. Verify Spike takes interrupt at same PC as DUT
Pass: Interrupt PC matches between DUT and Spike
Fail: "Synchronous trap was expected... but DUT didn't report one"
```

### Test 6: Reset Recovery

```
Goal: Cosim re-initializes correctly after reset
Binary: hello_world.hex + random reset at cycle 1000
Config: +enable_cosim=1 +cosim_fatal_on_mismatch=0
Steps:
  1. Run simulation with reset agent
  2. Check for "Reset asserted" and "Reset de-asserted" messages
  3. Verify cosim re-initializes and continues stepping
Pass: Cosim recovers after reset, steps resume
Fail: Cosim stuck after reset, or stale state causes mismatch
```

---

## 11. Conclusion

### 11.1 Current State

The cosim data path is **architecturally sound** for the default configuration:

- i0/i1 ordering is guaranteed by the trace monitor's sequential checking.
- The TLM FIFO preserves ordering.
- The #0 delay synchronizes probe data with trace consumption.
- Spike step ordering matches the Ibex pattern.

### 11.2 Conditions for Correct Operation

The cosim can be considered correct (pending simulation verification) when ALL of the following hold:

1. **NUM_THREADS=1** (default config). Dual-thread is not supported.
2. **Tests do not touch EH2 custom CSRs** (mscause, mrac, mfdc, etc.). These are not modeled in Spike.
3. **Tests do not use non-block loads** or the non-block load writeback correlation is verified.
4. **AXI4 data bus transactions are 32-bit or narrower** for instruction-level accesses.

### 11.3 Required Next Steps (Priority Order)

| Priority | Action | Effort |
|----------|--------|--------|
| P0 | Run cosim smoke test (Test 1-2 above) to verify basic functionality | 1 day |
| P0 | Add `cosim: disabled` flag to testlist for CSR-touching tests | 0.5 day |
| P1 | Verify 64-bit bus data handling with cache line fills | 1 day |
| P1 | Verify non-block load writeback correlation | 1 day |
| P2 | Add fixup_csr() for EH2 custom CSRs | 3-5 days |
| P2 | Create cosim regression suite (Tests 1-6 above) | 2 days |
| P3 | Multi-hart SpikeCosim for NUM_THREADS=2 | 5-10 days |

### 11.4 Sign-off Readiness

| Criterion | Status |
|-----------|--------|
| Architecture documented | **DONE** (this document) |
| Data path analyzed | **DONE** |
| Ordering verified (analytically) | **DONE** |
| Ordering verified (by simulation) | **NOT DONE** |
| CSR handling complete | **NOT DONE** (4/20+ CSRs) |
| NUM_THREADS=2 support | **NOT DONE** (BLOCKING) |
| Cosim smoke test passing | **NOT DONE** |
| Cosim regression passing | **NOT DONE** |

**Overall assessment:** The platform skeleton is architecturally complete for single-thread, non-custom-CSR verification. The cosim correctness must be proven by running the minimal test plan before any large-scale regression can trust cosim results.
