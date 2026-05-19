.. _appendix_b_uvm_env:
.. _appendix_b_uvm/env:

UVM Environment 源码字典
========================

:status: draft
:source: dv/uvm/core_eh2/env/core_eh2_env.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/env/` 下的 UVM environment 代码。``core_eh2_env`` 是组件编排
中心：它创建 AXI4 agent、IRQ/JTAG/Halt-Run active agent、trace monitor、DUT probe monitor、
cosim agent 和 double-fault scoreboard，并在 connect phase 连接 analysis port 与 virtual
sequencer 句柄。当前源码没有在 env 中创建 functional coverage collector；coverage 相关 virtual
interface 由 tb 顶层注入 config_db，fcov 章节另行说明。

本章覆盖 9 个 env 源文件和 tb 顶层 config_db 注入片段：

* :file:`dv/uvm/core_eh2/env/core_eh2_env_pkg.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env_cfg.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_scoreboard.sv`
* :file:`dv/uvm/core_eh2/env/eh2_csr_if.sv`
* :file:`dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv`
* :file:`dv/uvm/core_eh2/env/eh2_dut_probe_if.sv`
* :file:`dv/uvm/core_eh2/env/eh2_rvfi_if.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``core_eh2_env`` 的主体连接可以分成 4 类：active stimulus agent、passive monitor、cosim
scoreboard 和 double-fault scoreboard。trace monitor 是两个 scoreboard 的共同输入；DUT
probe monitor 只接 cosim scoreboard 的 async writeback FIFO；LSU AXI4 monitor 只在 cosim
开启时接 ``cosim_agt.dmem_port``。

::

   core_eh2_env
      |
      +-- vseqr
      |     +-- irq_seqr      <- irq_agent.sequencer
      |     +-- jtag_seqr     <- jtag_agent.sequencer
      |     +-- halt_run_seqr <- halt_run_agt.sequencer
      |
      +-- trace_monitor.ap ----------+--> cosim_agt.scoreboard.trace_fifo
      |                              |
      |                              +--> dfd_scoreboard.trace_fifo
      |
      +-- dut_probe_monitor.ap ----------> cosim_agt.scoreboard.dut_probe_fifo
      |
      +-- lsu_agent.ap ------------------> cosim_agt.dmem_port

接口关系：

* 被调用：``core_eh2_base_test`` 创建 env 并通过 env 暴露 agent/sequencer 句柄。
* 调用：UVM factory、``uvm_config_db``、analysis port ``connect``。
* 共享状态：``core_eh2_env_cfg``、``vseqr``、agent component 句柄、scoreboard FIFO。

§2  ``core_eh2_env_pkg.sv`` — package 依赖顺序
------------------------------------------------------------------------------------------------------------------------

职责：env package 汇入所有 agent package，并 include env 自身的 vseqr、cfg、scoreboard 和
env class。

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

* 第 7 行：在 package 外 include UVM macros。
* 第 9~17 行：package import UVM、AXI4、trace、IRQ、JTAG、cosim 和 halt/run agent package。
* 第 19~22 行：按 env 内部依赖 include vseqr、cfg、scoreboard 和 env class。
* 第 24 行：结束 package。

接口关系：

* 被调用：test package 和 tb filelist 编译 env package。
* 调用：SystemVerilog import/include。
* 共享状态：无运行期共享状态。

§3  ``core_eh2_env_cfg.sv`` — plusarg 配置对象
------------------------------------------------------------------------------------------------------------------------

职责：``core_eh2_env_cfg`` 是 env 的配置对象。constructor 读取 plusargs，``convert2string``
把关键配置打印到 UVM log。

§3.1  stimulus 与 cosim knobs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L19-L46``）：

