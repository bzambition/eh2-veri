.. _troubleshooting:
.. _08_appendix/troubleshooting:

常见问题排查
============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本章给出 EH2 验证平台的常见问题排查路径，覆盖 VCS 编译、仿真挂起、cosim mismatch、
coverage 缺失、waiver gate、formal、LEC、compliance 和 Sphinx 构建。排障原则是先
定位失败属于哪个 stage，再看该 stage 的权威日志；不要先改文档或 gate 阈值。

当前主线是 VCS。NC/Incisive 只用于 ``make smoke|regress SIMULATOR=nc WAVES=1``
单测波形调试；若 sign-off 或 coverage 失败，应优先检查 VCS/URG 产物。

设计目标与约束
--------------

排障步骤必须满足 3 个条件：命令真实存在，日志路径来自当前代码，修复动作不会掩盖
失败。对于 waiver 相关问题，唯一正式豁免来源是
:file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`；testlist 中的说明性字段不能替代
waiver。对于 coverage 相关问题，唯一 release coverage 来源是 VCS ``.vdb`` 经 URG
生成的 dashboard。

架构与组成
----------

排障入口可以按 sign-off stage 分组：

::

   make signoff
      |
      +-- precheck       filelist, simulator, toolchain, libcosim
      +-- smoke          basic RTL run
      +-- directed       directed ASM/testlist
      +-- cosim          Spike DPI + scoreboard
      +-- riscvdv        generator + ISS compare + regression metadata
      +-- lint           Verible / Verilator
      +-- csr_unit       CSR sub-env
      +-- compliance     RISC-V compliance framework
      +-- formal         IFV / property logs
      +-- syn            DC + Formality LEC
      `-- coverage       VCS .vdb -> merge_cov.py -> URG dashboard

实现细节
--------

sign-off CLI 暴露了排障所需的主要开关：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 1536-1586
   :caption: signoff.py:1536-1586 - sign-off CLI 排障参数

coverage 失败通常落在 `evaluate_coverage()` 的 blocker 中：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 1046-1107
   :caption: signoff.py:1046-1107 - coverage gate 排障点

waiver 失败由 final gate 统一检查：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 1302-1385
   :caption: signoff.py:1302-1385 - waiver 和最终 gate

URG merge 失败先看 `merge_cov.py` 的工具调用和错误码：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/merge_cov.py
   :language: python
   :lines: 45-84
   :caption: merge_cov.py:45-84 - URG merge 命令

配置与使用
----------

基础排障命令：

.. code-block:: bash

   # 查看 full profile 计划，不运行 stage
   python3 dv/uvm/core_eh2/scripts/signoff.py --profile full --dry-run

   # 运行完整 sign-off
   make signoff COV=1 PARALLEL=4

   # 复用已有 stage 目录重新 gate
   make signoff_replay STAGE_DATA_DIR=build/demo

   # 校验 cosim-disabled waiver schema
   python3 dv/uvm/core_eh2/scripts/signoff.py \
     --validate-waivers dv/uvm/core_eh2/waivers/cosim-disabled.yaml

   # 单测波形调试
   make smoke SIMULATOR=nc WAVES=1

常见问题表
----------

.. list-table:: 常见失败与第一检查点
   :header-rows: 1
   :widths: 24 32 44

   * - 症状
     - 第一检查点
     - 处理建议
   * - ``signoff`` 拒绝 simulator
     - :file:`Makefile` 的 ``signoff`` target
     - 当前只接受 ``SIMULATOR=vcs`` 或 ``SIMULATOR=nc``；VCS 是默认 release 参考，
       NC 是完整备选 simulator
   * - VCS compile 找不到 RTL
     - :file:`dv/uvm/core_eh2/eh2_rtl.f`
     - 检查上游 RTL clone、filelist 路径和环境变量
   * - ``libcosim.so`` 缺失
     - :file:`build/libcosim.so`
     - 运行 ``make cosim``，不要用关闭 cosim 方式掩盖 directed cosim 失败
   * - cosim PC mismatch
     - scoreboard log、trace item、Spike PC
     - 先判断是 exception、interrupt、debug、compressed next-PC 还是 retire 顺序问题
   * - GPR mismatch
     - trace/probe writeback、``wb_tag``
     - 检查 long-latency writeback hint、DIV/NB-load 和 strict tag 匹配
   * - CSR mismatch
     - CSR register model、Spike fixup、WARL 字段
     - 判断是否为 EH2 custom CSR、debug CSR 或 PIC CSR
   * - memory mismatch
     - AXI4 monitor、store WSTRB、PMP fault
     - 对照 ADR-0005、ADR-0009 和 AXI4 transaction
   * - coverage report missing
     - ``build/<out>/cov_merged/dashboard.txt``
     - 确认 ``COV=1``、VCS ``.vdb`` 存在、``urg`` 在 PATH
   * - waiver schema fail
     - :file:`cosim-disabled.yaml`
     - 每条 entry 必须有 test、reason、tracking_issue、expiry_date
   * - formal stage fail
     - :file:`dv/formal/build/`
     - 查看 IFV log 和 property 名称，不要只看 Make 返回码
   * - LEC stage fail
     - :file:`syn/build/lec_summary.txt`
     - 先看 failing/unverified compare points，再定位 block report
   * - Sphinx build warning
     - warning 行号和引用路径
     - 修复 `literalinclude` 行号、重复 label 或未定义引用

