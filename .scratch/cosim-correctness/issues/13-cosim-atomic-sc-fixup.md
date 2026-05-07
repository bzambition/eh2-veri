# Issue 13: atomic / AMO cosim 闭环 — SC.W 写回 fixup

Status: ready-for-agent
Milestone: D — cosim hardening
Type: AFK / multi-session
Risk: MEDIUM-HIGH（要动 spike-cosim AMO 语义，非纯胶水）
Parent: docs/cosim-correctness-analysis.md — RISK-11
Blocked by: 无（与 Issue 11/12 独立可并行）

## What（要做什么）

让 `riscv_amo_test` 在 cosim 开启下跑过。当前 disabled 的根因：
EH2 RTL 对 `SC.W` 的成功/失败语义与 Spike 默认 amo 模型分歧 —
具体在 SC.W 失败路径上 RTL 写回 rd=1（失败码），Spike 默认写 rd=0
或反之，导致 GPR 一拍后即 mismatch。

需要做的工作：

1. **定位分歧**：在 `dv/cosim/spike_cosim_glue.cc` 加 amo 路径打点，
   对比一个最小 LR.W / SC.W 序列下 RTL 与 Spike 的 rd 值
2. **写 fixup hook**：spike_cosim 端为 SC.W 提供 `amo_post_step_fixup()`
   钩子，让 EH2 实现的具体码值生效（参考 ADR-0005 store wider WSTRB
   的 fixup 模式）
3. **同步 reservation set**：LR.W 之后 EH2 reservation 失效条件
   （context switch / 任意 store 命中同一 cache line）应在 cosim
   端模拟，目前完全没建模
4. **不要改 EH2 RTL**：fixup 永远站在 cosim 这边

## Why

CONTEXT.md RISK-11 当前 OPEN。`riscv_amo_test` 是 RV32A 的核心覆盖，
cosim 不通意味着 atomic 的 ISA 一致性**没有被验证**。
EH2 是 RV32**IMAC**，A 是必备扩展。

## Acceptance criteria

- [ ] 新建 ADR-0006-amo-cosim-fixup.md 记录 SC.W 成功/失败码与 reservation
      失效条件的设计契约
- [ ] `dv/cosim/spike_cosim_glue.cc` 增加 `amo_fixup` 路径，至少覆盖：
      LR.W / SC.W / AMOADD.W / AMOSWAP.W
- [ ] testlist.yaml 把 `riscv_amo_test` 的 `cosim: disabled` 移除
- [ ] 至少 3 个 seed 在 cosim 开启下 mismatch_count == 0
- [ ] 写一条 directed `asm/cosim_amo.S`：先 LR/SC 成功一次，再被
      context-switch 打断后 SC 失败一次 — 两次 cosim 都过
- [ ] `make signoff SIGNOFF_PROFILE=full PARALLEL=4` 仍 PASS
- [ ] 关闭本 issue 时把 RISK-11 在 CONTEXT.md 中状态改为 `已修`

## Non-goals

- 不动 EH2 RTL 的 LSU AMO 路径（fixup 永远只在 spike-cosim 侧）
- 不改其它 RV32A 子集（LR.D / SC.D 不在 EH2 scope）

## References

- ADR-0005-spike-cosim-store-wider-wstrb.md — 历史 fixup 模式范本
- `vendor/google_riscv-dv/yaml/base_testlist.yaml` 中 amo test 模板
- `rtl/design/lsu/eh2_lsu_*.sv` — EH2 SC.W 实际写回路径（**只读，不改**）
- spike-cosim 上游：`/home/host/spike-cosim/riscv/` — amo 实现位置

## Risk / review checkpoint

⚠️ amo fixup 涉及 cosim 端的 reservation state 机器，写错会污染所有
load/store 路径。建议：

1. commit A：仅加打点 + ADR，不改语义，跑现有 32/32 验回归
2. commit B：上 fixup，先单独跑 cosim_amo.S，再跑 riscv_amo_test
3. commit C：解锁 testlist + sign-off

任意一步既有 PASS 项 mismatch++ 立即停下回退。
