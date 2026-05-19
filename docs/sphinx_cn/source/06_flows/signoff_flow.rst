.. _signoff_flow:
.. _06_flows/signoff_flow:

签核流程 - 详细参考
================================================================================

:status: draft
:source: Makefile; dv/uvm/core_eh2/scripts/signoff.py; dv/uvm/core_eh2/scripts/gen_html_report.py; dv/uvm/core_eh2/tests/test_signoff_gates.py; docs/signoff-gates.md; dv/uvm/core_eh2/waivers/cosim-disabled.yaml; syn/build/lec_summary.txt
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
--------------------------------------------------------------------------------

读懂本章前，请先确认你已经掌握：

* :ref:`glossary_pretest` — 能区分 smoke、regress、sign-off、coverage、waiver 和 LEC；
* :ref:`build_flow` — 知道 ``make signoff`` 会先编译，再由 ``signoff.py`` 调度 stage；
* :ref:`regression_flow` — 知道 ``report.json``、``result.yaml`` 和 ``regr.log`` 的来源；
* :ref:`functional_coverage` — 知道 LINE/GROUP/OVERALL 的区别；
* 基础 Python ``argparse``、JSON、YAML 和返回码概念。

本章讨论的 sign-off（签核）不是“跑一个测试通过”，而是把 smoke、directed、cosim、
riscv-dv、lint、CSR unit、compliance、formal 和 syn/LEC 9 个 stage 合并成一个
可审计结论。默认 simulator 是 VCS；NC/Incisive 是完整备选 simulator，可显式用
``SIMULATOR=nc`` 跑 sign-off/cross-check，产物与 VCS 按 ``build/<target>_<simulator>/``
隔离。

学完本章你应该能够：

1. 解释 ``make signoff``、``make signoff GATE_ONLY=1`` 和 ``make signoff_replay`` 的区别。
2. 说明 25% fail-rate ceiling 为什么比单纯 pass count 更严格。
3. 在 ``signoff_status.json``、``signoff_report.md`` 和 ``report.html`` 中找到同一
   stage 的 PASS/FAIL 证据。
4. 解释 LINE 95.05%、GROUP 69.42%、实跑覆盖率 102/104 和 LEC 31635/31635 分别来自哪里。
5. 当 full profile FAIL 时，按 precheck、stage、coverage、waiver、LEC 的顺序排查 blocker。

§1  流程边界
--------------------------------------------------------------------------------

本章只解释 EH2 sign-off driver 的当前代码行为：顶层 :file:`Makefile`
如何调用 :file:`dv/uvm/core_eh2/scripts/signoff.py`，`signoff.py`
如何把 stage 执行、已有结果复用、coverage gate、waiver gate、LEC/formal
收集和 JSON/Markdown/HTML 报告串成一个 CI 返回码。

本章的签核事实以 2026-05-19 01:02 VCS 主线 demo 为准。该 run 使用
Synopsys VCS、``cover.cfg`` DUT-only scope、URG 原生 dashboard、block-level
Formality LEC，完成 9/9 stages PASS。NC/Incisive 是完整备选 simulator，可通过
``SIMULATOR=nc`` 跑 compile、smoke、regress、sign-off、demo 和波形调试；VCS 仍是
默认主线和 Ibex 对齐路径。

.. list-table::
   :header-rows: 1
   :widths: 18 18 16 48

   * - 项目
     - 2026-05-19 数字
     - 状态
     - 证据边界
   * - full profile
     - 9/9 stages
     - PASS
     - ``signoff.py`` full profile
   * - formal
     - 46/46
     - PASS
     - :file:`dv/formal/build/ifv_final.log`
   * - LEC
     - 31635/31635
     - PASS
     - :file:`syn/build/lec_summary.txt`
   * - compliance
     - 85/88 (96.59%)
     - PASS
     - compliance stage report
   * - riscv-dv
     - 370/395 (93.67%)
     - PASS
     - riscv-dv extension stage
   * - csr_unit
     - 20/20
     - PASS
     - CSR unit sub-env
   * - directed
     - 40/40 (100%)
     - PASS
     - directed ASM suite
   * - cosim
     - 7/7
     - PASS
     - cosim waiver gate clean
   * - real run coverage
     - 102/104 (98.1%)
     - PASS
     - Markdown report ``实跑覆盖率`` 字段
   * - coverage dashboard
     - LINE 95.05%、GROUP 69.42%、OVERALL 65.17%
     - PASS
     - URG native ``dashboard.txt``

当前 coverage 维度固定为 ``-cm line+tgl+assert+fsm+branch``。URG dashboard 中
``GROUP`` 来自 SystemVerilog covergroup，脚本内部仍以 ``functional`` 作为历史
兼容键名；这不表示 sign-off 重新引入 ``cond`` 维度。

`signoff.py` 的运行数据流如下。左侧是输入配置和已有工具输出，中间是
Python driver，右侧是签核产物和进程退出码：

.. code-block:: bash

   Makefile signoff/signoff_gate
        |
        v
   signoff.py --profile/--stages/--stage-result/--coverage-path
        |
        +-- precheck: filelist, simulator, GCC, riscv-dv, libcosim, NUM_THREADS
        +-- run or reuse stage directories
        +-- collect: regression, lint, formal, syn, compliance
        +-- evaluate: pass-rate, coverage, waiver, directed pool, real-run pool
        |
        v
   signoff_status.json + signoff_report.md + optional report.html + exit code

这张图只描述代码里的控制流：`main()` 在解析参数后生成 `planned` stage
列表，按顺序执行或复用每个 stage，再在所有 stage 结果收集完成后统一计算
coverage、waiver 和最终 `status`。stage 内部的并行度来自
`run_regress.py --parallel`，不是 `signoff.py` 自己创建线程。

**接口关系**：

* **上层调用**：:file:`Makefile` 的 `signoff`、`signoff_gate` 和
  `html_report` target。
* **下层调用**：:file:`dv/uvm/core_eh2/scripts/run_regress.py`、
  lint/formal/syn/compliance make target、:file:`gen_html_report.py`。
* **共享状态**：输出目录、per-target `simv`、coverage dashboard、waiver YAML、
  stage report JSON/result pickle、`syn/build/lec_summary.txt`。

§2  顶层 Make target
--------------------------------------------------------------------------------

§2.1  `SIGNOFF_*` 变量 - Makefile 侧默认入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：顶层 :file:`Makefile` 为 `signoff.py` 提供 profile、输出目录、
附加参数、LEC block-level 开关和 HTML dashboard 默认路径。

**关键代码** （`Makefile:L125-L154`）：

.. code-block:: makefile

   PROFILE         ?= full
   GATE_ONLY       ?= 0
   CLEANUP         ?= 0
   SIGNOFF_OUT     ?= $(BUILD_DIR)/signoff
   SIGNOFF_OPTS    ?=
   SIGNOFF_ITERATIONS ?=
   LEC_KNOWN_LIMITED  ?= 0
   LEC_BLOCKLEVEL  ?= 1
   LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt

   SIGNOFF_MIN_LINE_COV       ?= 65
   SIGNOFF_MIN_FUNCTIONAL_COV ?= 40
   SIGNOFF_ALLOW_WARNINGS     ?= 1

**逐段解释**：

* 第 L125 行：`PROFILE` 默认是 `full`，对应 `signoff.py`
  中包含 9 个 stage 的 profile。
* 第 L126-L128 行：`GATE_ONLY` 控制是否只评估已有结果，`CLEANUP` 控制结束后
  是否做 lock-only 清理，默认输出目录是 `build/signoff`。
* 第 L129-L130 行：`SIGNOFF_OPTS` 和 `SIGNOFF_ITERATIONS` 是透传参数，
  Makefile 不解释其语义。
* 第 L131-L134 行：`LEC_BLOCKLEVEL` 默认打开，sign-off 优先读取
  :file:`syn/build/lec_summary.txt` 的 31635/31635 block-level LEC 结果。
* 第 L138-L141 行：line 门限默认 65，covergroup/GROUP 门限默认 40，warning
  默认允许；这与 2026-05-19 demo 的 LINE 95.05% 和 GROUP 69.42% 匹配。

**接口关系**：

* **被调用**：用户执行 `make signoff`、`make signoff_gate` 或
  `make html_report` 时读取这些变量。
* **调用**：变量被 recipe 展开后传给 `signoff.py` 或 `gen_html_report.py`。
* **共享状态**：`BUILD_DIR`、`OUT`、`SIGNOFF_OUT`、`COV`、`WAVES`。

§2.2  `signoff` target - 运行或复用完整 stage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：`signoff` target 把 Make 变量转换为 `signoff.py` CLI 参数。

**关键代码** （`Makefile:L1236-L1268`）：

.. code-block:: makefile

   SIGNOFF_LEC_OPTS := $(if $(filter 1,$(LEC_BLOCKLEVEL)),$(if $(wildcard $(LEC_SUMMARY_PATH)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),--lec-known-limited),$(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,))

   signoff:
       @# VCS 是 sign-off 默认；NC 也可作 cross-check（覆盖率独立合并，
       @# 维度名与 VCS 同构但工具不同，参见 cover.cfg / cov_full_nc.ccf）。
       @if [ "$(SIMULATOR)" != "vcs" ] && [ "$(SIMULATOR)" != "nc" ]; then \
         echo "ERROR: signoff 仅支持 SIMULATOR=vcs (默认) 或 SIMULATOR=nc (当前为 $(SIMULATOR))。"; \
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

**逐段解释**：

* 第 L1236-L1240 行：`SIGNOFF_LEC_OPTS` 先判断 block-level summary 是否存在。
  存在时走 `--lec-blocklevel --lec-summary-path`；不存在时转入
  `--lec-known-limited`，使报告明确暴露 LEC 证据缺口。
* 第 L1242-L1253 行：`make signoff` 接受 `SIMULATOR=vcs|nc`。VCS 是默认主线；
  NC 作为备选/cross-check 时会打印提示，但不会被拒绝。
* 第 L1254-L1255 行：非 `GATE_ONLY` 时先运行 ASM 和 compile，compile 使用
  `BUILD_SUBDIR=$(SIGNOFF_OUT)`，保证 sign-off 有自己的 per-simulator build island。
* 第 L1256-L1268 行：coverage 阈值来自 Make 变量，默认 line 65、GROUP/function
  40；`SIGNOFF_ALLOW_WARNINGS=1` 会传入 `--allow-warnings`。

**接口关系**：

* **被调用**：顶层 `make signoff`。
* **调用**：`signoff.py main()`。
* **共享状态**：`PROFILE`、`SIMULATOR`、`SEED`、`PARALLEL`、
  `SIGNOFF_OUT`、`LEC_*`、`COV`、`WAVES`。

§2.3  `signoff_gate` target - 只评估已有结果
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：`signoff_gate` 不启动 stage，只让 `signoff.py` 进入
`--gate-only` 路径，适合重放已有结果目录。

**关键代码** （`Makefile:L1095-L1116`）：

.. code-block:: makefile

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
   	  $(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,) \
   	  --coverage --min-line-coverage $(SIGNOFF_MIN_LINE_COV) --min-functional-coverage $(SIGNOFF_MIN_FUNCTIONAL_COV) \
   	  $(if $(wildcard $(STAGE_DATA_DIR)/cov_merged/dashboard.txt),--coverage-path $(STAGE_DATA_DIR)/cov_merged/dashboard.txt,) \
   	  --allow-warnings \
   	  $(SIGNOFF_OPTS)

**逐段解释**：

* 第 L1095-L1105 行：`signoff_replay` 固定使用 full profile 和 `--gate-only`，
  并从 `STAGE_DATA_DIR/runs/<stage>` 读取已有 smoke、directed、cosim、riscvdv、
  csr_unit 与 compliance 结果。
* 第 L1106-L1114 行：LEC、coverage path、coverage 阈值和 warning 策略都由
  Make 变量传入。coverage path 只在 `cov_merged/dashboard.txt` 存在时追加。
* 第 L1115-L1116 行：用户仍可通过 `SIGNOFF_OPTS` 添加额外 gate 参数。

**接口关系**：

* **被调用**：顶层 `make signoff_replay`。
* **调用**：`signoff.py main()` 的 `args.gate_only` 分支。
* **共享状态**：已有 stage 输出目录、`SIGNOFF_REPLAY_OUT` 和
  `syn/build/lec_summary.txt`。

§3  `signoff.py` 全局配置
--------------------------------------------------------------------------------

§3.1  路径常量和导入关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：脚本在启动时定位 EH2 repo 根、DV 目录和默认输出目录，并导入
regression 收集器与 log checker。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L26-L34`）：

.. code-block:: python

   SCRIPT_DIR = Path(__file__).resolve().parent
   DV_DIR = SCRIPT_DIR.parent
   EH2_ROOT = DV_DIR.parents[2]
   DEFAULT_OUT = EH2_ROOT / "build" / ("signoff_" + time.strftime("%Y%m%d_%H%M%S"))
   
   sys.path.insert(0, str(SCRIPT_DIR))
   from collect_results import collect_results, write_reports  # noqa: E402
   from check_logs import check_sim_log  # noqa: E402
   from metadata import RegressionSummary, TestRunResult  # noqa: E402

**逐段解释**：

* 第 L26-L29 行：`SCRIPT_DIR` 指向 scripts 目录，`DV_DIR` 指向
  `dv/uvm/core_eh2`，`EH2_ROOT` 通过 `DV_DIR.parents[2]` 回到 repo 根；
  默认输出目录带当前时间戳。
* 第 L31-L34 行：脚本把 `SCRIPT_DIR` 插入 `sys.path` 后导入本地
  `collect_results`、`check_logs` 和 `metadata`。这说明 stage 结果格式沿用
  regression 框架，而不是 sign-off 自己定义新的测试结果类。

**接口关系**：

* **被调用**：Python 解释器加载 `signoff.py` 时执行。
* **调用**：本地模块 `collect_results.py`、`check_logs.py`、`metadata.py`。
* **共享状态**：repo 路径、默认输出目录、Python import path。

§3.2  `PROFILE_STAGES` - profile 到 stage 的映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：定义 `--profile` 可展开出的 stage 列表。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L37-L44`）：

