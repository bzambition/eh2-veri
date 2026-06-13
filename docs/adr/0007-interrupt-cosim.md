# ADR-0007: Interrupt Cosim Closure

**Date**: 2026-05-08
**Status**: Accepted
**Issues**: 53, depends on 51

## Context

EH2 has 8 interrupt-related riscv-dv tests with `cosim: disabled` — the entire interrupt subsystem was never verified against Spike ISS. Since interrupt entry/exit is the most corner-case-rich path in RTL, this is a P0 release blocker.

The gap spans:
- General interrupt injection (interrupt_test)
- Single interrupt (irq_single_test)  
- WFI wakeup (irq_wfi_test)
- CSR interaction during interrupt (irq_csr_test)
- Nested interrupts (irq_nest_test)
- Stress (stress_test)
- Reset mid-test (reset_test)
- Interrupt-in-debug (irq_in_debug_test — also depends on issue 54)

## Decision

### 1. Interrupt-only trace item (already implemented)

The scoreboard already distinguishes interrupt-only trace items (`interrupt=1 && exception=0`) from exception trace items. For interrupt-only items:
- Spike's `set_mip()` is called to update the interrupt pending bits
- Spike does NOT `step()` — no instruction was executed
- mcause/mepc comparison now uses UVM_ERROR + mismatch_count (issue 51)

### 2. PIC CSR registration (already implemented)

28 EH2 custom CSRs including all PIC registers (meivt, meipt, meicurpl, meicidpl, meihap) are registered in spike_cosim.cc via `initial_proc_setup()` and have WARL fixup in `fixup_csr()`.

### 3. Nested interrupt mstatus stack

EH2 only supports M-mode, so mstatus.mpp always decodes to M. Nested interrupts push/pop mstatus.mpie/mie/mpp on the hardware stack. The cosim scoreboard relies on set_csr fixup to keep Spike's mstatus aligned with DUT. No additional fixup needed since both sides implement the same priv-spec-compliant stacking.

### 4. Test unlock strategy

All 8 interrupt tests had `cosim: disabled` removed:
- irq_single_test: Added `+max_interval=200` to prevent forever-loop timeout
- stress_test: cosim enabled (combined IRQ+debug; debug path is issue 54 scope)
- irq_in_debug_test: cosim enabled (requires both issue 53 and 54 paths)

Any tests that fail cosim after unlock will generate child issues (53a-53h) — never re-disabled.

## Alternatives Considered

1. **Full PIC model in Spike**: Would require adding 127 external interrupt sources + priority arbitration to Spike.
   - Rejected: Massive effort, low ROI. PIC is EH2-specific and not part of the ISA spec.

2. **Filter out interrupt trace items from cosim comparison**: Would bypass interrupt entry/exit entirely.
   - Rejected: Violates P0 requirement — the point is to verify interrupt behavior.

## Consequences

- 8 interrupt tests now attempt cosim lockstep
- mcause/mepc mismatch now correctly fails the test (was silently INFO)
- PIC behavior is modeled through set_csr registration, not full PIC emulation
- If nested interrupt mstatus stack diverges, Spike fixup_csr handles alignment

## Verification

```bash
for t in interrupt irq_single stress reset irq_wfi irq_csr irq_nest irq_in_debug; do
  make run TEST=$t COSIM=1 SEED=1
done
```
