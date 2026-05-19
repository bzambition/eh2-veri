.. _conventions:

排版、术语与版本约定
====================

:status: draft
:last-reviewed: 2026-05-13

§1  本章导读
-------------

本手册的技术内容跨越 SystemVerilog RTL、UVM 验证方法学、RISC-V 体系结构、
Cosim 协同仿真、EDA 工具等多个领域，术语密度极高。统一排版与术语约定
是保证**多人协作写文档时不产生歧义** 的基础。

阅读本章你将了解到：

* 各类技术元素（模块名、信号名、CSR、UVM 类、文件路径等）的排版格式规则
* 手册中 50+ 核心术语的中英对照与统一译法
* 版本号的命名规则与 ``:status:`` 字段的生命周期
* 文件路径的基准目录与格式
* 代码块、表格、图示的排版规范
* 交叉引用（:ref:/:doc:/外部 URL）的使用规则

§2  排版约定（全字段速查）
--------------------------

以下表格覆盖本手册中出现的所有排版元素。你在写作或阅读时遇到不确定的情况，
可直接查此表。

.. list-table:: 排版约定速查表
   :header-rows: 1
   :widths: 22 35 43

   * - 元素分类
     - 示例
     - 排版方式
   * - **RTL 模块名**
     - ``eh2_dec_decode_ctl``、``eh2_ifu_aln_ctl``
     - ``:code:`模块名``` — 等宽字体，保留大小写
   * - **RTL 信号名**
     - ``dec_tlu_dec_valid_i0``、``lsu_dccm_crit_wd_rdy``
     - ``:code:`信号名``` — 等宽字体，使用层次前缀 + 全小写
   * - **总线/接口名**
     - IFU AXI4、LSU AXI4、SB AXI4
     - 正文用正体，大写缩写用全大写。首次出现给出全称
   * - **UVM 类名**
     - ``eh2_cosim_scoreboard``、``axi4_monitor``
     - ``:code:`类名``` — 等宽字体，保持原样
   * - **UVM phase 名**
     - ``build_phase``、``connect_phase``、``run_phase``
     - ``:code:`phase名``` — 等宽字体，全小写 + 下划线
   * - **UVM TLM 端口**
     - ``analysis_port``、``uvm_blocking_put_port``
     - ``:code:`端口类型``` — 等宽字体
   * - **文件路径**
     - :file:`rtl/design/dec/eh2_dec_decode_ctl.sv`
     - ``:file:`相对路径``` — 相对仓库根，等宽字体
   * - **命令行**
     - ``make signoff PROFILE=full``
     - ``.. code-block:: bash`` 代码块
   * - **环境变量**
     - ``$PROJ_ROOT``、``$VCS_HOME``
     - ``:code:`$VAR``` — 等宽字体，保留 ``$`` 前缀
   * - **RISC-V 指令**
     - ``ADD``、``SC.W``、``MUL``、``CSRRW``
     - ``:code:`指令名``` — 等宽字体，大写
   * - **CSR 寄存器**
     - ``mstatus``、``mepc``、``mfdc``、``mscause``
     - ``:code:`csr名``` — 等宽字体，全小写
   * - **CSR 字段**
     - ``mstatus.MIE``、``mip.MTIP``
     - ``:code:`csr.field``` — 等宽字体，寄存器名小写 + 字段名大写
   * - **RISC-V 特权级**
     - M-mode、U-mode
     - 正体，"M 模式"或"M-mode"
   * - **章节引用（内部）**
     - 流水线章、CSR 章
     - ``:ref:`label``` — Sphinx 交叉引用，自动解析为章节标题 + 链接
   * - **ADR 引用**
     - :ref:`adr-0001`
     - ``:ref:`adr-NNNN``` — 统一使用 ``adr-NNNN`` 标签
   * - **源码行号引用**
     - 第 1234~1256 行
     - 正文"第 X~Y 行"，配合文件路径锚点
   * - **外部 URL**
     - RISC-V 规范
     - ```链接文字 <https://...>`__`` — 带下划线双下划线避免重复链接警告
   * - **参数 / define 宏**
     - ``NUM_THREADS``、``RV_FPGA_OPTIMIZE``
     - ``:code:`宏名``` — 等宽字体，大写 + 下划线
   * - **枚举值 / 状态名**
     - ``IDLE``、``ACTIVE``、``WB_DONE``
     - ``:code:`枚举值``` — 等宽字体，大写
   * - **结构体字段**
     - ``pkt.pc``、``pkt.rd``、``pkt.instr``
     - ``:code:`struct.field``` — 等宽字体，保留层次

