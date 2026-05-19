.. _appendix_c_tools_syn_yosys:
.. _appendix_c_tools/syn_yosys:

Yosys 综合脚本源码字典
======================

:status: draft
:source: syn/yosys/eh2_synth.tcl
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 EH2 仓库中的 Yosys 综合入口。当前 :file:`syn/yosys/eh2_synth.tcl`
不是一个可闭合 EH2 综合的脚本，而是一个显式失败的 sentinel：它记录
Yosys 0.55 无法解析 EH2 SystemVerilog 2017 语法，并阻止用户把旧的
``rvjtag_tap`` 假综合结果误当成 ``eh2_veer`` 综合结果。

本章重点不是"如何用 Yosys 综合 EH2"，而是说明这条 open-source path 的真实边界：

* :file:`syn/yosys/eh2_synth.tcl` 在第 21~24 行直接打印错误并 ``exit 1``。
* :file:`syn/Makefile` 仍保留 ``syn-yosys`` target，用于可重复地产生失败日志。
* :ref:`adr-0013` 记录综合工具链决策：默认综合路径转向 Design Compiler。

§2  ``syn/yosys/eh2_synth.tcl`` 顶部状态块
------------------------------------------------------------------------------------------------------------------------

职责：脚本开头用注释定义 Yosys path 的状态、目标 top、阻塞点和 fallback 方向。
这些注释是文档中描述 open-source 综合边界的直接证据。

§2.1  状态与目标声明
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/yosys/eh2_synth.tcl:L1-L4``）：

.. code-block:: text

   # ─── EH2 Yosys Synthesis TCL ────────────────────────────────────────────
   # STATUS: OPEN-SOURCE-INCOMPATIBLE (yosys 0.55 cannot parse SV-2017)
   # Target: eh2_veer (core wrapper, ~1500 lines SV, ~40 submodules)
   #

逐段解释：

* 第 1 行：文件是 EH2 Yosys synthesis TCL，不是 LEC 脚本，也不是 Design Compiler
  脚本。
* 第 2 行：状态明确为 ``OPEN-SOURCE-INCOMPATIBLE``。原因也写在同一行：
  ``yosys 0.55`` 不能解析 ``SV-2017``。
* 第 3 行：目标 top 是 ``eh2_veer``，不是 ``rvjtag_tap`` 或其它小模块。这个目标
  定义与 :ref:`adr-0013` 中对早期误导性综合结果的纠正一致。

接口关系：

* 被调用：``syn/Makefile:syn-yosys`` 通过 stdin 把该文件传给 Yosys。
* 调用：无实际综合命令；后文直接 ``exit 1``。
* 共享状态：目标 top 名称 ``eh2_veer``。

§2.2  Yosys blocker 列表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/yosys/eh2_synth.tcl:L5-L10``）：

.. code-block:: text

   # BLOCKER: yosys 0.55 cannot parse:
   #   1. 'import eh2_pkg::*;' in module headers (all design modules)
   #   2. '{...} struct literals in parameter defaults (eh2_param.vh)
   #   sv2v pre-built binaries require GLIBC 2.27+ (system has 2.17)
   #   See ADR-0013 for full analysis.
   #

逐段解释：

* 第 5~7 行：脚本列出两个 Yosys 解析 blocker：模块头部的
  ``import eh2_pkg::*;``，以及 :file:`eh2_param.vh` 中参数默认值里的
  ``'{...}`` struct literal。
* 第 8 行：``sv2v`` 预构建二进制也不可直接作为 fallback，因为需要
  ``GLIBC 2.27+``，而当前系统记录为 ``2.17``。
* 第 9 行：完整分析归档在 :ref:`adr-0013`。本文引用 ADR，不重新编造工具版本或
  workaround。

接口关系：

* 被调用：读者和 ``syn-yosys`` 失败日志使用这段作为根因提示。
* 调用：无。
* 共享状态：依赖工具版本 ``yosys 0.55`` 与系统 ``GLIBC 2.17``。

§2.3  预期未来流程与当前替代路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/yosys/eh2_synth.tcl:L11-L19``）：

.. code-block:: text

   # INTENDED FLOW (when toolchain supports SV-2017):
   #   step 1: sv2v or DC elaboration to produce flat Verilog-2001
   #   step 2: yosys reads flat file
   #   step 3: yosys synth -top eh2_veer
   #
   # For now, use commercial flow: make syn-dc (Design Compiler)
   #
   # This script will exit with error if run as-is.
   # The old rvjtag_tap fake synthesis has been REMOVED.

逐段解释：

* 第 11~14 行：当工具链支持 SV-2017 时，预期路径是先生成 flat Verilog-2001，
  再由 Yosys 读取 flat file，最后执行 ``synth -top eh2_veer``。
