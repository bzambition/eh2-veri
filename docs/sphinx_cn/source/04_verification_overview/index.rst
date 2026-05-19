.. _verification_overview_index:
.. _04_verification_overview/index:

验证平台总览
============

:status: draft
:source: README.md; docs/PROJECT_STATUS.md; Makefile; dv/uvm/core_eh2/scripts/signoff.py; docs/sphinx_cn/source/index.rst; docs/sphinx_cn/source/04_verification_overview/goals_scope.rst; docs/sphinx_cn/source/04_verification_overview/quickstart.rst; docs/sphinx_cn/source/04_verification_overview/ibex_capability_matrix.rst
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本部分边界
--------------

本部分是 EH2-Veri 中文手册的第四部分，职责是回答三个进入验证平台前必须先确认的问题：

* 当前 VCS 主线 demo 到底验证什么，哪些 stage 和 coverage gate 属于 sign-off 范围。
* 第一次进入仓库时，应使用哪些当前有效命令，而不是旧文档里的 deprecated alias。
* EH2 验证平台借鉴了 Ibex 哪些方法，又在哪些 DUT surface 上必须偏离 Ibex。

它不展开 UVM class、脚本实现、RTL 模块或 EDA tool flow 的逐文件细节；这些内容分别由
:ref:`verification_arch_index`、:ref:`flows_index`、:ref:`appendix_a_rtl/index`、
:ref:`appendix_b_uvm/index`、:ref:`appendix_c_tools/index` 和
:ref:`appendix_f_scripts/index` 承接。

关键代码（`docs/sphinx_cn/source/index.rst:L64-L72`）：

.. code-block:: bash

   .. toctree::
      :maxdepth: 2
      :caption: 第四部分 — 验证平台总览
      :numbered:
   
      04_verification_overview/index
      04_verification_overview/goals_scope
      04_verification_overview/quickstart
      04_verification_overview/ibex_capability_matrix

逐段解释：

* 第 L64-L67 行：顶层 `index.rst` 把本部分作为单独 toctree，并启用编号显示。
* 第 L69-L72 行：本部分固定包含 4 个现有页面：本页、验证目标与范围、快速上手、
  Ibex 能力对比。本次改写不新增/删除 toctree 条目。
* 这些条目决定了读者进入验证平台总览时的顺序：先看总览，再看 scope，再跑命令，
  最后理解 Ibex 对标关系。

接口关系：

* 被调用：顶层中文手册 toctree、读者导航、签核 review 入口。
* 调用：:ref:`goals_scope`、:ref:`quickstart`、:ref:`ibex_capability_matrix`。
* 共享状态：当前签核数字、sign-off stage、coverage gate、Ibex 对标边界。

§2  release 数字的来源
----------------------

本部分所有签核可见数字必须来自当前 status 记录，而不能从旧审计、
旧构建目录或人工推断中提取。当前 project status 明确给出 demo 日期、top-level
status 和主要 release artifact。

关键代码（`docs/PROJECT_STATUS.md:L1-L15`）：

.. code-block:: bash

   # EH2 Verification Platform Project Status
   
   Version: **v1.1**
   
   Date: **2026-05-19 01:02**
   
   Industrial score: **4.99/5**
   
   Top-level sign-off: **PASS**
   
   Primary status artifact: `build/demo/signoff_status.json`
   
   Primary HTML dashboard: `build/demo/report.html`
   
   Primary Markdown report: `build/demo/signoff_report.md`

逐段解释：

* 第 L1-L5 行：当前 demo 时间是 2026-05-19 01:02。
* 第 L7-L9 行：status 文档记录 industrial score 和 top-level sign-off；本页只引用
  `PASS` 状态，不重新计算 score。
* 第 L11-L15 行：primary artifacts 分别是 JSON、HTML dashboard 和 Markdown report。
  本部分后续章节引用这些路径时必须保持字面一致。

接口关系：

* 被调用：:ref:`goals_scope` 的范围定义和本页 sign-off 摘要。
* 调用：`build/demo/signoff_status.json`、`build/demo/report.html`、
  `build/demo/signoff_report.md`。
