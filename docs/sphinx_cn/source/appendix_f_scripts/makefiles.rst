.. _appendix_f_scripts_makefiles:
.. _appendix_f_scripts/makefiles:

Makefile 体系
==============

:status: draft
:source: Makefile, env.mk, dv/uvm/core_eh2/Makefile, dv/uvm/core_eh2/wrapper.mk, dv/uvm/core_eh2/scripts/\*.mk
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本章解释 EH2-Veri 的 Makefile 入口、变量、target 调用关系和 metadata 驱动的
staged flow。行号均基于本页 frontmatter 中记录的 commit。所有代码片段均来自
实际 Makefile，且单段不超过 30 行。

§1 Makefile 体系总览
--------------------------------------------------------------------------------

EH2-Veri 同时保留两条 Make 路径：顶层 `Makefile` 的直接模式用于日常编译、
单测、回归、sign-off、lint、formal、synthesis 和 LEC；`GOAL` 非空时进入
Ibex-style staged 模式，由 `metadata.py` 先生成 metadata，再委托
`dv/uvm/core_eh2/wrapper.mk` 执行分阶段流水。

::

   make <target>
        |
        +-- GOAL empty ------------------> top-level direct targets
        |                                   compile/run/regress/signoff/...
        |
        +-- GOAL set --------------------> metadata.py --op create_metadata
                                            |
                                            v
                                          dv/uvm/core_eh2/wrapper.mk
                                            |
                                            +-- core_config
                                            +-- instr_gen_build / instr_gen_run
                                            +-- compile_*_tests
                                            +-- rtl_tb_compile / rtl_sim_run
                                            +-- check_logs
                                            +-- collect_results

§1.1 顶层分支结构
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 `GOAL` 是否为空，在同一个顶层 `Makefile` 中选择 staged 入口或直接
target 入口。

关键代码（``Makefile:L25-L35``）：

.. code-block:: bash

   SHELL := /bin/bash

   # Source environment
   -include env.mk

   # Ibex-style staged entry point. When GOAL is set, `make run GOAL=...` creates
   # regression metadata and delegates to dv/uvm/core_eh2/wrapper.mk.
   GOAL ?=

   ifneq ($(GOAL),)

逐段解释：

* 第 L25 行：顶层 Makefile 固定使用 `/bin/bash`，后续 recipe 中的 shell 条件和
  多行命令均按 bash 语义执行。
* 第 L28 行：`env.mk` 以 `-include` 方式读取；文件缺失不会让 make 失败。
* 第 L32-L35 行：`GOAL` 默认为空；非空时进入 staged 分支。

接口关系：

* 被调用：用户直接运行 `make`、`make run` 或 `make run GOAL=<target>`。
* 调用：staged 分支调用 `metadata.py` 和 `wrapper.mk`；直接分支定义普通 targets。
* 共享状态：读取 `env.mk`，通过 `GOAL` 选择 Makefile 分支。

§1.2 staged 入口的 metadata 创建和委托
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 `GOAL` 非空时，先创建 metadata，再把 stage 执行交给
`dv/uvm/core_eh2/wrapper.mk`。

关键代码（``Makefile:L54-L78``）：

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

* 第 L54 行：`PYTHONPATH` 由 `scripts.setup_imports.get_pythonpath()` 动态生成，
  避免 staged flow 依赖用户手工设置 Python 搜索路径。
* 第 L56-L66 行：`run` target 调用 `metadata.py --op create_metadata`，把 seed、
  waves、coverage、simulator、ISS、test、iterations、signature address、config、
  RTL test、sim opts 和 gen opts 写入 metadata。

接口关系：

* 被调用：`make run GOAL=<wrapper target>`。
* 调用：`dv/uvm/core_eh2/scripts/metadata.py`。
* 共享状态：写 `$(METADATA-DIR)` 和 `$(OUT-DIR)`。

关键代码（``Makefile:L67-L78``）：

.. code-block:: bash

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

逐段解释：

* 第 L67-L70 行：子 make 工作目录切到 `dv/uvm/core_eh2`，Makefile 指定为
  `wrapper.mk`，并用绝对路径传入输出目录、metadata 目录和项目根目录。
* 第 L71-L78 行：simulator、test、seed、iterations、parallel、coverage、waves
  都透传给 wrapper；最终执行的目标名来自 `$(GOAL)`。

接口关系：

* 被调用：顶层 staged `run` target。
* 调用：`dv/uvm/core_eh2/wrapper.mk`。
* 共享状态：通过环境和 make 变量传递 metadata 路径及执行参数。

§2 顶层变量和环境文件
--------------------------------------------------------------------------------

顶层 Makefile 的变量分为 staged 分支变量、直接分支变量、工具路径变量、coverage
变量和 sign-off 变量。`env.mk` 只提供少量默认环境开关。

§2.1 ``env.mk`` — 外部环境默认值
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为顶层 Makefile 提供 simulator、waves 和 coverage 的默认值。

关键代码（``env.mk:L1-L9``）：

.. code-block:: makefile

   # EH2 UVM Verification Platform - Environment Makefile
   # This file is included by the main Makefile

   # Simulator selection
   EH2_SIMULATOR ?= vcs

   # Build options
   WAVES ?= 0
   COV ?= 0

逐段解释：

* 第 L1-L2 行：注释说明该文件由主 Makefile include。
* 第 L5 行：`EH2_SIMULATOR` 默认值为 `vcs`；注意顶层直接分支使用的主变量名是
  `SIMULATOR`，因此该变量是环境层默认，不直接替代 `SIMULATOR`。
* 第 L8-L9 行：`WAVES` 和 `COV` 默认均为 0。

接口关系：

* 被调用：顶层 `Makefile` 第 L28 行 `-include env.mk`。
* 调用：无。
* 共享状态：只定义 make 变量，不创建文件。

§2.2 staged 分支变量
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 `GOAL` 非空的 staged 模式下定义 metadata 生成所需参数。

关键代码（``Makefile:L36-L54``）：

.. code-block:: makefile

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

逐段解释：

* 第 L36-L49 行：staged 分支给 config、seed、test、simulator、waves、coverage、
  iterations、parallel、RTL test、sim/generator opts、ISS、verbose 和 signature
  address 设置默认值。
* 第 L50-L52 行：`OUT` 默认是 `out`；`OUT-DIR` 通过 `$(dir $(OUT)/)` 推导；
  metadata 目录固定为 `$(OUT-DIR)metadata`。
* 第 L54 行：`PYTHONPATH` 从 core UVM 脚本中动态生成。

接口关系：

* 被调用：`make run GOAL=<target>`。
* 调用：`metadata.py --op create_metadata`。
* 共享状态：这些变量最终写入 metadata，并被 `wrapper.mk` 读取。

§2.3 直接分支目录和主变量
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义日常直接目标使用的目录、test 参数、simulator 参数、coverage 参数和
sign-off 输出参数。

关键代码（``Makefile:L82-L132``）：

.. code-block:: makefile

   # Directories
   RTL_DIR      := rtl/design
   SNAPSHOTS    := rtl/snapshots/default
   TB_DIR       := dv/uvm/core_eh2
   SHARED_DIR   := shared/rtl
   COSIM_DIR    := dv/cosim
   SCRIPTS_DIR  := $(TB_DIR)/scripts
   DV_EXT_DIR   := $(TB_DIR)/riscv_dv_extension
   RISCV_DV_DIR := vendor/google_riscv-dv

   # Configuration
   CONFIG      ?= default
   SEED        ?= 1
   TEST        ?= riscv_arithmetic_basic_test

逐段解释：

* 第 L82-L90 行：目录变量覆盖 RTL snapshot、UVM testbench、shared RTL、cosim、
  scripts、riscv-dv extension 和 vendor riscv-dv。
* 第 L92-L107 行：直接分支的默认 test 为 `riscv_arithmetic_basic_test`，
  simulator 默认为 `vcs`，timeout 为 `10000000` ns，iterations 默认为 1。
