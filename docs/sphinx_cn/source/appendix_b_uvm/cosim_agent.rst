.. _appendix_b_uvm_cosim_agent:
.. _appendix_b_uvm/cosim_agent:

Cosim Agent 源码字典
====================

:status: draft
:source: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/common/cosim_agent/` 下的 UVM cosim agent。
这个目录不是单一 scoreboard 文件，而是一个包：package 汇入配置类、DPI 声明、
scoreboard、agent wrapper，以及两个从 scoreboard 内部 include 的 helper header。

本章覆盖 6 个源文件：

* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cosim agent 的核心数据流由环境层连接建立：trace monitor、DUT probe monitor 和
LSU AXI4 monitor 分别写入 scoreboard 的 3 个 FIFO。scoreboard 再按 thread_id
维护 pending trace 队列、async writeback 队列和共享 LSU memory access 队列，
最终调用 Spike DPI。

::

   eh2_trace_monitor.ap
      |
      v
   trace_fifo ------------------+
                                |
   dut_probe_monitor.ap         v
      |                  pending_trace_q[tid]
      v                         |
   dut_probe_fifo --> async_wb_q[tid]
                                |
   lsu_agent.ap                 v
      |                  compare_instruction()
      v                         |
   dmem_port --> lsu_axi_fifo --> pending_mem_access_q
                                |
                                v
                      riscv_cosim_* DPI calls

接口关系：

* 被调用：:file:`dv/uvm/core_eh2/env/core_eh2_env.sv` 在 ``enable_cosim`` 为真时创建
  ``cosim_agt``。
* 调用：scoreboard 调用 :file:`dv/cosim/cosim_dpi.svh` 声明的
  ``riscv_cosim_*`` DPI 函数。
* 共享状态：``pending_trace_q[2]``、``async_wb_q[2]``、``pending_mem_access_q``、
  ``prev_mip[2]`` 和 ``cosim_handle``。

§2  ``eh2_cosim_agent_pkg.sv`` — package 汇入顺序
------------------------------------------------------------------------------------------------------------------------

职责：package 定义 cosim agent 的编译单元。它先导入 UVM、trace agent 和 AXI4
agent，再按依赖顺序 include 配置、DPI、scoreboard 和 agent。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv:L7-L24``）：

.. code-block:: systemverilog

   package eh2_cosim_agent_pkg;

     `include "uvm_macros.svh"
     import uvm_pkg::*;
     import eh2_trace_agent_pkg::*;
     import axi4_agent_pkg::*;

     // Configuration object
     `include "eh2_cosim_cfg.sv"

     // DPI declarations
     `include "cosim_dpi.svh"

     // Co-simulation scoreboard
     `include "eh2_cosim_scoreboard.sv"

     // Top-level agent
     `include "eh2_cosim_agent.sv"

逐段解释：

* 第 7 行：声明 ``eh2_cosim_agent_pkg``。
* 第 9~12 行：引入 UVM 宏、``uvm_pkg``、trace agent package 和 AXI4 agent
  package。scoreboard 使用 ``eh2_trace_seq_item`` 和 ``axi4_seq_item``，因此这两个
  package 必须先导入。
* 第 15 行：先 include ``eh2_cosim_cfg.sv``，让 scoreboard build phase 可以声明和
  获取 ``eh2_cosim_cfg``。
* 第 18 行：include ``cosim_dpi.svh``。该文件实际位于 :file:`dv/cosim/`，由 filelist
  include path 提供。
* 第 21~24 行：scoreboard 先于 top-level agent include，因为 agent 内部声明了
  ``eh2_cosim_scoreboard scoreboard``。

接口关系：

* 被调用：UVM test/env 通过 ``import eh2_cosim_agent_pkg::*`` 使用这些类。
* 调用：SystemVerilog package import 和 include。
* 共享状态：无运行期状态；只建立编译期可见性。

§3  ``eh2_cosim_agent.sv`` — agent wrapper
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_cosim_agent`` 是轻量 UVM agent。它拥有一个 scoreboard，并向外暴露
``dmem_port``，让 env 把 LSU AXI4 monitor 的 analysis port 接入 scoreboard。

§3.1  类成员与 build/connect phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv:L14-L39``）：

.. code-block:: systemverilog

   class eh2_cosim_agent extends uvm_agent;

     `uvm_component_utils(eh2_cosim_agent)

     // Co-simulation scoreboard
     eh2_cosim_scoreboard scoreboard;

     // External analysis exports for memory traffic
     // (connected by env to AXI4 agent monitors)
     uvm_analysis_export #(axi4_seq_item) dmem_port;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

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

* 第 14~16 行：类继承 ``uvm_agent``，并注册到 UVM factory。
* 第 18~23 行：成员只有两个：``scoreboard`` 和 ``dmem_port``。``dmem_port`` 类型为
  ``uvm_analysis_export #(axi4_seq_item)``，只承接 memory traffic。
* 第 25~27 行：构造函数仅调用父类构造。
* 第 29~33 行：build phase 创建 ``scoreboard``，并实例化外部 analysis export。
* 第 35~39 行：connect phase 将 ``dmem_port`` 连接到
  ``scoreboard.lsu_axi_fifo.analysis_export``。trace 和 DUT probe 的连接不在 agent
  内部做，而是在 env connect phase 中直接连到 scoreboard。

接口关系：

* 被调用：``core_eh2_env`` 在 build phase 创建 ``cosim_agt``。
* 调用：``eh2_cosim_scoreboard::type_id::create`` 和 TLM ``connect``。
* 共享状态：``scoreboard`` 与 ``dmem_port``。

§3.2  Spike memory backdoor helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv:L41-L64``）：

.. code-block:: systemverilog

     // Backdoor-write a single byte into the Spike memory model
     function void write_mem_byte(bit [31:0] addr, bit [7:0] data);
       if (scoreboard.cosim_handle != null) begin
         riscv_cosim_write_mem_byte(scoreboard.cosim_handle, int'(addr), int'(data));
       end
     endfunction

     // Backdoor-write a 32-bit word (little-endian) into the Spike memory model
     function void write_mem_word(bit [31:0] addr, bit [31:0] data);
       write_mem_byte(addr,     data[7:0]);
       write_mem_byte(addr + 1, data[15:8]);
       write_mem_byte(addr + 2, data[23:16]);
       write_mem_byte(addr + 3, data[31:24]);
     endfunction

     // Load a binary file into the Spike memory model
     function void load_binary_to_mem(bit [31:0] base_addr, string bin_path);
       scoreboard.load_binary(bin_path, base_addr);
     endfunction

     // Flush all scoreboard state (called on reset)
     function void reset();
       scoreboard.flush_state();
     endfunction

逐段解释：

* 第 41~46 行：``write_mem_byte`` 只有在 ``scoreboard.cosim_handle`` 非空时调用
  ``riscv_cosim_write_mem_byte``。这防止 cosim 尚未初始化时写入空 handle。
* 第 48~54 行：``write_mem_word`` 按 little-endian 顺序拆成 4 个 byte 写入：
  低 8 位写 ``addr``，高 8 位写 ``addr + 3``。
* 第 56~59 行：``load_binary_to_mem`` 只是把请求转给 scoreboard 的
  ``load_binary``。
* 第 61~64 行：``reset`` 调用 ``scoreboard.flush_state``，不直接销毁或重建 Spike
  handle。

接口关系：

* 被调用：测试或环境可通过 agent 调用这些 helper。
* 调用：``riscv_cosim_write_mem_byte``、``scoreboard.load_binary``、
  ``scoreboard.flush_state``。
* 共享状态：``scoreboard.cosim_handle``。

§4  ``eh2_cosim_cfg.sv`` — Spike 配置对象
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_cosim_cfg`` 保存 Spike 初始化参数、PMP 参数、relax 模式、log 文件路径
和 DUT 可访问 memory region。env 在创建 ``cosim_agt`` 前把该对象写入
``uvm_config_db``，scoreboard 在 build phase 读取。

§4.1  ISA、PC、PMP 与 mismatch 策略
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L10-L37``）：

.. code-block:: systemverilog

   class eh2_cosim_cfg extends uvm_object;

     `uvm_object_utils(eh2_cosim_cfg)

     // RISC-V ISA string passed to Spike (e.g. "rv32imac_zba_zbb_zbc_zbs")
     string isa_string = "rv32imac_zba_zbb_zbc_zbs";

     // Initial program counter for the cosim
     bit [31:0] start_pc = 32'h8000_0000;

     // Initial machine trap-vector base address
     bit [31:0] start_mtvec = 32'h0;

     // Number of PMP regions
     bit [31:0] pmp_num_regions = 16;

     // PMP granularity (log2 of minimum region size)
     bit [31:0] pmp_granularity = 0;

     // Number of MHPM performance counters
     bit [31:0] mhpm_counter_num = 0;

     // When set, mismatches are logged as UVM_LOW instead of UVM_FATAL
     bit relax_cosim_check = 0;

     // Path to Spike log output (empty = no log)
     string log_file = "";

逐段解释：

* 第 10~12 行：配置类继承 ``uvm_object`` 并注册到 factory。
* 第 14~21 行：ISA 字符串默认是 ``rv32imac_zba_zbb_zbc_zbs``，起始 PC 是
  ``0x80000000``，``start_mtvec`` 为 0。
* 第 23~30 行：PMP region 数量默认为 16，granularity 为 0，MHPM counter 数量为 0。
* 第 32~36 行：``relax_cosim_check`` 默认 0，``log_file`` 默认为空字符串。scoreboard
  build phase 会把 ``relax_cosim_check`` 转换为 ``fatal_on_mismatch``。

接口关系：

* 被调用：``core_eh2_env`` 创建并写入 ``uvm_config_db``；scoreboard build phase 获取。
* 调用：无下层函数。
* 共享状态：``isa_string``、``start_pc``、``pmp_num_regions``、``relax_cosim_check``。

§4.2  memory region 表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L38-L65``）：

