.. _lint_flow:
.. _06_flows/lint_flow:

Lint 流程 — 详细参考
================================================================================

:status: draft
:source: lint/Makefile; lint/README.md; lint/verible/verible.rules; lint/verible/waivers.vbl; lint/verilator/verilator-config.vlt; lint/verilator/verilator_waiver.vlt
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
--------------------------------------------------------------------------------

读懂本章前，请先确认：

* :ref:`glossary_pretest` — 知道 lint 是 sign-off 的静态质量 stage；
* :ref:`build_flow` — 知道 lint 不生成 ``simv``，也不运行 RTL 仿真；
* :ref:`signoff_flow` — 知道 lint stage FAIL 会阻断 full profile；
* 基础 SystemVerilog 语法：``module``、``always_comb``、``always_ff``、``interface``；
* 基础 waiver 概念：豁免必须有边界和理由，不能用来掩盖真实错误。

Lint 的价值在于尽早暴露语法、风格、未用信号、潜在综合歧义和可维护性问题。EH2 使用
Verible 与 Verilator 双路径：Verible 更偏 SystemVerilog 风格和规则，Verilator 更偏
静态 elaboration 与综合/仿真可疑点。两者都不是仿真器，也不替代 VCS/NC regression。

学完本章你应该能够：

1. 解释 ``make -C lint lint`` 如何展开到 ``lint-verible`` 和 ``lint-verilator``。
2. 区分 Verible rules、Verible waivers、Verilator config 和 Verilator waivers。
3. 在 ``lint/build`` 中找到 blocking error 的来源。
4. 判断一个 waiver 是否有足够理由，是否违反 blanket waiver 禁令。
5. 说明 lint PASS 与 formal/LEC/coverage PASS 的边界。

§1  流程边界
--------------------------------------------------------------------------------

EH2 lint flow 由 :file:`lint/Makefile` 驱动，包含两条工具路径：
``lint-verible`` 和 ``lint-verilator``。顶层 ``lint`` target 依赖这两个 target，
因此完整 lint run 的执行顺序由 Makefile 依赖关系决定。

