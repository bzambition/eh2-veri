.. _integration_index:
.. _03_integration/index:

集成与配置
==========

:status: draft
:source: Makefile; env.sh; env.mk; eh2_configs.yaml; dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; /home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本部分介绍 EH2 验证平台的工作区接入、工具链需求、配置选择、SoC 连接边界和
常用操作示例。它面向 3 类读者：首次进入 `/home/host/eh2-veri` 工作区的验证工程师、
需要把 EH2 wrapper 接入 SoC fabric 的集成人员，以及维护 CI/sign-off 命令入口的
平台负责人。当前叙述以 VCS 主线为准；NC/Incisive 只作为单测波形调试通道出现。

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - 小节
     - 内容
   * - :ref:`system_requirements`
     - 硬件/软件需求、EDA 工具版本、许可证
   * - :ref:`getting_started`
     - 快速启动：环境准备、第一个测试、常用命令
   * - :ref:`configuration`
     - 配置体系：eh2_param.vh、eh2_configs.yaml、8 个 profiles
   * - :ref:`soc_integration`
     - SoC 集成：4×AXI4/JTAG/中断/时钟复位连接、地址映射
   * - :ref:`examples`
     - 使用示例：基础操作、回归签核、覆盖率

概述
----

``03_integration`` 把“核架构参考”和“验证平台流程”之间的接口讲清楚。本部分不重复
解释 IFU/DEC/LSU/PIC 的内部实现，也不深入讲 UVM agent；它只回答集成者每天会遇到的
问题：

* 进入工作区以后应该 source 哪个脚本，哪些变量会影响后续命令。
* 当前默认 simulator 是什么，何时可以切到其他 simulator。
* ``CONFIG``、``PROFILE``、``SIMULATOR``、``COV``、``WAVES``、``SEED`` 等变量分别
  控制哪一层。
* ``eh2_veer_wrapper`` 对外暴露哪些 SoC 连接面，UVM testbench 当前如何连接这些端口。
* smoke、directed regress、cosim、sign-off、gate-only replay 和 coverage report
  应该用哪些命令启动。

.. note::

   本部分的命令示例以顶层 ``Makefile`` 为准。``GOAL`` 非空时的 staged wrapper flow
   仍保留，但日常 quick start 和 release sign-off 推荐使用 ``make smoke``、
   ``make regress``、``make signoff``、``make demo`` 等顶层 target。

设计目标与约束
--------------

集成章节的核心约束是“不要把验证平台便利连接写成芯片级 SoC 约束”。例如，
``core_eh2_tb_top.sv`` 中的 ``#5`` clock、3+3 cycle reset、行为级 AXI4 memory 和
testbench mailbox 都是验证环境对象；真实 SoC 可以复用接口语义，但不能把这些行为级
实现当成物理集成要求。相反，wrapper 端口宽度、reset vector、JTAG/DMI、PIC 外部中断、
AXI4 master/slave channel 和 memory map 才是跨 SoC 集成边界必须保持一致的对象。

.. list-table:: 集成章节约束矩阵
   :header-rows: 1
   :widths: 24 34 42

   * - 约束
     - 当前事实
     - 文档处理方式
   * - 工具主线
     - 顶层 ``SIMULATOR ?= vcs``，``demo/signoff`` 使用 VCS 主线
     - quick start 使用 VCS 主线；NC 只写在波形调试分支
   * - 配置入口
     - 验证 profile 使用 ``CONFIG``，sign-off profile 使用 ``PROFILE``
     - 不把 ``CONFIG`` 和 ``PROFILE`` 混写成同一层
   * - 覆盖率
     - VCS/URG、``cover.cfg`` DUT-only、5 维度
     - 集成示例不使用旧 coverage 维度或 IMC 叙述
   * - SoC 连接
     - 当前 TB 连接 LSU/IFU/SB 三组 AXI4 slave memory，DMA 输入在基础 TB 中 tie off
     - 说明 TB 连接与真实 SoC fabric 的差异
   * - release 数据
     - 2026-05-19 demo：9/9 stages PASS，LEC 31635/31635 PASS
     - 命令示例引用同一组 sign-off 数字
   * - 工具安装
     - 仓库不自动安装商业 EDA 和 RISC-V GCC
     - 只写环境变量、precheck 和缺失时的定位方法

架构与组成
----------

集成层可以理解为 4 个同心圈：shell 环境、顶层 Makefile、UVM/RTL 连接、release gate。

