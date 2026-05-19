.. _system_requirements:
.. _03_integration/system_requirements:

系统与工具链需求
================

:status: draft
:source: README.md; env.sh; docs/requirements-docs.txt; Makefile; lint/Makefile; dv/formal/Makefile; syn/Makefile; dv/uvm/core_eh2/scripts/signoff.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章边界
-------------

本章不写无法从仓库源文件验证的硬件最低规格，也不把工具版本号扩展成安装指南。
它只回答一个问题：当前代码在不同流程中实际检查、调用或假定哪些外部工具。

需求可以按流程拆成 6 类：

.. code-block:: bash

   quick smoke / regress
      -> python3, GNU Make, vcs|xrun|vsim or existing build/simv
      -> riscv32-unknown-elf-gcc / objcopy when directed/cosim/riscvdv is included

   cosim
      -> Spike install tree, VCS_HOME, g++ used by SPIKE_CXX

   lint / formal / synth / docs
      -> verible-verilog-lint, verilator
      -> ifv
      -> dc_shell, fm_shell, optional yosys
      -> sphinx-build, optional xelatex

逐段解释：

* 第 1-3 行：quick smoke 和普通回归依赖 Python、Make 和 simulator。`signoff.py`
  的 precheck 允许已有 `build/simv` 代替当前 PATH 中的 simulator 命令。
* 第 4-5 行：directed、cosim、riscv-dv stage 需要 RISC-V bare-metal 编译工具。
  这来自 `signoff.py` 对 `riscv32-unknown-elf-gcc` 和 `riscv32-unknown-elf-objcopy`
  的检查。
* 第 7-8 行：cosim 编译需要 Spike 安装树、`VCS_HOME` include 目录和 `SPIKE_CXX`
  指向的 C++ 编译器。
* 第 10-14 行：lint、formal、synth 和文档构建分别调用不同工具。它们不是所有
  quick start 命令的前置条件，而是对应流程的前置条件。

接口关系：

* 被调用：:ref:`getting_started`、:ref:`build_flow`、:ref:`signoff_flow`。
* 调用：不调用源代码；本章根据 Makefile 和 Python precheck 归纳依赖。
* 共享状态：`PATH`、`GCC_PREFIX`、`SPIKE_INSTALL`、`VCS_HOME`、`build/simv`。

§2  README 中的 full sign-off 工具清单
---------------------------------------

仓库根 `README.md` 给出 full sign-off 的总需求。该清单是文字说明，不替代各个
Makefile recipe 的实际检查。

关键代码（`README.md:L411-L427`）：

.. code-block:: bash

   ## Toolchain Requirements

   The full platform assumes access to commercial EDA tools and a RISC-V software
   toolchain.

   Required for full sign-off:

   - Synopsys VCS for SystemVerilog simulation;
   - Synopsys Design Compiler for synthesis inputs used by the LEC flow;
   - Synopsys Formality for block-level LEC;
   - Cadence IFV 15.20 for the current formal proof evidence;
   - Spike built with the EH2 cosim DPI integration;
   - `riscv32-unknown-elf-gcc`;
   - `riscv32-unknown-elf-objcopy`;
   - Python 3;
   - `pyyaml`;
   - GNU Make.

逐段解释：

* 第 411-414 行：README 明确把这些要求限定在 full platform 和 full sign-off
  场景，不是运行所有局部命令的统一最低门槛。
* 第 418-421 行：商业 EDA 工具包括 VCS、Design Compiler、Formality 和 IFV。
  README 只对 IFV 写出 `15.20`，因此本章不为 VCS、DC 或 Formality 补写版本号。
* 第 422 行：Spike 需求被描述为“built with the EH2 cosim DPI integration”。
  这和顶层 `Makefile` 中的 `SPIKE_INSTALL`、`libcosim.so` 构建规则对应。
* 第 423-427 行：软件工具链需求包括 RISC-V GCC/objcopy、Python 3、`pyyaml` 和
  GNU Make。

接口关系：

