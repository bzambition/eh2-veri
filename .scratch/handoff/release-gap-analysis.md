# EH2 验证平台 Release 差距分析

对标：lowRISC Ibex 验证平台 (`/home/host/ibex/dv/uvm/core_ibex/`)
生成日期：2026-05-08

---

## 1. Cosim 覆盖率

### 现状

| 维度 | EH2 | Ibex |
|------|-----|------|
| riscv-dv 总测试数 | 43 | 57 |
| cosim:disabled | **34** (79%) | **1** (riscv_csr_test, `disable_cosim=1`) |
| cosim 已启用 | 9 | 56 |
| 定向 cosim disabled | 2 (directed_csr_warl, directed_axi4_error_inject) | 0 |

### 34 个 cosim:disabled 分级

**BLOCKER — 核心功能路径，release 前必须解锁**

| 测试 | 原因 | 对应 RISK |
|------|------|-----------|
| riscv_random_instr_test | 中断/异常 cosim 不支持（RISK-9） | RISK-9 |
| riscv_interrupt_test | 中断 cosim | RISK-9 |
| riscv_irq_single_test | 中断 cosim | RISK-9 |
| riscv_irq_wfi_test | 中断 cosim | RISK-9 |
| riscv_irq_csr_test | 中断 cosim | RISK-9 |
| riscv_irq_nest_test | 中断 cosim | RISK-9 |
| riscv_exception_stream_test | 异常 cosim | RISK-9 |

**SHOULD-HAVE — 重要但可做 known limitation release**

| 测试 | 原因 | 对应 RISK |
|------|------|-----------|
| riscv_bitmanip_test | Zba/Zbb illegal-instr 异常率高（RISK-10） | RISK-10 |
| riscv_amo_test | SC.W 写回分歧（RISK-11） | RISK-11 |
| riscv_debug_test | 调试模式 cosim | — |
| riscv_debug_csr_test | 调试 CSR cosim | — |
| riscv_debug_wfi_test | 调试 + WFI cosim | — |
| riscv_debug_during_csr_test | 调试 + CSR cosim | — |
| riscv_debug_ebreak_test | EBREAK cosim | — |
| riscv_debug_ebreakmu_test | ebreakm/u cosim | — |
| riscv_single_debug_pulse_test | 调试脉冲 cosim | — |
| riscv_debug_in_irq_test | 调试 + 中断交互 | — |
| riscv_irq_in_debug_test | 中断 + 调试交互 | — |
| riscv_dret_test | DRET cosim | — |
| riscv_csr_test | CSR cosim | — |
| riscv_csr_hazard_test | CSR 流水线冲突 | — |

**NICE-TO-HAVE — 安全/鲁棒性测试，可 post-release**

| 测试 | 原因 |
|------|------|
| riscv_pmp_basic_test | PMP cosim |
| riscv_pmp_disable_all_test | PMP cosim |
| riscv_pmp_random_test | PMP cosim |
| riscv_epmp_mml_test | ePMP cosim |
| riscv_epmp_mmwp_test | ePMP cosim |
| riscv_epmp_rlb_test | ePMP cosim |
| riscv_pc_intg_test | 完整性注入 cosim |
| riscv_rf_intg_test | 完整性注入 cosim |
| riscv_mem_error_test | 内存错误注入 cosim |
| riscv_stress_test | 综合压力 cosim |
| riscv_breakpoint_test | 断点 cosim |
| riscv_reset_test | 复位 cosim |
| riscv_single_step_test | 单步 cosim |

---

## 2. Sign-off Gate 完整性

| 维度 | EH2 | Ibex | 差距 |
|------|-----|------|------|
| Stage 数量 | 4 (smoke/directed/cosim/riscvdv) | 无统一 sign-off 脚本，靠 CI pipeline 组合 | EH2 有优势 |
| 覆盖率 gate | signoff.py 已实现 `--coverage` / `--min-*-coverage` 参数框架 | `merge_cov.py` + `get_fcov.py` 独立脚本 | 对等 |
| 覆盖率 gate 启用 | **未启用**（默认阈值全 0.0，`--require-coverage` 默认 false） | CI 中可选启用 | **SHOULD-HAVE** |
| Profile 层级 | quick/cosim/nightly/full | 按 test 分组跑 | 对等 |

