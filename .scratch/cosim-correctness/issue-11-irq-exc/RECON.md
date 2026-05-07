# Issue 11 前置调研：中断/异常 cosim 路径

调研日期：2026-05-07
状态：仅调研，无代码改动

---

## Q1. 当前 cosim_scoreboard 中 interrupt-only trace item 如何处理

**文件**: `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
**关键代码**: 第 557–566 行

```systemverilog
if (item.interrupt && !item.exception) begin
  riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req));
  riscv_cosim_set_nmi(cosim_handle, int'(item.nmi));
  riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int));
  riscv_cosim_set_mip(cosim_handle, int'(prev_mip), int'(item.mip));
  prev_mip = item.mip;
  riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle));
  `uvm_info("cosim", $sformatf("IRQ-ONLY: PC=%08x", item.pc), UVM_HIGH)
  return;
end
```

**行为分析**:
- **仅调 `set_mip`**（加上 debug_req / nmi / nmi_int / mcycle 的通知）
- `set_mip` 在 C++ 层（`spike_cosim.cc:678–700`）调用 `early_interrupt_handle()`，后者让 Spike step 一次但期望"不执行指令"（`last_inst_pc == PC_INVALID`），完成中断状态切换
- **无 mtvec/mepc/mcause 比对**：当前 scoreboard 在 interrupt-only 分支直接 `return`，不检查任何 CSR 值
- **无 step() 调用**：不调 `riscv_cosim_step()`，所以 `insn_cnt` 不递增
- **DUT probe 已有 mtvec/mepc/mcause 信号**（`eh2_dut_probe_if.sv:41–43`），但 `trace_monitor` 没有把它们放入 `eh2_trace_seq_item`，scoreboard 也没使用

**结论**: interrupt-only 只做了"把中断注入 Spike"的前半步，没做"比对 Spike 和 DUT 的 trap CSR 是否一致"的后半步。

---

## Q2. 当前 exception trace item 处理

**文件**: `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
**关键代码**: 第 614–630 行（在 `compare_instruction` 中）

```systemverilog
sync_trap = item.exception && !item.interrupt;  // line 614

// ... 通知 Spike (set_debug_req / set_nmi / set_nmi_int / set_mip / set_mcycle)
// 特殊：ecause==1 (instruction access fault) 时调 set_iside_error (line 623-625)

result = riscv_cosim_step(cosim_handle,
  int'(write_reg), int'(write_reg_data),
  int'(item.pc), sync_trap ? 1 : 0,        // sync_trap 传给 Spike
  suppress_reg_write ? 1 : 0);
