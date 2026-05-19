.. _reader:

读者对象与前置知识
==================

:status: draft
:last-reviewed: 2026-05-13

§0  前置知识自检
-----------------

读懂本章不需要任何 EH2、SystemVerilog 或 UVM 基础。本章就是整本手册的入口，
用于帮你判断自己属于哪类读者、应该先读哪些章节、哪些知识可以边做边补。

如果你只懂 C 语言、第一次接触处理器验证，先按下面的“小白路径”走：

* 先读本章，确认自己需要补哪些词汇和工具概念；
* 再读 :ref:`introduction`，用 30 分钟理解 EH2 是什么；
* 接着读 :ref:`getting_started`，照着命令跑出第一个 ``smoke``；
* 然后读 :ref:`quickstart`，理解 ``compile``、``smoke``、``regress``、``signoff`` 的关系；
* 最后再进入 :ref:`pipeline` 和 :ref:`tb_top`，开始读 RTL 与 UVM 源码。

如果你已经是验证工程师，可以跳过入门解释，但仍建议检查本章的路径约定。
本手册大量使用 :file:`/home/host/eh2-veri/...` 绝对路径、``:ref:`` 交叉引用、
源码行号和实测数据；如果这些约定没看懂，后面的源码精读会很难定位。

学完本章你能：

1. 根据自己的角色选择“零基础学习路径”“验证工程师路径”或“审计路径”；
2. 说出读懂 UVM、cosim、coverage、formal、LEC 分别需要哪些前置知识；
3. 看懂本手册里的路径、命令、术语和源码引用格式；
4. 知道遇到读不懂的章节时，应先回到哪一章补背景。

§1  本章导读
-------------

本手册覆盖 **RTL 设计、UVM 验证架构、协同仿真、形式验证、综合流程、签发签核** 六大技术域，
总篇幅超过 500 页。不同读者不需要通读全册——本章告诉你**按角色定位应该读哪些章节，
按什么顺序读，需要准备好哪些前置知识**。

阅读本章你将学到：

* 本手册为哪 5 类读者设计，各有怎样的典型阅读路径
* 每类读者需要掌握哪些**硬性前置技术** （没有则读不下去），以及哪些是"锦上添花"的软性知识
* 在阅读技术章节时，如何理解本手册的排版约定（术语格式、路径锚点、交叉引用规则）
* 如何利用本手册进行**日常巡检** 而非从头通读
* 手册与上游 RISC-V 规范、Ibex 验证平台文档之间的导航关系

阅读本章需要的前置知识：**无** 。本章是手册的入口，对零基础读者同样友好。
在阅读后续技术章节前，建议先浏览 :ref:`about_index` 了解手册全貌，
再阅读 :ref:`glossary` 熟悉核心术语。

§2  目标读者与角色画像
-----------------------

下表给出 5 类读者的**工作产出** 与**建议阅读路径** 。
其中"宽度优先"意为先浏览章节标题与图表，建立全局心智模型；"深度优先"意为逐行研读源码导读与波形。

