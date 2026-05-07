# Phase 2 实施进度（2026-05-06 完成）

## 总结

Phase 2 完成 4 个步骤的结构整理：env 接口归位、命名一致性、TB top 拆分、scoreboard 模块化。Phase 1 cosim 闭环 100% 保持（smoke + arithmetic 3 seeds 全 PASS, 0 mismatches）。

## 完成步骤

### Step 2A: env/ 接口归位 ✅

按 Ibex 约定，`env-level interfaces` 应位于 `env/` 而非 `common/`。

- `eh2_dut_probe_intf` → 移到 `env/eh2_dut_probe_if.sv`（顺便重命名 intf→if 与 Ibex 一致）
- `eh2_csr_if.sv` → 移到 `env/`
- `eh2_instr_monitor_if.sv` → 移到 `env/`
- `eh2_trace_intf.sv` 保留在 `common/trace_agent/`（trace 通道接口，配 monitor）
- 全代码库 `eh2_dut_probe_intf` → `eh2_dut_probe_if` 改名（7 文件）
- `eh2_tb.f` filelist 调整 incdir + 文件路径

### Step 2B: 命名一致性 ✅

EH2 特有的 `halt_run_*` 加 `eh2_` 前缀（与 `eh2_cosim_*`、`eh2_jtag_*`、`eh2_irq_*` 统一）。
通用协议 `axi4_*` 不加前缀（保留通用名是合理选择）。

- 6 个 `halt_run_*.sv` 文件 → `eh2_halt_run_*.sv`
- 文件内 class/package/interface 名同步重命名
- 所有引用文件（env、test、tb、filelist）同步更新
- 实例名（halt_run_vif、halt_run_agt、halt_run_seqr）保持简短不带前缀

### Step 2C: TB top 信号声明拆分 ✅

`core_eh2_tb_top.sv` 1298 → 1071 行（-227 行）：

- 抽出 220 行 DUT 信号声明（reset, JTAG, trace, debug, AXI4 LSU/IFU/SB/DMA）
  到 `tb/core_eh2_dut_signals.svh`
- TB top 顶部用 `\`include "core_eh2_dut_signals.svh"` 引入
- filelist 加 `+incdir+dv/uvm/core_eh2/tb`

**额外清理**（trace pkt 接管 wb 后的死代码）：
- 删除 `eh2_dut_probe_if.sv` 中 wb_valid/wb_dest/wb_data/wb_tid/wb_suppress/wb_seq
  字段（30+ 行死代码，没有 reader）
- 删除 TB top 中对应的 hierarchical assign（13 行）
- 死代码确认：`grep vif.wb_*` 全代码库 0 reader

### Step 2D: scoreboard 模块化 ✅

`eh2_cosim_scoreboard.sv` 871 → 734 行（-137 行）：

- 抽出 binary loader（`load_binary` / `load_raw_binary` / `load_hex`，112 行
  纯文件 I/O 工具函数）→ `eh2_cosim_binary_loader.svh`
- 抽出 28 个 EH2 CSR 预注册数据（重复模式数据，与 cosim 逻辑无关）
  → `eh2_cosim_csr_preregister.svh`
- scoreboard 主体用 `\`include` 引入两个 svh 头
- 主 scoreboard 现在专注：FIFO 处理、async wb 关联、Spike step、报告

## 累计成果（Phase 1 + Phase 2）

| 文件 | 1026 → 734 行 | scoreboard |
| 文件 | 178 → 118 行 | dut_probe_monitor |
| 文件 | 132 → 105 行 | dut_probe_if（删 wb_*/wb_seq 死字段） |
| 文件 | 1298 → 1071 行 | core_eh2_tb_top |
| | -34% | scoreboard 总瘦身 |
| | -34% | probe_monitor 瘦身 |
| | -17% | TB top 瘦身 |

新增辅助文件（svh / signals）：
- `eh2_cosim_binary_loader.svh`（125 行）
- `eh2_cosim_csr_preregister.svh`（41 行）
- `core_eh2_dut_signals.svh`（220 行）

## 验证证据

```
=== Smoke + cosim ===
Trace items received: 6
Steps executed:       6
Mismatches:           0
Pre-registered 28 EH2 custom CSRs
RESULT: PASS
TEST PASSED (mailbox)
TEST PASSED (signature)

=== arithmetic_basic 3 seeds (Phase 2 final) ===
Total:  3
Passed: 3
Failed: 0
Pass rate: 100.0%
```

每步骤都做了独立编译 + smoke 验证，Phase 1 闭环全程未受影响。

## 已知保留事项

- `axi4_*` 不加 `eh2_` 前缀（通用协议名，避免无意义改动）
- TB top 内的 fcov interface bind（160 行）保留就地，因为 hierarchical reference
  跨文件复杂度高于收益
- TB top 内的 dut_probe hierarchical assign（80 行）保留就地，原因同上

## 工程指标对比（Phase 0 → Phase 2）

| 指标 | Phase 0 baseline | Phase 2 完成 | 变化 |
|------|------------------|-------------|------|
| scoreboard 行数 | 1026 | 734 | **-29%** |
| probe_monitor 行数 | 178 | 118 | **-34%** |
| TB top 行数 | 1287 | 1071 | **-17%** |
| 死代码 wb_* 字段数 | 6 | 0 | **-100%** |
| WB_SEARCH_DEPTH band-aid | 1 | 0 | **-100%** |
| pending_wb_q band-aid | 1 | 0 | **-100%** |
| env/ 接口归位（Ibex 对齐） | 否 | 是 | ✓ |
| 命名前缀一致性 | 部分 | EH2 全统一 | ✓ |

## 下次会话起点

Phase 1 + 2 完成。备份在 `.scratch/snapshots/phase2_complete_*.tar.gz`。

**可选下一步**：
- Phase 3：Spike fixup_csr 完整实现（消除 RTL CSR 测试的 cosim disabled 限制）
- Phase 3：恢复 testlist 中 cosim disabled 的项目
- Phase 4：CONTEXT.md / ADR 更新
- Phase 5：多 hart cosim / formal / CI gate
- 修 wrapper.mk testlist description 引号 escape 问题（独立 bug）
- 修 random_instr_test 的 cosim 中断/异常处理（独立 bug）
