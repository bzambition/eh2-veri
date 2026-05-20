.. _appendix_b_uvm_tb:
.. _appendix_b_uvm/tb:

顶层 Testbench 文件 — 详细参考
================================================================================

:status: draft
:source: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  文件边界与数据流
--------------------------------------------------------------------------------

``core_eh2_tb_top.sv`` 是 UVM 类世界和 SystemVerilog module 世界之间的边界。
它实例化 ``eh2_veer_wrapper``、三组 ``axi4_slave_mem``、所有 virtual interface，
再通过 ``uvm_config_db::set`` 把这些 interface 交给 UVM agent、monitor、test 和
scoreboard。本文只描述源文件中已经存在的连线和行为，不把 env 中创建的 agent
误写成 testbench 顶层实例。

**顶层数据流**：

.. code-block:: text

   core_eh2_tb_top
     |
     +-- core_clk / rst_l / porst_l
     |
     +-- eh2_veer_wrapper dut
     |     +-- trace_rv_i_* ---------------> eh2_trace_intf
     |     +-- trace_rv_i_* + LSU AXI4 ----> eh2_veer_wrapper_rvfi -> eh2_rvfi_if
     |     +-- internal DEC/EXU/TLU probes -> eh2_dut_probe_if / eh2_fcov_if
     |     +-- IRQ/JTAG/HaltRun pins <------ eh2_irq_intf / eh2_jtag_intf / eh2_halt_run_intf
     |
     +-- axi4_slave_mem lsu_mem <---------- LSU AXI4
     +-- axi4_slave_mem ifu_mem <---------- IFU AXI4
     +-- axi4_slave_mem sb_mem  <---------- SB AXI4
     |
     +-- core_eh2_tb_intf -----------------> base test binary load and mailbox polling
     |
     +-- uvm_config_db::set ---------------> env/test/agent/monitor virtual handles

上图中的三组 ``axi4_slave_mem`` 是 module 实例；``lsu_agent``、``ifu_agent``、
``sb_agent`` 是 :ref:`appendix_b_uvm/env` 中创建的 UVM agent。TB 顶层没有创建
``dma_agent``，源文件把 DMA AXI4 输入信号固定为空闲值。

§2  顶层 module 与全局时钟复位
--------------------------------------------------------------------------------

§2.1  ``core_eh2_tb_top`` — module 边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义仿真顶层 module，引入 UVM 宏包，并建立 DUT 层级探针宏。宏
``DEC`` 和 ``EXU`` 后续用于访问 DUT 内部 decode/execution 信号。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L22-L36``）：

.. code-block:: systemverilog

   `include "uvm_macros.svh"
   import uvm_pkg::*;

   // Include parameter defines for RV_* macros
   // common_defines.vh provides `define RV_* macros used throughout the design
   // eh2_pdef.vh provides the eh2_param_t struct definition
   // Both are passed as compilation units via the filelist

   module core_eh2_tb_top;

     //--------------------------------------------------------------------------
     // DUT hierarchy macros (for internal signal probing)
     //--------------------------------------------------------------------------
     `define DEC dut.veer.dec
     `define EXU dut.veer.exu

逐段解释：

* 第 L22-L23 行：包含 UVM 宏并导入 ``uvm_pkg``，因此该 module 后面可以直接调用
  ``uvm_config_db`` 和 ``run_test``。
* 第 L30 行：声明唯一的顶层 module ``core_eh2_tb_top``；源文件没有在该文件中声明
  其它 module。
* 第 L35-L36 行：把 ``dut.veer.dec`` 和 ``dut.veer.exu`` 包装成宏，后续
  ``dut_probe_intf`` 和 ``u_fcov_if`` 的层级信号读取都依赖这两个宏。

接口关系：

* 被调用：仿真 filelist 把该 module 作为顶层编译/展开对象。
* 调用：调用 UVM runtime 的 ``run_test()``，并实例化 DUT、memory 和 interface。
* 共享状态：通过层级宏读取 DUT 内部信号，但不改变 DUT 内部状态。

§2.2  ``core_clk`` 与 ``rst_l/porst_l`` — 时钟和双复位
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 100 MHz core clock，并按固定顺序释放 ``porst_l`` 和 ``rst_l``。
``porst_l`` 接到 DUT 的 ``dbg_rst_l``，``rst_l`` 接到 DUT 主复位和大部分 interface。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L41-L48``）：

.. code-block:: systemverilog

     bit core_clk;
     initial begin
       core_clk = 0;
       forever #5 core_clk = ~core_clk;  // 100MHz
     end

     logic rst_l;       // Active-low reset
     logic porst_l;     // Power-on reset (active-low)

逐段解释：

* 第 L41-L45 行：``core_clk`` 初值为 0，每 5 个仿真时间单位翻转一次；完整周期是
  10 个时间单位，对应注释中的 100 MHz。
* 第 L47-L48 行：声明两个低有效复位。源文件后续把 ``rst_l`` 传给 core reset，把
  ``porst_l`` 传给 debug reset。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L125-L131``）：

.. code-block:: systemverilog

     initial begin
       rst_l   = 0;
       porst_l = 0;
       repeat (3) @(posedge core_clk);
       porst_l = 1;
       repeat (3) @(posedge core_clk);
       rst_l   = 1;
     end

逐段解释：

* 第 L126-L127 行：仿真起始时同时拉低主复位和 power-on reset。
* 第 L128-L129 行：等待 3 个 ``core_clk`` 上升沿后先释放 ``porst_l``。
* 第 L130-L131 行：再等待 3 个 ``core_clk`` 上升沿释放 ``rst_l``，因此 DUT 先得到
  debug reset 释放，再得到主复位释放。

接口关系：

* 被调用：所有同步 ``always``/``always_ff`` 块和 interface 实例都使用
  ``core_clk`` 或 ``rst_l``。
* 调用：不调用子任务；由 SystemVerilog ``initial`` 和 ``forever`` 调度驱动。
* 共享状态：写 ``core_clk``、``rst_l``、``porst_l``。

