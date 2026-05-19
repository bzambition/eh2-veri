.. _dual_thread:
.. _02_core_reference/dual_thread:

双硬件线程（SMT）
================================================================================

:status: draft
:source: syn/include/eh2_param.vh; rtl/design/dec/eh2_dec.sv; rtl/design/dec/eh2_dec_ib_ctl.sv; rtl/design/dec/eh2_dec_decode_ctl.sv; rtl/design/dec/eh2_dec_tlu_top.sv; rtl/design/lib/beh_lib.sv; dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv; dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv; dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv; dv/cosim/cosim.h; dv/cosim/cosim_dpi.svh; dv/cosim/cosim_dpi.cc; dv/cosim/spike_cosim.h; dv/cosim/spike_cosim.cc; rtl/lec_shim/eh2_veer_lec_pack.sv; docs/adr/0016-multi-hart-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界与当前结论
--------------------------------------------------------------------------------

本章只描述当前仓库源码中可以直接回溯的双硬件线程证据。当前 release 参数文件
:file:`syn/include/eh2_param.vh` 把 ``NUM_THREADS`` 设为 ``6'h01``，因此本章不会把
当前 release 配置描述成已启用双线程运行。与此同时，RTL 中存在 ``pt.NUM_THREADS``
条件生成、``rvarbiter2_smt`` 仲裁模块、thread CSR 选择逻辑；UVM trace/TB 端口按
``RV_NUM_THREADS`` 或 ``NUM_THREADS`` 参数展开；cosim DPI、``SpikeCosim`` 和
scoreboard 也都把 ``thread_id`` 作为路由键。准确地说，当前源码同时包含：

* **当前参数实例** ：``NUM_THREADS=1``。
* **RTL 双线程结构** ：``pt.NUM_THREADS > 1`` 时启用 decode SMT 仲裁和 thread CSR mux。
* **UVM trace 边界** ：interface 参数化，但当前 ``eh2_trace_monitor`` virtual interface
  类型固定为 ``NUM_THREADS(1)``，并只产生 ``thread_id=0`` 的 trace pkt。
* **cosim 支撑面** ：ADR-0016、DPI、``SpikeCosim`` 和 scoreboard 已按 ``thread_id`` 做
  per-hart/per-thread 路由，最大线程数由 ``COSIM_MAX_THREADS`` 限制为 2。

可见数据流如下：

.. code-block:: bash

   syn/include/eh2_param.vh
      |
      |-- pt.NUM_THREADS = 1 in current parameter set
      |
      +--> RTL generate blocks
      |      |-- NUM_THREADS == 1: fixed tid 0 path
      |      `-- NUM_THREADS > 1 : rvarbiter2_smt + thread CSR mux
      |
      +--> UVM TB trace ports
      |      |-- eh2_trace_intf is parameterized
      |      `-- eh2_trace_monitor currently emits thread_id=0
      |
      `--> cosim / scoreboard
             |-- DPI functions carry thread_id
             |-- SpikeCosim owns processors[0..1]
             `-- scoreboard queues pending_trace_q[tid] and async_wb_q[tid]

**逐段解释** ：

* 参数文件决定当前编译配置，本章所有“当前 release”结论都以该参数文件为准。
* RTL 的 ``pt.NUM_THREADS`` 条件块说明源码具备多线程 elaboration 分支，但该分支是否
  被当前配置采用取决于参数值。
* UVM trace 侧不能只看接口维度。``eh2_trace_intf`` 可以按线程展开，但 monitor 代码
  明确只采样 thread 0 的两个 slot。
* cosim 侧的 per-thread 支撑面来自 ADR-0016、C++ 对象数组、DPI 参数和 scoreboard
  队列；这些源码证据与 trace monitor 的当前边界需要分开描述。

**接口关系** ：

* **被调用** ：本章支撑 :ref:`pipeline`、:ref:`rvfi_trace`、:ref:`cosim_scoreboard`、
  :ref:`appendix_b_uvm/trace_agent` 和 :ref:`appendix_c_tools/cosim_cpp`。
* **调用** ：文档不调用运行时代码；源码链路中 RTL generate、UVM analysis FIFO、DPI-C
  和 Spike C++ 对象共同构成双线程支撑面。
* **共享状态** ：``NUM_THREADS``、``RV_NUM_THREADS``、``thread_id``、``tid``、
  ``pending_trace_q``、``async_wb_q``、``prev_mip``、Spike ``processors`` 和共享
  memory bus。

§2  当前参数：release 配置是 ``NUM_THREADS=1``
--------------------------------------------------------------------------------

§2.1  ``syn/include/eh2_param.vh`` 中的线程数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_param.vh`` 是当前综合/LEC 参数集合的一部分。本文件中的
``NUM_THREADS`` 字段给出当前参数实例，而不是描述所有可选 profile。

**关键代码** （``syn/include/eh2_param.vh:L155-L167``）：

.. code-block:: systemverilog

       LOAD_TO_USE_BUS_PLUS1  : 5'h00         ,
       LOAD_TO_USE_PLUS1      : 5'h00         ,
       LSU_BUS_ID             : 5'h01         ,
       LSU_BUS_PRTY           : 6'h02         ,
       LSU_BUS_TAG            : 8'h04         ,
       LSU_NUM_NBLOAD         : 9'h008        ,
       LSU_NUM_NBLOAD_WIDTH   : 7'h03         ,
       LSU_SB_BITS            : 9'h010        ,
       LSU_STBUF_DEPTH        : 8'h0A         ,
       NO_ICCM_NO_ICACHE      : 5'h00         ,
       NO_SECONDARY_ALU       : 5'h00         ,
       NUM_THREADS            : 6'h01         ,
       PIC_2CYCLE             : 5'h01         ,

**逐段解释** ：

* 第 L155-L163 行：这些 LSU 相关字段与 ``NUM_THREADS`` 相邻，说明该片段属于同一组
  ``eh2_param_t`` 参数赋值，而不是脚本或测试配置。
* 第 L164-L165 行：``NO_ICCM_NO_ICACHE`` 与 ``NO_SECONDARY_ALU`` 继续给出当前核心
  配置开关。
* 第 L166 行：``NUM_THREADS`` 的当前值是 ``6'h01``。因此当前 release 参数实例只展开
  一个硬件线程。
* 第 L167 行：``PIC_2CYCLE`` 紧随其后，说明线程数与 PIC 等硬件参数一起被固化到当前
  参数文件中。

**接口关系** ：

* **被调用** ：该参数通过 RTL ``pt`` 参数进入 ``eh2_dec``、``eh2_dec_tlu_top``、
  ``eh2_veer_lec_pack`` 等模块。
* **调用** ：无函数调用；这是参数数据源。
* **共享状态** ：``pt.NUM_THREADS`` 是 RTL generate 条件、端口宽度和部分 formal/LEC
  wrapper 宽度的共同依据。

§2.2  单线程路径与多线程路径的 RTL 分界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_dec.sv`` 在 decode 侧根据 ``pt.NUM_THREADS`` 选择单线程固定路径或
多线程仲裁路径。当前参数为 1 时，代码进入 ``genst`` 分支。

**关键代码** （``rtl/design/dec/eh2_dec.sv:L805-L829``）：

.. code-block:: systemverilog

   assign ready_in[pt.NUM_THREADS-1:0] = ib0_valid_in[pt.NUM_THREADS-1:0];
   assign lsu_in[pt.NUM_THREADS-1:0] = ib0_lsu_in[pt.NUM_THREADS-1:0];
   assign mul_in[pt.NUM_THREADS-1:0] = ib0_mul_in[pt.NUM_THREADS-1:0];
   assign i0_only_in[pt.NUM_THREADS-1:0] = ib0_i0_only_in[pt.NUM_THREADS-1:0];
   
   logic i0_sel_i0_t1_d;
   logic [1:0] i1_sel_i0_d, i1_sel_i1_d;
   
   
   if (pt.NUM_THREADS == 1) begin: genst
      assign gpr_i0_rs1_d[31:0] = gpr_i0rs1_d[0];
      assign gpr_i0_rs2_d[31:0] = gpr_i0rs2_d[0];
      assign gpr_i1_rs1_d[31:0] = gpr_i1rs1_d[0];
      assign gpr_i1_rs2_d[31:0] = gpr_i1rs2_d[0];
   
      assign dec_i0_tid_d = 1'b0;
      assign dec_i1_tid_d = 1'b0;
   
      assign ready[0] = 1'b1;
   
      assign i0_sel_i0_t1_d = 1'b0;
      assign i1_sel_i0_d[1:0] = 2'b00;
      assign i1_sel_i1_d[1:0] = 2'b01;
   
   end

**逐段解释** ：

* 第 L805-L808 行：decode 从每个 thread 的 ``ib0`` 状态形成仲裁输入，包括是否 valid、
  是否 LSU、是否 MUL、是否只能进入 i0 slot。
* 第 L810-L811 行：``i0_sel_i0_t1_d``、``i1_sel_i0_d`` 和 ``i1_sel_i1_d`` 是后续选择
  thread/slot 的本地信号。
* 第 L814-L818 行：当 ``pt.NUM_THREADS == 1`` 时，GPR 读数据只从索引 0 取出。
* 第 L820-L827 行：单线程路径把 ``dec_i0_tid_d`` 和 ``dec_i1_tid_d`` 都固定为 0，
  并让 ``ready[0]`` 恒为 1；i1 选择信号固定为 thread 0 的 i1 路径。

**接口关系** ：

* **被调用** ：由 ``eh2_dec`` elaboration 时根据 ``pt.NUM_THREADS`` 选择。
* **调用** ：单线程分支不实例化 ``rvarbiter2_smt``。
* **共享状态** ：``ib0_valid_in``、``ib0_lsu_in``、``ib0_mul_in``、``ib0_i0_only_in``、
  ``gpr_i0rs*_d`` 和 ``gpr_i1rs*_d``。

§2.3  多线程路径实例化 ``rvarbiter2_smt``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当 ``pt.NUM_THREADS`` 不是 1 时，``eh2_dec.sv`` 进入 ``genmt`` 分支，把
两线程仲裁输入接到 ``rvarbiter2_smt``，并用仲裁结果产生 ``dec_i0_tid_d`` 与
``dec_i1_tid_d``。

**关键代码** （``rtl/design/dec/eh2_dec.sv:L831-L860``）：

.. code-block:: systemverilog

   else begin: genmt
   
      assign gpr_i0_rs1_d[31:0] = gpr_i0rs1_d[1] | gpr_i0rs1_d[0];
      assign gpr_i0_rs2_d[31:0] = gpr_i0rs2_d[1] | gpr_i0rs2_d[0];
      assign gpr_i1_rs1_d[31:0] = gpr_i1rs1_d[1] | gpr_i1rs1_d[0];
      assign gpr_i1_rs2_d[31:0] = gpr_i1rs2_d[1] | gpr_i1rs2_d[0];
   
   
   
      rvarbiter2_smt dec_arbiter (
                                  .clk(active_clk),
                                  .flush(exu_flush_final[1:0]),
                                  .shift(dec_i0_decode_d),
                                  .ready_in(ready_in[1:0]),
                                  .lsu_in(lsu_in[1:0]),
                                  .mul_in(mul_in[1:0]),
                                  .i0_only_in(i0_only_in[1:0]),
                                  .thread_stall_in(dec_thread_stall_in[1:0]),
                                  .force_favor_flip(dec_force_favor_flip_d),
                                  .ready(ready[1:0]),
                                  .i0_sel_i0_t1(i0_sel_i0_t1_d),
                                  .i1_sel_i0(i1_sel_i0_d[1:0]),
                                  .i1_sel_i1(i1_sel_i1_d[1:0]),
                                  .*
                                  );

**逐段解释** ：

* 第 L831 行：``genmt`` 是 ``pt.NUM_THREADS != 1`` 时的多线程分支。结合 §2.1，当前
  release 参数不会选择这一分支。
* 第 L833-L836 行：多线程分支把两个 thread 的 GPR 读数据按位 OR 后送到共享 decode
  datapath。该 OR 的正确性依赖上游每个 thread 只驱动被选中的路径。
* 第 L840-L855 行：``rvarbiter2_smt`` 接收 flush、decode shift、ready、LSU、MUL、
  i0-only、thread stall 和强制翻转 favor 的输入，输出 thread ready 与 i0/i1 选择。
* 第 L857-L859 行：i0 的 thread ID 直接来自 ``i0_sel_i0_t1_d``；i1 的 thread ID 由
  ``i1_sel_i1_d[1]`` 或 ``i1_sel_i0_d[1]`` 决定。

**接口关系** ：

* **被调用** ：``eh2_dec`` 在 ``pt.NUM_THREADS > 1`` 的配置下实例化。
* **调用** ：调用 ``rvarbiter2_smt``。
* **共享状态** ：``active_clk``、``exu_flush_final``、``ready_in``、``lsu_in``、
  ``mul_in``、``i0_only_in``、``dec_thread_stall_in``、``dec_force_favor_flip_d``。

§2.4  IB 与 GPR 控制按 ``pt.NUM_THREADS`` 复制
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_dec.sv`` 通过 generate 循环为每个 thread 连接 IB 控制与 GPR 控制。
这说明 thread 维度不是只存在于 cosim，而是进入 decode 内部结构。

**关键代码** （``rtl/design/dec/eh2_dec.sv:L726-L766``，节选）：

