.. _appendix_c_tools_index:
.. _appendix_c_tools/index:

附录 C — Cosim / Formal / Syn / Lint 源码字典
=============================================

:status: draft
:source: dv/cosim; dv/formal; syn; lint; dv/uvm/core_eh2/tests/asm
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本附录边界
--------------

本附录只覆盖验证工具链相关源码：Spike DPI cosim、Formal/IFV/SVA、综合与
LEC、Verible/Verilator lint、以及手写汇编测试。RTL 模块解释见
:ref:`appendix_a_rtl/index`，UVM 类解释见 :ref:`appendix_b_uvm/index`，
脚本和 YAML 配置见 :ref:`appendix_f_scripts/index`。

本页不是 toctree 定义，不新增或删除任何章节；它只是把已经存在的工具字典按
证据来源重新分流。当前签核数字统一引用 2026-05-19 01:02 的 VCS 主线
demo：``9/9`` stages PASS，实跑覆盖率 ``102/104``（98.1%），LEC
``31635/31635`` PASS；riscv-dv ``370/395``（93.67%）、compliance
``85/88``（96.59%）、directed ``40/40``（100%）、formal ``46/46``
（100%）。URG dashboard 的 DUT subtree 覆盖率为 LINE ``95.05%``、
BRANCH ``84.97%``、TOGGLE ``53.52%``、ASSERT ``33.33%``、FSM
``54.74%``、GROUP ``69.42%``、OVERALL ``65.17%``。

需要特别区分两类 formal 数字：

* :file:`dv/formal/properties/*.sv` 源码内共有 7 个 property 文件，源码计数为
  41 条 ``assert property`` 和 14 条 ``cover property``。
