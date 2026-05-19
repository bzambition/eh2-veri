.. _formal_flow:
.. _06_flows/formal_flow:

形式验证流程 — 详细参考
================================================================================

:status: draft
:source: dv/formal/Makefile; dv/formal/ifv_filelist.f; dv/formal/eh2_veer_sva.sv; dv/formal/eh2_formal_top.sv; dv/formal/scripts/ifv_prove.tcl; dv/formal/scripts/ifv_cex_dump.tcl; dv/formal/spec/sail_setup.sh; dv/formal/spec/sail_trace_check.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
--------------------------------------------------------------------------------

读懂本章前，请先确认：

* :ref:`glossary_pretest` — 知道 formal stage 是 sign-off 的 9 个 stage 之一；
* :ref:`signoff_flow` — 知道 ``collect_formal_stage()`` 如何读取 formal summary；
* :ref:`pipeline` — 能把 IFU/DEC/EXU/LSU/PIC/DBG 等断言对象放回 EH2 微架构；
* 基础 SVA（SystemVerilog Assertions）语法：``property``、``assert property``、
  ``assume property``、``disable iff``；
* 基础 formal 概念：proof、counterexample (CEX)、constraint、bounded proof。

形式验证不是替代仿真，而是用数学搜索覆盖“随机测试很难稳定打到”的安全性质。
EH2 当前 formal 证据是 ``46/46`` PASS，主入口是 ``make -C dv/formal ifv``，
工具路径以 Cadence IFV 为准；Symbiyosys/Sail 辅助路径用于补充检查和教学解释。

学完本章你应该能够：

1. 解释 ``ifv_filelist.f`` 为什么是 formal 真实入口，而不是文档里另写一个 top。
2. 找到 ``eh2_veer_sva.sv`` 中的 bind/assume/assert 关系。
3. 跑 ``make -C dv/formal ifv`` 后知道检查 ``build/ifv_run.log`` 与
   ``build/ifv_summary.txt``。
4. 看懂 CEX dump 的用途：定位失败 property 的输入序列，而不是直接修 RTL。
5. 说明 formal 46/46 PASS 与 simulation coverage 数字是两个不同质量维度。

§1  流程边界
--------------------------------------------------------------------------------

本章描述 :file:`dv/formal/` 的执行流程：从 Makefile 入口到 IFV 编译、证明、
summary 提取、CEX 诊断和 Sail 辅助检查。SVA 源码逐条解释见
:ref:`appendix_c_tools_formal_infra` 和 :ref:`appendix_c_tools_formal_properties`。

当前流程的实际入口由源码决定：

