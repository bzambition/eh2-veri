# ADR-0015: RVFI 适配层（不改 design RTL）

## Status

ACCEPTED 2026-05-08

## Context

Ibex 在 design 级别内置 RVFI 总线作为 cosim 主接口，通过 RISC-V Formal
Interface 标准化 retire 信息。EH2 design 没有 RVFI（见 ADR-0004），当前
cosim 走 trace_pkt 路径——trace_monitor 从 DUT 拉 trace_i0/i1 信号经由
probe_if 喂给 spike_cosim scoreboard。

工业级对比：
- Ibex: RVFI → riscv-formal + sail-riscv 等价证明
- EH2 当前: trace_pkt → spike_cosim（无标准 retire 接口）

RC3 目标：在不改 upstream design 的前提下，加一层 trace-to-RVFI 适配器，
为 RC4 接入 riscv-formal / sail-riscv 等价证明铺路。

## Decision

在 `rtl/eh2_veer_wrapper_rvfi.sv` 加 trace-to-RVFI 适配层：
- RVFI 信号从现有 trace_pkt + probe_if 信号推导
- 不改 `Cores-VeeR-EH2/design/` 下任何文件
- 双 channel（i0/i1）对应 EH2 双发射

Scoreboard 双路径：
- 主路径：trace_pkt → spike_cosim（保持向后兼容，现有流程）
- 副路径：RVFI → 自洽性检查（rvfi_pc_rdata + rvfi_insn → 计算 next PC，
  与 rvfi_pc_wdata 对比）+（未来）riscv-formal 引擎对接

RVFI 字段对齐（32 位 RVFI spec）：

| RVFI 字段 | EH2 来源 |
|---|---|
| rvfi_valid | trace_i0_valid / trace_i1_valid |
| rvfi_order | wb_seq counter（probe_monitor 维护） |
| rvfi_insn | trace_i0_insn / trace_i1_insn |
| rvfi_pc_rdata | trace_i0_pc / trace_i1_pc |
| rvfi_pc_wdata | next-PC (pc + 2/4) |
| rvfi_rs1_addr / rs2_addr | 解码 trace_insn |
| rvfi_rd_addr / rd_wdata | wb result（probe） |
| rvfi_mem_* | LSU AXI4 monitor |
| rvfi_trap | trace.exception |
| rvfi_intr | trace.interrupt |
| rvfi_mode | 固定 M-mode（EH2 only） |

## Consequences

### 正
- 不破坏现有 trace 路径（向后兼容）
- 为 RC4 接入 riscv-formal / sail-riscv 等价证明铺标准接口
- DUT 输出端有标准 RVFI，方便外部工具集成（如 riscv-formal, RVFI-DII）
- 适配层可独立仿真验证

### 负
- Wrapper 复杂度增加
- RVFI 信号从 trace + probe 推导，非 design 原生，存在"伪 RVFI"风险
- 双 channel 时序对齐（i0/i1 retire 顺序）需额外验证
- rs1/rs2 解码会增加组合逻辑（trace_insn 解码器）

## 相关

- ADR-0004: RTL RVFI-equivalent trace（说明为什么没在 design 加 RVFI）
- PROMPT-O: RC3 RVFI 适配 + 杂务收尾
- Ibex RVFI: https://ibex-core.readthedocs.io/en/latest/03_reference/rvfi.html
