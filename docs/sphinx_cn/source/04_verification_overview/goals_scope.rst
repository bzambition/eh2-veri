.. _goals_scope:
.. _04_verification_overview/goals_scope:

验证目标与范围
==============

:status: draft
:source: docs/PROJECT_STATUS.md; Makefile; dv/uvm/core_eh2/scripts/signoff.py; eh2_configs.yaml; dv/uvm/core_eh2/directed_tests/directed_testlist.yaml; dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml; dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml; dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章边界
-------------

本章只定义 EH2-Veri 当前主线的验证目标、已纳入 sign-off 的范围、当前配置覆盖边界和不覆盖范围。
所有数字来自当前仓库中的 status 文档、gate 脚本和 2026-05-19 01:02
VCS 主线 demo 实测摘要，不能用旧审计记录或未来目标替代。
尤其注意三点：

* 当前 demo 时间是 `2026-05-19 01:02`。
* 当前 sign-off 变量是 `PROFILE`，覆盖率门限默认是 line `65`、group/covergroup
  `40`；脚本参数名为了兼容旧调用仍保留 `SIGNOFF_MIN_FUNCTIONAL_COV`。
* 当前 `eh2_configs.yaml` 只有 `default`、`minimal`、`dual_thread`、`ahb_lite` 四个 profile；
  不存在旧文档中的 8 个 profile 集合。

.. code-block:: bash

   当前 sign-off scope
       |
       +-- dynamic simulation: smoke / directed / cosim / riscvdv / compliance / csr_unit
       +-- static/tool gates: lint / formal / syn
       +-- coverage gates: line >= 65, group >= 40
       +-- evidence summary: 2026-05-19 VCS demo + signoff.py artifacts

逐段解释：

* 第 1-4 行：本章把验证目标拆成动态仿真、静态/工具 gate、coverage gate 和 evidence summary。
* 2026-05-19 VCS demo 是本章引用当前 pass rate、coverage 和 LEC 数字的主要来源；
  `signoff.py`、Makefile 和 testlist 源码用于解释这些数字如何进入 gate。

接口关系：

* 被调用：验证计划评审、release 范围确认、用户验收抽检。
* 调用：:ref:`signoff_flow`、:ref:`regression_flow`、:ref:`coverage_plan`、
  :ref:`functional_coverage`、:ref:`appendix_e_config/eh2_configs`。
* 共享状态：status 表、Makefile gate 变量、YAML testlist、coverage interface。

§2  当前 sign-off 目标
----------------------

当前目标不是“列出 EH2 所有可能功能”，而是在当前验证平台中形成可复演的 sign-off
门禁。当前 VCS 主线 demo 已在 2026-05-19 01:02 完成 9/9 stage PASS，且 LEC
为 31635/31635 PASS。

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

* 第 1-4 行：full profile 顶层状态为 PASS，9 个 stage 全部通过，LEC compare point
  全部等价。
* 第 6-9 行：动态与工具 stage 的核心实测数字分别是 riscv-dv 370/395、
  compliance 85/88、directed 40/40 和 formal 46/46。
* smoke、cosim、lint、csr_unit 和 syn 仍属于 9 stage sign-off；本节只列出用户最常
  复核的签核可见数字，逐 stage gate 由 :ref:`signoff_flow` 展开。

接口关系：

* 被调用：sign-off 报告、状态记录、验收门。
* 调用：无脚本调用；该表是汇总证据。
* 共享状态：`build/demo/signoff_status.json`、`build/demo/runs/*`、
  `dv/formal/build/ifv_final.log`、`syn/build/lec_summary.txt`。

§3  覆盖率目标与签核数字
------------------------------

当前 Makefile 的 coverage gate 和签核 coverage result 是两类不同数字：
gate 是 sign-off 判断门限，签核 result 是已达成的覆盖率。文档必须同时保留二者差异。

关键代码（`Makefile:L148-L151`）：

.. code-block:: makefile

   # 当前 release 门限（修过——旧 Makefile 写死 85/50 与当前 release 不符）
   SIGNOFF_MIN_LINE_COV       ?= 65
   SIGNOFF_MIN_FUNCTIONAL_COV ?= 40
   SIGNOFF_ALLOW_WARNINGS     ?= 1