.. code-block:: text

   make -C lint lint
      |
      |-- lint-verible
      |     |-- find rtl/*.sv and dv/uvm/core_eh2/*.sv
      |     |-- verible-verilog-lint --rules_config --waiver_files <file>
      |     `-- grep "^(E|FATAL|Error)" lint/build/verible.log
      |
      `-- lint-verilator
            |-- find rtl/*.sv
            |-- verilator --lint-only -Wno-fatal -Wno-UNOPTFLAT -Wno-UNUSED ...
            `-- grep "%Error" lint/build/verilator.log

**逐段解释** ：

* ``lint-verible`` 使用的工具是 ``verible-verilog-lint``，不是
  ``verible-verilog-syntax``。它遍历 RTL 和 DV ``.sv`` 文件。
* ``lint-verilator`` 使用 ``verilator --lint-only``，当前输入是 RTL ``.sv`` 文件，
  不包含 DV 文件集合。
* Verible 的 blocking 条件来自 ``verible_errors.txt`` 是否非空；Verilator 的
  blocking 条件来自 log 中是否存在 ``%Error``。
* Makefile 对工具缺失的行为是打印 warning 并跳过对应 tool path；sign-off 是否
  接受跳过由上层 sign-off gate 决定，本章只描述 lint Makefile 行为。

**接口关系** ：

* **上游入口** ：用户、CI 或 sign-off 脚本运行 ``make -C lint lint``。
* **下游工具** ：Verible ``verible-verilog-lint``、Verilator ``verilator``、
  shell ``find``、``grep``、``tee``。
* **共享状态** ：输出写入 :file:`lint/build/`，规则和 waiver 文件来自
  :file:`lint/verible/` 与 :file:`lint/verilator/`。

§1.1  sign-off 状态证据
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当前 full sign-off 记录 lint 为必跑 stage；本章不能把 lint
描述成非门禁检查。

**关键证据** （2026-05-19 01:02 VCS demo）：

.. code-block:: text

   | lint | PASS | 1 | 1 | `lint/build` |
   | csr_unit | PASS | 20 | 20 | `runs/csr_unit` |
   | compliance | PASS | 85 | 88 | `runs/compliance` |
   | formal | PASS | 46 | 46 | `dv/formal/build/ifv_final.log` |
   | syn | PASS | 31635 | 31635 | `syn/build/lec_summary.txt` |

**逐段解释** ：

* 第一行把 lint stage 记录为 ``PASS``，完成数和总数均为 ``1``，
  证据目录为 :file:`lint/build`。
* lint 与 CSR、compliance、formal、syn 同列为 full profile 的 sign-off stage。

**关键代码** （``lint/README.md:L40-L42``）：

.. code-block:: text

   ## Sign-off Integration
   
   Lint is a required sign-off stage in full profile. Lint errors → sign-off FAIL.

**逐段解释** ：

* 第 40 行：README 单独列出 sign-off integration。
* 第 42 行：full profile 中 lint 是 required stage，lint error 会导致 sign-off
  失败。

**接口关系** ：

* **被调用** ：release status 和 sign-off 文档引用 lint 结果。
* **调用** ：无脚本调用；这是文档层证据。
* **共享状态** ：必须与 :file:`lint/build` 中的 lint 输出一致。

§2  ``lint/Makefile`` 全局变量与文件集合
--------------------------------------------------------------------------------

§2.1  路径、工具和配置文件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Makefile 从自身路径推导 repo root，定义 RTL/DV 目录、工具名、规则文件、
waiver 文件和 build 目录。

**关键代码** （``lint/Makefile:L7-L20``）：

.. code-block:: text

   LINT_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
   EH2_ROOT := $(LINT_DIR)/..
   RTL_DIR  := $(EH2_ROOT)/rtl
   DV_DIR   := $(EH2_ROOT)/dv/uvm/core_eh2
   
   VERIBLE  ?= verible-verilog-lint
   VERILATOR ?= verilator
   
   VERIBLE_RULES  := $(LINT_DIR)/verible/verible.rules
   VERIBLE_WAIVERS := $(LINT_DIR)/verible/waivers.vbl
   VERILATOR_WAIVER := $(LINT_DIR)/verilator/verilator_waiver.vlt
   VERILATOR_CONFIG := $(LINT_DIR)/verilator/verilator-config.vlt
   
   BUILD_DIR := $(LINT_DIR)/build

**逐段解释** ：

* 第 7-L10 行：``LINT_DIR`` 使用当前 Makefile 路径计算，``EH2_ROOT`` 是 lint
  目录的上一级；RTL 来自 :file:`rtl/`，DV 来自 :file:`dv/uvm/core_eh2/`。
* 第 12-L13 行：``VERIBLE`` 和 ``VERILATOR`` 都可由命令行覆盖，默认值分别为
  ``verible-verilog-lint`` 和 ``verilator``。
* 第 15-L18 行：Verible 使用 ``verible.rules`` 和 ``waivers.vbl``；Verilator
  使用 ``verilator_waiver.vlt`` 和 ``verilator-config.vlt``。
* 第 20 行：所有 lint 输出目录固定为 :file:`lint/build/`。

**接口关系** ：

* **被调用** ：Makefile 解析阶段和所有 lint target。
* **调用** ：Make 内建函数 ``realpath``、``lastword``。
* **共享状态** ：``VERIBLE``、``VERILATOR`` 可被外部环境或命令行覆盖。

§2.2  SystemVerilog 文件集合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Makefile 用 ``find`` 收集 RTL 和 DV SystemVerilog 文件，并形成 Verible
使用的 ``ALL_SV``。

**关键代码** （``lint/Makefile:L22-L27``）：

.. code-block:: text

   # Collect all SystemVerilog files
   RTL_SV  := $(shell find $(RTL_DIR) -name '*.sv' -type f 2>/dev/null)
   DV_SV   := $(shell find $(DV_DIR) -name '*.sv' -type f 2>/dev/null)
   ALL_SV  := $(RTL_SV) $(DV_SV)
   
   .PHONY: lint lint-verible lint-verilator clean

**逐段解释** ：

* 第 23 行：``RTL_SV`` 是 :file:`rtl/` 下所有 ``*.sv`` 文件。
* 第 24 行：``DV_SV`` 是 :file:`dv/uvm/core_eh2/` 下所有 ``*.sv`` 文件。
* 第 25 行：``ALL_SV`` 将 RTL 和 DV 文件拼接，供 ``lint-verible`` 遍历。
* 第 27 行：``lint``、``lint-verible``、``lint-verilator`` 和 ``clean`` 是 phony
  target，不与同名文件时间戳绑定。

**接口关系** ：

* **被调用** ：Makefile 解析阶段。
* **调用** ：shell ``find``。
* **共享状态** ：读取 :file:`rtl/` 和 :file:`dv/uvm/core_eh2/` 当前文件树。

§2.3  target 拓扑
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``lint`` 聚合 Verible 和 Verilator；``$(BUILD_DIR)`` target 负责创建
输出目录。

**关键代码** （``lint/Makefile:L29-L34``）：

.. code-block:: text

   $(BUILD_DIR):
   	mkdir -p $(BUILD_DIR)
   
   lint: lint-verible lint-verilator
   	@echo "LINT: All linters completed"

**逐段解释** ：

* 第 29-L30 行：需要 :file:`lint/build/` 时执行 ``mkdir -p``。
* 第 32 行：``lint`` target 依赖 ``lint-verible`` 和 ``lint-verilator``。Make 会先
  执行依赖 target，再执行 echo。
* 第 33 行：``LINT: All linters completed`` 只表示两个依赖 target 返回；实际 PASS
  由各 target 的 error gate 决定。

**接口关系** ：

* **被调用** ：``make -C lint lint``。
* **调用** ：``lint-verible``、``lint-verilator``。
* **共享状态** ：写入 :file:`lint/build/`。

§3  ``lint-verible`` 执行路径
--------------------------------------------------------------------------------

§3.1  初始化、工具检查和逐文件运行
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``lint-verible`` 创建 build 目录，清空 error 文件，检查 Verible 工具，
并对 ``ALL_SV`` 中每个文件执行 ``verible-verilog-lint``。

**关键代码** （``lint/Makefile:L35-L46``）：

.. code-block:: text

   lint-verible: $(BUILD_DIR)
   	@echo "=== Verible SystemVerilog Lint ==="
   	@> $(BUILD_DIR)/verible_errors.txt
   	@if command -v $(VERIBLE) >/dev/null 2>&1; then \
   		lint_errors=0; \
   		for f in $(ALL_SV); do \
   			$(VERIBLE) --rules_config=$(VERIBLE_RULES) \
   				--waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | tee -a $(BUILD_DIR)/verible.log; \
   			if [ $${PIPESTATUS[0]} -ne 0 ]; then \
   				lint_errors=$$((lint_errors + 1)); \
   			fi; \
   		done; \

**逐段解释** ：

* 第 35-L37 行：target 依赖 ``$(BUILD_DIR)``，打印 Verible 阶段名，并清空
  ``verible_errors.txt``。
* 第 38-L39 行：只有 ``command -v $(VERIBLE)`` 成功时才进入 lint loop，并初始化
  ``lint_errors``。
* 第 40-L42 行：循环遍历 ``ALL_SV``，对每个文件传入 ``--rules_config`` 和
  ``--waiver_files``，并把 stdout/stderr 追加到 ``verible.log``。
* 第 43-L45 行：通过 Bash ``PIPESTATUS[0]`` 读取 Verible 命令本身的退出码，而
  不是 ``tee`` 的退出码；非零时递增 ``lint_errors``。

**接口关系** ：

* **被调用** ：``lint`` target 或用户直接运行 ``make -C lint lint-verible``。
* **调用** ：``verible-verilog-lint``、``tee``。
* **共享状态** ：读取 ``ALL_SV``；写入 ``lint/build/verible.log`` 和
  ``lint/build/verible_errors.txt``。

§3.2  Verible blocking gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Verible target 不直接使用 ``lint_errors`` 决定最终状态，而是从 log 中
抽取 ``E``、``FATAL`` 或 ``Error`` 开头的行。

**关键代码** （``lint/Makefile:L47-L58``）：

.. code-block:: text

   		grep -E "^(E|FATAL|Error)" $(BUILD_DIR)/verible.log > $(BUILD_DIR)/verible_errors.txt 2>/dev/null || true; \
   		if [ -s $(BUILD_DIR)/verible_errors.txt ]; then \
   			echo "BLOCKING: Verible lint errors:"; \
   			cat $(BUILD_DIR)/verible_errors.txt; \
   			echo "Verible lint FAILED"; \
   			exit 1; \
   		else \
   			echo "Verible lint PASSED (0 errors)"; \
   		fi; \
   	else \
   		echo "WARNING: verible-verilog-lint not found, skipping"; \
   	fi

**逐段解释** ：

* 第 47 行：``grep`` 将匹配 error 关键字的行写入 ``verible_errors.txt``；
  ``|| true`` 防止无匹配时 grep 的退出码中断 shell。
* 第 48-L52 行：如果 ``verible_errors.txt`` 非空，target 打印 blocking message、
  输出 error 文件内容，并 ``exit 1``。
* 第 53-L55 行：error 文件为空时打印 ``Verible lint PASSED (0 errors)``。
* 第 56-L58 行：工具不存在时打印 warning 并跳过。该分支没有生成 PASS 证据。

**接口关系** ：

* **被调用** ：Verible loop 结束后执行。
* **调用** ：``grep``、``cat``、``exit``。
* **共享状态** ：读取 ``verible.log``；写入并读取 ``verible_errors.txt``。

§3.3  Verible rules
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`lint/verible/verible.rules` 显式启用 style、naming 和 synthesis
safety 规则，同时为 DV/UVM 宏禁用一个 RTL 风格规则。

**关键代码** （``lint/verible/verible.rules:L6-L30``）：

.. code-block:: text

   # ─── Style rules ───
   enable: forbid-line-continuations
   enable: forbid-defparam
   enable: forbid-consecutive-null-statements
   
   # ─── Naming ───
   # EH2 module naming convention: eh2_<block>_<unit>
   enable: module-filename
   enable: explicit-function-lifetime
   enable: explicit-task-lifetime
   
   # ─── Synthesis safety ───
   enable: always-comb
   enable: always-comb-blocking
   enable: always-ff-non-blocking
   enable: case-missing-default
   enable: no-trailing-spaces
   enable: no-tabs
   
   # ─── UVM/DV rules ───
   # DV code uses class-based SystemVerilog; relax some RTL rules for DV
   disable: forbid-consecutive-null-statements  # UVM macros produce empty statements
   
   # ─── Waived rules (tracked in waivers.vbl) ───
   # See waivers.vbl for per-file/per-line waivers with reasons

**逐段解释** ：

* 第 6-L9 行：启用 line continuation、defparam 和 consecutive null statement 相关
  style rules。
* 第 11-L15 行：启用 module filename、function lifetime、task lifetime 规则；注释
  说明 EH2 module 命名约定是 ``eh2_<block>_<unit>``。
* 第 17-L23 行：启用 ``always_comb``、blocking/non-blocking、case default、
  trailing space、tab 等 synthesis safety 和格式规则。
* 第 25-L27 行：DV 使用 class-based SystemVerilog，因此禁用
  ``forbid-consecutive-null-statements``，注释指向 UVM macro 产生的 empty
  statements。
* 第 29-L30 行：per-file/per-line waiver 不写在 rules 文件中，而在
  :file:`lint/verible/waivers.vbl` 中跟踪。

**接口关系** ：

* **被调用** ：``lint-verible`` 通过 ``--rules_config`` 传入。
* **调用** ：Verible rule engine。
* **共享状态** ：与 ``waivers.vbl`` 一起决定 Verible 输出。

§3.4  Verible waiver policy file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`lint/verible/waivers.vbl` 记录 waiver 格式和分类，当前内容主要是
带 reason 的示例和类别约束。

**关键代码** （``lint/verible/waivers.vbl:L1-L22``）：

.. code-block:: text

   # EH2 Verible Waivers
   #
   # Waiver format: waiver --rule=<rule> --line=<line> [--regex] "reason"
   # Each waiver MUST have a reason explaining why the violation is acceptable.
   #
   # Waiver categories:
   #   STYLE    — line-length, no-trailing-spaces, parameter-name-style
   #   VENDOR   — third-party RTL not EH2's to fix (rvjtag_tap, AXI4_TO_AHB, etc.)
   #   QUALITY  — implicit truncation, unused signal — MUST NOT waive, fix the RTL
   #   DV-ONLY  — UVM/SV testbench constructs not applicable to synthesizable RTL
   
   # ─── Style waivers ───
   # STYLE: line-length violations in wide parameter lists — cosmetic only
   # waive --rule=line-length --line=1 "EH2 parameter lists exceed 100 chars per convention"
   
   # ─── Vendor RTL waivers (Cores-VeeR-EH2 origin files) ───
   # VENDOR: rvjtag_tap — imported JTAG TAP controller, not EH2-authored
   # waive --rule=module-filename --file="*/rvjtag_tap.sv" "VENDOR: rvjtag_tap from third-party"
   
   # ─── DV waivers ───
   # DV-ONLY: UVM macro expansions may trigger specific rules; document each
   # waive --rule=no-trailing-spaces --line=42 "DV-ONLY: UVM `uvm_info macro generated whitespace"

