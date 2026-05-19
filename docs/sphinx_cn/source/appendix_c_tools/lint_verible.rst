.. _appendix_c_tools_lint_verible:
.. _appendix_c_tools/lint_verible:

Verible Lint 源码字典
========================================================================================================================

:status: draft
:source: lint/Makefile
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 EH2 lint 基础设施中的 Verible 路径。实际执行工具是
``verible-verilog-lint``，不是只做语法解析的 ``verible-verilog-syntax``。
Verible target 会遍历 RTL 与 DV SystemVerilog 文件，加载规则配置和 waiver 文件，
将日志写入 :file:`lint/build/verible.log`，再从日志中抽取 blocking error。

本章覆盖 4 个源文件：

* :file:`lint/Makefile`：Verible target、文件收集、error gate。
* :file:`lint/verible/verible.rules`：启用和禁用的 Verible rule。
* :file:`lint/verible/waivers.vbl`：waiver 格式和类别。
* :file:`lint/README.md`：lint 目录结构、使用命令和 sign-off policy。

§2  ``lint/Makefile`` 的全局变量
------------------------------------------------------------------------------------------------------------------------

职责：Makefile 首先定位 lint 目录、仓库根、RTL/DV 目录，并定义 Verible 工具、
rule 文件、waiver 文件和 build 目录。

关键代码（``lint/Makefile:L7-L20``）：

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

逐段解释：

* 第 7~10 行：``LINT_DIR`` 从当前 Makefile 路径推导，``EH2_ROOT`` 是其上一级。
  RTL 文件来自 :file:`rtl/`，DV 文件来自 :file:`dv/uvm/core_eh2`。
* 第 12 行：Verible 工具默认是 ``verible-verilog-lint``，可由命令行覆盖
  ``VERIBLE=/path/to/tool``。
* 第 15~16 行：Verible target 使用
  :file:`lint/verible/verible.rules` 与 :file:`lint/verible/waivers.vbl`。
* 第 20 行：所有 lint 输出写到 :file:`lint/build`。

接口关系：

* 被调用：``make -C lint lint-verible`` 和 ``make -C lint lint``。
* 调用：Make 变量展开。
* 共享状态：``VERIBLE`` 可由外部覆盖。

§3  文件集合与 target 关系
------------------------------------------------------------------------------------------------------------------------

职责：Verible path 同时检查 RTL 和 DV SystemVerilog 文件。顶层 ``lint`` target
依赖 Verible 和 Verilator 两条路径。

§3.1  SystemVerilog 文件收集
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L22-L27``）：

.. code-block:: text

   # Collect all SystemVerilog files
   RTL_SV  := $(shell find $(RTL_DIR) -name '*.sv' -type f 2>/dev/null)
   DV_SV   := $(shell find $(DV_DIR) -name '*.sv' -type f 2>/dev/null)
   ALL_SV  := $(RTL_SV) $(DV_SV)

   .PHONY: lint lint-verible lint-verilator clean

逐段解释：

* 第 23 行：``RTL_SV`` 由 ``find $(RTL_DIR) -name '*.sv'`` 生成。
* 第 24 行：``DV_SV`` 由 ``find $(DV_DIR) -name '*.sv'`` 生成。
* 第 25 行：``ALL_SV`` 把 RTL 与 DV 文件拼接，供 Verible target 使用。
* 第 27 行：``lint``、``lint-verible``、``lint-verilator`` 和 ``clean`` 都是
  phony target。

接口关系：

* 被调用：Make 解析阶段。
* 调用：shell ``find``。
* 共享状态：读取 :file:`rtl/` 和 :file:`dv/uvm/core_eh2/`。

§3.2  总 lint target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L29-L34``）：

.. code-block:: text

   $(BUILD_DIR):
           mkdir -p $(BUILD_DIR)

   lint: lint-verible lint-verilator
           @echo "LINT: All linters completed"

逐段解释：

* 第 29~30 行：需要输出目录时创建 :file:`lint/build`。
* 第 32 行：``lint`` target 先跑 ``lint-verible``，再跑 ``lint-verilator``。
* 第 33 行：该 echo 只表示两个 target 执行结束；是否通过由各 target 的退出码决定。

接口关系：

* 被调用：``make -C lint lint``。
* 调用：``lint-verible`` 与 ``lint-verilator``。
* 共享状态：``BUILD_DIR``。

§4  ``lint-verible`` 执行流程
------------------------------------------------------------------------------------------------------------------------

职责：``lint-verible`` 是 blocking gate。只要日志中抽取到 ``E``、``FATAL`` 或
``Error`` 开头的行，就输出错误并退出 1。

