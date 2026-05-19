.. _examples:
.. _03_integration/examples:

使用示例
========

:status: draft
:source: README.md; Makefile; dv/uvm/core_eh2/scripts/run_regress.py; dv/uvm/core_eh2/scripts/signoff.py; dv/uvm/core_eh2/directed_tests/directed_testlist.yaml; dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章边界
-------------

本章只保留当前源码能验证的命令示例。旧版示例中的测试枚举命令、独立覆盖率合并命令、
带 `GOAL=smoke` 的 regress 写法和旧 sign-off profile 变量名不再作为示例出现，因为它们不在
当前顶层 `Makefile` 的推荐入口中。

示例命令分为 5 类：

.. code-block:: bash

   # 快速开发循环
   make smoke NO_COSIM=1 COV=0
   make regress TEST=directed_alu TESTLIST=directed SEED=1 COV=0

   # directed/cosim testlist
   make regress TESTLIST=directed ITERATIONS=1 PARALLEL=4 COV=0
   make cosim
   make regress TESTLIST=cosim ITERATIONS=1 PARALLEL=4 COV=0

   # sign-off 规划和复演
   python3 dv/uvm/core_eh2/scripts/signoff.py --profile full --dry-run
   make signoff_replay STAGE_DATA_DIR=build/demo

逐段解释：

* 第 1-3 行：开发循环优先使用 `make smoke` 和 `make regress TEST=...`。
  `NO_COSIM=1` 属于编译期跳过 Spike DPI 链接，`COV=0` 避免示例默认引入覆盖率开销。
* 第 5-8 行：directed testlist 不要求先跑 `make cosim`；cosim testlist 需要
  `build/libcosim.so`，因此示例先执行 `make cosim`。
* 第 10-11 行：`--dry-run` 只打印 sign-off 计划，不执行 stage；`signoff_replay`
  从既有 `STAGE_DATA_DIR/runs` 读取结果。

接口关系：

* 被调用：人工开发、CI 调试、release gate 复演。
* 调用：顶层 `Makefile`、`run_regress.py`、`signoff.py`。
* 共享状态：`build/simv`、`build/libcosim.so`、`build/regression/`、
  stage result 目录。

§2  smoke 与单测
-----------------

`make smoke` 是当前最短冒烟路径。调试单个 directed test 时，推荐使用
`make regress TEST=<name> TESTLIST=directed`，而不是旧 `make run`。

关键代码（`Makefile:L372-L385`）：

.. code-block:: bash

     make smoke
           用途：跑 1 个 smoke 测试快速冒烟。和 sign-off smoke stage 跑的是同一个测试
           耗时：~1 分钟（含 compile 自动重建）
           依赖：自动触发 make compile + make asm
           变量：
             SIMULATOR=vcs|xlm                仿真器（默认 vcs）
           产出：
             build/smoke/<test>_s1/sim_*.log
             build/smoke/<test>_s1/result.yaml
             build/smoke/regr.log
             build/smoke/report.json

逐段解释：

* 第 372-375 行：help 文本明确 `make smoke` 会自动触发 `make compile` 和 `make asm`。
* 第 376-382 行：唯一暴露变量是 `SIMULATOR`，产物落在 `build/smoke`。
* 第 384-385 行：示例支持默认 simulator 和 `SIMULATOR=xlm`。VCS 是默认值，Xcelium
  用 `xlm` 变量值选择。

关键代码（`Makefile:L826-L836`）：

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

* 第 826 行：`smoke` 依赖 `compile` 和 `asm`，所以示例不需要手动先跑 `make asm`。
* 第 828-834 行：实际执行命令是 `run_regress.py --test smoke`，输入 binary 是
  `tests/asm/smoke.hex`，UVM test class 是 `core_eh2_base_test`，运行期 plusarg
  是 `+disable_cosim=1`。
* 第 835 行：输出目录固定为 `build/smoke`。

可复制示例：

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh
   make smoke NO_COSIM=1 SIMULATOR=vcs COV=0

逐段解释：