逐段解释：

* 第 L148 行：注释说明旧 Makefile 曾写死 85/50，但当前 release 不采用该门限。
* 第 L149-L150 行：line coverage gate 是 `65`，group/covergroup gate 通过历史参数名
  `SIGNOFF_MIN_FUNCTIONAL_COV` 表示为 `40`。
* 第 L151 行：`SIGNOFF_ALLOW_WARNINGS ?= 1` 表示默认允许 warning，不把 warning 本身作为失败条件。

实测覆盖率摘要（`core_eh2_tb_top.dut`，URG 原生 dashboard）：

.. code-block:: text

   LINE     95.05%
   BRANCH   84.97%
   TOGGLE   53.52%
   ASSERT   33.33%
   FSM      54.74%
   GROUP    69.42%
   OVERALL  65.17%

逐段解释：

* 第 1-2 行：line 与 branch 是当前覆盖率收敛最强的结构指标。
* 第 3-5 行：toggle、assert 和 FSM 仍是后续 directed/formal 增强的主要增长空间。
* 第 6-7 行：group 来自功能覆盖率采样，overall 是 URG dashboard 的综合得分。

接口关系：

* 被调用：coverage gate、status 记录、HTML report。
* 调用：`signoff.py:evaluate_coverage()` 解析 coverage report 文本。
* 共享状态：`SIGNOFF_MIN_LINE_COV`、`SIGNOFF_MIN_FUNCTIONAL_COV`、coverage dashboard。

§4  sign-off profile 与 stage 边界
-----------------------------------

`signoff.py` 直接定义 profile 到 stage list 的映射。验证范围以这些 stage 为准，而不是旧文档
中的“6 层金字塔”口径。

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

* 第 L37-L44 行：`quick` 只包含 `smoke` 和 `directed`；`full` 包含 9 个 stage。
* 第 L46-L53 行：`STAGE_MIN_PASSED` 记录最小通过数门限。release 实际数字可以高于门限，
  例如 directed release 是 40/40，而最小门限是 33。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L112-L120`）：

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

* 第 L112-L113 行：如果命令行提供 `--stages`，它覆盖 profile 默认 stage list；
  否则使用 `PROFILE_STAGES[profile]`。
* 第 L114-L120 行：允许的 stage 名称被硬编码为 9 个；未知 stage 会抛出 `ValueError`。

接口关系：

* 被调用：`signoff.py:main()`。
* 调用：`_split_csv()` 和 `PROFILE_STAGES`。
* 共享状态：`args.profile`、`args.stages`、stage result list。

§5  sign-off precheck 范围
---------------------------

precheck 的范围来自脚本：它检查 EH2 root、RTL/TB filelist、仿真器或 `build/simv`，
并按 stage 条件检查 RISC-V GCC、riscv-dv、Spike DPI 等工具或产物。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L152-L180`）：

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

逐段解释：

* 第 L152-L160 行：precheck 始终检查仓库根、RTL filelist 和 TB filelist。
* 第 L162-L165 行：仿真器检查允许两条路径：已有 `build/simv`，或者系统中存在对应工具。
* 第 L167-L170 行：directed、cosim、riscv-dv stage 需要 RISC-V GCC 和 objcopy；
  这里只展示 GCC，后续行继续检查 objcopy。
* 第 L173-L180 行在源码中继续检查 riscv-dv 和 `build/libcosim.so`，这些检查只在相关 stage 出现时启用。

接口关系：

* 被调用：`signoff.py:main()`，除非传 `--skip-precheck`。
* 调用：`resolve_gcc_prefix()`、`tool_exists()`。
* 共享状态：stage list、`build/simv`、`build/libcosim.so`、toolchain path。

§6  配置覆盖范围
-----------------

配置覆盖范围以 `eh2_configs.yaml` 为准。当前文件只有 4 个 profile：`default`、
`minimal`、`dual_thread`、`ahb_lite`。旧文档列出的 `2thread`、`no_icache`、
`no_dccm`、`fpga`、`no_pmp`、`full` 不在当前 YAML 中。