.. code-block:: python

   PROFILE_STAGES = {
       "quick": ["smoke", "directed"],
       "cosim": ["smoke", "cosim"],
       "riscvdv_smoke": ["riscvdv"],
       "nightly": ["smoke", "directed", "cosim", "riscvdv"],
       "full": ["smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                "compliance", "formal", "syn"],
   }

**逐段解释**：

* 第 L38 行：`quick` 只跑 `smoke` 和 `directed`。
* 第 L39 行：`cosim` 跑 `smoke` 和 `cosim`。
* 第 L40 行：`riscvdv_smoke` 只跑 `riscvdv`。
* 第 L41 行：`nightly` 覆盖 simulation 类 stage，但不包含 lint、CSR unit、
  compliance、formal 和 syn。
* 第 L42-L43 行：`full` 包含 9 个 stage，是 2026-05-19 VCS 主线 sign-off 的
  profile 基础，顺序为 smoke、directed、cosim、riscvdv、lint、csr_unit、
  compliance、formal、syn。

**接口关系**：

* **被调用**：`argparse` 的 `--profile choices` 和 `resolve_stages()`。
* **调用**：无下层函数。
* **共享状态**：stage 名称必须与 `build_stage_cmd()` 和 `collect_*_stage()`
  的分支一致。

§3.3  `STAGE_MIN_PASSED` 和 `STAGE_TESTLIST`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：为部分 stage 定义最小通过数，并把 simulation stage 绑定到 YAML
testlist。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L46-L59`）：

.. code-block:: python

   STAGE_MIN_PASSED = {
       "smoke": 1,
       "directed": 33,
       "cosim": 7,
       "riscvdv": 50,
       "csr_unit": 20,
       "compliance": 85,
   }
   
   STAGE_TESTLIST = {
       "directed": DV_DIR / "directed_tests" / "directed_testlist.yaml",
       "cosim": DV_DIR / "directed_tests" / "cosim_testlist.yaml",
       "riscvdv": DV_DIR / "riscv_dv_extension" / "testlist.yaml",
   }

**逐段解释**：

* 第 L46-L53 行：`smoke`、`directed`、`cosim`、`riscvdv`、`csr_unit`、
  `compliance` 有最小通过数。`collect_stage()` 和 `evaluate_signoff()` 都会
  使用这些阈值。
* 第 L55-L59 行：只有 `directed`、`cosim`、`riscvdv` 通过
  `run_regress.py --testlist` 读取 YAML。`lint`、`formal`、`syn`、
  `csr_unit`、`compliance` 走专门命令或专门收集器。

**接口关系**：

* **被调用**：`build_stage_cmd()`、`collect_stage()`、
  `compute_real_run_count()`、`evaluate_signoff()`。
* **调用**：无下层函数。
* **共享状态**：YAML testlist 路径和 release gate 的最小通过数。

§3.4  `COVERAGE_METRIC_ALIASES` - coverage 名称归一化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把 URG dashboard 或文本报告里的 coverage 字段名映射到
`overall`、`line`、`cond`、`fsm`、`toggle`、`branch`、`assert`、
`functional` 等内部键。这里的 `cond` 只是历史文本解析兼容项；当前 VCS
编译选项不采集 `cond`，sign-off dashboard 只按 ``line+tgl+assert+fsm+branch``
五个 VCS 维度加 ``GROUP`` covergroup 结果解释。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L70-L88`）：

.. code-block:: python

   COVERAGE_METRIC_ALIASES = {
       "overall": "overall",
       "total": "overall",
       "score": "overall",
       "line": "line",
       "lines": "line",
       "cond": "cond",
       "condition": "cond",
       "conditions": "cond",
       "fsm": "fsm",
       "toggle": "toggle",
       "tgl": "toggle",
       "branch": "branch",
       "assert": "assert",
       "assertion": "assert",
       "group": "functional",
       "covergroup": "functional",
       "functional": "functional",
   }

**逐段解释**：

* 第 L71-L73 行：`overall`、`total`、`score` 都归一为 `overall`。
* 第 L74-L77 行：`cond`、`condition`、`conditions` 保留在 alias 表中，目的是让
  旧 dashboard 或单元测试文本能被解析；它不是当前 sign-off coverage 维度。
* 第 L82-L87 行：`group` 和 `covergroup` 归一为 `functional`，对应 URG dashboard
  中显示的 ``GROUP`` 列。
* 第 L74-L81 行：line、condition、FSM、toggle 的常见写法归一为
  `line`、`cond`、`fsm`、`toggle`。
* 第 L82-L87 行：branch、assert 和 covergroup/functional 也进入统一
  key 空间；`group` 和 `covergroup` 被视为 `functional`。

**接口关系**：

* **被调用**：`_parse_urg_dashboard_header()` 和 `parse_coverage_text()`。
* **调用**：无下层函数。
* **共享状态**：coverage gate 使用这些规范化后的 key 与阈值比较。

§4  stage 解析和 precheck
--------------------------------------------------------------------------------

§4.1  `_split_csv()` / `_load_yaml()` - 输入工具函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：解析逗号分隔的 stage 列表，并用 UTF-8 加载 YAML。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L101-L109`）：

.. code-block:: python

   def _split_csv(value: str) -> List[str]:
       if not value:
           return []
       return [item.strip() for item in value.split(",") if item.strip()]
   
   
   def _load_yaml(path: Path):
       with open(path, "r", encoding="utf-8") as f:
           return yaml.safe_load(f)

**逐段解释**：

* 第 L101-L104 行：空字符串返回空列表；非空字符串按逗号切分，去掉首尾空白，
  并丢弃空项。
* 第 L107-L109 行：YAML 统一按 UTF-8 读取，然后交给 `yaml.safe_load()`。

**接口关系**：

* **被调用**：`resolve_stages()`、`precheck()`、waiver 与 testlist 相关函数。
* **调用**：`yaml.safe_load()`。
* **共享状态**：无全局写入。

§4.2  `resolve_stages()` - profile 和 `--stages` 合并
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：决定本次 sign-off 要评估的 stage 列表，并拒绝未知 stage 名。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L112-L120`）：

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

**逐段解释**：

* 第 L113 行：如果用户传了 `--stages`，使用逗号列表；否则使用
  `PROFILE_STAGES[profile]`。
* 第 L114-L116 行：合法 stage 固定为 9 个字符串。
* 第 L117-L119 行：任意未知 stage 触发 `ValueError`，错误消息列出未知项。
* 第 L120 行：返回最终 stage 列表。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`_split_csv()`。
* **共享状态**：读取 `PROFILE_STAGES`。

§4.3  `parse_stage_result_args()` - 绑定已有结果目录
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：解析 `--stage-result STAGE=DIR`，把指定 stage 绑定到已有结果目录。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L123-L134`）：

.. code-block:: python

   def parse_stage_result_args(stage_result_args: List[str]) -> Dict[str, Path]:
       results = {}
       for item in stage_result_args or []:
           if "=" not in item:
               raise ValueError("--stage-result must be STAGE=DIR")
           stage, directory = item.split("=", 1)
           stage = stage.strip()
           if stage not in ("smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                            "compliance", "formal", "syn"):
               raise ValueError("Unknown stage in --stage-result: {}".format(stage))
           results[stage] = Path(directory).resolve()
       return results

**逐段解释**：

* 第 L124-L128 行：函数要求每个参数包含 `=`，并只按第一个 `=` 切分。
* 第 L129-L132 行：stage 名称必须属于同一个 9-stage 集合。
* 第 L133 行：目录被解析为绝对路径后写入结果字典。
* 第 L134 行：返回 `stage -> Path` 映射。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`Path.resolve()`。
* **共享状态**：无全局写入。

§4.4  `precheck()` - 环境和输入文件预检
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：在运行 gate 前检查 repo 根、filelist、simulator 或 `build/simv`、
RISC-V 工具链、riscv-dv、cosim DPI 和默认 `NUM_THREADS`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L152-L180`）：

.. code-block:: python

   def precheck(stages: List[str], simulator: str) -> Dict:
       checks = []
   
       def add(name: str, passed: bool, detail: str):
           checks.append({"name": name, "passed": passed, "detail": detail})
   
       add("eh2_root", EH2_ROOT.exists(), str(EH2_ROOT))
       add("rtl_filelist", (DV_DIR / "eh2_rtl.f").exists(), str(DV_DIR / "eh2_rtl.f"))
       add("tb_filelist", (DV_DIR / "eh2_tb.f").exists(), str(DV_DIR / "eh2_tb.f"))
   
       sim_tool = {"vcs": "vcs", "xlm": "xrun", "questa": "vsim"}[simulator]
       simv_exists = (EH2_ROOT / "build" / "simv").exists()
       add("simulator_or_simv", simv_exists or tool_exists(sim_tool),
           "found build/simv" if simv_exists else sim_tool)
   
       if any(stage in stages for stage in ("directed", "cosim", "riscvdv")):
           gcc_prefix = resolve_gcc_prefix()
           add("riscv_gcc", tool_exists(gcc_prefix + "-gcc"), gcc_prefix + "-gcc")
           add("riscv_objcopy", tool_exists(gcc_prefix + "-objcopy"),
               gcc_prefix + "-objcopy")
   
       if "riscvdv" in stages:
           riscv_dv_run = EH2_ROOT / "vendor" / "google_riscv-dv" / "run.py"
           add("riscv_dv", riscv_dv_run.exists(), str(riscv_dv_run))
   
       if "cosim" in stages:
           libcosim = EH2_ROOT / "build" / "libcosim.so"
           add("spike_cosim_dpi", libcosim.exists(),

**逐段解释**：

* 第 L152-L156 行：`checks` 是局部列表，内部 `add()` 统一写入
  `{name, passed, detail}`。
* 第 L158-L160 行：固定检查 repo 根、`eh2_rtl.f` 和 `eh2_tb.f`。
* 第 L162-L165 行：simulator 名映射为真实工具命令；只要已有 `build/simv`
  或对应工具存在就通过 `simulator_or_simv`。
* 第 L167-L171 行：包含 `directed`、`cosim` 或 `riscvdv` 时检查
  `riscv32-unknown-elf-gcc` 和 `riscv32-unknown-elf-objcopy`。
* 第 L173-L175 行：包含 `riscvdv` 时检查 vendor 下的 riscv-dv `run.py`。
* 第 L177-L180 行：包含 `cosim` 时检查 `build/libcosim.so`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L180-L198`）：

.. code-block:: python

               "{} (run `make cosim` if missing)".format(libcosim))
   
       cfg_path = EH2_ROOT / "eh2_configs.yaml"
       if cfg_path.exists():
           try:
               cfg = _load_yaml(cfg_path) or {}
               default_threads = cfg.get("default", {}).get(
                   "parameters", {}).get("NUM_THREADS")
               add("default_single_thread", default_threads == 1,
                   "default NUM_THREADS={}".format(default_threads))
           except Exception as err:
               add("eh2_config_parse", False, "{}: {}".format(cfg_path, err))
       else:
           add("eh2_config", False, str(cfg_path))
   
       return {
           "passed": all(check["passed"] for check in checks),
           "checks": checks,
       }

**逐段解释**：

* 第 L182-L189 行：如果 `eh2_configs.yaml` 存在，读取
  `default.parameters.NUM_THREADS`，要求默认配置为单线程。
* 第 L190-L193 行：YAML 解析失败或配置文件缺失都会生成失败 check。
* 第 L195-L198 行：返回整体 `passed` 和逐项 `checks`。整体值是所有
  `check["passed"]` 的逻辑与。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`resolve_gcc_prefix()`、`tool_exists()`、`_load_yaml()`。
* **共享状态**：读取 `EH2_ROOT`、`DV_DIR`、`eh2_configs.yaml`。

§5  stage 命令构造
--------------------------------------------------------------------------------

§5.1  `build_stage_cmd()` - 通用 `run_regress.py` 命令头
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：为 simulation 类 stage 生成 `run_regress.py` 命令，并把全局
parallel、coverage、waves、warning-clean 开关转成 CLI 参数。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L201-L215`）：

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

**逐段解释**：

* 第 L202-L206 行：基础命令固定使用当前 Python 解释器执行
  `run_regress.py`，并设置 simulator、seed 和 stage 输出目录。
* 第 L208-L209 行：只有 `parallel > 1` 才添加 `--parallel`。
* 第 L210-L213 行：coverage 和 waves 分别追加 `--coverage`、`--waves`。
* 第 L214-L215 行：默认 warning-clean；只有用户显式 `--allow-warnings`
  时才不追加 `--fail-on-warnings`。

**接口关系**：

* **被调用**：`main()` 生成 `planned` 列表。
* **调用**：无下层函数。
* **共享状态**：读取 `SCRIPT_DIR` 和 CLI 参数对象。

§5.2  `build_stage_cmd()` - 9 个 stage 的分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把 stage 名映射为 smoke 单测、testlist regression 或专用 make/
Python 命令。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L217-L248`）：

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
       elif stage == "compliance":
           runner = EH2_ROOT / "dv" / "uvm" / "riscv_compliance" / "scripts" / "run_compliance.py"
           simv = EH2_ROOT / "build" / "simv"
           return [
               sys.executable, str(runner),
               "--isa", "all",
               "--simv", str(simv),
               "--output", str(stage_out),
           ]
       elif stage == "formal":
           return ["make", "-C", str(EH2_ROOT), "formal"]
       elif stage == "syn":
           return ["make", "-C", str(EH2_ROOT), "syn"]
       else:
           cmd.extend(["--testlist", str(STAGE_TESTLIST[stage])])
           if args.iterations:
               cmd.extend(["--iterations", str(args.iterations)])

**逐段解释**：

* 第 L217-L223 行：`smoke` 直接跑 `tests/asm/smoke.hex`，RTL test 为
  `core_eh2_base_test`，并设置 `+disable_cosim=1`。
* 第 L224-L225 行：`lint` 返回顶层 `make -C <root> lint`。
* 第 L226-L229 行：`csr_unit` 进入 `dv/uvm/cs_registers_eh2` 执行
  `compliance`，同时传 `SIGNOFF_OUT=<stage_out>`。
* 第 L230-L238 行：`compliance` 运行 riscv-compliance 的
  `run_compliance.py --isa all --simv build/simv --output <stage_out>`。
* 第 L239-L242 行：`formal` 和 `syn` 分别返回顶层 `make formal` 与
  `make syn`。
* 第 L243-L246 行：其余 stage 使用 `STAGE_TESTLIST[stage]`，并在
  `args.iterations` 非零时覆盖迭代数。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`run_regress.py`、Make target、riscv-compliance runner。
* **共享状态**：`EH2_ROOT`、`STAGE_TESTLIST`、stage 输出目录。

§6  stage 执行和通用结果收集
--------------------------------------------------------------------------------

§6.1  `run_command()` - 执行命令并写 stage log
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：创建 log 目录，记录命令行，设置 `EH2_SIGNOFF_MODE=1`，运行
stage 命令并处理 timeout。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L251-L271`）：

.. code-block:: python

   def run_command(cmd: List[str], log_path: Path, timeout_s: int) -> int:
       log_path.parent.mkdir(parents=True, exist_ok=True)
       # Tell run_regress.py we're in sign-off mode so it can honor
       # `skip_in_signoff: true` testlist entries (broken-but-tracked tests).
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
               return proc.returncode
           except subprocess.TimeoutExpired:
               log_fd.write(("\nERROR: signoff stage timed out after {}s\n".
                             format(timeout_s)).encode("utf-8"))
               return 124

**逐段解释**：

* 第 L252 行：先创建 log 父目录，避免 `open()` 因目录不存在失败。
* 第 L253-L256 行：复制当前环境并设置 `EH2_SIGNOFF_MODE=1`。注释说明
  `run_regress.py` 会据此处理 `skip_in_signoff: true` 条目。
* 第 L257-L258 行：以二进制方式打开 log，并把实际命令以 `+ ...` 形式写入。
* 第 L260-L267 行：`subprocess.run()` 把 stdout/stderr 都写入同一个 log，
  超时时间来自 `timeout_s`。
* 第 L268-L271 行：timeout 时向 log 追加错误行并返回 124。

**接口关系**：

* **被调用**：`main()` 的 stage 执行循环。
* **调用**：`subprocess.run()` 和 `_cmd_str()`。
* **共享状态**：进程环境变量 `EH2_SIGNOFF_MODE`。

§6.2  `summary_from_report_json()` - JSON 到 `RegressionSummary`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把已有 `report.json` 转成 regression 框架使用的
`RegressionSummary` 和 `TestRunResult` 对象。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L274-L300`）：

.. code-block:: python

   def summary_from_report_json(report_path: Path) -> RegressionSummary:
       data = json.loads(report_path.read_text(encoding="utf-8"))
       summary = RegressionSummary()
       summary.total_time_sec = float(data.get("total_time_sec", 0.0) or 0.0)
       for item in data.get("tests", []):
           trr = TestRunResult()
           trr.test_name = item.get("name", "")
           trr.seed = int(item.get("seed", 0) or 0)
           trr.test_type = item.get("type", "")
           trr.passed = bool(item.get("passed", False))
           trr.failure_mode = item.get("failure_mode", "")
           trr.sim_log_path = item.get("sim_log", "")
           trr.uvm_log_path = item.get("uvm_log", "")
           trr.trace_path = item.get("trace", "")
           trr.assembly_path = item.get("assembly", "")
           trr.binary_path = item.get("binary", "")
           trr.coverage_path = item.get("coverage", "")
           trr.uvm_errors = int(item.get("uvm_errors", 0) or 0)
           trr.uvm_warnings = int(item.get("uvm_warnings", 0) or 0)
           trr.num_instructions = int(item.get("instructions", 0) or 0)
           trr.num_cycles = int(item.get("cycles", 0) or 0)
           trr.ipc = float(item.get("ipc", 0.0) or 0.0)
           trr.gen_time_sec = float(item.get("gen_time_sec", 0.0) or 0.0)
           trr.compile_time_sec = float(item.get("compile_time_sec", 0.0) or 0.0)
           trr.sim_time_sec = float(item.get("sim_time_sec", 0.0) or 0.0)
           summary.add_result(trr)
       return summary

**逐段解释**：

* 第 L275-L277 行：读取 JSON 并初始化 `RegressionSummary`，保留总耗时。
* 第 L278-L299 行：每个 `tests` 条目被映射到一个 `TestRunResult`，包括
  名称、seed、类型、pass/fail、日志路径、trace、二进制、coverage、
  UVM error/warning、指令数、cycle 数、IPC 和各阶段耗时。
* 第 L300 行：返回填充完成的 `summary`。

**接口关系**：

* **被调用**：`load_stage_summary()`。
* **调用**：`json.loads()`、`RegressionSummary.add_result()`。
* **共享状态**：读取已有 `report.json`。

§6.3  `load_stage_summary()` - 优先读取 `report.json`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：加载 stage 结果，优先使用 `report.json`，否则回退到
`collect_results()` 扫描结果目录。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L330-L341`）：

.. code-block:: python

   def load_stage_summary(results_dir: Path) -> Tuple[RegressionSummary, bool]:
       report_json = results_dir / "report.json"
       if report_json.exists():
           summary = summary_from_report_json(report_json)
           refresh_failure_classification(summary)
           recompute_summary_counts(summary)
           return summary, True
   
       summary = collect_results(str(results_dir))
       refresh_failure_classification(summary)
       recompute_summary_counts(summary)
       return summary, False

**逐段解释**：

* 第 L331-L336 行：如果 stage 目录已有 `report.json`，先转为
  `RegressionSummary`，再用当前 `check_logs.py` 规则重刷 failure
  classification，最后返回 `from_report_json=True`。
* 第 L338-L341 行：没有 `report.json` 时调用 `collect_results()` 扫描结果目录，
  同样刷新 failure classification 和统计计数。

**接口关系**：

* **被调用**：`collect_stage()`。
* **调用**：`summary_from_report_json()`、`refresh_failure_classification()`、
  `recompute_summary_counts()`、`collect_results()`。
* **共享状态**：stage 结果目录。

§6.4  `collect_stage()` - 通用 stage 摘要对象
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把 regression summary 转成 sign-off stage result 字典，并写出
per-stage report。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L344-L367`）：

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
           "total": summary.total_tests,
           "passed": summary.passed,
           "failed": summary.failed,
           "pass_rate": 100.0 * summary.passed / max(1, summary.total_tests),
           "warnings": warning_count,
           "status": "PASS",
           "blockers": [],
           "waivers": [],
           "source": "report.json" if from_report_json else "result.pkl",
           "tests": [],
       }

**逐段解释**：

* 第 L347-L348 行：加载 summary 后调用 `write_reports()` 生成 stage 级报告。
* 第 L350-L361 行：统计 UVM warning，并生成包含目录、命令、退出码、
  total/passed/failed/pass_rate/warnings 的 result 字典。
* 第 L362-L367 行：默认状态先设为 `PASS`，blocker 和 waiver 列表为空，
  `source` 记录结果来自 `report.json` 还是 `result.pkl`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L369-L415`）：

.. code-block:: python

       for trr in summary.results:
           result["tests"].append({
               "name": trr.test_name,
               "seed": trr.seed,
               "passed": trr.passed,
               "failure_mode": trr.failure_mode,
               "warnings": trr.uvm_warnings,
               "sim_log": trr.sim_log_path,
           })
   
       if exit_code not in (None, 0):
           result["blockers"].append("stage command exit code {}".format(exit_code))
       if summary.total_tests == 0:
           result["blockers"].append("no test results collected")
       if summary.failed > 0:
           result["blockers"].append("{} test(s) failed".format(summary.failed))
       if fail_on_warnings and warning_count > 0:
           result["blockers"].append("{} warning(s) in warning-clean run".format(
               warning_count))

**逐段解释**：

* 第 L369-L377 行：每个 `TestRunResult` 被压缩成 HTML/JSON 报告需要的
  test 条目。
* 第 L379-L387 行：非零退出码、零测试、失败测试、warning-clean 模式下的
  warning 都会进入 `blockers`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L389-L415`）：

.. code-block:: python

       min_passed = STAGE_MIN_PASSED.get(stage)
       threshold_met = (
           min_passed is not None and
           summary.total_tests > 0 and
           summary.passed >= min_passed
       )
       if threshold_met:
           threshold_notes = []
           if exit_code not in (None, 0):
               threshold_notes.append("stage command exit code {}".format(exit_code))
           if summary.failed > 0:
               threshold_notes.append("{} test(s) failed".format(summary.failed))
           if threshold_notes:
               result["waivers"].append(
                   "stage threshold met: {}/{} passed, minimum {}; waived: {}".format(
                       summary.passed, summary.total_tests, min_passed,
                       "; ".join(threshold_notes)))
               result["blockers"] = [
                   blocker for blocker in result["blockers"]
                   if not (
                       blocker.startswith("stage command exit code") or
                       blocker.endswith("test(s) failed"))
               ]
   
       if result["blockers"]:
           result["status"] = "FAIL"
       return result

**逐段解释**：

* 第 L389-L394 行：对存在 `STAGE_MIN_PASSED` 的 stage，计算是否达到最小
  passed 数。
* 第 L395-L405 行：如果达到最小 passed 数，但有非零退出码或失败测试，
  这些问题会被记录为 stage waiver 文本。
* 第 L406-L411 行：被最小通过数覆盖的退出码和失败测试 blocker 会从
  `blockers` 列表移除。
* 第 L413-L415 行：仍有 blocker 时 stage 状态变为 `FAIL`，否则保持 `PASS`。

**接口关系**：

* **被调用**：`main()` 对 `smoke`、`directed`、`cosim`、`riscvdv`、
  `csr_unit`、`compliance` 的默认收集路径。
* **调用**：`load_stage_summary()`、`write_reports()`、`_cmd_str()`。
* **共享状态**：`STAGE_MIN_PASSED`。

§7  专用 stage 收集器
--------------------------------------------------------------------------------

§7.1  `collect_lint_stage()` - lint 日志 gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：从 :file:`lint/build` 读取 Verible 和 Verilator 输出，把 lint
错误数转换为 sign-off stage result。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L426-L461`）：

.. code-block:: python

   def collect_lint_stage(stage: str, results_dir: Path, report_dir: Path) -> Dict:
       """Collect lint results from lint/build/*.log and *.txt files.
   
       Parses Verible errors and Verilator %Error lines.  Pass condition:
       zero errors from all linters *and* lint has actually been run.
       """
       lint_build = EH2_ROOT / "lint" / "build"
       total_errors = 0
       total_warnings = 0
       details = []
   
       if not lint_build.is_dir():
           tests = [{
               "name": "lint",
               "seed": 0,
               "passed": False,
               "failure_mode": "no_results",
               "warnings": 0,
               "sim_log": "",
           }]
           return {
               "stage": stage,
               "results_dir": str(lint_build),
               "report_dir": str(report_dir),
               "command": "",
               "exit_code": 0,
               "total": 0,
               "passed": 0,
               "failed": 0,
               "pass_rate": 0.0,

**逐段解释**：

* 第 L426-L431 行：docstring 明确 lint gate 需要所有 linter 零 error，
  且 lint 必须实际运行过。
* 第 L432-L435 行：结果目录固定为 `lint/build`，局部统计 error、warning
  和详情。
* 第 L437-L461 行：如果 `lint/build` 不存在，构造一个 `no_results`
  test 条目，并返回 `FAIL` 状态。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L463-L513`）：

.. code-block:: python

       # Verible error log
       verible_err = lint_build / "verible_errors.txt"
       if verible_err.exists():
           lines = verible_err.read_text(encoding="utf-8", errors="replace").splitlines()
           verible_errors = len([l for l in lines if l.strip()])
           total_errors += verible_errors
           details.append("verible_errors={}".format(verible_errors))
   
       # Verilator log
       verilator_log = lint_build / "verilator.log"
       if verilator_log.exists():
           text = verilator_log.read_text(encoding="utf-8", errors="replace")
           verilator_errors = len(re.findall(r"%Error", text))
           verilator_warns = len(re.findall(r"%Warning", text))
           total_errors += verilator_errors
           total_warnings += verilator_warns
           details.append("verilator_errors={}".format(verilator_errors))

**逐段解释**：

* 第 L463-L469 行：Verible 错误来自 `verible_errors.txt` 的非空行数。
* 第 L471-L479 行：Verilator 错误和 warning 分别通过 `%Error` 与
  `%Warning` 正则计数。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L481-L513`）：

.. code-block:: python

       # Also check for any other error files
       for f in lint_build.glob("*errors*"):
           if f != verible_err:
               text = f.read_text(encoding="utf-8", errors="replace")
               extra = len([l for l in text.splitlines() if l.strip()])
               total_errors += extra
               details.append("{}={}".format(f.name, extra))
   
       tests = [{
           "name": "lint",
           "seed": 0,
           "passed": total_errors == 0,
           "failure_mode": "lint_errors" if total_errors > 0 else "NONE",
           "warnings": total_warnings,
           "sim_log": str(lint_build),
       }]

**逐段解释**：

* 第 L481-L487 行：除 `verible_errors.txt` 外，任何文件名包含 `errors`
  的文件也按非空行计入 error。
* 第 L489-L496 行：lint 被归约成一个 test 条目，`total_errors == 0`
  才 pass。
* 第 L497-L513 行：返回的 stage result total 固定为 1，status 由
  `total_errors` 是否为 0 决定，blocker 文本包含 error 汇总详情。

**接口关系**：

* **被调用**：`main()` 在 `stage == "lint"` 时调用。
* **调用**：`Path.glob()`、`re.findall()`。
* **共享状态**：:file:`lint/build/verible_errors.txt` 和
  :file:`lint/build/verilator.log`。

§7.2  `collect_formal_stage()` - IFV assertion summary
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：从 :file:`dv/formal/build` 中最新的 IFV log 解析
`Assertion Summary`，生成 formal stage result。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L516-L552`）：

.. code-block:: python

   def collect_formal_stage(stage: str, results_dir: Path, report_dir: Path) -> Dict:
       """Collect formal verification results from the latest ifv_prove_*.log.
   
       Parses the Assertion Summary block (Total / Pass / Fail / Not_Run).
       Pass condition: Fail == 0 and Total > 0.
       """
       prove_candidates = []
       formal_build = EH2_ROOT / "dv" / "formal" / "build"
       for pattern in ("ifv_prove_*.log", "ifv_run.log", "ifv_final.log",
                       "ifv_cex_run.log"):
           prove_candidates.extend(Path(p) for p in glob.glob(str(formal_build / pattern)))
       prove_log = max(prove_candidates, key=lambda p: p.stat().st_mtime) \
           if prove_candidates else None
       total = passed = failed = not_run = 0
       details = []
       log_path = ""
   
       if prove_log is not None:
           log_path = str(prove_log)
           text = prove_log.read_text(encoding="utf-8", errors="replace")
           # Parse the Assertion Summary block
           summary_blocks = re.findall(
               r"Assertion Summary:\s*\n((?:\s*[A-Za-z_]+\s*:\s*[0-9]+\s*\n)+)",
               text)

**逐段解释**：

* 第 L516-L521 行：docstring 定义 pass 条件为 `Fail == 0` 且 `Total > 0`。
* 第 L522-L528 行：候选 log 包括 `ifv_prove_*.log`、`ifv_run.log`、
  `ifv_final.log` 和 `ifv_cex_run.log`，选择修改时间最新者。
* 第 L529-L535 行：初始化计数；找到 log 后读取文本。
* 第 L537-L539 行：正则提取最后一个 `Assertion Summary` 样式的键值块。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L540-L583`）：

.. code-block:: python

           if summary_blocks:
               values = {}
               for line in summary_blocks[-1].splitlines():
                   m = re.match(r"\s*([A-Za-z_]+)\s*:\s*([0-9]+)", line)
                   if m:
                       values[m.group(1)] = int(m.group(2))
               total = values.get("Total", 0)
               passed = values.get("Pass", 0)
               failed = values.get("Fail", 0)
               not_run = values.get("Not_Run", 0)
               explored = values.get("Explored", 0)
               details.append("Total={} Pass={} Fail={} Explored={} Not_Run={}".format(
                   total, passed, failed, explored, not_run))

**逐段解释**：

* 第 L540-L546 行：逐行解析 summary block 中的 `Key: Value`。
* 第 L547-L550 行：提取 `Total`、`Pass`、`Fail`、`Not_Run`。
* 第 L551-L552 行：`Explored` 只进入 detail 字符串，不作为 pass 条件。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L554-L583`）：

.. code-block:: python

       blocker_msg = []
       if total == 0:
           blocker_msg.append("no formal assertion results found")
       if failed > 0:
           blocker_msg.append("{} formal assertion(s) FAIL".format(failed))
   
       tests = [{
           "name": "formal_prove",
           "seed": 0,
           "passed": total > 0 and failed == 0,
           "failure_mode": "formal_fail" if failed > 0 else ("no_results" if total == 0 else "NONE"),
           "warnings": 0,
           "sim_log": log_path,
       }]

**逐段解释**：

* 第 L554-L558 行：`total == 0` 或 `failed > 0` 都会生成 blocker。
* 第 L560-L567 行：formal 被归约成 `formal_prove` 单个 test 条目。
* 第 L568-L583 行：stage result 的 total/passed/failed 来自 IFV summary；
  `total > 0 and failed == 0` 时 status 为 `PASS`。

**接口关系**：

* **被调用**：`main()` 在 `stage == "formal"` 时调用。
* **调用**：`glob.glob()`、`re.findall()`、`re.match()`。
* **共享状态**：:file:`dv/formal/build` 下 IFV log。formal 策略见
  :ref:`adr-0012` 和 :ref:`adr-0014`。

§7.3  `parse_lec_blocklevel_summary()` - 解析 block-level LEC 汇总
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：读取 `syn/build/lec_summary.txt` 形式的 Markdown 表格，提取每个
module 和 TOTAL 的 passing/failing/unverified/status。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L595-L621`）：

.. code-block:: python

   def parse_lec_blocklevel_summary(path: str) -> Dict:
       """Parse syn/build/lec_summary.txt into per-module and TOTAL data."""
       modules = {}
       total = {"passing": 0, "failing": 0, "unverified": 0, "status": "UNKNOWN"}
       with open(path, "r", encoding="utf-8", errors="replace") as f:
           for line in f:
               if not line.startswith("|"):
                   continue
               cols = [col.strip() for col in line.split("|")[1:-1]]
               if len(cols) < 5 or cols[0] in ("Module", "---"):
                   continue
               try:
                   entry = {
                       "passing": int(cols[1]),
                       "failing": int(cols[2]),
                       "unverified": int(cols[3]),
                       "status": cols[4],
                   }
               except ValueError:
                   continue
               if len(cols) >= 6:
                   entry["note"] = cols[5]
               if cols[0] == "TOTAL":
                   total = entry
               else:
                   modules[cols[0]] = entry
       return {"modules": modules, "total": total}

**逐段解释**：

* 第 L597-L599 行：初始化 `modules` 和默认 `total`。
* 第 L600-L605 行：只处理以 `|` 开头的表格行，跳过表头和分隔线。
* 第 L606-L614 行：把 passing、failing、unverified 转为整数；转换失败的行
  被跳过。
* 第 L615-L620 行：第 6 列如果存在则作为 note；`TOTAL` 行写入 `total`，
  其他行写入 `modules`。
* 第 L621 行：返回 `{modules, total}`。

**接口关系**：

* **被调用**：`collect_syn_stage()` 的 block-level 分支。
* **调用**：文件读取和整数转换。
* **共享状态**：:file:`syn/build/lec_summary.txt`。block-level closure
  路径见 :ref:`adr-0020`。

§7.4  `evaluate_lec_blocklevel()` - block-level LEC 判定
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：根据 TOTAL 行的 failing 和 unverified 数量返回 `PASS`、
`WAIVE_TOOL_LIMITED` 或 `FAIL`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L624-L653`）：

.. code-block:: python

   def evaluate_lec_blocklevel(summary: Dict,
                               unverified_threshold: int = 5,
                               waive_unverified_threshold: int = 50) -> Tuple[str, str]:
       total = summary["total"]
       if total["failing"] > 0:
           return ("FAIL", "block-level LEC has {} failing compare points".format(
               total["failing"]))
       if total["unverified"] <= unverified_threshold:
           return (
               "PASS",
               "block-level LEC: {} passing, {} unverified within tolerance".format(
                   total["passing"], total["unverified"]),
           )
       bad_modules = [
           name for name, module in summary["modules"].items()
           if module.get("unverified", 0) > 0
       ]
       if total["unverified"] <= waive_unverified_threshold:
           return (
               "WAIVE_TOOL_LIMITED",
               "block-level LEC: {} passing, {} unverified concentrated in {} "
               "(R3-C tool limitation)".format(

**逐段解释**：

* 第 L624-L627 行：默认 unverified 容忍阈值为 5，waive 阈值为 50。
* 第 L628-L630 行：只要 failing compare point 大于 0，立即 `FAIL`。
* 第 L631-L636 行：unverified 不超过 5 时返回 `PASS`。
* 第 L637-L648 行：unverified 不超过 50 时返回 `WAIVE_TOOL_LIMITED`，并把
  有 unverified 的模块名放入 note。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L644-L653`）：

.. code-block:: python

                   total["passing"], total["unverified"],
                   ",".join(bad_modules) if bad_modules else "unknown"),
           )
       return (
           "WAIVE_TOOL_LIMITED",
           "block-level LEC: {} unverified > waive threshold {}, partial closure".format(
               total["unverified"], waive_unverified_threshold),
       )

**逐段解释**：

* 第 L644-L648 行：返回的 note 包含 passing 数、unverified 数和模块列表。
* 第 L649-L653 行：超过 waive 阈值时仍返回 `WAIVE_TOOL_LIMITED`，note
  明确记录 partial closure。2026-05-19 demo 的 LEC 结果是 31635/31635 PASS、
  unverified 0，因此不依赖该 partial 分支。

**接口关系**：

* **被调用**：`collect_syn_stage()` 的 block-level 分支。
* **调用**：无下层函数。
* **共享状态**：`parse_lec_blocklevel_summary()` 的输出。

§7.5  `collect_syn_stage()` - syn/LEC stage 收集
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：当 `--lec-blocklevel` 打开时读取 `lec_summary.txt`；否则读取最新
`lec_*final.log` 并解析 Formality compare point。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L656-L710`）：

.. code-block:: python

   def collect_syn_stage(stage: str, results_dir: Path, report_dir: Path,
                         lec_known_limited: bool = False,
                         lec_blocklevel: bool = False,
                         lec_summary_path: str = "") -> Dict:
       """Collect synthesis / LEC results from the latest lec_*final.log.
   
       Parses Formality status report for Verification SUCCEEDED / FAILED
       and the compare-point summary.  Pass condition: SUCCEEDED and Failing==0.
       """
       lec_log = _latest_matching_log(str(
           EH2_ROOT / "syn" / "build" / "lec_*final.log"))
       status = "UNKNOWN"
       passing_pts = failing_pts = aborted_pts = unverified_pts = 0
       details = []
       log_path = ""
   
       if lec_blocklevel:
           summary_path = Path(lec_summary_path) if lec_summary_path else \
               EH2_ROOT / "syn" / "build" / "lec_summary.txt"

**逐段解释**：

* 第 L656-L664 行：函数参数把 LEC tool limitation waiver、block-level 模式和
  summary 路径都显式传入；docstring 给出普通 LEC pass 条件。
* 第 L665-L670 行：普通路径先定位最新 `syn/build/lec_*final.log`，并初始化
  compare point 计数。
* 第 L672-L674 行：block-level 模式优先使用 `lec_summary_path`，否则使用
  `syn/build/lec_summary.txt`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L675-L710`）：

.. code-block:: python

           if not summary_path.is_absolute():
               summary_path = EH2_ROOT / summary_path
           if summary_path.exists():
               summary = parse_lec_blocklevel_summary(str(summary_path))
               block_status, note = evaluate_lec_blocklevel(summary)
               total = summary["total"]
               total_points = (total["passing"] + total["failing"] +
                               total["unverified"])
               tests = [{
                   "name": "lec_blocklevel",
                   "seed": 0,
                   "passed": block_status in ("PASS", "WAIVE_TOOL_LIMITED"),
                   "failure_mode": "NONE" if block_status == "PASS" else block_status,
                   "warnings": 0,
                   "sim_log": str(summary_path),
               }]

**逐段解释**：

* 第 L675-L676 行：相对路径会被解释为 repo 根下路径。
* 第 L677-L680 行：存在 summary 文件时解析表格并计算 block-level 状态。
* 第 L681-L682 行：TOTAL 的 passing、failing、unverified 相加为 total。
* 第 L683-L690 行：block-level LEC 被归约成 `lec_blocklevel` 单个 test；
  `PASS` 和 `WAIVE_TOOL_LIMITED` 都算 test passed。
* 第 L691-L710 行：返回 stage result，包含 `blocklevel=True`、`summary_path`
  和逐模块 `modules`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L712-L773`）：

.. code-block:: python

       if lec_log is not None:
           log_path = str(lec_log)
           text = lec_log.read_text(encoding="utf-8", errors="replace")
           if re.search(r"Verification\s+SUCCEEDED", text):
               status = "SUCCEEDED"
           elif re.search(r"Verification\s+FAILED", text):
               status = "FAILED"
   
           m = re.search(r"(\d+)\s+Passing compare points", text)
           if m:
               passing_pts = int(m.group(1))
           m = re.search(r"(\d+)\s+Failing compare points", text)
           if m:
               failing_pts = int(m.group(1))

**逐段解释**：

* 第 L712-L718 行：普通路径读取最新 final log，并用正则识别
  `Verification SUCCEEDED` 或 `Verification FAILED`。
* 第 L720-L725 行：解析 passing 和 failing compare point 数。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L726-L773`）：

.. code-block:: python

           m = re.search(r"(\d+)\s+Aborted compare points", text)
           if m:
               aborted_pts = int(m.group(1))
           m = re.search(r"(\d+)\s+Unverified compare points", text)
           if m:
               unverified_pts = int(m.group(1))
           details.append("Passing={} Failing={} Aborted={} Unverified={}".format(
               passing_pts, failing_pts, aborted_pts, unverified_pts))
   
       syn_passed = status == "SUCCEEDED" and failing_pts == 0
       true_rtl_bug = has_true_rtl_bug_in_buckets()
       blocker_msg = []
       if status == "FAILED":
           blocker_msg.append("LEC Verification FAILED")
       if unverified_pts > 0:
           blocker_msg.append("{} Unverified compare points".format(unverified_pts))

**逐段解释**：

* 第 L726-L733 行：继续解析 aborted 和 unverified compare point，并记录 detail。
* 第 L735-L741 行：普通 LEC 通过要求 status 为 `SUCCEEDED` 且
  `failing_pts == 0`；失败状态和 unverified 数会加入 blocker。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L742-L773`）：

.. code-block:: python

       if lec_known_limited and not syn_passed and not true_rtl_bug:
           blocker_msg = [
               "WAIVE_TOOL_LIMITED: ADR-0019 tool limitation; True RTL bug count is 0"
           ]
   
       tests = [{
           "name": "lec",
           "seed": 0,
           "passed": syn_passed or (lec_known_limited and not true_rtl_bug),
           "failure_mode": "NONE" if syn_passed else (
               "WAIVE_TOOL_LIMITED" if lec_known_limited and not true_rtl_bug else "lec_fail"),
           "warnings": 0,
           "sim_log": log_path,
       }]

**逐段解释**：

* 第 L742-L745 行：打开 `--lec-known-limited` 且没有 true RTL bug bucket 时，
  blocker 文本被替换为 ADR-0019 tool limitation。ADR 编号已存在于
  :ref:`adr-0019`。
* 第 L747-L755 行：普通 LEC 被归约成 `lec` 单个 test，waived tool limitation
  也会让 test passed。
* 第 L756-L773 行：stage status 是 `PASS`、`WAIVE_TOOL_LIMITED` 或 `FAIL`；
  total 是四类 compare point 之和。

**接口关系**：

* **被调用**：`main()` 在 `stage == "syn"` 时调用。
* **调用**：`_latest_matching_log()`、`parse_lec_blocklevel_summary()`、
  `evaluate_lec_blocklevel()`、`has_true_rtl_bug_in_buckets()`。
* **共享状态**：:file:`syn/build/lec_summary.txt`、
  :file:`syn/build/lec_*final.log`、:file:`syn/build/failing_buckets.md`。

§7.6  `evaluate_compliance_per_suite()` - compliance 子套件 gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：对 riscv-compliance 的 per-ISA 结果施加 suite-level pass-rate
阈值，并把异常作为 blocker 返回。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L776-L823`）：

.. code-block:: python

   def evaluate_compliance_per_suite(results_dir: Path) -> List[str]:
       """Per-suite compliance gate (rv32i >=95%, rv32im/imc/Zicsr =100%).
   
       Reads per-ISA report.json files from the compliance results directory
       and enforces per-suite pass-rate thresholds.  Returns list of blocker
       strings (empty = all suites pass).
       """
       blockers = []
       suite_gates = {
           "rv32i":      95.0,
           "rv32im":     100.0,
           "rv32imc":    100.0,
           "rv32Zicsr":  100.0,
       }
       zifencei_known_fail = 1
   
       for isa, threshold in suite_gates.items():
           report_path = results_dir / isa / "report.json"
           if not report_path.exists():
               # Try aggregated report.json

**逐段解释**：

* 第 L776-L782 行：docstring 说明 per-suite gate 和返回值形态。
* 第 L783-L790 行：`rv32i` 阈值为 95.0，`rv32im`、`rv32imc`、
  `rv32Zicsr` 阈值为 100.0；`rv32Zifencei` 已知失败数为 1。
* 第 L792-L797 行：优先读取 `results_dir/<isa>/report.json`，不存在时回退到
  聚合 `results_dir/report.json`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L798-L842`）：

.. code-block:: python

           if not report_path.exists():
               blockers.append(
                   "compliance {} report.json not found".format(isa))
               continue
   
           try:
               data = json.loads(report_path.read_text(encoding="utf-8"))
           except Exception:
               blockers.append(
                   "compliance {} report.json unparseable".format(isa))
               continue
   
           suite_tests = [t for t in data.get("tests", [])
                          if t.get("type", "").startswith("compliance_" + isa)]
           total = len(suite_tests)
           passed = sum(1 for t in suite_tests if t.get("passed", False))

**逐段解释**：

* 第 L798-L808 行：缺少或无法解析 report JSON 都会生成 blocker。
* 第 L810-L814 行：只统计 `type` 以 `compliance_<isa>` 开头的测试。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L815-L842`）：

.. code-block:: python

           if total == 0:
               continue
   
           rate = 100.0 * passed / total
           if rate < threshold:
               blockers.append(
                   "compliance {} pass rate {:.1f}% below {:.1f}% ({}/{})".format(
                       isa, rate, threshold, passed, total))
   
       # rv32Zifencei: treated as PASS when known_fail covers the failures
       zifencei_dir = results_dir / "rv32Zifencei"
       if zifencei_dir.exists():
           zifencei_report = zifencei_dir / "report.json"
           if zifencei_report.exists():

**逐段解释**：

* 第 L815-L823 行：suite 没有测试时跳过；有测试时按 pass rate 与阈值比较。
* 第 L824-L842 行：`rv32Zifencei` 允许已知失败数覆盖，超过
  `zifencei_known_fail` 才生成 blocker。

**接口关系**：

* **被调用**：`main()` 在 `stage == "compliance"` 后额外调用。
* **调用**：`json.loads()`。
* **共享状态**：compliance stage 输出目录。合规框架见 :ref:`adr-0011`。

§8  coverage 收集和 gate
--------------------------------------------------------------------------------

§8.1  `_parse_urg_dashboard_header()` - URG 表头格式解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：解析 URG dashboard 里 `SCORE LINE COND TOGGLE FSM ASSERT` 这类
表头加数据行的格式。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L845-L893`）：

.. code-block:: python

   def _parse_urg_dashboard_header(text: str) -> Dict[str, float]:
       """Parse URG dashboard.txt header-row + data-row format.
   
       Example::
   
           SCORE  LINE   COND   TOGGLE FSM    ASSERT
            41.59  82.73  40.61  35.57  22.39  26.67
   
       Returns a dict of COVERAGE_METRIC_ALIASES values keyed by canonical metric.
       """
       result = {}
       header_re = re.compile(
           r"\b(SCORE|LINE|COND|TOGGLE|FSM|ASSERT|BRANCH)\b",
           re.IGNORECASE)
       data_re = re.compile(r"[0-9]+\.[0-9]+")

**逐段解释**：

* 第 L845-L854 行：docstring 说明输入格式和返回 key 使用
  `COVERAGE_METRIC_ALIASES` 的规范名。
* 第 L855-L859 行：初始化 result，并编译表头和数值行的正则。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L861-L893`）：

.. code-block:: python

       lines = text.splitlines()
       for i, line in enumerate(lines):
           if not header_re.search(line):
               continue
           # Check if next non-empty line looks like a data row
           if i + 1 >= len(lines):
               continue
           data_line = lines[i + 1].strip()
           if not data_re.search(data_line):
               # Could be a blank line between header and data
               if i + 2 < len(lines):
                   data_line = lines[i + 2].strip()
               if not data_re.search(data_line):
                   continue

**逐段解释**：

* 第 L861-L864 行：逐行找包含 coverage 表头关键字的行。
* 第 L865-L874 行：表头后下一行或隔一行必须包含浮点数，否则继续搜索。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L876-L893`）：

.. code-block:: python

           headers = [h.upper() for h in line.split()]
           values = []
           for token in data_line.split():
               try:
                   values.append(float(token))
               except ValueError:
                   continue
   
           if not values or not headers:
               continue
   
           n = min(len(headers), len(values))
           for hdr, val in zip(headers[:n], values[:n]):
               metric = COVERAGE_METRIC_ALIASES.get(hdr.lower())
               if metric and 0.0 <= val <= 100.0:
                   result[metric] = max(result.get(metric, 0.0), val)
           return result

**逐段解释**：

* 第 L876-L882 行：表头转大写，数据行逐 token 转 float。
* 第 L884-L891 行：按表头和值对齐，用 alias 映射到 canonical metric，
  同一 metric 取最大值。
* 第 L892-L893 行：找到第一组有效表后返回；没有有效表则返回空字典。

**接口关系**：

* **被调用**：`parse_coverage_text()`。
* **调用**：`re.compile()`、`float()`。
* **共享状态**：`COVERAGE_METRIC_ALIASES`。

§8.2  `parse_coverage_text()` - fallback coverage 正则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：优先用 URG header parser；如果失败，再用文本正则解析
`line coverage: 95.05%` 或列式报告。当前主线的 coverage dashboard 由 URG 原生
输出，fallback 正则只服务于脚本兼容性和单元测试。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L896-L923`）：

.. code-block:: python

   def parse_coverage_text(text: str) -> Dict[str, float]:
       metrics = _parse_urg_dashboard_header(text)
       # If URG dashboard parser already found values, trust them and skip
       # the fallback regexes which are known to mis-parse header-row formats.
       if metrics:
           return metrics
       patterns = [
           re.compile(
               r"\b(line|lines|cond|condition|conditions|fsm|toggle|tgl|branch|"
               r"assert|assertion|group|covergroup|functional|overall|total|"
               r"score)\b(?:\s+coverage|\s+score)?\s*[:=]?\s*"
               r"([0-9]+(?:\.[0-9]+)?)\s*%",
               re.IGNORECASE),
           re.compile(
               r"\b(line|cond|fsm|tgl|toggle|branch|assert|score|total)\b"
               r"\s+\S+\s+\S+\s+([0-9]+(?:\.[0-9]+)?)\b",
               re.IGNORECASE),
       ]

**逐段解释**：

* 第 L897-L901 行：如果 URG header parser 已经找到 metrics，直接返回，
  避免 fallback 正则误读 header-row。
* 第 L902-L913 行：fallback 包含两类正则：百分号文本和列式文本。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L914-L923`）：

.. code-block:: python

       for pattern in patterns:
           for match in pattern.finditer(text):
               raw_name = match.group(1).lower()
               metric = COVERAGE_METRIC_ALIASES.get(raw_name)
               if not metric:
                   continue
               value = float(match.group(2))
               if 0.0 <= value <= 100.0:
                   metrics[metric] = max(metrics.get(metric, 0.0), value)
       return metrics

**逐段解释**：

* 第 L914-L918 行：对每个匹配项取 metric 名，并用 alias 表归一化。
* 第 L919-L922 行：只接受 0 到 100 之间的数值；同一 metric 保留最大值。
* 第 L923 行：返回最终 metrics。

**接口关系**：

* **被调用**：`evaluate_coverage()`。
* **调用**：`_parse_urg_dashboard_header()`、`re.Pattern.finditer()`。
* **共享状态**：`COVERAGE_METRIC_ALIASES`。

§8.3  `coverage_candidate_files()` - coverage 文件发现
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：从用户提供路径、输出目录和默认 build coverage 目录中寻找可解析的
coverage 文本报告。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L926-L955`）：

.. code-block:: python

   def coverage_candidate_files(paths: List[Path], output_dir: Path) -> List[Path]:
       candidates = []
       search_roots = list(paths)
       search_roots.extend([
           output_dir / "coverage",
           output_dir / "cov_report",
           EH2_ROOT / "build" / "r2b_cov_report",
       ])
   
       for root in search_roots:
           if not root:
               continue
           root = Path(root)
           if root.is_file():
               candidates.append(root)
               continue
           if not root.is_dir():

**逐段解释**：

* 第 L927-L933 行：搜索根包括 CLI 传入路径、`output_dir/coverage`、
  `output_dir/cov_report` 和 `build/r2b_cov_report`。
* 第 L935-L941 行：如果搜索根本身是文件，直接作为候选。
* 第 L942-L943 行：非文件也非目录的路径会被跳过。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L942-L955`）：

.. code-block:: python

               continue
           for name in TEXT_REPORT_NAMES:
               candidates.extend(Path(p) for p in glob.glob(str(root / "**" / name),
                                                            recursive=True))
   
       seen = set()
       uniq = []
       for path in candidates:
           real = str(path.resolve())
           if real not in seen and path.exists():
               seen.add(real)
               uniq.append(path)
       return uniq

**逐段解释**：

* 第 L944-L946 行：目录下递归寻找 `TEXT_REPORT_NAMES` 中定义的文件名。
* 第 L948-L954 行：按真实路径去重，并确认文件仍存在。
* 第 L955 行：返回去重后的候选文件列表。

**接口关系**：

* **被调用**：`evaluate_coverage()`。
* **调用**：`glob.glob()`。
* **共享状态**：`TEXT_REPORT_NAMES`、`EH2_ROOT`。

§8.4  `auto_merge_stage_coverage()` - stage coverage 自动合并
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：当本次运行开启 coverage 时，扫描各 stage 的 `.vdb`、``coverage`` 目录
和 NC ``cov_work`` 目录，调用 `merge_cov.py` 生成 merged coverage 目录。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L989-L1028`）：

.. code-block:: python

   def auto_merge_stage_coverage(stage_results: List[Dict],
                                  output_dir: Path) -> Path:
      """Merge coverage databases from all stages into a single merged report.

      Scans each stage's results_dir for .vdb directories, and additionally
      includes the centralized output_dir/cov.vdb that VCS produces when
      every stage shares the same -cm_dir. Runs urg merge and generates
      dashboard.txt. Returns the merged output directory path.
      """
      vdb_dirs = []
       for stage in stage_results:
           results_dir = Path(stage.get("results_dir", ""))
           if not results_dir.is_dir():
               continue
           for p in results_dir.rglob("*.vdb"):
               if p.is_dir():
                   vdb_dirs.append(str(p))
           coverage_dir = results_dir / "coverage"
           if coverage_dir.is_dir():
               vdb_dirs.append(str(coverage_dir))

**逐段解释**：

* 第 L989-L997 行：docstring 说明函数扫描 stage 的 coverage DB，并补充 VCS
  shared ``-cm_dir`` 产生的 centralized ``cov.vdb``。
* 第 L998-L1008 行：对每个 stage 的 `results_dir` 查找 `.vdb` 目录和
  `coverage` 子目录。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1010-L1028`）：

.. code-block:: python

      central_vdb = output_dir / "cov.vdb"
      if central_vdb.is_dir():
          vdb_dirs.append(str(central_vdb))

      # NC/imc coverage layout (build_dir/cov_work) — full sign-off support.
      # merge_cov.py auto-detects .vdb (VCS) vs cov_work/*.ucd (NC) and routes
      # to urg / imc accordingly. NC produces dashboard.txt in the same
      # column layout as VCS so the signoff parser stays simulator-agnostic.
      central_cov_work = output_dir / "cov_work"
      if central_cov_work.is_dir():
          vdb_dirs.append(str(central_cov_work))

**逐段解释**：

* 第 L1010-L1012 行：VCS shared coverage 目录位于 ``output_dir/cov.vdb`` 时也加入合并。
* 第 L1014-L1021 行：NC ``cov_work`` 是完整 sign-off coverage 路径的一部分；
  ``merge_cov.py`` 根据 ``.vdb`` 或 ``cov_work/*.ucd`` 自动分流到 URG 或 IMC。
* 第 L1022-L1024 行：NC 合并后仍输出同样列布局的 ``dashboard.txt``，因此后续 parser
  保持 simulator-agnostic。

**接口关系**：

* **被调用**：`main()` 在 `not gate_only`、`not dry_run` 且 `args.coverage`
  为真时调用。
* **调用**：:file:`dv/uvm/core_eh2/scripts/merge_cov.py`。
* **共享状态**：各 stage 结果目录和 `output_dir/cov_merged`。

§8.5  `evaluate_coverage()` - coverage gate 判定
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：解析 coverage 文件，并按 CLI 阈值生成 coverage result。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L996-L1038`）：

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
       metrics = {}
       parsed_files = []

**逐段解释**：

* 第 L997-L1005 行：coverage 是否必需由 `--no-require-coverage` 控制；
  阈值来自 6 个 `--min-*-coverage` 参数。
* 第 L1007-L1010 行：只要 coverage 被要求，或任一阈值大于 0，`required`
  就为真。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1012-L1038`）：

.. code-block:: python

       if required or paths:
           files = coverage_candidate_files(paths, output_dir)
   
           for path in files:
               try:
                   if path.stat().st_size > 5 * 1024 * 1024:
                       continue
                   text = path.read_text(encoding="utf-8", errors="replace")
               except Exception:
                   continue
               parsed = parse_coverage_text(text)
               if parsed:
                   parsed_files.append(str(path))
               for key, value in parsed.items():
                   metrics[key] = max(metrics.get(key, 0.0), value)
   
           if "overall" not in metrics and metrics:
               metrics["overall"] = sum(metrics.values()) / len(metrics)

**逐段解释**：

* 第 L1012-L1014 行：只有 required 或显式传入路径时才搜索候选文件。
* 第 L1015-L1021 行：超过 5 MB 的文件跳过；读取失败也跳过。
* 第 L1022-L1026 行：解析文本后记录成功解析的文件，多个文件同一 metric
  取最大值。
* 第 L1028-L1029 行：如果没有 `overall` 但存在其他 metric，则用这些 metric
  的平均值补出 `overall`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1031-L1060`）：

.. code-block:: python

       result = {
           "required": required,
           "status": "PASS",
           "metrics": metrics,
           "files": parsed_files,
           "thresholds": thresholds,
           "blockers": [],
       }
   
       if required and not metrics:
           result["blockers"].append("coverage report not found or not parseable")

**逐段解释**：

* 第 L1031-L1038 行：coverage result 初始状态为 `PASS`，同时记录 parsed
  metrics、文件和 thresholds。
* 第 L1040-L1041 行：required 但没有任何 metric 时生成 blocker。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1043-L1060`）：

.. code-block:: python

       for metric, threshold in thresholds.items():
           if threshold <= 0.0:
               continue
           value = metrics.get(metric)
           if value is None:
               result["blockers"].append(
                   "{} coverage missing (threshold {:.2f}%)".format(
                       metric, threshold))
           elif value < threshold:
               result["blockers"].append(
                   "{} coverage {:.2f}% below threshold {:.2f}%".format(
                       metric, value, threshold))
   
       if result["blockers"]:
           result["status"] = "FAIL"
       elif not required and not metrics:
           result["status"] = "SKIP"
       return result

**逐段解释**：

* 第 L1043-L1054 行：阈值小于等于 0 的 metric 不 gate；缺失或低于阈值都会
  生成 blocker。
* 第 L1056-L1060 行：有 blocker 时 status 为 `FAIL`；coverage 非 required
  且无 metrics 时 status 为 `SKIP`。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`coverage_candidate_files()`、`parse_coverage_text()`。
* **共享状态**：coverage 文件路径、CLI 阈值。当前 demo 数字见本章 §1 表格。

§9  waiver 和 test pool gate
--------------------------------------------------------------------------------

§9.1  `collect_cosim_exceptions()` - 收集 riscv-dv cosim-disabled
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：扫描 riscv-dv testlist，找出 `cosim` 字段为 disabled 类值的测试。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1063-L1079`）：

.. code-block:: python

   def collect_cosim_exceptions() -> List[Dict]:
       testlist = DV_DIR / "riscv_dv_extension" / "testlist.yaml"
       if not testlist.exists():
           return []
       try:
           entries = _load_yaml(testlist) or []
       except Exception:
           return []
       disabled = []
       for entry in entries:
           if str(entry.get("cosim", "")).lower() in ("disabled", "disable", "0",
                                                      "false", "no", "rtl_only"):
               disabled.append({
                   "test": entry.get("test", "unknown"),
                   "reason": entry.get("cosim_reason", ""),
               })
       return disabled

**逐段解释**：

* 第 L1064-L1070 行：只读取
  `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`；文件缺失或解析失败都返回
  空列表。
* 第 L1071-L1078 行：`cosim` 字段小写后属于 disabled 类集合时加入结果，
  同时保留 `test` 和 `cosim_reason`。
* 第 L1079 行：返回 disabled 列表。

**接口关系**：

* **被调用**：`evaluate_signoff()` 和最终 `signoff_status` 生成。
* **调用**：`_load_yaml()`。
* **共享状态**：riscv-dv testlist。integrity waiver 边界见 :ref:`adr-0017`。

§9.2  `collect_skip_in_signoff()` - 收集 sign-off skip
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：扫描 riscv-dv testlist，找出 `skip_in_signoff: true` 的测试。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1082-L1097`）：

.. code-block:: python

   def collect_skip_in_signoff() -> List[Dict]:
       testlist = DV_DIR / "riscv_dv_extension" / "testlist.yaml"
       if not testlist.exists():
           return []
       try:
           entries = _load_yaml(testlist) or []
       except Exception:
           return []
       skipped = []
       for entry in entries:
           if entry.get("skip_in_signoff") in (True, "true", "True", 1):
               skipped.append({
                   "test": entry.get("test", "unknown"),
                   "reason": entry.get("skip_reason", ""),
               })
       return skipped

**逐段解释**：

* 第 L1083-L1089 行：读取同一个 riscv-dv testlist，缺失或解析失败时返回空。
* 第 L1090-L1096 行：`skip_in_signoff` 接受布尔真、字符串 `"true"`、
  `"True"` 或整数 1。
* 第 L1097 行：返回 skipped 列表。

**接口关系**：

* **被调用**：`evaluate_signoff()` 和最终 `signoff_status` 生成。
* **调用**：`_load_yaml()`。
* **共享状态**：riscv-dv testlist。

§9.3  `detect_cosim_reason_loophole()` - 禁止 inline waiver
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：扫描 3 个 testlist，只要出现 `cosim_reason` 字段就视为 gate
loophole。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1100-L1130`）：

.. code-block:: python

   def detect_cosim_reason_loophole() -> List[Dict]:
       """Detect cosim_reason field in ANY testlist YAML.
   
       The cosim_reason field in testlist entries is a forbidden "add comment
       to PASS" loophole (see signoff-gates.md).  Waivers MUST go through
       formal waiver files under dv/uvm/core_eh2/waivers/, never through
       inline YAML comments.
   
       Returns list of {test, file_path} for every entry with cosim_reason set.
       """
       violations = []
       testlist_paths = [
           DV_DIR / "riscv_dv_extension" / "testlist.yaml",
           DV_DIR / "directed_tests" / "directed_testlist.yaml",
           DV_DIR / "directed_tests" / "cosim_testlist.yaml",
       ]

**逐段解释**：

* 第 L1100-L1109 行：docstring 明确 `cosim_reason` 不是正式 waiver，正式
  waiver 必须在 `dv/uvm/core_eh2/waivers/` 下。
* 第 L1110-L1115 行：扫描 riscv-dv、directed 和 cosim 3 个 testlist。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1116-L1130`）：

.. code-block:: python

       for testlist_path in testlist_paths:
           if not testlist_path.exists():
               continue
           try:
               entries = _load_yaml(testlist_path) or []
           except Exception:
               continue
           for entry in entries:
               if isinstance(entry, dict) and "cosim_reason" in entry:
                   violations.append({
                       "test": entry.get("test", "unknown"),
                       "file": str(testlist_path),
                       "cosim_reason": entry["cosim_reason"],
                   })
       return violations

**逐段解释**：

* 第 L1116-L1122 行：不存在或解析失败的 testlist 被跳过。
* 第 L1123-L1129 行：任意 dict entry 含 `cosim_reason` 字段就记录 test、
  文件路径和字段值。
* 第 L1130 行：返回所有违规项。

**接口关系**：

* **被调用**：`evaluate_signoff()`。
* **调用**：`_load_yaml()`。
* **共享状态**：3 个 testlist 文件。

§9.4  `validate_waiver_schema()` - waiver YAML schema
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：校验 cosim-disabled waiver 文件必须是 YAML list，且每个 entry
包含 `reason`、`tracking_issue`、`expiry_date`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1133-L1165`）：

.. code-block:: python

   def validate_waiver_schema(waiver_path: Path) -> Tuple[bool, List[str]]:
       """Validate cosim-disabled waiver YAML schema.
   
       Each entry must have: reason, tracking_issue, expiry_date.
       Returns (valid, errors).
       """
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

**逐段解释**：

* 第 L1133-L1138 行：函数返回 `(valid, errors)`。
* 第 L1139-L1147 行：缺失文件和空 YAML 都视为 valid；解析异常返回 false。
* 第 L1148-L1149 行：顶层不是 list 时失败。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1150-L1165`）：

.. code-block:: python

       required_fields = ["reason", "tracking_issue", "expiry_date"]
       for i, entry in enumerate(waivers):
           if not isinstance(entry, dict):
               errors.append("Waiver entry {} is not a dict".format(i))
               continue
           for field in required_fields:
               if field not in entry or not entry[field]:
                   errors.append(
                       "Waiver entry {} ('{}'): missing or empty field '{}'".format(
                           i, entry.get("test", "unknown"), field))
           if "expiry_date" in entry and entry["expiry_date"]:
               if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(entry["expiry_date"])):
                   errors.append(
                       "Waiver entry {} ('{}'): expiry_date '{}' must be YYYY-MM-DD".format(
                           i, entry.get("test", "unknown"), entry["expiry_date"]))

**逐段解释**：

* 第 L1150-L1159 行：每个 entry 必须是 dict，且 3 个 required field 非空。
* 第 L1160-L1164 行：`expiry_date` 必须匹配 `YYYY-MM-DD`。
* 第 L1165 行：没有 errors 时 valid 为 true。

**接口关系**：

* **被调用**：`main()` 和 `--validate-waivers` 路径。
* **调用**：`_load_yaml()`、`re.match()`。
* **共享状态**：waiver YAML 文件。

§9.5  `cosim-disabled.yaml` - 正式 waiver 文件格式
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：记录允许通过 `--fail-on-cosim-disabled` gate 的测试名和人工跟踪字段。

**关键代码** （`dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L1-L15`）：

.. code-block:: yaml

   # EH2 Cosim-Disabled Waivers
   #
   # Each waiver corresponds to a test with `cosim: disabled` in the testlist
   # (riscv_dv_extension/testlist.yaml). Only waived tests pass the
   # --fail-on-cosim-disabled gate.
   #
   # Schema (per entry):
   #   test:            test name (must match testlist exactly)
   #   reason:          technical explanation of why cosim cannot run
   #   tracking_issue:  reference to issue tracker or ADR
   #   expiry_date:     YYYY-MM-DD — after this date the waiver is invalid
   #
   # cosim_reason fields in testlist.yaml are NOT waivers — only this file confers
   # formal waiver status. The gate is enforced by signoff.py.

**逐段解释**：

* 第 L1-L5 行：文件声明每个 waiver 对应 riscv-dv testlist 里
  `cosim: disabled` 的测试，只有在这个文件里有 waiver 的测试才能通过 gate。
* 第 L7-L11 行：schema 字段为 `test`、`reason`、`tracking_issue`、
  `expiry_date`。
* 第 L13-L15 行：再次强调 `cosim_reason` 不是 waiver，gate 由 `signoff.py`
  执行。

**关键代码** （`dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L17-L26`）：

.. code-block:: yaml

   - test: riscv_csr_test
     reason: >
       Directed CSR read/write test exercises EH2-specific custom CSRs (mrac,
       mcgc, mfdc, meivt, etc.) that have WARL/U behaviours not implemented in
       Spike. Spike's CSR model does not emulate the full EH2 custom CSR space,
       leading to CSR value mismatches that cascade into GPR mismatches on CSR
       readback. The test also triggers presync/postsync side effects that Spike
       does not model.
     tracking_issue: "ADR-0006 — CSR WARL fixups in spike_cosim.cc; EH2 custom CSRs"
     expiry_date: 2026-07-31

**逐段解释**：

* 第 L17 行：entry 的 test 名必须与 testlist 中的 `riscv_csr_test` 匹配。
* 第 L18-L24 行：reason 解释该测试的 CSR 行为为什么无法由 Spike 完整建模。
* 第 L25-L26 行：tracking 和 expiry 字段满足 `validate_waiver_schema()` 的
  required fields。

**接口关系**：

* **被调用**：`validate_waiver_schema()` 和 `load_waiver_set()` 读取该文件。
* **调用**：无下层函数。
* **共享状态**：waiver 文件中的 test 名会与 `collect_cosim_exceptions()` 和
  `collect_skip_in_signoff()` 的结果比对。

§9.6  `check_directed_pool_coverage()` - directed ASM 注册完整性
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：检查 `directed_*.S` ASM 文件，并要求每个文件名在 directed
testlist 中出现。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1190-L1210`）：

.. code-block:: python

   def check_directed_pool_coverage(testlist_path: Path,
                                     asm_root: Path = None) -> Tuple[int, int, List[str]]:
       """Check directed test pool: all .S entries must be in directed_testlist.yaml.
   
       Returns (listed, on_disk, missing_from_list).
       """
       asm_dir = asm_root if asm_root else DV_DIR / "tests" / "asm"
       if not asm_dir.exists():
           return 0, 0, []
       disk_tests = set()
       for p in asm_dir.glob("directed_*.S"):
           disk_tests.add(p.stem)
       if not testlist_path.exists():
           return 0, len(disk_tests), sorted(disk_tests)

**逐段解释**：

* 第 L1190-L1195 行：函数返回 `(listed, on_disk, missing_from_list)`。
* 第 L1196-L1201 行：默认 ASM 根目录是 `DV_DIR/tests/asm`，只收集
  `directed_*.S` 的 stem。
* 第 L1202-L1203 行：testlist 不存在时，磁盘上的所有 directed ASM 都视为缺失。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1204-L1210`）：

.. code-block:: python

       try:
           entries = _load_yaml(testlist_path) or []
       except Exception:
           return 0, len(disk_tests), sorted(disk_tests)
       listed = {e.get("test", "") for e in entries if isinstance(e, dict)}
       missing = sorted(disk_tests - listed)
       return len(listed), len(disk_tests), missing

**逐段解释**：

* 第 L1204-L1207 行：testlist 解析失败时，也把所有磁盘 directed ASM 视为缺失。
* 第 L1208-L1210 行：从 YAML entry 中取 `test` 字段，与磁盘 stem 做集合差。

**接口关系**：

* **被调用**：`main()` 生成最终 `signoff_status` 前调用。
* **调用**：`_load_yaml()`。
* **共享状态**：`dv/uvm/core_eh2/tests/asm` 和
  `directed_tests/directed_testlist.yaml`。

§9.7  `compute_real_run_count()` - 实跑数和 test pool 分母
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：统计 stage result 的 total 之和，并把 3 个 testlist 的 entry 数作为
总池子分母。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1213-L1227`）：

.. code-block:: python

   def compute_real_run_count(stage_results: List[Dict]) -> Tuple[int, int]:
       """Count actually-run tests vs total pool across all testlists.
   
       Returns (ran, total_pool).
       """
       ran = sum(s.get("total", 0) for s in stage_results)
       pool = 0
       for stage, path in STAGE_TESTLIST.items():
           if path.exists():
               try:
                   entries = _load_yaml(path) or []
                   pool += len(entries)
               except Exception:
                   pass
       return ran, pool

**逐段解释**：

* 第 L1213-L1217 行：返回值是 `(ran, total_pool)`。
* 第 L1218 行：`ran` 是所有 stage result 的 `total` 求和。
* 第 L1219-L1226 行：`pool` 只统计 `STAGE_TESTLIST` 中 3 个 YAML 的 entry 数；
  解析失败的 testlist 被忽略。
* 第 L1227 行：返回实跑数和池子总数。

**接口关系**：

* **被调用**：`main()` 和单元测试。
* **调用**：`_load_yaml()`。
* **共享状态**：`STAGE_TESTLIST`。

§10  最终 sign-off 判定
--------------------------------------------------------------------------------

§10.1  `evaluate_signoff()` - precheck 和 inline waiver blocker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把 stage result、coverage result、precheck result 和 waiver schema
错误合并成最终 `PASS`、`PASS_WITH_WAIVERS` 或 `FAIL`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1230-L1248`）：

.. code-block:: python

   def evaluate_signoff(stage_results: List[Dict], coverage_result: Dict,
                        precheck_result: Dict, args,
                        waiver_errors: List[str]) -> Tuple[str, List[str]]:
       blockers = []
       if not args.skip_precheck and not precheck_result.get("passed", False):
           blockers.append("precheck failed")
   
       # Hard blocker: cosim_reason in testlist YAML is a forbidden loophole.
       # All waivers MUST go through formal waiver files under dv/uvm/core_eh2/waivers/.
       # See docs/adr/0010-integrity-cosim-waiver.md and docs/signoff-gates.md.
       cosim_reason_violations = detect_cosim_reason_loophole()
       if cosim_reason_violations:
           names = [v["test"] for v in cosim_reason_violations]
           blockers.append(
               "FORBIDDEN cosim_reason field in testlist ({}): {}. "
               "Move waiver to dv/uvm/core_eh2/waivers/cosim-disabled.yaml "
               "and REMOVE the cosim_reason field from the YAML.".format(
                   len(names), ", ".join(sorted(names))))

**逐段解释**：

* 第 L1233-L1235 行：如果未跳过 precheck 且 precheck 未通过，最终 blocker
  加入 `precheck failed`。
* 第 L1237-L1240 行：注释说明 `cosim_reason` 是 hard blocker，正式 waiver
  必须在 `waivers/` 目录下。
* 第 L1241-L1248 行：检测到 inline `cosim_reason` 后，blocker 文本列出数量和
  test 名，并要求迁移到 `cosim-disabled.yaml`。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`detect_cosim_reason_loophole()`。
* **共享状态**：precheck result、testlist。

§10.2  `evaluate_signoff()` - stage 和 coverage blocker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：检查每个 stage 的状态、最小通过数和 pass rate，并叠加 coverage
失败。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1249-L1272`）：

.. code-block:: python

       if not stage_results:
           blockers.append("no sign-off stages were evaluated")
   
       has_waivers = False
       for stage in stage_results:
           if stage["status"] == "WAIVE_TOOL_LIMITED":
               has_waivers = True
               continue
           if stage["status"] != "PASS":
               blockers.append("{}: {}".format(
                   stage["stage"], "; ".join(stage["blockers"])))
           if stage["stage"] == "formal" and stage.get("failed", 0) == 0:
               continue
           min_passed = STAGE_MIN_PASSED.get(stage["stage"])
           if min_passed is not None and stage.get("passed", 0) >= min_passed:
               continue
           if stage["pass_rate"] < args.min_pass_rate:
               blockers.append("{} pass rate {:.2f}% below {:.2f}%".format(
                   stage["stage"], stage["pass_rate"], args.min_pass_rate))
   
       if coverage_result["status"] == "FAIL":
           blockers.append("coverage: {}".format(
               "; ".join(coverage_result["blockers"])))

**逐段解释**：

* 第 L1249-L1250 行：没有任何 stage 被评估时直接失败。
* 第 L1252-L1256 行：`WAIVE_TOOL_LIMITED` 不产生 blocker，但会把最终状态
  可能降为 `PASS_WITH_WAIVERS`。
* 第 L1257-L1259 行：非 `PASS` stage 的 blocker 被附加到最终 blockers。
* 第 L1260-L1267 行：formal 在 failed 为 0 时跳过 pass-rate 检查；其他 stage
  如果达到 `STAGE_MIN_PASSED` 也跳过 pass-rate 检查，否则按
  `args.min_pass_rate` gate。
* 第 L1269-L1272 行：coverage result 为 `FAIL` 时，将 coverage blocker 汇总成
  最终 blocker。

**接口关系**：

* **被调用**：`main()`。
* **调用**：无下层函数。
* **共享状态**：`STAGE_MIN_PASSED` 和 coverage result。

§10.3  `evaluate_signoff()` - waiver gate 和返回状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：检查 cosim-disabled、skip-in-signoff、require-cosim-all-tests，并决定
最终状态字符串。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1273-L1312`）：

.. code-block:: python

       fail_on_cosim_disabled = not getattr(args, 'no_fail_on_cosim_disabled', False)
       fail_on_skip_in_signoff = not getattr(args, 'no_fail_on_skip_in_signoff', False)
   
       if fail_on_cosim_disabled or fail_on_skip_in_signoff:
           waiver_path_str = getattr(args, 'waivers_cosim_disabled', '')
           waiver_path = Path(waiver_path_str) if waiver_path_str else \
                         DV_DIR / "waivers" / "cosim-disabled.yaml"
           if waiver_errors:
               blockers.append("waiver schema errors: {}".format(
                   "; ".join(waiver_errors)))
           waived = load_waiver_set(waiver_path) if not waiver_errors else set()
       else:
           waived = set()

**逐段解释**：

* 第 L1273-L1274 行：两个 fail-on gate 默认打开，除非用户传对应
  `--no-fail-*` 参数。
* 第 L1276-L1283 行：需要 waiver 时，默认文件是
  `DV_DIR/waivers/cosim-disabled.yaml`；schema 错误会成为 blocker，且不加载
  waived set。
* 第 L1284-L1285 行：两个 gate 都关闭时，waived set 为空。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1287-L1312`）：

.. code-block:: python

       if fail_on_cosim_disabled:
           disabled = collect_cosim_exceptions()
           unwaived = [d["test"] for d in disabled if d["test"] not in waived]
           if unwaived:
               blockers.append(
                   "cosim-disabled tests without waiver ({}): {}".format(
                       len(unwaived), ", ".join(sorted(unwaived))))
   
       if fail_on_skip_in_signoff:
           skipped = collect_skip_in_signoff()
           unwaived_skip = [s["test"] for s in skipped if s["test"] not in waived]
           if unwaived_skip:
               blockers.append(
                   "skip_in_signoff tests without waiver ({}): {}".format(
                       len(unwaived_skip), ", ".join(sorted(unwaived_skip))))

**逐段解释**：

* 第 L1287-L1293 行：所有 cosim-disabled 测试必须出现在 waiver set 中，否则
  生成 blocker。
* 第 L1295-L1301 行：所有 `skip_in_signoff` 测试也必须出现在同一个 waiver set
  中，否则生成 blocker。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1303-L1312`）：

.. code-block:: python

       if args.require_cosim_all_tests:
           disabled = collect_cosim_exceptions()
           if disabled:
               names = [d["test"] for d in disabled]
               blockers.append("riscv-dv tests with cosim disabled: {}".format(
                   ", ".join(names)))
   
       if blockers:
           return "FAIL", blockers
       return ("PASS_WITH_WAIVERS" if has_waivers else "PASS", blockers)

**逐段解释**：

* 第 L1303-L1308 行：`--require-cosim-all-tests` 是更严格的 gate，只要存在
  cosim-disabled riscv-dv 测试就失败。
* 第 L1310-L1312 行：有任意 blocker 返回 `FAIL`；没有 blocker 且存在
  `WAIVE_TOOL_LIMITED` stage 返回 `PASS_WITH_WAIVERS`；否则返回 `PASS`。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`load_waiver_set()`、`collect_cosim_exceptions()`、
  `collect_skip_in_signoff()`。
* **共享状态**：waiver YAML、riscv-dv testlist、CLI gate 参数。

§11  报告生成
--------------------------------------------------------------------------------

§11.1  `write_markdown_report()` - Markdown 报告头和实跑覆盖率
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把最终 status 字典渲染为 Markdown，并在实跑覆盖率不足 95% 时把
展示状态降为 `PARTIAL`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1315-L1335`）：

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
       pool_status = "PASS" if real_pct >= 95.0 else "PARTIAL" if real_pct >= 50.0 else "FAIL"
       lines.append("- **实跑覆盖率**: {}/{} ({:.1f}%) — {}".format(
           real_ran, real_pool, real_pct, pool_status))
       if real_pct < 95.0:
           actual_status = status["status"]
           if actual_status == "PASS":
               lines.append("- **整体状态降级**: PASS → PARTIAL（真实覆盖率 {:.1f}% < 95%）".format(real_pct))
               status["status"] = "PARTIAL"

**逐段解释**：

* 第 L1316-L1318 行：`stages` 既可能是 dict，也可能是 list，内部函数统一返回
  可迭代 stage 行。
* 第 L1320-L1328 行：报告以标题开头，并计算 `real_ran / real_pool`。
* 第 L1329-L1335 行：`real_pct < 95.0` 且原状态为 `PASS` 时，报告状态被改为
  `PARTIAL`。注意这发生在 Markdown 渲染函数内。

**接口关系**：

* **被调用**：`main()` 写出 `signoff_report.md`。
* **调用**：无下层函数。
* **共享状态**：传入的 `status` 字典会被原地修改。

§11.2  `write_markdown_report()` - stage、coverage、precheck、waiver、command
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把 stage 表、coverage metrics、precheck 检查项、cosim exception、
blocker、stage waiver 和命令写入 Markdown。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1342-L1368`）：

.. code-block:: python

       lines.append("## Stages")
       lines.append("")
       lines.append("| Stage | Status | Total | Passed | Failed | Pass Rate | Warnings |")
       lines.append("|---|---:|---:|---:|---:|---:|---:|")
       for stage in stage_rows():
           lines.append("| {stage} | {status} | {total} | {passed} | {failed} | "
                        "{pass_rate:.2f}% | {warnings} |".format(**stage))
       lines.append("")
   
       lines.append("## Coverage")
       coverage = status["coverage"]
       lines.append("")
       lines.append("- Status: {}".format(coverage["status"]))
       if coverage["metrics"]:
           for metric in sorted(coverage["metrics"]):
               lines.append("- {}: {:.2f}%".format(metric,
                                                   coverage["metrics"][metric]))
       else:
           lines.append("- No parsed coverage metrics.")

**逐段解释**：

* 第 L1342-L1349 行：stage summary 以 Markdown 表格输出。
* 第 L1351-L1360 行：coverage 区域输出 status 和已解析 metrics；没有 metrics
  时写固定说明。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1363-L1406`）：

.. code-block:: python

       lines.append("## Precheck")
       lines.append("")
       for check in status["precheck"]["checks"]:
           state = "PASS" if check["passed"] else "FAIL"
           lines.append("- {}: {} ({})".format(check["name"], state,
                                               check["detail"]))
       lines.append("")
   
       disabled = status.get("cosim_disabled_tests", [])
       if disabled:
           lines.append("## Cosim Exceptions")
           lines.append("")
           lines.append("The following riscv-dv tests are marked cosim disabled "
                        "and must remain waiver-reviewed for final closure:")

**逐段解释**：

* 第 L1363-L1368 行：precheck 每项转成 `PASS` 或 `FAIL` 文本。
* 第 L1371-L1376 行：如果存在 cosim-disabled 测试，报告单独输出
  `Cosim Exceptions` 区域。
* 第 L1382-L1387 行：最终 blockers 非空时输出 `Blockers` 区域。
* 第 L1389-L1398 行：从每个 stage 的 `waivers` 列表收集 stage waiver 文本。
* 第 L1400-L1405 行：对包含 `command` 字段的 stage 输出命令行。
* 第 L1406 行：写入 Markdown 文件。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`Path.write_text()`。
* **共享状态**：最终 status 字典。

§11.3  `maybe_generate_html_report()` - HTML 报告调度
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：在 `--html-report` 打开时，为 `gen_html_report.py` 选择 coverage
dashboard 并执行 HTML 生成命令。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1409-L1429`）：

.. code-block:: python

   def _select_html_coverage_dashboard(coverage_result: Dict,
                                       cov_merged_dir: Optional[Path],
                                       output_dir: Path) -> Optional[Path]:
       """Pick a dashboard.txt path for the self-contained HTML report."""
       for file_name in coverage_result.get("files", []) or []:
           path = Path(file_name)
           if path.name == "dashboard.txt" and path.exists():
               return path
   
       candidates = []
       if cov_merged_dir:
           candidates.append(cov_merged_dir / "dashboard.txt")
       candidates.extend([
           output_dir / "cov_merged" / "dashboard.txt",
           output_dir / "coverage" / "dashboard.txt",
           output_dir / "cov_report" / "dashboard.txt",
       ])

**逐段解释**：

* 第 L1409-L1416 行：优先从 coverage result 已解析文件里选择名为
  `dashboard.txt` 且存在的文件。
* 第 L1418-L1425 行：否则依次尝试 merged coverage、`output/coverage` 和
  `output/cov_report` 下的 dashboard。
* 第 L1426-L1429 行：第一个存在的候选被返回，否则返回 `None`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1432-L1469`）：

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

**逐段解释**：

* 第 L1432-L1437 行：`args.html_report` 为 false 时直接跳过。
* 第 L1439-L1443 行：找不到 dashboard 时打印 warning，并返回 `None`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1445-L1469`）：

.. code-block:: python

       html_path = output_dir / "report.html"
       script = SCRIPT_DIR / "gen_html_report.py"
       cmd = [
           sys.executable, str(script),
           "--signoff-status", str(json_path),
           "--coverage-dashboard", str(dashboard),
           "--runs-dir", str(output_dir / "runs"),
           "--output", str(html_path),
       ]
       try:
           proc = subprocess.run(cmd, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT,
                                 universal_newlines=True, timeout=120)

**逐段解释**：

* 第 L1445-L1453 行：HTML 路径固定为 `output_dir/report.html`，命令输入为
  sign-off JSON、coverage dashboard、runs 目录和 output HTML。
* 第 L1454-L1457 行：子进程 stdout/stderr 被捕获，timeout 为 120 秒。
* 第 L1458-L1469 行：异常或非零返回码只打印 warning，不改变 sign-off 主状态；
  成功时打印 HTML 路径并返回。

**接口关系**：

* **被调用**：`main()`。
* **调用**：`_select_html_coverage_dashboard()`、`gen_html_report.py`。
* **共享状态**：`output_dir/report.html` 和 coverage dashboard。

§11.4  `gen_html_report.py` - 数据装载和页面组成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：HTML 生成器读取 sign-off JSON、coverage dashboard 和 runs 目录，
渲染自包含 HTML 页面。

**关键代码** （`dv/uvm/core_eh2/scripts/gen_html_report.py:L456-L483`）：

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
       return {
           "status": status,
           "signoff_status_path": str(signoff_status.resolve()),
           "coverage_dashboard_path": str(coverage_dashboard.resolve()),

**逐段解释**：

* 第 L456-L459 行：读取 JSON，并解析 coverage dashboard。
* 第 L460-L464 行：stage summary 和 stage detail 都从 `status` 结构派生。
* 第 L465-L466 行：display test count 优先使用 coverage report 中的测试数，
  否则使用 stage detail 中的 test 条目数。

**关键代码** （`dv/uvm/core_eh2/scripts/gen_html_report.py:L467-L483`）：

.. code-block:: python

           "runs_dir": str(runs_dir.resolve()),
           "output_path": str(output.resolve()),
           "stage_summaries": stage_summaries,
           "stages": stage_details,
           "coverage": coverage,
           "coverage_metrics": coverage["metrics"] or
           status.get("coverage", {}).get("metrics", {}),
           "test_entry_count": display_test_count,
           "per_stage_entry_count": per_stage_entry_count,
           "lec_modules": parse_lec_modules(status),
           "formal": parse_formal_results(status),
           "stage_waivers": collect_stage_waivers(status),
       }

**逐段解释**：

* 第 L467-L477 行：返回数据中同时包含路径、stage、coverage 和 fallback
  coverage metrics。
* 第 L478-L482 行：LEC module、formal property 和 stage waiver 由 helper
  从 sign-off JSON 或日志中派生。

**关键代码** （`dv/uvm/core_eh2/scripts/gen_html_report.py:L1038-L1066`）：

.. code-block:: python

   def render_html(data: Dict[str, Any]) -> str:
       """Render complete self-contained HTML."""
       parts = [
           "<!DOCTYPE html>",
           '<html lang="en">',
           "<head>",
           '<meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width, initial-scale=1">',
           "<title>EH2 Sign-off Dashboard</title>",
           "<style>{}</style>".format(css()),
           "</head>",
           "<body>",
           render_header(data),
           "<main>",
           render_nav(),
           render_stage_summary(data),

**逐段解释**：

* 第 L1038-L1048 行：HTML 页面包含 charset、viewport、title 和内联 CSS。
* 第 L1049-L1054 行：body 中先渲染 header、nav、stage summary 和 coverage
  summary。

**关键代码** （`dv/uvm/core_eh2/scripts/gen_html_report.py:L1055-L1066`）：

.. code-block:: python

           render_stage_details(data),
           render_coverage_details(data),
           render_formal_section(data),
           render_lec_section(data),
           render_lint_section(data),
           render_waivers_section(data),
           "</main>",
           "<script>{}</script>".format(javascript()),
           "</body>",
           "</html>",
       ]
       return "\n".join(parts) + "\n"

**逐段解释**：

* 第 L1055-L1060 行：页面还包含 per-stage test、coverage detail、formal、
  LEC、lint 和 waiver 区域。
* 第 L1061-L1066 行：JavaScript 内联到页面底部，函数返回完整 HTML 文本。

**接口关系**：

* **被调用**：`signoff.py maybe_generate_html_report()` 或顶层 `make html_report`。
* **调用**：coverage parser、stage normalizer、formal/LEC/lint/waiver 渲染函数。
* **共享状态**：sign-off JSON、coverage dashboard、runs 目录。

§12  CLI 入口和退出码
--------------------------------------------------------------------------------

§12.1  `main()` - 参数定义
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：定义 sign-off driver 的 CLI 参数，包含 profile、stage 复用、simulator、
coverage、waiver、LEC 和 HTML 报告开关。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1472-L1510`）：

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
       parser.add_argument("--gate-only", action="store_true",
                           help="Only evaluate --stage-result directories")
       parser.add_argument("--simulator", default="vcs",
                           choices=["vcs", "xlm", "questa"])
       parser.add_argument("--seed", type=int, default=1)
       parser.add_argument("--iterations", type=int, default=0,
                           help="Override per-test iterations for non-smoke stages")

**逐段解释**：

* 第 L1472-L1485 行：profile 默认 `full`，`--stages` 可覆盖 stage 列表，
  `--stage-result` 可重复传入，`--dry-run` 和 `--gate-only` 是两种不直接运行
  stage 的路径。
* 第 L1486-L1490 行：simulator 限定为 `vcs`、`xlm`、`questa`，seed 默认 1，
  iterations 默认 0。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1491-L1538`）：

.. code-block:: python

       parser.add_argument("--max-iter-per-test", type=int, default=0,
                           help="Alias for --iterations; caps non-smoke per-test iterations")
       parser.add_argument("--parallel", type=int, default=1)
       parser.add_argument("--timeout-s", type=int, default=7200)
       parser.add_argument("--coverage", action="store_true",
                           help="Enable simulator coverage while running stages")
       parser.add_argument("--waves", action="store_true",
                           help="Enable waveform dumping while running stages")
       parser.add_argument("--coverage-path", action="append", default=[],
                           help="Coverage report file or directory to gate")
       parser.add_argument("--no-require-coverage", action="store_true",
                           dest="no_require_coverage",
                           help="Disable coverage requirement (escape hatch for old behavior)")
       parser.add_argument("--min-pass-rate", type=float, default=100.0)
       parser.add_argument("--min-overall-coverage", type=float, default=0.0)
       parser.add_argument("--min-line-coverage", type=float, default=60.0)
       parser.add_argument("--min-cond-coverage", type=float, default=0.0)
       parser.add_argument("--min-fsm-coverage", type=float, default=0.0)
       parser.add_argument("--min-toggle-coverage", type=float, default=0.0)
       parser.add_argument("--min-functional-coverage", type=float, default=0.0)

**逐段解释**：

* 第 L1491-L1494 行：`--max-iter-per-test` 是 `--iterations` 的别名，
  parallel 默认 1，timeout 默认 7200 秒。
* 第 L1559-L1565 行：simulator 支持 ``vcs``、``nc``、``xlm``、``questa``；
  顶层 Makefile 当前只允许 sign-off 使用 ``vcs`` 或 ``nc``。
* 第 L1572-L1580 行：coverage、waves、coverage path 和 coverage required
  escape hatch 在这里定义。
* 第 L1581-L1588 行：裸 CLI 默认 pass rate 为 100.0，line coverage threshold
  为 60.0，其他 coverage threshold 默认 0.0。顶层 Makefile 在 `COV=1` 时会
  覆盖其中部分阈值。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1511-L1538`）：

.. code-block:: python

       parser.add_argument("--no-fail-on-cosim-disabled", action="store_true",
                           dest="no_fail_on_cosim_disabled",
                           help="Do not fail on cosim-disabled tests without waivers")
       parser.add_argument("--no-fail-on-skip-in-signoff", action="store_true",
                           dest="no_fail_on_skip_in_signoff",
                           help="Do not fail on skip_in_signoff tests without waivers")
       parser.add_argument("--waivers-cosim-disabled", type=str, default="",
                           help="Path to cosim-disabled waivers YAML")
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

**逐段解释**：

* 第 L1511-L1518 行：cosim-disabled、skip-in-signoff 和自定义 waiver 文件参数
  在这里定义。
* 第 L1519-L1523 行：warning、precheck 和 require-cosim-all-tests gate 在这里
  定义。
* 第 L1524-L1529 行：LEC tool limitation waiver 和 block-level summary 路径
  在这里定义。
* 第 L1530-L1537 行：HTML 报告默认开启，可用 `--no-html-report` 关闭；
  `--validate-waivers` 只做 schema 校验并退出。

**接口关系**：

* **被调用**：脚本入口 `sys.exit(main())`。
* **调用**：`argparse.ArgumentParser`。
* **共享状态**：CLI 参数对象 `args`。

§12.2  `main()` - waiver schema 校验和 full profile coverage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：处理 `--validate-waivers` 的早退出路径，并强制 `full` profile 要求
coverage。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1538-L1563`）：

.. code-block:: python

       args = parser.parse_args(argv)
       if args.max_iter_per_test:
           args.iterations = args.max_iter_per_test
   
       if args.validate_waivers:
           waiver_p = Path(args.validate_waivers)
           if not waiver_p.exists():
               print("ERROR: waiver file not found: {}".format(waiver_p))
               return 1
           valid, errors = validate_waiver_schema(waiver_p)
           if errors:
               print("Schema validation FAILED for {}:".format(waiver_p))
               for err in errors:
                   print("  - {}".format(err))
               return 1

**逐段解释**：

* 第 L1538-L1540 行：解析参数后，如果设置了 `--max-iter-per-test`，覆盖
  `args.iterations`。
* 第 L1542-L1552 行：`--validate-waivers` 路径只检查文件存在和 schema；失败
  返回 1。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1553-L1563`）：

.. code-block:: python

           print("Schema validation PASSED for {}".format(waiver_p))
           waived = load_waiver_set(waiver_p)
           print("Loaded {} waived entries".format(len(waived)))
           for w in sorted(waived):
               print("  - {}".format(w))
           return 0
   
       # For full profile, coverage gates are mandatory regardless of flags.
       if args.profile == "full":
           args.no_require_coverage = False

**逐段解释**：

* 第 L1553-L1558 行：schema 通过时打印 loaded waiver 数量和名称，然后返回 0。
* 第 L1560-L1563 行：`profile == "full"` 时强制
  `args.no_require_coverage = False`，即 `--no-require-coverage` 不会关闭 full
  profile 的 coverage requirement。

**接口关系**：

* **被调用**：`main()` 内部。
* **调用**：`validate_waiver_schema()`、`load_waiver_set()`。
* **共享状态**：CLI 参数对象。

§12.3  `main()` - 计划生成、dry-run 和 stage 循环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：创建输出目录、解析 stage、生成 planned 命令，并按 stage 执行或复用
结果目录。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1564-L1580`）：

.. code-block:: python

       output_dir = Path(args.output).resolve()
       output_dir.mkdir(parents=True, exist_ok=True)
   
       stages = resolve_stages(args.profile, args.stages)
       stage_result_dirs = parse_stage_result_args(args.stage_result)
   
       planned = []
       for stage in stages:
           stage_out = output_dir / "runs" / stage
           planned.append((stage, build_stage_cmd(stage, args, stage_out), stage_out))
   
       if args.dry_run:
           print("EH2 sign-off plan: profile={} stages={}".format(
               args.profile, ",".join(stages)))
           for stage, cmd, _ in planned:
               print("{}: {}".format(stage, _cmd_str(cmd)))
           return 0

**逐段解释**：

* 第 L1564-L1565 行：输出目录转绝对路径并创建。
* 第 L1567-L1568 行：解析 stage 列表和已有 stage result 目录。
* 第 L1570-L1573 行：每个 stage 的输出目录固定为 `output_dir/runs/<stage>`，
  planned tuple 包含 stage 名、命令和输出目录。
* 第 L1575-L1580 行：dry-run 打印计划后返回 0，不进入 precheck 和 gate。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1582-L1623`）：

.. code-block:: python

       precheck_result = {"passed": True, "checks": []}
       if not args.skip_precheck:
           precheck_result = precheck(stages, args.simulator)
   
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

**逐段解释**：

* 第 L1582-L1584 行：除非 `--skip-precheck`，否则运行 precheck。
* 第 L1586-L1591 行：如果用户通过 `--stage-result` 指定了 stage 目录，
  不运行命令，exit code 视为 0。
* 第 L1592-L1595 行：`--gate-only` 未指定 stage-result 时使用默认
  `stage_out`，并把 exit code 置为 1。这会要求已有结果能通过后续收集和阈值逻辑。
* 第 L1596-L1601 行：普通路径调用 `run_command()`，日志写到
  `output_dir/logs/<stage>.log`。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1603-L1623`）：

.. code-block:: python

           report_dir = output_dir / "reports" / stage
           if stage == "lint":
               stage_result = collect_lint_stage(stage, results_dir, report_dir)
           elif stage == "formal":
               stage_result = collect_formal_stage(stage, results_dir, report_dir)
           elif stage == "syn":
               stage_result = collect_syn_stage(
                   stage, results_dir, report_dir,
                   lec_known_limited=args.lec_known_limited,
                   lec_blocklevel=args.lec_blocklevel,
                   lec_summary_path=args.lec_summary_path)
           else:
               stage_result = collect_stage(
                   stage, results_dir, report_dir, command, exit_code,
                   fail_on_warnings=not args.allow_warnings)

**逐段解释**：

* 第 L1603-L1613 行：`lint`、`formal`、`syn` 分别使用专用收集器。
* 第 L1614-L1617 行：其他 stage 使用通用 `collect_stage()`。
* 第 L1618-L1622 行：`compliance` stage 在通用收集后额外执行 per-suite gate；
  有 suite blocker 时把 stage status 改为 `FAIL`。
* 第 L1623 行：stage result 追加到 `stage_results`。

**接口关系**：

* **被调用**：`main()` 内部。
* **调用**：`resolve_stages()`、`parse_stage_result_args()`、
  `build_stage_cmd()`、`run_command()`、各类 collect 函数。
* **共享状态**：输出目录、stage result 目录、stage report 目录。

§12.4  `main()` - 汇总 status、写文件和退出码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：合并 coverage，校验 waiver，评估最终状态，写 JSON/Markdown/HTML，并把
最终状态映射为进程退出码。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1625-L1645`）：

.. code-block:: python

       # Auto-merge coverage across stages before gate evaluation
       cov_merged_dir = None
       if not args.gate_only and not args.dry_run and args.coverage:
           cov_merged_dir = auto_merge_stage_coverage(stage_results, output_dir)
   
       coverage_paths = [Path(p).resolve() for p in args.coverage_path]
       if cov_merged_dir and cov_merged_dir.exists():
           coverage_paths.append(cov_merged_dir)
       coverage_result = evaluate_coverage(coverage_paths, output_dir, args)
   
       waiver_errors = []
       waiver_path_str = getattr(args, 'waivers_cosim_disabled', '')
       waiver_path = Path(waiver_path_str) if waiver_path_str else \
                     DV_DIR / "waivers" / "cosim-disabled.yaml"
       if waiver_path.exists():
           waiver_valid, waiver_errors = validate_waiver_schema(waiver_path)
       elif not waiver_path_str:
           pass

**逐段解释**：

* 第 L1625-L1628 行：只有普通运行且 `--coverage` 打开时才自动合并 stage
  coverage。
* 第 L1630-L1633 行：CLI coverage path 和 merged coverage 目录共同传给
  `evaluate_coverage()`。
* 第 L1635-L1642 行：默认 waiver 文件为 `DV_DIR/waivers/cosim-disabled.yaml`；
  文件存在才校验 schema。
* 第 L1644-L1645 行：调用 `evaluate_signoff()` 得到最终 status 和 blockers。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1647-L1674`）：

.. code-block:: python

       real_ran, real_pool = compute_real_run_count(stage_results)
       directed_listed, directed_on_disk, directed_missing = \
           check_directed_pool_coverage(STAGE_TESTLIST.get("directed",
                                       DV_DIR / "directed_tests" / "directed_testlist.yaml"))
       if directed_missing:
           blockers.append("directed tests on disk but not in testlist: {}".format(
               ", ".join(directed_missing)))
   
       stage_results_by_name = {stage["stage"]: stage for stage in stage_results}
       signoff_status = {
           "status": status,
           "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "profile": args.profile,
           "stages_requested": stages,

**逐段解释**：

* 第 L1647-L1650 行：计算实跑数和 directed ASM 注册完整性。
* 第 L1651-L1653 行：如果磁盘上存在未注册 directed ASM，最终 blockers 追加
  缺失列表。
* 第 L1655-L1660 行：stage result 同时保留 dict 形式和 list 形式，便于
  JSON 消费端按名称或顺序读取。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1661-L1693`）：

.. code-block:: python

           "output_dir": str(output_dir),
           "precheck": precheck_result,
           "stages": stage_results_by_name,
           "stage_results": stage_results,
           "coverage": coverage_result,
           "cosim_disabled_tests": [d["test"] for d in collect_cosim_exceptions()],
           "skip_in_signoff_tests": [s["test"] for s in collect_skip_in_signoff()],
           "real_ran": real_ran,
           "real_pool": real_pool,
           "directed_on_disk": directed_on_disk,
           "directed_missing_from_list": directed_missing,
           "waiver_errors": waiver_errors,
           "blockers": blockers,
       }