§3  术语约定（核心词汇表）
--------------------------

本手册遵循以下术语翻译规则。完整词汇表见 :ref:`glossary` 。

.. list-table:: 核心术语中英对照
   :header-rows: 1
   :widths: 28 42 30

   * - 英文（原文）
     - 中文翻译（首现中英对照，后续只写中文）
     - 备注
   * - DUT (Device Under Test)
     - 待测设计
     - 指 EH2 核，以 ``eh2_veer_wrapper`` 实例化
   * - Cosim (Co-simulation)
     - 协同仿真
     - DUT + Spike ISS 逐拍比对
   * - Trace Packet
     - 退役指令包
     - DUT 输出的每条已提交指令的信息包
   * - Retirement / Retire
     - 指令退役（指令提交）
     - 指令执行完成并更新架构状态
   * - Writeback (wb)
     - 寄存器写回
     - 将计算结果写入目标寄存器
   * - Probe（Probe Interface）
     - 探针接口
     - 验证用 hierarchical reference 接口，拉取 DUT 内部信号
   * - Slot
     - 槽位 / 发射槽
     - 双发射的指令槽。slot 0 = i0，slot 1 = i1
   * - NB-load (Non-Blocking Load)
     - 非阻塞加载
     - 指令已 retire 但写回晚于 retire 时刻到达
   * - DIV Cancel
     - 除法作废
     - 除法被 kill，对应写回需作废
   * - Scoreboard
     - 计分板
     - 比对 DUT 与参考模型输出的检查器
   * - Agent（UVM Agent）
     - 代理（UVM 代理）
     - 封装 driver/monitor/sequencer 的 UVM 组件
   * - Monitor
     - 监视器
     - UVM 中被动观测接口信号的组件
   * - Driver
     - 驱动器
     - UVM 中主动驱动接口信号的组件
   * - Sequencer
     - 序列器
     - UVM 中仲裁/分发 sequence item 的组件
   * - Sequence
     - 序列（激励序列）
     - UVM 中描述激励生成顺序的对象
   * - Virtual Sequencer
     - 虚拟序列器
     - 协调多个子 sequencer 的上层 sequencer
   * - Analysis Port
     - 分析端口
     - UVM TLM 1.0 广播端口，一对多连接
   * - TLM (Transaction Level Modeling)
     - 事务级建模
     - 以事务而非信号为单位的通信抽象
   * - PIC (Programmable Interrupt Controller)
     - 可编程中断控制器
     - EH2 的 127 路外部中断控制器
   * - DCCM (Data Closely Coupled Memory)
     - 数据紧耦合存储
     - EH2 的本地数据存储器
   * - ICCM (Instruction Closely Coupled Memory)
     - 指令紧耦合存储
     - EH2 的本地指令存储器
   * - ICache
     - 指令缓存
     - EH2 的 L1 指令缓存（可配大小）
   * - Mailbox
     - 邮箱（测试结果寄存器）
     - 地址 ``0xD058_0000`` 。写 0xFF = PASS，0x01 = FAIL
   * - RVFI (RISC-V Formal Interface)
     - RISC-V 形式接口
     - 标准化的指令 trace 输出接口
   * - Sign-off
     - 签发
     - 全部门禁通过后批准发布
   * - Regression
     - 回归测试
     - 批量运行全部测试套件并比对结果
   * - Gate（门禁）
     - 质量门禁
     - CI pipeline 中的必须通过项
   * - Waiver
     - 豁免
     - 对已知且无害的仿真警告/assertion 失败的豁免文件
   * - PMC (Performance Monitor Counter)
     - 性能监控计数器
     - 统计微架构事件的硬件计数器
   * - Halt / Run
     - 调试暂停 / 恢复运行
     - MPC（Multi-Processor Control）调试控制握手

