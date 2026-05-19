.. _pic:
.. _02_core_reference/pic:

可编程中断控制器（PIC）
================================================================================

:status: draft
:source: syn/include/eh2_param.vh; rtl/design/eh2_pic_ctrl.sv; rtl/design/eh2_veer.sv; rtl/design/lsu/eh2_lsu.sv; rtl/design/lsu/eh2_lsu_dccm_ctl.sv; rtl/design/lib/beh_lib.sv; dv/uvm/core_eh2/eh2_rtl.f; dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh; dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv; dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv; dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv; dv/uvm/core_eh2/tests/core_eh2_test_lib.sv; dv/uvm/core_eh2/directed_tests/directed_testlist.yaml; dv/uvm/core_eh2/tests/asm/directed_pic_state_walk.S; dv/uvm/core_eh2/tests/asm/directed_irq_basic.S; dv/uvm/core_eh2/tests/asm/directed_nested_irq.S; dv/formal/properties/eh2_pic_assert.sv; dv/formal/eh2_formal_bind.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh; dv/cosim/spike_cosim.cc; docs/adr/0007-interrupt-cosim.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界与当前结论
--------------------------------------------------------------------------------

本章只描述当前工作区源码中可回溯的 PIC 行为。需要先说明一个版本边界：
``rtl/design/eh2_pic_ctrl.sv`` 当前在工作区存在，但不在 ``feeac23a...`` 的
``HEAD`` tree 中；现有 filelist、formal filelist 和文档均引用该路径。因此，本章的
PIC RTL 行号以当前工作区文件为准，frontmatter 的 ``:commit:`` 仍记录会话基准 commit。

当前参数把 PIC 配置为单线程 core 周边的 127 路外部中断输入：
``NUM_THREADS=6'h01``、``PIC_2CYCLE=5'h01``、``PIC_BASE_ADDR=36'h0F00C0000``、
``PIC_TOTAL_INT=12'h07F``、``PIC_TOTAL_INT_PLUS1=13'h0080``。RTL 的
``extintsrc_req`` 输入宽度使用 ``PIC_TOTAL_INT_PLUS1``，其中 interrupt 0 在
``eh2_veer.sv`` 实例化时被常量 ``1'b0`` 补入，UVM 侧驱动的是
``extintsrc_req[127:1]``。

PIC 数据流如下：

.. code-block:: bash

   UVM irq_agent
      |
      v
   eh2_irq_intf.extintsrc_req[127:1]
      |
      v
   core_eh2_tb_top -> eh2_veer_wrapper -> eh2_veer
      |
      v
   eh2_pic_ctrl
      |-- gateway: sync / polarity / type / clear
      |-- registers: priority / enable / delegation / config
      |-- priority tree: eh2_cmp_and_mux
      |-- threshold: meipt and meicurpl
      v
   mexintpend_out / claimid_out / pl_out / mhwakeup_out
      |
      v
   DEC/TLU interrupt entry and wakeup path

**接口关系** ：

* **上游** ：UVM IRQ agent、LSU PIC memory access、DMA PIC write path、DEC/TLU
  ``meipt`` / ``meicurpl`` 输入。
* **下游** ：``mexintpend``、``pic_claimid``、``pic_pl`` 和 ``mhwakeup`` 进入
  ``eh2_veer`` 内部 DEC/TLU 逻辑。
* **共享状态** ：``intpriority_reg``、``intenable_reg``、``gw_config_reg``、
  ``delg_reg``、``config_reg``、``extintsrc_req_gw``、``selected_int_priority``、
  ``claimid_in``。

§2  参数事实
--------------------------------------------------------------------------------

**职责** ：参数文件给 PIC 的地址、输入数、plus-one 宽度和两级优先级树开关提供当前配置。
旧文档中“4/8/16 级可配”的说法不来自当前所引源码；当前 RTL 里 priority 宽度是
``INTPRIORITY_BITS=4``。

**关键代码** （``syn/include/eh2_param.vh:L166-L174``）：

.. code-block:: systemverilog

       NUM_THREADS            : 6'h01         ,
       PIC_2CYCLE             : 5'h01         ,
       PIC_BASE_ADDR          : 36'h0F00C0000  ,
       PIC_BITS               : 9'h00F        ,
       PIC_INT_WORDS          : 8'h04         ,
       PIC_REGION             : 8'h0F         ,
       PIC_SIZE               : 13'h0020       ,
       PIC_TOTAL_INT          : 12'h07F        ,
       PIC_TOTAL_INT_PLUS1    : 13'h0080       ,

**逐段解释** ：

* 第 L166 行：当前 release 参数为 ``NUM_THREADS=1``，因此 PIC RTL 的单线程分支是当前实例行为。
* 第 L167 行：``PIC_2CYCLE=1``，RTL 会启用中间寄存器的两段 priority tree 路径。
* 第 L168-L172 行：``PIC_BASE_ADDR`` 为 ``0x0F00C0000``，并给出 region、size 和 word
  分组相关参数。
* 第 L173-L174 行：``PIC_TOTAL_INT=127``，``PIC_TOTAL_INT_PLUS1=128``。PIC RTL 内部数组
  使用 plus-one 宽度，以便 index 0 固定为无效中断槽。

**接口关系** ：

* **被调用** ：``eh2_pic_ctrl.sv`` 通过 ``eh2_param.vh`` 的 ``pt`` 参数结构使用这些字段。
* **调用** ：无。
* **共享状态** ：``pt.NUM_THREADS``、``pt.PIC_2CYCLE``、``pt.PIC_BASE_ADDR``、
  ``pt.PIC_TOTAL_INT``、``pt.PIC_TOTAL_INT_PLUS1``。

§3  filelist 中的 RTL 入口
--------------------------------------------------------------------------------

**职责** ：UVM RTL filelist 把 ``eh2_pic_ctrl.sv`` 纳入 top-level RTL 编译单元。该事实说明
PIC RTL 是 testbench 编译路径的一部分。

**关键代码** （``dv/uvm/core_eh2/eh2_rtl.f:L70-L75``）：

.. code-block:: bash

   // Top-level
   rtl/design/eh2_dma_ctrl.sv
   rtl/design/eh2_mem.sv
   rtl/design/eh2_pic_ctrl.sv
   rtl/design/eh2_veer.sv
   rtl/design/eh2_veer_wrapper.sv

**逐段解释** ：

* 第 L70 行：注释把后续条目标为 top-level 相关 RTL。
* 第 L71-L73 行：DMA、memory 和 PIC 控制器一起进入 filelist。
* 第 L74-L75 行：core top 和 wrapper 随后编译；``eh2_veer.sv`` 中实例化 PIC。

**接口关系** ：

* **被调用** ：RTL compile flow 读取该 filelist。
* **调用** ：无。
* **共享状态** ：编译单元包含 ``rtl/design/eh2_pic_ctrl.sv``。

§4  ``eh2_pic_ctrl`` 端口边界
--------------------------------------------------------------------------------

**职责** ：PIC module 的端口清楚划分了 4 类接口：clock/reset、外部中断源、PIC memory
register 访问、DEC/TLU priority threshold 输入和输出到 core 的 pending/claim/wakeup。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L23-L58``）：

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

**逐段解释** ：

* 第 L23-L27 行：module 导入 ``eh2_pkg`` 并 include 参数文件，所有宽度均通过 ``pt`` 参数化。
* 第 L30-L35 行：输入包含 core clock、free clock、reset 和两个 clock override。
* 第 L36-L38 行：``o_cpu_halt_status`` 用于多线程 arbitration；``extintsrc_req`` 是
  ``PIC_TOTAL_INT_PLUS1`` 宽的中断请求向量。
* 第 L39-L43 行：``picm_rdaddr``、``picm_wraddr``、``picm_wr_data``、``picm_wren`` 和
  ``picm_rden`` 组成 memory-mapped register 访问入口。

**接口关系** ：

* **被调用** ：``eh2_veer.sv`` 中 ``pic_ctrl_inst`` 实例化该 module。
* **调用** ：module 内部实例化 clock gate、gateway、comparator 和 flops。
* **共享状态** ：``extintsrc_req``、``picm_*``、``dec_tlu_meipt``、``dec_tlu_meicurpl``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L43-L56``）：

.. code-block:: systemverilog

                        input  logic                   picm_rden,            // Read enable for the register
                        input  logic                   picm_rd_thr,          // Reading thread
                        input  logic                   picm_mken,            // Read the Mask for the register

                        input  logic [pt.NUM_THREADS-1:0] [3:0]             dec_tlu_meicurpl,           // Current Priority Level
                        input  logic [pt.NUM_THREADS-1:0] [3:0]             dec_tlu_meipt,              // Current Priority Threshold

                        output logic [pt.NUM_THREADS-1:0]                   mexintpend_out,           // External Inerrupt request to the core
                        output logic [pt.NUM_THREADS-1:0] [7:0]             claimid_out,              // Claim Id of the requested interrupt
                        output logic [pt.NUM_THREADS-1:0] [3:0]             pl_out,                   // Priority level of the requested interrupt
                        output logic [pt.NUM_THREADS-1:0]                   mhwakeup_out,             // Wake-up interrupt request

                        output logic [31:0]            picm_rd_data,         // Read data of the register
                        input  logic                   scan_mode             // scan mode

**逐段解释** ：

* 第 L43-L45 行：``picm_rden`` 表示 read enable，``picm_rd_thr`` 表示读取线程，``picm_mken``
  用于读取 store mask。
* 第 L47-L48 行：DEC/TLU 提供当前 priority level ``meicurpl`` 和 priority threshold
  ``meipt``，二者都是每线程 4 bit。
* 第 L50-L53 行：PIC 输出 external interrupt pending、claim ID、priority level 和 high-priority
  wakeup 请求。
* 第 L55-L56 行：``picm_rd_data`` 返回 register read data，``scan_mode`` 进入各类 flop/gate。

**接口关系** ：

* **被调用** ：DEC/TLU 和 LSU 通过 ``eh2_veer`` 内部 wires 与这些端口相连。
* **调用** ：无直接函数调用。
* **共享状态** ：``mexintpend_out``、``claimid_out``、``pl_out``、``mhwakeup_out``、
  ``picm_rd_data``。

§5  PIC 地址常量与寄存器区域
--------------------------------------------------------------------------------

**职责** ：RTL 通过 base address 派生 priority、pending、threshold-pending、enable、
PIC config、gateway config、gateway clear 和 delegation 区域。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L60-L80``）：

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

