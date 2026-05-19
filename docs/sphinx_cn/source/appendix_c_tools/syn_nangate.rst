.. _appendix_c_tools_syn_nangate:
.. _appendix_c_tools/syn_nangate:

Design Compiler / Nangate 综合脚本源码字典
==========================================

:status: draft
:source: syn/scripts/dc_synth.tcl
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`syn/` 下与 Synopsys Design Compiler（DC）和 Nangate SDC
约束相关的脚本。EH2 当前主线的开源 Yosys path 被 :ref:`adr-0013` 标记为
受限，默认可用综合入口是 :file:`syn/Makefile` 中的 ``syn-dc``，核心脚本是
:file:`syn/scripts/dc_synth.tcl`。

本章覆盖 5 个文件：

* :file:`syn/scripts/dc_synth.tcl`：top-level ``eh2_veer`` DC 综合。
* :file:`syn/scripts/dc_synth_block.tcl`：block-level LEC 的 per-block 综合。
* :file:`syn/scripts/dc_synth_keep2d.tcl`：packed-array keep-2D 诊断实验。
* :file:`syn/scripts/dc_elab_fixed.tcl` 与
  :file:`syn/scripts/dc_elaborate_flat.tcl`：早期 DC elaboration / flat Verilog
  尝试。
* :file:`syn/nangate/eh2_nangate.sdc`：Nangate 45nm 约束文件。

本章不修改 :file:`syn/build/` 下的生成报告，也不把旧实验脚本描述成
sign-off 入口。当前 LEC 闭环见 :doc:`syn_lec`。

§2  ``syn/Makefile:syn-dc`` 调用入口
------------------------------------------------------------------------------------------------------------------------

职责：``syn-dc`` 是商业综合入口。它检查 ``dc_shell``，创建 run 目录，然后执行
:file:`syn/scripts/dc_synth.tcl`。

关键代码（``syn/Makefile:L86-L97``）：

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

逐段解释：

* 第 87~92 行：当 ``dc_shell`` 在 ``PATH`` 中存在时，target 在
  :file:`syn/build/dc_run` 中执行 DC，并加载 :file:`syn/scripts/dc_synth.tcl`。
* 第 93~96 行：当 ``dc_shell`` 不存在时，target 打印错误，提示 SDC 路径
  :file:`syn/nangate/eh2_nangate.sdc`，然后以非零状态退出。
* 该 target 不直接调用 Nangate SDC。当前 :file:`dc_synth.tcl` 内部使用
  Synopsys ``class.db`` 与 ``gtech.db``；SDC 是约束资产和错误提示路径。

接口关系：

* 被调用：顶层 ``make syn_dc`` 或 ``make -C syn syn-dc``。
* 调用：``dc_shell -f syn/scripts/dc_synth.tcl``。
* 共享状态：``BUILD_DIR``、``SYN_DIR``、shell ``PATH``。

§3  ``dc_synth.tcl`` — top-level DC 综合
------------------------------------------------------------------------------------------------------------------------

职责：该脚本综合 ``eh2_veer``，输出 top-level netlist 和 area/timing/QoR 报告。
它使用 wrapper single-compilation-unit 路径，目标库是 Synopsys
``class.db``。

§3.1  library 与 HDL 解析设置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth.tcl:L1-L13``）：

.. code-block:: text

   # DC synthesis — RC3 v8: wrapper + class.db target library
   # v7: elaboration succeeded (379K cells GTECH), compile_ultra failed (gtech not mappable)
   # v8: use class.db (generic educational library) for technology mapping

   set TARGET_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
   set GTECH_DB  /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
   set_app_var target_library $TARGET_DB
   set_app_var link_library [list * $GTECH_DB $TARGET_DB]
   set_app_var hdlin_sverilog_std 2012
   set_app_var hdlin_keep_signal_name all_driving

   set BUILD_DIR /home/host/eh2-veri/syn/build
   file mkdir $BUILD_DIR

逐段解释：

* 第 1~3 行：注释记录脚本版本和技术库变化。v8 选择 ``class.db`` 做 technology
  mapping，原因是 GTECH elaboration 后 ``compile_ultra`` 不能完成映射。
* 第 5~8 行：``target_library`` 是 ``class.db``，``link_library`` 同时包含
  wildcard、``gtech.db`` 和 ``class.db``。