* 第 L107-L118 行：sign-off 和 HTML report 的默认路径基于 `SIGNOFF_OUT` 和
  `BUILD_DIR` 推导。

接口关系：

* 被调用：所有直接 targets。
* 调用：无。
* 共享状态：为 compile、run、regress、signoff、coverage 等目标提供路径和参数。

关键代码（``Makefile:L123-L150``）：

.. code-block:: makefile

   # Simulator command
   VCS         := vcs
   XLM         := xrun
   QUESTA      := questa

   # Build directory
   BUILD_DIR   := build
   OUT_DIR     := $(BUILD_DIR)/$(TEST)_$(SEED)
   OUT         ?=
   TEST_LIST   ?= default

   VCS_COV_METRICS := line+tgl+assert+fsm+branch
   VCS_COV_HIER    := $(TB_DIR)/cover.cfg
   VCS_FSM_CFG     := $(TB_DIR)/cov_fsm.cfg

逐段解释：

* 第 L123-L126 行：工具命令名分别是 `vcs`、`xrun` 和 `questa`。
* 第 L128-L132 行：直接分支 build 目录固定为 `build`，单测输出目录为
  `build/<TEST>_<SEED>`。
* 第 L134-L137 行：VCS coverage metric 和 hierarchy/FSM config 路径集中定义。

接口关系：

* 被调用：`compile_vcs`、`run`、`cov` 等目标。
* 调用：无。
* 共享状态：决定 build/out 目录和 coverage 配置文件路径。

§2.4 testlist 驱动的 RTL test 和 cosim plusarg
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 riscv-dv testlist 中读取 per-test `rtl_test` 和 `cosim` 字段，自动生成
仿真 plusarg。

关键代码（``Makefile:L146-L150``）：

.. code-block:: makefile

   TESTLIST_RTL_TEST := $(shell python3 -c 'import pathlib,yaml; p=pathlib.Path("$(DV_EXT_DIR)/testlist.yaml"); data=yaml.safe_load(p.read_text(encoding="utf-8")) if p.exists() else []; print(next((e.get("rtl_test","") for e in (data or []) if isinstance(e,dict) and e.get("test")=="$(TEST)"), ""))' 2>/dev/null)
   TESTLIST_COSIM := $(shell python3 -c 'import pathlib,yaml; p=pathlib.Path("$(DV_EXT_DIR)/testlist.yaml"); data=yaml.safe_load(p.read_text(encoding="utf-8")) if p.exists() else []; print(next((str(e.get("cosim","")) for e in (data or []) if isinstance(e,dict) and e.get("test")=="$(TEST)"), ""))' 2>/dev/null)
   RUN_RTL_TEST := $(if $(filter core_eh2_base_test,$(RTL_TEST)),$(if $(TESTLIST_RTL_TEST),$(TESTLIST_RTL_TEST),$(RTL_TEST)),$(RTL_TEST))
   RUN_COSIM_OPTS := $(if $(filter 0 false False no disabled disable rtl_only,$(COSIM)),+disable_cosim=1,$(if $(filter 1 true True yes enabled enable,$(COSIM)),+enable_cosim=1,$(if $(filter disabled disable false False 0 no rtl_only,$(TESTLIST_COSIM)),+disable_cosim=1,)))
   RUN_SIM_OPTS := $(SIM_OPTS) $(RUN_COSIM_OPTS)

逐段解释：

* 第 L146 行：Make 通过内联 Python 读取 `$(DV_EXT_DIR)/testlist.yaml`，查找当前
  `$(TEST)` 对应的 `rtl_test`。
* 第 L147 行：同样通过内联 Python 读取当前测试的 `cosim` 字段。
* 第 L148 行：如果用户没有把 `RTL_TEST` 改成其它值，则优先采用 testlist 中的
  `rtl_test`。
* 第 L149-L150 行：`COSIM` 变量显式指定时优先；否则依据 testlist 的 cosim 字段
  决定是否追加 `+disable_cosim=1`，最终与 `SIM_OPTS` 合并。

接口关系：

* 被调用：`run` target。
* 调用：内联 Python `yaml.safe_load()`。
* 共享状态：读取 `riscv_dv_extension/testlist.yaml`，生成 `RUN_RTL_TEST` 和
  `RUN_SIM_OPTS`。

§3 顶层 phony 目标和帮助文本
--------------------------------------------------------------------------------

§3.1 ``.PHONY`` 分组
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明顶层直接分支中不会与同名文件冲突的目标。

关键代码（``Makefile:L160-L164``）：

.. code-block:: makefile

   .PHONY: help compile compile_vcs compile_xlm run gen smoke nightly weekly \
           regress run_regress signoff signoff_with_cleanup signoff_quick signoff_gate html_report \
           clean_cov clean ci_unit ci_lint manual manual_html formal formal_clean lint lint_verible \
           lint_verilator synth syn_yosys syn_dc lec block_lec syn_clean \
           clean_workspace clean_workspace_dry

逐段解释：

* 第 L160-L164 行：目标按功能分组覆盖编译、单测、生成、回归、sign-off、HTML、
  coverage 清理、CI、文档、formal、lint、synthesis、LEC 和 workspace 清理。

接口关系：

* 被调用：GNU Make 的 target 解析。
* 调用：无。
* 共享状态：防止同名文件影响 target 执行。

§3.2 ``help`` — 用户入口说明
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：打印目标和变量清单，作为顶层 Makefile 的 CLI 帮助。

关键代码（``Makefile:L169-L219``）：

.. code-block:: makefile

   help:
           @echo "EH2 UVM Verification Platform"
           @echo "=============================="
           @echo ""
           @echo "Build Targets:"
           @echo "  compile     - Compile RTL testbench (default: VCS)"
           @echo "  compile_vcs - Compile with VCS"
           @echo "  compile_xlm - Compile with Xcelium"
           @echo ""
           @echo "Test Targets:"
           @echo "  smoke       - Quick smoke test (1 iteration)"
           @echo "  run         - Run single test (TEST=, SEED=)"

逐段解释：

* 第 L169-L177 行：帮助信息先列 build targets，包含通用 `compile`、VCS 和 Xcelium。
* 第 L178-L186 行：test targets 包含 smoke、run、nightly、weekly、signoff、
  signoff_quick、signoff_gate 和 html_report。
* 第 L188-L219 行：utility、synthesis targets 和变量说明继续通过 `echo` 输出。

接口关系：

* 被调用：`make help`。
* 调用：shell `echo`。
* 共享状态：只读 Makefile 变量，不写文件。

§4 编译目标和 cosim 动态库
--------------------------------------------------------------------------------

§4.1 ``compile_vcs`` — VCS testbench 编译
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：编译 RTL、shared RTL、UVM TB 和 cosim DPI，生成 `build/simv`。

关键代码（``Makefile:L236-L272``）：

.. code-block:: makefile

   LIBCOSIM := $(BUILD_DIR)/libcosim.so

   ifeq ($(NO_COSIM),1)
   COMPILE_LIBCOSIM_DEP :=
   COMPILE_LIBCOSIM_LINK :=
   else
   COMPILE_LIBCOSIM_DEP := $(LIBCOSIM)
   COMPILE_LIBCOSIM_LINK := $(CURDIR)/$(LIBCOSIM)
   endif

   compile_vcs: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
           @echo "=== Compiling with VCS ==="

逐段解释：

* 第 L236 行：cosim 动态库输出路径固定为 `build/libcosim.so`。
* 第 L238-L244 行：`NO_COSIM=1` 时取消 `libcosim.so` 依赖和链接参数；默认情况下
  VCS 编译依赖该动态库。
* 第 L246-L247 行：`compile_vcs` 依赖 cosim 动态库，并确保 `$(BUILD_DIR)` 存在。

接口关系：

* 被调用：`compile`、`smoke`、`nightly`、`weekly`、`regress`、`run_regress`。
* 调用：外部工具 `vcs`。
* 共享状态：读 filelist 和 cosim `.so`；写 `build/simv`、`build/compile.log`、
  `build/csrc`。