**逐段解释**：

* 第 L1661-L1674 行：最终 JSON 状态包含输出目录、precheck、stage、coverage、
  waiver/testlist 派生字段、实跑统计和 blocker。

**关键代码** （`dv/uvm/core_eh2/scripts/signoff.py:L1676-L1693`）：

.. code-block:: python

       json_path = output_dir / "signoff_status.json"
       md_path = output_dir / "signoff_report.md"
       json_path.write_text(json.dumps(signoff_status, indent=2,
                                       default=_json_default) + "\n",
                            encoding="utf-8")
       write_markdown_report(signoff_status, md_path)
       html_path = maybe_generate_html_report(
           args, output_dir, json_path, coverage_result, cov_merged_dir)
   
       print("EH2 sign-off {}: {}".format(status, md_path))
       if html_path:
           print("EH2 sign-off HTML: {}".format(html_path))
       if blockers:
           print("Blockers:")
           for blocker in blockers:
               print("  - {}".format(blocker))
   
       return 0 if status in ("PASS", "PASS_WITH_WAIVERS") else 1

**逐段解释**：

* 第 L1676-L1683 行：写出 `signoff_status.json`、`signoff_report.md`，并尝试生成
  `report.html`。
* 第 L1685-L1691 行：stdout 打印 sign-off 状态、Markdown 路径、HTML 路径和
  blockers。
