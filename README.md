# EH2 UVM Verification Platform

EH2 UVM Verification Platform is the verification framework for VeeR EH2 in this
repository. The implementation is intentionally modeled after the lowRISC Ibex
`dv/uvm/core_ibex` flow and adapted to EH2's AXI4 buses, trace-only retire
interface, PIC interrupt topology, JTAG debug path, and Spike DPI co-simulation.

## Quick start

```bash
make compile SIMULATOR=vcs
python3 dv/uvm/core_eh2/scripts/run_regress.py \
  --test smoke \
  --binary tests/asm/smoke.hex \
  --simulator vcs \
  --rtl-test core_eh2_base_test \
  --sim-opts "+disable_cosim=1" \
  --output build/smoke
python3 dv/uvm/core_eh2/scripts/collect_results.py \
  --results-dir build/smoke \
  --output-dir build/smoke_report
```

The Ibex-style staged flow is also supported from the repository root. It
creates regression metadata, delegates to `dv/uvm/core_eh2/wrapper.mk`, and
produces per-test `test.S`, `test.bin`, `test.hex`, RTL logs, `trr.yaml`, plus
top-level `regr.log`, JUnit XML, and JSON reports:

```bash
make run GOAL=collect_results OUT=build/wrapper_smoke \
  TEST=directed_smoke ITERATIONS=1 SIMULATOR=vcs
make run GOAL=dump OUT=build/wrapper_smoke TEST=all_directed ITERATIONS=1
```

## Sign-off Gate

The sign-off entry point is `dv/uvm/core_eh2/scripts/signoff.py`, also exposed
through Make:

```bash
make signoff_quick
make signoff SIGNOFF_PROFILE=full PARALLEL=4
python3 dv/uvm/core_eh2/scripts/signoff.py --profile full --dry-run
```

The gate runs/evaluates the requested Ibex-style stages (`smoke`, `directed`,
`cosim`, `riscvdv`), collects text/JUnit/JSON reports per stage, checks pass
rate and warning-clean status, optionally gates parsed coverage reports, and
writes `signoff_status.json` plus `signoff_report.md`. A final sign-off is
reported only when every requested stage and required coverage threshold passes.

Ibex-style staged entry points are available under `dv/uvm/core_eh2/wrapper.mk`.
The wrapper exposes the same stage names used by core_ibex (`core_config`,
`instr_gen_build`, `instr_gen_run`, `compile_riscvdv_tests`,
`compile_directed_tests`, `rtl_tb_compile`, `rtl_sim_run`, `check_logs`,
`merge_cov`, `collect_results`). The primary day-to-day flow can use either the
direct `run_regress.py` entry point or `make run GOAL=...`; both feed the same
result collector and sign-off gate.

## Framework Scope

The framework contains:

- UVM TB/env/test library with AXI4, IRQ, JTAG, halt/run, trace, DUT probe, and
  co-simulation components.
- riscv-dv custom target files and EH2 testlist.
- Directed testlists under `dv/uvm/core_eh2/directed_tests`.
- Functional coverage interfaces and coverage merge/report scripts.
- Regression result collection in text, JUnit XML, and JSON formats.

## Known limitations

- Spike cosim is scoped to `NUM_THREADS=1`. The `dual_thread` EH2 configuration
  must run with cosim disabled until a multi-hart SpikeCosim implementation is
  added.
- Full sign-off currently requires the `cosim` stage to pass. Existing archived
  cosim proof logs show a VCS/Spike `SIM_CRASH`, now classified explicitly by
  `check_logs.py`; this remains a blocking closure item rather than a waived
  pass.
- Tests that intentionally stress custom EH2 CSR behavior can opt out of cosim
  with `cosim: disabled` when Spike does not model the CSR side effect.
- Coverage waivers must be reviewed against generated coverage reports before
  signoff. Waiver templates live under `dv/uvm/core_eh2/waivers` and
  `dv/uvm/core_eh2/fcov/cov_waivers`.
