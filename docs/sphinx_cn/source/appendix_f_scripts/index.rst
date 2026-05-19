.. _appendix_f_scripts_index:
.. _appendix_f_scripts/index:

附录 F — 脚本字典
==================

:status: draft
:source: Makefile; env.mk; env.sh; dv/uvm/core_eh2/scripts; dv/uvm/core_eh2/yaml
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本附录边界
--------------

本附录覆盖 EH2 验证平台的脚本、Makefile、Shell 入口和 YAML 配置。它的目标不是
替代每个深度章节，而是说明读者应该先进入哪个脚本字典：

* :ref:`appendix_f_scripts/core_eh2_scripts`：22 个 Python 脚本和
  :file:`dv/uvm/core_eh2/scripts/report_lib/`。
* :ref:`appendix_f_scripts/makefiles`：顶层 :file:`Makefile`、:file:`env.mk`、
  :file:`dv/uvm/core_eh2/Makefile` 和 :file:`dv/uvm/core_eh2/scripts/*.mk`。
* :ref:`appendix_f_scripts/top_scripts`：:file:`env.sh`、workspace 清理、
  RC self-check、PDF manual build、``objdump.sh`` 和 ``prettify.sh``。
* :ref:`appendix_f_scripts/yaml_configs`：:file:`eh2_configs.yaml`、RTL simulation
  YAML、directed/cosim testlist、以及 cosim-disabled waiver YAML。

路径核对结果：当前工作树中存在
:file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`，不存在根目录
:file:`waivers/cosim-disabled.yaml`。因此本附录只引用实际存在的
:file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`。

§2  脚本体系数据流
------------------