.. code-block:: systemverilog

   class core_eh2_env_cfg extends uvm_object;

     `uvm_object_utils(core_eh2_env_cfg)

     // =========================================================================
     // Stimulus control knobs
     // =========================================================================

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

* 第 19~21 行：config class 继承 ``uvm_object`` 并注册 factory。
* 第 27~31 行：IRQ sequence knobs 包括 single、multiple、NMI 和 drop。
* 第 34~36 行：debug sequence knobs 包括 debug、stress 和 single。
* 第 39 行：fetch toggle knob 控制随机 fetch-enable toggling。
* 第 44~45 行：cosim 默认开启，``disable_cosim`` 作为 override。

接口关系：

* 被调用：``core_eh2_env.new`` 创建 cfg；virtual sequence/test 读取 cfg 字段。
* 调用：UVM object macro。
* 共享状态：env 配置字段。

§3.2  error injection、timeout、ISA 和 binary 字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L47-L95``）：

.. code-block:: systemverilog

     // =========================================================================
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

逐段解释：

* 第 50~51 行：AXI4 error injection 包括 enable bit 和 error percentage。
* 第 56~58 行：memory model control 包括 memory error、spurious response 和 percentage。
* 第 63~64 行：double-fault detector 配置包括 enable bit 和 consecutive threshold。

接口关系：

* 被调用：env build/connect phase 读取 ``enable_axi4_error_inject``；scoreboard 独立读取
  double-fault plusargs。
* 调用：无。
* 共享状态：cfg 字段。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L66-L95``）：

.. code-block:: systemverilog

     // =========================================================================
     // Stimulus timing
     // =========================================================================
     int max_interval              = 500;   // Max cycles between stimulus events
     int irq_delay_min             = 100;   // Min delay before first IRQ (ns)
     int irq_delay_max             = 5000;  // Max delay before first IRQ (ns)
     int debug_delay_min           = 1000;  // Min delay before debug request (ns)
     int debug_delay_max           = 10000; // Max delay before debug request (ns)

     // =========================================================================
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

* 第 69~73 行：stimulus timing 字段定义最大间隔和 IRQ/debug 初始延迟范围。
* 第 78~82 行：test completion 字段包括 30 分钟 wall-clock timeout、cycle timeout、signature
  completion、mailbox 地址和 boot 地址。
* 第 87~88 行：ISA string 与 ``misa_value`` 默认值在 config 中定义。
* 第 93~94 行：``binary`` 和 ``cosim_binary`` 保存 DUT 与 cosim binary 路径。

接口关系：

* 被调用：base test 和 sequence 读取 timeout、binary、boot/signature 配置。
* 调用：无。
* 共享状态：cfg 字段。

§3.3  constructor 读取 plusargs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

逐段解释：

* 第 96~98 行：constructor 调父类 ``new`` 后开始读取 plusargs。
* 第 99~107 行：读取 IRQ、debug 和 fetch toggle 相关 plusargs。
* 第 108~111 行：读取 AXI4 error injection 和 cosim enable/disable。
* 第 112~117 行：读取 memory error、spurious response、double-fault 和 max interval。

接口关系：

* 被调用：``core_eh2_env.new`` 创建 cfg 时执行。
* 调用：``$value$plusargs``。
* 共享状态：cfg 字段。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L118-L136``）：

.. code-block:: systemverilog

       void'($value$plusargs("timeout_ns=%d", timeout_ns));
       void'($value$plusargs("max_cycles=%d", max_cycles));
       void'($value$plusargs("bin=%s", binary));
       void'($value$plusargs("bin_cosim=%s", cosim_binary));
       void'($value$plusargs("boot_addr=%h", boot_addr));
       void'($value$plusargs("irq_delay_min=%d", irq_delay_min));
       void'($value$plusargs("irq_delay_max=%d", irq_delay_max));
       void'($value$plusargs("debug_delay_min=%d", debug_delay_min));
       void'($value$plusargs("debug_delay_max=%d", debug_delay_max));

       // If disable_cosim is set, override enable_cosim
       if (disable_cosim) enable_cosim = 0;

       // If enable_irq_seq is set, enable single + drop IRQ sequences
       // (multiple and NMI must be enabled independently)
       if (enable_irq_single_seq) begin
         enable_irq_drop_seq = 1;
       end
     endfunction

逐段解释：

* 第 118~126 行：读取 timeout、max cycles、binary、cosim binary、boot 地址和 delay 范围。
* 第 128~129 行：``disable_cosim`` 为真时强制 ``enable_cosim=0``。
* 第 131~135 行：``enable_irq_single_seq`` 为真时自动打开 ``enable_irq_drop_seq``。
* 第 136 行：结束 constructor。

接口关系：

* 被调用：cfg constructor。
* 调用：``$value$plusargs``。
* 共享状态：cfg 字段之间的派生关系。

§3.4  ``convert2string()`` — 配置日志
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L138-L156``）：

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

   endclass

逐段解释：

* 第 138~140 行：function 初始化输出字符串。
* 第 141~150 行：追加 IRQ、debug、fetch、cosim、memory 和 AXI4 error injection 配置。
* 第 151~152 行：追加 timeout 和 binary。
* 第 153~156 行：返回字符串并结束 class。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 通过 ``uvm_info`` 打印该字符串。
* 调用：``$sformatf``。
* 共享状态：读取 cfg 字段。

§4  ``core_eh2_env.sv`` — component 编排
------------------------------------------------------------------------------------------------------------------------

职责：``core_eh2_env`` 创建和连接 UVM components，是本章的核心 class。

§4.1  成员声明与 constructor
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L18-L64``）：

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

* 第 18~20 行：env 继承 ``uvm_env`` 并注册 component 类型。
* 第 23~26 行：声明 cfg 和 virtual sequencer。
* 第 29~31 行：声明 3 个 AXI4 agent：LSU、IFU、SB。源码没有声明 DMA AXI4 agent。
* 第 34~37 行：声明 IRQ 和 JTAG active agent。

接口关系：

* 被调用：base test 创建 env。
* 调用：UVM component macro。
* 共享状态：env component 句柄。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L39-L64``）：

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

     function new(string name, uvm_component parent);
       super.new(name, parent);
       // Create cfg in constructor so it's available during child build_phase
       cfg = core_eh2_env_cfg::type_id::create("cfg");
     endfunction

逐段解释：

* 第 39~46 行：声明 halt/run agent、trace monitor 和 DUT probe monitor。
* 第 49~52 行：声明 cosim agent 和 double-fault detection scoreboard。
* 第 55~58 行：声明 optional CSR 与 instruction monitor virtual interface 句柄。
* 第 60~64 行：constructor 创建 cfg，注释说明这样 child build phase 期间 cfg 已可用。

接口关系：

* 被调用：UVM factory 创建 env 时执行。
* 调用：``core_eh2_env_cfg::type_id::create``。
* 共享状态：``cfg``。

§4.2  build phase：vseqr 与 AXI4 agent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L66-L85``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       `uvm_info("env", cfg.convert2string(), UVM_LOW)

       // Virtual sequencer
       vseqr = core_eh2_vseqr::type_id::create("vseqr", this);

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