* 第 9 行：HDL 标准设置为 SystemVerilog 2012。该值与 :ref:`adr-0013` 中
  DC O-2018.06-SP1 的工具能力边界一致。
* 第 10 行：``hdlin_keep_signal_name all_driving`` 保留 driving signal 名称，用于
  后续 netlist 可读性和 Formality 调试。
* 第 12~13 行：所有主要输出都进入 :file:`syn/build`。

接口关系：

* 被调用：``syn-dc`` target 通过 ``dc_shell`` 调用。
* 调用：Design Compiler ``set_app_var``。
* 共享状态：Synopsys installation path 与 :file:`syn/build`。

§3.2  run 目录、message 抑制与 search path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth.tcl:L15-L32``）：

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
       /home/host/Cores-VeeR-EH2/snapshots/default \
       /home/host/Cores-VeeR-EH2/design/include \
       /home/host/Cores-VeeR-EH2/design/lib \
       [get_app_var search_path]]

逐段解释：

* 第 16~19 行：DC 工作目录固定为 :file:`syn/build/dc_run`，并尝试把
  ``hdlin_temporary_dir`` 指向该目录。
* 第 21~24 行：脚本抑制 LINT、VER、UID、ELAB 类已知噪声。这里是消息过滤，不是
  综合 waiver 或等价性 waiver。
* 第 26~32 行：search path 优先包含 run 目录、仓库内 :file:`syn/include`、
  EH2 snapshot、design include 和 design lib。

接口关系：

* 被调用：``dc_synth.tcl`` 初始化阶段。
* 调用：``file mkdir``、``cd``、``suppress_message``、``set_app_var``。
* 共享状态：``RUN_DIR`` 与 DC search path。

§3.3  analyze、elaborate 与 link
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth.tcl:L34-L49``）：

.. code-block:: text

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

逐段解释：

* 第 36~38 行：脚本只 analyze :file:`syn/build/eh2_dc_wrapper.sv`。这是 wrapper
  single-compilation-unit 路径，不是逐文件 analyze。
* 第 40~42 行：elaboration top 是 ``eh2_veer``，并打印当前 design。
* 第 44~46 行：``link`` 解析设计引用，``uniquify`` 复制共享实例以避免后续优化冲突。
* 第 48~49 行：``check_design`` 在 compile 前检查设计结构。

接口关系：

* 被调用：``dc_shell`` 执行脚本主体。
* 调用：DC ``analyze``、``elaborate``、``link``、``uniquify``、``check_design``。
* 共享状态：读取 :file:`syn/build/eh2_dc_wrapper.sv`。

§3.4  时序约束与 compile
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth.tcl:L51-L57``）：

.. code-block:: text

   create_clock -name clk -period 2.0 [get_ports clk]
   set_max_fanout 32 [current_design]
   set_max_transition 0.5 [current_design]

   puts "DC: Starting compile_ultra..."
   compile_ultra -no_autoungroup -no_boundary_optimization
   puts "DC: compile_ultra done"

逐段解释：

* 第 51 行：脚本在 ``clk`` 端口上创建 2.0 ns 时钟。这与
  :file:`syn/nangate/eh2_nangate.sdc` 中 10.0 ns open-source 约束不同。
* 第 52~53 行：对当前设计设置 max fanout 和 max transition。
* 第 55~57 行：综合命令是 ``compile_ultra``，并显式关闭 auto ungroup 和 boundary
  optimization。这有助于保留层次用于后续报告和 LEC。

接口关系：

* 被调用：设计检查通过后执行。
* 调用：DC timing constraint 与 compile 命令。
* 共享状态：当前 design。

§3.5  报告与 netlist 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth.tcl:L59-L69``）：

.. code-block:: text

   report_area -hierarchy > $BUILD_DIR/area_report.txt
   report_timing -max_paths 10 > $BUILD_DIR/timing_report.txt
   report_qor > $BUILD_DIR/qor_report.txt

   change_names -rules verilog -hierarchy
   write -format verilog -hierarchy -output $BUILD_DIR/eh2_synth.v
   # Note: write_svf not available in DC O-2018.06, use set_svf in Formality instead

   puts "DC: Netlist cells: [sizeof_collection [get_cells -hier *]]"
   puts "DC: === Synthesis Complete ==="
   exit 0

逐段解释：

