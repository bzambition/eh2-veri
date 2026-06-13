# EH2 Verification Platform Project Status

Version: **v1.1**

Date: **2026-05-12**

Industrial score: **4.99/5**

Top-level sign-off: **PASS**

Primary status artifact: `build/r4a_final/signoff_status.json`

Primary HTML dashboard: `build/r4a_final/report.html`

Primary Markdown report: `build/r4a_final/signoff_report.md`

## Executive Summary

EH2 Verification Platform v1.1 is a release-ready verification workspace for
the VeeR EH2 RISC-V core.

The release keeps the v1.0.2 GA simulation, coverage, compliance, CSR, lint,
and LEC numbers stable, then lands the R3-A IFV formal result into the
top-level sign-off JSON.

The main release change is formal closure:

- previous sign-off JSON formal result: `32/46 PASS`;
- current sign-off JSON formal result: `46/46 PASS`;
- current IFV log result: `Total=46`, `Pass=46`, `Not_Run=0`.

No RTL edits are required for this status update.

No generated IFV log is hand-edited for this status update.

## Current Sign-off Table

| Stage | Status | Passed | Total | Evidence |
|---|---:|---:|---:|---|
| smoke | PASS | 1 | 1 | `build/r4a_final/signoff_status.json` |
| directed | PASS | 40 | 40 | `build/r3b_final/runs/directed` |
| cosim | PASS | 7 | 7 | `build/r3b_final/runs/cosim` |
| riscvdv | PASS | 54 | 55 | `build/r3b_final/runs/riscvdv` |
| lint | PASS | 1 | 1 | `lint/build` |
| csr_unit | PASS | 20 | 20 | `build/r3b_final/runs/csr_unit` |
| compliance | PASS | 85 | 88 | `build/r3b_final/runs/compliance` |
| formal | PASS | 46 | 46 | `dv/formal/build/ifv_final.log` |
| syn | PASS | 31635 | 31635 | `syn/build/lec_summary.txt` |

Top-level status is `PASS`.

Blockers list is empty.

The status is not `PASS_WITH_WAIVERS` because the current LEC path is fully
closed through block-level Formality results.

## Coverage Status

Coverage source: `build/r3b_cov_report/dashboard.txt`

Coverage collector output: `build/r4a_final/signoff_status.json`

The 5 release-facing coverage metrics are:

| Metric | Value | v1.1 Gate |
|---|---:|---:|
| line | 78.29% | >= 65% |
| cond | 64.07% | informational |
| toggle | 55.49% | >= 50% |
| fsm | 61.81% | informational |
| functional | 69.34% | >= 40% |

Additional score:

| Metric | Value |
|---|---:|
| overall | 65.80% |

Coverage is unchanged from v1.0.2 GA.

The release does not lower coverage numbers to pass.

The release does not regenerate coverage with a reduced test pool.

## LEC Block-Level Status

LEC source: `syn/build/lec_summary.txt`

LEC stage in v1.1: `31635/31635 PASS`

All 9 modules are closed:

| Module | Passing | Failing | Unverified | Status |
|---|---:|---:|---:|---:|
| `eh2_dec` | 7160 | 0 | 0 | PASS |
| `eh2_exu_alu_ctl` | 294 | 0 | 0 | PASS |
| `eh2_exu_mul_ctl` | 272 | 0 | 0 | PASS |
| `eh2_exu_div_ctl` | 181 | 0 | 0 | PASS |
| `eh2_lsu` | 3565 | 0 | 0 | PASS |
| `eh2_pic_ctrl` | 1573 | 0 | 0 | PASS |
| `eh2_dma_ctrl` | 967 | 0 | 0 | PASS |
| `eh2_dbg` | 571 | 0 | 0 | PASS |
| `eh2_ifu` | 17052 | 0 | 0 | PASS |
| TOTAL | 31635 | 0 | 0 | PASS |

The R3-C block-level LEC strategy remains the accepted closure path.

No `set_dont_verify_points` waiver is used for this summary.

## Formal Status

Formal source: `dv/formal/build/ifv_final.log`

Formal sign-off collector source: `dv/uvm/core_eh2/scripts/signoff.py`

Formal stage output: `build/r4a_final/signoff_status.json`

Formal result:

```text
Total   : 46
Pass    : 46
Not_Run : 0
Status  : PASS
```

R3-A baseline:

```text
Total    : 46
Pass     : 32
Explored : 14
Not_Run  : 0
```

R3-A final:

```text
Total   : 46
Pass    : 46
Not_Run : 0
```

The 14 previously explored properties are documented in
`docs/release-notes-v1.1.md`.

