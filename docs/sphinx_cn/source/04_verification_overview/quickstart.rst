.. _quickstart:
.. _04_verification_overview/quickstart:

验证平台快速上手
================

:status: draft
:source: README.md; env.sh; Makefile; dv/uvm/core_eh2/scripts/run_regress.py; dv/uvm/core_eh2/scripts/signoff.py; docs/PROJECT_STATUS.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
-----------------

读懂本章，你需要已经看过 :ref:`getting_started`，至少知道 ``env.sh``、``make compile``、
``make smoke`` 和 ``make signoff`` 的基本作用。本章面向验证平台使用者，重点解释
“第一次跑通以后，如何理解每条命令背后的验证含义”。

如果你还没跑过任何命令，先回到 :ref:`getting_started`。如果你已经能跑通 smoke，
本章会把 smoke 扩展成一个完整的验证心智模型：编译产生 ``simv``，仿真执行
``smoke.hex``，UVM testbench 监控 mailbox，cosim scoreboard 可以逐条对比 Spike，
sign-off 再把 smoke、directed、riscv-dv、formal、LEC 等 stage 汇总成质量证据。

学完本章你能：

1. 区分 ``make compile``、``make smoke``、``make regress``、``make signoff`` 的边界；
2. 解释 ``NO_COSIM=1`` 和 ``+disable_cosim=1`` 分别发生在编译期还是运行期；
3. 找到 smoke 日志、sign-off JSON、coverage dashboard 和 HTML 报告的默认位置；
4. 遇到 deprecated alias 时，把旧命令改写成当前推荐入口。

§1  本章边界
-------------

本章给验证工程师一个最短但不失真的上手路径：先进入 `/home/host/eh2-veri`，
加载 `env.sh`，确认无 Spike 环境时如何编译，运行 `make smoke`，再进入
directed/cosim/riscv-dv 回归和 sign-off。脚本内部实现详见 :ref:`scripts_reference`；
构建 target 详见 :ref:`build_flow`；sign-off gate 详见 :ref:`signoff_flow`。

当前源码里有一个容易踩错的点：`make run` 还存在，但 Makefile 已把它标记为
deprecated alias。快速上手应使用 `make smoke`、`make regress` 和 `make signoff`。
sign-off profile 变量名是 `PROFILE`，旧版 profile 变量只在历史 wrapper 中可见。

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh
   make compile NO_COSIM=1 SIMULATOR=vcs
   make smoke
   make signoff PROFILE=quick PARALLEL=4

逐段解释：

* 第 1 行：README quick start 固定从 `/home/host/eh2-veri` 工作区开始。
* 第 2 行：`source env.sh` 把 `EH2_VERIF_ROOT`、`RV_ROOT`、`GCC_PREFIX` 和
  RISC-V GCC `PATH` 写入当前 shell。
* 第 3 行：`NO_COSIM=1` 只跳过编译期 `libcosim.so` 链接，适合没有 Spike 安装目录的
  smoke bring-up。
* 第 4 行：`make smoke` 会编译 testbench、编译 `tests/asm/smoke.hex`，再通过
  `run_regress.py --test smoke` 启动 RTL simulation。
* 第 5 行：`PROFILE=quick` 对应 `signoff.py` 中的 `smoke` 与 `directed` 两个 stage。

接口关系：

* 被调用：第一次进入 EH2-Veri 工作区的验证工程师。
* 调用：`env.sh`、顶层 `Makefile`、`run_regress.py`、`signoff.py`。
* 共享状态：`build/simv`、`tests/asm/smoke.hex`、`build/smoke/`、
  `build/signoff/` 和环境变量 `GCC_PREFIX`。

§2  README quick start 的最小命令
----------------------------------

README 的 quick start 没有假设仓库会安装外部工具；它明确说前提是 prepared
workspace，且 VCS 和 RISC-V toolchain 已经可用。最小 smoke 命令可以直接调用
`run_regress.py`，并用 `+disable_cosim=1` 关闭运行期 cosim。

关键代码（`README.md:L124-L139`）：

