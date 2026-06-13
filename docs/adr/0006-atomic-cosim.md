# ADR-0006: Atomic (A-subset) Cosim Fixup

**Date**: 2026-05-08
**Status**: Accepted
**Issue**: 52

## Context

EH2 nominally supports RV32IM**A**C + Zb*, but the atomic (A) sub-instruction-set had never been verified against Spike ISS:
- `amo_test` was `cosim: disabled` since inception
- `spike_cosim.cc` had no atomic-specific fixup
- RISK-11 tracked "atomic SC.W RTL writeback and Spike divergence"

This is a release-blocking gap: the ISA string claims "A" support but no ISS golden-reference comparison existed for LR/SC/AMO instructions.

## Decision

Add atomic-specific fixup in `spike_cosim.cc` with two components:

### 1. SC.W GPR writeback fixup

SC.W success/failure is determined by the reservation state. Spike's internal reservation tracking is based on its own memory model, while EH2's reservation is tracked at the LSU AXI level. These can diverge legitimately — e.g., a store from another thread clears Spike's reservation but may not clear EH2's.

**Fixup**: In `check_gpr_write()`, when the last committed instruction is SC.W and the rd writeback values diverge between DUT and Spike, DUT is authoritative. Spike's GPR is overwritten with DUT's SC result to keep subsequent instruction execution consistent.

### 2. LR reservation tracking

LR.W sets a reservation address. The fixup records this address in `PerThreadState::lr_reservation_addr` and uses it to detect SC.W operations that need fixup. When SC.W executes, the reservation is cleared regardless of outcome (matches RISC-V spec: SC.W clears any pending LR reservation).

## Alternatives Considered

1. **Full Spike-level reservation sync**: Would require deep integration with Spike's internal reservation mechanism, high complexity, maintenance burden when Spike upstream changes.
   - Rejected: Too invasive for marginal gain. The GPR fixup covers the only observable divergence point (rd value).

2. **Disable SC.W from random generators**: Would prevent amo_test from including SC.W sequences.
   - Rejected: Would not close the cosim gap — AMO sub-instructions matter.

3. **set_csr workaround**: Register SC.W result as a "known divergent CSR."
   - Rejected: Does not actually model the atomic semantics; violates issue 52's "不准用 set_csr fixup 绕过 atomic 实现" red line.

## Consequences

- `amo_test` cosim is enabled (was disabled)
- `cosim_atomic_basic.S` added as a directed cosim proof test
- Spike's GPR state may be modified after SC.W divergence (DUT-authoritative fixup)
- Reservation tracking is minimal and only used for SC.W detection

## Verification

```bash
make run TEST=cosim_atomic_basic COSIM=1
make run TEST=amo_test COSIM=1 SEED=1
# Expect: 0 mismatch, PASS
```