**逐段解释** ：

* 第 1-L4 行：文件头说明 waiver 语法，并要求每个 waiver 都有 reason。
* 第 6-L10 行：waiver 分为 STYLE、VENDOR、QUALITY、DV-ONLY；其中 QUALITY 类
  明确标注 ``MUST NOT waive``，要求修 RTL。
* 第 12-L18 行：style 和 vendor waiver 当前以注释示例形式存在。
* 第 20-L22 行：DV-only waiver 示例说明 UVM macro expansion 可以触发特定规则，
  但仍需逐条记录。

**接口关系** ：

* **被调用** ：``lint-verible`` 通过 ``--waiver_files`` 传入。
* **调用** ：Verible waiver parser。
* **共享状态** ：waiver 不在 :file:`dv/uvm/core_eh2/waivers/`，而在
  :file:`lint/verible/waivers.vbl`。

§4  ``lint-verilator`` 执行路径
--------------------------------------------------------------------------------

§4.1  Verilator 命令行
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``lint-verilator`` 检查工具存在性，运行 ``verilator --lint-only``，加载
config 和 waiver 文件，并把 log 写入 :file:`lint/build/verilator.log`。

**关键代码** （``lint/Makefile:L60-L69``）：

.. code-block:: text

   lint-verilator:
   	@echo "=== Verilator Lint ==="
   	@if command -v $(VERILATOR) >/dev/null 2>&1; then \
   		$(VERILATOR) --lint-only \
   			-Wno-fatal \
   			-Wno-UNOPTFLAT \
   			-Wno-UNUSED \
   			$(VERILATOR_CONFIG) \
   			$(VERILATOR_WAIVER) \
   			$(RTL_SV) 2>&1 | tee $(BUILD_DIR)/verilator.log; \