§4.1  初始化和工具检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L35-L39``）：

.. code-block:: text

   lint-verible: $(BUILD_DIR)
           @echo "=== Verible SystemVerilog Lint ==="
           @> $(BUILD_DIR)/verible_errors.txt
           @if command -v $(VERIBLE) >/dev/null 2>&1; then \
                   lint_errors=0; \

逐段解释：

* 第 35 行：``lint-verible`` 依赖 :file:`lint/build` 目录。
* 第 36 行：打印 Verible lint 阶段标题。
* 第 37 行：清空或创建 :file:`lint/build/verible_errors.txt`，避免沿用旧错误。
* 第 38~39 行：只有 ``command -v $(VERIBLE)`` 成功时才执行 Verible；否则进入
  skip 分支。

接口关系：

* 被调用：``lint`` target 或用户直接运行 ``lint-verible``。
* 调用：shell ``command -v``。
* 共享状态：写 :file:`lint/build/verible_errors.txt`。

§4.2  遍历 ``ALL_SV`` 并追加日志
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L40-L47``）：

.. code-block:: text

   for f in $(ALL_SV); do \
           $(VERIBLE) --rules_config=$(VERIBLE_RULES) \
                   --waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | tee -a $(BUILD_DIR)/verible.log; \
           if [ $${PIPESTATUS[0]} -ne 0 ]; then \
                   lint_errors=$$((lint_errors + 1)); \
           fi; \
   done; \
   grep -E "^(E|FATAL|Error)" $(BUILD_DIR)/verible.log > $(BUILD_DIR)/verible_errors.txt 2>/dev/null || true; \

逐段解释：

* 第 40 行：target 遍历 ``ALL_SV``，即 RTL 和 DV 的全部 ``.sv`` 文件。
* 第 41~42 行：每个文件调用 ``$(VERIBLE)``，并加载
  ``--rules_config=$(VERIBLE_RULES)`` 与 ``--waiver_files=$(VERIBLE_WAIVERS)``。
* 第 42 行：stdout/stderr 通过 ``tee -a`` 追加到
  :file:`lint/build/verible.log`。
* 第 43~45 行：如果 Verible 进程退出码非 0，``lint_errors`` 自增。该变量只在
  shell 片段内部计数，最终 gate 还会基于错误文件判断。
* 第 47 行：从完整 log 中 grep 以 ``E``、``FATAL`` 或 ``Error`` 开头的行，写入
  :file:`lint/build/verible_errors.txt`。``|| true`` 防止没有匹配时 grep 的
  非零状态中断 shell 片段。

接口关系：

* 被调用：工具存在时执行。
* 调用：``verible-verilog-lint``、``tee``、``grep``。
* 共享状态：读取 ``ALL_SV`` 文件；写 :file:`verible.log` 与
  :file:`verible_errors.txt`。

§4.3  blocking error gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L48-L58``）：

.. code-block:: text

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

逐段解释：

* 第 48 行：``-s`` 检查错误文件是否存在且非空。
* 第 49~52 行：如果有 blocking error，target 打印错误内容、声明 failed，并
  ``exit 1``。
* 第 53~55 行：错误文件为空时打印 ``Verible lint PASSED (0 errors)``。
* 第 56~58 行：如果工具不存在，target 打印 warning 并跳过。这是当前 Makefile
  行为；sign-off 是否允许跳过由上层流程决定，不能在本页推断。

接口关系：

* 被调用：Verible 遍历完成后。
* 调用：shell ``test -s``、``cat``、``exit``。
* 共享状态：读取 :file:`lint/build/verible_errors.txt`。

§5  quick Verible target
------------------------------------------------------------------------------------------------------------------------

职责：``lint-quick`` 只跑 RTL 文件，并只显示每个文件输出的前 5 行。它适合快速
查看 Verible 是否能启动，不等同于 full lint gate。

关键代码（``lint/Makefile:L81-L87``）：

.. code-block:: text

   # Quick lint: verible only, RTL only
   lint-quick:
           @echo "=== Quick Verible Lint (RTL only) ==="
           @for f in $(RTL_SV); do \
                   $(VERIBLE) --rules_config=$(VERIBLE_RULES) \
                           --waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | head -5; \
           done

逐段解释：

* 第 81~83 行：注释和标题都说明该 target 是 RTL-only quick lint。
* 第 84 行：循环输入是 ``RTL_SV``，不包含 DV 文件。
* 第 85~86 行：仍加载同一套 Verible rule 与 waiver，但输出被 ``head -5`` 截断。
* 该 target 没有生成 ``verible_errors.txt``，也没有 blocking gate。

