.. _core_reference_index:
.. _02_core_reference/index:

EH2 核架构参考 — 导航
======================

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本部分是手册的**核心技术部分** ，详细描述 EH2 处理器的微架构。
10 个小节按流水线顺序和功能域组织。当前叙述以 2026-05-19 VCS 主线 demo
为基准：9/9 sign-off stages PASS，实跑覆盖率 102/104 (98.1%)，
block-level Formality LEC 31635/31635 PASS；覆盖率使用 Ibex 对齐的
``-cm line+tgl+assert+fsm+branch``、``cover.cfg`` dut-only scope 和 URG 原生
dashboard。

.. note::

   本部分描述的是 RTL 架构与验证可观测接口。主线 simulator 是 VCS；NC/Incisive
   只在单测波形调试中出现，不作为覆盖率或 sign-off 现状来叙述。

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - 小节
     - 内容
   * - :ref:`pipeline`
     - **核心章** 。9 级流水线全解、双发射 6 条规则、4 种 stall、
       3 类写回、旁路前递网络、flush 传播、时钟门控、trace packet 格式
   * - :ref:`dual_thread`
     - 双硬件线程（SMT）。每线程独立 IB/GPR/TLU。线程仲裁器
       (rvarbiter2_smt)。线程间隔离与通信
   * - :ref:`icache`
     - 指令缓存与 ICCM。当前参数为 32 KB、4-way、每 way 2-bank、
       64 B line、ECC 使能的 ICache；ICCM 为 64 KB 紧耦合指令存储。
       本章只写当前源码可回溯的 hit/miss、fill、bypass 与 ECC 路径
   * - :ref:`dccm_iccm`
     - 数据/指令紧耦合存储边界。当前 DCCM 为 64 KB、8-bank、ECC 保护；
       ICCM 为 64 KB。章节重点是参数、端口、formal property 和 directed ASM
       证据链，而非不可回溯的旧内部状态机描述
   * - :ref:`csr`
     - **CSR 寄存器体系** 。~80 个 CSR 逐位字段详解。
       Espresso 译码原理。WARL 行为。Cosim 桥接策略
   * - :ref:`pic`
     - 可编程中断控制器。127 路外部中断。优先级仲裁。
       阈值过滤。快速中断重定向
   * - :ref:`debug`
     - 调试系统。JTAG DTM + DMI。Abstract command。
       硬件触发器。Halt/Resume 握手
   * - :ref:`bus_axi_ahb`
     - AXI4/AHB-Lite 总线接口。UVM TB 可观测主路径是 LSU/IFU/SB 三组
       AXI4 master 端口；DMA 输入在基础 TB 中 tie off，AHB-Lite 主要作为
       LEC shim/可选配置边界出现
   * - :ref:`rvfi_trace`
     - Trace 接口。双槽位 trace packet 格式。
       RVFI adapter。Cosim scoreboard 消费
   * - :ref:`mailbox`
     - Mailbox 地址。0xD058_0000。PASS/FAIL 编码。
       Cosim 超时保护

建议阅读顺序：先读 :ref:`pipeline` 建立全局认知，再按需深入各子系统。

概述
----

``02_core_reference`` 是面向 RTL 读者、验证工程师和 SoC 集成人员的核心架构参考。
它不替代上游 EH2 源码，也不重复附录 A 的逐文件逐段解析；本部分的职责是把
EH2 的主要微架构对象、验证可观测接口和 sign-off 证据组织成可以快速检索的
系统模型。读者在排查 cosim mismatch、PMP access fault、debug halt 卡死、
RISC-V compliance 失败或 LEC 比对差异时，应先用本章确认问题属于 IFU、DEC、
EXU、LSU、TLU、PIC、DBG、DMI、DMA、memory wrapper 还是验证侧 trace/RVFI
边界，再跳转到对应深度章节。