* 第 16 行：当前可用替代路径是 ``make syn-dc``，也就是商业 Design Compiler
  flow。
* 第 18 行：脚本声明按当前状态运行会报错。
* 第 19 行：旧的 ``rvjtag_tap`` 假综合已移除。文档必须保留这个边界，因为
  :ref:`adr-0013` 明确指出早期 ``rvjtag_tap`` 结果不能代表 EH2 core。

接口关系：

* 被调用：用户读失败日志时获得下一步命令 ``make syn-dc``。
* 调用：无。
* 共享状态：未来流程依赖 ``sv2v`` 或 DC elaboration 生成 flat Verilog-2001。

§3  显式失败路径
------------------------------------------------------------------------------------------------------------------------

职责：脚本末尾没有隐藏综合尝试，而是用 3 条 ``puts`` 和一个 ``exit 1`` 使
``syn-yosys`` 明确失败。这比生成错误 netlist 更安全。

§3.1  ``puts`` 错误信息
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/yosys/eh2_synth.tcl:L21-L23``）：

.. code-block:: text

   puts "ERROR: yosys 0.55 cannot synthesize EH2 (SV-2017 unsupported)."
   puts "See ADR-0013 and syn/README.md for details."
   puts "Use commercial tool: make syn-dc"

逐段解释：

* 第 21 行：错误信息点名 ``yosys 0.55`` 和 ``SV-2017 unsupported``。这是
  ``syn-yosys`` 失败日志中最重要的用户可见行。
* 第 22 行：脚本要求读者参考 :ref:`adr-0013` 与 :file:`syn/README.md`。
* 第 23 行：脚本给出可操作替代命令 ``make syn-dc``。

接口关系：

* 被调用：Yosys 解释器执行 TCL 时输出。
* 调用：TCL ``puts``。
* 共享状态：无外部文件写入。

§3.2  非零退出码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/yosys/eh2_synth.tcl:L24``）：

.. code-block:: text

   exit 1

逐段解释：

* 第 24 行：脚本以非零状态退出，确保 :file:`syn/Makefile` 能捕获失败并在日志中
  显示 ``yosys exit code``。
* 这行也防止后续 Make target 把不存在的 Yosys netlist、area report 或 timing
  report 误判为成功产物。

接口关系：

* 被调用：``syn-yosys`` target 的 Yosys 进程。
* 调用：TCL ``exit``。
* 共享状态：进程退出码。

§4  ``syn/Makefile`` 中的 Yosys target
------------------------------------------------------------------------------------------------------------------------

职责：:file:`syn/Makefile` 保留 Yosys target 的目的，是让 open-source path 的
失败可复现、可记录，而不是在当前工具条件下宣称综合闭合。

§4.1  工具变量与输出路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/Makefile:L19-L32``）：

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

逐段解释：

* 第 19~23 行：Makefile 推导 :file:`syn/` 目录、仓库根目录、build 目录和默认
  Yosys binary 路径。
* 第 25 行：``YOSYS`` 可以由调用者覆盖；默认值是 :file:`syn/bin/yosys`。
* 第 28~31 行：如果 Yosys path 将来可用，netlist、area、timing、log 的路径都在
  :file:`syn/build/` 下。
* 第 32 行：当前 sentinel 失败时，主要生成的是 :file:`syn/build/syn_yosys.log`。

接口关系：

* 被调用：``make -C syn syn-yosys``。
* 调用：Make 变量展开。
* 共享状态：``YOSYS`` 可由命令行覆盖。

§4.2  ``check-prep`` 前置检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/Makefile:L63-L67``）：

.. code-block:: text

   check-prep:
           @mkdir -p $(BUILD_DIR)
           @test -x $(YOSYS_BIN) || { echo "ERROR: $(YOSYS_BIN) not found"; exit 1; }
           @test -f $(SYN_DIR)/beh_lib_syn.sv || { echo "ERROR: beh_lib_syn.sv not found"; exit 1; }

逐段解释：

* 第 64 行：target 确保 :file:`syn/build` 存在。
* 第 65 行：检查默认 :file:`syn/bin/yosys` 是否可执行。注意这里检查的是
  ``YOSYS_BIN``，不是用户覆盖后的 ``YOSYS``。
* 第 66 行：检查 :file:`syn/beh_lib_syn.sv` 是否存在。该文件是综合准备文件之一。

接口关系：

* 被调用：``syn-yosys`` 和 ``lec`` target 的依赖。
* 调用：shell ``test``。
* 共享状态：读取文件系统中的 tool binary 与支持文件。

§4.3  ``syn-yosys`` target 主体
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/Makefile:L68-L84``）：

