.. _appendix_b_uvm_index:
.. _appendix_b_uvm/index:

附录 B — UVM 类字典
====================

:status: draft
:source: dv/uvm/core_eh2/eh2_tb.f
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本附录边界
--------------

本附录按 :file:`dv/uvm/core_eh2/eh2_tb.f` 的编译顺序组织 UVM 类字典。
:file:`eh2_tb.f` 只列 TB/UVM 侧文件；RTL 和 shared AXI4 filelist 分别由
:file:`eh2_rtl.f` 与 :file:`eh2_shared.f` 传入，见
:ref:`appendix_a_rtl/index`。

当前 UVM 字典覆盖这些源目录：

* :file:`dv/uvm/core_eh2/tb/`：TB top 与 DUT signal include。
* :file:`dv/uvm/core_eh2/env/`：env、env cfg、scoreboard、vseqr、DUT probe、
  CSR、instruction monitor 和 RVFI interface。
* :file:`dv/uvm/core_eh2/common/*_agent/`：AXI4、IRQ、JTAG、halt/run、trace 和
  cosim agent。
* :file:`dv/uvm/core_eh2/tests/`：base test、test lib、sequence lib、vseq、
  report server 和 RVFI smoke test。
* :file:`dv/uvm/core_eh2/fcov/`：coverage bind、functional coverage interface、
  PMP coverage interface 和 CSR category include。
* :file:`dv/uvm/core_eh2/riscv_dv_extension/`：riscv-dv core setting、directed
  instruction library、program generator override 和 testlist YAML。

§2  TB filelist 编译顺序
------------------------

关键代码（``dv/uvm/core_eh2/eh2_tb.f:L1-L18``）：

.. code-block:: systemverilog

   // Testbench file list for EH2 UVM Verification Platform
   // Includes UVM components and testbench top
   // NOTE: eh2_shared.f and eh2_rtl.f are passed separately by the Makefile
   // Paths are relative to eh2-veri/ project root

   // Bus parameters (must precede agent packages)
   dv/uvm/bus_params_pkg/bus_params_pkg.sv

   // UVM agent packages (include path for package-internal includes)

   // AXI4 agent
   +incdir+dv/uvm/core_eh2/common/axi4_agent
   dv/uvm/core_eh2/common/axi4_agent/axi4_agent_pkg.sv

   // Trace agent (trace interface and monitor only - env interfaces moved to env/)
   +incdir+dv/uvm/core_eh2/common/trace_agent
   dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv
   dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv

逐段解释：

* 第 1~4 行：filelist 说明本文件只覆盖 testbench components 和 testbench top；
  shared RTL 与 RTL filelist 由 Makefile 分开传入。
* 第 7 行：:file:`bus_params_pkg.sv` 必须早于 agent packages，因为注释明确写出
  bus parameters must precede agent packages。
* 第 12~13 行：AXI4 agent package 通过 include path 加载 package 内部 include。
* 第 16~18 行：trace agent 先编译 trace interface，再编译 trace package；注释说明
  env interfaces 已移动到 :file:`env/`。

接口关系：

* 被调用：仿真编译命令使用 :file:`eh2_tb.f`。
* 调用：SystemVerilog compiler、UVM package/include 解析。
* 共享状态：agent package、interface 类型、env package 和 test package 的编译顺序。

§3  UVM 组件拓扑
----------------

::

   core_eh2_tb_top
      |
      +--> DUT + shared AXI4 interfaces
      |
      +--> core_eh2_env
              |
              +--> core_eh2_env_cfg
              +--> core_eh2_scoreboard
              +--> core_eh2_vseqr
              +--> AXI4 agent
              +--> IRQ agent
              +--> JTAG agent
              +--> halt/run agent
              +--> trace agent
              +--> cosim agent
              |
              +--> tests / vseq / fcov / riscv-dv extension

逐段解释：

* :file:`core_eh2_tb_top.sv` 是 top-level module，负责 DUT、interface、clock/reset
  和 UVM config_db 连接，详见 :ref:`appendix_b_uvm_tb`。
* :file:`core_eh2_env.sv` 聚合 agent、scoreboard、vseqr 和配置对象，详见
  :ref:`appendix_b_uvm_env`。
* 各 agent 目录提供 package、interface、seq_item、driver/monitor/sequencer 或
  scoreboard 所需组件；不同 agent 的主动/被动行为在各自章节说明。
* tests、vseq、fcov 和 riscv-dv extension 是 TB 行为的上层入口，分别负责 test
  selection、激励编排、coverage 和随机指令生成扩展。

