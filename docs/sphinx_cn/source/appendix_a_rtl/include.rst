.. _appendix_a_rtl_include:
.. _appendix_a_rtl/include:

头文件 / 类型定义（Include）- 详细参考
======================================

:status: draft
:source: rtl/design/include/eh2_def.sv
:last-reviewed: 2026-05-19

§1  文件边界
------------

``rtl/design/include/`` 在当前工作树中只有一个源文件：``eh2_def.sv``。该文件定义
``eh2_pkg`` package，并在 package 内集中放置 EH2 RTL 共享的 ``typedef enum``
和 ``typedef struct packed``。这些类型被 DEC、EXU、LSU、IFU、debug trigger、
trace、CSR/TLU 和 icache debug 诊断路径复用。

本章只描述实际存在的 ``rtl/design/include/eh2_def.sv``。当前工作树没有
``rtl/design/include/eh2_param.vh``；能通过 ``find`` 找到的参数头文件位于
``syn/include/eh2_param.vh``，不属于本章源文件边界。因此，本章不把参数配置写成
``rtl/design/include`` 的内容。

§1.1  Filelist 入口
~~~~~~~~~~~~~~~~~~~

职责：确认 ``eh2_def.sv`` 在 UVM RTL filelist 中的位置。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L9-L9``）：

.. code-block:: systemverilog

   rtl/design/include/eh2_def.sv

逐段解释：

* 第 L9 行：filelist 直接列出 ``rtl/design/include/eh2_def.sv``，说明仿真编译会先看到 ``eh2_pkg`` 中的共享类型定义。

接口关系：

* 被调用：RTL 仿真构建通过 ``eh2_rtl.f`` 纳入该 package。
* 调用：本文件不实例化模块。
* 共享状态：该文件没有寄存器状态，只提供类型名和字段布局。

§1.2  Package 声明与总体结构
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 ``eh2_pkg``，并在 package 内包含全部共享 typedef。

关键代码（``rtl/design/include/eh2_def.sv:L1-L19``）：

.. code-block:: systemverilog

   //`ifndef  EH2_DEF_SV
   //`define  EH2_DEF_SV

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

逐段解释：

* 第 L1-L2 行：传统 include guard 被注释掉，实际生效边界是第 L4 行的 SystemVerilog package。
* 第 L4 行：``package eh2_pkg`` 是所有 typedef 的命名空间。
* 第 L6-L19 行：第一个 typedef 是 ``eh2_trace_pkt_t``，同时定义 trace valid、instruction、address、exception、interrupt、tval 和 verification-only rd writeback 字段。

接口关系：

* 被调用：其它 RTL 文件通过 package 作用域使用这些类型。
* 调用：本片段没有子模块或函数调用。
* 共享状态：``eh2_trace_pkt_t`` 是 DEC trace 输出与验证 trace/cosim 观测之间的结构化接口。

§2  Trace 与错误状态类型
------------------------

本节覆盖 ``eh2_trace_pkt_t``、错误状态 enum、instruction class enum 以及早期队列/预测相关小包。

§2.1  ``eh2_trace_pkt_t`` - retire trace 包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：承载每线程双槽位 trace 输出以及 verification-only register writeback 字段。

关键代码（``rtl/design/include/eh2_def.sv:L6-L19``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 L7-L13 行：trace 包每个字段都带 ``i`` 前缀，宽度覆盖双槽位 valid、instruction、address、exception、ecause、interrupt 和 tval。
* 第 L14-L18 行：注释明确这些 rd 字段是 verification-only RVFI-equivalent register writeback signals，lane 0 对应 i0，lane 1 对应 i1。
* 第 L19 行：typedef 名称为 ``eh2_trace_pkt_t``，后续 DEC 和顶层按 ``pt.NUM_THREADS`` 扩展为 per-thread 数组。

接口关系：

* 被调用：``eh2_dec`` 输出 ``trace_rv_trace_pkt``，``eh2_veer`` 中也声明同名数组。
* 调用：本类型不调用子模块。
* 共享状态：trace 包在 DEC/trace monitor/cosim 路径中共享，尤其 ``trace_rv_i_rd_*`` 字段用于验证侧写回对齐。

§2.2  Trace 包在顶层与 DEC 的连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 ``eh2_trace_pkt_t`` 如何从 DEC 暴露到 core 顶层。

关键代码（``rtl/design/eh2_veer.sv:L930-L934``）：

.. code-block:: systemverilog

   logic [31:0]                  lsu_rs1_dc1;

   logic                         dec_extint_stall;

   eh2_trace_pkt_t  [pt.NUM_THREADS-1:0] trace_rv_trace_pkt;

逐段解释：

* 第 L934 行：顶层把 ``eh2_trace_pkt_t`` 扩展为 ``[pt.NUM_THREADS-1:0]`` 数组，说明 trace 包按 hart/thread 维度输出。

关键代码（``rtl/design/dec/eh2_dec.sv:L426-L429``）：

.. code-block:: systemverilog

   input logic [pt.NUM_THREADS-1:0] [15:0] ifu_i0_cinst,                  // 16b compressed instruction
   input logic [pt.NUM_THREADS-1:0] [15:0] ifu_i1_cinst,

   output eh2_trace_pkt_t  [pt.NUM_THREADS-1:0] trace_rv_trace_pkt,             // trace packet

逐段解释：

* 第 L429 行：DEC 模块把 ``trace_rv_trace_pkt`` 作为 output，类型与顶层声明一致。

接口关系：

* 被调用：``eh2_veer`` 声明数组并通过 DEC 实例连接。
* 调用：本节没有子模块调用。
* 共享状态：``trace_rv_trace_pkt`` 是 DEC 到 top-level trace 输出的结构化数据。

§2.3  错误状态 enum
~~~~~~~~~~~~~~~~~~~

职责：为性能/错误处理路径提供固定编码的 error state 类型。

关键代码（``rtl/design/include/eh2_def.sv:L22-L36``）：

.. code-block:: systemverilog

   typedef enum logic [2:0] {
                             ERR_IDLE   = 3'b000,
                             IC_WFF     = 3'b001,
                             ECC_WFF    = 3'b010,
                             ECC_CORR   = 3'b011,
                             DMA_SB_ERR = 3'b100
                            } eh2_perr_state_t;


   typedef enum logic [1:0] {
                             ERR_STOP_IDLE   = 2'b00,
                             ERR_FETCH1      = 2'b01,
                             ERR_FETCH2      = 2'b10,
                             ERR_STOP_FETCH  = 2'b11
                            } eh2_err_stop_state_t;

逐段解释：

* 第 L22-L28 行：``eh2_perr_state_t`` 是 3 bit enum，包含 idle、IC write/fetch fault、ECC write/fetch fault、ECC corrected 和 DMA system bus error 状态。
* 第 L31-L36 行：``eh2_err_stop_state_t`` 是 2 bit enum，包含 idle、两级 fetch 和 stop fetch 状态。