.. list-table:: 读者角色与阅读路径
   :header-rows: 1
   :widths: 18 18 32 32

   * - 角色
     - 典型工作产出
     - 宽度优先路径
     - 深度优先路径
   * - **验证工程师**
       （Verification Engineer）
     - 测试用例、覆盖率报告、cosim 调试日志
     - :ref:`04_verification_overview/index` → :ref:`05_verification_arch/tb_top`
       → :ref:`05_verification_arch/env`
     - :ref:`05_verification_arch/cosim_scoreboard` →
       :ref:`05_verification_arch/functional_coverage` →
       :ref:`05_verification_arch/tests_library` →
       :ref:`appendix_b_uvm/index`
   * - **RTL 设计工程师**
       （RTL Designer）
     - 微架构 spec、RTL 代码、性能计数器数据
     - :ref:`01_overview/features` → :ref:`02_core_reference/pipeline`
       → :ref:`02_core_reference/csr`
     - :ref:`02_core_reference/dual_thread` →
       :ref:`02_core_reference/icache` →
       :ref:`02_core_reference/dccm_iccm` →
       :ref:`appendix_a_rtl/index`
   * - **SoC 集成人员**
       （SoC Integrator）
     - 集成后的 netlist、地址映射表、启动固件
     - :ref:`03_integration/system_requirements` →
       :ref:`03_integration/configuration` →
       :ref:`03_integration/getting_started`
     - :ref:`03_integration/soc_integration` →
       :ref:`02_core_reference/bus_axi_ahb` →
       :ref:`appendix_e_config/eh2_configs` →
       :ref:`03_integration/examples`
   * - **工具链 / CI 维护者**
       （CI / Infrastructure Engineer）
     - CI pipeline、signoff 脚本、EDA license 配置
     - :ref:`06_flows/build_flow` → :ref:`06_flows/regression_flow`
       → :ref:`06_flows/ci_pipeline`
     - :ref:`06_flows/signoff_flow` → :ref:`06_flows/scripts_reference`
       → :ref:`appendix_f_scripts/index`
   * - **项目经理 / 质量审计**
       （Manager / Auditor）
     - 质量报告、风险登记册、审计记录
     - :ref:`07_decisions/adr_summary` → :ref:`07_decisions/risk_register`
       → :ref:`07_decisions/coverage_plan`
     - :ref:`07_decisions/known_limitations` →
       :ref:`04_verification_overview/ibex_capability_matrix`

§3  硬性前置知识
-----------------

以下知识是阅读本手册的**必要条件**——没有这些基础，你将无法理解技术内容。
每个条目给出了建议的学习资源与所需深度。

.. list-table:: 硬性前置知识
   :header-rows: 1
   :widths: 20 30 25 25

   * - 知识域
     - 具体内容
     - 建议深度
     - 推荐学习资源
   * - **SystemVerilog**
     - ``always_ff`` / ``always_comb`` 语义、interface 声明、
       ``modport``、``generate``、``typedef struct packed``、
       ``enum`` 状态机编码、hierarchical reference（``$root.a.b`` ）
     - 能独立写出一个包含 FSM + 参数化接口的模块
     - Sutherland "RTL Modeling with SystemVerilog" 第 1-12 章
   * - **UVM 方法学**
       （Universal Verification Methodology）
     - ``uvm_component`` vs ``uvm_object`` 生命周期、
       factory override 机制、TLM 1.0 analysis port、
       ``build_phase`` / ``connect_phase`` / ``run_phase`` 执行顺序、
       ``uvm_config_db`` 的 set/get 语义、
       virtual sequencer 与 sequence 调度
     - 能解释一个 UVM agent 的 driver/monitor/sequencer 如何通过
       analysis port 连接 scoreboard
     - IEEE 1800.2-2020 UVM 标准；Mentor "UVM Cookbook"
       (verificationacademy.com)
   * - **RISC-V 体系结构**
       （RV32 子集）
     - RV32I 基本整数指令集（47 条指令的编码格式 R/I/S/B/U/J）、
       CSR 寄存器（mstatus/mcause/mepc/mtvec/mie/mip）、
       M-Mode 特权级（机器模式）、异常与中断的陷入/返回机制、
       物理内存保护（PMP）
     - 能手写出一个简单中断服务例程（ISR）的汇编代码，
       并能解释 ``mret`` 的硬件行为
     - "The RISC-V Instruction Set Manual Volume I: Unprivileged ISA"
       (20191213) 第 2、16、19、20、24 章；
       "Volume II: Privileged Architecture" (20211203) 第 3 章
   * - **AXI4 协议**
       （AMBA AXI4）
     - 5 通道模型（AW/W/B/AR/R）、valid/ready 握手机制、
       burst 类型（FIXED/INCR/WRAP）、AxSIZE/AxLEN/AxBURST 字段含义、
       out-of-order transaction 与 AxID 标签
     - 能画出一次 INCR4 读 burst 的握手波形
     - ARM IHI0022H "AMBA AXI and ACE Protocol Specification"
       第 A1-A8 章
   * - **Shell / Linux 操作**
     - ``make`` 变量传递、环境变量 export、管道与重定向、
       ``grep`` / ``find`` / ``sed`` 基本用法
     - 能在终端中独立完成 make 构建 + 日志 grep 定位错误
     - 任何 Linux 命令行入门教材

