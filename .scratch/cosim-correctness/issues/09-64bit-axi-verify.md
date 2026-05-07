# Issue 09: Verify 64-bit AXI4 memory access notify correctness

Status: needs-triage
Milestone: 3 - Risk hardening
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 7, RISK-2

## What to build

Investigate whether RV32IMAC instruction-level loads/stores can produce 64-bit AXI4 bus transactions. The concern is that `notify_memory_access()` truncates `beat_data[31:0]` and `beat_strb[3:0]`, which would be wrong if the DUT produces 64-bit transactions for 32-bit instructions.

Investigation steps:
1. Read EH2 RTL LSU to determine maximum bus width per instruction access
2. Check if cache line fills (ICache/DCCM) produce 64-bit bursts that reach the AXI4 monitor
3. Run a test with 64-bit bus monitoring enabled, check AXI4 transaction widths
4. If 64-bit transactions exist, fix `notify_memory_access()` to handle them

## Acceptance criteria

- [ ] Analysis document: can RV32IMAC instructions produce 64-bit AXI4 transactions?
- [ ] If yes: `notify_memory_access()` updated to handle 64-bit data
- [ ] If no: documented with evidence from RTL analysis
- [ ] Load/store cosim test (Issue 03) passes with no data truncation errors

## Blocked by

None - can start immediately (investigation task)
