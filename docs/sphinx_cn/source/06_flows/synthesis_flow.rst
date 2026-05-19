.. _synthesis_flow:
.. _06_flows/synthesis_flow:

综合流程 — 详细参考
================================================================================

:status: draft
:source: syn/Makefile; syn/yosys/eh2_synth.tcl; syn/scripts/dc_synth.tcl; syn/scripts/dc_synth_block.tcl; syn/scripts/dc_synth_keep2d.tcl; syn/scripts/dc_elab_fixed.tcl; syn/scripts/dc_elaborate_flat.tcl
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  流程边界
--------------------------------------------------------------------------------

EH2 当前综合流程有两条入口，但 sign-off 语义不同：

.. code-block:: text

   syn/Makefile
      |
      |-- syn-dc
      |     `-- dc_shell -f syn/scripts/dc_synth.tcl
      |
      |-- syn-yosys
      |     `-- yosys < syn/yosys/eh2_synth.tcl
      |           `-- explicit error sentinel; see ADR-0013
      |
      |-- block_lec
      |     |-- dc_shell -f syn/scripts/dc_synth_block.tcl
      |     |-- fm_shell -f syn/scripts/lec_blocklevel/lec_<label>.tcl
      |     `-- python3 syn/scripts/lec_summary.py
      |
      `-- syn-full
            |-- syn-yosys
            `-- lec

**逐段解释** ：

* ``syn-dc`` 是当前商业综合入口。它只在 ``dc_shell`` 可用时执行，并加载
  :file:`syn/scripts/dc_synth.tcl`。
* ``syn-yosys`` 仍存在于 Makefile 中，但 :file:`syn/yosys/eh2_synth.tcl` 当前
  明确打印 Yosys 0.55 无法综合 EH2 的错误并 ``exit 1``。该路径是失败哨兵，
  不能写成成功的开源综合命令。
* ``block_lec`` 同时包含 per-block DC 综合和 Formality LEC。它属于综合与 LEC
  的交界流程，详细等价检查见 :ref:`lec_flow`。
* ``syn-full`` 依赖 ``syn-yosys`` 和 ``lec``，由于 Yosys sentinel 当前会失败，
  不能作为当前可用闭环来描述。

**接口关系** ：

* **被调用** ：顶层 Makefile 或开发者命令行调用 ``make -C syn <target>``。
* **调用** ：``syn-dc`` 调用 Design Compiler；``syn-yosys`` 调用 Yosys；
  ``block_lec`` 调用 Design Compiler、Formality 和 ``lec_summary.py``。
* **共享状态** ：输出目录为 :file:`syn/build/`，包括 netlist、report、log 和
  block-level LEC 子目录。

§2  Makefile 变量与 target 图
--------------------------------------------------------------------------------

§2.1  变量、输出文件和 block-level LEC 列表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`syn/Makefile` 定义 repo 路径、build 路径、Yosys binary、输出
文件名，以及 R3-C block-level LEC 涉及的 top 和 label。

**关键代码** （``syn/Makefile:L19-L35``）：

.. code-block:: text

   SHELL      := /bin/bash
   SYN_DIR    := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
   EH2_ROOT   := $(realpath $(SYN_DIR)/..)
   BUILD_DIR  := $(SYN_DIR)/build
   YOSYS_BIN  := $(SYN_DIR)/bin/yosys
   
   YOSYS      ?= $(YOSYS_BIN)
   
   # Output files
   NETLIST    := $(BUILD_DIR)/eh2_synth.v
   AREA_RPT   := $(BUILD_DIR)/area_report.txt
   TIMING_RPT := $(BUILD_DIR)/timing_report.txt
   SYN_LOG    := $(BUILD_DIR)/syn_yosys.log
   LEC_LOG    := $(BUILD_DIR)/lec.log
   
   .PHONY: syn-yosys syn-dc lec syn-full block_lec clean check-yosys check-prep

**逐段解释** ：

* 第 19-L24 行：Makefile 使用 Bash，计算 ``SYN_DIR``、``EH2_ROOT``、``BUILD_DIR``
  和内置 Yosys wrapper 路径。
* 第 25 行：``YOSYS`` 可由命令行覆盖，默认使用 ``syn/bin/yosys``。
* 第 28-L32 行：netlist、area report、timing report、Yosys log 和 LEC log 路径
  都放在 ``syn/build`` 下。
* 第 34 行：声明综合、LEC、clean 和 pre-flight 相关 phony target。

**关键代码** （``syn/Makefile:L36-L52``）：

.. code-block:: makefile

   BLOCK_LEC_TOPS := \
   	eh2_dec \
   	eh2_exu_alu_ctl \
   	eh2_exu_mul_ctl \
   	eh2_exu_div_ctl \
   	eh2_lsu \
   	eh2_pic_ctrl \
   	eh2_dma_ctrl \
   	eh2_dbg \
   	eh2_ifu
   
   BLOCK_LEC_LABELS := dec exu_alu exu_mul exu_div lsu pic dma dbg ifu
   BLOCK_LEC_RPT_DIR := $(BUILD_DIR)/lec_blocklevel
   BLOCK_LEC_DC_RUN_DIR := $(BLOCK_LEC_RPT_DIR)/run/dc
   BLOCK_LEC_FM_RUN_DIR := $(BLOCK_LEC_RPT_DIR)/run/fm
   BLOCK_LEC_RESYNTH ?= 0

**逐段解释** ：

* 第 36-L45 行：block-level LEC 的 DC 综合 top 包括 DEC、EXU ALU/MUL/DIV、LSU、
  PIC、DMA、DBG 和 IFU。