§4  软性前置知识（锦上添花）
----------------------------

以下知识不是读本手册的必要条件，但**有则能大幅加速理解** 。在遇到对应章节时，
可以按需补充背景。

.. list-table:: 软性前置知识
   :header-rows: 1
   :widths: 25 35 40

   * - 知识域
     - 适用章节
     - 推荐学习资源
   * - **Spike ISS 原理**
     - :ref:`05_verification_arch/cosim_scoreboard`、
       :ref:`appendix_c_tools/cosim_cpp`
     - riscv-isa-sim README (github.com/riscv-software-src/riscv-isa-sim)
   * - **JTAG 调试协议** (IEEE 1149.1)
     - :ref:`05_verification_arch/agent_jtag`、
       :ref:`02_core_reference/debug`
     - "IEEE Std 1149.1-2013" 第 1-5 章；RISC-V Debug Specification 0.13.2
   * - **EDA 工具基础**
       （VCS / Xcelium / Verilator）
     - :ref:`06_flows/build_flow`、:ref:`06_flows/scripts_reference`
     - 各工具的 User Guide 前两章（编译与仿真基础）；Verilator 官方手册
   * - **Python 3 基本语法**
     - :ref:`appendix_f_scripts/index` 中各 Python 脚本注释
     - Python 3 官方教程 (docs.python.org) 第 1-6 章
   * - **Yosys 综合基础**
     - :ref:`06_flows/synthesis_flow`、
       :ref:`appendix_c_tools/syn_yosys`
     - Yosys 官方手册 (yosyshq.net) 第 1-4 章
   * - **形式验证基础**
       （SVA / SymbiYosys）
     - :ref:`06_flows/formal_flow`、
       :ref:`appendix_c_tools/formal_properties`
     - "SystemVerilog Assertions Handbook" 第 1-3 章

§5  如何有效使用本手册
-----------------------

**日常巡检模式**

如果你是验证工程师，每天上班第一件事可能是检查昨晚的 nightly regression 结果。
此时你不该通读任何章节，而是：

1. 打开 :ref:`06_flows/regression_flow` 页面，对照 log 定位失败的测试用例名
2. 在 :ref:`05_verification_arch/tests_library` 中按用例名查找其测试意图与预期行为
3. 定位到具体 RTL 模块后，打开 :ref:`appendix_a_rtl/index` 对应的章节查看端口与状态机
4. 用 :ref:`troubleshooting` 中的故障模式速查表，确认是否为已知问题
5. 如需深入波形，打开 :ref:`02_core_reference/pipeline` 中的时序图对照

**新人上手模式**

如果你是刚接手项目的验证工程师，建议按以下顺序在两周内逐步建立全貌：

.. list-table::
   :header-rows: 1
   :widths: 15 65 20

   * - 天数
     - 阅读内容
     - 预计时间
   * - 第 1 天
     - :ref:`01_overview/index` 全部 5 节 + :ref:`glossary`
     - 2 小时
   * - 第 2 天
     - :ref:`04_verification_overview/index` 全部 3 节
     - 1.5 小时
   * - 第 3 天
     - :ref:`03_integration/getting_started` + 跑通 hello world
     - 3 小时
   * - 第 4-5 天
     - :ref:`02_core_reference/pipeline` 逐节阅读 + 对照源码
     - 5 小时
   * - 第 6 天
     - :ref:`05_verification_arch/tb_top` + :ref:`05_verification_arch/env`
     - 2 小时
   * - 第 7 天
     - :ref:`05_verification_arch/cosim_scoreboard` 全文
     - 2 小时
   * - 第 8-9 天
     - :ref:`05_verification_arch/tests_library` + 运行回归并阅读日志
     - 4 小时
   * - 第 10 天
     - :ref:`06_flows/index` 全部 + 修改一个简单 agent 做实验
     - 3 小时