**逐段解释** ：

* 第 L60 行：``NUM_LEVELS`` 等于 ``$clog2(PIC_TOTAL_INT_PLUS1)``，后续 priority tree 使用它分层。
* 第 L61-L68 行：各寄存器区域从 ``PIC_BASE_ADDR`` 加固定 offset 得到。priority base 就是
  base address，pending、enable、gateway 和 delegation 各有独立 offset。
* 第 L71-L75 行：``INTPEND_SIZE`` 按 interrupt 数向上取到 32/64/128/256/512/1024。
  当前 ``PIC_TOTAL_INT_PLUS1=128`` 时该表达式落在 ``< 256`` 分支，得到 256。
* 第 L77-L80 行：pending read 分组宽度是 32 bit，priority 宽度固定为 4 bit，claim ID
  宽度固定为 8 bit，gateway config 默认数组为 0。

**接口关系** ：

* **被调用** ：地址 decode、priority tree 和 readback mux 使用这些 localparam。
* **调用** ：SystemVerilog ``$clog2``。
* **共享状态** ：``NUM_LEVELS``、``INTPRIORITY_BASE_ADDR``、``INTPEND_BASE_ADDR``、
  ``INTENABLE_BASE_ADDR``、``INTPRIORITY_BITS``、``ID_BITS``。

§6  内部寄存器与中断选择状态
--------------------------------------------------------------------------------

**职责** ：PIC 内部保存 priority、enable、delegation、gateway config、pending readback 和
priority tree 的中间状态。这些信号决定最终 ``claimid``、``pl``、``mexintpend`` 和
``mhwakeup``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L126-L153``）：

.. code-block:: systemverilog

   logic [INTPRIORITY_BITS-1:0] meipt_inv , meicurpl_inv , meicurpl, meipt;

   logic [pt.PIC_TOTAL_INT_PLUS1-1:0] [INTPRIORITY_BITS-1:0] intpriority_reg;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0] [INTPRIORITY_BITS-1:0] intpriority_reg_inv;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        intpriority_reg_we;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        intpriority_reg_re;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        delg_thr_match;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0] [1:0]                  gw_config_reg;

   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        intenable_reg;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        intenable_reg_we;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        intenable_reg_re;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        delg_reg;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        delg_reg_we;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        delg_reg_re;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        gw_config_reg_we;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        gw_config_reg_re;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0]                        gw_clear_reg_we;

   logic [INTPEND_SIZE-1:0]                     intpend_reg_extended;
   logic [INTPEND_SIZE-1:0]                     thr_mx_intpend_reg_extended;

   logic [pt.PIC_TOTAL_INT_PLUS1-1:0] [INTPRIORITY_BITS-1:0] intpend_w_prior_en;
   logic [pt.PIC_TOTAL_INT_PLUS1-1:0] [ID_BITS-1:0]          intpend_id;
   logic [INTPRIORITY_BITS-1:0]                 maxint;

**逐段解释** ：

* 第 L126 行：``meipt``、``meicurpl`` 及其 inverted 版本用于 threshold 比较。
* 第 L128-L133 行：每个 interrupt slot 有 4-bit priority、write/read enable 和 gateway config。
* 第 L135-L143 行：enable、delegation、gateway config、gateway clear 都按
  ``PIC_TOTAL_INT_PLUS1`` 维度建模。
* 第 L145-L146 行：pending readback 被扩展到 ``INTPEND_SIZE``，便于按 32-bit group 读出。
* 第 L148-L150 行：``intpend_w_prior_en`` 是“pending、enable、delegation 匹配后带 priority”
  的候选向量；``intpend_id`` 保存各 slot ID；``maxint`` 用于 wakeup 判定。

**接口关系** ：

* **被调用** ：后续 SETREG、priority tree、pending readback 和 threshold 逻辑读写这些信号。
* **调用** ：无。
* **共享状态** ：``intpriority_reg``、``intenable_reg``、``delg_reg``、
  ``gw_config_reg``、``intpend_w_prior_en``、``intpend_id``。

§7  clock gating 与 address decode
--------------------------------------------------------------------------------

**职责** ：PIC 根据当前 memory access 类型开启对应局部 clock，并对读写地址做区域匹配。
``picm_bypass_ff`` 处理同地址读写同拍的 read data bypass。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L211-L239``）：

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

**逐段解释** ：

* 第 L211-L218 行：read address、write data、priority register、enable register 和 gateway config
  各有独立 clock enable，``clk_override`` 可强制打开。
* 第 L220-L224 行：对应实例化 5 个 ``rvoclkhdr``，生成 ``pic_*_c1_clk`` 和
  ``gw_config_c1_clk``。
* 这些 clock enable 不改变功能语义，但决定寄存器更新和读地址锁存何时有 clock。

**接口关系** ：

* **被调用** ：register flop 实例使用这些 gated clock。
* **调用** ：实例化 ``rvoclkhdr``。
* **共享状态** ：``picm_mken``、``picm_rden``、``picm_wren``、address match 信号和
  ``clk_override``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L228-L254``）：

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

**逐段解释** ：

* 第 L228-L232 行：read path 匹配 enable、priority、gateway config、PIC config 和 pending base。
* 第 L235-L239 行：write path 匹配 PIC config、gateway clear、priority、enable 和 gateway config。
* 第 L233 行：pending read 使用 ``[31:6]`` 匹配，这意味着低地址位用于 pending group 选择。
* 第 L254 行不在片段中展示；它定义 ``picm_bypass_ff`` 用于同地址读写 bypass，读数据 mux 在
  §18 解释。

**接口关系** ：

* **被调用** ：SETREG、readback mux、clock enable 和 bypass 逻辑使用 match 信号。
* **调用** ：无。
* **共享状态** ：``picm_raddr_ff``、``picm_waddr_ff``、各 base address localparam。

§8  LSU 到 PIC memory port
--------------------------------------------------------------------------------

**职责** ：LSU 把访问 PIC 地址区域的 load/store 转成 ``picm_*`` 端口。store 数据既可来自
LSU store data，也可来自 DMA PIC write path。

**关键代码** （``rtl/design/lsu/eh2_lsu.sv:L118-L126``）：

.. code-block:: systemverilog

      // PIC ports
      output logic                            picm_wren,        // PIC memory write enable
      output logic                            picm_rden,        // PIC memory read enable
      output logic                            picm_mken,        // Need to read the mask for stores to determine which bits to write/forward
      output logic                            picm_rd_thr,      // PICM read thread
      output logic [31:0]                     picm_rdaddr,      // PIC memory address
      output logic [31:0]                     picm_wraddr,      // PIC memory address
      output logic [31:0]                     picm_wr_data,     // PIC memory write data
      input logic [31:0]                      picm_rd_data,     // PIC memory read/mask data

**逐段解释** ：

* 第 L118-L126 行：LSU module 对外暴露 PIC memory write/read enable、mask enable、读线程、
  read/write address、write data 和 read data。
* ``picm_rd_data`` 是 input，说明 PIC readback 数据返回 LSU。

**接口关系** ：

* **被调用** ：``eh2_veer.sv`` 通过 ``.*`` 将 LSU 和 PIC controller 的 ``picm_*`` wires 连接。
* **调用** ：无。
* **共享状态** ：``picm_wren``、``picm_rden``、``picm_mken``、``picm_rdaddr``、
  ``picm_wraddr``、``picm_wr_data``、``picm_rd_data``。

**关键代码** （``rtl/design/lsu/eh2_lsu_dccm_ctl.sv:L375-L383``）：

.. code-block:: systemverilog

      // PIC signals. PIC ignores the lower 2 bits of address since PIC memory registers are 32-bits
      assign picm_wren_notdma   = (lsu_pkt_dc5.valid & lsu_pkt_dc5.store & addr_in_pic_dc5 & lsu_commit_dc5);
      assign picm_wren          = (lsu_pkt_dc5.valid & lsu_pkt_dc5.store & addr_in_pic_dc5 & lsu_commit_dc5) | dma_pic_wen;
      assign picm_rden          = lsu_pkt_dc1.valid & lsu_pkt_dc1.load  & addr_in_pic_dc1;
      assign picm_mken          = lsu_pkt_dc1.valid & lsu_pkt_dc1.store & addr_in_pic_dc1;  // Get the mask for stores
      assign picm_rd_thr        = lsu_pkt_dc1.tid;
      assign picm_rdaddr[31:0]  = lsu_addr_dc1[31:0];
      assign picm_wraddr[31:0]  = dma_pic_wen ? dma_mem_addr[31:0] : lsu_addr_dc5[31:0];
      assign picm_wr_data[31:0] = dma_pic_wen ? dma_mem_wdata[31:0] : store_data_lo_dc5[31:0];

**逐段解释** ：

* 第 L375 行：注释说明 PIC register 是 32-bit，因此 PIC 忽略地址低 2 bit。
* 第 L376-L377 行：store 且地址在 PIC 区域且 DC5 commit 时产生 write enable；DMA PIC write
  也会置位 ``picm_wren``。
* 第 L378-L380 行：load 且地址在 PIC 区域时产生 read enable；store 在 DC1 且地址在 PIC
  区域时产生 mask enable；读线程来自 ``lsu_pkt_dc1.tid``。
* 第 L381-L383 行：read address 来自 DC1 地址；write address/data 在 DMA 和 LSU store 路径间选择。

**接口关系** ：

* **被调用** ：PIC controller 接收 ``picm_*`` 端口。
* **调用** ：无。
* **共享状态** ：``lsu_pkt_dc*``、``addr_in_pic_dc*``、``dma_pic_wen``、``dma_mem_*``、
  ``store_data_lo_dc5``。

§9  ``eh2_veer`` 中的 PIC 实例化
--------------------------------------------------------------------------------

**职责** ：``eh2_veer`` 实例化 ``eh2_pic_ctrl``，把外部 interrupt 向量补上 index 0 的
``1'b0``，并把 PIC 输出接到 core 内部 pending、claim、priority 和 wakeup wires。

**关键代码** （``rtl/design/eh2_veer.sv:L1106-L1117``）：

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

**逐段解释** ：

* 第 L1106 行：实例名为 ``pic_ctrl_inst``，参数 ``pt`` 传给 ``eh2_pic_ctrl``。
* 第 L1107-L1110 行：PIC 使用 ``free_l2clk``、clock override、PIC IO clock override 和
  ``picm_mken``。
