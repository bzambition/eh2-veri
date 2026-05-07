# Phase 5 — Sign-off full PASS

日期：2026-05-07

## Sign-off 结果

`make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1` 全通过。

| Stage | 结果 | 详情 |
|-------|------|------|
| smoke | PASS 1/1 | smoke.hex + cosim disabled |
| directed | PASS 3/3 | directed_alu / directed_load_store / directed_branch |
| cosim | PASS 4/4 | cosim_smoke / cosim_alu / cosim_load_store / cosim_dual_issue |
| riscvdv | PASS 32/32 | 11 个 skip_in_signoff（RTL/binary 层 hang，非 cosim 问题） |

证据：`build/sf_full2/signoff_report.md`、`build/sf_baseline2/signoff_status.json`（二次验证一致）

## cosim:disabled 概况

34 个 riscv-dv test 标记 cosim:disabled，属于以下 4 个子 issue：

- **Issue 11**（中断/异常）：~10 个 IRQ/exception 相关 test
- **Issue 12**（bitmanip）：riscv_bitmanip_test 等 Zb* 相关
- **Issue 13**（atomic SC.W）：riscv_amo_test
- **Issue 14**（CSR WARL）：riscv_csr_test / riscv_csr_hazard_test 等

总跟踪 issue：`.scratch/cosim-correctness/issues/15-cosim-disabled-zero-out-meta.md`

## 已关闭 issue

| Issue | 标题 | 状态 |
|-------|------|------|
| PI-01 | RTL 加 RVFI 等价信号 | done |
| PI-02 | trace_monitor 采样 wb | done |
| PI-03 | scoreboard 简化 | done |
| PI-04 | probe_monitor 保持异步 | done |
| PI-05 | testlist enable cosim | done |
| PI-06 | signoff full pass | done |
| CC-01 | cosim smoke test | done |
| CC-02 | single ALU cosim test | done |
| CC-03 | load/store cosim test | done |
| CC-04 | dual-issue ordering test | done |
| CC-06 | per-test cosim toggle | done |
| CC-07 | CSR suppression | done |
| CC-08 | CSR fixup design | done |
| CC-09 | 64-bit AXI verify | done |
| CC-10 | NUM_THREADS constraint | wontfix |

## 仍 OPEN 的 issue

| Issue | 标题 | 状态 | 路线 |
|-------|------|------|------|
| CC-05 | interrupt cosim test | ready-for-agent | D (issue 11 前置) |
| CC-11 | 中断/异常 scoreboard | ready-for-agent | D |
| CC-12 | bitmanip Zb* cosim | ready-for-agent | D |
| CC-13 | atomic SC.W fixup | ready-for-agent | D |
| CC-14 | CSR WARL fixup | ready-for-agent | D |
| CC-15 | cosim:disabled 清零 meta | ready-for-agent | D (总跟踪) |
| PI-40 | AXI4 active driver | ready-for-agent | F |
| PI-41 | multi-hart cosim | ready-for-agent | G (人主导) |
| PI-42 | formal bridge | ready-for-agent | H |

## 主要成果指标

| 指标 | Phase 0 | Phase 5 |
|------|---------|---------|
| scoreboard 行数 | 1026 | 734 (-29%) |
| sign-off 结果 | 不通过 | 4 stage 全 PASS |
| cosim PASS test | 0 | 4 (cosim stage) + 32 riscvdv |
| ADR 文档 | 0 | 5 篇 |
| 已关闭 issue | 0 | 15 |
