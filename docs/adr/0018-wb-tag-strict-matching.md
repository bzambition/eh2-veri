# ADR-0014: 异步写回匹配——从 rd 启发式转向严格 wb_tag

- 状态：Accepted
- 日期：2026-05-08
- 关联：Issue 66, ADR-0004

## 上下文

Issue 66 在异步写回提示（async_wb_q）匹配中引入了 `wb_tag` 字段用于严格排序匹配。
然而，原始实现在三个位置保留了 `rd == expected_rd` 启发式回退：

1. `has_matching_async_wb()`——NB-load 路径：wb_tag 不匹配时回退到 rd 比较（行 348）
2. `try_consume_async_wb()`——DIV 路径：wb_tag 不匹配时回退到 rd 比较并发出 UVM_WARNING（行 402-408）
3. `try_consume_async_wb()`——NB-load 路径：wb_tag 不匹配时回退到 rd 比较（行 423-427）

此外，`has_matching_async_wb()` 中的 DIV 路径包含一个非 rd 的回退：`else return 1'b1`（行 338），该回退在 wb_tag 不匹配时匹配第一个任意 DIV 来源的提示。

这些回退存在风险：
- **假阳性**：错误的写回数据可能通过 rd 匹配与指令关联
- **掩盖错误**：wb_tag 不匹配未被报告，bug 被隐藏
- **违反设计原则**：ADR-0004 的本意是消除启发式方法，而非部分减少

## 决策

**删除所有 `rd == expected_rd` 启发式回退。强制仅通过 wb_tag 进行严格关联。**

### scoreboard 变更 (`eh2_cosim_scoreboard.sv`)

1. **`has_matching_async_wb()`**：
   - 删除 `else return 1'b1` DIV 回退——仅严格按 wb_tag 匹配
   - 删除 `if (rd == expected_rd) return 1'b1` NB-load 回退
   - 移除未使用的 `expected_rd` 局部变量

2. **`try_consume_async_wb()`**：
   - 删除两处 `if (rd == expected_rd)` 回退块（DIV 和 NB-load）
   - 新增 mismatch 检测：当队列中存在正确来源的提示但 wb_tag 不匹配时，递增 `mismatch_count[tid]` 并通过 `uvm_error` 报告
   - 不匹配的提示保留在队列中（不被消费），等待正确的 wb_tag 到来

3. **头注释更新**：从"via rd address"更新为"via strict wb_tag association"

### probe_monitor 变更 (`eh2_dut_probe_monitor.sv`)

- `wb_seq_counter` 初始值从 `0` 改为 `1`，确保每个写回事件的 `wb_tag >= 1`
- scoreboard 检查 `wb_tag > 0`，因此第一个写回事件之前的 wb_tag=0 会被拒绝

### wb_tag 缺失时的行为

| 场景 | 行为 |
|------|------|
| hint wb_tag == item wb_tag | 正常匹配，消费提示 |
| hint queue 中有正确来源但 wb_tag 不匹配 | `uvm_error` + `mismatch_count++` |
| hint queue 为空或没有正确来源的提示 | 无错误——等待提示到达 |
| hint wb_tag == 0（probe_monitor 未填充） | 从不匹配（因为 `wb_tag > 0` 检查失败），不一致时触发 mismatch |

## 影响评估

| 维度 | 影响 | 风险 |
|------|------|------|
| 功能行为 | 回退被移除后，当 wb_tag 错位时，先前悄悄回退到 rd 匹配的情况现在会报告 mismatch | 低（mismatch 本应被报告） |
| 验证准确性 | 假阳性减少——wb_tag 不匹配被检测并标记为错误 | 正向 |
| 调试能力 | `uvm_error` 消息包含 item.wb_tag、hint.wb_tag 和 rd，便于根因分析 | 正向 |
| probe_monitor | 最小改动（计数器起始值 +1） | 零风险 |
| 上游兼容 | 无 RTL 变更——仅 UVM 层 | 低 |

## 备选方案

| 方案 | 描述 | 评估 |
|------|------|------|
| A. 保留 rd 回退但添加 UVM_ERROR | 优雅降级同时标记不一致 | 不解决根本问题——错误数据仍被接受 |
| **B. 删除回退，严格 wb_tag 匹配（本 ADR）** | 拒绝所有非 wb_tag 的匹配 | **选定** |
| C. 完全移除 wb_tag 恢复纯 rd 匹配 | 回归 ADR-0004 之前的状态 | 倒退，未利用 ADR-0004 的改进 |

## 后果

### 正面
- 异步写回匹配现在具有确定性且可验证
- wb_tag 不匹配会引发明确的 `uvm_error`，而非静默通过
- 代码更简单——`has_matching_async_wb` 去除了 `expected_rd` 变量和冗余分支
- 与 ADR-0004 理念一致：消除启发式方法，拥抱确定性的逐指令关联

### 负面
- wb_tag 错位（DUT/probe 错误）会直接导致 mismatch，而此前可能被 rd 回退掩盖
- 监控基础设施中的任何 wb_tag 缺陷都会立即显现——这在审查期间是正向的，但对首次运行可能是破坏性的

## 验证标准

- `grep -n "rd == expected_rd\|rd_fallback" eh2_cosim_scoreboard.sv` 返回 0 行
- `make smoke` PASS，0 mismatch
- `make run TEST=riscv_arithmetic_basic_test ITERATIONS=5` 5/5 PASS
- `make run TEST=riscv_load_store_test` PASS（覆盖 NB-load 路径）
