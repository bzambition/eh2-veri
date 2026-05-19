.. _scripts_reference:
.. _06_flows/scripts_reference:

脚本参考入口
============

:status: draft
:source: Makefile, dv/uvm/core_eh2/wrapper.mk, dv/uvm/core_eh2/scripts/\*.py, dv/uvm/core_eh2/scripts/\*.mk
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本章从 flow 和 CLI 入口角度解释 EH2-Veri 脚本体系：谁调用脚本、哪些参数构成
脚本边界、metadata staged mode 如何把单个 test 转成 compile/run/check/collect
流水线。脚本内部函数逐段实现见 :doc:`../appendix_f_scripts/core_eh2_scripts`；
本章只保留必要代码片段，用于建立入口、参数语义和互调关系。

§1 入口分层
--------------------------------------------------------------------------------

EH2-Veri 当前同时保留两类脚本入口：

* 顶层 `Makefile` 的直接入口：`gen`、`smoke`、`nightly`、`weekly`、`regress`、
  `run_regress`、`signoff`、`signoff_gate`、`html_report`。
* `GOAL` 非空时的 staged 入口：顶层 `Makefile` 先调用 `metadata.py` 创建 metadata，
  再委托 `dv/uvm/core_eh2/wrapper.mk` 分阶段调用脚本。

.. code-block:: text

   top Makefile
      |
      +-- direct targets
      |     +-- run_instr_gen.py
      |     +-- run_regress.py
      |     +-- signoff.py
      |     +-- gen_html_report.py
      |
      +-- run GOAL=<wrapper target>
            |
            +-- metadata.py --op create_metadata
            +-- wrapper.mk
                  |
                  +-- render_config_template.py
                  +-- build_instr_gen.py
                  +-- run_instr_gen.py
                  +-- compile_test.py
                  +-- run_rtl.py
                  +-- check_logs.py
                  +-- get_fcov.py / merge_cov.py
                  +-- collect_results.py
                  +-- signoff.py

设计边界：

* `metadata.py` 是 staged mode 的状态中心，负责把 Make 变量、testlist 和目录路径
  固化到 metadata 目录。
* `run_regress.py` 是直接 regression CLI，参数面向用户和顶层 Make target。
* `wrapper.mk` 是 Ibex-style staged dependency graph，参数面向单个 `TEST.SEED`
  目录。
* `signoff.py` 既能执行 stage，也能做 `--gate-only` 评估。
* `gen_html_report.py` 只读取 sign-off JSON、coverage dashboard 和 runs 目录，不启动
  仿真。

§2 顶层 ``Makefile`` 入口
--------------------------------------------------------------------------------

职责：把用户的 Make 变量转成 Python CLI 参数，或通过 staged flow 委托给
`wrapper.mk`。

§2.1 ``run`` target — metadata staged 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``Makefile:L54-L66``）：