接口关系：

* 被调用：错误处理 RTL 可以使用这些 enum 作为状态类型。
* 调用：enum 类型没有调用关系。
* 共享状态：编码值固定写在 typedef 中，修改会影响使用该 enum 的状态机编码。

§2.4  ``eh2_inst_pkt_t`` - 指令类别枚举
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 PMU 或译码路径使用的指令类别压缩为 5 bit 枚举。

关键代码（``rtl/design/include/eh2_def.sv:L39-L59``）：

.. code-block:: systemverilog

   typedef enum logic [4:0] {
                            NULL     = 5'b00000,
                            MUL      = 5'b00001,
                            LOAD     = 5'b00010,
                            STORE    = 5'b00011,
                            ALU      = 5'b00100,
                            CSRREAD  = 5'b00101,
                            CSRWRITE = 5'b00110,
                            CSRRW    = 5'b00111,
                            EBREAK   = 5'b01000,
                            ECALL    = 5'b01001,
                            FENCE    = 5'b01010,
                            FENCEI   = 5'b01011,
                            MRET     = 5'b01100,
                            CONDBR   = 5'b01101,
                            JAL      = 5'b01110,
                            BITMANIPU   = 5'b01111,
                            ATOMIC   = 5'b10000,
                            LR       = 5'b10001,
                            SC       = 5'b10010
                             } eh2_inst_pkt_t;

逐段解释：

* 第 L39 行：``eh2_inst_pkt_t`` 的底层宽度是 5 bit。
* 第 L40-L58 行：枚举覆盖 null、mul、load/store、ALU、CSR read/write/RW、debug/trap、fence、branch/jal、bitmanip、atomic、LR 和 SC。
* 第 L59 行：typedef 名称用于后续 packet 字段，例如 trap packet 中的 PMU 指令类别字段。

接口关系：

* 被调用：``eh2_trap_pkt_t`` 在字段 ``pmu_i0_itype`` 和 ``pmu_i1_itype`` 中使用该 enum。
* 调用：enum 类型没有调用关系。
* 共享状态：该 enum 的编码是 PMU/trap packet 的字段编码基础。

§3  前端与分支预测类型
----------------------

前端类型覆盖 instruction buffer、branch prediction、branch-to-TLU 更新和 return stack 相关字段。

§3.1  ``eh2_load_cam_pkt_t`` 与 ``eh2_rets_pkt_t``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 NB-load CAM 条目字段，以及 return/call 路径使用的返回预测摘要。

关键代码（``rtl/design/include/eh2_def.sv:L61-L76``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic valid;
                          logic wb;
                          logic stall;
                          logic [2:0] tag;
                          logic [4:0] rd;
                          } eh2_load_cam_pkt_t;

   typedef struct packed {
                          logic pc0_call;
                          logic pc0_ret;
                          logic pc0_pc4;
                          logic pc1_call;
                          logic pc1_ret;
                          logic pc1_pc4;
                          } eh2_rets_pkt_t;

逐段解释：

* 第 L61-L67 行：``eh2_load_cam_pkt_t`` 描述一个 NB-load CAM 条目，包含有效、写回、stall、3 bit tag 和 5 bit rd。
* 第 L69-L76 行：``eh2_rets_pkt_t`` 分别记录 pc0 与 pc1 是否 call、ret 或 pc4。

接口关系：

* 被调用：LSU 或前端返回预测路径可用这些 packet 聚合相关状态。
* 调用：类型定义没有调用关系。
* 共享状态：``tag`` 和 ``rd`` 字段为 NB-load 写回关联提供结构化载荷。

§3.2  ``eh2_br_pkt_t`` 与 ``eh2_br_tlu_pkt_t``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：承载 IFU/DEC/EXU 分支预测和 TLU 更新所需的分支结果字段。

关键代码（``rtl/design/include/eh2_def.sv:L78-L87``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic ret;
                          logic [31:1] prett;  // predicted ret target
                          logic br_error;
                          logic br_start_error;
                          logic bank;
                          logic valid;
                          logic [1:0] hist;
                          logic way;
                          } eh2_br_pkt_t;

逐段解释：

* 第 L78-L87 行：``eh2_br_pkt_t`` 包含 return 标记、预测 return target、branch error、branch start error、bank、valid、2 bit history 和 way。

关键代码（``rtl/design/include/eh2_def.sv:L113-L122``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic valid;
                          logic [1:0] hist;
                          logic br_error;
                          logic br_start_error;
                          logic bank;
                          logic way;
                          logic middle;
                          logic tid;
                          } eh2_br_tlu_pkt_t;

逐段解释：

* 第 L113-L122 行：``eh2_br_tlu_pkt_t`` 用于写回或 TLU 更新路径，字段包含 valid、history、error、bank、way、middle 和 tid。

接口关系：

* 被调用：``eh2_veer`` 在分支信号区声明 ``eh2_br_tlu_pkt_t`` 和 ``eh2_br_pkt_t``。
* 调用：类型定义没有调用关系。
* 共享状态：branch prediction 与 TLU update 通过这些 packet 避免散落字段连接。

§3.3  ``eh2_ib_pkt_t`` - instruction buffer 条目
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 DEC instruction buffer 中每个条目的 instruction、PC、predecode、branch predict 与异常字段。

关键代码（``rtl/design/include/eh2_def.sv:L89-L111``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic lsu;
                          logic mul;
                          logic i0_only;
                          logic legal1;
                          logic legal2;
                          logic legal3;
                          logic legal4;
                          } eh2_predecode_pkt_t;


   typedef struct packed {
                         // ...
                         logic [31:1]         pc;
                         eh2_br_pkt_t         brp;
                         logic [31:0]         inst;
                         eh2_predecode_pkt_t predecode;
                         logic                pc4;
                         logic [15:0]         cinst;
                        } eh2_ib_pkt_t;

逐段解释：

* 第 L89-L97 行：``eh2_predecode_pkt_t`` 把 LSU、MUL、i0-only 和 4 个 legal 标志打包。
* 第 L100-L111 行：``eh2_ib_pkt_t`` 包含 instruction fetch/access fault 字段、PC、branch prediction packet、32 bit instruction、predecode、pc4 和 compressed instruction。
* 片段中省略了第 L100-L104 行部分字段，完整字段见源文件；省略不改变保留行的原文内容。

关键代码（``rtl/design/dec/eh2_dec_ib_ctl.sv:L198-L207``）：

.. code-block:: systemverilog

   eh2_ib_pkt_t ib3_in, ib3_final, ib3;
   eh2_ib_pkt_t ib2_in, ib2_final, ib2;
   eh2_ib_pkt_t ib1_in, ib1_final, ib1_final_in, ib1;
   eh2_ib_pkt_t ib0_in, ib0_final, ib0_final_in, ib0, ib0_raw, ibsave;

   logic                       debug_valid_d;
   logic mul_in, lsu_in, i0_only_in;

   eh2_ib_pkt_t ifu_i0_ibp, ifu_i1_ibp;