**逐段解释** ：

* 第 60-L62 行：target 打印阶段名，并通过 ``command -v`` 检查 ``$(VERILATOR)``。
* 第 63 行：``--lint-only`` 表示只做 lint，不生成仿真 binary。
* 第 64-L66 行：命令行关闭 fatal、UNOPTFLAT、UNUSED warning 的 fatal 影响或输出。
  这不等同于放行 ``%Error``。
* 第 67-L68 行：传入 Verilator config 和 waiver 文件。
* 第 69 行：输入文件是 ``$(RTL_SV)``，日志通过 ``tee`` 写入
  ``verilator.log``。

**接口关系** ：

* **被调用** ：``lint`` target 或用户直接运行 ``make -C lint lint-verilator``。
* **调用** ：``verilator --lint-only``、``tee``。
* **共享状态** ：读取 RTL ``.sv`` 文件；写 :file:`lint/build/verilator.log`。

§4.2  Verilator blocking gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：Verilator target 使用 ``%Error`` 作为 blocking 关键字。

**关键代码** （``lint/Makefile:L70-L79``）：

.. code-block:: text

   		if grep -qE "%Error" $(BUILD_DIR)/verilator.log; then \
   			echo "BLOCKING: Verilator lint errors found"; \
   			grep -E "%Error" $(BUILD_DIR)/verilator.log; \
   			exit 1; \
   		else \
   			echo "Verilator lint PASSED"; \
   		fi; \
   	else \
   		echo "WARNING: verilator not found, skipping"; \
   	fi

