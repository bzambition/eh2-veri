# Issue 15: cosim:disabled 全量清零（D 路线总跟踪）

Status: ready-for-agent
Milestone: D — cosim hardening
Type: AFK / multi-session / meta
Risk: 见各子 issue
Parent: docs/cosim-correctness-analysis.md — RISK-1 / 9 / 10 / 11

## What（要做什么）

跟踪 D 路线（cosim:disabled 名单逐项收编）整体进度。本 issue 不
直接落代码，仅做：

- 维护下面四个子 issue 的状态视图
- 每次某子 issue 关闭后跑一次 `make signoff SIGNOFF_PROFILE=full
  PARALLEL=4`，归档 `signoff_status.json` 到
  `.scratch/cosim-correctness/snapshots/`
- 在 CONTEXT.md "Sign-off 标准"一节追加 cosim_disabled 数量行
- 当四个子 issue 全部 done 时，在 README "Known limitations"
  里把 RISK-1/9/10/11 那几行删掉，并在 ADR-0007 中记录"cosim
  scope 扩展到完整 riscv-dv 套件"

## 子 issue 列表

| Issue | RISK | 范围 | 风险 | 推荐先后 |
|-------|------|------|------|---------|
| 11    | RISK-9  | 中断/异常 scoreboard 同步（10 个 test） | HIGH（动 scoreboard 主路径） | 第二步 |
| 12    | RISK-10 | bitmanip / Zb* ISA 扩展（1 个 test）   | MEDIUM（动 spike ISA 字符串）| **可先做** |
| 13    | RISK-11 | atomic / SC.W fixup（1 个 test）       | MEDIUM-HIGH（动 spike amo） | 第三步 |
| 14    | RISK-1  | EH2 自定义 CSR + PMP fixup（20+ test） | MEDIUM（量大，单点风险低）  | 可与 12 并行 |

## Acceptance criteria（D 路线总闭合）

- [ ] 子 issue 11 / 12 / 13 / 14 全部 status: done
- [ ] `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml` 中
      `cosim: disabled` 行数 ≤ 5（仅保留 multi-hart / wontfix 类）
- [ ] `signoff_report.md` 的 `cosim_disabled_tests` 段长度 ≤ 5
- [ ] CONTEXT.md RISK-1 / 9 / 10 / 11 全部状态 `已修`
- [ ] 新增 ADR-0007-cosim-scope-expansion.md 记录扩展后的 cosim 契约
- [ ] 一次完整 `make signoff SIGNOFF_PROFILE=full PARALLEL=4` PASS，
      归档为 `build/sf_full_d_complete/`

## 给 codex 的执行指引

- 这 4 个子 issue **不必串行**：12 与 14 互不冲突可并行；11 与 13
  各自动 scoreboard / spike，建议串行避免合并冲突
- 每个子 issue 完成后**强制跑一次完整 sign-off** 才能判 done，不能
  只跑被解锁的几个 test
- 任意一个子 issue 让既有 PASS bank 出现 mismatch_count > 0 立刻停
  下回报，**不准用 waiver 绕过** — 这是整条 D 路线的语义底线
- 每关闭一个子 issue，刷新本 issue 的子 issue 状态表

## References

- `.scratch/cosim-correctness/issues/11-cosim-interrupt-exception-scoreboard.md`
- `.scratch/cosim-correctness/issues/12-cosim-bitmanip-zb-extensions.md`
- `.scratch/cosim-correctness/issues/13-cosim-atomic-sc-fixup.md`
- `.scratch/cosim-correctness/issues/14-cosim-eh2-csr-warl-fixup.md`
- `build/sf_full2/signoff_report.md` — 当前 cosim_disabled 名单（34 项）的基线