* 第 L1111 行：``extintsrc_req[pt.PIC_TOTAL_INT:1]`` 与 ``1'b0`` 拼接，形成
  ``PIC_TOTAL_INT_PLUS1`` 宽输入。index 0 被固定为 0。
* 第 L1112-L1115 行：PIC 输出连接到 ``pic_pl``、``pic_claimid``、``mexintpend`` 和
  ``mhwakeup``。
* 第 L1116-L1117 行：reset 为 ``core_rst_l``，其余同名端口通过 ``.*`` 连接。

**接口关系** ：

* **被调用** ：``eh2_veer`` elaboration 时实例化。
* **调用** ：实例化 ``eh2_pic_ctrl``。
* **共享状态** ：``extintsrc_req``、``pic_pl``、``pic_claimid``、``mexintpend``、
  ``mhwakeup``、``picm_*``。

§10  UVM top 的 interrupt wiring
--------------------------------------------------------------------------------

**职责** ：TB top 声明 interrupt wires，连接 DUT wrapper interrupt ports，并用
``eh2_irq_intf`` 驱动 timer、software、external 和 NMI interrupt。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:L47-L50``）：

.. code-block:: systemverilog

     // Interrupts
     logic [`RV_NUM_THREADS-1:0] timer_int;
     logic [`RV_NUM_THREADS-1:0] soft_int;
     logic [`RV_PIC_TOTAL_INT:1] extintsrc_req;

**逐段解释** ：

* 第 L47-L50 行：TB signal include 文件声明 timer、software 和 external interrupt wires。
* ``extintsrc_req`` 的范围是 ``[`RV_PIC_TOTAL_INT:1]``，没有 index 0；这与
  ``eh2_veer.sv`` 中补 ``1'b0`` 的实例化方式一致。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top.sv`` include 该信号声明。
* **调用** ：无。
* **共享状态** ：``timer_int``、``soft_int``、``extintsrc_req``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L356-L360``）：

.. code-block:: systemverilog

       // Interrupts
       .timer_int         (timer_int),
       .soft_int          (soft_int),
       .extintsrc_req     (extintsrc_req),

**逐段解释** ：

* 第 L356-L360 行：DUT wrapper interrupt ports 与 TB wires 相连。外部 PIC 请求通过
  ``extintsrc_req`` 进入 DUT。

**接口关系** ：

* **被调用** ：DUT wrapper 实例化时连接。
* **调用** ：无。
* **共享状态** ：``timer_int``、``soft_int``、``extintsrc_req``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L892-L904``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // IRQ Interface Instance (for interrupt stimulus)
     //--------------------------------------------------------------------------
     eh2_irq_intf #(
       .NUM_THREADS  (`RV_NUM_THREADS),
       .PIC_TOTAL_INT(`RV_PIC_TOTAL_INT)
     ) irq_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect IRQ interface to DUT interrupt signals
     assign timer_int     = irq_intf.timer_int;
     assign soft_int      = irq_intf.soft_int;
     assign extintsrc_req = irq_intf.extintsrc_req;
     assign nmi_int       = irq_intf.nmi_int;

**逐段解释** ：

* 第 L892-L898 行：TB top 实例化 ``eh2_irq_intf``，参数来自 ``RV_NUM_THREADS`` 和
  ``RV_PIC_TOTAL_INT``。
* 第 L900-L904 行：interface 的 timer、software、external 和 NMI signals 直接赋给 DUT wires。
* PIC 只消费 external interrupt vector；timer、software 和 NMI 走其他 core interrupt path。

**接口关系** ：

* **被调用** ：UVM IRQ driver 通过 virtual interface 驱动这些 signals。
* **调用** ：实例化 ``eh2_irq_intf``。
* **共享状态** ：``irq_intf.extintsrc_req``、``extintsrc_req``、``timer_int``、
  ``soft_int``、``nmi_int``。

§11  IRQ interface 与 transaction 类型
--------------------------------------------------------------------------------

**职责** ：``eh2_irq_intf`` 定义 UVM 驱动端可写的 interrupt signals；``eh2_irq_seq_item``
定义 transaction 类型、external interrupt ID、值和持续周期。

**关键代码** （``dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv:L7-L27``）：

.. code-block:: systemverilog

   interface eh2_irq_intf #(
     parameter NUM_THREADS = 1,
     parameter PIC_TOTAL_INT = 127
   )(
     input logic clk,
     input logic rst_n
   );

     // Interrupt signals
     logic [NUM_THREADS-1:0]   timer_int;
     logic [NUM_THREADS-1:0]   soft_int;
     logic [PIC_TOTAL_INT:1]   extintsrc_req;
     logic                     nmi_int;

     // Default values
     initial begin
       timer_int     = '0;
       soft_int      = '0;
       extintsrc_req = '0;
       nmi_int       = 1'b0;
     end

**逐段解释** ：

* 第 L7-L13 行：interface 参数默认 ``NUM_THREADS=1``、``PIC_TOTAL_INT=127``，并接收 clock/reset。
* 第 L15-L19 行：声明 timer、software、external 和 NMI interrupt signals，其中 external
  range 是 ``[PIC_TOTAL_INT:1]``。
* 第 L21-L27 行：initial block 将所有 interrupt signals 置为 0。

**接口关系** ：

* **被调用** ：TB top 实例化，IRQ driver 通过 ``uvm_config_db`` 获取 virtual interface。
* **调用** ：无。
* **共享状态** ：``timer_int``、``soft_int``、``extintsrc_req``、``nmi_int``。

**关键代码** （``dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv:L9-L21``）：

.. code-block:: systemverilog

     // Interrupt type
     typedef enum bit [2:0] {
       IRQ_TIMER    = 3'b000,
       IRQ_SOFTWARE = 3'b001,
       IRQ_EXTERNAL = 3'b010,
       IRQ_NMI      = 3'b011
     } irq_type_e;

     // Interrupt fields
     rand irq_type_e irq_type;
     rand bit [6:0]  irq_id;       // External interrupt ID (0-126)
     rand bit        irq_val;      // Interrupt value (1=set, 0=clear)
     rand bit [7:0]  duration;     // Duration in clock cycles (0=one-shot)

**逐段解释** ：

* 第 L9-L15 行：transaction 类型分为 timer、software、external 和 NMI。
* 第 L17-L21 行：external interrupt ID 是 7-bit，注释写明范围 ``0-126``；``irq_val`` 表示 set/clear，
  ``duration`` 表示持续 clock 数，0 表示 one-shot。
* 注意 interface 的 external vector 是 ``[PIC_TOTAL_INT:1]``。driver 使用 ``irq_id`` 作为索引，
  因此有效 external ID 应由 sequence 选择与接口范围共同约束。

**接口关系** ：

* **被调用** ：IRQ sequence 和 driver 创建、随机化和消费该 item。
* **调用** ：无。
* **共享状态** ：``irq_type``、``irq_id``、``irq_val``、``duration``。

§12  IRQ driver 对外部中断的驱动
--------------------------------------------------------------------------------

**职责** ：IRQ driver 根据 transaction 类型驱动 interface signals。外部 interrupt 类型直接写
``vif.extintsrc_req[txn.irq_id]``，并根据 ``duration`` 安排自动清零。

**关键代码** （``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L42-L60``）：

.. code-block:: systemverilog

     task drive_interrupt(eh2_irq_seq_item txn);
       case (txn.irq_type)
         eh2_irq_seq_item::IRQ_TIMER: begin
           vif.timer_int <= txn.irq_val;
           if (txn.duration > 0) begin
             // Non-blocking: schedule de-assert in background
             fork
               begin
                 bg_process = process::self();
                 repeat (txn.duration) @(posedge vif.clk);
                 vif.timer_int <= 1'b0;
               end
             join_none
           end else begin
             // Pulse: de-assert on next clock edge
             @(posedge vif.clk);
             vif.timer_int <= 1'b0;
           end

**逐段解释** ：

* 第 L42-L44 行：``drive_interrupt`` 按 ``txn.irq_type`` 分发。
* 第 L45-L54 行：timer interrupt 先写 ``txn.irq_val``；若 ``duration > 0``，后台 fork 等待对应
  clock 数后清零。
* 第 L55-L59 行：``duration == 0`` 时等待一个 clock 后清零，形成 one-shot pulse。
* timer interrupt 不经过 PIC，但它与 external interrupt 使用同一个 IRQ driver。

**接口关系** ：

* **被调用** ：``run_phase`` 从 sequencer 取 item 后调用。
* **调用** ：SystemVerilog fork/join_none 和 clock wait。
* **共享状态** ：``vif.timer_int``、``txn.duration``、``bg_process``。

**关键代码** （``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L78-L92``）：

.. code-block:: systemverilog

         eh2_irq_seq_item::IRQ_EXTERNAL: begin
           vif.extintsrc_req[txn.irq_id] <= txn.irq_val;
           if (txn.duration > 0) begin
             fork
               begin
                 bg_process = process::self();
                 repeat (txn.duration) @(posedge vif.clk);
                 vif.extintsrc_req[txn.irq_id] <= 1'b0;
               end
             join_none
           end else begin
             @(posedge vif.clk);
             vif.extintsrc_req[txn.irq_id] <= 1'b0;
           end
         end

**逐段解释** ：

* 第 L78-L79 行：external interrupt 分支把 ``txn.irq_val`` 写到
  ``vif.extintsrc_req[txn.irq_id]``。这就是 UVM 侧进入 PIC 的主要刺激路径。
* 第 L80-L87 行：持续型 external interrupt 用后台进程在 ``duration`` 个 clock 后清零。
* 第 L88-L91 行：one-shot external interrupt 等一个 clock 后清零。

**接口关系** ：

* **被调用** ：IRQ driver ``drive_interrupt()``。
* **调用** ：fork/join_none 和 clock wait。
* **共享状态** ：``vif.extintsrc_req``、``txn.irq_id``、``txn.irq_val``、``txn.duration``。

**关键代码** （``dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv:L112-L124``）：

.. code-block:: systemverilog

     // Reset handling: kill background threads and clear all IRQ signals
     task pre_reset_phase(uvm_phase phase);
       if (bg_process != null) begin
         bg_process.kill();
         bg_process = null;
       end
       if (vif != null) begin
         vif.timer_int     <= '0;
         vif.soft_int      <= '0;
         vif.extintsrc_req <= '0;
         vif.nmi_int       <= 1'b0;
       end
     endtask

