# ADR-0020: R3-C Block-level LEC and Packed-port Mitigation

Date: 2026-05-10

## Status

Accepted.

## Context

ADR-0019 records a Synopsys O-2018.06-SP1 Formality limitation: the top-level `eh2_veer` LEC run reports 194 failing compare points, all traced to 2D packed-array or packed-struct port handling. The single top-level run has 0 known true RTL bugs in `syn/build/failing_buckets.md`.

R3-C attempted to reduce the tool-limited failure set without upgrading EDA tools by combining:

- block-level LEC for major EH2 submodules;
- standalone block synthesis to avoid top-context constant hoisting;
- explicit `set_user_match` mappings for packed struct / packed array ports;
- a LEC-only `eh2_veer_lec_pack` wrapper that flattens trace ports.

## Decision

Use the block-level flow as the R3-C LEC closure path for the Synopsys O-2018.06-SP1 packed-port limitation. The monolithic `eh2_exu` result is superseded by an EXU sub-block decomposition because the full EXU datapath is too hard for this Formality version to close as one unit.

The implemented flow is intentionally non-waiving:

- no `set_dont_verify_points` is used;
- no report files are edited by hand;
- block reports are parsed from real Formality output only;
- DDC and valid DC-generated SVF files are emitted per block to preserve datapath guidance.

## Results on 2026-05-10

The following original modules reached `Verification SUCCEEDED`:

- `eh2_dec`
- `eh2_lsu`
- `eh2_pic_ctrl`
- `eh2_dma_ctrl`
- `eh2_dbg`
- `eh2_ifu`

The original `eh2_exu` block reached clean matching but remained inconclusive as a monolithic verify:

- `eh2_exu`: packed-array user matches are accepted and the latest monolithic run reaches 0 unmatched compare points, but Formality still times out during verify on the EXU datapath cone. A graceful timeout run reports 3166 passing, 0 failing, 37 aborted, and 59 unverified compare points. Direct inspection showed those unverified points were concentrated in `mul_e1/prod_e3_ff`.

The EXU decomposition closes the remaining issue:

- `eh2_exu_alu_ctl`: 294 passing, 0 failing, 0 unverified, `Verification SUCCEEDED`;
- `eh2_exu_mul_ctl`: 272 passing, 0 failing, 0 unverified, `Verification SUCCEEDED`;
- `eh2_exu_div_ctl`: 181 passing, 0 failing, 0 unverified, `Verification SUCCEEDED`.

The key flow fix was to generate a real block SVF in `dc_synth_block.tcl` with `set_svf` before synthesis. The earlier flow copied `default.svf`, which Formality rejected as invalid and ignored. Once a valid per-block SVF was loaded before reading designs, the multiplier `prod_e3_ff` cone closed.

The latest parsed summary is 31635 passing, 0 failing, and 0 unverified compare points. The total uses the EXU sub-block reports in place of the older monolithic `eh2_exu` result.

## Consequences

The work closes the original 194 top-level failures through a non-waiving block-level path. It also proves that IFU packed-array issues, LSU packed-struct trigger inputs, and EXU datapath convergence can be handled without changing functional RTL or upgrading the EDA tools.

Next steps:

- wire `syn/build/lec_summary.txt` into `signoff.py`;
- keep ADR-0019 as the record of the original top-level tool limitation;
- keep this ADR as the accepted closure path for R3-C block-level sign-off.
