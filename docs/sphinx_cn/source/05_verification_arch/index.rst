.. _verification_arch_index:
.. _05_verification_arch/index:

验证平台架构与组件
==================

:status: draft
:source: dv/uvm/core_eh2/env/core_eh2_env.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  本部分边界
--------------

本部分描述 EH2 UVM testbench 的组件拓扑和数据流：TB top、env、agent、cosim
scoreboard、coverage、tests/vseq 和 riscv-dv extension。完整 UVM 类源码字典见
:ref:`appendix_b_uvm/index`；本部分更偏向架构视角和组件之间的连接关系。

§2  TB 与 env 拓扑
------------------

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L7-L17``）：

.. code-block:: systemverilog

   // Architecture:
   //   core_eh2_env
   //     +-- cfg (core_eh2_env_cfg)
   //     +-- vseqr (core_eh2_vseqr)
   //     +-- lsu_agent / ifu_agent / sb_agent (AXI4 agents)
   //     +-- irq_agent (interrupt agent)
   //     +-- jtag_agent (JTAG debug agent)
   //     +-- trace_monitor (instruction commit monitor)
   //     +-- dut_probe_monitor (register writeback monitor)
   //     +-- cosim_scoreboard (co-simulation scoreboard)

逐段解释：

* 第 8~10 行：env 内部先有配置对象和 virtual sequencer。
* 第 11 行：LSU、IFU 和 SB 各自使用 AXI4 agent。
* 第 12~13 行：IRQ 和 JTAG agent 是外部 stimulus 入口。
* 第 14~16 行：trace monitor、DUT probe monitor 和 cosim scoreboard 构成 cosim
  观测/比对主路径。

接口关系：

* 被调用：``core_eh2_tb_top`` 通过 UVM factory 创建 test，再由 test 创建 env。
* 调用：env build/connect phase 中创建各 agent、monitor、scoreboard。
* 共享状态：``core_eh2_env_cfg``、virtual interface、TLM analysis port/FIFO。

§3  架构数据流
--------------

::

   core_eh2_tb_top
      |
      +--> eh2_veer_wrapper DUT
      +--> AXI4 slave memory models
      +--> mailbox detection
      +--> virtual interface config_db
      |
      v
   core_eh2_env
      |
      +--> trace_monitor --------+
      +--> dut_probe_monitor ----+--> cosim_scoreboard --> Spike DPI
      +--> lsu_agent monitor ----+
      |
      +--> irq_agent / jtag_agent / halt_run_agent
      |
      +--> functional coverage bind/interfaces

逐段解释：

* TB top 实例化 DUT、AXI4 memory model 和 mailbox 检测逻辑。mailbox 地址和 PASS/FAIL
  约定来自 :file:`core_eh2_tb_top.sv` 顶部注释。
* env 中 trace/probe/LSU AXI 三路观测进入 cosim scoreboard；这个 3 路 FIFO
  结构是 :ref:`cosim_scoreboard` 的核心。
* IRQ/JTAG/halt-run agent 负责主动 stimulus；AXI4 agent 默认 passive，LSU
  error injection 开启时可设为 active。
* coverage 通过 fcov interface 和 bind 文件采样 DUT/trace/CSR/PMP 相关状态。

§4  章节目录
------------

.. list-table::
   :header-rows: 1
   :widths: 24 76

   * - 小节
     - 内容
   * - :ref:`tb_top`
     - TB 顶层：DUT 实例化、clock/reset、AXI4 memory model、mailbox、config_db。
   * - :ref:`env`
     - UVM env：组件树、build/connect phase、TLM 连接和 cfg。
   * - :ref:`agent_axi4`
     - AXI4 agent：LSU/IFU/SB 端口监视和 error injection 入口。
   * - :ref:`agent_irq`
     - IRQ agent：timer、software、external、NMI stimulus。
   * - :ref:`agent_jtag`
     - JTAG agent：TAP/DMI transaction 和 debug stimulus。
   * - :ref:`agent_halt_run`
     - Halt/Run agent：MPC halt/resume 握手。
   * - :ref:`agent_trace`
     - Trace agent：退休指令采样、trace seq item、DUT probe monitor。
   * - :ref:`agent_cosim`
     - Cosim agent：Spike DPI bridge、binary loader、CSR preregister、scoreboard ownership。
   * - :ref:`cosim_scoreboard`
     - Cosim scoreboard：trace/probe/AXI 三路 FIFO、pending_wb_q、多 hart 和 Spike step。
   * - :ref:`functional_coverage`
     - Functional coverage：coverage bind、covergroup、coverage gate。
   * - :ref:`pmp_coverage`
     - PMP coverage：PMP region/mode/permission/lock 维度。
   * - :ref:`tests_library`
     - Test library：base test、directed test、report server。
   * - :ref:`vseq_library`
     - Virtual sequence：多 agent 激励编排。
   * - :ref:`riscv_dv_extension`
     - riscv-dv extension：core setting、ASM generator、testlist YAML。

