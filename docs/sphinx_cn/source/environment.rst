:orphan:

UVM Environment
==========================================================================================

``core_eh2_env`` 是平台的 UVM 组合层。它负责创建 agent、scoreboard、
virtual sequencer，并在 connect phase 中完成 analysis port 连接。
测试类只需要配置 ``core_eh2_env_cfg`` 和启动 sequence，不直接连接底层
monitor。

组件树
------------------------------------------------------------------------------------------

当前 env 组件树如下：

.. code-block:: text

   core_eh2_env
   ├── cfg: core_eh2_env_cfg
   ├── vseqr: core_eh2_vseqr
   ├── lsu_agent: axi4_agent#(`RV_LSU_BUS_TAG)  passive
   ├── ifu_agent: axi4_agent#(`RV_IFU_BUS_TAG)  passive
   ├── sb_agent:  axi4_agent#(`RV_SB_BUS_TAG)   passive
   ├── irq_agent: eh2_irq_agent                 active
   ├── jtag_agent: eh2_jtag_agent               active
   ├── halt_run_agt: eh2_halt_run_agent         active
   ├── trace_monitor: eh2_trace_monitor         passive monitor
   ├── dut_probe_monitor: eh2_dut_probe_monitor passive monitor
   ├── cosim_agt: eh2_cosim_agent               enable_cosim 时创建
   └── dfd_scoreboard: core_eh2_scoreboard      double-fault detector

``cosim_agt`` 只有在 ``cfg.enable_cosim`` 为 1 时创建。``+disable_cosim=1``
会在 cfg 构造阶段覆盖该值，从而完全跳过 cosim agent。

env_cfg
------------------------------------------------------------------------------------------

``core_eh2_env_cfg`` 通过 plusarg 管理测试控制面。常用字段如下：

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - 字段 / plusarg
     - 默认
     - 说明
   * - ``enable_cosim`` / ``+enable_cosim``
     - 1
     - 打开 Spike lockstep。
   * - ``disable_cosim`` / ``+disable_cosim``
     - 0
     - 强制关闭 cosim。
   * - ``enable_irq_single_seq``
     - 0
     - 开启单中断序列；``+enable_irq_seq=1`` 是兼容别名。
   * - ``enable_irq_multiple_seq``
     - 0
     - 开启多中断并发场景。
   * - ``enable_irq_nmi_seq``
     - 0
     - 开启 NMI 激励。
   * - ``enable_debug_seq``
     - 0
     - 开启 JTAG debug halt/resume。
   * - ``enable_fetch_toggle``
     - 0
     - 随机切换 fetch enable。
   * - ``enable_mem_error``
     - 0
     - 预留内存错误注入开关。
   * - ``max_cycles``
     - 100000
     - base_test cycle timeout。
   * - ``timeout_ns``
     - 1800000000000
     - wall-clock 级仿真安全超时。
   * - ``bin`` / ``binary``
     - 空
     - 待加载 hex / binary。
   * - ``boot_addr``
     - ``0x8000_0000``
     - binary 加载基地址。

connect phase 数据通路
------------------------------------------------------------------------------------------

env 负责把 monitor 输出接到 scoreboard：

.. code-block:: text

   trace_monitor.ap      ──► cosim_agt.scoreboard.trace_fifo
   dut_probe_monitor.ap  ──► cosim_agt.scoreboard.dut_probe_fifo
   lsu_agent.ap          ──► cosim_agt.dmem_port

   trace_monitor.ap      ──► dfd_scoreboard.trace_fifo

前三条仅在 cosim 打开时连接。最后一条用于 double-fault detection，与
Spike 无关。

Virtual Sequencer
------------------------------------------------------------------------------------------

``core_eh2_vseqr`` 持有子 sequencer 句柄：

* ``irq_seqr`` → ``eh2_irq_agent.sequencer``
* ``jtag_seqr`` → ``eh2_jtag_agent.sequencer``
* ``halt_run_seqr`` → ``eh2_halt_run_agt.sequencer``

``core_eh2_vseq`` 从 cfg 读取开关后，在同一 virtual sequence 中并发启动
IRQ、debug、halt/run、fetch toggle 等激励。这避免每个 test 单独管理
多 agent 调度。

Double-fault Scoreboard
------------------------------------------------------------------------------------------

``core_eh2_scoreboard`` 是 env 级轻量检查器，不等同于 cosim scoreboard。
它订阅 trace item，统计异常 / 中断相关模式，并可通过以下 plusarg 控制：

* ``+enable_double_fault_detector=1``
* ``+double_fault_threshold=<N>``
* ``+double_fault_total_threshold=<N>``
* ``+double_fault_fatal=1``

该检查器用于发现连续异常、异常风暴等平台级症状。指令功能正确性仍由
``eh2_cosim_scoreboard`` 负责。

维护准则
------------------------------------------------------------------------------------------

新增组件时遵循以下边界：

* 需要连接多个 agent 的逻辑放在 env。
* 单个协议的 driver / monitor / sequencer 留在对应 agent 目录。
* 与 Spike 参考模型直接交互的逻辑留在 ``common/cosim_agent`` 。
* 测试策略、开关解析和 sequence 调度优先放在 test / vseq 层。

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
