# EH2 Synthesis Scaffold

Synthesis and logical equivalence check (LEC) infrastructure for EH2 EL2 processor.
Modeled after lowRISC Ibex syn/ structure.

## Structure

```
syn/
├── README.md
├── Makefile
├── nangate/
│   └── eh2_nangate.sdc     # Nangate 45nm SDC constraints
├── yosys/
│   └── eh2_synth.tcl       # Yosys synthesis script
└── lec/
    └── eh2_lec.tcl         # Conformal LEC / Yosys equivalence check
```

## Usage

```bash
# Synthesize with Yosys (open-source)
make syn-yosys

# Synthesize with Design Compiler (commercial)
make syn-dc

# Run logical equivalence check
make lec

# Full synthesis + LEC flow
make syn-full
```

## Prerequisites

- **Yosys**: `yosys` (open-source synthesis)
- **Design Compiler**: `dc_shell` (commercial, optional)
- **Conformal LEC**: `lec` (commercial) or Yosys `equiv` pass
- **Nangate 45nm PDK**: `NANGATE45` liberty files

## Sign-off Integration

Synthesis+LEC is a P2 requirement for v1.1 release.
Not yet part of `make signoff` full profile.
