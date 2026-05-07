# Issue 06: Per-test cosim enable/disable in testlist

Status: done (testlist 已修)
Milestone: 2 - Testlist and suppression infrastructure
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 6.3, Option (C)

## What to build

Add a `cosim` field to `riscv_dv_extension/testlist.yaml` that controls whether co-simulation is enabled for each test. Valid values: `enabled` (default), `disabled`. The regression runner (`scripts/run_regress.py`) and base test (`tests/core_eh2_base_test.sv`) must read this field and pass `+enable_cosim=<value>` to the simulation.

This enables:
- Tests that touch unmodeled EH2 custom CSRs can disable cosim
- Regression can include mixed cosim/non-cosim tests
- Cosim failures don't block tests that are expected to fail cosim

## Acceptance criteria

- [ ] `testlist.yaml` schema supports `cosim: enabled|disabled` per test
- [ ] `run_regress.py` passes `+enable_cosim=0` for `cosim: disabled` tests
- [ ] `core_eh2_base_test.sv` respects the plusarg
- [ ] Default is `enabled` when field is absent (backward compatible)
- [ ] At least one test in testlist has `cosim: disabled`

## Blocked by

None - can start immediately