* 被调用：full sign-off 准备 checklist。
* 调用：无代码调用；这是 README 的人工入口说明。
* 共享状态：与下游 `Makefile`、`signoff.py` 对应的环境变量和 PATH。

§3  环境变量：`env.sh`
----------------------

`env.sh` 只设置环境变量和 PATH，不检查工具是否真的存在。它是 quick start 的入口脚本，
但不是环境验收工具。

关键代码（`env.sh:L5-L19`）：

.. code-block:: bash

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

* 第 5-7 行：`EH2_VERIF_ROOT` 由脚本所在目录计算得到，指向当前验证仓库根。
* 第 8-13 行：`RV_ROOT` 和 `GCC_PREFIX` 使用绝对路径。`PATH` 被追加
  `${GCC_PREFIX}/bin`，这会影响 shell 后续查找 `riscv32-unknown-elf-gcc`
  与 `riscv32-unknown-elf-objcopy`。
* 第 15-16 行：`QEMU_BIN` 指向一个外部 qemu 路径。当前 quick start 和 sign-off
  precheck 没有直接检查这个变量。
* 第 18-19 行：脚本设置 `EH2_SIMULATOR="vcs"`。顶层 `Makefile` 的实际选择变量是
  `SIMULATOR`，因此需要用 `make ... SIMULATOR=vcs|xlm` 明确覆盖时，应传 Make 变量。

接口关系：

* 被调用：`source env.sh`。
* 调用：无外部命令检查；只执行 shell 展开与 `export`。
* 共享状态：`EH2_VERIF_ROOT`、`RV_ROOT`、`GCC_PREFIX`、`PATH`、`QEMU_BIN`、
  `EH2_SIMULATOR`。

§4  sign-off precheck 实际检查项
---------------------------------

`signoff.py` 的 `precheck()` 是最接近“环境验收”的代码路径。它不检查所有工具，
只检查当前 profile/stage 需要的关键输入。

关键代码（`signoff.py:L137-L165`）：

.. code-block:: python

   def tool_exists(tool: str) -> bool:
       if os.path.isabs(tool):
           return os.path.exists(tool)
       return shutil.which(tool) is not None


   def resolve_gcc_prefix() -> str:
       env_prefix = os.environ.get("GCC_PREFIX", "").strip()
       if env_prefix:
           candidate = Path(env_prefix) / "bin" / "riscv32-unknown-elf-gcc"
           if candidate.exists():
               return str(candidate)[:-len("-gcc")]
       return "riscv32-unknown-elf"

逐段解释：

* 第 137-140 行：`tool_exists()` 对绝对路径使用 `os.path.exists()`，对普通命令名使用
  `shutil.which()`。因此 precheck 的结果受 PATH 影响。
* 第 143-149 行：`resolve_gcc_prefix()` 优先读取环境变量 `GCC_PREFIX`。当
  `${GCC_PREFIX}/bin/riscv32-unknown-elf-gcc` 存在时，返回不带 `-gcc`
  后缀的 prefix；否则回退到 `riscv32-unknown-elf`。

关键代码（`signoff.py:L158-L180`）：

.. code-block:: python

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

逐段解释：

* 第 158-160 行：precheck 先确认 EH2 根目录、RTL filelist 和 TB filelist 存在。
* 第 162-165 行：simulator 名到命令名的映射是 `vcs -> vcs`、`xlm -> xrun`、
  `questa -> vsim`。如果 `build/simv` 已存在，precheck 接受已有仿真可执行文件。
* 第 167-171 行：只有当 stage 包含 `directed`、`cosim` 或 `riscvdv` 时，
  才检查 RISC-V GCC 和 objcopy。

关键代码（`signoff.py:L173-L193`）：

.. code-block:: python

       if "riscvdv" in stages:
           riscv_dv_run = EH2_ROOT / "vendor" / "google_riscv-dv" / "run.py"
           add("riscv_dv", riscv_dv_run.exists(), str(riscv_dv_run))

       if "cosim" in stages:
           libcosim = EH2_ROOT / "build" / "libcosim.so"
           add("spike_cosim_dpi", libcosim.exists(),
               "{} (run `make cosim` if missing)".format(libcosim))

       cfg_path = EH2_ROOT / "eh2_configs.yaml"
       if cfg_path.exists():
           try:
               cfg = _load_yaml(cfg_path) or {}