.. code-block:: bash

   ## Quick Start

   The following three commands run the smoke path from a prepared workspace with
   VCS and the RISC-V toolchain available:

   ```bash
   cd /home/host/eh2-veri
   source env.sh
   python3 dv/uvm/core_eh2/scripts/run_regress.py --test smoke --binary tests/asm/smoke.hex --simulator vcs --rtl-test core_eh2_base_test --sim-opts "+disable_cosim=1" --output build/quick_smoke
   ```

   If `build/simv` is missing, compile first:

   ```bash
   make compile NO_COSIM=1 SIMULATOR=vcs
   ```

逐段解释：

* 第 L124-L128 行：README 把 quick start 定位为 prepared workspace 上的 smoke path，
  并显式列出 VCS 和 RISC-V toolchain 前提。
* 第 L130-L132 行：示例直接调用 `run_regress.py`，指定 `--test smoke`、预编译
  `tests/asm/smoke.hex`、VCS、UVM test class 和 `+disable_cosim=1`。
* 第 L135-L139 行：如果 `build/simv` 不存在，需要先运行
  `make compile NO_COSIM=1 SIMULATOR=vcs`。这一步不会替代后续运行期 plusarg。

接口关系：

* 被调用：README 用户、CI smoke 调试者。
* 调用：`run_regress.py` 和顶层 `make compile`。
* 共享状态：`build/simv`、`build/quick_smoke/`、`tests/asm/smoke.hex`。

§3  环境脚本只设置变量
-----------------------

`env.sh` 的职责是设置路径，不负责检查工具版本、不安装依赖，也不创建 `build/simv`。
因此上手流程中要把 “source 环境” 和 “编译/运行” 分开看。

关键代码（`env.sh:L1-L19`）：

.. code-block:: bash

   #!/bin/bash
   # EH2 UVM Verification Platform - Environment Setup
   # Source this file: source env.sh

   # Project root
   export EH2_VERIF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

   # RTL source
   export RV_ROOT="/home/host/Cores-VeeR-EH2"

   # RISC-V GCC toolchain
   export GCC_PREFIX="/home/host/gcc-riscv64-unknown-elf"
   export PATH="${GCC_PREFIX}/bin:${PATH}"

   # QEMU (for co-simulation)
   export QEMU_BIN="/home/host/eh2-verification/qemu-eh2/build/qemu-system-riscv32"

   # Simulator selection (vcs/xlm/questa)
   export EH2_SIMULATOR="vcs"

逐段解释：

* 第 L1-L3 行：注释要求通过 `source env.sh` 使用。作为子进程执行时，`export`
  无法影响当前 shell。
* 第 L5-L13 行：脚本从自身路径推导 `EH2_VERIF_ROOT`，固定 `RV_ROOT`，设置
  `GCC_PREFIX`，并把 `${GCC_PREFIX}/bin` 前置到 `PATH`。
* 第 L15-L19 行：脚本还设置 `QEMU_BIN` 和 `EH2_SIMULATOR`。顶层 Makefile 的常用变量
  仍是 `SIMULATOR ?= vcs`，命令行可用 `SIMULATOR=xlm` 或 `SIMULATOR=questa` 覆盖。

接口关系：

* 被调用：交互式 shell、README quick start。
* 调用：无外部命令，除 shell 参数展开。
* 共享状态：`EH2_VERIF_ROOT`、`RV_ROOT`、`GCC_PREFIX`、`PATH`、`QEMU_BIN`、
  `EH2_SIMULATOR`。

§4  Makefile 变量：上手时只需少数几个
--------------------------------------

顶层 Makefile 把常用变量集中定义在“用户可覆盖变量”段。快速上手阶段通常只需要
`SIMULATOR`、`NO_COSIM`、`PARALLEL`、`TEST`、`TESTLIST`、`PROFILE` 和 `SIGNOFF_OUT`。

关键代码（`Makefile:L121-L146`）：

.. code-block:: bash

   CONFIG          ?= default
   SEED            ?= 1
   TEST            ?=
   TESTLIST        ?= riscvdv
   SIMULATOR       ?= vcs
   BINARY          ?=
   VERBOSITY       ?= UVM_MEDIUM
   TIMEOUT_NS      ?= 10000000
   WAVES           ?= 0
   COV             ?= 1
   ITERATIONS      ?= 1
   PARALLEL        ?= 4
   RTL_TEST        ?= core_eh2_base_test
   SIM_OPTS        ?=
   GEN_OPTS        ?=

   # Sign-off
   PROFILE         ?= full
   GATE_ONLY       ?= 0
   CLEANUP         ?= 0
   SIGNOFF_OUT     ?= $(BUILD_DIR)/signoff
   SIGNOFF_OPTS    ?=
   SIGNOFF_ITERATIONS ?=
   LEC_KNOWN_LIMITED  ?= 0
   LEC_BLOCKLEVEL  ?= 1
   LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt

逐段解释：

* 第 L121-L135 行：仿真类 target 使用 `SIMULATOR`、`TEST`、`TESTLIST`、`SEED`、
  `ITERATIONS`、`PARALLEL`、`WAVES`、`COV` 等变量。
* 第 L137-L146 行：sign-off 使用 `PROFILE`，默认 `full`。旧版 profile
  变量不是当前顶层 Makefile 的推荐入口。
* `LEC_BLOCKLEVEL ?= 1` 表示 sign-off 默认启用 block-level LEC summary 路径；
  若没有 `syn/build/lec_summary.txt`，需要先跑 synthesis/LEC 或显式调整参数。

接口关系：

* 被调用：所有顶层 `make` 命令。
* 调用：变量在后续 target recipe 中展开。
* 共享状态：Make 命令行变量、环境变量和 `build/` 输出目录。

§5  `make compile`：生成 `build/simv`
--------------------------------------

`make compile` 根据 `SIMULATOR` 调度到 `compile_vcs` 或 `compile_xlm`。VCS 路径读取
RTL、shared 和 TB filelist，top 为 `core_eh2_tb_top`，输出 `build/simv`。

关键代码（`Makefile:L803-L831`）：

.. code-block:: makefile

   compile: compile_$(SIMULATOR)

   compile_vcs: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
   	@echo "=== [compile] VCS UVM testbench ==="
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

逐段解释：

* 第 L803 行：`compile` 是调度 target，实际规则由 `SIMULATOR` 决定。
* 第 L805-L813 行：VCS 编译依赖 `COMPILE_LIBCOSIM_DEP`，并开启 UVM 1.2、
  SVA extension、`GTLSIM` define 和 snapshot include。
* 第 L819-L823 行：编译读取 `eh2_rtl.f`、`eh2_shared.f`、`eh2_tb.f`，top module 是
  `core_eh2_tb_top`，并按 `NO_COSIM` 决定是否链接 `libcosim.so`。

接口关系：

* 被调用：`make smoke`、`make regress` 和用户直接 `make compile`。
* 调用：VCS 或 Xcelium。
* 共享状态：`build/simv`、`build/compile.log`、`build/csrc/`、`build/libcosim.so`。

§6  `make smoke`：最短 RTL 仿真路径
------------------------------------

`make smoke` 是当前推荐的快速冒烟入口。它依赖 `compile` 和 `asm`，然后调用
`run_regress.py` 运行 `smoke`，使用 `tests/asm/smoke.hex`，并传入
`+disable_cosim=1`。

关键代码（`Makefile:L854-L865`）：

.. code-block:: makefile

   smoke: compile asm
   	@echo "=== [smoke] 运行 smoke 测试 ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --test smoke \
   	  --binary $(ASM_DIR)/smoke.hex \
   	  --simulator $(SIMULATOR) \
   	  --seed 1 \
   	  --rtl-test core_eh2_base_test \
   	  --sim-opts "+disable_cosim=1" \
   	  --output $(BUILD_DIR)/smoke \
   	  $(if $(filter 1,$(WAVES)),--waves,)
   	@echo "=== [smoke] 完成 ==="

逐段解释：

* 第 L854 行：`smoke` 会先确保 testbench 已编译、ASM hex 已生成。
* 第 L856-L863 行：脚本参数固定为单测 `smoke`、binary `$(ASM_DIR)/smoke.hex`、
  seed 1、UVM test `core_eh2_base_test` 和输出目录 `build/smoke`。
* 第 L862 行：`+disable_cosim=1` 是运行期 plusarg；它和 `NO_COSIM=1` 分别作用于运行期和编译期。
* 第 L864 行：如果命令行传 `WAVES=1`，Makefile 追加 `--waves`。

接口关系：

* 被调用：开发循环、CI 快速 gate。
* 调用：`compile`、`asm`、`run_regress.py`。
* 共享状态：`tests/asm/smoke.hex`、`build/smoke/smoke_s1/`、`sim_smoke_1.log`。

