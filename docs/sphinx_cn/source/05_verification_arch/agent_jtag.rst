.. _agent_jtag:
.. _05_verification_arch/agent_jtag:

JTAG Agent — 架构参考
======================

:status: draft
:source: dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章边界
------------

本章解释 JTAG agent 在 EH2 UVM 环境中的 debug stimulus 路径。逐函数源码字典见
:ref:`appendix_b_uvm_jtag_agent`；这里聚焦 testbench 5-pin 接线、env active
配置、JTAG TAP state machine、IR/DR scan 和 DMI read/write 的架构边界。当前
``eh2_jtag_agent`` 只有 driver 和 sequencer，没有 monitor 成员。

JTAG agent 目录包含 7 个源文件：

* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv`
* :file:`dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv`

§2  架构数据流
--------------

JTAG agent 的主路径是 ``eh2_jtag_seq_item`` 进入 driver，driver 把 READ/WRITE
操作展开为 DMI request，再通过 TAP IR/DR scan 驱动 ``tck/tms/tdi/trst_n``，
并从 ``tdo`` 捕获响应。

.. code-block:: text

   core_eh2_vseqr.jtag_seqr
          |
          v
   eh2_jtag_sequencer
          |
          v
   eh2_jtag_driver
          |
          +-- drive_jtag_transaction()
          |       |
          |       +-- dmi_read() / dmi_write()
          |               |
          |               +-- write_ir(IR_DMI_ACCESS)
          |               +-- shift_dr_41()
          |
          v
   eh2_jtag_intf: tck/tms/tdi/trst_n -> DUT, tdo <- DUT

接口关系：

* 被调用：virtual sequence 通过 ``core_eh2_vseqr.jtag_seqr`` 提交 JTAG item。
* 调用：driver 调 ``dmi_read``、``dmi_write``、``write_ir``、``shift_dr_41`` 和
  ``tck_cycle``。
* 共享状态：``jtag_vif``、``tap_state``、``op``、``addr``、``wdata``、``rdata``、
  ``resp``。

§3  Package 与 agent 组成
-------------------------

职责：``eh2_jtag_agent_pkg`` 汇入 JTAG transaction、driver、sequencer、sequence
和 top-level agent。

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
* 第 6~7 行：导入 UVM 宏和 ``uvm_pkg``。
* 第 9~13 行：先 include ``eh2_jtag_seq_item.sv``，再 include driver、sequencer、
  sequence 和 agent。driver 与 sequencer 均依赖 ``eh2_jtag_seq_item``。

接口关系：

* 被调用：env package import JTAG agent package。
* 调用：SystemVerilog include。
* 共享状态：无运行期状态。

§4  Env active 配置
-------------------

职责：env 创建 JTAG agent 并把 ``is_active`` 设置为 ``UVM_ACTIVE``。connect phase
再把 JTAG sequencer 接到 virtual sequencer。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L91-L93``）：

.. code-block:: systemverilog

   // JTAG agent (active)
   jtag_agent = eh2_jtag_agent::type_id::create("jtag_agent", this);
   uvm_config_db#(uvm_active_passive_enum)::set(this, "jtag_agent", "is_active", UVM_ACTIVE);

逐段解释：

* 第 92 行：env 用 UVM factory 创建 ``jtag_agent``。
* 第 93 行：``jtag_agent`` 被设置为 ``UVM_ACTIVE``，从而在 agent build phase 创建
  driver 和 sequencer。

接口关系：

* 被调用：UVM build phase。
* 调用：``eh2_jtag_agent::type_id::create``、``uvm_config_db::set``。
* 共享状态：``jtag_agent`` 与 ``is_active``。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L172``）：

.. code-block:: systemverilog

   // Wire sub-sequencers to virtual sequencer
   vseqr.irq_seqr      = irq_agent.sequencer;
   vseqr.jtag_seqr     = jtag_agent.sequencer;
   vseqr.halt_run_seqr = halt_run_agt.sequencer;

逐段解释：

* 第 170 行：IRQ sequencer 接入 virtual sequencer。
* 第 171 行：JTAG sequencer 接入 ``vseqr.jtag_seqr``，这是 directed debug sequence
  的入口。
* 第 172 行：Halt/Run sequencer 也接入同一个 virtual sequencer。

接口关系：

* 被调用：UVM connect phase。
* 调用：普通句柄赋值。
* 共享状态：``vseqr.jtag_seqr``。

§5  Agent 内部组件
------------------

职责：``eh2_jtag_agent`` 在 active 模式创建 driver 与 typed sequencer，并连接
driver/sequencer 的 seq item 通道。源码没有创建 monitor。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv:L4-L30``）：

.. code-block:: systemverilog

   class eh2_jtag_agent extends uvm_agent;
   
     `uvm_component_utils(eh2_jtag_agent)
   
     eh2_jtag_driver    driver;
     eh2_jtag_sequencer sequencer;
   
     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
   
       if (get_is_active() == UVM_ACTIVE) begin
         driver    = eh2_jtag_driver::type_id::create("driver", this);
         sequencer = eh2_jtag_sequencer::type_id::create("sequencer", this);
       end
     endfunction
   
     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
   
       if (get_is_active() == UVM_ACTIVE) begin
         driver.seq_item_port.connect(sequencer.seq_item_export);
       end
     endfunction