逐段解释：

* 第 173-175 行：`riscvdv` stage 需要 `vendor/google_riscv-dv/run.py` 存在。
* 第 177-180 行：`cosim` stage 需要 `build/libcosim.so` 存在；缺失时 detail 字符串明确提示
  运行 `make cosim`。
* 第 182-185 行：precheck 还读取 `eh2_configs.yaml`，后续会检查 default profile 的
  `NUM_THREADS`。该检查是配置一致性，不是外部工具需求。

接口关系：

* 被调用：`make signoff` 间接调用 `signoff.py`。
* 调用：`os.path.exists()`、`shutil.which()`、YAML 读取。
* 共享状态：`GCC_PREFIX`、`PATH`、`build/simv`、`build/libcosim.so`、
  `vendor/google_riscv-dv/run.py`、`eh2_configs.yaml`。

§5  仿真器与编译入口
---------------------

顶层 `Makefile` 的仿真器选择由 `SIMULATOR` 控制。当前直接编译 target 有 VCS
和 Xcelium；`signoff.py` 的 CLI choices 还接受 `questa`，但顶层 `Makefile`
没有 `compile_questa` 规则。

关键代码（`Makefile:L775-L821`）：

.. code-block:: bash

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

逐段解释：

* 第 775 行：`compile` 展开为 `compile_$(SIMULATOR)`。因此 `SIMULATOR=vcs`
  进入 `compile_vcs`，`SIMULATOR=xlm` 进入 `compile_xlm`。
* 第 777-783 行：`compile_vcs` 需要 `vcs` 命令，使用 UVM 1.2、SystemVerilog、
  SVA assertion 和 `+define+GTLSIM`。
* 第 784-790 行：VCS 编译显式加入 snapshot、AXI4、trace、irq、jtag、cosim
  agent 的 include 目录。

关键代码（`Makefile:L805-L821`）：

.. code-block:: makefile

   compile_xlm: | $(BUILD_DIR)
   	@echo "=== [compile] Xcelium UVM testbench ==="
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

逐段解释：

* 第 805-807 行：Xcelium 路径在 `build/` 目录下运行 `$(XLM)`，顶层默认把
  `XLM` 设为 `xrun`。
* 第 808-818 行：Xcelium 路径读取同一组 defines、include 目录、filelist 和 TB 顶层。
* 第 819-820 行：日志写入 `build/compile.log`；`COV=1` 时附加 Xcelium coverage
  相关参数。

接口关系：

* 被调用：`make compile`、`make smoke`、`make regress`。
* 调用：`vcs` 或 `xrun`。
* 共享状态：`SIMULATOR`、`COV`、`NO_COSIM`、`build/simv`、`build/compile.log`。

§6  Spike DPI 与 cosim 需求
----------------------------

cosim 不是所有仿真的前置条件。`NO_COSIM=1` 可以跳过 VCS 编译时的 cosim 链接，
但 `cosim` stage 仍需要 `build/libcosim.so`。

关键代码（`Makefile:L720-L762`）：

.. code-block:: makefile

   COMPILE_LIBCOSIM_LINK :=
   else
   COMPILE_LIBCOSIM_DEP := $(LIBCOSIM)
   COMPILE_LIBCOSIM_LINK := $(CURDIR)/$(LIBCOSIM)
   endif

   SPIKE_DIR     ?= /home/host/spike-cosim
   SPIKE_INSTALL ?= $(SPIKE_DIR)/install
   SPIKE_CXX     ?= /home/Xilinx/Vivado/2019.1/tps/lnx64/gcc-6.2.0/bin/g++
   SPIKE_CXXFLAGS ?= -std=c++17 -static-libstdc++
   SPIKE_BUILD   ?= $(BUILD_DIR)/spike_objs