.. code-block:: systemverilog

     // Debug module address range
     bit [31:0] dm_start_addr = 32'h0000_0000;
     bit [31:0] dm_end_addr   = 32'h0000_0FFF;

     // Memory region configuration (issue 65: from RTL pkg, no hardcoding)
     // Override with plusargs: +MEM_BOOT_BASE=... +MEM_BOOT_SIZE=...
     typedef struct {
       bit [31:0] base;
       bit [31:0] size;
     } mem_region_t;

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

逐段解释：

* 第 38~40 行：debug module address range 默认为 ``0x00000000`` 到 ``0x00000FFF``。
* 第 42~47 行：定义 ``mem_region_t``，只包含 ``base`` 和 ``size``。
* 第 49~55 行：默认 region 包含 boot、debug_sb、ext_data1、ext_data2、ICCM 和
  DCCM。ICCM 默认 ``0xEE000000/0x10000``，DCCM 默认 ``0xF0040000/0x10000``。
* 第 56~63 行：为 env 注入路径提供 flat ``dccm_base``、``dccm_size``、
  ``iccm_base``、``iccm_size`` 字段。
* 第 63~65 行：后续 region 包含 PIC、mailbox 和 NMI vector，mailbox 默认
  ``0xD0580000/0x1000``。

接口关系：

* 被调用：scoreboard ``init_cosim`` 使用这些 region 调用 ``riscv_cosim_add_memory``。
* 调用：无下层函数。
* 共享状态：``mem_*`` region 和 flat DCCM/ICCM 字段。

§4.3  ``sync_mem_regions()`` 与 ``convert2string()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L67-L84``）：

.. code-block:: systemverilog

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
     endfunction

     function string convert2string();
       return $sformatf(
         "eh2_cosim_cfg: isa=%s start_pc=%08x mtvec=%08x pmp=%0d relax=%0b dccm_base=%08h iccm_base=%08h",
         isa_string, start_pc, start_mtvec, pmp_num_regions, relax_cosim_check, dccm_base, iccm_base);
     endfunction

逐段解释：

* 第 67~69 行：构造函数默认对象名是 ``eh2_cosim_cfg``。
* 第 71~78 行：``sync_mem_regions`` 把 flat ICCM/DCCM 字段同步回 ``mem_iccm`` 和
  ``mem_dccm`` struct。env 在读取 plusarg 后调用该函数。
* 第 80~84 行：``convert2string`` 输出 ISA、start PC、mtvec、PMP region 数量、relax
  标志和 DCCM/ICCM base。

接口关系：

* 被调用：``core_eh2_env`` 调用 ``sync_mem_regions``；日志路径可调用
  ``convert2string``。
* 调用：``$sformatf``。
* 共享状态：flat 字段和 struct 字段之间的一致性。

§5  ``core_eh2_env`` 中的创建与连接
------------------------------------------------------------------------------------------------------------------------

职责：cosim agent 的 trace/probe/AXI 输入并非在 agent 内部自动发现，而是由
``core_eh2_env`` 在 build/connect phase 里创建配置、实例化 agent 并连接 analysis
ports。

§5.1  build phase 注入 ``cosim_cfg``
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

* 第 105~106 行：只有 ``cfg.enable_cosim`` 为真时才进入 cosim agent 创建路径。
* 第 107~112 行：env 创建 ``eh2_cosim_cfg`` 对象，注释说明该对象用于把 memory region
  mapping 传给 scoreboard。
* 第 113~117 行：env 读取 ``MEM_ICCM_BASE``、``MEM_ICCM_SIZE``、``MEM_DCCM_BASE``、
  ``MEM_DCCM_SIZE`` plusargs，写入 flat 字段。
* 第 118~120 行：调用 ``sync_mem_regions`` 后，把 cfg 放到
  ``cosim_agt.scoreboard`` 的 ``uvm_config_db`` 路径。
* 第 122 行：最后创建 ``cosim_agt``。

接口关系：

* 被调用：``core_eh2_env.build_phase``。
* 调用：``eh2_cosim_cfg::type_id::create``、``$value$plusargs``、
  ``uvm_config_db::set`` 和 ``eh2_cosim_agent::type_id::create``。
* 共享状态：``cfg.enable_cosim`` 和 ``cosim_cfg``。

§5.2  connect phase 的 3 条输入通道
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 151~154 行：trace monitor 的 analysis port 直接连接到
  ``cosim_agt.scoreboard.trace_fifo.analysis_export``。
* 第 156~159 行：DUT probe monitor 连接到
  ``cosim_agt.scoreboard.dut_probe_fifo.analysis_export``。
* 第 161~164 行：LSU AXI4 agent 的 analysis port 连接到 ``cosim_agt.dmem_port``，
  agent 再在自身 connect phase 转接到 ``lsu_axi_fifo``。

接口关系：

* 被调用：``core_eh2_env.connect_phase``。
* 调用：TLM analysis ``connect``。
* 共享状态：``cfg.enable_cosim`` 和 ``cosim_agt``。

§6  ``eh2_cosim_scoreboard.sv`` — 成员状态
------------------------------------------------------------------------------------------------------------------------

职责：scoreboard 保存所有运行期状态，包括 3 个 FIFO、Spike handle、配置对象、统计
计数、per-thread 队列和 reset/binary reload 状态。

§6.1  FIFO、handle 和统计计数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L33-L64``）：

.. code-block:: systemverilog

   class eh2_cosim_scoreboard extends uvm_scoreboard;

     `uvm_component_utils(eh2_cosim_scoreboard)

     // Analysis FIFOs from monitors
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) trace_fifo;
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) dut_probe_fifo;
     uvm_tlm_analysis_fifo #(axi4_seq_item)      lsu_axi_fifo;

     // Co-simulation handle
     chandle cosim_handle;

     // Configuration object (from config_db, optional)
     eh2_cosim_cfg cfg;

     // Configuration (plusarg overrides or defaults)
     string cosim_config = "";
     bit    enable_cosim = 1;
     bit    fatal_on_mismatch = 0;  // 1 = UVM_FATAL on mismatch, 0 = UVM_ERROR

     // Statistics (aggregated across threads)
     int    step_count;
     int    trace_item_count;
     int    probe_item_count;
     int    suppressed_probe_item_count;
     int    axi_item_count;
     int    pending_trace_high_watermark;

逐段解释：

* 第 33~40 行：scoreboard 是 UVM component，拥有 3 个 analysis FIFO。trace 和
  dut_probe 的 item 类型都是 ``eh2_trace_seq_item``，LSU AXI FIFO 的 item 类型是
  ``axi4_seq_item``。
* 第 42~46 行：``cosim_handle`` 保存 DPI C++ 侧实例句柄；``cfg`` 是从
  ``uvm_config_db`` 获取的配置对象。
* 第 48~52 行：``cosim_config``、``enable_cosim``、``fatal_on_mismatch`` 可由 plusarg
  或 cfg 影响。
* 第 53~64 行：统计计数分为总步数、输入 FIFO 收包数、AXI 收包数和 pending trace
  high watermark。

接口关系：

* 被调用：agent build phase 创建该 scoreboard。
* 调用：无下层函数。
* 共享状态：3 个 FIFO 和 ``cosim_handle``。

§6.2  pending trace、memory access 与 async wb 队列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L65-L103``）：

.. code-block:: systemverilog

     // Tracking state
     bit    initialized = 0;

     // EH2 store-buffer coalescing counters: track how many store-type AXI
     // transactions the AXI monitor has delivered vs how many store trace items
     // the cosim has stepped.  When stepped > delivered, a coalesced store
     // was consumed without a matching AXI — let it proceed.
     int    store_axi_delivered  = 0;
     int    store_trace_stepped  = 0;

     // Trace items wait here until matching memory accesses (for stores/AMOs) arrive.
     // Per-thread queues for dual-hart support.
     typedef struct {
       eh2_trace_seq_item item;
     } pending_trace_t;
     pending_trace_t pending_trace_q[2][$];

     // LSU AXI memory accesses from the bus monitor.
     // Memory bus is shared across threads — no per-thread split needed.
     typedef struct {
       axi4_seq_item txn;
       bit           is_store;
       int           observed_access_count;
     } pending_mem_access_t;
     pending_mem_access_t pending_mem_access_q[$];

     // Async writeback hints from the dut probe (NB-load wb / DIV cancel).
     // Per-thread queues. wb_tag enables strict ordering match (issue 66).

逐段解释：

* 第 65~73 行：``initialized`` 标记 Spike 是否可用；``store_axi_delivered`` 与
  ``store_trace_stepped`` 用于处理 store-buffer coalescing。
* 第 75~80 行：``pending_trace_q`` 是 2 个 per-thread 队列，每个元素保存一个
  ``eh2_trace_seq_item``。
* 第 82~89 行：``pending_mem_access_q`` 是共享 memory bus 队列，记录 AXI transaction、
  是否 store 和 observed access count。
* 第 91~103 行：async writeback hint 是 per-thread 队列，包含 ``rd``、
  ``rd_data``、``suppress``、``source`` 和严格匹配用的 ``wb_tag``。

接口关系：

* 被调用：``run_cosim_trace``、``run_cosim_probe_async`` 和 ``run_cosim_dmem`` 写入这些
  队列。
* 调用：无下层函数。
* 共享状态：``pending_trace_q``、``pending_mem_access_q``、``async_wb_q``。

§6.3  build/connect/run phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L121-L163``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       trace_fifo     = new("trace_fifo", this);
       dut_probe_fifo = new("dut_probe_fifo", this);
       lsu_axi_fifo   = new("lsu_axi_fifo", this);

       // Get configuration object from config_db (optional)
       void'(uvm_config_db#(eh2_cosim_cfg)::get(this, "", "cosim_cfg", cfg));

       // Get configuration via plusargs (overrides cfg or defaults)
       void'($value$plusargs("enable_cosim=%b", enable_cosim));
       void'($value$plusargs("cosim_config=%s", cosim_config));
       void'($value$plusargs("cosim_fatal_on_mismatch=%b", fatal_on_mismatch));

       // Apply cfg values if cfg was provided and plusargs didn't override
       if (cfg != null) begin
         if (cosim_config == "") cosim_config = cfg.isa_string;
         fatal_on_mismatch = cfg.relax_cosim_check ? 0 : 1;
         // Memory region overrides (issue 65): plusargs override cfg defaults
         void'($value$plusargs("MEM_BOOT_BASE=%h",     cfg.mem_boot.base));
         void'($value$plusargs("MEM_ICCM_BASE=%h",     cfg.mem_iccm.base));
         void'($value$plusargs("MEM_DCCM_BASE=%h",     cfg.mem_dccm.base));
         void'($value$plusargs("MEM_MAILBOX_BASE=%h",  cfg.mem_mailbox.base));
       end
     endfunction

逐段解释：

* 第 121~125 行：build phase 创建 3 个 FIFO。
* 第 127~128 行：scoreboard 从 ``uvm_config_db`` 获取 ``cosim_cfg``，获取失败也不报错。
* 第 130~133 行：读取 ``enable_cosim``、``cosim_config`` 和
  ``cosim_fatal_on_mismatch`` plusargs。
* 第 135~144 行：如果 cfg 存在，默认 ``cosim_config`` 来自 ``cfg.isa_string``，
  ``fatal_on_mismatch`` 由 ``cfg.relax_cosim_check`` 反向决定，并继续读取部分 memory
  base plusargs 覆盖 cfg。

接口关系：

* 被调用：UVM build phase。
* 调用：``uvm_config_db::get`` 和 ``$value$plusargs``。
* 共享状态：FIFO、``cfg``、``cosim_config``、``enable_cosim``。

§6.4  ``run_phase()`` 的并行任务
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L153-L183``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       if (enable_cosim) begin
         init_cosim();
         fork
           run_cosim_trace();
           run_cosim_probe_async();
           run_cosim_dmem();
           run_reset_monitor();
         join
       end
     endtask

     // Monitor reset and re-initialize cosim model after reset de-assertion
     task run_reset_monitor();
       if (probe_vif == null) return;

       forever begin
         @(negedge probe_vif.rst_n);
         reset_active = 1;
         `uvm_info("cosim", "Reset asserted - flushing state", UVM_LOW)
         flush_state();

         @(posedge probe_vif.rst_n);