§4  章节目录
------------

.. list-table::
   :header-rows: 1
   :widths: 24 24 52

   * - 章节
     - 主要源目录
     - 范围
   * - :ref:`appendix_b_uvm_tb`
     - :file:`dv/uvm/core_eh2/tb/`
     - TB top、DUT signal include、virtual interface/config_db 连接
   * - :ref:`appendix_b_uvm_env`
     - :file:`dv/uvm/core_eh2/env/`
     - env、cfg、scoreboard、vseqr、CSR/probe/instr/RVFI interface
   * - :ref:`appendix_b_uvm_axi4_agent`
     - :file:`common/axi4_agent/`
     - AXI4 seq item、driver、monitor、sequencer、agent package
   * - :ref:`appendix_b_uvm_irq_agent`
     - :file:`common/irq_agent/`
     - IRQ interface、seq、seq item、driver、sequencer、agent
   * - :ref:`appendix_b_uvm_jtag_agent`
     - :file:`common/jtag_agent/`
     - JTAG interface、seq item、driver、TAP/DMI sequence、agent
   * - :ref:`appendix_b_uvm_halt_run_agent`
     - :file:`common/halt_run_agent/`
     - halt/run interface、seq item、driver、monitor、agent
   * - :ref:`appendix_b_uvm_trace_agent`
     - :file:`common/trace_agent/`
     - trace interface、trace monitor、DUT probe monitor、trace seq item
   * - :ref:`appendix_b_uvm_cosim_agent`
     - :file:`common/cosim_agent/`
     - cosim cfg、agent、scoreboard、binary loader、CSR preregister include
   * - :ref:`appendix_b_uvm_tests`
     - :file:`dv/uvm/core_eh2/tests/`
     - base test、test lib、integration tests、report server、RVFI smoke
   * - :ref:`appendix_b_uvm_vseq`
     - :file:`dv/uvm/core_eh2/tests/`
     - sequence lib、new sequence lib、vseq 和 virtual sequence 编排
   * - :ref:`appendix_b_uvm_fcov`
     - :file:`dv/uvm/core_eh2/fcov/`
     - functional coverage、PMP coverage、coverage bind、waiver package
   * - :ref:`appendix_b_uvm_riscv_dv_ext`
     - :file:`dv/uvm/core_eh2/riscv_dv_extension/`
     - riscv-dv setting、extension hooks、directed instruction library、testlists

§5  Agent package 顺序
----------------------

关键代码（``dv/uvm/core_eh2/eh2_tb.f:L20-L38``）：

.. code-block:: systemverilog

   // IRQ agent (interrupt stimulus)
   +incdir+dv/uvm/core_eh2/common/irq_agent
   dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv
   dv/uvm/core_eh2/common/irq_agent/eh2_irq_agent_pkg.sv

   // JTAG agent (debug stimulus)
   +incdir+dv/uvm/core_eh2/common/jtag_agent
   dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv
   dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv

   // Co-simulation agent (scoreboard, DPI)
   +incdir+dv/uvm/core_eh2/common/cosim_agent
   +incdir+dv/cosim
   dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv

   // Halt/Run agent (MPC halt/run stimulus)
   +incdir+dv/uvm/core_eh2/common/halt_run_agent
   dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv
   dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_agent_pkg.sv

逐段解释：

* 第 21~23 行：IRQ agent 先加入 include path，再编译 IRQ interface 和 agent
  package。
* 第 26~28 行：JTAG agent 采用同样模式，注释标记它属于 debug stimulus。
* 第 31~33 行：cosim agent 额外加入 :file:`dv/cosim` include path，因为 package
  内部需要 DPI/Cosim 声明。
* 第 36~38 行：halt/run agent 提供 MPC halt/run stimulus 的 interface 和 package。

接口关系：

* 被调用：TB filelist 编译。
* 调用：各 agent package 内部 include 的 class/interface 定义。
* 共享状态：agent interface 类型和 package class 名称必须先于 env/test package 可见。

§6  Env、coverage、test package 顺序
------------------------------------

关键代码（``dv/uvm/core_eh2/eh2_tb.f:L46-L72``）：