当前手册以 ``/home/host/eh2-veri`` 工作区和
``/home/host/Cores-VeeR-EH2`` 上游 clone 为准。RTL 规模约 4.6 万行
SystemVerilog，核心顶层路径包括 ``design/eh2_veer.sv``、
``design/eh2_veer_wrapper.sv``、``design/dec``、``design/exu``、
``design/ifu``、``design/lsu``、``design/dbg``、``design/dmi``、
``design/dma``、``design/lib``、``design/eh2_pic_ctrl.sv`` 和
``design/eh2_mem.sv``。验证侧将 wrapper 实例化在
``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``，并通过 trace monitor、DUT probe、
RVFI sidecar、Spike DPI 和 functional coverage bind 形成可观测闭环。

.. warning::

   本部分不把历史 NC 迁移阶段的覆盖率数字作为当前结论。出现 ``irun``、
   ``ncelab``、``INCA_libs`` 或 ``waves.shm`` 时，只表示调试单测、波形或历史 ADR
   背景。release/sign-off 叙述一律以 VCS、URG、``simv``、``cov.vdb`` 和
   ``core_eh2_tb_top.dut`` 子树为准。

设计目标与约束
--------------

EH2 核架构章节的写作目标有 4 个层次。第一层是**微架构可读性**：把 9 级流水线、
双发射、ICache/ICCM/DCCM、CSR/TLU、PIC、debug/DMI、AXI4/AHB 边界和 mailbox
机制解释到足以指导调试。第二层是**验证可观测性**：每个硬件现象都要能落到
trace packet、DUT probe、RVFI adapter、coverage bind、directed ASM 或 formal
property 的某个证据点。第三层是**工具流一致性**：架构描述必须与 VCS 主线、
Ibex 对齐覆盖率、URG dashboard、signoff.py 9 stage gate 和 Formality LEC 数字
一致。第四层是**边界诚实**：当前 release 参数实例中没有启用的路径，例如
``NUM_THREADS > 1`` elaboration 分支、DMA 输入的部分 SoC 集成路径、NC 覆盖率汇总，
只能写成源码支撑面或调试通道，不能写成已签核默认行为。

.. list-table:: 核架构章节的工业约束
   :header-rows: 1
   :widths: 22 38 40

   * - 约束
     - 当前事实
     - 文档处理方式
   * - simulator
     - 顶层 ``Makefile`` 中 ``SIMULATOR ?= vcs``；``demo`` 和 ``signoff`` 强制走 VCS
     - 命令示例默认写 ``make demo``、``make signoff``、``make smoke``，需要波形时才写 ``SIMULATOR=nc WAVES=1``
   * - 覆盖率维度
     - ``VCS_COV_METRICS := line+tgl+assert+fsm+branch``
     - 所有章节只引用这 5 个 code coverage 维度；不把 ``cond`` 写成当前 gate
   * - 覆盖率 scope
     - ``cover.cfg`` 只包含 ``+tree core_eh2_tb_top.dut``，并排除 DUT 内 toggle 子树
     - 覆盖率数字必须说明来自 DUT 子树 URG dashboard，而不是 TB stub 或接口层
   * - sign-off stage
     - ``full`` profile 为 smoke、directed、cosim、riscvdv、lint、csr_unit、compliance、formal、syn
     - 架构章节引用 stage 结果时使用同一套 9 stage 名称
   * - waiver gate
     - stage waiver eligibility 有 25% fail-rate ceiling
     - 不把“达到最小通过数”写成无条件 PASS；必须结合 fail rate 与 formal waiver
   * - LEC gate
     - block-level Formality LEC 最新 demo 为 31635/31635 PASS
     - wrapper、RVFI、LEC shim、综合相关章节都引用同一 gate

架构与组成
----------

EH2 在本项目中的层次可以分成 5 个边界：上游 RTL、项目内验证 wrapper、
UVM testbench、子环境和工具流。下面的 ASCII 图是阅读本部分时最常用的索引图。

