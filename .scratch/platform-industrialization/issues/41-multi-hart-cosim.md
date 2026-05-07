# Issue: 多 hart Spike cosim

Status: ready-for-agent
Milestone: Phase 5
Type: AFK / multi-session
Risk: HIGH (architectural)

## What

EH2 是双线程核（NUM_THREADS=2 配置），但当前 cosim 只支持
NUM_THREADS=1。`dual_thread` profile 必须 `+disable_cosim=1` 才能跑，
sign-off 因此对 dual_thread 没有 ISA 一致性保证。

## Why

Spike 的 sim_t 已经支持多 hart（`processor_t * procs_[]`），但
EH2 cosim glue 假定单 hart：
- `riscv_cosim_step` 只 step proc[0]
- async_wb_q 是单队列（不区分 hart）
- mip / mcycle 注入不带 hart_id

## Acceptance

- [ ] `riscv_cosim_step` 接受 hart_id 参数，路由到对应 proc
- [ ] dut_probe / trace_monitor 信号扩展为 per-thread 数组
- [ ] scoreboard 的 pending_trace_q / async_wb_q / pending_lsu_q 拆 per-hart
- [ ] dual_thread profile smoke 100% PASS（cosim enabled）
- [ ] 单 thread cosim 9/9 sweep 不破

## References

- Spike `simif_t::get_harts()` API
- Ibex 是单核，无类似先例 — 全新实现
- `dv/cosim/spike_cosim.cc` — DPI binding 当前位置
- `rtl/snapshots/dual_thread/common_defines.vh` — dual_thread RTL 配置
- ADR-0003（NUM_THREADS scope 决策）

## Risk

- 接口变更 → trace_intf / probe_intf 信号阵列化 → 编译影响面大
- 性能：双 hart 对应 2x trace queue + 2x cosim step，scoreboard 速率影响
- mcycle 在 dual hart 是共享还是 per-hart 计数 — 需查 EH2 RTL

## Estimate

3-5 days dedicated work.