逐段解释：

* 第 L198-L201 行：DEC instruction buffer 控制器为 ib0-ib3、final、raw 和 save path 都使用 ``eh2_ib_pkt_t``。
* 第 L206 行：IFU 传入的 i0/i1 instruction buffer packet 也使用同一类型，说明该 typedef 是 IFU 到 DEC 的结构化边界。

接口关系：

* 被调用：``eh2_dec_ib_ctl`` 使用该类型保存和移动 instruction buffer 条目。
* 调用：``eh2_ib_pkt_t`` 嵌套使用 ``eh2_br_pkt_t`` 与 ``eh2_predecode_pkt_t``。
* 共享状态：``ib0`` 到 ``ib3`` 的 shift、cancel 和 write 逻辑都依赖同一字段布局。

§3.4  ``eh2_predict_pkt_t`` - branch prediction 包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：承载预测目标、history、bank/way、taken/mispredict、call/return/jump 和 error 信息。

关键代码（``rtl/design/include/eh2_def.sv:L124-L140``）：

.. code-block:: systemverilog

   typedef struct packed {// data bits - upper 19b not likely to change
                          logic [31:1] prett;
                          logic boffset;
                          logic [1:0] hist;
                          logic bank;
                          logic way;
                          // ctl bits
                          logic ataken;
                          logic valid;
                          logic pc4;
                          logic misp;
                          logic br_error;
                          logic br_start_error;
                          logic pcall;
                          logic pret;
                          logic pja;
                          } eh2_predict_pkt_t;

逐段解释：

* 第 L124-L129 行：前半段是 data bits，包括 predicted target、branch offset、history、bank 和 way。
* 第 L130-L140 行：后半段是 control bits，包括 actual taken、valid、pc4、mispredict、branch error、start error、predicted call/return/jump。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L342-L352``）：

.. code-block:: systemverilog

   output eh2_predict_pkt_t  i0_predict_p_d,        // i0 predict packet decode
   output eh2_predict_pkt_t  i1_predict_p_d,
   output logic [pt.BHT_GHR_SIZE-1:0]           i0_predict_fghr_d, // i0 predict fghr
   output logic [pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] i0_predict_index_d, // i0 predict index
   output logic [pt.BTB_BTAG_SIZE-1:0]          i0_predict_btag_d, // i0_predict branch tag
   output logic [pt.BTB_TOFFSET_SIZE-1:0]       i0_predict_toffset_d, // i0_predict branch tag

   output logic [pt.BHT_GHR_SIZE-1:0]           i1_predict_fghr_d, // i1 predict fghr
   output logic [pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] i1_predict_index_d, // i1 predict index
   output logic [pt.BTB_BTAG_SIZE-1:0]          i1_predict_btag_d, // i1_predict branch tag
   output logic [pt.BTB_TOFFSET_SIZE-1:0]       i1_predict_toffset_d, // i1_predict branch tag

逐段解释：

* 第 L342-L343 行：decode 控制器分别输出 i0/i1 的 ``eh2_predict_pkt_t``。
* 第 L344-L352 行：同一接口旁边还输出 fghr、BTB index、BTB tag 和 target offset，说明 ``eh2_predict_pkt_t`` 与 predictor metadata 一起传递到后续分支路径。

接口关系：

* 被调用：DEC decode 输出该 packet，EXU 和 IFU branch predictor 控制逻辑读取该 packet。
* 调用：类型定义没有调用关系。
* 共享状态：``valid``、``misp``、``hist``、``bank``、``way`` 等字段跨 DEC/EXU/IFU 传递。

§4  Decode、EXU 与 LSU 控制包
-----------------------------

本节覆盖主执行流水线中的控制 packet：trap/dest/class/reg、ALU packet、LSU packet、decode packet、MUL packet 和 DIV packet。

§4.1  ``eh2_trap_pkt_t`` 与 ``eh2_dest_pkt_t``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 trap/PMU 相关字段和写回目的寄存器字段结构化。

关键代码（``rtl/design/include/eh2_def.sv:L142-L199``）：

.. code-block:: systemverilog

   typedef struct packed {
                          // bits not likely to change for power
                          logic           i0icaf;
                          logic [1:0]     i0icaf_type;
                          logic           i0icaf_second;
                          logic           i0fence_i;
                          logic [3:0]     i0trigger;
                          logic [3:0]     i1trigger;
                          logic           pmu_i0_br_unpred;     // pmu
                          logic           pmu_i1_br_unpred;     // pmu
                          logic           pmu_divide;
                          logic           pmu_lsu_misaligned;
                          // bits likely to change for power
                          logic           i0legal;
                          logic           i0tid;
                          logic           i1tid;
                          logic           lsu_pipe0;
                          eh2_inst_pkt_t pmu_i0_itype;        // pmu - instruction type
                          eh2_inst_pkt_t pmu_i1_itype;        // pmu - instruction type
                          } eh2_trap_pkt_t;

逐段解释：

* 第 L142-L161 行：``eh2_trap_pkt_t`` 包含 icache access fault、trigger、PMU branch/divide/LSU 事件、legal/tid、LSU pipe 和两条指令的 PMU instruction type。``pmu_i0_itype`` 与 ``pmu_i1_itype`` 使用 ``eh2_inst_pkt_t``。

关键代码（``rtl/design/include/eh2_def.sv:L163-L199``）：

.. code-block:: systemverilog

   typedef struct packed {
                          // bits unlikely to change
                          logic i0sc;
                          logic i0div;
                          logic i0csrwen;
                          logic i0csrwonly;
                          logic i1sc;
                          logic [11:0] i0csrwaddr;
                          // less likely to toggle
                          logic [1:0] i0rs1bype2;
                          logic [1:0] i0rs2bype2;
                          // ...
                          logic [4:0] i0rd;
                          logic i0mul;
                          logic i0load;
                          logic i0store;
                          logic i0v;
                          logic i0valid;
                          logic i0secondary;
                          logic i0tid;
                          logic [4:0] i1rd;
                          logic i1mul;
                          logic i1load;
                          } eh2_dest_pkt_t;

逐段解释：

* 第 L163-L199 行：``eh2_dest_pkt_t`` 把 i0/i1 的 store-conditional、divide、CSR write、bypass、rd、mul/load/store、valid、secondary、tid 以及 LSU tid 打包。片段省略了中间若干 bypass 与 i1 字段，完整字段在源文件 L163-L199。

接口关系：

* 被调用：decode 和 TLU 路径可用这些 packet 传递 trap、PMU 和目的寄存器信息。
* 调用：``eh2_trap_pkt_t`` 调用 ``eh2_inst_pkt_t`` 作为字段类型。
* 共享状态：这些 packet 将 PMU、trap、destination 和 bypass 信息从 decode 推向后续控制路径。

