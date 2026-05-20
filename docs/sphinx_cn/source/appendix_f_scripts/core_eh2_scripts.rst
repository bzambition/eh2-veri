.. _appendix_f_scripts_core_eh2_scripts:
.. _appendix_f_scripts/core_eh2_scripts:

核心 Python 脚本（22 个文件）
==============================

:status: draft
:source: dv/uvm/core_eh2/scripts/
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本章只解释 :file:`dv/uvm/core_eh2/scripts/` 下的核心 Python 脚本及
:file:`report_lib/`。Makefile 片段、顶层 shell 脚本和 YAML 配置分别由后续
脚本附录章节解释；本章只在说明调用边界时点到对应文件名。

所有行号均基于本页 frontmatter 中的 commit。代码片段按功能切片，单片不超过
30 行；每片后面给出段级解释和接口关系。

§1 脚本数据流总览
--------------------------------------------------------------------------------

EH2 UVM Python 脚本围绕同一个数据对象流动：先由 `metadata.py` 创建回归
metadata，再由 `run_regress.py` 对每个 `TEST.SEED` 调用生成、编译、仿真和
日志检查，最后由 `collect_results.py`、`signoff.py` 和
`gen_html_report.py` 聚合为报告。

::

   create_metadata()
        |
        v
   dir_metadata/metadata.pkl
        |
        v
   run_regress.py
        |
        +--> run_instr_gen.py  --> asm_test/*.S
        |
        +--> compile_test.py   --> test.elf / test.bin / test.hex
        |
        +--> run_rtl.py        --> sim_TEST_SEED.log / trace_core
        |
        +--> check_logs.py     --> result.pkl / trr.yaml
        |
        v
   collect_results.py          --> regr.log / regr_junit.xml / report.json
        |
        v
   signoff.py                  --> signoff_status.json / signoff_report.md
        |
        v
   gen_html_report.py          --> report.html

职责：该数据流不是单个脚本中的显式图，而是由 `run_regress.py` 的
`run_single_test()` 和 `run_regression()`、`metadata.py` 的
`create_metadata()`、`signoff.py` 的 `main()` 共同形成。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L171-L188``）：

.. code-block:: python

   def run_single_test(test_entry: dict, seed: int, simulator: str,
                       output_dir: str, riscv_dv_dir: str,
                       gcc_prefix: str, coverage: bool = False,
                       waves: bool = False, timeout: int = 10000000,
                       fail_on_warnings: bool = False,
                       cli_sim_opts: str = "") -> TestRunResult:
       """Run a single test through complete flow."""
       test_name = test_entry["test"]
       work_dir = os.path.join(output_dir, f"{test_name}_{seed}")
       os.makedirs(work_dir, exist_ok=True)

       result = TestRunResult()
       result.test_name = test_name
       result.seed = seed
       result.test_type = test_entry.get("test_type", "RISCVDV")

逐段解释：

* 第 L171-L177 行：单测入口接受 test entry、seed、模拟器、输出目录、
  riscv-dv 根目录、GCC 前缀，以及 coverage、waves、timeout 等执行参数；
  这些参数来自 `run_regression()` 的矩阵展开或 CLI。
* 第 L179-L181 行：`work_dir` 固定为 `<output>/<test>_<seed>`，后续生成、
  编译、仿真、检查阶段都在这个目录中读写 per-test 产物。
* 第 L183-L187 行：每个测试先创建一个 `TestRunResult` 对象；后续阶段只补充
  `assembly_path`、`binary_path`、`sim_log_path`、`failure_mode` 等字段。

接口关系：

* 被调用：`run_regression()` 在串行或 `ProcessPoolExecutor` 并行模式下调用。
* 调用：下游调用 `run_instr_gen.py`、`compile_test.py`、`run_rtl.py` 和
  `check_sim_log()`。
* 共享状态：读 `test_entry` 的 `test_type`、`gen_opts`、`rtl_test`、
  `sim_opts`、`cosim` 字段；写 `work_dir/result.pkl`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1586-L1624``）：

.. code-block:: python

   stage_results = []
   for stage, cmd, stage_out in planned:
       if stage in stage_result_dirs:
           results_dir = stage_result_dirs[stage]
           exit_code = 0
           command = []
       elif args.gate_only:
           results_dir = stage_out
           exit_code = 1
           command = []
       else:
           results_dir = stage_out
           command = cmd
           exit_code = run_command(
               cmd, output_dir / "logs" / "{}.log".format(stage),
               args.timeout_s)

       report_dir = output_dir / "reports" / stage

逐段解释：

* 第 L1587-L1592 行：`--stage-result` 把某个 stage 指向已有结果目录；
  这种模式不重新跑命令，`exit_code` 被置为 0。
* 第 L1593-L1597 行：`--gate-only` 只做门禁评估，不执行阶段命令；脚本用
  `exit_code = 1` 表达该目录仍需被 collector 判定。
* 第 L1598-L1604 行：普通模式调用 `run_command()`，并把阶段日志放在
  `output/logs/<stage>.log`。
* 第 L1606 行：每个 stage 的报告目录固定在 `output/reports/<stage>`，
  这样后续 Markdown 和 JSON 都能引用稳定路径。

接口关系：

* 被调用：`signoff.py main()` 的 stage loop。
* 调用：按 stage 分发到 `collect_stage()`、`collect_lint_stage()`、
  `collect_formal_stage()` 或 `collect_syn_stage()`。
* 共享状态：读取 CLI 的 `gate_only`、`stage_result`、`timeout_s`；
  写 `stage_results` 列表。

§2 ``metadata.py`` — 回归元数据和结果模型
--------------------------------------------------------------------------------

`metadata.py` 是 Python DV flow 的数据契约文件。它定义回归级 metadata、单测结果
和回归汇总，并提供 CLI 来创建 `metadata.pkl`、选择测试列表和打印字段。

§2.1 ``RegressionMetadata`` — 回归级配置容器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：保存一次回归的目录、工具、testlist、开关和展开后的
`tests_and_counts`。该对象被 `run_instr_gen.py`、`compile_test.py`、
`run_rtl.py`、`check_logs.py`、`collect_results.py` 等脚本反复加载。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L21-L61``）：

.. code-block:: python

   @dataclass
   class RegressionMetadata:
       """Metadata for a regression run."""
       # Directory paths
       dir_metadata: str = ""
       dir_out: str = ""
       dir_tests: str = ""
       work_dir: str = ""
       build_dir: str = ""
       out_dir: str = ""
       eh2_root: str = ""

       # Test configuration
       test: str = ""
       seed: int = 1
       iterations: int = 1
       test_type: str = "RISCVDV"  # RISCVDV or DIRECTED

       # Tool configuration
       simulator: str = "vcs"
       eh2_config: str = "default"
       riscv_dv_dir: str = ""
       gcc_prefix: str = "riscv32-unknown-elf"

逐段解释：

* 第 L21-L30 行：目录字段覆盖 metadata 目录、回归输出目录、per-test 目录、
  build 目录、out 目录和 EH2 根目录；后续脚本只需要 metadata 目录就能恢复这些路径。
* 第 L32-L36 行：测试字段保存单测名、seed、迭代次数和测试类型；`test_type`
  默认为 `RISCVDV`，directed 流由 testlist 选择或 CLI 参数覆盖。
* 第 L38-L43 行：工具字段保存模拟器、EH2 配置、riscv-dv 根目录和 GCC 前缀；
  `compile_test.py` 和 `run_rtl.py` 都从这里获取外部工具参数。

接口关系：

* 被调用：`create_metadata()` 创建并导出；其它脚本通过
  `construct_from_metadata_dir()` 加载。
* 调用：类方法内部调用 `pickle.load()` 和 `yaml.safe_dump()`。
* 共享状态：落盘为 `metadata.pkl` 和 `metadata.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L101-L139``）：

.. code-block:: python

       @classmethod
       def construct_from_metadata_dir(cls, dir_metadata: Path):
           """Load metadata from directory."""
           metadata_pkl = Path(dir_metadata) / "metadata.pkl"
           with open(metadata_pkl, "rb") as f:
               return pickle.load(f)

       def save(self, dir_metadata: str):
           """Save metadata to directory."""
           os.makedirs(dir_metadata, exist_ok=True)
           self.dir_metadata = str(dir_metadata)
           pkl_path = os.path.join(dir_metadata, "metadata.pkl")
           with open(pkl_path, "wb") as f:
               pickle.dump(self, f)

           yaml_path = os.path.join(dir_metadata, "metadata.yaml")
           with open(yaml_path, "w", encoding="utf-8") as f:
               yaml.safe_dump(self.to_dict(), f, default_flow_style=False)

逐段解释：

* 第 L102-L106 行：加载路径固定为 `<dir_metadata>/metadata.pkl`；这解释了
  下游脚本为什么只暴露 `--dir-metadata` 而不重复传所有参数。
* 第 L108-L115 行：保存时先创建目录，再更新 `self.dir_metadata`，然后写
  pickle；pickle 是下游 Python 脚本使用的主格式。
* 第 L117-L119 行：同一份对象还写出 YAML 版本，供人工查看或调试。

接口关系：

* 被调用：`compile_from_metadata()`、`run_from_metadata()`、
  `collect_results.py main()`、`render_config_template.py main()`。
* 调用：标准库 `pickle`、`os.makedirs()`、`yaml.safe_dump()`。
* 共享状态：`metadata.pkl` 是脚本间的共享状态；`metadata.yaml` 是可读镜像。

§2.2 ``TestRunResult`` — 单测结果契约
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：记录一个测试一次 seed 的生成、编译、仿真、日志和统计结果。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L141-L185``）：

.. code-block:: python

   @dataclass
   class TestRunResult:
       """Result of a single test run."""
       test_name: str = ""
       seed: int = 0
       test_type: str = ""
       passed: bool = False
       failure_mode: str = "UNKNOWN"

       # Paths
       work_dir: str = ""
       assembly_path: str = ""
       binary_path: str = ""
       sim_log_path: str = ""
       uvm_log_path: str = ""
       trace_path: str = ""
       coverage_path: str = ""

       # Statistics
       num_instructions: int = 0
       num_cycles: int = 0
       ipc: float = 0.0

逐段解释：

* 第 L141-L148 行：测试身份和最终状态集中在对象顶部；`failure_mode` 的默认值
  是 `UNKNOWN`，只有日志检查或 pre-sim 失败记录会把它改成具体分类。
* 第 L150-L158 行：路径字段覆盖生成的 assembly、binary、sim log、UVM log、
  trace 和 coverage；`report.json` 会把这些路径导出给 sign-off 和 HTML 报告。
* 第 L160-L163 行：统计字段保存指令数、cycle 数和 IPC；这些值来自
  `check_logs.py` 的 trace/log 解析。

接口关系：

* 被调用：`run_regress.py`、`compile_test.py`、`run_rtl.py`、
  `check_logs.py`、`collect_results.py`。
* 调用：自身 `save()` 和 `load()` 使用 pickle。
* 共享状态：通常保存为 `<test>_<seed>.pkl` 或 `result.pkl`。

§2.3 ``RegressionSummary`` — 回归聚合模型
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把多个 `TestRunResult` 聚合为总数、通过数、失败数和报告格式。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L188-L225``）：

.. code-block:: python

   @dataclass
   class RegressionSummary:
       """Summary of regression run."""
       results: List[TestRunResult] = field(default_factory=list)
       total_tests: int = 0
       passed: int = 0
       failed: int = 0
       total_time_sec: float = 0.0

       def add_result(self, result: TestRunResult):
           """Add a test result."""
           self.results.append(result)
           self.total_tests += 1
           if result.passed:
               self.passed += 1
           else:
               self.failed += 1
           self.total_time_sec += (
               result.gen_time_sec + result.compile_time_sec +
               result.sim_time_sec
           )

逐段解释：

* 第 L188-L194 行：summary 只保存结果列表和计数，不重新执行任何测试。
* 第 L196-L205 行：`add_result()` 是唯一累加入口；它根据 `result.passed`
  同步更新 passed/failed，并累加生成、编译和仿真耗时。

接口关系：

* 被调用：`collect_results()` 逐个 pickle 调用；`summary_from_report_json()`
  从 JSON 还原时也构造该对象。
* 调用：`to_log()` 和 `to_junit_xml()` 生成报告。
* 共享状态：最终被 `report.json`、`regr.log`、`regr_junit.xml` 表达。

§2.4 ``create_metadata()`` — 创建 metadata 目录
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 CLI 参数和 testlist 展开测试集合，并写出 metadata。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L379-L417``）：

.. code-block:: python

   def create_metadata(dir_metadata: str, dir_out: str,
                       testlist: str = "", test: str = "",
                       iterations: int = 1, seed: int = 1,
                       simulator: str = "vcs", **kwargs) -> RegressionMetadata:
       """Create and save regression metadata."""
       md = RegressionMetadata()
       md.dir_metadata = dir_metadata
       md.dir_out = dir_out
       md.dir_tests = os.path.join(dir_out, "tests")
       md.work_dir = os.path.join(dir_out, "work")
       md.build_dir = os.path.join(dir_out, "build")
       md.out_dir = dir_out

       # Infer EH2 root from script location
       script_dir = Path(__file__).resolve().parent
       md.eh2_root = str(script_dir.parents[3])

       md.testlist = testlist
       md.test = test
       md.iterations = iterations
       md.seed = seed
       md.simulator = simulator

逐段解释：

* 第 L379-L385 行：函数参数把输出目录、testlist、单测选择、迭代次数、seed
  和模拟器作为核心输入。
* 第 L386-L392 行：metadata 内部派生 `dir_tests`、`work_dir`、`build_dir`；
  这些目录名是固定约定。
* 第 L395-L396 行：EH2 根目录由脚本位置向上推导，不依赖当前 shell 的工作目录。
* 第 L398-L402 行：原始选择参数也保存在 metadata 中，便于后续脚本判断
  当前是 testlist 模式还是单测模式。

接口关系：

* 被调用：`metadata.py main()`。
* 调用：`_select_test_entries()`、`save()`。
* 共享状态：写 `dir_metadata/metadata.pkl`、`dir_metadata/metadata.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L419-L451``）：

.. code-block:: python

       for key, value in kwargs.items():
           if hasattr(md, key):
               setattr(md, key, value)

       selected = _select_test_entries(md, testlist, test, iterations)
       md.tests_and_counts = [
           (entry["test"], count, entry.get("test_type", md.test_type))
           for entry, count in selected
       ]
       md.test_entries = [entry for entry, _ in selected]
       md.riscvdv_tests_and_counts = _tds_for_type(md, "RISCVDV")
       md.directed_tests_and_counts = _tds_for_type(md, "DIRECTED")

       # Create directories
       os.makedirs(md.dir_metadata, exist_ok=True)
       os.makedirs(md.dir_tests, exist_ok=True)
       os.makedirs(md.work_dir, exist_ok=True)

       md.save(dir_metadata)
       return md

逐段解释：

* 第 L419-L421 行：`kwargs` 只写入 `RegressionMetadata` 已有字段，避免向对象塞入
  未定义属性。
* 第 L423-L430 行：测试选择结果被拆成通用 `tests_and_counts`、完整 entry 列表、
  riscv-dv 列表和 directed 列表；下游可按类型分流。
* 第 L433-L435 行：metadata、tests、work 三个目录在创建阶段就保证存在。
* 第 L437-L438 行：最终落盘并返回对象。

接口关系：

* 被调用：CLI `--create` 路径。
* 调用：`_select_test_entries()`、`_tds_for_type()`、`os.makedirs()`。
* 共享状态：`md.tests_and_counts` 被 `run_regress.py` 作为回归矩阵来源。

§3 ``run_regress.py`` — 单测和回归编排
--------------------------------------------------------------------------------

`run_regress.py` 是普通回归入口。它支持直接跑单个 binary，也支持从 testlist
展开 riscv-dv 和 directed 测试，并可用 `--parallel` 并行执行。

§3.1 ``load_regression_testlist()`` — 读取并标准化 testlist
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 YAML testlist 的 config entry 和 test entry 拆开，并把 directed
schema 中的字段转换为 `run_single_test()` 需要的 dict。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L54-L90``）：

.. code-block:: python

   def load_regression_testlist(testlist_path: str) -> list:
       """Load regression testlist (riscv-dv or directed schema)."""
       with open(testlist_path, "r", encoding="utf-8") as f:
           data = yaml.safe_load(f) or []

       if any(isinstance(entry, dict) and "test_srcs" in entry for entry in data):
           model = directed_test_schema.import_model(Path(testlist_path))
           return [{
               "test": test.test,
               "iterations": test.iterations,
               "test_type": "DIRECTED",
               "test_srcs": test.test_srcs,
               "rtl_test": test.rtl_test,
               "ld_script": test.ld_script,
               "includes": test.includes,
               "sim_opts": "",
           } for test in model.tests]

逐段解释：

* 第 L54-L57 行：testlist 通过 `yaml.safe_load()` 读取，空文件被当成空列表。
* 第 L59-L60 行：只要任一 entry 含 `test_srcs`，脚本就按 directed schema 处理。
* 第 L61-L72 行：directed schema 的 dataclass 被转换成普通 dict，字段包括
  `test`、`iterations`、`test_type`、`test_srcs`、`rtl_test`、`ld_script`、
  `includes` 和 `sim_opts`。

接口关系：

* 被调用：`run_regression()`。
* 调用：`directed_test_schema.import_model()`。
* 共享状态：读 `directed_testlist.yaml`、`cosim_testlist.yaml` 或
  riscv-dv `testlist.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L74-L90``）：

.. code-block:: python

       tests = []
       for entry in data:
           if not isinstance(entry, dict) or "test" not in entry:
               continue
           item = dict(entry)
           item.setdefault("iterations", 1)
           item.setdefault("test_type", "RISCVDV")
           item.setdefault("rtl_test", "core_eh2_base_test")
           item.setdefault("sim_opts", "")
           tests.append(item)

       return tests

逐段解释：

* 第 L74-L77 行：riscv-dv 路径忽略非 dict 或不含 `test` 的 entry。
* 第 L78-L82 行：为缺省字段补默认值；默认测试类型是 `RISCVDV`，默认 UVM test
  是 `core_eh2_base_test`。
* 第 L83-L85 行：标准化后的列表直接交给回归矩阵展开。

接口关系：

* 被调用：`run_regression()`。
* 调用：无下游 helper。
* 共享状态：返回 list[dict] 给 `find_test_entry()` 和矩阵生成逻辑。

§3.2 ``build_sim_opts()`` — 合成 cosim plusarg
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：合并 testlist 和 CLI 的仿真选项，并根据 `cosim` 字段补上
`+enable_cosim=1` 或 `+disable_cosim=1`。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L118-L140``）：

.. code-block:: python

   def build_sim_opts(test_entry: dict, cli_sim_opts: str = "") -> str:
       """Build simulation plusargs from test entry plus CLI overrides."""
       pieces = []
       entry_opts = str(test_entry.get("sim_opts", "") or "").strip()
       if entry_opts:
           pieces.append(entry_opts)
       cli_sim_opts = str(cli_sim_opts or "").strip()
       if cli_sim_opts:
           pieces.append(cli_sim_opts)

       joined = " ".join(pieces)
       if "+enable_cosim=" not in joined and "+disable_cosim=" not in joined:
           cosim = str(test_entry.get("cosim", "enabled")).lower()
           if cosim in ("disabled", "disable", "false", "0", "no", "rtl_only"):
               pieces.append("+disable_cosim=1")
           else:
               pieces.append("+enable_cosim=1")

       return " ".join(piece for piece in pieces if piece).strip()

逐段解释：

* 第 L118-L127 行：testlist 的 `sim_opts` 和 CLI 的 `--sim-opts` 被按顺序拼接；
  空字符串不会进入最终命令。
* 第 L129-L136 行：如果用户没有显式传 cosim plusarg，脚本才读取 `cosim` 字段并补
  `+enable_cosim=1` 或 `+disable_cosim=1`。
* 第 L138-L140 行：最终返回单行字符串，供 `run_rtl.py` 的 `--sim-opts` 使用。

接口关系：

* 被调用：`run_single_test()`。
* 调用：无下游函数。
* 共享状态：读取 testlist entry 的 `cosim` 和 `sim_opts`。

§3.3 ``run_single_test()`` — 单个测试流水线
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：对一个 test/seed 顺序执行生成、编译、仿真和检查，并保存结果。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L203-L249``）：

.. code-block:: python

       if result.test_type == "RISCVDV":
           gen_cmd = [
               sys.executable, str(SCRIPT_DIR / "run_instr_gen.py"),
               "--riscv-dv-dir", riscv_dv_dir,
               "--work-dir", work_dir,
               "--test", test_name,
               "--gen-opts", test_entry.get("gen_opts", ""),
               "--seed", str(seed),
               "--iterations", "1",
           ]
           gen_start = time.time()
           gen_proc = run_captured(gen_cmd, timeout=600)
           result.gen_time_sec = time.time() - gen_start
           write_process_log(os.path.join(work_dir, "instr_gen.process.log"),
                             gen_proc)

逐段解释：

* 第 L203-L212 行：riscv-dv 测试通过子进程调用 `run_instr_gen.py`，传入
  riscv-dv 根目录、工作目录、测试名、生成选项、seed 和单次 iteration。
* 第 L214-L217 行：生成阶段用 `time.time()` 统计耗时，并把子进程 stdout/stderr
  写到 `instr_gen.process.log`。

接口关系：

* 被调用：`run_regression()`。
* 调用：`run_instr_gen.py`、`run_captured()`、`write_process_log()`。
* 共享状态：写 `work_dir` 下生成日志和 riscv-dv assembly。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L251-L320``）：

.. code-block:: python

       compile_cmd = [
           sys.executable, str(SCRIPT_DIR / "compile_test.py"),
           "--asm", asm_path,
           "--bin", bin_path,
           "--hex", hex_path,
           "--gcc-prefix", gcc_prefix,
           "--riscv-dv-dir", riscv_dv_dir,
       ]
       if linker:
           compile_cmd.extend(["--linker", linker])
       for include_dir in include_dirs:
           compile_cmd.extend(["--include-dir", include_dir])

       comp_start = time.time()
       comp_proc = run_captured(compile_cmd, timeout=120)
       result.compile_time_sec = time.time() - comp_start

逐段解释：

* 第 L251-L259 行：编译阶段始终调用 `compile_test.py`，输出 `test.bin` 和
  `test.hex`，并传入 GCC 前缀和 riscv-dv include 根目录。
* 第 L260-L263 行：directed 测试如果声明 linker 或 include 目录，会追加到编译命令。
* 第 L265-L267 行：编译阶段也记录耗时；失败路径会设置 `COMPILE_ERROR` 或
  `COMPILE_TIMEOUT`。

接口关系：

* 被调用：`run_single_test()` 内部。
* 调用：`compile_test.py`。
* 共享状态：写 `test.bin`、`test.hex`、`compile.process.log`。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L288-L320``）：

.. code-block:: python

       sim_opts = build_sim_opts(test_entry, cli_sim_opts)
       run_cmd = [
           sys.executable, str(SCRIPT_DIR / "run_rtl.py"),
           "--test", test_name,
           "--seed", str(seed),
           "--binary", hex_path if os.path.exists(hex_path) else bin_path,
           "--simulator", simulator,
           "--timeout", str(timeout),
           "--rtl-test", rtl_test,
           "--sim-opts", sim_opts,
           "--out-dir", work_dir,
       ]
       if coverage:
           run_cmd.append("--coverage")
       if waves:
           run_cmd.append("--waves")

       sim_start = time.time()
       sim_proc = run_captured(run_cmd, timeout=timeout // 1000000 + 600)

逐段解释：

* 第 L288-L299 行：仿真阶段调用 `run_rtl.py`，优先加载 `test.hex`，没有 hex 时才
  回退到 `test.bin`。
* 第 L300-L304 行：coverage 和 waves 是布尔开关，只有 CLI 请求时才追加。
* 第 L306-L307 行：仿真子进程 timeout 由仿真 ns timeout 换算出一个 wall-clock
  上限并加 600 秒余量。

接口关系：

* 被调用：`run_single_test()` 内部。
* 调用：`build_sim_opts()`、`run_rtl.py`。
* 共享状态：读 `test.hex` 或 `test.bin`；写 `run_rtl.process.log` 和仿真日志。

§3.4 ``run_regression()`` — 测试矩阵和并行执行
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 CLI 选择测试集合和 seed 矩阵，串行或并行调用 `run_single_test()`。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L338-L375``）：

.. code-block:: python

   def run_regression(args) -> RegressionSummary:
       """Run complete regression."""
       os.makedirs(args.output, exist_ok=True)

       # Load testlist or create single test entry
       if args.testlist:
           testlist = load_regression_testlist(args.testlist)
           if args.test:
               test_entry = find_test_entry(testlist, args.test)
               testlist = [test_entry]
       else:
           testlist = [{
               "test": args.test or "smoke",
               "iterations": 1,
               "test_type": "DIRECTED" if args.binary else "RISCVDV",
               "rtl_test": args.rtl_test,
           }]

逐段解释：

* 第 L338-L341 行：回归入口先确保输出目录存在。
* 第 L344-L350 行：有 testlist 时读取完整列表；如果同时指定 `--test`，再过滤到
  单个 entry。
* 第 L351-L357 行：没有 testlist 时构造单测 entry；指定 `--binary` 时视为
  directed，未指定 binary 时视为 riscv-dv。

接口关系：

* 被调用：`main()`。
* 调用：`load_regression_testlist()`、`find_test_entry()`。
* 共享状态：读取 CLI `args`；写输出目录。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L381-L415``）：

.. code-block:: python

       if args.parallel > 1:
           with ProcessPoolExecutor(max_workers=args.parallel) as executor:
               futures = [
                   executor.submit(run_single_test, entry, seed, args.simulator,
                                   args.output, args.riscv_dv_dir,
                                   args.gcc_prefix, args.coverage, args.waves,
                                   args.timeout, args.fail_on_warnings,
                                   args.sim_opts)
                   for entry, seed in test_matrix
               ]
               for future in as_completed(futures):
                   summary.add_result(future.result())
       else:
           for entry, seed in test_matrix:
               result = run_single_test(
                   entry, seed, args.simulator, args.output,
                   args.riscv_dv_dir, args.gcc_prefix,
                   args.coverage, args.waves, args.timeout,
                   args.fail_on_warnings, args.sim_opts)
               summary.add_result(result)

逐段解释：

* 第 L381-L392 行：`--parallel` 大于 1 时，每个 `entry, seed` 作为独立任务提交给
  `ProcessPoolExecutor`，返回后逐个加入 summary。
* 第 L393-L402 行：串行模式按矩阵顺序调用 `run_single_test()`。
* 第 L404-L415 行之后的代码会写 reports，并在 coverage 时复制 coverage DB；
  这保证 sign-off collector 可以从 stage 输出目录找到统一报告。

接口关系：

* 被调用：`main()`。
* 调用：`run_single_test()`、`RegressionSummary.add_result()`。
* 共享状态：每个 worker 写独立 `work_dir`，summary 在主进程聚合。

§4 ``run_instr_gen.py`` 与 ``riscvdv_interface.py`` — riscv-dv 命令封装
--------------------------------------------------------------------------------

这两个脚本都围绕 riscv-dv 命令构造。`run_instr_gen.py` 直接执行生成；`riscvdv_interface.py`
提供可复用的命令构造 helper。

§4.1 ``build_sim_opts()`` — EH2 generator plusarg
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：给 riscv-dv generator 注入 EH2 自定义 asm program generator 和 signature
地址要求。

关键代码（``dv/uvm/core_eh2/scripts/run_instr_gen.py:L24-L35``）：

.. code-block:: python

   DEFAULT_TESTLIST = os.path.join(EXT_DIR, "testlist.yaml")
   EH2_SIGNATURE_ADDR = "d0580000"


   def build_sim_opts() -> str:
       """Build riscv-dv generator simulator plusargs for EH2 customizations."""
       return " ".join([
           "+uvm_set_inst_override=riscv_asm_program_gen,"
           "eh2_asm_program_gen,uvm_test_top.asm_gen",
           "+require_signature_addr=1",
           f"+signature_addr={EH2_SIGNATURE_ADDR}",
       ])

逐段解释：

* 第 L24-L25 行：默认 testlist 来自 EH2 riscv-dv extension；signature 地址常量为
  `d0580000`。
* 第 L28-L35 行：plusarg 替换 riscv-dv 默认 asm generator 为
  `eh2_asm_program_gen`，并要求使用指定 signature 地址。

接口关系：

* 被调用：`run_instr_gen()` 构造 `--sim_opts`。
* 调用：无下游函数。
* 共享状态：读取模块级常量 `EH2_SIGNATURE_ADDR`。

§4.2 ``write_overlay_testlist()`` — 单次生成 testlist
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从默认 testlist 中抽取一个测试，合并 CLI 生成选项，写成 per-run YAML。

关键代码（``dv/uvm/core_eh2/scripts/run_instr_gen.py:L50-L68``）：

.. code-block:: python

   def write_overlay_testlist(work_dir: str, test_name: str,
                              extra_gen_opts: str = "") -> str:
       """Create a per-run testlist that carries CLI generator plusargs."""
       entry = load_test_entry(DEFAULT_TESTLIST, test_name)
       entry["iterations"] = 1

       base_opts = str(entry.get("gen_opts", "") or "").strip()
       extra_gen_opts = (extra_gen_opts or "").strip()
       entry["gen_opts"] = " ".join(
           opt for opt in [base_opts, extra_gen_opts] if opt
       )

       overlay_path = os.path.join(work_dir, "riscv_dv_testlist.yaml")
       with open(overlay_path, "w") as f:
           yaml.safe_dump([entry], f, default_flow_style=False, sort_keys=False)
       return overlay_path

逐段解释：

* 第 L50-L54 行：函数先读取默认 testlist 中的目标测试，并强制本次 overlay 的
  `iterations` 为 1。
* 第 L56-L63 行：原 testlist 的 `gen_opts` 和 CLI 传入的 `extra_gen_opts` 会先
  `strip()`，再以空格合并。
* 第 L65-L68 行：overlay 写到 `work_dir/riscv_dv_testlist.yaml`，供 riscv-dv
  `run.py --testlist` 使用。

接口关系：

* 被调用：`run_instr_gen()`。
* 调用：`load_test_entry()`、`yaml.safe_dump()`。
* 共享状态：读 extension `testlist.yaml`，写 per-run overlay YAML。

§4.3 ``run_instr_gen()`` — 执行 riscv-dv ``run.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：构造并执行 riscv-dv 生成命令，把 stdout 写入生成日志。

关键代码（``dv/uvm/core_eh2/scripts/run_instr_gen.py:L91-L116``）：

.. code-block:: python

       riscv_dv_run = os.path.join(riscv_dv_dir, "run.py")
       if not os.path.exists(riscv_dv_run):
           print(f"Error: riscv-dv run.py not found at {riscv_dv_run}")
           return False

       testlist_path = write_overlay_testlist(work_dir, test_name, gen_opts)

       cmd = [
           sys.executable, riscv_dv_run,
           "--test", test_name,
           "--target", "rv32imc",
           "-o", work_dir,
           "--steps", "gen",
           "--seed", str(seed),
           "--iterations", str(iterations),
           "--isa", "rv32imac",
           "--mabi", "ilp32",
           "--testlist", testlist_path,
           "--sim_opts", build_sim_opts(),
       ]

逐段解释：

* 第 L91-L95 行：脚本显式检查 `run.py` 是否存在；不存在时返回 `False`。
* 第 L97 行：每次生成都使用 overlay testlist，而不是直接修改默认 testlist。
* 第 L99-L111 行：命令使用当前 Python 解释器运行 riscv-dv `run.py`，目标是
  `rv32imc`，ISA 是 `rv32imac`，步骤限定为 `gen`。

接口关系：

* 被调用：CLI main 或 `run_from_metadata()`。
* 调用：`write_overlay_testlist()`、`build_sim_opts()`、`subprocess.run()`。
* 共享状态：写 `<work_dir>/<test>_gen.log`。

§4.4 ``riscvdv_interface.get_run_cmd()`` — 可复用生成命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：返回 riscv-dv 生成命令列表，不直接执行。

关键代码（``dv/uvm/core_eh2/scripts/riscvdv_interface.py:L24-L75``）：

.. code-block:: python

   def get_run_cmd(test: str, seed: int, iterations: int = 1,
                   gen_opts: str = "", isa: str = "rv32imac",
                   mabi: str = "ilp32", output_dir: str = "") -> list:
       """Build command to run riscv-dv instruction generator."""
       run_py = os.path.join(RISCV_DV_DIR, "run.py")

       cmd = [
           sys.executable, run_py,
           "--test", test,
           "--target", "rv32imc",
           "--seed", str(seed),
           "--iterations", str(iterations),
           "--steps", "gen",
           "--isa", isa,
           "--mabi", mabi,
       ]

逐段解释：

* 第 L24-L26 行：函数参数暴露 test、seed、iteration、generator 选项、ISA、ABI
  和输出目录。
* 第 L42-L53 行：基础命令只包含 riscv-dv `run.py` 的通用参数，不含 EH2 extension
  和 CSR YAML；这些在后续条件分支中追加。

接口关系：

* 被调用：`build_instr_gen.py`。
* 调用：无执行调用，只返回 list。
* 共享状态：读取模块级 `RISCV_DV_DIR`、`EXT_DIR`。

关键代码（``dv/uvm/core_eh2/scripts/riscvdv_interface.py:L55-L75``）：

.. code-block:: python

       if os.path.exists(os.path.join(EXT_DIR, "user_extension.svh")):
           cmd.extend(["--custom_target", EXT_DIR])

       testlist = os.path.join(EXT_DIR, "testlist.yaml")
       if os.path.exists(testlist):
           cmd.extend(["--testlist", testlist])

       csr_yaml = os.path.join(EXT_DIR, "csr_description.yaml")
       if os.path.exists(csr_yaml):
           cmd.extend(["--csr_yaml", csr_yaml])

       if output_dir:
           cmd.extend(["-o", output_dir])

       if gen_opts:
           cmd.extend(gen_opts.split())

       return cmd

逐段解释：

* 第 L55-L57 行：存在 `user_extension.svh` 时追加 `--custom_target`。
* 第 L60-L67 行：存在 testlist 和 CSR 描述 YAML 时分别追加 `--testlist` 和
  `--csr_yaml`。
* 第 L69-L73 行：输出目录和生成选项都是可选追加项；`gen_opts` 通过 `split()`
  展开为多个 argv。

接口关系：

* 被调用：`build_instr_gen.py main()`。
* 调用：`os.path.exists()`。
* 共享状态：读 extension 目录中的文件是否存在。

§5 ``compile_test.py`` — Assembly 到 binary/hex
--------------------------------------------------------------------------------

`compile_test.py` 把 riscv-dv 生成或 directed 提供的 assembly 编译为 RTL simulation
可加载的 `test.bin` 和按 VMA 标注的 `test.hex`。

§5.1 ``compile_from_metadata()`` — metadata 模式编译入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 `TEST.SEED` 从 metadata 中定位测试目录，判断是 directed 还是
riscv-dv，并准备 linker/include 参数。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L97-L127``）：

.. code-block:: python

   def compile_from_metadata(dir_metadata: str, test_dot_seed: str) -> bool:
       """Compile one test.seed using Ibex-style metadata."""
       md = RegressionMetadata.construct_from_metadata_dir(Path(dir_metadata))
       test_name, seed = read_test_dot_seed(test_dot_seed)
       test_dir = Path(md.dir_tests) / test_dot_seed
       test_dir.mkdir(parents=True, exist_ok=True)

       entry = directed_entry(md, test_name)
       include_dirs = []
       if entry is not None:
           asm_path = Path(md.eh2_root) / "dv" / "uvm" / "core_eh2" / entry.test_srcs
           generated_asm = test_dir / "test.S"
           if not generated_asm.exists():
               generated_asm.write_text(
                   Path(asm_path).read_text(encoding="utf-8"),
                   encoding="utf-8")
           linker = entry.ld_script or ""

逐段解释：

* 第 L97-L103 行：metadata 模式只需要 metadata 目录和 `TEST.SEED` 字符串；
  `read_test_dot_seed()` 解析出 test name 和 seed。
* 第 L104-L113 行：如果 directed testlist 中有该测试，脚本把源 `.S` 复制到
  per-test 目录的 `test.S`，以便后续流程路径一致。
* 第 L113-L127 行：directed entry 可以提供 linker 和 include；没有 directed
  entry 时则转入 riscv-dv generated assembly 查找。

接口关系：

* 被调用：`compile_test.py main()` 的 `--dir-metadata` 分支。
* 调用：`RegressionMetadata.construct_from_metadata_dir()`、
  `read_test_dot_seed()`、`directed_entry()`、`compile_assembly()`。
* 共享状态：读 metadata 和 testlist；写 per-test `test.S`、`compile.log`。

§5.2 ``resolve_riscv_dv_dir()`` — include 根目录解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 CLI 参数、环境变量、仓库 vendor 和固定路径之间选择一个可用的
riscv-dv 根目录。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L156-L187``）：

.. code-block:: python

   def _looks_like_riscv_dv_dir(path: str) -> bool:
       """Return true when path can provide riscv-dv generated ASM includes."""
       return (
           os.path.exists(os.path.join(path, "run.py")) or
           os.path.exists(os.path.join(path, "user_extension", "user_define.h")) or
           os.path.exists(os.path.join(path, "user_extension", "user_init.s"))
       )


   def resolve_riscv_dv_dir(riscv_dv_dir: str = "") -> str:
       """Resolve the riscv-dv root used for assembly include files."""
       candidates = [
           riscv_dv_dir,
           os.environ.get("RISCV_DV_DIR", ""),
           os.path.join(EH2_ROOT, "vendor", "google_riscv-dv"),
           "/home/host/riscv-dv",
       ]

逐段解释：

* 第 L156-L162 行：目录只要含 `run.py`、`user_define.h` 或 `user_init.s` 之一，
  就被认为能提供 riscv-dv assembly include。
* 第 L165-L172 行：候选顺序从显式参数开始，然后是 `RISCV_DV_DIR` 环境变量，
  再到仓库 `vendor/google_riscv-dv` 和 `/home/host/riscv-dv`。

接口关系：

* 被调用：`default_include_dirs()`。
* 调用：`_looks_like_riscv_dv_dir()`。
* 共享状态：读取环境变量 `RISCV_DV_DIR`。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L173-L187``）：

.. code-block:: python

       for candidate in candidates:
           if candidate and _looks_like_riscv_dv_dir(candidate):
               return os.path.realpath(candidate)
       return ""


   def default_include_dirs(riscv_dv_dir: str = "") -> list:
       """Return include dirs needed by riscv-dv generated assembly."""
       include_dirs = []
       resolved_riscv_dv_dir = resolve_riscv_dv_dir(riscv_dv_dir)
       if resolved_riscv_dv_dir:
           _append_existing_dir(
               include_dirs, os.path.join(resolved_riscv_dv_dir, "user_extension"))
       _append_existing_dir(include_dirs, EXT_DIR)
       return include_dirs

逐段解释：

* 第 L173-L176 行：候选目录按顺序短路返回；没有命中时返回空字符串。
* 第 L179-L187 行：include 列表先尝试 riscv-dv `user_extension`，再追加 EH2
  `riscv_dv_extension`；`_append_existing_dir()` 会去重并忽略不存在目录。

接口关系：

* 被调用：`compile_assembly()`。
* 调用：`resolve_riscv_dv_dir()`、`_append_existing_dir()`。
* 共享状态：读取 `EXT_DIR` 常量。

§5.3 ``write_vma_hex_from_elf()`` — 生成 VMA 标注 hex
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 `objdump -h` 找出 loadable sections，并按 section VMA 写出 Verilog
hex 文件。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L223-L265``）：

.. code-block:: python

   def write_vma_hex_from_elf(elf_path: str, hex_path: str,
                              gcc_prefix: str = "riscv32-unknown-elf") -> bool:
       """Write a byte-addressed verilog hex file using section VMAs."""
       objdump = f"{gcc_prefix}-objdump"
       result = subprocess.run(
           [objdump, "-h", elf_path],
           stdout=subprocess.PIPE,
           stderr=subprocess.STDOUT,
           timeout=30
       )
       if result.returncode != 0:
           output = result.stdout.decode("utf-8", errors="replace")
           print(f"objdump failed:\n{output}")
           return False

逐段解释：

* 第 L223-L231 行：函数通过 `<gcc_prefix>-objdump -h` 获取 ELF section 表；
  stdout 和 stderr 合并保存到内存。
* 第 L233-L236 行：objdump 失败时打印输出并返回 `False`，不继续写 hex。

接口关系：

* 被调用：`compile_assembly()` 的 `hex_path` 分支。
* 调用：`subprocess.run()`、`_parse_objdump_sections()`。
* 共享状态：读 `elf_path`，写 `hex_path`。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L238-L265``）：

.. code-block:: python

       sections = _parse_objdump_sections(
           result.stdout.decode("utf-8", errors="replace"))
       if not sections:
           print("Error: ELF has no loadable sections for hex generation")
           return False

       with open(elf_path, "rb") as elf_fd:
           elf_data = elf_fd.read()

       hex_dir = os.path.dirname(hex_path)
       if hex_dir:
           os.makedirs(hex_dir, exist_ok=True)

       with open(hex_path, "w") as hex_fd:
           for section in sections:
               start = section["file_off"]
               end = start + section["size"]

逐段解释：

* 第 L238-L242 行：section 解析结果为空会直接失败；这避免产生没有装载地址的 hex。
* 第 L244-L249 行：函数一次性读取 ELF，并确保 hex 输出目录存在。
* 第 L251-L255 行：每个 section 根据 file offset 和 size 切出原始字节；后续代码
  用 `@%08X` 写 VMA 地址，再每 16 字节写一行。

接口关系：

* 被调用：`compile_assembly()`。
* 调用：`_parse_objdump_sections()`。
* 共享状态：依赖 objdump section 元数据中的 `file_off`、`size`、`vma`。

§5.4 ``compile_assembly()`` — GCC/objcopy 编译管线
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：将 assembly 编译为 ELF，再用 objcopy 生成 binary，可选生成 VMA hex。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L268-L318``）：

.. code-block:: python

   def compile_assembly(asm_path: str, bin_path: str, linker_script: str,
                        gcc_prefix: str = "riscv32-unknown-elf",
                        include_dirs: list = None,
                        riscv_dv_dir: str = "",
                        hex_path: str = "") -> bool:
       """Compile RISC-V assembly to binary."""
       bin_dir = os.path.dirname(bin_path)
       if bin_dir:
           os.makedirs(bin_dir, exist_ok=True)

       gcc = f"{gcc_prefix}-gcc"
       objcopy = f"{gcc_prefix}-objcopy"

       obj_path = bin_path.replace(".bin", ".o")
       elf_path = bin_path.replace(".bin", ".elf")
       del obj_path

逐段解释：

* 第 L268-L272 行：函数输入包含 asm、binary、linker、GCC 前缀、include 目录、
  riscv-dv 根目录和 hex 输出路径。
* 第 L285-L294 行：输出目录先创建；工具名由 GCC 前缀拼出；ELF 路径由 bin 路径
  替换后缀获得。
* 第 L295 行：`obj_path` 被创建后立即删除变量，说明当前实现不保留独立 object
  文件路径。

接口关系：

* 被调用：`compile_from_metadata()` 和 CLI 直接模式。
* 调用：`default_include_dirs()`、`subprocess.run()`、
  `write_vma_hex_from_elf()`。
* 共享状态：读 assembly 和 linker；写 ELF、bin、hex。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L297-L318``）：

.. code-block:: python

       compile_include_dirs = default_include_dirs(riscv_dv_dir)
       for include_dir in include_dirs or []:
           _append_existing_dir(compile_include_dirs, include_dir)
       include_opts = [f"-I{include_dir}" for include_dir in compile_include_dirs]

       compile_cmd = [
           gcc,
           "-march=rv32imac_zba_zbb",
           "-mabi=ilp32",
           "-static",
           "-mcmodel=medany",
           "-fvisibility=hidden",
           "-nostdlib",
           "-nostartfiles",
           *include_opts,
           "-T", linker_script,
           "-o", elf_path,
           asm_path,
       ]

逐段解释：

* 第 L297-L300 行：include 目录先放默认 riscv-dv/EH2 extension，再追加调用方传入的
  include 目录。
* 第 L302-L318 行：GCC 命令固定使用 `rv32imac_zba_zbb`、`ilp32`、静态链接、
  `medany` code model，并用 `-nostdlib -nostartfiles` 避免标准启动文件。

接口关系：

* 被调用：`compile_assembly()` 内部。
* 调用：`default_include_dirs()`。
* 共享状态：读取 include 目录、linker script 和 asm 文件路径。

关键代码（``dv/uvm/core_eh2/scripts/compile_test.py:L322-L370``）：

.. code-block:: python

       try:
           result = subprocess.run(
               compile_cmd,
               stdout=subprocess.PIPE,
               stderr=subprocess.STDOUT,
               timeout=60
           )

           if result.returncode != 0:
               output = result.stdout.decode("utf-8", errors="replace")
               print(f"Compilation failed:\n{output}")
               return False

           objcopy_cmd = [
               objcopy,
               "-O", "binary",
               elf_path,
               bin_path,
           ]

逐段解释：

* 第 L322-L328 行：GCC 编译 timeout 为 60 秒，stdout/stderr 合并捕获。
* 第 L330-L333 行：非零返回码会打印编译输出并返回失败。
* 第 L336-L341 行：ELF 到 raw binary 的转换由 `<gcc_prefix>-objcopy -O binary`
  完成。

接口关系：

* 被调用：`compile_assembly()` 内部。
* 调用：`subprocess.run()`。
* 共享状态：依赖 `compile_cmd` 和 `objcopy_cmd` 的返回码。

§6 ``run_rtl.py`` 与 ``compile_tb.py`` — RTL 仿真命令层
--------------------------------------------------------------------------------

`run_rtl.py` 根据 metadata 或直接 CLI 执行一次 RTL 仿真。`compile_tb.py` 是
metadata 驱动的 testbench 编译命令构造脚本。

§6.1 ``build_sim_cmd()`` — simulator YAML 变量替换
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 `rtl_simulation.yaml` 中选择模拟器命令，并替换 `<build_dir>`、
`<out_dir>`、`<test>`、`<seed>` 等变量。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L54-L85``）：

.. code-block:: python

   def build_sim_cmd(md: RegressionMetadata, sim_cfg: dict) -> str:
       """Build the simulation command."""
       cfg = sim_cfg.get(md.simulator, sim_cfg.get("vcs", {}))
       sim_cfg_inner = cfg.get("sim", {})

       variables = {
           "build_dir": md.build_dir,
           "out_dir": md.out_dir,
           "test": md.test_name,
           "seed": md.seed,
           "binary": md.binary_path,
           "rtl_test": md.rtl_test or "core_eh2_base_test",
           "sim_opts": md.sim_opts or "",
           "timeout": md.sim_time_ns if md.sim_time_ns > 0 else 10000000,
           "uvm_verbosity": "UVM_MEDIUM",
       }

逐段解释：

* 第 L54-L57 行：模拟器配置优先取 `md.simulator`，不存在时回退到 `vcs`。
* 第 L59-L69 行：变量字典把 metadata 字段映射到 YAML command placeholder；
  `rtl_test` 和 timeout 都有默认值。

接口关系：

* 被调用：`run_rtl_simulation()`。
* 调用：`substitute_vars()`。
* 共享状态：读取 `RegressionMetadata` 的 build、out、test、seed、binary 等字段。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L71-L85``）：

.. code-block:: python

       cmd = sim_cfg_inner.get("cmd", "")
       if not cmd:
           raise ValueError(
               f"No simulation command configured for simulator '{md.simulator}'")
       if md.coverage:
           cmd += " " + sim_cfg_inner.get("cov_opts", "")
       if md.waves:
           cmd += " " + sim_cfg_inner.get("wave_opts", "")

       cmd = substitute_vars(cmd, variables)
       cmd = " ".join(cmd.split())
       return cmd

逐段解释：

* 第 L71-L74 行：缺少 simulator command 时抛 `ValueError`，上层会记录为
  `CONFIG_ERROR`。
* 第 L75-L78 行：coverage 和 waves 只在 metadata 标志为真时追加对应 YAML 选项。
* 第 L80-L85 行：变量替换后压缩空白，避免 YAML 多行字符串破坏 shell 命令。

接口关系：

* 被调用：`run_rtl_simulation()`。
* 调用：`substitute_vars()`。
* 共享状态：读 simulator YAML 中 `sim.cmd`、`cov_opts`、`wave_opts`。

§6.2 ``run_rtl_simulation()`` — 一次 RTL 仿真
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：加载 simulator 配置，必要时编译 VCS simv，执行仿真并用 `check_sim_log()`
判定结果。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L107-L149``）：

.. code-block:: python

   def run_rtl_simulation(md: RegressionMetadata) -> TestRunResult:
       """Run a single RTL simulation."""
       if not md.eh2_root:
           md.eh2_root = str(EH2_ROOT)
       if not md.build_dir:
           md.build_dir = os.path.join(md.eh2_root, "build")
       if not md.out_dir:
           md.out_dir = os.path.join(md.eh2_root, "build", f"{md.test_name}_{md.seed}")

       trr = TestRunResult()
       trr.test_name = md.test_name
       trr.seed = md.seed
       trr.test_type = md.test_type

逐段解释：

* 第 L107-L114 行：缺省根目录、build 目录和 out 目录会在函数内补齐。
* 第 L116-L120 行：返回对象先写入 test name、seed 和 test type；路径和状态
  后续逐步补充。

接口关系：

* 被调用：`run_from_metadata()` 和 CLI 直接模式。
* 调用：`load_sim_config()`、`build_compile_cmd()`、`build_sim_cmd()`、
  `run_command()`、`check_sim_log()`。
* 共享状态：读 `rtl_simulation.yaml`，写 per-test log。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L121-L175``）：

.. code-block:: python

       sim_cfg_path = os.path.join(md.eh2_root, "dv", "uvm", "core_eh2", "yaml", "rtl_simulation.yaml")
       if os.path.exists(sim_cfg_path):
           sim_cfg = load_sim_config(sim_cfg_path) or {}
       else:
           trr.failure_mode = "CONFIG_ERROR"
           trr.sim_log_path = os.path.join(
               md.out_dir, f"sim_{md.test_name}_{md.seed}.log")
           os.makedirs(md.out_dir, exist_ok=True)
           with open(trr.sim_log_path, "w") as log_f:
               log_f.write(f"ERROR: simulator config not found: {sim_cfg_path}\n")
           return trr

逐段解释：

* 第 L121-L124 行：simulator 配置路径固定在
  `dv/uvm/core_eh2/yaml/rtl_simulation.yaml`。
* 第 L125-L132 行：配置缺失时不抛异常，而是写一份 sim log，并把结果标记为
  `CONFIG_ERROR`。

接口关系：

* 被调用：`run_rtl_simulation()` 内部。
* 调用：`load_sim_config()`。
* 共享状态：读取 YAML 配置文件。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L151-L175``）：

.. code-block:: python

       try:
           sim_cmd = build_sim_cmd(md, sim_cfg)
       except ValueError as err:
           trr.failure_mode = "CONFIG_ERROR"
           with open(trr.sim_log_path, "w") as log_f:
               log_f.write(f"ERROR: {err}\n")
           return trr
       trr.sim_cmd = sim_cmd
       rc = run_command(sim_cmd, trr.sim_log_path, timeout=600)
       trr.sim_returncode = rc

       checked = check_sim_log(trr.sim_log_path, trr.trace_path,
                               sim_returncode=rc)
       trr.passed = checked.passed
       trr.failure_mode = checked.failure_mode

逐段解释：

* 第 L151-L158 行：命令构造失败同样归类为 `CONFIG_ERROR`，并写入 sim log。
* 第 L159-L161 行：实际仿真 timeout 为 600 秒，返回码保存到 `sim_returncode`。
* 第 L165-L175 行：仿真返回码不是唯一判据；脚本调用 `check_sim_log()` 读取
  pass signature、UVM 错误、trace 和 cycle 统计。

接口关系：

* 被调用：`run_rtl_simulation()` 内部。
* 调用：`build_sim_cmd()`、`run_command()`、`check_sim_log()`。
* 共享状态：读 sim log 和 trace；写 `TestRunResult` 字段。

§6.3 ``_merge_sim_opts()`` — metadata 模式 cosim 选项
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：metadata 模式下合并 test entry 和全局 `sim_opts`，并补齐 cosim plusarg。

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L184-L201``）：

.. code-block:: python

   def _merge_sim_opts(test_entry: dict, global_sim_opts: str) -> str:
       pieces = []
       _append_opt(pieces, test_entry.get("sim_opts", ""))
       _append_opt(pieces, global_sim_opts)

       joined = " ".join(pieces).strip()
       has_cosim_plusarg = (
           "+enable_cosim=" in joined or
           "+disable_cosim=" in joined
       )
       if not has_cosim_plusarg:
           cosim = str(test_entry.get("cosim", "enabled")).lower()
           if cosim in ("disabled", "disable", "false", "0", "no", "rtl_only"):
               pieces.append("+disable_cosim=1")
           else:
               pieces.append("+enable_cosim=1")

       return " ".join(piece for piece in pieces if piece).strip()

逐段解释：

* 第 L184-L188 行：先追加 test entry 选项，再追加 metadata 全局选项。
* 第 L190-L193 行：如果任一来源已经包含 cosim plusarg，函数不再覆盖。
* 第 L194-L199 行：没有显式 plusarg 时，根据 `cosim` 字段追加启用或禁用 cosim。

接口关系：

* 被调用：`run_from_metadata()`。
* 调用：`_append_opt()`。
* 共享状态：读取 metadata 里的全局 `sim_opts` 和 test entry 的 `cosim`。

§6.4 ``compile_tb.get_compile_cmd()`` — TB 编译命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 simulator 构造 testbench 编译命令。

关键代码（``dv/uvm/core_eh2/scripts/compile_tb.py:L23-L49``）：

.. code-block:: python

   def get_compile_cmd(md: RegressionMetadata) -> list:
       """Build the compilation command based on simulator type."""
       eh2_root = Path(__file__).resolve().parents[4]
       core_eh2 = eh2_root / 'dv' / 'uvm' / 'core_eh2'

       if md.simulator == 'vcs':
           cmd = [
               'vcs', '-full64',
               '-sverilog',
               '-ntb_opts', 'uvm-1.2',
               '-timescale=1ns/1ps',
               '-debug_access+all',
               '-kdb',
               '-l', os.path.join(md.work_dir, 'compile.log'),
               '-Mdir={}'.format(os.path.join(md.work_dir, 'csrc')),
           ]

逐段解释：

* 第 L23-L27 行：EH2 根目录由脚本路径向上推导，core UVM 目录固定为
  `dv/uvm/core_eh2`。
* 第 L28-L38 行：VCS 命令包含 `-full64`、SystemVerilog、UVM 1.2、timescale、
  debug/KDB、compile log 和 `csrc` 目录。

接口关系：

* 被调用：`compile_tb.py main()`。
* 调用：无下游 helper。
* 共享状态：读取 `md.simulator` 和 `md.work_dir`。

关键代码（``dv/uvm/core_eh2/scripts/compile_tb.py:L39-L76``）：

.. code-block:: python

           cmd += ['-f', str(core_eh2 / 'eh2_rtl.f')]
           cmd += ['-f', str(core_eh2 / 'eh2_shared.f')]
           cmd += ['-f', str(core_eh2 / 'eh2_tb.f')]
           cmd += ['+incdir+{}'.format(core_eh2 / 'riscv_dv_extension')]
           cmd += ['-CFLAGS', '-std=c++17']
           cmd += ['-o', os.path.join(md.work_dir, 'simv')]

       elif md.simulator == 'xlm':
           cmd = [
               'xrun', '-64bit',
               '-uvm',
               '-sv',
               '-timescale', '1ns/1ps',
               '-l', os.path.join(md.work_dir, 'compile.log'),
           ]

逐段解释：

* 第 L39-L48 行：VCS 分支追加 RTL、shared、TB 三个 filelist、riscv-dv extension
  include、C++17 CFLAGS 和 simv 输出路径。
* 第 L50-L57 行：Xcelium 分支使用 `xrun -64bit -uvm -sv` 并写 compile log。
* 第 L63-L74 行：Questa 分支使用 `vlog -sv`；未知 simulator 会抛 `ValueError`。

接口关系：

* 被调用：`compile_tb.py main()`。
* 调用：标准路径拼接。
* 共享状态：读 filelist 路径，不修改 RTL 或 filelist。

§7 ``check_logs.py`` — 仿真日志判定
--------------------------------------------------------------------------------

`check_logs.py` 将 simulator/UVM 日志转换为 `TestRunResult`。它要求明确的 pass
signature，零返回码本身不能代表测试通过。

§7.1 ``check_uvm_log()`` — UVM 和工具错误分类
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解析 UVM summary、真实 UVM fatal/error/warning、工具 crash/timeout 和
测试 pass/fail 文本。

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L23-L47``）：

.. code-block:: python

   UVM_SUMMARY_RE = re.compile(
       r"^\s*(UVM_WARNING|UVM_ERROR|UVM_FATAL)\s*:\s*(\d+)\b")

   UVM_SUMMARY_LINE_RE = re.compile(
       r"^\s*(UVM_WARNING|UVM_ERROR|UVM_FATAL)"
       r"(\s*:|\s+(?=V\s*C\s*S\b))")

   TOOL_WARNING_RE = re.compile(r"\bWarning-\[")
   TOOL_CRASH_RE = re.compile(
       r"(An unexpected termination|Segmentation fault|Fatal signal|core dumped|"
       r"Stack trace follows)",
       re.IGNORECASE)
   TOOL_TIMEOUT_RE = re.compile(
       r"(Command timed out|Simulation timeout|Wall-clock timeout)",
       re.IGNORECASE)

逐段解释：

* 第 L23-L25 行：`UVM_SUMMARY_RE` 解析 UVM Report Summary 中的 severity 计数。
* 第 L34-L37 行：`UVM_SUMMARY_LINE_RE` 用于跳过被 VCS banner 干扰的 summary 行。
* 第 L39-L46 行：工具 warning、crash、timeout 各有独立正则；crash 和 timeout
  后续优先于缺失 pass signature。

接口关系：

* 被调用：`check_uvm_log()`。
* 调用：Python `re`。
* 共享状态：这些正则是模块级常量，被所有日志检查复用。

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L58-L99``）：

.. code-block:: python

   def check_uvm_log(log_path: str, fail_on_warnings: bool = False,
                     sim_returncode: int = None) -> tuple:
       """Check UVM simulation log for errors."""
       if not os.path.exists(log_path):
           return (False, "FILE_ERROR", 0, 0)

       num_errors = 0
       num_warnings = 0
       summary_errors = None
       summary_warnings = None
       has_fatal = False
       has_test_pass = False
       has_test_fail = False
       has_tool_crash = False
       has_tool_timeout = False

逐段解释：

* 第 L58-L67 行：缺失 log 直接返回 `FILE_ERROR`。
* 第 L69-L78 行：函数同时维护计数、summary 计数和多个布尔标志；这些标志决定最终
  failure mode。

接口关系：

* 被调用：`check_sim_log()`。
* 调用：`os.path.exists()`、正则匹配。
* 共享状态：读取 log 文件。

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L119-L144``）：

.. code-block:: python

       if summary_errors is not None:
           num_errors = summary_errors
       if summary_warnings is not None:
           num_warnings = summary_warnings

       if has_tool_crash:
           return (False, "SIM_CRASH", num_errors, num_warnings)
       if has_tool_timeout:
           return (False, "SIM_TIMEOUT", num_errors, num_warnings)
       if has_fatal:
           return (False, "UVM_FATAL", num_errors, num_warnings)
       if has_test_fail:
           return (False, "TEST_FAIL", num_errors, num_warnings)
       if num_errors > 0:
           return (False, "UVM_ERROR", num_errors, num_warnings)
       if sim_returncode not in (None, 0):
           return (False, "SIM_ERROR", num_errors, num_warnings)

逐段解释：

* 第 L119-L122 行：如果 summary 中有明确计数，summary 计数覆盖逐行计数。
* 第 L126-L137 行：failure mode 有固定优先级：工具 crash、timeout、UVM fatal、
  test fail、UVM error、sim 返回码错误。
* 第 L138-L144 行：warning-clean 模式可把 warning 视为失败；最终必须看到
  `TEST PASSED` 或 `test_passed`，否则返回 `NO_PASS_SIGNATURE`。

接口关系：

* 被调用：`check_sim_log()`。
* 调用：无下游 helper。
* 共享状态：返回 `(passed, failure_mode, errors, warnings)` tuple。

§7.2 ``check_sim_log()`` — 生成 ``TestRunResult``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：组合 UVM 检查、trace 指令数、cycle 数和 IPC。

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L175-L205``）：

.. code-block:: python

   def check_sim_log(log_path: str, trace_path: str = "",
                     fail_on_warnings: bool = False,
                     sim_returncode: int = None) -> TestRunResult:
       """Analyze simulation log and produce test result."""
       result = TestRunResult()
       result.sim_returncode = sim_returncode

       passed, failure_mode, num_errors, num_warnings = check_uvm_log(
           log_path, fail_on_warnings, sim_returncode)
       result.passed = passed
       result.failure_mode = failure_mode
       result.uvm_errors = num_errors
       result.uvm_warnings = num_warnings

       if trace_path:
           result.num_instructions = extract_instruction_count(trace_path)
       result.num_cycles = extract_cycle_count(log_path)

逐段解释：

* 第 L175-L189 行：函数先创建 `TestRunResult`，并保留 simulator 返回码。
* 第 L191-L196 行：`check_uvm_log()` 的 tuple 被映射到 result 字段。
* 第 L198-L200 行：trace path 存在时统计指令数；cycle 数总是从 log 中尝试解析。

接口关系：

* 被调用：`run_rtl.py` 和 `check_logs.py main()`。
* 调用：`check_uvm_log()`、`extract_instruction_count()`、
  `extract_cycle_count()`。
* 共享状态：读 sim log 和 trace 文件。

§7.3 metadata 模式结果回写
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 staged Make flow 中，`check_logs.py` 读取已有 run result，保留 pre-sim
失败，并写出 `result.pkl` 与 `trr.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L255-L301``）：

.. code-block:: python

       if metadata_mode:
           if not args.test_dot_seed:
               parser.error("--test-dot-seed is required with --dir-metadata")
           from metadata import RegressionMetadata

           md = RegressionMetadata.construct_from_metadata_dir(
               Path(args.dir_metadata))
           test_name, seed = read_test_dot_seed(args.test_dot_seed)
           test_dir = Path(md.dir_tests) / args.test_dot_seed
           log_path = test_dir / "sim_{}_{}.log".format(test_name, seed)
           trace_path = test_dir / "trace_core"

逐段解释：

* 第 L255-L263 行：metadata 模式要求 `--test-dot-seed`，并从 metadata 找到 per-test
  目录。
* 第 L264-L265 行：sim log 和 trace 文件名按 `run_rtl.py` 的输出约定构造。

接口关系：

* 被调用：CLI main。
* 调用：`RegressionMetadata.construct_from_metadata_dir()`、
  `read_test_dot_seed()`。
* 共享状态：读 metadata 和 per-test 目录。

关键代码（``dv/uvm/core_eh2/scripts/check_logs.py:L266-L321``）：

.. code-block:: python

           recorded_result = load_recorded_result(test_dir, test_name, seed)
           sim_returncode = args.sim_returncode
           if sim_returncode is None:
               sim_returncode = (
                   getattr(recorded_result, "sim_returncode", None)
                   if recorded_result is not None else None)
           if recorded_result is not None and \
                   recorded_result.failure_mode in PRE_SIM_FAILURE_MODES:
               result = recorded_result
               result.passed = False
           else:
               result = check_sim_log(
                   str(log_path),
                   str(trace_path) if trace_path.exists() else "",
                   args.fail_on_warnings,
                   sim_returncode)

逐段解释：

* 第 L266-L271 行：如果 `run_rtl.py` 已经记录过 simulator 返回码，这里会复用它。
* 第 L272-L276 行：生成或编译阶段失败属于 `PRE_SIM_FAILURE_MODES`，不会被后续日志
  检查覆盖。
* 第 L277-L281 行：普通情况调用 `check_sim_log()` 重新分析 log。
* 第 L291-L301 行：结果保存为 pickle，并写出一个轻量 `trr.yaml` 供聚合或人工查看。

接口关系：

* 被调用：CLI main。
* 调用：`load_recorded_result()`、`check_sim_log()`、`TestRunResult.save()`。
* 共享状态：写 `result.pkl` 和 `trr.yaml`。

§8 ``collect_results.py`` 与 ``report_lib`` — 报告聚合
--------------------------------------------------------------------------------

`collect_results.py` 负责从 per-test pickle 生成标准回归报告；`report_lib/`
提供 text、JUnit、HTML、SVG 和 dvsim JSON 的格式化函数。

§8.1 ``collect_results()`` — 去重读取 result pickle
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：递归查找结果 pickle，优先使用 `result.pkl`，避免同一测试目录中的中间
pickle 重复计数。

关键代码（``dv/uvm/core_eh2/scripts/collect_results.py:L22-L61``）：

.. code-block:: python

   def collect_results(results_dir: str) -> RegressionSummary:
       """Collect all test results from a directory."""
       summary = RegressionSummary()

       all_pkl_files = glob.glob(os.path.join(results_dir, "**", "*.pkl"), recursive=True)
       final_result_files = {
           os.path.realpath(path)
           for path in all_pkl_files
           if os.path.basename(path) == "result.pkl"
       }
       final_result_dirs = {
           os.path.dirname(path)
           for path in final_result_files
       }

逐段解释：

* 第 L22-L34 行：函数递归查找所有 `.pkl` 文件。
* 第 L35-L43 行：文件名为 `result.pkl` 的结果被视为最终结果，并记录其目录。

接口关系：

* 被调用：`collect_results.py main()` 和 `signoff.py load_stage_summary()`。
* 调用：`glob.glob()`、`pickle.load()`、`RegressionSummary.add_result()`。
* 共享状态：读取 per-test 结果 pickle。

关键代码（``dv/uvm/core_eh2/scripts/collect_results.py:L44-L61``）：

.. code-block:: python

       pkl_files = sorted(final_result_files)
       pkl_files.extend(
           sorted(path for path in all_pkl_files
                  if os.path.realpath(path) not in final_result_files and
                  os.path.dirname(os.path.realpath(path)) not in final_result_dirs)
       )

       for pkl_path in pkl_files:
           try:
               with open(pkl_path, "rb") as f:
                   result = pickle.load(f)
               if not isinstance(result, TestRunResult):
                   continue
               summary.add_result(result)

逐段解释：

* 第 L44-L49 行：`result.pkl` 先进入列表；同目录下其它 pickle 被过滤掉。
* 第 L51-L57 行：只有反序列化结果是 `TestRunResult` 时才进入 summary。
* 第 L58-L60 行：无法读取的 pickle 只打印 warning，不中断整个聚合。

接口关系：

* 被调用：`collect_results()`。
* 调用：`pickle.load()`、`summary.add_result()`。
* 共享状态：读文件系统中的 pickle 集合。

§8.2 ``generate_report_json()`` — 机器可读报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 `RegressionSummary` 写成 `report.json`，供 `signoff.py` 直接解析。

关键代码（``dv/uvm/core_eh2/scripts/collect_results.py:L64-L101``）：

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
               "name": r.test_name,
               "seed": r.seed,
               "type": r.test_type,

逐段解释：

* 第 L64-L73 行：顶层 JSON 包含时间戳、总数、通过数、失败数、通过率和总耗时。
* 第 L76-L98 行：每个测试 entry 导出名称、seed、类型、pass/fail、failure mode、
  log、trace、assembly、binary、coverage 和统计字段。
* 第 L100-L101 行：JSON 使用 indent 2 写出，便于人读和脚本读取。

接口关系：

* 被调用：`write_reports()`。
* 调用：`json.dump()`。
* 共享状态：写 `report.json`。

§8.3 ``report_lib.text`` — 文本回归报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 plain text summary、短列表和 pass/fail 详情。

关键代码（``dv/uvm/core_eh2/scripts/report_lib/text.py:L21-L57``）：

.. code-block:: python

   def gen_summary_line(passing_tests: list, failing_tests: list) -> str:
       """Generate a summary line for test results."""
       total_tests = len(passing_tests) + len(failing_tests)
       if total_tests == 0:
           return 'No tests run'
       pass_pct = (len(passing_tests) / total_tests) * 100
       return f'{pass_pct:0.2f}% PASS {len(passing_tests)} PASSED, ' \
              f'{len(failing_tests)} FAILED'

逐段解释：

* 第 L21-L25 行：无测试时返回 `No tests run`，避免除零。
* 第 L26-L28 行：非空时按 passing/total 计算百分比，并输出固定格式摘要。

接口关系：

* 被调用：`output_results_text()`。
* 调用：无下游 helper。
* 共享状态：读取 passing/failing 列表。

关键代码（``dv/uvm/core_eh2/scripts/report_lib/text.py:L31-L57``）：

.. code-block:: python

   def output_results_text(passing_tests: list, failing_tests: list,
                           summary_dict: Dict[str, str], report_file: TextIO):
       """Write results in text form to report_file."""
       report_file.write(gen_summary_line(passing_tests, failing_tests))
       report_file.write('\n')

       summary_yaml = io.StringIO()
       scripts_lib.pprint_dict(summary_dict, summary_yaml)
       summary_yaml.seek(0)
       report_file.write(summary_yaml.getvalue())
       report_file.write('\n')

逐段解释：

* 第 L31-L36 行：报告开头先写 summary line。
* 第 L39-L43 行：短摘要通过 `scripts_lib.pprint_dict()` 以 YAML-like 形式写入。
* 第 L46-L57 行：失败测试详情先写，通过测试详情后写；每个详情来自
  `gen_test_run_result_text()`。

接口关系：

* 被调用：`RegressionSummary.to_log()`。
* 调用：`gen_summary_line()`、`scripts_lib.pprint_dict()`、
  `gen_test_run_result_text()`。
* 共享状态：写 `regr.log`。

§8.4 ``report_lib.junit_xml`` — CI XML 报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 pass/fail 测试列表转换为 JUnit XML；同时生成普通版和 merged 版。

关键代码（``dv/uvm/core_eh2/scripts/report_lib/junit_xml.py:L39-L66``）：

.. code-block:: python

   def to_xml_report_string(test_suites: List[TestSuite]) -> str:
       """Convert test suites to JUnit XML string."""
       root = Element('testsuites')

       for suite in test_suites:
           suite_elem = SubElement(root, 'testsuite')
           suite_elem.set('name', suite.name)
           suite_elem.set('tests', str(len(suite.test_cases)))

           failures = sum(1 for tc in suite.test_cases if tc.failure_message is not None)
           suite_elem.set('failures', str(failures))

逐段解释：

* 第 L39-L47 行：根节点为 `testsuites`，每个 suite 生成一个 `testsuite` 节点。
* 第 L48-L49 行：failure 数量来自 test case 是否带 `failure_message`。
* 第 L51-L66 行：每个 test case 写入 name、stdout 和可选 failure 节点，最后用
  `minidom` 美化输出。

接口关系：

* 被调用：`output_run_results_junit_xml()`。
* 调用：`xml.etree.ElementTree` 和 `xml.dom.minidom`。
* 共享状态：写 XML 字符串到目标文件。

§8.5 ``report_lib.html``、``svg`` 和 ``dvsim_json``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供轻量 HTML、SVG dashboard 和 dvsim JSON 兼容报告。

关键代码（``dv/uvm/core_eh2/scripts/report_lib/svg.py:L88-L143``）：

.. code-block:: python

   def output_results_svg(test_summary_dict: Dict[str, Dict[str, int]],
                          cov_summary_dict: Dict[str, float],
                          dest: TextIO) -> None:
       '''Write an SVG summary dashboard for the given test and coverage results.'''

       passing_tests = sum(
           info['passing'] for info in test_summary_dict.values()
       )
       failing_tests = sum(
           info['failing'] for info in test_summary_dict.values()
       )
       total_tests = passing_tests + failing_tests

       if total_tests == 0:
           dest.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
           return

逐段解释：

* 第 L88-L99 行：SVG dashboard 从 per-test summary 里计算 passing、failing 和 total。
* 第 L101-L103 行：没有测试时写空 SVG 并返回。
* 第 L105-L143 行：非空时创建 Total Tests、Tests Passing，以及可选 coverage
  dashboard elements。

接口关系：

* 被调用：报告生成路径中需要 SVG 时调用。
* 调用：`DashboardElement`、`Dashboard`、`css_red_green_gradient()`。
* 共享状态：读取 summary dict 和 coverage dict，写 SVG 到 `dest`。

关键代码（``dv/uvm/core_eh2/scripts/report_lib/dvsim_json.py:L9-L46``）：

.. code-block:: python

   def create_dvsim_report_dict(tool: str, block_name: str, block_variant: str,
                                test_summary_dict: Dict[str, Dict[str, int]],
                                cov_summary_dict: Dict[str, float]) -> Dict:
       '''Produces a dvsim json style dict for given test and coverage results.'''

       dvsim_test_info = []

       for test_name, test_info in test_summary_dict.items():
           total_runs = test_info['passing'] + test_info['failing']

逐段解释：

* 第 L9-L18 行：函数参数包含工具名、block 名、variant、测试摘要和覆盖率摘要。
* 第 L19-L27 行：每个 test name 转成 dvsim 的 `unmapped_tests` entry，包含 passing
  runs、total runs 和 pass rate。
* 第 L29-L46 行：coverage 值从 0 到 1 的比例转换为百分比，并包装成 dvsim 结构。

接口关系：

* 被调用：`output_results_dvsim_json()`。
* 调用：标准库 `json.dumps()`。
* 共享状态：不读文件，只把 dict 写成 JSON。

§9 ``signoff.py`` — 签核阶段和门禁
--------------------------------------------------------------------------------

`signoff.py` 是当前 VCS 主线 sign-off 的编排和评估入口。它可运行阶段、复用已有阶段结果、
检查覆盖率、校验 waivers、生成 JSON/Markdown/HTML 报告。

§9.1 profile、门槛和 testlist 映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 sign-off preset、各 stage 最低通过数和 stage 到 testlist 的映射。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L37-L59``）：

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

* 第 L37-L44 行：profile 决定默认 stage 列表；`full` 包含 smoke、directed、
  cosim、riscv-dv、lint、CSR unit、compliance、formal 和 syn。
* 第 L46-L53 行：部分 stage 有最低通过数量门槛，例如 cosim 为 7，compliance
  为 85，CSR unit 为 20。

接口关系：

* 被调用：`resolve_stages()`、`collect_stage()`、`evaluate_signoff()`。
* 调用：无下游 helper。
* 共享状态：作为模块级常量被多个函数读取。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L55-L88``）：

.. code-block:: python

   STAGE_TESTLIST = {
       "directed": DV_DIR / "directed_tests" / "directed_testlist.yaml",
       "cosim": DV_DIR / "directed_tests" / "cosim_testlist.yaml",
       "riscvdv": DV_DIR / "riscv_dv_extension" / "testlist.yaml",
   }

   TEXT_REPORT_NAMES = (
       "dashboard.txt",
       "summary.txt",
       "coverage.txt",
       "cov_summary.txt",
       "report.txt",
       "urgReport.html",
   )

逐段解释：

* 第 L55-L59 行：只有 directed、cosim、riscv-dv 三类 stage 直接映射 testlist。
* 第 L61-L68 行：coverage 解析会在目录中查找这些常见文本报告名。
* 第 L70-L88 行：coverage metric alias 将 `group`、`covergroup`、`functional`
  都归一到 `functional`。

接口关系：

* 被调用：`build_stage_cmd()`、`coverage_candidate_files()`。
* 调用：无下游 helper。
* 共享状态：读取 `DV_DIR` 常量和 coverage 文本路径。

§9.2 ``resolve_stages()`` 与 ``precheck()`` — 阶段选择和环境预检
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解析 profile/stage override，并在执行前检查必要工具和输入。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L112-L120``）：

.. code-block:: python

   def resolve_stages(profile: str, stages_arg: str) -> List[str]:
       stages = _split_csv(stages_arg) if stages_arg else PROFILE_STAGES[profile]
       unknown = [stage for stage in stages if stage not in
                  ("smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                   "compliance", "formal", "syn")]
       if unknown:
           raise ValueError("Unknown sign-off stage(s): {}".format(
               ", ".join(unknown)))
       return stages

逐段解释：

* 第 L112-L113 行：`--stages` 存在时覆盖 profile，否则使用 `PROFILE_STAGES`。
* 第 L114-L120 行：未知 stage 会触发 `ValueError`，避免误拼写被静默忽略。

接口关系：

* 被调用：`main()`。
* 调用：`_split_csv()`。
* 共享状态：读取 `PROFILE_STAGES`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L152-L198``）：

.. code-block:: python

   def precheck(stages: List[str], simulator: str) -> Dict:
       checks = []

       checks.append({
           "name": "eh2 root",
           "passed": EH2_ROOT.exists(),
           "detail": str(EH2_ROOT),
       })
       checks.append({
           "name": "simulator config",
           "passed": (DV_DIR / "yaml" / "rtl_simulation.yaml").exists(),
           "detail": str(DV_DIR / "yaml" / "rtl_simulation.yaml"),
       })

逐段解释：

* 第 L152-L164 行：预检先确认 EH2 根目录和 simulator YAML 存在。
* 第 L166-L198 行：后续检查会根据 stage 需要验证 `run_regress.py`、testlist、
  smoke hex、GCC、lint/formal/syn 入口等。

接口关系：

* 被调用：`main()`，除非传入 `--skip-precheck`。
* 调用：`tool_exists()`、`resolve_gcc_prefix()`。
* 共享状态：读取 stage 列表、`simulator` 和文件系统状态。

§9.3 ``build_stage_cmd()`` — stage 到命令的映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 stage 和 CLI 参数构造执行命令。

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

* 第 L201-L206 行：默认命令指向 `run_regress.py`，并带 simulator、seed 和输出目录。
* 第 L208-L215 行：parallel、coverage、waves、warning-clean 都是通用参数。

接口关系：

* 被调用：`main()` 在 planned stage 阶段调用。
* 调用：无执行调用，只构造 argv list。
* 共享状态：读取 CLI args。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L217-L248``）：

.. code-block:: python

       if stage == "smoke":
           cmd.extend([
               "--test", "smoke",
               "--binary", str(EH2_ROOT / "tests" / "asm" / "smoke.hex"),
               "--rtl-test", "core_eh2_base_test",
               "--sim-opts", "+disable_cosim=1",
           ])
       elif stage == "lint":
           return ["make", "-C", str(EH2_ROOT), "lint"]
       elif stage == "csr_unit":
           csr_dir = EH2_ROOT / "dv" / "uvm" / "cs_registers_eh2"
           return ["make", "-C", str(csr_dir), "compliance",
                   "SIGNOFF_OUT=" + str(stage_out)]

逐段解释：

* 第 L217-L224 行：smoke stage 指定 `tests/asm/smoke.hex`，UVM test 为
  `core_eh2_base_test`，并显式传 `+disable_cosim=1`。
* 第 L225-L231 行：lint 和 CSR unit 不通过 `run_regress.py`，而是直接返回 make
  命令。
* 第 L232-L248 行：compliance、formal、syn 也各自返回专用 runner 或 make 目标；
  directed/cosim/riscv-dv 则追加 `--testlist`。

接口关系：

* 被调用：`main()`。
* 调用：无执行调用。
* 共享状态：读取 `EH2_ROOT`、`STAGE_TESTLIST`。

§9.4 ``run_command()`` — stage 执行包装
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：运行 stage 命令，写日志，并注入 `EH2_SIGNOFF_MODE=1`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L251-L271``）：

.. code-block:: python

   def run_command(cmd: List[str], log_path: Path, timeout_s: int) -> int:
       log_path.parent.mkdir(parents=True, exist_ok=True)
       env = os.environ.copy()
       env["EH2_SIGNOFF_MODE"] = "1"
       with open(log_path, "wb") as log_fd:
           log_fd.write(("+ " + _cmd_str(cmd) + "\n").encode("utf-8"))
           try:
               proc = subprocess.run(
                   cmd,
                   stdout=log_fd,
                   stderr=subprocess.STDOUT,
                   timeout=timeout_s,
                   env=env,
               )

逐段解释：

* 第 L251-L254 行：stage 日志目录先创建，环境变量复制自当前进程并加入
  `EH2_SIGNOFF_MODE=1`。
* 第 L255-L264 行：日志第一行写入完整命令；子进程 stdout/stderr 都写入同一个日志。
* 第 L265-L271 行：timeout 返回 124，并在日志中记录超时信息。

接口关系：

* 被调用：`main()` 的普通执行路径。
* 调用：`subprocess.run()`。
* 共享状态：写 `output/logs/<stage>.log`；影响下游 `run_regress.py` 对
  `skip_in_signoff` 的处理。

§9.5 ``collect_stage()`` — 普通回归 stage collector
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 stage 结果目录加载 summary，写报告，转换为 sign-off stage result。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L344-L383``）：

.. code-block:: python

   def collect_stage(stage: str, results_dir: Path, report_dir: Path,
                     command: List[str], exit_code: int,
                     fail_on_warnings: bool) -> Dict:
       summary, from_report_json = load_stage_summary(results_dir)
       write_reports(summary, str(report_dir))

       warning_count = sum(result.uvm_warnings for result in summary.results)
       result = {
           "stage": stage,
           "results_dir": str(results_dir),
           "report_dir": str(report_dir),
           "command": _cmd_str(command) if command else "",
           "exit_code": exit_code,

逐段解释：

* 第 L344-L349 行：stage summary 可以来自 `report.json` 或 pickle；collector
  会重新写标准 reports。
* 第 L351-L383 行：结果 dict 记录目录、命令、退出码、总数、通过数、失败数、
  pass rate、warnings、status、blockers、waivers 和每个测试详情。

接口关系：

* 被调用：`main()` 对 smoke/directed/cosim/riscv-dv/compliance 的路径。
* 调用：`load_stage_summary()`、`write_reports()`。
* 共享状态：读 stage results；写 `reports/<stage>`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L385-L415``）：

.. code-block:: python

       if exit_code not in (None, 0):
           result["blockers"].append("stage command exit code {}".format(exit_code))
       if summary.total_tests == 0:
           result["blockers"].append("no test results collected")
       if summary.failed > 0:
           result["blockers"].append("{} test(s) failed".format(summary.failed))
       if fail_on_warnings and warning_count > 0:
           result["blockers"].append("{} warning(s) in warning-clean run".format(
               warning_count))

       min_passed = STAGE_MIN_PASSED.get(stage)

逐段解释：

* 第 L385-L393 行：退出码、零测试、失败测试和 warning-clean warning 都会成为 blocker。
* 第 L395-L411 行：如果 stage 达到最低通过数，失败或退出码 blocker 可转为 stage
  waiver 说明；这是 threshold waiver 逻辑。
* 第 L413-L415 行：仍存在 blocker 时 status 改为 `FAIL`。

接口关系：

* 被调用：`main()`。
* 调用：无下游 helper。
* 共享状态：读取 `STAGE_MIN_PASSED`。

§9.6 coverage、waiver 和 sign-off 门禁
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解析覆盖率、校验 waiver schema，检查 cosim-disabled 和 skip-in-signoff
是否有正式 waiver，并给出最终 PASS/FAIL。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L996-L1060``）：

.. code-block:: python

   def evaluate_coverage(paths: List[Path], output_dir: Path, args) -> Dict:
       require_coverage = not getattr(args, 'no_require_coverage', False)
       thresholds = {
           "overall": args.min_overall_coverage,
           "line": args.min_line_coverage,
           "cond": args.min_cond_coverage,
           "fsm": args.min_fsm_coverage,
           "toggle": args.min_toggle_coverage,
           "functional": args.min_functional_coverage,
       }

       required = require_coverage or any(value > 0.0
                                          for value in thresholds.values())

逐段解释：

* 第 L996-L1005 行：coverage requirement 来自 `--no-require-coverage` 的反值，
  thresholds 来自 CLI 最小覆盖率参数。
* 第 L1007-L1008 行：只要要求 coverage，或任何 threshold 大于 0，就需要解析
  coverage 文件。
* 第 L1011-L1060 行：候选文件来自 CLI 和输出目录；解析出的 metric 取各文件最大值，
  并逐项与 threshold 比较。

接口关系：

* 被调用：`main()`。
* 调用：`coverage_candidate_files()`、`parse_coverage_text()`。
* 共享状态：读 coverage report 文件；返回门禁结果 dict。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1133-L1165``）：

.. code-block:: python

   def validate_waiver_schema(waiver_path: Path) -> Tuple[bool, List[str]]:
       """Validate cosim-disabled waiver YAML schema."""
       errors = []
       if not waiver_path.exists():
           return True, []
       try:
           waivers = _load_yaml(waiver_path)
       except Exception as e:
           return False, ["Cannot parse waiver file {}: {}".format(waiver_path, e)]
       if waivers is None:
           return True, []
       if not isinstance(waivers, list):
           return False, ["Waiver file must contain a YAML list"]
       required_fields = ["reason", "tracking_issue", "expiry_date"]

逐段解释：

* 第 L1133-L1142 行：waiver 文件不存在或为空都视为 schema 通过。
* 第 L1143-L1147 行：顶层必须是 YAML list。
* 第 L1148-L1165 行：每个 entry 必须有 `reason`、`tracking_issue`、
  `expiry_date`，且日期格式必须是 `YYYY-MM-DD`。

接口关系：

* 被调用：`main()` 的 `--validate-waivers` 分支和 sign-off gating。
* 调用：`_load_yaml()`、`re.match()`。
* 共享状态：读 waiver YAML。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1230-L1312``）：

.. code-block:: python

   def evaluate_signoff(stage_results: List[Dict], coverage_result: Dict,
                        precheck_result: Dict, args,
                        waiver_errors: List[str]) -> Tuple[str, List[str]]:
       blockers = []
       if not args.skip_precheck and not precheck_result.get("passed", False):
           blockers.append("precheck failed")

       cosim_reason_violations = detect_cosim_reason_loophole()
       if cosim_reason_violations:
           names = [v["test"] for v in cosim_reason_violations]
           blockers.append(
               "FORBIDDEN cosim_reason field in testlist ({}): {}. "

逐段解释：

* 第 L1230-L1235 行：precheck 失败会成为全局 blocker。
* 第 L1240-L1250 行：任何 testlist 中出现 `cosim_reason` 字段都会被视为禁止的
  bypass 路径，必须迁移到 waiver YAML。
* 第 L1253-L1275 行：每个 stage 非 PASS、pass rate 低于阈值或 coverage FAIL
  都会加入 blocker。

接口关系：

* 被调用：`main()`。
* 调用：`detect_cosim_reason_loophole()`、`collect_cosim_exceptions()`、
  `collect_skip_in_signoff()`、`load_waiver_set()`。
* 共享状态：读 stage result、coverage result、waiver 文件和 CLI flags。

§9.7 报告输出和 HTML 生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 sign-off 状态写成 Markdown、JSON，并在有 coverage dashboard 时生成
自包含 HTML 报告。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1315-L1406``）：

.. code-block:: python

   def write_markdown_report(status: Dict, path: Path):
       def stage_rows():
           stages = status["stages"]
           return stages.values() if isinstance(stages, dict) else stages

       lines = []
       lines.append("# EH2 Sign-off Report")
       lines.append("")

       real_ran = status.get("real_ran", 0)
       real_pool = status.get("real_pool", 0)
       real_pct = 100.0 * real_ran / max(1, real_pool)

逐段解释：

* 第 L1315-L1320 行：Markdown writer 支持 `stages` 是 dict 或 list 两种形态。
* 第 L1322-L1336 行：报告先写真实运行覆盖率，并在真实覆盖率小于 95% 且原状态为
  PASS 时把状态降级为 PARTIAL。
* 第 L1338-L1406 行：后续写 stages 表、coverage、precheck、cosim exceptions、
  blockers、stage waivers 和命令列表。

接口关系：

* 被调用：`main()`。
* 调用：无下游 helper。
* 共享状态：读取 `signoff_status` dict，写 `signoff_report.md`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1432-L1469``）：

.. code-block:: python

   def maybe_generate_html_report(args, output_dir: Path, json_path: Path,
                                  coverage_result: Dict,
                                  cov_merged_dir: Optional[Path]) -> Optional[Path]:
       """Generate report.html after sign-off evaluation when requested."""
       if not getattr(args, "html_report", True):
           return None

       dashboard = _select_html_coverage_dashboard(
           coverage_result, cov_merged_dir, output_dir)
       if dashboard is None:
           print("WARNING: HTML report skipped; coverage dashboard.txt not found")
           return None

逐段解释：

* 第 L1432-L1437 行：`--no-html-report` 会直接跳过 HTML。
* 第 L1439-L1443 行：找不到 coverage `dashboard.txt` 时打印 warning 并返回 `None`。
* 第 L1445-L1469 行：找到 dashboard 后调用 `gen_html_report.py`，传入 sign-off JSON、
  coverage dashboard、runs 目录和 HTML 输出路径。

接口关系：

* 被调用：`main()`。
* 调用：`_select_html_coverage_dashboard()`、`subprocess.run()`。
* 共享状态：读 `signoff_status.json` 和 coverage dashboard，写 `report.html`。

§9.8 ``main()`` — CLI、执行循环和最终状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解析 CLI、计划 stages、执行或复用结果、评估 coverage/waiver/sign-off，
最后写 JSON、Markdown 和 HTML。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1472-L1562``）：

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

逐段解释：

* 第 L1472-L1480 行：CLI 以 `--profile`、`--stages`、`--output` 和
  `--stage-result` 为核心参数。
* 第 L1481-L1538 行：后续 parser 参数覆盖 dry-run、gate-only、simulator、
  seed、iterations、parallel、coverage thresholds、waiver、LEC 和 HTML 选项。
* 第 L1560-L1562 行：`full` profile 强制要求 coverage gate，不允许通过
  `--no-require-coverage` 关闭。

接口关系：

* 被调用：脚本入口。
* 调用：本文件所有核心 helper。
* 共享状态：读取 CLI 和文件系统，写 sign-off 输出目录。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1570-L1693``）：

.. code-block:: python

       stages = resolve_stages(args.profile, args.stages)
       stage_result_dirs = parse_stage_result_args(args.stage_result)

       planned = []
       for stage in stages:
           stage_out = output_dir / "runs" / stage
           planned.append((stage, build_stage_cmd(stage, args, stage_out), stage_out))

       if args.dry_run:
           print("EH2 sign-off plan: profile={} stages={}".format(
               args.profile, ",".join(stages)))

逐段解释：

* 第 L1570-L1576 行：stage 列表和 stage-result override 先解析；每个 stage
  被转换为 `(stage, command, stage_out)` tuple。
* 第 L1578-L1583 行：dry-run 只打印计划命令，不执行也不评估门禁。
* 第 L1586-L1683 行：普通路径执行 stage loop、coverage 合并、coverage 评估、
  waiver schema 检查、sign-off 评估、真实运行覆盖率和 directed pool 覆盖检查。
* 第 L1685-L1693 行：只有 `PASS` 或带 waiver 的 PASS 状态返回 0；其它状态返回 1。

接口关系：

* 被调用：`if __name__ == "__main__"`。
* 调用：`resolve_stages()`、`build_stage_cmd()`、`run_command()`、
  `collect_stage()`、`evaluate_coverage()`、`evaluate_signoff()`、
  `write_markdown_report()`、`maybe_generate_html_report()`。
* 共享状态：写 `signoff_status.json`、`signoff_report.md` 和可选 `report.html`。

§10 ``gen_html_report.py`` — 自包含 HTML sign-off 报告
--------------------------------------------------------------------------------

`gen_html_report.py` 读取 `signoff_status.json` 和 URG dashboard 文本，生成一个
含 CSS/JavaScript 的自包含 HTML 文件。

§10.1 ``parse_total_coverage()`` — URG 总覆盖率解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 URG dashboard 的 Total Coverage Summary 表中解析 overall、line、
branch、toggle、assert、fsm、functional 等 metric。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L141-L176``）：

.. code-block:: python

   def parse_total_coverage(text: str) -> Dict[str, float]:
       """Parse the Total Coverage Summary block from URG dashboard text."""
       lines = text.splitlines()
       for idx, line in enumerate(lines):
           if not re.search(r"\bSCORE\b.*\bLINE\b", line):
               continue
           if idx + 1 >= len(lines):
               continue
           data_line = lines[idx + 1].strip()
           if not data_line and idx + 2 < len(lines):
               data_line = lines[idx + 2].strip()
           headers = [token.lower() for token in line.split()]
           values = data_line.split()

逐段解释：

* 第 L141-L149 行：函数逐行查找同时包含 `SCORE` 和 `LINE` 的表头。
* 第 L150-L153 行：数据行默认取下一行；如果下一行为空，再尝试下下行。
* 第 L154-L176 行：表头 token 被小写化，值行拆分后按 alias 映射成统一 metric。

接口关系：

* 被调用：`parse_coverage_report()`。
* 调用：`pct()`。
* 共享状态：只解析传入文本，不读文件。

§10.2 ``parse_metric_table()`` 与 ``parse_group_table()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解析 URG module 表和 covergroup 表，用于 HTML coverage detail。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L183-L232``）：

.. code-block:: python

   def parse_metric_table(path: Path, expected_name: bool = True) -> List[Dict[str, Any]]:
       """Parse URG SCORE/LINE/COND/TOGGLE/FSM/NAME tables."""
       text = read_text_if_exists(path)
       if not text:
           return []
       rows: List[Dict[str, Any]] = []
       active = False
       for raw in text.splitlines():
           line = raw.rstrip()
           if re.search(r"\bSCORE\b.*\bTOGGLE\b.*\bNAME\b", line):
               active = True
               continue

逐段解释：

* 第 L183-L189 行：缺少文件内容时返回空列表。
* 第 L190-L196 行：只有看到包含 `SCORE`、`TOGGLE`、`NAME` 的表头后才进入数据区。
* 第 L197-L232 行：每行拆成 score、line、cond、toggle、fsm 和 name，并按 score
  升序排序；无法解析分数的行也会保留为 unmeasured row。

接口关系：

* 被调用：`parse_coverage_report()`。
* 调用：`read_text_if_exists()`、`pct()`。
* 共享状态：读 `modlist.txt`。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L234-L266``）：

.. code-block:: python

   def parse_group_table(path: Path) -> List[Dict[str, Any]]:
       text = read_text_if_exists(path)
       if not text:
           return []
       rows: List[Dict[str, Any]] = []
       active = False
       for raw in text.splitlines():
           line = raw.rstrip()
           if re.search(r"\bSCORE\b.*\bINSTANCES\b.*\bNAME\b", line):
               active = True
               continue

逐段解释：

* 第 L234-L241 行：covergroup 表解析同样先找到表头。
* 第 L242-L263 行：每行至少需要 score 和 instances；名称取最后一个 token。
* 第 L264-L266 行：结果按 score 和 name 排序。

接口关系：

* 被调用：`parse_coverage_report()`。
* 调用：`pct()`。
* 共享状态：读 `groups.txt`。

§10.3 ``load_report_data()`` — 汇总 HTML 输入数据
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：读取 sign-off JSON 和 coverage 文本，归一化 stage、test、coverage、formal、
LEC 和 waiver 数据。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L456-L483``）：

.. code-block:: python

   def load_report_data(signoff_status: Path, coverage_dashboard: Path,
                        runs_dir: Path, output: Path) -> Dict[str, Any]:
       status = load_json(signoff_status)
       coverage = parse_coverage_report(coverage_dashboard)
       stage_summaries = [
           normalize_stage_summary(stage)
           for stage in get_stage_list(status)
       ]
       stage_details = collect_stage_details(status, output)
       per_stage_entry_count = sum(len(stage["tests"]) for stage in stage_details)
       display_test_count = coverage.get("number_of_tests") or per_stage_entry_count

逐段解释：

* 第 L456-L460 行：函数先加载 sign-off JSON，再解析 coverage dashboard。
* 第 L461-L466 行：stage summary 和 test detail 分别归一化；test 数优先取 coverage
  dashboard 的 `Number of tests`。
* 第 L467-L483 行：返回 dict 同时包含 coverage metrics、LEC modules、formal results
  和 stage waivers，供 render 函数直接消费。

接口关系：

* 被调用：`main()`。
* 调用：`load_json()`、`parse_coverage_report()`、`get_stage_list()`、
  `normalize_stage_summary()`、`collect_stage_details()`。
* 共享状态：读 `signoff_status.json`、coverage dashboard、formal log、LEC data。

§10.4 ``render_stage_summary()`` 和 ``render_stage_details()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：渲染 stage 总表和 per-stage 测试详情。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L517-L540``）：

.. code-block:: python

   def render_stage_summary(data: Dict[str, Any]) -> str:
       rows = []
       for stage in data["stage_summaries"]:
           rows.append(
               "<tr>"
               "{stage}{status}{total}{passed}{failed}{rate}{note}"
               "</tr>".format(
                   stage=cell(stage["stage"]),
                   status=cell(stage["status"], "badge " + stage["status_class"]),
                   total=cell(stage["total"]),

逐段解释：

* 第 L517-L529 行：每个 stage summary 转换为一行 HTML table row。
* 第 L530-L540 行：函数返回一个带 `id="summary"` 的 section，表格 class 为
  `sortable`，供 JavaScript 排序。

接口关系：

* 被调用：`render_html()`。
* 调用：`cell()`。
* 共享状态：读取 `data["stage_summaries"]`。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L557-L593``）：

.. code-block:: python

   def render_stage_details(data: Dict[str, Any]) -> str:
       panels = []
       for stage in data["stages"]:
           rows = []
           for test in stage["tests"]:
               log = link_or_text("log", test["log_href"]) if test["log_href"] else ""
               rows.append(
                   '<tr class="row-{}">'.format(test["status_class"]) +
                   cell(test["name"]) +
                   cell(test["seed"]) +
                   cell(test["status"], "badge " + test["status_class"]) +

逐段解释：

* 第 L557-L568 行：每个 test 被渲染为一行，包含名称、seed、状态、仿真时间、
  failure mode 和 log link。
* 第 L570-L593 行：每个 stage 渲染成 `<details>` 面板，内含搜索框和可排序表格。

接口关系：

* 被调用：`render_html()`。
* 调用：`link_or_text()`、`cell()`、`raw_cell()`。
* 共享状态：读取 `data["stages"]`。

§10.5 Formal、LEC、Lint 和 Waiver 渲染
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 sign-off JSON 中的 formal、LEC、lint 和 waiver 数据渲染为 HTML section。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L653-L685``）：

.. code-block:: python

   def render_formal_section(data: Dict[str, Any]) -> str:
       formal = data["formal"]
       summary = formal["summary"]
       rows = []
       for prop in formal["properties"]:
           rows.append(
               "<tr>{}</tr>".format(
                   cell(prop["short_name"]) +
                   cell(prop["result"], "badge " + prop["status_class"]) +
                   cell(prop["detail"]) +
                   cell(prop["name"])

逐段解释：

* 第 L653-L665 行：formal properties 每行显示短名、结果、detail 和完整 property 名。
* 第 L668-L685 行：section 顶部显示 PASS、EXPLORED、TOTAL 计数和来源 log 路径。

接口关系：

* 被调用：`render_html()`。
* 调用：`cell()`、`esc()`。
* 共享状态：读取 `data["formal"]`。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L687-L758``）：

.. code-block:: python

   def render_lec_section(data: Dict[str, Any]) -> str:
       rows = []
       for mod in data["lec_modules"]:
           rows.append(
               "<tr>{}</tr>".format(
                   cell(mod["name"]) +
                   cell(mod["passing"]) +
                   cell(mod["failing"]) +
                   cell(mod["unverified"]) +
                   cell(mod["status"], "badge " + status_class(mod["status"]))
               )
           )

逐段解释：

* 第 L687-L699 行：LEC section 按 module 展示 passing、failing、unverified 和 status。
* 第 L711-L725 行：lint section 从 stage summary 中取 lint 状态、文件数和 warning 数。
* 第 L728-L758 行：waiver section 展示 cosim-disabled、skip-in-signoff 和 stage waiver。

接口关系：

* 被调用：`render_html()`。
* 调用：`cell()`、`status_class()`、`esc()`。
* 共享状态：读取 sign-off JSON 归一化后的 LEC、lint 和 waiver 数据。

§10.6 ``render_html()``、CSS 和 JavaScript
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：组装完整 HTML，包括内联样式、导航、header、section 和交互脚本。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L761-L805``）：

.. code-block:: python

   def render_nav() -> str:
       links = [
           ("#summary", "Stages"),
           ("#coverage-summary", "Coverage"),
           ("#tests", "Tests"),
           ("#coverage-detail", "Coverage Detail"),
           ("#formal", "Formal"),
           ("#lec", "LEC"),
           ("#lint", "Lint"),
           ("#waivers", "Waivers"),
       ]

逐段解释：

* 第 L761-L775 行：导航链接固定对应页面内 section id。
* 第 L777-L805 行：header 展示 sign-off status、timestamp、profile、输出路径、
  coverage test 数和 line/toggle/functional 覆盖率。

接口关系：

* 被调用：`render_html()`。
* 调用：`esc()`、`status_class()`、`pct_text()`。
* 共享状态：读取 `data["status"]` 和 `data["coverage_metrics"]`。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L1038-L1106``）：

.. code-block:: python

   def render_html(data: Dict[str, Any]) -> str:
       return "\n".join([
           "<!doctype html>",
           "<html>",
           "<head>",
           '<meta charset="utf-8">',
           "<title>EH2 Sign-off Dashboard</title>",
           "<style>",
           css(),
           "</style>",
           "</head>",

逐段解释：

* 第 L1038-L1048 行：HTML 头部内联 charset、title 和 CSS。
* 第 L1049-L1066 行：body 中按顺序加入 nav、header、stage summary、coverage、
  test details、formal、LEC、lint、waiver 和 JavaScript。
* 第 L1069-L1106 行：`write_report()` 写文件；`parse_args()` 要求 sign-off JSON、
  coverage dashboard、runs dir 和输出路径；`main()` 调用 `load_report_data()` 后写出。

接口关系：

* 被调用：`main()`。
* 调用：全部 render helper、`css()`、`javascript()`。
* 共享状态：写 CLI 指定的 HTML 输出路径。

§11 辅助脚本
--------------------------------------------------------------------------------

本节覆盖小型 helper。它们行数较少，但处在回归工具链的边界上，主要负责路径、
schema、coverage 合并和共享工具函数。

§11.1 ``merge_cov.py`` — VCS coverage DB 合并
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：查找 `.vdb` 数据库，调用 `urg` 合并，并生成 `dashboard.txt`。

关键代码（``dv/uvm/core_eh2/scripts/merge_cov.py:L23-L37``）：

.. code-block:: python

   def find_vdb_dirs(start_dir: Path) -> Set[Path]:
       """Find all VCS coverage .vdb directories under start_dir."""
       cov_dbs = set()
       if not start_dir.is_dir():
           return cov_dbs
       if start_dir.name.endswith(".vdb"):
           cov_dbs.add(start_dir)
           return cov_dbs
       for p in start_dir.rglob("test.vdb"):
           cov_dbs.add(p)
       if not cov_dbs:
           for p in start_dir.rglob("*.vdb"):
               if p.is_dir():
                   cov_dbs.add(p)
       return cov_dbs

逐段解释：

* 第 L23-L30 行：如果输入本身就是 `.vdb` 目录，直接返回该目录。
* 第 L31-L37 行：优先查找 `test.vdb`；没有命中时再查找任意 `.vdb` 目录。

接口关系：

* 被调用：`standalone_merge()`。
* 调用：`Path.rglob()`。
* 共享状态：读取覆盖率目录树。

关键代码（``dv/uvm/core_eh2/scripts/merge_cov.py:L40-L99``）：

.. code-block:: python

   def merge_urg(vdb_dirs: List[Path], output_dir: Path, db_name: str = "cov_merged") -> int:
       """Merge VCS coverage databases using urg and generate dashboard.txt."""
       output_dir.mkdir(parents=True, exist_ok=True)
       report_dir = output_dir / "report"

       cmd = [
           "urg", "-full64",
           "-format", "text",
           "-dbname", str(output_dir / db_name),
           "-report", str(report_dir),
           "-log", str(output_dir / "merge.log"),
           "-dir",
       ]

逐段解释：

* 第 L40-L52 行：`urg` 命令设置 text 输出、merged DB 名、报告目录和 log 路径。
* 第 L53-L69 行：所有 vdb 目录追加到 `-dir` 后；timeout 返回 124，找不到 `urg`
  返回 127。
* 第 L71-L99 行：merge 成功后再尝试生成 dashboard，并把找到的 dashboard 复制到
  `output_dir/dashboard.txt`。

接口关系：

* 被调用：`standalone_merge()` 和 `signoff.py auto_merge_stage_coverage()`。
* 调用：外部工具 `urg`、`shutil.copy()`。
* 共享状态：读 `.vdb` 目录，写 merged coverage 目录。

§11.2 ``get_fcov.py`` — 功能覆盖率收集入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：metadata 模式下查找 coverage DB，并按 simulator 分支处理。

关键代码（``dv/uvm/core_eh2/scripts/get_fcov.py:L15-L62``）：

.. code-block:: python

   def _main():
       parser = argparse.ArgumentParser(description="Collect riscv-dv functional coverage")
       parser.add_argument("--dir-metadata", type=str, required=True,
                           help="Path to metadata directory")
       parser.add_argument("--simulator", type=str, default="vcs",
                           choices=["vcs", "xlm", "questa"],
                           help="Simulator used for coverage collection")
       parser.add_argument("--cov-dir", type=str, default=None,
                           help="Override coverage output directory")

逐段解释：

* 第 L15-L26 行：CLI 要求 `--dir-metadata`，并允许指定 simulator、coverage 输出目录
  和 verbose。
* 第 L30-L44 行：VCS 分支递归查找 `.vdb`；没有覆盖率数据库时只 warning 并返回 0。
* 第 L46-L57 行：找到 vdb 后调用 `urg -dir <joined vdb> -report <cov_dir>/report`。
* 第 L59-L62 行：Xcelium 分支只打印使用说明，当前没有实际 coverage 合并调用。

接口关系：

* 被调用：脚本入口。
* 调用：外部工具 `urg`。
* 共享状态：读 metadata 目录中的 `.vdb`，写 coverage report。

§11.3 ``eh2_cmd.py`` — EH2 配置助手
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：读取 `eh2_configs.yaml`，计算 ISA 字符串，并渲染 simulator compile defines。

关键代码（``dv/uvm/core_eh2/scripts/eh2_cmd.py:L13-L45``）：

.. code-block:: python

   def get_config(config_name: str) -> Dict:
       """Return one EH2 configuration from eh2_configs.yaml."""
       cfg_path = setup_imports._EH2_ROOT / "eh2_configs.yaml"
       with open(cfg_path, "r", encoding="utf-8") as f:
           configs = yaml.safe_load(f) or {}
       if config_name not in configs:
           raise KeyError(
               "Unknown EH2 config '{}'; available: {}".format(
                   config_name, ", ".join(sorted(configs))))

逐段解释：

* 第 L13-L17 行：配置文件路径来自 `setup_imports._EH2_ROOT / "eh2_configs.yaml"`。
* 第 L18-L21 行：未知配置名会抛 `KeyError`，错误信息包含可用配置列表。
* 第 L22-L27 行：返回 dict 包含 name、description 和 parameters。

接口关系：

* 被调用：`render_config_template.py` 和本文件 CLI。
* 调用：`yaml.safe_load()`。
* 共享状态：读 `eh2_configs.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/eh2_cmd.py:L30-L55``）：

.. code-block:: python

   def get_isas_for_config(cfg: Dict) -> Tuple[str, str]:
       """Return GCC and ISS ISA strings for one EH2 configuration."""
       params = cfg.get("parameters", {})
       base = "rv32imac"
       bitmanip = [
           name for name, enabled in [
               ("zba", params.get("BITMANIP_ZBA", 0)),
               ("zbb", params.get("BITMANIP_ZBB", 0)),
               ("zbc", params.get("BITMANIP_ZBC", 0)),
               ("zbs", params.get("BITMANIP_ZBS", 0)),
           ]
           if int(enabled)
       ]

逐段解释：

* 第 L30-L42 行：bitmanip 扩展由 `BITMANIP_ZBA/ZBB/ZBC/ZBS` 参数决定。
* 第 L43-L45 行：存在 bitmanip 时 GCC ISA 固定返回 `rv32imac_zba_zbb_zbc_zbs`，
  ISS ISA 按实际启用扩展拼接；没有 bitmanip 时两者都是 `rv32imac`。
* 第 L48-L55 行：`render_compile_defines()` 只把 int 参数渲染成 `+define+KEY=VALUE`。

接口关系：

* 被调用：配置模板和 CLI。
* 调用：`get_config()`。
* 共享状态：读取配置 parameters。

§11.4 ``render_config_template.py`` — 条件模板渲染
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 `eh2_configs.yaml` 参数替换模板中的 `{{ KEY }}`，并处理
`//% if KEY` / `//% endif` 条件块。

关键代码（``dv/uvm/core_eh2/scripts/render_config_template.py:L14-L54``）：

.. code-block:: python

   TOKEN_RE = re.compile(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}")
   IF_RE = re.compile(r"^\s*//%\s*if\s+([A-Za-z0-9_]+)\s*$")
   ENDIF_RE = re.compile(r"^\s*//%\s*endif\s*$")


   def render_template(config_name: str, template_filename: str) -> str:
       """Render a small token template using values from eh2_configs.yaml."""
       cfg = get_config(config_name)
       params = cfg["parameters"]
       text = Path(template_filename).read_text(encoding="utf-8")
       rendered_lines = []
       keep_stack = [True]