* 第 66~68 行：build phase 先调用父类，再打印 cfg 字符串。
* 第 70~71 行：创建 ``vseqr``。
* 第 73~79 行：创建 ``lsu_agent``；当 ``cfg.enable_axi4_error_inject`` 为真时设置 active，
  否则设置 passive。
* 第 81~85 行：创建 ``ifu_agent`` 和 ``sb_agent``，二者都设置为 ``UVM_PASSIVE``。

接口关系：

* 被调用：UVM build phase。
* 调用：UVM factory、``uvm_config_db::set``、``cfg.convert2string``。
* 共享状态：AXI4 agent 句柄和 ``is_active`` config。

§4.3  build phase：active agents 与 monitors
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L87-L104``）：

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

       // Trace monitor
       trace_monitor = eh2_trace_monitor::type_id::create("trace_monitor", this);

       // DUT probe monitor
       dut_probe_monitor = eh2_dut_probe_monitor::type_id::create("dut_probe_monitor", this);

逐段解释：

* 第 87~89 行：创建 IRQ agent 并设为 ``UVM_ACTIVE``。
* 第 91~93 行：创建 JTAG agent 并设为 ``UVM_ACTIVE``。
* 第 95~97 行：创建 halt/run agent 并设为 ``UVM_ACTIVE``。
* 第 99~103 行：直接创建 trace monitor 与 DUT probe monitor；源码没有 ``trace_agent`` wrapper。

接口关系：

* 被调用：UVM build phase。
* 调用：UVM factory 和 ``uvm_config_db::set``。
* 共享状态：agent/monitor component 句柄。

§4.4  build phase：cosim cfg 注入与 cosim agent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 105~106 行：cosim agent 只在 ``cfg.enable_cosim`` 为真时创建。
* 第 110~112 行：创建局部 ``eh2_cosim_cfg`` 对象。
* 第 114~117 行：读取 ``MEM_ICCM_BASE``、``MEM_ICCM_SIZE``、``MEM_DCCM_BASE`` 和
  ``MEM_DCCM_SIZE`` plusargs。
* 第 119~120 行：同步 flat fields 到 struct fields，并把 ``cosim_cfg`` 注入
  ``cosim_agt.scoreboard``。
* 第 122 行：创建 ``cosim_agt``。

接口关系：

* 被调用：UVM build phase。
* 调用：``$value$plusargs``、``sync_mem_regions``、``uvm_config_db::set``、UVM factory。
* 共享状态：``cosim_cfg`` 和 ``cosim_agt``。

§4.5  build phase：double-fault scoreboard 与 optional interfaces
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L125-L139``）：

