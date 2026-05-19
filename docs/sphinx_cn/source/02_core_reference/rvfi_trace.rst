.. _rvfi_trace:

RVFI / Trace 接口
==================

:status: draft
:source: rtl/design/include/eh2_def.sv; rtl/design/dec/eh2_dec.sv; rtl/design/eh2_veer.sv; rtl/eh2_veer_wrapper_rvfi.sv; dv/uvm/core_eh2/common/trace_agent/
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界与数据流
---------------------

本章只描述当前仓库中可追溯的 trace、probe、scoreboard 与 RVFI sidecar 行为。本文档的基准
commit 为 ``feeac23a7c15114f9f962beca1758834f83dbf88``；其中
:file:`rtl/design/include/eh2_def.sv`、:file:`rtl/design/dec/eh2_dec.sv`、
:file:`rtl/design/eh2_veer.sv`、:file:`rtl/eh2_veer_wrapper_rvfi.sv`、
:file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv`、
:file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`、
:file:`dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv` 和
:file:`dv/uvm/core_eh2/env/eh2_rvfi_if.sv` 在当前工作区可能包含未进入
``HEAD`` 的验证增量。因此本章对这些文件的行号引用以当前工作树读取结果为准，frontmatter
中的 ``:commit:`` 用作本轮文档审查基线。

整体数据流如下。RTL 端的 ``eh2_trace_pkt_t`` 在 DEC 顶层生成，``eh2_veer``
把 struct 拆成顶层 trace 端口；testbench 同时把这些端口接入 UVM trace interface
和 RVFI sidecar。cosim 主路径走 ``eh2_trace_monitor`` 到
``eh2_cosim_scoreboard``；probe 路径只补充 DIV、NB-load 和 CSR/中断状态。

::

   DEC wb1 tracep
       |
       v
   eh2_trace_pkt_t
       |
       v
   eh2_veer.trace_rewire
       |
       +----------------------+------------------------------+
       |                      |                              |
       v                      v                              v
   eh2_trace_intf       eh2_veer_wrapper_rvfi          eh2_dut_probe_if
       |                      |                              |
       v                      v                              v
   eh2_trace_monitor    eh2_rvfi_if                    eh2_dut_probe_monitor
       |                                                     |
       +------------------------------+----------------------+
                                      v
                           eh2_cosim_scoreboard
                                      |
                                      v
                             Spike cosim DPI

该图刻意区分三件事：第一，``trace pkt`` 是退休指令主记录；第二，``RVFI``
是由 sidecar 从 trace 与 LSU bus 推导出的标准化视图；第三，probe 不再是常规
wb 主路径，而是提供异步写回提示、CSR 快照和中断/调试状态。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L7-L18``）：

.. code-block:: systemverilog

   // Phase 1 simplification (ADR-0004): The RTL trace packet now carries the
   // RVFI-equivalent {wb_valid, rd_addr, rd_wdata} tuple, so each trace_seq_item
   // arriving from the trace monitor is self-contained. The scoreboard no longer
   // needs to correlate trace items with a separate writeback FIFO.
   //
   // Multi-thread support (ADR-0008): When NUM_THREADS=2, per-thread state
   // (pending_trace_q, async_wb_q, prev_mip, insn_cnt, mismatch_count) is
   // maintained independently and routed by trace_seq_item.thread_id.
   //
   // Async writeback corner cases (NB-load, DIV-cancel) still arrive via the
   // dut probe monitor, but only as suppress hints—they override wb_valid for
   // the matching trace item by strict wb_tag association (issue 66).

**逐段解释**：

* 第 L7-L10 行：scoreboard 头注释把当前主路径写清楚，``trace_seq_item`` 已经携带
  ``wb_valid``、``rd_addr`` 和 ``rd_wdata``，不再需要把 trace 和单独 wb FIFO 做主路径匹配。
* 第 L12-L14 行：多线程状态按 ``thread_id`` 分开维护，本文后续解释 trace item 时只讨论
  当前代码实际监控的 thread 0，但 scoreboard 数据结构已经按 2 个线程数组化。
* 第 L16-L18 行：异步写回角落仍从 ``dut probe monitor`` 进入，不过语义是
  ``suppress`` 或覆盖提示，而不是常规 wb 记录。

**接口关系**：

* **被调用**：scoreboard 由 UVM env 在 cosim enabled 时创建并连接。
* **调用**：scoreboard 后续调用 Spike cosim DPI，例如 ``riscv_cosim_step``。
* **共享状态**：``pending_trace_q``、``async_wb_q``、``prev_mip``、
  ``mismatch_count`` 和 ``insn_cnt`` 按 thread 维度共享。

§2  ``eh2_trace_pkt_t`` — RTL trace 包字段定义
------------------------------------------------

**职责**：``eh2_trace_pkt_t`` 定义 RTL 到验证平台的退休 trace payload。字段包含
双槽位有效位、指令、PC、异常、中断、``tval``，以及 verification-only 的寄存器写回视图。

**关键代码** （``rtl/design/include/eh2_def.sv:L4-L19``）：

.. code-block:: systemverilog

   package eh2_pkg;
   // performance monitor stuff
   typedef struct packed {
                          logic [1:0] trace_rv_i_valid_ip;
                          logic [63:0] trace_rv_i_insn_ip;
                          logic [63:0] trace_rv_i_address_ip;
                          logic [1:0] trace_rv_i_exception_ip;
                          logic [4:0] trace_rv_i_ecause_ip;
                          logic [1:0] trace_rv_i_interrupt_ip;
                          logic [31:0] trace_rv_i_tval_ip;
                          // Verification-only RVFI-equivalent register writeback signals.
                          // Lane 0 = i0, Lane 1 = i1.
                          logic [1:0]  trace_rv_i_rd_valid_ip;
                          logic [9:0]  trace_rv_i_rd_addr_ip;
                          logic [63:0] trace_rv_i_rd_wdata_ip;
                          } eh2_trace_pkt_t;

**逐段解释**：

* 第 L4-L6 行：struct 位于 ``eh2_pkg`` 包内，注释把这组字段归入性能监视相关定义。
* 第 L7-L13 行：基础 trace 字段覆盖 ``valid``、``insn``、``address``、
  ``exception``、``ecause``、``interrupt`` 和 ``tval``。其中 ``insn`` 与
  ``address`` 为 64 位，是为了在一个线程内承载 i0/i1 两个 retire 槽位。
* 第 L14-L18 行：写回字段明确标注为 verification-only，并且 lane 0 对应 i0、lane 1 对应
  i1。``rd_addr`` 为 10 位，按两个 5 位目的寄存器拼接；``rd_wdata`` 为 64 位，按两个
  32 位写回数据拼接。

**接口关系**：

* **被调用**：``eh2_dec`` 生成 ``trace_rv_trace_pkt[i]``，``eh2_veer`` 再把该 struct
  拆成顶层输出端口。
* **调用**：struct 本身不调用函数，只作为 packed payload。
* **共享状态**：共享状态是端口级 trace payload；没有内部寄存状态。

§3  DEC ``tracep`` — 在 WB1 级生成 trace pkt
---------------------------------------------

**职责**：``tracep`` generate 块把 DEC/TLU WB1 阶段的退休指令、PC、异常、中断、
``mtval`` 和写回信息打包进 ``eh2_trace_pkt_t``。

**关键代码** （``rtl/design/dec/eh2_dec.sv:L1001-L1022``）：