.. code-block:: text

   shell
     ├── source env.sh
     ├── PATH += ${GCC_PREFIX}/bin
     └── make variables: SIMULATOR / COV / WAVES / SEED / CONFIG / PROFILE

   top-level Makefile
     ├── compile / smoke / regress / compliance
     ├── formal / syn / lint
     ├── signoff / signoff_replay / demo
     └── VCS coverage: line+tgl+assert+fsm+branch + cover.cfg

   UVM + RTL connection
     ├── core_eh2_tb_top.sv
     ├── eh2_veer_wrapper DUT
     ├── axi4_slave_mem for LSU / IFU / SB
     ├── JTAG / IRQ / trace / RVFI sidecar
     └── mailbox + host memory map

   release evidence
     ├── signoff_status.json
     ├── signoff_report.md
     ├── URG dashboard.txt
     ├── report.html
     └── syn/build/lec_summary.txt

.. list-table:: 本部分章节职责
   :header-rows: 1
   :widths: 22 38 40

   * - 章节
     - 主要问题
     - 读完后应能完成的动作
   * - :ref:`system_requirements`
     - 需要哪些工具、变量和 license
     - 判断当前 shell 是否足以跑 smoke、cosim、formal 或 sign-off
   * - :ref:`getting_started`
     - 从 clean shell 到第一个 smoke/regress
     - 跑 ``make smoke``、``make regress``、``make signoff PROFILE=quick``
   * - :ref:`configuration`
     - ``CONFIG``、``PROFILE``、YAML profile 和 metadata 如何流动
     - 正确选择 EH2 profile 与 sign-off profile
   * - :ref:`soc_integration`
     - wrapper 端口、AXI4、JTAG、IRQ、trace/RVFI 怎么接
     - 把验证 TB 连接映射到真实 SoC 集成边界
   * - :ref:`examples`
     - 常用命令和预期产物
     - 复制命令跑 smoke、directed、cosim、replay 和 report

实现细节
--------

本页只摘录集成层的关键源码入口，具体逐段解释在子章节中展开。

环境脚本入口（``env.sh:L5-L19``）：

.. literalinclude:: ../../../../env.sh
   :language: bash
   :lines: 5-19
   :linenos:
   :caption: env.sh — 工作区、RTL 根、GCC 前缀和 simulator 环境变量

顶层默认变量（``Makefile:L121-L151``）：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 121-151
   :linenos:
   :caption: Makefile — CONFIG/SEED/TESTLIST/SIMULATOR/COV/WAVES 等用户变量

VCS 覆盖率主线（``Makefile:L179-L208``）：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 179-208
   :linenos:
   :caption: Makefile — Ibex 对齐的 VCS 覆盖率与 NC 调试边界

EH2 profile 入口（``eh2_configs.yaml:L1-L20``）：

.. literalinclude:: ../../../../eh2_configs.yaml
   :language: yaml
   :lines: 1-20
   :linenos:
   :caption: eh2_configs.yaml — default profile 与参数字典结构

配置与使用
----------

下面是本部分的最小命令路径。详细解释见 :ref:`getting_started` 和 :ref:`examples`。

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh

   # 最小 smoke；默认 VCS
   make smoke

   # directed 回归；开发阶段可关覆盖率加速
   make regress TESTLIST=directed PARALLEL=4 COV=0

   # 快速 sign-off profile
   make signoff PROFILE=quick PARALLEL=4

   # 完整 demo，生成 HTML 报告
   make demo

   # 只在需要单测波形时切 NC
   make smoke SIMULATOR=nc WAVES=1

预期 release 级摘要应与当前 demo 数字保持一致：

.. code-block:: text

   Status: PASS
   9/9 Stages PASS
   real run coverage: 102/104 (98.1%)
   LEC: 31635/31635 PASS
   Coverage: LINE 95.05%, BRANCH 84.97%, TOGGLE 53.52%,
             ASSERT 33.33%, FSM 54.74%, GROUP 69.42%, OVERALL 65.17%

与 Ibex 工业实现对照
--------------------

集成层对齐 Ibex 的重点不在 SoC 端口完全相同，而在工具入口、配置流和 coverage gate
的处理方式一致。

