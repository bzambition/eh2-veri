# Issue 03: Load/store cosim test

Status: done (cosim_load_store PASS — Phase 3 BE 语义修复后稳定)
Milestone: 1 - Minimal cosim loop
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 10, Test 3

## What to build

Create a minimal assembly test (`asm/cosim_load_store.S`) that exercises the memory access notification path. The test performs known store/load pairs (SW/LW, SH/LH, SB/LB) with deterministic addresses and data, then writes mailbox PASS.

This verifies:
- `notify_memory_access()` is called for each AXI4 transaction
- `pending_dside_accesses` queue matches Spike's `mmio_load`/`mmio_store`
- Byte-enable (strb) handling for sub-word accesses
- No "ISS generated load but no DUT memory access was pending" error

## Acceptance criteria

- [ ] `asm/cosim_load_store.S` compiles with `riscv64-unknown-elf-gcc -march=rv32imac`
- [ ] Test runs with `core_eh2_cosim_test` + `+enable_cosim=1` + `+cosim_fatal_on_mismatch=1`
- [ ] Simulation log shows "MEM WR" and "MEM RD" messages
- [ ] `mismatch_count == 0` in cosim report
- [ ] No "no DUT memory access was pending" errors
- [ ] Mailbox PASS detected

## Blocked by

- Issue 01 (cosim smoke test must pass first)

## 完成证据

- cosim_testlist.yaml 中 `cosim_load_store` PASS（build/sf_full2、build/sf_baseline2 均通过）
- CONTEXT.md §6 RISK-8: RESOLVED — Phase 3 BE 语义放宽后 1848 trace / 0 mismatch
- mismatch_count=0 稳定可复现