**逐段解释** ：

* 第 L112-L117 行：reset 前如果有后台清零进程，driver 会 kill 并清空 process handle。
* 第 L118-L123 行：virtual interface 存在时，timer、software、external 和 NMI 都清零。
* 该 reset 处理避免 reset 后残留 external interrupt request。

**接口关系** ：

* **被调用** ：UVM reset phase 调用。
* **调用** ：``process::kill``。
* **共享状态** ：``bg_process``、``vif.*`` interrupt signals。

§13  gateway 配置与同步
--------------------------------------------------------------------------------

**职责** ：每个非零 interrupt slot 经过 ``eh2_configurable_gw``，支持 polarity、type 和 clear。
gateway 输出 ``extintsrc_req_gw`` 进入 enable/priority 选择逻辑。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L327-L351``）：

.. code-block:: systemverilog

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

**逐段解释** ：

* 第 L327-L330 行：gateway 按 4 个 interrupt 一组生成 group clock enable，``io_clk_override`` 可强制打开。
* 第 L332-L336 行：非 FPGA optimize 路径实例化 ``rvclkhdr``；FPGA optimize 路径把
  ``gw_clk[p]`` 置 0。本文不扩展宏配置之外的行为。
* 第 L339-L345 行：内部 ``GW`` loop 从 group 0 的 index 1 开始，跳过 interrupt 0；
  gateway 输入连接 ``extintsrc_req[i+p*4]``。

**接口关系** ：

* **被调用** ：``eh2_pic_ctrl`` elaboration 时生成每路 gateway。
* **调用** ：实例化 ``rvclkhdr`` 和 ``eh2_configurable_gw``。
* **共享状态** ：``intenable_clk_enable``、``io_clk_override``、``extintsrc_req``、
  ``gw_config_reg``、``gw_clear_reg_we``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L345-L350``）：

.. code-block:: systemverilog

               .extintsrc_req(extintsrc_req[i+p*4]) ,
               .meigwctrl_polarity(gw_config_reg[i+p*4][0]) ,
               .meigwctrl_type(gw_config_reg[i+p*4][1]) ,
               .meigwclr(gw_clear_reg_we[i+p*4]) ,
               .extintsrc_req_config(extintsrc_req_gw[i+p*4])
           );

**逐段解释** ：

* 第 L345-L349 行：gateway 消费 raw external request、polarity bit、type bit 和 clear bit，
  输出 configured request ``extintsrc_req_gw``。
* 第 L350 行：结束 gateway 实例化。

**接口关系** ：

* **被调用** ：gateway loop。
* **调用** ：``eh2_configurable_gw`` module。
* **共享状态** ：``gw_config_reg``、``gw_clear_reg_we``、``extintsrc_req_gw``。

§14  ``eh2_configurable_gw`` 的 pending 逻辑
--------------------------------------------------------------------------------

**职责** ：gateway module 对 raw interrupt request 做同步、polarity 处理、level/latched
type 选择，并支持 clear。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L703-L727``）：

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

**逐段解释** ：

* 第 L703-L714 行：module 端口包括 gateway clock、raw clock、clock enable、reset、raw request、
  polarity、type、clear 和 configured request 输出。
* 第 L716-L721 行：``rvsyncss_fpga`` 把 ``extintsrc_req`` 同步到 ``extintsrc_req_sync``。
* 第 L722 行：pending 输入是 polarity 后的同步 request，或此前 pending 且没有 clear。
* 第 L723 行：``rvdff_fpga`` 保存 ``gw_int_pending``。

**接口关系** ：

* **被调用** ：``eh2_pic_ctrl`` 对每路外部中断实例化。
* **调用** ：``rvsyncss_fpga`` 和 ``rvdff_fpga``。
* **共享状态** ：``extintsrc_req_sync``、``gw_int_pending``、``meigwclr``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L722-L727``）：

.. code-block:: systemverilog

     assign gw_int_pending_in =  (extintsrc_req_sync ^ meigwctrl_polarity) | (gw_int_pending & ~meigwclr) ;
    rvdff_fpga #(1) int_pend_ff        (.*, .clk(gw_clk), .rawclk(rawclk), .clken(clken), .din (gw_int_pending_in),     .dout(gw_int_pending));


     assign extintsrc_req_config =  meigwctrl_type ? ((extintsrc_req_sync ^  meigwctrl_polarity) | gw_int_pending) : (extintsrc_req_sync ^  meigwctrl_polarity) ;

**逐段解释** ：

* 第 L722-L723 行：pending flop 会保持已经观察到的 request，直到 ``meigwclr`` 清除。
* 第 L726 行：``meigwctrl_type`` 为 1 时输出包含 latched pending；为 0 时输出仅为同步且 polarity
  处理后的当前 request。

**接口关系** ：

* **被调用** ：gateway 输出进入 ``extintsrc_req_gw``。
* **调用** ：flop module。
* **共享状态** ：``meigwctrl_type``、``meigwctrl_polarity``、``meigwclr``。

§15  SETREG：priority、enable、delegation、gateway config
--------------------------------------------------------------------------------

**职责** ：``SETREG`` generate loop 为每个非零 interrupt slot 产生 priority、enable、
delegation 和 gateway config 寄存器。interrupt 0 被固定为全 0。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L354-L383``）：

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

**逐段解释** ：

* 第 L354-L356 行：loop 遍历 ``0`` 到 ``PIC_TOTAL_INT_PLUS1-1``；只有 ``i > 0`` 进入可配置分支。
* 第 L357-L361 行：priority 和 enable 的 read/write enable 由区域匹配、地址 index 和
  ``picm_*en_ff`` 共同决定。
* 第 L363-L366 行：多线程配置下 delegation 寄存器可读写，并用 ``picm_wr_data_ff[0]`` 更新。
* 第 L367 行之后是单线程分支；当前 ``NUM_THREADS=1`` 时 delegation 相关信号固定为 0。

**接口关系** ：

* **被调用** ：address decode 和 register write path 驱动。
* **调用** ：实例化 ``rvdffs``。
* **共享状态** ：``intpriority_reg_we``、``intenable_reg_we``、``delg_reg_we``、
  ``picm_waddr_ff``、``picm_wr_data_ff``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L367-L383``）：

.. code-block:: systemverilog

        end else begin: one_t
             assign delg_reg_re[i] = 1'b0 ;
             assign delg_reg_we[i] = 1'b0 ;
             assign delg_reg[i]    = 1'b0;
        end


        assign gw_config_reg_we[i]   =  waddr_config_gw_base_match   & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff;
        assign gw_config_reg_re[i]   =  raddr_config_gw_base_match   & (picm_raddr_ff[NUM_LEVELS+1:2] == i) & picm_rden_ff;

        assign gw_clear_reg_we[i]    =  addr_clear_gw_base_match     & (picm_waddr_ff[NUM_LEVELS+1:2] == i) & picm_wren_ff ;

        rvdffs #(INTPRIORITY_BITS) intpriority_ff  (.*, .en( intpriority_reg_we[i]), .din (picm_wr_data_ff[INTPRIORITY_BITS-1:0]), .dout(intpriority_reg[i]), .clk(pic_pri_c1_clk));
        rvdffs #(1)                 intenable_ff   (.*, .en( intenable_reg_we[i]),   .din (picm_wr_data_ff[0]),                    .dout(intenable_reg[i]),   .clk(pic_int_c1_clk));
        rvdffs #(2)                 gw_config_ff   (.*, .en( gw_config_reg_we[i]),   .din (picm_wr_data_ff[1:0]),                  .dout(gw_config_reg[i]),   .clk(gw_config_c1_clk));

**逐段解释** ：

* 第 L367-L371 行：单线程配置下 delegation read/write enable 和 register 均固定为 0。
* 第 L374-L377 行：gateway config 和 gateway clear write enable 用相同的地址 index 匹配方式。
* 第 L379-L381 行：priority register 保存写数据低 4 bit，enable 保存 bit 0，gateway config 保存低 2 bit。
* 第 L383 行在下一片段中参与 clock enable 计算。

**接口关系** ：

* **被调用** ：memory-mapped store 到 PIC register 时更新。
* **调用** ：``rvdffs`` flops。
* **共享状态** ：``gw_config_reg``、``intpriority_reg``、``intenable_reg``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L386-L412``）：

.. code-block:: systemverilog

    end else begin : INT_ZERO
        assign intpriority_reg_we[i] =  1'b0 ;
        assign intpriority_reg_re[i] =  1'b0 ;
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

**逐段解释** ：

* 第 L386-L395 行：interrupt 0 的所有 register read/write enable 都固定为 0。
* 第 L397-L404 行：interrupt 0 的 gateway config、priority、enable、delegation、gateway request
  和 sync request 均固定为 0。
* 这解释了为什么 UVM interface 从 ``[127:1]`` 开始驱动，``eh2_veer`` 实例化时补入 index 0 的 0。

**接口关系** ：

* **被调用** ：SETREG loop 的 ``i == 0`` 分支。
* **调用** ：无。
* **共享状态** ：interrupt 0 的所有 PIC 状态。

§16  候选 pending 与 priority 输入
--------------------------------------------------------------------------------

**职责** ：每路 interrupt 的候选 priority 由 gateway request、enable bit、delegation/thread
匹配共同 gate；未命中时 priority 为 0。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L408-L412``）：

.. code-block:: systemverilog

       assign intpriority_reg_inv[i] =  intpriord ? ~intpriority_reg[i] : intpriority_reg[i] ;
       assign delg_thr_match[i]      =  (delg_reg[i] &  curr_int_tid) |   (~delg_reg[i] & ~curr_int_tid) ;

       assign intpend_w_prior_en[i]  =  {INTPRIORITY_BITS{(extintsrc_req_gw[i] & intenable_reg[i] & delg_thr_match[i])}} & intpriority_reg_inv[i] ;
       assign intpend_id[i]          =  i ;

**逐段解释** ：

* 第 L408 行：``config_reg`` 通过 ``intpriord`` 控制 priority 是否取反。
* 第 L409 行：``delg_thr_match`` 比较 delegation bit 和当前 interrupt thread。当前单线程配置下
  ``delg_reg`` 固定为 0，``curr_int_tid`` 固定为 0，因此匹配为 1。
* 第 L411 行：只有 gateway request、enable bit 和 delegation/thread match 同时为 1，才把
  priority 送入 ``intpend_w_prior_en``；否则输出全 0。
