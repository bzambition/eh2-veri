.. _appendix_b_uvm_jtag_agent:
.. _appendix_b_uvm/jtag_agent:

JTAG Agent 源码字典
===================

:status: draft
:source: dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/common/jtag_agent/` 下的 JTAG UVM agent。该 agent 通过
``eh2_jtag_intf`` 驱动 ``tck``、``tms``、``tdi`` 和 ``trst_n``，读取 ``tdo``，并在
driver 内实现 JTAG TAP state machine、IR scan、41-bit DMI DR scan、DMI read/write
以及 busy retry。当前目录没有 ``eh2_jtag_monitor.sv``，top-level ``eh2_jtag_agent``
也没有 monitor 成员，因此本章不写 JTAG monitor 或 DMI transaction analysis port。

本章覆盖 7 个 agent 源文件，以及 env、tb、test 中的调用点：

* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_test_lib.sv`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

JTAG agent 的主路径是 test/debug sequence 调 ``eh2_jtag_seq::send_write`` 或
``send_read``，该 sequence 在 ``eh2_jtag_sequencer`` 上启动，driver 收到
``eh2_jtag_seq_item`` 后把 DMI request 转为 JTAG IR/DR scan。tb 顶层把
``jtag_intf`` 连到 DUT JTAG pin，并通过 ``uvm_config_db`` 发布 ``jtag_vif``。

::

   core_eh2_test_lib.sv / core_eh2_seq_lib.sv
      |
      +-- eh2_jtag_seq::send_write()/send_read()
            |
            +-- eh2_jtag_sequencer
                  |
                  +-- eh2_jtag_driver
                        |
                        +-- write_ir(IR_DMI_ACCESS)
                        +-- shift_dr_41({addr,data,op}, response)
                              |
                              +-- eh2_jtag_intf -> DUT JTAG pins

接口关系：

* 被调用：``core_eh2_env`` 创建 active ``jtag_agent``，并把 ``jtag_agent.sequencer`` 接到
  ``vseqr.jtag_seqr``。
* 调用：driver 调 ``goto_state``、``write_ir``、``shift_dr_41``、``dmi_read``、
  ``dmi_write``、``reset_dmi``。
* 共享状态：virtual ``eh2_jtag_intf``、``jtag_vif`` config_db 条目、
  ``eh2_jtag_seq_item`` 的 ``op``、``addr``、``wdata``、``rdata``、``resp``。

§2  ``eh2_jtag_agent_pkg.sv`` — package 汇入顺序
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_agent_pkg`` 汇入 JTAG transaction、driver、sequencer、sequence 和
top-level agent。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv:L4-L15``）：

.. code-block:: systemverilog

   package eh2_jtag_agent_pkg;

     `include "uvm_macros.svh"
     import uvm_pkg::*;

     `include "eh2_jtag_seq_item.sv"
     `include "eh2_jtag_driver.sv"
     `include "eh2_jtag_sequencer.sv"
     `include "eh2_jtag_seq.sv"
     `include "eh2_jtag_agent.sv"

   endpackage

逐段解释：

* 第 4 行：声明 ``eh2_jtag_agent_pkg``。
* 第 6~7 行：引入 UVM 宏和 ``uvm_pkg``。
* 第 9 行：先 include ``eh2_jtag_seq_item.sv``，因为 driver、sequencer 和 sequence 都依赖该类型。
* 第 10~13 行：随后 include driver、sequencer、sequence 和 agent。agent 内部声明
  driver/sequencer 类型，因此放在后面。
* 第 15 行：结束 package；该文件没有运行期状态。

接口关系：

* 被调用：``core_eh2_env_pkg.sv``、``core_eh2_test_pkg.sv`` 和 test 文件 import 该 package。
* 调用：SystemVerilog include。
* 共享状态：无运行期共享状态。

§3  ``eh2_jtag_intf.sv`` — JTAG pin interface
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_intf`` 定义连接 DUT 的 JTAG pin 信号，并用 clocking block 规定 driver
输出与 monitor 输入方向。

§3.1  信号与默认值
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv:L6-L24``）：

.. code-block:: systemverilog

   interface eh2_jtag_intf(
     input logic clk,
     input logic rst_n
   );

     // JTAG signals
     logic       tck;
     logic       tms;
     logic       tdi;
     logic       trst_n;
     logic       tdo;

     // Default values (trst_n release is controlled by the JTAG driver)
     initial begin
       tck    = 0;
       tms    = 1;
       tdi    = 0;
       trst_n = 0;
     end

逐段解释：

* 第 6~9 行：interface 接收 ``clk`` 和 ``rst_n``，JTAG driver 用 ``clk`` 作为产生 TCK
  半周期的时间基准。
* 第 11~16 行：定义 ``tck``、``tms``、``tdi``、``trst_n`` 和 ``tdo`` 5 个 JTAG pin
  信号。
* 第 18~24 行：initial block 设置 ``tck=0``、``tms=1``、``tdi=0``、``trst_n=0``。
  注释说明 ``trst_n`` 释放由 JTAG driver 控制。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 实例化 ``jtag_intf``。
* 调用：无函数调用。
* 共享状态：这些 pin 信号被 driver 写入或读取，再由 tb 顶层连接到 DUT。

§3.2  clocking block
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv:L26-L44``）：

.. code-block:: systemverilog

     // Clocking block for driver
     clocking driver_cb @(posedge clk);
       output tck;
       output tms;
       output tdi;
       output trst_n;
       input  tdo;
     endclocking

     // Clocking block for monitor
     clocking monitor_cb @(posedge clk);
       input tck;
       input tms;
       input tdi;
       input trst_n;
       input tdo;
     endclocking

   endinterface

逐段解释：

* 第 26~33 行：``driver_cb`` 在 ``posedge clk`` 边界输出 ``tck``、``tms``、``tdi``、
  ``trst_n``，并输入 ``tdo``。driver 的 ``tck_cycle`` 使用该 clocking block。
* 第 35~42 行：``monitor_cb`` 以同一时钟边界观察全部 JTAG pin。当前 agent 目录没有 monitor
  component 使用该 block。
* 第 44 行：结束 interface。

接口关系：

* 被调用：``eh2_jtag_driver`` 使用 ``vif.driver_cb``。
* 调用：SystemVerilog clocking block。
* 共享状态：``clk`` 是 driver 产生 TCK low/high half 的时间基准。

§4  ``eh2_jtag_seq_item.sv`` — DMI transaction 对象
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_seq_item`` 封装一笔 JTAG/DMI transaction，包括读写方向、DMI 地址、写数据、
读数据和响应码。

§4.1  op、DMI 地址枚举与字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv:L6-L35``）：

.. code-block:: systemverilog

   class eh2_jtag_seq_item extends uvm_sequence_item;

     // Transaction type
     typedef enum bit {
       JTAG_READ  = 1'b0,
       JTAG_WRITE = 1'b1
     } jtag_op_e;

     // DMI register addresses (from Debug Spec)
     typedef enum bit [6:0] {
       DMI_DATA0    = 7'h04,
       DMI_DATA1    = 7'h05,
       DMI_DMCONTROL = 7'h10,
       DMI_DMSTATUS  = 7'h11,
       DMI_HAWINDOW  = 7'h15,
       DMI_ABSTRACTCS = 7'h16,
       DMI_COMMAND   = 7'h17,
       DMI_SBCS      = 7'h38,
       DMI_SBADDRESS0 = 7'h39,
       DMI_SBDATA0   = 7'h3C,
       DMI_SBDATA1   = 7'h3D,
       DMI_HALTSUM   = 7'h40
     } dmi_reg_e;

     // Transaction fields
     rand jtag_op_e   op;
     rand bit [6:0]   addr;
     rand bit [31:0]  wdata;
     bit [31:0]       rdata;
     bit [1:0]        resp;

逐段解释：

* 第 6 行：该类继承 ``uvm_sequence_item``，可以由 UVM sequence 发送给 driver。
* 第 9~12 行：``jtag_op_e`` 只包含 ``JTAG_READ`` 和 ``JTAG_WRITE`` 两种操作。
* 第 15~28 行：``dmi_reg_e`` 列出当前测试代码使用的 DMI register address，例如
  ``DMI_DMCONTROL``、``DMI_COMMAND``、``DMI_SBCS`` 和 ``DMI_SBDATA0``。
* 第 31~33 行：``op``、``addr`` 和 ``wdata`` 是随机字段；静态 sequence helper 会显式赋值。
* 第 34~35 行：``rdata`` 和 ``resp`` 由 driver 在 DMI read/write 后写回 transaction 对象。

接口关系：

* 被调用：``eh2_jtag_seq`` 创建该对象，``eh2_jtag_driver`` 消费并回填字段。
* 调用：无。
* 共享状态：transaction 字段在 sequence 与 driver 之间传递。

§4.2  UVM field 与字符串化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv:L37-L56``）：

