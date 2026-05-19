.. _getting_started:
.. _03_integration/getting_started:

快速启动指南
============

:status: draft
:source: README.md; env.sh; env.mk; Makefile; dv/uvm/core_eh2/Makefile; dv/uvm/core_eh2/scripts/run_regress.py; dv/uvm/core_eh2/scripts/signoff.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
-----------------

读懂本章，你需要能在 Linux shell 中完成最基本操作：``cd`` 切目录、``source`` 加载环境、
``make <target> VAR=value`` 传变量，以及用 ``grep`` 在日志中搜索关键字。不要求你已经懂
SystemVerilog 或 UVM；本章的目标是先把平台跑起来，再回头解释内部机制。

开始前请确认：

* 你位于 :file:`/home/host/eh2-veri` 工作区，且知道这是验证平台仓库；
* 上游 DUT clone 位于 :file:`/home/host/Cores-VeeR-EH2/`；
* VCS 是默认仿真器，NC/Incisive 是可选备选路径；本章命令优先展示 VCS；
* 你能接受第一次编译较慢，因为 testbench、DUT、UVM package 和 coverage 选项都要展开。

学完本章你能：

1. 从一个新 shell 进入工作区并加载 :file:`env.sh`；
2. 在没有 Spike cosim 环境时用 ``NO_COSIM=1`` 编译出最小 ``simv``；
3. 跑 ``make smoke`` 并知道去哪个 ``build/`` 子目录找日志；
4. 把单测扩展到 ``make regress`` 和 ``make signoff PROFILE=quick``；
5. 遇到工具缺失、GCC 缺失或旧 target 提示时，知道先查哪一节。

§1  本章边界
-------------

本章只说明从一个已经准备好的 `/home/host/eh2-veri` 工作区开始，如何进入
EH2 验证平台、选择当前 Makefile 入口、跑第一个 smoke 测试，并进一步进入
regress、sign-off 与 gate-only 复演。这里不重复解释每个 driver 的内部实现；
脚本级细节见 :ref:`scripts_reference`，构建细节见 :ref:`build_flow`，
签核细节见 :ref:`signoff_flow`。

当前源码里存在两套容易混淆的入口：

.. code-block:: bash

   # 当前推荐：GOAL 为空，使用顶层 Makefile 规整后的 core targets
   make compile NO_COSIM=1 SIMULATOR=vcs
   make smoke
   make regress TESTLIST=directed PARALLEL=4
   make signoff PROFILE=quick PARALLEL=4

   # 兼容路径：GOAL 非空时，make run 会进入 wrapper.mk staged flow
   make run GOAL=<wrapper-target> CONFIG=default SEED=1

逐段解释：

* 第 1-5 行：这些命令对应 :file:`Makefile` 的默认分支，也就是 `GOAL`
  为空时的 `else` 分支。该分支定义 `compile`、`smoke`、`regress`、
  `signoff` 等核心 target。
* 第 7-8 行：`GOAL` 非空时，顶层 `Makefile` 在前置分支只保留一个
  `run` target；它先调用 `metadata.py --op create_metadata`，再把工作转交给
  :file:`dv/uvm/core_eh2/wrapper.mk`。
* 本章后续以默认分支为主。原因不是 `wrapper.mk` 不可用，而是当前顶层
  `Makefile` 的 `help` 文本明确把规整后的 15 个 core target 作为主要入口。

接口关系：

* 被调用：用户 shell、CI job、局部 `dv/uvm/core_eh2/Makefile`。
* 调用：顶层 `Makefile`、`run_regress.py`、`signoff.py`。
* 共享状态：`build/` 下的 `simv`、`libcosim.so`、`runs/`、coverage 数据库和
  sign-off 报告目录。

§2  工作区与环境脚本
---------------------

`README.md` 的 quick start 先进入固定工作区，再 source `env.sh`。`env.sh`
不是一个工具检查脚本；它只设置路径变量、把 RISC-V GCC 的 `bin` 目录加入
`PATH`，最后打印当前环境摘要。

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

* 第 124-128 行：README 把 quick start 的前提限定为“prepared workspace”，并且
  明确要求 VCS 与 RISC-V toolchain 可用。文档不能把这些外部依赖写成仓库自动安装。
* 第 130-132 行：示例先 `cd /home/host/eh2-veri`，再 `source env.sh`，最后直接调用
  `run_regress.py` 跑一个 `smoke` 单测。这里显式传入 `--binary tests/asm/smoke.hex`
  和 `--sim-opts "+disable_cosim=1"`，表示使用已编译 hex 并在仿真 plusarg 侧关闭
  cosim。
* 第 135-139 行：如果 `build/simv` 缺失，README 要求先执行
  `make compile NO_COSIM=1 SIMULATOR=vcs`。`NO_COSIM=1` 是编译期跳过
  `libcosim.so` 链接的 Make 变量，不等同于运行期 plusarg。

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

* 第 1-3 行：文件需要被 `source`，不是作为子进程执行。只有 `source env.sh`
  才能把后续 `export` 的变量保留在当前 shell。