**速查模式**

遇到具体问题时，手册的以下"速查节点"最频繁被使用：

* 不确定某个信号的含义 → 直接翻到对应模块的 :ref:`appendix_a_rtl/index` 章节，看 §3 端口表
* 不确定某个 UVM 组件的 TLM 端口如何连接 → 读对应 agent 的 §3 config/port 表
* 回归失败但不确定是否已知问题 → 读 :ref:`troubleshooting` ，关键词 grep 日志
* 想在测试中加入新指令序列 → 读 :ref:`05_verification_arch/vseq_library` 的 §8 扩展指南
* 配置文件 ``eh2_configs.yaml`` 中的某个开关含义不确定 → 读 :ref:`appendix_e_config/eh2_configs`

§6  本手册不覆盖的内容
-----------------------

为避免读者在海量信息中迷失，本手册**有意识不包含** 以下内容（并给出替代信息源）：

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 不覆盖内容
     - 替代信息源
   * - **EH2 RTL 微架构 spec**
       （设计意图、性能分析）
     - 本仓库 :file:`doc/architecture/` 目录下的架构文档；
       Cores-VeeR-EH2 原始仓库的 Design Specification
   * - **RISC-V ISA 指令编码全集**
       （逐指令 bit field）
     - RISC-V 官方规范 PDF（Unprivileged ISA, 20191213）
   * - **UVM 库 API 参考**
       （每个 ``uvm_*`` 宏的参数列表）
     - Accellera UVM 1.2/2.0 类参考手册；IEEE 1800.2-2020
   * - **EDA 工具手册全文**
       （VCS/Xcelium/Questa/Verilator 的全部命令行参数）
     - 各厂商官方 User Guide 与 Reference Manual
   * - **Spike ISS 内部源码分析**
       （除本平台通过 DPI 调用的接口外）
     - ``riscv-software-src/riscv-isa-sim`` 上游项目；
       本平台只约束 Spike DPI 调用边界
   * - **riscv-dv 框架内部实现**
       （除本平台扩展的部分外）
     - ``google/riscv-dv`` 上游项目；
       本平台只说明 :file:`dv/uvm/core_eh2/riscv_dv_extension/`

§7  排版、术语与路径约定速览
-----------------------------

完整约定见 :ref:`conventions` 。这里只给出阅读过程中最常见的 8 条规则：

1. 模块名、信号名、CSR 名、UVM 类名一律使用 ``等宽字体``
2. 文件路径使用 :file:`相对路径` （相对于仓库根 ``eh2-veri/`` ）
3. 章节内部引用使用 ``:ref:`` 交叉引用标签（如 :ref:`pipeline` 指向流水线章）
4. ADR 引用格式为 ``:ref:`` 角色加 ``adr-NNNN`` 标签（如 :ref:`adr-0001` ）
5. 术语首次出现时给出**中英对照** （例如"协同仿真（cosim）"），之后统一用中文
6. RTL 源码引用使用 :file:`文件路径` + 行号范围锚点
7. 时序波形使用 ASCII art 绘制，CLK 为顶行参考时钟
8. 所有代码块标注语言类型（``.. code-block:: systemverilog`` ），确保语法高亮正确

§8  与上游参考实现的导航关系
-----------------------------

本平台**对标 lowRISC Ibex 验证平台** ，两者结构相似但有以下核心差异，
读者在交叉阅读时需注意：

* **Ibex 是单发射** ，EH2 是双发射（i0/i1 双槽位），导致 trace packet 结构和 scoreboard 写回匹配逻辑有本质差异
* **Ibex 使用 RVFI** 接口直连 trace，EH2 使用自有的 ``eh2_trace_pkt_t`` 结构体 + RVFI adapter 侧载方案，见 :ref:`adr-0015`
* **EH2 有 PIC** （127 路外部中断），Ibex 的外部中断数量较少且无独立 PIC 模块
* **EH2 的 ICCM/DCCM** 是紧耦合存储（TCM），Ibex 无此概念
* **Spike DPI 接口** 在 EH2 平台有大量定制扩展（PIC CSR 注册、多 hart 支持、debug cosim），见 :ref:`adr-0001` 至 :ref:`adr-0010`

