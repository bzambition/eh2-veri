.. _appendix_b_uvm_trace_agent:
.. _appendix_b_uvm/trace_agent:

Trace Agent 源码字典
====================

:status: draft
:source: dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/common/trace_agent/` 下的 trace monitor 组件。当前目录没有
``eh2_trace_agent.sv`` top-level agent；env 直接创建 ``eh2_trace_monitor`` 和
``eh2_dut_probe_monitor`` 两个 monitor。``eh2_trace_monitor`` 从 RTL trace packet 采样
retire 指令和 regular writeback 字段；``eh2_dut_probe_monitor`` 只发布 trace packet
无法及时表达的异步写回事件，包括 DIV writeback、DIV overwrite cancel 和 NB-load completion。

本章覆盖 5 个 trace agent 源文件，以及 DUT probe interface、env、tb 和 cosim scoreboard
连接点：

* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`
* :file:`dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
* :file:`dv/uvm/core_eh2/env/eh2_dut_probe_if.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Trace 路径分成 regular retire 和 async writeback 两条 analysis 流。regular retire 来自
``eh2_trace_intf``，每个有效 slot 生成一笔 ``eh2_trace_seq_item``。async writeback 来自
``eh2_dut_probe_if`` 的 DIV/NB-load 内部信号，也复用 ``eh2_trace_seq_item`` 作为 FIFO item
类型，但 ``wb_source`` 标记为 ``EH2_WB_SRC_DIV`` 或 ``EH2_WB_SRC_NB_LOAD``。

::

   RTL trace_rv_i_* ports
      |
      +-- eh2_trace_intf --> eh2_trace_monitor.ap
                              |
                              +-- cosim_agt.scoreboard.trace_fifo
                              +-- dfd_scoreboard.trace_fifo

   DUT hierarchical probe signals
      |
      +-- eh2_dut_probe_if --> eh2_dut_probe_monitor.ap
                               |
                               +-- cosim_agt.scoreboard.dut_probe_fifo

接口关系：

* 被调用：``core_eh2_env`` 直接创建 ``trace_monitor`` 与 ``dut_probe_monitor``。
* 调用：``trace_monitor`` 调 ``ap.write(txn)``；``dut_probe_monitor`` 调 ``ap.write(txn)``。
* 共享状态：``trace_intf``、``dut_probe_intf``、``probe_vif.wb_seq``、``eh2_trace_seq_item``。

§2  ``eh2_trace_agent_pkg.sv`` — package 与 writeback source 常量
------------------------------------------------------------------------------------------------------------------------

职责：package 汇入 trace seq item、trace monitor 和 DUT probe monitor，并定义 writeback
source 分类常量。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv:L7-L21``）：

.. code-block:: systemverilog

   package eh2_trace_agent_pkg;

     `include "uvm_macros.svh"
     import uvm_pkg::*;

     localparam int EH2_WB_SRC_REGULAR = 0;
     localparam int EH2_WB_SRC_DIV     = 1;
     localparam int EH2_WB_SRC_NB_LOAD = 2;

     // Trace agent components
     `include "eh2_trace_seq_item.sv"
     `include "eh2_trace_monitor.sv"
     `include "eh2_dut_probe_monitor.sv"

   endpackage

逐段解释：

* 第 7 行：声明 ``eh2_trace_agent_pkg``。
* 第 9~10 行：引入 UVM 宏和 ``uvm_pkg``。
* 第 12~14 行：定义 ``EH2_WB_SRC_REGULAR``、``EH2_WB_SRC_DIV`` 和
  ``EH2_WB_SRC_NB_LOAD``，用于区分 regular trace writeback 与 async writeback hint。
* 第 17~19 行：include trace item、trace monitor 和 DUT probe monitor；该目录没有 top-level
  agent 文件。
* 第 21 行：结束 package。

接口关系：

* 被调用：env package、cosim agent package 和 test package import 该 package。
* 调用：SystemVerilog include。
* 共享状态：writeback source 常量被 trace monitor、DUT probe monitor 和 cosim scoreboard 使用。

§3  ``eh2_trace_intf.sv`` — RTL trace packet interface
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_trace_intf`` 把 DUT trace ports 组织成 monitor 可读的 interface，并提供 thread 0
i0/i1 便捷解码信号。

§3.1  trace packet 信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L19-L38``）：

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

逐段解释：

* 第 19~24 行：interface 参数化 ``NUM_THREADS``，端口为 ``clk`` 和 ``rst_n``。
* 第 26~33 行：trace packet 包括 instruction、PC address、valid、exception、ecause、
  interrupt 和 tval。
* 第 34~38 行：``rd_valid``、``rd_addr`` 和 ``rd_wdata`` 是 verification-only
  RVFI-equivalent writeback view；注释说明 lane 0 对应 i0，lane 1 对应 i1。

接口关系：

* 被调用：tb 顶层实例化 ``trace_intf`` 并连接 ``trace_rv_i_*`` DUT trace ports。
* 调用：无。
* 共享状态：trace monitor 读取这些信号构造 ``eh2_trace_seq_item``。

§3.2  thread 0 i0/i1 便捷解码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L39-L77``）：

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

逐段解释：

* 第 39~48 行：声明 thread 0 i0 的便捷信号，包括 PC、instruction、valid、exception、
  ecause 和 writeback 字段。
* 第 50~58 行：声明 thread 0 i1 的同类便捷信号。

接口关系：

* 被调用：``eh2_trace_monitor`` 直接读取 ``t0_i0_*`` 和 ``t0_i1_*``。
* 调用：无。
* 共享状态：便捷信号由下方 continuous assignment 驱动。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L60-L77``）：

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

逐段解释：

* 第 60~68 行：i0 使用 lower 32-bit instruction、lower 32-bit PC、``valid[0][0]`` 和
  ``rd_addr[0][4:0]``。
* 第 70~77 行：i1 使用 upper 32-bit instruction、upper 32-bit PC、``valid[0][1]`` 和
  ``rd_addr[0][9:5]``。

