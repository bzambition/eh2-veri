# Issue 04: probe_monitor 仅保留异步通道

Status: done (Phase 1 完成)
Phase: 1
Type: AFK
Blocked by: Issue 03

## 要做什么

`eh2_dut_probe_monitor.sv` 当前监视 3 个通道：
1. `monitor_writeback`：常规 wb（**Issue 03 后由 trace 通道直接携带，应删除**）
2. `monitor_division`：DIV cancel（异步，保留）
3. `monitor_nb_load`：NB-load 写回（异步，保留）

异步通道的存在原因：DIV cancel / NB-load 写回**与 trace 包的 retire 周期不在同一拍**——DIV 可能在 retire 后多周期才完成，NB-load 同理。

### 修改

| 文件 | 操作 |
|------|------|
| `eh2_dut_probe_monitor.sv` | 删除 `monitor_writeback` 任务和相关 wb_seq_counter 主循环 |
| `eh2_dut_probe_intf.sv` | 删除 `wb_valid` / `wb_dest` / `wb_data` / `wb_suppress` / `wb_seq` |
| `core_eh2_tb_top.sv` | 删除常规 wb 信号的 hierarchical assign（line ~949–972） |
| `eh2_cosim_scoreboard.sv` | 增加 `pending_async_wb_q[$]` 队列处理 nb_load/div_cancel |

### scoreboard 异步通道处理逻辑

```systemverilog
// 在 compare_instruction 内：
if (item.is_div() || item.is_load_or_amo()) begin
  // 主路径写回已由 trace 直接给出，但需要检查 nb_load / div_cancel 是否覆盖
  pending_async_wb_t async_wb;
  if (try_consume_async_wb(item, async_wb)) begin
    // 异步通道覆盖：使用异步数据 / suppress
    write_reg      = async_wb.suppress ? 0 : item.wb_dest;
    write_reg_data = async_wb.suppress ? 0 : async_wb.data;
    suppress_reg_write = async_wb.suppress;
  end
end
```

## 验收标准

- [ ] 编译通过
- [ ] smoke + 至少 2 个含 mul/div 的 test，cosim 全部 MATCH
- [ ] probe_monitor.sv 行数从 178 → ~100

## 阻塞依赖

- Issue 03