.. code-block:: systemverilog

     `uvm_object_utils_begin(eh2_jtag_seq_item)
       `uvm_field_enum(jtag_op_e, op, UVM_ALL_ON)
       `uvm_field_int(addr, UVM_ALL_ON)
       `uvm_field_int(wdata, UVM_ALL_ON)
       `uvm_field_int(rdata, UVM_ALL_ON)
       `uvm_field_int(resp, UVM_ALL_ON)
     `uvm_object_utils_end

     function new(string name = "eh2_jtag_seq_item");
       super.new(name);
     endfunction

     function string convert2string();
       if (op == JTAG_READ)
         return $sformatf("READ  addr=0x%02x rdata=0x%08x", addr, rdata);
       else
         return $sformatf("WRITE addr=0x%02x wdata=0x%08x", addr, wdata);
     endfunction

   endclass

逐段解释：

* 第 37~43 行：UVM field macro 注册 ``op``、``addr``、``wdata``、``rdata`` 和 ``resp``。
* 第 45~47 行：constructor 只调用父类 constructor，默认对象名为 ``eh2_jtag_seq_item``。
* 第 49~54 行：``convert2string`` 按 ``op`` 选择 read 或 write 字符串；read 显示
  ``rdata``，write 显示 ``wdata``。
* 第 56 行：结束 class。

接口关系：

* 被调用：driver 在 log 中调用 ``txn.convert2string()``。
* 调用：``$sformatf``。
* 共享状态：只读取当前 transaction 字段。

§5  ``eh2_jtag_driver.sv`` — TAP 与 DMI 驱动器
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_driver`` 把 ``eh2_jtag_seq_item`` 转换成 JTAG TAP state transition 和
DMI DR scan。它包含初始化、TCK 生成、TAP 状态维护、IR scan、DR scan、DTMCS reset、
DMI read/write busy retry。

§5.1  常量、TAP state 与 DMI 编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L17-L68``）：

.. code-block:: systemverilog

   class eh2_jtag_driver extends uvm_driver #(eh2_jtag_seq_item);

     `uvm_component_utils(eh2_jtag_driver)

     virtual eh2_jtag_intf vif;

     // JTAG TAP states
     typedef enum {
       TEST_LOGIC_RESET,
       RUN_TEST_IDLE,
       SELECT_DR_SCAN,
       CAPTURE_DR,
       SHIFT_DR,
       EXIT1_DR,
       PAUSE_DR,
       EXIT2_DR,
       UPDATE_DR,
       SELECT_IR_SCAN,
       CAPTURE_IR,
       SHIFT_IR,
       EXIT1_IR,
       PAUSE_IR,
       EXIT2_IR,
       UPDATE_IR
     } tap_state_e;

逐段解释：

* 第 17 行：driver 参数化为 ``uvm_driver #(eh2_jtag_seq_item)``。
* 第 19 行：注册 UVM component 类型。
* 第 21 行：``vif`` 保存 virtual ``eh2_jtag_intf``。
* 第 24~41 行：``tap_state_e`` 枚举列出 16 个 TAP 状态，供 ``tap_state`` 和
  ``update_tap_state`` 使用。

接口关系：

* 被调用：``eh2_jtag_agent`` 在 active 模式创建 driver。
* 调用：无。
* 共享状态：``vif`` 和 ``tap_state`` 是 driver 内部核心状态。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L43-L68``）：

.. code-block:: systemverilog

     tap_state_e tap_state;

     // DMI operation codes
     localparam DMI_OP_NOP   = 2'b00;
     localparam DMI_OP_READ  = 2'b01;
     localparam DMI_OP_WRITE = 2'b10;

     // DMI response codes
     localparam DMI_RESP_OK   = 2'b00;
     localparam DMI_RESP_FAIL = 2'b10;
     localparam DMI_RESP_BUSY = 2'b11;

     // DTMCS register bits
     localparam DTMCS_DMI_RESET = 16;  // dmireset bit

     // Busy retry configuration
     localparam MAX_BUSY_RETRIES = 5;
     localparam BUSY_RETRY_DELAY = 20;  // Clock cycles between retries

     // DMI register width
     localparam DMI_WIDTH = 41;

     // IR values for RISC-V Debug Spec
     localparam IR_DMI_ACCESS = 5'h11;  // DMI access register
     localparam IR_DTMCSR     = 5'h10;  // DTM Control and Status

逐段解释：

* 第 43 行：``tap_state`` 保存 driver 认为当前 TAP 所在状态。
* 第 46~48 行：DMI op 编码包括 NOP、READ、WRITE。
* 第 51~53 行：DMI response 编码包括 OK、FAIL、BUSY；read/write retry loop 只显式处理
  BUSY 和 FAIL。
* 第 56 行：``DTMCS_DMI_RESET`` 是 DTMCS 中 ``dmireset`` bit 位置。
* 第 59~60 行：busy retry 最多 5 次，每次 retry 之间等待 20 个 ``vif.clk`` 周期。
* 第 63 行：DMI DR scan 宽度是 41 bit。
* 第 66~68 行：IR value 包括 DMI access register 和 DTM Control and Status。

接口关系：

* 被调用：``dmi_read``、``dmi_write``、``write_dtmcs``、``write_ir`` 和 ``shift_dr_41`` 使用这些常量。
* 调用：无。
* 共享状态：localparam 是 driver 内部常量。

§5.2  connect phase 与 run phase 初始化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L69-L106``）：