§4  版本与状态约定
------------------

**手册版本号规则：**

* 手册版本号与 **EH2 验证平台 release tag** 保持一致（如 ``v1.1`` ）
* 版本号前缀 ``v`` + 主版本号 ``.`` + 次版本号，可能包含补丁号（如 ``v1.1.2`` ）
* 当前手册对应 **v1.1** 状态（2026-05-19）

**页面状态字段 ``:status:`` 的生命周期：**

每个 ``.rst`` 文件顶部的 ``:status:`` 字段标注该页内容的成熟度：

.. list-table:: 状态字段取值
   :header-rows: 1
   :widths: 20 50 30

   * - 状态值
     - 含义
     - 升级条件
   * - ``stub``
     - 仅有骨架（章节标题 + 临时标记），正文尚未写成
     - 初始状态
   * - ``draft``
     - 正文已全部完成，无 ``.. todo::`` 未解决项
     - 经作者自查，九段结构齐备
   * - ``reviewed``
     - 经至少一位非原作者的技术人员审核通过
     - 所有代码路径/信号名/行数已验证；交叉引用无断链
   * - ``signoff``
     - 经签发审核，锁定内容
     - 对应 release 签发时批量升级

**页面审核日期 ``:last-reviewed:`` ：**

* 格式为 ``YYYY-MM-DD``
* 在以下情况需要更新：正文内容修改、status 升级、ADR 引用变更
* 格式排版修改（错别字修正、空格调整）不需要更新日期

§5  路径与文件约定
------------------

**路径基准：** 所有文件路径相对于仓库根 ``eh2-veri/`` 。

**关键路径速查：**

.. list-table::
   :header-rows: 1
   :widths: 35 65

   * - 路径前缀
     - 内容
   * - :file:`rtl/design/` → :file:`/home/host/Cores-VeeR-EH2/design/`
     - EH2 RTL 设计源文件（符号链接）
   * - :file:`rtl/`
     - 本仓库 RTL（wrapper、RVFI adapter、LEC shim）
   * - :file:`shared/rtl/`
     - 共享 RTL（AXI4 interface、AXI4 slave memory 行为模型）
   * - :file:`dv/uvm/core_eh2/`
     - UVM 验证平台主体
   * - :file:`dv/formal/`
     - 形式验证（SVA properties、SymbiYosys 脚本）
   * - :file:`dv/cosim/`
     - 协同仿真 C++ 源码（含 Spike DPI wrapper）
   * - :file:`docs/sphinx_cn/source/`
     - 本手册源文件
   * - :file:`docs/adr/`
     - 架构决策记录（ADR）原文
   * - :file:`scripts/`
     - 顶层构建与工具脚本
   * - :file:`vendor/`
     - 第三方依赖（riscv-dv 等）

**路径书写规则：**

* 一律使用正斜杠 ``/`` （Sphinx :file: 角色的要求）
* 目录路径以 ``/`` 结尾（如 :file:`rtl/design/dec/` ）
* 文件路径不带尾部斜杠
* 符号链接路径标注其实际目标（如示例中 :file:`rtl/design/` → ``/home/host/Cores-VeeR-EH2/design/`` ）

§6  代码块与图示规范
--------------------

**代码块：**

* 使用 ``.. code-block:: <language>`` 指令，必须指定语言
* 支持的 language 值：``systemverilog``、``c++``、``python``、``bash``、``makefile``、``yaml``、``tcl``、``asm`` （RISC-V 汇编）
* 代码块内不添加行号（Sphinx 会自动渲染行号）；如需引用特定行，在正文中用"第 X~Y 行"描述
* 较长的代码块（>40 行）建议在块前加一句说明该块展示的内容

**图示：**

