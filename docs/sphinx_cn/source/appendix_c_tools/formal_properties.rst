.. _appendix_c_tools_formal_properties:
.. _appendix_c_tools/formal_properties:

形式验证属性（SVA）- 详细参考
=============================

:status: draft
:source: dv/formal/properties/
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  文件边界与统计
------------------

本章描述 ``dv/formal/properties/`` 下的 SVA property 模块，以及与这些 property
直接相关的 bind、top-level SVA、Sail bridge 和 trace checker。IFV 的 Makefile、
TCL 证明脚本和 filelist 编译细节见 :doc:`formal_infra`，本章只在接口关系中引用。

当前源码中有 7 个 property 文件：

* ``eh2_dbg_assert.sv``：5 条 ``assert property``，1 条 ``cover property``。
* ``eh2_dec_assert.sv``：5 条 ``assert property``，1 条 ``cover property``。
* ``eh2_exu_assert.sv``：6 条 ``assert property``，3 条 ``cover property``。
* ``eh2_ifu_assert.sv``：7 条 ``assert property``，3 条 ``cover property``。
* ``eh2_lsu_assert.sv``：6 条 ``assert property``，3 条 ``cover property``。
* ``eh2_pic_assert.sv``：5 条 ``assert property``，1 条 ``cover property``。
* ``eh2_pmp_assert.sv``：7 条 ``assert property``，1 条 ``cover property``。

合计为 41 条 assertion 和 14 条 cover property。这个统计来自源码中的
``assert property`` 与 ``cover property`` 语句计数，不包含 ``sail_bridge.sv`` 和
``eh2_veer_sva.sv`` 中的额外顶层断言。

§1.1  Property 文件清单
~~~~~~~~~~~~~~~~~~~~~~~

职责：确认 property 文件的实际数量和行数，避免沿用旧 README 中的过期 4 文件描述。

关键代码（``dv/formal/properties`` 文件清单）：

.. code-block:: bash

   dv/formal/properties/eh2_dbg_assert.sv   # 162 lines
   dv/formal/properties/eh2_dec_assert.sv   # 172 lines
   dv/formal/properties/eh2_exu_assert.sv   # 131 lines
   dv/formal/properties/eh2_ifu_assert.sv   # 153 lines
   dv/formal/properties/eh2_lsu_assert.sv   # 136 lines
   dv/formal/properties/eh2_pic_assert.sv   # 150 lines
   dv/formal/properties/eh2_pmp_assert.sv   # 154 lines

逐段解释：

