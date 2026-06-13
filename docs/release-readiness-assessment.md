# EH2 验证平台 Release 就绪度评估

**评估日期**：2026-05-08
**评估范围**：`/home/host/eh2-veri/` 对标 `/home/host/ibex/dv/uvm/core_ibex/`
**评估方法**：四路并行核查 sign-off 真实性 / Ibex 功能对齐 / cosim 实际覆盖 / 代码层 hack
**结论**：**当前 v1.0 PASS 是"自我宽容的 PASS"，离工业级 Release 仍有结构性差距，不能直接发版。**

---

## 一、Sign-off 真实成色

`build/sf_full2/signoff_report.md` 报告 40/40 PASS，但展开看：

| Stage | 报告 | testlist 池 | 实跑 | 静默跳过 |
|---|---|---|---|---|
| smoke | 1/1 | 1 | 1 | — |
| directed | 3/3 | **13** | 3 | 10 个连入口都没出现 |
| cosim | 4/4 | 5 | 4 | 缺 `cosim_bitmanip` |
| riscvdv | 32/32 | **43** | 32 | 11 个 `skip_in_signoff: true` |

**真实覆盖：62 个 testlist 条目跑了 40 个 ≈ 64%**。`signoff.py:418` 默认 `--require-coverage=off`，sf_full2 报告 `Coverage Status: SKIP`，**这次签发完全没跑覆盖率**。

## 二、cosim ISA 覆盖严重不足

`riscv_dv_extension/testlist.yaml` 共 **32 处 `cosim: disabled`（占 76%）**，CONTEXT.md 写的"11 个"是低估。逐 ISA 子集：

| 子集 | cosim 状态 | 依据 |
|---|---|---|
| I 基础 | ✅ 闭环 | arithmetic_basic / random_instr / load_store |
| M 乘除 | ✅ 闭环 | mul_div_test，div cancel 已修 |
| **A 原子** | ❌ 未覆盖 | amo_test 全禁，spike 无 atomic-store fixup（RISK-11） |
| **C 压缩** | ⚠️ 部分 | 仅 random 中混入，无专项 |
| **Zba/Zbb** | ⚠️ 仅样本 | 随机禁用，仅 1 个确定性 ASM（RISK-10） |
| 中断 (8 个) | ❌ 0 cosim | interrupt / irq_single / irq_wfi / irq_csr / irq_nest / irq_in_debug / stress / reset |
| 调试 (10 个) | ❌ 0 cosim | debug / debug_csr / breakpoint / single_step / debug_wfi / debug_during_csr / debug_ebreak / debug_in_irq / dret / debug_ebreakmu / single_debug_pulse |
| PMP/ePMP (6 个) | ❌ 0 cosim | pmp_basic / pmp_disable_all / pmp_random / epmp_mml / epmp_mmwp / epmp_rlb |
| 完整性注入 (3 个) | ❌ 0 cosim | pc_intg / rf_intg / mem_error |

**更隐蔽的旁路**：

- `eh2_cosim_scoreboard.sv:547-558` `mcause/mepc` 比对**只 `UVM_INFO`，不递增 mismatch**——分歧也 PASS
- `spike_cosim.cc:885-890` `misaligned_pmp_fixup` 是空 stub
- `spike_cosim.cc:1131-1145` store coalescing 直接 `return kCheckMemOk`
- `spike_cosim.cc:1222-1239` store BE 用"超集即 OK"放宽（有 ADR-0005 背书）

**名义"RV32IMAC + Zb*"，A 与 Zb 实际都没被 ISS 校验过。**

## 三、与 Ibex 对齐度 ≈ 65–70%

EH2 反超 Ibex 的部分：6 agent vs 3、PMP fcov 1458 行 vs 854 行、Makefile/scripts 体系更完善。

EH2 落后的部分：

