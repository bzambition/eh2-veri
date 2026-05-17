# Per-target 独立 build 目录隔离（target 自包含原则）

**日期**：2026-05-17
**范围**：`Makefile`、`dv/uvm/core_eh2/scripts/{run_regress.py,run_rtl.py,signoff.py}`、help 文本
**关联**：与同日的"Makefile help 波形支持落地"规格相邻，承接其修复的 latent bug 链

## 背景

当前所有仿真类 target（compile / smoke / regress / signoff / demo / signoff_replay）共用一份 `build/simv` 与 `build/csrc/`。结果：

1. **不能并行**：用户在一个终端跑 `make demo`，另一个终端跑 `make smoke`，两者抢同一份 simv、cov.vdb、ucli 锁，结果污染——本次会话已实际踩到。
2. **build/ 顶层杂乱**：simv、simv.daidir、cov.vdb、smoke/、regression/、signoff/、demo/、r3b_final/、r4a_final/、libcosim.so 一起堆在顶层，看不出哪个目录"属于哪个 target"。
3. **clean 难做**：CLEAN_PRESERVE_BUILD 必须列出 `simv*`、`cov.vdb` 等共享物，因为单清 demo 时不能误删 simv。
4. **隐含 bug 滋生**：本次会话发现的两个 latent bug（`<tb_dir>` 模板缺失、`SIM_DIR` 未设）都跟"无人真正端到端跑过隔离场景"有关。

**核心原则（用户要求）**：每个仿真类 target 是一个"岛"——`simv` / `csrc` / `cov` / `compile.log` / work_dirs 全在自己目录里。岛之间任意并行，不抢资源。

## 设计

### 新 `build/` 布局

```
build/
├── libcosim.so          共享只读 Spike DPI 库（保持顶层）
├── spike_objs/          共享 Spike 编译中间产物（保持顶层）
├── r3b_final/           历史 v1.1 sign-off 证据（保持顶层，clean 保护）
├── r4a_final/           历史 v1.1 sign-off 证据（保持顶层，clean 保护）
├── archive_signoffs_*   历史归档软链（保持顶层）
│
├── compile/             make compile 独立调用
│   ├── simv, simv.daidir, csrc/
│   ├── cov.vdb, cov/, compile.log
├── smoke/               make smoke
│   ├── simv, simv.daidir, csrc/, cov.vdb, cov/, compile.log
│   └── smoke_s1/        单测 work_dir（waves.fsdb / sim_*.log / result.yaml）
├── regress/             make regress（从 build/regression/ 改名）
│   ├── simv, ...
│   └── <test>_s<seed>/
├── signoff/             make signoff
│   ├── simv, ...
│   └── runs/<stage>/<test>_s<seed>/
├── signoff_replay/      gate-only，无 simv
│   └── （报告输出）
└── demo/                make demo
    ├── simv, ...
    └── runs/<stage>/<test>_s<seed>/
```

### 设计选择（已对齐用户回答）

