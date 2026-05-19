.. _learning_path:
.. _00_about/learning_path:

学习路线图
==========

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
-----------------

本章面向“只懂 C 语言、第一次接触 SystemVerilog/UVM 的工科学生”，也兼顾已经有
验证经验但第一次进入 EH2-Veri 工作区的工程师。读懂本章不要求你先会写 UVM；
你只需要能使用 Linux shell、读懂基本 C 代码、理解“程序由指令组成”这一点。

开始前请确认：

* 你知道仓库根目录是 :file:`/home/host/eh2-veri`；
* 你知道 DUT 上游 clone 是 :file:`/home/host/Cores-VeeR-EH2/`；
* 你已经读过 :ref:`reader`，知道本手册的路径和术语约定；
* 你愿意先“照着跑通”，再回头理解每一层源码。

学完本章你能：

1. 按 4 周节奏从零基础走到能写第一个 directed test；
2. 知道每天该读哪几章、跑哪几条命令、产出什么检查物；
3. 在卡住时选择正确排查入口，而不是在 100,000+ 行文档里盲找；
4. 判断自己是否已经具备进入 :ref:`tb_top`、:ref:`agent_cosim` 或
   :ref:`signoff_flow` 的前置知识。

§1  本章为什么存在
-------------------

v1 手册已经覆盖 157 个 RST 文件和 141,000+ 行内容，适合工程师查资料；
但零基础读者会遇到一个实际问题：章节太全，反而不知道先读哪一章。比如你刚跑
``make smoke`` 失败，理论上可以查 :ref:`getting_started`、:ref:`quickstart`、
:ref:`build_flow`、:ref:`tb_top`、:ref:`cosim_scoreboard` 和
:ref:`troubleshooting`，但新人不知道失败属于“构建失败”“仿真失败”还是
“scoreboard mismatch”。

本章把手册重排成学习路径，而不是项目结构。项目结构回答“文件在哪里”，学习路径回答
“今天该学什么、跑什么、看什么输出”。它不替代任何技术章节，只给出进入技术章节前的
顺序、检查点和失败分流。

§2  四周全局路线图
-------------------

下面的 4 周安排假设你每天投入 1 到 2 小时。若你已经熟悉 SystemVerilog 或 UVM，
可以跳过前置知识练习，但不要跳过命令检查点；EH2-Veri 的很多概念只有跑过日志后才稳。

.. list-table:: 4 周学习目标
   :header-rows: 1
   :widths: 12 28 30 30

   * - 周次
     - 学习目标
     - 必读章节
     - 交付物
   * - 第 1 周
     - 跑通环境、理解 EH2 是什么
     - :ref:`reader`、:ref:`introduction`、:ref:`getting_started`、:ref:`quickstart`
     - 一份 smoke 日志定位记录
   * - 第 2 周
     - 看懂 DUT/TB 边界和第一批 UVM 组件
     - :ref:`pipeline`、:ref:`tb_top`、:ref:`05_verification_arch/env`、
       :ref:`05_verification_arch/agent_axi4`
     - 一张 TB top 连接图和 5 个关键信号说明
   * - 第 3 周
     - 理解 cosim、coverage、regression
     - :ref:`05_verification_arch/agent_cosim`、:ref:`05_verification_arch/cosim_scoreboard`、
       :ref:`functional_coverage`、:ref:`regression_flow`
     - 一次 directed 或 cosim 单测复现记录
   * - 第 4 周
     - 写 directed test，理解 sign-off 门禁
     - :ref:`tests_library`、:ref:`vseq_library`、:ref:`signoff_flow`、
       :ref:`coverage_plan`
     - 一个新 directed test 草案或 coverage closure 建议

§3  第 1 周：先跑起来
---------------------

第 1 周的目标不是读完所有概念，而是建立“命令 → 产物 → 日志 → 下一步”的闭环。
你需要先知道 EH2 是什么，再让本机跑出最小 smoke。

