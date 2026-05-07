# Issue: AXI4 active driver — error injection wiring

Status: ready-for-agent
Milestone: Phase 5
Type: AFK / multi-session

## What

`dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv` exists as a stub:
config fields (`enable_error_inject` / `error_pct` / `enable_delay_inject`)
and helper functions (`should_inject_error` / `get_error_resp`) are in
place, but the driver is **not instantiated anywhere**. `run_phase` active
mode is a no-op loop. No sequencer connection. No TB binding.

## Why

EH2's sign-off coverage requires AXI4 fault injection (SLVERR / DECERR
on read/write) to exercise the bus-error trap path in mtvec/mcause/mtval.
Currently this path is only reachable through directed `mem_error_test`,
which is itself `cosim: disabled`.

## Acceptance

- [ ] Active driver subclass takes precedence over `axi4_slave_mem` when
      `enable_error_inject` is set (env_cfg flag)
- [ ] At least one new test (`riscv_axi4_error_inject_test`) injects 5%
      SLVERR/DECERR and confirms DUT enters mcause=5/7 trap handler
- [ ] Existing 9/9 cosim sweep still PASS (driver does nothing in default
      passive mode)
- [ ] tb_top binds the driver vif; env wires sequencer; default
      configuration leaves it disabled

## Non-goals

- Not modeling AXI back-pressure or out-of-order responses (separate issue)
- Not switching the entire memory model away from RTL `axi4_slave_mem`

## References

- Ibex pattern: `ibex_mem_intf_response_driver` in
  `/home/host/ibex/dv/uvm/core_ibex/common/ibex_mem_intf_agent`
- Existing stub: `dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv`
- AXI4 monitor: passive monitor already collects all transactions; the
  active driver should *replace* the RTL slave's responses, not augment them
- Memory model: `dv/uvm/core_eh2/common/axi4_agent/axi4_slave_mem.sv` is
  the current default responder

## Risk

- Active driver and RTL slave responding to the same channel will race
  → must gate slave_mem off when driver is active
- 5% error rate may fire during init (early boot loads) → consider
  windowing error injection to `post_initial_pc` time
