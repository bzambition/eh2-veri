# ADR-0009: PMP/ePMP Cosim Closure

**Date**: 2026-05-08
**Status**: Accepted
**Issue**: 55, depends on 51

## Context

The `misaligned_pmp_fixup` function in `spike_cosim.cc` was an empty stub, causing all 6 PMP/ePMP tests to be `cosim: disabled`. PMP is a safety-critical feature for isolating memory regions, and ePMP (enhanced PMP with MML/MMWP/RLB) adds Machine-Mode Whitelist Policy.

PMI (Physical Memory Integrity) verification without ISS golden reference is insufficient for industrial release.

## Decision

### 1. Implement misaligned_pmp_fixup

The stub now:
1. Checks if any PMP regions are enabled (pmpcfg L bits)
2. Scans pending dside accesses for error-flagged entries (PMP fault paths)
3. Removes faulting access entries so Spike's memory comparison doesn't stall

This handles the common case: misaligned load/store crossing a PMP region boundary where one half faults and the other succeeds.

### 2. PMP CSR pass-through

PMP config registers (pmpcfg0-3) and address registers (pmpaddr0-15) are forwarded to Spike natively via `put_csr()`. Spike already implements standard PMP matching in its TLB/mmu layer. ePMP-specific bits (mml/mmwp/rlb in the upper byte of pmpcfg) are preserved by Spike's put_csr.

### 3. Test unlock

All 6 PMP tests had `cosim: disabled` removed:
- pmp_basic: 4-region basic PMP
- pmp_disable_all: All regions disabled (should be equivalent to no PMP)
- pmp_random: 8 random regions
- epmp_mml: ePMP Machine Mode Lockdown
- epmp_mmwp: ePMP Machine Mode Whitelist Policy
- epmp_rlb: ePMP Rule Locking Bypass

## Limitations

- Full ePMP state machine (mml/mmwp/rlb interaction) is not modeled in Spike. Tests exercising these extensions may see divergence.
- Misaligned PMP access with cacheability attributes (mrac interaction) is not modeled.
- Complex PMP region overlap behavior may differ between EH2 and Spike. Divergences → new child issues.

## Consequences

- 6 PMP tests attempt cosim lockstep
- PMP CSR writes propagated to Spike for native PMP matching
- misaligned_pmp_fixup handles the common crossing-boundary fault case
- ePMP-specific divergence tracked via child issues (55a-55f)

## Verification

```bash
for t in pmp_basic pmp_disable_all pmp_random epmp_mml epmp_mmwp epmp_rlb; do
  for s in 1 2 3 4 5; do
    make run TEST=$t COSIM=1 SEED=$s
  done
done
```
