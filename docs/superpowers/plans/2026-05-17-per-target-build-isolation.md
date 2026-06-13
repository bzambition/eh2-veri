# Per-target build 目录隔离 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让每个仿真类 Makefile target（compile / smoke / regress / signoff / demo）拥有独立的 build 子目录，使 `make demo` 与 `make smoke` 等可任意并行。

**架构：** 所有 simv / csrc / cov.vdb / compile.log 从 `build/` 顶层下沉到 `build/<target>/`；共享只读资源（libcosim.so、spike_objs/）与历史证据（r3b_final 等）保持顶层。Makefile 引入 `BUILD_SUBDIR` 变量，每个 target 调 compile 时传自己的值；3 个 Python 脚本透传 `--build-dir`，signoff.py 把硬编码 `build/simv` 全替换为 `args.output/simv`。

**技术栈：** GNU Make + Python 3 + Synopsys VCS（已有平台）

**规格：** `docs/superpowers/specs/2026-05-17-per-target-build-isolation-design.md`

---

## 文件结构

| 文件 | 职责 | 变更类型 |
|------|------|----------|
| `dv/uvm/core_eh2/scripts/run_rtl.py` | 单测仿真器执行 + YAML 模板替换 | 修改：调整 build_dir 默认值 |
| `dv/uvm/core_eh2/scripts/run_regress.py` | 回归调度器 | 修改：argparse 加 --build-dir、透传给 run_rtl.py |
| `dv/uvm/core_eh2/scripts/signoff.py` | Sign-off 编排器 | 修改：simv 路径全替换为 args.output/simv |
| `Makefile`（根目录） | 顶层入口 + help | 修改：BUILD_SUBDIR 抽象 + 每个 target 接入 + clean 列表 + 改名 + help 重写 |

不动：`run_compliance.py`（已支持 `--simv` 参数）、`dv/uvm/core_eh2/yaml/rtl_simulation.yaml`（`<build_dir>` 模板已就位）。

---

## 任务 1：run_regress.py 加 `--build-dir` 透传

**文件：**
- 修改：`dv/uvm/core_eh2/scripts/run_regress.py`

**目的：** 让 run_regress.py 接收 `--build-dir` 并把它透传给内部调用的 run_rtl.py。这是 Python 层的入口改动。

- [ ] **步骤 1：阅读现状**

读 `dv/uvm/core_eh2/scripts/run_regress.py` 第 280-310 行，确认当前 run_rtl.py 调用是这样的：
```python
sim_cmd = [
    sys.executable, os.path.join(SCRIPT_DIR, "run_rtl.py"),
    "--test", test_name,
    "--seed", str(seed),
    "--binary", binary,
    "--simulator", simulator,
    "--rtl-test", rtl_test,
    "--sim-opts", sim_opts,
    "--build-dir", os.path.join(EH2_ROOT, "build"),    # <- 硬编码
    "--out-dir", work_dir,
]
```

也读 argparse 段（约 460-500 行），确认当前**没有** `--build-dir` 参数。

- [ ] **步骤 2：加 argparse 参数**

定位 argparse 段，加：
```python
parser.add_argument("--build-dir", default=None,
                    help="Per-target build root for simv lookup. "
                         "Defaults to <eh2_root>/build/compile when omitted.")
```

放在 `--output` 参数附近。

- [ ] **步骤 3：把参数传给 run_single_test**

`run_single_test` 函数签名加 `build_dir: str = None`。在所有调用 `run_single_test` 的位置（grep `run_single_test(` 找到 2-3 处）传入 `build_dir=args.build_dir`。

- [ ] **步骤 4：把 build_dir 接入 sim_cmd 构造**

定位上面看到的 sim_cmd 列表，把硬编码改成参数化：
```python
sim_cmd = [
    sys.executable, os.path.join(SCRIPT_DIR, "run_rtl.py"),
    "--test", test_name,
    "--seed", str(seed),
    "--binary", binary,
    "--simulator", simulator,
    "--rtl-test", rtl_test,
    "--sim-opts", sim_opts,
    "--build-dir", build_dir or os.path.join(EH2_ROOT, "build", "compile"),
    "--out-dir", work_dir,
]
```

注意默认 fallback 是 `<eh2_root>/build/compile`，跟规格 A1 BUILD_SUBDIR 默认值对齐。

- [ ] **步骤 5：语法验证 + 静态检查**

```bash
python3 -c "import ast; ast.parse(open('dv/uvm/core_eh2/scripts/run_regress.py').read()); print('syntax OK')"
python3 dv/uvm/core_eh2/scripts/run_regress.py --help 2>&1 | grep -i build-dir
```

预期：syntax OK；--help 输出里出现 `--build-dir` 行。

- [ ] **步骤 6：Commit**

```bash
git add dv/uvm/core_eh2/scripts/run_regress.py
git commit -m "feat(sim): run_regress.py 加 --build-dir 透传

为 per-target build 隔离做铺垫。argparse 接收 --build-dir，
内部调 run_rtl.py 时透传；默认 fallback 为 build/compile/。"
```