* 共享状态：2026-05-19 01:02、top-level PASS。

§3  验证平台主数据流
--------------------

README 把 EH2-Veri 的数据流定义为：sign-off orchestration 汇总 stage 输出，
UVM environment 产生 trace item 和 probe hint，DUT 退休指令流进入 Spike DPI，
scoreboard 使用 Spike 作为 architectural reference model。

关键代码（`README.md:L43-L74`）：

.. code-block:: bash

   ## Architecture
   
   The core data path is RTL retire trace plus DUT probes into a UVM scoreboard,
   with Spike DPI acting as the architectural reference model.
   
   ```text
      ┌─────────────────────────────────────────────────────────────┐
      │                    Sign-off Orchestration                   │
      │  signoff.py  gen_html_report.py  collect_results.py         │
      └────────────────────────────┬────────────────────────────────┘
                                   │ JSON / Markdown / HTML
      ┌────────────────────────────▼────────────────────────────────┐
      │                      Regression Stages                      │
      │  smoke  directed  cosim  riscvdv  lint  csr  compliance     │
      │  formal  syn                                                │

逐段解释：

* 第 L43-L46 行：README 直接说明核心数据路是 RTL retire trace 加 DUT probe
  进入 UVM scoreboard，Spike DPI 是 architectural reference model。
* 第 L48-L53 行：sign-off orchestration 层由 `signoff.py`、`gen_html_report.py`
  和 `collect_results.py` 组成，输出 JSON、Markdown 和 HTML。
* 第 L54-L58 行：regression stages 包含 smoke、directed、cosim、riscvdv、lint、
  csr、compliance、formal 和 syn；这与 `signoff.py` 的 full profile 对齐。

关键代码（`README.md:L59-L74`）：

.. code-block:: bash

                                   │ report.json / logs / coverage
      ┌────────────────────────────▼────────────────────────────────┐
      │                       UVM Environment                       │
      │  tests → env → agents → trace monitor → cosim scoreboard    │
      └────────────────────────────┬────────────────────────────────┘
                                   │ trace item + probe hint
      ┌────────────────────────────▼────────────────────────────────┐
      │                         VeeR EH2 DUT                         │
      │  rtl/design + shared/rtl + generated configuration snapshots │
      └────────────────────────────┬────────────────────────────────┘
                                   │ retired instruction stream
      ┌────────────────────────────▼────────────────────────────────┐
      │                         Spike DPI                            │
      │  libcosim.so  spike_cosim.cc  CSR fixups  memory comparison │
      └─────────────────────────────────────────────────────────────┘
   ```

逐段解释：

* 第 L59-L64 行：stage 输出进入 UVM environment，UVM environment 由 tests、env、
  agents、trace monitor 和 cosim scoreboard 串起来。
* 第 L65-L69 行：DUT 层输出 trace item 和 probe hint，并产生 retired instruction stream。
* 第 L70-L74 行：Spike DPI 层包含 `libcosim.so`、`spike_cosim.cc`、CSR fixup
  和 memory comparison。

接口关系：

* 被调用：本部分三章的共同背景。
* 调用：:ref:`cosim_scoreboard`、:ref:`scripts_reference`、:ref:`signoff_flow`。
* 共享状态：trace pkt、probe、Spike DPI、sign-off artifacts。

§4  sign-off profile 的真实边界
-------------------------------

当前 sign-off profile 由 `signoff.py` 定义。`full` profile 包含 smoke、directed、
cosim、riscvdv、lint、csr_unit、compliance、formal 和 syn；quick、cosim、
riscvdv_smoke、nightly 只是不同 stage 子集。

关键代码（`dv/uvm/core_eh2/scripts/signoff.py:L37-L59`）：

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
   
   STAGE_TESTLIST = {
       "directed": DV_DIR / "directed_tests" / "directed_testlist.yaml",
       "cosim": DV_DIR / "directed_tests" / "cosim_testlist.yaml",
       "riscvdv": DV_DIR / "riscv_dv_extension" / "testlist.yaml",
   }

