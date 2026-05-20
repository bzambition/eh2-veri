.. _compliance_flow:
.. _06_flows/compliance_flow:

RISC-V Compliance 流程
======================

:status: draft
:source: dv/uvm/riscv_compliance/scripts/run_compliance.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  流程边界
------------

本章描述 EH2 验证平台中的 RISC-V compliance 流程。该流程的 primary runner 是
:file:`dv/uvm/riscv_compliance/scripts/run_compliance.py`，顶层入口由
:file:`Makefile` 委托到 :file:`dv/uvm/riscv_compliance/Makefile`，当前 full
sign-off 由 :file:`dv/uvm/core_eh2/scripts/signoff.py` 调用同一个 runner。

2026-05-19 01:02 VCS 主线 demo 记录的 compliance 结果是 85/88
(96.59%)。本文只描述当前源码树中的 RV32I/RV32IM/RV32IMC/RV32Zicsr/RV32Zifencei
套件和 suite gate，不从旧版文档继承当前 runner 无法证明的 RV32A 或 Zb* 测试套件
描述。

数据流如下::

   top Makefile
        |
        v
   dv/uvm/riscv_compliance/Makefile
        |
        v
   run_compliance.py
        |
        +--> riscv32-unknown-elf-gcc + objcopy
        |         |
        |         v
        |      <test>.elf / <test>.hex
        |
        +--> build/simv + +bin=<hex> + +disable_cosim=1
                  |
                  v
              mailbox / SIGNATURE lines
                  |
                  v
              byte comparison + report.json
                  |
                  v
              signoff.py suite gate

关键证据（2026-05-19 01:02 VCS demo）：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   compliance 85/88 (96.59%)
   formal     46/46 (100%)
   syn / LEC  31635/31635 PASS

逐段解释：

* compliance 行的状态是 `PASS`，通过数是 85，总数是 88，通过率是 96.59%。
* formal 和 syn 的数字也在同一组 full profile 结果里出现，因此 compliance 的
  85/88 是 sign-off gate 证据的一部分，而不是独立脚本自报的临时输出。

接口关系：

* 被调用：`:ref:`signoff_flow`` 在 `full` profile 中调用 compliance stage。
* 调用：顶层 Makefile、compliance 子 Makefile、`run_compliance.py`、simv。
* 共享状态：VCS 编译产物、sign-off 输出下的 `runs/compliance`、
  `dv/uvm/riscv_compliance/work`、per-ISA `report.json`。

§2  顶层 Makefile 入口
----------------------

顶层 :file:`Makefile` 只负责将 compliance 相关目标委托给
:file:`dv/uvm/riscv_compliance/Makefile`。这里没有展开编译、运行或签名比较逻辑，
因此调试 compliance 失败时应继续进入子目录 Makefile 和 Python runner。

§2.1  ``compliance``、``compliance-all``、``compliance-compile`` — 顶层委托
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供仓库根目录下的统一 CLI 入口，把用户或 CI 的 `make compliance`
命令传递到 RISC-V compliance 子目录。

关键代码（``Makefile:L543-L556``）：

.. code-block:: makefile

   # -----------------------------------------------------------------------
   # RISC-V Compliance Tests (issue 57)
   #
   # `make compliance` runs riscv-compliance against the EH2 simulator.
   # Requires: TARGET_SIM (simv), riscv32-unknown-elf-gcc
   # -----------------------------------------------------------------------
   compliance:
   	+@$(MAKE) -C dv/uvm/riscv_compliance compliance

   compliance-all:
   	+@$(MAKE) -C dv/uvm/riscv_compliance compliance-all

   compliance-compile:
   	+@$(MAKE) -C dv/uvm/riscv_compliance compliance-compile

逐段解释：

* 第 L543-L548 行：注释给出目标边界：这些目标运行 riscv-compliance，并要求 simv
  与 `riscv32-unknown-elf-gcc` 可用。注释中的 `TARGET_SIM` 没有在这段目标里展开，
  实际 simv 默认值由子目录 Makefile 和 runner 决定。
* 第 L549-L550 行：`compliance` 通过 `$(MAKE) -C dv/uvm/riscv_compliance
  compliance` 进入子目录。前缀 `+` 允许递归 make 在上层 make 的 jobserver 语义下
  继续执行。
* 第 L552-L556 行：`compliance-all` 和 `compliance-compile` 使用同样的委托方式；
  顶层 Makefile 不自行解析 ISA、test name、output 目录或已知失败。

接口关系：

* 被调用：用户命令、CI job、sign-off 包装命令可从仓库根目录调用这些目标。
* 调用：`:file:`dv/uvm/riscv_compliance/Makefile`` 中的同名目标。
* 共享状态：继承 make 变量，例如 `RISCV_ISA`、`SIMV`、`VERBOSE`、`WORK_DIR`。

§3  Compliance 子 Makefile
--------------------------

:file:`dv/uvm/riscv_compliance/Makefile` 是 compliance flow 的 make 层控制面。它定义
EH2 根目录、上游 riscv-compliance 路径、work 目录、RISC-V 工具链前缀、支持的 ISA
列表，以及 runner 与 standalone TB 编译目标。

§3.1  变量与支持套件 — 固定路径和 ISA 白名单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 compliance 运行所需的路径、默认 ISA、simv 位置和 runner 文件收敛到
Makefile 变量中，避免命令行重复写长路径。

关键代码（``dv/uvm/riscv_compliance/Makefile:L22-L44``）：

.. code-block:: makefile

   SHELL := /bin/bash

   EH2_ROOT        ?= $(realpath $(CURDIR)/../../..)
   COMPLIANCE_FW   ?= /home/host/riscv-compliance
   COMPLIANCE_DIR  ?= $(CURDIR)
   WORK_DIR        ?= $(COMPLIANCE_DIR)/work

   RISCV_PREFIX    ?= riscv32-unknown-elf-
   RISCV_ISA       ?= rv32i
   RISCV_DEVICE    ?= rv32imac

   # Supported compliance suites
   SUPPORTED_ISAS := rv32i rv32im rv32imc rv32Zicsr rv32Zifencei
   KNOWN_FAIL_ISAS := rv32Zicsr rv32Zifencei

   # Device directory for a given ISA
   DEVICE_DIR      = $(COMPLIANCE_DIR)/device/$(ISA)

   # Simulator
   SIMV            ?= $(EH2_ROOT)/build/simv

   # Python runner
   RUNNER          := $(COMPLIANCE_DIR)/scripts/run_compliance.py

逐段解释：

* 第 L22 行：子 Makefile 显式使用 `/bin/bash`，因此后续 shell 片段可以使用 bash
  语法。
* 第 L24-L27 行：`EH2_ROOT` 从当前目录向上三级得到仓库根目录；`COMPLIANCE_FW`
  默认指向 `/home/host/riscv-compliance`；`WORK_DIR` 默认落在
  `dv/uvm/riscv_compliance/work`。
* 第 L29-L31 行：工具链前缀默认是 `riscv32-unknown-elf-`，默认运行 ISA 是
  `rv32i`。`RISCV_DEVICE` 在这段中定义为 `rv32imac`，但后续主要目标实际按
  `RISCV_ISA` 调用 Python runner。
* 第 L34-L35 行：Makefile 白名单列出 `rv32i`、`rv32im`、`rv32imc`、
  `rv32Zicsr`、`rv32Zifencei`；`KNOWN_FAIL_ISAS` 只包含 `rv32Zicsr` 和
  `rv32Zifencei`。
* 第 L41-L44 行：`SIMV` 默认是仓库根目录下的 `build/simv`；`RUNNER` 指向
  `scripts/run_compliance.py`，后续目标都通过这个脚本进入 Python 层。

接口关系：

* 被调用：顶层 `make compliance*` 委托到本 Makefile。
* 调用：`run_compliance.py`、VCS、RISC-V GCC、objcopy。
* 共享状态：`EH2_ROOT`、`COMPLIANCE_FW`、`WORK_DIR`、`RISCV_ISA`、`SIMV`。

§3.2  ``compliance`` — 单 ISA 运行入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 simv 是否存在，然后以 `RISCV_ISA`、`SIMV` 和 per-ISA output 目录调用
Python runner。

关键代码（``dv/uvm/riscv_compliance/Makefile:L52-L62``）：

.. code-block:: makefile

   # Run compliance tests for a single ISA (delegates to Python runner)
   compliance:
   	@if [ ! -f "$(SIMV)" ]; then \
   		echo "ERROR: simv not found at $(SIMV)"; \
   		echo "  Build it: cd $(EH2_ROOT) && make compile"; \
   		exit 1; \
   	fi
   	@echo "=== EH2 Compliance: $(RISCV_ISA) ==="
   	python3 $(RUNNER) --isa $(RISCV_ISA) --simv $(SIMV) \
   		--output $(WORK_DIR)/$(RISCV_ISA) \
   		$(if $(VERBOSE),--verbose,)

逐段解释：

* 第 L52-L58 行：目标首先检查 `$(SIMV)` 是否是文件；不存在时打印构建提示并以
  `exit 1` 结束。该检查只覆盖 simulator 可执行文件，不检查 RISC-V toolchain。
* 第 L59-L62 行：通过 `python3 $(RUNNER)` 调用 runner，显式传入 `--isa`、
  `--simv` 与 `--output`。输出目录按 `$(WORK_DIR)/$(RISCV_ISA)` 分 ISA 隔离。
* 第 L62 行：当 `VERBOSE` 非空时追加 `--verbose`，否则不传该参数。

接口关系：

* 被调用：顶层 `make compliance`、本目录 `compliance-all`。
* 调用：`run_compliance.py --isa <RISCV_ISA> --simv <SIMV> --output
  <WORK_DIR>/<RISCV_ISA>`。
* 共享状态：`SIMV` 文件、`WORK_DIR`、`VERBOSE`。

§3.3  ``compliance-all``、``compliance-compile``、``list-tests`` — 批量与只编译入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供全 ISA 批量运行、只编译和列测试名三个辅助入口。

关键代码（``dv/uvm/riscv_compliance/Makefile:L64-L85``）：

.. code-block:: makefile

   # Run all compliance suites
   compliance-all:
   	@failed=0; \
   	for isa in $(SUPPORTED_ISAS); do \
   		echo ""; \
   		echo "========================================"; \
   		echo "  $$isa"; \
   		echo "========================================"; \
   		$(MAKE) compliance RISCV_ISA=$$isa || failed=1; \
   	done; \
   	if [ $$failed -ne 0 ]; then \
   		echo ""; \
   		echo "Some suites had failures (check known-fail ISAs: $(KNOWN_FAIL_ISAS))"; \
   	fi

   # Compile tests only (no simulation)
   compliance-compile:
   	python3 $(RUNNER) --isa $(RISCV_ISA) --dry-run

   # List available tests for an ISA
   list-tests:
   	python3 $(RUNNER) --isa $(RISCV_ISA) --list-tests

逐段解释：

* 第 L64-L73 行：`compliance-all` 遍历 `SUPPORTED_ISAS`，每个 ISA 递归调用
  `$(MAKE) compliance RISCV_ISA=$$isa`。任何一次失败都会把 shell 变量
  `failed` 置为 1。
* 第 L74-L77 行：如果至少一个 suite 失败，Makefile 只打印提示文本，没有在这段代码中
  显式 `exit 1`。实际单 suite 返回码由 runner 控制。
* 第 L79-L81 行：`compliance-compile` 使用 `--dry-run`。在 runner 中 dry-run
  表示仍编译并生成 hex，但跳过 simulation 和签名比较。
* 第 L83-L85 行：`list-tests` 使用 `--list-tests` 只枚举上游 suite `src/*.S` 的
  stem。

接口关系：

* 被调用：用户命令或调试脚本。
* 调用：本 Makefile 的 `compliance` 目标、runner 的 `--dry-run` 与
  `--list-tests` 模式。
* 共享状态：`SUPPORTED_ISAS`、`KNOWN_FAIL_ISAS`、`RISCV_ISA`。

§3.4  ``compile-compliance-tb`` — Standalone TB 编译
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 VCS 编译无 UVM 依赖的 `eh2_compliance_tb`，输出
`build/simv_compliance`。

关键代码（``dv/uvm/riscv_compliance/Makefile:L94-L120``）：

.. code-block:: makefile

   COMPLIANCE_TB_DIR  := $(COMPLIANCE_DIR)/tb
   COMPLIANCE_TB_TOP  := eh2_compliance_tb
   COMPLIANCE_SIMV    := $(EH2_ROOT)/build/simv_compliance

   # File lists from the core testbench (reuse RTL + shared)
   RTL_F      := $(EH2_ROOT)/dv/uvm/core_eh2/eh2_rtl.f
   SHARED_F   := $(EH2_ROOT)/dv/uvm/core_eh2/eh2_shared.f

   compile-compliance-tb:
   	@echo "=== Compiling stand-alone compliance TB (VCS) ==="
   	@mkdir -p $(EH2_ROOT)/build
   	cd $(EH2_ROOT) && vcs -full64 -assert svaext -sverilog \
   		+error+500 \
   		+define+GTLSIM \
   		+define+RV_BUILD_AXI4 \
   		rtl/snapshots/default/common_defines.vh \
   		+incdir+rtl/snapshots/default \
   		+incdir+dv/uvm/core_eh2/tb \

逐段解释：

* 第 L94-L100 行：目标设置 standalone TB 目录、top module、输出 simulator 路径，
  并复用 core testbench 的 RTL 与 shared file list。
* 第 L102-L105 行：目标创建 `$(EH2_ROOT)/build`，随后在仓库根目录执行 VCS。
* 第 L105-L113 行：VCS 参数包含 `-full64`、`-assert svaext`、`-sverilog`、
  `+define+GTLSIM` 和 `+define+RV_BUILD_AXI4`，并加入 RTL snapshot 与 testbench
  include 目录。

关键代码（``dv/uvm/riscv_compliance/Makefile:L113-L120``）：

.. code-block:: makefile

   		-f $(RTL_F) \
   		-f $(SHARED_F) \
   		$(COMPLIANCE_TB_DIR)/eh2_compliance_tb.sv \
   		-top $(COMPLIANCE_TB_TOP) \
   		-o $(COMPLIANCE_SIMV) \
   		-l $(EH2_ROOT)/build/compliance_tb_compile.log \
   		-timescale=1ns/1ps
   	@echo "=== Compliance TB compiled: $(COMPLIANCE_SIMV) ==="

逐段解释：

* 第 L113-L115 行：编译命令读入 RTL file list、shared file list，并把
  `eh2_compliance_tb.sv` 作为 standalone TB 源文件。
* 第 L116-L119 行：top module 是 `eh2_compliance_tb`，输出 binary 是
  `build/simv_compliance`，编译日志写到 `build/compliance_tb_compile.log`，
  timescale 是 `1ns/1ps`。
* 第 L120 行：编译完成后打印输出路径。

接口关系：

* 被调用：`make compile-compliance-tb`。
* 调用：VCS、RTL file list、shared file list、standalone compliance TB。
* 共享状态：`build/simv_compliance`、`build/compliance_tb_compile.log`。

§3.5  ``test-%.hex`` 与 ``clean`` — 手工 hex 和清理
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供单个 compliance 汇编文件的手工 hex 构建目标，并提供 work 目录清理目标。

关键代码（``dv/uvm/riscv_compliance/Makefile:L122-L140``）：

.. code-block:: makefile

   # Old-style: compile a single test hex (for manual testing)
   test-%.hex:
   	$(RISCV_PREFIX)gcc -march=$(RISCV_ISA) -mabi=ilp32 -nostdlib -nostartfiles \
   		-T$(COMPLIANCE_DIR)/device/$(RISCV_ISA)/link.ld \
   		-I$(COMPLIANCE_DIR)/device/$(RISCV_ISA) \
   		-I$(COMPLIANCE_FW)/riscv-test-env \
   		-I$(COMPLIANCE_FW)/riscv-test-env/p \
   		$(COMPLIANCE_DIR)/device/$(RISCV_ISA)/startup.S \
   		$(COMPLIANCE_FW)/riscv-test-suite/$(RISCV_ISA)/src/$*.S \
   		-o $*.elf
   	$(RISCV_PREFIX)objcopy -O verilog $*.elf $@
   	@echo "Generated $@"

   clean:
   	rm -rf $(WORK_DIR)
   	@echo "Cleaned $(WORK_DIR)"

