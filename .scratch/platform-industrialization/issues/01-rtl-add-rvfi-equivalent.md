# Issue 01: RTL trace 包增加 rd_addr/rd_wdata（RVFI 等价）

Status: done (Phase 1 完成)
Phase: 1
Type: AFK
Owner: 待分配
ADR: docs/adr/0004-rtl-rvfi-equivalent-trace.md

## 父需求

ADR-0004 — Phase 1 cosim 闭环修复的根基

## 要做什么

在 EH2 RTL 中把寄存器写回信号引出到 trace 包，等价于 Ibex RVFI 的 rd_addr/rd_wdata 输出。

### 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| `rtl/design/include/eh2_def.sv` | `eh2_trace_pkt_t` 增加 3 个字段 |
| `rtl/design/dec/eh2_dec_decode_ctl.sv` | 加 6 个 rvdffe（i0/i1 × wdata/waddr/wen，wb1 阶段） |
| `rtl/design/dec/eh2_dec_decode_ctl.sv` | 端口列表 output `dec_i0_wdata_wb1` 等 |
| `rtl/design/dec/eh2_dec.sv` | 端口透传 + tracep 块连线 |
| `rtl/design/eh2_veer.sv` | trace 端口列表加新字段 |

### 详细规格

**1. eh2_trace_pkt_t（include/eh2_def.sv:6-14）**

```systemverilog
typedef struct packed {
   logic [1:0]  trace_rv_i_valid_ip;
   logic [63:0] trace_rv_i_insn_ip;
   logic [63:0] trace_rv_i_address_ip;
   logic [1:0]  trace_rv_i_exception_ip;
   logic [4:0]  trace_rv_i_ecause_ip;
   logic [1:0]  trace_rv_i_interrupt_ip;
   logic [31:0] trace_rv_i_tval_ip;
   // ↓↓↓ 新增（仅 verification 用）
   logic [1:0]       trace_rv_i_rd_valid_ip;   // {i1_wb_valid, i0_wb_valid}
   logic [9:0]       trace_rv_i_rd_addr_ip;    // {i1_rd[4:0], i0_rd[4:0]}
   logic [63:0]      trace_rv_i_rd_wdata_ip;   // {i1_wdata[31:0], i0_wdata[31:0]}
} eh2_trace_pkt_t;
```

**2. eh2_dec_decode_ctl.sv：加 wb1 阶段流水**

参考现有 `i0wb1instff` (line 2992)、`i0wb1pcff` (line 3007) 的 pattern：

```systemverilog
logic [31:0] i0_wdata_wb1, i1_wdata_wb1;
logic [4:0]  i0_waddr_wb1, i1_waddr_wb1;
logic        i0_wen_wb1,   i1_wen_wb1;

rvdffe #(32) i0wb1wdataff (.*, .en(i0_wb1_data_en & trace_enable),
                            .din(i0_result_wb[31:0]), .dout(i0_wdata_wb1[31:0]));
rvdffe #(32) i1wb1wdataff (.*, .en(i1_wb1_data_en & trace_enable),
                            .din(i1_result_wb[31:0]), .dout(i1_wdata_wb1[31:0]));
rvdffe #(5)  i0wb1waddrff (.*, .en(i0_wb1_data_en & trace_enable),
                            .din(wbd.i0rd[4:0]),       .dout(i0_waddr_wb1[4:0]));
rvdffe #(5)  i1wb1waddrff (.*, .en(i1_wb1_data_en & trace_enable),
                            .din(wbd.i1rd[4:0]),       .dout(i1_waddr_wb1[4:0]));
rvdffe #(1)  i0wb1wenff   (.*, .en(i0_wb1_data_en & trace_enable),
                            .din(wbd.i0v & ~dec_tlu_i0_kill_writeb_wb),
                            .dout(i0_wen_wb1));
rvdffe #(1)  i1wb1wenff   (.*, .en(i1_wb1_data_en & trace_enable),
                            .din(wbd.i1v & ~dec_tlu_i1_kill_writeb_wb),
                            .dout(i1_wen_wb1));

assign dec_i0_wdata_wb1[31:0] = i0_wdata_wb1[31:0];
assign dec_i1_wdata_wb1[31:0] = i1_wdata_wb1[31:0];
assign dec_i0_waddr_wb1[4:0]  = i0_waddr_wb1[4:0];
assign dec_i1_waddr_wb1[4:0]  = i1_waddr_wb1[4:0];
assign dec_i0_wen_wb1         = i0_wen_wb1;
assign dec_i1_wen_wb1         = i1_wen_wb1;
```

**3. eh2_dec.sv tracep 块（line 999–1014）增加：**

```systemverilog
assign trace_rv_trace_pkt[i].trace_rv_i_rd_valid_ip = {dec_i1_wen_wb1, dec_i0_wen_wb1};
assign trace_rv_trace_pkt[i].trace_rv_i_rd_addr_ip  = {dec_i1_waddr_wb1, dec_i0_waddr_wb1};
assign trace_rv_trace_pkt[i].trace_rv_i_rd_wdata_ip = {dec_i1_wdata_wb1, dec_i0_wdata_wb1};
```

**4. eh2_veer.sv trace 端口（line 1475–1481）增加：**

```systemverilog
assign trace_rv_i_rd_valid_ip[i][1:0]  = trace_rv_trace_pkt[i].trace_rv_i_rd_valid_ip[1:0];
assign trace_rv_i_rd_addr_ip[i][9:0]   = trace_rv_trace_pkt[i].trace_rv_i_rd_addr_ip[9:0];
assign trace_rv_i_rd_wdata_ip[i][63:0] = trace_rv_trace_pkt[i].trace_rv_i_rd_wdata_ip[63:0];
```

并在 module 端口声明里加：

```systemverilog
output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_rd_valid_ip,
output logic [pt.NUM_THREADS-1:0] [9:0]  trace_rv_i_rd_addr_ip,
output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_rd_wdata_ip,
```

**5. eh2_veer_wrapper.sv** 同样需要透传这 3 个端口（具体行需 grep 确认）

## 验收标准

- [ ] `make compile SIMULATOR=vcs` 编译通过，无新 warning
- [ ] `make compile SIMULATOR=xlm` 编译通过（如有 Xcelium 环境）
- [ ] `vcs -lint=...` 检查通过
- [ ] 综合 trial（如有 dc_shell）：报告新增 ~150 FF（4 个 rvdffe）
- [ ] 现有 smoke / directed test 仍 PASS（功能行为未变）

## 注意事项

1. **不要把这些信号绑到 dec_tlu_trace_disable 控制之外**——保持与现有 inst_wb1/pc_wb1 一致的 gate
2. **i0_wb1_data_en / i1_wb1_data_en 信号**已在 dec_decode_ctl.sv 中存在，复用即可
3. **wb1 而非 wb 阶段**：与 trace pkt 的 inst_wb1 / pc_wb1 同步对齐，避免与 trace 包错位 1 拍
4. **rd_valid 必须 mask 写回 kill 信号**（dec_tlu_i0_kill_writeb_wb / dec_tlu_i1_kill_writeb_wb），防止异常 / 中断杀掉写回但 cosim 还期望写

## 参考实现

- Ibex 的 `ibex_top_tracing.sv` 是同款做法的工业实证
- Ibex 的 `core_ibex_rvfi_if.sv`（27 个 RVFI 信号）展示完整目标
- 现有 `dec_i0_inst_wb1`（line 3003）的实现 pattern 是直接参照

## 阻塞依赖

无（首发 issue）

## 后续触发

完成后触发 Issue 02（trace_monitor 采样新信号）