关键代码（`eh2_configs.yaml:L5-L38`）：

.. code-block:: yaml

   default:
     description: "Default EH2 configuration (AXI4, single-thread, full features)"
     parameters:
       # Threading
       NUM_THREADS: 1
       # Bus
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0
       BUILD_AXI_NATIVE: 1
       LSU_BUS_TAG: 4
       IFU_BUS_TAG: 4
       SB_BUS_TAG: 1
       DMA_BUS_TAG: 1
       # DCCM
       DCCM_ENABLE: 1
       DCCM_SIZE: 64
       # ICCM
       ICCM_ENABLE: 1
       ICCM_SIZE: 64

逐段解释：

* 第 L5-L7 行：`default` 是 AXI4、single-thread、full features profile。
* 第 L8-L17 行：threading 与 bus 参数包括 `NUM_THREADS: 1`、`BUILD_AXI4: 1`、
  `BUILD_AHB_LITE: 0` 和各 AXI tag width。
* 第 L18-L23 行：DCCM 与 ICCM 默认启用，size 均为 `64`。

关键代码（`eh2_configs.yaml:L40-L94`，节选）：

.. code-block:: yaml

   minimal:
     description: "Minimal EH2 configuration (no ICache, no DCCM, few interrupts)"
     parameters:
       NUM_THREADS: 1
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0
       DCCM_ENABLE: 0
       ICCM_ENABLE: 0
       ICACHE_ENABLE: 0

   dual_thread:
     description: "Dual-thread EH2 configuration"
     parameters:
       NUM_THREADS: 2
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0

   ahb_lite:
     description: "AHB-Lite bus configuration"
     parameters:
       NUM_THREADS: 1
       BUILD_AXI4: 0
       BUILD_AHB_LITE: 1

逐段解释：

* 第 L40-L49 行：`minimal` 关闭 DCCM、ICCM、ICache，并保留 AXI4。
* 第 L58-L63 行：`dual_thread` 把 `NUM_THREADS` 设为 2，并仍使用 AXI4。
* 第 L77-L83 行：`ahb_lite` 把 `BUILD_AXI4` 设为 0，把 `BUILD_AHB_LITE` 设为 1。

接口关系：

* 被调用：metadata/config 渲染路径、配置章节、staged flow。
* 调用：YAML 本身不调用代码。
* 共享状态：`CONFIG=<profile>`、metadata 中的 `eh2_config`、riscv-dv setting 渲染。

§7  directed 测试范围
----------------------

directed 测试由 `directed_testlist.yaml` 组织。当前列表先定义 config block，再列出
smoke、ALU、load/store、IRQ、PMP、dual-issue、NB-load、AXI4 error、debug、coverage pump
等 test entries。sign-off release 记录 directed 40/40。

关键代码（`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L25-L43`）：

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

   - test: directed_load_store
     desc: "Deterministic load/store directed test"
     config: eh2_directed
     test_srcs: tests/asm/cosim_load_store.S
     iterations: 1

   - test: directed_irq_basic

逐段解释：

* 第 L25-L35 行：smoke 和 ALU directed tests 复用 `cosim_smoke.S` 与 `cosim_alu.S`，
  但通过 directed pipeline 运行。
* 第 L37-L43 行：load/store 与 IRQ basic 进入同一 directed list，均使用
  `eh2_directed` config。

关键代码（`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L69-L87`）：

.. code-block:: yaml

   - test: directed_nb_load_chain
     desc: "Three consecutive NB-loads + dependent branch (RISK-5)"
     config: eh2_directed
     test_srcs: tests/asm/directed_nb_load_chain.S
     iterations: 1

   - test: directed_axi4_error_inject
     desc: "AXI4 SLVERR/DECERR injection triggers load access fault"
     config: eh2_directed
     test_srcs: tests/asm/directed_axi4_error_inject.S
     cosim: disabled
     sim_opts: '+enable_axi4_error_inject=1 +axi4_error_pct=100'
     iterations: 1

   - test: directed_illegal_instr
     desc: "Illegal instruction exception handling"
     config: eh2_directed
     test_srcs: tests/asm/directed_illegal_instr.S
     iterations: 1

