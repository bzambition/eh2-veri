.. _env:
.. _05_verification_arch/env:

UVM Environment — 架构参考
==========================

:status: draft
:source: dv/uvm/core_eh2/env/core_eh2_env.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  本章边界
------------

本章解释 ``core_eh2_env`` 如何编排 EH2 UVM 验证环境。逐类源码字典见
:ref:`appendix_b_uvm_env`；这里聚焦 env 在 build/connect phase 中创建哪些组件、哪些
agent 是 active/passive、哪些 analysis port 接到 cosim scoreboard、virtual sequencer
如何拿到子 sequencer，以及 env 配置对象如何从 plusarg 与 test 侧进入运行路径。

本章只描述以下源文件中可以直接回溯的内容：

* :file:`dv/uvm/core_eh2/env/core_eh2_env_pkg.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env_cfg.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_scoreboard.sv`
* :file:`dv/uvm/core_eh2/env/eh2_csr_if.sv`
* :file:`dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv`
* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_base_test.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_vseq.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

当前 ``core_eh2_env.sv`` 没有创建功能覆盖率 collector，也没有把 IFU/SB AXI4 monitor
连接到 cosim agent。功能覆盖率 interface 在 testbench 通过 config DB 分发，但不是本 env
源码中的子组件。

§2  架构数据流
--------------

``core_eh2_env`` 的结构是组件编排层，而不是协议转换层。它创建 AXI4、IRQ、JTAG、
Halt/Run、trace、DUT probe、cosim 和 double-fault scoreboard 等组件，然后在
connect phase 中连接 TLM analysis port。

::

   core_eh2_base_test
      |
      +-- create core_eh2_env
      |      |
      |      +-- cfg created in env constructor
      |      +-- vseqr
      |      +-- lsu_agent / ifu_agent / sb_agent
      |      +-- irq_agent / jtag_agent / halt_run_agt
      |      +-- trace_monitor / dut_probe_monitor
      |      +-- cosim_agt when cfg.enable_cosim
      |      `-- dfd_scoreboard
      |
      `-- start core_eh2_vseq on env.vseqr

   connect_phase:

      trace_monitor.ap      --> cosim_agt.scoreboard.trace_fifo
      dut_probe_monitor.ap  --> cosim_agt.scoreboard.dut_probe_fifo
      lsu_agent.ap          --> cosim_agt.dmem_port --> scoreboard.lsu_axi_fifo
      trace_monitor.ap      --> dfd_scoreboard.trace_fifo
      irq/jtag/halt seqr    --> vseqr sub-sequencer handles

接口关系：

* 被调用：``core_eh2_base_test`` 在 build phase 创建 ``core_eh2_env``。
* 调用：env 在 build/connect phase 调 UVM factory、``uvm_config_db`` 与 analysis
  ``connect``。
* 共享状态：``cfg``、``vseqr``、各 agent 句柄、``trace_monitor``、``dut_probe_monitor``、
  ``cosim_agt``、``dfd_scoreboard``。

§3  ``core_eh2_env_pkg`` 汇入环境依赖
-------------------------------------

职责：env package 汇入所有 agent package，再 include env 自身的 virtual sequencer、配置、
double-fault scoreboard 和 env class。这个 package 是 tests 侧 ``import`` 的统一入口。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_pkg.sv:L7-L24``）：

.. code-block:: systemverilog

   `include "uvm_macros.svh"
   
   package core_eh2_env_pkg;
   
     import uvm_pkg::*;
     import axi4_agent_pkg::*;
     import eh2_trace_agent_pkg::*;
     import eh2_irq_agent_pkg::*;
     import eh2_jtag_agent_pkg::*;
     import eh2_cosim_agent_pkg::*;
     import eh2_halt_run_agent_pkg::*;
   
     `include "core_eh2_vseqr.sv"
     `include "core_eh2_env_cfg.sv"
     `include "core_eh2_scoreboard.sv"
     `include "core_eh2_env.sv"
   
   endpackage

逐段解释：

* 第 7 行：package 外先 include UVM 宏。
* 第 9 行：声明 ``core_eh2_env_pkg``。
* 第 11~17 行：依次导入 UVM、AXI4、trace、IRQ、JTAG、cosim 和 Halt/Run agent package。
  ``core_eh2_env.sv`` 中声明这些类型的成员，因此 package 必须先导入类型定义。
* 第 19~22 行：include env 内部类。顺序上先 include ``core_eh2_vseqr`` 与
  ``core_eh2_env_cfg``，再 include scoreboard 和 env class。
* 第 24 行：结束 package。

接口关系：

* 被调用：``core_eh2_base_test.sv`` 与 ``core_eh2_vseq.sv`` import 该 package。
* 调用：SystemVerilog import/include。
* 共享状态：无运行期状态；它提供类型可见性。

§4  ``core_eh2_env`` 成员边界
-----------------------------

职责：env class 声明配置对象、virtual sequencer、三个 AXI4 agent、三个 active stimulus
agent、trace/probe monitor、cosim agent、double-fault scoreboard，以及两个可选 monitoring
interface 句柄。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L18-L58``）：

.. code-block:: systemverilog

   class core_eh2_env extends uvm_env;
   
     `uvm_component_utils(core_eh2_env)
   
     // Configuration
     core_eh2_env_cfg cfg;
   
     // Virtual sequencer
     core_eh2_vseqr vseqr;
   
     // AXI4 agents (passive - monitor only)
     axi4_agent#(`RV_LSU_BUS_TAG) lsu_agent;
     axi4_agent#(`RV_IFU_BUS_TAG) ifu_agent;
     axi4_agent#(`RV_SB_BUS_TAG) sb_agent;
   
     // Interrupt agent (active - drives interrupts)
     eh2_irq_agent irq_agent;
   
     // JTAG agent (active - drives debug)
     eh2_jtag_agent jtag_agent;

逐段解释：

* 第 18 行：``core_eh2_env`` 继承 ``uvm_env``。
* 第 20 行：注册 UVM factory。
* 第 23 行：``cfg`` 是 env 级配置对象。
* 第 26 行：``vseqr`` 是 virtual sequence 的启动点。
* 第 29~31 行：LSU、IFU、SB 三个 AXI4 agent 分别使用 ``RV_LSU_BUS_TAG``、
  ``RV_IFU_BUS_TAG``、``RV_SB_BUS_TAG`` 参数。
* 第 34~37 行：IRQ 与 JTAG agent 是 active stimulus agent。

接口关系：

* 被调用：UVM factory 创建 env 后访问这些成员。
* 调用：无函数调用。
* 共享状态：env 成员句柄由 build/connect phase 填充。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L39-L58``）：

.. code-block:: systemverilog

     // Halt/Run agent (active - drives halt/run)
     eh2_halt_run_agent halt_run_agt;
   
     // Trace monitor
     eh2_trace_monitor trace_monitor;
   
     // DUT probe monitor
     eh2_dut_probe_monitor dut_probe_monitor;
   
     // Co-simulation agent (owns scoreboard + backdoor loading)
     eh2_cosim_agent cosim_agt;
   
     // Double-fault detection scoreboard
     core_eh2_scoreboard dfd_scoreboard;
   
     // CSR monitoring interface virtual handle
     virtual eh2_csr_if csr_vif;
   
     // Instruction monitoring interface virtual handle
     virtual eh2_instr_monitor_if instr_monitor_vif;

逐段解释：

* 第 40 行：Halt/Run agent 被声明为 env 成员。
* 第 43~46 行：trace monitor 和 DUT probe monitor 是两个独立成员，不存在 top-level
  ``trace_agent`` wrapper。
* 第 49 行：``cosim_agt`` 拥有 cosim scoreboard 和 backdoor loading helper。
* 第 52 行：``dfd_scoreboard`` 是 double-fault detection scoreboard。
* 第 55~58 行：``csr_vif`` 与 ``instr_monitor_vif`` 是可选 virtual interface 句柄；
  env 只从 config DB 获取它们，本源码没有 further connect。

接口关系：

* 被调用：env build/connect phase。
* 调用：无函数调用。
* 共享状态：``cosim_agt`` 可能为 null，取决于 ``cfg.enable_cosim``。

§5  构造函数提前创建 ``cfg``
-----------------------------

职责：env 构造函数在 child build phase 之前创建 ``cfg``，使 test 在 env 创建后可以立即通过
``env.cfg`` 修改配置。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L60-L64``）：

