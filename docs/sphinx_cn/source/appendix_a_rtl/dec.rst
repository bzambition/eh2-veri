.. _appendix_a_rtl_dec:
.. _appendix_a_rtl/dec:

译码单元（DEC）- 详细参考
==========================

:status: draft
:source: rtl/design/dec/
:last-reviewed: 2026-05-19

§1  源文件边界与数据流
----------------------

本章只描述当前源码中的 DEC 实现。DEC 源文件位于
:file:`rtl/design/dec/`，并由 :file:`dv/uvm/core_eh2/eh2_rtl.f`
的 ``// Decode`` 分组纳入 RTL 编译。本文不会把外部 RISC-V 规范、旧版
微架构说明或验证经验写成源码事实；所有端口、状态和控制关系都来自当前
commit 下的 SystemVerilog 源码。

DEC 的主要数据流如下：

.. code-block:: text

   IFU aligner
      |
      +-- ifu_i0_* / ifu_i1_*
      v
   per-thread eh2_dec_ib_ctl
      |        |
      |        +-- debug abstract command injection
      v
   thread arbitration in eh2_dec
      |
      +-- selected i0 / i1 instruction, PC, predecode, branch metadata
      v
   eh2_dec_decode_ctl
      |
      +-- ALU / LSU / MUL / DIV packets
      +-- block and stall vectors
      +-- bypass selects and data
      +-- nonblocking load CAM
      +-- WB1 trace mirror
      |
      +-- per-thread eh2_dec_gpr_ctl write/read ports
      |
      +-- eh2_dec_tlu_top
               |
               +-- per-thread eh2_dec_tlu_ctl
               +-- CSR read/write state
               +-- trap / interrupt / debug halt control
               +-- trace valid / exception / interrupt metadata

``eh2_dec`` 是集成层：它实例化每个线程的 instruction buffer 和 GPR，
再实例化 decode 控制、TLU 顶层和 trigger 匹配器。``eh2_dec_decode_ctl``
承担大部分 D/E/WB 级控制；``eh2_dec_tlu_top`` 和 ``eh2_dec_tlu_ctl``
承担 CSR、trap、interrupt、debug、performance counter 和 trace 元数据；
``eh2_dec_trigger`` 只做 DEC 级 trigger 数据匹配。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L32-L40``）：

.. code-block:: text

   // Decode
   rtl/design/dec/eh2_dec_csr.sv
   rtl/design/dec/eh2_dec_decode_ctl.sv
   rtl/design/dec/eh2_dec_gpr_ctl.sv
   rtl/design/dec/eh2_dec_ib_ctl.sv
   rtl/design/dec/eh2_dec.sv
   rtl/design/dec/eh2_dec_tlu_ctl.sv
   rtl/design/dec/eh2_dec_tlu_top.sv
   rtl/design/dec/eh2_dec_trigger.sv

逐段解释：

* 第 L32 行：filelist 用 ``// Decode`` 明确标出 DEC 编译分组。该分组是本章
  的源码边界。
* 第 L33-L40 行：当前 DEC 分组一共列出 8 个 SystemVerilog 文件。其中
  ``eh2_dec.sv`` 是顶层集成文件；``eh2_dec_decode_ctl.sv`` 是译码控制主文件；
  ``eh2_dec_tlu_ctl.sv`` 和 ``eh2_dec_tlu_top.sv`` 共同实现 TLU。

接口关系：

* 被引用：仿真和综合 filelist 通过 :file:`dv/uvm/core_eh2/eh2_rtl.f`
  把这些文件加入 RTL 编译。
* 调用：filelist 不调用逻辑，只定义编译输入集合。
* 共享状态：无运行时状态；运行时状态存在于各 RTL 模块的 flop、组合信号和端口。

§2  ``eh2_dec.sv`` 顶层集成
----------------------------

``eh2_dec`` 的职责是把 per-thread 前端输入收束到 decode lane，并把 decode、
GPR、TLU 和 trigger 子模块接成一个 DEC 子系统。源码中没有单独的 DEC wrapper；
``eh2_dec`` 自身就是该目录的顶层。

§2.1  模块参数和早期端口
~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 DEC 顶层模块，导入 ``eh2_pkg``，并通过 ``eh2_param.vh`` 获取
``pt`` 参数结构。早期端口已经显示 DEC 同时连接时钟、线程时钟、secondary ALU、
branch、core-empty 和 DIV cancel 信号。

关键代码（``rtl/design/dec/eh2_dec.sv:L27-L60``）：

.. code-block:: systemverilog

   module eh2_dec
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic clk,
      input logic free_clk,
      input logic free_l2clk,
      input logic [pt.NUM_THREADS-1:0] active_thread_l2clk,

      output logic         dec_i0_secondary_d,             // I0 Secondary ALU at  D-stage.  Used for clock gating
      output logic         dec_i0_secondary_e1,            // I0 Secondary ALU at E1-stage.  Used for clock gating
      output logic         dec_i0_secondary_e2,            // I0 Secondary ALU at E2-stage.  Used for clock gating

      output logic         dec_i1_secondary_d,             // I1 Secondary ALU at  D-stage.  Used for clock gating
      output logic         dec_i1_secondary_e1,            // I1 Secondary ALU at E1-stage.  Used for clock gating
      output logic         dec_i1_secondary_e2,            // I1 Secondary ALU at E2-stage.  Used for clock gating

      output logic         dec_i0_branch_d,                // I0 Branch at  D-stage.  Used for clock gating
      output logic         dec_i0_branch_e1,               // I0 Branch at E1-stage.  Used for clock gating
      output logic         dec_i0_branch_e2,               // I0 Branch at E2-stage.  Used for clock gating
      output logic         dec_i0_branch_e3,               // I0 Branch at E3-stage.  Used for clock gating

      output logic         dec_i1_branch_d,                // I1 Branch at  D-stage.  Used for clock gating
      output logic         dec_i1_branch_e1,               // I1 Branch at E1-stage.  Used for clock gating
      output logic         dec_i1_branch_e2,               // I1 Branch at E2-stage.  Used for clock gating

逐段解释：

* 第 L27-L31 行：模块名是 ``eh2_dec``，导入 ``eh2_pkg``，并 include 参数文件。
  本章后续出现的 ``pt.NUM_THREADS``、``pt.BTB_*``、``pt.DCCM_REGION`` 等参数
  均来自这一路径。
* 第 L33-L37 行：DEC 同时接收 ``clk``、``free_clk``、``free_l2clk`` 和
  per-thread ``active_thread_l2clk``。这解释了为什么后续 IB、GPR 和 TLU
  会按线程实例化并使用线程时钟。
* 第 L38-L54 行：secondary ALU 和 branch 信号按 i0/i1、D/E1/E2/E3 阶段输出。
  源码注释说明这些信号用于 clock gating。
* 第 L59-L60 行：``dec_tlu_core_empty`` 和 ``dec_div_cancel`` 在端口早期出现，
  表明 TLU 空闲状态和 DIV cancel 是 DEC 对外接口的一部分。

接口关系：

* 被调用：上层 core RTL 实例化 ``eh2_dec``，该实例化不在本文件片段内展开。
* 调用：本节仅声明模块，不实例化下层模块。
* 共享状态：使用 ``pt`` 参数结构和多个时钟域输入。

§2.2  active clock 和 instruction buffer generate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 DEC 内部 ``active_clk``，并按 ``pt.NUM_THREADS`` 为每个线程实例化
``eh2_dec_ib_ctl``。IB 接收 IFU 指令、PC、predecode、branch prediction 元数据、
debug 注入输入和 flush/cancel 控制。

关键代码（``rtl/design/dec/eh2_dec.sv:L689-L706``）：

