.. _build_flow:
.. _06_flows/build_flow:

构建流程 — 详细参考
================================================================================

:status: draft
:source: Makefile; env.mk; dv/uvm/core_eh2/Makefile; dv/uvm/core_eh2/wrapper.mk; dv/uvm/core_eh2/scripts/compile_tb.py; dv/uvm/core_eh2/scripts/compile_test.py; dv/uvm/core_eh2/scripts/eh2_cmd.py; dv/uvm/core_eh2/scripts/scripts_lib.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  流程边界
--------------------------------------------------------------------------------

EH2 构建流程有两类入口，不能混写：

.. code-block:: text

   default Make path (GOAL empty)
      |
      |-- make compile SIMULATOR=vcs
      |     `-- compile_vcs -> build/simv
      |
      |-- make compile SIMULATOR=xlm
      |     `-- compile_xlm -> xrun compile database under build/
      |
      |-- make run TEST=<name> SEED=<seed>
      |     `-- compile + build/simv +UVM_TESTNAME=...
      |
      `-- make gen TEST=<name>
            `-- scripts/run_instr_gen.py
   
   Ibex-style staged path (GOAL non-empty)
      |
      |-- make run GOAL=<wrapper-target>
      |     |-- scripts/metadata.py --op create_metadata
      |     `-- make -C dv/uvm/core_eh2 --file wrapper.mk <GOAL>
      |
      `-- wrapper.mk
            |-- core_config
            |-- instr_gen_build / instr_gen_run
            |-- compile_riscvdv_tests / compile_directed_tests
            |-- rtl_tb_compile
            |-- rtl_sim_run
            |-- check_logs
            `-- collect_results

**逐段解释** ：

* 默认路径在顶层 :file:`Makefile` 的 ``else`` 分支中定义。这里的
  ``compile`` target 展开为 ``compile_$(SIMULATOR)``，当前源码中有
  ``compile_vcs`` 和 ``compile_xlm`` 两个直接 target。
* ``GOAL`` 非空时，顶层 :file:`Makefile` 只保留一个 ``run`` target。该 target
  先创建 regression metadata，再调用 :file:`dv/uvm/core_eh2/wrapper.mk` 中的
  staged target。
* :file:`dv/uvm/core_eh2/scripts/compile_tb.py` 支持 ``vcs``、``xlm``、
  ``questa`` 三个 simulator 分支，但这是 Python staged flow 的命令构造函数，
  不是顶层 :file:`Makefile` 中已经存在的 ``compile_questa`` target。
* ``NO_COSIM=1`` 只影响 VCS 直接编译路径中 ``libcosim.so`` 的依赖和链接；运行期
  cosim 开关由 ``RUN_COSIM_OPTS`` 生成 ``+disable_cosim=1`` 或
  ``+enable_cosim=1``。

**接口关系** ：

* **上游入口** ：命令行 ``make compile``、``make run``、``make run GOAL=...``、
  :file:`dv/uvm/core_eh2/Makefile` 的转发 target。
* **下游工具** ：VCS、Xcelium ``xrun``、Spike cosim C++ build、riscv-dv generator、
  RISC-V GCC/objcopy、Python regression scripts。
* **共享状态** ：默认输出目录为 :file:`build/`；staged flow 默认输出目录为
  :file:`out/` 下的 metadata、tests、build 和 run 子目录。

§2  顶层 Makefile 分支选择
--------------------------------------------------------------------------------

§2.1  文件头、环境 include 和 ``GOAL``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：顶层 :file:`Makefile` 先设置 shell、读取 :file:`env.mk`，再通过 ``GOAL``
是否为空选择执行分支。

**关键代码** （``Makefile:L25-L34``）：

.. code-block:: text

   SHELL := /bin/bash
   
   # Source environment
   -include env.mk
   
   # Ibex-style staged entry point. When GOAL is set, `make run GOAL=...` creates
   # regression metadata and delegates to dv/uvm/core_eh2/wrapper.mk.
   GOAL ?=
   
   ifneq ($(GOAL),)

**逐段解释** ：

* 第 25 行：Makefile shell 固定为 ``/bin/bash``。后续 ``PIPESTATUS``、条件展开和
  多行 shell 片段都依赖 Bash 行为。
* 第 28 行：``env.mk`` 是 soft include。文件不存在时不会中断 Make 解析。
* 第 30-L32 行：注释说明 ``GOAL`` 非空时，``make run GOAL=...`` 先创建 metadata，
  再委派给 wrapper。
* 第 34 行：``ifneq ($(GOAL),)`` 是本文件的主分支条件。

**关键代码** （``env.mk:L1-L9``）：

.. code-block:: text

   # EH2 UVM Verification Platform - Environment Makefile
   # This file is included by the main Makefile
   
   # Simulator selection
   EH2_SIMULATOR ?= vcs
   
   # Build options
   WAVES ?= 0
   COV ?= 0

**逐段解释** ：

* 第 1-L2 行：该文件只作为顶层 Makefile 的环境片段。
* 第 5 行：``EH2_SIMULATOR`` 默认 ``vcs``。注意顶层直接编译路径实际读取的是
  ``SIMULATOR`` 变量，``EH2_SIMULATOR`` 不是 ``compile`` target 的变量名。
* 第 8-L9 行：``WAVES`` 和 ``COV`` 默认都为 ``0``，会被顶层 Makefile 后续同名
  ``?=`` 保持。

**接口关系** ：

* **被调用** ：所有顶层 Make target 解析前执行。
* **调用** ：Make include 和条件分支。
* **共享状态** ：``GOAL`` 决定当前 Makefile 走 staged branch 还是 direct branch。

§2.2  ``GOAL`` 分支变量与 metadata 创建
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``GOAL`` 非空时，顶层 ``run`` target 创建 metadata，并把路径和变量传入
wrapper。

**关键代码** （``Makefile:L36-L54``）：

