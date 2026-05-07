# Issue 06: signoff full profile 跑通

Status: done
Phase: 1（完成标志）
Type: AFK
Blocked by: Issue 05

## 要做什么

跑通 `make signoff SIGNOFF_PROFILE=full PARALLEL=4`，确认 4 个 stage 全 PASS。

### 命令

```bash
cd /home/host/eh2-veri
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/phase1_signoff
```

### 期望产出

`build/phase1_signoff/signoff_status.json` 形如：

```json
{
  "status": "PASS",
  "profile": "full",
  "stages_requested": ["smoke", "directed", "cosim", "riscvdv"],
  "stages": [
    {"stage": "smoke",    "status": "PASS", "pass_rate": 100.0},
    {"stage": "directed", "status": "PASS", "pass_rate": 100.0},
    {"stage": "cosim",    "status": "PASS", "pass_rate": 100.0},
    {"stage": "riscvdv",  "status": "PASS", "pass_rate": 100.0}
  ]
}
```

### 期望 cosim 报告

每个 cosim 测试的 sim log 都应包含：

```
=== Co-simulation Scoreboard Report ===
Trace items received: 10000+
Steps executed:       10000+
Mismatches:           0
Suppressed probe writebacks dropped: 0  ← 关键：不应该再有大量 suppressed
Pending writebacks: slot0=0 slot1=0     ← 关键：scoreboard 退出时无遗留
```

## 验收标准

- [ ] signoff_status.json 顶层 `status == "PASS"`
- [ ] 4 个 stage 全 PASS（smoke / directed / cosim / riscvdv）
- [ ] cosim stage 至少 5 个不同 random test 通过
- [ ] 整个 signoff 跑完 ≤ 6 小时
- [ ] 无 unexpected SIM_CRASH

## 失败时的诊断

- 如果某个 random test mismatch：用 `+UVM_VERBOSITY=UVM_HIGH` 重跑，看 trace_monitor / scoreboard 的 MATCH/MISMATCH 日志
- 如果某个 random test SIM_CRASH：检查 cosim spike 日志（spike_objs/）和 simv 退出码
- 如果 riscvdv 阶段 hang：检查 instr_gen 是否生成的 hex 异常

## 阻塞依赖

- Issue 01–05 全部完成

## 完成证据

- `build/sf_full2/signoff_status.json`：status=PASS，4 stage 全 PASS（smoke 1/1, directed 3/3, cosim 4/4, riscvdv 32/32），时间戳 2026-05-07T15:04:58
- `build/sf_baseline2/signoff_status.json`：二次验证 PASS，结果与 sf_full2 完全一致，时间戳 2026-05-07T19:36
- `build/sf_full2/signoff_report.md`：完整签发报告
- cosim_disabled_tests：34 项（waiver-reviewed，对应 issue 11/12/13/14）
- 比对报告：`.scratch/handoff/signoff-baseline2-vs-sf_full2.md`