逐段解释：

* 第 L14-L16 行：三个正则分别识别 token、条件开始和条件结束。
* 第 L19-L25 行：函数先加载配置和模板文本，并用 `keep_stack` 表达嵌套条件状态。

接口关系：

* 被调用：`main()`。
* 调用：`get_config()`。
* 共享状态：读模板文件和 `eh2_configs.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/render_config_template.py:L27-L54``）：

.. code-block:: python

       for line in text.splitlines():
           if_match = IF_RE.match(line)
           if if_match:
               key = if_match.group(1)
               keep_stack.append(keep_stack[-1] and bool(int(params.get(key, 0))))
               continue
           if ENDIF_RE.match(line):
               if len(keep_stack) == 1:
                   raise ValueError("Unexpected //% endif in {}".format(
                       template_filename))
               keep_stack.pop()
               continue

逐段解释：

* 第 L27-L32 行：遇到 `//% if KEY` 时，将当前 keep 状态和配置参数布尔值相与后入栈。
* 第 L33-L38 行：遇到 `//% endif` 时出栈；栈深度为 1 说明 endif 多余，会抛异常。
* 第 L39-L54 行：保留的行再做 token 替换；`CONFIG_NAME` 是特殊 token，其它 key
  必须存在于 parameters 中。

接口关系：

