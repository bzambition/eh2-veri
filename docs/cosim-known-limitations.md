# EH2 Cosim Known Limitations

Date: 2026-05-09

This file records the remaining tests with `cosim: disabled` in
`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml` after the Task-C unlock pass.
The debug, PMP/ePMP, and listed integrity tests were run with cosim enabled; the
remaining disabled entries below are either real CSR-model compare failures or
testbench class registration gaps.

## Remaining Disabled Tests

| Test | Failure trace | Root cause | Disposition |
|---|---|---|---|
| `riscv_csr_test` | Cycle/time: 405000 ps. PC: DUT `0x00000000`, Spike `0x80000000`; insn `0x00000000`; expected aligned boot PC retirement, actual synchronous-trap PC mismatch. Log: `build/cosim_remaining_disabled_seed1/run/tests/riscv_csr_test.1/sim_riscv_csr_test_1.log`. | A: Spike CSR model gap. The directed CSR stream exercises EH2 custom CSR/WARL behavior and reset/trap synchronization not modeled by Spike. | Keep disabled under `dv/uvm/core_eh2/waivers/cosim-disabled.yaml`; fix path is targeted EH2 custom CSR presync/postsync modeling in `spike_cosim.cc`. |
| `riscv_csr_hazard_test` | Cycle/time: 4765000 ps. PC: DUT retired `0x80016cf0`, Spike retired `0x80016c00`; insn `0x0800006f`; expected same retired PC after CSR hazard stream, actual ISS lag/divergence. Log: `build/cosim_remaining_disabled_seed1/run/tests/riscv_csr_hazard_test.1/sim_riscv_csr_hazard_test_1.log`. | C: scoreboard/ISS timing limitation around EH2 CSR pipeline hazards. Spike is architectural and does not model EH2 CSR write/read forwarding or skid timing. | Keep disabled under waiver; fix path is a CSR hazard-aware synchronization window, not a blanket mismatch bypass. |
| `riscv_rf_addr_intg_test` | Cycle/time: 0. PC: not reached. Expected UVM test class `core_eh2_rf_addr_intg_test`; actual `UVM_FATAL [INVTST] Requested test ... not found`. Log: `build/cosim_remaining_disabled_seed1/run/tests/riscv_rf_addr_intg_test.1/sim_riscv_rf_addr_intg_test_1.log`. | B: testbench registration gap plus integrity-fault modeling gap. The RTL test class is absent from the compiled UVM test set; even after registration, Spike has no RF address parity/fault-injection model. | Keep disabled under waiver; fix path is to add the UVM test class or map to an existing self-checking integrity class, then keep RTL-only unless a microarchitectural fault model is added. |
| `riscv_ram_intg_test` | Cycle/time: 0. PC: not reached. Expected UVM test class `core_eh2_ram_intg_test`; actual `UVM_FATAL [INVTST] Requested test ... not found`. Log: `build/cosim_remaining_disabled_seed1/run/tests/riscv_ram_intg_test.1/sim_riscv_ram_intg_test_1.log`. | B: testbench registration gap plus DCCM/ICCM ECC fault-model gap. Spike memory is byte-addressable ISA memory with no RAM ECC/parity injection. | Keep disabled under waiver; fix path is UVM class registration and RTL-only self-checking coverage unless an EH2 ECC model is introduced. |
| `riscv_icache_intg_test` | Cycle/time: 0. PC: not reached. Expected UVM test class `core_eh2_icache_intg_test`; actual `UVM_FATAL [INVTST] Requested test ... not found`. Log: `build/cosim_remaining_disabled_seed1/run/tests/riscv_icache_intg_test.1/sim_riscv_icache_intg_test_1.log`. | B: testbench registration gap plus ICache tag/data parity model gap. Spike has no instruction-cache tag/data arrays or parity state. | Keep disabled under waiver; fix path is UVM class registration and RTL-only self-checking coverage unless cache parity modeling is added. |
| `riscv_mem_intg_error_test` | Cycle/time: 0. PC: not reached. Expected UVM test class `core_eh2_mem_intg_error_test`; actual `UVM_FATAL [INVTST] Requested test ... not found`. Log: `build/cosim_remaining_disabled_seed1/run/tests/riscv_mem_intg_error_test.1/sim_riscv_mem_intg_error_test_1.log`. | B: testbench registration gap plus memory integrity error-model gap. Spike lacks EH2 integrity CSRs, fault injection hooks, and error-reporting timing. | Keep disabled under waiver; fix path is UVM class registration and RTL-only self-checking coverage unless an EH2 integrity fault model is added. |

## Unlock Evidence

The user-provided target list contains 19 tests, although the prompt says 18.
All 19 listed tests passed with cosim enabled for seed 1 in
`build/cosim_19_seed1/report.json`.

Sentinel tests `riscv_debug_test`, `riscv_pmp_basic_test`, and
`riscv_mem_error_test` passed seeds 1, 2, and 3 in
`build/cosim_sentinel_3seed/report.json`.