* 第 59~61 行：脚本输出层次 area、最多 10 条 timing path 和 QoR 报告。
* 第 63~64 行：写 netlist 前使用 Verilog 命名规则重命名，并把层次 netlist 写到
  :file:`syn/build/eh2_synth.v`。
* 第 65 行：注释说明 DC O-2018.06 不支持 ``write_svf``。R3-C block flow 改用
  :file:`dc_synth_block.tcl` 中的 ``set_svf`` 生成 block SVF。
* 第 67~69 行：脚本打印 cell 数和完成信息，然后退出。

接口关系：

* 被调用：``compile_ultra`` 完成后。
* 调用：``report_area``、``report_timing``、``report_qor``、``write``。
* 共享状态：写 :file:`syn/build/area_report.txt`、
  :file:`syn/build/timing_report.txt`、:file:`syn/build/qor_report.txt`、
  :file:`syn/build/eh2_synth.v`。

§4  ``dc_synth_block.tcl`` — R3-C block-level synthesis
------------------------------------------------------------------------------------------------------------------------

职责：该脚本为 :doc:`syn_lec` 中的 R3-C block-level Formality LEC 生成 per-block
DDC、Verilog netlist 和 SVF。它不综合整个 ``eh2_veer``，而是由环境变量
``R3C_BLOCK_TOP`` 指定 block top。

§4.1  block top 必填检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth_block.tcl:L1-L15``）：

.. code-block:: text

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

逐段解释：

* 第 4~7 行：未设置 ``R3C_BLOCK_TOP`` 时直接报错并退出，避免生成无法归属的 block
  netlist。
* 第 9 行：``TOP`` 来自环境变量，这使 :file:`syn/Makefile:block_lec` 可以循环设置
  ``eh2_dec``、``eh2_lsu`` 等 block。
* 第 10~15 行：library 设置与 top-level DC 类似，但 signal name 保留策略是
  ``all_ports``，更贴合 block-level LEC 的端口匹配需求。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 DC block loop。
* 调用：DC ``set_app_var``。
* 共享状态：环境变量 ``R3C_BLOCK_TOP``。

§4.2  block 目录与 SVF 生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth_block.tcl:L17-L30``）：

.. code-block:: text

   set BUILD_DIR /home/host/eh2-veri/syn/build
   set BLOCK_DIR $BUILD_DIR/lec_blocklevel/synth
   file mkdir $BLOCK_DIR

   # Redirect DC working files to a dedicated build subdir.
   set RUN_DIR $BUILD_DIR/lec_blocklevel/run/dc/$TOP
   file mkdir $RUN_DIR
   cd $RUN_DIR
   catch {set_app_var hdlin_temporary_dir $RUN_DIR}

   set BLOCK_SVF $BLOCK_DIR/${TOP}.svf
   file delete -force $BLOCK_SVF
   set_svf $BLOCK_SVF

逐段解释：

* 第 17~19 行：block netlist、DDC、SVF 和报告输出到
  :file:`syn/build/lec_blocklevel/synth`。
* 第 22~25 行：每个 block 有独立 DC run 目录
  :file:`syn/build/lec_blocklevel/run/dc/<TOP>`。
* 第 27~29 行：脚本删除旧 SVF，再调用 ``set_svf`` 开始记录新的 block SVF。
  :ref:`adr-0020` 明确指出这是 R3-C 闭合 multiplier cone 的关键修复。

接口关系：

* 被调用：block 初始化阶段。
* 调用：``file delete``、``set_svf``。
* 共享状态：``BLOCK_SVF`` 路径。

§4.3  block analyze、elaborate 与 compile 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth_block.tcl:L45-L72``）：

.. code-block:: text

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
   } else {
       puts "DC: No top-level clk port found for $TOP; continuing without a clock constraint"
   }

逐段解释：

* 第 45~50 行：block flow 仍 analyze 同一个
  :file:`syn/build/eh2_dc_wrapper.sv`，但 elaborate 的 top 是 ``$TOP``。
* 第 52~55 行：当 ``R3C_VERIFY_PRIORITY=1`` 时，脚本把 verification priority
  设置为 high，用于 LEC-oriented datapath preservation。
* 第 57~62 行：脚本只在 block 有 ``clk`` 端口时创建 2.0 ns clock；没有 clock
  时打印提示并继续。