* 文件清单来自 ``wc -l dv/formal/properties/*.sv``。所有 property 文件都是 SystemVerilog 源文件，模块名与文件名一一对应。
* 这些文件不直接实例化 DUT；它们定义 checker 模块，由 bind 文件或 formal top-level 集成到 IFV/SBY 环境。

接口关系：

* 被调用：``eh2_formal_bind.sv`` 尝试把若干 property 模块 bind 到对应 RTL 模块；``sby_*.sby`` 也直接读取部分 property 文件。
* 调用：property 模块内部使用 SVA ``assert property`` 与 ``cover property``。
* 共享状态：property 端口必须与被验证 RTL 内部信号或顶层端口匹配。

§1.2  编译 filelist 中的 SVA 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 IFV filelist 如何把顶层 SVA 绑定到 ``eh2_veer``。

关键代码（``dv/formal/ifv_filelist.f:L1-L16``）：

.. code-block:: systemverilog

   // IFV Filelist — EH2 Core + Formal Properties
   // RC5 (2026-05-09): Fixed bootstrap + formal_top for IFV 15.20 compatibility.
   // eh2_param.vh moved inside modules (was at file scope, causing SVNOTY).

   +define+FORMAL
   +define+RV_BUILD_AXI4
   +incdir+/home/host/Cores-VeeR-EH2/snapshots/default
   +incdir+/home/host/Cores-VeeR-EH2/design/include
   +incdir+/home/host/Cores-VeeR-EH2/design/lib
   +incdir+/home/host/eh2-veri/dv/formal/properties
   +incdir+/home/host/eh2-veri/dv/formal

   // Bootstrap: macro and type-definition files for $unit scope
   /home/host/eh2-veri/dv/formal/ifv_bootstrap.sv

逐段解释：

* 第 L1-L3 行：filelist 注释记录 RC5 修正点：``eh2_param.vh`` 不再放在 file scope。
* 第 L5-L11 行：定义 ``FORMAL`` 与 ``RV_BUILD_AXI4``，并加入 snapshot、design include/lib、formal properties 和 formal 目录。
* 第 L13-L14 行：``ifv_bootstrap.sv`` 先编译，为宏和 ``eh2_pdef.vh`` 类型定义提供 $unit scope 入口。

关键代码（``dv/formal/ifv_filelist.f:L63-L66``）：

.. code-block:: systemverilog

   /home/host/Cores-VeeR-EH2/design/eh2_veer.sv

   // SVA bind module: binds to eh2_veer using .* auto-connect (no manual port mapping)
   /home/host/eh2-veri/dv/formal/eh2_veer_sva.sv

逐段解释：

* 第 L63 行：filelist 编译顶层 ``eh2_veer.sv``。
* 第 L65-L66 行：实际纳入 IFV 的 SVA bind module 是 ``eh2_veer_sva.sv``，注释说明它使用 ``.*`` auto-connect 绑定到 ``eh2_veer``。

接口关系：

* 被调用：``dv/formal/Makefile`` 的 ``ifv`` target 使用 ``ifv -f ifv_filelist.f``。
* 调用：filelist 不执行逻辑，只声明 IFV 编译输入。
* 共享状态：``FORMAL`` 宏控制 property 文件中 ``ifdef FORMAL`` 包裹的断言是否启用。

§2  Debug property：``eh2_dbg_assert.sv``
-----------------------------------------

``eh2_dbg_assert`` 检查 debug FSM、halt/resume 互斥、abstract command 完成和
``dmactive`` 关闭行为。源码注释称 "Properties (6 total)"，但实际实现为 5 条
assertion 加 1 条 cover。

§2.1  端口与 FSM 编码
~~~~~~~~~~~~~~~~~~~~~

职责：声明 checker 需要观测的 debug FSM、halt/resume、DM register、abstract command 和 DMI 信号。

关键代码（``dv/formal/properties/eh2_dbg_assert.sv:L19-L56``）：

.. code-block:: systemverilog

   module eh2_dbg_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- Debug FSM state (per-thread) ---
     input logic [pt.NUM_THREADS-1:0][3:0]  dbg_state,
     input logic [pt.NUM_THREADS-1:0]        dbg_state_en,

     // --- Halt/Resume handshake ---
     input logic [pt.NUM_THREADS-1:0]        dbg_halt_req,
     input logic [pt.NUM_THREADS-1:0]        dbg_resume_req,
     input logic [pt.NUM_THREADS-1:0]        dec_tlu_debug_mode,
     input logic [pt.NUM_THREADS-1:0]        dec_tlu_dbg_halted,
     input logic [pt.NUM_THREADS-1:0]        dec_tlu_resume_ack,

     // --- DM control/status ---
     input logic [31:0]                      dmcontrol_reg,

逐段解释：

* 第 L19-L23 行：checker 是一个带 ``eh2_param.vh`` 参数块的模块，并 import ``eh2_pkg``。
* 第 L24-L36 行：输入包含 clock/reset、per-thread ``dbg_state``、``dbg_state_en``、halt/resume 请求和 TLU debug status。
* 第 L39-L55 行：checker 继续接收 ``dmcontrol_reg``、``dmstatus_reg``、``abstractcs_reg``、abstract command 相关信号和 DMI 地址/数据/写使能。

关键代码（``dv/formal/properties/eh2_dbg_assert.sv:L58-L72``）：

.. code-block:: systemverilog

     // FSM state encoding (from eh2_dbg.sv)
     localparam logic [3:0] FSM_IDLE           = 4'h0;
     localparam logic [3:0] FSM_HALTING        = 4'h1;
     localparam logic [3:0] FSM_HALTED         = 4'h2;
     localparam logic [3:0] FSM_CORE_CMD_START = 4'h3;
     localparam logic [3:0] FSM_CORE_CMD_WAIT  = 4'h4;
     localparam logic [3:0] FSM_SB_CMD_START   = 4'h5;
     localparam logic [3:0] FSM_SB_CMD_SEND    = 4'h6;
     localparam logic [3:0] FSM_SB_CMD_RESP    = 4'h7;
     localparam logic [3:0] FSM_CMD_DONE       = 4'h8;
     localparam logic [3:0] FSM_RESUMING       = 4'h9;

     // pick thread 0 for single-thread config
     wire [3:0] fsm = dbg_state[0];

逐段解释：

* 第 L58-L68 行：checker 本地复制 ``eh2_dbg.sv`` 的 FSM 编码，用符号名表示 4 bit 状态值。
* 第 L70-L72 行：当前 property 只取 ``dbg_state[0]`` 作为 ``fsm``，后续断言都围绕 thread 0。

接口关系：

* 被调用：bind 或 SBY 环境将 RTL 内部 debug 信号接入该 checker。
* 调用：checker 使用 SVA property。
* 共享状态：``dbg_state``、``dbg_halt_req``、``dbg_resume_req`` 和 ``dmcontrol_reg`` 是该模块的核心观测状态。

§2.2  Halt/Resume 与 command 完成断言
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 5 条 debug assertion 和一个 halt-resume roundtrip cover。

关键代码（``dv/formal/properties/eh2_dbg_assert.sv:L81-L112``）：

.. code-block:: systemverilog

     property p_halt_req_enters_halt_fsm;
       @(posedge clk) disable iff (~rst_l)
         (dbg_halt_req[0])
           |=>
         (fsm == FSM_HALTING);
     endproperty
     a_halt_req_enters_halt_fsm: assert property (p_halt_req_enters_halt_fsm)
       else $error("FORMAL FAIL: halt_req did not enter HALTING");

     property p_resume_from_halted;
       @(posedge clk) disable iff (~rst_l)
         ((fsm == FSM_HALTED) && dbg_resume_req[0] && dec_tlu_dbg_halted[0])
           |=>
         (fsm == FSM_RESUMING);
     endproperty
     a_resume_from_halted: assert property (p_resume_from_halted)
       else $error("FORMAL FAIL: resume from HALTED did not enter RESUMING");

     property p_halt_resume_onehot;
       @(posedge clk) disable iff (~rst_l)
         !(dbg_halt_req[0] && dbg_resume_req[0]);

逐段解释：

* 第 L81-L88 行：``a_halt_req_enters_halt_fsm`` 要求 thread 0 的 ``dbg_halt_req`` 在下一拍进入 ``FSM_HALTING``。
* 第 L93-L100 行：``a_resume_from_halted`` 要求 ``HALTED`` 且 resume request 且 TLU halted 时下一拍进入 ``FSM_RESUMING``。
* 第 L107-L112 行：``a_halt_resume_onehot`` 禁止 ``dbg_halt_req[0]`` 和 ``dbg_resume_req[0]`` 同时为 1。

关键代码（``dv/formal/properties/eh2_dbg_assert.sv:L121-L157``）：

.. code-block:: systemverilog

     property p_cmd_done_clears_busy;
       @(posedge clk) disable iff (~rst_l)
         ($rose(fsm == FSM_CMD_DONE) && dbg_state_en[0])
           |=>
         (fsm == FSM_HALTED);
     endproperty
     a_cmd_done_clears_busy: assert property (p_cmd_done_clears_busy)
       else $error("FORMAL FAIL: cmd_done did not return to HALTED");

     property p_dmactive_off_holds_idle;
       @(posedge clk) disable iff (~rst_l)
         (!dmcontrol_reg[0])
           |=>
         (fsm == FSM_IDLE);
     endproperty
     a_dmactive_off_holds_idle: assert property (p_dmactive_off_holds_idle)
       else $error("FORMAL FAIL: dmactive=0 but FSM not IDLE");

     c_halt_resume_roundtrip: cover property (
       @(posedge clk) disable iff (~rst_l)
         (fsm == FSM_IDLE)

逐段解释：

* 第 L121-L128 行：``a_cmd_done_clears_busy`` 实际检查 ``FSM_CMD_DONE`` 上升且状态使能后，下一拍回到 ``FSM_HALTED``；名字中的 busy 语义通过状态流间接体现。
* 第 L136-L143 行：``a_dmactive_off_holds_idle`` 要求 ``dmcontrol_reg[0]`` 为 0 时下一拍 FSM 为 ``FSM_IDLE``。
* 第 L148-L157 行：cover 描述 IDLE、halt request、HALTING、HALTED、resume request、RESUMING、IDLE 的可达序列。

接口关系：

* 被调用：``sby_dbg.sby`` 读取该 property 文件；bind 文件也包含 debug bind 段。
* 调用：SVA temporal implication、``$rose`` 和 cover sequence。
* 共享状态：所有断言只检查 thread 0，不覆盖 ``pt.NUM_THREADS`` 中其它 thread 的状态。

§3  Decode property：``eh2_dec_assert.sv``
------------------------------------------

``eh2_dec_assert`` 检查 MRET decode、EBREAK debug valid、CSR legal、flush kill writeback
和 dual-issue rd exclusion。

§3.1  Decode checker 端口与指令解码辅助信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 DEC checker 输入，并从指令 bit 切片生成 MRET、EBREAK 和 CSR 判断。

关键代码（``dv/formal/properties/eh2_dec_assert.sv:L19-L67``）：

.. code-block:: systemverilog

   module eh2_dec_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- Decode control signals ---
     input logic                          dec_i0_decode_d,
     input logic                          dec_i1_decode_d,
     input logic [31:0]                   dec_i0_instr_d,
     input logic [31:0]                   dec_i1_instr_d,

     // --- Writeback signals ---
     input logic [4:0]                    dec_i0_waddr_wb,
     input logic                          dec_i0_wen_wb,
     input logic [4:0]                    dec_i1_waddr_wb,
     input logic                          dec_i1_wen_wb,

逐段解释：

* 第 L19-L23 行：模块导入 ``eh2_pkg`` 并在参数块内 include ``eh2_param.vh``。
* 第 L24-L37 行：checker 输入 clock/reset、i0/i1 decode valid、instruction 和 writeback destination/write enable。
* 第 L39-L66 行：输入还包括 CSR、flush/exception、debug/halt、illegal instruction 和 tid 信号。

关键代码（``dv/formal/properties/eh2_dec_assert.sv:L69-L80``）：

.. code-block:: systemverilog

     // Instruction encoding extracts
     wire [6:0]  i0_opcode = dec_i0_instr_d[6:0];
     wire [6:0]  i1_opcode = dec_i1_instr_d[6:0];
     wire [2:0]  i0_funct3 = dec_i0_instr_d[14:12];
     wire        i0_is_mret = (i0_opcode == 7'b1110011) && (i0_funct3 == 3'b000) &&
                              (dec_i0_instr_d[31:20] == 12'b001100000010);
     wire        i0_is_ebreak = (i0_opcode == 7'b1110011) && (i0_funct3 == 3'b000) &&
                                (dec_i0_instr_d[31:20] == 12'b000000000001);
     wire [11:0] i0_csr_addr = dec_i0_instr_d[31:20];
     wire        i0_is_csr = (i0_opcode == 7'b1110011) &&
                             (i0_funct3 inside {3'b001, 3'b010, 3'b011, 3'b101, 3'b110, 3'b111});

逐段解释：

* 第 L70-L72 行：checker 从 instruction 中切出 opcode 和 funct3。``i1_opcode`` 被定义但在后续 property 中未使用。
* 第 L73-L76 行：``i0_is_mret`` 与 ``i0_is_ebreak`` 都要求 opcode 为 ``7'b1110011``、funct3 为 ``3'b000``，并分别匹配 ``instr[31:20]``。
* 第 L77-L80 行：``i0_csr_addr`` 取 ``instr[31:20]``；``i0_is_csr`` 使用 SYSTEM opcode 和 CSR funct3 集合判断。

接口关系：

* 被调用：DEC bind 或 SBY 环境把 DEC 内部信号接入该 checker。
* 调用：checker 使用 SystemVerilog ``inside`` 和 SVA。
* 共享状态：property 仅基于 i0 指令编码做 MRET/EBREAK/CSR 判断。

§3.2  Decode assertion 组
~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实现 5 条 decode assertion 和一条 MRET reachability cover。

关键代码（``dv/formal/properties/eh2_dec_assert.sv:L93-L130``）：

.. code-block:: systemverilog

     property p_mret_decode_legal;
       @(posedge clk) disable iff (~rst_l)
         (dec_i0_decode_d && i0_is_mret)
           |-> dec_i0_csr_legal_d;
     endproperty
     a_mret_decode_legal: assert property (p_mret_decode_legal)
       else $error("FORMAL FAIL: MRET decoded as illegal");

     property p_ebreak_triggers_debug;
       @(posedge clk) disable iff (~rst_l)
         (dec_i0_decode_d && i0_is_ebreak && !dec_tlu_debug_mode[dec_i0_tid_d])
           |-> dec_i0_debug_valid_d;
     endproperty
     a_ebreak_triggers_debug: assert property (p_ebreak_triggers_debug)
       else $error("FORMAL FAIL: ebreak did not trigger debug valid");

     property p_csr_legal_write_consistency;
       @(posedge clk) disable iff (~rst_l)
         (dec_i0_decode_d && i0_is_csr && (i0_funct3 != 3'b000))
           |-> dec_i0_csr_legal_d;

逐段解释：

* 第 L93-L99 行：MRET decode 时要求 ``dec_i0_csr_legal_d`` 为 1。
* 第 L108-L114 行：EBREAK 且当前 tid 不在 debug mode 时要求 ``dec_i0_debug_valid_d`` 为 1。
* 第 L124-L130 行：CSR 指令且 funct3 非 0 时要求 CSR legal。

关键代码（``dv/formal/properties/eh2_dec_assert.sv:L138-L167``）：

.. code-block:: systemverilog

     property p_flush_kills_writeback;
       @(posedge clk) disable iff (~rst_l)
         (exu_flush_final != '0)
           |-> (dec_tlu_i0_kill_writeb_wb && dec_tlu_i1_kill_writeb_wb);
     endproperty
     a_flush_kills_writeback: assert property (p_flush_kills_writeback)
       else $error("FORMAL FAIL: flush did not kill writeback");

     property p_dual_issue_rd_exclusion;
       @(posedge clk) disable iff (~rst_l)
         (dec_i0_wen_wb && dec_i1_wen_wb)
           |-> (dec_i0_waddr_wb != dec_i1_waddr_wb) || (dec_i0_waddr_wb == 5'd0);
     endproperty
     a_dual_issue_rd_exclusion: assert property (p_dual_issue_rd_exclusion)
       else $error("FORMAL FAIL: dual-issue wrote same rd");

     c_decode_mret: cover property (
       @(posedge clk) disable iff (~rst_l)
         (dec_i0_decode_d && i0_is_mret)
     );

逐段解释：

* 第 L138-L144 行：任一 bit 的 ``exu_flush_final`` 非 0 时，要求 i0/i1 writeback kill 都为 1。
* 第 L153-L159 行：i0 和 i1 同时写回时，要求目的寄存器不同，或者 i0 目的寄存器是 x0。
* 第 L164-L167 行：cover 只要求 MRET decode 条件可达。

接口关系：

* 被调用：``sby_dec.sby`` 读取该 property 文件。
* 调用：SVA implication 和 cover property。
* 共享状态：``dec_i0_tid_d`` 作为索引读取 ``dec_tlu_debug_mode``，因此 property 依赖 tid 与 debug mode 数组一致。

§4  EXU / IFU / LSU property
----------------------------

EXU、IFU 和 LSU property 文件是面向单模块接口的局部约束。它们都采用单一 checker 模块，端口名直接表达被验证的 micro-signal。

§4.1  ``eh2_exu_assert.sv`` - ALU/MUL/DIV
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 MUL one-cycle valid、DIV overlap、ALU result valid、BEQ compare、DIV bounded completion 和 div-by-zero completion。

关键代码（``dv/formal/properties/eh2_exu_assert.sv:L15-L48``）：

.. code-block:: systemverilog

   module eh2_exu_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- ALU signals ---
     input logic        alu_valid_i,
     input logic [31:0] alu_operand_a,
     input logic [31:0] alu_operand_b,
     input logic [3:0]  alu_op,
     input logic [31:0] alu_result,
     input logic        alu_result_valid,

     // --- MUL signals ---
     input logic        mul_valid_i,
     input logic [31:0] mul_operand_a,
     input logic [31:0] mul_operand_b,
     input logic [31:0] mul_result,
     input logic        mul_result_valid,
     input logic        mul_busy,

逐段解释：

* 第 L15-L21 行：checker 带 ``eh2_param.vh`` 参数块和 clock/reset。
* 第 L24-L29 行：ALU 输入包含 valid、两个 operand、4 bit opcode、result 和 result valid。
* 第 L32-L47 行：MUL/DIV 输入分别包含 valid、operand/result/busy，以及 DIV quotient/remainder/result_valid/done。

关键代码（``dv/formal/properties/eh2_exu_assert.sv:L53-L114``）：

.. code-block:: systemverilog

   property p_mul_result_one_cycle;
     @(posedge clk) disable iff (!rst_l)
     (mul_valid_i)
     |=>
     (mul_result_valid);
   endproperty
   a_mul_result_one_cycle: assert property(p_mul_result_one_cycle);

   property p_div_no_overlap;
     @(posedge clk) disable iff (!rst_l)
     (div_busy)
     |->
     (!div_valid_i);
   endproperty
   a_div_no_overlap: assert property(p_div_no_overlap);

   property p_alu_result_valid;
     @(posedge clk) disable iff (!rst_l)
     (alu_valid_i)

逐段解释：

* 第 L53-L59 行：``a_mul_result_one_cycle`` 要求 ``mul_valid_i`` 后下一拍 ``mul_result_valid``。
* 第 L64-L70 行：``a_div_no_overlap`` 要求 DIV busy 时不能再接受 ``div_valid_i``。
* 第 L75-L81 行：ALU valid 后下一拍 result valid。后续同文件还检查 BEQ subtraction result、DIV 1 到 64 拍完成和 div-by-zero 不挂起。

接口关系：

* 被调用：bind 文件包含 EXU bind 段；若端口匹配，IFV 可将其接入 ``eh2_exu``。
* 调用：SVA bounded delay ``##[1:64]``。
* 共享状态：DIV 断言使用 ``div_busy``、``div_valid_i``、``div_done`` 和 ``div_divisor``。

§4.2  ``eh2_ifu_assert.sv`` - Fetch/BTB/ICache/RAS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 fetch PC 对齐、BTB taken 后 branch decode、ICache hit 地址匹配、GHR 更新、RAS push 与 bypass data。

关键代码（``dv/formal/properties/eh2_ifu_assert.sv:L16-L57``）：

.. code-block:: systemverilog

   module eh2_ifu_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- IFU control signals ---
     input logic [31:0] ifu_fetch_pc_f,
     input logic        ifu_fetch_req_f,
     input logic        ifu_fetch_ack_f,

     // --- BTB signals ---
     input logic        btb_hit_f,
     input logic        btb_taken_f,
     input logic [31:0] btb_target_pc_f,

     // --- BHT/GHR signals ---

逐段解释：

* 第 L16-L27 行：IFU checker 观测 fetch PC、fetch request 和 fetch ack。
* 第 L30-L42 行：BTB、BHT/GHR 和 RAS 输入分别覆盖 taken、target PC、GHR 更新、push/pop/call/ret。
* 第 L44-L56 行：ICache 输入包含 hit、tag/request address、bypass flag、bypass data、fetch data，并接收 DEC branch feedback。

关键代码（``dv/formal/properties/eh2_ifu_assert.sv:L62-L90``）：

.. code-block:: systemverilog

   property p_btb_taken_implies_branch;
     @(posedge clk) disable iff (!rst_l)
     (btb_hit_f && btb_taken_f)
     |=>
     (dec_i0_branch_d || dec_i1_branch_d);
   endproperty
   a_btb_taken_implies_branch: assert property(p_btb_taken_implies_branch);

   property p_ic_hit_addr_match;
     @(posedge clk) disable iff (!rst_l)
     (ic_hit_f)
     |->
     (ic_tag_addr_f == ic_req_addr_f);
   endproperty
   a_ic_hit_addr_match: assert property(p_ic_hit_addr_match);

   property p_fetch_pc_aligned;
     @(posedge clk) disable iff (!rst_l)
     (ifu_fetch_req_f)

逐段解释：

* 第 L62-L68 行：BTB hit 且 taken 后下一拍要求 DEC i0 或 i1 branch decode 为 1。
* 第 L73-L79 行：ICache hit 时 tag address 必须等于 request address。
* 第 L84-L90 行：fetch request 时要求 fetch PC bit 0 为 0，即 2-byte aligned。

接口关系：

* 被调用：bind 文件包含 IFU bind 段；SBY 当前没有独立 IFU sby 文件。
* 调用：SVA implication 和 bounded fetch ack property。
* 共享状态：IFU property 将 fetch stage 信号与 decode branch feedback 联系起来。

§4.3  ``eh2_lsu_assert.sv`` - Bus、store buffer、DCCM 与 AMO
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 LSU bus handshake、store buffer overflow、alignment、DCCM read stability、AMO write data 和 bus error exception。

关键代码（``dv/formal/properties/eh2_lsu_assert.sv:L15-L52``）：

.. code-block:: systemverilog

   module eh2_lsu_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- LSU bus signals ---
     input logic        lsu_bus_valid,
     input logic        lsu_bus_ready,
     input logic [31:0] lsu_bus_addr,
     input logic [31:0] lsu_bus_wdata,
     input logic [31:0] lsu_bus_rdata,
     input logic        lsu_bus_write,
     input logic [1:0]  lsu_bus_size,    // 00=byte, 01=half, 10=word
     input logic        lsu_bus_error,

     // --- Store buffer signals ---

逐段解释：

* 第 L15-L31 行：checker 输入 clock/reset 和 LSU bus valid/ready/address/data/write/size/error。
* 第 L34-L51 行：其余输入覆盖 store buffer count/full/push/pop、DCCM read valid/data、AMO active/read/write/complete 和 exception/cause。

关键代码（``dv/formal/properties/eh2_lsu_assert.sv:L57-L86``）：

.. code-block:: systemverilog

   property p_bus_handshake_complete;
     @(posedge clk) disable iff (!rst_l)
     (lsu_bus_valid && lsu_bus_ready)
     |->
     (lsu_bus_valid && lsu_bus_ready);  // handshake is single-cycle
   endproperty
   a_bus_handshake_complete: assert property(p_bus_handshake_complete);

   property p_store_buf_no_overflow;
     @(posedge clk) disable iff (!rst_l)
     (1'b1)
     |->
     (!stbuf_full || stbuf_pop);
   endproperty
   a_store_buf_no_overflow: assert property(p_store_buf_no_overflow);

   property p_addr_align_legal;
     @(posedge clk) disable iff (!rst_l)
     (lsu_bus_valid)

逐段解释：

* 第 L57-L63 行：``a_bus_handshake_complete`` 当前是同周期 tautological handshake 检查，表达 valid 和 ready 同时成立时 handshake 条件成立。
* 第 L68-L74 行：store buffer full 时要求同周期 pop，否则认为 overflow 风险。
* 第 L79-L86 行：alignment property 在 bus valid 时约束 word/half address 低位。

接口关系：

* 被调用：bind 文件包含 LSU bind 段；当前 SBY 独立 PMP 用 ``eh2_pmp_assert``，没有独立 LSU sby 文件。
* 调用：SVA implication、``$stable`` 和 cover property。
* 共享状态：alignment property 依赖 ``lsu_bus_size`` 编码注释：00 byte、01 half、10 word。

§5  PIC 与 PMP property
-----------------------

PIC 与 PMP property 文件覆盖中断仲裁和 LSU address-check/PMP 保护。

§5.1  ``eh2_pic_assert.sv`` - 中断优先级与 claim
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 pending claim id、threshold gating、max priority wakeup、enable gate 和 priority tree monotonicity。

关键代码（``dv/formal/properties/eh2_pic_assert.sv:L19-L53``）：

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

     // --- Priority/threshold inputs from core ---

逐段解释：

* 第 L19-L26 行：PIC checker 使用 ``clk``、``free_clk`` 和 ``rst_l``。
* 第 L29-L45 行：输入覆盖 external interrupt request、输出给 core 的 pending/claimid/priority/wakeup、core priority/threshold 和内部 register state。
* 第 L49-L52 行：checker 还接收 priority tree 的 selected priority、claimid、pending 和 wakeup 内部输出。

关键代码（``dv/formal/properties/eh2_pic_assert.sv:L66-L90``）：

.. code-block:: systemverilog

     property p_int_pending_implies_valid_claim;
       @(posedge clk) disable iff (~rst_l)
         (mexintpend_out[0])
           |->
         (claimid_out[0] > 0) && (claimid_out[0] < pt.PIC_TOTAL_INT_PLUS1);
     endproperty
     a_int_pending_implies_valid_claim: assert property (p_int_pending_implies_valid_claim)
       else $error("FORMAL FAIL: mexintpend with invalid claimid");

     property p_priority_below_threshold_no_int;
       @(posedge clk) disable iff (~rst_l)
         (selected_int_priority <= dec_tlu_meipt[0])
           |=>
         !mexintpend_out[0];
     endproperty
     a_priority_below_threshold_no_int: assert property (p_priority_below_threshold_no_int)
       else $error("FORMAL FAIL: interrupt pending when priority <= threshold");

逐段解释：

* 第 L66-L73 行：pending 时要求 claim ID 非 0 且小于 ``pt.PIC_TOTAL_INT_PLUS1``。
* 第 L82-L89 行：selected priority 小于等于 ``dec_tlu_meipt[0]`` 时，下一拍 ``mexintpend_out[0]`` 必须为 0。

接口关系：

* 被调用：``sby_pic.sby`` 读取该 property 文件。
* 调用：SVA implication。
* 共享状态：当前 PIC properties 主要检查 thread 0 的 interrupt output。

§5.2  ``eh2_pmp_assert.sv`` - LSU address check/PMP
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 region disabled、DCCM/PIC internal region、unmapped external fault、AMO in DCCM、side-effect alignment、DMA bypass 和 fault cause encoding。

关键代码（``dv/formal/properties/eh2_pmp_assert.sv:L18-L46``）：

.. code-block:: systemverilog

   module eh2_pmp_assert
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- eh2_lsu_addrcheck key signals ---
     input logic [31:0] start_addr_dc2,
     input logic [31:0] end_addr_dc2,
     input logic        access_fault_dc2,
     input logic        mpu_access_fault_dc2,
     input logic        unmapped_access_fault_dc2,
     input logic        amo_access_fault_dc2,
     input logic        misaligned_fault_dc2,
     input logic [3:0]  exc_mscause_dc2,
     input logic        is_sideeffects_dc2,
     input logic        lsu_pkt_dc2_valid,

逐段解释：

* 第 L18-L24 行：PMP checker 使用 clock/reset 和参数 include。
* 第 L27-L45 行：端口直接来自 LSU address check 相关信号，包括 start/end address、access fault 分类、exception cause、side-effects、LSU packet valid/DMA/word/atomic、DCCM/PIC/external 地址判定。

关键代码（``dv/formal/properties/eh2_pmp_assert.sv:L53-L84``）：

.. code-block:: systemverilog

     property p_all_disabled_no_fault;
       @(posedge clk) disable iff (~rst_l)
         (non_dccm_access_ok && lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
           |-> !mpu_access_fault_dc2;
     endproperty
     a_all_disabled_no_fault: assert property (p_all_disabled_no_fault)
       else $error("FORMAL FAIL: MPU fault with all regions disabled");

     property p_internal_region_no_fault;
       @(posedge clk) disable iff (~rst_l)
         ((start_addr_in_dccm_region_dc2 || start_addr_in_pic_region_dc2) &&
           lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
           |-> !mpu_access_fault_dc2;
     endproperty
     a_internal_region_no_fault: assert property (p_internal_region_no_fault)
       else $error("FORMAL FAIL: MPU fault in internal region");

     property p_unmapped_ext_triggers_fault;

逐段解释：

* 第 L53-L59 行：在 ``non_dccm_access_ok``、valid 且非 DMA 时，要求没有 MPU access fault。
* 第 L64-L71 行：DCCM 或 PIC region 且 valid、非 DMA 时，要求没有 MPU access fault。
* 第 L76-L84 行：外部 unmapped、非 DCCM/PIC、非 ``non_dccm_access_ok`` 且 valid、非 DMA 时，要求 ``access_fault_dc2``。

关键代码（``dv/formal/properties/eh2_pmp_assert.sv:L91-L150``）：

.. code-block:: systemverilog

     property p_atomic_in_dccm_no_fault;
       @(posedge clk) disable iff (~rst_l)
         (lsu_pkt_dc2_valid && lsu_pkt_dc2_atomic && addr_in_dccm_dc2)
           |-> !amo_access_fault_dc2;
     endproperty
     a_atomic_in_dccm_no_fault: assert property (p_atomic_in_dccm_no_fault)
       else $error("FORMAL FAIL: AMO in DCCM wrongly faulted");

     property p_sidefx_aligned_no_misalign;
       @(posedge clk) disable iff (~rst_l)
         (is_sideeffects_dc2 && addr_external_dc2 &&
          lsu_pkt_dc2_word && (start_addr_dc2[1:0] == 2'b00) &&
          lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
           |-> !misaligned_fault_dc2;

逐段解释：

* 第 L91-L97 行：AMO、valid 且地址在 DCCM 时，要求没有 AMO access fault。
* 第 L105-L113 行：side-effects external word access 且地址 4-byte aligned、valid、非 DMA 时，要求没有 misaligned fault。
* 第 L120-L126 行：DMA transaction valid 时要求没有 access fault。
* 第 L134-L140 行：access fault 时要求 ``exc_mscause_dc2`` 非 0 且小于等于 7。
* 第 L145-L150 行：cover 要求 external address valid transaction 可达。

接口关系：

* 被调用：``sby_pmp.sby`` 读取该 property 文件，top 是 ``eh2_lsu_addrcheck``。
* 调用：SVA implication 和 cover property。
* 共享状态：PMP checker 不读取 PMP config array，而是围绕 address-check 输出和 region 分类信号写 property。

§6  顶层 SVA 与 bind 文件
-------------------------

除了 ``properties/*.sv``，formal 目录还包含 ``eh2_veer_sva.sv`` 和 ``eh2_formal_bind.sv``。前者是当前 IFV filelist 明确编译的 top-level bind module；后者保留了多模块 bind 映射，但部分端口名与当前 checker 端口不一致，需要在使用前核对 elaboration 日志。

§6.1  ``eh2_veer_sva.sv`` 端口与输入假设
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义绑定到 ``eh2_veer`` 的顶层 SVA 模块，使用 ``.*`` auto-connect 读取顶层端口和内部层级路径。

关键代码（``dv/formal/eh2_veer_sva.sv:L9-L28``）：

.. code-block:: systemverilog

   module eh2_veer_sva
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic clk,
     input logic rst_l,
     input logic dbg_rst_l,
     input logic [31:1] rst_vec,
     input logic nmi_int,
     input logic [31:1] nmi_vec,
     input logic scan_mode,

     input logic core_rst_l,
     input logic dbg_core_rst_l,
     input logic active_l2clk,
     input logic free_l2clk,
     input logic lsu_bus_clk_en,
     input logic ifu_bus_clk_en,
     input logic dma_bus_clk_en,

逐段解释：

* 第 L9-L13 行：``eh2_veer_sva`` 和其它 checker 一样 import ``eh2_pkg``，并在参数块内 include ``eh2_param.vh``。
* 第 L14-L28 行：端口先声明 clock/reset、reset vector、NMI、scan mode、core reset、debug reset、clock gates 和 bus clock enable。

关键代码（``dv/formal/eh2_veer_sva.sv:L114-L137``）：

.. code-block:: systemverilog

     // =========================================================================
     // INPUT ASSUMPTIONS — constrain free inputs for meaningful proofs
     // =========================================================================
     // Assume dbg_rst_l tracks rst_l (debug reset tied to main reset in formal)
     a_dbg_rst_tracks_rst: assume property (@(posedge clk)
       dbg_rst_l == rst_l
     );

     // The formal top models functional operation only; scan mode forces some
     // reset logic active-high and makes the functional reset properties invalid.
     a_no_scan_mode: assume property (@(posedge clk)
       scan_mode == 1'b0
     );

     // Reset and NMI vectors are platform pins. The platform is expected to hold
     // them stable while reset is asserted; otherwise reset-vector properties are

逐段解释：

* 第 L114-L120 行：输入假设 ``dbg_rst_l == rst_l``，将 debug reset 与 main reset 绑定。
* 第 L122-L126 行：假设 ``scan_mode`` 为 0，使 reset 相关断言处于 functional mode。
* 第 L128-L137 行：reset 和 NMI vector 在 reset 期间保持稳定，避免 unconstrained platform input 影响 core reset property。

接口关系：

* 被调用：文件末尾通过 ``bind eh2_veer eh2_veer_sva u_eh2_veer_sva (.*);`` 绑定到顶层。
* 调用：使用 ``assume property`` 约束 free input。
* 共享状态：``.*`` auto-connect 要求 ``eh2_veer`` 作用域内存在同名端口或信号。

§6.2  ``eh2_veer_sva.sv`` 顶层 assertion 分类
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明顶层 SVA 覆盖 reset/clock、AXI、trace/debug、DCCM/ICCM、结构连接和 clock override。

关键代码（``dv/formal/eh2_veer_sva.sv:L142-L170``）：

.. code-block:: systemverilog

     // P1: external reset must force core reset in functional mode
     a_core_rst_active_low: assert property (@(posedge clk)
       (!rst_l && !scan_mode) |-> !core_rst_l
     );

     // P2: with all reset sources deasserted, core_rst_l is released
     a_core_rst_from_reset: assert property (@(posedge clk)
       (rst_l && dbg_core_rst_l && !scan_mode) |-> core_rst_l
     );

     // P3: active_l2clk settles after reset
     a_active_clk_known: assert property (@(posedge clk)
       $past(rst_l, 3) && $past(rst_l, 2) |-> !$isunknown(active_l2clk)
     );

     // P4: free_l2clk settles after reset
     a_free_clk_known: assert property (@(posedge clk)

逐段解释：

* 第 L142-L150 行：reset assertions 检查 external reset 拉低 core reset，以及 reset sources 释放后 core reset 释放。
* 第 L152-L170 行：clock 和 core reset known 性质使用 ``$past`` 和 ``$isunknown`` 检查 reset 后稳定性。

关键代码（``dv/formal/eh2_veer_sva.sv:L178-L218``）：

.. code-block:: systemverilog

     a_lsu_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awvalid == lsu.bus_intf.lsu_axi_awvalid
     );

     a_lsu_awaddr_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awaddr == lsu.bus_intf.lsu_axi_awaddr
     );

     a_lsu_awlen_legal: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awvalid |-> lsu_axi_awlen <= 8'd255
     );

     a_lsu_awsize_legal: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awvalid |-> lsu_axi_awsize <= 3'd7
     );

     a_lsu_wvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_wvalid == lsu.bus_intf.lsu_axi_wvalid

逐段解释：

* 第 L178-L206 行：LSU AXI property 的多处名称带 ``stable``，但当前实现实际检查顶层 AXI 端口与 ``lsu.bus_intf`` 层级路径相等。
* 第 L186-L192 行：AW len 和 size 仍是协议合法性检查。
* 第 L212-L218 行：读地址 channel 也通过层级路径检查 top-level 连接。

关键代码（``dv/formal/eh2_veer_sva.sv:L270-L385``）：

.. code-block:: systemverilog

     a_trace_valid_addr: assert property (@(posedge clk) disable iff (!rst_l)
       (!trace_rv_i_valid_ip[0][0] || !$isunknown(trace_rv_i_address_ip[0][31:0])) &&
       (!trace_rv_i_valid_ip[0][1] || !$isunknown(trace_rv_i_address_ip[0][63:32]))
     );

     a_debug_halt_track: assert property (@(posedge clk) disable iff (!rst_l)
       o_debug_mode_status[0] == dec.tlu.o_debug_mode_status[0]
     );

     // ...

   // Bind to the top-level eh2_veer instance
   bind eh2_veer eh2_veer_sva u_eh2_veer_sva (.*);

逐段解释：

* 第 L270-L273 行：trace valid 时要求对应 address lane 不是 unknown。
* 第 L275-L277 行：debug mode status 顶层输出必须等于 ``dec.tlu.o_debug_mode_status[0]``。
* 第 L282-L358 行：后续 assertions 覆盖 DCCM write/read mutex、ICCM connection、地址 known、IFU/LSU structural properties、reset vector stable 和 clock override known。
* 第 L366-L380 行：4 个 cover 只检查 halt/run ack、AXI write/read 相关信号不是 unknown 或可达。
* 第 L385 行：真正的 bind 语句把该 SVA 模块绑定到 ``eh2_veer``。

接口关系：

* 被调用：``ifv_filelist.f`` 直接编译该文件，IFV elaboration 绑定到 ``eh2_veer``。
* 调用：使用层级路径 ``lsu.bus_intf``、``ifu.mem_ctl``、``dma_ctrl`` 和 ``dec.tlu``。
* 共享状态：该文件是当前 IFV 顶层连接/结构 property 的主入口。

§6.3  ``eh2_formal_bind.sv`` 多模块 bind 映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：记录属性模块到 DEC/PIC/DBG/IFU/LSU/EXU/PMP 的 bind 意图，以及源码中可见的端口映射风险。

关键代码（``dv/formal/eh2_formal_bind.sv:L1-L16``）：

.. code-block:: systemverilog

   // ============================================================================
   // eh2_formal_bind.sv — EH2 Formal Bind File for IFV
   //
   // Binds formal property modules (dec, pic, dbg, ifu, lsu, exu, pmp) to
   // their corresponding RTL modules. Used by Cadence IFV (Incisive Formal
   // Verifier) to prove SVA assertions on the RTL design.
   //
   // RC5 (2026-05-09): Removed file-scope includes of eh2_pdef.vh/eh2_param.vh —
   // those caused ncvlog parser errors (SVNOTY/EXPSMC) because parameter
   // declarations are illegal outside a module.  The eh2_param_t type is already
   // visible from the bootstrap file's $unit-scope include of eh2_pdef.vh.

逐段解释：

* 第 L1-L6 行：注释说明该文件意图是把 dec、pic、dbg、ifu、lsu、exu、pmp property module 绑定到对应 RTL 模块。
* 第 L8-L13 行：RC5 注释说明删除 file-scope include，因为参数声明不能出现在 module 外；每个 property module 自己在参数端口列表里 include ``eh2_param.vh``。

关键代码（``dv/formal/eh2_formal_bind.sv:L21-L51``）：

.. code-block:: systemverilog

   bind eh2_dec eh2_dec_assert #() u_dec_assert (
       .clk                        (clk),
       .rst_l                      (rst_l),
       .dec_i0_decode_d            (dec_i0_decode_d),
       .dec_i1_decode_d            (dec_i1_decode_d),
       .dec_i0_instr_d             (dec_i0_instr_d),
       .dec_i1_instr_d             (dec_i1_instr_d),
       .dec_i0_waddr_wb            (dec_i0_waddr_wb),
       .dec_i0_wen_wb              (dec_i0_wen_wb),
       .dec_i1_waddr_wb            (dec_i1_waddr_wb),
       .dec_i1_wen_wb              (dec_i1_wen_wb),
       .dec_i0_csr_wraddr_wb       (dec_i0_csr_wraddr_wb),
       .dec_i0_csr_wen_wb          (dec_i0_csr_wen_wb),
       .dec_i0_csr_legal_d         (dec_i0_csr_legal_d),
       .dec_i0_csr_ren_d           (dec_i0_csr_ren_d),

逐段解释：

* 第 L21-L51 行：DEC bind 显式映射 clock/reset、decode、instruction、writeback、CSR、flush/debug/illegal/tid 信号。该段端口名与 ``eh2_dec_assert.sv`` 的端口列表一致。

关键代码（``dv/formal/eh2_formal_bind.sv:L79-L102``）：

.. code-block:: systemverilog

   bind eh2_dbg eh2_dbg_assert #() u_dbg_assert (
       .clk                        (clk),
       .rst_l                      (dbg_rst_l),
       .dmi_reg_wren               (dmi_reg_wren),
       .dmi_reg_rden               (dmi_reg_rden),
       .dmi_reg_addr               (dmi_reg_addr),
       .dmi_reg_wdata              (dmi_reg_wdata),
       .dmi_reg_rdata              (dmi_reg_rdata),
       .dmi_hard_reset             (dmi_hard_reset),
       .dmi_dmihard_reset          (dmi_dmihard_reset),
       .dmi_ndmreset               (dmi_ndmreset),
       .dmi_dmactive               (dmi_dmactive),
       .dmi_halt_req               (dmi_halt_req),
       .dmi_resume_req             (dmi_resume_req),

逐段解释：

* 第 L79-L102 行：DBG bind 段连接 ``dmi_reg_wren``、``dmi_reg_rden``、``dmi_hard_reset`` 等端口名。但 ``eh2_dbg_assert.sv`` 的实际端口是 ``dbg_state``、``dbg_state_en``、``dbg_halt_req``、``dbg_resume_req``、``dmcontrol_reg``、``dmi_reg_en`` 等。因此这个 bind 段不能被视为已匹配当前 checker 端口，使用前必须以 IFV elaboration 日志验证。

接口关系：

* 被调用：该文件可作为 formal bind 映射源，但当前 ``ifv_filelist.f`` 未列出它。
* 调用：SystemVerilog ``bind``。
* 共享状态：bind 段的端口名必须同时存在于 checker 和目标模块中；不匹配会在 elaboration 阶段失败。

§7  Formal top、Sail bridge 与 trace checker
--------------------------------------------

``eh2_formal_top.sv`` 提供了一个 full-core formal testbench；``sail_bridge.sv`` 和
``sail_trace_check.py`` 则把 EH2 trace/writeback 状态映射到 Sail/RISC-V 风格的
architectural checkpoint。

§7.1  ``eh2_formal_top.sv`` clock/reset 与 tied-off bus
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：构造 IFV full-core testbench，生成 clock/reset，把外部输入和 AXI responder 约束为 formal-safe 值。

关键代码（``dv/formal/eh2_formal_top.sv:L15-L36``）：

.. code-block:: systemverilog

   module eh2_formal_top
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   );

       // ====================================================================
       // Clock and reset generation (free-running for formal)
       // ====================================================================
       logic clk = 0;
       logic rst_l = 0;
       logic free_clk = 0;

       always #5 clk = ~clk;
       always #3 free_clk = ~free_clk;

       // Reset sequence
       initial begin
           rst_l = 0;
           repeat(10) @(posedge clk);

逐段解释：

* 第 L15-L19 行：formal top 是参数化模块，导入 ``eh2_pkg`` 并 include ``eh2_param.vh``。
* 第 L24-L29 行：``clk`` 和 ``free_clk`` 通过 ``always`` 反相生成，周期分别由 ``#5`` 和 ``#3`` 控制。
* 第 L31-L36 行：initial reset sequence 拉低 ``rst_l``，等待 10 个 ``clk`` 上升沿后拉高。

关键代码（``dv/formal/eh2_formal_top.sv:L129-L138``）：

.. code-block:: systemverilog

       // Memory slave: respond to reads with X (formal value), accept writes
       assign lsu_axi_awready = 1'b1;
       assign lsu_axi_wready  = 1'b1;
       assign lsu_axi_bvalid  = 1'b0;  // No write response initially
       assign lsu_axi_arready = 1'b1;
       assign lsu_axi_rvalid  = 1'b0;  // No read data initially
       assign lsu_axi_rdata   = '0;
       assign lsu_axi_rresp   = '0;
       assign lsu_axi_rlast   = 1'b0;
       assign lsu_axi_bresp   = '0;

逐段解释：

* 第 L129-L138 行：LSU AXI responder 被 tie off：AW/W/AR ready 为 1，B/R valid 为 0，读数据和 response 为 0。
* 第 L140-L199 行：同一文件还以类似方式 tie off IFU、SB 和 DMA bus；这为 full-core IFV 提供固定外部平台模型。

接口关系：

* 被调用：可作为 IFV full-core testbench 顶层使用。
* 调用：实例化 ``eh2_veer``。
* 共享状态：bus ready/valid tie-off 会影响 AXI liveness/cover property 的可达性。

§7.2  ``eh2_formal_top.sv`` 实例化 ``eh2_veer`` 与顶层断言
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 formal top 信号连接到 ``eh2_veer``，并在同一文件中定义一组直接顶层断言。

关键代码（``dv/formal/eh2_formal_top.sv:L218-L235``）：

.. code-block:: systemverilog

       eh2_veer #() u_dut (
           .clk                    (clk),
           .rst_l                  (rst_l),
           .dbg_rst_l              (rst_l),
           .rst_vec                (rst_vec),
           .nmi_int                (nmi_int),
           .nmi_vec                (nmi_vec),
           .jtag_id                (jtag_id),
           .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
           .trace_rv_i_address_ip  (trace_rv_i_address_ip),
           .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
           .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
           .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
           .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
           .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),
           .trace_rv_i_rd_valid_ip (trace_rv_i_rd_valid_ip),
           .trace_rv_i_rd_addr_ip  (trace_rv_i_rd_addr_ip),

逐段解释：

* 第 L218-L221 行：formal top 实例化 ``eh2_veer``，并把 ``dbg_rst_l`` 连接到 ``rst_l``。
* 第 L222-L235 行：reset/NMI/JTAG ID 和 trace 输出全部显式连接，其中 trace 包括 instruction、address、valid、exception、ecause、interrupt、tval 和 rd writeback 字段。

关键代码（``dv/formal/eh2_formal_top.sv:L441-L460``）：

.. code-block:: systemverilog

       // --- Category 1: Reset / Clock (6 assertions) ---

       // P1: core_rst_l is derived from external rst_l (active low)
       a_core_rst_active_low: assert property (@(posedge clk)
           !rst_l |-> !core_rst_l
       );

       // P2: core_rst_l follows dbg_rst_l
       a_dbg_rst_to_core: assert property (@(posedge clk)
           !dbg_rst_l |-> !core_rst_l
       );

       // P3: active_l2clk known after reset sequence
       a_active_clk_known: assert property (@(posedge clk)
           $past(rst_l, 3) && $past(rst_l, 2) |-> !$isunknown(active_l2clk)
       );

逐段解释：

* 第 L441-L460 行：formal top 内直接定义 reset/clock assertion。该文件继续在 L473-L608 定义 AXI、debug/trace 和 cover property，形式上与 ``eh2_veer_sva.sv`` 有重叠。

接口关系：

* 被调用：full-core formal run 可使用该 testbench。
* 调用：实例化 ``eh2_veer`` 并使用 SVA。
* 共享状态：``trace_rv_i_*`` 输出既被 formal top 断言使用，也可被 Sail trace checker 消费。

§7.3  ``sail_bridge.sv`` architectural projection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 EH2 writeback/exception/debug 状态映射为 Sail 可观测的 PC、GPR write、privilege、exception 和 halted 状态，并定义 3 条 SAIL-REF assertion。

关键代码（``dv/formal/spec/sail_bridge.sv:L24-L59``）：

.. code-block:: systemverilog

   module sail_bridge
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (
     input logic        clk,
     input logic        rst_l,

     // --- Architectural state from EH2 decode/writeback ---
     input logic [31:1]                    dec_i0_pc_wb1,
     input logic [31:1]                    dec_i1_pc_wb1,
     input logic [31:0]                    dec_i0_inst_wb1,
     input logic [31:0]                    dec_i1_inst_wb1,
     input logic [4:0]                     dec_i0_waddr_wb1,
     input logic [4:0]                     dec_i1_waddr_wb1,
     input logic                           dec_i0_wen_wb1,
     input logic                           dec_i1_wen_wb1,

逐段解释：

* 第 L24-L30 行：Sail bridge 是参数化模块，输入 clock/reset。
* 第 L33-L48 行：architectural state 输入来自 decode/writeback，包括 PC、instruction、rd、write enable、write data、valid、interrupt/exception 和 exception cause。
* 第 L51-L57 行：还接收 CSR priority/threshold 和 debug halted/mode 状态。

关键代码（``dv/formal/spec/sail_bridge.sv:L69-L99``）：

.. code-block:: systemverilog

     // Current architectural PC (last committed, lane 0)
     // SAIL: model/riscv_step.sail function step() uses PC for fetch
     logic [31:0] sail_pc;
     assign sail_pc = {dec_i0_pc_wb1, 1'b0};

     // GPR writeback (architectural register file update)
     // SAIL: model/riscv_regfile.sail function writeReg()
     logic        sail_gpr_wen;
     logic [4:0]  sail_gpr_waddr;
     logic [31:0] sail_gpr_wdata;
     assign sail_gpr_wen   = dec_i0_wen_wb1 & dec_tlu_i0_valid_wb1[0];
     assign sail_gpr_waddr = dec_i0_waddr_wb1;
     assign sail_gpr_wdata = dec_i0_wdata_wb1;

逐段解释：

* 第 L69-L72 行：``sail_pc`` 由 lane 0 的 ``dec_i0_pc_wb1`` 左移补 bit 0 得到。
* 第 L76-L81 行：GPR write projection 使用 i0 write enable 与 i0 valid，地址和数据来自 i0 writeback。
* 第 L85-L98 行：privilege 固定为 ``2'b11``；exception valid 由 i0 exception 或 interrupt 得到；halted 来自 ``dec_tlu_dbg_halted[0]``。

关键代码（``dv/formal/spec/sail_bridge.sv:L113-L137``）：

.. code-block:: systemverilog

     property p_sail_regfile_x0_stability;
       @(posedge clk) disable iff (~rst_l)
         (sail_gpr_wen && sail_gpr_waddr == 5'd0)
           |-> (sail_gpr_wdata == 32'd0);
     endproperty
     a_sail_regfile_x0_stability: assert property (p_sail_regfile_x0_stability)
       else $error("SAIL-FORMAL FAIL: non-zero writeback to x0");

     property p_sail_exception_cause_range;
       @(posedge clk) disable iff (~rst_l)
         (sail_exception_valid)
           |-> (sail_exception_cause inside {5'd0, 5'd2, 5'd3, 5'd5, 5'd6, 5'd7, 5'd11});

逐段解释：

* 第 L113-L119 行：x0 writeback assertion 要求写 x0 时写数据为 0。
* 第 L123-L129 行：exception valid 时要求 cause 在固定集合内。
* 第 L132-L137 行：M-mode assertion 要求 ``sail_cur_privilege`` 始终为 ``2'b11``。

接口关系：

* 被调用：可由 formal environment 实例化或 bind，用于 SAIL-REF 标记的 architectural checks。
* 调用：SVA assertion。
* 共享状态：bridge 当前只投影 i0 lane 和 thread 0，不覆盖 i1 或多 hart完整 architectural state。

§7.4  ``sail_trace_check.py`` trace divergence checker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供 Python 侧 trace replay/divergence checker，内置部分 RV32 指令语义并检查 PC、x0、rd 和 wdata。

关键代码（``dv/formal/spec/sail_trace_check.py:L20-L65``）：

.. code-block:: python

   import argparse
   import subprocess
   import sys
   import os
   import struct

   # ---------------------------------------------------------------------------
   # RISC-V instruction encoding helpers (RV32IMCB)
   # ---------------------------------------------------------------------------
   OPCODE_MASK    = 0x7F
   FUNCT3_MASK    = 0x7000
   FUNCT7_MASK    = 0xFE000000
   RD_MASK        = 0xF80
   RS1_MASK       = 0xF8000

   OP_LUI         = 0x37
   OP_AUIPC       = 0x17
   OP_JAL         = 0x6F
   OP_JALR        = 0x67

逐段解释：

* 第 L20-L24 行：脚本导入 argparse、subprocess、sys、os 和 struct。
* 第 L29-L45 行：定义 opcode/mask 常量，覆盖 LUI、AUIPC、JAL、JALR、branch、load/store、ALU、fence 和 system opcode。
* 第 L47-L65 行：定义 system funct3 常量和 ``decode_rd`` / ``decode_opcode`` / ``decode_funct3`` helper。

关键代码（``dv/formal/spec/sail_trace_check.py:L66-L130``）：

.. code-block:: python

   class SailChecker:
       """Wraps sail-riscv c_emulator for trace replay and divergence detection."""

       # SAIL architectural register checkpoints (matches sail_bridge.sv projections)
       SAIL_PC = 0
       SAIL_GPR_BASE = 1
       SAIL_GPR_COUNT = 32
       SAIL_X0_RESERVED = 0  # x0 is hardwired to zero in RISC-V
       SAIL_PRIV_M_MODE = 3
       SAIL_MSTATUS = 0x300
       SAIL_MCAUSE  = 0x342

       def __init__(self, sail_bin):
           self.sail_bin = sail_bin
           self.gpr = [0] * 32
           self.pc = 0

逐段解释：

* 第 L66-L77 行：``SailChecker`` 保存 architectural checkpoint 常量，包括 PC、GPR、x0、M-mode 和 CSR 地址。
* 第 L78-L88 行：构造与 reset 初始化 gpr、pc 和 mstatus。
* 第 L90-L130 行：``step_instruction`` 对 LUI、AUIPC、JAL、JALR、branch、ALU_IMM、ALU 和默认路径更新 PC/GPR write。注释写明生产环境会调用 sail c_emulator，但当前实现内置部分 architectural semantics。

关键代码（``dv/formal/spec/sail_trace_check.py:L132-L162``）：

.. code-block:: python

       def check_against_eh2_trace(self, eh2_pc, eh2_rd, eh2_wen, eh2_wdata, eh2_instr):
           """Compare EH2 trace entry against sail execution."""
           sail_next_pc, sail_gpr_write = self.step_instruction(eh2_instr)

           divergences = []

           # Check 1: PC match
           if eh2_pc != self.pc:
               divergences.append(
                   f"PC divergence: EH2={eh2_pc:#010x} SAIL={self.pc:#010x}"
               )

           # Check 2: x0 writes
           if eh2_wen and eh2_rd == 0 and eh2_wdata != 0:
               divergences.append(
                   f"x0 writeback violation: EH2 wrote {eh2_wdata:#010x} to x0"

逐段解释：

* 第 L132-L135 行：checker 用 EH2 instruction 推进 SailChecker 内部状态。
* 第 L138-L142 行：PC mismatch 会生成 ``PC divergence`` 文本。
* 第 L145-L148 行：写 x0 且写数据非 0 会生成 x0 writeback violation。
* 第 L151-L162 行：如果 Sail 也产生 GPR write，则比较 rd 和 wdata，并记录 mismatch。

接口关系：

* 被调用：命令行 ``python3 sail_trace_check.py --trace ... --sail ...``。
* 调用：当前源码导入 subprocess 但 ``step_instruction`` 未实际调用 subprocess。
* 共享状态：脚本期望 trace entry 至少能提供 pc、rd、wen、wdata 和 instruction。

§8  证明脚本关系
----------------

§8.1  SBY property 子集
~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 SymbiYosys 配置当前覆盖的 property 子集和 top 模块。

关键代码（``dv/formal/scripts/sby_dbg.sby:L16-L24``）：

.. code-block:: yaml

   [script]
   read -define FORMAL
   read -sv ../../rtl/snapshots/default/eh2_pdef.vh
   read -sv ../../rtl/design/include/eh2_def.sv
   read -sv ../../rtl/design/lib/beh_lib.sv
   read -sv ../../rtl/design/lib/eh2_lib.sv
   read -sv ../../rtl/design/dbg/eh2_dbg.sv
   read -sv ../properties/eh2_dbg_assert.sv
   prep -top eh2_dbg

逐段解释：

* 第 L16-L24 行：``sby_dbg.sby`` 读取 FORMAL define、参数/类型/lib、``eh2_dbg.sv`` 和 ``eh2_dbg_assert.sv``，top 是 ``eh2_dbg``。

关键代码（``dv/formal/scripts/sby_pmp.sby:L16-L24``）：

.. code-block:: yaml

   [script]
   read -define FORMAL
   read -sv ../../rtl/snapshots/default/eh2_pdef.vh
   read -sv ../../rtl/design/include/eh2_def.sv
   read -sv ../../rtl/design/lib/beh_lib.sv
   read -sv ../../rtl/design/lib/eh2_lib.sv
   read -sv ../../rtl/design/lsu/eh2_lsu_addrcheck.sv
   read -sv ../properties/eh2_pmp_assert.sv
   prep -top eh2_lsu_addrcheck

逐段解释：

* 第 L16-L24 行：``sby_pmp.sby`` 将 top 设为 ``eh2_lsu_addrcheck``，只读取 PMP property，不读取完整 LSU。
* 同目录还有 ``sby_dec.sby`` 与 ``sby_pic.sby``，分别读取 ``eh2_dec_assert.sv``、``eh2_pic_assert.sv``。当前没有 ``sby_exu.sby``、``sby_ifu.sby`` 或 ``sby_lsu.sby``。

接口关系：

* 被调用：开发者可手动运行 ``sby -f scripts/sby_*.sby``。
* 调用：Yosys/SymbiYosys ``read -sv`` 和 ``prep -top``。
* 共享状态：SBY 文件使用相对路径 ``../../rtl/...``，需要从 ``dv/formal`` 目录运行才与注释一致。

§8.2  IFV prove 与 CEX dump
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 IFV TCL 脚本如何添加 clock、收集 assertion、prove 并输出 summary/diagnostic。

关键代码（``dv/formal/scripts/ifv_prove.tcl:L1-L13``）：

.. code-block:: tcl

   # IFV 15.20 proof script for EH2.
   #
   # This intentionally uses the legacy FormalVerifier shell commands supported by
   # INCISIVE152. Newer check_formal/report_cex/write_vcd commands are not
   # available in this installed tool version.

   puts "IFV: EH2 formal proof start"
   clock -add clk -initial 0 -period 2 -width 1
   assertion -add -specification
   prove
   assertion -summary
   puts "IFV: EH2 formal proof complete"
   exit

逐段解释：

* 第 L1-L5 行：脚本注释限定工具命令集为 IFV 15.20 / INCISIVE152 支持的 legacy FormalVerifier shell。
* 第 L7-L12 行：脚本打印开始信息，添加 clock，添加 specification assertions，执行 ``prove``，输出 assertion summary，再打印完成信息。

关键代码（``dv/formal/scripts/ifv_cex_dump.tcl:L13-L23``）：

.. code-block:: tcl

   set props {
     eh2_veer.u_eh2_veer_sva.a_core_rst_active_low
     eh2_veer.u_eh2_veer_sva.a_core_rst_from_reset
     eh2_veer.u_eh2_veer_sva.a_dccm_wr_rd_mutex
     eh2_veer.u_eh2_veer_sva.a_debug_halt_track
     eh2_veer.u_eh2_veer_sva.a_dma_arvalid_stable
     eh2_veer.u_eh2_veer_sva.a_dma_awvalid_stable
     eh2_veer.u_eh2_veer_sva.a_iccm_wr_rd_mutex
     eh2_veer.u_eh2_veer_sva.a_ifu_arvalid_stable
     eh2_veer.u_eh2_veer_sva.a_ifu_awvalid_stable

逐段解释：

* 第 L13-L23 行：CEX dump 脚本列出一组 ``eh2_veer.u_eh2_veer_sva`` property 名称，作为诊断目标列表。
* 第 L40-L52 行：脚本对每个 property 创建 ``build/cex_<short>.txt``，打印 ``assertion -show <property> -verbose -list`` 的诊断块。

接口关系：

* 被调用：``make ifv`` 使用 ``ifv_prove.tcl``；``make ifv_cex`` 使用 ``ifv_cex_dump.tcl``。
* 调用：IFV shell 命令 ``clock``、``assertion``、``prove``。
* 共享状态：CEX property 名称与 ``eh2_veer_sva.sv`` 中的 assertion label 一一对应。

§9  行为汇总
------------

formal property 体系由三层组成：

* 局部 property 模块：``properties/*.sv`` 按 DBG/DEC/EXU/IFU/LSU/PIC/PMP 切分，输入端口是目标 RTL 的内部或边界信号。
* 顶层 SVA：``eh2_veer_sva.sv`` 绑定 ``eh2_veer``，重点检查 reset、AXI 连接、trace/debug、DCCM/ICCM 和 clock override 等顶层结构属性。
* architectural bridge：``sail_bridge.sv`` 和 ``sail_trace_check.py`` 把 EH2 trace/writeback 状态映射到 Sail 风格的 PC、GPR、privilege、exception 和 halted checkpoint。

从源码看，当前 IFV filelist 明确纳入的是 ``eh2_veer_sva.sv``；``eh2_formal_bind.sv`` 是多模块 bind 映射文件，但当前 filelist 没有列入，且其中 DBG/IFU/LSU/EXU bind 段存在端口名与 checker 端口不一致的风险。使用这些 bind 段前必须以 IFV elaboration 日志确认。

§10  参考资料
-------------

* 关联章节：:doc:`formal_infra`、:ref:`formal_flow`
* 关联 ADR：:ref:`adr-0012`、:ref:`adr-0014`、:ref:`adr-0015`
* Property 源目录：``/home/host/eh2-veri/dv/formal/properties/``
* 顶层 SVA：``/home/host/eh2-veri/dv/formal/eh2_veer_sva.sv``
* Formal bind：``/home/host/eh2-veri/dv/formal/eh2_formal_bind.sv``
* Formal top：``/home/host/eh2-veri/dv/formal/eh2_formal_top.sv``
* Sail bridge：``/home/host/eh2-veri/dv/formal/spec/sail_bridge.sv``
* Trace checker：``/home/host/eh2-veri/dv/formal/spec/sail_trace_check.py``

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从脚本、Makefile 或配置文件中找到本页讲到的真实入口。

.. code-block:: bash

   rg -n "def main|argparse|subprocess|class |target:" dv/uvm/core_eh2/scripts scripts Makefile | head -80
   rg -n "cover.cfg|cov_full_nc.ccf|rtl_simulation.yaml|eh2_configs.yaml" docs/sphinx_cn/source/appendix_e_config docs/sphinx_cn/source/appendix_f_scripts

**进阶题**：检查工具职责是否按 VCS/NC/Formal/Syn/Lint 分开，而不是混成一个流程。

.. code-block:: bash

   rg -n "urg|imc|vcs|irun|xrun|dc_shell|fm_shell|verilator|verible" docs/sphinx_cn/source/appendix_c_tools docs/sphinx_cn/source/appendix_f_scripts | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？