逐段解释：

* 第 L122-L131 行：`test-%.hex` 直接调用 prefixed GCC，使用当前 ISA 的 linker
  script、device include、riscv-test-env include、device startup 和上游
  `src/$*.S`，输出 `$*.elf`。
* 第 L132-L133 行：objcopy 把 ELF 转成 Verilog hex，并打印生成文件名。
* 第 L138-L140 行：`clean` 删除 `$(WORK_DIR)`，用于清理 compliance work 目录。

接口关系：

* 被调用：手工调试命令。
* 调用：GCC、objcopy、上游 `riscv-test-suite/<ISA>/src/<test>.S`。
* 共享状态：当前工作目录中的 `$*.elf`、`$@`，以及 `WORK_DIR`。

§4  ``run_compliance.py``：路径、工具和编译
-------------------------------------------

Python runner 是 compliance flow 的执行层。它负责发现工具链、编译 test、运行 simv、
解析 mailbox 或 `SIGNATURE:` 输出、加载 reference、逐字节比较，并写出 report。

§4.1  默认路径和 ISA 映射
~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 runner 的默认根路径、上游 framework 路径、工具链前缀和支持的 ISA
集合。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L32-L50``）：

.. code-block:: python

   # ---------------------------------------------------------------------------
   # Default paths
   # ---------------------------------------------------------------------------
   EH2_ROOT = Path(__file__).resolve().parent.parent.parent.parent.parent
   COMPLIANCE_DIR = EH2_ROOT / "dv" / "uvm" / "riscv_compliance"
   RISCV_COMPLIANCE_FW = Path("/home/host/riscv-compliance")
   RISCV_TESTS_FW = Path("/home/host/riscv-tests")
   RISCV_PREFIX = "riscv32-unknown-elf-"

   SUPPORTED_ISAS = ["rv32i", "rv32im", "rv32imc", "rv32Zicsr", "rv32Zifencei"]

   # Map EH2 ISA names to riscv-compliance suite directory names
   ISA_TO_SUITE = {
       "rv32i": "rv32i",
       "rv32im": "rv32im",
       "rv32imc": "rv32imc",
       "rv32Zicsr": "rv32Zicsr",
       "rv32Zifencei": "rv32Zifencei",
   }

逐段解释：

* 第 L35-L38 行：`EH2_ROOT` 由脚本路径向上五级得到；`COMPLIANCE_DIR` 是仓库内
  compliance 目录；上游 `riscv-compliance` 与 `riscv-tests` 路径固定在
  `/home/host` 下。
* 第 L39 行：RISC-V 工具链前缀固定为 `riscv32-unknown-elf-`。
* 第 L41 行：runner 的 ISA 白名单与子 Makefile 一致。
* 第 L44-L50 行：当前映射是 identity map，EH2 侧 ISA 名称直接映射到
  riscv-compliance 的 suite 目录名。

接口关系：

* 被调用：module import、`main()` 和 `run_compliance()`。
* 调用：无外部调用；仅提供常量。
* 共享状态：`SUPPORTED_ISAS` 同时约束 CLI `--isa all` 展开和运行时 ISA 校验。

§4.2  ``find_tool()`` — 工具链二级查找
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：优先查找带 `riscv32-unknown-elf-` 前缀的工具，找不到时回退到无前缀工具名。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L56-L67``）：

.. code-block:: python

   def find_tool(name: str) -> str:
       """Find a RISC-V tool binary."""
       full = RISCV_PREFIX + name
       import shutil
       path = shutil.which(full)
       if path:
           return full
       # Try without prefix
       path = shutil.which(name)
       if path:
           return name
       raise FileNotFoundError("Tool not found: {}".format(full))

逐段解释：

* 第 L58-L62 行：函数先拼出 `RISCV_PREFIX + name`，例如 `gcc` 会变成
  `riscv32-unknown-elf-gcc`；如果 `shutil.which()` 找到该 binary，则返回 prefixed
  名称。
* 第 L63-L66 行：prefixed 版本不存在时尝试无前缀名称，便于环境中直接提供 `gcc`
  或 `objcopy` 包装器。
* 第 L67 行：两个名称都不可用时抛出 `FileNotFoundError`。`run_compliance()` 和
  `main()` 都会捕获该异常并把状态转成 toolchain blocker。

接口关系：

* 被调用：`compile_test()`、`run_compliance()`、`main()`。
* 调用：`shutil.which()`。
* 共享状态：读取 `RISCV_PREFIX`。

§4.3  ``compile_test()`` — 单测试编译和 hex 生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把上游 `src/<test>.S` 与 EH2 device 文件一起编译成 ELF，再转成 Verilog
hex。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L73-L93``）：

.. code-block:: python

   def compile_test(test_name: str, isa: str, device_dir: Path,
                    suite_src_dir: Path, output_dir: Path,
                    verbose: bool = False) -> Optional[Path]:
       """Compile one compliance test .S to .elf and .hex.

       Returns path to the .hex file, or None on failure.
       """
       src_file = suite_src_dir / "src" / f"{test_name}.S"
       if not src_file.exists():
           print(f"  SKIP: source not found: {src_file}")
           return None

       elf_file = output_dir / f"{test_name}.elf"
       hex_file = output_dir / f"{test_name}.hex"

       # GCC include paths
       includes = [
           f"-I{device_dir}",
           f"-I{RISCV_COMPLIANCE_FW}/riscv-test-env",
           f"-I{RISCV_COMPLIANCE_FW}/riscv-test-env/p",
       ]

逐段解释：

* 第 L73-L79 行：函数参数显式接收 test name、ISA、device 目录、suite 源目录和输出目录；
  返回值是 hex 路径或 `None`。
* 第 L80-L83 行：源文件路径固定为 `<suite_src_dir>/src/<test_name>.S`。源文件不存在时
  打印 `SKIP` 并返回 `None`，上层会把它记为 compile failure。
* 第 L85-L86 行：ELF 与 hex 都写入 output 目录，文件名沿用 test name。
* 第 L88-L93 行：include path 包括 EH2 device 目录、上游 `riscv-test-env` 和
  `riscv-test-env/p`。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L95-L124``）：

.. code-block:: python

   # Map march
   if isa == "rv32imc":
       march_std = "rv32imc"
   elif isa == "rv32im":
       march_std = "rv32im"
   elif isa == "rv32i":
       march_std = "rv32i"
   elif isa == "rv32Zicsr":
       march_std = "rv32im"  # Zicsr is baseline in this GCC version
   elif isa == "rv32Zifencei":
       march_std = "rv32im"  # Zifencei is baseline in this GCC version
   else:
       march_std = isa

   # Compile: .S -> .elf
   gcc = find_tool("gcc")
   objcopy = find_tool("objcopy")

   compile_cmd = [
       gcc,
       f"-march={march_std}",
       "-mabi=ilp32",
       "-nostdlib",
       "-nostartfiles",
       f"-T{device_dir}/link.ld",
   ] + includes + [

逐段解释：

* 第 L95-L107 行：`rv32i`、`rv32im`、`rv32imc` 直接映射到同名 `-march`；
  `rv32Zicsr` 和 `rv32Zifencei` 在当前 GCC 版本下使用 `rv32im`。
* 第 L110-L111 行：编译前调用 `find_tool()` 查找 `gcc` 与 `objcopy`。
* 第 L113-L124 行：GCC 命令固定使用 `-mabi=ilp32`、`-nostdlib`、
  `-nostartfiles` 和 per-ISA `link.ld`，随后追加 include path、startup.S 和
  上游 test 源文件。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L120-L153``）：

.. code-block:: python

   ] + includes + [
       f"{device_dir}/startup.S",
       str(src_file),
       "-o", str(elf_file),
   ]

   if verbose:
       print(f"    Compile: {' '.join(compile_cmd)}")

   result = subprocess.run(
       compile_cmd,
       stdout=subprocess.PIPE,
       stderr=subprocess.PIPE,
       universal_newlines=True,
       timeout=60,
   )

   if result.returncode != 0:
       print(f"  COMPILE FAIL: {test_name}")
       if verbose:
           print(result.stderr[-500:])
       return None

   # Convert: .elf -> .hex (Verilog hex format)
   hex_cmd = [objcopy, "-O", "verilog", str(elf_file), str(hex_file)]

逐段解释：

* 第 L120-L124 行：EH2 的 `startup.S` 放在 test 源文件前一起传给 GCC，输出路径是
  `<output_dir>/<test_name>.elf`。
* 第 L126-L135 行：verbose 模式打印完整编译命令；`subprocess.run()` 捕获 stdout、
  stderr，使用文本模式，并设置 60 秒超时。
* 第 L137-L141 行：GCC 返回码非 0 时打印 `COMPILE FAIL`；verbose 模式额外打印
  stderr 末尾 500 字符，然后返回 `None`。
* 第 L143-L144 行：objcopy 使用 `-O verilog` 生成 hex，供 simv 的 `+bin=` 读取。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L144-L153``）：

.. code-block:: python

   hex_cmd = [objcopy, "-O", "verilog", str(elf_file), str(hex_file)]
   result = subprocess.run(hex_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True, timeout=30)
   if result.returncode != 0:
       print(f"  OBJCOPY FAIL: {test_name}")
       return None

   # .signature section is now included in the hex file automatically
   # because the linker script uses a proper loadable section with PHDRS.
   return hex_file

逐段解释：

* 第 L144-L146 行：objcopy 命令同样捕获输出，并设置 30 秒超时。
* 第 L147-L149 行：objcopy 返回码非 0 时打印 `OBJCOPY FAIL` 并返回 `None`。
* 第 L151-L153 行：函数假设 linker script 通过 PHDRS 把 `.signature` 放入可加载段，
  因此 hex 文件中已经包含签名段，返回 hex 路径给 simulation 阶段。

接口关系：

* 被调用：`run_compliance()` 的 per-test loop。
* 调用：`find_tool()`、GCC、objcopy。
* 共享状态：`RISCV_COMPLIANCE_FW`、`RISCV_PREFIX`、per-ISA device 目录。

§5  ``run_compliance.py``：simulation、签名与比较
--------------------------------------------------------------------------------

runner 的 runtime 部分围绕两个输出协议工作：UVM `core_eh2_base_test` 运行 hex 时通过
mailbox 写出 PASS/FAIL 和签名字符；standalone TB 则可输出 `SIGNATURE:` 加 8 位 hex
word 的文本行。

§5.1  ``run_simulation()`` — simv 命令和 mailbox 解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 `+bin=<hex>` 运行 simv，解析 mailbox 写入，生成 `<test>.signature.output`。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L159-L185``）：