```

**Spike C++ 端** (`spike_cosim.cc:270–402`):
- `step()` 收到 `sync_trap=true` 后，Spike 自己也 step → 如果 Spike 也看到同步 trap（`last_inst_pc == PC_INVALID` 且 `mcause` 最高位为 0），调 `check_sync_trap()`（第 460–497 行）
- `check_sync_trap()` 仅比对 **PC 匹配**（DUT PC == Spike initial_PC）和 **write_reg == 0**
- **mcause 比对**: 仅在 `check_sync_trap()` 内做 fixup（load/store access fault `mcause=5/7` → `misaligned_pmp_fixup`，内部 NMI `mcause=0xFFFFFFE0` → pop pending_dside_accesses），但**不比对 DUT 和 Spike 的 mcause 值是否一致**
- **mepc 比对**: **无**
- **mtval 比对**: **无**
- **mtvec 比对**: **无**

**结论**: 异常路径调了 Spike step 并传 `sync_trap=true`，Spike 内部验证了"DUT 应该在同一 PC 看到 trap"，但**没有比对 mcause/mepc/mtval 三元组**。这意味着即使 DUT 报了一个完全错误的 cause code，只要 PC 一致就不会报 mismatch。

---

## Q3. interrupt 与 exception 同周期的优先级

**RTL trace_pkt 行为**（`eh2_trace_intf.sv:30–33`）:
- `interrupt[thread][slot]` 和 `exception[thread][slot]` 是独立信号
- trace monitor 采样: `txn.interrupt = vif.interrupt[0][slot]`（第 91、123 行）

**scoreboard 处理优先级**（`eh2_cosim_scoreboard.sv:557`）:
- `interrupt=1 && exception=0` → interrupt-only，不 step，仅 set_mip，return
- `exception=1`（不管 interrupt 是什么）→ 走 `compare_instruction` 完整路径
  - 其中 `sync_trap = item.exception && !item.interrupt`（第 614 行）
  - 所以 `exception=1 && interrupt=1` → `sync_trap = 0`（不算同步 trap，走正常 step 路径）
  - 这个组合理论上代表"中断在异常指令上"——DUT 应该优先处理中断（exception 被丢弃）

**"指令未退役但 trace_pkt 仍 valid"的情况**:
- interrupt-only: trace_pkt valid 但 PC 处的指令没执行，scoreboard 在 `needs_async_wb()` 中检查 `item.exception || item.interrupt` 时 return false（第 273 行），不等 async wb
- 当前实现正确处理了"不等 wb hint"的语义，但**缺失了中断导致 Spike 应该进 ISR 后的 CSR 状态比对**

---

## Q4. 现有 disabled 测试的失败模式

**testlist.yaml 中 cosim:disabled 的 34 个测试**（`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`）:

### IRQ/exception 相关（本 issue 核心，10 个）:
| 行号 | 测试名 | 类型 |
|------|--------|------|
| 20 | riscv_random_instr_test | IRQ（+enable_interrupt=1） |
| 97 | riscv_interrupt_test | IRQ + PIC |
| 110 | riscv_irq_single_test | 单次 IRQ |
| 350 | riscv_irq_wfi_test | WFI + IRQ |
| 362 | riscv_irq_csr_test | CSR + IRQ |
| 374 | riscv_irq_nest_test | 嵌套 IRQ |
| 386 | riscv_irq_in_debug_test | debug 中 IRQ |
| 398 | riscv_debug_in_irq_test | IRQ 中 debug |
| 197 | riscv_exception_stream_test | 定向异常流 |
| 177 | riscv_breakpoint_test | 断点异常 |

### Debug 相关（12 个）:
| 行号 | 测试名 |
|------|--------|
| 123 | riscv_debug_test |
| 135 | riscv_debug_csr_test |
| 267 | riscv_single_step_test |
| 316 | riscv_debug_wfi_test |
| 329 | riscv_debug_during_csr_test |
| 338 | riscv_debug_ebreak_test |
| 410 | riscv_dret_test |
| 422 | riscv_debug_ebreakmu_test |
| 434 | riscv_single_debug_pulse_test |
| 148 | riscv_stress_test（IRQ+debug 混合） |

### 其它原因 disabled（12 个）:
| 行号 | 测试名 | 原因 |
|------|--------|------|
| 36 | riscv_csr_test | CSR WARL |
| 75 | riscv_bitmanip_test | bitmanip 异常（RISK-10） |
| 85 | riscv_amo_test | AMO cosim |
| 187 | riscv_csr_hazard_test | CSR 流水线冲突 |
| 206 | riscv_pmp_basic_test | PMP |
| 215 | riscv_pmp_disable_all_test | PMP |
| 224 | riscv_pmp_random_test | PMP |
| 233 | riscv_pc_intg_test | PC 完整性 |
| 242 | riscv_rf_intg_test | RF 完整性 |
| 254 | riscv_reset_test | reset recovery |
| 277 | riscv_epmp_mml_test | ePMP |
| 286 | riscv_epmp_mmwp_test | ePMP |
| 295 | riscv_epmp_rlb_test | ePMP |
| 304 | riscv_mem_error_test | bus error |

### 已知失败 log 归档:
- **`build/issue12_fix4/riscv_bitmanip_test_s42/sim_riscv_bitmanip_test_42.log:2249`**:
  `Synchronous trap was expected at ISS PC: 80005b00 but the DUT didn't report one at PC 800025b4`
  → Spike 认为地址应 trap（内存映射分歧），DUT 正常执行
- **`build/verify5_riscv_amo_test/run/tests/riscv_amo_test.1/sim_riscv_amo_test_1.log:492`**:
  PC mismatch 级联（一个初始 mismatch 导致 Spike 和 DUT 永久失步）
- **`build/issue12_5seed/seed_*/` 多个 log**: 相同的 "Synchronous trap was expected" 模式

---

## Q5. EH2 自定义中断 CSR

**文件**: `dv/cosim/spike_cosim.cc` — `initial_proc_setup()`（第 633–671 行）

### set_csr / csrmap 静态注册情况:

| CSR | 编号 | 注册行号 | 类型 | WARL fixup |
|-----|------|---------|------|------------|
| meivt | 0xBC8 | 656 | basic_csr_t | ✅（894–905行，高22位可写） |
| meihap | 0xFC8 | 657 | basic_csr_t | 无（default 分支全写） |
| meipt | 0xBC9 | 658 | basic_csr_t | ✅（911–922行，低4位可写） |
| meicpct | 0xBCA | 659 | basic_csr_t | 无（default 分支全写） |
| meicurpl | 0xBCC | 660 | basic_csr_t | ✅（911–922行，低4位可写） |
| meicidpl | 0xBCB | 661 | basic_csr_t | ✅（911–922行，低4位可写） |
| mip | — | Spike 原生 | processor 内建 | N/A |
| mie | — | Spike 原生 | processor 内建 | N/A |

