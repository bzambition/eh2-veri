.. _glossary:
.. _08_appendix/glossary:

术语表
======

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本章统一 EH2 中文手册中的缩写、英文术语和中文解释。验证平台涉及 RISC-V ISA、
处理器微架构、SystemVerilog/UVM、EDA 工具、coverage、formal、synthesis/LEC 和
本地工程流程；同一个缩写在不同上下文中可能有不同含义。术语表的目标是保证读者
在阅读架构、UVM 组件、流程和 ADR 时使用同一套词汇。

术语首次出现时，本手册通常采用「中文（English, 缩写）」格式；后续段落保留英文
缩写。例如「验证环境（verification environment, env）」首次展开后，后文直接写
env。工具名如 VCS、URG、Formality、IFV、DC、Spike、riscv-dv 不强行翻译。

设计目标与约束
--------------

术语表只解释本项目实际使用的概念，不收录与 EH2 无关的泛化条目。若某个术语同时
有规范含义和项目实现含义，表格会区分「规范定义」和「EH2 用法」。例如 RVFI 在
规范层是 RISC-V Formal Interface；在 EH2 中是 wrapper sidecar 适配层，而不是
上游 design RTL 原生接口。

.. note::

   ``GROUP`` 在 URG dashboard 中表示 SystemVerilog covergroup 结果；`signoff.py`
   内部历史键名是 ``functional``。文档展示时统一写 ``GROUP``，只在解释脚本兼容性
   时提到内部键名。

架构与组成
----------

术语可按 6 类记忆：

::

   ISA / Core      RV32IMAC, Zb*, CSR, PMP, PIC, DCCM, ICCM
   UVM / TB        env, agent, monitor, driver, sequencer, vseq, scoreboard
   Cosim / ISS     Spike, DPI, trace item, retire, wb_tag, RVFI
   Coverage        LINE, BRANCH, TOGGLE, ASSERT, FSM, GROUP, OVERALL
   Tools           VCS, URG, Verdi, IFV, DC, Formality, Verible, Verilator
   Sign-off        stage, gate, waiver, profile, LEC, compliance

实现细节
--------

术语不是孤立定义，它们对应真实代码和配置。下面片段展示 sign-off stage 的官方名称：

.. literalinclude:: ../../../../dv/uvm/core_eh2/scripts/signoff.py
   :language: python
   :lines: 37-55
   :caption: signoff.py:37-55 - stage 名称和最小通过数

coverage 维度来自 Makefile，而不是文档自由定义：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 169-178
   :caption: Makefile:169-178 - VCS coverage 术语来源

waiver schema 中的字段名也是术语表的一部分：

.. literalinclude:: ../../../../dv/uvm/core_eh2/waivers/cosim-disabled.yaml
   :language: yaml
   :lines: 1-16
   :caption: cosim-disabled.yaml:1-16 - waiver 字段名

配置与使用
----------

查找术语来源的常用命令：

.. code-block:: bash

   # 查找某个术语在手册中的用法
   rg -n "RVFI|wb_tag|GROUP|waiver" docs/sphinx_cn/source

   # 查找某个 UVM 类或接口定义
   rg -n "class .*scoreboard|interface .*rvfi|covergroup" dv/uvm/core_eh2

   # 查找 sign-off stage 名称
   rg -n "PROFILE_STAGES|STAGE_MIN_PASSED" dv/uvm/core_eh2/scripts/signoff.py

核心术语表
----------