* 被调用：`main()`。
* 调用：正则匹配和 `TOKEN_RE.sub()`。
* 共享状态：读取配置参数。

§11.5 ``directed_test_schema.py`` — directed YAML schema
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 directed testlist 的 config/test dataclass，并导入 YAML。

关键代码（``dv/uvm/core_eh2/scripts/directed_test_schema.py:L21-L54``）：

.. code-block:: python

   @dataclass
   class DConfig:
       """Common configuration for building directed tests."""
       config: str
       rtl_test: str
       rtl_params: dict = field(default_factory=dict)
       timeout_s: int = 300
       gcc_opts: str = "-O2 -g -static -nostdlib -nostartfiles"
       ld_script: Optional[str] = None
       includes: Optional[str] = None


   @dataclass
   class DTest(DConfig):
       """A single directed test entry."""
       test: str = ""
       desc: str = ""
       test_srcs: str = ""
       iterations: int = 1

逐段解释：

* 第 L21-L34 行：`DConfig` 保存多个 directed tests 可复用的 RTL test、参数、
  timeout、GCC 选项、linker 和 include。
* 第 L36-L46 行：`DTest` 继承 `DConfig`，再增加 test 名、描述、源文件和 iterations。
* 第 L48-L54 行：`DirectedTestsYaml` 保存 YAML 路径、configs 列表和 tests 列表。