§7  `run_regress.py` 单测内部阶段
----------------------------------

`run_regress.py` 的单测执行顺序是：必要时生成 assembly，必要时编译为 binary/hex，
调用 `run_rtl.py` 运行仿真，再调用 `check_sim_log()` 判断 PASS/FAIL 并保存结果。
当 `--binary` 已传入时，生成和编译阶段会被跳过。

关键代码（`dv/uvm/core_eh2/scripts/run_regress.py:L171-L201`）：

.. code-block:: python

   def run_single_test(test_entry: dict, seed: int, simulator: str,
                       output_dir: str, binary: str = "",
                       cli_sim_opts: str = "",
                       coverage: bool = False,
                       waves: bool = False,
                       fail_on_warnings: bool = False) -> TestRunResult:
       """
       Run a single test: generate, compile, simulate, check.

       Returns:
           TestRunResult
       """
       result = TestRunResult()
       test_name = test_entry["test"]
       result.test_name = test_name
       result.seed = seed
       result.test_type = test_entry.get("test_type", "DIRECTED"
                                         if test_entry.get("asm") or
                                         test_entry.get("test_srcs") else
                                         "RISCVDV")

       work_dir = os.path.join(output_dir, f"{test_name}_s{seed}")
       os.makedirs(work_dir, exist_ok=True)

       gen_opts = test_entry.get("gen_opts", "")
       rtl_test = test_entry.get("rtl_test", "core_eh2_base_test")
       sim_opts = build_sim_opts(test_entry, cli_sim_opts)

逐段解释：

* 第 L171-L176 行：函数参数覆盖 test entry、seed、simulator、输出目录、binary、
  CLI sim opts、coverage、waves 和 warning 策略。
* 第 L183-L190 行：结果对象记录 test name、seed 和 test type。若 entry 有
  `asm` 或 `test_srcs`，默认 type 为 `DIRECTED`；否则为 `RISCVDV`。
* 第 L192-L197 行：work directory 以 `<test>_s<seed>` 命名，UVM test 默认
  `core_eh2_base_test`，sim opts 由 `build_sim_opts()` 合成。

关键代码（`dv/uvm/core_eh2/scripts/run_regress.py:L251-L303`，节选）：

.. code-block:: python

       if not binary:
           # Step 2: Compile to binary/hex
           compile_start = time.time()
           bin_path = os.path.join(work_dir, f"{test_name}.bin")
           hex_path = os.path.join(work_dir, f"{test_name}.hex")
           asm_for_compile = result.assembly_path
           compile_cmd = [
               sys.executable, os.path.join(SCRIPT_DIR, "compile_test.py"),
               "--asm", asm_for_compile,
               "--bin", bin_path,
               "--hex", hex_path,
           ]
           if test_entry.get("linker"):
               linker = test_entry["linker"]
               if not os.path.isabs(linker):
                   linker = os.path.join(DV_DIR, linker)
               compile_cmd.extend(["--linker", linker])

逐段解释：

* 第 L251-L262 行：没有 `--binary` 时，脚本调用 `compile_test.py` 从 assembly 生成
  `.bin` 和 `.hex`。
* 第 L263-L267 行：如果 test entry 指定 linker，脚本将相对路径转为 DV 目录下路径，
  再传给 compile command。
* 在 smoke 的 Makefile 路径中已经提供 `--binary $(ASM_DIR)/smoke.hex`，因此这段编译逻辑不会重跑。

关键代码（`dv/uvm/core_eh2/scripts/run_regress.py:L288-L335`，节选）：

.. code-block:: python

       # Step 3: Run RTL simulation
       sim_start = time.time()
       log_path = os.path.join(work_dir, f"sim_{test_name}_{seed}.log")

       # For now, use a simpler direct command
       sim_cmd = [
           sys.executable, os.path.join(SCRIPT_DIR, "run_rtl.py"),
           "--test", test_name,
           "--seed", str(seed),
           "--binary", binary,
           "--simulator", simulator,
           "--rtl-test", rtl_test,
           "--sim-opts", sim_opts,
           "--build-dir", os.path.join(EH2_ROOT, "build"),
           "--out-dir", work_dir,
       ]
       if coverage:
           sim_cmd.append("--coverage")
       if waves:
           sim_cmd.append("--waves")