* 第 3 行：`NO_COSIM=1` 传给 `compile` 依赖，适合无 Spike DPI 的本地 smoke。
  `make smoke` recipe 自身已经传入 `+disable_cosim=1`。

接口关系：

* 被调用：人工 quick smoke、`signoff.py` 的 smoke stage 等价命令。
* 调用：`compile`、`asm`、`run_regress.py`。
* 共享状态：`tests/asm/smoke.hex`、`build/smoke/`、`build/simv`。

§3  单个 directed test
-----------------------

`directed_alu` 是当前 directed testlist 中存在的测试名。直接调用 `run_regress.py`
和通过 `make regress TEST=... TESTLIST=directed` 都可以表达这个示例。

关键代码（`directed_testlist.yaml:L25-L35`）：

.. code-block:: yaml

   - test: directed_smoke
     desc: "Mailbox smoke test running through the directed-test pipeline"
     config: eh2_directed
     test_srcs: tests/asm/cosim_smoke.S
     iterations: 1

   - test: directed_alu
     desc: "Deterministic ALU directed test"
     config: eh2_directed
     test_srcs: tests/asm/cosim_alu.S
     iterations: 1

逐段解释：

* 第 25-29 行：`directed_smoke` 使用 `eh2_directed` 配置和
  `tests/asm/cosim_smoke.S`。
* 第 31-35 行：`directed_alu` 使用同一配置，源码是 `tests/asm/cosim_alu.S`，
  `iterations` 为 1。

关键代码（`README.md:L341-L350`）：

.. code-block:: bash

   Run one directed test:

   ```bash
   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --test directed_alu \
     --testlist dv/uvm/core_eh2/directed_tests/directed_testlist.yaml \
     --simulator vcs \
     --seed 1 \
     --output build/one_directed
   ```

逐段解释：

* 第 341-346 行：README 示例直接调用 `run_regress.py`，并同时提供 `--test` 与
  `--testlist`。脚本会从 testlist 中查找 `directed_alu`。
* 第 347-349 行：simulator 固定为 `vcs`，seed 为 1，输出目录为
  `build/one_directed`。

等价 Make 示例：

.. code-block:: bash

   make regress TEST=directed_alu TESTLIST=directed SEED=1 \
     OUT=build/one_directed NO_COSIM=1 COV=0

逐段解释：

* `TEST=directed_alu` 触发 `Makefile:L840` 中 `--test $(TEST)` 分支。
* `TESTLIST=directed` 仍有意义，因为 `run_regress.py` 在单测模式下需要知道从哪个
  testlist 找到该 test 的 YAML 条目。
* `OUT=build/one_directed` 对齐 README 示例中的输出目录。

接口关系：

* 被调用：单测调试。
* 调用：`run_regress.py`、directed testlist、ASM 编译与 RTL 仿真。
* 共享状态：`build/one_directed/`、directed testlist 条目、`tests/asm/cosim_alu.S`。

§4  directed testlist 回归
---------------------------

directed testlist 是一组 YAML 条目。当前 Makefile 的通用入口是 `make regress
TESTLIST=directed`。

关键代码（`Makefile:L387-L412`）：

.. code-block:: bash

     make regress
           用途：通用回归入口，覆盖旧的 run / nightly / weekly / run_regress
           耗时：取决于 TESTLIST 和 ITERATIONS：riscvdv 全量约 30-60 分钟
           依赖：自动触发 make compile
           变量：
             TEST=<name>                       指定单测（不填则跑整个 testlist）
             SEED=<N>                          随机种子（默认 1）
             TESTLIST=riscvdv|directed|cosim   testlist 选择（默认 riscvdv）
             ITERATIONS=<N>                    迭代次数（默认 1；旧 weekly 用 5）
             PARALLEL=<N>                      并行度（默认 4）
             COV=0|1                           覆盖率（默认 1）

逐段解释：