.. code-block:: systemverilog

       // Double-fault detection scoreboard
       dfd_scoreboard = core_eh2_scoreboard::type_id::create("dfd_scoreboard", this);

       // CSR monitoring interface
       if (!uvm_config_db#(virtual eh2_csr_if)::get(this, "", "csr_vif", csr_vif))
         `uvm_info("env", "CSR monitoring interface not set (optional)", UVM_LOW)

       // Instruction monitoring interface
       if (!uvm_config_db#(virtual eh2_instr_monitor_if)::get(this, "", "instr_monitor_vif", instr_monitor_vif))
         `uvm_info("env", "Instruction monitoring interface not set (optional)", UVM_LOW)

       // Configure AXI4 error injection on LSU driver (only when active)
       // NOTE: driver is not yet built here (build_phase is top-down, agent's
       // build_phase runs after env's). Configuration is deferred to connect_phase.
     endfunction

逐段解释：

* 第 125~126 行：env 总是创建 ``dfd_scoreboard``。
* 第 128~130 行：尝试获取 optional ``csr_vif``；失败只打印低 verbosity info。
* 第 132~134 行：尝试获取 optional ``instr_monitor_vif``；失败也只打印 info。
* 第 136~138 行：注释说明 AXI4 error injection driver 配置延后到 connect phase，因为 child
  agent build phase 在 env build phase 之后运行。
* 第 139 行：结束 build phase。

接口关系：

* 被调用：UVM build phase。
* 调用：UVM factory、``uvm_config_db::get``、``uvm_info``。
* 共享状态：``dfd_scoreboard``、``csr_vif``、``instr_monitor_vif``。

§4.6  connect phase：LSU error injection 和 cosim 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L141-L164``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);

       // Configure AXI4 error injection on LSU driver (driver is now built)
       if (cfg.enable_axi4_error_inject && lsu_agent.driver != null) begin
         lsu_agent.driver.enable_error_inject = 1;
         lsu_agent.driver.error_pct           = cfg.axi4_error_pct;
         `uvm_info("env", $sformatf("AXI4 error injection enabled on LSU (pct=%0d)", cfg.axi4_error_pct), UVM_LOW)
       end

       // Connect trace monitor to co-simulation agent's scoreboard
       if (cfg.enable_cosim && cosim_agt != null) begin
         trace_monitor.ap.connect(cosim_agt.scoreboard.trace_fifo.analysis_export);
       end

       // Connect DUT probe monitor to co-simulation agent's scoreboard
       if (cfg.enable_cosim && cosim_agt != null) begin
         dut_probe_monitor.ap.connect(cosim_agt.scoreboard.dut_probe_fifo.analysis_export);

逐段解释：

* 第 141~142 行：connect phase 先调用父类。
* 第 145~148 行：当 AXI4 error injection 开启且 ``lsu_agent.driver`` 非空时，设置 driver
  的 ``enable_error_inject`` 和 ``error_pct``。
* 第 151~154 行：cosim 开启且 ``cosim_agt`` 非空时，trace monitor output 连接到 cosim
  scoreboard ``trace_fifo``。
* 第 156~158 行：同样条件下，DUT probe monitor output 连接到 cosim scoreboard
  ``dut_probe_fifo``。

接口关系：

* 被调用：UVM connect phase。
* 调用：analysis port ``connect``、UVM log macro。
* 共享状态：LSU driver config、cosim scoreboard FIFO。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L157-L173``）：

.. code-block:: systemverilog

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
     endfunction

逐段解释：

* 第 157~159 行：DUT probe monitor 到 cosim scoreboard 的连接完成 async writeback hint 输入。
* 第 161~164 行：LSU AXI4 monitor output 连接到 ``cosim_agt.dmem_port``。
* 第 166~167 行：trace monitor output 无条件连接到 double-fault scoreboard 的 ``trace_fifo``。
* 第 169~172 行：把 IRQ、JTAG、Halt/Run agent sequencer 句柄写入 virtual sequencer。
* 第 173 行：结束 connect phase。

接口关系：

* 被调用：UVM connect phase。
* 调用：analysis port ``connect``。
* 共享状态：``vseqr`` sub-sequencer 句柄、scoreboard FIFO。

§5  ``core_eh2_vseqr.sv`` — virtual sequencer
------------------------------------------------------------------------------------------------------------------------

职责：``core_eh2_vseqr`` 保存 active agent 的 sub-sequencer 句柄，供 virtual sequence 统一调度。

关键代码（``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L20``）：

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

   endclass

逐段解释：

* 第 7~9 行：virtual sequencer 继承 ``uvm_sequencer`` 并注册 component 类型。
* 第 11~14 行：保存 IRQ、JTAG 和 Halt/Run sub-sequencer 句柄。
* 第 16~18 行：constructor 只调用父类 constructor。
* 第 20 行：结束 class；该文件没有 run phase 或 sequence 启动逻辑。

接口关系：

* 被调用：``core_eh2_env`` 创建并在 connect phase 填充句柄。
* 调用：无。
* 共享状态：``irq_seqr``、``jtag_seqr``、``halt_run_seqr``。

§6  ``core_eh2_scoreboard.sv`` — double-fault detection scoreboard
------------------------------------------------------------------------------------------------------------------------

职责：``core_eh2_scoreboard`` 从 trace monitor 接收 retire item，检测连续 exception 数或总
exception 数是否超过阈值。

§6.1  配置、FIFO 与 plusargs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L11-L42``）：

.. code-block:: systemverilog

   class core_eh2_scoreboard extends uvm_scoreboard;

     `uvm_component_utils(core_eh2_scoreboard)

     // Configuration
     bit  enable_detector = 0;
     int  threshold_consecutive = 100;  // Consecutive exception threshold
     int  threshold_total = 1000;       // Total exception threshold
     bit  fatal_on_threshold = 1;       // 1 = UVM_FATAL, 0 = UVM_ERROR

     // Tracking state
     int  consecutive_exceptions = 0;
     int  total_exceptions = 0;
     int  total_retirements = 0;
     int  max_consecutive_exceptions = 0;

     // Analysis FIFO from trace monitor
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) trace_fifo;

逐段解释：

* 第 11~13 行：scoreboard 继承 ``uvm_scoreboard`` 并注册 component 类型。
* 第 16~19 行：配置字段包括 detector enable、consecutive threshold、total threshold 和
  threshold 命中时是否 fatal。
* 第 22~25 行：tracking state 统计连续 exception、总 exception、总 retirements 和最大连续值。
* 第 28 行：``trace_fifo`` 接收 ``eh2_trace_seq_item``。

接口关系：