**逐段解释** ：

* 第 70 行：grep 在 ``verilator.log`` 中查找 ``%Error``。
* 第 71-L73 行：发现 error 时打印 blocking message、列出 error 行，并退出
  ``1``。
* 第 74-L76 行：未发现 ``%Error`` 时打印 ``Verilator lint PASSED``。
* 第 77-L79 行：工具缺失时打印 warning 并跳过。

**接口关系** ：

* **被调用** ：Verilator 命令结束后执行。
* **调用** ：``grep``、``exit``。
* **共享状态** ：读取 :file:`lint/build/verilator.log`。

§4.3  Verilator config
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`lint/verilator/verilator-config.vlt` 启用 Verilator lint 规则，并
保留 include path 和 coverage exclusion 的注释配置。

**关键代码** （``lint/verilator/verilator-config.vlt:L1-L22``）：

.. code-block:: text

   // EH2 Verilator Lint Configuration
   //
   // Configure Verilator lint run for EH2 RTL and DV code.
   // Based on lowRISC Ibex's lint/verilator/verilator-config.vlt.
   
   `verilator_config
   
   // ─── Lint rules ───
   lint_on -rule UNUSED
   lint_on -rule BLKSEQ
   lint_on -rule WIDTH
   lint_on -rule LITENDIAN
   
   // ─── EH2-specific configuration ───
   // Top module: not applicable in lint mode (analyze-all)
   // Include paths
   // +incdir+rtl/design/include
   // +incdir+dv/uvm/core_eh2/env
   
   // ─── Coverage exclusion (lint only, not coverage) ───
   // These constructs are intentional in EH2 RTL
   // lint_off -rule COMBDLY -file "*" -match "*"

**逐段解释** ：

* 第 1-L6 行：文件声明为 Verilator config，并使用 ``verilator_config`` directive。
* 第 8-L12 行：启用 ``UNUSED``、``BLKSEQ``、``WIDTH``、``LITENDIAN`` lint rule。
* 第 14-L18 行：include path 当前是注释形式，没有被该 config 文件实际启用。
* 第 20-L22 行：COMBDLY waiver 也处于注释状态；文件只说明这些构造在 lint only
  场景下可按需处理。

**接口关系** ：

* **被调用** ：``lint-verilator`` 作为命令行参数传入。
* **调用** ：Verilator config parser。
* **共享状态** ：与 :file:`lint/verilator/verilator_waiver.vlt` 共同影响
  Verilator lint 输出。

§4.4  Verilator waiver skeleton
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`lint/verilator/verilator_waiver.vlt` 定义 waiver 分类和注释示例；
当前没有未注释的 ``lint_off`` 规则。

**关键代码** （``lint/verilator/verilator_waiver.vlt:L1-L27``）：

.. code-block:: text

   // EH2 Verilator Lint Waiver File
   //
   // Based on lowRISC Ibex's lint/verilator/verilator_waiver.vlt.
   // Each waiver MUST have a comment explaining the reason.
   //
   // Categories:
   //   STYLE    — cosmetic issues (UNUSED on intentional placeholders)
   //   DV-ONLY  — UVM testbench constructs not synthesis-safe
   //   VENDOR   — third-party RTL not EH2's to fix
   
   `verilator_config
   
   // ─── RTL waivers ───
   // Add waivers as needed after initial lint run.
   // Example:
   //   lint_off -rule UNUSED -file "*/eh2_dec_tlu_ctl.sv" -match "Signal not used: *"
   //   STYLE: Signal retained for clarity in NUM_THREADS=1 configuration
   
   // ─── DV waivers ───
   // DV-ONLY: UVM testbench code intentionally uses constructs not synthesis-safe
   // lint_off -rule BLKSEQ -file "*/eh2_*_agent/*" -match "*"
   // Waive reason: UVM agents use blocking assignments in class methods
   
   // ─── Third-party waivers ───
   // VENDOR: Third-party code not EH2's responsibility to fix
   // lint_off -rule UNUSED -file "*/vendor/*" -match "*"
   // Waive reason: VENDOR third-party code

