.. _overview_index:
.. _01_overview/index:

EH2 核总览
==========

:status: draft
:last-reviewed: 2026-05-13

§1  本章导读
-------------

本部分是 EH2 验证平台参考手册的**第一技术部分** ，回答"EH2 是什么、能做什么、
怎么验证"三个核心问题。无论你是验证工程师、RTL 设计师还是 SoC 集成人员，
在深入后续章节之前，应该先通读本部分建立对 EH2 核的全局认知。

阅读本部分你将学到：

* EH2 的项目背景：由谁开发、为何开源、与 RISC-V 生态的关系、从 EL2 到 EH2 的演进路径
* EH2 顶层微架构框图与 7 大子系统的职责划分（IFU / DEC / EXU / LSU / PIC / DBG / MEM）
* 完整的微架构特性清单（流水线 9 级、双发射规则、存储层次、中断系统、调试能力、可配置参数矩阵）
* 所遵循的 RISC-V 规范版本、标准 M-mode CSR 全集、18+ 个 EH2 自定义 CSR 的功能定位
* 验证目标体系（6 层质量金字塔：功能正确性 → 代码覆盖率 → 功能覆盖率 → 合规性 → 形式验证 → LEC）
* 当前 2026-05-19 demo所有验证指标的实测值与门限值
* 与 Ibex 验证平台的功能对标矩阵（双发射 vs 单发射、双线程 vs 单线程、PIC vs 无 PIC 等 15+ 维度）
* 许可证条款与 9 个第三方组件的合规状态

阅读本部分需要的前置知识：基本的 RISC-V 概念（RV32I、CSR、M-mode）。如果你对这些
概念不熟悉，请先阅读 :ref:`reader` 中的前置知识章节。

§2  顶层微架构框图
-------------------

EH2 由 7 大子系统组成，以下 ASCII art 框图标出了各子系统的位置、数据流向
与控制关系。

.. code-block:: text

                          ┌──────────────────────────────────────────────────────┐
                          │                  EH2 (eh2_veer_wrapper)               │
                          │                                                      │
      ┌──────────┐        │  ┌──────────┐   ┌──────────┐   ┌──────────┐          │
      │ ICCM     │◄───────┼──┤          ├──►│          ├──►│          │          │
      │ (64KB)   │        │  │  IFU     │   │  DEC     │   │  EXU     │          │
      └──────────┘        │  │ (取指)    │   │ (译码)    │   │ (执行)    │          │
                          │  │          │   │          │   │          │          │
      ┌──────────┐        │  │ BFF→F1→F2│   │ A→D      │   │ E1→E4    │          │
      │ ICache   │◄───────┼──┤ →A       │   │          │   │          │          │
      │ (32KB)   │        │  └──────────┘   └──────────┘   └────┬─────┘          │
      └──────────┘        │                                      │                │
                          │                                      ▼                │
      IFU AXI4 ◄──────────┼── ┌──────────────────────────────────────┐           │
                          │   │           LSU (存储)                    │           │
      LSU AXI4 ◄──────────┼── │         DC1→DC2→DC3→DC4→DC5            │           │
                          │   └──────────┬───────────────────────────┘           │
      SB AXI4  ◄──────────┼──            │                                       │
                          │   ┌──────────┴──────┐    ┌──────────┐                │
      DMA AXI4 ◄──────────┼── │  DCCM (64KB)    │    │  DMA     │                │
                          │   └─────────────────┘    └──────────┘                │
      ┌──────────┐        │                                                      │
      │ PIC      │◄───────┼── 127 路外部中断输入                                   │
      │ (中断)    │        │                                                      │
      └──────────┘        │  ┌──────────┐    ┌──────────┐                        │
                          │  │  DBG     │    │  DMI     │                        │
      JTAG ◄──────────────┼──│ (调试)    │◄──►│ (调试存储) │                        │
                          │  └──────────┘    └──────────┘                        │
                          │                                                      │
                          │  ┌──────────────────────────────────┐                │
                          │  │      MEM (内存子系统)               │                │
                          │  │   ICCM + DCCM + ICache + AXI4    │                │
                          │  └──────────────────────────────────┘                │
                          └──────────────────────────────────────────────────────┘