逐段解释：

* 第 8~9 行：agent 成员只有 ``eh2_jtag_driver`` 和 ``eh2_jtag_sequencer``。
* 第 18~21 行：active 模式创建 driver/sequencer。
* 第 27~28 行：active 模式连接 ``driver.seq_item_port`` 与
  ``sequencer.seq_item_export``。

接口关系：

* 被调用：env 创建 agent 后由 UVM phase 调用。
* 调用：UVM factory 与 seq item port/export connect。
* 共享状态：``is_active``、``driver``、``sequencer``。

§6  JTAG interface 与 testbench 接线
------------------------------------

职责：``eh2_jtag_intf`` 保存 JTAG 5-pin 信号，并在 testbench 中接到 DUT 顶层端口。
``tdo`` 方向与其它四个信号相反：driver 输出 ``tck/tms/tdi/trst_n``，从 DUT 输入
``tdo``。

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

* 第 6~9 行：interface 绑定 UVM/core clock reset。
* 第 12~16 行：interface 保存 ``tck``、``tms``、``tdi``、``trst_n`` 和 ``tdo``。
* 第 19~24 行：默认 ``tck=0``、``tms=1``、``tdi=0``、``trst_n=0``；注释说明
  ``trst_n`` 的释放由 JTAG driver 控制。

接口关系：

* 被调用：testbench 实例化 ``jtag_intf``。
* 调用：无函数调用。
* 共享状态：五个 JTAG pin。

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

* 第 909 行：``jtag_intf`` 使用 ``core_clk`` 与 ``rst_l``。
* 第 912~915 行：interface 的 ``tck/tms/tdi/trst_n`` 连到 DUT 输入。
* 第 916 行：DUT 输出 ``jtag_tdo`` 回灌到 interface ``tdo``。

接口关系：

* 被调用：testbench elaboration。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``jtag_intf`` 与 DUT JTAG pins。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1124-L1126``）：

.. code-block:: systemverilog

   // Store JTAG interface
   uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);

逐段解释：

* 第 1126 行：testbench 以字段名 ``jtag_vif`` 发布 virtual interface。driver
  connect phase 用相同字段名获取它。

接口关系：

* 被调用：testbench initial 配置块。
* 调用：``uvm_config_db::set``。
* 共享状态：virtual ``eh2_jtag_intf``。

§7  Sequence item：DMI 操作抽象
-------------------------------