接口关系：

* 被调用：`import_model()` 构造对象；`run_regress.py` 和 `compile_test.py` 读取。
* 调用：dataclass 默认行为。
* 共享状态：表达 directed testlist 的内存模型。

关键代码（``dv/uvm/core_eh2/scripts/directed_test_schema.py:L56-L119``）：

.. code-block:: python

   def import_model(directed_test_yaml: Path) -> DirectedTestsYaml:
       """Import and validate a directed test YAML file."""
       yaml_data = scripts_lib.read_yaml(directed_test_yaml)

       if not isinstance(yaml_data, list):
           logger.error(f"Expected a list in {directed_test_yaml}, got {type(yaml_data)}")
           sys.exit(1)

       configs = []
       tests = []

逐段解释：

* 第 L56-L69 行：YAML 顶层必须是 list，否则记录错误并退出。
* 第 L74-L85 行：不含 `test` 的 entry 被视为 config entry，构造成 `DConfig`。
* 第 L87-L113 行：含 `test` 的 entry 必须引用已存在 config；找不到 config 会退出。
* 第 L115-L119 行：最终返回 `DirectedTestsYaml`。

接口关系：

* 被调用：`run_regress.load_regression_testlist()`、`compile_test.directed_entry()`、
  `run_rtl._directed_test_entry()`。
