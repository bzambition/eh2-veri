# EH2 Lint

EH2 RTL and DV lint infrastructure, using Verible (SystemVerilog style/lint) and Verilator (lint mode).

## Structure

```
lint/
├── verible/          # SystemVerilog style/lint
│   ├── verible.rules # Enabled/disabled lint rules
│   └── waivers.vbl   # Per-file/per-line waivers
├── verilator/        # Verilator lint mode
│   ├── verilator_waiver.vlt  # Waived violations
│   └── verilator-config.vlt  # Lint configuration
├── README.md
└── Makefile
```

## Usage

```bash
# Run both linters
make lint

# Run Verible only
make lint-verible

# Run Verilator only
make lint-verilator
```

## Waiver Policy

1. Every waiver MUST have a reason comment explaining why the violation is acceptable
2. Waivers are reviewed at each release checkpoint
3. No "blanket" waivers (e.g., waiving all rules for a file without specific reasons)
4. DV code waivers are acceptable for UVM-specific constructs
5. Third-party (vendor/) code violations are waived but tracked

## Sign-off Integration

Lint is a required sign-off stage in full profile. Lint errors → sign-off FAIL.