关键代码（``Makefile:L248-L272``）：

.. code-block:: bash

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

* 第 L248-L251 行：VCS 以 64 位、SVA extension、SystemVerilog 和 UVM 1.2 编译。
* 第 L252-L259 行：加入 snapshot、各 UVM agent 和 cosim include 路径。
* 第 L260-L264 行：加载 RTL、shared 和 TB filelist，top 设为 `core_eh2_tb_top`，
  并链接 `COMPILE_LIBCOSIM_LINK`。
* 第 L265-L271 行：输出目录、simv、compile log、timescale、debug 和 coverage
  选项在这里设置。

接口关系：

* 被调用：`compile: compile_$(SIMULATOR)`。
* 调用：VCS。
* 共享状态：读取 `eh2_rtl.f`、`eh2_shared.f`、`eh2_tb.f` 和 coverage cfg。

§4.2 ``$(LIBCOSIM)`` — Spike cosim DPI 动态库
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：将 Spike 静态库对象和 EH2 cosim C++ 源码链接成 VCS 可加载的 `libcosim.so`。

关键代码（``Makefile:L277-L319``）：

.. code-block:: makefile

   SPIKE_DIR     ?= /home/host/spike-cosim
   SPIKE_INSTALL ?= $(SPIKE_DIR)/install
   SPIKE_CXX     ?= /home/Xilinx/Vivado/2019.1/tps/lnx64/gcc-6.2.0/bin/g++
   SPIKE_CXXFLAGS ?= -std=c++17 -static-libstdc++
   SPIKE_BUILD   ?= $(BUILD_DIR)/spike_objs

   .PHONY: cosim
   cosim: $(LIBCOSIM)

   $(LIBCOSIM): $(COSIM_DIR)/spike_cosim.cc $(COSIM_DIR)/cosim_dpi.cc \
                $(COSIM_DIR)/spike_cosim.h $(COSIM_DIR)/cosim.h | $(BUILD_DIR)

逐段解释：

* 第 L277-L281 行：Spike 安装目录、C++ 编译器、编译选项和中间 object 目录都有默认值。
* 第 L285-L286 行：`cosim` 是面向用户的别名，实际文件目标是 `$(LIBCOSIM)`。
* 第 L288-L289 行：动态库依赖 `spike_cosim.cc`、`cosim_dpi.cc` 和对应头文件。

接口关系：

* 被调用：`compile_vcs` 默认依赖，或用户执行 `make cosim`。
* 调用：`ar`、`g++`。
* 共享状态：读 Spike install 静态库和 `dv/cosim` 源码，写 `build/libcosim.so`。

关键代码（``Makefile:L290-L319``）：

.. code-block:: bash

           @if [ ! -d "$(SPIKE_INSTALL)" ]; then \
             echo "ERROR: SPIKE_INSTALL=$(SPIKE_INSTALL) does not exist."; \
             echo "       Build spike-cosim first, set SPIKE_DIR=<path>, or pass"; \
             echo "       NO_COSIM=1 to skip cosim linkage."; \
             exit 1; \
           fi
           @echo "=== Building co-simulation library (Spike) ==="
           @mkdir -p $(SPIKE_BUILD)
           @# Extract Spike library objects into a single directory
           @cd $(SPIKE_BUILD) && \
             ar x $(SPIKE_INSTALL)/lib/libriscv.a && \
             rm -f libfdt.a libsoftfloat.a && \

逐段解释：

* 第 L290-L295 行：`SPIKE_INSTALL` 不存在时直接失败，并提示可设置 `SPIKE_DIR` 或
  使用 `NO_COSIM=1` 跳过链接。
* 第 L296-L305 行：Make 把 Spike 相关静态库 object 解包到 `$(SPIKE_BUILD)`，
  再归档为 `libspike_all.a`。
* 第 L307-L318 行：`$(SPIKE_CXX)` 以 `-shared -fPIC` 链接 EH2 cosim 源码、
  Spike object 包、softfloat、pthread 和 dl。

接口关系：

* 被调用：`$(LIBCOSIM)` 文件目标。
* 调用：shell test、`mkdir`、`ar`、C++ 编译器。
* 共享状态：写 `$(SPIKE_BUILD)` 和 `$(LIBCOSIM)`。

§4.3 ``compile_xlm`` 和 ``compile``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供 Xcelium 编译路径，并用 `compile_$(SIMULATOR)` 作为默认编译分发。

关键代码（``Makefile:L324-L343``）：

.. code-block:: makefile

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

逐段解释：

* 第 L324-L326 行：Xcelium 编译先确保 build 目录存在，并在 build 目录内运行 `xrun`。
* 第 L327-L337 行：Xcelium 分支使用相对路径加入 defines、include 和 filelist，
  top 同样是 `core_eh2_tb_top`。
* 第 L338-L340 行：compile log 写到 `compile.log`；coverage 时追加 `-covoverwrite`
  和 coverage command file。
* 第 L343 行：通用 `compile` target 通过 `compile_$(SIMULATOR)` 分发到 simulator
  对应 target。

接口关系：

* 被调用：`make compile SIMULATOR=xlm` 或 `make compile`。
* 调用：外部工具 `xrun`。
* 共享状态：读 filelist，写 build 目录中的 compile log。

§5 单测、生成和回归目标
--------------------------------------------------------------------------------

§5.1 ``run`` — 直接运行一个已编译 simulator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：运行 `build/simv`，传入 UVM test、binary、seed、timeout、verbosity、cosim
和 coverage/wave 选项。

关键代码（``Makefile:L348-L361``）：

.. code-block:: makefile

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

逐段解释：

* 第 L348 行：直接 run 依赖 compile，因此会先生成 simulator。
* 第 L350-L360 行：仿真命令传入 UVM test name、binary、seed、timeout、verbosity、
  sim opts、wave opts、coverage opts 和 log 路径。
* 第 L361 行：目标结束后打印测试完成消息。

接口关系：

* 被调用：`make run TEST=<name> SEED=<n> BINARY=<path>`。
* 调用：`build/simv`。
* 共享状态：读 `BINARY`，写 `$(OUT_DIR)/sim.log`。

§5.2 ``gen`` — riscv-dv assembly 生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：调用 `run_instr_gen.py` 生成 riscv-dv assembly。

关键代码（``Makefile:L366-L376``）：

.. code-block:: makefile

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

逐段解释：

* 第 L366-L368 行：生成目标需要 build 目录存在，并创建 per-test 输出目录。
* 第 L369-L375 行：Python 脚本参数覆盖 riscv-dv 根目录、work dir、test、gen opts、
  seed 和 iterations。
* 第 L376 行：生成完成后输出状态文本。

接口关系：

* 被调用：`make gen TEST=<riscv-dv-test>`。
* 调用：`dv/uvm/core_eh2/scripts/run_instr_gen.py`。
* 共享状态：写 `$(OUT_DIR)` 下的 riscv-dv 生成产物。

§5.3 ``smoke``、``nightly`` 和 ``weekly``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为不同规模回归提供固定参数封装。

关键代码（``Makefile:L381-L415``）：

.. code-block:: makefile

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

逐段解释：

* 第 L381-L388 行：smoke 固定跑 `riscv_arithmetic_basic_test`，seed 为 1，输出到
  `build/smoke`。
* 第 L393-L402 行：nightly 使用 riscv-dv extension testlist，iterations 固定为 1，
  支持 `PARALLEL` 和 `COV`。
* 第 L407-L415 行：weekly 同样使用 riscv-dv testlist，但 iterations 固定为 5。

接口关系：

* 被调用：`make smoke`、`make nightly`、`make weekly`。
* 调用：`run_regress.py`。
* 共享状态：写 `build/smoke`、`build/nightly`、`build/weekly`。

§5.4 ``regress`` 与 ``run_regress``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供完整回归入口，`run_regress` 额外支持通过 `TEST_LIST=directed` 切换到
directed testlist。

关键代码（``Makefile:L420-L435``）：

