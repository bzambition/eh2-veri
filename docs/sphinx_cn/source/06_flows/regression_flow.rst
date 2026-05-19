.. _regression_flow:
.. _06_flows/regression_flow:

回归测试流程 — 详细参考
================================================================================

:status: draft
:source: Makefile; dv/uvm/core_eh2/wrapper.mk; dv/uvm/core_eh2/scripts/run_regress.py; dv/uvm/core_eh2/scripts/metadata.py; dv/uvm/core_eh2/scripts/check_logs.py; dv/uvm/core_eh2/scripts/collect_results.py; dv/uvm/core_eh2/scripts/test_entry.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  流程边界
--------------------------------------------------------------------------------

EH2 回归流程有两条源码路径：

.. code-block:: text

   Direct regression path
      |
      |-- make smoke / nightly / weekly / regress / run_regress
      |     `-- python3 dv/uvm/core_eh2/scripts/run_regress.py
      |           |-- load_regression_testlist()
      |           |-- build test_matrix
      |           |-- run_single_test() sequentially or via ProcessPoolExecutor
      |           |     |-- run_instr_gen.py
      |           |     |-- compile_test.py
      |           |     |-- run_rtl.py
      |           |     `-- check_sim_log()
      |           `-- regr.log / regr_junit.xml / report.json
      |
   Ibex-style staged path
      |
      |-- make run GOAL=<wrapper-target>
      |     |-- metadata.py --op create_metadata
      |     `-- make -C dv/uvm/core_eh2 --file wrapper.mk <wrapper-target>
      |           |-- instr_gen_run
      |           |-- compile_riscvdv_tests / compile_directed_tests
      |           |-- rtl_tb_compile
      |           |-- rtl_sim_run
      |           |-- check_logs
      |           `-- collect_results

**逐段解释** ：

* ``make regress`` 走 direct regression path，调用
  :file:`dv/uvm/core_eh2/scripts/run_regress.py`。``GOAL`` 不作用于
  ``make regress``；源码中 ``GOAL`` 非空时只定义顶层 ``run`` target。
* direct path 在 Python 中构造 test matrix，可以顺序执行，也可以用
  ``ProcessPoolExecutor`` 并行执行。
* staged path 先由 :file:`dv/uvm/core_eh2/scripts/metadata.py` 写 metadata，再由
  :file:`dv/uvm/core_eh2/wrapper.mk` 根据 metadata 展开 Make 文件依赖。
* 两条路径最终都以 :class:`TestRunResult` 和 :class:`RegressionSummary` 为核心数据
  结构，但 direct path 在 ``run_regress.py`` 内部收集，staged path 通过
  ``collect_results.py --dir-metadata`` 收集。

**接口关系** ：

* **上游入口** ：顶层 :file:`Makefile` 的 ``smoke``、``nightly``、``weekly``、
  ``regress``、``run_regress`` 和 ``run GOAL=...``。
* **下游脚本** ：``run_instr_gen.py``、``compile_test.py``、``run_rtl.py``、
  ``check_logs.py``、``collect_results.py``。
* **共享状态** ：direct path 输出到 :file:`build/` 子目录；staged path 读取
  metadata 中的 ``dir_tests``、``dir_out``、``dir_metadata``。

§2  顶层 Makefile 回归入口
--------------------------------------------------------------------------------

§2.1  direct regression targets
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：顶层 Makefile 的 ``smoke``、``nightly``、``weekly``、``regress`` 和
``run_regress`` target 都先依赖 ``compile``，再调用 ``run_regress.py``。

**关键代码** （``Makefile:L381-L435``）：

.. code-block:: text

   smoke: compile
   	@echo "=== Running smoke tests ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --test riscv_arithmetic_basic_test \
   	  --simulator $(SIMULATOR) \
   	  --seed 1 \
   	  --output $(BUILD_DIR)/smoke
   	@echo "=== Smoke tests complete ==="
   
   nightly: compile
   	@echo "=== Running nightly regression ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \
   	  --iterations 1 \
   	  --parallel $(PARALLEL) \

**逐段解释** ：

* 第 381-L388 行：``smoke`` 固定调用单测 ``riscv_arithmetic_basic_test``，seed 为
  ``1``，输出目录为 :file:`build/smoke`。
* 第 393-L401 行：``nightly`` 使用
  :file:`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`，iterations 为 ``1``，
  parallel 来自 ``PARALLEL``，``COV=1`` 时追加 ``--coverage``。

**关键代码** （``Makefile:L407-L435``）：

.. code-block:: text

   weekly: compile
   	@echo "=== Running weekly regression ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \
   	  --iterations 5 \
   	  --parallel $(PARALLEL) \
   	  --output $(BUILD_DIR)/weekly
   	@echo "=== Weekly regression complete ==="
   
   regress: compile
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \

**逐段解释** ：

* 第 407-L415 行：``weekly`` 与 ``nightly`` 使用同一 testlist，但 iterations 固定为
  ``5``。
* 第 420-L426 行：``regress`` 使用 ``ITERATIONS`` 和 ``PARALLEL`` 变量，输出到
  :file:`build/regression`。
* 第 428-L435 行：``run_regress`` 可以通过 ``TEST_LIST=directed`` 切换到 directed
  testlist；输出目录可由 ``OUT`` 覆盖，否则使用 :file:`build/regression`。

**接口关系** ：

* **被调用** ：用户或 sign-off wrapper 调用这些 Make target。
* **调用** ：:file:`dv/uvm/core_eh2/scripts/run_regress.py`。
* **共享状态** ：依赖 ``compile`` 生成的 simulator binary，读取 testlist YAML，
  写 :file:`build/smoke`、:file:`build/nightly`、:file:`build/weekly` 或
  :file:`build/regression`。

§2.2  ``GOAL`` staged 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``GOAL`` 非空时，顶层 ``run`` target 创建 metadata 并调用 wrapper；这
是 staged regression path。

**关键代码** （``Makefile:L56-L78``）：

.. code-block:: text

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
   	+@$(MAKE) -C dv/uvm/core_eh2 --file wrapper.mk \
   	  OUT-DIR=$(abspath $(OUT-DIR)) \
   	  METADATA-DIR=$(abspath $(METADATA-DIR)) \
   	  PRJ_DIR=$(CURDIR) \
   	  SIMULATOR=$(SIMULATOR) \
   	  TEST=$(TEST) \
   	  SEED=$(SEED) \
   	  ITERATIONS=$(ITERATIONS) \
   	  PARALLEL=$(PARALLEL) \
   	  COV=$(COV) \
   	  WAVES=$(WAVES) \
   	  --environment-overrides --no-print-directory $(GOAL)

**逐段解释** ：

* 第 57-L66 行：metadata 创建命令把 Make 变量打包成 ``KEY=VALUE`` 字符串传给
  ``metadata.py --op create_metadata``。
* 第 67-L78 行：wrapper 调用把 ``OUT-DIR``、``METADATA-DIR``、``PRJ_DIR``、
  simulator、test、seed、iterations、parallel、coverage、waves 传给
  :file:`dv/uvm/core_eh2/wrapper.mk`。
* ``$(GOAL)`` 是 wrapper target 名称，例如 ``instr_gen_run``、``rtl_sim_run``、
  ``collect_results`` 或 ``all``。源码中没有把 ``GOAL`` 接到 ``make regress``。

**接口关系** ：

* **被调用** ：用户运行 ``make run GOAL=<target>``。
* **调用** ：``metadata.py`` 和 ``wrapper.mk``。
* **共享状态** ：写 metadata 后，wrapper 使用同一 metadata 目录展开 test graph。

§3  ``run_regress.py`` direct runner
--------------------------------------------------------------------------------

§3.1  路径常量与 testlist 归一化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``run_regress.py`` 定位脚本目录、DV 目录、repo root、riscv-dv root 和
默认 testlist，并把 riscv-dv 或 directed schema 归一化为 entry list。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L38-L90``）：

.. code-block:: python

   # Paths
   SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
   DV_DIR = os.path.dirname(SCRIPT_DIR)
   EH2_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(DV_DIR)))
   RISCV_DV_DIR = os.path.join(EH2_ROOT, "vendor", "google_riscv-dv")
   DEFAULT_TESTLIST = os.path.join(DV_DIR, "riscv_dv_extension", "testlist.yaml")
   
   
   def find_test_entry(testlist: list, test_name: str) -> dict:
       """Find a test entry in the testlist."""
       for entry in testlist:
           if entry.get("test") == test_name:
               return entry
       return None
   
   
   def load_regression_testlist(testlist_path: str) -> list:
       """Load riscv-dv or Ibex-style directed testlist entries."""
       raw_entries = load_testlist(testlist_path)

**逐段解释** ：

* 第 39-L43 行：脚本从自身路径推导 ``SCRIPT_DIR``、``DV_DIR``、``EH2_ROOT``，
  默认 riscv-dv root 为 :file:`vendor/google_riscv-dv`，默认 testlist 为
  :file:`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`。
* 第 46-L51 行：``find_test_entry`` 是按 ``test`` 字段查找 entry 的简单 helper。
* 第 54-L57 行：``load_regression_testlist`` 先调用 ``metadata.load_testlist`` 读取
  YAML；空列表直接返回空列表。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L60-L90``）：

.. code-block:: python

       if any(isinstance(entry, dict) and "config" in entry and "test" not in entry
              for entry in raw_entries):
           model = directed_test_schema.import_model(testlist_path)
           raw_by_name = {
               entry.get("test"): entry
               for entry in raw_entries
               if isinstance(entry, dict) and entry.get("test")
           }
           entries = []
           for test in model.tests:
               raw_entry = raw_by_name.get(test.test, {})
               entry = {
                   "test": test.test,
                   "description": test.desc,
                   "test_type": "DIRECTED",
                   "asm": test.test_srcs,
                   "rtl_test": test.rtl_test,
                   "iterations": test.iterations,

**逐段解释** ：

* 第 60-L62 行：如果 YAML entry 中存在 ``config`` 且没有 ``test``，脚本把该文件按
  directed schema 处理。
* 第 63-L67 行：``raw_by_name`` 保存原始 YAML 中带 ``test`` 的 entry，后续用于覆盖
  sim/gen options 等字段。
* 第 68-L77 行：directed schema 的每个 test 被转换为普通 regression entry，包含
  ``test``、``description``、``test_type``、``asm``、``rtl_test`` 和
  ``iterations``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L78-L90``）：

.. code-block:: python

                   "cosim": "enabled"
                            if test.rtl_test == "core_eh2_cosim_test"
                            else "disabled",
               }
               if test.ld_script:
                   entry["linker"] = test.ld_script
               for key in ("sim_opts", "gen_opts", "skip_in_signoff"):
                   if key in raw_entry:
                       entry[key] = raw_entry[key]
               entries.append(entry)
           return entries
   
       return raw_entries

**逐段解释** ：

* 第 78-L80 行：directed test 的 cosim policy 根据 ``rtl_test`` 是否等于
  ``core_eh2_cosim_test`` 生成。
* 第 82-L87 行：linker、``sim_opts``、``gen_opts``、``skip_in_signoff`` 从 schema
  或原始 entry 复制到归一化 entry。
* 第 88-L90 行：directed schema 返回归一化 entries；普通 riscv-dv testlist 直接
  返回 raw entries。

**接口关系** ：

* **被调用** ：``run_regression`` 在非 ``--test`` 模式调用。
* **调用** ：``load_testlist``、``directed_test_schema.import_model``。
* **共享状态** ：读取 riscv-dv或 directed testlist YAML。

§3.2  assembly 查找和 cosim plusarg 合并
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``find_generated_asm`` 定位 riscv-dv 输出的 assembly；``build_sim_opts``
合并 testlist/CLI sim options 并保证存在 cosim plusarg。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L93-L140``）：

.. code-block:: python

   def find_generated_asm(work_dir: str, test_name: str) -> str:
       """Find the assembly file produced by riscv-dv for one test/seed.
   
       riscv-dv writes generated assembly under asm_test/<test>_0.S for a
       single-iteration run.  Some tests (notably CSR tests) can use slightly
       different names, so fall back to the first .S under asm_test.
       """
       candidates = [
           os.path.join(work_dir, "asm_test", f"{test_name}_0.S"),
           os.path.join(work_dir, f"{test_name}_0.S"),
           os.path.join(work_dir, f"{test_name}.S"),
       ]
       for path in candidates:
           if os.path.exists(path):

**逐段解释** ：

* 第 93-L99 行：docstring 明确 riscv-dv 常见输出路径是
  ``asm_test/<test>_0.S``，但也有 fallback。
* 第 100-L107 行：候选路径依次为 ``asm_test/<test>_0.S``、``<test>_0.S``、
  ``<test>.S``，命中即返回。
* 第 109-L115 行：候选都不存在时遍历 ``asm_test`` 或 work dir 下的 ``*.S``；仍找
  不到则抛 ``FileNotFoundError``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L118-L140``）：

.. code-block:: python

   def build_sim_opts(test_entry: dict, cli_sim_opts: str = "") -> str:
       """Merge testlist/CLI sim options and enforce per-test cosim policy."""
       pieces = []
       entry_opts = test_entry.get("sim_opts", "")
       if entry_opts:
           pieces.append(str(entry_opts).replace("\n", " ").strip())
       if cli_sim_opts:
           pieces.append(cli_sim_opts.replace("\n", " ").strip())
   
       cosim = str(test_entry.get("cosim", "enabled")).lower()
       joined = " ".join(piece for piece in pieces if piece).strip()
   
       has_cosim_plusarg = (
           "+enable_cosim=" in joined or
           "+disable_cosim=" in joined
       )

**逐段解释** ：

* 第 118-L125 行：先合并 entry 中的 ``sim_opts`` 和 CLI ``--sim-opts``，并把换行替换
  为空格。
* 第 127-L133 行：从 entry 的 ``cosim`` 字段读取 policy，并检查合并后的 options 中
  是否已经包含 ``+enable_cosim=`` 或 ``+disable_cosim=``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L134-L140``）：

.. code-block:: python

       if not has_cosim_plusarg:
           if cosim in ("disabled", "disable", "false", "0", "no", "rtl_only"):
               pieces.append("+disable_cosim=1")
           else:
               pieces.append("+enable_cosim=1")
   
       return " ".join(piece for piece in pieces if piece).strip()

**逐段解释** ：

* 第 134-L138 行：如果用户或 testlist 未显式给 cosim plusarg，脚本根据 policy 追加
  ``+disable_cosim=1`` 或 ``+enable_cosim=1``。
* 第 140 行：返回去空后的 sim options 字符串。

**接口关系** ：

* **被调用** ：``run_single_test`` 调用这两个 helper。
* **调用** ：filesystem walk 和字符串拼接。
* **共享状态** ：cosim policy 来自 testlist entry 或 directed schema entry。

§3.3  ``run_single_test`` — generate / compile / simulate / check
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``run_single_test`` 对一个 ``(test_entry, seed)`` 执行完整 direct 单测流程。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L171-L238``）：

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

**逐段解释** ：

* 第 171-L181 行：函数参数包含 test entry、seed、simulator、输出目录、可选 binary、
  CLI sim options、coverage、waves 和 fail-on-warnings。
* 第 183-L190 行：创建 ``TestRunResult``，设置 test name、seed，并根据 entry 是否
  含 ``asm`` 或 ``test_srcs`` 推断 ``DIRECTED`` 或 ``RISCVDV``。
* 第 192-L201 行：work dir 形如 ``<output>/<test>_s<seed>``；directed ASM 为相对路径
  时以 ``DV_DIR`` 为基准转换。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L203-L249``）：

.. code-block:: python

       # Step 1: Generate assembly (if no binary or directed assembly provided)
       if not binary and not directed_asm:
           gen_start = time.time()
           gen_cmd = [
               sys.executable, os.path.join(SCRIPT_DIR, "run_instr_gen.py"),
               "--riscv-dv-dir", RISCV_DV_DIR,
               "--work-dir", work_dir,
               "--test", test_name,
               "--gen-opts", gen_opts,
               "--seed", str(seed),
           ]
           try:
               proc = run_captured(gen_cmd, timeout=600)
               result.gen_time_sec = time.time() - gen_start
               gen_log = os.path.join(work_dir, "gen.log")

**逐段解释** ：

* 第 203-L212 行：没有预编译 binary 且不是 directed ASM 时，脚本调用
  ``run_instr_gen.py``，timeout 为 600 秒。
* 第 214-L222 行：生成命令结束后写 ``gen.log``；return code 非 0 时记录
  ``GEN_ERROR`` 并提前保存结果。
* 第 223-L236 行：生成超时记录 ``GEN_TIMEOUT``；找不到 assembly 记录
  ``GEN_NO_ASM``。
* 第 240-L249 行：directed ASM 不存在时记录 ``DIRECTED_ASM_MISSING``；存在时直接
  作为 ``assembly_path``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L251-L286``）：

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

**逐段解释** ：

* 第 251-L262 行：没有预编译 binary 时，脚本调用 ``compile_test.py``，输出
  ``<test>.bin`` 和 ``<test>.hex``。
* 第 263-L267 行：entry 含 linker 时，relative linker path 以 ``DV_DIR`` 为基准。
* 第 268-L282 行：compile timeout 为 120 秒；非零 return code 记录
  ``COMPILE_ERROR``，timeout 记录 ``COMPILE_TIMEOUT``。
* 第 284-L286 行：编译成功后，后续仿真使用 ``hex_path`` 作为 binary path。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L288-L335``）：

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

**逐段解释** ：

* 第 288-L303 行：仿真命令调用 ``run_rtl.py``，传入 test、seed、binary、
  simulator、RTL UVM test、sim opts、build dir 和 out dir。
* 第 304-L307 行：coverage 和 waves 通过 CLI flag 追加。
* 第 309-L320 行：RTL simulation timeout 为 1800 秒；超时记录 ``SIM_TIMEOUT`` 并写
  ``rtl_timeout.log``。
* 第 322-L335 行：仿真结束后调用 ``check_sim_log``，把 pass/failure mode、UVM
  error/warning、instruction/cycle/IPC 写回 result，并保存 ``result.pkl``。

**接口关系** ：

* **被调用** ：``run_regression`` 顺序或并行调用。
* **调用** ：``run_instr_gen.py``、``compile_test.py``、``run_rtl.py``、
  ``check_sim_log``。
* **共享状态** ：单测 work dir 内写 ``gen.log``、``compile.log``、
  ``sim_<test>_<seed>.log``、``result.pkl`` 和 ``result.yaml``。

§3.4  ``run_regression`` — test matrix、并行和报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``run_regression`` 加载 testlist，构造 test matrix，按 ``--parallel`` 选择
顺序或进程池执行，最后生成三类报告。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L338-L379``）：

.. code-block:: python

   def run_regression(args) -> RegressionSummary:
       """Run the full regression."""
       summary = RegressionSummary()
       start_time = time.time()
   
       # Load testlist
       testlist_path = args.testlist or DEFAULT_TESTLIST
       if args.test:
           # Single test mode
           testlist = [{"test": args.test, "rtl_test": args.rtl_test or "core_eh2_base_test",
                        "gen_opts": args.gen_opts or "", "sim_opts": "",
                        "cosim": "disabled" if args.disable_cosim else "enabled"}]
       else:
           testlist = load_regression_testlist(testlist_path)
   
       output_dir = args.output or os.path.join(EH2_ROOT, "build", "regression",

**逐段解释** ：

* 第 338-L341 行：初始化 ``RegressionSummary`` 和 start time。
* 第 344-L351 行：``--test`` 单测模式构造一个 entry；否则从 ``--testlist`` 或默认
  testlist 加载 entries。
* 第 353-L355 行：没有 ``--output`` 时，输出目录为
  ``build/regression/<YYYYMMDD_HHMMSS>``。
* 第 357-L369 行：test matrix 遍历每个 entry 和 iteration；sign-off 环境变量
  ``EH2_SIGNOFF_MODE=1`` 时会跳过 ``skip_in_signoff`` entry。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L381-L422``）：

.. code-block:: python

       # Run tests (sequential for now, parallel later)
       max_workers = args.parallel if hasattr(args, 'parallel') else 1
   
       if max_workers > 1:
           with ProcessPoolExecutor(max_workers=max_workers) as executor:
               futures = {}
               for entry, seed in test_matrix:
                   future = executor.submit(
                       run_single_test, entry, seed, args.simulator,
                       output_dir, args.binary, args.sim_opts,
                       args.coverage, args.waves, args.fail_on_warnings
                   )
                   futures[future] = (entry["test"], seed)

**逐段解释** ：

* 第 381-L383 行：``max_workers`` 来自 ``args.parallel``，默认 ``1``。
* 第 384-L393 行：并行模式使用 ``ProcessPoolExecutor`` 提交每个
  ``run_single_test``。
* 第 395-L403 行：``as_completed`` 收集 future；正常结果加入 summary，异常只打印
  ``[ERROR]``。
* 第 404-L415 行：顺序模式逐项运行 ``run_single_test``，并打印每个 test 的 PASS/FAIL
  和仿真耗时。
* 第 417-L422 行：记录 total time，生成 ``regr.log``、``regr_junit.xml`` 和
  ``report.json``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L424-L444``）：

.. code-block:: python

       if args.coverage and args.simulator == "vcs":
           cov_db = os.path.join(EH2_ROOT, "build", "cov.vdb")
           out_cov_db = os.path.join(output_dir, "cov.vdb")
           if os.path.isdir(cov_db):
               if os.path.isdir(out_cov_db):
                   shutil.rmtree(out_cov_db)
               shutil.copytree(cov_db, out_cov_db)
               print(f"Coverage DB: {out_cov_db}")
           else:
               print(f"[WARN] Coverage requested, but VCS DB not found: {cov_db}")
   
       print(f"\n{'='*60}")
       print(f"Regression Complete")
       print(f"Total: {summary.total_tests} | Passed: {summary.passed} | "
             f"Failed: {summary.failed}")
       print(f"Pass rate: {100*summary.passed/max(1,summary.total_tests):.1f}%")
       print(f"Time: {summary.total_time_sec:.0f}s")
       print(f"Reports: {output_dir}/")
       print(f"{'='*60}\n")

**逐段解释** ：

* 第 424-L433 行：只有 coverage enabled 且 simulator 为 ``vcs`` 时，脚本尝试复制
  :file:`build/cov.vdb` 到 regression output 下的 ``cov.vdb``。
* 第 435-L442 行：打印 total、passed、failed、pass rate、time 和 reports path。
* 第 444 行：返回 ``RegressionSummary``，由 ``main`` 决定进程退出码。

**接口关系** ：

* **被调用** ：``run_regress.py:main``。
* **调用** ：``run_single_test``、``RegressionSummary.to_log``、
  ``RegressionSummary.to_junit_xml``、``generate_report_json``。
* **共享状态** ：输出 ``regr.log``、``regr_junit.xml``、``report.json`` 和可选
  ``cov.vdb``。

§3.5  CLI 参数和退出码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``main`` 定义 direct regression CLI，并在存在失败 test 时返回非零。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L447-L502``）：

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

**逐段解释** ：

* 第 447-L456 行：CLI help 给出 testlist、single test、iterations/parallel 示例。
* 第 459-L463 行：test selection 参数包括 ``--testlist``、``--test``、
  ``--iterations``、``--seed``。
* 第 466-L478 行：test configuration 参数包括 ``--rtl-test``、``--gen-opts``、
  ``--sim-opts``、``--binary``、``--disable-cosim``、``--coverage``、``--waves``、
  ``--fail-on-warnings``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L480-L502``）：

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

**逐段解释** ：

* 第 480-L483 行：simulator choices 为 ``vcs``、``xlm``、``questa``。
* 第 485-L490 行：``--output`` 覆盖输出目录，``--parallel`` 控制进程池大小。
* 第 492-L495 行：必须指定 ``--testlist`` 或 ``--test`` 之一。
* 第 497-L498 行：失败数为 ``0`` 时退出 ``0``，否则退出 ``1``。

**接口关系** ：

* **被调用** ：顶层 Makefile 或命令行直接调用。
* **调用** ：``run_regression``。
* **共享状态** ：进程退出码用于 Make target 或 CI 判定。

§4  metadata 与 staged wrapper
--------------------------------------------------------------------------------

§4.1  ``RegressionMetadata`` 和 ``TestRunResult``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`metadata.py` 定义回归运行的配置对象、单测结果对象和汇总对象。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L21-L80``）：

.. code-block:: python

   @dataclass
   class RegressionMetadata:
       """Central configuration for a regression run."""
   
       # Test configuration
       test_name: str = ""
       test_type: str = "RISCVDV"
       seed: int = 0
       iterations: Optional[int] = 1
       binary_path: str = ""
       rtl_test: str = "core_eh2_base_test"
       signature_addr: str = "d0580000"
   
       # Simulator configuration
       simulator: str = "vcs"  # vcs, xlm, questa
       sim_opts: str = ""
       gen_opts: str = ""

**逐段解释** ：

* 第 21-L32 行：``RegressionMetadata`` 的 test configuration 包含 test name/type、
  seed、iterations、binary path、RTL test 和 signature address。
* 第 34-L42 行：simulator configuration 包含 simulator、sim/gen options、sim time、
  waves、coverage、verbose 和 ISS。
* 第 48-L80 行：metadata 还保存 work/build/out/log/binary/coverage 目录以及 canonical
  input files。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L141-L179``）：

.. code-block:: python

   @dataclass
   class TestRunResult:
       """Result of a single test run."""
   
       test_name: str = ""
       seed: int = 0
       iteration: int = 0
       test_type: str = "RISCVDV"  # RISCVDV or DIRECTED
   
       # Paths
       assembly_path: str = ""
       binary_path: str = ""
       sim_log_path: str = ""
       uvm_log_path: str = ""
       trace_path: str = ""

**逐段解释** ：

* 第 141-L148 行：``TestRunResult`` 保存 test name、seed、iteration 和 test type。
* 第 150-L171 行：结果对象保存 assembly、binary、sim log、trace、coverage、
  pass/failure mode、instruction/cycle/IPC、UVM 计数、return code 和耗时。
* 第 173-L179 行：``save`` 同时写 YAML 和 pickle。

**接口关系** ：

* **被调用** ：所有 regression scripts import 这些 dataclass。
* **调用** ：YAML 和 pickle 序列化。
* **共享状态** ：metadata 和 result 文件是 direct/staged 两条路径的桥。

§4.2  metadata test selection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``metadata.py`` 解析 ``--args-list``，选择 riscv-dv、directed 和 cosim
tests，并为 wrapper 生成 ``TEST.SEED`` 列表。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L277-L317``）：

.. code-block:: python

   def _parse_args_list(args_list: str) -> Dict[str, str]:
       """Parse Make-style KEY=VALUE tokens from metadata --args-list."""
       parsed = {}
       for token in shlex.split(str(args_list or "")):
           if "=" not in token:
               continue
           key, value = token.split("=", 1)
           parsed[key.strip()] = value.strip()
       return parsed
   
   
   def _selected_tests_arg(test_arg: str) -> List[str]:
       return [item.strip() for item in str(test_arg or "all").split(",")
               if item.strip()]
   
   
   def _entry_iterations(entry: Dict, override: Optional[int]) -> int:

**逐段解释** ：

* 第 277-L285 行：``_parse_args_list`` 用 ``shlex.split`` 解析 Make 传来的
  ``KEY=VALUE`` 字符串。
* 第 288-L290 行：``_selected_tests_arg`` 将逗号分隔的 ``TEST`` 字符串转换为列表。
* 第 293-L296 行：``_entry_iterations`` 优先使用 override，否则读取 entry 的
  ``iterations`` 字段。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L320-L366``）：

.. code-block:: python

   def _select_test_entries(md: RegressionMetadata,
                            riscvdv_testlist: Path,
                            directed_testlists: List[Path]
                            ) -> List[Tuple[str, int, str]]:
       """Return (test, count, type) tuples for Ibex-style make dependencies."""
       selected = _selected_tests_arg(md.test_name)
       run_all = any(item in ("all", "all_riscvdv", "all_directed",
                              "all_cosim")
                     for item in selected)
       run_all_riscvdv = any(item in ("all", "all_riscvdv") for item in selected)

**逐段解释** ：

* 第 320-L332 行：selection 支持 ``all``、``all_riscvdv``、``all_directed`` 和
  ``all_cosim``。
* 第 334-L343 行：遍历 riscv-dv testlist，选中的 entry 以
  ``(name, count, "RISCVDV")`` 加入 matrix。
* 第 345-L357 行：遍历 directed 和 cosim testlist；cosim testlist 名称为
  ``cosim_testlist.yaml`` 时，``all_cosim`` 会纳入这些 tests。
* 第 359-L365 行：若未匹配任何 test 且不是 run_all，保留一个单测 metadata entry。

**接口关系** ：

* **被调用** ：``create_metadata``。
* **调用** ：``load_testlist``、``directed_test_schema.import_model``。
* **共享状态** ：生成 ``tests_and_counts``，后续派生 ``riscvdv_tds`` 和
  ``directed_tds``。

§4.3  ``create_metadata`` 和 ``print_field``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``create_metadata`` 写 metadata 文件和目录；``print_field`` 为
``get_meta.mk`` 输出字段值。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L379-L451``）：

.. code-block:: python

   def create_metadata(dir_metadata: str, dir_out: str,
                       args_list: str = "") -> RegressionMetadata:
       """Create a RegressionMetadata object using Ibex-style CLI arguments."""
       args = _parse_args_list(args_list)
       root = Path(__file__).resolve().parents[4]
       out_dir = Path(dir_out).resolve()
       metadata_dir = Path(dir_metadata).resolve()
       core_eh2 = root / "dv" / "uvm" / "core_eh2"
       run_dir = out_dir / "run"
       tests_dir = run_dir / "tests"
       cov_dir = run_dir / "coverage"
   
       md = RegressionMetadata()
       md.seed = int(args.get("SEED", 1) or 1)
       md.test_name = args.get("TEST", "all") or "all"
       md.simulator = args.get("SIMULATOR", "vcs") or "vcs"

**逐段解释** ：

* 第 379-L389 行：函数解析 args，推导 repo root、out dir、metadata dir、core_eh2、
  run/tests/coverage 目录。
* 第 391-L425 行：把 Make 传入的 seed、test、simulator、iterations、waves、
  coverage、verbose、ISS、signature address、config、RTL test、sim/gen options 写入
  metadata。
* 第 426-L434 行：记录 canonical input files，包括 :file:`eh2_configs.yaml`、
  riscv-dv custom target、riscv-dv testlist、directed test dir、directed testlist 和
  cosim testlist。
* 第 436-L450 行：生成 test matrix、``riscvdv_tds``、``directed_tds`` 和 pickle file
  列表，创建目录，并保存 metadata。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L454-L496``）：

.. code-block:: python

   def print_field(dir_metadata: str, field: str) -> str:
       """Print one metadata field for Makefile use."""
       md = RegressionMetadata.construct_from_metadata_dir(dir_metadata)
       if field == "riscvdv_tds":
           value = md.riscvdv_tds
       elif field == "directed_tds":
           value = md.directed_tds
       else:
           if not hasattr(md, field):
               raise AttributeError(f"Unknown metadata field: {field}")
           value = getattr(md, field)

**逐段解释** ：

* 第 454-L464 行：``print_field`` 从 metadata 目录加载 metadata，对
  ``riscvdv_tds`` 和 ``directed_tds`` 做显式分支，其余字段用 ``getattr``。
* 第 466-L473 行：list/tuple 被空格连接；嵌套 tuple 被点号连接；``None`` 输出空
  字符串。
* 第 476-L496 行：CLI ``--op`` 只支持 ``create_metadata`` 和 ``print_field`` 两种。

**接口关系** ：

* **被调用** ：顶层 Makefile 调用 ``create_metadata``；``wrapper.mk`` 通过
  ``get_meta.mk`` 调用 ``print_field``。
* **调用** ：YAML/pickle 保存和读取。
* **共享状态** ：metadata 目录中的 ``metadata.yaml`` 与 ``metadata.pkl``。

§4.4  ``wrapper.mk`` staged graph
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：wrapper 把 metadata 中的 ``TEST.SEED`` 列表转换为 Make 文件依赖。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L40-L64``）：

.. code-block:: text

   OUT-DIR := $(call get-meta,dir_out)
   TESTS-DIR := $(call get-meta,dir_tests)
   BUILD-DIR := $(call get-meta,dir_build)
   RUN-DIR := $(call get-meta,dir_run)
   METADATA-DIR := $(call get-meta,dir_metadata)
   
   riscvdv-ts := $(call get-meta,riscvdv_tds)
   directed-ts := $(call get-meta,directed_tds)
   
   asm-stem := test.S
   bin-stem := test.bin
   hex-stem := test.hex
   rtl-sim-logfile := rtl_sim.log
   trr-stem := trr.yaml

**逐段解释** ：

* 第 40-L44 行：wrapper 所有目录都从 metadata 读取。
* 第 46-L47 行：riscv-dv 与 directed 的 test-dot-seed 列表由 metadata 提供。
* 第 49-L53 行：每个 test 目录使用固定文件名 ``test.S``、``test.bin``、
  ``test.hex``、``rtl_sim.log``、``trr.yaml``。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L87-L145``）：

.. code-block:: text

   instr_gen_run: $(riscvdv-test-asms)
   $(riscvdv-test-asms): $(TESTS-DIR)/%/$(asm-stem): instr_gen_build scripts/run_instr_gen.py
   	@echo Running randomized test generator for $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/run_instr_gen.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    --test-dot-seed $*
   	$(verb)cp $$(find $(@D) -name '*.S' | sort | head -n 1) $@
   
   compile_riscvdv_tests: $(riscvdv-test-bins)

**逐段解释** ：

* 第 87-L94 行：riscv-dv assembly 由 ``run_instr_gen.py --test-dot-seed`` 生成，
  然后复制第一个 ``*.S`` 为统一 ``test.S``。
* 第 96-L110 行：riscv-dv 和 directed binary 都由 ``compile_test.py
  --dir-metadata --test-dot-seed`` 生成。
* 第 112-L122 行：``rtl_tb_compile`` 回到 repo root 执行 ``compile GOAL=``，
  ``rtl_sim_run`` 调用 ``run_rtl.py``，并复制 ``sim_<test>_<seed>.log`` 为
  ``rtl_sim.log``。
* 第 124-L145 行：``check_logs`` 生成 ``trr.yaml``，``collect_results`` 调用
  ``collect_results.py --dir-metadata`` 写最终报告。

**接口关系** ：

* **被调用** ：顶层 ``make run GOAL=<target>``。
* **调用** ：instruction generator、test compiler、RTL runner、log checker、result
  collector。
* **共享状态** ：metadata 中的 test-dot-seed 列表驱动 Make 文件依赖。

§5  日志检查与结果收集
--------------------------------------------------------------------------------

§5.1  ``check_uvm_log`` 判定优先级
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``check_uvm_log`` 扫描仿真 log，识别 UVM summary、真实 UVM error/fatal、
tool crash、timeout、test pass/fail 和 warnings。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L23-L55``）：

.. code-block:: python

   UVM_SUMMARY_RE = re.compile(
       r"^\s*(UVM_WARNING|UVM_ERROR|UVM_FATAL)\s*:\s*(\d+)\b")
   
   # Lines starting with the UVM Report Summary severity tag are never real
   # fatals/errors/warnings — those come from `uvm_report_*` and embed a path
   # like "UVM_FATAL <path>(<line>) @ <time>: ...". VCS interleaves its banner
   # over the summary in two known shapes:
   #   "UVM_FATAL :            V C S   S i m u l a t i o n   R e p o r t"
   #   "UVM_FATAL            V C S   S i m u l a t i o n   R e p o r t"
   # (the colon and count are both eaten.) Match both — colon optional, banner
   # keyword required — so we can safely skip them.

**逐段解释** ：

* 第 23-L24 行：``UVM_SUMMARY_RE`` 匹配 UVM summary 中带 count 的 severity 行。
* 第 26-L36 行：注释和 ``UVM_SUMMARY_LINE_RE`` 处理 VCS banner 覆盖 UVM summary
  count 的情况，避免把 summary banner 误判为真实 fatal/error。
* 第 39-L55 行：tool warning/crash/timeout regex 和 pre-sim failure modes 定义在
  文件顶部。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L58-L144``）：

.. code-block:: python

   def check_uvm_log(log_path: str, fail_on_warnings: bool = False,
                     sim_returncode: int = None) -> tuple:
       """
       Check UVM simulation log for errors.
   
       Returns:
           (passed: bool, failure_mode: str, num_errors: int, num_warnings: int)
       """
       if not os.path.exists(log_path):
           return (False, "FILE_ERROR", 0, 0)
   
       num_errors = 0
       num_warnings = 0
       summary_errors = None
       summary_warnings = None
       has_fatal = False

**逐段解释** ：

* 第 58-L67 行：log 不存在时直接返回 ``FILE_ERROR``。
* 第 69-L84 行：初始化 counters 和 flags；逐行扫描 tool crash 和 timeout。
* 第 86-L122 行：优先读取 UVM summary count；真实 ``UVM_FATAL``、``UVM_ERROR``、
  ``UVM_WARNING`` 和 test pass/fail 字符串也在同一 loop 中识别。
* 第 126-L144 行：判定优先级为 tool crash、tool timeout、fatal、test fail、
  UVM error、sim return code、warnings、test pass，最后缺少 pass signature 返回
  ``NO_PASS_SIGNATURE``。

**接口关系** ：

* **被调用** ：``run_regress.py`` direct path 和 ``check_sim_log``。
* **调用** ：regex search/match。
* **共享状态** ：failure mode 字符串写入 ``TestRunResult``。

§5.2  metadata mode 的 ``check_logs.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：metadata mode 从 metadata 和 ``TEST.SEED`` 定位 log、trace、binary，并且
即使单测失败也返回 ``0``，让 wrapper 可以继续收集所有结果。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L239-L325``）：

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
                           help="Ibex-style TEST.SEED selector")

**逐段解释** ：

* 第 239-L252 行：CLI 支持 direct log mode，也支持 ``--dir-metadata`` 和
  ``--test-dot-seed`` metadata mode。
* 第 255-L290 行：metadata mode 加载 ``RegressionMetadata``，解析 ``TEST.SEED``，
  定位 test dir、``sim_<test>_<seed>.log``、``trace_core`` 和 binary。
* 第 272-L281 行：如果 recorded result 属于 pre-sim failure mode，沿用该结果；
  否则调用 ``check_sim_log``。
* 第 291-L301 行：保存 ``result.pkl`` 和 ``trr.yaml``。
* 第 316-L321 行：metadata mode 返回 ``0``，direct CLI mode 根据 pass/fail 返回。

**接口关系** ：

* **被调用** ：``wrapper.mk:check_logs`` 或命令行 direct check。
* **调用** ：``RegressionMetadata.construct_from_metadata_dir``、``read_test_dot_seed``、
  ``check_sim_log``。
* **共享状态** ：写 ``result.pkl`` 和 ``trr.yaml``。

§5.3  ``collect_results.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：结果收集器扫描 result pickle，聚合为 ``RegressionSummary``，输出 text、
JUnit XML 和 JSON。

**关键代码** （``dv/uvm/core_eh2/scripts/collect_results.py:L22-L61``）：

.. code-block:: python

   def collect_results(results_dir: str) -> RegressionSummary:
       """
       Collect all test results from a directory.
   
       Args:
           results_dir: Directory containing .pkl result files
   
       Returns:
           RegressionSummary with all results
       """
       summary = RegressionSummary()
   
       all_pkl_files = glob.glob(os.path.join(results_dir, "**", "*.pkl"), recursive=True)
       final_result_files = {
           os.path.realpath(path)
           for path in all_pkl_files
           if os.path.basename(path) == "result.pkl"

**逐段解释** ：

* 第 22-L32 行：函数输入是 results directory，输出 ``RegressionSummary``。
* 第 34-L49 行：优先收集 ``result.pkl``；同一目录已有 final result 时，避免重复加入
  其它 pickle。
* 第 51-L59 行：每个 pickle 被加载后必须是 ``TestRunResult`` 才加入 summary；
  加载失败只打印 warning。

**关键代码** （``dv/uvm/core_eh2/scripts/collect_results.py:L64-L109``）：

.. code-block:: python

   def generate_report_json(summary: RegressionSummary, path: str):
       """Generate JSON report."""
       report = {
           "timestamp": datetime.now().isoformat(),
           "total": summary.total_tests,
           "passed": summary.passed,
           "failed": summary.failed,
           "pass_rate": 100.0 * summary.passed / max(1, summary.total_tests),
           "total_time_sec": summary.total_time_sec,
           "tests": []
       }
   
       for r in summary.results:
           report["tests"].append({

**逐段解释** ：

* 第 64-L74 行：JSON report top-level 字段包含 timestamp、total、passed、failed、
  pass_rate、total_time_sec 和 tests。
* 第 76-L98 行：每个 test 记录 name、seed、type、passed、failure_mode、各类路径、
  UVM count、return code、instruction/cycle/IPC 和耗时。
* 第 100-L109 行：``write_reports`` 创建 output directory，并写 ``regr.log``、
  ``regr_junit.xml``、``report.json``。

**关键代码** （``dv/uvm/core_eh2/scripts/collect_results.py:L112-L151``）：

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

**逐段解释** ：

* 第 112-L118 行：CLI 支持 ``--results-dir`` direct mode、``--output-dir`` 和
  ``--dir-metadata`` staged mode。
* 第 120-L129 行：metadata mode 从 metadata 读取 ``dir_tests``，output dir 默认为
  ``md.dir_out``；direct mode 必须提供 ``--results-dir``。
* 第 131-L151 行：收集结果、写三类报告、打印总数/通过/失败/pass rate，失败数非 0
  时退出 ``1``。

**接口关系** ：

* **被调用** ：``wrapper.mk:collect_results`` 或 direct CLI。
* **调用** ：``collect_results``、``write_reports``。
* **共享状态** ：读取 result pickle；写 ``regr.log``、``regr_junit.xml``、
  ``report.json``。

§6  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`build_flow`、:ref:`signoff_flow`、:ref:`scripts_reference`。
* 关联配置：:file:`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`、
  :file:`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`、
  :file:`dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`。
* 源文件绝对路径：
  :file:`/home/host/eh2-veri/Makefile`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/wrapper.mk`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/check_logs.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/collect_results.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/test_entry.py`。