---

## 任务 2：run_rtl.py 默认 build_dir 调整

**文件：**
- 修改：`dv/uvm/core_eh2/scripts/run_rtl.py`

**目的：** 把 run_rtl.py 的默认 build_dir 从 `<eh2_root>/build` 改成 `<eh2_root>/build/compile`，与 Makefile compile target 的默认输出一致。

- [ ] **步骤 1：阅读现状**

读 `run_rtl.py` 第 108-115 行：
```python
def run_rtl_simulation(md: RegressionMetadata) -> TestRunResult:
    """Run a single RTL simulation."""
    if not md.eh2_root:
        md.eh2_root = str(EH2_ROOT)
    if not md.build_dir:
        md.build_dir = os.path.join(md.eh2_root, "build")    # <- 改这里
```

- [ ] **步骤 2：调整默认值**

把第 112 行改为：
```python
    if not md.build_dir:
        md.build_dir = os.path.join(md.eh2_root, "build", "compile")
```

- [ ] **步骤 3：语法验证**

```bash
python3 -c "import ast; ast.parse(open('dv/uvm/core_eh2/scripts/run_rtl.py').read()); print('OK')"
```

预期：OK

- [ ] **步骤 4：旧单元测试是否还过**

```bash
cd dv/uvm/core_eh2/scripts && python3 -m unittest tests.test_regression_framework 2>&1 | tail -15
```

预期：所有测试 PASS。该测试在第 88 行显式设 `md.build_dir = "/tmp/eh2-build"`，所以默认值改动不影响它。如果有意外失败，再分析。

- [ ] **步骤 5：Commit**

```bash
git add dv/uvm/core_eh2/scripts/run_rtl.py
git commit -m "feat(sim): run_rtl.py 默认 build_dir 改为 build/compile/

与 per-target build 隔离方案对齐——make compile 独立调用时
simv 落在 build/compile/，run_rtl.py 默认查找路径同步更新。"
```

---

## 任务 3：signoff.py 把硬编码 build/simv 全替换为 args.output/simv

**文件：**
- 修改：`dv/uvm/core_eh2/scripts/signoff.py`

**目的：** sign-off 编排器内部 3 处硬编码 `EH2_ROOT/"build"/"simv"` 全部改为基于 `args.output`，让 signoff 的 simv 落在 `build/signoff/simv`（即 args.output/simv）。

- [ ] **步骤 1：找全所有需要改的位置**

```bash
grep -n 'EH2_ROOT.*"build".*"simv"\|build/simv' dv/uvm/core_eh2/scripts/signoff.py
```

预期看到 3 处：
- line ~163：`simv_exists = (EH2_ROOT / "build" / "simv").exists()`
- line ~165：报错文案 `"found build/simv"`
- line ~232：`simv = EH2_ROOT / "build" / "simv"` （compliance stage 用）

另外注意：`build_stage_cmd` 函数有 `args` 参数，但 `args.output` 在这里是 `output_dir = Path(args.output).resolve()` 在 main 里算出来的，需要把 `output_dir` 也传到 `build_stage_cmd`，或者直接在 `build_stage_cmd` 里调 `args.output`。

- [ ] **步骤 2：调整 build_stage_cmd 签名**

把 `build_stage_cmd` 改为接收 `simv_path`：

定位 `def build_stage_cmd(stage: str, args, stage_out: Path) -> List[str]:`，改为：
```python
def build_stage_cmd(stage: str, args, stage_out: Path, simv_path: Path) -> List[str]:
```

并把所有 `EH2_ROOT / "build" / "simv"` 替换为 `simv_path`（compliance stage line 232 那处）。

- [ ] **步骤 3：调整 build_stage_cmd 的调用点**

main 函数里调 build_stage_cmd 的地方，传入 `simv_path = output_dir / "simv"`：

定位 main 函数（约 1564 行往后），找到 `cmd = build_stage_cmd(stage, args, stage_out)` 调用，改为：
```python
        simv_path = output_dir / "simv"
        cmd = build_stage_cmd(stage, args, stage_out, simv_path)
```

`output_dir` 在 main 中已通过 `output_dir = Path(args.output).resolve()` 计算。

- [ ] **步骤 4：调整 simv_exists 启动检查**

定位 line 163 附近：
```python
    simv_exists = (EH2_ROOT / "build" / "simv").exists()
    sim_tool = ...
    print("  Simulator: " + ("found build/simv" if simv_exists else sim_tool))
```

改为基于 args.output：
```python
    output_dir_for_check = Path(args.output).resolve()
    simv_exists = (output_dir_for_check / "simv").exists()
    sim_tool = ...
    print("  Simulator: " + (f"found {output_dir_for_check}/simv" if simv_exists else sim_tool))
```

如果 `args.output` 在这一行之前还没解析，调整下顺序，把 `output_dir = Path(args.output).resolve()` 上移到合适位置（或独立保留 `output_dir_for_check`，main 里二次计算不冲突）。

