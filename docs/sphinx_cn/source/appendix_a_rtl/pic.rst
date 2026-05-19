.. _appendix_a_rtl_pic:
.. _appendix_a_rtl/pic:

可编程中断控制器（PIC）— 详细参考
==================================

:status: draft
:source: rtl/design/eh2_pic_ctrl.sv
:last-reviewed: 2026-05-19

§1  源文件边界与集成位置
------------------------

本章只描述当前源码中的 ``eh2_pic_ctrl`` 实现。PIC 中断源数量、线程数量、优先级树深度和
两周期切分均由参数对象 ``pt`` 决定；因此本文使用 ``pt.PIC_TOTAL_INT_PLUS1``、
``pt.NUM_THREADS`` 和 ``pt.PIC_2CYCLE`` 表达参数化行为，不把实现写成固定 127 路或固定
单线程结构。

``eh2_pic_ctrl`` 的主要数据流如下：

.. code-block:: text

   extintsrc_req
        │
        ▼
   eh2_configurable_gw per interrupt
        │  extintsrc_req_gw
        ▼
   enable / delegation / priority registers
        │
        ▼
   intpend_w_prior_en + intpend_id
        │
        ▼
   eh2_cmp_and_mux priority tree
        │
        ├── claimid_in
        └── selected_int_priority
                │
                ▼
   threshold/current-priority compare
        │
        ├── mexintpend_out
        ├── claimid_out
        ├── pl_out
        └── mhwakeup_out

LSU/PIC memory-mapped 访问通过 ``picm_*`` 输入进入地址匹配和寄存器读写路径。外部中断
``extintsrc_req`` 先进入每路 gateway，之后与 ``intenable_reg``、``delg_reg``、
``intpriority_reg`` 合成优先级树输入。优先级树输出的 claim id 和 priority 再与
``dec_tlu_meipt``、``dec_tlu_meicurpl`` 比较，决定是否向 core 输出 pending 和 wakeup。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L70-L73``）：

.. code-block:: text

   // Top-level
   rtl/design/eh2_dma_ctrl.sv
   rtl/design/eh2_mem.sv
   rtl/design/eh2_pic_ctrl.sv
   rtl/design/eh2_veer.sv

逐段解释：

* 第 L70-L73 行：filelist 将 ``eh2_pic_ctrl.sv`` 列入 top-level RTL 组。
  该事实说明 PIC 控制器是独立编译单元；具体连线仍以 ``eh2_veer.sv`` 的实例为准。
* 第 L73 行：``eh2_pic_ctrl.sv`` 与 ``eh2_veer.sv`` 同组出现，后者在顶层实例化
  ``eh2_pic_ctrl``。

接口关系：

* 被引用：:file:`dv/uvm/core_eh2/eh2_rtl.f` 将该文件纳入 RTL 编译。
* 调用：filelist 不调用逻辑，只定义编译输入。
* 共享状态：无运行时共享状态；运行时共享信号在 ``eh2_veer`` 实例中连接。

关键代码（``rtl/design/eh2_veer.sv:L1106-L1117``）：