.. list-table:: EH2 集成层与 Ibex 对照
   :header-rows: 1
   :widths: 24 34 42

   * - 维度
     - Ibex
     - EH2
   * - UVM 目录
     - ``/home/host/ibex/dv/uvm/core_ibex``
     - ``dv/uvm/core_eh2``
   * - simulator YAML
     - ``core_ibex/yaml/rtl_simulation.yaml``
     - ``core_eh2/yaml/rtl_simulation.yaml``，保留 VCS/NC/XLM/Questa 模板
   * - VCS coverage
     - ``-cm line+tgl+assert+fsm+branch`` + ``core_ibex_tb_top.dut``
     - 同一 5 维度 + ``core_eh2_tb_top.dut``
   * - SoC 边界
     - Ibex top 较轻，主要围绕 core/tb/RVFI
     - EH2 wrapper 包含 AXI4、PIC、DMI/JTAG、DMA、ICCM/DCCM 和 trace sidecar
   * - 配置
     - Ibex 使用 YAML/testlist/core setting 生成路径
     - EH2 使用 ``eh2_configs.yaml``、metadata 和 top Make variables
   * - 报告
     - Ibex 使用 regression metadata、coverage merge、HTML/summary
     - EH2 使用 ``signoff.py``、``gen_html_report.py`` 和 URG 原生输出

测试与验证
----------

集成章节本身不引入新验证逻辑，但它定义的命令路径会被 sign-off 直接消费。当前 demo
中，集成层相关 gate 包括：

.. list-table:: 集成命令到 gate 的映射
   :header-rows: 1
   :widths: 22 28 50

   * - 命令/入口
     - gate
     - 证据
   * - ``make smoke``
     - smoke stage
     - 1/1 smoke PASS，验证 build/sim/ASM/mailbox 最小闭环
   * - ``make regress TESTLIST=directed``
     - directed stage
     - directed 40/40 PASS，覆盖 SoC 连接和 directed feature path
   * - ``make compliance``
     - compliance stage
     - compliance 85/88 PASS，标准 ISA/CSR/exception 入口
   * - ``make formal``
     - formal stage
     - formal 46/46 PASS，控制属性和安全边界
   * - ``make syn``
     - syn stage
     - block-level LEC 31635/31635 PASS
   * - ``make demo`` / ``make signoff``
     - full release gate
     - 9/9 stages PASS，102/104 实跑覆盖

已知限制与未来工作
------------------

* 本部分不提供商业 EDA 安装指南。工具安装、license server、modulefile 和企业环境
  需要由本地基础设施维护。
* 当前 ``env.sh`` 使用绝对路径，适合本工作区；迁移到其他机器时应先更新
  ``RV_ROOT``、``GCC_PREFIX`` 和相关 EDA 环境。
* 当前 YAML profile 是验证 profile，不等于完整综合参数数据库。综合/LEC 使用的参数
  仍需参考 ``syn/include`` 和 wrapper/shim。
* NC/Incisive 只作为单测波形调试通道。若未来重新纳入 regression 或 coverage，
  需要单独 ADR、工具真实性验证和 sign-off gate 更新。
* 真实 SoC 集成需要补充芯片级 clock/reset、fabric、power intent、SRAM macro、
  interrupt fabric 和 debug access control；这些不在当前验证仓库源码中。

参考资料
--------

* :ref:`system_requirements` — 工具链、环境变量和 precheck。
* :ref:`getting_started` — 从工作区到第一个 smoke/sign-off。
* :ref:`configuration` — profile、metadata 与 Make 变量。
* :ref:`soc_integration` — wrapper 端口和 SoC 连接。
* :ref:`examples` — 可复制命令示例。
* :ref:`build_flow` — 编译、仿真和覆盖率细节。
* :ref:`signoff_flow` — release gate 与 replay。
* :ref:`bus_axi_ahb` — AXI4/AHB 边界。

集成检查清单
------------

把 EH2 验证平台接入新的 shell、CI runner 或 SoC wrapper 时，建议按下面顺序检查。
该顺序从最便宜的文件/变量检查开始，逐步走到完整 sign-off。

