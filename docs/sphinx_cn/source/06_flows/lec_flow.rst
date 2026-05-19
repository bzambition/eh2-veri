.. _lec_flow:
.. _06_flows/lec_flow:

LEC 流程 — 详细参考
================================================================================

:status: draft
:source: syn/Makefile; syn/scripts/lec_blocklevel/lec_common.tcl; syn/scripts/lec_blocklevel/lec_dec.tcl; syn/scripts/lec_blocklevel/lec_lsu.tcl; syn/scripts/lec_blocklevel/lec_ifu.tcl; syn/scripts/lec_blocklevel/lec_exu_alu.tcl; syn/scripts/lec_blocklevel/lec_exu_mul.tcl; syn/scripts/lec_blocklevel/lec_exu_div.tcl; syn/scripts/lec_summary.py; syn/build/lec_summary.txt; README.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
--------------------------------------------------------------------------------

读懂本章前，请先确认：

* :ref:`synthesis_flow` — 知道 DC 综合会生成 netlist、DDC 和 SVF；
* :ref:`signoff_flow` — 知道 syn stage 读取 ``syn/build/lec_summary.txt`` 做 gate；
* :ref:`coverage_plan` — 能区分 coverage gate 与 LEC gate，二者不能互相替代；
* 基础 LEC（logic equivalence checking）概念：reference design、implementation
  design、compare point、SVF、failing/unverified；
* 基础 Tcl/Make 概念：``fm_shell -f``、``dc_shell -f``、per-block 循环。

LEC 的目标是证明综合后的 implementation 与 RTL reference 在逻辑上等价。EH2 当前
sign-off 使用 block-level Formality 流程，而不是早期 top-level 兜底路径。最新证据是
9 个 block、``31635/31635`` compare points PASS，failing 和 unverified 都为 ``0``。

学完本章你应该能够：

1. 解释为什么当前签核数字来自 ``syn/build/lec_summary.txt`` 的 TOTAL 行。
2. 区分 DC 阶段的 ``dc_<top>.log`` 与 Formality 阶段的 ``lec_<label>.rpt``。
3. 说明 ADR-0020 为什么选择 block-level LEC，而不是继续依赖 top-level packed-port 失败路径。
4. 跑 ``make -C syn block_lec`` 后知道先看哪个目录、哪个 summary 文件。
5. 解释 LEC PASS 不能替代 UVM、formal 或 compliance，只说明综合等价。

§1  流程边界
--------------------------------------------------------------------------------

EH2 当前 VCS 主线的 LEC 结果是 ``31635/31635 PASS``。这个数字不是
从单一 top-level ``eh2_veer`` Formality 脚本得出，而是来自 R3-C
block-level Formality 流程生成的 :file:`syn/build/lec_summary.txt`。2026-05-19
demo 记录了同一组结果：9 个 block，``31635``
passing compare points，``0`` failing compare points，``0`` unverified compare
points。

本章说明“如何跑出并汇总该结果”，不重复 :ref:`appendix_c_tools/syn_lec`
中每个 Tcl 文件的源码字典。边界如下：