.. code-block:: text

   /home/host/Cores-VeeR-EH2/design
   ├── eh2_veer.sv
   │   ├── ifu/     指令获取、ICache、ICCM、BTB/BHT、aligner
   │   ├── dec/     decode、IB、CSR/TLU、GPR、scoreboard、trace packet
   │   ├── exu/     ALU、branch、MUL/DIV、bitmanip、flush path
   │   └── lsu/     DCCM、store buffer、AXI4 load/store、PMP/addrcheck
   └── eh2_veer_wrapper.sv
       ├── eh2_mem.sv          ICCM/DCCM wrapper 与 SRAM 边界
       ├── eh2_pic_ctrl.sv     127 路 external interrupt controller
       ├── dma/                DMA slave/控制路径
       ├── dbg/ + dmi/         debug module、JTAG DTM、DMI wrapper
       └── bus interfaces      IFU/LSU/SB/DMA AXI4，AHB 可选边界

   /home/host/eh2-veri
   ├── rtl/eh2_veer_wrapper_rvfi.sv      RVFI sidecar adapter
   ├── rtl/lec_shim/                     Formality packed-port shim
   ├── dv/uvm/core_eh2/tb                UVM top，DUT 实例和 interface 连接
   ├── dv/uvm/core_eh2/common            axi4/jtag/irq/cosim/trace agents
   ├── dv/uvm/core_eh2/fcov              DUT coverage bind
   ├── dv/uvm/cs_registers_eh2           CSR unit 子环境
   ├── dv/uvm/riscv_compliance           RISC-V compliance 子环境
   └── dv/formal + syn + lint            formal、综合/LEC、lint gate

.. list-table:: 章节到源码的快速映射
   :header-rows: 1
   :widths: 20 36 44

   * - 章节
     - 主源码
     - 常见调试问题
   * - :ref:`pipeline`
     - ``design/dec/eh2_dec.sv``、``design/exu``、``design/lsu``、``eh2_trace_monitor.sv``
     - 双发射排序、flush、stall、DIV/NB-load 异步写回、trace commit 顺序
   * - :ref:`dual_thread`
     - ``syn/include/eh2_param.vh``、``eh2_dec_ib_ctl.sv``、``SpikeCosim``
     - 当前 ``NUM_THREADS=1`` 与源码 SMT 支撑面的边界，thread_id 路由
   * - :ref:`icache`
     - ``design/ifu``、``eh2_ifu_ic_mem.sv``、``eh2_ifu_mem_ctl.sv``
     - ICache miss/fill、ICCM bypass、ECC、FENCE.I、branch predictor 交互
   * - :ref:`dccm_iccm`
     - ``design/lsu``、``eh2_mem.sv``、formal property、directed ASM
     - DCCM bank、ECC、ICCM/DCCM address map、DMA stall 与 access fault
   * - :ref:`csr`
     - ``eh2_dec_csr.sv``、``eh2_dec_tlu_ctl.sv``、``eh2_csr_reg_block.sv``、``spike_cosim.cc``
     - WARL、presync/postsync、trap CSR、custom CSR fixup、CSR unit gate
   * - :ref:`pic`
     - ``eh2_pic_ctrl.sv``、PIC CSR、irq agent、formal PIC property
     - external interrupt priority、threshold、claim/complete、fast interrupt
   * - :ref:`debug`
     - ``design/dbg``、``design/dmi``、JTAG agent、debug directed ASM
     - halt/resume、abstract command、DCSR/DPC、trigger CSR、debug ROM
   * - :ref:`bus_axi_ahb`
     - wrapper AXI4 ports、``axi4_agent``、LEC shim
     - LSU/IFU/SB transaction、AXI SVA、AHB 可选边界、DMA tie-off
   * - :ref:`rvfi_trace`
     - ``eh2_trace_intf.sv``、``eh2_trace_monitor.sv``、``eh2_veer_wrapper_rvfi.sv``
     - trace/RVFI 对齐、interrupt-only item、async writeback tag
   * - :ref:`mailbox`
     - ASM tests、host memory map、cosim scoreboard
     - PASS/FAIL 编码、timeout、test termination 与 compliance 结果采集