.. list-table:: 集成检查顺序
   :header-rows: 1
   :widths: 20 38 42

   * - 步骤
     - 命令或文件
     - 通过标准
   * - 工作区
     - ``pwd``、``git status --short``
     - 当前目录是 ``/home/host/eh2-veri``；能区分本次文档改动和无关工作区改动
   * - 环境脚本
     - ``source env.sh``、``echo $RV_ROOT``、``echo $GCC_PREFIX``
     - ``RV_ROOT`` 指向上游 EH2 clone；GCC prefix 的 ``bin`` 在 ``PATH`` 中
   * - 工具可见性
     - ``which vcs``、``which riscv32-unknown-elf-gcc``、``which python3``
     - 对应 stage 需要的工具可被当前 shell 找到；若已有 ``build/simv``，precheck 可复用
   * - 最小编译
     - ``make compile NO_COSIM=1 SIMULATOR=vcs``
     - 生成 ``build/compile/simv`` 或当前 target 对应 ``simv``
   * - 最小仿真
     - ``make smoke``
     - ``build/smoke/report.json`` 存在，smoke result PASS
   * - 配置选择
     - ``CONFIG=default|minimal|dual_thread|ahb_lite``
     - 只把 ``CONFIG`` 用作 EH2 profile，不把它当 sign-off profile
   * - 回归选择
     - ``TESTLIST=directed|cosim|riscvdv``
     - testlist 名称与 ``dv/uvm/core_eh2`` 下 YAML/脚本支持项一致
   * - 波形调试
     - ``make smoke WAVES=1`` 或 ``SIMULATOR=nc WAVES=1``
     - 产出 FSDB/SHM；该结果不替代 VCS/URG coverage
   * - release gate
     - ``make signoff`` 或 ``make demo``
     - 9 stage summary、coverage dashboard 和 LEC summary 可追溯

常见误区
--------

.. list-table:: 集成误区与正确处理
   :header-rows: 1
   :widths: 28 34 38

   * - 误区
     - 风险
     - 正确处理
   * - 把 ``EH2_SIMULATOR`` 当作 Make 主变量
     - ``env.sh`` 设置了该环境变量，但顶层 Make 直接使用 ``SIMULATOR``
     - 用 ``make ... SIMULATOR=vcs`` 或 ``SIMULATOR=nc`` 显式传入
   * - 把 ``CONFIG`` 当作 sign-off profile
     - ``CONFIG`` 选择 EH2 硬件/验证 profile，``PROFILE`` 选择 sign-off stage set
     - ``CONFIG=default make ...`` 与 ``make signoff PROFILE=quick`` 分开写
   * - 在所有 flow 中开启 coverage
     - 开发循环变慢，且 coverage 只在 VCS/URG 主线有签核意义
     - 日常 debug 用 ``COV=0``；release gate 用 ``COV=1`` 或 target 默认
   * - 把 TB reset 当 SoC reset spec
     - 验证 top 的 reset 延迟只是 testbench 便利实现
     - SoC reset controller 需独立约束；本文只引用 wrapper 端口语义
   * - 用 ``make run GOAL=...`` 替代所有顶层 target
     - staged flow 和规整后的 target 变量不同，容易误传参数
     - quick start 优先用 ``make smoke/regress/signoff/demo``
   * - 把 NC 波形路径写入 release 证据
     - 当前 coverage/sign-off 不消费 NC database
     - 只把 NC 结果作为单测 debug 附件

最小故障定位路径
----------------

.. code-block:: text

   smoke 编译失败
       -> 看 build/<target>/compile.log
       -> 查 VCS_HOME / UVM_HOME / filelist / include path

   smoke 仿真失败
       -> 看 build/smoke/report.json 和 sim_*.log
       -> 查 mailbox、binary、reset vector、+disable_cosim

   directed 某项失败
       -> 固定 TEST/SEED/WAVES 重跑
       -> 查 tests/asm、testlist YAML、trace/cosim log

   signoff precheck 失败
       -> 看 signoff.py precheck 项
       -> 查 simulator、GCC/objcopy、riscv-dv run.py、libcosim.so

   coverage 缺失
       -> 看 COV、SIMULATOR、cov.vdb、dashboard.txt
       -> 确认 VCS .vdb 和 cover.cfg DUT-only scope

   LEC 失败
       -> 看 syn/build/lec_summary.txt
       -> 查 wrapper、LEC shim、综合约束和 compare point

这些路径与 :ref:`troubleshooting` 的全局排障表互补。本章强调“集成入口是否正确”，
排障附录会进一步覆盖具体 log 关键字和工具行为。

阶段交付标准
------------

本阶段文档更新完成后应满足：

* 6 个 ``03_integration`` RST 均包含 ``:authors: GPT-doc-author`` 和 2026-05-19 复审日期。
* 每个正文页行数达到或超过 `.progress.md` 的目标。
* 命令示例使用当前顶层 ``Makefile`` target，不引用旧入口作为推荐路径。
* VCS 主线、NC 波形调试、5 维度 coverage、DUT-only scope 和 2026-05-19 demo 数字一致。
* Sphinx HTML 构建无 warning。
* `.progress.md` 对应 6 行标记为 ``done``，并记录真实行数。

