.. _flows_index:
.. _06_flows/index:

流程与脚本
==========

:status: draft
:source: Makefile
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本部分边界
--------------

本部分说明 EH2 验证平台的自动化流程：构建、回归、sign-off、CI、lint、formal、
综合、LEC、compliance 和脚本 CLI。流程章节关注命令入口、参数语义、数据流和
证据收集；脚本内部逐函数解释见 :ref:`appendix_f_scripts/index`，工具源码解释见
:ref:`appendix_c_tools/index`。

顶层 :file:`Makefile` 把核心 target 组织为 5 组：

* 一键运行：``demo``、``signoff``、``signoff_replay``。
* 构建：``asm``、``cosim``、``compile``。
* 仿真回归：``smoke``、``regress``、``compliance``。
* 静态/形式化/综合：``lint``、``formal``、``synth``。
* 文档/清理：``manual``、``clean``。

§2  Makefile 核心 target
------------------------

关键代码（``Makefile:L197-L214``）：

.. code-block:: makefile

   # ============================================================
   # .PHONY — 15 核心 target + 内部 + deprecated alias
   # ============================================================
   .PHONY: help \
           demo signoff signoff_replay \
           asm cosim compile \
           smoke regress compliance \
           lint formal synth \
           manual clean \
           compile_vcs compile_xlm \
           run gen nightly weekly run_regress \
           signoff_quick signoff_gate signoff_with_cleanup html_report cov \
           lint_verible lint_verilator \
           syn_yosys syn_dc lec block_lec syn_clean \
           formal_clean compliance-all compliance-compile \
           manual_html \
           clean_cov clean_workspace clean_workspace_dry \
           run-csr-unit ci_unit ci_lint

逐段解释：

* 第 200~205 行：核心 target 是 ``help`` 加上 14 个主要动作；help 文本将其拆成
  一键运行、构建、回归、静态/形式化/综合、文档/清理 5 组。
* 第 206~214 行：后续名字是内部 target 或 deprecated alias，用于兼容旧 CI/文档。
  例如 ``run_regress``、``syn_yosys``、``formal_clean`` 仍保留，但当前文档优先描述
  新的核心 target。

接口关系：

* 被调用：用户、CI workflow、sign-off replay。
* 调用：Python 脚本、子目录 Makefile、EDA 工具和 Shell 维护脚本。
* 共享状态：``build``、``out``、coverage DB、formal log、LEC summary 和
  sign-off JSON/HTML。

§3  流程总图
------------

::

   make demo / make signoff
      |
      +-- make asm
      |     `-- tests/asm/*.S -> *.hex
      |
      +-- make compile SIMULATOR=vcs COV=1 BUILD_SUBDIR=build/signoff
      |     |-- VCS -cm line+tgl+assert+fsm+branch
      |     |-- -cm_hier dv/uvm/core_eh2/cover.cfg
      |     `-- <target>/simv
      |
      +-- signoff.py full profile
      |     |-- smoke -> run_regress.py
      |     |-- directed -> directed_tests/directed_testlist.yaml
      |     |-- cosim -> directed_tests/cosim_testlist.yaml
      |     |-- riscvdv -> riscv_dv_extension/testlist.yaml
      |     |-- lint -> make lint
      |     |-- csr_unit -> dv/uvm/cs_registers_eh2
      |     |-- compliance -> dv/uvm/riscv_compliance
      |     |-- formal -> make formal
      |     `-- syn -> syn/build/lec_summary.txt
      |
      +-- merge_cov.py -> urg -> cov_merged/dashboard.txt
      `-- signoff_status.json + signoff_report.md + report.html

逐段解释：

* ``asm`` 和 ``compile`` 是多数仿真 flow 的前置动作。当前主线 compile 明确使用
  VCS，coverage 维度为 ``line+tgl+assert+fsm+branch``，并通过
  :file:`dv/uvm/core_eh2/cover.cfg` 在编译时限定 DUT 子树。
* ``regress`` 调用 :file:`dv/uvm/core_eh2/scripts/run_regress.py`，根据
  ``TESTLIST`` 选择 riscv-dv、directed 或 cosim testlist。
