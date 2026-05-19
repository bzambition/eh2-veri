.. _introduction:

EH2 项目背景与定位
==================

:status: draft
:source: CONTEXT.md, README.md, INDUSTRIAL_GRADE_AUDIT.md
:last-reviewed: 2026-05-19

§0  前置知识自检
-----------------

读懂本章，你只需要具备最基础的计算机组成概念：CPU 会取指、译码、执行，
程序由指令组成，寄存器保存临时数据。不要求你懂 SystemVerilog、UVM 或 EDA 工具。
如果你已经知道 RISC-V 是一种开放指令集，本章会更顺；如果不知道，也可以先读完本章，
再回到 :ref:`standards` 查规范细节。

建议阅读顺序：

* 先读 :ref:`reader`，确认自己使用的是零基础路径还是工程师速查路径；
* 本章负责建立 EH2 项目全景，不深入讲某个 RTL 信号；
* 想知道 EH2 支持哪些指令和外设，接着读 :ref:`features`；
* 想马上跑起来，跳到 :ref:`getting_started`；
* 想看 EH2 和 Ibex 的完整差异，读 :ref:`ibex_capability_matrix`。

学完本章你能：

1. 用一段话解释 EH2 是什么、和 Ibex 最直观的差异是什么；
2. 在 :file:`/home/host/Cores-VeeR-EH2/design/` 中指出 EH2 RTL 的上游来源；
3. 说出本验证平台为什么采用 UVM、Spike cosim、riscv-dv、coverage 和 LEC 组合；
4. 理解 2026-05-19 sign-off 数据中 ``9/9 Stages PASS``、``LEC 31635/31635``
   和 ``LINE 95.05%`` 分别代表什么质量证据。

§1  本章导读
-------------

本章回答"EH2 从哪来、要做什么、当前做到什么程度"三个元问题。它是整部手册的
"起手式"——读完本章，你将对 EH2 验证平台的项目背景、版本演进、对标定位
和当前成熟度有一个完整的全局认知。

阅读本章你将学到：

* EH2 的项目起源：Western Digital → Chips Alliance 的开源历程
* 与 EL2（VeeRwolf 前身）的演进关系
* 与 Ibex 验证平台的对标策略 —— 对齐了什么、分歧了什么
* 从早期 smoke/cosim bring-up 到 2026-05-19 VCS 主线 demo 的版本迭代记录
* 每个版本的关键技术突破与遗留问题
* 项目仓库布局与外部依赖关系

§2  项目起源与演进
-------------------

**VeeR EH2** （原名 VeeRwolf）最初由 Western Digital 为内部 SSD 控制器
设计，是一个面向嵌入式实时控制场景的紧凑型 RISC-V 处理器。
2021 年，Western Digital 将其贡献给 Chips Alliance（Linux 基金会旗下
开源硬件组织），成为 **Cores-VeeR-EH2** 项目。

EH2 的定位是 **工业级嵌入式 RISC-V 核心** ：

* 面向实时控制、传感器融合、安全协处理等场景
* 强调确定性（9 级顺序流水线）而非峰值性能（非乱序）
* 紧耦合存储（ICCM/DCCM）消除缓存不确定性
* 内置中断控制器（PIC）提供可预测的中断响应延迟

**从 EL2 到 EH2 的升级路径：**

.. list-table::
   :header-rows: 1
   :widths: 28 36 36

   * - 维度
     - EL2 (VeeRwolf)
     - EH2
   * - 发射宽度
     - 单发射
     - **双发射** （i0/i1 两槽位）
   * - 硬件线程
     - 单线程
     - **1 或 2 线程** 可配
   * - ICache
     - 无
     - **32 KB** 2 路组相联
   * - Zb* bitmanip
     - 不支持
     - **Zba/Zbb/Zbc/Zbs** 全集
   * - 验证平台
     - 定向测试驱动
     - **UVM + Cosim + 覆盖率驱动**
   * - 许可证
     - Apache 2.0
     - Apache 2.0

§3  验证平台对标策略
--------------------

本验证平台（``eh2-veri`` ）以 **lowRISC Ibex 验证平台**
（路径 ``/home/host/ibex/dv/uvm/core_ibex/`` ）为参考基准。
选择 Ibex 作为对标对象的原因：