§2.3  ``core_eh2_dut_signals.svh`` — DUT 连线声明
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 DUT 顶层端口需要的 reset、trace、debug、interrupt、clock enable 和
四组 AXI4 信号声明到 ``core_eh2_tb_top`` 作用域。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L54-L57``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // DUT Signal Declarations (DUT, JTAG, trace, debug, AXI4 LSU/IFU/SB/DMA)
     //--------------------------------------------------------------------------
     `include "core_eh2_dut_signals.svh"

逐段解释：

* 第 L54-L56 行：注释列出 include 文件覆盖的端口族，包括 DUT、JTAG、trace、debug
  和 AXI4 LSU/IFU/SB/DMA。
* 第 L57 行：include 直接把 ``core_eh2_dut_signals.svh`` 的声明展开到 module 内，
  因此后续 DUT、memory 和 interface 实例共用同一批 signal。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:L14-L25``）：

.. code-block:: systemverilog

     // Trace
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_insn_ip;
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_address_ip;
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_valid_ip;
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_exception_ip;
     logic [`RV_NUM_THREADS-1:0][4:0]  trace_rv_i_ecause_ip;
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_interrupt_ip;
     logic [`RV_NUM_THREADS-1:0][31:0] trace_rv_i_tval_ip;
     // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
     logic [`RV_NUM_THREADS-1:0][1:0]  trace_rv_i_rd_valid_ip;
     logic [`RV_NUM_THREADS-1:0][9:0]  trace_rv_i_rd_addr_ip;
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_rd_wdata_ip;

逐段解释：

* 第 L15-L21 行：trace 信号按 ``RV_NUM_THREADS`` 维度展开，每个线程携带两个 slot
  的 instruction、PC、valid、exception、interrupt 和 tval 信息。
* 第 L22-L25 行：额外声明 verification-only 的 writeback view；注释明确 lane 0
  对应 ``i0``，lane 1 对应 ``i1``。这些信号后续同时进入 trace monitor 和 RVFI
  sidecar。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 通过 include 引用。
* 调用：不调用任务或函数，只提供声明。
* 共享状态：声明的信号被 DUT、AXI4 memory、UVM interface 和 coverage interface
  共同连接。

§3  Mailbox、测试服务接口与早期加载
--------------------------------------------------------------------------------

§3.1  ``mailbox_write`` — 从 LSU AW 通道抽取签名写
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 LSU AXI4 写地址握手抽象成 mailbox 写事件，并把地址、数据和完成标志同步到
``core_eh2_tb_intf``，供 base test 轮询。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L63-L82``）：

.. code-block:: systemverilog

     logic        mailbox_write;
     logic [63:0] mailbox_data;
     logic [31:0] mailbox_addr;
     event mailbox_test_pass;
     event mailbox_test_fail;
     bit   mailbox_test_done = 0;
     string early_bin_path;
     logic  early_bin_loaded = 0;

     assign mailbox_write = lsu_axi_awvalid && lsu_axi_awready;
     assign mailbox_addr  = lsu_axi_awaddr;
     assign mailbox_data  = lsu_axi_wdata;

     core_eh2_tb_intf tb_intf (.clk(core_clk), .rst_n(rst_l));

     assign tb_intf.mailbox_write     = mailbox_write;
     assign tb_intf.mailbox_addr      = mailbox_addr;
     assign tb_intf.mailbox_data      = mailbox_data;
     assign tb_intf.mailbox_test_done = mailbox_test_done;
     assign tb_intf.early_bin_loaded  = early_bin_loaded;

逐段解释：

* 第 L63-L70 行：声明 mailbox 检测所需的写脉冲、地址、数据、PASS/FAIL 事件、完成标志
  和 early binary load 状态。
* 第 L72-L74 行：``mailbox_write`` 只看 LSU AW 通道 ``valid && ready``；地址来自
  ``lsu_axi_awaddr``，数据来自 ``lsu_axi_wdata``。
* 第 L76-L82 行：实例化 ``core_eh2_tb_intf``，再把 mailbox 和 early-load 状态映射到
  interface 字段。UVM test 通过这个 interface 读取状态，而不是层级访问 TB 顶层信号。

接口关系：

* 被调用：``core_eh2_base_test`` 通过 ``tb_vif`` 读取 ``mailbox_test_done``、
  ``mailbox_data`` 和 ``early_bin_loaded``。
* 调用：连接 ``core_eh2_tb_intf``。
* 共享状态：读 LSU AXI4 信号，写 ``tb_intf`` 字段和 ``mailbox_test_done``。

§3.2  ``mem_write_req`` — UVM 到三组 memory 的 backdoor 写
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：响应 ``core_eh2_tb_intf.write_mem_byte`` 触发的 event，把同一个 byte 写到
LSU、IFU、SB 三组 AXI4 memory model，并用请求 ID 回传完成。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L84-L89``）：

.. code-block:: systemverilog

     always @(tb_intf.mem_write_req) begin
       lsu_mem.mem[tb_intf.mem_write_addr] = tb_intf.mem_write_data;
       ifu_mem.mem[tb_intf.mem_write_addr] = tb_intf.mem_write_data;
       sb_mem.mem[tb_intf.mem_write_addr]  = tb_intf.mem_write_data;
       tb_intf.mem_write_done_id = tb_intf.mem_write_req_id;
     end

逐段解释：

* 第 L84 行：该块对 ``tb_intf.mem_write_req`` 事件敏感，不依赖 AXI4 协议握手。
* 第 L85-L87 行：使用相同地址和 byte 数据同步写入 ``lsu_mem.mem``、
  ``ifu_mem.mem`` 和 ``sb_mem.mem``，保证 raw/hex binary 加载后三个外部 memory
  视图一致。
* 第 L88 行：把完成 ID 设置为当前请求 ID；``core_eh2_tb_intf.write_mem_byte`` 会等待
  这个 ID 匹配再返回。

关键代码（``dv/uvm/core_eh2/common/core_eh2_tb_intf.sv:L30-L36``）：

.. code-block:: systemverilog

     task automatic write_mem_byte(input bit [31:0] addr, input bit [7:0] data);
       mem_write_addr = addr;
       mem_write_data = data;
       mem_write_req_id++;
       -> mem_write_req;
       wait (mem_write_done_id == mem_write_req_id);
     endtask

逐段解释：

* 第 L31-L33 行：interface 先保存地址和数据，再递增请求 ID。
* 第 L34 行：触发 ``mem_write_req``，唤醒 TB 顶层的 ``always`` 块。
* 第 L35 行：等待 TB 顶层回写 ``mem_write_done_id``，避免 UVM 侧连续写时覆盖尚未处理的
  地址/数据字段。

接口关系：

* 被调用：``core_eh2_base_test.write_mem_byte`` 调用 ``tb_vif.write_mem_byte``。
* 调用：直接写 ``lsu_mem.mem``、``ifu_mem.mem``、``sb_mem.mem``。
* 共享状态：读写 ``tb_intf.mem_write_*`` 字段，写三组 memory model 的 ``mem`` 数组。

§3.3  ``mailbox monitor`` — PASS/FAIL 和 console 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在复位释放后监控 ``0xD0580000`` mailbox 写；低 8 位为 ``8'hFF`` 时标记
PASS，为 ``8'h01`` 时标记 FAIL，可打印 ASCII 字符作为 console 输出。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L100-L120``）：

.. code-block:: systemverilog

     always @(posedge core_clk) begin
       if (rst_l && mailbox_write && mailbox_addr == 32'hD0580000) begin
         $display("MAILBOX WRITE detected at %0t: data=%08x", $time, mailbox_data);
         if (mailbox_data[7:0] == 8'hFF) begin
           $display("========================================");
           $display("TEST PASSED (mailbox)");
           $display("========================================");
           mailbox_test_done = 1;
           ->mailbox_test_pass;
         end else if (mailbox_data[7:0] == 8'h01) begin
           $display("========================================");
           $display("TEST FAILED (mailbox)");
           $display("========================================");
           mailbox_test_done = 1;
           ->mailbox_test_fail;
         end else if (mailbox_data[7:0] >= 8'h20 && mailbox_data[7:0] < 8'h7F) begin
           // Console output (printable ASCII)
           $write("%c", mailbox_data[7:0]);
         end
       end
     end

逐段解释：

* 第 L100-L102 行：仅在 ``core_clk`` 上升沿、``rst_l`` 为 1、出现 mailbox write 且地址
  等于 ``32'hD0580000`` 时进入处理逻辑。
* 第 L103-L108 行：低 8 位等于 ``8'hFF`` 时打印 PASS banner，设置
  ``mailbox_test_done``，并触发 ``mailbox_test_pass`` event。
* 第 L109-L114 行：低 8 位等于 ``8'h01`` 时执行 FAIL 分支，设置同一个完成标志，并触发
  ``mailbox_test_fail`` event。
* 第 L115-L117 行：低 8 位落在可打印 ASCII 范围 ``0x20`` 到 ``0x7E`` 时，作为字符输出；
  该分支不设置完成标志。

接口关系：

* 被调用：``core_eh2_base_test.wait_for_signature`` 轮询 ``tb_vif.mailbox_test_done``。
* 调用：SystemVerilog ``$display``、``$write``；不直接调用 UVM report API。
* 共享状态：读 ``mailbox_*``，写 ``mailbox_test_done``，触发 PASS/FAIL event。

§3.4  ``early_bin_loaded`` — 时间 0 的 hex 预加载
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 UVM test 加载 binary 之前，检测 ``+bin=<path>`` plusarg；如果路径后缀是
``.hex``，用 ``$readmemh`` 同步加载到三组 AXI4 memory。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L154-L167``）：

.. code-block:: systemverilog

     initial begin
       if ($value$plusargs("bin=%s", early_bin_path) && early_bin_path.len() > 0) begin
         // Only load .hex files early; raw binaries still go through UVM
         if (early_bin_path.len() > 4 &&
             early_bin_path.substr(early_bin_path.len()-4, early_bin_path.len()-1) == ".hex") begin
           $display("TB_TOP: Early-loading hex file: %s", early_bin_path);
           $readmemh(early_bin_path, lsu_mem.mem);
           $readmemh(early_bin_path, ifu_mem.mem);
           $readmemh(early_bin_path, sb_mem.mem);
           early_bin_loaded = 1;
           $display("TB_TOP: Early binary load complete");
         end
       end
     end

逐段解释：

* 第 L155 行：读取 plusarg ``bin=%s`` 到 ``early_bin_path``，并要求字符串长度大于 0。
* 第 L157-L158 行：只接受后缀为 ``.hex`` 的路径；raw binary 不在该 initial 块处理。
* 第 L160-L162 行：对 ``lsu_mem.mem``、``ifu_mem.mem`` 和 ``sb_mem.mem`` 依次执行
  ``$readmemh``。
* 第 L163 行：设置 ``early_bin_loaded``，该标志通过 ``tb_intf`` 传给 base test。

接口关系：

* 被调用：仿真启动自动执行；``core_eh2_base_test.load_binary_to_mem`` 读取
  ``tb_vif.early_bin_loaded`` 来决定是否跳过 UVM 加载。
* 调用：SystemVerilog ``$value$plusargs`` 和 ``$readmemh``。
* 共享状态：写三组 memory 的 ``mem`` 数组，写 ``early_bin_loaded``。

§4  DUT 实例与端口族
--------------------------------------------------------------------------------

§4.1  ``eh2_veer_wrapper dut`` — 主 DUT 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 EH2 DUT，并连接 clock/reset、reset vector、NMI vector、JTAG ID、
trace、AXI4、interrupt、halt/run、performance counter 和 miscellaneous 端口。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L172-L191``）：

.. code-block:: systemverilog

     eh2_veer_wrapper dut (
       .clk                    (core_clk),
       .rst_l                  (rst_l),
       .dbg_rst_l              (porst_l),
       .rst_vec                (reset_vector[31:1]),
       .nmi_int                (nmi_int),
       .nmi_vec                (nmi_vector[31:1]),
       .jtag_id                (jtag_id[31:1]),

       // Trace
       .trace_rv_i_insn_ip      (trace_rv_i_insn_ip),
       .trace_rv_i_address_ip   (trace_rv_i_address_ip),
       .trace_rv_i_valid_ip     (trace_rv_i_valid_ip),
       .trace_rv_i_exception_ip (trace_rv_i_exception_ip),
       .trace_rv_i_ecause_ip    (trace_rv_i_ecause_ip),
       .trace_rv_i_interrupt_ip (trace_rv_i_interrupt_ip),
       .trace_rv_i_tval_ip      (trace_rv_i_tval_ip),
       .trace_rv_i_rd_valid_ip  (trace_rv_i_rd_valid_ip),
       .trace_rv_i_rd_addr_ip   (trace_rv_i_rd_addr_ip),
       .trace_rv_i_rd_wdata_ip  (trace_rv_i_rd_wdata_ip),

逐段解释：

* 第 L172-L179 行：DUT 是 ``eh2_veer_wrapper``，不是 RVFI wrapper；``rst_vec`` 和
  ``nmi_vec`` 连接时取 ``[31:1]``，保留源文件中的 bit slicing。
* 第 L182-L191 行：DUT trace 输出直接连接到 TB 顶层 trace signal；其中
  ``trace_rv_i_rd_*`` 是 verification-only writeback view，会被 trace monitor 和
  RVFI sidecar 使用。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L367-L402``）：

.. code-block:: systemverilog

       // External memory packets (tied off - internal memories used)
       .dccm_ext_in_pkt   ('0),
       .iccm_ext_in_pkt   ('0),
       .btb_ext_in_pkt    ('0),
       .ic_data_ext_in_pkt('0),
       .ic_tag_ext_in_pkt ('0),

       // MPC halt/run
       .mpc_debug_halt_req (mpc_debug_halt_req),
       .mpc_debug_run_req  (mpc_debug_run_req),
       .mpc_reset_run_req  (mpc_reset_run_req),
       .mpc_debug_halt_ack (mpc_debug_halt_ack),
       .mpc_debug_run_ack  (mpc_debug_run_ack),
       .debug_brkpt_status (debug_brkpt_status),
       .dec_tlu_mhartstart (dec_tlu_mhartstart),

       // CPU halt/run
       .i_cpu_halt_req    (i_cpu_halt_req),
       .o_cpu_halt_ack    (o_cpu_halt_ack),
       .o_cpu_halt_status (o_cpu_halt_status),
       .i_cpu_run_req     (i_cpu_run_req),
       .o_cpu_run_ack     (o_cpu_run_ack),

       // Debug status
       .o_debug_mode_status (o_debug_mode_status),

逐段解释：

* 第 L367-L372 行：外部 DCCM、ICCM、BTB、IC data 和 IC tag packet 端口全部接
  ``'0``；源文件注释说明这里使用内部 memory。
* 第 L374-L381 行：MPC debug halt/run 相关端口连到 TB 顶层 signal，后续由
  ``eh2_halt_run_intf`` 驱动请求并接收 acknowledge。
* 第 L383-L391 行：CPU halt/run 请求、响应和 debug mode status 也走 TB 顶层 signal，
  其中 status 后续回灌到 ``halt_run_vif``。

接口关系：

* 被调用：仿真 elaboration 实例化该 DUT。
* 调用：连接外部 memory model、virtual interface 和内部探针，不调用 UVM task。
* 共享状态：DUT 驱动 trace、AXI4 ready/valid/data、JTAG TDO、halt/run ack、
  performance counter 等信号；TB 顶层驱动 reset、vector、interrupt、JTAG 输入等。

§4.2  默认信号值 — boot、NMI、JTAG ID 和 bus clock enable
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：设置 boot/reset 默认输入，并把四个 bus clock enable 置为 1。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L137-L147``）：

.. code-block:: systemverilog

     initial begin
       reset_vector       = 32'h80000000;
       nmi_vector         = 32'h00000000;
       jtag_id            = 31'h1;
       // mpc_debug_halt_req/run_req/reset_run_req driven by eh2_halt_run_intf (assign below)
       // i_cpu_halt_req/run_req driven by eh2_halt_run_intf (assign below)
       lsu_bus_clk_en     = 1;
       ifu_bus_clk_en     = 1;
       dbg_bus_clk_en     = 1;
       dma_bus_clk_en     = 1;
     end

逐段解释：

* 第 L138-L140 行：reset vector 为 ``32'h80000000``，NMI vector 为 ``32'h00000000``，
  JTAG ID 为 ``31'h1``。
* 第 L141-L142 行：注释说明 MPC 和 CPU halt/run 请求不在该 initial 块驱动，而由后续
  ``eh2_halt_run_intf`` 赋值。
* 第 L143-L146 行：LSU、IFU、debug bus 和 DMA bus clock enable 全部置为 1。

接口关系：

* 被调用：仿真启动自动执行。
* 调用：不调用子任务。
* 共享状态：写 DUT 输入侧默认值。

§5  AXI4 memory model 与 DMA tie-off
--------------------------------------------------------------------------------

§5.1  三组 ``axi4_slave_mem`` — LSU/IFU/SB 外部 memory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 LSU、IFU 和 debug system bus 三个 AXI4 master 端口各实例化一个 64 MB
``axi4_slave_mem``，并把 error injection 控制信号从对应 ``axi4_intf`` 接入 memory。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L409-L420``）：

.. code-block:: systemverilog

     // LSU memory (data) - connected to LSU AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_LSU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) lsu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (lsu_axi_intf.error_inject_mode),
       .force_bresp       (lsu_axi_intf.force_bresp),
       .force_rresp       (lsu_axi_intf.force_rresp),

逐段解释：

* 第 L409-L415 行：``lsu_mem`` 的地址宽度是 32，数据宽度是 64，ID 宽度使用
  ``RV_LSU_BUS_TAG``，容量是 ``64 * 1024 * 1024``。
* 第 L416-L420 行：memory 的 clock/reset 来自 ``core_clk`` 和 ``rst_l``；
  response/error 控制来自 ``lsu_axi_intf``，与 :ref:`appendix_b_uvm/axi4_agent`
  中的错误注入路径对齐。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L452-L463``）：

.. code-block:: systemverilog

     // IFU memory (instruction) - connected to IFU AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_IFU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) ifu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (ifu_axi_intf.error_inject_mode),
       .force_bresp       (ifu_axi_intf.force_bresp),
       .force_rresp       (ifu_axi_intf.force_rresp),

逐段解释：

* 第 L452-L458 行：``ifu_mem`` 与 ``lsu_mem`` 参数相同，只是 ID 宽度换成
  ``RV_IFU_BUS_TAG``。
* 第 L459-L463 行：IFU memory 也接入 ``ifu_axi_intf`` 的 error injection 控制字段。
  当前 env 中 IFU agent 被配置为 passive，但 TB 顶层仍把控制字段连好。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L495-L506``）：

.. code-block:: systemverilog

     // SB memory (debug system bus) - connected to SB AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_SB_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) sb_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (sb_axi_intf.error_inject_mode),
       .force_bresp       (sb_axi_intf.force_bresp),
       .force_rresp       (sb_axi_intf.force_rresp),

逐段解释：

* 第 L495-L501 行：``sb_mem`` 服务 debug system bus，ID 宽度使用 ``RV_SB_BUS_TAG``。
* 第 L502-L506 行：SB memory 使用自己的 ``sb_axi_intf`` error injection 字段；它不复用
  LSU/IFU interface 状态。

接口关系：

* 被调用：DUT 的 LSU/IFU/SB AXI4 master 端口发起读写时访问这些 memory。
* 调用：实例化 ``axi4_slave_mem``，不调用 UVM class。
* 共享状态：每个 memory 既被 AXI4 协议访问，也会被 early load 和
  ``tb_intf.mem_write_req`` backdoor 写入。

§5.2  DMA AXI4 tie-off — 无外部 DMA master
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：保持 DMA 输入通道空闲，只让 DUT 驱动 DMA 输出侧 ready/response/data 信号。
源文件没有为 DMA 创建 ``axi4_slave_mem`` 或 UVM ``dma_agent``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L538-L564``）：

.. code-block:: systemverilog

     // DMA port: no external DMA master — tie all inputs to inactive values.
     // OUTPUTS are driven by the DUT only (do NOT assign — that caused multi-driver X).
     // AW channel inputs
     assign dma_axi_awvalid = 1'b0;
     assign dma_axi_awid    = '0;
     assign dma_axi_awaddr  = '0;
     assign dma_axi_awsize  = '0;
     assign dma_axi_awprot  = '0;
     assign dma_axi_awlen   = '0;
     assign dma_axi_awburst = '0;
     // W channel inputs
     assign dma_axi_wvalid  = 1'b0;
     assign dma_axi_wdata   = '0;
     assign dma_axi_wstrb   = '0;
     assign dma_axi_wlast   = '0;
     // B channel input
     assign dma_axi_bready  = 1'b0;
     // AR channel inputs
     assign dma_axi_arvalid = 1'b0;
     assign dma_axi_arid    = '0;
     assign dma_axi_araddr  = '0;
     assign dma_axi_arsize  = '0;
     assign dma_axi_arprot  = '0;
     assign dma_axi_arlen   = '0;
     assign dma_axi_arburst = '0;
     // R channel input
     assign dma_axi_rready  = 1'b0;

逐段解释：

* 第 L538-L539 行：注释明确 DMA 端口没有外部 DMA master；输出由 DUT 驱动，TB 不再对
  输出做赋值，以避免 multi-driver X。
* 第 L541-L554 行：AW、W、B 输入通道全部固定为空闲或 0。
* 第 L556-L564 行：AR 和 R 输入侧也固定为空闲或 0；因此当前 TB 顶层不会从 DMA 侧发起
  AXI4 访问。

接口关系：

* 被调用：DUT 的 DMA AXI4 端口在实例化时连接这些信号。
* 调用：不实例化 memory，不注入 virtual interface。
* 共享状态：只驱动 DMA 输入侧信号；不读写 UVM 配置。

§6  AXI4 virtual interface 与 passive 观测
--------------------------------------------------------------------------------

§6.1  ``axi4_intf`` 实例 — 三个 UVM 可见总线视图
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 LSU、IFU、SB 三个 AXI4 总线各创建一个 ``axi4_intf``，ID 宽度使用 DUT
真实 tag 宽度，供 AXI4 agent 监控和错误注入配置使用。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L595-L602``）：

.. code-block:: systemverilog

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_LSU_BUS_TAG))
       lsu_axi_intf (.clk(core_clk), .rst_n(rst_l));

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_IFU_BUS_TAG))
       ifu_axi_intf (.clk(core_clk), .rst_n(rst_l));

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_SB_BUS_TAG))
       sb_axi_intf (.clk(core_clk), .rst_n(rst_l));

逐段解释：

* 第 L595-L596 行：``lsu_axi_intf`` 使用 ``RV_LSU_BUS_TAG``，与 LSU DUT 端口和
  ``lsu_mem`` ID 宽度一致。
* 第 L598-L599 行：``ifu_axi_intf`` 使用 ``RV_IFU_BUS_TAG``。
* 第 L601-L602 行：``sb_axi_intf`` 使用 ``RV_SB_BUS_TAG``。三者都使用同一个
  ``core_clk`` 和 ``rst_l``。

接口关系：

* 被调用：env 中的 ``lsu_agent``、``ifu_agent``、``sb_agent`` 通过
  ``uvm_config_db`` 获取对应 virtual interface。
* 调用：实例化 ``axi4_intf``。
* 共享状态：interface 字段由 TB 顶层 assign 映射到 DUT wire，同时携带
  ``error_inject_mode``、``force_bresp``、``force_rresp`` 给 memory。

§6.2  LSU interface 映射 — 从 DUT wire 到 virtual interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 LSU AXI4 五通道信号逐项映射到 ``lsu_axi_intf``，让 UVM monitor 看到同一批
握手、地址、数据和 response。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L606-L626``）：

.. code-block:: systemverilog

     assign lsu_axi_intf.awvalid  = lsu_axi_awvalid;
     assign lsu_axi_intf.awready  = lsu_axi_awready;
     assign lsu_axi_intf.awid     = lsu_axi_awid;
     assign lsu_axi_intf.awaddr   = lsu_axi_awaddr;
     assign lsu_axi_intf.awlen    = lsu_axi_awlen;
     assign lsu_axi_intf.awsize   = lsu_axi_awsize;
     assign lsu_axi_intf.awburst  = lsu_axi_awburst;
     assign lsu_axi_intf.awlock   = lsu_axi_awlock;
     assign lsu_axi_intf.awcache  = lsu_axi_awcache;
     assign lsu_axi_intf.awprot   = lsu_axi_awprot;
     assign lsu_axi_intf.awregion = lsu_axi_awregion;
     assign lsu_axi_intf.awqos    = lsu_axi_awqos;
     assign lsu_axi_intf.wvalid   = lsu_axi_wvalid;
     assign lsu_axi_intf.wready   = lsu_axi_wready;
     assign lsu_axi_intf.wdata    = lsu_axi_wdata;
     assign lsu_axi_intf.wstrb    = lsu_axi_wstrb;
     assign lsu_axi_intf.wlast    = lsu_axi_wlast;
     assign lsu_axi_intf.bvalid   = lsu_axi_bvalid;
     assign lsu_axi_intf.bready   = lsu_axi_bready;
     assign lsu_axi_intf.bresp    = lsu_axi_bresp;
     assign lsu_axi_intf.bid      = lsu_axi_bid;

逐段解释：

* 第 L606-L617 行：LSU write address channel 的 valid/ready、ID、地址和属性字段完整映射。
* 第 L618-L622 行：write data channel 的 valid/ready、data、strb、last 映射到
  interface。
* 第 L623-L626 行：write response channel 映射 response valid/ready、response code 和
  response ID。

接口关系：

* 被调用：``axi4_monitor`` 通过 ``lsu_axi_intf`` 采样 LSU transaction。
* 调用：不调用任务；是连续赋值。
* 共享状态：读 DUT/LSU wire，写 virtual interface 字段。

§6.3  IFU/SB interface 映射 — 指令侧和 debug system bus
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用同样模式把 IFU 和 SB 总线映射到各自 ``axi4_intf``，保持 agent 监控路径与
真实 DUT wire 一致。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L647-L685``）：

.. code-block:: systemverilog

     assign ifu_axi_intf.awvalid  = ifu_axi_awvalid;
     assign ifu_axi_intf.awready  = ifu_axi_awready;
     assign ifu_axi_intf.awid     = ifu_axi_awid;
     assign ifu_axi_intf.awaddr   = ifu_axi_awaddr;
     assign ifu_axi_intf.awlen    = ifu_axi_awlen;
     assign ifu_axi_intf.awsize   = ifu_axi_awsize;
     assign ifu_axi_intf.awburst  = ifu_axi_awburst;
     assign ifu_axi_intf.awlock   = ifu_axi_awlock;
     assign ifu_axi_intf.awcache  = ifu_axi_awcache;
     assign ifu_axi_intf.awprot   = ifu_axi_awprot;
     assign ifu_axi_intf.awregion = ifu_axi_awregion;
     assign ifu_axi_intf.awqos    = ifu_axi_awqos;
     assign ifu_axi_intf.wvalid   = ifu_axi_wvalid;
     assign ifu_axi_intf.wready   = ifu_axi_wready;
     assign ifu_axi_intf.wdata    = ifu_axi_wdata;
     assign ifu_axi_intf.wstrb    = ifu_axi_wstrb;
     assign ifu_axi_intf.wlast    = ifu_axi_wlast;
     assign ifu_axi_intf.bvalid   = ifu_axi_bvalid;
     assign ifu_axi_intf.bready   = ifu_axi_bready;
     assign ifu_axi_intf.bresp    = ifu_axi_bresp;
     assign ifu_axi_intf.bid      = ifu_axi_bid;

逐段解释：

* 第 L647-L658 行：IFU write address channel 映射字段与 LSU 相同，只是源信号前缀变成
  ``ifu_axi_*``。
* 第 L659-L663 行：IFU write data channel 映射。
* 第 L664-L685 行：IFU write response、read address、read data channel 映射完整保留；
  代码片段只展示前半段，后续字段在源文件 L668-L685。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L688-L726``）：

.. code-block:: systemverilog

     assign sb_axi_intf.awvalid  = sb_axi_awvalid;
     assign sb_axi_intf.awready  = sb_axi_awready;
     assign sb_axi_intf.awid     = sb_axi_awid;
     assign sb_axi_intf.awaddr   = sb_axi_awaddr;
     assign sb_axi_intf.awlen    = sb_axi_awlen;
     assign sb_axi_intf.awsize   = sb_axi_awsize;
     assign sb_axi_intf.awburst  = sb_axi_awburst;
     assign sb_axi_intf.awlock   = sb_axi_awlock;
     assign sb_axi_intf.awcache  = sb_axi_awcache;
     assign sb_axi_intf.awprot   = sb_axi_awprot;
     assign sb_axi_intf.awregion = sb_axi_awregion;
     assign sb_axi_intf.awqos    = sb_axi_awqos;
     assign sb_axi_intf.wvalid   = sb_axi_wvalid;
     assign sb_axi_intf.wready   = sb_axi_wready;
     assign sb_axi_intf.wdata    = sb_axi_wdata;
     assign sb_axi_intf.wstrb    = sb_axi_wstrb;
     assign sb_axi_intf.wlast    = sb_axi_wlast;
     assign sb_axi_intf.bvalid   = sb_axi_bvalid;
     assign sb_axi_intf.bready   = sb_axi_bready;
     assign sb_axi_intf.bresp    = sb_axi_bresp;
     assign sb_axi_intf.bid      = sb_axi_bid;

逐段解释：

* 第 L688-L699 行：SB write address channel 映射到 ``sb_axi_intf``。
* 第 L700-L704 行：SB write data channel 映射到 ``sb_axi_intf``。
* 第 L705-L726 行：源文件继续映射 SB write response、read address 和 read data channel，
  使 debug system bus 的读写都能被 SB agent 监控。

接口关系：

* 被调用：``ifu_agent`` 和 ``sb_agent`` 的 monitor 读取这些 virtual interface。
* 调用：连续赋值。
* 共享状态：读 IFU/SB DUT wire，写对应 virtual interface 字段。

§7  Trace、RVFI 与 DUT probe
--------------------------------------------------------------------------------

§7.1  ``eh2_trace_intf`` — 原生 trace pkt 交付给 UVM monitor
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 DUT 原生 trace signal 包装为 ``eh2_trace_intf``，交给
:ref:`appendix_b_uvm/trace_agent` 中的 ``eh2_trace_monitor``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L731-L744``）：

.. code-block:: systemverilog

     eh2_trace_intf #(.NUM_THREADS(`RV_NUM_THREADS))
       trace_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect trace interface to DUT trace signals
     assign trace_intf.insn      = trace_rv_i_insn_ip;
     assign trace_intf.address   = trace_rv_i_address_ip;
     assign trace_intf.valid     = trace_rv_i_valid_ip;
     assign trace_intf.exception = trace_rv_i_exception_ip;
     assign trace_intf.ecause    = trace_rv_i_ecause_ip;
     assign trace_intf.interrupt = trace_rv_i_interrupt_ip;
     assign trace_intf.tval      = trace_rv_i_tval_ip;
     assign trace_intf.rd_valid  = trace_rv_i_rd_valid_ip;
     assign trace_intf.rd_addr   = trace_rv_i_rd_addr_ip;
     assign trace_intf.rd_wdata  = trace_rv_i_rd_wdata_ip;