§4.2  ``eh2_alu_pkt_t`` - ALU 控制包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：承载 ALU、branch、CSR、bitmanip 和 thread 标志，作为 DEC 到 EXU ALU 的控制载荷。

关键代码（``rtl/design/include/eh2_def.sv:L215-L261``）：

.. code-block:: systemverilog

   typedef struct packed {
                          // unlikely to change
                          logic clz;
                          logic ctz;
                          logic cpop;
                          logic sext_b;
                          logic sext_h;
                          logic min;
                          logic max;
                          logic pack;
                          logic packu;
                          logic packh;
                          logic rol;
                          logic ror;
                          logic grev;
                          logic gorc;
                          logic zbb;
                          logic bset;
                          logic bclr;
                          logic binv;
                          logic bext;
                          logic sh1add;
                          logic sh2add;
                          logic sh3add;
                          logic zba;

逐段解释：

* 第 L215-L239 行：ALU packet 前半段主要是 bitmanip 和 Zb* 相关控制位，包括 clz/ctz/cpop、sext、min/max、pack、rotate、grev/gorc、bit set/clear/invert/extract 和 shNadd。

关键代码（``rtl/design/include/eh2_def.sv:L240-L261``）：

.. code-block:: systemverilog

                          // likely to change
                          logic land;
                          logic lor;
                          logic lxor;
                          logic sll;
                          logic srl;
                          logic sra;
                          logic beq;
                          logic bne;
                          logic blt;
                          logic bge;
                          logic add;
                          logic sub;
                          logic slt;
                          logic unsign;
                          logic jal;
                          logic predict_t;
                          logic predict_nt;
                          logic csr_write;
                          logic csr_imm;
                          logic tid;
                          } eh2_alu_pkt_t;

逐段解释：

* 第 L240-L261 行：后半段包含逻辑/移位/比较/加减/无符号/跳转/预测/CSR/tid 控制位。注释按 toggle 可能性分区，RTL 后续用定制 flop 保存不同字段段。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L221-L222``）：

.. code-block:: systemverilog

   output eh2_alu_pkt_t i0_ap,                   // alu packets
   output eh2_alu_pkt_t i1_ap,

逐段解释：

* 第 L221-L222 行：decode 控制器输出 i0 和 i1 两个 ALU packet，名称分别是 ``i0_ap`` 与 ``i1_ap``。

关键代码（``rtl/design/exu/eh2_exu.sv:L499-L507``）：

.. code-block:: systemverilog

   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e1_ff (.*,  .clk(clk), .en(i0_e1_data_en), .din(i0_ap),   .dout(i0_ap_e1) );
   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e2_ff (.*,  .clk(clk), .en(i0_e2_data_en), .din(i0_ap_e1),.dout(i0_ap_e2) );
   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e3_ff (.*,  .clk(clk), .en(i0_e3_data_en), .din(i0_ap_e2),.dout(i0_ap_e3) );
   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e4_ff (.*,  .clk(clk), .en(i0_e4_data_en), .din(i0_ap_e3),.dout(i0_ap_e4) );

   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e1_ff (.*,  .clk(clk), .en(i1_e1_data_en), .din(i1_ap),   .dout(i1_ap_e1) );
   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e2_ff (.*,  .clk(clk), .en(i1_e2_data_en), .din(i1_ap_e1),.dout(i1_ap_e2) );
   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e3_ff (.*,  .clk(clk), .en(i1_e3_data_en), .din(i1_ap_e2),.dout(i1_ap_e3) );
   rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e4_ff (.*,  .clk(clk), .en(i1_e4_data_en), .din(i1_ap_e3),.dout(i1_ap_e4) );

逐段解释：

* 第 L499-L507 行：EXU 将 i0/i1 ALU packet 从 E1 推到 E4。每级用 ``$bits(eh2_alu_pkt_t)`` 计算宽度，说明字段布局变化会直接影响这些 pipeline flop 的宽度。

接口关系：

* 被调用：DEC 生成 ``i0_ap`` / ``i1_ap``，EXU ALU pipeline 保存并消费。
* 调用：类型定义没有调用关系；EXU 使用 ``rvdfflie`` 保存该类型。
* 共享状态：``eh2_alu_pkt_t`` 是 DEC 到 EXU 的 ALU 控制边界。

§4.3  ``eh2_lsu_pkt_t`` - LSU 控制包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：承载 load/store/atomic/LR/SC/DMA/size/bypass/thread/valid 等 LSU 控制位。

关键代码（``rtl/design/include/eh2_def.sv:L263-L294``）：

.. code-block:: systemverilog

   typedef struct packed {
                          // unlikely to change
                          logic atomic;               // this is atomic instruction
                          logic atomic64;
                          logic fast_int;
                          logic barrier;
                          logic lr;
                          logic sc;
                          logic [4:0] atomic_instr;   // this will be decoded to get which of the amo instruction lsu is doing
                          logic dma;               // dma pkt
                          // may change
                          logic by;
                          logic half;
                          logic word;
                          logic dword;
                          logic load;
                          logic store;
                          logic pipe;   // which pipe is load/store
                          logic unsign;
   /* verilator lint_off SYMRSVDWORD */
                          logic stack;
   /* verilator lint_on SYMRSVDWORD */
                          logic tid;
                          logic store_data_bypass_c1;

逐段解释：

* 第 L263-L272 行：前半段覆盖 atomic、atomic64、fast interrupt、barrier、LR、SC、5 bit AMO instruction 和 DMA packet 标志。
* 第 L274-L285 行：size、load/store、pipe、unsigned、stack 和 tid 是执行阶段更常变化的控制位；``stack`` 旁有 Verilator 保留字 lint 关闭/开启。

关键代码（``rtl/design/include/eh2_def.sv:L286-L294``）：

.. code-block:: systemverilog

                          logic store_data_bypass_c1;
                          logic load_ldst_bypass_c1;
                          logic store_data_bypass_c2;
                          logic store_data_bypass_i0_e2_c2;
                          logic [1:0] store_data_bypass_e4_c1;
                          logic [1:0] store_data_bypass_e4_c2;
                          logic [1:0] store_data_bypass_e4_c3;
                          logic valid;
                          } eh2_lsu_pkt_t;

逐段解释：

* 第 L286-L293 行：尾部字段全部是 LSU bypass 和 valid 控制，分别覆盖 C1/C2/C3 与 E4 到 C* 的 store data bypass。
* 第 L294 行：typedef 名称为 ``eh2_lsu_pkt_t``。

关键代码（``rtl/design/lsu/eh2_lsu_lsc_ctl.sv:L135-L145``）：