### PIC 路径 Spike 不模型:
1. **PIC 中断仲裁逻辑**（127 路中断源优先级排序）—— Spike 的 `mip` 只是简单的位掩码，不模型 EH2 的 `meihap = meivt + (4 × claimid)` 向量跳转
2. **meicpct (0xBCA)** —— PIC 中断 claim/complete 触发器，RTL 读此 CSR 会 side-effect 更新 `meicidpl`，Spike 的 `basic_csr_t` 无副作用
3. **meihap (0xFC8)** —— PIC 跳转地址，RTL 中由硬件计算（`meivt + claimid*4`），Spike 只是一个可读写寄存器
4. **EH2 内部 timer (mitcnt0/1, mitb0/1, mitctl0/1)** —— Spike 注册了 CSR 但不模型自动递增/比较中断产生逻辑

**结论**: Spike 对 PIC 是"寄存器桩"而非"行为模型"。对于 `riscv_interrupt_test` 等用 PIC directed stream 的测试，Spike 的 mip 需要由 DUT probe 实时同步，但 PIC 向量跳转路径（meivt → meihap）无法被 Spike 独立验证。

**CSR 预注册文件**: `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`（28 个 CSR，第 14–42 行全列表）

---

## Q6. 改动风险评估

### Phase 1 删除的 band-aid:

**来源**: commit `da13aa9` 的 commit message 明确记载:
> "scoreboard 删除所有 band-aid (WB_SEARCH_DEPTH / pending_wb_q)"

在当前代码中已无 `WB_SEARCH_DEPTH`、`pending_wb_q` 的任何痕迹（grep 确认为空）。Phase 1 的改动核心：
- **删除**: writeback 搜索队列 `pending_wb_q` + 启发式深度 `WB_SEARCH_DEPTH`
- **替换**: RTL trace pkt 直接携带 `wb_valid/wb_dest/wb_data`（ADR-0004）
- **新增**: NB-load 和 DIV 走独立的 `async_wb_q` FIFO

scoreboard 当前唯一的 "Phase 1" 标记:
- 第 6 行注释："Phase 1 simplification (ADR-0004)"
- 第 588 行注释："For Phase 1 we set div writeback to the async hint's data"

### 本次 IRQ/exception 路径与历史 band-aid 的关系:

**低相关**。Phase 1 的 band-aid 全部围绕"writeback 对齐"（即正常指令的 rd 写回如何与 trace 关联），而本次改动目标是"中断/异常时的 CSR 比对"——两者是 scoreboard 的不同分支：
- wb 路径: `compare_instruction()` → `try_consume_async_wb()` → Spike `step()` → `check_retired_instr()`
- IRQ-only 路径: `compare_instruction()` 第 557 行 `if (item.interrupt && !item.exception)` → 直接 return
- exception 路径: 走 `step()` 但 `sync_trap=true` → `check_sync_trap()` → 仅查 PC

**唯一交叉点**: 如果新增的 CSR 比对逻辑从 `eh2_dut_probe_if` 读 `mtvec/mepc/mcause`，需要确保 probe monitor 在正确的时序点采样（与 `#0` 延迟的 wb probe 共用同一 clocking block `monitor_cb`），否则可能在 dual-issue 场景下采到错误的值。

### 回归最敏感的 case:

1. **`riscv_arithmetic_basic_test`**（10 iterations，cosim enabled）—— 基础算术，最先暴露任何 step 路径回归
2. **`riscv_load_store_test`**（10 iterations，cosim enabled）—— 涉及 AXI + wb 对齐，store coalescing
3. **`riscv_mul_div_test`**（10 iterations，cosim enabled）—— 涉及 async_wb_q（DIV 路径）
4. **`riscv_dual_issue_test`**（10 iterations，cosim enabled）—— dual-issue 时序最敏感

---

## Q7. 建议的 commit 拆分

### Commit A: 纯加 compare 路径 + UVM_HIGH log，不改 testlist