.. code-block:: makefile

   regress: compile
           python3 $(SCRIPTS_DIR)/run_regress.py \
             --testlist $(DV_EXT_DIR)/testlist.yaml \
             --simulator $(SIMULATOR) \
             --iterations $(ITERATIONS) \
             --parallel $(PARALLEL) \
             --output $(BUILD_DIR)/regression

   run_regress: compile
           python3 $(SCRIPTS_DIR)/run_regress.py \
             --testlist $(if $(filter directed,$(TEST_LIST)),$(TB_DIR)/directed_tests/directed_testlist.yaml,$(DV_EXT_DIR)/testlist.yaml) \
             --simulator $(SIMULATOR) \

逐段解释：

* 第 L420-L426 行：`regress` 固定使用 riscv-dv extension testlist，输出到
  `build/regression`。
* 第 L428-L435 行：`run_regress` 根据 `TEST_LIST` 选择 directed testlist 或
  riscv-dv testlist，并允许 `OUT` 覆盖输出目录。

接口关系：

* 被调用：`make regress`、`make run_regress TEST_LIST=directed`。
* 调用：`run_regress.py`。
* 共享状态：读 testlist，写 regression 输出目录。

§6 sign-off、HTML 和 coverage
--------------------------------------------------------------------------------

§6.1 ``signoff`` — 签核主入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：调用 `signoff.py` 执行或评估指定 profile 的 sign-off gate。

关键代码（``Makefile:L1079-L1104``）：

.. code-block:: makefile

   signoff:
      @# VCS 是 sign-off 默认；NC 也可作完整备选 simulator / cross-check 入口。
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

* 第 L1079-L1098 行：sign-off 传入 profile、simulator、seed、parallel 和输出目录。
* 第 L1099-L1103 行：可选传入 gate-only、iterations、block-level LEC、coverage
  gate、warning policy 和 waves。coverage 门限来自 ``SIGNOFF_MIN_LINE_COV=65`` 与
  ``SIGNOFF_MIN_FUNCTIONAL_COV=40``，不是覆盖率实测结果。

接口关系：

* 被调用：`make signoff`。
* 调用：`dv/uvm/core_eh2/scripts/signoff.py`。
* 共享状态：写 `$(SIGNOFF_OUT)` 下的 sign-off 结果。

§6.2 sign-off 派生目标
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供清理后 sign-off、quick profile 和 gate-only 评估入口。

关键代码（``Makefile:L454-L466``）：

.. code-block:: makefile

   signoff_with_cleanup: signoff
           bash scripts/clean_workspace.sh --lck-only 2>/dev/null || true

   signoff_quick:
           $(MAKE) signoff PROFILE=quick SIGNOFF_OUT=$(SIGNOFF_QUICK_OUT)

   signoff_gate:
           python3 $(SCRIPTS_DIR)/signoff.py \
             --profile $(PROFILE) \
             --simulator $(SIMULATOR) \
             --output $(SIGNOFF_OUT) \
             --gate-only \
             $(SIGNOFF_OPTS)

逐段解释：

* 第 L454-L455 行：`signoff_with_cleanup` 先跑 signoff，再执行 workspace 清理脚本的
  lock-only 模式；清理脚本失败不会让 target 失败。
* 第 L457-L458 行：`signoff_quick` 通过递归 make 调用 `signoff`，把 profile 改成
  `quick`，输出目录改成 `SIGNOFF_QUICK_OUT`。
* 第 L460-L466 行：`signoff_gate` 调用 `signoff.py --gate-only`，只评估已有输出。

接口关系：

* 被调用：用户显式运行对应 target。
* 调用：`signoff.py`、`scripts/clean_workspace.sh`。
* 共享状态：读/写 `SIGNOFF_OUT`。

§6.3 ``html_report`` 和 ``cov``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：分别生成自包含 sign-off HTML 报告和合并 simulator coverage。

关键代码（``Makefile:L468-L488``）：

.. code-block:: makefile

   html_report:
           python3 $(SCRIPTS_DIR)/gen_html_report.py \
             --signoff-status $(HTML_REPORT_STATUS) \
             --coverage-dashboard $(HTML_REPORT_COVERAGE) \
             --runs-dir $(HTML_REPORT_RUNS) \
             --output $(HTML_REPORT_OUT)

   cov:
           @echo "=== Collecting coverage ==="
           @if [ "$(SIMULATOR)" = "vcs" ]; then \
             urg -dir $(BUILD_DIR)/cov/simv.vdb -report $(BUILD_DIR)/cov_report; \

逐段解释：

* 第 L468-L473 行：HTML 报告由 `gen_html_report.py` 读取 sign-off JSON、coverage
  dashboard、runs 目录和输出路径。
* 第 L478-L485 行：coverage target 是 deprecated 辅助入口；VCS 分支调用 `urg`。
  当前 sign-off 覆盖率合并由 `signoff.py` 自动驱动，NC/Xcelium 不作为权威 coverage
  sign-off 路径。
* 第 L487-L488 行：`clean_cov` 只删除 build 目录下的 coverage DB 和 coverage report。

接口关系：

* 被调用：`make html_report`、`make cov`、`make clean_cov`。
* 调用：`gen_html_report.py`、`urg`。
* 共享状态：读 sign-off/coverage 文件，写 HTML 或 coverage report。

§7 CI、辅助流程和委托目标
--------------------------------------------------------------------------------

§7.1 ``ci_unit`` 与 ``ci_lint``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：运行 Python 回归框架单元测试和 testlist YAML sanity 检查。

关键代码（``Makefile:L497-L513``）：

.. code-block:: makefile

   ci_unit:
           @echo "=== CI: Python regression-framework tests ==="
           cd $(TB_DIR)/scripts && python3 -m unittest tests.test_regression_framework
           @$(MAKE) --no-print-directory ci_lint
           @echo "=== CI unit tests complete ==="

   ci_lint:
           @echo "=== CI: testlist YAML sanity ==="
           @python3 -c "import yaml, pathlib; \
   tl = pathlib.Path('$(TB_DIR)/riscv_dv_extension/testlist.yaml'); \
   tests = yaml.safe_load(tl.read_text()); \

逐段解释：

* 第 L497-L501 行：`ci_unit` 在 scripts 目录运行 Python unittest，然后调用
  `ci_lint`。
* 第 L503-L513 行：`ci_lint` 用内联 Python 读取 riscv-dv testlist，检查其为非空
  list，并检查 test name 没有重复。

接口关系：

* 被调用：`make ci_unit` 或 `make ci_lint`。
* 调用：Python unittest 和内联 Python YAML 检查。
* 共享状态：读取 `riscv_dv_extension/testlist.yaml`。

§7.2 lint、CSR、compliance 和 manual
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：顶层 Makefile 将这些流程委托给对应子目录或脚本。

关键代码（``Makefile:L525-L562``）：

.. code-block:: makefile

   lint:
           +@$(MAKE) -C lint lint

   lint_verible:
           +@$(MAKE) -C lint lint-verible

   lint_verilator:
           +@$(MAKE) -C lint lint-verilator

   run-csr-unit:
           +@$(MAKE) -C dv/uvm/cs_registers_eh2 run-csr-unit \
                   SIGNOFF_OUT=$(SIGNOFF_OUT)

逐段解释：

* 第 L525-L532 行：lint、verible lint 和 verilator lint 都委托到 `lint/Makefile`。
* 第 L539-L541 行：CSR unit test 委托到 `dv/uvm/cs_registers_eh2`，并透传
  `SIGNOFF_OUT`。
* 第 L549-L556 行：compliance 相关目标委托到 `dv/uvm/riscv_compliance`。
* 第 L558-L562 行：manual 调用 PDF 构建脚本；manual_html 调用 Sphinx HTML 构建。

接口关系：

* 被调用：对应顶层 make target。
* 调用：子目录 Makefile、`docs/build_manual_pdf.sh`、`sphinx-build`。
* 共享状态：这些内部流程由各自章节展开，本章只记录委托边界。

§7.3 formal、synthesis、LEC 和 clean
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 formal、综合、LEC 和清理命令委托给对应子系统。