* 调用：`scripts_lib.read_yaml()`。
* 共享状态：读 directed/cosim testlist YAML。

§11.6 ``scripts_lib.py`` — 共享工具函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供子进程执行、YAML 读取、字符串替换、可打印 dict 和 pickle/YAML
持久化基类。

关键代码（``dv/uvm/core_eh2/scripts/scripts_lib.py:L20-L73``）：

.. code-block:: python

   def run_one(verbose: bool, cmd: List[str],
               redirect_stdstreams: Optional[Union[str, Path]] = None,
               timeout_s: Optional[int] = None,
               env: Optional[Dict[str, str]] = None) -> int:
       """Run a command, returning its retcode."""
       stdstream_dest = None
       needs_closing = False

       if redirect_stdstreams is not None:
           if str(redirect_stdstreams) == '/dev/null':
               stdstream_dest = subprocess.DEVNULL
           elif isinstance(redirect_stdstreams, (str, Path)):
               stdstream_dest = open(redirect_stdstreams, 'wb')
               needs_closing = True

逐段解释：

* 第 L20-L31 行：函数参数覆盖 verbose、命令列表、stdout/stderr 重定向、timeout 和 env。
* 第 L36-L44 行：重定向目标可以是 `/dev/null` 或文件路径；文件路径以二进制写打开。
* 第 L46-L73 行：verbose 时打印 shell-like 命令；`subprocess.run()` 执行后返回
  return code，timeout 或 OSError 返回 1，并在 finally 中关闭文件。