**逐段解释** ：

* 第 1-L9 行：文件头说明 waiver 必须有 comment reason，并列出 STYLE、DV-ONLY、
  VENDOR 三类。
* 第 11 行：文件使用 ``verilator_config`` directive。
* 第 13-L18 行：RTL waiver 目前是示例；示例说明 ``UNUSED`` 可在有 reason 的情况
  下针对具体文件和 match 表达式关闭。
* 第 19-L27 行：DV 和 third-party waiver 同样是注释示例。由于
  ``lint-verilator`` 当前只传入 ``RTL_SV``，这些 DV/vendor 示例不是当前命令行的
  必然输入。

**接口关系** ：

* **被调用** ：``lint-verilator`` 作为命令行参数传入。
* **调用** ：Verilator config parser。
* **共享状态** ：当前没有 active waiver；后续若启用 waiver，应保持 reason 注释。

§5  ``lint-quick`` 与 ``clean``
--------------------------------------------------------------------------------

§5.1  ``lint-quick``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``lint-quick`` 只对 RTL 文件运行 Verible，并只显示每个文件输出的前
5 行。它不是完整 lint gate。

**关键代码** （``lint/Makefile:L81-L87``）：

.. code-block:: text

   # Quick lint: verible only, RTL only
   lint-quick:
   	@echo "=== Quick Verible Lint (RTL only) ==="
   	@for f in $(RTL_SV); do \
   		$(VERIBLE) --rules_config=$(VERIBLE_RULES) \
   			--waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | head -5; \
   	done