关键代码（``Makefile:L567-L605``）：

.. code-block:: makefile

   formal:
           +@$(MAKE) -C dv/formal formal

   formal_clean:
           +@$(MAKE) -C dv/formal formal_clean

   synth:
           +@$(MAKE) -C syn syn-full

   syn_yosys:
           +@$(MAKE) -C syn syn-yosys

   syn_dc:
           +@$(MAKE) -C syn syn-dc

逐段解释：

* 第 L567-L571 行：formal 和 formal_clean 委托到 `dv/formal/Makefile`。
* 第 L576-L592 行：综合和 LEC 目标委托到 `syn/Makefile`，包括 full、Yosys、
  Design Compiler、LEC、block-level LEC 和 clean。
* 第 L597-L605 行：`clean` 删除 `$(BUILD_DIR)`；workspace 清理目标调用
  `scripts/clean_workspace.sh` 或其 dry-run 模式。

接口关系：

* 被调用：对应顶层 make target。
* 调用：子目录 Makefile 和 workspace 清理脚本。
* 共享状态：`clean` 只删除 build 目录；workspace 清理脚本的详细行为由顶层脚本文档覆盖。

§8 ``dv/uvm/core_eh2/Makefile`` — 本地开发入口
--------------------------------------------------------------------------------

core UVM 目录下的 `Makefile` 是 convenience wrapper。它不重新实现编译或回归，
而是切回项目根目录调用顶层 Makefile。

§8.1 变量透传和帮助
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 `dv/uvm/core_eh2` 目录内提供与顶层一致的变量名和帮助文本。

关键代码（``dv/uvm/core_eh2/Makefile:L16-L41``）：

.. code-block:: makefile

   SHELL := /bin/bash

   # Project root (relative to this Makefile)
   PROJ_ROOT := ../../..
   TB_DIR    := dv/uvm/core_eh2

   # Pass-through variables
   CONFIG     ?= default
   SEED       ?= 1
   TEST       ?= riscv_arithmetic_basic_test
   SIMULATOR   ?= vcs
   BINARY      ?=

逐段解释：

* 第 L16-L20 行：本地 Makefile 也使用 bash，并通过相对路径定义项目根目录。
* 第 L22-L36 行：变量与顶层 Makefile 对齐，包括 config、seed、test、simulator、
  binary、waves、coverage、iterations、parallel、RTL test、verbosity 和 LEC 参数。
* 第 L41 行：本地 phony targets 覆盖 help、compile、run、gen、smoke、nightly、
  weekly、signoff、signoff_quick、cov、clean 和 lint。

接口关系：

* 被调用：用户在 `dv/uvm/core_eh2` 目录执行 `make <target>`。
* 调用：顶层 `Makefile`。
* 共享状态：变量透传给顶层 make。

§8.2 本地 target 到顶层 target 的委托
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：将本地 compile/run/gen/regression/signoff/cov/clean 目标委托到项目根目录。

关键代码（``dv/uvm/core_eh2/Makefile:L67-L100``）：

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

逐段解释：

* 第 L67-L73 行：本地 compile 和 run 都切回 `$(PROJ_ROOT)`，run 先依赖 compile，
  再透传 test、seed、simulator、binary、waves、coverage、RTL test 和 verbosity。
* 第 L75-L86 行：gen、smoke、nightly、weekly 均委托顶层同名目标。
* 第 L88-L100 行：signoff、signoff_quick、cov、clean 也全部委托顶层 Makefile。

接口关系：

* 被调用：本地 Makefile targets。
* 调用：顶层 `make`。
* 共享状态：不直接写本地文件，输出由顶层目标决定。

§8.3 本地 ``lint`` — UVM 源文件枚举
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：快速列出 UVM 树下的 `.sv` 和 `.svh` 文件数量，不调用 simulator。

关键代码（``dv/uvm/core_eh2/Makefile:L102-L112``）：

.. code-block:: makefile

   # Quick syntax check - compile UVM sources only (no RTL)
   # Useful for catching SV syntax errors without full compilation
   lint:
           @echo "=== Linting UVM sources ==="
           @# List all .sv files in the UVM tree
           @find . -name "*.sv" -o -name "*.svh" | sort
           @echo ""
           @echo "Total UVM source files: $$(find . -name '*.sv' -o -name '*.svh' | wc -l)"
           @echo ""
           @echo "Note: Full syntax validation requires a simulator license."
           @echo "Use 'make compile' for actual compilation."

逐段解释：

* 第 L102-L104 行：注释和 target 名说明这是轻量 lint，不是 simulator 语法编译。
* 第 L105-L109 行：target 用 `find` 列出所有 `.sv` 和 `.svh`，再统计数量。
* 第 L111-L112 行：输出提示完整语法校验仍需 simulator license，并建议使用
  `make compile`。

接口关系：

* 被调用：`cd dv/uvm/core_eh2 && make lint`。
* 调用：shell `find`、`wc`。
* 共享状态：只读 UVM 源树，不写文件。

§9 ``wrapper.mk`` — metadata 驱动 staged flow
--------------------------------------------------------------------------------

`wrapper.mk` 是 staged flow 的实际执行器。顶层 Makefile 先创建 metadata，再调用
这个文件中的目标。它通过 `scripts/get_meta.mk` 从 metadata 中读取目录和测试集合。

§9.1 wrapper 的基础变量和 metadata 读取
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 staged targets、设置默认变量，并从 metadata 中覆盖目录和 test seed 列表。

关键代码（``dv/uvm/core_eh2/wrapper.mk:L4-L45``）：

.. code-block:: makefile

   all: collect_results

   .PHONY: core_config
   .PHONY: instr_gen_build
   .PHONY: instr_gen_run
   .PHONY: compile_riscvdv_tests
   .PHONY: compile_directed_tests
   .PHONY: rtl_tb_compile
   .PHONY: rtl_sim_run
   .PHONY: check_logs
   .PHONY: riscv_dv_fcov
   .PHONY: merge_cov
   .PHONY: collect_results

逐段解释：

* 第 L4 行：默认目标是 `collect_results`。
* 第 L6-L18 行：wrapper 的 phony targets 覆盖 core config、generator build/run、
  riscv-dv/directed 编译、TB 编译、RTL 仿真、日志检查、coverage、结果收集、
  signoff 和 dump。
* 第 L20-L35 行：设置 shell、项目根、输出目录、metadata 目录、simulator、test、
  seed、iterations、parallel、coverage、waves 和 `PYTHONPATH` 默认值。

接口关系：

* 被调用：顶层 `make run GOAL=<target>`。
* 调用：多个 Python 脚本和顶层 compile target。
* 共享状态：读取 `$(METADATA-DIR)/metadata.pkl`。

关键代码（``dv/uvm/core_eh2/wrapper.mk:L37-L64``）：

.. code-block:: makefile

   include scripts/util.mk
   -include scripts/get_meta.mk

   OUT-DIR := $(call get-meta,dir_out)
   TESTS-DIR := $(call get-meta,dir_tests)
   BUILD-DIR := $(call get-meta,dir_build)
   RUN-DIR := $(call get-meta,dir_run)
   METADATA-DIR := $(call get-meta,dir_metadata)

   riscvdv-ts := $(call get-meta,riscvdv_tds)
   directed-ts := $(call get-meta,directed_tds)

逐段解释：

* 第 L37-L38 行：wrapper 引入通用工具和 metadata accessor。
* 第 L40-L44 行：输出目录、tests 目录、build 目录、run 目录和 metadata 目录均从
  metadata 中读取。
* 第 L46-L47 行：riscv-dv 和 directed 的 `TEST.SEED` 列表也来自 metadata。
* 第 L49-L64 行：后续用 stem 和目录列表推导 assembly、binary、log、result 文件目标。

接口关系：

* 被调用：`wrapper.mk` 解析阶段。
* 调用：`get-meta` macro。
* 共享状态：metadata 是 staged flow 的单一事实来源。