.. code-block:: text

   CONFIG      ?= default
   SEED        ?= 1
   TEST        ?= all
   SIMULATOR   ?= vcs
   WAVES       ?= 0
   COV         ?= 0
   ITERATIONS  ?=
   PARALLEL    ?= 1
   RTL_TEST    ?= core_eh2_base_test
   SIM_OPTS    ?=
   GEN_OPTS    ?=
   ISS         ?= spike
   VERBOSE     ?= 0
   SIGNATURE_ADDR ?= d0580000
   OUT ?= out
   OUT-DIR := $(dir $(OUT)/)
   METADATA-DIR := $(OUT-DIR)metadata
   
   export PYTHONPATH := $(shell cd dv/uvm/core_eh2 && python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')

**逐段解释** ：

* 第 36-L49 行：staged branch 的默认参数包括配置、seed、test、simulator、waves、
  coverage、parallel、ISS 和 signature address。
* 第 50-L52 行：``OUT`` 默认 ``out``，``OUT-DIR`` 取 ``$(OUT)/`` 的目录部分，
  ``METADATA-DIR`` 固定在该目录下的 ``metadata``。
* 第 54 行：``PYTHONPATH`` 由 :file:`dv/uvm/core_eh2/scripts/setup_imports.py`
  计算，供 wrapper 调用的 Python 脚本导入本地模块。

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

**逐段解释** ：

* 第 56-L66 行：``run`` 先执行 ``metadata.py --op create_metadata``，把 seed、waves、
  cov、simulator、ISS、test、verbosity、iteration、signature address、config、
  RTL test、sim/gen options 写入 metadata。
* 第 67-L78 行：metadata 创建完成后，target 调用
  ``make -C dv/uvm/core_eh2 --file wrapper.mk``，并传入绝对 ``OUT-DIR``、
  ``METADATA-DIR``、repo root、simulator、test、seed、iterations、parallel、
  coverage 和 waves。

**接口关系** ：

* **被调用** ：用户执行 ``make run GOAL=<target>``。
* **调用** ：:file:`dv/uvm/core_eh2/scripts/metadata.py` 和
  :file:`dv/uvm/core_eh2/wrapper.mk`。
* **共享状态** ：写入 metadata 目录；wrapper 后续通过 ``scripts/get_meta.mk``
  读取这些字段。

§3  直接 Make 路径变量
--------------------------------------------------------------------------------

§3.1  目录、配置和 simulator 命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``GOAL`` 为空时，顶层 Makefile 定义 direct build path 所需目录、
默认测试、simulator、coverage、sign-off 和 LEC 参数。

**关键代码** （``Makefile:L82-L117``）：

.. code-block:: text

   # Directories
   RTL_DIR      := rtl/design
   SNAPSHOTS    := rtl/snapshots/default
   TB_DIR       := dv/uvm/core_eh2
   SHARED_DIR   := shared/rtl
   COSIM_DIR    := dv/cosim
   SCRIPTS_DIR  := $(TB_DIR)/scripts
   DV_EXT_DIR   := $(TB_DIR)/riscv_dv_extension
   RISCV_DV_DIR := vendor/google_riscv-dv
   ASM_DIR      := tests/asm
   BUILD_DIR    := build

   # Per-target build sub-directory. Each top-level sim target overrides this
   # (smoke -> build/smoke, signoff -> build/signoff, etc.) so the simv/csrc/
   # cov.vdb/compile.log they produce live in their own island.
   BUILD_SUBDIR ?= $(BUILD_DIR)/compile
   
   # Configuration
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

**逐段解释** ：

* 第 82-L92 行：direct path 的 RTL snapshot、testbench、shared RTL、cosim、
  scripts、riscv-dv extension、vendor riscv-dv 和顶层 ASM 路径都在顶层
  Makefile 中固定。
* 第 97-L102 行：``BUILD_SUBDIR`` 是 per-target build island 的关键变量。
  ``make smoke``、``make regress``、``make signoff`` 和 ``make demo`` 会把
  ``simv``、``csrc``、``cov.vdb`` 与 ``compile.log`` 放入各自子目录，避免并行
  目标互相覆盖。
* 第 105-L117 行：默认 simulator 是 ``vcs``，默认 coverage 开启为 ``COV=1``，
  默认 testlist 是 ``riscvdv``。``TEST`` 默认为空，表示 regression target 优先按
  ``TESTLIST`` 选择 YAML；单测可显式传入 ``TEST=<name>``。

**关键代码** （``Makefile:L118-L154``）：

.. code-block:: text

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
   
   # Sign-off coverage 门限（历史兼容命名，当前 dashboard 中显示为 GROUP）
   SIGNOFF_MIN_LINE_COV       ?= 65
   SIGNOFF_MIN_FUNCTIONAL_COV ?= 40
   SIGNOFF_ALLOW_WARNINGS     ?= 1

**逐段解释** ：

* 第 118-L122 行：iteration、parallel、RTL test、sim options、generator options
  都在 direct path 有默认值。
* 第 125-L135 行：sign-off 默认 profile 是 ``full``，默认输出目录是
  :file:`build/signoff`，默认启用 block-level LEC，summary 路径为
  :file:`syn/build/lec_summary.txt`。
* 第 138-L141 行：coverage gate 的 Make 变量名仍保留
  ``SIGNOFF_MIN_FUNCTIONAL_COV``，这是脚本兼容历史报告字段的名字；当前 URG
  dashboard 中对应显示为 ``GROUP``，不是额外的 ``cond`` 维度。

**关键代码** （``Makefile:L123-L132``）：

.. code-block:: text

   # 仿真器命令
   VCS         := vcs
   XLM         := xrun
   IRUN        := irun

   OUT_DIR     := $(BUILD_DIR)/$(TEST)_$(SEED)
   TESTLIST_PATH := $(if $(filter directed,$(TESTLIST)),$(TB_DIR)/directed_tests/directed_testlist.yaml,\
                    $(if $(filter cosim,$(TESTLIST)),$(TB_DIR)/directed_tests/cosim_testlist.yaml,\
                    $(DV_EXT_DIR)/testlist.yaml))

**逐段解释** ：

* 第 156-L158 行：tool command 变量为 ``vcs``、``xrun`` 和 ``irun``。当前
  sign-off 主线强制使用 VCS；NC/Incisive 只作为 ``SIMULATOR=nc WAVES=1`` 的单测
  波形调试通道。
* ``TESTLIST_PATH`` 根据 ``TESTLIST`` 在 directed、cosim 和 riscv-dv extension
  三类 YAML 之间选择。``regress`` 和 sign-off stage 都依赖这个派生路径。

**接口关系** ：

* **被调用** ：``compile_vcs``、``compile_xlm``、``run``、``gen``、regression、
  sign-off 和 coverage target。
* **调用** ：Make 变量展开。
* **共享状态** ：决定编译输入、仿真输出和 sign-off 输出目录。

§3.2  coverage 选项和 testlist 派生变量
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：direct path 为 VCS coverage 生成编译/run 选项，并从 riscv-dv testlist
中派生 ``RUN_RTL_TEST`` 与 cosim plusarg。

**关键代码** （``Makefile:L181-L213``）：

.. code-block:: text

   # Coverage 配置 — 对齐 lowRISC Ibex 工业实现
   #   - 5 维度（line+tgl+assert+fsm+branch）；不收 cond/expression
   #   - -cm_hier cover.cfg 编译时限定 dut 子树
   VCS_COV_METRICS := line+tgl+assert+fsm+branch
   VCS_COV_HIER    := $(TB_DIR)/cover.cfg
   VCS_FSM_CFG     := $(TB_DIR)/cov_fsm.cfg
   VCS_FSM_RESET_FILTER := $(TB_DIR)/cov_fsm_reset_filter.cfg
   VCS_COMPILE_COV_OPTS := -lca \
                           -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                           -cm_hier $(VCS_COV_HIER) \
                           -cm_tgl portsonly \
                           -cm_tgl structarr \
                           -cm_report noinitial \
                           -cm_seqnoconst \
                           -cm_fsmcfg $(VCS_FSM_CFG) \
                           -cm_fsmresetfilter $(VCS_FSM_RESET_FILTER) \
                           -cm_fsmopt report2StateFsms+allowTmp+reportvalues+reportWait+upto64
   NC_COMPILE_COV_OPTS :=
   VCS_RUN_COV_OPTS := -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                       -cm_name $(TEST)_$(SEED) +enable_eh2_fcov=1
   
   TESTLIST_RTL_TEST := $(shell python3 -c 'import pathlib,yaml; p=pathlib.Path("$(DV_EXT_DIR)/testlist.yaml"); data=yaml.safe_load(p.read_text(encoding="utf-8")) if p.exists() else []; print(next((e.get("rtl_test","") for e in (data or []) if isinstance(e,dict) and e.get("test")=="$(TEST)"), ""))' 2>/dev/null)
   TESTLIST_COSIM := $(shell python3 -c 'import pathlib,yaml; p=pathlib.Path("$(DV_EXT_DIR)/testlist.yaml"); data=yaml.safe_load(p.read_text(encoding="utf-8")) if p.exists() else []; print(next((str(e.get("cosim","")) for e in (data or []) if isinstance(e,dict) and e.get("test")=="$(TEST)"), ""))' 2>/dev/null)
   RUN_RTL_TEST := $(if $(filter core_eh2_base_test,$(RTL_TEST)),$(if $(TESTLIST_RTL_TEST),$(TESTLIST_RTL_TEST),$(RTL_TEST)),$(RTL_TEST))
   RUN_COSIM_OPTS := $(if $(filter 0 false False no disabled disable rtl_only,$(COSIM)),+disable_cosim=1,$(if $(filter 1 true True yes enabled enable,$(COSIM)),+enable_cosim=1,$(if $(filter disabled disable false False 0 no rtl_only,$(TESTLIST_COSIM)),+disable_cosim=1,)))
   RUN_SIM_OPTS := $(SIM_OPTS) $(RUN_COSIM_OPTS)

**逐段解释** ：

* 第 181-L188 行：当前 coverage 维度严格是 ``line+tgl+assert+fsm+branch``。
  ``cond`` 不属于 2026-05-19 VCS 主线 sign-off 维度；旧文档中把 cond 当作
  主线维度的口径不能作为当前事实引用。
* 第 189-L203 行：``cover.cfg`` 在编译时限定 ``core_eh2_tb_top.dut`` 子树，
  toggle 采用 Ibex 风格的 ``portsonly`` 与 ``structarr``，并使用 FSM config 与
  reset filter。coverage 数据库按 ``BUILD_SUBDIR`` 写入 per-target island。
* 第 204-L205 行：``NC_COMPILE_COV_OPTS`` 为空，表示 NC 不参与 sign-off coverage。
* 第 206-L213 行：run 阶段使用同一组 VCS metrics 和 per-target coverage 目录，并用
  ``+enable_eh2_fcov=1`` 打开 EH2 covergroup 采样。
* 第 146-L147 行：两个内联 Python 片段从
  :file:`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml` 查找当前 ``TEST`` 的
  ``rtl_test`` 与 ``cosim`` 字段。
* 第 148 行：当用户没有覆盖 ``RTL_TEST`` 时，``RUN_RTL_TEST`` 优先使用 testlist
  中的 ``rtl_test``。
* 第 149-L150 行：``COSIM`` 或 testlist ``cosim`` 字段会生成
  ``+disable_cosim=1`` 或 ``+enable_cosim=1``，并合并进 ``RUN_SIM_OPTS``。

**接口关系** ：

* **被调用** ：``compile_vcs``、``run``、``nightly``、``run_regress``。
* **调用** ：内联 Python/YAML 解析。
* **共享状态** ：读取 riscv-dv testlist，影响 UVM test name 与 cosim plusarg。

§3.3  filelist 变量和 phony target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：direct path 的 simulator 编译使用固定 filelist，phony target 列表声明本
Makefile 的主要入口。

**关键代码** （``Makefile:L152-L164``）：

.. code-block:: text

   # Define files from snapshot
   DEFINES     := $(SNAPSHOTS)/common_defines.vh
   
   # Filelists
   RTL_F       := $(TB_DIR)/eh2_rtl.f
   SHARED_F    := $(TB_DIR)/eh2_shared.f
   TB_F        := $(TB_DIR)/eh2_tb.f
   
   .PHONY: help compile compile_vcs compile_xlm run gen smoke nightly weekly \
           regress run_regress signoff signoff_with_cleanup signoff_quick signoff_gate html_report \
           clean_cov clean ci_unit ci_lint manual manual_html formal formal_clean lint lint_verible \
           lint_verilator synth syn_yosys syn_dc lec block_lec syn_clean \
           clean_workspace clean_workspace_dry

**逐段解释** ：

* 第 152-L153 行：``DEFINES`` 指向 snapshot 中的 ``common_defines.vh``。
* 第 155-L158 行：RTL、shared RTL、testbench filelist 分别是 ``eh2_rtl.f``、
  ``eh2_shared.f``、``eh2_tb.f``。
* 第 160-L164 行：phony target 中列出 ``compile_vcs`` 和 ``compile_xlm``，没有
  ``compile_questa``。

**接口关系** ：

* **被调用** ：``compile_vcs``、``compile_xlm``、Python ``compile_tb.py`` 也使用
  同一组三个 filelist。
* **调用** ：Make phony target 声明。
* **共享状态** ：filelist 是 RTL/TB 编译的核心输入。

§4  VCS 编译与 cosim 链接
--------------------------------------------------------------------------------

§4.1  ``NO_COSIM`` 对 VCS 编译依赖的影响
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：VCS direct path 默认把 ``libcosim.so`` 作为 hard prerequisite；设置
``NO_COSIM=1`` 时跳过该依赖和链接参数。

**关键代码** （``Makefile:L226-L244``）：

.. code-block:: text

   # -----------------------------------------------------------------------
   # VCS compilation
   #
   # compile_vcs hard-depends on $(LIBCOSIM) so simv always links the cosim DPI
   # symbols. With a soft `wildcard` link as before, a missing libcosim.so silently
   # yields a simv that throws `Error-[DPI-DIFNF] riscv_cosim_init` only at run
   # time. To opt out (e.g. machines without spike-cosim installed), pass
   # NO_COSIM=1 — this skips the .so prereq and link, and the simv runs only with
   # +disable_cosim=1.
   # -----------------------------------------------------------------------
   LIBCOSIM := $(BUILD_DIR)/libcosim.so
   
   ifeq ($(NO_COSIM),1)
   COMPILE_LIBCOSIM_DEP :=
   COMPILE_LIBCOSIM_LINK :=
   else
   COMPILE_LIBCOSIM_DEP := $(LIBCOSIM)
   COMPILE_LIBCOSIM_LINK := $(CURDIR)/$(LIBCOSIM)
   endif

**逐段解释** ：

* 第 229-L234 行：注释解释 hard dependency 的目的：避免缺少 ``libcosim.so`` 时生成
  运行期才报 DPI symbol 缺失的 ``simv``。
* 第 236 行：``LIBCOSIM`` 固定为 :file:`build/libcosim.so`。
* 第 238-L240 行：``NO_COSIM=1`` 时，``COMPILE_LIBCOSIM_DEP`` 与
  ``COMPILE_LIBCOSIM_LINK`` 都为空。
* 第 241-L244 行：默认情况下，VCS compile 依赖 ``$(LIBCOSIM)`` 并把绝对
  ``libcosim.so`` 路径传给 VCS。

**接口关系** ：

* **被调用** ：``compile_vcs`` target 的 prerequisite 和命令行参数。
* **调用** ：Make 条件 ``ifeq``。
* **共享状态** ：``NO_COSIM`` 影响编译链接；运行期是否禁用 cosim 仍需
  ``+disable_cosim=1``。

§4.2  ``compile_vcs`` 命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``compile_vcs`` 编译 RTL、shared RTL 和 UVM testbench，生成
:file:`build/simv`。

**关键代码** （``Makefile:L246-L272``）：

.. code-block:: text

   compile_vcs: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
   	@echo "=== Compiling with VCS ==="
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

**逐段解释** ：

* 第 246-L248 行：target 依赖 cosim library 和 build directory，然后调用 ``$(VCS)``
  并开启 ``-full64``、SVA extension、SystemVerilog。
* 第 249-L253 行：启用 UVM 1.2、设置 error limit、定义 ``GTLSIM``，并传入
  snapshot defines。
* 第 254-L259 行：加入 AXI4、trace、IRQ、JTAG、cosim agent 和 cosim C++ include
  目录。
* 第 260-L264 行：加载三个 filelist，top module 为 ``core_eh2_tb_top``，并按
  ``NO_COSIM`` 条件传入 ``libcosim.so``。

**关键代码** （``Makefile:L265-L272``）：

.. code-block:: text

   	  -Mdir=$(BUILD_DIR)/csrc \
   	  -o $(BUILD_DIR)/simv \
   	  -l $(BUILD_DIR)/compile.log \
   	  -timescale=1ns/1ps \
   	  -debug_access+all \
   	  $(if $(filter 1,$(WAVES)),-kdb,) \
   	  $(if $(filter 1,$(COV)),$(VCS_COMPILE_COV_OPTS),)
   	@echo "=== Compilation complete ==="

**逐段解释** ：

* 第 265-L267 行：VCS intermediate directory 是 :file:`build/csrc`，输出 binary 是
  :file:`build/simv`，compile log 是 :file:`build/compile.log`。
* 第 268-L269 行：timescale 固定为 ``1ns/1ps``，debug access 为 ``all``。
* 第 270 行：``WAVES=1`` 时额外传入 ``-kdb``。
* 第 271 行：``COV=1`` 时追加 ``VCS_COMPILE_COV_OPTS``。

**接口关系** ：

* **被调用** ：``compile`` 在 ``SIMULATOR=vcs`` 时展开调用；``run``、``smoke``、
  regression target 也通过 ``compile`` 依赖调用。
* **调用** ：Synopsys VCS。
* **共享状态** ：读取 filelist、include 目录、``libcosim.so``；写
  :file:`build/simv` 和 :file:`build/compile.log`。

§4.3  ``libcosim.so`` 构建
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：cosim file target 从 Spike 静态库抽取对象，重新打包 ``libspike_all.a``，
再用 C++ 编译并链接 :file:`dv/cosim/spike_cosim.cc` 和
:file:`dv/cosim/cosim_dpi.cc`。

**关键代码** （``Makefile:L277-L295``）：

.. code-block:: text

   SPIKE_DIR     ?= /home/host/spike-cosim
   SPIKE_INSTALL ?= $(SPIKE_DIR)/install
   SPIKE_CXX     ?= /home/Xilinx/Vivado/2019.1/tps/lnx64/gcc-6.2.0/bin/g++
   SPIKE_CXXFLAGS ?= -std=c++17 -static-libstdc++
   SPIKE_BUILD   ?= $(BUILD_DIR)/spike_objs
   
   # `cosim` is the user-facing alias; the real build is the file target so make
   # can track it as a prereq of compile_vcs.
   .PHONY: cosim
   cosim: $(LIBCOSIM)
   
   $(LIBCOSIM): $(COSIM_DIR)/spike_cosim.cc $(COSIM_DIR)/cosim_dpi.cc \
                $(COSIM_DIR)/spike_cosim.h $(COSIM_DIR)/cosim.h | $(BUILD_DIR)
   	@if [ ! -d "$(SPIKE_INSTALL)" ]; then \
   	  echo "ERROR: SPIKE_INSTALL=$(SPIKE_INSTALL) does not exist."; \
   	  echo "       Build spike-cosim first, set SPIKE_DIR=<path>, or pass"; \

**逐段解释** ：

* 第 277-L281 行：Spike root、install path、C++ compiler、C++ flags 和 object
  staging directory 都可通过 Make 变量覆盖。
* 第 283-L286 行：``cosim`` 是 phony alias，真实可追踪 target 是
  ``$(LIBCOSIM)``。
* 第 288-L289 行：``libcosim.so`` 的源依赖是两个 C++ 文件和两个 header。
* 第 290-L295 行：``SPIKE_INSTALL`` 不存在时打印 error 并退出，提示用户构建
  spike-cosim、设置 ``SPIKE_DIR`` 或传 ``NO_COSIM=1``。

**关键代码** （``Makefile:L296-L319``）：

.. code-block:: text

   	@echo "=== Building co-simulation library (Spike) ==="
   	@mkdir -p $(SPIKE_BUILD)
   	@# Extract Spike library objects into a single directory
   	@cd $(SPIKE_BUILD) && \
   	  ar x $(SPIKE_INSTALL)/lib/libriscv.a && \
   	  rm -f libfdt.a libsoftfloat.a && \
   	  ar x $(SPIKE_INSTALL)/lib/libdisasm.a && \
   	  ar x $(SPIKE_INSTALL)/lib/libfesvr.a && \
   	  ar x $(SPIKE_INSTALL)/lib/libfdt.a && \
   	  ar rcs libspike_all.a *.o
   	@# Compile and link
   	$(SPIKE_CXX) -shared -fPIC -O2 -g \
   	  -I$(COSIM_DIR) \
   	  -I$(SPIKE_INSTALL)/include \
   	  -I$(SPIKE_INSTALL)/include/softfloat \
   	  -I$(VCS_HOME)/include \
   	  $(SPIKE_CXXFLAGS) \
   	  -o $(LIBCOSIM) \
   	  $(COSIM_DIR)/spike_cosim.cc \
   	  $(COSIM_DIR)/cosim_dpi.cc \

**逐段解释** ：

* 第 296-L305 行：target 创建 ``$(SPIKE_BUILD)``，从 ``libriscv.a``、
  ``libdisasm.a``、``libfesvr.a``、``libfdt.a`` 抽取对象，再打包为
  ``libspike_all.a``。
* 第 307-L315 行：C++ 编译使用 ``-shared -fPIC -O2 -g``，include path 包含 cosim
  源目录、Spike include、softfloat include 和 ``$(VCS_HOME)/include``。
* 第 313-L315 行：输出为 ``$(LIBCOSIM)``，源文件是 ``spike_cosim.cc`` 和
  ``cosim_dpi.cc``。

**接口关系** ：

* **被调用** ：默认 ``compile_vcs`` prerequisite 或用户直接运行 ``make cosim``。
* **调用** ：``ar``、C++ compiler、Spike 静态库。
* **共享状态** ：读取 ``SPIKE_INSTALL`` 和 :file:`dv/cosim/`；写
  :file:`build/libcosim.so`。

§5  Xcelium 编译与默认 ``compile`` target
--------------------------------------------------------------------------------

§5.1  ``compile_xlm``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``compile_xlm`` 在 :file:`build/` 目录中调用 ``xrun``，加载同一组 RTL、
shared RTL 和 TB filelist。

**关键代码** （``Makefile:L321-L340``）：

.. code-block:: text

   # -----------------------------------------------------------------------
   # Xcelium compilation
   # -----------------------------------------------------------------------
   compile_xlm: | $(BUILD_DIR)
   	@echo "=== Compiling with Xcelium ==="
   	cd $(BUILD_DIR) && $(XLM) -uvm -sv \
   	  $(DEFINES) \
   	  +incdir+$(SNAPSHOTS) \
   	  +incdir+../$(TB_DIR)/common/axi4_agent \
   	  +incdir+../$(TB_DIR)/common/trace_agent \
   	  +incdir+../$(TB_DIR)/common/irq_agent \
   	  +incdir+../$(TB_DIR)/common/jtag_agent \
   	  +incdir+../$(TB_DIR)/common/cosim_agent \
   	  -f ../$(RTL_F) \
   	  -f ../$(SHARED_F) \
   	  -f ../$(TB_F) \
   	  -top core_eh2_tb_top \
   	  -l compile.log \
   	  $(if $(filter 1,$(COV)),-covoverwrite -covfile ../$(TB_DIR)/cov.ccf,)
   	@echo "=== Compilation complete ==="

**逐段解释** ：

* 第 324-L326 行：target 依赖 build directory，并在该目录中运行 ``xrun``。
* 第 327-L333 行：传入 defines、snapshot include 和 common agent include。
* 第 334-L338 行：filelist 路径因当前目录为 :file:`build/` 而使用 ``../`` 前缀；
  top 仍为 ``core_eh2_tb_top``，log 为 ``compile.log``。
* 第 339 行：``COV=1`` 时传入 ``-covoverwrite`` 和 ``cov.ccf``。

**接口关系** ：

* **被调用** ：``compile`` 在 ``SIMULATOR=xlm`` 时展开调用。
* **调用** ：Cadence Xcelium ``xrun``。
* **共享状态** ：读取同一组三个 filelist；写 :file:`build/compile.log`。

§5.2  ``compile`` 展开规则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：direct path 的默认 ``compile`` target 通过 ``compile_$(SIMULATOR)``
进行二级展开。

**关键代码** （``Makefile:L342-L343``）：

.. code-block:: text

   # Default compile target
   compile: compile_$(SIMULATOR)

**逐段解释** ：

* 第 342 行：注释说明这是默认 compile target。
* 第 343 行：``SIMULATOR=vcs`` 时依赖 ``compile_vcs``，``SIMULATOR=xlm`` 时依赖
  ``compile_xlm``。当前 Makefile 未定义 ``compile_questa``，因此 direct path
  下不能把 ``SIMULATOR=questa`` 写成已有可用 target。

**接口关系** ：

* **被调用** ：``make compile``、``run``、``smoke``、``nightly``、``weekly``、
  ``regress``、``run_regress``。
* **调用** ：Make target dependency expansion。
* **共享状态** ：读取 ``SIMULATOR``。

§6  单测运行、生成和回归入口
--------------------------------------------------------------------------------

§6.1  ``run`` direct path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：direct path 的 ``run`` 先依赖 ``compile``，再调用 :file:`build/simv`
执行单个 UVM test。

**关键代码** （``Makefile:L345-L361``）：

.. code-block:: text

   # -----------------------------------------------------------------------
   # Run a single test
   # -----------------------------------------------------------------------
   run: compile
   	@echo "=== Running test: $(TEST) seed=$(SEED) ==="
   	@mkdir -p $(OUT_DIR)
   	$(BUILD_DIR)/simv \
   	  +UVM_TESTNAME=$(RUN_RTL_TEST) \
   	  +bin=$(BINARY) \
   	  +seed=$(SEED) \
   	  +timeout_ns=$(TIMEOUT_NS) \
   	  +UVM_VERBOSITY=$(VERBOSITY) \
   	  $(RUN_SIM_OPTS) \
   	  $(if $(filter 1,$(WAVES)),+fsdb+functions,) \
   	  $(if $(filter 1,$(COV)),$(VCS_RUN_COV_OPTS),) \
   	  -l $(OUT_DIR)/sim.log
   	@echo "=== Test complete: $(TEST) ==="

**逐段解释** ：

* 第 348-L350 行：``run`` 依赖 ``compile``，然后创建
  ``build/<TEST>_<SEED>``。
* 第 351-L356 行：执行 :file:`build/simv`，传入 UVM test name、binary path、
  seed、timeout 和 UVM verbosity。
* 第 357-L359 行：追加 ``RUN_SIM_OPTS``、wave plusarg 和 VCS coverage run options。
* 第 360-L361 行：仿真 log 写入 ``$(OUT_DIR)/sim.log``，随后打印完成信息。

**接口关系** ：

* **被调用** ：用户执行 ``make run TEST=<name> SEED=<seed>``。
* **调用** ：:file:`build/simv`。
* **共享状态** ：读取 ``BINARY``；写 :file:`build/<TEST>_<SEED>/sim.log`。

§6.2  ``gen`` direct path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``gen`` 调用 riscv-dv instruction generator wrapper，输出到当前
``OUT_DIR``。

**关键代码** （``Makefile:L363-L376``）：

.. code-block:: text

   # -----------------------------------------------------------------------
   # Generate riscv-dv instructions
   # -----------------------------------------------------------------------
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

**逐段解释** ：

* 第 366-L368 行：``gen`` 需要 build directory，并创建当前 test/seed 输出目录。
* 第 369-L375 行：调用 :file:`dv/uvm/core_eh2/scripts/run_instr_gen.py`，传入
  riscv-dv root、work dir、test、generator options、seed 和 iterations。
* 第 376 行：脚本返回后打印 generation complete。

**接口关系** ：

* **被调用** ：用户执行 ``make gen TEST=<name>``。
* **调用** ：:file:`dv/uvm/core_eh2/scripts/run_instr_gen.py`。
* **共享状态** ：读取 :file:`vendor/google_riscv-dv` 和
  :file:`dv/uvm/core_eh2/riscv_dv_extension/`；写 ``OUT_DIR``。

§6.3  regression target 与 coverage merge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：smoke、nightly、weekly、regress、run_regress 均依赖 ``compile``，再调用
``run_regress.py``。

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

* 第 381-L388 行：``smoke`` 固定运行 ``riscv_arithmetic_basic_test``，seed 为 ``1``，
  输出目录为 :file:`build/smoke`。
* 第 393-L401 行：``nightly`` 使用 riscv-dv extension testlist，iterations 为
  ``1``，parallel 来自 ``PARALLEL``，``COV=1`` 时追加 ``--coverage``。

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

* 第 407-L415 行：``weekly`` 使用同一 testlist，但 iterations 固定为 ``5``。
* 第 420-L426 行：``regress`` 使用 ``ITERATIONS``、``PARALLEL`` 和
  :file:`build/regression`。
* 第 428-L435 行：``run_regress`` 根据 ``TEST_LIST=directed`` 在 directed testlist
  和 riscv-dv testlist 之间选择，并可用 ``OUT`` 覆盖输出目录。

**接口关系** ：

* **被调用** ：用户或 sign-off profile 调用 regression target。
* **调用** ：:file:`dv/uvm/core_eh2/scripts/run_regress.py`。
* **共享状态** ：读取 testlist YAML；输出到 :file:`build/smoke`、
  :file:`build/nightly`、:file:`build/weekly`、:file:`build/regression` 或 ``OUT``。

§7  ``wrapper.mk`` staged flow
--------------------------------------------------------------------------------

§7.1  metadata 导入与目录派生
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：wrapper 通过 ``scripts/get_meta.mk`` 从 metadata 中读取目录和 test
集合，形成 staged target 的文件依赖。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L16-L40``）：

.. code-block:: text

   SHELL := bash
   PRJ_DIR ?= $(realpath ../../..)
   OUT-DIR ?= $(PRJ_DIR)/out
   METADATA-DIR ?= $(OUT-DIR)/metadata
   SIMULATOR ?= vcs
   TEST ?= all
   SEED ?= 1
   ITERATIONS ?=
   PARALLEL ?= 1
   COV ?= 0
   WAVES ?= 0
   SIGNOFF_PROFILE ?= full
   SIGNOFF_OPTS ?=
   SIGNOFF_ITERATIONS ?=
   
   export PYTHONPATH ?= $(shell python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')
   
   include scripts/util.mk
   -include scripts/get_meta.mk

**逐段解释** ：

* 第 16-L29 行：wrapper 设置 shell、project root、output/metadata directory、simulator、
  test、seed、iteration、parallel、coverage、waves 和 sign-off 参数。
* 第 31 行：wrapper 自己也会计算 ``PYTHONPATH``。
* 第 33-L34 行：包含 ``scripts/util.mk``，并 soft include ``scripts/get_meta.mk``。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L36-L63``）：

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
   
   riscvdv-dirs = $(foreach ts,$(riscvdv-ts),$(TESTS-DIR)/$(ts)/)
   directed-dirs = $(foreach ts,$(directed-ts),$(TESTS-DIR)/$(ts)/)
   ts-dirs := $(riscvdv-dirs) $(directed-dirs)
   
   riscvdv-test-asms = $(addsuffix $(asm-stem),$(riscvdv-dirs))

**逐段解释** ：

* 第 36-L40 行：wrapper 不直接信任命令行目录，而是从 metadata 读取 ``dir_out``、
  ``dir_tests``、``dir_build``、``dir_run`` 和 ``dir_metadata``。
* 第 42-L43 行：riscv-dv 和 directed test-dot-seed 列表来自 metadata。
* 第 45-L49 行：wrapper 定义每个 test directory 内的固定文件名：``test.S``、
  ``test.bin``、``test.hex``、``rtl_sim.log``、``trr.yaml``。
* 第 51-L63 行：由 test-dot-seed 列表展开出目录、assembly、binary、simulation log
  和 comparison result 依赖。

**接口关系** ：

* **被调用** ：顶层 ``make run GOAL=...`` 委派到 wrapper。
* **调用** ：``get-meta`` Make function。
* **共享状态** ：metadata 是 wrapper target graph 的 ground truth。

§7.2  staged generation、compile、simulation、check
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：wrapper 将 riscv-dv generation、ASM compile、RTL TB compile、RTL
simulation、log check 和 result collection 拆成文件依赖。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L65-L112``）：

.. code-block:: text

   $(BUILD-DIR) $(TESTS-DIR) $(METADATA-DIR):
   	@mkdir -p $@
   
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

**逐段解释** ：

* 第 65-L66 行：build、tests、metadata 目录通过同一个 pattern target 创建。
* 第 68-L76 行：``core_config`` 生成
  :file:`riscv_dv_extension/riscv_core_setting.sv`，并用 stamp 文件标记完成。
* 第 78 行：``instr_gen_build`` 依赖 ``instr.gen.build.stamp``。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L79-L137``）：

.. code-block:: text

   $(METADATA-DIR)/instr.gen.build.stamp: core_config scripts/build_instr_gen.py | $(BUILD-DIR)
   	@echo Building randomized test generator
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/build_instr_gen.py \
   	    --dir-metadata $(METADATA-DIR)
   	@touch $@
   
   instr_gen_run: $(riscvdv-test-asms)
   $(riscvdv-test-asms): $(TESTS-DIR)/%/$(asm-stem): instr_gen_build scripts/run_instr_gen.py
   	@echo Running randomized test generator for $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/run_instr_gen.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    --test-dot-seed $*

**逐段解释** ：

* 第 79-L84 行：generator build 依赖 ``core_config`` 和 ``build_instr_gen.py``。
* 第 87-L94 行：每个 riscv-dv test-dot-seed 的 ``test.S`` 由
  ``run_instr_gen.py --test-dot-seed`` 生成。
* 第 95 行：wrapper 将 generator 输出目录中找到的第一个 ``*.S`` 复制为
  当前 test directory 的 ``test.S``。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L97-L137``）：

.. code-block:: text

   compile_riscvdv_tests: $(riscvdv-test-bins)
   $(riscvdv-test-bins): $(TESTS-DIR)/%/$(bin-stem): $(TESTS-DIR)/%/$(asm-stem) scripts/compile_test.py
   	@echo Compiling riscv-dv test $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/compile_test.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    --test-dot-seed $*
   
   compile_directed_tests: $(directed-test-bins)
   $(directed-test-bins): $(TESTS-DIR)/%/$(bin-stem): scripts/compile_test.py | $(TESTS-DIR)
   	@echo Compiling directed test $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \

**逐段解释** ：

* 第 97-L103 行：riscv-dv test binary 依赖同目录 ``test.S`` 和
  ``compile_test.py``。
* 第 106-L112 行：directed test binary 不依赖预先存在的 ``test.S``，由
  ``compile_test.py`` 根据 metadata 中的 directed entry 复制源 ASM。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L117-L144``）：

.. code-block:: text

   rtl_tb_compile:
   	$(verb)$(MAKE) -C $(PRJ_DIR) compile GOAL= SIMULATOR=$(SIMULATOR) COV=$(COV) WAVES=$(WAVES)
   
   rtl_sim_run: $(rtl-sim-logs)
   $(rtl-sim-logs): $(TESTS-DIR)/%/$(rtl-sim-logfile): rtl_tb_compile $(TESTS-DIR)/%/$(bin-stem) scripts/run_rtl.py
   	@echo Running RTL simulation for $*
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/run_rtl.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    --test-dot-seed $*
   	$(verb)cp $(@D)/sim_$$(echo $* | sed 's/\.[0-9][0-9]*$$//')_$$(echo $* | sed 's/^.*\.//').log $@
   
   check_logs: $(comp-results)
   $(comp-results): $(TESTS-DIR)/%/$(trr-stem): $(TESTS-DIR)/%/$(rtl-sim-logfile) scripts/check_logs.py

**逐段解释** ：

* 第 117-L118 行：``rtl_tb_compile`` 回到 repo root 运行 direct ``compile``，并显式
  传 ``GOAL=`` 防止递归回 staged branch。
* 第 120-L127 行：每个 ``rtl_sim.log`` 依赖 testbench compile、binary 和
  ``run_rtl.py``；仿真完成后复制具体 ``sim_<test>_<seed>.log`` 为统一的
  ``rtl_sim.log``。
* 第 129-L137 行：``check_logs`` 为每个 simulation log 生成 ``trr.yaml``。

**接口关系** ：

* **被调用** ：wrapper target 如 ``instr_gen_run``、``compile_riscvdv_tests``、
  ``rtl_sim_run``、``check_logs``、默认 ``all``。
* **调用** ：``render_config_template.py``、``build_instr_gen.py``、
  ``run_instr_gen.py``、``compile_test.py``、``run_rtl.py``、``check_logs.py``。
* **共享状态** ：每个 test directory 中固定使用 ``test.S``、``test.bin``、
  ``test.hex``、``rtl_sim.log``、``trr.yaml``。

§8  Python 编译辅助脚本
--------------------------------------------------------------------------------

§8.1  ``compile_tb.py:get_compile_cmd()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Python staged flow 根据 metadata 中的 simulator 构造 testbench 编译命令。

**关键代码** （``dv/uvm/core_eh2/scripts/compile_tb.py:L23-L49``）：

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
           # Add filelists
           cmd += ['-f', str(core_eh2 / 'eh2_rtl.f')]
           cmd += ['-f', str(core_eh2 / 'eh2_shared.f')]
           cmd += ['-f', str(core_eh2 / 'eh2_tb.f')]

**逐段解释** ：

* 第 23-L26 行：函数从脚本路径反推 repo root，并定位
  :file:`dv/uvm/core_eh2/`。
* 第 28-L38 行：``md.simulator == 'vcs'`` 时构造 VCS 命令，log 写到
  ``md.work_dir/compile.log``，csrc 写到 ``md.work_dir/csrc``。
* 第 39-L42 行：VCS Python path 同样加载 ``eh2_rtl.f``、``eh2_shared.f``、
  ``eh2_tb.f``。

**关键代码** （``dv/uvm/core_eh2/scripts/compile_tb.py:L43-L76``）：

.. code-block:: python

           # Add include dirs
           cmd += ['+incdir+{}'.format(core_eh2 / 'riscv_dv_extension')]
           # Add cosim DPI
           cmd += ['-CFLAGS', '-std=c++17']
           # Output
           cmd += ['-o', os.path.join(md.work_dir, 'simv')]
   
       elif md.simulator == 'xlm':
           cmd = [
               'xrun', '-64bit',
               '-uvm',
               '-sv',
               '-timescale', '1ns/1ps',
               '-l', os.path.join(md.work_dir, 'compile.log'),
           ]
           cmd += ['-f', str(core_eh2 / 'eh2_rtl.f')]
           cmd += ['-f', str(core_eh2 / 'eh2_shared.f')]

**逐段解释** ：

* 第 43-L48 行：VCS Python command 加入 riscv-dv extension include、C++17 CFLAGS，
  并把输出 binary 命名为 ``md.work_dir/simv``。
* 第 50-L61 行：``md.simulator == 'xlm'`` 时构造 Xcelium ``xrun`` 命令，并加载同
  一组三个 filelist。
* 第 63-L74 行：``md.simulator == 'questa'`` 时构造 ``vlog -sv`` 命令；不支持的
  simulator 触发 ``ValueError``。

**接口关系** ：

* **被调用** ：``compile_tb.py:main()``。
* **调用** ：不直接运行工具，只返回命令列表。
* **共享状态** ：读取 metadata 中的 ``simulator`` 和 ``work_dir``。

§8.2  ``compile_tb.py:main()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``main()`` 从 metadata 目录恢复 regression metadata，创建 work dir，
调用 ``get_compile_cmd``，再用 ``run_one`` 执行。

**关键代码** （``dv/uvm/core_eh2/scripts/compile_tb.py:L79-L103``）：

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
   
       stdout_log = os.path.join(md.work_dir, 'compile_stdout.log')
       retcode = run_one(True, cmd, redirect_stdstreams=stdout_log)
   
       if retcode:
           logger.error(f'Compilation failed with return code {retcode}')
       else:
           logger.info('Compilation succeeded')
   
       return retcode
   
   
   if __name__ == '__main__':
       sys.exit(main())

**逐段解释** ：

* 第 79-L83 行：脚本只接受 ``--dir-metadata`` 参数。
* 第 85-L88 行：从 metadata 目录构造 ``RegressionMetadata``，创建 ``md.work_dir``，
  并生成 compile command。
* 第 91-L92 行：stdout/stderr 重定向到 ``compile_stdout.log``，实际命令执行由
  ``scripts_lib.run_one`` 完成。
* 第 94-L103 行：根据 return code 记录成功或失败，并把 return code 作为进程退出码。

**接口关系** ：

* **被调用** ：wrapper 或其他 staged scripts 可调用该脚本。
* **调用** ：``RegressionMetadata.construct_from_metadata_dir``、``run_one``。
* **共享状态** ：读取 metadata pickle/YAML；写 work dir 下的 compile log。

§8.3  ``scripts_lib.run_one()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``run_one`` 是多个 Python 脚本共用的 subprocess wrapper，负责命令打印、
stdout/stderr 重定向、timeout 和 return code 转换。

**关键代码** （``dv/uvm/core_eh2/scripts/scripts_lib.py:L20-L69``）：

.. code-block:: python

   def run_one(verbose: bool, cmd: List[str],
               redirect_stdstreams: Optional[Union[str, Path]] = None,
               timeout_s: Optional[int] = None,
               env: Optional[Dict[str, str]] = None) -> int:
       """Run a command, returning its retcode.
   
       Args:
           verbose: If True, print the command to stderr (like bash -x).
           cmd: Command as list of strings.
           redirect_stdstreams: Path to redirect stdout/stderr to.
           timeout_s: Timeout in seconds.
           env: Optional environment variables.
   
       Returns:
           Process return code.
       """

**逐段解释** ：

* 第 20-L24 行：函数参数包括 verbose、命令列表、可选重定向路径、timeout 和环境。
* 第 25-L37 行：docstring 明确返回 subprocess return code。

**关键代码** （``dv/uvm/core_eh2/scripts/scripts_lib.py:L38-L69``）：

.. code-block:: python

       stdstream_dest = None
       needs_closing = False
   
       if redirect_stdstreams is not None:
           if str(redirect_stdstreams) == '/dev/null':
               stdstream_dest = subprocess.DEVNULL
           elif isinstance(redirect_stdstreams, (str, Path)):
               stdstream_dest = open(redirect_stdstreams, 'wb')
               needs_closing = True
   
       cmd_str = ' '.join(shlex.quote(w) for w in cmd)
       if verbose:
           print('+ ' + cmd_str, file=sys.stderr)
           if stdstream_dest and stdstream_dest != subprocess.DEVNULL:
               try:
                   print('+ ' + cmd_str, file=stdstream_dest)
               except (TypeError, AttributeError):
                   pass

**逐段解释** ：

* 第 38-L46 行：重定向路径为 ``/dev/null`` 时使用 ``subprocess.DEVNULL``；普通路径
  以 binary write 打开，并记录需要关闭。
* 第 48-L55 行：命令通过 ``shlex.quote`` 拼成可打印字符串；verbose 为真时打印到
  stderr，并尝试写入重定向日志。

**关键代码** （``dv/uvm/core_eh2/scripts/scripts_lib.py:L57-L69``）：

.. code-block:: python

       try:
           ps = subprocess.run(cmd,
                               stdout=stdstream_dest,
                               stderr=stdstream_dest,
                               close_fds=False,
                               timeout=timeout_s,
                               env=env)
           return ps.returncode
       except subprocess.CalledProcessError:
           return 1
       except OSError as e:
           print(e, file=sys.stderr)
           return 1

**逐段解释** ：

* 第 57-L63 行：实际执行使用 ``subprocess.run``，stdout/stderr 指向同一个
  destination，``close_fds`` 为 ``False``。
* 第 64-L69 行：``CalledProcessError`` 和 ``OSError`` 都转换为 return code ``1``；
  ``OSError`` 会额外打印异常。

**接口关系** ：

* **被调用** ：``compile_tb.py``、``compile_test.py`` 和其他 regression scripts。
* **调用** ：Python ``subprocess.run``。
* **共享状态** ：可写 stdout/stderr redirect log。

§8.4  ``eh2_cmd.py`` 配置 helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_cmd.py`` 从 :file:`eh2_configs.yaml` 读取配置，生成 ISA 字符串或
Verilog defines。

**关键代码** （``dv/uvm/core_eh2/scripts/eh2_cmd.py:L13-L27``）：

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
       params = dict(configs[config_name].get("parameters", {}) or {})
       return {
           "name": config_name,
           "description": configs[config_name].get("description", ""),
           "parameters": params,
       }

**逐段解释** ：

* 第 13-L17 行：配置文件路径是 repo root 下的 :file:`eh2_configs.yaml`，读取方式为
  ``yaml.safe_load``。
* 第 18-L21 行：未知 config 会抛出 ``KeyError``，错误信息列出可用配置。
* 第 22-L27 行：返回字典包含 name、description 和 parameters。

**关键代码** （``dv/uvm/core_eh2/scripts/eh2_cmd.py:L30-L55``）：

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
       if bitmanip:
           return (base + "_zba_zbb_zbc_zbs", base + "_" + "_".join(bitmanip))
       return (base, base)

**逐段解释** ：

* 第 30-L33 行：基础 ISA 字符串为 ``rv32imac``。
* 第 34-L42 行：从 config parameters 中读取 ``BITMANIP_ZBA``、``BITMANIP_ZBB``、
  ``BITMANIP_ZBC``、``BITMANIP_ZBS``，值转为 int 后决定是否加入 bitmanip 列表。
* 第 43-L45 行：若 bitmanip 非空，GCC ISA 固定返回
  ``rv32imac_zba_zbb_zbc_zbs``，ISS ISA 只包含实际 enabled 的 bitmanip 项；否则
  两者都返回 ``rv32imac``。

**接口关系** ：

* **被调用** ：编译 test 或命令行配置 helper。
* **调用** ：YAML parser。
* **共享状态** ：读取 :file:`eh2_configs.yaml`。

§9  本地 UVM Makefile 转发
--------------------------------------------------------------------------------

§9.1  pass-through 变量
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`dv/uvm/core_eh2/Makefile` 是本地开发 convenience Makefile，它
不直接编译 RTL，而是转发到 repo root。

**关键代码** （``dv/uvm/core_eh2/Makefile:L18-L41``）：

.. code-block:: text

   # Project root (relative to this Makefile)
   PROJ_ROOT := ../../..
   TB_DIR    := dv/uvm/core_eh2
   
   # Pass-through variables
   CONFIG     ?= default
   SEED       ?= 1
   TEST       ?= riscv_arithmetic_basic_test
   SIMULATOR   ?= vcs
   BINARY      ?=
   WAVES       ?= 0
   COV         ?= 0
   ITERATIONS  ?= 1
   PARALLEL    ?= 1
   RTL_TEST    ?= core_eh2_base_test
   VERBOSITY   ?= UVM_MEDIUM
   SIGNOFF_ITERATIONS ?=
   LEC_BLOCKLEVEL ?= 0
   LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt

**逐段解释** ：

* 第 18-L20 行：本地 Makefile 通过 ``../../..`` 找到 repo root。
* 第 23-L36 行：定义转发变量，默认值与顶层 direct path 基本一致。
* 第 38-L41 行：coverage 编译选项由顶层 Makefile 和
  :file:`dv/uvm/core_eh2/yaml/rtl_simulation.yaml` 拥有，本地 Makefile 不复制这些
  选项。

**接口关系** ：

* **被调用** ：开发者在 :file:`dv/uvm/core_eh2/` 下运行 ``make``。
* **调用** ：后续 target 全部 ``cd $(PROJ_ROOT) && $(MAKE) ...``。
* **共享状态** ：只传递变量，不维护独立 build graph。

§9.2  target 转发
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：本地 Makefile 的 compile/run/gen/smoke/nightly/weekly/signoff/cov/clean
target 都转发到顶层 Makefile。

**关键代码** （``dv/uvm/core_eh2/Makefile:L67-L100``）：

.. code-block:: text

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

**逐段解释** ：

* 第 67-L68 行：本地 ``compile`` 转发 ``SIMULATOR`` 和 ``CONFIG``。
* 第 70-L73 行：本地 ``run`` 依赖本地 ``compile``，再转发 test、seed、simulator、
  binary、waves、coverage、RTL test 和 verbosity。
* 第 75-L80 行：``gen`` 和 ``smoke`` 也只转发到顶层 target。

**关键代码** （``dv/uvm/core_eh2/Makefile:L82-L100``）：

.. code-block:: text

   nightly:
   	cd $(PROJ_ROOT) && $(MAKE) nightly SIMULATOR=$(SIMULATOR) PARALLEL=$(PARALLEL)
   
   weekly:
   	cd $(PROJ_ROOT) && $(MAKE) weekly SIMULATOR=$(SIMULATOR) PARALLEL=$(PARALLEL)
   
   signoff:
   	cd $(PROJ_ROOT) && $(MAKE) signoff SIMULATOR=$(SIMULATOR) PARALLEL=$(PARALLEL) \
   	  SIGNOFF_ITERATIONS=$(SIGNOFF_ITERATIONS) COV=$(COV) WAVES=$(WAVES) \
   	  LEC_BLOCKLEVEL=$(LEC_BLOCKLEVEL) LEC_SUMMARY_PATH=$(LEC_SUMMARY_PATH)
   
   signoff_quick:
   	cd $(PROJ_ROOT) && $(MAKE) signoff_quick SIMULATOR=$(SIMULATOR) PARALLEL=$(PARALLEL)

**逐段解释** ：

* 第 82-L86 行：nightly 和 weekly 转发 simulator 与 parallel。
* 第 88-L91 行：signoff 转发 simulator、parallel、iteration、coverage、waves、
  LEC block-level 开关和 summary path。
* 第 93-L94 行：signoff quick 转发 simulator 与 parallel。
* 第 96-L100 行：cov 和 clean 也回到 repo root 运行。

**接口关系** ：

* **被调用** ：本地开发者 convenience target。
* **调用** ：repo root :file:`Makefile`。
* **共享状态** ：不直接写本地输出；输出仍由顶层 Makefile 决定。

§10  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`regression_flow`、:ref:`signoff_flow`、:ref:`scripts_reference`、
  :ref:`appendix_f_scripts/makefiles`。
* 关联配置：:file:`eh2_configs.yaml`、:file:`dv/uvm/core_eh2/yaml/rtl_simulation.yaml`。
* 源文件绝对路径：
  :file:`/home/host/eh2-veri/Makefile`、
  :file:`/home/host/eh2-veri/env.mk`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/Makefile`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/wrapper.mk`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_tb.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_test.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/eh2_cmd.py`、
  :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/scripts_lib.py`。