.. code-block:: python

   def run_simulation(hex_path: Path, output_dir: Path, test_name: str,
                      simv_path: Path, max_cycles: int = 500000,
                      verbose: bool = False) -> Tuple[bool, List[str], str]:
       """Run UVM simv with the test hex. Returns (passed, signature_lines, log_text)."""
       log_path = output_dir / f"{test_name}.log"

       sim_cmd = [
           str(simv_path),
           "+UVM_TESTNAME=core_eh2_base_test",
           f"+bin={hex_path}",
           f"+max_cycles={max_cycles}",
           "+disable_cosim=1",
           "+UVM_VERBOSITY=UVM_LOW",
           "-l", str(log_path),
       ]

       if verbose:
           print(f"    Run: {' '.join(sim_cmd)}")

       try:
           result = subprocess.run(
               sim_cmd,
               stdout=subprocess.PIPE,
               stderr=subprocess.PIPE,

逐段解释：

* 第 L159-L163 行：函数默认 `max_cycles` 为 500000，并为每个 test 建立独立 log path。
* 第 L165-L173 行：simv 参数固定为 `+UVM_TESTNAME=core_eh2_base_test`、
  `+bin=<hex>`、`+max_cycles=<max_cycles>`、`+disable_cosim=1`、
  `+UVM_VERBOSITY=UVM_LOW` 和 `-l <log_path>`。这里明确关闭 cosim，compliance
  比较只依赖签名。
* 第 L175-L185 行：verbose 模式打印命令；simulation 通过 `subprocess.run()` 执行，
  stdout/stderr 被捕获，超时是 300 秒。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L186-L225``）：

.. code-block:: python

       except subprocess.TimeoutExpired:
           print(f"  TIMEOUT: {test_name}")
           return False, [], "TIMEOUT"

       log_text = result.stdout + "\n" + result.stderr

       # Detect PASS/FAIL via compliance mailbox protocol:
       #   0xFF written to mailbox = PASS
       #   0x01 written to mailbox = FAIL (mcause follows)
       mailbox_pass = False
       mailbox_fail = False
       mailbox_fail_cause = ""
       hex_data = []
       saw_address_write = False

       for line in log_text.splitlines():
           m = re.search(r'MAILBOX WRITE.*data=([0-9a-fA-F]+)', line)
           if m:
               raw = int(m.group(1), 16)
               data_val = raw & 0xFF

               if not saw_address_write:
                   # First write is the begin_signature address
                   saw_address_write = True
                   continue

逐段解释：

* 第 L186-L188 行：simulation 超时时返回 `(False, [], "TIMEOUT")`。
* 第 L190-L198 行：stdout 与 stderr 合并成 `log_text`；状态变量记录 mailbox pass、
  fail、fail cause、十六进制字符流以及是否看见过地址写入。
* 第 L201-L205 行：runner 用正则查找 `MAILBOX WRITE.*data=<hex>`，取最低 8 bit
  作为协议字节。
* 第 L207-L210 行：第一次 mailbox write 被视为 `begin_signature` 地址，runner 只记录
  已看到地址写入，不把它当签名数据。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L212-L264``）：

.. code-block:: python

               if data_val == 0xFF:  # PASS token
                   mailbox_pass = True
                   break
               elif data_val == 0x01:  # FAIL token
                   mailbox_fail = True
               elif mailbox_fail:
                   # After FAIL token, the next write is mcause
                   mailbox_fail_cause = f"mcause=0x{data_val:02x}"
                   break
               elif data_val == 0x0A:  # newline = end of stream
                   break
               elif data_val in range(0x30, 0x3A) or data_val in range(0x61, 0x67):
                   hex_data.append(chr(data_val))

       # If no mailbox writes detected at all, check for simulation failure
       if not saw_address_write:
           return False, [], log_text

逐段解释：

* 第 L212-L214 行：`0xFF` 是 PASS token；看到后设置 `mailbox_pass` 并退出 mailbox
  解析循环。
* 第 L215-L220 行：`0x01` 是 FAIL token；紧随其后的一个字节被格式化为
  `mcause=0x..`，然后退出循环。当前函数没有把 `mailbox_fail_cause` 写入返回值，
  但 fail 状态会影响 `passed`。
* 第 L221-L224 行：`0x0A` 结束字符流；`0-9` 与 `a-f` 的 ASCII 值被收集到
  `hex_data`。
* 第 L226-L228 行：如果完全没有看到 mailbox 地址写入，函数直接返回失败，并把完整
  log 交给上层判别。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L230-L264``）：

.. code-block:: python

   # Parse hex chars into 32-bit words (each word = 8 hex chars, MSB-first)
   hex_str = "".join(hex_data)
   signature_lines = []
   for i in range(0, len(hex_str) - 7, 8):
       try:
           word = int(hex_str[i:i+8], 16)
           signature_lines.append(f"{word:08x}")
       except ValueError:
           break

   # Also try looking for SIGNATURE: lines from compliance TB output
   if not signature_lines:
       if log_path.exists():
           with open(log_path, "r") as f:
               log_content = f.read()
           for line in log_content.splitlines():
               m = re.match(r'^SIGNATURE:\s*([0-9a-fA-F]{8})$', line.strip())
               if m:

逐段解释：

* 第 L230-L238 行：runner 将 mailbox 字符串按每 8 个 hex 字符切成一个 32-bit word，
  并用小写 8 字符格式加入 `signature_lines`。
* 第 L240-L248 行：如果 mailbox 路径没有生成签名行，则读取 simv log，查找独立 TB
  风格的 `SIGNATURE:` 加 8 位 hex word 文本行作为 fallback。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L246-L264``）：

.. code-block:: python

               m = re.match(r'^SIGNATURE:\s*([0-9a-fA-F]{8})$', line.strip())
               if m:
                   signature_lines.append(m.group(1).lower())

   # Determine pass/fail: trust mailbox protocol over UVM framework
   passed = mailbox_pass and not mailbox_fail

   if not mailbox_pass and not signature_lines:
       passed = False
   elif mailbox_pass:
       passed = True

   # Write signature to file
   sig_path = output_dir / f"{test_name}.signature.output"
   with open(sig_path, "w") as f:
       for line in signature_lines:
           f.write(line + "\n")

   return passed, signature_lines, log_text

逐段解释：

* 第 L250-L256 行：pass/fail 优先信任 mailbox 协议；有 PASS token 时 `passed=True`，
  没有 PASS 且没有签名时失败。
* 第 L258-L263 行：无论最终是否通过，只要有 `signature_lines`，都会写到
  `<test>.signature.output`。
* 第 L264 行：返回三元组：运行是否通过、签名 word 列表、完整 log 文本。

接口关系：

* 被调用：`run_compliance()` 的 per-test loop。
* 调用：simv、UVM base test、mailbox log parser、standalone TB signature parser。
* 共享状态：`build/simv`、`<output_dir>/<test>.log`、
  `<output_dir>/<test>.signature.output`。

§5.2  ``load_reference()`` — reference output 过滤
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从上游 reference 文件中读取 8 位十六进制 word 行，忽略不匹配格式的文本。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L270-L281``）：

.. code-block:: python

   def load_reference(reference_path: Path) -> List[str]:
       """Load reference signature lines (32-bit hex words, one per line)."""
       if not reference_path.exists():
           return []

       lines = []
       with open(reference_path, "r") as f:
           for line in f:
               line = line.strip()
               if re.match(r'^[0-9a-fA-F]{8}$', line):
                   lines.append(line.lower())
       return lines

逐段解释：

* 第 L270-L273 行：reference 文件不存在时返回空列表；上层 `compare_signatures()`
  会把“有签名但无 reference”视为 skip-like pass。
* 第 L275-L280 行：函数逐行 strip，仅保留完整匹配 8 个 hex 字符的行，并转换成小写。
* 第 L281 行：返回 word 列表，供逐字节比较。

接口关系：

* 被调用：`run_compliance()`。
* 调用：`re.match()`。
* 共享状态：上游 `riscv-test-suite/<isa>/references/<test>.reference_output`。

§5.3  ``compare_signatures()`` — 逐字节比较
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：将 actual 与 reference 的 32-bit word 序列展开成 byte stream，并做严格字节
比较。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L287-L315``）：

.. code-block:: python

   def compare_signatures(
       actual: List[str],
       reference: List[str],
       test_name: str,
   ) -> Tuple[bool, str]:
       """Byte-by-byte comparison of signature words.

       Returns (passed, detail_string).
       """
       if not actual:
           return False, "no signature captured (empty)"

       if not reference:
           return True, "no reference available (SKIP — signature captured but no ref)"

       # Convert 32-bit hex words to byte streams (big-endian decomposition)
       def words_to_bytes(words):
           b = bytearray()
           for w in words:
               val = int(w, 16)
               b.extend([(val >> 24) & 0xFF, (val >> 16) & 0xFF,
                          (val >> 8) & 0xFF, val & 0xFF])
           return bytes(b)

       actual_bytes = words_to_bytes(actual)
       ref_bytes = words_to_bytes(reference)

       if actual_bytes == ref_bytes:

逐段解释：

* 第 L287-L295 行：函数返回 `(passed, detail_string)`，detail 用于 report 和终端输出。
* 第 L296-L300 行：actual 为空必定失败；reference 为空时返回通过状态和
  `no reference available` 说明。
* 第 L302-L309 行：内部 `words_to_bytes()` 把每个 32-bit word 按 MSB-first 展开成
  4 个字节。
* 第 L311-L315 行：actual bytes 与 reference bytes 完全相等时返回通过，并报告
  actual word 数量。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L314-L335``）：

.. code-block:: python

   if actual_bytes == ref_bytes:
       return True, "signature match ({} words)".format(len(actual))

   # Find first mismatch
   min_len = min(len(actual_bytes), len(ref_bytes))
   mismatch_index = None
   for i in range(min_len):
       if actual_bytes[i] != ref_bytes[i]:
           mismatch_index = i
           break

   if mismatch_index is not None:
       detail = (f"byte {mismatch_index} differs: "
                 f"actual=0x{actual_bytes[mismatch_index]:02x} "
                 f"ref=0x{ref_bytes[mismatch_index]:02x}")
   elif len(actual_bytes) != len(ref_bytes):
       detail = (f"length mismatch: {len(actual_bytes)} actual vs "
                 f"{len(ref_bytes)} ref bytes")
   else:
       detail = "signature mismatch (unknown)"

   return False, detail

逐段解释：

* 第 L317-L323 行：首次不匹配的 byte index 通过线性扫描得到。
* 第 L325-L328 行：存在 byte mismatch 时，detail 写出 byte index、actual byte 和
  reference byte。
* 第 L329-L333 行：如果公共长度内没有 mismatch，但长度不同，则报告 actual/ref byte
  长度差异；其他情况使用兜底 detail。
* 第 L335 行：任何 mismatch 都返回 `False`。

接口关系：

* 被调用：`run_compliance()` 与 `collect_compliance.py` 中同名逻辑。
* 调用：内部 `words_to_bytes()`。
* 共享状态：无全局写入；只消费 actual/reference word 列表。

§6  ``run_compliance.py``：套件循环、报告和 CLI
-----------------------------------------------

`run_compliance()` 是 runner 的主控制函数。`main()` 负责 CLI 解析、simv/toolchain
预检、`--isa all` 展开，以及 aggregated report 写出。

§6.1  ``run_compliance()`` — 路径解析和前置检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：验证 ISA、device 目录、suite 目录、simv、test source 目录和 toolchain，准备
per-ISA 输出目录。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L341-L381``）：

.. code-block:: python

   def run_compliance(
       isa: str,
       test_name: Optional[str] = None,
       simv_path: Optional[Path] = None,
       output_dir: Optional[Path] = None,
       device_dir: Optional[Path] = None,
       verbose: bool = False,
       dry_run: bool = False,
   ) -> Dict:
       """Run all compliance tests for a given ISA.

       Returns a dict with results:
           {"total": N, "passed": P, "failed": F, "tests": [{...}, ...]}
       """
       if isa not in SUPPORTED_ISAS:
           print(f"ERROR: unsupported ISA: {isa}. Supported: {SUPPORTED_ISAS}")
           return {"total": 0, "passed": 0, "failed": 0, "tests": []}

       # Resolve paths
       if device_dir is None:
           device_dir = COMPLIANCE_DIR / "device" / isa

逐段解释：

* 第 L341-L349 行：函数参数覆盖单 test、simv 路径、输出目录、device 目录、verbose
  和 dry-run 模式。
* 第 L350-L357 行：不在 `SUPPORTED_ISAS` 中的 ISA 直接返回空结果，不进入文件系统或
  simulator。
* 第 L359-L361 行：未显式传入 device 目录时使用
  `dv/uvm/riscv_compliance/device/<isa>`。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L362-L405``）：

.. code-block:: python

       if not device_dir.exists():
           print(f"ERROR: device directory not found: {device_dir}")
           return {"total": 0, "passed": 0, "failed": 0, "tests": []}

       suite_dir_name = ISA_TO_SUITE[isa]
       suite_src_dir = RISCV_COMPLIANCE_FW / "riscv-test-suite" / suite_dir_name
       if not suite_src_dir.exists():
           print(f"ERROR: suite directory not found: {suite_src_dir}")
           return {"total": 0, "passed": 0, "failed": 0, "tests": []}

       if simv_path is None:
           simv_path = EH2_ROOT / "build" / "simv"
       if not simv_path.exists():
           print(f"ERROR: simv not found: {simv_path}")
           print(f"  Build it first: cd {EH2_ROOT} && make compile")
           return {"total": 0, "passed": 0, "failed": 0, "tests": []}

       if output_dir is None:
           output_dir = COMPLIANCE_DIR / "work" / isa
       output_dir.mkdir(parents=True, exist_ok=True)

逐段解释：

* 第 L362-L364 行：device 目录不存在时返回空结果。
* 第 L366-L370 行：suite 目录来自 `/home/host/riscv-compliance/riscv-test-suite/<isa>`；
  不存在时返回空结果。
* 第 L372-L377 行：simv 默认是 `build/simv`；不存在时打印构建提示并返回空结果。
* 第 L379-L381 行：输出目录默认是 `dv/uvm/riscv_compliance/work/<isa>`，并用
  `mkdir(parents=True, exist_ok=True)` 创建。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L383-L405``）：

.. code-block:: python

   # Discover tests
   src_dir = suite_src_dir / "src"
   if not src_dir.exists():
       print(f"ERROR: test source directory not found: {src_dir}")
       return {"total": 0, "passed": 0, "failed": 0, "tests": []}

   if test_name:
       test_list = [test_name]
   else:
       test_list = sorted([p.stem for p in src_dir.glob("*.S")])

   if not test_list:
       print(f"ERROR: no tests found for ISA={isa}")
       return {"total": 0, "passed": 0, "failed": 0, "tests": []}

   # Check that toolchain is available
   try:
       find_tool("gcc")
       find_tool("objcopy")
   except FileNotFoundError as e:
       print(f"STATUS: BLOCKED-NEEDS-TOOLCHAIN ({e})")

逐段解释：

* 第 L383-L387 行：runner 要求 suite 下存在 `src` 目录。
* 第 L389-L392 行：如果 CLI 指定 `--test`，只运行该 test；否则枚举 `src/*.S` 并按
  stem 排序。
* 第 L394-L396 行：没有发现 test 时返回空结果。
* 第 L399-L405 行：运行前预查 `gcc` 与 `objcopy`；找不到时打印
  `BLOCKED-NEEDS-TOOLCHAIN` 并返回带 `blocked` 与 `reason` 字段的空结果。

接口关系：

* 被调用：`main()`。
* 调用：`find_tool()`、filesystem glob。
* 共享状态：`SUPPORTED_ISAS`、`ISA_TO_SUITE`、`RISCV_COMPLIANCE_FW`、
  `COMPLIANCE_DIR`、`EH2_ROOT`。

§6.2  ``run_compliance()`` — per-test 三阶段执行
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：对每个 test 顺序执行 compile、simulation、reference compare，并将结果加入
summary。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L407-L444``）：

.. code-block:: python

   print(f"\n=== EH2 RISC-V Compliance: {isa} ===")
   print(f"  Tests: {len(test_list)}")
   print(f"  Device: {device_dir}")
   print(f"  Output: {output_dir}")
   print(f"  Simv: {simv_path}")
   print()

   results = []
   passed_count = 0
   failed_count = 0

   for test in test_list:
       print(f"  [{test}] ", end="", flush=True)

       # 1. Compile
       hex_path = compile_test(
           test, isa, device_dir, suite_src_dir, output_dir, verbose)
       if hex_path is None:
           results.append({
               "name": test,
               "passed": False,
               "failure": "compile",
               "detail": "compilation failed",
           })

逐段解释：

* 第 L407-L412 行：runner 在 suite 开始时打印 ISA、test 数量、device、output 和 simv。
* 第 L414-L418 行：初始化结果列表和 passed/failed 计数器，然后逐 test 运行。
* 第 L421-L433 行：第一阶段调用 `compile_test()`。返回 `None` 时记录失败模式
  `compile`，detail 是 `compilation failed`，然后进入下一个 test。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L431-L469``）：

.. code-block:: python

               "detail": "compilation failed",
           })
           failed_count += 1
           print("FAIL (compile)")
           continue

       if dry_run:
           results.append({
               "name": test,
               "passed": True,
               "failure": None,
               "detail": "dry-run",
           })
           passed_count += 1
           print("OK (dry-run)")
           continue

       # 2. Run simulation
       ok, sig_lines, log_text = run_simulation(
           hex_path, output_dir, test, simv_path, verbose=verbose)

       if not ok:

逐段解释：

* 第 L431-L434 行：compile failure 会增加 failed count，并打印 `FAIL (compile)`。
* 第 L435-L444 行：dry-run 模式把已成功编译的 test 记录为 passed，detail 是
  `dry-run`，不运行 simulation。
* 第 L446-L448 行：非 dry-run 模式进入 simulation，调用 `run_simulation()` 并接收
  `ok`、`sig_lines`、`log_text`。
* 第 L450 行：`ok=False` 时进入 simulation failure 分类。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L450-L469``）：

.. code-block:: python

       if not ok:
           failure = "simulation"
           detail = "no signature captured"
           if "TIMEOUT" in log_text:
               failure = "timeout"
               detail = "simulation timeout"
           elif not sig_lines:
               failure = "no_signature"
               detail = "no PASS/FAIL token or signature data in mailbox"

           results.append({
               "name": test,
               "passed": False,
               "failure": failure,
               "detail": detail,
               "log": str(output_dir / f"{test}.log"),
           })
           failed_count += 1
           print(f"FAIL ({detail})")
           continue

逐段解释：

* 第 L451-L458 行：默认 failure 是 `simulation`；log 中包含 `TIMEOUT` 时改为
  `timeout`；没有签名行时改为 `no_signature`。
* 第 L460-L466 行：失败结果记录 test name、passed=false、failure、detail 和 log
  path。
* 第 L467-L469 行：失败计数加一，打印 detail，并跳过 reference compare。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L471-L518``）：

.. code-block:: python

       # 3. Compare with reference
       ref_dir = suite_src_dir / "references"
       ref_path = ref_dir / f"{test}.reference_output"
       ref_lines = load_reference(ref_path)

       try:
           match, detail = compare_signatures(sig_lines, ref_lines, test)
       except Exception as exc:
           match = False
           detail = f"comparison exception: {exc}"

       if match:
           results.append({
               "name": test,
               "passed": True,
               "failure": None,
               "detail": detail,
           })

逐段解释：

* 第 L471-L474 行：reference 文件路径固定为 suite `references/<test>.reference_output`。
* 第 L476-L480 行：调用 `compare_signatures()`；比较逻辑出现异常时把 test 标记为
  mismatch，并把异常文本写入 detail。
* 第 L482-L488 行：match 时记录通过结果，failure 为 `None`，detail 来自比较函数。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L489-L518``）：

.. code-block:: python

           passed_count += 1
           print("PASS")
       else:
           # Write .diff file for this test
           diff_path = output_dir / f"{test}.diff"
           actual_str = "\n".join(sig_lines)
           ref_str = "\n".join(ref_lines)
           with open(diff_path, "w") as f:
               f.write(f"--- expected ({test}.reference_output)\n")
               f.write(f"+++ actual  ({test}.signature.output)\n")
               for line in difflib.unified_diff(
                   ref_str.splitlines(keepends=True),
                   actual_str.splitlines(keepends=True),
                   fromfile=f"{test}.reference_output",
                   tofile=f"{test}.signature.output",

逐段解释：

* 第 L489-L490 行：通过时增加 passed count 并打印 `PASS`。
* 第 L492-L505 行：不匹配时写 `<test>.diff`，diff 使用 reference 作为 expected，
  actual signature 作为 actual。
* 第 L499-L505 行：具体 diff 由 `difflib.unified_diff()` 生成，from/to file 名称与
  reference output 和 signature output 对应。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L502-L533``）：

.. code-block:: python

                   fromfile=f"{test}.reference_output",
                   tofile=f"{test}.signature.output",
               ):
                   f.write(line)

           results.append({
               "name": test,
               "passed": False,
               "failure": "signature_mismatch",
               "detail": detail,
               "signature_path": str(output_dir / f"{test}.signature.output"),
               "reference_path": str(ref_path),
               "diff_path": str(diff_path),
           })
           failed_count += 1
           print(f"FAIL ({detail})")

   total = len(results)

