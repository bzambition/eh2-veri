# ADR 0011: RISC-V Compliance Framework

**Status:** Accepted  
**Date:** 2026-05-08  
**Issue:** [#57](https://github.com/example/eh2-veri/issues/57)

## Context

EH2 needs a RISC-V compliance verification framework to ensure the core correctly
implements the RISC-V ISA specifications. The compliance framework runs standard
RISC-V compliance test suites, captures signature outputs, and compares them
byte-by-byte against golden reference outputs.

Two upstream compliance frameworks are available on the host:

1. **riscv-compliance** (`/home/host/riscv-compliance/`) -- the original
   Imperas/Codasip compliance framework with per-instruction tests.
2. **riscv-tests** (`/home/host/riscv-tests/`) -- the official RISC-V
   ISA tests from the riscv-software-src/riscv-tests repository.

## Decision

**Use riscv-compliance as the primary framework** (rv32i, rv32im, rv32imc,
rv32Zicsr, rv32Zifencei).  We use the test source files and reference outputs
from this framework, but compile them with our own EH2 device files (linker
script, startup code, compliance I/O headers).  The riscv-tests repository is
a fallback for future expansion.

### Signature comparison strategy

- **Comparer**: byte-by-byte comparison, NO relaxation.
- **How it works**:
  1. Compliance test writes its results to a `.signature` data section.
  2. At test end, `RV_COMPLIANCE_HALT` writes the begin/end signature addresses
     to the EH2 compliance mailbox (`0xD0580004` / `0xD0580008`), then triggers
     signature dump via a write to `0xD0580000`.
  3. The testbench (simv) reads the signature range from AXI4 slave memory and
     emits `SIGNATURE: XXXXXXXX` lines to stdout.
  4. The Python runner (`scripts/run_compliance.py`) parses these lines and
     compares each 32-bit word against the reference file byte-by-byte.
- **Any byte difference = FAIL**.  No approximations, no fuzzy matching.

### Testbench architecture

Two TB options are provided:

| TB | Top module | Use case |
|----|-----------|----------|
| `core_eh2_tb_top` | Full UVM TB (existing) | Can run compliance hex files via `+bin=` |
| `eh2_compliance_tb` | Stand-alone compliance TB | No UVM dependency; signature monitor built-in; Verilator-ready |

Both TBs instantiate `eh2_veer_wrapper`, connect to AXI4 slave memories, and
monitor the mailbox at `0xD0580000`.

### Supported ISA suites

| ISA | Suite dir | Tests | Expected status |
|-----|-----------|-------|-----------------|
| rv32i | `riscv-test-suite/rv32i` | 48 | PASS |
| rv32im | `riscv-test-suite/rv32im` | 8 | PASS |
| rv32imc | `riscv-test-suite/rv32imc` | 25 | PASS |
| rv32Zicsr | `riscv-test-suite/rv32Zicsr` | TBD | known-fail (CSR writeback not yet fully verified) |
| rv32Zifencei | `riscv-test-suite/rv32Zifencei` | TBD | known-fail |

## Consequences

### Positive

- Automated gate in sign-off flow: `full` profile includes `compliance` stage.
- Catches ISA regression immediately (wrong ALU result, mis-decoded instruction).
- Byte-level diff means no silent signature corruption passes.
- Device files are per-ISA, allowing ISA-specific startup/link differences.

### Negative / Trade-offs

- Compliance testing requires the full simv build (~30-60s per test run).
- Known-fail suites (rv32Zicsr, rv32Zifencei) still run signature comparison but
  may legitimately fail -- these are tracked for future closure.
- The compliance stage only runs rv32i/rv32im/rv32imc by default.  Z-extensions
  require explicit `--isa` flags.

### Alternatives considered

1. **riscv-arch-test (riscof) framework** -- newer framework with better
   modularity but not yet adopted.  Too heavy for the current EH2 verification
   maturity.
2. **Per-test UVM sequences** -- too heavyweight for compliance; the bare
   simv + hex approach is simpler and more portable.
3. **Fuzzy signature matching** -- rejected because any byte-level difference
   in a compliance signature indicates a real ISA bug.

## Verification

```bash
cd /home/host/eh2-veri/dv/uvm/riscv_compliance
make compliance RISCV_ISA=rv32i
make compliance RISCV_ISA=rv32imc
```

The sign-off `full` profile also gates on the compliance stage:

```bash
cd /home/host/eh2-veri
make signoff SIGNOFF_PROFILE=full
# Looks for: compliance PASS in sign-off report
```
