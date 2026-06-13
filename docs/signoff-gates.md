# EH2 Sign-off Gates

本文档说明 EH2 sign-off 流程中每条 gate 的语义、如何 waive、如何 escape。

## 总览

`make signoff SIGNOFF_PROFILE=full` 会经过以下判定门：

| # | Gate | 默认 | 语义 | Escape Hatch |
|---|------|------|------|--------------|
| 1 | coverage requirement | ON | 必须能解析到覆盖率报告，否则 sign-off FAIL | `--no-require-coverage` |
| 2 | line coverage | ≥ 60% | 行覆盖率低于 60% → FAIL | `--min-line-coverage 0` |
| 3 | functional coverage | ≥ 50% | 功能覆盖率低于 50% → FAIL | `--min-functional-coverage 0` |
| 4 | cosim-disabled gate | ON | 任何 testlist 条目 `cosim: disabled` 必须在 waivers 中显式 waive | `--no-fail-on-cosim-disabled` |
| 5 | skip-in-signoff gate | ON | 任何 `skip_in_signoff: true` 必须在 waivers 中显式 waive | `--no-fail-on-skip-in-signoff` |
| 6 | directed pool check | ON | `tests/asm/directed_*.S` 必须在 `directed_testlist.yaml` 中显式列出 | 无可 escape（必须补齐） |
| 7 | 实跑覆盖率 | ≥ 95% | 实跑测试数 / 总池子数 < 95% → 状态降级为 PARTIAL | 无可 escape |
| 8 | LEC tool-version waiver | OFF | ADR-0019 覆盖的 Formality 版本限制可降级为 `WAIVE_TOOL_LIMITED` | `--lec-known-limited` |

## Gate 1: 覆盖率要求

**默认值**: ON

sign-off 会从 stage 输出目录搜索覆盖率报告文件（`dashboard.txt`、`summary.txt`、`urgReport.html` 等）。如果找不到、或解析失败，且 `--no-require-coverage` 未设置，sign-off FAIL。

**什么情况下 waive**: 
- 你正在非覆盖率仿真模式下只检查 pass/fail 状态
- Escape: `--no-require-coverage`

## Gate 2 & 3: 覆盖率阈值

**默认值**: line ≥ 60%, functional ≥ 50%

设计原则：
- 60% 行覆盖率是业界最低可接受标准。低于此值表示验证平台没有系统性地跑够指令路径
- 50% 功能覆盖率确保我们至少覆盖了一半的功能空间

**如何调整阈值**:
```bash
# 临时降低或关闭阈值（不推荐）
make signoff SIGNOFF_PROFILE=full \
  SIGNOFF_OPTS="--min-line-coverage 50.0 --min-functional-coverage 40.0"

# 完全关闭
make signoff SIGNOFF_PROFILE=full \
  SIGNOFF_OPTS="--min-line-coverage 0 --min-functional-coverage 0"
```

## Gate 4 & 5: cosim-disabled / skip-in-signoff Gate

**默认值**: ON

扫 `riscv_dv_extension/testlist.yaml`：
- 任何 `cosim: disabled` 条目 → 必须在 `waivers/cosim-disabled.yaml` 有对应 waiver

**Waiver 格式**:
```yaml
- test: riscv_bitmanip_test
  reason: "Bitmanip RTL illegal-instr bug pending investigation. Tracking in issue 60."
  tracking_issue: "https://github.com/example/eh2-veri/issues/60"
  expiry_date: "2026-07-15"  # YYYY-MM-DD
```

**必须三字段**:
- `reason`: 为什么 disabled
- `tracking_issue`: 负责修的 issue 链接/编号
- `expiry_date`: 截止日期，过期后 waiver 失效

**Escape**:
```bash
# 关闭 cosim-disabled gate
make signoff SIGNOFF_PROFILE=full SIGNOFF_OPTS="--no-fail-on-cosim-disabled"

# 关闭 skip-in-signoff gate
make signoff SIGNOFF_PROFILE=full SIGNOFF_OPTS="--no-fail-on-skip-in-signoff"

# 使用自定义 waiver 文件
make signoff SIGNOFF_PROFILE=full \
  SIGNOFF_OPTS="--waivers-cosim-disabled /path/to/custom-waivers.yaml"
```

## Gate 6: Directed 测试池完整性

`tests/asm/` 下每个 `directed_*.S` 必须在 `directed_tests/directed_testlist.yaml` 中有对应 entry。

如果某个 ASM 只写了文件但未在 testlist 注册，sign-off FAIL 并列出缺失项。这是"静默不跑"的最后防线。

**修复方式**: 在 `directed_testlist.yaml` 中添加对应 entry。

## Gate 7: 实跑覆盖率

报告顶部会显示：
```
实跑覆盖率: 40/62 (64.5%) — PARTIAL
```

计算方式: `sum(stage.total) / sum(testlist entries across all stages)`

如果 < 95%：
- 报告整体状态从 PASS 降级为 PARTIAL
- 不等于 FAIL（因为可能有合理 skip），但不能再宣称"全 PASS"

## Gate 8: LEC Tool-version Waiver

ADR-0019 记录了当前 Formality 版本对 2D packed array port 的等价检查限制。该问题会产生固定 bucket 的 LEC fail，但 `syn/build/failing_buckets.md` 中 `True RTL bug / other unmatched` 必须为 0。

启用方式：
```bash
make signoff SIGNOFF_PROFILE=full \
  SIGNOFF_OPTS="--lec-known-limited"
```

启用后：
- 如果 `failing_buckets.md` 中 True RTL bug 数为 0，`syn` stage 状态为 `WAIVE_TOOL_LIMITED`
- 整体状态在无其他 blocker 时为 `PASS_WITH_WAIVERS`
- 如果 True RTL bug 数大于 0，`syn` stage 仍然 FAIL

## 红线

- 不允许为了让 sign-off 跑通把默认值设回旧行为
- 不允许在 waiver 中填假 issue 或未来 expiry 来绕过 gate
- 不允许把正常 disabled 的测试从 testlist 中删除来降低分母

## 验证

```bash
# 在当前 codebase 状态跑 sign-off（应 FAIL）
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_gate_test

# 验证 all escape hatches work
make signoff SIGNOFF_PROFILE=full PARALLEL=4 \
  SIGNOFF_OPTS="--no-require-coverage --no-fail-on-cosim-disabled --no-fail-on-skip-in-signoff"

# 单元测试
cd dv/uvm/core_eh2 && python -m pytest tests/test_signoff_gates.py -v

# waiver schema 校验
python scripts/signoff.py --validate-waivers waivers/cosim-disabled.yaml
```