.. code-block:: systemverilog

                                          .dec_i1_cancel_e1  (dec_i1_cancel_e1[i]),
                                          .exu_flush_final   (exu_flush_final[i]),
                                          .ib3_valid_d       (ib3_valid_d[i]   ),
                                          .ib2_valid_d       (ib2_valid_d[i]   ),
                                          .ib1_valid_d       (ib1_valid_d[i]   ),
                                          .ib0_valid_d       (ib0_valid_d[i]   ),
                                          .ib0_valid_in      (ib0_valid_in[i]  ),
                                          .ib0_lsu_in        (ib0_lsu_in[i]    ),
                                          .ib0_mul_in        (ib0_mul_in[i]    ),
                                          .ib0_i0_only_in    (ib0_i0_only_in[i]),
                                          .i0_instr_d        (i0_instr_d[i]    ),
                                          .i1_instr_d        (i1_instr_d[i]    ),
                                          .i0_debug_valid_d  (i0_debug_valid_d[i]),
                                          .i0_pc_d           (i0_pc_d[i]       ),
                                          .i1_pc_d           (i1_pc_d[i]       ),
                                          .i0_pc4_d          (i0_pc4_d[i]      ),
                                          .i1_pc4_d          (i1_pc4_d[i]      ),
                                          .i0_bp_index       (i0_bp_index[i]   ),
                                          .i0_bp_fghr        (i0_bp_fghr[i]    ),
                                          .i0_bp_btag        (i0_bp_btag[i]    ),
                                          .i0_bp_fa_index    (i0_bp_fa_index[i]),
                                          .i0_bp_toffset     (i0_bp_toffset[i] ),
                                          .i1_bp_index       (i1_bp_index[i]   ),

**逐段解释** ：

* 第 L726-L735 行：IB 控制输出 ``ib*_valid_d``、``ib0_valid_in``、``ib0_lsu_in``、
  ``ib0_mul_in``、``ib0_i0_only_in`` 都按 ``[i]`` 索引进入 thread 维度。
* 第 L736-L742 行：每个 thread 拥有自己的 i0/i1 指令与 PC/PC+4 输出。
* 第 L743-L748 行：分支预测相关 index、FGHR、BTB tag 与 fall-through index 也按 thread
  索引传递。
* 第 L749-L766 行：i1 分支预测、异常、debug、compressed instruction 和 predecode
  信号继续沿相同的 ``[i]`` 维度连接。

**接口关系** ：

* **被调用** ：``eh2_dec`` 的 IB generate block 调用 ``eh2_dec_ib_ctl``。
* **调用** ：该片段本身是实例端口连接，不调用任务或函数。
* **共享状态** ：``i`` 是 generate thread 索引；后续 ``ready_in``、``lsu_in``、
  ``mul_in`` 和 ``i0_only_in`` 都从这些 per-thread 输出派生。

**关键代码** （``rtl/design/dec/eh2_dec.sv:L772-L797``）：

.. code-block:: systemverilog

   for (genvar i=0; i<pt.NUM_THREADS; i++) begin : arf
   
      eh2_dec_gpr_ctl #(.pt(pt)) arf (.*,
                                       .clk (active_thread_l2clk[i]),
                                       .tid (1'(i)),
   
                                       .rtid0(dec_i0_tid_d),
                                       .rtid1(dec_i0_tid_d),
                                       .rtid2(dec_i1_tid_d),
                                       .rtid3(dec_i1_tid_d),
   
                                       // inputs
                                       .raddr0(dec_i0_rs1_d[4:0]), .rden0(dec_i0_rs1_en_d),
                                       .raddr1(dec_i0_rs2_d[4:0]), .rden1(dec_i0_rs2_en_d),
                                       .raddr2(dec_i1_rs1_d[4:0]), .rden2(dec_i1_rs1_en_d),
                                       .raddr3(dec_i1_rs2_d[4:0]), .rden3(dec_i1_rs2_en_d),
   
                                       .wtid0(dec_i0_tid_wb),              .waddr0(dec_i0_waddr_wb[4:0]),            .wen0(dec_i0_wen_wb),            .wd0(dec_i0_wdata_wb[31:0]),
                                       .wtid1(dec_i1_tid_wb),              .waddr1(dec_i1_waddr_wb[4:0]),            .wen1(dec_i1_wen_wb),            .wd1(dec_i1_wdata_wb[31:0]),
                                       .wtid2(lsu_nonblock_load_data_tid), .waddr2(dec_nonblock_load_waddr[i][4:0]), .wen2(dec_nonblock_load_wen[i]), .wd2(lsu_nonblock_load_data[31:0]),
                                       .wtid3(div_tid_wb),                 .waddr3(div_waddr_wb[4:0]),               .wen3(exu_div_wren),             .wd3(exu_div_result[31:0]),

**逐段解释** ：

* 第 L772-L776 行：GPR 控制同样按 ``pt.NUM_THREADS`` generate，时钟使用
  ``active_thread_l2clk[i]``，并把 ``tid`` 绑定为当前 generate 索引。
* 第 L778-L781 行：读端口的 thread ID 来自 decode 选择结果，i0 两个源寄存器使用
  ``dec_i0_tid_d``，i1 两个源寄存器使用 ``dec_i1_tid_d``。
* 第 L784-L787 行：四个读端口共享 decode 阶段寄存器地址和读使能，由 ``rtid*`` 决定
  读哪个 thread 的 GPR 实例。
* 第 L789-L792 行：写端口覆盖普通 i0/i1 wb、NB-load 写回和 DIV 写回；每条写回都有
  对应 ``wtid*``。

**接口关系** ：

* **被调用** ：由 ``eh2_dec`` 的 GPR generate block 实例化。
* **调用** ：实例化 ``eh2_dec_gpr_ctl``。
* **共享状态** ：``active_thread_l2clk``、``dec_i*_tid_*``、``lsu_nonblock_load_data_tid``、
  ``div_tid_wb`` 和 ``dec_nonblock_load_w*``。

§3  ``rvarbiter2_smt`` 仲裁逻辑
--------------------------------------------------------------------------------

§3.1  仲裁器接口：输入来自两个 thread 的 IB0 状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``rvarbiter2_smt`` 是两路 SMT decode 仲裁模块。它不读取完整指令，而是读取
每个 thread 的 ready、LSU、MUL、i0-only、stall 和 flush 类摘要信号。

**关键代码** （``rtl/design/lib/beh_lib.sv:L812-L829``）：

.. code-block:: systemverilog

   module rvarbiter2_smt
     (
      input  logic       [1:0] flush,
      input  logic       [1:0] ready_in,
      input  logic       [1:0] lsu_in,
      input  logic       [1:0] mul_in,
      input  logic       [1:0] i0_only_in,
      input  logic       [1:0] thread_stall_in,
      input  logic             force_favor_flip,
      input  logic             shift,
      input  logic             clk,
      input  logic             rst_l,
      input  logic             scan_mode,
      output logic [1:0]       ready,
      output logic             i0_sel_i0_t1,
      output logic [1:0]       i1_sel_i1,
      output logic [1:0]       i1_sel_i0
      );

**逐段解释** ：

* 第 L812-L813 行：模块名表明它是 2 路 SMT 仲裁器；接口中所有 thread 数据宽度都是
  ``[1:0]``。
* 第 L814-L820 行：输入覆盖 flush、ready、LSU、MUL、i0-only、thread stall 和强制
  favor 翻转。它们是仲裁依据。
* 第 L821-L824 行：``shift``、``clk``、``rst_l``、``scan_mode`` 让仲裁器保存状态并
  接入扫描模式。
* 第 L825-L828 行：输出分为 thread ready、i0 是否选择 thread 1，以及 i1 从 i1 或 i0
  队列选择的编码。

**接口关系** ：

* **被调用** ：``eh2_dec.sv`` 的 ``genmt`` 分支实例化该模块。
* **调用** ：内部调用 ``rvdff`` 保存 flush、ready、favor 和 filtered ready。
* **共享状态** ：``favor`` 是跨周期保存的本地状态；输入来自 decode/IB。

§3.2  ``eff_ready_in``：flush 与 stall 会先过滤 ready
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：仲裁器先用 flush 和 thread stall 过滤 ready，再寄存成 ``ready``。这样下游
decode 不会选择已 flush 的 thread，也不会在两个 thread 同时 ready 时选择已知下一拍
stall 的 thread。

**关键代码** （``rtl/design/lib/beh_lib.sv:L844-L859``）：

.. code-block:: systemverilog

   rvdff #(2) flushff (.*,
                        .clk(clk),
                        .din(flush[1:0]),
                        .dout(flush_ff[1:0])
                        );
   
   // if thread is flushed take it out of arbitration right away
   // if thread is stalled AND both threads ready make ready=0 for stall thread
   assign eff_ready_in[1:0] = ready_in[1:0] & ~({2{ready_in[1]&ready_in[0]}} & thread_stall_in[1:0]) & ~flush[1:0] & ~flush_ff[1:0];
   
   
   rvdff #(2) ready_ff (.*,
                        .clk(clk),
                        .din(eff_ready_in[1:0]),
                        .dout(ready[1:0])
                        );

**逐段解释** ：

* 第 L844-L848 行：``flush`` 被打一拍成为 ``flush_ff``，使当前 flush 和上一拍 flush
  都能影响 ready 过滤。
* 第 L850-L852 行：``eff_ready_in`` 同时屏蔽当前 flush、上一拍 flush，以及“两线程都
  ready 且某 thread 已知 stall”的情况。
* 第 L855-L859 行：过滤后的 ``eff_ready_in`` 再寄存为 ``ready``。因此 ``ready`` 是
  下游看到的仲裁 ready，而不是原始 IB0 valid。

**接口关系** ：

* **被调用** ：``rvarbiter2_smt`` 内部组合与时序逻辑。
* **调用** ：两个 ``rvdff``。
* **共享状态** ：``flush_ff``、``ready``、``eff_ready_in``。

§3.3  favor 更新：只在冲突条件下翻转
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``favor`` 是仲裁器的跨周期偏好位。代码只在两个 thread 都 ready 且出现
LSU/MUL/i0-only 冲突，或外部强制翻转时更新它。

**关键代码** （``rtl/design/lib/beh_lib.sv:L861-L880``）：

.. code-block:: systemverilog

   // optimize for power: only update favor bit when you have to
   assign update_favor_in = &eff_ready_in[1:0] & (lsu2_in | mul2_in | i0_only2_in);
   
   rvdff #(1) update_favor_ff (.*,
                        .clk(clk),
                        .din(update_favor_in),
                        .dout(update_favor)
                        );
   
   
   assign favor_in = (shift & (update_favor | force_favor_flip)) ? ~favor : favor;
   
   // i0_only optimization : make i0_only favored if at all possible
   assign favor_final_raw = (favor_in       & !i0_only_in[0]) |
                            (!i0_only_in[0] &  i0_only_in[1]) |
                            (favor_in       &  i0_only_in[1]);
   
   assign favor_final = (force_favor_flip) ? favor_in : favor_final_raw;
   
   rvdff #(1) favor_ff (.*, .clk(clk), .din(favor_final),  .dout(favor) );

**逐段解释** ：

* 第 L861-L862 行：只有两个 thread 都有效且同时命中 LSU、MUL 或 i0-only 类冲突时，
  ``update_favor_in`` 才为 1。
* 第 L864-L868 行：``update_favor`` 被寄存，避免组合路径直接影响 favor 更新。
* 第 L871 行：``shift`` 表示本周期 decode 发生推进；只有推进且需要更新或强制翻转时，
  ``favor`` 才取反。
* 第 L873-L878 行：``i0_only`` 会修正 raw favor；``force_favor_flip`` 则直接使用
  ``favor_in``。
* 第 L880 行：``favor_final`` 被寄存为下一拍 ``favor``。

**接口关系** ：

* **被调用** ：``rvarbiter2_smt`` 内部。
* **调用** ：``rvdff`` 保存 ``update_favor`` 和 ``favor``。
* **共享状态** ：``eff_ready_in``、``lsu2_in``、``mul2_in``、``i0_only2_in``、
  ``force_favor_flip``、``shift``。

§3.4  冲突取消与 slot 选择
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：在两个 thread 都 ready 且两边都是 LSU 或 MUL 时，仲裁器取消非 favor thread，
再根据 ``fready`` 与 ``favor`` 产生 i0/i1 选择。

**关键代码** （``rtl/design/lib/beh_lib.sv:L882-L910``）：

.. code-block:: systemverilog

   // SMT optimization
   assign ready2_in  = eff_ready_in[1] & eff_ready_in[0];
   assign lsu2_in    = lsu_in[1] & lsu_in[0];
   assign mul2_in    = mul_in[1] & mul_in[0];
   assign i0_only2_in = i0_only_in[1] & i0_only_in[0];
   
   // cancel non favored thread in the case of 2 muls or 2 load/stores
   // this case won't happen if i0_only for one or more threads
   assign thread_cancel_in[1:0] = { (lsu2_in | mul2_in) & ready2_in & ~favor_in,
                                    (lsu2_in | mul2_in) & ready2_in &  favor_in  };
   rvdff #(2) fready_ff (.*,
                        .clk(clk),
                        .din(eff_ready_in[1:0] & ~thread_cancel_in[1:0]),
                        .dout(fready[1:0])
                        );
   
   assign i0_sel_i0_t1 = (fready[1]&favor) | (!fready[0]);
   
   assign i1_sel_i1[1] = (!fready[0]);
   
   assign i1_sel_i0[1] = (fready[0]&fready[1]&!favor);
   
   assign i1_sel_i1[0] = (!fready[1]);
   
   assign i1_sel_i0[0] = (fready[0]&fready[1]&favor);

**逐段解释** ：

* 第 L882-L886 行：``ready2_in``、``lsu2_in``、``mul2_in`` 和 ``i0_only2_in`` 是双
  thread 同时命中条件。
* 第 L888-L891 行：当两个 thread 同时 ready 且同时 LSU/MUL 时，``thread_cancel_in``
  按 ``favor_in`` 取消非 favor 的一边。
* 第 L892-L896 行：``fready`` 保存过滤后的最终 ready，作为 slot 选择输入。
* 第 L898-L906 行：``i0_sel_i0_t1`` 和 ``i1_sel_*`` 用 ``fready`` 与 ``favor`` 选择
  i0/i1 取哪个 thread 的 IB 内容。

**接口关系** ：

* **被调用** ：``rvarbiter2_smt`` 内部。
* **调用** ：``rvdff`` 保存 ``fready``。
* **共享状态** ：``fready``、``favor``、``favor_in`` 和输入摘要信号。

