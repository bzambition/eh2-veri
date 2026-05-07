# Issue 14: EH2 自定义 CSR 全量同步 — set_csr 静态注册到 WARL fixup

Status: ready-for-agent
Milestone: D — cosim hardening
Type: AFK / multi-session
Risk: MEDIUM（量大但单点风险低，每个 CSR 独立）
Parent: docs/cosim-correctness-analysis.md — RISK-1
Blocked by: 无（与 Issue 11/12/13 独立可并行）

## What（要做什么）

EH2 有 18+ 个自定义 CSR（`mscause / mrac / mfdc / meivt / meipt /
mip / mie / meihap / dmst / dicawics / dicad0 / dicad1 / dicad0h /
dicago / mcgc / mfdht / mfdhs / micect / mfdc / mcountinhibit /
mvendorid_eh / marchid_eh` 等）。当前状态（Phase 3）：

- 已做：28 个 CSR 通过 `set_csr` **静态注册**（trace 上看到 csr 写时
  把 RTL 写入值同步给 Spike）
- 未做：没有 **WARL fixup** — 即 Spike 自己 step 时若产生与 EH2
  WARL 行为不同的写值，cosim 不会修正它

**目标**：把"写时静态同步"升级为"读/写时双向 WARL fixup"，覆盖
`riscv_csr_test / riscv_csr_hazard_test / riscv_invalid_csr_test`
等 CSR 类 test 的 cosim 路径。

具体工作：

1. **梳理 EH2 CSR WARL 表**：从 RTL `eh2_dec_decode_ctl.sv` 中
   抽出每个自定义 CSR 的 mask 与 reset value，登记在新建的
   `dv/cosim/eh2_csr_warl_table.h`
2. **在 spike_cosim_glue 中实现 fixup hook**：每次 Spike 写 CSR
   后，按 WARL 表 mask 一次（`written = (written & mask) | (cur & ~mask)`）
3. **read fixup**：对 EH2 特殊行为（如读 mcountinhibit 返回的位）
   也做 fixup
4. **从 cosim:disabled 移除**：`riscv_csr_test`、`riscv_csr_hazard_test`、
   `riscv_invalid_csr_test`、`riscv_pmp_basic_test`、`riscv_pmp_random_test`、
   `riscv_pmp_disable_all_test`、`riscv_epmp_mml/mmwp/rlb_test`、
   `riscv_pc_intg_test`、`riscv_rf_intg_test`、`riscv_reset_test`、
   `riscv_single_step_test` —— **CSR 相关一组**

## Why

CONTEXT.md RISK-1 列为"部分缓解"。`signoff_report.md` 的 cosim
disabled 名单里 CSR/PMP/Debug 类占了 **20 项以上**，是 disabled
名单里最大的一类。

## Acceptance criteria

- [ ] `dv/cosim/eh2_csr_warl_table.h` 至少覆盖 18 个 EH2 自定义 CSR
      的 mask/reset，每个 CSR 给出 RTL 行号引用
- [ ] `spike_cosim_glue.cc` 增加 `eh2_csr_warl_fixup()` 钩子
- [ ] testlist.yaml 上述 CSR/PMP 类 test 至少 5 个 cosim 解锁
- [ ] 解锁的每个 test 至少 3 seed mismatch_count == 0
- [ ] 写一条 directed `asm/cosim_eh2_csr.S`：连续读写 mscause / mrac /
      mfdc，cosim 路径 mismatch_count == 0
- [ ] `make signoff SIGNOFF_PROFILE=full PARALLEL=4` 仍 PASS
- [ ] 关闭本 issue 时 CONTEXT.md RISK-1 状态改为 `已修`

## Non-goals

- 不修 multi-hart 的 per-thread CSR 视图（归 Issue 41）
- debug-mode 专属 CSR（dcsr / dpc / dscratch0/1）由 RISK-9 / Issue 11
  的中断闭环顺带覆盖，本 issue 不重复做
- 不动 RTL — fixup 永远只在 cosim 这边

## References

- 现有 set_csr 列表：`dv/cosim/eh2_csr_setup.cc`（28 项）
- WARL 行为：`rtl/design/dec/eh2_dec_decode_ctl.sv`
- ADR-0001 cosim via trace and probe — CSR 责任边界

## Risk / review checkpoint

按 CSR 分组分批提 commit，每组完成后跑一次 32/32 回归：

1. commit A：WARL 表 + fixup hook 框架，**不改 testlist**
2. commit B：CSR 类（mscause/mrac/mfdc/...）解锁 + 验证
3. commit C：PMP 类解锁 + 验证
4. commit D：完整 sign-off

每一步出现既有 PASS 项 mismatch++ 直接停下回退。