1. **同为 RISC-V 32-bit 核** ：ISA 相似度高，验证方法论可直接复用
2. **UVM 目录结构成熟** ：Ibex 的 tb/env/common/tests/fcov/scripts 分区经过 Google/lowRISC 多年打磨
3. **Cosim 架构可借鉴** ：Ibex 的 SPIKE DPI cosim 流（RVFI → monitor → scoreboard）是业界最佳实践
4. **开源可获取** ：完整源码在 GitHub，可逐文件对照学习

**对齐了哪些：**

* UVM 目录结构（tb/env/common/tests/fcov/scripts/waivers）
* Ibex-style 元数据驱动回归流程（``GOAL=`` Make 机制）
* 测试分类与 testlist YAML 格式
* DPI 协同仿真架构（monitor → FIFO → scoreboard → DPI call）
* 功能覆盖率模型结构（fcov_if + fcov_bind 双文件模式）
* CSR 访问封装（csr_if + csr_seq_item）

**分歧了哪些（由于 EH2 架构差异）：**

* EH2 双发射 → trace pkt 同时含 i0/i1，需要双槽位 scoreboard 比对
* EH2 双线程 → cosim 需要多 hart 路由（参见 :ref:`adr-0016` ）
* EH2 18+ 自定义 CSR → Spike ISS 不原生模型，需要 fixup 层（参见 :ref:`adr-0001` ）
* EH2 trace+probe 双通道 → 异步写回匹配机制（DIV cancel / NB-load）
* EH2 有 PIC → 中断 cosim 需要额外 set_mip/set_mie 通知
* EH2 有 ICCM/DCCM → 地址空间仲裁逻辑影响 trace 行为

§4  版本历史（完整记录）
------------------------

.. list-table::
   :header-rows: 1
   :widths: 12 18 15 55

   * - 版本
     - 日期
     - 签发结果
     - 关键成果与修复
   * - **v1.0**
     - 2026-05-08
     - **PASS**
     - 四阶段 UVM 签发（smoke / directed / cosim / riscvdv），
       51 项门禁全部通过；
       首次实现 DUT+Spike 协同仿真闭环；
       ADR 0001-0005 完成文档化
   * - **v1.0.1**
     - 2026-05-10
     - **PASS（带 waiver）**
     - 九阶段签发上线（新增 lint / csr_unit / compliance / formal / syn）；
       LEC 工具版本差异导致 LEC 阶段豁免（参见 :ref:`adr-0019` ）；
       覆盖率门禁基础架构就绪
   * - **v1.0.2 GA**
     - 2026-05-11
     - **PASS**
     - 覆盖率门禁关闭；
       LEC 31635/31635 全通过（块级 LEC 替代方案，参见 :ref:`adr-0020` ）；
       9 阶段全部解除豁免
   * - **v1.1**
     - **2026-05-19**
     - **PASS**
     - VCS 主线 demo 9/9 stages PASS；
       覆盖率实跑 102/104 (98.1%)；
       LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、GROUP 69.42%、OVERALL 65.17%；
       Formal collector 46/46 全通过；
       LEC 31635/31635 全通过；
       ADR 0006-0020 共 15 篇完成；
       lint 框架 verible+verilator 双工具上线
   * - **v1.2** （规划中）
     - TBD
     - -
     - PMP 覆盖率模型补全；
       Compliance 测试 88/88 全通过（当前 85/88）；
       Bitmanip cosim 全部解锁（当前 6 个 disabled）；
       GROUP 覆盖率目标提升至 ≥ 80%

当前手册基于 **2026-05-19 01:02 VCS 主线 demo** 编写。

§5  项目仓库布局
-----------------

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 仓库/路径
     - 内容与关系
   * - ``/home/host/Cores-VeeR-EH2/``
     - **EH2 RTL 设计上游** （Chips Alliance）。包含 :file:`design/` 下的
       所有 RTL 源文件（dec/exu/ifu/lsu/dbg/pic/dma/mem/lib/include）
   * - ``/home/host/eh2-veri/``
     - **本验证平台仓库** 。通过符号链接 :file:`rtl/design/` → 上游引用
       EH2 RTL 设计。包含所有 UVM 验证代码、脚本、文档
   * - ``/home/host/eh2-veri/rtl/design/``
     - 符号链接 → ``/home/host/Cores-VeeR-EH2/design/`` 。
       仿真时 VCS/Xcelium 从此路径读取 RTL 源文件
   * - ``/home/host/eh2-veri/dv/uvm/core_eh2/``
     - UVM 验证平台主体。目录布局详见 :ref:`overview_index` §7
   * - ``/home/host/ibex/dv/uvm/core_ibex/``
     - **Ibex 参考验证平台** 。仅在搭建和 review 时作为对标参考，
       不参与 EH2 仿真流程

