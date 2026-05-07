# Issue 02: Single ALU cosim test

Status: done (Phase 1 arithmetic PASS)
Milestone: 1 - Minimal cosim loop
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 10, Test 2

## What to build

Create a minimal assembly test (`asm/cosim_alu.S`) that exercises basic ALU instruction comparison between DUT and Spike. The test executes a known sequence of register-writing instructions (addi, add, sub, and, or, xor) with deterministic inputs, then writes mailbox PASS.

This verifies:
- Register writeback correlation (probe queue + trace item alignment)
- Spike step() matches DUT on PC and rd_data
- No false mismatch on instructions that write x0

## Acceptance criteria

- [ ] `asm/cosim_alu.S` compiles with `riscv64-unknown-elf-gcc -march=rv32imac`
- [ ] Test runs with `core_eh2_cosim_test` + `+enable_cosim=1` + `+cosim_fatal_on_mismatch=1`
- [ ] Simulation log shows MATCH messages for each ALU instruction
- [ ] `mismatch_count == 0` in cosim report
- [ ] Mailbox PASS detected

## Blocked by

- Issue 01 (cosim smoke test must pass first)
