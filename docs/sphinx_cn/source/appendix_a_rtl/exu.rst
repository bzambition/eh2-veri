.. _appendix_a_rtl_exu:
.. _appendix_a_rtl/exu:

执行单元（EXU）- 详细参考
=========================

:status: draft
:source: rtl/design/exu/
:last-reviewed: 2026-05-19

§1  源码边界与数据流
--------------------

本章只解释 `rtl/design/exu/` 下的 EXU 源码，以及 EXU 在顶层文件和 RTL
filelist 中的连接位置。EXU 的直接源码边界来自
`dv/uvm/core_eh2/eh2_rtl.f:L42-L46`，顶层实例化来自
`rtl/design/eh2_veer.sv:L1077-L1082`。

EXU 与邻近模块的数据流可以按下面的方向理解。图中的信号名均出现在
`eh2_exu.sv` 端口或实例化连线中；未在源码中出现的握手或队列名不写入本章。

::

   DEC/GPR/LSU
      |  i0_ap/i1_ap, mul_p, div_p, GPR operands, bypass data
      v
   eh2_exu.sv
      |-- eh2_exu_alu_ctl x4 -> exu_i0_result_e1/e4, exu_i1_result_e1/e4
      |-- eh2_exu_mul_ctl    -> exu_mul_result_e3
      |-- eh2_exu_div_ctl    -> exu_div_result, exu_div_wren
      |
      |  exu_lsu_rs1_d/exu_lsu_rs2_d
      v
   LSU

   Branch metadata:
   DEC predict packet -> ALU -> EXU flush/mispredict packet -> IFU/DEC/TLU

§1.1  RTL filelist 中的 EXU 文件集合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_rtl.f` 把 EXU 四个编译单元列在 `Execution Unit` 注释之后。该顺序说明
`eh2_exu_alu_ctl.sv`、`eh2_exu_div_ctl.sv`、`eh2_exu_mul_ctl.sv` 与
`eh2_exu.sv` 一起构成 EXU 在 UVM 仿真 filelist 中的源文件集合。

关键代码（`dv/uvm/core_eh2/eh2_rtl.f:L42-L46`）：

.. code-block:: systemverilog

   // Execution Unit
   rtl/design/exu/eh2_exu_alu_ctl.sv
   rtl/design/exu/eh2_exu_div_ctl.sv
   rtl/design/exu/eh2_exu_mul_ctl.sv
   rtl/design/exu/eh2_exu.sv

逐段解释：

* 第 L42 行：filelist 用注释把后续文件归入 `Execution Unit`。这不是模块实例化，
  但它是仿真和编译时确定 EXU 源文件范围的入口。
* 第 L43-L45 行：三个控制子模块先进入 filelist，分别对应 ALU、除法器和乘法器。
  这三类模块都被 `eh2_exu.sv` 实例化或间接选择。
* 第 L46 行：`eh2_exu.sv` 是 EXU 顶层。它实例化 ALU、mul、div 子模块，并把 DEC、
  LSU、IFU/TLU 相关信号连到 EXU 输出。

接口关系：

* 被调用：filelist 被仿真和综合脚本读取，用来决定编译文件集合。
* 调用：本段不调用 SystemVerilog 模块，只列出文件路径。
* 共享状态：没有运行期共享状态；它只定义编译边界。

§1.2  `eh2_veer.sv` 顶层实例化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_veer.sv` 在 DEC 与 LSU 实例之间实例化 `eh2_exu`，并使用 `.*`
连接多数同名端口。显式端口只覆盖 EXU 时钟、时钟覆盖和复位。

关键代码（`rtl/design/eh2_veer.sv:L1077-L1082`）：

.. code-block:: systemverilog

      eh2_exu #(.pt(pt)) exu (
                               .clk(active_l2clk),
                               .clk_override(dec_tlu_exu_clk_override),
                               .rst_l(core_rst_l),
                               .*
                               );

逐段解释：

* 第 L1077 行：顶层用参数包 `pt` 实例化 `eh2_exu`，实例名是 `exu`。本章后续所有
  `pt.NUM_THREADS`、`pt.BHT_GHR_SIZE`、`pt.BTB_*` 等参数都来自该参数包。
* 第 L1078-L1080 行：EXU 接收 `active_l2clk`、`dec_tlu_exu_clk_override` 和
  `core_rst_l`。这与 EXU 内部乘法器和除法器的 clock enable 逻辑相关。
* 第 L1081 行：`.*` 把同名信号自动连接到 EXU 端口。文档解释接口关系时只引用
  `eh2_exu.sv` 中真实存在的端口名。

接口关系：

* 被调用：`eh2_veer.sv` 顶层调用 `eh2_exu`。
* 调用：`eh2_exu` 内部再调用 `eh2_exu_alu_ctl`、`eh2_exu_mul_ctl` 和
  `eh2_exu_div_ctl`。
* 共享状态：`pt` 参数包决定线程数、BTB/BHT 宽度、bitmanip 开关和除法器实现选择。

§2  `eh2_exu.sv` 顶层
---------------------

`eh2_exu.sv` 是 EXU 顶层。它的职责不是实现每一种运算细节，而是完成 4 类工作：
选择 D-stage 操作数，把控制包和预测包沿 E1/E2/E3/E4 流水传播，实例化 ALU/mul/div
运算单元，并汇总 flush、NPC、mispredict 更新信息。

§2.1  模块声明与参数导入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：模块声明导入 `eh2_pkg::*`，再包含 `eh2_param.vh`。这使端口可以使用
`eh2_predict_pkt_t`、`eh2_alu_pkt_t`、`eh2_mul_pkt_t`、`eh2_div_pkt_t` 和 `pt.*`
参数字段。

关键代码（`rtl/design/exu/eh2_exu.sv:L17-L22`）：