* 第 387-390 行：`make regress` 是当前通用回归入口，先触发 `make compile`。
* 第 392-399 行：`TEST`、`SEED`、`TESTLIST`、`ITERATIONS`、`PARALLEL`、
  `COV`、`OUT`、`SIMULATOR` 都是可覆盖变量。
* 第 407-412 行：help 示例明确写出 `make regress TESTLIST=directed` 和
  `make regress TESTLIST=cosim PARALLEL=8`。

可复制示例：

.. code-block:: bash

   make regress TESTLIST=directed ITERATIONS=1 PARALLEL=4 \
     OUT=build/directed_smoke COV=0 NO_COSIM=1

逐段解释：

* `TESTLIST=directed` 路由到 `dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`。
* `ITERATIONS=1` 保持 testlist 中每项 1 次的示例语义。
* `NO_COSIM=1` 只影响编译期 Spike DPI 链接；具体 test 的运行期 cosim plusarg
  由 testlist 条目和 `run_regress.py` 合成。

接口关系：

* 被调用：开发自检、quick sign-off 前的 directed 回归。
* 调用：`compile`、`run_regress.py`、directed YAML。
* 共享状态：`build/directed_smoke/`、`build/simv`。

§5  cosim directed list
------------------------

cosim testlist 使用 `core_eh2_cosim_test`，并要求 Spike lockstep 相关 DPI 库已经可用。
README 中保留了直接调用 `run_regress.py` 的示例。

关键代码（`cosim_testlist.yaml:L1-L16`）：

.. code-block:: yaml

   # SPDX-License-Identifier: Apache-2.0
   # EH2 cosim proof tests. These are framework proof points and run with
   # core_eh2_cosim_test so Spike lockstep is enabled by construction.

   - config: eh2_cosim
     rtl_test: core_eh2_cosim_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - test: cosim_smoke
     desc: "Cosim initialization, binary load, first Spike step, mailbox PASS"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_smoke.S
     iterations: 1

逐段解释：

* 第 1-3 行：文件注释把这些测试定义为 cosim proof tests，并说明使用
  `core_eh2_cosim_test`。
* 第 5-10 行：`eh2_cosim` 配置指定 UVM test class、timeout、gcc options、
  linker script 和 include 路径。
* 第 12-16 行：`cosim_smoke` 使用 `tests/asm/cosim_smoke.S`，迭代次数为 1。

关键代码（`README.md:L352-L361`）：

.. code-block:: bash

   Run the cosim directed list:

   ```bash
   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --testlist dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml \
     --simulator vcs \
     --iterations 1 \
     --parallel 4 \
     --output build/cosim_directed
   ```

逐段解释：

* 第 352-356 行：README 示例直接传入 cosim testlist 文件。
* 第 357-360 行：示例选择 VCS、1 次迭代、4 并行，输出到 `build/cosim_directed`。

等价 Make 示例：

.. code-block:: bash

   make cosim
   make regress TESTLIST=cosim ITERATIONS=1 PARALLEL=4 \
     OUT=build/cosim_directed COV=0

逐段解释：

* 第 1 行：`make cosim` 负责生成 `build/libcosim.so`。`signoff.py` 的 cosim
  precheck 也检查该文件存在。
* 第 2-3 行：`TESTLIST=cosim` 路由到 cosim testlist，输出目录对齐 README 示例。

接口关系：

* 被调用：cosim proof point 回归。
* 调用：`make cosim`、`run_regress.py`、Spike DPI、cosim testlist。
* 共享状态：`build/libcosim.so`、`build/cosim_directed/`。

§6  cosim plusarg 合成
----------------------

示例里不手写 `+enable_cosim=1`，是因为 `run_regress.py` 会根据 testlist 的 `cosim`
字段补齐 plusarg。

关键代码（`run_regress.py:L118-L140`）：

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

逐段解释：

* 第 118-125 行：函数先合并 testlist 条目里的 `sim_opts` 和 CLI 传入的 `cli_sim_opts`。
* 第 127-132 行：`cosim` 字段默认是 `enabled`，随后检查已经合并的字符串里是否存在
  `+enable_cosim=` 或 `+disable_cosim=`。