逐段解释：

* 第 L507-L515 行：signature mismatch 结果包含 signature、reference 和 diff 三个路径，
  便于后续人工定位。
* 第 L516-L517 行：失败计数加一并打印比较 detail。
* 第 L519 行：suite 总数来自 `results` 长度，而不是原始 `test_list` 长度。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L519-L533``）：

.. code-block:: python

   total = len(results)
   print(f"\n  Summary: {total} tests, {passed_count} PASS, {failed_count} FAIL")

   summary = {
       "isa": isa,
       "total": total,
       "passed": passed_count,
       "failed": failed_count,
       "tests": results,
   }

   # Write report.json for sign-off framework integration
   _write_report_json(summary, output_dir)

   return summary

逐段解释：

* 第 L519-L526 行：summary 包含 ISA、total、passed、failed 和 tests 列表。
* 第 L530-L531 行：每个 ISA 运行结束后写出 `report.json`，供 sign-off 框架收集。
* 第 L533 行：返回 summary 给 CLI aggregation。

接口关系：

* 被调用：`main()`。
* 调用：`compile_test()`、`run_simulation()`、`load_reference()`、
  `compare_signatures()`、`_write_report_json()`。
* 共享状态：per-ISA output 目录、`.elf`、`.hex`、`.log`、`.signature.output`、
  `.diff`、`report.json`。

§6.3  ``_write_report_json()`` — sign-off 兼容报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 runner 内部 summary 转成 sign-off 收集器识别的 `tests` JSON schema。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L536-L570``）：

.. code-block:: python

   def _write_report_json(summary: Dict, output_dir: Path):
       """Write a report.json compatible with the sign-off framework."""
       report_tests = []
       for t in summary["tests"]:
           report_tests.append({
               "name": t["name"],
               "seed": 0,
               "type": "compliance_{}".format(summary["isa"]),
               "passed": t["passed"],
               "failure_mode": t.get("failure", ""),
               "sim_log": t.get("log", ""),
               "uvm_log": "",
               "trace": "",
               "assembly": "",
               "binary": "",
               "coverage": "",
               "uvm_errors": 0 if t["passed"] else 1,
               "uvm_warnings": 0,
               "instructions": 0,

逐段解释：

* 第 L536-L544 行：每个 test 被转成 report entry，`type` 固定为
  `compliance_<isa>`，这是 `signoff.py` suite gate 的过滤条件。
* 第 L545-L553 行：failure mode、sim log、UVM error/warning 字段按 sign-off
  schema 填充；通过用 `uvm_errors=0`，失败用 `uvm_errors=1`。
* 第 L554-L560 行：instructions、cycles、IPC 和时间字段当前填 0，说明 compliance
  runner 只提供 pass/fail 和路径信息，不提供性能统计。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L554-L570``）：

.. code-block:: python

               "instructions": 0,
               "cycles": 0,
               "ipc": 0.0,
               "gen_time_sec": 0.0,
               "compile_time_sec": 0.0,
               "sim_time_sec": 0.0,
           })

       report = {
           "total_time_sec": 0.0,
           "tests": report_tests,
       }

       report_path = output_dir / "report.json"
       with open(report_path, "w") as f:
           json.dump(report, f, indent=2)
       print(f"  Report: {report_path}")

逐段解释：

* 第 L562-L565 行：顶层 report 只包含 `total_time_sec` 和 `tests`。
* 第 L567-L570 行：报告写入 `<output_dir>/report.json`，并打印路径。

接口关系：

* 被调用：`run_compliance()`、`main()` aggregation。
* 调用：`json.dump()`。
* 共享状态：`report.json` schema 与 `signoff.py` 的 compliance gate 共享。

§6.4  ``main()`` — CLI 参数与环境预检
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解析命令行参数，检查 simv 和 toolchain，支持列测试、单 ISA、逗号分隔 ISA
和 `all` 模式。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L576-L614``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(
           description="EH2 RISC-V Compliance Runner (issue 57)")
       parser.add_argument("--isa", required=True,
                           help="RISC-V ISA to test (e.g. rv32i, rv32imc, or 'all')")
       parser.add_argument("--test", default=None,
                           help="Run a single test (e.g. I-ADD-01)")
       parser.add_argument("--simv", default=None,
                           help="Path to compiled simulator (default: build/simv)")
       parser.add_argument("--output", default=None,
                           help="Output directory for build artifacts")
       parser.add_argument("--verbose", action="store_true",
                           help="Verbose output")
       parser.add_argument("--dry-run", action="store_true",
                           help="Compile only, no simulation")
       parser.add_argument("--list-tests", action="store_true",
                           help="List available test names and exit")
       args = parser.parse_args()

逐段解释：

* 第 L576-L593 行：CLI 必填 `--isa`，可选 `--test`、`--simv`、`--output`、
  `--verbose`、`--dry-run` 和 `--list-tests`。
* 第 L579-L580 行：help 文本明确 `--isa` 支持单个 ISA 或 `all`。
* 第 L589-L592 行：`--dry-run` 是只编译不仿真；`--list-tests` 是列测试后退出。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L595-L614``）：

.. code-block:: python

   # Resolve simv path
   simv_path = Path(args.simv) if args.simv else EH2_ROOT / "build" / "simv"
   output_dir = Path(args.output) if args.output else None

   # Check simv
   if not args.dry_run and not args.list_tests and not simv_path.exists():
       print(f"ERROR: simulator not found: {simv_path}")
       print(
           "  Build the compliance simv: "
           f"cd {EH2_ROOT} && make compile")
       sys.exit(1)

   # Check toolchain
   toolchain_ok = True
   try:
       find_tool("gcc")
       find_tool("objcopy")

逐段解释：

* 第 L595-L597 行：未指定 `--simv` 时默认使用 `build/simv`；未指定 `--output` 时交给
  `run_compliance()` 使用 per-ISA work 目录。
* 第 L599-L605 行：非 dry-run、非 list-tests 模式要求 simv 存在，不存在时以 exit 1
  退出。
* 第 L607-L614 行：CLI 层也预查 GCC 和 objcopy；找不到工具链时打印 blocker，并以
  exit 2 退出。

接口关系：

* 被调用：脚本入口。
* 调用：`argparse`、`find_tool()`、`sys.exit()`。
* 共享状态：CLI 参数映射到 `run_compliance()` 参数。

§6.5  ``main()`` — list、all 和聚合报告
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：处理 `--list-tests`，展开 `--isa all` 或逗号列表，逐 ISA 调用
`run_compliance()`，并在指定 output 时写 aggregated `report.json`。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L616-L635``）：

.. code-block:: python

   # List tests
   if args.list_tests:
       isa = args.isa
       suite_name = ISA_TO_SUITE.get(isa, isa)
       src_dir = RISCV_COMPLIANCE_FW / "riscv-test-suite" / suite_name / "src"
       if src_dir.exists():
           for p in sorted(src_dir.glob("*.S")):
               print(p.stem)
       else:
           print(f"No tests found for {isa}")
       return

   # Parse ISAs (supports comma-separated or "all")
   if args.isa == "all":
       isa_list = ["rv32i", "rv32im", "rv32imc", "rv32Zicsr", "rv32Zifencei"]
   elif "," in args.isa:
       isa_list = [i.strip() for i in args.isa.split(",")]
   else:
       isa_list = [args.isa]

逐段解释：

* 第 L616-L626 行：list-tests 模式直接列出 suite `src/*.S` 的 stem，不检查 simv，也不运行
  compile。
* 第 L628-L630 行：`--isa all` 展开为五个支持的 ISA。
* 第 L631-L634 行：`--isa` 包含逗号时按逗号切分并 strip；否则作为单 ISA 列表。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L636-L668``）：

.. code-block:: python

   # Run compliance for each ISA
   aggregated = {
       "isa": args.isa,
       "total": 0,
       "passed": 0,
       "failed": 0,
       "tests": [],
   }
   exit_code = 0

   for isa in isa_list:
       result = run_compliance(
           isa=isa,
           test_name=args.test,
           simv_path=simv_path,
           output_dir=output_dir / isa if output_dir else None,
           verbose=args.verbose,

逐段解释：

* 第 L636-L643 行：aggregated summary 初始 total/passed/failed 都为 0，tests 为空。
* 第 L644-L654 行：每个 ISA 调用一次 `run_compliance()`；如果 CLI 指定 `--output`，
  per-ISA 输出目录是 `<output>/<isa>`。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L651-L668``）：

.. code-block:: python

           output_dir=output_dir / isa if output_dir else None,
           verbose=args.verbose,
           dry_run=args.dry_run,
       )
       aggregated["total"] += result["total"]
       aggregated["passed"] += result["passed"]
       aggregated["failed"] += result["failed"]
       aggregated["tests"].extend(result["tests"])
       if result["failed"] > 0:
           exit_code = 1
       elif result["total"] == 0 and exit_code == 0:
           exit_code = 2

   # Write aggregated report.json
   if output_dir:
       _write_report_json(aggregated, output_dir)

   sys.exit(exit_code)

逐段解释：

* 第 L655-L658 行：每个 ISA 的 total、passed、failed 和 tests 都汇总到 aggregated。
* 第 L659-L662 行：任一 ISA 有 failed 时 exit code 置 1；如果某个 ISA total 为 0 且
  当前没有失败，则 exit code 置 2。
* 第 L664-L666 行：只有显式传入 `--output` 时，runner 才写 aggregated
  `<output>/report.json`。
* 第 L668 行：进程以聚合后的 exit code 退出。

接口关系：

* 被调用：脚本入口。
* 调用：`run_compliance()`、`_write_report_json()`。
* 共享状态：`--output` 决定是否生成 aggregated report，sign-off stage 依赖该
  aggregated report 与 per-ISA report。

§7  EH2 device 文件
-------------------

EH2 compliance device 文件位于 :file:`dv/uvm/riscv_compliance/device/<isa>/`。各 ISA
目录提供 `compliance_test.h`、`compliance_io.h`、`startup.S` 和 `link.ld`；runner
按 ISA 选择对应目录。以下以 `rv32i` 目录为证据说明 mailbox、签名段和启动流程。

§7.1  ``compliance_test.h`` — mailbox 地址和 compliance 宏
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 EH2 compliance mailbox 地址，并把上游 compliance 宏映射到 EH2 的
signature begin/end 和 pass 流程。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/compliance_test.h:L15-L27``）：

.. code-block:: cpp

   #define COMPLIANCE_MBX_BASE              0xD0580000
   #define COMPLIANCE_MBX_HALT              (COMPLIANCE_MBX_BASE + 0x0)
   #define COMPLIANCE_MBX_BEGIN_SIGNATURE   (COMPLIANCE_MBX_BASE + 0x4)
   #define COMPLIANCE_MBX_END_SIGNATURE     (COMPLIANCE_MBX_BASE + 0x8)

   #define RV_COMPLIANCE_HALT                                                    \
           la t0, begin_signature;                                               \
           li t1, COMPLIANCE_MBX_BEGIN_SIGNATURE;                                \
           sw t0, 0(t1);                                                         \
           la t0, end_signature;                                                 \
           li t1, COMPLIANCE_MBX_END_SIGNATURE;                                  \
           sw t0, 0(t1);                                                         \
           RVTEST_PASS

逐段解释：

* 第 L15-L18 行：mailbox base 是 `0xD0580000`，offset `+0x0` 是 halt，
  `+0x4` 是 signature begin，`+0x8` 是 signature end。
* 第 L20-L27 行：`RV_COMPLIANCE_HALT` 先把 `begin_signature` 和 `end_signature`
  地址写入 mailbox，再执行 `RVTEST_PASS`。这对应 ADR-0011 描述的 begin/end 地址写入。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/compliance_test.h:L29-L50``）：

.. code-block:: cpp

   #define RV_COMPLIANCE_RV32M                                                   \
           RVTEST_RV32M

   #define RV_COMPLIANCE_CODE_BEGIN                                              \
           .section .text;                                                       \
           .globl  test_entry;                                                   \
   test_entry:

   #define RV_COMPLIANCE_CODE_END                                                \
           j signature_dump;                                                     \
           nop

   #define RV_COMPLIANCE_DATA_BEGIN                                              \
           .section .signature, "aw", @progbits;                                                 \
           .align 4

   #define RV_COMPLIANCE_DATA_END                                                \
           .align 4;                                                             \
           .global end_signature;                                                \
           end_signature:                                                        \
           nop;                                                                  \
           nop

逐段解释：

* 第 L29-L30 行：RV32M compliance 宏直接使用上游 `RVTEST_RV32M`。
* 第 L32-L35 行：代码段宏把 test entry 放在 `.text`，并导出 `test_entry`。
* 第 L37-L39 行：代码结束宏跳到 `signature_dump`，因此 test 结束后进入 startup 中的
  签名输出流程。
* 第 L41-L50 行：数据段宏切换到 `.signature`，对齐到 4 字节，并定义
  `end_signature` 标号。

接口关系：

* 被调用：上游 compliance `.S` 测试通过宏展开使用。
* 调用：`RVTEST_PASS`、`signature_dump`。
* 共享状态：`begin_signature` 由 linker script 定义，`end_signature` 由宏定义。

§7.2  ``compliance_io.h`` — 禁用 ecall 式 PASS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把上游 `RVTEST_IO_*` 宏定义为空，并重写 `RVTEST_PASS`，避免通过 ecall 退出。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/compliance_io.h:L11-L24``）：

.. code-block:: cpp

   #define RVTEST_IO_INIT
   #define RVTEST_IO_WRITE_STR(_SP, _STR)
   #define RVTEST_IO_CHECK()
   #define RVTEST_IO_ASSERT_GPR_EQ(_SP, _R, _I)
   #define RVTEST_IO_ASSERT_SFPR_EQ(_F, _R, _I)
   #define RVTEST_IO_ASSERT_DFPR_EQ(_D, _R, _I)

   /* Override RVTEST_PASS from riscv-compliance — must NOT contain ecall.
    * The EH2 trap handler interprets ecall as a FAIL, and the exit protocol
    * is handled by signature_dump in startup.S (via j signature_dump from
    * RV_COMPLIANCE_CODE_END). */
   #undef RVTEST_PASS
   #define RVTEST_PASS  fence

逐段解释：

* 第 L11-L16 行：IO 宏全部为空，说明 EH2 compliance device 不通过这些宏输出结果。
* 第 L18-L24 行：`RVTEST_PASS` 被改写成 `fence`，注释说明 EH2 trap handler 会把
  ecall 解释为 FAIL，正常退出由 `RV_COMPLIANCE_CODE_END` 跳到 `signature_dump` 完成。

接口关系：

* 被调用：上游 compliance 环境 include。
* 调用：无函数调用；通过宏替换影响汇编展开。
* 共享状态：与 `startup.S` 的 `signature_dump` 和 trap handler 形成协议。

§7.3  ``startup.S`` — reset、signature dump 和 trap fail
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：设置 trap vector、清 BSS、调用 `test_entry`，随后把 `.signature` 内容写到
mailbox。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/startup.S:L16-L29``）：