职责：``eh2_jtag_seq_item`` 把上层 debug 操作抽象为 DMI read/write：地址、写数据、
读数据和 response。DMI register enum 来自源码中的 Debug Spec 注释。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv:L8-L28``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 9~12 行：``jtag_op_e`` 只有 ``JTAG_READ`` 和 ``JTAG_WRITE``。
* 第 15~28 行：``dmi_reg_e`` 枚举列出 DATA、DMCONTROL、DMSTATUS、
  ABSTRACTCS、COMMAND、SBCS、SBADDRESS/SBDATA 和 HALTSUM 等 DMI 地址。

接口关系：

* 被调用：JTAG sequences 创建 transaction 时使用这些枚举值。
* 调用：无外部函数。
* 共享状态：``op`` 与 ``addr`` 的合法含义。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv:L30-L54``）：

.. code-block:: systemverilog

   // Transaction fields
   rand jtag_op_e   op;
   rand bit [6:0]   addr;
   rand bit [31:0]  wdata;
   bit [31:0]       rdata;
   bit [1:0]        resp;
   
   `uvm_object_utils_begin(eh2_jtag_seq_item)
     `uvm_field_enum(jtag_op_e, op, UVM_ALL_ON)
     `uvm_field_int(addr, UVM_ALL_ON)
     `uvm_field_int(wdata, UVM_ALL_ON)
     `uvm_field_int(rdata, UVM_ALL_ON)
     `uvm_field_int(resp, UVM_ALL_ON)
   `uvm_object_utils_end
   
   function string convert2string();
     if (op == JTAG_READ)
       return $sformatf("READ  addr=0x%02x rdata=0x%08x", addr, rdata);
     else
       return $sformatf("WRITE addr=0x%02x wdata=0x%08x", addr, wdata);
   endfunction

逐段解释：

* 第 31~35 行：``op``、``addr``、``wdata`` 是随机输入字段；``rdata`` 与 ``resp`` 是
  driver 回填字段。
* 第 37~43 行：UVM field 宏注册五个字段。
* 第 49~54 行：``convert2string`` 按 READ/WRITE 输出不同日志字符串。

接口关系：

* 被调用：driver 日志和 UVM object 工具路径。
* 调用：``$sformatf``。
* 共享状态：``op``、``addr``、``wdata``、``rdata``、``resp``。

§8  Driver 初始化与事务分发
---------------------------

职责：driver 获取 ``jtag_vif``，初始化 JTAG pins，释放 TRST，进入已知 TAP 状态，
加载 ``IR_DMI_ACCESS``，然后循环处理 read/write transaction。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L73-L105``）：

.. code-block:: systemverilog

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
     repeat (5) @(posedge vif.clk);
   
     // Navigate to known state
     goto_state(TEST_LOGIC_RESET);
     goto_state(RUN_TEST_IDLE);

逐段解释：

* 第 75~77 行：driver 通过字段名 ``jtag_vif`` 获取 virtual interface；失败时触发
  ``uvm_fatal``。
* 第 82~85 行：初始化 ``tck/tms/tdi/trst_n``。
* 第 88~90 行：TRST 保持 10 个 clock cycle 后释放，再等待 5 个 clock cycle。
* 第 93~94 行：driver 先进入 ``TEST_LOGIC_RESET``，再进入 ``RUN_TEST_IDLE``。

接口关系：

* 被调用：UVM connect/run phase。
* 调用：``uvm_config_db::get``、``goto_state``。
* 共享状态：``vif``、``tap_state``。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L96-L123``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 97 行：事务循环前加载 ``IR_DMI_ACCESS``。
* 第 100~104 行：driver 永久循环获取 item、驱动事务、调用 ``item_done``。
* 第 109~118 行：``drive_jtag_transaction`` 根据 ``txn.op`` 分派到 ``dmi_read`` 或
  ``dmi_write``，并把结果写回 transaction 字段。
* 第 119~121 行在源码中处理 default 分支，未知 op 记录 ``uvm_error``。

接口关系：

* 被调用：``run_phase``。
* 调用：``write_ir``、``seq_item_port.get_next_item``、``drive_jtag_transaction``、
  ``dmi_read``、``dmi_write``。
* 共享状态：``seq_item_port``、``txn.rdata``、``txn.resp``。

§9  TCK cycle 与 TAP 状态跟踪
-----------------------------

职责：driver 用 ``tck_cycle`` 生成单个 JTAG TCK 周期；``tck_nav`` 在不关心 TDO 的
导航场景中封装 ``tck_cycle`` 并更新软件侧 ``tap_state``。

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

逐段解释：

* 第 131~133 行：``tck_cycle`` 先设置 ``tms`` 与 ``tdi``。
* 第 134~138 行：用两个 ``vif.clk`` 上升沿组成 TCK low/high half，在 high half
  采样 ``tdo``，再把 ``tck`` 拉低。
* 第 142~146 行：``tck_nav`` 用 ``tdi=0`` 执行导航周期，并调用
  ``update_tap_state``。

接口关系：

* 被调用：``goto_state``、``write_ir``、``shift_dr_41``、``write_dtmcs``。
* 调用：``update_tap_state``。
* 共享状态：``vif.driver_cb``、``tap_state``。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L265-L285``）：

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

逐段解释：

* 第 266~267 行：``update_tap_state`` 根据当前 ``tap_state`` 和输入 ``tms`` 计算
  下一状态。
* 第 268~276 行：DR 侧状态覆盖 TEST_LOGIC_RESET、RUN_TEST_IDLE、SELECT_DR、
  CAPTURE/SHIFT/EXIT/PAUSE/UPDATE_DR。
* 第 277~284 行在源码后续覆盖 IR 侧状态，并在 default 分支回到
  ``TEST_LOGIC_RESET``。

接口关系：

* 被调用：``tck_nav``、``write_ir``、``shift_dr_41``、``write_dtmcs``。
* 调用：无下层函数。
* 共享状态：``tap_state``。

§10  IR scan 与 DR scan
-----------------------

职责：``write_ir`` 把 5-bit IR value LSB-first 移入 instruction register；
``shift_dr_41`` 把 41-bit DMI request 移入 DR，同时从 TDO 捕获上一笔 response。

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

逐段解释：

* 第 296~300 行：从 RUN_TEST_IDLE 导航到 SHIFT_IR。
* 第 303~307 行：循环移入 5 个 IR bit，最后一位用 ``TMS=1`` 退出 SHIFT_IR。
* 第 311 行：进入 UPDATE_IR；源码后续再回到 RUN_TEST_IDLE 并等待 2 个 clock。

接口关系：

* 被调用：driver 初始化、``write_dtmcs`` 和 ``reset_dmi`` 路径。
* 调用：``goto_state``、``tck_nav``、``tck_cycle``、``update_tap_state``。
* 共享状态：``tap_state``、``vif.driver_cb``。

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

* 第 327~330 行：``shift_dr_41`` 接收 41-bit input，返回 41-bit captured output。
* 第 333~336 行：从 RUN_TEST_IDLE 导航到 SHIFT_DR。
* 第 339~340 行：循环范围由 ``DMI_WIDTH`` 决定，最后一位用 ``is_last`` 标识。
* 第 343~356 行在源码后续通过 ``tck_cycle`` 移入数据、捕获 TDO，并经 UPDATE_DR
  返回 RUN_TEST_IDLE。

接口关系：

* 被调用：``dmi_read`` 和 ``dmi_write``。
* 调用：``goto_state``、``tck_nav``、``tck_cycle``、``update_tap_state``。
* 共享状态：``DMI_WIDTH``、``tap_state``、``vif.driver_cb.tdo``。

§11  DMI busy retry 与 reset
----------------------------

职责：DMI read/write 都使用两次 DR scan：第一次发送 request，第二次发送 NOP 并捕获
response。若 response 为 BUSY，driver 通过 DTMCS 的 ``dmireset`` bit 清理 DMI 状态，
然后延迟重试。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L45-L67``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 46~48 行：DMI op 编码为 NOP、READ 和 WRITE。
* 第 51~53 行：DMI response 编码为 OK、FAIL 和 BUSY。
* 第 56 行：``DTMCS_DMI_RESET`` 是 DTMCS 中的 ``dmireset`` bit index。
* 第 59~63 行：BUSY retry 最多 5 次，重试间隔 20 个 clock，DMI 宽度是 41 bit。
* 第 66~67 行：IR value 包含 DMI access 和 DTMCSR。

接口关系：

* 被调用：driver 内部 DMI helper。
* 调用：无函数调用。
* 共享状态：DMI/TAP 常量。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L367-L399``）：

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

逐段解释：

* 第 368~373 行：``write_dtmcs`` 切换 IR 到 ``IR_DTMCSR``。
* 第 375~379 行：DTMCS DR 宽度是 32 bit，所以这里不使用 ``shift_dr_41``。
* 第 381~385 行：循环移入 32 bit DTMCS data。
* 第 386~392 行在源码后续经 UPDATE_DR/RUN_TEST_IDLE 后切回 ``IR_DMI_ACCESS``。
* ``reset_dmi`` 调用 ``write_dtmcs(1 << DTMCS_DMI_RESET)``，再等待 5 个 clock。

接口关系：

* 被调用：``reset_dmi``。
* 调用：``write_ir``、``goto_state``、``tck_nav``、``tck_cycle``。
* 共享状态：``IR_DTMCSR``、``IR_DMI_ACCESS``、``DTMCS_DMI_RESET``。

§12  DMI read/write 事务
------------------------

职责：``dmi_read`` 构造 READ request，``dmi_write`` 构造 WRITE request；两者都在
BUSY 时调用 ``reset_dmi`` 并重试，最终把 ``resp`` 写回 transaction。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L408-L446``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 408~416 行：``dmi_read`` 初始化 request/response 变量，并把 ``resp`` 初值设为
  ``DMI_RESP_BUSY``。
* 第 418~423 行：在 BUSY 且 retry 未超限时构造 READ request，并通过第一次
  ``shift_dr_41`` 发出。
* 第 426 行：等待 5 个 clock 给 DTM 处理。
* 第 429~445 行在源码后续发送 NOP 捕获 response；若 response 仍 BUSY，则递增
  retry、调用 ``reset_dmi``，再等待 ``BUSY_RETRY_DELAY``。

接口关系：

* 被调用：``drive_jtag_transaction`` 的 READ 分支。
* 调用：``shift_dr_41``、``reset_dmi``。
* 共享状态：``addr``、``rdata``、``resp``、``retry_count``。

关键代码（``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L466-L503``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 466~474 行：``dmi_write`` 初始化 request/response 变量，并把 ``resp`` 初值设为
  ``DMI_RESP_BUSY``。
* 第 476~481 行：构造 WRITE request，字段布局是 ``addr``、``wdata`` 和
  ``DMI_OP_WRITE``。
* 第 484 行：等待 DMI 处理。
* 第 487~502 行在源码后续发送 NOP 捕获 write response；BUSY 时调用
  ``reset_dmi`` 并按 ``BUSY_RETRY_DELAY`` 延迟重试。

接口关系：

* 被调用：``drive_jtag_transaction`` 的 WRITE 分支。
* 调用：``shift_dr_41``、``reset_dmi``。
* 共享状态：``addr``、``wdata``、``resp``、``retry_count``。

§13  与 debug 状态采样的边界
-----------------------------

JTAG agent 通过 DMI 操作访问 debug module；cosim 侧使用 DUT probe 中的 debug
状态字段。testbench 里 ``debug_req`` 当前来自 Halt/Run 的 ``mpc_debug_halt_req``，
而 ``debug_mode`` 和 ``dbg_halted`` 来自 DUT 内部层次。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L837-L843``）：

.. code-block:: systemverilog

   // Interrupt/NMI/debug state for cosim notification
   // Construct MIP from external interrupt sources:
   //   bit 11 = MEIP (external), bit 7 = MTIP (timer), bit 3 = MSIP (software)
   assign dut_probe_intf.mip        = {20'b0, extintsrc_req[1], 3'b0, timer_int[0], 3'b0, soft_int[0], 3'b0};
   assign dut_probe_intf.nmi        = nmi_int;
   assign dut_probe_intf.nmi_int    = nmi_int;
   assign dut_probe_intf.debug_req  = mpc_debug_halt_req[0];

逐段解释：

* 第 837 行：注释说明该段为 cosim notification 构造 interrupt/NMI/debug 状态。
* 第 840~842 行：中断和 NMI 字段由 IRQ 信号构成。
* 第 843 行：``debug_req`` 来自 ``mpc_debug_halt_req[0]``，不是直接来自 JTAG pin。

接口关系：

* 被调用：testbench continuous assignment。
* 调用：无函数调用。
* 共享状态：``dut_probe_intf``、IRQ/Halt-Run/debug 状态。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L882-L883``）：

.. code-block:: systemverilog

   assign dut_probe_intf.debug_mode  = dut.veer.dec.dec_tlu_debug_mode[0];
   assign dut_probe_intf.dbg_halted  = dut.veer.dec.dec_tlu_dbg_halted[0];

逐段解释：

* 第 882~883 行：``debug_mode`` 与 ``dbg_halted`` 由 DUT 内部 decode/TLU 状态回灌到
  probe interface，供 trace/cosim 路径采样。

接口关系：

* 被调用：testbench continuous assignment。
* 调用：DUT hierarchy signal reference。
* 共享状态：``dut_probe_intf.debug_mode``、``dut_probe_intf.dbg_halted``。

§14  参考资料
-------------

* :ref:`appendix_b_uvm_jtag_agent` — JTAG agent 逐函数源码字典。
* :doc:`env` — env 中 active agent 与 virtual sequencer 的连接。
* :doc:`tb_top` — testbench 顶层 interface 分发和 DUT debug 状态采样。
* :ref:`agent_halt_run` — MPC halt/run 请求与 ``debug_req`` 的来源。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent_pkg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_sequencer.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`

