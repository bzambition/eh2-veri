# EH2 Verification Platform

EH2 Verification Platform is a UVM, cosim, coverage, formal, and sign-off
environment for the VeeR EH2 RISC-V core.

This repository is not a marketing wrapper around a few smoke tests. It is a
release-oriented verification workspace that collects RTL simulation,
Spike-based instruction lockstep, directed assembly, riscv-dv stimulus,
coverage, CSR unit checks, RISC-V compliance, lint, formal proof, and
block-level LEC into one sign-off record.

Current release: **v1.1**.

Current sign-off result: **PASS**.

Current formal result: **46/46 PASS**.

Current LEC result: **31635/31635 PASS**.

## Project Scope

VeeR EH2 is a 32-bit RISC-V processor core with RV32IMAC support, EH2-specific
custom CSRs, tightly coupled memories, programmable interrupt control, debug
logic, AXI/AHB-facing integration points, and a dual-thread-capable
microarchitecture.

This platform verifies the EH2 core through:

- UVM testbench infrastructure under `dv/uvm/core_eh2`;
- Spike DPI cosim under `dv/cosim`;
- directed assembly tests under `dv/uvm/core_eh2/tests/asm`;
- riscv-dv integration under `dv/uvm/core_eh2/riscv_dv_extension`;
- functional coverage under `dv/uvm/core_eh2/fcov`;
- formal properties and IFV scripts under `dv/formal`;
- synthesis and LEC summaries under `syn`;
- sign-off reporting under `build/<release>/`.

The platform is modeled after the lowRISC Ibex verification flow, but it is not
a line-for-line port. EH2 has different bus topology, trace behavior, CSR
surface, debug topology, memory error paths, and multi-thread support, so the
verification architecture is adapted around EH2-specific contracts.

## Architecture

The core data path is RTL retire trace plus DUT probes into a UVM scoreboard,
with Spike DPI acting as the architectural reference model.

```text
   ┌─────────────────────────────────────────────────────────────┐
   │                    Sign-off Orchestration                   │
   │  signoff.py  gen_html_report.py  collect_results.py         │
   └────────────────────────────┬────────────────────────────────┘
                                │ JSON / Markdown / HTML
   ┌────────────────────────────▼────────────────────────────────┐
   │                      Regression Stages                      │
   │  smoke  directed  cosim  riscvdv  lint  csr  compliance     │
   │  formal  syn                                                │
   └────────────────────────────┬────────────────────────────────┘
                                │ report.json / logs / coverage
   ┌────────────────────────────▼────────────────────────────────┐
   │                       UVM Environment                       │
   │  tests → env → agents → trace monitor → cosim scoreboard    │
   └────────────────────────────┬────────────────────────────────┘
                                │ trace item + probe hint
   ┌────────────────────────────▼────────────────────────────────┐
   │                         VeeR EH2 DUT                         │
   │  rtl/design + shared/rtl + generated configuration snapshots │
   └────────────────────────────┬────────────────────────────────┘
                                │ retired instruction stream
   ┌────────────────────────────▼────────────────────────────────┐
   │                         Spike DPI                            │
   │  libcosim.so  spike_cosim.cc  CSR fixups  memory comparison │
   └─────────────────────────────────────────────────────────────┘
```

Important contracts:

- RTL retire packets carry the architectural instruction state used by cosim.
- DUT probe monitors provide long-latency writeback hints for EH2 pipeline
  behavior that is not visible in a simple trace packet.
- The cosim scoreboard fails on architectural mismatch; it is not a mailbox-only
  result checker.
- The sign-off JSON is produced by collectors reading tool output, not by hand.
- Coverage and formal evidence are kept as generated artifacts and linked from
  release notes.

## Platform Capability Matrix

| Capability | Ibex reference flow | EH2 v1.1 flow | EH2 status |
|---|---|---|---|
| UVM env/test hierarchy | mature `core_ibex` environment | `core_eh2` env, tests, vseq, agents | PASS |
| ISS cosim | RVFI-centered Ibex cosim | trace/probe-centered Spike DPI cosim | PASS |
| Bus monitoring | simpler Ibex bus surface | AXI4 passive monitoring plus memory model | stronger EH2 adaptation |
| Active agents | core Ibex agents | AXI4, JTAG, IRQ, halt/run, trace, cosim | broader EH2 agent set |
| Directed tests | Ibex directed testlist | 40/40 directed in v1.1 | PASS |
| riscv-dv | broad Ibex target | 54/55 v1.1 stage result | PASS by stage gate |
| CSR unit tests | `cs_registers` environment | EH2 CSR unit environment, 20/20 | PASS |
| Compliance | integrated RISC-V compliance | 85/88 with documented gate | PASS |
| Functional coverage | mature Ibex coverage | line 78.29%, functional 69.34% | PASS |
| PMP coverage | Ibex PMP coverage baseline | `eh2_pmp_fcov_if.sv` is 1461 lines | EH2 exceeds line count |
| Formal | Ibex formal stack | Cadence IFV, 46/46 assertions | PASS |
| Synthesis / LEC | Ibex synthesis checks | block-level Formality, 31635/31635 | PASS |
| HTML dashboard | project dependent | self-contained sign-off dashboard | PASS |
| ADR discipline | strong | 20 ADR files plus index | PASS |