* 第 L412 行：每路 candidate ID 等于 loop index。

**接口关系** ：

* **被调用** ：priority tree 的 level 0 使用 ``intpend_w_prior_en`` 和 ``intpend_id``。
* **调用** ：无。
* **共享状态** ：``extintsrc_req_gw``、``intenable_reg``、``delg_thr_match``、
  ``intpriority_reg_inv``。

§17  priority tree 与 tie 行为
--------------------------------------------------------------------------------

**职责** ：priority tree 用 ``eh2_cmp_and_mux`` 两两比较 candidate。比较器只在
``a_priority < b_priority`` 时选择 b；priority 相等时选择 a。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L421-L455``）：

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

**逐段解释** ：

* 第 L421 行：当前参数 ``PIC_2CYCLE=1``，因此使用该分支。
* 第 L422-L430 行：两段 priority tree 的 level 数组和中间寄存器输入被建立。
* 第 L431-L433 行：top half priority tree 开始两两比较。
* 该片段展示结构开头；下一片段展示 comparator 实例和最终输出。

**接口关系** ：

* **被调用** ：``intpend_w_prior_en`` 候选向量更新后组合求最大 priority。
* **调用** ：后续实例化 ``eh2_cmp_and_mux`` 与 ``rvdffie``。
* **共享状态** ：``level_intpend_w_prior_en``、``level_intpend_id``、
  ``l2_intpend_w_prior_en_ff``、``l2_intpend_id_ff``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L438-L477``）：

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

**逐段解释** ：

* 第 L438-L445 行：top half 每个 compare node 实例化 ``eh2_cmp_and_mux``，输入两路 ID/priority，
  输出胜出的 ID/priority。
* 第 L450-L455 行：middle flops 把 top half 的 priority 和 ID 一起寄存到
  ``l2_intpend_w_prior_en_ff`` / ``l2_intpend_id_ff``。
* 第 L458-L477 行未完整展示；它继续用 ``eh2_cmp_and_mux`` 做 bottom half 比较，并在 L476-L477
  把最终 ``claimid_in`` 与 ``selected_int_priority`` 接到最后一级输出。

**接口关系** ：

* **被调用** ：priority tree。
* **调用** ：``eh2_cmp_and_mux``、``rvdffie``。
* **共享状态** ：``claimid_in``、``selected_int_priority``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L678-L699``）：

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

**逐段解释** ：

* 第 L678-L690 行：comparator module 输入两路 ID/priority，输出一路 ID/priority。
* 第 L692-L694 行：只在 ``a_priority < b_priority`` 时 ``a_is_lt_b`` 为 1。
* 第 L696-L699 行：``a_is_lt_b`` 为 1 时输出 b，否则输出 a；因此 priority 相等时保留 a。
* 由于 tree 输入按 index 顺序排列，tie 行为由 tree pairing 和 a/b 位置决定；文档不额外推断
  “低编号永远优先”之外的更复杂跨级证明。

**接口关系** ：

* **被调用** ：PIC priority tree 多处实例化。
* **调用** ：无。
* **共享状态** ：输入 priority 和 ID。

§18  pending、threshold 与 wakeup 输出
--------------------------------------------------------------------------------

**职责** ：PIC 把 priority tree 的结果与 ``meipt``、``meicurpl`` 比较，生成
``mexintpend_in``。当选中 priority 等于最大 priority 时生成 ``mhwakeup_in``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L572-L596``）：

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

**逐段解释** ：

* 第 L572-L578 行：当前 ``NUM_THREADS=1`` 时进入 ``one_thread`` 分支，pending、claim ID、
  priority level 和 wakeup 都被寄存。
* 第 L580-L583 行：寄存后的单线程状态直接驱动 ``claimid_out``、``pl_out``、
  ``mexintpend_out`` 和 ``mhwakeup_out``。
* 第 L585-L586 行：threshold 输入直接取 thread 0 的 ``dec_tlu_meipt[0]`` 和
  ``dec_tlu_meicurpl[0]``。

**接口关系** ：

* **被调用** ：PIC output path。
* **调用** ：``rvdff``、``rvdffie``。
* **共享状态** ：``mexintpend_in``、``claimid_in``、``pl_in_q``、``mhwakeup_in``、
  ``dec_tlu_meipt``、``dec_tlu_meicurpl``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L590-L596``）：

.. code-block:: systemverilog

   assign meipt_inv[INTPRIORITY_BITS-1:0]    = intpriord ? ~meipt[INTPRIORITY_BITS-1:0]    : meipt[INTPRIORITY_BITS-1:0] ;
   assign meicurpl_inv[INTPRIORITY_BITS-1:0] = intpriord ? ~meicurpl[INTPRIORITY_BITS-1:0] : meicurpl[INTPRIORITY_BITS-1:0] ;
   assign mexintpend_in = (( selected_int_priority[INTPRIORITY_BITS-1:0] > meipt_inv[INTPRIORITY_BITS-1:0]) &
                           ( selected_int_priority[INTPRIORITY_BITS-1:0] > meicurpl_inv[INTPRIORITY_BITS-1:0]) );

   assign maxint[INTPRIORITY_BITS-1:0]      =  intpriord ? 0 : 15 ;
   assign mhwakeup_in = ( pl_in_q[INTPRIORITY_BITS-1:0] == maxint) ;

**逐段解释** ：

* 第 L590-L591 行：``intpriord`` 为 1 时 threshold 和 current priority level 都取反。
* 第 L592-L593 行：只有 selected priority 同时严格大于 ``meipt_inv`` 和 ``meicurpl_inv``，
  ``mexintpend_in`` 才为 1。
* 第 L595-L596 行：最大 priority 在正常排序下为 15，在 inverted priority 模式下为 0；
  ``pl_in_q`` 等于最大值时产生 wakeup。

**接口关系** ：

* **被调用** ：pending/wakeup flops 的输入。
* **调用** ：无。
* **共享状态** ：``selected_int_priority``、``meipt_inv``、``meicurpl_inv``、
  ``intpriord``、``pl_in_q``。

§19  PIC register readback
--------------------------------------------------------------------------------

**职责** ：PIC readback path 根据 read match 信号返回 pending、threshold-masked pending、
priority、enable、delegation、gateway config、PIC config 或 mask 常量。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L605-L620``）：

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

**逐段解释** ：

* 第 L605-L610 行：各类 register read enable 由地址 match 和 ``picm_rden_ff`` 共同决定。
* 第 L612-L613 行：thread-masked pending 根据 ``picm_rd_thr_ff`` 在 delegation bit 为 1 或 0 的 pending
  中选择。
* 第 L615-L616 行：raw pending 和 thread-masked pending 都被 zero-extend 到 ``INTPEND_SIZE``。
* 第 L618-L620 行：每个 32-bit group 根据 read address 低位选择输出 pending part。

**接口关系** ：

* **被调用** ：``picm_rd_data_in`` mux 使用这些 readback signals。
* **调用** ：无。
* **共享状态** ：``picm_rden_ff``、``picm_rd_thr_ff``、``extintsrc_req_gw``、``delg_reg``、
  ``intpend_reg_extended``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L632-L667``）：

.. code-block:: systemverilog

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
      end

**逐段解释** ：

* 第 L632-L637 行：readback 聚合逻辑先把 enable、delegation、priority 和 gateway config read data 清零。
* 第 L637-L649 行：遍历每个 PIC slot；如果对应 read enable 置位，就把该 slot 的 register 值放到输出。
* 该片段只聚合 per-slot register read data；最终 32-bit mux 在下一片段完成。

**接口关系** ：

* **被调用** ：readback mux。
* **调用** ：无。
* **共享状态** ：``intenable_reg_re``、``delg_reg_re``、``intpriority_reg_re``、
  ``gw_config_reg_re``。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L654-L667``）：

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

**逐段解释** ：

* 第 L654-L660 行：readback mux 根据 read type 选择 pending、threshold pending、priority、enable、
  delegation、gateway config 或 PIC config。
* 第 L661-L664 行：``picm_mken_ff`` 和 ``mask`` 组合返回 store mask 常量。
* 第 L667 行：同地址读写 bypass 时直接返回 ``picm_wr_data_ff``，否则返回 mux 结果。

**接口关系** ：

* **被调用** ：LSU PIC read data path。
* **调用** ：无。
* **共享状态** ：``picm_rd_data``、``picm_bypass_ff``、``picm_wr_data_ff``、``picm_rd_data_in``。

§20  ``pic_map_auto.h`` mask 生成
--------------------------------------------------------------------------------

**职责** ：PIC RTL 在 readback mux 后 include ``pic_map_auto.h``，使用 ``address[14:0]`` 生成
``mask``。本章只记录 include 事实，不展开该 generated header 的内容。

**关键代码** （``rtl/design/eh2_pic_ctrl.sv:L669-L674``）：

.. code-block:: systemverilog

   logic [14:0] address;

   assign address[14:0] = picm_raddr_ff[14:0];

   `include "pic_map_auto.h"

   endmodule

**逐段解释** ：

* 第 L669-L671 行：低 15 bit read address 被赋给 ``address``。
* 第 L673 行：include ``pic_map_auto.h``。readback mux 中的 ``mask`` 来自该 include 文件。
* 第 L675 行：``eh2_pic_ctrl`` module 结束。

**接口关系** ：

* **被调用** ：Verilog 预处理 include。
* **调用** ：``pic_map_auto.h``。
* **共享状态** ：``address``、``mask``。

§21  directed PIC UVM test
--------------------------------------------------------------------------------

**职责** ：``core_eh2_pic_test`` 载入 binary、启动 virtual sequence，并并行运行 PIC stimulus
和 completion wait。stimulus 创建 external IRQ transaction 并送到 IRQ sequencer。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1028-L1055``）：

.. code-block:: systemverilog

     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
       `uvm_info(test_name, "PIC test started", UVM_LOW)
       load_binary_to_mem();
       start_vseq();
       fork
         run_pic_stimulus();
         wait_for_completion(phase);
       join_any
       disable fork;
       if (vseq != null) vseq.stop();
       phase.drop_objection(this);
     endtask

     virtual task run_pic_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       // Test different PIC priority levels
       repeat (20) begin

**逐段解释** ：

* 第 L1028-L1033 行：run phase raise objection、打印启动信息、load binary，并启动 virtual sequence。
* 第 L1033-L1037 行：``run_pic_stimulus()`` 和 ``wait_for_completion()`` 并行，任意一路结束后
  disable fork。