逐段解释：

* 第 L731-L732 行：``eh2_trace_intf`` 参数化为 ``RV_NUM_THREADS``，clock/reset 与 DUT
  相同。
* 第 L735-L744 行：trace instruction、address、valid、exception、ecause、interrupt、
  tval 和 writeback 字段逐项映射到 interface；monitor 后续采样的是这些字段。

接口关系：

* 被调用：``eh2_trace_monitor`` 通过 ``uvm_config_db`` 的 ``vif`` 获取
  ``trace_intf``。
* 调用：实例化 ``eh2_trace_intf``。
* 共享状态：读 DUT trace wire，写 trace virtual interface。

§7.2  简化 trace 打印 — 只打印 thread 0 的两个 slot
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 TB 顶层直接打印 thread 0 的 ``i0`` 和 ``i1`` trace commit 信息，作为仿真日志
辅助，不向 UVM analysis port 写 transaction。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L580-L589``）：

.. code-block:: systemverilog

     always_ff @(posedge core_clk) begin
       if (rst_l) begin
         if (trace_rv_i_valid_ip[0][0]) begin
           $display("TRACE: t0.i0 PC=%h INSN=%h", trace_rv_i_address_ip[0][31:0], trace_rv_i_insn_ip[0][31:0]);
         end
         if (trace_rv_i_valid_ip[0][1]) begin
           $display("TRACE: t0.i1 PC=%h INSN=%h", trace_rv_i_address_ip[0][63:32], trace_rv_i_insn_ip[0][63:32]);
         end
       end
     end

