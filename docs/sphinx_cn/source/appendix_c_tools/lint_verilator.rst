.. _appendix_c_tools_lint_verilator:
.. _appendix_c_tools/lint_verilator:

Verilator Lint 源码字典
========================================================================================================================

:status: draft
:source: lint/Makefile
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 EH2 lint 基础设施中的 Verilator 路径。Verilator target 只对 RTL
SystemVerilog 文件运行 ``verilator --lint-only``，加载 config 与 waiver 文件，
将日志写入 :file:`lint/build/verilator.log`，再通过 ``%Error`` 关键字决定
blocking gate。

本章覆盖 4 个源文件：

* :file:`lint/Makefile`：``lint-verilator`` target 与 error gate。
* :file:`lint/verilator/verilator-config.vlt`：Verilator lint rule 配置。
* :file:`lint/verilator/verilator_waiver.vlt`：Verilator waiver skeleton。
* :file:`lint/README.md`：使用命令与 sign-off policy。

§2  ``lint/Makefile`` 中的 Verilator 变量
------------------------------------------------------------------------------------------------------------------------

职责：Makefile 定义 Verilator tool、配置文件、waiver 文件和 RTL file set。
与 Verible 不同，Verilator target 当前只输入 ``RTL_SV``。

关键代码（``lint/Makefile:L7-L25``）：

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
   ...
   RTL_SV  := $(shell find $(RTL_DIR) -name '*.sv' -type f 2>/dev/null)
   DV_SV   := $(shell find $(DV_DIR) -name '*.sv' -type f 2>/dev/null)
   ALL_SV  := $(RTL_SV) $(DV_SV)

逐段解释：

* 第 7~10 行：目录变量与 Verible 共用，``RTL_DIR`` 指向 :file:`rtl/`，``DV_DIR``
  指向 :file:`dv/uvm/core_eh2`。
* 第 13 行：``VERILATOR`` 默认是 ``verilator``，可由命令行覆盖。
* 第 17~18 行：Verilator path 使用 :file:`verilator_waiver.vlt` 与
  :file:`verilator-config.vlt`。
* 第 23~25 行：Makefile 同时收集 RTL 和 DV ``.sv`` 文件，但 Verilator target
  后续只使用 ``RTL_SV``。

接口关系：

* 被调用：``make -C lint lint-verilator``。
* 调用：Make 变量和 shell ``find``。
* 共享状态：``VERILATOR`` 可由外部覆盖。

§3  ``lint-verilator`` target 主流程
------------------------------------------------------------------------------------------------------------------------

职责：``lint-verilator`` 检查工具是否存在，执行 Verilator lint，把 log 写到
:file:`lint/build/verilator.log`，并把 ``%Error`` 作为 blocking 条件。

§3.1  Verilator 命令行
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L60-L69``）：

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

逐段解释：

* 第 60~62 行：target 打印阶段名，并用 ``command -v`` 检查 ``$(VERILATOR)``。
* 第 63 行：核心模式是 ``--lint-only``，不会生成仿真 binary。
* 第 64~66 行：命令行显式加入 ``-Wno-fatal``、``-Wno-UNOPTFLAT``、
  ``-Wno-UNUSED``。这些是 Verilator warning 控制，不是对 ``%Error`` 的放行。
* 第 67~68 行：随后传入 config 与 waiver 文件。
* 第 69 行：输入文件是 ``$(RTL_SV)``，日志通过 ``tee`` 写入
  :file:`lint/build/verilator.log`。

接口关系：

* 被调用：``lint`` target 或用户直接运行 ``lint-verilator``。
* 调用：``verilator --lint-only``、``tee``。
* 共享状态：读取 RTL ``.sv`` 文件；写 :file:`verilator.log`。

§3.2  ``%Error`` blocking gate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/Makefile:L70-L79``）：

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

逐段解释：

* 第 70 行：gate 条件是 log 中存在 ``%Error``。
* 第 71~73 行：发现 error 时打印 blocking message、列出 error 行，并退出 1。
* 第 74~76 行：没有 ``%Error`` 时打印 ``Verilator lint PASSED``。
* 第 77~79 行：工具不存在时打印 warning 并跳过。这是 Makefile 当前行为，不等同于
  sign-off 允许跳过。

接口关系：

* 被调用：Verilator 命令结束后。
* 调用：``grep``、``exit``。
* 共享状态：读取 :file:`lint/build/verilator.log`。

§4  ``verilator-config.vlt`` 配置文件
------------------------------------------------------------------------------------------------------------------------

职责：config 文件启用 Verilator lint rule，并记录 EH2 lint mode 的 include path
注释和 coverage-exclusion 注释。

§4.1  配置文件头与启用规则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verilator/verilator-config.vlt:L1-L13``）：

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

逐段解释：