关键代码（``syn/scripts/dc_synth_block.tcl:L64-L72``）：

.. code-block:: text

   set_max_fanout 32 [current_design]
   set_max_transition 0.5 [current_design]

   if {[info exists env(R3C_SIMPLE_COMPILE)] && $env(R3C_SIMPLE_COMPILE) eq "1"} {
       puts "DC: Using simple compile for LEC-oriented block netlist"
       compile -map_effort medium
   } else {
       compile_ultra -no_autoungroup -no_boundary_optimization
   }

逐段解释：

* 第 64~65 行：block flow 与 top-level flow 一样设置 fanout 和 transition。
* 第 67~69 行：当 ``R3C_SIMPLE_COMPILE=1`` 时使用 ``compile -map_effort medium``。
  :file:`syn/Makefile:block_lec` 对 ``eh2_ifu`` 设置该变量。
* 第 70~72 行：默认路径仍使用 ``compile_ultra`` 并关闭 auto ungroup 和 boundary
  optimization。

接口关系：

* 被调用：block source 读入之后。
* 调用：DC ``analyze``、``elaborate``、``set_verification_priority``、``compile``。
* 共享状态：``R3C_VERIFY_PRIORITY``、``R3C_SIMPLE_COMPILE``。

§4.4  block 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth_block.tcl:L74-L87``）：

.. code-block:: text

   report_area -hierarchy > $BLOCK_DIR/${TOP}_area.rpt
   report_timing -max_paths 10 > $BLOCK_DIR/${TOP}_timing.rpt
   report_qor > $BLOCK_DIR/${TOP}_qor.rpt

   change_names -rules verilog -hierarchy
   write -format ddc -hierarchy -output $BLOCK_DIR/${TOP}.ddc
   write -format verilog -hierarchy -output $BLOCK_DIR/${TOP}.v
   set_svf -off

   puts "DC: Wrote $BLOCK_DIR/${TOP}.v"
   puts "DC: Wrote $BLOCK_DIR/${TOP}.ddc"
   puts "DC: Wrote $BLOCK_SVF"
   puts "DC: === R3-C block synthesis complete: $TOP ==="
   exit 0

逐段解释：

* 第 74~76 行：每个 block 输出 area、timing 和 QoR 报告。
* 第 78~80 行：脚本输出 DDC 和 Verilog 两种 implementation 格式。
* 第 81 行：block SVF 记录在输出完成后关闭。
* 第 83~87 行：脚本打印 Verilog、DDC、SVF 三类输出路径，并以 0 退出。

接口关系：

* 被调用：block compile 后。
* 调用：DC report、write、``set_svf -off``。
* 共享状态：写 :file:`syn/build/lec_blocklevel/synth/<TOP>.*`。

§5  ``dc_synth_keep2d.tcl`` — packed-array 诊断实验
------------------------------------------------------------------------------------------------------------------------

职责：该脚本是非侵入式 probe，用于探索 DC/Formality 对 2D packed array
的处理。它不是当前 sign-off 的默认综合入口。

§5.1  best-effort option 设置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth_keep2d.tcl:L1-L20``）：

.. code-block:: text

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

   proc try_set_var {name value} {
       if {[catch {set $name $value} msg]} {
           puts "DC: keep2d variable unsupported: $name = $value ($msg)"
           return 0
       }
       puts "DC: keep2d variable set: $name = $value"
       return 1
   }

逐段解释：

* 第 1~2 行：脚本用途是 packed-array handling probe。
* 第 4~11 行：``try_set_app_var`` 尝试设置 DC app var；不支持时捕获异常并返回 0。
* 第 13~20 行：``try_set_var`` 对普通 Tcl 变量执行相同的 best-effort 设置。
* 这两个过程说明 keep-2D 实验不假设所有 DC 选项都存在。

接口关系：

* 被调用：脚本内部 option 设置阶段。
* 调用：``set_app_var``、Tcl ``set``。
* 共享状态：无固定输出，主要打印支持情况。

§5.2  keep-2D 选项和输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_synth_keep2d.tcl:L29-L34``）：

.. code-block:: text

   try_set_var verilogout_no_tri true
   try_set_var verilogout_show_unconnected_pins true
   try_set_app_var hdlin_unresolved_modules black_box
   try_set_app_var change_names_dont_change_packed_arrays true
   try_set_app_var hdlin_preserve_packed_arrays true