.. list-table:: 核心术语
   :header-rows: 1
   :widths: 20 24 56

   * - 术语
     - 英文全称或类别
     - EH2 手册中的含义
   * - DUT
     - Device Under Test
     - 待测设计，通常指 `core_eh2_tb_top.dut` 下的 EH2 RTL 实例
   * - EH2
     - VeeR EH2
     - Western Digital/CHIPS Alliance VeeR EH2 RISC-V core
   * - RV32IMAC
     - RISC-V ISA profile
     - 32 位整数、乘除、原子和压缩指令基础组合；EH2 还包含 Zb* bitmanip 支持
   * - Zb*
     - RISC-V Bitmanip family
     - bitmanip 扩展族，在 riscv-dv 和 directed tests 中作为覆盖目标
   * - CSR
     - Control and Status Register
     - 机器模式、debug、PIC、memory control 和 EH2 custom CSR 集合
   * - WARL
     - Write Any, Read Legal
     - CSR 字段可写任意值但读回合法值；cosim 需要 Spike fixup 或 CSR model
   * - PMP
     - Physical Memory Protection
     - 物理内存保护，包含 TOR、NA4、NAPOT、lock、priority 等覆盖维度
   * - PIC
     - Programmable Interrupt Controller
     - EH2 127 路外部中断控制器和相关 CSR
   * - DCCM
     - Data Closely Coupled Memory
     - 数据紧耦合存储，LSU 侧访问并受 ECC/完整性路径影响
   * - ICCM
     - Instruction Closely Coupled Memory
     - 指令紧耦合存储，IFU 侧取指路径之一
   * - ICache
     - Instruction Cache
     - 指令缓存，包含 tag/data/parity 和 fill/flush 行为
   * - Trace item
     - Retire trace transaction
     - trace monitor 采样的退役指令事务，用于 cosim scoreboard
   * - RVFI
     - RISC-V Formal Interface
     - EH2 项目内 wrapper sidecar 适配层，不表示上游 design RTL 原生 RVFI
   * - DPI
     - Direct Programming Interface
     - SystemVerilog 调用 C/C++ Spike cosim 的接口
   * - Spike
     - RISC-V ISA simulator
     - cosim golden reference；不建模 EH2 ECC/parity fault injection
   * - Agent
     - UVM agent
     - UVM 中封装 driver、monitor、sequencer 和 config 的组件
   * - Monitor
     - UVM monitor
     - 被动采样接口信号并发出 transaction
   * - Scoreboard
     - UVM scoreboard
     - 比对 DUT trace/probe/AXI 与 Spike 参考模型的组件
   * - vseq
     - virtual sequence
     - 统筹多个 agent sequencer 的 UVM stimulus 序列
   * - Mailbox
     - Test status MMIO
     - 汇编测试通过写特定地址报告 PASS/FAIL 的机制

覆盖率与工具术语
----------------

.. list-table:: coverage 和工具术语
   :header-rows: 1
   :widths: 18 26 56

   * - 术语
     - 类别
     - 说明
   * - LINE
     - code coverage
     - 行覆盖率，当前 demo 为 95.05%
   * - BRANCH
     - code coverage
     - 分支覆盖率，当前 demo 为 84.97%
   * - TOGGLE
     - code coverage
     - 信号翻转覆盖率，当前 demo 为 53.52%
   * - ASSERT
     - assertion coverage
     - 断言触发/覆盖统计，当前 demo 为 33.33%
   * - FSM
     - state coverage
     - 状态机覆盖率，当前 demo 为 54.74%
   * - GROUP
     - covergroup coverage
     - SystemVerilog covergroup 结果，当前 demo 为 69.42%
   * - OVERALL
     - URG score
     - URG 综合分，当前 demo 为 65.17%
   * - VCS
     - simulator
     - 当前默认 simulator 和 sign-off 主线
   * - URG
     - coverage report
     - VCS coverage merge/report 工具，生成 dashboard
   * - Verdi
     - debug GUI
     - 波形和调试查看工具
   * - NC/Incisive
     - simulator/debug
     - 仅用于单测波形调试，不参与 sign-off coverage
   * - IFV
     - formal
     - Cadence 形式验证工具，formal stage 当前 46/46 PASS
   * - DC
     - synthesis
     - Synopsys Design Compiler，生成综合输入和 SVF
   * - Formality
     - LEC
     - Synopsys 等价检查工具，block-level LEC 当前 31635/31635 PASS
   * - Verible
     - lint
     - SystemVerilog lint/format 工具
   * - Verilator
     - lint
     - SystemVerilog lint 和静态分析工具

与 Ibex 工业实现对照
--------------------

Ibex 文档大量保留英文缩写并用上下文解释其含义。EH2 保持相同风格，但新增双线程、
AXI4、PIC、DMI/JTAG、DMA、DCCM/ICCM 和 block-level LEC 相关术语。

测试与验证
----------

术语表验证靠一致性扫描：

.. code-block:: bash

   # 检查 GROUP 和 functional 是否被混用为展示名
   rg -n "functional coverage|GROUP" docs/sphinx_cn/source

   # 检查 NC 是否只出现在调试语境
   rg -n "NC|Incisive" docs/sphinx_cn/source

已知限制与未来工作
------------------

术语表会随附录 A 到 F 扩写继续增加条目。新增术语前应先确认是否已有等价缩写，
避免同一概念出现多个中文译名。

参考资料
--------

* :ref:`coverage_plan` - coverage 术语上下文。
* :ref:`signoff_flow` - sign-off stage 和 gate 术语。
* :ref:`cosim_scoreboard` - cosim、trace、Spike、scoreboard 术语。
* :ref:`rvfi_trace` - RVFI 和 trace 术语。