实现细节
--------

本部分所有架构事实都要求可回溯到真实源码。为了避免在正文中大量复制上游文件，
本页只摘录 3 个“全局约束”片段；各子章再展开对应模块。

VCS 覆盖率配置（``Makefile:L179-L208``）：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 179-208
   :linenos:
   :caption: Makefile — VCS 5 维度覆盖率与 NC 调试边界

DUT-only 覆盖率 scope（``dv/uvm/core_eh2/cover.cfg:L1-L4``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/cover.cfg
   :language: text
   :lines: 1-4
   :linenos:
   :caption: cover.cfg — 只统计 core_eh2_tb_top.dut 子树

sign-off stage 定义（``signoff.py:L37-L53``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 37-53
   :linenos:
   :caption: signoff.py — full profile 与 stage 最小通过数

stage waiver 的 fail-rate ceiling（``signoff.py:L398-L423``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 398-423
   :linenos:
   :caption: signoff.py — 25% fail-rate ceiling

这些片段解释了为什么本章不按“工具偏好”组织，而按“签核事实”组织：架构手册中的
每个数字最终都会被 ``signoff.py``、``cover.cfg``、URG dashboard 或 Formality LEC
报告消费。若 RTL 行为与验证工具观测边界不一致，文档必须指出差异，而不是把
verification artifact 写成 DUT 功能。

配置与使用
----------

架构章节本身不是流程手册，但读者通常会在定位问题时需要最小命令。下面给出
与本部分最相关的命令入口。

.. code-block:: bash

   # 快速确认 DUT 能跑通基础 smoke；默认 simulator 为 VCS
   make smoke

   # 跑完整 demo，生成 signoff_status.json、signoff_report.md 和 HTML 报告
   make demo

   # 跑 release 级 sign-off；默认 full profile，包含 9 个 stage
   make signoff

   # 只需要波形调试时使用 NC/Incisive，不能把该路径的 coverage 当作 sign-off
   make smoke SIMULATOR=nc WAVES=1

   # CSR 子环境独立 gate，由 signoff.py 的 csr_unit stage 调用
   make -C dv/uvm/cs_registers_eh2 compliance SIMULATOR=vcs

.. code-block:: text

   2026-05-19 01:02 demo 摘要：
     Status: PASS
     9/9 Stages PASS
     实跑覆盖率: 102/104 (98.1%)
     LEC: 31635/31635 PASS
     LINE 95.05%, BRANCH 84.97%, TOGGLE 53.52%,
     ASSERT 33.33%, FSM 54.74%, GROUP 69.42%, OVERALL 65.17%
     riscvdv 370/395, compliance 85/88, directed 40/40, formal 46/46

与 Ibex 工业实现对照
--------------------

EH2 手册刻意对齐 lowRISC Ibex 的验证叙事方式，但不复制 Ibex 的微架构描述。
Ibex 的核心优势是 RVFI 原生可观测性、成熟的 ``core_ibex`` UVM 环境和 VCS/URG
覆盖率配置；EH2 的复杂度来自双发射深流水、trace/probe 历史接口、PIC/DMA/DMI、
DCCM/ICCM 和 block-level LEC。对照的目的不是把 EH2 写成 Ibex，而是把 EH2 的
工业 gate 和报告方式拉到同一标准。