* 第 L1038-L1039 行：停止 vseq 并 drop objection。
* 第 L1042-L1047 行：PIC stimulus task 声明 transaction，先等待 10000 ns，再进入 20 次 repeat。

**接口关系** ：

* **被调用** ：``eh2_directed_pic`` config 使用 ``core_eh2_pic_test``。
* **调用** ：``load_binary_to_mem()``、``start_vseq()``、``run_pic_stimulus()``、
  ``wait_for_completion()``、``vseq.stop()``。
* **共享状态** ：``phase``、``vseq``、``env.irq_agent.sequencer``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1046-L1054``）：

.. code-block:: systemverilog

       repeat (20) begin
         #($urandom_range(1000, 5000) * 10ns);
         txn = eh2_irq_seq_item::type_id::create("txn");
         txn.irq_type = eh2_irq_seq_item::IRQ_EXTERNAL;
         txn.irq_id = $urandom_range(1, 31);  // Lower IDs = higher priority
         txn.irq_val = 1'b1;
         txn.duration = $urandom_range(5, 30);
         eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);

**逐段解释** ：

* 第 L1046-L1048 行：每次 stimulus 随机等待 1000 到 5000 的单位，再创建 transaction。
* 第 L1049-L1052 行：transaction 类型为 ``IRQ_EXTERNAL``，ID 随机范围是 1 到 31，值为 1，
  duration 为 5 到 30。
* 第 L1053 行：调用 ``eh2_irq_seq::send_irq``，把 transaction 送到 IRQ agent sequencer。
* 注释写 “Lower IDs = higher priority”，但本文不把它作为 RTL tie 规则；RTL priority 由
  ``intpriority_reg`` 和 comparator 决定。

**接口关系** ：

* **被调用** ：``run_pic_stimulus()``。
* **调用** ：``$urandom_range``、``type_id::create``、``eh2_irq_seq::send_irq``。
* **共享状态** ：``txn``、``env.irq_agent.sequencer``。

§22  directed testlist 中的 PIC 配置
--------------------------------------------------------------------------------

**职责** ：directed testlist 定义 ``eh2_directed_pic`` config，并把
``directed_pic_state_walk`` 绑定到 ``core_eh2_pic_test`` 和 IRQ plusargs。

**关键代码** （``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L11-L16``）：

.. code-block:: yaml

   - config: eh2_directed_pic
     rtl_test: core_eh2_pic_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

**逐段解释** ：

* 第 L11-L12 行：``eh2_directed_pic`` config 使用 ``core_eh2_pic_test``。
* 第 L13-L16 行：timeout、GCC opts、linker script 和 include 目录与 directed asm 编译相关。

**接口关系** ：

* **被调用** ：regression metadata/testlist 解析脚本读取。
* **调用** ：无。
* **共享状态** ：``rtl_test``、``timeout_s``、``ld_script``。

**关键代码** （``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L224-L230``）：

.. code-block:: yaml

   - test: directed_pic_state_walk
     desc: "PIC/trap claim-complete state stimulus with IRQ sideband"
     config: eh2_directed_pic
     test_srcs: tests/asm/directed_pic_state_walk.S
     sim_opts: '+enable_irq_seq=1 +enable_irq_single_seq=1 +max_interval=20'
     cosim: disabled
     iterations: 1

**逐段解释** ：

* 第 L224-L227 行：``directed_pic_state_walk`` 使用 ``eh2_directed_pic`` config，源文件是
  ``directed_pic_state_walk.S``。
* 第 L228 行：simulation options 打开 ``+enable_irq_seq=1`` 和
  ``+enable_irq_single_seq=1``，并设置 ``+max_interval=20``。
* 第 L229 行：当前 testlist 对该 directed PIC state walk 标记 ``cosim: disabled``。这与
  ADR-0007 中 riscv-dv interrupt cosim unlock 不是同一条 directed asm 用例。

**接口关系** ：

* **被调用** ：directed regression flow。
* **调用** ：无。
* **共享状态** ：``sim_opts``、``cosim``、``iterations``。

§23  directed PIC state walk 汇编
--------------------------------------------------------------------------------

**职责** ：``directed_pic_state_walk.S`` 设置 trap handler，打开 M-mode interrupt enable 和
machine external interrupt enable，执行 ECALL，并在 trap handler 中设置进度标志。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_pic_state_walk.S:L13-L23``）：

.. code-block:: bash

   _start:
       la      t0, trap_handler
       csrw    mtvec, t0

       li      s0, 0
       li      t0, (1 << 3)        // mstatus.MIE
       csrs    mstatus, t0
       li      t0, (1 << 11)       // mie.MEIE
       csrs    mie, t0

       ecall

**逐段解释** ：

* 第 L13-L16 行：入口加载 ``trap_handler`` 地址并写入 ``mtvec``。
* 第 L17-L21 行：清零 ``s0``，设置 ``mstatus.MIE`` 和 ``mie.MEIE``。
* 第 L23 行：执行 ``ecall``，保证至少有一次 trap entry/complete 路径。

**接口关系** ：

* **被调用** ：directed test binary 从 ``_start`` 执行。
* **调用** ：CSR 指令 ``csrw``、``csrs`` 和 ``ecall``。
* **共享状态** ：``mtvec``、``mstatus``、``mie``、``s0``。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_pic_state_walk.S:L48-L63``）：

.. code-block:: bash

   .align 4
   trap_handler:
       csrr    t0, mcause
       li      t1, 11              // ECALL from M-mode
       beq     t0, t1, ecall_seen

       // External IRQ path: mark progress and return to interrupted PC.
       li      s0, 0xCAFE
       mret

   ecall_seen:
       li      s0, 0xCAFE
       csrr    t0, mepc
       addi    t0, t0, 4
       csrw    mepc, t0
       mret

**逐段解释** ：

* 第 L48-L52 行：handler 读取 ``mcause``，若为 11 则进入 ECALL 分支。
* 第 L54-L56 行：非 ECALL path 被注释为 external IRQ path，设置 ``s0=0xCAFE`` 后 ``mret``。
* 第 L58-L63 行：ECALL path 同样设置 ``s0=0xCAFE``，读取并推进 ``mepc`` 4 字节后返回。
* 该汇编保证 trap path 有可见进度；external IRQ 是否落入窗口还取决于 UVM sideband stimulus。

**接口关系** ：

* **被调用** ：``mtvec`` 指向该 handler。
* **调用** ：CSR read/write、branch 和 ``mret``。
* **共享状态** ：``mcause``、``mepc``、``s0``。

§24  IRQ basic 与 nested trap 用例边界
--------------------------------------------------------------------------------

**职责** ：``directed_irq_basic.S`` 和 ``directed_nested_irq.S`` 验证 trap/return 与 nested ECALL
路径，不直接配置 PIC memory-mapped registers。它们属于 interrupt/trap 参考用例，但不是 PIC
priority tree 的直接测试。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_irq_basic.S:L43-L62``）：

.. code-block:: bash

   // ---- Trap handler ----
   .align 4
   trap_handler:
       // Read mcause - should be 11 (ecall from M-mode)
       csrr    t0, mcause
       li      t1, 11
       bne     t0, t1, trap_unexpected

       // Read mepc (should point to ecall instruction)
       csrr    t0, mepc

       // Signal to main code that handler ran
       li      x31, 0xCAFE

       // Advance mepc past ecall (4 bytes)
       addi    t0, t0, 4
       csrw    mepc, t0

       // Return from trap
       mret

**逐段解释** ：

* 第 L43-L49 行：basic IRQ 用例 handler 检查 ``mcause`` 是否为 M-mode ECALL 的 11。
* 第 L51-L59 行：读取 ``mepc``，设置 ``x31=0xCAFE``，推进 ``mepc``。
* 第 L61-L62 行：执行 ``mret`` 返回。
* 文件头注释写明该测试不依赖 interrupt controller behavior，因此不把它作为 PIC 本体功能证据。

**接口关系** ：

* **被调用** ：``mtvec`` trap handler。
* **调用** ：CSR read/write、branch 和 ``mret``。
* **共享状态** ：``mcause``、``mepc``、``x31``。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_nested_irq.S:L72-L91``）：

.. code-block:: bash

   first_level:
       // Save mepc on stack (we need it after the nested ecall)
       csrr    t0, mepc
       addi    sp, sp, -8
       sw      t0, 0(sp)
       // Also save mstatus so nested mret works correctly
       csrr    t0, mstatus
       sw      t0, 4(sp)

       // Increment depth to 1
       li      t0, 1
       csrw    mscratch, t0

       // Advance mepc past the first ecall (so mret after second-level goes right)
       csrr    t0, mepc
       addi    t0, t0, 4
       csrw    mepc, t0

       // Trigger second-level ECALL from within the handler
       ecall

**逐段解释** ：

* 第 L72-L79 行：first-level handler 保存 ``mepc`` 和 ``mstatus`` 到 stack。
* 第 L81-L88 行：用 ``mscratch`` 记录嵌套深度，并推进 first-level ``mepc``。
* 第 L90-L91 行：handler 内再次执行 ``ecall``，形成 nested trap。
* 该用例覆盖 nested trap 栈行为；PIC 章节只将其作为 interrupt/trap 相关背景，不把它写成
  external PIC arbitration 证据。

**接口关系** ：

* **被调用** ：nested trap handler。
* **调用** ：CSR read/write、stack store 和 ``ecall``。
* **共享状态** ：``mepc``、``mstatus``、``mscratch``、``sp``。

§25  Formal PIC properties
--------------------------------------------------------------------------------

**职责** ：``eh2_pic_assert.sv`` 定义 PIC 形式属性接口和若干 property。属性文件表达的意图包括
valid claim、threshold gating、max-priority wakeup、enable gating、priority tree monotonicity
和 claim sequence cover。

**关键代码** （``dv/formal/properties/eh2_pic_assert.sv:L19-L53``）：

.. code-block:: systemverilog

   module eh2_pic_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        free_clk,
     input logic        rst_l,

     // --- Interrupt source requests ---
     input logic [pt.PIC_TOTAL_INT_PLUS1-1:0]   extintsrc_req,

     // --- Outputs to core ---
     input logic [pt.NUM_THREADS-1:0]            mexintpend_out,
     input logic [pt.NUM_THREADS-1:0][7:0]       claimid_out,
     input logic [pt.NUM_THREADS-1:0][3:0]       pl_out,
     input logic [pt.NUM_THREADS-1:0]            mhwakeup_out,