逐段解释：

* 第 153~155 行：只有 ``enable_cosim`` 为真才初始化 Spike。
* 第 156~161 行：scoreboard 并行启动 4 个任务：trace、probe async、dmem 和 reset
  monitor。这里使用 ``fork ... join``，因此这些 forever 任务共同构成 scoreboard 的
  运行期。
* 第 166~167 行：如果 ``probe_vif`` 为空，reset monitor 直接返回。
* 第 169~173 行：reset 下降沿时设置 ``reset_active``，打印日志并调用
  ``flush_state``。
* 第 175~183 行：源文件随后在 reset 上升沿清 ``reset_active``，并在
  ``enable_cosim`` 为真时重新 ``init_cosim``。

接口关系：

* 被调用：UVM run phase。
* 调用：``init_cosim``、``run_cosim_trace``、``run_cosim_probe_async``、
  ``run_cosim_dmem``、``run_reset_monitor`` 和 ``flush_state``。
* 共享状态：``enable_cosim``、``probe_vif``、``reset_active``。

§6.5  ``flush_state()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L185-L203``）：

.. code-block:: systemverilog

     // Flush all scoreboard state (FIFOs, queues, counters)
     function void flush_state();
       eh2_trace_seq_item trash_item;
       axi4_seq_item trash_axi;

       while (trace_fifo.try_get(trash_item)) begin end
       while (dut_probe_fifo.try_get(trash_item)) begin end
       while (lsu_axi_fifo.try_get(trash_axi)) begin end

       for (int t = 0; t < 2; t++) begin
         pending_trace_q[t].delete();
         async_wb_q[t].delete();
         prev_mip[t] = 0;
       end
       pending_mem_access_q.delete();

       store_axi_delivered = 0;
       store_trace_stepped = 0;
     endfunction

逐段解释：

* 第 185~192 行：函数先用 ``try_get`` 清空 3 个 FIFO。trace/probe FIFO 共用
  ``eh2_trace_seq_item trash_item``，AXI FIFO 使用 ``axi4_seq_item trash_axi``。
* 第 194~198 行：对 2 个 thread 清空 ``pending_trace_q`` 和 ``async_wb_q``，并把
  ``prev_mip`` 置 0。
* 第 199 行：清空共享 ``pending_mem_access_q``。
* 第 201~202 行：store coalescing 计数器归零。

接口关系：

* 被调用：agent ``reset`` helper 和 ``run_reset_monitor``。
* 调用：FIFO ``try_get``、queue ``delete``。
* 共享状态：3 个 FIFO、per-thread 队列、memory queue、store counters。

§7  trace/probe/AXI 三个运行任务
------------------------------------------------------------------------------------------------------------------------

职责：三个 forever task 分别处理退役 trace、DUT probe 异步写回和 LSU AXI4 事务。
它们都只在 ``cosim_handle != null && initialized`` 后推进 pending trace。

§7.1  ``run_cosim_trace()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L206-L224``）：

.. code-block:: systemverilog

     // Process trace items - each carries its own wb data from the RTL trace pkt.
     task run_cosim_trace();
       eh2_trace_seq_item trace_item;

       forever begin
         trace_fifo.get(trace_item);
         trace_item_count++;

         if (cosim_handle != null && initialized) begin
           pending_trace_t pending;
           int tid = int'(trace_item.thread_id);
           pending.item = trace_item;
           pending_trace_q[tid].push_back(pending);
           if (pending_trace_q[tid].size() > pending_trace_high_watermark) begin
             pending_trace_high_watermark = pending_trace_q[tid].size();
           end
           process_pending_trace(tid);
         end
       end
     endtask

逐段解释：

* 第 206~211 行：任务从 ``trace_fifo`` 阻塞读取 trace item，并递增
  ``trace_item_count``。
* 第 213~217 行：只有 Spike handle 已初始化时，才按 ``trace_item.thread_id`` 选取
  thread 队列并 push pending trace。
* 第 218~220 行：更新 pending trace high watermark。
* 第 221 行：调用 ``process_pending_trace(tid)`` 尝试按序 step。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：``trace_fifo.get``、``process_pending_trace``。
* 共享状态：``pending_trace_q[tid]``、``pending_trace_high_watermark``。

§7.2  ``run_cosim_probe_async()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L226-L258``）：

.. code-block:: systemverilog

     // Async writeback hints (NB-load wb / DIV completion / DIV cancel).
     task run_cosim_probe_async();
       eh2_trace_seq_item probe_item;
       async_wb_hint_t hint;

       forever begin
         dut_probe_fifo.get(probe_item);
         probe_item_count++;

         // Drop regular writebacks - the trace channel already carries them.
         if (probe_item.wb_source == EH2_WB_SRC_REGULAR) continue;

         hint.rd       = probe_item.wb_dest;
         hint.rd_data  = probe_item.wb_data;
         hint.suppress = probe_item.wb_suppress;
         hint.source   = probe_item.wb_source;
         hint.wb_tag   = probe_item.wb_tag;  // strict ordering tag (issue 66)

逐段解释：

* 第 226~233 行：任务从 ``dut_probe_fifo`` 读取 probe item，并递增
  ``probe_item_count``。
* 第 235~236 行：regular writeback 直接丢弃，因为 trace channel 已经携带 regular
  writeback 视图。
* 第 238~242 行：非 regular probe item 被转换为 ``async_wb_hint_t``，字段包括
  ``rd``、``rd_data``、``suppress``、``source`` 和 ``wb_tag``。
* 第 244~255 行：源文件随后按 ``thread_id`` push 到 ``async_wb_q[tid]``，打印
  ``ASYNC_WB`` 日志，并在 cosim 初始化后调用 ``process_pending_trace(tid)``。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：``dut_probe_fifo.get``、``process_pending_trace``。
* 共享状态：``async_wb_q[tid]`` 和 ``probe_item_count``。

§7.3  ``run_cosim_dmem()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L260-L275``）：

.. code-block:: systemverilog

     // Monitor LSU AXI4 transactions for memory access notification
     task run_cosim_dmem();
       axi4_seq_item axi_txn;

       forever begin
         lsu_axi_fifo.get(axi_txn);
         axi_item_count++;

         if (cosim_handle != null && initialized) begin
           enqueue_memory_accesses(axi_txn);
           // Try to unblock both threads
           process_pending_trace(0);
           process_pending_trace(1);
         end
       end
     endtask

逐段解释：

* 第 260~266 行：任务从 ``lsu_axi_fifo`` 读取 AXI transaction，并递增
  ``axi_item_count``。
* 第 268~269 行：cosim 初始化后调用 ``enqueue_memory_accesses``，把 AXI transaction
  放入共享 memory queue。
* 第 270~272 行：LSU AXI4 bus 是共享资源，因此新 memory access 可能解除任一 thread
  的 pending trace 阻塞；代码对 thread 0 和 thread 1 都调用
  ``process_pending_trace``。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：``lsu_axi_fifo.get``、``enqueue_memory_accesses``、``process_pending_trace``。
* 共享状态：``pending_mem_access_q`` 和 ``axi_item_count``。

§8  pending trace gating 与分类函数
------------------------------------------------------------------------------------------------------------------------

职责：scoreboard 不会所有 trace item 一到就立即 step。store/AMO 要等待 LSU AXI
access，DIV 和 NB-load 要等待 matching async writeback hint。

§8.1  ``needs_async_wb()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L277-L286``）：