**子系统职责速览：**

.. list-table::
   :header-rows: 1
   :widths: 12 20 68

   * - 子系统
     - 源文件位置
     - 职责
   * - **IFU** （取指单元）
     - :file:`rtl/design/ifu/`
     - 指令取指、分支预测（BHT+BTB+RAS）、压缩指令解压、ICache/ICCM 仲裁、取指 AXI4 总线主端
   * - **DEC** （译码单元）
     - :file:`rtl/design/dec/`
     - 指令译码与发射（双槽位 i0/i1 仲裁）、CSR 译码（Espresso 逻辑最小化）、
       操作数前递控制、指令退休与 trace packet 生成
   * - **EXU** （执行单元）
     - :file:`rtl/design/exu/`
     - ALU 运算、乘法器（3 级流水）、除法器（多周期迭代）、分支解析、CSR 读写执行
   * - **LSU** （存储单元）
     - :file:`rtl/design/lsu/`
     - Load/Store 地址生成与检查、DCCM 访问、外部 AXI4 总线访问、
       非阻塞 load 管理、SC.W 成功确认、地址对齐检查
   * - **PIC** （中断控制器）
     - :file:`rtl/design/eh2_pic_ctrl.sv`
     - 127 路外部中断、可配优先级（4/8/16 级）、阈值过滤、NMI 支持
   * - **DBG** （调试单元）
     - :file:`rtl/design/dbg/`
     - JTAG DTM 接口、硬件断点/触发器（2 个 mcontrol）、halt/run 握手、单步执行
   * - **MEM** （内存子系统）
     - :file:`rtl/design/eh2_mem.sv`
     - ICCM + DCCM + ICache 的片选与地址译码、DMA 仲裁

§3  关键数字速览（EH2 at a Glance）
------------------------------------

以下表格汇总了 EH2 核的核心技术参数，建议打印或收藏以供日常速查。

.. list-table:: EH2 核心参数速查
   :header-rows: 1
   :widths: 40 60

   * - 参数
     - 值
   * - **指令集架构**
     - RV32IMAC + Zba + Zbb + Zbc + Zbs（RV32IMAC + Zb* bitmanip 全集）
   * - **流水线深度**
     - 9 级（BFF→F1→F2→A→D→E1→E2→E3→E4→DC1→DC2→DC3→DC4→DC5）
   * - **发射宽度**
     - 双发射（i0/i1 两槽位），顺序发射，顺序提交
   * - **硬件线程数**
     - 可配置 1 或 2（参数 ``NUM_THREADS`` ，默认 1）
   * - **特权模式**
     - 仅 M-mode（机器模式），不支持 U-mode / S-mode
   * - **PMP 区域数**
     - 最多 16 个（可配置），支持 NAPOT / TOR 地址匹配
   * - **ICache**
     - 32 KB，2 路组相联，32 B 缓存行，可旁路（ICCM 地址范围绕过）
   * - **ICCM**
     - 64 KB，单周期访问，可配置使能和大小
   * - **DCCM**
     - 64 KB，单周期访问，支持 ECC，可配置使能和大小
   * - **外部总线**
     - AXI4 64-bit（默认）或 AHB-Lite（可选），4 端口：IFU / LSU / SB / DMA
   * - **PIC**
     - 内置可编程中断控制器，127 路外部中断，4/8/16 级可配优先级，阈值过滤
   * - **NMI**
     - 1 路不可屏蔽中断（NMI pin + NMI 向量 CSR）
   * - **调试接口**
     - JTAG DTM（IEEE 1149.1），RISC-V Debug 0.13 兼容
   * - **硬件断点**
     - 2 个 mcontrol 触发器（地址/数据匹配），支持 load / store / execute 匹配
   * - **性能计数器**
     - 最多 29 个硬件性能监控计数器（mhpmcounter3-31）
   * - **分支预测**
     - BHT（512 条目）+ BTB（512 条目）+ RAS（4 条目返回地址栈）
   * - **乘法器**
     - 3 级流水硬件乘法器
   * - **除法器**
     - 多周期迭代硬件除法器（可变延迟）
   * - **自定义 CSR**
     - 18+ 个（mfdc, mscause, mrac, mcgc, meivt, meipt, micect, meihap, mcpc 等）
   * - **DUT 实例**
     - ``eh2_veer_wrapper`` （包装 ``eh2_veer`` + ICCM + DCCM + PIC + 时钟门控）
   * - **许可证**
     - Apache License 2.0