.. code-block:: systemverilog

   module eh2_exu
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (

逐段解释：

* 第 L17 行：定义 EXU 顶层模块名 `eh2_exu`。
* 第 L18 行：导入 `eh2_pkg::*`，因此端口和内部信号可以直接使用 EH2 的 packet
  typedef。
* 第 L19-L21 行：包含 `eh2_param.vh`，使模块参数列表中存在 `pt`。后续代码多次读取
  `pt.NUM_THREADS`、`pt.BTB_ADDR_HI`、`pt.BHT_GHR_SIZE` 和 bitmanip 开关。
* 第 L22 行：进入端口列表。EXU 的数据路径和控制路径都由此暴露给顶层。

接口关系：

* 被调用：`rtl/design/eh2_veer.sv:L1077-L1082` 实例化本模块。
* 调用：本模块后续实例化 `eh2_exu_alu_ctl`、`eh2_exu_mul_ctl`、`eh2_exu_div_ctl`。
* 共享状态：`pt` 参数包决定线程向量宽度和预测元数据宽度。

§2.2  时钟、secondary ALU 与分支 clock enable 输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：EXU 顶层端口接收全局时钟、复位、scan 控制，以及 DEC 产生的 secondary ALU
和 branch clock enable。顶层不在此处解释指令语义，只把 enable 信号作为后续寄存器和
ALU 实例的门控条件使用。

关键代码（`rtl/design/exu/eh2_exu.sv:L24-L57`）：

.. code-block:: systemverilog

      input logic                                   clk,                          // Top level clock
      input logic [pt.NUM_THREADS-1:0]              active_thread_l2clk,
      input logic                                   clk_override,                 // Override multiply clock enables
      input logic                                   rst_l,                        // Reset
      input logic                                   scan_mode,                    // Scan control

      input logic                                   dec_i0_secondary_d,           // I0 Secondary ALU at  D-stage.  Used for clock gating
      input logic                                   dec_i0_secondary_e1,          // I0 Secondary ALU at E1-stage.  Used for clock gating
      input logic                                   dec_i0_secondary_e2,          // I0 Secondary ALU at E2-stage.  Used for clock gating

      input logic                                   dec_i1_secondary_d,           // I1 Secondary ALU at  D-stage.  Used for clock gating
      input logic                                   dec_i1_secondary_e1,          // I1 Secondary ALU at E1-stage.  Used for clock gating
      input logic                                   dec_i1_secondary_e2,          // I1 Secondary ALU at E2-stage.  Used for clock gating

      input logic                                   dec_i0_branch_d,              // I0 Branch at  D-stage.  Used for clock gating
      input logic                                   dec_i0_branch_e1,             // I0 Branch at E1-stage.  Used for clock gating
      input logic                                   dec_i0_branch_e2,             // I0 Branch at E2-stage.  Used for clock gating
      input logic                                   dec_i0_branch_e3,             // I0 Branch at E3-stage.  Used for clock gating

      input logic                                   dec_i1_branch_d,              // I0 Branch at  D-stage.  Used for clock gating
      input logic                                   dec_i1_branch_e1,             // I0 Branch at E1-stage.  Used for clock gating
      input logic                                   dec_i1_branch_e2,             // I0 Branch at E2-stage.  Used for clock gating
      input logic                                   dec_i1_branch_e3,             // I0 Branch at E3-stage.  Used for clock gating

逐段解释：

* 第 L24-L28 行：EXU 有顶层时钟 `clk`、每线程活动时钟 `active_thread_l2clk`、
  clock override、低有效复位和 scan 控制。`active_thread_l2clk` 后续用于每线程
  mispredict packet 寄存器。
* 第 L30-L36 行：`dec_i0_secondary_*` 与 `dec_i1_secondary_*` 标记 secondary ALU
  相关数据在 D/E1/E2 的存在，后续驱动 `i0_src_*_ff` 和 `i1_src_*_ff` 的 enable。
* 第 L38-L46 行：`dec_i0_branch_*` 与 `dec_i1_branch_*` 标记 branch 元数据在
  D/E1/E2/E3 的存在，后续用于预测包和 `predpipe` 的流水寄存。
* 第 L54-L57 行：`dec_i0_data_en`、`dec_i0_ctl_en`、`dec_i1_data_en`、
  `dec_i1_ctl_en` 是 slot 级 E1-E4 enable，后续在 L380-L384 展开成独立阶段信号。

接口关系：

* 被调用：DEC/TLU 侧产生这些 enable 和 clock override。
* 调用：本节信号被 `rvdffe`、`rvdfflie`、`rvdffpcie` 和 ALU 实例端口使用。
* 共享状态：`active_thread_l2clk` 以 `pt.NUM_THREADS` 为宽度。

§2.3  预测包、bypass 和运算控制包输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：EXU 从 DEC 接收分支预测包、bypass 选择、GPR 操作数、立即数、ALU/mul/div
控制包，以及 TLU flush 输入。顶层只在真实代码中连接这些信号，不推导不存在的协议。

关键代码（`rtl/design/exu/eh2_exu.sv:L63-L134`）：

.. code-block:: systemverilog

      input logic [31:0]                            lsu_result_dc3,               // Load result

      input eh2_predict_pkt_t                      i0_predict_p_d,               // DEC branch predict packet
      input eh2_predict_pkt_t                      i1_predict_p_d,               // DEC branch predict packet
      input logic [pt.BHT_GHR_SIZE-1:0]             i0_predict_fghr_d,            // DEC predict fghr
      input logic [pt.BTB_ADDR_HI:pt.BTB_ADDR_LO]   i0_predict_index_d,           // DEC predict index
      input logic [pt.BTB_BTAG_SIZE-1:0]            i0_predict_btag_d,            // DEC predict branch tag
      input logic [pt.BTB_TOFFSET_SIZE-1:0]         i0_predict_toffset_d,         // DEC predict branch toffset
      input logic [pt.BHT_GHR_SIZE-1:0]             i1_predict_fghr_d,            // DEC predict fghr
      input logic [pt.BTB_ADDR_HI:pt.BTB_ADDR_LO]   i1_predict_index_d,           // DEC predict index
      input logic [pt.BTB_BTAG_SIZE-1:0]            i1_predict_btag_d,            // DEC predict branch tag
      input logic [pt.BTB_TOFFSET_SIZE-1:0]         i1_predict_toffset_d,         // DEC predict branch toffset

      input logic                                   dec_i0_rs1_bypass_en_e2,      // DEC bypass bus select for E2 stage
      input logic                                   dec_i0_rs2_bypass_en_e2,      // DEC bypass bus select for E2 stage
      input logic                                   dec_i1_rs1_bypass_en_e2,      // DEC bypass bus select for E2 stage
      input logic                                   dec_i1_rs2_bypass_en_e2,      // DEC bypass bus select for E2 stage

逐段解释：

* 第 L63 行：`lsu_result_dc3` 是 load result。`eh2_exu_mul_ctl.sv:L197-L198`
  直接用它处理 multiply 的 load-result bypass。
* 第 L65-L74 行：I0/I1 各自带 `eh2_predict_pkt_t` 以及 fghr、index、btag、
  toffset。L466-L484 将这些字段打包并跨 E1-E4 传播。
* 第 L76-L83 行：E2 bypass 选择和数据由 DEC 输入，用于 secondary ALU 的 E2 操作数修正。
  E3 bypass 也在端口列表中，后续 L552-L555 使用。
* 第 L130-L134 行：`i0_ap`、`i1_ap`、`mul_p`、`div_p` 是 ALU、乘法器和除法器的控制包。
  它们进入 EXU 后分别沿 ALU packet 流水、mul packet 流水或 div wrapper 端口传播。

接口关系：

* 被调用：DEC、GPR、LSU 和 TLU 侧为 EXU 提供这些输入。
* 调用：`i0_predict_p_d`、`i1_predict_p_d` 进入 `eh2_exu_alu_ctl`；`mul_p`
  进入 `eh2_exu_mul_ctl`；`div_p` 进入 `eh2_exu_div_ctl`。
* 共享状态：预测字段宽度由 `pt.BHT_GHR_SIZE`、`pt.BTB_ADDR_HI`、
  `pt.BTB_ADDR_LO`、`pt.BTB_BTAG_SIZE`、`pt.BTB_TOFFSET_SIZE` 决定。

§2.4  EXU 输出分组
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：EXU 输出 ALU 结果、LSU 操作数、CSR RS1、flush、mul/div 结果、NPC 和分支
更新元数据。输出名直接反映它们被 DEC、LSU、GPR、TLU、IFU 或 PMU 使用的方向。

关键代码（`rtl/design/exu/eh2_exu.sv:L158-L200`）：

.. code-block:: systemverilog

      output logic [31:0]                           exu_i0_result_e1,             // Primary ALU result to DEC
      output logic [31:0]                           exu_i1_result_e1,             // Primary ALU result to DEC
      output logic [31:1]                           exu_i0_pc_e1,                 // Primary PC  result to DEC
      output logic [31:1]                           exu_i1_pc_e1,                 // Primary PC  result to DEC

      output logic [31:0]                           exu_i0_result_e4,             // Secondary ALU result
      output logic [31:0]                           exu_i1_result_e4,             // Secondary ALU result

      output logic [31:0]                           exu_lsu_rs1_d,                // LSU operand
      output logic [31:0]                           exu_lsu_rs2_d,                // LSU operand

      output logic [31:0]                           exu_i0_csr_rs1_e1,            // RS1 source for a CSR instruction

      output logic [pt.NUM_THREADS-1:0]             exu_flush_final,              // Pipe is being flushed this cycle
      output logic [pt.NUM_THREADS-1:0]             exu_i0_flush_final,           // I0 flush to DEC
      output logic [pt.NUM_THREADS-1:0]             exu_i1_flush_final,           // I1 flush to DEC

逐段解释：

* 第 L158-L164 行：primary ALU 结果在 E1 输出，secondary ALU 结果在 E4 输出。I0/I1
  分别有独立结果线。
* 第 L166-L169 行：`exu_lsu_rs1_d`、`exu_lsu_rs2_d` 送 LSU，`exu_i0_csr_rs1_e1`
  保存 CSR 指令需要的 RS1 源。
* 第 L171-L179 行：EXU 输出最终 flush 与 early flush 的线程向量和路径。最终 flush
  后续由 L701-L703 汇总。
* 第 L181-L200 行：乘法、除法和 mispredict 更新输出在同一端口列表中声明。`exu_mp_*`
  字段来自 L640-L663 的 final mispredict 选择和打包。

接口关系：

* 被调用：DEC、LSU、GPR、TLU、IFU_DP 和 PMU 根据端口名接收这些输出。
* 调用：输出的组合值来自 ALU/mul/div 子模块和 EXU 内部 flush/GHR 逻辑。
* 共享状态：flush 和 mispredict 输出均按 `pt.NUM_THREADS` 分线程。

§2.5  D-stage 操作数选择
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：D-stage 组合逻辑在 GPR、bypass、PC、immediate、debug 写数据和外部中断地址之间
选择操作数。源码中没有单独函数，这一段直接由连续赋值完成。

关键代码（`rtl/design/exu/eh2_exu.sv:L325-L350`）：

.. code-block:: systemverilog

      assign i0_rs1_d[31:0]       = ({32{~dec_i0_rs1_bypass_en_d}} & ((dec_debug_wdata_rs1_d) ? dbg_cmd_wrdata[31:0] : gpr_i0_rs1_d[31:0])) |
                                    ({32{~dec_i0_rs1_bypass_en_d   & dec_i0_select_pc_d}} & { dec_i0_pc_d[31:1], 1'b0}) |    // for jal's
                                    ({32{ dec_i0_rs1_bypass_en_d}} & i0_rs1_bypass_data_d[31:0]);


      assign i0_rs1_final_d[31:0] =  {32{~dec_i0_csr_ren_d}}       & i0_rs1_d[31:0];

      assign i0_rs2_d[31:0]       = ({32{~dec_i0_rs2_bypass_en_d}} & gpr_i0_rs2_d[31:0]        ) |
                                    ({32{~dec_i0_rs2_bypass_en_d}} & dec_i0_immed_d[31:0]      ) |
                                    ({32{ dec_i0_rs2_bypass_en_d}} & i0_rs2_bypass_data_d[31:0]);

      assign i1_rs1_d[31:0]       = ({32{~dec_i1_rs1_bypass_en_d}} & gpr_i1_rs1_d[31:0]) |
                                    ({32{~dec_i1_rs1_bypass_en_d   & dec_i1_select_pc_d}} & { dec_i1_pc_d[31:1], 1'b0}) |  // pc orthogonal with rs1
                                    ({32{ dec_i1_rs1_bypass_en_d}} & i1_rs1_bypass_data_d[31:0]);


      assign i1_rs2_d[31:0]       = ({32{~dec_i1_rs2_bypass_en_d}} & gpr_i1_rs2_d[31:0]        ) |
                                    ({32{~dec_i1_rs2_bypass_en_d}} & dec_i1_immed_d[31:0]      ) |
                                    ({32{ dec_i1_rs2_bypass_en_d}} & i1_rs2_bypass_data_d[31:0]);

逐段解释：

* 第 L325-L327 行：I0 RS1 先在非 bypass 路径中选择 debug 写数据或 GPR，再在
  `dec_i0_select_pc_d` 为 1 时 OR 入 `{dec_i0_pc_d[31:1], 1'b0}`，最后由 bypass 路径
  覆盖。这里的掩码写法要求控制信号互斥，否则多个来源会按位 OR。
* 第 L330 行：`dec_i0_csr_ren_d` 清掉 `i0_rs1_final_d`。该信号只作用于 I0 primary
  ALU 输入路径，CSR RS1 本身在 L389 单独寄存。
* 第 L332-L334 行：I0 RS2 在 GPR、立即数和 bypass 数据之间选择。源码使用两个
  `~dec_i0_rs2_bypass_en_d` 掩码并列 OR，因此 immediate 与 GPR 的互斥关系来自上游
  decode 控制。
* 第 L336-L343 行：I1 的 RS1/RS2 选择结构与 I0 对应，但没有 debug 写数据分支。

接口关系：

* 被调用：DEC/GPR/bypass 网络提供 `gpr_*`、`dec_*` 和 `*_bypass_data_d`。
* 调用：结果进入 primary ALU、secondary ALU 操作数流水、LSU/mul/div 选择逻辑。
* 共享状态：本段为组合逻辑，不写寄存器。

§2.6  LSU、mul 和 div 操作数分流
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：顶层从同一组 D-stage GPR/bypass 输入中分出 LSU、乘法器和除法器的操作数。
LSU 路径额外处理 `dec_extint_stall`，乘法器路径会用 immediate 低 5 位参与 RS2 选择，
除法器只取 I0 除法输入。

关键代码（`rtl/design/exu/eh2_exu.sv:L346-L376`）：

.. code-block:: systemverilog

      assign exu_lsu_rs1_d[31:0]  = ({32{ ~dec_i0_rs1_bypass_en_d &  dec_i0_lsu_d & ~dec_extint_stall               }} & gpr_i0_rs1_d[31:0]        ) |
                                    ({32{ ~dec_i1_rs1_bypass_en_d & ~dec_i0_lsu_d & ~dec_extint_stall & dec_i1_lsu_d}} & gpr_i1_rs1_d[31:0]        ) |
                                    ({32{  dec_i0_rs1_bypass_en_d &  dec_i0_lsu_d & ~dec_extint_stall               }} & i0_rs1_bypass_data_d[31:0]) |
                                    ({32{  dec_i1_rs1_bypass_en_d & ~dec_i0_lsu_d & ~dec_extint_stall & dec_i1_lsu_d}} & i1_rs1_bypass_data_d[31:0]) |
                                    ({32{                                            dec_extint_stall               }} & {dec_tlu_meihap[31:2],2'b0});

      assign exu_lsu_rs2_d[31:0]  = ({32{ ~dec_i0_rs2_bypass_en_d &  dec_i0_lsu_d & ~dec_extint_stall               }} & gpr_i0_rs2_d[31:0]        ) |
                                    ({32{ ~dec_i1_rs2_bypass_en_d & ~dec_i0_lsu_d & ~dec_extint_stall & dec_i1_lsu_d}} & gpr_i1_rs2_d[31:0]        ) |
                                    ({32{  dec_i0_rs2_bypass_en_d &  dec_i0_lsu_d & ~dec_extint_stall               }} & i0_rs2_bypass_data_d[31:0]) |
                                    ({32{  dec_i1_rs2_bypass_en_d & ~dec_i0_lsu_d & ~dec_extint_stall & dec_i1_lsu_d}} & i1_rs2_bypass_data_d[31:0]);


      assign mul_rs1_d[31:0]      = ({32{ ~dec_i0_rs1_bypass_en_d &  dec_i0_mul_d               }} & gpr_i0_rs1_d[31:0]        ) |
                                    ({32{ ~dec_i1_rs1_bypass_en_d & ~dec_i0_mul_d & dec_i1_mul_d}} & gpr_i1_rs1_d[31:0]        ) |

逐段解释：

* 第 L346-L350 行：`exu_lsu_rs1_d` 优先处理 `dec_extint_stall`。该信号为 1 时，
  RS1 输出被 `{dec_tlu_meihap[31:2],2'b0}` 掩码项驱动。
* 第 L352-L355 行：`exu_lsu_rs2_d` 没有外部中断地址项，只在 I0/I1 的 GPR 和 bypass
  数据之间选择。
* 第 L358-L368 行：`mul_rs1_d`、`mul_rs2_d` 使用 `dec_i0_mul_d` 和 `dec_i1_mul_d`
  选择 slot。`mul_rs2_d` 还包含 `{27'b0,dec_i*_immed_d[4:0]}` 项，说明乘法器输入 B
  也承载部分 bitmanip 类操作需要的 5 位控制量。
* 第 L372-L376 行：`div_rs1_d`、`div_rs2_d` 只受 `dec_i0_div_d` 控制，没有 I1 除法选择项。

接口关系：

* 被调用：DEC 控制选择信号和 GPR/bypass 数据驱动本段。
* 调用：`exu_lsu_rs1_d`、`exu_lsu_rs2_d` 输出到 LSU；`mul_rs*_d` 进入
  `eh2_exu_mul_ctl`；`div_rs*_d` 进入 `eh2_exu_div_ctl`。
* 共享状态：`dec_extint_stall` 与 `dec_tlu_meihap` 在 LSU RS1 路径中改变输出来源。

§2.7  乘法器和除法器实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：顶层把 D-stage 选择出的 `mul_rs*_d` 和 `div_rs*_d` 送到子模块。乘法输出在
`exu_mul_result_e3`，除法输出由 `exu_div_wren` 与 `exu_div_result` 组合表示。

关键代码（`rtl/design/exu/eh2_exu.sv:L392-L406`）：

.. code-block:: systemverilog

      eh2_exu_mul_ctl #(.pt(pt)) mul_e1    (.*,
                             .clk_override  ( clk_override                             ),   // I
                             .mp            ( mul_p                                    ),   // I
                             .a             ( mul_rs1_d[31:0]                          ),   // I
                             .b             ( mul_rs2_d[31:0]                          ),   // I
                             .out           ( exu_mul_result_e3[31:0]                  ));  // O


      eh2_exu_div_ctl #(.pt(pt)) div_e1    (.*,
                             .cancel        ( dec_div_cancel                           ),   // I
                             .dp            ( div_p                                    ),   // I
                             .dividend      ( div_rs1_d[31:0]                          ),   // I
                             .divisor       ( div_rs2_d[31:0]                          ),   // I
                             .finish_dly    ( exu_div_wren                             ),   // O
                             .out           ( exu_div_result[31:0]                     ));  // O

逐段解释：

* 第 L392-L397 行：`mul_e1` 实例把 `mul_p`、`mul_rs1_d`、`mul_rs2_d` 送入
  `eh2_exu_mul_ctl`。实例输出直接命名为 `exu_mul_result_e3`，与乘法器内部 E1/E2/E3
  流水相匹配。
* 第 L400-L406 行：`div_e1` 实例把 `div_p`、`div_rs1_d`、`div_rs2_d` 和
  `dec_div_cancel` 送入 `eh2_exu_div_ctl`。`finish_dly` 连接到 `exu_div_wren`，
  `out` 连接到 `exu_div_result`。
* 两个实例均使用 `.*`，因此 `clk`、`rst_l`、`scan_mode` 等同名端口由顶层自动连接。

接口关系：

* 被调用：`eh2_exu.sv` 调用两个子模块。
* 调用：`eh2_exu_mul_ctl` 内部使用 `rvoclkhdr`、`rvdff` 和组合 bitmanip 逻辑；
  `eh2_exu_div_ctl` 按参数选择具体除法器实现。
* 共享状态：两者共享 `pt` 参数包；除法器还共享 `dec_div_cancel` 控制。

§2.8  primary ALU 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：I0/I1 primary ALU 在 E1 产生 `exu_i*_result_e1`、PC 寄存输出、预测包寄存输出
以及 upper flush。它们接收 D-stage 操作数和 D-stage branch immediate。

关键代码（`rtl/design/exu/eh2_exu.sv:L423-L462`）：

.. code-block:: systemverilog

      eh2_exu_alu_ctl #(.pt(pt)) i0_alu_e1 (.*,
                             .b_enable      ( dec_i0_branch_d                          ),   // I
                             .c_enable      ( i0_e1_ctl_en                             ),   // I
                             .d_enable      ( i0_e1_data_en                            ),   // I
                             .predict_p     ( i0_predict_newp_d                        ),   // I
                             .valid         ( dec_i0_alu_decode_d                      ),   // I
                             .flush         ( exu_flush_final                          ),   // I
                             .a             ( i0_rs1_final_d[31:0]                     ),   // I
                             .b             ( i0_rs2_d[31:0]                           ),   // I
                             .pc            ( dec_i0_pc_d[31:1]                        ),   // I
                             .brimm         ( dec_i0_br_immed_d[pt.BTB_TOFFSET_SIZE:1] ),   // I
                             .ap_in_tid     ( i0_ap.tid                                ),   // I
                             .ap            ( i0_ap_e1                                 ),   // I
                             .out           ( exu_i0_result_e1[31:0]                   ),   // O
                             .flush_upper   ( i0_flush_upper_e1                        ),   // O
                             .flush_path    ( i0_flush_path_e1[31:1]                   ),   // O
                             .predict_p_ff  ( i0_predict_p_e1                          ),   // O
                             .pc_ff         ( exu_i0_pc_e1[31:1]                       ),   // O
                             .pred_correct  ( i0_pred_correct_upper_e1                 ));  // O

逐段解释：

* 第 L423-L441 行：I0 primary ALU 以 `i0_predict_newp_d` 和 D-stage 操作数为输入，
  输出 E1 结果、E1 PC、upper flush 路径和更新后的预测包。
* 第 L429 行：ALU 的 `flush` 输入接 `exu_flush_final`，因此 ALU 内部的
  `valid_ff` 会在同线程 flush 时被清掉。
* 第 L434-L435 行：`ap_in_tid` 使用当前 D-stage `i0_ap.tid`，而 `ap` 连接到
  已经通过 L499 流水到 E1 的 `i0_ap_e1`。
* 第 L444-L462 行：I1 primary ALU 与 I0 对称，但输入 `a` 是 `i1_rs1_d`，没有
  `i0_rs1_final_d` 的 CSR 清零路径。

接口关系：

* 被调用：`eh2_exu.sv` 调用两个 `eh2_exu_alu_ctl` 实例。
* 调用：每个 ALU 实例内部调用 `rvbradder` 并使用多个 `rvdff*` 寄存器。
* 共享状态：`exu_flush_final` 是按线程的 flush 向量，参与 ALU valid gating。

§2.9  预测元数据流水
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：EXU 将 fghr、BTB index、btag、toffset 打包成 `predpipe`，再和
`eh2_predict_pkt_t` 一起从 D/E1 传播到 E4。该路径给 E4 分支更新和 final mispredict
打包使用。

关键代码（`rtl/design/exu/eh2_exu.sv:L466-L484`）：

.. code-block:: systemverilog

      assign i0_predpipe_d[PREDPIPESIZE-1:0] = {i0_predict_fghr_d, i0_predict_index_d, i0_predict_btag_d, i0_predict_toffset_d};
      assign i1_predpipe_d[PREDPIPESIZE-1:0] = {i1_predict_fghr_d, i1_predict_index_d, i1_predict_btag_d, i1_predict_toffset_d};


      rvdffppie #(.WIDTH($bits(eh2_predict_pkt_t)),.LEFT(19),.RIGHT(9))  i0_pp_e2_ff         (.*, .clk(clk), .en ( i0_e2_ctl_en ), .den(i0_e2_data_en & dec_i0_branch_e1), .din( i0_predict_p_e1 ),  .dout( i0_pp_e2       ) );
      rvdffppie #(.WIDTH($bits(eh2_predict_pkt_t)),.LEFT(19),.RIGHT(9))  i0_pp_e3_ff         (.*, .clk(clk), .en ( i0_e3_ctl_en ), .den(i0_e3_data_en & dec_i0_branch_e2), .din( i0_pp_e2        ),  .dout( i0_pp_e3       ) );
      rvdffppie #(.WIDTH($bits(eh2_predict_pkt_t)),.LEFT(19),.RIGHT(9))  i1_pp_e2_ff         (.*, .clk(clk), .en ( i1_e2_ctl_en ), .den(i1_e2_data_en & dec_i1_branch_e1), .din( i1_predict_p_e1 ),  .dout( i1_pp_e2       ) );
      rvdffppie #(.WIDTH($bits(eh2_predict_pkt_t)),.LEFT(19),.RIGHT(9))  i1_pp_e3_ff         (.*, .clk(clk), .en ( i1_e3_ctl_en ), .den(i1_e3_data_en & dec_i1_branch_e2), .din( i1_pp_e2        ),  .dout( i1_pp_e3       ) );


      rvdffe #(PREDPIPESIZE)                                   i0_predpipe_e1_ff   (.*, .clk(clk), .en ( i0_e1_data_en & dec_i0_branch_d ),  .din( i0_predpipe_d   ),  .dout( i0_predpipe_e1 ) );
      rvdffe #(PREDPIPESIZE)                                   i0_predpipe_e2_ff   (.*, .clk(clk), .en ( i0_e2_data_en & dec_i0_branch_e1),  .din( i0_predpipe_e1  ),  .dout( i0_predpipe_e2 ) );

逐段解释：

* 第 L466-L467 行：I0/I1 分别把预测历史和 BTB 元数据按固定顺序拼成 `predpipe_d`。
  后续 L620-L636 和 L660-L663 依赖这个拼接顺序拆包。
* 第 L470-L473 行：预测 packet 本体从 E1 输出进入 E2/E3 寄存器，enable 与对应 slot
  的 control/data enable 和 branch 标记绑定。
* 第 L476-L484 行：`predpipe` 从 D 传到 E4。I0/I1 都有 E1、E2、E3、E4 四级寄存器。
* L496-L497 又把 `i0_pp_e3`、`i1_pp_e3` 分配给 E4 ALU 输入 `i0_pp_e4_in`、
  `i1_pp_e4_in`，用于 secondary ALU 的 E4 分支校验。

接口关系：

* 被调用：DEC 预测字段驱动 `predpipe_d`。
* 调用：E4 分支输出、mispredict 更新和 GHR 修复读取这些流水寄存器。
* 共享状态：`PREDPIPESIZE` 由 BTB/BHT 参数计算，见 `eh2_exu.sv:L297-L299`。

§2.10  ALU 控制包与 secondary 操作数流水
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：EXU 将 `eh2_alu_pkt_t` 从 D/E1 推进到 E4，并把 secondary ALU 需要的 RS1、
RS2 和 branch immediate 从 D 级推进到 E3，再在 E2/E3 允许 bypass 覆盖。

关键代码（`rtl/design/exu/eh2_exu.sv:L499-L555`）：

.. code-block:: systemverilog

      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e1_ff (.*,  .clk(clk), .en(i0_e1_data_en), .din(i0_ap),   .dout(i0_ap_e1) );
      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e2_ff (.*,  .clk(clk), .en(i0_e2_data_en), .din(i0_ap_e1),.dout(i0_ap_e2) );
      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e3_ff (.*,  .clk(clk), .en(i0_e3_data_en), .din(i0_ap_e2),.dout(i0_ap_e3) );
      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i0_ap_e4_ff (.*,  .clk(clk), .en(i0_e4_data_en), .din(i0_ap_e3),.dout(i0_ap_e4) );

      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e1_ff (.*,  .clk(clk), .en(i1_e1_data_en), .din(i1_ap),   .dout(i1_ap_e1) );
      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e2_ff (.*,  .clk(clk), .en(i1_e2_data_en), .din(i1_ap_e1),.dout(i1_ap_e2) );
      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e3_ff (.*,  .clk(clk), .en(i1_e3_data_en), .din(i1_ap_e2),.dout(i1_ap_e3) );
      rvdfflie #(.WIDTH($bits(eh2_alu_pkt_t)),.LEFT(25)) i1_ap_e4_ff (.*,  .clk(clk), .en(i1_e4_data_en), .din(i1_ap_e3),.dout(i1_ap_e4) );


      assign i0_rs1_e2_final[31:0] = (dec_i0_rs1_bypass_en_e2) ? i0_rs1_bypass_data_e2[31:0] : i0_rs1_e2[31:0];
      assign i0_rs2_e2_final[31:0] = (dec_i0_rs2_bypass_en_e2) ? i0_rs2_bypass_data_e2[31:0] : i0_rs2_e2[31:0];
      assign i1_rs1_e2_final[31:0] = (dec_i1_rs1_bypass_en_e2) ? i1_rs1_bypass_data_e2[31:0] : i1_rs1_e2[31:0];

逐段解释：

* 第 L499-L507 行：I0/I1 的 ALU 控制包从输入一路寄存到 E4。`LEFT(25)` 是本地
  `rvdfflie` 参数，不在本文推测其物理含义，只说明它属于寄存器实例参数。
* 第 L511-L541 行：源码用 `rvdffe #(64+pt.BTB_TOFFSET_SIZE)` 对 I0/I1 secondary
  ALU 的 RS1、RS2 和 branch immediate 做 D->E1->E2->E3 传播。
* 第 L546-L555 行：E2/E3 的 `*_final` 操作数允许 DEC bypass 数据替换流水寄存值。
  secondary ALU 实例在 L566-L605 使用 E3 final 操作数。

接口关系：

* 被调用：DEC 提供 `i0_ap`、`i1_ap`、secondary enable 和 bypass 控制。
* 调用：E4 ALU 实例读取 `i0_ap_e4`、`i1_ap_e4` 和 E3 final 操作数。
* 共享状态：本段写 `i*_ap_e*`、`i*_rs*_e*` 和 `i*_br_immed_e*` 流水寄存器。

§2.11  secondary ALU 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：secondary ALU 在 E4 校验或执行延迟到 E4 的 ALU/branch 工作。它使用 E3 final
操作数、E3 PC、E3 branch immediate 和 E4 控制包，输出 E4 结果与 lower flush。

关键代码（`rtl/design/exu/eh2_exu.sv:L566-L605`）：

.. code-block:: systemverilog

      eh2_exu_alu_ctl #(.pt(pt)) i0_alu_e4 (.*,
                             .b_enable      ( dec_i0_branch_e3                         ),   // I
                             .c_enable      ( i0_e4_ctl_en                             ),   // I
                             .d_enable      ( i0_e4_data_en                            ),   // I
                             .predict_p     ( i0_pp_e4_in                              ),   // I
                             .valid         ( dec_i0_sec_decode_e3                     ),   // I
                             .flush         ( dec_tlu_flush_lower_wb                   ),   // I
                             .a             ( i0_rs1_e3_final[31:0]                    ),   // I
                             .b             ( i0_rs2_e3_final[31:0]                    ),   // I
                             .pc            ( dec_i0_pc_e3[31:1]                       ),   // I
                             .brimm         ( i0_br_immed_e3[pt.BTB_TOFFSET_SIZE:1]    ),   // I
                             .ap_in_tid     ( i0_ap_e3.tid                             ),   // I
                             .ap            ( i0_ap_e4                                 ),   // I
                             .out           ( exu_i0_result_e4[31:0]                   ),   // O
                             .flush_upper   ( exu_i0_flush_lower_e4                    ),   // O
                             .flush_path    ( exu_i0_flush_path_e4[31:1]               ),   // O
                             .predict_p_ff  ( i0_predict_p_e4                          ),   // O
                             .pc_ff         ( i0_alu_pc_unused[31:1]                   ),   // O
                             .pred_correct  ( i0_pred_correct_lower_e4                 ));  // O

逐段解释：

* 第 L566-L584 行：I0 E4 ALU 的 `flush_upper` 端口被顶层命名为
  `exu_i0_flush_lower_e4`。这说明同一个 ALU 子模块端口在 E1 被用于 upper flush，
  在 E4 实例上成为 lower flush 输出。
* 第 L572 行：E4 ALU 的 `flush` 输入是 `dec_tlu_flush_lower_wb`，不是
  `exu_flush_final`。这与 E1 ALU 的 flush 输入不同。
* 第 L587-L605 行：I1 E4 ALU 与 I0 对称，输出 `exu_i1_result_e4`、
  `exu_i1_flush_lower_e4` 和 `exu_i1_flush_path_e4`。

接口关系：

* 被调用：`eh2_exu.sv` 调用两个 E4 ALU 实例。
* 调用：每个 ALU 实例内部重新计算 ALU 输出、分支方向和 flush path。
* 共享状态：E4 ALU 读取从 D/E1 传播来的 `predict_p` 和 `predpipe` 元数据。

§2.12  分支 E4 输出和 mispredict 打包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：EXU 把 E4 的 `i*_predict_p_e4` 和 `i*_predpipe_e4` 拆成给 DEC/IFU 的分支
更新字段，并在多个 flush 源之间选择 final mispredict packet。

关键代码（`rtl/design/exu/eh2_exu.sv:L608-L663`）：

.. code-block:: systemverilog

      assign exu_i0_br_hist_e4[1:0]               =  i0_predict_p_e4.hist[1:0];
      assign exu_i0_br_bank_e4                    =  i0_predict_p_e4.bank;
      assign exu_i0_br_error_e4                   =  i0_predict_p_e4.br_error;
      assign exu_i0_br_middle_e4                  =  i0_predict_p_e4.pc4 ^ i0_predict_p_e4.boffset;
      assign exu_i0_br_start_error_e4             =  i0_predict_p_e4.br_start_error;

      assign exu_i0_br_valid_e4                   =  i0_predict_p_e4.valid;
      assign exu_i0_br_mp_e4                      =  i0_predict_p_e4.misp; // needed to squash i1 error
      assign exu_i0_br_ret_e4                     =  i0_predict_p_e4.pret;
      assign exu_i0_br_call_e4                    =  i0_predict_p_e4.pcall;
      assign exu_i0_br_way_e4                     =  i0_predict_p_e4.way;

      assign {exu_i0_br_fghr_e4[pt.BHT_GHR_SIZE-1:0],
              exu_i0_br_index_e4[pt.BTB_ADDR_HI:pt.BTB_ADDR_LO]} =  i0_predpipe_e4[PREDPIPESIZE-1:pt.BTB_BTAG_SIZE+pt.BTB_TOFFSET_SIZE];

逐段解释：

* 第 L608-L618 行：I0 的 E4 分支输出直接来自 `i0_predict_p_e4`，包括 history、bank、
  error、valid、misp、return/call 和 way。
* 第 L620-L621 行：I0 的 fghr 和 index 从 `i0_predpipe_e4` 高位切片中拆出，与 L466
  的拼接顺序对应。
* 第 L623-L636 行：I1 的 E4 分支输出按相同结构从 `i1_predict_p_e4` 和
  `i1_predpipe_e4` 拆出。
* 第 L645-L653 行：final mispredict 的优先选择顺序是 I0 lower、I1 lower、I0 upper、
  I1 upper；没有 flush 时输出 `'0`。
* 第 L660-L663 行：`exu_mp_index`、`exu_mp_btag`、`exu_mp_toffset` 和 `exu_mp_eghr`
  从 `final_predpipe_mp_ff` 拆出，供 IFU_DP 更新使用。

接口关系：

* 被调用：E1/E4 ALU 产生 `i*_predict_p_*` 和 flush。
* 调用：本段输出给 DEC 和 IFU_DP 的分支更新接口。
* 共享状态：`final_predpipe_mp_ff` 在 L688-L689 用 `active_thread_l2clk[i]` 寄存。

§2.13  GHR 更新与 flush 汇总
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：每个线程独立计算 E1 GHR、E4 GHR、flush path 和最终 flush。源码用
`for (genvar i=0; i<pt.NUM_THREADS; i++)` 明确按线程复制逻辑。

关键代码（`rtl/design/exu/eh2_exu.sv:L640-L709`）：

.. code-block:: systemverilog

      for (genvar i=0; i<pt.NUM_THREADS; i++) begin

         assign fp_enable[i]                             = (exu_i0_flush_lower_e4[i]) | (exu_i1_flush_lower_e4[i]) |
                                                           (i0_flush_upper_e1[i])     | (i1_flush_upper_e1[i]);

         assign after_flush_eghr[i][pt.BHT_GHR_SIZE-1:0] = (i0_flush_upper_e2[i] | i1_flush_upper_e2[i] & ~dec_tlu_flush_lower_wb[i]) ? ghr_e1[i][pt.BHT_GHR_SIZE-1:0] : ghr_e4[i][pt.BHT_GHR_SIZE-1:0];

         assign exu_mp_fghr[i][pt.BHT_GHR_SIZE-1:0]      =  after_flush_eghr[i][pt.BHT_GHR_SIZE-1:0];     // fghr repair value

        // E1 GHR - fill in the ptaken for secondary branches.

         assign i0_valid_e1[i]  = ~exu_flush_final[i] & (i0_ap_e1.tid==i) & ~flush_final_f[i] & (i0_predict_p_e1.valid | i0_predict_p_e1.misp);
         assign i1_valid_e1[i]  = ~exu_flush_final[i] & (i1_ap_e1.tid==i) & ~flush_final_f[i] & (i1_predict_p_e1.valid | i1_predict_p_e1.misp) & ~(i0_flush_upper_e1[i]);

逐段解释：

* 第 L640 行：GHR 与 flush 汇总逻辑按 `pt.NUM_THREADS` 展开。
* 第 L642-L643 行：`fp_enable[i]` 汇总 I0/I1 lower flush 和 I0/I1 upper flush。它随后
  驱动 final predict packet 寄存器的 enable。
* 第 L656-L658 行：`after_flush_eghr` 在 upper flush 已经进入 E2 且没有 lower WB
  flush 时选择 `ghr_e1`，否则选择 `ghr_e4`。`exu_mp_fghr` 直接等于该修复值。
* 第 L668-L675 行：E1 GHR 使用 `i0_taken_e1`、`i1_taken_e1` 更新。双发有效且 I0
  没有 mispredict 时，一次移入两个 taken 位。
* 第 L679-L684 行：E4 GHR 使用 `i0_predict_p_e4.ataken` 和 `i1_predict_p_e4.ataken`
  更新。它依赖 commit 侧有效信号 `dec_tlu_i0_valid_e4` 和 `dec_tlu_i1_valid_e4`。
* 第 L701-L703 行：最终 flush 是 `dec_tlu_flush_lower_wb`、`i0_flush_upper_e2` 和
  `i1_flush_upper_e2` 的按线程 OR。

接口关系：

* 被调用：ALU flush、TLU flush、predict packet 和 ALU packet tid 驱动本段。
* 调用：本段输出 `exu_flush_final`、`exu_i0_flush_final`、`exu_i1_flush_final`、
  `exu_mp_fghr` 和 final predict packet。
* 共享状态：`ghr_e1`、`ghr_e4`、`flush_final_f` 和 `fp_enable_ff` 是每线程寄存状态。

§2.14  early flush 与 NPC 选择
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：当 `pt.BTB_USE_SRAM` 为真时，EXU 提供 early flush 输出；同时在 E4 为每个线程
选择 commit NPC。NPC 选择在 I1 有效时优先考虑 I1，否则使用 I0。

关键代码（`rtl/design/exu/eh2_exu.sv:L712-L805`）：

.. code-block:: systemverilog

         if(pt.BTB_USE_SRAM) begin
            assign flush_path_e1[i][31:1]           = (i0_flush_upper_e1[i])       ?  i0_flush_path_e1[31:1]     :  i1_flush_path_e1[31:1];
            assign flush_path_e4[i][31:1]           = (exu_i0_flush_lower_e4[i])         ?  exu_i0_flush_path_e4[31:1] :  exu_i1_flush_path_e4[31:1];

            // SRAM BTB arch moves flushes to BF stage, but only mispredicts. TLU flushes are still a cycle later
            assign exu_flush_path_final_early[i][31:1]    =  (exu_i0_flush_lower_e4[i] | exu_i1_flush_lower_e4[i])     ?  flush_path_e4[i][31:1]  :
                                                            ((i0_flush_upper_e1[i] | i1_flush_upper_e1[i]) ?  flush_path_e1[i][31:1]   : '0);
            assign exu_flush_final_early[i]            =    exu_i0_flush_lower_e4[i] | exu_i1_flush_lower_e4[i] | i0_flush_upper_e1[i]  | i1_flush_upper_e1[i];
         end

逐段解释：

* 第 L713-L720 行：`pt.BTB_USE_SRAM` 为真时，early flush path 可以来自 E4 lower
  flush 或 E1 upper flush。源码注释限定了该 early path 针对 mispredict，TLU flush
  仍晚一个周期。
* 第 L722-L725 行：`pt.BTB_USE_SRAM` 为假时，early flush 输出被置零。
* 第 L728-L736 行：`pred_correct_npc_e2` 继续寄存到 E3/E4，作为预测正确时 NPC 来源。
* 第 L793-L797 行：当对应 slot 是 secondary decode 时，E4 pred_correct 和 flush_path
  采用 lower ALU 结果；否则采用 upper 路径流水值。
* 第 L800-L804 行：`exu_npc_e4` 在 I1 有效且未被 I0 同线程 flush 压制时使用 I1，
  否则使用 I0。若对应 slot 预测正确则使用 `pred_correct_npc_e4`，否则使用 flush path。

接口关系：

* 被调用：BTB 参数、ALU flush、TLU flush 和 pred_correct 流水驱动本段。
* 调用：输出给 TLU/DEC/IFU 的 early flush 与 commit NPC 路径。
* 共享状态：`pred_correct_npc_e3/e4` 和 upper flush path 通过 `rvdffpcie` 寄存。

§3  `eh2_exu_alu_ctl.sv` ALU 控制器
-----------------------------------

`eh2_exu_alu_ctl.sv` 是一个可复用 ALU 实例。`eh2_exu.sv` 在 E1 和 E4 分别实例化它，
因此同一份 ALU 代码同时服务 primary ALU 与 secondary ALU。

§3.1  ALU 模块接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 控制器接收 flush、三类 enable、valid、操作数、PC、预测包和 branch
immediate，输出运算结果、flush、flush path、寄存 PC、预测是否正确和更新后的预测包。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L17-L47`）：

.. code-block:: systemverilog

   module eh2_exu_alu_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input  logic                          clk,               // Top level clock
      input  logic                          rst_l,             // Reset
      input  logic                          scan_mode,         // Scan control

      input  logic [pt.NUM_THREADS-1:0]     flush,             // Flush pipeline
      input  logic                          b_enable,          // Clock enable - branch
      input  logic                          c_enable,          // Clock enable - control
      input  logic                          d_enable,          // Clock enable - data
      input  logic                          valid,             // Valid
      input  logic                          ap_in_tid,         // predecodes
      input  eh2_alu_pkt_t                 ap,                // predecodes
      input  logic [31:0]                   a,                 // A operand
      input  logic [31:0]                   b,                 // B operand
      input  logic [31:1]                   pc,                // for pc=pc+2,4 calculations

逐段解释：

* 第 L17-L21 行：ALU 模块与 EXU 顶层一样导入 package 并包含参数。
* 第 L27-L31 行：`flush` 是每线程向量；`b_enable`、`c_enable`、`d_enable`
  分别用于 branch、control 和 data 相关寄存器。
* 第 L32-L38 行：`ap_in_tid` 与 `ap.tid` 共同用于线程级 flush gating；`a`、`b`、
  `pc`、`predict_p`、`brimm` 是 ALU 和分支计算输入。
* 第 L41-L46 行：ALU 输出不仅有 `out`，还返回 flush、flush path、flopped PC、
  `pred_correct` 和更新后的 `predict_p_ff`。

接口关系：

* 被调用：`eh2_exu.sv` 四次实例化本模块。
* 调用：本模块内部调用 `rvbradder`，并使用 `rvdffie`、`rvdffe`、`rvdffpcie`、
  `rvdffppie`。
* 共享状态：`pp_ff`、`a_ff`、`b_ff`、`pc_ff`、`valid_ff` 是 ALU 本地寄存状态。

§3.2  bitmanip 开关对 predecode 的 gating
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 通过 `pt.BITMANIP_*` 参数决定是否接受 `ap` 控制包中的 bitmanip 控制位。
未启用的扩展对应控制位被固定为 `1'b0`。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L110-L201`）：

.. code-block:: systemverilog

      if (pt.BITMANIP_ZBB == 1)
        begin
          assign ap_clz          =  ap.clz;
          assign ap_ctz          =  ap.ctz;
          assign ap_cpop         =  ap.cpop;
          assign ap_sext_b       =  ap.sext_b;
          assign ap_sext_h       =  ap.sext_h;
          assign ap_min          =  ap.min;
          assign ap_max          =  ap.max;
        end
      else
        begin
          assign ap_clz          =  1'b0;
          assign ap_ctz          =  1'b0;
          assign ap_cpop         =  1'b0;
          assign ap_sext_b       =  1'b0;
          assign ap_sext_h       =  1'b0;

逐段解释：

* 第 L110-L129 行：`pt.BITMANIP_ZBB` 控制 `clz`、`ctz`、`cpop`、`sext_b`、
  `sext_h`、`min`、`max`。关闭时这些内部 `ap_*` 信号全部为 0。
* 第 L132-L147 行：`BITMANIP_ZBB` 或 `BITMANIP_ZBP` 任一启用时，ALU 接受 `rol`、
  `ror`、`grev/gorc` 派生的 `rev8`、`orc_b` 和 `zbb`。
* 第 L150-L163 行：`pt.BITMANIP_ZBS` 控制 `bset`、`bclr`、`binv`、`bext`。
* 第 L166-L185 行：`packu` 仅受 ZBP 控制；`pack`、`packh` 在 ZBB/ZBP/ZBE/ZBF
  任一启用时接收 `ap` 控制位。
* 第 L188-L201 行：`pt.BITMANIP_ZBA` 控制 `sh1add`、`sh2add`、`sh3add` 和 `zba`。

接口关系：

* 被调用：DEC 产生 `eh2_alu_pkt_t ap`；参数 `pt.BITMANIP_*` 决定哪些字段有效。
* 调用：后续 adder、logic、shift、pack、single-bit 操作都读取这些内部 `ap_*` 信号。
* 共享状态：此段是 elaboration-time 条件生成样式的组合赋值，不写寄存器。

§3.3  ALU 输入寄存
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 在 enable 条件下寄存 valid、A/B 操作数、PC、branch immediate 和预测包。
`valid_ff` 同时考虑 `flush[ap_in_tid]`。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L210-L215`）：

.. code-block:: systemverilog

      rvdffie  #(1,1)                     validff         (.*, .clk(clk),                               .din(valid & ~flush[ap_in_tid]),    .dout(valid_ff));
      rvdffe #(32)                        aff             (.*, .clk(clk),        .en(d_enable & valid), .din(a[31:0]),                      .dout(a_ff[31:0]));
      rvdffe #(32)                        bff             (.*, .clk(clk),        .en(d_enable & valid), .din(b[31:0]),                      .dout(b_ff[31:0]));
      rvdffpcie #(31)                     pcff            (.*, .clk(clk),        .en(d_enable),         .din(pc[31:1]),                     .dout(pc_ff[31:1]));   // all PCs run through here
      rvdffe #(pt.BTB_TOFFSET_SIZE)       brimmff         (.*, .clk(clk),        .en(d_enable),         .din(brimm[pt.BTB_TOFFSET_SIZE:1]), .dout(brimm_ff[pt.BTB_TOFFSET_SIZE:1]));
      rvdffppie #(.WIDTH($bits(eh2_predict_pkt_t)),.LEFT(19),.RIGHT(9)) predictpacketff (.*, .clk(clk), .en(c_enable), .den(b_enable & d_enable),  .din(predict_p),  .dout(pp_ff));

逐段解释：

* 第 L210 行：`valid_ff` 只在 `valid` 为 1 且同线程 flush 为 0 时置位。
* 第 L211-L212 行：A/B 操作数只有在 `d_enable & valid` 时寄存，避免无效数据更新。
* 第 L213-L214 行：PC 和 branch immediate 只受 `d_enable` 控制，不额外要求 `valid`。
* 第 L215 行：预测包 `pp_ff` 受 control enable 控制，并用 `b_enable & d_enable`
  作为 data enable。

接口关系：

* 被调用：`eh2_exu.sv` 为 E1/E4 ALU 实例提供 enable 和输入数据。
* 调用：后续 ALU、分支和预测更新逻辑都读取这些 flopped 信号。
* 共享状态：`valid_ff`、`a_ff`、`b_ff`、`pc_ff`、`brimm_ff`、`pp_ff` 是本模块寄存状态。

§3.4  adder、比较与基本逻辑
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 的加减法、Zba shifted-add、比较和 AND/OR/XOR 类逻辑都在本段组合完成。
`lt` 和 `ge` 同时被 SLT、MIN/MAX 和 branch 条件使用。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L238-L266`）：

.. code-block:: systemverilog

      assign zba_a_ff[31:0]      = ( {32{ ap_sh1add}} & {a_ff[30:0],1'b0} ) |
                                   ( {32{ ap_sh2add}} & {a_ff[29:0],2'b0} ) |
                                   ( {32{ ap_sh3add}} & {a_ff[28:0],3'b0} ) |
                                   ( {32{~ap_zba   }} &  a_ff[31:0]       );


      logic        [31:0]    bm;

      assign bm[31:0]            = ( ap.sub )  ?  ~b_ff[31:0]  :  b_ff[31:0];

      assign {cout, aout[31:0]}  = {1'b0, zba_a_ff[31:0]} + {1'b0, bm[31:0]} + {32'b0, ap.sub};

      assign ov                  = (~a_ff[31] & ~bm[31] &  aout[31]) |
                                   ( a_ff[31] &  bm[31] & ~aout[31] );

      assign lt                  = (~ap.unsign & (neg ^ ov)) |
                                   ( ap.unsign & ~cout);

逐段解释：

* 第 L238-L241 行：Zba 操作把 `a_ff` 左移 1、2、3 位后送入 adder；非 Zba 时使用
  原始 `a_ff`。
* 第 L246-L248 行：SUB 通过对 `b_ff` 取反并加上 `ap.sub` 实现；ADD 和 Zba
  使用同一个加法器。
* 第 L250-L259 行：`ov`、`lt`、`eq`、`ne`、`neg`、`ge` 由 adder 输出和操作数比较得到。
  `ap.unsign` 决定 `lt` 使用 signed overflow 公式还是 carry-out。
* 第 L261-L266 行：逻辑输出 `lout` 在普通逻辑和 Zbb 取反逻辑之间切换。`ap_zbb`
  为真时，AND/OR/XOR 使用 `~b_ff` 参与计算。

接口关系：

* 被调用：`ap` 控制位和 `a_ff/b_ff` 驱动本段。
* 调用：`out` 结果选择、branch 条件、MIN/MAX 和 SLT 读取本段结果。
* 共享状态：组合逻辑不写寄存器。

§3.5  shift、rotate 与 BEXT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 用统一的 `shift_amount`、`shift_extend` 和 `shift_long` 实现 SLL/SRL/SRA、
ROL/ROR 和 BEXT 所需的移位路径。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L274-L301`）：

.. code-block:: systemverilog

      assign shift_amount[5:0]            = ( { 6{ap.sll}}   & (6'd32 - {1'b0,b_ff[4:0]}) ) |   // [5] unused
                                            ( { 6{ap.srl}}   &          {1'b0,b_ff[4:0]}  ) |
                                            ( { 6{ap.sra}}   &          {1'b0,b_ff[4:0]}  ) |
                                            ( { 6{ap_rol}}   & (6'd32 - {1'b0,b_ff[4:0]}) ) |
                                            ( { 6{ap_ror}}   &          {1'b0,b_ff[4:0]}  ) |
                                            ( { 6{ap_bext}}  &          {1'b0,b_ff[4:0]}  );


      assign shift_mask[31:0]             = ( 32'hffffffff << ({5{ap.sll}} & b_ff[4:0]) );


      assign shift_extend[31:0]           =  a_ff[31:0];

      assign shift_extend[62:32]          = ( {31{ap.sra}} & {31{a_ff[31]}} ) |
                                            ( {31{ap.sll}} &     a_ff[30:0] ) |
                                            ( {31{ap_rol}} &     a_ff[30:0] ) |
                                            ( {31{ap_ror}} &     a_ff[30:0] );

逐段解释：

* 第 L280-L285 行：左移和 rotate-left 通过 `32 - shamt` 转换成右移长向量实现；SRL、
  SRA、ROR、BEXT 使用 `b_ff[4:0]` 作为移位量。
* 第 L288 行：`shift_mask` 只在 `ap.sll` 时左移全 1，用于清除右移模型产生的无效位。
* 第 L291-L296 行：`shift_extend` 的高 31 位根据 SRA、SLL、ROL、ROR 构造。SRA 填充符号位。
* 第 L299-L301 行：`shift_long` 对 63 位长向量右移，`sout` 再与 mask 相与，成为统一 shift 输出。

接口关系：

* 被调用：ALU 输入 `a_ff/b_ff` 和 `ap.sll/srl/sra`、`ap_rol/ror/bext` 控制本段。
* 调用：`out` 的 shift 选择和 BEXT 选择读取 `sout`。
* 共享状态：组合逻辑不写寄存器。

§3.6  CLZ、CTZ、CPOP、SEXT 与 MIN/MAX
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 在组合逻辑中实现计数、符号扩展和 min/max。CLZ 与 CTZ 共享 leading-zero
扫描器，CTZ 先反转输入位序。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L314-L369`）：

.. code-block:: systemverilog

      assign bitmanip_clz_ctz_sel         =  ap_clz | ap_ctz;

      assign bitmanip_a_reverse_ff[31:0]  = {a_ff[0],  a_ff[1],  a_ff[2],  a_ff[3],  a_ff[4],  a_ff[5],  a_ff[6],  a_ff[7],
                                             a_ff[8],  a_ff[9],  a_ff[10], a_ff[11], a_ff[12], a_ff[13], a_ff[14], a_ff[15],
                                             a_ff[16], a_ff[17], a_ff[18], a_ff[19], a_ff[20], a_ff[21], a_ff[22], a_ff[23],
                                             a_ff[24], a_ff[25], a_ff[26], a_ff[27], a_ff[28], a_ff[29], a_ff[30], a_ff[31]};

      assign bitmanip_lzd_ff[31:0]        = ( {32{ap_clz}} & a_ff[31:0]                 ) |
                                            ( {32{ap_ctz}} & bitmanip_a_reverse_ff[31:0]);

逐段解释：

* 第 L314-L322 行：CLZ 直接使用 `a_ff`；CTZ 使用位反转后的 `bitmanip_a_reverse_ff`。
* 第 L328-L342 行：`always_comb` 从 bit 31 开始扫描，遇到 0 时计数加 1 并左移，
  遇到 1 时停止。全 0 输入会循环 32 次，编码最高位表示 32。
* 第 L345 行：`bitmanip_clz_ctz_result` 用 `{dw_lzd_enc[5], ...}` 保留 32 的编码。
* 第 L358-L369 行：CPOP 循环累加 `a_ff` 的 32 个 bit，结果只在 `ap_cpop` 为真时输出。
* 第 L378-L396 行：SEXT.B/SEXT.H 用 bit 7 或 bit 15 复制扩展；MIN/MAX 通过 `ge ^ ap_min`
  在 A/B 中选择结果。

接口关系：

* 被调用：bitmanip gating 产生的 `ap_clz`、`ap_ctz`、`ap_cpop`、`ap_sext_*`、
  `ap_min`、`ap_max` 控制本段。
* 调用：最终 `out` 选择读取这些结果。
* 共享状态：组合逻辑不写寄存器。

§3.7  PACK、REV8、ORC.B 与单 bit 操作
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 将 pack、byte reverse、OR-combine-byte 和单 bit set/clear/invert 的结果并入
最终 `out` OR 树。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L400-L457`）：

.. code-block:: systemverilog

      assign bitmanip_pack_result[31:0]   = {32{ap_pack}}  & {b_ff[15:0], a_ff[15:0]};
      assign bitmanip_packu_result[31:0]  = {32{ap_packu}} & {b_ff[31:16],a_ff[31:16]};
      assign bitmanip_packh_result[31:0]  = {32{ap_packh}} & {16'b0,b_ff[7:0],a_ff[7:0]};




      // * * * * * * * * * * * * * * * * * *  BitManip  :  REV8   * * * * * * * * * * * * * * * * * * * * *

      logic        [31:0]    bitmanip_rev8_result;
      logic        [31:0]    bitmanip_orc_b_result;

      assign bitmanip_rev8_result[31:0]   = {32{ap_rev8}}  & {a_ff[7:0],a_ff[15:8],a_ff[23:16],a_ff[31:24]};

逐段解释：

* 第 L406-L408 行：`pack` 拼接 B/A 的低半字；`packu` 拼接 B/A 的高半字；
  `packh` 拼接 B/A 的低字节并在高 16 位补 0。
* 第 L418 行：`rev8` 按字节反转 `a_ff`。
* 第 L443 行：`orc_b` 对每个 byte 做 OR reduction，再复制成该 byte 的 8 个 bit。
* 第 L453-L457 行：`bitmanip_sb_1hot` 根据 `b_ff[4:0]` 生成 one-hot，
  BSET/BCLR/BINV 分别执行 OR、AND with inverse、XOR。

接口关系：

* 被调用：`ap_pack*`、`ap_rev8`、`ap_orc_b`、`ap_bset/bclr/binv` 控制本段。
* 调用：最终 `out` 选择读取本段结果。
* 共享状态：组合逻辑不写寄存器。

§3.8  `out` 结果 OR 树
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 最终结果不是用 case 语句实现，而是多个互斥掩码结果按位 OR 得到。源码依赖
decode/predecode 保证同一条指令只打开对应结果来源。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L467-L492`）：

.. code-block:: systemverilog

      assign sel_shift           =  ap.sll  | ap.srl | ap.sra | ap_rol | ap_ror;
      assign sel_adder           = (ap.add  | ap.sub | ap_zba) & ~ap.slt & ~ap_min & ~ap_max;
      assign sel_pc              =  ap.jal  | pp_ff.pcall | pp_ff.pja | pp_ff.pret;
      assign csr_write_data[31:0]= (ap.csr_imm)  ?  b_ff[31:0]  :  a_ff[31:0];

      assign slt_one             =  ap.slt & lt;



      assign out[31:0]           =                        lout[31:0]             |
                                   ({32{sel_shift}}    &  sout[31:0]           ) |
                                   ({32{sel_adder}}    &  aout[31:0]           ) |
                                   ({32{sel_pc}}       & {pcout[31:1],1'b0}    ) |
                                   ({32{ap.csr_write}} &  csr_write_data[31:0] ) |

逐段解释：

* 第 L467-L470 行：`sel_shift`、`sel_adder`、`sel_pc` 和 `csr_write_data` 是结果 OR
  树的主要选择条件。
* 第 L472 行：SLT 结果只在 `ap.slt` 且比较小于时置 bit0。
* 第 L476-L492 行：`out` 依次 OR 入 logic、shift、adder、PC、CSR、SLT、BEXT、
  CLZ/CTZ、CPOP、SEXT、MIN/MAX、PACK、REV8、ORC.B 和 single-bit 结果。
* 由于源码未在本段提供冲突检测，本章不声称 OR 树会自行解决多控制位冲突；互斥关系应来自
  上游 decode 控制。

接口关系：

* 被调用：所有 ALU 子路径结果和 `ap` 控制位驱动本段。
* 调用：`out` 返回给 `eh2_exu.sv` 的 E1/E4 result 端口。
* 共享状态：组合逻辑不写寄存器。

§3.9  分支实际方向、flush path 与预测包更新
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 用比较结果和预测包计算实际 taken、预测是否正确、flush path、flush 向量和新
history。该逻辑同时服务 E1 primary ALU 和 E4 secondary ALU。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L498-L540`）：

.. code-block:: systemverilog

      assign any_jal             =  ap.jal      |
                                    pp_ff.pcall |
                                    pp_ff.pja   |
                                    pp_ff.pret;

      assign actual_taken        = (ap.beq & eq) |
                                   (ap.bne & ne) |
                                   (ap.blt & lt) |
                                   (ap.bge & ge) |
                                    any_jal;

      // for a conditional br pcout[] will be the opposite of the branch prediction
      // for jal or pcall, it will be the link address pc+2 or pc+4

      rvbradder ibradder (
                        .pc     ( pc_ff[31:1]    ),
                        .offset ( brimm_ff[pt.BTB_TOFFSET_SIZE:1] ),
                        .dout   ( pcout[31:1]    ));

逐段解释：

* 第 L498-L507 行：`any_jal` 覆盖 JAL、call、jump-alias 和 return；`actual_taken`
  对条件分支使用比较结果，对 `any_jal` 直接视为 taken。
* 第 L512-L515 行：`rvbradder` 用 `pc_ff` 和 `brimm_ff` 计算 `pcout`。
* 第 L522-L527 行：`pred_correct` 只对非 JAL 条件分支判断方向预测是否正确；
  `flush_path` 对 `any_jal` 使用 `aout[31:1]`，否则使用 `pcout[31:1]`。
* 第 L531-L537 行：`cond_mispredict` 检测方向错误，`target_mispredict` 只在 `pp_ff.pret`
  且预测 return target 与 `aout` 不一致时置位。
* 第 L539-L540 行：`flush_upper[i]` 按线程产生，条件包含 JAL、方向错误或 return
  target 错误、`valid_ff`、线程匹配以及未被 flush。

接口关系：

* 被调用：ALU 比较结果、预测包和 branch immediate 驱动本段。
* 调用：`rvbradder` 是下层分支地址加法器。
* 共享状态：`pp_ff`、`pc_ff`、`brimm_ff` 和 `valid_ff` 是本地寄存状态。

§3.10  饱和计数 history 与 `predict_p_ff`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ALU 根据实际 taken 更新 2 bit history，并把 mispredict、actual taken 和新
history 写回输出预测包。

关键代码（`rtl/design/exu/eh2_exu_alu_ctl.sv:L559-L570`）：

.. code-block:: systemverilog

      assign newhist[1]          = ( pp_ff.hist[1] &  pp_ff.hist[0]) | (~pp_ff.hist[0] & actual_taken);
      assign newhist[0]          = (~pp_ff.hist[1] & ~actual_taken)  | ( pp_ff.hist[1] & actual_taken);

      always_comb begin
         predict_p_ff            =  pp_ff;

         predict_p_ff.misp       = ( valid_ff )  ? ( (cond_mispredict | target_mispredict) & ~flush[ap.tid] )  :  pp_ff.misp;
         predict_p_ff.ataken     = ( valid_ff )  ?  actual_taken  :  pp_ff.ataken;
         predict_p_ff.hist[1]    = ( valid_ff )  ?  newhist[1]    :  pp_ff.hist[1];
         predict_p_ff.hist[0]    = ( valid_ff )  ?  newhist[0]    :  pp_ff.hist[0];

      end

逐段解释：

* 第 L559-L560 行：`newhist` 由原 history 和实际 taken 组合得到。源码上方 L544-L557
  给出了 2 bit history 的真值表。
* 第 L562-L564 行：`always_comb` 先把输出预测包初始化为 `pp_ff`，再覆盖需要更新的字段。
* 第 L565 行：`misp` 只在 `valid_ff` 为真时根据方向或 target 错误更新，并被同线程
  `flush[ap.tid]` 屏蔽。
* 第 L566-L568 行：`ataken` 和 history 只在 valid 时更新；无效时保持原预测包字段。

接口关系：

* 被调用：分支校验逻辑驱动 `cond_mispredict`、`target_mispredict` 和 `actual_taken`。
* 调用：输出 `predict_p_ff` 返回 `eh2_exu.sv`，再用于 E4 输出和 mispredict 打包。
* 共享状态：不写时序寄存器；输出是对 `pp_ff` 的组合覆盖。

§4  `eh2_exu_mul_ctl.sv` 乘法与部分 bitmanip
--------------------------------------------

`eh2_exu_mul_ctl.sv` 接收 `eh2_mul_pkt_t mp`、两个 32 bit 操作数和 `lsu_result_dc3`。
它内部有 E1/E2/E3 三段寄存状态，并在 E3 输出普通乘法结果或 bitmanip 结果。

§4.1  模块接口与本地流水状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：乘法器接口暴露 `clk_override`、`a/b`、`lsu_result_dc3`、`mp` 和 `out`。本地状态
包含 `mp_e1/mp_e2`、`valid_e1/valid_e2`、E1/E2/E3 clock enable 和乘积寄存器。

关键代码（`rtl/design/exu/eh2_exu_mul_ctl.sv:L17-L52`）：

.. code-block:: systemverilog

   module eh2_exu_mul_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic          clk,              // Top level clock
      input logic          clk_override,     // Override clock enables
      input logic          rst_l,            // Reset
      input logic          scan_mode,        // Scan mode

      input logic [31:0]   a,                // A operand
      input logic [31:0]   b,                // B operand

      input logic [31:0]   lsu_result_dc3,   // Load result used in E1 bypass

      input eh2_mul_pkt_t mp,               // valid, rs1_sign, rs2_sign, low, load_mul_rs1_bypass_e1, load_mul_rs2_bypass_e1, bitmanip controls

逐段解释：

* 第 L17-L21 行：乘法器模块导入 package 并包含参数。
* 第 L23-L31 行：输入包含顶层时钟、clock override、复位、scan、两个操作数和
  `lsu_result_dc3`。`lsu_result_dc3` 的用途在注释中明确为 E1 bypass。
* 第 L33-L37 行：`mp` 是乘法控制包，`out` 是 32 bit 结果。
* 第 L41-L52 行：`mp_e1/mp_e2`、`valid_e1/valid_e2`、三个 gated clock、E1/E2
  操作数和 E3 乘积寄存器构成三段流水状态。

接口关系：

* 被调用：`eh2_exu.sv:L392-L397` 实例化本模块。
* 调用：本模块使用 `rvoclkhdr` 生成 gated clocks，并使用 `rvdff/rvdffie` 寄存流水状态。
* 共享状态：`mp_e1/mp_e2` 和 `prod_e3` 是乘法器本地状态。

§4.2  bitmanip 控制 gating
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：乘法器承载部分 bitmanip 操作。它按 `pt.BITMANIP_ZBE/ZBC/ZBP/ZBR/ZBF` 控制
`mp_e2` 中的 bcompress、clmul、grev/gorc、shfl、CRC、bfp 和 xperm 控制位。

关键代码（`rtl/design/exu/eh2_exu_mul_ctl.sv:L93-L164`）：

.. code-block:: systemverilog

      if (pt.BITMANIP_ZBE == 1)
        begin
          assign ap_bcompress_e2   =  mp_e2.bcompress;
          assign ap_bdecompress_e2 =  mp_e2.bdecompress;
        end
      else
        begin
          assign ap_bcompress_e2   =  1'b0;
          assign ap_bdecompress_e2 =  1'b0;
        end

      if (pt.BITMANIP_ZBC == 1)
        begin
          assign ap_clmul_e2     =  mp_e2.clmul;
          assign ap_clmulh_e2    =  mp_e2.clmulh;
          assign ap_clmulr_e2    =  mp_e2.clmulr;
        end

逐段解释：

* 第 L93-L102 行：ZBE 使能 bcompress 和 bdecompress；关闭时对应内部控制为 0。
* 第 L104-L115 行：ZBC 使能 `clmul`、`clmulh`、`clmulr`。
* 第 L117-L136 行：ZBP 使能 `grev`、`gorc`、`shfl`、`unshfl`、`xperm_n/b/h`。
* 第 L138-L155 行：ZBR 使能 CRC32 和 CRC32C 的 byte、halfword、word 形式。
* 第 L157-L164 行：ZBF 使能 `bfp`。

接口关系：

* 被调用：DEC 产生的 `mp` 控制包在 E2 成为 `mp_e2`。
* 调用：后续 bitmanip 组合逻辑读取这些 `ap_*_e2` 信号。
* 共享状态：这些信号是组合派生，不写寄存器。

§4.3  clock gating 与 E1/E2/E3 乘法流水
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：乘法器用 `mp.valid`、`valid_e1`、`valid_e2` 和 `clk_override` 生成三段 gated
clock，再把操作数、控制包和乘积推进到 E3。

关键代码（`rtl/design/exu/eh2_exu_mul_ctl.sv:L171-L216`）：

.. code-block:: systemverilog

      // C1 clock enables
      assign mul_c1_e1_clken        = (mp.valid | clk_override);
      assign mul_c1_e2_clken        = (valid_e1 | clk_override);
      assign mul_c1_e3_clken        = (valid_e2 | clk_override);

      // C1 - 1 clock pulse for data
      rvoclkhdr exu_mul_c1e1_cgc    (.*, .en(mul_c1_e1_clken),   .l1clk(exu_mul_c1_e1_clk));
      rvoclkhdr exu_mul_c1e2_cgc    (.*, .en(mul_c1_e2_clken),   .l1clk(exu_mul_c1_e2_clk));
      rvoclkhdr exu_mul_c1e3_cgc    (.*, .en(mul_c1_e3_clken),   .l1clk(exu_mul_c1_e3_clk));


      // --------------------------- Input flops    ----------------------------------

      rvdffie #(2,1)                   valid_ff      (.*, .din({mp.valid,valid_e1}),       .dout({valid_e1,valid_e2}),  .clk(clk));

逐段解释：

* 第 L174-L176 行：E1 clock 由 `mp.valid` 或 override 打开；E2/E3 分别由上一段 valid
  或 override 打开。
* 第 L179-L181 行：三个 `rvoclkhdr` 生成 E1/E2/E3 的本地 clock。
* 第 L186-L189 行：`valid_e1/valid_e2`、`mp_e1`、E1 A/B 输入在对应时钟下寄存。
* 第 L197-L198 行：如果 `mp_e1.load_mul_rs1_bypass_e1` 或
  `mp_e1.load_mul_rs2_bypass_e1` 为真，E1 操作数来自 `lsu_result_dc3`。
* 第 L204-L216 行：`mp_e2`、33 bit 符号扩展操作数、`low_e3` 和 64 bit `prod_e3`
  依次寄存。乘法组合表达式是 `a_ff_e2 * b_ff_e2`。

接口关系：

* 被调用：EXU 顶层传入 `mp`、`clk_override` 和 `lsu_result_dc3`。
* 调用：`rvoclkhdr`、`rvdffie`、`rvdff` 和 SystemVerilog 乘法运算。
* 共享状态：`valid_e1/valid_e2`、`mp_e1/mp_e2`、`a_ff_e2/b_ff_e2`、`prod_e3`。

§4.4  BCOMPRESS 与 BDECOMPRESS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：ZBE 的 bcompress/bdecompress 在 E2 用 `b_ff_e2` 作为选择 mask。bcompress 把
被 mask 选中的 A bit 收集到低位；bdecompress 把低位 A bit 分散到 mask 位置。

关键代码（`rtl/design/exu/eh2_exu_mul_ctl.sv:L230-L273`）：

.. code-block:: systemverilog

      always_comb
        begin

          bcompress_j                      =      0;
          bcompress_test_bit_e2            =   1'b0;
          bcompress_e2[31:0]               =  32'b0;

          for (bcompress_i=0; bcompress_i<32; bcompress_i++)
            begin
                bcompress_test_bit_e2      =  b_ff_e2[bcompress_i];
                if (bcompress_test_bit_e2)
                  begin
                     bcompress_e2[bcompress_j]  =  a_ff_e2[bcompress_i];
                     bcompress_j           =  bcompress_j + 1;
                  end  // IF  bcompress_test_bit
            end        // FOR bcompress_i
        end            // ALWAYS_COMB

逐段解释：

* 第 L230-L246 行：bcompress 从 bit 0 到 bit 31 扫描 `b_ff_e2`。mask bit 为 1 时，
  将同位置 `a_ff_e2` 收集到 `bcompress_j` 指向的低位并递增索引。
* 第 L257-L273 行：bdecompress 也扫描 `b_ff_e2`，但在 mask bit 为 1 时，把
  `a_ff_e2[bdecompress_j]` 写回当前 bit 位置。
* 两段逻辑都先把结果清零，因此未被 mask 选中的输出 bit 为 0。

接口关系：

* 被调用：`ap_bcompress_e2`、`ap_bdecompress_e2` 在最终 bitmanip 选择中决定是否使用结果。
* 调用：只使用组合循环，不调用子模块。
* 共享状态：组合逻辑不写寄存器。

§4.5  CLMUL 与位排列类操作
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：乘法器内部实现 carry-less multiply、grev、gorc、shuffle、unshuffle、CRC、BFP
和 xperm。它们都在 E2 形成 32 bit `bitmanip_e2` 候选结果。

关键代码（`rtl/design/exu/eh2_exu_mul_ctl.sv:L278-L315`）：

.. code-block:: systemverilog

      logic        [62:0]    clmul_raw_e2;


      assign clmul_raw_e2[62:0]     = ( {63{b_ff_e2[00]}} & {31'b0,a_ff_e2[31:0]      } ) ^
                                      ( {63{b_ff_e2[01]}} & {30'b0,a_ff_e2[31:0], 1'b0} ) ^
                                      ( {63{b_ff_e2[02]}} & {29'b0,a_ff_e2[31:0], 2'b0} ) ^
                                      ( {63{b_ff_e2[03]}} & {28'b0,a_ff_e2[31:0], 3'b0} ) ^
                                      ( {63{b_ff_e2[04]}} & {27'b0,a_ff_e2[31:0], 4'b0} ) ^
                                      ( {63{b_ff_e2[05]}} & {26'b0,a_ff_e2[31:0], 5'b0} ) ^
                                      ( {63{b_ff_e2[06]}} & {25'b0,a_ff_e2[31:0], 6'b0} ) ^
                                      ( {63{b_ff_e2[07]}} & {24'b0,a_ff_e2[31:0], 7'b0} ) ^

逐段解释：

* 第 L280-L315 行：`clmul_raw_e2` 对 `b_ff_e2` 的每个 bit 做条件选择，将
  `a_ff_e2` 左移对应位数后异或到 63 bit 结果中。这是 carry-less multiply 的源码实现。
* 第 L343-L358 行：`grev` 分 1、2、4、8、16 bit 阶段交换位组，每一级受 `b_ff_e2`
  相应位控制。
* 第 L387-L402 行：`gorc` 与 `grev` 类似，但每一级把交换结果与原值 OR。
* 第 L439-L490 行：`shfl` 与 `unshfl` 按 `b_ff_e2[3:0]` 分阶段重新排列 bit。
* 第 L530-L599 行：CRC32/CRC32C 对 byte、halfword、word 形式分别执行 8、16、32 次
  右移和多项式异或。
* 第 L630-L641 行：BFP 从 `b_ff_e2` 取 len/off，形成 shift data、shift mask 后与
  `a_ff_e2` 合成结果。
* 第 L678-L693 行：XPERM_N/B/H 按 nibble、byte、halfword 粒度从 `a_ff_e2` 选择 lane。

接口关系：

* 被调用：`mp_e2` 中 bitmanip 控制位和 `a_ff_e2/b_ff_e2` 驱动本段。
* 调用：不调用子模块；所有排列和 CRC 都是组合表达式或组合循环。
* 共享状态：组合逻辑结果进入 L726 的 E3 寄存器。

§4.6  bitmanip 结果寄存与最终输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：乘法器把 E2 bitmanip 选择和值寄存到 E3。最终输出在普通乘法高/低 32 bit
与 bitmanip 结果之间选择。

关键代码（`rtl/design/exu/eh2_exu_mul_ctl.sv:L702-L733`）：

.. code-block:: systemverilog

      assign bitmanip_sel_e2        =  ap_bcompress_e2 | ap_bdecompress_e2 | ap_clmul_e2 | ap_clmulh_e2 | ap_clmulr_e2 | ap_grev_e2 | ap_gorc_e2 | ap_shfl_e2 | ap_unshfl_e2 | crc32_all_e2 | ap_bfp_e2 | ap_xperm_n_e2 | ap_xperm_b_e2 | ap_xperm_h_e2;

      assign bitmanip_e2[31:0]      = ( {32{ap_bcompress_e2}}   &       bcompress_e2[31:0]   ) |
                                      ( {32{ap_bdecompress_e2}} &       bdecompress_e2[31:0] ) |
                                      ( {32{ap_clmul_e2}}       &       clmul_raw_e2[31:0]   ) |
                                      ( {32{ap_clmulh_e2}}      & {1'b0,clmul_raw_e2[62:32]} ) |
                                      ( {32{ap_clmulr_e2}}      &       clmul_raw_e2[62:31]  ) |
                                      ( {32{ap_grev_e2}}        &       grev_e2[31:0]        ) |
                                      ( {32{ap_gorc_e2}}        &       gorc_e2[31:0]        ) |
                                      ( {32{ap_shfl_e2}}        &       shfl_e2[31:0]        ) |
                                      ( {32{ap_unshfl_e2}}      &       unshfl_e2[31:0]      ) |

逐段解释：

* 第 L702 行：`bitmanip_sel_e2` 是所有乘法器承载 bitmanip 操作的 OR。
* 第 L704-L722 行：`bitmanip_e2` 是 OR 树，按控制位选择 bcompress、bdecompress、
  clmul、grev、gorc、shfl、unshfl、CRC、BFP、XPERM 等结果。
* 第 L726 行：`bitmanip_sel_e2` 和 `bitmanip_e2` 一起寄存到 E3。
* 第 L731-L733 行：如果 E3 没有 bitmanip 结果，`low_e3` 选择 `prod_e3[31:0]`
  或 `prod_e3[63:32]`；若有 bitmanip 结果，则 OR 入 `bitmanip_e3`。

接口关系：

* 被调用：E2 bitmanip 控制和普通乘法流水共同驱动本段。
* 调用：输出 `out` 返回 `eh2_exu.sv` 的 `exu_mul_result_e3`。
* 共享状态：`bitmanip_sel_e3`、`bitmanip_e3`、`low_e3`、`prod_e3` 是 E3 寄存状态。

§5  `eh2_exu_div_ctl.sv` 除法器
-------------------------------

`eh2_exu_div_ctl.sv` 包含一个 wrapper 和多个具体除法器实现。wrapper 根据 `pt.DIV_NEW`
和 `pt.DIV_BIT` 选择实现；具体实现处理 valid、cancel、特殊情况、shortq 和结果符号。

§5.1  wrapper 接口与输出静默
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：wrapper 接收 `eh2_div_pkt_t dp`、`dividend`、`divisor` 和 `cancel`，输出
`finish_dly` 与 `out`。`out` 只有在 `finish_dly` 为 1 时才透出 `out_raw`。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L17-L42`）：

.. code-block:: systemverilog

   module eh2_exu_div_ctl
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   )
     (
      input logic           clk,                       // Top level clock
      input logic           rst_l,                     // Reset
      input logic           scan_mode,                 // Scan mode

      input eh2_div_pkt_t  dp,                        // valid, sign, rem
      input logic  [31:0]   dividend,                  // Numerator
      input logic  [31:0]   divisor,                   // Denominator

      input logic           cancel,                    // Cancel divide


      output logic          finish_dly,                // Finish to match data
      output logic [31:0]   out                        // Result

逐段解释：

* 第 L17-L21 行：wrapper 与其它 EXU 模块一样导入 package 并包含参数。
* 第 L23-L31 行：输入包含时钟、复位、scan、div packet、被除数、除数和 cancel。
* 第 L34-L35 行：`finish_dly` 是结果有效输出，`out` 是 32 bit 除法或余数结果。
* 第 L42 行：`out` 被 `{32{finish_dly}}` 掩码，源码注释说明这是为了在除法迭代时静默结果总线。

接口关系：

* 被调用：`eh2_exu.sv:L400-L406` 实例化 wrapper。
* 调用：wrapper 按参数实例化具体除法器实现。
* 共享状态：wrapper 本身只有 `out_raw` 中间线，不保存时序状态。

§5.2  `pt.DIV_NEW` 与 `pt.DIV_BIT` 实现选择
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：wrapper 用参数选择旧 1 bit cheapshortq 或新 1/2/3/4 bit fullshortq 实现。所有实现
共享同一组端口：`cancel`、`valid_in`、`signed_in`、`rem_in`、`dividend_in`、
`divisor_in`、`valid_out`、`data_out`。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L46-L128`）：

.. code-block:: systemverilog

      if (pt.DIV_NEW == 0)
         begin
           eh2_exu_div_existing_1bit_cheapshortq   i_existing_1bit_div_cheapshortq (
               .clk              ( clk                      ),   // I
               .rst_l            ( rst_l                    ),   // I
               .scan_mode        ( scan_mode                ),   // I
               .cancel           ( cancel                   ),   // I
               .valid_in         ( dp.valid                 ),   // I
               .signed_in        (~dp.unsign                ),   // I
               .rem_in           ( dp.rem                   ),   // I
               .dividend_in      ( dividend[31:0]           ),   // I
               .divisor_in       ( divisor[31:0]            ),   // I
               .valid_out        ( finish_dly               ),   // O
               .data_out         ( out_raw[31:0]            ));  // O
         end

逐段解释：

* 第 L46-L60 行：`pt.DIV_NEW == 0` 时实例化
  `eh2_exu_div_existing_1bit_cheapshortq`。
* 第 L63-L77 行：`pt.DIV_NEW == 1` 且 `pt.DIV_BIT == 1` 时实例化
  `eh2_exu_div_new_1bit_fullshortq`。
* 第 L80-L94、L97-L111、L114-L128 行：`pt.DIV_BIT` 为 2、3、4 时分别实例化
  new 2 bit、3 bit、4 bit fullshortq。
* 所有实例都把 `~dp.unsign` 连接到 `signed_in`，把 `dp.rem` 连接到 `rem_in`，
  把 `valid_out` 连接到 wrapper 的 `finish_dly`。

接口关系：

* 被调用：`eh2_exu_div_ctl` wrapper 根据参数调用一个具体实现。
* 调用：具体实现内部使用 `rvdffe`、`rvtwoscomp`，new fullshortq 还调用
  `eh2_exu_div_cls`。
* 共享状态：参数选择在 elaboration 阶段确定，不是运行期 mux。

§5.3  existing 1 bit cheapshortq 状态寄存
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：旧实现保存 valid、finish、run、count、shortq、符号和 rem 状态，并保存除数、
商/被除数、部分余数。cancel 会屏蔽 valid、finish 和 smallnum 状态。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L202-L240`）：

.. code-block:: systemverilog

      rvdffe #(18) i_misc_ff         (.*, .clk(clk), .en(div_clken), .din ({valid_in & ~cancel,
                                                                            finish   & ~cancel,
                                                                            run_in,
                                                                            count_in[5:0],
                                                                            shortq_enable,
                                                                            shortq_shift[3:0],
                                                                            (valid_in & dividend_in[31]) | (~valid_in & dividend_neg_ff),
                                                                            (valid_in & divisor_in[31] ) | (~valid_in & divisor_neg_ff ),
                                                                            (valid_in & sign_eff       ) | (~valid_in & sign_ff        ),
                                                                            (valid_in & rem_in         ) | (~valid_in & rem_ff         )} ),
                                                                     .dout({valid_ff_x,
                                                                            finish_ff,
                                                                            run_state,
                                                                            count[5:0],

逐段解释：

* 第 L202-L221 行：`i_misc_ff` 保存 valid、finish、run、count、shortq、符号和 rem。
  `valid_in & ~cancel` 与 `finish & ~cancel` 表明 cancel 直接阻断这些状态置位。
* 第 L223-L232 行：small number fast path 的四级标记同样用 `& ~cancel` 写入。
* 第 L234-L236 行：`m_ff` 保存符号扩展除数，`qff` 保存商/被除数移位寄存器，
  `aff` 保存部分余数。
* 第 L238-L240 行：三个 `rvtwoscomp` 分别用于 dividend、quotient 和 remainder
  的二补数修正。

接口关系：

* 被调用：wrapper 在 `pt.DIV_NEW == 0` 时实例化本模块。
* 调用：`rvdffe` 和 `rvtwoscomp`。
* 共享状态：`valid_ff_x`、`finish_ff`、`run_state`、`count`、`q_ff`、`a_ff`、`m_ff`。

§5.4  existing 实现的 smallnum、shortq 与迭代控制
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：旧实现对 4 bit 范围内的小数除法给出 fast path，同时用 shortq 跳过部分迭代。
普通迭代由 `run_state`、`count`、`finish` 和 `cancel` 控制。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L248-L396`）：

.. code-block:: systemverilog

      assign smallnum_case_e1        = ((q_ff[31:4] == 28'b0) & (m_ff[31:4] == 28'b0) & (m_ff[31:0] != 32'b0) & ~rem_ff & valid_x) |
                                       ((q_ff[31:0] == 32'b0) &                         (m_ff[31:0] != 32'b0) & ~rem_ff & valid_x);


      assign smallnum[3]             = ( q_ff[3] &                                  ~m_ff[3] & ~m_ff[2] & ~m_ff[1]           );


      assign smallnum[2]             = ( q_ff[3] &                                  ~m_ff[3] & ~m_ff[2] &            ~m_ff[0]) |
                                       ( q_ff[2] &                                  ~m_ff[3] & ~m_ff[2] & ~m_ff[1]           ) |
                                       ( q_ff[3] &  q_ff[2] &                       ~m_ff[3] & ~m_ff[2]                      );

逐段解释：

* 第 L253-L255 行：smallnum fast path 仅覆盖非 rem、非除 0、被除数和除数高位为 0
  或被除数为 0 的情况。
* 第 L258-L305 行：`smallnum[3:0]` 是由 4 bit 被除数和除数展开的组合方程。
* 第 L313-L378 行：shortq 逻辑根据被除数和除数的高位分类决定跳过 8/16/24/30 bit。
  L375 注释说明 31 会映射到 30，以避免 nonblocking div 的完成早于 E4。
* 第 L385-L394 行：`div_clken`、`run_in`、`count_in`、`finish`、`valid_out`
  共同控制迭代生命周期。`valid_out` 是 `finish_ff & ~cancel`。
* 第 L399-L441 行：`q_in`、`a_in`、`m_eff`、`add`、`rem_correct` 和最终 `data_out`
  实现商/余数迭代和符号修正。

接口关系：

* 被调用：旧除法器状态机内部调用这些组合路径。
* 调用：不调用额外子模块；二补数修正来自上一节的 `rvtwoscomp`。
* 共享状态：`smallnum_ff`、`shortq_shift_ff`、`count`、`q_ff`、`a_ff`。

§5.5  new fullshortq 的公共控制结构
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：new 1/2/3/4 bit fullshortq 实现有共同结构：保存 valid/control/count/special/shortq，
处理 by-zero、smallnum、cancel、running state，并根据每周期位数生成 quotient。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L517-L614`）：

.. code-block:: systemverilog

      rvdffe #(22) i_misc_ff        (.*, .clk(clk), .en(misc_enable),  .din ({valid_ff_in, control_in[2:0], count_in[6:0], special_in[4:1], shortq_enable,    shortq_shift[4:0],    finish   }),
                                                                       .dout({valid_ff,    control_ff[2:0], count_ff[6:0], special_ff[4:1], shortq_enable_ff, shortq_shift_ff[4:0], finish_ff}) );

      rvdffe #(32) i_a_ff           (.*, .clk(clk), .en(a_enable),     .din(a_in[31:0]),    .dout(a_ff[31:0]));
      rvdffe #(33) i_b_ff           (.*, .clk(clk), .en(b_enable),     .din(b_in[32:0]),    .dout(b_ff[32:0]));
      rvdffe #(32) i_r_ff           (.*, .clk(clk), .en(rq_enable),    .din(r_in[31:0]),    .dout(r_ff[31:0]));
      rvdffe #(32) i_q_ff           (.*, .clk(clk), .en(rq_enable),    .din(q_in[31:0]),    .dout(q_ff[31:0]));



      assign special_in[4:1]        = {special_ff[3] & ~cancel,

逐段解释：

* 第 L517-L523 行：new 1 bit 实现保存 valid、control、count、special、shortq、finish
  以及 A/B/R/Q 寄存器。2/3/4 bit 实现有相同类别的寄存器，只是宽度和 quotient
  生成不同。
* 第 L527-L536 行：`special_in`、`valid_ff_in` 和 `control_in` 都显式处理 cancel 或
  valid 输入。`control_in[2:0]` 保存 dividend sign、divisor sign 和 rem 标志。
* 第 L543-L552 行：`by_zero_case`、`misc_enable`、`running_state`、`finish_raw`、
  `finish` 和 `count_enable` 共同控制迭代生命周期。
* 第 L556-L584 行：A/R 路径根据是否 running、shortq、restore 或 adder 选择下一值。
* 第 L587-L614 行：Q 路径处理普通 quotient bit、smallnum、除 0 全 1、二补数修正和
  rem/quotient 输出选择。

接口关系：

* 被调用：wrapper 在 `pt.DIV_NEW == 1` 且对应 `pt.DIV_BIT` 时实例化 new fullshortq。
* 调用：new 实现调用 `rvtwoscomp` 和 `eh2_exu_div_cls`。
* 共享状态：`valid_ff`、`control_ff`、`count_ff`、`special_ff`、`a_ff/b_ff/r_ff/q_ff`。

§5.6  new shortq 与 `eh2_exu_div_cls`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：new fullshortq 使用 `eh2_exu_div_cls` 统计被除数和除数的 leading sign bits，
再计算 shortq 跳步量。`eh2_exu_div_cls` 是同文件末尾的辅助模块。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L674-L705`）：

.. code-block:: systemverilog

      assign shortq_dividend[32:0]   = {dividend_sign_ff,a_ff[31:0]};


      parameter shortq_a_width = 33;
      parameter shortq_b_width = 33;

      logic [5:0]  dw_a_enc;
      logic [5:0]  dw_b_enc;
      logic [6:0]  dw_shortq_raw;


      eh2_exu_div_cls i_a_cls  (
          .operand  ( shortq_dividend[32:0]  ),
          .cls      ( dw_a_enc[4:0]          ));

      eh2_exu_div_cls i_b_cls  (
          .operand  ( b_ff[32:0]             ),

逐段解释：

* 第 L674 行：shortq 的 dividend 输入把符号位和 `a_ff[31:0]` 拼成 33 bit。
* 第 L685-L691 行：两个 `eh2_exu_div_cls` 实例分别计算 dividend 和 divisor 的
  leading sign-bit 分类。
* 第 L697-L703 行：`dw_shortq_raw` 由除数分类减去被除数分类再加 1；负数或 0 映射为
  最小 1；`shortq_shift` 由 `5'b11111 - shortq[4:0]` 得到。
* 第 L701 行：`shortq_enable` 还要求 shortq 不为负、不是过大跳步，并且没有 cancel。

接口关系：

* 被调用：new 1/2/3/4 bit fullshortq 均调用 `eh2_exu_div_cls`。
* 调用：`eh2_exu_div_cls` 不再调用其它模块，只是组合分类器。
* 共享状态：`shortq_shift_ff` 在 fullshortq 主状态寄存器中保存。

§5.7  `eh2_exu_div_cls` leading sign-bit 分类器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_exu_div_cls` 接收 33 bit operand，根据 operand[32] 选择 leading ones
或 leading zeros 分类结果。源码注释说明输出是忽略 `[32]` 的 "n" format。

关键代码（`rtl/design/exu/eh2_exu_div_ctl.sv:L1749-L1832`）：

.. code-block:: systemverilog

   module eh2_exu_div_cls
     (
      input  logic [32:0] operand,

      output logic [4:0]  cls                  // Count leading sign bits - "n" format ignoring [32]
      );


      logic [4:0]   cls_zeros;
      logic [4:0]   cls_ones;


   assign cls_zeros[4:0]             = ({5{operand[31]    ==  {           1'b1} }} & 5'd00) |
                                       ({5{operand[31:30] ==  {{ 1{1'b0}},1'b1} }} & 5'd01) |
                                       ({5{operand[31:29] ==  {{ 2{1'b0}},1'b1} }} & 5'd02) |

逐段解释：

* 第 L1749-L1754 行：模块只有 `operand` 和 `cls` 两个端口。`cls` 注释明确是 counting
  leading sign bits。
* 第 L1761-L1793 行：`cls_zeros` 匹配从高位开始的 0 串直到第一个 1。全 0 被标为
  don't care case，因为特殊情况在主除法器处理。
* 第 L1796-L1827 行：`cls_ones` 匹配从高位开始的 1 串直到第一个 0。全 1 返回 31。
* 第 L1830 行：`operand[32]` 为 1 时选择 `cls_ones`，否则选择 `cls_zeros`。

接口关系：

* 被调用：new fullshortq 实现的 `i_a_cls` 和 `i_b_cls` 实例调用本模块。
* 调用：无下层模块。
* 共享状态：纯组合模块，不写寄存器。

§6  关键时序关系
----------------

本节只画源码中能直接看到的寄存和实例连接。图中 E1/E2/E3/E4 的命名来自信号名和
寄存器命名；不额外推导未在 EXU 源码出现的流水阶段。

§6.1  ALU E1 与 E4 复用同一控制器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

::

   D-stage operands/control
      |
      | i0_alu_e1 / i1_alu_e1
      v
   E1 result, upper flush, predict_p_e1
      |
      | predict packet / predpipe / ap / secondary operands registers
      v
   E4 i0_alu_e4 / i1_alu_e4
      |
      v
   E4 result, lower flush, branch update metadata

说明：

* E1 ALU 直接接 D-stage 操作数和 `i*_ap_e1`，输出 `exu_i*_result_e1`。
* E4 ALU 接 E3 final 操作数和 `i*_ap_e4`，输出 `exu_i*_result_e4`。
* 两级 ALU 都是 `eh2_exu_alu_ctl` 实例，区别来自顶层端口连接。

§6.2  乘法器 E1/E2/E3
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

::

   D-stage mul_rs1_d/mul_rs2_d + mul_p
      |
      v
   E1: mp_e1, a_ff_e1, b_ff_e1
      |   optional lsu_result_dc3 bypass
      v
   E2: mp_e2, signed 33-bit operands, prod_e2, bitmanip_e2
      |
      v
   E3: prod_e3, low_e3, bitmanip_e3
      |
      v
   exu_mul_result_e3

说明：

* `mul_c1_e1_clken` 由 `mp.valid | clk_override` 打开。
* `mul_c1_e2_clken` 和 `mul_c1_e3_clken` 分别由上一段 valid 打开。
* 普通乘法和乘法器内 bitmanip 最终在 `out[31:0]` 汇合。

§6.3  除法 wrapper 与具体实现
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

::

   div_p, div_rs1_d, div_rs2_d, dec_div_cancel
      |
      v
   eh2_exu_div_ctl
      |
      | pt.DIV_NEW / pt.DIV_BIT selects one implementation
      v
   existing_1bit_cheapshortq or new_Nbit_fullshortq
      |
      v
   finish_dly -> exu_div_wren
   out        -> exu_div_result, masked by finish_dly

说明：

* wrapper 的 `out` 在 `finish_dly` 为 0 时被强制为 0。
* 所有具体实现都把 `valid_out` 接回 `finish_dly`。
* cancel 在 wrapper 和具体实现端口中保持同名连接。

§7  与相邻章节的阅读顺序
------------------------

阅读 EXU 时建议按以下顺序交叉查阅：

* 先读 :doc:`dec`，确认 `i0_ap`、`i1_ap`、`mul_p`、`div_p` 和 bypass 控制来自 DEC。
* 再读本章 §2，确认 EXU 顶层如何把 DEC 输出分发到 ALU、mul、div 和 LSU。
* 再读 :doc:`lsu`，确认 `exu_lsu_rs1_d`、`exu_lsu_rs2_d` 与 load result bypass
  在 LSU/EXU 之间的连接位置。
* 最后回到本章 §3-§5，按 ALU、mul、div 子模块分别定位具体运算逻辑。

§8  EXU 常见失败模式与排查
--------------------------

EXU 失败通常不会只表现为“ALU 算错”。同一条 branch 或 DIV 指令可能同时影响
flush、predict packet、GPR writeback、LSU bypass 和 cosim trace。定位时先看
``eh2_exu.sv`` 的边界信号，再下钻到 ``eh2_exu_alu_ctl.sv``、``eh2_exu_mul_ctl.sv``
或 ``eh2_exu_div_ctl.sv``。

.. list-table:: EXU 失败模式
   :header-rows: 1
   :widths: 24 32 28 16

   * - 现象
     - 可能根因
     - 排查命令
     - 阅读入口
   * - cosim 报 PC mismatch，且 branch 指令附近失败
     - E1 upper flush、E4 lower flush 或 ``exu_flush_path_final`` 选择错误
     - ``rg -n "flush_path|exu_flush_final|predict_p" /home/host/Cores-VeeR-EH2/design/exu``
     - 本章 §6.1 与 :ref:`appendix_a_rtl/ifu`
   * - DIV 指令写回晚到或被多写一次
     - ``dec_div_cancel``、``finish_dly``、``exu_div_wren`` 时序关系错误
     - ``rg -n "dec_div_cancel|finish_dly|exu_div_wren" /home/host/Cores-VeeR-EH2/design/exu``
     - 本章 §5.1-§5.5
   * - MUL 后接 load-use 场景结果错误
     - ``load_mul_rs*_bypass_e1`` 与 ``lsu_result_dc3`` bypass 未按 packet 生效
     - ``rg -n "load_mul_rs|lsu_result_dc3|mp_e1" /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_mul_ctl.sv``
     - 本章 §4.2
   * - bitmanip 指令只在某些操作数失败
     - ALU packet 的 bitmanip 控制位或 ``eh2_exu_alu_ctl`` operand mux 错位
     - ``rg -n "bitmanip|grev|gor|shfl|cpop" /home/host/Cores-VeeR-EH2/design/exu``
     - 本章 §3 与 :ref:`appendix_a_rtl/dec`
   * - branch predictor update 覆盖率低
     - ``fp_enable`` 或 ``final_predict_mp`` 未被目标 directed/riscv-dv 场景触发
     - ``rg -n "fp_enable|final_predict_mp|exu_mp_pkt" /home/host/Cores-VeeR-EH2/design/exu/eh2_exu.sv``
     - 本章 §6.1 与 :ref:`coverage_plan`
   * - LEC 只在 EXU 子块失败
     - 子块 DDC 与 RTL 文件映射错，或把 ``eh2_exu`` 顶层与 ALU/MUL/DIV 子块混淆
     - ``sed -n '1,20p' syn/build/lec_summary.txt``
     - :ref:`lec_flow` 与 :ref:`adr-0020`

§9  参考资料
------------

* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/exu/eh2_exu.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/exu/eh2_exu_alu_ctl.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/exu/eh2_exu_mul_ctl.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/exu/eh2_exu_div_ctl.sv`
* 顶层实例绝对路径：:file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* filelist 绝对路径：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* 控制包定义绝对路径：:file:`/home/host/eh2-veri/rtl/design/include/eh2_def.sv`
* 关联章节：:doc:`dec`
* 关联章节：:doc:`lsu`