.. code-block:: systemverilog

     // True if the trace item describes an instruction whose architectural
     // writeback arrives on an async channel (DIV unit / NB-load) instead of
     // the regular pipeline. Wait for the matching async hint before stepping.
     function bit needs_async_wb(eh2_trace_seq_item item);
       if (item.exception || item.interrupt) return 1'b0;
       if (!item.writes_rd()) return 1'b0;
       if (item.is_div()) return 1'b1;
       if (needs_nb_load_async_wb(item)) return 1'b1;
       return 1'b0;
     endfunction

逐段解释：

* 第 277~280 行：函数只判断某条 trace item 是否需要等待 async writeback。
* 第 281 行：异常或中断 item 不等待 async writeback。
* 第 282 行：不写 GPR 的指令不等待。
* 第 283~284 行：DIV 指令和 NB-load 类 load 指令需要等待。
* 第 285 行：其它情况返回 0。

接口关系：

* 被调用：``process_pending_trace``。
* 调用：``item.writes_rd``、``item.is_div``、``needs_nb_load_async_wb``。
* 共享状态：无；纯组合判断。

§8.2  ``process_pending_trace()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L288-L327``）：

.. code-block:: systemverilog

     // Drain pending_trace_q[tid] in order. Gates:
     //   - stores/AMOs wait for matching LSU AXI access (with coalescing bypass)
     //   - DIV / NB-load trace items wait for the matching async writeback hint
     function void process_pending_trace(int tid);
       while (pending_trace_q[tid].size() > 0) begin
         pending_trace_t pending = pending_trace_q[tid][0];

         if (must_wait_for_memory_access(pending.item) &&
             !has_matching_memory_access(pending.item)) begin
           if (store_trace_stepped > store_axi_delivered) begin
             `uvm_info("cosim", $sformatf(
               "T%0d Store at PC=%08x insn=%08x — coalesced (stepped=%0d > axi=%0d), proceeding without AXI",
               tid, pending.item.pc, pending.item.insn, store_trace_stepped, store_axi_delivered), UVM_LOW)
           end else begin
             `uvm_info("cosim", $sformatf(
               "T%0d Waiting for LSU AXI access before stepping store/AMO PC=%08x insn=%08x (stepped=%0d, axi=%0d)",
               tid, pending.item.pc, pending.item.insn, store_trace_stepped, store_axi_delivered), UVM_HIGH)
             break;
           end

逐段解释：

* 第 288~293 行：函数只处理指定 ``tid`` 的 pending trace 队列，并始终查看队首。
* 第 295~296 行：如果该 item 必须等待 memory access 且当前没有 matching AXI access，
  进入 gating 逻辑。
* 第 297~300 行：当 ``store_trace_stepped > store_axi_delivered`` 时，认为存在
  coalesced store 场景，允许继续。
* 第 301~305 行：否则打印等待 LSU AXI access 的日志，并 ``break``，保持队首不弹出。
* 第 309~325 行：源文件随后检查 async writeback gate，通过后 pop 队首、消费 matching
  memory access、更新 store trace counter，并调用 ``compare_instruction``。

接口关系：

* 被调用：trace、probe、dmem 三个任务都会调用。
* 调用：``must_wait_for_memory_access``、``has_matching_memory_access``、
  ``needs_async_wb``、``has_matching_async_wb``、``pop_matching_memory_access``、
  ``compare_instruction``。
* 共享状态：``pending_trace_q[tid]``、store counters、memory queue、async queue。

§8.3  memory/load/store 分类函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L350-L380``）：

.. code-block:: systemverilog

     function bit is_memory_instruction(eh2_trace_seq_item item);
       if (item.is_load() || item.is_store() || item.is_amo()) begin
         return 1'b1;
       end
       return item.is_compressed_load_store();
     endfunction

     function bit is_load_instruction(eh2_trace_seq_item item);
       return item.is_load() ||
              is_lr_instruction(item) ||
              (item.is_compressed_load_store() && item.writes_rd());
     endfunction

     function bit is_store_or_amo_instruction(eh2_trace_seq_item item);
       return item.is_store() ||
              (item.is_compressed_load_store() && !item.writes_rd());
     endfunction

     function bit is_lr_instruction(eh2_trace_seq_item item);
       return item.is_amo() && item.insn[31:27] == 5'b00010;
     endfunction

逐段解释：

* 第 350~355 行：普通 load/store/AMO 都算 memory instruction；compressed load/store
  也算。
* 第 357~361 行：load instruction 包含普通 load、LR，以及写 rd 的 compressed
  load/store item。
* 第 363~366 行：store/AMO 判断包含普通 store，以及不写 rd 的 compressed
  load/store item。函数名包含 AMO，但代码没有把所有 ``item.is_amo()`` 归入此返回值；
  LR 在前一个函数里单独作为 load 处理。
* 第 368~370 行：LR 判断为 ``item.is_amo()`` 且 ``insn[31:27] == 5'b00010``。

接口关系：

* 被调用：``process_pending_trace``、``has_matching_async_wb``、``notify`` 相关函数。
* 调用：``eh2_trace_seq_item`` 的 helper 方法。
* 共享状态：无；依赖 trace item 字段。

§8.4  ``eh2_trace_seq_item`` 中的分类来源
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L152-L174``）：