.. code-block:: text

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
           @echo ""
           @echo "=== Output summary ==="
           @test -f $(NETLIST)    && echo "  OK  $(NETLIST)    ($(shell wc -l < $(NETLIST) 2>/dev/null || echo 0) lines)" || echo "  --  $(NETLIST)    (not produced — see ADR-0013)"

逐段解释：

* 第 69 行：``syn-yosys`` 依赖 ``check-prep``。前置检查不通过时不会执行 Yosys。
* 第 70~73 行：target 打印流程名、真实 RTL 路径、build 目录和 stdin script 模式。
* 第 74 行：在仓库根目录运行 ``$(YOSYS) -Q``，把
  :file:`syn/yosys/eh2_synth.tcl` 作为 stdin 输入，并把 stdout/stderr 都写入
  :file:`syn/build/syn_yosys.log`。
* 第 75~77 行：target 记录 Yosys exit code，并从 log 中提取 ``ERROR``、
  ``Successfully``、``End of script`` 等关键行。
* 第 80 行：如果 :file:`eh2_synth.v` 不存在，则输出
  ``not produced — see ADR-0013``。这与 sentinel 的失败语义一致。

接口关系：

* 被调用：顶层 ``make syn_yosys`` 或 ``make -C syn syn-yosys``。
* 调用：``$(YOSYS) -Q``、``sed``、``tail``、``test``。
* 共享状态：写 :file:`syn/build/syn_yosys.log`；在成功工具链下可能写 netlist/report。

§4.4  output summary 对缺失产物的处理
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/Makefile:L79-L84``）：

.. code-block:: text

   @echo "=== Output summary ==="
   @test -f $(NETLIST)    && echo "  OK  $(NETLIST)    ($(shell wc -l < $(NETLIST) 2>/dev/null || echo 0) lines)" || echo "  --  $(NETLIST)    (not produced — see ADR-0013)"
   @test -f $(AREA_RPT)   && echo "  OK  $(AREA_RPT)   ($(shell wc -l < $(AREA_RPT) 2>/dev/null || echo 0) lines)" || echo "  --  $(AREA_RPT)   (not produced)"
   @test -f $(TIMING_RPT) && echo "  OK  $(TIMING_RPT) ($(shell wc -l < $(TIMING_RPT) 2>/dev/null || echo 0) lines)" || echo "  --  $(TIMING_RPT) (not produced)"
   @echo "  LOG: $(SYN_LOG)"
   @echo "=== syn-yosys done ==="

逐段解释：

* 第 80 行：netlist 不存在时，Makefile 明确把读者导向 :ref:`adr-0013`。
* 第 81~82 行：area report 与 timing report 不存在时只打印 ``not produced``。
* 第 83 行：无论是否成功产生产物，target 都打印 log 路径，方便审计失败原因。
* 第 84 行：``syn-yosys done`` 只是 target 尾声打印，不代表综合通过。真实状态要看
  exit code、log 和产物存在性。

接口关系：

* 被调用：``syn-yosys`` target 内部。
* 调用：shell ``test -f`` 与 ``wc -l``。
* 共享状态：读取 :file:`syn/build` 中的产物。

§5  与 Design Compiler path 的关系
------------------------------------------------------------------------------------------------------------------------

职责：Yosys path 的失败不是整个 synthesis sign-off 的失败。当前仓库把默认可用
综合路径放在 ``syn-dc``，LEC release path 放在 ``block_lec``。

§5.1  ``syn-dc`` target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 87~92 行：``syn-dc`` 检查 ``dc_shell`` 是否存在；存在时进入
  :file:`syn/build/dc_run` 并运行 :file:`syn/scripts/dc_synth.tcl`。
* 第 93~96 行：``dc_shell`` 缺失时，target 打印错误并退出，且提示 SDC 约束文件
  位于 :file:`syn/nangate/eh2_nangate.sdc`。
* 这段是 ``eh2_synth.tcl`` 第 23 行提示 ``make syn-dc`` 的实际入口。

接口关系：

* 被调用：顶层 ``make syn_dc`` 或 ``make -C syn syn-dc``。
* 调用：``dc_shell -f syn/scripts/dc_synth.tcl``。
* 共享状态：写 :file:`syn/build/dc_run`。

§5.2  ``syn-full`` 的历史组合语义
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/Makefile:L152-L161``）：

.. code-block:: text

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

逐段解释：

* 第 153 行：``syn-full`` 依赖 ``syn-yosys`` 和 ``lec``。在当前 sentinel 状态下，
  这条组合路径不是当前 sign-off 的闭合综合路径。
* 第 157~159 行：target 打印 netlist、report 和 log 路径。
* 第 160 行：输出中再次注明 Yosys 0.55 的 SV import limitation，并指向
  :ref:`adr-0013`。

接口关系：

