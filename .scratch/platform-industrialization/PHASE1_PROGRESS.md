# Phase 1 实施进度（2026-05-06 会话最终状态 — 完全闭环成功）

## 总结

**Phase 1 完全闭环达成** 🎉

- Smoke + cosim: **0 mismatches, RESULT: PASS**
- riscv_arithmetic_basic_test 5 seeds: **5/5 PASS, 0 mismatches**（每个 seed 包含数百~数千条 div/rem/mul/load/store/branch 指令）
- scoreboard 1026 → 871 行（-15%），删除所有 band-aid
- 复杂 EH2 推测 div 取消语义已正确处理

## 解决路径

### 问题诊断（用户提问引出的关键洞察）

用户问"Ibex 怎么处理 div？"——我去看了 Ibex `ibex_top_tracing.sv` 和 `ibex_core.sv:1357`，发现：

```systemverilog
// Ibex 的 RVFI rd_wdata 在两个写口之间 mux：
assign rvfi_rd_wdata_wb = rf_we_wb ? rf_wdata_wb : rf_wdata_lsu;
```

Ibex 的 multdiv **同步**写 RF，wb stage 锁存最终数据。EH2 的 div **真异步**+有 `nonblock_div_cancel` 优化。

但根本问题不是 div 闭环不可能，而是 **EH2 的 cancel 信号有两种语义被混在一起**：
- `nonblock_div_cancel & div_flush`：speculative 取消（trace 没该 div）
- `nonblock_div_cancel & 同 rd 覆盖`：架构 retire 但被 RF 覆盖（trace 有该 div）

UVM 层无法区分两种 cancel，只能丢弃所有 cancel（v12，92 mismatch）或保留所有 cancel（v13，1890 mismatch）。

### 解决方案：RTL 端区分 cancel 类型

**关键改动**：`rtl/design/dec/eh2_dec_decode_ctl.sv` 把 nonblock_div_cancel 拆成两个信号：

```systemverilog
assign nonblock_div_cancel_flush     = (div_valid & div_flush);
assign nonblock_div_cancel_overwrite =
                  (div_valid & ~div_e1_to_wb & wbd.i0rd==div_rd & i0_wen_wb) |
                  (div_valid & ~div_e1_to_wb & wbd.i1rd==div_rd & i1_wen_wb) |
                  (div_valid & wbd.i0div & wbd.i0rd==wbd.i1rd & i1_wen_wb);
assign nonblock_div_cancel = nonblock_div_cancel_flush | nonblock_div_cancel_overwrite;

assign dec_div_cancel = nonblock_div_cancel;
assign dec_div_cancel_overwrite = nonblock_div_cancel_overwrite;  // verification-only
```

UVM probe_monitor:
- 收到 `div_wren`: 入队 wb hint
- 收到 `div_cancel & div_cancel_overwrite`: 入队 cancel hint（suppress=1）—— 对应 trace 中的 div
- 收到 `div_cancel & !div_cancel_overwrite`: **丢弃**（speculative）—— 没对应 trace

UVM scoreboard:
- div trace 等 async wb hint, FIFO 取队首
- 拿到 wb hint: 用 hint.rd_data 调 Spike step
- 拿到 cancel hint: suppress_reg_write=1, Spike 撤销内部 RF 写

### 同时还修了 Load 闭环

发现：EH2 所有 load 都走 nb_load 通道（`cam_load_kill_wen` 不是"被杀"，是"走异步路径"）。trace pkt 的 wb_valid 对 load 也是 0。

修复：scoreboard 的 `needs_async_wb` 也对 load 等待 nb_load hint。

## 最终状态

### 修改文件 (vs baseline)

| 文件 | 改动 | 性质 |
|------|------|------|
| `rtl/design/include/eh2_def.sv` | +5 | trace_pkt 加 rd_valid/addr/wdata 字段 |
| `rtl/design/dec/eh2_dec_decode_ctl.sv` | +40 | 6 输出 + 2 rvdffe + cancel 拆分 |
| `rtl/design/dec/eh2_dec.sv` | +7 | 信号 + tracep 连线 |
| `rtl/design/eh2_veer.sv` | +7 | 端口 + assign + cancel_overwrite |
| `rtl/design/eh2_veer_wrapper.sv` | +3 | 端口透传 |
| `dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv` | +25 | 信号 + 便利赋值 |
| `dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv` | +12 | 采样新字段 |
| `dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_intf.sv` | +1 | div_cancel_overwrite |
| `dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv` | -60 | 简化 + 区分 cancel |
| `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv` | -155 | 删 band-aid + 加 async gate |
| `dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` | +14 | 信号连接 |

### 验证证据

**Smoke + cosim:**
```
=== Co-simulation Scoreboard Report ===
Trace items received: 6
Steps executed:       6
Mismatches:           0
RESULT: PASS
UVM_ERROR : 0
UVM_FATAL : 0
TEST PASSED (mailbox)
TEST PASSED (signature)
```

**riscv_arithmetic_basic_test 5 seeds:**
```
Seed 1: PASS, 0 mismatches, 3649 steps
Seed 2: PASS, 0 mismatches
Seed 3: PASS, 0 mismatches, 7534 steps
Seed 4: PASS, 0 mismatches, 1480 steps
Seed 5: PASS, 0 mismatches, 256 steps
Pass rate: 100.0%
```

**Code metrics:**
```
$ wc -l eh2_cosim_scoreboard.sv → 871 (vs 1026 baseline = -15%)
$ wc -l eh2_dut_probe_monitor.sv → 118 (vs 178 baseline = -34%)
$ grep WB_SEARCH_DEPTH pending_wb_q → 0 matches
```

### 未涉及 / 后续 Phase

- **riscv_random_instr_test**: testlist 已 `cosim: disabled`，因为含中断/异常 cosim 处理需要单独修复（独立 bug，与 div 无关）
- **riscv_load_store_test / riscv_mul_div_test**: riscv-dv 生成阶段失败 (`GEN_NO_ASM`)，与 cosim 无关
- 这些独立问题不影响 Phase 1 的 div/load 闭环成果

## Phase 1 总结

按 ADR-0004 设计目标，Phase 1 完全达成：
- ✅ scoreboard 复杂度大幅降低（-15%）
- ✅ band-aid 全部删除（WB_SEARCH_DEPTH / pending_wb_q / wb_seq_counter）
- ✅ smoke cosim 完全闭环
- ✅ **arithmetic_basic 多 seed 100% cosim 闭环**（包含 div/rem/mul/branch/load/store 等所有指令）
- ✅ EH2 推测 div 取消语义正确处理
- ✅ Load 通过 nb_load 通道闭环

这是工业级 cosim 闭环的核心成就。后续 Phase 2 处理：
- 结构整理（env 接口归位 / TB top 拆分 / agent 命名统一）
- 中断/异常 cosim
- 余下未通过的 testlist 项目
- signoff full profile

## 下次会话起点

1. 读本文件了解 Phase 1 成果
2. 决定进入 Phase 2 还是先扩大 cosim 测试覆盖
3. 验证 Phase 1 改动可否合并 git commit
4. 评估 Phase 2 优先级：env/ 归位 vs TB top 拆分 vs cosim 中断处理