### 差距

- **[SHOULD-HAVE]** EH2 signoff.py 的覆盖率 gate 代码已写好但阈值全为 0，release 前应设置最低 line/branch/functional coverage 阈值并在 `full` profile 中启用 `--require-coverage`
- **[NICE-TO-HAVE]** Ibex 有 `merge_cov.py` 做跨 test 覆盖率合并 + HTML 报告，EH2 无独立 merge 脚本

---

## 3. 功能覆盖率（fcov）

| 文件 | EH2 (行数) | Ibex (行数) | 比例 |
|------|------------|------------|------|
| fcov_if.sv | 797 | 854 | 93% |
| pmp_fcov_if.sv | **285** | **854** | **33%** |
| fcov_bind.sv | 703 B | 422 B | 正常 |
| csr_categories.svh | 1485 B | 2722 B | 适配差异 |
| cov_waivers/ | 有 (3 yaml + 1 sv) | 无 | EH2 有优势 |

### 差距

- **[BLOCKER]** `eh2_pmp_fcov_if.sv` 仅 285 行 vs Ibex 854 行（仅 33%），PMP 功能覆盖点严重不足
- **[SHOULD-HAVE]** fcov 未接入 sign-off gate（见 §2，`--require-coverage` 未启用）
- **[NICE-TO-HAVE]** 无 `cov_testlist.yaml`（Ibex 有 `riscv_instr_cov_test` 从 trace 采样覆盖率）

---

## 4. CI/CD 流水线

| 维度 | EH2 | Ibex | 差距 |
|------|-----|------|------|
| CI 配置数 | 2 (sim.yml + unit-tests.yml) | 4 (ci.yml + ci-formal.yml + pr_lint.yml + private-ci.yml) | — |
| RTL 仿真 CI | sim.yml (self-hosted, VCS, 手动/label 触发) | ci.yml (push/PR 自动触发) | **SHOULD-HAVE** |
| Lint/格式检查 | 无 | Verible lint + clang-format | **SHOULD-HAVE** |
| Formal CI | 无 | ci-formal.yml | **NICE-TO-HAVE** |
| Python 单元测试 | unit-tests.yml (push/PR 自动) | — | EH2 有优势 |
| YAML 校验 | unit-tests.yml 内含 | — | EH2 有优势 |
| 自动触发 | sim.yml 仅手动/label | ci.yml 每 PR 自动跑 | **SHOULD-HAVE** |

### 差距

- **[SHOULD-HAVE]** sim.yml 未在每次 PR 自动触发（需 self-hosted runner），应至少在 nightly schedule 自动运行
- **[SHOULD-HAVE]** 无 Verilog lint CI gate（Ibex 用 Verible）
- **[NICE-TO-HAVE]** 无 formal CI workflow

---

## 5. 测试数量与多样性

### 数量对比

| 类型 | EH2 | Ibex | 差异 |
|------|-----|------|------|
| riscv-dv tests | 43 | 57 | -14 |
| directed tests (yaml) | 9 | 942 (含大量 PMP 排列) | -933 |
| directed test ASM 文件 | 12 (.S) | 4 (.S) | +8 |
| cosim proof tests | 5 | 0 (Ibex cosim 全隐式) | +5 |
| 总 iterations (riscv-dv) | ~278 | ~1797 | -1519 |

### 39 个 Ibex 有 EH2 无的测试

**BLOCKER 级（核心验证能力缺失）**

| 缺失测试 | 重要性 |
|----------|--------|
| riscv_rand_instr_test | Ibex 版带 CSR 写 + sub-program，EH2 的 random_instr 不等价 |
| riscv_machine_mode_rand_test | M 模式随机 |
| riscv_illegal_instr_test | 非法指令处理 |
| riscv_debug_basic_test | 调试基础（Ibex 用 signature_addr 校验） |
| riscv_debug_stress_test | 调试压力 |
| riscv_debug_single_step_test | 单步调试 |
| riscv_nested_interrupt_test | 嵌套中断 |

**SHOULD-HAVE 级**