**逐段解释** ：

* 第 81-L83 行：注释和 echo 都说明这是 quick path，范围是 RTL only。
* 第 84-L86 行：循环遍历 ``RTL_SV``，用同一套 Verible rules 和 waivers 运行，
  但通过 ``head -5`` 截断输出。
* 第 87 行：循环结束后没有 grep gate 或 error file 检查，因此不能替代
  ``lint-verible``。

**接口关系** ：

* **被调用** ：用户手工执行 ``make -C lint lint-quick``。
* **调用** ：``verible-verilog-lint``、``head``。
* **共享状态** ：读取 ``RTL_SV``；不写 ``verible_errors.txt``。

§5.2  ``clean``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``clean`` 删除 :file:`lint/build/`。

**关键代码** （``lint/Makefile:L89-L90``）：

.. code-block:: text

   clean:
   	rm -rf $(BUILD_DIR)

**逐段解释** ：

* 第 89 行：定义 ``clean`` target。
* 第 90 行：删除 ``$(BUILD_DIR)``，即 :file:`lint/build/`。这属于 lint 输出目录清理，
  不会修改源 RTL、DV、rules 或 waiver 文件。

**接口关系** ：

* **被调用** ：用户执行 ``make -C lint clean``。
* **调用** ：``rm -rf``。
* **共享状态** ：删除 :file:`lint/build/`。

§6  目录结构与 waiver policy
--------------------------------------------------------------------------------

§6.1  README 目录结构
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`lint/README.md` 给出 lint 目录布局、使用命令和 waiver policy。

**关键代码** （``lint/README.md:L5-L17``）：

.. code-block:: text

   ## Structure
   
   ```
   lint/
   ├── verible/          # SystemVerilog style/lint
   │   ├── verible.rules # Enabled/disabled lint rules
   │   └── waivers.vbl   # Per-file/per-line waivers
   ├── verilator/        # Verilator lint mode
   │   ├── verilator_waiver.vlt  # Waived violations
   │   └── verilator-config.vlt  # Lint configuration
   ├── README.md
   └── Makefile
   ```

**逐段解释** ：

* 第 5-L11 行：Verible rules 和 waiver 位于 :file:`lint/verible/`。
* 第 12-L14 行：Verilator waiver 和 config 位于 :file:`lint/verilator/`。
* 第 15-L17 行：lint 目录还包含 README 和 Makefile。

**关键代码** （``lint/README.md:L19-L30``）：

.. code-block:: bash

   ## Usage
   
   ```bash
   # Run both linters
   make lint
   
   # Run Verible only
   make lint-verible
   
   # Run Verilator only
   make lint-verilator
   ```

**逐段解释** ：

* 第 19-L23 行：完整 lint 命令是 ``make lint``。
* 第 25-L29 行：Verible 和 Verilator 可以分别通过 ``make lint-verible`` 与
  ``make lint-verilator`` 单独运行。

**接口关系** ：

* **被调用** ：开发者查阅 lint 目录说明。
* **调用** ：README 不调用脚本；命令会进入 :file:`lint/Makefile`。
* **共享状态** ：目录结构必须与 Makefile 中的路径变量一致。

§6.2  waiver policy
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：README 明确 waiver 的人工审查规则；配置文件中的示例必须符合这些规则。

**关键代码** （``lint/README.md:L32-L38``）：

.. code-block:: text

   ## Waiver Policy
   
   1. Every waiver MUST have a reason comment explaining why the violation is acceptable
   2. Waivers are reviewed at each release checkpoint
   3. No "blanket" waivers (e.g., waiving all rules for a file without specific reasons)
   4. DV code waivers are acceptable for UVM-specific constructs
   5. Third-party (vendor/) code violations are waived but tracked

**逐段解释** ：