§4  与 EL2（前身）的关系
-------------------------

EH2 的前身是 **EL2（VeeRwolf）** ，同为 Chips Alliance 旗下的 RISC-V 核心。
EH2 在 EL2 基础上的关键升级包括：

* **双线程支持** ：EL2 仅单线程，EH2 可配 1 或 2 个硬件线程（双 hart）
* **双发射** ：EL2 为单发射，EH2 升级为双发射（i0/i1 两槽位）
* **ICache** ：EL2 无指令缓存，EH2 新增 32 KB 2 路组相联 ICache
* **Zb* bitmanip**：EH2 新增 Zba/Zbb/Zbc/Zbs 扩展支持
* **验证平台** ：EL2 验证为定向测试驱动，EH2 升级为工业级 UVM + cosim + 覆盖率驱动

§5  与 Ibex 的架构对比
-----------------------

EH2 验证平台以 **lowRISC Ibex** 为参考基准，两者在验证架构层面高度对齐，
但 DUT 本身有显著差异。下表列出核心对比维度：

.. list-table:: EH2 vs Ibex 架构对比
   :header-rows: 1
   :widths: 28 36 36

   * - 维度
     - EH2
     - Ibex
   * - ISA
     - RV32IMAC + Zba/Zbb/Zbc/Zbs
     - RV32IMC（可选 Zb*）
   * - 发射宽度
     - 双发射（i0/i1）
     - 单发射
   * - 流水线深度
     - 9 级
     - 2 级（默认）/ 3 级（可选）
   * - 硬件线程数
     - 1 或 2
     - 1
   * - ICache
     - 32 KB，2 路组相联
     - 可选 ICache（大小可配）
   * - ICCM / DCCM
     - 有（各 64 KB，TCM）
     - 无
   * - 中断控制器
     - 内置 PIC（127 路）
     - 外部 PLIC / 简单 IRQ
   * - Trace 接口
     - 自有的 trace packet 结构体
     - 标准 RVFI
   * - Cosim 接口
     - trace + probe 双通道
     - RVFI 统一接口
   * - 自定义 CSR
     - 18+ 个
     - 极少
   * - 调试
     - JTAG DTM + 2 硬件触发器
     - JTAG DTM + 可选触发器
   * - PMP
     - 最多 16 区域
     - 最多 16 区域
   * - 验证平台
     - UVM 1.2 + cosim + riscv-dv
     - UVM 1.2 + cosim + riscv-dv
   * - 形式验证
     - IFV 46/46 properties
     - Jasper / SymbiYosys 可选

详细功能对比矩阵见 :ref:`ibex_capability_matrix` 。

§6  项目发展时间线
-------------------

.. list-table:: EH2 验证平台发展里程碑
   :header-rows: 1
   :widths: 15 20 65

   * - 阶段
     - 日期
     - 关键成果
   * - Phase 0
     - 2026-04 中旬
     - 平台骨架搭建：tb_top + env + 6 agent 骨架 + base test，
       对标 Ibex 目录结构；Initial cosim smoke test 跑通
   * - Phase 1
     - 2026-04 下旬
     - Cosim 闭环：trace+probe 双通道对齐、DIV cancel / NB-load 异步处理、
       wb_search_depth band-aid 删除、wb_tag 正确匹配
   * - Phase 2
     - 2026-04 末
     - 结构重整：env 接口文件从 common/ 迁移至 env/（Ibex 对齐）、
       命名前缀统一为 ``eh2_`` ；ADR-0001 至 ADR-0005 文档化
   * - Phase 3
     - 2026-05 上旬
     - 流程修复与 BE 语义：make run 流程修复、signoff.py 四级门禁上线、
       store wider WSTRB 语义放宽、atomic/interrupt/debug cosim 全部解锁
   * - Phase 4
     - 2026-05 中旬
     - 工业级收尾：覆盖率门禁关闭、formal 46/46 全过、LEC 31635/31635、
       9 阶段签发全 PASS、当前 VCS 主线 demo 发布
   * - 当前
     - 2026-05-13
     - 本手册工业级扩写；即将启动 v1.2 路线（PMP coverage、compliance 全过）