- [ ] **步骤 5：在 build_stage_cmd 内透传 --build-dir 到 run_regress.py**

定位 build_stage_cmd 函数，在通用 `cmd = [sys.executable, str(run_regress), ...]` 列表里加 `--build-dir`：

```python
def build_stage_cmd(stage: str, args, stage_out: Path, simv_path: Path) -> List[str]:
    run_regress = SCRIPT_DIR / "run_regress.py"
    cmd = [sys.executable, str(run_regress),
           "--simulator", args.simulator,
           "--seed", str(args.seed),
           "--build-dir", str(simv_path.parent),    # 新增：传 build/signoff
           "--output", str(stage_out)]
    ...
```

- [ ] **步骤 6：语法验证 + 启动测试**

```bash
python3 -c "import ast; ast.parse(open('dv/uvm/core_eh2/scripts/signoff.py').read()); print('OK')"
python3 dv/uvm/core_eh2/scripts/signoff.py --help 2>&1 | head -5
```

预期：syntax OK；`--help` 不爆。

- [ ] **步骤 7：Commit**

```bash
git add dv/uvm/core_eh2/scripts/signoff.py
git commit -m "feat(sim): signoff.py 用 args.output/simv 取代硬编码 build/simv

per-target 隔离配套改动：build_stage_cmd 接收 simv_path 参数，
所有 stage 走 args.output/simv（即 build/signoff/simv），不再共用
顶层 build/simv。compliance stage 与启动检查同步更新。"
```

---

## 任务 4：Makefile compile target 参数化 BUILD_SUBDIR

**文件：**
- 修改：`Makefile`（根目录）

**目的：** 引入 `BUILD_SUBDIR` 顶层变量，把 `compile_vcs` / `compile_xlm` 里所有写死的 `$(BUILD_DIR)/simv`、`$(BUILD_DIR)/csrc`、`$(BUILD_DIR)/compile.log` 替换为基于 `$(BUILD_SUBDIR)`。覆盖率选项里的 `$(BUILD_DIR)/cov` 也跟着改。

- [ ] **步骤 1：加 BUILD_SUBDIR 顶层默认值**

在 Makefile 顶层变量定义段（约第 120 行附近，紧跟 `BUILD_DIR := build` 之后），加：

```makefile
# Per-target build sub-directory. Each top-level sim target overrides this
# (smoke -> build/smoke, signoff -> build/signoff, etc.) so the simv/csrc/
# cov.vdb/compile.log they produce live in their own island. Default for
# standalone `make compile` invocations.
BUILD_SUBDIR ?= $(BUILD_DIR)/compile
```

- [ ] **步骤 2：compile_vcs 全面参数化**

定位 `compile_vcs:` target（约第 777 行）。把所有出现的 `$(BUILD_DIR)/simv`、`$(BUILD_DIR)/csrc`、`$(BUILD_DIR)/compile.log` 替换为 `$(BUILD_SUBDIR)/simv` 等。同时在前面创建目录：

```makefile
compile_vcs: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
	@echo "=== [compile] VCS UVM testbench (BUILD_SUBDIR=$(BUILD_SUBDIR)) ==="
	@mkdir -p $(BUILD_SUBDIR)
	$(VCS) -full64 -assert svaext -sverilog \
	  -ntb_opts uvm-1.2 \
	  +error+500 \
	  +define+GTLSIM \
	  $(DEFINES) \
	  +incdir+$(SNAPSHOTS) \
	  +incdir+$(TB_DIR)/common/axi4_agent \
	  +incdir+$(TB_DIR)/common/trace_agent \
	  +incdir+$(TB_DIR)/common/irq_agent \
	  +incdir+$(TB_DIR)/common/jtag_agent \
	  +incdir+$(TB_DIR)/common/cosim_agent \
	  +incdir+$(COSIM_DIR) \
	  -f $(RTL_F) \
	  -f $(SHARED_F) \
	  -f $(TB_F) \
	  -top core_eh2_tb_top \
	  $(COMPILE_LIBCOSIM_LINK) \
	  -Mdir=$(BUILD_SUBDIR)/csrc \
	  -o $(BUILD_SUBDIR)/simv \
	  -l $(BUILD_SUBDIR)/compile.log \
	  -timescale=1ns/1ps \
	  -debug_access+all \
	  $(if $(filter 1,$(WAVES)),-kdb,) \
	  $(if $(filter 1,$(COV)),$(VCS_COMPILE_COV_OPTS),)
	@echo "=== [compile] simv 完成: $(BUILD_SUBDIR)/simv ==="
```

- [ ] **步骤 3：compile_xlm 同步参数化**

定位 `compile_xlm:` target（约第 805 行）。原 target 用 `cd $(BUILD_DIR) && $(XLM) ...`，要改成在 `$(BUILD_SUBDIR)` 工作：