* 被调用：``core_eh2_env`` 创建 ``dfd_scoreboard``。
* 调用：UVM component macro。
* 共享状态：scoreboard counters 和 FIFO。

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L30-L42``）：

.. code-block:: systemverilog

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       trace_fifo = new("trace_fifo", this);

       void'($value$plusargs("enable_double_fault_detector=%b", enable_detector));
       void'($value$plusargs("double_fault_threshold=%d", threshold_consecutive));
       void'($value$plusargs("double_fault_total_threshold=%d", threshold_total));
       void'($value$plusargs("double_fault_fatal=%b", fatal_on_threshold));
     endfunction

逐段解释：

* 第 30~32 行：constructor 只调用父类 constructor。
* 第 34~36 行：build phase 创建 ``trace_fifo``。
* 第 38~41 行：读取 double-fault detector 相关 plusargs。
* 第 42 行：结束 build phase。

接口关系：

* 被调用：UVM build phase。
* 调用：``$value$plusargs``。
* 共享状态：``trace_fifo`` 和 detector 配置。

§6.2  run phase 与 threshold 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L44-L79``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       if (enable_detector) begin
         fork
           monitor_exceptions();
         join
       end
     endtask

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

逐段解释：

* 第 44~50 行：只有 ``enable_detector`` 为真时，run phase 才 fork ``monitor_exceptions``。
* 第 53~58 行：``monitor_exceptions`` 从 ``trace_fifo`` 阻塞获取 item，空 item 直接跳过。
* 第 60 行：每个非空 item 增加 retirements。
* 第 62~66 行：exception item 调 ``notify_exception``，否则调 ``notify_retirement``。

接口关系：

* 被调用：UVM run phase。
* 调用：``trace_fifo.get``、``notify_exception``、``notify_retirement``。
* 共享状态：``trace_fifo`` 和 counters。

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L68-L94``）：

.. code-block:: systemverilog

         // Check consecutive threshold
         if (consecutive_exceptions >= threshold_consecutive) begin
           if (fatal_on_threshold) begin
             `uvm_fatal("scoreboard", $sformatf(
               "Double-fault detected: %0d consecutive exceptions (threshold: %0d)",
               consecutive_exceptions, threshold_consecutive))
           end else begin
             `uvm_error("scoreboard", $sformatf(
               "Double-fault detected: %0d consecutive exceptions (threshold: %0d)",
               consecutive_exceptions, threshold_consecutive))
           end
         end

         // Check total threshold
         if (total_exceptions >= threshold_total) begin
           if (fatal_on_threshold) begin
             `uvm_fatal("scoreboard", $sformatf(

逐段解释：

* 第 68~79 行：连续 exception 数达到阈值时，根据 ``fatal_on_threshold`` 选择
  ``uvm_fatal`` 或 ``uvm_error``。
* 第 81~84 行：总 exception 数达到阈值时进入第二个 threshold 检查。

接口关系：

* 被调用：``monitor_exceptions`` 每个 item 后执行。
* 调用：UVM fatal/error macro 和 ``$sformatf``。
* 共享状态：``consecutive_exceptions``、``threshold_consecutive``、``total_exceptions``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L82-L94``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 82~91 行：总 exception threshold 命中时，同样根据 ``fatal_on_threshold`` 选择 fatal 或 error。
* 第 93~94 行：结束 forever loop 和 task。

接口关系：

* 被调用：``monitor_exceptions``。
* 调用：UVM fatal/error macro。
* 共享状态：``total_exceptions``、``threshold_total``。

§6.3  counter 更新与 report phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_scoreboard.sv:L96-L119``）：

.. code-block:: systemverilog

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

     // Report phase
     function void report_phase(uvm_phase phase);
       super.report_phase(phase);
       `uvm_info("scoreboard", "=== Double-Fault Scoreboard Report ===", UVM_LOW)
       `uvm_info("scoreboard", $sformatf("  Total retirements: %0d", total_retirements), UVM_LOW)
       `uvm_info("scoreboard", $sformatf("  Total exceptions: %0d", total_exceptions), UVM_LOW)
       `uvm_info("scoreboard", $sformatf("  Max consecutive exceptions: %0d", max_consecutive_exceptions), UVM_LOW)
       `uvm_info("scoreboard", $sformatf("  Detector enabled: %0b", enable_detector), UVM_LOW)
     endfunction

   endclass

逐段解释：

* 第 96~102 行：``notify_exception`` 增加 consecutive 和 total counters，并更新最大连续值。
* 第 104~107 行：``notify_retirement`` 把 ``consecutive_exceptions`` 清零。
* 第 110~117 行：report phase 打印 retirements、exceptions、max consecutive 和 detector enable。
* 第 119 行：结束 class。

接口关系：

* 被调用：``monitor_exceptions`` 和 UVM report phase。
* 调用：UVM log macro。
* 共享状态：scoreboard counters。

§7  env 辅助 interface
------------------------------------------------------------------------------------------------------------------------