.. code-block:: text

   make block_lec
      |
      `-- make -C syn block_lec
            |
            |-- for each top in BLOCK_LEC_TOPS
            |     `-- dc_shell -f syn/scripts/dc_synth_block.tcl
            |
            |-- for each label in BLOCK_LEC_LABELS
            |     `-- fm_shell -f syn/scripts/lec_blocklevel/lec_<label>.tcl
            |
            `-- python3 syn/scripts/lec_summary.py
                  `-- syn/build/lec_summary.txt

**逐段解释** ：

* ``BLOCK_LEC_TOPS`` 和 ``BLOCK_LEC_LABELS`` 在 :file:`syn/Makefile` 中定义。
  top 列表面向 DC 综合，label 列表面向 Formality Tcl 文件名。
* 每个 block 先生成 standalone implementation，再由对应
  :file:`syn/scripts/lec_blocklevel/lec_<label>.tcl` 做 RTL-to-netlist LEC。
* :file:`syn/scripts/lec_summary.py` 只读取工具报告，不修改报告内容。它把
  ``lec_<label>.rpt`` 中的 passing、failing、unverified 计数汇总到
  :file:`syn/build/lec_summary.txt`。

**接口关系** ：

* **上游入口** ：顶层 ``make block_lec`` 或直接 ``make -C syn block_lec``。
* **下游工具** ：Synopsys Design Compiler ``dc_shell`` 与 Synopsys Formality
  ``fm_shell``。
* **共享状态** ：所有 LEC 中间文件和报告都位于 :file:`syn/build/lec_blocklevel/`。

§1.1  2026-05-19 结果证据
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当前 demo 固定 LEC sign-off 数字，防止流程文档把旧的
top-level 失败路径误写成当前结果。

**关键代码** （``syn/build/lec_summary.txt``）：

.. code-block:: text

   | Module | Passing | Failing | Unverified | Status |
   |---|---:|---:|---:|---:|
   | `eh2_dec` | 7160 | 0 | 0 | PASS |
   | `eh2_exu_alu_ctl` | 294 | 0 | 0 | PASS |
   | `eh2_exu_mul_ctl` | 272 | 0 | 0 | PASS |
   | `eh2_exu_div_ctl` | 181 | 0 | 0 | PASS |
   | `eh2_lsu` | 3565 | 0 | 0 | PASS |
   | `eh2_pic_ctrl` | 1573 | 0 | 0 | PASS |
   | `eh2_dma_ctrl` | 967 | 0 | 0 | PASS |
   | `eh2_dbg` | 571 | 0 | 0 | PASS |
   | `eh2_ifu` | 17052 | 0 | 0 | PASS |
   | TOTAL | 31635 | 0 | 0 | PASS |

**逐段解释** ：

* 9 个 closed module 与 compare point 计数逐项列出。EXU 不是
  单体 ``eh2_exu``，而是 ``eh2_exu_alu_ctl``、``eh2_exu_mul_ctl``、
  ``eh2_exu_div_ctl`` 三个子块。
* TOTAL 行是 31635 passing、0 failing、0 unverified、PASS。该 summary 不使用
  ``set_dont_verify_points`` waiver。

**接口关系** ：

* **被调用** ：sign-off、demo 摘要和本章引用这些数字作为结果证据。
* **调用** ：无脚本调用；这是文档层证据。
* **共享状态** ：必须与 :file:`syn/build/lec_summary.txt` 和 :ref:`adr-0020`
  保持一致。

§2  ``syn/Makefile:block_lec`` — 当前执行入口
--------------------------------------------------------------------------------

§2.1  block 列表与报告目录
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`syn/Makefile` 定义 block-level LEC 的 top、label、report
目录和 run 目录。所有后续循环都从这些变量展开。

**关键代码** （``syn/Makefile:L36-L52``）：

.. code-block:: text

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

* 第 36-L45 行：``BLOCK_LEC_TOPS`` 是 DC 综合输入的 RTL top 列表。列表中没有
  ``eh2_mem`` 或 ``lib``，因此流程文档不能把这两个名字写成当前
  block-level LEC 模块。
* 第 47 行：``BLOCK_LEC_LABELS`` 是 Formality Tcl 文件名中的 label 列表。
  例如 label ``exu_mul`` 对应
  :file:`syn/scripts/lec_blocklevel/lec_exu_mul.tcl`。
* 第 48-L50 行：report、DC run、FM run 都落在
  :file:`syn/build/lec_blocklevel/` 之下。
* 第 51 行：``BLOCK_LEC_RESYNTH`` 默认 ``0``，表示已有 standalone block
  netlist 时可以复用。

**接口关系** ：

* **被调用** ：``block_lec`` target 的两个 ``for`` loop 读取这些变量。
* **调用** ：变量本身不调用工具。
* **共享状态** ：决定 ``lec_summary.py`` 后续查找报告的目录。

§2.2  pre-flight 与目录创建
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``block_lec`` 在运行工具前创建目录，并检查 ``dc_shell`` 与
``fm_shell`` 是否存在。

**关键代码** （``syn/Makefile:L99-L111``）：

.. code-block:: text

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

* 第 100-L103 行：target 开始后先创建 report 目录、standalone synth 目录、DC
  run 目录和 FM run 目录。
* 第 104-L107 行：没有 ``dc_shell`` 时立即退出。这个检查发生在任何 block 综合
  之前。
* 第 108-L111 行：没有 ``fm_shell`` 时立即退出。该检查保证不会只完成 DC 综合
  而跳过 Formality。

**接口关系** ：

* **被调用** ：用户执行 ``make -C syn block_lec`` 时进入。
* **调用** ：调用 shell 内建检查 ``command -v``。
* **共享状态** ：写入 :file:`syn/build/lec_blocklevel/` 下的目录结构。

§2.3  per-block DC 综合循环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：第一个 ``for`` loop 为每个 block 生成或复用 standalone netlist；
``eh2_ifu`` 额外传入 ``R3C_SIMPLE_COMPILE=1``。

**关键代码** （``syn/Makefile:L112-L127``）：

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
   		else \
   			echo "  DC synth: $${top} (reuse existing netlist)"; \
   		fi; \
   	done

**逐段解释** ：

* 第 112-L114 行：循环遍历 ``BLOCK_LEC_TOPS``。当
  ``BLOCK_LEC_RESYNTH=1`` 或 block netlist 不存在时才重新运行 DC。
* 第 115-L119 行：打印当前 top。``eh2_ifu`` 单独设置
  ``R3C_SIMPLE_COMPILE=1``，其余 block 的 ``extra_env`` 为空。
* 第 120-L123 行：每个 top 在独立 DC run 目录内执行
  :file:`syn/scripts/dc_synth_block.tcl`，并通过 ``R3C_BLOCK_TOP`` 指定综合 top。
* 第 124-L126 行：当 netlist 已存在且未强制 resynth 时，target 复用
  :file:`syn/build/lec_blocklevel/synth/<top>.v`。

**接口关系** ：

* **被调用** ：``block_lec`` target 的 pre-flight 之后执行。
* **调用** ：Design Compiler ``dc_shell`` 和
  :file:`syn/scripts/dc_synth_block.tcl`。
* **共享状态** ：读取 ``BLOCK_LEC_RESYNTH``；写入 ``dc_<top>.log``、
  ``synth/<top>.v``、``synth/<top>.ddc`` 和 ``synth/<top>.svf``。

§2.4  per-label Formality 循环与 summary
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：第二个 ``for`` loop 按 label 启动 Formality；所有 label 完成后
调用 Python 汇总器。

**关键代码** （``syn/Makefile:L128-L137``）：

.. code-block:: text

   	@for label in $(BLOCK_LEC_LABELS); do \
   		echo "  Formality LEC: $${label}"; \
   		mkdir -p $(BLOCK_LEC_FM_RUN_DIR)/$${label}; \
   		(cd $(BLOCK_LEC_FM_RUN_DIR)/$${label} && \
   		  env R3C_FM_RUN_DIR=$(BLOCK_LEC_FM_RUN_DIR)/$${label} \
   		  fm_shell -f $(SYN_DIR)/scripts/lec_blocklevel/lec_$${label}.tcl \
   		    > $(BLOCK_LEC_RPT_DIR)/lec_$${label}.log 2>&1); \
   	done
   	@python3 $(SYN_DIR)/scripts/lec_summary.py
   	@echo "=== R3-C Block-level LEC done ==="

**逐段解释** ：

* 第 128-L134 行：循环遍历 ``BLOCK_LEC_LABELS``，为每个 label 创建独立 FM run
  目录，并把 ``R3C_FM_RUN_DIR`` 传给 Tcl。
* 第 132-L134 行：Tcl 文件名由 ``lec_$${label}.tcl`` 拼接得到。label ``pic``
  对应 :file:`syn/scripts/lec_blocklevel/lec_pic.tcl`。
* 第 136 行：所有 Formality run 完成后执行 :file:`syn/scripts/lec_summary.py`。
  summary 的输入不是 DC log，而是 Formality ``report_status`` 产物。
* 第 137 行：target 结束时打印 block-level LEC 完成标记。

**接口关系** ：

* **被调用** ：per-block DC 循环结束后执行。
* **调用** ：Synopsys Formality ``fm_shell`` 和 Python 汇总器。
* **共享状态** ：写入 ``lec_<label>.log``，读取并生成 ``lec_<label>.rpt``、
  ``lec_<label>_failing.rpt``、``lec_<label>_unverified.rpt``。

§3  ``lec_common.tcl`` — 共享 Formality 环境
--------------------------------------------------------------------------------

§3.1  路径、run 目录和全局 app var
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：共享 Tcl 设置 EH2 root、build path、report path、Formality run 目录、
SystemVerilog 标准、验证模式和 search path。

**关键代码** （``syn/scripts/lec_blocklevel/lec_common.tcl:L6-L27``）：

.. code-block:: text

   set EH2_ROOT /home/host/eh2-veri
   set BUILD_DIR $EH2_ROOT/syn/build
   set RPT_DIR $BUILD_DIR/lec_blocklevel
   file mkdir $RPT_DIR
   
   # Redirect Formality working files to a dedicated build subdir.
   if {[info exists env(R3C_FM_RUN_DIR)] && $env(R3C_FM_RUN_DIR) ne ""} {
       set RUN_DIR $env(R3C_FM_RUN_DIR)
   } else {
       set RUN_DIR $RPT_DIR/run/fm/shared
   }
   file mkdir $RUN_DIR
   cd $RUN_DIR
   catch {set_app_var hdlin_temporary_dir $RUN_DIR}
   
   set R3C_SVF_PRELOADED 0
   
   suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
   set_app_var hdlin_sverilog_std 2012
   set verification_mode relaxed
   set verification_set_undriven_signals 0
   set verification_clock_gate_hold_mode low

**逐段解释** ：

* 第 6-L9 行：固定 EH2 repo root、:file:`syn/build` 和 block-level report 目录。
* 第 12-L19 行：优先使用环境变量 ``R3C_FM_RUN_DIR``；若未传入，则使用共享
  fallback 目录 ``run/fm/shared``。随后切换当前目录并尝试设置
  ``hdlin_temporary_dir``。
* 第 21 行：``R3C_SVF_PRELOADED`` 初值为 ``0``，后续 SVF preload 逻辑会更新它。
* 第 23-L27 行：抑制指定 Formality message，设置 ``hdlin_sverilog_std`` 为
  ``2012``，启用 relaxed verification mode，并设置 undriven signal 与 clock
  gate hold 处理方式。

**关键代码** （``syn/scripts/lec_blocklevel/lec_common.tcl:L29-L40``）：

.. code-block:: text

   set_app_var search_path [concat \
       $RUN_DIR \
       $RPT_DIR \
       $EH2_ROOT/syn/include \
       /home/host/Cores-VeeR-EH2/snapshots/default \
       /home/host/Cores-VeeR-EH2/design/include \
       /home/host/Cores-VeeR-EH2/design/lib \
       [get_app_var search_path]]
   
   puts "FM: R3-C reading technology libraries..."
   read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
   read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

**逐段解释** ：

* 第 29-L36 行：search path 合并 run 目录、report 目录、repo include 目录、
  VeeR EH2 snapshot 目录和 Formality 原有 search path。
* 第 38-L40 行：读取 Synopsys ``class.db`` 和 ``gtech.db``。这些库用于解析
  综合 netlist 中的 cell reference。

**接口关系** ：

* **被调用** ：每个 :file:`syn/scripts/lec_blocklevel/lec_<label>.tcl` 通过
  ``source`` 载入。
* **调用** ：Formality ``set_app_var``、``read_db`` 等命令。
* **共享状态** ：设置 ``EH2_ROOT``、``BUILD_DIR``、``RPT_DIR``、``RUN_DIR``、
  ``R3C_SVF_PRELOADED``。

§3.2  SVF preload 与 reference 读取
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：根据环境变量提前加载 SVF guide，然后读取 reference design。

**关键代码** （``syn/scripts/lec_blocklevel/lec_common.tcl:L42-L66``）：

.. code-block:: text

   if {[info exists env(R3C_PRELOAD_SVF_FILE)] && $env(R3C_PRELOAD_SVF_FILE) ne ""} {
       if {[file exists $env(R3C_PRELOAD_SVF_FILE)]} {
           puts "FM: R3-C preloading explicit SVF guide $env(R3C_PRELOAD_SVF_FILE)"
           set_svf $env(R3C_PRELOAD_SVF_FILE)
           set R3C_SVF_PRELOADED 1
       } else {
           puts "FM: R3-C WARNING: explicit SVF guide missing: $env(R3C_PRELOAD_SVF_FILE)"
       }
   } elseif {[info exists env(R3C_PRELOAD_SVF_TOP)] && $env(R3C_PRELOAD_SVF_TOP) ne ""} {
       set preload_svf $RPT_DIR/synth/$env(R3C_PRELOAD_SVF_TOP).svf
       if {[file exists $preload_svf]} {
           puts "FM: R3-C preloading block SVF guide $preload_svf"
           set_svf $preload_svf
           set R3C_SVF_PRELOADED 1
       } elseif {[file exists $EH2_ROOT/default.svf]} {
           puts "FM: R3-C WARNING: block SVF missing for $env(R3C_PRELOAD_SVF_TOP); preloading $EH2_ROOT/default.svf"
           set_svf $EH2_ROOT/default.svf
           set R3C_SVF_PRELOADED 1
       } else {
           puts "FM: R3-C WARNING: no pre-readable SVF guide available for $env(R3C_PRELOAD_SVF_TOP)"
       }
   }
   
   puts "FM: R3-C reading reference design from $BUILD_DIR/eh2_dc_wrapper.sv"
   read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv

**逐段解释** ：

* 第 42-L49 行：若 ``R3C_PRELOAD_SVF_FILE`` 存在且非空，脚本先检查文件存在，
  再调用 ``set_svf`` 并把 ``R3C_SVF_PRELOADED`` 置为 ``1``。文件缺失时只打印
  warning，不退出。
* 第 50-L63 行：若没有显式 SVF 文件但有 ``R3C_PRELOAD_SVF_TOP``，脚本尝试加载
  ``synth/<top>.svf``，失败时 fallback 到 repo root 下的 ``default.svf``。
* 第 65-L66 行：SVF preload 判定完成后读取 reference design
  :file:`syn/build/eh2_dc_wrapper.sv`，并以 ``-r`` 标记为 reference。

**接口关系** ：

* **被调用** ：IFU、EXU ALU/MUL/DIV 等脚本在 ``source lec_common.tcl`` 前设置
  ``R3C_PRELOAD_SVF_TOP``。
* **调用** ：Formality ``set_svf`` 和 ``read_sverilog -r``。
* **共享状态** ：读取环境变量 ``R3C_PRELOAD_SVF_FILE``、
  ``R3C_PRELOAD_SVF_TOP``；更新 ``R3C_SVF_PRELOADED``。

§3.3  ``r3c_load_svf`` — 按 top 延迟加载 SVF
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当没有提前 preload SVF 时，为当前 block 加载
``syn/build/lec_blocklevel/synth/<top>.svf``，必要时 fallback 到 ``default.svf``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_common.tcl:L68-L88``）：

.. code-block:: text

   proc r3c_load_svf {top} {
       global RPT_DIR EH2_ROOT R3C_SVF_PRELOADED
       if {$R3C_SVF_PRELOADED} {
           puts "FM: R3-C SVF guide already preloaded for $top"
           return
       }
       set block_svf $RPT_DIR/synth/${top}.svf
       if {[file exists $block_svf]} {
           puts "FM: R3-C loading block SVF guide $block_svf"
           if {[catch {set_svf $block_svf} msg]} {
               puts "FM: R3-C WARNING: set_svf failed for $top: $msg"
           }
       } elseif {[file exists $EH2_ROOT/default.svf]} {
           puts "FM: R3-C WARNING: block SVF missing for $top; falling back to $EH2_ROOT/default.svf"
           if {[catch {set_svf $EH2_ROOT/default.svf} msg]} {
               puts "FM: R3-C WARNING: set_svf failed for default.svf: $msg"
           }
       } else {
           puts "FM: R3-C WARNING: no SVF guide available for $top"
       }
   }

**逐段解释** ：

* 第 68-L73 行：proc 接收 ``top`` 参数。如果 ``R3C_SVF_PRELOADED`` 已经为真，
  说明前置逻辑已加载 SVF，本 proc 直接返回。
* 第 74-L79 行：优先加载 per-block SVF。``set_svf`` 被包在 ``catch`` 中，失败时
  打印 warning。
* 第 80-L84 行：per-block SVF 不存在时尝试加载 ``default.svf``。
* 第 85-L87 行：两类 SVF 都不存在时只打印 warning。是否继续由后续 match/verify
  的 Formality 结果决定。

**接口关系** ：

* **被调用** ：所有 block-level LEC 脚本在设置 implementation top 后调用。
* **调用** ：Formality ``set_svf``。
* **共享状态** ：读取 ``RPT_DIR``、``EH2_ROOT``、``R3C_SVF_PRELOADED``。

§3.4  ``r3c_read_impl`` — 选择 implementation 输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：按环境变量和文件存在性选择 implementation design：强制 top-context、
强制 standalone Verilog、standalone DDC、standalone Verilog，最后 fallback 到
top-context netlist。

**关键代码** （``syn/scripts/lec_blocklevel/lec_common.tcl:L90-L110``）：

.. code-block:: text

   proc r3c_read_impl {top} {
       global BUILD_DIR RPT_DIR env
       set block_ddc $RPT_DIR/synth/${top}.ddc
       set block_netlist $RPT_DIR/synth/${top}.v
       if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
           puts "FM: R3-C reading forced top-context implementation from $BUILD_DIR/eh2_synth.v"
           read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
       } elseif {[info exists env(R3C_FORCE_VERILOG_IMPL)] && $env(R3C_FORCE_VERILOG_IMPL) eq "1" && [file exists $block_netlist]} {
           puts "FM: R3-C reading forced standalone Verilog implementation from $block_netlist"
           read_verilog -i -libname WORK $block_netlist
       } elseif {[file exists $block_ddc]} {
           puts "FM: R3-C reading standalone block DDC implementation from $block_ddc"
           read_ddc -i -libname WORK $block_ddc
       } elseif {[file exists $block_netlist]} {
           puts "FM: R3-C reading standalone block implementation from $block_netlist"
           read_verilog -i -libname WORK $block_netlist
       } else {
           puts "FM: R3-C reading top-context implementation from $BUILD_DIR/eh2_synth.v"
           puts "FM: R3-C WARNING: no standalone block netlist found for $top"
           read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
       }
   }

**逐段解释** ：

* 第 92-L93 行：为当前 ``top`` 计算 standalone DDC 和 Verilog netlist 路径。
* 第 94-L96 行：``R3C_FORCE_TOP_CONTEXT_IMPL=1`` 时读取完整
  :file:`syn/build/eh2_synth.v`。
* 第 97-L99 行：``R3C_FORCE_VERILOG_IMPL=1`` 且 standalone Verilog 存在时，强制
  读取 ``synth/<top>.v``。
* 第 100-L105 行：默认优先 standalone DDC，其次 standalone Verilog。
* 第 106-L109 行：standalone 文件都不存在时 fallback 到 top-context netlist，并
  打印 no standalone block netlist warning。

**接口关系** ：

* **被调用** ：每个 block-level LEC 脚本在设置 reference top 后调用。
* **调用** ：Formality ``read_ddc -i`` 或 ``read_verilog -i``。
* **共享状态** ：读取 ``BUILD_DIR``、``RPT_DIR``、环境变量
  ``R3C_FORCE_TOP_CONTEXT_IMPL``、``R3C_FORCE_VERILOG_IMPL``。

§3.5  ``r3c_set_impl_top`` 与 ``r3c_write_reports``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``r3c_set_impl_top`` 选择 implementation top 名称；``r3c_write_reports``
输出 status、failing point 和 unverified point 报告。

**关键代码** （``syn/scripts/lec_blocklevel/lec_common.tcl:L113-L139``）：

.. code-block:: text

   proc r3c_set_impl_top {top} {
       global RPT_DIR env
       set suffixed ${top}_
       if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
           puts "FM: R3-C using forced top-context implementation top $suffixed"
           set_top i:/WORK/$suffixed
       } elseif {[file exists $RPT_DIR/synth/${top}.v]} {
           puts "FM: R3-C using standalone implementation top $top"
           set_top i:/WORK/$top
       } else {
           puts "FM: R3-C using top-context implementation top $suffixed"
           set_top i:/WORK/$suffixed
       }
   }
   
   proc r3c_write_reports {label} {
       global RPT_DIR
       puts "FM: R3-C reporting $label"
       report_status > $RPT_DIR/lec_${label}.rpt
       if {[catch {report_failing_points > $RPT_DIR/lec_${label}_failing.rpt} msg]} {
           puts "FM: R3-C report_failing_points failed for $label: $msg"
       }
       if {[catch {report_failing_points -verbose > $RPT_DIR/lec_${label}_failing_verbose.rpt} msg]} {
           puts "FM: R3-C verbose failing report unsupported for $label: $msg"
       }
       report_unverified_points > $RPT_DIR/lec_${label}_unverified.rpt
   }

**逐段解释** ：

* 第 113-L125 行：top-context implementation 使用带尾下划线的 ``${top}_``；
  standalone implementation 使用原始 ``top``。选择条件与 standalone Verilog
  是否存在、是否强制 top-context 相关。
* 第 128-L131 行：``r3c_write_reports`` 用 label 生成
  ``lec_<label>.rpt``，该文件是 ``lec_summary.py`` 的主要输入。
* 第 132-L137 行：failing point 报告被 ``catch`` 包裹，避免某些 Formality 版本
  不支持 verbose report 时中断 report 输出。
* 第 138 行：unverified point 报告固定写入
  ``lec_<label>_unverified.rpt``。

**接口关系** ：

* **被调用** ：每个 block-level Tcl 调用 ``r3c_set_impl_top`` 和
  ``r3c_write_reports``。
* **调用** ：Formality ``set_top``、``report_status``、
  ``report_failing_points``、``report_unverified_points``。
* **共享状态** ：读取 ``RPT_DIR`` 和 ``R3C_FORCE_TOP_CONTEXT_IMPL``。

§4  per-block Formality 脚本模式
--------------------------------------------------------------------------------

§4.1  leaf block 模板：``dbg``、``dma``、``pic``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：简单 block 脚本只设置 top、读取 implementation、加载 SVF、执行
``match`` 和 ``verify``，最后写报告。

**关键代码** （``syn/scripts/lec_blocklevel/lec_dbg.tcl:L1-L19``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl
   
   puts "FM: R3-C block LEC dbg"
   set TOP eh2_dbg
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP
   
   puts "FM: R3-C matching dbg"
   match
   
   puts "FM: R3-C verifying dbg"
   verify
   r3c_write_reports dbg
   
   puts "FM: R3-C dbg complete"
   exit 0

**逐段解释** ：

* 第 1-L2 行：脚本禁止 shell continue-on-error，并加载共享 Formality 环境。
* 第 4-L9 行：设置 reference top 为 ``eh2_dbg``，随后调用共享 proc 读取
  implementation、选择 implementation top、加载 SVF。
* 第 11-L16 行：执行 ``match``、``verify``，再用 label ``dbg`` 写出报告。
* 第 18-L19 行：打印完成信息并以 ``exit 0`` 结束。

**接口关系** ：

* **被调用** ：``syn/Makefile:block_lec`` 在 label ``dbg`` 时调用。
* **调用** ：``r3c_read_impl``、``r3c_set_impl_top``、``r3c_load_svf``、
  ``r3c_write_reports``。
* **共享状态** ：读写 ``RPT_DIR`` 下的 ``lec_dbg.*`` 报告。

§4.2  ``lec_dec.tcl`` — packed struct、predict packet、trace pkt 显式匹配
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：DEC block 在通用 match/verify 前添加 packed-struct 和 trace pkt 的
``set_user_match`` 映射，并记录映射数量。

**关键代码** （``syn/scripts/lec_blocklevel/lec_dec.tcl:L1-L13``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl
   
   puts "FM: R3-C block LEC dec"
   set TOP eh2_dec
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP
   
   set rtop r:/WORK/eh2_dec
   set itop i:/WORK/eh2_dec
   set user_match_count 0

**逐段解释** ：

* 第 1-L9 行：DEC 使用与 leaf block 相同的基础流程，top 为 ``eh2_dec``。
* 第 11-L13 行：设置 reference path ``rtop``、implementation path ``itop``，
  并把 ``user_match_count`` 初始化为 ``0``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_dec.tcl:L15-L28``）：

.. code-block:: text

   puts "FM: R3-C adding dec packed-struct port matches"
   foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70] {
       set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_wrdata\]\[$bit\] ${itop}/dec_tlu_ic_diag_pkt\[[expr {$bit + 19}]\]
       incr user_match_count
   }
   foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16] {
       set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_dicawics\]\[$bit\] ${itop}/dec_tlu_ic_diag_pkt\[[expr {$bit + 2}]\]
       incr user_match_count
   }
   set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_rd_valid\] ${itop}/dec_tlu_ic_diag_pkt\[1\]
   incr user_match_count
   set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_wr_valid\] ${itop}/dec_tlu_ic_diag_pkt\[0\]
   incr user_match_count

**逐段解释** ：

* 第 15-L19 行：``icache_wrdata`` 的 71 bit 按 ``bit + 19`` 映射到 flattened
  implementation vector。
* 第 20-L23 行：``icache_dicawics`` 的 17 bit 按 ``bit + 2`` 映射。
* 第 24-L27 行：两个 valid bit 分别映射到 flattened vector 的 bit ``1`` 和 bit
  ``0``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_dec.tcl:L29-L55``）：

.. code-block:: text

   foreach pred {i0_predict_p_d i1_predict_p_d} {
       foreach bit [list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
           set_user_match ${rtop}/${pred}\[prett\]\[$bit\] ${itop}/${pred}\[[expr {$bit + 13}]\]
           incr user_match_count
       }
       foreach bit {0 1} {
           set_user_match ${rtop}/${pred}\[hist\]\[$bit\] ${itop}/${pred}\[[expr {$bit + 11}]\]
           incr user_match_count
       }
       foreach {field idx} {
           boffset 13
           bank 10
           way 9
           ataken 8
           valid 7
           pc4 6
           misp 5
           br_error 4
           br_start_error 3
           pcall 2
           pret 1
           pja 0
       } {
           set_user_match ${rtop}/${pred}\[$field\] ${itop}/${pred}\[$idx\]
           incr user_match_count
       }
   }

**逐段解释** ：

* 第 29-L33 行：对 ``i0_predict_p_d`` 和 ``i1_predict_p_d`` 都映射 ``prett``
  字段。reference 的 bit ``1`` 到 ``31`` 映射到 implementation 的 ``bit + 13``。
* 第 34-L37 行：``hist[0]`` 和 ``hist[1]`` 映射到 implementation bit ``11`` 和
  ``12``。
* 第 38-L54 行：其余 scalar field 通过 Tcl list 给出固定 index 映射。每个
  ``set_user_match`` 后都递增 ``user_match_count``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_dec.tcl:L110-L123``）：

.. code-block:: text

   puts "FM: R3-C dec user_match_count=$user_match_count"
   set match_count_fh [open $RPT_DIR/lec_dec_user_match_count.txt w]
   puts $match_count_fh $user_match_count
   close $match_count_fh
   
   puts "FM: R3-C matching dec"
   match
   
   puts "FM: R3-C verifying dec"
   verify
   r3c_write_reports dec
   
   puts "FM: R3-C dec complete"
   exit 0

**逐段解释** ：

* 第 110-L113 行：DEC 将最终 ``user_match_count`` 写入
  :file:`syn/build/lec_blocklevel/lec_dec_user_match_count.txt`。
* 第 115-L120 行：显式匹配建立后才运行 ``match`` 和 ``verify``，然后输出 label
  ``dec`` 的报告。
* 第 122-L123 行：脚本正常退出。

**接口关系** ：

* **被调用** ：``syn/Makefile:block_lec`` 在 label ``dec`` 时调用。
* **调用** ：共享 proc、Formality ``set_user_match``、``match``、``verify``。
* **共享状态** ：写入 ``lec_dec.rpt`` 与 ``lec_dec_user_match_count.txt``。

§4.3  ``lec_lsu.tcl`` — LSU error packet 与 trigger packet 显式匹配
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：LSU block 为 ``lsu_error_pkt_dc3`` 和 ``trigger_pkt_any`` 添加
packed-struct 输入映射。

**关键代码** （``syn/scripts/lec_blocklevel/lec_lsu.tcl:L15-L33``）：

.. code-block:: text

   puts "FM: R3-C adding lsu lsu_error_pkt_dc3 packed-struct matches"
   foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
       set_user_match ${rtop}/lsu_error_pkt_dc3\[addr\]\[$bit\] ${itop}/lsu_error_pkt_dc3\[$bit\]
       incr user_match_count
   }
   foreach bit {0 1 2 3} {
       set_user_match ${rtop}/lsu_error_pkt_dc3\[mscause\]\[$bit\] ${itop}/lsu_error_pkt_dc3\[[expr {$bit + 32}]\]
       incr user_match_count
   }
   foreach {field idx} {
       exc_type 36
       amo_valid 37
       inst_type 38
       single_ecc_error 39
       exc_valid 40
   } {
       set_user_match ${rtop}/lsu_error_pkt_dc3\[$field\] ${itop}/lsu_error_pkt_dc3\[$idx\]
       incr user_match_count
   }

**逐段解释** ：

* 第 15-L19 行：``addr`` 的 32 bit 逐位映射到 implementation 的同 index bit。
* 第 20-L23 行：``mscause`` 的 4 bit 映射到 implementation bit ``32`` 到 ``35``。
* 第 24-L33 行：``exc_type``、``amo_valid``、``inst_type``、
  ``single_ecc_error``、``exc_valid`` 分别映射到 bit ``36`` 到 ``40``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_lsu.tcl:L35-L53``）：

.. code-block:: text

   puts "FM: R3-C adding lsu trigger_pkt_any packed-struct input matches"
   foreach trig {0 1 2 3} {
       set base [expr {$trig * 38}]
       foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
           set_user_match ${rtop}/trigger_pkt_any\[0\]\[$trig\]\[tdata2\]\[$bit\] ${itop}/trigger_pkt_any\[[expr {$base + $bit}]\]
           incr user_match_count
       }
       foreach {field idx} {
           m 32
           execute 33
           load 34
           store 35
           match 36
           select 37
       } {
           set_user_match ${rtop}/trigger_pkt_any\[0\]\[$trig\]\[$field\] ${itop}/trigger_pkt_any\[[expr {$base + $idx}]\]
           incr user_match_count
       }
   }

**逐段解释** ：

* 第 35-L37 行：4 个 trigger entry 逐个处理，每个 entry 的 flattened base 为
  ``trig * 38``。
* 第 38-L41 行：每个 trigger 的 ``tdata2[31:0]`` 映射到 ``base + bit``。
* 第 42-L52 行：每个 trigger 的 ``m``、``execute``、``load``、``store``、
  ``match``、``select`` 映射到 ``base + 32`` 到 ``base + 37``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_lsu.tcl:L55-L68``）：

.. code-block:: text

   puts "FM: R3-C lsu user_match_count=$user_match_count"
   set match_count_fh [open $RPT_DIR/lec_lsu_user_match_count.txt w]
   puts $match_count_fh $user_match_count
   close $match_count_fh
   
   puts "FM: R3-C matching lsu"
   match
   
   puts "FM: R3-C verifying lsu"
   verify
   r3c_write_reports lsu
   
   puts "FM: R3-C lsu complete"
   exit 0

**逐段解释** ：

* 第 55-L58 行：LSU 将匹配数量写入 ``lec_lsu_user_match_count.txt``。
* 第 60-L65 行：执行 Formality ``match`` 和 ``verify``，并输出 label ``lsu`` 的
  report。
* 第 67-L68 行：脚本以 ``exit 0`` 结束。

**接口关系** ：

* **被调用** ：``syn/Makefile:block_lec`` 在 label ``lsu`` 时调用。
* **调用** ：共享 proc、``set_user_match``、``match``、``verify``。
* **共享状态** ：写入 ``lec_lsu.rpt`` 与 ``lec_lsu_user_match_count.txt``。

§4.4  ``lec_ifu.tcl`` — IFU packed array 与 branch packet 显式匹配
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：IFU block 先做一次基础 ``match``，再根据 standalone/top-context
implementation 形态选择 ``rtop``/``itop``，随后添加 packed array 和 branch packet
匹配。

**关键代码** （``syn/scripts/lec_blocklevel/lec_ifu.tcl:L1-L24``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_ifu
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl
   
   puts "FM: R3-C block LEC ifu"
   set TOP eh2_ifu
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP
   
   puts "FM: R3-C matching ifu before explicit packed-array matches"
   match
   
   if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
       set rtop r:/WORK/eh2_ifu_
       set itop i:/WORK/eh2_ifu_
   } elseif {[file exists $RPT_DIR/synth/${TOP}.v]} {
       set rtop r:/WORK/eh2_ifu
       set itop i:/WORK/eh2_ifu
   } else {
       set rtop r:/WORK/eh2_ifu
       set itop i:/WORK/eh2_ifu_
   }

**逐段解释** ：

* 第 1-L3 行：IFU 在 source 共享脚本前设置 ``R3C_PRELOAD_SVF_TOP=eh2_ifu``，
  触发 ``lec_common.tcl`` 的 preload 分支。
* 第 5-L10 行：基础 top 设置、implementation 读取和 SVF 处理与其他 block 一致。
* 第 12-L13 行：在显式 packed-array mapping 前先运行一次 ``match``。
* 第 15-L24 行：根据 ``R3C_FORCE_TOP_CONTEXT_IMPL`` 和 standalone netlist 是否
  存在选择 reference/implementation path。top-context implementation 使用带尾
  下划线的 implementation top。

**关键代码** （``syn/scripts/lec_blocklevel/lec_ifu.tcl:L27-L61``）：

.. code-block:: text

   puts "FM: R3-C adding IFU ic_wr_data user matches"
   foreach way {0 1} {
       for {set bit 0} {$bit < 71} {incr bit} {
           set flat_idx [expr {$way * 71 + $bit}]
           set_user_match ${rtop}/ic_wr_data\[$way\]\[$bit\] ${itop}/ic_wr_data\[$flat_idx\]
           incr user_match_count
       }
   }
   
   puts "FM: R3-C adding IFU btb_rw_addr user matches"
   foreach way {0 1} {
       for {set bit 1} {$bit <= 9} {incr bit} {
           set flat_idx [expr {$way * 9 + ($bit - 1)}]
           set_user_match ${rtop}/btb_rw_addr\[$way\]\[$bit\] ${itop}/btb_rw_addr\[$flat_idx\]
           incr user_match_count
       }
   }
   
   puts "FM: R3-C adding IFU btb_rw_addr_f1 user matches"
   foreach way {0 1} {
       for {set bit 1} {$bit <= 9} {incr bit} {
           set flat_idx [expr {$way * 9 + ($bit - 1)}]
           set_user_match ${rtop}/btb_rw_addr_f1\[$way\]\[$bit\] ${itop}/btb_rw_addr_f1\[$flat_idx\]
           incr user_match_count
       }
   }

**逐段解释** ：

* 第 27-L34 行：``ic_wr_data`` 有 2 个 way，每个 way 71 bit，flattened index 为
  ``way * 71 + bit``。
* 第 36-L43 行：``btb_rw_addr`` 的 bit 范围从 ``1`` 到 ``9``，flattened index
  为 ``way * 9 + (bit - 1)``。
* 第 45-L52 行：``btb_rw_addr_f1`` 使用同样的 way/bit flatten 规则。

**关键代码** （``syn/scripts/lec_blocklevel/lec_ifu.tcl:L63-L90``）：

.. code-block:: text

   proc r3c_ifu_add_brp_matches {rtop itop port_name user_match_count_name} {
       upvar $user_match_count_name user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[way\] ${itop}/${port_name}\[0\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[hist\]\[0\] ${itop}/${port_name}\[1\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[hist\]\[1\] ${itop}/${port_name}\[2\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[valid\] ${itop}/${port_name}\[3\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[bank\] ${itop}/${port_name}\[4\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[br_start_error\] ${itop}/${port_name}\[5\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[br_error\] ${itop}/${port_name}\[6\]
       incr user_match_count
       for {set bit 1} {$bit <= 31} {incr bit} {
           set flat_idx [expr {$bit + 6}]
           set_user_match ${rtop}/${port_name}\[0\]\[prett\]\[$bit\] ${itop}/${port_name}\[$flat_idx\]
           incr user_match_count
       }
       set_user_match ${rtop}/${port_name}\[0\]\[ret\] ${itop}/${port_name}\[38\]
       incr user_match_count
   }
   
   puts "FM: R3-C adding IFU branch packet user matches"
   r3c_ifu_add_brp_matches $rtop $itop i0_brp user_match_count
   r3c_ifu_add_brp_matches $rtop $itop i1_brp user_match_count

**逐段解释** ：

* 第 63-L64 行：局部 proc 通过 ``upvar`` 修改外层 ``user_match_count``。
* 第 65-L78 行：branch packet 中的 scalar field 逐项映射到 flattened vector
  index ``0`` 到 ``6``。
* 第 79-L83 行：``prett[1:31]`` 映射到 ``bit + 6``，覆盖 flattened bit ``7``
  到 ``37``。
* 第 84-L85 行：``ret`` 映射到 flattened bit ``38``。
* 第 88-L90 行：同一个 proc 分别应用到 ``i0_brp`` 和 ``i1_brp``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_ifu.tcl:L100-L113``）：

.. code-block:: text

   puts "FM: R3-C ifu user_match_count=$user_match_count"
   set match_count_fh [open $RPT_DIR/lec_ifu_user_match_count.txt w]
   puts $match_count_fh $user_match_count
   close $match_count_fh
   
   puts "FM: R3-C matching ifu after explicit packed-array matches"
   match
   
   puts "FM: R3-C verifying ifu"
   verify
   r3c_write_reports ifu
   
   puts "FM: R3-C ifu complete"
   exit 0

**逐段解释** ：

* 第 100-L103 行：IFU 将显式匹配数量写入 ``lec_ifu_user_match_count.txt``。
* 第 105-L110 行：添加 packed-array mapping 后再次 ``match``，随后 ``verify`` 并
  写出 label ``ifu`` 的报告。
* 第 112-L113 行：脚本正常退出。

**接口关系** ：

* **被调用** ：``syn/Makefile:block_lec`` 在 label ``ifu`` 时调用。
* **调用** ：共享 proc、局部 ``r3c_ifu_add_brp_matches``、``set_user_match``、
  ``match``、``verify``。
* **共享状态** ：读取 ``R3C_FORCE_TOP_CONTEXT_IMPL``；写入 ``lec_ifu.rpt`` 与
  ``lec_ifu_user_match_count.txt``。

§4.5  EXU 子块：``alu``、``mul``、``div``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：EXU 在当前 closure path 中不是单体 ``eh2_exu``，而是拆成 ALU、MUL、
DIV 三个子块。该选择由 :ref:`adr-0020` 记录。

**关键代码** （``syn/scripts/lec_blocklevel/lec_exu_alu.tcl:L1-L37``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_exu_alu_ctl
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl
   
   puts "FM: R3-C EXU sub-block LEC alu"
   set TOP eh2_exu_alu_ctl
   set LABEL exu_alu
   
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP
   
   set rtop r:/WORK/$TOP
   set itop i:/WORK/$TOP
   set user_match_count 0
   
   puts "FM: R3-C adding alu predict_p_ff packed-struct matches"
   set_user_match ${rtop}/predict_p_ff\[ataken\] ${itop}/predict_p_ff\[8\]
   incr user_match_count
   set_user_match ${rtop}/predict_p_ff\[misp\] ${itop}/predict_p_ff\[5\]
   incr user_match_count
   set_user_match ${rtop}/predict_p_ff\[hist\]\[0\] ${itop}/predict_p_ff\[11\]
   incr user_match_count

**逐段解释** ：

* 第 1-L7 行：ALU 子块设置 ``R3C_PRELOAD_SVF_TOP=eh2_exu_alu_ctl``，top 为
  ``eh2_exu_alu_ctl``，summary label 为 ``exu_alu``。
* 第 9-L12 行：读取 reference 和 implementation，并加载对应 SVF。
* 第 14-L23 行：ALU 为 ``predict_p_ff`` 的部分 packed-struct field 添加
  ``set_user_match``，并递增 ``user_match_count``。

**关键代码** （``syn/scripts/lec_blocklevel/lec_exu_mul.tcl:L1-L34``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_exu_mul_ctl
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl
   
   puts "FM: R3-C EXU sub-block LEC mul"
   set TOP eh2_exu_mul_ctl
   set LABEL exu_mul
   if {[info exists env(R3C_REPORT_LABEL)] && $env(R3C_REPORT_LABEL) ne ""} {
       set LABEL $env(R3C_REPORT_LABEL)
   }
   set verification_timeout_limit 0:5:0
   set verification_datapath_effort_level High
   if {[info exists env(R3C_FM_STRATEGY)] && $env(R3C_FM_STRATEGY) ne ""} {
       puts "FM: R3-C using MUL alternate strategy $env(R3C_FM_STRATEGY)"
       set_app_var verification_alternate_strategy $env(R3C_FM_STRATEGY)
   }
   if {[info exists env(R3C_FM_PASSING_MODE)] && $env(R3C_FM_PASSING_MODE) ne ""} {
       puts "FM: R3-C using MUL passing mode $env(R3C_FM_PASSING_MODE)"
       set_app_var verification_passing_mode $env(R3C_FM_PASSING_MODE)
   }

**逐段解释** ：

* 第 1-L7 行：MUL 子块 top 为 ``eh2_exu_mul_ctl``，默认 label 为 ``exu_mul``。
* 第 8-L10 行：若 ``R3C_REPORT_LABEL`` 存在且非空，脚本用该环境变量覆盖 label。
* 第 11-L12 行：MUL 设置 ``verification_timeout_limit`` 为 ``0:5:0``，并把
  datapath effort 设为 ``High``。
* 第 13-L20 行：``R3C_FM_STRATEGY`` 与 ``R3C_FM_PASSING_MODE`` 可分别传入
  Formality alternate strategy 和 passing mode。

**关键代码** （``syn/scripts/lec_blocklevel/lec_exu_div.tcl:L1-L23``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_exu_div_ctl
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl
   
   puts "FM: R3-C EXU sub-block LEC div"
   set TOP eh2_exu_div_ctl
   set LABEL exu_div
   set verification_timeout_limit 0:5:0
   
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP
   
   puts "FM: R3-C matching $TOP"
   match
   
   puts "FM: R3-C verifying $TOP"
   verify -level 1
   r3c_write_reports $LABEL
   
   puts "FM: R3-C EXU sub-block div complete"
   exit 0

**逐段解释** ：

* 第 1-L8 行：DIV 子块 top 为 ``eh2_exu_div_ctl``，label 为 ``exu_div``，并设置
  5 分钟 verification timeout。
* 第 10-L13 行：读取 reference/implementation，选择 implementation top 并加载
  SVF。
* 第 15-L20 行：运行 ``match``，随后用 ``verify -level 1`` 做等价验证并写报告。
* 第 22-L23 行：脚本正常退出。

**接口关系** ：

* **被调用** ：``syn/Makefile:block_lec`` 在 label ``exu_alu``、``exu_mul``、
  ``exu_div`` 时调用。
* **调用** ：共享 proc、Formality ``set_user_match``、``set_app_var``、
  ``match``、``verify``。
* **共享状态** ：写入 ``lec_exu_alu.rpt``、``lec_exu_mul.rpt``、
  ``lec_exu_div.rpt``，供 ``lec_summary.py`` 替代旧的单体 ``lec_exu``。

§5  ``lec_summary.py`` — 报告解析与 TOTAL 生成
--------------------------------------------------------------------------------

§5.1  module 列表与输出路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Python 汇总器定位 :file:`syn/build/lec_blocklevel`，定义 base modules
和 EXU submodules，并把 summary 写到 :file:`syn/build/lec_summary.txt`。

**关键代码** （``syn/scripts/lec_summary.py:L9-L26``）：

.. code-block:: python

   SYN_ROOT = Path(__file__).resolve().parents[1]
   BUILD = SYN_ROOT / "build" / "lec_blocklevel"
   OUT = SYN_ROOT / "build" / "lec_summary.txt"
   
   BASE_MODULES = [
       ("eh2_dec", "dec"),
       ("eh2_lsu", "lsu"),
       ("eh2_pic_ctrl", "pic"),
       ("eh2_dma_ctrl", "dma"),
       ("eh2_dbg", "dbg"),
       ("eh2_ifu", "ifu"),
   ]
   
   EXU_SUBMODULES = [
       ("eh2_exu_alu_ctl", "exu_alu"),
       ("eh2_exu_mul_ctl", "exu_mul"),
       ("eh2_exu_div_ctl", "exu_div"),
   ]

**逐段解释** ：

* 第 9-L11 行：脚本从自身路径反推 :file:`syn/` root，读取
  :file:`syn/build/lec_blocklevel`，输出 :file:`syn/build/lec_summary.txt`。
* 第 13-L20 行：base modules 包含 DEC、LSU、PIC、DMA、DBG、IFU。
* 第 22-L26 行：EXU 子模块单独列为 ALU、MUL、DIV。summary 的 EXU 选择逻辑在
  ``main()`` 中决定。

**接口关系** ：

* **被调用** ：``syn/Makefile:block_lec`` 在所有 Formality run 后调用。
* **调用** ：Python ``pathlib`` 和文件读取 API。
* **共享状态** ：读取 ``syn/build/lec_blocklevel/lec_*.rpt``，写入
  ``syn/build/lec_summary.txt``。

§5.2  ``_extract_int()`` 与 ``parse_module()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``_extract_int()`` 从 report 文本中提取整数；``parse_module()`` 读取单个
label 的 report、timeout report 和 log，生成 module 状态字典。

**关键代码** （``syn/scripts/lec_summary.py:L29-L63``）：

.. code-block:: python

   def _extract_int(pattern, text):
       match = re.search(pattern, text)
       return int(match.group(1)) if match else 0
   
   
   def parse_module(label):
       rpt = BUILD / f"lec_{label}.rpt"
       timeout_rpt = BUILD / f"lec_{label}_timeout_status.rpt"
       log = BUILD / f"lec_{label}.log"
       if not rpt.exists():
           return {
               "passing": 0,
               "failing": 0,
               "unverified": 0,
               "status": "MISSING",
               "note": "report missing",
           }
   
       source_rpt = rpt
       if timeout_rpt.exists() and timeout_rpt.stat().st_mtime > rpt.stat().st_mtime:
           source_rpt = timeout_rpt
   
       text = source_rpt.read_text(encoding="utf-8", errors="replace")
       passing = _extract_int(r"(\d+)\s+Passing compare points", text)
       failing = _extract_int(r"(\d+)\s+Failing compare points", text)
       unverified = _extract_int(r"(\d+)\s+Unverified compare points", text)
   
       if "Verification SUCCEEDED" in text and failing == 0 and unverified == 0:
           status = "PASS"

**逐段解释** ：

* 第 29-L31 行：``_extract_int`` 用正则匹配第一个 capture group；没有匹配时返回
  ``0``。
* 第 34-L45 行：``parse_module`` 为 label 计算 ``lec_<label>.rpt``、
  ``lec_<label>_timeout_status.rpt`` 和 ``lec_<label>.log``。缺少主 report 时，
  状态为 ``MISSING``。
* 第 47-L54 行：如果 timeout report 比主 report 新，则用 timeout report 作为
  解析源。随后提取 passing、failing、unverified 三类 compare point 数字。
* 第 56-L63 行：只有文本包含 ``Verification SUCCEEDED`` 且 failing/unverified
  都为 ``0`` 时才标记 ``PASS``；失败和 inconclusive 通过关键字识别。

**关键代码** （``syn/scripts/lec_summary.py:L65-L90``）：

.. code-block:: python

       note = ""
       if source_rpt == timeout_rpt:
           note = "graceful timeout status"
       if log.exists():
           log_text = log.read_text(encoding="utf-8", errors="replace")
           if "Process terminated by kill" in log_text or "Received Signal 15" in log_text:
               if source_rpt == timeout_rpt:
                   status = "INCONCLUSIVE"
               else:
                   status = "TIMEOUT"
                   if "0(0) Unmatched reference(implementation) compare points" in log_text:
                       note = "latest run timed out after clean match; counts are last completed rpt"
                   else:
                       note = "latest run timed out; counts are last completed rpt"
           elif "reading standalone block DDC" in log_text:
               note = note or "standalone DDC"
           elif "reading standalone block implementation" in log_text:
               note = note or "standalone Verilog"
   
       return {
           "passing": passing,
           "failing": failing,
           "unverified": unverified,
           "status": status,
           "note": note,
       }

**逐段解释** ：

* 第 65-L67 行：如果使用 timeout report，note 初始为 ``graceful timeout status``。
* 第 68-L78 行：若 log 中出现 kill 或 Signal 15，脚本根据是否使用 timeout report
  把状态改成 ``INCONCLUSIVE`` 或 ``TIMEOUT``，并区分是否 clean match 后超时。
* 第 79-L82 行：如果 log 显示读取 standalone DDC 或 standalone Verilog，note
  记录 implementation 输入类型。
* 第 84-L90 行：返回字典统一包含 passing、failing、unverified、status 和 note。

**接口关系** ：

* **被调用** ：``main()`` 对每个 module label 调用 ``parse_module``。
* **调用** ：``_extract_int``、``Path.exists``、``Path.read_text``。
* **共享状态** ：读取 ``lec_<label>.rpt``、``lec_<label>_timeout_status.rpt``、
  ``lec_<label>.log``。

§5.3  ``main()`` — EXU 替代、TOTAL 状态和输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``main()`` 判断 EXU 子块报告是否齐全，选择模块列表，累计计数，生成
Markdown 表格并写出 summary。

**关键代码** （``syn/scripts/lec_summary.py:L93-L119``）：

.. code-block:: python

   def main():
       rows = []
       total_passing = total_failing = total_unverified = 0
   
       exu_decomposed = all((BUILD / f"lec_{label}.rpt").exists() for _module, label in EXU_SUBMODULES)
       modules = [BASE_MODULES[0]]
       if exu_decomposed:
           modules.extend(EXU_SUBMODULES)
       else:
           modules.append(("eh2_exu", "exu"))
       modules.extend(BASE_MODULES[1:])
   
       for module, label in modules:
           data = parse_module(label)
           if label in ("exu_alu", "exu_mul", "exu_div"):
               data["note"] = "EXU sub-block decomposition"
           rows.append((module, label, data))
           total_passing += int(data["passing"])
           total_failing += int(data["failing"])
           total_unverified += int(data["unverified"])
   
       if total_failing == 0 and total_unverified == 0:
           total_status = "PASS"
       elif total_failing < 30 and total_unverified == 0:
           total_status = "PARTIAL_PASS_LT30"
       else:
           total_status = "INCOMPLETE"

**逐段解释** ：

* 第 93-L95 行：初始化 rows 和 total counters。
* 第 97-L103 行：当 ``lec_exu_alu.rpt``、``lec_exu_mul.rpt``、
  ``lec_exu_div.rpt`` 全部存在时，summary 用 EXU 子块替代旧的单体 ``lec_exu``。
  否则 fallback 到 ``("eh2_exu", "exu")``。
* 第 105-L112 行：逐 module 解析 report。EXU 子块 note 被覆盖为
  ``EXU sub-block decomposition``，然后累计三类 compare point 数字。
* 第 114-L119 行：TOTAL 只有在 total failing 和 total unverified 都为 ``0`` 时
  标记 ``PASS``；否则按 ``PARTIAL_PASS_LT30`` 或 ``INCOMPLETE`` 分类。

**关键代码** （``syn/scripts/lec_summary.py:L121-L159``）：

.. code-block:: python

       lines = [
           "EH2 Block-level LEC Summary (R3-C)",
           f"Date: {_dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S %z')}",
           "",
           "| Module | Passing | Failing | Unverified | Status | Note |",
           "|---|---:|---:|---:|---|---|",
       ]
       for module, _label, data in rows:
           lines.append(
               "| {module} | {passing} | {failing} | {unverified} | {status} | {note} |".format(
                   module=module,
                   passing=data["passing"],
                   failing=data["failing"],
                   unverified=data["unverified"],
                   status=data["status"],
                   note=data["note"],
               )
           )

**逐段解释** ：

* 第 121-L127 行：summary header 包含标题、当前时间和 Markdown 表头。
* 第 128-L138 行：每个 module row 都从 ``rows`` 中的 data 字典格式化得到。

**关键代码** （``syn/scripts/lec_summary.py:L140-L159``）：

.. code-block:: python

       lines.extend([
           "| TOTAL | {passing} | {failing} | {unverified} | {status} | real tool output only |".format(
               passing=total_passing,
               failing=total_failing,
               unverified=total_unverified,
               status=total_status,
           ),
           "",
           "Notes:",
           "- Reports are parsed from syn/build/lec_blocklevel/lec_*.rpt.",
           "- When lec_exu_alu/mul/div reports exist, they replace the older monolithic lec_exu result in TOTAL.",
           "- If a newer lec_<module>_timeout_status.rpt exists, it is used to avoid stale failed counts after a graceful timeout run.",
           "- TIMEOUT means the latest log was killed by timeout; the numeric counts come from the last completed report for that module.",
           "- A clean-match timeout means matching completed with 0 unmatched compare points, but verification did not finish.",
           "- No set_dont_verify_points waiver is used by this summary.",
       ])
   
       OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
       print(OUT)
       print("\n".join(lines))

**逐段解释** ：

* 第 140-L146 行：TOTAL row 使用累计值，并把 note 固定为
  ``real tool output only``。
* 第 148-L154 行：Notes 明确说明 report 来源、EXU 子块替代、timeout report 处理、
  timeout 语义，以及 summary 不使用 ``set_dont_verify_points`` waiver。
* 第 157-L159 行：写出 :file:`syn/build/lec_summary.txt`，随后把输出路径和 summary
  内容打印到 stdout。

**接口关系** ：

* **被调用** ：脚本入口 ``if __name__ == "__main__": main()``。
* **调用** ：``parse_module``、``OUT.write_text``、``print``。
* **共享状态** ：读取 report 目录中存在的 EXU 子块报告决定是否替代单体 EXU。

§6  legacy top-level Formality 脚本边界
--------------------------------------------------------------------------------

§6.1  ``lec_run.tcl`` — 早期 top-level LEC 尝试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``lec_run.tcl`` 读取 top-level reference wrapper 和 synthesized netlist，
设置 top 为 ``eh2_veer``，执行一次 top-level ``match`` 和 ``verify``。该脚本不是
当前 sign-off closure path。

**关键代码** （``syn/scripts/lec_run.tcl:L28-L48``）：

.. code-block:: text

   # Reference (Golden RTL)
   puts "FM: Reading reference design..."
   read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
   puts "FM: Setting ref top..."
   set_top r:/WORK/eh2_veer
   
   # Implementation (synthesized netlist)
   puts "FM: Reading implementation netlist..."
   read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
   puts "FM: Setting impl top..."
   set_top i:/WORK/eh2_veer
   
   # Match and verify
   puts "FM: Starting match..."
   match
   puts "FM: Starting verify..."
   verify
   
   report_status > $BUILD_DIR/lec_report.txt
   puts "FM: === LEC Complete ==="
   exit 0

**逐段解释** ：

* 第 28-L32 行：reference design 来自 :file:`syn/build/eh2_dc_wrapper.sv`，top 为
  ``r:/WORK/eh2_veer``。
* 第 34-L38 行：implementation netlist 来自 :file:`syn/build/eh2_synth.v`，top 为
  ``i:/WORK/eh2_veer``。
* 第 40-L48 行：脚本运行 ``match``、``verify`` 并输出
  :file:`syn/build/lec_report.txt`。

**接口关系** ：

* **被调用** ：手工或旧流程可直接调用 ``fm_shell -f syn/scripts/lec_run.tcl``。
* **调用** ：Formality ``read_sverilog``、``read_verilog``、``set_top``、
  ``match``、``verify``。
* **共享状态** ：读取 :file:`syn/build/eh2_dc_wrapper.sv` 与
  :file:`syn/build/eh2_synth.v`。

§6.2  ``lec_svf.tcl`` 与 ``lec_user_match.tcl`` — top-level packed-port 诊断
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``lec_svf.tcl`` 在 top-level LEC 前加载 ``default.svf``；
``lec_user_match.tcl`` 列出 top-level packed-array reference port 到 flattened
implementation port 的显式 ``set_user_match`` 映射。它们记录了 ADR-0019 背景下的
诊断路径，但当前 closure path 由 :ref:`adr-0020` 的 block-level flow 接管。

**关键代码** （``syn/scripts/lec_svf.tcl:L23-L47``）：

.. code-block:: text

   # Load SVF before reading designs to guide matching
   puts "FM: Loading SVF..."
   set_svf /home/host/eh2-veri/default.svf
   
   # Reference (Golden RTL)
   puts "FM: Reading reference design..."
   read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
   puts "FM: Setting ref top..."
   set_top r:/WORK/eh2_veer
   
   # Implementation (synthesized netlist)
   puts "FM: Reading implementation netlist..."
   read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
   puts "FM: Setting impl top..."
   set_top i:/WORK/eh2_veer
   
   # Match and verify — SVF guides the matching
   puts "FM: Starting match (SVF-guided)..."
   match
   puts "FM: Starting verify..."
   verify
   
   report_status > $BUILD_DIR/lec_p0a_svf.log
   report_failing_points > $BUILD_DIR/lec_p0a_svf_failing.rpt
   puts "FM: === LEC (SVF) Complete ==="

**逐段解释** ：

* 第 23-L25 行：top-level 尝试在读取 reference/implementation 之前加载
  :file:`default.svf`。
* 第 27-L37 行：reference 和 implementation top 都是 ``eh2_veer``。
* 第 39-L47 行：脚本执行 SVF-guided ``match`` 和 ``verify``，并输出 status 和
  failing point report。

**关键代码** （``syn/scripts/lec_user_match.tcl:L1-L24``）：

.. code-block:: text

   # P0-A: Auto-generated set_user_match for 194 failing LEC compare points
   # Maps 2D packed-array Ref ports to 1D flattened Impl ports
   # Formula: linear(i,j) = (i-d1_min)*sub_w + (j-d2_min)
   
   suppress_message {VER-130 VER-250}
   
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][1] i:/WORK/eh2_veer/btb_rw_addr[0]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][2] i:/WORK/eh2_veer/btb_rw_addr[1]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][3] i:/WORK/eh2_veer/btb_rw_addr[2]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][4] i:/WORK/eh2_veer/btb_rw_addr[3]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][5] i:/WORK/eh2_veer/btb_rw_addr[4]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][6] i:/WORK/eh2_veer/btb_rw_addr[5]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][7] i:/WORK/eh2_veer/btb_rw_addr[6]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][8] i:/WORK/eh2_veer/btb_rw_addr[7]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][9] i:/WORK/eh2_veer/btb_rw_addr[8]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][1] i:/WORK/eh2_veer/btb_rw_addr[9]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][2] i:/WORK/eh2_veer/btb_rw_addr[10]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][3] i:/WORK/eh2_veer/btb_rw_addr[11]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][4] i:/WORK/eh2_veer/btb_rw_addr[12]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][5] i:/WORK/eh2_veer/btb_rw_addr[13]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][6] i:/WORK/eh2_veer/btb_rw_addr[14]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][7] i:/WORK/eh2_veer/btb_rw_addr[15]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][8] i:/WORK/eh2_veer/btb_rw_addr[16]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][9] i:/WORK/eh2_veer/btb_rw_addr[17]

**逐段解释** ：

* 第 1-L3 行：文件说明这些 ``set_user_match`` 由 194 个 failing compare points
  生成，并给出 flatten 公式。
* 第 5 行：抑制 ``VER-130`` 与 ``VER-250``。
* 第 7-L24 行：``btb_rw_addr`` 的 reference 二维索引按线性 index 映射到
  implementation 一维 vector。

**接口关系** ：

* **被调用** ：这些脚本可被手工 Formality run 载入或执行；当前
  :file:`syn/Makefile:block_lec` 不直接调用 ``lec_user_match.tcl``。
* **调用** ：Formality ``set_svf``、``set_user_match``、``match``、``verify``。
* **共享状态** ：读取 top-level :file:`syn/build/eh2_synth.v`，输出旧的 top-level
  report 文件。

§6.3  ADR-0019 到 ADR-0020 的结果边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：ADR 记录为什么当前章节必须描述 block-level LEC，而不能把早期 top-level
脚本写成当前 closure path。

**关键代码** （``docs/adr/0020-blocklevel-lec.md:L20-L29``）：

.. code-block:: text

   ## Decision
   
   Use the block-level flow as the R3-C LEC closure path for the Synopsys O-2018.06-SP1 packed-port limitation. The monolithic `eh2_exu` result is superseded by an EXU sub-block decomposition because the full EXU datapath is too hard for this Formality version to close as one unit.
   
   The implemented flow is intentionally non-waiving:
   
   - no `set_dont_verify_points` is used;
   - no report files are edited by hand;
   - block reports are parsed from real Formality output only;
   - DDC and valid DC-generated SVF files are emitted per block to preserve datapath guidance.

**逐段解释** ：

* 第 20-L22 行：ADR-0020 明确选择 block-level flow 作为 R3-C LEC closure path，
  并说明单体 ``eh2_exu`` 被 EXU 子块替代。
* 第 24-L29 行：flow 的约束是 non-waiving：不使用 ``set_dont_verify_points``，
  不手改报告，只解析真实 Formality 输出，并为每个 block 生成 DDC 和有效 SVF。

**关键代码** （``docs/adr/0020-blocklevel-lec.md:L46-L54``）：

.. code-block:: text

   The EXU decomposition closes the remaining issue:
   
   - `eh2_exu_alu_ctl`: 294 passing, 0 failing, 0 unverified, `Verification SUCCEEDED`;
   - `eh2_exu_mul_ctl`: 272 passing, 0 failing, 0 unverified, `Verification SUCCEEDED`;
   - `eh2_exu_div_ctl`: 181 passing, 0 failing, 0 unverified, `Verification SUCCEEDED`.
   
   The key flow fix was to generate a real block SVF in `dc_synth_block.tcl` with `set_svf` before synthesis. The earlier flow copied `default.svf`, which Formality rejected as invalid and ignored. Once a valid per-block SVF was loaded before reading designs, the multiplier `prod_e3_ff` cone closed.
   
   The latest parsed summary is 31635 passing, 0 failing, and 0 unverified compare points. The total uses the EXU sub-block reports in place of the older monolithic `eh2_exu` result.

**逐段解释** ：

* 第 46-L50 行：EXU 子块的 passing/failing/unverified 计数与 release 结果一致。
* 第 52 行：关键修复来自 :file:`syn/scripts/dc_synth_block.tcl` 生成真实 block
  SVF，并在读取设计前加载该 SVF。
* 第 54 行：最新 parsed summary 是 ``31635`` passing、``0`` failing、``0``
  unverified；TOTAL 使用 EXU 子块替代旧的单体 ``eh2_exu``。

**接口关系** ：

* **被调用** ：本章、:ref:`appendix_c_tools/syn_lec` 和 release note 引用
  ADR-0020 作为 closure path 依据。
* **调用** ：ADR 本身不调用脚本。
* **共享状态** ：ADR 的 non-waiving 约束必须与 ``lec_summary.py`` 的 note 和
  ``r3c_write_reports`` 的真实 report 输出保持一致。

§7  运行方式与排错边界
--------------------------------------------------------------------------------

§7.1  最小运行命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：使用 ``block_lec`` 生成当前 sign-off summary；不要把
``syn-full`` 或 Yosys ``lec`` target 写成当前 LEC sign-off 入口。

**关键代码** （``README.md:L369-L377``）：

.. code-block:: bash

   cd /home/host/eh2-veri
   make -C syn syn-full
   
   # or, from the repository root:
   make synth
   
   Run block-level LEC:
   
   make -C syn block_lec

**逐段解释** ：

* 第 369-L374 行：README 同时给出 full synthesis/LEC 入口和顶层 ``make synth``
  转发入口。
* 第 375-L377 行：block-level LEC 的直接命令是 ``make -C syn block_lec``。当前
  sign-off LEC summary 来自该命令对应的 R3-C path。

**接口关系** ：

* **被调用** ：开发者或 CI shell。
* **调用** ：GNU Make 进入 :file:`syn/Makefile:block_lec`。
* **共享状态** ：读取并写入 :file:`syn/build/lec_blocklevel/` 与
  :file:`syn/build/lec_summary.txt`。

§7.2  常见输出与判断
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：通过文件名判断当前 run 处于哪一阶段，并用 summary 的 TOTAL 行判断
是否可作为 sign-off 证据。

.. code-block:: text

   syn/build/lec_blocklevel/
      |
      |-- dc_<top>.log
      |-- synth/<top>.v
      |-- synth/<top>.ddc
      |-- synth/<top>.svf
      |-- lec_<label>.log
      |-- lec_<label>.rpt
      |-- lec_<label>_failing.rpt
      `-- lec_<label>_unverified.rpt
   
   syn/build/lec_summary.txt
      `-- TOTAL row: passing/failing/unverified/status

**逐段解释** ：

* ``dc_<top>.log`` 属于 DC 综合阶段；如果该文件存在但没有对应
  ``lec_<label>.rpt``，说明 Formality 阶段没有形成可汇总的 status report。
* ``synth/<top>.svf`` 是 ADR-0020 记录的关键输入之一；``lec_common.tcl`` 会按
  top 加载该 SVF 或 fallback。
* ``lec_<label>.rpt`` 是 ``lec_summary.py`` 的主要输入；summary 不解析
  ``lec_<label>_failing.rpt`` 来计算 passing/failing/unverified。
* ``lec_summary.txt`` 的 TOTAL 行只有在 failing 和 unverified 都为 ``0`` 时才会
  被脚本标记为 ``PASS``。

**接口关系** ：

* **被调用** ：人工检查、sign-off gate 或 release status 文档。
* **调用** ：无直接工具调用。
* **共享状态** ：必须与 ``lec_summary.py`` 的路径常量和 Makefile report 目录一致。

§8  参考资料
--------------------------------------------------------------------------------

* 关联 ADR：:ref:`adr-0019`、:ref:`adr-0020`。
* 关联章节：:ref:`synthesis_flow`、:ref:`appendix_c_tools/syn_lec`。
* 结果证据：2026-05-19 01:02 VCS 主线 sign-off 摘要、
  :file:`syn/build/lec_summary.txt`。
* 源文件绝对路径：
  :file:`/home/host/eh2-veri/syn/Makefile`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_dec.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_lsu.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_ifu.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu_alu.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu_mul.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu_div.tcl`、
  :file:`/home/host/eh2-veri/syn/scripts/lec_summary.py`。