* 第 47 行：label 列表与 top 列表一一对应，Formality Tcl 使用 label 名称拼接
  ``lec_<label>.tcl``。
* 第 48-L50 行：block-level report、DC run 和 Formality run 目录都在
  ``syn/build/lec_blocklevel`` 下。
* 第 51 行：``BLOCK_LEC_RESYNTH`` 默认 0；已有 block netlist 时可以复用。

**接口关系** ：

* **被调用** ：所有 syn target 读取这些变量。
* **调用** ：无直接命令调用。
* **共享状态** ：变量决定后续 netlist、report、log 的路径。

§2.2  pre-flight target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``check-yosys`` 检查 Yosys 是否存在；``check-prep`` 创建 build 目录并
检查 Yosys wrapper 和 ``beh_lib_syn.sv``。

**关键代码** （``syn/Makefile:L53-L67``）：

.. code-block:: makefile

   # ─── Pre-flight check ─────────────────────────────────────────────────────
   check-yosys:
   	@if [ ! -x "$(YOSYS)" ] && ! command -v yosys >/dev/null 2>&1; then \
   		echo "ERROR: yosys not found."; \
   		echo "  Install: pip3 install --user yowasp-yosys"; \
   		echo "  Then run: make syn-yosys YOSYS=$(YOSYS_BIN)"; \
   		exit 1; \
   	fi
   	@echo "  yosys: $(YOSYS)"
   
   check-prep:
   	@mkdir -p $(BUILD_DIR)
   	@test -x $(YOSYS_BIN) || { echo "ERROR: $(YOSYS_BIN) not found"; exit 1; }
   	@test -f $(SYN_DIR)/beh_lib_syn.sv || { echo "ERROR: beh_lib_syn.sv not found"; exit 1; }

**逐段解释** ：

* 第 54-L60 行：``check-yosys`` 先看 ``$(YOSYS)`` 是否可执行，再看系统 PATH 中是否
  有 ``yosys``。两者都不存在时打印安装提示并退出 1。
* 第 61 行：检查通过时打印当前 ``YOSYS`` 路径。
* 第 63-L67 行：``check-prep`` 创建 ``BUILD_DIR``，并要求 ``syn/bin/yosys`` 可执行、
  ``syn/beh_lib_syn.sv`` 存在。

**接口关系** ：

* **被调用** ：``syn-yosys`` 和 ``lec`` 依赖 ``check-prep``。
* **调用** ：shell ``test``、``command -v``、``mkdir``。
* **共享状态** ：只创建 ``syn/build``，不生成 netlist。

§3  Yosys path
--------------------------------------------------------------------------------

§3.1  ``syn-yosys`` target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``syn-yosys`` 执行 Yosys stdin 脚本并打印输出摘要。当前脚本会因
SystemVerilog 支持限制主动退出 1，因此该 target 的主要作用是保留 open-source
path 的可诊断失败。

**关键代码** （``syn/Makefile:L68-L85``）：

.. code-block:: makefile

   # ─── Yosys synthesis ──────────────────────────────────────────────────────
   syn-yosys: check-prep
   	@echo "=== Yosys Synthesis ==="
   	@echo "  RTL real path   : /home/host/Cores-VeeR-EH2"
   	@echo "  Build dir       : $(BUILD_DIR)"
   	@echo "  Running yosys (stdin script)..."
   	@cd $(EH2_ROOT) && $(YOSYS) -Q < $(SYN_DIR)/yosys/eh2_synth.tcl > $(SYN_LOG) 2>&1; \
   		RC=$$?; \
   		echo "  yosys exit code: $$RC"; \
   		sed -n '/ERROR/p;/Successfully/p;/End of script/p' $(SYN_LOG) | tail -30

**逐段解释** ：

* 第 69 行：``syn-yosys`` 依赖 ``check-prep``，因此先验证 Yosys wrapper 和
  ``beh_lib_syn.sv``。
* 第 70-L73 行：target 打印流程标题、RTL 实际路径、build dir 和 stdin script
  执行提示。
* 第 74-L77 行：在 repo 根目录执行 ``$(YOSYS) -Q``，stdin 来自
  ``syn/yosys/eh2_synth.tcl``，stdout/stderr 写入 ``syn/build/syn_yosys.log``。
  退出码被记录到 ``RC`` 并打印；随后从 log 中筛选 ERROR、Successfully 和 End of
  script 行。

**关键代码** （``syn/Makefile:L78-L85``）：

.. code-block:: text

   	@echo ""
   	@echo "=== Output summary ==="
   	@test -f $(NETLIST)    && echo "  OK  $(NETLIST)    ($(shell wc -l < $(NETLIST) 2>/dev/null || echo 0) lines)" || echo "  --  $(NETLIST)    (not produced — see ADR-0013)"
   	@test -f $(AREA_RPT)   && echo "  OK  $(AREA_RPT)   ($(shell wc -l < $(AREA_RPT) 2>/dev/null || echo 0) lines)" || echo "  --  $(AREA_RPT)   (not produced)"
   	@test -f $(TIMING_RPT) && echo "  OK  $(TIMING_RPT) ($(shell wc -l < $(TIMING_RPT) 2>/dev/null || echo 0) lines)" || echo "  --  $(TIMING_RPT) (not produced)"
   	@echo "  LOG: $(SYN_LOG)"
   	@echo "=== syn-yosys done ==="

**逐段解释** ：

* 第 79-L82 行：target 检查 netlist、area report、timing report 是否存在；netlist
  不存在时提示 ``not produced — see ADR-0013``。
* 第 83-L84 行：最后打印 Yosys log 路径和完成标记。注意完成标记只是 target
  打印行为，不代表 Yosys 成功综合 EH2。

**接口关系** ：