```makefile
compile_xlm: | $(BUILD_DIR)
	@echo "=== [compile] Xcelium UVM testbench (BUILD_SUBDIR=$(BUILD_SUBDIR)) ==="
	@mkdir -p $(BUILD_SUBDIR)
	cd $(BUILD_SUBDIR) && $(XLM) -uvm -sv \
	  $(DEFINES) \
	  +incdir+$(SNAPSHOTS) \
	  +incdir+../../$(TB_DIR)/common/axi4_agent \
	  +incdir+../../$(TB_DIR)/common/trace_agent \
	  +incdir+../../$(TB_DIR)/common/irq_agent \
	  +incdir+../../$(TB_DIR)/common/jtag_agent \
	  +incdir+../../$(TB_DIR)/common/cosim_agent \
	  -f ../../$(RTL_F) \
	  -f ../../$(SHARED_F) \
	  -f ../../$(TB_F) \
	  -top core_eh2_tb_top \
	  -l compile.log \
	  $(if $(filter 1,$(COV)),-covoverwrite -covfile ../../$(TB_DIR)/cov.ccf,)
	@echo "=== [compile] Xcelium 完成: $(BUILD_SUBDIR)/ ==="
```

注意相对路径要多上一层（`../../` 而不是 `../`），因为 BUILD_SUBDIR 比 BUILD_DIR 深一层。

- [ ] **步骤 4：覆盖率选项里的 cov 目录也参数化**

定位（约第 180 行）：
```makefile
VCS_COMPILE_COV_OPTS := -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_DIR)/cov \
                        ...
VCS_RUN_COV_OPTS := -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_DIR)/cov \
                    ...
```

把两处 `-cm_dir $(BUILD_DIR)/cov` 改成 `-cm_dir $(BUILD_SUBDIR)/cov`。

- [ ] **步骤 5：dry-run 验证**

```bash
make -n compile 2>&1 | grep -E "simv|csrc|compile.log|cov" | head -10
```

预期：所有路径出现 `build/compile/`，不再出现裸 `build/simv`。

```bash
make -n compile BUILD_SUBDIR=build/smoke 2>&1 | grep -E "simv|csrc" | head -5
```

预期：路径出现 `build/smoke/simv`、`build/smoke/csrc`。

- [ ] **步骤 6：Commit**

```bash
git add Makefile
git commit -m "feat(make): compile target 参数化 BUILD_SUBDIR

引入顶层变量 BUILD_SUBDIR（默认 build/compile/），compile_vcs/
compile_xlm 里所有 simv/csrc/compile.log/cov 路径基于它构造。
为 per-target 隔离铺路——后续每个仿真 target 会传自己的
BUILD_SUBDIR。"
```

---

## 任务 5：每个仿真 target 接入 BUILD_SUBDIR

**文件：**
- 修改：`Makefile`

**目的：** smoke / regress / signoff / demo 在调 compile（以及调用 Python 脚本）时传自己的 BUILD_SUBDIR，确保各自的 simv 落在 build/<target>/。

- [ ] **步骤 1：smoke target 改造**

定位 smoke target（约第 826 行），先让它给 compile 传 BUILD_SUBDIR：

```makefile
smoke: asm
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(BUILD_DIR)/smoke
	@echo "=== [smoke] 运行 smoke 测试 ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --test smoke \
	  --binary $(ASM_DIR)/smoke.hex \
	  --simulator $(SIMULATOR) \
	  --seed 1 \
	  --rtl-test core_eh2_base_test \
	  --sim-opts "+disable_cosim=1" \
	  --build-dir $(BUILD_DIR)/smoke \
	  --output $(BUILD_DIR)/smoke \
	  $(if $(filter 1,$(WAVES)),--waves,)
	@echo "=== [smoke] 完成 ==="
```

注意：
- 把原来的 `smoke: compile asm` 依赖去掉，改成 target body 里显式调 `$(MAKE) compile BUILD_SUBDIR=...`，否则父 make 直接跑 compile 用的是默认 BUILD_SUBDIR（build/compile）。
- run_regress.py 加 `--build-dir $(BUILD_DIR)/smoke` 让 sim 阶段去 build/smoke/ 找 simv。

- [ ] **步骤 2：regress target 改造**

定位 regress target（约第 838 行）：

```makefile
regress:
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(BUILD_DIR)/regress
	@echo "=== [regress] testlist=$(TESTLIST) parallel=$(PARALLEL) iter=$(ITERATIONS) ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  $(if $(TEST),--test $(TEST),--testlist $(TESTLIST_PATH)) \
	  --simulator $(SIMULATOR) \
	  --seed $(SEED) \
	  --iterations $(ITERATIONS) \
	  --parallel $(PARALLEL) \
	  --build-dir $(BUILD_DIR)/regress \
	  --output $(if $(OUT),$(OUT),$(BUILD_DIR)/regress) \
	  $(if $(filter 1,$(COV)),--coverage,) \
	  $(if $(filter 1,$(WAVES)),--waves,)
	@echo "=== [regress] 完成 ==="
```

注意：默认 OUT 改为 `build/regress`（任务 7 会全文清理 regression 相关字串）。

- [ ] **步骤 3：signoff target 改造**