.. code-block:: systemverilog

   // trace
      // also need retires_p==2
        for (genvar i=0; i<pt.NUM_THREADS; i++) begin : tracep

           assign trace_rv_trace_pkt[i].trace_rv_i_insn_ip    = { dec_i1_inst_wb1[31:0],     dec_i0_inst_wb1[31:0] };
           assign trace_rv_trace_pkt[i].trace_rv_i_address_ip = { dec_i1_pc_wb1[31:1], 1'b0, dec_i0_pc_wb1[31:1], 1'b0 };

           assign trace_rv_trace_pkt[i].trace_rv_i_valid_ip =     {
                                                                                              dec_tlu_i1_valid_wb1[i] | dec_tlu_i1_exc_valid_wb1[i],
                                                                   dec_tlu_int_valid_wb1[i] | dec_tlu_i0_valid_wb1[i] | dec_tlu_i0_exc_valid_wb1[i]
                                                                   };
           assign trace_rv_trace_pkt[i].trace_rv_i_exception_ip = {dec_tlu_i1_exc_valid_wb1[i],
                                                                   dec_tlu_int_valid_wb1[i] | dec_tlu_i0_exc_valid_wb1[i]};

           assign trace_rv_trace_pkt[i].trace_rv_i_ecause_ip =     dec_tlu_exc_cause_wb1[i][4:0];  // replicate across ports
           assign trace_rv_trace_pkt[i].trace_rv_i_interrupt_ip = {1'b0, dec_tlu_int_valid_wb1[i]};
           assign trace_rv_trace_pkt[i].trace_rv_i_tval_ip =    dec_tlu_mtval_wb1[i][31:0];        // replicate across ports
           // Verification-only RVFI-equivalent writeback (lane 0 = i0, lane 1 = i1).
           assign trace_rv_trace_pkt[i].trace_rv_i_rd_valid_ip = {dec_i1_wen_wb1, dec_i0_wen_wb1};
           assign trace_rv_trace_pkt[i].trace_rv_i_rd_addr_ip  = {dec_i1_waddr_wb1[4:0], dec_i0_waddr_wb1[4:0]};
           assign trace_rv_trace_pkt[i].trace_rv_i_rd_wdata_ip = {dec_i1_wdata_wb1[31:0], dec_i0_wdata_wb1[31:0]};

**逐段解释**：

* 第 L1001-L1004 行：trace 生成逻辑在 ``pt.NUM_THREADS`` 上展开，每个线程一个
  ``trace_rv_trace_pkt[i]``。
* 第 L1005-L1006 行：``insn`` 和 ``address`` 都按 ``{i1, i0}`` 拼接。PC 拼接时使用
  ``pc[31:1]`` 再补 ``1'b0``，因此 trace 端口看到的是低位对齐后的 32 位 PC。
* 第 L1008-L1013 行：``valid`` 的 i1 位来自 i1 valid 或 i1 exception；i0 位还并入
  ``dec_tlu_int_valid_wb1[i]``。``exception`` 的 i0 位也并入 interrupt valid，这使
  interrupt-only item 能走同一条 trace 输出路径。
* 第 L1015-L1017 行：``ecause`` 与 ``tval`` 来自 TLU WB1 信号，并在注释中标明在端口间复制；
  ``interrupt`` 只把 i0 lane 置为 ``dec_tlu_int_valid_wb1[i]``，i1 lane 固定为 0。
* 第 L1018-L1021 行：verification-only 写回字段同样按 ``{i1, i0}`` 拼接，使用 WB1 阶段
  ``wen``、``waddr`` 和 ``wdata``。这正是后续 trace monitor 能直接填 ``wb_*`` 字段的来源。

**接口关系**：

* **被调用**：``eh2_dec`` 顶层在综合/仿真 elaboration 时实例化该 generate 块。
* **调用**：该块不调用任务；组合赋值读取 DEC/TLU WB1 信号。
* **共享状态**：读取 ``dec_tlu_*_wb1``、``dec_i*_inst_wb1``、``dec_i*_pc_wb1``、
  ``dec_i*_wen_wb1``、``dec_i*_waddr_wb1`` 和 ``dec_i*_wdata_wb1``。

§4  ``eh2_veer`` — trace 端口导出
---------------------------------

**职责**：``eh2_veer`` 把内部 ``eh2_trace_pkt_t`` 拆成模块输出端口，使 testbench
和 sidecar 能直接接入 trace 信号。

**关键代码** （``rtl/design/eh2_veer.sv:L39-L49``）：

.. code-block:: systemverilog

      output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_insn_ip,
      output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_address_ip,
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_valid_ip,
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_exception_ip,
      output logic [pt.NUM_THREADS-1:0] [4:0]  trace_rv_i_ecause_ip,
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_interrupt_ip,
      output logic [pt.NUM_THREADS-1:0] [31:0] trace_rv_i_tval_ip,
      // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
      output logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_rd_valid_ip,
      output logic [pt.NUM_THREADS-1:0] [9:0]  trace_rv_i_rd_addr_ip,
      output logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_rd_wdata_ip,

**逐段解释**：

* 第 L39-L45 行：基础 trace 输出端口保留线程维度 ``pt.NUM_THREADS``，并把每线程两个槽位编码在
  64 位或 2 位字段内。
* 第 L46-L49 行：写回视图同样以线程维度导出，注释再次标明 lane 0 为 i0、lane 1 为 i1。

**关键代码** （``rtl/design/eh2_veer.sv:L1478-L1489``）：

.. code-block:: systemverilog

      for (genvar i=0; i<pt.NUM_THREADS; i++) begin : trace_rewire

         assign trace_rv_i_insn_ip[i][63:0]     = trace_rv_trace_pkt[i].trace_rv_i_insn_ip[63:0];
         assign trace_rv_i_address_ip[i][63:0]  = trace_rv_trace_pkt[i].trace_rv_i_address_ip[63:0];
         assign trace_rv_i_valid_ip[i][1:0]     = trace_rv_trace_pkt[i].trace_rv_i_valid_ip[1:0];
         assign trace_rv_i_exception_ip[i][1:0] = trace_rv_trace_pkt[i].trace_rv_i_exception_ip[1:0];
         assign trace_rv_i_ecause_ip[i][4:0]    = trace_rv_trace_pkt[i].trace_rv_i_ecause_ip[4:0];
         assign trace_rv_i_interrupt_ip[i][1:0] = trace_rv_trace_pkt[i].trace_rv_i_interrupt_ip[1:0];
         assign trace_rv_i_tval_ip[i][31:0]     = trace_rv_trace_pkt[i].trace_rv_i_tval_ip[31:0];
         assign trace_rv_i_rd_valid_ip[i][1:0]  = trace_rv_trace_pkt[i].trace_rv_i_rd_valid_ip[1:0];
         assign trace_rv_i_rd_addr_ip[i][9:0]   = trace_rv_trace_pkt[i].trace_rv_i_rd_addr_ip[9:0];
         assign trace_rv_i_rd_wdata_ip[i][63:0] = trace_rv_trace_pkt[i].trace_rv_i_rd_wdata_ip[63:0];

**逐段解释**：

* 第 L1478 行：``trace_rewire`` 同样按 ``pt.NUM_THREADS`` 展开，保持与 DEC trace pkt 的线程维度一致。
* 第 L1480-L1486 行：基础 trace 字段逐字段透传，没有重新编码，也没有过滤 valid、exception
  或 interrupt。
* 第 L1487-L1489 行：``rd_valid``、``rd_addr`` 和 ``rd_wdata`` 被原样拆出到顶层端口。
  因此 UVM trace interface 看到的写回视图与 DEC ``tracep`` 拼接结果一致。

**接口关系**：

* **被调用**：testbench 中 DUT 实例连接这些 trace 端口。
* **调用**：``trace_rewire`` 不调用下层逻辑，只做组合透传。
* **共享状态**：读取内部 ``trace_rv_trace_pkt``，驱动模块外部 trace 端口。

§5  TB trace 信号 — 从 DUT 端口进入 ``eh2_trace_intf``
----------------------------------------------------------------------

**职责**：testbench 在信号声明层保存 DUT trace 端口，并实例化 ``eh2_trace_intf``，
让 UVM monitor 可以通过 virtual interface 同步采样 trace。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:L14-L25``）：

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

**逐段解释**：

* 第 L14-L21 行：testbench 声明基础 trace 信号，线程维度使用宏 ``RV_NUM_THREADS``。
* 第 L22-L25 行：写回视图信号也在 testbench 层声明，宽度与 ``eh2_veer`` 输出端口一致。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L728-L744``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Trace Interface Instance (for UVM trace monitor)
     //--------------------------------------------------------------------------
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

**逐段解释**：

* 第 L728-L732 行：``eh2_trace_intf`` 以 ``RV_NUM_THREADS`` 参数化，并使用 ``core_clk``
  与 ``rst_l``。
* 第 L734-L744 行：DUT trace 信号逐字段接到 interface，字段名保持语义一致。写回三元组
  ``rd_valid``、``rd_addr``、``rd_wdata`` 与基础 trace 字段一起进入 monitor 采样域。

**接口关系**：

* **被调用**：UVM config_db 后续把 ``trace_intf`` 交给 ``eh2_trace_monitor``。
* **调用**：TB 顶层不调用函数，只实例化 interface 并做连续赋值。
* **共享状态**：``trace_intf`` 是 RTL trace 进入 UVM 的共享采样边界。

§6  ``eh2_trace_intf`` — 按 i0/i1 解码 trace bus
-------------------------------------------------

**职责**：``eh2_trace_intf`` 接收 packed trace bus，并给 monitor 提供 thread 0
的 i0/i1 便捷信号。当前代码包含 ``rd_valid``、``rd_addr`` 和 ``rd_wdata``，所以源文件头部
关于「No rd_addr/rd_wdata」的注释已经与实现不一致；本文按代码实现描述行为。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L13-L18``）：

.. code-block:: systemverilog

   // Limitations vs RVFI:
   //   - No rd_addr/rd_wdata (register writeback not directly visible)
   //   - No mem_addr/mem_wdata/mem_rdata (memory access not directly visible)
   //   - No CSR updates
   //   - Only 2 instructions per cycle per thread

**逐段解释**：

* 第 L13-L18 行：这段注释仍保留旧限制描述，其中 ``No rd_addr/rd_wdata`` 与同一文件
  第 L34-L37 行的信号声明冲突。文档不按该旧注释推导当前行为，只把它作为需要读者注意的
  历史注释残留。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L26-L37``）：

.. code-block:: systemverilog

     // Trace signals
     logic [NUM_THREADS-1:0][63:0] insn;
     logic [NUM_THREADS-1:0][63:0] address;
     logic [NUM_THREADS-1:0][1:0]  valid;
     logic [NUM_THREADS-1:0][1:0]  exception;
     logic [NUM_THREADS-1:0][4:0]  ecause;
     logic [NUM_THREADS-1:0][1:0]  interrupt;
     logic [NUM_THREADS-1:0][31:0] tval;
     // Verification-only RVFI-equivalent writeback view (lane 0 = i0, lane 1 = i1).
     logic [NUM_THREADS-1:0][1:0]  rd_valid;
     logic [NUM_THREADS-1:0][9:0]  rd_addr;
     logic [NUM_THREADS-1:0][63:0] rd_wdata;

**逐段解释**：

* 第 L26-L33 行：interface 保存从 TB 顶层接入的基础 trace 字段，仍保留线程维度。
* 第 L34-L37 行：interface 明确声明写回视图；因此 UVM monitor 可以不经过 probe 主路径获取
  常规 pipeline wb。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L60-L77``）：

.. code-block:: systemverilog

     // Decode convenience signals
     assign t0_i0_pc        = address[0][31:0];
     assign t0_i0_insn      = insn[0][31:0];
     assign t0_i0_valid     = valid[0][0];
     assign t0_i0_exception = exception[0][0];
     assign t0_i0_ecause    = ecause[0][4:0];
     assign t0_i0_wb_valid  = rd_valid[0][0];
     assign t0_i0_wb_addr   = rd_addr[0][4:0];
     assign t0_i0_wb_data   = rd_wdata[0][31:0];

     assign t0_i1_pc        = address[0][63:32];
     assign t0_i1_insn      = insn[0][63:32];
     assign t0_i1_valid     = valid[0][1];
     assign t0_i1_exception = exception[0][1];
     assign t0_i1_ecause    = ecause[0][4:0];
     assign t0_i1_wb_valid  = rd_valid[0][1];
     assign t0_i1_wb_addr   = rd_addr[0][9:5];
     assign t0_i1_wb_data   = rd_wdata[0][63:32];

**逐段解释**：

* 第 L60-L68 行：i0 使用 packed bus 的低半部分，PC、指令和写回数据均取低 32 位；
  ``rd_addr`` 取低 5 位。
* 第 L70-L77 行：i1 使用 packed bus 的高半部分，``rd_addr`` 取 ``[9:5]``，
  ``rd_wdata`` 取 ``[63:32]``。``ecause`` 对 i0/i1 都取 ``ecause[0][4:0]``，
  与 DEC 端「replicate across ports」注释一致。

**接口关系**：

* **被调用**：``eh2_trace_monitor`` 通过 virtual interface 读取 ``t0_i0_*`` 和
  ``t0_i1_*``。
* **调用**：interface 不调用任务；只提供组合解码和 clocking block。
* **共享状态**：``monitor_cb`` 在第 L79-L91 行声明输入集合，提供同步采样边界。

§7  ``eh2_trace_seq_item`` — retire item 数据模型
--------------------------------------------------

**职责**：``eh2_trace_seq_item`` 是 UVM trace monitor 发给 scoreboard 的单条退休记录。
它既包含 PC、指令、异常/中断，也包含写回、probe 状态和 trap CSR 快照。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L7-L31``）：

.. code-block:: systemverilog

   class eh2_trace_seq_item extends uvm_sequence_item;

     // Thread ID
     rand bit thread_id;

     // Instruction slot (0 or 1 - EH2 can commit 2 per cycle)
     rand bit slot;

     // Instruction information
     bit [31:0] pc;
     bit [31:0] insn;

     // Exception information
     bit        exception;
     bit [4:0]  ecause;
     bit        interrupt;
     bit [31:0] tval;

     // Register writeback (from DUT probe)
     bit        wb_valid;
     bit [4:0]  wb_dest;
     bit [31:0] wb_data;
     bit        wb_suppress;  // Writeback suppressed (killed load or canceled DIV)
     int        wb_tag;       // Writeback sequence tag for trace-to-wb correlation
     int        wb_source;    // EH2_WB_SRC_*: regular, DIV, or non-blocking load

**逐段解释**：

* 第 L7-L13 行：item 继承 ``uvm_sequence_item``，并以 ``thread_id`` 与 ``slot`` 描述
  线程和 i0/i1 槽位。
* 第 L15-L23 行：PC、指令、异常、异常原因、中断和 ``tval`` 是从 trace bus 直接填充的
  retire 语义字段。
* 第 L25-L31 行：写回字段目前注释仍写「from DUT probe」，但 trace monitor 实现已经从
  RTL trace packet 填 ``wb_valid``、``wb_dest`` 和 ``wb_data``。``wb_suppress``、
  ``wb_tag`` 与 ``wb_source`` 仍用于 DIV/NB-load 异步覆盖路径。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L33-L48``）：

.. code-block:: systemverilog

     // Interrupt/NMI/debug state (from DUT probe, for Spike notification)
     bit [31:0] mip;          // Machine interrupt pending
     bit        nmi;          // NMI mode
     bit        nmi_int;      // NMI interrupt pending
     bit        debug_req;    // Debug request active
     bit [63:0] mcycle;       // Cycle counter

     // DUT-side trap CSR snapshot (sampled by trace_monitor when exception/interrupt)
     bit [31:0] dut_mtvec;
     bit [31:0] dut_mepc;
     bit [31:0] dut_mcause;
     bit [31:0] dut_mtval;

     // Timing
     time       commit_time;
     int        cycle_count;

**逐段解释**：

* 第 L33-L38 行：``mip``、``nmi``、``nmi_int``、``debug_req`` 和 ``mcycle`` 来自
  probe，用于 scoreboard 在调用 ``step`` 前通知 Spike。
* 第 L40-L44 行：trap CSR 快照在异常或中断 item 上采样，供 scoreboard 对比
  ``mcause`` 和 ``mepc``。
* 第 L46-L48 行：``commit_time`` 记录仿真时间，``cycle_count`` 记录 monitor 周期计数。

**接口关系**：

* **被调用**：``eh2_trace_monitor`` 和 ``eh2_dut_probe_monitor`` 都创建该 item。
* **调用**：item 内部 helper 方法被 scoreboard 用来分类指令和提取寄存器字段。
* **共享状态**：item 本身是 analysis port 上传输的事务对象。

§8  ``eh2_trace_seq_item`` helper — 指令字段解析
-------------------------------------------------

**职责**：helper 方法把 ``insn`` 按 RISC-V 编码切出 opcode、rd、rs1、rs2，并给
scoreboard 提供 branch、load、store、AMO、DIV、compressed 和 jump 分类。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L80-L95``）：

.. code-block:: systemverilog

     // Convert to string
     function string convert2string();
       return $sformatf("t%0d.%0d PC=%08x INSN=%08x %s",
         thread_id, slot, pc, insn,
         exception ? $sformatf("EXC=%0d", ecause) : "OK");
     endfunction

     // Get instruction opcode
     function bit [6:0] get_opcode();
       return insn[6:0];
     endfunction

     // Get destination register
     function bit [4:0] get_rd();
       return insn[11:7];
     endfunction

**逐段解释**：

* 第 L80-L85 行：``convert2string`` 输出 thread、slot、PC、INSN 和异常状态，用于 monitor
  日志。
* 第 L87-L95 行：``get_opcode`` 和 ``get_rd`` 直接切 ``insn`` 的标准字段，后续分类函数都基于
  这两个基础方法。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L97-L135``）：

.. code-block:: systemverilog

     // Get destination register for compressed instructions.
     function bit [4:0] get_compressed_rd();
       bit [2:0] funct3;
       bit [1:0] quadrant;

       funct3   = insn[15:13];
       quadrant = insn[1:0];

       case (quadrant)
         2'b00: begin
           // C.ADDI4SPN, C.LW use rd'.
           if (funct3 == 3'b000 || funct3 == 3'b010) return {2'b01, insn[4:2]};
         end
         2'b01: begin
           case (funct3)
             3'b000, 3'b010, 3'b011: return insn[11:7];       // C.ADDI/LI/LUI
             3'b001:                 return 5'd1;             // C.JAL (RV32)
             3'b100: begin
               if (insn[11:10] == 2'b11) return {2'b01, insn[9:7]};
               return {2'b01, insn[9:7]};                      // shifts/ANDI

**逐段解释**：

* 第 L97-L103 行：compressed rd 解码先取 ``funct3`` 和 ``quadrant``，即 ``insn[15:13]``
  与 ``insn[1:0]``。
* 第 L105-L109 行：quadrant ``00`` 下，``C.ADDI4SPN`` 与 ``C.LW`` 使用压缩寄存器
  ``rd'``，代码通过 ``{2'b01, insn[4:2]}`` 还原 x8-x15 范围。
* 第 L110-L118 行：quadrant ``01`` 下，部分指令直接使用 ``insn[11:7]``，
  ``C.JAL`` 固定写 x1；``funct3 == 3'b100`` 的分支返回压缩寄存器字段。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L121-L135``）：

.. code-block:: systemverilog

         2'b10: begin
           case (funct3)
             3'b000, 3'b010: return insn[11:7];                // C.SLLI/LWSP
             3'b100: begin
               if (insn[12] && insn[6:2] == 5'b0) return 5'd1; // C.JALR
               if (insn[6:2] != 5'b0) return insn[11:7];       // C.MV/C.ADD
             end
             default: return 5'd0;
           endcase
         end
         default: return 5'd0;
       endcase

       return 5'd0;
     endfunction

**逐段解释**：

* 第 L121-L129 行：quadrant ``10`` 下，``C.SLLI`` 与 ``C.LWSP`` 使用 ``insn[11:7]``；
  ``C.JALR`` 固定返回 x1；``C.MV/C.ADD`` 在 ``insn[6:2]`` 非零时返回 ``insn[11:7]``。
* 第 L130-L135 行：无法识别的压缩写回目的寄存器返回 x0，后续 ``writes_rd`` 会据此判断不写 GPR。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L147-L174``）：

.. code-block:: systemverilog

     // Check if instruction is a branch
     function bit is_branch();
       return (get_opcode() == 7'b1100011);
     endfunction

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

**逐段解释**：

* 第 L147-L165 行：branch、load、store 和 AMO 分类都只比较 ``opcode``。
* 第 L167-L174 行：DIV/REM 分类先排除 compressed，然后要求 ``opcode`` 为
  ``7'b0110011``、``funct7`` 为 ``7'b0000001``，并把 ``funct3`` 限定在
  ``100`` 到 ``111``，从而排除同 opcode/funct7 下走常规 pipeline 的 MUL。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L176-L224``）：

.. code-block:: systemverilog

     // Check if instruction is compressed
     function bit is_compressed();
       return (insn[1:0] != 2'b11);
     endfunction

     // Check if compressed instruction performs a load/store.
     // RV32C memory opcodes: C.LW/C.SW in quadrant 0, C.LWSP/C.SWSP in quadrant 2.
     function bit is_compressed_load_store();
       bit [2:0] funct3;
       bit [1:0] quadrant;

       if (!is_compressed()) return 1'b0;

       funct3   = insn[15:13];
       quadrant = insn[1:0];

       return ((quadrant == 2'b00 && (funct3 == 3'b010 || funct3 == 3'b110)) ||
               (quadrant == 2'b10 && (funct3 == 3'b010 || funct3 == 3'b110)));
     endfunction

     // Check if instruction is a jump
     function bit is_jump();

**逐段解释**：

* 第 L176-L179 行：compressed 判定只看 ``insn[1:0] != 2'b11``。
* 第 L181-L194 行：压缩 load/store 判定只覆盖 RV32C 的 ``C.LW/C.SW`` 和
  ``C.LWSP/C.SWSP``，由 quadrant 与 ``funct3`` 共同决定。
* 第 L196-L224 行：``is_jump``、``get_write_rd`` 和 ``writes_rd`` 使用前述 helper
  判定跳转和 GPR 写回。``writes_rd`` 会排除 x0，并把 CSR 指令的 ``funct3 != 0``
  作为写 rd 条件。

**接口关系**：

* **被调用**：scoreboard 的 ``is_memory_instruction``、``needs_async_wb``、
  ``has_matching_async_wb`` 和 ``compare_instruction`` 调用这些 helper。
* **调用**：helper 间互相调用，例如 ``writes_rd`` 调用 ``is_compressed``、
  ``get_compressed_rd`` 和 ``get_opcode``。
* **共享状态**：只读取 item 内部 ``insn`` 字段，不修改外部状态。

§9  ``eh2_trace_monitor`` — 连接 virtual interface
---------------------------------------------------

**职责**：trace monitor 从 config_db 取得 ``eh2_trace_intf``，可选取得
``eh2_dut_probe_if``，并创建 analysis port 输出 ``eh2_trace_seq_item``。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L14-L48``）：

.. code-block:: systemverilog

   class eh2_trace_monitor extends uvm_monitor;

     `uvm_component_utils(eh2_trace_monitor)

     // Virtual interfaces
     virtual eh2_trace_intf #(.NUM_THREADS(1)) vif;
     virtual eh2_dut_probe_if probe_vif;

     // Analysis port
     uvm_analysis_port #(eh2_trace_seq_item) ap;

     // Statistics
     int commit_count;
     int exception_count;
     int cycle_count;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);

**逐段解释**：

* 第 L14-L23 行：monitor 是 UVM component，核心输入是 trace virtual interface 和可选
  probe virtual interface，输出是 ``uvm_analysis_port``。
* 第 L25-L28 行：monitor 统计 commit、exception 与 cycle 数，report phase 会输出这些统计。
* 第 L30-L37 行：构造函数只调用父类，``build_phase`` 中创建 analysis port。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L39-L54``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (!uvm_config_db#(virtual eh2_trace_intf)::get(this, "", "vif", vif)) begin
         `uvm_fatal("trace_monitor", "Could not get trace virtual interface")
       end
       // DUT probe interface is optional - cosim notifications won't work without it
       if (!uvm_config_db#(virtual eh2_dut_probe_if)::get(this, "", "probe_vif", probe_vif)) begin
         `uvm_warning("trace_monitor", "Could not get DUT probe interface - interrupt/debug state will be zero")
       end
     endfunction

     task run_phase(uvm_phase phase);
       fork
         monitor_trace();
       join
     endtask

**逐段解释**：

* 第 L39-L43 行：trace ``vif`` 是必需依赖，缺失时直接 ``uvm_fatal``。
* 第 L44-L47 行：probe ``vif`` 是可选依赖；缺失时 monitor 发 warning，后续中断/调试状态填 0。
* 第 L50-L54 行：run phase 只 fork ``monitor_trace``，因此 trace 采样是该 monitor 的唯一运行线程。

**接口关系**：

* **被调用**：UVM env 创建 ``trace_monitor``，testbench/config_db 提供 interface。
* **调用**：``run_phase`` 调用 ``monitor_trace``，``monitor_trace`` 调用
  ``populate_cosim_state``。
* **共享状态**：读 ``vif`` 和 ``probe_vif``，写 ``ap``、``commit_count``、
  ``exception_count`` 和 ``cycle_count``。

§10  ``populate_cosim_state()`` — 采样 Spike 通知状态
-----------------------------------------------------

**职责**：该函数把 probe interface 中的 debug、NMI、``mip`` 和 ``mcycle`` 状态复制到
trace item；当 probe interface 不存在时，填 0。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L56-L71``）：

.. code-block:: systemverilog

     // Populate trace item with interrupt/debug/NMI state from DUT probe
     function void populate_cosim_state(eh2_trace_seq_item txn);
       if (probe_vif != null) begin
         txn.debug_req = probe_vif.debug_req;
         txn.nmi       = probe_vif.nmi;
         txn.nmi_int   = probe_vif.nmi_int;
         txn.mip       = probe_vif.mip;
         txn.mcycle    = probe_vif.mcycle;
       end else begin
         txn.debug_req = 0;
         txn.nmi       = 0;
         txn.nmi_int   = 0;
         txn.mip       = 0;
         txn.mcycle    = 0;
       end
     endfunction

**逐段解释**：

* 第 L56-L63 行：probe 存在时，函数把 ``debug_req``、``nmi``、``nmi_int``、
  ``mip`` 和 ``mcycle`` 复制进 item。scoreboard 后续按固定顺序通知 Spike。
* 第 L64-L70 行：probe 缺失时，所有通知状态归零。这个分支与 connect phase 的 warning 对应。

**接口关系**：

* **被调用**：``monitor_trace`` 在 i0 和 i1 item 创建后分别调用。
* **调用**：不调用外部函数。
* **共享状态**：读取 ``probe_vif``，写入传入的 ``eh2_trace_seq_item``。

§11  ``monitor_trace()`` — i0 槽位采样
--------------------------------------

**职责**：``monitor_trace`` 在 ``rst_n`` 为真时按 ``posedge`` 采样 trace。i0 槽位有效时，
monitor 创建 item，填基础 trace、写回、probe 状态和 trap CSR 快照，再通过 analysis port
发送。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L73-L110``）：

.. code-block:: systemverilog

     // Monitor trace interface
     task monitor_trace();
       eh2_trace_seq_item txn;

       forever begin
         @(posedge vif.clk iff vif.rst_n);

         cycle_count++;

         // Monitor thread 0, instruction 0 (i0)
         if (vif.t0_i0_valid) begin
           txn = eh2_trace_seq_item::type_id::create("trace_txn");
           txn.thread_id   = 0;
           txn.slot        = 0;
           txn.pc          = vif.t0_i0_pc;
           txn.insn        = vif.t0_i0_insn;
           txn.exception   = vif.t0_i0_exception;
           txn.ecause      = vif.t0_i0_ecause;
           txn.interrupt   = vif.interrupt[0][0];
           txn.tval        = vif.tval[0];
           txn.commit_time = $time;
           txn.cycle_count = cycle_count;

           // RVFI-equivalent writeback view from RTL trace packet (lane 0).
           txn.wb_valid    = vif.t0_i0_wb_valid;
           txn.wb_dest     = vif.t0_i0_wb_addr;
           txn.wb_data     = vif.t0_i0_wb_data;

**逐段解释**：

* 第 L73-L80 行：monitor 等待 ``posedge vif.clk iff vif.rst_n``，所以 reset 期间不采样；
  每次采样递增 ``cycle_count``。
* 第 L82-L94 行：i0 有效时创建 ``trace_txn``，固定 ``thread_id=0`` 和 ``slot=0``，
  并填入 PC、指令、异常、中断、``tval``、时间和周期。
* 第 L96-L99 行：i0 的写回字段来自 ``vif.t0_i0_wb_*``，也就是 RTL trace packet lane 0。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L100-L127``）：

.. code-block:: systemverilog

           txn.wb_suppress = 0;
           txn.wb_source   = EH2_WB_SRC_REGULAR;

           // Sample interrupt/debug/NMI/mcycle state for Spike notification
           populate_cosim_state(txn);

           // Capture current wb_seq for async-wb correlation (issue 66)
           if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;

           commit_count++;
           if (txn.exception) exception_count++;

           // Snapshot trap CSRs when exception or interrupt
           if (txn.exception || txn.interrupt) begin
             if (probe_vif != null) begin
               txn.dut_mtvec  = probe_vif.mtvec;
               txn.dut_mepc   = probe_vif.mepc;
               txn.dut_mcause = probe_vif.mcause;
               txn.dut_mtval  = probe_vif.mtval;  // from RTL TLU mtval register (issue 64)
             end else begin
               txn.dut_mtval  = txn.tval;  // fallback from RTL trace packet
             end
           end

**逐段解释**：

* 第 L100-L104 行：常规 trace item 默认不 suppress，``wb_source`` 标记为
  ``EH2_WB_SRC_REGULAR``，然后调用 ``populate_cosim_state``。
* 第 L106-L110 行：若 probe 存在，item 捕获当前 ``wb_seq``；随后更新 commit 与 exception 统计。
* 第 L112-L122 行：仅当异常或中断时采样 trap CSR。probe 存在时从 TLU mirror 取
  ``mtvec/mepc/mcause/mtval``；probe 缺失时只把 ``dut_mtval`` 回退为 trace packet 中的
  ``tval``。
* 第 L124-L127 行：monitor 打印 UVM_HIGH 日志后调用 ``ap.write(txn)``，把 i0 item 送入下游。

**接口关系**：

* **被调用**：``run_phase`` fork 后持续执行。
* **调用**：调用 ``populate_cosim_state`` 和 ``ap.write``。
* **共享状态**：读 ``vif`` 与 ``probe_vif``，写统计计数和 analysis port。

§12  ``monitor_trace()`` — i1 槽位采样
--------------------------------------

**职责**：i1 分支与 i0 分支结构相同，但 ``slot`` 为 1，并读取 ``t0_i1_*`` 便捷信号。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L129-L157``）：

.. code-block:: systemverilog

         // Monitor thread 0, instruction 1 (i1)
         if (vif.t0_i1_valid) begin
           txn = eh2_trace_seq_item::type_id::create("trace_txn");
           txn.thread_id   = 0;
           txn.slot        = 1;
           txn.pc          = vif.t0_i1_pc;
           txn.insn        = vif.t0_i1_insn;
           txn.exception   = vif.t0_i1_exception;
           txn.ecause      = vif.t0_i1_ecause;
           txn.interrupt   = vif.interrupt[0][1];
           txn.tval        = vif.tval[0];
           txn.commit_time = $time;
           txn.cycle_count = cycle_count;

           // RVFI-equivalent writeback view from RTL trace packet (lane 1).
           txn.wb_valid    = vif.t0_i1_wb_valid;
           txn.wb_dest     = vif.t0_i1_wb_addr;
           txn.wb_data     = vif.t0_i1_wb_data;
           txn.wb_suppress = 0;
           txn.wb_source   = EH2_WB_SRC_REGULAR;

           // Sample interrupt/debug/NMI/mcycle state for Spike notification
           populate_cosim_state(txn);

           // Capture current wb_seq for async-wb correlation (issue 66)
           if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;

           commit_count++;

**逐段解释**：

* 第 L129-L141 行：i1 分支固定 ``slot=1``，从 ``t0_i1_pc``、``t0_i1_insn``、
  ``t0_i1_exception`` 和 ``interrupt[0][1]`` 填 item。
* 第 L143-L149 行：i1 写回字段来自 trace packet lane 1，``wb_source`` 同样是
  ``EH2_WB_SRC_REGULAR``。
* 第 L150-L157 行：i1 也调用 ``populate_cosim_state`` 并采样 ``wb_seq``，随后更新统计。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L159-L188``）：

.. code-block:: systemverilog

           // Snapshot trap CSRs when exception or interrupt
           if (txn.exception || txn.interrupt) begin
             if (probe_vif != null) begin
               txn.dut_mtvec  = probe_vif.mtvec;
               txn.dut_mepc   = probe_vif.mepc;
               txn.dut_mcause = probe_vif.mcause;
               txn.dut_mtval  = probe_vif.mtval;  // from RTL TLU mtval register (issue 64)
             end else begin
               txn.dut_mtval  = txn.tval;  // fallback from RTL trace packet
             end
           end

           `uvm_info("trace_monitor", $sformatf("Commit: %s wb=%0b rd=x%0d wdata=%08x",
             txn.convert2string(), txn.wb_valid, txn.wb_dest, txn.wb_data), UVM_HIGH)
           ap.write(txn);
         end
       end
     endtask

     // Report statistics
     function void report_phase(uvm_phase phase);
       super.report_phase(phase);
       `uvm_info("trace_monitor", $sformatf("=== Trace Monitor Statistics ==="), UVM_LOW)

**逐段解释**：

* 第 L159-L169 行：i1 trap CSR 采样逻辑与 i0 相同。
* 第 L171-L176 行：i1 item 写到同一个 analysis port；下游通过 ``slot`` 区分 i0/i1。
* 第 L178-L188 行：report phase 输出 commit、exception、cycle，并在周期数大于 0 时计算 IPC。

**接口关系**：

* **被调用**：``run_phase`` 通过同一个 ``monitor_trace`` 任务覆盖 i0/i1。
* **调用**：调用 ``populate_cosim_state``、``convert2string`` 和 ``ap.write``。
* **共享状态**：与 i0 分支共享 ``cycle_count``、``commit_count`` 和 ``exception_count``。

§13  ``eh2_dut_probe_if`` — probe 保留的状态边界
-------------------------------------------------

**职责**：``eh2_dut_probe_if`` 当前不再暴露常规 i0/i1 pipeline 写回主路径；它保留 DIV、
NB-load、interrupt/NMI/debug、CSR mirror、trap 和 ``wb_seq`` 信号。

**关键代码** （``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L1-L12``）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 DUT Probe Interface — internal DUT signal probing for verification
   //
   // Phase 1 (ADR-0004) note: regular pipeline writebacks are now carried by the
   // RTL trace packet (rd_valid/rd_addr/rd_wdata fields), so this interface no
   // longer needs to expose i0/i1 wb_valid/wb_dest/wb_data. What remains:
   //   - DIV unit async writebacks + cancel-overwrite annotation
   //   - NB-load async writeback completion
   //   - Interrupt/NMI/debug state for cosim notification
   //   - CSR mirror state and exception flags (used by directed tests + fcov)
   //
   // Connect to DUT internal signals via hierarchical references in tb_top.

**逐段解释**：

* 第 L1-L6 行：头注释直接说明 Phase 1 后常规 pipeline 写回由 RTL trace packet 承载，
  probe 不再需要 i0/i1 常规 wb 字段。
* 第 L7-L10 行：保留功能分为四类：DIV 异步写回/覆盖取消、NB-load 异步完成、中断/NMI/debug
  通知状态、CSR mirror 与异常标志。
* 第 L12 行：probe 信号通过 TB 顶层 hierarchical reference 连接 DUT 内部路径。

**关键代码** （``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L19-L44``）：

.. code-block:: systemverilog

     // Division unit signals
     logic             div_cancel;             // Division canceled (any kind)
     logic             div_cancel_overwrite;   // Cancel due to younger same-rd write (paired with retired div trace)
     logic [4:0]       div_rd;                 // Division destination register
     logic [31:0]      div_result;             // Division raw result (pre-qualify)
     logic             div_wren;               // Division writeback valid (exu_div_wren)
     logic [31:0]      div_wdata;              // Division writeback data (exu_div_result)

     // Non-block load signals
     logic             nb_load_wen;
     logic [4:0]       nb_load_waddr;
     logic [31:0]      nb_load_data;

     // Interrupt/NMI/debug state (sampled each cycle for cosim notification)
     logic [31:0]      mip;           // Machine interrupt pending
     logic             nmi;           // NMI mode
     logic             nmi_int;       // NMI interrupt pending
     logic             debug_req;     // Debug request active
     logic [63:0]      mcycle;        // Cycle counter

     // CSR mirror state (for directed tests and coverage)
     logic [31:0]      mstatus;
     logic [31:0]      mtvec;
     logic [31:0]      mepc;
     logic [31:0]      mcause;
     logic [31:0]      mtval;

**逐段解释**：

* 第 L19-L25 行：DIV 相关信号区分取消、覆盖取消、目的寄存器、原始结果、写回 valid 和写回数据。
* 第 L27-L30 行：NB-load 只需要完成 valid、目的寄存器和数据。
* 第 L32-L37 行：中断、NMI、debug 和 ``mcycle`` 是 trace item 中 Spike 通知字段的来源。
* 第 L39-L44 行：CSR mirror 供异常/中断路径比较，也被注释标注为 directed tests 与 coverage 使用。

**关键代码** （``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L46-L74``）：

.. code-block:: systemverilog

     // Exception/trap signals at E4 stage (for directed tests and coverage)
     logic             mret_e4;
     logic             illegal_e4;
     logic             ecall_e4;
     logic             ebreak_e4;
     logic             ebreak_to_debug_e4;
     logic             inst_acc_e4;

     // Exception/trap signals at writeback stage
     logic             mret_wb;
     logic             illegal_wb;
     logic             ecall_wb;
     logic             ebreak_wb;

     // Debug state
     logic             debug_mode;
     logic             dbg_halted;

     // Interrupt tracking
     logic             interrupt_valid;
     logic             take_ext_int;
     logic             take_timer_int;
     logic             take_soft_int;
     logic             take_nmi;

     // Global writeback sequence counter (issue 66: strict wb_seq ordering)
     // Incremented by probe_monitor for each non-suppressed wb event.
     // Read by trace_monitor to tag trace items for async_wb matching.
     logic [15:0]      wb_seq;

**逐段解释**：

* 第 L46-L58 行：probe 同时保存 E4 阶段与 writeback 阶段的异常/trap 状态。
* 第 L60-L69 行：debug 与 interrupt tracking 信号为 directed tests、coverage 或 cosim 通知提供
  DUT 内部状态。
* 第 L71-L74 行：``wb_seq`` 是严格异步写回关联的共享计数器。注释说明它由 probe monitor
  递增，并由 trace monitor 读出写入 ``trace_seq_item.wb_tag``。

**接口关系**：

* **被调用**：TB 顶层实例化并把内部 DUT 信号连接到该 interface。
* **调用**：interface 自身不调用函数；clocking block 提供 monitor 采样集合。
* **共享状态**：``wb_seq`` 是 trace monitor 和 probe monitor 之间的共享关联状态。

§14  ``eh2_dut_probe_monitor`` — 异步写回事件监控
--------------------------------------------------

**职责**：probe monitor 只产生异步写回提示，覆盖 DIV 和 NB-load；常规 pipeline 写回已经由
trace packet 提供。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L1-L26``）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 DUT Probe Monitor — async writeback events only.
   //
   // Phase 1 (ADR-0004) note: regular pipeline writebacks now ride along the
   // trace channel inside eh2_trace_seq_item.wb_*. This monitor exists only to
   // surface async events that the trace packet cannot describe in time:
   //   - DIV writeback / DIV cancel (long latency, separate writeback port)
   //   - Non-blocking load completion (writeback arrives after retire)
   //
   // The cosim scoreboard treats these as overrides/suppressions for the
   // matching trace item.

   class eh2_dut_probe_monitor extends uvm_monitor;

     `uvm_component_utils(eh2_dut_probe_monitor)

     virtual eh2_dut_probe_if vif;
     uvm_analysis_port #(eh2_trace_seq_item) ap;

     int wb_count;
     int wb_seq_counter;  // global writeback sequence (issue 66)

     function new(string name, uvm_component parent);
       super.new(name, parent);
       wb_seq_counter = 1;  // start from 1 so wb_tag >= 1 always (issue 66)
     endfunction

**逐段解释**：

* 第 L1-L11 行：头注释把 probe monitor 的范围限定为异步写回，明确常规写回已经在
  ``eh2_trace_seq_item.wb_*`` 中。
* 第 L13-L21 行：monitor 保存 probe virtual interface、analysis port、异步写回统计和
  全局 ``wb_seq_counter``。
* 第 L23-L26 行：``wb_seq_counter`` 从 1 开始，避免第一个异步写回产生 ``wb_tag == 0``。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L33-L47``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (!uvm_config_db#(virtual eh2_dut_probe_if)::get(this, "", "vif", vif)) begin
         `uvm_warning("dut_probe", "Could not get DUT probe virtual interface - async writeback monitoring disabled")
       end
     endfunction

     task run_phase(uvm_phase phase);
       if (vif != null) begin
         fork
           monitor_division();
           monitor_nb_load();
         join
       end
     endtask

**逐段解释**：

* 第 L33-L38 行：probe ``vif`` 缺失只发 warning，不 fatal；结果是异步写回监控禁用。
* 第 L40-L47 行：只有 ``vif`` 非空时才并行启动 ``monitor_division`` 和 ``monitor_nb_load``。

**接口关系**：

* **被调用**：UVM env 创建并连接该 monitor。
* **调用**：``run_phase`` 并行调用 ``monitor_division`` 与 ``monitor_nb_load``。
* **共享状态**：读 ``vif``，写 ``ap``、``wb_count``、``wb_seq_counter`` 和
  ``vif.wb_seq``。

§15  ``monitor_division()`` — DIV 写回和覆盖取消
------------------------------------------------

**职责**：``monitor_division`` 监听 DIV 写回、DIV overwrite-cancel 和 speculative cancel。
前两类会生成 ``eh2_trace_seq_item`` 异步提示；speculative cancel 只打印日志，不写 analysis port。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L49-L70``）：

.. code-block:: systemverilog

     // Monitor DIV writebacks and DIV-cancel events.
     task monitor_division();
       eh2_trace_seq_item txn;

       forever begin
         @(posedge vif.clk iff vif.rst_n);

         if (vif.div_wren && vif.div_rd != 5'b0) begin
           txn = eh2_trace_seq_item::type_id::create("div_wb_txn");
           txn.slot      = 0;  // Divides are i0-only
           txn.wb_valid  = 1;
           txn.wb_dest   = vif.div_rd;
           txn.wb_data   = vif.div_wdata;
           txn.wb_source = EH2_WB_SRC_DIV;
           txn.wb_tag    = wb_seq_counter;
           vif.wb_seq    = wb_seq_counter;  // write to interface for trace_monitor (issue 66)
           ap.write(txn);
           `uvm_info("dut_probe", $sformatf("DIV WB: x%0d = %08x wb_tag=%0d",
             vif.div_rd, vif.div_wdata, wb_seq_counter), UVM_HIGH)
           wb_count++;
           wb_seq_counter++;

**逐段解释**：

* 第 L49-L55 行：任务在 reset 释放后的每个时钟沿采样。
* 第 L56-L64 行：DIV 写回 valid 且目的寄存器非 x0 时，monitor 创建 ``div_wb_txn``，
  固定 ``slot=0``，填 ``wb_valid``、``wb_dest``、``wb_data``、``wb_source`` 和
  ``wb_tag``。
* 第 L64-L70 行：当前 ``wb_seq_counter`` 写入 ``vif.wb_seq``，再通过 ``ap.write``
  发送提示，然后统计并递增计数器。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L71-L95``）：

.. code-block:: systemverilog

         end
         else if (vif.div_cancel && vif.div_cancel_overwrite && vif.div_rd != 5'b0) begin
           // Only forward "overwrite" cancels: these pair with a retired div
           // trace whose architectural writeback was killed by a younger same-rd
           // write. Speculative-flush cancels (no matching trace) are dropped.
           txn = eh2_trace_seq_item::type_id::create("div_cancel_txn");
           txn.slot        = 0;
           txn.wb_valid    = 1;
           txn.wb_dest     = vif.div_rd;
           txn.wb_data     = vif.div_result;
           txn.wb_suppress = 1;
           txn.wb_source   = EH2_WB_SRC_DIV;
           txn.wb_tag      = wb_seq_counter;
           vif.wb_seq      = wb_seq_counter;
           ap.write(txn);
           `uvm_info("dut_probe", $sformatf("DIV OVERWRITE-CANCEL: x%0d = %08x wb_tag=%0d",
             vif.div_rd, vif.div_result, wb_seq_counter), UVM_HIGH)
           wb_count++;
           wb_seq_counter++;
         end
         else if (vif.div_cancel && !vif.div_cancel_overwrite) begin
           `uvm_info("dut_probe", $sformatf(
             "DIV SPEC-CANCEL: x%0d (dropped, no paired trace)",
             vif.div_rd), UVM_HIGH)

**逐段解释**：

* 第 L71-L75 行：只有 ``div_cancel`` 与 ``div_cancel_overwrite`` 同时为真且 rd 非 x0 时，
  monitor 才把取消作为可匹配的 retired DIV 提示发送；注释明确 speculative-flush cancel 不发送。
* 第 L76-L84 行：overwrite-cancel item 设置 ``wb_suppress=1``，表示匹配到的 trace item
  应抑制架构写回。
* 第 L85-L89 行：overwrite-cancel 同样写 ``vif.wb_seq``、发送 analysis port 并递增计数。
* 第 L90-L94 行：非 overwrite 的 DIV cancel 仅打印 ``DIV SPEC-CANCEL`` 日志，不产生下游 item。

**接口关系**：

* **被调用**：``run_phase`` fork 后执行。
* **调用**：创建 ``eh2_trace_seq_item`` 并调用 ``ap.write``。
* **共享状态**：读取 ``vif.div_*``，写 ``vif.wb_seq``、``wb_count`` 和
  ``wb_seq_counter``。

§16  ``monitor_nb_load()`` — NB-load 完成提示
---------------------------------------------

**职责**：``monitor_nb_load`` 监听 non-blocking load 完成信号，把目的寄存器和数据封装为
``EH2_WB_SRC_NB_LOAD`` 异步写回提示。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L98-L121``）：

.. code-block:: systemverilog

     // Monitor non-blocking load completions.
     task monitor_nb_load();
       eh2_trace_seq_item txn;

       forever begin
         @(posedge vif.clk iff vif.rst_n);

         if (vif.nb_load_wen && vif.nb_load_waddr != 5'b0) begin
           txn = eh2_trace_seq_item::type_id::create("nb_load_txn");
           txn.slot      = 0;
           txn.wb_valid  = 1;
           txn.wb_dest   = vif.nb_load_waddr;
           txn.wb_data   = vif.nb_load_data;
           txn.wb_source = EH2_WB_SRC_NB_LOAD;
           txn.wb_tag    = wb_seq_counter;
           vif.wb_seq    = wb_seq_counter;  // issue 66
           ap.write(txn);
           `uvm_info("dut_probe", $sformatf("NB LOAD: x%0d = %08x wb_tag=%0d",
             vif.nb_load_waddr, vif.nb_load_data, wb_seq_counter), UVM_HIGH)
           wb_count++;
           wb_seq_counter++;
         end
       end
     endtask

**逐段解释**：

* 第 L98-L104 行：任务在 reset 释放后的时钟沿循环采样。
* 第 L105-L113 行：只有 ``nb_load_wen`` 为真且目标寄存器非 x0 时，monitor 创建
  ``nb_load_txn``，填入 ``wb_dest``、``wb_data``、``EH2_WB_SRC_NB_LOAD`` 和
  ``wb_tag``。
* 第 L113-L119 行：当前 tag 写到 ``vif.wb_seq``，再把提示写入 analysis port，
  然后统计并递增 tag。

**接口关系**：

* **被调用**：``run_phase`` 与 DIV monitor 并行启动该任务。
* **调用**：创建 ``eh2_trace_seq_item`` 并调用 ``ap.write``。
* **共享状态**：读取 ``vif.nb_load_*``，写 ``vif.wb_seq``、``wb_count`` 和
  ``wb_seq_counter``。

§17  TB probe 连接 — 从 DUT 内部路径到 probe interface
-------------------------------------------------------

**职责**：TB 顶层实例化 ``eh2_dut_probe_if`` 并用 hierarchical reference 把 DIV、
NB-load、CSR、debug 和 interrupt 状态接入 probe。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L815-L835``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // DUT Probe Interface Instance (for register writeback monitoring)
     //--------------------------------------------------------------------------
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

**逐段解释**：

* 第 L815-L824 行：TB 顶层注释与 probe interface 注释一致，说明常规 wb 已转移到 trace packet。
* 第 L826-L831 行：DIV 信号来自 ``DEC``、``EXU`` 或 ``dut.veer`` 内部路径，覆盖取消、rd、
  原始结果、写回 valid 和写回数据。
* 第 L833-L835 行：NB-load 信号从 DEC 内部 non-block load 路径接出。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L837-L865``）：

.. code-block:: systemverilog

     // Interrupt/NMI/debug state for cosim notification
     // Construct MIP from external interrupt sources:
     //   bit 11 = MEIP (external), bit 7 = MTIP (timer), bit 3 = MSIP (software)
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
     // mepc: 31 bits stored, bit 0 always 0
     assign dut_probe_intf.mepc    = {dut.veer.dec.tlu.tlumt[0].tlu.mepc[31:1], 1'b0};
     // mcause: full 32 bits
     assign dut_probe_intf.mcause  = dut.veer.dec.tlu.tlumt[0].tlu.mcause[31:0];
     // mtval: full 32 bits (issue 64 — from RTL TLU mtval register)

**逐段解释**：

* 第 L837-L847 行：``mip`` 由外部、timer 和 software interrupt 组合构造；
  ``nmi``、``nmi_int``、``debug_req`` 和 ``mcycle`` 也在这里接入 probe。
* 第 L849-L855 行：``mstatus`` 从 TLU 内部 bit 组合，其中 MPP 硬编码为 ``2'b11``。
* 第 L856-L865 行：``mtvec``、``mepc``、``mcause`` 和 ``mtval`` 从 TLU 内部寄存器拼接或直连。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L867-L890``）：

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

**逐段解释**：

* 第 L867-L879 行：E4 和 WB 阶段 trap 信号均从 TLU 内部路径接入 probe。
* 第 L881-L883 行：debug mode 与 halted 状态从 DEC/TLU debug 状态接入。
* 第 L885-L890 行：interrupt valid 和具体 interrupt take 信号从 TLU 内部路径接入。

**接口关系**：

* **被调用**：``eh2_dut_probe_monitor`` 与 ``eh2_trace_monitor`` 通过 virtual interface 读这些信号。
* **调用**：TB 顶层不调用任务；只做 hierarchical assignment。
* **共享状态**：probe interface 将内部 DUT 状态暴露给 UVM monitor。

§18  UVM env 连接 — trace/probe 到 scoreboard
---------------------------------------------

**职责**：``core_eh2_env`` 创建 trace monitor 和 probe monitor，并在 cosim enabled 时把它们的
analysis port 连接到 cosim scoreboard 的 FIFO。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env.sv:L99-L123``）：

.. code-block:: systemverilog

       // Trace monitor
       trace_monitor = eh2_trace_monitor::type_id::create("trace_monitor", this);

       // DUT probe monitor
       dut_probe_monitor = eh2_dut_probe_monitor::type_id::create("dut_probe_monitor", this);

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

**逐段解释**：

* 第 L99-L103 行：env 无条件创建 trace monitor 和 probe monitor。
* 第 L105-L123 行：只有 ``cfg.enable_cosim`` 为真时才创建 cosim agent，并在创建前构造
  ``eh2_cosim_cfg``，从 plusargs 读取 ICCM/DCCM region 覆盖值后注入 scoreboard。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L164``）：

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

**逐段解释**：

* 第 L151-L154 行：trace monitor 输出连接到 ``scoreboard.trace_fifo``，这是退休指令主输入。
* 第 L156-L159 行：probe monitor 输出连接到 ``scoreboard.dut_probe_fifo``，用于异步写回提示。
* 第 L161-L164 行：LSU AXI4 monitor 连接到 ``dmem_port``，为 memory access 通知路径提供输入。

**接口关系**：

* **被调用**：UVM build/connect phase 调用这些逻辑。
* **调用**：``analysis_port.connect`` 把 monitor 与 scoreboard FIFO 接起来。
* **共享状态**：env 不保存事务状态，只负责连接 ``trace_fifo``、``dut_probe_fifo`` 和 dmem path。

§19  ``run_cosim_trace()`` — trace item 入队
-------------------------------------------------------

**职责**：scoreboard 从 ``trace_fifo`` 读取 trace item，按 ``thread_id`` 放入
``pending_trace_q``，再尝试处理对应线程的 pending trace。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L37-L40``）：

.. code-block:: systemverilog

     // Analysis FIFOs from monitors
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) trace_fifo;
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) dut_probe_fifo;
     uvm_tlm_analysis_fifo #(axi4_seq_item)      lsu_axi_fifo;

**逐段解释**：

* 第 L37-L40 行：scoreboard 有三个输入 FIFO：trace item、probe item 和 LSU AXI item。
  这与 env 中的三个连接一一对应。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L205-L224``）：

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

**逐段解释**：

* 第 L205-L211 行：任务阻塞式读取 ``trace_fifo``，每读到一个 trace item 增加
  ``trace_item_count``。
* 第 L213-L221 行：只有 cosim handle 非空且已经初始化时，item 才进入 ``pending_trace_q[tid]``。
  高水位统计记录 pending 队列最大深度。
* 第 L221 行：入队后立即调用 ``process_pending_trace(tid)``，尝试推进该线程可执行的 trace。

**接口关系**：

* **被调用**：scoreboard run phase 中启动该任务。
* **调用**：调用 ``process_pending_trace``。
* **共享状态**：读 ``trace_fifo``，写 ``trace_item_count``、``pending_trace_q`` 和
  ``pending_trace_high_watermark``。

§20  ``run_cosim_probe_async()`` — 异步写回提示入队
---------------------------------------------------

**职责**：scoreboard 从 probe FIFO 读取异步写回 item，丢弃常规写回，按 ``thread_id`` 放入
``async_wb_q``，再尝试处理 pending trace。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L226-L258``）：

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

         begin
           int tid = int'(probe_item.thread_id);
           async_wb_q[tid].push_back(hint);

**逐段解释**：

* 第 L226-L233 行：任务从 ``dut_probe_fifo`` 读取 item，并统计 probe item 数量。
* 第 L235-L236 行：``EH2_WB_SRC_REGULAR`` 被直接跳过，因为常规写回已经由 trace channel 携带。
* 第 L238-L242 行：probe item 被压缩为 ``async_wb_hint_t``，包含 rd、数据、suppress、来源和
  ``wb_tag``。
* 第 L244-L247 行：hint 按 ``thread_id`` 放入 ``async_wb_q[tid]``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L248-L257``）：

.. code-block:: systemverilog

           `uvm_info("cosim", $sformatf(
             "ASYNC_WB: T%0d src=%s rd=x%0d data=%08x suppress=%0b qsize=%0d",
             tid, wb_source_name(probe_item.wb_source), probe_item.wb_dest,
             probe_item.wb_data, probe_item.wb_suppress, async_wb_q[tid].size()), UVM_HIGH)

           if (cosim_handle != null && initialized) begin
             process_pending_trace(tid);
           end
         end
       end
     endtask

**逐段解释**：

* 第 L248-L251 行：日志记录 thread、来源、rd、数据、suppress 和队列深度。
* 第 L253-L255 行：cosim 初始化后，异步 hint 到达也会触发 ``process_pending_trace(tid)``，
  使等待 DIV/NB-load 的 trace item 可以继续推进。

**接口关系**：

* **被调用**：scoreboard run phase 中启动该任务。
* **调用**：调用 ``wb_source_name`` 和 ``process_pending_trace``。
* **共享状态**：读 ``dut_probe_fifo``，写 ``probe_item_count`` 和 ``async_wb_q``。

§21  ``has_matching_async_wb()`` — 等待严格 tag 匹配
----------------------------------------------------

**职责**：该函数判断当前 trace item 是否已经有匹配的异步写回提示。DIV 与 NB-load 都按
``wb_tag`` 匹配，不按 rd 回退。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L309-L348``）：

.. code-block:: systemverilog

         if (needs_async_wb(pending.item) && !has_matching_async_wb(tid, pending.item)) begin
           `uvm_info("cosim", $sformatf(
             "T%0d Waiting for async wb (DIV) before stepping PC=%08x insn=%08x rd=x%0d",
             tid, pending.item.pc, pending.item.insn, pending.item.get_write_rd()), UVM_HIGH)
           break;
         end

         pending_trace_q[tid].pop_front();
         if (is_memory_instruction(pending.item) &&
             has_matching_memory_access(pending.item)) begin
           pop_matching_memory_access(pending.item);
         end
         // Track store trace items stepped (for coalescing detection).
         if (is_store_or_amo_instruction(pending.item)) begin
           store_trace_stepped++;
         end
         compare_instruction(tid, pending.item);
       end
     endfunction

     function bit has_matching_async_wb(int tid, eh2_trace_seq_item item);
       if (!item.writes_rd()) return 1'b0;

       if (item.is_div()) begin

**逐段解释**：

* 第 L309-L314 行：当 ``needs_async_wb`` 为真但没有匹配 hint 时，``process_pending_trace``
  停在当前 pending item，不调用 ``compare_instruction``。
* 第 L316-L325 行：满足内存访问和异步写回条件后，item 从 pending 队列弹出，必要时弹出匹配内存访问，
  最后进入 ``compare_instruction``。
* 第 L329-L332 行：``has_matching_async_wb`` 首先排除不写 rd 的指令；DIV 才进入 DIV hint 搜索。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L332-L348``）：

.. code-block:: systemverilog

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

**逐段解释**：

* 第 L332-L339 行：DIV 分支只接受 ``source == EH2_WB_SRC_DIV`` 且 ``hint.wb_tag == item.wb_tag``。
* 第 L341-L346 行：load 分支只接受 ``EH2_WB_SRC_NB_LOAD``，并要求 ``hint.wb_tag > 0`` 且等于
  item tag。
* 第 L347-L348 行：未找到严格 tag 匹配时返回 0，保持 pending trace 等待。

**接口关系**：

* **被调用**：``process_pending_trace`` 在调用 ``compare_instruction`` 前调用它。
* **调用**：调用 item helper，例如 ``writes_rd``、``is_div`` 和 ``is_load_instruction``。
* **共享状态**：读取 ``async_wb_q[tid]``，不消费队列。

§22  ``try_consume_async_wb()`` — 消费严格 tag 匹配
---------------------------------------------------

**职责**：该函数在 ``compare_instruction`` 内尝试消费匹配的异步写回 hint。匹配成功时从队列删除；
同来源但 tag 不匹配时记录 mismatch。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L391-L422``）：

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
           end
           if (!found_wrong_tag) begin
             found_wrong_tag = 1;
             wrong_tag_val = async_wb_q[tid][i].wb_tag;
           end

**逐段解释**：

* 第 L391-L399 行：函数头注释明确「Strict wb_tag-only matching」；``expected_rd`` 只用于错误日志中的
  rd 打印，不作为匹配回退。
* 第 L401-L408 行：DIV 分支要求来源为 ``EH2_WB_SRC_DIV`` 且 tag 相等；匹配成功后复制 hint、
  删除队列元素并返回 1。
* 第 L410-L413 行：遇到来源正确但 tag 不匹配的第一个 hint 时，记录 ``wrong_tag_val``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L415-L442``）：

.. code-block:: systemverilog

         if (found_wrong_tag) begin
           mismatch_count[tid]++;
           `uvm_error("cosim", $sformatf(
             "T%0d DIV wb_tag mismatch: item.wb_tag=%0d hint.wb_tag=%0d rd=x%0d — strict matching, no fallback",
             tid, item.wb_tag, wrong_tag_val, expected_rd))
         end
         return 1'b0;
       end

       if (is_load_instruction(item)) begin
         found_wrong_tag = 0;
         foreach (async_wb_q[tid][i]) begin
           if (async_wb_q[tid][i].source != EH2_WB_SRC_NB_LOAD) continue;
           if (async_wb_q[tid][i].wb_tag > 0 && async_wb_q[tid][i].wb_tag == item.wb_tag) begin
             hint = async_wb_q[tid][i];
             async_wb_q[tid].delete(i);
             return 1'b1;
           end
           if (!found_wrong_tag) begin
             found_wrong_tag = 1;
             wrong_tag_val = async_wb_q[tid][i].wb_tag;
           end
         end
         if (found_wrong_tag) begin
           mismatch_count[tid]++;
           `uvm_error("cosim", $sformatf(
             "T%0d NB-LOAD wb_tag mismatch: item.wb_tag=%0d hint.wb_tag=%0d rd=x%0d — strict matching, no fallback",

**逐段解释**：

* 第 L415-L421 行：DIV 来源存在但 tag 不匹配时，scoreboard 增加 ``mismatch_count[tid]``
  并发 ``uvm_error``，然后返回 0。
* 第 L424-L431 行：NB-load 分支要求来源为 ``EH2_WB_SRC_NB_LOAD``、tag 大于 0 且等于 item tag；
  匹配后同样删除队列元素。
* 第 L432-L442 行：NB-load 来源存在但 tag 不匹配时也递增 mismatch 并报错。错误消息包含 item tag、
  hint tag 和 expected rd。

**接口关系**：

* **被调用**：``compare_instruction`` 在取 trace packet 写回之后调用。
* **调用**：调用 item helper，例如 ``writes_rd``、``get_write_rd``、``is_div`` 和
  ``is_load_instruction``。
* **共享状态**：读写 ``async_wb_q[tid]``，写 ``mismatch_count[tid]``。

§23  ``compare_instruction()`` — interrupt-only 分支
----------------------------------------------------

**职责**：interrupt-only item 的条件是 ``item.interrupt && !item.exception``。该分支只更新
Spike 的 debug/NMI/MIP/mcycle 状态并对比 trap CSR，不调用 ``riscv_cosim_step``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L564-L610``）：

.. code-block:: systemverilog

     // Compare one instruction against Spike.
     function void compare_instruction(int tid, eh2_trace_seq_item item);
       bit [4:0]  write_reg;
       bit [31:0] write_reg_data;
       bit        sync_trap;
       bit        suppress_reg_write;
       int        result;
       async_wb_hint_t async_hint;

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

**逐段解释**：

* 第 L564-L571 行：函数声明本次比较需要的写回寄存器、写回数据、trap 标志、suppress 标志、
  Spike 返回结果和异步 hint。
* 第 L573-L575 行：代码注释定义 interrupt-only item：``interrupt=1`` 且 ``exception=0``，
  该 PC 上没有执行指令。
* 第 L576-L582 行：interrupt-only 分支只调用 debug/NMI/MIP/mcycle 通知 API，并更新
  ``prev_mip[tid]``；这里没有 ``riscv_cosim_step``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L584-L609``）：

.. code-block:: systemverilog

         // Compare trap CSRs on interrupt path — upgraded to mismatch (issue 51)
         begin
           int unsigned spike_mcause, spike_mepc;
           spike_mcause = riscv_cosim_get_mcause(cosim_handle, tid);
           spike_mepc   = riscv_cosim_get_mepc(cosim_handle, tid);

           if (spike_mcause != item.dut_mcause) begin
             mismatch_count[tid]++;
             `uvm_error("cosim", $sformatf(
               "T%0d IRQ mcause MISMATCH: DUT=%08x Spike=%08x PC=%08x",
               tid, item.dut_mcause, spike_mcause, item.pc))
           end

           if (spike_mepc != item.dut_mepc) begin
             mismatch_count[tid]++;
             `uvm_error("cosim", $sformatf(
               "T%0d IRQ mepc MISMATCH: DUT=%08x Spike=%08x PC=%08x",
               tid, item.dut_mepc, spike_mepc, item.pc))
           end

**逐段解释**：

* 第 L584-L588 行：interrupt path 从 Spike 读取 ``mcause`` 和 ``mepc``。
* 第 L590-L602 行：``mcause`` 或 ``mepc`` 不一致时，scoreboard 递增 mismatch 并发
  ``uvm_error``。
* 第 L604-L609 行：打印 IRQ CSR compare 日志后返回，阻止函数继续进入常规 step 路径。

**接口关系**：

* **被调用**：``process_pending_trace`` 在 trace item 具备必要条件后调用。
* **调用**：调用 ``riscv_cosim_set_debug_req``、``riscv_cosim_set_nmi``、
  ``riscv_cosim_set_nmi_int``、``riscv_cosim_set_mip``、``riscv_cosim_set_mcycle``、
  ``riscv_cosim_get_mcause`` 和 ``riscv_cosim_get_mepc``。
* **共享状态**：读写 ``prev_mip[tid]``，写 ``mismatch_count[tid]``。

§24  ``compare_instruction()`` — trace 写回与 async 覆盖
--------------------------------------------------------

**职责**：常规 item 先从 trace packet 写回视图生成 Spike step 参数，再让异步 hint 覆盖或抑制写回。
DIV 在没有 hint 时默认抑制 regular write。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L612-L638``）：

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
         end
       end else if (item.is_div()) begin
         suppress_reg_write = 1;
         write_reg          = 0;
         write_reg_data     = 0;
       end

**逐段解释**：

* 第 L612-L621 行：scoreboard 首先从 trace item 自带写回字段取 ``write_reg`` 和
  ``write_reg_data``；如果 ``wb_valid`` 低或 rd 为 x0，则写回参数清零。
* 第 L623-L633 行：若消费到异步 hint，``suppress`` 为真时清零写回并设置
  ``suppress_reg_write``；否则用 hint 的 rd 和数据覆盖 trace 写回。
* 第 L634-L638 行：若 item 是 DIV 但没有可消费 hint，scoreboard 抑制写回。这与 DIV 长延迟/异步写回路径对应。

**接口关系**：

* **被调用**：``compare_instruction`` 常规路径内部执行。
* **调用**：调用 ``try_consume_async_wb`` 和 ``item.is_div``。
* **共享状态**：通过 ``try_consume_async_wb`` 读写 ``async_wb_q``。

§25  ``compare_instruction()`` — Spike 通知和 step 顺序
-------------------------------------------------------

**职责**：scoreboard 在调用 ``riscv_cosim_step`` 前按固定顺序通知 debug、NMI、MIP 和
``mcycle``，然后把写回、PC、trap 和 suppress 参数交给 Spike。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L640-L656``）：

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

**逐段解释**：

* 第 L640 行：同步 trap 定义为异常且非中断。
* 第 L642-L648 行：Spike 通知顺序是 debug request、NMI、NMI interrupt、MIP pre/post、mcycle；
  ``prev_mip[tid]`` 在调用后更新为当前 item 的 ``mip``。
* 第 L649-L651 行：当 exception 为真、interrupt 为假且 ``ecause == 5'd1`` 时，
  额外调用 ``riscv_cosim_set_iside_error``。
* 第 L653-L656 行：``riscv_cosim_step`` 参数依次包含 handle、写回寄存器、写回数据、PC、
  sync trap 标志、suppress 标志和 thread id。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L658-L703``）：

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
       end

       // Compare trap CSRs on exception path — upgraded to mismatch (issue 51)
       // mtval is now connected from RTL trace packet (issue 64); Spike-side
       // get_mtval() API not yet added — deferred to future cosim API extension

**逐段解释**：

* 第 L658-L669 行：Spike step 返回 0 时递增 ``mismatch_count[tid]``。是否 fatal 由
  ``fatal_on_mismatch`` 决定。
* 第 L670-L673 行：非 mismatch 时打印 MATCH 日志。
* 第 L675-L703 行：同步异常路径继续比较 Spike 与 DUT 的 ``mcause`` 和 ``mepc``，
  mismatch 同样递增 ``mismatch_count[tid]`` 并报错；函数末尾递增 ``step_count``。

**接口关系**：

* **被调用**：``process_pending_trace``。
* **调用**：调用多个 Spike DPI wrapper 和 ``get_cosim_error_str``。
* **共享状态**：读写 ``prev_mip[tid]``、``mismatch_count[tid]`` 和 ``step_count``。

§26  ``eh2_veer_wrapper_rvfi`` — sidecar 输入输出边界
------------------------------------------------------

**职责**：``eh2_veer_wrapper_rvfi`` 是 trace-to-RVFI converter layer。源文件注释说明它在
TB 顶层作为 sidecar 实例化，不替代现有 DUT wrapper。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L1-L10,L13-L16``）：

.. code-block:: systemverilog

   // ============================================================================
   // eh2_veer_wrapper_rvfi.sv — EH2 Trace-to-RVFI Converter Layer
   //
   // ADR-0015: Converts EH2-native trace signals to standard RVFI format.
   // This module is instantiated as a SIDECAR in tb_top (not as a DUT wrapper).
   // The existing eh2_veer_wrapper remains the DUT; this converter taps its
   // trace output ports (which are already live and driven) and produces the
   // RVFI-equivalent interface for lockstep comparison and formal verification.
   //
   // Dual-channel: i0 (first retire) and i1 (second retire) for dual-issue.
   //
   // RC4 status (2026-05-08): ALL internal trace signals are now driven by real
   // assign statements connected to live DUT trace ports. Previously this file
   // was a hollow shell with 0 driven internal signals and 0 instantiations.
   // ============================================================================

**逐段解释**：

* 第 L1-L8 行：模块目标是把 EH2-native trace 转为 RVFI 格式，并且作为 TB sidecar 接在现有
  DUT wrapper 外侧。
* 第 L10 行：sidecar 输出为 i0/i1 双 channel，对应 EH2 dual issue。
* 第 L13-L16 行：注释记录当前内部 trace 信号由真实 assign 驱动，说明它不是空壳模块。
  代码注释中含外部 RVFI reference URL；本文档引用该事实但不引入裸 URL。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L18-L60``）：

.. code-block:: systemverilog

   module eh2_veer_wrapper_rvfi (
       input  logic        clk,
       input  logic        rst_n,

       // Trace inputs (from DUT trace ports, live in tb_top)
       input  logic [63:0] trace_insn,
       input  logic [63:0] trace_address,
       input  logic [1:0]  trace_valid,
       input  logic [1:0]  trace_exception,
       input  logic [4:0]  trace_ecause,
       input  logic [1:0]  trace_interrupt,
       input  logic [31:0] trace_tval,
       input  logic [1:0]  trace_rd_valid,
       input  logic [9:0]  trace_rd_addr,
       input  logic [63:0] trace_rd_wdata,

       // LSU bus inputs (from AXI4 bus signals in tb_top)
       input  logic        lsu_bus_valid,
       input  logic [31:0] lsu_bus_addr,
       input  logic [31:0] lsu_bus_rdata,
       input  logic [31:0] lsu_bus_wdata,
       input  logic [3:0]  lsu_bus_wmask,
       input  logic        lsu_bus_write,

**逐段解释**：

* 第 L18-L32 行：模块输入包括 clock/reset 和完整 trace 字段，其中 ``trace_rd_valid``、
  ``trace_rd_addr``、``trace_rd_wdata`` 是写回视图来源。
* 第 L34-L40 行：LSU bus 输入来自 TB 中的 AXI4 bus 派生信号，用于生成 RVFI memory 字段。
* 第 L42-L60 行：模块输出标准化 RVFI 字段，包括 valid、order、insn、PC、rs/rd、mem、trap、intr 和 mode。

**接口关系**：

* **被调用**：TB 顶层实例化 ``u_rvfi_converter``。
* **调用**：sidecar 不调用任务；通过组合赋值和一个 ``always_ff`` 生成 RVFI。
* **共享状态**：内部 ``wb_seq`` 是 sidecar 自己维护的 order counter，不是 probe interface 的
  ``wb_seq``。

§27  RVFI sidecar — trace lane 拆分与 LSU bus
---------------------------------------------

**职责**：sidecar 将 packed trace bus 拆成 i0/i1 内部信号，并把 LSU bus 输入保存为内部
``lsu_bus_*_int``。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L99-L132``）：

.. code-block:: systemverilog

       // ========================================================================
       // Drive trace_i0_* / trace_i1_* from DUT trace ports
       //   trace_address[31:0]  = channel 0 PC
       //   trace_address[63:32] = channel 1 PC
       //   trace_valid[0]       = channel 0 valid
       //   trace_valid[1]       = channel 1 valid
       //   (same pattern for insn, exception, interrupt, rd_*)
       // ========================================================================
       assign trace_i0_valid      = trace_valid[0];
       assign trace_i1_valid      = trace_valid[1];
       assign trace_i0_pc         = trace_address[31:0];
       assign trace_i1_pc         = trace_address[63:32];
       assign trace_i0_insn       = trace_insn[31:0];
       assign trace_i1_insn       = trace_insn[63:32];
       assign trace_i0_exception  = trace_exception[0];
       assign trace_i1_exception  = trace_exception[1];
       assign trace_i0_interrupt  = trace_interrupt[0];

**逐段解释**：

* 第 L99-L106 行：注释定义 packed trace 到 channel 0/1 的拆分规则。
* 第 L107-L115 行：i0 读取低位 valid、PC、insn、exception、interrupt；i1 读取高位字段。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L116-L132``）：

.. code-block:: systemverilog

       assign trace_i1_interrupt  = trace_interrupt[1];
       assign trace_i0_exc_cause  = trace_ecause[3:0];
       assign trace_i1_exc_cause  = trace_ecause[3:0];
       assign trace_i0_rd_addr    = trace_rd_addr[4:0];
       assign trace_i1_rd_addr    = trace_rd_addr[9:5];
       assign trace_i0_rd_wdata   = trace_rd_wdata[31:0];
       assign trace_i1_rd_wdata   = trace_rd_wdata[63:32];

       // ========================================================================
       // Drive LSU bus probe from bus inputs
       // ========================================================================
       assign lsu_bus_valid_int = lsu_bus_valid;
       assign lsu_bus_addr_int  = lsu_bus_addr;
       assign lsu_bus_rdata_int = lsu_bus_rdata;
       assign lsu_bus_wdata_int = lsu_bus_wdata;
       assign lsu_bus_wmask_int = lsu_bus_write ? lsu_bus_wmask : 4'b0;
       assign lsu_bus_write_int = lsu_bus_write;

**逐段解释**：

* 第 L116-L122 行：两个 channel 共享 ``trace_ecause[3:0]``，写回 rd 和数据按低/高半拆分。
* 第 L124-L132 行：LSU bus 内部信号直接来自模块输入；写 mask 只在 ``lsu_bus_write`` 为真时保留，
  否则为 0。

**接口关系**：

* **被调用**：RVFI 输出赋值读取这些内部拆分信号。
* **调用**：无函数调用。
* **共享状态**：内部 ``trace_i*`` 和 ``lsu_bus_*_int`` 是 sidecar 内部组合状态。

§28  RVFI sidecar — order counter 与双 channel 输出
----------------------------------------------------

**职责**：sidecar 用本地 ``wb_seq`` 生成 RVFI order，并从 trace lane、rd 字段和 LSU bus
生成 RVFI 输出。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L134-L149``）：

.. code-block:: systemverilog

       // ========================================================================
       // Writeback sequence counter (increments on each retire)
       // ========================================================================
       assign wb_i0_valid  = trace_i0_valid;
       assign wb_i1_valid  = trace_i1_valid;
       assign wb_i0_pc     = trace_i0_pc;
       assign wb_i1_pc     = trace_i1_pc;
       assign wb_i0_result = trace_i0_rd_wdata;
       assign wb_i1_result = trace_i1_rd_wdata;

       always_ff @(posedge clk or negedge rst_n) begin
           if (!rst_n)
               wb_seq <= 64'b0;
           else if (trace_i0_valid || trace_i1_valid)
               wb_seq <= wb_seq + 64'd1;
       end

**逐段解释**：

* 第 L134-L142 行：sidecar 把 ``wb_i*_valid``、PC 和 result 直接映射到 trace lane 信号。
* 第 L144-L149 行：本地 ``wb_seq`` 在 reset 时清零；任一 lane valid 时每周期加 1。代码没有按两个 lane
  分别递增，而是每个有 retire 的周期递增一次。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L151-L179``）：

.. code-block:: systemverilog

       // ========================================================================
       // RVFI generation: trace packets -> standard RVFI fields
       // ========================================================================

       // Channel 0 (i0)
       assign rvfi_valid[0]       = trace_i0_valid && !trace_i0_exception;
       assign rvfi_order[63:0]    = {32'b0, wb_seq[31:0]};
       assign rvfi_insn[31:0]     = trace_i0_insn;
       assign rvfi_pc_rdata[31:0] = trace_i0_pc;
       assign rvfi_pc_wdata[31:0] = trace_i0_pc + (trace_i0_insn[1:0] != 2'b11 ? 32'd2 : 32'd4);
       assign rvfi_rs1_addr[31:0] = {27'b0, trace_i0_insn[19:15]};
       assign rvfi_rs2_addr[31:0] = {27'b0, trace_i0_insn[24:20]};
       assign rvfi_rd_addr[31:0]  = {27'b0, trace_i0_rd_addr};
       assign rvfi_rd_wdata[31:0] = trace_i0_rd_wdata;
       assign rvfi_trap[0]        = trace_i0_exception;
       assign rvfi_intr[0]        = trace_i0_interrupt;

       // Channel 1 (i1)
       assign rvfi_valid[1]        = trace_i1_valid && !trace_i1_exception;

**逐段解释**：

* 第 L151-L167 行：i0 RVFI valid 过滤 exception；order 使用 ``wb_seq[31:0]``；next PC 按
  compressed 指令 2 字节、普通指令 4 字节递增；rs/rd 字段从 instruction 或 trace rd 取得。
* 第 L168-L179 行：i1 RVFI valid 同样过滤 exception，后续字段与 i0 对称，但 order 使用
  ``wb_seq + 1``。

**关键代码** （``rtl/eh2_veer_wrapper_rvfi.sv:L169-L196``）：

.. code-block:: systemverilog

       assign rvfi_valid[1]        = trace_i1_valid && !trace_i1_exception;
       assign rvfi_order[127:64]   = {32'b0, wb_seq[31:0] + 32'd1};
       assign rvfi_insn[63:32]     = trace_i1_insn;
       assign rvfi_pc_rdata[63:32] = trace_i1_pc;
       assign rvfi_pc_wdata[63:32] = trace_i1_pc + (trace_i1_insn[1:0] != 2'b11 ? 32'd2 : 32'd4);
       assign rvfi_rs1_addr[63:32] = {27'b0, trace_i1_insn[19:15]};
       assign rvfi_rs2_addr[63:32] = {27'b0, trace_i1_insn[24:20]};
       assign rvfi_rd_addr[63:32]  = {27'b0, trace_i1_rd_addr};
       assign rvfi_rd_wdata[63:32] = trace_i1_rd_wdata;
       assign rvfi_trap[1]         = trace_i1_exception;
       assign rvfi_intr[1]         = trace_i1_interrupt;

       // Memory interface (from LSU probe)
       assign rvfi_mem_addr[31:0]  = lsu_bus_valid_int ? lsu_bus_addr_int : 32'b0;
       assign rvfi_mem_rdata[31:0] = lsu_bus_rdata_int;
       assign rvfi_mem_wdata[31:0] = lsu_bus_wdata_int;
       assign rvfi_mem_wmask[3:0]  = lsu_bus_write_int ? lsu_bus_wmask_int : 4'b0;
       assign rvfi_mem_rmask[3:0]  = lsu_bus_write_int ? 4'b0 : 4'b1111;

       // Upper 32 bits of memory fields tied to 0 (32-bit address space)

**逐段解释**：

* 第 L169-L179 行：i1 输出使用 packed bus 高半段，trap/intr 直接来自 trace exception/interrupt。
* 第 L181-L186 行：memory 字段来自 LSU bus 内部信号；store 时写 mask 来自 bus，read mask 使用
  ``4'b1111``。
* 第 L188-L196 行：memory 字段高 32 位清零，``rvfi_mode`` 固定为 ``4'b0011``。

**接口关系**：

* **被调用**：TB 顶层把 sidecar 输出接到 ``eh2_rvfi_if``。
* **调用**：无函数调用。
* **共享状态**：本地 ``wb_seq`` 是 RVFI order 状态；memory 输出读取 LSU bus 内部组合信号。

§29  TB RVFI sidecar 实例 — trace + LSU 到 ``eh2_rvfi_if``
----------------------------------------------------------

**职责**：TB 顶层从 LSU AXI 信号派生 sidecar 输入，实例化 ``eh2_veer_wrapper_rvfi``，
并把输出接到 ``rvfi_intf``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L760-L793``）：

.. code-block:: systemverilog

     assign lsu_bus_valid = (lsu_axi_awvalid && lsu_axi_awready) || (lsu_axi_arvalid && lsu_axi_arready) || (lsu_axi_wvalid && lsu_axi_wready) || (lsu_axi_rvalid && lsu_axi_rready);
     assign lsu_bus_addr  = lsu_axi_awvalid ? lsu_axi_awaddr : lsu_axi_araddr;
     assign lsu_bus_rdata = lsu_axi_rdata[31:0];
     assign lsu_bus_wdata = lsu_axi_wdata[31:0];
     assign lsu_bus_wmask = lsu_axi_wstrb[3:0];
     assign lsu_bus_write = lsu_axi_awvalid && lsu_axi_awready;

     //--------------------------------------------------------------------------
     // RVFI Converter Instance (Trace + LSU -> Standard RVFI format)
     //--------------------------------------------------------------------------
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

**逐段解释**：

* 第 L760-L766 行：TB 用 AXI valid/ready 信号组合出 ``lsu_bus_valid``，从 AW/AR 选择地址，
  并提取 LSU read/write data、write mask 和 write 标志。
* 第 L768-L785 行：sidecar 实例接入 thread 0 trace 字段，包括写回三元组。
* 第 L787-L793 行：LSU bus 派生信号接入 sidecar memory 输入。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L795-L813``）：

.. code-block:: systemverilog

       // RVFI output -> interface
       .rvfi_valid       (rvfi_intf.rvfi_valid),
       .rvfi_order       (rvfi_intf.rvfi_order),
       .rvfi_insn        (rvfi_intf.rvfi_insn),
       .rvfi_pc_rdata    (rvfi_intf.rvfi_pc_rdata),
       .rvfi_pc_wdata    (rvfi_intf.rvfi_pc_wdata),
       .rvfi_rs1_addr    (rvfi_intf.rvfi_rs1_addr),
       .rvfi_rs2_addr    (rvfi_intf.rvfi_rs2_addr),
       .rvfi_rd_addr     (rvfi_intf.rvfi_rd_addr),
       .rvfi_rd_wdata    (rvfi_intf.rvfi_rd_wdata),
       .rvfi_mem_addr    (rvfi_intf.rvfi_mem_addr),
       .rvfi_mem_rdata   (rvfi_intf.rvfi_mem_rdata),
       .rvfi_mem_wdata   (rvfi_intf.rvfi_mem_wdata),
       .rvfi_mem_rmask   (rvfi_intf.rvfi_mem_rmask),
       .rvfi_mem_wmask   (rvfi_intf.rvfi_mem_wmask),
       .rvfi_trap        (rvfi_intf.rvfi_trap),
       .rvfi_intr        (rvfi_intf.rvfi_intr),
       .rvfi_mode        (rvfi_intf.rvfi_mode)
     );

**逐段解释**：

* 第 L795-L813 行：sidecar 输出逐字段接到 ``rvfi_intf``，未见额外过滤或重命名逻辑。

**接口关系**：

* **被调用**：testbench elaboration 时实例化 sidecar。
* **调用**：模块例化连接 trace、LSU 和 RVFI interface。
* **共享状态**：``rvfi_intf`` 是 sidecar 输出进入 UVM 或后续检查逻辑的共享接口。

§30  ``eh2_rvfi_if`` — RVFI monitor interface
---------------------------------------------

**职责**：``eh2_rvfi_if`` 保存 sidecar 输出的双 channel RVFI 信号，并提供 clocking block
和 monitor modport。

**关键代码** （``dv/uvm/core_eh2/env/eh2_rvfi_if.sv:L1-L29``）：

.. code-block:: systemverilog

   // ============================================================================
   // eh2_rvfi_if.sv — RVFI monitor interface for UVM scoreboard
   //
   // Captures RVFI retire packets from eh2_veer_wrapper_rvfi for cosim
   // self-consistency checks. Dual-channel (i0 / i1) for EH2 dual-issue.
   // ============================================================================

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

**逐段解释**：

* 第 L1-L6 行：注释说明该 interface 捕获 ``eh2_veer_wrapper_rvfi`` 输出，用于 cosim
  self-consistency checks，且是 i0/i1 双 channel。
* 第 L8-L29 行：interface 声明 RVFI 信号集合。宽度与 sidecar 输出一致，例如
  ``rvfi_order`` 为 128 位，两个 64 位 channel 拼接。

**关键代码** （``dv/uvm/core_eh2/env/eh2_rvfi_if.sv:L30-L49``）：

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

**逐段解释**：

* 第 L30-L49 行：clocking block 在 ``posedge clk`` 同步采样全部 RVFI 信号。

**关键代码** （``dv/uvm/core_eh2/env/eh2_rvfi_if.sv:L51-L62``）：

.. code-block:: systemverilog

     // Modport for monitor
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

**逐段解释**：

* 第 L51-L62 行：monitor modport 暴露 clock/reset 和 RVFI 信号输入集合，供监控组件使用。

**接口关系**：

* **被调用**：TB 顶层 sidecar 输出连接该 interface。
* **调用**：interface 自身不调用任务。
* **共享状态**：``cb`` 和 ``monitor`` modport 是后续 RVFI 监控逻辑的采样入口。

§31  ADR 约束与当前实现对应关系
-------------------------------

本节只引用已在 :file:`docs/adr/INDEX.md` 中登记的 ADR。索引第 L24-L45 行列出
``0001`` 至 ``0020`` 的 canonical 文件名；第 L29、L40、L43 行分别确认
:ref:`adr-0004`、:ref:`adr-0015` 和 :ref:`adr-0018` 为 Accepted。

**关键摘录** （``docs/adr/INDEX.md:L24-L45``）：

* 第 L24-L29 行：ADR 表把 ``0001`` 至 ``0004`` 登记为 Accepted，其中 ``0004`` 的摘要是给
  EH2 trace 增加 verification-oriented retire 字段。
* 第 L40 行：``0015-rvfi-adapter-layer.md`` 的状态为 Accepted，摘要是定义避免修改 upstream
  design RTL 的 RVFI adapter layer。
* 第 L43 行：``0018-wb-tag-strict-matching.md`` 的状态为 Accepted，摘要是用严格
  ``wb_tag`` 关联替代异步写回 ``rd`` 启发式。

**逐段解释**：

* 第 L24-L29 行：ADR index 使用文件编号作为 canonical 编号，``0004`` 的摘要明确是给 EH2 trace
  添加 verification-oriented retire fields，而不是把完整 RVFI bus 强塞进 design RTL。
* 第 L40 行：``0015`` 摘要确认 RVFI adapter layer 的决策是避免修改 upstream design RTL。
* 第 L43 行：``0018`` 摘要确认异步写回匹配从 rd 启发式切换为严格 ``wb_tag`` 关联。

**ADR 对应关系**：

* :ref:`adr-0001`：早期 trace + probe 数据路径。当前实现仍保留 probe，但常规 wb 主路径已经从
  probe 转移到 trace packet。
* :ref:`adr-0004`：当前 ``eh2_trace_pkt_t``、``eh2_dec.tracep``、``eh2_veer`` trace 端口和
  ``eh2_trace_monitor`` 写回采样都体现该 ADR。
* :ref:`adr-0015`：``eh2_veer_wrapper_rvfi`` 作为 sidecar 将 trace + LSU 转换为 RVFI。
* :ref:`adr-0018`：scoreboard 中 ``has_matching_async_wb`` 与 ``try_consume_async_wb`` 只按
  ``wb_tag`` 匹配异步 hint。

§32  边界与易误读点
--------------------

* ``trace pkt`` 不是标准 RVFI。标准化 RVFI 信号由 :file:`rtl/eh2_veer_wrapper_rvfi.sv`
  sidecar 推导生成。
* ``eh2_trace_intf.sv`` 文件头部的「No rd_addr/rd_wdata」注释与当前代码不一致；当前实现确实声明并解码
  ``rd_valid``、``rd_addr`` 和 ``rd_wdata``。
* ``eh2_trace_monitor`` 当前 virtual interface 参数写为 ``NUM_THREADS(1)``，并只解码
  thread 0 的 i0/i1 便捷信号；scoreboard 数据结构可按 2 个 thread 保存队列。
* ``interrupt && !exception`` 的 trace item 是 interrupt-only 通知，不执行
  ``riscv_cosim_step``。
* probe monitor 不发送常规 pipeline wb；它只发送 DIV、DIV overwrite-cancel 和 NB-load 的异步 hint。
* sidecar 的 ``wb_seq`` 是 RVFI order counter；probe interface 的 ``wb_seq`` 是异步写回匹配 tag。
  二者位于不同模块，不能混用。
* sidecar 的 memory 字段只使用当前 TB 派生的 LSU bus 低 32 位信号，高 32 位清零。

§33  参考资料
--------------

* :ref:`adr-0001` — trace plus DUT probe cosim 数据路径。
* :ref:`adr-0004` — EH2 trace packet 增加 verification-oriented retire 字段。
* :ref:`adr-0015` — RVFI adapter layer，不替代 DUT wrapper。
* :ref:`adr-0018` — 异步写回严格 ``wb_tag`` 匹配。
* :doc:`../05_verification_arch/cosim_scoreboard` — cosim scoreboard 结构说明。
* :doc:`../05_verification_arch/agent_trace` — trace agent 架构说明。
* :file:`/home/host/eh2-veri/rtl/design/include/eh2_def.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec.sv`
* :file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* :file:`/home/host/eh2-veri/rtl/eh2_veer_wrapper_rvfi.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_dut_probe_if.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_rvfi_if.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