**逐段解释** ：

* 第 L19-L23 行：property module 导入 ``eh2_pkg`` 并 include 参数。
* 第 L24-L29 行：输入包括 clock、reset 和 ``extintsrc_req``。
* 第 L31-L35 行：property 观察 PIC 输出到 core 的 ``mexintpend_out``、``claimid_out``、
  ``pl_out`` 和 ``mhwakeup_out``。
* 后续端口包括 DEC/TLU threshold 输入、内部 register 状态和 priority tree 输出。

**接口关系** ：

* **被调用** ：``eh2_formal_bind.sv`` 通过 ``bind eh2_pic_ctrl`` 绑定该 module。
* **调用** ：SystemVerilog assertion property。
* **共享状态** ：PIC outputs、threshold 输入、内部 register 观察端口。

**关键代码** （``dv/formal/properties/eh2_pic_assert.sv:L66-L89``）：

.. code-block:: systemverilog

     property p_int_pending_implies_valid_claim;
       @(posedge clk) disable iff (~rst_l)
         (mexintpend_out[0])
           |->
         (claimid_out[0] > 0) && (claimid_out[0] < pt.PIC_TOTAL_INT_PLUS1);
     endproperty
     a_int_pending_implies_valid_claim: assert property (p_int_pending_implies_valid_claim)
       else $error("FORMAL FAIL: mexintpend with invalid claimid");

     // ========================================================================
     // Property 2: Priority below threshold = no interrupt
     //
     // SAIL-REF: sail-riscv/model/riscv_platform.sail function pending()
     // If the selected interrupt priority is not strictly greater than the
     // current privilege level threshold (meicurpl), no interrupt is taken.
     // ========================================================================

**逐段解释** ：

* 第 L66-L73 行：当 ``mexintpend_out[0]`` 为 1 时，``claimid_out[0]`` 必须大于 0 且小于
  ``PIC_TOTAL_INT_PLUS1``。
* 第 L76-L89 行：第二个属性的注释和实现说明 selected priority 小于等于 threshold 时不应产生
  ``mexintpend_out[0]``。
* 这些属性位于 ``ifdef FORMAL`` 内，仿真普通编译不会启用。

**接口关系** ：

* **被调用** ：formal tool 在 ``FORMAL`` define 下检查。
* **调用** ：SVA ``assert property``。
* **共享状态** ：``mexintpend_out``、``claimid_out``、``selected_int_priority``、
  ``dec_tlu_meipt``。

**关键代码** （``dv/formal/properties/eh2_pic_assert.sv:L98-L120``）：