逐段解释：

* 第 L580-L581 行：该打印块在 ``core_clk`` 上升沿执行，并要求 ``rst_l`` 为 1。
* 第 L582-L584 行：当 thread 0 的 slot 0 valid 时打印低 32 位 PC 和低 32 位 instruction。
* 第 L585-L587 行：当 thread 0 的 slot 1 valid 时打印高 32 位 PC 和高 32 位 instruction。

接口关系：

* 被调用：仿真时钟触发。
* 调用：只调用 ``$display``。
* 共享状态：只读取 ``trace_rv_i_*``，不写 UVM 对象。

§7.3  ``eh2_rvfi_if`` 与 ``u_rvfi_converter`` — trace 到 RVFI sidecar
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 RVFI interface，再用 sidecar module ``eh2_veer_wrapper_rvfi`` 把 DUT
trace 和 LSU bus 信息转换成 RVFI 等价字段。该 sidecar 不是 DUT wrapper，本文件中的 DUT
仍是 ``eh2_veer_wrapper``。这与 :ref:`adr-0015` 的源代码注释一致。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L749-L766``）：

.. code-block:: systemverilog

     eh2_rvfi_if rvfi_intf (.clk(core_clk), .rst_l(rst_l));

     //--------------------------------------------------------------------------
     // LSU bus valid signal (derived from AXI4 LSU transactions)
     //--------------------------------------------------------------------------
     logic lsu_bus_valid;
     logic [31:0] lsu_bus_addr;
     logic [31:0] lsu_bus_rdata;
     logic [31:0] lsu_bus_wdata;
     logic [3:0]  lsu_bus_wmask;
     logic        lsu_bus_write;

     assign lsu_bus_valid = (lsu_axi_awvalid && lsu_axi_awready) || (lsu_axi_arvalid && lsu_axi_arready) || (lsu_axi_wvalid && lsu_axi_wready) || (lsu_axi_rvalid && lsu_axi_rready);
     assign lsu_bus_addr  = lsu_axi_awvalid ? lsu_axi_awaddr : lsu_axi_araddr;
     assign lsu_bus_rdata = lsu_axi_rdata[31:0];
     assign lsu_bus_wdata = lsu_axi_wdata[31:0];
     assign lsu_bus_wmask = lsu_axi_wstrb[3:0];
     assign lsu_bus_write = lsu_axi_awvalid && lsu_axi_awready;

逐段解释：

* 第 L749 行：实例化 ``eh2_rvfi_if``，reset 端口名是 ``rst_l``，与其它 ``rst_n`` 命名的
  interface 不同。
* 第 L754-L759 行：声明 RVFI converter 需要的 LSU bus 摘要信号。
* 第 L761-L766 行：``lsu_bus_valid`` 合并 AW、AR、W、R 四类握手；地址在 AW valid 时取
  ``lsu_axi_awaddr``，否则取 ``lsu_axi_araddr``；数据和 mask 截取 32 位。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L771-L793``）：

