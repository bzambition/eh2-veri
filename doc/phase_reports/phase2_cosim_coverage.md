# Phase 2: Cosim & Coverage - PARTIALLY COMPLETED

## 2.1 Spike EH2 Custom CSR Support - DONE
CSR fixup implemented in `spike_cosim.cc`:
- `initial_proc_setup()` initializes 30+ EH2 custom CSRs in csrmap
- `fixup_csr()` handles WARL behavior for mstatus, misa, mtvec, mcause
- Default case writes EH2 custom CSR values directly to Spike's csrmap

## 2.2 Coverage Bind Fix - DONE
- Changed from SV `bind` to testbench-level instantiation
- Signals connected via hierarchical references across 3 module levels
- 4 covergroups: uarch_cg, csr_cg, dual_issue_cg, interrupt_cg
- Smoke test passes with `+enable_eh2_fcov=1`

## 2.3 64-bit AXI4 Data Truncation - DONE
Scoreboard already handles 64-to32-bit split correctly in `notify_memory_access()`.

## 2.4 Directed Tests with Cosim - BLOCKED
Cosim still has fundamental Spike issues:
- "memory size must be a positive multiple of 4 KiB" for unmapped addresses
- Segfault in DPI after Spike exception
- Disabled with `+enable_cosim=0`

## Status: 3/4 DONE, 1 BLOCKED