.. list-table:: 第 1 周每日计划
   :header-rows: 1
   :widths: 10 30 30 30

   * - 天数
     - 阅读
     - 命令
     - 检查点
   * - D1
     - :ref:`reader` §0-§5
     - ``pwd``、``ls docs/sphinx_cn/source``
     - 能说出自己属于哪类读者
   * - D2
     - :ref:`introduction` §0-§3
     - ``ls /home/host/Cores-VeeR-EH2/design``
     - 能指出 ``eh2_veer.sv`` 和 ``eh2_veer_wrapper.sv``
   * - D3
     - :ref:`getting_started` §0-§3
     - ``cd /home/host/eh2-veri``；``source env.sh``
     - 能解释 ``GCC_PREFIX`` 和 ``EH2_VERIF_ROOT``
   * - D4
     - :ref:`getting_started` §4-§5
     - ``make compile NO_COSIM=1 SIMULATOR=vcs``
     - 找到 ``build/compile_vcs/simv`` 或对应编译日志
   * - D5
     - :ref:`quickstart` §0-§4
     - ``make smoke SIMULATOR=vcs``
     - 找到 ``build/smoke_vcs`` 和 ``sim_*.log``
   * - D6
     - :ref:`quickstart` §5-§8
     - ``make regress TESTLIST=directed ITERATIONS=1 PARALLEL=1``
     - 能区分 smoke 与 directed testlist
   * - D7
     - 复盘本周日志
     - ``rg -n "TEST PASSED|UVM_ERROR|UVM_FATAL" build/smoke_vcs``
     - 写下第一个 PASS 或失败关键字

.. note::

   如果你没有 VCS license，本周不要硬卡在编译阶段。先读 :ref:`system_requirements`
   和 :ref:`build_flow`，确认工具路径，再用已有日志或老师提供的 build 产物学习目录结构。

§4  第 2 周：看懂硬件边界
-------------------------

第 2 周开始进入代码，但仍不要求你一次看完所有 RTL。先抓住三层边界：
DUT wrapper 的端口、TB top 的连接、UVM env 的接口发布。

关键读法是“从外到内”：

1. :ref:`tb_top` 先看 ``core_eh2_tb_top.sv`` 如何例化 DUT；
2. :ref:`pipeline` 再看指令在 IFU/DEC/EXU/LSU 之间如何流动；
3. :ref:`05_verification_arch/env` 看 UVM env 如何拿到 virtual interface；
4. :ref:`05_verification_arch/agent_axi4` 看外部总线 monitor 如何观察 LSU/IFU 访问。

本周建议画一张自己的连接图，至少包含：

* ``core_eh2_tb_top``；
* ``dut`` / ``eh2_veer_wrapper_rvfi``；
* ``lsu_axi_*``、``ifu_axi_*``、``trace``、``dut_probe``；
* ``core_eh2_env``；
* ``axi4_agent``、``trace_agent``、``cosim_agent``。

§5  第 3 周：理解验证闭环
-------------------------

第 3 周的目标是看懂“为什么测试通过不等于验证充分”。EH2-Veri 不只看 mailbox PASS，
还要做 Spike lock-step、功能覆盖、RISC-V compliance、formal 和 LEC。

建议最小路径：

.. code-block:: bash

   cd /home/host/eh2-veri
   make regress TESTLIST=cosim ITERATIONS=1 PARALLEL=1 SIMULATOR=vcs
   make regress TESTLIST=directed ITERATIONS=1 PARALLEL=1 SIMULATOR=vcs COV=1

读日志时先找三类证据：

* mailbox 是否写 PASS；
* cosim scoreboard 是否出现 mismatch；
* coverage 是否生成在目标 ``build/<target>_<simulator>/`` 子目录。

§6  第 4 周：写第一个 directed test
------------------------------------

第 4 周开始动手写测试。你不需要马上写复杂 UVM sequence；先写一条 assembly directed
test，确认它能进入 testlist、编译成 hex、被 regression 调度，再看 coverage 是否有贡献。

最小流程：

1. 在 :file:`dv/uvm/core_eh2/tests/asm/` 找一个相近的 ``directed_*.S``；
2. 复制成新文件，先只改注释和一个可观察的寄存器写；
3. 把测试加入 :file:`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`；
4. 跑 ``make regress TEST=<new_test_name> ITERATIONS=1 PARALLEL=1``；
5. 如果失败，先查 :ref:`tests_library` 和 :ref:`troubleshooting`，再进入 waveform。

后续 v2 会在 :file:`appendix_g_tutorials/g02_write_first_directed.rst` 给出完整 2 小时教程。

§7  学习检查点与实测数据
-------------------------

本路线图的最终目标不是“读完文档”，而是能解释当前平台的质量证据。
你在第 4 周结束时应能读懂以下数字：