.. code-block:: systemverilog

   // Functional coverage
   +incdir+dv/uvm/core_eh2/fcov
   dv/uvm/core_eh2/fcov/eh2_csr_categories.svh
   dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
   dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv
   dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv

   // UVM environment interfaces (DUT probe, CSR, instr monitor — Ibex-style env/ layout)
   +incdir+dv/uvm/core_eh2/env
   dv/uvm/core_eh2/env/eh2_dut_probe_if.sv
   dv/uvm/core_eh2/env/eh2_csr_if.sv
   dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv

   // UVM environment (env_pkg includes cfg, vseqr, scoreboard, env)
   dv/uvm/core_eh2/env/core_eh2_env_pkg.sv

   // UVM test package (includes seq_lib, new_seq_lib, vseq, base_test, test_lib, report_server)
   +incdir+dv/uvm/core_eh2/tests
   dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv

   // RVFI interface (formal verification)
   +incdir+dv/uvm/core_eh2/env
   dv/uvm/core_eh2/env/eh2_rvfi_if.sv

   // UVM testbench top
   +incdir+dv/uvm/core_eh2/tb
   dv/uvm/core_eh2/tb/core_eh2_tb_top.sv

逐段解释：

* 第 47~51 行：coverage include 和 coverage interfaces 在 env package 之前编译。
* 第 54~58 行：DUT probe、CSR 和 instruction monitor interfaces 位于
  :file:`env/`，供 env 和 TB top 连接。
* 第 60 行：``core_eh2_env_pkg.sv`` 汇入 cfg、vseqr、scoreboard 和 env。
* 第 63~64 行：``core_eh2_test_pkg.sv`` 汇入 sequence lib、vseq、base test、test
  lib 和 report server。
* 第 67~68 行：RVFI interface 独立编译，注释标记用途是 formal verification。
* 第 71~72 行：TB top 最后进入 filelist，确保 package、interface 和 test class
  都已经可见。

接口关系：

* 被调用：TB filelist 编译。
* 调用：coverage bind、env package、test package、TB top module。
* 共享状态：coverage interfaces、virtual interfaces、UVM factory 注册和 config_db。

§7  阅读顺序
------------

建议按问题类型进入章节：

* TB 连接或 interface 注入问题：先读 :ref:`appendix_b_uvm_tb`。
* env build/connect/run phase 问题：读 :ref:`appendix_b_uvm_env`。
* AXI4 bus monitor 或 memory model 交互问题：读 :ref:`appendix_b_uvm_axi4_agent`。
* 中断注入问题：读 :ref:`appendix_b_uvm_irq_agent`。
* debug/JTAG/DMI stimulus 问题：读 :ref:`appendix_b_uvm_jtag_agent`。
* MPC halt/run 问题：读 :ref:`appendix_b_uvm_halt_run_agent`。
* trace pkt、wb、probe 问题：读 :ref:`appendix_b_uvm_trace_agent`。
* Spike DPI、cosim scoreboard、CSR preregister 和 binary loader 问题：读
  :ref:`appendix_b_uvm_cosim_agent` 与 :ref:`appendix_c_tools/cosim_cpp`。
* test class、directed tests 和 virtual sequence 问题：读
  :ref:`appendix_b_uvm_tests` 与 :ref:`appendix_b_uvm_vseq`。
* coverage 问题：读 :ref:`appendix_b_uvm_fcov`。
* riscv-dv generator setting、extension hook 或 testlist 问题：读
  :ref:`appendix_b_uvm_riscv_dv_ext`。

§8  参考资料
------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_tb.f`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/fcov/`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/`

关联章节：

* :ref:`appendix_b_uvm_tb`
* :ref:`appendix_b_uvm_env`
* :ref:`appendix_b_uvm_axi4_agent`
* :ref:`appendix_b_uvm_irq_agent`
* :ref:`appendix_b_uvm_jtag_agent`
* :ref:`appendix_b_uvm_halt_run_agent`
* :ref:`appendix_b_uvm_trace_agent`
* :ref:`appendix_b_uvm_cosim_agent`
* :ref:`appendix_b_uvm_tests`
* :ref:`appendix_b_uvm_vseq`
* :ref:`appendix_b_uvm_fcov`
* :ref:`appendix_b_uvm_riscv_dv_ext`

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从真实 UVM 源码中找出本页组件所属 class、interface 或 covergroup。

.. code-block:: bash

   rg -n "class .*extends|uvm_component_utils|uvm_object_utils|phase" dv/uvm/core_eh2 | head -60
   rg -n "interface|analysis_port|scoreboard|covergroup" dv/uvm/core_eh2 | head -60

**进阶题**：检查本页是否把 EH2 和 Ibex 的一致点、差异点分开描述。

.. code-block:: bash

   rg -n "core_ibex|Ibex|与 Ibex" docs/sphinx_cn/source/05_verification_arch docs/sphinx_cn/source/appendix_b_uvm | head -80

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