§5  Env build/connect 关键连接
------------------------------

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L173``）：

.. code-block:: systemverilog

   // Connect trace monitor to co-simulation agent's scoreboard
   if (cfg.enable_cosim && cosim_agt != null) begin
     trace_monitor.ap.connect(cosim_agt.scoreboard.trace_fifo.analysis_export);
   end
   
   // Connect DUT probe monitor to co-simulation agent's scoreboard
   if (cfg.enable_cosim && cosim_agt != null) begin
     dut_probe_monitor.ap.connect(cosim_agt.scoreboard.dut_probe_fifo.analysis_export);
   end
   
   // Connect LSU AXI4 monitor to co-simulation agent
   if (cfg.enable_cosim && cosim_agt != null) begin
     lsu_agent.ap.connect(cosim_agt.dmem_port);
   end
   
   // Connect trace monitor to double-fault detection scoreboard
   trace_monitor.ap.connect(dfd_scoreboard.trace_fifo.analysis_export);
   
   // Wire sub-sequencers to virtual sequencer
   vseqr.irq_seqr      = irq_agent.sequencer;
   vseqr.jtag_seqr     = jtag_agent.sequencer;
   vseqr.halt_run_seqr = halt_run_agt.sequencer;

逐段解释：

* 第 152~154 行：cosim enabled 时，trace monitor analysis port 接到 cosim
  scoreboard 的 ``trace_fifo``。
* 第 157~159 行：DUT probe monitor 接到 ``dut_probe_fifo``，用于异步写回和内部
  probe hint。
* 第 162~164 行：LSU AXI4 monitor 接到 cosim agent 的 data-memory port，用于
  store/AMO/memory access 通知。
* 第 167 行：trace monitor 同时接到 double-fault detection scoreboard。
* 第 170~172 行：virtual sequencer 保存 IRQ、JTAG 和 halt/run sequencer 句柄。

接口关系：

* 被调用：UVM ``connect_phase``。
* 调用：TLM ``connect`` 和 virtual sequencer handle assignment。
* 共享状态：``cfg.enable_cosim``、``cosim_agt``、analysis FIFO、sub-sequencer handle。

§6  阅读顺序
------------

建议先读 :ref:`tb_top` 和 :ref:`env`，确认 DUT、interface、agent 和 scoreboard
之间的连接；再按问题域选择 agent 章节；最后读 :ref:`cosim_scoreboard`、
:ref:`functional_coverage`、:ref:`tests_library` 和 :ref:`vseq_library`。

如果问题来自脚本或工具：

* 运行命令、testlist、report：:ref:`flows_index` 与 :ref:`scripts_reference`。
* UVM class 逐文件字典：:ref:`appendix_b_uvm/index`。
* Spike DPI C++：:ref:`appendix_c_tools/cosim_cpp`。