.. code-block:: systemverilog

     eh2_veer_wrapper_rvfi u_rvfi_converter (
       .clk              (core_clk),
       .rst_n            (rst_l),

       // Trace inputs from DUT
       .trace_insn       (trace_rv_i_insn_ip[0]),
       .trace_address    (trace_rv_i_address_ip[0]),
       .trace_valid      (trace_rv_i_valid_ip[0]),
       .trace_exception  (trace_rv_i_exception_ip[0]),
       .trace_ecause     (trace_rv_i_ecause_ip[0]),
       .trace_interrupt  (trace_rv_i_interrupt_ip[0]),
       .trace_tval       (trace_rv_i_tval_ip[0]),
       .trace_rd_valid   (trace_rv_i_rd_valid_ip[0]),
       .trace_rd_addr    (trace_rv_i_rd_addr_ip[0]),
       .trace_rd_wdata   (trace_rv_i_rd_wdata_ip[0]),

       // LSU bus inputs
       .lsu_bus_valid    (lsu_bus_valid),
       .lsu_bus_addr     (lsu_bus_addr),
       .lsu_bus_rdata    (lsu_bus_rdata),
       .lsu_bus_wdata    (lsu_bus_wdata),
       .lsu_bus_wmask    (lsu_bus_wmask),
       .lsu_bus_write    (lsu_bus_write),

逐段解释：

* 第 L771-L773 行：RVFI converter 使用同一个 clock 和 reset。
* 第 L776-L785 行：只把 thread 0 的 trace 数组元素传给 converter；源代码索引为
  ``[0]``。
* 第 L788-L793 行：把上一段派生的 LSU bus 摘要输入 converter，使 RVFI memory 字段能
  反映 LSU transaction。

接口关系：

* 被调用：``core_eh2_rvfi_smoke_test`` 通过 ``rvfi_vif`` 读取 RVFI 字段。
* 调用：实例化 ``eh2_veer_wrapper_rvfi``。
* 共享状态：读 trace/LSU wire，写 ``rvfi_intf`` 字段。

§7.4  ``dut_probe_intf`` — DIV、NB-load、CSR 和异常镜像
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把无法完全从常规 trace pkt 得到的异步 writeback、CSR、异常、debug 和 interrupt
状态暴露给 cosim scoreboard 和 trace monitor。源文件注释明确常规 ``wb_valid``、
``wb_dest``、``wb_data``、``wb_suppress`` 不再由该 interface 探测，而是随 RTL trace
packet 传递；这对应 :ref:`adr-0004`。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L818-L835``）：

.. code-block:: systemverilog

     eh2_dut_probe_if dut_probe_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect DUT probe signals to internal DUT hierarchy.
     // Phase 1 note: regular wb_valid/wb_dest/wb_data/wb_suppress fields are no
     // longer probed here — they ride along the RTL trace packet now (ADR-0004).
     // Only async writeback (DIV / NB-load) and CSR/exception mirror state are
     // exposed via this interface.

     assign dut_probe_intf.div_cancel = `DEC.dec_div_cancel;
     assign dut_probe_intf.div_cancel_overwrite = `DEC.dec_div_cancel_overwrite;
     assign dut_probe_intf.div_rd     = `DEC.decode.div_rd;
     assign dut_probe_intf.div_result = `EXU.div_e1.out_raw[31:0];
     assign dut_probe_intf.div_wren   = dut.veer.exu_div_wren;
     assign dut_probe_intf.div_wdata  = dut.veer.exu_div_result[31:0];

     assign dut_probe_intf.nb_load_wen   = `DEC.dec_nonblock_load_wen[0];
     assign dut_probe_intf.nb_load_waddr = `DEC.dec_nonblock_load_waddr[0];
     assign dut_probe_intf.nb_load_data  = `DEC.lsu_nonblock_load_data;

逐段解释：

* 第 L818 行：实例化 ``eh2_dut_probe_if``，clock/reset 使用 TB 顶层的
  ``core_clk`` 和 ``rst_l``。
* 第 L820-L824 行：注释限定 probe interface 的职责，只暴露 DIV、NB-load 和
  CSR/exception mirror state，不再承载常规 wb 信号。
* 第 L826-L831 行：DIV cancel、overwrite、目的寄存器、raw result、write enable 和
  write data 分别来自 DEC/EXU 层级路径。
* 第 L833-L835 行：NB-load 的 write enable、write address 和 data 来自 DEC/LSU 相关
  层级信号。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L840-L865``）：

.. code-block:: systemverilog

     assign dut_probe_intf.mip        = {20'b0, extintsrc_req[1], 3'b0, timer_int[0], 3'b0, soft_int[0], 3'b0};
     assign dut_probe_intf.nmi        = nmi_int;
     assign dut_probe_intf.nmi_int    = nmi_int;
     assign dut_probe_intf.debug_req  = mpc_debug_halt_req[0];
     // mcycle: 64-bit cycle counter from TLU CSR registers
     // Path: dut.veer.dec.tlu.tlumt[0].tlu.mcycleh/mcyclel
     assign dut_probe_intf.mcycle     = {dut.veer.dec.tlu.tlumt[0].tlu.mcycleh[31:0],
                                         dut.veer.dec.tlu.tlumt[0].tlu.mcyclel[31:0]};

     // CSR signals - probed from TLU internal registers
     // mstatus: only bits [1:0] stored (MPIE, MIE), MPP hardcoded to 2'b11
     assign dut_probe_intf.mstatus = {19'b0, 2'b11, 3'b0,
                                      dut.veer.dec.tlu.tlumt[0].tlu.mstatus[1],
                                      3'b0,
                                      dut.veer.dec.tlu.tlumt[0].tlu.mstatus[0],
                                      3'b0};
     // mtvec: 31 bits stored {BASE[31:2], MODE[0]}, bit 1 reserved
     assign dut_probe_intf.mtvec   = {dut.veer.dec.tlu.tlumt[0].tlu.mtvec[30:1],
                                      1'b0,
                                      dut.veer.dec.tlu.tlumt[0].tlu.mtvec[0]};

逐段解释：

* 第 L840-L843 行：把 interrupt pending、NMI 和 debug request 映射到 probe interface；
  ``mip`` 拼接只使用 ``extintsrc_req[1]``、``timer_int[0]`` 和 ``soft_int[0]`` 三类输入。
* 第 L844-L847 行：从 TLU 的 ``mcycleh`` 和 ``mcyclel`` 拼成 64 位 ``mcycle``。
* 第 L851-L855 行：``mstatus`` 由常量位和 TLU 内部 ``mstatus[1]``、``mstatus[0]`` 拼接。
* 第 L857-L859 行：``mtvec`` 从 TLU ``mtvec`` 字段拼接，bit 1 固定为 0。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L867-L890``）：

.. code-block:: systemverilog

     // Exception/trap signals at E4 stage
     assign dut_probe_intf.mret_e4            = dut.veer.dec.tlu.tlumt[0].tlu.mret_e4;
     assign dut_probe_intf.illegal_e4         = dut.veer.dec.tlu.tlumt[0].tlu.illegal_e4;
     assign dut_probe_intf.ecall_e4           = dut.veer.dec.tlu.tlumt[0].tlu.ecall_e4;
     assign dut_probe_intf.ebreak_e4          = dut.veer.dec.tlu.tlumt[0].tlu.ebreak_e4;
     assign dut_probe_intf.ebreak_to_debug_e4 = dut.veer.dec.tlu.tlumt[0].tlu.ebreak_to_debug_mode_e4;
     assign dut_probe_intf.inst_acc_e4        = dut.veer.dec.tlu.tlumt[0].tlu.inst_acc_e4;

     // Exception/trap signals at writeback stage
     assign dut_probe_intf.mret_wb    = dut.veer.dec.tlu.tlumt[0].tlu.mret_wb;
     assign dut_probe_intf.illegal_wb = dut.veer.dec.tlu.tlumt[0].tlu.illegal_wb;
     assign dut_probe_intf.ecall_wb   = dut.veer.dec.tlu.tlumt[0].tlu.ecall_wb;
     assign dut_probe_intf.ebreak_wb  = dut.veer.dec.tlu.tlumt[0].tlu.ebreak_wb;

     // Debug state
     assign dut_probe_intf.debug_mode  = dut.veer.dec.dec_tlu_debug_mode[0];
     assign dut_probe_intf.dbg_halted  = dut.veer.dec.dec_tlu_dbg_halted[0];

     // Interrupt tracking
     assign dut_probe_intf.interrupt_valid = dut.veer.dec.tlu.tlumt[0].tlu.interrupt_valid;
     assign dut_probe_intf.take_ext_int    = dut.veer.dec.tlu.tlumt[0].tlu.take_ext_int;
     assign dut_probe_intf.take_timer_int  = dut.veer.dec.tlu.tlumt[0].tlu.take_timer_int;
     assign dut_probe_intf.take_soft_int   = dut.veer.dec.tlu.tlumt[0].tlu.take_soft_int;
     assign dut_probe_intf.take_nmi        = dut.veer.dec.tlu.tlumt[0].tlu.take_nmi;

逐段解释：

* 第 L867-L873 行：E4 stage 的 mret、illegal、ecall、ebreak、ebreak-to-debug 和
  instruction access exception 状态进入 probe interface。
* 第 L875-L879 行：writeback stage 的 mret、illegal、ecall、ebreak 状态单独暴露。
* 第 L881-L883 行：debug mode 和 debug halted 状态来自 DEC 输出。
* 第 L885-L890 行：interrupt valid 和各类 take_* 状态来自 TLU 内部路径。

接口关系：

* 被调用：``eh2_trace_monitor`` 获取 ``probe_vif`` 后把 debug/NMI/MIP/CSR mirror
  信息并入 trace transaction；cosim scoreboard 获取 ``probe_vif`` 后监控 reset 和异步
  writeback 状态。
* 调用：连续读取 DUT 层级信号。
* 共享状态：只读 DUT 内部路径，写 ``dut_probe_intf`` 字段。

§8  IRQ、JTAG、Halt/Run 与 fetch enable
--------------------------------------------------------------------------------

§8.1  ``eh2_irq_intf`` — interrupt stimulus 管脚
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 IRQ virtual interface，并把 timer、software、external interrupt 和
NMI 信号驱动到 DUT。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L895-L904``）：

.. code-block:: systemverilog

     eh2_irq_intf #(
       .NUM_THREADS  (`RV_NUM_THREADS),
       .PIC_TOTAL_INT(`RV_PIC_TOTAL_INT)
     ) irq_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect IRQ interface to DUT interrupt signals
     assign timer_int     = irq_intf.timer_int;
     assign soft_int      = irq_intf.soft_int;
     assign extintsrc_req = irq_intf.extintsrc_req;
     assign nmi_int       = irq_intf.nmi_int;

逐段解释：

* 第 L895-L898 行：IRQ interface 参数来自 ``RV_NUM_THREADS`` 和 ``RV_PIC_TOTAL_INT``。
* 第 L901-L904 行：interface 内的 ``timer_int``、``soft_int``、``extintsrc_req``、
  ``nmi_int`` 连续赋值到 DUT 输入侧信号。

接口关系：

* 被调用：IRQ driver 和 virtual sequence 通过 ``irq_vif`` 驱动 interrupt。
* 调用：实例化 ``eh2_irq_intf``。
* 共享状态：读 ``irq_intf`` 字段，写 DUT interrupt signal。

§8.2  ``eh2_jtag_intf`` — JTAG stimulus 与 TDO 回读
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 JTAG virtual interface，把 ``tck/tms/tdi/trst_n`` 驱动到 DUT，并把 DUT
``jtag_tdo`` 回灌到 interface。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L909-L916``）：

.. code-block:: systemverilog

     eh2_jtag_intf jtag_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect JTAG interface to DUT JTAG signals
     assign jtag_tck    = jtag_intf.tck;
     assign jtag_tms    = jtag_intf.tms;
     assign jtag_tdi    = jtag_intf.tdi;
     assign jtag_trst_n = jtag_intf.trst_n;
     assign jtag_intf.tdo = jtag_tdo;

逐段解释：

* 第 L909 行：``eh2_jtag_intf`` 使用 core clock/reset；JTAG driver 内部再驱动 TCK/TMS/TDI。
* 第 L912-L915 行：JTAG 输入方向从 interface 到 DUT。
* 第 L916 行：TDO 方向相反，从 DUT 回写到 ``jtag_intf.tdo``。

接口关系：

* 被调用：JTAG driver 通过 ``jtag_vif`` 执行 TAP/DMI 操作。
* 调用：实例化 ``eh2_jtag_intf``。
* 共享状态：读 interface stimulus，写 DUT JTAG 输入；读 DUT ``jtag_tdo``，写 interface。

§8.3  ``eh2_halt_run_intf`` — halt/run 请求与响应回灌
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 UVM halt/run 请求接到 DUT 的 MPC/CPU halt-run 输入，并把 DUT ack/status 回灌
到 ``halt_run_vif``，供 base test 和 halt/run agent 使用。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L921-L934``）：

.. code-block:: systemverilog

     eh2_halt_run_intf halt_run_vif (.clk(core_clk), .rst_n(rst_l));

     // Connect halt/run interface to DUT signals
     assign mpc_debug_halt_req = halt_run_vif.mpc_debug_halt_req;
     assign mpc_debug_run_req  = halt_run_vif.mpc_debug_run_req;
     assign mpc_reset_run_req  = halt_run_vif.mpc_reset_run_req;
     assign i_cpu_halt_req     = halt_run_vif.i_cpu_halt_req;
     assign i_cpu_run_req      = halt_run_vif.i_cpu_run_req;

     // Feed acknowledgment signals back to interface
     assign halt_run_vif.o_cpu_halt_ack     = o_cpu_halt_ack[0];
     assign halt_run_vif.o_cpu_run_ack      = o_cpu_run_ack[0];
     assign halt_run_vif.o_cpu_halt_status  = o_cpu_halt_status[0];
     assign halt_run_vif.o_debug_mode_status = o_debug_mode_status[0];

逐段解释：

* 第 L921 行：实例化 ``eh2_halt_run_intf``。
* 第 L924-L928 行：MPC debug halt/run/reset-run 和 CPU halt/run 请求由 interface 驱动到 DUT。
* 第 L931-L934 行：只取线程 0 的 ``o_cpu_*`` 和 ``o_debug_mode_status`` 回写到 interface。

接口关系：

* 被调用：``core_eh2_base_test`` 通过 ``halt_run_vif`` 在加载 binary 前后 halt/release
  core；halt/run agent driver 和 monitor 也使用同一个 key。
* 调用：实例化 ``eh2_halt_run_intf``。
* 共享状态：双向连接请求和 ack/status。

§8.4  ``fetch_enable_intf`` — fetch enable virtual handle
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 fetch enable interface，并通过 ``uvm_config_db`` 交给 sequence。源文件在
TB 顶层没有把该 interface 进一步连接到 DUT 端口。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L937-L939``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Fetch Enable Interface Instance (for fetch-enable toggling)
     //--------------------------------------------------------------------------
     fetch_enable_intf fetch_en_intf();

逐段解释：

* 第 L937-L939 行：创建 ``fetch_en_intf`` 实例；构造函数没有显式 clock/reset 端口。
* 该 interface 后续在 L1132 被设置为 ``fetch_vif``，由 sequence 侧获取。

接口关系：

* 被调用：``core_eh2_seq_lib.sv`` 和 ``core_eh2_new_seq_lib.sv`` 中的 fetch 相关
  sequence 获取 ``fetch_vif``。
* 调用：实例化 ``fetch_enable_intf``。
* 共享状态：只通过 ``uvm_config_db`` 暴露 virtual handle。

§9  Coverage、CSR 与 instruction monitor interface
--------------------------------------------------------------------------------

§9.1  ``eh2_fcov_if`` — decode/TLU/PMU 信号覆盖采样
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 DUT 内部 decode、TLU、branch、flush、stall、exception、interrupt、debug、
PIC、LSU PMU 和 cache PMU 信号接入功能覆盖 interface。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L944-L966``）：

.. code-block:: systemverilog

     eh2_fcov_if u_fcov_if (
       .clk_i                    (core_clk),
       .rst_l_i                  (rst_l),

       // Pipeline valids (from eh2_dec internal signals)
       .dec_ib0_valid_d          (dut.veer.dec.dec_ib0_valid_d),
       .dec_ib1_valid_d          (dut.veer.dec.dec_ib1_valid_d),
       .dec_i1_valid_e1          (dut.veer.dec.dec_i1_valid_e1),
       .dec_tlu_i0_valid_e4      (dut.veer.dec.tlu.tlumt[0].tlu.dec_tlu_i0_valid_e4),
       .dec_tlu_i1_valid_e4      (dut.veer.dec.tlu.tlumt[0].tlu.dec_tlu_i1_valid_e4),
       .tlu_i0_commit_cmt        (dut.veer.dec.tlu.tlumt[0].tlu.tlu_i0_commit_cmt),
       .tlu_i1_commit_cmt        (dut.veer.dec.tlu.tlumt[0].tlu.tlu_i1_commit_cmt),

       // Instructions at decode
       .dec_i0_instr_d            (dut.veer.dec.dec_i0_instr_d),
       .dec_i1_instr_d            (dut.veer.dec.dec_i1_instr_d),
       .dec_i0_pc4_d              (dut.veer.dec.dec_i0_pc4_d),
       .dec_i1_pc4_d              (dut.veer.dec.dec_i1_pc4_d),

       // Decode packets (from decode_ctl instance)
       .i0_dec                    (dut.veer.dec.decode.i0_dp),
       .i1_dec                    (dut.veer.dec.decode.i1_dp),

逐段解释：

* 第 L944-L946 行：coverage interface 使用 ``core_clk`` 和 ``rst_l``。
* 第 L949-L955 行：pipeline valid 和 commit 信号来自 DEC/TLU 层级路径。
* 第 L958-L961 行：slot 0/slot 1 的 decode instruction 和 compressed 判断相关 PC4 信号被接入。
* 第 L964-L966 行：decode packet ``i0_dp``、``i1_dp`` 从 decode_ctl 实例传入 coverage。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L993-L1025``）：

.. code-block:: systemverilog

       // Exceptions (TLU internal)
       .i0_exception_valid_e4     (dut.veer.dec.tlu.tlumt[0].tlu.i0_exception_valid_e4),
       .lsu_exc_valid_e4          (dut.veer.dec.tlu.tlumt[0].tlu.lsu_exc_valid_e4),
       .ebreak_e4                 (dut.veer.dec.tlu.tlumt[0].tlu.ebreak_e4),
       .ecall_e4                  (dut.veer.dec.tlu.tlumt[0].tlu.ecall_e4),
       .illegal_e4                (dut.veer.dec.tlu.tlumt[0].tlu.illegal_e4),
       .mret_e4                   (dut.veer.dec.tlu.tlumt[0].tlu.mret_e4),
       .inst_acc_e4               (dut.veer.dec.tlu.tlumt[0].tlu.inst_acc_e4),

       // Interrupts (TLU internal)
       .interrupt_valid           (dut.veer.dec.tlu.tlumt[0].tlu.interrupt_valid),
       .take_ext_int              (dut.veer.dec.tlu.tlumt[0].tlu.take_ext_int),
       .take_timer_int            (dut.veer.dec.tlu.tlumt[0].tlu.take_timer_int),
       .take_soft_int             (dut.veer.dec.tlu.tlumt[0].tlu.take_soft_int),
       .take_nmi                  (dut.veer.dec.tlu.tlumt[0].tlu.take_nmi),
       .take_ce_int               (dut.veer.dec.tlu.tlumt[0].tlu.take_ce_int),

       // Debug (decode output)
       .dec_tlu_dbg_halted        (dut.veer.dec.dec_tlu_dbg_halted[0]),
       .dec_tlu_debug_mode        (dut.veer.dec.dec_tlu_debug_mode[0]),

       // PIC (TLU internal)
       .dec_tlu_meicurpl          (dut.veer.dec.tlu.tlumt[0].tlu.tlu_meicurpl),

逐段解释：

* 第 L993-L1000 行：E4 stage exception 相关信号全部来自 ``tlumt[0].tlu``。
* 第 L1002-L1008 行：interrupt valid 和 take_* 信号同样来自线程 0 TLU 路径。
* 第 L1011-L1016 行：debug halted/debug mode 以及 PIC priority/id 字段接入 coverage。
* 第 L1019-L1025 行：源文件后续还接入 LSU PMU 和 cache PMU 信号。

接口关系：

* 被调用：功能覆盖 interface 自身采样这些输入；``uvm_config_db`` 也把
  ``u_fcov_if`` 暴露为 ``fcov_vif``。
* 调用：实例化 ``eh2_fcov_if``。
* 共享状态：只读 DUT 内部信号。

§9.2  ``eh2_pmp_fcov_if`` — PMP 覆盖 scaffold
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 PMP coverage interface，但默认参数和输入均为非 PMP 配置：``PMPEnable``
为 0，PMP 配置/地址/error/data_req 接 0，只有 ``debug_mode`` 从 DUT 读取。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1031-L1054``）：

.. code-block:: systemverilog

     // The default EH2 configuration used by this platform does not implement
     // PMP/ePMP, but the interface is instantiated to keep the coverage scaffold
     // complete and ready for PMP-enabled configurations.
     eh2_pmp_fcov_if #(
       .PMPEnable      (1'b0),
       .PMPGranularity (0),
       .PMPNumRegions  (4)
     ) u_pmp_fcov_if (
       .clk_i          (core_clk),
       .rst_l_i        (rst_l),
       .pmp_cfg_lock   ('0),
       .pmp_cfg_mode   ('0),
       .pmp_cfg_exec   ('0),
       .pmp_cfg_write  ('0),
       .pmp_cfg_read   ('0),
       .pmp_addr       ('0),
       .mseccfg_mml    (1'b0),
       .mseccfg_mmwp   (1'b0),
       .mseccfg_rlb    (1'b0),
       .pmp_iside_err  (1'b0),
       .pmp_dside_err  (1'b0),
       .debug_mode     (dut.veer.dec.dec_tlu_debug_mode[0]),
       .data_req       (1'b0)
     );

逐段解释：

* 第 L1031-L1033 行：源文件注释说明默认 EH2 配置不实现 PMP/ePMP，但保留 coverage scaffold。
* 第 L1034-L1038 行：参数中 ``PMPEnable`` 固定为 0，region 数为 4。
* 第 L1039-L1054 行：除了 ``debug_mode`` 从 DUT 读取，其余 PMP 配置、地址、error 和
  ``data_req`` 输入都接 0。

接口关系：

* 被调用：coverage interface 在仿真中实例存在。
* 调用：实例化 ``eh2_pmp_fcov_if``。
* 共享状态：仅读 ``dut.veer.dec.dec_tlu_debug_mode[0]``。

§9.3  ``eh2_csr_if`` — CSR decode/writeback 监视
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 CSR decode 和 writeback 相关信号映射到 ``eh2_csr_if``，供 env 可选获取。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1059-L1075``）：

.. code-block:: systemverilog

     eh2_csr_if u_csr_if (.clk(core_clk), .rst_n(rst_l));

     // CSR access valid at decode stage
     assign u_csr_if.csr_access = dut.veer.dec.dec_i0_csr_any_unq_d;
     // CSR address at decode (read address = instruction[31:20])
     assign u_csr_if.csr_addr   = dut.veer.dec.dec_i0_csr_rdaddr_d;
     // CSR read data from TLU MUX
     assign u_csr_if.csr_rdata  = dut.veer.dec.dec_i0_csr_rddata_d;
     // CSR write enable at writeback
     assign u_csr_if.csr_wen    = dut.veer.dec.dec_i0_csr_wen_wb;
     // CSR write data at writeback
     assign u_csr_if.csr_wdata  = dut.veer.dec.dec_i0_csr_wrdata_wb;
     // CSR operation type from decode packet
     assign u_csr_if.csr_read   = dut.veer.dec.decode.i0_dp.csr_read;
     assign u_csr_if.csr_write  = dut.veer.dec.decode.i0_dp.csr_write;
     assign u_csr_if.csr_set    = dut.veer.dec.decode.i0_dp.csr_set;
     assign u_csr_if.csr_clr    = dut.veer.dec.decode.i0_dp.csr_clr;

逐段解释：

* 第 L1059 行：实例化 CSR interface。
* 第 L1062-L1070 行：CSR access、address、read data、write enable 和 write data 来自 DEC
  层级信号。
* 第 L1072-L1075 行：CSR operation type 从 decode packet 的 read/write/set/clr 字段取得。

接口关系：

* 被调用：``core_eh2_env`` 通过 ``csr_vif`` 可选获取该 interface。
* 调用：实例化 ``eh2_csr_if``。
* 共享状态：只读 DUT decode/TLU 信号。

§9.4  ``eh2_instr_monitor_if`` — decode slot 监视
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 slot 0/slot 1 decode 阶段 instruction、compressed、branch、stall、flush 和
dual-issue 状态交给 instruction monitor interface。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1080-L1100``）：

.. code-block:: systemverilog

     eh2_instr_monitor_if u_instr_monitor_if (.clk(core_clk), .rst_n(rst_l));

     // I0 (slot 0) decode stage
     assign u_instr_monitor_if.i0_valid           = dut.veer.dec.dec_ib0_valid_d;
     assign u_instr_monitor_if.i0_instr           = dut.veer.dec.dec_i0_instr_d;
     assign u_instr_monitor_if.i0_compressed      = ~dut.veer.dec.dec_i0_pc4_d;
     assign u_instr_monitor_if.i0_instr_compressed = dut.veer.dec.dec_i0_instr_d[15:0];
     assign u_instr_monitor_if.i0_branch_taken    = dut.veer.dec.exu_i0_br_valid_e4;
     assign u_instr_monitor_if.i0_stall           = dut.veer.dec.tlu.tlumt[0].tlu.dec_pmu_decode_stall;

     // I1 (slot 1) decode stage
     assign u_instr_monitor_if.i1_valid           = dut.veer.dec.dec_ib1_valid_d;
     assign u_instr_monitor_if.i1_instr           = dut.veer.dec.dec_i1_instr_d;
     assign u_instr_monitor_if.i1_compressed      = ~dut.veer.dec.dec_i1_pc4_d;
     assign u_instr_monitor_if.i1_instr_compressed = dut.veer.dec.dec_i1_instr_d[15:0];
     assign u_instr_monitor_if.i1_branch_taken    = dut.veer.dec.exu_i1_br_valid_e4;
     assign u_instr_monitor_if.i1_stall           = dut.veer.dec.tlu.tlumt[0].tlu.dec_pmu_decode_stall;

     // Pipeline control
     assign u_instr_monitor_if.pipe_flush  = dut.veer.dec.exu_flush_final[0];
     assign u_instr_monitor_if.dual_issue  = dut.veer.dec.dec_ib0_valid_d & dut.veer.dec.dec_ib1_valid_d;

逐段解释：

* 第 L1080 行：实例化 instruction monitor interface。
* 第 L1083-L1088 行：slot 0 的 valid、instruction、compressed、branch taken 和 stall 状态
  接入 interface。
* 第 L1091-L1096 行：slot 1 使用对应的 ``dec_ib1``、``dec_i1`` 和 ``exu_i1`` 信号。
* 第 L1099-L1100 行：pipeline flush 来自 ``exu_flush_final[0]``，dual issue 由两个 decode
  valid 做与运算。

接口关系：

* 被调用：``core_eh2_env`` 通过 ``instr_monitor_vif`` 可选获取该 interface。
* 调用：实例化 ``eh2_instr_monitor_if``。
* 共享状态：只读 DUT decode/TLU 信号。

§10  ``uvm_config_db`` 注入与 ``run_test``
--------------------------------------------------------------------------------

§10.1  virtual interface 注入 — 从 module 世界进入 UVM 树
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 TB 顶层创建的 virtual interface 句柄放入 ``uvm_config_db``。路径 pattern
决定接收组件范围。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1105-L1120``）：

.. code-block:: systemverilog

     initial begin
       // Store interface references for UVM agents
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

* 第 L1107 行：``tb_vif`` 面向 ``*`` 设置，base test 使用 ``get(null, "", "tb_vif", tb_vif)``
  获取。
* 第 L1108-L1110 行：只注入 LSU、IFU、SB 三个 AXI4 agent 的 ``vif``；没有 DMA agent 注入。
* 第 L1113-L1114 行：trace monitor 获得 ``trace_intf``，DUT probe monitor 获得
  ``dut_probe_intf``。
* 第 L1117-L1120 行：同一个 ``dut_probe_intf`` 还以 ``probe_vif`` 名称提供给 trace monitor
  和 cosim agent/scoreboard 路径。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1122-L1145``）：

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
     end

逐段解释：

* 第 L1123-L1129 行：IRQ、JTAG、halt/run interface 都面向 ``*`` 设置，agent、sequence 和
  base test 可按 key 获取。
* 第 L1132-L1135 行：fetch enable 和 functional coverage interface 同样注入全局范围。
* 第 L1138-L1144 行：CSR、instruction monitor 和 RVFI interface 分别以 ``csr_vif``、
  ``instr_monitor_vif``、``rvfi_vif`` 注入。
* 第 L1145 行：结束 config DB setup 的 ``initial`` 块；所有 set 都发生在 ``run_test``
  之前的并行 initial 调度中。

接口关系：

* 被调用：UVM component 的 ``build_phase`` 或 sequence body 通过相同 key 获取。
* 调用：``uvm_config_db::set``。
* 共享状态：把 module 实例句柄暴露到 UVM 对象层。

§10.2  ``run_test()`` — 启动 UVM test
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：调用 UVM runtime，按命令行 ``+UVM_TESTNAME`` 或默认工厂配置创建 test。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1147-L1152``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // UVM Test Execution
     //--------------------------------------------------------------------------
     initial begin
       run_test();
     end

逐段解释：

* 第 L1147-L1149 行：注释标明这是 UVM test execution 区域。
* 第 L1150-L1152 行：``initial`` 块调用 ``run_test()``，把控制权交给 UVM phase 机制。

接口关系：

* 被调用：仿真启动自动执行。
* 调用：UVM ``run_test``。
* 共享状态：不直接读写 TB 信号，但 UVM test 会通过前一节注入的 virtual interface
  访问 TB 服务和 DUT 端口视图。

§11  超时与 completion 的双层防护
--------------------------------------------------------------------------------

§11.1  TB 顶层 safety timeout
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供最后一层 30 分钟安全超时；如果 UVM 自身 timeout 没有结束仿真，该块会打印
安全超时信息并调用 ``$finish``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L566-L575``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Safety Timeout (UVM handles timeouts via the test - this is a last resort)
     //--------------------------------------------------------------------------
     initial begin
       #(64'd1_800_000_000_000);  // 30 minutes safety timeout (matches env_cfg.timeout_ns)
       $display("========================================");
       $display("SAFETY TIMEOUT (TB top) - 30 minutes");
       $display("========================================");
       $finish;
     end

逐段解释：

* 第 L566-L568 行：注释说明该 timeout 是 last resort，常规 timeout 由 UVM test 处理。
* 第 L570 行：延时常量为 ``64'd1_800_000_000_000``，注释标注为 30 minutes。
* 第 L571-L574 行：打印 timeout banner 后调用 ``$finish``，直接结束仿真。

接口关系：

* 被调用：仿真启动自动执行。
* 调用：``$display`` 和 ``$finish``。
* 共享状态：不读写 DUT 状态。

§11.2  Base test completion — mailbox 标志的 UVM 消费端
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 TB 顶层的 mailbox 标志如何被 UVM test 使用。该逻辑不在
``core_eh2_tb_top.sv`` 中实现，但它是 ``tb_vif`` 字段的直接消费者。

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

* 第 L347-L355 行：completion 的第一路是 signature/mailbox；如果 ``use_signature`` 关闭，
  该分支永久等待。
* 第 L357-L361 行：第二路是 wall-clock timeout，使用 ``env_cfg.timeout_ns``。
* 第 L363-L367 行：第三路是 cycle count timeout，通过 TB 注入的 ``tb_vif.wait_clks``
  等待 ``env_cfg.max_cycles``。
* 第 L369-L378 行：源文件后续还有 double-fault detector 分支，``join_any`` 后关闭其它分支。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L382-L399``）：

.. code-block:: systemverilog

     virtual task wait_for_signature();
       forever begin
         @(posedge tb_vif.clk);
         if (tb_vif.mailbox_test_done) begin
           // Check which event fired
           if (tb_vif.mailbox_data[7:0] == 8'hFF) begin
             `uvm_info(test_name, "TEST PASSED (signature)", UVM_LOW)
           end else begin
             `uvm_error(test_name, "TEST FAILED (signature)")
           end
           // EH2 can retire the mailbox store before the external AXI write
           // response is observed. Leave a short drain window so monitors and
           // scoreboards can close outstanding transactions before report_phase.
           tb_vif.wait_clks(10);
           return;
         end
       end
     endtask

逐段解释：

* 第 L383-L385 行：每个 ``tb_vif.clk`` 上升沿检查 ``mailbox_test_done``。
* 第 L387-L391 行：仍然以 ``tb_vif.mailbox_data[7:0]`` 判断 PASS/FAIL，和 TB 顶层
  mailbox monitor 的 ``8'hFF``/其它完成值保持一致。
* 第 L392-L395 行：完成后等待 10 个 clock，让外部 AXI write response 和 scoreboard
  outstanding transaction 有 drain 窗口。

接口关系：

* 被调用：``core_eh2_base_test.run_phase`` 调用 ``wait_for_completion``。
* 调用：``wait_for_signature``、``tb_vif.wait_clks``、UVM report 宏。
* 共享状态：读取 TB 顶层通过 ``core_eh2_tb_intf`` 暴露的 mailbox 状态。

§12  与 env 和 agent 的边界
--------------------------------------------------------------------------------

§12.1  TB 顶层只提供 virtual interface，不创建 UVM agent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：澄清职责边界。``core_eh2_tb_top.sv`` 创建 module/interface 实例并注入 config DB；
``core_eh2_env.sv`` 创建 UVM agent、monitor、scoreboard 和 virtual sequencer。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L28-L49``）：

.. code-block:: systemverilog

     // AXI4 agents (passive - monitor only)
     axi4_agent#(`RV_LSU_BUS_TAG) lsu_agent;
     axi4_agent#(`RV_IFU_BUS_TAG) ifu_agent;
     axi4_agent#(`RV_SB_BUS_TAG) sb_agent;

     // Interrupt agent (active - drives interrupts)
     eh2_irq_agent irq_agent;

     // JTAG agent (active - drives debug)
     eh2_jtag_agent jtag_agent;

     // Halt/Run agent (active - drives halt/run)
     eh2_halt_run_agent halt_run_agt;

     // Trace monitor
     eh2_trace_monitor trace_monitor;

     // DUT probe monitor
     eh2_dut_probe_monitor dut_probe_monitor;

     // Co-simulation agent (owns scoreboard + backdoor loading)
     eh2_cosim_agent cosim_agt;