§3.5  IB0 的 LSU/MUL/i0-only 摘要来自 ``eh2_dec_ib_ctl``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_dec_ib_ctl`` 从即将进入 IB0 的 predecode 信息中生成
``ib0_lsu_in``、``ib0_mul_in`` 和 ``ib0_i0_only_in``，这些信号被 ``eh2_dec`` 收集后
送入 SMT 仲裁器。

**关键代码** （``rtl/design/dec/eh2_dec_ib_ctl.sv:L370-L383``）：

.. code-block:: systemverilog

   assign lsu_in = (write_i0_ib0 & ifu_i0_predecode.lsu) |
                   (shift_ib1_ib0 & ib1.predecode.lsu) |
                   (shift_ib2_ib0 & ib2.predecode.lsu) |
                   (~write_i0_ib0 & ~shift_ib1_ib0 & ~shift_ib2_ib0 & ib0.predecode.lsu);
   
   assign mul_in = (write_i0_ib0 & ifu_i0_predecode.mul) |
                   (shift_ib1_ib0 & ib1.predecode.mul) |
                   (shift_ib2_ib0 & ib2.predecode.mul) |
                   (~write_i0_ib0 & ~shift_ib1_ib0 & ~shift_ib2_ib0 & ib0.predecode.mul);
   
   assign i0_only_in = (write_i0_ib0 & ifu_i0_predecode.i0_only) |
                       (shift_ib1_ib0 & ib1.predecode.i0_only) |
                       (shift_ib2_ib0 & ib2.predecode.i0_only) |
                       (~write_i0_ib0 & ~shift_ib1_ib0 & ~shift_ib2_ib0 & ib0.predecode.i0_only);

**逐段解释** ：

* 第 L370-L373 行：``lsu_in`` 优先使用写入 IB0 的新 i0 predecode；如果 IB1/IB2 正在
  shift 到 IB0，则改用对应队列项；都没有时使用当前 IB0 的 predecode。
* 第 L375-L378 行：``mul_in`` 采用与 LSU 相同的来源选择，只是读取 ``mul`` 位。
* 第 L380-L383 行：``i0_only_in`` 采用相同来源选择，读取 ``i0_only`` 位。

**接口关系** ：

* **被调用** ：每个 thread 的 ``eh2_dec_ib_ctl`` 实例产生这些信号。
* **调用** ：无函数调用；组合逻辑。
* **共享状态** ：``write_i0_ib0``、``shift_ib1_ib0``、``shift_ib2_ib0``、
  ``ifu_i0_predecode``、``ib1.predecode``、``ib2.predecode``、``ib0.predecode``。

**关键代码** （``rtl/design/dec/eh2_dec_ib_ctl.sv:L387-L402``）：

.. code-block:: systemverilog

   assign ib0_final = (i1_cancel_e1) ? ibsave : ib0_in;
   
   assign ib0_final_in = (ibwrite[0]) ? ib0_final : ib0;
   
   rvdffibie #(.WIDTH($bits(eh2_ib_pkt_t)),.LEFT(24),.PADLEFT(13),.MIDDLE(31),.PADRIGHT(47),.RIGHT(16)) ib0ff (.*, .en(ibwrite[0]), .din(ib0_final), .dout(ib0));
   
   assign i0_cinst_d[15:0] = ib0.cinst;
   
   assign i1_cinst_d[15:0] = ib1.cinst;
   
   assign i0_predecode = ib0.predecode;
   assign i1_predecode = ib1.predecode;
   
   assign  ib0_lsu_in = lsu_in;
   assign  ib0_mul_in = mul_in;
   assign  ib0_i0_only_in = i0_only_in;

**逐段解释** ：

* 第 L387-L391 行：``ib0`` 的最终写入值经过 i1 cancel 选择，再由 ``rvdffibie`` 保存。
* 第 L393-L398 行：IB0/IB1 的 compressed instruction 和 predecode 输出给 decode。
* 第 L400-L402 行：``lsu_in``、``mul_in``、``i0_only_in`` 被导出为 ``ib0_*`` 信号，供
  ``eh2_dec`` 聚合到 thread 维度。

**接口关系** ：

* **被调用** ：``eh2_dec`` 的 per-thread IB 实例。
* **调用** ：``rvdffibie``。
* **共享状态** ：``ib0``、``ib1``、``ibsave``、``ibwrite`` 和导出的 ``ib0_*`` 摘要。

§3.6  ``thread_stall_in`` 与 ``force_favor_flip`` 的来源
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_dec_decode_ctl`` 根据当前 decode 情况生成 thread stall 和强制 favor
翻转信号。前者用于过滤仲裁 ready，后者用于在 i1 路径不可用时调整 favor。

**关键代码** （``rtl/design/dec/eh2_dec_decode_ctl.sv:L1721-L1735``）：

.. code-block:: systemverilog

   for (genvar i=0; i<pt.NUM_THREADS; i++) begin
      assign dec_thread_stall_in[i] =
                                     // exact 1 cycle stall
                                      (i0_valid_d & i0_mul_block_thread_1cycle_d & (dd.i0tid==i)) |
                                      (i1_valid_d & i1_mul_block_thread_1cycle_d & (dd.i1tid==i) & (dd.i0tid!=dd.i1tid)) |
   
                                     // exact 1 cycle stall
                                      (i0_valid_d & i0_secondary_stall_thread_1cycle_d & (dd.i0tid==i)) |
                                      (i0_valid_d & i0_secondary_block_thread_1cycle_d & (dd.i0tid==i)) |
                                      (i1_valid_d & i1_secondary_block_thread_1cycle_d & (dd.i1tid==i) & (dd.i0tid!=dd.i1tid)) |
   
                                     // exact 2 cycle stall
                                      smt_secondary_stall[i]           |
   
                                      smt_csr_write_stall_in[i]        |

**逐段解释** ：

* 第 L1721-L1722 行：``dec_thread_stall_in`` 按 ``pt.NUM_THREADS`` generate，每个
  thread 有一个独立 stall 输入。
* 第 L1723-L1730 行：1-cycle stall 条件来自 MUL blocking 和 secondary stall/block，
  并通过 ``dd.i0tid`` 或 ``dd.i1tid`` 判断属于哪个 thread。
* 第 L1732-L1735 行：2-cycle secondary stall 和 CSR write stall 也进入同一 per-thread
  stall 汇总。

**接口关系** ：

* **被调用** ：``eh2_dec`` 将该输出接到 ``rvarbiter2_smt.thread_stall_in``。
* **调用** ：无函数调用；组合逻辑。
* **共享状态** ：``dd.i0tid``、``dd.i1tid``、MUL stall、secondary stall、CSR stall。

**关键代码** （``rtl/design/dec/eh2_dec_decode_ctl.sv:L2018-L2024``）：

.. code-block:: systemverilog

   assign dec_i1_decode_d = (dd.i0tid==dd.i1tid) ? (dec_i0_decode_d & i0_legal_except_csr & i1_valid_d & i1_legal & ~i1_block_d & ~flush_lower_wb[dd.i1tid] & ~flush_final_e3[dd.i1tid]) :
                                                   (                  i0_legal_except_csr & i1_valid_d & i1_legal & ~i1_block_d & ~flush_lower_wb[dd.i1tid] & ~flush_final_e3[dd.i1tid]);
   
   
   assign i1_legal_decode_d = dec_i1_decode_d & i1_legal;
   
   assign dec_force_favor_flip_d = i0_valid_d & i1_valid_d & (dd.i0tid ^ dd.i1tid) & (~i1_legal | i1_icaf_d | leak1_i1_stall[dd.i1tid] | dec_i1_debug_valid_d);  // force favor bit flip

**逐段解释** ：

* 第 L2018-L2019 行：i1 decode 允许条件取决于 i0/i1 是否来自同一 thread。如果是同一
  thread，则 i1 必须等待 i0 decode 成功。
* 第 L2022 行：``i1_legal_decode_d`` 是 i1 decode 与 legal 的合取结果。
* 第 L2024 行：当 i0/i1 来自不同 thread 且 i1 不合法、ICAF、leak stall 或 debug valid
  时，``dec_force_favor_flip_d`` 置位，促使仲裁 favor 翻转。

**接口关系** ：

* **被调用** ：``eh2_dec`` 将 ``dec_force_favor_flip_d`` 接到 ``rvarbiter2_smt``。
* **调用** ：无函数调用。
* **共享状态** ：``dd.i0tid``、``dd.i1tid``、``i1_legal``、``i1_icaf_d``、
  ``leak1_i1_stall``、``dec_i1_debug_valid_d``。

§4  thread CSR：``MHARTSTART``、``MNMIPDEL`` 与读数据 mux
--------------------------------------------------------------------------------

§4.1  ``MHARTSTART`` 对 thread 1 的启动位
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_dec_tlu_top.sv`` 定义 ``MHARTSTART`` CSR。代码注释说明 bit 1 用于
start thread 1，bit 0 对应 thread 0，并复位为 1。当前参数为 1 时，thread 1 的
``mhartstart_ns[1]`` 被硬连为 0。

**关键代码** （``rtl/design/dec/eh2_dec_tlu_top.sv:L838-L852``）：

.. code-block:: systemverilog

   // MHARTSTART (Write 1 only)
   // [31:2] : Reserved
   // [1]    : Start thread 1
   // [0]    : Start thread 0 (Resets to 0x1)
   localparam MHARTSTART    = 12'h7fc;
   
   assign wr_mhartstart_wb = dec_i0_csr_wen_wb_mod_thr[i0tid_wb] & (dec_i0_csr_wraddr_wb[11:0] == MHARTSTART);
   
   if (pt.NUM_THREADS > 1)
     assign mhartstart_ns[1] =  wr_mhartstart_wb ? (dec_i0_csr_wrdata_wb[1] | mhartstart[1]) : mhartstart[1];
   else
     assign mhartstart_ns[1] =  'b0;
   
   rvdff #(1)  mhartstart_ff (.*, .clk(active_clk), .din(mhartstart_ns[1]), .dout(mhartstart[1]));
   assign mhartstart[0] = 1'b1;

**逐段解释** ：

* 第 L838-L842 行：注释与 ``localparam`` 给出 CSR 地址 ``12'h7fc``，并描述 bit 1/0 的
  thread 含义。
* 第 L844 行：只有 i0 CSR 写使能有效且地址命中 ``MHARTSTART`` 时，写入才生效。
* 第 L846-L849 行：``pt.NUM_THREADS > 1`` 时，bit 1 是 write-1 sticky；否则 bit 1
  固定为 0。
* 第 L851-L852 行：``mhartstart[1]`` 通过 flop 保存，``mhartstart[0]`` 固定为 1。

**接口关系** ：

* **被调用** ：TLU CSR 写回路径。
* **调用** ：``rvdff`` 保存 ``mhartstart[1]``。
* **共享状态** ：``dec_i0_csr_wen_wb_mod_thr``、``i0tid_wb``、``dec_i0_csr_wraddr_wb``、
  ``dec_i0_csr_wrdata_wb``、``mhartstart``。

§4.2  ``MNMIPDEL`` 在单线程配置下忽略写入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``MNMIPDEL`` 控制 NMI pin delegation。代码在 ``pt.NUM_THREADS == 1`` 时
直接忽略该 CSR 写入，在多线程配置下拒绝全 0 写入。

**关键代码** （``rtl/design/dec/eh2_dec_tlu_top.sv:L855-L871``）：

.. code-block:: systemverilog

   // MNMIPDEL (Legal values: 01, 10, 11.
   // [31:2] : Reserved
   // [1]    : Delegate NMI pin to thread 1
   // [0]    : Delegate NMI pin to thread 0 (Resets to 0x1)
   localparam MNMIPDEL      = 12'h7fe;
   
   assign wr_mnmipdel_wb = dec_i0_csr_wen_wb_mod_thr[i0tid_wb] & (dec_i0_csr_wraddr_wb[11:0] == MNMIPDEL);
   
   if(pt.NUM_THREADS == 1)
     assign ignore_mnmipdel_wr = 1'b1;
   else
     assign ignore_mnmipdel_wr = &(~dec_i0_csr_wrdata_wb[1:0]);
   
   assign mnmipdel_ns[1:0] =  (wr_mnmipdel_wb & ~ignore_mnmipdel_wr) ? dec_i0_csr_wrdata_wb[1:0] : mnmipdel[1:0];
   
   rvdff #(2)  mnmipdel_ff (.*, .clk(active_clk), .din({mnmipdel_ns[1], ~mnmipdel_ns[0]}), .dout({mnmipdel[1], mnmipdel0_b}));
   assign mnmipdel[0] = ~mnmipdel0_b;

**逐段解释** ：

* 第 L855-L859 行：注释说明 bit 1/0 分别委派 NMI pin 到 thread 1 和 thread 0。
* 第 L861 行：写使能同样由 i0 CSR 写回路径和地址命中产生。
* 第 L863-L866 行：单线程配置无条件忽略写入；多线程配置只在写入值不是 ``2'b00`` 时
  接受。
* 第 L868-L871 行：``mnmipdel`` 通过 flop 保存，其中 bit 0 以反相信号 ``mnmipdel0_b``
  存储再反相输出。

**接口关系** ：

* **被调用** ：TLU CSR 写回路径。
* **调用** ：``rvdff`` 保存 delegation 状态。
* **共享状态** ：``dec_i0_csr_wen_wb_mod_thr``、``i0tid_wb``、``dec_i0_csr_wraddr_wb``、
  ``dec_i0_csr_wrdata_wb``、``mnmipdel``。

§4.3  thread CSR 读数据 mux 与 ``mhartnums``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TLU 根据 ``pt.NUM_THREADS`` 选择 thread CSR 读数据 mux，并给 ``mhartnums``
返回当前 hart 数编码。

**关键代码** （``rtl/design/dec/eh2_dec_tlu_top.sv:L874-L883``）：

