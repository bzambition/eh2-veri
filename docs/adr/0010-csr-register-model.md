# ADR 0010: CSR Register Model — uvm_reg over csr_desc_t

## Status

Accepted (2026-05-08)

## Context

The EH2 CSR unit test sub-environment (Issue 56) requires a register model
that describes every CSR address, reset value, WARL mask, read-only status,
and access privilege.  Two approaches were evaluated:

| Approach | Mechanism | Pros | Cons |
|----------|-----------|------|------|
| **csr_desc_t** | Hand-rolled struct + associative array (`csr_desc_t csrs[$]`) | Simple, quick to write | Not UVM-standard; no built-in mirroring, prediction, or coverage hooks; ad-hoc lookup; tools and review scripts cannot use standard `uvm_reg` reflection |
| **uvm_reg / uvm_reg_block** | UVM register layer: each CSR = one `uvm_reg` in a `uvm_reg_block` | Industry standard; automatic mirror / predict / scoreboard integration; frontdoor + backdoor access; coverage model built-in; discoverable via `uvm_reg::type_id` | More code per register |

## Decision

Use **uvm_reg / uvm_reg_block** for the EH2 CSR register model.  
The `csr_desc_t` approach is rejected.

### Why uvm_reg

1. **Mirroring and prediction** — `uvm_reg` provides `mirror()`, `predict()`,
   and `do_predict()` as built-in mechanisms.  The scoreboard can push
   DUT-observed values into the mirror and detect mismatches without
   writing ad-hoc comparison code per CSR.

2. **Access abstraction** — `uvm_reg::read()` / `uvm_reg::write()` support
   both frontdoor (bus-sequencer) and backdoor (DPI/hierarchical) access.
   The EH2 unit test uses DPI backdoor access; the same register model
   could later be reused with a bus frontdoor in a full-chip environment.

3. **Discoverability** — Standard `uvm_reg` introspection allows scripts
   (including the `grep "uvm_reg\b"` sign-off check) to verify that
   every CSR has been instantiated.  With `csr_desc_t`, verification
   tools must parse a custom struct format.

4. **Coverage** — `uvm_reg` fields can carry functional coverage models
   (e.g., `has_coverage(UVM_CVR_ALL)`).  `csr_desc_t` has no coverage
   integration path.

5. **Industry precedent** — LowRISC Ibex (the reference implementation)
   uses `uvm_reg`-style register modelling in C++ (`BaseRegister` class),
   confirming this is the accepted pattern for RISC-V CSR verification.

### Why not csr_desc_t

- No UVM mirror / predict integration — must hand-write every comparison
- No standard backdoor access — must invent custom read/write functions
- No coverage linkage — cannot attach covergroups to individual registers
- The task specification explicitly forbids it: "No csr_desc_t style"

## Implementation

Each EH2 CSR (standard RISC-V M-mode + EH2 custom extensions, ~65 total)
is a single `eh2_csr_reg` object extending `uvm_reg`.  All registers
live in `eh2_csr_reg_block` (extends `uvm_reg_block`).

Access to the DUT goes through DPI backdoor functions (`csr_dpi_read`,
`csr_dpi_write`) exported from the `csr_dut` register-file module.
The register model's `predict_from_dut()` method synchronizes the
mirror from the DUT after each access.

## Consequences

- **Positive**: Standard UVM tooling can introspect and verify the model
- **Positive**: Mirror-based scoreboard comparison eliminates hand-written
  per-CSR check code
- **Positive**: The model can be shared between unit-test and full-chip
  environments by swapping the access mechanism (DPI backdoor vs bus frontdoor)
- **Negative**: Slightly more boilerplate per register (handled by the
  `add_reg()` helper in `eh2_csr_reg_block::build()`)
- **Negative**: Requires VCS or another simulator with DPI + UVM 1.2 support

## References

- Issue 56: cs_registers unit test sub-environment for EH2 RISC-V core
- ADR 0006: Atomic Cosimulation (CSR fixup_csr logic for EH2 custom CSRs)
- ADR 0009: PMP Cosimulation (PMP register WARL behaviour)
- LowRISC Ibex `dv/cs_registers/model/register_model.h` (C++ register model)
- UVM 1.2 Reference Manual, Chapter 5: Register Layer