逐段解释：

* 第 L69-L73 行：NB-load directed test 直接覆盖 `NB-load` 风险路径。
* 第 L75-L81 行：AXI4 error injection test 显式 `cosim: disabled`，并用 plusargs 打开
  AXI4 error injection。
* 第 L83-L87 行：illegal instruction handling 作为 directed exception 路径进入列表。

关键代码（`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L222-L245`）：

.. code-block:: yaml

   # Coverage pump directed tests (Task-D)

   - test: directed_pic_state_walk
     desc: "PIC/trap claim-complete state stimulus with IRQ sideband"
     config: eh2_directed_pic
     test_srcs: tests/asm/directed_pic_state_walk.S
     sim_opts: '+enable_irq_seq=1 +enable_irq_single_seq=1 +max_interval=20'
     cosim: disabled
     iterations: 1

   - test: directed_dbg_dret_walk
     desc: "Debug halt/resume and breakpoint trap stimulus"
     config: eh2_directed
     test_srcs: tests/asm/directed_dbg_dret_walk.S
     sim_opts: '+enable_debug_seq=1 +enable_debug_single=1 +max_interval=20'
     cosim: disabled
     iterations: 1

逐段解释：

* 第 L222-L230 行：coverage pump 中的 PIC test 使用 IRQ sideband plusargs，并关闭 cosim。
* 第 L232-L238 行：debug dret walk 使用 debug sequence plusargs，也关闭 cosim。
* 第 L240-L245 行：DMA burst 继续作为 coverage pump entry，刺激 DMA/AXI memory path。

接口关系：

* 被调用：`make regress TESTLIST=directed`、`signoff.py` directed stage。
* 调用：ASM test、UVM `rtl_test`、plusargs。
* 共享状态：`directed_testlist.yaml`、`tests/asm/*.S`、cosim waiver/gate。

§8  cosim proof 测试范围
-------------------------

cosim proof list 由 7 个测试组成，status 记录中 cosim 为 7/7。该列表使用
`core_eh2_cosim_test`，并以 Spike lockstep 为目标。

关键代码（`dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml:L1-L16`）：

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

* 第 L1-L3 行：注释说明这些是 framework proof points，并通过 `core_eh2_cosim_test`
  启用 Spike lockstep。
* 第 L5-L10 行：`eh2_cosim` config 定义 UVM test、timeout、GCC options、linker 和 include。
* 第 L12-L16 行：`cosim_smoke` 覆盖初始化、binary load、第一步 Spike step 和 mailbox PASS。

关键代码（`dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml:L18-L53`，节选）：

.. code-block:: yaml

   - test: cosim_alu
     desc: "Register writeback correlation for deterministic ALU instructions"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_alu.S
     iterations: 1

   - test: cosim_load_store
     desc: "LSU AXI memory notification path for deterministic loads/stores"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_load_store.S
     iterations: 1

   - test: cosim_dual_issue
     desc: "Program-order lockstep for EH2 dual-issue retire traces"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_dual_issue.S
     iterations: 1

逐段解释：

* 第 L18-L22 行：ALU cosim proof 聚焦寄存器写回关联。
* 第 L24-L28 行：load/store proof 聚焦 LSU AXI memory notification path。
* 第 L30-L34 行：dual-issue proof 聚焦 EH2 双发射 retire trace 的 program-order lockstep。
* 后续同一 YAML 还包含 bitmanip、exception compare 和 atomic basic proof。

接口关系：

* 被调用：`make regress TESTLIST=cosim`、`signoff.py` cosim stage。
* 调用：`core_eh2_cosim_test`、Spike DPI、ASM tests。
* 共享状态：cosim scoreboard、trace pkt、AXI memory notification、mailbox。

§9  riscv-dv 随机范围与 waiver 边界
------------------------------------

riscv-dv extension testlist 定义随机和混合 directed proof。当前签核数字为
riscv-dv 370/395。部分条目可以标记 `cosim: disabled` 或 `cosim: rtl_only`，这些条目
必须经过 waiver 文件和 sign-off gate 检查。