* 第 5-7 行：`EH2_VERIF_ROOT` 从 `env.sh` 自身路径反推，因此只要从仓库内 source
  该脚本，变量就指向当前验证平台根目录。
* 第 8-13 行：`RV_ROOT` 固定到 `/home/host/Cores-VeeR-EH2`，`GCC_PREFIX` 固定到
  `/home/host/gcc-riscv64-unknown-elf`，并把 `${GCC_PREFIX}/bin` 放到 `PATH`
  前面。后续 `signoff.py` 的 precheck 会基于 `GCC_PREFIX` 查找
  `riscv32-unknown-elf-gcc`。
* 第 15-19 行：脚本还导出 `QEMU_BIN` 与 `EH2_SIMULATOR`。当前顶层 `Makefile`
  使用自己的 `SIMULATOR ?= vcs` 变量；`EH2_SIMULATOR` 是 shell 环境变量，不会自动替代
  `make SIMULATOR=...`。

接口关系：

* 被调用：交互式 shell、README quick start。
* 调用：无子命令调用；只执行 shell 参数展开与 `export`。
* 共享状态：`PATH`、`EH2_VERIF_ROOT`、`RV_ROOT`、`GCC_PREFIX`、`QEMU_BIN`、
  `EH2_SIMULATOR`。

§3  Makefile 的默认变量
------------------------

顶层 `Makefile` 包含 `env.mk`，但 `env.mk` 当前只给 `EH2_SIMULATOR`、`WAVES`
和 `COV` 提供默认值。真正驱动 `compile`、`smoke`、`regress`、`signoff`
的默认变量集中在顶层 `Makefile` 的“用户可覆盖变量”段。

关键代码（`env.mk:L1-L9`）：

.. code-block:: makefile

   # EH2 UVM Verification Platform - Environment Makefile
   # This file is included by the main Makefile

   # Simulator selection
   EH2_SIMULATOR ?= vcs

   # Build options
   WAVES ?= 0
   COV ?= 0

逐段解释：

* 第 1-2 行：`env.mk` 是被顶层 `Makefile` include 的片段，不是独立入口。
* 第 4-5 行：`EH2_SIMULATOR ?= vcs` 只设置 `EH2_SIMULATOR` 变量；顶层直接编译路径
  使用的是 `SIMULATOR ?= vcs`。
* 第 7-9 行：`WAVES` 与 `COV` 在这里默认关闭，但顶层 `Makefile` 后续又设置
  `COV ?= 1`。由于 `?=` 只在变量尚未定义时生效，include 顺序会让 `env.mk`
  中的 `COV ?= 0` 成为当前默认值，除非命令行显式传 `COV=1`。

关键代码（`Makefile:L121-L151`）：

.. code-block:: makefile

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

* 第 121-135 行：这些变量控制常规构建和仿真。常用覆盖项包括 `SIMULATOR`、
  `TEST`、`TESTLIST`、`SEED`、`ITERATIONS`、`PARALLEL`、`WAVES`、`COV` 和
  `SIM_OPTS`。
* 第 137-146 行：sign-off 使用 `PROFILE`，不是旧文档中的 sign-off profile 变量名。
  `PROFILE` 可传给 `signoff.py --profile`，`GATE_ONLY` 会展开为 `--gate-only`，
  `LEC_BLOCKLEVEL` 会展开为 `--lec-blocklevel --lec-summary-path`。
* 第 148-151 行：当前默认门限在 Makefile 中写为 line 65、functional
  40，并允许 warnings。这里是门限，不是已达成覆盖率数字；当前实测数字以
  2026-05-19 VCS demo 和 :ref:`signoff_flow` 为准。

接口关系：

* 被调用：所有顶层 `make` 命令。
* 调用：不直接调用下游；变量在后续 target recipe 中展开。
* 共享状态：Make 命令行变量、环境变量、`build/` 输出路径。

§4  第一次编译：无 Spike 环境路径
----------------------------------

如果只是确认 UVM testbench 能编译，且本机没有 Spike cosim 安装目录，当前 quick
start 应使用 `NO_COSIM=1`。这条路径只影响 VCS 直接编译规则中的 `libcosim.so`
依赖与链接参数；实际仿真是否启用 cosim 仍由运行期 plusarg 决定。

关键代码（`Makefile:L451-L480`）：

.. code-block:: makefile

   cosim: $(LIBCOSIM)

   $(LIBCOSIM): $(COSIM_DIR)/spike_cosim.cc $(COSIM_DIR)/cosim_dpi.cc \
                $(COSIM_DIR)/spike_cosim.h $(COSIM_DIR)/cosim.h | $(BUILD_DIR)
   	@if [ ! -d "$(SPIKE_INSTALL)" ]; then \
   	  echo "ERROR: SPIKE_INSTALL=$(SPIKE_INSTALL) 不存在。"; \
   	  echo "       先 build spike-cosim，或设 SPIKE_DIR=<path>，或传 NO_COSIM=1 跳过 cosim。"; \
   	  exit 1; \
   	fi
   	@echo "=== [cosim] 构建 Spike DPI libcosim.so ==="
   	@mkdir -p $(SPIKE_BUILD)
   	@cd $(SPIKE_BUILD) && \
   	  ar x $(SPIKE_INSTALL)/lib/libriscv.a && \
   	  rm -f libfdt.a libsoftfloat.a && \
   	  ar x $(SPIKE_INSTALL)/lib/libdisasm.a && \
   	  ar x $(SPIKE_INSTALL)/lib/libfesvr.a && \