* ``lint``、``formal``、``csr_unit``、``compliance`` 和 ``syn`` 是 full profile 的
  非普通 UVM regression stage。
* ``merge_cov.py`` 对 VCS ``.vdb`` 使用 URG 原生合并；sign-off standalone 入口也能
  识别 NC ``cov_work`` 并走 IMC 生成兼容 dashboard。VCS 是默认 release 参考，
  NC 是完整备选 simulator 和 cross-check 路径。

§4  章节目录
------------

.. list-table::
   :header-rows: 1
   :widths: 22 28 50

   * - 小节
     - 主要入口
     - 内容边界
   * - :ref:`build_flow`
     - ``make asm``、``make cosim``、``make compile``
     - Make 目标、仿真器选择、RTL/TB filelist、Cosim 编译、环境变量
   * - :ref:`regression_flow`
     - ``make smoke``、``make regress``
     - gen、compile、sim、check、collect、testlist 路由和并行参数
   * - :ref:`signoff_flow`
     - ``make signoff``、``make signoff_replay``
     - 9-stage gate、profile、coverage gate、formal/LEC evidence、报告生成
   * - :ref:`ci_pipeline`
     - GitHub workflow 和 Make target
     - PR/Nightly 触发、环境变量、缓存和失败边界
   * - :ref:`lint_flow`
     - ``make lint``
     - Verible/Verilator 双 lint、rule/waiver 和 blocking error
   * - :ref:`formal_flow`
     - ``make formal``
     - Cadence IFV 编译、TCL proof、summary 提取和 formal ``46/46`` gate
   * - :ref:`synthesis_flow`
     - ``make synth``
     - DC 综合、Yosys 复盘路径、wrapper 生成和 STEP/TOOL 参数
   * - :ref:`lec_flow`
     - ``make synth STEP=block_lec``
     - R3-C block-level LEC、9 个模块、``31635/31635`` compare points
   * - :ref:`compliance_flow`
     - ``make compliance``
     - RISC-V compliance sub-env、compile/run/all 模式和 ``85/88`` gate
   * - :ref:`scripts_reference`
     - Python CLI
     - 22 个核心 Python 脚本的 CLI 入口、参数语义和互调关系

§5  Regression 与 sign-off 入口
-------------------------------

关键代码（``Makefile:L557-L624``）：

.. code-block:: makefile

   regress: compile
   	@echo "=== [regress] testlist=$(TESTLIST) parallel=$(PARALLEL) iter=$(ITERATIONS) ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  $(if $(TEST),--test $(TEST),--testlist $(TESTLIST_PATH)) \
   	  --simulator $(SIMULATOR) \
   	  --seed $(SEED) \
   	  --iterations $(ITERATIONS) \
   	  --parallel $(PARALLEL) \
   	  --output $(if $(OUT),$(OUT),$(BUILD_DIR)/regression) \
   	  $(if $(filter 1,$(COV)),--coverage,)
   	@echo "=== [regress] 完成 ==="
   
   compliance:
   	@echo "=== [compliance] mode=$(or $(MODE),run) ==="
   	+@$(MAKE) -C dv/uvm/riscv_compliance $(if $(filter all,$(MODE)),compliance-all,$(if $(filter compile,$(MODE)),compliance-compile,compliance))

逐段解释：

* 第 557 行：``regress`` 依赖 ``compile``，因此 regression 运行前先保证 TB 已编译。
* 第 559~566 行：Makefile 将 ``TEST`` 或 ``TESTLIST_PATH``、simulator、seed、
  iterations、parallel、output 和 coverage 开关传给 ``run_regress.py``。
* 第 569~571 行：``compliance`` 不走 ``run_regress.py``，而是转入
  :file:`dv/uvm/riscv_compliance` 子目录 Makefile。

接口关系：

* 被调用：``make regress``、``make compliance``、sign-off stage。
* 调用：``run_regress.py``、RISC-V compliance 子环境。
* 共享状态：``TESTLIST_PATH``、``BUILD_DIR``、coverage 开关和 regression 输出目录。

§6  Static / Formal / Synthesis 入口
------------------------------------

关键代码（``Makefile:L576-L601``）：

