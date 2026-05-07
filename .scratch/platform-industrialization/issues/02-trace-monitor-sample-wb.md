# Issue 02: trace_monitor 采样新 wb 信号

Status: done (Phase 1 完成)
Phase: 1
Type: AFK
Blocked by: Issue 01

## 要做什么

让 `eh2_trace_monitor` 在采样 trace 包时直接读取新的 rd_valid / rd_addr / rd_wdata 信号，填入 `eh2_trace_seq_item`。

### 修改文件

| 文件 | 修改 |
|------|------|
| `dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv` | 增加同名信号 |
| `dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv` | 采样并填入 txn |
| `dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` | 把 RTL 新端口连到 trace_intf |

### 关键改动

**1. eh2_trace_intf.sv 增加：**

```systemverilog
logic [NUM_THREADS-1:0][1:0]  rd_valid;
logic [NUM_THREADS-1:0][9:0]  rd_addr;
logic [NUM_THREADS-1:0][63:0] rd_wdata;

// 拆开成 t0_i0/i1 结构方便 monitor 用
logic       t0_i0_wb_valid;
logic [4:0] t0_i0_wb_addr;
logic [31:0] t0_i0_wb_data;
logic       t0_i1_wb_valid;
logic [4:0] t0_i1_wb_addr;
logic [31:0] t0_i1_wb_data;

assign t0_i0_wb_valid = rd_valid[0][0];
assign t0_i0_wb_addr  = rd_addr[0][4:0];
assign t0_i0_wb_data  = rd_wdata[0][31:0];
assign t0_i1_wb_valid = rd_valid[0][1];
assign t0_i1_wb_addr  = rd_addr[0][9:5];
assign t0_i1_wb_data  = rd_wdata[0][63:32];
```

**2. eh2_trace_monitor.sv 在 monitor_trace 内 i0/i1 分支补：**

```systemverilog
// In i0 branch (line 83-104):
txn.wb_valid = vif.t0_i0_wb_valid;
txn.wb_dest  = vif.t0_i0_wb_addr;
txn.wb_data  = vif.t0_i0_wb_data;

// In i1 branch (line 107-128):
txn.wb_valid = vif.t0_i1_wb_valid;
txn.wb_dest  = vif.t0_i1_wb_addr;
txn.wb_data  = vif.t0_i1_wb_data;
```

**3. core_eh2_tb_top.sv 把 DUT 输出连进 trace_intf：**

参考现有 `trace_intf.t0_i0_insn` 等连接 pattern，把新端口连进去。

## 验收标准

- [ ] 编译通过，无 unconnected warning
- [ ] smoke test 跑通后，trace_seq_item 的 wb_dest/wb_data 在 sim log 里非零（用 UVM_HIGH 看 trace_monitor.convert2string）
- [ ] cosim 自身禁用情况下，平台 smoke 仍 PASS

## 阻塞依赖

- Issue 01（必须先完成 RTL 改动）