职责：env 目录还定义 CSR、instruction monitor、DUT probe 和 RVFI interface。这些 interface
由 tb 顶层注入 config_db，env 或其它组件按需读取。

§7.1  ``eh2_csr_if.sv`` — CSR monitoring interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/eh2_csr_if.sv:L16-L45``）：

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
       input csr_read;
       input csr_write;
       input csr_set;
       input csr_clr;
     endclocking

   endinterface

逐段解释：

* 第 16~19 行：CSR interface 接收 ``clk`` 和 ``rst_n``。
* 第 21~30 行：声明 CSR access、address、write/read data、write enable 和 read/write/set/clear
  operation flags。
* 第 32~43 行：``monitor_cb`` 在 ``posedge clk`` 采样所有 CSR signals。
* 第 45 行：结束 interface。

接口关系：

* 被调用：tb 顶层把 ``u_csr_if`` 注入 config_db；env 尝试获取 ``csr_vif``。
* 调用：SystemVerilog clocking block。
* 共享状态：CSR monitor virtual interface。

§7.2  ``eh2_instr_monitor_if.sv`` — decode instruction monitor interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv:L17-L60``）：

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

* 第 17~20 行：instruction monitor interface 接收 ``clk`` 和 ``rst_n``。
* 第 22~28 行：i0 decode stage 信号包括 valid、instruction、compressed、branch taken 和 stall。
* 第 30~36 行：i1 decode stage 信号与 i0 对应。
* 第 38~40 行：pipeline control 包括 ``pipe_flush`` 和 ``dual_issue``。

接口关系：

* 被调用：tb 顶层把 ``u_instr_monitor_if`` 注入 config_db；env 尝试获取 ``instr_monitor_vif``。
* 调用：无。
* 共享状态：decode-stage monitor virtual interface。

关键代码（``dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv:L42-L60``）：

.. code-block:: systemverilog

     // Monitor clocking block
     clocking monitor_cb @(posedge clk);
       input i0_valid;
       input i0_instr;
       input i0_compressed;
       input i0_instr_compressed;
       input i0_branch_taken;
       input i0_stall;
       input i1_valid;
       input i1_instr;
       input i1_compressed;
       input i1_instr_compressed;
       input i1_branch_taken;
       input i1_stall;
       input pipe_flush;
       input dual_issue;
     endclocking

   endinterface

逐段解释：

* 第 42~58 行：``monitor_cb`` 在 ``posedge clk`` 采样 i0/i1 decode 和 pipeline control 信号。
* 第 60 行：结束 interface。

接口关系：

* 被调用：instruction monitor 或 coverage 组件可通过 virtual interface 采样。
* 调用：SystemVerilog clocking block。
* 共享状态：decode-stage monitor signals。

§7.3  ``eh2_rvfi_if.sv`` — RVFI monitor interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/eh2_rvfi_if.sv:L8-L29``）：

.. code-block:: systemverilog

   interface eh2_rvfi_if (
     input logic clk,
     input logic rst_l
   );
     logic [1:0]   rvfi_valid;
     logic [127:0] rvfi_order;
     logic [63:0]  rvfi_insn;
     logic [63:0]  rvfi_pc_rdata;
     logic [63:0]  rvfi_pc_wdata;
     logic [63:0]  rvfi_rs1_addr;
     logic [63:0]  rvfi_rs2_addr;
     logic [63:0]  rvfi_rd_addr;
     logic [63:0]  rvfi_rd_wdata;
     logic [63:0]  rvfi_mem_addr;
     logic [63:0]  rvfi_mem_rdata;
     logic [63:0]  rvfi_mem_wdata;
     logic [63:0]  rvfi_mem_rmask;
     logic [63:0]  rvfi_mem_wmask;
     logic [1:0]   rvfi_trap;
     logic [1:0]   rvfi_intr;
     logic [3:0]   rvfi_mode;

逐段解释：

* 第 8~11 行：RVFI interface 接收 ``clk`` 和 active-low ``rst_l``。
* 第 12~28 行：声明双通道 RVFI fields，包括 valid、order、instruction、PC、source/destination
  register、memory、trap、interrupt 和 mode。

接口关系：

* 被调用：tb 顶层 RVFI converter 输出接入该 interface，并注入 config_db。
* 调用：无。
* 共享状态：``rvfi_vif``。

关键代码（``dv/uvm/core_eh2/env/eh2_rvfi_if.sv:L30-L62``）：