.. code-block:: systemverilog

   output eh2_lsu_pkt_t         lsu_pkt_dc1_pre,
   output eh2_lsu_pkt_t         lsu_pkt_dc1,
   output eh2_lsu_pkt_t         lsu_pkt_dc2,
   output eh2_lsu_pkt_t         lsu_pkt_dc3,
   output eh2_lsu_pkt_t         lsu_pkt_dc4,
   output eh2_lsu_pkt_t         lsu_pkt_dc5,

   output logic                  addr_external_dc1,
   output logic                  addr_external_dc3,
   output logic                  lsu_sc_success_dc5,
   output logic [pt.NUM_THREADS-1:0]            lr_vld,   // needed for clk gating

逐段解释：

* 第 L135-L140 行：LSU load/store control 将同一 ``eh2_lsu_pkt_t`` 沿 DC1_pre 到 DC5 输出，表明 LSU 控制包随 LSU pipeline 级联推进。

接口关系：

* 被调用：DEC 输出 ``lsu_p``，LSU 子模块和 trigger/address/bus/ecc 控制读取不同 DC stage 的 packet。
* 调用：类型定义没有调用关系；LSU pipeline 使用 ``rvdfflie`` 保存。
* 共享状态：``eh2_lsu_pkt_t`` 的字段布局是 LSU 多级 pipeline 之间的共享合同。

§4.4  ``eh2_lsu_error_pkt_t`` 与 ``eh2_class_pkt_t`` / ``eh2_reg_pkt_t``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 LSU exception 汇总、指令分类和寄存器源/目的字段。

关键代码（``rtl/design/include/eh2_def.sv:L201-L212``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic mul;
                          logic load;
                          logic sec;
                          logic alu;
                          } eh2_class_pkt_t;

   typedef struct packed {
                          logic [4:0] rs1;
                          logic [4:0] rs2;
                          logic [4:0] rd;
                          } eh2_reg_pkt_t;

逐段解释：

* 第 L201-L206 行：``eh2_class_pkt_t`` 只包含 mul、load、secondary 和 alu 4 个分类位。
* 第 L208-L212 行：``eh2_reg_pkt_t`` 是 3 个 5 bit register index 的组合：rs1、rs2、rd。

关键代码（``rtl/design/include/eh2_def.sv:L296-L304``）：

.. code-block:: systemverilog

   typedef struct packed {
                         logic exc_valid;
                         logic single_ecc_error;
                         logic inst_type;   //0: Load, 1: Store
                         logic amo_valid;
                         logic exc_type;    //0: MisAligned, 1: Access Fault
                         logic [3:0] mscause;
                         logic [31:0] addr;
                         } eh2_lsu_error_pkt_t;

逐段解释：

* 第 L296-L304 行：``eh2_lsu_error_pkt_t`` 包含 exception valid、single ECC error、load/store 类型、AMO valid、misaligned/access-fault 类型、4 bit ``mscause`` 和 32 bit 地址。

接口关系：

* 被调用：LSU exception 和 decode 分类路径可以用这些 packet 聚合字段。
* 调用：类型定义没有调用关系。
* 共享状态：``inst_type`` 与 ``exc_type`` 的编码由注释固定，使用方必须按 0/1 解释。

§4.5  ``eh2_dec_pkt_t`` - decode 全量控制包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 bitmanip、operand source、LSU、ALU、branch、CSR、trap、MUL/DIV 和合法性字段集中到一个译码输出结构中。

关键代码（``rtl/design/include/eh2_def.sv:L306-L360``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic clz;
                          logic ctz;
                          logic cpop;
                          logic sext_b;
                          logic sext_h;
                          logic min;
                          logic max;
                          logic pack;
                          logic packu;
                          logic packh;
                          logic rol;
                          logic ror;
                          logic grev;
                          logic gorc;
                          logic zbb;
                          logic bset;
                          logic bclr;
                          logic binv;
                          logic bext;
                          logic zbs;
                          logic bcompress;
                          logic bdecompress;
                          logic zbe;

逐段解释：

* 第 L306-L329 行：decode packet 开头是 bitmanip 相关字段，覆盖 Zbb/Zbs/Zbe 及 bcompress/bdecompress 等控制位。

关键代码（``rtl/design/include/eh2_def.sv:L330-L407``）：

.. code-block:: systemverilog

                          logic clmul;
                          logic clmulh;
                          logic clmulr;
                          logic zbc;
                          logic shfl;
                          logic unshfl;
                          logic xperm_n;
                          logic xperm_b;
                          logic xperm_h;
                          logic zbp;
                          // ...
                          logic pm_alu;
                          logic i0_only;
                          logic legal;
                          } eh2_dec_pkt_t;

逐段解释：

* 第 L330-L352 行：中段继续覆盖 carry-less multiply、shuffle、xperm、CRC、BFP 和 Zba 字段。
* 第 L353-L407 行：后段覆盖 ALU/atomic/LR/SC、source 选择、load/store/LSU、算术逻辑、branch/jal、CSR、sync、trap、mul/div、fence、power-management ALU、i0-only 和 legal。片段以省略号截断，完整字段在源文件 L330-L407。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L392-L393``）：

.. code-block:: systemverilog

   eh2_dec_pkt_t i0_dp_raw, i0_dp;
   eh2_dec_pkt_t i1_dp_raw, i1_dp;

逐段解释：

* 第 L392-L393 行：decode control 为 i0/i1 各保留 raw 和处理后的 decode packet，说明 ``eh2_dec_pkt_t`` 是译码内部的全量控制向量。

接口关系：

* 被调用：``eh2_dec_decode_ctl`` 生成并处理 i0/i1 decode packet。
* 调用：类型定义没有调用关系。
* 共享状态：``eh2_dec_pkt_t`` 字段再被拆分成 ALU、LSU、MUL、DIV、CSR 等后续 packet。

§4.6  ``eh2_mul_pkt_t`` 与 ``eh2_div_pkt_t``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 MUL 与 DIV 单元需要的控制字段。

关键代码（``rtl/design/include/eh2_def.sv:L410-L443``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic valid;
                          logic rs1_sign;
                          logic rs2_sign;
                          logic low;
                          logic load_mul_rs1_bypass_e1;
                          logic load_mul_rs2_bypass_e1;
                          logic bcompress;
                          logic bdecompress;
                          logic clmul;
                          logic clmulh;
                          logic clmulr;
                          logic grev;
                          logic gorc;
                          logic shfl;
                          logic unshfl;
                          logic crc32_b;
                          logic crc32_h;
                          logic crc32_w;

逐段解释：

* 第 L410-L436 行：``eh2_mul_pkt_t`` 包含 valid、operand sign、low、load-to-mul bypass，以及 bitmanip/multiply 扩展字段，包括 bcompress/bdecompress、clmul、grev/gorc、shuffle、CRC、BFP、xperm。