§9.2 ``core_config`` 和 ``instr_gen_build``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：渲染 EH2 riscv-dv core setting，并构建随机指令生成器。

关键代码（``dv/uvm/core_eh2/wrapper.mk:L66-L85``）：

.. code-block:: makefile

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

逐段解释：

* 第 L66-L67 行：build、tests、metadata 三个目录目标用 `mkdir -p` 创建。
* 第 L69-L77 行：core config stamp 依赖模板渲染脚本，输出写到
  `riscv_dv_extension/riscv_core_setting.sv`。
* 第 L79-L85 行：`instr_gen_build` 调用 `build_instr_gen.py --dir-metadata`，
  成功后 touch stamp。

接口关系：

* 被调用：`instr_gen_build` 和 `instr_gen_run` 的前置依赖。
* 调用：`render_config_template.py`、`build_instr_gen.py`。
* 共享状态：写 riscv-dv core setting 和 metadata stamp。

§9.3 generator、编译、仿真和日志检查目标
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为每个 `TEST.SEED` 生成 assembly、编译 binary、运行 RTL simulation 并检查日志。

关键代码（``dv/uvm/core_eh2/wrapper.mk:L87-L130``）：

.. code-block:: makefile

   instr_gen_run: $(riscvdv-test-asms)
   $(riscvdv-test-asms): $(TESTS-DIR)/%/$(asm-stem): instr_gen_build scripts/run_instr_gen.py
           @echo Running randomized test generator for $*
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             python3 scripts/run_instr_gen.py \
               --dir-metadata $(METADATA-DIR) \
               --test-dot-seed $*
           $(verb)cp $$(find $(@D) -name '*.S' | sort | head -n 1) $@

逐段解释：

* 第 L87-L94 行：每个 riscv-dv test seed 通过 `run_instr_gen.py --dir-metadata`
  和 `--test-dot-seed` 生成 assembly，然后复制找到的 `.S` 到标准 `test.S`。
* 第 L96-L110 行：riscv-dv 和 directed 编译都调用 `compile_test.py --dir-metadata`
  与 `--test-dot-seed`，区别在于 riscv-dv 依赖生成出的 `test.S`。
* 第 L112-L122 行：RTL TB compile 通过顶层 `make compile GOAL=` 执行；RTL sim
  调用 `run_rtl.py`，并复制 sim log 到 wrapper 约定的 `rtl_sim.log`。
* 第 L124-L130 行：`check_logs.py` 从 metadata 和 `TEST.SEED` 生成 `trr.yaml`。

接口关系：

* 被调用：wrapper 默认 `collect_results` 依赖链。
* 调用：`run_instr_gen.py`、`compile_test.py`、顶层 `make compile`、`run_rtl.py`、
  `check_logs.py`。
* 共享状态：读 metadata；写 per-test `test.S`、`test.bin`、`rtl_sim.log`、`trr.yaml`。

§9.4 coverage、collect_results、signoff 和 dump
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供 staged flow 的 coverage、结果聚合、sign-off 和调试输出。

关键代码（``dv/uvm/core_eh2/wrapper.mk:L132-L164``）：

.. code-block:: makefile

   riscv_dv_fcov:
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             python3 scripts/get_fcov.py --dir-metadata $(METADATA-DIR) --simulator $(SIMULATOR)

   merge_cov:
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             python3 scripts/merge_cov.py --dir-metadata $(METADATA-DIR)

   collect_results: $(comp-results)
           @echo Collecting regression results
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             python3 scripts/collect_results.py \
               --dir-metadata $(METADATA-DIR) \

逐段解释：

* 第 L132-L138 行：coverage 目标分别调用 `get_fcov.py` 和 `merge_cov.py`。
* 第 L140-L145 行：`collect_results` 依赖所有 `comp-results`，然后调用
  `collect_results.py` 写回归汇总。
* 第 L147-L157 行：wrapper 中的 `signoff` 调用 `signoff.py`，输出到
  `$(OUT-DIR)/signoff`，并透传 profile、simulator、seed、parallel、iterations、
  coverage 和额外选项。
* 第 L159-L164 行：`dump` 打印关键路径和 test seed 列表。

接口关系：

* 被调用：`make run GOAL=riscv_dv_fcov`、`GOAL=merge_cov`、`GOAL=collect_results`
  或 `GOAL=signoff`。
* 调用：`get_fcov.py`、`merge_cov.py`、`collect_results.py`、`signoff.py`。
* 共享状态：读 per-test results；写 regression reports 和 sign-off 输出。

§10 ``scripts/riscvdv.mk`` — riscv-dv 片段
--------------------------------------------------------------------------------

该片段标注为 included by wrapper，但当前 `wrapper.mk` 已经内联了同类规则。本节按
文件自身内容解释其 target 语义。

§10.1 stamp 和变量依赖
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 core config、instruction generator build 和 generator run 的 stamp
目标。

关键代码（``dv/uvm/core_eh2/scripts/riscvdv.mk:L11-L34``）：

.. code-block:: makefile

   CORE-CONFIG-STAMP = $(METADATA-DIR)/core.config.stamp
   core_config: $(CORE-CONFIG-STAMP)
   core-config-var-deps := EH2_CONFIG

   INSTR-GEN-BUILD-STAMP = $(METADATA-DIR)/instr.gen.build.stamp
   instr_gen_build: $(METADATA-DIR)/instr.gen.build.stamp
   instr-gen-build-var-deps := SIMULATOR SIGNATURE_ADDR

   instr_gen_run: $(riscvdv-test-asms)

   riscvdv-test-asms +=
   riscvdv-test-bins +=

逐段解释：

* 第 L11-L17 行：core config 和 instr gen build 都以 metadata 目录下的 stamp 文件
  表示完成状态，并声明变量依赖列表。
* 第 L19-L22 行：`instr_gen_run` 依赖 `riscvdv-test-asms`；两个列表变量先初始化为空，
  等待包含者追加。
* 第 L28-L34 行：`vars-prereq` 用于根据变量变化触发 rebuild。

接口关系：

* 被调用：被 wrapper 类 Makefile include 时生效。
* 调用：`vars-prereq` macro。
* 共享状态：写 metadata stamp 和 build vars 文件。

§10.2 generator build 和 run
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 metadata 驱动 build_instr_gen 和 run_instr_gen。

关键代码（``dv/uvm/core_eh2/scripts/riscvdv.mk:L36-L57``）：

.. code-block:: makefile

   $(METADATA-DIR)/instr.gen.build.stamp: \
     $(instr-gen-build-vars-prereq) $(riscv-dv-files) $(CORE-CONFIG-STAMP) \
     scripts/build_instr_gen.py \
     | $(BUILD-DIR)
           @echo Building randomized test generator
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             scripts/build_instr_gen.py \
               --dir-metadata $(METADATA-DIR)
           $(call dump-vars,$(ig-build-vars-path),gen,$(instr-gen-build-var-deps))
           @touch $@

逐段解释：

* 第 L36-L39 行：generator build stamp 依赖变量变化、riscv-dv 文件、core config
  stamp 和 build 脚本。
* 第 L40-L45 行：recipe 调用 `scripts/build_instr_gen.py --dir-metadata`，dump 变量
  到 `.instr_gen.vars.mk`，并 touch stamp。
* 第 L51-L57 行：每个 `riscvdv-test-asms` 由 `run_instr_gen.py --dir-metadata`
  和 `--test-dot-seed $*` 生成。

接口关系：

* 被调用：`instr_gen_build`、`instr_gen_run`。
* 调用：`build_instr_gen.py`、`run_instr_gen.py`。
* 共享状态：读 metadata，写 generator stamp 和 per-test assembly。

§11 ``scripts/eh2_sim.mk`` — 仿真片段
--------------------------------------------------------------------------------

该片段定义 TB 编译、RTL sim、日志检查、coverage 和结果聚合 target。

§11.1 target 列表和 TB 编译 stamp
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明仿真相关高层 target，并用 stamp 表示 TB 编译完成。

关键代码（``dv/uvm/core_eh2/scripts/eh2_sim.mk:L11-L48``）：