.. code-block:: systemverilog

     // Clocking block for synchronous sampling
     clocking cb @(posedge clk);
       input rvfi_valid;
       input rvfi_order;
       input rvfi_insn;
       input rvfi_pc_rdata;
       input rvfi_pc_wdata;
       input rvfi_rs1_addr;
       input rvfi_rs2_addr;
       input rvfi_rd_addr;
       input rvfi_rd_wdata;
       input rvfi_mem_addr;
       input rvfi_mem_rdata;
       input rvfi_mem_wdata;
       input rvfi_mem_rmask;
       input rvfi_mem_wmask;
       input rvfi_trap;
       input rvfi_intr;
       input rvfi_mode;
     endclocking

     // Modport for monitor
     modport monitor (
       input clk, rst_l,

逐段解释：

* 第 30~49 行：``cb`` clocking block 在 ``posedge clk`` 同步采样全部 RVFI fields。
* 第 51~54 行：monitor modport 开始声明 ``clk``、``rst_l`` 和 RVFI input list。

接口关系：

* 被调用：RVFI monitor 可使用该 clocking block 或 modport。
* 调用：SystemVerilog clocking block 和 modport。
* 共享状态：RVFI fields。

关键代码（``dv/uvm/core_eh2/env/eh2_rvfi_if.sv:L52-L62``）：

.. code-block:: systemverilog

     modport monitor (
       input clk, rst_l,
       input rvfi_valid, rvfi_order, rvfi_insn,
       input rvfi_pc_rdata, rvfi_pc_wdata,
       input rvfi_rs1_addr, rvfi_rs2_addr,
       input rvfi_rd_addr, rvfi_rd_wdata,
       input rvfi_mem_addr, rvfi_mem_rdata, rvfi_mem_wdata,
       input rvfi_mem_rmask, rvfi_mem_wmask,
       input rvfi_trap, rvfi_intr, rvfi_mode
     );
   endinterface

逐段解释：

* 第 52~61 行：``monitor`` modport 把所有 RVFI fields 声明为 input。
* 第 62 行：结束 interface。

接口关系：

* 被调用：monitor 类型可使用 ``eh2_rvfi_if.monitor`` 视图。
* 调用：SystemVerilog modport。
* 共享状态：RVFI fields。

§8  tb 顶层 config_db 注入
------------------------------------------------------------------------------------------------------------------------

职责：tb 顶层把 env 及各 agent/monitor 所需 virtual interfaces 注入 config_db。env 文档只引用
实际存在的 key 和 instance pattern。

§8.1  AXI4 与 trace/probe interface 注入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1107-L1120``）：

.. code-block:: systemverilog

       uvm_config_db#(virtual core_eh2_tb_intf)::set(null, "*", "tb_vif", tb_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_LSU_BUS_TAG)))::set(null, "*lsu_agent*", "vif", lsu_axi_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_IFU_BUS_TAG)))::set(null, "*ifu_agent*", "vif", ifu_axi_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_SB_BUS_TAG)))::set(null, "*sb_agent*",  "vif", sb_axi_intf);

       // Store trace and DUT probe interfaces
       uvm_config_db#(virtual eh2_trace_intf)::set(null, "*trace_monitor*", "vif", trace_intf);
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*dut_probe_monitor*", "vif", dut_probe_intf);

       // Also provide DUT probe interface to trace monitor (for interrupt/debug state sampling)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*trace_monitor*", "probe_vif", dut_probe_intf);

       // Provide DUT probe interface to cosim agent's scoreboard (for reset monitoring)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*cosim_agt*", "probe_vif", dut_probe_intf);

逐段解释：

* 第 1107 行：``tb_vif`` 对所有实例 pattern ``"*"`` 可见。
* 第 1108~1110 行：LSU、IFU、SB AXI interfaces 分别注入对应 agent pattern。
* 第 1112~1117 行：trace monitor 获取 ``trace_intf`` 和 ``dut_probe_intf``；DUT probe monitor
  获取 ``dut_probe_intf``。
* 第 1119~1120 行：cosim agent 也获取 DUT probe interface。

接口关系：

* 被调用：tb 顶层 initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：virtual interface config entries。

§8.2  active agent、coverage、CSR、instruction 与 RVFI interface 注入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1122-L1144``）：

.. code-block:: systemverilog

       // Store IRQ interface
       uvm_config_db#(virtual eh2_irq_intf)::set(null, "*", "irq_vif", irq_intf);

       // Store JTAG interface
       uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);

       // Store Halt/Run interface
       uvm_config_db#(virtual eh2_halt_run_intf)::set(null, "*", "halt_run_vif", halt_run_vif);

       // Store fetch enable interface
       uvm_config_db#(virtual fetch_enable_intf)::set(null, "*", "fetch_vif", fetch_en_intf);

       // Store functional coverage interface
       uvm_config_db#(virtual eh2_fcov_if)::set(null, "*", "fcov_vif", u_fcov_if);

       // Store CSR monitoring interface
       uvm_config_db#(virtual eh2_csr_if)::set(null, "*", "csr_vif", u_csr_if);

       // Store instruction monitoring interface
       uvm_config_db#(virtual eh2_instr_monitor_if)::set(null, "*", "instr_monitor_vif", u_instr_monitor_if);

       // Store RVFI interface
       uvm_config_db#(virtual eh2_rvfi_if)::set(null, "*", "rvfi_vif", rvfi_intf);

逐段解释：

* 第 1122~1129 行：IRQ、JTAG 和 Halt/Run virtual interfaces 分别以 ``irq_vif``、
  ``jtag_vif`` 和 ``halt_run_vif`` 注入。