接口关系：

* 被调用：`compile_tb.py`、`build_instr_gen.py`。
* 调用：`subprocess.run()`。
* 共享状态：可写 stdout/stderr log 文件。

关键代码（``dv/uvm/core_eh2/scripts/scripts_lib.py:L111-L188``）：

.. code-block:: python

   def read_yaml(yaml_file: Path) -> dict:
       """Read YAML file to a dictionary."""
       with open(yaml_file, 'r', encoding='utf-8') as f:
           try:
               yaml_data = yaml.safe_load(f)
           except yaml.YAMLError as exc:
               print(f"YAML error: {exc}", file=sys.stderr)
               sys.exit(1)
       return yaml_data

逐段解释：

* 第 L111-L119 行：YAML 解析错误会打印到 stderr 并退出；调用方不用捕获
  `yaml.YAMLError`。
* 第 L122-L141 行：`pprint_dict()` 和 `_yaml_value_format()` 把 dict 写成
  YAML-like 文本，多行或含特殊字符的字符串用 block style。
* 第 L159-L188 行：`TestdataCls` 提供 pickle 导入和 pickle/YAML 导出；子类只需设置
  `pickle_file`、`yaml_file` 并实现 printable dict。

接口关系：

* 被调用：`directed_test_schema.py`、`test_entry.py`、`test_run_result.py`、
  `report_lib.text`。
* 调用：`yaml.safe_load()`、`pickle.dump()`、`pickle.load()`。
* 共享状态：读 YAML，写 pickle/YAML。

§11.7 ``setup_imports.py`` 与 ``test_entry.py`` — 路径和 ``TEST.SEED``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`setup_imports.py` 生成 Python 搜索路径；`test_entry.py` 解析 `TEST.SEED`
并读取 testlist entry。

关键代码（``dv/uvm/core_eh2/scripts/setup_imports.py:L14-L38``）：

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

逐段解释：

* 第 L14-L16 行：项目根目录由脚本路径向上 4 层推导。
* 第 L19-L27 行：模块级常量记录 EH2 根、core UVM、scripts、riscv-dv extension、
  YAML 和 vendor riscv-dv scripts 路径。
* 第 L29-L38 行：`get_pythonpath()` 将这些路径用冒号连接成 `PYTHONPATH`。

接口关系：

* 被调用：shell/Make 环境需要 Python path 时可调用脚本。
* 调用：`Path.resolve()`。
* 共享状态：只返回字符串，不写文件。

关键代码（``dv/uvm/core_eh2/scripts/test_entry.py:L24-L41``）：

.. code-block:: python

   def read_test_dot_seed(arg: str) -> TestAndSeed:
       """Read a value for --test-dot-seed argument (format: TEST.SEED)."""
       match = re.match(r'([^.]+)\.([0-9]+)$', arg)
       if match is None:
           raise ValueError(
               f'Bad --test-dot-seed ({arg}): should be of the form TEST.SEED.')
       return (match.group(1), int(match.group(2), 10))


   def get_test_entry(testname: str, testlist: Path) -> TestEntry:
       """Get a specific test entry from the testlist by name."""
       yaml_data = scripts_lib.read_yaml(testlist)

逐段解释：

* 第 L24-L30 行：`TEST.SEED` 必须只有一个点，并且 seed 必须是十进制数字。
* 第 L33-L41 行：`get_test_entry()` 从 YAML list 中查找 test name，不存在时抛
  `RuntimeError`。

接口关系：

* 被调用：`metadata.py`、`run_instr_gen.py`、`compile_test.py`、`run_rtl.py`、
  `check_logs.py`。
* 调用：`scripts_lib.read_yaml()`。
* 共享状态：读 testlist YAML。

§11.8 ``build_instr_gen.py`` — 预编译 riscv-dv generator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：metadata 模式下清理并创建 `instr_gen` 目录，然后用 riscv-dv compile-only
选项构建 generator。

关键代码（``dv/uvm/core_eh2/scripts/build_instr_gen.py:L23-L59``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(description='Build riscv-dv instruction generator')
       parser.add_argument('--dir-metadata', type=Path, required=True,
                           help='Path to regression metadata directory')
       args = parser.parse_args()

       md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)

       gen_dir = Path(md.work_dir) / 'instr_gen'
       try:
           shutil.rmtree(gen_dir)
       except FileNotFoundError:
           pass

逐段解释：

* 第 L23-L29 行：脚本只接受 metadata 目录，并加载 `RegressionMetadata`。
* 第 L31-L37 行：`instr_gen` 目录每次先删除再创建；不存在时忽略 `FileNotFoundError`。
* 第 L39-L48 行：命令由 `riscvdv_interface.get_run_cmd()` 构造，再追加 `--co`、
  simulator 和 `--end_signature_addr 0D058000`。
* 第 L50-L59 行：命令 stdout/stderr 写入 `build_stdout.log`，返回外部命令 retcode。

接口关系：

* 被调用：Make/metadata staged flow。
* 调用：`RegressionMetadata.construct_from_metadata_dir()`、
  `riscvdv_interface.get_run_cmd()`、`scripts_lib.run_one()`。
* 共享状态：写 `work_dir/instr_gen`。

§11.9 ``test_run_result.py`` — Ibex-style 结果 dataclass
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供另一套 Ibex-style `TestRunResult` 数据结构，供脚本库兼容路径使用。
当前主回归路径主要使用 `metadata.py` 中的 `TestRunResult`。

关键代码（``dv/uvm/core_eh2/scripts/test_run_result.py:L21-L52``）：

.. code-block:: python

   class TestType(Enum):
       """Type of the test."""
       RISCVDV = 0
       DIRECTED = 1


   class FailureModes(Enum):
       """Descriptive enum for the mode in which a test fails."""
       NONE = 0
       TIMEOUT = 1
       FILE_ERROR = 2
       LOG_ERROR = 3
       UVM_FATAL = 4
       COSIM_MISMATCH = 5

逐段解释：

* 第 L21-L25 行：测试类型枚举只有 `RISCVDV` 和 `DIRECTED`。
* 第 L27-L35 行：失败模式枚举覆盖 none、timeout、file error、log error、
  UVM fatal 和 cosim mismatch。
* 第 L36-L37 行：`__str__()` 输出 `NAME(value)` 格式。

接口关系：

* 被调用：该文件内 dataclass 使用。
* 调用：Python `Enum`。
* 共享状态：不读写文件。

关键代码（``dv/uvm/core_eh2/scripts/test_run_result.py:L40-L111``）：

.. code-block:: python

   @dataclass
   class TestRunResult(scripts_lib.TestdataCls):
       """Holds metadata about a single test run and its results."""

       testname: Optional[str] = None
       seed: Optional[int] = None
       testdotseed: Optional[str] = None
       testtype: Optional[TestType] = None

       passed: Optional[bool] = None
       failure_mode: Optional[FailureModes] = None

逐段解释：

* 第 L40-L52 行：类继承 `scripts_lib.TestdataCls`，保存 test identity 和 result。
* 第 L56-L90 行：后续字段覆盖 simulator、binary、riscv-dv、directed、目录、日志和
  执行命令。
* 第 L96-L111 行：`construct_from_metadata_dir()` 从 `<tds>.pickle` 加载；
  `format_to_printable_dict()` 会把位于 `dir_test` 下的路径转成相对路径。

接口关系：

* 被调用：兼容 Ibex-style pickle/YAML 导出路径。
* 调用：`scripts_lib.TestdataCls.construct_from_pickle()`。
* 共享状态：读写 pickle/YAML。

§12 CLI 调用关系矩阵
--------------------------------------------------------------------------------

下表只列本章覆盖的 Python 脚本之间的直接调用关系。

.. list-table::
   :header-rows: 1
   :widths: 22 34 44

   * - 上层入口
     - 直接调用
     - 共享数据
   * - ``run_regress.py``
     - ``run_instr_gen.py``、``compile_test.py``、``run_rtl.py``、``check_sim_log()``
     - ``TestRunResult``、per-test work dir、``report.json``
   * - ``run_rtl.py``
     - ``check_logs.check_sim_log()``
     - simulator YAML、sim log、trace
   * - ``check_logs.py``
     - ``metadata.RegressionMetadata``、``TestRunResult.save()``
     - ``result.pkl``、``trr.yaml``
   * - ``collect_results.py``
     - ``RegressionSummary.add_result()``、``write_reports()``
     - result pickle、``report.json``、JUnit XML
   * - ``signoff.py``
     - ``run_regress.py``、``collect_results``、``merge_cov.py``、``gen_html_report.py``
     - stage reports、coverage reports、waiver YAML
   * - ``gen_html_report.py``
     - 只读取 JSON/text，不回调 runner
     - ``signoff_status.json``、URG ``dashboard.txt``
   * - ``compile_tb.py``
     - ``scripts_lib.run_one()``
     - metadata、simulator filelists、compile log
   * - ``build_instr_gen.py``
     - ``riscvdv_interface.get_run_cmd()``、``scripts_lib.run_one()``
     - metadata、``work/instr_gen``

常见 failure mode 的来源如下：

.. list-table::
   :header-rows: 1
   :widths: 24 34 42

   * - failure mode
     - 产生位置
     - 触发条件
   * - ``GEN_ERROR`` / ``GEN_TIMEOUT``
     - ``run_regress.py``
     - riscv-dv 生成子进程非零返回或超时
   * - ``COMPILE_ERROR``
     - ``compile_test.py`` 或 ``run_rtl.py``
     - GCC/objcopy/TB 编译失败
   * - ``BINARY_MISSING``
     - ``run_rtl.py``
     - metadata 模式中 ``test.hex`` 和 ``test.bin`` 都不存在
   * - ``SIM_CRASH`` / ``SIM_TIMEOUT``
     - ``check_logs.py``
     - log 中匹配工具 crash 或 timeout 正则
   * - ``UVM_FATAL`` / ``UVM_ERROR``
     - ``check_logs.py``
     - log 中存在 UVM fatal/error 或 summary 计数非零
   * - ``NO_PASS_SIGNATURE``
     - ``check_logs.py``
     - 没有明确 ``TEST PASSED`` 或 ``test_passed`` 文本
   * - ``CONFIG_ERROR``
     - ``run_rtl.py``
     - simulator YAML 缺失或 simulator command 为空

§13 参考资料
--------------------------------------------------------------------------------

源文件绝对路径：

* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_instr_gen.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/riscvdv_interface.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_test.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_rtl.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_tb.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/check_logs.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/collect_results.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/gen_html_report.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/merge_cov.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/get_fcov.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/eh2_cmd.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/render_config_template.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/directed_test_schema.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/scripts_lib.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/setup_imports.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/test_entry.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/build_instr_gen.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/test_run_result.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/util.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/text.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/junit_xml.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/html.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/svg.py``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/dvsim_json.py``

关联 ADR：

* :ref:`adr-0010` — CSR register model；`signoff.py` 的 `csr_unit` stage 调用 CSR
  compliance make 目标。
* :ref:`adr-0011` — Compliance framework；`signoff.py` 的 `compliance` stage 调用
  RISC-V compliance runner。
* :ref:`adr-0012` — Formal strategy；`signoff.py` 的 `formal` stage 和
  `gen_html_report.py` 的 formal section 读取 formal 结果。
* :ref:`adr-0013` — Synthesis toolchain；`signoff.py` 的 `syn` stage 调用合成入口。
* :ref:`adr-0016` — Multi-hart cosim；`run_regress.py` 和 `run_rtl.py` 通过
  cosim plusarg 控制 cosim 运行路径。
* :ref:`adr-0017` — Integrity cosim waiver；`signoff.py` 使用
  ``dv/uvm/core_eh2/waivers/cosim-disabled.yaml`` 检查 cosim-disabled waiver。
* :ref:`adr-0019` — LEC tool-version limitation；`signoff.py` 暴露
  ``--lec-known-limited``。
* :ref:`adr-0020` — Block-level LEC；`signoff.py` 暴露 ``--lec-blocklevel`` 和
  ``--lec-summary-path``。

§14 v2-9 Python 脚本覆盖清单
--------------------------------------------------------------------------------

本节给出 ``dv/uvm/core_eh2/scripts`` 的文件级覆盖清单，作为后续逐函数精读的入口。
本章前文已经深入解释核心调度类脚本；v2-9 先把边缘工具、report library 和单元测试纳入同一
审计表，避免遗漏。