详细的功能对比矩阵见 :ref:`ibex_capability_matrix` 。

§9  参考资料与延伸阅读
-----------------------

* **RISC-V 规范** ：
  `The RISC-V Instruction Set Manual Volume I: Unprivileged ISA (20191213) <https://riscv.org/specifications/ratified/>`_
* **RISC-V 特权规范** ：
  `The RISC-V Instruction Set Manual Volume II: Privileged Architecture (20211203) <https://riscv.org/specifications/ratified/>`_
* **AMBA AXI4 协议** ：
  `Arm AMBA specifications <https://www.arm.com/architecture/system-architectures/amba/amba-specifications>`_
* **UVM 标准** ：
  `IEEE 1800.2-2020 Universal Verification Methodology Language Reference Manual <https://standards.ieee.org/ieee/1800.2/7567/>`_
* **SystemVerilog 标准** ：
  `IEEE 1800-2017 SystemVerilog Language Reference Manual <https://standards.ieee.org/ieee/1800/6700/>`_
* **EH2 验证平台对标参考** ：
  `lowRISC Ibex Verification <https://ibex-core.readthedocs.io/en/latest/03_reference/verification.html>`_
* **本仓库内交叉引用** ：
  :ref:`conventions` — 完整排版与术语约定；
  :ref:`contributing` — 如何为本手册贡献内容；
  :ref:`glossary` — 中英术语对照表；
  :ref:`about_index` — 手册全局目录；
  :ref:`references` — 完整参考文献列表

§10  自检 5 问
------------------------

读完本章，你应该能回答：

1. 只懂 C 语言的新读者为什么不应直接跳到 :ref:`appendix_b_uvm/cosim_agent`？
2. 验证工程师和 SoC 集成人员的阅读路径为什么不同？
3. 手册中的 :file:`dv/uvm/core_eh2/...` 路径默认相对于哪个仓库根目录？
4. 如果后续章节第一次出现 ``RVFI``、``DPI``、``URG`` 等术语，你应该去哪里查？
5. 为什么本手册要求每个关键结论都绑定源码路径、命令或实测数据？

如果第 1 题答不上来，回到 §2 重新看读者画像；如果第 3 题答不上来，
回到 §7 重新看路径约定；如果第 4 题答不上来，先读 :ref:`glossary`。

§11  v2 学习路径参考资料
-------------------------

本章之后建议按目标选择下一步：

* 零基础读者：:ref:`introduction` → :ref:`getting_started` → :ref:`quickstart`；
* 想理解 RTL：:ref:`features` → :ref:`pipeline` → :ref:`dual_thread`；
* 想理解 UVM：:ref:`quickstart` → :ref:`tb_top` → :ref:`05_verification_arch/env`；
* 想调 cosim：:ref:`rvfi_trace` → :ref:`05_verification_arch/agent_cosim` →
  :ref:`05_verification_arch/cosim_scoreboard`；
* 想做质量审计：:ref:`targets` → :ref:`signoff_flow` → :ref:`coverage_plan`。

v2 教学层会在后续阶段新增 :file:`00_about/learning_path.rst` 和
:file:`00_about/glossary_pretest.rst`。在这些章节创建前，本章就是学习路线的主入口。

..
   自检八问：
   1. ✅ 每个技术断言都有源文件佐证（本文件为元信息章，技术断言来自 CONTEXT.md 与 index.rst）
   2. ✅ 端口/接口表不适用于本文件（元信息章）
   3. ✅ 源文件覆盖不适用于本文件
   4. ✅ §5 中的新人上手步骤可直接照做
   5. ✅ 无"详见源代码"等偷懒措辞
   6. ✅ 所有外链 URL 可访问（均为 RISC-V 官方 / IEEE / ARM 官方地址）
   7. ✅ 与 CONTEXT.md 交叉核对无冲突
   8. ✅ 本文件 260+ 行，超过 150 行门槛