* 当前 formal gate 来自 IFV assertion summary，结果是 ``46/46``，
  证据来自 :file:`dv/formal/build/ifv_final.log` 或 sign-off collector 的
  formal stage 输出。这个数字不是
  ``properties/*.sv`` 文件内 ``assert property`` 的简单行数。

§2  阅读路径
------------

.. list-table::
   :header-rows: 1
   :widths: 22 34 44

   * - 目标
     - 先读章节
     - 依据文件
   * - 理解 Spike DPI lockstep 如何从 SystemVerilog 进入 C++
     - :ref:`appendix_c_tools/cosim_cpp`
     - :file:`dv/cosim/cosim_dpi.svh`、:file:`dv/cosim/cosim_dpi.cc`、:file:`dv/cosim/spike_cosim.cc`
   * - 理解 SVA property 模块本身
     - :ref:`appendix_c_tools/formal_properties`
     - :file:`dv/formal/properties/*.sv`、:file:`dv/formal/eh2_veer_sva.sv`
   * - 理解 IFV 如何编译、证明和收集结果
     - :ref:`appendix_c_tools/formal_infra`
     - :file:`dv/formal/Makefile`、:file:`dv/formal/ifv_filelist.f`、:file:`dv/formal/scripts/*.tcl`
   * - 理解开源 Yosys 综合路径
     - :ref:`appendix_c_tools/syn_yosys`
     - :file:`syn/Makefile`、:file:`syn/yosys/eh2_synth.tcl`
   * - 理解 Design Compiler + Nangate 路径
     - :ref:`appendix_c_tools/syn_nangate`
     - :file:`syn/Makefile`、:file:`syn/scripts/dc_*.tcl`
   * - 理解 block-level Formality LEC
     - :ref:`appendix_c_tools/syn_lec`
     - :file:`syn/Makefile`、:file:`syn/scripts/lec_blocklevel/*.tcl`、:file:`syn/scripts/lec_summary.py`
   * - 理解 Verible lint gate
     - :ref:`appendix_c_tools/lint_verible`
     - :file:`lint/Makefile`、:file:`lint/verible/verible.rules`、:file:`lint/verible/waivers.vbl`
   * - 理解 Verilator lint gate
     - :ref:`appendix_c_tools/lint_verilator`
     - :file:`lint/Makefile`、:file:`lint/verilator/verilator-config.vlt`
   * - 理解手写汇编测试
     - :ref:`appendix_c_tools/asm_tests`
     - :file:`dv/uvm/core_eh2/tests/asm/*.S`、:file:`dv/uvm/core_eh2/tests/asm/Makefile`

§3  工具链数据流总览
--------------------

::

   SystemVerilog TB
      |
      +--> DPI-C import declarations
      |       |
      |       v
      |    dv/cosim/cosim_dpi.cc
      |       |
      |       v
      |    Cosim / SpikeCosim
      |
      +--> IFV filelist + SVA bind
      |       |
      |       v
      |    Cadence IFV proof scripts
      |
      +--> lint/Makefile
      |       |
      |       +--> Verible rule/waiver files
      |       +--> Verilator config/waiver files
      |
      +--> syn/Makefile
              |
              +--> Yosys synthesis
              +--> DC synthesis
              +--> Formality block-level LEC

逐段解释：

* Cosim 路径从 :file:`dv/cosim/cosim_dpi.svh` 的 DPI-C import 开始，C shim
  在 :file:`dv/cosim/cosim_dpi.cc` 中把 ``chandle`` 转回 ``Cosim*``，再调用
  C++ virtual interface。逐函数解释见 :ref:`appendix_c_tools/cosim_cpp`。
* Formal 路径由 :file:`dv/formal/ifv_filelist.f` 把 ``+define+FORMAL``、
  RTL 源文件和 :file:`dv/formal/eh2_veer_sva.sv` 交给 IFV；property 文件和
  bind 风险在 :ref:`appendix_c_tools/formal_properties` 中逐段说明。
* Lint、综合和 LEC 路径都以 Makefile target 为入口。本文档只描述源码中可见
  的 target、变量、脚本调用和报告收集，不把 build 目录产物当作可编辑源。

§4  Cosim DPI 分流
------------------

Cosim 工具链的 SystemVerilog 边界是 :file:`dv/cosim/cosim_dpi.svh`。该文件声明
``riscv_cosim_init``、``riscv_cosim_step``、``riscv_cosim_set_csr``、
``riscv_cosim_notify_dside_access``、``riscv_cosim_get_result`` 等 DPI 函数。
这些函数名在文档中保留英文，不翻译。

关键代码（``dv/cosim/cosim_dpi.svh:L25-L35``）：

.. code-block:: text

   // Step one instruction
   // Returns 1 on match, 0 on mismatch
   import "DPI-C" function int riscv_cosim_step(
     input chandle handle,
     input int     write_reg,
     input int     write_reg_data,
     input int     pc,
     input int     sync_trap,
     input int     suppress_reg_write,
     input int     thread_id
   );

逐段解释：

* 第 27 行：``riscv_cosim_step`` 是 TB 每条退休指令进入 cosim 的核心 DPI
  函数，返回值约定为 ``1`` 表示匹配，``0`` 表示 mismatch。
* 第 28~35 行：参数把写回寄存器、写回数据、PC、同步 trap、寄存器写抑制和
  ``thread_id`` 一并传给 C++ 层。``thread_id`` 是 EH2 多线程 cosim 必需的
  hart/thread 维度。

接口关系：

* 被调用：UVM cosim agent 和 scoreboard 通过 DPI import 调用这些函数。
* 调用：C shim 继续调用 :file:`dv/cosim/cosim.h` 中的 ``Cosim`` virtual 方法。
* 共享状态：``handle`` 是 C++ cosim 对象生命周期句柄，由
  ``riscv_cosim_init`` 创建并由 ``riscv_cosim_destroy`` 释放。

§5  Formal 分流
---------------

Formal 工具链分成两层：property 源码层和 IFV 执行层。property 层解释每个 SVA
模块的端口、property 和 cover；IFV 层解释 filelist、Make target、TCL 证明脚本
和 summary 生成。

关键代码（``dv/formal/Makefile:L20-L25``）：

.. code-block:: makefile

   ifv:
           @mkdir -p $(BUILD_DIR)
           $(IFV) -f $(FILELIST) $(IFV_COMPILE_OPTS) -c -l $(BUILD_DIR)/ifv_elab.log
           $(IFV) -r +tcl+$(SCRIPTS)/ifv_prove.tcl -l $(BUILD_DIR)/ifv_run.log
           @grep -A 6 "Assertion Summary" $(BUILD_DIR)/ifv_run.log > $(BUILD_DIR)/ifv_summary.txt || true
           @cat $(BUILD_DIR)/ifv_summary.txt

逐段解释：

* 第 20 行：``ifv`` 是默认 formal target，``formal`` target 只是依赖它。
* 第 21 行：target 先创建 :file:`dv/formal/build`。
* 第 22 行：第一条 IFV 命令用 :file:`dv/formal/ifv_filelist.f` 编译和 elaboration，
  日志写入 :file:`dv/formal/build/ifv_elab.log`。
* 第 23 行：第二条 IFV 命令加载 :file:`dv/formal/scripts/ifv_prove.tcl` 执行证明，
  日志写入 :file:`dv/formal/build/ifv_run.log`。
* 第 24~25 行：Makefile 从运行日志提取 ``Assertion Summary``，生成
  :file:`dv/formal/build/ifv_summary.txt` 并打印。

接口关系：

* 被调用：顶层 sign-off 流程和人工 ``make -C dv/formal ifv``。
* 调用：Cadence IFV、:file:`dv/formal/ifv_filelist.f`、
  :file:`dv/formal/scripts/ifv_prove.tcl`。
* 共享状态：release 证据中的 formal ``46/46`` 来自 IFV summary，而不是
  ``ifv_count`` target 的源码标签统计。

§6  综合与 LEC 分流
-------------------

综合和 LEC 的统一入口是 :file:`syn/Makefile`。同一个 Makefile 同时保留开源
Yosys 路径、商业 Design Compiler 路径和 R3-C block-level Formality LEC 路径。

关键代码（``syn/Makefile:L42-L59``）：

.. code-block:: makefile

   .PHONY: syn-yosys syn-dc lec syn-full block_lec clean check-yosys check-prep wrapper

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

逐段解释：

* 第 42 行：Makefile 暴露 ``syn-yosys``、``syn-dc``、``lec``、``syn-full`` 和
  ``block_lec`` 等 target。每条路径的脚本细节分别在对应章节解释。
* 第 44~53 行：R3-C block-level LEC 只列出 9 个 top：
  ``eh2_dec``、``eh2_exu_alu_ctl``、``eh2_exu_mul_ctl``、``eh2_exu_div_ctl``、
  ``eh2_lsu``、``eh2_pic_ctrl``、``eh2_dma_ctrl``、``eh2_dbg``、``eh2_ifu``。
* 第 55~59 行：label、报告目录、DC run 目录、Formality run 目录和
  ``BLOCK_LEC_RESYNTH`` 控制 block-level LEC 是否复用已有 netlist。

接口关系：

* 被调用：``make -C syn syn-yosys``、``make -C syn syn-dc``、
  ``make -C syn block_lec`` 和顶层 sign-off 流程。
* 调用：Yosys、``dc_shell``、``fm_shell``、:file:`syn/scripts/lec_summary.py`。
* 共享状态：LEC sign-off 数字 ``31635/31635`` 对应 9 个 block-level 模块，
  决策依据见 :ref:`adr-0019` 与 :ref:`adr-0020`。

§7  Lint 分流
-------------

Lint 工具链由 :file:`lint/Makefile` 收集 RTL 和 DV SystemVerilog 文件，并按
Verible 与 Verilator 两条路径执行。顶层 ``lint`` target 依赖
``lint-verible`` 和 ``lint-verilator``。

关键代码（``lint/Makefile:L22-L32``）：

.. code-block:: makefile

   # Collect all SystemVerilog files
   RTL_SV  := $(shell find $(RTL_DIR) -name '*.sv' -type f 2>/dev/null)
   DV_SV   := $(shell find $(DV_DIR) -name '*.sv' -type f 2>/dev/null)
   ALL_SV  := $(RTL_SV) $(DV_SV)

   .PHONY: lint lint-verible lint-verilator clean

   $(BUILD_DIR):
           mkdir -p $(BUILD_DIR)

   lint: lint-verible lint-verilator

逐段解释：

* 第 23~25 行：Verible 路径使用 ``ALL_SV``，也就是 RTL 与
  :file:`dv/uvm/core_eh2` 下的 DV SystemVerilog 文件；Verilator target 在后续
  规则中只使用 ``RTL_SV``。
* 第 27 行：Makefile 把 ``lint``、``lint-verible``、``lint-verilator`` 和
  ``clean`` 声明为 phony target。
* 第 29~32 行：``lint`` 先确保 build 目录存在，再顺序触发 Verible 和 Verilator
  target。

接口关系：

* 被调用：``make -C lint lint``、``make -C lint lint-verible``、
  ``make -C lint lint-verilator``。
* 调用：``verible-verilog-lint``、``verilator``、规则文件和 waiver 文件。
* 共享状态：lint sign-off gate 只记录 PASS/FAIL，不产生 formal 或 LEC 的数量型
  proof object。

§8  汇编测试分流
----------------

汇编测试章节覆盖两类源：:file:`dv/uvm/core_eh2/tests/asm/` 下的 directed/cosim
程序，以及 :file:`tests/asm/` 下的仓库根部 smoke 样例。它们不是
``riscv-dv`` 随机生成器输出，而是已提交的 ``.S``、linker script、Makefile 和
testlist 配置。

阅读边界：

* 想看 mailbox、trap、PMP、AXI4 error、NB-load 和 coverage pump 汇编序列，读
  :ref:`appendix_c_tools/asm_tests`。
* 想看这些测试如何进入 directed 或 cosim regression，读
  :ref:`appendix_f_scripts/yaml_configs` 和 :ref:`scripts_reference`。
* 想看 UVM 如何加载 hex、监控 mailbox 和对接 cosim，读
  :ref:`appendix_b_uvm/tb`、:ref:`appendix_b_uvm/cosim_agent` 和
  :ref:`appendix_b_uvm/trace_agent`。

§9  ADR 与签核证据
------------------

本附录引用的设计决策只使用已存在 ADR：

* :ref:`adr-0012`：formal strategy。
* :ref:`adr-0013`：synthesis toolchain。
* :ref:`adr-0014`：formal real runs。
* :ref:`adr-0019`：LEC tool-version limitation。
* :ref:`adr-0020`：block-level LEC closure。

2026-05-19 签核证据边界：

* Formal gate：``46/46``，证据为 :file:`dv/formal/build/ifv_final.log`。
* LEC gate：``31635/31635``，证据为 :file:`syn/build/lec_summary.txt`。
* Cosim stage：当前主线使用 cosim-disabled waiver 受控关闭，见 :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`。
* Directed gate：``40/40``。
* RISC-V DV gate：``370/395`` （93.67%）。
* CSR unit gate：由 sign-off ``csr_unit`` stage 单独执行。
* Compliance gate：``85/88`` （96.59%）。
* Coverage：LINE ``95.05%``、BRANCH ``84.97%``、TOGGLE ``53.52%``、ASSERT ``33.33%``、FSM ``54.74%``、OVERALL ``65.17%``。

§10  参考资料
-------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.svh`
* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.cc`
* :file:`/home/host/eh2-veri/dv/cosim/cosim.h`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.cc`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.h`
* :file:`/home/host/eh2-veri/dv/formal/Makefile`
* :file:`/home/host/eh2-veri/dv/formal/ifv_filelist.f`
* :file:`/home/host/eh2-veri/dv/formal/eh2_veer_sva.sv`
* :file:`/home/host/eh2-veri/dv/formal/properties/`
* :file:`/home/host/eh2-veri/syn/Makefile`
* :file:`/home/host/eh2-veri/syn/scripts/`
* :file:`/home/host/eh2-veri/lint/Makefile`
* :file:`/home/host/eh2-veri/lint/verible/`
* :file:`/home/host/eh2-veri/lint/verilator/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/`

关联章节：

* :ref:`appendix_c_tools/cosim_cpp`
* :ref:`appendix_c_tools/formal_properties`
* :ref:`appendix_c_tools/formal_infra`
* :ref:`appendix_c_tools/syn_yosys`
* :ref:`appendix_c_tools/syn_nangate`
* :ref:`appendix_c_tools/syn_lec`
* :ref:`appendix_c_tools/lint_verible`
* :ref:`appendix_c_tools/lint_verilator`
* :ref:`appendix_c_tools/asm_tests`

§11  v2-9 强制资产审计
----------------------

本节是 v2-9 的工具附录审计入口，用来确认 Formal、Synthesis/LEC、Lint 与 CI
资产已经有可追溯章节承接。它不替代各深度页面的源码精读；它给后续 reviewer 一个
统一入口，避免在 ``dv/formal``、``syn``、``lint`` 和 ``.github`` 之间手工查找。

.. list-table::
   :header-rows: 1
   :widths: 30 30 40

   * - 资产组
     - 当前归属章节
     - v2-9 审计结论
   * - ``dv/formal/properties/eh2_*_assert.sv``
     - :ref:`appendix_c_tools/formal_properties`
     - 7 个 property 文件均已列入 formal properties 字典；Formal gate 证据仍以 IFV
       ``46/46`` 为准。
   * - ``dv/formal/scripts/*.tcl`` / ``*.sby``
     - :ref:`appendix_c_tools/formal_infra`
     - IFV 主证明、CEX dump 和 Symbiyosys 入口由基础设施章节承接。
   * - ``syn/scripts/*.tcl`` / ``lec_blocklevel/*.tcl``
     - :ref:`appendix_c_tools/syn_lec`、:ref:`appendix_c_tools/syn_nangate`
     - DC synthesis、Formality block LEC 和 legacy diagnostic Tcl 均属于 syn 工具章节。
   * - ``lint/verible`` / ``lint/verilator``
     - :ref:`appendix_c_tools/lint_verible`、:ref:`appendix_c_tools/lint_verilator`
     - rule、waiver skeleton、blocking gate 和 CI 触发条件分开解释。
   * - ``.github/workflows/lint.yml``
     - :ref:`ci_pipeline`、:ref:`appendix_c_tools/lint_verible`
     - CI 只跑 Verible DV lint；本地 full lint 仍由 ``lint/Makefile`` 跑双引擎。

关键代码（``.github/workflows/lint.yml:L1-L18``）：

.. literalinclude:: ../../../../.github/workflows/lint.yml
   :language: yaml
   :lines: 1-18
   :caption: /home/host/eh2-veri/.github/workflows/lint.yml:L1-L18

逐段解释：

* 第 L1-L5 行：workflow 名称和注释说明这是 blocking CI gate；waiver 文件位置也在注释中给出。
* 第 L7 行：触发条件是 ``push`` 和 ``pull_request``。
* 第 L10-L18 行：job 在 Ubuntu 上运行，先 checkout，再下载固定版本 Verible。

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L1-L20``）：

.. literalinclude:: ../../../../syn/scripts/lec_blocklevel/lec_common.tcl
   :language: tcl
   :lines: 1-20
   :caption: /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl:L1-L20

逐段解释：

* 第 L1-L4 行：注释说明该 common Tcl 服务 R3-C block-level Formality，复用 RC4
  reference wrapper 和 synthesized netlist，不屏蔽 compare points。
* 第 L6-L18 行：脚本设置 ``EH2_ROOT``、``BUILD_DIR``、``RPT_DIR`` 和 Formality
  run directory；如果环境变量 ``R3C_FM_RUN_DIR`` 存在，则优先使用外部指定目录。
* 第 L19-L20 行：切换到 run directory，并把 ``hdlin_temporary_dir`` 指向该目录。
  31635/31635 PASS 的汇总由 :file:`syn/scripts/lec_summary.py` 读取各 block 报告后生成。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？