逐段解释：

* 第 L28-L31 行：env 中只有 LSU、IFU、SB 三个 AXI4 agent 字段。
* 第 L33-L40 行：IRQ、JTAG、halt/run agent 是 env 的 UVM component，不是 TB module 实例。
* 第 L42-L49 行：trace monitor、DUT probe monitor 和 cosim agent 也由 env 创建，TB 顶层只负责
  向它们提供 virtual interface。

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

* 第 L73-L79 行：LSU agent 在 ``enable_axi4_error_inject`` 打开时 active，否则 passive。
* 第 L81-L85 行：IFU 和 SB agent 在源文件中始终设置为 ``UVM_PASSIVE``。
* 这里没有 ``dma_agent`` 创建语句；因此文档不应把 DMA 写成 UVM agent。

接口关系：

* 被调用：UVM build phase 创建 env 后执行这些 component 创建。
* 调用：UVM factory ``type_id::create`` 和 ``uvm_config_db::set``。
* 共享状态：使用 TB 顶层注入的 ``vif``，但 agent 生命周期由 env 管理。

§13  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`tb_top`、:ref:`appendix_b_uvm/env`、:ref:`appendix_b_uvm/axi4_agent`、
  :ref:`appendix_b_uvm/trace_agent`、:ref:`appendix_b_uvm/cosim_agent`、
  :ref:`appendix_b_uvm/irq_agent`、:ref:`appendix_b_uvm/jtag_agent`、
  :ref:`appendix_b_uvm/halt_run_agent`