* 第 L1693 行：只有 `PASS` 和 `PASS_WITH_WAIVERS` 返回 0；其他状态返回 1。

**接口关系**：

* **被调用**：`sys.exit(main())`。
* **调用**：coverage、waiver、directed pool、JSON/Markdown/HTML 生成函数。
* **共享状态**：最终输出目录下的 `signoff_status.json`、`signoff_report.md`、
  `report.html`。

§13  gate 单元测试覆盖
--------------------------------------------------------------------------------

§13.1  `Args` fixture - 测试用 argparse 替身
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：为 gate 单元测试提供最小参数对象。

**关键代码** （`dv/uvm/core_eh2/tests/test_signoff_gates.py:L39-L55`）：

.. code-block:: python

   class Args:
       """Minimal argparse-like namespace for testing."""
       skip_precheck = True
       min_pass_rate = 100.0
       require_cosim_all_tests = False
       no_require_coverage = False
       no_fail_on_cosim_disabled = False
       no_fail_on_skip_in_signoff = False
       waivers_cosim_disabled = ""
       min_overall_coverage = 0.0
       min_line_coverage = 60.0
       min_cond_coverage = 0.0
       min_fsm_coverage = 0.0
       min_toggle_coverage = 0.0
       min_functional_coverage = 50.0
       min_pass_rate = 100.0
       require_coverage = True