Cosim mismatch 细分
-------------------

cosim mismatch 需要先按事务类型分类：

.. list-table:: cosim mismatch 分类
   :header-rows: 1
   :widths: 20 36 44

   * - 类型
     - 典型根因
     - 关联章节
   * - PC
     - compressed 指令长度、trap/interrupt、debug return、retire 顺序
     - :ref:`rvfi_trace`、:ref:`agent_trace`
   * - GPR
     - writeback hint、DIV cancel、NB-load、wb_tag 错位
     - :ref:`cosim_scoreboard`
   * - CSR
     - EH2 custom CSR、WARL、debug CSR、PIC CSR
     - :ref:`csr`
   * - memory
     - AXI4 WSTRB、PMP fault、store buffer、misaligned access
     - :ref:`agent_axi4`、:ref:`pmp_coverage`
   * - exception
     - mcause、mepc、mtval、mscause、trap priority
     - :ref:`pipeline`、:ref:`csr`

覆盖率排查
----------

coverage 失败遵循以下顺序：

1. 确认命令带了 ``COV=1`` 或 `--coverage`。
2. 确认 build/run 目录下有 VCS ``.vdb``。
3. 确认 ``merge_cov.py`` 输出 ``cov_merged/dashboard.txt``。
4. 确认 dashboard 中 LINE 和 GROUP 数字被解析。
5. 若 ASSERT/FSM 偏低，进入 URG detail report 分析具体未命中对象。

.. code-block:: bash

   find build -name "*.vdb" -type d | head
   python3 dv/uvm/core_eh2/scripts/merge_cov.py --dirs build/demo --output build/manual_cov
   sed -n '1,80p' build/manual_cov/dashboard.txt

与 Ibex 工业实现对照
--------------------

Ibex 排障通常从 regression metadata、sim log、ISS compare 和 coverage report 入手。
EH2 对齐这种顺序，但额外关注 AXI4、trace/probe、waiver YAML 和 block-level LEC。

测试与验证
----------

每次修复排障文档后，至少运行：

.. code-block:: bash

   rg -n "旧默认入口|旧覆盖率数字|旧产物路径" docs/sphinx_cn/source/08_appendix
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

已知限制与未来工作
------------------

本章给的是第一轮定位路径，不替代具体章节的深入分析。若定位到 RTL、UVM agent、
Spike DPI、formal property 或 LEC script，应跳转到相应章节和附录继续处理。

参考资料
--------

* :ref:`signoff_flow` - sign-off gate 和报告。
* :ref:`scripts_reference` - 脚本 CLI。
* :ref:`cosim_scoreboard` - cosim 比对器。
* :ref:`coverage_plan` - coverage gate。
* :ref:`known_limitations` - 已知限制。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：确认索引、术语、附录或兼容旧入口不会破坏整本手册构建。

.. code-block:: bash

   sphinx-build -W --keep-going -b html docs/sphinx_cn/source /tmp/eh2-doc-practice-check
   rg -n "自检 5 问|动手练习" docs/sphinx_cn/source | head -80

**进阶题**：抽查参考页是否使用当前统一平台口径。

.. code-block:: bash

   rg -n "95.05|31635/31635|line\+tgl\+assert\+fsm\+branch|NC/Incisive" docs/sphinx_cn/source | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