.. code-block:: systemverilog

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (!uvm_config_db#(virtual eh2_jtag_intf)::get(this, "", "jtag_vif", vif)) begin
         `uvm_fatal("jtag_driver", "Could not get JTAG virtual interface")
       end
     endfunction

     task run_phase(uvm_phase phase);
       // Initialize JTAG signals
       vif.driver_cb.tck    <= 1'b0;
       vif.driver_cb.tms    <= 1'b1;
       vif.driver_cb.tdi    <= 1'b0;
       vif.driver_cb.trst_n <= 1'b0;

       // Hold reset for 10 clock cycles
       repeat (10) @(posedge vif.clk);
       vif.driver_cb.trst_n <= 1'b1;

逐段解释：

* 第 69~71 行：constructor 只调用父类 constructor。
* 第 73~78 行：connect phase 从 config_db 获取 ``jtag_vif``；失败时触发 ``uvm_fatal``。
* 第 80~85 行：run phase 开始时初始化 JTAG pin，保持 ``trst_n`` 为 0。
* 第 87~89 行：driver 等待 10 个 ``vif.clk`` 周期后释放 ``trst_n``。

接口关系：

* 被调用：UVM connect/run phase 调度。
* 调用：``uvm_config_db::get``、``uvm_fatal``、clock wait。
* 共享状态：``jtag_vif`` 和 ``vif.driver_cb`` pin。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L89-L106``）：

.. code-block:: systemverilog

       vif.driver_cb.trst_n <= 1'b1;
       repeat (5) @(posedge vif.clk);

       // Navigate to known state
       goto_state(TEST_LOGIC_RESET);
       goto_state(RUN_TEST_IDLE);

       // Set IR to DMI access (always use DMI for RISC-V debug)
       write_ir(IR_DMI_ACCESS);

       // Process transactions
       forever begin
         eh2_jtag_seq_item txn;
         seq_item_port.get_next_item(txn);
         drive_jtag_transaction(txn);
         seq_item_port.item_done();
       end
     endtask

逐段解释：

* 第 89~90 行：释放 ``trst_n`` 后再等待 5 个 ``vif.clk`` 周期。
* 第 92~94 行：driver 调 ``goto_state`` 进入 ``TEST_LOGIC_RESET``，再进入
  ``RUN_TEST_IDLE``。
* 第 96~97 行：driver 调 ``write_ir(IR_DMI_ACCESS)``，把 IR 设置到 DMI access register。
* 第 99~105 行：forever 循环从 sequencer 取 item，调用 ``drive_jtag_transaction``，再
  ``item_done``。
* 第 106 行：结束 run phase。

接口关系：

* 被调用：driver run phase。
* 调用：``goto_state``、``write_ir``、``seq_item_port.get_next_item``、
  ``drive_jtag_transaction``、``item_done``。
* 共享状态：TAP state、IR setting 和 UVM item 握手状态。

§5.3  ``drive_jtag_transaction()`` — 读写分派
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L108-L123``）：

.. code-block:: systemverilog

     // Drive a JTAG/DMI transaction
     task drive_jtag_transaction(eh2_jtag_seq_item txn);
       `uvm_info("jtag_driver", $sformatf("Driving: %s", txn.convert2string()), UVM_HIGH)

       case (txn.op)
         eh2_jtag_seq_item::JTAG_READ: begin
           dmi_read(txn.addr, txn.rdata, txn.resp);
         end
         eh2_jtag_seq_item::JTAG_WRITE: begin
           dmi_write(txn.addr, txn.wdata, txn.resp);
         end
         default: begin
           `uvm_error("jtag_driver", $sformatf("Unknown JTAG op: %0d", txn.op))
         end
       endcase
     endtask

逐段解释：

* 第 108~110 行：driver 打印 transaction 字符串；字符串来自 ``txn.convert2string()``。
* 第 112~115 行：``JTAG_READ`` 分支调用 ``dmi_read``，并把结果写回 ``txn.rdata`` 和
  ``txn.resp``。
* 第 116~118 行：``JTAG_WRITE`` 分支调用 ``dmi_write``，并把 response 写回 ``txn.resp``。
* 第 119~121 行：未知 ``op`` 触发 ``uvm_error``。
* 第 122~123 行：结束 case 和 task。

接口关系：

* 被调用：``run_phase`` 每收到一个 item 调一次。
* 调用：``dmi_read``、``dmi_write``、``convert2string``、UVM log macro。
* 共享状态：读写 transaction 字段。

§5.4  ``tck_cycle()`` 与 ``tck_nav()`` — TCK 基本动作
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L129-L146``）：

.. code-block:: systemverilog

     // Generate one TCK cycle (low half then high half, each half = 1 clk).
     // TDO is sampled at the rising edge of TCK (second posedge clk).
     task tck_cycle(bit tms_val, bit tdi_val, output bit tdo_val);
       vif.driver_cb.tms <= tms_val;
       vif.driver_cb.tdi <= tdi_val;
       @(posedge vif.clk);  // TCK low half
       vif.driver_cb.tck <= 1'b1;
       @(posedge vif.clk);  // TCK high half - TDO sampled here
       tdo_val = vif.driver_cb.tdo;
       vif.driver_cb.tck <= 1'b0;
     endtask

     // Wrapper for tck_cycle when TDO is not needed (navigation only)
     task tck_nav(bit tms_val);
       bit unused_tdo;
       tck_cycle(tms_val, 1'b0, unused_tdo);
       update_tap_state(tms_val);
     endtask

逐段解释：

* 第 129~131 行：注释说明一个 TCK cycle 由 low half 和 high half 组成，每个 half 等待
  一个 ``vif.clk``。
* 第 132~138 行：``tck_cycle`` 先驱动 ``tms`` 和 ``tdi``，等待 low half，拉高 ``tck``，
  再等待 high half 并采样 ``tdo``。
* 第 138~139 行：采样后把 ``tck`` 拉回 0，结束一个 TCK cycle。
* 第 142~146 行：``tck_nav`` 是导航包装器，不关心 TDO；调用 ``tck_cycle`` 后用
  ``update_tap_state`` 更新 driver 内部 ``tap_state``。

接口关系：

* 被调用：``goto_state``、``write_ir``、``shift_dr_41`` 和 ``write_dtmcs``。
* 调用：``update_tap_state`` 和 clock wait。
* 共享状态：写 ``vif.driver_cb`` JTAG pin，读 ``tdo``，更新 ``tap_state``。

§5.5  ``goto_state()`` — 从 reset 状态导航到目标 TAP state
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L152-L183``）：

.. code-block:: systemverilog

     // Navigate TAP state machine to target state.
     // Strategy: go to TEST_LOGIC_RESET first (hold TMS=1 for up to 5 cycles),
     // then navigate from there to the target using known paths.
     task goto_state(tap_state_e target);
       if (tap_state == target) return;

       // Go to TEST_LOGIC_RESET: hold TMS=1 for up to 5 cycles
       while (tap_state != TEST_LOGIC_RESET) begin
         tck_nav(1);
       end

       // Navigate from TEST_LOGIC_RESET to target
       case (target)
         TEST_LOGIC_RESET: ; // Already there
         RUN_TEST_IDLE: begin
           tck_nav(0);  // RTI
         end
         SELECT_DR_SCAN: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR
         end
         CAPTURE_DR: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR
           tck_nav(0);  // CAPTURE_DR
         end
         SHIFT_DR: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR

逐段解释：

* 第 152~155 行：``goto_state`` 的策略是先回到 ``TEST_LOGIC_RESET``，再按已知路径进入目标状态。
* 第 156 行：如果当前 ``tap_state`` 已经等于目标，直接返回。
* 第 158~161 行：只要当前状态不是 ``TEST_LOGIC_RESET``，就持续以 ``TMS=1`` 调
  ``tck_nav``。
* 第 164~183 行：case 中列出从 reset 到 ``RUN_TEST_IDLE``、``SELECT_DR_SCAN``、
  ``CAPTURE_DR`` 和 ``SHIFT_DR`` 的路径。

接口关系：

* 被调用：run phase、``write_ir``、``shift_dr_41``、``write_dtmcs``。
* 调用：``tck_nav``。
* 共享状态：读写 ``tap_state``，间接驱动 JTAG pin。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L205-L263``）：

.. code-block:: systemverilog

         UPDATE_DR: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR
           tck_nav(0);  // CAPTURE_DR
           tck_nav(1);  // EXIT1_DR
           tck_nav(1);  // UPDATE_DR
         end
         SELECT_IR_SCAN: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR
           tck_nav(1);  // SELECT_IR
         end
         CAPTURE_IR: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR
           tck_nav(1);  // SELECT_IR
           tck_nav(0);  // CAPTURE_IR
         end
         SHIFT_IR: begin
           tck_nav(0);  // RTI
           tck_nav(1);  // SELECT_DR
           tck_nav(1);  // SELECT_IR
           tck_nav(0);  // CAPTURE_IR
           tck_nav(0);  // SHIFT_IR
         end

逐段解释：

* 第 205~211 行：``UPDATE_DR`` 路径从 RTI 进入 DR scan，再经 ``EXIT1_DR`` 到
  ``UPDATE_DR``。
* 第 212~216 行：``SELECT_IR_SCAN`` 路径从 RTI 经 ``SELECT_DR`` 到 ``SELECT_IR``。
* 第 217~222 行：``CAPTURE_IR`` 路径在 ``SELECT_IR`` 后以 ``TMS=0`` 进入 capture。
* 第 223~229 行：``SHIFT_IR`` 路径在 ``CAPTURE_IR`` 后再以 ``TMS=0`` 进入 shift。
* 第 262~263 行：源码在完整 case 后结束 ``goto_state``；中间其它 IR 状态路径按同一模式展开。

接口关系：

* 被调用：``write_ir`` 需要 ``SHIFT_IR``，其它路径可由 driver 内部导航使用。
* 调用：``tck_nav``。
* 共享状态：``tap_state`` 和 JTAG pin。

§5.6  ``update_tap_state()`` — TAP state 软件镜像
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L265-L286``）：

.. code-block:: systemverilog

     // Update TAP state based on TMS value (mirrors hardware TAP FSM)
     task update_tap_state(bit tms);
       case (tap_state)
         TEST_LOGIC_RESET: tap_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
         RUN_TEST_IDLE:    tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
         SELECT_DR_SCAN:   tap_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
         CAPTURE_DR:       tap_state = tms ? EXIT1_DR         : SHIFT_DR;
         SHIFT_DR:         tap_state = tms ? EXIT1_DR         : SHIFT_DR;
         EXIT1_DR:         tap_state = tms ? UPDATE_DR        : PAUSE_DR;
         PAUSE_DR:         tap_state = tms ? EXIT2_DR         : PAUSE_DR;
         EXIT2_DR:         tap_state = tms ? UPDATE_DR        : SHIFT_DR;
         UPDATE_DR:        tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
         SELECT_IR_SCAN:   tap_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
         CAPTURE_IR:       tap_state = tms ? EXIT1_IR         : SHIFT_IR;
         SHIFT_IR:         tap_state = tms ? EXIT1_IR         : SHIFT_IR;
         EXIT1_IR:         tap_state = tms ? UPDATE_IR        : PAUSE_IR;
         PAUSE_IR:         tap_state = tms ? EXIT2_IR         : PAUSE_IR;
         EXIT2_IR:         tap_state = tms ? UPDATE_IR        : SHIFT_IR;
         UPDATE_IR:        tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
         default:          tap_state = TEST_LOGIC_RESET;
       endcase
     endtask

逐段解释：

* 第 265~267 行：task 以当前 ``tap_state`` 和输入 ``tms`` 为条件更新状态。
* 第 268~276 行：DR 路径覆盖 reset、idle、select/capture/shift/exit/pause/update 等状态。
* 第 277~283 行：IR 路径覆盖 select/capture/shift/exit/pause/update 等状态。
* 第 284 行：未匹配状态回到 ``TEST_LOGIC_RESET``。
* 第 285~286 行：结束 case 和 task。

接口关系：

* 被调用：``tck_nav``、``write_ir``、``shift_dr_41``、``write_dtmcs``。
* 调用：无。
* 共享状态：写 ``tap_state``。

§5.7  ``write_ir()`` — 写 5-bit instruction register
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L292-L318``）：

.. code-block:: systemverilog

     task write_ir(bit [4:0] ir_value);
       bit unused_tdo;

       // Navigate: RTI -> SELECT_DR -> SELECT_IR -> CAPTURE_IR -> SHIFT_IR
       goto_state(RUN_TEST_IDLE);
       tck_nav(1);  // SELECT_DR_SCAN
       tck_nav(1);  // SELECT_IR_SCAN
       tck_nav(0);  // CAPTURE_IR
       tck_nav(0);  // SHIFT_IR

       // Shift 5 bits of IR value (LSB first)
       for (int i = 0; i < 5; i++) begin
         bit is_last = (i == 4);
         tck_cycle(is_last, ir_value[i], unused_tdo);  // TMS=1 on last bit to exit
         update_tap_state(is_last);
       end
       // Now in EXIT1_IR

       // EXIT1_IR -> UPDATE_IR
       tck_nav(1);  // UPDATE_IR

       // UPDATE_IR -> RUN_TEST_IDLE
       tck_nav(0);  // RUN_TEST_IDLE

       // Small delay for IR update
       repeat (2) @(posedge vif.clk);
     endtask

逐段解释：

* 第 292~300 行：``write_ir`` 先回到 ``RUN_TEST_IDLE``，再通过 TMS 序列进入
  ``SHIFT_IR``。
* 第 302~307 行：for loop 以 LSB first 方式移入 5 bit IR；最后一 bit 让 ``TMS=1``，
  使 TAP 退出 shift。
* 第 310~314 行：从 ``EXIT1_IR`` 进入 ``UPDATE_IR``，再回到 ``RUN_TEST_IDLE``。
* 第 316~318 行：IR 更新后等待 2 个 ``vif.clk`` 周期。

接口关系：

* 被调用：run phase 初始化、``write_dtmcs``、``reset_dmi`` 间接调用。
* 调用：``goto_state``、``tck_nav``、``tck_cycle``、``update_tap_state``。
* 共享状态：驱动 JTAG IR scan，更新 ``tap_state``。

§5.8  ``shift_dr_41()`` — DMI DR scan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L324-L357``）：

.. code-block:: systemverilog

     // Shift 41 bits through DR. Returns the captured value.
     // input_data is shifted in (LSB first).
     // Returns the value captured from TDO (LSB first).
     task shift_dr_41(bit [DMI_WIDTH-1:0] input_data,
                      output bit [DMI_WIDTH-1:0] output_data);
       bit [DMI_WIDTH-1:0] captured;
       bit tdo_val;

       // Navigate: RTI -> SELECT_DR -> CAPTURE_DR -> SHIFT_DR
       goto_state(RUN_TEST_IDLE);
       tck_nav(1);  // SELECT_DR_SCAN
       tck_nav(0);  // CAPTURE_DR
       tck_nav(0);  // SHIFT_DR

       // Shift 41 bits, LSB first
       for (int i = 0; i < DMI_WIDTH; i++) begin
         bit is_last = (i == DMI_WIDTH - 1);

逐段解释：

* 第 324~328 行：task 说明 input/output 都是 41 bit DMI width，输入 LSB first 移入，输出从
  TDO LSB first 捕获。
* 第 329~330 行：``captured`` 保存 TDO 采样结果，``tdo_val`` 保存单周期采样 bit。
* 第 332~336 行：driver 从 idle 导航到 ``SHIFT_DR``。
* 第 338~340 行：for loop 遍历 ``DMI_WIDTH`` 位，最后一位用 ``is_last`` 控制退出 shift。

接口关系：

* 被调用：``dmi_read``、``dmi_write``。
* 调用：``goto_state`` 和 ``tck_nav``。
* 共享状态：驱动 DR scan，捕获 TDO。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L342-L357``）：

.. code-block:: systemverilog

         // Drive TDI with input data bit, TMS=1 on last bit to exit
         tck_cycle(is_last, input_data[i], tdo_val);
         captured[i] = tdo_val;

         update_tap_state(is_last);
       end
       // Now in EXIT1_DR

       // EXIT1_DR -> UPDATE_DR
       tck_nav(1);  // UPDATE_DR

       // UPDATE_DR -> RUN_TEST_IDLE
       tck_nav(0);  // RUN_TEST_IDLE

       output_data = captured;
     endtask

逐段解释：

* 第 342~344 行：每一位调用 ``tck_cycle``，TDI 来自 ``input_data[i]``，TDO 写入
  ``captured[i]``。
* 第 346 行：每次 TCK 后用 ``update_tap_state`` 更新软件 TAP state。
* 第 350~354 行：scan 完成后从 ``EXIT1_DR`` 进入 ``UPDATE_DR``，再回到
  ``RUN_TEST_IDLE``。
* 第 356~357 行：把捕获到的 41 bit 值赋给 ``output_data``，结束 task。

接口关系：

* 被调用：``dmi_read``、``dmi_write``。
* 调用：``tck_cycle``、``update_tap_state``、``tck_nav``。
* 共享状态：JTAG pin、``tap_state`` 和 ``output_data``。

§5.9  ``write_dtmcs()`` 与 ``reset_dmi()`` — DMI busy 恢复
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L367-L400``）：

.. code-block:: systemverilog

     // Write to DTMCS register (for dmireset, etc.)
     task write_dtmcs(bit [31:0] wdata);
       bit [DMI_WIDTH-1:0] dmi_resp;
       bit unused_tdo;

       // Switch IR to DTMCS
       write_ir(IR_DTMCSR);

       // Shift 32 bits of DTMCS data (not 41 - DTMCS is 32-bit DR)
       goto_state(RUN_TEST_IDLE);
       tck_nav(1);  // SELECT_DR_SCAN
       tck_nav(0);  // CAPTURE_DR
       tck_nav(0);  // SHIFT_DR

       for (int i = 0; i < 32; i++) begin
         bit is_last = (i == 31);
         tck_cycle(is_last, wdata[i], unused_tdo);
         update_tap_state(is_last);
       end

逐段解释：

* 第 367~370 行：``write_dtmcs`` 写 32-bit DTMCS DR，声明 ``dmi_resp`` 和 ``unused_tdo``；
  其中 ``dmi_resp`` 在当前 task 中未被后续读取。
* 第 372~373 行：先写 IR 到 ``IR_DTMCSR``。
* 第 375~379 行：从 idle 进入 DR shift。
* 第 381~385 行：以 LSB first 方式移入 32 bit ``wdata``，最后一位退出 shift，并更新 TAP state。

接口关系：

* 被调用：``reset_dmi``。
* 调用：``write_ir``、``goto_state``、``tck_nav``、``tck_cycle``、``update_tap_state``。
* 共享状态：JTAG pin 和 ``tap_state``。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L386-L400``）：

.. code-block:: systemverilog

       tck_nav(1);  // UPDATE_DR
       tck_nav(0);  // RUN_TEST_IDLE

       repeat (2) @(posedge vif.clk);

       // Switch IR back to DMI access
       write_ir(IR_DMI_ACCESS);
     endtask

     // Reset DMI state (clear busy)
     task reset_dmi();
       `uvm_info("jtag_driver", "Resetting DMI (dmireset)", UVM_LOW)
       write_dtmcs(1 << DTMCS_DMI_RESET);
       repeat (5) @(posedge vif.clk);
     endtask

逐段解释：

* 第 386~387 行：DTMCS shift 完成后进入 ``UPDATE_DR``，再回到 ``RUN_TEST_IDLE``。
* 第 389 行：等待 2 个 ``vif.clk`` 周期。
* 第 391~392 行：把 IR 切回 ``IR_DMI_ACCESS``，使后续 DR scan 回到 DMI access register。
* 第 396~400 行：``reset_dmi`` 打印 log，调用 ``write_dtmcs(1 << DTMCS_DMI_RESET)``，
  然后等待 5 个 ``vif.clk`` 周期。

接口关系：

* 被调用：``dmi_read`` 和 ``dmi_write`` 在 BUSY retry 中调用 ``reset_dmi``。
* 调用：``tck_nav``、``write_ir``、``write_dtmcs``、UVM log macro。
* 共享状态：IR selection、TAP state 和 JTAG pin。

§5.10  ``dmi_read()`` — read request 与 response scan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L406-L434``）：

.. code-block:: systemverilog

     // DMI Read: send read request, then read response on next scan
     // Handles Busy responses with retry and DTMCS error recovery
     task dmi_read(input bit [6:0] addr,
                   output bit [31:0] rdata,
                   output bit [1:0] resp);
       bit [DMI_WIDTH-1:0] dmi_req;
       bit [DMI_WIDTH-1:0] dmi_resp;
       int retry_count;

       retry_count = 0;
       resp = DMI_RESP_BUSY;

       while (resp == DMI_RESP_BUSY && retry_count < MAX_BUSY_RETRIES) begin
         // Build DMI read request: addr[40:34] | data=0[33:2] | op=READ[1:0]
         dmi_req = {addr, 32'b0, DMI_OP_READ};

         // First DR scan: send the read request (response is for previous op)
         shift_dr_41(dmi_req, dmi_resp);

         // Wait for DMI to process (DTM needs time)
         repeat (5) @(posedge vif.clk);

         // Second DR scan: send NOP, capture the read response
         shift_dr_41({7'b0, 32'b0, DMI_OP_NOP}, dmi_resp);

         // Extract response
         rdata = dmi_resp[33:2];
         resp  = dmi_resp[1:0];

逐段解释：

* 第 406~410 行：``dmi_read`` 输入 7-bit 地址，输出 32-bit ``rdata`` 和 2-bit ``resp``。
* 第 411~416 行：声明 request/response shift register 和 retry counter，并把初始 response
  设为 BUSY。
* 第 418~423 行：retry loop 内构造 ``{addr, 32'b0, DMI_OP_READ}``，第一次 41-bit DR scan
  发送 read request。
* 第 425~429 行：等待 5 个 ``vif.clk`` 后，第二次 DR scan 发送 NOP 并捕获 read response。
* 第 431~434 行：从 response 中提取 ``rdata=dmi_resp[33:2]`` 和 ``resp=dmi_resp[1:0]``。

接口关系：

* 被调用：``drive_jtag_transaction`` 的 read 分支。
* 调用：``shift_dr_41`` 和 clock wait。
* 共享状态：JTAG DR scan 输出、``rdata``、``resp``。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L435-L462``）：

.. code-block:: systemverilog

         if (resp == DMI_RESP_BUSY) begin
           retry_count++;
           `uvm_warning("jtag_driver", $sformatf(
             "DMI READ Busy (addr=0x%02x), retry %0d/%0d",
             addr, retry_count, MAX_BUSY_RETRIES))

           // Reset DMI state to clear busy condition
           reset_dmi();

           // Delay before retry
           repeat (BUSY_RETRY_DELAY) @(posedge vif.clk);
         end
       end

       if (resp == DMI_RESP_BUSY) begin
         `uvm_error("jtag_driver", $sformatf(
           "DMI READ still Busy after %0d retries (addr=0x%02x)",
           MAX_BUSY_RETRIES, addr))
       end

逐段解释：

* 第 435~439 行：如果 response 是 BUSY，retry counter 加 1，并打印 warning。
* 第 441~445 行：BUSY 时调用 ``reset_dmi`` 清除 DMI 状态，再等待 ``BUSY_RETRY_DELAY``
  个时钟周期。
* 第 447 行：结束 retry loop。
* 第 449~453 行：如果退出 loop 后仍是 BUSY，打印 ``uvm_error``。

接口关系：

* 被调用：``dmi_read`` retry loop。
* 调用：``reset_dmi``、UVM log macro、clock wait。
* 共享状态：``retry_count``、``resp``、TAP/DMI 状态。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L455-L462``）：

.. code-block:: systemverilog

       if (resp == DMI_RESP_FAIL) begin
         `uvm_warning("jtag_driver", $sformatf(
           "DMI READ Fail response (addr=0x%02x)", addr))
       end

       `uvm_info("jtag_driver", $sformatf("DMI READ: addr=0x%02x data=0x%08x resp=%0d",
         addr, rdata, resp), UVM_HIGH)
     endtask

逐段解释：

* 第 455~458 行：如果 response 是 FAIL，driver 打印 warning。
* 第 460~461 行：driver 以 ``UVM_HIGH`` 打印 read 地址、数据和 response。
* 第 462 行：结束 ``dmi_read``。

接口关系：

* 被调用：read 分支结束前。
* 调用：UVM log macro。
* 共享状态：``addr``、``rdata`` 和 ``resp``。

§5.11  ``dmi_write()`` — write request 与 response scan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L464-L491``）：

.. code-block:: systemverilog

     // DMI Write: send write request, then check response
     // Handles Busy responses with retry and DTMCS error recovery
     task dmi_write(input bit [6:0] addr,
                    input bit [31:0] wdata,
                    output bit [1:0] resp);
       bit [DMI_WIDTH-1:0] dmi_req;
       bit [DMI_WIDTH-1:0] dmi_resp;
       int retry_count;

       retry_count = 0;
       resp = DMI_RESP_BUSY;

       while (resp == DMI_RESP_BUSY && retry_count < MAX_BUSY_RETRIES) begin
         // Build DMI write request: addr[40:34] | data[33:2] | op=WRITE[1:0]
         dmi_req = {addr, wdata, DMI_OP_WRITE};

         // First DR scan: send the write request
         shift_dr_41(dmi_req, dmi_resp);

         // Wait for DMI to process
         repeat (5) @(posedge vif.clk);

         // Second DR scan: send NOP, capture the write response
         shift_dr_41({7'b0, 32'b0, DMI_OP_NOP}, dmi_resp);

         // Extract response
         resp = dmi_resp[1:0];

逐段解释：

* 第 464~468 行：``dmi_write`` 输入 7-bit 地址和 32-bit ``wdata``，输出 2-bit response。
* 第 469~474 行：声明 shift register 和 retry counter，并把 response 初始设为 BUSY。
* 第 476~481 行：retry loop 中构造 ``{addr, wdata, DMI_OP_WRITE}``，第一次 DR scan
  发送 write request。
* 第 483~487 行：等待 5 个时钟后，第二次 DR scan 发送 NOP 并捕获 write response。
* 第 489~491 行：write 只从 ``dmi_resp[1:0]`` 提取 response。

接口关系：

* 被调用：``drive_jtag_transaction`` 的 write 分支。
* 调用：``shift_dr_41`` 和 clock wait。
* 共享状态：JTAG DR scan 输出和 ``resp``。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L492-L519``）：

.. code-block:: systemverilog

         if (resp == DMI_RESP_BUSY) begin
           retry_count++;
           `uvm_warning("jtag_driver", $sformatf(
             "DMI WRITE Busy (addr=0x%02x), retry %0d/%0d",
             addr, retry_count, MAX_BUSY_RETRIES))

           // Reset DMI state to clear busy condition
           reset_dmi();

           // Delay before retry
           repeat (BUSY_RETRY_DELAY) @(posedge vif.clk);
         end
       end

       if (resp == DMI_RESP_BUSY) begin
         `uvm_error("jtag_driver", $sformatf(
           "DMI WRITE still Busy after %0d retries (addr=0x%02x)",
           MAX_BUSY_RETRIES, addr))
       end

逐段解释：

* 第 492~496 行：如果 write response 是 BUSY，retry counter 加 1，并打印 warning。
* 第 498~502 行：BUSY 时调用 ``reset_dmi``，再等待 ``BUSY_RETRY_DELAY`` 个时钟。
* 第 504 行：结束 retry loop。
* 第 506~510 行：如果退出 loop 后仍 BUSY，打印 ``uvm_error``。

接口关系：

* 被调用：``dmi_write`` retry loop。
* 调用：``reset_dmi``、UVM log macro、clock wait。
* 共享状态：``retry_count``、``resp`` 和 DMI/TAP 状态。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L512-L521``）：

.. code-block:: systemverilog

       if (resp == DMI_RESP_FAIL) begin
         `uvm_warning("jtag_driver", $sformatf(
           "DMI WRITE Fail response (addr=0x%02x)", addr))
       end

       `uvm_info("jtag_driver", $sformatf("DMI WRITE: addr=0x%02x data=0x%08x resp=%0d",
         addr, wdata, resp), UVM_HIGH)
     endtask

   endclass

逐段解释：

* 第 512~515 行：如果 response 是 FAIL，driver 打印 warning。
* 第 517~518 行：driver 以 ``UVM_HIGH`` 打印 write 地址、数据和 response。
* 第 519~521 行：结束 ``dmi_write`` 和 driver class。

接口关系：

* 被调用：write 分支结束前。
* 调用：UVM log macro。
* 共享状态：``addr``、``wdata`` 和 ``resp``。

§6  ``eh2_jtag_sequencer.sv`` — 类型化 sequencer
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_sequencer`` 是 ``eh2_jtag_seq_item`` 的类型化 sequencer，供 agent 和
virtual sequencer 持有。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv:L4-L12``）：

.. code-block:: systemverilog

   class eh2_jtag_sequencer extends uvm_sequencer #(eh2_jtag_seq_item);

     `uvm_component_utils(eh2_jtag_sequencer)

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

   endclass

逐段解释：

* 第 4 行：sequencer 参数化为 ``eh2_jtag_seq_item``，与 driver 事务类型匹配。
* 第 6 行：注册 component 类型。
* 第 8~10 行：constructor 只调用父类 constructor。
* 第 12 行：结束 class；源码没有新增 arbitration 或状态字段。

接口关系：

* 被调用：``eh2_jtag_agent.build_phase`` 创建该 sequencer。
* 调用：无。
* 共享状态：UVM sequencer item 队列。

§7  ``eh2_jtag_seq.sv`` — 单事务 sequence 与快捷入口
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_seq`` 是一笔 JTAG/DMI transaction 的轻量包装，并提供 ``send_write`` 与
``send_read`` 两个静态 helper。

§7.1  ``body()`` — 发送 ``txn``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv:L6-L22``）：

.. code-block:: systemverilog

   class eh2_jtag_seq extends uvm_sequence #(eh2_jtag_seq_item);

     `uvm_object_utils(eh2_jtag_seq)

     // Transaction to send
     eh2_jtag_seq_item txn;

     function new(string name = "eh2_jtag_seq");
       super.new(name);
     endfunction

     virtual task body();
       if (txn != null) begin
         start_item(txn);
         finish_item(txn);
       end
     endtask

逐段解释：

* 第 6 行：sequence 参数化为 ``eh2_jtag_seq_item``。
* 第 8 行：注册 UVM object 类型。
* 第 11 行：``txn`` 保存外部准备好的 transaction。
* 第 13~15 行：constructor 默认对象名是 ``eh2_jtag_seq``。
* 第 17~21 行：如果 ``txn`` 非空，sequence 调 ``start_item`` 和 ``finish_item`` 发送它。
* 第 22 行：结束 body task。

接口关系：

* 被调用：``seq.start(seqr)``。
* 调用：``start_item`` 和 ``finish_item``。
* 共享状态：``txn`` 字段。

§7.2  ``send_write()`` 与 ``send_read()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv:L24-L44``）：

.. code-block:: systemverilog

     // Convenience: send a write transaction
     static task send_write(uvm_sequencer_base seqr, bit [6:0] addr, bit [31:0] data);
       eh2_jtag_seq seq = new("jtag_write_seq");
       seq.txn = eh2_jtag_seq_item::type_id::create("txn");
       seq.txn.op = eh2_jtag_seq_item::JTAG_WRITE;
       seq.txn.addr = addr;
       seq.txn.wdata = data;
       seq.start(seqr);
     endtask

     // Convenience: send a read transaction
     static task send_read(uvm_sequencer_base seqr, bit [6:0] addr, output bit [31:0] data);
       eh2_jtag_seq seq = new("jtag_read_seq");
       seq.txn = eh2_jtag_seq_item::type_id::create("txn");
       seq.txn.op = eh2_jtag_seq_item::JTAG_READ;
       seq.txn.addr = addr;
       seq.start(seqr);
       data = seq.txn.rdata;
     endtask

逐段解释：

* 第 24~31 行：``send_write`` 创建 sequence 和 transaction，设置 ``op=JTAG_WRITE``、
  ``addr``、``wdata``，然后在传入 sequencer 上启动。
* 第 35~40 行：``send_read`` 创建 sequence 和 transaction，设置 ``op=JTAG_READ`` 与
  ``addr``，然后启动 sequence。
* 第 41 行：read sequence 完成后把 ``seq.txn.rdata`` 写到 output ``data``。
* 第 42~44 行：结束 read helper 和 class。

接口关系：

* 被调用：``debug_seq``、``core_eh2_base_test.send_debug_stimulus`` 和多个 debug/stress test。
* 调用：UVM factory ``type_id::create`` 和 ``seq.start``。
* 共享状态：调用者传入的 sequencer，以及 transaction 回填的 ``rdata``。

§8  ``eh2_jtag_agent.sv`` — top-level agent
------------------------------------------------------------------------------------------------------------------------

职责：``eh2_jtag_agent`` 在 active 模式创建 driver 与 sequencer，并连接二者的 item 通路。

§8.1  build phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv:L4-L22``）：

.. code-block:: systemverilog

   class eh2_jtag_agent extends uvm_agent;

     `uvm_component_utils(eh2_jtag_agent)

     eh2_jtag_driver    driver;
     eh2_jtag_sequencer sequencer;

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);

       if (get_is_active() == UVM_ACTIVE) begin
         driver    = eh2_jtag_driver::type_id::create("driver", this);
         sequencer = eh2_jtag_sequencer::type_id::create("sequencer", this);
       end
     endfunction

逐段解释：

* 第 4 行：top-level agent 继承 ``uvm_agent``。
* 第 6 行：注册 agent component 类型。
* 第 8~9 行：agent 只声明 driver 和 sequencer；没有 monitor 成员。
* 第 11~13 行：constructor 只调用父类 constructor。
* 第 15~22 行：build phase 只在 ``get_is_active() == UVM_ACTIVE`` 时创建 driver 和 sequencer。

接口关系：

* 被调用：``core_eh2_env.build_phase`` 创建 ``jtag_agent``。
* 调用：UVM factory 和 ``get_is_active``。
* 共享状态：``is_active`` 配置决定组件是否创建。

§8.2  connect phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv:L24-L32``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);

       if (get_is_active() == UVM_ACTIVE) begin
         driver.seq_item_port.connect(sequencer.seq_item_export);
       end
     endfunction

   endclass

逐段解释：

* 第 24~25 行：connect phase 先调用父类 connect phase。
* 第 27 行：连接逻辑受 active 模式保护。
* 第 28 行：driver 的 ``seq_item_port`` 连接到 sequencer 的 ``seq_item_export``。
* 第 30~32 行：结束 function 和 class。

接口关系：

* 被调用：UVM connect phase 调度。
* 调用：``driver.seq_item_port.connect``。
* 共享状态：UVM sequencer/driver item 通路。

§9  Env、vseqr 与 tb 顶层连接
------------------------------------------------------------------------------------------------------------------------

职责：JTAG agent 的运行依赖 env active 配置、virtual sequencer 句柄、tb 顶层 pin 连接和
config_db 注入。

§9.1  env 创建 active ``jtag_agent``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L87-L97``）：

.. code-block:: systemverilog

       // Interrupt agent (active)
       irq_agent = eh2_irq_agent::type_id::create("irq_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "irq_agent", "is_active", UVM_ACTIVE);

       // JTAG agent (active)
       jtag_agent = eh2_jtag_agent::type_id::create("jtag_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "jtag_agent", "is_active", UVM_ACTIVE);

       // Halt/Run agent (active)
       halt_run_agt = eh2_halt_run_agent::type_id::create("halt_run_agt", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "halt_run_agt", "is_active", UVM_ACTIVE);

逐段解释：

* 第 87~89 行：IRQ agent 被设为 active。
* 第 91~93 行：env 创建 ``jtag_agent``，并用 config_db 把该实例的 ``is_active`` 设为
  ``UVM_ACTIVE``。
* 第 95~97 行：Halt/Run agent 也在相邻代码中以 active 模式创建。

接口关系：

* 被调用：``core_eh2_env.build_phase``。
* 调用：UVM factory 和 ``uvm_config_db::set``。
* 共享状态：``jtag_agent`` 实例和 ``is_active`` 配置。

§9.2  vseqr 保存并连接 JTAG sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L15``）：

.. code-block:: systemverilog

   class core_eh2_vseqr extends uvm_sequencer;

     `uvm_component_utils(core_eh2_vseqr)

     // Sub-sequencers (use specific types for type-safe access)
     eh2_irq_sequencer              irq_seqr;
     eh2_jtag_sequencer             jtag_seqr;
     uvm_sequencer #(eh2_halt_run_seq_item) halt_run_seqr;

逐段解释：

* 第 7 行：``core_eh2_vseqr`` 是 env virtual sequencer。
* 第 9 行：注册 virtual sequencer 类型。
* 第 11~14 行：``jtag_seqr`` 类型是 ``eh2_jtag_sequencer``，与 agent 内 sequencer 类型一致。

接口关系：

* 被调用：env 创建和配置 virtual sequencer。
* 调用：无。
* 共享状态：``jtag_seqr`` 句柄。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L173``）：

.. code-block:: systemverilog

       // Wire sub-sequencers to virtual sequencer
       vseqr.irq_seqr      = irq_agent.sequencer;
       vseqr.jtag_seqr     = jtag_agent.sequencer;
       vseqr.halt_run_seqr = halt_run_agt.sequencer;
     endfunction

逐段解释：

* 第 169 行：注释说明该段把 sub-sequencer 接到 virtual sequencer。
* 第 170 行：IRQ sequencer 先被赋值。
* 第 171 行：``jtag_agent.sequencer`` 被赋给 ``vseqr.jtag_seqr``。
* 第 172~173 行：Halt/Run sequencer 随后赋值，并结束 connect phase。

接口关系：

* 被调用：UVM connect phase 调度。
* 调用：无函数调用，只做句柄赋值。
* 共享状态：``vseqr.jtag_seqr``。

§9.3  tb 顶层 pin 连接与 config_db
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L907-L916``）：

.. code-block:: systemverilog

     // JTAG Interface Instance (for debug stimulus)
     //--------------------------------------------------------------------------
     eh2_jtag_intf jtag_intf (.clk(core_clk), .rst_n(rst_l));

     // Connect JTAG interface to DUT JTAG signals
     assign jtag_tck    = jtag_intf.tck;
     assign jtag_tms    = jtag_intf.tms;
     assign jtag_tdi    = jtag_intf.tdi;
     assign jtag_trst_n = jtag_intf.trst_n;
     assign jtag_intf.tdo = jtag_tdo;

逐段解释：

* 第 907~909 行：tb 顶层实例化 ``eh2_jtag_intf``，时钟接 ``core_clk``，复位接 ``rst_l``。
* 第 911~915 行：interface 的 ``tck``、``tms``、``tdi`` 和 ``trst_n`` 被连续赋值到 DUT
  JTAG 输入 wire。
* 第 916 行：DUT 输出 ``jtag_tdo`` 被反馈给 ``jtag_intf.tdo``。

接口关系：

* 被调用：tb 顶层 elaboration。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``jtag_intf`` 是 driver 与 DUT JTAG pin 的共享边界。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1123-L1129``）：

.. code-block:: systemverilog

       uvm_config_db#(virtual eh2_irq_intf)::set(null, "*", "irq_vif", irq_intf);

       // Store JTAG interface
       uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);

       // Store Halt/Run interface
       uvm_config_db#(virtual eh2_halt_run_intf)::set(null, "*", "halt_run_vif", halt_run_vif);

逐段解释：

* 第 1123 行：IRQ interface 先存入 config_db。
* 第 1125~1126 行：``jtag_intf`` 以 key ``jtag_vif`` 存入 config_db，instance pattern 是
  ``"*"``。
* 第 1128~1129 行：Halt/Run interface 随后存入 config_db。

接口关系：

* 被调用：tb 顶层 initial/config 阶段。
* 调用：``uvm_config_db::set``。
* 共享状态：config_db 中的 ``jtag_vif``。

§10  Test 侧调用方式
------------------------------------------------------------------------------------------------------------------------

职责：debug tests 通过 ``eh2_jtag_seq::send_write`` 访问 DMI register，常见目标包括
``DMI_DMCONTROL``、``DMI_COMMAND``、``DMI_DATA1``、``DMI_SBCS``、``DMI_SBADDRESS0`` 和
``DMI_SBDATA0``。

§10.1  ``debug_seq`` — debug command walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L186-L213``）：

.. code-block:: systemverilog

   class debug_seq extends core_eh2_base_seq;

     `uvm_object_utils(debug_seq)

     // Sequencer to send JTAG transactions
     uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr;

     bit stress_mode = 0;  // 1 = continuous, 0 = single

     function new(string name = "debug_seq");
       super.new(name);
     endfunction

     virtual task body();
       rand_delay();
       if (stress_mode) begin
         // Continuous debug stimulus for stress tests only.
         forever begin
           if (stopped) return;
           send_debug_command_walk();
           rand_interval();
         end
       end else begin
         // Finite debug stimulus for directed coverage tests. This avoids
         // holding the core in debug mode until the mailbox timeout expires.
         send_debug_command_walk();
       end
     endtask

逐段解释：

* 第 186~193 行：``debug_seq`` 持有 ``jtag_seqr``，并用 ``stress_mode`` 区分连续模式和单次模式。
* 第 195~197 行：constructor 只调用父类 constructor。
* 第 199~207 行：body 先随机延迟；stress 模式下进入 forever，直到 ``stopped`` 为真才返回。
* 第 208~212 行：非 stress 模式只调用一次 ``send_debug_command_walk``。
* 第 213 行：结束 body task。

接口关系：

* 被调用：``core_eh2_debug_test`` 和 virtual sequence helper 创建并启动该 sequence。
* 调用：``rand_delay``、``rand_interval``、``send_debug_command_walk``。
* 共享状态：``jtag_seqr`` 和 ``stress_mode``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L219-L239``）：

.. code-block:: systemverilog

     virtual task send_debug_command_walk();
       bit [31:0] dccm_addr;
       send_dmactive();
       dmi_gap(20);
       send_halt();
       dmi_gap(120);
       send_core_register_read();
       dmi_gap(160);
       for (int unsigned i = 0; i < 5; i++) begin
         dccm_addr = 32'hf0040000 + (i * 32'h4);
         send_core_local_memory_read(dccm_addr);
         dmi_gap(180);
       end
       send_external_system_bus_read();
       dmi_gap(220);
       send_direct_system_bus_read_write();
       dmi_gap(220);
       send_resume();
       dmi_gap(120);
       clear_resume();
     endtask

逐段解释：

* 第 219~224 行：walk 先激活 debug module，等待 20 个 gap 单位，再发 halt 并等待 120。
* 第 225~231 行：先发 core register read，再循环 5 次对 DCCM 地址
  ``32'hf0040000 + i*4`` 发 local memory read。
* 第 232~235 行：随后发 external system bus read 和 direct system bus read/write。
* 第 236~238 行：最后发 resume，等待 120，再 clear resume。
* 第 239 行：结束 walk task。

接口关系：

* 被调用：``debug_seq.body``。
* 调用：多个 ``send_*`` helper 和 ``dmi_gap``。
* 共享状态：``jtag_seqr`` 由各 helper 使用。

§10.2  debug_seq 的 DMI 写 helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L241-L265``）：

.. code-block:: systemverilog

     virtual task send_dmactive();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h00000001);
     endtask

     virtual task send_halt();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);
     endtask

     virtual task send_core_register_read();
       // Abstract register command: read x0 with transfer=1 and 32-bit size.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_COMMAND, 32'h00221000);
     endtask

     virtual task send_core_local_memory_read(bit [31:0] addr = 32'hf0040000);
       // Debug memory command targeting DCCM. This goes through CORE_CMD_* and
       // exercises the DMA/debug memory path rather than the external SB path.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DATA1, addr);
       dmi_gap(20);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_COMMAND, 32'h02200000);

逐段解释：

* 第 241~244 行：``send_dmactive`` 写 ``DMI_DMCONTROL`` 为 ``32'h00000001``。
* 第 246~249 行：``send_halt`` 写 ``DMI_DMCONTROL`` 为 ``32'h80000001``。
* 第 251~255 行：``send_core_register_read`` 写 ``DMI_COMMAND`` 为 ``32'h00221000``。
* 第 257~265 行：``send_core_local_memory_read`` 先写 ``DMI_DATA1`` 为目标地址，等待
  ``dmi_gap(20)``，再写 ``DMI_COMMAND`` 为 ``32'h02200000``。

接口关系：

* 被调用：``send_debug_command_walk``。
* 调用：``eh2_jtag_seq::send_write`` 和 ``dmi_gap``。
* 共享状态：``jtag_seqr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L267-L298``）：

.. code-block:: systemverilog

     virtual task send_external_system_bus_read();
       // Debug memory command targeting external AXI memory. This drives
       // SB_CMD_START/SEND/RESP in eh2_dbg and the SB AXI slave.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DATA1, 32'h80000000);
       dmi_gap(20);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_COMMAND, 32'h02200000);
     endtask

     virtual task send_direct_system_bus_read_write();
       // Direct system-bus register access covers the standalone sb_state FSM.
       // bit 20 readonaddr starts a read when SBADDRESS0 is written.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_SBCS, 32'h00100000);
       dmi_gap(20);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_SBADDRESS0, 32'h80000000);
       dmi_gap(120);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_SBDATA0, 32'ha5a55a5a);
     endtask

逐段解释：

* 第 267~275 行：external system bus read 先写 ``DMI_DATA1`` 为 ``32'h80000000``，再写
  ``DMI_COMMAND`` 为 ``32'h02200000``。
* 第 277~288 行：direct system-bus read/write 依次写 ``DMI_SBCS``、``DMI_SBADDRESS0``
  和 ``DMI_SBDATA0``，中间插入 ``dmi_gap``。

接口关系：

* 被调用：``send_debug_command_walk``。
* 调用：``eh2_jtag_seq::send_write`` 和 ``dmi_gap``。
* 共享状态：``jtag_seqr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L290-L298``）：

.. code-block:: systemverilog

     virtual task send_resume();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h40000001);
     endtask

     virtual task clear_resume();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h00000001);
     endtask

逐段解释：

* 第 290~293 行：``send_resume`` 写 ``DMI_DMCONTROL`` 为 ``32'h40000001``。
* 第 295~298 行：``clear_resume`` 写 ``DMI_DMCONTROL`` 为 ``32'h00000001``。

接口关系：

* 被调用：``send_debug_command_walk``。
* 调用：``eh2_jtag_seq::send_write``。
* 共享状态：``jtag_seqr``。

§10.3  Base test debug stimulus
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L166-L216``）：

.. code-block:: systemverilog

     virtual task send_debug_stimulus(
       bit [1:0]  mode,
       string     debug_status_msg,
       uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr = null,
       int        halt_timeout_ns = 10000
     );
       bit [31:0] addr, data;
       bit is_write;

       if (jtag_seqr == null)
         jtag_seqr = env.jtag_agent.sequencer;

       // Send debug halt request via JTAG
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);

       // Wait for core to acknowledge debug mode entry
       fork
         begin
           wait_for_core_status(DEBUG_REQ);

逐段解释：

* 第 166~171 行：``send_debug_stimulus`` 参数包括期望 privilege mode、错误消息、可选
  ``jtag_seqr`` 和 halt timeout。
* 第 172~176 行：如果调用者没有传入 ``jtag_seqr``，task 使用 ``env.jtag_agent.sequencer``。
* 第 178~180 行：task 通过 JTAG 写 ``DMI_DMCONTROL`` 为 ``32'h80000001`` 发 halt request。
* 第 182~185 行：随后 fork 等待 ``wait_for_core_status(DEBUG_REQ)``。

接口关系：

* 被调用：debug 相关 test task。
* 调用：``eh2_jtag_seq::send_write`` 和 ``wait_for_core_status``。
* 共享状态：``env.jtag_agent.sequencer``、``DEBUG_REQ`` 状态。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L187-L216``）：

.. code-block:: systemverilog

         end
         begin
           #(halt_timeout_ns * 1ns);
           `uvm_fatal(test_name, $sformatf(
             "Timeout waiting for debug entry: %0s", debug_status_msg))
         end
       join_any
       disable fork;

       `uvm_info(test_name, $sformatf("Debug mode entered: %0s", debug_status_msg), UVM_LOW)

       // Verify we are in M-mode (EH2 debug entry always runs in M-mode)
       // Note: privilege mode checking depends on trace interface availability.
       // The DCSR.prv field below provides the authoritative check.

       // Read DCSR via abstract command (dmdata0 / abstract data register)
       // The EH2 debug module provides DCSR through abstract CSR read.
       // We read it from the signature mailbox if available, otherwise via JTAG.
       wait_for_csr_write(CSR_DCSR);
       dcsr_data = get_last_signature_data();

       // Verify dcsr.prv matches expected mode
       check_dcsr_prv(mode);

逐段解释：

* 第 187~193 行：timeout 分支等待 ``halt_timeout_ns`` 纳秒后触发 ``uvm_fatal``；任一分支完成后
  ``join_any`` 返回并 ``disable fork``。
* 第 195 行：进入 debug mode 后打印 UVM info。
* 第 197~205 行：注释和代码说明 DCSR 数据来自 signature mailbox；task 调
  ``wait_for_csr_write(CSR_DCSR)`` 后读取 ``get_last_signature_data``。
* 第 208 行：调用 ``check_dcsr_prv(mode)`` 检查 privilege mode。

接口关系：

* 被调用：``send_debug_stimulus`` 后半段。
* 调用：``uvm_fatal``、``uvm_info``、``wait_for_csr_write``、``get_last_signature_data``、
  ``check_dcsr_prv``。
* 共享状态：``dcsr_data`` 和 signature mailbox 最近数据。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L210-L216``）：

.. code-block:: systemverilog

       // Verify dcsr.cause indicates halt request (cause = 3)
       check_dcsr_cause(DBG_CAUSE_HALTREQ);

       // Resume from debug mode
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h40000000);

逐段解释：

* 第 210~211 行：task 调 ``check_dcsr_cause(DBG_CAUSE_HALTREQ)`` 检查 debug cause。
* 第 213~216 行：task 最后通过 JTAG 写 ``DMI_DMCONTROL`` 为 ``32'h40000000`` 退出 debug mode。

接口关系：

* 被调用：``send_debug_stimulus``。
* 调用：``check_dcsr_cause`` 和 ``eh2_jtag_seq::send_write``。
* 共享状态：``jtag_seqr``。

§10.4  Debug/stress tests 使用 JTAG sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L537-L552``）：

.. code-block:: systemverilog

     // Override start_vseq: fork a background debug_seq on the JTAG sequencer
     // so that the vseq body() doesn't return immediately (causing join_any
     // to complete at time 0).
     virtual task start_vseq();
       debug_seq dbg_h;
       fork
         begin
           dbg_h = debug_seq::type_id::create("dbg_h");
           dbg_h.jtag_seqr = env.vseqr.jtag_seqr;
           dbg_h.stress_mode = 1;
           dbg_h.start(null);
         end
       join_none
       // Also start the vseq for any other configured sequences
       super.start_vseq();
     endtask

逐段解释：

* 第 537~540 行：debug test 覆盖 ``start_vseq``，注释说明后台启动 ``debug_seq``。
* 第 541~547 行：fork 内创建 ``debug_seq``，把 ``jtag_seqr`` 指到 ``env.vseqr.jtag_seqr``，
  设置 ``stress_mode=1``，再 ``start(null)``。
* 第 549~551 行：后台线程 ``join_none`` 后调用父类 ``start_vseq``。
* 第 552 行：结束 task。

接口关系：

* 被调用：debug test 启动 virtual sequence 时。
* 调用：UVM factory、``debug_seq.start``、``super.start_vseq``。
* 共享状态：``env.vseqr.jtag_seqr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L585-L596``）：

.. code-block:: systemverilog

         // Debug stimulus
         begin
           #50000ns;
           forever begin
             #($urandom_range(2000, 10000) * 10ns);
             eh2_jtag_seq::send_write(env.jtag_agent.sequencer,
               eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);
             #($urandom_range(20, 200) * 10ns);
             eh2_jtag_seq::send_write(env.jtag_agent.sequencer,
               eh2_jtag_seq_item::DMI_DMCONTROL, 32'h40000000);
           end
         end

逐段解释：

* 第 585~589 行：stress test 的 debug 分支先等待 ``#50000ns``，然后按随机间隔循环。
* 第 590~591 行：每轮写 ``DMI_DMCONTROL`` 为 ``32'h80000001`` 触发 debug halt request。
* 第 592~594 行：等待随机时间后写 ``DMI_DMCONTROL`` 为 ``32'h40000000`` 触发 resume。
* 第 595~596 行：循环持续运行，直到外层 test 逻辑停止 fork。

接口关系：

* 被调用：``core_eh2_stress_test.start_vseq`` 的 debug stimulus fork 分支。
* 调用：``eh2_jtag_seq::send_write`` 和 ``$urandom_range``。
* 共享状态：``env.jtag_agent.sequencer``。

§11  运行时行为边界
------------------------------------------------------------------------------------------------------------------------

职责：本节列出源码中明确存在的边界，避免把未实现能力写进 JTAG agent 文档。

§11.1  当前 agent 没有 monitor component
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``dv/uvm/core_eh2/common/jtag_agent/`` 目录只有 package、interface、seq item、driver、
sequencer、sequence 和 agent 7 个文件。``eh2_jtag_agent.sv`` 第 8~9 行只声明
``driver`` 与 ``sequencer``，build phase 也只创建这两个 component。因此当前源码没有
``eh2_jtag_monitor``，也没有 DMI transaction analysis port。

接口关系：

* 被调用：agent build/connect phase。
* 调用：无 monitor 调用。
* 共享状态：JTAG pin 状态经 driver 和 tb 顶层连接，不由 agent monitor 发布。

§11.2  DMI response 是下一次 DR scan 捕获
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

driver 注释和代码都把 DMI response 建模为下一次 DR scan 捕获：``dmi_read`` 先发送 read
request，再等待 5 个 ``vif.clk``，随后发送 NOP 并捕获 response；``dmi_write`` 也使用同样
两次 scan 结构。BUSY 时 driver 会调用 ``reset_dmi``，写 DTMCS ``dmireset`` bit，并在 retry
前等待 ``BUSY_RETRY_DELAY``。

接口关系：

* 被调用：``dmi_read`` 和 ``dmi_write``。
* 调用：``shift_dr_41``、``reset_dmi``、``write_dtmcs``。
* 共享状态：``resp``、``rdata``、TAP state 和 JTAG pin。

§12  参考资料
------------------------------------------------------------------------------------------------------------------------

* :ref:`agent_jtag` — verification architecture 中的 JTAG agent 说明。
* :ref:`appendix_b_uvm_irq_agent` — active stimulus agent 与 test 调用方式的相邻例子。
* :doc:`../05_verification_arch/cosim_scoreboard` — debug/NMI 状态进入 cosim 的背景。
* :ref:`adr-0008` — debug cosim 决策背景。
* :ref:`adr-0001` — cosim via trace and probe。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv``。

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

本节补齐 JTAG agent 的 package、agent wrapper 和 sequencer 源码片段。JTAG driver
的 TAP state、DMI scan 和 retry 逻辑已在前文展开；这里补足最小 UVM 骨架，便于读者
从 package 入口追到 active component。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv
   :language: systemverilog
   :lines: 1-15
   :linenos:
   :caption: dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv:L1-L15

逐段精读：L4-L7 建立 package 与 UVM 依赖；L9-L14 汇入 item、driver、sequencer、
sequence 和 agent。这个顺序与 IRQ agent 一致，是简单 active UVM agent 的标准结构。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv
   :language: systemverilog
   :lines: 1-32
   :linenos:
   :caption: dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv:L1-L32

逐段精读：L4-L10 声明 driver 和 sequencer 成员；L16-L24 只在 active 模式创建二者；
L26-L30 连接 ``seq_item_port``。源码没有 ``eh2_jtag_monitor``，所以 DMI response
不通过 analysis port 发布。

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv
   :language: systemverilog
   :lines: 1-12
   :linenos:
   :caption: dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv:L1-L12

逐段精读：L5-L11 声明 typed sequencer。JTAG 事务的复杂性集中在 driver 的 TAP/DMI
task，而不是 sequencer 派生类。