关键代码（``rtl/design/include/eh2_def.sv:L438-L443``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic valid;
                          logic unsign;
                          logic rem;
                          logic tid;
                          } eh2_div_pkt_t;

逐段解释：

* 第 L438-L443 行：``eh2_div_pkt_t`` 只包含 valid、unsigned、remainder 和 tid 4 个字段。

关键代码（``rtl/design/dec/eh2_dec_decode_ctl.sv:L265-L269``）：

.. code-block:: systemverilog

   output eh2_lsu_pkt_t    lsu_p,                   // load/store packet

   output eh2_mul_pkt_t    mul_p,                   // multiply packet

   output eh2_div_pkt_t    div_p,                   // divide packet

逐段解释：

* 第 L265-L269 行：decode control 同时输出 LSU、MUL 和 DIV packet，说明这些类型是 decode 到执行后端的分流接口。

接口关系：

* 被调用：DEC 输出 ``mul_p`` 和 ``div_p``；MUL/DIV 控制单元消费。
* 调用：类型定义没有调用关系。
* 共享状态：``tid`` 字段在 DIV packet 中保留 thread 信息；MUL packet 中的 bypass 字段连接 load-to-mul 数据路径。

§5  Memory macro、trigger、cache debug 与 CSR 类型
--------------------------------------------------

后半部分类型连接存储宏外部控制、debug trigger、icache debug 诊断、BTB SRAM 命中信息和 CSR/TLU decode。

§5.1  CCM / DCCM / ICache macro ext-in packet
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为不同 memory macro 外部控制端口定义相同字段布局。

关键代码（``rtl/design/include/eh2_def.sv:L445-L494``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic        TEST1;
                          logic        RME;
                          logic [3:0]  RM;

                          logic        LS;
                          logic        DS;
                          logic        SD;
                          logic        TEST_RNM;
                          logic        BC1;
                          logic        BC2;
                         } eh2_ccm_ext_in_pkt_t;

   typedef struct packed {
                          logic        TEST1;
                          logic        RME;
                          logic [3:0]  RM;
                          logic        LS;
                          logic        DS;

逐段解释：

* 第 L445-L456 行：``eh2_ccm_ext_in_pkt_t`` 包含 TEST1、RME、4 bit RM、LS、DS、SD、TEST_RNM、BC1 和 BC2。
* 第 L458-L494 行：``eh2_dccm_ext_in_pkt_t``、``eh2_ic_data_ext_in_pkt_t`` 和 ``eh2_ic_tag_ext_in_pkt_t`` 复用同样字段布局，只是 typedef 名称对应 DCCM、I-cache data 和 I-cache tag。

接口关系：

* 被调用：memory wrapper 或 memory macro 适配层使用这些 packet 连接 memory test/repair/control 端口。
* 调用：类型定义没有调用关系。
* 共享状态：四个 typedef 字段一致，但类型名区分使用场景。

§5.2  ``eh2_trigger_pkt_t`` - debug trigger 配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：描述每个 trigger 的 select、match、load/store/execute、mode 和 compare value。

关键代码（``rtl/design/include/eh2_def.sv:L497-L505``）：

.. code-block:: systemverilog

   typedef struct packed {
                           logic        select;
                           logic        match;
                           logic        store;
                           logic        load;
                           logic        execute;
                           logic        m;
                           logic [31:0] tdata2;
               } eh2_trigger_pkt_t;

逐段解释：

* 第 L497-L505 行：trigger packet 包含选择字段、match 模式、store/load/execute 触发条件、M-mode bit 和 32 bit ``tdata2``。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L180-L188``）：

.. code-block:: systemverilog

   output logic [pt.NUM_THREADS-1:0] dec_tlu_dbg_halted, // Core is halted and ready for debug command
   output logic [pt.NUM_THREADS-1:0] dec_tlu_debug_mode, // Core is in debug mode
   output logic dec_dbg_cmd_done, // abstract command done
   output logic dec_dbg_cmd_fail, // abstract command failed
   output logic dec_dbg_cmd_tid,  // Tid for debug abstract command response
   output logic [pt.NUM_THREADS-1:0] dec_tlu_resume_ack, // Resume acknowledge
   output logic [pt.NUM_THREADS-1:0] dec_tlu_debug_stall, // stall decode while waiting on core to empty
   output logic [pt.NUM_THREADS-1:0] dec_tlu_mpc_halted_only, // Core is halted only due to MPC
   output eh2_trigger_pkt_t [pt.NUM_THREADS-1:0] [3:0] trigger_pkt_any, // trigger info for trigger blocks

逐段解释：

* 第 L188 行：TLU top 输出 ``trigger_pkt_any``，类型是 ``eh2_trigger_pkt_t [pt.NUM_THREADS-1:0][3:0]``，即每个 thread 有 4 个 trigger packet。

关键代码（``rtl/design/lsu/eh2_lsu_trigger.sv:L31-L45``）：

.. code-block:: systemverilog

   input logic                    rst_l,
   input logic                    clk_override,
   input logic                    clk,
   input eh2_trigger_pkt_t [pt.NUM_THREADS-1:0][3:0] trigger_pkt_any, // Trigger info from the decode
   input eh2_lsu_pkt_t           lsu_pkt_dc3,            // lsu packet
   input eh2_lsu_pkt_t           lsu_pkt_dc4,            // lsu packet
   input logic [31:0]             lsu_addr_dc4,           // address
   input logic [31:0]             store_data_dc3,         // store data
   input logic [31:0]             amo_data_dc3,

   output logic [3:0]             lsu_trigger_match_dc4   // match result
   );

   eh2_trigger_pkt_t  [3:0]        trigger_tid_pkt_any;

逐段解释：

* 第 L34-L36 行：LSU trigger 模块同时接收 ``trigger_pkt_any`` 和 DC3/DC4 LSU packet，用于 load/store trigger match。
* 第 L44 行：模块内部再按目标 thread 选出 4 个 ``eh2_trigger_pkt_t``。

接口关系：

* 被调用：TLU 生成 trigger packet，LSU trigger 和 DEC trigger 模块消费。
* 调用：类型定义没有调用关系。
* 共享状态：``trigger_pkt_any`` 通过 thread 和 trigger index 两维数组传递 trigger 配置。

§5.3  ``eh2_cache_debug_pkt_t`` - icache debug 诊断包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：承载 I-cache debug 写数据、DICAWICS 控制和读写 valid。

关键代码（``rtl/design/include/eh2_def.sv:L508-L513``）：

.. code-block:: systemverilog

   typedef struct packed {
                           logic [70:0]  icache_wrdata;
                           logic [16:0]  icache_dicawics;
                           logic         icache_rd_valid;
                           logic         icache_wr_valid;
               } eh2_cache_debug_pkt_t;

逐段解释：

* 第 L508-L513 行：cache debug packet 包含 71 bit I-cache 写数据、17 bit DICAWICS 字段、读 valid 和写 valid。