.. code-block:: systemverilog

      rvoclkhdr activeclk (.*, .en(1'b1), .l1clk(active_clk));


     for (genvar i=0; i<pt.NUM_THREADS; i++) begin : ib


        eh2_dec_ib_ctl #(.pt(pt)) instbuff (.clk               (active_thread_l2clk[i]),
                                             .tid               (1'(i)            ),
                                             .ifu_i0_valid      (ifu_i0_valid[i]),
                                             .ifu_i1_valid      (ifu_i1_valid[i]),
                                             .ifu_i0_icaf       (ifu_i0_icaf[i]),
                                             .ifu_i0_icaf_type  (ifu_i0_icaf_type[i]),
                                             .ifu_i0_icaf_second (ifu_i0_icaf_second[i]),
                                             .ifu_i0_dbecc      (ifu_i0_dbecc[i]),

逐段解释：

* 第 L689 行：``rvoclkhdr`` 以常量 enable 生成 ``active_clk``。该信号后续喂给
  SMT arbiter 和其他 DEC 内部 flop。
* 第 L692-L696 行：``for`` generate 按 ``pt.NUM_THREADS`` 建立 ``ib`` 实例数组。
  每个实例的 ``clk`` 接 ``active_thread_l2clk[i]``，``tid`` 接当前 generate 索引。
* 第 L697-L706 行：IFU 的 i0/i1 valid、instruction access fault、ECC、instruction
  和 PC 输入按线程切片后接入对应 IB。

接口关系：

* 被调用：``eh2_dec`` 顶层生成 ``instbuff``。
* 调用：实例化 ``eh2_dec_ib_ctl``。
* 共享状态：读取 ``pt.NUM_THREADS``，按线程传递 IFU 输入和 cancel/flush 信号。

关键代码（``rtl/design/dec/eh2_dec.sv:L723-L766``）：

.. code-block:: systemverilog

                                             .ifu_i0_cinst      (ifu_i0_cinst[i]),
                                             .ifu_i1_cinst      (ifu_i1_cinst[i]),

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

逐段解释：

* 第 L723-L724 行：压缩指令原始 16-bit 编码也进入 IB，并在后续 trace/非法指令
  捕获路径中使用。
* 第 L726-L727 行：IB 直接接收 ``dec_i1_cancel_e1`` 和 ``exu_flush_final``。
  这两个信号决定 IB valid 更新和 cancel recovery。
* 第 L728-L735 行：IB 输出四个 buffer slot 的 valid，以及下一周期 ``ib0`` 是否含
  LSU、MUL 或 i0-only 指令。这些信号被顶层用于 SMT arbitration。
* 第 L736-L747 行：IB 输出 D-stage i0/i1 指令、debug valid、PC、PC4 和 branch
  predictor 元数据。后续 thread mux 会按 ``dec_i0_tid_d`` 和 ``dec_i1_tid_d`` 选择。

接口关系：

* 被调用：``eh2_dec`` 顶层。
* 调用：``eh2_dec_ib_ctl`` 输出 D-stage 数据和 arbitration hint。
* 共享状态：``dec_i1_cancel_e1`` 来自 ``eh2_dec_decode_ctl``，``exu_flush_final``
  来自执行/提交 flush 汇总。

§2.3  per-thread GPR 实例化
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按线程实例化 ``eh2_dec_gpr_ctl``，把 i0/i1 源寄存器读端口和 i0/i1、
NB-load、DIV 四个写端口接到每个线程自己的 GPR 实例。

关键代码（``rtl/design/dec/eh2_dec.sv:L772-L797``）：

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

                                          // outputs
                                          .rd0(gpr_i0rs1_d[i]), .rd1(gpr_i0rs2_d[i]),
                                          .rd2(gpr_i1rs1_d[i]), .rd3(gpr_i1rs2_d[i])
                                          );

逐段解释：

* 第 L772-L776 行：GPR 也按 ``pt.NUM_THREADS`` 生成，每个实例使用对应线程时钟和
  ``tid``。
* 第 L778-L787 行：i0 的两个读端口使用 ``dec_i0_tid_d``，i1 的两个读端口使用
  ``dec_i1_tid_d``。这使一个物理实例只在 tid 匹配时返回非零读数据。
* 第 L789-L792 行：四个写端口分别来自 i0 WB、i1 WB、NB-load 数据返回和 DIV 结果。
  NB-load 写地址按线程从 ``dec_nonblock_load_waddr[i]`` 选择。
* 第 L795-L796 行：四个读数据输出仍按线程保留，后续在顶层通过 OR 或 mux 合成
  decode lane 的源操作数。

接口关系：

* 被调用：``eh2_dec`` 顶层。
* 调用：``eh2_dec_gpr_ctl``。
* 共享状态：GPR 写入来自 normal WB、NB-load 异步完成和 DIV 异步完成三类路径。

§2.4  SMT arbitration 和线程选择
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把每线程 IB 的 ``ready_in``、``lsu_in``、``mul_in``、``i0_only_in`` 汇总，
并根据 ``pt.NUM_THREADS`` 选择单线程固定路径或双线程 ``rvarbiter2_smt`` 路径。

关键代码（``rtl/design/dec/eh2_dec.sv:L805-L860``）：

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

逐段解释：

* 第 L805-L808 行：顶层把 IB 的提前一拍 valid 和预译码类别提示转成 arbiter 输入。
* 第 L810-L811 行：``i0_sel_i0_t1_d`` 和两个 i1 选择向量是 thread selection 的内部控制。
* 第 L814-L827 行：单线程路径不使用 arbiter，tid 固定为 0，``ready[0]`` 固定为 1，
  GPR 读数据直接取线程 0。

接口关系：

* 被调用：``eh2_dec`` 组合路径。
* 调用：单线程分支不实例化下层模块。
* 共享状态：读取 IB hint，写 ``dec_i0_tid_d``、``dec_i1_tid_d``、``ready`` 和 GPR 读数据。

关键代码（``rtl/design/dec/eh2_dec.sv:L831-L860``）：

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

逐段解释：

* 第 L831-L836 行：双线程路径把两个线程的 GPR 读数据 OR 在一起。由于
  ``eh2_dec_gpr_ctl`` 内部按 tid gating，未选中线程输出为 0，这里可以用 OR 合成。
* 第 L840-L854 行：``rvarbiter2_smt`` 接收 flush、decode shift、per-thread ready、
  LSU/MUL/i0-only hint、thread stall 和 favor flip，输出 i0/i1 的选择信号。
* 第 L857-L859 行：i0 tid 来自 ``i0_sel_i0_t1_d``；i1 tid 由 ``i1_sel_i1_d[1]`` 或
  ``i1_sel_i0_d[1]`` 表示是否选择线程 1。

接口关系：

* 被调用：``eh2_dec`` 双线程 generate 分支。
* 调用：``rvarbiter2_smt``。
* 共享状态：读取 ``dec_thread_stall_in`` 和 ``dec_force_favor_flip_d``，输出 decode lane tid。

§2.5  i0/i1 lane 选择和子模块实例化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 arbiter 结果从 per-thread IB 输出中选择 i0 和 i1 的 D-stage 数据，
再实例化 decode control、TLU top 和 trigger matcher。

关键代码（``rtl/design/dec/eh2_dec.sv:L869-L890``）：

.. code-block:: systemverilog

      assign dec_ib0_valid_d       = ib0_valid_d[dec_i0_tid_d] & ready[dec_i0_tid_d]     ;
      assign dec_i0_instr_d        = i0_instr_d[dec_i0_tid_d]        ;
      assign dec_i0_pc_d           = i0_pc_d[dec_i0_tid_d]           ;
      assign dec_i0_pc4_d          = i0_pc4_d[dec_i0_tid_d]          ;
      assign dec_i0_bp_index       = i0_bp_index[dec_i0_tid_d]       ;
      assign dec_i0_bp_fghr        = i0_bp_fghr[dec_i0_tid_d]        ;
      assign dec_i0_bp_btag        = i0_bp_btag[dec_i0_tid_d]        ;
      assign dec_i0_bp_toffset     = i0_bp_toffset[dec_i0_tid_d]        ;
      assign dec_i0_icaf_d         = i0_icaf_d[dec_i0_tid_d]         ;
      assign dec_i0_icaf_second_d  = i0_icaf_second_d[dec_i0_tid_d]      ;
      assign dec_i0_dbecc_d        = i0_dbecc_d[dec_i0_tid_d]        ;
      assign dec_i0_cinst_d        = i0_cinst_d[dec_i0_tid_d]        ;
      assign dec_i0_icaf_type_d    = i0_icaf_type_d[dec_i0_tid_d]    ;
      assign dec_i0_brp            = i0_br_p[dec_i0_tid_d]           ;
      assign dec_i0_predecode      = i0_predecode_p[dec_i0_tid_d]           ;

      assign dec_i0_debug_valid_d  = i0_debug_valid_d[dec_i0_tid_d] ;

      assign dec_i0_bp_fa_index    = i0_bp_fa_index[dec_i0_tid_d];

逐段解释：

* 第 L869 行：i0 valid 同时要求选中线程 ``ib0_valid_d`` 为 1 且 ``ready`` 为 1。
* 第 L870-L883 行：i0 instruction、PC、branch predictor 元数据、异常元数据、
  compressed instruction 和 predecode 都用 ``dec_i0_tid_d`` 选择。
* 第 L885-L889 行：debug valid 和 debug write/fence 相关数据也随 i0 选中线程传递。

接口关系：

* 被调用：``eh2_dec`` 顶层组合选择逻辑。
* 调用：无下层模块。
* 共享状态：读取 per-thread IB 输出和 arbiter 产生的 ``dec_i0_tid_d``。

关键代码（``rtl/design/dec/eh2_dec.sv:L893-L908``）：

.. code-block:: systemverilog

      if (pt.NUM_THREADS==2 )  begin

         // pipe is flushed; should not need ready[]
         assign dec_i1_debug_valid_d  = (i1_sel_i0_d[0] & i0_debug_valid_d[0]) |
                                        (i1_sel_i0_d[1] & i0_debug_valid_d[1]);

         assign dec_ib1_valid_d       = (i1_sel_i0_d[0] & ib0_valid_d[0] & ready[0]) |
                                        (i1_sel_i1_d[0] & ib1_valid_d[0] & ready[0]) |
                                        (i1_sel_i0_d[1] & ib0_valid_d[1] & ready[1]) |
                                        (i1_sel_i1_d[1] & ib1_valid_d[1] & ready[1]);


         assign dec_i1_instr_d        = ({32{i1_sel_i0_d[0]}} & i0_instr_d[0]) |
                                        ({32{i1_sel_i1_d[0]}} & i1_instr_d[0]) |
                                        ({32{i1_sel_i0_d[1]}} & i0_instr_d[1]) |
                                        ({32{i1_sel_i1_d[1]}} & i1_instr_d[1]);

逐段解释：

* 第 L893-L897 行：双线程路径允许 i1 选择某线程的 i0 slot，因此 debug valid 只从
  ``i1_sel_i0_d`` 对应的 i0 debug valid 合成。
* 第 L899-L902 行：``dec_ib1_valid_d`` 可以来自线程 0/1 的 ib0 或 ib1，每个候选项还
  要求对应线程 ``ready``。
* 第 L905-L908 行：i1 指令用 one-hot mask 从四个候选源合成：t0.i0、t0.i1、t1.i0、t1.i1。

接口关系：

* 被调用：``eh2_dec`` 双线程 i1 选择路径。
* 调用：无下层模块。
* 共享状态：读取 arbiter 的 ``i1_sel_i0_d``、``i1_sel_i1_d`` 和 per-thread IB 输出。

关键代码（``rtl/design/dec/eh2_dec.sv:L988-L996``）：

.. code-block:: systemverilog

      eh2_dec_decode_ctl #(.pt(pt)) decode (
                                             .*);

      eh2_dec_tlu_top #(.pt(pt)) tlu (.*);


   // Trigger

      eh2_dec_trigger #(.pt(pt)) dec_trigger (.*);

逐段解释：

* 第 L988-L989 行：``decode`` 实例接管 D-stage 译码、发射、stall、bypass、
  result pipeline 和 WB1 trace mirror。
* 第 L991 行：``tlu`` 实例接管 per-thread trap/interrupt/debug/CSR 逻辑和全局 CSR。
* 第 L994-L996 行：``dec_trigger`` 实例负责将 TLU 给出的 trigger 配置与当前 i0/i1
  decode 数据匹配。

接口关系：

* 被调用：``eh2_dec`` 顶层。
* 调用：``eh2_dec_decode_ctl``、``eh2_dec_tlu_top``、``eh2_dec_trigger``。
* 共享状态：三个实例通过 ``.*`` 共享大量 DEC 内部信号，具体信号由各模块端口声明约束。

§2.6  trace packet 打包
~~~~~~~~~~~~~~~~~~~~~~~

职责：在 DEC 顶层把 decode/TLU 产生的 WB1 instruction、PC、valid、exception、
interrupt 和 verification-only writeback mirror 打包成 ``trace_rv_trace_pkt``。

关键代码（``rtl/design/dec/eh2_dec.sv:L1003-L1022``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 L1003-L1006 行：每个线程生成一个 trace packet，instruction 和 address 字段按
  lane 1=i1、lane 0=i0 的顺序拼接。
* 第 L1008-L1013 行：valid 和 exception 字段来自 TLU 的 WB1 per-thread 输出。
  lane 0 valid 还包含 interrupt valid。
* 第 L1015-L1017 行：exception cause、interrupt 和 mtval 由 TLU 提供；注释说明
  cause 和 tval 在端口间复制。
* 第 L1018-L1021 行：源码明确把 rd valid/address/data 标注为 verification-only
  RVFI-equivalent writeback，lane 0 对应 i0，lane 1 对应 i1。

接口关系：

* 被调用：trace 输出消费者读取 ``trace_rv_trace_pkt``。
* 调用：无下层模块。
* 共享状态：读取 ``dec_i*_inst_wb1``、``dec_i*_pc_wb1``、``dec_tlu_*_wb1`` 和
  ``dec_i*_w*_wb1``。

§3  ``eh2_dec_ib_ctl.sv`` instruction buffer
--------------------------------------------

``eh2_dec_ib_ctl`` 是 per-thread instruction buffer。它维护 ib0 到 ib3 的四个
slot，把 IFU aligner 的 i0/i1 输入、debug abstract command 和 cancel/flush
逻辑组合成 D-stage 可选指令。

§3.1  端口边界
~~~~~~~~~~~~~~

职责：声明 IB 的输入输出边界。端口显示该模块同时连接 IFU 指令流、branch predictor
元数据、debug command、decode shift、flush、cancel 和 D-stage 输出。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L16-L40``）：

.. code-block:: systemverilog

   module eh2_dec_ib_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic   active_clk,                    // free clk

      input logic   tid,                           // thread id


      input logic   dec_i0_tid_d,                  // tid selected for decode this cycle
      input logic   dec_i1_tid_d,                  // tid selected for decode this cycle


      input logic                 dbg_cmd_valid,  // valid dbg cmd
      input logic                 dbg_cmd_tid,    // dbg tid

      input logic                 dbg_cmd_write,  // dbg cmd is write
      input logic [1:0]           dbg_cmd_type,   // dbg type
      input logic [31:0]          dbg_cmd_addr,   // expand to 31:0

      input logic exu_flush_final,                // all flush sources: primary/secondary alu's, trap

      input logic dec_i1_cancel_e1,

逐段解释：

* 第 L16-L20 行：IB 与其他 DEC 子模块一样导入 ``eh2_pkg`` 并使用 ``eh2_param.vh``。
* 第 L22-L28 行：模块知道自己的 ``tid``，同时接收本周期被 decode 选中的 i0/i1 tid。
  后续 shift 判断依赖这些 tid 是否匹配。
* 第 L31-L37 行：debug abstract command 以 valid、tid、write、type、addr 形式进入 IB。
* 第 L38-L40 行：flush 和 ``dec_i1_cancel_e1`` 是 IB valid/data movement 的全局控制输入。

接口关系：

* 被调用：``eh2_dec`` 每线程实例化。
* 调用：端口声明本身不调用下层模块。
* 共享状态：读取 debug command、thread selection、flush 和 cancel 信号。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L85-L103``）：

.. code-block:: systemverilog

      output logic ib3_valid_d,               // ib3 valid
      output logic ib2_valid_d,               // ib2 valid
      output logic ib1_valid_d,               // ib1 valid
      output logic ib0_valid_d,               // ib0 valid

      output logic ib0_valid_in,              // ib0 valid cycle before decode
      output logic ib0_lsu_in,                // lsu cycle before decode
      output logic ib0_mul_in,                // mul cycle before decode
      output logic ib0_i0_only_in,            // i0_only cycle before decode

      output logic [31:0] i0_instr_d,         // i0 inst at decode
      output logic [31:0] i1_instr_d,         // i1 inst at decode

      output logic [31:1] i0_pc_d,            // i0 pc at decode
      output logic [31:1] i1_pc_d,

逐段解释：

* 第 L85-L88 行：IB 对外暴露四个 slot 的 valid，供 aligner 和 decode 顶层判断 buffer 深度。
* 第 L90-L93 行：``ib0_valid_in``、``ib0_lsu_in``、``ib0_mul_in``、``ib0_i0_only_in``
  是提前一拍的 arbitration hint。
* 第 L95-L103 行：D-stage instruction、PC 和 PC4 由 ib0/ib1 当前内容驱动。

接口关系：

* 被调用：``eh2_dec`` 的 IB instance 输出连接顶层 per-thread 数组。
* 调用：无下层模块。
* 共享状态：输出 ``ibval``、``ib0``、``ib1`` 当前状态的派生值。

§3.2  valid 生命周期和 IFU 写入许可
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：维护 ib0-ib3 的 valid 状态，并在 buffer 有空间、无 cancel、无 flush 时接受
IFU i0/i1 输入。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L208-L240``）：

.. code-block:: systemverilog

      rvdff #(1) flush_upperff (.*, .clk(active_clk), .din(exu_flush_final), .dout(flush_final));


      assign i1_cancel_e1 = dec_i1_cancel_e1;

      assign ibvalid[3:0] = ibval[3:0] | i0_wen[3:0] | {i1_wen[3:1],1'b0};

      assign ibval_in[3:0] = (({4{shift0}} & ((i1_cancel_e1) ? {ibval[2:0],1'b1} : ibvalid[3:0] )) |
                              ({4{shift1}} & {1'b0, ibvalid[3:1]}) |
                              ({4{shift2}} & {2'b0, ibvalid[3:2]})) & ~{4{flush_final}};

      rvdff #(4) ibvalff (.*, .clk(active_clk), .din(ibval_in[3:0]), .dout(ibval[3:0]));


      assign align_val[1:0] = {ifu_i1_valid,ifu_i0_valid};


   // only valid if there is room
   // no room if i1_cancel_e1

      assign ifu_i0_val = align_val[0] & ~ibval[3] & ~i1_cancel_e1 & ~flush_final;
      assign ifu_i1_val = align_val[1] & ~ibval[2] & ~i1_cancel_e1 & ~flush_final;

逐段解释：

* 第 L208-L211 行：``exu_flush_final`` 先打一拍成 ``flush_final``，``dec_i1_cancel_e1``
  直接赋给本模块内部 ``i1_cancel_e1``。
* 第 L213-L219 行：``ibvalid`` 合并旧 valid 和本周期写使能；``ibval_in`` 根据
  ``shift0``、``shift1``、``shift2`` 选择保持、移一格或移两格。``flush_final``
  会清零全部 valid。
* 第 L222-L229 行：IFU valid 被打包为 ``align_val``；i0 只有在 ib3 未占用、无 cancel、
  无 flush 时可进入，i1 只有在 ib2 未占用、无 cancel、无 flush 时可进入。
* 第 L233-L240 行：``i0_wen`` 和 ``i1_wen`` 根据当前占用情况选择写入 ib0-ib3 的位置。
  i1 不写 ib0，符合 ib0 作为下一条 i0 decode slot 的结构。

接口关系：

* 被调用：IB 内部 always/flop 网络。
* 调用：``rvdff`` 保存 flush 和 valid 状态。
* 共享状态：读写 ``ibval``，读取 ``shift*``、``i*_wen``、``flush_final`` 和 IFU valid。

§3.3  IFU packet 和 debug command 注入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 IFU 输入打包成 ``eh2_ib_pkt_t``，并把非 memory debug abstract command
转成可注入 ib0 的 GPR/CSR 指令编码。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L243-L263``）：

.. code-block:: systemverilog

      assign ifu_i0_ibp.cinst         = ifu_i0_cinst;
      assign ifu_i0_ibp.predecode     = ifu_i0_predecode;
      assign ifu_i0_ibp.icaf_type     = ifu_i0_icaf_type;
      assign ifu_i0_ibp.icaf_second       = ifu_i0_icaf_second;
      assign ifu_i0_ibp.dbecc         = ifu_i0_dbecc;
      assign ifu_i0_ibp.icaf          = ifu_i0_icaf;
      assign ifu_i0_ibp.pc            = ifu_i0_pc;
      assign ifu_i0_ibp.pc4           = ifu_i0_pc4;
      assign ifu_i0_ibp.brp           = i0_brp;
      assign ifu_i0_ibp.inst          = ifu_i0_instr;

      assign ifu_i1_ibp.cinst         = ifu_i1_cinst;
      assign ifu_i1_ibp.predecode     = ifu_i1_predecode;
      assign ifu_i1_ibp.icaf_type     = '0;
      assign ifu_i1_ibp.icaf_second       = '0;
      assign ifu_i1_ibp.dbecc         = '0;
      assign ifu_i1_ibp.icaf          = '0;
      assign ifu_i1_ibp.pc            = ifu_i1_pc;
      assign ifu_i1_ibp.pc4           = ifu_i1_pc4;
      assign ifu_i1_ibp.brp           = i1_brp;
      assign ifu_i1_ibp.inst          = ifu_i1_instr;

逐段解释：

* 第 L243-L252 行：i0 packet 保留 compressed instruction、predecode、icaf 类型、
  second-half fault、dbecc、PC、PC4、branch packet 和 instruction。
* 第 L254-L263 行：i1 packet 保留 compressed instruction、predecode、PC、PC4、
  branch packet 和 instruction；i1 的 icaf 类型、icaf second、dbecc、icaf 在此处被置 0。

接口关系：

* 被调用：IB 写入选择逻辑读取 ``ifu_i0_ibp`` 和 ``ifu_i1_ibp``。
* 调用：无下层模块。
* 共享状态：读取 IFU 输入和 branch packet 输入。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L283-L318``）：

.. code-block:: systemverilog

   // abstract memory command not done here
      assign debug_valid = dbg_cmd_valid & (dbg_cmd_type[1:0] != 2'h2) & (dbg_cmd_tid == tid);


      assign debug_read  = debug_valid & ~dbg_cmd_write;
      assign debug_write = debug_valid &  dbg_cmd_write;

      assign debug_read_gpr  = debug_read  & (dbg_cmd_type[1:0]==2'h0);
      assign debug_write_gpr = debug_write & (dbg_cmd_type[1:0]==2'h0);
      assign debug_read_csr  = debug_read  & (dbg_cmd_type[1:0]==2'h1);
      assign debug_write_csr = debug_write & (dbg_cmd_type[1:0]==2'h1);

      assign dreg[4:0]  = dbg_cmd_addr[4:0];
      assign dcsr[11:0] = dbg_cmd_addr[11:0];


      assign ib0_debug_in[31:0] = ({32{debug_read_gpr}}  & {12'b000000000000,dreg[4:0],15'b110000000110011}) |
                                  ({32{debug_write_gpr}} & {20'b00000000000000000110,dreg[4:0],7'b0110011}) |
                                  ({32{debug_read_csr}}  & {dcsr[11:0],20'b00000010000001110011}) |
                                  ({32{debug_write_csr}} & {dcsr[11:0],20'b00000001000001110011});

逐段解释：

* 第 L283-L284 行：源码注释说明 memory abstract command 不在这里处理；
  ``debug_valid`` 排除 ``dbg_cmd_type == 2'h2``，并要求 command tid 与本 IB tid 匹配。
* 第 L287-L293 行：debug command 被拆成 read/write 和 GPR/CSR 四种类别。
* 第 L295-L302 行：GPR 使用 ``dbg_cmd_addr[4:0]``，CSR 使用 ``dbg_cmd_addr[11:0]``，
  并按类别生成注入 ib0 的 32-bit 指令编码。
* 第 L305-L318 行：源码随后用 ``rvdffs`` 保存 debug write-data-on-rs1、debug fence
  和 debug valid，并用 ``debug_valid_d & ibval[0]`` 生成 ``i0_debug_valid_d``。

接口关系：

* 被调用：debug command 从外部进入 IB。
* 调用：``rvdffs`` 保存 debug 相关 D-stage 标志。
* 共享状态：读取 ``dbg_cmd_*``，写 ``ib0_debug_in``、``debug_wdata_rs1_d``、
  ``debug_fence_d`` 和 ``i0_debug_valid_d``。

§3.4  buffer 数据移动和 cancel recovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 ib3、ib2、ib1、ib0 之间移动 packet。``i1_cancel_e1`` 时，源码把保存的
旧 ib1/bp1 或相邻 slot 回灌，用于恢复被取消的 i1。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L320-L391``）：

.. code-block:: systemverilog

      assign ib3_in = ({$bits(eh2_ib_pkt_t){write_i0_ib3}} & ifu_i0_ibp) |
                      ({$bits(eh2_ib_pkt_t){write_i1_ib3}} & ifu_i1_ibp);

      assign ib3_final = (i1_cancel_e1) ? ib2 : ib3_in;

      rvdffibie #(.WIDTH($bits(eh2_ib_pkt_t)),.LEFT(24),.PADLEFT(13),.MIDDLE(31),.PADRIGHT(47),.RIGHT(16)) ib3ff (.*, .en(ibwrite[3]), .din(ib3_final), .dout(ib3));

      assign ib2_in = ({$bits(eh2_ib_pkt_t){write_i0_ib2}} & ifu_i0_ibp) |
                      ({$bits(eh2_ib_pkt_t){write_i1_ib2}} & ifu_i1_ibp) |
                      ({$bits(eh2_ib_pkt_t){shift_ib3_ib2}} & ib3);

      assign ib2_final = (i1_cancel_e1) ? ib1 : ib2_in;

      rvdffibie #(.WIDTH($bits(eh2_ib_pkt_t)),.LEFT(24),.PADLEFT(13),.MIDDLE(31),.PADRIGHT(47),.RIGHT(16)) ib2ff (.*, .en(ibwrite[2]), .din(ib2_final), .dout(ib2));

逐段解释：

* 第 L320-L325 行：ib3 可以从 IFU i0/i1 写入；cancel 时 ib3 取 ib2，形成向上恢复。
* 第 L327-L333 行：ib2 可以从 IFU i0/i1 写入，也可以由 ib3 下移；cancel 时 ib2 取 ib1。
* 第 L335-L344 行：ib1 可以从 IFU 写入，也可以由 ib2 或 ib3 下移；cancel 时 ib1 取 ib0。
* 第 L346-L391 行：ib0 可以从 IFU i0 或 ib1/ib2 下移。debug valid 时覆盖 ib0
  instruction 和部分 predecode/异常/branch 字段；cancel 时 ib0 使用 ``ibsave``。

接口关系：

* 被调用：IB shift/write 逻辑。
* 调用：``rvdffibie`` 保存 packet。
* 共享状态：读写 ``ib0`` 至 ``ib3``，读取 ``write_*``、``shift_*``、``i1_cancel_e1`` 和
  ``debug_valid``。

§3.5  branch metadata、shift 信号和保存点
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：branch prediction 元数据跟随 IB slot 移动；当同周期 decode 两条指令时，
源码保存旧 ib1/bp1，以便 ``i1_cancel_e1`` 恢复。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L436-L488``）：

.. code-block:: systemverilog

      if(pt.BTB_FULLYA) begin
         assign ifu_i0_brdata = {ifu_i0_bp_fa_index, ifu_i0_bp_index, ifu_i0_bp_fghr, ifu_i0_bp_btag, ifu_i0_bp_toffset};
         assign ifu_i1_brdata = {ifu_i1_bp_fa_index, ifu_i1_bp_index, ifu_i1_bp_fghr, ifu_i1_bp_btag, ifu_i1_bp_toffset};
      end
      else begin
         assign ifu_i0_brdata = {ifu_i0_bp_index, ifu_i0_bp_fghr, ifu_i0_bp_btag, ifu_i0_bp_toffset};
         assign ifu_i1_brdata = {ifu_i1_bp_index, ifu_i1_bp_fghr, ifu_i1_bp_btag, ifu_i1_bp_toffset};
      end

      assign bp3_in = ({BRWIDTH{write_i0_ib3}} & ifu_i0_brdata) |
                      ({BRWIDTH{write_i1_ib3}} & ifu_i1_brdata);

      assign bp3_final = (i1_cancel_e1) ? bp2 : bp3_in;

逐段解释：

* 第 L436-L443 行：``pt.BTB_FULLYA`` 决定 branch metadata 是否包含 fully-associative
  index。两个分支都把 IFU bp 字段打包成 ``ifu_i*_brdata``。
* 第 L445-L450 行：bp3 的写入选择与 ib3 对齐；cancel 时 bp3 取 bp2。
* 第 L453-L477 行：bp2、bp1、bp0 使用与 IB packet 相同的 shift/cancel 模式。
* 第 L479-L488 行：输出解包时，如果 ``pt.BTB_FULLYA`` 为 0，``i0_bp_fa_index`` 被置 0。

接口关系：

* 被调用：IB branch predictor 元数据路径。
* 调用：``rvdffe`` 保存 bp0-bp3。
* 共享状态：读取 ``pt.BTB_FULLYA`` 和 IFU bp 字段，输出 D-stage bp 字段。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L493-L536``）：

.. code-block:: systemverilog

      assign ib3_valid_d = ibval[3];
      assign ib2_valid_d = ibval[2];
      assign ib1_valid_d = ibval[1];
      assign ib0_valid_d = ibval[0];

      assign ib0_valid_in = ibval_in[0];

      assign i0_decode_d = dec_i0_decode_d & (tid == dec_i0_tid_d);
      assign i1_decode_d = dec_i1_decode_d & (tid == dec_i1_tid_d);

      assign shift1 = i0_decode_d ^ i1_decode_d;

      assign shift2 = i0_decode_d & i1_decode_d;

      assign shift0 = ~shift1 & ~shift2;

   // save off prior i1 on shift2

      rvdffibie #(.WIDTH($bits(eh2_ib_pkt_t)),.LEFT(24),.PADLEFT(13),.MIDDLE(31),.PADRIGHT(47),.RIGHT(16)) ibsaveff (.*, .en(shift2), .din(ib1),    .dout(ibsave));

      rvdffe #(BRWIDTH)         bpsaveindexff (.*, .en(shift2), .din(bp1),  .dout(bpsave));

逐段解释：

* 第 L493-L498 行：valid 输出直接来自 ``ibval``，``ib0_valid_in`` 来自下一状态。
* 第 L500-L507 行：只有当前 IB tid 与 decode 选中 tid 匹配时才认为 i0/i1 decode
  消费了本线程 slot；``shift1`` 表示消费一条，``shift2`` 表示消费两条。
* 第 L511-L513 行：消费两条时保存 ``ib1`` 和 ``bp1``。后续 ``i1_cancel_e1`` 可用
  ``ibsave`` 和 ``bpsave`` 恢复被取消的 lane。
* 第 L517-L536 行：``shift_ibval`` 基于 shift 结果计算写入空洞，再派生
  ``write_i*_ib*`` 和 ``shift_ib*_ib*`` 控制。

接口关系：

* 被调用：IB shift/write 控制。
* 调用：``rvdffibie`` 和 ``rvdffe`` 保存 cancel recovery 状态。
* 共享状态：读取 decode valid、tid、``ibval``，写 ``ibsave`` 和 ``bpsave``。

§4  ``eh2_dec_gpr_ctl.sv`` per-thread GPR
-----------------------------------------

``eh2_dec_gpr_ctl`` 是一个线程内 GPR 文件。源码只实现 x1 到 x31 的 31 个 32-bit
寄存器；x0 通过读数据默认清零和不生成寄存器实现。

§4.1  端口和寄存器阵列
~~~~~~~~~~~~~~~~~~~~~~

职责：提供 4 个读端口和 4 个写端口，每个端口都带 tid 或使用实例 tid 做 gating。

关键代码（``rtl/design/dec/eh2_dec_gpr_ctl.sv:L16-L77``）：

.. code-block:: systemverilog

   module eh2_dec_gpr_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )  (
       input logic       tid,

       input logic [4:0] raddr0,  // logical read addresses
       input logic [4:0] raddr1,
       input logic [4:0] raddr2,
       input logic [4:0] raddr3,

       input logic       rtid0,   // read tids
       input logic       rtid1,
       input logic       rtid2,
       input logic       rtid3,

       input logic       rden0,   // read enables
       input logic       rden1,
       input logic       rden2,

逐段解释：

* 第 L16-L20 行：GPR 模块导入 EH2 package 和参数文件。
* 第 L21-L36 行：读侧有 4 组 address、tid、enable，分别由顶层连接到 i0.rs1、
  i0.rs2、i1.rs1、i1.rs2。
* 第 L38-L56 行：写侧有 4 组 address、tid、enable、data，由顶层连接到 i0 WB、
  i1 WB、NB-load 和 DIV。
* 第 L69-L77 行：``gpr_out`` 和 ``gpr_in`` 只覆盖 ``[31:1]``，generate loop 也从
  1 到 31，源码中没有 x0 flop。

接口关系：

* 被调用：``eh2_dec`` per-thread ``arf`` generate。
* 调用：``rvdffe`` 保存每个 GPR。
* 共享状态：``tid`` 是实例固定线程号；读写端口携带动态 tid。

§4.2  读写 mux 和写碰撞断言
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：读端口用 OR-reduction mux 返回匹配寄存器；写端口为每个寄存器生成 one-hot
写使能和写数据。断言检查同一线程同周期多写端口写同一 GPR 的情况。

关键代码（``rtl/design/dec/eh2_dec_gpr_ctl.sv:L80-L110``）：

.. code-block:: systemverilog

   // the read out
      always_comb begin
         rd0[31:0] = 32'b0;
         rd1[31:0] = 32'b0;
         rd2[31:0] = 32'b0;
         rd3[31:0] = 32'b0;
         w0v[31:1] = 31'b0;
         w1v[31:1] = 31'b0;
         w2v[31:1] = 31'b0;
         w3v[31:1] = 31'b0;
         gpr_in[31:1] = '0;

         // GPR Read logic
         for (int j=1; j<32; j++ )  begin
            rd0[31:0] |= ({32{rden0 & (rtid0 == tid) & (raddr0[4:0]== 5'(j))}} & gpr_out[j][31:0]);
            rd1[31:0] |= ({32{rden1 & (rtid1 == tid) & (raddr1[4:0]== 5'(j))}} & gpr_out[j][31:0]);
            rd2[31:0] |= ({32{rden2 & (rtid2 == tid) & (raddr2[4:0]== 5'(j))}} & gpr_out[j][31:0]);
            rd3[31:0] |= ({32{rden3 & (rtid3 == tid) & (raddr3[4:0]== 5'(j))}} & gpr_out[j][31:0]);
        end

逐段解释：

* 第 L81-L90 行：读数据、写向量和写数据先清零。这也是 x0 读出为 0 的源码依据之一。
* 第 L93-L98 行：读逻辑遍历 x1 到 x31，只有读 enable、读 tid 等于实例 tid、
  读地址等于当前寄存器号时才 OR 进对应读数据。
* 第 L101-L110 行：写逻辑同样遍历 x1 到 x31，为四个写端口分别生成 ``w0v`` 至
  ``w3v``，再按端口选择写数据 OR 成 ``gpr_in[j]``。

接口关系：

* 被调用：GPR 组合读写准备逻辑。
* 调用：无下层模块。
* 共享状态：读取 ``gpr_out`` 和端口输入，生成 ``rd*``、``w*v``、``gpr_in``。

关键代码（``rtl/design/dec/eh2_dec_gpr_ctl.sv:L113-L125``）：

.. code-block:: systemverilog

   `ifdef RV_ASSERT_ON

      logic write_collision_unused;

      assign write_collision_unused = ( (w0v[31:1] == w1v[31:1]) & wen0 & wen1 & (wtid0==tid) & (wtid1==tid) ) |
                                      ( (w0v[31:1] == w2v[31:1]) & wen0 & wen2 & (wtid0==tid) & (wtid2==tid) ) |
                                      ( (w0v[31:1] == w3v[31:1]) & wen0 & wen3 & (wtid0==tid) & (wtid3==tid) ) |
                                      ( (w1v[31:1] == w2v[31:1]) & wen1 & wen2 & (wtid1==tid) & (wtid2==tid) ) |
                                      ( (w1v[31:1] == w3v[31:1]) & wen1 & wen3 & (wtid1==tid) & (wtid3==tid) ) |
                                      ( (w2v[31:1] == w3v[31:1]) & wen2 & wen3 & (wtid2==tid) & (wtid3==tid ));

      // asserting that no 2 ports will write to the same gpr simultaneously
      assert_multiple_wen_to_same_gpr: assert #0 (~( write_collision_unused ) );

逐段解释：

* 第 L113 行：写碰撞检查只在 ``RV_ASSERT_ON`` 下启用，不改变综合路径。
* 第 L117-L122 行：源码逐对比较四个写端口的写向量，并要求两个端口都写同一实例 tid。
* 第 L124-L125 行：断言名称为 ``assert_multiple_wen_to_same_gpr``，检查同周期不存在
  两个端口写同一 GPR。

接口关系：

* 被调用：仿真或形式检查在 ``RV_ASSERT_ON`` 时启用。
* 调用：SystemVerilog immediate assertion。
* 共享状态：读取 ``w*v``、``wen*``、``wtid*`` 和实例 ``tid``。

§5  ``eh2_dec_csr.sv`` CSR decode
---------------------------------

``eh2_dec_csr`` 是 CSR 地址译码器。它不保存 CSR architectural state；它根据
``dec_csr_rdaddr_d`` 生成合法性、presync/postsync 和 ``eh2_csr_tlu_pkt_t``，
再交给 TLU 控制器使用。

§5.1  生成方式和端口
~~~~~~~~~~~~~~~~~~~~

职责：声明 CSR decode 输入输出，并保留源码中用于生成 decode 方程的命令说明。

关键代码（``rtl/design/dec/eh2_dec_csr.sv:L25-L57``）：

.. code-block:: systemverilog

   module eh2_dec_csr
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (


   input logic [11:0] dec_csr_rdaddr_d,
   input logic dec_csr_any_unq_d,
   input logic dec_csr_wen_unq_d,
   input logic dec_tlu_dbg_halted,

   output logic dec_csr_legal_d,
   output logic tlu_presync_d,
   output logic tlu_postsync_d,

   output eh2_csr_tlu_pkt_t tlu_csr_pkt_d
   );


   // file "csrdecode" is human readable file that has all of the CSR decodes defined and is part of git repo
   // modify this file as needed

逐段解释：

* 第 L25-L30 行：CSR decode 模块同样使用 EH2 package 和参数文件。
* 第 L33-L42 行：输入只有 CSR 地址、CSR 是否存在、是否写和 debug halted 状态；
  输出包括合法性、presync/postsync 和传给 TLU 的 decode packet。
* 第 L46-L57 行：源码注释记录了 ``coredecode``、``espresso``、``addassign`` 的生成流程。
  本章只引用注释中的当前文件事实，不推断工具输出之外的 CSR 语义。

接口关系：

* 被调用：``eh2_dec_decode_ctl`` 通过 CSR decode packet 与 TLU 交互。
* 调用：本文件没有实例化下层模块。
* 共享状态：无 flop；只根据输入组合生成输出。

§5.2  CSR select 方程和同步属性
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为每个 CSR 生成 select bit，并生成 presync、postsync、glob 和 legal 等属性。

关键代码（``rtl/design/dec/eh2_dec_csr.sv:L61-L146``）：

.. code-block:: systemverilog

   logic csr_misa;
   logic csr_mvendorid;
   logic csr_marchid;
   logic csr_mimpid;
   logic csr_mhartid;
   logic csr_mstatus;
   logic csr_mtvec;
   logic csr_mip;
   logic csr_mie;
   logic csr_mcyclel;
   logic csr_mcycleh;
   logic csr_minstretl;
   logic csr_minstreth;
   logic csr_mscratch;
   logic csr_mepc;
   logic csr_mcause;
   logic csr_mscause;
   logic csr_mtval;
   logic csr_mrac;
   logic csr_dmst;
   logic csr_mdseac;
   logic csr_meihap;
   logic csr_meivt;
   logic csr_meipt;
   logic csr_meicurpl;

逐段解释：

* 第 L61-L88 行：源码声明了标准 machine CSR、debug CSR 和全局控制 CSR 的 select bit，
  例如 ``csr_mstatus``、``csr_mtvec``、``csr_dcsr``、``csr_mcgc``、``csr_mfdc``。
* 第 L91-L138 行：源码继续声明 trigger、performance counter、timer、cache diagnostic
  和 multi-hart 相关 CSR select bit。
* 第 L139-L146 行：``valid_only``、``presync``、``postsync``、``glob``、
  ``conditionally_illegal``、``valid_csr`` 和 ``legal`` 是对 CSR 访问属性的组合结果。

接口关系：

* 被调用：CSR decode 组合方程内部。
* 调用：无下层模块。
* 共享状态：读取 ``dec_csr_rdaddr_d`` 的 12-bit 地址。

关键代码（``rtl/design/dec/eh2_dec_csr.sv:L373-L400``）：

.. code-block:: systemverilog

   assign presync = (dec_csr_rdaddr_d[10]&dec_csr_rdaddr_d[4]&dec_csr_rdaddr_d[3]
       &!dec_csr_rdaddr_d[1]&dec_csr_rdaddr_d[0]) | (!dec_csr_rdaddr_d[7]
       &dec_csr_rdaddr_d[5]&!dec_csr_rdaddr_d[4]&!dec_csr_rdaddr_d[3]
       &!dec_csr_rdaddr_d[2]&!dec_csr_rdaddr_d[0]) | (dec_csr_rdaddr_d[5]
       &!dec_csr_rdaddr_d[4]&!dec_csr_rdaddr_d[3]&!dec_csr_rdaddr_d[2]
       &!dec_csr_rdaddr_d[1]&dec_csr_rdaddr_d[0]) | (!dec_csr_rdaddr_d[6]
       &!dec_csr_rdaddr_d[5]&!dec_csr_rdaddr_d[4]&!dec_csr_rdaddr_d[3]
       &!dec_csr_rdaddr_d[2]&dec_csr_rdaddr_d[1]) | (dec_csr_rdaddr_d[11]
       &!dec_csr_rdaddr_d[4]&!dec_csr_rdaddr_d[3]&dec_csr_rdaddr_d[1]
       &!dec_csr_rdaddr_d[0]) | (dec_csr_rdaddr_d[11]&!dec_csr_rdaddr_d[6]
       &!dec_csr_rdaddr_d[4]&!dec_csr_rdaddr_d[3]&dec_csr_rdaddr_d[2]
       &!dec_csr_rdaddr_d[1]) | (dec_csr_rdaddr_d[7]&!dec_csr_rdaddr_d[5]
       &!dec_csr_rdaddr_d[4]&!dec_csr_rdaddr_d[3]&!dec_csr_rdaddr_d[2]
       &dec_csr_rdaddr_d[1]);

逐段解释：

* 第 L373-L386 行：``presync`` 是若干地址位条件的 OR。源码没有在本文件中给出
  CSR 名称到每个 product term 的注释，因此文档只说明这是地址方程，不把每一项
  反推为人工命名的 CSR。
* 第 L388-L400 行：``postsync`` 使用同样形式的地址位 product-term OR。
  后续 ``tlu_postsync_d`` 会在 CSR 访问存在时使用该属性。

接口关系：

* 被调用：``tlu_presync_d`` 和 ``tlu_postsync_d`` 输出逻辑。
* 调用：无下层模块。
* 共享状态：读取 ``dec_csr_rdaddr_d``。

§5.3  合法性和 packet 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 raw legal 方程、debug-only 限制、配置相关限制和只读 CSR 写限制合成
``dec_csr_legal_d``，并把各 CSR select bit 打包给 TLU。

关键代码（``rtl/design/dec/eh2_dec_csr.sv:L515-L534``）：

.. code-block:: systemverilog

   //
      assign tlu_presync_d = presync & dec_csr_any_unq_d & ~dec_csr_wen_unq_d;
      assign tlu_postsync_d = postsync & dec_csr_any_unq_d;

      // allow individual configuration of these features
      assign conditionally_illegal = ((csr_mitcnt0 | csr_mitcnt1 | csr_mitb0 | csr_mitb1 | csr_mitctl0 | csr_mitctl1) & !pt.TIMER_LEGAL_EN) |
                                     (csr_meicpct & pt.FAST_INTERRUPT_REDIRECT);

      assign valid_csr = ( legal &
                           // not a debug only csr during running mode
                           (~(csr_dcsr | csr_dpc | csr_dmst | csr_dicawics | csr_dicad0 | csr_dicad0h | csr_dicad1 | csr_dicago) | dec_tlu_dbg_halted) &
                           // not conditionally illegal based on configuration
                           ~conditionally_illegal
                           );

      assign dec_csr_legal_d = ( dec_csr_any_unq_d &
                                 valid_csr &          // of a valid CSR
                                 ~(dec_csr_wen_unq_d & (csr_mvendorid | csr_marchid | csr_mimpid | csr_mhartid |
                                                        csr_mdseac | csr_meihap | csr_mhartnum)) // that's not a write to a RO CSR
                                 );

逐段解释：

* 第 L516-L517 行：presync 只在 CSR 访问存在且不是写时输出；postsync 在 CSR 访问存在时输出。
* 第 L520-L521 行：``conditionally_illegal`` 由 timer CSR 在 ``!pt.TIMER_LEGAL_EN``
  下非法，以及 ``csr_meicpct`` 在 ``pt.FAST_INTERRUPT_REDIRECT`` 下非法两类条件组成。
* 第 L523-L528 行：``valid_csr`` 要求 raw ``legal`` 为真，debug-only CSR 在运行态不可访问，
  且不触发配置相关非法条件。
* 第 L530-L534 行：最终 ``dec_csr_legal_d`` 还要求 CSR 操作存在，并排除对源码列出的
  只读 CSR 的写访问。

接口关系：

* 被调用：decode 控制用 ``dec_csr_legal_d`` 参与 instruction legal 判断。
* 调用：无下层模块。
* 共享状态：读取 ``pt.TIMER_LEGAL_EN``、``pt.FAST_INTERRUPT_REDIRECT`` 和
  ``dec_tlu_dbg_halted``。

关键代码（``rtl/design/dec/eh2_dec_csr.sv:L538-L612``）：

.. code-block:: systemverilog

      assign tlu_csr_pkt_d.csr_misa = csr_misa;
      assign tlu_csr_pkt_d.csr_mvendorid = csr_mvendorid;
      assign tlu_csr_pkt_d.csr_marchid = csr_marchid;
      assign tlu_csr_pkt_d.csr_mimpid = csr_mimpid;
      assign tlu_csr_pkt_d.csr_mhartid = csr_mhartid;
      assign tlu_csr_pkt_d.csr_mstatus = csr_mstatus;
      assign tlu_csr_pkt_d.csr_mtvec = csr_mtvec;
      assign tlu_csr_pkt_d.csr_mip = csr_mip;
      assign tlu_csr_pkt_d.csr_mie = csr_mie;
      assign tlu_csr_pkt_d.csr_mcyclel = csr_mcyclel;
      assign tlu_csr_pkt_d.csr_mcycleh = csr_mcycleh;
      assign tlu_csr_pkt_d.csr_minstretl = csr_minstretl;
      assign tlu_csr_pkt_d.csr_minstreth = csr_minstreth;
      assign tlu_csr_pkt_d.csr_mscratch = csr_mscratch;
      assign tlu_csr_pkt_d.csr_mepc = csr_mepc;
      assign tlu_csr_pkt_d.csr_mcause = csr_mcause;
      assign tlu_csr_pkt_d.csr_mscause = csr_mscause;

逐段解释：

* 第 L538-L570 行：CSR select bit 被逐项复制到 ``tlu_csr_pkt_d``，TLU 后续用 packet
  选择读数据、写寄存器和特殊副作用。
* 第 L571-L606 行：performance counter、timer/cache diagnostic、multi-hart 和 NMI
  delegation 相关 CSR select bit 也被复制到同一个 packet。
* 第 L607-L611 行：``valid_only``、``presync``、``postsync``、``glob`` 和 ``legal``
  作为访问属性随 packet 输出。

接口关系：

* 被调用：TLU CSR read mux 和 CSR write逻辑读取 ``eh2_csr_tlu_pkt_t``。
* 调用：无下层模块。
* 共享状态：输出 packet，不保存状态。

§6  ``eh2_dec_decode_ctl.sv`` decode 控制
--------------------------------------------------------

``eh2_dec_decode_ctl`` 是 DEC 中最大的控制模块。它从 IB/TLU/LSU/EXU/CSR/GPR
接口读入状态，生成 decode valid、block/stall、bypass、ALU packet、NB-load CAM、
DIV cancel 和 WB1 trace writeback mirror。

§6.1  端口覆盖的控制面
~~~~~~~~~~~~~~~~~~~~~~

职责：声明 decode 控制模块的输入输出边界，显示它同时管理 debug valid、CSR、
NB-load、trigger、TLU stall、trace disable 和 LSU/EXU 结果。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L17-L80``）：

.. code-block:: systemverilog

   module eh2_dec_decode_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic [pt.NUM_THREADS-1:0] active_thread_l2clk,

      input dec_i0_debug_valid_d,
      input dec_i1_debug_valid_d,

      input logic dec_i0_csr_global_d,

      input eh2_predecode_pkt_t dec_i0_predecode,
      input eh2_predecode_pkt_t dec_i1_predecode,

      input logic [pt.NUM_THREADS-1:0] dec_tlu_force_halt, // invalidate nonblock load cam on a force halt event

      input logic [pt.NUM_THREADS-1:0] dec_tlu_debug_stall, // stall decode while waiting on core to empty

      input logic [pt.NUM_THREADS-1:0] dec_tlu_flush_extint,

逐段解释：

* 第 L17-L23 行：decode control 使用参数化线程时钟输入。
* 第 L25-L31 行：D-stage debug valid、CSR global 属性和 i0/i1 predecode packet 是
  decode 控制的早期输入。
* 第 L33-L37 行：TLU force halt、debug stall 和 external interrupt flush 进入 decode，
  其中 force halt 在 NB-load CAM 中用于清空 CAM valid。
* 第 L65-L67 行：``dec_div_cancel`` 和 ``dec_div_cancel_overwrite`` 是输出端口；
  注释明确后者是 verification-only，用于区分 younger same-rd 覆盖导致的 cancel。
* 第 L73-L80 行：WB1 instruction/PC 和 ``dec_i1_cancel_e1`` 也是本模块输出。

接口关系：

* 被调用：``eh2_dec`` 实例化为 ``decode``。
* 调用：内部实例化 ``eh2_dec_cam``，并使用多个 ``rvdff*`` flop。
* 共享状态：连接 IFU/IB、TLU、LSU、EXU、GPR、CSR、trace 等多个接口。

§6.2  i0/i1 ALU packet
~~~~~~~~~~~~~~~~~~~~~~

职责：当对应 lane legal、ALU 类型且 valid 时，把 decode packet 中的操作码字段
复制到 ``eh2_alu_pkt_t``，并附带 tid、CSR 写信息、JAL 和 branch prediction 方向。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L960-L1016``）：

.. code-block:: systemverilog

      always_comb begin
         i0_ap = '0;

         i0_ap.tid = dd.i0tid;

         if (i0_dp.legal & i0_dp.alu & i0_valid_d) begin
            i0_ap.add =    i0_dp.add;
            i0_ap.sub =    i0_dp.sub;
            i0_ap.land =   i0_dp.land;
            i0_ap.lor =    i0_dp.lor;
            i0_ap.lxor =   i0_dp.lxor;
            i0_ap.sll =    i0_dp.sll;
            i0_ap.srl =    i0_dp.srl;
            i0_ap.sra =    i0_dp.sra;
            i0_ap.slt =    i0_dp.slt;
            i0_ap.unsign = i0_dp.unsign;
            i0_ap.beq =    i0_dp.beq;
            i0_ap.bne =    i0_dp.bne;
            i0_ap.blt =    i0_dp.blt;
            i0_ap.bge =    i0_dp.bge;

逐段解释：

* 第 L960-L964 行：``i0_ap`` 先清零，tid 来自 destination packet ``dd.i0tid``。
* 第 L965-L1004 行：只有 ``i0_dp.legal & i0_dp.alu & i0_valid_d`` 为真时，ALU、
  branch 和 bitmanip 相关字段才从 ``i0_dp`` 复制到 ``i0_ap``。
* 第 L1005-L1014 行：i0 还携带 ``csr_write``、``csr_imm``、``jal`` 和 prediction
  方向。

接口关系：

* 被调用：EXU 和 trigger 匹配器读取 ``i0_ap``。
* 调用：无下层模块。
* 共享状态：读取 ``i0_dp``、``i0_valid_d``、``dd.i0tid`` 和 branch prediction 信号。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L1025-L1081``）：

.. code-block:: systemverilog

      always_comb begin
         i1_ap = '0;

         i1_ap.tid = dd.i1tid;

         if (i1_dp.legal & i1_dp.alu & i1_valid_d) begin

            i1_ap.add =    i1_dp.add;
            i1_ap.sub =    i1_dp.sub;
            i1_ap.land =   i1_dp.land;
            i1_ap.lor =    i1_dp.lor;
            i1_ap.lxor =   i1_dp.lxor;
            i1_ap.sll =    i1_dp.sll;
            i1_ap.srl =    i1_dp.srl;
            i1_ap.sra =    i1_dp.sra;
            i1_ap.slt =    i1_dp.slt;
            i1_ap.unsign = i1_dp.unsign;
            i1_ap.beq =    i1_dp.beq;
            i1_ap.bne =    i1_dp.bne;
            i1_ap.blt =    i1_dp.blt;

逐段解释：

* 第 L1025-L1030 行：``i1_ap`` 也先清零，并使用 ``dd.i1tid``。
* 第 L1032-L1069 行：i1 ALU packet 复制常规 ALU、branch 和 bitmanip 字段。
* 第 L1071-L1072 行：i1 的 ``csr_write`` 和 ``csr_imm`` 被强制为 0，这是 i1 与 i0
  packet 的源码差异。
* 第 L1074-L1078 行：i1 仍携带 ``jal`` 和 prediction 方向。

接口关系：

* 被调用：EXU 和 trigger 匹配器读取 ``i1_ap``。
* 调用：无下层模块。
* 共享状态：读取 ``i1_dp``、``i1_valid_d``、``dd.i1tid`` 和 branch prediction 信号。

§6.3  i1 cancel
~~~~~~~~~~~~~~~

职责：检测 i0 load 与 i1 依赖关系，生成 ``i1_cancel_d``，再在 E1 级生成 per-thread
``dec_i1_cancel_e1``。源码对 DCCM/PIC 地址范围有额外 gating。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L1087-L1118``）：

.. code-block:: systemverilog

      assign i1_cancel_d = i0_dp.load & i1_depend_i0_d & i1_legal_decode_d & ~i0_br_error_all & ~i1_br_error_all;  // no decode if flush



      rvdffie #(pt.NUM_THREADS+18) misc1ff
        ( .*,
          .din({ i1_cancel_d,  dec_tlu_flush_extint[pt.NUM_THREADS-1:0], dec_i0_csr_ren_d,   i0_csr_clr_d,  i0_csr_set_d,  i0_csr_write_d,  i0_dp.csr_imm, div_active_in,
                 dec_i0_debug_valid_d, i0_debug_valid_e1, i0_debug_valid_e2, i0_debug_valid_e3, i0_debug_valid_e4,
                 dec_i0_branch_d, dec_i0_branch_e1, dec_i0_branch_e2, dec_i1_branch_d, dec_i1_branch_e1, dec_i1_branch_e2}),
          .dout({i1_cancel_e1,         flush_extint[pt.NUM_THREADS-1:0],     i0_csr_read_e1, i0_csr_clr_e1, i0_csr_set_e1, i0_csr_write_e1, i0_csr_imm_e1, div_active,
                 i0_debug_valid_e1,    i0_debug_valid_e2, i0_debug_valid_e3, i0_debug_valid_e4, i0_debug_valid_wb,
                 dec_i0_branch_e1, dec_i0_branch_e2, dec_i0_branch_e3, dec_i1_branch_e1, dec_i1_branch_e2, dec_i1_branch_e3})
          );

逐段解释：

* 第 L1087 行：``i1_cancel_d`` 的直接条件是 i0 为 load、i1 依赖 i0、i1 legal decode，
  且 i0/i1 都没有 branch error。
* 第 L1091-L1099 行：``misc1ff`` 把 ``i1_cancel_d`` 与 external interrupt flush、CSR、
  debug valid 和 branch stage 信号一起推进到后续阶段。
* 第 L1103-L1109 行：``dec_i1_cancel_e1`` 先清零，再只对 ``e1d.i1tid`` 设置。
  设置条件中排除了 DCCM region 且 DCCM enabled，或 PIC region；同时受
  ``flush_final_e3`` 和 ``flush_lower_wb`` gating。
* 第 L1114-L1118 行：NB-load 目的寄存器和 tid 也在这一附近从 E1/E2/WB 数据中导出。

接口关系：

* 被调用：IB 使用 ``dec_i1_cancel_e1`` 做 cancel recovery。
* 调用：``rvdffie`` 保存 E1 级控制。
* 共享状态：读取 load/依赖/branch error、LSU 地址、flush 状态和 E1 destination tid。

§6.4  block 和 stall packet
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 CSR、interrupt、debug、pause、postsync、presync、fence、NB-load、DIV、
load/store/AMO、MUL、secondary 和 same-thread 依赖等条件合成 i0/i1 block。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L1647-L1699``）：

.. code-block:: systemverilog

   always_comb begin
      i0blockp.csr_read_stall      = (i0_dp.csr_read & (dec_i0_csr_global_d ? prior_any_csr_write_any_thread : prior_csr_write[dd.i0tid])); // no csr bypass
      i0blockp.extint_stall        = (dec_extint_stall & i0_dp.lsu);     // 1 external interrupt per cycle, block both threads
      i0blockp.i1_cancel_e1_stall  = dec_i1_cancel_e1[dd.i0tid];                              // block i0 if same tid as i1_cancel_e1
      i0blockp.pause_stall         = pause_stall[dd.i0tid];
      i0blockp.leak1_stall         = leak1_i0_stall[dd.i0tid];                                // need 1 inst for debug single step
      i0blockp.debug_stall         = dec_tlu_debug_stall[dd.i0tid];                           // stop decode for db-halt request
      i0blockp.postsync_stall      = postsync_stall[dd.i0tid];
      i0blockp.presync_stall       = presync_stall[dd.i0tid];
      i0blockp.wait_lsu_idle_stall = ((i0_dp.fence | debug_fence | i0_dp.atomic) & ~lsu_idle[dd.i0tid]);   // fences only go out as i0 - presync'd
      i0blockp.nonblock_load_stall = cam_i0_nonblock_load_stall[dd.i0tid];
      i0blockp.nonblock_div_stall  = i0_nonblock_div_stall;
      i0blockp.prior_div_stall     = i0_div_prior_div_stall;
      i0blockp.load_stall          = i0_load_stall_d ;

逐段解释：

* 第 L1647-L1667 行：i0 block packet 覆盖 CSR read stall、external interrupt stall、
  i1 cancel stall、pause/debug/postsync/presync、等待 LSU idle、NB-load、DIV、
  load/store/AMO、MUL 和 secondary 条件。
* 第 L1668-L1689 行：i1 block packet 覆盖 debug valid、NB-load、atomic 等待 LSU idle、
  external interrupt、i1 cancel、pause/debug/postsync/presync、DIV、load/store/AMO、
  load2/mul2、secondary、leak1、i0-only、icaf 和 same-thread block。
* 第 L1697-L1699 行：``i0_block_d`` 和 ``i1_block_d`` 是对应 packet 的 reduction OR。

接口关系：

* 被调用：decode valid 生成逻辑读取 ``i0_block_d`` 和 ``i1_block_d``。
* 调用：无下层模块。
* 共享状态：读取 TLU stall、LSU idle/stall、NB-load CAM、DIV、predecode 和 dependency 状态。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L1701-L1745``）：

.. code-block:: systemverilog

      assign i1_depend_i0_case_d = (i1_depend_i0_d & ~non_block_case_d & ~store_data_bypass_i0_e2_c2);


      assign i1_block_same_thread_d =  i0_jal |               // all the i1 block cases for ST - none of these valid for MT

                                       i0_presync |
                                       i0_postsync |

                                       i0_dp.csr_read  |      // thread independent
                                       i0_dp.csr_write |

                                       dec_tlu_dual_issue_disable |

                                       i1_depend_i0_case_d |
                                       i0_icaf_d ;             // dont allow i1 decode if icaf in i0

逐段解释：

* 第 L1701 行：same-cycle i1 依赖 i0 的 block 会排除 ``non_block_case_d`` 和
  ``store_data_bypass_i0_e2_c2`` 两类源码允许的情况。
* 第 L1704-L1715 行：same-thread 下，i0 JAL、presync/postsync、CSR read/write、
  ``dec_tlu_dual_issue_disable``、i1 依赖 i0 和 i0 icaf 都会阻止 i1 同周期 decode。
* 第 L1721-L1745 行：``dec_thread_stall_in`` 汇总一拍/两拍的 MUL、secondary、CSR、
  atomic、DIV、pause、postsync、presync 和 NB-load stall，用于 SMT arbiter。

接口关系：

* 被调用：SMT arbiter 读取 ``dec_thread_stall_in``。
* 调用：无下层模块。
* 共享状态：读取 i0/i1 valid、tid、CSR、MUL、secondary、atomic、DIV、pause 和 CAM 状态。

§6.5  legal、decode valid 和非法指令捕获
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 predecode legal、CSR legal、bitmanip legal 和 atomic legal 合成 lane legal，
并捕获 i0 非法指令字用于 TLU。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L1973-L2022``）：

.. code-block:: systemverilog

      assign i0_legal = i0_dp.legal & (~i0_any_csr_d | i0_csr_legal_d) & i0_bitmanip_legal & i0_atomic_legal;

      assign i0_legal_except_csr = i0_dp.legal & i0_bitmanip_legal & i0_atomic_legal;

      assign i1_legal = i1_dp.legal            & i1_bitmanip_legal & i1_atomic_legal;


      // illegal inst handling

      assign i0_inst_d[31:0] = (dec_i0_pc4_d) ? i0[31:0] : {16'b0, dec_i0_cinst_d[15:0] };

      for (genvar i=0; i<pt.NUM_THREADS; i++) begin : illegal

         assign shift_illegal[i] = dec_i0_decode_d & ~i0_legal & (i == dd.i0tid);

         assign illegal_inst_en[i] = shift_illegal[i] & ~illegal_lockout[i];

逐段解释：

* 第 L1973-L1977 行：i0 legal 包含 CSR legal；``i0_legal_except_csr`` 去掉 CSR legal
  供 timing 相关路径使用；i1 legal 不包含 CSR legal，因为本源码中 i1 CSR 写字段被强制为 0。
* 第 L1982 行：非法指令捕获使用 32-bit instruction；如果 ``dec_i0_pc4_d`` 为 0，
  则使用 16-bit compressed instruction 扩展到低 16 位。
* 第 L1984-L1999 行：每个线程只在 ``dd.i0tid`` 匹配且 i0 decode 非法时捕获一次，
  ``illegal_lockout`` 防止重复覆盖，flush 会释放 lockout。
* 第 L2008-L2022 行：``dec_i0_decode_d`` 允许非法指令流入 pipe；i1 decode 在 same-thread
  情况下还要求 i0 decode 和 ``i0_legal_except_csr``。

接口关系：

* 被调用：TLU 使用 ``dec_illegal_inst`` 和 legal decode 结果处理 exception。
* 调用：``rvdffe`` 保存非法 instruction。
* 共享状态：读取 CSR legal、bitmanip/atomic legal、flush、tid 和 compressed instruction。

§6.6  bypass 网络
~~~~~~~~~~~~~~~~~

职责：为 D、E2、E3 stage 生成 bypass enable 和 data。源码按 depth 和 result class
选择 ALU、load、mul、secondary、WB、E4 或 NB-load 数据。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L2186-L2222``）：

.. code-block:: systemverilog

   // define bypasses for e2 stage - 1 is youngest

      assign dd.i0rs1bype2[1:0] = {  i0_dp.alu & i0_rs1_depth_d[3:0] == 4'd5 & i0_rs1_class_d.sec,
                                     i0_dp.alu & i0_rs1_depth_d[3:0] == 4'd6 & i0_rs1_class_d.sec };

      assign dd.i0rs2bype2[1:0] = {  i0_dp.alu & i0_rs2_depth_d[3:0] == 4'd5 & i0_rs2_class_d.sec,
                                     i0_dp.alu & i0_rs2_depth_d[3:0] == 4'd6 & i0_rs2_class_d.sec };

      assign dd.i1rs1bype2[1:0] = {  i1_dp.alu & i1_rs1_depth_d[3:0] == 4'd5 & i1_rs1_class_d.sec,
                                     i1_dp.alu & i1_rs1_depth_d[3:0] == 4'd6 & i1_rs1_class_d.sec };

      assign dd.i1rs2bype2[1:0] = {  i1_dp.alu & i1_rs2_depth_d[3:0] == 4'd5 & i1_rs2_class_d.sec,
                                     i1_dp.alu & i1_rs2_depth_d[3:0] == 4'd6 & i1_rs2_class_d.sec };

逐段解释：

* 第 L2186-L2198 行：E2 bypass 只在 lane 是 ALU 且源寄存器 depth 命中 5 或 6、
  class 为 secondary 时设置。
* 第 L2206-L2216 行：E2 bypass data 从 i1 或 i0 WB result 选择。
* 第 L2219-L2222 行：四个 E2 bypass enable 是对应 2-bit select 的 reduction OR。

接口关系：

* 被调用：EXU 源操作数选择读取 bypass enable/data。
* 调用：无下层模块。
* 共享状态：读取 scoreboard depth/class、lane 类型和 WB result。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L2228-L2278``）：

.. code-block:: systemverilog

      assign i1_rs1_depend_i0_d = dec_i1_rs1_en_d & i0_dp.rd & (i1r.rs1[4:0] == i0r.rd[4:0]) & (dd.i1tid == dd.i0tid);
      assign i1_rs2_depend_i0_d = dec_i1_rs2_en_d & i0_dp.rd & (i1r.rs2[4:0] == i0r.rd[4:0]) & (dd.i1tid == dd.i0tid);


   // i0
      assign dd.i0rs1bype3[3:0] = { i0_dp.alu & i0_rs1_depth_d[3:0]==4'd1 & (i0_rs1_class_d.sec | i0_rs1_class_d.load | i0_rs1_class_d.mul),
                                    i0_dp.alu & i0_rs1_depth_d[3:0]==4'd2 & (i0_rs1_class_d.sec | i0_rs1_class_d.load | i0_rs1_class_d.mul),
                                    i0_dp.alu & i0_rs1_depth_d[3:0]==4'd3 & (i0_rs1_class_d.sec | i0_rs1_class_d.load | i0_rs1_class_d.mul),
                                    i0_dp.alu & i0_rs1_depth_d[3:0]==4'd4 & (i0_rs1_class_d.sec | i0_rs1_class_d.load | i0_rs1_class_d.mul) };

      assign dd.i0rs2bype3[3:0] = { i0_dp.alu & i0_rs2_depth_d[3:0]==4'd1 & (i0_rs2_class_d.sec | i0_rs2_class_d.load | i0_rs2_class_d.mul),
                                    i0_dp.alu & i0_rs2_depth_d[3:0]==4'd2 & (i0_rs2_class_d.sec | i0_rs2_class_d.load | i0_rs2_class_d.mul),

逐段解释：

* 第 L2228-L2229 行：i1 intra-lane dependency 只在 rs enable、i0 有 rd、源/目的寄存器相同且
  i0/i1 tid 相同时成立。
* 第 L2233-L2241 行：i0 E3 bypass 根据 depth 1-4 和 sec/load/mul class 生成 select。
* 第 L2245-L2257 行：i1 先判断是否能从同周期 i0 的 ALU/MUL/load 路径 intra-bypass。
* 第 L2260-L2278 行：i1 E3 bypass select 把 intra-bypass 放在高位，再加入 depth 1-4
  的外部 bypass；enable 是 7-bit select 的 reduction OR。

接口关系：

* 被调用：E3 operand 选择路径。
* 调用：无下层模块。
* 共享状态：读取 register packet、destination packet、scoreboard depth/class 和 lane 类型。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L2287-L2308``）：

.. code-block:: systemverilog

      assign i0_rs1_bypass_data_e3[31:0] = ({32{e3d.i0rs1bype3[3]}} & i1_result_e4_eff[31:0]) |
                                           ({32{e3d.i0rs1bype3[2]}} & i0_result_e4_eff[31:0]) |
                                           ({32{e3d.i0rs1bype3[1]}} & i1_result_wb_eff[31:0]) |
                                           ({32{e3d.i0rs1bype3[0]}} & i0_result_wb_eff[31:0]);

      assign i0_rs2_bypass_data_e3[31:0] = ({32{e3d.i0rs2bype3[3]}} & i1_result_e4_eff[31:0]) |
                                           ({32{e3d.i0rs2bype3[2]}} & i0_result_e4_eff[31:0]) |
                                           ({32{e3d.i0rs2bype3[1]}} & i1_result_wb_eff[31:0]) |
                                           ({32{e3d.i0rs2bype3[0]}} & i0_result_wb_eff[31:0]);

      assign i1_rs1_bypass_data_e3[31:0] = ({32{e3d.i1rs1bype3[6]}} & i0_result_e3[31:0]) |
                                           ({32{e3d.i1rs1bype3[5]}} & exu_mul_result_e3[31:0]) |
                                           ({32{e3d.i1rs1bype3[4]}} & lsu_result_dc3[31:0]) |

逐段解释：

* 第 L2287-L2295 行：i0 E3 bypass data 从 i1 E4、i0 E4、i1 WB、i0 WB 四个结果源选择。
* 第 L2297-L2308 行：i1 E3 bypass data 增加了 intra-bypass 源：i0 E3 result、
  ``exu_mul_result_e3`` 和 ``lsu_result_dc3``。
* 第 L3121-L3228 行：D-stage 还有 10-bit bypass mux，最低优先级 fallback 可选
  ``lsu_nonblock_load_data``，并通过 ``dec_i*_rs*_bypass_en_d`` 输出 enable。

接口关系：

* 被调用：EXU D/E2/E3 operand mux。
* 调用：无下层模块。
* 共享状态：读取 E3/E4/WB result、LSU DC3 result、MUL E3 result 和 NB-load data。

§6.7  nonblocking DIV 和 result/trace pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：跟踪非阻塞 DIV 的目的寄存器和 tid，检测依赖 stall 和 younger same-rd 覆盖，
并把 result 与 trace instruction/PC/writeback mirror 推到 WB1。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L2925-L2967``）：

.. code-block:: systemverilog

      assign div_active_in = i0_div_decode_d | (div_active & ~exu_div_wren & ~nonblock_div_cancel);


      assign dec_div_active = div_active;
      assign dec_div_tid = div_tid;

      assign div_stall = div_active;
      assign div_valid = div_active;

   // nonblocking div scheme

   // divides must go down as i0; i1 will not go same cycle if dependent on i0 and same tid as i0 div

   // after div reaches wb if any inst writes to same dest on subsequent cycles and same tid as div then div is canceled

      assign i0_nonblock_div_stall  = (dec_i0_rs1_en_d & (dd.i0tid == div_tid) & div_valid & (div_rd[4:0] == i0r.rs1[4:0])) |
                                      (dec_i0_rs2_en_d & (dd.i0tid == div_tid) & div_valid & (div_rd[4:0] == i0r.rs2[4:0]));

逐段解释：

* 第 L2925-L2932 行：DIV active 在新 i0 DIV decode 时置位，直到 EXU DIV 写回或
  nonblock DIV cancel。``dec_div_active`` 和 ``dec_div_tid`` 对外输出当前状态。
* 第 L2934-L2938 行：源码注释说明 DIV 必须作为 i0 下发，并且 younger same-rd
  写回会取消已到 WB 后的 DIV。
* 第 L2940-L2944 行：i0/i1 的 nonblock DIV stall 分别检查源寄存器是否与当前 DIV
  目的寄存器相同，且 tid 相同。
* 第 L2949-L2962 行：cancel 分为 flush cancel 和 overwrite cancel；后者驱动
  verification-only ``dec_div_cancel_overwrite``。
* 第 L2964-L2967 行：i0 legal decode 且 i0 是 DIV 时，保存 ``i0r.rd`` 和 ``dd.i0tid``。

接口关系：

* 被调用：EXU DIV、cosim trace 侧信号和 decode stall 读取 DIV 状态。
* 调用：``rvdffe`` 保存 DIV rd/tid。
* 共享状态：读取 ``exu_div_wren``、WB destination、WB write enable、flush 和 i0 decode。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L2971-L3000``）：

.. code-block:: systemverilog

      assign i0_result_e1[31:0] = exu_i0_result_e1[31:0];
      assign i1_result_e1[31:0] = exu_i1_result_e1[31:0];

      // pipe the results down the pipe
      // i0 has i0csrwen and debug instructions
      rvdffe #(32) i0e2resultff (.*, .en(i0_e2_data_en & (e1d.i0v | e1d.i0csrwen | i0_debug_valid_e1)),  .din(i0_result_e1[31:0]), .dout(i0_result_e2[31:0]));
      rvdffe #(32) i1e2resultff (.*, .en(i1_e2_data_en &  e1d.i1v),                                      .din(i1_result_e1[31:0]), .dout(i1_result_e2[31:0]));

      rvdffe #(32) i0e3resultff (.*, .en(i0_e3_data_en & (e2d.i0v | e2d.i0csrwen | i0_debug_valid_e2)),  .din(i0_result_e2[31:0]), .dout(i0_result_e3[31:0]));
      rvdffe #(32) i1e3resultff (.*, .en(i1_e3_data_en &  e2d.i1v),                                      .din(i1_result_e2[31:0]), .dout(i1_result_e3[31:0]));

      assign i0_result_e3_final[31:0] = (e3d.i0v & e3d.i0load) ? lsu_result_dc3[31:0] : (e3d.i0v & e3d.i0mul) ? exu_mul_result_e3[31:0] : i0_result_e3[31:0];

      assign i1_result_e3_final[31:0] = (e3d.i1v & e3d.i1load) ? lsu_result_dc3[31:0] : (e3d.i1v & e3d.i1mul) ? exu_mul_result_e3[31:0] : i1_result_e3[31:0];

逐段解释：

* 第 L2971-L2980 行：EXU E1 result 通过 E2/E3 flop 推进；i0 enable 包含 CSR 写和
  debug valid，i1 enable 只使用 i1 valid。
* 第 L2982-L2984 行：E3 final result 对 load 选择 ``lsu_result_dc3``，对 MUL 选择
  ``exu_mul_result_e3``，否则保留 ALU pipeline result。
* 第 L2986-L3000 行：E4/WB result 继续推进，E4 final 对 secondary 和 load corrected
  data 做选择，SC 写回数据由 ``lsu_sc_success_dc5`` 生成 0/1 结果。

接口关系：

* 被调用：GPR writeback 和 bypass 网络读取 result pipeline。
* 调用：``rvdffe`` result flops。
* 共享状态：读取 EXU、LSU、MUL、SC 和 pipeline valid。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L3003-L3071``）：

.. code-block:: systemverilog

      logic trace_enable;

      assign trace_enable = ~dec_tlu_trace_disable;

      rvdffe #(32) i0e1instff  (.*, .en(i0_e1_data_en & trace_enable),  .din(i0_inst_d[31:0] ), .dout(i0_inst_e1[31:0]));
      rvdffe #(32) i0e2instff  (.*, .en(i0_e2_data_en & trace_enable),  .din(i0_inst_e1[31:0]), .dout(i0_inst_e2[31:0]));
      rvdffe #(32) i0e3instff  (.*, .en(i0_e3_data_en & trace_enable),  .din(i0_inst_e2[31:0]), .dout(i0_inst_e3[31:0]));
      rvdffe #(32) i0e4instff  (.*, .en(i0_e4_data_en & trace_enable),  .din(i0_inst_e3[31:0]), .dout(i0_inst_e4[31:0]));
      rvdffe #(32) i0wbinstff  (.*, .en(i0_wb_data_en & trace_enable),  .din(i0_inst_e4[31:0]), .dout(i0_inst_wb[31:0] ));
      rvdffe #(32) i0wb1instff (.*, .en(i0_wb1_data_en & trace_enable), .din(i0_inst_wb[31:0]), .dout(i0_inst_wb1[31:0]));

逐段解释：

* 第 L3003-L3005 行：trace pipeline enable 直接是 ``~dec_tlu_trace_disable``。
* 第 L3007-L3021 行：i0/i1 instruction 分别经过 E1、E2、E3、E4、WB、WB1。
  i1 在进入 pipeline 前也根据 ``dec_i1_pc4_d`` 选择 32-bit 或 compressed 扩展指令。
* 第 L3023-L3032 行：WB1 instruction 和 PC 输出给 DEC 顶层 trace packet。
* 第 L3034-L3048 行：源码注释说明 verification-only WB1 mirror 与物理 RF write enable
  故意不同，用于让 cosim 按 ISA 语义观察每条指令的写回。
* 第 L3049-L3071 行：i0/i1 architectural writeback enable、rd 和 data 被打包到 38-bit
  flop，再拆成 ``dec_i*_wen_wb1``、``dec_i*_waddr_wb1``、``dec_i*_wdata_wb1``。

接口关系：

* 被调用：``eh2_dec`` 顶层 trace packet 读取 WB1 outputs。
* 调用：``rvdffe`` instruction、PC 和 writeback mirror flops。
* 共享状态：读取 TLU kill、load-kill、DIV、WB destination/result 和 trace disable。

§6.8  NB-load CAM
~~~~~~~~~~~~~~~~~

职责：``eh2_dec_cam`` 跟踪 nonblocking load 的 tag、rd 和 valid 状态，检测源寄存器依赖、
数据返回、作废、force halt 和 younger same-rd cancel。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L3235-L3296``）：

.. code-block:: systemverilog

   module eh2_dec_cam
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )  (
      input logic  clk,
      input logic  scan_mode,
      input logic  rst_l,

      input logic  active_clk,

      input logic flush,
      input logic  tid,

      input logic dec_tlu_i0_kill_writeb_wb,
      input logic dec_tlu_i1_kill_writeb_wb,

      input logic dec_tlu_force_halt,

      input logic                                lsu_nonblock_load_data_tid,

逐段解释：

* 第 L3235-L3247 行：NB-load CAM 是 ``eh2_dec_decode_ctl.sv`` 内的独立 module，
  使用 ``flush`` 和实例 ``tid`` 区分线程。
* 第 L3249-L3254 行：TLU kill writeback、force halt 和 LSU data tid 是 CAM 的控制输入。
* 第 L3261-L3273 行：CAM 接收 LSU nonblock load valid/tag、DC2/DC5 invalidate、
  data valid/error 和 data tag。
* 第 L3288-L3295 行：CAM 输出 load completion write address/write enable、i0/i1 stall、
  load-kill write enable 和汇总 stall。

接口关系：

* 被调用：decode control 为每个线程实例化 CAM。
* 调用：内部使用 ``rvdffie`` 和 ``rvdff``。
* 共享状态：维护 per-thread ``eh2_load_cam_pkt_t`` 数组。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L3324-L3365``）：

.. code-block:: systemverilog

      always_comb begin
         found = 0;
         for (int i=0; i<NBLOAD_SIZE; i++) begin
            if (~found) begin
               if (~cam[i].valid) begin
                  cam_wen[i] = cam_write;  // cam_write is threaded
                  found = 1'b1;
               end
               else begin
                cam_wen[i] = 0;
               end
            end
            else
                cam_wen[i] = 0;
         end
      end

逐段解释：

* 第 L3324-L3339 行：CAM 写入选择第一个 invalid entry。``found`` 保证同周期最多选择
  一个 entry，``cam_write`` 已经按线程限定。
* 第 L3342-L3349 行：同一 WB 周期 i0/i1 写同一目的且旧 load 到 WB 时会触发
  ``cam_reset_same_dest_wb``；新 CAM write 来自 ``lsu_nonblock_load_valid_dc1`` 且 tid 匹配。
* 第 L3351-L3365 行：DC2/DC5 invalidate 和 data valid/error reset 都按 tid 和 tag 生成。

接口关系：

* 被调用：CAM entry 状态更新。
* 调用：无下层模块。
* 共享状态：读取 ``cam``、LSU tag、WB destination 和 tid。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L3380-L3428``）：

.. code-block:: systemverilog

      for (genvar i=0; i<NBLOAD_SIZE; i++) begin : cam_array

         assign cam_inv_dc2_reset_val[i] = cam_inv_dc2_reset   & (cam_inv_dc2_reset_tag[NBLOAD_TAG_MSB:0]  == cam[i].tag[NBLOAD_TAG_MSB:0]) & cam[i].valid;

         assign cam_inv_dc5_reset_val[i] = cam_inv_dc5_reset   & (cam_inv_dc5_reset_tag[NBLOAD_TAG_MSB:0]  == cam[i].tag[NBLOAD_TAG_MSB:0]) & cam[i].valid;

         assign cam_data_reset_val[i] = cam_data_reset & (cam_data_reset_tag[NBLOAD_TAG_MSB:0] == cam_raw[i].tag[NBLOAD_TAG_MSB:0]) & cam_raw[i].valid;

         always_comb begin

            cam[i] = cam_raw[i];

            if (pt.LOAD_TO_USE_BUS_PLUS1==0 & cam_data_reset_val[i])
              cam[i].valid = 1'b0;

逐段解释：

* 第 L3380-L3387 行：每个 CAM entry 根据 DC2 invalidate、DC5 invalidate 和 data reset
  tag 匹配生成 reset 条件。
* 第 L3388-L3403 行：entry 默认从 ``cam_raw`` 继承；写入时设置 valid、清 stall/wb，
  保存 tag 和 ``nonblock_load_rd``。
* 第 L3404-L3409 行：invalidate、LOAD_TO_USE_BUS_PLUS1 data reset、或 WB 同目的写回
  会清 valid。
* 第 L3411-L3417 行：nonblock load 到 WB 时标记 ``wb``；``dec_tlu_force_halt`` 具有最高优先级，
  强制清 valid。
* 第 L3419-L3428 行：flush 清 stall；当前 decode 源寄存器命中 CAM rd 时设置 stall，
  ``rvdffie`` 保存 entry。

接口关系：

* 被调用：CAM entry array。
* 调用：``rvdffie`` 保存 ``cam_raw``。
* 共享状态：读写 ``cam_raw``、``cam_in``、``cam``。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L3442-L3491``）：

.. code-block:: systemverilog

      assign nonblock_load_cancel = ((wbd.i0rd[4:0] == nonblock_load_waddr[4:0]) & (wbd.i0tid == tid) & (wbd.i0tid == lsu_nonblock_load_data_tid) & i0_wen_wb) |    // cancel if any younger inst (including another nonblock) committing this cycle
                                    ((wbd.i1rd[4:0] == nonblock_load_waddr[4:0]) & (wbd.i1tid == tid) & (wbd.i1tid == lsu_nonblock_load_data_tid) & i1_wen_wb);

      // threaded
      assign nonblock_load_wen = lsu_nonblock_load_data_valid & (lsu_nonblock_load_data_tid == tid) & |nonblock_load_write[NBLOAD_SIZE_MSB:0] & ~nonblock_load_cancel;

      always_comb begin
         nonblock_load_waddr[4:0] = '0;

         nonblock_load_stall = '0;

         i0_nonblock_load_stall = i0_nonblock_boundary_stall;
         i1_nonblock_load_stall = i1_nonblock_boundary_stall;

逐段解释：

* 第 L3442-L3446 行：如果 younger WB 同周期写同一目的寄存器且 tid 匹配，
  nonblock load completion 被 cancel；否则数据返回有效且 tag 命中时产生
  ``nonblock_load_wen``。
* 第 L3448-L3468 行：输出写地址由命中的 CAM entry rd OR 得到；i0/i1 stall 检查当前
  decode 源寄存器是否命中有效 CAM entry。
* 第 L3470-L3475 行：boundary stall 检查本周期新写入 CAM 的 rd 是否正好被当前 decode
  源寄存器读取。
* 第 L3477-L3491 行：CAM 还生成 load-kill write enable，用于避免正常 load 写回与
  nonblock load 语义冲突。

接口关系：

* 被调用：GPR NB-load 写端口和 decode stall 读取 CAM 输出。
* 调用：``rvdff`` 推进 nonblock load valid 到 WB。
* 共享状态：读取 LSU data valid/tag、WB destination/write enable 和 CAM entry。

§7  ``eh2_dec_tlu_top.sv`` TLU 顶层
--------------------------------------------------------

``eh2_dec_tlu_top`` 是 TLU 集成层。它同步 NMI，按线程实例化 ``eh2_dec_tlu_ctl``，
聚合 per-thread 输出，并维护 MCGC、MFDC 等全局 CSR。

§7.1  端口和 NMI 同步
~~~~~~~~~~~~~~~~~~~~~

职责：声明 TLU 顶层端口，接入 reset/NMI/halt/run、PMU、CSR、LSU/IFU/EXU 和 PIC 信号；
并在进入 per-thread TLU 前同步 NMI。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L26-L47``）：

.. code-block:: systemverilog

   module eh2_dec_tlu_top
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic clk,
      input logic free_clk,
      input logic active_clk,
      input logic free_l2clk,
      input logic [pt.NUM_THREADS-1:0] active_thread_l2clk,
      input logic rst_l,
      input logic scan_mode,

      input logic [31:1] rst_vec, // reset vector, from core pins
      input logic        nmi_int, // nmi pin
      input logic [31:1] nmi_vec, // nmi vector
      input logic  [pt.NUM_THREADS-1:0] i_cpu_halt_req,    // Asynchronous Halt request to CPU
      input logic  [pt.NUM_THREADS-1:0] i_cpu_run_req,     // Asynchronous Restart request to CPU

逐段解释：

* 第 L26-L38 行：TLU 顶层使用多个时钟输入和 per-thread active clock。
* 第 L40-L44 行：reset vector、NMI、CPU halt/run request 是 TLU 顶层早期输入。
* 第 L49-L80 行：源码随后列出 PMU 事件输入，覆盖 decode、IFU、LSU、EXU 和 DMA 事件。
* 第 L89-L108 行：TLU 还接收 decode trap packet、LSU error packet 和 CSR 访问地址/数据。

接口关系：

* 被调用：``eh2_dec`` 实例化为 ``tlu``。
* 调用：后续实例化 per-thread ``eh2_dec_tlu_ctl``。
* 共享状态：连接 trap、interrupt、debug、CSR、PMU 和 trace 元数据。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L420-L426``）：

.. code-block:: systemverilog

      rvsyncss #(1) syncro_ff(.*,
                              .clk(free_clk),
                              .din ({nmi_int    }),
                              .dout({nmi_int_sync_raw}));

      // If SW is writing the nmipdel register, hold off nmis for a cycle
      assign nmi_int_sync = nmi_int_sync_raw & ~dec_csr_nmideleg_e4;

逐段解释：

* 第 L420-L423 行：NMI pin 通过 ``rvsyncss`` 同步到 ``free_clk`` 域。
* 第 L425-L426 行：当软件正在写 ``nmipdel`` 对应 CSR 时，``nmi_int_sync`` 会被
  ``dec_csr_nmideleg_e4`` gating 一拍。

接口关系：

* 被调用：per-thread TLU 控制器读取 ``nmi_int_sync``。
* 调用：``rvsyncss`` 同步器。
* 共享状态：读取 ``nmi_int`` 和 ``dec_csr_nmideleg_e4``。

§7.2  per-thread TLU 实例和聚合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 ``pt.NUM_THREADS`` 实例化 ``eh2_dec_tlu_ctl``，把 per-thread 输入切片后送入
各实例，并把 per-thread 输出聚合为 DEC 对外信号。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L431-L555``）：

.. code-block:: systemverilog

     for (genvar i=0; i<pt.NUM_THREADS; i++) begin : tlumt
        eh2_dec_tlu_ctl #(.pt(pt)) tlu (//inputs
                                         .clk           (active_thread_l2clk[i]),
                                         .mytid               (1'(i)),
                                         .exu_i0_flush_path_e4(exu_i0_flush_path_e4[31:1] & {31{exu_i0_flush_lower_e4[i]}}),
                                         .exu_i1_flush_path_e4(exu_i1_flush_path_e4[31:1] & {31{exu_i1_flush_lower_e4[i]}}),
                                         .dec_div_active(dec_div_active & (dec_div_tid == i)),
                                         .i_cpu_run_req(i_cpu_run_req[i] & mhartstart[i]),
                                         .i_cpu_halt_req(i_cpu_halt_req[i] & mhartstart[i]),
                                         .mpc_debug_halt_req(mpc_debug_halt_req[i] & mhartstart[i]),
                                         .mpc_debug_run_req(mpc_debug_run_req[i] & mhartstart[i]),
                                         .mpc_reset_run_req(mpc_reset_run_req[i]),
                                         .dbg_halt_req(dbg_halt_req[i]),
                                         .dbg_resume_req(dbg_resume_req[i] & mhartstart[i]),
                                         .exu_npc_e4(exu_npc_e4[i]),
                                         .lsu_store_stall_any(lsu_store_stall_any[i]),

逐段解释：

* 第 L431-L434 行：每个线程一个 ``eh2_dec_tlu_ctl``，使用对应线程 clock 和 ``mytid``。
* 第 L435-L437 行：EXU flush path 只有在对应线程 flush lower 时传入；DIV active 也按
  ``dec_div_tid == i`` 限定。
* 第 L438-L445 行：CPU halt/run、MPC debug halt/run、debug halt/resume 都按线程切片，
  部分请求还受 ``mhartstart[i]`` gating。
* 第 L451-L488 行：IFU/LSU/DEC/PMU/PIC/interruption 输入按线程传入。
* 第 L500-L555 行：实例输出包括 performance counter、trace valid/exception/int、
  CSR read data、debug status、flush、halt、trigger packet 和 writeback kill。

接口关系：

* 被调用：``eh2_dec_tlu_top`` generate。
* 调用：``eh2_dec_tlu_ctl``。
* 共享状态：读写 per-thread arrays，如 ``dec_tlu_i0_valid_wb1``、``trigger_pkt_any``、
  ``dec_tlu_flush_lower_wb``。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L558-L574``）：

.. code-block:: systemverilog

      assign dec_tlu_meihap = dec_tlu_meihap_thr[tlu_select_tid_f2];

      assign dec_tlu_ic_diag_pkt = dec_tlu_ic_diag_pkt_thr[dec_i0_tid_d_f];

      // tid specific signals to pipe specific conversion
      assign dec_tlu_i0_kill_writeb_wb = |tlu_i0_kill_writeb_wb_thr[pt.NUM_THREADS-1:0];
      assign dec_tlu_i1_kill_writeb_wb = |tlu_i1_kill_writeb_wb_thr[pt.NUM_THREADS-1:0];
      assign dec_tlu_i0_commit_cmt[pt.NUM_THREADS-1:0] = tlu_i0_commit_cmt_thr[pt.NUM_THREADS-1:0];


      assign dec_tlu_core_empty = &dec_tlu_core_empty_thr[pt.NUM_THREADS-1:0];

      assign dec_dbg_cmd_tid = ~dec_dbg_cmd_done_thr[0];
      assign dec_dbg_cmd_done = |dec_dbg_cmd_done_thr[pt.NUM_THREADS-1:0];
      assign dec_dbg_cmd_fail = |dec_dbg_cmd_fail_thr[pt.NUM_THREADS-1:0];
      assign ic_perr_wb_all = |ic_perr_wb_thr[pt.NUM_THREADS-1:0];
      assign iccm_sbecc_wb_all = |iccm_sbecc_wb_thr[pt.NUM_THREADS-1:0];

逐段解释：

* 第 L558-L560 行：``meihap`` 和 IC diagnostic packet 从选中线程数组中取出。
* 第 L563-L568 行：i0/i1 kill writeback 通过 OR 聚合；``dec_tlu_core_empty`` 通过所有线程
  core empty 的 AND 聚合。
* 第 L570-L574 行：debug command done/fail 和 ECC error 标志通过 per-thread OR 聚合；
  ``dec_dbg_cmd_tid`` 由线程 0 done 状态反向推导。

接口关系：

* 被调用：DEC 顶层和 debug/trace 逻辑读取这些聚合输出。
* 调用：无下层模块。
* 共享状态：读取 per-thread TLU outputs。

§7.3  branch update、MCGC 和 MFDC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 TLU 顶层处理 branch predictor 更新 packet，并维护全局 MCGC/MFDC CSR 输出。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L582-L660``）：

.. code-block:: systemverilog

      assign dec_tlu_br0_addr_e4[pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] = exu_i0_br_index_e4[pt.BTB_ADDR_HI:pt.BTB_ADDR_LO];
      assign dec_tlu_br0_bank_e4 = exu_i0_br_bank_e4;
      assign dec_tlu_br1_addr_e4[pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] = exu_i1_br_index_e4[pt.BTB_ADDR_HI:pt.BTB_ADDR_LO];
      assign dec_tlu_br1_bank_e4 = exu_i1_br_bank_e4;

      // go ahead and repair the branch error on other flushes, doesn't have to be the rfpc flush
      assign dec_tlu_br0_error_e4 = exu_i0_br_error_e4 & dec_tlu_i0_valid_e4 & ~dec_tlu_flush_lower_wb[dec_tlu_packet_e4.i0tid];
      assign dec_tlu_br0_start_error_e4 = exu_i0_br_start_error_e4 & dec_tlu_i0_valid_e4 & ~dec_tlu_flush_lower_wb[dec_tlu_packet_e4.i0tid];
      assign dec_tlu_br0_v_e4 = exu_i0_br_valid_e4 & dec_tlu_i0_valid_e4 & ~dec_tlu_flush_lower_wb[dec_tlu_packet_e4.i0tid] & ~exu_i0_br_mp_e4;

      assign dec_tlu_br1_error_e4 = exu_i1_br_error_e4 & dec_tlu_i1_valid_e4 & ~dec_tlu_flush_lower_wb[dec_tlu_packet_e4.i1tid] & ~br0_mp_e4_thr[dec_tlu_packet_e4.i1tid];

逐段解释：

* 第 L582-L585 行：i0/i1 branch update 地址和 bank 来自 EXU E4 branch info。
* 第 L587-L594 行：branch error、start error 和 valid 会受 lane valid、flush lower、
  branch mispredict 和同线程 i0 mispredict gating。
* 第 L596-L607 行：tid selection flop 使用 ``free_clk``，源码注释说明 active clock 对
  fast interrupt sleep 场景下的 tid pick 太慢。
* 第 L610-L660 行：branch update packet 用 ``rvdffe`` 在变化时保存，并附加 i0/i1 WB tid。

接口关系：

* 被调用：branch predictor 更新逻辑读取 ``dec_tlu_br*_wb_pkt``。
* 调用：``rvdff`` 和 ``rvdffe`` 保存 tid 和 branch packet。
* 共享状态：读取 EXU branch E4 输入、TLU flush、thread id 和 branch history。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L680-L745``）：

.. code-block:: systemverilog

      localparam MCGC          = 12'h7f8;
      assign wr_mcgc_wb = dec_i0_csr_wen_wb_mod_thr[i0tid_wb] & (dec_i0_csr_wraddr_wb[11:0] == MCGC);

      assign mcgc_ns[9:0] = wr_mcgc_wb ? {~dec_i0_csr_wrdata_wb[9], dec_i0_csr_wrdata_wb[8:0]} : mcgc_int[9:0];
      rvdffe #(10)  mcgc_ff (.*, .en(wr_mcgc_wb), .din(mcgc_ns[9:0]), .dout(mcgc_int[9:0]));

      assign mcgc[9:0] = {~mcgc_int[9], mcgc_int[8:0]};

      assign dec_tlu_picio_clk_override= mcgc[9];
      assign dec_tlu_misc_clk_override = mcgc[8];
      assign dec_tlu_dec_clk_override  = mcgc[7];
      assign dec_tlu_exu_clk_override  = mcgc[6];
      assign dec_tlu_ifu_clk_override  = mcgc[5];

逐段解释：

* 第 L680-L684 行：MCGC 地址为 ``12'h7f8``，写使能来自对应 WB tid 的 CSR write
  和写地址比较；bit 9 在写入内部寄存器时取反。
* 第 L686-L697 行：读出 ``mcgc`` 时 bit 9 再取反，并分配到 picio、misc、dec、exu、
  ifu、lsu、bus、pic、dccm、icm clock override 输出。
* 第 L716-L735 行：MFDC 地址为 ``12'h7f9``，源码对 ``pt.BUILD_AXI4 == 1`` 的 bit 6
  power-on value 路径单独处理。
* 第 L737-L745 行：MFDC 输出 DMA QoS、trace disable、external load forwarding disable、
  dual issue disable、core ECC disable、sideeffect posted disable、branch prediction disable、
  write buffer coalescing disable 和 pipelining disable。

接口关系：

* 被调用：全局 clock gating、decode control、trace 和配置路径读取 MCGC/MFDC 输出。
* 调用：``rvdffe`` 保存 MCGC/MFDC。
* 共享状态：读取 CSR WB 地址/数据、``pt.BUILD_AXI4`` 和 per-thread CSR write enable。

§8  ``eh2_dec_tlu_ctl.sv`` per-thread TLU
-----------------------------------------

``eh2_dec_tlu_ctl`` 是每个线程的 TLU 控制器。它保存线程本地 CSR、处理 debug halt/run、
PMU/FW halt、trigger、LSU/IFU exception、commit、flush 和 trace WB1 元数据。

§8.1  端口范围
~~~~~~~~~~~~~~

职责：声明 per-thread TLU 的输入输出边界。端口显示它同时接入 CSR、trap packet、
LSU error、interrupt、PIC、debug/MPC、PMU 和 trace 输出。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L26-L54``）：

.. code-block:: systemverilog

   module eh2_dec_tlu_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic clk,
      input logic free_clk,
      input logic active_clk,
      input logic free_l2clk,
      input logic rst_l,
      input logic scan_mode,
      input logic mytid, // tid of this instance


      input logic tlu_select_tid, // selected tid for fast int

      input logic dec_tlu_dec_clk_override,

      input logic [31:1] rst_vec, // reset vector, from core pins
      input logic        nmi_int_sync, // nmi pin

逐段解释：

* 第 L26-L38 行：每个 ``eh2_dec_tlu_ctl`` 实例知道自己的 ``mytid``，并接收多个时钟域。
* 第 L41-L47 行：fast interrupt 选择 tid、DEC clock override、reset vector 和已同步 NMI
  进入线程 TLU。
* 第 L54-L85 行：PMU 输入覆盖 IFU、DEC、LSU、DMA 和 EXU branch 事件。
* 第 L103-L120 行：LSU error packet、CSR 访问输入和 CSR decode packet 进入 TLU。

接口关系：

* 被调用：``eh2_dec_tlu_top`` per-thread generate。
* 调用：后续内部使用多个 flop、同步器和 CSR/trigger 控制逻辑。
* 共享状态：保存线程本地 CSR 和 debug/halt/interrupt 状态。

§8.2  debug/MPC halt、core empty 和 noredir flush
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：处理 MPC halt/run、debug halt/resume、single-step、debug command done/fail、
core empty 判断和 halt 相关 no-redirection flush。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L557-L633``）：

.. code-block:: systemverilog

      // MPC halt
      // - can interact with debugger halt and v-v

      // fast ints in progress have priority
      assign mpc_debug_halt_req_sync = mpc_debug_halt_req_sync_raw & ~ext_int_freeze_d1;

      //hold dbg request when hart isn't started
      assign dbg_halt_req_no_start = (dbg_halt_req | dbg_halt_req_no_start_f) & ~mhartstart_csr;

       rvdffie #(11)  mpvhalt_ff (.*, .clk(free_l2clk),
                                    .din({dbg_halt_req_no_start,
                                          mpc_debug_halt_req_sync, mpc_debug_run_req_sync & debug_mode_status,
                                          mpc_halt_state_ns, mpc_run_state_ns, debug_brkpt_status_ns,
                                          mpc_debug_halt_ack_ns, mpc_debug_run_ack_ns,
                                          dbg_halt_state_ns, dbg_run_state_ns,
                                          dec_tlu_mpc_halted_only_ns}),

逐段解释：

* 第 L557-L565 行：fast interrupt freeze 会屏蔽 MPC halt；hart 未 start 时 debug halt request
  被保持在 ``dbg_halt_req_no_start``。
* 第 L566-L578 行：``mpvhalt_ff`` 在 ``free_l2clk`` 域保存 MPC/debug halt/run state、
  breakpoint status、ack 和 halted-only 状态。
* 第 L580-L603 行：源码把 level-sensitive halt/run request 转成 pulse，并生成 halt/run
  state 与 ack。
* 第 L610-L619 行：debug halt request 会和 MPC halt request 合成；debug resume request
  会避免 back-to-back resume。
* 第 L624-L633 行：``take_halt`` 受 flush、mret、halt_taken、noredir flush 和 reset gating；
  ``core_empty`` 要求 LSU/IFU 空闲并且无 debug halt request、无 active DIV，或 force halt。

接口关系：

* 被调用：debug interface、MPC interface 和 TLU flush 控制读取这些状态。
* 调用：``rvdffie`` 保存 halt/run 状态。
* 共享状态：读取 debug/MPC request、fast interrupt freeze、hart start、LSU/IFU idle 和 DIV active。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L640-L700``）：

.. code-block:: systemverilog

      assign enter_debug_halt_req = (~internal_dbg_halt_mode_f & debug_halt_req) | dcsr_single_step_done_f | trigger_hit_dmode_wb | ebreak_to_debug_mode_wb;

      // dbg halt state active from request until non-step resume
      assign internal_dbg_halt_mode = debug_halt_req_ns | (internal_dbg_halt_mode_f & ~(debug_resume_req_f & ~dcsr[DCSR_STEP]));
      // dbg halt can access csrs as long as we are not stepping
      assign allow_dbg_halt_csr_write = internal_dbg_halt_mode_f & ~dcsr_single_step_running_f;


      // hold debug_halt_req_ns high until we enter debug halt
      assign debug_halt_req_ns = enter_debug_halt_req | (debug_halt_req_f & ~dbg_tlu_halted);

      assign dbg_tlu_halted = (debug_halt_req_f & core_empty & halt_taken) | (dbg_tlu_halted_f & ~debug_resume_req_f);

      assign resume_ack_ns = (debug_resume_req_f & dbg_tlu_halted_f & dbg_run_state_ns);

逐段解释：

* 第 L640-L645 行：进入 debug halt 的来源包括 debug halt request、single-step done、
  trigger dmode hit 和 ebreak-to-debug；debug CSR 写许可要求 debug halt mode 且不是 single-step running。
* 第 L648-L659 行：debug halt request 会保持到 ``dbg_tlu_halted``；debug command done
  在 i0 valid E4 且 TLU halted 时产生。
* 第 L661-L680 行：trigger/DCSR 引起的 debug mode request 会阻止 pipe commit；
  ``halt_ff`` 保存 debug/halt/single-step/trigger 状态，输出 ``dec_tlu_debug_stall``、
  ``dec_tlu_dbg_halted`` 和 ``dec_tlu_debug_mode``。
* 第 L683-L700 行：``dec_tlu_flush_noredir_wb`` 在 halt、debug halt 中 fence_i、pause flush、
  dmode trigger 或 fast external interrupt start 时置位；非法 CSR debug command 会产生 fail。

接口关系：

* 被调用：debug command path、CSR write path、fetch flush path。
* 调用：``rvdffie`` 保存 halt/debug 状态。
* 共享状态：读取 ``dcsr``、trigger/ebreak、pause、interrupt 和 core empty。

§8.3  trigger 优先级和 action
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 mtdata1/mtdata2 配置筛选 trigger hit，处理 chain、dmode action、hit bit 更新，
并输出 breakpoint 或 debug mode 动作。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L717-L745``）：

.. code-block:: systemverilog

      // Prioritize trigger hits with other exceptions.
      //
      // Trigger should have highest priority except:
      // - trigger is an execute-data and there is an inst_access exception (lsu triggers won't fire, inst. is nop'd by decode)
      // - trigger is a store-data and there is a lsu_acc_exc or lsu_ma_exc.
      assign trigger_execute[3:0] = {mtdata1_t3[MTDATA1_EXE], mtdata1_t2[MTDATA1_EXE], mtdata1_t1[MTDATA1_EXE], mtdata1_t0[MTDATA1_EXE]};
      assign trigger_data[3:0] = {mtdata1_t3[MTDATA1_SEL], mtdata1_t2[MTDATA1_SEL], mtdata1_t1[MTDATA1_SEL], mtdata1_t0[MTDATA1_SEL]};
      assign trigger_store[3:0] = {mtdata1_t3[MTDATA1_ST], mtdata1_t2[MTDATA1_ST], mtdata1_t1[MTDATA1_ST], mtdata1_t0[MTDATA1_ST]};

      // testing proxy until RV debug committee figures out how to prevent triggers from firing inside exception handlers.
      // MSTATUS[MIE] needs to be on to take triggers unless the action is trigger to debug mode.
      assign trigger_enabled[3:0] = {(mtdata1_t3[MTDATA1_ACTION] | mstatus[MSTATUS_MIE]) & mtdata1_t3[MTDATA1_M_ENABLED],
                                     (mtdata1_t2[MTDATA1_ACTION] | mstatus[MSTATUS_MIE]) & mtdata1_t2[MTDATA1_M_ENABLED],

逐段解释：

* 第 L717-L724 行：源码注释说明 trigger 与其他 exception 的优先关系，并从四个
  ``mtdata1_t*`` 中提取 execute/data/store 属性。
* 第 L726-L731 行：trigger enabled 需要 M enabled；若不是 action-to-debug，则还依赖
  ``mstatus[MSTATUS_MIE]``。
* 第 L733-L744 行：iside exception、branch error、IC error 和 LSU exception 会参与
  trigger priority gating，最终得到 i0/i1 trigger raw hit。

接口关系：

* 被调用：commit/exception/debug path 读取 trigger hit。
* 调用：无下层模块。
* 共享状态：读取 trigger CSR state、mstatus、LSU/IFU/branch exception 状态。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L760-L790``）：

.. code-block:: systemverilog

      // This is the highest priority by this point.
      assign i0_trigger_hit_raw_e4 = |i0_trigger_chain_masked_e4[3:0];
      assign i1_trigger_hit_raw_e4 = |i1_trigger_chain_masked_e4[3:0];

      assign i0_problem_kills_i1_trigger = (~tlu_i0_commit_cmt | exu_i0_br_mp_e4 | lsu_i0_rfnpc_dc4) & tlu_i0_valid_e4;
      // Qual trigger hits
      assign i0_trigger_hit_e4 = ~(dec_tlu_flush_lower_wb | dec_tlu_dbg_halted) & i0_trigger_hit_raw_e4;
      assign i1_trigger_hit_e4 = ~(dec_tlu_flush_lower_wb | dec_tlu_dbg_halted | i0_problem_kills_i1_trigger) & i1_trigger_hit_raw_e4;

      // Actions include breakpoint, or dmode. Dmode is only possible if the DMODE bit is set.
      // Otherwise, take a breakpoint.
      assign trigger_action[3:0] = {mtdata1_t3[MTDATA1_ACTION] & mtdata1_t3[MTDATA1_DMODE],
                                    mtdata1_t2[MTDATA1_ACTION] & mtdata1_t2[MTDATA1_DMODE] & ~mtdata1_t2[MTDATA1_CHAIN],
                                    mtdata1_t1[MTDATA1_ACTION] & mtdata1_t1[MTDATA1_DMODE],

逐段解释：

* 第 L760-L767 行：chain-masked trigger 被 OR 成 raw hit；flush、debug halted 和 i0 问题会
  进一步屏蔽最终 hit。
* 第 L769-L785 行：action-to-debug 只有在 action 和 DMODE 条件满足时成立，部分 chained
  trigger 还要检查 chain bit。
* 第 L787-L790 行：最终 ``trigger_hit_dmode_e4`` 决定进入 debug mode，非 dmode trigger
  则选择 mepc trigger hit PC。

接口关系：

* 被调用：debug halt、exception cause 和 hit bit 更新逻辑。
* 调用：无下层模块。
* 共享状态：读取 trigger chain-masked hit、flush、debug halted、commit 和 branch/LSU 状态。

§8.4  commit、exception 和 writeback kill
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 branch RFPC、LSU exception、instruction access fault、debug halted、
request_debug_mode 和 trigger hit 生成 commit valid 与 writeback kill。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L862-L918``）：

.. code-block:: systemverilog

      // LSU exceptions (LSU responsible for prioritizing simultaneous cases)

      rvdff #( $bits(eh2_lsu_error_pkt_t) ) lsu_error_dc4ff (.*, .clk(lsu_e3_e4_clk), .din(lsu_error_pkt_dc3),  .dout(lsu_error_pkt_dc4));


      assign lsu_error_pkt_addr_dc4[31:0] = lsu_error_pkt_e4.addr[31:0];
      rvdff #(38) lsu_error_wbff (.*, .clk(lsu_e4_e5_clk), .din({lsu_error_pkt_addr_dc4[31:0], lsu_exc_valid_e4, lsu_i0_exc_dc4, lsu_error_pkt_e4.mscause[3:0]}),
                                                          .dout({lsu_error_pkt_addr_wb[31:0], lsu_exc_valid_wb, lsu_i0_exc_wb, lsu_error_mscause_wb[3:0]}));


      // lsu exception is valid unless it's in pipe1 and there was a rfpc_i0_e4, brmp, or an iside exception in pipe0.
      assign lsu_exc_valid_e4_raw = lsu_error_pkt_e4.exc_valid & ~(~tlu_packet_e4.lsu_pipe0 & (rfpc_i0_e4 | i0_exception_valid_e4 | exu_i0_br_mp_e4)) & ~dec_tlu_flush_lower_wb;

逐段解释：

* 第 L862-L869 行：LSU error packet 从 DC3 推到 DC4/WB，并保存地址、valid、lane 和 mscause。
* 第 L872-L879 行：pipe1 LSU exception 在 i0 RFPC、i0 exception 或 i0 branch mispredict
  时会被屏蔽；i0/i1 exception 还受 trigger 和 iside RFPC gating。
* 第 L886-L891 行：single-bit ECC load 走 RFNPC corrected data 路径，并受 trigger hit gating。
* 第 L895-L911 行：i0/i1 commit valid 会排除 RFPC、LSU exception、instruction access fault、
  debug halted、request_debug_mode 和 trigger hit。i1 还受 i0 mispredict、i0 RFPC 和
  i0 exception 影响。
* 第 L913-L918 行：writeback kill 集中管理 exception/trigger/RFPC 等对 architectural state
  写回的抑制。

接口关系：

* 被调用：GPR write enable、trace valid 和 cosim 观察路径读取 commit/kill。
* 调用：``rvdff`` 保存 LSU error 状态。
* 共享状态：读取 LSU error packet、trap packet、branch/trigger/debug/flush 状态。

§8.5  trigger CSR、performance counter 和 trace WB1
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：维护 trigger CSR，生成 ``tlu_trigger_pkt_any`` 给 DEC trigger matcher；
维护 performance counter increment；并输出 trace WB1 元数据。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L1762-L1855``）：

.. code-block:: systemverilog

      // [1:0] : Trigger select : 00, 01, 10 are data/address triggers. 11 is inst count
      localparam MTSEL         = 12'h7a0;

      assign wr_mtsel_wb = dec_i0_csr_wen_wb_mod & (dec_i0_csr_wraddr_wb[11:0] == MTSEL);
      assign mtsel_ns[1:0] = wr_mtsel_wb ? {dec_i0_csr_wrdata_wb[1:0]} : mtsel[1:0];

      rvdff #(2)  mtsel_ff (.*, .clk(csr_wr_clk), .din(mtsel_ns[1:0]), .dout(mtsel[1:0]));

      // ----------------------------------------------------------------------
      // MTDATA1 (R/W)
      // [31:0] : Trigger Data 1
      localparam MTDATA1       = 12'h7a1;

逐段解释：

* 第 L1762-L1768 行：``MTSEL`` 地址为 ``12'h7a0``，写入时保存 ``dec_i0_csr_wrdata_wb[1:0]``。
* 第 L1771-L1802 行：源码注释列出 MTDATA1 位域和内部 decoder ring 映射。
* 第 L1804-L1818 行：源码禁止 load-data、execute-data 的部分配置，并对 DMODE/action/chain
  写入施加 WARL 条件。
* 第 L1820-L1855 行：按 ``mtsel`` 选择 trigger 0-3 的 MTDATA1 写入，并在 trigger hit
  时更新 hit bit，读出时重构 32-bit ``mtdata1_tsel_out``。

接口关系：

* 被调用：debug CSR 和 trigger match path。
* 调用：``rvdff``、``rvdffe`` 保存 trigger CSR。
* 共享状态：读取 CSR writeback、debug halted、hit bit update 和 ``mtsel``。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L1857-L1913``）：

.. code-block:: systemverilog

      assign tlu_trigger_pkt_any[0].select = mtdata1_t0[MTDATA1_SEL];
      assign tlu_trigger_pkt_any[0].match = mtdata1_t0[MTDATA1_MATCH];
      assign tlu_trigger_pkt_any[0].store = mtdata1_t0[MTDATA1_ST];
      assign tlu_trigger_pkt_any[0].load = mtdata1_t0[MTDATA1_LD];
      assign tlu_trigger_pkt_any[0].execute = mtdata1_t0[MTDATA1_EXE];
      assign tlu_trigger_pkt_any[0].m = mtdata1_t0[MTDATA1_M_ENABLED];

      assign tlu_trigger_pkt_any[1].select = mtdata1_t1[MTDATA1_SEL];
      assign tlu_trigger_pkt_any[1].match = mtdata1_t1[MTDATA1_MATCH];
      assign tlu_trigger_pkt_any[1].store = mtdata1_t1[MTDATA1_ST];
      assign tlu_trigger_pkt_any[1].load = mtdata1_t1[MTDATA1_LD];
      assign tlu_trigger_pkt_any[1].execute = mtdata1_t1[MTDATA1_EXE];
      assign tlu_trigger_pkt_any[1].m = mtdata1_t1[MTDATA1_M_ENABLED];

逐段解释：

* 第 L1857-L1883 行：四个 trigger packet 都从对应 ``mtdata1_t*`` 提取 select、match、
  store、load、execute 和 M enable 字段。
* 第 L1894-L1903 行：``MTDATA2`` 写入同样受 DMODE 和 debug halted 状态限制，并按
  ``mtsel`` 选择 trigger 0-3。
* 第 L1905-L1913 行：``mtdata2_tsel_out`` 用于 CSR read mux；``tlu_trigger_pkt_any[*].tdata2``
  提供给 DEC trigger matcher。

接口关系：

* 被调用：``eh2_dec_trigger`` 读取 ``trigger_pkt_any``。
* 调用：``rvdffe`` 保存 MTDATA2。
* 共享状态：读取 trigger CSR state 和 CSR writeback。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L2045-L2103``）：

.. code-block:: systemverilog

                ({2{(mhpme_vec[i][9:0] == MHPME_EXC_TAKEN       )}} & {1'b0, (i0_exception_valid_e4 | trigger_hit_e4 | lsu_exc_valid_e4)}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_TIMER_INT_TAKEN )}} & {1'b0, take_timer_int | take_int_timer0_int | take_int_timer1_int}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_EXT_INT_TAKEN   )}} & {1'b0, take_ext_int}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_FLUSH_LOWER     )}} & {1'b0, tlu_flush_lower_e4}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_BR_ERROR        )}} & {(dec_tlu_br1_error_e4 | dec_tlu_br1_start_error_e4) & rfpc_i1_e4,
                                                                        (dec_tlu_br0_error_e4 | dec_tlu_br0_start_error_e4) & rfpc_i0_e4}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_IBUS_TRANS      )}} & {1'b0, ifu_pmu_bus_trxn}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_DBUS_TRANS      )}} & {1'b0, lsu_pmu_bus_trxn}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_DBUS_MA_TRANS   )}} & {1'b0, lsu_pmu_bus_misaligned}) |
                ({2{(mhpme_vec[i][9:0] == MHPME_IBUS_ERROR      )}} & {1'b0, ifu_pmu_bus_error}) |

逐段解释：

* 第 L2045-L2071 行：performance event increment 根据 ``mhpme_vec[i][9:0]`` 选择 exception、
  timer interrupt、external interrupt、flush lower、branch error、I/D bus transaction、
  bus error、stall、instruction class、DMA read/write 等事件。
* 第 L2075-L2091 行：``bundle_ff`` 和 ``bundle2_ff`` 保存 mstatus/mip/minstret/PIC level、
  mfdhs、icache diagnostic valid 和四组 performance counter increment。
* 第 L2094-L2103 行：debug halted 且 ``dcsr[DCSR_STOPC]`` 或 PMU/FW halted 会抑制 counter，
  但 ``perfcnt_during_sleep`` 对应事件可以在 sleep 期间计数。

接口关系：

* 被调用：PMU/performance counter 输出读取 ``tlu_perfcnt*``。
* 调用：``rvdffie`` 保存 counter increment bundle。
* 共享状态：读取 PMU 输入、exception/interrupt/flush state、debug/PMU halt state 和 CSR 配置。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L2265-L2290``）：

.. code-block:: systemverilog

      assign tracef_en = (i0_valid_wb | i1_valid_wb | exc_or_int_valid_wb | interrupt_valid_wb | tlu_i0_valid_wb1 | tlu_i1_valid_wb1 |
                          tlu_i0_exc_valid_wb1 | tlu_i1_exc_valid_wb1 | tlu_int_valid_wb1_raw | tlu_int_valid_wb2) & ~dec_tlu_trace_disable;

      rvdffe #(16)  traceff (.*, .clk(free_l2clk), .en(tracef_en),
                           .din ({i0_valid_wb, i1_valid_wb,
                                  i0_exception_valid_wb | lsu_i0_exc_wb | (i0_trigger_hit_wb & ~trigger_hit_dmode_wb),
                                  ~(i0_exception_valid_wb | lsu_i0_exc_wb | i0_trigger_hit_wb) & exc_or_int_valid_wb & ~interrupt_valid_wb,
                                  exc_cause_wb[4:0],
                                  interrupt_valid_wb,
                                  tlu_exc_cause_wb1_raw[4:0],
                                  tlu_int_valid_wb1_raw}),

逐段解释：

* 第 L2265-L2266 行：trace flop enable 覆盖 WB valid、exception/interrupt、已有 WB1 状态和
  interrupt skid buffer 状态，并受 ``dec_tlu_trace_disable`` gating。
* 第 L2268-L2282 行：``traceff`` 保存 i0/i1 valid、i0/i1 exception valid、exception cause
  和 interrupt valid。
* 第 L2284-L2288 行：interrupt 使用 skid buffer，``tlu_mtval_wb1`` 直接来自当前 ``mtval``。

接口关系：

* 被调用：``eh2_dec`` 顶层 trace packet 打包读取这些 WB1 元数据。
* 调用：``rvdffe`` 保存 trace metadata。
* 共享状态：读取 WB valid、exception/interrupt state、trace disable 和 mtval。

§8.6  CSR read mux
~~~~~~~~~~~~~~~~~~

职责：根据 ``eh2_dec_csr`` 生成的 ``tlu_i0_csr_pkt_d``，把线程本地 CSR state
组合成 32-bit CSR read data。

关键代码（``rtl/design/dec/eh2_dec_tlu_ctl.sv:L2299-L2345``）：

.. code-block:: systemverilog

      assign csr_rd = tlu_i0_csr_pkt_d;

   //   for( genvar i=0; i<2 ; i++) begin: CSR_rd_mux
      assign csr_rddata_d[31:0] = (  ({32{csr_rd.csr_mhartid}}   & {core_id[31:4], 3'b0, mytid}) |
                                     ({32{csr_rd.csr_mstatus}}   & {19'b0, 2'b11, 3'b0, mstatus[1], 3'b0, mstatus[0], 3'b0}) |
                                     ({32{csr_rd.csr_mtvec}}     & {mtvec[30:1], 1'b0, mtvec[0]}) |
                                     ({32{csr_rd.csr_mip}}       & {1'b0, mip[5:3], 16'b0, mip[2], 3'b0, mip[1], 3'b0, mip[0], 3'b0}) |
                                     ({32{csr_rd.csr_mie}}       & {1'b0, mie[5:3], 16'b0, mie[2], 3'b0, mie[1], 3'b0, mie[0], 3'b0}) |
                                     ({32{csr_rd.csr_mcyclel}}   & mcyclel[31:0]) |
                                     ({32{csr_rd.csr_mcycleh}}   & mcycleh_inc[31:0]) |
                                     ({32{csr_rd.csr_minstretl}} & minstretl_read[31:0]) |

逐段解释：

* 第 L2299 行：CSR read mux 直接使用 ``tlu_i0_csr_pkt_d``，即 CSR decode 输出 packet。
* 第 L2302-L2326 行：CSR read data 用每个 select bit 的 32-bit mask OR 合成；
  示例包括 ``mhartid``、``mstatus``、``mtvec``、``mip``、``mie``、cycle/instret、
  ``mepc``、``mcause``、PIC 相关 CSR、debug CSR 和 trigger CSR。
* 第 L2327-L2345 行：performance counter、event selector、count inhibit、cache diagnostic
  和 ``mfdhs`` 等也进入同一个 read mux。

接口关系：

* 被调用：decode/CSR read path 输出 ``csr_rddata_d``。
* 调用：无下层模块。
* 共享状态：读取线程本地 CSR state、``core_id``、``mytid`` 和 CSR decode packet。

§9  ``eh2_dec_trigger.sv`` DEC trigger matcher
----------------------------------------------

``eh2_dec_trigger`` 是 DEC 目录中最小的模块。它不保存 trigger CSR；CSR 状态由
TLU 控制器维护，并通过 ``trigger_pkt_any`` 传入。本模块只在 decode PC 与 trigger
配置之间做匹配。

§9.1  4 组 trigger 匹配
~~~~~~~~~~~~~~~~~~~~~~~

职责：遍历 4 个 trigger，根据 lane tid 选择对应线程的 trigger packet；当 ``select == 0``
且 ``execute`` 置位时使用 PC 作为匹配数据，再调用 ``rvmaskandmatch``。

关键代码（``rtl/design/dec/eh2_dec_trigger.sv:L25-L56``）：

.. code-block:: systemverilog

   module eh2_dec_trigger
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (

      input eh2_trigger_pkt_t [pt.NUM_THREADS-1:0] [3:0] trigger_pkt_any,           // Packet from tlu. 'select':0-pc,1-Opcode  'Execute' needs to be set for dec triggers to fire. 'match'-1 do mask, 0: full match
      input logic [31:1]                                   dec_i0_pc_d,                    // i0 pc
      input logic [31:1]                                   dec_i1_pc_d,                    // i1 pc
      input eh2_alu_pkt_t                                 i0_ap,                          // alu packet
      input eh2_alu_pkt_t                                 i1_ap,                          // alu packet

      output logic [3:0] dec_i0_trigger_match_d,
      output logic [3:0] dec_i1_trigger_match_d
   );

逐段解释：

* 第 L25-L29 行：trigger matcher 使用 EH2 package 和参数文件。
* 第 L31-L35 行：输入包括 per-thread、4-entry 的 ``trigger_pkt_any``，i0/i1 PC 和 i0/i1
  ALU packet。源码注释说明 ``select``、``execute`` 和 ``match`` 的含义。
* 第 L37-L38 行：输出是 i0/i1 各 4-bit trigger match vector。

接口关系：

* 被调用：``eh2_dec`` 顶层实例化。
* 调用：下方调用 ``rvmaskandmatch``。
* 共享状态：读取 TLU trigger packet 和 decode lane tid/PC。

关键代码（``rtl/design/dec/eh2_dec_trigger.sv:L46-L56``）：

.. code-block:: systemverilog

      for (genvar i=0; i<4; i++) begin
         assign dec_i0_match_data[i][31:0] = ({32{~trigger_pkt_any[i0_ap.tid][i].select & trigger_pkt_any[i0_ap.tid][i].execute}} & {dec_i0_pc_d[31:1], trigger_pkt_any[i0_ap.tid][i].tdata2[0]}); // select=0; do a PC match

         assign dec_i1_match_data[i][31:0] = ({32{~trigger_pkt_any[i1_ap.tid][i].select & trigger_pkt_any[i1_ap.tid][i].execute}} & {dec_i1_pc_d[31:1], trigger_pkt_any[i1_ap.tid][i].tdata2[0]} );// select=0; do a PC match

         rvmaskandmatch trigger_i0_match (.mask(trigger_pkt_any[i0_ap.tid][i].tdata2[31:0]), .data(dec_i0_match_data[i][31:0]), .masken(trigger_pkt_any[i0_ap.tid][i].match), .match(dec_i0_trigger_data_match[i]));
         rvmaskandmatch trigger_i1_match (.mask(trigger_pkt_any[i1_ap.tid][i].tdata2[31:0]), .data(dec_i1_match_data[i][31:0]), .masken(trigger_pkt_any[i1_ap.tid][i].match), .match(dec_i1_trigger_data_match[i]));

         assign dec_i0_trigger_match_d[i] = trigger_pkt_any[i0_ap.tid][i].execute & trigger_pkt_any[i0_ap.tid][i].m & dec_i0_trigger_data_match[i];
         assign dec_i1_trigger_match_d[i] = trigger_pkt_any[i1_ap.tid][i].execute & trigger_pkt_any[i1_ap.tid][i].m & dec_i1_trigger_data_match[i];
      end

逐段解释：

* 第 L46-L49 行：循环固定为 4 个 trigger。若对应 trigger 的 ``select`` 为 0 且
  ``execute`` 为 1，则匹配数据由 lane PC 和 ``tdata2[0]`` 拼成；否则 mask 后数据为 0。
* 第 L51-L52 行：i0/i1 各调用一个 ``rvmaskandmatch``，mask 来自对应 trigger 的
  ``tdata2``，``masken`` 来自 ``match``。
* 第 L54-L55 行：最终 match 还要求 ``execute`` 和 ``m`` 置位。

接口关系：

* 被调用：``eh2_dec_decode_ctl`` 和 TLU exception path 使用 ``dec_i*_trigger_match_d``。
* 调用：``rvmaskandmatch``。
* 共享状态：读取 ``trigger_pkt_any``、``i0_ap.tid``、``i1_ap.tid`` 和 decode PC。

§10  端到端时序关系
-------------------

本节把前面各源码片段的关系串起来，便于对照 trace、debug 和 NB-load 行为。所有箭头
均对应前文引用的源码连接或信号赋值。

.. code-block:: text

   Cycle N, IFU/IB:
     ifu_i0/i1_* enter eh2_dec_ib_ctl
     debug command may override ib0 instruction
     ibval_in updates according to shift0/shift1/shift2 and flush_final

   Cycle N, D-stage selection:
     rvarbiter2_smt chooses dec_i0_tid_d and dec_i1_tid_d
     eh2_dec selects i0/i1 instruction, PC, predecode, branch metadata
     eh2_dec_gpr_ctl returns rs1/rs2 for selected tids

   Cycle N, decode control:
     eh2_dec_decode_ctl builds i0_ap and i1_ap
     block packets decide dec_i0_decode_d and dec_i1_decode_d
     i1_cancel_d may be registered into i1_cancel_e1

   E/WB stages:
     result pipeline selects ALU, load, mul, secondary, SC data
     TLU qualifies commit, exception, interrupt and writeback kill
     NB-load CAM tracks async load completion by tag and rd

   WB1 trace:
     decode_ctl produces instruction, PC and RVFI-equivalent rd mirror
     TLU produces valid, exception, interrupt, cause and mtval
     eh2_dec packs trace_rv_trace_pkt per thread

这张时序图不引入额外状态，只把 ``eh2_dec_ib_ctl`` 的 IB 更新、``eh2_dec`` 的
thread/lane selection、``eh2_dec_decode_ctl`` 的 decode/result/NB-load，以及
``eh2_dec_tlu_ctl`` 的 commit/trace 元数据按源码信号顺序连接起来。

§11  参考资料
-------------

关联 ADR：

* :ref:`adr-0001` - Cosim via trace and probe。DEC 顶层 trace packet 和 TLU WB1
  元数据是该数据路径的 RTL 侧输入。
* :ref:`adr-0004` - RTL RVFI-equivalent trace。``eh2_dec.sv`` 和
  ``eh2_dec_decode_ctl.sv`` 中的 verification-only WB1 writeback mirror 与该 ADR 相关。
* :ref:`adr-0010` - CSR register model。本文 CSR 章节只描述 RTL CSR decode 和 TLU CSR
  read mux，不描述 UVM register model 的实现。
* :ref:`adr-0015` - RVFI adapter layer。DEC trace packet 是适配层消费的 RTL 侧来源之一。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_ib_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_gpr_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_csr.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_decode_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_tlu_top.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_tlu_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/dec/eh2_dec_trigger.sv`

关联章节：

* :doc:`wrapper` - core wrapper 和 trace adapter 的外层连接。
* :doc:`ifu` - IFU aligner、branch prediction 和 compressed instruction 输入来源。
* :doc:`lsu` - LSU result、nonblocking load 和 LSU error packet 来源。
* :doc:`exu` - ALU/MUL/DIV result 和 branch feedback 来源。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：核对本页关联的 RTL 名称是否能在上游 design 目录和中文手册代码引用中同时找到。

.. code-block:: bash

   rg -n "module |input |output |parameter" /home/host/Cores-VeeR-EH2/design | head -40
   rg -n "literalinclude::|code-block:: verilog" docs/sphinx_cn/source/02_core_reference docs/sphinx_cn/source/appendix_a_rtl | head -40

**进阶题**：确认该 RTL 主题没有脱离当前 VCS/URG coverage 和 LEC 证据口径。

.. code-block:: bash

   rg -n "core_eh2_tb_top.dut|cover.cfg|31635/31635|95.05" docs/sphinx_cn/source/02_core_reference docs/sphinx_cn/source/appendix_a_rtl

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？

§12  v2-19 ``eh2_dec.sv`` 全文段落级精读
--------------------------------------------------------------------------------

``eh2_dec.sv`` 是 decode/TLU/GPR/IB 顶层胶合文件，也是 EH2 双线程、双发射、
CSR、debug、interrupt 和 trace packet 的汇合点。v2-19 将该文件全文加入文档，避免
只解释 decode_ctl 或 TLU 子块而漏掉 thread arbitration、I1 选择、NB-load mirror 和
trace packing 的顶层 glue。

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec.sv:全文

逐段精读：

* L1-L26：版权、include 和 package import。DEC 顶层依赖 ``eh2_def.sv`` 的 packet
  typedef，并继承 ``pt`` 参数包中的线程数、BTB 宽度和 LSU nonblocking load 配置。
* L27-L90：模块头、clock/reset、secondary ALU、branch、core empty、debug halt/run
  和 reset vector 端口。这些端口把 DEC 同时接到 top clock gating、debug PMU 和 TLU。
* L91-L154：MPC debug、branch PMU、LSU nonblocking load、LSU/DMA/IFU PMU、debug
  abstract command 和 IFU access fault 输入。DEC 不是纯 decode，它也汇总异常和性能事件。
* L155-L247：IFU predecode、LSU stall、branch predictor metadata、LSU error、EXU flush、
  result、interrupt/PIC 和 I-cache diagnostic 端口。该段决定 decode 与 IFU/EXU/LSU/TLU
  的主要握手边界。
* L248-L465：debug mode、trigger、GPR operand、immediate、ALU/LSU/MUL/DIV packet、
  flush、CSR、prediction、commit、trace、clock override 和 final flush 输出。外部模块
  看到的 DEC 行为大多从这段端口离开。
* L469-L620：localparam 与内部信号声明。该段建立 GPR bank、CSR control、debug stall、
  illegal instruction、branch prediction metadata、WB1 trace mirror、per-thread GPR bus
  和 ``dec_tlu_i*_pc_e4`` 等 glue。
* L621-L688：简单 assign、instruction buffer 信号、thread ready/stall、divide state、
  active clock 和 active clock header。这里为后续 generate block 准备 per-thread 数据面。
* L689-L771：``ib`` generate。每个线程实例化 instruction buffer/control 相关逻辑，
  将 IFU I0/I1 指令、PC、predecode、branch metadata 和 fault 信息送入 decode staging。
* L772-L804：``arf`` generate 与 ready/lsu/mul/i0_only 输入汇总。每线程 GPR/ARF
  读写和 bypass 资源在这里展开，随后统一进入 thread selection 逻辑。
* L805-L864：单线程/双线程选择 generate。单线程直接选择 thread 0；双线程通过
  ``rvarbiter2_smt`` 在两个线程间选择 I0/I1，决定 ``dec_i0_tid_d``、``dec_i1_tid_d``
  和各 slot ready。
* L866-L892：I0 slot 选择与 debug/fence 派生。该段把 per-thread arrays 按
  ``dec_i0_tid_d`` mux 成单个 I0 decode view，是后续 decode_ctl 的主输入。
* L893-L982：I1 slot 选择。双线程配置下允许 I1 从 thread 0 的第二条或 thread 1 的
  第一条指令选择；单线程配置下回退为同线程 I1 buffer。这里是 EH2 dual-thread/dual-issue
  行为最容易误读的代码段。
* L983-L1002：decode_ctl、TLU、CSR、GPR 或 trigger 子模块连接收尾。该区域把前面选出的
  I0/I1 view 送入实际 decode、CSR legality、writeback 和 trap/interrupt 控制。
* L1003-L1027：``tracep`` generate 与 ``endmodule``。WB1 级 instruction、PC、valid、
  exception、interrupt、cause、tval 和 rd writeback 被打包成 ``trace_rv_trace_pkt``，
  供 top trace_rewire、UVM trace monitor、RVFI converter 和 cosim scoreboard 消费。

§13  v2-20 DEC 子模块全文段落级精读
--------------------------------------------------------------------------------

v2-20 继续把 DEC 顶层下钻到子模块。下面 7 个文件分别覆盖 CSR legality、
decode/result/NB-load 主控制、GPR、instruction buffer、TLU、TLU top glue 和 trigger。
它们共同解释 ``eh2_dec.sv`` 端口背后的真实实现，不能只用顶层信号名替代源码阅读。

§13.1  ``eh2_dec_csr.sv`` — CSR 地址、合法性与同步属性
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_csr.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_csr.sv:全文

逐段精读：

* L1-L24：文件头和 package import。该文件只做 CSR decode/legality，不保存 CSR 状态。
* L25-L86：模块端口。输入是 decode 阶段 CSR 地址、操作类型和当前特权/debug 状态；
  输出是 ``tlu_csr_pkt_d``、legal、global、presync/postsync 等控制。
* L88-L147：为标准 CSR、EH2 custom CSR、debug CSR、PIC CSR、timer CSR 和诊断 CSR
  建立 one-hot 命中信号，同时保留 ``valid_only``、``presync``、``postsync``、``glob``。
* L148-L370：逐地址组合 decode。每个 ``csr_*`` assign 都是对 ``dec_csr_rdaddr_d`` 的
  位级匹配，覆盖 MISA、MSTATUS、MEPC/MCAUSE、PIC、debug trigger、performance counter、
  memory diagnostic 和 EH2 custom control CSR。
* L373-L414：presync、postsync 和 global 属性分类。CSR 访问是否需要序列化、是否影响
  全局状态，在这里由地址类别决定。
* L415-L529：legal/conditionally illegal/valid CSR 判定。该段结合地址命中、timer/PIC
  配置、debug mode、read/write 属性和 CSR 操作类型生成 ``dec_csr_legal_d``。
* L530-L613：``tlu_csr_pkt_d`` 打包。所有 one-hot CSR 命中和属性位被送给 TLU，由 TLU
  完成实际 CSR read mux、write side effect、trap 和 interrupt state 更新。

§13.2  ``eh2_dec_decode_ctl.sv`` — decode、result 与 nonblocking load 主控制
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_decode_ctl.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_decode_ctl.sv:全文

逐段精读：

* L1-L16：文件头和 package import。该文件包含 3 个 module：主 ``eh2_dec_decode_ctl``、
  ``eh2_dec_cam`` 和位级 ``eh2_dec_dec_ctl``。
* L17-L210：主 decode_ctl 模块端口。输入来自 IFU/IB、GPR、CSR、EXU/LSU/MUL/DIV、
  TLU flush、debug 和 nonblocking load；输出是 ALU/LSU/MUL/DIV packet、bypass、
  writeback、trace mirror 和 stall。
* L211-L520：decode 阶段 I0/I1 operand、immediate、packet 和 legality 组合。该段把
  compressed/predecode、CSR、debug fence、load/store/mul/div/atomic 选择转成下游控制。
* L521-L940：pipeline valid、stall、flush、presync/postsync、debug stall、dual issue
  和 I1 cancel 逻辑。这里决定哪条指令能从 D 进入 E1，哪条必须被 flush 或取消。
* L941-L1300：operand bypass、GPR writeback source、CSR write data、LSU result、
  MUL/DIV result 和 store-conditional result 选择。该段解释 RAW hazard 如何在 decode
  控制层被消解。
* L1301-L1760：E1/E2/E3/E4/WB pipeline 寄存器和 control/data enable。``dec_i*_data_en``
  与 ``dec_i*_ctl_en`` 从这里驱动 EXU clock gating。
* L1761-L2250：TLU 交互、exception/interrupt/debug command、CSR side effect、commit
  kill 和 writeback qualification。该段是 decode_ctl 与 TLU 边界最密集的部分。
* L2251-L2740：trace/WB1 mirror、performance event、secondary ALU、divide cancel、
  debug readback 和 flush path 相关逻辑。UVM probe 和 RVFI-like trace 都依赖这些镜像。
* L2741-L3233：主 module 收尾。剩余 assign/generate 完成 writeback、stall、commit、
  nonblocking load output 和 ``endmodule``。
* L3235-L3493：``eh2_dec_cam``。该 CAM 跟踪 LSU nonblocking load tag、rd、valid 和
  data return；处理 dc2/dc5 invalidate、same-dest cancel、force halt、flush 和 load-use
  boundary stall。
* L3522-L3812：``eh2_dec_dec_ctl``。这是位级 decoder，把 instruction bits 与 predecode
  信息展开成 ``out`` packet，覆盖 ALU、load/store、branch、CSR、mul/div、fence、atomic
  和 Zb* bitmanip 指令类别。

§13.3  ``eh2_dec_gpr_ctl.sv`` — GPR bank 读写
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_gpr_ctl.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_gpr_ctl.sv:全文

逐段精读：

* L1-L15：文件头和 include。GPR 控制模块不依赖复杂状态机，只负责 register file glue。
* L16-L48：模块端口。输入包含读地址、写地址、写数据、write enable、thread/bank 选择
  和 clock/reset；输出是 I0/I1 RS1/RS2 数据。
* L49-L88：读写地址、write enable 和 x0 处理。该段保证 x0 读为零，写 x0 不改变状态。
* L89-L116：register file array 与同步写。写回路径按 thread/bank 选择更新物理寄存器。
* L117-L129：读数据输出和 module 结束。读口将数组内容或零值送回 ``eh2_dec.sv`` 的
  per-thread operand mux。

§13.4  ``eh2_dec_ib_ctl.sv`` — instruction buffer 控制
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_ib_ctl.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_ib_ctl.sv:全文

逐段精读：

* L1-L15：文件头和 import。IB control 是 IFU 到 decode 的 staging buffer。
* L16-L105：模块端口。输入是 IFU I0/I1 valid/instruction/PC/predecode、stall/ready、
  flush、debug stall、thread 选择；输出是 IB0-IB3 valid、instruction、PC、branch metadata
  和 fault/debug 信息。
* L106-L210：buffer valid、ready、write pointer 和 input selection。该段把 fetch group
  写入 IB，并根据 decode 消费情况移动。
* L211-L330：IB data path。instruction、compressed halfword、PC、PC4、predecode、branch
  prediction index/tag/fghr/toffset 和 access fault 信息随 valid 一起推进。
* L331-L450：flush、debug fence、i0_only、dual issue 和 stall 处理。该段决定 IB 中哪些
  条目能形成 I0/I1，哪些因为 flush 或同步约束被清空。
* L451-L539：输出打包和 module 结束。IB0/IB1/IB2/IB3 valid 与 instruction view 被送回
  ``eh2_dec.sv`` 的 thread/lane selection。

§13.5  ``eh2_dec_tlu_ctl.sv`` — trap/interrupt/debug/CSR 控制
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_tlu_ctl.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_tlu_ctl.sv:全文

逐段精读：

* L1-L25：文件头和 import。该文件包含主 ``eh2_dec_tlu_ctl`` 和 ``eh2_dec_timer_ctl``。
* L26-L180：TLU control 端口。输入覆盖 commit、exception、interrupt、debug、CSR packet、
  LSU error、PIC/timer/software/NMI、trigger 和 flush；输出覆盖 CSR state、flush path、
  debug mode、interrupt claim、trace exception metadata 和 PMU。
* L181-L520：CSR state、mstatus/mie/mip/mepc/mcause/mtval、debug CSR 和 EH2 custom CSR
  相关寄存器声明与 reset 值。该段是 architectural state 的主要存储区。
* L521-L980：exception、interrupt、NMI、debug entry、MRET/DRET 和 flush 优先级。
  TLU 在这里选择进入 trap/debug 的原因、写入 EPC/cause/tval，并生成 lower flush。
* L981-L1380：CSR read/write side effect、counter、performance event、PIC CSR、timer
  CSR 和 memory diagnostic CSR 更新。该段解释 CSR 操作如何改变 core architectural state。
* L1381-L1780：halt/run、MPC/debug resume、force halt、core empty、pause state 和
  debug command done/fail。UVM halt/run agent 与 debug/cosim 场景重点观察这些信号。
* L1781-L2140：interrupt prioritization、external interrupt claim、PIC current priority、
  wakeup、fast interrupt 和 NMI delegation。该段是 PIC/interrupt directed tests 的 RTL 根。
* L2141-L2350：trace metadata、commit valid、flush output、clock override、final assigns
  和 ``endmodule``。trace exception/interrupt/cause/tval 从这里进入 ``trace_rv_trace_pkt``。
* L2352-L2524：``eh2_dec_timer_ctl``。timer 子模块维护 mcycle/minstret 和 HPM 计数器，
  响应 counter inhibit、performance event 和 reset，供 CSR read path 和 coverage 使用。

§13.6  ``eh2_dec_tlu_top.sv`` — TLU top glue
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_tlu_top.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_tlu_top.sv:全文

逐段精读：

* L1-L25：文件头和 import。TLU top 是 per-thread TLU control 的实例化胶合层。
* L26-L180：模块端口。它承接 DEC 顶层传入的 CSR、flush、interrupt、debug、PIC、LSU
  error、trigger 和 commit 信号，并输出 per-thread TLU 状态。
* L181-L330：内部 per-thread arrays 和 shared glue。该段把单个顶层信号拆成
  ``NUM_THREADS`` 维度，准备实例化每线程 TLU。
* L331-L640：per-thread ``eh2_dec_tlu_ctl`` 实例和连接。每个 hart/thread 拥有自己的
  CSR/trap/debug state，但共享部分 top-level interrupt/PIC 输入。
* L641-L820：thread 结果归并。debug halt/run ack、flush、PIC priority、trace metadata、
  CSR read data 和 PMU event 被汇回 DEC 顶层。
* L821-L906：clock override、ECC disable、external load forwarding disable、misc control
  和 module 收尾。这些输出直接影响 top clock gating、LSU/IFU 行为和 coverage 采样。

§13.7  ``eh2_dec_trigger.sv`` — debug trigger match
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec_trigger.sv
   :language: systemverilog
   :linenos:
   :caption: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_trigger.sv:全文

逐段精读：

* L1-L24：文件头、include 和 package import。trigger 模块服务 debug trigger CSR。
* L25-L44：模块端口。输入是 trigger packet、PC、load/store address 或 execute match
  条件；输出是 trigger match bit。
* L45-L58：组合匹配逻辑和 module 结束。该段按 trigger 配置比较地址/execute 条件，
  将命中结果送回 DEC/TLU 触发 debug entry。