EH2 overtakes the original comparison baseline in several areas:

- more verification agents because EH2 exposes more integration interfaces;
- deeper PMP functional coverage file size and coverage intent;
- a richer sign-off profile with CSR unit, compliance, lint, formal, and syn
  stages in the same top-level JSON;
- block-level LEC closure for 9 EH2 modules;
- HTML reporting wired into the release artifact path.

Areas that remain intentionally constrained:

- cosim-disabled tests are limited to 6 waived entries in v1.1;
- integrity fault injection remains RTL-only because Spike has no ECC or parity
  fault model;
- multi-thread cosim is documented through ADRs and code support, but sign-off
  numbers here are the v1.1 release gate numbers, not a claim of every
  multi-thread scenario.

## Quick Start

The following three commands run the smoke path from a prepared workspace with
VCS and the RISC-V toolchain available:

```bash
cd /home/host/eh2-veri
source env.sh
python3 dv/uvm/core_eh2/scripts/run_regress.py --test smoke --binary tests/asm/smoke.hex --simulator vcs --rtl-test core_eh2_base_test --sim-opts "+disable_cosim=1" --output build/quick_smoke
```

If `build/simv` is missing, compile first:

```bash
make compile NO_COSIM=1 SIMULATOR=vcs
```

If you want the standard quick sign-off wrapper instead of a single smoke run:

```bash
make signoff_quick PARALLEL=4 SIGNOFF_OUT=build/signoff_quick
```

The primary full sign-off command is:

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1 LEC_BLOCKLEVEL=1 COV=1 SIGNOFF_OUT=build/signoff
```

For release replay using existing R3-B run artifacts and the R3-A IFV result,
v1.1 uses a gate-only collector path equivalent to:

```bash
python3 dv/uvm/core_eh2/scripts/signoff.py \
  --profile full \
  --gate-only \
  --output build/r4a_final \
  --stage-result smoke=build/r3b_final/runs/smoke \
  --stage-result directed=build/r3b_final/runs/directed \
  --stage-result cosim=build/r3b_final/runs/cosim \
  --stage-result riscvdv=build/r3b_final/runs/riscvdv \
  --stage-result csr_unit=build/r3b_final/runs/csr_unit \
  --stage-result compliance=build/r3b_final/runs/compliance \
  --lec-blocklevel \
  --lec-summary-path syn/build/lec_summary.txt \
  --coverage-path build/r3b_cov_report \
  --min-line-coverage 65 \
  --min-toggle-coverage 50 \
  --min-functional-coverage 40
```

Generate the release HTML report:

```bash
python3 dv/uvm/core_eh2/scripts/gen_html_report.py \
  --signoff-status build/r4a_final/signoff_status.json \
  --coverage-dashboard build/r3b_cov_report/dashboard.txt \
  --runs-dir build/r3b_final/runs \
  --output build/r4a_final/report.html
```

## Sign-off Results

v1.1 sign-off source:

```text
build/r4a_final/signoff_status.json
build/r4a_final/signoff_report.md
build/r4a_final/report.html
```

Stage table:

| Stage | Status | Passed | Total |
|---|---:|---:|---:|
| smoke | PASS | 1 | 1 |
| directed | PASS | 40 | 40 |
| cosim | PASS | 7 | 7 |
| riscvdv | PASS | 54 | 55 |
| lint | PASS | 1 | 1 |
| csr_unit | PASS | 20 | 20 |
| compliance | PASS | 85 | 88 |
| formal | PASS | 46 | 46 |
| syn | PASS | 31635 | 31635 |

Coverage table:

| Metric | Value |
|---|---:|
| overall | 65.80% |
| line | 78.29% |
| cond | 64.07% |
| toggle | 55.49% |
| fsm | 61.81% |
| functional | 69.34% |

LEC module table:

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

Formal evidence:

```text
dv/formal/build/ifv_final.log
Assertion Summary:
  Total                  :  46
  Pass                   :  46
  Not_Run                :   0
