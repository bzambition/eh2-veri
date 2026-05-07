# Issue 04: Dual-issue ordering cosim test

Status: done (Phase 1 双发射 div/load 闭环)
Milestone: 1 - Minimal cosim loop
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 10, Test 4

## What to build

Create a minimal assembly test (`asm/cosim_dual_issue.S`) that exercises dual-issue ordering. The test constructs instruction pairs that are likely to dual-issue (independent ALU ops back-to-back), verifying that i0 is always stepped before i1 in the same cycle.

This verifies:
- Trace monitor produces i0 before i1 (Section 2 of analysis)
- TLM FIFO preserves ordering
- Spike processes instructions in program order even when DUT retires two in one cycle
- No ordering-induced mismatch

## Acceptance criteria

- [ ] `asm/cosim_dual_issue.S` compiles with `riscv64-unknown-elf-gcc -march=rv32imac`
- [ ] Test runs with `core_eh2_cosim_test` + `+enable_cosim=1` + `+cosim_fatal_on_mismatch=1`
- [ ] Simulation log shows two consecutive MATCH messages for same-cycle dual-issue
- [ ] `mismatch_count == 0` in cosim report
- [ ] IPC > 1.0 observed in trace monitor report (confirms dual-issue occurred)
- [ ] Mailbox PASS detected

## Blocked by

- Issue 01 (cosim smoke test must pass first)