关键代码（``rtl/design/eh2_veer.sv:L546-L550``）：

.. code-block:: systemverilog

   // Icache debug
      logic [70:0]                  ifu_ic_debug_rd_data;

      logic ifu_ic_debug_rd_data_valid; // diagnostic icache read data valid
      eh2_cache_debug_pkt_t dec_tlu_ic_diag_pkt; // packet of DICAWICS, DICAD0/1, DICAGO info for icache diagnostics

逐段解释：

* 第 L546-L550 行：顶层将 ``dec_tlu_ic_diag_pkt`` 声明为 ``eh2_cache_debug_pkt_t``，注释说明 packet 包含 DICAWICS、DICAD0/1 和 DICAGO 的 icache diagnostics 信息。

关键代码（``rtl/design/dec/eh2_dec_tlu_top.sv:L197-L197``）：

.. code-block:: systemverilog

   output eh2_cache_debug_pkt_t dec_tlu_ic_diag_pkt, // packet of DICAWICS, DICAD0/1, DICAGO info for icache diagnostics

逐段解释：

* 第 L197 行：TLU top 输出同名 ``dec_tlu_ic_diag_pkt``，类型与顶层声明一致。

接口关系：

* 被调用：DEC/TLU 生成该 packet，IFU/I-cache debug path 消费。
* 调用：类型定义没有调用关系。
* 共享状态：``icache_wrdata`` 与 ``icache_dicawics`` 是 icache debug CSR 到 IFU memory control 的结构化载荷。

§5.4  ``eh2_btb_sram_pkt``
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：打包 BTB SRAM way-hit 和 tag-match 相关字段。

关键代码（``rtl/design/include/eh2_def.sv:L515-L521``）：

.. code-block:: systemverilog

   typedef struct packed {
                          logic [3:0] wayhit_f1;
                          logic [3:0] wayhit_p1_f1;
                          logic [1:0] tag_match_way0_f1;
                          logic [1:0] tag_match_way0_p1_f1;
                          logic [3:0] tag_match_vway1_expanded_f1;
                          } eh2_btb_sram_pkt;

逐段解释：

* 第 L515-L521 行：该 packet 包含 F1 stage 的 way-hit、p1 way-hit、way0 tag match、p1 way0 tag match 和 expanded virtual way1 tag match。

接口关系：

* 被调用：BTB SRAM 相关控制逻辑可使用该 packet 聚合 match 信息。
* 调用：类型定义没有调用关系。
* 共享状态：字段命名全部带 F1，表明该 packet 服务 IFU/BTB F1 级信息传递。

§5.5  ``eh2_csr_tlu_pkt_t`` - CSR decode 到 TLU 的位图
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 CSR decode 结果打包为逐 CSR bit，再附加 presync/postsync/glob/legal 等控制位。

关键代码（``rtl/design/include/eh2_def.sv:L523-L598``）：

.. code-block:: systemverilog

   typedef struct packed {
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

逐段解释：

* 第 L523-L541 行：CSR packet 先列出标准 machine-mode CSR 与 EH2 自定义 CSR 的 decode bit，包括 misa、vendor/arch/imp/hart id、mstatus、mtvec、mip/mie、cycle/instret、scratch、epc、cause、scause、tval 和 mrac。

关键代码（``rtl/design/include/eh2_def.sv:L542-L598``）：

.. code-block:: systemverilog

                          logic csr_dmst;
                          logic csr_mdseac;
                          logic csr_meihap;
                          logic csr_meivt;
                          logic csr_meipt;
                          logic csr_meicurpl;
                          logic csr_meicidpl;
                          logic csr_dcsr;
                          logic csr_mcgc;
                          // ...
                          logic csr_mhartnum;
                          logic csr_mhartstart;
                          logic csr_mnmipdel;
                          logic valid_only;
                          logic presync;
                          logic postsync;
                          logic glob;
                          logic legal;
                          } eh2_csr_tlu_pkt_t;

逐段解释：

* 第 L542-L592 行：中段覆盖 debug、PIC、trigger、HPM、timer、cache diagnostic、fetch/data fault 相关 EH2 CSR bit。片段省略了中间若干 CSR 字段，完整列表见源文件 L542-L592。
* 第 L593-L598 行：尾部字段 ``valid_only``、``presync``、``postsync``、``glob`` 和 ``legal`` 是 CSR 访问控制与流水线同步属性。

关键代码（``rtl/design/dec/eh2_dec_csr.sv:L34-L42``）：

.. code-block:: systemverilog

   input logic dec_csr_any_unq_d,
   input logic dec_csr_wen_unq_d,
   input logic dec_tlu_dbg_halted,

   output logic dec_csr_legal_d,
   output logic tlu_presync_d,
   output logic tlu_postsync_d,

   output eh2_csr_tlu_pkt_t tlu_csr_pkt_d

逐段解释：

* 第 L42 行：CSR decode 模块输出 ``tlu_csr_pkt_d``，类型正是 ``eh2_csr_tlu_pkt_t``。

接口关系：

* 被调用：CSR decode 输出该 packet，TLU 控制读取逐 CSR decode bit 和同步属性。
* 调用：类型定义没有调用关系。
* 共享状态：``legal``、``presync``、``postsync`` 和各 ``csr_*`` bit 是 CSR decode 到 TLU 的共享控制合同。

§6  顶层类型使用地图
--------------------

``eh2_veer.sv`` 将 package 中多个 typedef 作为模块间连接信号使用。下面的片段展示 top-level 中的主要结构化信号。

§6.1  DEC/EXU/LSU 控制 packet 在顶层的声明
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 ALU、trigger、LSU packet 在 ``eh2_veer`` 顶层如何作为模块边界信号。

关键代码（``rtl/design/eh2_veer.sv:L567-L610``）：

.. code-block:: systemverilog

   eh2_alu_pkt_t  i0_ap, i1_ap;

   // Trigger signals
   eh2_trigger_pkt_t [pt.NUM_THREADS-1:0][3:0]     trigger_pkt_any;
   logic [3:0]             lsu_trigger_match_dc4;
   logic [pt.NUM_THREADS-1:0] dec_ib3_valid_d, dec_ib2_valid_d;

   logic [31:0] dec_i0_immed_d;
   logic [31:0] dec_i1_immed_d;

   logic [pt.BTB_TOFFSET_SIZE:1] dec_i0_br_immed_d;
   logic [pt.BTB_TOFFSET_SIZE:1] dec_i1_br_immed_d;
   // ...
   eh2_lsu_pkt_t    lsu_p;

逐段解释：

* 第 L567 行：顶层为 i0/i1 分别声明 ALU packet，连接 DEC 输出与 EXU 输入。
* 第 L570-L571 行：``trigger_pkt_any`` 是 per-thread、4-entry trigger packet 数组，``lsu_trigger_match_dc4`` 是 LSU trigger match 结果。
* 第 L610 行：``lsu_p`` 是 DEC 到 LSU 的 load/store packet。