**逐段解释**：

* 第 L39-L47 行：测试对象模拟 precheck、pass-rate、cosim waiver 和 skip waiver
  参数。
* 第 L48-L55 行：测试 fixture 中 line threshold 为 60.0，functional threshold
  为 50.0。这个测试 fixture 用于覆盖 gate 规则；裸 CLI 默认值仍以
  `signoff.py` 的 argparse 行为为准。

**接口关系**：

* **被调用**：`test_signoff_gates.py` 中多个测试实例化。
* **调用**：无下层函数。
* **共享状态**：测试内存对象，不写文件。

§13.2  coverage requirement 测试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：验证 coverage 默认 required，且 `--no-require-coverage` 可恢复
`SKIP` 行为。

**关键代码** （`dv/uvm/core_eh2/tests/test_signoff_gates.py:L60-L78`）：

.. code-block:: python

   def test_coverage_required_by_default():
       """Coverage must be required unless explicitly disabled."""
       args = Args()
       result = evaluate_coverage([], Path("/tmp"), args)
       assert result["required"] is True
       # With no coverage files, it should FAIL (not SKIP)
       assert result["status"] == "FAIL"
   
   
   def test_coverage_optional_with_escape_hatch():
       """--no-require-coverage should restore old SKIP behavior."""
       args = Args()
       args.no_require_coverage = True
       # Set thresholds to 0 to test pure requirement
       args.min_line_coverage = 0.0
       args.min_functional_coverage = 0.0
       result = evaluate_coverage([], Path("/tmp"), args)
       assert result["required"] is False
       assert result["status"] == "SKIP"