* **被调用** ：``make -C syn syn-yosys`` 或顶层转发 target。
* **调用** ：``syn/yosys/eh2_synth.tcl``。
* **共享状态** ：写 ``syn/build/syn_yosys.log``，在未来工具链支持时可能写
  ``eh2_synth.v``、``area_report.txt``、``timing_report.txt``。

§3.2  ``eh2_synth.tcl`` — Yosys error sentinel
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 Tcl 文件当前不执行综合步骤；它明确说明 Yosys 0.55 的 SV-2017
解析限制，并以错误退出。

**关键代码** （``syn/yosys/eh2_synth.tcl:L1-L19``）：

.. code-block:: text

   # ─── EH2 Yosys Synthesis TCL ────────────────────────────────────────────
   # STATUS: OPEN-SOURCE-INCOMPATIBLE (yosys 0.55 cannot parse SV-2017)
   # Target: eh2_veer (core wrapper, ~1500 lines SV, ~40 submodules)
   #
   # BLOCKER: yosys 0.55 cannot parse:
   #   1. 'import eh2_pkg::*;' in module headers (all design modules)
   #   2. '{...} struct literals in parameter defaults (eh2_param.vh)
   #   sv2v pre-built binaries require GLIBC 2.27+ (system has 2.17)
   #   See ADR-0013 for full analysis.
   #
   # INTENDED FLOW (when toolchain supports SV-2017):
   #   step 1: sv2v or DC elaboration to produce flat Verilog-2001
   #   step 2: yosys reads flat file
   #   step 3: yosys synth -top eh2_veer
   #
   # For now, use commercial flow: make syn-dc (Design Compiler)
   #
   # This script will exit with error if run as-is.
   # The old rvjtag_tap fake synthesis has been REMOVED.

**逐段解释** ：

* 第 2 行：状态标为 ``OPEN-SOURCE-INCOMPATIBLE``，原因是 Yosys 0.55 不能解析
  SV-2017。
* 第 5-L9 行：blocker 明确列出 ``import eh2_pkg::*;``、struct literal parameter
  defaults，以及 sv2v pre-built binary 对 GLIBC 2.27+ 的需求。
* 第 11-L14 行：注释中的 intended flow 是未来工具链支持时的三步：先生成 flat
  Verilog-2001，再由 Yosys 读取，最后 ``synth -top eh2_veer``。
* 第 16-L19 行：当前要求使用 ``make syn-dc``；旧 ``rvjtag_tap`` fake synthesis
  已移除。

**关键代码** （``syn/yosys/eh2_synth.tcl:L21-L24``）：

.. code-block:: tcl

   puts "ERROR: yosys 0.55 cannot synthesize EH2 (SV-2017 unsupported)."
   puts "See ADR-0013 and syn/README.md for details."
   puts "Use commercial tool: make syn-dc"
   exit 1

**逐段解释** ：

* 第 21-L23 行：脚本向 Yosys log 打印三行错误/指引文本。
* 第 24 行：脚本以 1 退出，确保调用者不会误把 open-source path 当成通过。

**接口关系** ：

* **被调用** ：``syn-yosys`` target 使用 stdin 执行该文件。
* **调用** ：只调用 Tcl ``puts`` 和 ``exit``。
* **共享状态** ：错误文本写入 ``syn/build/syn_yosys.log``。

§4  Design Compiler path
--------------------------------------------------------------------------------

§4.1  ``syn-dc`` target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``syn-dc`` 是商业综合入口。它检查 ``dc_shell``，创建 run 目录，然后
在该目录中执行 :file:`syn/scripts/dc_synth.tcl`。

**关键代码** （``syn/Makefile:L86-L97``）：

.. code-block:: text

   # ─── Design Compiler synthesis (commercial) ────────────────────────────────
   syn-dc:
   	@echo "=== Design Compiler Synthesis ==="
   	@if command -v dc_shell >/dev/null 2>&1; then \
   		echo "  Running dc_shell..."; \
   		mkdir -p $(BUILD_DIR)/dc_run; \
   		cd $(BUILD_DIR)/dc_run && dc_shell -f $(SYN_DIR)/scripts/dc_synth.tcl; \
   	else \
   		echo "ERROR: dc_shell not found. Install Synopsys Design Compiler."; \
   		echo "  The SDC constraints file is at $(SYN_DIR)/nangate/eh2_nangate.sdc"; \
   		exit 1; \
   	fi

**逐段解释** ：

* 第 87-L92 行：当 ``dc_shell`` 存在时，target 创建 ``syn/build/dc_run``，切换到
  该目录并执行 ``dc_shell -f syn/scripts/dc_synth.tcl``。
* 第 93-L96 行：当 ``dc_shell`` 不存在时，target 打印错误、提示 SDC 文件路径
  ``syn/nangate/eh2_nangate.sdc``，并退出 1。

**接口关系** ：

* **被调用** ：``make -C syn syn-dc`` 或顶层转发 target。
* **调用** ：``dc_shell`` 和 ``syn/scripts/dc_synth.tcl``。
* **共享状态** ：写 ``syn/build/dc_run`` 以及 ``dc_synth.tcl`` 指定的报告/netlist。

§4.2  ``dc_synth.tcl`` — top-level ``eh2_veer`` 综合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该脚本使用 Synopsys ``class.db`` 作为 target library，读入
``eh2_dc_wrapper.sv``，elaborate ``eh2_veer``，执行 ``compile_ultra``，输出
top-level netlist 和 area/timing/QoR report。

**关键代码** （``syn/scripts/dc_synth.tcl:L5-L14``）：