接口关系：

* 被调用：trace monitor 的 i0/i1 分支。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``address``、``insn``、``valid``、``exception``、``rd_*``。

§3.3  monitor clocking block
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv:L79-L93``）：

.. code-block:: systemverilog

     // Monitor clocking block
     clocking monitor_cb @(posedge clk);
       input insn;
       input address;
       input valid;
       input exception;
       input ecause;
       input interrupt;
       input tval;
       input rd_valid;
       input rd_addr;
       input rd_wdata;
     endclocking

   endinterface

逐段解释：

* 第 79~91 行：``monitor_cb`` 在 ``posedge clk`` 处声明 trace packet 和 writeback view 为 input。
* 第 93 行：结束 interface。当前 ``eh2_trace_monitor`` 直接读取便捷信号和 arrays，没有显式通过
  ``monitor_cb`` 访问。

接口关系：

* 被调用：作为 interface 定义的一部分供 monitor 使用。
* 调用：SystemVerilog clocking block。
* 共享状态：trace packet 信号。

§4  ``eh2_trace_seq_item.sv`` — trace/cosim transaction
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_trace_seq_item`` 是 trace monitor、DUT probe monitor 和 cosim scoreboard 之间的
统一 transaction 类型。它既能表示一条 retired instruction，也能表示 async writeback hint。

§4.1  基本 retire、trap 和 writeback 字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L7-L32``）：

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

逐段解释：

* 第 7 行：该类继承 ``uvm_sequence_item``。
* 第 10~13 行：``thread_id`` 与 ``slot`` 标识 thread 和 i0/i1 slot。
* 第 16~17 行：``pc`` 与 ``insn`` 保存 retired instruction 的 PC 和 instruction bits。
* 第 20~23 行：``exception``、``ecause``、``interrupt``、``tval`` 保存 trap 相关信息。
* 第 26~32 行：writeback 字段包括 valid、destination、data、suppress、tag 和 source。

接口关系：

* 被调用：trace monitor 和 DUT probe monitor 创建该对象；cosim scoreboard 消费该对象。
* 调用：无。
* 共享状态：transaction 字段。

§4.2  cosim state、CSR snapshot 与 UVM field
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L33-L74``）：

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

     `uvm_object_utils_begin(eh2_trace_seq_item)
       `uvm_field_int(thread_id, UVM_ALL_ON)
       `uvm_field_int(slot, UVM_ALL_ON)
       `uvm_field_int(pc, UVM_ALL_ON)
       `uvm_field_int(insn, UVM_ALL_ON)
       `uvm_field_int(exception, UVM_ALL_ON)

逐段解释：

* 第 33~38 行：``mip``、``nmi``、``nmi_int``、``debug_req`` 和 ``mcycle`` 来自 DUT probe，
  供 Spike notification 使用。
* 第 40~44 行：``dut_mtvec``、``dut_mepc``、``dut_mcause``、``dut_mtval`` 是 exception
  或 interrupt 时采样的 DUT-side trap CSR snapshot。
* 第 46~48 行：``commit_time`` 与 ``cycle_count`` 保存 monitor 时间统计。
* 第 50~55 行：UVM field macro 开始注册基础字段。

接口关系：

* 被调用：trace monitor ``populate_cosim_state`` 和 trap snapshot 逻辑写这些字段。
* 调用：UVM object macro。
* 共享状态：transaction 字段。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L55-L74``）：

.. code-block:: systemverilog

       `uvm_field_int(exception, UVM_ALL_ON)
       `uvm_field_int(ecause, UVM_ALL_ON)
       `uvm_field_int(interrupt, UVM_ALL_ON)
       `uvm_field_int(tval, UVM_ALL_ON)
       `uvm_field_int(wb_valid, UVM_ALL_ON)
       `uvm_field_int(wb_dest, UVM_ALL_ON)
       `uvm_field_int(wb_data, UVM_ALL_ON)
       `uvm_field_int(wb_suppress, UVM_ALL_ON)
       `uvm_field_int(wb_tag, UVM_ALL_ON)
       `uvm_field_int(wb_source, UVM_ALL_ON)
       `uvm_field_int(mip, UVM_ALL_ON)
       `uvm_field_int(nmi, UVM_ALL_ON)
       `uvm_field_int(nmi_int, UVM_ALL_ON)
       `uvm_field_int(debug_req, UVM_ALL_ON)
       `uvm_field_int(mcycle, UVM_ALL_ON)
       `uvm_field_int(dut_mtvec, UVM_ALL_ON)
       `uvm_field_int(dut_mepc, UVM_ALL_ON)
       `uvm_field_int(dut_mcause, UVM_ALL_ON)
       `uvm_field_int(dut_mtval, UVM_ALL_ON)
     `uvm_object_utils_end

逐段解释：

* 第 55~64 行：注册 trap 和 writeback 字段。
* 第 65~69 行：注册 interrupt/NMI/debug state 字段。
* 第 70~74 行：注册 DUT-side trap CSR snapshot 字段，并结束 UVM object macro。

接口关系：

* 被调用：UVM print/copy/compare 自动化路径。
* 调用：UVM field macro。
* 共享状态：transaction 字段。

§4.3  基础 helper function
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L76-L95``）：

.. code-block:: systemverilog

     function new(string name = "eh2_trace_seq_item");
       super.new(name);
     endfunction

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

逐段解释：

* 第 76~78 行：constructor 只调用父类 constructor。
* 第 81~85 行：``convert2string`` 输出 thread、slot、PC、instruction 和 exception/OK 状态。
* 第 88~90 行：``get_opcode`` 返回 ``insn[6:0]``。
* 第 93~95 行：``get_rd`` 返回 ``insn[11:7]``。

接口关系：

* 被调用：trace monitor log 调 ``convert2string``；cosim scoreboard helper 调 opcode/rd helper。
* 调用：``$sformatf``。
* 共享状态：当前 item 的 ``insn``、``thread_id``、``slot``、``pc``、``exception``。