.. code-block:: bash

   .globl _start
   _start:
       la   t0, trap_vector
       csrw mtvec, t0
       // Clear BSS
       la   t0, _bss_start
       la   t1, _bss_end
   1:  bge  t0, t1, 2f
       sw   zero, 0(t0)
       addi t0, t0, 4
       j    1b
   2:  jal  ra, test_entry
       // Fall through to signature_dump if test returns via ret

逐段解释：

* 第 L16-L19 行：`_start` 首先把 `mtvec` 写成 `trap_vector`。
* 第 L20-L26 行：启动代码用 `_bss_start` 到 `_bss_end` 的范围清零 BSS。
* 第 L27-L29 行：清零后调用 `test_entry`；如果 test 通过 ret 返回，则顺序落入
  `signature_dump`。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/startup.S:L33-L46``）：

.. code-block:: bash

   .globl signature_dump
   signature_dump:
       lui  s0, 0xD0580            // s0 = mailbox base
       la   t0, begin_signature
       la   t1, end_signature
   sig_loop:
       bge  t0, t1, sig_done
       lw   t2, 0(t0)              // load 32-bit word
       // Write as 8 hex chars
       // Word goes MSB-first in the hex output (like reference format)
       srli t3, t2, 28              // nibble 7
       andi t3, t3, 0xF
       jal  ra, hex_nibble
       sw   t3, 0(s0)

逐段解释：

* 第 L33-L37 行：`signature_dump` 将 `s0` 设为 mailbox base，`t0/t1` 分别指向
  `begin_signature` 和 `end_signature`。
* 第 L38-L40 行：loop 在地址达到 end 前每次读一个 32-bit word。
* 第 L41-L46 行：签名 word 按 MSB-first 转成 8 个 hex 字符；这里展示的是最高 nibble
  的处理，后续代码对其他 nibble 重复同一模式。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/startup.S:L71-L91``）：

.. code-block:: bash

       andi t3, t2, 0xF             // nibble 0
       jal  ra, hex_nibble
       sw   t3, 0(s0)
       addi t0, t0, 4
       j    sig_loop
   sig_done:
       li   t2, 0xFF
       sw   t2, 0(s0)
       // Newline
       li   t2, 0x0A
       sw   t2, 0(s0)
   5:  wfi
       j 5b

   // Convert nibble to hex char
   hex_nibble:
       addi t3, t3, 0x30
       li   t4, 0x39
       ble  t3, t4, 9f
       addi t3, t3, 0x27
   9:  ret

逐段解释：

* 第 L71-L75 行：最低 nibble 写出后，签名地址加 4，然后回到 `sig_loop`。
* 第 L76-L83 行：签名结束后写 `0xFF` PASS token，再写 newline `0x0A`，随后停在
  `wfi` 循环。
* 第 L85-L91 行：`hex_nibble` 把 0 到 15 转成 ASCII hex 字符；大于 `0x39` 时加
  `0x27`，得到 `a-f`。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/startup.S:L93-L111``）：

.. code-block:: bash

   // ---------------------------------------------------------------------------
   // Trap vector — 64-byte aligned for direct mode
   // ---------------------------------------------------------------------------
   .align 6
   .globl trap_vector
   trap_vector:
       j trap_handler

   // ---------------------------------------------------------------------------
   // Trap handler — signal FAIL via mailbox
   // ---------------------------------------------------------------------------
   trap_handler:
       csrr t0, mcause
       lui  t1, 0xD0580
       li   t2, 0x01              // FAIL token
       sw   t2, 0(t1)
       sw   t0, 0(t1)             // mcause for debug
   6:  wfi
       j 6b

逐段解释：

* 第 L93-L99 行：trap vector 64 字节对齐，并直接跳到 `trap_handler`。
* 第 L104-L109 行：trap handler 读取 `mcause`，向 mailbox 写 `0x01` FAIL token，
  随后写 `mcause`。
* 第 L110-L111 行：fail 后停在 `wfi` 循环。

接口关系：

* 被调用：reset vector、`RV_COMPLIANCE_CODE_END` 跳转、trap vector。
* 调用：mailbox write、`hex_nibble`。
* 共享状态：`begin_signature`、`end_signature`、`_bss_start`、`_bss_end`。

§7.4  ``link.ld`` — 可加载签名段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：将 text/data/signature/bss 放入从 `0x80000000` 开始的 RAM，并定义
`begin_signature`。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/link.ld:L4-L16``）：

.. code-block:: bash

   OUTPUT_ARCH(riscv)
   ENTRY(_start)

   PHDRS
   {
       text PT_LOAD FLAGS(5);  /* R+X */
       data PT_LOAD FLAGS(6);  /* R+W */
   }

   MEMORY
   {
       ram (rwx) : ORIGIN = 0x80000000, LENGTH = 0x04000000
   }

逐段解释：

* 第 L4-L5 行：输出架构是 RISC-V，入口是 `_start`。
* 第 L7-L11 行：linker script 定义两个 loadable program header：text 为 R+X，
  data 为 R+W。
* 第 L13-L16 行：RAM 起点是 `0x80000000`，长度是 `0x04000000`。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/link.ld:L18-L54``）：

.. code-block:: bash

   SECTIONS
   {
       .text.init : {
           KEEP(*(.text.init))
       } > ram :text

       .text : {
           *(.text)
           *(.text.*)
       } > ram :text

       .rodata : {
           *(.rodata)
           *(.rodata.*)
       } > ram :text

       .data : {
           *(.data)
           *(.data.*)
       } > ram :data

逐段解释：

* 第 L18-L27 行：`.text.init` 和 `.text` 放入 RAM 的 text PHDR；`KEEP(*(.text.init))`
  保证启动段不被丢弃。
* 第 L29-L37 行：`.rodata` 放入 text PHDR，`.data` 放入 data PHDR。

关键代码（``dv/uvm/riscv_compliance/device/rv32i/link.ld:L39-L54``）：

.. code-block:: bash

       /* Compliance signature section.
        * begin_signature marks the start; test data follows via
        * RV_COMPLIANCE_DATA_BEGIN/END which sets end_signature. */
       .signature : {
           begin_signature = .;
       } > ram :data

       .bss : {
           _bss_start = .;
           *(.bss)
           *(.bss.*)
           _bss_end = .;
       } > ram :data

       _end = .;
   }

逐段解释：

* 第 L39-L44 行：`.signature` 放入 data PHDR，并在段起点定义 `begin_signature`。
  `end_signature` 由 `compliance_test.h` 的 data end 宏定义。
* 第 L46-L51 行：`.bss` 同样放入 data PHDR，并导出 `_bss_start` 与 `_bss_end`，
  供 `startup.S` 清零。
* 第 L53 行：`_end` 标记最终链接地址。

接口关系：

* 被调用：GCC link command 通过 `-T<device_dir>/link.ld` 使用。
* 调用：无运行时调用；定义 linker symbols。
* 共享状态：`_start`、`begin_signature`、`_bss_start`、`_bss_end`。

§8  Standalone compliance TB
----------------------------

standalone TB 位于 :file:`dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv`。当前
Makefile 提供 VCS 编译目标；runner 的默认运行路径仍使用 `build/simv` 和
`core_eh2_base_test`，但 `run_simulation()` 也支持解析 standalone TB 输出的
`SIGNATURE:` 行。

§8.1  时钟、复位、默认信号和 binary 加载
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供 standalone top module 的时钟复位、默认输入和 `+bin=` hex 加载。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L26-L45``）：

