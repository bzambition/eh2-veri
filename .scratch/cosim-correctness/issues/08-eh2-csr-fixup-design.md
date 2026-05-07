# Issue 08: Design EH2 custom CSR fixup_csr long-term strategy

Status: done (set_csr 静态注册)
Milestone: 3 - Risk hardening
Type: HITL

## Parent

docs/cosim-correctness-analysis.md -- Section 6.3

## What to build

Design the long-term strategy for handling EH2 custom CSRs in Spike co-simulation. This requires an architectural decision between four options:

| Option | Description | Effort |
|--------|-------------|--------|
| (A) Full fixup | Add fixup_csr() for all 20+ EH2 CSRs, matching RTL WARL behavior | 3-5 days |
| (B) Read-only suppression | Make unrecognized CSRs read-only in Spike | 1 day |
| (C) Per-test disable | Keep current suppression, add more disabled tests as needed | 0 (already done in #07) |
| (D) Spike extension | Add EH2 CSR definitions to Spike source | 5-10 days |

The decision must consider:
- Sign-off requirements (can we certify without CSR-level cosim?)
- Maintenance burden (how many CSRs change between EH2 versions?)
- Spike fork feasibility (do we own the Spike source?)

Output: an ADR in `docs/adr/` documenting the chosen strategy.

## Acceptance criteria

- [ ] ADR document created at `docs/adr/NNNN-eh2-csr-cosim-strategy.md`
- [ ] All four options evaluated with pros/cons
- [ ] Chosen strategy justified with sign-off requirements
- [ ] Implementation plan for chosen strategy (if not option C)

## Blocked by

- Issue 07 (suppression must be in place before long-term design)