::

   top-level Makefile
      |
      +--> env.mk defaults
      |
      +--> dv/uvm/core_eh2/Makefile convenience targets
      |
      +--> dv/uvm/core_eh2/scripts/run_regress.py
      |       |
      |       +--> metadata.py / directed_test_schema.py
      |       +--> run_instr_gen.py / compile_test.py / run_rtl.py
      |       +--> check_logs.py / collect_results.py
      |       +--> gen_html_report.py / report_lib/*
      |
      +--> signoff.py
      |       |
      |       +--> coverage, formal, LEC, compliance, CSR, lint gates
      |
      +--> top shell scripts
              |
              +--> env.sh
              +--> scripts/clean_workspace.sh
              +--> scripts/rc4_self_check.sh / scripts/rc5_self_check.sh

逐段解释：

* 顶层 :file:`Makefile` 是大多数用户命令的第一入口。它包含旧式
  ``make run GOAL=...`` wrapper 分支，也包含当前中文 help 中列出的
  compile、regress、signoff、lint、synth、formal、compliance、manual 和 clean
  分组。
* :file:`dv/uvm/core_eh2/scripts/run_regress.py` 是 Python regression 主控。
  它读取 testlist，生成或定位汇编，编译 binary，运行 RTL simulation，检查日志，
  然后生成 JSON/HTML/JUnit/text 报告。
* :file:`signoff.py` 属于同一脚本目录，但职责不是单次 regression；它聚合 smoke、
  directed、cosim、riscv-dv、lint、CSR、compliance、formal、syn/LEC 和 coverage
  gate。
* Shell 脚本只负责环境或维护动作；其中 :file:`scripts/clean_workspace.sh` 的默认
  preserve 列表会保留当前签核证据和昂贵缓存。

§3  Python 脚本分流
-------------------

``dv/uvm/core_eh2/scripts`` 顶层当前有 22 个 ``.py`` 文件。深度解释见
:ref:`appendix_f_scripts/core_eh2_scripts`，本页只给入口关系。

关键代码（``dv/uvm/core_eh2/scripts/run_regress.py:L447-L498``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(
           description="EH2 Regression Runner",
           formatter_class=argparse.RawDescriptionHelpFormatter,
           epilog="""
   Examples:
     %(prog)s --testlist riscv_dv_extension/testlist.yaml
     %(prog)s --test riscv_random_instr_test --seed 42 --simulator vcs
     %(prog)s --testlist testlist.yaml --iterations 5 --parallel 4
           """
       )

       # Test selection
       parser.add_argument("--testlist", help="Test list YAML file")
       parser.add_argument("--test", help="Run a single test")
       parser.add_argument("--iterations", type=int, help="Override iterations count")
       parser.add_argument("--seed", type=int, help="Override random seed")

逐段解释：

* 第 447~456 行：``main()`` 用 ``argparse`` 定义 regression CLI，并在 epilog
  中给出 testlist、single-test 和 parallel run 三种示例。
* 第 459~463 行：test selection 参数支持 YAML testlist、单个 test、iterations
  覆盖和 seed 覆盖。
* 后续参数继续定义 ``--rtl-test``、``--gen-opts``、``--sim-opts``、``--binary``、
  ``--disable-cosim``、``--coverage``、``--waves``、``--fail-on-warnings``、
  ``--simulator``、``--output`` 和 ``--parallel``；这些参数在深度章节中逐项说明。

接口关系：

* 被调用：顶层 Makefile、CI、人工命令行。
* 调用：``metadata.py``、``directed_test_schema.py``、``check_logs.py``、
  ``collect_results.py``，以及外部 simulator/toolchain。
* 共享状态：输出目录、seed、testlist、simulator、coverage 和 cosim policy。

§4  Makefile 分流
-----------------

Makefile 章节说明顶层目标如何把变量传给 Python、UVM 本地 Makefile、lint/formal/syn
子目录。深度解释见 :ref:`appendix_f_scripts/makefiles`。

关键代码（``Makefile:L137-L151``）：

.. code-block:: makefile

   # Sign-off
   PROFILE         ?= full
   GATE_ONLY       ?= 0
   CLEANUP         ?= 0
   SIGNOFF_OUT     ?= $(BUILD_DIR)/signoff
   SIGNOFF_OPTS    ?=
   SIGNOFF_ITERATIONS ?=
   LEC_KNOWN_LIMITED  ?= 0
   LEC_BLOCKLEVEL  ?= 1
   LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt

   # Sign-off coverage gates
   SIGNOFF_MIN_LINE_COV       ?= 65
   SIGNOFF_MIN_FUNCTIONAL_COV ?= 40
   SIGNOFF_ALLOW_WARNINGS     ?= 1

逐段解释：

* 第 138~146 行：顶层 Makefile 用变量控制 sign-off profile、gate-only、cleanup、
  输出目录、iteration 覆盖和 LEC summary 路径。
* 第 145 行：``LEC_BLOCKLEVEL`` 默认值是 ``1``，因此当前主线默认走 block-level LEC
  summary 路径。
* 第 149~151 行：coverage gate 的默认门限是 line ``65``、functional ``40``，
  并允许 warning；这些是 Makefile 变量，不是 release 覆盖率结果。

接口关系：

* 被调用：用户在仓库根目录执行 ``make``。
* 调用：Python 脚本、子目录 Makefile、EDA 工具、Shell 维护脚本。
* 共享状态：``build`` 目录、``SIGNOFF_OUT``、coverage DB、LEC summary、formal
  evidence。

§5  Shell 脚本分流
------------------

Shell 脚本章节覆盖环境设置、workspace 清理、自检和 PDF manual 构建。深度解释见
:ref:`appendix_f_scripts/top_scripts`。

关键代码（``env.sh:L5-L19``）：

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

* 第 6 行：``EH2_VERIF_ROOT`` 通过当前脚本路径推导，不依赖调用者所在目录。
* 第 9 行：``RV_ROOT`` 指向外部 EH2 RTL source 根目录。
* 第 12~13 行：``GCC_PREFIX`` 进入 ``PATH``，供汇编测试和 riscv-dv 编译使用。
* 第 16 行：``QEMU_BIN`` 给 QEMU cosim 或相关外部入口预留路径。
* 第 19 行：默认 simulator 是 ``vcs``。

接口关系：

* 被调用：用户通过 ``source env.sh`` 加载环境。
* 调用：shell 内建、路径展开和环境变量 export。
* 共享状态：当前 shell 的 ``PATH``、``EH2_VERIF_ROOT``、``RV_ROOT``、
  ``GCC_PREFIX``、``EH2_SIMULATOR``。

§6  YAML 配置分流
-----------------

YAML 章节覆盖配置 profile、仿真命令模板、directed/cosim testlist 和 waiver。
深度解释见 :ref:`appendix_f_scripts/yaml_configs`。

关键代码（``eh2_configs.yaml:L5-L16``）：

.. code-block:: yaml

   default:
     description: "Default EH2 configuration (AXI4, single-thread, full features)"
     parameters:
       # Threading
       NUM_THREADS: 1
       # Bus
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0
       BUILD_AXI_NATIVE: 1
       LSU_BUS_TAG: 4
       IFU_BUS_TAG: 4
       SB_BUS_TAG: 1

逐段解释：

* 第 5~7 行：``default`` profile 是一个带 ``description`` 和 ``parameters`` 的
  YAML map。
* 第 9 行：``NUM_THREADS`` 在 default profile 中为 ``1``；dual-thread profile
  在同一文件后续段落中把它设为 ``2``。
* 第 11~16 行：bus 相关参数选择 AXI4、关闭 AHB-Lite，并列出 LSU/IFU/SB bus tag
  参数。

接口关系：

* 被调用：配置渲染脚本、Makefile 和仿真脚本读取这些 YAML。
* 调用：YAML parser，不直接调用 simulator。
* 共享状态：DUT parameter profile、simulator 命令模板、testlist entry、cosim
  waiver gate。

§7  章节选择规则
----------------

.. list-table::
   :header-rows: 1
   :widths: 32 68

   * - 你要查的问题
     - 应进入的章节
   * - 某个 Python 函数、类或 CLI 参数如何工作
     - :ref:`appendix_f_scripts/core_eh2_scripts`
   * - ``make signoff``、``make regress``、``LEC_BLOCKLEVEL`` 或 clean preserve 规则
     - :ref:`appendix_f_scripts/makefiles`
   * - ``env.sh`` 导出什么变量，清理脚本保留什么 evidence
     - :ref:`appendix_f_scripts/top_scripts`
   * - YAML profile、testlist、simulator template 或 cosim-disabled waiver
     - :ref:`appendix_f_scripts/yaml_configs`
   * - CLI 总览、参数语义和脚本互调关系
     - :ref:`scripts_reference`
   * - UVM 类如何消费这些参数
     - :ref:`appendix_b_uvm/index`
   * - Formal、Lint、Syn、LEC 工具源码
     - :ref:`appendix_c_tools/index`

§8  当前签核数字边界
--------------------

本脚本附录可以引用签核数字，但不能从脚本默认值推导签核结果。当前
2026-05-19 01:02 VCS 主线 demo 证据数字如下：

* sign-off：``9/9`` stages PASS。
* 实跑覆盖率：``102/104`` （98.1%）。
* formal：``46/46``。
* LEC：``31635/31635``。
* compliance：``85/88`` （96.59%）。
* riscv-dv：``370/395`` （93.67%）。
* directed：``40/40``。
* coverage：LINE ``95.05%``、BRANCH ``84.97%``、TOGGLE ``53.52%``、
  ASSERT ``33.33%``、FSM ``54.74%``、GROUP ``69.42%``、OVERALL ``65.17%``。

这些数字来自 release/status 证据，不来自本索引页的源码片段。脚本章节解释的是
这些证据如何被生成、收集或引用。

§9  参考资料
------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/env.mk`
* :file:`/home/host/eh2-veri/env.sh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/report_lib/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/yaml/rtl_simulation.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
* :file:`/home/host/eh2-veri/scripts/clean_workspace.sh`
* :file:`/home/host/eh2-veri/scripts/rc4_self_check.sh`
* :file:`/home/host/eh2-veri/scripts/rc5_self_check.sh`
* :file:`/home/host/eh2-veri/docs/build_manual_pdf.sh`

关联章节：

* :ref:`appendix_f_scripts/core_eh2_scripts`
* :ref:`appendix_f_scripts/makefiles`
* :ref:`appendix_f_scripts/top_scripts`
* :ref:`appendix_f_scripts/yaml_configs`
* :ref:`scripts_reference`
* :ref:`appendix_c_tools/index`

§10  v2-9 脚本资产审计
----------------------

v2-9 对脚本附录做文件级审计，确认 ``dv/uvm/core_eh2/scripts`` 的 Python、Makefile
fragment、report library 和单元测试都有入口。深度源码精读仍在
:ref:`appendix_f_scripts/core_eh2_scripts`；本节只给 review checklist。

.. list-table::
   :header-rows: 1
   :widths: 28 30 42

   * - 脚本族
     - 归属章节
     - 审计结论
   * - ``signoff.py`` / ``merge_cov.py`` / ``gen_html_report.py``
     - :ref:`appendix_f_scripts/core_eh2_scripts`
     - 9-stage gate、URG/IMC coverage merge 和 HTML dashboard 是 release 证据核心。
   * - ``run_regress.py`` / ``run_rtl.py`` / ``compile_tb.py`` / ``run_instr_gen.py``
     - :ref:`appendix_f_scripts/core_eh2_scripts`
     - regression、single RTL run、TB compile 和 riscv-dv generation 入口。
   * - ``check_logs.py`` / ``metadata.py`` / ``scripts_lib.py``
     - :ref:`appendix_f_scripts/core_eh2_scripts`
     - log 判定、Ibex-style metadata 和公共命令封装。
   * - ``report_lib/*.py``
     - :ref:`appendix_f_scripts/core_eh2_scripts`
     - HTML/text/JUnit/dvsim JSON/SVG 输出库。
   * - ``scripts/*.mk``
     - :ref:`appendix_f_scripts/makefiles`
     - ``riscvdv.mk``、``eh2_sim.mk``、``util.mk``、``get_meta.mk`` 均为 Makefile
       fragment。
   * - ``scripts/tests/test_*.py``
     - :ref:`appendix_f_scripts/core_eh2_scripts`
     - 覆盖 regression framework、HTML coverage parsing 和 sign-off gate 行为。

关键代码（``dv/uvm/core_eh2/scripts/gen_html_report.py:L24-L48``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/gen_html_report.py
   :language: python
   :lines: 24-48
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/scripts/gen_html_report.py:L24-L48

逐段解释：

* 第 L24-L27 行：默认输入仍指向历史 ``r3b_final`` 产物；sign-off flow 会通过 CLI 传入当前
  ``build/signoff_vcs`` 或 ``build/signoff_nc`` 路径。
* 第 L29-L39 行：HTML dashboard 展开 stage 顺序，其中 summary 阶段包含 ``formal`` 和 ``syn``。
* 第 L41-L48 行：coverage metric 列包含 line、toggle、fsm、branch、assert 和 functional/group。

关键代码（``dv/uvm/core_eh2/scripts/tests/test_parse_coverage.py:L9-L25``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/tests/test_parse_coverage.py
   :language: python
   :lines: 9-25
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/scripts/tests/test_parse_coverage.py:L9-L25

逐段解释：

* 第 L9-L18 行：单元测试保留 URG legacy header 中 ``COND`` 的 parser 兼容性。
* 第 L19-L25 行：断言 parser 能提取 line、cond、toggle、fsm、assert 和 overall；
  这不代表当前 VCS release coverage 启用 cond，当前主线仍是
  ``line+tgl+assert+fsm+branch`` 五维。

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
