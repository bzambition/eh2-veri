# ADR-0010: Integrity Test Cosim Waiver

**Date**: 2026-05-08
**Status**: Accepted
**Issue**: 61

## Context

EH2 implements hardware integrity protections:

- **RF address parity** (`riscv_rf_addr_intg_test`): ECC on register file address lines;
  faults are injected via RTL force/release into internal RF address decode paths.
- **DCCM/ICCM RAM ECC** (`riscv_ram_intg_test`): ECC and parity on DCCM/ICCM
  memory arrays; faults inject single/double-bit errors into RAM read paths.
- **ICache tag/data parity** (`riscv_icache_intg_test`): Parity on ICache tag and
  data SRAM arrays; faults flip bits in the tag/data outputs.
- **Generic memory integrity** (`riscv_mem_intg_error_test`): System-level memory
  integrity error injection on bus interfaces.

These are purely RTL-level verification concerns. The golden ISS (Spike) models
the RISC-V ISA at the architectural level -- it has no representation of ECC
encoding/decoding, parity computation, or RAM array bit-flip fault injection.

Each integrity test works by:

1. Configuring the EH2 integrity error injection mechanism (CSR threshold registers,
   fault enable bits).
2. Injecting a fault via RTL force/release or backdoor CSR write.
3. Verifying the core either (a) takes the correct machine-check exception, or
   (b) corrects the error transparently (single-bit ECC correction) and continues
   execution, or (c) reports the error to the error counter CSRs and continues.

Spike cannot replicate any of these steps. There is no Spike model for ECC
decoders, parity trees, or hardware fault injection.

## Decision

### 1. Integrity tests are permanently cosim: disabled

These tests are waived from cosim comparison via the formal waiver file at
`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`, NOT via `cosim_reason` fields in
the testlist YAML.

The `cosim_reason` field in testlist entries is a **forbidden loophole** (Issue
50 red line). `signoff.py` blocks signoff if any `cosim_reason` field is
detected in any testlist YAML file.

### 2. RTL-only verification is trustworthy because

- **Self-checking testbench**: Each integrity test has a built-in scoreboard that
  verifies the expected architectural behavior (trap type, error counter values,
  ECC correction behavior) without relying on ISS comparison.
- **Deterministic fault injection**: Faults are injected at known addresses and
  known instruction counts; the core's response (trap or correction) is
  architecturally specified.
- **Error counter CSRs**: EH2 provides `micect`, `miccmect`, `mdccmect` CSRs
  that count detected errors; the testbench reads these to confirm faults were
  detected.
- **Directed tests**: These are small directed tests (instr_cnt=5000), not
  random sequences; the fault injection timing and expected outcome are fully
  deterministic.

### 3. Formal waiver mechanism

All cosim-disabled tests require a waiver entry in:
```
dv/uvm/core_eh2/waivers/cosim-disabled.yaml
```

Each entry MUST have:
- `test`: Test name matching the testlist
- `reason`: Technical explanation of why cosim cannot be enabled
- `tracking_issue`: GitHub issue URL
- `expiry_date`: YYYY-MM-DD review deadline

`signoff.py --validate-waivers` verifies schema compliance.

### 4. Gate enforcement

`signoff.py` enforces three levels of gate:

| Gate | Mechanism |
|------|-----------|
| No `cosim_reason` in YAML | Hard blocker in `evaluate_signoff()` -- always active |
| Cosim-disabled must have waiver | `--fail-on-cosim-disabled` (default on) checks against `cosim-disabled.yaml` |
| Waiver schema must be valid | `validate_waiver_schema()` checks required fields |

## Consequences

- **Positive**: Integrity tests are formally tracked and waiver-reviewed, not
  silently bypassed via inline comments.
- **Positive**: The `cosim_reason` loophole is permanently closed by a hard
  blocker in signoff.py.
- **Neutral**: 5 integrity tests (pc_intg, rf_intg, rf_addr_intg, ram_intg,
  icache_intg, mem_intg_error) have cosim: disabled with formal waivers.
- **Future work**: If a future ISS models microarchitectural ECC/parity (e.g., a
  cycle-accurate model), these waivers can be re-evaluated.

## Alternatives considered

### A. Spike fixup hook

Rejected. A "fixup" that ignores all comparison mismatches when an integrity
fault was injected is functionally identical to disabling cosim. There is no
meaningful comparison to make when Spike has no model of the hardware under test.

### B. Synthetic fault modeling in Spike

Rejected. Adding ECC encoding/decoding, parity trees, and fault injection
mechanisms to Spike would require a microarchitectural model of EH2's internal
datapaths, which is out of scope for an ISA-level golden reference model.

### C. Silently accept cosim_reason as waiver

Rejected. This is the Issue 50 violation being fixed here. Inline comments are
not auditable, not schema-validated, and not reviewed on expiry.