.. code-block:: text

   set TARGET_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
   set GTECH_DB  /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
   set_app_var target_library $TARGET_DB
   set_app_var link_library [list * $GTECH_DB $TARGET_DB]
   set_app_var hdlin_sverilog_std 2012
   set_app_var hdlin_keep_signal_name all_driving
   
   set BUILD_DIR /home/host/eh2-veri/syn/build
   file mkdir $BUILD_DIR

**逐段解释** ：

* 第 5-L8 行：脚本设置 target library 为 ``class.db``，link library 包含 ``*``、
  ``gtech.db`` 和 ``class.db``。
* 第 9-L10 行：SystemVerilog 标准设为 2012，信号名保留策略设为
  ``all_driving``。
* 第 12-L13 行：build 目录固定为 ``/home/host/eh2-veri/syn/build``，脚本确保目录
  存在。

**关键代码** （``syn/scripts/dc_synth.tcl:L15-L33``）：

.. code-block:: text

   # Redirect DC working files to a dedicated build subdir.
   set RUN_DIR $BUILD_DIR/dc_run
   file mkdir $RUN_DIR
   cd $RUN_DIR
   catch {set_app_var hdlin_temporary_dir $RUN_DIR}
   
   suppress_message {LINT-1 LINT-28 LINT-29 LINT-31 LINT-32 LINT-33 LINT-34}
   suppress_message {VER-130 VER-250 VER-318 VER-26 VER-1}
   suppress_message {UID-401}
   suppress_message {ELAB-902}
   
   set_app_var search_path [concat \
       $RUN_DIR \
       /home/host/eh2-veri/syn/include \

**逐段解释** ：

* 第 16-L19 行：脚本把 DC 工作目录切到 ``syn/build/dc_run``，并尝试设置
  ``hdlin_temporary_dir``。
* 第 21-L24 行：脚本 suppress 一组 LINT、VER、UID 和 ELAB 信息。
* 第 26-L33 行：search path 以 run dir、``syn/include``、EH2 snapshot/default、
  design include/lib 和原有 search path 拼接。

**关键代码** （``syn/scripts/dc_synth.tcl:L34-L57``）：

.. code-block:: tcl

   puts "DC: === EH2 Synthesis RC3 v8 (class.db target) ==="
   
   puts "DC: Analyzing wrapper..."
   analyze -format sverilog -work WORK $BUILD_DIR/eh2_dc_wrapper.sv
   puts "DC: analyze OK"
   
   puts "DC: Elaborating eh2_veer..."
   elaborate eh2_veer -work WORK
   puts "DC: elaborate OK — [current_design]"
   
   link
   puts "DC: link OK"
   uniquify
   
   check_design
   puts "DC: check_design OK"
   
   create_clock -name clk -period 2.0 [get_ports clk]
   set_max_fanout 32 [current_design]

**逐段解释** ：

* 第 34-L38 行：脚本打印流程标题，分析 ``syn/build/eh2_dc_wrapper.sv``，并打印
  analyze OK。
* 第 40-L46 行：elaborate top 为 ``eh2_veer``，随后执行 ``link`` 和 ``uniquify``。
* 第 48-L53 行：执行 ``check_design``，创建 2.0ns ``clk``，设置 max fanout 32 和
  max transition 0.5。
* 第 55-L57 行：脚本执行 ``compile_ultra -no_autoungroup -no_boundary_optimization``。

**关键代码** （``syn/scripts/dc_synth.tcl:L59-L69``）：

.. code-block:: tcl

   report_area -hierarchy > $BUILD_DIR/area_report.txt
   report_timing -max_paths 10 > $BUILD_DIR/timing_report.txt
   report_qor > $BUILD_DIR/qor_report.txt
   
   change_names -rules verilog -hierarchy
   write -format verilog -hierarchy -output $BUILD_DIR/eh2_synth.v
   # Note: write_svf not available in DC O-2018.06, use set_svf in Formality instead
   
   puts "DC: Netlist cells: [sizeof_collection [get_cells -hier *]]"
   puts "DC: === Synthesis Complete ==="
   exit 0

**逐段解释** ：

* 第 59-L61 行：报告输出为 ``area_report.txt``、``timing_report.txt`` 和
  ``qor_report.txt``。
* 第 63-L64 行：执行 Verilog 命名规则转换，并输出 ``syn/build/eh2_synth.v``。
* 第 65 行：注释说明 DC O-2018.06 不提供 ``write_svf``，Formality 侧使用
  ``set_svf``。
* 第 67-L69 行：打印 netlist cell 数、完成标记并以 0 退出。

**接口关系** ：

* **被调用** ：``syn-dc`` target。
* **调用** ：Design Compiler 命令 ``analyze``、``elaborate``、``link``、
  ``uniquify``、``check_design``、``compile_ultra``、``report_*``、``write``。
* **共享状态** ：读取 ``syn/build/eh2_dc_wrapper.sv``；写 ``syn/build`` 下的报告和
  ``eh2_synth.v``。

§5  block-level synthesis for LEC
--------------------------------------------------------------------------------

§5.1  ``block_lec`` 中的 DC 综合循环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``block_lec`` target 为每个 block 运行 DC block synthesis，然后运行
对应 Formality LEC。本文只说明综合部分；等价检查细节见 :ref:`lec_flow`。

**关键代码** （``syn/Makefile:L99-L127``）：

.. code-block:: makefile

   # ─── R3-C block-level Formality LEC ───────────────────────────────────────
   block_lec:
   	@echo "=== R3-C Block-level LEC ==="
   	@mkdir -p $(BLOCK_LEC_RPT_DIR) $(BLOCK_LEC_RPT_DIR)/synth \
   	  $(BLOCK_LEC_DC_RUN_DIR) $(BLOCK_LEC_FM_RUN_DIR)
   	@if ! command -v dc_shell >/dev/null 2>&1; then \
   		echo "ERROR: dc_shell not found."; \
   		exit 1; \
   	fi
   	@if ! command -v fm_shell >/dev/null 2>&1; then \
   		echo "ERROR: fm_shell not found."; \
   		exit 1; \
   	fi

**逐段解释** ：

* 第 100-L103 行：target 创建 block-level report、synth、DC run 和 Formality run
  目录。
* 第 104-L111 行：target 要求 ``dc_shell`` 和 ``fm_shell`` 都在 PATH 中，否则分别
  打印错误并退出 1。

**关键代码** （``syn/Makefile:L112-L137``）：

.. code-block:: text

   	@for top in $(BLOCK_LEC_TOPS); do \
   		if [ "$(BLOCK_LEC_RESYNTH)" = "1" ] || \
   		   [ ! -f "$(BLOCK_LEC_RPT_DIR)/synth/$${top}.v" ]; then \
   			echo "  DC synth: $${top}"; \
   			extra_env=""; \
   			if [ "$${top}" = "eh2_ifu" ]; then \
   				extra_env="R3C_SIMPLE_COMPILE=1"; \
   			fi; \
   			mkdir -p $(BLOCK_LEC_DC_RUN_DIR)/$${top}; \
   			(cd $(BLOCK_LEC_DC_RUN_DIR)/$${top} && \
   			  env R3C_BLOCK_TOP=$${top} $${extra_env} dc_shell -f $(SYN_DIR)/scripts/dc_synth_block.tcl \
   			    > $(BLOCK_LEC_RPT_DIR)/dc_$${top}.log 2>&1); \

**逐段解释** ：

* 第 112-L115 行：循环遍历 ``BLOCK_LEC_TOPS``；如果 ``BLOCK_LEC_RESYNTH=1`` 或
  block netlist 不存在，则执行 DC 综合。
* 第 116-L119 行：当 top 是 ``eh2_ifu`` 时，额外设置 ``R3C_SIMPLE_COMPILE=1``。
* 第 120-L123 行：每个 top 在自己的 DC run 目录下执行
  ``dc_shell -f syn/scripts/dc_synth_block.tcl``，并通过环境变量传入
  ``R3C_BLOCK_TOP``。

**接口关系** ：

* **被调用** ：``make -C syn block_lec``。
* **调用** ：``dc_shell``、``dc_synth_block.tcl``、后续 Formality 和 summary。
* **共享状态** ：写 ``syn/build/lec_blocklevel/synth``、
  ``syn/build/lec_blocklevel/run/dc`` 和 ``dc_<top>.log``。

§5.2  ``dc_synth_block.tcl`` — per-block DC script
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 Tcl 通过环境变量 ``R3C_BLOCK_TOP`` 选择 block top，设置
``class.db``/``gtech.db``，分析 wrapper，elaborate 指定 top，并输出 per-block
DDC、Verilog、SVF 和报告。

**关键代码** （``syn/scripts/dc_synth_block.tcl:L1-L30``）：

.. code-block:: tcl

   # DC block-level synthesis for R3-C LEC.
   # Set R3C_BLOCK_TOP to the RTL module name before invoking dc_shell.
   
   if {![info exists env(R3C_BLOCK_TOP)] || $env(R3C_BLOCK_TOP) eq ""} {
       puts "DC: ERROR: R3C_BLOCK_TOP is not set"
       exit 1
   }
   
   set TOP $env(R3C_BLOCK_TOP)
   set TARGET_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
   set GTECH_DB  /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
   set_app_var target_library $TARGET_DB
   set_app_var link_library [list * $GTECH_DB $TARGET_DB]
   set_app_var hdlin_sverilog_std 2012
   set_app_var hdlin_keep_signal_name all_ports

**逐段解释** ：

* 第 4-L7 行：脚本要求环境变量 ``R3C_BLOCK_TOP`` 非空，否则打印错误并退出 1。
* 第 9-L15 行：``TOP`` 来自环境变量；library 设置与 top-level DC 类似，但
  ``hdlin_keep_signal_name`` 是 ``all_ports``。
* 第 17-L29 行：脚本设置 ``BUILD_DIR``、``BLOCK_DIR``、run dir 和 per-block SVF
  路径，随后打开 ``set_svf``。

**关键代码** （``syn/scripts/dc_synth_block.tcl:L45-L72``）：

.. code-block:: tcl

   puts "DC: === R3-C block synthesis: $TOP ==="
   analyze -format sverilog -work WORK $BUILD_DIR/eh2_dc_wrapper.sv
   elaborate $TOP -work WORK
   link
   uniquify
   check_design
   
   if {[info exists env(R3C_VERIFY_PRIORITY)] && $env(R3C_VERIFY_PRIORITY) eq "1"} {
       puts "DC: Setting verification priority for LEC-oriented datapath preservation"
       set_verification_priority -all -high
   }
   
   set clk_ports [get_ports clk -quiet]
   if {[sizeof_collection $clk_ports] > 0} {
       create_clock -name clk -period 2.0 $clk_ports

**逐段解释** ：

* 第 45-L50 行：分析 ``eh2_dc_wrapper.sv``，elaborate 指定 ``TOP``，然后 link、
  uniquify 和 check design。
* 第 52-L55 行：如果 ``R3C_VERIFY_PRIORITY=1``，脚本设置
  ``set_verification_priority -all -high``。
* 第 57-L62 行：只有当当前 block 有 ``clk`` port 时才创建 2.0ns clock，否则打印
  no top-level clk port 信息并继续。

**关键代码** （``syn/scripts/dc_synth_block.tcl:L64-L87``）：

.. code-block:: tcl

   set_max_fanout 32 [current_design]
   set_max_transition 0.5 [current_design]
   
   if {[info exists env(R3C_SIMPLE_COMPILE)] && $env(R3C_SIMPLE_COMPILE) eq "1"} {
       puts "DC: Using simple compile for LEC-oriented block netlist"
       compile -map_effort medium
   } else {
       compile_ultra -no_autoungroup -no_boundary_optimization
   }
   
   report_area -hierarchy > $BLOCK_DIR/${TOP}_area.rpt
   report_timing -max_paths 10 > $BLOCK_DIR/${TOP}_timing.rpt
   report_qor > $BLOCK_DIR/${TOP}_qor.rpt

**逐段解释** ：

* 第 64-L65 行：每个 block 都设置 max fanout 32 和 max transition 0.5。
* 第 67-L72 行：``R3C_SIMPLE_COMPILE=1`` 时使用 ``compile -map_effort medium``；
  否则使用 ``compile_ultra -no_autoungroup -no_boundary_optimization``。
* 第 74-L76 行：输出 per-block area、timing 和 QoR report。

**关键代码** （``syn/scripts/dc_synth_block.tcl:L78-L87``）：

.. code-block:: tcl

   change_names -rules verilog -hierarchy
   write -format ddc -hierarchy -output $BLOCK_DIR/${TOP}.ddc
   write -format verilog -hierarchy -output $BLOCK_DIR/${TOP}.v
   set_svf -off
   
   puts "DC: Wrote $BLOCK_DIR/${TOP}.v"
   puts "DC: Wrote $BLOCK_DIR/${TOP}.ddc"
   puts "DC: Wrote $BLOCK_SVF"
   puts "DC: === R3-C block synthesis complete: $TOP ==="
   exit 0

**逐段解释** ：

* 第 78-L81 行：执行 Verilog 命名规则转换，输出 per-block DDC、Verilog netlist，
  并关闭 SVF。
* 第 83-L86 行：打印生成的 Verilog、DDC、SVF 路径和完成标记。
* 第 87 行：脚本以 0 退出。

**接口关系** ：

* **被调用** ：``block_lec`` target 的 DC synthesis loop。
* **调用** ：Design Compiler 命令和 ``set_svf``。
* **共享状态** ：读取 ``R3C_BLOCK_TOP``、``R3C_SIMPLE_COMPILE``、
  ``R3C_VERIFY_PRIORITY``；写 ``syn/build/lec_blocklevel/synth``。

§6  辅助 DC 实验脚本
--------------------------------------------------------------------------------

§6.1  ``dc_synth_keep2d.tcl`` — packed-array keep-2D 探针
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该脚本是 R3-C Step 0 keep-2D experiment，用于探测 Synopsys
O-2018.06-SP1 packed-array 处理选项。它不是默认 ``syn-dc`` 入口。

**关键代码** （``syn/scripts/dc_synth_keep2d.tcl:L1-L34``）：

.. code-block:: tcl

   # DC synthesis — R3-C Step 0 keep-2D experiment.
   # This is a non-invasive probe for Synopsys O-2018.06-SP1 packed-array handling.
   
   proc try_set_app_var {name value} {
       if {[catch {set_app_var $name $value} msg]} {
           puts "DC: keep2d option unsupported: $name = $value ($msg)"
           return 0
       }
       puts "DC: keep2d option set: $name = $value"
       return 1
   }

**逐段解释** ：

* 第 1-L2 行：注释说明该脚本是 keep-2D experiment，是 non-invasive probe。
* 第 4-L11 行：``try_set_app_var`` 用 ``catch`` 包住 ``set_app_var``，不支持时打印
  unsupported 并返回 0，支持时打印 set 并返回 1。
* 第 13-L20 行：``try_set_var`` 对普通 Tcl variable 使用同样的尝试/打印/返回模式。
* 第 29-L34 行：脚本尝试设置 ``verilogout_no_tri``、
  ``verilogout_show_unconnected_pins``、``hdlin_unresolved_modules``、
  ``change_names_dont_change_packed_arrays`` 和 ``hdlin_preserve_packed_arrays``。

**关键代码** （``syn/scripts/dc_synth_keep2d.tcl:L50-L77``）：

.. code-block:: tcl

   puts "DC: === R3-C keep2d synthesis probe ==="
   puts "DC: Analyzing wrapper..."
   analyze -format sverilog -work WORK $BUILD_DIR/eh2_dc_wrapper.sv
   
   puts "DC: Elaborating eh2_veer..."
   elaborate eh2_veer -work WORK
   link
   uniquify
   check_design
   
   create_clock -name clk -period 2.0 [get_ports clk]
   set_max_fanout 32 [current_design]

**逐段解释** ：

* 第 50-L58 行：keep2d probe 仍分析 wrapper、elaborate ``eh2_veer``、link、
  uniquify 和 check design。
* 第 60-L65 行：设置 clock、fanout、transition 后执行 ``compile_ultra``。
* 第 68-L73 行：报告写入 ``r3c_keep2d_*`` 文件，netlist 输出为
  ``eh2_synth_keep2d.v``。

**接口关系** ：

* **被调用** ：手工诊断 packed-array 行为时调用。
* **调用** ：Design Compiler 命令和本文件两个 ``try_*`` proc。
* **共享状态** ：写 ``syn/build/r3c_keep2d_*`` 和 ``eh2_synth_keep2d.v``。

§6.2  ``dc_elab_fixed.tcl`` 与 ``dc_elaborate_flat.tcl`` — flat Verilog 尝试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：这两个脚本是 DC elaboration / flat Verilog 尝试，用于为 Yosys/LEC
生成平坦 Verilog。当前默认综合入口不是这两个脚本。

**关键代码** （``syn/scripts/dc_elab_fixed.tcl:L1-L14``）：

.. code-block:: text

   # DC elaboration script v4 — fixed include path
   # Target: elaborate eh2_veer, dump flat Verilog for yosys synthesis + LEC
   
   set GTECH_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
   set_app_var target_library $GTECH_DB
   set_app_var link_library [list $GTECH_DB]
   set_app_var hdlin_sverilog_std 2012
   
   # Fix: set search_path so `include "eh2_param.vh"` resolves
   set_app_var search_path [list \
       /home/host/Cores-VeeR-EH2/snapshots/default \
       /home/host/Cores-VeeR-EH2/design/include \
       /home/host/Cores-VeeR-EH2/design/lib \

**逐段解释** ：

* 第 1-L2 行：脚本目标是 elaborate ``eh2_veer`` 并 dump flat Verilog。
* 第 4-L7 行：library 只设置 ``gtech.db``，HDL 标准为 SystemVerilog 2012。
* 第 9-L14 行：search path 修正 include resolution，尤其是 ``eh2_param.vh``。

**关键代码** （``syn/scripts/dc_elab_fixed.tcl:L30-L72``）：

.. code-block:: tcl

   # Read RTL file list
   set fp [open "/home/host/eh2-veri/syn/build/eh2_rtl_dc.lst" r]
   set rtl_files [list]
   while {[gets $fp line] >= 0} {
       set line [string trim $line]
       if {$line ne "" && [string index $line 0] ne "#"} {
           lappend rtl_files $line
       }
   }
   close $fp
   
   puts "DC: Analyzing [llength $rtl_files] RTL files..."

**逐段解释** ：

* 第 31-L39 行：脚本读取 ``syn/build/eh2_rtl_dc.lst``，跳过空行和 ``#`` 开头的行，
  将剩余路径加入 ``rtl_files``。
* 第 41-L54 行：循环 analyze 每个 RTL 文件，统计 analyzed 和 failed 数。
* 第 60-L69 行：elaborate ``eh2_veer``，成功后写
  ``syn/build/eh2_golden_flat.v``。

**关键代码** （``syn/scripts/dc_elaborate_flat.tcl:L21-L44``）：

.. code-block:: tcl

   puts "DC: Analyzing RTL files..."
   
   # Type defs (must be first)
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/snapshots/default/eh2_pdef.vh
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/include/eh2_def.sv
   
   # Library files
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/beh_lib.sv
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/eh2_lib.sv
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/mem_lib.sv
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/ahb_to_axi4.sv
   analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/axi4_to_ahb.sv

**逐段解释** ：

* 第 21-L25 行：该脚本显式逐个 analyze type definition 和 ``eh2_def.sv``。
* 第 27-L32 行：随后 analyze design/lib 中的行为库、EH2 lib、memory lib 和
  AHB/AXI bridge。
* 第 34-L89 行：脚本继续按 IFU、DEC、EXU、LSU、DBG、DMI 和 top-level 分组
  analyze RTL 文件。

**关键代码** （``syn/scripts/dc_elaborate_flat.tcl:L91-L104``）：

.. code-block:: tcl

   puts "DC: All files analyzed. Elaborating eh2_veer..."
   
   elaborate eh2_veer
   
   puts "DC: Current design: [current_design]"
   puts "DC: Elaboration complete. Writing flat Verilog..."
   
   write -format verilog -hierarchy -output /home/host/eh2-veri/syn/build/eh2_golden_flat.v
   
   puts "DC: Reporting area..."
   report_area > /home/host/eh2-veri/syn/build/dc_area_report.txt
   
   puts "DC: Done. Flat Verilog written to syn/build/eh2_golden_flat.v"
   exit

**逐段解释** ：

* 第 91-L98 行：所有文件 analyze 后 elaborate ``eh2_veer``，并输出
  ``eh2_golden_flat.v``。
* 第 100-L103 行：脚本输出 ``dc_area_report.txt`` 并打印完成信息。

**接口关系** ：

* **被调用** ：手工 flat Verilog 实验或旧 Yosys/LEC 准备路径。
* **调用** ：Design Compiler ``analyze``、``elaborate``、``write``、``report_area``。
* **共享状态** ：写 ``syn/build/eh2_golden_flat.v`` 和 ``dc_area_report.txt``。

§7  与 LEC 和 ADR 的关系
--------------------------------------------------------------------------------

§7.1  LEC 入口关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：综合产物供 LEC 使用，但综合流程本身不判定等价性。等价检查由
:ref:`lec_flow` 和 :ref:`appendix_c_tools/syn_lec` 说明。

**关键代码** （``syn/Makefile:L139-L161``）：

.. code-block:: makefile

   # ─── Logical Equivalence Check (yosys equiv) ───────────────────────────────
   lec: check-prep
   	@echo "=== Logical Equivalence Check (yosys equiv) ==="
   	@echo "  Golden  : RTL (SystemVerilog)"
   	@echo "  Revised : $(NETLIST)"
   	@echo "  Running equiv_induct..."
   	@cd $(EH2_ROOT) && $(YOSYS) -Q < $(SYN_DIR)/lec/eh2_lec.tcl > $(LEC_LOG) 2>&1; \
   		RC=$$?; \
   		echo "  yosys exit code: $$RC"; \
   		grep -E "ERROR|Successfully|equiv_status|mismatch|PASS|FAIL" $(LEC_LOG) | tail -10

**逐段解释** ：

* 第 140-L145 行：``lec`` target 是 Yosys equiv path，依赖 ``check-prep``，读取
  ``syn/lec/eh2_lec.tcl`` 并写 ``syn/build/lec.log``。
* 第 146-L149 行：target 打印 Yosys exit code，并从 LEC log 中筛选 ERROR、
  Successfully、equiv_status、mismatch、PASS、FAIL。

**关键代码** （``syn/Makefile:L152-L161``）：

.. code-block:: makefile

   # ─── Full flow: synthesis + LEC ───────────────────────────────────────────
   syn-full: syn-yosys lec
   	@echo ""
   	@echo "============================================================"
   	@echo "  EH2 Synthesis + LEC complete"
   	@echo "  Netlist  : $(NETLIST)"
   	@echo "  Reports  : $(AREA_RPT), $(TIMING_RPT)"
   	@echo "  Logs     : $(SYN_LOG), $(LEC_LOG)"
   	@echo "  Note: yosys 0.55 has SV import limitations (ADR-0013)"
   	@echo "============================================================"

**逐段解释** ：

* 第 153 行：``syn-full`` 依赖 ``syn-yosys`` 和 ``lec``。
* 第 155-L160 行：target 打印 netlist、reports、logs 和 ADR-0013 限制说明。
  由于 ``syn-yosys`` 当前是 error sentinel，不能把 ``syn-full`` 写成当前
  sign-off 成功路径。

**接口关系** ：

* **被调用** ：开发者手工调用 Yosys LEC 或 full flow。
* **调用** ：Yosys ``syn/lec/eh2_lec.tcl``。
* **共享状态** ：读取 ``NETLIST``，写 ``LEC_LOG``。

§7.2  ADR-0013 ground truth
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:ref:`adr-0013` 是综合工具链决策的 ground truth。本文引用它来说明
为什么默认综合路径转向 Design Compiler，以及为什么 Yosys path 是显式失败哨兵。

**关键代码** （``docs/sphinx_cn/source/appendix_d_adr/0013_synthesis_toolchain.rst:L9-L24``）：

.. code-block:: text

   EH2 需要 synthesis 和 LEC 能力作为签核需求。开源 yosys 0.55
   无法解析 SV-2017 特性（``import pkg::*``、struct literals）。
   sv2v 因 CentOS 7 glibc 2.17 不兼容无法安装。
   
   §2  决策
   ---------
   
   使用 Design Compiler O-2018.06-SP1。RC3 创建 wrapper 文件
   ``eh2_dc_wrapper.sv`` ，将全部 RTL 合并到单个编译单元。
   结果：0 errors, 379,305 total cells。

**逐段解释** ：

* ADR 文本明确把 Yosys 0.55 的 SV-2017 解析能力列为阻塞点。
* ADR 决策使用 Design Compiler O-2018.06-SP1，并记录 RC3 wrapper 单编译单元路径。
* 本文不把早期 Yosys ``rvjtag_tap`` 结果写成 EH2 core 综合结果；该旧路径已在
  ``eh2_synth.tcl`` 注释中标为移除。

**接口关系** ：

* **被调用** ：综合文档和工具章节引用 :ref:`adr-0013`。
* **调用** ：ADR 不调用脚本。
* **共享状态** ：综合流程中的 ``syn-dc``、``eh2_dc_wrapper.sv``、Yosys sentinel
  都与 ADR-0013 的决策一致。

§8  运行命令
--------------------------------------------------------------------------------

§8.1  当前商业综合入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当前应使用 ``syn-dc`` 运行 top-level Design Compiler 综合。

.. code-block:: bash

   make -C /home/host/eh2-veri/syn syn-dc

**逐段解释** ：

* 该命令要求 ``dc_shell`` 在 PATH 中。
* 成功路径加载 ``syn/scripts/dc_synth.tcl``。
* 输出由 Tcl 写到 ``/home/host/eh2-veri/syn/build``。
* 若 ``dc_shell`` 不存在，Makefile 会打印错误并退出 1。

**接口关系** ：

* **被调用** ：开发者、release flow 或顶层 Makefile 转发目标。
* **调用** ：``syn-dc`` target。
* **共享状态** ：写 ``syn/build``，不修改源 RTL。

§8.2  Yosys path 的预期失败命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Yosys path 保留为可诊断入口，但当前预期行为是打印 ADR-0013 相关错误。

.. code-block:: bash

   make -C /home/host/eh2-veri/syn syn-yosys

**逐段解释** ：

* 该命令先运行 ``check-prep``。
* 如果 pre-flight 通过，Yosys 执行 ``syn/yosys/eh2_synth.tcl``。
* 当前 ``eh2_synth.tcl`` 打印 ``yosys 0.55 cannot synthesize EH2`` 并
  ``exit 1``。
* 因此这个命令用于验证 open-source path 的已知限制，不用于声明综合通过。

**接口关系** ：

* **被调用** ：开发者确认 Yosys 限制或排查工具链时调用。
* **调用** ：``syn-yosys`` target。
* **共享状态** ：写 ``syn/build/syn_yosys.log``。

§9  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`lec_flow`、:ref:`appendix_c_tools/syn_yosys`、
  :ref:`appendix_c_tools/syn_nangate`、:ref:`appendix_c_tools/syn_lec`。
* 关联 ADR：:ref:`adr-0013`、:ref:`adr-0019`、:ref:`adr-0020`。
* 源文件绝对路径：``/home/host/eh2-veri/syn/Makefile``。
* 源文件绝对路径：``/home/host/eh2-veri/syn/yosys/eh2_synth.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/syn/scripts/dc_synth.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/syn/scripts/dc_synth_block.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/syn/scripts/dc_synth_keep2d.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/syn/scripts/dc_elab_fixed.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/syn/scripts/dc_elaborate_flat.tcl``。

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