逐段解释：

* 第 451 行：`cosim` target 只依赖 `$(LIBCOSIM)`，因此它本身是构建 Spike DPI
  共享库的入口。
* 第 453-454 行：`libcosim.so` 的源码依赖包括 `spike_cosim.cc`、
  `cosim_dpi.cc`、`spike_cosim.h` 和 `cosim.h`。
* 第 455-459 行：如果 `$(SPIKE_INSTALL)` 目录不存在，Makefile 直接报错并提示三种处理：
  先 build spike-cosim、设置 `SPIKE_DIR=<path>`，或传 `NO_COSIM=1` 跳过 cosim。
* 第 460-467 行：存在 Spike 安装目录时，规则进入 `$(SPIKE_BUILD)`，展开多个静态库并重新打包
  `libspike_all.a`，供后续共享库链接使用。

关键代码（`Makefile:L494-L521`）：

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

逐段解释：

* 第 494 行：`compile` 根据 `SIMULATOR` 展开为 `compile_vcs` 或 `compile_xlm`。
  因此 `make compile SIMULATOR=vcs` 和 `make compile SIMULATOR=xlm` 走不同 recipe。
* 第 496 行：`compile_vcs` 依赖 `$(COMPILE_LIBCOSIM_DEP)`。在当前 Makefile 中，
  该变量由 `NO_COSIM` 控制；无 Spike 环境时应传 `NO_COSIM=1`。
* 第 498-504 行：VCS 编译使用 `-full64`、`-assert svaext`、`-sverilog`、
  `-ntb_opts uvm-1.2` 和 `+define+GTLSIM`，并引入 RTL snapshot 目录。
* 第 505-514 行：规则显式加入 AXI4、trace、irq、jtag、cosim agent 的 include
  目录，再读取 RTL、shared 和 TB filelist。即使 `NO_COSIM=1` 跳过链接，SV 侧
  cosim agent include 目录仍在编译命令中。

推荐命令：

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh
   make compile NO_COSIM=1 SIMULATOR=vcs COV=0

逐段解释：

* 第 1 行：顶层 Makefile 的路径计算基于仓库根执行最清晰。
* 第 2 行：`env.sh` 提供 `GCC_PREFIX`、`PATH` 和几个工程根路径变量。
* 第 3 行：`NO_COSIM=1` 避免 `libcosim.so` 依赖，`SIMULATOR=vcs` 选择 VCS recipe，
  `COV=0` 避免 quick start 编译时默认继承覆盖率选项。

接口关系：

* 被调用：用户 shell、README quick start、`dv/uvm/core_eh2/Makefile:compile`。
* 调用：VCS 命令、filelist、include 目录、可选 `libcosim.so` 链接。
* 共享状态：`build/simv`、`build/compile.log`、`build/csrc`。

§5  第一个 smoke 测试
---------------------

顶层 `make smoke` 是当前最短的回归入口。它依赖 `compile` 和 `asm`，然后调用
`run_regress.py` 跑 `tests/asm/smoke.hex`，并显式传入 `+disable_cosim=1`。

关键代码（`Makefile:L545-L555`）：

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
   	  --output $(BUILD_DIR)/smoke
   	@echo "=== [smoke] 完成 ==="

逐段解释：

* 第 545 行：`smoke` 先确保 testbench 已编译、ASM hex 已构建。`compile` 会按照
  `SIMULATOR` 选择后端，`asm` 会进入 `tests/asm` 构建 `smoke.hex` 等文件。
* 第 547-550 行：`run_regress.py` 以单测模式运行 `--test smoke`，并用
  `--binary $(ASM_DIR)/smoke.hex` 指向预构建二进制输入。
* 第 551-553 行：`--seed 1`、`--rtl-test core_eh2_base_test` 和
  `--sim-opts "+disable_cosim=1"` 固定了 smoke stage 的基本仿真形态。
* 第 554 行：输出目录固定为 `build/smoke`，后续结果由 `run_regress.py`
  写入 `regr.log`、`regr_junit.xml` 和 `report.json`。

推荐命令：

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh
   make smoke NO_COSIM=1 SIMULATOR=vcs COV=0

逐段解释：

* 第 3 行中的 `NO_COSIM=1` 传给 `compile` 阶段，`make smoke` 自身已经在
  `run_regress.py` 参数里传入 `+disable_cosim=1`。两者分别覆盖编译期和运行期。
* `COV=0` 是 quick start 建议值。若要收集覆盖率，应在理解 `build/cov.vdb`
  和 sign-off coverage gate 后再打开。

接口关系：

* 被调用：用户 shell、`make signoff` 的 smoke stage 逻辑等价路径。
* 调用：`compile`、`asm`、`run_regress.py`。
* 共享状态：`tests/asm/smoke.hex`、`build/smoke/`、`build/simv`。