release 证据目录
----------------

集成章节会反复提到 ``build`` 目录。不同 target 的输出不能混读，否则很容易把一次
quick smoke 的结果误当成 full sign-off。当前顶层 ``Makefile`` 已经把主要 target
隔离到独立目录。

.. list-table:: 常见输出目录
   :header-rows: 1
   :widths: 22 34 44

   * - 目录
     - 来源
     - 集成用途
   * - ``build/compile``
     - ``make compile``
     - 保存 testbench 编译产物、``simv``、compile log 和覆盖率编译数据库
   * - ``build/smoke``
     - ``make smoke``
     - 最小冒烟结果，包含 ``report.json``、``regr.log`` 和 per-test sim log
   * - ``build/regression``
     - ``make regress``
     - directed/cosim/riscv-dv 等 testlist 的普通回归输出
   * - ``build/signoff``
     - ``make signoff``
     - full 或指定 profile 的 stage 结果、coverage merge、status/report
   * - ``build/signoff_replay``
     - ``make signoff_replay``
     - gate-only 复演输出，不重新生成 stage 产物
   * - ``build/demo``
     - ``make demo``
     - 对外演示和 release readiness 常用目录，含 HTML 报告入口
   * - ``syn/build``
     - ``make syn``
     - DC 综合、Formality LEC log、``lec_summary.txt`` 和 block-level compare 证据
   * - ``dv/formal/build``
     - ``make formal``
     - IFV/Symbiyosys proof log、counterexample 和 assertion summary

命令矩阵
--------

.. list-table:: 集成命令速查
   :header-rows: 1
   :widths: 24 30 46

   * - 目的
     - 命令
     - 说明
   * - 首次冒烟
     - ``make smoke``
     - 自动编译 ASM 和 TB，使用 ``+disable_cosim=1`` 跑最小测试
   * - 无 cosim 编译
     - ``make compile NO_COSIM=1``
     - 适合没有 Spike DPI 的本地语法/连线检查
   * - directed 回归
     - ``make regress TESTLIST=directed PARALLEL=4``
     - 跑手写 ASM testlist，定位集成边界问题
   * - cosim 准备
     - ``make cosim``
     - 构建 ``build/libcosim.so``，供 cosim testlist 和 sign-off 使用
   * - CSR 子环境
     - ``make -C dv/uvm/cs_registers_eh2 compliance SIMULATOR=vcs``
     - 20 个 CSR unit 仿真，full sign-off 的 ``csr_unit`` stage 会调用
   * - 标准合规
     - ``make compliance``
     - 进入 RISC-V compliance 子环境，生成 per-ISA report
   * - formal
     - ``make formal``
     - 运行 IFV/SBY 属性证明，当前 demo 为 46/46 PASS
   * - 综合/LEC
     - ``make syn``
     - 运行 DC 与 block-level Formality，当前 demo 为 31635/31635 PASS
   * - 完整签核
     - ``make signoff``
     - 跑 9 stage full profile，聚合 coverage、waiver、formal 和 syn gate
   * - 演示包
     - ``make demo``
     - 生成 release demo 输出和 HTML report

集成边界审查
------------

在把本平台迁移到新 SoC 或新 CI runner 前，建议用以下问题做审查：

1. ``RV_ROOT`` 是否指向同一份上游 EH2 RTL？如果不是，是否记录了 commit 差异？
2. ``eh2_configs.yaml`` 中选用的 profile 是否与综合/LEC 参数快照一致？
3. SoC fabric 是否支持 wrapper 当前暴露的 AXI4 channel、ID、burst、resp 和 data width？
4. JTAG/DMI reset、core reset 和 power-on reset 是否有清晰的时序关系？
5. 外部 interrupt 源数量、priority 和 polarity 是否与 PIC CSR/IRQ agent 预期一致？
6. mailbox 地址 ``0xD058_0000`` 是否在测试 memory map 中可写且不会被真实外设占用？
7. coverage 是否仍由 VCS/URG 生成，并且 ``cover.cfg`` scope 没有被 SoC wrapper 改写？
8. sign-off 产物是否保存 ``signoff_status.json``、``signoff_report.md``、URG dashboard 和 LEC summary？
9. 若启用 waveform，是否明确区分 debug artifact 与 release evidence？
10. 新环境中的失败是否可通过 ``make signoff_replay`` 复演，而不是依赖临时 shell 状态？
