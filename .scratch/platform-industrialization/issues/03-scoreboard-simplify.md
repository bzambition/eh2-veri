# Issue 03: scoreboard 简化（删 pending_wb_q 与 wb_search_depth）

Status: ready-for-agent
Phase: 1
Type: AFK
Blocked by: Issue 02

## 要做什么

在 trace_monitor 已经直接携带 wb 信息的前提下，简化 `eh2_cosim_scoreboard.sv`。

### 删除的代码

| 内容 | 行号（参考） | 原因 |
|------|------------|------|
| `pending_wb_q[2][$]` 数据结构 | ~89 | trace 自带 wb，不再需要 |
| `run_cosim_probe()` task | ~228–284 | wb 不再异步，无需消费 probe FIFO |
| `dut_probe_fifo` analysis FIFO | ~39 | 同上 |
| `wb_search_depth` 变量与所有引用 | ~52, 401–408, 442–470 | band-aid 删除 |
| `has_expected_writeback()` 函数 | ~394–424 | 不需要等待 wb |
| `pop_expected_writeback()` 函数 | ~426–472 | 不需要 pop |
| `pending_trace_q` + `process_pending_trace` 的 wb 等待逻辑 | ~307–319 | trace 自带 wb |
| `compare_instruction()` 中的 `pop_expected_writeback` 调用 | ~663 | 直接从 item 取 |
| `WB_SEARCH_DEPTH` plusarg 处理 | ~123–124 | 删除 |
| `pending_wb_high_watermark` 等统计 | ~62–63, ~199–200 | 删除 |
| `wb_source_matches` / `writeback_matches` | ~373–388 | 删除（移到 probe 异步通道判断） |
| `EH2_WB_SRC_REGULAR` 主路径分支 | trace_seq_item.sv | 保留 enum，仅 nb_load/div 用 |

### 修改的代码

`compare_instruction()` 内（~628 行）从：

```systemverilog
if (needs_writeback(item) && pop_expected_writeback(item, wb)) begin
  if (wb.rd != 0 && !wb.suppress) begin
    write_reg      = wb.rd;
    write_reg_data = wb.rd_data;
  end ...
```

改为：

```systemverilog
// trace 直接携带 wb 信息（来自 RTL trace 包）
if (item.wb_valid && item.wb_dest != 0) begin
  write_reg      = item.wb_dest;
  write_reg_data = item.wb_data;
end else begin
  write_reg      = 0;
  write_reg_data = 0;
end
suppress_reg_write = item.wb_suppress;
```

### 保留的代码

- `lsu_axi_fifo` 与 `run_cosim_dmem`：内存访问通知不变
- `pending_mem_access_q` 与 `process_pending_trace` 的 mem 等待逻辑：保留
- nb_load / div_cancel 异步通道处理：移到 issue 04 处理
- `init_cosim` / `cleanup_cosim` / `flush_state` / `reset_monitor`：保留
- Spike notification 顺序（debug_req → nmi → mip → mcycle → step）：保留

## 预期产出

| 指标 | 当前 | 目标 |
|------|------|------|
| eh2_cosim_scoreboard.sv 行数 | 1026 | ≤ 500 |
| pending_wb_q 引用 | 30+ | 0 |
| wb_search_depth 引用 | 5+ | 0 |
| run_cosim_* 任务数 | 4 | 3（去掉 probe） |

## 验收标准

- [ ] 编译通过
- [ ] smoke + 1 个 random test 跑通，cosim 全部 MATCH
- [ ] 行数下降到 500 以下
- [ ] grep `WB_SEARCH_DEPTH` 全代码库无结果

## 阻塞依赖

- Issue 02

## 后续

Issue 04: probe_monitor 简化（保留异步通道）