逐段解释：

* 第 720-724 行：当未跳过 cosim 时，VCS 编译依赖 `$(LIBCOSIM)`，并把当前目录下的
  `libcosim.so` 加入链接参数。
* 第 726-730 行：Spike 相关默认变量包括 `SPIKE_DIR`、`SPIKE_INSTALL`、
  `SPIKE_CXX`、`SPIKE_CXXFLAGS` 和 `SPIKE_BUILD`。这些是 Makefile 默认值，
  可由命令行覆盖。

关键代码（`Makefile:L734-L762`）：

.. code-block:: makefile

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

逐段解释：

* 第 734-735 行：`libcosim.so` 的源码依赖来自 `dv/cosim` 目录中的 C++ 与头文件。
* 第 736-740 行：Makefile 只检查 `SPIKE_INSTALL` 是否为目录；不存在就退出，并提示
  设置 Spike 路径或使用 `NO_COSIM=1`。
* 第 741-748 行：构建规则进入 `SPIKE_BUILD`，从 Spike 安装目录解包多个静态库。
* 第 750-761 行：共享库链接还使用 `VCS_HOME/include`、Spike include 目录、
  `libsoftfloat.a`、`pthread` 和 `dl`。

接口关系：

* 被调用：`make cosim`、`make compile` 默认 VCS 路径、cosim sign-off stage。
* 调用：`ar`、`SPIKE_CXX`、Spike 静态库、VCS DPI include。
* 共享状态：`SPIKE_DIR`、`SPIKE_INSTALL`、`SPIKE_CXX`、`VCS_HOME`、
  `build/libcosim.so`、`build/spike_objs`。

§7  Lint、formal、synthesis 和 LEC 工具
---------------------------------------

这些工具不是 quick smoke 的前置条件，但 full sign-off 或对应 flow 会调用它们。

关键代码（`lint/Makefile:L12-L18`）：

.. code-block:: makefile

   VERIBLE  ?= verible-verilog-lint
   VERILATOR ?= verilator

   VERIBLE_RULES  := $(LINT_DIR)/verible/verible.rules
   VERIBLE_WAIVERS := $(LINT_DIR)/verible/waivers.vbl
   VERILATOR_WAIVER := $(LINT_DIR)/verilator/verilator_waiver.vlt
   VERILATOR_CONFIG := $(LINT_DIR)/verilator/verilator-config.vlt

逐段解释：

* 第 12-13 行：lint 默认命令名是 `verible-verilog-lint` 和 `verilator`，都可通过
  Make 变量覆盖。
* 第 15-18 行：Verible 和 Verilator 都使用仓库内规则或 waiver/config 文件；工具可执行文件仍需在
  PATH 中可见，或通过变量指向可执行文件。

关键代码（`lint/Makefile:L35-L79`）：

.. code-block:: makefile

   lint-verible: $(BUILD_DIR)
   	@echo "=== Verible SystemVerilog Lint ==="
   	@> $(BUILD_DIR)/verible_errors.txt
   	@if command -v $(VERIBLE) >/dev/null 2>&1; then \
   		lint_errors=0; \
   		for f in $(ALL_SV); do \
   			$(VERIBLE) --rules_config=$(VERIBLE_RULES) \
   				--waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | tee -a $(BUILD_DIR)/verible.log; \
   			if [ $${PIPESTATUS[0]} -ne 0 ]; then \

逐段解释：

* 第 35-38 行：Verible lint 先创建 build 目录和错误文件，再用 `command -v`
  检查命令是否存在。
* 第 40-47 行：规则遍历 `ALL_SV`，把每个文件的输出追加到 `lint/build/verible.log`，
  再抽取错误行。
* 同一 Makefile 的 Verilator 路径也先 `command -v $(VERILATOR)`，缺失时打印 warning
  并跳过，而不是直接失败。

关键代码（`dv/formal/Makefile:L1-L24`）：