**逐段解释**：

* 第 L60-L67 行：无 coverage 文件且 coverage required 时，`evaluate_coverage()`
  应返回 `FAIL`。
* 第 L69-L78 行：设置 `no_require_coverage=True`，并把阈值清零后，无 metrics
  时应返回 `SKIP`。

**接口关系**：

* **被调用**：pytest。
* **调用**：`evaluate_coverage()`。
* **共享状态**：临时 `Path("/tmp")`，不写 repo 文件。

§13.3  waiver schema 测试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：验证 waiver entry 缺少字段或 expiry 格式错误会失败，合法 entry 会通过。

**关键代码** （`dv/uvm/core_eh2/tests/test_signoff_gates.py:L237-L284`）：

.. code-block:: python

   def test_waiver_schema_rejects_missing_expiry():
       """Waiver entries without expiry_date must fail validation."""
       with tempfile.NamedTemporaryFile(
               mode="w", suffix=".yaml", delete=False) as f:
           yaml.dump([{
               "test": "riscv_foo_test",
               "reason": "some reason",
               # missing tracking_issue and expiry_date
           }], f)
           f.flush()
           valid, errors = validate_waiver_schema(Path(f.name))
           assert not valid
           assert len(errors) >= 2  # missing tracking_issue and expiry_date
           os.unlink(f.name)