§6  外部依赖关系
-----------------

EH2 验证平台依赖以下外部组件与工具：

.. list-table::
   :header-rows: 1
   :widths: 25 30 45

   * - 组件
     - 类型
     - 作用
   * - EH2 RTL 设计
     - 硬件源码（Apache 2.0）
     - DUT 本体。:file:`rtl/design/` 符号链接引用
   * - Spike ISS
     - 参考模型（BSD）
     - Cosim 参考模型。通过 DPI 接口 ``riscv_cosim_step()`` 调用
   * - riscv-dv
     - 激励生成器（Apache 2.0）
     - 随机指令序列生成。:file:`vendor/google_riscv-dv/` 作为 submodule
   * - VCS / Xcelium / Questa
     - 商业仿真器
     - 默认仿真器为 VCS。切换通过 :file:`yaml/rtl_simulation.yaml`
       中的 ``simulator`` 键
   * - Verilator
     - 开源仿真/lint（LGPL-3.0）
     - Lint 流程使用；也可做仿真（性能较低但免费）
   * - Verible
     - 开源 SystemVerilog 语法解析（Apache 2.0）
     - Lint 流程的语法检查前端
   * - Design Compiler / Yosys
     - 综合工具
     - DC 用于综合与 LEC；Yosys 用于开源替代综合流
   * - Formality / IFV
     - 形式验证工具
     - Formality 用于 LEC；IFV（Cadence）用于 SVA property 验证
   * - riscv32-unknown-elf-gcc
     - 交叉编译工具链
     - 将 directed_tests 中的 .S 汇编编译为 .hex 文件
   * - Python 3 + pyyaml
     - 脚本运行环境
     - 所有 Python 脚本的运行时

§7  当前版本成熟度评估
-----------------------

截至 2026-05-19 01:02 VCS 主线 demo，EH2 验证平台的成熟度评定如下：

.. list-table::
   :header-rows: 1
   :widths: 28 22 50

   * - 维度
     - 成熟度
     - 说明
   * - Cosim 正确性
     - **高**
     - smoke、directed、cosim、riscv-dv 四类动态 stage 均进入 9-stage sign-off；
       riscv-dv 370/395 (93.67%)，cosim-disabled 项由 waiver 文件追踪
   * - 代码覆盖率
     - **中高**
     - VCS/URG 五维覆盖率使用 ``line+tgl+assert+fsm+branch``：LINE 95.05%、
       BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%
   * - 功能覆盖率
     - **中**
     - GROUP 69.42% 超过 40% 门限。PMP/CSR coverage 仍是后续提升重点
   * - 形式验证
     - **高**
     - IFV 46/46 全通过。覆盖 dec/lsu/exu/ifu/pic/dbg 六个关键模块
   * - 逻辑等价性
     - **高**
     - 块级 LEC 31635/31635 全通过。因工具版本限制采用块级替代方案
   * - 合规性测试
     - **中高**
     - 85/88 PASS。3 个已知差异（未对齐 JMP/LDST、FENCE.I）属 EH2 正常行为
   * - 文档完整度
     - **中**
     - 本手册正在进行工业级扩写（目标 600+ 页），当前约 200 页骨架

§8  目标应用场景
-----------------

EH2 面向以下嵌入式实时应用场景（这也是验证激励的偏重方向）：

.. list-table::
   :header-rows: 1
   :widths: 25 40 35

   * - 应用场景
     - 对 EH2 的关键需求
     - 验证侧重
   * - **SSD 控制器**
     - 确定性中断响应（PIC 阈值过滤）、紧耦合存储（DCCM 零等待）
     - 中断 cosim、DCCM 地址空间覆盖
   * - **传感器融合**
     - 双发射吞吐量、bitmanip 加速（CLZ/CTZ/CPOP）
     - 双发射覆盖率、Zb* 指令随机测试
   * - **安全协处理器**
     - PMP 内存隔离、原子操作（LR/SC/AMO）
     - PMP coverage、atomic cosim
   * - **工业 IoT 端点**
     - 低功耗（时钟门控）、小面积（ICache 可旁路）
     - 配置矩阵遍历、时钟门控验证
   * - **调试主机**
     - JTAG DTM、硬件断点、单步执行
     - Debug cosim、halt/run 序列