定位 signoff target（约第 888 行）。加 compile sub-make 并传 BUILD_SUBDIR：

```makefile
signoff:
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(SIGNOFF_OUT) COV=$(COV)
	@echo "=== [signoff] profile=$(PROFILE) gate_only=$(GATE_ONLY) out=$(SIGNOFF_OUT) ==="
	python3 $(SCRIPTS_DIR)/signoff.py \
	  --profile $(PROFILE) \
	  --simulator $(SIMULATOR) \
	  --seed $(SEED) \
	  --parallel $(PARALLEL) \
	  --output $(SIGNOFF_OUT) \
	  $(if $(filter 1,$(GATE_ONLY)),--gate-only,) \
	  ... [其余原有透传保持不变]
```

signoff.py 内部已经在任务 3 里把 build_stage_cmd 改成基于 args.output，所以 stage 会自动用 $(SIGNOFF_OUT)/simv。这里 Makefile 只需要确保 compile 用 SIGNOFF_OUT 即可。

- [ ] **步骤 4：demo target 改造**

定位 demo target（约第 930 行）。当前是 `@$(MAKE) --no-print-directory compile COV=1`，改成传 BUILD_SUBDIR：

```makefile
demo:
	...原 echo + clean + asm 不动...
	@$(MAKE) --no-print-directory cosim COV=1
	@$(MAKE) --no-print-directory compile COV=1 BUILD_SUBDIR=$(DEMO_OUT)
	...synth 段不动...
	@$(MAKE) --no-print-directory signoff SIGNOFF_OUT=$(DEMO_OUT) PARALLEL=$(PARALLEL) COV=1
	...
```

注意：demo 调 signoff 时传 SIGNOFF_OUT=$(DEMO_OUT)，让 signoff 直接用 demo 的目录而不是 build/signoff（避免 demo 跑完又额外产生一份 build/signoff/）。signoff 那次的 compile sub-make 会传 BUILD_SUBDIR=$(SIGNOFF_OUT) 也就是 $(DEMO_OUT) —— 跟 demo 这层已经传的一致，simv 不会被重新覆盖（make 同 target 不会跑两次）。

实际验证：如果 demo 调 signoff 时 signoff 又调 compile BUILD_SUBDIR=DEMO_OUT，会不会重跑 compile？因为 compile 是 PHONY，是的会重跑。这会拖时间但不会出错。如果想避免，可以让 signoff 在 BUILD_SUBDIR/simv 已存在时跳过 compile。但这是后续优化，本计划不做。

- [ ] **步骤 5：dry-run 验证**

```bash
echo "=== smoke ==="
make -n smoke 2>&1 | grep -E "BUILD_SUBDIR|build-dir" | head -3

echo "=== regress ==="
make -n regress 2>&1 | grep -E "BUILD_SUBDIR|build-dir" | head -3

echo "=== signoff ==="
make -n signoff 2>&1 | grep -E "BUILD_SUBDIR|build-dir|simv" | head -5

echo "=== demo ==="
make -n demo 2>&1 | grep -E "BUILD_SUBDIR" | head -5
```

预期：每个 target 的 BUILD_SUBDIR 出现且指向自己的子目录。

- [ ] **步骤 6：Commit**

```bash
git add Makefile
git commit -m "feat(make): smoke/regress/signoff/demo 接入 BUILD_SUBDIR

每个仿真类 target 调 compile 时传自己的 BUILD_SUBDIR：
  smoke   -> build/smoke
  regress -> build/regress（同时默认 OUT 改名）
  signoff -> \$(SIGNOFF_OUT)（默认 build/signoff）
  demo    -> \$(DEMO_OUT)（默认 build/demo）
run_regress.py 调用同步传 --build-dir，让 sim 阶段查找 simv 时
落在对应 target 子目录。"
```

---

## 任务 6：clean 列表与 cov scope 更新

**文件：**
- 修改：`Makefile`

**目的：** 新约定下顶层不再有 simv*、csrc、cov.vdb，CLEAN_PRESERVE_BUILD 简化。cov scope 改为递归清各 target 子目录里的 cov.vdb。

- [ ] **步骤 1：简化 CLEAN_PRESERVE_BUILD**

定位（约第 102 行）：
```makefile
CLEAN_PRESERVE_BUILD := r3b_final r4a_final nightly \
                        cov cov.vdb cov_report \
                        simv simv.daidir simv.vdb \
                        simv_compliance simv_compliance.daidir \
                        libcosim.so spike_objs csrc \
                        compile.log compliance_tb_compile.log
```

改为：
```makefile
# Items inside $(BUILD_DIR) that `make clean` MUST preserve. In the new
# per-target layout, only shared read-only artifacts (libcosim.so,
# spike_objs/) and historical sign-off evidence (r3b_final, r4a_final,
# archive_signoffs_*) live at the top level — everything else (simv,
# csrc, cov.vdb, etc.) lives inside per-target sub-directories and is
# safe to wipe wholesale.
CLEAN_PRESERVE_BUILD := r3b_final r4a_final nightly \
                        libcosim.so spike_objs \
                        compliance_tb_compile.log
```