.. code-block:: makefile

   # EH2 formal verification flow using Cadence Incisive Formal Verifier.

   SHELL := /bin/bash

   BUILD_DIR := build
   FILELIST  := ifv_filelist.f
   SCRIPTS   := scripts
   IFV       := ifv
   IFV_TOP   := eh2_veer

   # IFV 15.20 needs a high loop unroll limit for EH2 IFU/PIC generated muxes.
   # One EXU data-dependent loop still remains tool-limited and is documented in
   # known_fails.md, but this option avoids extra IFU/PIC black-boxing.
   IFV_COMPILE_OPTS := +top+$(IFV_TOP) +loop_unroll_size+2048

逐段解释：

* 第 1 行：formal flow 明确使用 Cadence Incisive Formal Verifier。
* 第 5-9 行：默认 IFV 命令名是 `ifv`，top 是 `eh2_veer`，filelist 是
  `ifv_filelist.f`。
* 第 11-14 行：注释只对 IFV 15.20 写出 loop unroll 背景；本章不把它扩展为其它
  IFV 版本的兼容性承诺。

关键代码（`syn/Makefile:L106-L158`）：

.. code-block:: makefile

   syn-dc: $(WRAPPER)
   	@echo "=== Design Compiler Synthesis ==="
   	@echo "  wrapper: $(WRAPPER)"
   	@if command -v dc_shell >/dev/null 2>&1; then \
   		echo "  Running dc_shell..."; \
   		mkdir -p $(BUILD_DIR)/dc_run; \
   		cd $(BUILD_DIR)/dc_run && dc_shell -f $(SYN_DIR)/scripts/dc_synth.tcl; \
   	else \
   		echo "ERROR: dc_shell not found. Install Synopsys Design Compiler."; \
   		echo "  The SDC constraints file is at $(SYN_DIR)/nangate/eh2_nangate.sdc"; \

逐段解释：

* 第 106-118 行：Design Compiler 路径要求 `dc_shell` 在 PATH 中可见；缺失时退出。
* `syn/Makefile:L120-L158` 的 block-level LEC 还检查 `dc_shell` 和 `fm_shell`，
  然后按模块运行 DC 和 Formality 脚本，并调用 `lec_summary.py` 汇总。

接口关系：

* 被调用：`make lint`、`make formal`、`make synth`、full sign-off 的 lint/formal/syn stage。
* 调用：`verible-verilog-lint`、`verilator`、`ifv`、`dc_shell`、`fm_shell`、
  `yosys`、`python3`。
* 共享状态：`lint/build/`、`dv/formal/build/`、`syn/build/`。

§8  文档构建依赖
-----------------

Sphinx 手册依赖单独写在 `docs/requirements-docs.txt`。顶层 `make manual` 调用
`sphinx-build`，PDF 还需要 `xelatex`。

关键代码（`docs/requirements-docs.txt:L1-L8`）：

.. code-block:: bash

   # EH2 UVM 验证平台中文手册依赖
   # 安装：pip install --user -r docs/requirements-docs.txt
   # Python 推荐 3.10+（rinohtype 0.5.x 在 3.6 importlib_metadata 上有兼容问题）

   sphinx>=7.0
   sphinx-tabs>=3.4.5
   sphinx-copybutton>=0.5.0
   rinohtype>=0.5.5

逐段解释：

* 第 1-3 行：requirements 文件建议 Python 3.10+，原因是 `rinohtype 0.5.x`
  在 Python 3.6 的 `importlib_metadata` 上有兼容问题。
* 第 5-8 行：文档 Python 包需求包含 `sphinx>=7.0`、`sphinx-tabs>=3.4.5`、
  `sphinx-copybutton>=0.5.0` 和 `rinohtype>=0.5.5`。当前运行环境若使用
  Sphinx 4.5.0，也只能说明本地构建工具链状态，不改变 requirements 文件的内容。
  `sphinx-tabs` 对应 VCS/NC 分流 tab，`sphinx-copybutton` 对应 bash 命令复制按钮。

关键代码（`Makefile:L495-L507`）：