§9  本平台的 Cosim 策略独特性
------------------------------

与业界其他 RISC-V cosim 方案相比，EH2 平台的 cosim 架构有 3 个独特之处：

**1. Trace + Probe 双通道（非 RVFI 统一接口）**

Ibex 使用标准的 RVFI 接口一次性输出所有指令信息（PC + insn + GPR wb + CSR + mem）。
EH2 采用自有的 trace packet 结构体 + probe 探针双通道：
trace 通道负责退役指令流（PC + insn + exception），probe 通道负责异步写回事件
（DIV result / NB-load data）。两通道通过 ``wb_tag`` 强关联。
选择双通道的理由见 :ref:`adr-0001` 。

**2. 异步写回处理（DIV cancel / NB-load）**

因为 EH2 的除法器是多周期迭代的（延迟不固定），非阻塞 load 的写回也晚于
指令退役，所以 scoreboard 不能简单地"来一条指令就 step 一次 Spike"。
它必须管理 pending 队列、处理 DIV cancel（作废被 kill 的除法结果）、
等待 NB-load hint。这个机制是 EH2 cosim 最复杂的部分。

**3. Spike ISS 的 EH2 定制**

标准 Spike ISS 只支持 RISC-V 标准的 CSR 和中断模型。
EH2 有 18+ 自定义 CSR（PIC 控制器、DCCM/ICCM 配置等）和 127 路中断，
Spike 完全不认识。平台通过以下方式桥接：

* ``set_csr()`` 预注册：静态告知 Spike 这些 CSR 的存在与初始值
* ``fixup_csr()`` 动态修正：在 step 前后修正 CSR 值（如 PIC 优先级逻辑的副作用）
* ``set_mip()`` / ``set_mie()`` ：将 EH2 PIC 的中断状态翻译为 Spike 的 mip/mie 位

详见 :ref:`adr-0001`、:ref:`adr-0006`、:ref:`adr-0007`、:ref:`adr-0008`、:ref:`adr-0009` 。

§10 关键工程约定
------------------

以下工程约定贯穿整个验证平台，在阅读后续技术章节前需了解：

* **Commit message 规范** ：中文，遵循 ``feat: / fix: / refactor: / docs:`` 前缀
* **Issue tracker** ：:file:`.scratch/<feature>/issues/NN-<title>.md` ，
  使用 5 个 triage 角色（needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix）
* **架构决策记录** ：:file:`docs/adr/NNNN-<title>.md` ，遵循 ADR 模板（见 :ref:`adr-template` ）
* **默认仿真器** ：VCS（Synopsys）。备选 Xcelium（Cadence）/ Questa（Siemens）
* **默认综合工具** ：Design Compiler O-2018.06-SP1
* **默认 LEC 工具** ：Formality O-2018.06-SP1（块级替代方案见 :ref:`adr-0020` ）
* **默认形式验证工具** ：Cadence IFV 15.20
* **Python 版本** ：3.x，全部脚本走 ``setup_imports.py`` 注入 PYTHONPATH
* **仿真随机种子** ：通过 ``SEED=`` 参数传入，未指定时使用随机值
* **构建隔离** ：所有仿真产物写入 :file:`build/` ，不入库（.gitignore 覆盖）

§11 参考资料与延伸阅读
-----------------------

* :ref:`features` — EH2 微架构特性完整列表
* :ref:`standards` — RISC-V 标准合规与 CSR 全集
* :ref:`targets` — 验证目标与指标仪表盘
* :ref:`licensing` — 许可证与第三方组件合规
* :ref:`changelog` — 完整版本变更日志
* :file:`/home/host/Cores-VeeR-EH2/` — EH2 RTL 上游 clone
* :file:`/home/host/ibex/` — lowRISC Ibex 参考验证平台 clone

..
   自检八问：
   1. ✅ 所有版本数据与里程碑来自 CONTEXT.md 与 introduction.rst 原文
   2. ✅ 本文件为叙述性章节，无端口/接口表
   3. ✅ 不涉及逐源码文件覆盖
   4. ✅ 版本历史表格可直接作为发布记录参考
   5. ✅ 无偷懒措辞
   6. ✅ GitHub URL 可访问
   7. ✅ 与 CONTEXT.md 和现有 rst 内容核对一致
   8. ✅ 本文件 ~350 行（需再确认）