§9  动手练习
--------------------------------------------------------------------------------

入门题（5 分钟）：

.. code-block:: bash

   cd /home/host/eh2-veri
   sed -n '1,40p' syn/build/lec_summary.txt

写下 TOTAL 行的 passing、failing、unverified 和 status。合格答案应为
``31635``、``0``、``0``、``PASS``。

进阶题（30 分钟）：

.. code-block:: bash

   rg -n "BLOCK_LEC_TOPS|BLOCK_LEC_LABELS|block_lec" syn/Makefile

解释为什么 EXU 在 summary 里拆成 ``alu``、``mul``、``div`` 三个 label，而不是一个
``eh2_exu`` 单体。

挑战题（2 小时）：

任选一个 ``syn/scripts/lec_blocklevel/lec_*.tcl``，列出 reference 读取、implementation
读取、SVF 载入、match/verify 和 report 输出 5 个步骤。参考 :ref:`appendix_c_tools/syn_lec`
的源码精读格式，不需要实际修改 Tcl。

§10  自检 5 问
--------------------------------------------------------------------------------

1. 当前 sign-off 的 LEC 证据为什么是 block-level，而不是 top-level？
2. ``dc_shell`` 与 ``fm_shell`` 在 LEC 流程中分别负责什么？
3. ``failing=0`` 与 ``unverified=0`` 为什么都必须满足？
4. ADR-0019 和 ADR-0020 的边界是什么？
5. LEC PASS 与 formal 46/46 PASS、coverage LINE 95.05% 的质量含义有什么不同？

§11  下一步
--------------------------------------------------------------------------------

完成本章后，建议回到 :ref:`signoff_flow` §7.3-§7.5，查看 ``signoff.py`` 如何读取
``lec_summary.txt`` 并把 syn stage 写入最终 JSON。若要看每个 Tcl 文件的逐段解释，
继续阅读 :ref:`appendix_c_tools/syn_lec`。
