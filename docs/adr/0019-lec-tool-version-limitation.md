# ADR-0019: LEC Tool Version Limitation

Date: 2026-05-09

Status: Open

## Context

Formality LEC is blocked at:

- 30,675 passing compare points
- 194 failing compare points
- 0 unverified compare points

The current available Synopsys tools are:

- Design Compiler `O-2018.06-SP1`
- Formality `O-2018.06-SP1`

No newer Synopsys 2020.09+ install was found in the active PATH or under the
local Synopsys install tree inspected during Task-A.  `yosys` is not installed.
Cadence Conformal LEC command-line tools were not found in PATH.

## Root Cause

The 194 failing points are unmatched reference ports from 2D packed arrays.
The parsed failing report is `syn/build/lec_failing.rpt`; the user-provided
`syn/build/lec_failing.txt` currently contains only:

```text
No failing points available before matching.
```

Bucket result:

- Clock-gated register differences: 0
- 2D packed array ports: 194
- ECC spare bits: 0
- DFT scan chain: 0
- True RTL bug / other unmatched: 0

Signal families:

- `ic_wr_data`: 142
- `btb_rw_addr`: 18
- `btb_rw_addr_f1`: 18
- `btb_sram_rd_tag_f1`: 10
- trace 2D ports: 6

## Decision

Do not use `set_dont_verify_points` for these 194 failing points.

Reason: these are not semantically waived design differences.  They are tool
matching failures caused by O-2018.06-SP1 handling of 2D packed array port
flattening.  Waiving them would hide the LEC mismatch rather than close it.

The preferred closure path remains tool upgrade to Synopsys 2020.09+ DC/FM, or a
newer Formality release capable of matching the flattened packed-array ports.

## Consequences

The current O-2018.06-SP1 flow cannot meet:

- `Verification PASSED`
- `Failing <= 0`

without either:

- upgrading DC/FM, or
- introducing exact, verified user matches for every flattened bit while keeping
  `Unverified` bounded.

Earlier user-match/SVF attempts in this workspace already produced worse
outcomes, including large unverified counts, so this ADR records the tool
version limitation rather than applying a waiver.