.. list-table::
   :header-rows: 1
   :widths: 28 28 44

   * - 文件
     - 类型
     - 当前文档入口
   * - ``build_instr_gen.py``、``compile_test.py``、``run_instr_gen.py``
     - riscv-dv generation/build
     - §3、§4、§5、§6 和 §12。
   * - ``run_regress.py``、``run_rtl.py``、``compile_tb.py``
     - regression/RTL/TB 调度
     - §4、§5、§6、§12。
   * - ``check_logs.py``、``collect_results.py``、``test_run_result.py``
     - result 判定与汇总
     - §8、§9、§11、§12。
   * - ``signoff.py``、``merge_cov.py``、``gen_html_report.py``
     - release evidence
     - §10、§12 和 :ref:`signoff_flow`。
   * - ``metadata.py``、``scripts_lib.py``、``eh2_cmd.py``
     - metadata/命令/配置公共层
     - §2、§7 和 :ref:`appendix_f_scripts/yaml_configs`。
   * - ``directed_test_schema.py``、``test_entry.py``、``setup_imports.py``
     - schema / entry / import helper
     - §7、§11、§12。
   * - ``report_lib/*.py``
     - 报告输出库
     - 本节新增入口。
   * - ``scripts/tests/test_*.py``
     - 单元测试
     - 本节新增入口。

关键代码（``dv/uvm/core_eh2/scripts/report_lib/html.py:L1-L18``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/html.py
   :language: python
   :lines: 1-18
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/html.py:L1-L18

逐段解释：

* 第 L1-L8 行：文件头说明该模块生成 EH2 HTML regression report，使用 Mako template，
  并说明它来自 Ibex report library 风格。
* 第 L10-L14 行：导入 typing、datetime、os 和 report library 公共 helper；report lib
  本身不调用 simulator。
* 第 L17-L18 行：``pct_str()`` 是第一个格式化 helper，用于把浮点比例渲染成百分比字符串。

关键代码（``dv/uvm/core_eh2/scripts/tests/test_regression_framework.py:L1-L18``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/tests/test_regression_framework.py
   :language: python
   :lines: 1-18
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/scripts/tests/test_regression_framework.py:L1-L18

逐段解释：

* 第 L1-L2 行：脚本入口和 SPDX 许可证头。
* 第 L4-L10 行：测试引入 ``os``、``sys``、``tempfile``、``unittest``、``json``、
  ``yaml``、``Path`` 和 ``mock``。
* 第 L12-L18 行：把脚本目录加入 ``sys.path``，随后导入 regression、RTL run、instr gen、
  template rendering 和 log checking 模块，后续测试用临时 workspace 验证这些模块的组合行为。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从脚本、Makefile 或配置文件中找到本页讲到的真实入口。

.. code-block:: bash

   rg -n "def main|argparse|subprocess|class |target:" dv/uvm/core_eh2/scripts scripts Makefile | head -80
   rg -n "cover.cfg|cov_full_nc.ccf|rtl_simulation.yaml|eh2_configs.yaml" docs/sphinx_cn/source/appendix_e_config docs/sphinx_cn/source/appendix_f_scripts

**进阶题**：检查工具职责是否按 VCS/NC/Formal/Syn/Lint 分开，而不是混成一个流程。

.. code-block:: bash

   rg -n "urg|imc|vcs|irun|xrun|dc_shell|fm_shell|verilator|verible" docs/sphinx_cn/source/appendix_c_tools docs/sphinx_cn/source/appendix_f_scripts | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？

§12  v2-16 Python 包初始化与 HTML report 单测补齐
--------------------------------------------------------------------------------

本节补齐脚本目录中容易被忽略的 Python 辅助文件。它们代码很短，但对 import path、
pytest 运行和 HTML report 解析契约很关键。

§12.1  ``scripts/__init__.py`` 与 ``report_lib/__init__.py``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/__init__.py
   :language: python
   :lines: 1-1
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/__init__.py:L1-L1

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/__init__.py
   :language: python
   :lines: 1-2
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/__init__.py:L1-L2

逐段精读：

* ``scripts/__init__.py`` 为空文件，作用是把 ``dv/uvm/core_eh2/scripts`` 标记为
  Python package。pytest 或外部 wrapper 通过 package import 脚本 helper 时依赖这个文件。
* ``report_lib/__init__.py`` 只有 package docstring，作用是把 HTML/text/JUnit/SVG
  report helper 聚合在同一 package 下。真实逻辑在 ``html.py``、``text.py`` 等文件。

§12.2  ``test_gen_html_report.py`` — HTML report parser 回归测试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/tests/test_gen_html_report.py
   :language: python
   :lines: 1-90
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/tests/test_gen_html_report.py:L1-L90

逐段精读：

* L1-L11：测试把 ``scripts`` 目录加入 ``sys.path`` 后导入 ``gen_html_report``。
  这验证脚本既能作为命令行入口，也能被 pytest 直接 import。
* L14-L37：第一个测试在临时目录构造 ``dashboard.txt``、``modlist.txt`` 和
  ``groups.txt``，覆盖 coverage dashboard、module list 和 group list 的解析。
* L39-L90：第二个测试构造 sign-off ``status`` 字典和相对 log 路径，验证 HTML report
  汇总器能把 smoke/syn stage 结果、LEC module 数字和 log link 组织成前端可用数据。

失败定位：若这个单测失败，优先检查 ``gen_html_report.parse_coverage_report`` 是否仍支持
当前 VCS/URG dashboard 格式；不要把 coverage 维度改回旧的 cond 口径。

§13  v2-18 关键脚本全文段落级精读
--------------------------------------------------------------------------------

v2-17 证明了每个脚本资产至少有源码片段；v2-18 进一步要求关键长脚本具备全文
``literalinclude``，让审计能发现“只解释前几十行”的假完整。本节覆盖
``signoff.py``、``gen_html_report.py`` 和 ``merge_cov.py`` 三个 release 证据核心脚本。

§13.1  ``signoff.py`` — 9-stage 签核编排全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/signoff.py:全文

逐段精读：

* L1-L90：脚本头、import、stage/profile 常量、coverage 门限、LEC/compliance 参数和
  release 默认值。这里固定 VCS 主线、9-stage 顺序和 25% fail-rate ceiling 的基础契约。
* L91-L201：JSON/YAML/CSV helper、stage 解析、工具存在性检查、GCC prefix 解析和
  precheck。precheck 只检查环境和输出目录，不伪造任何 stage 结果。
* L202-L351：``build_stage_cmd``、``run_command`` 和 stage summary loader。每个
  stage 都被转换成真实 Make/Python 命令，日志写入 stage output，结果从 report JSON
  或原生日志回读。
* L352-L533：仿真类 stage 与 lint stage 收集。这里把 smoke、directed、cosim、
  riscv-dv 等 stage 的 ``RegressionSummary`` 统一成 sign-off status，同时保留 log、
  failure bucket 和 known-fail 分类。
* L534-L793：formal、LEC 和 syn stage 收集。LEC 解析 block-level summary，
  ``31635/31635`` 这类数字来自 summary 文件，不从脚本常量推导。
* L794-L988：compliance suite 评价、URG dashboard header 解析、coverage 文本解析和
  coverage candidate 选择。当前主线解析 line/toggle/assert/fsm/branch 与 functional/group，
  不把历史 cond 当成 release 维度。
* L989-L1152：coverage merge/evaluate、cosim waiver、skip-in-signoff 和 reason loophole
  检查。这里是防止“关闭 cosim 却仍宣称 full sign-off”的主要 guardrail。
* L1153-L1305：waiver schema、waiver set、directed pool coverage、real run count。
  这些检查把 testlist、waiver YAML 和 stage 实跑数量连到最终签核判断。
* L1306-L1484：``evaluate_signoff`` 与 Markdown report。该段集中实现 9-stage PASS/FAIL、
  fail-rate ceiling、coverage gate、LEC gate 和 waiver gate。
* L1485-L1774：HTML dashboard 选择、HTML report 生成、CLI 参数和 ``main``。最后
  ``main`` 负责执行 stage、收集结果、写 JSON/Markdown/HTML，并以进程返回码表达签核状态。

§13.2  ``gen_html_report.py`` — 静态 HTML dashboard 全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/gen_html_report.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/gen_html_report.py:全文

逐段精读：

* L1-L69：脚本目标、默认路径、stage 顺序、coverage metric 列和颜色阈值。它只渲染
  已生成证据，不运行 simulator。
* L70-L142：HTML escape、百分比格式、status class、JSON/text 读取和相对链接 helper。
  这些函数保证报告在离线目录中可浏览。
* L143-L299：URG dashboard、module/group table 和 coverage report parser。它接受当前
  VCS/URG dashboard 文本，把 LINE/BRANCH/TOGGLE/ASSERT/FSM/GROUP/OVERALL 组织成结构化数据。
* L300-L469：stage 排序、test entry 归一化、stage detail、LEC/formal/waiver 数据抽取。
  该段把 sign-off JSON 中异构 stage 结果映射到统一 dashboard model。
* L470-L530：``load_report_data`` 和 HTML cell/link helper。它把 sign-off status、
  coverage dashboard、输出路径和 report link 汇成一个 data dict。
* L531-L788：stage summary、coverage bars、stage detail、coverage detail、formal、
  LEC、lint 和 waivers section 渲染。每个 section 只显示原始证据的结构化视图。
* L789-L1008：navigation、header 和 CSS。CSS 固定静态 HTML 风格，避免依赖外部资源。
* L1009-L1138：JavaScript、完整 HTML 拼装、写文件、CLI 和 ``main``。JavaScript 只做表格
  过滤/折叠等前端交互，不改变 PASS/FAIL 语义。

§13.3  ``merge_cov.py`` — VCS/URG 与 NC/IMC coverage 合并全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/merge_cov.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/merge_cov.py:全文

逐段精读：

* L1-L31：脚本头说明两种调用模式：Ibex-style metadata mode 和 standalone mode。
  当前 VCS 主线的 release 参考是 URG 原生 merge/report。
* L32-L100：VCS ``simv.vdb`` 发现与 ``urg -dir ... -dbname merged`` 调用。
  这段是 Ibex 对齐路径，报告输出交给 URG 原生 dashboard。
* L101-L224：NC run directory 发现、IMC cumulative metric 解析和兼容 dashboard 写出。
  NC/Incisive 是完整备选 simulator；该路径用于 ``cov_work``/IMC 兼容输出。
* L225-L288：``merge_imc`` 负责调用 IMC command-line flow，并把生成目录整理成 report
  artifact。它与 VCS/URG path 分开，避免混淆 database 格式。
* L290-L317：metadata mode 入口，从 regression framework 传入 run list 和输出目录。
* L318-L398：standalone CLI、参数解析和 ``main``。手工调用时按 ``--simulator`` 选择
  VCS 或 NC，不从文件名猜测 release 口径。

§15  v2-33 UVM scripts 主流程 Python 全文行段级精读
--------------------------------------------------------------------------------

本节补齐 ``dv/uvm/core_eh2/scripts`` 根目录下主流程 Python 脚本的全文
``literalinclude``。v2-18 已经覆盖 ``signoff.py``、``gen_html_report.py`` 和
``merge_cov.py``；本阶段聚焦 metadata、riscv-dv 生成、assembly 编译、RTL 运行、
日志判定、结果汇总和共享 helper，不把 ``report_lib``、``scripts/tests``、``*.mk``、
``*.sh`` 混入同一批提交。

§15.1  ``metadata.py`` — staged regression 状态中心
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/metadata.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/metadata.py:全文

逐段精读：

* L1-L19：脚本头说明 metadata 被所有 regression 脚本共享，import 覆盖 argparse、
  shlex、YAML、pickle、Path、dataclass 和时间戳。
* L21-L93：``RegressionMetadata`` dataclass 定义单次回归的统一状态：test/seed、
  simulator、EH2 config、输出目录、coverage 目录、test matrix、canonical input 文件、
  command、结果和时间戳。这个对象是 Make staged flow 的共享上下文。
* L94-L139：metadata 保存/加载逻辑同时写 YAML 与 pickle，并在旧 pickle 入口点不兼容时
  回退 YAML。这个回退避免 ``python scripts/metadata.py`` 生成的 ``__main__`` pickle
  破坏后续脚本读取。
* L141-L186：``TestRunResult`` 记录单个 test run 的路径、pass/fail、instruction/cycle、
  UVM error/warning、sim return code 和耗时，并提供 pickle/YAML 持久化。
* L188-L262：``RegressionSummary`` 汇总所有 result，生成 JUnit XML 和 text log。它只基于
  per-test result 累计，不重新解析 simulator log。
* L264-L317：YAML 读取、Make-style 参数解析、iteration override 和 directed testlist
  schema import。``_load_directed_entries`` 把 directed YAML 转成统一 entry 字典。
* L320-L367：``_select_test_entries`` 根据 ``TEST=all/all_riscvdv/all_directed/all_cosim``
  或显式 test 名称生成 ``(test, count, type)`` matrix。没有命中 testlist 时保留单测入口，
  使 smoke 这类外部名字仍可运行。
* L369-L451：``create_metadata`` 从 Make 变量构造目录树、canonical 路径和
  ``riscvdv_tds``/``directed_tds``，然后写 ``metadata`` 文件。该段是 staged flow 的入口。
* L454-L502：``print_field`` 和 CLI ``main`` 支持 Makefile 查询 metadata 字段。返回列表时会
  展平成空格分隔字符串，供 make dependency expansion 使用。

§15.2  ``run_regress.py`` — 直接回归编排入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/run_regress.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/run_regress.py:全文

逐段精读：

* L1-L36：文件头定义完整直接回归流程：生成、编译、仿真、检查和报告。import 引入
  subprocess、ProcessPoolExecutor、metadata、log checker、report JSON 和 directed schema。
* L38-L90：路径常量与 testlist loader。``load_regression_testlist`` 能识别 directed YAML
  中的 config 条目，并把 directed/cosim test 转成统一 entry。
* L93-L140：生成 assembly 搜索和 ``build_sim_opts``。后者合并 testlist 与 CLI plusarg，并按
  ``cosim`` 字段自动追加 ``+enable_cosim=1`` 或 ``+disable_cosim=1``。
* L143-L169：subprocess 日志与捕获 helper。每个外部进程 stdout/stderr 都写入持久 log，
  便于失败后追溯。
* L171-L251：``run_single_test`` 前半段建立 result/work dir，处理 riscv-dv generation 或
  directed assembly。generation 失败、timeout、缺少 assembly 和 directed source 缺失都会
  记录明确 failure mode。
* L252-L336：``run_single_test`` 后半段编译 assembly、调用 ``run_rtl.py``、再用
  ``check_sim_log`` 判定 PASS/FAIL。这里保存最终 result，是直接回归的 per-test 原子单元。
* L339-L454：``run_regression`` 选择 testlist、构造 test/seed matrix、可选并行执行、
  写 text/JUnit/JSON 报告，并在 coverage 模式复制 VCS DB。
* L457-L515：CLI 参数覆盖 test selection、UVM test、generator/sim opts、binary、cosim、
  coverage、waves、warning policy、simulator、输出目录和并行数。最终用失败数量设置进程返回码。

§15.3  ``run_instr_gen.py`` — riscv-dv generator runner
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/run_instr_gen.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/run_instr_gen.py:全文

逐段精读：

* L1-L26：脚本头、路径常量和 EH2 signature 地址。该脚本只负责 generator 阶段，
  输出 assembly 供后续 ``compile_test.py`` 使用。
* L28-L68：``build_sim_opts`` 注入 EH2 program generator override 和 signature 地址；
  ``load_test_entry`` 读取主 testlist；``write_overlay_testlist`` 为单次运行生成只含一个
  entry 的 overlay YAML，并合并 CLI 额外 ``gen_opts``。
* L71-L147：``run_instr_gen`` 构造 ``vendor/google_riscv-dv/run.py`` 命令，传入 target、
  seed、iterations、ISA、MABI、overlay testlist 和 EH2 custom target。返回码非零、timeout
  或异常都会转成 False，并写 ``*_gen.log``。
* L149-L164：metadata 模式从 ``TEST.SEED`` 和 metadata 目录推导 work dir，只传入 metadata
  额外 gen opts，避免 testlist 自带 ``gen_opts`` 被重复拼接。
* L166-L202：CLI 同时支持 standalone 参数和 Ibex-style ``--dir-metadata``。metadata 模式缺少
  ``--test-dot-seed`` 会直接报错。

§15.4  ``compile_test.py`` — assembly 到 binary/hex
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/compile_test.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/compile_test.py:全文

逐段精读：

* L1-L27：脚本头说明同时支持 riscv-dv generated tests 和 directed tests，路径常量定位
  script、DV root、EH2 root 和 riscv-dv extension。
* L29-L67：generated assembly 搜索、directed testlist 优先级、directed entry 查找和
  metadata 中 test type 查询。directed/cosim YAML 都可参与查找。
* L77-L145：metadata 模式编译一个 ``TEST.SEED``。directed test 会复制手写 assembly 到
  test dir 并解析 linker/include；riscv-dv test 会查找 generator 输出；失败时写
  ``COMPILE_ERROR`` result。
* L147-L187：riscv-dv include 目录解析。函数按 CLI、环境变量、vendor 目录和历史路径顺序
  找 generator include，最后追加 EH2 extension include。
* L190-L265：ELF section parser 与 VMA-addressed hex writer。它用 objdump 识别 loadable
  section，按 section VMA 写 ``@ADDR`` 格式 hex，供 RTL memory load 使用。
* L268-L377：``compile_assembly`` 构造 RISC-V GCC、objcopy 和可选 hex 生成流程。当前
  ``-march`` 使用 ``rv32imac_zba_zbb``，注释明确 Zbc/Zbs 需更高 GCC 版本。
* L380-L431：缺省 linker script 生成，定义 FLASH/RAM、PHDR 和 text/data/bss/tohost/signature
  section，服务 standalone 编译入口。
* L434-L480：CLI 同时支持 metadata mode 与 standalone mode。metadata mode 为了收集所有
  测试失败，即使单项 compile 失败也返回 0，并把失败写入 result。

§15.5  ``run_rtl.py`` — RTL 仿真运行器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/run_rtl.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/run_rtl.py:全文

逐段精读：

* L1-L31：文件头说明读取 ``rtl_simulation.yaml`` 构造 VCS/NC/Xcelium/Questa 命令。
  ``PRE_SIM_FAILURE_MODES`` 用于保护 generator/compile 阶段已记录的失败语义。
* L34-L87：YAML 读取、变量替换、compile command 和 sim command 构造。sim command 会根据
  coverage/waves 开关追加 YAML 中对应 options，并把多行 YAML command 压成单行 shell 字符串。
* L90-L108：``run_command`` 统一执行 shell 命令、写 log、处理 timeout。返回码留给上层
  ``check_sim_log`` 分类。
* L110-L192：``run_rtl_simulation`` 设置默认目录、读取 simulator YAML、准备 output log、
  必要时触发 compile，再运行 simulation。仿真结束后必须通过 ``check_sim_log`` 找到明确 pass
  signature，不能只信 simulator 返回码。
* L195-L218：``_merge_sim_opts`` 合并 testlist/global plusarg，并根据 ``cosim`` policy 自动加
  cosim enable/disable plusarg。
* L221-L265：directed/riscv-dv test entry 查询。directed entry 根据 UVM test class 推断 cosim
  默认策略，riscv-dv entry 从主 testlist 读取并补 ``test_type``。
* L268-L307：已有 result 读取与 missing binary result 构造。若 compile/generation 已失败，
  这里保留原 failure mode，避免后续被简单覆盖成 binary missing。
* L310-L340：metadata mode 创建单个 test run 的 metadata，选择 ``test.hex`` 或 ``test.bin``，
  合并 UVM test、plusarg、build/out dir，然后调用 ``run_rtl_simulation``。
* L343-L414：CLI 支持 standalone 与 metadata mode。metadata mode 始终返回 0，让 Make 继续
  跑 ``check_logs`` 和 ``collect_results`` 聚合所有测试。

§15.6  ``check_logs.py`` — simulator/UVM log 判定器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/check_logs.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/check_logs.py:全文

逐段精读：

* L1-L21：文件头列出检查项：UVM fatal/error、mailbox pass/fail、timeout 和 trace
  instruction count。它是仿真结果转 ``TestRunResult`` 的入口。
* L23-L63：正则定义覆盖 UVM summary、VCS banner 覆盖 summary、NC report catcher、
  tool warning、tool crash、tool timeout 和 pre-sim failure mode。
* L66-L160：``check_uvm_log`` 逐行扫描 log，跳过 summary 假阳性，统计 error/warning，
  识别 explicit pass/fail、tool crash、timeout 和 simulator return code。EH2 要求显式
  pass signature，没有 pass marker 就是 ``NO_PASS_SIGNATURE``。
* L163-L188：trace instruction count 和 log cycle count 提取 helper。IPC 统计只在两者都
  大于 0 时计算。
* L191-L221：``check_sim_log`` 组合 UVM 判定、instruction/cycle/IPC，并返回
  ``TestRunResult``。
* L224-L252：metadata mode helper 读取前序 result 或 simulator return code，并保留
  pre-sim failure mode。
* L255-L341：CLI 支持 standalone 和 metadata mode。metadata mode 会写 ``result.pkl`` 和
  ``trr.yaml``，但返回 0 以便 Make 继续聚合；standalone mode 保留失败返回码。

§15.7  ``collect_results.py`` — result 聚合与报告写出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/collect_results.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/collect_results.py:全文

逐段精读：

* L1-L20：文件头说明输出 ``regr.log``、``regr_junit.xml`` 和 ``report.json``，import
  glob/json/pickle/datetime 以及 metadata 中的 result/summary 类型。
* L22-L61：``collect_results`` 递归查找 ``*.pkl``，优先取每个 test 目录的最终
  ``result.pkl``，并避免同一目录内旧中间 pickle 重复计数。
* L64-L101：``generate_report_json`` 把 summary 转为 machine-readable JSON，包含 test
  名称、seed、类型、失败模式、路径、UVM 计数、sim 返回码、instruction/cycle/IPC 和耗时。
* L104-L109：``write_reports`` 同时写 text log、JUnit XML 和 JSON，作为 CI 和 sign-off
  后续消费的统一出口。
* L112-L155：CLI 支持 standalone ``--results-dir`` 和 metadata mode ``--dir-metadata``。
  命令行输出打印总数、通过数、失败数、通过率和失败 test 列表，返回码由失败数决定。

§15.8  ``build_instr_gen.py`` 与 ``compile_tb.py`` — 构建入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/build_instr_gen.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/build_instr_gen.py:全文

逐段精读：

* L1-L20：脚本头说明它按 Ibex 风格预构建 riscv-dv instruction generator，import 包括
  metadata、``scripts_lib.run_one``、``format_to_cmd`` 和 ``riscvdv_interface``。
* L23-L37：CLI 只接收 ``--dir-metadata``，读取 metadata 后清理并重建
  ``<work_dir>/instr_gen``。
* L39-L59：用 ``riscvdv_interface.get_run_cmd`` 构造 compile-only 命令，追加 ``--co``、
  simulator 和 signature 地址，然后通过 ``run_one`` 执行并写 ``build_stdout.log``。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/compile_tb.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/compile_tb.py:全文

逐段精读：

* L1-L20：脚本头说明该入口编译 UVM testbench，支持不同 simulator。
* L23-L76：``get_compile_cmd`` 根据 metadata simulator 生成 VCS、Xcelium 或 Questa
  compile command。VCS 路径加入 RTL/shared/TB filelist、riscv-dv extension include、
  C++17 DPI flag 和 ``simv`` 输出。
* L79-L103：CLI 读取 metadata、创建 work dir、调用 ``get_compile_cmd``，再用
  ``run_one`` 写 ``compile_stdout.log`` 并返回 compile retcode。

§15.9  ``eh2_cmd.py``、``render_config_template.py`` 与 ``setup_imports.py`` — 配置与路径 helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/eh2_cmd.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/eh2_cmd.py:全文

逐段精读：

* L1-L10：脚本头和 import 定义 EH2 config helper，依赖 ``setup_imports`` 定位仓库根目录。
* L13-L27：``get_config`` 读取顶层 ``eh2_configs.yaml``，校验 profile 名并返回 name、
  description 和 parameters。
* L30-L55：``get_isas_for_config`` 由 bitmanip 参数生成 GCC/ISS ISA 字符串；
  ``render_compile_defines`` 把 integer 参数渲染成 simulator ``+define+``。
* L58-L69：CLI 可打印 config dict 或 ``--defines`` 输出，用于 shell/Make 集成。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/render_config_template.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/render_config_template.py:全文

逐段精读：

* L1-L17：脚本头和正则定义 ``{{ TOKEN }}``、``//% if KEY`` 与 ``//% endif`` 三种模板语法。
* L19-L54：``render_template`` 读取 EH2 profile 参数，按条件栈过滤模板行，再替换 token。
  未闭合或多余 endif 会抛 ``ValueError``，未知 token 会抛 ``KeyError``。
* L57-L69：CLI 从 metadata 读取 ``eh2_config``，渲染传入模板到 stdout，供 Make 重定向成
  ``riscv_core_setting.sv``。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/setup_imports.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/setup_imports.py:全文

逐段精读：

* L1-L12：脚本头说明该文件建立所有 regression 脚本使用的 Python path。
* L14-L27：``get_project_root`` 通过当前文件位置回溯到 ``eh2-veri`` 根目录，并定义 core、
  scripts、riscv-dv extension、YAML 和 vendor riscv-dv scripts 路径常量。
* L29-L42：``get_pythonpath`` 把上述路径拼成冒号分隔字符串；CLI 直接打印该字符串。

§15.10  schema、entry、result 与共享库
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/directed_test_schema.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/directed_test_schema.py:全文

逐段精读：

* L1-L18：脚本头说明它定义 directed test 配置 schema，import dataclass、Path、typing 和
  ``scripts_lib``。
* L21-L54：``DConfig``、``DTest`` 和 ``DirectedTestsYaml`` dataclass 分别表示共享 config、
  单个 directed test 和整个 YAML model。
* L56-L119：``import_model`` 读取 YAML list，先收集 config，再把 test entry 与已有 config
  合并。引用不存在 config 会直接报错退出，防止 directed test 静默使用空配置。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/test_entry.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/test_entry.py:全文

逐段精读：

* L1-L21：脚本头、typing alias 和 logger。``TestEntry``、``TestEntries``、
  ``TestAndSeed`` 为其他脚本提供轻量类型约定。
* L24-L30：``read_test_dot_seed`` 解析 ``TEST.SEED``，格式不符时抛 ``ValueError``。
* L33-L41：``get_test_entry`` 从 YAML testlist 查找指定 test，找不到即抛
  ``RuntimeError``。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/test_run_result.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/test_run_result.py:全文

逐段精读：

* L1-L18：脚本头说明该 dataclass 追踪单个 test run 的 metadata 和结果。
* L21-L37：``TestType`` 区分 RISCVDV 与 DIRECTED；``FailureModes`` 给 timeout、
  file/log error、UVM fatal 和 cosim mismatch 定义枚举。
* L40-L95：``TestRunResult`` dataclass 保存 test identity、result、simulator、binary、
  riscv-dv 字段、directed 字段、目录、日志、执行命令和持久化文件路径。
* L96-L111：从 metadata dir 加载 pickle，并把 Path 转成相对路径形式以便打印。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/scripts_lib.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/scripts_lib.py:全文

逐段精读：

* L1-L18：共享工具库 import subprocess、pickle、YAML、Path 和 typing。
* L20-L74：``run_one`` 执行命令、可选重定向 stdout/stderr、处理 timeout/OSError，并在
  verbose 模式打印 shell-quoted command。
* L76-L108：``format_to_cmd``、``format_to_str``、``subst_opt`` 和 ``subst_dict`` 提供
  command/string/path 格式化与 ``<name>`` 占位替换。
* L111-L156：YAML 读取、字典 pretty print 和可打印 dict 转换。``read_yaml`` 遇到 YAML
  语法错误会退出，避免调用方继续使用坏配置。
* L159-L188：``TestdataCls`` 是 pickle/YAML export 基类，要求调用方设置 ``pickle_file``，
  并可选写 printable YAML。

§15.11  ``riscvdv_interface.py`` 与 ``get_fcov.py`` — riscv-dv command/coverage helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/riscvdv_interface.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/riscvdv_interface.py:全文

逐段精读：

* L1-L22：脚本头说明提供 riscv-dv command、coverage command 和 simulator YAML command
  helper，并定义 EH2 root、vendor riscv-dv、DV 和 extension 路径。
* L24-L75：``get_run_cmd`` 构造 ``run.py`` generator 命令，加入 test、target、seed、
  iterations、ISA、MABI、custom target、testlist、CSR YAML、output dir 和 gen opts。
* L78-L103：``get_cov_cmd`` 构造 riscv-dv ``cov.py`` 命令，输入 trace CSV、ISA、target 和
  output dir。
* L106-L140：``get_tool_cmds`` 读取 ``rtl_simulation.yaml``，对 compile/sim command 做
  ``<var>`` 替换，并按 simulator/stage 返回字典。
* L143-L161：``get_default_variables`` 生成 simulator YAML 变量默认值，包括 tb/build/out、
  seed、binary、rtl_test、sim/cov/wave opts 和 timeout。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/get_fcov.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/get_fcov.py:全文

逐段精读：

* L1-L13：脚本头说明收集 riscv-dv functional coverage，import argparse、subprocess 和
  logging。
* L15-L34：CLI 参数包括 metadata 目录、simulator、coverage 输出目录和 verbose；默认
  coverage 输出目录为 ``<metadata>/fcov``。
* L35-L58：VCS 模式递归查找 ``*.vdb``，没有 DB 时给 warning 并返回 0；有 DB 时调用
  ``urg -dir`` 合并并输出 both 格式报告。
* L59-L66：Xcelium 模式当前只给出 IMC 使用提示，脚本返回 0。完整 NC/IMC merge 由
  ``merge_cov.py`` 覆盖。

§16  v2-34 ``report_lib`` 报告后端全文行段级精读
--------------------------------------------------------------------------------

本节补齐 ``dv/uvm/core_eh2/scripts/report_lib`` 下所有 Python 报告后端的全文
``literalinclude``。这些文件不重新运行仿真，也不改变 test result；它们只把
``RegressionSummary``、``TestRunResult``、test summary dict 和 coverage summary dict
转换成 text、JUnit XML、HTML、SVG 与 dvsim JSON。

§16.1  ``util.py`` — 报告通用格式化工具
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/util.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/util.py:全文

逐段精读：

* L1-L13：文件头说明该模块从 Ibex 报告工具迁移而来，import 覆盖 dataclass
  转 dict、正则和字符串缓冲区。这里的 ``re`` 与 ``io`` 当前没有被下方逻辑使用，属于
  上游迁移遗留依赖。
* L14-L29：``CSS_RG_GRADIENT_YELLOW_POINT`` 把红黄绿渐变的黄色分界固定在 0.7；
  ``css_red_green_gradient`` 将 0 到 1 的比例映射成 CSS ``rgb(r,g,0)``。低于 0.7
  时红色保持满值、绿色线性增加；高于 0.7 时绿色保持满值、红色线性下降。
* L32-L50：``gen_test_run_result_text`` 先构造 ``test.seed`` 标题，再从
  ``TestRunResult`` dataclass 中抽取 binary、RTL log、trace 和 ISS cosim log。路径字段若能
  相对 ``dir_test`` 表示，就输出相对路径；缺失值统一写成 ``MISSING``，便于失败报告定位。
* L51-L60：函数把抽取后的字段渲染成 YAML-like 行，并按 ``trr.passed`` 追加
  ``[PASSED]`` 或 failure message。该字符串被 text、JUnit 和 HTML 报告复用，因此这里是
  单个 test run 详情格式的唯一公共入口。
* L63-L76：``create_test_summary_dict`` 按 test name 聚合 passing/failing 计数。它不看
  seed，也不重新解析 log，只消费已经判定好的 ``TestRunResult`` 列表，为 HTML、SVG 和
  dvsim JSON 提供相同的 per-test summary。

§16.2  ``text.py`` — plain text 回归报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/text.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/text.py:全文

逐段精读：

* L1-L13：文件头说明本模块生成纯文本回归报告，依赖 ``scripts_lib.pprint_dict`` 输出
  YAML-like 摘要，并复用 ``util.gen_test_run_result_text`` 输出单测详情。
* L16-L19：``box_comment`` 生成 80 个 ``#`` 组成的分隔标题。它只负责视觉分区，
  不参与 pass/fail 判定。
* L21-L28：``gen_summary_line`` 计算总测试数和通过率。没有测试时返回 ``No tests run``，
  避免除零；有测试时输出固定格式 ``xx.xx% PASS N PASSED, M FAILED``，这是
  ``regr.log`` 顶部最直接的人工读数。
* L31-L43：``output_results_text`` 先写 summary line，再把 ``summary_dict`` 经
  ``pprint_dict`` 写成短摘要。``summary_dict`` 通常来自 ``RegressionSummary``，键值是
  ``TEST.SEED`` 到 PASS/FAIL 的映射。
* L45-L57：报告后半段先列失败测试，再列通过测试。每个 entry 都调用
  ``gen_test_run_result_text``，因此失败与通过详情保持同一字段集合；没有对应测试时输出
  ``No failing tests.`` 或 ``No passing tests.``。

§16.3  ``junit_xml.py`` — CI 可消费 XML
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/junit_xml.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/junit_xml.py:全文

逐段精读：

* L1-L13：文件头说明该模块生成 JUnit XML，import 使用标准库
  ``xml.etree.ElementTree`` 构造节点，再用 ``xml.dom.minidom`` 美化输出。它同样复用
  ``gen_test_run_result_text`` 作为 stdout/failure 内容。
* L16-L29：``TestCase`` 是轻量 JUnit test case model，保存 name、stdout、stderr、
  failure message 和 failure output。``add_failure_info`` 只填充失败字段，不改变测试判定。
* L31-L37：``TestSuite`` 保存 suite 名称和 test case 列表。这里没有继承外部 JUnit 库，
  使生成逻辑完全由本仓库控制。
* L39-L66：``to_xml_report_string`` 把 suite model 转成 ``testsuites`` 根节点。
  每个 suite 写 ``name``、``tests`` 和 ``failures`` 属性；每个 case 写 ``testcase``、
  可选 ``stdout`` 和可选 ``failure`` 节点，最后返回格式化 XML 字符串。
* L69-L95：``output_run_results_junit_xml`` 合并 passing 与 failing 列表，以 test name
  分组。普通 XML 模式下，一个 seed 对应一个 ``TestCase``；失败 seed 会把完整 run detail
  写入 failure output，同时把失败详情追加到 merged accumulator。
* L97-L111：函数写出两份 XML。普通版保留每个 seed 的 test case；merged 版每个 test
  name 只有一个 test case，stdout 聚合所有 seed，failure 聚合失败 seed。CI 可以用普通版看
  粒度，也可以用 merged 版减少 testcase 数量。

§16.4  ``html.py`` — 轻量 HTML 回归页
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/html.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/html.py:全文

逐段精读：

* L1-L13：文件头仍保留早期 Mako 模板描述，但当前实现使用字符串拼接，不依赖 Mako。
  import 中 ``os`` 当前未被使用；核心依赖是 ``datetime``、CSS 渐变和 test run 详情格式化。
* L16-L23：``pct_str`` 把 0 到 1 的比例格式化为一位小数百分比；``pct_style`` 把同一比例
  转成带背景色的 CSS style。这样通过率和覆盖率在 HTML 表格里使用同一颜色语义。
* L26-L50：``output_results_html`` 先遍历 ``test_summary_dict``，为每个 test 计算
  total、passing 和 pass rate，并累计全局 total/passing。空测试集时全局通过率退化为 0，
  避免除零。
* L52-L68：函数开始拼接完整 HTML 文档、内联 CSS 和标题时间戳。报告是自包含字符串，
  不需要额外 CSS 或模板文件。
* L69-L83：Test Results 表展示每个 test name 的 passing、total 和 pass rate，并追加
  Total 行。pass rate 单元格调用 ``pct_style``，因此红黄绿颜色与其它报告后端保持一致。
* L85-L95：如果传入 coverage summary，就生成 Coverage 表；值为 ``None`` 的 metric 被跳过，
  防止未知覆盖率被渲染成误导性百分比。
* L96-L108：Failure Details 区只列失败测试。没有失败时输出明确的 ``No failing tests.``；
  有失败时把 ``gen_test_run_result_text`` 的内容放入 ``pre``，最后把 HTML 行列表写入
  ``dest``。

§16.5  ``svg.py`` — 单行 dashboard 徽章
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/svg.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/svg.py:全文

逐段精读：

* L1-L8：文件头说明该模块生成 SVG dashboard。``dedent`` 用于写内联 style，
  ``reduce`` 用于计算 dashboard 总宽，颜色仍来自 ``css_red_green_gradient``。
* L10-L22：常量定义 dashboard 高度、元素间距、文字样式、默认 value 宽度、name 背景色和
  普通 value 背景色。这些值固定了徽章的像素布局。
* L24-L58：``DashboardElement`` 表示一个 name/value pair。``to_svg`` 生成左右两个矩形与
  居中文本；``calc_total_width`` 返回 name 与 value 的总宽，用于后续水平排布。
* L61-L85：``Dashboard`` 持有多个元素并按 ``element_gap`` 横向排列。``to_svg`` 为每个元素
  包一层 translate；``calc_total_width`` 把所有元素宽度和间距相加，并扣除最后一个多余间距。
* L88-L105：``output_results_svg`` 先汇总 passing/failing/total。没有测试时写空 SVG 并返回；
  有测试时计算 passing percentage。
* L107-L130：函数固定创建 Total Tests 和 Tests Passing 两个元素；有 coverage summary 时，
  额外创建 Functional Coverage 和 Code Coverage。Code Coverage 取 block、branch、
  statement、expression、fsm 五类均值，缺失项按 0 处理。
* L132-L143：最终把 dashboard 包进顶层 ``<svg>``，宽度来自 ``calc_total_width``，高度来自
  常量，并把内联 style 与所有 element SVG 写入 ``dest``。

§16.6  ``dvsim_json.py`` — dvsim 兼容 JSON
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/report_lib/dvsim_json.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/report_lib/dvsim_json.py:全文

逐段精读：

* L1-L6：文件头说明该模块输出 dvsim-compatible JSON；只依赖 ``typing`` 和标准库
  ``json``。
* L9-L27：``create_dvsim_report_dict`` 为每个 test summary entry 计算 total runs 与
  pass rate，并生成 dvsim ``unmapped_tests`` 条目。total 为 0 时 pass rate 置 0，避免除零。
* L29-L35：coverage summary 若存在，会把仓库内部 0 到 1 的比例转换成 dvsim 常见的
  0 到 100 百分数；没有 coverage 时输出空 dict。
* L37-L46：返回 dict 的顶层字段包括 tool、block name、block variant 和 results。
  ``xlm`` 会被映射为 ``xcelium``，以匹配 dvsim 对 Cadence simulator 名称的约定。
* L49-L61：``output_results_dvsim_json`` 设置默认 tool/block/variant，调用
  ``create_dvsim_report_dict`` 后用 indent 2 序列化并写入 ``dest``。调用方无需关心 JSON
  schema 细节。

§17  v2-36 scripts/tests 中短回归测试全文行段级精读
--------------------------------------------------------------------------------

本节补齐 ``dv/uvm/core_eh2/scripts/tests`` 中两个中短 pytest 文件的全文
``literalinclude``。超长 ``test_regression_framework.py`` 独立留到后续阶段，避免把
2273 行 regression framework fixture 与这两个 focused parser/report 单测混成一个提交。

§17.1  ``test_gen_html_report.py`` — HTML sign-off report 回归测试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/tests/test_gen_html_report.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/tests/test_gen_html_report.py:全文

逐段精读：

* L1-L12：文件头说明这是自包含 HTML sign-off report 的测试。测试把
  ``dv/uvm/core_eh2/scripts`` 插入 ``sys.path`` 后 import ``gen_html_report``，
  验证该脚本既能作为 CLI 使用，也能被 pytest 直接导入。
* L15-L37：``test_parse_urg_report_reads_summary_modules_and_groups`` 在临时目录构造
  ``dashboard.txt``、``modlist.txt`` 和 ``groups.txt``。fixture 覆盖三类 URG 文本：
  top summary、module coverage list 和 covergroup list。
* L38-L45：测试调用 ``parse_coverage_report`` 并断言 number of tests、line coverage、
  functional coverage、module 名和 group 名。这里锁定的是 HTML dashboard 输入解析契约，
  不是仿真本身。
* L47-L92：``test_collect_report_data_creates_relative_log_links`` 构造一个最小
  sign-off status：smoke stage 有一条 passing test 和真实 log path，syn stage 有一个
  LEC module 摘要，并携带 cosim-disabled/skip-in-signoff 列表。
* L93-L108：测试再写一个 coverage dashboard 和 ``status.json``，调用
  ``load_report_data``。断言重点是 test entry 数量、相对 ``log_href`` 和 LEC module 名称，
  防止 HTML 报告把本地绝对路径暴露给浏览器。
* L110-L128：``test_render_html_is_self_contained_and_contains_real_data`` 依赖真实
  R3-B sign-off artifact；artifact 不存在时 skip。存在时它要求 HTML 包含 dashboard 标题、
  coverage 数字、LEC passing 数、54/55 口径、log href 和真实 simulation 名，同时禁止
  CDN 或远程 ``src``，保证报告可离线归档。

§17.2  ``test_parse_coverage.py`` — signoff 覆盖率文本解析回归
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/tests/test_parse_coverage.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/tests/test_parse_coverage.py:全文

逐段精读：

* L1-L8：文件头说明测试目标是 ``signoff.parse_coverage_text``。测试通过
  ``sys.path.insert`` 直接导入 ``signoff``，让 parser 单测不依赖 package 安装。
* L10-L25：``test_urg_dashboard_header_format`` 构造 URG ``Total Coverage Summary`` 的
  标准 header/data 连续行，断言 line、cond、toggle、fsm、assert 和 overall 六个维度。
* L28-L39：``test_urg_dashboard_header_with_blank_line`` 覆盖 header 与 data 中间有空行的
  dashboard。解析器必须跳过空行，不能因为 URG 输出格式变化而丢 metric。
* L41-L50：``test_urg_hierarchical_dashboard`` 覆盖带 ``NAME`` 列的 per-instance
  coverage 行。该格式常见于层级 module/table，解析器只应提取前面的数值列。
* L52-L76：三个 old-style fallback 测试覆盖 ``Line Coverage:``、
  ``Condition Coverage =`` 以及多个旧式 metric 混排。它们保证 parser 能消费历史日志或
  非 URG dashboard 文本。
* L79-L89：``test_urg_takes_precedence`` 同时放入 URG header 和旧式 line coverage。
  断言旧式 fallback 不能覆盖已经由 URG parser 读到的 line 口径。
* L91-L103：``test_various_spacing`` 覆盖 header 列之间有不规则空格的情况。解析器必须按
  token 而不是固定列宽提取 coverage 数字。
* L106-L108：空字符串返回空 dict，给 sign-off coverage 缺失路径提供可预测结果。
* L111-L121：``test_total_module_definition`` 覆盖 ``Total Module Definition Coverage
  Summary``，保证 module-definition 报告仍能写出 overall、line 和 assert。
* L124-L133：``test_urg_group_dashboard_maps_to_functional`` 覆盖只有 ``GROUP`` 的 summary。
  这类 dashboard 应把 group coverage 映射为 ``functional``，供 sign-off HTML 和 gate
  复用统一字段。

§18  v2-37 ``test_regression_framework.py`` 全文行段级精读
--------------------------------------------------------------------------------

``test_regression_framework.py`` 是当前 UVM scripts 测试目录中最长的回归测试文件。
它不是一个单一 parser 单测，而是把 regression framework 的端到端契约拆成多个
``unittest`` case：riscv-dv 生成、directed/cosim testlist、metadata staged flow、
RTL simulation、log 判定、assembly compile、report JSON、AXI/cosim scoreboard、
Spike DPI lifetime，以及 sign-off gate 都在这里有防退化断言。

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/tests/test_regression_framework.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/scripts/tests/test_regression_framework.py:全文

逐段精读：

* L1-L28：测试文件入口导入 tempfile、unittest、json、yaml、mock 和 Path，把
  ``dv/uvm/core_eh2/scripts`` 插入 ``sys.path``，随后直接导入 run_regress、run_rtl、
  run_instr_gen、compile_test、collect_results、metadata、signoff 等脚本模块。这个导入方式
  模拟本仓库脚本被本地 pytest/unittest 直接运行的真实环境。
* L29-L79：``RegressionFrameworkTest`` 开头覆盖 riscv-dv assembly 搜索、cosim enable/disable
  plusarg 拼接，以及主 testlist 中已知非 cosim 测试的 ``cosim: disabled`` 标记。这里锁住
  regression test entry 到 simulator plusarg 的最早转换层。
* L80-L202：第一组 ``run_rtl`` 测试覆盖 shared build/out log command 生成、已有 ``simv``
  时跳过 compile、零返回码但无 PASS signature 时失败，以及缺失 simulator YAML 时返回
  ``CONFIG_ERROR``。这保证 RTL runner 不把 simulator return code 当作唯一真相。
* L204-L356：metadata-mode ``run_rtl`` 测试覆盖 directed/cosim testlist policy、
  compile failure 时保留既有 ``COMPILE_ERROR``，以及 riscv-dv entry 的 sim opts 合并。
  这些断言保证 staged wrapper 按 ``TEST.SEED`` 传入时不会丢失 test type、rtl_test 或
  cosim policy。
* L358-L459：``run_instr_gen`` 相关测试验证 riscv-dv 路径在 ``chdir`` 前解析、额外
  ``gen_opts`` 写入 overlay testlist，而不是直接拼到命令行，并确认 EH2 asm generator override、
  signature address 要求和 ``d0580000`` 地址进入 ``--sim_opts``。
* L461-L545：静态源码契约测试检查 riscv-dv setting 使用当前类型名、EH2 asm program gen
  只有带 hart 参数的 init override、base test 安装 EH2 report server、report server 的 PASS/FAIL
  不受 warning 影响、directed stream 使用 ``instr_list``，以及 TB/fcov/PMP 连接宽度和默认关闭
  状态正确。
* L546-L620：cosim/trace/Spike/AXI 低层契约测试覆盖：cosim scoreboard 在启用但无 step 时失败，
  async writeback source tag 区分 DIV 与 non-blocking load，Spike 允许被抑制的 DIV writeback，
  AXI memory hex loader 必须消费 ``$fgets``/``$sscanf`` 返回值。
* L622-L695：VCS compile 与 RTL cast bridge 测试检查 Makefile 不再使用危险 ``-sv_lib``/wildcard
  linking，``compile_vcs`` 对 ``libcosim.so`` 有硬依赖，``NO_COSIM=1`` 可显式跳过 cosim link，
  IFU enum state flop 通过 vector bridge 连接 ``rvdff``。
* L697-L793：``run_single_test`` 失败路径测试覆盖 generator failure、compile failure 和
  Python 3.6 兼容 subprocess capture。失败时必须保留 gen/compile log、写出 ``result.pkl``，
  并使用 ``stdout=PIPE``/``stderr=PIPE`` 而不是 Python 3.7 才有的 ``capture_output``。
* L795-L977：``check_logs`` 核心分类测试覆盖显式 PASS signature、simulator crash、
  nonzero return code、UVM summary 零计数、warning-clean 模式、VCS banner 与 UVM_FATAL summary
  重叠、真实 UVM_FATAL、以及 EH2 FAILED banner。这里定义了 log 到 ``failure_mode`` 的主要安全网。
* L979-L1134：metadata-mode log/run 测试确认 ``check_logs.main`` 对失败测试仍返回 0，
  方便 Make 继续收集结果；同时保留 sim return code、directed test type 和 pre-sim compile
  failure。``run_rtl.main`` 也在 metadata mode 下写 pickle 并返回 0。
* L1136-L1328：assembly compile 与 single-test 细节测试覆盖 riscv-dv user extension include、
  VMA-addressed hex 输出、generated hex 传给 RTL、sim return code 参与 log check、warning/error
  count 写入结果。这一段保护 assembly 到 binary/hex 再到 simulation 的数据路径。
* L1330-L1454：report collection 测试覆盖 ``run_regression`` 写 ``report.json``、
  默认 linker 把 generated RAM 放到外部 memory、``collect_results`` 从 pickle 生成 text/JUnit/JSON，
  report JSON 包含诊断路径和计数，并优先使用最终 ``result.pkl`` 而非中间 RTL result。
* L1456-L1567：Ibex-style wrapper 与 metadata 测试检查 wrapper/get_meta/util 文件存在、
  wrapper target 列表齐全，``create_metadata`` 生成 YAML/pickle 并导出字段，
  directed/cosim/all_cosim test selection 被正确分类，config template 根据 EH2 profile 过滤 ISA。
* L1569-L1720：``compile_test`` metadata mode 覆盖 directed、riscv-dv 和 cosim entry。
  directed/cosim 使用 testlist 中的 assembly 与 linker，riscv-dv 使用 generator 输出 assembly 和
  默认 ``scripts/link.ld``。
* L1722-L1834：compile failure、instr_gen metadata mode 和 run_rtl metadata mode 测试确认：
  compile 失败会写 ``compile.log`` 和 result，instruction generator work dir 使用
  ``run/tests/TEST.SEED``，RTL metadata mode 使用 ``test.hex`` 和共享 build dir。
* L1836-L1899：directed/cosim testlist 与 debug coverage 测试验证 YAML 文件存在并可解析，
  cosim suite 包含 7 个指定测试且使用 ``core_eh2_cosim_test``，directed override 保留
  debug plusarg 和 cosim disabled，debug sequence 覆盖 DMI 命令路径。
* L1901-L1995：directed single-test、coverage/waves 和 warning-clean 测试确认 directed assembly
  不经过 instruction generator，coverage/waves 选项能转发给 RTL runner，tool warning 在
  warning-clean 模式下会变成 ``TOOL_WARNING``，VCS compile 指定唯一 testbench top。
* L2003-L2069：AXI agent 和 cosim scoreboard 测试检查 AXI agent 按 ID width 参数化、
  SB monitor 连接、同周期 write address/data handshake 可捕获，store/AMO trace 会等待 LSU AXI，
  而 EH2 内部 forwarded load 可以无外部 AXI retire。
* L2071-L2139：cosim DPI 与 Spike lifetime 测试禁止 ``/tmp`` debug side effect，确认 mcycle sync
  不直接写 Spike CSR，DPI init 返回调整后的 ``Cosim`` 指针，``isa_parser`` 保持存活，
  并允许 EH2 widened AXI load/store byte enable 与 forwarded load without pending dside。
* L2141-L2273：最后一组覆盖项目 README 与 sign-off gate：README 必须说明 Ibex parity、quick start
  和 known limitations；signoff dry-run 能列出 Ibex-style stages；gate-only 模式能接受 clean
  stage result 或 archived ``report.json``，跳过未要求 coverage 的 ambient build 报告，并在已有
  failed stage result 时返回失败。