逐段解释：

* 第 L37-L44 行：profile 到 stage list 的映射写在源码中；`full` 是 9-stage profile。
* 第 L46-L53 行：stage 最低通过数不是 release result，而是 gate threshold：
  directed 33、cosim 7、riscv-dv 50、csr_unit 20、compliance 85。
* 第 L55-L59 行：directed、cosim 和 riscv-dv stage 分别读取不同 testlist。
  这解释了 :ref:`goals_scope` 为什么必须把 testlist 范围和 sign-off 数字分开描述。

接口关系：

* 被调用：`make signoff`、`make signoff_quick` deprecated alias、release replay。
* 调用：directed/cosim/riscv-dv testlist。
* 共享状态：PROFILE、STAGE_MIN_PASSED、STAGE_TESTLIST。

§5  当前命令入口
----------------

快速上手章节使用当前 Makefile 变量名。尤其注意，sign-off profile 变量是 `PROFILE`，
coverage gate 变量是 `SIGNOFF_MIN_LINE_COV` 和 `SIGNOFF_MIN_FUNCTIONAL_COV`；
后者是兼容旧脚本参数名，当前 URG dashboard 中对应 `GROUP`/covergroup 指标。

关键代码（`Makefile:L568-L590`）：

.. code-block:: bash

       SIMULATOR        compile / smoke / regress / signoff                （默认 vcs）
       PARALLEL         regress / signoff / demo                           （默认 4）
       SEED             regress / signoff                                  （默认 1）
       COV              compile / regress / signoff                        （顶层默认 1；显式 COV=0 关）
       WAVES            compile / smoke / regress / signoff / demo         （默认 0，详见"查看波形"小节）
                        compliance 不支持 WAVES（验证靠 signature 比对）
       NO_COSIM         cosim / compile                                    （默认 0）
   
     仿真：
       TEST=<name>                       单测名（regress 用）
       TESTLIST=riscvdv|directed|cosim   testlist 选择
       ITERATIONS=<N>                    迭代次数
       OUT=<dir>                         regress 输出目录
   
     sign-off：
       PROFILE=full|quick|cosim|nightly  sign-off profile
       GATE_ONLY=0|1                     gate-only 模式
       SIGNOFF_OUT=<dir>                 输出目录
       STAGE_DATA_DIR=<dir>              signoff_replay 数据源
       SIGNOFF_MIN_LINE_COV=<pct>        line 门限（默认 65）
      SIGNOFF_MIN_FUNCTIONAL_COV=<pct>  group/covergroup 门限（默认 40，参数名保留 functional）
       SIGNOFF_ALLOW_WARNINGS=0|1        warning 容忍（默认 1）
       LEC_BLOCKLEVEL=0|1                启用块级 LEC（默认 1）

逐段解释：

* 第 L568-L575 行：通用变量包括 `SIMULATOR`、`PARALLEL`、`SEED`、`COV`、
  `WAVES` 和 `NO_COSIM`。
* 第 L576-L581 行：regress 入口使用 `TEST`、`TESTLIST`、`ITERATIONS` 和 `OUT`。
* 第 L582-L590 行：sign-off 入口使用 `PROFILE`，并列出 gate-only、输出目录、
  stage data source、coverage gate、warning 容忍和 block-level LEC 开关。

接口关系：

* 被调用：:ref:`quickstart`、:ref:`build_flow`、:ref:`signoff_flow`。
* 调用：顶层 Makefile target、`signoff.py`。
* 共享状态：PROFILE、coverage gate、LEC_BLOCKLEVEL。

§6  三个子章职责
-----------------

本部分后续三个子章各自承担不同层级的信息，不互相替代。

