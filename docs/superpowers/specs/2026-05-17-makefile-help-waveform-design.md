# Makefile help 改进：波形支持落地 + 参数适用范围澄清

**日期**：2026-05-17
**范围**：`Makefile`（仅根目录）
**关联**：无新增 ADR；本次仅修 bug + 写文档

## 背景

`make help` 当前"通用"小节列出 6 个参数（`SIMULATOR / PARALLEL / SEED / COV / WAVES / NO_COSIM`），暗示这些参数对所有 target 都生效。实际审计 Makefile 与下游 Python 脚本后发现：

1. **"通用"是误导**：6 个参数各自只对一部分 target 生效；对 `asm / lint / formal / synth / manual / clean / signoff_replay` 这些 target 传这些参数完全无效。
2. **`WAVES=1` 在 `smoke` 和 `regress` 上是失效的**：`run_regress.py` 内部支持 `--waves`（脚本 line 306-307），但主 Makefile 的 `smoke`（line 826-836）和 `regress`（line 838-848）调用 `run_regress.py` 时**没有把 `--waves` 传下去**。这是真实 bug，不是文档问题。
3. **`wave.fsdb` 文件名错**：help line 669 写的是 `wave.fsdb`，实际 `dv/uvm/core_eh2/vcs.tcl:16` dump 的是 `waves.fsdb`（带 s）。
4. **COV 默认值内部矛盾**：`Makefile:130` 是 `COV ?= 1`（顶层默认开），但 `Makefile:354` 与 `Makefile:567` 的 help 写"默认 0"。导致 `make compile` 单独跑时，行为与文档不一致。

用户原则：**查看波形是基本操作，所有"实际跑 simv"的 target 都应该原生支持 `WAVES=1`，默认关（省磁盘）**。`compliance` 不在此范围内（compliance 验证靠 signature 比对，原则上不需要波形——明确划入范围外）。

## 设计

### 适用范围审计（基线事实，本设计基于此）

| Target | 是否跑 simv | -kdb 编译期 | --waves 运行期 | 现状 |
|--------|-------------|-------------|----------------|------|
| `compile` | 否（只编译 simv） | ✓ Makefile:801 | N/A | OK |
| `smoke` | 是 via run_regress.py | ✓（自动触发 compile） | ❌ **未转发** | 需修 1 行 |
| `regress` | 是 via run_regress.py | ✓（自动触发 compile） | ❌ **未转发** | 需修 1 行 |
| `signoff` | 是 via signoff.py | 靠预先 `make compile WAVES=1` | ✓ Makefile:902 + signoff.py:212 | OK |
| `signoff_replay` | 否（纯 gate-only） | N/A | N/A | N/A |
| `compliance` | 是 via run_compliance.py | — | ❌ 不支持 | **本设计明确不做**：compliance 看 signature，不需要波形 |
| `demo` | 通过 signoff 间接仿真 | 命令行变量自动传播 | 命令行变量自动传播 | OK |

### 改动 1：修复 smoke / regress 的 `WAVES` 转发（代码）

**目标文件**：`Makefile`

`smoke` target（line 826-836）末尾追加：
```makefile
  $(if $(filter 1,$(WAVES)),--waves,)
```

`regress` target（line 838-848）末尾追加同样的转发行。

**期望行为**（修复后）：
- `make smoke WAVES=1`：自动重新 compile simv（带 `-kdb`），然后 simv 运行时挂 `-ucli -do dv/uvm/core_eh2/vcs.tcl`，dump `build/smoke/<test>_s1/waves.fsdb`。
- `make regress TEST=<name> WAVES=1`：类似，dump 在 `build/regression/<test>_s<seed>/waves.fsdb`。

### 改动 2：修复 COV 默认值矛盾（代码）

**取舍**：把 `Makefile:130` 的 `COV ?= 1` 改为 `COV ?= 0`，让顶层默认与 help 文档一致。理由：

- 单独跑 `make compile` 默认带覆盖率插桩会让用户意外。
- `signoff` target 在调用 `signoff.py` 时显式传 `--coverage`，不依赖顶层默认（line 900）。
- `demo` target 显式传 `COV=1` 给所有 sub-make（line 937-938）。
- 仅 `regress` 当前行为会因此从"默认开 cov"变成"默认不开 cov"。help 已经写"默认 1"，需同步改为"默认 0"以与新默认值一致（或保留 `regress` 自己的默认 1——见下方决策点）。

**决策点**：`regress` 是否保留自己的 `COV ?= 1`？倾向**保留**：跑回归通常就是为了 cov，且 help 在 `regress` 段已声明"默认 1"。实现上让 `regress` 段使用 `$(if $(COV),$(COV),1)` 风格 fallback 而不依赖顶层默认。但这会引入复杂度——更简单的实现是顶层就 `COV ?= 1`，但 help 必须诚实写明"顶层默认 1，影响 compile/regress"。