逐段解释：

* 第 29~30 行：输出 Verilog 时尝试关闭 tri 表达并显示未连接 pin。
* 第 31 行：未解析 module 尝试按 black box 处理。
* 第 32~33 行：关键实验选项是不要改 packed arrays 名称、保留 packed arrays。
  脚本通过 ``try_set_app_var`` 捕获不支持情况。

关键代码（``syn/scripts/dc_synth_keep2d.tcl:L64-L77``）：

.. code-block:: text

   puts "DC: Starting compile_ultra..."
   compile_ultra -no_autoungroup -no_boundary_optimization
   puts "DC: compile_ultra done"

   report_area -hierarchy > $BUILD_DIR/r3c_keep2d_area_report.txt
   report_timing -max_paths 10 > $BUILD_DIR/r3c_keep2d_timing_report.txt
   report_qor > $BUILD_DIR/r3c_keep2d_qor_report.txt

   change_names -rules verilog -hierarchy
   write -format verilog -hierarchy -output $BUILD_DIR/eh2_synth_keep2d.v

   puts "DC: Netlist cells: [sizeof_collection [get_cells -hier *]]"
   puts "DC: === R3-C keep2d synthesis probe complete ==="

逐段解释：

* 第 64~66 行：实验仍使用 ``compile_ultra``。
* 第 68~70 行：报告文件以 ``r3c_keep2d`` 前缀写出，避免覆盖主综合报告。
* 第 72~73 行：实验 netlist 输出为 :file:`syn/build/eh2_synth_keep2d.v`。
* 第 75~76 行：脚本打印 cell 数与完成信息。

接口关系：

* 被调用：手工 R3-C packed-array 诊断。
* 调用：DC option、compile、report、write。
* 共享状态：写 :file:`syn/build/eh2_synth_keep2d.v` 与 ``r3c_keep2d_*`` 报告。

§6  早期 elaboration 脚本
------------------------------------------------------------------------------------------------------------------------

职责：:file:`dc_elaborate_flat.tcl` 与 :file:`dc_elab_fixed.tcl` 是早期把 EH2
elaborate 成 flat Verilog 的尝试。它们有助于理解 :ref:`adr-0013` 中的工具链
演进，但不是当前默认 ``syn-dc`` 入口。

§6.1  ``dc_elaborate_flat.tcl`` — 手工列 RTL 文件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_elaborate_flat.tcl:L21-L33``）：

.. code-block:: text

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

逐段解释：

* 第 21 行：脚本进入逐文件 analyze 模式。
* 第 23~25 行：先 analyze type definition 和 include definition。
* 第 27~32 行：随后 analyze lib 文件，包括 behavioral lib、EH2 lib、memory lib 和
  AXI/AHB 转换模块。
* 该脚本后续继续逐个列出 IFU、DEC、EXU、LSU、DBG、DMI 和 top-level 文件。

关键代码（``syn/scripts/dc_elaborate_flat.tcl:L91-L104``）：

.. code-block:: text

   puts "DC: All files analyzed. Elaborating eh2_veer..."

   elaborate eh2_veer

   puts "DC: Current design: [current_design]"
   puts "DC: Elaboration complete. Writing flat Verilog..."

   write -format verilog -hierarchy -output /home/host/eh2-veri/syn/build/eh2_golden_flat.v

   puts "DC: Reporting area..."
   report_area > /home/host/eh2-veri/syn/build/dc_area_report.txt

逐段解释：

* 第 91~93 行：逐文件 analyze 后 elaborate ``eh2_veer``。
* 第 95~98 行：把层次 Verilog 写到 :file:`syn/build/eh2_golden_flat.v`。
* 第 100~101 行：输出 area report 到 :file:`syn/build/dc_area_report.txt`。

接口关系：

* 被调用：早期手工 DC elaboration 调试。
* 调用：逐文件 ``analyze``、``elaborate``、``write``。
* 共享状态：读取上游 :file:`/home/host/Cores-VeeR-EH2/design`。

§6.2  ``dc_elab_fixed.tcl`` — 文件列表驱动修正版
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/dc_elab_fixed.tcl:L30-L58``）：