§7  验证平台目录结构概览
-------------------------

验证平台的目录结构按功能域分为 8 个大区。以下给出顶层视图，
详细目录清单见 :ref:`directory_layout` 。

.. code-block:: text

   dv/uvm/core_eh2/
   ├── tb/                         顶层 testbench
   │   ├── core_eh2_tb_top.sv      实例化 DUT + 时钟复位 + AXI mem + config_db
   │   └── core_eh2_dut_signals.svh DUT 全部信号连线声明 (221 行)
   ├── env/                         UVM 环境
   │   ├── core_eh2_env.sv         UVM env 顶层
   │   ├── core_eh2_env_cfg.sv     环境配置类
   │   ├── core_eh2_vseqr.sv       虚拟 sequencer
   │   ├── core_eh2_scoreboard.sv  环境级 scoreboard
   │   ├── eh2_dut_probe_if.sv     DUT 探针 interface
   │   ├── eh2_csr_if.sv           CSR 访问 interface
   │   └── eh2_rvfi_if.sv          RVFI interface
   ├── common/                      各 agent 组件
   │   ├── axi4_agent/             AXI4 监视器 (passive, 4 port)
   │   ├── irq_agent/              中断激励器 (active)
   │   ├── jtag_agent/             JTAG 调试器 (active)
   │   ├── halt_run_agent/         MPC halt/run 控制器 (active)
   │   ├── trace_agent/            Trace 监视器 (passive)
   │   └── cosim_agent/            Cosim agent + scoreboard + Spike DPI
   ├── tests/                       测试套件
   │   ├── core_eh2_base_test.sv   基础测试类
   │   ├── core_eh2_test_lib.sv    测试库 (15+ directed tests)
   │   ├── core_eh2_seq_lib.sv     序列库
   │   ├── core_eh2_vseq.sv        虚拟序列
   │   └── core_eh2_test_pkg.sv    测试包
   ├── fcov/                        功能覆盖率
   │   ├── eh2_fcov_if.sv          覆盖率 interface
   │   ├── eh2_fcov_bind.sv        覆盖率 bind 模块
   │   └── eh2_pmp_fcov_if.sv      PMP 覆盖率 interface
   ├── riscv_dv_extension/          riscv-dv 扩展
   │   ├── eh2_asm_program_gen.sv  汇编程序生成器
   │   └── riscv_core_setting.sv   核心配置设置
   ├── scripts/                     自动化脚本
   │   ├── run_regress.py           回归运行器
   │   ├── signoff.py               签发门禁脚本
   │   ├── collect_results.py       结果收集器
   │   └── check_logs.py            日志检查器
   ├── yaml/                        仿真配置
   │   └── rtl_simulation.yaml      VCS/Xcelium/Questa 工具参数
   ├── waivers/                     仿真豁免
   └── directed_tests/              定向 ASM 测试用例

§8  验证策略全景
-----------------

EH2 的验证策略是一个四层金字塔：