| 决策点 | 选择 | 理由 |
|--------|------|------|
| libcosim.so / spike_objs 共享 vs per-target | **共享顶层** | 只读、安全、避免重复编译 ~1GB×N 浪费 |
| make compile 独立调用的 simv 落点 | **build/compile/** | 跟其它 target 同等待遇，目录约定一致 |
| build/regression/ 命名 | **改为 build/regress/** | 与 `make regress` 同名 |
| 历史 r3b_final / r4a_final | **不动** | v1.1 sign-off 证据，受 clean 保护 |
| compliance 存储位置 | **不动**（保持 dv/uvm/riscv_compliance/build/） | 独立沙盒、有自己的 Makefile |

### A. Makefile 改动

**A1. 引入 BUILD_SUBDIR 抽象**
新增顶层变量 `BUILD_SUBDIR ?= $(BUILD_DIR)/compile`，作为 compile target 的默认输出目录。

**A2. compile_vcs / compile_xlm 全面参数化**
所有写死的 `$(BUILD_DIR)/simv`、`$(BUILD_DIR)/csrc`、`$(BUILD_DIR)/compile.log` 替换为 `$(BUILD_SUBDIR)/...`。VCS 覆盖率选项 `VCS_COMPILE_COV_OPTS` 与 `VCS_RUN_COV_OPTS` 里的 `-cm_dir $(BUILD_DIR)/cov` 改为 `-cm_dir $(BUILD_SUBDIR)/cov`。

**A3. 每个仿真类 target 调 compile 时传自己的 BUILD_SUBDIR**
- `smoke`：`$(MAKE) compile BUILD_SUBDIR=$(BUILD_DIR)/smoke`
- `regress`：默认 OUT=`$(BUILD_DIR)/regress`，调 compile 传 `BUILD_SUBDIR=$(BUILD_DIR)/regress`
- `signoff`：调 compile 传 `BUILD_SUBDIR=$(SIGNOFF_OUT)`（默认 `build/signoff`）
- `demo`：调 compile 传 `BUILD_SUBDIR=$(DEMO_OUT)`（默认 `build/demo`）

**A4. cosim target 不变**
`make cosim` 仍编译到 `build/libcosim.so`。所有 target 通过 `COMPILE_LIBCOSIM_LINK := $(CURDIR)/$(LIBCOSIM)` 共用这同一份。

**A5. CLEAN_PRESERVE_BUILD 简化**
旧列表保留 `simv*` 类是因为它们在顶层。新约定下顶层只剩共享与历史项，保留列表变为：
```
libcosim.so spike_objs r3b_final r4a_final nightly compliance_tb_compile.log
+ archive_signoffs_* glob
```
顶层不再有 simv / cov.vdb / csrc，所以不需要保护。

**A6. clean SCOPE=cov 行为调整**
现在 cov.vdb 散布在多个 target 子目录下。`make clean SCOPE=cov` 改为：递归删 `build/*/cov.vdb`、`build/*/cov/`、`build/*/cov_report/`，但不删 libcosim/r*_final/archive_*。

### B. Python 脚本改动

**B1. run_regress.py**
- argparse 加 `--build-dir`（已经存在的接口，确认所有调用方都正确传值）
- 内部调 run_rtl.py 时 `--build-dir <args.build_dir>` 透传
- 默认 `--build-dir` 取 `dirname(args.output)`（如 output=build/smoke/smoke_s1 → build/smoke）

**B2. run_rtl.py**
- 已有 `--build-dir` 接收能力（line 60 用 `md.build_dir`）。确认 `<build_dir>` 模板替换走的是 md.build_dir 而非硬编码
- 移除 `if not md.build_dir: md.build_dir = os.path.join(md.eh2_root, "build")` 的旧 fallback（line 112）改为 `os.path.join(md.eh2_root, "build", "compile")`，与 make compile 默认对齐
- 注意：上次刚加的 `"tb_dir": str(DV_DIR)` 与 `SIM_DIR` 环境变量透传不动

**B3. signoff.py**
- 把 `EH2_ROOT / "build" / "simv"` 全部改为 `args.output / "simv"`（signoff.py:163、:232）
- `build_stage_cmd` 在 compliance stage 里 `--simv` 传 `args.output / "simv"` 而不是顶层 build/simv
- 内部调 run_regress.py 时透传 `--build-dir <args.output>`

**B4. run_compliance.py**
- 不改。它已经有 `--simv <path>` 参数；调用方（signoff.py 与本地 dv/uvm/riscv_compliance/Makefile）负责传正确路径。

**B5. test_regression_framework.py**
- 旧 unit test 里 `self.assertIn("/tmp/eh2-build/simv", cmd)` 这种硬编码可能要跟着新约定调整。如果是 mock 路径不实际访问，可能不用动；实施时核查。

### C. Help 文本改动

**C1. 删除"导师"字样**
line 235 `用途：导师演示 / release 自检` → `用途：完整端到端演示 / release 自检`
全文 grep 一遍确保无其他出现。

**C2. 新增"build/ 目录约定"小节**
位置：放在"15 个核心 target"段下、"参数适用范围速查"段上。内容简述岛屿原则、目录树、什么共享什么独立。

**C3. 每个 target 的"产出"段路径更新**
- compile：build/compile/simv 等
- smoke：build/smoke/{simv, smoke_s1/...}
- regress：build/regress/{simv, <test>_s<seed>/...}
- signoff：build/signoff/{simv, runs/<stage>/...}
- demo：build/demo/{simv, runs/<stage>/...}

**C4. 工作流示例的 fsdb 路径**
保持现状的 `verdi -ssf build/smoke/smoke_s1/waves.fsdb` 等——smoke_s1 在新约定下仍在 build/smoke/ 下，路径不变。其它 target 的 fsdb 路径同理。

**C5. clean 示例与 SCOPE 描述**
更新 cov scope 描述为递归删 `build/*/cov.vdb`。其它 scope 不变。

### D. 改名：`build/regression/` → `build/regress/`

- `regress` target 里 `--output $(if $(OUT),$(OUT),$(BUILD_DIR)/regression)` 改为 `--output $(if $(OUT),$(OUT),$(BUILD_DIR)/regress)`
- help 中 `OUT=<dir> regress 输出目录（默认 build/regression）` 改为 `默认 build/regress`
- help 中所有"build/regression/<test>_s<seed>/..."字样替换为"build/regress/<test>_s<seed>/..."
- 如果文件系统里已有 `build/regression/` 目录，**不主动迁移**——下次 make regress 会写到新路径 build/regress；旧的 build/regression 当成残留，用户可手动删

## 不做的事

- 不动 libcosim.so / spike_objs/ 的位置（顶层共享）
- 不动 r3b_final / r4a_final / archive_signoffs_*（历史证据）
- 不动 dv/uvm/riscv_compliance/build/（compliance 独立沙盒）
- 不引入"simv 软链"魔术——每个 target 真正独立的 simv 文件
- 不动 `make compile` 的 PHONY 性质——每次 make smoke 仍会重链 simv（incremental VCS 通常很快）
- 不做向后兼容 alias：旧的 build/simv 路径不再产生，外部脚本若依赖必须更新（属于本次 breaking change 的一部分）

## 风险与代价

1. **首次构建时间增加**：每个 target 第一次跑独立编译（~3-5 分钟）。连续跑 smoke + regress + signoff + demo = ~20 分钟编译。后续每个 target 自己 incremental 复用。
2. **磁盘占用增加**：每个 target 多 ~170MB（simv.daidir + csrc）。5 个 target = ~850MB 额外。
3. **Breaking change**：`build/simv` 不再产生。任何外部脚本、CI、文档若假设它存在必须更新。
4. **改动覆盖面**：4 个文件实质改动（Makefile + 3 个 Python 脚本）+ help 大段重写。预计 80-150 行实质代码改动。

## 验证（完成定义）

1. `make smoke WAVES=1`：
   - `build/smoke/simv` 存在
   - `build/smoke/smoke_s1/waves.fsdb` 存在 > 1MB
   - **build/simv 不存在**（旧路径已废）
2. **并发安全**：另开终端跑 `make demo` 同时 `make smoke`：
   - 两个 simv 互不覆盖
   - 都成功（无 ucli 锁冲突）
3. `make compile`：
   - `build/compile/simv` 存在
4. `make signoff` 完成后：
   - `build/signoff/simv` 存在
   - `build/signoff/runs/<stage>/...` 完整
   - compliance stage 用的是 build/signoff/simv 而非 build/simv
5. `make clean`：
   - libcosim.so、spike_objs/、r*_final/、archive_*/ 保留
   - 顶层不再有 simv / simv.daidir
   - build/{compile,smoke,regress,signoff,demo}/ 被清
6. `make help`：
   - 无"导师"字样
   - 新增"build/ 目录约定"小节
   - 所有产出路径符合新约定

## 变更文件清单

- `Makefile` — 参数化 BUILD_SUBDIR + 每个 target 调用更新 + clean 列表更新 + help 重写
- `dv/uvm/core_eh2/scripts/run_regress.py` — 透传 --build-dir
- `dv/uvm/core_eh2/scripts/run_rtl.py` — 默认 build_dir 调整
- `dv/uvm/core_eh2/scripts/signoff.py` — simv 路径全部改 args.output/simv
- `dv/uvm/core_eh2/scripts/tests/test_regression_framework.py` — 如有硬编码路径跟进
- 本规格 commit 入 git

无其他文件改动。