**改动范围**:
| 文件 | 改动 | 预估行数 |
|------|------|---------|
| `eh2_cosim_scoreboard.sv` | interrupt-only 分支：step 后读 Spike mcause/mepc，与 probe_vif 比对，UVM_HIGH log | +40 行 |
| `eh2_cosim_scoreboard.sv` | exception 分支（`check_sync_trap` 后）：读 Spike mcause/mepc/mtval，与 DUT 比对 | +30 行 |
| `eh2_trace_seq_item.sv` | 新增 `mtvec_dut`/`mepc_dut`/`mcause_dut` 字段（从 probe 采样） | +15 行 |
| `eh2_trace_monitor.sv` | `populate_cosim_state()` 增加采样 probe_vif.mtvec/mepc/mcause | +6 行 |
| `spike_cosim.cc` | `check_sync_trap()` 增加 mcause/mepc 比对（读 Spike CSR 与 DUT 入参对比） | +25 行 |
| `cosim.h` | step 签名可能需要扩展传入 DUT 的 mcause/mepc（或走 set_csr） | +10 行 |
| `cosim_dpi.cc` | 对应 DPI 桥扩展 | +10 行 |

**总预估**: ~136 行新增 / 修改
**回归验证**: 现有 32/32 sign-off PASS 不变（新增路径只 log，不 fatal）

### Commit B: 解锁最简单的 1 个 IRQ test

**候选**: `riscv_exception_test`（testlist.yaml 第 159–166 行）
- **理由**: 这个测试**没有 `cosim: disabled`**（第 166 行后无此字段），实际上它已经是 cosim enabled！但它触发 illegal instruction / ebreak / unaligned——这些异常路径正是 commit A 要加强的。如果 commit A 的比对逻辑正确，这个测试应该继续 PASS。

**真正的第一个解锁候选**: `riscv_irq_single_test`（第 100–111 行）
- 只有单次 IRQ 注入，无嵌套，无 debug 混合
- `cosim: disabled` 在第 110 行

**改动**:
| 文件 | 改动 | 预估行数 |
|------|------|---------|
| `testlist.yaml` | 删除第 110 行 `cosim: disabled` | -1 行 |

**回归验证**: 跑 `riscv_irq_single_test` 5 iterations + 现有 cosim-enabled 回归

### Commit C: 解锁剩余 IRQ/exception tests

**改动**:
| 文件 | 改动 | 预估行数 |
|------|------|---------|
| `testlist.yaml` | 删除 9 个 IRQ/exception test 的 `cosim: disabled` | -9 行 |
| `eh2_cosim_scoreboard.sv` | 可能需要的 edge case 修复（基于 B 轮暴露的问题） | +20~50 行 |
| `spike_cosim.cc` | PIC 向量跳转 fixup / NMI mstack 比对 | +20~40 行 |

**总预估**: ~80 行新增 / 修改
**回归验证**: full profile sign-off + 所有新解锁测试 3 seed 验证

---

## Q8. 最终建议

### 主导模式

**Codex/Claude 可主导 Commit A**（纯加 compare + log）：
- 改动模式清晰（读 Spike CSR → 比对 → log），无算法设计决策
- 参考 Ibex 的 `check_sync_trap` 已有明确模板
- 不改 testlist，回归风险低

**Commit B 需要人 review checkpoint**：
- 解锁后的 `riscv_irq_single_test` 可能暴露 Spike `set_mip()` / `early_interrupt_handle()` 时序问题
- 需要人看 mismatch log 判断是 scoreboard 问题还是 Spike 配置问题

**Commit C 必须人主导**：
- 嵌套 IRQ / debug-in-IRQ 的状态机交互极其复杂
- PIC 向量跳转路径（meivt → meihap）可能需要 Spike 侧的行为扩展
- NMI mstack 保存/恢复的比对需要深入理解 EH2 RTL 的 tlu 状态机

### 可先单独抽出来做的子任务

1. **✅ 立即可做**: trace_seq_item 扩展 + trace_monitor 采样 probe_vif.mtvec/mepc/mcause
   - 纯机械操作，不影响任何现有逻辑，commit A 的前提
   - 预估 20 行，Codex/Claude 可独立完成

2. **✅ 立即可做**: 在 `compare_instruction()` 的 interrupt-only 分支加 UVM_HIGH 级别的 mcause/mepc/mtvec 信息 log（纯 diagnostic，不 assert）
   - 为后续调试积累数据，零回归风险

3. **⚠️ 需要小心**: `spike_cosim.cc` 的 `check_sync_trap()` 扩展 mcause/mepc 比对
   - 需要验证 Spike 内部 trap 处理后 CSR 值的读取时机（step 后 vs step 前）
   - 建议先用 `UVM_HIGH` log 打印双方值，收集一轮数据再加 assert

4. **🚫 不能提前做**: 删除 testlist 的 `cosim: disabled`——必须等 compare 路径 verified

### 依赖图

```
trace_seq_item 扩展 ──┐
                      ├─→ scoreboard compare 路径 ──→ 回归 32/32 ──→ 解锁 irq_single ──→ 解锁剩余
trace_monitor 采样 ───┘
```
