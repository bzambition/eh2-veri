# Issue 11: 中断/异常 cosim 闭环 — scoreboard 同步 mcause/mepc/mtval

Status: ready-for-agent
Milestone: D — cosim hardening
Type: AFK / multi-session
Risk: HIGH（改 scoreboard 主路径，可能回归既有 PASS bank）
Parent: docs/cosim-correctness-analysis.md — RISK-9
Blocked by: 无（Phase 5 sign-off 已 PASS，可独立推进）

## What（要做什么）

把 `riscv_random_instr_test`、`riscv_interrupt_test`、`riscv_irq_single_test`、
`riscv_irq_wfi_test`、`riscv_irq_csr_test`、`riscv_irq_nest_test`、
`riscv_irq_in_debug_test`、`riscv_debug_in_irq_test`、
`riscv_exception_stream_test`、`riscv_breakpoint_test` 这一组**中断/异常类**
test 从 `riscv_dv_extension/testlist.yaml` 的 `cosim: disabled` 列表里
拆出来，让它们在 cosim 开启的情况下能跑过 mismatch_count == 0。

核心是 cosim_scoreboard 在收到 trace 包时，对中断/异常路径的处理：

1. `interrupt-only trace item`（trace_pkt.interrupt=1, exception=0）：
   - DUT 表示该 PC 处的指令**没有执行**，仅作为中断通知
   - Spike 不调 `step()`，仅 `set_mip()` 注入对应中断位
   - mtvec / mepc / mcause / mtval 在下一拍由 Spike 自己处理

2. `exception trace item`（trace_pkt.exception=1）：
   - DUT 已写入 mcause/mepc/mtval，trace_pkt.tval / ecause 字段携带值
   - Spike step 后比对 mcause/mepc/mtval 寄存器值
   - 不一致时 mismatch++

3. nested IRQ / debug-in-irq：
   - 需要在 mip / dcsr.step / dpc 写入时通过 `set_csr` 同步到 Spike

## Why（为什么值得做）

CONTEXT.md RISK-9 当前 OPEN。`signoff_report.md` 自己声明：上述测试
"must remain waiver-reviewed for final closure" — 也就是说当前 sign-off
PASS **不覆盖中断 / 异常的 ISA 一致性**，这是最大的语义缺口。

## Acceptance criteria

- [ ] `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv` 新增/扩展
      `compare_interrupt_only_item()` 与 `compare_exception_item()` 路径，
      每类至少一条 UVM_HIGH log line（便于回归审计）
- [ ] `eh2-csr-categories.svh` 中 `mip / mcause / mepc / mtval / mstatus.mie`
      列入 cosim 同步集合（`set_csr` 或 fixup hook）
- [ ] testlist.yaml 把上述 10 个中断/异常 test 的 `cosim: disabled` 移除
- [ ] `make signoff SIGNOFF_PROFILE=full PARALLEL=4` 仍 PASS（不能破现有 32/32）
- [ ] 新建 directed test `asm/cosim_interrupt.S` 覆盖最小 timer IRQ + 嵌套 IRQ
      场景，单跑 cosim 路径 mismatch_count == 0
- [ ] PROGRESS 记录：本 issue 关闭时把 RISK-9 在 CONTEXT.md 中状态改为 `已修`

## Non-goals

- 不修 multi-hart cosim（NUM_THREADS=2 仍然 disable_cosim，归 Issue 41）
- 不接 PIC 127 路全量 IRQ — 只覆盖 timer / external / software 三类基础源

## References

- `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
  当前中断处理：搜索 `interrupt` 关键字，会看到只 set_mip，没比对 mcause/mepc
- Ibex 对应实现：`/home/host/ibex/dv/uvm/core_ibex/common/cosim_agent/`
- ADR-0001 cosim via trace and probe（设计契约不能动）
- `docs/cosim-correctness-analysis.md` Section RISK-9

## Risk / 必要的 review checkpoint

⚠️ **必须设 review checkpoint**：scoreboard 主路径改动历史踩过 wb_seq /
div_cancel 这种坑（Phase 1 修了一次）。建议拆成两次提交：

1. commit A：纯加 compare 路径 + log，**不改 testlist**，跑现有 32/32 验回归
2. commit B：testlist.yaml 解锁中断类 test，跑 sign-off 验真闭环

任何一次 mismatch_count > 0 直接停下，**不准用 waiver 绕过** — 这是中断
ISA 一致性的核心。

## 拆分 / 后续 issue

完成本 issue 不会自动闭合 RISK-1 / 10 / 11，那些有独立 issue（12 / 13 / 14）。