.. code-block:: systemverilog

      eh2_pic_ctrl #(.pt(pt))  pic_ctrl_inst (
                                               .clk(free_l2clk),
                                               .clk_override(dec_tlu_pic_clk_override),
                                               .io_clk_override(dec_tlu_picio_clk_override),
                                               .picm_mken (picm_mken),
                                               .extintsrc_req({extintsrc_req[pt.PIC_TOTAL_INT:1],1'b0}),
                                               .pl_out(pic_pl),
                                               .claimid_out(pic_claimid),
                                               .mexintpend_out(mexintpend),
                                               .mhwakeup_out(mhwakeup),
                                               .rst_l(core_rst_l),
                                               .*);

逐段解释：

* 第 L1106 行：实例名为 ``pic_ctrl_inst``，参数 ``pt`` 传入 ``eh2_pic_ctrl``。
* 第 L1107-L1109 行：实例使用 ``free_l2clk``，并接收 PIC 与 PIC IO 两个 clock override。
* 第 L1110 行：``picm_mken`` 显式连接，其他 ``picm_*`` 信号通过第 L1117 行 ``.*`` 同名连接。
* 第 L1111 行：传入 PIC 的 ``extintsrc_req`` 把 bit 0 固定为 ``1'b0``，其余位来自顶层
  ``extintsrc_req[pt.PIC_TOTAL_INT:1]``。
* 第 L1112-L1115 行：PIC 输出 priority level、claim id、external interrupt pending 和
  wakeup，分别连接到 ``pic_pl``、``pic_claimid``、``mexintpend``、``mhwakeup``。
* 第 L1116-L1117 行：reset 使用 ``core_rst_l``；同名端口继续连接 threshold/current priority、
  PIC memory 访问和 scan 等信号。

接口关系：

* 被实例化：``eh2_veer`` 通过 ``pic_ctrl_inst`` 连接 PIC。
* 调用：作为硬件实例不执行函数调用；内部组合逻辑和触发器由端口驱动。
* 共享状态：``pt``、``picm_*``、``dec_tlu_meipt``、``dec_tlu_meicurpl``、
  ``extintsrc_req`` 和输出 pending/claim/pl/wakeup。

§2  模块端口与参数化地址
------------------------

``eh2_pic_ctrl`` 的端口分为 clock/reset、PMU halt status、外部中断输入、PIC memory-mapped
访问、DEC/TLU priority 输入和 core 输出。地址 map localparam 均从 ``pt.PIC_BASE_ADDR``
加偏移得到。

§2.1  ``eh2_pic_ctrl`` 端口 — PIC memory 与 core 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 PIC 控制器的参数、时钟复位、外部中断请求、memory-mapped 访问输入和对 core
输出的 pending/claim/priority/wakeup。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L23-L58``）：

.. code-block:: systemverilog

   module eh2_pic_ctrl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
    )
                     (

                        input  logic                   clk,                  // Core clock
                        input  logic                   free_clk,             // free clock
                        input  logic                   rst_l,                // Reset for all flops
                        input  logic                   clk_override,         // Clock over-ride for gating
                        input  logic                   io_clk_override,      // PIC IO  Clock over-ride for gating

                        input  logic [pt.NUM_THREADS-1:0] o_cpu_halt_status, // PMU interface, halted

                        input  logic [pt.PIC_TOTAL_INT_PLUS1-1:0]   extintsrc_req,  // Interrupt requests
                        input  logic [31:0]            picm_rdaddr,          // Address of the register
                        input  logic [31:0]            picm_wraddr,          // Address of the register
                        input  logic [31:0]            picm_wr_data,         // Data to be written to the register
                        input  logic                   picm_wren,            // Write enable to the register
                        input  logic                   picm_rden,            // Read enable for the register

逐段解释：

* 第 L23-L27 行：模块导入 ``eh2_pkg::*`` 并包含 ``eh2_param.vh``，后续使用 ``pt`` 参数对象。
* 第 L30-L35 行：``clk``、``free_clk``、``rst_l``、``clk_override`` 和
  ``io_clk_override`` 构成 clock/reset/override 输入。
* 第 L36 行：``o_cpu_halt_status`` 以 ``pt.NUM_THREADS`` 为宽度，后续多线程仲裁用它判断线程
  是否 active。
* 第 L38-L45 行：``extintsrc_req`` 宽度为 ``pt.PIC_TOTAL_INT_PLUS1``；``picm_rdaddr``、
  ``picm_wraddr``、``picm_wr_data``、``picm_wren``、``picm_rden``、``picm_rd_thr`` 和
  ``picm_mken`` 组成 memory-mapped 访问接口。

接口关系：

* 被连接：``eh2_veer`` 的 ``pic_ctrl_inst`` 实例连接这些端口。
* 调用：本段只声明模块端口。
* 共享状态：``picm_*`` 被地址寄存器、读写使能、bypass 和 read mux 共同读取。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L47-L56``）：

.. code-block:: systemverilog

                        input  logic [pt.NUM_THREADS-1:0] [3:0]             dec_tlu_meicurpl,           // Current Priority Level
                        input  logic [pt.NUM_THREADS-1:0] [3:0]             dec_tlu_meipt,              // Current Priority Threshold

                        output logic [pt.NUM_THREADS-1:0]                   mexintpend_out,           // External Inerrupt request to the core
                        output logic [pt.NUM_THREADS-1:0] [7:0]             claimid_out,              // Claim Id of the requested interrupt
                        output logic [pt.NUM_THREADS-1:0] [3:0]             pl_out,                   // Priority level of the requested interrupt
                        output logic [pt.NUM_THREADS-1:0]                   mhwakeup_out,             // Wake-up interrupt request

                        output logic [31:0]            picm_rd_data,         // Read data of the register
                        input  logic                   scan_mode             // scan mode

逐段解释：

* 第 L47-L48 行：``dec_tlu_meicurpl`` 与 ``dec_tlu_meipt`` 都按线程展开，每线程 4 bit。
  后续第 L569-L586 行按当前线程选择其中一组。
* 第 L50-L53 行：PIC 对每个线程输出 external interrupt pending、claim id、priority level 和
  wakeup。
* 第 L55-L56 行：``picm_rd_data`` 返回 memory-mapped 读数据；``scan_mode`` 进入子模块或
  clock wrapper 的同名连接。

接口关系：

* 被调用：core trap/CSR/wakeup 逻辑观察 ``mexintpend_out``、``claimid_out``、``pl_out``、
  ``mhwakeup_out``。
* 调用：阈值比较、priority tree 和读数据 mux 生成这些输出。
* 共享状态：输出寄存器由 ``selected_int_priority``、``claimid_in``、``pl_in_q`` 和
  ``mhwakeup_in`` 驱动。

§2.2  Localparam 地址 map — PIC register base
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 ``pt.PIC_BASE_ADDR`` 推导 PIC priority、pending、thread pending、enable、config、
gateway config、gateway clear 和 delegation register 的 base address，并定义 pending
扩展大小和 priority/id 宽度。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L60-L83``）：

.. code-block:: systemverilog

   localparam NUM_LEVELS            = $clog2(pt.PIC_TOTAL_INT_PLUS1);
   localparam INTPRIORITY_BASE_ADDR = pt.PIC_BASE_ADDR ;
   localparam INTPEND_BASE_ADDR     = pt.PIC_BASE_ADDR + 32'h00001000 ;
   localparam INTPEND_THR_BASE_ADDR = pt.PIC_BASE_ADDR + 32'h00001800 ;
   localparam INTENABLE_BASE_ADDR   = pt.PIC_BASE_ADDR + 32'h00002000 ;
   localparam EXT_INTR_PIC_CONFIG   = pt.PIC_BASE_ADDR + 32'h00003000 ;
   localparam EXT_INTR_GW_CONFIG    = pt.PIC_BASE_ADDR + 32'h00004000 ;
   localparam EXT_INTR_GW_CLEAR     = pt.PIC_BASE_ADDR + 32'h00005000 ;
   localparam EXT_INTR_DELG_REG     = pt.PIC_BASE_ADDR + 32'h00006000 ;


   localparam INTPEND_SIZE          = (pt.PIC_TOTAL_INT_PLUS1 < 32)  ? 32  :
                                      (pt.PIC_TOTAL_INT_PLUS1 < 64)  ? 64  :
                                      (pt.PIC_TOTAL_INT_PLUS1 < 128) ? 128 :
                                      (pt.PIC_TOTAL_INT_PLUS1 < 256) ? 256 :
                                      (pt.PIC_TOTAL_INT_PLUS1 < 512) ? 512 :  1024 ;

   localparam INT_GRPS              =   INTPEND_SIZE / 32 ;
   localparam INTPRIORITY_BITS      =  4 ;
   localparam ID_BITS               =  8 ;
   localparam int GW_CONFIG[pt.PIC_TOTAL_INT_PLUS1-1:0] = '{default:0} ;

   localparam INT_ENABLE_GRPS       =   (pt.PIC_TOTAL_INT_PLUS1 - 1)  / 4 ;

逐段解释：

* 第 L60 行：``NUM_LEVELS`` 是 ``pt.PIC_TOTAL_INT_PLUS1`` 的 ``$clog2``，后续用于 priority tree
  和地址比较切片。
* 第 L61-L68 行：各 register base address 均由 ``pt.PIC_BASE_ADDR`` 加固定偏移得到。
  本文只引用源码里的 base 名称和偏移，不额外构造 CSR 名。
* 第 L71-L75 行：``INTPEND_SIZE`` 根据 interrupt 总数扩展到 32、64、128、256、512 或
  1024 bit 桶。
* 第 L77-L83 行：pending 按 32-bit 分组，priority 固定 4 bit，ID 固定 8 bit；
  ``GW_CONFIG`` 默认全 0，``INT_ENABLE_GRPS`` 按每组 4 路 enable clock 分组。

接口关系：

* 被调用：地址匹配、read mux、gateway loop、priority tree 和 register array 使用这些参数。
* 调用：读取 ``pt.PIC_BASE_ADDR``、``pt.PIC_TOTAL_INT_PLUS1``。
* 共享状态：``NUM_LEVELS`` 同时影响地址切片和 priority tree 层数。

§3  Clock gating、地址匹配与输入寄存
------------------------------------

PIC 控制器先把 memory-mapped 地址、写数据和读写 enable 寄存，再用寄存后的地址做
base match。不同寄存器组使用独立 gated clock：地址、数据、priority、enable、delegation
和 gateway config。

§3.1  Clock enable 与 gated clock — 按访问类型使能
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 PIC memory-mapped 访问类型生成 gated clock enable，并实例化 ``rvoclkhdr``。
``pic_del_c1_clk`` 只在 ``pt.NUM_THREADS > 1`` 时启用。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L211-L224``）：

.. code-block:: systemverilog

   // ---- Clock gating section ------
   // c1 clock enables
      assign pic_raddr_c1_clken  = picm_mken | picm_rden | clk_override;
      assign pic_data_c1_clken   = picm_wren | clk_override;
      assign pic_pri_c1_clken    = (waddr_intpriority_base_match & picm_wren_ff)  | (raddr_intpriority_base_match & picm_rden_ff) | clk_override;
      assign pic_int_c1_clken    = (waddr_intenable_base_match   & picm_wren_ff)  | (raddr_intenable_base_match   & picm_rden_ff) | clk_override;
      assign gw_config_c1_clken  = (waddr_config_gw_base_match   & picm_wren_ff)  | (raddr_config_gw_base_match   & picm_rden_ff) | clk_override;

      // C1 - 1 clock pulse for data
      rvoclkhdr pic_addr_c1_cgc   ( .en(pic_raddr_c1_clken),  .l1clk(pic_raddr_c1_clk), .* );
      rvoclkhdr pic_data_c1_cgc   ( .en(pic_data_c1_clken),   .l1clk(pic_data_c1_clk), .* );
      rvoclkhdr pic_pri_c1_cgc    ( .en(pic_pri_c1_clken),    .l1clk(pic_pri_c1_clk),  .* );
      rvoclkhdr pic_int_c1_cgc    ( .en(pic_int_c1_clken),    .l1clk(pic_int_c1_clk),  .* );
      rvoclkhdr gw_config_c1_cgc  ( .en(gw_config_c1_clken),  .l1clk(gw_config_c1_clk),  .* );

逐段解释：

* 第 L213-L214 行：读地址 clock 在 mask read 或 normal read 时打开；写数据 clock 在 write
  时打开；两者都受 ``clk_override`` 强制打开。
* 第 L215-L217 行：priority、enable 和 gateway config clock 由对应写地址或读地址命中加读写
  enable 触发，也受 ``clk_override`` 控制。
* 第 L220-L224 行：五个 ``rvoclkhdr`` 分别生成地址、数据、priority、enable 和 gateway config
  的 local clock。

接口关系：

* 被调用：地址/数据寄存器、priority/enable/gateway config 寄存器使用这些 clock。
* 调用：读取 address match 信号和 ``picm_*`` enable。
* 共享状态：这些 clock enable 依赖已经寄存的 ``picm_wren_ff``、``picm_rden_ff`` 和地址 match。

§3.2  地址匹配与多线程 delegation 地址
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用寄存后的 read/write 地址与 base address 做比较，产生各寄存器组的 read/write match。
多线程下额外支持 delegation register 和 thread-filtered pending read。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L228-L254``）：

.. code-block:: systemverilog

   assign raddr_intenable_base_match   = (picm_raddr_ff[31:NUM_LEVELS+2] == INTENABLE_BASE_ADDR[31:NUM_LEVELS+2]) ;
   assign raddr_intpriority_base_match = (picm_raddr_ff[31:NUM_LEVELS+2] == INTPRIORITY_BASE_ADDR[31:NUM_LEVELS+2]) ;
   assign raddr_config_gw_base_match   = (picm_raddr_ff[31:NUM_LEVELS+2] == EXT_INTR_GW_CONFIG[31:NUM_LEVELS+2]) ;
   assign raddr_config_pic_match       = (picm_raddr_ff[31:0]            == EXT_INTR_PIC_CONFIG[31:0]) ;

   assign addr_intpend_base_match      = (picm_raddr_ff[31:6]            == INTPEND_BASE_ADDR[31:6]) ;

   assign waddr_config_pic_match       = (picm_waddr_ff[31:0]            == EXT_INTR_PIC_CONFIG[31:0]) ;
   assign addr_clear_gw_base_match     = (picm_waddr_ff[31:NUM_LEVELS+2] == EXT_INTR_GW_CLEAR[31:NUM_LEVELS+2]) ;
   assign waddr_intpriority_base_match = (picm_waddr_ff[31:NUM_LEVELS+2] == INTPRIORITY_BASE_ADDR[31:NUM_LEVELS+2]) ;
   assign waddr_intenable_base_match   = (picm_waddr_ff[31:NUM_LEVELS+2] == INTENABLE_BASE_ADDR[31:NUM_LEVELS+2]) ;
   assign waddr_config_gw_base_match   = (picm_waddr_ff[31:NUM_LEVELS+2] == EXT_INTR_GW_CONFIG[31:NUM_LEVELS+2]) ;

   if (pt.NUM_THREADS > 1 ) begin:  gt_1_thr
      assign pic_del_c1_clken    = (waddr_delg_base_match        & picm_wren_ff)  | (raddr_delg_base_match        & picm_rden_ff) | clk_override;
      rvoclkhdr pic_del_c1_cgc    ( .en(pic_del_c1_clken),    .l1clk(pic_del_c1_clk),  .* );
      assign raddr_delg_base_match        = (picm_raddr_ff[31:NUM_LEVELS+2] == EXT_INTR_DELG_REG[31:NUM_LEVELS+2]) ;
      assign waddr_delg_base_match        = (picm_waddr_ff[31:NUM_LEVELS+2] == EXT_INTR_DELG_REG[31:NUM_LEVELS+2]) ;
      assign addr_intpend_thr_base_match  = (picm_raddr_ff[31:6]            == INTPEND_THR_BASE_ADDR[31:6]) ;

逐段解释：

* 第 L228-L233 行：read address 匹配 enable、priority、gateway config、PIC config 和 pending
  base。priority/enable/gateway 使用 ``NUM_LEVELS+2`` 以上地址位比较，pending 使用
  ``[31:6]`` 比较。
* 第 L235-L239 行：write address 匹配 PIC config、gateway clear、priority、enable 和 gateway
  config base。
* 第 L241-L246 行：多线程配置下，delegation clock enable、delegation read/write match 和
  thread pending read match 才有效。

接口关系：

* 被调用：clock enable、寄存器写使能、read mux 和 delegation read/write 使用这些 match。
* 调用：读取 ``picm_raddr_ff``、``picm_waddr_ff`` 和 base address localparam。
* 共享状态：``pic_del_c1_clk`` 只在多线程 generate 分支中由 ``rvoclkhdr`` 生成。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L247-L263``）：

.. code-block:: systemverilog

   end else begin: one_t
      assign raddr_delg_base_match = 1'b0 ;
      assign waddr_delg_base_match = 1'b0 ;
      assign pic_del_c1_clk = 1'b0  ;
      assign addr_intpend_thr_base_match  = 1'b0;
   end

      assign picm_bypass_ff = picm_rden_ff & picm_wren_ff & ( picm_raddr_ff[31:0] == picm_waddr_ff[31:0] );    // pic writes and reads to same address together


   rvdff #(32) picm_radd_flop  (.*, .din (picm_rdaddr),        .dout(picm_raddr_ff),         .clk(pic_raddr_c1_clk));
   rvdff #(32) picm_wadd_flop  (.*, .din (picm_wraddr),        .dout(picm_waddr_ff),         .clk(pic_data_c1_clk));
   rvdff  #(1) picm_wre_flop   (.*, .din (picm_wren),          .dout(picm_wren_ff),          .clk(free_clk));
   rvdff  #(1) picm_rde_flop   (.*, .din (picm_rden),          .dout(picm_rden_ff),          .clk(free_clk));
   rvdff  #(1) picm_rdt_flop   (.*, .din (picm_rd_thr),        .dout(picm_rd_thr_ff),        .clk(free_clk));
   rvdff  #(1) picm_mke_flop   (.*, .din (picm_mken),          .dout(picm_mken_ff),          .clk(free_clk));
   rvdff #(32) picm_dat_flop   (.*, .din (picm_wr_data[31:0]), .dout(picm_wr_data_ff[31:0]), .clk(pic_data_c1_clk));

逐段解释：

* 第 L247-L252 行：单线程配置下，delegation 相关 match 固定为 0，``pic_del_c1_clk`` 固定为 0。
* 第 L254 行：同周期读写相同 PIC 地址时，``picm_bypass_ff`` 置位；第 L667 行用它选择返回写数据。
* 第 L257-L263 行：读地址、写地址、写使能、读使能、读线程、mask enable 和写数据分别寄存。
  读地址使用 ``pic_raddr_c1_clk``，写地址/写数据使用 ``pic_data_c1_clk``，enable 类使用
  ``free_clk``。

接口关系：

* 被调用：后续所有地址匹配和读写逻辑使用 ``picm_*_ff``。
* 调用：实例化 ``rvdff``。
* 共享状态：``picm_bypass_ff`` 连接 read data 输出选择。

§4  线程选择与两周期切分
------------------------

PIC 在 ``pt.NUM_THREADS > 1`` 时按线程 active 状态和 ``rvarbiter2_pic`` 选择当前线程。
``pt.PIC_2CYCLE`` 控制当前线程选择是否再打一拍，并控制 priority tree 是否在中间层插入寄存器。

§4.1  当前线程选择 — 单线程固定 0，多线程仲裁
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为多线程 PIC 输出选择当前服务线程。单线程时 ``curr_int_tid`` 固定为 0；多线程时用
halt status、``io_clk_override``、ready counter 和 ``rvarbiter2_pic`` 决定线程。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L267-L309``）：

.. code-block:: systemverilog

      if (pt.NUM_THREADS==1)
        assign curr_int_tid = '0;
      else begin

         logic ready_pulse;
         logic [2:0] ready_cnt_in, ready_cnt;
         logic [1:0] ready;
         logic [1:0] active_thread;
         logic       active1;
         logic       active2;
         logic       favor;
         logic       tid;


         assign ready_pulse = ready_cnt[2:0] == 3'b111;

         assign ready_cnt_in[2:0] = (ready_pulse) ? '0 : ready_cnt[2:0] + 3'b1;

         rvdff #(3) ready_cntff (.*, .din(ready_cnt_in[2:0]), .dout(ready_cnt[2:0]), .clk(free_clk));

逐段解释：

* 第 L267-L268 行：单线程配置下，当前线程 ID 固定为 0。
* 第 L271-L278 行：多线程分支声明 ready pulse、3-bit 计数器、ready bitmap、active thread
  bitmap、active1/active2、favor 和 tid。
* 第 L281-L285 行：``ready_cnt`` 达到 ``3'b111`` 时产生 ``ready_pulse`` 并回到 0，否则递增。

接口关系：

* 被调用：delegation match、per-thread output hold flops 和 threshold 选择使用当前线程。
* 调用：多线程分支实例化 ``rvdff`` 和 ``rvarbiter2_pic``。
* 共享状态：``ready_cnt`` 在 ``free_clk`` 下运行。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L288-L309``）：

.. code-block:: systemverilog

         assign active_thread[1:0] = (~o_cpu_halt_status[1:0] | {2{io_clk_override}});
         assign active1            = ^active_thread[1:0] ;
         assign active2            = &active_thread[1:0] ;



         assign ready[1:0] = (active2) ? 2'b11 :
                             (active1 & ~ready_pulse) ?  active_thread[1:0] :
                             (active1 &  ready_pulse) ? ~active_thread[1:0] :
                             {2{ready_pulse}};


         rvarbiter2_pic pic_arbiter (.*,
                                     .clk(free_clk),
                                     .shift(1'b1),
                                     .tid(tid),
                                     .favor(favor)
                                     );

         assign curr_int_tid = (|ready[1:0]) ? tid : favor;

      end

逐段解释：

* 第 L288-L290 行：active thread 来自非 halted 状态，或者在 ``io_clk_override`` 时强制 active；
  ``active1`` 表示恰有一个 active，``active2`` 表示两个线程都 active。
* 第 L294-L297 行：``ready`` 在两个线程都 active 时为 ``2'b11``；只有一个 active 时，
  每到 ``ready_pulse`` 会短暂翻转到另一个线程；都 inactive 时由 ``ready_pulse`` 复制。
* 第 L300-L305 行：``rvarbiter2_pic`` 接收 ready，固定 ``shift(1'b1)``，输出 ``tid`` 和
  ``favor``。
* 第 L307 行：只要 ready 非零就选 ``tid``，否则回退到 ``favor``。

接口关系：

* 被调用：``curr_int_tid`` 进入 per-thread output 和 delegation matching。
* 调用：读取 ``o_cpu_halt_status``、``io_clk_override`` 和 arbiter 输出。
* 共享状态：``favor`` 是 ``rvarbiter2_pic`` 内部保存并外露的仲裁偏好位。

§4.2  ``rvarbiter2_pic`` — favor 位外露的 2 路仲裁器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在两个 ready 输入之间选择 ``tid``，并把 favor 位作为输出提供给 PIC 当前线程选择逻辑。

关键代码（``rtl/design/lib/beh_lib.sv:L723-L739``）：

.. code-block:: systemverilog

   `define RV_ARBITER2          \
      assign ready0 = ~(|ready[1:0]);           \
                                                \
      assign ready1 = ready[1] ^ ready[0];      \
                                                \
      assign ready2 = ready[1] & ready[0];      \
                                                \
      assign favor_in = (ready2 & ~favor) |     \
                        (ready1 & ready[0]) |   \
                        (ready0 & favor);       \
                                                \
      // only update if 2 ready threads         \
      rvdffs #(.WIDTH(1)) favor_ff (.*, .en(shift & ready2), .clk(clk), .din(favor_in),  .dout(favor) );  \
                                                \
      // when to select tid 1                   \
      assign tid = (ready2 & favor) |           \
                   (ready[1] & ~ready[0]);

逐段解释：

* 第 L724-L728 行：``ready0``、``ready1``、``ready2`` 分别表示没有 ready、恰有一个 ready、
  两个都 ready。
* 第 L730-L735 行：``favor_in`` 在两个 ready 时翻转 favor，在单 ready 且 ready[0] 为真时选择
  0，在没有 ready 时保持 favor；``favor_ff`` 只在 ``shift & ready2`` 时更新。
* 第 L738-L739 行：``tid`` 在两个 ready 时取 favor，在仅 ready[1] 时取 1。

接口关系：

* 被调用：``eh2_pic_ctrl`` 的 ``pic_arbiter`` 实例使用该模块。
* 调用：实例化 ``rvdffs``。
* 共享状态：``favor`` 输出回到 PIC，用于 no-ready 时的线程选择。

§4.3  ``PIC_2CYCLE`` 当前线程流水
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：控制当前线程 ID 在输出路径中使用哪一拍，并在两周期模式下再打一拍。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L312-L320``）：

.. code-block:: systemverilog

      rvdff  #(1) curr_thr_ff   (.*, .din (curr_int_tid),     .dout(curr_int_tid_ff),          .clk(free_clk));

   if (pt.PIC_2CYCLE == 1) begin : pic2cyle
      assign curr_int_tid_final_in = curr_int_tid_ff ;
      rvdff  #(1) curr_thr_ff2  (.*, .din (curr_int_tid_ff),  .dout(curr_int_tid_final),          .clk(free_clk));
   end else begin: not_pic2cycle
      assign curr_int_tid_final_in = curr_int_tid ;
      assign curr_int_tid_final = curr_int_tid_ff ;
   end

逐段解释：

* 第 L312 行：``curr_int_tid`` 先在 ``free_clk`` 下寄存到 ``curr_int_tid_ff``。
* 第 L314-L317 行：两周期模式下，``curr_int_tid_final_in`` 取打一拍后的值，并再寄存到
  ``curr_int_tid_final``。
* 第 L317-L320 行：非两周期模式下，``curr_int_tid_final_in`` 直接取当前组合线程，
  ``curr_int_tid_final`` 使用前一拍 ``curr_int_tid_ff``。

接口关系：

* 被调用：per-thread output hold flops 和 output mux 使用 ``curr_int_tid_final``、
  ``curr_int_tid_final_in``。
* 调用：实例化 ``rvdff``。
* 共享状态：该分支与 priority tree 的 ``pt.PIC_2CYCLE`` 分支共同决定时序切分。

§5  Gateway 与每路配置寄存器
----------------------------

每个非 0 interrupt 入口有 priority、enable、delegation、gateway config 和 gateway clear
相关逻辑。interrupt 0 在 ``INT_ZERO`` 分支中被固定为不可用，这与 ``eh2_veer`` 实例把
``extintsrc_req`` bit 0 接为 0 相互对应。

§5.1  Gateway 分组 clock 与 ``eh2_configurable_gw`` 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 4 路 interrupt 分组生成 gateway clock enable，并为每个可用 interrupt 实例化
``eh2_configurable_gw``。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L325-L352``）：

.. code-block:: systemverilog

   genvar i ;
   genvar p ;
   for (p=0; p<=INT_ENABLE_GRPS ; p++) begin  : IO_CLK_GRP
   wire grp_clk, grp_clken;

       assign grp_clken = |intenable_clk_enable[(p==INT_ENABLE_GRPS?pt.PIC_TOTAL_INT_PLUS1-1:p*4+3) : p*4] | io_clk_override;

     `ifndef RV_FPGA_OPTIMIZE
       rvclkhdr intenable_c1_cgc( .en(grp_clken),  .l1clk(grp_clk), .* );
     `else
       assign gw_clk[p] = 1'b0 ;
     `endif


       for(genvar i= (p==0 ? 1: 0); i< (p==INT_ENABLE_GRPS ? pt.PIC_TOTAL_INT_PLUS1-p*4 :4); i++) begin : GW
           eh2_configurable_gw gw_inst(
                .*,
               .gw_clk(grp_clk),
               .rawclk(clk),
               .clken (grp_clken),
               .extintsrc_req(extintsrc_req[i+p*4]) ,

逐段解释：

* 第 L327-L330 行：outer loop 按 ``INT_ENABLE_GRPS`` 分组；``grp_clken`` 由该组
  ``intenable_clk_enable`` 的 OR 或 ``io_clk_override`` 产生。
* 第 L332-L336 行：非 FPGA 优化路径用 ``rvclkhdr`` 生成 ``grp_clk``；FPGA 优化路径把
  ``gw_clk[p]`` 赋为 0。当前片段没有给 ``grp_clk`` 在 FPGA 分支赋值，本文不推导宏展开后的工具行为。
* 第 L339-L340 行：inner loop 在第 0 组从 ``i=1`` 开始，跳过 interrupt 0；其他组从 0 开始。
* 第 L340-L345 行：每路实例化 ``eh2_configurable_gw``，连接 ``gw_clk``、``rawclk``、
  ``clken`` 和对应 ``extintsrc_req``。

接口关系：

* 被调用：每路 gateway 输出 ``extintsrc_req_gw``，后续参与 pending/priority。
* 调用：实例化 ``rvclkhdr`` 和 ``eh2_configurable_gw``。
* 共享状态：``intenable_clk_enable`` 由 enable/config/clear 状态共同决定。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L345-L350``）：

.. code-block:: systemverilog

               .extintsrc_req(extintsrc_req[i+p*4]) ,
               .meigwctrl_polarity(gw_config_reg[i+p*4][0]) ,
               .meigwctrl_type(gw_config_reg[i+p*4][1]) ,
               .meigwclr(gw_clear_reg_we[i+p*4]) ,
               .extintsrc_req_config(extintsrc_req_gw[i+p*4])
           );

逐段解释：

* 第 L345-L348 行：gateway 输入包括原始外部中断、polarity、type 和 clear。polarity/type
  来自 ``gw_config_reg``，clear 来自 gateway clear 写使能。
* 第 L349 行：gateway 输出 ``extintsrc_req_config`` 接到 ``extintsrc_req_gw``，这是后续
  pending 逻辑使用的中断请求。

接口关系：

* 被调用：``intpend_w_prior_en`` 和 pending read path 读取 ``extintsrc_req_gw``。
* 调用：读取 ``gw_config_reg`` 和 ``gw_clear_reg_we``。
* 共享状态：gateway config 寄存器写入后影响该路中断的极性和类型处理。

§5.2  每路寄存器写读使能 — priority、enable、delegation、gateway config
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：对每个非 0 interrupt 生成 priority、enable、delegation、gateway config 和 gateway
clear 的读写使能，并实例化对应寄存器。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L354-L383``）：

.. code-block:: systemverilog

   for (i=0; i<pt.PIC_TOTAL_INT_PLUS1 ; i++) begin  : SETREG

    if (i > 0 ) begin : NON_ZERO_INT
        assign intpriority_reg_we[i] =  waddr_intpriority_base_match & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff;
        assign intpriority_reg_re[i] =  raddr_intpriority_base_match & (picm_raddr_ff[NUM_LEVELS+1:2] == i) & picm_rden_ff;

        assign intenable_reg_we[i]   =  waddr_intenable_base_match   & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff;
        assign intenable_reg_re[i]   =  raddr_intenable_base_match   & (picm_raddr_ff[NUM_LEVELS+1:2] == i) & picm_rden_ff;

        if (pt.NUM_THREADS > 1 ) begin:   gt_1_thr
             assign delg_reg_we[i]   =  waddr_delg_base_match   & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff;
             assign delg_reg_re[i]   =  raddr_delg_base_match   & (picm_raddr_ff[NUM_LEVELS+1:2] == i) & picm_rden_ff;
             rvdffs #(1)                 delg_ff        (.*, .en( delg_reg_we[i]),        .din (picm_wr_data_ff[0]),                    .dout(delg_reg[i]),        .clk(pic_del_c1_clk));
        end else begin: one_t
             assign delg_reg_re[i] = 1'b0 ;
             assign delg_reg_we[i] = 1'b0 ;

逐段解释：

* 第 L354-L356 行：``SETREG`` 遍历 ``pt.PIC_TOTAL_INT_PLUS1``，但只有 ``i > 0`` 进入
  ``NON_ZERO_INT`` 分支。
* 第 L357-L361 行：priority 和 enable 的写/读使能要求 base match、地址 index 等于 ``i``，
  并且对应 ``picm_wren_ff`` 或 ``picm_rden_ff`` 有效。
* 第 L363-L366 行：多线程配置下，delegation register 也按 base match 和 index 生成读写使能，
  并用 ``picm_wr_data_ff[0]`` 写入 ``delg_reg[i]``。
* 第 L367-L369 行：单线程配置下 delegation 读写使能固定为 0。

接口关系：

* 被调用：寄存器实例、read mux 和 delegation thread match 读取这些使能。
* 调用：读取 address match、``picm_*_ff`` 和 ``pt.NUM_THREADS``。
* 共享状态：``delg_reg`` 参与中断归属线程判断。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L370-L413``）：

.. code-block:: systemverilog

             assign delg_reg[i]    = 1'b0;
        end


        assign gw_config_reg_we[i]   =  waddr_config_gw_base_match   & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff;
        assign gw_config_reg_re[i]   =  raddr_config_gw_base_match   & (picm_raddr_ff[NUM_LEVELS+1:2] == i) & picm_rden_ff;

        assign gw_clear_reg_we[i]    =  addr_clear_gw_base_match     & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff ;

        rvdffs #(INTPRIORITY_BITS) intpriority_ff  (.*, .en( intpriority_reg_we[i]), .din (picm_wr_data_ff[INTPRIORITY_BITS-1:0]), .dout(intpriority_reg[i]), .clk(pic_pri_c1_clk));
        rvdffs #(1)                 intenable_ff   (.*, .en( intenable_reg_we[i]),   .din (picm_wr_data_ff[0]),                    .dout(intenable_reg[i]),   .clk(pic_int_c1_clk));
        rvdffs #(2)                 gw_config_ff   (.*, .en( gw_config_reg_we[i]),   .din (picm_wr_data_ff[1:0]),                  .dout(gw_config_reg[i]),   .clk(gw_config_c1_clk));

        assign intenable_clk_enable[i]  =  gw_config_reg[i][1] | intenable_reg_we[i] | intenable_reg[i] | gw_clear_reg_we[i] ;


    end else begin : INT_ZERO
        assign intpriority_reg_we[i] =  1'b0 ;
        assign intpriority_reg_re[i] =  1'b0 ;

逐段解释：

* 第 L374-L377 行：gateway config 和 gateway clear 的使能同样由 base match、index 和写/读
  enable 生成。
* 第 L379-L381 行：priority 寄存器写入 ``picm_wr_data_ff`` 的低 4 bit；enable 写入 bit 0；
  gateway config 写入低 2 bit。
* 第 L383 行：该路 gateway clock enable 由 gateway type bit、enable 写、enable 当前值或
  gateway clear 写共同打开。
* 第 L386-L389 行：interrupt 0 分支把 priority/enable 的读写使能固定为 0。

接口关系：

* 被调用：gateway clock 分组、pending priority 输入和 read mux 读取这些寄存器。
* 调用：实例化 ``rvdffs``。
* 共享状态：``intenable_clk_enable`` 反馈到 gateway clock enable 生成。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L390-L413``）：

.. code-block:: systemverilog

        assign intenable_reg_we[i]   =  1'b0 ;
        assign intenable_reg_re[i]   =  1'b0 ;
        assign delg_reg_re[i]        =  1'b0 ;
        assign delg_reg_we[i]        =  1'b0 ;
        assign gw_config_reg_we[i]   =  1'b0 ;
        assign gw_config_reg_re[i]   =  1'b0 ;
        assign gw_clear_reg_we[i]    =  1'b0 ;

        assign gw_config_reg[i]    = '0 ;

        assign intpriority_reg[i] = {INTPRIORITY_BITS{1'b0}} ;
        assign intenable_reg[i]   = 1'b0 ;
        assign delg_reg[i]        = 1'b0 ;
        assign extintsrc_req_gw[i] = 1'b0 ;
        assign extintsrc_req_sync[i]    = 1'b0 ;
        assign intenable_clk_enable[i] = 1'b0;
    end


       assign intpriority_reg_inv[i] =  intpriord ? ~intpriority_reg[i] : intpriority_reg[i] ;
       assign delg_thr_match[i]      =  (delg_reg[i] &  curr_int_tid) |   (~delg_reg[i] & ~curr_int_tid) ;

       assign intpend_w_prior_en[i]  =  {INTPRIORITY_BITS{(extintsrc_req_gw[i] & intenable_reg[i] & delg_thr_match[i])}} & intpriority_reg_inv[i] ;
       assign intpend_id[i]          =  i ;
   end

逐段解释：

* 第 L390-L404 行：interrupt 0 的 enable、delegation、gateway config、gateway output、
  priority 和 clock enable 全部固定为 0。
* 第 L408 行：``intpriority_reg_inv`` 在 ``intpriord`` 为真时取反 priority，否则使用原 priority。
* 第 L409 行：``delg_thr_match`` 根据 delegation bit 和当前线程决定该中断是否属于当前线程。
* 第 L411 行：只有 gateway pending、interrupt enable 和 delegation/thread match 都为真时，
  priority 才进入 ``intpend_w_prior_en``。
* 第 L412 行：``intpend_id`` 直接等于 loop index ``i``。

接口关系：

* 被调用：priority tree 读取 ``intpend_w_prior_en`` 和 ``intpend_id``。
* 调用：读取 gateway 输出、enable、delegation、current thread 和 priority order config。
* 共享状态：``intpriord`` 来自 PIC config register。

§6  Priority tree 与输出阈值
----------------------------

优先级树通过 ``eh2_cmp_and_mux`` 两两比较 priority 和 id。``pt.PIC_2CYCLE`` 为 1 时在中间层
插入寄存器；否则整棵树组合完成。最终输出 ``claimid_in`` 和 ``selected_int_priority``。

§6.1  两周期 priority tree — 中间层寄存
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 ``pt.PIC_2CYCLE == 1`` 时，把 priority tree 拆成 top half 和 bottom half，中间层
用 ``rvdffie`` 寄存 priority/id。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L421-L456``）：

.. code-block:: systemverilog

   if (pt.PIC_2CYCLE == 1) begin : genblock
           logic [NUM_LEVELS/2:0] [pt.PIC_TOTAL_INT_PLUS1+2:0] [INTPRIORITY_BITS-1:0] level_intpend_w_prior_en;
           logic [NUM_LEVELS/2:0] [pt.PIC_TOTAL_INT_PLUS1+2:0] [ID_BITS-1:0]          level_intpend_id;

           assign level_intpend_w_prior_en[0][pt.PIC_TOTAL_INT_PLUS1+2:0] = {4'b0,4'b0,4'b0,intpend_w_prior_en[pt.PIC_TOTAL_INT_PLUS1-1:0]} ;
           assign level_intpend_id[0][pt.PIC_TOTAL_INT_PLUS1+2:0]         = {8'b0,8'b0,8'b0,intpend_id[pt.PIC_TOTAL_INT_PLUS1-1:0]} ;


           assign levelx_intpend_w_prior_en[NUM_LEVELS/2][(pt.PIC_TOTAL_INT_PLUS1/2**(NUM_LEVELS/2))+1:0] = {{1*INTPRIORITY_BITS{1'b0}},l2_intpend_w_prior_en_ff[(pt.PIC_TOTAL_INT_PLUS1/2**(NUM_LEVELS/2)):0]} ;
           assign levelx_intpend_id[NUM_LEVELS/2][(pt.PIC_TOTAL_INT_PLUS1/2**(NUM_LEVELS/2))+1:0]         = {{1*ID_BITS{1'b1}},l2_intpend_id_ff[(pt.PIC_TOTAL_INT_PLUS1/2**(NUM_LEVELS/2)):0]} ;
   ///  Do the prioritization of the interrupts here  ////////////
    for (l=0; l<NUM_LEVELS/2 ; l++) begin : TOP_LEVEL
       for (m=0; m<=(pt.PIC_TOTAL_INT_PLUS1)/(2**(l+1)) ; m++) begin : COMPARE

逐段解释：

* 第 L421-L423 行：两周期分支声明前半段 priority/id level 数组。
* 第 L425-L426 行：level 0 在有效 interrupt 向量前补 3 个 0 priority/id 项。
* 第 L429-L430 行：后半段 level 输入来自中间寄存器 ``l2_intpend_*_ff``，并在前面补一项。
* 第 L432-L433 行：top half 循环从 level 0 到 ``NUM_LEVELS/2 - 1``，每层继续按二叉比较缩减。

接口关系：

* 被调用：两周期模式下的 priority tree 输出。
* 调用：实例化 ``eh2_cmp_and_mux`` 和中间层 ``rvdffie``。
* 共享状态：``l2_intpend_w_prior_en_ff``、``l2_intpend_id_ff`` 是两周期模式的中间寄存器。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L438-L478``）：

.. code-block:: systemverilog

          eh2_cmp_and_mux  #(.ID_BITS(ID_BITS),
                         .INTPRIORITY_BITS(INTPRIORITY_BITS)) cmp_l1 (
                         .a_id(level_intpend_id[l][2*m]),
                         .a_priority(level_intpend_w_prior_en[l][2*m]),
                         .b_id(level_intpend_id[l][2*m+1]),
                         .b_priority(level_intpend_w_prior_en[l][2*m+1]),
                         .out_id(level_intpend_id[l+1][m]),
                         .out_priority(level_intpend_w_prior_en[l+1][m])) ;

       end
    end

           for (i=0; i<=pt.PIC_TOTAL_INT_PLUS1/2**(NUM_LEVELS/2) ; i++) begin : MIDDLE_FLOPS

              rvdffie #(INTPRIORITY_BITS+ID_BITS) level2_intpend_reg  (.*,
                                                                       .din ({level_intpend_w_prior_en[NUM_LEVELS/2][i], level_intpend_id[NUM_LEVELS/2][i]}),
                                                                       .dout({l2_intpend_w_prior_en_ff[i],               l2_intpend_id_ff[i]})
                                                                       );
           end

    for (j=NUM_LEVELS/2; j<NUM_LEVELS ; j++) begin : BOT_LEVELS

逐段解释：

* 第 L438-L445 行：每个比较节点实例化 ``eh2_cmp_and_mux``，输入两个 id/priority，输出胜出的
  id/priority 到下一层。
* 第 L450-L456 行：``MIDDLE_FLOPS`` 将 ``NUM_LEVELS/2`` 层结果打入
  ``l2_intpend_w_prior_en_ff`` 和 ``l2_intpend_id_ff``。
* 第 L458 行：bottom half 从 ``NUM_LEVELS/2`` 层继续向最终 level 比较。

接口关系：

* 被调用：``claimid_in`` 和 ``selected_int_priority`` 读取最终层输出。
* 调用：``eh2_cmp_and_mux`` 负责单节点比较。
* 共享状态：中间层寄存器改变两周期模式下的输出时序。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L458-L478``）：

.. code-block:: systemverilog

    for (j=NUM_LEVELS/2; j<NUM_LEVELS ; j++) begin : BOT_LEVELS
       for (k=0; k<=(pt.PIC_TOTAL_INT_PLUS1)/(2**(j+1)) ; k++) begin : COMPARE
          if ( k == (pt.PIC_TOTAL_INT_PLUS1)/(2**(j+1))) begin
               assign levelx_intpend_w_prior_en[j+1][k+1] = '0 ;
               assign levelx_intpend_id[j+1][k+1]         = '0 ;
          end
               eh2_cmp_and_mux  #(.ID_BITS(ID_BITS),
                           .INTPRIORITY_BITS(INTPRIORITY_BITS))
                    cmp_l1 (
                           .a_id(levelx_intpend_id[j][2*k]),
                           .a_priority(levelx_intpend_w_prior_en[j][2*k]),
                           .b_id(levelx_intpend_id[j][2*k+1]),
                           .b_priority(levelx_intpend_w_prior_en[j][2*k+1]),
                           .out_id(levelx_intpend_id[j+1][k]),
                           .out_priority(levelx_intpend_w_prior_en[j+1][k])) ;
       end
     end

           assign claimid_in[ID_BITS-1:0]                      =      levelx_intpend_id[NUM_LEVELS][0] ;   // This is the last level output
           assign selected_int_priority[INTPRIORITY_BITS-1:0]  =      levelx_intpend_w_prior_en[NUM_LEVELS][0] ;
   end

逐段解释：

* 第 L459-L463 行：bottom half 每层最后一个边界项被补 0，避免比较树越界使用未定义输入。
* 第 L464-L472 行：bottom half 同样使用 ``eh2_cmp_and_mux`` 两两比较。
* 第 L476-L477 行：最终层 0 号元素给出 ``claimid_in`` 和 ``selected_int_priority``。

接口关系：

* 被调用：输出 hold flops 和 threshold 比较读取最终 priority/id。
* 调用：``eh2_cmp_and_mux``。
* 共享状态：两周期分支结束后与非两周期分支共享 ``claimid_in`` 和
  ``selected_int_priority``。

§6.2  单周期 priority tree — 全组合比较
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 ``pt.PIC_2CYCLE != 1`` 时，用一棵组合比较树直接从 ``intpend_w_prior_en`` 得到最终
claim id 和 priority。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L479-L508``）：

.. code-block:: systemverilog

   else begin : genblock

           logic [NUM_LEVELS:0] [pt.PIC_TOTAL_INT_PLUS1+1:0] [INTPRIORITY_BITS-1:0] level_intpend_w_prior_en;
           logic [NUM_LEVELS:0] [pt.PIC_TOTAL_INT_PLUS1+1:0] [ID_BITS-1:0]          level_intpend_id;

           assign level_intpend_w_prior_en[0][pt.PIC_TOTAL_INT_PLUS1+1:0] = {{2*INTPRIORITY_BITS{1'b0}},intpend_w_prior_en[pt.PIC_TOTAL_INT_PLUS1-1:0]} ;
           assign level_intpend_id[0][pt.PIC_TOTAL_INT_PLUS1+1:0] = {{2*ID_BITS{1'b1}},intpend_id[pt.PIC_TOTAL_INT_PLUS1-1:0]} ;

   ///  Do the prioritization of the interrupts here  ////////////
   // genvar l, m , j, k;  already declared outside ifdef
    for (l=0; l<NUM_LEVELS ; l++) begin : LEVEL
       for (m=0; m<=(pt.PIC_TOTAL_INT_PLUS1)/(2**(l+1)) ; m++) begin : COMPARE
          if ( m == (pt.PIC_TOTAL_INT_PLUS1)/(2**(l+1))) begin
               assign level_intpend_w_prior_en[l+1][m+1] = '0 ;
               assign level_intpend_id[l+1][m+1]         = '0 ;
          end
          eh2_cmp_and_mux  #(.ID_BITS(ID_BITS),
                         .INTPRIORITY_BITS(INTPRIORITY_BITS)) cmp_l1 (
                         .a_id(level_intpend_id[l][2*m]),

逐段解释：

* 第 L479-L482 行：非两周期分支声明从 level 0 到 ``NUM_LEVELS`` 的 priority/id 数组。
* 第 L484-L485 行：level 0 在有效输入前补两项 0 priority 和 all-ones id。
* 第 L489-L490 行：循环覆盖全部 ``NUM_LEVELS`` 层，不插入中间寄存器。
* 第 L491-L497 行：每层末尾补 0，并实例化 ``eh2_cmp_and_mux``。

接口关系：

* 被调用：非两周期模式下生成 ``claimid_in`` 和 ``selected_int_priority``。
* 调用：``eh2_cmp_and_mux``。
* 共享状态：输入同样来自 ``intpend_w_prior_en`` 和 ``intpend_id``。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L497-L508``）：

.. code-block:: systemverilog

                         .a_id(level_intpend_id[l][2*m]),
                         .a_priority(level_intpend_w_prior_en[l][2*m]),
                         .b_id(level_intpend_id[l][2*m+1]),
                         .b_priority(level_intpend_w_prior_en[l][2*m+1]),
                         .out_id(level_intpend_id[l+1][m]),
                         .out_priority(level_intpend_w_prior_en[l+1][m])) ;

       end
    end
           assign claimid_in[ID_BITS-1:0]                      =      level_intpend_id[NUM_LEVELS][0] ;   // This is the last level output
           assign selected_int_priority[INTPRIORITY_BITS-1:0]  =      level_intpend_w_prior_en[NUM_LEVELS][0] ;

   end

逐段解释：

* 第 L497-L502 行：比较节点连接当前层两个候选项，输出到下一层同一 index。
* 第 L506-L507 行：最终层 0 号元素给出 claim id 和 selected priority。

接口关系：

* 被调用：阈值比较、output flops 和 wakeup 逻辑读取最终结果。
* 调用：``eh2_cmp_and_mux``。
* 共享状态：与两周期分支共享同名输出信号。

§6.3  ``eh2_cmp_and_mux`` — priority 大者胜出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：比较两个候选中断的 priority，选择 priority 更大的候选；如果 ``a_priority`` 不小于
``b_priority``，输出 a。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L678-L700``）：

.. code-block:: systemverilog

   module eh2_cmp_and_mux #(parameter ID_BITS=8,
                                  INTPRIORITY_BITS = 4)
                       (
                           input  logic [ID_BITS-1:0]       a_id,
                           input  logic [INTPRIORITY_BITS-1:0] a_priority,

                           input  logic [ID_BITS-1:0]       b_id,
                           input  logic [INTPRIORITY_BITS-1:0] b_priority,

                           output logic [ID_BITS-1:0]       out_id,
                           output logic [INTPRIORITY_BITS-1:0] out_priority

                       );

   logic   a_is_lt_b ;

   assign  a_is_lt_b  = ( a_priority[INTPRIORITY_BITS-1:0] < b_priority[INTPRIORITY_BITS-1:0] ) ;

   assign  out_id[ID_BITS-1:0]                = a_is_lt_b ? b_id[ID_BITS-1:0] :
                                                            a_id[ID_BITS-1:0] ;
   assign  out_priority[INTPRIORITY_BITS-1:0] = a_is_lt_b ? b_priority[INTPRIORITY_BITS-1:0] :
                                                            a_priority[INTPRIORITY_BITS-1:0] ;
   endmodule // cmp_and_mux

逐段解释：

* 第 L678-L690 行：模块参数化 id 宽度和 priority 宽度，输入 a/b 两个候选，输出一个候选。
* 第 L692-L694 行：``a_is_lt_b`` 仅在 a priority 小于 b priority 时为真。
* 第 L696-L699 行：当 ``a_is_lt_b`` 为真时选择 b；否则选择 a。这意味着 priority 相等时保留
  a 输入。结合 priority tree 的输入顺序，可回溯同优先级保留左侧候选。

接口关系：

* 被调用：priority tree 每个比较节点实例化该模块。
* 调用：无子模块。
* 共享状态：纯组合模块，不保存状态。

§7  Config、threshold、输出寄存与 wakeup
----------------------------------------

PIC config register 的 bit 0 进入 ``intpriord``，控制 priority 是否取反。最终 interrupt pending
要求 selected priority 同时大于 ``meipt`` 和 ``meicurpl`` 的当前值。wakeup 在输出 priority
等于最大 priority 时置位。

§7.1  PIC config 与 priority order
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：保存 PIC config bit，并用它控制 priority 取反路径。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L513-L531``）：

.. code-block:: systemverilog

   ///////////////////////////////////////////////////////////////////////
   // Config Reg`
   ///////////////////////////////////////////////////////////////////////
   assign config_reg_we               =  waddr_config_pic_match & picm_wren_ff;
   assign config_reg_re               =  raddr_config_pic_match & picm_rden_ff;

   assign config_reg_in  =  picm_wr_data_ff[0] ;   //
   rvdffs #(1) config_reg_ff  (.*, .clk(free_clk), .en(config_reg_we), .din (config_reg_in), .dout(config_reg));

   assign intpriord  = config_reg ;


   //////////////////////////////////////////////////////////////////////////
   // Send the interrupt to the core if it is above the thresh-hold
   //////////////////////////////////////////////////////////////////////////
   ///////////////////////////////////////////////////////////
   /// ClaimId  Reg and Corresponding PL
   ///////////////////////////////////////////////////////////
   assign pl_in_q[INTPRIORITY_BITS-1:0] = intpriord ? ~pl_in : pl_in ;

逐段解释：

* 第 L516-L517 行：PIC config 的写/读使能来自 config address match 和 ``picm_wren_ff``/
  ``picm_rden_ff``。
* 第 L519-L520 行：config 只写入 ``picm_wr_data_ff[0]``，并在 ``free_clk`` 下寄存到
  ``config_reg``。
* 第 L522 行：``intpriord`` 直接等于 ``config_reg``。
* 第 L531 行：``pl_in_q`` 在 ``intpriord`` 为真时取反 ``pl_in``，否则保持原 priority。

接口关系：

* 被调用：priority 输入取反、threshold 比较和 read mux 读取 ``config_reg``/``intpriord``。
* 调用：实例化 ``rvdffs``。
* 共享状态：``config_reg`` 也可通过 read mux 返回。

§7.2  多线程输出 hold flops 与输出 mux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在多线程配置下为线程 0/1 分别保存 pending、priority、claim id 和 wakeup，再根据
``curr_int_tid_final`` 选择当前值或保持值输出。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L533-L570``）：

.. code-block:: systemverilog

   if (pt.NUM_THREADS > 1 ) begin:   more_than_1_thr

   //  Per thread hold flops

     rvdffe  #(.WIDTH(1),.OVERRIDE(1))                mexintpend_fl_thr0  (.*, .din (mexintpend_in ), .dout(mexintpend[0]), .en(~curr_int_tid_final_in));
     rvdffe  #(.WIDTH(1),.OVERRIDE(1))                mexintpend_fl_thr1  (.*, .din (mexintpend_in ), .dout(mexintpend[1]), .en( curr_int_tid_final_in));

     rvdffe  #(.WIDTH(INTPRIORITY_BITS),.OVERRIDE(1)) pl_fl_thr0      (.*, .din (pl_in_q[INTPRIORITY_BITS-1:0]), .dout(pl[0][INTPRIORITY_BITS-1:0]), .en(~curr_int_tid_final_in));
     rvdffe  #(.WIDTH(INTPRIORITY_BITS),.OVERRIDE(1)) pl_fl_thr1      (.*, .din (pl_in_q[INTPRIORITY_BITS-1:0]), .dout(pl[1][INTPRIORITY_BITS-1:0]), .en( curr_int_tid_final_in));

     rvdffe  #(.WIDTH(ID_BITS),.OVERRIDE(1))          claimid_fl_thr0 (.*, .din (claimid_in[ID_BITS-1:00]),      .dout(claimid[0][ID_BITS-1:00]), .en(~curr_int_tid_final_in));
     rvdffe  #(.WIDTH(ID_BITS),.OVERRIDE(1))          claimid_fl_thr1 (.*, .din (claimid_in[ID_BITS-1:00]),      .dout(claimid[1][ID_BITS-1:00]), .en( curr_int_tid_final_in));

     rvdffe  #(.WIDTH(1),.OVERRIDE(1))                wake_up_ff_thr0      (.*, .din (mhwakeup_in),    .dout(mhwakeup[0]),       .en(~curr_int_tid_final_in));

逐段解释：

* 第 L533-L538 行：多线程分支为每个线程分别保存 ``mexintpend``；enable 根据
  ``curr_int_tid_final_in`` 选择线程。
* 第 L540-L541 行：priority level 同样分线程保存。
* 第 L543-L544 行：claim id 按线程保存，输入来自 priority tree 的 ``claimid_in``。
* 第 L546 行：线程 0 wakeup 保存逻辑使用 ``mhwakeup_in`` 和 ``~curr_int_tid_final_in``。

接口关系：

* 被调用：多线程输出 mux 读取这些 hold flops。
* 调用：实例化 ``rvdffe``。
* 共享状态：``curr_int_tid_final_in`` 控制当前更新哪一个线程的输出状态。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L547-L570``）：

.. code-block:: systemverilog

     rvdffe  #(.WIDTH(1),.OVERRIDE(1))                wake_up_ff_thr1      (.*, .din (mhwakeup_in),    .dout(mhwakeup[1]),       .en( curr_int_tid_final_in));

   ///////


     rvdffie #(2*ID_BITS)          claimid_ff_f2     (.*, .din (claimid),      .dout(claimid_ff) );
     rvdff   #(2*INTPRIORITY_BITS) pl_ff_f2          (.*, .din (pl),           .dout(pl_ff), .clk(free_clk));
     rvdff   #(2)                  mexintpend_ff_f2  (.*, .clk(free_clk),      .din (mexintpend[1:0]), .dout(mexintpend_ff[1:0]));
     rvdff   #(2)                  wake_up_ff_f2     (.*, .clk(free_clk),      .din (mhwakeup[1:0]),   .dout(mhwakeup_ff[1:0]));

     assign claimid_out[0]  =  curr_int_tid_final ?  claimid_ff[0] : claimid[0] ;
     assign claimid_out[1]  = ~curr_int_tid_final ?  claimid_ff[1] : claimid[1] ;

     assign  pl_out[0]      =  curr_int_tid_final ?  pl_ff[0]: pl[0];
     assign  pl_out[1]      = ~curr_int_tid_final ?  pl_ff[1]: pl[1];

     assign  mexintpend_out[0]      =  curr_int_tid_final ?  mexintpend_ff[0] : mexintpend[0] ;
     assign  mexintpend_out[1]      = ~curr_int_tid_final ?  mexintpend_ff[1] : mexintpend[1] ;

     assign mhwakeup_out[0] =    curr_int_tid_final ?   mhwakeup_ff[0] : mhwakeup[0] ;
     assign mhwakeup_out[1] =   ~curr_int_tid_final ?   mhwakeup_ff[1] : mhwakeup[1] ;

     assign meipt    =  curr_int_tid_final_in ? dec_tlu_meipt[1]    : dec_tlu_meipt[0] ;
     assign meicurpl =  curr_int_tid_final_in ? dec_tlu_meicurpl[1] : dec_tlu_meicurpl[0] ;

逐段解释：

* 第 L547 行：线程 1 wakeup 保存逻辑使用 ``curr_int_tid_final_in`` 作为 enable。
* 第 L552-L555 行：claim id、priority、pending、wakeup 再打一拍形成 ``*_ff`` 版本。
* 第 L557-L567 行：输出 mux 对当前线程使用当前值，对非当前线程使用保持值，避免未服务线程输出被覆盖。
* 第 L569-L570 行：threshold/current priority 输入按 ``curr_int_tid_final_in`` 从线程 0/1
  选择。

接口关系：

* 被调用：core 观察 ``claimid_out``、``pl_out``、``mexintpend_out``、``mhwakeup_out``。
* 调用：实例化 ``rvdffie``、``rvdff``。
* 共享状态：``dec_tlu_meipt`` 和 ``dec_tlu_meicurpl`` 是阈值比较输入。

§7.3  单线程输出与阈值比较
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：单线程配置直接保存并输出 pending、claim id、priority 和 wakeup；随后统一执行
threshold/current priority 比较。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L572-L596``）：

.. code-block:: systemverilog

   end else begin : one_thread

     rvdff   #(1)                mexintpend_fl (.*,  .din (mexintpend_in),                 .dout(mexintpend), .clk(free_clk));
     rvdffie #(ID_BITS)          claimid_fl    (.*,  .din (claimid_in[ID_BITS-1:00]),      .dout(claimid) );
     rvdff   #(INTPRIORITY_BITS) pl_fl         (.*,  .din (pl_in_q[INTPRIORITY_BITS-1:0]), .dout(pl),         .clk(free_clk));
     rvdff   #(1)                wake_up_ff    (.*,  .din (mhwakeup_in),                   .dout(mhwakeup),   .clk(free_clk));


     assign claimid_out[pt.NUM_THREADS-1:0]    = claimid[pt.NUM_THREADS-1:0];
     assign pl_out[pt.NUM_THREADS-1:0]         = pl[pt.NUM_THREADS-1:0] ;
     assign mexintpend_out[pt.NUM_THREADS-1:0] = mexintpend[pt.NUM_THREADS-1:0] ;
     assign mhwakeup_out[pt.NUM_THREADS-1:0]   = mhwakeup[pt.NUM_THREADS-1:0] ;

     assign meipt    =  dec_tlu_meipt[0] ;
     assign meicurpl =  dec_tlu_meicurpl[0] ;

   end

   assign meipt_inv[INTPRIORITY_BITS-1:0]    = intpriord ? ~meipt[INTPRIORITY_BITS-1:0]    : meipt[INTPRIORITY_BITS-1:0] ;
   assign meicurpl_inv[INTPRIORITY_BITS-1:0] = intpriord ? ~meicurpl[INTPRIORITY_BITS-1:0] : meicurpl[INTPRIORITY_BITS-1:0] ;
   assign mexintpend_in = (( selected_int_priority[INTPRIORITY_BITS-1:0] > meipt_inv[INTPRIORITY_BITS-1:0]) &

逐段解释：

* 第 L574-L577 行：单线程分支用 ``rvdff``/``rvdffie`` 保存 pending、claim id、priority 和 wakeup。
* 第 L580-L586 行：单线程输出直接来自这些寄存器，threshold/current priority 取线程 0。
* 第 L590-L591 行：``intpriord`` 为真时，threshold 和 current priority 也取反后参与比较。
* 第 L592 行：``mexintpend_in`` 的第一部分要求 selected priority 大于 ``meipt_inv``。

接口关系：

* 被调用：单线程 core 输出直接读取这些寄存器。
* 调用：实例化 ``rvdff``、``rvdffie``。
* 共享状态：阈值比较在单线程和多线程分支之后共用。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L592-L596``）：

.. code-block:: systemverilog

   assign mexintpend_in = (( selected_int_priority[INTPRIORITY_BITS-1:0] > meipt_inv[INTPRIORITY_BITS-1:0]) &
                           ( selected_int_priority[INTPRIORITY_BITS-1:0] > meicurpl_inv[INTPRIORITY_BITS-1:0]) );

   assign maxint[INTPRIORITY_BITS-1:0]      =  intpriord ? 0 : 15 ;
   assign mhwakeup_in = ( pl_in_q[INTPRIORITY_BITS-1:0] == maxint) ;

逐段解释：

* 第 L592-L593 行：external interrupt pending 要求 selected priority 同时大于 priority threshold
  和 current priority。
* 第 L595 行：最大 priority 在 normal order 下为 15，在 inverted order 下为 0。
* 第 L596 行：``mhwakeup_in`` 在输出 priority 等于 ``maxint`` 时置位。

接口关系：

* 被调用：pending/wakeup 输出寄存器读取 ``mexintpend_in`` 和 ``mhwakeup_in``。
* 调用：读取 selected priority、threshold、current priority 和 ``pl_in_q``。
* 共享状态：``intpriord`` 同时影响 priority 输入、threshold 比较和 max priority。

§8  Read path 与 include 边界
-----------------------------

PIC read path 先根据地址 match 产生 read select，再分别汇总 pending、thread pending、enable、
delegation、priority、gateway config、config 和 mask read data。最终 ``picm_rd_data`` 在
同地址读写冲突时 bypass 写数据。

§8.1  Pending read 与 per-register read select
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 pending、thread pending、priority、enable、delegation 和 gateway config 的 read
条件，并构造 pending 扩展向量。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L605-L621``）：

.. code-block:: systemverilog

   assign intpend_reg_read     =  addr_intpend_base_match      & picm_rden_ff ;
   assign intpend_thr_reg_read =  addr_intpend_thr_base_match  & picm_rden_ff ;
   assign intpriority_reg_read =  raddr_intpriority_base_match & picm_rden_ff;
   assign intenable_reg_read   =  raddr_intenable_base_match   & picm_rden_ff;
   assign delg_reg_read        =  raddr_delg_base_match        & picm_rden_ff;
   assign gw_config_reg_read   =  raddr_config_gw_base_match   & picm_rden_ff;

   assign thr_mx_intpend_reg[pt.PIC_TOTAL_INT_PLUS1-1:0]   = picm_rd_thr_ff ? {(extintsrc_req_gw[pt.PIC_TOTAL_INT_PLUS1-1:0] &  delg_reg[pt.PIC_TOTAL_INT_PLUS1-1:0]) } :
                                                                              {(extintsrc_req_gw[pt.PIC_TOTAL_INT_PLUS1-1:0] & ~delg_reg[pt.PIC_TOTAL_INT_PLUS1-1:0]) } ;

   assign intpend_reg_extended[INTPEND_SIZE-1:0]       = {{INTPEND_SIZE-pt.PIC_TOTAL_INT_PLUS1{1'b0}},extintsrc_req_gw[pt.PIC_TOTAL_INT_PLUS1-1:0]} ;
   assign thr_mx_intpend_reg_extended[INTPEND_SIZE-1:0]= {{INTPEND_SIZE-pt.PIC_TOTAL_INT_PLUS1{1'b0}},thr_mx_intpend_reg[pt.PIC_TOTAL_INT_PLUS1-1:0]} ;

      for (i=0; i<(INT_GRPS); i++) begin
               assign intpend_rd_part_out[i]     =  (({32{intpend_reg_read     &  (picm_raddr_ff[5:2] == i)}}) & intpend_reg_extended[((32*i)+31):(32*i)]) ;
               assign intpend_thr_rd_part_out[i] =  (({32{intpend_thr_reg_read &  (picm_raddr_ff[5:2] == i)}}) & thr_mx_intpend_reg_extended[((32*i)+31):(32*i)]) ;

逐段解释：

* 第 L605-L610 行：read select 由对应 base match 和 ``picm_rden_ff`` 生成。
* 第 L612-L613 行：thread-filtered pending 由 ``picm_rd_thr_ff`` 选择 delegation bit 为 1
  或为 0 的 pending 集合。
* 第 L615-L616 行：pending 向量扩展到 ``INTPEND_SIZE``，高位补 0。
* 第 L618-L620 行：按 ``picm_raddr_ff[5:2]`` 选择 32-bit pending 分组输出。

接口关系：

* 被调用：read data mux 读取 ``intpend_rd_out`` 和 ``intpend_thr_rd_out``。
* 调用：读取 gateway pending、delegation、地址 index 和 read select。
* 共享状态：``picm_rd_thr_ff`` 决定 thread-filtered pending 读哪一类 delegation。

§8.2  Read 汇总与 ``picm_rd_data`` bypass
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把各分组 read 输出 OR 汇总，并在最终 read data mux 中选择 pending、priority、enable、
delegation、gateway config、config 或 mask 数据；同地址读写时直接返回写数据。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L623-L651``）：

.. code-block:: systemverilog

      always_comb begin : INTPEND_RD
            intpend_rd_out =  '0 ;
            intpend_thr_rd_out =  '0 ;
            for (int i=0; i<INT_GRPS; i++) begin
                  intpend_rd_out     |=  intpend_rd_part_out[i] ;
                  intpend_thr_rd_out |=  intpend_thr_rd_part_out[i] ;
            end
      end

      always_comb begin : INTEN_RD
            intenable_rd_out =  '0 ;
            delg_rd_out =  '0 ;
            intpriority_rd_out =  '0 ;
            gw_config_rd_out =  '0 ;
            for (int i=0; i<pt.PIC_TOTAL_INT_PLUS1; i++) begin
                 if (intenable_reg_re[i]) begin
                  intenable_rd_out    =  intenable_reg[i]  ;
                 end
                 if (delg_reg_re[i]) begin
                  delg_rd_out    =  delg_reg[i]  ;
                 end
                 if (intpriority_reg_re[i]) begin
                  intpriority_rd_out  =  intpriority_reg[i] ;
                 end
                 if (gw_config_reg_re[i]) begin
                  gw_config_rd_out  =  gw_config_reg[i] ;
                 end
            end

逐段解释：

* 第 L623-L630 行：``INTPEND_RD`` 把所有 32-bit pending 分组 OR 成一个 read output。
* 第 L632-L637 行：``INTEN_RD`` 初始化 enable、delegation、priority 和 gateway config read
  输出为 0。
* 第 L638-L649 行：循环查找哪个 per-interrupt read enable 有效，并取出对应寄存器值。

接口关系：

* 被调用：``picm_rd_data_in`` read mux 使用这些汇总输出。
* 调用：读取 per-interrupt read enable 和寄存器数组。
* 共享状态：多个 read enable 同时有效时，后续 loop 赋值会覆盖较早值；本文不推导非法地址场景。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L654-L673``）：

.. code-block:: systemverilog

    assign picm_rd_data_in[31:0] = ({32{intpend_reg_read      }} &   intpend_rd_out                                                    ) |
                                   ({32{intpend_thr_reg_read  }} &   intpend_thr_rd_out                                                ) |
                                   ({32{intpriority_reg_read  }} &  {{32-INTPRIORITY_BITS{1'b0}}, intpriority_rd_out                 } ) |
                                   ({32{intenable_reg_read    }} &  {31'b0 , intenable_rd_out                                        } ) |
                                   ({32{delg_reg_read         }} &  {31'b0 , delg_rd_out                                             } ) |
                                   ({32{gw_config_reg_read    }} &  {30'b0 , gw_config_rd_out                                        } ) |
                                   ({32{config_reg_re         }} &  {31'b0 , config_reg                                              } ) |
                                   ({32{picm_mken_ff & mask[3]}} &  {30'b0 , 2'b11                                                   } ) |
                                   ({32{picm_mken_ff & mask[2]}} &  {31'b0 , 1'b1                                                    } ) |
                                   ({32{picm_mken_ff & mask[1]}} &  {28'b0 , 4'b1111                                                 } ) |
                                   ({32{picm_mken_ff & mask[0]}} &   32'b0                                                             ) ;


   assign picm_rd_data[31:0] = picm_bypass_ff ? picm_wr_data_ff[31:0] : picm_rd_data_in[31:0] ;

   logic [14:0] address;

   assign address[14:0] = picm_raddr_ff[14:0];

   `include "pic_map_auto.h"

逐段解释：

* 第 L654-L664 行：最终 read data mux 通过 32-bit mask 组合 pending、thread pending、
  priority、enable、delegation、gateway config、PIC config 和 mask read data。
* 第 L667 行：如果 ``picm_bypass_ff`` 为真，``picm_rd_data`` 返回 ``picm_wr_data_ff``；
  否则返回 ``picm_rd_data_in``。
* 第 L669-L671 行：``address`` 取 ``picm_raddr_ff[14:0]``。
* 第 L673 行：源码包含 ``pic_map_auto.h``。当前工作区未找到该头文件，因此本文只记录
  include 边界，不解释该头文件内部生成的 ``mask`` 逻辑。

接口关系：

* 被调用：LSU/PIC memory 访问路径读取 ``picm_rd_data``。
* 调用：读取 read select、汇总 read data、``mask``、bypass 和写数据寄存器。
* 共享状态：``mask`` 的来源在 include 文件中，不在当前可读源文件中展开。

§9  Gateway helper 模块
------------------------

``eh2_configurable_gw`` 在同一源文件中定义。它把异步/外部中断输入同步到 raw clock，并根据
polarity、type 和 clear 生成配置后的 pending 请求。

§9.1  ``eh2_configurable_gw`` — polarity/type/clear 处理
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：同步单路外部中断，并在 level 或 latched 模式下生成 ``extintsrc_req_config``。

关键代码（``rtl/design/eh2_pic_ctrl.sv:L703-L728``）：

.. code-block:: systemverilog

   module eh2_configurable_gw (
                                input logic gw_clk,
                                input logic rawclk,
                                input logic clken,
                                input logic rst_l,
                                input logic extintsrc_req,
                                input logic meigwctrl_polarity ,
                                input logic meigwctrl_type ,
                                input logic meigwclr ,

                                output logic extintsrc_req_config
                               );

     logic  gw_int_pending_in, gw_int_pending, extintsrc_req_sync;

     rvsyncss_fpga  #(1) sync_inst (
         .dout        (extintsrc_req_sync),
         .din         (extintsrc_req),
         .*) ;
     assign gw_int_pending_in =  (extintsrc_req_sync ^ meigwctrl_polarity) | (gw_int_pending & ~meigwclr) ;
    rvdff_fpga #(1) int_pend_ff        (.*, .clk(gw_clk), .rawclk(rawclk), .clken(clken), .din (gw_int_pending_in),     .dout(gw_int_pending));


     assign extintsrc_req_config =  meigwctrl_type ? ((extintsrc_req_sync ^  meigwctrl_polarity) | gw_int_pending) : (extintsrc_req_sync ^  meigwctrl_polarity) ;

   endmodule // configurable_gw

逐段解释：

* 第 L703-L714 行：gateway 接收 gateway clock、raw clock、clock enable、reset、原始中断、
  polarity、type、clear，输出配置后的中断请求。
* 第 L716-L721 行：``rvsyncss_fpga`` 将 ``extintsrc_req`` 同步到 ``extintsrc_req_sync``。
* 第 L722-L723 行：pending 输入等于极性处理后的同步请求，或既有 pending 且未 clear；
  ``gw_int_pending`` 由 ``rvdff_fpga`` 保存。
* 第 L726 行：``meigwctrl_type`` 为真时输出极性处理后的当前请求 OR latched pending；
  否则只输出极性处理后的当前请求。

接口关系：

* 被调用：``eh2_pic_ctrl`` 每路 gateway 实例化该模块。
* 调用：实例化 ``rvsyncss_fpga`` 和 ``rvdff_fpga``。
* 共享状态：``gw_int_pending`` 保存 level/edge 处理中的 pending 状态。

§10  Sign-off 与 ADR 关联
-------------------------

本节只引用已存在的项目状态和 ADR 文档，不把 sign-off 数字扩展成新的 RTL 行为。
``eh2_pic_ctrl`` 在 block-level LEC 表中对应 ``1573`` passing、``0`` failing、
``0`` unverified、``PASS``。PIC 也在 formal strategy 中作为中断优先级树相关 property
目标出现。

关键代码（``docs/PROJECT_STATUS.md:L96-L104``）：

.. code-block:: text

   | `eh2_exu_alu_ctl` | 294 | 0 | 0 | PASS |
   | `eh2_exu_mul_ctl` | 272 | 0 | 0 | PASS |
   | `eh2_exu_div_ctl` | 181 | 0 | 0 | PASS |
   | `eh2_lsu` | 3565 | 0 | 0 | PASS |
   | `eh2_pic_ctrl` | 1573 | 0 | 0 | PASS |
   | `eh2_dma_ctrl` | 967 | 0 | 0 | PASS |
   | `eh2_dbg` | 571 | 0 | 0 | PASS |
   | `eh2_ifu` | 17052 | 0 | 0 | PASS |
   | TOTAL | 31635 | 0 | 0 | PASS |

逐段解释：

* 第 L96-L104 行：项目状态表记录 block-level LEC 结果；``eh2_pic_ctrl`` 对应
  ``1573`` passing、``0`` failing、``0`` unverified、``PASS``。
* 第 L104 行：总计为 ``31635`` passing、``0`` failing、``0`` unverified、``PASS``。

接口关系：

* 被调用：LEC 和 sign-off flow 文档引用该状态。
* 调用：本文只引用状态表，不从中推导 RTL 实现。
* 共享状态：与 :ref:`adr-0020` 的 block-level LEC closure 结果一致。

关键代码（``docs/adr/0012-formal-strategy.md:L24-L31``）：

.. code-block:: text

   ### Property File Allocation

   | File | Target Module | Domain | Properties | Cover Points |
   |------|--------------|--------|-----------|--------------|
   | `eh2_pmp_assert.sv` | `eh2_lsu_addrcheck` | PMP/MPU address check, mem map, side-effects | 7 assert + 1 cover | 1 |
   | `eh2_dec_assert.sv` | `eh2_dec` | Pipeline decode, CSR legality, MRET, hazards | 5 assert + 1 cover | 1 |
   | `eh2_dbg_assert.sv` | `eh2_dbg` | Debug FSM, halt/resume, abstract command | 5 assert + 1 cover | 1 |
   | `eh2_pic_assert.sv` | `eh2_pic_ctrl` | Interrupt priority tree, claim/complete, threshold | 5 assert + 1 cover | 1 |

逐段解释：

* 第 L24-L31 行：ADR-0012 的 property allocation 表把 ``eh2_pic_assert.sv`` 绑定到
  ``eh2_pic_ctrl``，domain 是 interrupt priority tree、claim/complete 和 threshold。
* 本章引用该表的目的只是说明 PIC 的 formal 关注点存在于已登记 ADR 中。

接口关系：

* 被调用：formal flow 和 formal property 文档引用 :ref:`adr-0012`。
* 调用：本文不解释 property 文件内部实现，避免跨文件推断。
* 共享状态：无 RTL 共享状态。

§11  参考资料
-------------

* 源文件：:file:`/home/host/eh2-veri/rtl/design/eh2_pic_ctrl.sv`
* 顶层实例：:file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* Arbiter helper：:file:`/home/host/eh2-veri/rtl/design/lib/beh_lib.sv`
* RTL filelist：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* 状态文档：:file:`/home/host/eh2-veri/docs/PROJECT_STATUS.md`
* 关联 ADR：:ref:`adr-0012`、:ref:`adr-0014`、:ref:`adr-0020`
* 关联章节：:ref:`pic`、:doc:`dma`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