.. list-table:: 核架构总览与 Ibex 对照
   :header-rows: 1
   :widths: 24 34 42

   * - 维度
     - Ibex 参考
     - EH2 当前实现
   * - RTL 顶层
     - ``/home/host/ibex/rtl/ibex_top.sv``，单发射 RV32 core
     - ``/home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv``，双发射 EH2 wrapper
   * - UVM top
     - ``/home/host/ibex/dv/uvm/core_ibex/tb/core_ibex_tb_top.sv``
     - ``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``
   * - coverage scope
     - ``/home/host/ibex/dv/uvm/core_ibex/cover.cfg`` 为 ``+tree core_ibex_tb_top.dut``
     - ``dv/uvm/core_eh2/cover.cfg`` 为 ``+tree core_eh2_tb_top.dut``
   * - VCS cov opts
     - ``rtl_simulation.yaml`` 使用 ``-cm line+tgl+assert+fsm+branch`` 与 ``-cm_hier cover.cfg``
     - 顶层 ``Makefile`` 使用同一 5 维度，并通过 ``merge_cov.py`` 调 URG
   * - CSR unit
     - ``/home/host/ibex/dv/cs_registers`` 为独立 CSR 测试生态
     - ``dv/uvm/cs_registers_eh2`` 采用 UVM register layer，sign-off 中 20/20 PASS
   * - trace/RVFI
     - Ibex 原生 RVFI/tracer 路径
     - EH2 trace packet + probe + RVFI sidecar，scoreboard 做 Spike DPI 同步
   * - 额外硬件
     - Ibex 集成较轻，外设/interrupt 复杂度低
     - EH2 wrapper 包含 PIC、DMA、DMI/JTAG、ICCM/DCCM、AXI4 多 master 边界

测试与验证
----------

核架构章节引用的验证证据来自完整 demo，而不是单个章节自造门限。各模块对应的
主要验证入口如下：

.. list-table:: 架构域到 sign-off stage 的映射
   :header-rows: 1
   :widths: 22 28 50

   * - 架构域
     - 主要 stage
     - 证据说明
   * - 流水线、trace、mailbox
     - smoke、directed、cosim、riscvdv
     - smoke 和 directed 提供确定性 ASM；cosim 与 riscv-dv 扩大 ISA/异常/写回覆盖
   * - CSR/TLU/PMP
     - csr_unit、compliance、riscvdv、formal
     - CSR unit 20/20 PASS；compliance 85/88；PMP directed 和 formal 覆盖 corner
   * - PIC/debug/DMI/JTAG
     - directed、formal、cosim
     - directed ASM 驱动 PIC/debug 状态，formal 检查控制类 SVA
   * - ICache/ICCM/DCCM/LSU
     - directed、riscvdv、formal、syn
     - memory directed、PMP directed、IFV property 和 LEC 共同覆盖存储边界
   * - 总线和 wrapper
     - directed、lint、syn
     - AXI4 agent/SVA、lint 双引擎、DC 综合和 block-level LEC
   * - 覆盖率收敛
     - signoff coverage gate
     - URG 原生 dashboard：LINE 95.05%，OVERALL 65.17%，只统计 DUT 子树

已知限制与未来工作
------------------

* 当前 release 参数实例为 ``NUM_THREADS=1``。源码存在 SMT 支撑面，cosim DPI 也保留
  ``thread_id``，但默认手册不能把双线程运行写成当前签核配置。
* NC/Incisive 仍可用于单测波形调试，但不参与当前 coverage/sign-off。若后续恢复 NC
  regression，需要新的 ADR 和独立覆盖率真实性验证。
* ``ASSERT`` 和 ``FSM`` 覆盖率仍低于 line/branch，当前 demo 中分别为 33.33% 和
  54.74%。这不是 build failure，但会在覆盖率计划和后续 directed/formal 增强中跟踪。
* ``riscvdv`` 370/395 和 compliance 85/88 通过的是 sign-off gate，而不是所有 testlist
  条目 100% 通过。waiver 必须留在 ``dv/uvm/core_eh2/waivers`` 和 ADR 风险登记中。