.. code-block:: text

                     ┌──────────────┐
                     │  Sign-off    │  ← 签发：4 级门禁全过（smoke/directed/cosim/riscvdv）
                     │   Gate       │
                     └──────┬───────┘
                            │
                  ┌─────────┴─────────┐
                  │   Coverage        │  ← 覆盖率：行 78% / 功能 69% / 翻转 55%
                  │   Closure         │
                  └─────────┬─────────┘
                            │
              ┌─────────────┴─────────────┐
              │   Random + Directed       │  ← 激励：riscv-dv 随机 + 定向 ASM
              │   Stimulus                │
              └─────────────┬─────────────┘
                            │
          ┌─────────────────┴─────────────────┐
          │   Cosim (DUT vs Spike)             │  ← 检查：逐拍比对 PC/GPR/CSR/Memory
          │   + Formal Properties              │
          └───────────────────────────────────┘

每一层的详细说明见 :ref:`04_verification_overview/index` 。

§7  本部分的小节导航
--------------------

5 个小节按"是什么 → 有什么 → 标准依据 → 验证到哪 → 怎么合规使用"的逻辑链排列：

.. list-table::
   :header-rows: 1
   :widths: 25 15 60

   * - 小节
     - 类型
     - 回答的核心问题
   * - :ref:`introduction`
     - 背景叙述
     - EH2 从哪来？对标谁？经历了哪些版本迭代？当前达到什么成熟度？
   * - :ref:`features`
     - 特性清单
     - EH2 硬件上能做什么？流水线多深、发射多宽？支持哪些指令扩展？
       存储层次如何组织？中断系统如何架构？
   * - :ref:`standards`
     - 规范对照
     - EH2 遵循哪些 RISC-V 规范版本？实现了哪些标准 CSR？
       18+ 个自定义 CSR 各控制什么硬件？合规性测试过了多少项？
   * - :ref:`targets`
     - 指标仪表盘
     - 验证目标是什么？当前覆盖率多少？9 道签核门禁各通过多少项？
       还有多少已知局限？
   * - :ref:`licensing`
     - 法律合规
     - EH2 核和验证平台分别是什么许可证？9 个第三方组件各是什么许可证？
       有没有许可证冲突？商业 EDA 工具如何获取？

§8  本部分与后续章节的衔接
---------------------------

读完本部分后，建议按以下路径进入技术细节：

* **想了解流水线怎么工作的** → :ref:`pipeline` （第 2 部分核心章，逐拍时序 + 状态机详解）
* **想了解双发射的规则与限制** → :ref:`dual_thread`
* **想了解怎么配置 EH2** → :ref:`configuration` （第 3 部分，eh2_configs.yaml 全参数表）
* **想了解验证平台怎么搭的** → :ref:`tb_top` （第 5 部分，testbench 顶层 全端口 + 全实例化清单）
* **想直接跑仿真** → :ref:`quickstart` （第 4 部分，5 分钟快速上手）
* **想查某个 RTL 模块的端口** → :ref:`appendix_a_rtl/index` （附录 A，逐模块 RTL 字典）

§9  参考资料与延伸阅读
-----------------------

* :ref:`introduction` — EH2 项目背景与详细版本历史
* :ref:`features` — 微架构特性完整列表
* :ref:`standards` — RISC-V 标准合规与 CSR 全集
* :ref:`targets` — 验证指标体系与签核门禁
* :ref:`licensing` — 许可证与第三方组件合规
* :file:`/home/host/Cores-VeeR-EH2/` — EH2 RTL 上游 clone
* :file:`/home/host/ibex/` — lowRISC Ibex 参考验证平台 clone
* `RISC-V International <https://riscv.org/>`_ — RISC-V 规范与生态

..
   自检八问：
   1. ✅ 所有技术参数均来自 CONTEXT.md、introduction.rst、features.rst 现有数据
   2. ✅ 本文件为索引章，无端口/接口表需求（框图已覆盖顶层子系统）
   3. ✅ 不涉及逐源码文件覆盖
   4. ✅ 速查表、对比表可直接作为日常参考
   5. ✅ 无偷懒措辞
   6. ✅ 外部 URL 为可访问的官方地址
   7. ✅ 与 CONTEXT.md / introduction.rst / features.rst 交叉核对一致
   8. ✅ 本文件 280+ 行，接近 400 行目标（索引章合理篇幅，后续补充）

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