.. code-block:: text

   make -C dv/formal ifv
      |
      |-- ifv -f ifv_filelist.f +top+eh2_veer +loop_unroll_size+2048 -c
      |     |
      |     |-- ifv_bootstrap.sv
      |     |-- EH2 RTL design files
      |     `-- eh2_veer_sva.sv
      |
      |-- ifv -r +tcl+scripts/ifv_prove.tcl
      |     |
      |     |-- clock -add clk -initial 0 -period 2 -width 1
      |     |-- assertion -add -specification
      |     |-- prove
      |     `-- assertion -summary
      |
      `-- grep "Assertion Summary" build/ifv_run.log

**逐段解释** ：

* Makefile 的 ``IFV_TOP`` 当前是 ``eh2_veer``，不是 ``eh2_formal_top``。
  因此 IFV 主路径是 full core RTL 加 ``eh2_veer_sva.sv`` bind 模块。
* ``eh2_formal_top.sv`` 仍保存在源码树中，描述 full-core formal testbench，
  但当前 ``ifv_filelist.f`` 没有列入该文件。流程文档必须以 filelist 为准。
* 主证明脚本使用 IFV 15.20 可用的 legacy FormalVerifier 命令；源码注释明确
  没有使用 newer ``check_formal``、``report_cex`` 或 ``write_vcd`` 命令。

**结果口径** ：

README 和项目状态文档记录当前 formal evidence 为
``dv/formal/build/ifv_final.log``，summary 数字为 formal 46/46：

.. code-block:: text

   Assertion Summary:
     Total                  :  46
     Pass                   :  46
     Not_Run                :   0

**接口关系** ：

* **被调用** ：顶层 Makefile、sign-off collector 或开发者命令行进入
  ``dv/formal`` 后调用 ``make ifv``。
* **调用** ：``Makefile`` 调用 ``ifv``、``ifv_filelist.f``、
  ``scripts/ifv_prove.tcl`` 和 shell ``grep``。
* **共享状态** ：主输出写入 ``dv/formal/build/ifv_elab.log``、
  ``dv/formal/build/ifv_run.log`` 和 ``dv/formal/build/ifv_summary.txt``。

§2  Makefile 入口
--------------------------------------------------------------------------------

§2.1  变量与 IFV 编译选项
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``dv/formal/Makefile`` 定义 IFV 命令、filelist、脚本目录、输出目录、
top 名称和 IFV 15.20 编译选项。

**关键代码** （``dv/formal/Makefile:L1-L16``）：

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
   
   .DEFAULT_GOAL := ifv

**逐段解释** ：

* 第 3 行：Makefile 使用 ``/bin/bash`` 作为 shell，后续 recipe 的 shell 行为按
  Bash 执行。
* 第 5-L8 行：``BUILD_DIR`` 是 ``build``；``FILELIST`` 是
  ``ifv_filelist.f``；``SCRIPTS`` 是 ``scripts``；``IFV`` 默认命令名是 ``ifv``。
* 第 9 行：``IFV_TOP`` 固定为 ``eh2_veer``。
* 第 11-L14 行：源码注释说明 IFV 15.20 对 EH2 IFU/PIC generated muxes 需要较高
  loop unroll limit；Makefile 因此把 ``+loop_unroll_size+2048`` 加入
  ``IFV_COMPILE_OPTS``。
* 第 16 行：默认目标是 ``ifv``。在 ``dv/formal`` 目录直接运行 ``make`` 时，
  会进入主 IFV 流程。

**接口关系** ：

* **被调用** ：``make -C dv/formal``、``make -C dv/formal ifv``。
* **调用** ：后续 target 使用 ``$(IFV)``、``$(FILELIST)`` 和 ``$(SCRIPTS)``。
* **共享状态** ：所有 target 默认读写 ``dv/formal/build``。

§2.2  ``ifv`` 与 ``formal`` target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``ifv`` target 创建 build 目录，先运行 IFV compile/elaboration，再运行
proof Tcl，最后从 run log 提取 assertion summary。``formal`` target 只是
``ifv`` 的别名。

**关键代码** （``dv/formal/Makefile:L18-L27``）：

.. code-block:: makefile

   .PHONY: ifv formal ifv_clean formal_clean ifv_count formal_count ifv_cex
   
   ifv:
   	@mkdir -p $(BUILD_DIR)
   	$(IFV) -f $(FILELIST) $(IFV_COMPILE_OPTS) -c -l $(BUILD_DIR)/ifv_elab.log
   	$(IFV) -r +tcl+$(SCRIPTS)/ifv_prove.tcl -l $(BUILD_DIR)/ifv_run.log
   	@grep -A 6 "Assertion Summary" $(BUILD_DIR)/ifv_run.log > $(BUILD_DIR)/ifv_summary.txt || true
   	@cat $(BUILD_DIR)/ifv_summary.txt
   
   formal: ifv

**逐段解释** ：

* 第 18 行：所有 formal 操作入口被声明为 phony，避免同名文件影响 target 执行。
* 第 20-L22 行：``ifv`` 先创建 ``build``，再执行
  ``ifv -f ifv_filelist.f +top+eh2_veer +loop_unroll_size+2048 -c``，日志写入
  ``build/ifv_elab.log``。
* 第 23 行：第二次 IFV 调用使用 ``-r +tcl+scripts/ifv_prove.tcl`` 进入证明阶段，
  日志写入 ``build/ifv_run.log``。
* 第 24-L25 行：Makefile 从 ``ifv_run.log`` 中提取 ``Assertion Summary`` 后 6 行
  到 ``ifv_summary.txt`` 并打印。``|| true`` 只包住 grep，表示 summary 未命中时
  该 shell 命令不会让 Makefile 立即失败。
* 第 27 行：``formal`` 依赖 ``ifv``，没有额外 recipe。

**接口关系** ：

* **被调用** ：sign-off 或开发者执行 formal 主流程。
* **调用** ：IFV compile、IFV run、``grep`` 和 ``cat``。
* **共享状态** ：读 ``ifv_filelist.f`` 和 ``scripts/ifv_prove.tcl``，写
  ``build/ifv_elab.log``、``build/ifv_run.log``、``build/ifv_summary.txt``。

§2.3  计数、CEX 与清理 target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：辅助 target 分别统计 property 数、调用 CEX 诊断 Tcl、清理 IFV
产物。

**关键代码** （``dv/formal/Makefile:L29-L52``）：

.. code-block:: makefile

   ifv_cex:
   	@mkdir -p $(BUILD_DIR)
   	$(IFV) -r +tcl+$(SCRIPTS)/ifv_cex_dump.tcl -l $(BUILD_DIR)/ifv_cex_run.log
   	@ls $(BUILD_DIR)/cex_*.txt 2>/dev/null | wc -l
   
   ifv_count:
   	@echo "=== IFV Property Count ==="
   	@echo "SVA files: $$(ls *.sv properties/*.sv 2>/dev/null | wc -l)"
   	@asserts=$$(grep -Rho '^[[:space:]]*a_[A-Za-z0-9_]*:' *.sv properties/*.sv 2>/dev/null | wc -l); \
   	covers=$$(grep -Rho '^[[:space:]]*c_[A-Za-z0-9_]*:' *.sv properties/*.sv 2>/dev/null | wc -l); \
   	echo "Assertions: $$asserts"; \
   	echo "Covers:     $$covers"; \
   	echo "Total:      $$((asserts + covers))"

**逐段解释** ：

* 第 29-L32 行：``ifv_cex`` 创建 ``build``，运行
  ``scripts/ifv_cex_dump.tcl``，日志写入 ``build/ifv_cex_run.log``，随后统计
  ``build/cex_*.txt`` 文件数量。
* 第 34-L41 行：``ifv_count`` 使用 ``ls`` 和 ``grep`` 扫描当前目录 ``*.sv`` 与
  ``properties/*.sv``。它统计以 ``a_`` 开头的 label 和以 ``c_`` 开头的 label，
  再输出 Assertions、Covers 和 Total。

**关键代码** （``dv/formal/Makefile:L43-L52``）：

.. code-block:: makefile

   formal_count: ifv_count
   
   ifv_clean:
   	@echo "=== Cleaning IFV artifacts ==="
   	@rm -f $(BUILD_DIR)/ifv_*.log $(BUILD_DIR)/ifv_*.tcl $(BUILD_DIR)/ifv_*.input
   	@rm -f $(BUILD_DIR)/ifv_summary.txt $(BUILD_DIR)/cex_*.txt
   	@rm -rf $(BUILD_DIR)/ifv_work .ifv
   	@echo "=== Clean complete ==="
   
   formal_clean: ifv_clean

**逐段解释** ：

* 第 43 行：``formal_count`` 是 ``ifv_count`` 的别名。
* 第 45-L50 行：``ifv_clean`` 删除 IFV log、Tcl/input 中间文件、summary、CEX 文本、
  IFV work directory 和 ``.ifv`` 目录。
* 第 52 行：``formal_clean`` 是 ``ifv_clean`` 的别名。

**接口关系** ：

* **被调用** ：开发者诊断、计数或清理 formal 工作区时调用。
* **调用** ：``ifv_cex`` 调用 ``scripts/ifv_cex_dump.tcl``；``ifv_count`` 调用
  shell ``grep``；``ifv_clean`` 调用 ``rm``。
* **共享状态** ：读写 ``build``，但不修改源文件。

§3  IFV filelist
--------------------------------------------------------------------------------

§3.1  defines、include path 与 bootstrap
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``ifv_filelist.f`` 把 IFV 编译需要的宏、include path、bootstrap、
RTL 文件和 SVA bind 文件列给 IFV。

**关键代码** （``dv/formal/ifv_filelist.f:L1-L15``）：

.. code-block:: text

   // IFV Filelist — EH2 Core + Formal Properties
   // RC5 (2026-05-09): Fixed bootstrap + formal_top for IFV 15.20 compatibility.
   // eh2_param.vh moved inside modules (was at file scope, causing SVNOTY).
   
   +define+FORMAL
   +define+RV_BUILD_AXI4
   +incdir+/home/host/Cores-VeeR-EH2/snapshots/default
   +incdir+/home/host/Cores-VeeR-EH2/design/include
   +incdir+/home/host/Cores-VeeR-EH2/design/lib
   +incdir+/home/host/eh2-veri/dv/formal/properties
   +incdir+/home/host/eh2-veri/dv/formal
   
   // Bootstrap: macro and type-definition files for $unit scope
   /home/host/eh2-veri/dv/formal/ifv_bootstrap.sv

**逐段解释** ：

* 第 1-L3 行：文件注释说明这是 EH2 core 和 formal properties 的 IFV filelist，
  并记录 RC5 兼容性修正。
* 第 5-L6 行：定义 ``FORMAL`` 和 ``RV_BUILD_AXI4``。
* 第 7-L11 行：include path 覆盖 EH2 snapshot 默认配置、design include/lib、
  formal properties 目录和 ``dv/formal`` 自身。
* 第 13-L14 行：先列入 ``ifv_bootstrap.sv``，用于为 ``$unit`` scope 提供宏和
  type-definition 文件。

**接口关系** ：

* **被调用** ：Makefile 的 IFV compile 命令通过 ``-f ifv_filelist.f`` 读取。
* **调用** ：filelist 不执行命令；它把文件路径和编译选项传给 IFV。
* **共享状态** ：绝对路径指向 ``/home/host/Cores-VeeR-EH2`` 和
  ``/home/host/eh2-veri``。

§3.2  RTL 设计文件与 SVA bind 文件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：filelist 使用与综合相近的 RTL 文件集合，再在末尾列入
``eh2_veer_sva.sv``。当前 filelist 不列入 ``eh2_formal_top.sv``。

**关键代码** （``dv/formal/ifv_filelist.f:L16-L34``）：

.. code-block:: text

   // RTL design files (same as synthesis flist)
   /home/host/Cores-VeeR-EH2/design/include/eh2_def.sv
   /home/host/Cores-VeeR-EH2/design/lib/eh2_lib.sv
   /home/host/Cores-VeeR-EH2/design/lib/beh_lib.sv
   /home/host/Cores-VeeR-EH2/design/lib/mem_lib.sv
   /home/host/Cores-VeeR-EH2/design/lib/ahb_to_axi4.sv
   /home/host/Cores-VeeR-EH2/design/lib/axi4_to_ahb.sv
   /home/host/Cores-VeeR-EH2/design/dmi/dmi_wrapper.v
   /home/host/Cores-VeeR-EH2/design/dmi/dmi_jtag_to_core_sync.v
   /home/host/Cores-VeeR-EH2/design/dmi/rvjtag_tap.v
   /home/host/Cores-VeeR-EH2/design/dbg/eh2_dbg.sv
   /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_decode_ctl.sv
   /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_gpr_ctl.sv

**逐段解释** ：

* 第 16 行：注释说明 RTL design files 与 synthesis flist 对齐。
* 第 17-L22 行：先列 include/lib 和 AHB/AXI bridge 类库文件。
* 第 23-L34 行：随后列入 DMI、JTAG、debug 和 DEC 模块文件。

**关键代码** （``dv/formal/ifv_filelist.f:L35-L66``）：

.. code-block:: text

   /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_alu_ctl.sv
   /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_mul_ctl.sv
   /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_div_ctl.sv
   /home/host/Cores-VeeR-EH2/design/exu/eh2_exu.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_clkdomain.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_addrcheck.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_lsc_ctl.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_stbuf.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_bus_buffer.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_bus_intf.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_ecc.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_dccm_mem.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_dccm_ctl.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_trigger.sv
   /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_amo.sv

**逐段解释** ：

* 第 35-L38 行：EXU 相关 ALU、MUL、DIV 和 top 文件进入 filelist。
* 第 39-L50 行：LSU top、clock domain、address check、load/store control、
  store buffer、bus interface、ECC、DCCM 和 AMO 文件进入 filelist。

**关键代码** （``dv/formal/ifv_filelist.f:L51-L66``）：

.. code-block:: text

   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_aln_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_compress_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_ifc_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_bp_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_ic_mem.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_mem_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_iccm_mem.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_btb_mem.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu.sv
   /home/host/Cores-VeeR-EH2/design/eh2_mem.sv
   /home/host/Cores-VeeR-EH2/design/eh2_pic_ctrl.sv
   /home/host/Cores-VeeR-EH2/design/eh2_dma_ctrl.sv
   /home/host/Cores-VeeR-EH2/design/eh2_veer.sv
   
   // SVA bind module: binds to eh2_veer using .* auto-connect (no manual port mapping)
   /home/host/eh2-veri/dv/formal/eh2_veer_sva.sv

**逐段解释** ：

* 第 51-L59 行：IFU alignment、compress、fetch control、branch prediction、
  icache、mem control、ICCM、BTB 和 IFU top 文件进入 filelist。
* 第 60-L63 行：memory、PIC、DMA 和 top-level ``eh2_veer.sv`` 进入 filelist。
* 第 65-L66 行：最后列入 ``eh2_veer_sva.sv``，注释说明它通过
  ``bind eh2_veer`` 和 ``.*`` auto-connect 绑定，不需要手写端口映射。

**接口关系** ：

* **被调用** ：IFV compile/elaboration 阶段读取。
* **调用** ：无脚本调用。
* **共享状态** ：决定 IFV 编译中可见的 RTL module、macro 和 SVA bind module。

§4  主证明 Tcl
--------------------------------------------------------------------------------

§4.1  ``ifv_prove.tcl`` — legacy FormalVerifier 命令序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：主证明 Tcl 在 IFV 15.20 中添加时钟、加入 assertion specification、
执行 prove、打印 assertion summary 并退出。

**关键代码** （``dv/formal/scripts/ifv_prove.tcl:L1-L13``）：

.. code-block:: tcl

   # IFV 15.20 proof script for EH2.
   #
   # This intentionally uses the legacy FormalVerifier shell commands supported by
   # INCISIVE152. Newer check_formal/report_cex/write_vcd commands are not
   # available in this installed tool version.
   
   puts "IFV: EH2 formal proof start"
   clock -add clk -initial 0 -period 2 -width 1
   assertion -add -specification
   prove
   assertion -summary
   puts "IFV: EH2 formal proof complete"
   exit

**逐段解释** ：

* 第 1-L5 行：注释限定命令集，说明该脚本故意使用 INCISIVE152 支持的 legacy
  FormalVerifier shell commands。
* 第 7 行：向 IFV log 打印开始标记。
* 第 8 行：添加 ``clk``，initial 为 0，period 为 2，width 为 1。
* 第 9-L10 行：``assertion -add -specification`` 加入 assertion specification，
  随后 ``prove`` 启动证明。
* 第 11-L13 行：脚本打印 assertion summary、完成标记并退出。

**接口关系** ：

* **被调用** ：Makefile 的 ``ifv`` target 通过 ``ifv -r +tcl+scripts/ifv_prove.tcl``
  调用。
* **调用** ：IFV 内置 ``clock``、``assertion``、``prove``、``puts`` 和 ``exit``。
* **共享状态** ：读取 elaborated design 中的 ``clk`` 和 SVA specification；输出
  写入 ``build/ifv_run.log``。

§4.2  ``ifv_cex_dump.tcl`` — 诊断文本生成
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该脚本在 IFV 15.20 缺少 ``report_cex``、``write_vcd``、
``set_active``、``get_status`` 的限制下，使用 ``assertion -show <property>
-verbose -list`` 为指定 property 生成诊断文本。

**关键代码** （``dv/formal/scripts/ifv_cex_dump.tcl:L1-L12``）：

.. code-block:: tcl

   # IFV 15.20 diagnostic dump for the original RC5 24 failing properties.
   #
   # The installed INCISIVE152 FormalVerifier does not implement report_cex,
   # write_vcd, set_active, or get_status. The supported replacement is
   # assertion -show <property> -verbose -list. This script emits one verbose block
   # per property and creates a build/cex_<property>.txt file documenting the
   # diagnostic source for downstream review.
   
   clock -add clk -initial 0 -period 2 -width 1
   assertion -add -specification
   prove

**逐段解释** ：

* 第 1-L7 行：注释说明这是针对 RC5 原始 24 个 failing properties 的诊断 dump，
  并说明当前 IFV 版本没有 ``report_cex`` 和 ``write_vcd`` 等命令。
* 第 9-L11 行：诊断脚本与主 proof 脚本一样先添加 ``clk``、加入 assertion
  specification 并执行 ``prove``。

**关键代码** （``dv/formal/scripts/ifv_cex_dump.tcl:L13-L38``）：

.. code-block:: tcl

   set props {
     eh2_veer.u_eh2_veer_sva.a_core_rst_active_low
     eh2_veer.u_eh2_veer_sva.a_core_rst_from_reset
     eh2_veer.u_eh2_veer_sva.a_dccm_wr_rd_mutex
     eh2_veer.u_eh2_veer_sva.a_debug_halt_track
     eh2_veer.u_eh2_veer_sva.a_dma_arvalid_stable
     eh2_veer.u_eh2_veer_sva.a_dma_awvalid_stable
     eh2_veer.u_eh2_veer_sva.a_iccm_wr_rd_mutex
     eh2_veer.u_eh2_veer_sva.a_ifu_arvalid_stable
     eh2_veer.u_eh2_veer_sva.a_ifu_awvalid_stable
     eh2_veer.u_eh2_veer_sva.a_ifu_not_both_rw
     eh2_veer.u_eh2_veer_sva.a_ifu_rvalid_accepted
     eh2_veer.u_eh2_veer_sva.a_lsu_araddr_stable

**逐段解释** ：

* 第 13-L38 行：``props`` 列出 24 个完整 property 路径，路径前缀是
  ``eh2_veer.u_eh2_veer_sva``，说明诊断对象来自绑定到 ``eh2_veer`` 的 SVA
  instance。

**关键代码** （``dv/formal/scripts/ifv_cex_dump.tcl:L40-L55``）：

.. code-block:: tcl

   foreach prop $props {
     set fields [split $prop "."]
     set short [lindex $fields [expr {[llength $fields] - 1}]]
     set out "build/cex_${short}.txt"
     set fh [open $out "w"]
     puts $fh "Property: $prop"
     puts $fh "Diagnostic command: assertion -show $prop -verbose -list"
     puts $fh "Note: IFV 15.20 lacks report_cex/write_vcd; see build/ifv_cex_run.log for the verbose status block."
     close $fh
     puts "=== CEX_BEGIN $short ==="
     assertion -show $prop -verbose -list
     puts "=== CEX_END $short ==="
   }
   
   assertion -summary
   exit

**逐段解释** ：

* 第 40-L43 行：循环中从完整 property 路径取最后一个字段作为 short name，并生成
  ``build/cex_<short>.txt`` 文件名。
* 第 44-L48 行：脚本创建文本文件，写入 property 全名、诊断命令和 IFV 15.20
  命令限制说明。
* 第 49-L51 行：log 中用 ``CEX_BEGIN``/``CEX_END`` 包住
  ``assertion -show <property> -verbose -list`` 输出。
* 第 54-L55 行：最后打印 summary 并退出。

**接口关系** ：

* **被调用** ：Makefile 的 ``ifv_cex`` target 调用。
* **调用** ：IFV 内置 ``clock``、``assertion``、``prove`` 和 Tcl 文件 I/O。
* **共享状态** ：读取 elaborated design 中的 SVA property，写
  ``build/cex_*.txt`` 和 ``build/ifv_cex_run.log``。

§5  SVA 绑定模块
--------------------------------------------------------------------------------

§5.1  ``eh2_veer_sva.sv`` 端口与 assume 环境
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_veer_sva`` 是当前 IFV 主路径实际编译的 SVA bind module。它声明
与 ``eh2_veer`` 端口和内部层级路径相关的输入，并在文件末尾绑定到
``eh2_veer``。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L9-L30``）：

.. code-block:: systemverilog

   module eh2_veer_sva
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic clk,
     input logic rst_l,
     input logic dbg_rst_l,
     input logic [31:1] rst_vec,
     input logic nmi_int,
     input logic [31:1] nmi_vec,
     input logic scan_mode,
   
     input logic core_rst_l,
     input logic dbg_core_rst_l,
     input logic active_l2clk,
     input logic free_l2clk,
     input logic lsu_bus_clk_en,
     input logic ifu_bus_clk_en,

**逐段解释** ：

* 第 9-L13 行：模块导入 ``eh2_pkg`` 并 include ``eh2_param.vh``，使参数 ``pt`` 等
  类型/常量可用于端口宽度。
* 第 14-L21 行：第一组输入覆盖 clock/reset、reset vector、NMI vector 和
  ``scan_mode``。
* 第 22-L30 行：第二组输入覆盖 core/debug reset、l2 clock、bus clock enable 和
  ``dec_tlu_force_halt``。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L114-L138``）：

.. code-block:: systemverilog

     // =========================================================================
     // INPUT ASSUMPTIONS — constrain free inputs for meaningful proofs
     // =========================================================================
     // Assume dbg_rst_l tracks rst_l (debug reset tied to main reset in formal)
     a_dbg_rst_tracks_rst: assume property (@(posedge clk)
       dbg_rst_l == rst_l
     );
   
     // The formal top models functional operation only; scan mode forces some
     // reset logic active-high and makes the functional reset properties invalid.
     a_no_scan_mode: assume property (@(posedge clk)
       scan_mode == 1'b0
     );

**逐段解释** ：

* 第 114-L119 行：assumption ``a_dbg_rst_tracks_rst`` 约束 debug reset 与主 reset
  一致。
* 第 122-L126 行：assumption ``a_no_scan_mode`` 把 ``scan_mode`` 约束为 0，
  源码注释说明 scan mode 会改变 reset 逻辑语义。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L128-L138``）：

.. code-block:: systemverilog

     // Reset and NMI vectors are platform pins. The platform is expected to hold
     // them stable while reset is asserted; otherwise reset-vector properties are
     // checking an unconstrained environment rather than core RTL behavior.
     a_rst_vec_stable_env: assume property (@(posedge clk)
       !rst_l |-> $stable(rst_vec)
     );
   
     a_nmi_vec_stable_env: assume property (@(posedge clk)
       !rst_l |-> $stable(nmi_vec)
     );

**逐段解释** ：

* 第 128-L133 行：``a_rst_vec_stable_env`` 要求 reset asserted 时 ``rst_vec`` 稳定。
* 第 135-L137 行：``a_nmi_vec_stable_env`` 对 ``nmi_vec`` 施加同样的 reset 期间
  稳定约束。

**接口关系** ：

* **被调用** ：``ifv_filelist.f`` 编译该模块，文件末尾 ``bind`` 把它实例化到
  ``eh2_veer``。
* **调用** ：SVA assumption 不调用任务；它约束 IFV 状态空间。
* **共享状态** ：端口通过 ``.*`` 与 ``eh2_veer`` 同名信号自动连接。

§5.2  reset、AXI、trace、memory 和 cover 分类
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：SVA 文件把 assertion 分成 reset/clock、LSU AXI、IFU AXI、DMA AXI、
trace/debug、DCCM/ICCM、structural、reset sequencing、clock override 和 cover
几类。当前源码中 ``eh2_veer_sva.sv`` 有 4 条 assume、38 条 assert 和 4 条 cover，
合计 46 个以 ``a_``/``c_`` 开头的 property label。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L140-L170``）：

.. code-block:: systemverilog

     // =========================================================================
     // Category 1: Reset / Clock (6 assertions)
     // =========================================================================
     // P1: external reset must force core reset in functional mode
     a_core_rst_active_low: assert property (@(posedge clk)
       (!rst_l && !scan_mode) |-> !core_rst_l
     );
   
     // P2: with all reset sources deasserted, core_rst_l is released
     a_core_rst_from_reset: assert property (@(posedge clk)
       (rst_l && dbg_core_rst_l && !scan_mode) |-> core_rst_l
     );

**逐段解释** ：

* 第 140-L145 行：reset/clock 分类开始；``a_core_rst_active_low`` 约束 functional
  mode 下外部 reset asserted 时 ``core_rst_l`` 为 0。
* 第 148-L150 行：``a_core_rst_from_reset`` 约束 reset 源释放且非 scan mode 时
  ``core_rst_l`` 释放。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L178-L207``）：

.. code-block:: systemverilog

     a_lsu_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awvalid == lsu.bus_intf.lsu_axi_awvalid
     );
   
     a_lsu_awaddr_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awaddr == lsu.bus_intf.lsu_axi_awaddr
     );
   
     a_lsu_awlen_legal: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awvalid |-> lsu_axi_awlen <= 8'd255
     );
   
     a_lsu_awsize_legal: assert property (@(posedge clk) disable iff (!rst_l)

**逐段解释** ：

* 第 178-L184 行：前两条 LSU write-address assertion 检查 top-level AXI 信号与
  ``lsu.bus_intf`` 层级路径一致。
* 第 186-L192 行：``a_lsu_awlen_legal`` 和 ``a_lsu_awsize_legal`` 在
  ``lsu_axi_awvalid`` 时检查 AXI length/size 的合法范围。
* 第 197-L207 行：write-data 分类对 ``wvalid``、``wstrb``、``wdata`` 做
  top-level 与 ``lsu.bus_intf`` 的一致性检查。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L242-L277``）：

.. code-block:: systemverilog

     a_ifu_arvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
       ifu_axi_arvalid == ifu.mem_ctl.ifu_axi_arvalid
     );
   
     a_ifu_rvalid_accepted: assert property (@(posedge clk) disable iff (!rst_l)
       ifu_axi_rvalid |-> ifu_axi_rready
     );
   
     a_ifu_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
       ifu_axi_awvalid && !ifu_axi_awready |=> ifu_axi_awvalid
     );
   
     // =========================================================================
     // Category 7: DMA AXI (2 assertions)

**逐段解释** ：

* 第 242-L244 行：IFU read-address valid 与 ``ifu.mem_ctl`` 内部信号一致。
* 第 246-L252 行：IFU read data valid 要求 ready；IFU write address valid 在未
  ready 时保持 asserted。
* 第 257-L265 行：DMA AXI 分类检查 ``dma_axi_arready`` 和 ``dma_axi_awready`` 与
  ``dma_ctrl`` 内部 ready 信号一致。
* 第 270-L277 行：trace/debug 分类检查 trace valid 时地址不是 unknown，并检查
  debug mode status 与 ``dec.tlu`` 内部状态一致。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L282-L358``）：

.. code-block:: systemverilog

     a_dccm_wr_rd_mutex: assert property (@(posedge clk) disable iff (!rst_l)
       !(lsu.dccm_ctl.lsu_dccm_wren_spec_dc1 &&
         lsu.dccm_ctl.lsu_dccm_rden_dc1)
     );
   
     a_iccm_wr_rd_mutex: assert property (@(posedge clk) disable iff (!rst_l)
       (iccm_wren == ifu.mem_ctl.iccm_wren) &&
       (iccm_rden == ifu.mem_ctl.iccm_rden)
     );
   
     a_dccm_wr_addr_known: assert property (@(posedge clk) disable iff (!rst_l)
       dccm_wren |-> !$isunknown(dccm_wr_addr_lo)

**逐段解释** ：

* 第 282-L285 行：DCCM assertion 禁止 LSU DCCM write enable 和 read enable 在同一
  条件下同时为真。
* 第 287-L290 行：ICCM assertion 检查 top-level ``iccm_wren/iccm_rden`` 与
  ``ifu.mem_ctl`` 内部信号一致。
* 第 292-L358 行：后续 assertion 检查 DCCM/ICCM 地址 known、IFU/LSU 地址和数据
  known、reset vector/NMI vector 稳定，以及 clock override/ECC disable 不是
  unknown。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L360-L385``）：

.. code-block:: systemverilog

     // =========================================================================
     // Category 13: Cover properties (4 covers)
     // =========================================================================
     // These coverpoints are formal smoke reachability checks. Full halt/run and
     // AXI burst reachability depends on a constrained platform/test program and
     // is tracked by UVM directed tests, not by this unconstrained IFV proof.
     c_halt_handshake: cover property (@(posedge clk)
       rst_l && !scan_mode && !$isunknown(o_cpu_halt_ack[0])
     );
   
     c_run_handshake: cover property (@(posedge clk)
       rst_l && !scan_mode && !$isunknown(o_cpu_run_ack[0])

**逐段解释** ：

* 第 360-L365 行：源码注释说明 coverpoint 是 formal smoke reachability checks；
  完整 halt/run 和 AXI burst reachability 由 UVM directed tests 跟踪，不由这个
  unconstrained IFV proof 单独完成。
* 第 366-L380 行：4 个 cover 分别覆盖 halt ack known、run ack known、AXI write
  valid known 和 AXI read valid/ready known。
* 第 384-L385 行：``bind eh2_veer eh2_veer_sva u_eh2_veer_sva (.*);`` 把 SVA
  模块绑定到 top-level ``eh2_veer``。

**接口关系** ：

* **被调用** ：IFV elaboration 读取并 bind 到 ``eh2_veer``。
* **调用** ：SVA 使用 ``$past``、``$stable``、``$isunknown`` 和层级引用。
* **共享状态** ：property label 被 ``ifv_cex_dump.tcl`` 和 ``ifv_count`` 识别。

§6  ``eh2_formal_top.sv`` 保留 testbench
--------------------------------------------------------------------------------

§6.1  formal top 的时钟、reset 和 tie-off
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_formal_top.sv`` 是一个 full-core formal testbench：它声明时钟、
reset、DUT 输入、AXI tie-off 和 property。当前主 filelist 不使用它作为 IFV top，
但它仍是 formal harness 设计意图的源代码证据。

**关键代码** （``dv/formal/eh2_formal_top.sv:L15-L36``）：

.. code-block:: systemverilog

   module eh2_formal_top
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   );
   
       // ====================================================================
       // Clock and reset generation (free-running for formal)
       // ====================================================================
       logic clk = 0;
       logic rst_l = 0;
       logic free_clk = 0;
   
       always #5 clk = ~clk;
       always #3 free_clk = ~free_clk;

**逐段解释** ：

* 第 15-L19 行：formal top 导入 ``eh2_pkg`` 并 include ``eh2_param.vh``。
* 第 21-L29 行：声明 ``clk``、``rst_l``、``free_clk``，并用 ``always #5`` 和
  ``always #3`` 生成两个 free-running clock。

**关键代码** （``dv/formal/eh2_formal_top.sv:L31-L57``）：

.. code-block:: systemverilog

       // Reset sequence
       initial begin
           rst_l = 0;
           repeat(10) @(posedge clk);
           rst_l = 1;
       end
   
       // ====================================================================
       // DUT input signals — tied to inactive/formal-safe values
       // ====================================================================
       logic         dbg_rst_l     = 1'b1;  // Debug reset inactive
       logic [31:1]  rst_vec       = 31'h40000000;
       logic         nmi_int       = 1'b0;
       logic [31:1]  nmi_vec       = '0;
       logic [31:0]  extintsrc_req = '0;

**逐段解释** ：

* 第 31-L36 行：reset sequence 在 10 个 ``clk`` 上升沿后释放 ``rst_l``。
* 第 41-L57 行：DUT 输入被 tie 到 inactive/formal-safe 值，包括 debug reset、
  reset vector、NMI、external interrupt、JTAG、halt/run request 和 debug run/halt
  request。

**接口关系** ：

* **被调用** ：当前 ``ifv_filelist.f`` 未调用；未来如果 filelist 改为该 top，
  IFV top 需要同步切换。
* **调用** ：实例化 ``eh2_veer`` 并在本文件内定义 assertions。
* **共享状态** ：与 ``eh2_veer_sva.sv`` 有部分 property label 重名，但绑定方式不同。

§6.2  formal top 中的 DUT 实例化和内嵌 assertions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该文件直接实例化 ``eh2_veer``，连接 trace、AXI、debug、JTAG、interrupt
等大量端口，并在实例化后写入 27 条 assertion 和 3 条 cover。

**关键代码** （``dv/formal/eh2_formal_top.sv:L215-L235``）：

.. code-block:: systemverilog

       // ====================================================================
       // DUT Instantiation — eh2_veer (full core, no wrapper to minimize ports)
       // ====================================================================
       eh2_veer #() u_dut (
           .clk                    (clk),
           .rst_l                  (rst_l),
           .dbg_rst_l              (rst_l),
           .rst_vec                (rst_vec),
           .nmi_int                (nmi_int),
           .nmi_vec                (nmi_vec),
           .jtag_id                (jtag_id),
           .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
           .trace_rv_i_address_ip  (trace_rv_i_address_ip),
           .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
           .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
           .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),

**逐段解释** ：

* 第 215-L218 行：DUT 实例是 full-core ``eh2_veer``，实例名 ``u_dut``。
* 第 219-L235 行：开头连接 clock/reset、NMI、JTAG ID 和 trace 输出。

**关键代码** （``dv/formal/eh2_formal_top.sv:L441-L471``）：

.. code-block:: systemverilog

       // --- Category 1: Reset / Clock (6 assertions) ---
   
       // P1: core_rst_l is derived from external rst_l (active low)
       a_core_rst_active_low: assert property (@(posedge clk)
           !rst_l |-> !core_rst_l
       );
   
       // P2: core_rst_l follows dbg_rst_l
       a_dbg_rst_to_core: assert property (@(posedge clk)
           !dbg_rst_l |-> !core_rst_l
       );

**逐段解释** ：

* 第 441-L446 行：formal top 的 reset/clock category 开始，第一条 assertion 检查
  ``rst_l`` 拉低时 ``core_rst_l`` 也为低。
* 第 448-L451 行：第二条 assertion 检查 ``dbg_rst_l`` 拉低时 ``core_rst_l`` 为低。
* 第 453-L471 行：后续 assertion 检查 ``active_l2clk``、``free_l2clk`` known、
  reset 期间 ``dec_tlu_mhartstart`` 为 0，以及 ``core_rst_l`` 无 X。

**关键代码** （``dv/formal/eh2_formal_top.sv:L596-L608``）：

.. code-block:: systemverilog

       c_halt_handshake: cover property (@(posedge clk) disable iff (!rst_l)
           i_cpu_halt_req[0] ##1 o_cpu_halt_ack[0]
       );
   
       c_axi_write_burst: cover property (@(posedge clk) disable iff (!rst_l)
           lsu_axi_awvalid && lsu_axi_awready
           ##1 lsu_axi_wvalid && lsu_axi_wready && lsu_axi_wlast
       );
   
       c_axi_read_burst: cover property (@(posedge clk) disable iff (!rst_l)
           lsu_axi_arvalid && lsu_axi_arready
           ##[1:8] lsu_axi_rvalid && lsu_axi_rready && lsu_axi_rlast

**逐段解释** ：

* 第 596-L598 行：cover ``c_halt_handshake`` 覆盖 halt request 后 1 拍出现 halt ack。
* 第 600-L603 行：cover ``c_axi_write_burst`` 覆盖 AXI write address handshake 后
  1 拍出现 write data handshake 和 last。
* 第 605-L608 行：cover ``c_axi_read_burst`` 覆盖 AXI read address handshake 后
  1 到 8 拍出现 read data handshake 和 last。

**接口关系** ：

* **被调用** ：当前主 filelist 未列入；作为保留 harness 源文件存在。
* **调用** ：实例化 ``eh2_veer``，使用 SVA ``assert property`` 和
  ``cover property``。
* **共享状态** ：端口和 property 名称可与 ``eh2_veer_sva.sv`` 对照，但不能把该
  文件的 property 数计入当前 IFV filelist 主路径。

§7  Sail 辅助检查
--------------------------------------------------------------------------------

§7.1  ``sail_setup.sh`` — 获取和构建 Sail-RISCV
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该脚本尝试 clone 和 build ``sail-riscv``，为 formal/spec 路径提供
``riscv_sim_RV32``。如果网络、git、opam 或 build 不可用，脚本打印 skip/info 并
退出 0，保留 built-in checks。

**关键代码** （``dv/formal/spec/sail_setup.sh:L21-L38``）：

.. code-block:: bash

   set -euo pipefail
   
   SAIL_REPO="https://github.com/riscv/sail-riscv"
   SAIL_DIR="./sail-riscv"
   SAIL_BIN="./riscv_sim_RV32"
   
   echo "=== EH2 Formal: Sail-RISCV Setup ==="
   echo ""
   
   # Option 1: Clone and build (full integration)
   if [ ! -d "$SAIL_DIR" ]; then
       echo "[STEP 1/3] Cloning sail-riscv..."
       git clone --depth=1 "$SAIL_REPO" "$SAIL_DIR" || {
           echo "[SKIP] Unable to clone sail-riscv (no network or git unavailable)"
           echo "[INFO] Formal bridge will use built-in checks from sail_bridge.sv"

**逐段解释** ：

* 第 21 行：脚本使用 ``set -euo pipefail``。
* 第 23-L25 行：定义 Sail repo URL、本地目录和目标 binary symlink 路径。
* 第 31-L38 行：如果 ``sail-riscv`` 目录不存在，脚本执行 shallow clone；clone
  失败时打印 skip/info，并以 0 退出。

**关键代码** （``dv/formal/spec/sail_setup.sh:L43-L67``）：

.. code-block:: bash

   echo "[STEP 2/3] Installing sail-riscv build dependencies..."
   # Dependencies: OCaml, opam, sail, z3
   command -v opam >/dev/null 2>&1 || {
       echo "[SKIP] opam not found. Cannot build sail."
       echo "[INFO] Built-in checks remain active. Install opam for full replay."
       exit 0
   }
   
   (cd "$SAIL_DIR" && opam install -y sail) || true
   
   echo "[STEP 3/3] Building sail-riscv c_emulator (RV32)..."
   (cd "$SAIL_DIR" && make c_emulator 2>&1 | tail -5) || {
       echo "[SKIP] Build failed. Dependencies may be incomplete."
       echo "[INFO] Built-in checks remain active. See sail_bridge.sv."

**逐段解释** ：

* 第 43-L49 行：脚本要求 ``opam``，找不到时不报 fatal，而是提示 built-in checks
  仍 active 并退出 0。
* 第 51 行：在 Sail 目录中执行 ``opam install -y sail``，失败也通过 ``|| true``
  继续。
* 第 53-L58 行：执行 ``make c_emulator``，只显示最后 5 行；构建失败时打印 skip
  和 built-in checks 信息并退出 0。
* 第 61-L67 行：若生成 ``c_emulator/riscv_sim_RV32``，脚本在当前 spec 目录建立
  symlink ``riscv_sim_RV32``。

**接口关系** ：

* **被调用** ：开发者在 ``dv/formal/spec`` 下执行 ``bash sail_setup.sh``。
* **调用** ：``git clone``、``opam install``、``make c_emulator``、``ln -sf``。
* **共享状态** ：写 ``dv/formal/spec/sail-riscv`` 和
  ``dv/formal/spec/riscv_sim_RV32``。

§7.2  ``sail_trace_check.py`` — trace divergence checker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 Python 脚本提供 EH2 trace 与 Sail-RISCV architectural state 的比较
框架。当前 ``step_instruction`` 内部用 Python 逻辑模拟部分 RV32 指令语义；脚本
在 Sail binary 或 trace 不存在时打印 warning/info，并继续执行 built-in checks
路径。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L20-L66``）：

.. code-block:: python

   import argparse
   import subprocess
   import sys
   import os
   import struct
   
   # ---------------------------------------------------------------------------
   # RISC-V instruction encoding helpers (RV32IMCB)
   # ---------------------------------------------------------------------------
   OPCODE_MASK    = 0x7F
   FUNCT3_MASK    = 0x7000
   FUNCT7_MASK    = 0xFE000000
   RD_MASK        = 0xF80
   RS1_MASK       = 0xF8000

**逐段解释** ：

* 第 20-L24 行：脚本导入 argparse、subprocess、sys、os 和 struct。当前源码中
  ``subprocess`` 与 ``struct`` 被导入，但主路径未调用。
* 第 29-L45 行：定义 opcode 和字段 mask 常量，覆盖 LUI/AUIPC/JAL/JALR、
  branch、load/store、ALU、fence 和 system。
* 第 47-L54 行：定义 system ``funct3`` 常量，用于 ECALL/EBREAK/MRET/WFI 与 CSR
  指令分类。
* 第 56-L64 行：``decode_rd``、``decode_opcode``、``decode_funct3`` 从 instruction
  word 中提取字段。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L66-L130``）：

.. code-block:: python

   class SailChecker:
       """Wraps sail-riscv c_emulator for trace replay and divergence detection."""
   
       # SAIL architectural register checkpoints (matches sail_bridge.sv projections)
       SAIL_PC = 0
       SAIL_GPR_BASE = 1
       SAIL_GPR_COUNT = 32
       SAIL_X0_RESERVED = 0  # x0 is hardwired to zero in RISC-V
       SAIL_PRIV_M_MODE = 3
       SAIL_MSTATUS = 0x300
       SAIL_MCAUSE  = 0x342
   
       def __init__(self, sail_bin):

**逐段解释** ：

* 第 66-L76 行：``SailChecker`` 类记录 architectural checkpoint 常量，包括 PC、
  GPR base/count、x0、M-mode privilege、mstatus 和 mcause。
* 第 78-L83 行：构造函数保存 ``sail_bin``，初始化 32 个 GPR、PC 和 mstatus。
* 第 84-L88 行：``reset`` 把 GPR 清零，PC 设为 reset vector，mstatus 设为 0。
* 第 90-L130 行：``step_instruction`` 当前根据 opcode 处理 LUI、AUIPC、JAL、
  JALR 和其他顺序 PC 增量，并返回 ``(pc, gpr_write)``。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L132-L162``）：

.. code-block:: python

   def check_against_eh2_trace(self, eh2_pc, eh2_rd, eh2_wen, eh2_wdata, eh2_instr):
       """Compare EH2 trace entry against sail execution."""
       sail_next_pc, sail_gpr_write = self.step_instruction(eh2_instr)
   
       divergences = []
   
       # Check 1: PC match
       if eh2_pc != self.pc:
           divergences.append(
               f"PC divergence: EH2={eh2_pc:#010x} SAIL={self.pc:#010x}"
           )
   
       # Check 2: x0 writes

**逐段解释** ：

* 第 132-L136 行：函数执行一条 instruction，并创建 divergence 列表。
* 第 139-L142 行：如果 EH2 PC 与 checker 当前 PC 不一致，追加 PC divergence 文本。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L144-L162``）：

.. code-block:: python

       # Check 2: x0 writes
       if eh2_wen and eh2_rd == 0 and eh2_wdata != 0:
           divergences.append(
               f"x0 writeback violation: EH2 wrote {eh2_wdata:#010x} to x0"
           )
   
       # Check 3: GPR writeback match (when sail also writes)
       if eh2_wen and sail_gpr_write is not None:
           s_rd, s_val = sail_gpr_write
           if eh2_rd != s_rd:
               divergences.append(
                   f"rd mismatch: EH2={eh2_rd} SAIL={s_rd}"
               )

**逐段解释** ：

* 第 145-L148 行：当 EH2 写 x0 且写入值不是 0 时，函数报告 x0 writeback violation。
* 第 151-L156 行：如果 EH2 和 Sail 都写 GPR，先比较 ``rd`` 是否一致。
* 第 157-L160 行：随后比较 write data 是否一致，不一致时记录 ``wdata mismatch``。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L165-L213``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(
           description="EH2-to-Sail-RISCV trace divergence checker"
       )
       parser.add_argument("--trace", required=True, help="EH2 trace CSV file")
       parser.add_argument("--sail", default="./riscv_sim_RV32",
                           help="Path to sail-riscv c_emulator")
       parser.add_argument("--max-instructions", type=int, default=10000,
                           help="Maximum instructions to check")
       args = parser.parse_args()

**逐段解释** ：

* 第 165-L173 行：CLI 参数包括必填 ``--trace``、可选 ``--sail`` 和
  ``--max-instructions``。
* 第 176-L183 行：如果 Sail binary 不存在，脚本打印 warning 和 build 提示，并说明
  formal bridge 将使用 built-in architectural checks。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L176-L213``）：

.. code-block:: python

       if not os.path.exists(args.sail):
           print(f"[WARN] sail-riscv binary not found at {args.sail}")
           print("[INFO] Install sail-riscv: git clone https://github.com/riscv/sail-riscv")
           print("[INFO] Build: cd sail-riscv && make c_emulator")
           print("[INFO] Formal bridge will use built-in architectural checks only.")
           # Continue with built-in checks (x0 stability, privilege, cause range)
           # These are embedded in sail_bridge.sv as SVA properties.
   
       checker = SailChecker(args.sail)
       checker.reset()

**逐段解释** ：

* 第 176-L183 行：Sail binary 缺失不是 fatal；脚本继续创建 checker。
* 第 184-L185 行：实例化 ``SailChecker`` 并调用 ``reset``。

**关键代码** （``dv/formal/spec/sail_trace_check.py:L187-L213``）：

.. code-block:: python

       total_divergences = 0
       print("=" * 60)
       print("EH2 ↔ SAIL-RISCV Trace Divergence Check")
       print("=" * 60)
   
       if os.path.exists(args.trace):
           # In production: parse EH2 trace CSV and replay through sail
           # Format: pc,rd,wen,wdata,instr (one instruction per line)
           print(f"[INFO] Trace file: {args.trace}")
           print(f"[INFO] Max instructions: {args.max_instructions}")
       else:
           print(f"[WARN] Trace file not found: {args.trace}")

**逐段解释** ：

* 第 187-L190 行：初始化 divergence 计数并打印检查标题。
* 第 192-L196 行：trace 文件存在时，当前代码只打印 trace 路径和 max instruction；
  注释说明生产路径应解析 CSV 并 replay through Sail。
* 第 197-L202 行：trace 文件不存在时，脚本打印 built-in architectural checks 列表：
  x0 stability、exception cause range 和 M-mode only。
* 第 204-L209 行：根据 ``total_divergences`` 打印 PASS 或 FAIL，并返回 0 或 1。

**接口关系** ：

* **被调用** ：开发者或辅助流程执行 ``python3 sail_trace_check.py --trace ...``。
* **调用** ：当前主路径调用 Python 内部 decode/checker 逻辑，没有实际
  ``subprocess`` 调用 Sail binary。
* **共享状态** ：读取 ``--trace`` 路径和 ``--sail`` 路径；输出只打印到 stdout。

§8  运行与检查
--------------------------------------------------------------------------------

§8.1  主证明运行序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：formal 主流程只需要在 repo 内调用 Makefile target。命令序列来自
``dv/formal/Makefile``，不是文档自定义包装。

.. code-block:: bash

   make -C /home/host/eh2-veri/dv/formal ifv

**逐段解释** ：

* 该命令进入 ``dv/formal``，执行默认 IFV 主 target。
* 预期读取 ``ifv_filelist.f`` 和 ``scripts/ifv_prove.tcl``。
* 预期生成 ``build/ifv_elab.log``、``build/ifv_run.log`` 和
  ``build/ifv_summary.txt``。
* 当前 release 证据记录 formal 46/46，即 Total 46、Pass 46、Not_Run 0。

**接口关系** ：

* **被调用** ：开发者、本地 sign-off 或 CI stage。
* **调用** ：Makefile target ``ifv``。
* **共享状态** ：会写 ``dv/formal/build``；该目录是 build 产物，不由本文档修改。

§8.2  诊断和计数运行序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：CEX 诊断和 property 计数是辅助路径，不改变主 formal 结果。

.. code-block:: bash

   make -C /home/host/eh2-veri/dv/formal ifv_cex
   make -C /home/host/eh2-veri/dv/formal ifv_count

**逐段解释** ：

* ``ifv_cex`` 调用 ``ifv_cex_dump.tcl``，为脚本列出的 property 生成
  ``build/cex_*.txt`` 诊断文本，并把 verbose status block 写入
  ``build/ifv_cex_run.log``。
* ``ifv_count`` 使用 grep 统计当前目录 ``*.sv`` 与 ``properties/*.sv`` 中以
  ``a_``、``c_`` 开头的 label。该统计是文本扫描，不等同于 IFV summary。

**接口关系** ：

* **被调用** ：debug formal failure 或核对 property 数时调用。
* **调用** ：Makefile target ``ifv_cex``、``ifv_count``。
* **共享状态** ：``ifv_cex`` 写 build 目录；``ifv_count`` 只读源文件并打印统计。

§9  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`appendix_c_tools_formal_infra`、
  :ref:`appendix_c_tools_formal_properties`。
* 关联 ADR：:ref:`adr-0012`、:ref:`adr-0014`。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/Makefile``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/ifv_filelist.f``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/eh2_veer_sva.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/eh2_formal_top.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/scripts/ifv_prove.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/scripts/ifv_cex_dump.tcl``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/spec/sail_setup.sh``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/formal/spec/sail_trace_check.py``。

§10  动手练习
--------------------------------------------------------------------------------

入门题（5 分钟）：

.. code-block:: bash

   cd /home/host/eh2-veri
   rg -n "Assertion Summary|Total|Pass|Not_Run" dv/formal/build dv/formal/*.md

目标是找到 formal summary 的文本证据，并说明 ``46/46`` 与 coverage 百分比无关。

进阶题（30 分钟）：

.. code-block:: bash

   sed -n '1,80p' dv/formal/ifv_filelist.f
   sed -n '1,120p' dv/formal/scripts/ifv_prove.tcl

写下 filelist 中进入 IFV 的 3 类文件：bootstrap、RTL、SVA/bind，并说明 Tcl 脚本中
哪几行定义 clock、添加 assertions 和启动 prove。

挑战题（2 小时）：

选择 ``dv/formal/properties/eh2_lsu_assert.sv`` 中一条 property，按
:ref:`appendix_c_tools_formal_properties` 的模板写出：验证目标、前置 assume、可能 CEX、
与仿真 directed test 的互补关系。不要修改 RTL，只写分析记录。

§11  自检与下一步
--------------------------------------------------------------------------------

读完本章后，你应该能回答：

1. ``make -C dv/formal ifv`` 为什么是当前 formal 主入口？
2. ``eh2_formal_top.sv`` 存在但未列入 ``ifv_filelist.f`` 时，文档应以哪个为准？
3. SVA 中 assume 与 assert 的职责分别是什么？
4. 46/46 PASS 说明什么？它不能说明什么？
5. 如果 IFV 失败，你会先看 ``ifv_elab.log``、``ifv_run.log``、``ifv_summary.txt`` 还是
   ``cex_*.txt``？为什么？

下一步建议阅读 :ref:`lec_flow`，理解 formal property proof 之外，综合前后逻辑等价
如何被签核。
