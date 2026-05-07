# Phase 1 实施计划 — cosim 闭环修复

**目标**：让 EH2 cosim 真正闭环，scoreboard 复杂度降到与 Ibex 同级，sign-off full profile 全 stage PASS。

**预计工时**：连续工作 2–3 天（含编译/仿真等待）

**前置条件**：阅读
- `CONTEXT.md`（领域语言）
- `docs/adr/0004-rtl-rvfi-equivalent-trace.md`（设计决策）
- `.scratch/platform-industrialization/README.md`（总览）

---

## Step-by-step

### Step 1: RTL 改动（Issue 01）— 4–6 小时

按 `.scratch/platform-industrialization/issues/01-rtl-add-rvfi-equivalent.md` 执行。

**风险点**：
- `eh2_def.sv` 是 `eh2_pkg` 包，所有引用 `eh2_trace_pkt_t` 的 RTL 模块都要重新编译
- 加新 rvdffe 时小心 `i0_wb1_data_en` / `i1_wb1_data_en` 的实际位置（可能在不同 `generate` 块内）
- `wbd.i0v` 是 `eh2_dest_pkt_t` 的字段，确认 wb1 阶段是否还有该字段（应该有，wbd 本身就是 wb 阶段）

**验证**：
```bash
make compile SIMULATOR=vcs 2>&1 | tee /tmp/phase1_step1_compile.log
grep -i "error\|fatal" /tmp/phase1_step1_compile.log
```

### Step 2: trace_monitor 改动（Issue 02）— 1–2 小时

按 `02-trace-monitor-sample-wb.md` 执行。

**验证**：
```bash
# Smoke 用 UVM_HIGH 跑，确认 wb_dest/wb_data 非零
make run TEST=smoke BINARY=tests/asm/smoke.hex \
  SIM_OPTS="+UVM_VERBOSITY=UVM_HIGH +disable_cosim=1" \
  OUT=build/phase1_step2
grep "trace_monitor.*Commit:" build/phase1_step2/runs/.../*.log | head -10
```

期望看到：
```
trace_monitor: Commit: t0.0 PC=80000000 INSN=0d600113 OK rd=x2 wdata=00000000d6
```

### Step 3: scoreboard 简化（Issue 03）— 4–6 小时

按 `03-scoreboard-simplify.md` 执行。

**风险点**：
- 删除 `pending_wb_q` 和 `dut_probe_fifo` 后，env 的 connect_phase 也要相应改（去掉 probe 连接到 scoreboard）
- `process_pending_trace` 内的 mem access 等待逻辑要保留
- nb_load 队列会在 Issue 04 重新接入，**先不要急着接**——Step 3 验证时把 nb_load 测试暂时屏蔽

**验证**：
```bash
# 行数检查
wc -l dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
# 期望 ≤ 500

# grep 残留 band-aid
grep -n "WB_SEARCH_DEPTH\|pending_wb_q\|wb_search_depth" \
  dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
# 期望 0 行匹配
```

跑 smoke + 1 个 random（cosim 开启）：
```bash
make run TEST=riscv_arithmetic_basic_test SEED=1 \
  COSIM=1 OUT=build/phase1_step3
```

期望 mismatch_count == 0。

### Step 4: probe_monitor 改造（Issue 04）— 2–3 小时

按 `04-probe-monitor-keep-async.md` 执行。

**关键**：保留 nb_load / div_cancel 通道，删主路径 wb 通道。scoreboard 加 `pending_async_wb_q`。

**验证**：跑含 div / mul 的 test：
```bash
make run TEST=riscv_load_store_test COSIM=1 SEED=42 OUT=build/phase1_step4
# log 内查找 "DIV WB" / "NB LOAD"
```

### Step 5: testlist 恢复（Issue 05）— 1 小时

按 `05-testlist-enable-cosim.md` 执行。

```bash
# 把至少 5 个 random test 从 cosim:disabled 改为开启
vim dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml

# 跑 riscvdv 阶段
make run GOAL=collect_results OUT=build/phase1_step5_riscvdv \
  TEST=all_random ITERATIONS=5 SIMULATOR=vcs COSIM=1
```

### Step 6: 全量 sign-off（Issue 06）— 4–6 小时

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 \
  SIGNOFF_OUT=build/phase1_signoff 2>&1 | tee /tmp/phase1_signoff.log
```

期望 `build/phase1_signoff/signoff_status.json` 顶层 `status: PASS`。

---

## 失败回滚

如果 Step 1（RTL）改动后任何 corner 不通：
```bash
git diff rtl/design/include/eh2_def.sv
git diff rtl/design/dec/eh2_dec_decode_ctl.sv
git diff rtl/design/dec/eh2_dec.sv
git diff rtl/design/eh2_veer.sv
git checkout rtl/  # 全部回退 RTL 改动
```

转向 ADR-0004 备选方案 A（纯 UVM 修复，不改 RTL）：在 monitor 层做 batch matching。

---

## 完成标准

Phase 1 收尾交付物：
- ✅ `build/phase1_signoff/signoff_status.json` 顶层 `status: PASS`
- ✅ scoreboard 行数 ≤ 500
- ✅ 全代码库无 WB_SEARCH_DEPTH 引用
- ✅ 至少 5 个 random test 的 cosim 通过
- ✅ Issue 01–06 全部 status: completed
- ✅ git commit message：`feat: Phase 1 cosim 闭环修复 — RTL 引出 wb 信号 + scoreboard 简化`

完成后停下，向用户汇报，等 review 后进入 Phase 2。

---

## Phase 2 预告（不在本次实施范围）

- env/ 接口归位
- TB top 拆分
- agent 前缀统一
- scoreboard 拆子模块