接口关系：

* 被调用：用户手工运行 ``make -C lint lint-quick``。
* 调用：``verible-verilog-lint``、``head``。
* 共享状态：读取 ``RTL_SV`` 文件。

§6  ``verible.rules`` 规则文件
------------------------------------------------------------------------------------------------------------------------

职责：规则文件定义 Verible lint 的启用/禁用规则。该文件既包含 RTL 风格约束，
也包含 DV/UVM 特例。

§6.1  style 与 naming 规则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verible/verible.rules:L1-L16``）：

.. code-block:: text

   # EH2 Verible Lint Rules
   #
   # Based on lowRISC Ibex's lint/verible/verible.rules, adapted for EH2.
   # See https://github.com/chipsalliance/verible for rule documentation.

   # ─── Style rules ───
   enable: forbid-line-continuations
   enable: forbid-defparam
   enable: forbid-consecutive-null-statements

   # ─── Naming ───
   # EH2 module naming convention: eh2_<block>_<unit>
   enable: module-filename
   enable: explicit-function-lifetime
   enable: explicit-task-lifetime

逐段解释：

* 第 1~4 行：文件说明规则基于 lowRISC Ibex 规则并针对 EH2 修改。
* 第 7~9 行：style 规则启用禁止行续接、禁止 ``defparam``、禁止连续空语句。
* 第 12~15 行：命名和生命周期规则启用 module-filename、explicit function
  lifetime、explicit task lifetime。

接口关系：

* 被调用：``lint-verible`` 通过 ``--rules_config`` 加载。
* 调用：无。
* 共享状态：规则名必须是 Verible 支持的规则名。

§6.2  synthesis safety 与 DV 放宽
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verible/verible.rules:L17-L30``）：

.. code-block:: text

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

逐段解释：

* 第 18~23 行：synthesis safety 规则覆盖 ``always_comb``、``always_ff`` nonblocking、
  missing default、trailing spaces 和 tabs。
* 第 26~27 行：DV code 使用 class-based SystemVerilog，因此禁用
  ``forbid-consecutive-null-statements``，注释说明 UVM macro 可能生成空语句。
* 第 29~30 行：具体 waiver 不放在规则文件，而在 :file:`waivers.vbl` 中追踪。

接口关系：

* 被调用：Verible rule parser。
* 调用：无。
* 共享状态：与 :file:`lint/verible/waivers.vbl` 配合。

§7  ``waivers.vbl`` waiver 策略
------------------------------------------------------------------------------------------------------------------------

职责：waiver 文件定义格式和分类，要求每条 waiver 都有理由。当前文件中的示例
waiver 均以注释形式存在，不会实际屏蔽规则。

§7.1  waiver 格式与类别
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verible/waivers.vbl:L1-L11``）：

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

逐段解释：

* 第 3 行：格式要求包含 rule、line，可选 regex，并带 reason 字符串。
* 第 4 行：每条 waiver 必须说明为什么可接受。
* 第 7~10 行：分类包括 STYLE、VENDOR、QUALITY、DV-ONLY。
* 第 9 行：QUALITY 类问题标注为 ``MUST NOT waive``，应修 RTL。

接口关系：

* 被调用：``lint-verible`` 通过 ``--waiver_files`` 加载。
* 调用：无。
* 共享状态：与 Verible 报告的 rule/line 匹配。

§7.2  注释示例与实际生效边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verible/waivers.vbl:L12-L22``）：

.. code-block:: text

   # ─── Style waivers ───
   # STYLE: line-length violations in wide parameter lists — cosmetic only
   # waive --rule=line-length --line=1 "EH2 parameter lists exceed 100 chars per convention"

   # ─── Vendor RTL waivers (Cores-VeeR-EH2 origin files) ───
   # VENDOR: rvjtag_tap — imported JTAG TAP controller, not EH2-authored
   # waive --rule=module-filename --file="*/rvjtag_tap.sv" "VENDOR: rvjtag_tap from third-party"

   # ─── DV waivers ───
   # DV-ONLY: UVM macro expansions may trigger specific rules; document each
   # waive --rule=no-trailing-spaces --line=42 "DV-ONLY: UVM `uvm_info macro generated whitespace"

逐段解释：

* 第 12~14 行：style waiver 示例仍被 ``#`` 注释，不会生效。
* 第 16~18 行：vendor waiver 示例针对 ``rvjtag_tap``，同样是注释。
* 第 20~22 行：DV-only waiver 示例说明 UVM macro 可能触发规则，但未实际启用。
* 因为所有 ``waive`` 行都以 ``#`` 开头，当前文件主要是 policy skeleton，而不是
  active waiver set。

