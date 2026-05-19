.. _adr_summary:
.. _07_decisions/adr_summary:

ADR 汇总
========

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

架构决策记录（Architecture Decision Record, ADR）是 EH2 验证平台从原型走向
工业级签核的主线账本。当前仓库有 20 条 canonical ADR，编号从 ADR-0001 到
ADR-0020，索引文件为 :file:`docs/adr/INDEX.md`。这些 ADR 覆盖 cosim 数据通路、
AXI4 passive monitoring、双线程 cosim、RVFI adapter、CSR register model、
RISC-V compliance、formal、synthesis、LEC 和 waiver。它们不是孤立的历史记录，
而是解释当前 sign-off gate 的依据。

阅读本章时要注意两个边界。第一，ADR 的早期标题或正文可能保留当时的状态描述，
例如「Proposed」「Open」或旧编号；当前编号和状态以 :file:`docs/adr/INDEX.md`
为准。第二，ADR-0019 记录的是 Formality O-2018 packed-port 的历史限制；
当前 release 使用 ADR-0020 的 block-level LEC 闭环路径，最新 demo 为
31635/31635 PASS。

设计目标与约束
--------------

ADR 汇总页的目标是把「决策」「实现位置」「当前结果」连接起来。单看 ADR 全文，
读者可能只能知道当时为什么做某个选择；单看代码，读者又很难判断某个看似奇怪
的限制是不是有意为之。本页把两者合并：每条 ADR 都列出状态、主题、当前落点和
release 影响。

.. note::

   本章引用 ADR 正文作为历史证据，但不会把旧 coverage 数字或旧 simulator 默认值
   传播为当前事实。当前主线仍是 VCS、URG、``cover.cfg`` DUT-only scope 和
   5 维 code coverage。

架构与组成
----------

20 条 ADR 可以分成 6 组。cosim 组解决 EH2 没有原生 RVFI 的问题；bus/memory
组处理 AXI4 和 LSU 行为；ISA/异常组处理 atomic、interrupt、debug、PMP 和 CSR
差异；formal/RVFI 组为标准化 retire 接口和 property proof 提供路径；综合/LEC
组解决 DC/Formality 工具链问题；release 集成组把 compliance、多 hart 和 waiver
接入 sign-off。

::

   docs/adr/INDEX.md
      |
      +-- Cosim retire data path
      |     ADR-0001 -> ADR-0004 -> ADR-0015 -> ADR-0018
      |
      +-- ISA and micro-architectural compare
      |     ADR-0005 -> ADR-0006 -> ADR-0007 -> ADR-0008 -> ADR-0009 -> ADR-0010
      |
      +-- Release sub-environments
      |     ADR-0011 compliance
      |     ADR-0012/0014 formal
      |     ADR-0013 synthesis
      |
      +-- Multi-hart and waiver boundary
      |     ADR-0003 -> ADR-0016
      |     ADR-0017
      |
      `-- LEC closure
            ADR-0019 historical limitation
            ADR-0020 accepted block-level path

实现细节
--------

ADR canonical index 是本章的权威输入：

.. literalinclude:: ../../../../docs/adr/INDEX.md
   :language: text
   :lines: 1-36
   :caption: docs/adr/INDEX.md:1-36 - ADR 编号和 canonical list 说明

索引中的 Topic Map 把 ADR 按技术域分组，便于 release review 时快速定位：

.. literalinclude:: ../../../../docs/adr/INDEX.md
   :language: text
   :lines: 40-78
   :caption: docs/adr/INDEX.md:40-78 - ADR topic map

LEC 当前口径来自 ADR-0020，而不是 ADR-0019 的历史阻塞状态：

.. literalinclude:: ../../../../docs/adr/0020-blocklevel-lec.md
   :language: text
   :lines: 1-38
   :caption: docs/adr/0020-blocklevel-lec.md:1-38 - block-level LEC 决策

.. literalinclude:: ../../../../docs/adr/0020-blocklevel-lec.md
   :language: text
   :lines: 50-64
   :caption: docs/adr/0020-blocklevel-lec.md:61-78 - 31635/31635 LEC 结果

配置与使用
----------

ADR review 常用命令如下：

.. code-block:: bash

   # 查看 canonical ADR 文件集合
   ls docs/adr

   # 检查 ADR 编号是否连续，避免旧草稿重复编号再次进入索引
   rg -n "Canonical ADR List|Numbering Policy|ADR-00" docs/adr/INDEX.md

   # 查找某个 sign-off 行为的决策来源
   rg -n "waiver|block-level|RVFI|compliance|formal" docs/adr dv/uvm/core_eh2/scripts

   # 查看 Sphinx 附录中的 ADR 全文页
   ls docs/sphinx_cn/source/appendix_d_adr

   # 构建中文手册，确认 ADR 引用和交叉链接有效
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

与 Ibex 工业实现对照
--------------------

Ibex 的工程风格是把关键验证策略写入文档、脚本和 testlist，而不是只存在于
口头约定中。EH2 的 ADR 体系延续这个做法，但覆盖面更偏向 EH2 特有问题：
双线程、AXI4、DMI/JTAG、PIC、DMA、RVFI sidecar 和 block-level LEC。

.. list-table:: ADR 主题与 Ibex 对照
   :header-rows: 1
   :widths: 22 36 42

   * - 主题
     - Ibex 参考
     - EH2 决策
   * - retire 接口
     - Ibex 通过原生 RVFI 和 tracing 支撑 cosim
     - EH2 先用 trace/probe，后续通过 RVFI adapter 和 strict wb_tag 减少启发式
   * - coverage merge
     - :file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py` 使用 URG 合并 VCS coverage
     - EH2 的 :file:`merge_cov.py` 对齐 URG 路径，并移除 NC coverage 作为 sign-off 来源
   * - compliance
     - Ibex 有独立 RISC-V compliance flow
     - ADR-0011 将 EH2 compliance 子环境纳入 full profile
   * - formal
     - Ibex 文档明确 formal/property 边界
     - ADR-0012 和 ADR-0014 记录 EH2 IFV/Symbiyosys property 归属和实跑状态
   * - LEC
     - Ibex 规模较小，top-level 等价路径较直接
     - EH2 通过 ADR-0019 记录工具限制，通过 ADR-0020 建立 block-level closure