.. code-block:: text

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
   set analyzed 0
   set failed 0
   foreach f $rtl_files {
       if {[catch {analyze -format sverilog -work WORK $f} err]} {
           puts "  FAILED: $f"

逐段解释：

* 第 31~39 行：脚本从 :file:`syn/build/eh2_rtl_dc.lst` 读取 RTL 文件列表，跳过空行
  和以 ``#`` 开头的注释行。
* 第 41~44 行：初始化 analyze 计数器，并遍历文件列表。
* 第 45 行：每个文件用 ``catch`` 包裹 ``analyze``，使脚本能统计失败文件数量。
* 第 52~57 行（未在片段中全部展示）：每 10 个已分析文件打印进度；若存在失败，
  打印 warning 并继续尝试 elaboration。

关键代码（``syn/scripts/dc_elab_fixed.tcl:L60-L72``）：

.. code-block:: text

   puts "DC: Elaborating eh2_veer..."
   if {[catch {elaborate eh2_veer -work WORK -parameters ""} err]} {
       puts "DC: Elaboration FAILED: $err"
       exit 1
   }

   puts "DC: Elaboration complete. Current design: [current_design]"

   puts "DC: Writing flat Verilog..."
   write -format verilog -output /home/host/eh2-veri/syn/build/eh2_golden_flat.v

   puts "DC: Done. Checking output..."

逐段解释：

* 第 60~64 行：elaboration 用 ``catch`` 包裹，失败时打印错误并退出。
* 第 66~69 行：elaboration 成功后写 :file:`syn/build/eh2_golden_flat.v`。
* 该脚本仍是 flat Verilog 调试路径，不生成当前 sign-off LEC summary。

接口关系：

* 被调用：早期修复 include path 后的 DC elaboration 调试。
* 调用：``open``、``gets``、``analyze``、``elaborate``、``write``。
* 共享状态：读取 :file:`syn/build/eh2_rtl_dc.lst`。

§7  ``eh2_nangate.sdc`` 约束文件
------------------------------------------------------------------------------------------------------------------------

职责：该 SDC 给出 Nangate 45nm / timing-driven flow 可用的时钟、reset、
input delay、output delay、load、false path 和 transition 约束。

§7.1  clock 与 reset 约束
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/nangate/eh2_nangate.sdc:L1-L24``）：

.. code-block:: text

   # ─── EH2 Nangate 45nm SDC Constraints (issue 62) ───────────────────────────
   # Clock period: 10 ns (100 MHz target for open-source flow).
   # If targeting Nangate 45nm with a commercial tool (DC/Genus), lower to 2-5 ns.
   #
   # This SDC is referenced by the synthesis Makefile for timing-driven flows.
   # For yosys open-source flow, constraints are applied via liberty+ABC.

   # ─── Clock definition ──────────────────────────────────────────────────────
   set CLK_NAME    clk
   set CLK_PERIOD  10.0
   set CLK_UNCERT  0.50
   ...
   create_clock -name $CLK_NAME -period $CLK_PERIOD $clk_port
   set_clock_uncertainty $CLK_UNCERT [get_clocks $CLK_NAME]
   ...
   set RST_NAME rst_l
   if {[sizeof_collection [get_ports -quiet $RST_NAME]] > 0} {
     set_input_delay 0.0 -clock $CLK_NAME [get_ports $RST_NAME]
     set_false_path -from [get_ports $RST_NAME]
   }

逐段解释：

* 第 1~6 行：注释说明该文件面向 Nangate 45nm，默认 10 ns / 100 MHz；商业工具
  目标可降到 2~5 ns。
* 第 9~17 行：clock 名称是 ``clk``，周期是 ``10.0``，uncertainty 是 ``0.50``。
* 第 20~24 行：如果 ``rst_l`` 端口存在，脚本设置 0 input delay，并把 reset
  标为 false path。

接口关系：

* 被调用：timing-driven flow 或用户手工 source。
* 调用：SDC ``create_clock``、``set_clock_uncertainty``、``set_false_path``。
* 共享状态：设计端口 ``clk``、``rst_l``。

§7.2  debug reset、IO delay 和 load
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/nangate/eh2_nangate.sdc:L26-L58``）：

.. code-block:: text

   # ─── Debug reset ───────────────────────────────────────────────────────────
   set DBG_RST_NAME dbg_rst_l
   if {[sizeof_collection [get_ports -quiet $DBG_RST_NAME]] > 0} {
     set_input_delay 0.0 -clock $CLK_NAME [get_ports $DBG_RST_NAME]
     set_false_path -from [get_ports $DBG_RST_NAME]
   }

   # ─── Input delays (non-clock, non-reset primary inputs) ────────────────────
   # Apply 2.0 ns input delay to all remaining inputs
   set all_in  [all_inputs]
   set clk_in  [get_ports $CLK_NAME]
   set skip_list [list $clk_in]
   ...
   set other_in [remove_from_collection $all_in $skip_list]
   if {[sizeof_collection $other_in] > 0} {
     set_input_delay 2.0 -clock $CLK_NAME $other_in
   }

逐段解释：

* 第 27~31 行：``dbg_rst_l`` 存在时采用与 ``rst_l`` 相同的处理：0 input delay
  和 false path。
* 第 35~44 行：脚本先取得所有输入，再把 ``clk``、``rst_l`` 和 ``dbg_rst_l`` 放入
  skip list。
* 第 44~47 行：除 clock/reset/debug reset 之外的输入统一设置 2.0 ns input delay。

关键代码（``syn/nangate/eh2_nangate.sdc:L49-L71``）：

.. code-block:: text

   # ─── Output delays ─────────────────────────────────────────────────────────
   # 2.5 ns output delay from all outputs
   set all_out [all_outputs]
   if {[sizeof_collection $all_out] > 0} {
     set_output_delay 2.5 -clock $CLK_NAME $all_out
   }

   # ─── Output load ───────────────────────────────────────────────────────────
   set_load 0.05 [all_outputs]
   ...
   set NMI_NAME nmi_int
   if {[sizeof_collection [get_ports -quiet $NMI_NAME]] > 0} {
     set_false_path -from [get_ports $NMI_NAME]
   }
   ...
   set_input_transition 0.2 $other_in

逐段解释：

* 第 51~54 行：所有输出设置 2.5 ns output delay。
* 第 57 行：所有输出 load 设置为 ``0.05``。
* 第 61~64 行：如果 ``nmi_int`` 端口存在，则从该端口设置 false path。
* 第 67 行：其它输入设置 0.2 input transition。
* 第 69~71 行：operating condition 只以注释形式保留，没有实际执行
  ``set_operating_conditions``。

接口关系：

* 被调用：SDC source 时执行。
* 调用：``set_output_delay``、``set_load``、``set_false_path``、
  ``set_input_transition``。
* 共享状态：``other_in``、``all_outputs``、``nmi_int``。

§8  与 release 证据的边界
------------------------------------------------------------------------------------------------------------------------

``dc_synth.tcl`` 输出 :file:`syn/build/eh2_synth.v` 和综合报告；LEC 的
sign-off total 由 :file:`dc_synth_block.tcl` 生成 block implementation 后，
再由 :file:`syn/scripts/lec_blocklevel/*.tcl` 和 :file:`syn/scripts/lec_summary.py`
汇总。二者不能混为一个脚本。

:ref:`adr-0013` 的 Decision 指定默认综合流程为 ``make syn-dc``，工具为
Design Compiler ``O-2018.06-SP1``。同一个 ADR 还说明 ``class.db`` 是 educational
library；生产流片目标需要替换为 foundry ``.db``。本章只描述当前仓库脚本行为，
不声称它完成了 foundry PDK sign-off。

§9  参考资料
------------------------------------------------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0013` — 综合工具链决策：Yosys open-source path 与 Design Compiler
  path。
* :ref:`adr-0020` — R3-C block-level LEC closure path，说明 block SVF 的作用。

关联章节：

* :doc:`../06_flows/synthesis_flow` — 综合流程说明。
* :doc:`syn_yosys` — Yosys path 的失败哨兵。
* :doc:`syn_lec` — Formality LEC 与 block-level summary。

源文件绝对路径：

* :file:`/home/host/eh2-veri/syn/Makefile`
* :file:`/home/host/eh2-veri/syn/scripts/dc_synth.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/dc_synth_block.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/dc_synth_keep2d.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/dc_elab_fixed.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/dc_elaborate_flat.tcl`
* :file:`/home/host/eh2-veri/syn/nangate/eh2_nangate.sdc`
* :file:`/home/host/eh2-veri/docs/adr/0013-synthesis-toolchain.md`
* :file:`/home/host/eh2-veri/docs/adr/0020-blocklevel-lec.md`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？