```

## Repository Layout

The detailed manual version of this tree lives in
`docs/sphinx_cn/source/directory_layout.rst`.

```text
eh2-veri/
├── README.md
├── CONTEXT.md
├── Makefile
├── env.sh
├── env.mk
├── eh2_configs.yaml
├── dv/
│   ├── cosim/
│   │   ├── cosim.h
│   │   ├── cosim_dpi.cc
│   │   ├── cosim_dpi.svh
│   │   ├── spike_cosim.cc
│   │   └── spike_cosim.h
│   ├── formal/
│   │   ├── Makefile
│   │   ├── README.md
│   │   ├── eh2_formal_top.sv
│   │   ├── eh2_veer_sva.sv
│   │   ├── ifv_filelist.f
│   │   ├── scripts/
│   │   ├── properties/
│   │   └── build/
│   └── uvm/
│       ├── bus_params_pkg/
│       ├── core_eh2/
│       │   ├── tb/
│       │   ├── env/
│       │   ├── common/
│       │   │   ├── axi4_agent/
│       │   │   ├── cosim_agent/
│       │   │   ├── halt_run_agent/
│       │   │   ├── irq_agent/
│       │   │   ├── jtag_agent/
│       │   │   └── trace_agent/
│       │   ├── tests/
│       │   │   └── asm/
│       │   ├── directed_tests/
│       │   ├── riscv_dv_extension/
│       │   ├── fcov/
│       │   ├── scripts/
│       │   ├── yaml/
│       │   └── waivers/
│       ├── cs_registers_eh2/
│       └── riscv_compliance/
├── docs/
│   ├── adr/
│   ├── agents/
│   ├── sphinx_cn/
│   │   ├── source/
│   │   └── build/html/
│   ├── dir-conventions.md
│   ├── release-notes-v1.0.md
│   ├── release-notes-v1.1.md
│   └── PROJECT_STATUS.md
├── rtl/
│   ├── design/
│   └── snapshots/
├── shared/
│   └── rtl/
├── syn/
│   └── build/
├── tests/
│   └── asm/
├── vendor/
│   └── google_riscv-dv/
├── scripts/
├── .github/
│   └── workflows/
├── build/
├── out/
└── csrc/
```

## Main Commands

Build Spike DPI:

```bash
make cosim
```

Compile VCS testbench:

```bash
make compile SIMULATOR=vcs
```

Run one directed test:

```bash
python3 dv/uvm/core_eh2/scripts/run_regress.py \
  --test directed_alu \
  --testlist dv/uvm/core_eh2/directed_tests/directed_testlist.yaml \
  --simulator vcs \
  --seed 1 \
  --output build/one_directed
```

Run the cosim directed list:

```bash
python3 dv/uvm/core_eh2/scripts/run_regress.py \
  --testlist dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml \
  --simulator vcs \
  --iterations 1 \
  --parallel 4 \
  --output build/cosim_directed
```

Run sign-off dry plan:

```bash
python3 dv/uvm/core_eh2/scripts/signoff.py --profile full --dry-run
```

Run the full synthesis and LEC flow:

```bash
make synth
```

Run block-level LEC:

```bash
make block_lec
```

Validate cosim-disabled waivers:

```bash
python3 dv/uvm/core_eh2/scripts/signoff.py \
  --validate-waivers dv/uvm/core_eh2/waivers/cosim-disabled.yaml