.. list-table::
   :header-rows: 1
   :widths: 24 38 38

   * - 子章
     - 主要回答的问题
     - 不负责展开的内容
   * - :ref:`goals_scope`
     - 当前 sign-off 覆盖哪些 stage、哪些配置、哪些 coverage/formal/LEC 数字。
     - 不展开每个脚本、UVM class 或 RTL module 的内部实现。
   * - :ref:`quickstart`
     - 第一次进入仓库时如何加载环境、编译、运行 smoke/regress/signoff。
     - 不替代 :ref:`scripts_reference` 或 :ref:`build_flow` 的 target 逐段说明。
   * - :ref:`ibex_capability_matrix`
     - EH2 与 Ibex 的验证平台能力对比，特别是 trace/probe、agent、riscv-dv、coverage。
     - 不把 Ibex 参考实现改写成 EH2 的 ground truth。

关键代码（`docs/sphinx_cn/source/04_verification_overview/goals_scope.rst:L12-L22`）：

.. code-block:: bash

   §1  本章边界
   -------------
   
   本章只定义 EH2-Veri 当前主线的验证目标、已纳入 sign-off 的范围、当前配置覆盖边界和不覆盖范围。
   所有数字来自当前仓库中的 status 文档或 gate 脚本，不能用旧审计记录或未来目标替代。
   尤其注意三点：
   
   * 当前 demo 时间是 `2026-05-19 01:02`。
   * 当前 sign-off 变量是 `PROFILE`，覆盖率门限默认是 line `65`、group/covergroup `40`。
   * 当前 `eh2_configs.yaml` 只有 `default`、`minimal`、`dual_thread`、`ahb_lite` 四个 profile；

逐段解释：

* 第 L12-L16 行：`goals_scope` 明确只定义目标、sign-off 范围、配置边界和不覆盖范围。
* 第 L19-L22 行：该章固定 2026-05-19 01:02、`PROFILE` 和 coverage gate，
  并说明 `SIGNOFF_MIN_FUNCTIONAL_COV` 是历史兼容参数名，防止旧 profile 集合回流。

关键代码（`docs/sphinx_cn/source/04_verification_overview/quickstart.rst:L12-L22`）：

.. code-block:: bash

   §1  本章边界
   -------------
   
   本章给验证工程师一个最短但不失真的上手路径：先进入 `/home/host/eh2-veri`，
   加载 `env.sh`，确认无 Spike 环境时如何编译，运行 `make smoke`，再进入
   directed/cosim/riscv-dv 回归和 sign-off。脚本内部实现详见 :ref:`scripts_reference`；
   构建 target 详见 :ref:`build_flow`；sign-off gate 详见 :ref:`signoff_flow`。
   
   当前源码里有一个容易踩错的点：`make run` 还存在，但 Makefile 已把它标记为
   deprecated alias。快速上手应使用 `make smoke`、`make regress` 和 `make signoff`。
   sign-off profile 变量名是 `PROFILE`，旧版 profile 变量只在历史 wrapper 中可见。

逐段解释：

* 第 L12-L18 行：`quickstart` 只给最短上手路径，并把脚本、build target、
  sign-off gate 的深度解释转交给对应章节。
* 第 L20-L22 行：该章明确当前推荐命令是 `make smoke`、`make regress`、
  `make signoff`，并纠正旧版 profile 变量名。

接口关系：

* 被调用：本部分读者路径。
* 调用：三个子章。
* 共享状态：章节边界、release 数字、current command surface。

§7  2026-05-19 VCS 主线 sign-off 摘要
-------------------------------------

本页只摘要当前 release result；逐项 gate 解释见 :ref:`goals_scope` 和
:ref:`signoff_flow`。

实测摘要（2026-05-19 01:02，VCS 主线）：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   实跑覆盖率: 102/104 (98.1%)
   LEC: 31635/31635 PASS
   riscvdv:   370/395 (93.67%)
   compliance: 85/88 (96.59%)
   directed:   40/40 (100%)
   formal:     46/46 (100%)

   Coverage (core_eh2_tb_top.dut, URG native dashboard):
     LINE     95.05%
     BRANCH   84.97%
     TOGGLE   53.52%
     ASSERT   33.33%
     FSM      54.74%
     GROUP    69.42%
     OVERALL  65.17%

逐段解释：