.. list-table:: 当前 sign-off 关键数据
   :header-rows: 1
   :widths: 28 24 48

   * - 指标
     - 当前值
     - 你应能解释的问题
   * - 9-stage sign-off
     - 9/9 Stages PASS
     - 哪 9 个 stage，各自验证什么
   * - LEC
     - 31635/31635 PASS
     - 为什么综合后还要做等价性检查
   * - VCS/URG LINE
     - 95.05%
     - 为什么只看 DUT subtree
   * - GROUP
     - 69.42%
     - covergroup 与 line coverage 有何不同
   * - directed
     - 40/40 PASS
     - 为什么 directed 不能被 riscv-dv 完全替代
   * - formal
     - 46/46 PASS
     - SVA property 和动态仿真有什么互补关系

§8  常见失败模式与排查
-----------------------

.. list-table:: 学习阶段常见卡点
   :header-rows: 1
   :widths: 24 30 30 16

   * - 现象
     - 根因
     - 排查命令
     - 下一章
   * - ``source env.sh`` 后工具仍找不到
     - shell 没加载当前文件，或工具路径不在本机
     - ``env | rg 'EH2|GCC|RISCV'``
     - :ref:`system_requirements`
   * - ``make compile`` 找不到 VCS
     - EDA license 或 PATH 未配置
     - ``which vcs``；``make compile SIMULATOR=nc``
     - :ref:`build_flow`
   * - ``make smoke`` 没有 PASS
     - 编译产物、hex、timeout 或 mailbox 路径问题
     - ``rg -n 'TEST PASSED|UVM_FATAL|mailbox' build/smoke_vcs``
     - :ref:`quickstart`
   * - 看不懂 ``uvm_config_db``
     - 还没建立 UVM component 与 virtual interface 模型
     - ``rg -n 'uvm_config_db::set|get' dv/uvm/core_eh2``
     - :ref:`tb_top`
   * - cosim mismatch 不知道从哪查
     - 没区分 trace、probe、Spike step 和 scoreboard
     - ``rg -n 'mismatch|UVM_ERROR|spike' build``
     - :ref:`cosim_scoreboard`

§9  动手练习
------------

**入门题（5 分钟）**：

1. 在仓库根运行 ``rg -n "^smoke:" Makefile``，写下 ``smoke`` target 的行号。
   参考答案位置：本章 §3 和 :ref:`getting_started` §5。

**进阶题（30 分钟）**：

2. 跑 ``make smoke SIMULATOR=vcs``，然后在 ``build/smoke_vcs`` 下用
   ``rg -n "TEST PASSED|UVM_ERROR|UVM_FATAL"`` 找到结果关键字。
   若本机没有 VCS，改为阅读已有 smoke 日志并写出缺失工具名称。
   参考答案位置：:ref:`quickstart` §5-§7。

**挑战题（2 小时）**：

3. 选一个现有 ``directed_*.S``，追踪它从 ``directed_testlist.yaml`` 到
   ``run_regress.py`` 再到仿真日志的路径，画出“testlist → binary → simv → log”链路。
   参考答案位置：后续 :file:`appendix_g_tutorials/g02_write_first_directed.rst`。

§10  自检 5 问
------------------------

读完本章，你应该能回答：

1. 为什么零基础读者应先跑 smoke，再读 scoreboard 源码？
2. ``NO_COSIM=1``、``+disable_cosim=1`` 和 cosim scoreboard 分别处于哪一层？
3. 第 2 周为什么先看 TB top，而不是先看任意一个 UVM agent？
4. 当前 LINE 95.05% 和 GROUP 69.42% 分别来自哪类覆盖率？
5. 你要写第一个 directed test 时，最少需要改哪两个文件？

不能回答第 2 题时，回到 :ref:`quickstart`；不能回答第 3 题时，回到
:ref:`tb_top`；不能回答第 5 题时，先读 :ref:`tests_library`。

§11  参考资料
--------------

* :ref:`reader` — 读者画像与前置知识；
* :ref:`introduction` — EH2 项目背景；
* :ref:`getting_started` — 从工作区到 smoke 的命令细节；
* :ref:`quickstart` — 验证平台快速路径；
* :ref:`pipeline` — EH2 流水线和双发射；
* :ref:`tb_top` — testbench 顶层连接；
* :ref:`signoff_flow` — 9-stage sign-off；
* :file:`/home/host/eh2-veri/Makefile` — 顶层 target；
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
  — directed testlist。