关键代码（`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L1-L19`）：

.. code-block:: yaml

   - test: riscv_arithmetic_basic_test
     description: Basic arithmetic instruction test
     gen_test: riscv_instr_base_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +no_csr_instr=1

       '
     rtl_test: core_eh2_base_test
     iterations: 10
   - test: riscv_random_instr_test
     description: Random instruction mix test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=20000 +boot_mode=m +enable_interrupt=1 +enable_nested_interrupt=1

       '
     rtl_test: core_eh2_base_test

逐段解释：

* 第 L1-L8 行：arithmetic basic 使用 `riscv_instr_base_test`，指令数 10000，
  boot mode 为 M-mode，并关闭 CSR 指令。
* 第 L9-L19 行：random instruction mix 使用 `riscv_rand_instr_test`，打开 interrupt
  与 nested interrupt。

关键代码（`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L28-L37`）：

.. code-block:: yaml

   - test: riscv_csr_test
     description: CSR read/write test
     gen_test: riscv_instr_base_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_csr_write=1 +directed_instr_0=eh2_csr_access_stream,10

       '
     rtl_test: core_eh2_base_test
     cosim: disabled
     iterations: 5
     skip_in_signoff: true

逐段解释：

* 第 L28-L34 行：CSR read/write test 使用 CSR write 和 `eh2_csr_access_stream`。
* 第 L35-L37 行：该条目标记 `cosim: disabled` 且 `skip_in_signoff: true`。
  sign-off gate 会收集这些例外并要求 waiver 覆盖。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L1063-L1097`）：

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

逐段解释：

* 第 L1063-L1070 行：脚本读取 riscv-dv extension testlist；文件缺失或解析失败时返回空列表。
* 第 L1071-L1079 行：`disabled`、`disable`、`0`、`false`、`no`、`rtl_only`
  都被视为 cosim exception。
* `collect_skip_in_signoff()` 在同一文件第 L1082-L1097 行收集 `skip_in_signoff` entries。

接口关系：

* 被调用：`make regress TESTLIST=riscvdv`、`signoff.py` riscvdv stage、waiver gate。
* 调用：riscv-dv generator、directed streams、UVM tests。
* 共享状态：`testlist.yaml`、`cosim-disabled.yaml`、`skip_in_signoff` gate。

§10  功能覆盖模型范围
----------------------

功能覆盖范围来自 `eh2_fcov_if.sv`。该 interface 观察流水线 valid、decode packet、branch、
flush、stall、exception、interrupt、debug、LSU 和 ICache PMU signals，然后定义多个
covergroup 和 cross。

关键代码（`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L13-L36`）：

.. code-block:: systemverilog

   interface eh2_fcov_if
     import eh2_pkg::*;
   (
     input logic clk_i,
     input logic rst_l_i,

     // -- Pipeline stage valids --
     input logic        dec_ib0_valid_d,
     input logic        dec_ib1_valid_d,
     input logic        dec_i1_valid_e1,
     input logic        dec_tlu_i0_valid_e4,
     input logic        dec_tlu_i1_valid_e4,
     input logic        tlu_i0_commit_cmt,
     input logic        tlu_i1_commit_cmt,

     // -- Instruction at decode --
     input logic [31:0] dec_i0_instr_d,
     input logic [31:0] dec_i1_instr_d,
     input logic        dec_i0_pc4_d,
     input logic        dec_i1_pc4_d,

     // -- Decode packet --
     input eh2_dec_pkt_t i0_dec,
     input eh2_dec_pkt_t i1_dec,

逐段解释：

* 第 L13-L17 行：coverage interface 接收 clock/reset，并导入 `eh2_pkg`。
* 第 L19-L26 行：pipeline valid 和 commit signals 覆盖 i0/i1、decode/E4/CMT 等阶段。
* 第 L28-L36 行：decode instruction 和 `eh2_dec_pkt_t` 让 coverage model 可以按指令类别分类。

关键代码（`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L212-L253`，节选）：

.. code-block:: systemverilog

   covergroup uarch_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "uarch_cg";

     // -----------------------------------------------------------------------
     // Instruction categories at decode
     // -----------------------------------------------------------------------
     cp_i0_instr_category: coverpoint get_i0_instr_category() {
       bins alu         = {InstrCategoryALU};
       bins mul         = {InstrCategoryMul};
       bins div         = {InstrCategoryDiv};
       bins branch      = {InstrCategoryBranch};
       bins jump        = {InstrCategoryJump};
       bins load        = {InstrCategoryLoad};
       bins store       = {InstrCategoryStore};
       bins csr_access  = {InstrCategoryCSRAccess};
       bins ebreak      = {InstrCategoryEBreak};

逐段解释：

* 第 L212-L214 行：`uarch_cg` 是主微架构 covergroup，按 `clk_i` 采样并设置实例名。
* 第 L219-L235 行：i0 instruction category 覆盖 ALU、mul、div、branch、jump、
  load、store、CSR、ebreak、ecall、mret、fence、atomic、illegal 等类别。
* 第 L237-L253 行：i1 instruction category 使用同样类别，覆盖双发射第二 slot。

关键代码（`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L386-L414`）：

.. code-block:: systemverilog

     // -----------------------------------------------------------------------
     // Crosses
     // -----------------------------------------------------------------------

     // Instruction category x stall type
     stall_cross: cross cp_i0_instr_category, cp_stall_type {
       ignore_bins illegal_stall = binsof(cp_i0_instr_category.illegal);
     }

     // Branch taken x mispredict
     branch_cross: cross cp_i0_branch_taken, cp_i0_branch_mispredict;

     // Interrupt x debug mode
     interrupt_debug_cross: cross cp_interrupt_taken, cp_debug_mode;

     // Dual-issue x I0 category
     dual_issue_cross: cross cp_dual_issue, cp_i0_instr_category;

     // Exception x stall
     exception_stall_cross: cross cp_exception_type, cp_stall_type;

逐段解释：

* 第 L386-L393 行：stall cross 把 i0 instruction category 与 stall type 交叉，
  并忽略 illegal instruction stall bin。
* 第 L395-L405 行：branch、interrupt/debug、dual issue 和 exception/stall 都有显式 cross。
* 第 L407-L414 行：同一段后续还包含 i0/i1 instruction category cross 和 compressed dual issue cross。

接口关系：

* 被调用：`core_eh2_tb_top.sv` 实例化 coverage interface。
* 调用：`get_i0_instr_category()`、`get_i1_instr_category()`、`get_stall_type()`。
* 共享状态：coverage database、`+enable_eh2_fcov=1`、VCS URG dashboard。

§11  formal 与 LEC 范围
------------------------

formal stage 的 sign-off collector 解析 IFV assertion summary；syn stage 可使用
block-level LEC summary。status 记录 formal 46/46 和 syn 31635/31635。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L520-L583`，节选）：