§7  参考资料
------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/fcov/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/`

关联章节：

* :ref:`tb_top`
* :ref:`env`
* :ref:`agent_axi4`
* :ref:`agent_irq`
* :ref:`agent_jtag`
* :ref:`agent_halt_run`
* :ref:`agent_trace`
* :ref:`agent_cosim`
* :ref:`cosim_scoreboard`
* :ref:`functional_coverage`
* :ref:`pmp_coverage`
* :ref:`tests_library`
* :ref:`vseq_library`
* :ref:`riscv_dv_extension`

§8  当前实现与 sign-off 事实
-----------------------------

本部分所有验证组件描述以当前 VCS 主线为准。2026-05-19 01:02 demo 已完成 9/9 stage
PASS，实跑覆盖率 102/104 (98.1%)，LEC 31635/31635 PASS；coverage 使用
``-cm line+tgl+assert+fsm+branch``、``cover.cfg`` DUT-only scope 和 URG 原生
dashboard。验证组件层不再把历史 NC/IMC 迁移阶段的数据作为当前结论。

.. list-table:: 组件到 sign-off stage 的映射
   :header-rows: 1
   :widths: 25 25 50

   * - 组件
     - 主要 stage
     - 作用
   * - TB top / env
     - smoke、directed、riscvdv、compliance
     - 提供 DUT、memory、virtual interface 和 UVM 组件树
   * - AXI4 agent
     - directed、riscvdv、cosim
     - 观察 LSU/IFU/SB AXI4，LSU 事务进入 cosim d-side notification
   * - IRQ/JTAG/Halt-Run agent
     - directed、cosim、debug/interrupt tests
     - 主动驱动外部中断、debug scan、halt/run 请求
   * - Trace/probe monitor
     - cosim、riscvdv、formal sidecar
     - 采集退休指令和异步写回 hint
   * - Cosim agent/scoreboard
     - cosim、riscvdv
     - Spike DPI lockstep，比对 PC/GPR/trap/CSR/memory side effect
   * - Functional/PMP coverage
     - signoff coverage gate
     - 产生 GROUP 和微架构/PMP covergroup 数据
   * - Tests/vseq/riscv-dv extension
     - directed、riscvdv
     - 将 YAML/test class/sequence/ASM generator 连接到回归脚本

§9  组件接口契约
----------------

验证组件层最容易出现的问题不是某个类单独失效，而是接口契约被改坏后，错误在更深的
scoreboard 或脚本日志中才暴露。本节把本部分反复出现的契约汇总成一张检查表。修改
TB top、env、agent 或 sequence 时，先按这张表确认字段名、类型和连接方向未漂移。

.. list-table:: 05 章接口契约总表
   :header-rows: 1
   :widths: 24 26 24 26

   * - 契约
     - 发布方
     - 消费方
     - 破坏后的典型症状
   * - ``tb_vif``
     - ``core_eh2_tb_top``
     - base test / loader
     - binary 未加载、mailbox timeout
   * - AXI4 ``vif``
     - ``core_eh2_tb_top``
     - ``lsu/ifu/sb_agent``
     - monitor 静默、cosim 等待 store/AMO
   * - ``irq_vif``
     - ``core_eh2_tb_top``
     - IRQ driver
     - interrupt directed 无 stimulus
   * - ``jtag_vif``
     - ``core_eh2_tb_top``
     - JTAG driver
     - debug directed 停在 DMI/TAP 初始化
   * - ``halt_run_vif``
     - ``core_eh2_tb_top``
     - Halt/Run driver/monitor
     - halt ack/run ack 不出现
   * - ``probe_vif``
     - ``core_eh2_tb_top``
     - trace monitor / cosim scoreboard
     - reset 后 Spike 未重建、interrupt 状态不对
   * - ``fcov_vif``
     - ``core_eh2_tb_top``
     - coverage helper
     - GROUP hole 与实际 stimulus 不一致
   * - ``rvfi_vif``
     - ``core_eh2_tb_top``
     - RVFI smoke / adapter path
     - RVFI smoke test 无有效 retire item
   * - ``trace_fifo``
     - trace monitor
     - cosim scoreboard
     - Spike 未 step 或 pending trace 堆积
   * - ``dut_probe_fifo``
     - DUT probe monitor
     - cosim scoreboard
     - DIV/NB-load ``wb_tag`` 等待超时
   * - ``lsu_axi_fifo``
     - LSU AXI4 monitor
     - cosim scoreboard
     - store/AMO memory notify 缺失

§10  调试入口选择
-----------------

同一个失败可能出现在 UVM log、scoreboard mismatch、mailbox timeout 或 coverage hole
中。为了避免在错误层级上排查，推荐按失败入口选择章节：

.. list-table:: 失败入口到章节的映射
   :header-rows: 1
   :widths: 26 36 38

   * - 现象
     - 先读章节
     - 关键检查
   * - ``uvm_fatal`` 获取不到 interface
     - :ref:`tb_top`、:ref:`env`
     - config_db 字段名、路径匹配、agent active/passive 配置
   * - mailbox timeout
     - :ref:`tb_top`、:ref:`agent_axi4`
     - LSU AW/W handshake、``0xD058_0000`` 写入、程序入口地址
   * - store/AMO cosim hang
     - :ref:`agent_axi4`、:ref:`cosim_scoreboard`
     - write txn 是否 AW+W 后发布、pending memory queue 是否解锁
   * - interrupt mismatch
     - :ref:`agent_irq`、:ref:`agent_trace`、:ref:`cosim_scoreboard`
     - ``mip`` 拼接、NMI 状态、Spike step 前通知顺序
   * - debug/halt mismatch
     - :ref:`agent_jtag`、:ref:`agent_halt_run`、:ref:`agent_cosim`
     - DMI transaction、halt/run ack、debug request 优先级
   * - GROUP coverage hole
     - :ref:`functional_coverage`、:ref:`pmp_coverage`
     - covergroup bins、directed stimulus、riscv-dv constraint
   * - RVFI smoke 失败
     - :ref:`tb_top`、:ref:`agent_trace`
     - RVFI adapter、trace packet、retire valid

§11  与流程章节的边界
---------------------

本部分只解释 UVM 组件如何连接和工作，不把命令行参数、脚本实现和 sign-off 门禁细节
复制到每一页。需要从组件跳到流程时，使用下面的边界：

* 构建、编译、``-cm line+tgl+assert+fsm+branch`` 和 ``cover.cfg`` scope：
  见 :ref:`build_flow`。
* 回归 testlist、并行运行、日志检查和 fail-rate ceiling：见 :ref:`regression_flow`
  与 :ref:`signoff_flow`。
* 脚本参数、``merge_cov.py``、``run_regress.py`` 和 ``run_rtl.py``：
  见 :ref:`scripts_reference`。
* 工具安装、VCS/URG/Spike/Verdi 的使用方式：见 :ref:`appendix_c_tools/index`。

.. note::

   如果组件行为和流程章节描述冲突，以当前源码和 VCS 主线 sign-off 事实为准：
   主线 simulator 是 VCS，覆盖率来自 URG 原生报告；NC 只作为单测波形调试通道。

§12  最小复核命令
-----------------

修改 05 章文档后，至少执行如下文档侧复核。它不替代 RTL 回归，但能证明引用路径、
RST 标记和交叉引用在当前 workspace 中仍可构建。

.. code-block:: bash

   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html
   rg -n '<redline-patterns>' docs/sphinx_cn/source/05_verification_arch
   wc -l docs/sphinx_cn/source/05_verification_arch/*.rst

预期结果：

.. code-block:: text

   build succeeded, 0 warnings.
   # 红线扫描无命中
   # 05_verification_arch 总行数约 1.5 万行以上

§13  维护原则
--------------

05 章后续维护遵循四条原则。第一，组件文档只写当前 VCS 主线事实；历史 NC/IMC 迁移经验
放入 ADR 或已知限制，不作为现状叙述。第二，任何 interface 字段名、TLM FIFO 名称、
plusarg 或 memory region 的描述必须从源码确认后再写。第三，覆盖率数字全书统一使用
2026-05-19 01:02 demo：LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、ASSERT
33.33%、FSM 54.74%、GROUP 69.42%、OVERALL 65.17%。第四，Ibex 对照只比较方法论
和结构，不复制 Ibex 原文，也不把 Ibex 的单核假设套到 EH2 双线程平台上。

§14  与 Ibex 工业实现对照
--------------------------

EH2 验证平台借鉴 Ibex 的目录组织、UVM env/agent 分层、Spike DPI cosim、riscv-dv
目标扩展和 VCS/URG coverage flow，但不会强行复制 Ibex 的 RVFI-centered 数据面。
EH2 的 DUT surface 更大：双线程、双发射、AXI4、PIC、DMI/JTAG、DMA、ICCM/DCCM 和
EH2 custom CSR 都需要额外组件或 sidecar。

关键 Ibex 对照文件：

* :file:`/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_env.sv`
* :file:`/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_cosim_scoreboard.sv`
* :file:`/home/host/ibex/dv/uvm/core_ibex/common/ibex_mem_intf_agent/`
* :file:`/home/host/ibex/dv/uvm/core_ibex/yaml/rtl_simulation.yaml`
* :file:`/home/host/ibex/dv/uvm/core_ibex/cover.cfg`

.. list-table:: 05 章总体对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - Env
     - data/instr memory response、IRQ、cosim、scrambling key、scoreboard
     - AXI4 LSU/IFU/SB、IRQ、JTAG、Halt/Run、trace/probe、cosim、DFD scoreboard
   * - Retire path
     - RVFI monitor item
     - EH2 trace packet + DUT probe hint + RVFI adapter
   * - Memory path
     - Ibex memory interface item
     - AXI4 transaction item，LSU 进入 Spike d-side notification
   * - Coverage
     - VCS/URG DUT-only
     - 同一 VCS/URG 模型，增加 EH2 dual issue/PIC/PMP/custom CSR 采样
   * - Debug
     - Ibex debug state 与 RVFI/cosim 结合
     - JTAG agent + Halt/Run agent + debug CSR/probe