| 维度 | Ibex | EH2 | 缺口 |
|---|---|---|---|
| testlist 总数 | 57 | 43 | 缺 14 项 |
| debug 测试 | 13+ | 11 | 缺 triggers / stress / branch_jump / instr / csr_entry / assorted_traps |
| PMP 测试 | 10 | 6 | 缺 region_exec / out_of_bounds / full_random / mml_execute_only / mml_read_only |
| 完整性测试 | 6 | 3 | 缺 rf_addr_intg / ram_intg / icache_intg / mem_intg_error |
| bitmanip | 3 档 | 1 | 缺 full / otearlgrey / balanced 强度集 |
| 中断测试 | 6 | 4 | 缺 multiple_interrupt / interrupt_instr |
| 基础随机/特权模式 | hint_instr/illegal_instr/ebreak/loop/jump_stress/mmu_stress/umode_tw/machine_mode_rand/user_mode_rand/rv32im_instr | — | ~10 项缺失 |
| **`cs_registers/`** CSR 单测 | ✅ 独立 UVM 子环境 | ❌ 无 | 完全缺失 |
| **`riscv_compliance/`** | ✅ 完整 | ❌ 无 | 完全缺失 |
| **`lint/`** | ✅ verible+verilator waiver | ❌ 无 | 完全缺失 |
| **`syn/`** | ✅ Nangate sdc + yosys + LEC | ❌ 无 | 完全缺失 |
| **`formal/`** | ✅ 属性集 + sail-riscv + yosys 集成 | ⚠️ 空骨架 | 仅 4 个目录壳 |

## 四、代码层成熟度 7.5/10（相对干净）

`wb_search_depth` / `pending_wb_q` 已彻底删除，TODO/FIXME 全 codebase 仅 2 处。**主要遗留**：

- `eh2_trace_monitor.sv:116,158` `mtval = 32'h0` 占位（异常路径可能掩盖比对 bug）
- `eh2_cosim_scoreboard.sv:669-677` 9 行硬编码 DCCM/ICCM 地址
- `async_wb_q` 仍带启发式窗口色彩（基于 rd 匹配）
- `fcov/eh2_pmp_fcov_if.sv:162,568` 两条 TODO（PMP load/store 区分缺信号）
- CONTEXT.md §3 三个 if 的"Phase 2 修复"描述已与代码不符（实际已迁到 `env/`）

## 五、Release 阻塞清单（按优先级）

### P0（必须修，否则不算工业级 Release）

1. **签发判定标准强化**（`signoff.py`）
   - 启用 `--require-coverage`，line ≥ 60% / functional ≥ 50% 阻断
   - 新增 `--fail-on-cosim-disabled` 选项
   - directed/riscvdv testlist 池里所有未跑测试要么实跑要么显式 waiver
2. **cosim 比对发散从 UVM_INFO 升级为 mismatch**（`eh2_cosim_scoreboard.sv` mcause/mepc 路径）
3. **A 子集 cosim 闭环**（spike_cosim atomic-store fixup + amo_test 解禁）
4. **中断/调试 cosim 闭环**（18 个测试，最大风险面）

### P1（Ibex 工业级标尺的硬门槛）

5. **PMP/ePMP cosim 闭环**（填实 `misaligned_pmp_fixup` + 6 个测试解禁）
6. **`cs_registers/` CSR 单元测试子环境**
7. **`riscv_compliance/` 合规测试集**
8. **`lint/` 落地**（verible + verilator waiver）

### P2（补齐功能广度）

9. **directed 缺的 10 个测试入口实跑**
10. **bitmanip 三档强度集 + Zb cosim 闭环**
11. **完整性测试 3 项补齐**（rf_addr / ram / icache_intg）
12. **`syn/` 综合脚手架**（Nangate sdc + yosys + LEC）
13. **`formal/` 从空骨架填到有真实属性集**

### P3（代码层清理）

14. **mtval RTL probe 接通或在 cosim 端显式 waive 并文档化**
15. **cosim 内存映射从硬编码改为 env_cfg 注入**
16. **async_wb_q 启发式改为 wb_seq 严格序号关联**
17. **CONTEXT.md 与代码状态对齐**（接口位置、Phase 标注、RISK 数字）
18. **PMP fcov 信号补全**（load/store 区分）

## 六、建议的 Release 标签降级

把 CONTEXT.md 中的 "v1.0 Release Sign-off PASS" 改为：

> **"RC1：I/M 子集 cosim 闭环 + 流程框架就绪；A/Zb/中断/调试/PMP cosim 通道未闭环；覆盖率与 lint/syn/formal 未达工业级门槛"**

完成 P0 + P1 后才能宣称 v1.0 GA。

---

## 评估证据

| 来源 | 路径 |
|---|---|
| sign-off 真实性核查 | 本文档"一" |
| Ibex 对齐对比 | 本文档"三" |
| cosim 覆盖核查 | 本文档"二" |
| 代码层 hack 扫描 | 本文档"四" |
| issue 拆解 | `.scratch/release-readiness/issues/` |