.. code-block:: bash

   export PYTHONPATH := $(shell cd dv/uvm/core_eh2 && python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')

   .PHONY: run
   run:
   	+@env PYTHONPATH=$(PYTHONPATH) python3 dv/uvm/core_eh2/scripts/metadata.py \
   	  --op "create_metadata" \
   	  --dir-metadata $(METADATA-DIR) \
   	  --dir-out $(OUT-DIR) \
   	  --args-list "\
   	  SEED=$(SEED) WAVES=$(WAVES) COV=$(COV) SIMULATOR=$(SIMULATOR) \
   	  ISS=$(ISS) TEST=$(TEST) VERBOSE=$(VERBOSE) ITERATIONS=$(ITERATIONS) \
   	  SIGNATURE_ADDR=$(SIGNATURE_ADDR) CONFIG=$(CONFIG) RTL_TEST=$(RTL_TEST) \
   	  SIM_OPTS=$(SIM_OPTS) GEN_OPTS=$(GEN_OPTS)"

逐段解释：

* 第 L54 行：顶层 `PYTHONPATH` 不是手写常量，而是执行
  `scripts.setup_imports.get_pythonpath()` 得到。
* 第 L58-L61 行：`run` target 以 `metadata.py --op create_metadata` 开始，
  `--dir-metadata` 和 `--dir-out` 由 Make 变量提供。
* 第 L62-L66 行：`--args-list` 把 seed、waves、coverage、simulator、ISS、test、
  iterations、signature address、config、RTL test、sim opts、gen opts 作为
  Make-style `KEY=VALUE` 字符串传给 `metadata.py`。

接口关系：

* 被调用：用户执行 `make run GOAL=<target>`。
* 调用：`metadata.py`。
* 共享状态：写 `$(METADATA-DIR)`，后续 `wrapper.mk` 读取。

关键代码（``Makefile:L67-L74``）：

.. code-block:: bash

   	+@$(MAKE) -C dv/uvm/core_eh2 --file wrapper.mk \
   	  OUT-DIR=$(abspath $(OUT-DIR)) \
   	  METADATA-DIR=$(abspath $(METADATA-DIR)) \
   	  PRJ_DIR=$(CURDIR) \
   	  SIMULATOR=$(SIMULATOR) \
   	  TEST=$(TEST) \
   	  SEED=$(SEED) \
   	  ITERATIONS=$(ITERATIONS) \

逐段解释：

* 第 L67 行：metadata 创建后，顶层 Make 进入 `dv/uvm/core_eh2`，指定
  `wrapper.mk`。
* 第 L68-L74 行：传给 wrapper 的路径都使用 `abspath` 或当前目录变量，避免 wrapper
  在子目录执行时丢失路径上下文。

接口关系：

* 被调用：`run` target 的第二阶段。
* 调用：`make -C dv/uvm/core_eh2 --file wrapper.mk`。
* 共享状态：向 `wrapper.mk` 传递 `OUT-DIR`、`METADATA-DIR`、`PRJ_DIR` 等 Make 变量。

§2.2 直接 regression 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``Makefile:L366-L387``）：

.. code-block:: bash

   gen: | $(BUILD_DIR)
   	@echo "=== Generating riscv-dv instructions: $(TEST) ==="
   	@mkdir -p $(OUT_DIR)
   	python3 $(SCRIPTS_DIR)/run_instr_gen.py \
   	  --riscv-dv-dir $(RISCV_DV_DIR) \
   	  --work-dir $(OUT_DIR) \
   	  --test $(TEST) \
   	  --gen-opts "$(GEN_OPTS)" \
   	  --seed $(SEED) \
   	  --iterations $(ITERATIONS)
   	@echo "=== Generation complete ==="

   smoke: compile
   	@echo "=== Running smoke tests ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --test riscv_arithmetic_basic_test \
   	  --simulator $(SIMULATOR) \
   	  --seed 1 \
   	  --output $(BUILD_DIR)/smoke

逐段解释：

* 第 L366-L375 行：`gen` target 直接调用 `run_instr_gen.py`，必须给出 riscv-dv 根目录、
  work dir、test、gen opts、seed 和 iterations。
* 第 L381-L387 行：`smoke` target 不通过 testlist，而是调用 `run_regress.py --test`
  跑单个 `riscv_arithmetic_basic_test`，输出到 `build/smoke`。

接口关系：

* 被调用：用户执行 `make gen` 或 `make smoke`。
* 调用：`run_instr_gen.py`、`run_regress.py`。
* 共享状态：读 `$(RISCV_DV_DIR)`、`$(TEST)`、`$(SIMULATOR)`，写 `$(OUT_DIR)` 或
  `$(BUILD_DIR)/smoke`。

关键代码（``Makefile:L393-L435``）：

.. code-block:: bash

   nightly: compile
   	@echo "=== Running nightly regression ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \
   	  --iterations 1 \
   	  --parallel $(PARALLEL) \
   	  --output $(BUILD_DIR)/nightly \
   	  $(if $(filter 1,$(COV)),--coverage,)
   	@echo "=== Nightly regression complete ==="

   weekly: compile
   	@echo "=== Running weekly regression ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \

逐段解释：

* 第 L393-L401 行：`nightly` 使用 riscv-dv extension testlist，iterations 固定为 1，
  并按 `COV=1` 条件追加 `--coverage`。
* 第 L407-L414 行：`weekly` 使用同一 testlist，但 iterations 固定为 5。
* 第 L420-L426 行：`regress` 使用 `$(ITERATIONS)` 和 `$(PARALLEL)`。
* 第 L428-L435 行：`run_regress` 根据 `TEST_LIST=directed` 在 directed testlist 和
  riscv-dv testlist 之间选择，输出目录可由 `OUT` 覆盖。

接口关系：

* 被调用：用户执行 `make nightly`、`make weekly`、`make regress` 或
  `make run_regress`。
* 调用：`run_regress.py`。
* 共享状态：读 testlist、simulator、iterations、parallel、coverage 开关。

§2.3 sign-off 和 HTML 报告入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``Makefile:L1069-L1091``）：

.. code-block:: bash

   signoff:
     @if [ "$(SIMULATOR)" != "vcs" ] && [ "$(SIMULATOR)" != "nc" ]; then \
       echo "ERROR: signoff 仅支持 SIMULATOR=vcs (默认) 或 SIMULATOR=nc。"; \
       exit 1; \
     fi
     @if [ "$(SIMULATOR)" = "nc" ]; then \
       echo "[signoff] 注意：当前用 NC simulator (备选)。VCS 是 sign-off 默认。"; \
     fi
     @$(if $(filter 1,$(GATE_ONLY)),,$(MAKE) --no-print-directory asm)
     @$(if $(filter 1,$(GATE_ONLY)),,$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(SIGNOFF_OUT) COV=$(COV))
   	python3 $(SCRIPTS_DIR)/signoff.py \
   	  --profile $(PROFILE) \
   	  --simulator $(SIMULATOR) \
   	  --seed $(SEED) \
   	  --parallel $(PARALLEL) \
   	  --output $(SIGNOFF_OUT) \
   	  $(if $(filter 1,$(GATE_ONLY)),--gate-only,) \
   	  $(if $(SIGNOFF_ITERATIONS),--iterations $(SIGNOFF_ITERATIONS),) \
   	  $(SIGNOFF_LEC_OPTS) \
   	  $(if $(filter 1,$(COV)),--coverage --min-line-coverage $(SIGNOFF_MIN_LINE_COV) --min-functional-coverage $(SIGNOFF_MIN_FUNCTIONAL_COV),) \
   	  $(if $(filter 1,$(SIGNOFF_ALLOW_WARNINGS)),--allow-warnings,) \
   	  $(if $(filter 1,$(WAVES)),--waves,) \
   	  $(SIGNOFF_OPTS)

逐段解释：

* 第 L1069-L1076 行：`signoff` 入口强制 `SIMULATOR=vcs`，并把 NC 限定为
  `make smoke|regress SIMULATOR=nc WAVES=1` 单测波形用途。
* 第 L1078-L1079 行：非 `GATE_ONLY` 时自动执行 `asm` 和 `compile`，compile 写入
  `BUILD_SUBDIR=$(SIGNOFF_OUT)`。
* 第 L1081-L1091 行：`PROFILE`、seed、parallel、LEC、coverage、warnings 和 waves
  均通过 Make 变量映射到 `signoff.py` 参数。coverage gate 默认使用
  `SIGNOFF_MIN_LINE_COV=65` 和 `SIGNOFF_MIN_FUNCTIONAL_COV=40`。

接口关系：

* 被调用：用户执行 `make signoff` 或 `make signoff_with_cleanup`。
* 调用：`signoff.py`、`clean_workspace.sh`。
* 共享状态：读 sign-off 相关 Make 变量，写 `$(SIGNOFF_OUT)`。

关键代码（``Makefile:L1095-L1116``）：

.. code-block:: bash

   signoff_replay:
   	python3 $(SCRIPTS_DIR)/signoff.py \
   	  --profile full --gate-only \
   	  --simulator $(SIMULATOR) \
   	  --output $(SIGNOFF_REPLAY_OUT) \
   	  --stage-result smoke=$(STAGE_DATA_DIR)/runs/smoke \
   	  --stage-result directed=$(STAGE_DATA_DIR)/runs/directed \
   	  --stage-result cosim=$(STAGE_DATA_DIR)/runs/cosim \
   	  --stage-result riscvdv=$(STAGE_DATA_DIR)/runs/riscvdv \
   	  --stage-result csr_unit=$(STAGE_DATA_DIR)/runs/csr_unit \
   	  --stage-result compliance=$(STAGE_DATA_DIR)/runs/compliance \
   	  $(if $(filter 1,$(LEC_BLOCKLEVEL)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),) \
   	  --coverage --min-line-coverage $(SIGNOFF_MIN_LINE_COV) --min-functional-coverage $(SIGNOFF_MIN_FUNCTIONAL_COV) \
   	  $(if $(wildcard $(STAGE_DATA_DIR)/cov_merged/dashboard.txt),--coverage-path $(STAGE_DATA_DIR)/cov_merged/dashboard.txt,) \
   	  --allow-warnings \
   	  $(SIGNOFF_OPTS)

逐段解释：

* replay 入口固定 `--profile full --gate-only`，通过 `--stage-result` 绑定已有
  stage 目录。
* LEC summary、coverage dashboard 和 threshold 仍由 Make 变量控制，避免 replay
  使用过时硬编码路径。
* HTML 报告已并入 `signoff.py` 默认行为；保留的 `html_report` target 是 deprecated
  alias，只在手工重生 HTML 时使用。

接口关系：

* 被调用：用户执行 `make signoff_quick`、`make signoff_gate`、`make html_report`。
* 调用：`signoff.py`、`gen_html_report.py`。
* 共享状态：读取 sign-off JSON、coverage dashboard 和 runs 目录。

§3 staged wrapper 调用链
--------------------------------------------------------------------------------

职责：把 metadata 生成的 test matrix 转成 Make dependency graph，按 test.seed
粒度执行 instruction generation、compile、RTL simulation、log check、coverage 和
result collection。

§3.1 config 渲染与 generator build
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/wrapper.mk:L69-L85``）：

.. code-block:: bash

   core_config: $(METADATA-DIR)/core.config.stamp
   $(METADATA-DIR)/core.config.stamp: scripts/render_config_template.py | $(BUILD-DIR) $(METADATA-DIR)
   	@echo Generating EH2 riscv-dv core configuration
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/render_config_template.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    riscv_dv_extension/riscv_core_setting.tpl.sv \
   	    > riscv_dv_extension/riscv_core_setting.sv
   	@touch $@

   instr_gen_build: $(METADATA-DIR)/instr.gen.build.stamp
   $(METADATA-DIR)/instr.gen.build.stamp: core_config scripts/build_instr_gen.py | $(BUILD-DIR)
   	@echo Building randomized test generator
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/build_instr_gen.py \
   	    --dir-metadata $(METADATA-DIR)

逐段解释：

* 第 L69-L77 行：`core_config` 调用 `render_config_template.py`，输入 metadata 和
  riscv-dv core setting 模板，stdout 重定向到 `riscv_core_setting.sv`。
* 第 L79-L85 行：`instr_gen_build` 依赖 `core_config`，然后调用
  `build_instr_gen.py --dir-metadata`。

接口关系：

* 被调用：`instr_gen_run` 之前的 staged dependency。
* 调用：`render_config_template.py`、`build_instr_gen.py`。
* 共享状态：读 metadata，写 riscv-dv core setting 和 generator build stamp。

§3.2 test 生成、编译和仿真
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/wrapper.mk:L87-L122``）：

.. code-block:: bash

   instr_gen_run: $(riscvdv-test-asms)
   $(riscvdv-test-asms): $(TESTS-DIR)/%/$(asm-stem): instr_gen_build scripts/run_instr_gen.py
   	@echo Running randomized test generator for $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/run_instr_gen.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    --test-dot-seed $*
   	$(verb)cp $$(find $(@D) -name '*.S' | sort | head -n 1) $@

   compile_riscvdv_tests: $(riscvdv-test-bins)
   $(riscvdv-test-bins): $(TESTS-DIR)/%/$(bin-stem): $(TESTS-DIR)/%/$(asm-stem) scripts/compile_test.py
   	@echo Compiling riscv-dv test $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/compile_test.py \
   	    --dir-metadata $(METADATA-DIR) \

逐段解释：

* 第 L87-L94 行：每个 riscv-dv `TEST.SEED` 目录先调用 `run_instr_gen.py`，然后把生成
  目录中的第一份 `.S` 拷贝到目标 assembly path。
* 第 L96-L102 行：riscv-dv test binary 由 `compile_test.py --dir-metadata
  --test-dot-seed` 生成。
* 第 L104-L110 行：directed test binary 也使用同一个 `compile_test.py` 入口。
* 第 L112-L122 行：RTL simulation 先触发 `rtl_tb_compile`，再调用
  `run_rtl.py --dir-metadata --test-dot-seed`，最后拷贝 simulator log 到 wrapper 目标。

接口关系：

* 被调用：`compile_riscvdv_tests`、`compile_directed_tests`、`rtl_sim_run`。
* 调用：`run_instr_gen.py`、`compile_test.py`、`run_rtl.py`。
* 共享状态：读 metadata 中的 `TEST.SEED`、binary path、simulator、UVM test class。

§3.3 check、coverage、collect 和 signoff
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/wrapper.mk:L124-L154``）：

.. code-block:: bash

   check_logs: $(comp-results)
   $(comp-results): $(TESTS-DIR)/%/$(trr-stem): $(TESTS-DIR)/%/$(rtl-sim-logfile) scripts/check_logs.py
   	@echo Checking RTL log for $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/check_logs.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    --test-dot-seed $*

   riscv_dv_fcov:
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/get_fcov.py --dir-metadata $(METADATA-DIR) --simulator $(SIMULATOR)

   merge_cov:
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/merge_cov.py --dir-metadata $(METADATA-DIR)

   collect_results: $(comp-results)

逐段解释：

* 第 L124-L130 行：`check_logs` 对每个 test.seed 调用 `check_logs.py`，写 result/TRR
  数据。
* 第 L132-L134 行：functional coverage 收集调用 `get_fcov.py --dir-metadata
  --simulator`。
* 第 L136-L138 行：coverage merge 调用 `merge_cov.py --dir-metadata`；源码中的
  `merge_cov.py` 当前 standalone 参数是 `--dirs/--output`，无参数时打印 metadata mode
  提示并返回 0。
* 第 L140-L154 行：`collect_results` 调用 `collect_results.py --dir-metadata
  --output-dir`；`signoff` 调用 `signoff.py --profile --simulator --seed --parallel
  --output`。

接口关系：

* 被调用：staged regression 后半段。
* 调用：`check_logs.py`、`get_fcov.py`、`merge_cov.py`、`collect_results.py`、
  `signoff.py`。
* 共享状态：读 metadata、test result、coverage 数据，写 summary/report/signoff。

§4 metadata CLI
--------------------------------------------------------------------------------

职责：提供 Ibex-style `--op create_metadata` 和 `--op print_field` 两个入口。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L476-L502``）：

.. code-block:: python

   def main(argv=None) -> int:
       """Entry point compatible with Ibex's metadata.py --op interface."""
       parser = argparse.ArgumentParser(description="EH2 regression metadata helper")
       parser.add_argument("--op", required=True,
                           choices=["create_metadata", "print_field"])
       parser.add_argument("--dir-metadata", required=True)
       parser.add_argument("--dir-out", default="")
       parser.add_argument("--args-list", default="")
       parser.add_argument("--field", default="")
       args = parser.parse_args(argv)

       if args.op == "create_metadata":
           if not args.dir_out:
               parser.error("--dir-out is required for create_metadata")
           create_metadata(args.dir_metadata, args.dir_out, args.args_list)

逐段解释：

* 第 L478-L485 行：CLI 参数只有 5 个：`--op`、`--dir-metadata`、`--dir-out`、
  `--args-list`、`--field`。
* 第 L487-L491 行：`create_metadata` 必须提供 `--dir-out`，然后调用
  `create_metadata()`。
* 第 L492-L496 行：`print_field` 必须提供 `--field`，然后打印 metadata 字段。

接口关系：

* 被调用：顶层 `Makefile run`、`get_meta.mk`。
* 调用：`create_metadata()`、`print_field()`。
* 共享状态：读写 metadata directory。

§5 regression CLI
--------------------------------------------------------------------------------

职责：`run_regress.py` 是用户和 Makefile 的直接回归入口，负责 test selection、
simulator 选择、并行度、coverage/waves 选项和输出目录。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L447-L498``）：

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

逐段解释：

* 第 L447-L456 行：CLI help 中给出 testlist、single test 和 parallel regression
  三种示例。
* 第 L459-L463 行：test selection 参数包括 `--testlist`、`--test`、`--iterations`、
  `--seed`。
* 第 L465-L478 行：test configuration 参数包括 `--rtl-test`、`--gen-opts`、
  `--sim-opts`、`--binary`、`--disable-cosim`、`--coverage`、`--waves`、
  `--fail-on-warnings`。

接口关系：

* 被调用：顶层 `smoke/nightly/weekly/regress/run_regress` target 和用户直接 CLI。
* 调用：`run_regression(args)`。
* 共享状态：读取 testlist 或 single-test 参数，写 output directory。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L480-L498``）：

.. code-block:: python

       # Simulator
       parser.add_argument("--simulator", default="vcs",
                           choices=["vcs", "xlm", "questa"],
                           help="Simulator to use")

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

* 第 L481-L483 行：`--simulator` 只能是 `vcs`、`xlm`、`questa`。
* 第 L486-L490 行：`--output` 指定输出目录，`--parallel` 指定并行 test 数。
* 第 L494-L495 行：`--testlist` 和 `--test` 必须至少有一个。
* 第 L497-L498 行：`run_regression()` 返回 summary 后，失败数量为 0 才返回 exit code 0。

接口关系：

* 被调用：`main()`。
* 调用：`run_regression()`。
* 共享状态：根据 `summary.failed` 决定 CLI exit code。

§6 staged per-test CLI
--------------------------------------------------------------------------------

这些脚本都支持 `--dir-metadata` 和 `--test-dot-seed` 模式，用于 `wrapper.mk` 的
per-test dependency graph。

§6.1 ``run_instr_gen.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/run_instr_gen.py:L166-L198``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(description="Run riscv-dv instruction generator")
       parser.add_argument("--riscv-dv-dir", default="", help="riscv-dv directory")
       parser.add_argument("--work-dir", default="", help="Working directory")
       parser.add_argument("--test", default="", help="Test name")
       parser.add_argument("--gen-opts", default="", help="Generator options")
       parser.add_argument("--seed", type=int, default=1, help="Random seed")
       parser.add_argument("--iterations", type=int, default=1, help="Iterations")
       parser.add_argument("--dir-metadata", default="",
                           help="Ibex-style metadata directory")
       parser.add_argument("--test-dot-seed", default="",
                           help="Ibex-style TEST.SEED selector")
       args = parser.parse_args()

逐段解释：

* 第 L167-L173 行：standalone 模式需要 riscv-dv dir、work dir、test、gen opts、
  seed 和 iterations。
* 第 L174-L177 行：metadata mode 只需要 `--dir-metadata` 和 `--test-dot-seed`。
* 第 L180-L184 行：metadata mode 缺少 `--test-dot-seed` 会报错；否则调用
  `run_from_metadata()`。
* 第 L186-L198 行：standalone 模式要求 `--riscv-dv-dir`、`--work-dir` 和 `--test`
  非空，然后调用 `run_instr_gen()`。

接口关系：

* 被调用：`wrapper.mk` 的 `instr_gen_run`，或顶层 `Makefile gen`。
* 调用：`run_from_metadata()`、`run_instr_gen()`。
* 共享状态：metadata mode 读 metadata；standalone mode 写 work dir。

§6.2 ``compile_test.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L434-L476``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(description="Compile RISC-V assembly to binary")
       parser.add_argument("--asm", default="", help="Assembly file path")
       parser.add_argument("--bin", default="", help="Output binary path")
       parser.add_argument("--hex", default="", help="Output VMA-addressed hex path")
       parser.add_argument("--linker", default="", help="Linker script")
       parser.add_argument("--gcc-prefix", default="riscv32-unknown-elf",
                           help="GCC toolchain prefix")
       parser.add_argument("--riscv-dv-dir", default="",
                           help="riscv-dv root used for generated assembly includes")
       parser.add_argument("--include-dir", action="append", default=[],
                           help="Additional assembly include directory")

逐段解释：

* 第 L435-L445 行：standalone mode 的核心参数是 input asm、output bin/hex、
  linker、GCC prefix、riscv-dv dir 和 include dir。
* 第 L446-L449 行：metadata mode 使用 `--dir-metadata` 和 `--test-dot-seed`。
* 第 L452-L458 行：metadata mode 会调用 `compile_from_metadata()`，但 CLI 最终
  `sys.exit(0)`，让 staged regression 继续收集所有 per-test failures。
* 第 L460-L476 行：standalone mode 要求 `--asm` 和 `--bin`；linker 缺失时使用默认
  `scripts/link.ld`，然后调用 `compile_assembly()`。

接口关系：

* 被调用：`wrapper.mk` 的 compile targets。
* 调用：`compile_from_metadata()`、`compile_assembly()`、`create_default_linker_script()`。
* 共享状态：读 assembly/linker，写 binary/hex/result。

§6.3 ``run_rtl.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L326-L362``）：

.. code-block:: python

   def main(argv=None) -> int:
       parser = argparse.ArgumentParser(description="EH2 RTL Simulation Runner")
       parser.add_argument("--test", default="", help="Test name")
       parser.add_argument("--seed", type=int, default=1, help="Random seed")
       parser.add_argument("--binary", default="", help="Test binary path")
       parser.add_argument("--simulator", default="vcs", choices=["vcs", "xlm", "questa"])
       parser.add_argument("--config", default="default", help="EH2 configuration")
       parser.add_argument("--waves", action="store_true", help="Enable waveform dump")
       parser.add_argument("--coverage", action="store_true", help="Enable coverage")
       parser.add_argument("--timeout", type=int, default=10000000, help="Sim timeout (ns)")
       parser.add_argument("--rtl-test", default="core_eh2_base_test", help="UVM test class")
       parser.add_argument("--sim-opts", default="", help="Simulation plusargs")

逐段解释：

* 第 L327-L337 行：standalone mode 覆盖 test、seed、binary、simulator、config、
  waves、coverage、timeout、RTL test class 和 sim opts。
* 第 L338-L343 行：`--build-dir`、`--out-dir`、`--dir-metadata`、`--test-dot-seed`
  用于覆盖目录或进入 metadata mode。
* 第 L347-L362 行：metadata mode 要求 `--test-dot-seed`，调用 `run_from_metadata()`，
  保存 TRR 后返回 0，以便后续 `check_logs.py` 统一判定。

接口关系：

* 被调用：`wrapper.mk` 的 `rtl_sim_run`，或用户直接运行。
* 调用：`run_from_metadata()`、`run_rtl_simulation()`。
* 共享状态：读 `rtl_simulation.yaml`，写 sim log 和 result data。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L364-L393``）：

.. code-block:: python

       if not args.test:
           parser.error("--test is required without --dir-metadata")

       md = RegressionMetadata()
       md.test_name = args.test
       md.seed = args.seed
       md.binary_path = args.binary
       md.simulator = args.simulator
       md.eh2_config = args.config
       md.waves = args.waves
       md.coverage = args.coverage
       md.sim_time_ns = args.timeout
       md.rtl_test = args.rtl_test
       md.sim_opts = args.sim_opts

逐段解释：

* 第 L364-L365 行：standalone mode 必须提供 `--test`。
* 第 L367-L381 行：standalone mode 手工构造 `RegressionMetadata`，把 CLI 参数映射到
  metadata 字段。
* 第 L383-L393 行：调用 `run_rtl_simulation()`，保存结果，并按 `trr.passed` 返回
  exit code。

接口关系：

* 被调用：`run_rtl.py` standalone mode。
* 调用：`RegressionMetadata()`、`run_rtl_simulation()`。
* 共享状态：写 `md.out_dir` 下 result。

§6.4 ``check_logs.py`` 和 ``collect_results.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L239-L321``）：

.. code-block:: python

   def main(argv=None) -> int:
       parser = argparse.ArgumentParser(description="Check simulation logs")
       parser.add_argument("--log", default="", help="Simulation log path")
       parser.add_argument("--trace", default="", help="Trace file path")
       parser.add_argument("--output", default="", help="Output result path")
       parser.add_argument("--fail-on-warnings", action="store_true",
                           help="Treat simulator/UVM warnings as failures")
       parser.add_argument("--sim-returncode", type=int, default=None,
                           help="Simulator process return code")
       parser.add_argument("--dir-metadata", default="",
                           help="Ibex-style metadata directory")
       parser.add_argument("--test-dot-seed", default="",

逐段解释：

* 第 L240-L251 行：standalone mode 接收 log、trace、output、fail-on-warnings 和
  simulator return code；metadata mode 接收 `--dir-metadata` 和 `--test-dot-seed`。
* 第 L255-L301 行：metadata mode 从 metadata 目录定位 test dir、sim log、trace 和
  recorded result，写 `result` 和 `trr.yaml`。
* 第 L303-L306 行：standalone mode 必须提供 `--log`。
* 第 L316-L321 行：metadata mode 总是返回 0，让 collect 阶段聚合所有失败；
  standalone mode 按检查结果返回。

接口关系：

* 被调用：`wrapper.mk` 的 `check_logs` target。
* 调用：`check_sim_log()`、`RegressionMetadata.construct_from_metadata_dir()`。
* 共享状态：读 sim log/trace，写 result 和 `trr.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/collect_results.py:L112-L151``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(description="Collect regression results")
       parser.add_argument("--results-dir", default="", help="Results directory")
       parser.add_argument("--output-dir", default="", help="Output directory")
       parser.add_argument("--dir-metadata", default="",
                           help="Ibex-style metadata directory")
       args = parser.parse_args()

       if args.dir_metadata:
           from metadata import RegressionMetadata
           md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)
           results_dir = md.dir_tests
           output_dir = args.output_dir or md.dir_out

逐段解释：

* 第 L113-L118 行：`collect_results.py` 有 standalone 的 `--results-dir/--output-dir`
  和 staged 的 `--dir-metadata` 两种模式。
* 第 L120-L124 行：metadata mode 从 metadata 中读取 `dir_tests`，输出目录默认为
  `md.dir_out`。
* 第 L126-L134 行：standalone mode 必须提供 `--results-dir`，然后调用
  `collect_results()` 和 `write_reports()`。
* 第 L136-L151 行：打印 total/pass/fail/pass rate 和失败列表，并按失败数量返回 exit
  code。

接口关系：

* 被调用：`wrapper.mk` 的 `collect_results` target。
* 调用：`collect_results()`、`write_reports()`。
* 共享状态：读取 per-test result，写 text/JUnit/JSON 等报告。

§7 coverage 和 report CLI
--------------------------------------------------------------------------------

§7.1 ``get_fcov.py`` 与 ``merge_cov.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``get_fcov.py`` 仍保留 Ibex-style staged flow 的 coverage 入口，但当前 sign-off
coverage 的权威路径是 ``merge_cov.py``。后者只合并 VCS ``.vdb``，调用 URG 原生
dashboard；NC/Incisive 和 Xcelium 不进入 sign-off coverage。

关键代码（``dv/uvm/core_eh2/scripts/merge_cov.py:L1-L18``）：

.. code-block:: python

   """
   EH2 Coverage Merge Script
   
   Merges VCS coverage databases using urg. Modeled after lowRISC Ibex's
   dv/uvm/core_ibex/scripts/merge_cov.py.
   
   NC/Incisive does NOT participate in sign-off coverage. NC is reserved for
   single-test waveform debugging only (`make smoke|regress SIMULATOR=nc
   WAVES=1`). Coverage instrumentation, merge, and report generation all run
   on the VCS path exclusively.
   """

逐段解释：

* 第 L5-L7 行：脚本明确对齐 lowRISC Ibex 的 ``merge_cov.py``。
* 第 L12-L17 行：NC/Incisive 只保留单测波形调试用途；coverage instrumentation、
  merge 和 report 都固定在 VCS path。
* 这段注释是当前流程层判断 coverage 真实性的关键边界，优先级高于旧
  ``get_fcov.py`` 中的 Xcelium 提示。

接口关系：

* 被调用：`wrapper.mk` 的 `riscv_dv_fcov` target。
* 调用：`urg`。
* 共享状态：读 metadata 下 coverage database，写 coverage report。

关键代码（``dv/uvm/core_eh2/scripts/merge_cov.py:L48-L84``）：

.. code-block:: python

   def merge_cov_vcs(cov_dirs: List[Path], output_dir: Path) -> int:
       """Merge VCS coverage databases using urg.
   
       Produces:
         <output_dir>/merged.vdb           — merged coverage database
         <output_dir>/report/              — urg HTML + text reports
         <output_dir>/report/dashboard.txt — dashboard for signoff parsing
         <output_dir>/dashboard.txt        — mirrored dashboard (sign-off entry)
       """
       output_dir.mkdir(parents=True, exist_ok=True)
       log_path = output_dir / "merge.log"
       stdout_log = output_dir / "merge.log.stdout"
   
       cmd = [
           "urg", "-full64",
           "-format", "both",
           "-dbname", str(output_dir / "merged.vdb"),
           "-report", str(output_dir / "report"),
           "-log", str(log_path),
           "-dir",
       ] + [str(d) for d in cov_dirs]

逐段解释：

* 第 L48-L58 行：输出包含 ``merged.vdb``、URG HTML/text report、
  ``report/dashboard.txt`` 和根目录镜像 ``dashboard.txt``。
* 第 L63-L72 行：实际命令是 ``urg -full64 -format both -dbname ... -report ...
  -log ... -dir <vdb...>``，没有额外的 coverage dashboard 合成层。
* 第 L80-L84 行：如果 URG report 下存在 ``dashboard.txt``，脚本会镜像到输出根目录，
  让 ``signoff.py`` 不需要知道 URG 子目录结构。

接口关系：

* 被调用：`wrapper.mk` 的 `merge_cov` target、`signoff.py` 自动合并逻辑或用户
  standalone CLI。
* 调用：Synopsys URG。
* 共享状态：读取 VCS ``.vdb``，写 ``cov_merged/dashboard.txt``。
* 调用：`standalone_merge()`。
* 共享状态：读 coverage database directories，写 merged coverage output。

§7.2 ``gen_html_report.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L1074-L1110``）：

.. code-block:: python

   def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
       parser = argparse.ArgumentParser(
           description="Generate a self-contained EH2 sign-off HTML report")
       parser.add_argument("--signoff-status", type=Path,
                           default=DEFAULT_SIGNOFF_STATUS,
                           help="Path to signoff_status.json")
       parser.add_argument("--coverage-dashboard", type=Path,
                           default=DEFAULT_COVERAGE_DASHBOARD,
                           help="Path to URG dashboard.txt")
       parser.add_argument("--runs-dir", type=Path, default=DEFAULT_RUNS_DIR,
                           help="Path to sign-off runs directory")
       parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,

逐段解释：

* 第 L1074-L1087 行：HTML report CLI 有 4 个路径参数：sign-off status、coverage
  dashboard、runs dir、output。
* 第 L1090-L1099 行：`main()` 在读取前检查 status JSON 和 coverage dashboard 是否存在。
* 第 L1100-L1105 行：加载报告数据、写 HTML、打印输出路径和展示的 test 数量。

接口关系：

* 被调用：顶层 `Makefile html_report`。
* 调用：`load_report_data()`、`write_report()`。
* 共享状态：读 JSON/dashboard/runs，写单文件 HTML。

§8 sign-off CLI
--------------------------------------------------------------------------------

职责：`signoff.py` 统一执行 smoke、directed、cosim、riscv-dv、lint、CSR unit、
compliance、formal、syn 等 stage，并在 gate-only 模式下评估已有 stage result。

§8.1 stage 命令生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L201-L248``）：

.. code-block:: python

   def build_stage_cmd(stage: str, args, stage_out: Path) -> List[str]:
       run_regress = SCRIPT_DIR / "run_regress.py"
       cmd = [sys.executable, str(run_regress),
              "--simulator", args.simulator,
              "--seed", str(args.seed),
              "--output", str(stage_out)]

       if args.parallel > 1:
           cmd.extend(["--parallel", str(args.parallel)])
       if args.coverage:
           cmd.append("--coverage")
       if args.waves:
           cmd.append("--waves")
       if not args.allow_warnings:
           cmd.append("--fail-on-warnings")

逐段解释：

* 第 L201-L206 行：默认 stage 命令以当前 Python 解释器运行 `run_regress.py`，并传入
  simulator、seed、output。
* 第 L208-L215 行：parallel、coverage、waves 和 fail-on-warnings 由 sign-off CLI
  参数转换成 run_regress 参数。
* 第 L217-L223 行：smoke stage 使用固定 `--test smoke`、`tests/asm/smoke.hex`、
  `core_eh2_base_test` 和 `+disable_cosim=1`。
* 第 L224-L242 行：lint、CSR unit、compliance、formal、syn 直接返回对应 make 或
  compliance runner 命令。
* 第 L243-L248 行：其它 stage 通过 `STAGE_TESTLIST[stage]` 选择 testlist，并可传入
  iterations。

接口关系：

* 被调用：sign-off 执行 stage 时。
* 调用：`run_regress.py`、`make lint`、CSR compliance make、compliance runner、
  `make formal`、`make syn`。
* 共享状态：读取 CLI args 和 `STAGE_TESTLIST`。

§8.2 sign-off 参数面
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1472-L1518``）：

.. code-block:: python

   def main(argv=None) -> int:
       parser = argparse.ArgumentParser(description="Run/evaluate EH2 sign-off flow")
       parser.add_argument("--profile", choices=sorted(PROFILE_STAGES),
                           default="full", help="Sign-off stage preset")
       parser.add_argument("--stages", default="",
                           help="Comma-separated stage override")
       parser.add_argument("--output", default=str(DEFAULT_OUT),
                           help="Sign-off output directory")
       parser.add_argument("--stage-result", action="append", default=[],
                           help="Use existing results for a stage: STAGE=DIR")
       parser.add_argument("--dry-run", action="store_true",
                           help="Print planned commands without running or gating")

逐段解释：

* 第 L1473-L1485 行：stage selection 参数包括 profile、stages、output、stage-result、
  dry-run、gate-only。
* 第 L1486-L1498 行：execution 参数包括 simulator、seed、iterations、
  max-iter-per-test、parallel、timeout、coverage 和 waves。
* 第 L1499-L1510 行：coverage gate 参数包括 coverage path、no-require-coverage、
  min pass rate，以及 overall/line/fsm/toggle/GROUP(functional) 等阈值。脚本对
  `cond` 的解析是历史文本兼容，当前 VCS 编译维度不采集 `cond`。
* 第 L1511-L1518 行：cosim-disabled 和 skip-in-signoff waiver gate 可被关闭，
  或由 `--waivers-cosim-disabled` 指向 waiver YAML。

接口关系：

* 被调用：顶层 `Makefile signoff/signoff_gate` 或用户直接 CLI。
* 调用：`argparse`。
* 共享状态：生成 `args`，供 stage execution 和 gate evaluation 使用。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1519-L1538``）：

.. code-block:: python

       parser.add_argument("--allow-warnings", action="store_true",
                           help="Do not treat warnings as sign-off failures")
       parser.add_argument("--skip-precheck", action="store_true")
       parser.add_argument("--require-cosim-all-tests", action="store_true",
                           help="Fail if any riscv-dv test is marked cosim disabled")
       parser.add_argument("--lec-known-limited", action="store_true",
                           help="Waive LEC failures covered by ADR-0019 when no True RTL bug bucket exists")
       parser.add_argument("--lec-blocklevel", action="store_true",
                           help="Use R3-C syn/build/lec_summary.txt for the syn stage")
       parser.add_argument("--lec-summary-path", type=str, default="",
                           help="Override R3-C block-level LEC summary path")
       parser.add_argument("--html-report", dest="html_report",
                           action="store_true", default=True,

逐段解释：

* 第 L1519-L1523 行：warnings、precheck 和 cosim-all-tests 是 sign-off gate 的行为开关。
* 第 L1524-L1529 行：LEC 参数包含 `--lec-known-limited`、`--lec-blocklevel` 和
  `--lec-summary-path`。源码 help 明确把 known-limited waiver 关联到 ADR-0019。
* 第 L1530-L1538 行：HTML 报告默认开启，可用 `--no-html-report` 关闭；也可用
  `--validate-waivers` 单独校验 waiver YAML schema 后退出。

接口关系：

* 被调用：`signoff.py main()`。
* 调用：后续 gate 逻辑、HTML report 生成逻辑、waiver validation。
* 共享状态：读取 ADR-0019 相关 LEC waiver 开关和 block-level LEC summary path。

§9 辅助 CLI 和 import-only helper
--------------------------------------------------------------------------------

§9.1 ``build_instr_gen.py``、``compile_tb.py``、``render_config_template.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/build_instr_gen.py:L23-L59``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(description='Build riscv-dv instruction generator')
       parser.add_argument('--dir-metadata', type=Path, required=True,
                           help='Path to regression metadata directory')
       args = parser.parse_args()

       md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)

       # Clean and recreate the instruction generator directory
       gen_dir = Path(md.work_dir) / 'instr_gen'
       try:
           shutil.rmtree(gen_dir)
       except FileNotFoundError:
           pass

逐段解释：

* 第 L23-L27 行：`build_instr_gen.py` CLI 只接收必需的 `--dir-metadata`。
* 第 L29-L37 行：从 metadata 构造 `RegressionMetadata`，删除并重建 `instr_gen` 目录。
* 第 L40-L48 行：通过 `riscvdv_interface.get_run_cmd()` 构造 compile-only 命令，
  追加 `--co`、`--simulator`、`--end_signature_addr`。
* 第 L50-L59 行：执行命令，返回 riscv-dv generator build 的 return code。

接口关系：

* 被调用：`wrapper.mk` 的 `instr_gen_build`。
* 调用：`RegressionMetadata.construct_from_metadata_dir()`、`riscvdv_interface.get_run_cmd()`、
  `run_one()`。
* 共享状态：读 metadata，写 `instr_gen` build logs。

关键代码（``dv/uvm/core_eh2/scripts/compile_tb.py:L79-L103``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(description='Compile EH2 UVM testbench')
       parser.add_argument('--dir-metadata', type=Path, required=True,
                           help='Path to regression metadata directory')
       args = parser.parse_args()

       md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)
       os.makedirs(md.work_dir, exist_ok=True)

       cmd = get_compile_cmd(md)
       logger.info(f'Compiling testbench with {md.simulator}')

逐段解释：

* 第 L79-L83 行：`compile_tb.py` CLI 只接收 `--dir-metadata`。
* 第 L85-L88 行：从 metadata 构造编译命令。
* 第 L91-L99 行：stdout/stderr 重定向到 `compile_stdout.log`，返回 compile 命令
  return code。

接口关系：

* 被调用：`eh2_sim.mk` 的 testbench compile target。
* 调用：`get_compile_cmd()`、`run_one()`。
* 共享状态：读 metadata，写 compile log。

关键代码（``dv/uvm/core_eh2/scripts/render_config_template.py:L57-L69``）：

.. code-block:: python

   def main(argv=None) -> int:
       parser = argparse.ArgumentParser(description=__doc__)
       parser.add_argument("template_filename")
       parser.add_argument("--dir-metadata", type=Path, required=True)
       args = parser.parse_args(argv)

       md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)
       sys.stdout.write(render_template(md.eh2_config, args.template_filename))
       return 0

逐段解释：

* 第 L57-L61 行：CLI 接收一个 positional `template_filename` 和必需的
  `--dir-metadata`。
* 第 L63-L64 行：函数从 metadata 取 `eh2_config`，并把渲染结果写到 stdout。
* 第 L68-L69 行：脚本入口用 `SystemExit(main())` 返回状态。

接口关系：

* 被调用：`wrapper.mk` 的 `core_config` target。
* 调用：`render_template()`。
* 共享状态：读 metadata 和 template，stdout 通常被 Makefile 重定向到 generated SV。

§9.2 ``eh2_cmd.py`` 与 ``setup_imports.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/eh2_cmd.py:L58-L69``）：

.. code-block:: python

   if __name__ == "__main__":
       import argparse

       parser = argparse.ArgumentParser(description="EH2 config helper")
       parser.add_argument("config", nargs="?", default="default")
       parser.add_argument("--defines", action="store_true")
       args = parser.parse_args()

       if args.defines:
           print(render_compile_defines(args.config))
       else:
           print(get_config(args.config))

逐段解释：

* 第 L61-L63 行：CLI 接收可选 `config` positional 参数，默认 `default`，以及
  `--defines`。
* 第 L66-L69 行：`--defines` 输出 Verilog `+define+` 字符串；否则打印 profile
  字典。

接口关系：

* 被调用：用户或其它脚本可直接调用；主要 helper 函数由 render/config flow 使用。
* 调用：`render_compile_defines()`、`get_config()`。
* 共享状态：读 `eh2_configs.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/setup_imports.py:L14-L42``）：

.. code-block:: python

   def get_project_root() -> Path:
       """Get the project root directory (eh2-veri/)."""
       return Path(__file__).resolve().parents[4]


   root = get_project_root()
   _EH2_ROOT = root
   _CORE_EH2 = root / 'dv' / 'uvm' / 'core_eh2'
   _CORE_EH2_SCRIPTS = _CORE_EH2 / 'scripts'
   _CORE_EH2_RISCV_DV_EXTENSION = _CORE_EH2 / 'riscv_dv_extension'
   _CORE_EH2_YAML = _CORE_EH2 / 'yaml'
   _RISCV_DV = root / 'vendor' / 'google_riscv-dv'

逐段解释：

* 第 L14-L16 行：project root 从 `setup_imports.py` 向上 4 层得到。
* 第 L19-L26 行：模块级变量保存 EH2 root、core UVM 目录、scripts 目录、
  riscv_dv_extension、yaml 目录和 vendor riscv-dv scripts 目录。
* 第 L29-L38 行：`get_pythonpath()` 把这些路径用冒号连接。
* 第 L41-L42 行：直接执行 `setup_imports.py` 会打印该 PYTHONPATH 字符串。

接口关系：

* 被调用：顶层 `Makefile` 第 L54 行通过 `python3 -c` 调用 `get_pythonpath()`。
* 调用：无外部命令。
* 共享状态：提供统一 PYTHONPATH 字符串。

§10 快速索引
--------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 22 34 44

   * - CLI
     - 主要参数
     - 典型上层入口
   * - `metadata.py`
     - `--op`、`--dir-metadata`、`--dir-out`、`--args-list`、`--field`
     - `Makefile run`、`get_meta.mk`
   * - `run_regress.py`
     - `--testlist` / `--test`、`--simulator`、`--iterations`、`--parallel`
     - `smoke`、`nightly`、`weekly`、`regress`、`run_regress`
   * - `run_instr_gen.py`
     - `--riscv-dv-dir`、`--work-dir`、`--test`、`--dir-metadata`
     - `gen`、`wrapper.mk instr_gen_run`
   * - `compile_test.py`
     - `--asm`、`--bin`、`--hex`、`--dir-metadata`、`--test-dot-seed`
     - `wrapper.mk compile_*_tests`
   * - `run_rtl.py`
     - `--test`、`--seed`、`--binary`、`--simulator`、`--dir-metadata`
     - `wrapper.mk rtl_sim_run`
   * - `check_logs.py`
     - `--log`、`--trace`、`--fail-on-warnings`、`--dir-metadata`
     - `wrapper.mk check_logs`
   * - `collect_results.py`
     - `--results-dir`、`--output-dir`、`--dir-metadata`
     - `wrapper.mk collect_results`
   * - `signoff.py`
     - `--profile`、`--stages`、`--gate-only`、coverage thresholds、LEC switches
     - `Makefile signoff/signoff_gate`、`wrapper.mk signoff`
   * - `gen_html_report.py`
     - `--signoff-status`、`--coverage-dashboard`、`--runs-dir`、`--output`
     - `Makefile html_report`
   * - `get_fcov.py`
     - `--dir-metadata`、`--simulator`、`--cov-dir`
     - `wrapper.mk riscv_dv_fcov`
   * - `merge_cov.py`
     - `--dirs`、`--output`
     - `wrapper.mk merge_cov` 或 standalone merge

§11 参考资料
--------------------------------------------------------------------------------

关联章节：

* :doc:`build_flow` — build 和 compile target 的流程视角。
* :doc:`regression_flow` — regression target 和 testlist 执行视角。
* :doc:`signoff_flow` — sign-off stage 和 gate 视角。
* :doc:`../appendix_f_scripts/core_eh2_scripts` — Python 脚本逐函数实现。
* :doc:`../appendix_f_scripts/makefiles` — Makefile target 的逐段解释。
* :doc:`../appendix_f_scripts/yaml_configs` — YAML 配置与 testlist 的数据结构。

源文件绝对路径：

* `/home/host/eh2-veri/Makefile`
* `/home/host/eh2-veri/dv/uvm/core_eh2/wrapper.mk`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_instr_gen.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_test.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_rtl.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/check_logs.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/collect_results.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/get_fcov.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/merge_cov.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/gen_html_report.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/build_instr_gen.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_tb.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/render_config_template.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/eh2_cmd.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/setup_imports.py`

关联 ADR：

* :ref:`adr-0019` — `signoff.py --lec-known-limited` help 文本中引用的 LEC
  known-limited waiver。
* :ref:`adr-0020` — block-level LEC closure，与 `--lec-blocklevel` 和
  `--lec-summary-path` 的 sign-off 使用方式相关。