逐段解释：

* 第 L288-L303 行：仿真命令固定调用 `run_rtl.py`，并传入 test、seed、binary、
  simulator、UVM test class、sim opts、build directory 和 work directory。
* 第 L304-L307 行：coverage 和 waves 是布尔开关，分别追加 `--coverage`、`--waves`。
* 第 L322-L335 行随后调用 `check_sim_log()`，把 PASS/FAIL、UVM errors/warnings、
  instruction count、cycles 和 IPC 写回 `TestRunResult`。

接口关系：

* 被调用：`make smoke`、`make regress`、`signoff.py` stage command。
* 调用：`run_instr_gen.py`、`compile_test.py`、`run_rtl.py`、`check_logs.py`。
* 共享状态：`work_dir/result`、`regr.log`、`regr_junit.xml`、`report.json`。

§8  `make regress`：从单测扩展到 testlist
-------------------------------------------

`make regress` 会先编译 testbench，然后按 `TEST` 或 `TESTLIST` 选择单测或 testlist。
`TESTLIST=directed` 和 `TESTLIST=cosim` 会被 Makefile 映射到对应 YAML；默认
`TESTLIST=riscvdv` 映射到 riscv-dv extension testlist。

关键代码（`Makefile:L188-L191`）：

.. code-block:: makefile

   # testlist 路由
   TESTLIST_PATH := $(if $(filter directed,$(TESTLIST)),$(TB_DIR)/directed_tests/directed_testlist.yaml,\
                    $(if $(filter cosim,$(TESTLIST)),$(TB_DIR)/directed_tests/cosim_testlist.yaml,\
                    $(DV_EXT_DIR)/testlist.yaml))

逐段解释：

* 第 L188-L191 行：`TESTLIST=directed` 使用 directed YAML；`TESTLIST=cosim` 使用
  cosim YAML；其他值走 riscv-dv extension YAML。

关键代码（`Makefile:L867-L878`）：

.. code-block:: makefile

   regress: compile
   	@echo "=== [regress] testlist=$(TESTLIST) parallel=$(PARALLEL) iter=$(ITERATIONS) ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  $(if $(TEST),--test $(TEST),--testlist $(TESTLIST_PATH)) \
   	  --simulator $(SIMULATOR) \
   	  --seed $(SEED) \
   	  --iterations $(ITERATIONS) \
   	  --parallel $(PARALLEL) \
   	  --output $(if $(OUT),$(OUT),$(BUILD_DIR)/regression) \
   	  $(if $(filter 1,$(COV)),--coverage,) \
   	  $(if $(filter 1,$(WAVES)),--waves,)
   	@echo "=== [regress] 完成 ==="

逐段解释：

* 第 L867 行：`regress` 依赖 `compile`，不会自动调用 `asm`。
* 第 L869-L875 行：如果 `TEST` 非空，传 `--test <name>`；否则传 `--testlist`
  和 `TESTLIST_PATH`。并行度、seed、iterations 和输出目录均由 Make 变量控制。
* 第 L876-L877 行：`COV=1` 追加 `--coverage`，`WAVES=1` 追加 `--waves`。

接口关系：

* 被调用：开发自检、directed/cosim/riscv-dv 局部回归。
* 调用：`compile`、`run_regress.py`。
* 共享状态：`build/regression/` 或 `OUT=<dir>` 指定目录。

§9  `make signoff`：quick、full 与 gate-only
---------------------------------------------

