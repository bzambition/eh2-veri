# Issue 01: Cosim smoke test: init + hello_world

Status: needs-triage
Milestone: 1 - Minimal cosim loop
Type: AFK

## Parent

docs/cosim-correctness-analysis.md -- Section 10, Test 1

## What to build

Create a cosim smoke test that verifies the full Spike co-simulation data path works end-to-end: Spike initializes via DPI, binary loads into cosim memory, the DUT executes hello_world.hex, and at least one Spike step completes without fatal error.

The test must:
1. Run `core_eh2_cosim_test` with `+enable_cosim=1`
2. Use `hello_world.hex` from `rtl/testbench/hex/`
3. Check simulation log for cosim report (step_count > 0)
4. Report PASS/FAIL based on mailbox AND cosim step completion

## Acceptance criteria

- [ ] `make run TEST=core_eh2_cosim_test BINARY=<hello_world.hex>` completes without UVM_FATAL
- [ ] Simulation log contains "Co-simulation Scoreboard Report"
- [ ] `step_count > 0` in cosim report
- [ ] Mailbox PASS (0xFF at 0xD0580000) is detected
- [ ] No Spike init failure (`cosim_handle != null`)

## Blocked by

None - can start immediately
