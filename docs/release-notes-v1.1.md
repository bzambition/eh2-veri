# EH2 Verification Platform v1.1 Release Notes

Date: 2026-05-12

## Release Conclusion

v1.1 is the first release where the full EH2 verification platform records the
R3-A Cadence IFV formal closure in the top-level sign-off JSON.

The v1.0.2 GA baseline already had a full PASS sign-off with block-level LEC and
coverage closure, but its `formal` stage still reported `32/46` because the
sign-off status was generated before the final IFV log was re-collected.

R4-A reran the sign-off collector against the real IFV output:

- formal before v1.1: `32/46 PASS`;
- formal after v1.1: `46/46 PASS`;
- IFV evidence: `dv/formal/build/ifv_final.log`;
- sign-off evidence: `build/r4a_final/signoff_status.json`;
- HTML dashboard: `build/r4a_final/report.html`.

Top-level status is `PASS`.

## v1.0.2 to v1.1 Delta

| Area | v1.0.2 GA | v1.1 |
|---|---:|---:|
| Top-level status | PASS | PASS |
| Formal stage | 32/46 PASS | 46/46 PASS |
| LEC stage | 31635/31635 PASS | 31635/31635 PASS |
| Directed stage | 40/40 PASS | 40/40 PASS |
| RISC-V DV stage | 54/55 PASS | 54/55 PASS |
| Coverage line | 78.29% | 78.29% |
| Coverage toggle | 55.49% | 55.49% |
| Coverage functional | 69.34% | 69.34% |
| HTML report | available through R3-B gate | refreshed under `build/r4a_final/report.html` |
| Workspace hygiene | documented conventions | v1.1 README and project status link the cleanup policy |

No RTL files are touched by this release note update. The release is a sign-off
and documentation closure on top of the existing v1.0.2 GA implementation.

## Full v1.1 Sign-off Numbers

Source: `build/r4a_final/signoff_status.json`.

| Stage | Status | Passed | Total | Notes |
|---|---:|---:|---:|---|
| smoke | PASS | 1 | 1 | RTL-only mailbox smoke path |
| directed | PASS | 40 | 40 | Directed assembly suite, including R3-B coverage pumps |
| cosim | PASS | 7 | 7 | Spike DPI lockstep directed cosim proofs |
| riscvdv | PASS | 54 | 55 | Stage threshold waiver covers the known parser-classified reset item |
| lint | PASS | 1 | 1 | Verible/Verilator lint gate collected through sign-off |
| csr_unit | PASS | 20 | 20 | EH2 CSR unit compliance sub-environment |
| compliance | PASS | 85 | 88 | RISC-V compliance stage threshold closure |
| formal | PASS | 46 | 46 | Cadence IFV assertion summary, `Not_Run=0` |
| syn | PASS | 31635 | 31635 | Block-level Synopsys Formality LEC, 9 modules |

## Coverage Metrics

Source: `build/r3b_cov_report/dashboard.txt`, re-gated in
`build/r4a_final/signoff_status.json`.

| Metric | v1.1 Value | Gate |
|---|---:|---:|
| overall | 65.80% | informational |
| line | 78.29% | >= 65% |
| cond | 64.07% | informational |
| toggle | 55.49% | >= 50% |
| fsm | 61.81% | informational |
| functional | 69.34% | >= 40% |

The coverage numbers are intentionally unchanged from v1.0.2 GA. v1.1 is not a
stimulus-expansion release; it lands the final formal collector result and
refreshes the release-facing documentation.

## HTML Dashboard

The release dashboard is generated at:

```text
build/r4a_final/report.html
```

The dashboard consumes:

- `build/r4a_final/signoff_status.json`;
- `build/r3b_cov_report/dashboard.txt`;
- `build/r3b_final/runs`.

The formal section now renders `46/46`, matching the IFV log and the top-level
JSON.

## R3-A Formal Closure

R3-A converted the IFV formal stage from a partial collector snapshot to a full
assertion PASS result.

The baseline was:

- `dv/formal/build/r3a_baseline.log`;
- `Total=46`;
- `Pass=32`;
- `Explored=14`;
- `Not_Run=0`.

The final run is:

- `dv/formal/build/r3a_final.log`;
- `dv/formal/build/ifv_final.log`;
- `Total=46`;
- `Pass=46`;
- `Not_Run=0`.

## R3-A 14 Hookup Bug Fixes

The 14 previously explored formal objects were hookup or proof-harness issues,
not RTL functional regressions. R3-A closed them by wiring assertions to the
real EH2 source signals or by matching the property to the true microarchitecture.