- [ ] **步骤 2：cov scope 改为递归清各 target 子目录**

定位 clean target 的 SCOPE=cov 分支（约第 992 行）：
```makefile
  cov) \
    rm -rf $(BUILD_DIR)/simv.vdb $(BUILD_DIR)/cov.vdb $(BUILD_DIR)/cov $(BUILD_DIR)/cov_report; \
    echo "[clean] 已清覆盖率数据库" ;; \
```

改为：
```makefile
  cov) \
    find $(BUILD_DIR) -mindepth 2 -maxdepth 2 \
      \( -name 'cov.vdb' -o -name 'cov' -o -name 'cov_report' -o -name 'simv.vdb' \) \
      -exec rm -rf {} + 2>/dev/null || true; \
    echo "[clean] 已清各 target 子目录下的覆盖率数据库（递归 build/*/cov.vdb 等）" ;; \
```

`-mindepth 2 -maxdepth 2` 确保只清 `build/<target>/cov.vdb` 这种，不会误伤顶层 libcosim 之类。

- [ ] **步骤 3：dry-run 验证 clean**

```bash
make -n clean SCOPE=cov 2>&1 | head -3
make -n clean 2>&1 | grep -E "find|preserve" | head -5
```

预期：cov scope 命令出现 `find build -mindepth 2 ...`；clean SCOPE=full（默认）的 find 命令里只保护 r*_final / libcosim / spike_objs / archive_signoffs_*。

- [ ] **步骤 4：Commit**

```bash
git add Makefile
git commit -m "fix(make): clean 列表简化 + cov scope 递归化

per-target 隔离后顶层不再有 simv*/csrc/cov.vdb，
CLEAN_PRESERVE_BUILD 只需保留共享只读项（libcosim/spike_objs）
和历史证据（r*_final/archive_signoffs_*）。
SCOPE=cov 改为递归清 build/*/cov.vdb 等子目录文件。"
```

---

## 任务 7：build/regression → build/regress 改名

**文件：**
- 修改：`Makefile`

**目的：** 把 regress target 默认 OUT、help 文本里所有出现的 `build/regression` 字串替换为 `build/regress`。

- [ ] **步骤 1：定位所有 build/regression 出现处**

```bash
grep -n "build/regression" Makefile
```

预期看到 5-8 处，分布在 help 文本与示例命令里。

- [ ] **步骤 2：全文替换**

用 sed 或者 Edit 工具全文替换 `build/regression` 为 `build/regress`：

```bash
sed -i 's|build/regression|build/regress|g' Makefile
```

- [ ] **步骤 3：验证替换完成**

```bash
grep -n "build/regression" Makefile
```

预期：0 命中。

```bash
grep -c "build/regress" Makefile
```

预期：5-8（与步骤 1 相同数）。

- [ ] **步骤 4：dry-run 验证 regress 默认输出**

```bash
make -n regress 2>&1 | grep -E "output|build/regress" | head -3
```

预期：`--output build/regress`（不再是 build/regression）。

- [ ] **步骤 5：Commit**

```bash
git add Makefile
git commit -m "refactor(make): build/regression 改名为 build/regress

与 \`make regress\` target 名对齐，per-target 隔离方案下
每个 target 子目录与 target 同名。help 中所有示例路径同步更新。

注：旧的 build/regression/ 目录在文件系统里若存在，本次不主动
迁移；下次 make regress 直接写到新路径 build/regress。"
```

---

## 任务 8：Help 文本全面重写

**文件：**
- 修改：`Makefile`（help 段，约第 219-700 行）

**目的：** 1) 删除"导师"字样；2) 新增"build/ 目录约定"小节；3) 每个 target 的"产出"段路径更新为新约定；4) clean / cov 描述对齐新行为。

- [ ] **步骤 1：删除"导师"字样**

定位（约第 235 行）：
```
        用途：导师演示 / release 自检。一条龙：clean → asm → cosim → compile
```

改为：
```
        用途：完整端到端演示 / release 自检。一条龙：clean → asm → cosim → compile
```

```bash
grep -n "导师" Makefile
```

预期：删完后 0 命中。

- [ ] **步骤 2：新增 build/ 目录约定小节**

定位 help 开头的"15 个核心 target"段后、"参数适用范围速查"段前（约第 230 行附近）。插入：