关键代码（`run_regress.py:L130-L140`）：

.. code-block:: python

       has_cosim_plusarg = (
           "+enable_cosim=" in joined or
           "+disable_cosim=" in joined
       )
       if not has_cosim_plusarg:
           if cosim in ("disabled", "disable", "false", "0", "no", "rtl_only"):
               pieces.append("+disable_cosim=1")
           else:
               pieces.append("+enable_cosim=1")

       return " ".join(piece for piece in pieces if piece).strip()

逐段解释：

* 第 130-134 行：如果已有 cosim plusarg，函数不会再追加第二个开关。
* 第 135-138 行：当 `cosim` 字段等于 disabled/false/0/no/rtl_only 之一时追加
  `+disable_cosim=1`，否则追加 `+enable_cosim=1`。
* 第 140 行：最终返回由空格连接的仿真 plusarg 字符串。

接口关系：

* 被调用：`run_single_test()` 构造仿真命令时使用。
* 调用：无外部命令。
* 共享状态：testlist 条目的 `sim_opts`、`cosim` 字段和 CLI `--sim-opts`。

§7  sign-off dry-run
---------------------

`signoff.py --dry-run` 用于查看 profile 会展开哪些 stage 命令。它不会运行 stage，
也不会执行 gate。

关键代码（`README.md:L363-L367`）：

.. code-block:: bash

   Run sign-off dry plan:

   ```bash
   python3 dv/uvm/core_eh2/scripts/signoff.py --profile full --dry-run
   ```

逐段解释：

* 第 363-367 行：README 给出 full profile dry-run 的直接 Python 调用。
* 该示例适合查看 `full` profile 的 stage 命令，不需要先准备所有 stage 输出。

关键代码（`signoff.py:L1472-L1485`）：

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

* 第 1472-1479 行：parser 接受 `--profile`、`--stages`、`--output` 和
  `--stage-result`。
* 第 1482-1483 行：`--dry-run` 的 help 明确说明它只打印 planned commands，
  不运行或 gating。

关键代码（`signoff.py:L1570-L1580`）：

.. code-block:: python

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

逐段解释：

* 第 1570-1573 行：driver 先为每个 stage 构造计划命令和输出目录。
* 第 1575-1580 行：`args.dry_run` 为真时，只打印 profile、stage 列表和每条命令，
  然后返回 0。

接口关系：

* 被调用：人工检查 sign-off 展开计划。
* 调用：`build_stage_cmd()`、`_cmd_str()`。
* 共享状态：`PROFILE_STAGES`、CLI 参数、默认输出目录。

§8  waiver 校验
----------------

cosim-disabled waiver 可以单独校验。这个示例直接调用 `signoff.py --validate-waivers`，
不会启动 sign-off stage。

关键代码（`README.md:L381-L386`）：

.. code-block:: bash

   Validate cosim-disabled waivers:

   ```bash
   python3 dv/uvm/core_eh2/scripts/signoff.py \
     --validate-waivers dv/uvm/core_eh2/waivers/cosim-disabled.yaml
   ```

逐段解释：

* 第 381-385 行：README 指向当前 waiver 文件
  `dv/uvm/core_eh2/waivers/cosim-disabled.yaml`。
* 该命令适合在修改 waiver YAML 后单独验证 schema。

关键代码（`signoff.py:L1536-L1558`）：

.. code-block:: python

       parser.add_argument("--validate-waivers", type=str, default="",
                           help="Validate waiver YAML schema and exit")
       args = parser.parse_args(argv)
       if args.max_iter_per_test:
           args.iterations = args.max_iter_per_test

       if args.validate_waivers:
           waiver_p = Path(args.validate_waivers)
           if not waiver_p.exists():
               print("ERROR: waiver file not found: {}".format(waiver_p))
               return 1

逐段解释：

* 第 1536-1538 行：CLI 参数名是 `--validate-waivers`。
* 第 1542-1546 行：如果传了 waiver 路径，driver 先检查文件是否存在；不存在返回 1。