* 第 34 行：每个 waiver 都必须有 reason comment。
* 第 35 行：waiver 在每个 release checkpoint 复审。
* 第 36 行：禁止没有具体原因的 blanket waiver。
* 第 37-L38 行：DV 代码 waiver 可用于 UVM-specific constructs；third-party
  代码 violation 可以 waiver，但需要跟踪。

**接口关系** ：

* **被调用** ：编写或审查 ``waivers.vbl``、``verilator_waiver.vlt`` 时使用。
* **调用** ：无脚本调用。
* **共享状态** ：policy 与两类 waiver 文件中的注释和示例保持一致。

§7  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`appendix_c_tools/lint_verible`、:ref:`appendix_c_tools/lint_verilator`、
  :ref:`signoff_flow`。
* 结果证据：2026-05-19 01:02 VCS 主线 sign-off 摘要、:file:`lint/build/`。
* 源文件绝对路径：
  :file:`/home/host/eh2-veri/lint/Makefile`、
  :file:`/home/host/eh2-veri/lint/README.md`、
  :file:`/home/host/eh2-veri/lint/verible/verible.rules`、
  :file:`/home/host/eh2-veri/lint/verible/waivers.vbl`、
  :file:`/home/host/eh2-veri/lint/verilator/verilator-config.vlt`、
  :file:`/home/host/eh2-veri/lint/verilator/verilator_waiver.vlt`。

§8  常见失败模式与排查
--------------------------------------------------------------------------------

.. list-table:: Lint 常见失败模式
   :header-rows: 1
   :widths: 24 30 30 16

   * - 现象
     - 根因
     - 排查命令
     - 修复路径
   * - ``verible-verilog-lint`` not found
     - Verible 未安装或 PATH 未设置
     - ``which verible-verilog-lint``
     - 修环境，不要改源码绕过
   * - ``verible_errors.txt`` 非空
     - 触发 blocking Verible rule
     - ``cat lint/build/verible_errors.txt``
     - 修对应 SV，或补有理由 waiver
   * - ``%Error`` 出现在 Verilator log
     - 静态 elaboration 或语法问题
     - ``rg -n "%Error" lint/build/verilator.log``
     - 优先修 RTL，不先加 waiver
   * - waiver 被审查打回
     - 缺 reason 或范围过宽
     - ``sed -n '1,120p' lint/verible/waivers.vbl``
     - 缩小路径/行号并写清原因
   * - sign-off lint FAIL
     - lint stage 收集到 error
     - ``rg -n "lint" build/signoff_vcs/signoff_report.md``
     - 回到 ``lint/build`` 看原始工具日志

§9  动手练习
--------------------------------------------------------------------------------

入门题（5 分钟）：

.. code-block:: bash

   cd /home/host/eh2-veri
   make -C lint lint-quick

记录命令是否找到 Verible/Verilator；如果工具缺失，说明缺的是环境而不是 RTL。

进阶题（30 分钟）：

.. code-block:: bash

   sed -n '1,120p' lint/verible/verible.rules
   sed -n '1,120p' lint/verilator/verilator-config.vlt

分别写下一个 Verible rule 和一个 Verilator warning 配置，并说明它们为何属于 lint
而不是仿真。

挑战题（1 小时）：

任选 ``lint/verible/waivers.vbl`` 或 ``lint/verilator/verilator_waiver.vlt`` 中一条
waiver，按 §6.2 的 policy 检查它是否有理由、是否具体到文件/规则、是否可能掩盖真实
RTL bug。

§10  自检 5 问
--------------------------------------------------------------------------------

1. Verible 与 Verilator 的 lint 关注点有什么差异？
2. 为什么 tool missing 不应被描述成“RTL 通过 lint”？
3. blocking gate 分别检查 ``verible_errors.txt`` 和 ``%Error`` 的原因是什么？
4. 什么是 blanket waiver？为什么禁止？
5. lint PASS 不能替代哪几类动态或形式验证？

§11  下一步
--------------------------------------------------------------------------------

完成本章后，继续阅读 :ref:`formal_flow` 和 :ref:`lec_flow`，把静态规则检查、形式证明
和逻辑等价检查放到同一个 sign-off 质量框架下理解。函数和规则级细节见
:ref:`appendix_c_tools/lint_verible` 与 :ref:`appendix_c_tools/lint_verilator`。
