.. _appendix_a_rtl_lsu:
.. _appendix_a_rtl/lsu:

存储单元（LSU）- 详细参考
==========================

:status: draft
:source: rtl/design/lsu/
:last-reviewed: 2026-05-19

§1  源文件边界与数据流
----------------------

本章只描述当前源码中的 LSU 实现。LSU 源文件位于
:file:`rtl/design/lsu/`，并由 :file:`dv/uvm/core_eh2/eh2_rtl.f`
的 ``// Load/Store Unit`` 分组纳入 RTL 编译。本文不会把外部 ISA 规则、
旧版微架构说明或验证经验写成源码事实；所有端口、状态、时序和异常关系均来自
当前 commit 下的 SystemVerilog 源码。

LSU 的主要数据流如下：

.. code-block:: text

   DEC lsu_p / rs1 / rs2 / offset
      |
      v
   eh2_lsu_lsc_ctl
      |
      +-- address generation and eh2_lsu_addrcheck
      +-- DC1..DC5 packet, address and store-data pipeline
      +-- load result mux and LR/SC reservation
      |
      +-- DCCM path -> eh2_lsu_dccm_ctl -> eh2_lsu_ecc -> eh2_lsu_dccm_mem
      |
      +-- PIC path  -> picm_rden / picm_wren / picm_mken
      |
      +-- bus path  -> eh2_lsu_bus_intf -> per-thread eh2_lsu_bus_buffer
      |
      +-- store path -> eh2_lsu_stbuf -> DCCM writeback / forwarding
      |
      +-- optional AMO path -> eh2_lsu_amo
      |
      +-- debug trigger path -> eh2_lsu_trigger
      |
      +-- clocks -> eh2_lsu_clkdomain

``eh2_lsu`` 是 LSU 顶层集成模块。``eh2_lsu_lsc_ctl`` 负责地址生成、
流水线包传播、load 结果选择和 LR/SC 预约；``eh2_lsu_addrcheck`` 负责
DCCM、PIC、ICCM 和外部区域判断；``eh2_lsu_dccm_ctl`` 负责 DCCM/PIC
读写、store buffer 前递和 ECC 纠正写回；``eh2_lsu_stbuf`` 负责 DCCM store
缓冲和前递；``eh2_lsu_bus_intf`` 与 ``eh2_lsu_bus_buffer`` 负责外部 AXI
事务和 NB-load 回传；``eh2_lsu_ecc``、``eh2_lsu_amo``、``eh2_lsu_trigger``、
``eh2_lsu_clkdomain`` 和 ``eh2_lsu_dccm_mem`` 分别覆盖 ECC、AMO、trigger、
时钟门控和 DCCM SRAM wrapper。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L48-L60``）：

.. code-block:: text

   // Load/Store Unit
   rtl/design/lsu/eh2_lsu_addrcheck.sv
   rtl/design/lsu/eh2_lsu_amo.sv
   rtl/design/lsu/eh2_lsu_bus_buffer.sv
   rtl/design/lsu/eh2_lsu_bus_intf.sv
   rtl/design/lsu/eh2_lsu_clkdomain.sv
   rtl/design/lsu/eh2_lsu_dccm_ctl.sv
   rtl/design/lsu/eh2_lsu_dccm_mem.sv
   rtl/design/lsu/eh2_lsu_ecc.sv
   rtl/design/lsu/eh2_lsu_lsc_ctl.sv
   rtl/design/lsu/eh2_lsu_stbuf.sv
   rtl/design/lsu/eh2_lsu.sv
   rtl/design/lsu/eh2_lsu_trigger.sv

逐段解释：

* 第 L48 行：filelist 用 ``// Load/Store Unit`` 标出 LSU 编译分组。该分组是
  本章的源码边界。
* 第 L49-L60 行：当前 LSU 分组列出 12 个 SystemVerilog 文件。文件名显示
  ``eh2_lsu.sv`` 是顶层，``eh2_lsu_lsc_ctl.sv`` 和
  ``eh2_lsu_addrcheck.sv`` 负责核心控制和地址检查，``eh2_lsu_bus_*`` 负责
  外部总线，``eh2_lsu_dccm_*`` 负责 DCCM。

接口关系：

* 被引用：仿真和综合 filelist 通过 :file:`dv/uvm/core_eh2/eh2_rtl.f`
  把这些文件加入 RTL 编译。
* 调用：filelist 不调用逻辑，只定义编译输入集合。
* 共享状态：无运行时状态；运行时状态存在于各 RTL 模块的 flop、组合信号和端口。

§2  ``eh2_lsu.sv`` 顶层集成
----------------------------

``eh2_lsu`` 的职责是把 DEC、EXU、TLU、DCCM、PIC、DMA 和 AXI 端口连接成一个
五级 load/store 子系统，并实例化 LSU 目录下的主要子模块。源码注释明确该模块是
``Top level file for load store unit``，流水线标注为 ``DC1 -> DC2 -> DC3 -> DC4``，
其中源码信号继续保留 ``dc5`` 作为 commit/writeback 相关阶段。

§2.1  模块边界和上游控制入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 LSU 顶层模块、导入参数包，并接收 EXU 结果、flush、TLU 配置和
DEC 发来的地址操作数。该端口组决定 LSU 对外可见的阻塞、错误、NB-load 和
AXI 接口。

关键代码（``rtl/design/lsu/eh2_lsu.sv:L28-L58``）：

.. code-block:: systemverilog

   module eh2_lsu
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )(

      input logic [31:0]                      i0_result_e4_eff, // I0 e4 result for e4 -> dc3 store forwarding
      input logic [31:0]                      i1_result_e4_eff, // I1 e4 result for e4 -> dc3 store forwarding
      input logic [31:0]                      i0_result_e2,     // I0 e2 result for e2 -> dc2 store forwarding

      input logic [pt.NUM_THREADS-1:0]        flush_final_e3,            // I0/I1 flush in e3
      input logic [pt.NUM_THREADS-1:0]        i0_flush_final_e3,         // I0 flush in e3
      input logic [pt.NUM_THREADS-1:0]        dec_tlu_flush_lower_wb,    // I0/I1 writeback flush. This is used to flush the old packets only
      input logic                             dec_tlu_i0_kill_writeb_wb, // I0 is flushed, don't writeback any results to arch state
      input logic                             dec_tlu_i1_kill_writeb_wb, // I1 is flushed, don't writeback any results to arch state
      input logic [pt.NUM_THREADS-1:0]        dec_tlu_lr_reset_wb,
      input logic [pt.NUM_THREADS-1:0]        dec_tlu_force_halt,

      input logic                             dec_tlu_external_ldfwd_disable,     // disable load to load forwarding for externals
      input logic                             dec_tlu_wb_coalescing_disable,      // disable the write buffer coalesce
      input logic                             dec_tlu_sideeffect_posted_disable,  // disable posted writes to sideeffect addr to the bus
      input logic                             dec_tlu_core_ecc_disable,           // disable the generation of the ecc

      input logic [31:0]                      exu_lsu_rs1_d,      // address rs operand
      input logic [31:0]                      exu_lsu_rs2_d,      // store data
      input logic [11:0]                      dec_lsu_offset_d,   // address offset operand

逐段解释：

* 第 L28-L32 行：模块名是 ``eh2_lsu``，导入 ``eh2_pkg``，并 include
  ``eh2_param.vh``。后续 ``pt.NUM_THREADS``、``pt.DCCM_*`` 和 ``pt.LSU_*``
  参数均来自该参数结构。
* 第 L34-L36 行：EXU 提供 E4 和 E2 级结果，端口注释直接说明这些信号用于
  store data bypass。
* 第 L38-L44 行：TLU 和 EXU flush 信号按线程进入 LSU。``dec_tlu_lr_reset_wb``
  是 LR/SC 预约清除输入，``dec_tlu_force_halt`` 同时影响 bus buffer 和 clockdomain。
* 第 L46-L49 行：TLU 配置位可关闭外部 load forwarding、write buffer coalescing、
  side-effect posted write 和 ECC 生成/检查。
* 第 L51-L53 行：``exu_lsu_rs1_d``、``exu_lsu_rs2_d`` 和
  ``dec_lsu_offset_d`` 是地址生成和 store data 管线的入口。

接口关系：

* 被实例化：上层 core wrapper 实例化 ``eh2_lsu``。
* 调用：顶层端口本身不调用子模块；实例化发生在同文件第 L315-L465 行。
* 共享状态：共享 ``pt`` 参数、DEC/TLU 控制信号、EXU 旁路结果和 LSU 管线状态。

§2.2  DCCM、PIC、AXI 和 DMA 端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 LSU 内部访问路径外露为 DCCM/PIC/AXI/DMA 端口。源码中这些端口分组清楚：
DCCM 是内部紧耦合 memory 端口，PIC 是 32-bit PIC memory 端口，AXI 是外部 LSU
master 端口，DMA slave 端口通过 LSU 访问 DCCM/PIC。

关键代码（``rtl/design/lsu/eh2_lsu.sv:L105-L190``）：

.. code-block:: systemverilog

      // DCCM ports
      output logic                            dccm_wren,       // DCCM write enable
      output logic                            dccm_rden,       // DCCM read enable
      output logic [pt.DCCM_BITS-1:0]         dccm_wr_addr_lo, // DCCM write address low bankd
      output logic [pt.DCCM_BITS-1:0]         dccm_wr_addr_hi, // DCCM write address low bankd
      output logic [pt.DCCM_BITS-1:0]         dccm_rd_addr_lo, // DCCM read address low bank
      output logic [pt.DCCM_BITS-1:0]         dccm_rd_addr_hi, // DCCM read address hi bank (hi and low same if aligned read)
      output logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_wr_data_lo, // DCCM write data for hi bank
      output logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_wr_data_hi, // DCCM write data for hi bank

      input logic [pt.DCCM_FDATA_WIDTH-1:0]   dccm_rd_data_lo, // DCCM read data low bank
      input logic [pt.DCCM_FDATA_WIDTH-1:0]   dccm_rd_data_hi, // DCCM read data hi bank

      // PIC ports
      output logic                            picm_wren,        // PIC memory write enable
      output logic                            picm_rden,        // PIC memory read enable
      output logic                            picm_mken,        // Need to read the mask for stores to determine which bits to write/forward
      output logic                            picm_rd_thr,      // PICM read thread
      output logic [31:0]                     picm_rdaddr,      // PIC memory address
      output logic [31:0]                     picm_wraddr,      // PIC memory address
      output logic [31:0]                     picm_wr_data,     // PIC memory write data
      input logic [31:0]                      picm_rd_data,     // PIC memory read/mask data

逐段解释：

* 第 L105-L116 行：DCCM 端口同时提供 lo/hi read/write address 和 data。lo/hi
  划分由 LSU 地址和 DCCM bank 选择逻辑共同驱动，非对齐访问可以同时使用两个 bank。
* 第 L118-L126 行：PIC 端口只有 32-bit 数据宽度。``picm_mken`` 的注释说明 store
  需要先读 mask，以决定写哪些 bit 或进行前递。
* 第 L128-L173 行：紧随其后的 AXI 端口分成 AW、W、B、AR、R 五组通道。
  ``lsu_axi_wdata`` 是 64-bit，``lsu_axi_wstrb`` 是 8-bit。
* 第 L177-L190 行：DMA slave 端口传入 ``dma_dccm_req``、地址、size、write 和
  64-bit write data，并输出 DCCM DMA read valid、ECC error、tag、data 和 ready。

接口关系：

* 被调用：DCCM/PIC/MEM 顶层逻辑读取这些端口，AXI slave 或 bus fabric 响应 AXI 通道。
* 调用：``eh2_lsu_dccm_ctl`` 产生 DCCM/PIC 端口，``eh2_lsu_bus_intf`` 产生 AXI 端口。
* 共享状态：共享 DCCM ECC 宽度、PIC 读数据、AXI tag 和 DMA tag。

§2.3  子模块实例化边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 LSU 子模块接入顶层。源码中子模块实例均在 ``eh2_lsu.sv`` 后半段出现，
且大多数使用 ``.*`` 同名连接；这要求读者按信号名回溯同文件前面的内部信号定义。

关键代码（``rtl/design/lsu/eh2_lsu.sv:L405-L465``）：

.. code-block:: systemverilog

      if (pt.ATOMIC_ENABLE == 1) begin: GenAMO
         eh2_lsu_amo #(.pt(pt))  lsu_amo (.*);
      end
      else begin: GenNoAMO
         assign amo_data_dc3[31:0] = '0;
      end

      eh2_lsu_dccm_ctl #(.pt(pt)) dccm_ctl (
         .lsu_addr_dc1(lsu_addr_dc1[31:0]),
         .end_addr_dc1(end_addr_dc1[31:0]),
         .lsu_addr_dc3(lsu_addr_dc3[31:0]),
         .lsu_addr_dc4(lsu_addr_dc4[31:0]),
         .lsu_addr_dc5(lsu_addr_dc5[31:0]),

         .end_addr_dc2(end_addr_dc2[31:0]),
         .end_addr_dc3(end_addr_dc3[31:0]),
         .end_addr_dc4(end_addr_dc4[31:0]),
         .end_addr_dc5(end_addr_dc5[31:0]),
         .*
      );

逐段解释：

* 第 L405-L410 行：AMO 逻辑只在 ``pt.ATOMIC_ENABLE == 1`` 时实例化；关闭时
  ``amo_data_dc3`` 被置零。
* 第 L412-L424 行：``eh2_lsu_dccm_ctl`` 接收显式切片后的地址和 end address，
  其余端口通过 ``.*`` 连接。显式连接说明 DCCM 控制需要 DC1、DC3、DC4、DC5
  多级地址。
* 第 L426-L432 行：``eh2_lsu_stbuf`` 使用 ``pt.LSU_SB_BITS`` 宽度的地址切片，
  说明 store buffer 只保存 DCCM store buffer 地址所需的低位。
* 第 L434-L446 行：ECC、trigger 和 clockdomain 作为独立子模块接入。
* 第 L448-L465 行：bus interface 接收被 ``lsu_busreq_dc*`` gate 后的地址和
  store data，避免非 bus 请求把无关数据送入外部总线路径。

接口关系：

* 被调用：``eh2_lsu`` 是这些子模块的上层实例化者。
* 调用：实例化 ``eh2_lsu_amo``、``eh2_lsu_dccm_ctl``、``eh2_lsu_stbuf``、
  ``eh2_lsu_ecc``、``eh2_lsu_trigger``、``eh2_lsu_clkdomain`` 和
  ``eh2_lsu_bus_intf``。
* 共享状态：通过 ``.*`` 共享大量内部信号，包括 ``lsu_pkt_dc*``、地址、flush、
  DCCM/PIC/bus 状态和 ECC 状态。

§2.4  DMA ready、flush 和 stall
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在顶层组合逻辑中生成 DMA 接收条件、每级 flush、每线程 stall 和 idle。
这些信号是 DEC/TLU 对 LSU 进行 back-pressure 和 halt 判断的直接依据。

关键代码（``rtl/design/lsu/eh2_lsu.sv:L317-L355``）：