**逐段解释**：

* 第 L237-L245 行：临时 YAML 只包含 `test` 和 `reason`。
* 第 L247-L250 行：`validate_waiver_schema()` 必须返回 invalid，并至少报告两个
  缺失字段。

**关键代码** （`dv/uvm/core_eh2/tests/test_signoff_gates.py:L253-L284`）：

.. code-block:: python

   def test_waiver_schema_rejects_bad_expiry_format():
       """expiry_date must be YYYY-MM-DD format."""
       with tempfile.NamedTemporaryFile(
               mode="w", suffix=".yaml", delete=False) as f:
           yaml.dump([{
               "test": "riscv_foo_test",
               "reason": "some reason",
               "tracking_issue": "example.com/1",
               "expiry_date": "June-2026",  # wrong format
           }], f)
           f.flush()
           valid, errors = validate_waiver_schema(Path(f.name))
           assert not valid
           assert any("expiry_date" in e.lower() for e in errors)

**逐段解释**：

* 第 L253-L262 行：临时 YAML 包含所有字段，但 `expiry_date` 不是
  `YYYY-MM-DD`。
* 第 L264-L267 行：schema 校验必须失败，错误文本包含 `expiry_date`。
* 第 L270-L284 行：合法 entry 包含 `test`、`reason`、`tracking_issue` 和
  `expiry_date: 2026-12-31`，校验必须通过且无错误。