.. code-block:: bash

     make manual
           用途：构建 Sphinx 中文手册
           耗时：HTML ~30 秒；PDF ~2 分钟
           依赖：sphinx-build；PDF 还需 xelatex
           变量：
             FORMAT=html|pdf                 格式（默认 html）
           产出：
             docs/sphinx_cn/build/html/index.html
             docs/sphinx_cn/build/pdf/EH2-Verification-Manual.pdf （FORMAT=pdf）

逐段解释：

* 第 495-498 行：顶层 help 明确 `make manual` 依赖 `sphinx-build`，PDF 还需要 `xelatex`。
* 第 499-507 行：`FORMAT` 选择 HTML 或 PDF，产物分别落在 `docs/sphinx_cn/build/html`
  和 `docs/sphinx_cn/build/pdf`。

接口关系：

* 被调用：`make manual`、文档发布流水。
* 调用：`sphinx-build`，PDF 模式间接依赖 `xelatex`。
* 共享状态：`docs/requirements-docs.txt`、`docs/sphinx_cn/build/`。

§9  需求矩阵
-------------

.. list-table::
   :header-rows: 1
   :widths: 24 31 45

   * - 流程
     - 直接工具
     - 源码依据
   * - `make smoke`
     - `make`、`python3`、`vcs` 或 `xrun`、可选 `build/simv`
     - `Makefile:L775-L821`、`signoff.py:L162-L165`
   * - `make regress`
     - `python3`、simulator、RISC-V GCC/objcopy
     - `Makefile:L390-L412`、`signoff.py:L167-L171`
   * - `make cosim`
     - Spike 安装树、`SPIKE_CXX`、`VCS_HOME`
     - `Makefile:L726-L761`
   * - `make lint`
     - `verible-verilog-lint`、`verilator`
     - `lint/Makefile:L12-L79`
   * - `make formal`
     - `ifv`
     - `dv/formal/Makefile:L1-L24`
   * - `make synth`
     - `dc_shell`、`fm_shell`、可选 `yosys`
     - `syn/Makefile:L62-L158`
   * - `make manual`
     - `sphinx-build`、PDF 模式 `xelatex`
     - `docs/requirements-docs.txt:L1-L8`、`Makefile:L495-L507`
   * - full sign-off
     - 上述工具按 stage 组合
     - `README.md:L411-L427`、`signoff.py:L152-L193`

逐段解释：

* 该表是导航，不替代前文代码片段。需要判断某个工具是否必需时，应看对应流程的
  Make target 或 `signoff.py` stage。
* `questa` 目前出现在 `signoff.py` 的 simulator choices 和 precheck 映射中；顶层
  `Makefile` 当前没有 `compile_questa`，因此本文不把它写成顶层直接编译路径。
* `Yosys` 路径存在于 `syn/Makefile`，但 `Makefile` 和 ADR-0013 明确记录当前 open-source
  Yosys path 是已知受限路径；full release synthesis/LEC 以 DC/Formality 路径为主。

接口关系：

* 被调用：人工环境准备、CI runner 配置。
* 调用：无。
* 共享状态：各 flow 的 PATH、工具变量和 build 输出目录。

§10  参考资料
---------------

* 关联章节：:ref:`getting_started`、:ref:`build_flow`、:ref:`signoff_flow`、
  :ref:`lint_flow`、:ref:`formal_flow`、:ref:`synthesis_flow`、:ref:`lec_flow`。
* 关联 ADR：:ref:`adr-0012`、:ref:`adr-0013`、:ref:`adr-0020`。
* 源文件绝对路径：

  * `/home/host/eh2-veri/README.md`
  * `/home/host/eh2-veri/env.sh`
  * `/home/host/eh2-veri/docs/requirements-docs.txt`
  * `/home/host/eh2-veri/Makefile`
  * `/home/host/eh2-veri/lint/Makefile`
  * `/home/host/eh2-veri/dv/formal/Makefile`
  * `/home/host/eh2-veri/syn/Makefile`
  * `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