ADR 总表
--------

.. list-table:: ADR-0001 到 ADR-0020 当前状态
   :header-rows: 1
   :widths: 10 25 35 30

   * - ADR
     - 主题
     - 当前实现位置
     - release 影响
   * - :ref:`adr-0001`
     - trace + DUT probe cosim 数据通路
     - trace agent、DUT probe monitor、cosim scoreboard
     - 为无原生 RVFI 的 EH2 建立早期 cosim 闭环；后续由 ADR-0004/0018 收敛
   * - :ref:`adr-0002`
     - AXI4 passive monitoring
     - :file:`dv/uvm/core_eh2/common/axi4_agent`
     - 保持 DUT 主控行为真实，TB 用 slave memory 提供响应
   * - :ref:`adr-0003`
     - NUM_THREADS cosim 初始边界
     - :file:`eh2_configs.yaml`、cosim 配置
     - 作为 ADR-0016 的历史前置，说明单 hart 限制来源
   * - :ref:`adr-0004`
     - RTL trace 增加 RVFI 等价字段
     - trace packet、trace monitor、scoreboard
     - 降低 trace/wb 重建不确定性，为 strict matching 铺路
   * - :ref:`adr-0005`
     - Spike 接受 EH2 wider WSTRB
     - :file:`dv/cosim/spike_cosim.cc`
     - 避免合法 LSU read-modify-write 行为误报 store byte enable mismatch
   * - :ref:`adr-0006`
     - Atomic cosim fixup
     - Spike DPI、atomic directed ASM
     - 关闭 A-subset SC.W/LR/AMO 比对风险
   * - :ref:`adr-0007`
     - Interrupt cosim closure
     - PIC CSR sync、scoreboard interrupt-only item
     - 将中断 entry/exit 纳入 ISS 对照边界
   * - :ref:`adr-0008`
     - Debug cosim closure
     - JTAG/halt-run/debug CSR/DRET 路径
     - 让 debug 模式测试从纯自检转向 cosim 可比
   * - :ref:`adr-0009`
     - PMP/ePMP cosim
     - PMP directed tests、Spike CSR fixup、scoreboard exception path
     - 建立 PMP violation 与 EH2 exception/cause 的比对边界
   * - :ref:`adr-0010`
     - CSR register model
     - :file:`dv/uvm/cs_registers_eh2`
     - 支撑 csr_unit stage，当前 sign-off 为 20/20 PASS
   * - :ref:`adr-0011`
     - RISC-V compliance framework
     - :file:`dv/uvm/riscv_compliance`
     - full profile 纳入 compliance stage，demo 为 85/88 PASS
   * - :ref:`adr-0012`
     - Formal strategy
     - :file:`dv/formal`
     - 定义 IFV/Symbiyosys property 文件和模块归属
   * - :ref:`adr-0013`
     - Synthesis toolchain
     - :file:`syn`
     - 选择 DC 主线，给 syn stage 和 LEC 输入提供 netlist
   * - :ref:`adr-0014`
     - Formal real runs
     - formal logs、property summary
     - 从脚手架转为实跑证据，当前 release 引用 46/46 PASS
   * - :ref:`adr-0015`
     - RVFI adapter layer
     - :file:`rtl/eh2_veer_wrapper_rvfi.sv`
     - 不改上游 design RTL 的前提下提供标准 RVFI sidecar
   * - :ref:`adr-0016`
     - Multi-hart cosim
     - Spike per-hart state、scoreboard thread_id 路由
     - 解决 ADR-0003 的双线程 cosim 扩展方向
   * - :ref:`adr-0017`
     - Integrity cosim waiver
     - :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
     - 将硬件 fault injection 类测试从 ISS 不可比转为正式 waiver 管理
   * - :ref:`adr-0018`
     - Strict wb_tag matching
     - :file:`eh2_cosim_scoreboard.sv`、probe monitor
     - 删除 rd 启发式回退，降低 cosim 假阳性
   * - :ref:`adr-0019`
     - Formality 工具版本限制
     - :file:`syn/build/lec_failing.rpt` 历史分析
     - 记录 top-level packed-port 问题，不作为当前 closure 路径
   * - :ref:`adr-0020`
     - Block-level LEC closure
     - :file:`syn/build/lec_summary.txt`
     - 当前 syn/LEC stage 的权威闭环，31635/31635 PASS