| 缺失测试 | 重要性 |
|----------|--------|
| riscv_user_mode_rand_test | U 模式验证 |
| riscv_umode_tw_test | U 模式 WFI trap |
| riscv_pmp_full_random_test | PMP 全随机 (600 iter) |
| riscv_pmp_out_of_bounds_test | PMP 越界 |
| riscv_assorted_traps_interrupts_debug_test | 混合陷入压力 |
| riscv_ebreak_test | EBREAK 异常 |
| riscv_hint_instr_test | HINT 指令 |
| riscv_jump_stress_test | 跳转压力 |
| riscv_loop_test | 循环指令 |
| riscv_mmu_stress_test | 内存子系统压力 |

**NICE-TO-HAVE 级**

| 缺失测试 | 说明 |
|----------|------|
| riscv_bitmanip_full/balanced/otearlgrey_test | 多 B-ext 配置（EH2 有单一 bitmanip_test） |
| riscv_rv32im_instr_test | 无压缩指令 |
| riscv_mem_intg_error_test | 内存完整性 |
| riscv_icache_intg_test | ICache 完整性（Ibex SecureIbex 特有） |
| riscv_rf_addr_intg_test / riscv_ram_intg_test | SecureIbex 特有 |
| riscv_pmp_region_exec_test / riscv_epmp_mml_*_test | ePMP 变体 |
| riscv_debug_triggers_test / riscv_debug_branch_jump_test / riscv_debug_instr_test | 高级调试 |

### Ibex 无 EH2 有（EH2 特有验证）

EH2 独有 25 个测试，包含 dual_issue_test、amo_test、csr_hazard_test、exception_stream_test 等，这些是 EH2 双发射架构特有验证点。

### 额外 DV 组件

| 组件 | Ibex | EH2 |
|------|------|-----|
| CS Registers DV | 有 (独立 TB) | **无** — NICE-TO-HAVE |
| ICache DV | 有 (独立 UVM env) | **无** — NICE-TO-HAVE |
| Directed PMP 排列组合 | 942 测试 | 3 测试 — **SHOULD-HAVE** |

---

## 6. 文档完整性

| 维度 | EH2 | Ibex |
|------|-----|------|
| 领域语境 | CONTEXT.md (169 行，持续更新) | README.md (简要) |
| 架构决策 | 5 篇 ADR (0001-0005) | 无 ADR |
| Sphinx 文档 | docs/sphinx_cn/ (有 source + build) | doc/ (4 章, 35 个 .rst 文件) |
| Phase 报告 | 有 (doc/phase_reports/) | 无 |
| DV README | dv/uvm/core_eh2/ 无独立 README | 有 README.md |
| 实现总结 | doc/实现总结.md | — |
| Agent 文档 | docs/agents/ (issue-tracker, triage, domain) | — |

### 差距

- **[SHOULD-HAVE]** EH2 无独立的 `dv/uvm/core_eh2/README.md`（Ibex 有），release 需要一份 DV 目录级 README
- **[SHOULD-HAVE]** sphinx_cn 内容完整性未验证，需确认 build 能通过
- **[NICE-TO-HAVE]** EH2 文档偏内部开发视角，release 前需补一份面向外部用户的验证指南

---

## 7. 已知 OPEN Risk 评估

来源：CONTEXT.md §6

| RISK ID | 严重度 | 问题 | Release 建议 |
|---------|--------|------|-------------|
| RISK-1 | HIGH | 18+ EH2 自定义 CSR Spike fixup 仅 4 个（28 个 set_csr 静态注册，未做 WARL fixup） | **BLOCKER** — CSR 是 spec 合规核心，至少需 WARL fixup 或文档化为 known limitation |
| RISK-4 | BLOCKING | NUM_THREADS=2 不能 cosim | **SHOULD-HAVE** — 可标注为 known limitation（单线程 cosim 已验证），但必须在 release notes 中明确说明 |
| RISK-9 | OPEN | random_instr_test 中断/异常 cosim | **BLOCKER** — 中断是核心功能，无 cosim 校验不可接受 |
| RISK-10 | OPEN | bitmanip zba/zbb RTL illegal-instr 异常率高 | **SHOULD-HAVE** — 可做 known limitation，但需排除 RTL bug 可能性 |
| RISK-11 | OPEN | atomic SC.W RTL 写回与 Spike 分歧 | **SHOULD-HAVE** — 可做 known limitation（A 扩展非关键路径则降级） |