* 被调用：顶层 ``make synth`` 会转发到 ``make -C syn syn-full``。
* 调用：``syn-yosys`` 与 ``lec``。
* 共享状态：依赖 ``NETLIST``、``AREA_RPT``、``TIMING_RPT``、``SYN_LOG``、
  ``LEC_LOG``。

§6  ADR-0013 中的工具链决策
------------------------------------------------------------------------------------------------------------------------

职责：:ref:`adr-0013` 是本章的 ground truth。它同时记录早期错误、Yosys 阻塞、
DC 修复路径和当前默认综合工具链。

§6.1  早期 ``rvjtag_tap`` 误导性结果
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``docs/adr/0013-synthesis-toolchain.md``）：

.. code-block:: text

   The RC2 `syn_yosys.log` showed `Top module: \rvjtag_tap` (38 cells), implying synthesis
   was performed on the EH2 core. In reality, the synthesized design was the JTAG TAP unit
   only — not the EH2 core (`eh2_veer` / `eh2_veer_wrapper`). This was a dishonest
   representation.

逐段解释：

* ADR 明确指出早期 ``syn_yosys.log`` 的 top module 是 ``rvjtag_tap``，只有
  38 cells，不能代表 EH2 core。
* :file:`syn/yosys/eh2_synth.tcl` 第 19 行写明旧的 ``rvjtag_tap`` 假综合已移除。
* 因此本章不能写"Yosys 已经综合 EH2"，只能写"Yosys path 当前显式失败"。

接口关系：

* 被调用：本章和综合流程文档引用。
* 调用：无。
* 共享状态：ADR 文件是人工决策记录，不是可执行脚本。

§6.2  当前决策：默认使用 Design Compiler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``docs/adr/0013-synthesis-toolchain.md``）：

.. code-block:: text

   ## Decision

   Default synthesis flow: `make syn-dc` using Design Compiler O-2018.06-SP1.
   Open-source flow (yosys) blocked until SV-2017 support matures or sv2v becomes available.

逐段解释：

* ADR 的 Decision 部分指定默认综合流程是 ``make syn-dc``，工具是 Design Compiler
  ``O-2018.06-SP1``。
* 同一段把 open-source flow 状态写为 blocked，解除条件是 SV-2017 支持成熟或
  ``sv2v`` 可用。
* 这与 :file:`syn/yosys/eh2_synth.tcl` 第 11~16 行的 intended/fallback flow
  一致。

接口关系：

* 被调用：综合章节、Yosys 脚本和 release 文档。
* 调用：无。
* 共享状态：工具链决策状态。

§7  常见误读与排查
------------------------------------------------------------------------------------------------------------------------

§7.1  ``syn-yosys done`` 不等于综合成功
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:file:`syn/Makefile` 第 84 行会打印 ``=== syn-yosys done ===``，但这只是 target
尾声，不是 pass/fail 判定。当前判断成功必须同时检查：

* Yosys exit code 是否为 0。
* :file:`syn/build/eh2_synth.v` 是否存在。
* :file:`syn/build/syn_yosys.log` 是否没有第 21 行那类 explicit error。

在当前脚本第 24 行 ``exit 1`` 的状态下，预期行为是失败。

§7.2  ``check-yosys`` 与 ``check-prep`` 的差异
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``check-yosys`` 会检查 ``$(YOSYS)`` 或 PATH 中的 ``yosys``；``check-prep`` 则检查
默认 :file:`syn/bin/yosys` 是否可执行。当前 ``syn-yosys`` 依赖的是
``check-prep``。因此即使命令行覆盖 ``YOSYS=/path/to/yosys``，仍需注意
``check-prep`` 对 ``YOSYS_BIN`` 的检查。

§7.3  与 LEC 的关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``syn/Makefile:lec`` 是 Yosys equivalence path，读取
:file:`syn/lec/eh2_lec.tcl`，依赖 ``check-prep`` 和 ``NETLIST``。当前 sign-off 的
LEC 结果不是这条 path，而是 :doc:`syn_lec` 中说明的 block-level Formality path。

§8  参考资料
------------------------------------------------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0013` — Synthesis Toolchain：Yosys open-source path 与 commercial
  Design Compiler path 的决策记录。

关联章节：

* :doc:`../06_flows/synthesis_flow` — 综合流程说明。
* :doc:`syn_nangate` — Design Compiler / Nangate 综合脚本字典。
* :doc:`syn_lec` — Formality LEC 脚本字典。

源文件绝对路径：

* :file:`/home/host/eh2-veri/syn/yosys/eh2_synth.tcl`
* :file:`/home/host/eh2-veri/syn/Makefile`
* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/docs/adr/0013-synthesis-toolchain.md`
* :file:`/home/host/eh2-veri/syn/README.md`

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
