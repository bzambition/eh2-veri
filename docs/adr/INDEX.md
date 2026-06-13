# ADR Index

Date: 2026-05-12

This file is the canonical index for EH2 verification platform architecture
decision records.

The ADR filenames are uniquely numbered from `0001` through `0020`.

The historical audit called out duplicate ADR numbers in earlier drafts
(`0008`, `0010`, and `0014`). The current file set no longer has duplicate
filename prefixes:

```text
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010
0011 0012 0013 0014 0015 0016 0017 0018 0019 0020
```

Use the filename number as canonical when a legacy heading or older release note
uses an earlier draft number.

## Canonical ADR List

| ADR | File | Status | Summary |
|---:|---|---|---|
| 0001 | `0001-cosim-via-trace-and-probe.md` | Accepted | Defines the trace-packet plus DUT-probe cosim data path that replaces fragile writeback reconstruction. |
| 0002 | `0002-axi4-passive-monitoring.md` | Accepted | Chooses passive AXI4 monitoring and behavioral memory as the first EH2 bus strategy. |
| 0003 | `0003-num-threads-cosim-scope.md` | Accepted | Sets the original single-thread cosim sign-off boundary and documents NUM_THREADS constraints. |
| 0004 | `0004-rtl-rvfi-equivalent-trace.md` | Accepted | Adds verification-oriented retire fields to EH2 trace rather than forcing a full RVFI bus into design RTL. |
| 0005 | `0005-spike-cosim-store-wider-wstrb.md` | Accepted | Records the EH2 store wider-WSTRB handling accepted by the Spike cosim bridge. |
| 0006 | `0006-atomic-cosim.md` | Accepted | Documents A-subset atomic cosim fixups and the LR/SC/AMO verification direction. |
| 0007 | `0007-interrupt-cosim.md` | Accepted | Captures interrupt cosim closure strategy and Spike synchronization constraints. |
| 0008 | `0008-debug-cosim.md` | Accepted | Captures debug-mode cosim closure, including debug CSR and DRET-sensitive behavior. |
| 0009 | `0009-pmp-cosim.md` | Accepted | Captures PMP/ePMP cosim closure strategy and model boundaries. |
| 0010 | `0010-csr-register-model.md` | Accepted | Defines the EH2 CSR register model based on `uvm_reg` over `csr_desc_t`. |
| 0011 | `0011-compliance-framework.md` | Accepted | Documents the RISC-V compliance framework integrated into the sign-off profile. |
| 0012 | `0012-formal-strategy.md` | Accepted | Defines the multi-module formal verification strategy and property ownership. |
| 0013 | `0013-synthesis-toolchain.md` | Accepted | Records synthesis toolchain choices and the open-source versus commercial tradeoff. |
| 0014 | `0014-formal-real-runs.md` | Accepted | Records the transition from formal scaffolding to real formal runs and their limitations. |
| 0015 | `0015-rvfi-adapter-layer.md` | Accepted | Defines the RVFI adapter layer that avoids modifying upstream design RTL. |
| 0016 | `0016-multi-hart-cosim.md` | Accepted | Records the NUM_THREADS=2 cosim support path and per-hart Spike routing. |
| 0017 | `0017-integrity-cosim-waiver.md` | Accepted | Documents why integrity fault-injection tests remain cosim-disabled with formal waivers. |
| 0018 | `0018-wb-tag-strict-matching.md` | Accepted | Replaces asynchronous writeback `rd` heuristics with strict `wb_tag` association. |
| 0019 | `0019-lec-tool-version-limitation.md` | Accepted | Documents the Formality tool-version limitation that affected earlier top-level LEC runs. |
| 0020 | `0020-blocklevel-lec.md` | Accepted | Defines the R3-C block-level LEC closure path and packed-port mitigation. |

## Topic Map

Cosim data path:

- ADR-0001: trace plus probe data path.
- ADR-0004: retire trace fields.
- ADR-0018: strict writeback tag matching.

Bus and memory behavior:

- ADR-0002: AXI4 passive monitoring.
- ADR-0005: EH2 wider WSTRB handling.

ISA and architectural comparison:

- ADR-0006: atomic cosim.
- ADR-0007: interrupt cosim.
- ADR-0008: debug cosim.
- ADR-0009: PMP/ePMP cosim.
- ADR-0010: CSR model.
- ADR-0017: integrity waiver boundary.

Formal and RVFI:

- ADR-0012: formal strategy.
- ADR-0014: real formal runs.
- ADR-0015: RVFI adapter layer.

Synthesis and LEC:

- ADR-0013: synthesis toolchain.
- ADR-0019: LEC tool-version limitation.
- ADR-0020: block-level LEC closure.

Release integration:

- ADR-0011: compliance framework.
- ADR-0016: multi-hart cosim support.

## Numbering Policy

New ADRs must use the next available 4-digit prefix.

Do not reuse a number for a new topic.

Do not change an existing ADR filename after it has been referenced by release
notes or sign-off reports.

If a historical ADR heading contains a legacy number, prefer fixing references
through this index rather than rewriting old release notes.

If a future renumbering is unavoidable, update:

- `docs/adr/INDEX.md`;
- `CONTEXT.md`;
- active release notes;
- `docs/sphinx_cn/source/architecture_decisions.rst`;
- any sign-off or gate document that cites the ADR number.