* 第 1-4 行：当前 full sign-off 为 PASS，9 个 stage 全部通过，LEC compare point
  为 31635/31635。
* 第 5-8 行：动态回归中 riscv-dv 为 370/395，compliance 为 85/88，directed 为
  40/40，formal 为 46/46。
* 第 10-17 行：覆盖率来自 VCS/URG 原生 dashboard 的 DUT 子树，不包含 testbench
  scope，也不包含过时的条件覆盖维度。

接口关系：

* 被调用：本部分摘要、release review、验收门。
* 调用：:ref:`goals_scope` 和 :ref:`signoff_flow`。
* 共享状态：formal 46/46、LEC 31635/31635、compliance 85/88、riscv-dv 370/395、
  directed 40/40、102/104 实跑覆盖、LINE 95.05%、GROUP 69.42%、OVERALL 65.17%。

§8  读者路径
------------

不同读者应从本部分进入不同后续章节：

* 只想确认 release 是否闭合：读 :ref:`goals_scope`，再跳到 :ref:`signoff_flow`。
* 需要实际跑命令：读 :ref:`quickstart`，再跳到 :ref:`build_flow` 和
  :ref:`regression_flow`。
* 需要理解为什么 EH2 不是 Ibex 直接拷贝：读 :ref:`ibex_capability_matrix`，
  再跳到 :ref:`cosim_scoreboard`。
* 需要查 UVM 类：跳到 :ref:`verification_arch_index` 和 :ref:`appendix_b_uvm/index`。
* 需要查脚本或 Makefile：跳到 :ref:`scripts_reference` 和 :ref:`appendix_f_scripts/index`。
* 需要查工具链：跳到 :ref:`appendix_c_tools/index`、:ref:`formal_flow`、
  :ref:`synthesis_flow` 和 :ref:`lec_flow`。

.. code-block:: bash

   release reviewer
       -> goals_scope
       -> signoff_flow
   
   first-time runner
       -> quickstart
       -> build_flow
       -> regression_flow
   
   architecture reader
       -> ibex_capability_matrix
       -> cosim_scoreboard
       -> verification_arch_index

逐段解释：

* 第 1-3 行：release reviewer 先确认 scope，再看 sign-off flow 的 gate 逻辑。
* 第 5-8 行：first-time runner 先按 quickstart 跑通，再补 build/regression 细节。
* 第 10-13 行：architecture reader 先理解 Ibex 对标，再读 cosim scoreboard 和 UVM 架构。

接口关系：

* 被调用：读者导航。
* 调用：本手册第五、六、附录部分。
* 共享状态：章节锚点和 toctree。

§9  参考资料
-------------

关联章节：

* :ref:`goals_scope` — 验证目标、sign-off 范围、coverage/formal/LEC 数字。
* :ref:`quickstart` — 当前 smoke/regress/signoff 命令入口。
* :ref:`ibex_capability_matrix` — EH2 与 Ibex 验证能力对比。
* :ref:`verification_arch_index` — UVM 架构和主要组件。
* :ref:`flows_index` — build、regression、sign-off、formal、synthesis、LEC 等 flow。
* :ref:`appendix_a_rtl/index` — RTL 模块字典。
* :ref:`appendix_b_uvm/index` — UVM 类字典。
* :ref:`appendix_c_tools/index` — 工具链源码字典。
* :ref:`appendix_f_scripts/index` — 脚本和 Makefile 字典。

源文件绝对路径：

* `/home/host/eh2-veri/README.md`
* `/home/host/eh2-veri/docs/PROJECT_STATUS.md`
* `/home/host/eh2-veri/Makefile`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* `/home/host/eh2-veri/docs/sphinx_cn/source/index.rst`
* `/home/host/eh2-veri/docs/sphinx_cn/source/04_verification_overview/goals_scope.rst`
* `/home/host/eh2-veri/docs/sphinx_cn/source/04_verification_overview/quickstart.rst`
* `/home/host/eh2-veri/docs/sphinx_cn/source/04_verification_overview/ibex_capability_matrix.rst`