§4.4  ``get_compressed_rd()`` — compressed destination register
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L97-L135``）：

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

逐段解释：

* 第 97~103 行：function 提取 ``funct3`` 和 ``quadrant``。
* 第 105~109 行：quadrant 0 中，``C.ADDI4SPN`` 和 ``C.LW`` 使用 compressed rd' 编码
  ``{2'b01, insn[4:2]}``。
* 第 110~117 行：quadrant 1 中，``C.ADDI``、``C.LI``、``C.LUI`` 返回 ``insn[11:7]``；
  ``C.JAL`` 返回 x1；``funct3=100`` 返回 compressed register bank。

接口关系：

* 被调用：``get_write_rd`` 和 ``writes_rd``。
* 调用：无。
* 共享状态：读取 ``insn``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L121-L135``）：

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

逐段解释：

* 第 121~129 行：quadrant 2 中，``C.SLLI``、``C.LWSP`` 返回 ``insn[11:7]``；
  ``C.JALR`` 返回 x1；``C.MV``/``C.ADD`` 在 ``insn[6:2]`` 非 0 时返回 ``insn[11:7]``。
* 第 131~134 行：未匹配路径返回 x0。
* 第 135 行：结束 function。

接口关系：

* 被调用：``get_write_rd`` 和 ``writes_rd``。
* 调用：无。
* 共享状态：读取 ``insn``。

§4.5  instruction classifier helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L137-L179``）：

.. code-block:: systemverilog

     // Get source register 1
     function bit [4:0] get_rs1();
       return insn[19:15];
     endfunction

     // Get source register 2
     function bit [4:0] get_rs2();
       return insn[24:20];
     endfunction

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

逐段解释：

* 第 137~145 行：``get_rs1`` 和 ``get_rs2`` 分别返回 ``insn[19:15]`` 和 ``insn[24:20]``。
* 第 148~150 行：``is_branch`` 判断 opcode ``7'b1100011``。
* 第 153~155 行：``is_load`` 判断 opcode ``7'b0000011``。
* 第 158~160 行：``is_store`` 判断 opcode ``7'b0100011``。

接口关系：

* 被调用：cosim scoreboard 的 instruction classification helper 可调用这些 function。
* 调用：``get_opcode``。
* 共享状态：读取 ``insn``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L162-L194``）：

.. code-block:: systemverilog

     // Check if instruction is an atomic memory operation
     function bit is_amo();
       return (get_opcode() == 7'b0101111);
     endfunction

     // Check if instruction is a DIV/REM operation. MUL operations use the same
     // opcode/funct7 but write through the normal pipeline, not the DIV monitor.
     function bit is_div();
       if (is_compressed()) return 1'b0;
       return (get_opcode() == 7'b0110011 &&
               insn[31:25] == 7'b0000001 &&
               insn[14:12] inside {3'b100, 3'b101, 3'b110, 3'b111});
     endfunction

     // Check if instruction is compressed
     function bit is_compressed();
       return (insn[1:0] != 2'b11);
     endfunction

逐段解释：

* 第 162~165 行：``is_amo`` 判断 opcode ``7'b0101111``。
* 第 167~174 行：``is_div`` 排除 compressed instruction，并要求 opcode 为
  ``7'b0110011``、``funct7=7'b0000001``、``funct3`` 属于 DIV/REM 四类。
* 第 176~179 行：``is_compressed`` 判断 ``insn[1:0] != 2'b11``。

接口关系：

* 被调用：cosim scoreboard 判断 DIV、memory 和 async writeback 关系时可使用这些 helper。
* 调用：``is_compressed`` 和 ``get_opcode``。
* 共享状态：读取 ``insn``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L181-L224``）：

.. code-block:: systemverilog

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
       return (get_opcode() == 7'b1101111) ||  // JAL
              (get_opcode() == 7'b1100111);    // JALR

逐段解释：

* 第 181~190 行：``is_compressed_load_store`` 先确认 instruction 是 compressed，再提取
  ``funct3`` 和 ``quadrant``。
* 第 192~194 行：function 对 quadrant 0 和 quadrant 2 的 ``funct3=010`` 或 ``110`` 返回真。
* 第 197~200 行：``is_jump`` 判断 JAL 和 JALR opcode。

接口关系：

* 被调用：cosim scoreboard 的 memory/jump 分类路径可使用这些 helper。
* 调用：``is_compressed`` 和 ``get_opcode``。
* 共享状态：读取 ``insn``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv:L202-L224``）：

.. code-block:: systemverilog

     // Get architectural destination register for instructions that write GPRs.
     function bit [4:0] get_write_rd();
       if (is_compressed()) return get_compressed_rd();
       return get_rd();
     endfunction

     // Check if instruction writes to register
     function bit writes_rd();
       if (is_compressed()) begin
         return get_compressed_rd() != 5'b0;
       end

       if (get_rd() == 5'b0) return 1'b0;

       if (get_opcode() inside {7'b0110011, 7'b0010011, 7'b0110111,
                                7'b0010111, 7'b1101111, 7'b1100111,
                                7'b0000011, 7'b0101111}) begin
         return 1'b1;
       end

       // CSR instructions write rd when funct3 is nonzero.
       return (get_opcode() == 7'b1110011 && insn[14:12] != 3'b000);
     endfunction

逐段解释：

* 第 202~206 行：``get_write_rd`` 对 compressed instruction 使用 ``get_compressed_rd``，
  否则返回 ``get_rd``。
* 第 209~214 行：``writes_rd`` 对 compressed instruction 检查 compressed rd 是否非 x0；
  对普通 instruction 先排除 x0。
* 第 216~220 行：opcode 属于 ALU、immediate、LUI、AUIPC、JAL、JALR、load、AMO 时返回真。
* 第 222~224 行：CSR instruction 在 ``funct3`` 非 0 时返回真。

接口关系：

* 被调用：scoreboard 比较 writeback 时可用该 helper 判断 expected rd。
* 调用：``is_compressed``、``get_compressed_rd``、``get_rd``、``get_opcode``。
* 共享状态：读取 ``insn``。

§5  ``eh2_trace_monitor.sv`` — regular retire monitor
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_trace_monitor`` 采样 ``eh2_trace_intf``，为每个有效 i0/i1 slot 生成一笔
``eh2_trace_seq_item``，并把 regular writeback、interrupt/debug/NMI state 和 trap CSR snapshot
放入 item 后通过 analysis port 发布。

§5.1  component、analysis port 与 config_db
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L14-L48``）：

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

逐段解释：

* 第 14~16 行：monitor 继承 ``uvm_monitor`` 并注册 component 类型。
* 第 19~20 行：monitor 持有 ``eh2_trace_intf`` 和可选 ``eh2_dut_probe_if``。
* 第 23 行：``ap`` 是输出 ``eh2_trace_seq_item`` 的 analysis port。
* 第 26~28 行：统计 counters 包括 commit、exception 和 cycle。
* 第 30~32 行：constructor 只调用父类 constructor。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 创建 ``trace_monitor``。
* 调用：UVM component macro。
* 共享状态：``vif``、``probe_vif`` 和统计 counters。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L34-L48``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       ap = new("ap", this);
     endfunction

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

逐段解释：

* 第 34~37 行：build phase 创建 analysis port。
* 第 39~43 行：connect phase 从 config_db 获取 key ``vif``；失败时触发 ``uvm_fatal``。
* 第 44~47 行：``probe_vif`` 是 optional；获取失败时打印 warning，并在后续 cosim state 中填 0。
* 第 48 行：结束 connect phase。

接口关系：

* 被调用：UVM build/connect phase 调度。
* 调用：``uvm_config_db::get``、``uvm_fatal``、``uvm_warning``。
* 共享状态：config_db 中的 ``vif`` 和 ``probe_vif``。

§5.2  ``populate_cosim_state()`` — 从 probe 补充 Spike 通知状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L50-L71``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       fork
         monitor_trace();
       join
     endtask

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

逐段解释：

* 第 50~54 行：run phase fork ``monitor_trace`` 并 join；当前只有一个 fork 分支。
* 第 57~63 行：如果 ``probe_vif`` 非空，function 从 DUT probe 读取 debug、NMI、MIP 和
  mcycle 状态写入 transaction。
* 第 64~70 行：如果 ``probe_vif`` 为空，则把这些字段全部置 0。
* 第 71 行：结束 function。

接口关系：

* 被调用：i0 和 i1 item 创建后都会调用。
* 调用：无。
* 共享状态：读 ``probe_vif``，写 ``txn``。

§5.3  ``monitor_trace()`` — i0 retire item
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L73-L107``）：

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

逐段解释：

* 第 73~78 行：``monitor_trace`` 在 ``posedge vif.clk iff vif.rst_n`` 上运行，复位无效时不采样。
* 第 80 行：每个采样周期增加 ``cycle_count``。
* 第 83~85 行：当 ``vif.t0_i0_valid`` 为真时创建 ``trace_txn``，设置 thread 0 和 slot 0。
* 第 87~94 行：从 interface 写入 PC、instruction、exception、ecause、interrupt、tval、
  commit time 和 cycle count。

接口关系：

* 被调用：``run_phase``。
* 调用：UVM factory ``type_id::create``。
* 共享状态：读 ``vif``，写 ``txn`` 和 ``cycle_count``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L96-L126``）：

.. code-block:: systemverilog

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

           commit_count++;
           if (txn.exception) exception_count++;

逐段解释：

* 第 96~102 行：i0 regular writeback 从 trace packet lane 0 填入，``wb_source`` 设为
  ``EH2_WB_SRC_REGULAR``，``wb_suppress`` 固定为 0。
* 第 104 行：调用 ``populate_cosim_state`` 补充 Spike notification 状态。
* 第 107 行：如果 ``probe_vif`` 非空，用 ``probe_vif.wb_seq`` 给 trace item 打 tag。
* 第 109~110 行：增加 commit counter；异常时增加 exception counter。

接口关系：

* 被调用：i0 valid 分支。
* 调用：``populate_cosim_state``。
* 共享状态：读 ``vif`` 与 ``probe_vif``，写 ``txn`` 和 counters。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L112-L127``）：

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

逐段解释：

* 第 112~118 行：exception 或 interrupt 时，如果 ``probe_vif`` 非空，monitor 采样
  ``mtvec``、``mepc``、``mcause`` 和 ``mtval``。
* 第 119~121 行：如果没有 ``probe_vif``，仅把 ``dut_mtval`` fallback 到 trace packet 的
  ``tval``。
* 第 124~126 行：打印 commit log，并通过 ``ap.write(txn)`` 发布 item。

接口关系：

* 被调用：i0 valid 分支。
* 调用：``txn.convert2string``、UVM log macro、``ap.write``。
* 共享状态：读 ``probe_vif``，写 ``txn``，发布到 analysis port。

§5.4  ``monitor_trace()`` — i1 retire item
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L129-L158``）：

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

逐段解释：

* 第 129~133 行：当 ``vif.t0_i1_valid`` 为真时创建 item，设置 thread 0 和 slot 1。
* 第 134~141 行：从 i1 便捷信号和 trace arrays 填入 PC、instruction、exception、
  interrupt、tval 和 timing。
* 第 143~149 行：i1 regular writeback 从 trace packet lane 1 填入，source 同样设为
  ``EH2_WB_SRC_REGULAR``。

接口关系：

* 被调用：``monitor_trace`` 每周期 i1 valid 分支。
* 调用：UVM factory。
* 共享状态：读 ``vif``，写 ``txn``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L150-L176``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 150~154 行：i1 item 同样补充 cosim state，并在 ``probe_vif`` 存在时采样 ``wb_seq``。
* 第 156~157 行：更新 commit 与 exception 统计。
* 第 159~165 行：exception 或 interrupt 时采样 trap CSR snapshot。
* 第 166 行：进入没有 ``probe_vif`` 时的 fallback 分支。

接口关系：

* 被调用：i1 valid 分支。
* 调用：``populate_cosim_state``。
* 共享状态：读 ``probe_vif``，写 ``txn`` 和 counters。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L166-L176``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 166~168 行：没有 ``probe_vif`` 时，i1 的 ``dut_mtval`` 也 fallback 到 ``txn.tval``。
* 第 171~172 行：打印 commit log，包含 writeback valid、destination 和 data。
* 第 173 行：通过 analysis port 发布 i1 item。
* 第 174~176 行：结束 i1 分支、forever loop 和 task。

接口关系：

* 被调用：i1 valid 分支。
* 调用：``txn.convert2string``、UVM log macro、``ap.write``。
* 共享状态：analysis port 输出。

§5.5  ``report_phase()`` — 统计输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L178-L190``）：

.. code-block:: systemverilog

     // Report statistics
     function void report_phase(uvm_phase phase);
       super.report_phase(phase);
       `uvm_info("trace_monitor", $sformatf("=== Trace Monitor Statistics ==="), UVM_LOW)
       `uvm_info("trace_monitor", $sformatf("Total commits: %0d", commit_count), UVM_LOW)
       `uvm_info("trace_monitor", $sformatf("Total exceptions: %0d", exception_count), UVM_LOW)
       `uvm_info("trace_monitor", $sformatf("Total cycles: %0d", cycle_count), UVM_LOW)
       if (cycle_count > 0) begin
         `uvm_info("trace_monitor", $sformatf("IPC: %0.2f", real'(commit_count) / real'(cycle_count)), UVM_LOW)
       end
     endfunction

   endclass

逐段解释：

* 第 178~180 行：report phase 先调用父类 report phase。
* 第 181~184 行：打印 trace monitor statistics、commit 数、exception 数和 cycle 数。
* 第 185~187 行：如果 ``cycle_count > 0``，打印 ``commit_count / cycle_count`` 得到的 IPC。
* 第 188~190 行：结束 function 和 class。

接口关系：

* 被调用：UVM report phase 调度。
* 调用：UVM log macro 和 ``$sformatf``。
* 共享状态：统计 counters。

§6  ``eh2_dut_probe_if.sv`` — DUT probe interface
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_dut_probe_if`` 暴露 verification-only 内部 DUT 状态，供 trace monitor 采样 cosim
notification state，供 DUT probe monitor 采样 async writeback。

§6.1  DIV、NB-load 与 cosim notification 信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L14-L38``）：

.. code-block:: systemverilog

   interface eh2_dut_probe_if(
     input logic clk,
     input logic rst_n
   );

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

逐段解释：

* 第 14~17 行：interface 接收 ``clk`` 和 ``rst_n``。
* 第 19~25 行：DIV 相关信号包括 cancel、overwrite cancel、destination、raw result、
  write-enable 和 writeback data。
* 第 27~30 行：NB-load 相关信号包括 write enable、destination 和 data。
* 第 32~38 行：cosim notification state 包括 MIP、NMI、NMI pending、debug request 和 mcycle。

接口关系：

* 被调用：tb 顶层实例化 ``dut_probe_intf`` 并用 hierarchical references 连接。
* 调用：无。
* 共享状态：trace monitor、DUT probe monitor 和 cosim scoreboard 读取这些信号或字段。

§6.2  CSR/trap/debug/interrupt 状态与 ``wb_seq``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L39-L75``）：

.. code-block:: systemverilog

     // CSR mirror state (for directed tests and coverage)
     logic [31:0]      mstatus;
     logic [31:0]      mtvec;
     logic [31:0]      mepc;
     logic [31:0]      mcause;
     logic [31:0]      mtval;

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

逐段解释：

* 第 39~45 行：CSR mirror state 包括 ``mstatus``、``mtvec``、``mepc``、``mcause`` 和
  ``mtval``。
* 第 46~53 行：E4 stage trap 信号包括 mret、illegal、ecall、ebreak、debug ebreak 和
  instruction access fault。
* 第 54~59 行：writeback stage trap 信号包括 mret、illegal、ecall 和 ebreak。

接口关系：

* 被调用：trace monitor 在 exception/interrupt 时采样 CSR snapshot；directed tests 和 fcov
  也可读取这些 probe 信号。
* 调用：无。
* 共享状态：``dut_probe_intf``。

关键代码（``dv/uvm/core_eh2/env/eh2_dut_probe_if.sv:L60-L75``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 60~62 行：debug state 包括 ``debug_mode`` 和 ``dbg_halted``。
* 第 64~69 行：interrupt tracking 包括 generic interrupt valid、external/timer/software/NMI
  take 信号。
* 第 71~74 行：注释说明 ``wb_seq`` 是 global writeback sequence counter，由 probe monitor
  增加，并被 trace monitor 读取用于 async writeback matching。

接口关系：

* 被调用：DUT probe monitor 写 ``wb_seq``；trace monitor 读 ``wb_seq``。
* 调用：无。
* 共享状态：``wb_seq``。

§7  ``eh2_dut_probe_monitor.sv`` — async writeback monitor
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_dut_probe_monitor`` 只发布 trace packet 无法及时描述的 async writeback event：
DIV writeback、DIV overwrite cancel 和 NB-load completion。

§7.1  component、analysis port 与 reset 初值
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L13-L38``）：

.. code-block:: systemverilog

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

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       ap = new("ap", this);
     endfunction

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (!uvm_config_db#(virtual eh2_dut_probe_if)::get(this, "", "vif", vif)) begin
         `uvm_warning("dut_probe", "Could not get DUT probe virtual interface - async writeback monitoring disabled")
       end
     endfunction

逐段解释：

* 第 13~18 行：monitor 继承 ``uvm_monitor``，持有 ``eh2_dut_probe_if`` 和 analysis port。
* 第 20~21 行：``wb_count`` 统计 async writeback 数量，``wb_seq_counter`` 是全局 writeback
  sequence counter。
* 第 23~26 行：constructor 把 ``wb_seq_counter`` 初始化为 1，使 ``wb_tag >= 1``。
* 第 28~31 行：build phase 创建 analysis port。
* 第 33~38 行：connect phase 获取 ``vif``；失败时 warning，run phase 会因为 ``vif == null`` 不启动监视。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 创建 ``dut_probe_monitor``。
* 调用：``uvm_config_db::get`` 和 UVM warning macro。
* 共享状态：``vif``、``wb_count``、``wb_seq_counter``。

§7.2  run phase 并行监视 DIV 与 NB-load
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L40-L47``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       if (vif != null) begin
         fork
           monitor_division();
           monitor_nb_load();
         join
       end
     endtask

逐段解释：

* 第 40~41 行：run phase 只在 ``vif`` 非空时启动监视。
* 第 42~45 行：fork 两个并行 task：``monitor_division`` 与 ``monitor_nb_load``。
* 第 46~47 行：``join`` 等待两个 forever task；正常仿真期间该 run phase 持续运行。

接口关系：

* 被调用：UVM run phase 调度。
* 调用：``monitor_division`` 和 ``monitor_nb_load``。
* 共享状态：两个 task 共享 ``vif``、``wb_seq_counter`` 和 ``ap``。

§7.3  ``monitor_division()`` — DIV writeback 与 cancel
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L49-L70``）：

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

逐段解释：

* 第 49~55 行：``monitor_division`` 每个 ``vif.clk`` 上升沿且复位释放时采样。
* 第 56~63 行：当 ``div_wren`` 为真且 ``div_rd`` 非 x0 时，创建 ``div_wb_txn``，设置 slot 0、
  writeback valid、destination、data、source 和 tag。
* 第 64 行：把当前 tag 写到 ``vif.wb_seq``，供 trace monitor 标记 regular trace item。
* 第 65~69 行：发布 txn，打印 log，增加 ``wb_count`` 和 ``wb_seq_counter``。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：UVM factory、``ap.write``、UVM log macro。
* 共享状态：读 ``vif.div_*``，写 ``vif.wb_seq`` 和 counters。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L71-L96``）：

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

逐段解释：

* 第 71~75 行：overwrite cancel 分支要求 ``div_cancel``、``div_cancel_overwrite`` 为真且
  ``div_rd`` 非 x0；注释说明 speculative-flush cancel 不转发。
* 第 75~83 行：创建 ``div_cancel_txn``，设置 writeback valid、destination、raw result、
  ``wb_suppress=1``、source 和 tag。
* 第 83~84 行：写 ``vif.wb_seq`` 并发布 item。

接口关系：

* 被调用：``monitor_division``。
* 调用：UVM factory 和 ``ap.write``。
* 共享状态：读 ``vif.div_cancel*``，写 ``vif.wb_seq``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L85-L96``）：

.. code-block:: systemverilog

           `uvm_info("dut_probe", $sformatf("DIV OVERWRITE-CANCEL: x%0d = %08x wb_tag=%0d",
             vif.div_rd, vif.div_result, wb_seq_counter), UVM_HIGH)
           wb_count++;
           wb_seq_counter++;
         end
         else if (vif.div_cancel && !vif.div_cancel_overwrite) begin
           `uvm_info("dut_probe", $sformatf(
             "DIV SPEC-CANCEL: x%0d (dropped, no paired trace)",
             vif.div_rd), UVM_HIGH)
         end
       end
     endtask

逐段解释：

* 第 85~88 行：overwrite cancel 发布后打印 log，并递增 counters。
* 第 90~94 行：如果是 ``div_cancel`` 但不是 overwrite cancel，仅打印 dropped log，不发布 item。
* 第 95~96 行：结束 forever loop 和 task。

接口关系：

* 被调用：``monitor_division``。
* 调用：UVM log macro。
* 共享状态：``wb_count``、``wb_seq_counter``。

§7.4  ``monitor_nb_load()`` — NB-load completion
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L98-L121``）：

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

逐段解释：

* 第 98~104 行：NB-load monitor 每个 ``vif.clk`` 上升沿且复位释放时采样。
* 第 105~113 行：当 ``nb_load_wen`` 为真且 destination 非 x0 时，创建 ``nb_load_txn``，
  设置 writeback valid、destination、data、source 和 tag。
* 第 113~114 行：写 ``vif.wb_seq`` 并发布 item。

接口关系：

* 被调用：``run_phase`` fork。
* 调用：UVM factory 和 ``ap.write``。
* 共享状态：读 ``vif.nb_load_*``，写 ``vif.wb_seq``。

关键代码（``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv:L115-L130``）：

.. code-block:: systemverilog

           `uvm_info("dut_probe", $sformatf("NB LOAD: x%0d = %08x wb_tag=%0d",
             vif.nb_load_waddr, vif.nb_load_data, wb_seq_counter), UVM_HIGH)
           wb_count++;
           wb_seq_counter++;
         end
       end
     endtask

     function void report_phase(uvm_phase phase);
       super.report_phase(phase);
       `uvm_info("dut_probe", "=== DUT Probe Statistics (async only) ===", UVM_LOW)
       `uvm_info("dut_probe", $sformatf("Total async writebacks: %0d, wb_seq last: %0d",
                 wb_count, wb_seq_counter), UVM_LOW)
     endfunction

逐段解释：

* 第 115~118 行：NB-load item 发布后打印 log，并递增 counters。
* 第 119~121 行：结束 if、forever loop 和 task。
* 第 123~128 行：report phase 打印 async writeback 统计和最后的 ``wb_seq_counter``。
* 第 130 行：结束 class。

接口关系：

* 被调用：``monitor_nb_load`` 和 UVM report phase。
* 调用：UVM log macro 和 ``$sformatf``。
* 共享状态：``wb_count``、``wb_seq_counter``。

§8  tb 顶层与 env 连接
------------------------------------------------------------------------------------------------------------------------

职责：tb 顶层实例化 trace/probe interface，连接 DUT trace ports 和 internal probe signals，并把
virtual interface 注入 config_db；env 将 monitor analysis ports 接到 scoreboard。

§8.1  ``trace_intf`` 连接 DUT trace ports
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 731~732 行：tb 顶层以 ``RV_NUM_THREADS`` 实例化 ``eh2_trace_intf``。
* 第 735~741 行：DUT trace instruction、PC、valid、exception、ecause、interrupt 和 tval
  接到 interface。
* 第 742~744 行：RVFI-equivalent writeback view 的 ``rd_valid``、``rd_addr`` 和
  ``rd_wdata`` 也接到 interface。

接口关系：

* 被调用：tb 顶层 elaboration。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``trace_intf``。

§8.2  ``dut_probe_intf`` 连接 async writeback 与 cosim state
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

* 第 818 行：tb 顶层实例化 ``eh2_dut_probe_if``。
* 第 820~824 行：注释说明 regular writeback 不再由 probe 暴露，而是由 RTL trace packet 携带。
* 第 826~831 行：DIV cancel、overwrite cancel、rd、result、wren 和 wdata 接到 internal DUT path。
* 第 833~835 行：NB-load completion 信号接到 internal DUT path。

接口关系：

* 被调用：tb 顶层 elaboration。
* 调用：SystemVerilog continuous assignment 和宏 path。
* 共享状态：``dut_probe_intf``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L837-L848``）：

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

逐段解释：

* 第 837~840 行：tb 顶层从 external、timer 和 software interrupt 构造 ``mip``。
* 第 841~843 行：``nmi``、``nmi_int`` 和 ``debug_req`` 分别来自 ``nmi_int`` 与
  ``mpc_debug_halt_req[0]``。
* 第 844~848 行：``mcycle`` 由 TLU CSR registers 的 ``mcycleh`` 和 ``mcyclel`` 拼接得到。

接口关系：

* 被调用：tb 顶层 continuous assignment。
* 调用：无。
* 共享状态：``dut_probe_intf`` 的 cosim notification state。

§8.3  config_db 注入 interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1112-L1120``）：

.. code-block:: systemverilog

       // Store trace and DUT probe interfaces
       uvm_config_db#(virtual eh2_trace_intf)::set(null, "*trace_monitor*", "vif", trace_intf);
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*dut_probe_monitor*", "vif", dut_probe_intf);

       // Also provide DUT probe interface to trace monitor (for interrupt/debug state sampling)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*trace_monitor*", "probe_vif", dut_probe_intf);

       // Provide DUT probe interface to cosim agent's scoreboard (for reset monitoring)
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*cosim_agt*", "probe_vif", dut_probe_intf);

逐段解释：

* 第 1112~1114 行：tb 顶层把 ``trace_intf`` 注入给 ``*trace_monitor*`` 的 ``vif``，
  把 ``dut_probe_intf`` 注入给 ``*dut_probe_monitor*`` 的 ``vif``。
* 第 1116~1117 行：同一个 ``dut_probe_intf`` 也作为 ``probe_vif`` 注入给 trace monitor。
* 第 1119~1120 行：``dut_probe_intf`` 还注入给 ``*cosim_agt*``，供 cosim scoreboard 复位监测使用。

接口关系：

* 被调用：tb 顶层 initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：config_db 中的 ``vif`` 与 ``probe_vif``。

§8.4  env 创建 monitor 并连接 scoreboard
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L99-L104``）：

.. code-block:: systemverilog

       // Trace monitor
       trace_monitor = eh2_trace_monitor::type_id::create("trace_monitor", this);

       // DUT probe monitor
       dut_probe_monitor = eh2_dut_probe_monitor::type_id::create("dut_probe_monitor", this);


逐段解释：

* 第 99~100 行：env 直接创建 ``eh2_trace_monitor``。
* 第 102~103 行：env 直接创建 ``eh2_dut_probe_monitor``。
* 第 104 行：片段结束；源码没有创建 ``eh2_trace_agent`` wrapper。

接口关系：

* 被调用：``core_eh2_env.build_phase``。
* 调用：UVM factory ``type_id::create``。
* 共享状态：``trace_monitor`` 和 ``dut_probe_monitor`` component 句柄。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L151-L168``）：

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

       // Connect trace monitor to double-fault detection scoreboard
       trace_monitor.ap.connect(dfd_scoreboard.trace_fifo.analysis_export);

逐段解释：

* 第 151~154 行：cosim 开启且 ``cosim_agt`` 非空时，trace monitor output 接入
  ``cosim_agt.scoreboard.trace_fifo``。
* 第 156~159 行：DUT probe monitor output 接入 ``cosim_agt.scoreboard.dut_probe_fifo``。
* 第 161~164 行：LSU AXI4 monitor 也接入 cosim agent 的 memory port。
* 第 166~167 行：trace monitor output 还无条件接入 double-fault detection scoreboard。

接口关系：

* 被调用：``core_eh2_env.connect_phase``。
* 调用：analysis port ``connect``。
* 共享状态：scoreboard FIFO analysis exports。

§9  与 cosim scoreboard 的接口
------------------------------------------------------------------------------------------------------------------------

职责：cosim scoreboard 使用 ``trace_fifo`` 消费 regular trace item，使用 ``dut_probe_fifo`` 消费
async writeback hint。

§9.1  FIFO 类型与 trace consumption
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L33-L40``）：

.. code-block:: systemverilog

   class eh2_cosim_scoreboard extends uvm_scoreboard;

     `uvm_component_utils(eh2_cosim_scoreboard)

     // Analysis FIFOs from monitors
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) trace_fifo;
     uvm_tlm_analysis_fifo #(eh2_trace_seq_item) dut_probe_fifo;
     uvm_tlm_analysis_fifo #(axi4_seq_item)      lsu_axi_fifo;

逐段解释：

* 第 33~35 行：scoreboard 继承 ``uvm_scoreboard`` 并注册 component 类型。
* 第 37~40 行：``trace_fifo`` 和 ``dut_probe_fifo`` 都使用 ``eh2_trace_seq_item`` 类型；
  LSU AXI FIFO 使用 ``axi4_seq_item``。

接口关系：

* 被调用：cosim agent 创建 scoreboard。
* 调用：UVM FIFO 类型声明。
* 共享状态：analysis FIFO。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L207-L223``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 207~211 行：scoreboard 从 ``trace_fifo`` 阻塞获取 trace item，并增加 ``trace_item_count``。
* 第 213~217 行：cosim handle 已初始化时，按 ``trace_item.thread_id`` 把 item 放入
  per-thread pending queue。
* 第 218~221 行：更新 pending queue high watermark。
* 第 221~223 行：调用 ``process_pending_trace(tid)`` 处理该 thread 的 pending trace。

接口关系：

* 被调用：scoreboard run task。
* 调用：``trace_fifo.get`` 和 ``process_pending_trace``。
* 共享状态：``pending_trace_q``、``trace_item_count``。

§9.2  async writeback FIFO 与 IRQ-only path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L226-L238``）：

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

逐段解释：

* 第 226~229 行：async path 使用 ``eh2_trace_seq_item`` 作为 ``probe_item``，并转换成
  ``async_wb_hint_t``。
* 第 231~233 行：scoreboard 从 ``dut_probe_fifo`` 获取 item 并计数。
* 第 235~236 行：如果 source 是 regular writeback，scoreboard 直接丢弃，因为 regular
  writeback 已由 trace channel 携带。
* 第 238 行：async hint 的 rd 来自 ``probe_item.wb_dest``。

接口关系：

* 被调用：scoreboard async probe task。
* 调用：``dut_probe_fifo.get``。
* 共享状态：``probe_item_count``、async hint queue。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L565-L582``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 565~571 行：``compare_instruction`` 接收 thread id 和 trace item，并声明 writeback、
  trap 和 async hint 临时变量。
* 第 573~575 行：当 ``interrupt=1`` 且 ``exception=0`` 时，scoreboard 把 item 当作
  IRQ-only notification。
* 第 576~581 行：IRQ-only path 把 ``debug_req``、``nmi``、``nmi_int``、``mip`` 和
  ``mcycle`` 通知 Spike cosim。
* 第 582 行：打印 IRQ-only log。

接口关系：

* 被调用：``process_pending_trace`` 后续比较路径。
* 调用：``riscv_cosim_set_*`` DPI 函数和 UVM log macro。
* 共享状态：``prev_mip``、cosim handle。

§10  运行时行为边界
------------------------------------------------------------------------------------------------------------------------

职责：本节列出 trace monitor 当前源码明确支持和不支持的边界。

§10.1  当前 monitor 只显式采样 thread 0
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``eh2_trace_intf`` 参数化了 ``NUM_THREADS``，tb 顶层实例化时传入 ``RV_NUM_THREADS``。但
``eh2_trace_monitor`` 的 virtual interface 类型是 ``virtual eh2_trace_intf #(.NUM_THREADS(1))``，
并且 ``monitor_trace`` 只读取 ``t0_i0_*``、``t0_i1_*``、``interrupt[0]`` 和 ``tval[0]``。
因此本章只描述 thread 0 的 trace monitor 采样行为，不推断该 monitor 已遍历多个 thread。

接口关系：

* 被调用：``eh2_trace_monitor.monitor_trace``。
* 调用：无。
* 共享状态：thread 0 trace signals。

§10.2  regular writeback 与 async writeback 的边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

regular pipeline writeback 由 trace packet 的 ``rd_valid``、``rd_addr`` 和 ``rd_wdata`` 携带，
并在 ``eh2_trace_monitor`` 中标记为 ``EH2_WB_SRC_REGULAR``。DUT probe monitor 不再发布
regular writeback；它只发布 ``EH2_WB_SRC_DIV`` 和 ``EH2_WB_SRC_NB_LOAD``。cosim scoreboard
也明确丢弃 source 为 regular 的 probe item。

接口关系：

* 被调用：trace monitor、DUT probe monitor 和 cosim scoreboard async path。
* 调用：``ap.write``、``trace_fifo.get``、``dut_probe_fifo.get``。
* 共享状态：``wb_source``、``wb_tag``、``wb_seq``。

§11  参考资料
------------------------------------------------------------------------------------------------------------------------

* :ref:`agent_trace` — verification architecture 中的 Trace agent 说明。
* :ref:`appendix_b_uvm_cosim_agent` — cosim agent 与 scoreboard 源码字典。
* :doc:`../05_verification_arch/cosim_scoreboard` — cosim scoreboard 数据流标杆章节。
* :ref:`adr-0004` — RTL RVFI-equivalent trace。
* :ref:`adr-0016` — multi-hart cosim 背景。
* :ref:`adr-0018` — strict ``wb_tag`` matching。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_intf.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/eh2_dut_probe_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv``。

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

§13  v2-17 源码片段闭环
--------------------------------------------------------------------------------

本节补齐 ``eh2_trace_agent_pkg.sv`` 的完整 package 源码片段。trace agent 的关键
monitor 与 seq item 已在前文章节逐段解释；package 片段用于固定编译入口和 include
顺序。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv
   :language: systemverilog
   :lines: 1-21
   :linenos:
   :caption: dv/uvm/core_eh2/common/trace_agent/eh2_trace_agent_pkg.sv:L1-L21

逐段精读：L7-L11 建立 package、UVM 和 AXI4 依赖；L13-L20 依次 include trace item、
trace monitor、DUT probe monitor、memory monitor 和 agent wrapper。DUT probe monitor
依赖 probe interface 字段，memory monitor 依赖 AXI4 item，因此 package 必须先导入
``axi4_agent_pkg``。