```
──────────────────────────────────────────────────────────────────────────────
[ build/ 目录约定 ]
──────────────────────────────────────────────────────────────────────────────

每个仿真类 target 是一个"岛"——simv / csrc / cov.vdb / compile.log 与
work_dirs 全在自己目录里。岛之间任意并行，不抢资源。

  build/
  ├── libcosim.so           共享只读 Spike DPI 库
  ├── spike_objs/           共享 Spike 编译中间产物
  ├── r3b_final/            历史 v1.1 sign-off 证据（clean 保护）
  ├── r4a_final/            历史 v1.1 sign-off 证据（clean 保护）
  ├── archive_signoffs_*    历史归档软链（clean 保护）
  │
  ├── compile/              make compile 独立调用
  ├── smoke/                make smoke
  ├── regress/              make regress（旧 build/regression/ 改名）
  ├── signoff/              make signoff（含 runs/<stage>/...）
  ├── signoff_replay/       make signoff_replay（gate-only，无 simv）
  └── demo/                 make demo（含 runs/<stage>/...）

每个 target 子目录内典型布局：
  build/<target>/
  ├── simv, simv.daidir/, csrc/        VCS 编译产物
  ├── cov.vdb, cov/, cov_report/       覆盖率数据库（如 COV=1）
  ├── compile.log                      编译日志
  └── <test>_s<seed>/  或  runs/<stage>/<test>_s<seed>/
      ├── waves.fsdb                   如 WAVES=1
      ├── sim_*.log
      └── result.yaml

并行安全：可任意同时跑 make smoke + make demo + make signoff 三个 target，
彼此不抢 simv、不抢 cov、不抢 ucli 锁。

```

- [ ] **步骤 3：每个 target 的"产出"段路径更新**

定位每个 target 的"产出："小节，替换为新路径。具体例子：

`compile` 段（约第 360 行）：
```
        产出：
          build/compile/simv                       VCS 可执行
          build/compile/simv.daidir/               VCS 中间数据
          build/compile/csrc/                      VCS C 中间文件
          build/compile/compile.log                编译日志
```

`smoke` 段（约第 380 行）：
```
        产出：
          build/smoke/simv                         本 target 自己的 simv
          build/smoke/<test>_s1/sim_*.log
          build/smoke/<test>_s1/result.yaml
          build/smoke/<test>_s1/waves.fsdb         如 WAVES=1
          build/smoke/regr.log
          build/smoke/report.json
```

`regress` 段：
```
        产出：
          build/regress/simv                        本 target 自己的 simv
          $(OUT)/<test>_s<seed>/sim_*.log
          $(OUT)/<test>_s<seed>/result.yaml
          $(OUT)/<test>_s<seed>/waves.fsdb          如 WAVES=1
          $(OUT)/regr.log
          $(OUT)/report.json
          $(OUT)/regr_junit.xml
```

`signoff` 段：
```
        产出：
          $(SIGNOFF_OUT)/simv                       本 sign-off 用的 simv
          $(SIGNOFF_OUT)/report.html
          $(SIGNOFF_OUT)/signoff_status.json
          $(SIGNOFF_OUT)/signoff_report.md
          $(SIGNOFF_OUT)/runs/<stage>/
          $(SIGNOFF_OUT)/cov_merged/dashboard.txt
```

`demo` 段类似：在 `$(DEMO_OUT)/report.html` 等之前插入 `$(DEMO_OUT)/simv` 行。

- [ ] **步骤 4：clean SCOPE=cov 描述更新**

定位 help 中 clean 段的 SCOPE 描述（约第 520 行）：
```
              cov      —— 只清覆盖率数据库（cov.vdb/cov_report）
```

改为：
```
              cov      —— 递归清各 target 子目录下的 cov.vdb/cov/cov_report/simv.vdb
                          （build/<target>/cov.vdb 等；不动 libcosim.so 与 r*_final）
```

clean 段产出/示例描述也对应微调（不再保护 simv* / cov.vdb 等顶层项，因为不存在）。

- [ ] **步骤 5：依赖描述更新**

定位 signoff 段的依赖说明（约第 262 行）：
```
        依赖：build/simv（先跑 make compile 或包含在 demo 里）；
```

改为：
```
        依赖：本 target 自动调 compile 生成 $(SIGNOFF_OUT)/simv（含覆盖率
              插桩）；如要复用已编译产物，确保 BUILD_SUBDIR 一致。
```

- [ ] **步骤 6：验证渲染**

```bash
make help 2>&1 | grep "导师"
```

预期：0 命中。

```bash
make help 2>&1 | grep -A 12 "build/ 目录约定" | head -20
```

预期：看到新小节的目录树。

```bash
make help 2>&1 | grep -E "build/(compile|smoke|regress|signoff|demo)/simv" | head
```

预期：每个 target 的 simv 路径都出现。

```bash
make help 2>&1 | grep "build/simv\b" | head
```

预期：0 命中（裸 build/simv 不应再出现，除了任务 7 改完后已无此字串）。

- [ ] **步骤 7：Commit**

```bash
git add Makefile
git commit -m "docs(make): help 文本对齐 per-target 隔离新约定

- 删除\"导师\"字样（line 235）
- 新增\"build/ 目录约定\"小节（顶层共享 vs target 子目录岛）
- 每个 target 的\"产出\"段路径更新（含 simv 在子目录里的位置）
- clean SCOPE=cov 描述改为\"递归清 build/*/cov.vdb\"
- 显式说明并行安全：make smoke + make demo + make signoff 可同时跑"
```

---

## 任务 9：端到端验证 + 并发安全验证

**文件：** 无（纯运行验证）

**目的：** 验证规格中的 6 条完成定义全部满足。