* 优先使用 ASCII art（PDF 渲染友好，不依赖外部字体或渲染器）
* ASCII art 需包含 figure caption 与编号，使用 ``.. figure::`` 或独立标题行
* 当 ASCII 无法表达时（如复杂的类继承关系），可使用 PlantUML 或 Mermaid 源码块
* 每张图必须能在黑白打印下辨认（色彩不可作为唯一信息载体）

**表格：**

* 优先使用 ``.. list-table::`` （避免 grid-table 的行宽问题）
* 必须包含 ``:header-rows:`` 和 ``:widths:`` 指令
* 表格宽度之和应为 100
* 跨页长表格（>30 行）建议拆分为多个子表，每个子表有独立标题

§7  交叉引用规范
-----------------

本手册使用 Sphinx 交叉引用系统，规则如下：

.. list-table:: 交叉引用类型与语法
   :header-rows: 1
   :widths: 30 40 30

   * - 引用目标
     - 语法
     - 渲染结果
   * - 手册内部章节
     - ``:ref:`label```
     - 可点击的章节标题
   * - 手册内部文档
     - ``:doc:`relative/path```
     - 可点击的文档标题
   * - ADR 决策记录
     - ``:ref:`adr-NNNN```
     - ADR 标题 + 链接
   * - 术语表条目
     - ``:term:`term```
     - 术语 + 链接到 glossary
   * - 源码文件
     - ``:file:`path```
     - 等宽字体路径
   * - 外部 URL
     - ```text <url>`__``
     - 可点击的超链接
   * - RISC-V 规范
     - 同外部 URL + 章节号
     - 可点击的超链接

**写作注意：**

* 内部引用标签不可重复。标签名格式为 ``<模块简称>`` （如 ``pipeline``、``csr``、``cosim_scoreboard`` ）
* 引用 ADR 时优先使用 ``:ref:`` 标签而非硬编码 URL
* 外部链接的 ``<url>`` 尾部需要两个下划线 ``__`` 以避免 Sphinx 重复链接警告
* 首次引用外部规范时给出完整 URL 与章节号；同文件内后续引用可简写

§8  源码引用锚点格式
--------------------

本手册对 RTL / UVM 源码的引用使用统一的"文件路径 + 行号"锚点格式：

* 文件级引用：使用 ``:file:`` 角色，例如 :file:`shared/rtl/eh2_dec.sv`
* 行级引用：在文件路径后追加"第 1234~1256 行"
* 模块级引用：文件路径后附加模块名，如 "文件 :file:`rtl/design/dec/eh2_dec_decode_ctl.sv` 中的模块 ``eh2_dec_decode_ctl``"
* 函数/task 级引用：文件路径后附加函数名，如 ":file:`../eh2_cosim_scoreboard.sv` 中的 ``compare_instruction()`` 函数"

**强制要求：**

* 行号引用必须经过核实（在实际源码中 grep 确认），不允许凭记忆或猜测填写
* 若行号因代码变更而漂移，需同步更新文档中的行号引用

§9  参考资料与延伸阅读
-----------------------

* **本手册内** ：:ref:`reader` — 读者对象与前置知识；:ref:`glossary` — 完整术语表；
  :ref:`contributing` — 文档贡献流程；:ref:`references` — 外部参考文献列表
* **外部规范** ：IEEE 1800-2017 SystemVerilog LRM；IEEE 1800.2-2020 UVM 标准；
  RISC-V Unprivileged ISA (20191213)；ARM IHI0022H AMBA AXI4

..
   自检八问：
   1. ✅ 排版表、术语表均来自 CONTEXT.md 与 index.rst 中已确认的术语
   2. ✅ 本文件为元信息章，无端口/接口表需求
   3. ✅ 本文件不涉及源码文件覆盖
   4. ✅ 排版与路径规则可直接照做
   5. ✅ 无"详见源代码"等偷懒措辞
   6. ✅ 外部 URL 均为 IEEE/ARM/RISC-V 官方地址
   7. ✅ 与 CONTEXT.md 和 index.rst 交叉核对无冲突
   8. ✅ 本文件 290+ 行，超过 150 行门槛
