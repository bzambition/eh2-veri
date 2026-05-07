# Issue 12: bitmanip / Zb* cosim 闭环 — Spike illegal-instr 速率匹配

Status: ready-for-agent
Milestone: D — cosim hardening
Type: AFK / multi-session
Risk: MEDIUM（不动 scoreboard 主路径，主要修 spike fixup + testlist）
Parent: docs/cosim-correctness-analysis.md — RISK-10
Blocked by: 无（与 Issue 11 互不依赖，可并行）

## What（要做什么）

让 `riscv_bitmanip_test`（Zba / Zbb / Zbc / Zbs）在 cosim 开启下跑过。
当前 cosim disabled 的根因是：DUT 触发 illegal-instr 异常的速率与
Spike 的步进速率对不上 — Spike 在收到 trace_pkt 之前/之后多 step
一拍，导致 PC 越界 / mcause 不一致。

可能的修复方向（按 ROI 排序，二选一）：

A. **Spike 端开 Zba/Zbb/Zbc/Zbs ISA 扩展**（首选）
   - `dv/cosim/spike_cosim_glue.cc` 中构造 `processor_t` 时 `--isa=rv32imac_zba_zbb_zbc_zbs`
   - 验证 spike-cosim 的 disasm/exec 表已包含 bitmanip opcode
   - 验证后大部分原本"illegal-instr 速率不匹配"会消失，因为 Spike 也合法执行

B. **若 Spike 不支持 EH2 实现的特定 Zb 子集**：把不支持的 opcode 在
   trace_monitor 入队前过滤掉，转 `compare_skip_item()` 路径，并在
   PROGRESS 中记录为已知差异 + scope-skip waiver

## Why

CONTEXT.md RISK-10 当前 OPEN。bitmanip 是 EH2 RV32IMAC + Zb* 的核心
扩展，cosim 不通意味着 Zb* 指令的 ISA 一致性当前**没有被验证**，
只测了"DUT 不崩溃"。

## Acceptance criteria

- [ ] `riscv_bitmanip_test` 在 testlist.yaml 中 `cosim: disabled` 移除
- [ ] 该 test 至少 3 个 seed 在 cosim 开启下 mismatch_count == 0
- [ ] 若选方案 A：`build/libcosim.so` 支持的 ISA 字符串日志可见包含
      `zba/zbb/zbc/zbs`，新增一条 unit log 验证
- [ ] 若选方案 B：被过滤的 opcode 列入 PROGRESS 文档与 ADR-0006，且
      不超过总 trace 量的 5%
- [ ] `make signoff SIGNOFF_PROFILE=full PARALLEL=4` 仍 PASS
- [ ] 关闭本 issue 时把 RISK-10 在 CONTEXT.md 中状态改为 `已修`

## Non-goals

- 不修 atomic / amo cosim（归 Issue 13）
- 不在 directed_tests 写 bitmanip 定向 — 复用 riscv_dv 生成即可

## References

- `dv/cosim/spike_cosim_glue.cc` — Spike processor 构造
- `vendor/google_riscv-dv/yaml/base_testlist.yaml` — bitmanip test 模板
- `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml` — 当前 cosim:disabled 行
- spike-cosim 上游：`/home/host/spike-cosim/` 是仓库内副本

## Risk / review checkpoint

⚠️ 方案 A 改 ISA 字符串可能让某些 EH2 自定义指令在 Spike 端被错误
"识别"。建议先在 dry-run 下跑 1 个 seed，diff 一下与 disable 时的
trace 行为，再正式开。