.. code-block:: systemverilog

     // Check if instruction is a load
     function bit is_load();
       return (get_opcode() == 7'b0000011);
     endfunction

     // Check if instruction is a store
     function bit is_store();
       return (get_opcode() == 7'b0100011);
     endfunction

     // Check if instruction is an atomic memory operation
     function bit is_amo();
       return (get_opcode() == 7'b0101111);
     endfunction

     // Check if instruction is a DIV/REM operation. MUL operations use the same
     // opcode/funct7 but write through the normal pipeline, not the DIV monitor.
     function bit is_div();
       if (is_compressed()) return 1'b0;
       return (get_opcode() == 7'b0110011 &&

逐段解释：

* 第 152~164 行：trace item 的 load/store/AMO 分类来自 opcode，不由 scoreboard 重复
  解码完整指令格式。
* 第 167~174 行：DIV/REM 判断排除 compressed 指令，并要求 opcode ``0110011``、
  ``funct7=0000001``、``funct3`` 在 100/101/110/111 之间。源注释明确 MUL 同 opcode 和
  funct7，但走 regular pipeline，不走 DIV monitor。
* 第 183~224 行：同文件还提供 compressed load/store、``get_write_rd`` 和
  ``writes_rd``，scoreboard 的 gating 逻辑依赖这些 helper。

接口关系：

* 被调用：scoreboard 分类函数。
* 调用：``get_opcode``、``is_compressed``。
* 共享状态：``insn`` 字段。

§9  async writeback 与 ``wb_tag`` 严格匹配
------------------------------------------------------------------------------------------------------------------------

职责：NB-load、DIV completion 和 DIV cancel 等异步写回通过 DUT probe 进入
``async_wb_q``。scoreboard 使用 ``wb_tag`` 严格匹配 trace item 和 async hint，不使用
rd fallback。该行为对应 :ref:`adr-0018`。

§9.1  ``has_matching_async_wb()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L329-L348``）：

.. code-block:: systemverilog

     function bit has_matching_async_wb(int tid, eh2_trace_seq_item item);
       if (!item.writes_rd()) return 1'b0;

       if (item.is_div()) begin
         foreach (async_wb_q[tid][i]) begin
           if (async_wb_q[tid][i].source == EH2_WB_SRC_DIV) begin
             if (async_wb_q[tid][i].wb_tag == item.wb_tag) return 1'b1;
           end
         end
         return 1'b0;
       end

       if (is_load_instruction(item)) begin
         foreach (async_wb_q[tid][i]) begin
           if (async_wb_q[tid][i].source != EH2_WB_SRC_NB_LOAD) continue;
           if (async_wb_q[tid][i].wb_tag > 0 && async_wb_q[tid][i].wb_tag == item.wb_tag) return 1'b1;
         end
       end
       return 1'b0;
     endfunction

逐段解释：

* 第 329~330 行：不写 rd 的 item 没有 matching async writeback。
* 第 332~339 行：DIV 路径只接受 ``source == EH2_WB_SRC_DIV`` 且 ``wb_tag`` 相等的 hint。
* 第 341~346 行：load 路径只接受 ``EH2_WB_SRC_NB_LOAD``，并要求 hint ``wb_tag > 0`` 且
  等于 trace item 的 ``wb_tag``。
* 第 347 行：其它情况返回 0。

接口关系：

* 被调用：``process_pending_trace``。
* 调用：``item.writes_rd``、``item.is_div``、``is_load_instruction``。
* 共享状态：``async_wb_q[tid]``。

§9.2  ``try_consume_async_wb()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L391-L447``）：

.. code-block:: systemverilog

     // Try to consume an async writeback hint that matches this instruction.
     // Strict wb_tag-only matching (issue 66). No rd-based fallback.
     function bit try_consume_async_wb(int tid, eh2_trace_seq_item item,
                                       output async_wb_hint_t hint);
       bit [4:0] expected_rd;
       bit       found_wrong_tag;
       int       wrong_tag_val;
       if (!item.writes_rd()) return 1'b0;
       expected_rd = item.get_write_rd();

       if (item.is_div()) begin
         found_wrong_tag = 0;
         foreach (async_wb_q[tid][i]) begin
           if (async_wb_q[tid][i].source != EH2_WB_SRC_DIV) continue;
           if (async_wb_q[tid][i].wb_tag == item.wb_tag) begin
             hint = async_wb_q[tid][i];
             async_wb_q[tid].delete(i);
             return 1'b1;

逐段解释：

* 第 391~399 行：函数输出 matching hint；没有 rd 写回则返回 0，``expected_rd`` 用于错误日志。
* 第 401~409 行：DIV 路径遍历 ``async_wb_q[tid]``，跳过非 DIV hint，找到同
  ``wb_tag`` 的 hint 后复制到输出、删除队列元素并返回 1。
* 第 410~421 行：若只有错误 tag，函数递增 ``mismatch_count[tid]`` 并报
  ``DIV wb_tag mismatch``。
* 第 424~446 行：源文件对 NB-load 执行同样的 strict ``wb_tag`` 消费逻辑，错误时
  报 ``NB-LOAD wb_tag mismatch``。

接口关系：

* 被调用：``compare_instruction``。
* 调用：``item.writes_rd``、``item.get_write_rd``、``item.is_div``、
  ``is_load_instruction``。
* 共享状态：``async_wb_q[tid]`` 和 ``mismatch_count[tid]``。

§10  memory access 队列与 Spike D-side 通知
------------------------------------------------------------------------------------------------------------------------

职责：LSU AXI4 monitor 给出的 transaction 先进入 ``pending_mem_access_q``。当
store/AMO trace item 可以 step 时，scoreboard 弹出 matching memory access，并调用
``riscv_cosim_notify_dside_access``。

§10.1  ``enqueue_memory_accesses()`` 与 observed access count
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L449-L474``）：

.. code-block:: systemverilog

     function void enqueue_memory_accesses(axi4_seq_item txn);
       pending_mem_access_t access;
       access.txn = txn;
       access.is_store = (txn.tx_type == axi4_seq_item::AXI4_WRITE);
       access.observed_access_count = count_observed_memory_accesses(txn);
       pending_mem_access_q.push_back(access);
       if (access.is_store) store_axi_delivered++;
     endfunction

     function int count_observed_memory_accesses(axi4_seq_item txn);
       int observed_access_count;
       observed_access_count = 0;

       if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
         for (int i = 0; i < txn.get_beat_count(); i++) begin
           bit [7:0] beat_strb = txn.strb[i];

逐段解释：

* 第 449~455 行：函数把 AXI transaction 包装为 pending memory access，写入
  ``is_store`` 和 ``observed_access_count``，并 push 到共享队列。
* 第 455 行：若该 access 是 store，则递增 ``store_axi_delivered``。
* 第 458~461 行：``count_observed_memory_accesses`` 从 0 开始计数。
* 第 462~468 行：write transaction 按 beat 统计低 4 位 strobe 和高 4 位 strobe 是否
  非零；当 beat bytes 大于 4 时才统计高半。
* 第 469~473 行：read transaction 的 observed count 直接等于 beat count。

接口关系：

* 被调用：``run_cosim_dmem``。
* 调用：``txn.get_beat_count``。
* 共享状态：``pending_mem_access_q`` 和 ``store_axi_delivered``。

§10.2  matching memory access 消费
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L476-L504``）：

.. code-block:: systemverilog

     function bit has_matching_memory_access(eh2_trace_seq_item item);
       bit need_store;
       need_store = is_store_or_amo_instruction(item);

       foreach (pending_mem_access_q[i]) begin
         if (pending_mem_access_q[i].is_store == need_store) return 1'b1;
       end

       return 1'b0;
     endfunction

     function void pop_matching_memory_access(eh2_trace_seq_item item);
       bit need_store;
       int tid;
       need_store = is_store_or_amo_instruction(item);
       tid = int'(item.thread_id);

       foreach (pending_mem_access_q[i]) begin

逐段解释：

* 第 476~484 行：matching 条件只比较 access 是否为 store 类。``need_store`` 来自
  ``is_store_or_amo_instruction(item)``。
* 第 487~491 行：消费函数重新计算 ``need_store``，并从 item 取 ``thread_id``。
* 第 493~497 行：找到 matching entry 后调用 ``notify_memory_access(tid, txn)``，
  删除该队列元素并返回。
* 第 501~503 行：如果没有 matching entry，报 internal error，并打印 thread、PC 和
  insn。

接口关系：

* 被调用：``process_pending_trace``。
* 调用：``is_store_or_amo_instruction``、``notify_memory_access``。
* 共享状态：``pending_mem_access_q``。

§10.3  AXI4 write 通知拆分
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L506-L535``）：

.. code-block:: systemverilog

     // Notify Spike about a memory access from the AXI4 bus.
     // AXI4 bus is 64-bit; split 64-bit beats into two 32-bit notifications.
     function void notify_memory_access(int tid, axi4_seq_item txn);
       if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
         bit write_error = (txn.resp[0] != axi4_seq_item::AXI4_RESP_OKAY);

         for (int i = 0; i < txn.get_beat_count(); i++) begin
           bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
           bit [63:0] beat_data = txn.data[i];
           bit [7:0]  beat_strb = txn.strb[i];
           int beat_bytes = (1 << txn.size);

           if (beat_strb[3:0] != 4'b0) begin
             riscv_cosim_notify_dside_access(cosim_handle,
               1, int'(beat_data[31:0]), int'(beat_addr),
               int'({4'b0, beat_strb[3:0]}),
               int'(write_error), 0, 0, 0, 1, 0, tid);

逐段解释：

* 第 506~508 行：函数注释明确 AXI4 bus 为 64 bit，并拆成 32 bit 通知。
* 第 509~516 行：write transaction 先计算 ``write_error``，再逐 beat 取地址、64 bit
  data、8 bit strobe 和 beat bytes。
* 第 518~524 行：低半 strobe 非零时调用 ``riscv_cosim_notify_dside_access``，store
  参数为 1，data 使用 ``beat_data[31:0]``，byte enable 使用低 4 bit。
* 第 527~534 行：源文件随后在 ``beat_bytes > 4`` 且高半 strobe 非零时，对
  ``beat_addr + 4`` 和 ``beat_data[63:32]`` 再发一次通知。

接口关系：

* 被调用：``pop_matching_memory_access``。
* 调用：``riscv_cosim_notify_dside_access`` 和 ``txn.get_beat_count``。
* 共享状态：``cosim_handle``。

§10.4  AXI4 read 通知拆分
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L536-L562``）：

.. code-block:: systemverilog

       end else begin
         for (int i = 0; i < txn.get_beat_count(); i++) begin
           bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
           bit [63:0] beat_data = txn.rdata[i];
           bit read_error = (txn.resp[i] != axi4_seq_item::AXI4_RESP_OKAY);
           int beat_bytes = (1 << txn.size);
           bit widened_load = (beat_bytes > 4);
           bit [3:0] read_be = ((4'b0001 << beat_bytes) - 1) << beat_addr[1:0];

           riscv_cosim_notify_dside_access(cosim_handle,
             0, int'(beat_data[31:0]), int'(beat_addr),
             int'(read_be), int'(read_error),
             0, 0, 0, 1, int'(widened_load), tid);
           `uvm_info("cosim", $sformatf("T%0d MEM RD: addr=%08x data=%08x",
             tid, beat_addr, beat_data[31:0]), UVM_HIGH)

逐段解释：

* 第 536~543 行：read transaction 每个 beat 取 ``rdata``，用当前 beat 的 ``resp``
  计算 ``read_error``，并根据 beat bytes 计算 ``widened_load`` 与 ``read_be``。
* 第 545~550 行：低 32 bit read data 通过 ``riscv_cosim_notify_dside_access`` 通知
  Spike，store 参数为 0。
* 第 552~558 行：源文件随后在 ``beat_bytes > 4`` 时，用 ``beat_addr + 4`` 和
  ``beat_data[63:32]`` 再发一次读通知，byte enable 固定为 ``4'hf``。
* 第 561~562 行：函数结束，不返回状态。

接口关系：

* 被调用：``pop_matching_memory_access``。
* 调用：``riscv_cosim_notify_dside_access``。
* 共享状态：``cosim_handle``。

§11  ``compare_instruction()`` — Spike step 与 mismatch
------------------------------------------------------------------------------------------------------------------------

职责：``compare_instruction`` 是 scoreboard 的核心函数。它从 trace pkt 取写回视图，
应用 async override，按固定顺序通知 Spike debug/NMI/MIP/mcycle/iside error，然后
调用 ``riscv_cosim_step``。

§11.1  IRQ-only 路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L573-L610``）：

.. code-block:: systemverilog

       // EH2: When interrupt=1 and exception=0, the trace item is only an
       // interrupt notification (no instruction executed at this PC).
       if (item.interrupt && !item.exception) begin
         riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req), tid);
         riscv_cosim_set_nmi(cosim_handle, int'(item.nmi), tid);
         riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int), tid);
         riscv_cosim_set_mip(cosim_handle, int'(prev_mip[tid]), int'(item.mip), tid);
         prev_mip[tid] = item.mip;
         riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle), tid);
         `uvm_info("cosim", $sformatf("T%0d IRQ-ONLY: PC=%08x", tid, item.pc), UVM_HIGH)

         // Compare trap CSRs on interrupt path — upgraded to mismatch (issue 51)
         begin
           int unsigned spike_mcause, spike_mepc;
           spike_mcause = riscv_cosim_get_mcause(cosim_handle, tid);

逐段解释：

* 第 573~575 行：当 ``interrupt=1`` 且 ``exception=0`` 时，trace item 被视为纯中断通知，
  不代表该 PC 有一条指令执行。
* 第 576~581 行：该路径仍按顺序通知 Spike debug_req、NMI、NMI internal、MIP 和
  mcycle，并更新 ``prev_mip[tid]``。
* 第 584~588 行：随后读取 Spike 的 ``mcause`` 和 ``mepc``。
* 第 590~607 行：源文件比较 DUT 与 Spike 的 ``mcause``/``mepc``，不一致时递增
  ``mismatch_count[tid]`` 并报错。
* 第 609 行：IRQ-only 路径直接 ``return``，不会调用 ``riscv_cosim_step``。

接口关系：

* 被调用：``process_pending_trace``。
* 调用：``riscv_cosim_set_debug_req``、``riscv_cosim_set_nmi``、
  ``riscv_cosim_set_nmi_int``、``riscv_cosim_set_mip``、``riscv_cosim_set_mcycle``、
  ``riscv_cosim_get_mcause``、``riscv_cosim_get_mepc``。
* 共享状态：``prev_mip[tid]``、``mismatch_count[tid]``。

§11.2  写回来源与 async override
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L612-L638``）：

.. code-block:: systemverilog

       // Pull writeback view directly from the trace packet (RVFI-equivalent).
       if (item.wb_valid && item.wb_dest != 0) begin
         write_reg          = item.wb_dest;
         write_reg_data     = item.wb_data;
         suppress_reg_write = 0;
       end else begin
         write_reg          = 0;
         write_reg_data     = 0;
         suppress_reg_write = 0;
       end

       // Async overrides
       if (try_consume_async_wb(tid, item, async_hint)) begin
         if (async_hint.suppress) begin
           suppress_reg_write = 1;
           write_reg          = 0;
           write_reg_data     = 0;
         end else begin
           write_reg          = async_hint.rd;
           write_reg_data     = async_hint.rd_data;
           suppress_reg_write = 0;

逐段解释：

* 第 612~620 行：regular 写回视图直接来自 trace pkt 的 ``wb_valid``、
  ``wb_dest`` 和 ``wb_data``。目的寄存器为 x0 时不作为写回传给 Spike。
* 第 623~624 行：函数尝试消费 matching async writeback hint。
* 第 625~628 行：如果 hint 标记 ``suppress``，则 suppress register write，并把
  ``write_reg`` 和 ``write_reg_data`` 清 0。
* 第 629~633 行：非 suppress hint 覆盖写回寄存器和值。
* 第 634~638 行：源文件随后对未拿到 async hint 的 DIV item 也 suppress 写回。

接口关系：

* 被调用：``compare_instruction`` 内部顺序逻辑。
* 调用：``try_consume_async_wb``。
* 共享状态：``async_wb_q[tid]``。

§11.3  Spike 通知顺序和 ``riscv_cosim_step``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L640-L657``）：

.. code-block:: systemverilog

       sync_trap = item.exception && !item.interrupt;

       // Spike notification ordering (Ibex pattern)
       riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req), tid);
       riscv_cosim_set_nmi(cosim_handle, int'(item.nmi), tid);
       riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int), tid);
       riscv_cosim_set_mip(cosim_handle, int'(prev_mip[tid]), int'(item.mip), tid);
       prev_mip[tid] = item.mip;
       riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle), tid);
       if (item.exception && !item.interrupt && item.ecause == 5'd1) begin
         riscv_cosim_set_iside_error(cosim_handle, int'(item.pc), tid);
       end

       result = riscv_cosim_step(cosim_handle,
         int'(write_reg), int'(write_reg_data),
         int'(item.pc), sync_trap ? 1 : 0,
         suppress_reg_write ? 1 : 0, tid);

逐段解释：

* 第 640 行：``sync_trap`` 只在 exception 且非 interrupt 时为真。
* 第 643~648 行：Spike 通知顺序是 debug_req、NMI、NMI internal、MIP、mcycle。
  ``set_mip`` 使用 ``prev_mip[tid]`` 和当前 ``item.mip``，随后更新 ``prev_mip``。
* 第 649~651 行：如果是 instruction access fault 类 exception（``ecause == 5'd1``），
  额外调用 ``riscv_cosim_set_iside_error``。
* 第 653~657 行：``riscv_cosim_step`` 传入 writeback 寄存器、写回数据、PC、
  sync trap 标志、suppress 标志和 thread id。

接口关系：

* 被调用：``compare_instruction``。
* 调用：``riscv_cosim_set_debug_req``、``riscv_cosim_set_nmi``、
  ``riscv_cosim_set_nmi_int``、``riscv_cosim_set_mip``、``riscv_cosim_set_mcycle``、
  ``riscv_cosim_set_iside_error``、``riscv_cosim_step``。
* 共享状态：``prev_mip[tid]`` 和 ``cosim_handle``。

§11.4  mismatch、trap CSR 比对和 error string
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L658-L713``）：

.. code-block:: systemverilog

       if (result == 0) begin
         mismatch_count[tid]++;
         `uvm_info("cosim", $sformatf(
           "T%0d MISMATCH: PC=%08x insn=%08x slot=%0d rd=x%0d data=%08x",
           tid, item.pc, item.insn, item.slot, write_reg, write_reg_data), UVM_LOW)
         if (fatal_on_mismatch) begin
           `uvm_fatal("cosim", $sformatf("T%0d MISMATCH at PC=%08x insn=%08x\n%s",
             tid, item.pc, item.insn, get_cosim_error_str()))
         end else begin
           `uvm_error("cosim", $sformatf("T%0d MISMATCH at PC=%08x insn=%08x\n%s",
             tid, item.pc, item.insn, get_cosim_error_str()))
         end
       end else begin
         `uvm_info("cosim", $sformatf("T%0d MATCH: PC=%08x insn=%08x rd=x%0d data=%08x",
           tid, item.pc, item.insn, write_reg, write_reg_data), UVM_HIGH)

逐段解释：

* 第 658~663 行：``riscv_cosim_step`` 返回 0 表示 mismatch，scoreboard 递增
  ``mismatch_count[tid]`` 并打印 PC、insn、slot、rd 和 data。
* 第 663~669 行：``fatal_on_mismatch`` 为真时报 ``uvm_fatal``，否则报
  ``uvm_error``；两者都附带 ``get_cosim_error_str`` 返回的 Spike 错误信息。
* 第 670~673 行：step 成功时打印 MATCH 日志。
* 第 675~700 行：源文件随后在同步 trap 且 step 成功时，读取 Spike ``mcause`` 与
  ``mepc``，和 trace item 中的 ``dut_mcause``/``dut_mepc`` 比对。
* 第 705~713 行：``get_cosim_error_str`` 会读取错误数量、逐条拼接错误字符串，然后
  调用 ``riscv_cosim_clear_errors``。

接口关系：

* 被调用：``compare_instruction``。
* 调用：``get_cosim_error_str``、``riscv_cosim_get_mcause``、
  ``riscv_cosim_get_mepc``、``riscv_cosim_get_num_errors``、
  ``riscv_cosim_get_error``、``riscv_cosim_clear_errors``。
* 共享状态：``mismatch_count[tid]``。

§12  初始化、binary loader 和 CSR 预注册
------------------------------------------------------------------------------------------------------------------------

职责：scoreboard 初始化 Spike、注册 memory region 和 EH2 custom CSR，并负责把测试
binary 写入 Spike memory model。binary loader 和 CSR 预注册被拆到 ``.svh`` 文件，但
都从 scoreboard 内部 include。

§12.1  ``init_cosim()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L719-L757``）：

.. code-block:: systemverilog

     protected function void init_cosim();
       cleanup_cosim();

       if (enable_cosim) begin
         cosim_handle = riscv_cosim_init(cosim_config);
         if (cosim_handle == null) begin
           `uvm_fatal("cosim", "Failed to initialize co-simulation")
         end
         initialized = 1;

         // Register all DUT-accessible memory regions with Spike (from cfg — issue 65).
         if (cfg != null) begin
           riscv_cosim_add_memory(cosim_handle, cfg.mem_boot.base,      cfg.mem_boot.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_debug_sb.base,  cfg.mem_debug_sb.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_ext_data1.base, cfg.mem_ext_data1.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_ext_data2.base, cfg.mem_ext_data2.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_iccm.base,      cfg.mem_iccm.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_dccm.base,      cfg.mem_dccm.size);

逐段解释：

* 第 719~720 行：初始化前先调用 ``cleanup_cosim``，销毁旧 handle。
* 第 722~727 行：``enable_cosim`` 为真时调用 ``riscv_cosim_init(cosim_config)``，
  空 handle 直接 ``uvm_fatal``，成功后设置 ``initialized``。
* 第 729~739 行：如果 cfg 存在，依次注册 boot、debug_sb、ext_data1、ext_data2、
  ICCM、DCCM、PIC、mailbox 和 NMI vector。
* 第 740~752 行：源文件对 cfg 为空提供 fallback memory regions，但会警告 ICCM/DCCM
  未注册。
* 第 754~757 行：include CSR preregister header 后打印
  ``Pre-registered 28 EH2 custom CSRs``。

接口关系：

* 被调用：``run_phase`` 和 reset deassertion 后的 ``run_reset_monitor``。
* 调用：``cleanup_cosim``、``riscv_cosim_init``、``riscv_cosim_add_memory``、
  CSR preregister include。
* 共享状态：``cosim_handle``、``initialized``、``cfg``。

§12.2  pending binary 与 reset reload
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L759-L785``）：

.. code-block:: systemverilog

         if (pending_bin_path != "") begin
           `uvm_info("cosim", $sformatf("Loading pending binary: %s at 0x%08x",
             pending_bin_path, pending_base_addr), UVM_LOW)
           load_binary(pending_bin_path, pending_base_addr);
           pending_bin_path = "";
         end
         else if (stored_bin_path != "") begin
           `uvm_info("cosim", "Reloading binary after reset recovery", UVM_LOW)
           load_binary(stored_bin_path, stored_base_addr);
         end
       end

       step_count = 0;
       trace_item_count = 0;
       probe_item_count = 0;
       suppressed_probe_item_count = 0;
       axi_item_count = 0;
       pending_trace_high_watermark = 0;
       for (int t = 0; t < 2; t++) begin
         mismatch_count[t] = 0;
         insn_cnt[t] = 0;
         prev_mip[t] = 0;
         pending_trace_q[t].delete();

逐段解释：

* 第 759~764 行：如果 test 在 run phase 前设置了 ``pending_bin_path``，初始化时加载
  pending binary，并清空 pending path。
* 第 765~768 行：如果没有 pending binary 但已有 ``stored_bin_path``，说明 reset 后
  需要 reload 上一次 binary。
* 第 771~776 行：初始化后清空 step、trace、probe、suppressed probe、AXI 计数和
  high watermark。
* 第 777~785 行：源文件随后对两个 thread 清 ``mismatch_count``、``insn_cnt``、
  ``prev_mip``、pending trace、async wb 和 pending memory access。

接口关系：

* 被调用：``init_cosim``。
* 调用：``load_binary``。
* 共享状态：``pending_bin_path``、``stored_bin_path``、各统计计数和队列。

§12.3  ``load_binary()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh:L14-L30``）：

.. code-block:: systemverilog

     function void load_binary(string bin_path, bit [31:0] base_addr);
       `uvm_info("cosim", $sformatf("Loading binary: %s at 0x%08x", bin_path, base_addr), UVM_LOW)

       if (cosim_handle == null) begin
         `uvm_error("cosim", "Cannot load binary: cosim not initialized")
         return;
       end

       if (bin_path.len() > 4 && bin_path.substr(bin_path.len()-4, bin_path.len()-1) == ".hex") begin
         load_hex(bin_path, base_addr);
       end else begin
         load_raw_binary(bin_path, base_addr);
       end

       stored_bin_path = bin_path;
       stored_base_addr = base_addr;
     endfunction

逐段解释：

* 第 14~20 行：函数先打印加载路径和 base address；如果 ``cosim_handle`` 为空，报错并
  返回。
* 第 22~26 行：路径后缀是 ``.hex`` 时调用 ``load_hex``，否则调用 ``load_raw_binary``。
* 第 28~29 行：保存路径和 base address，供 reset recovery reload 使用。

接口关系：

* 被调用：agent ``load_binary_to_mem``、scoreboard ``init_cosim``。
* 调用：``load_hex``、``load_raw_binary``。
* 共享状态：``stored_bin_path``、``stored_base_addr``。

§12.4  raw binary loader
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh:L32-L59``）：

.. code-block:: systemverilog

     function void load_raw_binary(string bin_path, bit [31:0] base_addr);
       int fd;
       int byte_val;
       bit [7:0] mem_byte;
       bit [31:0] addr;
       int bytes_loaded;

       fd = $fopen(bin_path, "rb");
       if (fd == 0) begin
         `uvm_error("cosim", $sformatf("Cannot open binary file: %s", bin_path))
         return;
       end

       addr = base_addr;
       bytes_loaded = 0;
       while (!$feof(fd)) begin
         byte_val = $fread(mem_byte, fd);
         if (byte_val == 1) begin
           riscv_cosim_write_mem_byte(cosim_handle, int'(addr), int'(mem_byte));

逐段解释：

* 第 32~37 行：函数声明文件句柄、读字节返回值、当前 byte、地址和加载计数。
* 第 39~43 行：以 ``rb`` 模式打开文件，失败时报 ``uvm_error`` 并返回。
* 第 45~46 行：地址从 ``base_addr`` 开始，加载计数清零。
* 第 47~54 行：循环读取 byte；``$fread`` 返回 1 时调用
  ``riscv_cosim_write_mem_byte``，然后地址和计数递增。
* 第 55~58 行：源文件随后关闭文件并打印 loaded byte 数。

接口关系：

* 被调用：``load_binary``。
* 调用：``$fopen``、``$fread``、``riscv_cosim_write_mem_byte``、``$fclose``。
* 共享状态：``cosim_handle``。

§12.5  Verilog HEX loader
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh:L61-L98``）：

.. code-block:: systemverilog

     function void load_hex(string hex_path, bit [31:0] base_addr);
       int fd;
       int addr;
       int c;
       bit [7:0] val;
       int nybble_count;
       int bytes_loaded;

       fd = $fopen(hex_path, "r");
       if (fd == 0) begin
         `uvm_error("cosim", $sformatf("Cannot open hex file: %s", hex_path))
         return;
       end

       addr = base_addr;
       bytes_loaded = 0;
       nybble_count = 0;
       val = 0;

       while (!$feof(fd)) begin
         c = $fgetc(fd);
         if (c < 0) break;

         if (c == "@") begin
           int new_addr;
           new_addr = 0;
           while (!$feof(fd)) begin

逐段解释：

* 第 61~67 行：HEX loader 使用字符级 parser，维护当前地址、字符、byte 值、nybble
  计数和加载计数。
* 第 69~73 行：以文本模式打开 HEX 文件，失败时报错返回。
* 第 75~78 行：默认地址为 ``base_addr``，``val`` 和 ``nybble_count`` 清零。
* 第 80~84 行：循环读取字符；遇到 ``@`` 时进入地址解析分支。
* 第 85~98 行：源文件随后解析 ``@ADDR`` 十六进制地址，并在普通 hex 字符或空白字符
  分支中写入 byte。

接口关系：

* 被调用：``load_binary``。
* 调用：``$fopen``、``$fgetc``、``riscv_cosim_write_mem_byte``、``$fclose``。
* 共享状态：``cosim_handle``。

§12.6  CSR 预注册表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh:L14-L41``）：

.. code-block:: systemverilog

         riscv_cosim_set_csr(cosim_handle, 32'h7FF, 0, 0);  // mscause
         riscv_cosim_set_csr(cosim_handle, 32'h7C0, 0, 0);  // mrac
         riscv_cosim_set_csr(cosim_handle, 32'h7F9, 0, 0);  // mfdc
         riscv_cosim_set_csr(cosim_handle, 32'h7F8, 0, 0);  // mcgc
         riscv_cosim_set_csr(cosim_handle, 32'h7C6, 0, 0);  // mpmc
         riscv_cosim_set_csr(cosim_handle, 32'h7C2, 0, 0);  // mcpc
         riscv_cosim_set_csr(cosim_handle, 32'h7C4, 0, 0);  // dmst
         riscv_cosim_set_csr(cosim_handle, 32'h7CE, 0, 0);  // mfdht
         riscv_cosim_set_csr(cosim_handle, 32'h7CF, 0, 0);  // mfdhs
         riscv_cosim_set_csr(cosim_handle, 32'h7FC, 0, 0);  // mhartstart
         riscv_cosim_set_csr(cosim_handle, 32'h7FE, 0, 0);  // mnmipdel
         riscv_cosim_set_csr(cosim_handle, 32'h7D2, 0, 0);  // mitcnt0
         riscv_cosim_set_csr(cosim_handle, 32'h7D5, 0, 0);  // mitcnt1
         riscv_cosim_set_csr(cosim_handle, 32'h7D3, 0, 0);  // mitb0
         riscv_cosim_set_csr(cosim_handle, 32'h7D6, 0, 0);  // mitb1
         riscv_cosim_set_csr(cosim_handle, 32'h7D4, 0, 0);  // mitctl0
         riscv_cosim_set_csr(cosim_handle, 32'h7D7, 0, 0);  // mitctl1

逐段解释：

* 第 14~17 行：先注册 ``mscause``、``mrac``、``mfdc``、``mcgc``，初值均为 0，
  thread id 参数也为 0。
* 第 18~23 行：继续注册 ``mpmc``、``mcpc``、``dmst``、``mfdht``、``mfdhs`` 和
  ``mhartstart``。
* 第 24~30 行：注册 NMI/PIC timer 相关 CSR：``mnmipdel``、``mitcnt0/1``、
  ``mitb0/1``、``mitctl0/1``。
* 第 31~41 行：源文件后续注册 ``mdeau``、``mdseac``、ECC、PIC external interrupt
  CSR 等，一共 28 个 EH2 custom CSR。

接口关系：

* 被调用：``init_cosim`` 的 include 点。
* 调用：``riscv_cosim_set_csr``。
* 共享状态：``cosim_handle``。

§13  report/final/pre_abort
------------------------------------------------------------------------------------------------------------------------

职责：scoreboard 在 report phase 汇总 trace/probe/AXI 计数、pending 队列、step 数和
mismatch 数；final/pre_abort 负责销毁 Spike handle。

§13.1  ``report_phase()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L795-L837``）：

.. code-block:: systemverilog

     function void report_phase(uvm_phase phase);
       int total_mismatch;
       int total_pending_trace;
       int total_pending_async;

       super.report_phase(phase);

       total_mismatch = mismatch_count[0] + mismatch_count[1];
       total_pending_trace = pending_trace_q[0].size() + pending_trace_q[1].size();
       total_pending_async = async_wb_q[0].size() + async_wb_q[1].size();

       `uvm_info("cosim", "=== Co-simulation Scoreboard Report ===", UVM_LOW)
       `uvm_info("cosim", $sformatf("Trace items received: %0d", trace_item_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("Probe items received: %0d (async-only)", probe_item_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("AXI items received: %0d", axi_item_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("Pending trace items: T0=%0d T1=%0d",
         pending_trace_q[0].size(), pending_trace_q[1].size()), UVM_LOW)

逐段解释：

* 第 795~804 行：计算总 mismatch、总 pending trace 和总 pending async。
* 第 806~817 行：打印 scoreboard report 头，以及 trace/probe/AXI 收包数、pending
  trace、pending LSU access、pending async hint、high watermark 和 step 数。
* 第 818~824 行：源文件随后打印 T0/T1 mismatch 和 Spike instruction count。
* 第 825~831 行：若无 mismatch 且 ``step_count > 0``，即使 end-of-test 有 pending trace
  或 pending LSU access，也以 NOTE 形式记录，并打印 ``RESULT: PASS``。
* 第 832~835 行：如果有 trace/step/pending/memory activity 但不满足 pass 条件，则报
  ``RESULT: FAIL``。

接口关系：

* 被调用：UVM report phase。
* 调用：``riscv_cosim_get_insn_cnt``。
* 共享状态：统计计数和 pending 队列。

§13.2  ``cleanup_cosim()``、``final_phase()`` 和 ``pre_abort()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L787-L851``）：

.. code-block:: systemverilog

     protected function void cleanup_cosim();
       if (cosim_handle != null) begin
         riscv_cosim_destroy(cosim_handle);
         cosim_handle = null;
       end
       initialized = 0;
     endfunction

     function void final_phase(uvm_phase phase);
       super.final_phase(phase);
       if (cosim_handle != null) begin
         `uvm_info("cosim", $sformatf("Co-simulation matched T0=%0d T1=%0d instructions",
           riscv_cosim_get_insn_cnt(cosim_handle, 0),
           riscv_cosim_get_insn_cnt(cosim_handle, 1)), UVM_LOW)
       end
       cleanup_cosim();
     endfunction

     function void pre_abort();
       cleanup_cosim();
     endfunction

逐段解释：

* 第 787~793 行：``cleanup_cosim`` 在 handle 非空时调用 ``riscv_cosim_destroy``，
  然后清空 handle，并把 ``initialized`` 置 0。
* 第 839~846 行：final phase 在销毁前打印 T0/T1 matched instruction count，然后调用
  ``cleanup_cosim``。
* 第 849~851 行：``pre_abort`` 也调用 ``cleanup_cosim``，覆盖仿真 abort 路径。

接口关系：

* 被调用：``init_cosim``、``final_phase``、``pre_abort``。
* 调用：``riscv_cosim_destroy``、``riscv_cosim_get_insn_cnt``。
* 共享状态：``cosim_handle`` 和 ``initialized``。

§14  DPI 函数签名边界
------------------------------------------------------------------------------------------------------------------------

职责：SystemVerilog 侧只通过 :file:`dv/cosim/cosim_dpi.svh` 中声明的函数访问 C++ cosim。
文档中的 DPI 函数名均来自该文件。

§14.1  初始化、step 和通知函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/cosim/cosim_dpi.svh:L8-L35``）：

.. code-block:: text

   // Initialize co-simulation
   import "DPI-C" function chandle riscv_cosim_init(
     input string config
   );

   // Destroy co-simulation instance
   import "DPI-C" function void riscv_cosim_destroy(
     input chandle handle
   );

   // Add memory region
   import "DPI-C" function void riscv_cosim_add_memory(
     input chandle handle,
     input int     base_addr,
     input int     size
   );

   // Step one instruction
   // Returns 1 on match, 0 on mismatch
   import "DPI-C" function int riscv_cosim_step(
     input chandle handle,
     input int     write_reg,
     input int     write_reg_data,
     input int     pc,
     input int     sync_trap,
     input int     suppress_reg_write,
     input int     thread_id
   );

逐段解释：

* 第 8~16 行：``riscv_cosim_init`` 返回 ``chandle``；``riscv_cosim_destroy`` 接收同一
  handle。
* 第 18~23 行：``riscv_cosim_add_memory`` 接收 handle、base address 和 size。
* 第 25~35 行：``riscv_cosim_step`` 返回 int，注释明确 1 表示 match，0 表示 mismatch；
  参数包含 writeback、PC、sync trap、suppress register write 和 thread id。

接口关系：

* 被调用：scoreboard ``init_cosim``、``cleanup_cosim``、``compare_instruction``。
* 调用：C++ DPI 实现。
* 共享状态：``chandle``。

§14.2  D-side access 与 trap CSR 查询
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/cosim/cosim_dpi.svh:L81-L151``）：

.. code-block:: text

   // Notify dside access
   import "DPI-C" function void riscv_cosim_notify_dside_access(
     input chandle handle,
     input int     store,
     input int     data,
     input int     addr,
     input int     be,
     input int     error,
     input int     misaligned_first,
     input int     misaligned_second,
     input int     misaligned_first_saw_error,
     input int     m_mode_access,
     input int     widened_load,
     input int     thread_id
   );

   // Set iside error
   import "DPI-C" function void riscv_cosim_set_iside_error(
     input chandle handle,
     input int     addr,

逐段解释：

* 第 81~95 行：``riscv_cosim_notify_dside_access`` 接收 store/data/address/byte enable、
  error、misaligned 标志、M-mode access、widened load 和 thread id。scoreboard 的
  ``notify_memory_access`` 正是按该签名拆分 AXI4 beat。
* 第 97~102 行：``riscv_cosim_set_iside_error`` 用于 instruction-side error 通知。
* 第 138~151 行：源文件后续声明 ``riscv_cosim_get_mcause``、
  ``riscv_cosim_get_mepc`` 和 ``riscv_cosim_get_mtvec``，scoreboard 目前使用
  ``mcause`` 与 ``mepc`` 查询。

接口关系：

* 被调用：scoreboard ``notify_memory_access`` 和 trap CSR compare 路径。
* 调用：C++ DPI 实现。
* 共享状态：``chandle`` 和 ``thread_id``。

§15  参考资料
------------------------------------------------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0001`：trace plus DUT probe cosim 数据路径。
* :ref:`adr-0004`：RTL trace pkt 携带 RVFI-equivalent 写回字段。
* :ref:`adr-0016`：NUM_THREADS=2 cosim 支持路径。
* :ref:`adr-0018`：strict ``wb_tag`` matching。

关联章节：

* :ref:`cosim_scoreboard`：cosim scoreboard 的架构级说明。
* :ref:`appendix_c_tools/cosim_cpp`：C++ Spike DPI 实现。
* :doc:`env`：UVM env 与 agent 连接关系。
* :doc:`trace_agent`：trace monitor 和 DUT probe monitor 字段来源。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.svh`

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

§16  v2-17 源码片段闭环
--------------------------------------------------------------------------------

本节把 v2 源码审计中仍缺少 ``literalinclude`` 的 cosim agent 资产补成可渲染源码片段。
前文已经逐段解释 package、agent wrapper、scoreboard 和 helper header 的职责；这里
补齐真实文件引用，确保 Sphinx build 能直接验证路径与行号。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv
   :language: systemverilog
   :lines: 1-26
   :linenos:
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent_pkg.sv:L1-L26

逐段精读：L1-L12 建立 package、UVM、trace 和 AXI4 依赖；L14-L24 按 cfg、DPI、
scoreboard、agent 的顺序 include，保证 ``eh2_cosim_agent`` 能看到 scoreboard 类型。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv
   :language: systemverilog
   :lines: 1-66
   :linenos:
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_agent.sv:L1-L66

逐段精读：L1-L17 声明 agent class、scoreboard 和 ``dmem_port``；L23-L39 在
``build_phase`` 创建 scoreboard 与 analysis export；L41-L64 在 ``connect_phase`` 把
外部 LSU AXI4 transaction 接到 scoreboard FIFO。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh
   :language: systemverilog
   :lines: 1-125
   :linenos:
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_binary_loader.svh:L1-L125

逐段精读：L1-L17 说明 helper 的职责是把 ELF/HEX binary 装入 Spike cosim memory；
L19-L73 处理文件打开、地址递增和 byte 写入；L75-L125 负责错误报告和关闭路径。
它是 scoreboard 初始化前的 helper，不直接参与 retire compare。

§17  v2-29 cosim 配置与 CSR 预注册全源码精读
--------------------------------------------------------------------------------

本节补齐 cosim agent 中仍未全文纳入文档的两个配置类资产：``eh2_cosim_cfg.sv``
给 Spike DPI 初始化提供 ISA、PMP、内存窗口和 debug module 地址；``eh2_cosim_csr_preregister.svh``
在 scoreboard 初始化时把 EH2 vendor CSR 预注册到 cosim 模型。

§17.1  ``eh2_cosim_cfg.sv`` — Spike cosim 配置对象
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv
   :language: text
   :linenos:
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:全文

逐段精读：

* L1-L8：文件头说明该配置对象由 testbench 放入 ``uvm_config_db``，scoreboard 在
  build phase 读取；设计模式借鉴 Ibex cosim cfg，但字段按 EH2 调整。
* L10-L21：class 继承 ``uvm_object`` 并注册 factory；默认 ISA string 是
  ``rv32imac_zba_zbb_zbc_zbs``，起始 PC 为 ``0x8000_0000``，``mtvec`` 初值为 0。
* L23-L36：保存 PMP region 数量、PMP granularity、MHPM counter 数量、relax cosim
  开关和 Spike log 文件路径。这些字段决定 cosim mismatch 是 fatal 还是降级记录。
* L38-L40：debug module 地址窗口默认是 ``0x0000_0000`` 到 ``0x0000_0FFF``，供 debug
  访问模型识别 debug memory range。
* L42-L55：定义 ``mem_region_t`` 并列出 boot、debug system bus、外部数据、
  ICCM 与 DCCM 的默认窗口。注释说明这些值可由 plusarg 或 RTL 参数注入覆盖。
* L56-L66：提供 flat 的 DCCM/ICCM base/size 字段，并继续定义 PIC、mailbox 和
  NMI vector memory region。flat 字段用于 env 注入路径，struct 字段用于统一 region
  列表表达。
* L67-L78：constructor 无额外逻辑；``sync_mem_regions`` 把 flat ICCM/DCCM 字段同步回
  ``mem_iccm`` 和 ``mem_dccm``，避免 plusarg override 后两种表示不一致。
* L80-L86：``convert2string`` 输出 ISA、PC、mtvec、PMP、relax 标志和 DCCM/ICCM base，
  用于初始化 log 中快速确认 cosim 配置。

§17.2  ``eh2_cosim_csr_preregister.svh`` — EH2 vendor CSR 白名单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh
   :language: text
   :linenos:
   :caption: dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh:全文

逐段精读：

* L1-L12：文件头说明 EH2 有 28 个 Spike 默认 ``csrmap`` 不认识的 vendor-specific CSR。
  预注册的目标不是完整建模 WARL 语义，而是避免 Spike 把这些 CSR 指令误判为非法指令。
* L14-L24：第一组调用注册 machine/custom debug 相关 CSR，包括 ``mscause``、``mrac``、
  ``mfdc``、``mcgc``、``mpmc``、``mcpc``、``dmst``、``mfdht``、``mfdhs``、
  ``mhartstart`` 和 ``mnmipdel``。
* L25-L30：第二组注册 internal timer 相关 CSR：``mitcnt0/1``、``mitb0/1`` 和
  ``mitctl0/1``。
* L31-L35：第三组注册 ECC/cache/error 相关 CSR：``mdeau``、``mdseac``、``micect``、
  ``miccmect`` 和 ``mdccmect``。
* L36-L41：最后一组注册 PIC external interrupt 相关 CSR，包括 ``meivt``、``meihap``、
  ``meipt``、``meicpct``、``meicurpl`` 和 ``meicidpl``。每项初值均为 0，thread id
  参数也为 0。