接口关系：

* 被调用：``eh2_dec``、``eh2_exu`` 和 ``eh2_lsu`` 实例通过这些同名信号连接。
* 调用：本节没有子模块调用。
* 共享状态：顶层信号名是各模块之间共享 packet 的连接点。

§6.2  Branch prediction packet 在顶层的声明
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 EXU mispredict packet 与 DEC predictor packet 在顶层如何并存。

关键代码（``rtl/design/eh2_veer.sv:L726-L729``）：

.. code-block:: systemverilog

   eh2_br_tlu_pkt_t dec_tlu_br0_wb_pkt;
   eh2_br_tlu_pkt_t dec_tlu_br1_wb_pkt;

   eh2_predict_pkt_t [pt.NUM_THREADS-1:0]                    exu_mp_pkt;

逐段解释：

* 第 L726-L727 行：写回到 TLU 的 branch packet 分成 br0 和 br1。
* 第 L729 行：EXU mispredict packet 是 per-thread ``eh2_predict_pkt_t`` 数组。

关键代码（``rtl/design/eh2_veer.sv:L817-L818``）：

.. code-block:: systemverilog

   eh2_predict_pkt_t  i0_predict_p_d;
   eh2_predict_pkt_t  i1_predict_p_d;

逐段解释：

* 第 L817-L818 行：DEC stage 的 i0/i1 predict packet 在顶层单独声明，与 EXU 输出的 per-thread mispredict packet 分离。

接口关系：

* 被调用：DEC、EXU 和 IFU branch predictor 控制路径共享这些 packet。
* 调用：本节没有子模块调用。
* 共享状态：``i0_predict_p_d`` / ``i1_predict_p_d`` 从 DEC 进入 EXU，``exu_mp_pkt`` 从 EXU 回到 IFU。

§7  行为汇总
------------

``eh2_def.sv`` 本身不实现组合或时序行为，它的行为意义来自字段布局对 RTL 模块边界的约束：

* Trace 路径使用 ``eh2_trace_pkt_t`` 将 retired instruction、exception、interrupt、tval 和 verification-only rd writeback 字段打包。
* DEC 到 EXU 使用 ``eh2_alu_pkt_t``、``eh2_mul_pkt_t``、``eh2_div_pkt_t`` 和 ``eh2_predict_pkt_t`` 传递控制信息。
* DEC 到 LSU 使用 ``eh2_lsu_pkt_t``，LSU 内部把该 packet 从 DC1_pre 推进到 DC5。
* IFU 到 DEC instruction buffer 使用 ``eh2_ib_pkt_t`` 保存 instruction、PC、predecode 和 branch predict 信息。
* TLU/debug trigger 使用 ``eh2_trigger_pkt_t``，I-cache diagnostics 使用 ``eh2_cache_debug_pkt_t``。
* CSR decode 到 TLU 使用 ``eh2_csr_tlu_pkt_t`` 作为逐 CSR decode bit 与同步属性集合。

任何字段增删或顺序变化都会影响 ``$bits(<type>)`` 驱动的 pipeline flop 宽度，也会影响 ``.*`` 模块连接处结构化信号的二进制布局。因此，修改 ``eh2_def.sv`` 必须同时检查使用该类型的 DEC、EXU、LSU、IFU、TLU 和验证 trace 路径。

§8  Include/typedef 常见失败模式与排查
------------------------------------------------

``eh2_def.sv`` 和 ``eh2_pdef.vh`` 的问题通常不会在 include 文件本身报错，而是在
DEC/EXU/LSU/IFU 某个 ``$bits(<packet>)`` flop、``.*`` 端口连接或 cosim trace 解码处
暴露。修改 typedef 前先查完整使用面，再跑 compile 和 Sphinx 引用检查。

.. list-table:: include/typedef 失败模式
   :header-rows: 1
   :widths: 24 32 28 16

   * - 现象
     - 可能根因
     - 排查命令
     - 阅读入口
   * - compile 报 packet 字段不存在
     - ``eh2_def.sv`` typedef 字段名改动后使用点未同步
     - ``rg -n "<field_name>|eh2_.*_pkt_t" /home/host/Cores-VeeR-EH2/design``
     - 本章 §3-§7
   * - ``$bits`` 宽度不一致
     - typedef 增删字段改变 pipeline flop 宽度，旧连线仍按原宽度拼接
     - ``rg -n "\\$bits\\(eh2_.*_pkt_t\\)" /home/host/Cores-VeeR-EH2/design``
     - :ref:`appendix_a_rtl/dec` 与 :ref:`appendix_a_rtl/lsu`
   * - cosim trace 缺 rd 写回字段
     - ``eh2_trace_pkt_t`` 字段与 RVFI/trace sidecar 文档不同步
     - ``rg -n "eh2_trace_pkt_t|rd_wdata|rd_addr" /home/host/Cores-VeeR-EH2/design rtl dv/uvm/core_eh2``
     - :ref:`rvfi_trace` 与 :ref:`adr-0015`
   * - 某个 profile 下数组越界
     - ``eh2_pdef.vh`` 中 ``pt.NUM_THREADS`` 或 memory 参数与 generate 使用点不一致
     - ``rg -n "NUM_THREADS|ICCM|DCCM" rtl/snapshots/default /home/host/Cores-VeeR-EH2/design``
     - 本章 §2 与 :ref:`appendix_a_rtl/wrapper`
   * - lint 报 implicit cast 或 packed struct 宽度问题
     - typedef 字段是 packed struct，跨模块连接时被截断或扩展
     - ``rg -n "typedef struct packed|logic \\[.*\\].*=.*pkt" /home/host/Cores-VeeR-EH2/design``
     - :ref:`lint_flow`
   * - LEC packed-port 相关失败
     - 旧 Formality 对 top-level packed port 支持有限，需要 block-level LEC
     - ``rg -n "packed-port|block-level" docs/adr syn``
     - :ref:`adr-0020`

§9  参考资料
------------

* 关联章节：:doc:`dec`、:doc:`exu`、:doc:`lsu`、:doc:`ifu`、:doc:`dbg`
* 关联 ADR：:ref:`adr-0004`、:ref:`adr-0015`、:ref:`adr-0018`
* 源文件：``/home/host/eh2-veri/rtl/design/include/eh2_def.sv``
* 顶层使用：``/home/host/eh2-veri/rtl/design/eh2_veer.sv``
* DEC trace 输出：``/home/host/eh2-veri/rtl/design/dec/eh2_dec.sv``
* DEC decode 控制：``/home/host/eh2-veri/rtl/design/dec/eh2_dec_decode_ctl.sv``
* LSU packet pipeline：``/home/host/eh2-veri/rtl/design/lsu/eh2_lsu_lsc_ctl.sv``

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