.. code-block:: systemverilog

   // Thread mux, if required
   if (pt.NUM_THREADS > 1) begin: tlutop
      assign thread_csr_data_d[31:0] = ( ({32{~dec_i0_tid_d}} & csr_rddata_d[0]) |
                                         ({32{ dec_i0_tid_d}} & csr_rddata_d[1]) );
      assign mhartnums[1:0] = 2'b10;
   end
   else begin
      assign thread_csr_data_d[31:0] =  csr_rddata_d[dec_i0_tid_d];
      assign mhartnums[1:0] = 2'b01;
   end

**逐段解释** ：

* 第 L874-L879 行：多线程配置下，``thread_csr_data_d`` 根据 ``dec_i0_tid_d`` 在
  ``csr_rddata_d[0]`` 和 ``csr_rddata_d[1]`` 之间选择，并把 ``mhartnums`` 设为
  ``2'b10``。
* 第 L880-L883 行：单线程配置下，读数据直接来自 ``csr_rddata_d[dec_i0_tid_d]``，并把
  ``mhartnums`` 设为 ``2'b01``。

**接口关系** ：

* **被调用** ：CSR read data mux。
* **调用** ：无函数调用；条件生成与组合选择。
* **共享状态** ：``dec_i0_tid_d``、``csr_rddata_d``、``thread_csr_data_d``、
  ``mhartnums``。

**关键代码** （``rtl/design/dec/eh2_dec_tlu_top.sv:L887-L903``）：

