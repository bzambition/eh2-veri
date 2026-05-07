# Issue 10: Document NUM_THREADS=1 constraint; file NUM_THREADS=2 blocking issue

Status: needs-triage
Milestone: 2 - Testlist and suppression infrastructure
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 9, RISK-4

## What to build

Document the current limitation that Spike co-simulation only supports NUM_THREADS=1 (single hart). Add clear documentation in:
1. `docs/cosim-correctness-analysis.md` -- already has Section 9, verify it's complete
2. `README.md` or equivalent -- add a "Known Limitations" section
3. `eh2_configs.yaml` -- add a comment on `dual_thread` config noting cosim is not supported
4. `testlist.yaml` -- any test that requires NUM_THREADS=2 should have `cosim: disabled`

Also file a tracking issue for the NUM_THREADS=2 blocking item with the design options from Section 9.3.

## Acceptance criteria

- [ ] NUM_THREADS=1 cosim constraint documented in README or equivalent
- [ ] `eh2_configs.yaml` `dual_thread` entry has cosim limitation comment
- [ ] All NUM_THREADS=2 tests in testlist have `cosim: disabled`
- [ ] Tracking issue for NUM_THREADS=2 multi-hart SpikeCosim filed

## Blocked by

None - can start immediately