§6  `run_regress.py` 的命令边界
--------------------------------

直接调用 `run_regress.py` 时必须提供 `--testlist` 或 `--test`。脚本负责构造测试矩阵、
并行执行、生成日志和 JSON 报告；它不会自动编译 `build/simv`，因此 quick start
通常先执行 `make compile` 或使用依赖了 `compile` 的 Make target。

关键代码（`run_regress.py:L447-L498`）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(
           description="EH2 Regression Runner",
           formatter_class=argparse.RawDescriptionHelpFormatter,
           epilog="""
   Examples:
     %(prog)s --testlist riscv_dv_extension/testlist.yaml
     %(prog)s --test riscv_random_instr_test --seed 42 --simulator vcs
     %(prog)s --testlist testlist.yaml --iterations 5 --parallel 4
           """
       )

       # Test selection
       parser.add_argument("--testlist", help="Test list YAML file")
       parser.add_argument("--test", help="Run a single test")
       parser.add_argument("--iterations", type=int, help="Override iterations count")
       parser.add_argument("--seed", type=int, help="Override random seed")

       # Test configuration
       parser.add_argument("--rtl-test", default="core_eh2_base_test",
                           help="UVM test class")

逐段解释：

* 第 447-456 行：`main()` 创建 CLI parser，并在 epilog 中给出三种形式：按 testlist
  跑、按单个 test 跑、按 testlist 加迭代和并行跑。
* 第 459-463 行：`--testlist` 与 `--test` 是测试选择入口；`--iterations`
  和 `--seed` 可以覆盖 testlist 中的默认次数与随机种子。
* 第 466-467 行：`--rtl-test` 默认是 `core_eh2_base_test`，与 `make smoke`
  recipe 传入的 UVM test class 一致。

关键代码（`run_regress.py:L486-L498`）：

.. code-block:: python

       # Output
       parser.add_argument("--output", help="Output directory")

       # Parallelism
       parser.add_argument("--parallel", type=int, default=1,
                           help="Number of parallel test runs")

       args = parser.parse_args()

       if not args.testlist and not args.test:
           parser.error("Must specify --testlist or --test")

       summary = run_regression(args)
       sys.exit(0 if summary.failed == 0 else 1)

逐段解释：

* 第 486-490 行：`--output` 控制结果目录，`--parallel` 控制并发进程数。
* 第 492-495 行：脚本在参数解析后强制要求 `--testlist` 或 `--test` 至少一个存在。
  因此裸跑 `python3 .../run_regress.py` 一定会报参数错误。
* 第 497-498 行：脚本使用 `summary.failed` 决定进程退出码，适合 CI 直接把返回码作为
  回归通过或失败的判断。

关键代码（`run_regress.py:L376-L442`）：