.. code-block:: makefile

   lint:
   	@echo "=== [lint] tool=$(or $(TOOL),all) ==="
   	+@$(MAKE) -C lint $(if $(filter verible,$(TOOL)),lint-verible,$(if $(filter verilator,$(TOOL)),lint-verilator,lint))
   
   formal:
   	@echo "=== [formal] IFV 46 properties ==="
   	+@$(MAKE) -C dv/formal formal
   
   synth:
   	@echo "=== [synth] tool=$(or $(TOOL),dc) step=$(or $(STEP),full) ==="
   	@# STEP=full 默认 = DC 综合 + block-level Formality LEC（当前 VCS demo 真实路径）。
   	@# 旧的 syn-full（= syn-yosys + yosys-equiv）已知失败（ADR-0013：yosys 0.55 SV 限制）。
   	@# 显式指定 TOOL=yosys 仍可跑 yosys（仅用于 ADR-0013 复盘演示）。

逐段解释：

* 第 576~578 行：``lint`` 根据 ``TOOL`` 选择 Verible、Verilator 或双 lint。
* 第 580~582 行：``formal`` 转入 :file:`dv/formal`，运行 Cadence IFV flow。
  Makefile echo 中的 “46 properties” 对应 release formal gate 的 46 个 IFV 对象，
  不是 :file:`dv/formal/properties/*.sv` 内 ``assert property`` 行数。
* 第 584~601 行：``synth`` 根据 ``TOOL`` 和 ``STEP`` 选择 Yosys、LEC、block_lec、
  DC synth 或默认 DC synth + block-level Formality LEC。

接口关系：

* 被调用：用户、CI 和 sign-off flow。
* 调用：:file:`lint/Makefile`、:file:`dv/formal/Makefile`、:file:`syn/Makefile`。
* 共享状态：lint log、formal IFV log、syn/build artifacts 和 LEC summary。

§7  2026-05-19 VCS demo evidence gate
-------------------------------------

2026-05-19 01:02 的完整 demo 是流程层文档的当前 ground truth。该 run 的默认
simulator 是 VCS，coverage 使用 ``cover.cfg`` DUT-only scope，LEC 使用
:file:`syn/build/lec_summary.txt`，并完成 9/9 stages PASS。

.. list-table::
   :header-rows: 1
   :widths: 24 24 52

   * - Stage
     - 结果
     - 证据边界
   * - smoke
     - ``PASS``
     - full profile 第一阶段，验证编译产物可运行
   * - directed
     - ``40/40 (100%)``
     - directed assembly suite
   * - cosim
     - ``7/7``
     - Spike DPI lockstep directed cosim proofs
   * - riscv-dv
     - ``370/395 (93.67%)``
     - riscv-dv extension testlist，25% fail-rate ceiling 内通过
   * - lint
     - ``1/1``
     - Verible/Verilator lint gate
   * - csr_unit
     - ``20/20``
     - EH2 CSR unit sub-environment
   * - compliance
     - ``85/88 (96.59%)``
     - RISC-V compliance stage threshold closure
   * - formal
     - ``46/46``
     - Cadence IFV assertion summary，``Not_Run=0``
   * - syn / LEC
     - ``31635/31635``
     - block-level Synopsys Formality LEC，9 个模块

coverage evidence：

* 实跑覆盖率 ``102/104 (98.1%)``。
* LINE ``95.05%``，BRANCH ``84.97%``，TOGGLE ``53.52%``。
* ASSERT ``33.33%``，FSM ``54.74%``，GROUP ``69.42%``，OVERALL ``65.17%``。
* coverage 维度为 ``line+tgl+assert+fsm+branch``；不要把历史 ``cond`` 字段写成
  当前 sign-off 维度。

§8  与 Ibex 工业实现对照
------------------------

EH2 的流程主线按 lowRISC Ibex 的 UVM 工业结构组织，但保留 EH2 双线程和子环境差异：

