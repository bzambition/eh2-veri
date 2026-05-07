# Issue 07: Cosim suppression for EH2 custom CSR tests

Status: done (28 CSR 已预注册)
Milestone: 2 - Testlist and suppression infrastructure
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 6, RISK-1

## What to build

Mark all tests in `testlist.yaml` that exercise EH2 custom CSRs (mscause, mrac, mfdc, mcgc, mpmc, mcpc, dmst, mfdht, mfdhs, mhartstart, mnmipdel, PIC CSRs) with `cosim: disabled`. This prevents false cosim failures from Spike not recognizing these CSRs.

Affected tests (from testlist.yaml):
- `riscv_csr_test` -- accesses all CSRs
- `riscv_csr_hazard_test` -- back-to-back CSR ops
- Any test with `+directed_instr_*=eh2_csr_access_stream`
- Any test with `+directed_instr_*=eh2_pic_int_stream`
- Any test with `+directed_instr_*=eh2_debug_csr_stream`

## Acceptance criteria

- [ ] All tests that touch EH2 custom CSRs have `cosim: disabled` in testlist.yaml
- [ ] Tests that only touch standard M-mode CSRs remain `cosim: enabled`
- [ ] `make regress` runs without false cosim failures on disabled tests
- [ ] A comment in testlist.yaml explains why each test has cosim disabled

## Blocked by

- Issue 06 (per-test cosim toggle must exist first)