* 第 1~4 行：文件说明该配置用于 EH2 Verilator lint，并参考 lowRISC Ibex。
* 第 6 行：`` `verilator_config`` 声明该文件是 Verilator 配置文件。
* 第 9~12 行：显式打开 ``UNUSED``、``BLKSEQ``、``WIDTH`` 和 ``LITENDIAN`` 规则。

接口关系：

* 被调用：``lint-verilator`` 命令行直接把该文件作为参数传给 Verilator。
* 调用：Verilator config directive。
* 共享状态：规则名由 Verilator 支持。

§4.2  include path 与 lint-only 注释
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verilator/verilator-config.vlt:L14-L22``）：

.. code-block:: text

   // ─── EH2-specific configuration ───
   // Top module: not applicable in lint mode (analyze-all)
   // Include paths
   // +incdir+rtl/design/include
   // +incdir+dv/uvm/core_eh2/env

   // ─── Coverage exclusion (lint only, not coverage) ───
   // These constructs are intentional in EH2 RTL
   // lint_off -rule COMBDLY -file "*" -match "*"

逐段解释：

* 第 15 行：注释说明 lint mode 是 analyze-all，不指定 top module。
* 第 16~18 行：include path 只以注释形式记录，当前 Verilator 命令行没有把这些
  ``+incdir`` 注释转成参数。
* 第 20~22 行：coverage exclusion 也是注释；``COMBDLY`` 的 ``lint_off`` 示例未实际
  生效。

接口关系：

* 被调用：Verilator 读取该 config 文件。
* 调用：无 active ``lint_off`` 指令。
* 共享状态：当前 active rule 是 §4.1 中的 ``lint_on``。

§5  ``verilator_waiver.vlt`` waiver 文件
------------------------------------------------------------------------------------------------------------------------

职责：waiver 文件定义 waiver 分类和示例。当前 waiver 示例全部是注释，不会实际关闭
Verilator rule。

§5.1  文件头与类别
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verilator/verilator_waiver.vlt:L1-L12``）：

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

逐段解释：

* 第 1~4 行：文件要求每条 waiver 都有 reason comment。
* 第 6~9 行：分类包括 STYLE、DV-ONLY 和 VENDOR。
* 第 11 行：文件本身是 Verilator config 格式。

接口关系：

* 被调用：``lint-verilator`` 命令行直接传入。
* 调用：Verilator config directive。
* 共享状态：后续 active waiver 必须写在该文件中。

§5.2  RTL、DV 和 third-party waiver 示例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``lint/verilator/verilator_waiver.vlt:L13-L27``）：

.. code-block:: text

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

逐段解释：

* 第 13~17 行：RTL waiver 示例说明 ``UNUSED`` 可以因 ``NUM_THREADS=1`` 配置保留
  而被注释记录，但当前未启用。
* 第 19~22 行：DV waiver 示例针对 UVM agent 中的 blocking assignment，同样是注释。
* 第 24~27 行：third-party waiver 示例针对 :file:`vendor/`，要求 reason 标注为
  VENDOR。
* 因为这些 ``lint_off`` 行都以 ``//`` 开头，当前文件没有 active waiver。

接口关系：

* 被调用：Verilator 解析 waiver 文件。
* 调用：无 active ``lint_off``。
* 共享状态：无 active waiver。

§6  README 中的命令和 sign-off policy
------------------------------------------------------------------------------------------------------------------------

职责：:file:`lint/README.md` 给出 Verilator target 的用户入口和 full profile
sign-off 边界。

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

* 第 22~23 行：``make lint`` 会运行 Verible 和 Verilator 两条路径。
* 第 28~29 行：只运行 Verilator 的命令是 ``make lint-verilator``。

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

* 第 34~38 行：waiver policy 要求 reason、release checkpoint review、禁止 blanket
  waiver。
* 第 42 行：lint error 会导致 full profile sign-off fail。

接口关系：

* 被调用：文档读者、release checklist。
* 调用：无。
* 共享状态：与 ``lint/Makefile`` 的 blocking gate 一致。

§7  Verible 与 Verilator 的边界
------------------------------------------------------------------------------------------------------------------------

Verible target 使用 ``ALL_SV``，即 RTL 和 DV 全部 ``.sv`` 文件；Verilator target
当前只使用 ``RTL_SV``。Verible 的 gate 依据
:file:`lint/build/verible_errors.txt` 是否非空；Verilator 的 gate 依据
:file:`lint/build/verilator.log` 中是否存在 ``%Error``。

这两个 target 都会在工具缺失时打印 warning 并跳过。该行为来自 Makefile 源码；
在 release sign-off 中是否允许跳过，需要由上层 sign-off gate 判定，不能仅凭
本 Makefile 的 warning 分支推断为 PASS。

§8  参考资料
------------------------------------------------------------------------------------------------------------------------

关联章节：

* :doc:`../06_flows/lint_flow` — lint 流程说明。
* :doc:`lint_verible` — Verible lint 源码字典。

源文件绝对路径：

* :file:`/home/host/eh2-veri/lint/Makefile`
* :file:`/home/host/eh2-veri/lint/verilator/verilator-config.vlt`
* :file:`/home/host/eh2-veri/lint/verilator/verilator_waiver.vlt`
* :file:`/home/host/eh2-veri/lint/README.md`

§9  v2-9 Verilator waiver 审计
------------------------------------------------------------------------------------------------------------------------

v2-9 审计确认：当前 Verilator waiver 文件只有 policy skeleton，没有 active ``lint_off``。
因此 full lint 的 Verilator 结果主要由命令行 ``-Wno-fatal``、``-Wno-UNOPTFLAT``、
``-Wno-UNUSED`` 和 ``verilator-config.vlt`` 的 ``lint_on`` 决定。若后续新增 active
waiver，必须在本章增加逐条原因。

关键代码（``lint/verilator/verilator_waiver.vlt:L13-L27``）：

.. literalinclude:: ../../../../lint/verilator/verilator_waiver.vlt
   :language: text
   :lines: 13-27
   :caption: /home/host/eh2-veri/lint/verilator/verilator_waiver.vlt:L13-L27

逐段解释：

* 第 L13-L17 行：RTL waiver 示例被注释保留，说明 ``UNUSED`` 可能因单线程配置保留信号而
  需要 style waiver。
* 第 L19-L22 行：DV waiver 示例同样被注释；当前 Verilator target 实际只输入 ``RTL_SV``，
  不会用它放行 UVM class 代码。
* 第 L24-L27 行：third-party waiver 示例要求标注 ``VENDOR``，但当前也未生效。

审计结论：当前文件没有 active waiver；``%Error`` 仍是 blocking gate。

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