```

## Documentation Navigation

Read in this order when joining the project:

1. `README.md`: external entry point, commands, current release numbers.
2. `CONTEXT.md`: domain assumptions, key risk history, current project language.
3. `docs/PROJECT_STATUS.md`: one-page v1.1 status board with sign-off metrics.
4. `docs/release-notes-v1.1.md`: release delta from v1.0.2 GA to v1.1.
5. `docs/adr/INDEX.md`: ADR map and canonical numbering.
6. `docs/sphinx_cn/source/overview.rst`: manual overview.
7. `docs/sphinx_cn/source/architecture.rst`: component architecture.
8. `docs/sphinx_cn/source/quickstart.rst`: manual quick-start flow.
9. `docs/sphinx_cn/source/directory_layout.rst`: full directory explanation.
10. `docs/signoff-gates.md`: gate semantics and waiver rules.
11. `docs/dir-conventions.md`: generated artifact placement and cleanup policy.

Use release notes for historical deltas:

- `docs/release-notes-v1.0.md`: first four-stage UVM release.
- `docs/release-notes-v1.1.md`: R3-A formal 46/46 landing in sign-off JSON.

## Toolchain Requirements

The full platform assumes access to commercial EDA tools and a RISC-V software
toolchain.

Required for full sign-off:

- Synopsys VCS for SystemVerilog simulation;
- Synopsys Design Compiler for synthesis inputs used by the LEC flow;
- Synopsys Formality for block-level LEC;
- Cadence IFV 15.20 for the v1.1 formal proof evidence;
- Spike built with the EH2 cosim DPI integration;
- `riscv32-unknown-elf-gcc`;
- `riscv32-unknown-elf-objcopy`;
- Python 3;
- `pyyaml`;
- GNU Make.

Common environment variables:

| Variable | Meaning |
|---|---|
| `RV_ROOT` | Upstream VeeR EH2 RTL root |
| `EH2_VERIF_ROOT` | This repository root |
| `GCC_PREFIX` | RISC-V bare-metal compiler prefix |
| `RISCV_DV_ROOT` | riscv-dv checkout or submodule path |
| `SPIKE_INSTALL` | Spike cosim installation prefix |
| `SIMULATOR` | Simulation backend, normally `vcs` |
| `COV` | Coverage enable flag for Make targets |
| `WAVES` | Waveform enable flag for debug runs |

## Generated Outputs

Generated files are release evidence, but they are not source.

Important output paths:

- `build/r4a_final/signoff_status.json`: v1.1 sign-off JSON.
- `build/r4a_final/signoff_report.md`: v1.1 Markdown sign-off report.
- `build/r4a_final/report.html`: v1.1 HTML dashboard.
- `build/r4a_final.log`: R4-A sign-off rerun log.
- `dv/formal/build/ifv_final.log`: IFV final formal log.
- `syn/build/lec_summary.txt`: block-level LEC summary.
- `build/r3b_cov_report/dashboard.txt`: coverage dashboard reused by v1.1.

Generated work areas:

- `build/`: regression, compile, coverage, and sign-off output.
- `out/`: riscv-dv and wrapper output.
- `csrc/`: VCS C compilation intermediate files.
- `syn/build/`: synthesis and LEC output.
- `dv/formal/build/`: formal tool output.

Do not hand-edit generated evidence files to make a release pass.

## Waiver Policy

v1.1 allows 6 active cosim-disabled entries, all tracked through
`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`:

- `riscv_csr_test`;
- `riscv_csr_hazard_test`;
- `riscv_rf_addr_intg_test`;
- `riscv_ram_intg_test`;
- `riscv_icache_intg_test`;
- `riscv_mem_intg_error_test`.

Waivers are valid only through the waiver YAML file. Inline `cosim_reason`
fields in testlists are blocked by `signoff.py`.

Stage-level gate waivers are different from cosim-disabled waivers:

- riscv-dv reports 54/55 and passes by stage threshold;
- compliance reports 85/88 and passes by suite threshold;
- top-level status remains PASS because these thresholds are encoded in the
  sign-off gate and represented in the JSON report.

## Release History

| Version | Date | Status | Main Result |
|---|---:|---:|---|
| v1.0 | 2026-05-08 | PASS | Four-stage UVM sign-off reached 51/51 |
| v1.0.1 | 2026-05-10 | PASS_WITH_WAIVERS | Full 9-stage gate introduced, LEC tool limitation waived |
| v1.0.2 GA | 2026-05-11 | PASS | Coverage 78.29% line and LEC 31635/31635 closed |
| v1.1 | 2026-05-12 | PASS | Formal collector lands 46/46 in sign-off JSON |

## License

This workspace does not currently contain a top-level `LICENSE` file. Treat the
repository as an internal verification workspace unless maintainers publish an
explicit license for external distribution.

Third-party and upstream components retain their own licensing terms:

- VeeR EH2 RTL comes from the configured `RV_ROOT` source tree.
- Google riscv-dv is carried under `vendor/google_riscv-dv`.
- Spike is an external dependency installed through the local cosim toolchain.
- Commercial EDA tools are used under their respective site licenses.

## Citation

When referring to this platform in reports, cite the release artifact and the
source evidence together:

```text
EH2 Verification Platform v1.1, build/r4a_final/signoff_status.json,
formal evidence dv/formal/build/ifv_final.log, generated 2026-05-12.
```

For design decisions, cite the relevant ADR file under `docs/adr/`.

For sign-off numbers, cite `build/r4a_final/signoff_status.json` rather than a
copied table.

## Contact

Use the repository issue tracker or review flow for project questions.

Primary owner group: EH2 verification maintainers.

Sign-off questions should include:

- the command that was run;
- the output directory;
- the relevant `signoff_status.json`;
- the tool log path;
- whether `env.sh` was sourced;
- whether the run used fresh simulation or gate-only collector mode.