.. code-block:: python

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

逐段解释：

* 第 L522-L528 行：formal collector 在 `dv/formal/build` 下寻找 IFV 相关日志，并取最新一个。
* 第 L529-L535 行：如果找到日志，脚本读取文本，准备解析 assertion summary。
* 第 L546-L552 行在源码后续把 `Total`、`Pass`、`Fail`、`Not_Run` 等字段写入 stage result。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L595-L621`）：

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

逐段解释：

* 第 L595-L599 行：LEC parser 读取 `syn/build/lec_summary.txt`，并准备 per-module 与 total 数据。
* 第 L600-L605 行：只处理 Markdown table 行，跳过表头和分隔行。
* 第 L606-L613 行：把 passing、failing、unverified 和 status 解析成结构化字段。
* 第 L617-L621 行在源码后续把 `TOTAL` 行和各模块行分开保存。

接口关系：

* 被调用：`collect_formal_stage()`、`collect_syn_stage()`。
* 调用：文件系统 glob、IFV log parser、LEC summary parser。
* 共享状态：`dv/formal/build/*.log`、`syn/build/lec_summary.txt`、sign-off stage result。

§12  明确不覆盖范围
--------------------

以下项目不属于当前 EH2-Veri 主线 sign-off 范围；这些边界来自源码缺口或当前 stage 列表，
不是对 EH2 core 能力的否定。

.. list-table::
   :header-rows: 1
   :widths: 30 35 35

   * - 不覆盖项
     - 当前证据
     - 文档结论
   * - 物理实现验证
     - sign-off stage 只有 `smoke`、`directed`、`cosim`、`riscvdv`、`lint`、`csr_unit`、`compliance`、`formal`、`syn`
     - 不声明 DRC、LVS、IR-drop、EM、timing closure。
   * - 功耗和性能 corner
     - Makefile/signoff.py 没有 power/fmax stage
     - 不声明功耗、电压 scaling 或 PVT 性能签核。
   * - U-mode/S-mode
     - riscv-dv gen opts 多处使用 `+boot_mode=m`
     - 当前验证目标聚焦 M-mode。
   * - 多核 coherency
     - `NUM_THREADS` profile 支持 1/2，术语为 thread
     - 不声明多核 cluster cache coherency。
   * - 完整 AXI VIP 压力
     - 当前 bus 策略见 :ref:`adr-0002`
     - 不把 passive monitoring 写成通用 AXI4 VIP。
   * - 全 profile sign-off
     - status 记录的是当前 sign-off 数字
     - 不声明四个 `eh2_configs.yaml` profile 都完成 full sign-off。

接口关系：

* 被调用：scope review、risk review、状态记录。
* 调用：sign-off stage list 和 Makefile target 定义。
* 共享状态：无运行时状态；只限定文档结论。

§13  参考资料
--------------

关联 ADR：

* :ref:`adr-0002` — AXI4 passive monitoring 与 behavioral memory 策略。
* :ref:`adr-0004` — RTL trace 增加 verification-only retire 字段。
* :ref:`adr-0011` — compliance framework。
* :ref:`adr-0012` — formal verification strategy。
* :ref:`adr-0013` — synthesis toolchain。
* :ref:`adr-0014` — formal real runs。
* :ref:`adr-0015` — RVFI adapter layer。
* :ref:`adr-0016` — multi-hart cosim。
* :ref:`adr-0020` — block-level LEC closure。

关联章节：

* :ref:`targets` — 当前指标仪表盘。
* :ref:`regression_flow` — smoke、directed、cosim、riscv-dv 回归入口。
* :ref:`signoff_flow` — sign-off stage、gate-only、coverage gate。
* :ref:`functional_coverage` — coverage interface 和 covergroup 说明。
* :ref:`coverage_plan` — coverage 规划与现状。
* :ref:`formal_flow` — IFV formal flow。
* :ref:`lec_flow` — block-level LEC flow。
* :ref:`compliance_flow` — RISC-V compliance flow。
* :ref:`appendix_e_config/eh2_configs` — EH2 profile 字典。

源文件绝对路径：

* :file:`/home/host/eh2-veri/docs/PROJECT_STATUS.md`
* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* :file:`/home/host/eh2-veri/eh2_configs.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_if.sv`

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：把本页决策、风险或 coverage 计划追溯到 ADR 索引和 Sphinx 决策页。

.. code-block:: bash

   sed -n "1,120p" docs/adr/INDEX.md
   rg -n "ADR|waiver|LEC|coverage|cosim" docs/sphinx_cn/source/07_decisions docs/sphinx_cn/source/appendix_d_adr | head -80

**进阶题**：确认决策页没有回到旧 coverage 维度或旧 NC 口径。

.. code-block:: bash

   rg -n "line\+tgl\+assert\+fsm\+branch|31635/31635|95.05|NC/Incisive" docs/sphinx_cn/source/07_decisions docs/sphinx_cn/source/appendix_d_adr

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页的决策、风险或 coverage 结论依赖哪一条 ADR、脚本或 sign-off 证据？
2. 该结论是否区分当前事实、历史背景和未来工作？
3. 是否避免了旧 coverage 维度、旧 NC 口径和伪 dashboard 叙述？
4. 如果该决策被修改，最先需要同步哪些 Makefile、YAML、脚本或章节？
5. reviewer 能否从本页追到 2026-05-19 demo 的统一数字和 LEC 证据？
