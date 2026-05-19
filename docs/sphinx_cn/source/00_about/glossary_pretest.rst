.. _glossary_pretest:
.. _00_about/glossary_pretest:

术语基线自测
============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
----------------

本章是读完 :ref:`reader` 和 :ref:`learning_path` 之后的第一道关卡。它不要求你会写
SystemVerilog 或 UVM，但要求你能把 EH2-Veri 的核心词汇、命令、路径和报告数字说清楚。
如果你只懂 C 语言，这是进入 :ref:`pipeline`、:ref:`tb_top`、:ref:`build_flow` 前
最小的术语地基。

开始前请确认：

* 你知道当前仓库根目录是 :file:`/home/host/eh2-veri`；
* 你知道 DUT 上游 clone 在 :file:`/home/host/Cores-VeeR-EH2/`；
* 你已经读过 :ref:`conventions`，知道 ``:file:``、``:ref:``、命令块和表格的含义；
* 你知道默认 simulator 是 :term:`VCS`，:term:`NC/Incisive` 是完整备选 simulator；
* 你能在 shell 中运行 ``pwd``、``ls``、``rg`` 和 ``make help``。

学完本章你能：

1. 区分 :term:`DUT`、:term:`TB`、:term:`env`、:term:`agent`、:term:`monitor`、
   :term:`scoreboard`、:term:`coverage`、sign-off 和 :term:`LEC`；
2. 看到 ``build/smoke_vcs``、``build/smoke_nc``、``cov.vdb``、``cov_work`` 时知道它们
   分别属于哪条工具路径；
3. 解释最新 demo 数据中的 :term:`LINE` 95.05%、:term:`GROUP` 69.42%、
   :term:`OVERALL` 65.17% 和 :term:`LEC` 31635/31635 PASS；
4. 在首次阅读某个技术章节前判断自己缺的是微架构、UVM、工具命令还是报告口径。

§1  为什么要先做术语自测
------------------------

处理器验证平台的学习难点不只是代码多，而是同一个词跨越多层语境。例如 ``trace`` 在
软件世界可能指日志，在本平台中通常指 retire trace transaction；:term:`coverage` 既可能是
:term:`VCS` 的 :term:`LINE` / :term:`BRANCH` / :term:`TOGGLE`，也可能是 SystemVerilog
covergroup 的 :term:`GROUP`；``signoff``
不是一次仿真，而是 9 个 stage 的质量门禁。

如果术语不稳，后续会出现三类典型误解：

* 把 ``make smoke`` 的 PASS 当作 sign-off PASS，忽略 directed、riscv-dv、formal、
  compliance 和 LEC；
* 把 :term:`GROUP` 当作 URG 综合分，或者把 :term:`LINE` 95.05% 当成功能覆盖率；
* 把 :term:`NC/Incisive` 误认为只能看波形，忽略它在 v2 基线中同样支持 compile / smoke / regress /
  signoff / demo 与独立覆盖率合并。

本章用小题把这些误解提前暴露。做题时不要背答案；每题都给出一条可在本机运行的
核对命令，让你把概念落到文件和输出上。

§2  核心术语速查图
------------------

::

   /home/host/eh2-veri
        |
        |-- Makefile              -> compile / smoke / regress / signoff / demo
        |-- dv/uvm/core_eh2       -> UVM TB、agent、scoreboard、coverage、scripts
        |-- dv/cosim              -> Spike DPI C++ bridge
        |-- dv/formal             -> IFV / Symbiyosys property flow
        |-- syn                   -> DC synthesis + Formality LEC
        |-- docs/sphinx_cn        -> 本手册
        |
        `-- build/<target>_<simulator>
              |-- smoke_vcs       -> VCS smoke 产物
              |-- smoke_nc        -> NC smoke 产物
              |-- signoff_vcs     -> 默认 sign-off 主线
              `-- signoff_nc      -> NC 备选 sign-off/cross-check