接口关系：

* 被调用：Verible waiver parser 读取文件时忽略注释行。
* 调用：无。
* 共享状态：无 active waiver。

§8  README 中的使用与 sign-off policy
------------------------------------------------------------------------------------------------------------------------

职责：:file:`lint/README.md` 给出目录结构、常用命令和 sign-off 集成边界。

关键代码（``lint/README.md:L19-L30``）：

.. code-block:: text

   ## Usage

   ```bash
   # Run both linters
   make lint

   # Run Verible only
   make lint-verible

   # Run Verilator only
   make lint-verilator
   ```

逐段解释：

* 第 22~23 行：``make lint`` 同时运行 Verible 和 Verilator。
* 第 25~26 行：``make lint-verible`` 只运行 Verible target。
* 第 28~29 行：``make lint-verilator`` 只运行 Verilator target。

关键代码（``lint/README.md:L32-L42``）：

.. code-block:: text

   ## Waiver Policy

   1. Every waiver MUST have a reason comment explaining why the violation is acceptable
   2. Waivers are reviewed at each release checkpoint
   3. No "blanket" waivers (e.g., waiving all rules for a file without specific reasons)
   4. DV code waivers are acceptable for UVM-specific constructs
   5. Third-party (vendor/) code violations are waived but tracked

   ## Sign-off Integration

   Lint is a required sign-off stage in full profile. Lint errors → sign-off FAIL.

逐段解释：

* 第 34~38 行：waiver policy 要求理由、release checkpoint 审查、禁止 blanket
  waiver，并区分 DV 和 third-party code。
* 第 42 行：lint 是 full profile 的 required sign-off stage，lint error 会导致
  sign-off FAIL。

接口关系：

* 被调用：文档读者和 release checklist。
* 调用：无。
* 共享状态：与 :file:`lint/Makefile` 中 blocking gate 一致。

§9  参考资料
------------------------------------------------------------------------------------------------------------------------

关联章节：

* :doc:`../06_flows/lint_flow` — lint 流程说明。
* :doc:`lint_verilator` — Verilator lint 源码字典。

源文件绝对路径：

* :file:`/home/host/eh2-veri/lint/Makefile`
* :file:`/home/host/eh2-veri/lint/verible/verible.rules`
* :file:`/home/host/eh2-veri/lint/verible/waivers.vbl`
* :file:`/home/host/eh2-veri/lint/README.md`

§10  v2-9 Verible/CI 审计
------------------------------------------------------------------------------------------------------------------------

本地 Verible gate 和 GitHub Actions gate 不是同一个入口：本地 ``lint/Makefile`` 会遍历
RTL 与 DV ``.sv`` 文件，并加载 :file:`lint/verible/verible.rules`；
CI workflow 当前只对 :file:`dv/uvm/core_eh2` 下的 ``.sv/.svh`` 做 Verible lint。
review 时必须分清这两个范围，不能把 CI 的 DV-only 检查误写成完整 RTL+DV lint。

关键代码（``.github/workflows/lint.yml:L19-L36``）：

.. literalinclude:: ../../../../.github/workflows/lint.yml
   :language: yaml
   :lines: 19-36
   :caption: /home/host/eh2-veri/.github/workflows/lint.yml:L19-L36

逐段解释：

* 第 L19-L25 行：CI 用 ``find dv/uvm/core_eh2 -name '*.sv' -o -name '*.svh'`` 收集 DV
  文件，然后通过 ``xargs verible-verilog-lint`` 运行。
* 第 L25-L26 行：CI 传入 ``--rules=-line-length,-no-trailing-spaces`` 和
  ``--waiver_files=dv/uvm/core_eh2/fcov/cov_waivers/*.yaml``；这是 CI 特定配置，
  与本地 ``lint/verible/waivers.vbl`` 不同。
* 第 L28-L36 行：CI gate 只要 ``lint_report.txt`` 出现 ``E`` 或 ``FATAL`` 开头行就失败。

审计结论：

* 本地 full lint 章节继续以 :file:`lint/Makefile` 为主，覆盖 ``ALL_SV``。
* CI 章节应引用 :file:`.github/workflows/lint.yml`，说明它是 pull request 上的快速
  DV lint gate。
* :file:`dv/uvm/core_eh2/fcov/cov_waivers/*.yaml` 是 coverage waiver YAML，不是
  Verible 原生 ``waivers.vbl``；CI 当前把它传给 Verible 是源码事实，后续若改动需同步本文。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？