* 第 1131~1135 行：fetch enable 和 functional coverage interface 也注入 config_db。
* 第 1137~1144 行：CSR、instruction monitor 和 RVFI interface 以对应 key 注入。

接口关系：

* 被调用：tb 顶层 initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：virtual interface config entries。

§9  与 cosim cfg 的接口
------------------------------------------------------------------------------------------------------------------------

职责：env build phase 创建 ``eh2_cosim_cfg`` 并覆盖 ICCM/DCCM base/size。该 config object
本身在 cosim agent 目录定义，但 env 负责注入 scoreboard。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L49-L78``）：

.. code-block:: systemverilog

     mem_region_t mem_boot      = '{base: 32'h8000_0000, size: 32'h0400_0000};
     mem_region_t mem_debug_sb  = '{base: 32'hA058_0000, size: 32'h0400_0000};
     mem_region_t mem_ext_data1 = '{base: 32'hB000_0000, size: 32'h0400_0000};
     mem_region_t mem_ext_data2 = '{base: 32'hC058_0000, size: 32'h0400_0000};
     mem_region_t mem_iccm      = '{base: 32'hEE00_0000, size: 32'h0001_0000};
     mem_region_t mem_dccm      = '{base: 32'hF004_0000, size: 32'h0001_0000};

     // Explicit DCCM/ICCM base/size fields for env injection from RTL parameters
     // (issue 65). These mirror mem_dccm/mem_iccm but provide flat access for
     // testbench wiring and plusarg override.
     bit [31:0] dccm_base = 32'hF004_0000;
     bit [31:0] dccm_size = 32'h0001_0000;
     bit [31:0] iccm_base = 32'hEE00_0000;
     bit [31:0] iccm_size = 32'h0001_0000;
     mem_region_t mem_pic       = '{base: 32'hF00C_0000, size: 32'h0000_8000};
     mem_region_t mem_mailbox   = '{base: 32'hD058_0000, size: 32'h0000_1000};
     mem_region_t mem_nmi_vec   = '{base: 32'h1111_0000, size: 32'h0000_1000};

     function new(string name = "eh2_cosim_cfg");
       super.new(name);
     endfunction

     // Sync flat fields into struct fields (for env injection path).
     // Called after plusarg overrides to keep both representations in agreement.
     function void sync_mem_regions();
       mem_iccm.base = iccm_base;
       mem_iccm.size = iccm_size;
       mem_dccm.base = dccm_base;
       mem_dccm.size = dccm_size;

逐段解释：

* 第 49~55 行：``eh2_cosim_cfg`` 定义 boot、debug SB、external data、ICCM 和 DCCM memory regions。
* 第 59~64 行：flat ``dccm_*`` 和 ``iccm_*`` 字段用于 env plusarg override。
* 第 63~65 行：PIC、mailbox 和 NMI vector memory regions 也在 config 中定义。
* 第 73~78 行：``sync_mem_regions`` 把 flat ICCM/DCCM 字段同步到 struct fields。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 创建并调用 ``sync_mem_regions``。
* 调用：无。
* 共享状态：``cosim_cfg`` memory region fields。

§10  运行时行为边界
------------------------------------------------------------------------------------------------------------------------

职责：本节列出 env 当前源码明确支持的边界，避免把其它组件误写进 env。

§10.1  env 没有创建 DMA AXI4 agent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``core_eh2_env.sv`` 第 29~31 行只声明 ``lsu_agent``、``ifu_agent`` 和 ``sb_agent``。
tb 顶层有 DMA AXI wire，但 env 没有 ``dma_agent`` 成员，也没有 config_db pattern
``*dma_agent*``。因此本章只描述 3 个 AXI4 agent。

接口关系：

* 被调用：env build phase。
* 调用：无。
* 共享状态：AXI4 agent component 集合。

§10.2  env 没有创建 fcov collector
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

tb 顶层第 1134~1135 行把 ``eh2_fcov_if`` 以 ``fcov_vif`` 注入 config_db，但
``core_eh2_env.sv`` 没有声明或创建 ``eh2_fcov`` component。功能覆盖率实现位于 fcov 目录，
不属于当前 env class 的 component 创建列表。

接口关系：

* 被调用：tb 顶层 config_db 注入。
* 调用：``uvm_config_db::set``。
* 共享状态：``fcov_vif`` config entry。

§11  参考资料
------------------------------------------------------------------------------------------------------------------------

* :ref:`env` — verification architecture 中的 env 说明。
* :ref:`appendix_b_uvm_axi4_agent` — AXI4 agent 详细源码字典。
* :ref:`appendix_b_uvm_trace_agent` — trace/probe monitor 和 scoreboard 输入关系。
* :ref:`appendix_b_uvm_cosim_agent` — cosim agent 与 scoreboard 源码字典。
* :ref:`adr-0002` — AXI4 passive monitoring。
* :ref:`adr-0004` — RTL RVFI-equivalent trace。
* :ref:`adr-0017` — integrity cosim waiver 背景。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_pkg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_cfg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_scoreboard.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_csr_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_instr_monitor_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_dut_probe_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_rvfi_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
