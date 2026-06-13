# ADR 0012: Formal Verification Strategy for EH2

**Status:** Proposed
**Date:** 2026-05-08
**Author:** Agent (Issue 63)
**Supersedes:** N/A (first formal verification ADR)
**Superseded by:** N/A

## Context

EH2 RISC-V core has growing verification complexity with 30+ RTL modules spanning decode, execute, load/store, debug, and interrupt controller domains. Simulation-based verification (UVM) is the primary methodology, but simulation alone cannot exhaustively cover corner cases in pipeline hazards, PMP address matching, debug FSM transitions, and interrupt priority arbitration.

Issue 42 established a formal verification skeleton (`dv/formal/`) with one SVA file (9 properties for PMP/LSU) and one Symbiyosys configuration. This skeleton was compile-only -- no proofs were attempted, coverage was below 10%, and only the LSU address checker was instrumented.

Issue 63 (this ADR) upgrades the skeleton to a multi-module property set with actual Symbiyosys proof runs and sail-riscv integration.

## Decision

We will deploy a **multi-module formal verification strategy** with four independent property sets, each targeting a distinct EH2 module, connected by a shared architectural reference (sail-riscv).

### Property File Allocation

| File | Target Module | Domain | Properties | Cover Points |
|------|--------------|--------|-----------|--------------|
| `eh2_pmp_assert.sv` | `eh2_lsu_addrcheck` | PMP/MPU address check, mem map, side-effects | 7 assert + 1 cover | 1 |
| `eh2_dec_assert.sv` | `eh2_dec` | Pipeline decode, CSR legality, MRET, hazards | 5 assert + 1 cover | 1 |
| `eh2_dbg_assert.sv` | `eh2_dbg` | Debug FSM, halt/resume, abstract command | 5 assert + 1 cover | 1 |
| `eh2_pic_assert.sv` | `eh2_pic_ctrl` | Interrupt priority tree, claim/complete, threshold | 5 assert + 1 cover | 1 |
| `sail_bridge.sv` | sail-riscv ref model | Architectural invariants (x0, privilege, cause) | 3 assert (SAIL-REF) | 0 |

**Total: 25 assertions + 4 cover points = 29 formal objects**

### Property Selection Principles

1. **No tautologies** -- every property has a non-trivial antecedent and consequent (e.g., `a && b |-> c` where `c` is not `1'b1`)
2. **Falsifiable** -- each property has a counterexample that would cause a formal failure
3. **Module-scoped** -- properties target single-module interfaces; no cross-module temporal dependencies
4. **Architecture-informed** -- properties tagged SAIL-REF are derived from sail-riscv formal model invariants

### Sail-RISCV Integration

The architectural reference model (sail-riscv) is integrated at three levels:

1. **SVA bridge** (`sail_bridge.sv`): Projects EH2 microarchitectural signals into sail-observable state (PC, GPR writeback, privilege, exception cause). Three SAIL-REF assertions validate:
   - x0 register stability (writes to x0 must be zero)
   - Exception cause encoding (within privileged spec Table 3.6 range)
   - Privilege mode (EH2 is M-mode only; no U/S transitions)

2. **Trace replay** (`sail_trace_check.py`): Offline checker that replays EH2 execution traces through sail-riscv c_emulator and flags architectural state divergence.

3. **Setup script** (`sail_setup.sh`): Automated vendor/bootstrap of sail-riscv from upstream for environments where it is not pre-installed.

If sail-riscv cannot be built in a given environment, the SAIL-REF assertions in `sail_bridge.sv` remain valid and proveable because they encode ISA invariants directly in SVA without depending on the sail runtime.

### Engine Strategy

All proofs use Symbiyosys `smtbmc z3` (bounded model checking with Z3 SMT solver):

| Configuration | Depth | Rationale |
|--------------|-------|-----------|
| `sby_pmp.sby` | 25 | Combinational address matching + pipelined state (dc1->dc2) |
| `sby_dec.sby` | 20 | Pipeline depth from decode (D) to writeback (WB) ~ 4-5 stages |
| `sby_dbg.sby` | 20 | Debug FSM worst-case path: IDLE->HALTING->HALTED->RESUMING->IDLE |
| `sby_pic.sby` | 20 | Priority tree depth = log2(PIC_TOTAL_INT_PLUS1) ~ 7 levels |

Vacuous proof ratio is tracked in the sby log output. Target: less than 30% vacuous. Properties that prove vacuously are flagged for tightening.

### Coverage Strategy

Each property file includes at least one `cover property` to exercise a realizable scenario:
- PMP: external address with valid load/store
- Decoder: MRET instruction decoded
- Debug: full halt-resume round trip
- PIC: interrupt claim sequence

These cover statements are checked during `make formal` to confirm that formal assumptions do not over-constrain the design.

## Consequences

### Positive
- Four independently proveable property sets that can be run in parallel
- Architectural invariants validated against ISA specification via sail-riscv
- Zero-vacuous-proof requirement enforced by cover property checks
- Modular structure: adding a new property file only requires a new .sby config

### Negative
- Bounded model checking depth (20-30) may miss deep sequential bugs; induction or k-induction (`smtbmc induction`) can be added later for unbounded proofs
- sail-riscv trace replay requires the c_emulator binary, which may not be available in all CI environments (graceful degradation to SAIL-REF SVA checks)
- Four separate Yosys elaboration passes add runtime (~2-5 min per configuration with Z3)

### Risks

| Risk | Mitigation |
|------|-----------|
| Z3 timeout on large designs | Separate .sby per module keeps each elaboration tractable |
| sail-riscv build complexity | SAIL-REF properties encode invariants directly; sail binary is optional |
| Vacuity from over-constrained assumptions | Cover properties verify reachability |

## Alternatives Considered

1. **JasperGold only**: Rejected. Commercial tool licenses are not guaranteed in all environments. Symbiyosys provides an open-source baseline.
2. **Single monolithic .sby with all modules**: Rejected. Yosys elaboration of all EH2 RTL would exceed memory/time limits.
3. **Skip sail integration**: Rejected. ADR requirement mandates sail-riscv as architectural golden reference, even if via offline trace replay.

## Verification

```bash
# Run all formal proofs
cd dv/formal && make formal

# Expected output:
# sby_pmp: N proved, 0 failed
# sby_dec: M proved, 0 failed
# sby_dbg: P proved, 0 failed
# sby_pic: Q proved, 0 failed

# Count total properties
grep -c "property\s\+\w" properties/*.sv  # >= 12 total
grep -c "cover\s\+property" properties/*.sv # >= 4 total

# Check sail content
ls dv/formal/spec/   # sail_bridge.sv, sail_trace_check.py, sail_setup.sh
```

## Related Documents

- ADR 0001: Co-simulation via trace and probe
- ADR 0009: PMP co-simulation
- sail-riscv: https://github.com/riscv/sail-riscv
- Symbiyosys: https://symbiyosys.readthedocs.io/