.. code-block:: systemverilog

   module eh2_compliance_tb;

     //--------------------------------------------------------------------------
     // Clock and Reset
     //--------------------------------------------------------------------------
     bit core_clk;
     initial begin
       core_clk = 0;
       forever #5 core_clk = ~core_clk;  // 100 MHz
     end

     logic rst_l;       // Active-low core reset
     logic porst_l;     // Power-on reset

     //--------------------------------------------------------------------------
     // DUT signal declarations (shared via core_eh2_tb_top include)
     //--------------------------------------------------------------------------
     // NOTE: rst_l, porst_l, core_clk declared above; all other signals
     //       (AXI, trace, interrupts, JTAG, control) come from the include.
   `include "core_eh2_dut_signals.svh"

逐段解释：

* 第 L26-L35 行：TB 定义 `core_clk`，周期为 10 ns。
* 第 L37-L45 行：`rst_l` 和 `porst_l` 在本文件中声明，其余 DUT 信号通过
  `core_eh2_dut_signals.svh` 引入。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L59-L95``）：

.. code-block:: systemverilog

   initial begin
     rst_l   = 0;
     porst_l = 0;
     repeat (3) @(posedge core_clk);
     porst_l = 1;
     repeat (3) @(posedge core_clk);
     rst_l   = 1;
   end

   //--------------------------------------------------------------------------
   // Default Signal Values
   //--------------------------------------------------------------------------
   initial begin
     reset_vector       = 32'h80000000;
     nmi_vector         = 32'h00000000;
     jtag_id            = 31'h1;
     lsu_bus_clk_en     = 1;

逐段解释：

* 第 L59-L66 行：TB 先拉低 reset，3 个上升沿后释放 `porst_l`，再过 3 个上升沿释放
  `rst_l`。
* 第 L71-L79 行：默认 reset vector 是 `0x80000000`，NMI vector 是 0，JTAG ID 是 1，
  各 AXI bus clock enable 置 1。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L81-L95``）：

.. code-block:: systemverilog

   //--------------------------------------------------------------------------
   // Early Binary Loading
   //--------------------------------------------------------------------------
   string hex_path;
   initial begin
     if ($value$plusargs("bin=%s", hex_path) && hex_path.len() > 0) begin
       $display("COMPLIANCE_TB: Loading hex file: %s", hex_path);
       $readmemh(hex_path, lsu_mem.mem);
       $readmemh(hex_path, ifu_mem.mem);
       $readmemh(hex_path, sb_mem.mem);
       $display("COMPLIANCE_TB: Hex load complete");
     end else begin
       $display("COMPLIANCE_TB: WARNING - no +bin=<hex> argument provided");
     end
   end

逐段解释：

* 第 L84-L91 行：TB 读取 `+bin=<hex>` plusarg，并将同一 hex 加载到 `lsu_mem`、
  `ifu_mem` 和 `sb_mem`。
* 第 L92-L94 行：没有 `+bin` 时只打印 warning，不在该 initial block 中终止 simulation。

接口关系：

* 被调用：`compile-compliance-tb` 编译出的 standalone simulator。
* 调用：`$value$plusargs()`、`$readmemh()`。
* 共享状态：`lsu_mem.mem`、`ifu_mem.mem`、`sb_mem.mem`。

§8.2  mailbox 监视和 signature dump FSM
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：监视 LSU AXI 写地址，捕获 signature begin/end 和 halt 请求，并从 memory 中
打印签名 word。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L109-L132``）：

.. code-block:: systemverilog

   // Detect valid write from LSU AXI AW+W channels
   assign mailbox_write_valid = lsu_axi_awvalid && lsu_axi_awready;
   assign mailbox_write_addr  = lsu_axi_awaddr;
   assign mailbox_write_data  = lsu_axi_wdata;

   // Mailbox address capture — combinational detection
   logic mb_halt_req, mb_set_begin, mb_set_end;
   assign mb_halt_req  = rst_l && mailbox_write_valid && (mailbox_write_addr == 32'hD058_0000);
   assign mb_set_begin = rst_l && mailbox_write_valid && (mailbox_write_addr == 32'hD058_0004);
   assign mb_set_end   = rst_l && mailbox_write_valid && (mailbox_write_addr == 32'hD058_0008);

   always @(posedge core_clk) begin
     if (mb_set_begin) begin
       sig_begin_addr <= mailbox_write_data;
       $display("COMPLIANCE_TB: signature begin = 0x%08x", mailbox_write_data);

逐段解释：

* 第 L109-L112 行：TB 用 LSU AXI AW handshake 识别 mailbox write，并取 AWADDR 与 WDATA。
* 第 L115-L118 行：三个 mailbox 地址分别对应 halt、set begin、set end。
* 第 L120-L124 行：begin 写入时保存 `sig_begin_addr` 并打印。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L124-L132``）：

.. code-block:: systemverilog

     end
     if (mb_set_end) begin
       sig_end_addr <= mailbox_write_data;
       $display("COMPLIANCE_TB: signature end   = 0x%08x", mailbox_write_data);
     end
     if (mb_halt_req) begin
       $display("COMPLIANCE_TB: HALT signal received at %0t", $time);
     end
   end

逐段解释：

* 第 L125-L128 行：end 写入时保存 `sig_end_addr` 并打印。
* 第 L129-L131 行：halt 写入时打印收到 HALT 和当前时间；真正 dump 在后面的 FSM 中执行。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L134-L163``）：

.. code-block:: systemverilog

   // Signature dump FSM
   typedef enum logic [1:0] {
     IDLE, DUMPING, DONE
   } dump_state_e;
   dump_state_e dump_state;
   logic [31:0] dump_addr;
   int          dump_delay;

   always @(posedge core_clk or negedge rst_l) begin
     if (!rst_l) begin
       dump_state       <= IDLE;
       dump_addr        <= 0;
       dump_delay       <= 0;
       sig_begin_addr   <= 32'hFFFF_FFFF;
       sig_end_addr     <= 0;
     end else begin

逐段解释：

* 第 L134-L140 行：FSM 状态为 `IDLE`、`DUMPING`、`DONE`，并维护 `dump_addr` 与
  `dump_delay`。
* 第 L142-L149 行：reset 时状态回到 `IDLE`，signature begin 被设为
  `0xFFFF_FFFF`，end 被清 0。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L150-L190``）：

.. code-block:: systemverilog

       case (dump_state)
         IDLE: begin
           if (mb_halt_req) begin
             if (sig_begin_addr == 32'hFFFF_FFFF || sig_end_addr == 0) begin
               $display("COMPLIANCE_TB: WARNING - signature bounds not set, using default");
               sig_begin_addr = 32'h8000_1000;
               sig_end_addr   = 32'h8000_2000;
             end
             $display("COMPLIANCE_TB: Dumping signature from 0x%08x to 0x%08x",
                      sig_begin_addr, sig_end_addr);
             dump_delay <= 2;
             dump_addr  <= sig_begin_addr;
             dump_state <= DUMPING;

逐段解释：

* 第 L150-L163 行：`IDLE` 状态在 halt 请求后开始 dump；如果 signature bounds 没有设置，
  TB 使用 `0x8000_1000` 到 `0x8000_2000` 的默认范围。
* 第 L158-L162 行：开始 dump 前打印范围，等待 2 个周期，并把 `dump_addr` 设为
  `sig_begin_addr`。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L166-L190``）：

.. code-block:: systemverilog

         DUMPING: begin
           if (dump_delay > 0) begin
             dump_delay <= dump_delay - 1;
           end else begin
             if (dump_addr < sig_end_addr) begin
               $display("SIGNATURE: %08x", {
                 read_mem_byte(dump_addr + 3),
                 read_mem_byte(dump_addr + 2),
                 read_mem_byte(dump_addr + 1),
                 read_mem_byte(dump_addr + 0)
               });
               dump_addr <= dump_addr + 4;
             end else begin
               dump_state <= DONE;

逐段解释：

* 第 L166-L169 行：DUMPING 状态先消耗 `dump_delay`。
* 第 L170-L177 行：只要 `dump_addr < sig_end_addr`，TB 就按 byte 3、2、1、0 的顺序
  组装 32-bit word，并打印 `SIGNATURE: %08x`。
* 第 L177-L180 行：每打印一个 word 后地址加 4；到达 end 后进入 DONE。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L184-L200``）：

.. code-block:: systemverilog

         DONE: begin
           $display("COMPLIANCE_TB: Signature dump complete. Terminating.");
           $finish;
         end
       endcase
     end
   end

   // Read a byte from AXI memory (hierarchical access)
   function automatic logic [7:0] read_mem_byte(input logic [31:0] addr);
     if (ifu_mem.mem.exists(addr))
       return ifu_mem.mem[addr];
     else if (lsu_mem.mem.exists(addr))
       return lsu_mem.mem[addr];
     else
       return 8'h00;
   endfunction

逐段解释：

* 第 L184-L187 行：DONE 状态打印完成信息，并调用 `$finish` 结束 simulation。
* 第 L192-L200 行：`read_mem_byte()` 优先读 `ifu_mem.mem`，其次读 `lsu_mem.mem`，
  两者都不存在时返回 0。

接口关系：

* 被调用：mailbox write、signature dump FSM。
* 调用：`read_mem_byte()`、`$display()`、`$finish()`。
* 共享状态：LSU AXI write channel、`sig_begin_addr`、`sig_end_addr`、
  IFU/LSU memory。

§8.3  DUT、AXI memory、timeout 和 trace
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 EH2 wrapper，连接 LSU/IFU/SB AXI memory，关闭 DMA 输入，并提供安全
timeout 与 trace 输出。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L208-L217``）：

.. code-block:: systemverilog

   `ifdef RV_BUILD_AXI4
     eh2_veer_wrapper dut (
       .clk                    (core_clk),
       .rst_l                  (rst_l),
       .dbg_rst_l              (porst_l),
       .rst_vec                (reset_vector[31:1]),
       .nmi_int                (nmi_int),
       .nmi_vec                (nmi_vector[31:1]),
       .jtag_id                (jtag_id[31:1]),

逐段解释：

* 第 L208-L217 行：DUT 只在 `RV_BUILD_AXI4` 定义时实例化；clock/reset、reset vector、
  NMI、JTAG ID 均连接到 TB 信号。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L385-L436``）：

.. code-block:: systemverilog

       // JTAG — inactive, keep clock alive
       .jtag_tck          (core_clk),
       .jtag_tms          (1'b0),
       .jtag_tdi          (1'b0),
       .jtag_trst_n       (1'b1),
       .jtag_tdo          (jtag_tdo),

       // Interrupts — tied off for compliance
       .timer_int         ('0),
       .soft_int          ('0),
       .extintsrc_req     ('0),

       // Clock enables
       .lsu_bus_clk_en    (lsu_bus_clk_en),
       .ifu_bus_clk_en    (ifu_bus_clk_en),
       .dbg_bus_clk_en    (dbg_bus_clk_en),
       .dma_bus_clk_en    (dma_bus_clk_en),

逐段解释：

* 第 L385-L390 行：JTAG TCK 接 core clock，TMS/TDI 置 0，TRST_N 置 1。
* 第 L392-L395 行：timer、software 和 external interrupt 全部 tie off。
* 第 L397-L401 行：四个 bus clock enable 连接到 TB 默认置 1 的信号。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L410-L436``）：

.. code-block:: systemverilog

       // MPC halt/run — let core run freely after reset
       .mpc_debug_halt_req ('0),
       .mpc_debug_run_req  ({`RV_NUM_THREADS{1'b1}}),
       .mpc_reset_run_req  ({`RV_NUM_THREADS{1'b1}}),
       .mpc_debug_halt_ack (),
       .mpc_debug_run_ack  (),
       .debug_brkpt_status (),
       .dec_tlu_mhartstart (),

       // CPU halt/run — let core run freely
       .i_cpu_halt_req     ('0),
       .o_cpu_halt_ack     (),
       .o_cpu_halt_status  (),
       .i_cpu_run_req      ({`RV_NUM_THREADS{1'b1}}),
       .o_cpu_run_ack      (),

逐段解释：

* 第 L410-L417 行：MPC halt 请求 tie off，run/reset run 请求按 `RV_NUM_THREADS` 全部置 1。
* 第 L419-L424 行：CPU halt 请求 tie off，CPU run 请求按 `RV_NUM_THREADS` 全部置 1。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L441-L468``）：

.. code-block:: systemverilog

   // AXI4 Slave Memory Models (only when building AXI4 config)
   //--------------------------------------------------------------------------
   `ifdef RV_BUILD_AXI4
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_LSU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) lsu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (1'b0),
       .force_bresp       (2'b00),
       .force_rresp       (2'b00),
       .awid     (lsu_axi_awid),

逐段解释：

* 第 L441-L449 行：LSU memory 是 32-bit address、64-bit data，ID width 使用
  `RV_LSU_BUS_TAG`，memory size 是 64 MiB。
* 第 L450-L468 行：memory clock/reset 与 LSU AXI write response 信号连接，error
  injection 和 forced response 都关闭。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L486-L590``）：

.. code-block:: systemverilog

     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_IFU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) ifu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (1'b0),
       .force_bresp       (2'b00),
       .force_rresp       (2'b00),
       .awid     (ifu_axi_awid),

逐段解释：

* 第 L486-L491 行：IFU memory 与 LSU memory 参数形状相同，但 ID width 使用
  `RV_IFU_BUS_TAG`。
* 第 L528-L533 行：SB memory 也使用 32-bit address、64-bit data、64 MiB size，
  ID width 使用 `RV_SB_BUS_TAG`。
* 第 L570-L590 行：DMA AXI port 没有外部 master，valid、addr、data、ready 等输入
  全部 tie off 到 inactive 值。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L593-L611``）：

.. code-block:: systemverilog

   //--------------------------------------------------------------------------
   // Safety Timeout
   //--------------------------------------------------------------------------
   initial begin
     #(64'd1_800_000_000_000);  // 30 minutes
     $display("COMPLIANCE_TB: TIMEOUT - simulation stopped");
     $finish;
   end

   //--------------------------------------------------------------------------
   // Simple trace monitor for debugging
   //--------------------------------------------------------------------------
   always_ff @(posedge core_clk) begin
     if (rst_l && trace_rv_i_valid_ip[0][0]) begin
       $display("TRACE: PC=%08h INSN=%08h",
                trace_rv_i_address_ip[0][31:0],

逐段解释：

* 第 L593-L600 行：standalone TB 设置 30 分钟安全超时，超时后打印并结束。
* 第 L605-L611 行：trace monitor 在 reset 释放且 `trace_rv_i_valid_ip[0][0]` 为真时
  打印 PC 和 instruction。

接口关系：

* 被调用：standalone simulator。
* 调用：`eh2_veer_wrapper`、`axi4_slave_mem`、trace monitor。
* 共享状态：AXI memory、DUT trace port、`RV_NUM_THREADS`。

§8.4  Verilator C++ harness
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供 Verilator 模式下的简单 C++ harness，解析 plusarg，驱动
`Veh2_compliance_tb` clock，直到 `$finish` 或 `max_cycles`。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc:L25-L40``）：

.. code-block:: cpp

   static std::string hex_path;
   static std::string signature_path;
   static long long max_cycles = 10000000LL;

   static void parse_args(int argc, char **argv) {
     for (int i = 1; i < argc; ++i) {
       std::string arg(argv[i]);
       if (arg.rfind("+bin=", 0) == 0) {
         hex_path = arg.substr(5);
       } else if (arg.rfind("+signature=", 0) == 0) {
         signature_path = arg.substr(12);
       } else if (arg.rfind("+max_cycles=", 0) == 0) {
         max_cycles = std::atoll(arg.substr(13).c_str());
       }
     }
   }

逐段解释：

* 第 L25-L27 行：harness 保存 hex 路径、signature 路径和默认 10000000 cycle 上限。
* 第 L29-L40 行：`parse_args()` 解析 `+bin=`、`+signature=` 和 `+max_cycles=`。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc:L45-L89``）：

.. code-block:: cpp

   int main(int argc, char **argv) {
     Verilated::commandArgs(argc, argv);
     parse_args(argc, argv);

     Veh2_compliance_tb *top = new Veh2_compliance_tb;

     // Redirect stdout to capture SIGNATURE lines
     std::string sim_stdout_path = (signature_path.empty())
         ? "compliance_stdout.log"
         : signature_path + ".log";
     FILE *log_fd = std::fopen(sim_stdout_path.c_str(), "w");
     if (!log_fd) {
       std::cerr << "ERROR: cannot open log file " << sim_stdout_path << "\n";
       return 1;
     }

逐段解释：

* 第 L45-L49 行：`main()` 传递 Verilator 参数、解析本地 plusarg，并实例化
  `Veh2_compliance_tb`。
* 第 L51-L59 行：harness 根据 `+signature=` 选择 log 文件名，打开失败时返回 1。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc:L61-L89``）：

.. code-block:: cpp

     // Simulation loop
     top->core_clk = 0;
     top->eval();
     long long cycle = 0;

     while (!Verilated::gotFinish() && cycle < max_cycles) {
       // Toggle clock
       top->core_clk = !top->core_clk;
       top->eval();

       if (top->core_clk) {
         cycle++;
       }

       // After a $finish in the DUT, Verilator sets gotFinish
       if (Verilated::gotFinish()) break;
     }

逐段解释：

* 第 L61-L64 行：初始化 clock 并执行一次 eval。
* 第 L66-L77 行：循环翻转 `core_clk`，高电平时 cycle 计数加一；循环条件同时受
  `Verilated::gotFinish()` 和 `max_cycles` 限制。

关键代码（``dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc:L79-L89``）：

.. code-block:: cpp

     // Extract SIGNATURE: lines from the simulation stdout
     // (In Verilator, $display goes to stdout by default)
     // For a real flow, capture is done via the sim log

     std::fclose(log_fd);
     top->final();
     delete top;

     std::cout << "COMPLIANCE_TB: simulation complete, " << cycle/2 << " cycles" << std::endl;
     return 0;
   }

逐段解释：

* 第 L79-L82 行：注释说明 Verilator 下 `$display` 默认进入 stdout，真实 flow 通过
  sim log 捕获。
* 第 L83-L89 行：关闭 log、执行 `final()`、释放 top，并打印运行 cycle 数后返回 0。

接口关系：

* 被调用：Verilator 构建产物。
* 调用：`Veh2_compliance_tb`、Verilator runtime。
* 共享状态：`+bin=`、`+signature=`、`+max_cycles=` plusarg。

§9  结果重扫与已知失败
----------------------

`collect_compliance.py` 可以重扫 `work/` 目录，从已经生成的 `.signature.output` 和
`.log` 文件重建 `report.json`。`known_fail.yaml` 记录 compliance gate 允许或跟踪的
已知差异；`signoff.py` 对 `rv32Zifencei` 有单独已知失败数量检查。

§9.1  ``collect_compliance.py`` — 重扫 work 目录
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在不重新运行 simulator 的情况下，基于 work 目录中的 signature output 和 log
重建总报告与 per-ISA 报告。

关键代码（``dv/uvm/riscv_compliance/scripts/collect_compliance.py:L12-L19``）：

.. code-block:: python

   SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
   EH2_ROOT = os.path.realpath(os.path.join(SCRIPT_DIR, "..", "..", "..", ".."))
   COMPLIANCE_DIR = os.path.join(EH2_ROOT, "dv", "uvm", "riscv_compliance")
   RISCV_COMPLIANCE_FW = "/home/host/riscv-compliance"
   WORK_DIR = os.path.join(COMPLIANCE_DIR, "work")

   ISAS = ["rv32i", "rv32im", "rv32imc", "rv32Zicsr", "rv32Zifencei"]

逐段解释：

* 第 L12-L16 行：collector 从自身路径推导 EH2 根目录、compliance 目录和 `work`
  目录，上游 framework 路径固定为 `/home/host/riscv-compliance`。
* 第 L18 行：collector 的 ISA 列表与 runner 支持列表一致。

关键代码（``dv/uvm/riscv_compliance/scripts/collect_compliance.py:L21-L72``）：

.. code-block:: python

   def load_hex_words(path):
       """Load a file of 32-bit hex words, one per line."""
       if not os.path.exists(path):
           return []
       words = []
       with open(path, "r") as f:
           for line in f:
               line = line.strip()
               if re.match(r'^[0-9a-fA-F]{8}$', line):
                   words.append(line.lower())
       return words

   def words_to_bytes(words):
       """Convert list of 8-char hex words to byte stream (big-endian)."""
       b = bytearray()

逐段解释：

* 第 L21-L31 行：`load_hex_words()` 与 runner 的 `load_reference()` 同样只保留 8 位
  hex word。
* 第 L34-L41 行：`words_to_bytes()` 用 big-endian 分解 32-bit word。
* 第 L44-L72 行：`compare_signatures()` 复用相同的 byte-level 比较策略，并在 mismatch
  时返回 byte index 或 length mismatch detail。

关键代码（``dv/uvm/riscv_compliance/scripts/collect_compliance.py:L75-L123``）：

.. code-block:: python

   def collect_isa(isa):
       """Collect all test results for one ISA suite."""
       work_isa_dir = os.path.join(WORK_DIR, isa)
       ref_dir = os.path.join(RISCV_COMPLIANCE_FW, "riscv-test-suite", isa, "references")

       if not os.path.isdir(work_isa_dir):
           return []

       tests = []
       seen_names = set()

       for fname in sorted(os.listdir(work_isa_dir)):
           if not fname.endswith(".signature.output"):
               continue
           # e.g. I-ADD-01.signature.output -> test_name = I-ADD-01
           test_name = fname[:-len(".signature.output")]

逐段解释：

* 第 L75-L81 行：`collect_isa()` 按 ISA 找 work 子目录和 reference 目录；work 子目录不存在
  时返回空列表。
* 第 L83-L90 行：函数遍历 `.signature.output` 文件，并从文件名去掉后缀得到 test name。
* 第 L91-L123 行：collector 加载 actual 和 reference，执行比较，并生成与 sign-off
  schema 兼容的 test entry。

关键代码（``dv/uvm/riscv_compliance/scripts/collect_compliance.py:L126-L155``）：

.. code-block:: python

   # Also find tests that ran but produced no signature (only .log present)
   for fname in sorted(os.listdir(work_isa_dir)):
       if not fname.endswith(".log"):
           continue
       test_name = fname[:-len(".log")]
       if test_name in seen_names:
           continue
       tests.append({
           "name": test_name,
           "seed": 0,
           "type": "compliance_" + isa,
           "passed": False,
           "failure_mode": "no_signature",
           "sim_log": os.path.join(work_isa_dir, fname),

逐段解释：

* 第 L126-L132 行：collector 还扫描 `.log` 文件，补充那些运行过但没有生成
  `.signature.output` 的 test。
* 第 L133-L153 行：这类 test 被标记为 `passed=False`、`failure_mode=no_signature`，
  并把 sim log 路径写入报告。
* 第 L155 行：返回该 ISA 的 test 列表。

关键代码（``dv/uvm/riscv_compliance/scripts/collect_compliance.py:L158-L193``）：

.. code-block:: python

   def main():
       all_tests = []
       suite_stats = {}

       for isa in ISAS:
           tests = collect_isa(isa)
           all_tests.extend(tests)
           passed = sum(1 for t in tests if t["passed"])
           total = len(tests)
           suite_stats[isa] = {"total": total, "passed": passed,
                               "failed": total - passed}
           print("{}: {}/{} PASS ({} tests)".format(isa, passed, total, total))

       total_pass = sum(1 for t in all_tests if t["passed"])

逐段解释：

* 第 L158-L169 行：`main()` 遍历所有 ISA，打印每个 ISA 的 passed/total。
* 第 L171-L183 行：总报告写到 `WORK_DIR/report.json`。
* 第 L185-L193 行：每个 ISA 还会写一个 `WORK_DIR/<isa>/report.json`，供
  `signoff.py evaluate_compliance_per_suite()` 读取。

接口关系：

* 被调用：手工重建报告命令。
* 调用：`collect_isa()`、`compare_signatures()`、`json.dump()`。
* 共享状态：`dv/uvm/riscv_compliance/work` 与上游 references。

§9.2  ``known_fail.yaml`` — 已知差异清单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：记录 compliance 中已知失败 test、分类、原因、tracking issue 和过期日期。

关键代码（``dv/uvm/riscv_compliance/known_fail.yaml:L1-L12``）：

.. code-block:: text

   # EH2 RISC-V Compliance Known Failures
   # Each entry requires: test, reason, tracking_issue, expiry_date

   - test: "I-MISALIGN_LDST-01"
     type: "compliance_rv32i"
     reason: >
       EH2 treats unsupported misaligned load/store as illegal instruction
       (mcause=2) rather than separate load/store misaligned exceptions
       (mcause=4/6). The reference model expects rv32i-compliant mcause
       values. This is an EH2 architectural simplification.
     tracking_issue: "EH2-ARCH-001"
     expiry_date: "2026-12-31"

逐段解释：

* 第 L1-L2 行：文件声明每个条目需要 `test`、`reason`、`tracking_issue` 和
  `expiry_date`。
* 第 L4-L12 行：`I-MISALIGN_LDST-01` 的类型是 `compliance_rv32i`，原因描述为 EH2
  对不支持的 misaligned load/store 使用 illegal instruction，而 reference 期望
  load/store misaligned exception。

关键代码（``dv/uvm/riscv_compliance/known_fail.yaml:L14-L32``）：

.. code-block:: text

   - test: "I-MISALIGN_JMP-01"
     type: "compliance_rv32i"
     reason: >
       EH2 does not support misaligned instruction fetch. A misaligned
       jump target causes an infinite exception loop (mcause=0 re-fetches
       same misaligned address). Test times out after 500K cycles.
       Hardware limitation of EH2's fetch unit.
     tracking_issue: "EH2-ARCH-002"
     expiry_date: "2026-12-31"

   - test: "I-FENCE.I-01"
     type: "compliance_rv32Zifencei"
     reason: >

逐段解释：

* 第 L14-L22 行：`I-MISALIGN_JMP-01` 的类型是 `compliance_rv32i`，原因描述为 EH2 不支持
  misaligned instruction fetch，test 在 500K cycle 后 timeout。
* 第 L24-L27 行：`I-FENCE.I-01` 的类型是 `compliance_rv32Zifencei`，原因文本继续说明
  fence.i 与 I$/D$ 同步差异。

关键代码（``dv/uvm/riscv_compliance/known_fail.yaml:L24-L32``）：

.. code-block:: text

   - test: "I-FENCE.I-01"
     type: "compliance_rv32Zifencei"
     reason: >
       EH2 fence.i does not fully synchronize I$ with D$ stores.
       Self-modifying code test stores new instructions, executes fence.i,
       but I$ returns stale (zero) data. Signature expected
       0x00000012/0x00000042 but got 0x00000000/0x00000000.
     tracking_issue: "EH2-ARCH-003"
     expiry_date: "2026-12-31"

逐段解释：

* 第 L24-L32 行：`I-FENCE.I-01` 的 reason 说明 self-modifying code 写入新指令并执行
  fence.i 后，I$ 返回旧的 zero data；期望签名和实际签名在该条目中列出。

接口关系：

* 被调用：文档、人工 review 和 sign-off gate 语义。
* 调用：无执行代码。
* 共享状态：`type` 字段与 `report.json` 中 `compliance_<isa>` 分类一致。

§10  Sign-off 集成
--------------------------------------------------------------------------------

`signoff.py` 将 compliance 纳入 `full` profile，并在运行后执行 per-suite gate。该集成
依赖 runner 的 `--isa all`、per-ISA `report.json` 和 aggregated report。

§10.1  profile 和最小通过数
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 `full` profile 包含 compliance，并给 compliance 设置 stage-level
最小通过数 85。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L37-L53``）：

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

* 第 L37-L43 行：`full` profile 包含 compliance，位置在 `csr_unit` 之后、`formal`
  之前。
* 第 L46-L53 行：stage-level minimum passed 对 compliance 是 85，与当前 VCS demo
  85/88 (96.59%) 结果相匹配。

接口关系：

* 被调用：`signoff.py` profile 解析。
* 调用：后续 `build_stage_cmd()` 和 `collect_stage()`。
* 共享状态：`PROFILE_STAGES`、`STAGE_MIN_PASSED`。

§10.2  ``build_stage_cmd()`` 中的 compliance 命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 sign-off stage 为 compliance 构造 runner 命令，固定执行 `--isa all`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L224-L238``）：

.. code-block:: python

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

逐段解释：

* 第 L224-L229 行：同一区域还处理 lint 和 CSR unit，说明 compliance 与这些 stage 都是
  sign-off 中的非 regression stage。
* 第 L230-L238 行：compliance stage 使用当前 Python 解释器运行
  `run_compliance.py --isa all --simv build/simv --output <stage_out>`。

接口关系：

* 被调用：`signoff.py` 主流程按 stage 构造命令。
* 调用：`run_compliance.py`。
* 共享状态：`stage_out` 目录会包含 per-ISA 子目录和 aggregated report。

§10.3  ``evaluate_compliance_per_suite()`` — suite-level gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：读取 compliance 结果目录中的 per-ISA report，并按 suite 设置 pass-rate
阈值。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L776-L790``）：

.. code-block:: python

   def evaluate_compliance_per_suite(results_dir: Path) -> List[str]:
       """Per-suite compliance gate (rv32i ≥95%, rv32im/imc/Zicsr =100%).

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

逐段解释：

* 第 L776-L782 行：函数返回 blocker 字符串列表，空列表表示 suite gate 通过。
* 第 L784-L790 行：`rv32i` 阈值为 95.0；`rv32im`、`rv32imc` 和 `rv32Zicsr` 阈值为
  100.0；`rv32Zifencei` 单独允许 1 个 known fail。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L792-L823``）：

.. code-block:: python

   for isa, threshold in suite_gates.items():
       report_path = results_dir / isa / "report.json"
       if not report_path.exists():
           # Try aggregated report.json
           report_path = results_dir / "report.json"

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

逐段解释：

* 第 L792-L797 行：每个 suite 优先读取 `<results_dir>/<isa>/report.json`；不存在时回退到
  aggregated `<results_dir>/report.json`。
* 第 L798-L807 行：报告不存在或无法解析时，函数向 blockers 追加具体错误。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L810-L823``）：

.. code-block:: python

       suite_tests = [t for t in data.get("tests", [])
                      if t.get("type", "").startswith("compliance_" + isa)]
       total = len(suite_tests)
       passed = sum(1 for t in suite_tests if t.get("passed", False))

       if total == 0:
           continue

       rate = 100.0 * passed / total
       if rate < threshold:
           blockers.append(
               "compliance {} pass rate {:.1f}% below {:.1f}% ({}/{})".format(
                   isa, rate, threshold, passed, total))

逐段解释：

* 第 L810-L813 行：函数只统计 `type` 以 `compliance_<isa>` 开头的 test。
* 第 L815-L816 行：total 为 0 时跳过该 suite，不新增 blocker。
* 第 L818-L823 行：pass rate 低于阈值时追加 blocker，文本包含 suite、实际 rate、
  阈值和 passed/total。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L824-L842``）：

.. code-block:: python

   # rv32Zifencei: treated as PASS when known_fail covers the failures
   zifencei_dir = results_dir / "rv32Zifencei"
   if zifencei_dir.exists():
       zifencei_report = zifencei_dir / "report.json"
       if zifencei_report.exists():
           try:
               data = json.loads(zifencei_report.read_text(encoding="utf-8"))
               zifencei_failed = sum(
                   1 for t in data.get("tests", [])
                   if not t.get("passed", False))
               if zifencei_failed > zifencei_known_fail:
                   blockers.append(
                       "compliance rv32Zifencei {} unexpected failures "
                       "(known_fail covers {})".format(

逐段解释：

* 第 L824-L830 行：`rv32Zifencei` 只在对应目录存在且 report 存在时检查。
* 第 L831-L838 行：失败数超过 `zifencei_known_fail` 时追加 blocker，文本中写出实际失败
  数和 known-fail 覆盖数量。
* 第 L839-L842 行：解析异常被忽略，函数返回已累计的 blockers。

接口关系：

* 被调用：`signoff.py main()` 在 compliance stage 收集后调用。
* 调用：`json.loads()`、per-ISA report。
* 共享状态：依赖 `report.json` 中的 `type= compliance_<isa>` 字段。

§10.4  compliance stage 结果回写
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在通用 stage 收集之后，把 suite-level blocker 合并回 stage result。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1615-L1623``）：

.. code-block:: python

   stage_result = collect_stage(
       stage, results_dir, report_dir, command, exit_code,
       fail_on_warnings=not args.allow_warnings)
   if stage == "compliance":
       suite_blockers = evaluate_compliance_per_suite(results_dir)
       if suite_blockers:
           stage_result["blockers"].extend(suite_blockers)
           stage_result["status"] = "FAIL"
   stage_results.append(stage_result)

逐段解释：

* 第 L1615-L1617 行：非特殊 stage 先通过 `collect_stage()` 得到通用 result。
* 第 L1618-L1622 行：当 stage 是 `compliance` 时，额外执行 per-suite gate；存在
  blocker 时扩展 `stage_result["blockers"]` 并把 status 改成 `FAIL`。
* 第 L1623 行：更新后的 stage result 被加入 sign-off 结果列表。

接口关系：

* 被调用：`signoff.py` 主 stage loop。
* 调用：`collect_stage()`、`evaluate_compliance_per_suite()`。
* 共享状态：`results_dir`、`report_dir`、`args.allow_warnings`。

§11  ADR-0011 对流程的约束
---------------------------

:ref:`adr-0011` 是 compliance framework 的设计依据。该 ADR 明确选择
`riscv-compliance` 作为 primary framework，并要求 signature 做 byte-by-byte comparison。

§11.1  framework 选择和支持套件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明当前使用的上游框架和支持 ISA 列表。

关键代码（``docs/adr/0011-compliance-framework.md:L21-L27``）：

.. code-block:: text

   ## Decision

   **Use riscv-compliance as the primary framework** (rv32i, rv32im, rv32imc,
   rv32Zicsr, rv32Zifencei).  We use the test source files and reference outputs
   from this framework, but compile them with our own EH2 device files (linker
   script, startup code, compliance I/O headers).  The riscv-tests repository is
   a fallback for future expansion.

逐段解释：

* 第 L21-L27 行：ADR 决定使用 `riscv-compliance` 作为 primary framework，列出的 ISA
  是 `rv32i`、`rv32im`、`rv32imc`、`rv32Zicsr`、`rv32Zifencei`；device 文件使用
  EH2 自己的 linker script、startup code 和 compliance I/O headers。

接口关系：

* 被调用：本章、`:ref:`signoff_flow``、ADR 索引。
* 调用：无执行调用。
* 共享状态：与 Makefile 和 runner 中 `SUPPORTED_ISAS` 一致。

§11.2  signature comparison strategy
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：规定签名输出从 `.signature` 到 mailbox、TB、runner 的比较路径。

关键代码（``docs/adr/0011-compliance-framework.md:L29-L41``）：

.. code-block:: text

   ### Signature comparison strategy

   - **Comparer**: byte-by-byte comparison, NO relaxation.
   - **How it works**:
     1. Compliance test writes its results to a `.signature` data section.
     2. At test end, `RV_COMPLIANCE_HALT` writes the begin/end signature addresses
        to the EH2 compliance mailbox (`0xD0580004` / `0xD0580008`), then triggers
        signature dump via a write to `0xD0580000`.
     # ...
     4. The Python runner (`scripts/run_compliance.py`) parses these lines and
        compares each 32-bit word against the reference file byte-by-byte.
   - **Any byte difference = FAIL**.  No approximations, no fuzzy matching.

逐段解释：

* 第 L31-L41 行：ADR 要求 byte-by-byte comparison，流程是 test 写 `.signature`，
  `RV_COMPLIANCE_HALT` 写 begin/end 地址和 halt，TB 输出 signature 行，Python
  runner 逐字节比较。任何 byte difference 都是 FAIL。

接口关系：

* 被调用：device 宏、standalone TB、runner 比较函数。
* 调用：无执行调用。
* 共享状态：mailbox 地址 `0xD0580004`、`0xD0580008`、`0xD0580000`。

§11.3  sign-off 后果
~~~~~~~~~~~~~~~~~~~~

职责：说明 compliance stage 在 sign-off 中的自动化地位，以及逐字节 diff 的后果。

关键代码（``docs/adr/0011-compliance-framework.md:L65-L80``）：

.. code-block:: text

   ## Consequences

   ### Positive

   - Automated gate in sign-off flow: `full` profile includes `compliance` stage.
   - Catches ISA regression immediately (wrong ALU result, mis-decoded instruction).
   - Byte-level diff means no silent signature corruption passes.
   - Device files are per-ISA, allowing ISA-specific startup/link differences.

   ### Negative / Trade-offs

   - Compliance testing requires the full simv build (~30-60s per test run).
   - Known-fail suites (rv32Zicsr, rv32Zifencei) still run signature comparison but
     may legitimately fail -- these are tracked for future closure.

逐段解释：

* 第 L67-L72 行：ADR 明确 `full` profile 包含 compliance stage，并强调 byte-level diff
  不会放过 signature corruption。
* 第 L76-L80 行：ADR 记录 compliance 需要完整 simv 构建；`rv32Zicsr` 和
  `rv32Zifencei` 仍运行 signature comparison，但可能存在已知失败。

接口关系：

* 被调用：`signoff.py` profile、known-fail 解释、release gate。
* 调用：无执行调用。
* 共享状态：`full` profile、known-fail suite。

§12  运行命令与调试路径
-----------------------

本节只列出当前 Makefile 和 runner 实际支持的命令，不包含旧文档中无法在当前源码树证明的
`make run TEST=riscv_compliance_* GOAL=compliance` 形式。

§12.1  常用命令
~~~~~~~~~~~~~~~

职责：给出与源码入口一致的 compliance 命令。

关键代码（``dv/uvm/riscv_compliance/Makefile:L7-L15``）：

.. code-block:: makefile

   # Usage:
   #   make compliance RISCV_ISA=rv32i          # Run all RV32I tests
   #   make compliance RISCV_ISA=rv32im         # Run all RV32IM tests
   #   make compliance RISCV_ISA=rv32imc        # Run all RV32IMC tests
   #   make compliance RISCV_ISA=rv32Zicsr      # Run all Zicsr tests
   #   make compliance RISCV_ISA=rv32Zifencei   # Run all Zifencei tests
   #   make compliance-all                      # Run all supported suites
   #   make compile-compliance-tb               # Compile the stand-alone compliance TB
   #   make clean                               # Clean work directory

逐段解释：

* 第 L7-L13 行：子 Makefile 注释列出按 ISA 运行的 `make compliance RISCV_ISA=<isa>`
  形式，以及 `make compliance-all`。
* 第 L14-L15 行：同一区块还列出 standalone TB 编译和 clean。

接口关系：

* 被调用：用户命令、CI 脚本、sign-off 脚本。
* 调用：Makefile 目标和 runner CLI。
* 共享状态：`RISCV_ISA`、`WORK_DIR`、`SIMV`。

§12.2  单测试、列测试和 dry-run
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 runner 支持的直接 CLI 入口。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L13-L17``）：

.. code-block:: python

   Usage:
       python3 run_compliance.py --isa rv32i
       python3 run_compliance.py --isa rv32imc --debug
       python3 run_compliance.py --isa rv32i --test I-ADD-01
   """

逐段解释：

* 第 L13-L17 行：脚本文档字符串列出按 ISA 运行和单 test 运行示例。这里出现的
  `--debug` 没有在当前 argparse 参数中定义；实际 verbose 参数是 `--verbose`。

关键代码（``dv/uvm/riscv_compliance/scripts/run_compliance.py:L579-L592``）：

.. code-block:: python

   parser.add_argument("--isa", required=True,
                       help="RISC-V ISA to test (e.g. rv32i, rv32imc, or 'all')")
   parser.add_argument("--test", default=None,
                       help="Run a single test (e.g. I-ADD-01)")
   parser.add_argument("--simv", default=None,
                       help="Path to compiled simulator (default: build/simv)")
   parser.add_argument("--output", default=None,
                       help="Output directory for build artifacts")
   parser.add_argument("--verbose", action="store_true",
                       help="Verbose output")
   parser.add_argument("--dry-run", action="store_true",
                       help="Compile only, no simulation")
   parser.add_argument("--list-tests", action="store_true",

逐段解释：

* 第 L579-L586 行：实际 CLI 支持 `--isa`、`--test`、`--simv` 和 `--output`。
* 第 L587-L592 行：实际调试输出参数是 `--verbose`；`--dry-run` 只编译；`--list-tests`
  列出测试名后退出。

接口关系：

* 被调用：用户直接调用 Python runner。
* 调用：`main()`、`run_compliance()`。
* 共享状态：CLI 参数决定输出目录和运行范围。

§13  参考资料
-------------

关联章节：

* :ref:`signoff_flow` — `full` profile 中的 compliance stage 与 release gate。
* :ref:`scripts_reference` — 脚本入口、CLI 互调和参数语义。
* :ref:`adr-0011` — RISC-V compliance framework 决策记录。

关联 ADR：

* :ref:`adr-0011` — 使用 `riscv-compliance` 作为 primary framework，定义 mailbox
  signature 和 byte-by-byte comparison。

源文件绝对路径：

* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/scripts/run_compliance.py`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/scripts/collect_compliance.py`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/known_fail.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/device/rv32i/compliance_test.h`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/device/rv32i/compliance_io.h`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/device/rv32i/startup.S`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/device/rv32i/link.ld`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv`
* :file:`/home/host/eh2-veri/dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* :file:`/home/host/eh2-veri/docs/adr/0011-compliance-framework.md`
* 2026-05-19 01:02 VCS 主线 sign-off 摘要

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：不用启动仿真，先确认本页命令入口和默认 simulator 与 Makefile 一致。

.. code-block:: bash

   make help | sed -n "1,120p"
   rg -n "SIMULATOR \?= vcs|signoff:|regress:|VCS_COV_METRICS|NC_COV_CCF" Makefile

**进阶题**：检查流程章节中的 sign-off 数字是否仍与 2026-05-19 VCS demo 对齐。

.. code-block:: bash

   rg -n "95.05|31635/31635|102/104|line\+tgl\+assert\+fsm\+branch" docs/sphinx_cn/source/06_flows docs/sphinx_cn/source/07_decisions

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页介绍的 Makefile target 或 Python 脚本入口是什么，默认 simulator 是否仍是 VCS？
2. 该流程产生哪些 build 目录、log、JSON、coverage database 或 HTML artifact？
3. VCS/URG 路径和 NC/IMC 备选路径在本页中是否被分开解释？
4. 失败时第一份应打开的日志是哪一个，第二步应检查哪个变量或 YAML 配置？
5. 本页中的 sign-off 数字是否仍为 9/9 PASS、102/104、LEC 31635/31635 和 LINE 95.05%？

§14  v2-17 源码片段闭环：多 ISA device 与 runner
--------------------------------------------------

本节补齐 compliance framework 中此前只有逐段解释、没有 ``literalinclude`` 的资产。
EH2 的 device 目录按 ISA 拆分，``rv32i``、``rv32im``、``rv32imc``、
``rv32Zicsr`` 和 ``rv32Zifencei`` 共用相同的 mailbox/signature 设计；``rv32imac``
是压缩/原子组合的精简 device 变体。下面的片段用于审计闭环，不改变当前实测
``85/88 (96.59%)`` compliance sign-off 结果。

§14.1  ``rv32i`` device 基线
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32i/compliance_test.h
   :language: c
   :lines: 1-52
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32i/compliance_test.h:L1-L52

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32i/compliance_io.h
   :language: c
   :lines: 1-25
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32i/compliance_io.h:L1-L25

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32i/startup.S
   :language: text
   :lines: 1-111
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32i/startup.S:L1-L111

逐段精读：``compliance_test.h`` 定义 test entry、signature begin/end 和 PASS/FAIL
宏；``compliance_io.h`` 保持 IO 宏为空，说明结果通过 signature/mailbox 传递；
``startup.S`` 完成 reset entry、stack/global pointer、signature 清零和最终退出。

§14.2  ``rv32im`` 与 ``rv32imc`` device
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32im/compliance_test.h
   :language: c
   :lines: 1-52
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32im/compliance_test.h:L1-L52

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32im/compliance_io.h
   :language: c
   :lines: 1-25
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32im/compliance_io.h:L1-L25

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32im/startup.S
   :language: text
   :lines: 1-111
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32im/startup.S:L1-L111

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32imc/compliance_test.h
   :language: c
   :lines: 1-52
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32imc/compliance_test.h:L1-L52

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32imc/compliance_io.h
   :language: c
   :lines: 1-25
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32imc/compliance_io.h:L1-L25

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32imc/startup.S
   :language: text
   :lines: 1-111
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32imc/startup.S:L1-L111

逐段精读：``rv32im`` 和 ``rv32imc`` 复用 rv32i device 结构，但 suite 选择不同；
前者覆盖 M 扩展，后者覆盖 M+C 扩展。runner 通过 ``--isa`` 参数选择目录，不在
SystemVerilog TB 中硬编码 ISA。

§14.3  ``rv32Zicsr``、``rv32Zifencei`` 和 ``rv32imac`` device
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32Zicsr/compliance_test.h
   :language: c
   :lines: 1-52
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32Zicsr/compliance_test.h:L1-L52

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32Zicsr/compliance_io.h
   :language: c
   :lines: 1-25
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32Zicsr/compliance_io.h:L1-L25

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32Zicsr/startup.S
   :language: text
   :lines: 1-111
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32Zicsr/startup.S:L1-L111

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32Zifencei/compliance_test.h
   :language: c
   :lines: 1-52
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32Zifencei/compliance_test.h:L1-L52

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32Zifencei/compliance_io.h
   :language: c
   :lines: 1-25
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32Zifencei/compliance_io.h:L1-L25

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32Zifencei/startup.S
   :language: text
   :lines: 1-111
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32Zifencei/startup.S:L1-L111

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32imac/compliance_io.h
   :language: c
   :lines: 1-21
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32imac/compliance_io.h:L1-L21

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/device/rv32imac/startup.S
   :language: text
   :lines: 1-48
   :linenos:
   :caption: dv/uvm/riscv_compliance/device/rv32imac/startup.S:L1-L48

逐段精读：Zicsr/Zifencei 目录复用标准 signature 结构，分别承接 CSR 与 FENCE.I
suite；``rv32imac`` 目录较短，说明它只保留该组合测试需要的最小启动和 IO 边界。

§14.4  runner、collector、known fail 与 standalone TB
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/scripts/run_compliance.py
   :language: python
   :lines: 1-160
   :linenos:
   :caption: dv/uvm/riscv_compliance/scripts/run_compliance.py:L1-L160

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/scripts/collect_compliance.py
   :language: python
   :lines: 1-205
   :linenos:
   :caption: dv/uvm/riscv_compliance/scripts/collect_compliance.py:L1-L205

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/known_fail.yaml
   :language: yaml
   :lines: 1-32
   :linenos:
   :caption: dv/uvm/riscv_compliance/known_fail.yaml:L1-L32

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv
   :language: systemverilog
   :lines: 1-180
   :linenos:
   :caption: dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:L1-L180

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc
   :language: c++
   :lines: 1-89
   :linenos:
   :caption: dv/uvm/riscv_compliance/tb/eh2_compliance_tb.cc:L1-L89

逐段精读：``run_compliance.py`` 前 160 行定义路径、命令执行、ELF/HEX/signature
构建基础；``collect_compliance.py`` 全文件重扫 work 目录并汇总 JSON；
``known_fail.yaml`` 记录允许跟踪的失败；standalone SV/C++ TB 负责时钟、reset、
存储器加载和 Verilator 驱动。它们共同支撑 sign-off compliance stage。

§15  v2-18 compliance runner 与 TB 全文段落级精读
-------------------------------------------------

v2-17 已补 device、collector 和 TB 的入口片段；v2-18 对两个长文件做全文覆盖：
Python runner 决定 compile/run/compare/report，SystemVerilog TB 决定 standalone
仿真环境、memory map 和 signature 观测。二者共同决定 compliance stage 的真实行为。

§15.1  ``scripts/run_compliance.py`` 全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/scripts/run_compliance.py
   :language: python
   :linenos:
   :caption: dv/uvm/riscv_compliance/scripts/run_compliance.py:全文

逐段精读：

* L1-L55：脚本说明、路径常量和 ISA/test suite 默认目录。它把 EH2 local device 与
  external compliance framework 分开建模。
* L56-L158：toolchain 查找与 ``compile_test``。该段负责 GCC/objcopy/objdump、
  linker script、device include 和 ELF/HEX/signature 输入文件生成。
* L159-L307：``run_simulation`` 和 simulation log/signature 收集。它调用 standalone
  simulator，等待 signature 输出，并把 stdout/stderr 写入 work 目录。
* L308-L378：reference signature 加载和 byte-by-byte compare。比较结果保留 mismatch
  index、expected/actual 和 pass/fail 状态。
* L379-L583：suite 级 ``run_compliance``。它解析 ISA、device、test list、输出目录和
  known-fail 状态，逐 test 编译、运行、比较并汇总。
* L584-L623：``_write_report_json`` 写结构化报告，供 sign-off stage 和 HTML/report
  工具读取。
* L624-L736：CLI 参数、``--isa all``、``--list-tests``、``--dry-run`` 和 ``main``。
  该入口允许单 suite 调试，也允许 sign-off 调用全量套件。

§15.2  ``tb/eh2_compliance_tb.sv`` 全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/riscv_compliance/tb/eh2_compliance_tb.sv:全文

逐段精读：

* L1-L58：模块头、参数、clock/reset、memory array、DUT 连接和 plusarg 变量。TB 是
  standalone compliance 环境，不依赖 full UVM env。
* L59-L132：clock/reset 生成、timeout、hex 加载和初始状态。这里决定 ELF/HEX 如何进入
  TB memory，以及仿真何时被判定 hang。
* L134-L217：AXI/ICCM/DCCM/debug/DMI/DMA/PIC 等 DUT 端口绑定与默认 tie-off。该段
  定义 compliance TB 的 SoC 边界。
* L193-L384：memory byte/word 访问 helper、AXI read/write response、signature 区域
  采样和 mailbox 观察。它是 compliance pass/fail 与 signature 输出的核心。
* L385-L468：DUT instruction/data memory transaction 处理和 error/default response。
  当前 compliance 关注 architectural signature，不建模复杂外设 side effect。
* L469-L590：signature dump、finish 条件、pass/fail 打印和 debug trace。runner 从这些
  artifact 读取比较输入。
* L593-L613：收尾逻辑与 ``endmodule``。任何新增端口或 memory map 改动，都必须同步
  runner、device linker script 和本 TB。

§16  v2-48 ``dv/uvm/riscv_compliance/Makefile`` 全文行段级精读
---------------------------------------------------------------

本节补齐 RISC-V compliance 子目录 Makefile 的全文源码。它是 make 层控制面：上游顶层
``Makefile`` 只负责委托，真正的单 ISA 运行、全 suite 批量、dry-run/list-tests、standalone
TB 编译和 legacy 单测 hex 构建都在这里转发到 Python runner 或 VCS/GCC 命令。

.. literalinclude:: ../../../../dv/uvm/riscv_compliance/Makefile
   :language: make
   :linenos:
   :caption: dv/uvm/riscv_compliance/Makefile:全文

逐段精读：

* L1-L20：文件头说明该 Makefile 编译 riscv-compliance tests、通过 ``simv`` 运行、捕获
  signature，并与 reference output 做 byte-by-byte 比较。usage 列出单 ISA、全 suite、
  standalone TB 编译和 clean 入口；prerequisites 明确需要 RISC-V GCC、``build/simv`` 和外部
  riscv-compliance framework。
* L22-L31：``SHELL`` 固定为 bash；``EH2_ROOT`` 默认从当前目录向上三级得到仓库根；
  ``COMPLIANCE_FW`` 默认是 ``/home/host/riscv-compliance``；``WORK_DIR`` 默认在子目录
  ``work`` 下；工具链前缀和默认 ISA 分别是 ``riscv32-unknown-elf-`` 与 ``rv32i``。
* L33-L44：``SUPPORTED_ISAS`` 白名单包括 ``rv32i``、``rv32im``、``rv32imc``、``rv32Zicsr`` 和
  ``rv32Zifencei``；``KNOWN_FAIL_ISAS`` 记录当前已知失败 suite。``SIMV`` 默认指向
  ``$(EH2_ROOT)/build/simv``，``RUNNER`` 指向本目录的 ``scripts/run_compliance.py``。
* L46-L50：``.PHONY`` 声明当前 Makefile 的主要入口。它包含 ``compile-compliance-tb`` 和
  ``list-tests``，避免同名文件影响目标执行。
* L52-L63：``compliance`` target 首先检查 ``$(SIMV)`` 是否存在；缺失时提示用户在仓库根执行
  ``make compile`` 并退出。检查通过后调用 Python runner，传入 ``--isa``、``--simv`` 和
  ``--output $(WORK_DIR)/$(RISCV_ISA)``，并按 ``VERBOSE`` 可选追加 ``--verbose``。
* L64-L78：``compliance-all`` 遍历 ``SUPPORTED_ISAS``，逐个递归调用 ``$(MAKE) compliance
  RISCV_ISA=$$isa``。任一 suite 失败会把 shell 局部变量 ``failed`` 置 1，最后只打印 known-fail
  提示，没有在这段逻辑里显式 ``exit 1``。
* L79-L85：``compliance-compile`` 调 runner 的 ``--dry-run``，用于只编译/枚举不运行仿真；
  ``list-tests`` 调 ``--list-tests``，用于查看当前 ISA 下 runner 能发现的测试。
* L87-L100：standalone compliance TB 相关变量。``COMPLIANCE_TB_TOP`` 是
  ``eh2_compliance_tb``，输出 ``COMPLIANCE_SIMV`` 是 ``build/simv_compliance``；RTL/shared
  filelist 复用 core UVM 目录下的 ``eh2_rtl.f`` 和 ``eh2_shared.f``。
* L102-L120：``compile-compliance-tb`` 用 VCS 编译无 UVM 依赖的 standalone TB。命令启用
  ``-full64``、``-assert svaext``、SystemVerilog、``GTLSIM`` 和 ``RV_BUILD_AXI4``，包含
  snapshot defines、TB/common include、RTL/shared filelist 和 ``eh2_compliance_tb.sv``，输出
  ``build/simv_compliance`` 与 compile log。
* L122-L133：``test-%.hex`` 是旧式手工入口：用 RISC-V GCC 按当前 ``RISCV_ISA``、device linker
  script、device include 和 external riscv-test-env include 编译单个 upstream ``$*.S``，再用
  ``objcopy -O verilog`` 生成 hex。它适合手工 bring-up，不是 sign-off runner 的主路径。
* L135-L140：``clean`` 删除 ``WORK_DIR`` 并打印清理路径。它只清 compliance work 目录，不删除
  ``build/simv``、``build/simv_compliance``、外部 framework 或 device 源文件。

接口关系：

* 被调用：仓库根 ``make compliance``、``make compliance-all``、``make compliance-compile`` 或
  用户在 ``dv/uvm/riscv_compliance`` 下直接运行同名目标。
* 调用：``scripts/run_compliance.py``、递归 ``make``、VCS、RISC-V GCC、``objcopy``、``mkdir``、
  ``rm``。
* 共享状态：读取 external ``/home/host/riscv-compliance``、EH2 ``build/simv``、device/linker/TB
  源码和 filelist；写 ``dv/uvm/riscv_compliance/work/<isa>``、
  ``build/simv_compliance`` 和 ``build/compliance_tb_compile.log``。