* 关联 ADR：:ref:`adr-0004`、:ref:`adr-0015`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/core_eh2_tb_intf.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_rvfi_if.sv`
* 源文件：:file:`/home/host/eh2-veri/rtl/eh2_veer_wrapper_rvfi.sv`

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

§14  v2-19 ``core_eh2_tb_top.sv`` 全文段落级精读
--------------------------------------------------------------------------------

``core_eh2_tb_top.sv`` 是 UVM testbench 的硬件世界入口：它不创建 UVM component，
但负责实例化 DUT、interface、coverage、RVFI converter、probe 连接和 config DB
发布。v2-19 将该文件全文纳入 literalinclude，确保 mailbox、trace、AXI、IRQ、JTAG、
halt/run、functional coverage 和 CSR monitor 的每一段连接都有源码证据。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:全文

逐段精读：

* L1-L36：文件头、UVM import、EH2 package import 和 module 声明。这里固定了
  ``core_eh2_test_pkg`` 是测试包入口，TB 顶层作为 SystemVerilog module 驱动
  UVM run_test。
* L37-L68：时钟、复位、参数和 ``core_eh2_dut_signals.svh`` 引入。include 文件展开
  DUT 端口信号，避免在 TB 顶层手写几百个重复声明。
* L69-L90：mailbox 信号和 ``core_eh2_tb_intf``。LSU AXI write handshake 被解释成
  mailbox write，``mailbox_test_done``、``early_bin_loaded`` 通过 virtual interface
  暴露给 UVM base test。
* L91-L131：backdoor memory write、trace display 和 mailbox PASS/FAIL monitor。
  这段是 smoke/directd 测试最早可见的退出路径；``32'hD0580000`` 是测试完成地址。
* L132-L178：clock/reset 初始块和 early binary plusarg 处理。TB 支持在 reset 前通过
  ``+bin=`` 加载 ELF/hex，加载状态反馈给 base test，防止 UVM phase 与内存初始化竞态。
* L179-L547：``eh2_veer_wrapper dut`` 实例。该段连接 core clock/reset、trace、AXI、
  DMA、DMI/JTAG、PIC、timer/software interrupt、halt/run、debug 和 scan 信号，是
  testbench 到上游 EH2 wrapper 的主边界。
* L548-L575：DMA AXI tied-off。当前 UVM 主环境不主动驱动外部 DMA master，因此将 DMA
  request 侧固定为 idle；如果未来增加 DMA active agent，应从这里开始改连接。
* L576-L612：trace dump 辅助逻辑。该段按 ``trace_rv_i_valid_ip`` 打印 retire trace，
  服务手工 debug 和 cosim triage，不改变 scoreboard 数据结构。
* L613-L733：LSU、IFU、SB 三组 AXI interface 逐字段连接。每个 channel 的 valid/ready、
  id、addr、data、resp 都被映射到 UVM AXI4 agent 的 virtual interface，三组 agent
  因此能被动监控总线事务。
* L734-L755：trace interface 连接。``eh2_trace_if`` 直接接收 DUT trace packet 字段，
  trace monitor 和 cosim scoreboard 用它恢复 retire instruction、PC、exception、
  interrupt 和 GPR writeback。
* L756-L824：RVFI interface 与 ``eh2_veer_wrapper_rvfi`` converter。该段把 trace、
  LSU bus activity 和 reset/clock 转换为 RVFI-like 观察面，服务 smoke、formal-like
  debug 和后续可扩展 checker。
* L825-L907：DUT probe interface。这里用 hierarchy reference 暴露 divide cancel、
  nonblocking load、CSR、debug、exception、interrupt 等内部状态；cosim scoreboard
  依赖这些信号判断 Spike step 前后的副作用。
* L908-L945：IRQ、JTAG、halt/run 和 fetch enable interface。TB 顶层只连线并发布
  virtual interface；真正的 active driving 由 env 中的对应 agent 完成。
* L946-L1065：``eh2_fcov_if`` 实例。该段把 decode、EXU、TLU、LSU、IFU、debug 和
  interrupt 信号接到 functional coverage interface；coverage group 69.42% 的入口
  就是这组采样连接。
* L1066-L1085：CSR monitor interface。``eh2_csr_if`` 观察 CSR access、addr、rdata、
  write enable 和操作类型，用于 CSR 子环境或 coverage 侧验证。
* L1086-L1111：instruction monitor interface。该段暴露 I0/I1 decode valid、instruction、
  compressed、branch、stall、flush 和 dual issue 状态，支撑指令级 functional coverage。
* L1112-L1156：``uvm_config_db`` 发布。TB 将 tb/axi/irq/jtag/halt-run/trace/rvfi/probe/
  coverage/csr/instr interface 注入 ``uvm_test_top``，env build phase 从这里取 handle。
* L1157-L1161：``run_test()`` 与 module 结束。UVM 测试名来自 plusarg 或默认 test；
  TB 顶层在这里把 SystemVerilog module 世界交给 UVM phase 调度。