§15  与 Ibex 工业实现对照
-------------------------

Ibex 的 debug 验证更多依赖 debug request、RVFI trap/debug 状态和 cosim scoreboard；
EH2 额外保留 JTAG pin-level agent，因为 VeeR EH2 wrapper 内含 DMI/JTAG bridge，
并且 debug directed 需要覆盖 IR/DR scan、DMI read/write 和 debug 状态回灌。
EH2 JTAG agent 当前只有 driver/sequencer，没有 monitor；debug 结果由 DUT probe、
trace item 和 scoreboard 侧采样。

.. list-table:: JTAG/debug 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - pin-level JTAG
     - 不是 core_ibex env 的主要独立入口
     - ``eh2_jtag_intf`` + ``eh2_jtag_agent``
   * - debug 状态观察
     - RVFI/debug sideband
     - ``dut_probe_intf.debug_mode`` / ``dbg_halted`` / trace item
   * - halt 请求
     - debug request 路径
     - Halt/Run agent 与 JTAG agent 分离
   * - cosim priority
     - scoreboard step 前设置 debug request
     - EH2 scoreboard 继承同一优先级，并从 probe/trace 获取状态

§16  Sign-off 关联
------------------

JTAG agent 主要服务 debug directed 和波形调试，但它的 interface 发布、driver TAP 状态机
和 DMI transaction 会影响 debug-mode cosim closure。当前 demo directed 40/40、
formal 46/46、LEC 31635/31635 PASS。修改 JTAG agent 后，应重点检查 debug directed、
``directed_dbg_dret_walk.S``、Halt/Run 交互和 scoreboard 的 debug request 采样。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