.. code-block:: systemverilog

   function new(string name, uvm_component parent);
     super.new(name, parent);
     // Create cfg in constructor so it's available during child build_phase
     cfg = core_eh2_env_cfg::type_id::create("cfg");
   endfunction

逐段解释：

* 第 60~61 行：构造函数调用 ``super.new``。
* 第 62 行：注释说明 ``cfg`` 在构造函数创建，目的是 child build phase 期间已经可用。
* 第 63 行：通过 UVM factory 创建 ``core_eh2_env_cfg`` 对象，名字为 ``cfg``。
* 第 64 行：结束构造函数。

接口关系：

* 被调用：``core_eh2_env::type_id::create``。
* 调用：``core_eh2_env_cfg::type_id::create``。
* 共享状态：``cfg`` 在 env build phase 前已非空。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L73-L93``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
   
     // Create environment (which creates env_cfg internally)
     env = core_eh2_env::type_id::create("env", this);
   
     // env.cfg is created in env's constructor, so it's available immediately
     env_cfg = env.cfg;
   
     if (!uvm_config_db#(virtual core_eh2_tb_intf)::get(null, "", "tb_vif", tb_vif)) begin
       `uvm_fatal(test_name, "Cannot get tb_vif")
     end
   
     if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(null, "", "halt_run_vif", halt_run_vif)) begin
       `uvm_info(test_name, "halt_run_vif not set; halt/load helper tasks disabled", UVM_LOW)
     end
   
     // Build ISA string
     build_isa_string();

逐段解释：

* 第 73~77 行：base test build phase 创建 ``env``。
* 第 79~80 行：base test 立即把 ``env.cfg`` 赋给 ``env_cfg``，验证了 env constructor 中提前创建
  ``cfg`` 的使用方式。
* 第 82~88 行：base test 另行获取 ``tb_vif`` 与可选 ``halt_run_vif``。
* 第 90~91 行：base test 构造 ISA string；该 string 后续写入 cosim config。

接口关系：

* 被调用：UVM test build phase。
* 调用：``core_eh2_env::type_id::create``、``uvm_config_db::get``、``build_isa_string``。
* 共享状态：``env``、``env_cfg``、``tb_vif``、``halt_run_vif``。

§6  Env build phase 日志与 virtual sequencer
--------------------------------------------

职责：build phase 首先打印配置对象，再创建 ``vseqr``。virtual sequencer 是 virtual sequence
的单一启动 sequencer，实际子 sequencer 在 connect phase 通过句柄填入。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L66-L72``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     `uvm_info("env", cfg.convert2string(), UVM_LOW)
   
     // Virtual sequencer
     vseqr = core_eh2_vseqr::type_id::create("vseqr", this);

逐段解释：

* 第 66~67 行：进入 env build phase 并调用父类 build phase。
* 第 68 行：用 ``cfg.convert2string()`` 打印当前配置。
* 第 70~72 行：创建名为 ``vseqr`` 的 ``core_eh2_vseqr`` 子组件。

接口关系：

* 被调用：UVM build phase。
* 调用：``cfg.convert2string``、``core_eh2_vseqr::type_id::create``。
* 共享状态：``cfg``、``vseqr``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L18``）：

.. code-block:: systemverilog

   class core_eh2_vseqr extends uvm_sequencer;
   
     `uvm_component_utils(core_eh2_vseqr)
   
     // Sub-sequencers (use specific types for type-safe access)
     eh2_irq_sequencer              irq_seqr;
     eh2_jtag_sequencer             jtag_seqr;
     uvm_sequencer #(eh2_halt_run_seq_item) halt_run_seqr;
   
     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

逐段解释：

* 第 7 行：virtual sequencer 继承 ``uvm_sequencer``。
* 第 9 行：注册 UVM factory。
* 第 12~14 行：保存 IRQ、JTAG、Halt/Run 三类子 sequencer 句柄；Halt/Run 使用参数化
  ``uvm_sequencer #(eh2_halt_run_seq_item)``。
* 第 16~18 行：构造函数只调用父类构造函数。

接口关系：

* 被调用：env build phase 创建；virtual sequence 在 ``pre_body`` 中 cast ``m_sequencer``。
* 调用：无运行期任务。
* 共享状态：``irq_seqr``、``jtag_seqr``、``halt_run_seqr`` 在 env connect phase 赋值。

§7  AXI4 agent 创建与 active/passive 策略
-----------------------------------------

职责：env 创建 LSU、IFU、SB 三个 AXI4 agent。LSU agent 在 ``enable_axi4_error_inject`` 为 1
时设为 active，否则 passive；IFU 和 SB 始终设为 passive。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L73-L85``）：

.. code-block:: systemverilog

   // AXI4 agents — active when error injection is enabled, passive otherwise
   lsu_agent = axi4_agent#(`RV_LSU_BUS_TAG)::type_id::create("lsu_agent", this);
   if (cfg.enable_axi4_error_inject) begin
     uvm_config_db#(uvm_active_passive_enum)::set(this, "lsu_agent", "is_active", UVM_ACTIVE);
   end else begin
     uvm_config_db#(uvm_active_passive_enum)::set(this, "lsu_agent", "is_active", UVM_PASSIVE);
   end
   
   ifu_agent = axi4_agent#(`RV_IFU_BUS_TAG)::type_id::create("ifu_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "ifu_agent", "is_active", UVM_PASSIVE);
   
   sb_agent = axi4_agent#(`RV_SB_BUS_TAG)::type_id::create("sb_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "sb_agent", "is_active", UVM_PASSIVE);

逐段解释：

* 第 73~74 行：创建 LSU AXI4 agent。
* 第 75~79 行：``cfg.enable_axi4_error_inject`` 控制 LSU agent active/passive。active 时会创建
  AXI4 driver 和 sequencer，passive 时只监视。
* 第 81~82 行：创建 IFU AXI4 agent，并固定配置为 ``UVM_PASSIVE``。
* 第 84~85 行：创建 SB AXI4 agent，并固定配置为 ``UVM_PASSIVE``。

接口关系：

* 被调用：env build phase。
* 调用：``axi4_agent::type_id::create``、``uvm_config_db::set``。
* 共享状态：``cfg.enable_axi4_error_inject``、``lsu_agent``、``ifu_agent``、``sb_agent``。

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv:L36-L59``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
   
     // Always create monitor
     monitor = axi4_monitor#(ID_WIDTH)::type_id::create("monitor", this);
   
     // Create driver and sequencer only if active
     if (get_is_active() == UVM_ACTIVE) begin
       driver    = axi4_driver#(ID_WIDTH)::type_id::create("driver", this);
       sequencer = axi4_sequencer::type_id::create("sequencer", this);
     end
   endfunction
   
   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
   
     // Connect monitor analysis port
     ap = monitor.ap;
   
     // Connect driver to sequencer (if active)
     if (get_is_active() == UVM_ACTIVE) begin
       driver.seq_item_port.connect(sequencer.seq_item_export);
     end
   endfunction

逐段解释：

* 第 36~40 行：AXI4 agent 无论 active/passive 都创建 monitor。
* 第 42~46 行：只有 active 时创建 driver 和 sequencer。
* 第 49~53 行：agent 的 analysis port 直接引用 monitor 的 ``ap``。
* 第 55~58 行：active 时连接 driver 的 ``seq_item_port`` 和 sequencer 的 ``seq_item_export``。

接口关系：

* 被调用：三个 AXI4 agent 的 build/connect phase。
* 调用：``get_is_active``、factory create、TLM sequencer-driver connect。
* 共享状态：``monitor``、``driver``、``sequencer``、``ap``。

§8  Active stimulus agent 创建
------------------------------

职责：env 创建 IRQ、JTAG、Halt/Run 三个 active agent，并通过 config DB 把每个 agent 的
``is_active`` 设为 ``UVM_ACTIVE``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L87-L97``）：

.. code-block:: systemverilog

   // Interrupt agent (active)
   irq_agent = eh2_irq_agent::type_id::create("irq_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "irq_agent", "is_active", UVM_ACTIVE);
   
   // JTAG agent (active)
   jtag_agent = eh2_jtag_agent::type_id::create("jtag_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "jtag_agent", "is_active", UVM_ACTIVE);
   
   // Halt/Run agent (active)
   halt_run_agt = eh2_halt_run_agent::type_id::create("halt_run_agt", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "halt_run_agt", "is_active", UVM_ACTIVE);

逐段解释：

* 第 88~89 行：创建 IRQ agent，并设置 active。
* 第 92~93 行：创建 JTAG agent，并设置 active。
* 第 96~97 行：创建 Halt/Run agent，并设置 active。
* 这段代码只配置 active/passive；各 agent 的 interface 绑定由 testbench config DB 设置完成。

接口关系：

* 被调用：env build phase。
* 调用：三个 agent 的 factory create 与 ``uvm_config_db::set``。
* 共享状态：``irq_agent``、``jtag_agent``、``halt_run_agt``。

§9  Trace/probe monitor 创建
----------------------------

职责：env 直接创建 ``eh2_trace_monitor`` 与 ``eh2_dut_probe_monitor``。这两者不是 active
agent，也没有 sequencer；它们通过 analysis port 把 ``trace pkt`` 和 probe async event 送往
scoreboard。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L99-L103``）：

.. code-block:: systemverilog

   // Trace monitor
   trace_monitor = eh2_trace_monitor::type_id::create("trace_monitor", this);
   
   // DUT probe monitor
   dut_probe_monitor = eh2_dut_probe_monitor::type_id::create("dut_probe_monitor", this);

逐段解释：

* 第 100 行：创建 ``trace_monitor``。
* 第 103 行：创建 ``dut_probe_monitor``。
* 第 99~103 行：源码没有 ``eh2_trace_agent`` wrapper，env 直接持有两个 monitor。

接口关系：

* 被调用：env build phase。
* 调用：``eh2_trace_monitor::type_id::create``、
  ``eh2_dut_probe_monitor::type_id::create``。
* 共享状态：``trace_monitor`` 与 ``dut_probe_monitor``。

§10  Cosim agent 的条件创建
---------------------------

职责：env 只有在 ``cfg.enable_cosim`` 为 1 时才创建 ``cosim_agt``。创建前，它构造
``eh2_cosim_cfg``，读取 DCCM/ICCM plusarg override，调用 ``sync_mem_regions``，并把配置
对象注入 ``cosim_agt.scoreboard``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L105-L123``）：

.. code-block:: systemverilog

   // Co-simulation agent (only if enabled)
   if (cfg.enable_cosim) begin
     // Create and inject cosim_cfg from config_db so the scoreboard receives
     // memory region mappings (issue 65).  Plusargs MEM_ICCM_BASE,
     // MEM_DCCM_BASE etc. override the defaults set in eh2_cosim_cfg.
     begin
       eh2_cosim_cfg cosim_cfg;
       cosim_cfg = eh2_cosim_cfg::type_id::create("cosim_cfg");
       // Read plusarg overrides for DCCM/ICCM base addresses
       void'($value$plusargs("MEM_ICCM_BASE=%h", cosim_cfg.iccm_base));
       void'($value$plusargs("MEM_ICCM_SIZE=%h", cosim_cfg.iccm_size));
       void'($value$plusargs("MEM_DCCM_BASE=%h", cosim_cfg.dccm_base));
       void'($value$plusargs("MEM_DCCM_SIZE=%h", cosim_cfg.dccm_size));
       // Sync flat fields into struct fields so scoreboard mem_region_t paths work
       cosim_cfg.sync_mem_regions();
       uvm_config_db#(eh2_cosim_cfg)::set(this, "cosim_agt.scoreboard", "cosim_cfg", cosim_cfg);
     end
     cosim_agt = eh2_cosim_agent::type_id::create("cosim_agt", this);
   end

逐段解释：

* 第 105~106 行：只有 ``cfg.enable_cosim`` 为真时进入 cosim 创建路径。
* 第 107~109 行：注释说明 ``eh2_cosim_cfg`` 用于给 scoreboard 提供 memory region mapping，
  并允许 ``MEM_ICCM_*``、``MEM_DCCM_*`` plusarg override。
* 第 111~112 行：创建局部 ``cosim_cfg`` 对象。
* 第 114~117 行：读取 ICCM/DCCM base 和 size 的 plusarg。
* 第 119~120 行：同步 memory region struct，再通过 config DB 把 ``cosim_cfg`` 写到
  ``cosim_agt.scoreboard``。
* 第 122 行：创建 ``cosim_agt``。

接口关系：

* 被调用：env build phase。
* 调用：``$value$plusargs``、``cosim_cfg.sync_mem_regions``、``uvm_config_db::set``、
  ``eh2_cosim_agent::type_id::create``。
* 共享状态：``cfg.enable_cosim``、``cosim_agt``、``cosim_cfg``。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv:L29-L39``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     scoreboard = eh2_cosim_scoreboard::type_id::create("scoreboard", this);
     dmem_port  = new("dmem_port", this);
   endfunction
   
   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
     // Connect external memory port to scoreboard's LSU AXI FIFO
     dmem_port.connect(scoreboard.lsu_axi_fifo.analysis_export);
   endfunction

逐段解释：

* 第 29~33 行：cosim agent build phase 创建 ``eh2_cosim_scoreboard`` 和 external memory
  analysis export ``dmem_port``。
* 第 35~39 行：cosim agent connect phase 把 ``dmem_port`` 连接到 scoreboard 的
  ``lsu_axi_fifo.analysis_export``。

接口关系：

* 被调用：``cosim_agt`` 的 UVM build/connect phase。
* 调用：``eh2_cosim_scoreboard::type_id::create``、analysis export ``connect``。
* 共享状态：``scoreboard``、``dmem_port``、``scoreboard.lsu_axi_fifo``。

§11  Double-fault scoreboard 创建
---------------------------------

职责：env 总是创建 ``dfd_scoreboard``。该 scoreboard 接收 trace monitor item，根据 plusarg
开关决定 run phase 是否启动 exception monitor。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L125-L126``）：

.. code-block:: systemverilog

   // Double-fault detection scoreboard
   dfd_scoreboard = core_eh2_scoreboard::type_id::create("dfd_scoreboard", this);

逐段解释：

* 第 126 行：env 通过 factory 创建 ``core_eh2_scoreboard``，实例名是 ``dfd_scoreboard``。
* 该创建不受 ``cfg.enable_cosim`` 控制。

接口关系：

* 被调用：env build phase。
* 调用：``core_eh2_scoreboard::type_id::create``。
* 共享状态：``dfd_scoreboard``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L34-L50``）：

.. code-block:: systemverilog

   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     trace_fifo = new("trace_fifo", this);
   
     void'($value$plusargs("enable_double_fault_detector=%b", enable_detector));
     void'($value$plusargs("double_fault_threshold=%d", threshold_consecutive));
     void'($value$plusargs("double_fault_total_threshold=%d", threshold_total));
     void'($value$plusargs("double_fault_fatal=%b", fatal_on_threshold));
   endfunction
   
   task run_phase(uvm_phase phase);
     if (enable_detector) begin
       fork
         monitor_exceptions();
       join
     end
   endtask

逐段解释：

* 第 34~36 行：scoreboard build phase 创建 ``trace_fifo``。
* 第 38~41 行：读取 double-fault detector 开关、连续异常阈值、总异常阈值和 fatal/error 策略。
* 第 44~50 行：只有 ``enable_detector`` 为真时才 fork ``monitor_exceptions``。

接口关系：

* 被调用：``dfd_scoreboard`` 的 build/run phase。
* 调用：``$value$plusargs``、``monitor_exceptions``。
* 共享状态：``trace_fifo``、``enable_detector``、``threshold_consecutive``、
  ``threshold_total``、``fatal_on_threshold``。

§12  可选 CSR 与 instruction monitor interface
-----------------------------------------------

职责：env 从 config DB 获取 ``csr_vif`` 和 ``instr_monitor_vif``。源码只打印 optional
缺失信息，没有在 env 内部连接 coverage 或 scoreboard。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L128-L138``）：

.. code-block:: systemverilog

   // CSR monitoring interface
   if (!uvm_config_db#(virtual eh2_csr_if)::get(this, "", "csr_vif", csr_vif))
     `uvm_info("env", "CSR monitoring interface not set (optional)", UVM_LOW)
   
   // Instruction monitoring interface
   if (!uvm_config_db#(virtual eh2_instr_monitor_if)::get(this, "", "instr_monitor_vif", instr_monitor_vif))
     `uvm_info("env", "Instruction monitoring interface not set (optional)", UVM_LOW)
   
   // Configure AXI4 error injection on LSU driver (only when active)
   // NOTE: driver is not yet built here (build_phase is top-down, agent's
   // build_phase runs after env's). Configuration is deferred to connect_phase.

逐段解释：

* 第 128~130 行：env 尝试获取 ``csr_vif``，失败时用 ``UVM_LOW`` 打印 optional 信息。
* 第 132~134 行：env 尝试获取 ``instr_monitor_vif``，失败时同样只打印 optional 信息。
* 第 136~138 行：源码注释说明 AXI4 error injection 配置被推迟到 connect phase，因为 env build
  phase 中 LSU driver 还未构建完成。

接口关系：

* 被调用：env build phase。
* 调用：``uvm_config_db::get``、``uvm_info``。
* 共享状态：``csr_vif``、``instr_monitor_vif``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1137-L1141``）：

.. code-block:: systemverilog

   // Store CSR monitoring interface
   uvm_config_db#(virtual eh2_csr_if)::set(null, "*", "csr_vif", u_csr_if);
   
   // Store instruction monitoring interface
   uvm_config_db#(virtual eh2_instr_monitor_if)::set(null, "*", "instr_monitor_vif", u_instr_monitor_if);

逐段解释：

* 第 1138 行：testbench 把 ``u_csr_if`` 以 ``csr_vif`` 名称写入 config DB。
* 第 1141 行：testbench 把 ``u_instr_monitor_if`` 以 ``instr_monitor_vif`` 名称写入 config DB。
* 这两行解释了 env build phase 中 ``get`` 的来源。

接口关系：

* 被调用：testbench initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：``u_csr_if``、``u_instr_monitor_if``、``csr_vif``、``instr_monitor_vif``。

§13  LSU AXI4 error injection 配置延后到 connect phase
-------------------------------------------------------

职责：LSU AXI4 driver 只有在 agent active 时存在，因此 env 在 connect phase 检查
``cfg.enable_axi4_error_inject`` 和 ``lsu_agent.driver != null``，再写 driver 字段。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L141-L149``）：

.. code-block:: systemverilog

   function void connect_phase(uvm_phase phase);
     super.connect_phase(phase);
   
     // Configure AXI4 error injection on LSU driver (driver is now built)
     if (cfg.enable_axi4_error_inject && lsu_agent.driver != null) begin
       lsu_agent.driver.enable_error_inject = 1;
       lsu_agent.driver.error_pct           = cfg.axi4_error_pct;
       `uvm_info("env", $sformatf("AXI4 error injection enabled on LSU (pct=%0d)", cfg.axi4_error_pct), UVM_LOW)
     end

逐段解释：

* 第 141~142 行：进入 env connect phase。
* 第 144 行：注释说明此时 driver 已经构建完成。
* 第 145 行：同时检查 error injection 开关和 driver 非空，避免 passive agent 中访问空 driver。
* 第 146~147 行：把 driver 的 ``enable_error_inject`` 置 1，并把 ``error_pct`` 设为
  ``cfg.axi4_error_pct``。
* 第 148 行：打印 LSU AXI4 error injection 配置。

接口关系：

* 被调用：UVM connect phase。
* 调用：``uvm_info``。
* 共享状态：``cfg.enable_axi4_error_inject``、``cfg.axi4_error_pct``、``lsu_agent.driver``。

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L64-L85``）：

.. code-block:: systemverilog

   task run_phase(uvm_phase phase);
     // Ensure sideband signals are inactive at start
     vif.error_inject_mode <= 1'b0;
     vif.force_bresp       <= 2'b00;
     vif.force_rresp       <= 2'b00;
   
     if (!enable_error_inject) begin
       // Passive mode - error injection disabled; slave_mem handles everything.
       `uvm_info(agent_name, "Running in PASSIVE mode (no error injection)", UVM_LOW)
       forever begin
         @(posedge vif.clk);
       end
     end else begin
       // Active mode - monitor AXI handshakes, inject errors probabilistically.
       `uvm_info(agent_name, $sformatf(
         "Running in ACTIVE mode: error_pct=%0d%%", error_pct), UVM_LOW)
       fork
         inject_read_errors();
         inject_write_errors();
       join
     end
   endtask

逐段解释：

* 第 64~68 行：driver run phase 初始清零 error injection sideband。
* 第 70~75 行：``enable_error_inject`` 为 0 时只等待时钟，不注入错误。
* 第 76~84 行：``enable_error_inject`` 为 1 时 fork read/write error injection 任务。
* env connect phase 写入的 ``enable_error_inject`` 与 ``error_pct`` 直接决定该分支。

接口关系：

* 被调用：AXI4 driver run phase。
* 调用：``inject_read_errors``、``inject_write_errors``。
* 共享状态：``enable_error_inject``、``error_pct``、``vif.error_inject_mode``、
  ``force_bresp``、``force_rresp``。

§14  Cosim analysis port 连接
-----------------------------

职责：env 在 connect phase 把 trace monitor、DUT probe monitor 和 LSU AXI4 monitor 接到
cosim agent。源码只连接 LSU agent 的 analysis port；IFU/SB agent 在本 env 源码中没有连接到
cosim agent。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L164``）：

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

逐段解释：

* 第 151~154 行：trace monitor analysis port 连接到 cosim scoreboard ``trace_fifo``。
* 第 156~159 行：DUT probe monitor analysis port 连接到 cosim scoreboard ``dut_probe_fifo``。
* 第 161~164 行：LSU AXI4 monitor analysis port 连接到 ``cosim_agt.dmem_port``，再由
  cosim agent 内部连接到 ``scoreboard.lsu_axi_fifo``。
* 三个连接都受 ``cfg.enable_cosim && cosim_agt != null`` 保护。

接口关系：

* 被调用：env connect phase。
* 调用：analysis port/export ``connect``。
* 共享状态：``cfg.enable_cosim``、``cosim_agt``、``trace_monitor.ap``、
  ``dut_probe_monitor.ap``、``lsu_agent.ap``。

§15  Double-fault trace 连接与子 sequencer 注入
-----------------------------------------------

职责：env 不论 cosim 是否启用，都把 trace monitor 接到 double-fault scoreboard。随后它把
IRQ、JTAG、Halt/Run 子 sequencer 句柄写入 virtual sequencer。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L166-L173``）：

.. code-block:: systemverilog

   // Connect trace monitor to double-fault detection scoreboard
   trace_monitor.ap.connect(dfd_scoreboard.trace_fifo.analysis_export);
   
   // Wire sub-sequencers to virtual sequencer
   vseqr.irq_seqr      = irq_agent.sequencer;
   vseqr.jtag_seqr     = jtag_agent.sequencer;
   vseqr.halt_run_seqr = halt_run_agt.sequencer;
   endfunction

逐段解释：

* 第 166~167 行：trace monitor analysis port 连接到 ``dfd_scoreboard.trace_fifo``，不受
  ``cfg.enable_cosim`` 保护。
* 第 169~172 行：env 把 active agent 内部 sequencer 句柄赋给 ``vseqr``，virtual sequence
  后续通过 ``vseqr`` 访问这些子 sequencer。
* 第 173 行：结束 env connect phase。

接口关系：

* 被调用：env connect phase。
* 调用：analysis port/export ``connect``。
* 共享状态：``dfd_scoreboard.trace_fifo``、``vseqr.irq_seqr``、``vseqr.jtag_seqr``、
  ``vseqr.halt_run_seqr``。

§16  ``core_eh2_env_cfg`` 字段分组
----------------------------------

职责：``core_eh2_env_cfg`` 是 env 的中心配置对象，字段按 stimulus、cosim、AXI4 error
injection、memory model、double-fault、timing、completion、ISA 和 binary path 分组。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L27-L45``）：

.. code-block:: systemverilog

   // Interrupt sequences
   bit enable_irq_single_seq     = 0;  // Single interrupt per event
   bit enable_irq_multiple_seq   = 0;  // Multiple simultaneous interrupts
   bit enable_irq_nmi_seq        = 0;  // NMI stimulus
   bit enable_irq_drop_seq       = 0;  // Interrupt deassert sequence
   
   // Debug sequences
   bit enable_debug_seq          = 0;  // Debug halt/resume
   bit enable_debug_stress       = 0;  // Continuous debug requests
   bit enable_debug_single       = 0;  // Single debug pulse
   
   // Fetch enable
   bit enable_fetch_toggle       = 0;  // Random fetch-enable toggling
   
   // =========================================================================
   // Co-simulation control
   // =========================================================================
   bit enable_cosim              = 1;  // Enable co-simulation checking
   bit disable_cosim             = 0;  // Disable co-simulation (override)

逐段解释：

* 第 27~31 行：IRQ stimulus 开关分成 single、multiple、NMI 和 drop。
* 第 33~36 行：debug stimulus 开关分成通用 debug、stress 和 single pulse。
* 第 38~39 行：``enable_fetch_toggle`` 控制 fetch enable toggling。
* 第 41~45 行：cosim 默认启用，``disable_cosim`` 是 override。

接口关系：

* 被调用：env build phase、virtual sequence 和 tests 读取这些字段。
* 调用：无函数调用。
* 共享状态：``cfg`` 字段。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L47-L83``）：

.. code-block:: systemverilog

   // AXI4 error injection control
   // =========================================================================
   bit enable_axi4_error_inject = 0;  // Enable AXI4 SLVERR/DECERR injection
   int axi4_error_pct           = 5;  // Error injection percentage (0-100)
   
   // =========================================================================
   // Memory model control
   // =========================================================================
   bit enable_mem_error          = 0;  // Enable memory error injection
   bit enable_spurious_response  = 0;  // Enable spurious memory responses
   int spurious_response_pct     = 0;  // Spurious response percentage (0-100)
   
   // =========================================================================
   // Double-fault detection
   // =========================================================================
   bit enable_double_fault_detector = 0;
   int double_fault_threshold       = 3;
   
   // =========================================================================
   // Stimulus timing
   // =========================================================================
   int max_interval              = 500;   // Max cycles between stimulus events
   int irq_delay_min             = 100;   // Min delay before first IRQ (ns)
   int irq_delay_max             = 5000;  // Max delay before first IRQ (ns)
   int debug_delay_min           = 1000;  // Min delay before debug request (ns)

逐段解释：

* 第 50~51 行：AXI4 error injection 默认关闭，默认概率为 5。
* 第 56~58 行：memory error 与 spurious response 默认关闭，spurious percentage 默认 0。
* 第 63~64 行：double-fault detector 默认关闭，阈值默认 3。
* 第 69~73 行：stimulus timing 字段定义 maximum interval、IRQ delay range 和 debug delay
  range。

接口关系：

* 被调用：env、virtual sequence、test completion 与 AXI4 driver 配置路径读取这些字段。
* 调用：无函数调用。
* 共享状态：``enable_axi4_error_inject``、``axi4_error_pct``、``enable_mem_error``、
  ``enable_spurious_response``、``enable_double_fault_detector``、``max_interval`` 等。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L75-L95``）：

.. code-block:: systemverilog

   // Test completion
   // =========================================================================
   longint timeout_ns            = 64'd1_800_000_000_000;  // Wall-clock timeout (ns) - 30 minutes
   int max_cycles                = 100_000;     // Cycle count timeout
   bit use_signature             = 1;  // Use signature-based completion
   bit [31:0] signature_addr     = 32'hD058_0000;  // Mailbox/signature address
   bit [31:0] boot_addr          = 32'h8000_0000;  // Boot address
   
   // =========================================================================
   // ISA configuration
   // =========================================================================
   string isa                    = "rv32imac_zba_zbb_zbc_zbs";
   bit [31:0] misa_value         = 32'h40001104;  // RV32IMAC
   
   // =========================================================================
   // Binary paths
   // =========================================================================
   string binary                 = "";
   string cosim_binary           = "";  // Separate binary for cosim model

逐段解释：

* 第 78~82 行：completion 相关字段包括 wall-clock timeout、cycle timeout、signature 开关、
  signature 地址和 boot 地址。
* 第 87~88 行：ISA string 默认是 ``rv32imac_zba_zbb_zbc_zbs``，``misa_value`` 默认
  ``32'h40001104``。
* 第 93~94 行：``binary`` 与 ``cosim_binary`` 保存仿真和 cosim 侧 binary path。

接口关系：

* 被调用：base test completion、cosim config、binary loading 和 tests 读取这些字段。
* 调用：无函数调用。
* 共享状态：``timeout_ns``、``max_cycles``、``signature_addr``、``boot_addr``、``isa``、
  ``binary``、``cosim_binary``。

§17  配置对象读取 plusargs
--------------------------

职责：``core_eh2_env_cfg.new`` 读取所有 env 级 plusarg，并处理 ``disable_cosim`` 和
``enable_irq_single_seq`` 的派生行为。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L96-L127``）：

.. code-block:: systemverilog

   function new(string name = "core_eh2_env_cfg");
     super.new(name);
     // Read all plusargs
     void'($value$plusargs("enable_irq_seq=%0d", enable_irq_single_seq));
     void'($value$plusargs("enable_irq_single_seq=%0d", enable_irq_single_seq));
     void'($value$plusargs("enable_irq_multiple_seq=%0d", enable_irq_multiple_seq));
     void'($value$plusargs("enable_irq_nmi_seq=%0d", enable_irq_nmi_seq));
     void'($value$plusargs("enable_irq_drop_seq=%0d", enable_irq_drop_seq));
     void'($value$plusargs("enable_debug_seq=%0d", enable_debug_seq));
     void'($value$plusargs("enable_debug_stress=%0d", enable_debug_stress));
     void'($value$plusargs("enable_debug_single=%0d", enable_debug_single));
     void'($value$plusargs("enable_fetch_toggle=%0d", enable_fetch_toggle));
     void'($value$plusargs("enable_axi4_error_inject=%0d", enable_axi4_error_inject));
     void'($value$plusargs("axi4_error_pct=%d", axi4_error_pct));
     void'($value$plusargs("enable_cosim=%0d", enable_cosim));
     void'($value$plusargs("disable_cosim=%0d", disable_cosim));
     void'($value$plusargs("enable_mem_error=%0d", enable_mem_error));
     void'($value$plusargs("enable_spurious_response=%0d", enable_spurious_response));
     void'($value$plusargs("spurious_response_pct=%d", spurious_response_pct));
     void'($value$plusargs("enable_double_fault_detector=%0d", enable_double_fault_detector));
     void'($value$plusargs("double_fault_threshold=%d", double_fault_threshold));
     void'($value$plusargs("max_interval=%d", max_interval));
     void'($value$plusargs("timeout_ns=%d", timeout_ns));
     void'($value$plusargs("max_cycles=%d", max_cycles));
     void'($value$plusargs("bin=%s", binary));
     void'($value$plusargs("bin_cosim=%s", cosim_binary));
     void'($value$plusargs("boot_addr=%h", boot_addr));

逐段解释：

* 第 96~98 行：构造函数调用父类构造函数，并开始读取 plusarg。
* 第 99~107 行：读取 IRQ、debug 和 fetch toggle stimulus 开关。
* 第 108~114 行：读取 AXI4 error injection、cosim、memory error、spurious response 相关
  plusarg。
* 第 115~119 行：读取 double-fault、max interval、timeout 和 max cycles。
* 第 120~122 行：读取 ``bin``、``bin_cosim`` 和 ``boot_addr``。
* 第 123~126 行：源码继续读取 IRQ/debug delay range。

接口关系：

* 被调用：env constructor 创建 ``cfg`` 时自动执行。
* 调用：``$value$plusargs``。
* 共享状态：所有 env cfg 字段。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L128-L136``）：

.. code-block:: systemverilog

   // If disable_cosim is set, override enable_cosim
   if (disable_cosim) enable_cosim = 0;
   
   // If enable_irq_seq is set, enable single + drop IRQ sequences
   // (multiple and NMI must be enabled independently)
   if (enable_irq_single_seq) begin
     enable_irq_drop_seq = 1;
   end
   endfunction

逐段解释：

* 第 128~129 行：``disable_cosim`` 为真时强制 ``enable_cosim=0``。
* 第 131~135 行：``enable_irq_single_seq`` 为真时自动打开 ``enable_irq_drop_seq``；multiple
  和 NMI 不在这里自动打开。
* 第 136 行：结束构造函数。

接口关系：

* 被调用：``core_eh2_env_cfg.new`` 内部。
* 调用：无函数调用。
* 共享状态：``disable_cosim``、``enable_cosim``、``enable_irq_single_seq``、
  ``enable_irq_drop_seq``。

§18  配置打印
--------------

职责：``convert2string`` 把主要配置字段格式化成多行字符串。env build phase 用它打印
当前配置。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L138-L154``）：

.. code-block:: systemverilog

   function string convert2string();
     string s;
     s = "EH2 Environment Configuration:\n";
     s = {s, $sformatf("  IRQ sequences: single=%0b multi=%0b nmi=%0b drop=%0b\n",
          enable_irq_single_seq, enable_irq_multiple_seq, enable_irq_nmi_seq, enable_irq_drop_seq)};
     s = {s, $sformatf("  Debug sequences: debug=%0b stress=%0b single=%0b\n",
          enable_debug_seq, enable_debug_stress, enable_debug_single)};
     s = {s, $sformatf("  Fetch toggle=%0b\n", enable_fetch_toggle)};
     s = {s, $sformatf("  Cosim: enable=%0b\n", enable_cosim)};
     s = {s, $sformatf("  Memory: error=%0b spurious=%0b (pct=%0d)\n",
          enable_mem_error, enable_spurious_response, spurious_response_pct)};
     s = {s, $sformatf("  AXI4 error inject=%0b (pct=%0d)\n",
          enable_axi4_error_inject, axi4_error_pct)};
     s = {s, $sformatf("  Timeout: %0d ns / %0d cycles\n", timeout_ns, max_cycles)};
     s = {s, $sformatf("  Binary: %s\n", binary)};
     return s;
   endfunction

逐段解释：

* 第 138~140 行：函数声明本地 string，并写入标题行。
* 第 141~145 行：追加 IRQ、debug 和 fetch toggle 配置。
* 第 146~150 行：追加 cosim、memory 和 AXI4 error injection 配置。
* 第 151~152 行：追加 timeout 与 binary path。
* 第 153~154 行：返回字符串并结束函数。

接口关系：

* 被调用：env build phase ``uvm_info("env", cfg.convert2string(), UVM_LOW)``。
* 调用：``$sformatf``。
* 共享状态：只读 cfg 字段。

§19  Virtual sequence 使用 ``env.vseqr``
----------------------------------------

职责：base test 创建 ``core_eh2_vseq``，把 ``env_cfg`` 传入，然后在 ``env.vseqr`` 上启动。
virtual sequence 再从 ``m_sequencer`` cast 出 ``core_eh2_vseqr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L335-L342``）：

.. code-block:: systemverilog

   // =========================================================================
   // Virtual Sequence
   // =========================================================================
   virtual task start_vseq();
     vseq = core_eh2_vseq::type_id::create("vseq");
     vseq.cfg = env_cfg;
     vseq.start(env.vseqr);
   endtask

逐段解释：

* 第 338~339 行：base test 创建 virtual sequence。
* 第 340 行：把 ``env_cfg`` 句柄写入 ``vseq.cfg``。
* 第 341 行：在 ``env.vseqr`` 上启动 virtual sequence。
* 第 342 行：结束 task。

接口关系：

* 被调用：base test run flow。
* 调用：``core_eh2_vseq::type_id::create``、``vseq.start``。
* 共享状态：``vseq``、``env_cfg``、``env.vseqr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L46-L53``）：

.. code-block:: systemverilog

   virtual task pre_body();
     if (cfg == null) begin
       `uvm_fatal("vseq", "cfg is null - must set before starting vseq")
     end
     if (vseqr == null && !$cast(vseqr, m_sequencer)) begin
       `uvm_fatal("vseq", "m_sequencer is not a core_eh2_vseqr")
     end
   endtask

逐段解释：

* 第 46~49 行：virtual sequence 要求 ``cfg`` 非空，否则报 fatal。
* 第 50~52 行：如果本地 ``vseqr`` 为空，则从 ``m_sequencer`` cast 成 ``core_eh2_vseqr``；
  cast 失败时报 fatal。
* 第 53 行：结束 ``pre_body``。

接口关系：

* 被调用：virtual sequence 启动前。
* 调用：``$cast``、``uvm_fatal``。
* 共享状态：``cfg``、``vseqr``、``m_sequencer``。

§20  Virtual sequence 并行启动 stimulus
---------------------------------------

职责：``core_eh2_vseq.body`` 根据 ``cfg`` 开关并行启动 IRQ、debug 和 fetch enable sequence。
这些 stimulus 是否运行由 env cfg 决定，而不是由 env connect phase 动态判断。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L55-L83``）：

.. code-block:: systemverilog

   virtual task body();
     `uvm_info("vseq", "Starting virtual sequence", UVM_LOW)
   
     fork
       // IRQ sequences
       begin
         if (cfg.enable_irq_single_seq) begin
           irq_single_h = irq_raise_single_seq::type_id::create("irq_single_h");
           irq_single_h.irq_vif = get_irq_vif();
           irq_single_h.interval = cfg.max_interval;
           irq_single_h.start(null);
         end
       end
   
       begin
         if (cfg.enable_irq_multiple_seq) begin
           irq_multi_h = irq_raise_seq::type_id::create("irq_multi_h");
           irq_multi_h.irq_vif = get_irq_vif();
           irq_multi_h.interval = cfg.max_interval;
           irq_multi_h.start(null);
         end
       end
   
       begin
         if (cfg.enable_irq_nmi_seq) begin
           irq_nmi_h = irq_raise_nmi_seq::type_id::create("irq_nmi_h");
           irq_nmi_h.irq_vif = get_irq_vif();
           irq_nmi_h.interval = cfg.max_interval;
           irq_nmi_h.start(null);

逐段解释：

* 第 55~58 行：body 打印启动日志并进入 ``fork``。
* 第 60~66 行：``enable_irq_single_seq`` 为真时创建 ``irq_raise_single_seq``，注入
  ``irq_vif`` 和 ``max_interval``，然后直接 ``start(null)``。
* 第 69~75 行：``enable_irq_multiple_seq`` 为真时创建并启动 ``irq_raise_seq``。
* 第 78~83 行：``enable_irq_nmi_seq`` 为真时创建并启动 ``irq_raise_nmi_seq``。

接口关系：

* 被调用：``vseq.start(env.vseqr)``。
* 调用：IRQ sequence factory create、``get_irq_vif``、``start``。
* 共享状态：``cfg``、``irq_single_h``、``irq_multi_h``、``irq_nmi_h``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L87-L117``）：

.. code-block:: systemverilog

       // Debug sequences
       begin
         if (cfg.enable_debug_seq || cfg.enable_debug_stress) begin
           debug_stress_h = debug_seq::type_id::create("debug_stress_h");
           debug_stress_h.jtag_seqr = vseqr.jtag_seqr;
           debug_stress_h.stress_mode = cfg.enable_debug_stress;
           debug_stress_h.interval = cfg.max_interval;
           debug_stress_h.start(null);
         end
       end
   
       begin
         if (cfg.enable_debug_single) begin
           debug_single_h = debug_seq::type_id::create("debug_single_h");
           debug_single_h.jtag_seqr = vseqr.jtag_seqr;
           debug_single_h.stress_mode = 0;
           debug_single_h.interval = cfg.max_interval;
           debug_single_h.start(null);
         end
       end
   
       // Fetch-enable sequence
       begin
         if (cfg.enable_fetch_toggle) begin
           fetch_en_h = fetch_enable_seq::type_id::create("fetch_en_h");
           fetch_en_h.interval = cfg.max_interval;
           fetch_en_h.start(null);
         end
       end
     join_none
   endtask

逐段解释：

* 第 87~95 行：``enable_debug_seq`` 或 ``enable_debug_stress`` 为真时创建 debug sequence，
  写入 ``vseqr.jtag_seqr``、stress mode 和 interval，然后启动。
* 第 98~105 行：``enable_debug_single`` 为真时创建第二个 debug sequence，stress mode 固定为
  0。
* 第 108~114 行：``enable_fetch_toggle`` 为真时创建 fetch enable sequence 并启动。
* 第 116~117 行：``join_none`` 表示这些 stimulus sequence 后台运行，body 不等待它们结束。

接口关系：

* 被调用：virtual sequence body。
* 调用：``debug_seq::type_id::create``、``fetch_enable_seq::type_id::create``、``start``。
* 共享状态：``vseqr.jtag_seqr``、``cfg.enable_debug_*``、``cfg.enable_fetch_toggle``、
  ``cfg.max_interval``。

§21  Base test 设置 cosim config 与 pending binary
--------------------------------------------------

职责：base test 在 end-of-elaboration phase 根据 env cfg 写 cosim scoreboard 的
``cosim_config``，并把 binary path 延迟到 cosim 初始化阶段加载。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L99-L124``）：

.. code-block:: systemverilog

   function void end_of_elaboration_phase(uvm_phase phase);
     super.end_of_elaboration_phase(phase);
   
     // Populate cosim_config string from env_cfg
     // Format: "isa=<ISA>;pc=<PC>;mtvec=<MTVEC>;"
     if (env_cfg.enable_cosim && env.cosim_agt.scoreboard != null) begin
       string cosim_cfg_str;
       cosim_cfg_str = $sformatf("isa=%s;pc=0x%08x;mtvec=0x%08x;pmp_regions=%0d;pmp_granularity=%0d;mhpm_counters=%0d",
         isa_string,
         env_cfg.boot_addr,
         env_cfg.boot_addr & 32'hFFFFFF00,  // mtvec: 256-byte aligned, MODE=0 (direct)
         0,             // pmp_num_regions
         0,             // pmp_granularity
         0              // mhpm_counter_num
       );
       env.cosim_agt.scoreboard.cosim_config = cosim_cfg_str;
       `uvm_info(test_name, $sformatf("Cosim config: %s", cosim_cfg_str), UVM_LOW)

逐段解释：

* 第 99~104 行：end-of-elaboration phase 中，只有 cosim enable 且 scoreboard 非空时才写
  cosim config。
* 第 105~113 行：``cosim_cfg_str`` 包含 ISA、PC、mtvec、PMP regions、PMP granularity 和
  MHPM counters。``mtvec`` 来自 ``boot_addr & 32'hFFFFFF00``。
* 第 114~115 行：把字符串写入 ``env.cosim_agt.scoreboard.cosim_config`` 并打印日志。

接口关系：

* 被调用：UVM end-of-elaboration phase。
* 调用：``$sformatf``、``uvm_info``。
* 共享状态：``env_cfg.enable_cosim``、``env.cosim_agt.scoreboard.cosim_config``、
  ``isa_string``、``env_cfg.boot_addr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L118-L124``）：

.. code-block:: systemverilog

   // Set pending binary path for cosim (loaded during init_cosim, avoids race)
   if (env_cfg.enable_cosim && env.cosim_agt.scoreboard != null && env_cfg.binary != "") begin
     env.cosim_agt.scoreboard.pending_bin_path  = env_cfg.binary;
     env.cosim_agt.scoreboard.pending_base_addr = env_cfg.boot_addr;
     `uvm_info(test_name, $sformatf("Deferred cosim binary load: %s at 0x%08x",
       env_cfg.binary, env_cfg.boot_addr), UVM_LOW)
   end

逐段解释：

* 第 118~119 行：只有 cosim enable、scoreboard 非空且 ``env_cfg.binary`` 非空时设置 pending
  binary。
* 第 120~121 行：把 binary path 和 base address 写到 scoreboard 的 pending fields。
* 第 122~123 行：打印 deferred cosim binary load 日志。
* 第 124 行：结束条件分支。

接口关系：

* 被调用：base test end-of-elaboration phase。
* 调用：``uvm_info``。
* 共享状态：``env_cfg.binary``、``env_cfg.boot_addr``、
  ``scoreboard.pending_bin_path``、``scoreboard.pending_base_addr``。

§22  Test completion 与 env 状态读取
------------------------------------

职责：base test completion 逻辑同时等待 signature、wall-clock timeout、cycle timeout 和
double-fault detector。double-fault helper 直接读取 ``env.trace_monitor.exception_count``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L347-L378``）：

.. code-block:: systemverilog

   virtual task wait_for_completion(uvm_phase phase);
     fork
       // Way 1: Signature-based completion (mailbox write)
       begin
         if (env_cfg.use_signature)
           wait_for_signature();
         else
           wait (0);  // Block forever if disabled
       end
   
       // Way 2: Wall-clock timeout
       begin
         #(env_cfg.timeout_ns);
         `uvm_error(test_name, $sformatf("Wall-clock timeout: %0d ns", env_cfg.timeout_ns))
       end
   
       // Way 3: Cycle count timeout
       begin
         tb_vif.wait_clks(env_cfg.max_cycles);
         `uvm_error(test_name, $sformatf("Cycle timeout: %0d cycles", env_cfg.max_cycles))

逐段解释：

* 第 347~355 行：第一条 completion 路径在 ``use_signature`` 为真时等待 mailbox signature。
* 第 357~361 行：第二条路径等待 ``timeout_ns``，超时后报 ``uvm_error``。
* 第 363~367 行：第三条路径调用 ``tb_vif.wait_clks(max_cycles)``，超时后报 ``uvm_error``。
* 第 369 行之后的源码继续处理 double-fault detector。

接口关系：

* 被调用：base test run flow。
* 调用：``wait_for_signature``、``tb_vif.wait_clks``、``uvm_error``。
* 共享状态：``env_cfg.use_signature``、``env_cfg.timeout_ns``、``env_cfg.max_cycles``、
  ``tb_vif``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L369-L414``）：

.. code-block:: systemverilog

       // Way 4: Double-fault detector
       begin
         if (env_cfg.enable_double_fault_detector)
           detect_double_fault();
         else
           wait (0);  // Block forever if disabled
       end
     join_any
     disable fork;
   endtask
   
   // Signature-based completion: watch for writes to SIGNATURE_ADDR
   // Polls mailbox_test_done flag instead of using events (avoids triggered-state issues)
   virtual task wait_for_signature();

逐段解释：

* 第 369~375 行：第四条 completion 路径在 ``enable_double_fault_detector`` 为真时调用
  ``detect_double_fault``，否则永久阻塞。
* 第 376~377 行：任一 completion 路径返回后 ``join_any`` 结束，并 ``disable fork`` 关闭其它路径。
* 第 380~382 行：源码随后定义 signature completion helper，通过轮询 mailbox 状态而不是事件触发。

接口关系：

* 被调用：``wait_for_completion``。
* 调用：``detect_double_fault``、``disable fork``。
* 共享状态：``env_cfg.enable_double_fault_detector``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L401-L414``）：

.. code-block:: systemverilog

   // Double-fault detection
   virtual task detect_double_fault();
     int fault_count = 0;
     forever begin
       #1000ns;
       // Monitor for consecutive exceptions via trace
       // Simplified: count exceptions and trigger if threshold exceeded
       if (env.trace_monitor != null && env.trace_monitor.exception_count > env_cfg.double_fault_threshold) begin
         `uvm_error(test_name, $sformatf("Double-fault detected: %0d exceptions",
           env.trace_monitor.exception_count))
         return;
       end
     end
   endtask

逐段解释：

* 第 402~405 行：helper 每 1000 ns 轮询一次。
* 第 406~408 行：注释说明该 helper 通过 trace exception count 监视异常；条件要求
  ``env.trace_monitor`` 非空，且 ``exception_count`` 大于 env cfg 阈值。
* 第 409~410 行：命中阈值时报 ``uvm_error``，消息包含当前 exception count。
* 第 411~414 行：返回并结束 task。

接口关系：

* 被调用：completion fork 的 double-fault 分支。
* 调用：``uvm_error``。
* 共享状态：``env.trace_monitor.exception_count``、``env_cfg.double_fault_threshold``。

§23  Double-fault scoreboard 行为
---------------------------------

职责：``core_eh2_scoreboard`` 从 ``trace_fifo`` 读取 trace item，统计连续异常、总异常和退休数。
达到连续阈值或总阈值时，根据 ``fatal_on_threshold`` 报 fatal 或 error。

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L52-L79``）：

.. code-block:: systemverilog

   // Monitor trace items for exception patterns
   task monitor_exceptions();
     eh2_trace_seq_item item;
   
     forever begin
       trace_fifo.get(item);
       if (item == null) continue;
   
       total_retirements++;
   
       if (item.exception) begin
         notify_exception();
       end else begin
         notify_retirement();
       end
   
       // Check consecutive threshold
       if (consecutive_exceptions >= threshold_consecutive) begin
         if (fatal_on_threshold) begin
           `uvm_fatal("scoreboard", $sformatf(
             "Double-fault detected: %0d consecutive exceptions (threshold: %0d)",
             consecutive_exceptions, threshold_consecutive))

逐段解释：

* 第 53~57 行：monitor task 阻塞读取 ``trace_fifo``。
* 第 58 行：空 item 被跳过。
* 第 60 行：每个非空 item 递增 ``total_retirements``。
* 第 62~66 行：exception item 调 ``notify_exception``，非 exception item 调
  ``notify_retirement``。
* 第 68~73 行：连续异常数达到阈值时，如果 ``fatal_on_threshold`` 为真，报 ``uvm_fatal``。
* 第 74~79 行：否则报 ``uvm_error``。

接口关系：

* 被调用：``run_phase`` 在 ``enable_detector`` 为真时 fork。
* 调用：``trace_fifo.get``、``notify_exception``、``notify_retirement``、``uvm_fatal``、
  ``uvm_error``。
* 共享状态：``consecutive_exceptions``、``total_retirements``、``threshold_consecutive``、
  ``fatal_on_threshold``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L81-L107``）：

.. code-block:: systemverilog

       // Check total threshold
       if (total_exceptions >= threshold_total) begin
         if (fatal_on_threshold) begin
           `uvm_fatal("scoreboard", $sformatf(
             "Total exception threshold exceeded: %0d (threshold: %0d)",
             total_exceptions, threshold_total))
         end else begin
           `uvm_error("scoreboard", $sformatf(
             "Total exception threshold exceeded: %0d (threshold: %0d)",
             total_exceptions, threshold_total))
         end
       end
     end
   endtask
   
   // Called when an exception is observed
   function void notify_exception();
     consecutive_exceptions++;
     total_exceptions++;
     if (consecutive_exceptions > max_consecutive_exceptions)
       max_consecutive_exceptions = consecutive_exceptions;
   endfunction
   
   // Called when a successful retirement is observed
   function void notify_retirement();
     consecutive_exceptions = 0;
   endfunction

逐段解释：

* 第 81~91 行：总异常数达到 ``threshold_total`` 时，同样根据 ``fatal_on_threshold`` 报 fatal
  或 error。
* 第 96~102 行：``notify_exception`` 同时递增连续异常和总异常，并更新最大连续异常记录。
* 第 104~107 行：``notify_retirement`` 把连续异常数清零。

接口关系：

* 被调用：``monitor_exceptions``。
* 调用：``uvm_fatal``、``uvm_error``。
* 共享状态：``total_exceptions``、``threshold_total``、``max_consecutive_exceptions``、
  ``consecutive_exceptions``。

§24  CSR 与 instruction monitor interface 字段
----------------------------------------------

职责：``eh2_csr_if`` 与 ``eh2_instr_monitor_if`` 是 env 可选获取的 monitoring interface。它们
定义信号和 clocking block；env 本身只保存 virtual handle。

关键代码（``dv/uvm/core_eh2/env/eh2_csr_if.sv:L16-L43``）：

.. code-block:: systemverilog

   interface eh2_csr_if(
     input logic clk,
     input logic rst_n
   );
   
     // CSR access signals (from decode stage)
     logic        csr_access;      // Any CSR operation (read/write/set/clear)
     logic [11:0] csr_addr;        // CSR address (12-bit)
     logic [31:0] csr_wdata;       // CSR write data (at writeback)
     logic [31:0] csr_rdata;       // CSR read data (at decode)
     logic        csr_wen;         // CSR write enable (at writeback)
     logic        csr_read;        // CSR read operation
     logic        csr_write;       // CSR write operation
     logic        csr_set;         // CSR set operation
     logic        csr_clr;         // CSR clear operation
   
     // Monitor clocking block
     clocking monitor_cb @(posedge clk);
       input csr_access;
       input csr_addr;
       input csr_wdata;
       input csr_rdata;
       input csr_wen;

逐段解释：

* 第 16~19 行：CSR interface 接收 ``clk`` 与 ``rst_n``。
* 第 22~30 行：定义 CSR access、address、write data、read data、write enable 和 read/write/set/clear
  操作分类信号。
* 第 32~43 行：clocking block 在 ``posedge clk`` 采样这些 CSR 信号。

接口关系：

* 被调用：testbench 实例化并通过 config DB 设置；env 可选获取。
* 调用：无任务或函数。
* 共享状态：``csr_vif`` 句柄。

关键代码（``dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv:L17-L40``）：

.. code-block:: systemverilog

   interface eh2_instr_monitor_if(
     input logic clk,
     input logic rst_n
   );
   
     // I0 (slot 0) decode stage signals
     logic        i0_valid;           // I0 valid at decode
     logic [31:0] i0_instr;           // I0 instruction word
     logic        i0_compressed;      // I0 is 16-bit compressed
     logic [15:0] i0_instr_compressed; // I0 compressed instruction bits
     logic        i0_branch_taken;    // I0 branch was taken
     logic        i0_stall;           // I0 stage stalled
   
     // I1 (slot 1) decode stage signals
     logic        i1_valid;           // I1 valid at decode
     logic [31:0] i1_instr;           // I1 instruction word
     logic        i1_compressed;      // I1 is 16-bit compressed
     logic [15:0] i1_instr_compressed; // I1 compressed instruction bits
     logic        i1_branch_taken;    // I1 branch was taken
     logic        i1_stall;           // I1 stage stalled
   
     // Pipeline control
     logic        pipe_flush;         // Pipeline flush
     logic        dual_issue;         // Dual-issue active

逐段解释：

* 第 17~20 行：instruction monitor interface 接收 ``clk`` 与 ``rst_n``。
* 第 23~28 行：定义 i0 decode stage valid、instruction、compressed 标志、compressed bits、
  branch taken 和 stall。
* 第 31~36 行：定义 i1 对应信号。
* 第 39~40 行：定义 ``pipe_flush`` 与 ``dual_issue`` pipeline control 信号。

接口关系：

* 被调用：testbench 实例化并通过 config DB 设置；env 可选获取。
* 调用：无任务或函数。
* 共享状态：``instr_monitor_vif`` 句柄。

§25  参考资料
--------------

* :ref:`appendix_b_uvm_env` — Env 源码字典。
* :ref:`agent_axi4` — AXI4 passive/active agent 架构说明。
* :ref:`agent_trace` — trace/probe monitor 架构说明。
* :ref:`agent_cosim` — cosim scoreboard 和 Spike 通知路径。
* :ref:`agent_irq` — IRQ active stimulus 路径。
* :ref:`agent_jtag` — JTAG debug stimulus 路径。
* :ref:`agent_halt_run` — Halt/Run stimulus 路径。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_pkg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_cfg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_scoreboard.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_csr_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_vseq.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。

§26  与 Ibex 工业实现对照
-------------------------

Ibex 的 ``core_ibex_env`` 创建 data/instr memory response agent、IRQ agent、cosim
agent、scrambling key agent、virtual sequencer 和 scoreboard。EH2 的
``core_eh2_env`` 保留同样的 UVM env 分层，但根据 EH2 DUT surface 扩展为三组 AXI4
agent、IRQ、JTAG、Halt/Run、trace monitor、DUT probe monitor、cosim agent 和
double-fault detection scoreboard。两者都在 ``connect_phase`` 中把 monitor analysis
port 接到 cosim 或 scoreboard，并把子 sequencer 句柄保存到 virtual sequencer。

.. list-table:: Env 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex ``core_ibex_env``
     - EH2 ``core_eh2_env``
   * - memory agent
     - data/instr memory response agent
     - LSU/IFU/SB AXI4 agent
   * - interrupt/debug
     - IRQ agent + RVFI/debug 状态
     - IRQ + JTAG + Halt/Run 三类 active stimulus
   * - cosim
     - ``ibex_cosim_agent`` 与 RVFI/dmem/imem FIFO
     - ``eh2_cosim_agent`` 与 trace/probe/LSU AXI FIFO
   * - scoreboard
     - core scoreboard 用于 double fault 等检查
     - ``core_eh2_scoreboard`` 接 trace FIFO 做 DFD 检测
   * - sequencer
     - data/instr/irq 子 sequencer
     - irq/jtag/halt-run 子 sequencer

关键 Ibex 对照代码位于：

* :file:`/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_env.sv`
* :file:`/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_vseqr.sv`
* :file:`/home/host/ibex/dv/uvm/core_ibex/common/ibex_cosim_agent/ibex_cosim_scoreboard.sv`

§27  Sign-off 关联
------------------

Env 是 05 章所有组件的连接中心。2026-05-19 demo 的 9/9 stage PASS 依赖 env
build/connect phase 正确完成：若 AXI4 monitor 没有接到 cosim dmem port，store/AMO
cosim 会失真；若 trace/probe 没有接到 scoreboard，PC/GPR/CSR 比对会失效；若 IRQ/JTAG
sequencer 没有进入 vseqr，directed stimulus 会静默缺失。修改 env 后至少需要跑
``make smoke``、``make regress TESTLIST=directed`` 和一组 cosim/riscv-dv smoke。