.. code-block:: makefile

   TB-COMPILE-STAMP = $(METADATA-DIR)/tb.compile.stamp
   rtl_tb_compile: $(METADATA-DIR)/tb.compile.stamp
   rtl-tb-compile-var-deps := SIMULATOR COV WAVES

   rtl_sim_run: $(rtl-sim-logs)

   check_logs: $(comp-results)

   FCOV-STAMP = $(METADATA-DIR)/fcov.stamp
   riscv_dv_fcov: $(METADATA-DIR)/fcov.stamp

逐段解释：

* 第 L11-L17 行：TB compile、RTL sim 和 log check 目标分别依赖 stamp 或 per-test
  文件集合。
* 第 L19-L26 行：functional coverage、coverage merge 和 collect results 也都通过
  metadata 目录下的 stamp 文件表达完成状态。
* 第 L35-L48 行：TB compile stamp 依赖变量变化、Verilog/C++/riscv-dv 文件、
  `compile_tb.py` 和 simulator YAML；recipe 调用 `scripts/compile_tb.py`。

接口关系：

* 被调用：include 该片段的 wrapper。
* 调用：`compile_tb.py`。
* 共享状态：写 `tb.compile.stamp` 和 `.tb.vars.mk`。

§11.2 RTL sim、check_logs、coverage 和 collect
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 per-test binary 转换为 sim log，再转换为 `trr.yaml`，最后聚合报告。

关键代码（``dv/uvm/core_eh2/scripts/eh2_sim.mk:L53-L106``）：

.. code-block:: makefile

   $(rtl-sim-logs): $(TESTS-DIR)/%/$(rtl-sim-logfile): \
     $(TB-COMPILE-STAMP) $(TESTS-DIR)/%/test.bin scripts/run_rtl.py
           @echo Running RTL simulation at $(@D)
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             scripts/run_rtl.py \
               --dir-metadata $(METADATA-DIR) \
               --test-dot-seed $*

   $(comp-results): $(TESTS-DIR)/%/trr.yaml: \
     $(TESTS-DIR)/%/$(rtl-sim-logfile) scripts/check_logs.py

逐段解释：

* 第 L53-L60 行：每个 RTL sim log 依赖 TB compile stamp、per-test `test.bin`
  和 `run_rtl.py`，并通过 metadata/test-dot-seed 执行仿真。
* 第 L64-L70 行：每个 `trr.yaml` 依赖 sim log 和 `check_logs.py`，通过 metadata
  和 test-dot-seed 检查日志。
* 第 L75-L83 行：`COV=1` 时执行 `get_fcov.py`，否则只 touch coverage stamp。
* 第 L88-L96 行：`COV=1` 时执行 `merge_cov.py`，否则只 touch merge stamp。
* 第 L101-L106 行：结果聚合调用 `collect_results.py --dir-metadata`。

接口关系：

* 被调用：`rtl_sim_run`、`check_logs`、`riscv_dv_fcov`、`merge_cov`、`collect_results`。
* 调用：`run_rtl.py`、`check_logs.py`、`get_fcov.py`、`merge_cov.py`、
  `collect_results.py`。
* 共享状态：读 per-test binary/log；写 `trr.yaml`、coverage stamp、regression report。

§12 ``get_meta.mk`` 和 ``util.mk``
--------------------------------------------------------------------------------

§12.1 ``get_meta.mk`` — metadata 字段读取宏
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：通过 `metadata.py --op print_field` 从 metadata 中读取字段。

关键代码（``dv/uvm/core_eh2/scripts/get_meta.mk:L4-L12``）：

.. code-block:: makefile

   define get-metadata-variable
       env PYTHONPATH=$(PYTHONPATH) python3 ./scripts/metadata.py \
       --op "print_field" \
       --dir-metadata $(METADATA-DIR) \
       --field $(1)
   endef
   define get-meta
       $(shell $(call get-metadata-variable,$(1)))
   endef

逐段解释：

* 第 L4-L9 行：`get-metadata-variable` 宏构造 Python 命令，读取指定字段。
* 第 L10-L12 行：`get-meta` 用 `$(shell ...)` 执行上面的命令，并把输出作为
  make 变量值。

接口关系：

* 被调用：`wrapper.mk` 的 `$(call get-meta,...)`。
* 调用：`metadata.py --op print_field`。
* 共享状态：读 metadata 目录。

§12.2 ``util.mk`` — verbose 和 dump-vars
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 `VERBOSE` 控制命令回显，并提供变量 dump 目标。

关键代码（``dv/uvm/core_eh2/scripts/util.mk:L4-L15``）：

.. code-block:: makefile

   ifeq ($(VERBOSE),1)
   verb :=
   else
   verb := @
   endif

   .PHONY: dump-vars
   dump-vars:
           @echo "OUT-DIR=$(OUT-DIR)"
           @echo "METADATA-DIR=$(METADATA-DIR)"
           @echo "SIMULATOR=$(SIMULATOR)"
           @echo "TEST=$(TEST)"

逐段解释：

* 第 L4-L8 行：`VERBOSE=1` 时 `verb` 为空，命令会回显；否则 `verb` 为 `@`，
  recipe 中用 `$(verb)` 前缀隐藏命令。
* 第 L10-L15 行：`dump-vars` 打印输出目录、metadata 目录、simulator 和 test。

接口关系：

* 被调用：wrapper 和脚本 `.mk` 片段中的 recipe。
* 调用：shell `echo`。
* 共享状态：只读 make 变量。

§13 调用矩阵和输出边界
--------------------------------------------------------------------------------

§13.1 主要调用矩阵
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. list-table::
   :header-rows: 1
   :widths: 24 34 42

   * - Make 入口
     - 下游命令
     - 主要输出
   * - ``make compile``
     - ``compile_$(SIMULATOR)``
     - ``build/simv``、``build/compile.log``
   * - ``make cosim``
     - ``g++``、``ar``
     - ``build/libcosim.so``、``build/spike_objs``
   * - ``make run``
     - ``build/simv``
     - ``build/<TEST>_<SEED>/sim.log``
   * - ``make gen``
     - ``run_instr_gen.py``
     - ``build/<TEST>_<SEED>/`` 下的 riscv-dv 产物
   * - ``make regress``
     - ``run_regress.py``
     - ``build/regression``
   * - ``make signoff``
     - ``signoff.py``
     - ``$(SIGNOFF_OUT)/signoff_status.json``、``signoff_report.md``
   * - ``make html_report``
     - ``gen_html_report.py``
     - ``$(HTML_REPORT_OUT)``
   * - ``make run GOAL=collect_results``
     - ``metadata.py``、``wrapper.mk``、``collect_results.py``
     - ``$(OUT-DIR)`` 与 ``$(METADATA-DIR)``

§13.2 常用命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   make compile SIMULATOR=vcs
   make run TEST=riscv_arithmetic_basic_test SEED=1 BINARY=tests/asm/smoke.hex
   make gen TEST=riscv_arithmetic_basic_test SEED=1
   make regress PARALLEL=4 COV=1
   make signoff PROFILE=full COV=1 PARALLEL=4
   make signoff_gate SIGNOFF_OUT=build/signoff
   make run GOAL=collect_results OUT=out TEST=all

逐段解释：

* 第一行触发 simulator 编译。
* 第二行直接运行一个已有 binary。
* 第三行只生成 riscv-dv assembly。
* 第四行运行 Python regression，并启用 coverage。
* 第五行运行 full profile sign-off，并把 coverage gate 打开。
* 第六行只评估已有 sign-off 输出。
* 第七行进入 staged flow，先创建 metadata，再由 `wrapper.mk` 收集结果。

§13.3 输出目录和清理边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Makefile 中直接声明的可再生输出主要位于 `build/`、`out/` 或 `$(SIGNOFF_OUT)`：

