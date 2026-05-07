# ADR-0001: Cosim 数据通路 — trace 包 + probe 接口

- 状态：Accepted（当前实现），**Superseded by ADR-0004**（Phase 1 之后）
- 日期：2026-05-04
- 相关：docs/cosim-correctness-analysis.md, ADR-0004

## 上下文

EH2 RTL **没有 RVFI 接口**。Ibex 的 cosim 闭环依赖 RVFI：每条 retired 指令一个完整快照（rd_addr/rd_wdata/mem_*/csr_* 全部 27 个信号），scoreboard 直接拿 RVFI item 喂 Spike 一比一对照。

EH2 RTL 只有 trace 包（PC + insn + exception + interrupt + tval），没有 rd_addr/rd_wdata。要做 cosim 必须从其它地方拿到寄存器写回数据。

## 决策

通过两条独立通道在 UVM monitor 层重建 RVFI 等价信息：

1. **trace 通道**：`eh2_trace_monitor` 监视 RTL trace 包，给出 PC + insn + exception
2. **probe 通道**：`eh2_dut_probe_monitor` 通过 hierarchical reference 直接读 DUT 内部写回信号 (`wbd.i0v/i1v`, `i0_result_wb`)，再加 div / nb_load 异步通道
3. **scoreboard** 在两条通道间做 per-slot 队列匹配

## 后果

### 正面
- 不需要改 RTL（保持 EH2 RTL 与 chipsalliance 上游兼容）
- 利用现有内部信号，工作量集中在 UVM 层

### 负面
- **同周期同步靠 `#0` 延迟硬撑**——SystemVerilog scheduler 在某些 corner 不保证两 monitor 严格顺序
- **wb 与 trace 对应关系靠启发式**：rd 匹配 + wb_search_depth 窗口（典型 band-aid）
- **scoreboard 复杂度爆炸**：1026 行（Ibex 等价 361 行）
- NB-load / DIV cancel 等异步事件需要专门通道，多分支逻辑

## 已尝试的修补

- 加 wb_seq_counter 全局序号（probe 端）—— 但 trace_monitor 没读，半成品状态
- 加 wb_search_depth 限制启发式搜索范围 —— 仅缓解症状
- 加 #0 延迟保证 probe 先入队 —— 在双发射 + NB-load 场景仍有 race

## 相关链接

- `dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
- `dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
- `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
- `docs/cosim-correctness-analysis.md`（详细数据通路分析）

## 演进

ADR-0004 提议在 RTL trace 包中增加 rd_addr/rd_wdata 字段（仅 verification 用），让 trace 通道直接携带写回信息，废弃 probe 通道的写回主路径，把 scoreboard 简化到 ~500 行。