.. code-block:: systemverilog

      assign ldst_nodma_dc2todc5 = (lsu_pkt_dc2.valid & ~lsu_pkt_dc2.dma & (addr_in_dccm_dc2 | addr_in_pic_dc2) & lsu_pkt_dc2.store) |
                                   (lsu_pkt_dc3.valid & ~lsu_pkt_dc3.dma & (addr_in_dccm_dc3 | addr_in_pic_dc3) & lsu_pkt_dc3.store) |
                                   (lsu_pkt_dc4.valid & ~lsu_pkt_dc4.dma & (addr_in_dccm_dc4 | addr_in_pic_dc4) & lsu_pkt_dc4.store);
      assign dccm_ready = ~(picm_wren_notdma | lsu_pkt_dc1_pre.valid | ldst_nodma_dc2todc5 | ld_single_ecc_error_dc5_ff);
      assign dma_mem_tag_dc1[2:0] = dma_mem_tag[2:0];

      assign dma_pic_wen  = dma_dccm_req & dma_mem_write & ~dma_mem_addr_in_dccm;
      assign dma_dccm_wen = dma_dccm_req & dma_mem_write & dma_mem_addr_in_dccm & dma_mem_sz[1];
      assign dma_dccm_spec_wen = dma_dccm_spec_req & dma_mem_write & dma_mem_sz[1];
      assign dma_start_addr_dc1[31:0] = dma_mem_addr[31:0];
      assign dma_end_addr_dc1[31:3]   = dma_mem_addr[31:3];
      assign dma_end_addr_dc1[2:0]    = (dma_mem_sz[2:0] == 3'b11) ? 3'b100 : dma_mem_addr[2:0];
       assign {dma_dccm_wdata_hi[31:0], dma_dccm_wdata_lo[31:0]} = dma_mem_wdata[63:0] >> {dma_mem_addr[2:0], 3'b000};   // Shift the dma data to lower bits to make it consistent to lsu stores

逐段解释：

* 第 L317-L322 行：``dccm_ready`` 在 PIC 非 DMA 写、DC1 有 core packet、DC2-DC4
  有非 DMA DCCM/PIC store 或 ECC 纠正挂起时拉低。注释说明 DMA 不允许与可被 flush
  的非 DMA store 发生 in-pipe forwarding。
* 第 L325-L327 行：DMA 写按 ``dma_mem_addr_in_dccm`` 和 ``dma_mem_sz[1]``
  分成 PIC 写、DCCM 写和 DCCM speculative 写。
* 第 L328-L331 行：DMA 起始地址直接来自 ``dma_mem_addr``；结束地址在 dword
  访问时设置低 3 bit 为 ``3'b100``，并把 64-bit 写数据按地址低位右移成 lo/hi
  两个 32-bit 数据。

接口关系：

* 被调用：DMA 控制器观察 ``dccm_ready`` 和 DMA read return。
* 调用：这些组合信号被 ``eh2_lsu_lsc_ctl``、``eh2_lsu_dccm_ctl`` 和 PIC/DCCM
  写路径使用。
* 共享状态：读写 ``lsu_pkt_dc*``、``addr_in_dccm_dc*``、``addr_in_pic_dc*``、
  ``ld_single_ecc_error_dc5_ff`` 和 DMA 输入。

关键代码（``rtl/design/lsu/eh2_lsu.sv:L333-L378``）：

.. code-block:: systemverilog

      for (genvar i=0; i<pt.NUM_THREADS; i++) begin: GenFlushLoop
         assign flush_dc2_up[i] = flush_final_e3[i] | dec_tlu_flush_lower_wb[i];
         assign flush_dc3[i]    = (flush_final_e3[i] & i0_flush_final_e3[i]) | dec_tlu_flush_lower_wb[i];
         assign flush_dc4[i]    = dec_tlu_flush_lower_wb[i];
         assign flush_dc5[i]    = ((dec_tlu_i0_kill_writeb_wb & ~lsu_pkt_dc5.pipe) | (dec_tlu_i1_kill_writeb_wb & lsu_pkt_dc5.pipe)) & (lsu_pkt_dc5.tid == i);
      end

      assign lsu_fastint_stall_any = ld_single_ecc_error_dc3;

      // Dual ld-st
      assign ldst_dual_dc2          = (lsu_addr_dc2[2] != end_addr_dc2[2]);
      assign ldst_dual_dc3          = (lsu_addr_dc3[2] != end_addr_dc3[2]);
      assign ldst_dual_dc4          = (lsu_addr_dc4[2] != end_addr_dc4[2]);
      assign ldst_dual_dc5          = (lsu_addr_dc5[2] != end_addr_dc5[2]);

      for (genvar i=0; i<pt.NUM_THREADS; i++) begin: GenThreadLoop
         // block stores in decode  - for either bus or stbuf reasons
         // block for sc/amo since stores does read modify write so they are similar to load
         assign lsu_store_stall_any[i] = (lsu_pkt_dc1.valid & (lsu_pkt_dc1.sc | (lsu_pkt_dc1.atomic & lsu_pkt_dc1.store))) |
                                         (lsu_pkt_dc2.valid & (lsu_pkt_dc2.sc | (lsu_pkt_dc2.atomic & lsu_pkt_dc2.store))) |

逐段解释：

* 第 L333-L339 行：每线程生成 DC2-up、DC3、DC4 和 DC5 flush。DC5 根据
  ``lsu_pkt_dc5.pipe`` 区分 i0/i1 writeback kill。
* 第 L341 行：快速中断 stall 直接来自 DC3 load 单 bit ECC 错误。
* 第 L343-L347 行：``ldst_dual_dc*`` 只比较 address bit 2，表示访问跨越 32-bit
  word 边界并需要 hi/lo 两部分处理。
* 第 L349-L355 行：store stall 包含 DC1-DC3 中的 SC/atomic-store、store buffer
  full、bus buffer full 和 DC5 ECC 错误。

接口关系：

* 被调用：DEC 读取 ``lsu_store_stall_any``、``lsu_load_stall_any`` 和
  ``lsu_amo_stall_any`` 进行发射阻塞。
* 调用：flush 信号送入 ``eh2_lsu_lsc_ctl`` 和 ``eh2_lsu_bus_intf``。
* 共享状态：按线程读取 ``lsu_pkt_dc*``、store buffer 状态、bus buffer 状态和
  ECC 错误状态。

§2.5  store data、store buffer 请求和 bus 请求
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在顶层汇总 store data bypass、DCCM store buffer 入队条件和外部 bus 请求条件。
这些信号决定一次 LSU 操作走 DCCM store buffer、PIC、还是外部 bus。

关键代码（``rtl/design/lsu/eh2_lsu.sv:L383-L397``）：

.. code-block:: systemverilog

      assign store_data_dc3[31:0] = (picm_mask_data_dc3[31:0] | {32{~addr_in_pic_dc3}}) &
                                    ((lsu_pkt_dc3.store_data_bypass_e4_c3[1]) ? i1_result_e4_eff[31:0] :
                                     (lsu_pkt_dc3.store_data_bypass_e4_c3[0]) ? i0_result_e4_eff[31:0] : store_data_pre_dc3[31:0]);

      // Instantiate the store buffer
      assign store_stbuf_reqvld_dc5 = lsu_pkt_dc5.valid & (~lsu_pkt_dc5.sc | lsu_sc_success_dc5 | (lsu_single_ecc_error_dc5 & ~lsu_raw_fwd_lo_dc5)) & addr_in_dccm_dc5 &
                                      (((lsu_pkt_dc5.store | (lsu_pkt_dc5.atomic & ~lsu_pkt_dc5.lr)) & lsu_commit_dc5) |
                                       (lsu_pkt_dc5.dma & lsu_pkt_dc5.store & (lsu_pkt_dc5.by | lsu_pkt_dc5.half) & ~lsu_double_ecc_error_dc5));

      // Disable Forwarding for now
      assign lsu_cmpen_dc2 = lsu_pkt_dc2.valid & (lsu_pkt_dc2.load | lsu_pkt_dc2.store | lsu_pkt_dc1.atomic) & (addr_in_dccm_dc2 | addr_in_pic_dc2);

      // Bus signals
      assign lsu_busreq_dc1 = lsu_pkt_dc1_pre.valid & ((lsu_pkt_dc1_pre.load | lsu_pkt_dc1_pre.store) & addr_external_dc1) & ~flush_dc2_up[lsu_pkt_dc1_pre.tid] & ~lsu_pkt_dc1_pre.fast_int;

逐段解释：

* 第 L383-L385 行：store data 先经过 PIC mask 约束，再从 i1 E4、i0 E4 或
  ``store_data_pre_dc3`` 中选择。选择优先级由 ``store_data_bypass_e4_c3`` 两个 bit
  决定。
* 第 L388-L390 行：DCCM store buffer 入队需要 DC5 packet valid、目标在 DCCM、
  SC 未启用或 SC 成功，或特定 ECC 修复场景。DMA byte/half store 也可以进入该路径。
* 第 L393 行：``lsu_cmpen_dc2`` 在 DC2 对 DCCM/PIC load、store 或 atomic 使能比较，
  供 store buffer 和 PIC forwarding 使用。
* 第 L396 行：外部 bus 请求只来自 valid 的 load/store、目标为 external、未被
  ``flush_dc2_up`` flush，且不是 fast interrupt。

接口关系：

* 被调用：``eh2_lsu_stbuf`` 使用 ``store_stbuf_reqvld_dc5`` 和 ``lsu_cmpen_dc2``；
  ``eh2_lsu_bus_intf`` 使用 ``lsu_busreq_dc1``。
* 调用：组合逻辑读取 ``lsu_pkt_dc*``、地址区域标记、PIC mask 和 EXU bypass 结果。
* 共享状态：共享 DC2/DC3/DC5 packet、PIC mask、ECC raw forwarding 和 flush 状态。

§3  ``eh2_lsu_lsc_ctl.sv`` 核心控制
------------------------------------

``eh2_lsu_lsc_ctl`` 是 LSU 的地址生成和管线控制中心。它接收 DEC 操作数、EXU
bypass 结果、DMA 请求、flush、DCCM/PIC/bus 返回数据，并输出 DC1-DC5 地址、
packet、异常包、load 结果、LR/SC 状态和区域标记。

§3.1  rs1 bypass、地址生成和 addrcheck 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 DC1 计算 start/end address，并把 core 地址送入 ``eh2_lsu_addrcheck``。
当 ``pt.LOAD_TO_USE_PLUS1`` 打开时，rs1 可以从前一条 load 的 DC3 结果旁路。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L203-L246``）：

.. code-block:: systemverilog

      if (pt.LOAD_TO_USE_PLUS1 == 1) begin: GenL2U_1
         assign lsu_rs1_d[31:0] = lsu_pkt_dc1_in.load_ldst_bypass_c1 ? lsu_result_dc3[31:0] :  exu_lsu_rs1_d[31:0];
         assign rs1_dc1[31:0]   = rs1_dc1_raw[31:0];
      end else begin: GenL2U_0
         assign lsu_rs1_d[31:0] = exu_lsu_rs1_d[31:0];
         assign rs1_dc1[31:0]   = (lsu_pkt_dc1_pre.load_ldst_bypass_c1) ? lsu_result_dc3[31:0] : rs1_dc1_raw[31:0];
      end

      assign lsu_rs1_dc1[31:0] = rs1_dc1[31:0];

      // Premux the rs1/offset for dma
      assign lsu_offset_dc1[11:0] = offset_dc1[11:0] & ~{12{lsu_pkt_dc1_pre.atomic}};

      rvdff #(32) rs1ff    (.*, .din(lsu_rs1_d[31:0]),    .dout(rs1_dc1_raw[31:0]), .clk(lsu_c1_dc1_clk));
      rvdff #(12) offsetff (.*, .din(dec_lsu_offset_d[11:0]), .dout(offset_dc1[11:0]),  .clk(lsu_c1_dc1_clk));

       assign offset32_dc1[31:0] =  { {20{lsu_offset_dc1[11]}},lsu_offset_dc1[11:0]};

      assign core_start_addr_dc1[31:0] =  rs1_dc1[31:0] + offset32_dc1[31:0];
      assign core_end_addr_dc1[31:0]   = rs1_dc1[31:0] + {{19{end_addr_offset_dc1[12]}},end_addr_offset_dc1[12:0]};

逐段解释：

* 第 L203-L209 行：``LOAD_TO_USE_PLUS1`` 改变 rs1 bypass 的取样点。打开时，
  ``lsu_pkt_dc1_in.load_ldst_bypass_c1`` 可以在进入 DC1 前选择 ``lsu_result_dc3``；
  关闭时，选择发生在 ``rs1_dc1``。
* 第 L213-L217 行：atomic packet 将 offset 清零；rs1 和 offset 被寄存到 DC1。
* 第 L219-L222 行：offset 被符号扩展为 32-bit；start address 是
  ``rs1 + offset``，end address 是 ``rs1 + end_addr_offset``。

接口关系：

* 被调用：``eh2_lsu`` 实例化该模块。
* 调用：本节组合逻辑驱动 ``eh2_lsu_addrcheck`` 的 start/end address。
* 共享状态：读取 ``lsu_pkt_dc1_in``、``lsu_pkt_dc1_pre``、``lsu_result_dc3``、
  ``exu_lsu_rs1_d`` 和 ``dec_lsu_offset_d``。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L225-L247``）：

.. code-block:: systemverilog

      // Module to generate the memory map of the address
      eh2_lsu_addrcheck #(.pt(pt)) addrcheck (
                     .start_addr_dc1(core_start_addr_dc1[31:0]),
                     .end_addr_dc1(core_end_addr_dc1[31:0]),
                     .start_addr_dc2(lsu_addr_dc2[31:0]),
                     .end_addr_dc2(end_addr_dc2[31:0]),
                     .addr_in_dccm_dc1(core_addr_in_dccm_dc1),
                     .addr_in_pic_dc1(core_addr_in_pic_dc1),
                     .addr_external_dc1(core_addr_external_dc1),
                     .*
     );

      // Calculate start/end address for load/store
      assign addr_offset_dc1[2:0]      = ({3{lsu_pkt_dc1_pre.half}} & 3'b01) | ({3{lsu_pkt_dc1_pre.word}} & 3'b11) | ({3{lsu_pkt_dc1_pre.dword}} & 3'b111);
      assign end_addr_offset_dc1[12:0] = {lsu_offset_dc1[11],lsu_offset_dc1[11:0]} + {9'b0,addr_offset_dc1[2:0]};
      assign end_addr_dc1[31:0]        = lsu_pkt_dc1_pre.valid ? core_end_addr_dc1[31:0] : dma_end_addr_dc1[31:0];
      assign lsu_addr_dc1[31:0]        = lsu_pkt_dc1_pre.valid ? core_start_addr_dc1[31:0] : dma_start_addr_dc1[31:0];   // absence load/store all 0's

逐段解释：

* 第 L225-L235 行：``addrcheck`` 接收 core start/end address，同时也接收 DC2
  的 ``lsu_addr_dc2`` 和 ``end_addr_dc2``。DC1 输出使用局部信号名
  ``core_addr_in_*``，再由本模块转换为 LSU 对外区域标记。
* 第 L237-L239 行：访问大小转换为 end offset：half 为 1、word 为 3、dword 为 7。
* 第 L240-L241 行：DC1 地址在 core packet valid 时来自 core AGU；否则来自 DMA 地址。
  这说明同一套下游 DCCM/PIC 逻辑也服务 DMA。
* 第 L243-L247 行：DCCM/PIC 区域在 core 与 DMA 之间做选择；external 地址只对
  core packet 有效。

接口关系：

* 被调用：``addrcheck`` 输出区域和 fault 信号供本模块后续寄存。
* 调用：实例化 ``eh2_lsu_addrcheck``。
* 共享状态：共享 ``dma_start_addr_dc1``、``dma_end_addr_dc1``、
  ``dma_mem_addr_in_dccm`` 和 core AGU 地址。

§3.2  异常包、DMA packet 和 packet valid
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 DC2/DC3 的 fault 和 ECC 状态组织成 ``lsu_error_pkt_dc3``，并把 DMA
请求转换成内部 ``eh2_lsu_pkt_t``，再按 flush 规则推进 DC1-DC5 packet。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L249-L287``）：

.. code-block:: systemverilog

      // Goes to TLU to increment the ECC error counter
      assign lsu_single_ecc_error_incr = (lsu_single_ecc_error_dc5 & ~lsu_double_ecc_error_dc5) & (lsu_commit_dc5 | lsu_pkt_dc5.dma) & lsu_pkt_dc5.valid;

      // Generate exception packet
      assign lsu_error_pkt_dc3.exc_valid = (access_fault_dc3 | misaligned_fault_dc3 | lsu_double_ecc_error_dc3) & lsu_pkt_dc3.valid & ~lsu_pkt_dc3.dma & ~flush_dc3[lsu_pkt_dc3.tid] & ~lsu_pkt_dc3.fast_int;
      assign lsu_error_pkt_dc3.single_ecc_error = lsu_single_ecc_error_dc3 & ~lsu_error_pkt_dc3.exc_valid & ~lsu_pkt_dc3.dma & ~lsu_pkt_dc3.fast_int;   // This is used for rfnpc. Suppress single bit error if there is a fault/dma/fastint
      assign lsu_error_pkt_dc3.inst_type = lsu_pkt_dc3.store;   // AMO should be store
      assign lsu_error_pkt_dc3.amo_valid = lsu_pkt_dc3.atomic & ~(lsu_pkt_dc3.lr | lsu_pkt_dc3.sc);
      assign lsu_error_pkt_dc3.exc_type  = ~misaligned_fault_dc3;
      assign lsu_error_pkt_dc3.mscause[3:0] = (lsu_double_ecc_error_dc3 & ~misaligned_fault_dc3 & ~access_fault_dc3) ? 4'h1 : exc_mscause_dc3[3:0];
      assign lsu_error_pkt_dc3.addr[31:0] = lsu_addr_dc3[31:0] & {32{lsu_error_pkt_dc3.exc_valid | lsu_error_pkt_dc3.single_ecc_error}};

逐段解释：

* 第 L249-L250 行：单 bit ECC 计数只在 DC5 单 ECC 且非双 ECC、packet valid、
  并且 core commit 或 DMA packet 时递增。
* 第 L253 行：异常 valid 覆盖 access fault、misaligned fault 和 double ECC；
  DMA、flush 后 packet 和 fast interrupt 都被抑制。
* 第 L254 行：single ECC 不作为 ``exc_valid``，而是单独设置
  ``single_ecc_error``，且在已有 fault、DMA 或 fast interrupt 时抑制。
* 第 L255-L259 行：异常包记录 store/AMO 类型、exception type、mscause 和地址。
  double ECC 在无 misaligned/access fault 时把 mscause 设为 ``4'h1``。

接口关系：

* 被调用：TLU 读取 ``lsu_error_pkt_dc3`` 和 ``lsu_single_ecc_error_incr``。
* 调用：本节不实例化子模块，只组合异常包。
* 共享状态：读取 DC3 fault、ECC、packet、flush 和地址。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L261-L287``）：

.. code-block:: systemverilog

      //Create DMA packet
      always_comb begin
         dma_pkt_dc1 = '0;
         dma_pkt_dc1.valid   = dma_dccm_req;
         dma_pkt_dc1.dma     = 1'b1;
         dma_pkt_dc1.store   = dma_mem_write;
         dma_pkt_dc1.load    = ~dma_mem_write;
         dma_pkt_dc1.by      = (dma_mem_sz[2:0] == 3'b0);
         dma_pkt_dc1.half    = (dma_mem_sz[2:0] == 3'b1);
         dma_pkt_dc1.word    = (dma_mem_sz[2:0] == 3'b10);
         dma_pkt_dc1.dword   = (dma_mem_sz[2:0] == 3'b11);
      end

      always_comb begin
         lsu_pkt_dc1_in = lsu_p;
         lsu_pkt_dc1    = dma_dccm_req ? dma_pkt_dc1 : lsu_pkt_dc1_pre;
         lsu_pkt_dc2_in = lsu_pkt_dc1;

逐段解释：

* 第 L261-L272 行：DMA packet 从零值开始填充，固定 ``dma=1``，根据
  ``dma_mem_write`` 生成 store/load，并把 ``dma_mem_sz`` 解码为 by/half/word/dword。
* 第 L274-L280 行：core ``lsu_p`` 进入 ``lsu_pkt_dc1_in``；DC1 对外 packet 在
  DMA 请求有效时选择 ``dma_pkt_dc1``，否则选择已寄存的 ``lsu_pkt_dc1_pre``。
* 第 L282-L286 行：各级 valid 被不同 flush 信号 gate。DMA packet 在 DC2 valid
  生成中被 OR 进来，后续级别在 ``~lsu_pkt_dc*.dma`` 条件下避免被 core flush 清掉。

接口关系：

* 被调用：下游 DCCM、PIC、stbuf 和 bus 逻辑读取 ``lsu_pkt_dc1`` 到
  ``lsu_pkt_dc5``。
* 调用：本节不调用外部模块。
* 共享状态：读取 ``lsu_p``、DMA 请求、DMA size、flush 和前级 packet。

§3.3  load 结果选择和 store data 管线
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 DCCM、PIC 和 bus 三类 read data 合成 ``lsu_result_dc3``，并按
byte/half/word 与 signed/unsigned 控制做扩展；同时把 store data bypass 结果推进到
DC3。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L289-L328``）：

.. code-block:: systemverilog

      assign lsu_ld_datafn_dc3[31:0] = ({32{addr_external_dc3}} & bus_read_data_dc3) |
                                       ({32{addr_in_pic_dc3}}   & picm_rd_data_dc3)  |
                                       ({32{addr_in_dccm_dc3}}  & lsu_dccm_data_dc3);

      assign lsu_ld_datafn_corr_dc3[31:0] = ({32{addr_external_dc3}} & bus_read_data_dc3) |
                                            ({32{addr_in_pic_dc3}}   & picm_rd_data_dc3)  |
                                            ({32{addr_in_dccm_dc3}}  & lsu_dccm_data_corr_dc3);

      // this result must look at prior stores and merge them in. Qualified with valid for power
      assign lsu_result_dc3[31:0] = ({32{lsu_pkt_dc3.valid & lsu_pkt_dc3.load &  lsu_pkt_dc3.unsign & lsu_pkt_dc3.by  }} & {24'b0,lsu_ld_datafn_dc3[7:0]}) |
                                    ({32{lsu_pkt_dc3.valid & lsu_pkt_dc3.load &  lsu_pkt_dc3.unsign & lsu_pkt_dc3.half}} & {16'b0,lsu_ld_datafn_dc3[15:0]}) |
                                    ({32{lsu_pkt_dc3.valid & lsu_pkt_dc3.load & ~lsu_pkt_dc3.unsign & lsu_pkt_dc3.by  }} & {{24{  lsu_ld_datafn_dc3[7]}}, lsu_ld_datafn_dc3[7:0]}) |
                                    ({32{lsu_pkt_dc3.valid & lsu_pkt_dc3.load & ~lsu_pkt_dc3.unsign & lsu_pkt_dc3.half}} & {{16{  lsu_ld_datafn_dc3[15]}},lsu_ld_datafn_dc3[15:0]}) |
                                    ({32{lsu_pkt_dc3.valid & lsu_pkt_dc3.load & lsu_pkt_dc3.word}} &                       lsu_ld_datafn_dc3[31:0]);

逐段解释：

* 第 L289-L295 行：普通数据和 ECC 纠正数据各有一个 mux。external 选择
  ``bus_read_data_dc3``，PIC 选择 ``picm_rd_data_dc3``，DCCM 分别选择原始数据或
  ``lsu_dccm_data_corr_dc3``。
* 第 L297-L302 行：``lsu_result_dc3`` 只在 valid load 时有效，按照
  unsigned byte、unsigned half、signed byte、signed half 和 word 五种情况组合。
* 第 L304-L308 行：``lsu_result_corr_dc3`` 使用纠正后的 DCCM 数据，并保留同样的
  扩展规则，用于 DC4 写回路径。

接口关系：

* 被调用：DEC/GPR 写回路径读取 ``lsu_result_dc3`` 和 ``lsu_result_corr_dc4``。
* 调用：读取 ``eh2_lsu_dccm_ctl``、PIC 和 bus interface 的数据输出。
* 共享状态：共享 ``addr_external_dc3``、``addr_in_pic_dc3``、``addr_in_dccm_dc3``
  和 ``lsu_pkt_dc3``。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L313-L328``）：

.. code-block:: systemverilog

      // Interrupt as a flush source allows the WB to occur
      assign lsu_commit_dc5 = lsu_pkt_dc5.valid & (lsu_pkt_dc5.store | lsu_pkt_dc5.load | lsu_pkt_dc5.atomic) & ~flush_dc5[lsu_pkt_dc5.tid] & ~lsu_pkt_dc5.dma;

      assign store_data_d[31:0] = exu_lsu_rs2_d[31:0];

      //assign store_data_dc2_in[63:32] = store_data_dc1[63:32];
      assign store_data_dc2_in[31:0] = dma_dccm_req ? dma_dccm_wdata_lo[31:0] :                      // PIC writes from DMA still happens in dc5 since we need to read mask
                                       (lsu_pkt_dc1.store_data_bypass_c1) ? lsu_result_dc3[31:0] :
                                       (lsu_pkt_dc1.store_data_bypass_e4_c1[1]) ? i1_result_e4_eff[31:0] :
                                       (lsu_pkt_dc1.store_data_bypass_e4_c1[0]) ? i0_result_e4_eff[31:0] : store_data_dc1[31:0];

      //assign store_data_dc2[63:32] = store_data_pre_dc2[63:32];
      assign store_data_dc2[31:0] = (lsu_pkt_dc2.store_data_bypass_i0_e2_c2) ? i0_result_e2[31:0]     :
                                    (lsu_pkt_dc2.store_data_bypass_c2)       ? lsu_result_dc3[31:0]   :
                                    (lsu_pkt_dc2.store_data_bypass_e4_c2[1]) ? i1_result_e4_eff[31:0] :
                                    (lsu_pkt_dc2.store_data_bypass_e4_c2[0]) ? i0_result_e4_eff[31:0] : store_data_pre_dc2[31:0];

逐段解释：

* 第 L313-L314 行：``lsu_commit_dc5`` 要求 DC5 packet valid、类型是 load/store/atomic、
  未被 ``flush_dc5`` kill，且不是 DMA。
* 第 L316 行：原始 store data 来自 ``exu_lsu_rs2_d``。
* 第 L319-L322 行：DC2 输入 store data 优先选择 DMA write data，再选择 DC1 的
  load result bypass、E4 i1、E4 i0，最后使用 DC1 寄存值。
* 第 L325-L328 行：DC2 阶段还可以选择 E2 i0、load result、E4 i1、E4 i0 或
  ``store_data_pre_dc2``。

接口关系：

* 被调用：``eh2_lsu`` 后续 store data 逻辑和 DCCM/PIC/bus 写路径读取
  ``store_data_pre_dc3``。
* 调用：读取 EXU E2/E4 结果和 DC3 load result。
* 共享状态：共享 ``lsu_pkt_dc1``、``lsu_pkt_dc2``、DMA 写数据和 store data flops。

§3.4  管线寄存器和 LR/SC 预约
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 packet、store data、地址、区域标记、fault、ECC 和 fast interrupt 信息推进
到后续流水级，并在 atomic 打开时维护 per-thread LR station。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L331-L385``）：

.. code-block:: systemverilog

      // Flops
      rvdffe #(32) lsu_result_corr_dc4ff (.*, .din(lsu_result_corr_dc3[31:0]), .dout(lsu_result_corr_dc4[31:0]), .en((lsu_pkt_dc3.valid & lsu_pkt_dc3.load) | clk_override));

      // C2 clock for valid and C1 for other bits of packet
      rvdff #(1) lsu_pkt_vlddc1ff (.*, .din(lsu_pkt_dc1_in.valid), .dout(lsu_pkt_dc1_pre.valid), .clk(lsu_c2_dc1_clk));
      rvdff #(1) lsu_pkt_vlddc2ff (.*, .din(lsu_pkt_dc2_in.valid), .dout(lsu_pkt_dc2.valid), .clk(lsu_c2_dc2_clk));
      rvdff #(1) lsu_pkt_vlddc3ff (.*, .din(lsu_pkt_dc3_in.valid), .dout(lsu_pkt_dc3.valid), .clk(lsu_c2_dc3_clk));
      rvdff #(1) lsu_pkt_vlddc4ff (.*, .din(lsu_pkt_dc4_in.valid), .dout(lsu_pkt_dc4.valid), .clk(lsu_c2_dc4_clk));
      rvdff #(1) lsu_pkt_vlddc5ff (.*, .din(lsu_pkt_dc5_in.valid), .dout(lsu_pkt_dc5.valid), .clk(lsu_c2_dc5_clk));

      rvdfflie #(.WIDTH($bits(eh2_lsu_pkt_t)-1),.LEFT(12)) lsu_pkt_dc1ff (.*, .din(lsu_pkt_dc1_in[$bits(eh2_lsu_pkt_t)-1:1]), .dout(lsu_pkt_dc1_pre[$bits(eh2_lsu_pkt_t)-1:1]), .en(lsu_c1_dc1_clken));
      rvdfflie #(.WIDTH($bits(eh2_lsu_pkt_t)-1),.LEFT(12)) lsu_pkt_dc2ff (.*, .din(lsu_pkt_dc2_in[$bits(eh2_lsu_pkt_t)-1:1]), .dout(lsu_pkt_dc2[$bits(eh2_lsu_pkt_t)-1:1]),     .en(lsu_c1_dc2_clken));

逐段解释：

* 第 L331-L332 行：纠正后的 load result 从 DC3 寄存到 DC4，只在 valid load 或
  ``clk_override`` 时更新。
* 第 L334-L339 行：packet valid 使用 C2 clock 单独推进，源码注释说明 valid 与
  packet 其它 bit 使用不同 clock。
* 第 L341-L345 行：packet 除 valid 外的字段用 ``rvdfflie`` 和 C1 clock enable
  推进。``LEFT(12)`` 是实例参数，本文不从该数字推断字段语义。
* 第 L347-L385 行：store data、地址、end address、区域标记、external 标记、
  fault 和 ``exc_mscause`` 均通过对应 DC clock 推进。

接口关系：

* 被调用：所有下游子模块读取这些流水级信号。
* 调用：寄存器原语 ``rvdff``、``rvdffe``、``rvdfflie``。
* 共享状态：共享 C1/C2 时钟、packet、地址、fault、ECC 和区域标记。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L396-L429``）：

.. code-block:: systemverilog

      // Load Reservation
      // when the LR commits - it will set a valid and its address [31:2] for its own thread's LR
      // the Reset conditions are :
      // Same Thread : 1) Any Store Conditional - match or not is not relevant
      //               2) Entering Debug,
      //               3) Leaving Debug,
      //               4) Mret, Interrup or Exception
      //
      // Other Thread :1) Store or AMO to this location ( 31:2 match )
      if (pt.ATOMIC_ENABLE == 1) begin: GenAtomic
         logic [THREADS-1:0] [31:2] lr_addr;   // Per Thread LR stations
         logic [THREADS-1:0]        lr_wr_en;   // set and reset logic
         logic                      tid_dc5;
         logic [THREADS-1:0]        lsu_sc_success_vec_dc5;

逐段解释：

* 第 L396-L404 行：源码注释列出 LR station 的 set/reset 条件。LR commit 设置
  本线程预约地址，同线程 SC 和 TLU reset 清除，跨线程 store/AMO 命中同地址也清除。
* 第 L405-L410 行：atomic 逻辑只在 ``pt.ATOMIC_ENABLE == 1`` 时生成；每线程
  保存 ``lr_addr`` 和 ``lr_vld``。
* 第 L412-L419 行：SC 成功向量要求线程匹配、``lsu_addr_dc5[31:2]`` 等于该线程
  ``lr_addr``、packet valid、packet 是 SC 且 ``lr_vld`` 为 1。
* 第 L421-L429 行：LR commit 写入 ``lr_addr``；``lr_reset`` 覆盖同线程 SC、
  跨线程 store 命中、TLU reset 和 DMA store 命中。

接口关系：

* 被调用：顶层输出 ``lsu_sc_success_dc5``，store buffer 入队条件也读取该信号。
* 调用：``rvdffsc`` 保存 ``lr_vld``，``rvdffe`` 保存 ``lr_addr``。
* 共享状态：读写 per-thread ``lr_vld``、``lr_addr``，读取 ``dec_tlu_lr_reset_wb``、
  DC5 packet、地址和 DMA store 状态。

§4  ``eh2_lsu_addrcheck.sv`` 地址检查器
----------------------------------------

``eh2_lsu_addrcheck`` 在 DC1/DC2 判断地址属于 DCCM、PIC、ICCM 还是外部空间，并生成
access fault、misaligned fault、mscause 和 fast interrupt 地址错误。源码中的故障类型
只来自组合逻辑，不引用外部表格。

§4.1  DCCM、PIC、ICCM 和 external 区域判断
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 ``rvrangecheck`` 检查 start/end 地址是否在 DCCM/PIC 范围，并用 region
高位和 MRAC CSR 生成 external 与 side-effect 属性。

关键代码（``rtl/design/lsu/eh2_lsu_addrcheck.sv:L87-L153``）：

.. code-block:: systemverilog

      if (pt.DCCM_ENABLE == 1) begin: Gen_dccm_enable
         // Start address check
         rvrangecheck #(.CCM_SADR(pt.DCCM_SADR),
                        .CCM_SIZE(pt.DCCM_SIZE)) start_addr_dccm_rangecheck (
            .addr(start_addr_dc1[31:0]),
            .in_range(start_addr_in_dccm_dc1),
            .in_region(start_addr_in_dccm_region_dc1)
         );

         // End address check
         rvrangecheck #(.CCM_SADR(pt.DCCM_SADR),
                        .CCM_SIZE(pt.DCCM_SIZE)) end_addr_dccm_rangecheck (
            .addr(end_addr_dc1[31:0]),
            .in_range(end_addr_in_dccm_dc1),
            .in_region(end_addr_in_dccm_region_dc1)
         );
      end else begin: Gen_dccm_disable // block: Gen_dccm_enable

逐段解释：

* 第 L87-L102 行：当 ``pt.DCCM_ENABLE == 1`` 时，start 和 end 地址分别用
  ``rvrangecheck`` 检查 DCCM range 和 region。
* 第 L103-L108 行：DCCM 关闭时，start/end 的 DCCM range 和 region 命中全部置零。
* 第 L110-L116 行：ICCM 检查只比较 ``start_addr_dc2[31:28]`` 与
  ``pt.ICCM_REGION``，未启用 ICCM 时置零。
* 第 L118-L133 行：PIC start/end 地址同样通过 ``rvrangecheck`` 检查。

接口关系：

* 被调用：``eh2_lsu_lsc_ctl`` 实例化该模块。
* 调用：实例化两个 DCCM ``rvrangecheck`` 和两个 PIC ``rvrangecheck``。
* 共享状态：读取 ``pt.DCCM_*``、``pt.PIC_*``、``pt.ICCM_*`` 和 start/end 地址。

关键代码（``rtl/design/lsu/eh2_lsu_addrcheck.sv:L135-L153``）：

.. code-block:: systemverilog

      assign rs1_region_dc1[3:0] = rs1_dc1[31:28];
      assign start_addr_dccm_or_pic_dc2  = start_addr_in_dccm_region_dc2 | start_addr_in_pic_region_dc2;
      assign base_reg_dccm_or_pic_dc1    = ((rs1_region_dc1[3:0] == pt.DCCM_REGION) & pt.DCCM_ENABLE) | (rs1_region_dc1[3:0] == pt.PIC_REGION);

      assign addr_in_dccm_region_dc1 = (rs1_region_dc1[3:0] == pt.DCCM_REGION) & pt.DCCM_ENABLE;  // We don't need to look at final address since lsu will take an exception if final region is different
      assign addr_in_pic_region_dc1  = (rs1_region_dc1[3:0] == pt.PIC_REGION);   // We don't need to look at final address since lsu will take an exception if final region is different
      assign addr_in_dccm_dc1        = (start_addr_in_dccm_dc1 & end_addr_in_dccm_dc1);
      assign addr_in_pic_dc1         = (start_addr_in_pic_dc1 & end_addr_in_pic_dc1);

      assign addr_in_dccm_dc2        = (start_addr_in_dccm_dc2 & end_addr_in_dccm_dc2);
      assign addr_in_pic_dc2         = (start_addr_in_pic_dc2 & end_addr_in_pic_dc2);

      assign addr_external_dc1  = ~(addr_in_dccm_region_dc1 | addr_in_pic_region_dc1);  // look at the region based on rs1_dc1 for timing since this goes to busreq -> nbload_dc1 -> instbuf

逐段解释：

* 第 L135-L140 行：DC1 的区域预测基于 ``rs1_dc1[31:28]``，源码注释说明这样做是
  出于到 busreq 和 NB-load 的 timing。
* 第 L141-L145 行：DCCM/PIC 真正命中要求 start 和 end 同时在对应 range 内。
* 第 L147-L150 行：external DC1/DC2 是 DCCM/PIC region 的反相；side-effect
  从 ``dec_tlu_mrac_ff`` 的 per-region bit 读取，并排除 DCCM/PIC/ICCM 内部区域。
* 第 L151-L153 行：alignment 只按 word/half/by 三种大小检查。

接口关系：

* 被调用：``addr_external_dc1`` 直接参与 ``lsu_busreq_dc1``；``is_sideeffects_dc2``
  进入 bus interface。
* 调用：本节不实例化模块。
* 共享状态：读取 ``rs1_dc1``、DC1/DC2 地址命中、``dec_tlu_mrac_ff`` 和
  ``lsu_pkt_dc2``。

§4.2  DATA_ACCESS、access fault 和 misaligned fault
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 DATA_ACCESS 参数、DCCM/PIC range、region prediction、PIC 对齐和 AMO
约束生成 access fault，并对 region cross 与 side-effect 非对齐生成 misaligned fault。

关键代码（``rtl/design/lsu/eh2_lsu_addrcheck.sv:L155-L183``）：

.. code-block:: systemverilog

      assign non_dccm_access_ok = (~(|{pt.DATA_ACCESS_ENABLE0,pt.DATA_ACCESS_ENABLE1,pt.DATA_ACCESS_ENABLE2,pt.DATA_ACCESS_ENABLE3,pt.DATA_ACCESS_ENABLE4,pt.DATA_ACCESS_ENABLE5,pt.DATA_ACCESS_ENABLE6,pt.DATA_ACCESS_ENABLE7})) |
                                  (((pt.DATA_ACCESS_ENABLE0 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK0)) == (pt.DATA_ACCESS_ADDR0 | pt.DATA_ACCESS_MASK0)) |
                                    (pt.DATA_ACCESS_ENABLE1 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK1)) == (pt.DATA_ACCESS_ADDR1 | pt.DATA_ACCESS_MASK1)) |
                                    (pt.DATA_ACCESS_ENABLE2 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK2)) == (pt.DATA_ACCESS_ADDR2 | pt.DATA_ACCESS_MASK2)) |
                                    (pt.DATA_ACCESS_ENABLE3 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK3)) == (pt.DATA_ACCESS_ADDR3 | pt.DATA_ACCESS_MASK3)) |
                                    (pt.DATA_ACCESS_ENABLE4 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK4)) == (pt.DATA_ACCESS_ADDR4 | pt.DATA_ACCESS_MASK4)) |
                                    (pt.DATA_ACCESS_ENABLE5 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK5)) == (pt.DATA_ACCESS_ADDR5 | pt.DATA_ACCESS_MASK5)) |
                                    (pt.DATA_ACCESS_ENABLE6 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK6)) == (pt.DATA_ACCESS_ADDR6 | pt.DATA_ACCESS_MASK6)) |
                                    (pt.DATA_ACCESS_ENABLE7 & ((start_addr_dc2[31:0] | pt.DATA_ACCESS_MASK7)) == (pt.DATA_ACCESS_ADDR7 | pt.DATA_ACCESS_MASK7)))   &
                                   ((pt.DATA_ACCESS_ENABLE0 & ((end_addr_dc2[31:0]   | pt.DATA_ACCESS_MASK0)) == (pt.DATA_ACCESS_ADDR0 | pt.DATA_ACCESS_MASK0)) |
                                    (pt.DATA_ACCESS_ENABLE1 & ((end_addr_dc2[31:0]   | pt.DATA_ACCESS_MASK1)) == (pt.DATA_ACCESS_ADDR1 | pt.DATA_ACCESS_MASK1)) |

逐段解释：

* 第 L155 行：如果 8 个 ``DATA_ACCESS_ENABLE`` 全部为 0，则非 DCCM 访问直接允许。
* 第 L156-L163 行：start address 需要匹配任一启用的 DATA_ACCESS 地址/掩码窗口。
* 第 L164-L171 行：end address 也需要匹配任一启用窗口；start 和 end 条件以
  ``&`` 组合，表示跨窗口访问不会被认为是 ``non_dccm_access_ok``。

接口关系：

* 被调用：``mpu_access_fault_dc2`` 读取 ``non_dccm_access_ok``。
* 调用：本节只使用组合表达式。
* 共享状态：读取 ``pt.DATA_ACCESS_ENABLE*``、``pt.DATA_ACCESS_MASK*``、
  ``pt.DATA_ACCESS_ADDR*`` 和 DC2 start/end 地址。

关键代码（``rtl/design/lsu/eh2_lsu_addrcheck.sv:L173-L211``）：

.. code-block:: systemverilog

      // Access fault logic
      // 0. Unmapped local memory fault: Addr in dccm region but not in dccm offset OR Addr in picm region but not in picm offset OR DCCM -> PIC cross when DCCM/PIC in same region
      // 1. Uncorrectable (double bit) ECC error
      // 3. MPU access fault: Address is not in a populated non-dccm region
      // 5. Region prediction access fault: Base Address in DCCM/PIC and Final address in non-DCCM/non-PIC region or vice versa
      // 6. Ld/St access to picm are not word aligned or word size

      assign regpred_access_fault_dc2  = (start_addr_dccm_or_pic_dc2 ^ base_reg_dccm_or_pic_dc2);                            // 5. Region prediction access fault: Base Address in DCCM/PIC and Final address in non-DCCM/non-PIC region or vice versa
      assign picm_access_fault_dc2     = (addr_in_pic_dc2 & ((start_addr_dc2[1:0] != 2'b0) | ~lsu_pkt_dc2.word));    // 6. Ld/St access to picm are not word aligned or word size
      assign amo_access_fault_dc2      =  (lsu_pkt_dc2.atomic & (start_addr_dc2[1:0] != 2'b0))                     | // 7. AMO are not word aligned OR AMO address not in dccm region
                                          (lsu_pkt_dc2.valid & lsu_pkt_dc2.atomic & ~addr_in_dccm_dc2);

逐段解释：

* 第 L173-L179 行：源码注释列出 access fault 分类。本文只按该注释和紧随其后的逻辑解释。
* 第 L180 行：region prediction fault 来自 DC2 实际 start region 与 DC1 base
  register region 预测的 XOR。
* 第 L181 行：PIC 访问必须 word 对齐且 packet 为 word，否则进入 PIC access fault。
* 第 L182-L183 行：AMO 非 word 对齐，或 valid atomic 但不在 DCCM，会进入 AMO
  access fault。
* 第 L185-L197 行：当 DCCM 与 PIC region 相同和不同时，unmapped 与 MPU fault 的
  判定分支不同。
* 第 L199-L211 行：access fault 只对 valid 且非 DMA packet 有效；misaligned fault
  来自 region cross 或 external side-effect 非对齐，且 atomic 不走 misaligned 分支。

接口关系：

* 被调用：``eh2_lsu_lsc_ctl`` 寄存 ``access_fault_dc2``、``misaligned_fault_dc2``
  和 ``exc_mscause_dc2`` 到 DC3。
* 调用：本节不实例化模块。
* 共享状态：读取 DC2 地址、区域、packet、DCCM/PIC 配置和 DATA_ACCESS 检查结果。

§4.3  fast interrupt 错误和 DC2/DC3 寄存
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 fast interrupt 访问单独生成 DCCM 地址错误，并把 DC1 的 range/region
检查结果推进到 DC2，把 side-effect 属性推进到 DC3。

关键代码（``rtl/design/lsu/eh2_lsu_addrcheck.sv:L213-L229``）：

.. code-block:: systemverilog

      // Fast interrupt error logic
      assign fir_dccm_access_error_dc2    = ((start_addr_in_dccm_region_dc2 & ~start_addr_in_dccm_dc2) |
                                             (end_addr_in_dccm_region_dc2   & ~end_addr_in_dccm_dc2)) & lsu_pkt_dc2.valid & lsu_pkt_dc2.fast_int;
      assign fir_nondccm_access_error_dc2 = ~(start_addr_in_dccm_region_dc2 & end_addr_in_dccm_region_dc2) & lsu_pkt_dc2.valid & lsu_pkt_dc2.fast_int;


      rvdff #(.WIDTH(1)) base_reg_dccmorpic_dc2ff       (.din(base_reg_dccm_or_pic_dc1),      .dout(base_reg_dccm_or_pic_dc2),      .clk(lsu_c2_dc2_clk), .*);
      rvdff #(.WIDTH(1)) start_addr_in_dccm_dc2ff       (.din(start_addr_in_dccm_dc1),        .dout(start_addr_in_dccm_dc2),        .clk(lsu_c2_dc2_clk), .*);
      rvdff #(.WIDTH(1)) end_addr_in_dccm_dc2ff         (.din(end_addr_in_dccm_dc1),          .dout(end_addr_in_dccm_dc2),          .clk(lsu_c2_dc2_clk), .*);

逐段解释：

* 第 L213-L216 行：fast interrupt packet 如果在 DCCM region 但不在 DCCM range，
  设置 ``fir_dccm_access_error_dc2``；如果 start/end 不都在 DCCM region，设置
  ``fir_nondccm_access_error_dc2``。
* 第 L219-L227 行：base region、DCCM/PIC start/end range 和 region 都通过
  ``lsu_c2_dc2_clk`` 推进到 DC2。
* 第 L228 行：``is_sideeffects_dc2`` 再通过 ``lsu_c2_dc3_clk`` 推进到 DC3。

接口关系：

* 被调用：fast interrupt 错误信号进入 ``eh2_lsu_lsc_ctl``，随后形成
  ``lsu_fir_error``。
* 调用：寄存器原语 ``rvdff``。
* 共享状态：共享 DCCM/PIC range 检查结果、fast interrupt packet 和 C2 clocks。

§5  ``eh2_lsu_dccm_ctl.sv`` DCCM 与 PIC 控制
---------------------------------------------

``eh2_lsu_dccm_ctl`` 把 LSU 管线转换为 DCCM/PIC 读写时序。它处理 DMA DCCM read
return、DCCM read data 对齐、store buffer forwarding、ECC 纠正写回、PIC mask 读和
PIC/DMA 写。

§5.1  DCCM read data、store buffer merge 和 DMA return
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 DCCM lo/hi bank 和 store buffer 前递数据中构造 DC3 load 数据，并生成
DMA read return。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_ctl.sv:L202-L218``）：

.. code-block:: systemverilog

      assign dccm_dma_rvalid      = lsu_pkt_dc3.valid & lsu_pkt_dc3.load & lsu_pkt_dc3.dma;
      assign dccm_dma_ecc_error   = lsu_double_ecc_error_dc3;
      assign dccm_dma_rtag[2:0]   = dma_mem_tag_dc3[2:0];
      assign dccm_dma_rdata[63:0] = addr_in_pic_dc3 ? {2{picm_rd_data_dc3[31:0]}} : ldst_dual_dc3 ? lsu_rdata_corr_dc3[63:0] : {2{lsu_rdata_corr_dc3[31:0]}};

      assign {lsu_dccm_data_dc3_nc[63:32], lsu_dccm_data_dc3[31:0]} = lsu_rdata_dc3[63:0] >> 8*lsu_addr_dc3[1:0];
      assign {lsu_dccm_data_corr_dc3_nc[63:32], lsu_dccm_data_corr_dc3[31:0]} = lsu_rdata_corr_dc3[63:0] >> 8*lsu_addr_dc3[1:0];

      assign dccm_dout_dc3[63:0]      = {dccm_data_hi_dc3[pt.DCCM_DATA_WIDTH-1:0], dccm_data_lo_dc3[pt.DCCM_DATA_WIDTH-1:0]};
      assign dccm_corr_dout_dc3[63:0] = {sec_data_hi_dc3[pt.DCCM_DATA_WIDTH-1:0], sec_data_lo_dc3[pt.DCCM_DATA_WIDTH-1:0]};
      assign stbuf_fwddata_dc3[63:0]  = {stbuf_fwddata_hi_dc3[pt.DCCM_DATA_WIDTH-1:0], stbuf_fwddata_lo_dc3[pt.DCCM_DATA_WIDTH-1:0]};
      assign stbuf_fwdbyteen_dc3[7:0] = {stbuf_fwdbyteen_hi_dc3[pt.DCCM_BYTE_WIDTH-1:0], stbuf_fwdbyteen_lo_dc3[pt.DCCM_BYTE_WIDTH-1:0]};

逐段解释：

* 第 L202-L205 行：DMA read valid 来自 DC3 valid load DMA packet。DMA data 如果是
  PIC，复制 32-bit PIC data 到 64-bit；如果 DCCM dual，使用 64-bit 纠正数据；否则复制
  低 32-bit 纠正数据。
* 第 L207-L208 行：LSU core load data 按 ``lsu_addr_dc3[1:0]`` 右移，取对齐后的
  32-bit 结果。
* 第 L210-L213 行：原始 DCCM、纠正后 DCCM 和 stbuf 前递数据都拼成 64-bit hi/lo
  形式，byte enable 也拼成 8-bit。
* 第 L215-L218 行：逐 byte 选择 stbuf 前递数据或 DCCM 输出。纠正数据路径使用同样的
  byte enable 选择。

接口关系：

* 被调用：``eh2_lsu_lsc_ctl`` 读取 ``lsu_dccm_data_dc3`` 和
  ``lsu_dccm_data_corr_dc3``。
* 调用：读取 ``eh2_lsu_ecc`` 输出的 ``sec_data_*`` 和 ``eh2_lsu_stbuf`` 前递输出。
* 共享状态：共享 DCCM lo/hi data、ECC corrected data、stbuf data/byte enable、DMA tag。

§5.2  ECC 纠正写回和 DCCM 读写端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 single ECC 错误时决定是否进行纠正写回，并统一产生 DCCM read/write enable、
read/write address。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_ctl.sv:L220-L268``）：

.. code-block:: systemverilog

      assign kill_ecc_corr_lo_dc5 = (((lsu_addr_dc1[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2]) | (end_addr_dc1[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2])) & lsu_pkt_dc1.valid & lsu_pkt_dc1.store & lsu_pkt_dc1.dma & addr_in_dccm_dc1) |
                                    (((lsu_addr_dc2[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2]) | (end_addr_dc2[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2])) & lsu_pkt_dc2.valid & lsu_pkt_dc2.store & lsu_pkt_dc2.dma & addr_in_dccm_dc2) |
                                    (((lsu_addr_dc3[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2]) | (end_addr_dc3[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2])) & lsu_pkt_dc3.valid & lsu_pkt_dc3.store & lsu_pkt_dc3.dma & addr_in_dccm_dc3) |
                                    (((lsu_addr_dc4[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2]) | (end_addr_dc4[pt.DCCM_BITS-1:2] == lsu_addr_dc5[pt.DCCM_BITS-1:2])) & lsu_pkt_dc4.valid & lsu_pkt_dc4.store & lsu_pkt_dc4.dma & addr_in_dccm_dc4);

      assign kill_ecc_corr_hi_dc5 = (((lsu_addr_dc1[pt.DCCM_BITS-1:2] == end_addr_dc5[pt.DCCM_BITS-1:2]) | (end_addr_dc1[pt.DCCM_BITS-1:2] == end_addr_dc5[pt.DCCM_BITS-1:2])) & lsu_pkt_dc1.valid & lsu_pkt_dc1.store & lsu_pkt_dc1.dma & addr_in_dccm_dc1) |
                                    (((lsu_addr_dc2[pt.DCCM_BITS-1:2] == end_addr_dc5[pt.DCCM_BITS-1:2]) | (end_addr_dc2[pt.DCCM_BITS-1:2] == end_addr_dc5[pt.DCCM_BITS-1:2])) & lsu_pkt_dc2.valid & lsu_pkt_dc2.store & lsu_pkt_dc2.dma & addr_in_dccm_dc2) |

逐段解释：

* 第 L220-L228 行：如果 DC1-DC4 中有 DMA store 命中 DC5 ECC 纠正地址，lo/hi
  纠正写回分别被 kill。比较使用 ``[pt.DCCM_BITS-1:2]``。
* 第 L230-L238 行：load/LR single ECC 只在 commit 或 DMA 场景下成立，且 raw forwarding
  会屏蔽对应 lo/hi；double ECC 会屏蔽 single ECC 写回。
* 第 L243-L248 行：``lsu_stbuf_ecc_block`` 在 DC3-DC5 有 single ECC 时阻塞 stbuf
  commit；``lsu_stbuf_commit_any`` 还会检查当前 DCCM read/write 与 stbuf drain bank 是否冲突。
* 第 L250-L268 行：DCCM read enable 对 load、atomic 和需要读旧数据的 store 置位；
  DCCM write enable 来自 stbuf commit、ECC 纠正写回或 DMA DC1 write。

接口关系：

* 被调用：DCCM memory wrapper 读取 ``dccm_wren``、``dccm_rden`` 和地址。
* 调用：读取 stbuf drain 状态、ECC 状态、DMA 状态和 LSU packet。
* 共享状态：共享 ``ld_single_ecc_error_*``、``stbuf_reqvld_any``、
  ``lsu_dccm_rden_dc1``、``lsu_dccm_wren_spec_dc1`` 和地址。

§5.3  byte enable、write bypass、AMO/SC store data 和 PIC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：生成 DCCM byte enable、write bypass 比较、AMO/SC store data 选择、PIC read/write
信号和 raw bus store data。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_ctl.sv:L270-L310``）：

.. code-block:: systemverilog

       assign ldst_byteen_dc2[7:0] = ({8{lsu_pkt_dc2.by}}    & 8'b0000_0001) |
                                     ({8{lsu_pkt_dc2.half}}  & 8'b0000_0011) |
                                     ({8{lsu_pkt_dc2.word}}  & 8'b0000_1111) |
                                     ({8{lsu_pkt_dc2.dword}} & 8'b1111_1111);

      assign ldst_byteen_dc3[7:0] = ({8{lsu_pkt_dc3.by}}    & 8'b0000_0001) |
                                    ({8{lsu_pkt_dc3.half}}  & 8'b0000_0011) |
                                    ({8{lsu_pkt_dc3.word}}  & 8'b0000_1111) |
                                    ({8{lsu_pkt_dc3.dword}} & 8'b1111_1111);

     assign ldst_byteen_dc4[7:0] =  ({8{lsu_pkt_dc4.by}}    & 8'b0000_0001) |
                                    ({8{lsu_pkt_dc4.half}}  & 8'b0000_0011) |
                                    ({8{lsu_pkt_dc4.word}}  & 8'b0000_1111) |

逐段解释：

* 第 L270-L288 行：DC2-DC5 均按 by/half/word/dword 解码基础 byte enable。dword
  对应 8 个 byte 全开。
* 第 L290-L293 行：基础 byte enable 按地址低 2 bit 左移，得到横跨 hi/lo half 的
  8-bit byte enable。
* 第 L295-L305 行：stbuf drain 地址和 DC2-DC5 load/store 地址比较，生成 DCCM write
  bypass hit。SC 的 hi 比较被特殊屏蔽，因为源码注释说明 SC upper 32 bit 用于 ECC
  corrected data。
* 第 L307-L310 行：普通 AMO 使用 ``amo_data_dc3``；SC 的 hi data 在特定情况下使用
  ``sec_data_lo_dc3``。

接口关系：

* 被调用：byte enable 和 bypass 信号供 load data staging、ECC disable 和 store buffer
  data generation 使用。
* 调用：读取 ``eh2_lsu_amo`` 的 ``amo_data_dc3``。
* 共享状态：共享 ``lsu_pkt_dc*``、地址、stbuf drain address、SC success 和 ECC 数据。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_ctl.sv:L371-L388``）：

.. code-block:: systemverilog

      // Need to disable ecc correction since data is being forwarded for store (ECC is from RAM but data from forwarding path so they are out of sync).
      assign disable_ecc_check_lo_dc2 = lsu_stbuf_commit_any & lsu_pkt_dc2.store & dccm_wr_bypass_c1_c2_lo;
      assign disable_ecc_check_hi_dc2 = lsu_stbuf_commit_any & lsu_pkt_dc2.store & dccm_wr_bypass_c1_c2_hi;

      // PIC signals. PIC ignores the lower 2 bits of address since PIC memory registers are 32-bits
      assign picm_wren_notdma   = (lsu_pkt_dc5.valid & lsu_pkt_dc5.store & addr_in_pic_dc5 & lsu_commit_dc5);
      assign picm_wren          = (lsu_pkt_dc5.valid & lsu_pkt_dc5.store & addr_in_pic_dc5 & lsu_commit_dc5) | dma_pic_wen;
      assign picm_rden          = lsu_pkt_dc1.valid & lsu_pkt_dc1.load  & addr_in_pic_dc1;
      assign picm_mken          = lsu_pkt_dc1.valid & lsu_pkt_dc1.store & addr_in_pic_dc1;  // Get the mask for stores
      assign picm_rd_thr        = lsu_pkt_dc1.tid;
      assign picm_rdaddr[31:0]  = lsu_addr_dc1[31:0];
      assign picm_wraddr[31:0]  = dma_pic_wen ? dma_mem_addr[31:0] : lsu_addr_dc5[31:0];
      assign picm_wr_data[31:0] = dma_pic_wen ? dma_mem_wdata[31:0] : store_data_lo_dc5[31:0];

      // getting raw store data back for bus
      assign store_data_ext_dc3[63:0] = {store_ecc_data_hi_dc3[31:0], store_ecc_data_lo_dc3[31:0]};   // We don't need AMO here since this is used for fwding and there can't be a load behind AMO

逐段解释：

* 第 L371-L373 行：如果 store 数据来自 forwarding 而 ECC 仍来自 RAM，lo/hi ECC 检查会被
  关闭，源码注释说明这是为了避免数据和 ECC 不同步。
* 第 L375-L383 行：PIC write 来自 DC5 committed store 或 DMA PIC write；PIC read/mask
  在 DC1 触发；写地址和写数据在 DMA 与 core store 之间选择。
* 第 L385-L388 行：外部 bus forwarding 需要 raw store data，DC3 使用 ECC merge 后的
  hi/lo store data，DC4/DC5 使用已寄存的 store data。

接口关系：

* 被调用：PIC memory 读取 ``picm_*`` 信号，bus interface 读取
  ``store_data_ext_dc*``。
* 调用：本节不实例化模块。
* 共享状态：共享 stbuf commit、DCCM bypass、PIC/DMA 写状态、DC1/DC5 packet 和地址。

§6  ``eh2_lsu_stbuf.sv`` Store Buffer
--------------------------------------

``eh2_lsu_stbuf`` 的源码注释说明其功能是 Store Buffer，支持 dual writes and single
drain。它保存 DCCM store 的地址、byte enable、data、tid 和 DMA kill 状态，并为后续
load/PIC 访问提供 forwarding。

§6.1  entry 字段、coalescing 和入队
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 store buffer entry 字段，检测 DC5 store 与已有 entry 的地址匹配，并在
同一 entry 内合并 byte enable 和 data。

关键代码（``rtl/design/lsu/eh2_lsu_stbuf.sv:L96-L116``）：

.. code-block:: systemverilog

      localparam DEPTH      = pt.LSU_STBUF_DEPTH;
      localparam DATA_WIDTH = pt.DCCM_DATA_WIDTH;
      localparam BYTE_WIDTH = pt.DCCM_BYTE_WIDTH;
      localparam DEPTH_LOG2 = $clog2(DEPTH);

      // These are the fields in the store queue
      logic [DEPTH-1:0]                     stbuf_vld;
      logic [DEPTH-1:0]                     stbuf_dma_kill;
      logic [DEPTH-1:0][pt.LSU_SB_BITS-1:0] stbuf_addr;
      logic [DEPTH-1:0][BYTE_WIDTH-1:0]     stbuf_byteen;
      logic [DEPTH-1:0][DATA_WIDTH-1:0]     stbuf_data;
      logic [DEPTH-1:0]                     stbuf_tid;

      logic [DEPTH-1:0]                     sel_lo;
      logic [DEPTH-1:0]                     stbuf_wr_en;

逐段解释：

* 第 L96-L99 行：depth、data width、byte width 和 pointer width 全部来自 ``pt``。
* 第 L101-L107 行：每个 store buffer entry 保存 valid、DMA kill、地址、byte enable、
  data 和 tid。
* 第 L109-L116 行：写使能、reset、输入地址/数据/byte enable 分 entry 展开，供
  generate loop 更新。

接口关系：

* 被调用：``eh2_lsu`` 实例化 store buffer，``eh2_lsu_dccm_ctl`` 读取 drain 输出。
* 调用：后续使用 ``rvdffsc``、``rvdffe`` 保存 entry 字段。
* 共享状态：共享 ``pt.LSU_STBUF_DEPTH``、``pt.DCCM_DATA_WIDTH`` 和
  ``pt.LSU_SB_BITS``。

关键代码（``rtl/design/lsu/eh2_lsu_stbuf.sv:L220-L240``）：

.. code-block:: systemverilog

     // Store Buffer coalescing
      for (genvar i=0; i<DEPTH; i++) begin: FindMatchEntry
          assign store_matchvec_lo_dc5[i] = (stbuf_addr[i][pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)] == lsu_addr_dc5[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)]) & stbuf_vld[i] & ~stbuf_dma_kill[i] & lsu_commit_dc5 & ~stbuf_reset[i];
          assign store_matchvec_hi_dc5[i] = (stbuf_addr[i][pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)] == end_addr_dc5[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)]) & stbuf_vld[i] & ~stbuf_dma_kill[i] & lsu_commit_dc5 & ldst_dual_dc5 & ~stbuf_reset[i];
      end: FindMatchEntry

      assign store_coalesce_lo_dc5 = |store_matchvec_lo_dc5[DEPTH-1:0];
      assign store_coalesce_hi_dc5 = |store_matchvec_hi_dc5[DEPTH-1:0];

      // Allocate new in this entry if :
      // 1. wrptr, single allocate, lo did not coalesce
      // 2. wrptr, double allocate, lo ^ hi coalesced
      // 3. wrptr + 1, double alloacte, niether lo or hi coalesced
      // Also update if there is a hi or a lo coalesce to this entry
      // Store Buffer instantiation
      for (genvar i=0; i<DEPTH; i++) begin: GenStBuf
         assign stbuf_wr_en[i] = store_stbuf_reqvld_dc5 & (

逐段解释：

* 第 L220-L224 行：对每个 entry 分别比较 lo 地址和 hi/end 地址。匹配要求 entry
  valid、未被 DMA kill、DC5 store commit、entry 当前未 reset；hi 匹配还要求
  ``ldst_dual_dc5``。
* 第 L226-L227 行：lo/hi coalesce 是对应 match vector 的 OR。
* 第 L229-L234 行：源码注释列出新 entry 分配条件：单写未合并、dual 写部分合并、
  dual 写均未合并以及已有 entry 更新。
* 第 L235-L240 行：``stbuf_wr_en`` 把新分配和 coalesced update 合并成统一写使能。

接口关系：

* 被调用：entry write enable 驱动本模块内部 flops。
* 调用：无外部调用。
* 共享状态：读取 DC5 地址、end address、dual 标记、commit、reset 和 entry state。

§6.2  drain、full/empty 和 per-thread 计数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：选择读指针 entry 作为 DCCM writeback/drain 输出，维护读写指针，并按线程统计
store buffer 满/空状态。

关键代码（``rtl/design/lsu/eh2_lsu_stbuf.sv:L264-L309``）：

.. code-block:: systemverilog

      // Store Buffer drain logic
      assign stbuf_reqvld_flushed_any            = stbuf_vld[RdPtr] & stbuf_dma_kill[RdPtr];
      assign stbuf_reqvld_any                    = stbuf_vld[RdPtr] & ~stbuf_dma_kill[RdPtr] & ~(|stbuf_dma_kill_en[DEPTH-1:0]);  // Don't drain if some kill bit is being set this cycle
      assign stbuf_addr_any[pt.LSU_SB_BITS-1:0]  = stbuf_addr[RdPtr][pt.LSU_SB_BITS-1:0];
      assign stbuf_data_any[DATA_WIDTH-1:0]      = stbuf_data[RdPtr][DATA_WIDTH-1:0];

      // Update the RdPtr/WrPtr logic
      assign WrPtrEn                  = (store_stbuf_reqvld_dc5  & ~ldst_dual_dc5 & ~(store_coalesce_hi_dc5 | store_coalesce_lo_dc5))  |  // writing 1 and did not coalesce
                                        (store_stbuf_reqvld_dc5  &  ldst_dual_dc5 & ~(store_coalesce_hi_dc5 & store_coalesce_lo_dc5));    // writing 2 and atleast 1 did not coalesce
      assign NxtWrPtr[DEPTH_LOG2-1:0] = (store_stbuf_reqvld_dc5 & ldst_dual_dc5 & ~(store_coalesce_hi_dc5 | store_coalesce_lo_dc5)) ? WrPtrPlus2[DEPTH_LOG2-1:0] : WrPtrPlus1[DEPTH_LOG2-1:0];
      assign RdPtrEn                  = lsu_stbuf_commit_any | stbuf_reqvld_flushed_any;
      assign NxtRdPtr[DEPTH_LOG2-1:0] = RdPtrPlus1[DEPTH_LOG2-1:0];

逐段解释：

* 第 L264-L268 行：读指针 entry 被 DMA kill 时形成 flushed drain；未 kill 且本周期没有新
  kill 位设置时形成正常 drain。输出地址和数据直接来自 ``RdPtr`` entry。
* 第 L270-L275 行：写指针只在新 entry 分配时推进，dual 且 lo/hi 都未 coalesce 时推进 2。
  读指针在 DCCM commit 或 flushed drain 时推进 1。
* 第 L277-L284 行：按线程统计当前 valid entry 数。
* 第 L292-L308 行：把 DC1-DC5 管线中的 speculative DCCM store 也计入 per-thread
  fullness 判断，并输出 ``lsu_stbuf_full_any`` 和 ``lsu_stbuf_empty_any``。

接口关系：

* 被调用：``eh2_lsu_dccm_ctl`` 读取 ``stbuf_reqvld_any``、``stbuf_addr_any`` 和
  ``stbuf_data_any``。
* 调用：使用 ``rvdffs`` 保存 ``WrPtr`` 和 ``RdPtr``。
* 共享状态：共享 entry valid、DMA kill、DC1-DC5 store packet、thread id 和 stbuf commit。

§6.3  load/PIC forwarding
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 DC2 对 load/store 地址和 store buffer entry 做 byte-level 比较，生成 DCCM/PIC
前递 byte enable 和 data。

关键代码（``rtl/design/lsu/eh2_lsu_stbuf.sv:L319-L354``）：

.. code-block:: systemverilog

      // Load forwarding logic from the store queue
      assign cmpen_hi_dc2                                     = lsu_cmpen_dc2 & ldst_dual_dc2;
      assign cmpaddr_hi_dc2[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)] = end_addr_dc2[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)];

      assign cmpen_lo_dc2                                     = lsu_cmpen_dc2;
      assign cmpaddr_lo_dc2[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)] = lsu_addr_dc2[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)];

      always_comb begin: GenLdFwd
         stbuf_fwdbyteen_hi_dc2[BYTE_WIDTH-1:0]   = '0;
         stbuf_fwdbyteen_lo_dc2[BYTE_WIDTH-1:0]   = '0;

         for (int i=0; i<DEPTH; i++) begin
            stbuf_match_hi[i] = (stbuf_addr[i][pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)] == cmpaddr_hi_dc2[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)]) & stbuf_vld[i] & ~stbuf_dma_kill[i] & addr_in_dccm_dc2;
            stbuf_match_lo[i] = (stbuf_addr[i][pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)] == cmpaddr_lo_dc2[pt.LSU_SB_BITS-1:$clog2(BYTE_WIDTH)]) & stbuf_vld[i] & ~stbuf_dma_kill[i] &  addr_in_dccm_dc2;

逐段解释：

* 第 L319-L324 行：hi 比较只在 ``lsu_cmpen_dc2`` 且 ``ldst_dual_dc2`` 时使能；lo 比较只
  需要 ``lsu_cmpen_dc2``。
* 第 L326-L333 行：每个 entry 分别比较 lo/hi 地址，要求 entry valid、未被 DMA kill、
  且 DC2 地址在 DCCM。
* 第 L334-L335 行：如果 DC2 是 DMA store 且命中 entry，则设置 ``stbuf_dma_kill_en``，
  表示 DMA 已更新 DCCM，不再 drain 旧 entry。
* 第 L337-L343 行：逐 byte 合成 forwarding byte enable。
* 第 L347-L354 行：逐 entry OR 出 hi/lo forwarding data。

接口关系：

* 被调用：``eh2_lsu_dccm_ctl`` 使用 ``stbuf_fwddata_*_dc3`` 和
  ``stbuf_fwdbyteen_*_dc3``。
* 调用：本节不调用外部模块。
* 共享状态：读取 stbuf entry、DC2 地址、DCCM 命中、DMA packet 和 compare enable。

关键代码（``rtl/design/lsu/eh2_lsu_stbuf.sv:L390-L480``）：

.. code-block:: systemverilog

      assign ld_addr_dc3hit_lo_lo = (lsu_addr_dc2[31:2] == lsu_addr_dc3[31:2]) & lsu_pkt_dc3.valid & lsu_pkt_dc3.store  & ~lsu_pkt_dc3.dma & tid_match_c2c3;
      assign ld_addr_dc3hit_lo_hi = (end_addr_dc2[31:2] == lsu_addr_dc3[31:2]) & lsu_pkt_dc3.valid & lsu_pkt_dc3.store  & ~lsu_pkt_dc3.dma & tid_match_c2c3;
      assign ld_addr_dc3hit_hi_lo = (lsu_addr_dc2[31:2] == end_addr_dc3[31:2]) & lsu_pkt_dc3.valid & lsu_pkt_dc3.store  & ~lsu_pkt_dc3.dma & ldst_dual_dc3 & tid_match_c2c3;
      assign ld_addr_dc3hit_hi_hi = (end_addr_dc2[31:2] == end_addr_dc3[31:2]) & lsu_pkt_dc3.valid & lsu_pkt_dc3.store  & ~lsu_pkt_dc3.dma & ldst_dual_dc3 & tid_match_c2c3;

      assign ld_addr_dc4hit_lo_lo = (lsu_addr_dc2[31:2] == lsu_addr_dc4[31:2]) & lsu_pkt_dc4.valid & lsu_pkt_dc4.store & ~lsu_pkt_dc4.dma & tid_match_c2c4;
      assign ld_addr_dc4hit_lo_hi = (end_addr_dc2[31:2] == lsu_addr_dc4[31:2]) & lsu_pkt_dc4.valid & lsu_pkt_dc4.store & ~lsu_pkt_dc4.dma & tid_match_c2c4;

逐段解释：

* 第 L390-L403 行：除了 store buffer entry，模块还比较 DC2 load 与 DC3/DC4/DC5 中尚未
  入队的 store。比较同时覆盖 lo/hi 地址和 thread id。
* 第 L405-L452 行：每个 byte 组合 DC3/DC4/DC5 命中，生成 pipe forwarding 的 byte
  enable 和 data。
* 第 L453-L462 行：pipe forwarding 优先级高于 store queue forwarding：DC3 优先，
  然后 DC4、DC5，最后才使用 stbuf data。
* 第 L465-L467 行：PIC forwarding 复用 lo side 的 forwarding 结果，目标在 PIC 且 lo
  byte enable 非零时输出 ``picm_fwd_en_dc2``。
* 第 L472-L480 行：forwarding byte enable 和 data 被寄存到 DC3，供 DCCM 控制路径使用。

接口关系：

* 被调用：``eh2_lsu_dccm_ctl`` 和 PIC mask/data 路径读取最终 forwarding 信号。
* 调用：寄存器原语 ``rvdff``、``rvdffe``。
* 共享状态：共享 DC2-DC5 地址、packet、tid、store data、stbuf entry 和 clocks。

§7  ``eh2_lsu_bus_intf.sv`` 与 ``eh2_lsu_bus_buffer.sv`` 外部总线
-------------------------------------------------------------------

外部总线路径由两层组成。``eh2_lsu_bus_intf`` 负责顶层 AXI 信号、跨线程选择、
NB-load 汇聚和每线程 buffer 实例；``eh2_lsu_bus_buffer`` 负责某个线程内部的
ibuf、obuf、buffer entry 状态机、load forwarding、tag 分配和 imprecise error。

§7.1  bus interface 输入、NB-load 输出和 AXI 端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明总线接口边界。该模块接收 DC1-DC5 packet/address/store data、side-effect
属性、flush、TLU disable 位，并输出 NB-load、PMU、AXI 和 imprecise error 信号。

关键代码（``rtl/design/lsu/eh2_lsu_bus_intf.sv:L57-L113``）：

.. code-block:: systemverilog

      input logic                          lsu_busreq_dc1,                   // bus request is in dc2

      input                                eh2_lsu_pkt_t lsu_pkt_dc1_pre,        // lsu packet flowing down the pipe
      input                                eh2_lsu_pkt_t lsu_pkt_dc2,            // lsu packet flowing down the pipe
      input                                eh2_lsu_pkt_t lsu_pkt_dc3,            // lsu packet flowing down the pipe
      input                                eh2_lsu_pkt_t lsu_pkt_dc4,            // lsu packet flowing down the pipe
      input                                eh2_lsu_pkt_t lsu_pkt_dc5,            // lsu packet flowing down the pipe

      input logic [31:0]                   lsu_addr_dc2,                     // lsu address flowing down the pipe
      input logic [31:0]                   lsu_addr_dc3,                     // lsu address flowing down the pipe
      input logic [31:0]                   lsu_addr_dc4,                     // lsu address flowing down the pipe
      input logic [31:0]                   lsu_addr_dc5,                     // lsu address flowing down the pipe

逐段解释：

* 第 L57 行：bus 请求入口名为 ``lsu_busreq_dc1``，由顶层在 DC1 阶段生成。
* 第 L59-L63 行：总线接口持有 DC1-pre 到 DC5 的 packet，用于生成 tag、valid、
  flush、load forwarding 和 buffer 状态。
* 第 L65-L77 行：DC2-DC5 地址和 store data 输入给 external forwarding、ibuf/obuf 和
  AXI write data。
* 第 L80-L88 行：dual、commit、side-effect 和 flush 信号决定 bus request 是否继续推进
  以及是否可合并或 posted。
* 第 L101-L112 行：NB-load 输出包括创建、invalidate、return valid、error、tid、tag 和 data。

接口关系：

* 被调用：``eh2_lsu`` 实例化 ``eh2_lsu_bus_intf``。
* 调用：后续 per-thread generate 实例化 ``eh2_lsu_bus_buffer``。
* 共享状态：共享 DC1-DC5 packet/address、flush、side-effect、TLU disable 位和 AXI 端口。

§7.2  load forwarding、NB-load create/invalidate 和 AXI 命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 bus path 内进行 pipe/write-buffer forwarding，生成 NB-load CAM 入口和
invalidate 信号，并把 obuf 转为 AXI AW/W/AR。

关键代码（``rtl/design/lsu/eh2_lsu_bus_intf.sv:L404-L424``）：

.. code-block:: systemverilog

      always_comb begin
         ld_full_hit_lo_dc2 = 1'b1;
         ld_full_hit_hi_dc2 = 1'b1;
         for (int i=0; i<4; i++) begin
            ld_full_hit_lo_dc2 &= (ld_byte_hit_lo[i] | ~ldst_byteen_lo_dc2[i]);
            ld_full_hit_hi_dc2 &= (ld_byte_hit_hi[i] | ~ldst_byteen_hi_dc2[i]);
         end
      end

      // This will be high if all the bytes of load hit the stores in pipe/write buffer (dc3/dc4/dc5/wrbuf)
      assign ld_full_hit_dc2 = ld_full_hit_lo_dc2 & ld_full_hit_hi_dc2 & lsu_busreq_dc2 & lsu_pkt_dc2.load & ~is_sideeffects_dc2;
      assign {ld_fwddata_dc2_nc[63:32], ld_fwddata_dc2[31:0]} = {ld_fwddata_hi[31:0], ld_fwddata_lo[31:0]} >> (8*lsu_addr_dc2[1:0]);
      assign bus_read_data_dc3[31:0]                          = ld_fwddata_dc3[31:0];

逐段解释：

* 第 L404-L411 行：lo/hi full hit 从 4 个 byte 逐位相与得出。未请求的 byte 用
  ``~ldst_byteen`` 放行。
* 第 L413-L415 行：``ld_full_hit_dc2`` 要求所有需要 byte 都命中、DC2 是 bus load、
  且不是 side-effect。命中数据按地址低位右移成 32-bit。
* 第 L416 行：``bus_read_data_dc3`` 来自 DC3 flopped forwarding data。
* 第 L418-L424 行：外部 load 在 DC1 创建 NB-load CAM entry；如果 DC2 load 完全由
  forwarding 命中则在 DC2 invalidate；如果 DC5 没有 commit 则在 DC5 invalidate。

接口关系：

* 被调用：DEC NB-load CAM 读取 ``lsu_nonblock_load_*`` 信号。
* 调用：读取 per-thread bus buffer forwarding 数据和 pipe forwarding 数据。
* 共享状态：共享 DC2 byte enable、bus request、side-effect、WrPtr tag 和 commit。

关键代码（``rtl/design/lsu/eh2_lsu_bus_intf.sv:L445-L476``）：

.. code-block:: systemverilog

      // AXI command signals
      assign lsu_axi_awvalid               = obuf_valid[bus_tid] & obuf_write[bus_tid] & ~obuf_cmd_done[bus_tid] & ~bus_addr_match_pending[bus_tid];
      assign lsu_axi_awid[pt.LSU_BUS_TAG-1:0] = (pt.LSU_BUS_TAG)'({bus_tid,obuf_tag0[bus_tid][pt.LSU_BUS_TAG-2:0]});
      assign lsu_axi_awaddr[31:0]          = obuf_sideeffect[bus_tid] ? obuf_addr[bus_tid][31:0] : {obuf_addr[bus_tid][31:3],3'b0};
      assign lsu_axi_awsize[2:0]           = obuf_sideeffect[bus_tid] ? {1'b0, obuf_sz[bus_tid][1:0]} : 3'b011;
      assign lsu_axi_awprot[2:0]           = 3'b001;
      assign lsu_axi_awcache[3:0]          = obuf_sideeffect[bus_tid]? 4'b0 : 4'b1111;
      assign lsu_axi_awregion[3:0]         = obuf_addr[bus_tid][31:28];
      assign lsu_axi_awlen[7:0]            = '0;
      assign lsu_axi_awburst[1:0]          = 2'b01;
      assign lsu_axi_awqos[3:0]            = '0;
      assign lsu_axi_awlock                = '0;

逐段解释：

* 第 L445-L456 行：AXI AW valid 来自当前 ``bus_tid`` 的 obuf，要求 write、命令未完成、
  且无 same-address pending。非 side-effect 地址被 8-byte 对齐，size 固定为 ``3'b011``；
  side-effect 地址保留原地址和 packet size。
* 第 L458-L461 行：W channel valid 同样来自 obuf，wstrb 由 ``obuf_byteen`` 和 write
  gate，wlast 恒为 1。
* 第 L463-L473 行：AR channel 对非 write obuf 生效，地址、size、cache 和 region 与
  AW 规则对应。
* 第 L475-L476 行：B 和 R ready 恒为 1。

接口关系：

* 被调用：外部 AXI fabric 或 testbench memory 读取 LSU AXI channel。
* 调用：读取 per-thread obuf 和 ``bus_tid`` 仲裁状态。
* 共享状态：共享 obuf valid/write/tag/address/byteen/data、same-address pending 和
  ``pt.LSU_BUS_TAG``。

§7.3  per-thread bus buffer、bus_tid 和 NB return 仲裁
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为每个线程实例化一个 bus buffer，随后按 ``bus_tid`` 选择 AXI 命令线程，并用
另一个仲裁器选择 NB-load return 线程。

关键代码（``rtl/design/lsu/eh2_lsu_bus_intf.sv:L512-L588``）：

.. code-block:: systemverilog

      // Per thread bus buffer
      for (genvar i=0; i<pt.NUM_THREADS; i++) begin: GenThreadLoop
         // Read/Write Buffer
         eh2_lsu_bus_buffer #(.pt(pt)) bus_buffer (
            .tid(1'(i)),
            .clk(active_thread_l2clk[i]),
            .lsu_bus_obuf_c1_clken(lsu_bus_obuf_c1_clken[i]),
            .lsu_bus_ibuf_c1_clk(lsu_bus_ibuf_c1_clk[i]),
            .lsu_bus_buf_c1_clk(lsu_bus_buf_c1_clk[i]),
            .lsu_bus_obuf_c1_clk(lsu_bus_obuf_c1_clk[i]),
            .dec_tlu_force_halt(dec_tlu_force_halt[i]),
            .lsu_bus_cntr_overflow(lsu_bus_cntr_overflow[i]),
            .lsu_bus_idle_any(lsu_bus_idle_any[i]),

逐段解释：

* 第 L512-L565 行：每个 thread 实例化一个 ``eh2_lsu_bus_buffer``。实例 clock 使用
  ``active_thread_l2clk[i]``，并显式连接 ibuf、obuf 和 buf clock。
* 第 L567-L578 行：各线程 NB-load return valid/error/tag/data 被 ``lsu_nonblock_load_data_tid``
  选择汇聚成 LSU 顶层输出。
* 第 L580-L588 行：双线程配置下，``bus_tid`` 根据 obuf ready/valid 和 command sent
  状态更新；单线程配置固定为 0。

接口关系：

* 被调用：``eh2_lsu`` 读取汇聚后的 AXI、NB-load 和 imprecise error 信号。
* 调用：实例化 ``eh2_lsu_bus_buffer``，双线程 NB return 使用 ``rvarbiter2``。
* 共享状态：共享 per-thread obuf、bus buffer 状态、``bus_tid`` 和 NB return 状态。

§7.4  bus request pipeline 和 AXI assertions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 bus request 和 NB-load valid 从 DC1 推进到 DC5，并在 assertion 分支检查 AXI
地址对齐和通道信号稳定性。

关键代码（``rtl/design/lsu/eh2_lsu_bus_intf.sv:L603-L623``）：

.. code-block:: systemverilog

      // Fifo flops
      rvdffe #(.WIDTH(32)) lsu_fwddata_dc3ff (.din(ld_fwddata_dc2[31:0]), .dout(ld_fwddata_dc3[31:0]), .en((lsu_pkt_dc2.valid & lsu_pkt_dc2.load & lsu_busreq_dc2) | clk_override), .*);

      rvdff #(.WIDTH(1)) clken_ff (.din(lsu_bus_clk_en), .dout(lsu_bus_clk_en_q), .clk(active_clk), .*);

      rvdff #(.WIDTH(1)) is_sideeffects_dc4ff (.din(is_sideeffects_dc3), .dout(is_sideeffects_dc4), .clk(lsu_c1_dc4_clk), .*);
      rvdff #(.WIDTH(1)) is_sideeffects_dc5ff (.din(is_sideeffects_dc4), .dout(is_sideeffects_dc5), .clk(lsu_c1_dc5_clk), .*);

      rvdff #(4) lsu_byten_dc3ff (.*, .din(ldst_byteen_dc2[3:0]), .dout(ldst_byteen_dc3[3:0]), .clk(lsu_c1_dc3_clk));
      rvdff #(4) lsu_byten_dc4ff (.*, .din(ldst_byteen_dc3[3:0]), .dout(ldst_byteen_dc4[3:0]), .clk(lsu_c1_dc4_clk));
      rvdff #(4) lsu_byten_dc5ff (.*, .din(ldst_byteen_dc4[3:0]), .dout(ldst_byteen_dc5[3:0]), .clk(lsu_c1_dc5_clk));

逐段解释：

* 第 L603-L604 行：DC2 forwarding data 在 valid bus load 时寄存到 DC3。
* 第 L606 行：``lsu_bus_clk_en`` 被寄存为 ``lsu_bus_clk_en_q``，供 bus buffer 错误逻辑使用。
* 第 L608-L613 行：side-effect 和 byte enable 沿 DC4/DC5 推进。
* 第 L615-L623 行：``lsu_busreq`` 从 DC1 推进到 DC5。DC3 阶段在 ``ld_full_hit_dc2`` 为 1
  时清除请求，说明完全 forwarding 命中的 load 不再走外部 bus。
* 第 L625-L718 行：``RV_ASSERT_ON`` 下检查 AXI AW/AR 地址对齐，以及 AW/W/AR 通道在
  bus clock 中间的稳定性。

接口关系：

* 被调用：bus buffer 和 AXI command 逻辑读取这些 flopped 信号。
* 调用：寄存器原语 ``rvdff``、``rvdffe``。
* 共享状态：共享 bus request、byte enable、side-effect、forwarding hit 和 clocks。

§8  ``eh2_lsu_bus_buffer.sv`` per-thread bus buffer
---------------------------------------------------

``eh2_lsu_bus_buffer`` 是每线程外部访问队列。源码中的状态枚举为 ``IDLE``、
``WAIT``、``CMD``、``RESP``、``DONE_PARTIAL``、``DONE_WAIT`` 和 ``DONE``。注释说明
load 路径是 ``IDLE -> WAIT -> CMD -> RESP -> DONE -> IDLE``，store 路径是
``IDLE -> WAIT -> CMD -> RESP(?) -> IDLE``。

§8.1  状态、entry 字段和 load forwarding
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 buffer entry 状态和字段，并支持 external load 从 ibuf/buffer 中前递 store 数据。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L150-L206``）：

.. code-block:: systemverilog

      // For Ld: IDLE -> WAIT -> CMD -> RESP -> DONE -> IDLE
      // For St: IDLE -> WAIT -> CMD -> RESP(?) -> IDLE
      typedef enum logic [2:0] {IDLE=3'b000, WAIT=3'b001, CMD=3'b010, RESP=3'b011, DONE_PARTIAL=3'b100, DONE_WAIT=3'b101, DONE=3'b110} state_t;

      localparam DEPTH     = pt.LSU_NUM_NBLOAD;
      localparam DEPTH_LOG2 = pt.LSU_NUM_NBLOAD_WIDTH;
      localparam TIMER     = 8;   // This can be only power of 2
      localparam TIMER_LOG2 = (TIMER < 2) ? 1 : $clog2(TIMER);
      localparam TIMER_MAX = (TIMER == 0) ? TIMER_LOG2'(0) : TIMER_LOG2'(TIMER - 1);  // Maximum value of timer

逐段解释：

* 第 L150-L152 行：状态枚举直接定义 load/store buffer entry 的生命周期。
* 第 L154-L158 行：buffer depth 使用 ``pt.LSU_NUM_NBLOAD``，tag width 使用
  ``pt.LSU_NUM_NBLOAD_WIDTH``，timer 固定为 8。
* 第 L187-L205 行：每个 entry 保存 state、size、address、byte enable、side-effect、
  write、unsigned、dual、same-dword、nomerge、dual tag、forward tag、error、data、
  age 和 response age。

接口关系：

* 被调用：``eh2_lsu_bus_intf`` 按线程实例化本模块。
* 调用：后续状态机用这些字段生成 ibuf/obuf/AXI 和 NB return。
* 共享状态：共享 per-thread packet、address、store data、AXI response 和 force halt。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L323-L367``）：

.. code-block:: systemverilog

      // Buffer hit logic for bus load forwarding
      assign ldst_byteen_hi_dc2[3:0]   = ldst_byteen_ext_dc2[7:4];
      assign ldst_byteen_lo_dc2[3:0]   = ldst_byteen_ext_dc2[3:0];
      for (genvar i=0; i<DEPTH; i++) begin
         // We can't forward from RESP for ahb since multiple writes to the same address can be in RESP and we can't find out their age
         assign ld_addr_hitvec_lo[i] = (lsu_addr_dc2[31:2] == buf_addr[i][31:2]) & buf_write[i] & ((buf_state[i] == WAIT) | (buf_state[i] == CMD)) & (lsu_pkt_dc2.tid ~^ tid) & lsu_busreq_dc2;
         assign ld_addr_hitvec_hi[i] = (end_addr_dc2[31:2] == buf_addr[i][31:2]) & buf_write[i] & ((buf_state[i] == WAIT) | (buf_state[i] == CMD)) & (lsu_pkt_dc2.tid ~^ tid) & lsu_busreq_dc2;
      end

逐段解释：

* 第 L323-L325 行：DC2 的 8-bit byte enable 拆成 hi/lo 两个 4-bit enable。
* 第 L326-L330 行：buffer forwarding 只从 WAIT 或 CMD 状态的 write entry 取数据，
  并要求 thread id 匹配和当前是 bus request。源码注释说明不从 RESP 状态 forward。
* 第 L332-L342 行：逐 byte 检查 entry byte enable 与 load byte enable 的交集，并用
  age 规则屏蔽较老 entry 或已被 ibuf 命中的 byte。
* 第 L344-L351 行：ibuf 也参与 forwarding，命中条件是地址、tid、write、valid 和 bus request。
* 第 L353-L367 行：最终 forwarding data 先用 ibuf 数据初始化，再 OR 进各 buffer entry
  命中的 byte。

接口关系：

* 被调用：``eh2_lsu_bus_intf`` 汇总每线程 ``ld_byte_hit_buf_*`` 和 ``ld_fwddata_buf_*``。
* 调用：本节只使用组合逻辑。
* 共享状态：读取 ibuf、buffer entry、age、DC2 地址和 byte enable。

§8.2  ibuf、obuf 和 write coalescing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 DC5 committed bus request 暂存到 ibuf，必要时合并 store，再转入 obuf 发送 AXI
命令。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L377-L417``）：

.. code-block:: systemverilog

      assign ibuf_byp   = lsu_busreq_dc5 & ((lsu_pkt_dc5.load | no_word_merge_dc5) & ~ibuf_valid);    // Bypass if ibuf is empty and it's a load or no merge possible
      assign ibuf_wr_en = lsu_busreq_dc5 & lsu_commit_dc5 & (lsu_pkt_dc5.tid ~^ tid) & ~ibuf_byp;
      assign ibuf_rst   = (ibuf_drain_vld & ~ibuf_wr_en) | dec_tlu_force_halt;
      assign ibuf_force_drain = lsu_busreq_dc2 & ~lsu_busreq_dc3 & ~lsu_busreq_dc4 & ~lsu_busreq_dc5 & ibuf_valid & (lsu_pkt_dc2.load | (ibuf_addr[31:2] != lsu_addr_dc2[31:2]));  // Move the ibuf to buf if there is a non-colaescable ld/st in dc2 but nothing in dc3/dc4/dc5
      assign ibuf_drain_vld = ibuf_valid & (((ibuf_wr_en | (ibuf_timer == TIMER_MAX)) & ~(ibuf_merge_en & ibuf_merge_in)) | ibuf_byp | ibuf_force_drain | ibuf_sideeffect | ~ibuf_write | bus_coalescing_disable);
      assign ibuf_tag_in[DEPTH_LOG2-1:0] = (ibuf_merge_en & ibuf_merge_in) ? ibuf_tag[DEPTH_LOG2-1:0] : (ldst_dual_dc5 ? WrPtr1_dc5 : WrPtr0_dc5);
      assign ibuf_dualtag_in[DEPTH_LOG2-1:0] = WrPtr0_dc5;

逐段解释：

* 第 L377-L381 行：ibuf 可以被 bypass，也可以在 timer 到达最大值、不能继续 merge、
  side-effect、load 或 coalescing disabled 时 drain。
* 第 L382-L386 行：ibuf tag、dual tag、size、address 和 byte enable 从 DC5 request
  或 merge 状态生成。
* 第 L387-L390 行：写数据按 byte enable 选择新 store data 或 ibuf 旧数据，实现同地址
  store 合并。
* 第 L393-L395 行：ibuf merge 要求 DC5 committed store、tid 匹配、ibuf valid/write、
  word address 相同、非 side-effect 且 coalescing 未关闭；dual store 不在 ibuf 内部直接 merge。
* 第 L404-L417 行：ibuf valid、tag、dual、side-effect、write、size、address、byteen、
  data 和 timer 被寄存。

接口关系：

* 被调用：buffer entry 分配逻辑读取 ``ibuf_drain_vld``、``ibuf_*`` 字段。
* 调用：寄存器原语 ``rvdffsc``、``rvdffs``、``rvdffe``。
* 共享状态：共享 DC5 bus request、commit、tid、dual、merge disable 和 force halt。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L427-L478``）：

.. code-block:: systemverilog

      assign obuf_wr_wait = (buf_numvld_wrcmd_any[3:0] == 4'b1) & (buf_numvld_cmd_any[3:0] == 4'b1) & (obuf_wr_timer != TIMER_MAX) &
                            ~bus_coalescing_disable & ~buf_nomerge[CmdPtr0] & ~buf_sideeffect[CmdPtr0] & ~obuf_force_wr_en;
      assign obuf_wr_timer_in = obuf_wr_en ? 3'b0: (((buf_numvld_cmd_any > 4'b0) & (obuf_wr_timer < TIMER_MAX)) ? (obuf_wr_timer + 1'b1) : obuf_wr_timer);
      assign obuf_force_wr_en = lsu_busreq_dc2 & ~lsu_busreq_dc3 & ~lsu_busreq_dc4 & ~lsu_busreq_dc5 & ~ibuf_valid & (buf_numvld_cmd_any[3:0] == 4'b1) & (lsu_addr_dc2[31:2] != buf_addr[CmdPtr0][31:2]);   // Entry in dc2 can't merge with entry going to obuf and there is no entry in between
      assign ibuf_buf_byp = ibuf_byp & (buf_numvld_pend_any[3:0] == 4'b0) & (~lsu_pkt_dc5.store | no_dword_merge_dc5);

      assign obuf_wr_en = ((ibuf_buf_byp & lsu_commit_dc5 & (lsu_pkt_dc5.tid ~^ tid) & ~(is_sideeffects_dc5 & bus_sideeffect_pend)) |
                           ((buf_state[CmdPtr0] == CMD) & found_cmdptr0 & ~buf_cmd_state_bus_en[CmdPtr0] & ~(buf_sideeffect[CmdPtr0] & bus_sideeffect_pend) &

逐段解释：

* 第 L427-L430 行：obuf 可以等待更多可合并 write command，但 timer、nomerge、
  side-effect 和 force write 会打破等待。
* 第 L431-L436 行：obuf 写入可以来自 ibuf bypass，也可以来自 buffer 中最老 CMD entry。
  side-effect pending、bus command ready、overflow 和 same-address pending 都参与 gating。
* 第 L439-L448 行：obuf 输入字段从 ibuf bypass 或 ``CmdPtr0`` entry 中选择，并设置
  ``tag0`` 和 ``tag1``。
* 第 L457-L458 行：``obuf_nosend`` 用于 external load-to-load forwarding，条件包含
  同 8-byte address、对齐、非 side-effect、非 write 和外部 forwarding 未关闭。
* 第 L460-L478 行：obuf byte enable/data 可以把两个 entry 合并到一个 64-bit beat；
  源码注释说明 AXI native store 不进行 store obuf merge。

接口关系：

* 被调用：``eh2_lsu_bus_intf`` 用 obuf 字段生成 AXI AW/W/AR。
* 调用：读取 buffer age pointer、ibuf、side-effect pending 和 bus ready。
* 共享状态：共享 ``CmdPtr0``、``CmdPtr1``、obuf flops、bus command handshake 和
  TLU disable 位。

§8.3  tag 分配、age 向量和 entry 状态机
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 NB-load/bus buffer 找空 entry，按 age 选择命令和响应顺序，并用状态机管理
每个 entry 的 command、response、done 和 reset。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L502-L574``）：

.. code-block:: systemverilog

      // Find the entry to allocate and entry to send
      always_comb begin
         WrPtr0_dc1[DEPTH_LOG2-1:0] = '0;
         WrPtr1_dc1[DEPTH_LOG2-1:0] = '0;
         found_wrptr0  = '0;
         found_wrptr1  = '0;

         // Find first write pointer
         for (int i=0; i<DEPTH; i++) begin
            if (~found_wrptr0) begin
               WrPtr0_dc1[DEPTH_LOG2-1:0] = DEPTH_LOG2'(i);
               found_wrptr0 = (buf_state[i] == IDLE) & ~((ibuf_valid & (ibuf_tag == DEPTH_LOG2'(i)))                                               |

逐段解释：

* 第 L502-L533 行：``WrPtr0_dc1`` 和 ``WrPtr1_dc1`` 扫描 IDLE entry，并排除 ibuf 以及
  DC1-DC5 管线中已经预占的 tag。
* 第 L535-L547 行：``CmdPtr0Dec`` 选择最老 CMD entry，``CmdPtr1Dec`` 选择次老 CMD entry，
  ``RspPtrDec`` 选择 DONE_WAIT response entry，最后用 ``f_Enc8to3`` 编码。
* 第 L549-L561 行：``buf_age`` 记录命令顺序；entry 从 IDLE 分配时，把已有 WAIT/CMD
  entry 标为更老。
* 第 L563-L574 行：``buf_rspage`` 记录 response 顺序；DONE_WAIT 的 response 用
  ``buf_rsp_pickage`` 选择。

接口关系：

* 被调用：状态机、obuf 和 NB return 逻辑使用这些 pointer。
* 调用：内部函数 ``f_Enc8to3``。
* 共享状态：共享 buffer state、ibuf、pipeline tag、age flops 和 force halt。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L595-L710``）：

.. code-block:: systemverilog

         // Buffer entry state machine
         always_comb begin
            buf_nxtstate[i]          = IDLE;
            buf_state_en[i]          = '0;
            buf_resp_state_bus_en[i] = '0;
            buf_state_bus_en[i]      = '0;
            buf_wr_en[i]             = '0;
            buf_data_in[i]           = '0;
            buf_data_en[i]           = '0;
            buf_error_en[i]          = '0;
            buf_rst[i]               = dec_tlu_force_halt;
            buf_ldfwd_en[i]          = dec_tlu_force_halt;
            buf_ldfwd_in[i]          = '0;

逐段解释：

* 第 L595-L609 行：每个 entry 的 next state、enable、data、error、reset 和 load-forward
  控制先设默认值。
* 第 L610-L637 行：IDLE 分配新 entry，WAIT 等 bus clock，CMD 等待 obuf 发出命令并可进入
  RESP 或 DONE_WAIT。
* 第 L638-L657 行：RESP 接收 read/write response。write 在非 AXI native write error 时可回到
  IDLE；dual load 可能进入 DONE_PARTIAL；需要等待 NB return 仲裁时进入 DONE_WAIT。
* 第 L658-L676 行：DONE_PARTIAL 等另一半 dual load，DONE_WAIT 等 response 顺序，
  DONE 在 NB-load data/error 被消费后 reset。
* 第 L693-L710 行：状态、age、dual tag、side-effect、size、address、byteen、data 和
  error 用 flops 保存。

接口关系：

* 被调用：obuf、NB return、full/empty 和 imprecise error 逻辑读取 entry state。
* 调用：寄存器原语 ``rvdffs``、``rvdff``、``rvdffe``、``rvdffsc``。
* 共享状态：共享 bus response、obuf tag、force halt、NB return thread 和 entry fields。

§8.4  NB-load return、imprecise error 和 ordering
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 DONE entry 中生成 NB-load return data/error/tag，检测 side-effect pending 和
same-address pending，并输出 imprecise load/store error。

关键代码（``rtl/design/lsu/eh2_lsu_bus_buffer.sv:L714-L797``）：

.. code-block:: systemverilog

      // buffer full logic
      always_comb begin
         buf_numvld_any[3:0] =  ({3'b0,(lsu_pkt_dc1_pre.valid & (lsu_pkt_dc1_pre.tid ~^ tid))} << (lsu_pkt_dc1_pre.valid & ldst_dual_dc1)) +
                                ({3'b0,(lsu_busreq_dc2 & (lsu_pkt_dc2.tid ~^ tid))} << (lsu_busreq_dc2 & ldst_dual_dc2)) +
                                ({3'b0,(lsu_busreq_dc3 & (lsu_pkt_dc3.tid ~^ tid))} << (lsu_busreq_dc3 & ldst_dual_dc3)) +
                                ({3'b0,(lsu_busreq_dc4 & (lsu_pkt_dc4.tid ~^ tid))} << (lsu_busreq_dc4 & ldst_dual_dc4)) +
                                ({3'b0,(lsu_busreq_dc5 & (lsu_pkt_dc5.tid ~^ tid))} << (lsu_busreq_dc5 & ldst_dual_dc5)) +
                                {3'b0,ibuf_valid};

逐段解释：

* 第 L714-L739 行：full/empty 统计把 DC1-DC5 管线预占、ibuf valid 和非 IDLE buffer entry
  都计入 ``buf_numvld_any``。``lsu_bus_buffer_full_any`` 在计数大于等于 ``DEPTH-1`` 时置位。
* 第 L741-L769 行：DONE entry 生成 NB-load ready/error/tag/data；dual load 的 hi/lo data
  被重新拼接并按地址 offset 对齐，再按 unsigned 和 size 扩展。
* 第 L771-L777 行：side-effect pending 覆盖 obuf 和 RESP entry，且受
  ``dec_tlu_sideeffect_posted_disable`` 控制。
* 第 L779-L785 行：AXI native 下检查 same 8-byte address 的 outstanding transaction，
  生成 ``bus_addr_match_pending``。
* 第 L787-L797 行：store imprecise error 从 DONE write error entry 生成；load imprecise
  error 来自 NB-load data error，且在 store error 存在时被屏蔽以保证一次只发一个错误。

接口关系：

* 被调用：``eh2_lsu_bus_intf`` 汇总 per-thread NB return 和 imprecise error。
* 调用：本节只使用组合逻辑。
* 共享状态：共享 buffer state、buffer data/error、side-effect、obus、AXI native 参数和
  NB-load data tid。

§9  ``eh2_lsu_ecc.sv`` ECC 编码与纠正
--------------------------------------

``eh2_lsu_ecc`` 负责 DCCM SEC/DED 数据路径。它从 DCCM lo/hi bank 读出数据和 ECC，
调用 ``rvecc_decode`` 得到纠正数据和 single/double 错误标志，再调用
``rvecc_encode`` 为写回数据生成 ECC。

§9.1  ECC check enable 和 store merge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：判断本周期 DCCM load/store 是否需要 ECC 检查，并把 store data 与 corrected read
data 按 byte enable 合并。

关键代码（``rtl/design/lsu/eh2_lsu_ecc.sv:L107-L140``）：

.. code-block:: systemverilog

      assign ldst_dual_dc3 = (lsu_addr_dc3[2] != end_addr_dc3[2]);
      assign is_ldst_dc3 = lsu_pkt_dc3.valid & (lsu_pkt_dc3.load | lsu_pkt_dc3.store) & addr_in_dccm_dc3 & lsu_dccm_rden_dc3;
      assign is_ldst_lo_dc3 = is_ldst_dc3 & ~(dec_tlu_core_ecc_disable | disable_ecc_check_lo_dc3);
      assign is_ldst_hi_dc3 = is_ldst_dc3 & (ldst_dual_dc3 | lsu_pkt_dc3.dma) & ~(dec_tlu_core_ecc_disable | disable_ecc_check_hi_dc3);

      assign ldst_byteen_dc3[7:0] = ({8{lsu_pkt_dc3.by}}   & 8'b0000_0001) |
                                    ({8{lsu_pkt_dc3.half}} & 8'b0000_0011) |
                                    ({8{lsu_pkt_dc3.word}} & 8'b0000_1111) |
                                    ({8{lsu_pkt_dc3.dword}} & 8'b1111_1111);
      assign store_byteen_dc3[7:0] = ldst_byteen_dc3[7:0] & {8{~lsu_pkt_dc3.load}};

逐段解释：

* 第 L107-L110 行：ECC check 只对 valid load/store、DCCM address 且 DCCM read enable
  的访问打开。lo/hi 可被 ``dec_tlu_core_ecc_disable`` 或 disable-ecc-check 信号关闭。
* 第 L112-L120 行：根据访问大小生成 8-bit byte enable，再按地址低位拆成 hi/lo byte enable。
* 第 L122-L124 行：store data 被按地址低位左移，形成 hi/lo 两个 DCCM data 部分。
* 第 L127-L132 行：每个 byte 在 store byte enable 为 1 时选择 store data，否则选择
  ``sec_data_*`` corrected readout。源码注释说明 load 场景 store byte enable 为 0。
* 第 L134-L140 行：DCCM write data 在 DMA、ECC 修复和 stbuf drain 之间选择，并附加新编码的 ECC。

接口关系：

* 被调用：``eh2_lsu_dccm_ctl`` 读取 ``sec_data_*``、``store_ecc_data_*`` 和 ECC 错误。
* 调用：后续实例化 ``rvecc_decode`` 和 ``rvecc_encode``。
* 共享状态：共享 DC3 packet、DCCM read data/ECC、ECC disable、DMA write data 和 stbuf data。

§9.2  ECC decode、encode 和错误输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 DCCM 启用时实例化 hi/lo ECC 解码器和编码器；DCCM 关闭时将相关输出置零。

关键代码（``rtl/design/lsu/eh2_lsu_ecc.sv:L142-L190``）：

.. code-block:: systemverilog

      if (pt.DCCM_ENABLE == 1) begin: Gen_dccm_enable
         //Detect/Repair for Hi/Lo
         rvecc_decode lsu_ecc_decode_hi (
            // Inputs
            .en(is_ldst_hi_dc3),
            .sed_ded (1'b0),    // 1 : means only detection
            .din(dccm_data_hi_dc3[pt.DCCM_DATA_WIDTH-1:0]),
            .ecc_in(dccm_data_ecc_hi_dc3[pt.DCCM_ECC_WIDTH-1:0]),
            // Outputs
            .dout(sec_data_hi_dc3[pt.DCCM_DATA_WIDTH-1:0]),
            .ecc_out (ecc_out_hi_nc[6:0]),
            .single_ecc_error(single_ecc_error_hi_raw_dc3),
            .double_ecc_error(double_ecc_error_hi_dc3),
            .*
         );

逐段解释：

* 第 L142-L170 行：DCCM 启用时，hi 和 lo 各实例化一个 ``rvecc_decode``，输入分别为
  DCCM data 和 ECC，输出 corrected data、single error 和 double error。
* 第 L172-L185 行：hi 和 lo 各实例化一个 ``rvecc_encode``，为 ``dccm_wr_data_*``
  的 data 部分生成 ECC。
* 第 L187-L190 行：hi single ECC 需要 ``ldst_dual_dc3`` 才有效；lo single ECC 不需要。
  single error 在 misaligned/access fault 时被屏蔽；double error 合并 hi/lo。
* 第 L192-L193 行：single ECC 修复需要在 DC5 后保留 corrected data，因此用
  ``rvdffe`` 保存 ``sec_data_*_dc5``。
* 第 L195-L207 行：DCCM 关闭时 corrected data、single/double error 和 saved data 全部置零。

接口关系：

* 被调用：DCCM control 和 LSC control 读取 ECC error 和 corrected data。
* 调用：实例化 ``rvecc_decode``、``rvecc_encode`` 和 ``rvdffe``。
* 共享状态：共享 ``pt.DCCM_ENABLE``、``pt.DCCM_DATA_WIDTH``、``pt.DCCM_ECC_WIDTH``、
  DCCM read/write data 和 fault 状态。

§10  ``eh2_lsu_amo.sv`` AMO 运算
--------------------------------

``eh2_lsu_amo`` 只在 ``pt.ATOMIC_ENABLE == 1`` 时由顶层实例化。它在 DC3 解码
``lsu_pkt_dc3.atomic_instr[4:0]``，用 DCCM corrected data 作为 operand1、store data
作为 operand2，并输出写回 store path 的 ``amo_data_dc3``。

§10.1  AMO decode、logic/add/minmax 和 final mux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：解码 AMO 类型，计算 logical、add、min/max 和 swap/SC 结果，并用 one-hot 风格
mask 组合成 ``amo_data_dc3``。

关键代码（``rtl/design/lsu/eh2_lsu_amo.sv:L70-L88``）：

.. code-block:: systemverilog

      // decode the instruction type
      assign amo_sc_dc3     = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd3);

      assign amo_add_dc3    = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd0);
      assign amo_max_dc3    = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd20);
      assign amo_maxu_dc3   = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd28);
      assign amo_min_dc3    = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd16);
      assign amo_minu_dc3   = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd24);
      assign amo_xor_dc3    = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd4);
      assign amo_or_dc3     = lsu_pkt_dc3.valid & lsu_pkt_dc3.atomic & (lsu_pkt_dc3.atomic_instr[4:0] == 5'd8);

逐段解释：

* 第 L70-L81 行：AMO 类型由 ``atomic_instr[4:0]`` 解码，且每个类型都要求 packet valid
  和 atomic 为 1。
* 第 L83-L87 行：``amo_minmax_sel_dc3`` 和 ``logic_sel`` 汇总 min/max 和 logical 类操作，
  operand1 来自 ``lsu_dccm_data_corr_dc3``，operand2 来自 ``store_data_dc3``。
* 第 L91-L93 行：AND/OR/XOR 结果在 ``logical_out`` 中组合。
* 第 L101-L112 行：ADD 和 min/max 共用加法/比较结果；unsigned 与 signed 比较由
  ``lsu_pkt_dc3.unsign`` 和符号位组合决定。
* 第 L115-L118 行：final mux 在 logical、add、min/max、swap/SC 之间选择。
  SWAP 和 SC 都选择 operand2。

接口关系：

* 被调用：``eh2_lsu_dccm_ctl`` 在 AMO store data 选择中读取 ``amo_data_dc3``。
* 调用：本模块不实例化下级模块。
* 共享状态：读取 DC3 packet、DCCM corrected data、store data 和 PIC address 标记。

§11  ``eh2_lsu_trigger.sv`` LSU trigger
---------------------------------------

``eh2_lsu_trigger`` 对 LSU load/store 地址或 store data 做 trigger match。它接收 DEC
提供的 ``trigger_pkt_any``，根据当前 packet 的 tid 选择 4 个 trigger，并用
``rvmaskandmatch`` 进行掩码匹配。

§11.1  trigger enable、match data 和 mask match
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：先检查所有线程 trigger 的 ``m`` bit 是否打开，再为每个 trigger 选择 address 或
store data，最后输出 DC4 match。

关键代码（``rtl/design/lsu/eh2_lsu_trigger.sv:L173-L200``）：

.. code-block:: systemverilog

      // Generate the trigger enable
      always_comb begin
         trigger_enable = 1'b0;
         for (int i=0; i<pt.NUM_THREADS; i++) begin
            for (int j=0; j<4; j++) begin
               trigger_enable |= trigger_pkt_any[i][j].m;
            end
         end
      end

      assign trigger_store_data_dc3[31:0] = (lsu_pkt_dc3.atomic ? amo_data_dc3[31:0] : store_data_dc3[31:0]) & {32{trigger_enable}};
      assign store_data_trigger_dc3[31:0] = { ({16{lsu_pkt_dc3.word | lsu_pkt_dc3.dword}} & trigger_store_data_dc3[31:16]), ({8{(lsu_pkt_dc3.half | lsu_pkt_dc3.word | lsu_pkt_dc3.dword)}} & trigger_store_data_dc3[15:8]), trigger_store_data_dc3[7:0]};

逐段解释：

* 第 L173-L181 行：``trigger_enable`` 是所有线程、4 个 trigger 的 ``m`` bit OR。
* 第 L183-L184 行：store trigger data 对 atomic 选择 ``amo_data_dc3``，否则选择
  ``store_data_dc3``；随后按访问大小截断高位。
* 第 L186-L188 行：地址 match data 使用 DC4 地址；store data 从 DC3 flopped 到 DC4。
* 第 L190-L199 行：按 ``lsu_pkt_dc4.tid`` 选择该线程 4 个 trigger。``select`` 为 0 时
  用地址，``select`` 且 store 时用 store data；``rvmaskandmatch`` 输出 data match，
  再与 load/store 类型、valid、非 DMA 条件组合成 ``lsu_trigger_match_dc4``。

接口关系：

* 被调用：TLU/debug trigger 逻辑读取 ``lsu_trigger_match_dc4``。
* 调用：实例化 4 个 ``rvmaskandmatch``，并使用 ``rvdffe`` 保存 store trigger data。
* 共享状态：读取 trigger packet、DC3/DC4 LSU packet、地址、store data 和 AMO data。

§12  ``eh2_lsu_clkdomain.sv`` 时钟门控
--------------------------------------

``eh2_lsu_clkdomain`` 统一生成 LSU 管线、store、DCCM、PIC、store buffer、bus buffer 和
free clock。源码中 C1 clock 多用于数据路径，C2 clock 多用于 valid/控制状态，具体用途由
各调用处的 clock 端口决定。

§12.1  DC1-DC5、store、stbuf 和 bus 时钟 enable
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 packet valid、DMA、store、atomic、LR station、buffer 非空和 force halt
生成各路 clock enable，再通过 ``rvoclkhdr`` 或 ``rvclkhdr`` 生成 gated clock。

关键代码（``rtl/design/lsu/eh2_lsu_clkdomain.sv:L324-L363``）：

.. code-block:: systemverilog

      // Also use the flopped clock enable. We want to turn on the clocks from dc1->dc5 even if there is a freeze
      assign lsu_c1_dc1_clken = lsu_p.valid | clk_override;
      assign lsu_c1_dc2_clken = lsu_pkt_dc1.valid | dma_dccm_req | lsu_c1_dc1_clken_q | clk_override;
      assign lsu_c1_dc3_clken = lsu_pkt_dc2.valid | lsu_c1_dc2_clken_q | clk_override;
      assign lsu_c1_dc4_clken = lsu_pkt_dc3.valid | lsu_c1_dc3_clken_q | clk_override;
      assign lsu_c1_dc5_clken = lsu_pkt_dc4.valid | lsu_c1_dc4_clken_q | clk_override;

      assign lsu_c2_dc1_clken = lsu_c1_dc1_clken | lsu_c1_dc1_clken_q | clk_override;
      assign lsu_c2_dc2_clken = lsu_c1_dc2_clken | lsu_c1_dc2_clken_q | clk_override;
      assign lsu_c2_dc3_clken = lsu_c1_dc3_clken | lsu_c1_dc3_clken_q | clk_override;
      assign lsu_c2_dc4_clken = lsu_c1_dc4_clken | lsu_c1_dc4_clken_q | clk_override;
      assign lsu_c2_dc5_clken = lsu_c1_dc5_clken | lsu_c1_dc5_clken_q | clk_override;

逐段解释：

* 第 L324-L329 行：C1 clock enable 从当前或上一级 packet valid 推进，并保留上一拍
  enable，源码注释说明 freeze 时也要打开 DC1-DC5 clock。
* 第 L331-L335 行：C2 clock enable 是 C1 当前/上一拍 enable 的 OR，再加
  ``clk_override``。
* 第 L337-L343 行：store C1 clocks 只在 store、atomic 或 DMA write 活动时打开；
  stbuf clock 在 store buffer 入队、drain、flushed drain 或 override 时打开。
* 第 L344-L356 行：每线程 ibuf、obuf 和 bus buffer clock enable 根据该线程 bus request、
  buffer pending、buffer empty 和 force halt 生成。
* 第 L358-L363 行：DCCM/PIC clock 根据 DC2 地址区域打开；free clock 还观察 LR station、
  bus buffer 和 store buffer 非空。

接口关系：

* 被调用：LSU 各子模块使用本模块输出的 clocks。
* 调用：后续实例化 ``rvoclkhdr`` 和 ``rvclkhdr``。
* 共享状态：共享 packet valid、DMA、address region、buffer empty/pending、LR valid 和
  ``clk_override``。

关键代码（``rtl/design/lsu/eh2_lsu_clkdomain.sv:L374-L403``）：

.. code-block:: systemverilog

      // Clock Headers
      rvoclkhdr lsu_c1dc1_cgc ( .en(lsu_c1_dc1_clken), .l1clk(lsu_c1_dc1_clk), .* );
      rvoclkhdr lsu_c1dc2_cgc ( .en(lsu_c1_dc2_clken), .l1clk(lsu_c1_dc2_clk), .* );
      rvoclkhdr lsu_c1dc3_cgc ( .en(lsu_c1_dc3_clken), .l1clk(lsu_c1_dc3_clk), .* );
      rvoclkhdr lsu_c1dc4_cgc ( .en(lsu_c1_dc4_clken), .l1clk(lsu_c1_dc4_clk), .* );
      rvoclkhdr lsu_c1dc5_cgc ( .en(lsu_c1_dc5_clken), .l1clk(lsu_c1_dc5_clk), .* );

      rvoclkhdr lsu_c2dc1_cgc ( .en(lsu_c2_dc1_clken), .l1clk(lsu_c2_dc1_clk), .* );
      rvoclkhdr lsu_c2dc2_cgc ( .en(lsu_c2_dc2_clken), .l1clk(lsu_c2_dc2_clk), .* );
      rvoclkhdr lsu_c2dc3_cgc ( .en(lsu_c2_dc3_clken), .l1clk(lsu_c2_dc3_clk), .* );
      rvoclkhdr lsu_c2dc4_cgc ( .en(lsu_c2_dc4_clken), .l1clk(lsu_c2_dc4_clk), .* );
      rvoclkhdr lsu_c2dc5_cgc ( .en(lsu_c2_dc5_clken), .l1clk(lsu_c2_dc5_clk), .* );

逐段解释：

* 第 L374-L385 行：C1/C2 DC1-DC5 gated clocks 全部通过 ``rvoclkhdr`` 生成。
* 第 L387-L391 行：store DC1-DC3 和 store buffer clock 也使用 ``rvoclkhdr``。
* 第 L393-L399 行：bus master clock enable 观察 bus buffer 非空、bus idle、force halt、
  DC5 bus request 和 ``lsu_bus_clk_en``；非 FPGA optimize 时用 ``rvclkhdr`` 生成
  ``lsu_busm_clk``。
* 第 L400-L403 行：DCCM、PIC 和 free clocks 使用 ``rvoclkhdr``。

接口关系：

* 被调用：``eh2_lsu_lsc_ctl``、``eh2_lsu_dccm_ctl``、``eh2_lsu_stbuf``、
  ``eh2_lsu_bus_intf`` 和 ``eh2_lsu_bus_buffer`` 均使用这些 clocks。
* 调用：``rvoclkhdr``、``rvclkhdr``。
* 共享状态：共享 clock enable flops、scan mode、override 和 reset。

§13  ``eh2_lsu_dccm_mem.sv`` DCCM SRAM wrapper
----------------------------------------------

``eh2_lsu_dccm_mem`` 是 LSU DCCM memory wrapper。它根据 DCCM bank 数和 index depth
实例化不同容量的 SRAM macro 或 Verilator RAM，并为非对齐访问选择 lo/hi bank 输出。

§13.1  bank select、macro 选择和 read data mux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 read/write 地址选择 DCCM bank、地址、写数据和 clock enable，并按
``DCCM_INDEX_DEPTH`` 实例化对应 RAM。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L69-L96``）：

.. code-block:: systemverilog

      localparam DCCM_WIDTH_BITS = $clog2(pt.DCCM_BYTE_WIDTH);
      localparam DCCM_INDEX_BITS = (pt.DCCM_BITS - pt.DCCM_BANK_BITS - pt.DCCM_WIDTH_BITS);
      localparam DCCM_INDEX_DEPTH = (((pt.DCCM_SIZE)*1024)>>($clog2(pt.DCCM_BYTE_WIDTH)))>>$clog2((pt.DCCM_NUM_BANKS));  // Depth of memory bank


      logic [pt.DCCM_NUM_BANKS-1:0]                                        wren_bank;
      logic [pt.DCCM_NUM_BANKS-1:0]                                        rden_bank;
      logic [pt.DCCM_NUM_BANKS-1:0] [pt.DCCM_BITS-1:(pt.DCCM_BANK_BITS+2)] addr_bank;
      logic [pt.DCCM_BITS-1:(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)]           rd_addr_even, rd_addr_odd;
      logic                                                                rd_unaligned, wr_unaligned;
      logic [pt.DCCM_NUM_BANKS-1:0] [pt.DCCM_FDATA_WIDTH-1:0]              dccm_bank_dout;
      logic [pt.DCCM_FDATA_WIDTH-1:0]                                      wrdata;

逐段解释：

* 第 L69-L71 行：DCCM bank index depth 根据 DCCM size、byte width 和 bank 数计算。
* 第 L74-L84 行：每个 bank 有独立 read/write enable、地址、data out 和 read data
  bank select。
* 第 L95-L96 行：read/write 非对齐只比较 lo/hi 地址中的 bank bits 是否不同。

接口关系：

* 被调用：MEM 顶层或 DCCM 集成逻辑实例化该 wrapper。
* 调用：后续 generate block 实例化 RAM macro。
* 共享状态：共享 ``pt.DCCM_*`` 参数和 DCCM read/write address/data。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L99-L130``）：

.. code-block:: systemverilog

      // 8 Banks, 16KB each (2048 x 72)
      for (genvar i=0; i<pt.DCCM_NUM_BANKS; i++) begin: mem_bank
         assign  wren_bank[i]        = dccm_wren & ((dccm_wr_addr_hi[2+:pt.DCCM_BANK_BITS] == i) | (dccm_wr_addr_lo[2+:pt.DCCM_BANK_BITS] == i));
         assign  rden_bank[i]        = dccm_rden & ((dccm_rd_addr_hi[2+:pt.DCCM_BANK_BITS] == i) | (dccm_rd_addr_lo[2+:pt.DCCM_BANK_BITS] == i));
         assign  addr_bank[i][(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] = rden_bank[i] ? (((dccm_rd_addr_hi[2+:pt.DCCM_BANK_BITS] == i) & rd_unaligned) ?
                                                                                                           dccm_rd_addr_hi[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] :
                                                                                                           dccm_rd_addr_lo[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS]) :
                                                                                                     (((dccm_wr_addr_hi[2+:pt.DCCM_BANK_BITS] == i) & wr_unaligned) ?
                                                                                                           dccm_wr_addr_hi[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS] :
                                                                                                           dccm_wr_addr_lo[(pt.DCCM_BANK_BITS+DCCM_WIDTH_BITS)+:DCCM_INDEX_BITS]);

逐段解释：

* 第 L99-L102 行：每个 bank 的 read/write enable 由全局 rden/wren 和 lo/hi 地址 bank
  命中共同决定。
* 第 L103-L108 行：bank address 在 read 时从 read hi/lo 中选择，在 write 时从 write hi/lo
  中选择；非对齐访问且 hi 地址命中该 bank 时使用 hi 地址。
* 第 L111 行：write data 也根据 write hi 地址命中和 ``wr_unaligned`` 在 hi/lo data 中选择。
* 第 L113-L115 行：每个 bank clock enable 是该 bank rden、wren 或 ``clk_override``。
* 第 L117-L130 行：``VERILATOR`` 下实例化通用 ``eh2_ram``，并传入本地 DCCM RAM test ports。

接口关系：

* 被调用：DCCM read/write 端口驱动 bank enable。
* 调用：实例化 ``eh2_ram`` 或不同深度的 ``ram_*x39`` macro。
* 共享状态：共享 lo/hi address、lo/hi data、DCCM test packet 和 bank outputs。

关键代码（``rtl/design/lsu/eh2_lsu_dccm_mem.sv:L286-L315``）：

.. code-block:: systemverilog

      // Flops
      rvdffs  #(pt.DCCM_BANK_BITS) rd_addr_lo_ff (.*, .din(dccm_rd_addr_lo[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .dout(dccm_rd_addr_lo_q[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .en(1'b1), .clk(active_clk));
      rvdffs  #(pt.DCCM_BANK_BITS) rd_addr_hi_ff (.*, .din(dccm_rd_addr_hi[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .dout(dccm_rd_addr_hi_q[DCCM_WIDTH_BITS+:pt.DCCM_BANK_BITS]), .en(1'b1), .clk(active_clk));

      // For Plus1 --> Read data comes out 2 cycle after dccm_rden since we need to flop the bank data and then mux between the banks
      if (pt.LOAD_TO_USE_PLUS1 == 1) begin: GenL2U_1
         logic                                                          dccm_rden_q;
         logic [pt.DCCM_NUM_BANKS-1:0] [pt.DCCM_FDATA_WIDTH-1:0]        dccm_bank_dout_q;
         logic [(DCCM_WIDTH_BITS+pt.DCCM_BANK_BITS-1):DCCM_WIDTH_BITS]  dccm_rd_addr_lo_q2;
         logic [(DCCM_WIDTH_BITS+pt.DCCM_BANK_BITS-1):DCCM_WIDTH_BITS]  dccm_rd_addr_hi_q2;

逐段解释：

* 第 L286-L288 行：read lo/hi bank select 被寄存到 ``active_clk``。
* 第 L290-L307 行：``LOAD_TO_USE_PLUS1`` 打开时，read data 多打一拍到
  ``dccm_bank_dout_q``，再按第二级 bank select mux 出 lo/hi read data。
* 第 L308-L315 行：``LOAD_TO_USE_PLUS1`` 关闭时，read data 直接从 bank dout 和一级
  bank select mux 出；未使用的二级地址置零。

接口关系：

* 被调用：上层 DCCM control 读取 ``dccm_rd_data_lo`` 和 ``dccm_rd_data_hi``。
* 调用：寄存器原语 ``rvdffs``、``rvdffe``。
* 共享状态：共享 ``pt.LOAD_TO_USE_PLUS1``、DCCM bank outputs 和 read address flops。

§14  端到端时序关系
-------------------

本节只把前面源码关系串成时序图，不引入新行为。

§14.1  DCCM load 与 store buffer 前递
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 DCCM load 在 DC2 比较 stbuf/pipe store，在 DC3 取数据并由 LSC 生成
``lsu_result_dc3``。

.. code-block:: text

   cycle N:
     DC1: eh2_lsu_lsc_ctl computes lsu_addr_dc1/end_addr_dc1
     DC1: eh2_lsu_addrcheck predicts DCCM/PIC/external region

   cycle N+1:
     DC2: eh2_lsu_stbuf compares lsu_addr_dc2/end_addr_dc2
     DC2: eh2_lsu_addrcheck reports access_fault/misaligned

   cycle N+2:
     DC3: eh2_lsu_dccm_ctl merges DCCM data and stbuf_fwddata
     DC3: eh2_lsu_ecc decodes DCCM ECC
     DC3: eh2_lsu_lsc_ctl selects lsu_result_dc3

   cycle N+3:
     DC4: lsu_result_corr_dc4 is available for corrected writeback path

接口关系：

* DC1 地址来自 ``eh2_lsu_lsc_ctl.sv:L221-L247``。
* DC2 compare 来自 ``eh2_lsu_stbuf.sv:L319-L354``。
* DC3 merge 来自 ``eh2_lsu_dccm_ctl.sv:L202-L218``。
* DC3 result mux 来自 ``eh2_lsu_lsc_ctl.sv:L289-L308``。

§14.2  external NB-load 与 bus buffer return
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 external load 在 DC1 创建 NB-load CAM tag，bus buffer DONE entry 返回 data/error。

.. code-block:: text

   DC1:
     lsu_busreq_dc1
       -> lsu_nonblock_load_valid_dc1
       -> lsu_nonblock_load_tag_dc1 = WrPtr0_dc1[tid]

   DC2:
     if full forwarding hit:
       lsu_nonblock_load_inv_dc2 = 1
       no external AXI request continues

   bus buffer:
     IDLE/WAIT/CMD/RESP/DONE_PARTIAL/DONE_WAIT/DONE
       -> lsu_nonblock_load_data_valid or data_error
       -> lsu_nonblock_load_data_tag
       -> lsu_nonblock_load_data

   DEC side:
     NB-load CAM receives return by tid/tag

接口关系：

* NB-load create/invalidate 来自 ``eh2_lsu_bus_intf.sv:L418-L424``。
* bus buffer state 来自 ``eh2_lsu_bus_buffer.sv:L595-L710``。
* NB return data 来自 ``eh2_lsu_bus_buffer.sv:L741-L769``。
* return thread mux 来自 ``eh2_lsu_bus_intf.sv:L567-L578``。

§14.3  LR/SC 和 AMO store path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 atomic 启用时 AMO 和 LR/SC 如何共享 DCCM load/store 路径。

.. code-block:: text

   LR:
     DC5 commit and lsu_pkt_dc5.lr
       -> lr_wr_en[tid]
       -> lr_addr[tid] = lsu_addr_dc5[31:2]
       -> lr_vld[tid] = 1

   SC:
     DC5 valid and lsu_pkt_dc5.sc
       -> compare lsu_addr_dc5[31:2] with lr_addr[tid]
       -> lsu_sc_success_dc5
       -> store_stbuf_reqvld_dc5 only if SC success or ECC repair condition

   AMO:
     DC3 eh2_lsu_amo computes amo_data_dc3
       -> eh2_lsu_dccm_ctl selects AMO data for store_data_lo/hi
       -> DC5 store buffer or DCCM path writes result

接口关系：

* LR/SC reservation 来自 ``eh2_lsu_lsc_ctl.sv:L396-L429``。
* AMO compute 来自 ``eh2_lsu_amo.sv:L70-L118``。
* AMO store data selection 来自 ``eh2_lsu_dccm_ctl.sv:L307-L310``。
* stbuf request 来自 ``eh2_lsu.sv:L388-L390``。

§15  参考资料
-------------

关联章节：

* :doc:`dec`
* :doc:`mem`
* :doc:`pic`
* :doc:`shared_axi4`

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_lsc_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_addrcheck.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_dccm_ctl.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_stbuf.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_bus_intf.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_bus_buffer.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_ecc.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_amo.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_trigger.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_clkdomain.sv`
* :file:`/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_dccm_mem.sv`

ADR 引用：

* :ref:`adr-0005`
* :ref:`adr-0006`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