* `compile_vcs` 写 `build/simv`、`build/csrc`、`build/compile.log`。
* `$(LIBCOSIM)` 写 `build/libcosim.so` 和 `build/spike_objs`。
* `run` 写 `build/<TEST>_<SEED>/sim.log`。
* `regress` 和 `run_regress` 写 `build/regression` 或 `$(OUT)` 指定目录。
* `signoff` 写 `$(SIGNOFF_OUT)`。
* `clean` 只删除 `$(BUILD_DIR)`，即默认 `build`。
* `clean_cov` 只删除 build 目录中的 coverage DB 和 coverage report。

这些目录是仿真和报告产物，不是源码；但本章不修改任何 `build/`、`out/`、
`syn/build/` 或 formal build 目录。

§14 参考资料
--------------------------------------------------------------------------------

源文件绝对路径：

* ``/home/host/eh2-veri/Makefile``
* ``/home/host/eh2-veri/env.mk``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/Makefile``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/wrapper.mk``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/get_meta.mk``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/util.mk``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/riscvdv.mk``
* ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/eh2_sim.mk``

关联 ADR：

* :ref:`adr-0011` — Compliance framework；顶层 `compliance`、`compliance-all`、
  `compliance-compile` 委托到 RISC-V compliance 子目录。
* :ref:`adr-0012` — Formal strategy；顶层 `formal` 和 `formal_clean` 委托到
  `dv/formal`。
* :ref:`adr-0013` — Synthesis toolchain；顶层 `synth`、`syn_yosys`、`syn_dc`
  委托到 `syn`。
* :ref:`adr-0019` — LEC tool-version limitation；`signoff` 支持
  `LEC_KNOWN_LIMITED=1`。
* :ref:`adr-0020` — Block-level LEC；`signoff` 支持 `LEC_BLOCKLEVEL=1` 和
  `LEC_SUMMARY_PATH`。

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

§15  v2-19 顶层 ``Makefile`` 全文段落级精读
--------------------------------------------------------------------------------

v2-19 开始把“引用过源码”升级为“全文源码能被审计到”。顶层 ``Makefile`` 是
EH2 验证平台的总调度入口，不能只看 ``compile``、``smoke`` 或 ``signoff`` 的局部
片段；否则会漏掉 staged regression、coverage 配置、NC 备选路径、demo、clean
安全网和 deprecated alias 的真实行为。

.. literalinclude:: ../../../../Makefile
   :language: text
   :linenos:
   :caption: Makefile:全文

逐段精读：

* L1-L22：文件头说明这是顶层调度 Makefile，并在最前面包含 ``env.mk``。
  这一段建立全局语义：默认 simulator 是 VCS，核心 target 分组管理，clean 有
  保留策略，用户通过 ``make help`` 查看入口。
* L23-L76：Ibex-style staged entry。只要 ``GOAL`` 非空，Make 就创建
  ``OUT-DIR``、``METADATA-DIR``，导出 ``PYTHONPATH``，调用 ``metadata.py`` 后
  委托 ``dv/uvm/core_eh2/wrapper.mk``。这是保留给分阶段回归框架的入口，与后面
  人工 target 分支互斥。
* L78-L120：普通 target 分支的目录、filelist 和 clean preserve 集合。``TB_DIR``、
  ``SCRIPTS_DIR``、``RTL_F``、``TB_F`` 等变量把顶层命令映射到 UVM 工程树；
  ``CLEAN_PRESERVE_BUILD`` 和 ``CLEAN_PRESERVE_FIND`` 防止误删长耗时证据目录。
* L121-L173：用户可覆盖变量。``CONFIG``、``SEED``、``TESTLIST``、``SIMULATOR``、
  ``COV``、``PROFILE``、``SIGNOFF_OUT``、``LEC_BLOCKLEVEL``、``SCOPE`` 等都是
  命令行契约；文档中的命令示例必须使用这些真实名字。
* L174-L217：仿真器与覆盖率配置。VCS 采用 ``line+tgl+assert+fsm+branch`` 五维
  coverage、``cover.cfg`` DUT-only scope、``cov_fsm.cfg`` 和 reset filter；NC 路径
  使用 ``cov_full_nc.ccf`` 与 ``cov_work``，作为完整备选 simulator 和 waveform
  debug 通道。
* L218-L245：testlist 路由与 ``.PHONY`` 列表。``TESTLIST=directed`` 选择
  ``directed_testlist.yaml``，否则默认 riscv-dv extension testlist；``.PHONY``
  明确暴露 help/asm/cosim/compile/smoke/regress/compliance/formal/synth/signoff/demo
  等核心入口。
* L246-L945：中文 ``HELP_TEXT``。这一大段不是注释垃圾，而是用户界面：它解释 15 个
  核心 target、常用变量、VCS/NC 产物隔离、signoff 与 demo 差异、formal/syn 数据来源、
  clean safety net 和 deprecated alias。任何修改 target 名时都必须同步这段帮助文本。
* L946-L985：``help`` target 和 cosim 编译变量。``LIBCOSIM``、``SPIKE_*``、
  ``SVDPI_INCLUDE`` 决定 Spike DPI shared library 如何编译；``NO_COSIM=1`` 只影响
  cosim library 依赖，不应改变其它 regression 的 Make 语义。
* L986-L1022：``cosim`` recipe。该段创建 build 目录、收集 Spike include/lib 路径、
  调用 C++ 编译器并链接 ``libcosim.so``。失败时先看 ``build/libcosim.so`` 生成日志和
  Spike 安装路径，而不是改 UVM scoreboard。
* L1023-L1114：``asm``、``compile_vcs``、``compile_nc``、``compile_xlm``。VCS 编译
  读取 ``eh2_rtl.f``、``eh2_shared.f``、``eh2_tb.f``，加上 UVM、DPI 和 coverage
  option；NC/Xcelium 路径用各自命令模板保持兼容。
* L1115-L1152：``smoke``、``regress``、``compliance``。``smoke`` 先编译 asm，再跑
  单测；``regress`` 调用 ``run_regress.py``；``compliance`` 下钻到
  ``dv/uvm/riscv_compliance``，不在顶层重复实现 compliance framework。
* L1153-L1201：``wave_nc`` 交互式波形 debug。该 target 针对单个测试启动 NC/SimVision
  交互调试，输出语义与 batch smoke/regress 分开，不能把它当作 release gate。
* L1202-L1232：``lint``、``formal``、``synth``。顶层只做编排，下游分别进入
  ``lint``、``dv/formal``、``syn``；这保证 Verible/Verilator、IFV/Symbiyosys、
  DC/Formality 的工具边界不混杂。
* L1233-L1295：``signoff`` 和 ``signoff_replay``。``SIGNOFF_LEC_OPTS`` 根据
  ``syn/build/lec_summary.txt`` 是否存在选择 block-level LEC 证据或 limited 标记；
  ``signoff.py`` 负责 9-stage gate、25% fail-rate ceiling、coverage 和 waiver 判断。
* L1296-L1337：``demo``。demo 先运行 signoff，再显式调用 synth/DC/LEC，为
  2026-05-19 01:02 那次 9/9 PASS、102/104、LEC 31635/31635 的端到端证据提供
  Make 层入口。
* L1338-L1349：``manual``。该 target 下钻到 ``docs/sphinx_cn`` 构建中文 Sphinx 手册，
  本章本身就是该 target 的主要维护对象。
* L1350-L1434：``clean``。默认 clean 会根据 ``SCOPE``、``MODE``、``DRY_RUN`` 和
  ``FORCE`` 控制删除范围；没有 ``FORCE=1`` 时会保留 sign-off 证据、cosim library、
  archive links 和其它长耗时产物。
* L1435-L1569：deprecated alias。``run``、``gen``、``nightly``、``signoff_quick``、
  ``html_report``、``cov``、``syn_dc``、``block_lec``、``run-csr-unit``、``ci_*``
  等旧入口会打印提示并转发到新 target，保证旧 CI 或旧文档命令仍可定位到当前流程。
* L1570：普通 target 分支结束。这个 ``endif`` 与 L30 的 staged ``ifneq`` 配对，
  是顶层 Makefile 两套入口不会互相执行的结构边界。