**最终选择**：**保持 `COV ?= 1` 不动，修 help 让它讲实话**。改 help 比改逻辑风险低，且当前 help 描述与实际不符是更直接的问题。

### 改动 3：重写 help（文档）

#### 3.1 删除现状的"通用"小节
当前 line 563-569 的"通用"小节具有误导性，整段删除，替换为下面的"参数适用范围速查"。

#### 3.2 新增"参数适用范围速查"小节
位置：紧跟"15 个核心 target，按 5 组组织"那段，作为读者进入正文前的导航。形式为简表：

```
┌────────────────┬───────────────────────────────────────────────────────────────┐
│ 变量           │ 对以下 target 生效（其它 target 传了无效）                    │
├────────────────┼───────────────────────────────────────────────────────────────┤
│ SIMULATOR      │ compile / smoke / regress / signoff                           │
│ PARALLEL       │ regress / signoff / demo                                      │
│ SEED           │ regress / signoff                                             │
│ COV            │ compile / regress / signoff                                   │
│ WAVES          │ compile / smoke / regress / signoff / demo（所有"实际仿真"的）│
│ NO_COSIM       │ cosim / compile                                               │
└────────────────┴───────────────────────────────────────────────────────────────┘
```

#### 3.3 新增"查看波形（FSDB）"小节
位置：放在"典型工作流"小节里，介于"调试单测"和"完整 sign-off"之间，作为一等公民工作流而不是脚注。

内容大纲：
- **原则**：所有跑 simv 的 target 都原生支持 `WAVES=1`，默认关（节省磁盘，单测 fsdb 数十 MB 起步）。
- **机制**（一句话）：`WAVES=1` 同时影响编译期（`-kdb`）和运行期（`-ucli -do vcs.tcl`）。make 自动传播，用户只需在命令行加一次。
- **产物路径**：
  - `smoke`：`build/smoke/<test>_s1/waves.fsdb`
  - `regress`：`build/regression/<test>_s<seed>/waves.fsdb` 或 `$(OUT)/<test>_s<seed>/waves.fsdb`
  - `signoff`：`build/signoff/runs/<stage>/<test>_s<seed>/waves.fsdb`
  - `demo`：`build/demo/runs/<stage>/<test>_s<seed>/waves.fsdb`
- **查看器**：`verdi -ssf <path>/waves.fsdb`（推荐，环境已装；KDB 自动加载，可以源码联动）
- **每个 sim target 一个最短示例**：
  ```
  make smoke WAVES=1
  verdi -ssf build/smoke/smoke_s1/waves.fsdb

  make regress TEST=riscv_arithmetic_basic_test WAVES=1
  verdi -ssf build/regression/riscv_arithmetic_basic_test_s1/waves.fsdb

  make signoff WAVES=1     # 注意：所有 stage 都会 dump，磁盘需求显著上升
  ```
- **磁盘成本提示**：单测 ~50-200MB，full signoff 可能数十 GB；调试时单测跑，不要全 signoff 开 WAVES。
- **`compliance` 显式不支持**：单独一行说明"`make compliance` 不支持 `WAVES`——compliance 验证靠 signature 比对，原则上不需要波形"。

#### 3.4 修正 `wave.fsdb` → `waves.fsdb`
Help line 669 现有的"调试单测"示例同步修正。

#### 3.5 调整 `compile` / `regress` 段的 COV 说明
让两处描述与 `Makefile:130` 的 `COV ?= 1` 一致：

- `compile` 段（line 354）：把"默认 0；demo 自动设 1"改成"默认 1；可显式 `COV=0` 关闭"。
- `regress` 段（line 397）：保持"默认 1"（与现状一致，无需改）。
- 已删除的"通用"小节自然不再矛盾。

## 不做的事（明确划出）

- **不动 `compliance` 的波形支持**。原则上不需要；改 Python 脚本 + 两层 Makefile 的代价远大于价值。
- **不重构 help 整体结构**。只动有问题的几段。
- **不动 Makefile 的逻辑默认值**（`COV ?= 1` 保留），只让文档讲实话。
- **不动其它脚本**（`run_regress.py / signoff.py / vcs.tcl`），它们都已正确实现波形支持。

## 验证（完成定义）

1. `make smoke WAVES=1` 跑完后，`build/smoke/smoke_s1/waves.fsdb` 文件存在且体积 > 1MB。
2. `make regress TEST=riscv_arithmetic_basic_test WAVES=1` 跑完后，对应 work_dir 下 `waves.fsdb` 存在。
3. `verdi -ssf <path>/waves.fsdb` 能正常打开（不需要在本设计内执行，但是说明里需要给出这条命令）。
4. `make help | grep -A 20 "参数适用范围速查"` 显示新表格。
5. `make help` 全文不再出现 `wave.fsdb`（统一为 `waves.fsdb`）。
6. `make help` 中 `compile` 段不再写"默认 0"。

## 变更文件清单

- `Makefile` — 2 处单行修复 + help 文本重写
- 本规格本身 commit 入 git

无其他文件改动。
