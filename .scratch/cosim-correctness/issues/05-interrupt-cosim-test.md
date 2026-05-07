# Issue 05: Interrupt cosim test

Status: needs-triage
Milestone: 3 - Risk hardening
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 10, Test 5

## What to build

Create an assembly test (`asm/cosim_interrupt.S`) that verifies interrupt notification in the cosim path. The test enables MIE, sets up a trap handler, then waits for a timer interrupt raised by the IRQ agent. After handling the interrupt, it writes mailbox PASS.

This verifies:
- `set_mip()` pre/post notification matches Spike's interrupt logic
- Spike takes interrupt at the same PC as DUT
- Trap handler entry (mtvec) matches between DUT and Spike
- mepc/mcause written by interrupt match Spike's state

## Acceptance criteria

- [ ] `asm/cosim_interrupt.S` compiles
- [ ] Test runs with `core_eh2_cosim_test` + `+enable_cosim=1` + IRQ agent active
- [ ] Spike takes interrupt (no "Synchronous trap was expected" error)
- [ ] Interrupt PC matches between DUT and Spike
- [ ] `mismatch_count == 0` after interrupt handling
- [ ] Mailbox PASS detected

## Blocked by

- Issue 01 (cosim smoke test must pass first)