### 建议

- **Release blocker**: RISK-1 (WARL fixup) + RISK-9 (中断 cosim)
- **Known limitation release**: RISK-4 + RISK-10 + RISK-11，在 release notes 中声明

---

## 8. Skip_in_signoff 项目评估

11 个 riscv-dv 测试标记 `skip_in_signoff: true`，全部同时标记 `cosim: disabled`：

| 测试 | 跳过原因 | Release 建议 |
|------|---------|-------------|
| riscv_csr_test | CSR cosim 未实现 | **SHOULD-HAVE** — CSR 测试重要性高 |
| riscv_bitmanip_test | RISK-10 | SHOULD-HAVE |
| riscv_amo_test | RISK-11 | SHOULD-HAVE |
| riscv_interrupt_test | RISK-9 | **BLOCKER** |
| riscv_irq_single_test | RISK-9 | **BLOCKER** |
| riscv_stress_test | 综合压力 cosim | SHOULD-HAVE |
| riscv_breakpoint_test | 调试 cosim | SHOULD-HAVE |
| riscv_csr_hazard_test | CSR 冲突 cosim | SHOULD-HAVE |
| riscv_reset_test | 复位 cosim | SHOULD-HAVE |
| riscv_single_step_test | 单步 cosim | SHOULD-HAVE |
| riscv_debug_wfi_test | 调试 + WFI cosim | SHOULD-HAVE |

**建议**：至少将 `riscv_interrupt_test` 和 `riscv_irq_single_test` 解锁到 sign-off。其余可标 known limitation，但需在 release notes 列出全部 11 个被跳过的测试。

---

## 总结：Release Blocker 清单

| # | 差距 | 来源 | 行动项 |
|---|------|------|--------|
| B1 | 中断/异常 cosim 路径未实现 | §1/§7 RISK-9 | 扩展 scoreboard 处理 mcause/mepc/mtval |
| B2 | EH2 自定义 CSR WARL fixup 缺失 | §7 RISK-1 | 补全 Spike fixup 或文档化 known limitation |
| B3 | PMP fcov 仅 33% 覆盖 | §3 | 补全 eh2_pmp_fcov_if.sv 覆盖点 |

## SHOULD-HAVE 清单

| # | 差距 | 来源 | 行动项 |
|---|------|------|--------|
| S1 | 覆盖率 gate 未启用 | §2 | 设置 min coverage 阈值 + --require-coverage |
| S2 | CI sim 非自动触发 | §4 | 加 nightly schedule 或 PR 自动触发 |
| S3 | 无 Verilog lint CI | §4 | 加 Verible lint workflow |
| S4 | 缺 7+ 核心测试类型 | §5 | 至少补 illegal_instr / nested_interrupt / debug_basic |
| S5 | PMP directed 测试仅 3 个 vs Ibex 942 | §5 | 至少增加 PMP 排列子集 |
| S6 | NUM_THREADS=2 无 cosim | §7 RISK-4 | 标 known limitation + release notes |
| S7 | bitmanip/AMO cosim 分歧 | §7 RISK-10/11 | 排除 RTL bug 后标 known limitation |
| S8 | 11 个 skip_in_signoff 中 2 个是 blocker | §8 | 至少解锁中断测试到 sign-off |
| S9 | DV 目录无 README | §6 | 写 DV README.md |
| S10 | fcov 未接入 sign-off | §3 | 在 full profile 启用覆盖率采集 |

## NICE-TO-HAVE 清单

| # | 差距 | 来源 |
|---|------|------|
| N1 | 无 coverage merge 脚本 | §2 |
| N2 | 无 cov_testlist (trace → fcov 采样) | §3 |
| N3 | 无 CS Registers / ICache 独立 DV | §5 |
| N4 | 无 formal CI workflow | §4 |
| N5 | 缺 U-mode / SecureIbex 特有测试 | §5 |
| N6 | 面向外部用户的验证指南 | §6 |
