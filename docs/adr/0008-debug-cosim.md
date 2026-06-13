# ADR-0008: Debug Cosim Closure

**Date**: 2026-05-08
**Status**: Accepted
**Issue**: 54, depends on 51

## Context

EH2 has 10+ debug-related riscv-dv tests with `cosim: disabled` — the entire debug subsystem (entry/exit via ebreak, single_step, trigger, halt_run) was never verified against Spike ISS. Ibex has 13+ debug tests all passing cosim, putting EH2 at a significant verification gap for what is a safety-critical subsystem.

## Decision

### 1. Leverage existing Spike debug support

Spike natively supports:
- Debug mode entry via ebreak / haltreq
- dret (debug return) instruction
- dcsr.step single-step mode
- Debug CSR read/write (dcsr, dpc, dscratch0/1)

The cosim scoreboard already has `pc_is_debug_ebreak()`, `check_debug_ebreak()`, and `set_debug_req()` — these were ported from Ibex.

### 2. Debug CSR WARL fixup

Added dcsr/dpc/dscratch0/1 fixup in `fixup_csr()`:
- **dcsr**: WARL mask allows writes to step, ebreakm, ebreaku, nmip, mprven. ebreaks hardwired 0 (EH2 has no S-mode). cause and prv are read-only.
- **dpc**: Full writable, low 2 bits hardwired 0 (4-byte aligned)
- **dscratch0/1**: Full 32-bit writable

### 3. Debug entry/exit flow

| Entry Method | Scoreboard Handling |
|---|---|
| ebreak | `pc_is_debug_ebreak()` → `check_debug_ebreak()` → Spike enters debug mode |
| halt_req (JTAG) | `set_debug_req(true)` → Spike enters debug mode |
| single_step | dcsr.step=1 → Spike re-enters debug after each instruction |
| trigger | Trigger module not yet synced (future ADR) |

| Exit Method | Handling |
|---|---|
| dret | Spike natively executes dret, exits debug mode, resumes at dpc |
| resume_req (JTAG) | `set_debug_req(false)` → Spike resumes |

### 4. Test unlock

All 10+ debug tests had `cosim: disabled` and `skip_in_signoff` removed:
- debug, debug_csr, breakpoint, single_step, debug_wfi
- debug_during_csr, debug_ebreak, debug_in_irq, dret, debug_ebreakmu, single_debug_pulse

## Known limitations

- **Trigger module**: EH2's mcontrol/etrigger are not yet synced to Spike. breakpoint_test may fail due to trigger match divergence.
- **Halt/run agent**: JTAG halt_run_agent drives debug_req. Spike handles halt requests natively, but timing differences may cause divergence.
- **debug_in_irq / irq_in_debug**: These nested combinations require both interrupt (issue 53) and debug (issue 54) paths. Divergences should be tracked as child issues 54a/b/c.

## Consequences

- 10+ debug tests attempt cosim lockstep
- dcsr/dpc/dscratch WARL fixup aligns Spike with EH2
- ebreak-to-debug entry path is already handled (from Ibex port)
- Trigger module sync deferred to future work
- Any test that fails will generate child issues (54a-54l) — never re-disabled

## Verification

```bash
for t in debug debug_csr breakpoint single_step debug_wfi \
         debug_during_csr debug_ebreak debug_in_irq dret \
         debug_ebreakmu single_debug_pulse; do
  make run TEST=$t COSIM=1 SEED=1
done
```