The key closure theme was assertion hookup correctness, especially around LSU,
IFU, DMA, DCCM, ICCM, trace, and debug status signals.

## Cosim Disabled Status

Cosim disabled count: **6**

All 6 are waiver-reviewed through:

```text
dv/uvm/core_eh2/waivers/cosim-disabled.yaml
```

Active cosim-disabled tests:

| Test | Reason class |
|---|---|
| `riscv_csr_test` | EH2 custom CSR / WARL behavior not fully modeled by Spike |
| `riscv_csr_hazard_test` | EH2 CSR pipeline hazard timing not represented by Spike |
| `riscv_rf_addr_intg_test` | RTL integrity fault injection has no ISS equivalent |
| `riscv_ram_intg_test` | RAM ECC/parity injection has no ISS equivalent |
| `riscv_icache_intg_test` | ICache parity/tag fault injection has no ISS equivalent |
| `riscv_mem_intg_error_test` | memory integrity error injection has no ISS equivalent |

Inline `cosim_reason` fields are not accepted as waivers.

`signoff.py` blocks those fields as a release-gate loophole.

## Release Artifacts

| Artifact | Path |
|---|---|
| Sign-off JSON | `build/r4a_final/signoff_status.json` |
| Sign-off Markdown | `build/r4a_final/signoff_report.md` |
| HTML dashboard | `build/r4a_final/report.html` |
| Sign-off rerun log | `build/r4a_final.log` |
| IFV final log | `dv/formal/build/ifv_final.log` |
| Coverage dashboard | `build/r3b_cov_report/dashboard.txt` |
| LEC summary | `syn/build/lec_summary.txt` |
| Release notes | `docs/release-notes-v1.1.md` |
| README | `README.md` |
| ADR index | `docs/adr/INDEX.md` |

## Documentation Map

Read these files for current status:

| Document | Purpose |
|---|---|
| `README.md` | external onboarding and command entry point |
| `CONTEXT.md` | project assumptions and domain context |
| `docs/PROJECT_STATUS.md` | this one-page status dashboard |
| `docs/release-notes-v1.1.md` | v1.0.2 GA to v1.1 release delta |
| `docs/signoff-gates.md` | sign-off gate semantics |
| `docs/dir-conventions.md` | generated artifact placement policy |
| `docs/adr/INDEX.md` | canonical ADR list |
| `docs/sphinx_cn/source/overview.rst` | manual overview |
| `docs/sphinx_cn/source/architecture.rst` | manual architecture chapter |
| `docs/sphinx_cn/source/quickstart.rst` | manual quick-start chapter |
| `docs/sphinx_cn/source/directory_layout.rst` | full repository tree |

## Version Evolution

| Dimension | v1.0 | v1.0.1 | v1.0.2 GA | v1.1 |
|---|---:|---:|---:|---:|
| Status | PASS | PASS_WITH_WAIVERS | PASS | PASS |
| Stage scope | 4 stages | 9 stages | 9 stages | 9 stages |
| Formal | skeleton | 32/46 | 32/46 in JSON | 46/46 |
| LEC | not in gate | waived top-level | 31635/31635 | 31635/31635 |
| Directed | 13/13 | 33/35 | 40/40 | 40/40 |
| RISC-V DV | 32/32 | 51/55 | 54/55 | 54/55 |
| Compliance | not in gate | 85/88 | 85/88 | 85/88 |
| Line coverage | not gated | 63.06% | 78.29% | 78.29% |
| Toggle coverage | not gated | 27.46% | 55.49% | 55.49% |
| Functional coverage | not parsed | not parsed | 69.34% | 69.34% |
| HTML dashboard | absent | absent | present | refreshed |

## Current Engineering Boundaries

The v1.1 status does not claim that every possible EH2 behavior is proven in
formal or cosim.

It claims that the v1.1 release gate is closed with real tool evidence.

The active boundaries are:

- integrity fault-injection tests are waiver-reviewed because Spike has no ECC
  or parity model;
- CSR hazard cosim remains constrained by Spike's architectural timing model;
- coverage remains at the v1.0.2 GA level;
- release docs point to generated evidence instead of copying raw logs.

## Operational Notes

Use `build/r4a_final` for the v1.1 release record.

Use `build/r3b_final/runs` as the archived simulation run directory behind
the gate-only v1.1 replay.

Use `build/r3b_cov_report` as the coverage source.

Use `dv/formal/build/ifv_final.log` as the formal source.

Use `syn/build/lec_summary.txt` as the block-level LEC source.

Do not modify `dv/formal/build/ifv_final.log`.

Do not hand-edit `signoff_status.json`.

Do not modify `rtl/` for release documentation updates.

Do not reduce coverage thresholds to make a release pass.