**接口关系**：

* **被调用**：pytest。
* **调用**：`validate_waiver_schema()`。
* **共享状态**：临时 YAML 文件。

§13.4  Markdown 实跑覆盖率降级测试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：验证 `write_markdown_report()` 输出实跑覆盖率，并在实跑比例低于 95%
时把报告状态降为 `PARTIAL`。

**关键代码** （`dv/uvm/core_eh2/tests/test_signoff_gates.py:L305-L329`）：

.. code-block:: python

   def test_report_shows_real_coverage():
       """write_markdown_report must include real coverage rate line."""
       status = {
           "status": "PASS",
           "timestamp": "2026-01-01T00:00:00",
           "profile": "full",
           "output_dir": "/tmp/test",
           "precheck": {"checks": []},
           "stages": [],
           "coverage": {"status": "SKIP", "metrics": {}, "blockers": []},
           "cosim_disabled_tests": [],
           "real_ran": 40,
           "real_pool": 62,

**逐段解释**：

* 第 L305-L318 行：测试构造一个 `PASS` 状态，但 `real_ran=40`、
  `real_pool=62`，实跑比例低于 95%。

**关键代码** （`dv/uvm/core_eh2/tests/test_signoff_gates.py:L318-L329`）：

.. code-block:: python

           "blockers": [],
       }
       with tempfile.NamedTemporaryFile(
               mode="w", suffix=".md", delete=False) as f:
           write_markdown_report(status, Path(f.name))
           content = Path(f.name).read_text()
           assert "实跑覆盖率" in content
           assert "40/62" in content
           assert "64.5%" in content
           # Status should be downgraded from PASS to PARTIAL
           assert "PARTIAL" in content
           os.unlink(f.name)

**逐段解释**：

* 第 L320-L323 行：把报告写入临时 Markdown 并读回内容。
* 第 L324-L328 行：断言报告包含 `实跑覆盖率`、`40/62`、`64.5%` 和
  `PARTIAL`。
* 第 L329 行：删除临时文件。

**接口关系**：

* **被调用**：pytest。
* **调用**：`write_markdown_report()`。
* **共享状态**：临时 Markdown 文件。

§14  release 证据和参考资料
--------------------------------------------------------------------------------

§14.1  2026-05-19 VCS demo 数字的来源
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：固定本章引用的当前 demo 数字，防止把历史 R3/R4 证据、gate 阈值和
2026-05-19 VCS 主线结果混为一谈。

**关键数据** （2026-05-19 01:02，VCS 主线）：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   real run coverage: 102/104 (98.1%)
   LEC: 31635/31635 PASS

   riscvdv   370/395 (93.67%)
   compliance 85/88 (96.59%)
   directed  40/40 (100%)
   formal    46/46 (100%)

**逐段解释**：

* ``9/9 Stages PASS`` 对应 `PROFILE_STAGES["full"]` 的 smoke、directed、cosim、
  riscvdv、lint、csr_unit、compliance、formal、syn。
* ``102/104 (98.1%)`` 是 Markdown 报告中的实跑覆盖率，不等同于 URG coverage
  百分比。
* ``31635/31635 PASS`` 来自 :file:`syn/build/lec_summary.txt`，即 block-level
  Formality LEC summary。

**关键数据** （URG 原生 dashboard，DUT subtree）：

.. code-block:: text

   LINE     95.05%
   BRANCH   84.97%
   TOGGLE   53.52%
   ASSERT   33.33%
   FSM      54.74%
   GROUP    69.42%
   OVERALL  65.17%

**逐段解释**：

* VCS 编译维度是 ``line+tgl+assert+fsm+branch``，不包含 ``cond``。
* ``GROUP`` 是 covergroup 结果，在 `signoff.py` 内部以历史兼容键
  ``functional`` 保存；文档和 dashboard 口径统一写 ``GROUP``。
* ``OVERALL`` 是 URG dashboard 的综合分，不作为唯一 sign-off gate 替代分项阈值。

**接口关系**：

* **被调用**：本章 §1 和流程层其它 coverage/sign-off 解释。
* **调用**：无下层函数。
* **共享状态**：所有流程章节必须同步这些数字，不能引用旧 R3/R4 路径或 NC 迁移
  期间的 coverage 口径。

§14.2  关联 ADR
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

本章引用的 ADR 编号均已在 :file:`docs/adr/INDEX.md` 和 Sphinx ADR 附录中存在：

* :ref:`adr-0011` - RISC-V compliance framework，对应 compliance stage。
* :ref:`adr-0012` - formal verification strategy，对应 formal stage。
* :ref:`adr-0013` - synthesis toolchain，对应 syn/LEC stage。
* :ref:`adr-0014` - formal real runs，对应 IFV 真实运行记录。
* :ref:`adr-0017` - integrity cosim waiver，对应 cosim-disabled waiver 边界。
* :ref:`adr-0019` - LEC tool-version limitation，对应 `--lec-known-limited`。
* :ref:`adr-0020` - block-level LEC closure，对应 `--lec-blocklevel` 和
  `syn/build/lec_summary.txt`。

§14.3  参考资料
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* 源文件：:file:`/home/host/eh2-veri/Makefile`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/gen_html_report.py`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/test_signoff_gates.py`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
* demo 证据：2026-05-19 01:02 VCS 主线 sign-off 摘要
* LEC 证据：:file:`/home/host/eh2-veri/syn/build/lec_summary.txt`
* gate 说明：:file:`/home/host/eh2-veri/docs/signoff-gates.md`
* 关联章节：:ref:`build_flow`、:ref:`regression_flow`、:ref:`formal_flow`、
  :ref:`synthesis_flow`、:ref:`lec_flow`、:ref:`lint_flow`、
  :ref:`scripts_reference`