.. list-table::
   :header-rows: 1
   :widths: 24 36 40

   * - 维度
     - EH2 当前实现
     - Ibex 对照
   * - 默认 simulator
     - ``SIMULATOR=vcs``，sign-off/demo 拒绝 NC
     - :file:`/home/host/ibex/dv/uvm/core_ibex/yaml/rtl_simulation.yaml`
       以 VCS 作为工业主线模板之一
   * - coverage scope
     - :file:`dv/uvm/core_eh2/cover.cfg`，``+tree core_eh2_tb_top.dut``
     - :file:`/home/host/ibex/dv/uvm/core_ibex/cover.cfg` 使用 compile-time
       hierarchy scope
   * - merge
     - :file:`dv/uvm/core_eh2/scripts/merge_cov.py` 调用 ``urg -format both``
     - :file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py`
       同样使用 URG 原生报告
   * - sign-off stage
     - 9 stage，增加 CSR unit、compliance、formal、syn/LEC
     - Ibex 侧以 core_ibex regression、coverage 和 directed/riscv-dv 为主
   * - 设计差异
     - 双线程 EH2、DMI/JTAG/PIC/DMA/ICCM/DCCM/ICache 与 block-level LEC
     - Ibex 单核配置矩阵更小，不需要 EH2 的 dual-thread cosim waiver 形态

§9  常用命令速查
----------------

.. code-block:: bash

   # 完整 VCS demo：构建、综合/LEC、sign-off、URG coverage、HTML 报告
   make demo

   # 只跑 full sign-off；仍强制 SIMULATOR=vcs
   make signoff PROFILE=full COV=1 PARALLEL=4

   # 重放已有 stage 结果，不重新运行仿真
   make signoff_replay STAGE_DATA_DIR=build/signoff

   # directed/cosim/riscv-dv regression 入口
   make regress TESTLIST=directed PARALLEL=4
   make regress TESTLIST=cosim PARALLEL=4
   make regress TESTLIST=riscvdv PARALLEL=4

   # NC 备选 smoke/sign-off，也可打开 SHM 波形
   make smoke SIMULATOR=nc WAVES=1
   make signoff SIMULATOR=nc COV=1 PARALLEL=4

典型输出应包含：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   real run coverage: 102/104 (98.1%)
   LEC: 31635/31635 PASS
   LINE 95.05%  GROUP 69.42%  OVERALL 65.17%

§10  流程策略矩阵
-----------------

流程层的关键不是“每个命令都能跑”，而是每个命令的证据用途不同。下表给出当前
仓库推荐的使用边界：

.. list-table::
   :header-rows: 1
   :widths: 20 30 25 25

   * - 场景
     - 推荐命令
     - 输出目录
     - 是否可作 sign-off 证据
   * - 完整演示
     - ``make demo``
     - ``build/demo``
     - 是，前提是 VCS coverage、formal、LEC 均完成
   * - 完整签核
     - ``make signoff PROFILE=full COV=1``
     - ``build/signoff``
     - 是
   * - 只复评 gate
     - ``make signoff_replay STAGE_DATA_DIR=build/signoff``
     - ``build/signoff_replay``
     - 是，前提是 stage result 和 coverage dashboard 来自 VCS 主线
   * - 快速 sanity
     - ``make signoff PROFILE=quick COV=1``
     - ``build/signoff``
     - 否，只能证明 smoke/directed 子集
   * - directed 调试
     - ``make regress TESTLIST=directed TEST=directed_pmp_lock``
     - ``build/regress``
     - 否，需回到 full sign-off 聚合
   * - NC 波形
     - ``make smoke SIMULATOR=nc WAVES=1``
     - ``build/smoke`` 或目标指定目录
     - 否，只能用于单测波形定位

.. note::

   ``PROFILE`` 是当前顶层 Makefile 的主线变量。staged ``wrapper.mk`` 中仍可见
   旧版 profile 兼容变量，这是历史 Ibex-style wrapper 的内部参数，不应写成
   新用户命令的推荐入口。

§11  Simulator 与 coverage 契约
-------------------------------

当前流程层有一个强约束：sign-off、demo 和 coverage merge 都默认且只接受 VCS 主线。
这不是工具偏好，而是数据真实性约束。VCS 编译时通过 ``-cm_hier`` 和
:file:`dv/uvm/core_eh2/cover.cfg` 将 coverage scope 限定到
``core_eh2_tb_top.dut``；URG 直接生成 dashboard，``merge_cov.py`` 只镜像
``report/dashboard.txt`` 到输出根目录。

.. list-table::
   :header-rows: 1
   :widths: 22 28 50

   * - 契约项
     - 当前值
     - 说明
   * - 默认 simulator
     - ``vcs``
     - 与 Ibex 工业 flow 对齐；sign-off/demo 默认 VCS，也接受 ``SIMULATOR=nc``
       作为完整备选 simulator
   * - coverage 编译维度
     - ``line+tgl+assert+fsm+branch``
     - 不包含 condition/expression 维度
   * - coverage scope
     - ``+tree core_eh2_tb_top.dut``
     - 编译时限定 DUT 子树，从源头排除 testbench/interface stub
   * - toggle scope
     - DUT subtree 下排除内部 toggle 子树展开
     - 由 :file:`cover.cfg` 的 ``begin tgl`` 块控制
   * - merge 工具
     - ``urg -full64 -format both``
     - 由 :file:`dv/uvm/core_eh2/scripts/merge_cov.py` 调用
   * - NC 用途
     - ``SIMULATOR=nc`` 或 ``make wave_nc``
     - 支持 compile/smoke/regress/sign-off/demo、IMC coverage 和 SHM/SimVision 调试；
       VCS 仍是默认 release 参考

用于核对该契约的最小源码片段如下：

.. code-block:: makefile

   VCS_COV_METRICS := line+tgl+assert+fsm+branch
   VCS_COV_HIER    := $(TB_DIR)/cover.cfg
   VCS_COMPILE_COV_OPTS := -lca \
                           -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                           -cm_hier $(VCS_COV_HIER) \
                           -cm_tgl portsonly \
                           -cm_tgl structarr \
                           -cm_report noinitial \
                           -cm_seqnoconst

.. code-block:: text

   +tree core_eh2_tb_top.dut
   begin tgl
     -tree core_eh2_tb_top.dut.*
   end

§12  报告字段读法
-----------------

``signoff_status.json``、``signoff_report.md`` 和 ``report.html`` 面向不同读者：
JSON 给 CI 和脚本消费，Markdown 给代码评审和邮件摘要使用，HTML 给 dashboard
查看。三者必须来自同一个 ``SIGNOFF_OUT``，不能拼接不同 run 的 stage 与 coverage。

.. list-table::
   :header-rows: 1
   :widths: 22 28 50

   * - 字段
     - 当前 demo 值
     - 正确解读
   * - ``status``
     - ``PASS``
     - 所有 blocker 清空；存在 tool-limited waiver 时会降级为带 waiver 状态
   * - ``stages``
     - 9/9 PASS
     - full profile 的 stage 数，不等于单个 testlist 用例数
   * - ``real_run_coverage``
     - ``102/104 (98.1%)``
     - 实际运行 test pool 覆盖率，不是 URG line coverage
   * - ``coverage.line``
     - ``95.05%``
     - URG 对 DUT subtree 的 line 结果
   * - ``coverage.functional``
     - ``69.42%``
     - 内部键名沿用 functional，dashboard 显示为 GROUP
   * - ``lec.total.passing``
     - ``31635``
     - block-level Formality compare points 总 passing 数
   * - ``waivers``
     - cosim-disabled YAML
     - waiver 必须来自正式 YAML，不允许 testlist 内联 reason 绕过

典型 Markdown 摘要中应同时出现 stage、coverage 和 LEC 三类证据：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   实跑覆盖率: 102/104 (98.1%)
   LEC: 31635/31635 PASS
   Coverage:
     LINE     95.05%
     GROUP    69.42%
     OVERALL  65.17%

§13  失败边界和定位顺序
-----------------------

当流程失败时，先按“证据层级”定位，不要直接改 waiver 或阈值。推荐顺序如下：

.. list-table::
   :header-rows: 1
   :widths: 18 30 52

   * - 层级
     - 首看文件
     - 判断方式
   * - 编译
     - ``build/signoff/compile.log``
     - VCS 编译错误、DPI link 错误、缺少 include 或 package
   * - 单测
     - ``runs/<stage>/*/sim.log``
     - UVM_FATAL、timeout、mailbox fail、Spike mismatch
   * - 回归汇总
     - ``runs/<stage>/report.json``
     - passed/total、failure mode、warning count
   * - coverage
     - ``cov_merged/merge.log.stdout`` 与 ``cov_merged/dashboard.txt``
     - URG 是否找到 ``.vdb``，dashboard 是否含 LINE/GROUP/OVERALL
   * - formal
     - ``dv/formal/build/ifv_final.log``
     - FAIL、Not_Run、property count 是否为 46/46
   * - LEC
     - ``syn/build/lec_summary.txt``
     - TOTAL 行是否 31635 passing、0 failing、0 unverified
   * - waiver
     - ``dv/uvm/core_eh2/waivers/cosim-disabled.yaml``
     - schema 是否完整，testlist 是否存在禁止的 inline reason

.. warning::

   coverage 不达标时不要用 NC 波形 run 追加覆盖率，也不要手写 dashboard。正确路径是
   增加 VCS 主线测试、重新生成 ``.vdb``，再让 ``merge_cov.py`` 调用 URG 合并。

§14  阶段 6 交接检查表
----------------------

流程章节完成或复审时按下列检查表验收：

.. list-table::
   :header-rows: 1
   :widths: 12 48 40

   * - 序号
     - 检查项
     - 期望结果
   * - 1
     - 搜索过时 coverage 维度
     - 不存在把 condition 写成当前 sign-off 维度的叙述
   * - 2
     - 搜索旧 R3/R4 证据目录
     - 不把历史目录写成当前 demo ground truth
   * - 3
     - 搜索 NC 主线叙述
     - NC 写成完整备选 simulator，且与 VCS 默认 release 参考区分清楚
   * - 4
     - 核对 VCS coverage 数字
     - LINE 95.05%、GROUP 69.42%、OVERALL 65.17% 全文一致
   * - 5
     - 核对 stage 数字
     - riscv-dv 370/395、compliance 85/88、directed 40/40、formal 46/46
   * - 6
     - 核对 LEC 数字
     - 31635/31635 PASS，且说明来自 block-level Formality
   * - 7
     - 构建 Sphinx HTML
     - 无 error；新增 warning 必须修正或记录原因

§15  快速术语索引
-----------------

.. list-table::
   :header-rows: 1
   :widths: 24 76

   * - 术语
     - 本部分中的含义
   * - build island
     - 每个目标独立的 ``BUILD_SUBDIR``，隔离 ``simv``、``csrc``、``cov`` 和日志
   * - full profile
     - ``smoke directed cosim riscvdv lint csr_unit compliance formal syn`` 9 个 stage
   * - real run coverage
     - sign-off 对 test pool 实跑比例的统计，当前 demo 为 102/104
   * - GROUP
     - URG dashboard 的 covergroup 结果；脚本内部兼容键名为 ``functional``
   * - block-level LEC
     - 对 9 个模块分别运行 Formality 并汇总 compare point 的 closure path
   * - gate-only
     - 不重新运行 stage，只读取已有结果目录并重新评估 gate
   * - waiver YAML
     - 正式 waiver 文件；inline reason 会被 sign-off 当作 forbidden loophole

§16  参考资料
--------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* :file:`/home/host/eh2-veri/lint/Makefile`
* :file:`/home/host/eh2-veri/dv/formal/Makefile`
* :file:`/home/host/eh2-veri/syn/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/cover.cfg`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/merge_cov.py`
* :file:`/home/host/eh2-veri/syn/build/lec_summary.txt`
* :file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py`
* :file:`/home/host/ibex/dv/uvm/core_ibex/cover.cfg`

关联章节：

* :ref:`build_flow`
* :ref:`regression_flow`
* :ref:`signoff_flow`
* :ref:`ci_pipeline`
* :ref:`lint_flow`
* :ref:`formal_flow`
* :ref:`synthesis_flow`
* :ref:`lec_flow`
* :ref:`compliance_flow`
* :ref:`scripts_reference`
* :ref:`appendix_f_scripts/index`
* :ref:`appendix_c_tools/index`

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