关键代码（`signoff.py:L1547-L1558`）：

.. code-block:: python

           valid, errors = validate_waiver_schema(waiver_p)
           if errors:
               print("Schema validation FAILED for {}:".format(waiver_p))
               for err in errors:
                   print("  - {}".format(err))
               return 1
           print("Schema validation PASSED for {}".format(waiver_p))
           waived = load_waiver_set(waiver_p)
           print("Loaded {} waived entries".format(len(waived)))
           for w in sorted(waived):
               print("  - {}".format(w))
           return 0

逐段解释：

* 第 1547-1552 行：schema 有错误时逐条打印错误并返回 1。
* 第 1553-1558 行：schema 通过后打印 waiver 数量和条目，然后返回 0。

接口关系：

* 被调用：waiver YAML 修改后的快速检查。
* 调用：`validate_waiver_schema()`、`load_waiver_set()`。
* 共享状态：`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`。

§9  synthesis 和 LEC 示例
--------------------------

README 中仍展示 `make synth` 和 `make block_lec`。当前顶层 Makefile 保留
`block_lec` 作为 deprecated alias，并把推荐入口改为 `make synth STEP=block_lec`。

关键代码（`README.md:L369-L379`）：

.. code-block:: bash

   Run the full synthesis and LEC flow:

   ```bash
   make synth
   ```

   Run block-level LEC:

   ```bash
   make block_lec
   ```

逐段解释：

* 第 369-373 行：`make synth` 是 README 中的 full synthesis/LEC 示例。
* 第 375-379 行：`make block_lec` 仍能运行，但当前 Makefile 把它标为旧入口并转发。

关键代码（`Makefile:L1082-L1128`）：

.. code-block:: makefile

   signoff_gate:
   	@echo "[deprecated] 'make signoff_gate' → 'make signoff GATE_ONLY=1 SIGNOFF_OUT=$(SIGNOFF_OUT)'"
   	@$(MAKE) --no-print-directory signoff GATE_ONLY=1 SIGNOFF_OUT=$(SIGNOFF_OUT)

   signoff_with_cleanup:
   	@echo "[deprecated] 'make signoff_with_cleanup' → 'make signoff CLEANUP=1'"
   	@$(MAKE) --no-print-directory signoff CLEANUP=1

   html_report:
   	@echo "[deprecated] 'make html_report' → 已合并进 signoff target；如需单跑："

逐段解释：

* 第 1082-1088 行：sign-off 旧入口都转发到 `make signoff` 的变量形式。
* 第 1090-1099 行：`html_report` 和 `cov` 也标记为 deprecated，其中 coverage 合并已并入
  sign-off 的 `COV=1` 路径。

关键代码（`Makefile:L1114-L1128`）：

.. code-block:: makefile

   syn_yosys:
   	@echo "[deprecated] 'make syn_yosys' → 'make synth TOOL=yosys'"
   	@$(MAKE) --no-print-directory synth TOOL=yosys

   syn_dc:
   	@echo "[deprecated] 'make syn_dc' → 'make synth TOOL=dc STEP=synth'"
   	@$(MAKE) --no-print-directory synth TOOL=dc STEP=synth

   lec:
   	@echo "[deprecated] 'make lec' → 'make synth STEP=lec'"
   	@$(MAKE) --no-print-directory synth STEP=lec

   block_lec:
   	@echo "[deprecated] 'make block_lec' → 'make synth STEP=block_lec'"

逐段解释：

* 第 1114-1120 行：`syn_yosys` 和 `syn_dc` 分别转成 `make synth TOOL=yosys`
  与 `make synth TOOL=dc STEP=synth`。
* 第 1122-1128 行：`lec` 和 `block_lec` 分别转成 `make synth STEP=lec` 与
  `make synth STEP=block_lec`。

当前推荐示例：

.. code-block:: bash

   make synth
   make synth STEP=block_lec
   make synth STEP=lec
   make synth TOOL=yosys

逐段解释：

