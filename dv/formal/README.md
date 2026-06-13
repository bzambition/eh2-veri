# Formal Verification for EH2 RISC-V Core

> **Status:** Multi-module property set deployed (Issue 63). 25 assertions + 4 cover points across 4 property files.

## Directory Structure

```
dv/formal/
├── README.md                       # This file
├── Makefile                        # Build and run entry point
├── properties/
│   ├── eh2_pmp_assert.sv           # PMP/LSU address check (8 properties)
│   ├── eh2_dec_assert.sv           # Decoder pipeline/CSR (6 properties)
│   ├── eh2_dbg_assert.sv           # Debug module FSM (6 properties)
│   └── eh2_pic_assert.sv           # PIC interrupt controller (6 properties)
├── scripts/
│   ├── sby_pmp.sby                 # Symbiyosys config: eh2_lsu_addrcheck
│   ├── sby_dec.sby                 # Symbiyosys config: eh2_dec
│   ├── sby_dbg.sby                 # Symbiyosys config: eh2_dbg
│   └── sby_pic.sby                 # Symbiyosys config: eh2_pic_ctrl
└── spec/
    ├── sail_bridge.sv              # EH2-to-Sail-RISCV formal bridge
    ├── sail_trace_check.py         # Trace replay divergence checker
    └── sail_setup.sh               # Sail-riscv bootstrap script
```

## Property Coverage

| Module | Domain | Assertions | Cover Points | SAIL-REF |
|--------|--------|-----------|-------------|----------|
| `eh2_lsu_addrcheck` | PMP/MPU mem map, sideeffects | 7 | 1 | 0 |
| `eh2_dec` | Pipeline, CSR, MRET, hazards | 5 | 1 | 1 |
| `eh2_dbg` | Halt/resume FSM, abstract cmd | 5 | 1 | 0 |
| `eh2_pic_ctrl` | Priority tree, claim/complete | 5 | 1 | 0 |
| `sail_bridge` | Arch invariants (x0, priv, cause) | 3 | 0 | 3 |
| **Total** | | **25** | **4** | **4** |

## Usage

### Run all formal proofs

```bash
cd dv/formal
make formal
```

### Run individual module

```bash
make formal_pmp   # PMP/LSU only
make formal_dec   # Decoder only
make formal_dbg   # Debug module only
make formal_pic   # PIC only
```

### Check property counts

```bash
make formal_count
```

### Clean artifacts

```bash
make formal_clean
```

## Prerequisites

- [Symbiyosys](https://symbiyosys.readthedocs.io/) (`sby` command)
- [Yosys](https://yosyshq.net/yosys/) (synthesis frontend)
- SMT solver: [Z3](https://github.com/Z3Prover/z3) or [Boolector](https://boolector.github.io/)

### Sail-RISCV Integration (optional)

For SAIL-REF property validation and trace replay:

```bash
cd dv/formal/spec && bash sail_setup.sh
```

This clones and builds [sail-riscv](https://github.com/riscv/sail-riscv) as the architectural golden model. If unavailable, SAIL-REF assertions in `sail_bridge.sv` remain valid and proveable.

## Related Documents

- `docs/adr/0012-formal-strategy.md` — Formal verification strategy ADR
- `rtl/design/lsu/eh2_lsu_addrcheck.sv` — PMP/MPU address checker RTL
- `rtl/design/dec/eh2_dec.sv` — Decoder top-level RTL
- `rtl/design/dbg/eh2_dbg.sv` — Debug module RTL
- `rtl/design/eh2_pic_ctrl.sv` — PIC RTL