| # | Property | Closure detail |
|---:|---|---|
| 1 | `a_trace_valid_addr` | Changed trace address check from whole 64-bit nonzero to valid-lane address checking |
| 2 | `a_lsu_wstrb_active` | Reconnected LSU write strobe property to the real `lsu.bus_intf` generation path |
| 3 | `a_ifu_arvalid_stable` | Checked top-level IFU ARVALID against `ifu.mem_ctl.ifu_axi_arvalid` |
| 4 | `a_iccm_wr_rd_mutex` | Reframed ICCM read/write check around real top-level and `ifu.mem_ctl` source signals |
| 5 | `a_lsu_araddr_stable` | Reconnected LSU ARADDR to the real `lsu.bus_intf` path |
| 6 | `a_dccm_wr_rd_mutex` | Moved aggregate DCCM check to `lsu.dccm_ctl` spec write/read one-hot intent |
| 7 | `a_lsu_awvalid_stable` | Reconnected LSU AWVALID to the real `lsu.bus_intf` path |
| 8 | `a_lsu_wdata_stable` | Reconnected LSU WDATA to the real `lsu.bus_intf` path |
| 9 | `a_lsu_awaddr_stable` | Reconnected LSU AWADDR to the real `lsu.bus_intf` path |
| 10 | `a_debug_halt_track` | Replaced PMU halt-ack semantics with `dec.tlu.o_debug_mode_status` |
| 11 | `a_dma_arvalid_stable` | Reframed external DMA master ARVALID into EH2-owned ARREADY / DMA control hookup |
| 12 | `a_lsu_arvalid_stable` | Reconnected LSU ARVALID to the real `lsu.bus_intf` path |
| 13 | `a_lsu_wvalid_stable` | Reconnected LSU WVALID to the real `lsu.bus_intf` path |
| 14 | `a_dma_awvalid_stable` | Reframed external DMA master AWVALID into EH2-owned AWREADY / DMA control hookup |

The closure sequence is visible in:

- `dv/formal/build/r3a_baseline.log`: 32 pass, 14 explored;
- `dv/formal/build/r3a_retry_hookup1.log`: 33 pass, 13 explored;
- `dv/formal/build/r3a_retry_hookup2.log`: 46 pass;
- `dv/formal/build/r3a_final.log`: 46 pass.

## Block-Level LEC

v1.1 keeps the R3-C block-level LEC result unchanged.

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

## Workspace Hygiene

v1.1 documents the workspace policy more explicitly:

- tool outputs belong under `build/`, `out/`, `csrc/`, `syn/build/`, or
  tool-specific ignored directories;
- release artifacts are named by release or round, such as `build/r4a_final`;
- generated EDA logs are evidence and must not be hand-edited;
- `docs/dir-conventions.md` is the reference for clean-up scope;
- `scripts/clean_workspace.sh` exists for controlled removal of generated
  output, not for source cleanup.

## Evolution Table

| Dimension | v1.0 | v1.0.1 | v1.0.2 GA | v1.1 |
|---|---:|---:|---:|---:|
| Release status | PASS, 4-stage scope | PASS_WITH_WAIVERS | PASS | PASS |
| Smoke | 1/1 | 1/1 | 1/1 | 1/1 |
| Directed | 13/13 | 33/35 | 40/40 | 40/40 |
| Cosim | 5/5 | 7/7 | 7/7 | 7/7 |
| RISC-V DV | 32/32 | 51/55 | 54/55 | 54/55 |
| Lint | not in gate | 1/1 | 1/1 | 1/1 |
| CSR unit | not in gate | 20/20 | 20/20 | 20/20 |
| Compliance | not in gate | 85/88 | 85/88 | 85/88 |
| Formal | skeleton only | 32/46 | 32/46 in JSON | 46/46 |
| Syn / LEC | not in gate | 29545/30869 waived | 31635/31635 | 31635/31635 |
| Line coverage | not gated | 63.06% | 78.29% | 78.29% |
| Toggle coverage | not gated | 27.46% | 55.49% | 55.49% |
| Functional coverage | not parsed | not parsed | 69.34% | 69.34% |
| HTML dashboard | not present | not present | present | refreshed |
| Cosim-disabled waiver set | broad historical list | narrowed and schema-checked | 6 active entries | 6 active entries |

## Compatibility and Tool Requirements

v1.1 preserves the v1.0.2 GA tool requirements:

- Synopsys VCS for RTL simulation;
- Synopsys Design Compiler and Formality for synthesis and LEC;
- Cadence IFV 15.20 for the formal run used by R3-A;
- Spike with EH2 cosim DPI integration;
- `riscv32-unknown-elf-*` bare-metal toolchain;
- Python 3 with `pyyaml` for regression and reporting scripts.

## Release Artifacts

Primary artifacts:

- `build/r4a_final/signoff_status.json`;
- `build/r4a_final/signoff_report.md`;
- `build/r4a_final/report.html`;
- `docs/release-notes-v1.1.md`;
- `docs/PROJECT_STATUS.md`;
- `docs/adr/INDEX.md`;
- `README.md`.

The sign-off artifacts are regenerated from collectors and existing tool output.
They are not hand-edited JSON or hand-edited IFV logs.