`make signoff` 是当前签核入口。`PROFILE=quick` 映射到 smoke 和 directed；
`PROFILE=full` 映射到 smoke、directed、cosim、riscvdv、lint、csr_unit、
compliance、formal 和 syn。`GATE_ONLY=1` 表示只评估已有结果，不重跑 stage。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L37-L53`）：

.. code-block:: python

   PROFILE_STAGES = {
       "quick": ["smoke", "directed"],
       "cosim": ["smoke", "cosim"],
       "riscvdv_smoke": ["riscvdv"],
       "nightly": ["smoke", "directed", "cosim", "riscvdv"],
       "full": ["smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                "compliance", "formal", "syn"],
   }

   STAGE_MIN_PASSED = {
       "smoke": 1,
       "directed": 33,
       "cosim": 7,
       "riscvdv": 50,
       "csr_unit": 20,
       "compliance": 85,
   }

逐段解释：

* 第 L37-L44 行：profile 到 stage list 的映射在 Python 中定义，Makefile 只是传入
  `--profile $(PROFILE)`。
* 第 L46-L53 行：部分 stage 有最低 passed 数量要求。例如 cosim 需要至少 7，
  compliance 需要至少 85。

关键代码（`Makefile:L918-L935`）：

.. code-block:: makefile

   signoff:
   	@echo "=== [signoff] profile=$(PROFILE) gate_only=$(GATE_ONLY) out=$(SIGNOFF_OUT) ==="
   	python3 $(SCRIPTS_DIR)/signoff.py \
   	  --profile $(PROFILE) \
   	  --simulator $(SIMULATOR) \
   	  --seed $(SEED) \
   	  --parallel $(PARALLEL) \
   	  --output $(SIGNOFF_OUT) \
   	  $(if $(filter 1,$(GATE_ONLY)),--gate-only,) \
   	  $(if $(SIGNOFF_ITERATIONS),--iterations $(SIGNOFF_ITERATIONS),) \
   	  $(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,) \
   	  $(if $(filter 1,$(LEC_BLOCKLEVEL)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),) \
   	  $(if $(filter 1,$(COV)),--coverage --min-line-coverage $(SIGNOFF_MIN_LINE_COV) --min-functional-coverage $(SIGNOFF_MIN_FUNCTIONAL_COV),) \
   	  $(if $(filter 1,$(SIGNOFF_ALLOW_WARNINGS)),--allow-warnings,) \
   	  $(if $(filter 1,$(WAVES)),--waves,) \
   	  $(SIGNOFF_OPTS)

逐段解释：

* 第 L918-L925 行：Makefile 把 profile、simulator、seed、parallel 和 output
  传给 `signoff.py`。
* 第 L926-L929 行：`GATE_ONLY`、`SIGNOFF_ITERATIONS`、LEC known-limited 和 block-level
  LEC 通过条件展开控制。
* 第 L930-L933 行：`COV=1` 时追加 coverage gate；`SIGNOFF_ALLOW_WARNINGS=1`
  追加 `--allow-warnings`；`WAVES=1` 追加 `--waves`。

接口关系：

* 被调用：release gate、CI gate、局部 quick sign-off。
* 调用：`signoff.py`，以及 `signoff.py` 内部的 stage runners。
* 共享状态：`$(SIGNOFF_OUT)/signoff_status.json`、`signoff_report.md`、`report.html`、
  `runs/<stage>/`。

§10  sign-off 报告与 release 数字
----------------------------------

当前主线数字以 2026-05-19 01:02 的 VCS demo 实测为准。本快速上手章节只引用
这些数字，不重新计算、不扩展含义；脚本如何生成报告见 :ref:`signoff_flow`。

实测摘要：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   real run coverage: 102/104 (98.1%)
   LEC: 31635/31635 PASS

   riscvdv  370/395 (93.67%)
   compliance  85/88 (96.59%)
   directed 40/40 (100%)
   formal 46/46 (100%)

逐段解释：

* 第 1-4 行：`make demo` / `make signoff` 的 full profile 结果应收敛到 PASS，
  其中 LEC compare point 是 31635/31635。
* 第 6-9 行：快速核对时最常用的 stage 数字是 riscv-dv 370/395、
  compliance 85/88、directed 40/40 和 formal 46/46。

覆盖率摘要：

.. code-block:: text

   LINE     95.05%
   BRANCH   84.97%
   TOGGLE   53.52%
   ASSERT   33.33%
   FSM      54.74%
   GROUP    69.42%
   OVERALL  65.17%

逐段解释：

* 第 1-7 行：这些数字来自 `core_eh2_tb_top.dut` DUT-only scope 的 URG 原生
  dashboard。当前覆盖率维度是 `line+tgl+assert+fsm+branch`，没有 cond 维度。
* `GROUP` 是 covergroup/function coverage 的报告项；Makefile 的历史参数名仍是
  `SIGNOFF_MIN_FUNCTIONAL_COV`。

接口关系：

* 被调用：release replay、验收抽检。
* 调用：无；该文档是 status artifact 摘要。
* 共享状态：`build/demo/signoff_status.json`、`build/demo/cov_merged/dashboard.txt`。

§11  deprecated alias：不要从旧命令开始
-----------------------------------------

旧 target 仍保留是为了兼容旧 CI 和旧文档，但 Makefile 会输出 deprecated 提示并转发。
快速上手不应使用旧命令作为主路径。

关键代码（`Makefile:L649-L663`）：

.. code-block:: bash

   ──────────────────────────────────────────────────────────────────────────────
   [ 已废弃的旧 target ] —— 保留作 alias，下个发布周期可能移除
   ──────────────────────────────────────────────────────────────────────────────

     run / gen / nightly / weekly / run_regress            → make regress + 变量
     compile_vcs / compile_xlm                             → 由 compile 自动调度
     signoff_quick / signoff_gate / signoff_with_cleanup   → make signoff + PROFILE/GATE_ONLY/CLEANUP=
     html_report / cov                                     → 已合并到 signoff
     lint_verible / lint_verilator                         → make lint TOOL=
     syn_yosys / syn_dc / lec / block_lec / syn_clean      → make synth STEP= / make clean SCOPE=syn
     formal_clean                                          → make clean SCOPE=formal
     compliance-all / compliance-compile                   → make compliance MODE=
     manual_html                                           → make manual FORMAT=html

逐段解释：

* 第 L649-L655 行：`run`、`run_regress`、`signoff_quick` 等旧 target 仍存在，但说明文字明确写成
  deprecated alias。
* 第 L656-L663 行：HTML report、coverage、lint、synthesis、formal clean、compliance
  和 manual 的旧入口也都映射到新 target。

关键代码（`Makefile:L1081-L1083`）：

.. code-block:: makefile

   run:
   	@echo "[deprecated] 'make run' → 'make regress TEST=$(TEST) SEED=$(SEED)'"
   	@$(MAKE) --no-print-directory regress TEST=$(TEST) SEED=$(SEED)

逐段解释：

* 第 L1081-L1083 行：`make run` 会转发到 `make regress`。如果旧文档写
  `make run TEST=riscv_smoke_test`，实际语义已经不是“推荐入口”，而是 deprecated 转发。

接口关系：

* 被调用：旧 CI、旧手册命令、用户历史脚本。
* 调用：新 target，例如 `regress` 和 `signoff`。
* 共享状态：同新 target 的输出目录。

§12  阅读顺序
--------------

完成 smoke 后，建议按问题域阅读文档，而不是线性通读全手册：

.. list-table::
   :header-rows: 1
   :widths: 28 36 36

   * - 目标
     - 先读
     - 再读
   * - 只想跑通平台
     - :ref:`getting_started`
     - :ref:`system_requirements`
   * - 理解 DUT/TB 连接
     - :ref:`tb_top`
     - :ref:`soc_integration`
   * - 调 cosim mismatch
     - :ref:`cosim_scoreboard`
     - :ref:`rvfi_trace`
   * - 跑 directed/cosim/riscv-dv
     - :ref:`regression_flow`
     - :ref:`scripts_reference`
   * - 看 sign-off gate
     - :ref:`signoff_flow`
     - :ref:`formal_flow`
   * - 查 UVM class
     - :ref:`appendix_b_uvm/cosim_agent`
     - :ref:`appendix_b_uvm/env`

接口关系：

* 被调用：新加入项目的验证工程师、抽检 reviewer。
* 调用：现有章节引用。
* 共享状态：无运行时状态；只建立阅读路径。

§13  参考资料
--------------

关联章节：

* :ref:`getting_started` — 从工作区到 smoke/regress/sign-off 的详细命令。
* :ref:`system_requirements` — VCS、RISC-V GCC、Spike、lint/formal/synth/doc 依赖边界。
* :ref:`soc_integration` — DUT wrapper、AXI4、IRQ/JTAG、RVFI sidecar 连接。
* :ref:`scripts_reference` — CLI 参数语义和脚本互调关系。
* :ref:`signoff_flow` — sign-off stage、gate-only、coverage gate 和 replay。
* :ref:`cosim_scoreboard` — cosim 数据流与 Spike 通知顺序。

源文件绝对路径：

* :file:`/home/host/eh2-veri/README.md`
* :file:`/home/host/eh2-veri/env.sh`
* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* :file:`/home/host/eh2-veri/docs/PROJECT_STATUS.md`