.. code-block:: python

       print(f"\n{'='*60}")
       print(f"EH2 Regression: {len(test_matrix)} test runs")
       print(f"Output: {output_dir}")
       print(f"{'='*60}\n")

       # Run tests (sequential for now, parallel later)
       max_workers = args.parallel if hasattr(args, 'parallel') else 1

       if max_workers > 1:
           with ProcessPoolExecutor(max_workers=max_workers) as executor:
               futures = {}
               for entry, seed in test_matrix:
                   future = executor.submit(
                       run_single_test, entry, seed, args.simulator,

逐段解释：

* 第 376-379 行：脚本先打印测试数量和输出目录。这些信息来自已经展开好的
  `test_matrix`。
* 第 381-383 行：`max_workers` 取自 `args.parallel`，不存在时回退为 1。
* 第 384-391 行：当 `--parallel` 大于 1 时，脚本使用 `ProcessPoolExecutor`
  并行提交 `run_single_test`。这意味着并行粒度是 test/seed 组合，而不是单个仿真内部线程。

接口关系：

* 被调用：`make smoke`、`make regress`、`signoff.py` 的 stage runner、README
  quick start 示例。
* 调用：`run_single_test()`、`check_logs`、`collect_results.generate_report_json()`。
* 共享状态：`build/simv`、输出目录下的 `regr.log`、`regr_junit.xml`、
  `report.json`、可选 `cov.vdb`。

§7  通用回归入口 `make regress`
--------------------------------

`make regress` 是当前顶层 Makefile 的通用回归入口。它依赖 `compile`，再按
`TEST` 或 `TESTLIST` 选择 `run_regress.py` 的单测模式或 testlist 模式。

关键代码（`Makefile:L557-L567`）：

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
   	  $(if $(filter 1,$(COV)),--coverage,)
   	@echo "=== [regress] 完成 ==="

逐段解释：

* 第 557 行：`regress` 会先执行 `compile`。如果要跳过 Spike 链接，需要在
  `make regress` 命令行同样传入 `NO_COSIM=1`。
* 第 559-560 行：当 `TEST` 非空时，Makefile 传 `--test $(TEST)`；否则传
  `--testlist $(TESTLIST_PATH)`。这正是替代旧 `make run TEST=...` 的当前入口。
* 第 561-565 行：`SIMULATOR`、`SEED`、`ITERATIONS`、`PARALLEL` 和输出目录逐项透传给
  `run_regress.py`。
* 第 566 行：只有 `COV=1` 时才附加 `--coverage`。由于 `env.mk` 当前可能把默认
  `COV` 固定为 0，quick start 和 CI 都应显式传值，避免依赖 include 顺序。

常用命令：

.. code-block:: bash

   # 单个 riscv-dv 测试
   make regress TEST=riscv_arithmetic_basic_test SEED=1 NO_COSIM=1 COV=0

   # directed testlist
   make regress TESTLIST=directed ITERATIONS=1 PARALLEL=4 NO_COSIM=1 COV=0

   # cosim directed testlist，需要 build/libcosim.so
   make cosim
   make regress TESTLIST=cosim ITERATIONS=1 PARALLEL=4 COV=0

逐段解释：

* 第 1-2 行：`TEST` 非空时走单测模式；这对应 `Makefile:L560` 的条件展开。
* 第 4-5 行：`TESTLIST=directed` 由 `TESTLIST_PATH` 路由到 directed testlist。
  `NO_COSIM=1` 只影响编译期；具体 test 的 cosim plusarg 还要看 testlist 和
  `run_regress.py` 的 `build_sim_opts()`。
* 第 7-9 行：cosim testlist 需要先有 `build/libcosim.so`。如果 `SPIKE_INSTALL`
  不存在，`make cosim` 会按 `Makefile:L455-L459` 报错。

接口关系：

* 被调用：用户 shell、deprecated `make run`、`make nightly`、`make weekly`、
  `make run_regress`。
* 调用：`compile`、`run_regress.py`。
* 共享状态：`TESTLIST_PATH`、`OUT`、`build/regression`、coverage 数据库。

§8  sign-off 快速路径
---------------------

当前顶层 sign-off 入口是 `make signoff`，profile 用 `PROFILE` 变量选择。`quick`
profile 在 `signoff.py` 中只包含 `smoke` 和 `directed` 两个 stage。

关键代码（`signoff.py:L37-L44`）：

.. code-block:: python

   PROFILE_STAGES = {
       "quick": ["smoke", "directed"],
       "cosim": ["smoke", "cosim"],
       "riscvdv_smoke": ["riscvdv"],
       "nightly": ["smoke", "directed", "cosim", "riscvdv"],
       "full": ["smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                "compliance", "formal", "syn"],
   }

逐段解释：

* 第 37-39 行：`quick`、`cosim`、`riscvdv_smoke` 是较小 profile。`quick`
  不包含 cosim、formal、syn 或 compliance。
* 第 41-43 行：`full` 包含 9 个 stage：`smoke`、`directed`、`cosim`、
  `riscvdv`、`lint`、`csr_unit`、`compliance`、`formal`、`syn`。
* 这些 stage 名直接被 `resolve_stages()` 和 `build_stage_cmd()` 使用；文档引用 profile
  时必须按这里的大小写和拼写写。

关键代码（`Makefile:L607-L624`）：

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

逐段解释：

* 第 607-614 行：Makefile 把 `PROFILE`、`SIMULATOR`、`SEED`、`PARALLEL`
  和 `SIGNOFF_OUT` 逐项传给 `signoff.py`。当前入口只使用 `PROFILE` 表示 profile。
* 第 615-618 行：`GATE_ONLY=1` 展开为 `--gate-only`；`SIGNOFF_ITERATIONS`
  非空时展开为 `--iterations`；`LEC_KNOWN_LIMITED=1` 和 `LEC_BLOCKLEVEL=1`
  分别控制 LEC 的 known-limited 处理和 block-level LEC 摘要路径。

推荐命令：

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh
   make signoff PROFILE=quick PARALLEL=4 COV=0 SIGNOFF_OUT=build/signoff_quick

逐段解释：

* 第 3 行：`PROFILE=quick` 对应 `signoff.py:L38` 的 `smoke` 与 `directed`
  stage。`SIGNOFF_OUT` 显式写出可以避免覆盖默认 `build/signoff`。
* `COV=0` 表示 quick smoke/directed 路径不要求覆盖率输入。full release gate
  是否要求 coverage 由 `signoff.py` 的 profile 和参数检查共同决定。

接口关系：

* 被调用：用户 shell、`make demo`、deprecated `make signoff_quick`。
* 调用：`signoff.py`、间接 `run_regress.py`、`make lint`、`make formal`、
  `make syn` 等 stage 命令。
* 共享状态：`build/signoff*` 输出目录、stage result replay 输入、
  `syn/build/lec_summary.txt`、coverage dashboard。

§9  full sign-off 与 replay
----------------------------

full sign-off 是当前 release gate 的主路径。顶层 `make signoff` 可以启动 full
profile，`make signoff_replay` 则从既有 stage 结果目录复演 gate，不重新跑测试。

关键代码（`README.md:L153-L172`）：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/signoff.py \
     --profile full \
     --gate-only \
     --output build/signoff_replay \
     --stage-result smoke=build/demo/runs/smoke \

逐段解释：

* 第 153-160 行：replay 直接调用 `signoff.py --profile full --gate-only`，
  输出目录建议使用 `build/signoff_replay`。
* 第 161-172 行：每个 `--stage-result` 把 stage 名映射到既有结果目录；coverage
  门限用 `--min-line-coverage`、`--min-toggle-coverage` 和
  `--min-functional-coverage` 传入。

关键代码（`Makefile:L626-L647`）：

.. code-block:: makefile

   signoff_replay:
   	@echo "=== [signoff_replay] 数据源=$(STAGE_DATA_DIR) ==="
   	@if [ ! -d "$(STAGE_DATA_DIR)/runs" ]; then \
   	  echo "ERROR: STAGE_DATA_DIR=$(STAGE_DATA_DIR) 不存在或缺 runs/ 子目录。"; \
    echo "       先跑 'make demo' 攒数据，或显式传入已有 stage 结果目录。"; \
   	  exit 1; \
   	fi
   	python3 $(SCRIPTS_DIR)/signoff.py \
   	  --profile full --gate-only \
   	  --output $(SIGNOFF_REPLAY_OUT) \
   	  --stage-result smoke=$(STAGE_DATA_DIR)/runs/smoke \

逐段解释：

* 第 626-632 行：`signoff_replay` 先检查 `$(STAGE_DATA_DIR)/runs` 是否存在；
  不存在就退出并提示先跑 `make demo` 或显式传入已有 stage 结果目录。
* 第 633-641 行：recipe 固定使用 `--profile full --gate-only`，并逐个传入
  `smoke`、`directed`、`cosim`、`riscvdv`、`csr_unit`、`compliance` 的结果目录。
* 第 642-646 行：LEC、known-limited、coverage 门限和 warning 策略也在 replay
  路径中传给 `signoff.py`。这条路径的目的就是复评 gate，而不是重跑 stage。

推荐命令：

.. code-block:: bash

   # 当前顶层 Makefile 使用 PROFILE
   make signoff PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1 \
     LEC_BLOCKLEVEL=1 COV=1 SIGNOFF_OUT=build/signoff

   # 使用现有 stage 结果复演 full gate
   make signoff_replay STAGE_DATA_DIR=build/demo \
     SIGNOFF_REPLAY_OUT=build/signoff_replay

逐段解释：

* 第 1-3 行：这是 README full sign-off 示例的当前 Makefile 写法。关键修正是
  `PROFILE=full`。
* 第 5-7 行：`signoff_replay` 从 `STAGE_DATA_DIR` 读取 `runs/` 子目录，并把报告写到
  `SIGNOFF_REPLAY_OUT`。该命令不重新启动 smoke、directed 或 cosim 仿真。

接口关系：

* 被调用：release replay、CI gate 重评估、演示流程。
* 调用：`signoff.py --gate-only`、已有 stage result 目录、LEC summary、
  coverage dashboard。
* 共享状态：`<stage-data>/runs/*`、`build/signoff_replay/`、
  `syn/build/lec_summary.txt`。

§10  deprecated alias 与替代命令
---------------------------------

当前 Makefile 保留旧 target 作为兼容层，但会打印 `[deprecated]` 提示并转发到新入口。
新文档和新 CI 应优先使用新入口。

关键代码（`Makefile:L767-L807`）：

.. code-block:: makefile

   # ============================================================
   # Deprecated aliases — 兼容旧 CI / 文档；输出 [deprecated] 提示并转发
   # ============================================================
   run:
   	@echo "[deprecated] 'make run' → 'make regress TEST=$(TEST) SEED=$(SEED)'"
   	@$(MAKE) --no-print-directory regress TEST=$(TEST) SEED=$(SEED)

   gen: | $(BUILD_DIR)
   	@echo "[deprecated] 'make gen' → 现在 signoff 自动调用 riscv-dv generation；如需单跑："
   	@mkdir -p $(OUT_DIR)
   	python3 $(SCRIPTS_DIR)/run_instr_gen.py \
   	  --riscv-dv-dir $(RISCV_DV_DIR) \
   	  --work-dir $(OUT_DIR) \

逐段解释：

* 第 767-772 行：`make run` 仍存在，但只是打印 deprecated 提示并转发到
  `make regress TEST=$(TEST) SEED=$(SEED)`。因此快速启动不应再推荐
  `make run TEST=...` 作为主命令。
* 第 774-783 行：`make gen` 也保留兼容入口；提示说明 sign-off 现在会自动调用
  riscv-dv generation。需要单跑时，它直接调用 `run_instr_gen.py`。

关键代码（`Makefile:L785-L807`）：

.. code-block:: makefile

   nightly:
   	@echo "[deprecated] 'make nightly' → 'make regress PARALLEL=$(PARALLEL)'"
   	@$(MAKE) --no-print-directory regress PARALLEL=$(PARALLEL)

   weekly:
   	@echo "[deprecated] 'make weekly' → 'make regress PARALLEL=$(PARALLEL) ITERATIONS=5'"
   	@$(MAKE) --no-print-directory regress PARALLEL=$(PARALLEL) ITERATIONS=5

   run_regress:
   	@echo "[deprecated] 'make run_regress' → 'make regress TESTLIST=$(TEST_LIST)'"
   	@$(MAKE) --no-print-directory regress TESTLIST=$(if $(filter directed,$(TEST_LIST)),directed,riscvdv)

   signoff_quick:
   	@echo "[deprecated] 'make signoff_quick' → 'make signoff PROFILE=quick'"
   	@$(MAKE) --no-print-directory signoff PROFILE=quick SIGNOFF_OUT=$(BUILD_DIR)/signoff_quick

逐段解释：

* 第 785-791 行：旧的 nightly/weekly 入口都转到 `make regress`，区别是 weekly
  固定 `ITERATIONS=5`。
* 第 793-795 行：旧 `run_regress` target 根据 `TEST_LIST` 转成当前的 `TESTLIST`。
  注意这里旧变量名是 `TEST_LIST`，当前推荐变量是 `TESTLIST`。
* 第 797-799 行：`signoff_quick` 转成 `make signoff PROFILE=quick`。这证明 quick
  profile 的当前写法是 `PROFILE=quick`。
* 第 801-807 行：`signoff_gate` 和 `signoff_with_cleanup` 分别转成
  `GATE_ONLY=1` 和 `CLEANUP=1` 的 `make signoff`。

替代表：

.. list-table::
   :header-rows: 1
   :widths: 36 64

   * - 旧入口
     - 当前推荐入口
   * - `make run TEST=<name> SEED=<n>`
     - `make regress TEST=<name> SEED=<n>`
   * - `make nightly`
     - `make regress PARALLEL=<n>`
   * - `make weekly`
     - `make regress PARALLEL=<n> ITERATIONS=5`
   * - `make run_regress TEST_LIST=directed`
     - `make regress TESTLIST=directed`
   * - `make signoff_quick`
     - `make signoff PROFILE=quick`
   * - `make signoff_gate`
     - `make signoff GATE_ONLY=1`
   * - `make signoff_with_cleanup`
     - `make signoff CLEANUP=1`

接口关系：

* 被调用：旧 CI、旧文档命令、局部 `dv/uvm/core_eh2/Makefile`。
* 调用：`regress`、`signoff`、`run_instr_gen.py`。
* 共享状态：与转发后的新 target 完全一致。

§11  局部 UVM 目录入口
----------------------

在 `dv/uvm/core_eh2` 目录下也有一个本地开发 Makefile。它不是独立实现编译和回归，
而是 `cd` 回仓库根并调用顶层 Makefile。

关键代码（`dv/uvm/core_eh2/Makefile:L1-L15`）：

.. code-block:: makefile

   # EH2 Core UVM - Local Development Makefile
   #
   # Convenience targets for working within dv/uvm/core_eh2.
   # Delegates to the top-level Makefile for actual simulation.
   #
   # Usage:
   #   make help       - Show available targets
   #   make compile    - Compile the testbench
   #   make smoke      - Run smoke test
   #   make run        - Run a single test (TEST=, SEED=)
   #   make cov        - Collect coverage
   #   make signoff    - Run sign-off gate
   #   make lint       - Run lint checks on UVM sources
   #   make clean      - Clean build artifacts

逐段解释：

* 第 1-4 行：该文件明确定义为 local development convenience Makefile，并说明实际仿真委托给顶层
  Makefile。
* 第 6-14 行：帮助注释列出 compile、smoke、run、cov、signoff、lint、clean 等局部入口。
  这些入口服务于在 `dv/uvm/core_eh2` 内工作的人，不改变顶层 target 的真实行为。

关键代码（`dv/uvm/core_eh2/Makefile:L67-L95`）：

.. code-block:: makefile

   compile:
   	cd $(PROJ_ROOT) && $(MAKE) compile SIMULATOR=$(SIMULATOR) CONFIG=$(CONFIG)

   run: compile
   	cd $(PROJ_ROOT) && $(MAKE) run TEST=$(TEST) SEED=$(SEED) \
   	  SIMULATOR=$(SIMULATOR) BINARY=$(BINARY) WAVES=$(WAVES) COV=$(COV) \
   	  RTL_TEST=$(RTL_TEST) VERBOSITY=$(VERBOSITY)

   gen:
   	cd $(PROJ_ROOT) && $(MAKE) gen TEST=$(TEST) SEED=$(SEED) \
   	  ITERATIONS=$(ITERATIONS)

   smoke:
   	cd $(PROJ_ROOT) && $(MAKE) smoke SIMULATOR=$(SIMULATOR)

逐段解释：

* 第 67-68 行：局部 `compile` 回到 `$(PROJ_ROOT)` 后执行顶层 `make compile`。
* 第 70-73 行：局部 `run` 依赖局部 `compile`，然后调用顶层 `make run`。由于顶层
  `make run` 在默认分支中已经是 deprecated alias，新 quick start 不应把局部
  `make run` 当作首选路径。
* 第 75-80 行：局部 `gen` 和 `smoke` 同样只是回到仓库根转发。局部 `smoke`
  不透传 `NO_COSIM`；如需无 Spike 编译路径，应直接在仓库根执行顶层命令。

关键代码（`dv/uvm/core_eh2/Makefile:L88-L95`）：

.. code-block:: makefile

   signoff:
   	cd $(PROJ_ROOT) && $(MAKE) signoff SIMULATOR=$(SIMULATOR) PARALLEL=$(PARALLEL) \
   	  SIGNOFF_ITERATIONS=$(SIGNOFF_ITERATIONS) COV=$(COV) WAVES=$(WAVES) \
   	  LEC_BLOCKLEVEL=$(LEC_BLOCKLEVEL) LEC_SUMMARY_PATH=$(LEC_SUMMARY_PATH)

   signoff_quick:
   	cd $(PROJ_ROOT) && $(MAKE) signoff_quick SIMULATOR=$(SIMULATOR) PARALLEL=$(PARALLEL)

逐段解释：

* 第 88-91 行：局部 `signoff` 转发到顶层 `signoff`，但没有透传 `PROFILE`，
  所以会使用顶层默认 `PROFILE=full`，除非调用者通过其他方式扩展变量传递。
* 第 93-94 行：局部 `signoff_quick` 仍调用顶层 deprecated alias。当前推荐写法仍是在仓库根执行
  `make signoff PROFILE=quick`。

接口关系：

* 被调用：在 `dv/uvm/core_eh2` 子目录工作的开发者。
* 调用：仓库根顶层 `Makefile`。
* 共享状态：与顶层 Makefile 一致，输出仍落在仓库根 `build/`。

§12  常见故障边界
------------------

本节只列当前源码能直接证明的故障边界，不推测工具安装方式。

Spike DPI 缺失：

.. code-block:: bash

   make cosim
   # 若 SPIKE_INSTALL 不存在，Makefile 会提示：
   # ERROR: SPIKE_INSTALL=<path> 不存在。
   # 先 build spike-cosim，或设 SPIKE_DIR=<path>，或传 NO_COSIM=1 跳过 cosim。

逐段解释：

* `make cosim` 只构建 `build/libcosim.so`。当 `$(SPIKE_INSTALL)` 目录不存在时，
  `Makefile:L455-L459` 会退出。
* 若当前任务只是 smoke 或 directed RTL-only 调试，可以使用
  `make compile NO_COSIM=1` 和 `+disable_cosim=1` 路径；如果要跑 `TESTLIST=cosim`，
  仍需要先准备 `build/libcosim.so`。

sign-off precheck 失败：

.. code-block:: python

   sim_tool = {"vcs": "vcs", "xlm": "xrun", "questa": "vsim"}[simulator]
   simv_exists = (EH2_ROOT / "build" / "simv").exists()
   add("simulator_or_simv", simv_exists or tool_exists(sim_tool),
       "found build/simv" if simv_exists else sim_tool)

   if any(stage in stages for stage in ("directed", "cosim", "riscvdv")):
       gcc_prefix = resolve_gcc_prefix()
       add("riscv_gcc", tool_exists(gcc_prefix + "-gcc"), gcc_prefix + "-gcc")
       add("riscv_objcopy", tool_exists(gcc_prefix + "-objcopy"),
           gcc_prefix + "-objcopy")

逐段解释：

* 第 1-4 行来自 `signoff.py:L162-L165`。precheck 接受两种情况：已有
  `build/simv`，或者所选 simulator 命令在 `PATH` 中可见。
* 第 6-10 行来自 `signoff.py:L167-L171`。当 stage 包含 `directed`、`cosim`
  或 `riscvdv` 时，precheck 要求能找到 `riscv32-unknown-elf-gcc` 和
  `riscv32-unknown-elf-objcopy`。
* `resolve_gcc_prefix()` 会优先检查环境变量 `GCC_PREFIX` 下的
  `bin/riscv32-unknown-elf-gcc`；这就是 `source env.sh` 对 sign-off 的直接意义。

旧命令仍能跑但不推荐：

.. code-block:: bash

   make run TEST=riscv_arithmetic_basic_test SEED=1
   make signoff_quick

逐段解释：

* 这两个命令在当前 Makefile 中仍存在，但都会打印 `[deprecated]` 并转发。
* 新文档和新脚本应分别改为 `make regress TEST=... SEED=...` 与
  `make signoff PROFILE=quick`。

接口关系：

* 被调用：交互式排障、CI 日志分析。
* 调用：Makefile 错误分支、`signoff.py` precheck。
* 共享状态：`PATH`、`GCC_PREFIX`、`build/simv`、`build/libcosim.so`。

§13  参考资料
---------------

* 关联章节：:ref:`build_flow`、:ref:`regression_flow`、:ref:`signoff_flow`、
  :ref:`scripts_reference`、:ref:`configuration`。
* 关联 ADR：:ref:`adr-0011`、:ref:`adr-0013`、:ref:`adr-0016`。
* 源文件绝对路径：

  * `/home/host/eh2-veri/README.md`
  * `/home/host/eh2-veri/env.sh`
  * `/home/host/eh2-veri/env.mk`
  * `/home/host/eh2-veri/Makefile`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/Makefile`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