* block-level LEC gate 当前为 31635/31635 PASS；若综合参数、wrapper 或 LEC shim 改动，
  必须重新跑 ``make syn`` 或对应 gate-only replay，不能复用旧数字。

参考资料
--------

* :ref:`pipeline` — 流水线、双发射、stall、flush 与 trace commit。
* :ref:`csr` — CSR、TLU、WARL、PMP、debug CSR 和 Spike fixup。
* :ref:`rvfi_trace` — trace packet、RVFI sidecar 与 cosim 可观测边界。
* :ref:`signoff_flow` — 9 stage sign-off、coverage gate 和 replay。
* :ref:`coverage_plan` — 覆盖率目标、dut-only scope 和 URG 结果解释。
* :ref:`adr_summary` — ADR 总览与历史决策。
* :doc:`../appendix_a_rtl/index` — RTL 附录入口。
* ``/home/host/ibex/dv/uvm/core_ibex`` — Ibex UVM 验证对照。

章节维护规则
------------

本目录后续扩写和复审遵循同一套维护规则。它们不是排版偏好，而是为了保证架构手册
可以作为 release evidence 的入口使用。

.. list-table:: ``02_core_reference`` 维护检查表
   :header-rows: 1
   :widths: 26 34 40

   * - 检查项
     - 合格标准
     - 不合格示例
   * - 当前事实
     - 主线 simulator 写 VCS；覆盖率写 ``line+tgl+assert+fsm+branch``；demo 数据写 2026-05-19 数字
     - 把 NC 写成主线工具、写旧 coverage 维度、写 IMC 合成 dashboard 或旧假阳性数字
   * - 源码引用
     - 每个关键行为至少能回溯到 RTL/UVM/脚本/配置文件
     - 只写抽象 ISA 规范，不引用 EH2 实现
   * - Ibex 对照
     - 说明完全一致处和合理差异处，并给出 ``/home/host/ibex`` 路径
     - 把 Ibex 的单发射/RVFI 路径直接套到 EH2
   * - 验证证据
     - 引用 9 stage、102/104、31635/31635、URG 原生 coverage 数字
     - 只写“测试通过”而没有 stage、数量、路径或 gate
   * - 章节边界
     - 正文写架构和证据，附录 A 写逐文件细节，流程章节写命令和脚本
     - 在一个章节内混入大量无关 flow、ADR 或工具安装说明
   * - 历史背景
     - NC 迁移 bug 只在 ADR/历史风险中出现；当前章节只把 NC 写成波形调试通道
     - 把历史迁移经验写成当前默认工具流

本页也作为 Phase 1 的复审入口。每次修改 ``02_core_reference`` 后至少运行：

.. code-block:: bash

   rg -n "<redline-patterns>" \
     docs/sphinx_cn/source/02_core_reference
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

如果 Sphinx 构建因其他章节的已知 warning 失败或新增 warning，必须在阶段记录中说明。
本阶段当前已修复 ``08_appendix/references.rst`` 的 ADR 模板坏引用；后续阶段如果
发现旧扁平文档或未重写章节里还有过时事实，应在对应阶段处理，而不是在 Phase 1
无边界地重写全书。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：核对本页关联的 RTL 名称是否能在上游 design 目录和中文手册代码引用中同时找到。

.. code-block:: bash

   rg -n "module |input |output |parameter" /home/host/Cores-VeeR-EH2/design | head -40
   rg -n "literalinclude::|code-block:: verilog" docs/sphinx_cn/source/02_core_reference docs/sphinx_cn/source/appendix_a_rtl | head -40

**进阶题**：确认该 RTL 主题没有脱离当前 VCS/URG coverage 和 LEC 证据口径。

.. code-block:: bash

   rg -n "core_eh2_tb_top.dut|cover.cfg|31635/31635|95.05" docs/sphinx_cn/source/02_core_reference docs/sphinx_cn/source/appendix_a_rtl

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