测试与验证
----------

ADR 对 sign-off 的影响体现在 stage gate 中。下面的映射用于 release review：

.. list-table:: ADR 到 sign-off stage 的映射
   :header-rows: 1
   :widths: 24 28 48

   * - stage
     - 相关 ADR
     - 当前 demo 结果
   * - smoke/directed
     - ADR-0002、0004、0015、0018
     - directed 40/40 PASS，trace/RVFI/AXI4 基础路径可用
   * - cosim
     - ADR-0001、0005、0006、0007、0008、0009、0016、0017、0018
     - cosim stage PASS，cosim-disabled 通过 waiver 文件管理
   * - riscvdv
     - ADR-0006 到 ADR-0010
     - 370/395 (93.67%) PASS，满足 fail-rate ceiling
   * - csr_unit
     - ADR-0010
     - 20/20 PASS
   * - compliance
     - ADR-0011
     - 85/88 (96.59%) PASS
   * - formal
     - ADR-0012、0014、0015
     - 46/46 PASS
   * - syn
     - ADR-0013、0019、0020
     - LEC 31635/31635 PASS

已知限制与未来工作
------------------

ADR 并不自动关闭所有风险。ADR-0017 的 waiver 需要按 expiry date 复审；ADR-0019
仍提示如果将来恢复 top-level LEC 或升级工具，需要重新评估 packed-port 匹配；
ADR-0016 的 multi-hart cosim 需要继续扩大双线程随机和 directed 覆盖；ADR-0015
的 RVFI adapter 仍应在后续 riscv-formal/Sail 接入时接受独立一致性检查。

ADR 维护规则
------------

后续新增 ADR 时应遵守现有编号策略，使用下一个 4 位编号，不复用旧编号，不在
release note 已引用后改文件名。ADR 正文可以记录当时的上下文和备选方案，但
索引页必须承担「当前解释层」职责：如果某条旧 ADR 被后续 ADR 取代，应在
:file:`docs/adr/INDEX.md` 和本页同时说明 superseded 关系；如果某条 ADR 的状态在
正文中仍写着早期状态，应优先修正文档索引，而不是让使用者在旧状态和当前 gate
之间自行推断。

.. list-table:: ADR 更新检查
   :header-rows: 1
   :widths: 18 38 44

   * - 场景
     - 必改文件
     - 额外核对
   * - 新增决策
     - :file:`docs/adr/NNNN-*.md`、:file:`docs/adr/INDEX.md`
     - 本页总表、附录 D toctree、相关流程章节
   * - 决策被取代
     - 原 ADR、替代 ADR、索引 topic map
     - 风险登记中是否仍引用旧限制
   * - sign-off gate 改变
     - 相关 ADR、:ref:`signoff_flow`、:ref:`coverage_plan`
     - 最新 demo 数据是否需要整体刷新
   * - waiver 策略改变
     - ADR-0017 或新增 ADR、waiver YAML schema 文档
     - ``signoff.py --validate-waivers`` 的实际行为

参考资料
--------

* :file:`docs/adr/INDEX.md` - canonical ADR 索引。
* :ref:`risk_register` - ADR 关闭的风险与 residual risk。
* :ref:`coverage_plan` - coverage 决策如何进入 sign-off。
* :ref:`known_limitations` - ADR 后仍保留的限制。
* :ref:`appendix_d_adr_index` - ADR 全文附录。