.. list-table:: 入门必须会说清的 12 个词
   :header-rows: 1
   :widths: 18 26 56

   * - 术语
     - 你应该先怎么理解
     - EH2-Veri 中的落点
   * - :term:`DUT`
     - 被验证的硬件设计
     - ``core_eh2_tb_top.dut`` 下的 EH2 RTL
   * - :term:`TB`
     - testbench，包住 DUT 的验证世界
     - :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
   * - :term:`env`
     - UVM 验证环境
     - 创建 AXI4、IRQ、JTAG、trace、cosim 等 agent
   * - :term:`agent`
     - 某类接口的 UVM 封装
     - ``common/*_agent`` 目录
   * - :term:`monitor`
     - 被动采样信号并发出 transaction
     - AXI4 monitor、trace monitor、DUT probe monitor
   * - :term:`scoreboard`
     - 比对 DUT 与参考模型
     - ``eh2_cosim_scoreboard`` 对比 RTL 与 Spike
   * - Spike
     - RISC-V ISA simulator
     - cosim 的 golden reference
   * - DPI
     - SystemVerilog 调 C/C++ 的接口
     - ``dv/cosim/spike_cosim.cc`` 与 ``cosim_dpi.svh``
   * - :term:`coverage`
     - 覆盖率度量
     - VCS/NC code coverage + SystemVerilog covergroup
   * - sign-off
     - 工业签收门禁
     - smoke/direct/cosim/riscvdv/lint/csr/compliance/formal/syn
   * - waiver
     - 有边界的例外说明
     - 不能覆盖 25% 以上 fail-rate 的 stage
   * - :term:`LEC`
     - 逻辑等价检查
     - Formality block-level LEC，最新 31635/31635 PASS

§3  路径与命令题
----------------

下面 5 题检验你是否能把术语映射到真实路径。每题都能在仓库根目录运行。

.. list-table:: 路径与命令自测
   :header-rows: 1
   :widths: 8 42 30 20

   * - 题号
     - 问题
     - 核对命令
     - 合格答案
   * - 1
     - 顶层 ``smoke`` target 在哪个文件定义？
     - ``rg -n "^smoke:" Makefile``
     - :file:`Makefile`
   * - 2
     - UVM TB top 文件在哪里？
     - ``ls dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``
     - 该路径存在
   * - 3
     - cosim scoreboard 类在哪里？
     - ``rg -n "class eh2_cosim_scoreboard" dv/uvm/core_eh2``
     - cosim agent 目录
   * - 4
     - VCS coverage scope 文件叫什么？
     - ``ls dv/uvm/core_eh2/cover.cfg``
     - ``cover.cfg``
   * - 5
     - NC coverage 等价配置文件叫什么？
     - ``ls dv/uvm/core_eh2/cov_full_nc.ccf``
     - ``cov_full_nc.ccf``

§4  Simulator 口径题
--------------------

:term:`VCS` 与 :term:`NC/Incisive` 都能跑 EH2-Veri，但默认职责不同。当前口径是：
:term:`VCS` 为默认 simulator 和 release 参考主线，:term:`NC/Incisive` 为完整备选
simulator，可用于 compile、smoke、regress、signoff、demo 和波形调试。不要再使用
“NC 只能看波形”的旧说法。

.. list-table:: VCS / NC 对照自测
   :header-rows: 1
   :widths: 24 38 38

   * - 维度
     - :term:`VCS`
     - :term:`NC/Incisive`
   * - 默认性
     - ``SIMULATOR`` 默认值，sign-off 主线
     - 显式 ``SIMULATOR=nc`` 启用
   * - 编译产物
     - ``simv``、``simv.daidir``、``csrc``
     - ``INCA_libs``
   * - 覆盖率数据库
     - ``cov`` / ``cov.vdb``，URG 读取
     - ``cov_work``，IMC/脚本合并后输出统一 dashboard
   * - scope 配置
     - :term:`cover.cfg`，``+tree core_eh2_tb_top.dut``
     - :term:`cov_full_nc.ccf`，选择 DUT-only instance
   * - 波形
     - FSDB，通常用 Verdi 打开
     - SHM / SimVision，也支持 ``make wave_nc``

判断题：

1. ``make smoke`` 默认等价于 ``make smoke SIMULATOR=vcs``。答案：对。
2. ``make smoke SIMULATOR=nc`` 只能用于看波形，不会生成 pass/fail 结果。答案：错。
3. ``build/smoke_vcs`` 和 ``build/smoke_nc`` 可以并存。答案：对。
4. :term:`VCS` coverage 使用 ``-cm line+tgl+assert+fsm+branch``，不包含 ``cond``。答案：对。
5. :term:`NC/Incisive` 的 :term:`cov_full_nc.ccf` 是 v2 基线必须覆盖的配置资产。答案：对。

§5  覆盖率数字题
----------------

最新 demo 的 :term:`coverage` dashboard 使用统一展示口径：

.. list-table:: 最新覆盖率数字自测
   :header-rows: 1
   :widths: 16 18 66

   * - 字段
     - 最新值
     - 正确解释
   * - LINE
     - 95.05%
     - RTL 行覆盖率，不等于功能覆盖率
   * - BRANCH
     - 84.97%
     - 分支覆盖率，来自 simulator code coverage
   * - TOGGLE
     - 53.52%
     - portsonly toggle 口径，数字通常低于 LINE
   * - ASSERT
     - 33.33%
     - assertion coverage，不能和 SVA pass 数混为一谈
   * - FSM
     - 54.74%
     - 状态机覆盖率
   * - GROUP
     - 69.42%
     - SystemVerilog covergroup，属于 functional coverage 口径
   * - OVERALL
     - 65.17%
     - URG/统一 dashboard 综合分，不是任何单一维度

填空题：

1. 如果文档写 ``line+cond+tgl``，这是过时口径；当前 VCS 维度应写
   ``line+tgl+assert+fsm+branch``。
2. 如果 LINE 是 95.05%，但 GROUP 是 69.42%，说明代码执行很充分，但功能场景仍有
   closure 空间。
3. ``build/signoff_vcs/cov_merged/dashboard.txt`` 是最新 sign-off coverage 的常用入口。

§6  Sign-off 题
---------------

Sign-off 不是“跑过一个测试”，而是 9 stage 门禁。最新完整 demo 实测结果是：
``Status: PASS``，``9/9 Stages PASS``，LEC ``31635/31635 PASS``。

.. list-table:: 9 stage 自测
   :header-rows: 1
   :widths: 18 42 40

   * - Stage
     - 你应该先怎么理解
     - 最新数据或入口
   * - smoke
     - 最小冒烟，快速验证编译与基本运行
     - ``make smoke``
   * - directed
     - 手写 assembly 覆盖指定风险
     - ``40/40``
   * - cosim
     - RTL 与 Spike lock-step diff
     - ``+enable_cosim=1`` 场景
   * - riscvdv
     - 随机指令生成回归
     - ``370/395 (93.67%)``
   * - lint
     - 静态规则检查
     - Verible + Verilator
   * - csr_unit
     - CSR 子环境
     - ``dv/uvm/cs_registers_eh2``
   * - compliance
     - RISC-V compliance signature
     - ``85/88 (96.59%)``
   * - formal
     - IFV/Symbiyosys property
     - ``46/46 (100%)``
   * - syn
     - DC + LEC gate
     - LEC ``31635/31635 PASS``

判断题：

1. ``make signoff PROFILE=quick`` 可以替代 full sign-off。答案：错，只能快速检查。
2. stage 失败率超过 25% 时，不应靠 waiver 继续签收。答案：对。
3. LEC PASS 说明综合前后逻辑等价，但不替代 UVM regression。答案：对。

§7  UVM 代码阅读题
------------------

读 UVM 章节前，你至少要会把类名和职责对上。

.. list-table:: UVM 职责匹配题
   :header-rows: 1
   :widths: 28 32 40

   * - 类或文件
     - 关键词
     - 正确职责
   * - ``core_eh2_tb_top.sv``
     - ``run_test``
     - testbench 顶层，例化 DUT 并启动 UVM
   * - ``core_eh2_env.sv``
     - ``build_phase`` / ``connect_phase``
     - 创建和连接各类 agent
   * - ``axi4_monitor.sv``
     - ``VALID`` / ``READY``
     - 采样 AXI4 transaction
   * - ``eh2_trace_monitor.sv``
     - retire
     - 采样退役指令
   * - ``eh2_cosim_scoreboard.sv``
     - ``riscv_cosim_step``
     - 驱动 Spike 并比对结果
   * - ``eh2_fcov_if.sv``
     - ``covergroup``
     - 采集功能覆盖率

自测命令：

.. code-block:: bash

   rg -n "run_test|class core_eh2_env|class axi4_monitor|riscv_cosim_step|covergroup" \
     dv/uvm/core_eh2

能把每个 grep 命中行归到上表的一行，才建议进入 :ref:`tb_top` 和 :ref:`agent_axi4`。

§8  常见错误答案
----------------

.. list-table:: 新人最常见的术语误解
   :header-rows: 1
   :widths: 32 32 36

   * - 错误说法
     - 为什么错
     - 正确说法
   * - NC 只能看波形
     - v2 基线中 NC 支持 compile/smoke/regress/signoff/demo
     - NC 是完整备选 simulator，VCS 是默认主线
   * - GROUP 就是 OVERALL
     - GROUP 是 covergroup，OVERALL 是综合分
     - 两者都要看，但语义不同
   * - smoke pass 等于 sign-off pass
     - smoke 只是一条最小路径
     - sign-off 需要 9 stage
   * - Spike 是 RTL 的一部分
     - Spike 是 C++ ISS，不在 DUT RTL 中
     - RTL 通过 DPI 与 Spike 比对
   * - waiver 可以解释所有失败
     - 25% fail-rate ceiling 会阻止大面积失败签收
     - waiver 只能解释明确、可边界化的例外

§9  动手练习
------------

入门题（5 分钟）：

.. code-block:: bash

   cd /home/host/eh2-veri
   make help | sed -n '1,80p'

写下 ``compile``、``smoke``、``regress``、``signoff``、``demo`` 5 个 target 的一句话作用。
参考答案在 :ref:`build_flow` 和 :ref:`regression_flow`。

进阶题（20 分钟）：

.. code-block:: bash

   rg -n "VCS_COV_METRICS|NC_COV_CCF|SIGNOFF_MIN_LINE_COV|SIGNOFF_MIN_FUNCTIONAL_COV" Makefile

写下 VCS coverage 维度、NC coverage 配置文件、LINE 门限和 GROUP/functional 门限。
参考答案在 :ref:`coverage_plan` 与 :ref:`functional_coverage`。

挑战题（45 分钟）：

.. code-block:: bash

   rg -n "class eh2_cosim_scoreboard|riscv_cosim_step|report_phase" \
     dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv

把 3 个命中点分别归类为“类定义”“Spike step 调用”“最终结果报告”。如果能说出三者
的先后关系，就可以开始读 :ref:`cosim_scoreboard`。

§10  自检 5 问
------------------------

读完本章后，请不看答案回答：

1. DUT、TB、env、agent、monitor、scoreboard 的层级关系是什么？
2. ``build/smoke_vcs`` 与 ``build/smoke_nc`` 的差异是什么？为什么可以并存？
3. LINE 95.05%、GROUP 69.42%、OVERALL 65.17% 三个数字分别表示什么？
4. 为什么 ``make smoke`` 不能替代 ``make signoff``？
5. 如果日志里出现 ``riscv_cosim_step``，你应该联想到哪两个世界正在交互？

若 5 题中有 2 题答不上来，建议先回到 :ref:`learning_path` §3 和本章 §2-§6，
不要急着进入源码章节。

§11  参考资料
-------------

* :ref:`reader` — 读者画像与阅读路径；
* :ref:`learning_path` — 零基础 4 周学习路线；
* :ref:`conventions` — RST、路径、代码块、表格约定；
* :ref:`glossary` — 全量术语表；
* :ref:`build_flow` — Make 与编译流程；
* :ref:`regression_flow` — 回归调度与结果收集；
* :ref:`signoff_flow` — 9 stage sign-off 门禁；
* :ref:`functional_coverage` — coverage 数字和 covergroup 语义。