.. code-block:: systemverilog

     property p_wakeup_on_max_priority;
       @(posedge clk) disable iff (~rst_l)
         ((selected_int_priority == 4'hF) && (|extintsrc_req_gw))
           |=>
         mhwakeup_out[0];
     endproperty
     a_wakeup_on_max_priority: assert property (p_wakeup_on_max_priority)
       else $error("FORMAL FAIL: max priority did not trigger wakeup");

     // ========================================================================
     // Property 4: Interrupt pending requires enable bit
     //
     // An interrupt source can only contribute to intpend if both:
     //   (a) the external request is active (extintsrc_req_gw[i] == 1)
     //   (b) the enable bit is set (intenable_reg[i] == 1)
     // ========================================================================
     property p_intpend_enable_gate;

**逐段解释** ：

* 第 L98-L105 行：selected priority 为 ``4'hF`` 且存在 gateway request 时，下一拍要求
  ``mhwakeup_out[0]``。
* 第 L108-L114 行：注释说明 pending 需要 external request 与 enable bit 同时满足。
* 第 L114-L120 行：``p_intpend_enable_gate`` 在 ``mexintpend_in`` 且 priority 高于 threshold 时，
  要求 ``extintsrc_req_gw & intenable_reg`` 至少有一位。

**接口关系** ：

* **被调用** ：formal check。
* **调用** ：SVA property。
* **共享状态** ：``selected_int_priority``、``extintsrc_req_gw``、``mhwakeup_out``、
  ``intenable_reg``。

**关键代码** （``dv/formal/properties/eh2_pic_assert.sv:L128-L145``）：

.. code-block:: systemverilog

     property p_priority_tree_monotonic;
       @(posedge clk) disable iff (~rst_l)
         (|extintsrc_req_gw)
           |->
         (selected_int_priority >= 0);
     endproperty
     a_priority_tree_monotonic: assert property (p_priority_tree_monotonic)
       else $error("FORMAL FAIL: priority tree underflow");

     // ========================================================================
     // Cover Property 1: Full interrupt claim sequence
     // ========================================================================
     c_interrupt_claim_sequence: cover property (
       @(posedge clk) disable iff (~rst_l)
         (|extintsrc_req)           // source requests interrupt
           ##1 mexintpend_out[0]    // interrupt becomes pending

**逐段解释** ：

* 第 L128-L135 行：``p_priority_tree_monotonic`` 当前实现只要求存在 gateway request 时
  ``selected_int_priority >= 0``。由于 signal 是 unsigned 4-bit，这是一条较弱属性，不能写成完整
  priority tree 最大值证明。
* 第 L140-L145 行：cover property 描述 request、pending、claim ID 非 0 的序列。

**接口关系** ：

* **被调用** ：formal cover/assert flow。
* **调用** ：SVA ``assert property`` 和 ``cover property``。
* **共享状态** ：``extintsrc_req_gw``、``selected_int_priority``、``extintsrc_req``、
  ``mexintpend_out``、``claimid_out``。

§26  Formal bind 边界
--------------------------------------------------------------------------------

**职责** ：``eh2_formal_bind.sv`` 把 ``eh2_pic_assert`` bind 到 ``eh2_pic_ctrl``。当前 bind
只把输出和 threshold 等少数端口接到实际信号，若干内部状态端口接常量，因此文档不能声称它完整绑定
PIC 内部 register 状态。

**关键代码** （``dv/formal/eh2_formal_bind.sv:L53-L74``）：

.. code-block:: systemverilog

   // ============================================================================
   // Bind eh2_pic_assert to eh2_pic_ctrl (interrupt controller)
   // ============================================================================
   bind eh2_pic_ctrl eh2_pic_assert #() u_pic_assert (
       .clk                        (clk),
       .free_clk                   (free_clk),
       .rst_l                      (rst_l),
       .extintsrc_req              (extintsrc_req),
       .mexintpend_out             (mexintpend_out),
       .claimid_out                (claimid_out),
       .pl_out                     (pl_out),
       .mhwakeup_out               (mhwakeup_out),
       .dec_tlu_meicurpl           (dec_tlu_meicurpl),
       .dec_tlu_meipt              (dec_tlu_meipt),
       .config_reg                 (picm_wren),
       .intenable_reg              ('0),

**逐段解释** ：

* 第 L53-L56 行：bind 目标是 ``eh2_pic_ctrl``，实例名 ``u_pic_assert``。
* 第 L57-L66 行：clock/reset、external request、PIC outputs 和 DEC/TLU threshold 输入接到同名信号。
* 第 L67-L68 行：``config_reg`` 接到了 ``picm_wren``，``intenable_reg`` 接常量 0。
* 这说明当前 bind 不是对所有内部 PIC register 状态的透明连接。

**接口关系** ：

* **被调用** ：formal compile/elaboration 时执行 bind。
* **调用** ：实例化 ``eh2_pic_assert``。
* **共享状态** ：``mexintpend_out``、``claimid_out``、``pl_out``、``mhwakeup_out``。

**关键代码** （``dv/formal/eh2_formal_bind.sv:L67-L74``）：

.. code-block:: systemverilog

       .config_reg                 (picm_wren),
       .intenable_reg              ('0),
       .intpriority_reg            ('0),
       .extintsrc_req_gw           ('0),
       .delg_reg                   ('0),
       .selected_int_priority      ('0),
       .claimid_in                 ('0)
   );

**逐段解释** ：

* 第 L67-L73 行：多个 property module 输入接常量 0，包括 enable、priority、gateway request、
  delegation、selected priority 和 claim ID internal input。
* 因此，本章将 formal PIC properties 解释为“属性文件和当前 bind 事实”，不将其描述成完整内部状态证明。

**接口关系** ：

* **被调用** ：formal bind。
* **调用** ：无。
* **共享状态** ：常量绑定影响对应 property 的实际检查强度。

§27  cosim CSR 预注册
--------------------------------------------------------------------------------

**职责** ：cosim scoreboard include 的 CSR preregister 文件为 Spike 注册 EH2 custom CSRs，
其中包括 PIC 相关 CSR。这样 Spike 遇到这些 CSR access 时不会因为 csrmap 缺项而直接非法。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh:L31-L41``）：

.. code-block:: systemverilog

         riscv_cosim_set_csr(cosim_handle, 32'hBC0, 0, 0);  // mdeau
         riscv_cosim_set_csr(cosim_handle, 32'hFC0, 0, 0);  // mdseac
         riscv_cosim_set_csr(cosim_handle, 32'h7F0, 0, 0);  // micect
         riscv_cosim_set_csr(cosim_handle, 32'h7F1, 0, 0);  // miccmect
         riscv_cosim_set_csr(cosim_handle, 32'h7F2, 0, 0);  // mdccmect
         riscv_cosim_set_csr(cosim_handle, 32'hBC8, 0, 0);  // meivt
         riscv_cosim_set_csr(cosim_handle, 32'hFC8, 0, 0);  // meihap
         riscv_cosim_set_csr(cosim_handle, 32'hBC9, 0, 0);  // meipt
         riscv_cosim_set_csr(cosim_handle, 32'hBCA, 0, 0);  // meicpct
         riscv_cosim_set_csr(cosim_handle, 32'hBCC, 0, 0);  // meicurpl
         riscv_cosim_set_csr(cosim_handle, 32'hBCB, 0, 0);  // meicidpl

**逐段解释** ：

* 第 L31-L35 行：注册若干 EH2 custom CSR。
* 第 L36-L41 行：注册 PIC/interrupt 相关 CSR：``meivt``、``meihap``、``meipt``、
  ``meicpct``、``meicurpl`` 和 ``meicidpl``。
* 每个调用把 CSR 初始值设为 0，最后一个参数也为 0；具体 C++ 语义由 ``riscv_cosim_set_csr``
  实现决定。

**接口关系** ：

* **被调用** ：cosim scoreboard 初始化时 include。
* **调用** ：``riscv_cosim_set_csr``。
* **共享状态** ：``cosim_handle`` 和 Spike CSR map。

§28  SpikeCosim 中的 PIC CSR 初始化与 WARL fixup
--------------------------------------------------------------------------------

**职责** ：C++ cosim 侧在 ``initial_proc_setup()`` 中把 EH2 custom CSRs 放入 Spike
``csrmap``，并在 ``fixup_csr()`` 中限制 ``meipt``、``meicurpl`` 和 ``meicidpl`` 的可写位。

**关键代码** （``dv/cosim/spike_cosim.cc:L712-L744``）：

.. code-block:: cpp

     // Initialize EH2 custom CSRs in csrmap so they can be read/written
     // These are WD/Microchip extensions not natively supported by Spike
     static const int eh2_init_csrs[] = {
       0x7FF,  // mscause
       0x7C0,  // mrac
       0x7F9,  // mfdc
       0x7F8,  // mcgc
       0x7C6,  // mpmc
       0x7C2,  // mcpc
       0x7C4,  // dmst
       0x7CE,  // mfdht
       0x7CF,  // mfdhs
       0x7FC,  // mhartstart
       0x7FE,  // mnmipdel
       0x7D2,  // mitcnt0
       0x7D5,  // mitcnt1
       0x7D3,  // mitb0
       0x7D6,  // mitb1
       0x7D4,  // mitctl0
       0x7D7,  // mitctl1

**逐段解释** ：

* 第 L712-L714 行：注释说明 EH2 custom CSR 不是 Spike 原生支持，需要初始化到 csrmap。
* 第 L715-L731 行：数组列出 mscause、mrac、debug/perf 等 custom CSR。
* 该片段未完整列出 PIC CSR，是为了控制代码片段长度；下一片段继续。

**接口关系** ：

* **被调用** ：``SpikeCosim`` 初始化 processor 时调用 ``initial_proc_setup()``。
* **调用** ：后续循环会写 ``csrmap``。
* **共享状态** ：``proc->get_state()->csrmap``、``eh2_init_csrs``。

**关键代码** （``dv/cosim/spike_cosim.cc:L732-L743``）：

.. code-block:: cpp

       0xBC0,  // mdeau
       0xFC0,  // mdseac
       0x7F0,  // micect
       0x7F1,  // miccmect
       0x7F2,  // mdccmect
       0xBC8,  // meivt
       0xFC8,  // meihap
       0xBC9,  // meipt
       0xBCA,  // meicpct
       0xBCC,  // meicurpl
       0xBCB,  // meicidpl
       0xFC4,  // mhartnum

**逐段解释** ：

* 第 L732-L736 行：继续列出 EH2 custom CSR。
* 第 L737-L742 行：PIC/interrupt 相关 CSR 包括 ``meivt``、``meihap``、``meipt``、
  ``meicpct``、``meicurpl`` 和 ``meicidpl``。
* 第 L743 行：``mhartnum`` 也进入初始化列表。

**接口关系** ：

* **被调用** ：``initial_proc_setup()``。
* **调用** ：数组初始化。
* **共享状态** ：``eh2_init_csrs``。

**关键代码** （``dv/cosim/spike_cosim.cc:L1168-L1182``）：

.. code-block:: cpp

       // --- meipt (0xBC9): PIC Priority Threshold ---
       // --- meicurpl (0xBCC): PIC Current Priority Level ---
       // --- meicidpl (0xBCB): PIC Core Interrupt Priority Level ---
       // All: bits [3:0] writable, high 28 bits hardwired 0
       case 0xBC9:
       case 0xBCC:
       case 0xBCB: {
         uint32_t fixed = csr_val & 0xF;
         if (proc->get_state()->csrmap.find(csr_num) ==
             proc->get_state()->csrmap.end()) {
           proc->get_state()->csrmap[csr_num] =
               std::make_shared<basic_csr_t>(proc, csr_num, 0);
         }
         proc->get_state()->csrmap[csr_num]->write(fixed);
         break;

**逐段解释** ：

* 第 L1168-L1171 行：注释说明 ``meipt``、``meicurpl`` 和 ``meicidpl`` 只有低 4 bit 可写，
  高 28 bit 硬连 0。
* 第 L1172-L1175 行：三个 CSR 共用同一 fixup 分支，``fixed = csr_val & 0xF``。
* 第 L1176-L1181 行：若 csrmap 还没有该 CSR，则创建 ``basic_csr_t``，随后写入 masked 值。

**接口关系** ：

* **被调用** ：cosim CSR write fixup 路径。
* **调用** ：``std::make_shared<basic_csr_t>`` 和 CSR ``write``。
* **共享状态** ：Spike processor CSR map。

§29  ADR-0007 中的 cosim 边界
--------------------------------------------------------------------------------

**职责** ：ADR-0007 说明 interrupt cosim 的决策边界：Spike 不实现完整 EH2 PIC model，而是通过
CSR 注册、CSR fixup 和 interrupt trace item 处理来闭合 interrupt cosim。

**关键摘录** （``docs/adr/0007-interrupt-cosim.md:L23-L32``）：

ADR-0007 在第 L23-L28 行记录 interrupt-only trace item 的处理方式：scoreboard 区分
``interrupt=1 && exception=0`` 的 trace item，对这类 item 调用 Spike 的 ``set_mip()``，
不执行 ``step()``，并把 ``mcause`` / ``mepc`` mismatch 纳入 UVM error 与
``mismatch_count``。第 L30-L32 行记录 PIC 相关 custom CSR 通过
``initial_proc_setup()`` 注册，并由 ``fixup_csr()`` 执行 WARL fixup。

**逐段解释** ：

* 第 L23-L28 行：ADR 描述 interrupt-only trace item 的 cosim 行为：更新 Spike pending bits，不执行
  ``step()``，并用 UVM error/mismatch count 比较 ``mcause`` / ``mepc``。
* 第 L30-L32 行：ADR 明确 PIC 相关 custom CSR 在 ``spike_cosim.cc`` 中注册并在
  ``fixup_csr()`` 中做 WARL fixup。
* 该 ADR 不等同于 Spike 中有完整 PIC priority arbiter；它记录的是 cosim 策略。

**接口关系** ：

* **被调用** ：文档引用，cosim 实现与验证计划对齐。
* **调用** ：无。
* **共享状态** ：ADR 决策与 ``spike_cosim.cc`` CSR 初始化/fixup 实现。

**关键摘录** （``docs/adr/0007-interrupt-cosim.md:L47-L60``）：

ADR-0007 在第 L49-L53 行列出两种被拒绝方案：在 Spike 内实现完整 PIC model，以及过滤
interrupt trace item。第 L57-L60 行记录后果：interrupt tests 尝试 cosim lockstep，
``mcause`` / ``mepc`` mismatch 需要正确失败，PIC 行为通过 CSR 注册和 fixup 对齐。

**逐段解释** ：

* 第 L49-L50 行：ADR 明确拒绝在 Spike 中实现完整 PIC model，因为需要加入 127 个外部中断源和
  priority arbitration。
* 第 L52-L53 行：ADR 也拒绝过滤 interrupt trace item，因为这会绕过 interrupt entry/exit。
* 第 L57-L59 行：结果是 interrupt tests 尝试 cosim lockstep，``mcause`` / ``mepc`` mismatch
  正确失败。

**接口关系** ：

* **被调用** ：cosim 文档与签核说明引用。
* **调用** ：无。
* **共享状态** ：:ref:`adr-0007` 的 interrupt cosim 决策。

§30  常见误读边界
--------------------------------------------------------------------------------

**职责** ：把旧文档或表层理解中无法由当前源码证明的描述排除掉，保持 PIC 章节与 ground truth 一致。

**关键边界** ：

* 当前参数中 priority 宽度来自 ``INTPRIORITY_BITS=4``；本文不写“4/8/16 级可配”，因为所引源码没有
  对 priority level 数做运行时配置。
* ``PIC_TOTAL_INT=127``，UVM interface 驱动 ``extintsrc_req[127:1]``；PIC RTL 内部使用
  ``PIC_TOTAL_INT_PLUS1=128``，index 0 固定为 0。
* ``eh2_cmp_and_mux`` 在 priority 相等时选择 a 输入。本文只描述 comparator 的 tie 行为，不推断未逐级证明的全局 ID tie 规则。
* 当前 ``directed_pic_state_walk`` 在 directed testlist 中 ``cosim: disabled``；ADR-0007 描述的是
  interrupt riscv-dv cosim unlock 和 PIC CSR registration，不表示该 directed PIC asm 已启用 cosim。
* Formal PIC bind 当前有多个内部状态端口接常量，因此不能把 property 文件的注释当作完整 formal 覆盖结论。
* ``rtl/design/eh2_pic_ctrl.sv`` 当前不在 ``feeac23a...`` 的 ``HEAD`` tree 中；本章引用它是因为当前工作区、
  filelist 和现有文档均使用该路径。

§31  参考资料
--------------------------------------------------------------------------------

**关联 ADR** ：

* :ref:`adr-0007`：Interrupt cosim closure；说明 PIC CSR 注册、interrupt-only trace item 和不在 Spike
  中实现完整 PIC model 的决策。

**关联章节** ：

* :doc:`/appendix_a_rtl/pic`：RTL PIC 字典。
* :doc:`/05_verification_arch/agent_irq`：IRQ agent 验证架构说明。
* :doc:`/appendix_b_uvm/irq_agent`：IRQ agent 类字典。
* :doc:`/appendix_c_tools/cosim_cpp`：SpikeCosim C++ CSR fixup 和 cosim API。
* :doc:`/06_flows/formal_flow`：formal flow 入口。

**源文件绝对路径** ：

* :file:`/home/host/eh2-veri/syn/include/eh2_param.vh`
* :file:`/home/host/eh2-veri/rtl/design/eh2_pic_ctrl.sv`
* :file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_dccm_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/lib/beh_lib.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/irq_agent/eh2_irq_driver.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pic_state_walk.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_irq_basic.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_nested_irq.S`
* :file:`/home/host/eh2-veri/dv/formal/properties/eh2_pic_assert.sv`
* :file:`/home/host/eh2-veri/dv/formal/eh2_formal_bind.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_csr_preregister.svh`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.cc`
* :file:`/home/host/eh2-veri/docs/adr/0007-interrupt-cosim.md`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