.. code-block:: systemverilog

   assign dec_i0_csr_rddata_d[31:0] = ( // global csrs
                                     ({32{tlu_i0_csr_pkt_d.csr_misa}}       & ((pt.ATOMIC_ENABLE==0)?32'h40001104:32'h40001105)) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mvendorid}}  & 32'h00000045) |
                                     ({32{tlu_i0_csr_pkt_d.csr_marchid}}    & 32'h00000011) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mimpid}}     & 32'h3) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mhartnum}}   & {30'h0, mhartnums[1:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mrac}}       & mrac[31:0]) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mcgc}}       & {22'b0, mcgc[9:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mfdc}}       & {13'b0, mfdc[18:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_micect}}     & {micect[31:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_miccmect}}   & {miccmect[31:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mdccmect}}   & {mdccmect[31:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mfdht  }}    & {26'b0, mfdht[5:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mhartstart}} & {30'b0, mhartstart[1:0]}) |
                                     ({32{tlu_i0_csr_pkt_d.csr_mnmipdel}}   & {30'b0, mnmipdel[1:0]}) |
                                     // threaded csrs
                                     ({32{~tlu_i0_csr_pkt_d.glob}} & thread_csr_data_d[31:0])

**逐段解释** ：

* 第 L887-L892 行：global CSR read data 包含 ``misa``、vendor/arch/imp ID 和
  ``csr_mhartnum``。``csr_mhartnum`` 返回 ``mhartnums``。
* 第 L893-L901 行：global CSR read data 还包含 ``mrac``、clock/control、ECC threshold、
  ``mfdht``、``MHARTSTART`` 与 ``MNMIPDEL``。
* 第 L902-L903 行：当 CSR packet 不是 global CSR 时，读数据来自前一节生成的
  ``thread_csr_data_d``。

**接口关系** ：

* **被调用** ：CSR decode/readback path。
* **调用** ：无函数调用。
* **共享状态** ：``tlu_i0_csr_pkt_d``、``mhartnums``、``mhartstart``、``mnmipdel``、
  ``thread_csr_data_d``。

§5  trace 与 TB：端口参数化，但当前 monitor 只发 ``thread_id=0``
--------------------------------------------------------------------------------

§5.1  ``eh2_trace_intf`` 的 thread 维度
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_trace_intf`` 把 DUT trace ports 建模成 ``NUM_THREADS`` 维数组，每个
thread 携带两个 slot 的 instruction、PC、valid、exception、interrupt 和写回视图。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L19-L37``）：

.. code-block:: systemverilog

   interface eh2_trace_intf #(
     parameter NUM_THREADS = 1
   )(
     input logic clk,
     input logic rst_n
   );
   
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

**逐段解释** ：

* 第 L19-L24 行：interface 参数 ``NUM_THREADS`` 默认值为 1，端口只有 ``clk`` 和
  ``rst_n``。
* 第 L27-L33 行：指令、地址、valid、exception、ecause、interrupt 和 tval 全部带
  ``[NUM_THREADS-1:0]`` 维度。
* 第 L35-L37 行：验证专用写回视图也按 thread 展开；每个 thread 的两个 slot 共用
  2-bit valid、10-bit rd 地址和 64-bit 写回数据。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top.sv`` 实例化该 interface。
* **调用** ：无函数调用；interface 声明。
* **共享状态** ：DUT trace ports 与 UVM trace monitor 共享该 virtual interface。

§5.2  convenience decode 只展开 thread 0
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：虽然 ``eh2_trace_intf`` 的原始数组按 ``NUM_THREADS`` 维度定义，但 convenience
信号只解码 thread 0 的 i0/i1 两个 slot。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L39-L78``，节选）：

.. code-block:: systemverilog

     // Decoded per-instruction signals (convenience)
     // For thread 0, instruction 0 (i0)
     logic [31:0] t0_i0_pc;
     logic [31:0] t0_i0_insn;
     logic        t0_i0_valid;
     logic        t0_i0_exception;
     logic [4:0]  t0_i0_ecause;
     logic        t0_i0_wb_valid;
     logic [4:0]  t0_i0_wb_addr;
     logic [31:0] t0_i0_wb_data;
   
     // For thread 0, instruction 1 (i1)
     logic [31:0] t0_i1_pc;
     logic [31:0] t0_i1_insn;
     logic        t0_i1_valid;
     logic        t0_i1_exception;
     logic [4:0]  t0_i1_ecause;
     logic        t0_i1_wb_valid;
     logic [4:0]  t0_i1_wb_addr;
     logic [31:0] t0_i1_wb_data;

**逐段解释** ：

* 第 L39-L48 行：i0 convenience 信号名全部以 ``t0_i0`` 开头，来源限定为 thread 0。
* 第 L50-L58 行：i1 convenience 信号名全部以 ``t0_i1`` 开头，同样限定为 thread 0。
* 该片段没有定义 ``t1_i0`` 或 ``t1_i1`` convenience 信号。因此后续 monitor 若只使用
  convenience 信号，就只能采集 thread 0。

**接口关系** ：

* **被调用** ：``eh2_trace_monitor`` 使用这些 convenience 信号。
* **调用** ：无函数调用。
* **共享状态** ：``address[0]``、``insn[0]``、``valid[0]``、``rd_valid[0]``、
  ``rd_addr[0]``、``rd_wdata[0]``。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L60-L78``）：

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

**逐段解释** ：

* 第 L61-L68 行：i0 convenience 信号全部从数组索引 ``[0]`` 读取。
* 第 L70-L77 行：i1 convenience 信号也全部从数组索引 ``[0]`` 读取，只是选择 64-bit
  packed lane 的高半部分。

**接口关系** ：

* **被调用** ：``eh2_trace_monitor.monitor_trace``。
* **调用** ：无函数调用。
* **共享状态** ：thread 0 trace array lanes。

§5.3  ``eh2_trace_monitor`` 的 virtual interface 类型固定为 1 thread
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当前 monitor 声明的 virtual interface 是 ``eh2_trace_intf #(.NUM_THREADS(1))``。
这意味着本 monitor 的类型签名与单线程 trace interface 绑定。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L18-L20``）：

.. code-block:: systemverilog

     // Virtual interfaces
     virtual eh2_trace_intf #(.NUM_THREADS(1)) vif;
     virtual eh2_dut_probe_if probe_vif;

**逐段解释** ：

* 第 L18 行：注释说明这里是 virtual interface 声明区。
* 第 L19 行：``vif`` 的参数显式写成 ``NUM_THREADS(1)``，不是从 ``RV_NUM_THREADS`` 或
  配置对象传入。
* 第 L20 行：``probe_vif`` 是 DUT probe interface，用于补充 debug/NMI/mcycle 等状态，
  不改变 trace monitor 的 thread 采样范围。

**接口关系** ：

* **被调用** ：UVM config_db 向 ``trace_monitor`` 注入 virtual interface。
* **调用** ：monitor 后续通过 ``vif`` 读取 trace signal。
* **共享状态** ：``vif``、``probe_vif``。

§5.4  monitor 对 i0 slot 固定写入 ``thread_id=0``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``monitor_trace`` 在 thread 0 的 i0 valid 时创建 trace seq item，并把
``thread_id`` 写成 0。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L82-L108``）：

.. code-block:: systemverilog

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
           txn.wb_suppress = 0;
           txn.wb_source   = EH2_WB_SRC_REGULAR;
   
           // Sample interrupt/debug/NMI/mcycle state for Spike notification
           populate_cosim_state(txn);
   
           // Capture current wb_seq for async-wb correlation (issue 66)
           if (probe_vif != null) txn.wb_tag = probe_vif.wb_seq;

**逐段解释** ：

* 第 L82-L85 行：代码注释与赋值都明确指向 thread 0；``txn.thread_id`` 固定为 0。
* 第 L86-L94 行：i0 slot 的 PC、指令、异常、interrupt、tval、时间和 cycle count 都从
  ``t0_i0`` 或 ``[0][0]`` 读取。
* 第 L96-L101 行：写回视图来自 lane 0，source 固定为 ``EH2_WB_SRC_REGULAR``。
* 第 L103-L108 行：probe 状态与 ``wb_seq`` 作为 cosim 通知和异步写回匹配信息补充到
  同一个 trace pkt。

**接口关系** ：

* **被调用** ：``run_phase`` fork 出 ``monitor_trace``。
* **调用** ：``eh2_trace_seq_item::type_id::create``、``populate_cosim_state``、
  analysis port write。
* **共享状态** ：``vif``、``probe_vif``、``cycle_count``、``commit_count``。

§5.5  monitor 对 i1 slot 同样固定写入 ``thread_id=0``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``monitor_trace`` 在 thread 0 的 i1 valid 时创建第二个 trace seq item，slot
设为 1，但 ``thread_id`` 仍然固定为 0。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L129-L154``）：

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

**逐段解释** ：

* 第 L129-L133 行：i1 路径只改变 ``slot``，不改变 ``thread_id``。
* 第 L134-L142 行：i1 的 PC、指令、异常、interrupt、tval 和时间信息来自 ``t0_i1`` 或
  ``[0][1]``。
* 第 L143-L148 行：写回视图来自 lane 1。
* 第 L150-L154 行：cosim 状态采样与 ``wb_seq`` 捕获逻辑和 i0 路径一致。

**接口关系** ：

* **被调用** ：``monitor_trace``。
* **调用** ：``eh2_trace_seq_item::type_id::create``、``populate_cosim_state``、
  analysis port write。
* **共享状态** ：``vif``、``probe_vif``、``cycle_count``、``commit_count``。

§5.6  ``eh2_trace_seq_item`` 携带 ``thread_id``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：trace pkt 对象本身具备 ``thread_id`` 字段。scoreboard 后续按该字段路由，
但当前 trace monitor 只把该字段写成 0。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L7-L18``）：

.. code-block:: systemverilog

   class eh2_trace_seq_item extends uvm_sequence_item;
   
     // Thread ID
     rand bit thread_id;
   
     // Instruction slot (0 or 1 - EH2 can commit 2 per cycle)
     rand bit slot;
   
     // Instruction information
     bit [31:0] pc;
     bit [31:0] insn;

**逐段解释** ：

* 第 L7 行：trace pkt 是 ``uvm_sequence_item``。
* 第 L9-L10 行：``thread_id`` 是 pkt 的字段，类型为 1-bit random bit。
* 第 L12-L13 行：``slot`` 表示同一周期的 i0/i1 lane。
* 第 L16-L18 行：PC 和指令编码是每个 pkt 的基础退休信息。

**接口关系** ：

* **被调用** ：trace monitor 创建该对象，scoreboard 消费该对象。
* **调用** ：UVM object automation 宏注册字段。
* **共享状态** ：``thread_id`` 是 trace monitor、scoreboard 和 cosim DPI 的核心路由键。

§5.7  TB 顶层按 ``RV_NUM_THREADS`` 连接 trace interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB 顶层以 ``RV_NUM_THREADS`` 实例化 ``eh2_trace_intf``，并把 DUT trace ports
连接到 interface。这说明 TB 信号声明与端口连接具备参数化宽度。

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

**逐段解释** ：

* 第 L14-L21 行：DUT trace 信号按 ``RV_NUM_THREADS`` 展开，每个 thread 仍有两个 slot。
* 第 L22-L25 行：验证专用写回视图也按 ``RV_NUM_THREADS`` 展开。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top.sv`` include 该 signal 文件。
* **调用** ：无函数调用；信号声明。
* **共享状态** ：DUT wrapper ports、trace interface、RVFI converter 和 trace monitor。

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

**逐段解释** ：

* 第 L728-L732 行：TB 顶层以 ``RV_NUM_THREADS`` 参数实例化 trace interface。
* 第 L735-L744 行：DUT trace arrays 直接赋给 interface arrays，未在这里丢弃 thread
  维度。

**接口关系** ：

* **被调用** ：UVM TB elaboration。
* **调用** ：实例化 ``eh2_trace_intf``。
* **共享状态** ：``core_clk``、``rst_l``、DUT trace arrays、``trace_intf``。

§5.8  RVFI converter 当前只接 thread 0 trace
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB 顶层的 RVFI converter 使用 ``trace_rv_i_*[0]``，因此该转换路径当前只消费
thread 0 trace。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L771-L785``）：

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

**逐段解释** ：

* 第 L771-L773 行：RVFI converter 实例接入 TB 时钟和复位。
* 第 L776-L785 行：所有 trace 输入都从数组索引 ``[0]`` 读取，覆盖 instruction、PC、
  valid、exception、interrupt、tval 和写回视图。

**接口关系** ：

* **被调用** ：TB 顶层实例化。
* **调用** ：实例化 ``eh2_veer_wrapper_rvfi``。
* **共享状态** ：thread 0 trace arrays、LSU bus 派生信号和 RVFI interface。

§6  LEC wrapper：按 ``pt.NUM_THREADS`` 展平 trace 与控制端口
--------------------------------------------------------------------------------

§6.1  顶层端口宽度使用 ``pt.NUM_THREADS``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_veer_lec_pack`` 是 LEC-only wrapper。它把 2D packed-array trace 端口展平
为 1D 端口，同时保留内部 ``eh2_veer`` 实例不变。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L1-L10``）：

.. code-block:: systemverilog

   // LEC-ONLY wrapper. Not for simulation and not for production synthesis.
   // Old Formality O-2018.06-SP1 mishandles selected 2D packed-array top ports.
   // This wrapper exposes the trace/RVFI-style outputs as 1D vectors while keeping
   // the inner eh2_veer instance unchanged.
   
   module eh2_veer_lec_pack
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (

**逐段解释** ：

* 第 L1-L4 行：文件头限定该 wrapper 只用于 LEC，不用于 simulation 或 production
  synthesis；展平原因是旧 Formality 对 2D packed-array top ports 的处理限制。
* 第 L6-L10 行：模块导入 ``eh2_pkg`` 并 include ``eh2_param.vh``，因此端口宽度来自当前
  ``pt`` 参数。

**接口关系** ：

* **被调用** ：LEC flow 使用该 wrapper。
* **调用** ：内部实例化 ``eh2_veer``。
* **共享状态** ：``pt.NUM_THREADS``、trace 2D arrays、flat trace outputs。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L22-L45``）：

.. code-block:: systemverilog

      output logic [pt.NUM_THREADS*64-1:0] trace_rv_i_insn_ip_flat,
      output logic [pt.NUM_THREADS*64-1:0] trace_rv_i_address_ip_flat,
      output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_valid_ip_flat,
      output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_exception_ip_flat,
      output logic [pt.NUM_THREADS*5-1:0]  trace_rv_i_ecause_ip_flat,
      output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_interrupt_ip_flat,
      output logic [pt.NUM_THREADS*32-1:0] trace_rv_i_tval_ip_flat,
      output logic [pt.NUM_THREADS*2-1:0]  trace_rv_i_rd_valid_ip_flat,
      output logic [pt.NUM_THREADS*10-1:0] trace_rv_i_rd_addr_ip_flat,
      output logic [pt.NUM_THREADS*64-1:0] trace_rv_i_rd_wdata_ip_flat,
   
      output logic                 dccm_clk_override,
      output logic                 icm_clk_override,
      output logic                 dec_tlu_core_ecc_disable,
      output logic                 btb_clk_override,
   
      output logic [pt.NUM_THREADS-1:0] dec_tlu_mhartstart,
   
      input logic  [pt.NUM_THREADS-1:0] i_cpu_halt_req,
      input logic  [pt.NUM_THREADS-1:0] i_cpu_run_req,
      output logic [pt.NUM_THREADS-1:0] o_cpu_halt_status,
      output logic [pt.NUM_THREADS-1:0] o_cpu_halt_ack,
      output logic [pt.NUM_THREADS-1:0] o_cpu_run_ack,
      output logic [pt.NUM_THREADS-1:0] o_debug_mode_status,

**逐段解释** ：

* 第 L22-L31 行：trace flat outputs 的位宽全部是 ``pt.NUM_THREADS`` 乘以每个 thread
  的元素宽度。
* 第 L38 行：``dec_tlu_mhartstart`` 仍保留 thread 维度。
* 第 L40-L45 行：halt/run/debug status 端口都按 ``pt.NUM_THREADS`` 展开。

**接口关系** ：

* **被调用** ：LEC top wrapper 端口。
* **调用** ：无函数调用。
* **共享状态** ：LEC 对比点、trace flat outputs、halt/run/debug control signals。

§6.2  trace 2D arrays 到 flat outputs 的映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：wrapper 内部先声明 2D trace arrays，再用 ``for (genvar tid = 0; tid <
pt.NUM_THREADS; tid++)`` 按 thread 展平到 flat outputs。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L365-L387``）：

.. code-block:: systemverilog

      logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_insn_ip_2d;
      logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_address_ip_2d;
      logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_valid_ip_2d;
      logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_exception_ip_2d;
      logic [pt.NUM_THREADS-1:0] [4:0]  trace_rv_i_ecause_ip_2d;
      logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_interrupt_ip_2d;
      logic [pt.NUM_THREADS-1:0] [31:0] trace_rv_i_tval_ip_2d;
      logic [pt.NUM_THREADS-1:0] [1:0]  trace_rv_i_rd_valid_ip_2d;
      logic [pt.NUM_THREADS-1:0] [9:0]  trace_rv_i_rd_addr_ip_2d;
      logic [pt.NUM_THREADS-1:0] [63:0] trace_rv_i_rd_wdata_ip_2d;
   
      for (genvar tid = 0; tid < pt.NUM_THREADS; tid++) begin : gen_trace_flatten
         assign trace_rv_i_insn_ip_flat[tid*64 +: 64]     = trace_rv_i_insn_ip_2d[tid];
         assign trace_rv_i_address_ip_flat[tid*64 +: 64]  = trace_rv_i_address_ip_2d[tid];
         assign trace_rv_i_valid_ip_flat[tid*2 +: 2]      = trace_rv_i_valid_ip_2d[tid];
         assign trace_rv_i_exception_ip_flat[tid*2 +: 2]  = trace_rv_i_exception_ip_2d[tid];
         assign trace_rv_i_ecause_ip_flat[tid*5 +: 5]     = trace_rv_i_ecause_ip_2d[tid];
         assign trace_rv_i_interrupt_ip_flat[tid*2 +: 2]  = trace_rv_i_interrupt_ip_2d[tid];
         assign trace_rv_i_tval_ip_flat[tid*32 +: 32]     = trace_rv_i_tval_ip_2d[tid];
         assign trace_rv_i_rd_valid_ip_flat[tid*2 +: 2]   = trace_rv_i_rd_valid_ip_2d[tid];
         assign trace_rv_i_rd_addr_ip_flat[tid*10 +: 10]  = trace_rv_i_rd_addr_ip_2d[tid];
         assign trace_rv_i_rd_wdata_ip_flat[tid*64 +: 64] = trace_rv_i_rd_wdata_ip_2d[tid];
      end

**逐段解释** ：

* 第 L365-L374 行：内部 trace arrays 保留 ``[pt.NUM_THREADS-1:0]`` 维度。
* 第 L376 行：generate 循环按 ``tid`` 从 0 到 ``pt.NUM_THREADS-1`` 展开。
* 第 L377-L386 行：每个 thread 的 2D trace array 被切片赋给对应 flat output 区间，
  例如 instruction/address 用 ``tid*64 +: 64``，valid/exception/interrupt 用
  ``tid*2 +: 2``。

**接口关系** ：

* **被调用** ：LEC wrapper elaboration。
* **调用** ：无函数调用；generate 赋值。
* **共享状态** ：``tid``、2D trace arrays、flat trace outputs。

§6.3  内部 ``eh2_veer`` 仍接 2D arrays
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：wrapper 只改变 LEC 顶层端口形状；内部 ``eh2_veer`` 继续接收原始 2D trace
arrays。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L389-L401``）：

.. code-block:: systemverilog

      eh2_veer u_inner (
         .trace_rv_i_insn_ip(trace_rv_i_insn_ip_2d),
         .trace_rv_i_address_ip(trace_rv_i_address_ip_2d),
         .trace_rv_i_valid_ip(trace_rv_i_valid_ip_2d),
         .trace_rv_i_exception_ip(trace_rv_i_exception_ip_2d),
         .trace_rv_i_ecause_ip(trace_rv_i_ecause_ip_2d),
         .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip_2d),
         .trace_rv_i_tval_ip(trace_rv_i_tval_ip_2d),
         .trace_rv_i_rd_valid_ip(trace_rv_i_rd_valid_ip_2d),
         .trace_rv_i_rd_addr_ip(trace_rv_i_rd_addr_ip_2d),
         .trace_rv_i_rd_wdata_ip(trace_rv_i_rd_wdata_ip_2d),
         .*
      );

**逐段解释** ：

* 第 L389 行：内部实例名是 ``u_inner``，模块为 ``eh2_veer``。
* 第 L390-L399 行：trace/RVFI-style outputs 全部连接到 2D arrays，而不是 flat outputs。
* 第 L400-L401 行：其余端口使用 ``.*`` 连接。

**接口关系** ：

* **被调用** ：LEC wrapper 实例化内部 DUT。
* **调用** ：``eh2_veer``。
* **共享状态** ：trace 2D arrays、其他同名端口。

§7  cosim 多 hart 支撑：ADR、DPI 与 ``SpikeCosim``
--------------------------------------------------------------------------------

§7.1  ADR-0016 的决策边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：ADR-0016 记录了 ``NUM_THREADS=2`` cosim 支持路径，明确多 hart Spike、DPI
``thread_id`` 路由和 scoreboard per-thread 队列。

**关键代码** （``docs/adr/0016-multi-hart-cosim.md:L11-L18``）：

.. code-block:: bash

   ## 决策
   
   1. SpikeCosim 创建 2 个 processor_t 实例（当 num_threads==2）
   2. 每个 hart 独立维护：processor state、pending_dside_accesses、mip/prev_mip
   3. DPI 接口通过 thread_id 参数路由到对应 hart
   4. scoreboard 按 trace_seq_item.thread_id 路由到对应比对路径
   5. 每个 hart 独立维护 pending_trace_q 和 async_wb_q

**逐段解释** ：

* 第 L11-L13 行：ADR 决策要求 ``num_threads==2`` 时创建两个 Spike ``processor_t``。
* 第 L14 行：每个 hart 有独立 processor state、pending dside accesses 和 mip 状态。
* 第 L15-L18 行：DPI 与 scoreboard 都以 ``thread_id`` 为路由键，且每个 hart 有独立
  ``pending_trace_q`` 和 ``async_wb_q``。

**接口关系** ：

* **被调用** ：本章引用 ADR-0016 解释 cosim 支撑面。
* **调用** ：ADR 不调用代码；对应实现落在 ``spike_cosim.*``、``cosim_dpi.*`` 和
  ``eh2_cosim_scoreboard.sv``。
* **共享状态** ：``thread_id``、``num_threads``、``processor_t``、``pending_trace_q``、
  ``async_wb_q``。

**关键代码** （``docs/adr/0016-multi-hart-cosim.md:L25-L27``）：

.. code-block:: bash

   ### 负面
   - Spike 内存仍然共享（两个 hart 看同一个地址空间）
   - PIC 中断仲裁 Spike 不模型（每 hart 独立 set_mip）

**逐段解释** ：

* 第 L25-L27 行：ADR 同时限定了 cosim 模型边界：Spike memory 仍共享，PIC 仲裁不由
  Spike 模型化，而是每 hart 独立 ``set_mip``。

**接口关系** ：

* **被调用** ：本章 §8 的限制说明。
* **调用** ：无。
* **共享状态** ：共享 memory bus、per-hart interrupt pending 状态。

§7.2  C++ 抽象接口全部带 ``thread_id``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``Cosim`` 抽象类把 step、interrupt/debug、CSR、dside access、iside error、
instruction count 和 trap CSR query 都定义为带 ``thread_id`` 的接口。

**关键代码** （``dv/cosim/cosim.h:L49-L67``）：

.. code-block:: cpp

     // Step the co-simulator.
     //
     // write_reg: destination register index (0 = no write)
     // write_reg_data: data written to register
     // pc: program counter of the instruction
     // sync_trap: true if instruction caused synchronous trap
     // suppress_reg_write: true if register write was suppressed
     // thread_id: hardware thread (hart) index (0 or 1)
     //
     // Returns true if step succeeded (no mismatch).
     virtual bool step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
                       bool sync_trap, bool suppress_reg_write,
                       int thread_id = 0) = 0;
   
     // Set MIP (interrupt pending) with pre/post values.
     // pre_mip: value used to determine if interrupt is pending
     // post_mip: value observed by next instruction
     virtual void set_mip(uint32_t pre_mip, uint32_t post_mip,
                          int thread_id = 0) = 0;

**逐段解释** ：

* 第 L49-L58 行：``step`` 的注释列出寄存器写回、PC、同步 trap、写回抑制和
  ``thread_id`` 的语义。
* 第 L59-L61 行：``step`` 函数签名把 ``thread_id`` 作为最后一个参数，默认值为 0。
* 第 L63-L67 行：``set_mip`` 同样带 ``thread_id``，用于 per-hart interrupt pending
  同步。

**接口关系** ：

* **被调用** ：``cosim_dpi.cc`` 将 DPI-C 函数转调到该抽象接口。
* **调用** ：由具体实现 ``SpikeCosim`` 覆盖。
* **共享状态** ：``thread_id`` 是 C++ cosim 与 SV scoreboard 的共同路由键。

**关键代码** （``dv/cosim/cosim.h:L69-L104``，节选）：

.. code-block:: cpp

     // Set NMI state.
     virtual void set_nmi(bool nmi, int thread_id = 0) = 0;
   
     // Set NMI internal state.
     virtual void set_nmi_int(bool nmi_int, int thread_id = 0) = 0;
   
     // Set debug request.
     virtual void set_debug_req(bool debug_req, int thread_id = 0) = 0;
   
     // Set mcycle CSR value (full 64-bit).
     virtual void set_mcycle(uint64_t mcycle, int thread_id = 0) = 0;
   
     // Set a CSR value directly (for DUT-to-Spike synchronization).
     virtual void set_csr(const int csr_num, const uint32_t new_val,
                          int thread_id = 0) = 0;

**逐段解释** ：

* 第 L69-L79 行：NMI、NMI internal、debug request 和 mcycle sample 都按 ``thread_id``
  路由。
* 第 L81-L83 行：CSR 同步接口 ``set_csr`` 也按 ``thread_id`` 选择 hart。

**接口关系** ：

* **被调用** ：DPI wrappers 和 ``SpikeCosim``。
* **调用** ：具体实现访问 Spike processor state。
* **共享状态** ：per-hart NMI、debug、CSR 和 mcycle 采样路径。

§7.3  SystemVerilog DPI 声明显式传入 ``thread_id``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``cosim_dpi.svh`` 是 SystemVerilog 侧 import 声明。per-hart 函数都把
``thread_id`` 作为输入参数。

**关键代码** （``dv/cosim/cosim_dpi.svh:L25-L43``）：

.. code-block:: cpp

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
   
   // Set MIP (pre and post values)
   import "DPI-C" function void riscv_cosim_set_mip(
     input chandle handle,
     input int     pre_mip,
     input int     post_mip,
     input int     thread_id
   );

**逐段解释** ：

* 第 L25-L35 行：``riscv_cosim_step`` 的 SV import 参数末尾是 ``thread_id``。
* 第 L37-L43 行：``riscv_cosim_set_mip`` 同样把 ``thread_id`` 作为最后一个输入。

**接口关系** ：

* **被调用** ：``eh2_cosim_scoreboard.sv`` 调用这些 DPI 函数。
* **调用** ：链接到 ``cosim_dpi.cc`` 的 C wrapper。
* **共享状态** ：``cosim_handle``、writeback view、trap state、``thread_id``。

**关键代码** （``dv/cosim/cosim_dpi.svh:L81-L102``）：

.. code-block:: cpp

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
     input int     thread_id
   );