* 第 1 行：默认 `make synth` 走 DC 综合加 block-level LEC。
* 第 2 行：只跑 block-level LEC，替代旧 `make block_lec`。
* 第 3 行：只跑顶层 yosys equiv LEC，替代旧 `make lec`。
* 第 4 行：显式运行 Yosys synthesis；该路径在 ADR-0013 中记录为已知受限路径。

接口关系：

* 被调用：综合/LEC 调试、release 自检。
* 调用：顶层 `make synth`、`syn/Makefile`。
* 共享状态：`syn/build/`、`syn/build/lec_summary.txt`。

§10  coverage 示例边界
-----------------------

旧示例中的独立覆盖率合并 target 在当前顶层 Makefile 中不存在。当前 Makefile 保留
`make cov` 作为 deprecated alias，并说明 sign-off `COV=1` 时会自动合并。

关键代码（`Makefile:L1090-L1104`）：

.. code-block:: makefile

   html_report:
   	@echo "[deprecated] 'make html_report' → 已合并进 signoff target；如需单跑："
   	python3 $(SCRIPTS_DIR)/gen_html_report.py \
   	  --signoff-status $(SIGNOFF_OUT)/signoff_status.json \
    --coverage-dashboard $(SIGNOFF_OUT)/cov_merged/dashboard.txt \
   	  --runs-dir $(SIGNOFF_OUT)/runs \
   	  --output $(SIGNOFF_OUT)/report.html

   cov:
   	@echo "[deprecated] 'make cov' → signoff COV=1 时自动合并；如需单独合并："

逐段解释：

* 第 1090-1096 行：HTML 报告已并入 sign-off target；单跑时仍可直接调用
  `gen_html_report.py`。
* 第 1098-1099 行：`make cov` 被标记为 deprecated，提示 coverage 合并由
  sign-off `COV=1` 自动处理。

关键代码（`Makefile:L1098-L1104`）：

.. code-block:: makefile

   cov:
   	@echo "[deprecated] 'make cov' → signoff COV=1 时自动合并；如需单独合并："
   	@if [ "$(SIMULATOR)" = "vcs" ]; then \
   	  urg -dir $(BUILD_DIR)/cov/simv.vdb -report $(BUILD_DIR)/cov_report; \
   	elif [ "$(SIMULATOR)" = "xlm" ]; then \
   	  imc -load $(BUILD_DIR)/cov -exec $(TB_DIR)/cov_merge.tcl; \
   	fi

逐段解释：

* 第 1098-1101 行：VCS coverage 单独合并时调用 `urg`，输入是
  `build/cov/simv.vdb`，输出是 `build/cov_report`。
* 第 1102-1104 行：Xcelium coverage 单独合并时调用 `imc` 和 `cov_merge.tcl`。
* 本章示例不推荐新增独立覆盖率合并 target，因为当前顶层 Makefile 没有该 target。

当前推荐示例：

.. code-block:: bash

   make compile COV=1
   make signoff PROFILE=quick COV=1 SIGNOFF_OUT=build/signoff_quick_cov

逐段解释：

* 第 1 行：带覆盖率编译 testbench。
* 第 2 行：让 sign-off driver 处理 coverage gate 和报告输出；这是当前 Makefile 对
  coverage 示例的推荐方向。

接口关系：

* 被调用：覆盖率调试和签核。
* 调用：`urg`、`imc`、`gen_html_report.py`、`signoff.py`。
* 共享状态：`build/cov/`、`build/cov_report/`、`SIGNOFF_OUT/cov_merged`。

§11  参考资料
---------------

* 关联章节：:ref:`getting_started`、:ref:`build_flow`、:ref:`regression_flow`、
  :ref:`signoff_flow`、:ref:`scripts_reference`、:ref:`synthesis_flow`、
  :ref:`lec_flow`。
* 关联 ADR：:ref:`adr-0013`、:ref:`adr-0018`、:ref:`adr-0020`。
* 源文件绝对路径：

  * `/home/host/eh2-veri/README.md`
  * `/home/host/eh2-veri/Makefile`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