- [ ] **步骤 1：清理旧产物（让验证从干净状态开始）**

```bash
rm -rf build/smoke build/regress build/regression build/compile build/signoff build/demo
# 注意：libcosim.so/spike_objs/r*_final 保留
ls build/
```

预期看到 libcosim.so / spike_objs / r3b_final / r4a_final 等保留项。

- [ ] **步骤 2：验证 make smoke WAVES=1 落点正确**

```bash
time make smoke WAVES=1 2>&1 | tail -8
ls -lh build/smoke/simv build/smoke/smoke_s1/waves.fsdb
ls build/simv 2>&1 | head
```

预期：
- smoke PASS
- `build/smoke/simv` 存在
- `build/smoke/smoke_s1/waves.fsdb` 大小 > 1MB
- **`build/simv` 不存在**（旧路径已废）

- [ ] **步骤 3：验证 make compile 独立调用**

```bash
make compile 2>&1 | tail -3
ls -lh build/compile/simv
```

预期：`build/compile/simv` 存在。

- [ ] **步骤 4：并发安全验证（关键）**

开两个终端（或一个终端用 &）：

```bash
make smoke WAVES=1 > /tmp/smoke.log 2>&1 &
SMOKE_PID=$!
sleep 5
make compile BUILD_SUBDIR=build/parallel_test > /tmp/compile.log 2>&1 &
COMPILE_PID=$!
wait $SMOKE_PID $COMPILE_PID
echo "smoke exit=$?"
tail -3 /tmp/smoke.log
tail -3 /tmp/compile.log
ls build/smoke/simv build/parallel_test/simv build/smoke/smoke_s1/waves.fsdb
```

预期：两个都成功；两份 simv 都生成；waves.fsdb 在 smoke 工作目录。

- [ ] **步骤 5：验证 make clean 行为**

```bash
make clean 2>&1 | tail -3
ls build/
```

预期：libcosim.so、spike_objs、r3b_final、r4a_final 保留；smoke/regress/compile/signoff/demo 等被清除。

- [ ] **步骤 6：验证 help 无"导师"且有新章节**

```bash
make help | grep -c "导师"
make help | grep -A 2 "build/ 目录约定" | head -3
```

预期：第 1 条 grep 输出 0；第 2 条显示新章节存在。

- [ ] **步骤 7：commit 验证笔记（可选）**

如果想留个 verification 记录：

```bash
git log --oneline -10
```

确认 8 个 commit 链条干净。无需额外 commit，但可以选择性写一个简短的 commit 记录验证通过：

```bash
git commit --allow-empty -m "test: per-target build 隔离端到端验证通过

验证项（基于规格的 6 条完成定义）：
- make smoke WAVES=1 -> build/smoke/{simv, smoke_s1/waves.fsdb} ✓
- 并发跑 smoke + compile BUILD_SUBDIR=other 不抢资源 ✓
- make compile -> build/compile/simv ✓
- build/simv 不再产生 ✓
- make clean 后 r*_final / libcosim.so 保留，target 子目录清空 ✓
- make help 无\"导师\"字样、新增 build/ 目录约定小节 ✓"
```

---

## 自检结果

**规格覆盖度**：规格 A1-A6 覆盖到任务 4-6；B1-B5 覆盖到任务 1-3；C1-C5 覆盖到任务 8；D 覆盖到任务 7。验证（规格 6 条完成定义）覆盖到任务 9。无遗漏。

**占位符扫描**：每步都有具体命令/代码块。无"待定" / "TODO" / "类似上面"。

**类型/命名一致性**：
- `BUILD_SUBDIR`：在任务 4 定义、任务 5 在 4 个 target 处使用，命名一致
- `--build-dir`：任务 1 加 argparse、任务 5 在 4 个 Makefile 调用点传入，命名一致
- `simv_path`：任务 3 在 build_stage_cmd 引入，仅在该函数内使用，一致
- `args.output` vs `output_dir`：signoff.py 内部 main 用 `output_dir = Path(args.output).resolve()`；任务 3 让 build_stage_cmd 接收 `simv_path` 参数避免依赖 main 内的局部变量。一致

---

## 实施风险提示

1. **任务 5 步骤 1 改 smoke 依赖**：把 `smoke: compile asm` 改成 target body 里显式 sub-make 调 compile，是为了在 sub-make 里指定 BUILD_SUBDIR。要确认这样不会破坏 asm 依赖——保留 `smoke: asm` 即可。
2. **任务 5 步骤 4 demo 调 signoff 两次 compile**：demo 调 compile 一次（BUILD_SUBDIR=DEMO_OUT），signoff 又调一次（同样 BUILD_SUBDIR=DEMO_OUT）。重复编译会拖时间但不会出错。如果觉得不能接受，写一个文件存在性检查跳过即可。
3. **VCS Xcelium 路径**：任务 4 步骤 3 改了 `cd $(BUILD_SUBDIR)` 后相对路径要多上一层。要核对所有 `-f ../path` 是否都对应改成 `../../path`。