**逐段解释** ：

* 第 L81-L95 行：D-side access notification 把 store/data/addr/byte enable/error 等信息
  与 ``thread_id`` 一起传给 C++。
* 第 L97-L102 行：I-side error 设置也按 ``thread_id`` 路由。

**接口关系** ：

* **被调用** ：scoreboard memory notification 和 exception path。
* **调用** ：C wrapper ``riscv_cosim_notify_dside_access``、
  ``riscv_cosim_set_iside_error``。
* **共享状态** ：pending memory access、iside error state、``thread_id``。

§7.4  C wrapper 将 ``thread_id`` 直接转交给 ``Cosim``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``cosim_dpi.cc`` 是薄 C shim。它把 SV DPI 参数转换为 C++ 类型后，直接调用
``Cosim`` virtual methods，并传递 ``thread_id``。

**关键代码** （``dv/cosim/cosim_dpi.cc:L62-L92``，节选）：

.. code-block:: cpp

     // Step one instruction
     // Returns 1 on match, 0 on mismatch
     int riscv_cosim_step(void* handle, int write_reg, int write_reg_data,
                          int pc, int sync_trap, int suppress_reg_write,
                          int thread_id) {
       Cosim* cosim = static_cast<Cosim*>(handle);
       if (!cosim) {
         return 0;
       }
       try {
         int result = cosim->step(static_cast<uint32_t>(write_reg),
                                  static_cast<uint32_t>(write_reg_data),
                                  static_cast<uint32_t>(pc),
                                  sync_trap != 0,
                                  suppress_reg_write != 0,
                                  thread_id)
                    ? 1
                    : 0;
         return result;

**逐段解释** ：

* 第 L64-L67 行：DPI 函数签名接收 ``thread_id``，并把 ``handle`` 转为 ``Cosim*``。
* 第 L72-L79 行：``cosim->step`` 的最后一个实参就是 ``thread_id``，没有在 wrapper 中
  改写。

**接口关系** ：

* **被调用** ：SV DPI import ``riscv_cosim_step``。
* **调用** ：``Cosim::step``。
* **共享状态** ：``handle``、writeback fields、PC、trap state、``thread_id``。

**关键代码** （``dv/cosim/cosim_dpi.cc:L139-L162``）：

.. code-block:: cpp

     // Notify dside access
     void riscv_cosim_notify_dside_access(void* handle, int store, int data,
                                          int addr, int be, int error,
                                          int misaligned_first,
                                          int misaligned_second,
                                          int misaligned_first_saw_error,
                                          int m_mode_access,
                                          int widened_load,
                                          int thread_id) {
       Cosim* cosim = static_cast<Cosim*>(handle);
       if (cosim) {
         DSideAccessInfo info;
         info.store = (store != 0);
         info.data = static_cast<uint32_t>(data);
         info.addr = static_cast<uint32_t>(addr);
         info.be = static_cast<uint32_t>(be);
         info.error = (error != 0);
         info.misaligned_first = (misaligned_first != 0);
         info.misaligned_second = (misaligned_second != 0);
         info.misaligned_first_saw_error = (misaligned_first_saw_error != 0);
         info.m_mode_access = (m_mode_access != 0);
         info.widened_load = (widened_load != 0);
         cosim->notify_dside_access(info, thread_id);
       }

**逐段解释** ：

* 第 L140-L147 行：DPI wrapper 接收 memory access 的所有字段和 ``thread_id``。
* 第 L150-L160 行：wrapper 构造 ``DSideAccessInfo``，逐项填入 store/data/addr/be/error
  等字段。
* 第 L161 行：wrapper 调用 ``notify_dside_access`` 时把 ``thread_id`` 原样传入。

**接口关系** ：

* **被调用** ：SV scoreboard 的 memory notification。
* **调用** ：``Cosim::notify_dside_access``。
* **共享状态** ：``DSideAccessInfo``、``thread_id``。

§7.5  ``SpikeCosim`` 最大支持 2 个 processor
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``spike_cosim.h`` 定义 ``COSIM_MAX_THREADS`` 为 2，并在类成员中为 processor
和 per-thread state 各保留 2 个槽。

**关键代码** （``dv/cosim/spike_cosim.h:L24-L35``）：

.. code-block:: cpp

   // EH2 marchid value (VeeR EH2)
   #define EH2_MARCHID 0x56524545  // "VEER" in ASCII
   
   // Maximum number of hardware threads supported
   #define COSIM_MAX_THREADS 2
   
   class SpikeCosim : public simif_t, public Cosim {
   public:
     SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                uint32_t start_mtvec, const std::string &trace_log_path,
                uint32_t pmp_num_regions, uint32_t pmp_granularity,
                uint32_t mhpm_counter_num, int num_threads = 1);

**逐段解释** ：

* 第 L24-L25 行：``EH2_MARCHID`` 是 VeeR EH2 的 marchid 常量。
* 第 L27-L28 行：``COSIM_MAX_THREADS`` 被定义为 2。
* 第 L30-L35 行：``SpikeCosim`` 构造函数接收 ``num_threads``，默认值为 1。

**接口关系** ：

* **被调用** ：``riscv_cosim_init`` 创建 ``SpikeCosim``。
* **调用** ：继承 ``simif_t`` 和 ``Cosim``。
* **共享状态** ：``COSIM_MAX_THREADS``、``num_threads``。

**关键代码** （``dv/cosim/spike_cosim.h:L74-L88``）：

.. code-block:: cpp

   private:
     // Number of hardware threads (1 or 2)
     int num_threads;
   
     // Spike processor(s) and ISA
     std::unique_ptr<isa_parser_t> isa_parser;
     std::unique_ptr<processor_t> processors[COSIM_MAX_THREADS];
     std::unique_ptr<log_file_t> log;
   
     // Active thread for mmio callbacks (set before each step)
     int active_thread;
   
     // Memory bus (shared across threads — EH2 shares address space)
     bus_t bus;
     std::vector<std::unique_ptr<mem_t>> mems;

**逐段解释** ：

* 第 L75-L76 行：``num_threads`` 保存运行时启用的 hart 数。
* 第 L79-L81 行：``processors`` 是长度为 ``COSIM_MAX_THREADS`` 的 processor 指针数组。
* 第 L83-L84 行：``active_thread`` 用于 MMIO callback 判断当前由哪个 hart 触发访问。
* 第 L86-L88 行：memory bus 和 memory backing store 是类级共享成员，不按 hart 分裂。

**接口关系** ：

* **被调用** ：所有 ``SpikeCosim`` 成员函数。
* **调用** ：Spike ``processor_t`` 和 bus/memory 设施。
* **共享状态** ：``processors`` per-hart，``bus`` shared。

§7.6  per-thread state 保存 pending access、NMI 和 LR 预约
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``SpikeCosim`` 的 ``PerThreadState`` 保存每个 hart 的 NMI、pending dside
access、LR reservation 和最后 step PC 等状态。

**关键代码** （``dv/cosim/spike_cosim.h:L100-L125``）：

.. code-block:: cpp

     // Per-thread state
     struct PerThreadState {
       bool nmi_mode = false;
       bool pending_iside_error = false;
       uint32_t pending_iside_err_addr = 0;
       unsigned int insn_cnt = 0;
   
       // Mstack for NMI handling
       struct {
         uint8_t mpp = 0;
         bool mpie = false;
         uint32_t epc = 0;
         uint32_t cause = 0;
       } mstack;
   
       // Pending dside accesses from DUT
       std::vector<PendingMemAccess> pending_dside_accesses;
   
       // LR reservation tracking for atomic cosim (issue 52)
       uint32_t lr_reservation_addr = 0;
       bool lr_reservation_valid = false;
   
       // PC of last stepped instruction (for commit-log-free instr type checks)
       uint32_t last_step_pc = 0;
     };
     PerThreadState thread_state[COSIM_MAX_THREADS];

**逐段解释** ：

* 第 L101-L105 行：每个 thread 保存 NMI mode、pending iside error、error address 和
  matched instruction count。
* 第 L107-L113 行：``mstack`` 保存 NMI 相关 CSR 状态。
* 第 L115-L116 行：``pending_dside_accesses`` 是 per-thread vector。
* 第 L118-L123 行：LR reservation 和 last step PC 也属于 per-thread state。
* 第 L125 行：``thread_state`` 数组长度同样为 ``COSIM_MAX_THREADS``。

**接口关系** ：

* **被调用** ：``set_mip``、``set_nmi``、``notify_dside_access``、``step``、
  memory checking 和 atomic fixup。
* **调用** ：无函数调用；类型定义。
* **共享状态** ：每个 ``thread_id`` 对应一个 ``thread_state[thread_id]``。

§7.7  构造函数按 ``num_threads`` 创建 processor
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``SpikeCosim`` 构造函数检查线程数范围，并按 ``num_threads`` 循环创建 Spike
processor。

**关键代码** （``dv/cosim/spike_cosim.cc:L24-L53``）：

.. code-block:: cpp

   SpikeCosim::SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                          uint32_t start_mtvec, const std::string &trace_log_path,
                          uint32_t pmp_num_regions, uint32_t pmp_granularity,
                          uint32_t mhpm_counter_num, int num_threads)
       : num_threads(num_threads), active_thread(0) {
     assert(num_threads >= 1 && num_threads <= COSIM_MAX_THREADS);
   
     FILE *log_file = nullptr;
     if (trace_log_path.length() != 0) {
       log = std::make_unique<log_file_t>(trace_log_path.c_str());
       log_file = log->get();
     }
   
     isa_parser = std::make_unique<isa_parser_t>(isa_string.c_str(), "MU");
   
     for (int t = 0; t < num_threads; ++t) {
       processors[t] = std::make_unique<processor_t>(
           isa_parser.get(), DEFAULT_VARCH, this, t, false, log_file, std::cerr);
   
       processors[t]->set_pmp_num(pmp_num_regions);
       processors[t]->set_mhpm_counter_num(mhpm_counter_num);
       processors[t]->set_pmp_granularity(1 << (pmp_granularity + 2));
   
       initial_proc_setup(t, start_pc, start_mtvec, mhpm_counter_num);
   
       if (log) {
         processors[t]->set_debug(true);
         processors[t]->enable_log_commits();

**逐段解释** ：

* 第 L24-L29 行：构造函数保存 ``num_threads``，并断言范围在 1 到 ``COSIM_MAX_THREADS``
  之间。
* 第 L31-L37 行：可选创建 Spike commit log，并创建共享 ISA parser。
* 第 L39-L47 行：循环 ``t < num_threads`` 创建 processor，processor id 使用 ``t``，
  并设置 PMP、MHPM 和初始 PC/mtvec。
* 第 L49-L52 行：如果启用 log，则对每个 processor 打开 debug 和 commit log。

**接口关系** ：

* **被调用** ：``riscv_cosim_init``。
* **调用** ：Spike ``processor_t``、``initial_proc_setup``。
* **共享状态** ：``processors[t]``、``isa_parser``、``log``、``thread_state``。

§7.8  ``riscv_cosim_init`` 解析并夹紧 ``num_threads``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：DPI 初始化函数从 config string 解析 ``num_threads``，并把它限制到 1 到
``COSIM_MAX_THREADS`` 的范围内。

**关键代码** （``dv/cosim/spike_cosim.cc:L1608-L1623``）：

.. code-block:: cpp

   extern "C" void *riscv_cosim_init(const char *config) {
     // Parse config string: "isa=<ISA>;pc=<PC>;mtvec=<MTVEC>;pmp_regions=<N>;"
     //                       "pmp_granularity=<G>;mhpm_counters=<N>;trace=<PATH>"
     //                       ";num_threads=<N>"
     std::string config_str(config);
     // Default ISA string includes Zba/Zbb/Zbc/Zbs per default EH2 config.
     // If the config string contains ``isa=...`` the parsed value overrides this.
     std::string isa_string = "rv32imac_zba_zbb_zbc_zbs";
     uint32_t start_pc = 0;
     uint32_t start_mtvec = 0;
     uint32_t pmp_num_regions = 0;
     uint32_t pmp_granularity = 0;
     uint32_t mhpm_counter_num = 0;
     int num_threads = 1;
     std::string trace_log_path;

**逐段解释** ：

* 第 L1608-L1611 行：注释列出 config string 支持 ``num_threads=<N>``。
* 第 L1612-L1615 行：默认 ISA 是 ``rv32imac_zba_zbb_zbc_zbs``，可由 config 覆盖。
* 第 L1616-L1622 行：初始化 PC、mtvec、PMP、MHPM、``num_threads`` 和 trace log path
  的默认值；``num_threads`` 默认是 1。

**接口关系** ：

* **被调用** ：SV scoreboard 调用 ``riscv_cosim_init(cosim_config)``。
* **调用** ：后续创建 ``SpikeCosim``。
* **共享状态** ：``cosim_config`` string、``num_threads``。

**关键代码** （``dv/cosim/spike_cosim.cc:L1636-L1654``）：

.. code-block:: cpp

       if (key == "isa") isa_string = val;
       else if (key == "pc") start_pc = strtoul(val.c_str(), nullptr, 0);
       else if (key == "mtvec") start_mtvec = strtoul(val.c_str(), nullptr, 0);
       else if (key == "pmp_regions") pmp_num_regions = strtoul(val.c_str(), nullptr, 0);
       else if (key == "pmp_granularity") pmp_granularity = strtoul(val.c_str(), nullptr, 0);
       else if (key == "mhpm_counters") mhpm_counter_num = strtoul(val.c_str(), nullptr, 0);
       else if (key == "trace") trace_log_path = val;
       else if (key == "num_threads") num_threads = strtol(val.c_str(), nullptr, 0);
   
       pos = semi_pos + 1;
     }
   
     // Clamp num_threads to valid range
     if (num_threads < 1) num_threads = 1;
     if (num_threads > COSIM_MAX_THREADS) num_threads = COSIM_MAX_THREADS;
   
     SpikeCosim *cosim = new SpikeCosim(
         isa_string, start_pc, start_mtvec, trace_log_path,
         pmp_num_regions, pmp_granularity, mhpm_counter_num, num_threads);

**逐段解释** ：

* 第 L1636-L1643 行：parser 识别 ``isa``、``pc``、``mtvec``、PMP、MHPM、``trace`` 和
  ``num_threads`` 键。
* 第 L1648-L1650 行：``num_threads`` 小于 1 时夹紧为 1，大于 ``COSIM_MAX_THREADS`` 时
  夹紧为 ``COSIM_MAX_THREADS``。
* 第 L1652-L1654 行：最终 ``num_threads`` 被传给 ``SpikeCosim`` 构造函数。

**接口关系** ：

* **被调用** ：SV DPI 初始化。
* **调用** ：``new SpikeCosim``。
* **共享状态** ：``num_threads`` 与 ``COSIM_MAX_THREADS``。

§7.9  ``SpikeCosim::step`` 按 ``thread_id`` 选择 processor
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``step`` 是每条退休指令的 cosim 比对入口。它断言 ``thread_id`` 有效，选择
对应 processor 和 per-thread state，并在 Spike step 前设置 ``active_thread``。

**关键代码** （``dv/cosim/spike_cosim.cc:L303-L342``，节选）：

.. code-block:: cpp

   bool SpikeCosim::step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
                         bool sync_trap, bool suppress_reg_write,
                         int thread_id) {
     assert(write_reg < 32);
     assert(thread_id >= 0 && thread_id < num_threads);
   
     auto *proc = get_processor(thread_id);
     auto &ts = thread_state[thread_id];
   
     // First check if this is an ebreak that should enter debug mode. These need
     // specific handling. When spike steps over an ebreak entering debug mode it
     // immediately steps the next instruction (first instruction of debug handler)
     // too. To deal with this, skip the rest of the function for debug ebreaks.
     if (pc_is_debug_ebreak(thread_id, pc)) {
       check_debug_ebreak(thread_id, write_reg, pc, sync_trap);
       return errors.size() == 0;
     }
   
     uint32_t initial_spike_pc;
     uint32_t suppressed_write_reg;
     uint32_t suppressed_write_reg_data;
     bool pending_sync_exception = false;

**逐段解释** ：

* 第 L303-L307 行：``step`` 接收 ``thread_id``，并断言它处于当前 ``num_threads`` 范围内。
* 第 L309-L310 行：``get_processor(thread_id)`` 和 ``thread_state[thread_id]`` 将后续
  操作绑定到对应 hart。
* 第 L312-L319 行：debug ebreak 特殊路径同样按 ``thread_id`` 检查。
* 第 L321-L324 行：后续同步 trap 和写回抑制处理使用这些局部变量。

**接口关系** ：

* **被调用** ：``cosim_dpi.cc`` 的 ``riscv_cosim_step``。
* **调用** ：``get_processor``、``pc_is_debug_ebreak``、``check_debug_ebreak``。
* **共享状态** ：``processors[thread_id]``、``thread_state[thread_id]``、``errors``。

**关键代码** （``dv/cosim/spike_cosim.cc:L335-L355``）：

.. code-block:: cpp

     // Record current spike PC before stepping
     initial_spike_pc = (proc->get_state()->pc & 0xffffffff);
   
     ts.last_step_pc = pc;
   
     active_thread = thread_id;
     try {
       proc->step(1);
     } catch (const std::exception &e) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " Spike step exception at PC " << std::hex
               << initial_spike_pc << ": " << e.what();
       errors.emplace_back(err_str.str());
       return false;
     } catch (...) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " Spike unknown step exception at PC "
               << std::hex << initial_spike_pc;
       errors.emplace_back(err_str.str());
       return false;
     }

**逐段解释** ：

* 第 L335-L338 行：记录 Spike 当前 PC，并把 DUT PC 写入 per-thread ``last_step_pc``。
* 第 L340-L342 行：``active_thread`` 在 ``proc->step(1)`` 前设为当前 ``thread_id``，
  供 MMIO callback 使用。
* 第 L343-L355 行：Spike step 异常消息带 ``T<thread_id>``，错误记录进入共享
  ``errors`` vector。

**接口关系** ：

* **被调用** ：``SpikeCosim::step`` 内部。
* **调用** ：Spike ``processor_t::step``。
* **共享状态** ：``active_thread``、``thread_state[thread_id].last_step_pc``、``errors``。

§7.10  interrupt/debug/D-side 通知都按 thread 路由
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``SpikeCosim`` 的 interrupt、debug 和 dside access 方法都接收
``thread_id``，并访问对应 processor 或 per-thread state。

**关键代码** （``dv/cosim/spike_cosim.cc:L759-L784``）：

.. code-block:: cpp

   void SpikeCosim::set_mip(uint32_t pre_mip, uint32_t post_mip,
                            int thread_id) {
     auto *proc = get_processor(thread_id);
   
     uint32_t old_mip = proc->get_state()->mip->read();
   
     proc->get_state()->mip->write_with_mask(0xffffffff, post_mip);
     proc->get_state()->mip->write_pre_val(pre_mip);
   
     if (proc->get_state()->debug_mode ||
         (proc->halt_request == processor_t::HR_REGULAR) ||
         (!get_field(proc->get_csr(CSR_MSTATUS), MSTATUS_MIE) &&
          proc->get_state()->prv == PRV_M)) {
       return;
     }
   
     uint32_t old_enabled_irq = old_mip & proc->get_state()->mie->read();
     uint32_t new_enabled_irq = pre_mip & proc->get_state()->mie->read();
   
     // Trigger interrupt handling if new MIP produces an enabled interrupt for
     // the first time. Use pre_mip (the MIP value at the start of the instruction)
     // to determine if an interrupt should be taken, matching Ibex behavior.
     if ((old_enabled_irq == 0) && (new_enabled_irq != 0)) {
       early_interrupt_handle(thread_id);
     }

**逐段解释** ：

* 第 L759-L762 行：``set_mip`` 用 ``thread_id`` 取得对应 processor。
* 第 L763-L767 行：MIP 的 post/pre 值写入该 processor 的 state。
* 第 L768-L773 行：如果 processor 处于 debug、halt request 或 M-mode interrupt disabled
  条件，函数直接返回。
* 第 L775-L783 行：只有新 enabled interrupt 从无到有时，才对该 ``thread_id`` 调用
  ``early_interrupt_handle``。

**接口关系** ：

* **被调用** ：scoreboard 在 Spike step 前调用 ``riscv_cosim_set_mip``。
* **调用** ：``get_processor``、``early_interrupt_handle``。
* **共享状态** ：processor MIP/MIE/MSTATUS、``thread_id``。

**关键代码** （``dv/cosim/spike_cosim.cc:L863-L872``）：

.. code-block:: cpp

   void SpikeCosim::notify_dside_access(const DSideAccessInfo &access_info,
                                        int thread_id) {
     assert((access_info.addr & 0x3) == 0);
     assert(thread_id >= 0 && thread_id < num_threads);
   
     PendingMemAccess pending_access;
     pending_access.dut_access_info = access_info;
     pending_access.be_spike = 0;
     thread_state[thread_id].pending_dside_accesses.push_back(pending_access);
   }

**逐段解释** ：

* 第 L863-L866 行：D-side access 地址必须 4-byte 对齐，``thread_id`` 必须在当前
  ``num_threads`` 范围内。
* 第 L868-L871 行：DUT access 被封装成 ``PendingMemAccess`` 后压入
  ``thread_state[thread_id].pending_dside_accesses``。

**接口关系** ：

* **被调用** ：DPI wrapper ``riscv_cosim_notify_dside_access``。
* **调用** ：无下层函数；写 per-thread vector。
* **共享状态** ：``thread_state[thread_id].pending_dside_accesses``。

§8  scoreboard：按 ``trace_seq_item.thread_id`` 路由
--------------------------------------------------------------------------------

§8.1  scoreboard 的 per-thread 数组与共享 memory queue
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_cosim_scoreboard`` 维护两个 thread 槽的 mismatch、instruction count、
pending trace、async wb 和 previous MIP；memory access queue 则是共享队列。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L61-L80``）：

.. code-block:: systemverilog

     // Per-thread statistics
     int    mismatch_count[2];
     int    insn_cnt[2];
   
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

**逐段解释** ：

* 第 L61-L63 行：mismatch 和 instruction count 均按固定数组 ``[2]`` 保存。
* 第 L66-L73 行：scoreboard 还有全局初始化状态与 store coalescing counter。
* 第 L75-L80 行：pending trace queue 是 ``pending_trace_q[2][$]``，每个 thread 有一个
  queue。

**接口关系** ：

* **被调用** ：scoreboard run tasks 和 report phase。
* **调用** ：无函数调用；状态声明。
* **共享状态** ：``mismatch_count``、``insn_cnt``、``pending_trace_q``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L82-L103``）：

.. code-block:: systemverilog

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
     typedef struct {
       bit [4:0]  rd;
       bit [31:0] rd_data;
       bit        suppress;
       int        source;
       int        wb_tag;       // global wb_seq from probe_monitor
     } async_wb_hint_t;
     async_wb_hint_t async_wb_q[2][$];
   
     // Previous MIP value for pre/post tracking (per-thread)
     bit [31:0] prev_mip[2];

**逐段解释** ：

* 第 L82-L89 行：LSU AXI memory access queue 是单个 ``pending_mem_access_q[$]``，注释
  明确 memory bus 在 thread 间共享。
* 第 L91-L100 行：async writeback hint 带 rd/data/suppress/source/wb_tag，并按
  ``async_wb_q[2][$]`` 分 thread 存放。
* 第 L102-L103 行：``prev_mip`` 也是 per-thread 数组，用于 Spike pre/post MIP 通知。

**接口关系** ：

* **被调用** ：memory notification、async wb matching 和 Spike interrupt notification。
* **调用** ：无函数调用；状态声明。
* **共享状态** ：``pending_mem_access_q`` shared，``async_wb_q`` 和 ``prev_mip`` per-thread。

§8.2  run phase 并行消费 trace、probe、dmem 和 reset
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：scoreboard 在 ``run_phase`` 中 fork 四个任务：trace、probe async、dmem 和 reset
monitor。trace/probe/dmem 三条路径可能并行更新 per-thread queues 或 shared memory queue。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L153-L163``）：

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

**逐段解释** ：

* 第 L153-L155 行：只有 ``enable_cosim`` 为 1 时，scoreboard 才初始化 cosim。
* 第 L156-L161 行：四个任务并行运行。trace 负责提交指令，probe async 负责 NB-load/DIV
  写回 hint，dmem 负责 AXI LSU memory access，reset monitor 负责 reset 后重新初始化。
* 第 L162-L163 行：``join`` 表示这些 forever task 共同构成 run phase 主循环。

**接口关系** ：

* **被调用** ：UVM runtime。
* **调用** ：``init_cosim``、``run_cosim_trace``、``run_cosim_probe_async``、
  ``run_cosim_dmem``、``run_reset_monitor``。
* **共享状态** ：``pending_trace_q``、``async_wb_q``、``pending_mem_access_q``、
  ``cosim_handle``。

**并行数据流** ：

.. code-block:: bash

   trace_fifo          -> run_cosim_trace       -> pending_trace_q[tid]
   dut_probe_fifo      -> run_cosim_probe_async -> async_wb_q[tid]
   lsu_axi_fifo        -> run_cosim_dmem        -> pending_mem_access_q
   probe_vif.rst_n     -> run_reset_monitor     -> flush_state/init_cosim
                                             |
                                             v
                                  process_pending_trace(tid)

**逐段解释** ：

* trace path 和 probe path 都按 ``tid`` 写入 per-thread queue。
* dmem path 先写共享 ``pending_mem_access_q``，再尝试推进 thread 0 和 thread 1 的
  pending trace。
* reset path 会清空 per-thread queues 和 shared memory queue，因此它是所有路径的共同
  状态边界。

§8.3  trace pkt 按 ``thread_id`` 入队
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``run_cosim_trace`` 从 trace FIFO 取出 pkt，读取 ``trace_item.thread_id``，
并将 pkt 压入对应 ``pending_trace_q[tid]``。

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

**逐段解释** ：

* 第 L206-L211 行：task 永久从 ``trace_fifo`` 取 item，并统计 trace item 数。
* 第 L213-L217 行：cosim 已初始化时，``tid`` 来自 ``trace_item.thread_id``，pkt 压入
  ``pending_trace_q[tid]``。
* 第 L218-L220 行：high watermark 按对应 thread 的 queue size 更新。
* 第 L221 行：入队后立即尝试处理同一 ``tid`` 的 pending trace。

**接口关系** ：

* **被调用** ：``run_phase`` fork。
* **调用** ：``trace_fifo.get``、``process_pending_trace``。
* **共享状态** ：``trace_fifo``、``pending_trace_q[tid]``、``pending_trace_high_watermark``。

§8.4  async writeback hint 按 ``thread_id`` 入队
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：probe async task 只保留 NB-load/DIV 类异步写回 hint，并根据
``probe_item.thread_id`` 写入 ``async_wb_q[tid]``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L226-L247``）：

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

**逐段解释** ：

* 第 L227-L233 行：task 永久从 ``dut_probe_fifo`` 取 item，并统计 probe item 数。
* 第 L235-L236 行：regular writeback 已经在 trace channel 中携带，因此直接跳过。
* 第 L238-L242 行：hint 记录 rd、数据、suppress、source 和严格匹配用 ``wb_tag``。
* 第 L244-L247 行：``tid`` 来自 ``probe_item.thread_id``，hint 压入 ``async_wb_q[tid]``。

**接口关系** ：

* **被调用** ：``run_phase`` fork。
* **调用** ：``dut_probe_fifo.get``、``process_pending_trace``。
* **共享状态** ：``async_wb_q[tid]``、``probe_item_count``。

§8.5  dmem path 写共享 queue 后尝试推进两个 thread
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``run_cosim_dmem`` 从 LSU AXI FIFO 获取 memory transaction，写入共享 memory
access queue，然后分别尝试 ``process_pending_trace(0)`` 和 ``process_pending_trace(1)``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L260-L273``）：

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

**逐段解释** ：

* 第 L261-L266 行：task 永久从 ``lsu_axi_fifo`` 取 AXI transaction，并统计 AXI item 数。
* 第 L268-L269 行：cosim 已初始化时调用 ``enqueue_memory_accesses`` 写入共享 memory
  access queue。
* 第 L270-L272 行：由于 memory bus 是共享的，新的 AXI access 可能解除任一 thread 的
  store/AMO 等待，所以代码显式尝试 thread 0 和 thread 1。

**接口关系** ：

* **被调用** ：``run_phase`` fork。
* **调用** ：``lsu_axi_fifo.get``、``enqueue_memory_accesses``、
  ``process_pending_trace``。
* **共享状态** ：``pending_mem_access_q``、``pending_trace_q[0]``、``pending_trace_q[1]``。

§8.6  ``process_pending_trace`` 逐 thread 排空
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``process_pending_trace(int tid)`` 只处理指定 thread 的 pending trace queue。
它在 store/AMO 等待 memory access，DIV/NB-load 等待 async wb hint 后，才调用
``compare_instruction(tid, item)``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L288-L327``，节选）：

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

**逐段解释** ：

* 第 L288-L291 行：函数注释列出两个 gate：store/AMO 等 memory access，DIV/NB-load 等
  async writeback hint。
* 第 L292-L293 行：循环只查看 ``pending_trace_q[tid]`` 的队首。
* 第 L295-L307 行：如果当前指令必须等待 memory access 且没有匹配项，则根据 store
  coalescing counter 决定继续或 break。

**接口关系** ：

* **被调用** ：trace、probe async 和 dmem 三条路径都会调用。
* **调用** ：``must_wait_for_memory_access``、``has_matching_memory_access``、
  ``compare_instruction``。
* **共享状态** ：``pending_trace_q[tid]``、``pending_mem_access_q``、store coalescing
  counters。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L309-L326``）：

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

**逐段解释** ：

* 第 L309-L314 行：DIV/NB-load 类指令需要匹配 ``async_wb_q[tid]``，否则停止处理该 thread
  的队列。
* 第 L316-L320 行：通过 gate 后弹出队首；memory instruction 若有匹配 AXI access，则
  消费该 shared memory access。
* 第 L322-L325 行：store/AMO 增加 coalescing counter 后，调用 ``compare_instruction``
  并把 ``tid`` 传入。

**接口关系** ：

* **被调用** ：``run_cosim_trace``、``run_cosim_probe_async``、``run_cosim_dmem``。
* **调用** ：``has_matching_async_wb``、``pop_matching_memory_access``、
  ``compare_instruction``。
* **共享状态** ：``pending_trace_q[tid]``、``async_wb_q[tid]``、``pending_mem_access_q``。

§8.7  ``compare_instruction`` 用 ``tid`` 调用 Spike DPI
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``compare_instruction`` 在每条指令 step 前按 ``tid`` 设置 debug/NMI/MIP/mcycle，
并把 ``tid`` 传给 ``riscv_cosim_step``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L573-L581``）：

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

**逐段解释** ：

* 第 L573-L575 行：interrupt-only pkt 不对应一条实际退休指令。
* 第 L576-L581 行：debug、NMI、NMI internal、MIP 和 mcycle 通知都把 ``tid`` 传给
  DPI；``prev_mip`` 也按 ``tid`` 更新。

**接口关系** ：

* **被调用** ：``process_pending_trace``。
* **调用** ：``riscv_cosim_set_debug_req``、``riscv_cosim_set_nmi``、
  ``riscv_cosim_set_nmi_int``、``riscv_cosim_set_mip``、``riscv_cosim_set_mcycle``。
* **共享状态** ：``prev_mip[tid]``、``cosim_handle``、trace item interrupt state。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L642-L657``）：

.. code-block:: systemverilog

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

**逐段解释** ：

* 第 L642-L648 行：普通 step 路径遵循 debug、NMI、NMI internal、MIP、mcycle 的通知顺序，
  每个调用都带 ``tid``。
* 第 L649-L651 行：instruction-side error 也按 ``tid`` 通知 Spike。
* 第 L653-L657 行：``riscv_cosim_step`` 的最后一个实参是 ``tid``，把本次退休指令路由到
  对应 Spike hart。

**接口关系** ：

* **被调用** ：``process_pending_trace``。
* **调用** ：多组 ``riscv_cosim_*`` DPI 函数。
* **共享状态** ：``prev_mip[tid]``、writeback view、trap state、``cosim_handle``。

§8.8  report phase 分别报告 T0/T1
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：scoreboard report phase 汇总两个 thread 的 pending queue、async hint 和 mismatch
统计，并从 Spike 查询 T0/T1 matched instruction count。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L802-L823``）：

.. code-block:: systemverilog

       total_mismatch = mismatch_count[0] + mismatch_count[1];
       total_pending_trace = pending_trace_q[0].size() + pending_trace_q[1].size();
       total_pending_async = async_wb_q[0].size() + async_wb_q[1].size();
   
       `uvm_info("cosim", "=== Co-simulation Scoreboard Report ===", UVM_LOW)
       `uvm_info("cosim", $sformatf("Trace items received: %0d", trace_item_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("Probe items received: %0d (async-only)", probe_item_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("AXI items received: %0d", axi_item_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("Pending trace items: T0=%0d T1=%0d",
         pending_trace_q[0].size(), pending_trace_q[1].size()), UVM_LOW)
       `uvm_info("cosim", $sformatf("Pending LSU accesses: %0d", pending_mem_access_q.size()), UVM_LOW)
       `uvm_info("cosim", $sformatf("Pending async wb hints: T0=%0d T1=%0d",
         async_wb_q[0].size(), async_wb_q[1].size()), UVM_LOW)
       `uvm_info("cosim", $sformatf("Trace backlog high watermark: %0d",
         pending_trace_high_watermark), UVM_LOW)
       `uvm_info("cosim", $sformatf("Steps executed: %0d", step_count), UVM_LOW)
       `uvm_info("cosim", $sformatf("Mismatches: T0=%0d T1=%0d total=%0d",
         mismatch_count[0], mismatch_count[1], total_mismatch), UVM_LOW)

**逐段解释** ：

* 第 L802-L804 行：mismatch、pending trace 和 pending async 都分别从 index 0 和 1
  汇总。
* 第 L806-L814 行：report 输出 trace/probe/AXI 总数，并分别打印 T0/T1 pending trace 与
  async hint。
* 第 L815-L819 行：report 输出 backlog high watermark、step count 和 T0/T1 mismatch。

**接口关系** ：

* **被调用** ：UVM report phase。
* **调用** ：``uvm_info``。
* **共享状态** ：``pending_trace_q``、``async_wb_q``、``pending_mem_access_q``、
  ``mismatch_count``。

§9  当前边界与排查要点
--------------------------------------------------------------------------------

§9.1  不把当前 release 参数误写成双线程启用
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：本节把可配置能力、当前参数实例和验证侧支撑面分开，防止 ground truth 漂移。

**关键代码** （``syn/include/eh2_param.vh:L166``）：

.. code-block:: systemverilog

       NUM_THREADS            : 6'h01         ,

**逐段解释** ：

* 第 L166 行是当前 release 参数实例的直接证据。因此本文在描述当前配置时只写
  ``NUM_THREADS=1``。
* ``rvarbiter2_smt``、thread CSR mux、LEC wrapper 端口展平和 cosim per-thread 路由说明
  源码有双线程支撑结构，但它们不是当前参数实例已启用双线程的证据。

**接口关系** ：

* **被调用** ：所有本章结论的参数依据。
* **调用** ：无。
* **共享状态** ：``pt.NUM_THREADS``。

§9.2  trace monitor 是当前双线程闭环的显式边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当前 trace interface 与 TB signal 可以按线程展开，但 trace monitor 代码只消费
thread 0 convenience 信号，并固定写 ``thread_id=0``。

**关键代码** （``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L82-L85``）：

.. code-block:: systemverilog

         // Monitor thread 0, instruction 0 (i0)
         if (vif.t0_i0_valid) begin
           txn = eh2_trace_seq_item::type_id::create("trace_txn");
           txn.thread_id   = 0;

**逐段解释** ：

* 第 L82-L85 行：monitor 明确采样 thread 0，且 trace pkt 的 ``thread_id`` 固定为 0。
* 因此本章不会把当前 UVM trace monitor 描述成完整双线程 trace collector。

**接口关系** ：

* **被调用** ：UVM trace agent。
* **调用** ：trace seq item factory。
* **共享状态** ：``vif.t0_i0_*``、``txn.thread_id``。

§9.3  cosim memory 与 PIC 仲裁模型边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：ADR-0016 明确 Spike memory 仍是共享地址空间，PIC 中断仲裁不由 Spike 模型化。
本文把这作为 cosim 模型边界，而不是写成 RTL 行为边界。

**关键代码** （``dv/cosim/spike_cosim.h:L83-L88``）：

.. code-block:: cpp

     // Active thread for mmio callbacks (set before each step)
     int active_thread;
   
     // Memory bus (shared across threads — EH2 shares address space)
     bus_t bus;
     std::vector<std::unique_ptr<mem_t>> mems;

**逐段解释** ：

* 第 L83-L84 行：``active_thread`` 只用于 MMIO callback 判定当前 step 的 hart。
* 第 L86-L88 行：``bus`` 和 ``mems`` 是类成员，不在 ``PerThreadState`` 内；这与
  ADR-0016 中“Spike 内存仍然共享”的边界一致。

**接口关系** ：

* **被调用** ：Spike memory access callback 和 backdoor memory load/write。
* **调用** ：Spike bus/memory API。
* **共享状态** ：shared ``bus``、shared ``mems``、per-step ``active_thread``。

§9.4  排查路径：从 trace mismatch 回溯到 thread 路由
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：当 cosim mismatch 或 trace 缺失看起来与 thread 有关时，应按 source code 的
实际路由顺序排查。

排查顺序如下：

.. code-block:: bash

   1. syn/include/eh2_param.vh
      check NUM_THREADS in current parameter set
   2. rtl/design/dec/eh2_dec.sv
      check genst/genmt and dec_i*_tid_d routing
   3. dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv
      check emitted trace_seq_item.thread_id
   4. dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
      check pending_trace_q[tid] and async_wb_q[tid]
   5. dv/cosim/spike_cosim.cc
      check num_threads clamp and step(thread_id)

**逐段解释** ：

* 第 1 步确认当前配置是否真的启用多线程。
* 第 2 步确认 RTL decode 是固定 thread 0 路径，还是经过 ``rvarbiter2_smt``。
* 第 3 步确认 UVM trace pkt 的 ``thread_id`` 是否可能为 1。当前 monitor 代码只能产生 0。
* 第 4 步确认 scoreboard 是否把 pkt 放入正确 per-thread queue。
* 第 5 步确认 SpikeCosim 的 ``num_threads`` 和 ``thread_id`` 范围是否匹配。

**接口关系** ：

* **被调用** ：调试 cosim mismatch、trace gap、dual-thread profile 行为时使用。
* **调用** ：无。
* **共享状态** ：``NUM_THREADS``、``thread_id``、``tid``、``num_threads``。

§10  参考资料
--------------------------------------------------------------------------------

**关联章节** ：

* :ref:`pipeline` — decode、dual-issue 与 thread 选择背景。
* :ref:`rvfi_trace` — RVFI-equivalent trace 与 trace packet。
* :ref:`cosim_scoreboard` — scoreboard 的 Spike 通知顺序与 per-thread queue。
* :ref:`appendix_b_uvm/trace_agent` — trace interface、monitor 与 seq item。
* :ref:`appendix_b_uvm/cosim_agent` — cosim UVM agent 与 scoreboard。
* :ref:`appendix_c_tools/cosim_cpp` — C++ Spike cosim 与 DPI bridge。
* :ref:`adr-0003` — 原始 ``NUM_THREADS=1`` cosim 边界。
* :ref:`adr-0016` — ``NUM_THREADS=2`` multi-hart cosim 支持路径。

**源码绝对路径** ：

* :file:`/home/host/eh2-veri/syn/include/eh2_param.vh`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_ib_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_decode_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_tlu_top.sv`
* :file:`/home/host/eh2-veri/rtl/design/lib/beh_lib.sv`
* :file:`/home/host/eh2-veri/rtl/lec_shim/eh2_veer_lec_pack.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`/home/host/eh2-veri/dv/cosim/cosim.h`
* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.svh`
* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.cc`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.h`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.cc`
* :file:`/home/host/eh2-veri/docs/adr/0016-multi-hart-cosim.md`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
