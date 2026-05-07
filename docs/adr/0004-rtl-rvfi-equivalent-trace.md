# ADR-0004: RTL trace 包增加 verification-only rd_addr/rd_wdata 字段

- 状态：Proposed（Phase 1 待执行）
- 日期：2026-05-06
- 取代：ADR-0001（部分）

## 上下文

ADR-0001 的双通道架构在实践中产生 cosim 闭环不收敛问题：

- `eh2_cosim_scoreboard.sv` 膨胀到 1026 行（Ibex 等价仅 361 行）
- 引入 `WB_SEARCH_DEPTH` band-aid 限制启发式搜索
- NB-load / DIV cancel / interrupt-killed wb 等异步事件需要专门 corner 处理
- 50+ 个调试 build 目录在 build/ 累积，反映多次试错

根因：trace 通道与 wb 通道**没有可靠对应关系**——靠 #0 延迟 + rd 匹配 + 搜索窗口启发式。

## 决策

参考 Ibex `ibex_top_tracing.sv` 的做法，**在 EH2 RTL 层把 verification-only 信号引出到 trace 包**：

1. `rtl/design/include/eh2_def.sv` 中 `eh2_trace_pkt_t` 增加：
   - `logic [1:0][4:0]  trace_rv_i_rd_addr_ip;`  // 每个 slot 的 rd 地址
   - `logic [1:0][31:0] trace_rv_i_rd_wdata_ip;` // 每个 slot 的写回数据
   - `logic [1:0]       trace_rv_i_rd_valid_ip;` // 每个 slot 的写回 valid

2. `rtl/design/dec/eh2_dec_decode_ctl.sv` 增加 wb1 阶段的 wdata/waddr 寄存器（对齐现有 inst_wb1/pc_wb1 流水）：
   - `rvdffe i0wb1wdataff` / `i1wb1wdataff`：i0/i1_result_wb 流水到 wb1
   - `rvdffe i0wb1waddrff` / `i1wb1waddrff`：wbd.i0rd / wbd.i1rd 流水到 wb1
   - `rvdffe i0wb1wenff` / `i1wb1wenff`：wbd.i0v & ~kill / i1v & ~kill 流水到 wb1

3. `rtl/design/dec/eh2_dec.sv` tracep 块新增 assign：将 wb1 寄存器输出连入 `trace_rv_trace_pkt[i].trace_rv_i_rd_*_ip`

4. `rtl/design/eh2_veer.sv` trace 端口列表：将新字段从 trace_pkt 解包出来（与现有 trace_rv_i_* 端口并列）

5. UVM 侧：
   - `eh2_trace_intf.sv` 增加同名信号
   - `eh2_trace_monitor.sv` 直接采样 rd_addr/rd_wdata 填入 trace_seq_item
   - `eh2_cosim_scoreboard.sv` 删除 `pending_wb_q[2][$]`、`wb_search_depth`、`run_cosim_probe` 主路径
   - `eh2_dut_probe_monitor.sv` 仅保留 nb_load / div_cancel 异步通道
   - 预期 scoreboard 从 1026 → ~500 行

## 影响评估

| 维度 | 影响 | 风险 |
|------|------|------|
| 功能行为 | 0（纯组合 + 已有信号 + verification 输出） | 无 |
| 时序 | 4 个新 rvdffe（wb1 阶段），与现有 i0wb1instff/i1wb1instff 同样负载 | 低 |
| 综合面积 | +~150 FF（4 × 37 bit） | 可忽略 |
| 验证 | 大幅简化 cosim scoreboard | 正向 |
| 上游兼容 | trace_pkt 是内部 struct，外部端口可选用 `RV_DV_VERIFICATION` 包裹 | 低 |
| 上游回流 | 需评估：是否要加 `ifdef` 开关 | 中（可选） |

## 备选方案

| 方案 | 描述 | 评估 |
|------|------|------|
| A. 不动 RTL，scoreboard 内 batch matching | 按 cycle 分组 trace 与 wb 严格对齐 | scoreboard 复杂度不降，不解决根因 |
| **B. 加 RTL verification hooks（本 ADR）** | Ibex 同款做法 | **选定** |
| C. trace_monitor 同步采样 vif.wb_seq | 半成品延伸 | 同周期竞态，治标 |

## 后果

### 正面
- cosim scoreboard 与 Ibex 同等复杂度
- 删除 band-aid，平台真正进入工业级
- 可以为 NUM_THREADS=2 cosim 扩展打地基

### 负面
- 涉及 RTL 改动，需要充分验证综合时序中性
- 需要在所有 RTL filelist 里同步声明新信号（dec.sv / veer.sv / wrapper / shared）
- 上游回流时需评估 `ifdef RV_DV_VERIFICATION` 包裹策略

## 实施计划

详见 `.scratch/platform-industrialization/issues/01-rtl-add-rvfi-equivalent.md`
和 PHASE1_PLAN.md。

## 验证标准

- ✅ `make compile SIMULATOR=vcs` 通过
- ✅ smoke + 5 个 riscv-dv 随机 test cosim 全部 mismatch_count == 0
- ✅ `make signoff SIGNOFF_PROFILE=full` 全 stage PASS
- ✅ `WB_SEARCH_DEPTH` 从代码中删除
- ✅ `pending_wb_q` 从 scoreboard 中删除（仅留 nb_load 异步队列）
