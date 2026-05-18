.. _debug:
.. _02_core_reference/debug:

调试接口与验证路径
================================================================================

:status: draft
:source: dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv; dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv; dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv; dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv; dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv; dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv; dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv; dv/uvm/core_eh2/tests/core_eh2_test_lib.sv; dv/uvm/core_eh2/tests/asm/directed_debug_basic.S; dv/formal/properties/eh2_dbg_assert.sv; dv/formal/properties/eh2_dec_assert.sv; dv/formal/eh2_veer_sva.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  源码边界
--------------------------------------------------------------------------------

本章只描述当前验证源码中可直接回溯的 debug 相关接口：UVM JTAG/DMI agent、
halt/run agent、TB top 端口连接、debug sequence、directed EBREAK ASM 和 formal
debug properties。旧文中关于完整 RISC-V Debug Specification 0.13.2 功能集、硬件
trigger 数量、abstract command 内部指令注入方式等描述，在当前可见 RTL 源文件中没有
足够证据，本章不再把它们写成 EH2 当前实现结论。

验证侧 debug 数据流如下：

.. code-block:: text

   core_eh2_test_lib / core_eh2_seq_lib
      |
      |-- eh2_jtag_seq::send_write()
      v
   eh2_jtag_driver
      |
      |-- JTAG TAP state machine
      |-- 41-bit DMI DR scan
      v
   core_eh2_tb_top.jtag_* pins
      |
      v
   DUT debug/DMI path

**逐段解释** ：

* ``eh2_jtag_seq_item`` 定义 DMI register 地址、读写类型和数据字段。
* ``eh2_jtag_driver`` 将 sequence item 转换成 JTAG TAP 导航和 41-bit DMI scan。
* ``eh2_halt_run_intf`` 与 ``eh2_halt_run_driver`` 直接驱动 MPC/CPU halt-run pins，
  这条路径独立于 JTAG/DMI sequence。
* formal property 从 halt/resume FSM、DMI 控制寄存器、EBREAK decode 和顶层 debug
  status 角度做约束/检查。

**接口关系** ：

* **被调用** ：debug/stress/single-step 类测试、UVM vseq、formal flow。
* **调用** ：JTAG sequence 调用 driver；driver 驱动 ``jtag_*`` pins；formal property
  由 IFV 证明。
* **共享状态** ：``jtag_vif``、``halt_run_vif``、DMI register fields、debug FSM state
  和 DUT debug status pins。

§2  JTAG/DMI transaction 对象
--------------------------------------------------------------------------------

§2.1  ``eh2_jtag_seq_item`` 的操作类型与 DMI 地址
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_jtag_seq_item`` 是 UVM 侧 JTAG/DMI transaction 对象。它只抽象出读写
操作、7-bit DMI 地址、32-bit 写数据、32-bit 读数据和 2-bit response。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv:L6-L35``）：

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

**逐段解释** ：

* 第 L6 行：class 继承 ``uvm_sequence_item``，用于 sequence、driver 和 sequencer 之间
  传递 transaction。
* 第 L8-L12 行：``jtag_op_e`` 只定义 ``JTAG_READ`` 与 ``JTAG_WRITE`` 两种操作。
* 第 L14-L28 行：``dmi_reg_e`` 枚举列出当前测试使用的 DMI 地址，包括 ``DATA0``、
  ``DATA1``、``DMCONTROL``、``DMSTATUS``、``ABSTRACTCS``、``COMMAND``、``SBCS``、
  ``SBADDRESS0``、``SBDATA0``、``SBDATA1`` 和 ``HALTSUM``。
* 第 L30-L35 行：transaction 字段为 ``op``、``addr``、``wdata``、``rdata`` 和
  ``resp``。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv:L37-L54``）：

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

**逐段解释** ：

* 第 L37-L43 行：UVM field macro 注册操作、地址、写数据、读数据和 response 字段。
* 第 L45-L47 行：构造函数只调用 ``super.new``。
* 第 L49-L54 行：``convert2string`` 按 ``JTAG_READ`` 或 ``JTAG_WRITE`` 生成日志字符串。

**接口关系** ：

* **被调用** ：``eh2_jtag_seq`` 创建并填充该对象；``eh2_jtag_driver`` 消费该对象。
* **调用** ：UVM object macro 与 ``$sformatf``。
* **共享状态** ：对象字段保存单笔 DMI transaction。

§2.2  ``eh2_jtag_seq`` 的 send helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_jtag_seq`` 是简单 UVM sequence，提供 ``send_write`` 和 ``send_read``
两个 static helper。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv:L17-L42``）：

.. code-block:: systemverilog

     virtual task body();
       if (txn != null) begin
         start_item(txn);
         finish_item(txn);
       end
     endtask
   
     // Convenience: send a write transaction
     static task send_write(uvm_sequencer_base seqr, bit [6:0] addr, bit [31:0] data);
       eh2_jtag_seq seq = new("jtag_write_seq");
       seq.txn = eh2_jtag_seq_item::type_id::create("txn");
       seq.txn.op = eh2_jtag_seq_item::JTAG_WRITE;
       seq.txn.addr = addr;
       seq.txn.wdata = data;
       seq.start(seqr);

**逐段解释** ：

* 第 L17-L22 行：``body`` 只有在 ``txn`` 非空时才执行 ``start_item`` 和 ``finish_item``。
* 第 L24-L31 行：``send_write`` 创建 ``jtag_write_seq`` 和 ``txn``，设置 op、addr、wdata，
  然后在指定 sequencer 上启动 sequence。
* 第 L34-L42 行：``send_read`` 创建 ``jtag_read_seq``，设置 op 与 addr，启动后从
  ``seq.txn.rdata`` 取回读数据。

**接口关系** ：

* **被调用** ：debug sequence 和 test helper 多次调用 ``send_write``。
* **调用** ：``eh2_jtag_seq_item::type_id::create``、``start``。
* **共享状态** ：``txn`` 在 sequence 与 driver 之间传递，读 helper 通过同一对象取回
  ``rdata``。

§3  JTAG driver 与 DMI scan
--------------------------------------------------------------------------------

§3.1  driver 常量、TAP 状态与 DMI 位宽
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_jtag_driver`` 实现 JTAG TAP 状态机，并把 DMI transaction 编码为
41-bit DR scan。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L7-L68``）：

.. code-block:: systemverilog

   // DMI Register (41 bits, DR scan):
   //   [40:34] addr  (7-bit DMI address)
   //   [33:2]  data  (32-bit DMI data)
   //   [1:0]   op    (2-bit: 0=NOP, 1=Read, 2=Write)
   //
   // DMI Response (41 bits, returned on next DR scan):
   //   [40:34] addr
   //   [33:2]  data  (32-bit read data for Read op)
   //   [1:0]   resp  (2-bit: 0=OK, 1=Reserved, 2=Fail, 3=Busy)

**逐段解释** ：

* 第 L7-L10 行：DMI request scan 宽度是 41 bit，地址位于 ``[40:34]``，数据位于
  ``[33:2]``，op 位于 ``[1:0]``。
* 第 L12-L15 行：DMI response 也按 41 bit 返回，其中 ``[33:2]`` 是读数据，
  ``[1:0]`` 是 response。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L23-L68``）：

.. code-block:: systemverilog

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

**逐段解释** ：

* 第 L23-L41 行：driver 枚举 16 个 JTAG TAP 状态。
* 第 L45-L48 行：DMI op 编码为 ``NOP=2'b00``、``READ=2'b01``、``WRITE=2'b10``。
* 第 L50-L53 行：DMI response 编码为 ``OK=2'b00``、``FAIL=2'b10``、``BUSY=2'b11``。
* 第 L55-L68 行：driver 定义 DTMCS reset bit、busy retry 参数、DMI 宽度和 IR 值。

**接口关系** ：

* **被调用** ：JTAG agent 在 run phase 中运行 driver。
* **调用** ：后续 ``write_ir``、``dmi_read``、``dmi_write`` 等 task 使用这些常量。
* **共享状态** ：``tap_state`` 保存当前 TAP 状态。

§3.2  driver run phase 初始化与 transaction 分派
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：driver 从 ``uvm_config_db`` 获取 JTAG virtual interface，复位 TAP，写入
DMI access IR，然后持续处理 sequence item。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L73-L105``）：

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

**逐段解释** ：

* 第 L73-L78 行：driver 必须从 config DB 取得 ``jtag_vif``；失败时 fatal。
* 第 L80-L85 行：run phase 将 ``tck=0``、``tms=1``、``tdi=0``，并拉低 ``trst_n``。
* 第 L87-L90 行：保持 reset 10 个 ``vif.clk`` 周期，释放 ``trst_n`` 后再等 5 个周期。
* 第 L92-L97 行：driver 导航到 ``TEST_LOGIC_RESET``、``RUN_TEST_IDLE``，再写
  ``IR_DMI_ACCESS``。
* 第 L99-L105 行：driver 永久从 ``seq_item_port`` 取 transaction，调用
  ``drive_jtag_transaction``，再 ``item_done``。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L108-L123``）：

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

**逐段解释** ：

* 第 L108-L110 行：每笔 transaction 先打印 high verbosity 日志。
* 第 L112-L118 行：``JTAG_READ`` 调用 ``dmi_read``，``JTAG_WRITE`` 调用 ``dmi_write``。
* 第 L119-L121 行：未知 op 报 ``uvm_error``。

**接口关系** ：

* **被调用** ：driver run phase 调用 ``drive_jtag_transaction``。
* **调用** ：``uvm_config_db::get``、``goto_state``、``write_ir``、``dmi_read``、
  ``dmi_write``。
* **共享状态** ：读写 ``vif`` 和 ``tap_state``。

§3.3  TCK cycle 与 TAP 导航
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：driver 通过 ``tck_cycle`` 生成一拍 TCK，并通过 ``goto_state`` 导航 TAP。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv:L129-L146``）：

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

**逐段解释** ：

* 第 L129-L133 行：``tck_cycle`` 先设置 ``tms`` 与 ``tdi``。
* 第 L134-L138 行：用两个 ``vif.clk`` posedge 组成 TCK 低半拍和高半拍；高半拍采样
  ``tdo``，随后把 ``tck`` 拉低。
* 第 L141-L146 行：``tck_nav`` 包装 ``tck_cycle``，不关心 TDO，并调用
  ``update_tap_state`` 更新内部状态。

**接口关系** ：

* **被调用** ：TAP 导航、IR/DR shift task 调用。
* **调用** ：``update_tap_state``。
* **共享状态** ：驱动 ``eh2_jtag_intf.driver_cb``。

§4  JTAG interface 与 TB 连接
--------------------------------------------------------------------------------

§4.1  ``eh2_jtag_intf`` 信号和 clocking block
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_jtag_intf`` 包装 JTAG pins，并为 driver 与 monitor 提供 clocking block。

**关键代码** （``dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv:L6-L42``）：

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

**逐段解释** ：

* 第 L6-L9 行：interface 接收 ``clk`` 和 ``rst_n``。
* 第 L11-L16 行：interface 声明 ``tck``、``tms``、``tdi``、``trst_n`` 和 ``tdo``。
* 第 L18-L24 行：initial block 设置 ``tck=0``、``tms=1``、``tdi=0``、``trst_n=0``。
* 第 L26-L33 行：driver clocking block 输出 ``tck/tms/tdi/trst_n``，输入 ``tdo``。
* 第 L35-L42 行：monitor clocking block 只采样这 5 个 JTAG pins。

**接口关系** ：

* **被调用** ：JTAG agent driver/monitor 通过 virtual interface 使用。
* **调用** ：无。
* **共享状态** ：保存当前 JTAG pin 值。

§4.2  TB 中的 JTAG 和 debug pins
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB signals include 文件声明 JTAG pins 和 debug/control pins，TB top 把它们
连接到 DUT wrapper。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:L6-L39``）：

.. code-block:: systemverilog

     // JTAG
     logic         jtag_tck;
     logic         jtag_tms;
     logic         jtag_tdi;
     logic         jtag_trst_n;
     logic         jtag_tdo;
     logic [31:1]  jtag_id;
   
     // Trace
     logic [`RV_NUM_THREADS-1:0][63:0] trace_rv_i_insn_ip;

**逐段解释** ：

* 第 L6-L12 行：TB 声明 JTAG pins 和 ``jtag_id``。
* 第 L27-L39 行：同一文件声明 debug/control pins，包括 ``o_debug_mode_status``、
  ``o_cpu_halt_ack``、``o_cpu_halt_status``、``o_cpu_run_ack``、MPC debug halt/run/reset
  request/ack、``debug_brkpt_status``、``dec_tlu_mhartstart`` 和 ``i_cpu_run_req``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L349-L391``）：

.. code-block:: systemverilog

       // JTAG
       .jtag_tck          (jtag_tck),
       .jtag_tms          (jtag_tms),
       .jtag_tdi          (jtag_tdi),
       .jtag_trst_n       (jtag_trst_n),
       .jtag_tdo          (jtag_tdo),
   
       // Interrupts
       .timer_int         (timer_int),
       .soft_int          (soft_int),

**逐段解释** ：

* 第 L349-L354 行：DUT wrapper 的 JTAG pins 接到 TB wires。
* 第 L374-L381 行：MPC halt/run pins 接到 ``mpc_debug_halt_req``、
  ``mpc_debug_run_req``、``mpc_reset_run_req``、ack/status wires。
* 第 L383-L388 行：CPU halt/run pins 接到 ``i_cpu_halt_req``、``i_cpu_run_req`` 和
  ack/status wires。
* 第 L390-L391 行：debug mode status 输出接到 ``o_debug_mode_status``。

**接口关系** ：

* **被调用** ：DUT wrapper 实例化时连接。
* **调用** ：无。
* **共享状态** ：TB wires 同时被 interface、driver、monitor 和 DUT 端口使用。

§4.3  ``uvm_config_db`` 分发 debug virtual interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB top 把 JTAG 和 halt/run virtual interface 写入 config DB，供 agent 取得。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1123-L1129``）：

.. code-block:: systemverilog

       // Store IRQ interface
       uvm_config_db#(virtual eh2_irq_intf)::set(null, "*", "irq_vif", irq_intf);
   
       // Store JTAG interface
       uvm_config_db#(virtual eh2_jtag_intf)::set(null, "*", "jtag_vif", jtag_intf);
   
       // Store Halt/Run interface
       uvm_config_db#(virtual eh2_halt_run_intf)::set(null, "*", "halt_run_vif", halt_run_vif);

**逐段解释** ：

* 第 L1123 行：IRQ interface 分发与 debug 无关，但说明同一 config DB 模式。
* 第 L1125-L1126 行：``jtag_intf`` 以 key ``jtag_vif`` 写入 config DB。
* 第 L1128-L1129 行：``halt_run_vif`` 以 key ``halt_run_vif`` 写入 config DB。

**接口关系** ：

* **被调用** ：agent build/connect phase 调用 ``uvm_config_db::get``。
* **调用** ：``uvm_config_db::set``。
* **共享状态** ：virtual interface handle。

§5  Halt/Run agent
--------------------------------------------------------------------------------

§5.1  ``eh2_halt_run_intf`` 的默认值和 modport
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：halt/run interface 直接包装 MPC debug halt/run、CPU halt/run 和 ack/status
信号。

**关键代码** （``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L7-L28``）：

.. code-block:: systemverilog

   interface eh2_halt_run_intf (
     input logic clk,
     input logic rst_n
   );
   
     // MPC debug halt/run requests (active high)
     logic mpc_debug_halt_req = 1'b0;
     logic mpc_debug_run_req  = 1'b1;
     logic mpc_reset_run_req  = 1'b1;

**逐段解释** ：

* 第 L7-L10 行：interface 接收 ``clk`` 和 ``rst_n``。
* 第 L12-L15 行：MPC debug halt 默认 0，MPC debug run 与 reset run 默认 1。
* 第 L17-L21 行：CPU halt 默认 0，``i_cpu_run_req`` 默认 0；源码注释说明该默认值匹配
  reference testbench。
* 第 L23-L28 行：interface 声明 halt/run ack、halt status 和 debug mode status。

**关键代码** （``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv:L29-L55``）：

.. code-block:: systemverilog

     // Driver clocking block
     clocking driver_cb @(posedge clk);
       output mpc_debug_halt_req;
       output mpc_debug_run_req;
       output mpc_reset_run_req;
       output i_cpu_halt_req;
       output i_cpu_run_req;
     endclocking
   
     // Monitor clocking block
     clocking monitor_cb @(posedge clk);

**逐段解释** ：

* 第 L29-L36 行：driver clocking block 只驱动五个 request。
* 第 L38-L49 行：monitor clocking block 采样 request 与 ack/status。
* 第 L51-L55 行：driver modport 同时允许读取 ack/status，monitor modport 只采样。

**接口关系** ：

* **被调用** ：halt/run driver 和 monitor 使用该 interface。
* **调用** ：无。
* **共享状态** ：保存 request 与 ack/status pin 值。

§5.2  ``eh2_halt_run_seq_item`` action 编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：halt/run sequence item 把驱动动作压缩为四种 action，并允许设置延迟。

**关键代码** （``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_seq_item.sv:L4-L19``）：

.. code-block:: systemverilog

   class eh2_halt_run_seq_item extends uvm_sequence_item;
   
     // Action type
     typedef enum bit [1:0] {
       HALT_CORE    = 2'b00,
       RUN_CORE     = 2'b01,
       RESET_RUN    = 2'b10,
       CPU_HALT     = 2'b11
     } action_e;
   
     rand action_e action;
     rand int unsigned delay;  // Delay before applying (clock cycles)

**逐段解释** ：

* 第 L4 行：class 继承 ``uvm_sequence_item``。
* 第 L6-L12 行：action 枚举为 ``HALT_CORE``、``RUN_CORE``、``RESET_RUN`` 和 ``CPU_HALT``。
* 第 L14-L19 行：``delay`` 是施加动作前的 clock cycle 延迟，约束范围为 0 到 100。

**接口关系** ：

* **被调用** ：halt/run sequence 生成该对象，driver 消费。
* **调用** ：UVM object macro 和 ``$sformatf``。
* **共享状态** ：对象字段保存一次 halt/run 动作。

§5.3  ``eh2_halt_run_driver`` 的动作执行
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：halt/run driver 根据 action 驱动 MPC 或 CPU halt/run request，并等待对应 ack。

**关键代码** （``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L16-L32``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(this, "", "halt_run_vif", vif)) begin
         `uvm_fatal("halt_run_drv", "Failed to get halt_run interface")
       end
     endfunction
   
     task run_phase(uvm_phase phase);
       eh2_halt_run_seq_item item;

**逐段解释** ：

* 第 L16-L21 行：driver 从 config DB 获取 ``halt_run_vif``；失败时 fatal。
* 第 L23-L31 行：run phase 初始化默认 request：MPC halt 0、MPC run 1、MPC reset run 1、
  CPU halt 0、CPU run 1。

**关键代码** （``dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv:L33-L79``）：

.. code-block:: systemverilog

     forever begin
       seq_item_port.get_next_item(item);
   
       if (item.delay > 0) begin
         repeat (item.delay) @(posedge vif.clk);
       end
   
       case (item.action)
         eh2_halt_run_seq_item::HALT_CORE: begin
           `uvm_info("halt_run_drv", "Asserting MPC debug halt", UVM_MEDIUM)

**逐段解释** ：

* 第 L33-L38 行：driver 永久取 item，并按 ``item.delay`` 等待指定 clock cycles。
* 第 L40-L50 行：``HALT_CORE`` 拉高 ``mpc_debug_halt_req``、拉低 ``mpc_debug_run_req``，
  最多等待 100 个 clock cycles 检查 ``o_cpu_halt_ack``。
* 第 L52-L60 行：``RUN_CORE`` 拉低 halt、拉高 run，最多等待 100 个 clock cycles 检查
  ``o_cpu_run_ack``。
* 第 L63-L68 行：``RESET_RUN`` 把 ``mpc_reset_run_req`` 拉低 5 个 clock cycles 后再拉高。
* 第 L70-L77 行：``CPU_HALT`` 拉高 ``i_cpu_halt_req``、拉低 ``i_cpu_run_req``，最多等待
  100 个 clock cycles 检查 ``o_cpu_halt_ack``。

**接口关系** ：

* **被调用** ：halt/run agent 运行 driver。
* **调用** ：``uvm_config_db::get``、``seq_item_port``。
* **共享状态** ：驱动 ``halt_run_vif.driver_cb``，读取 ack/status。

§6  UVM debug sequence 与测试 helper
--------------------------------------------------------------------------------

§6.1  ``debug_seq`` 的 command walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``debug_seq`` 通过 JTAG/DMI 依次发送 dmactive、halt、abstract command、
DCCM debug memory read、external system-bus read、direct system-bus access 和
resume。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L186-L213``）：

.. code-block:: systemverilog

   class debug_seq extends core_eh2_base_seq;
   
     `uvm_object_utils(debug_seq)
   
     // Sequencer to send JTAG transactions
     uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr;
   
     bit stress_mode = 0;  // 1 = continuous, 0 = single

**逐段解释** ：

* 第 L186-L193 行：``debug_seq`` 继承 ``core_eh2_base_seq``，保存 JTAG sequencer handle，
  并用 ``stress_mode`` 区分连续与单次刺激。
* 第 L199-L207 行：``body`` 先随机延迟；stress 模式下永久执行 command walk，直到
  ``stopped``。
* 第 L208-L212 行：非 stress 模式只执行一次 command walk，源码注释说明这样避免让 core
  一直停在 debug mode 直到 mailbox timeout。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L219-L239``）：

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

**逐段解释** ：

* 第 L219-L224 行：command walk 先发送 dmactive，再发送 halt。
* 第 L225-L231 行：发送一次 core register read，然后循环 5 次读取从
  ``32'hf0040000`` 开始、步长 4 的 DCCM 地址。
* 第 L232-L238 行：随后发送 external system bus read、direct system bus read/write、
  resume 和 clear resume。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L241-L298``）：

.. code-block:: systemverilog

     virtual task send_dmactive();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h00000001);
     endtask
   
     virtual task send_halt();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);
     endtask

**逐段解释** ：

* 第 L241-L249 行：``send_dmactive`` 写 ``DMI_DMCONTROL`` 为 ``32'h00000001``；
  ``send_halt`` 写 ``32'h80000001``。
* 第 L251-L255 行：``send_core_register_read`` 向 ``DMI_COMMAND`` 写
  ``32'h00221000``。
* 第 L257-L265 行：``send_core_local_memory_read`` 先向 ``DMI_DATA1`` 写地址，再向
  ``DMI_COMMAND`` 写 ``32'h02200000``。
* 第 L267-L275 行：``send_external_system_bus_read`` 使用地址 ``32'h80000000`` 和同一
  command 值。
* 第 L277-L288 行：direct system-bus access 写 ``DMI_SBCS``、``DMI_SBADDRESS0`` 和
  ``DMI_SBDATA0``。
* 第 L290-L298 行：``send_resume`` 写 ``32'h40000001``；``clear_resume`` 写
  ``32'h00000001``。

**接口关系** ：

* **被调用** ：``core_eh2_vseq`` 和 ``core_eh2_debug_test`` 启动 ``debug_seq``。
* **调用** ：``eh2_jtag_seq::send_write``。
* **共享状态** ：使用 ``jtag_seqr``，读取 base sequence 的 ``stopped`` 和延迟配置。

§6.2  ``send_debug_stimulus`` 测试 helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：base test helper 通过 JTAG 发起 debug halt，等待 core 状态，检查 DCSR
字段，然后发送 resume。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L166-L218``）：

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

**逐段解释** ：

* 第 L166-L171 行：task 参数包含期望 privilege mode、错误消息、可选 JTAG sequencer 和
  halt timeout。
* 第 L175-L176 行：未传入 sequencer 时使用 ``env.jtag_agent.sequencer``。
* 第 L178-L180 行：helper 写 ``DMI_DMCONTROL`` 为 ``32'h80000001`` 发送 debug halt request。
* 第 L182-L193 行：fork 一个等待 ``wait_for_core_status(DEBUG_REQ)`` 的线程和一个 timeout
  线程，任一完成后 ``disable fork``。
* 第 L201-L211 行：等待 DCSR signature 写入，读取 ``dcsr_data``，检查 ``dcsr.prv`` 和
  cause。
* 第 L213-L217 行：写 ``DMI_DMCONTROL`` 为 ``32'h40000000`` 发送 resume。

**接口关系** ：

* **被调用** ：具体 debug 类测试可调用该 helper。
* **调用** ：``eh2_jtag_seq::send_write``、``wait_for_core_status``、
  ``wait_for_csr_write``、``check_dcsr_prv``、``check_dcsr_cause``。
* **共享状态** ：使用 ``env.jtag_agent.sequencer``、``dcsr_data`` 和 signature mailbox。

§6.3  ``core_eh2_debug_test`` 启动 background debug sequence
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``core_eh2_debug_test`` 重载 ``start_vseq``，在后台启动 stress 模式的
``debug_seq``，再调用 base vseq。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L527-L552``）：

.. code-block:: systemverilog

   // 2. Debug Test - Drives debug requests to test halt/resume
   // ---------------------------------------------------------------------------
   class core_eh2_debug_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_debug_test)
   
     function new(string name = "core_eh2_debug_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction

**逐段解释** ：

* 第 L527-L535 行：``core_eh2_debug_test`` 继承 ``core_eh2_base_test`` 并注册 UVM component。
* 第 L537-L549 行：``start_vseq`` fork 后台线程，创建 ``debug_seq``，把
  ``env.vseqr.jtag_seqr`` 赋给 ``jtag_seqr``，设置 ``stress_mode=1``，然后
  ``start(null)``。
* 第 L550-L551 行：后台 debug sequence 启动后，调用 ``super.start_vseq()`` 运行其它
  已配置 sequence。

**接口关系** ：

* **被调用** ：test factory 选择 ``core_eh2_debug_test`` 时运行。
* **调用** ：``debug_seq::type_id::create``、``debug_seq.start``、``super.start_vseq``。
* **共享状态** ：使用 ``env.vseqr.jtag_seqr``。

§7  Directed EBREAK 测试
--------------------------------------------------------------------------------

§7.1  ``directed_debug_basic.S`` 主流程
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：directed ASM 设置 trap handler，执行 ``ebreak``，并验证 handler 写入 flag。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_debug_basic.S:L14-L34``）：

.. code-block:: bash

   _start:
       // Set up trap handler (direct mode)
       la      t0, trap_handler
       csrw    mtvec, t0
   
       // Clear flag register
       li      x31, 0
   
       // Execute EBREAK -- should trap with mcause=3
       ebreak
   
       // After mret, we should land here
       // Check that trap handler set our flag
       li      t0, 0xBEEF
       bne     x31, t0, fail

**逐段解释** ：

* 第 L14-L17 行：测试把 ``trap_handler`` 地址写入 ``mtvec``。
* 第 L19-L20 行：清零 ``x31``，作为 handler 是否运行的 flag。
* 第 L22-L23 行：执行 ``ebreak``。
* 第 L25-L28 行：从 handler 返回后，测试要求 ``x31`` 等于 ``0xBEEF``。
* 第 L30-L34 行：pass 路径向 mailbox 地址 ``0xD0580000`` 写 ``0xFF``，然后跳到 done。

**接口关系** ：

* **被调用** ：directed regression 运行该 ASM。
* **调用** ：RISC-V ``csrw``、``ebreak``、``bne``、``sw``。
* **共享状态** ：``x31`` 是软件 flag，mailbox 是 pass/fail 观测点。

§7.2  trap handler 检查 ``mcause`` 并修正 ``mepc``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：trap handler 要求 ``mcause=3``，设置 flag，并根据指令低两位决定跳过 2 或
4 字节。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_debug_basic.S:L44-L84``）：

.. code-block:: bash

   // ---- Trap handler ----
   .align 4
   trap_handler:
       // Read mcause - should be 3 (breakpoint)
       csrr    t0, mcause
       li      t1, 3
       bne     t0, t1, trap_unexpected
   
       // Signal to main code that handler ran
       li      x31, 0xBEEF

**逐段解释** ：

* 第 L44-L50 行：handler 读取 ``mcause``，要求它等于 3，否则跳到 ``trap_unexpected``。
* 第 L52-L53 行：handler 把 ``x31`` 写为 ``0xBEEF``。
* 第 L55-L62 行：handler 读取 ``mepc`` 指向的 halfword，检查低两位是否为 ``0x3``。
* 第 L64-L74 行：32-bit 指令路径把 ``mepc`` 加 4；compressed 路径把 ``mepc`` 加 2；
  然后写回 ``mepc``。
* 第 L76-L77 行：``mret`` 返回。
* 第 L79-L84 行：unexpected trap cause 直接向 mailbox 写 ``0x01`` 并自旋。

**接口关系** ：

* **被调用** ：``ebreak`` trap 进入该 handler。
* **调用** ：RISC-V ``csrr``、``csrw``、``mret``。
* **共享状态** ：``mcause``、``mepc``、``x31`` 和 mailbox。

§8  Formal debug properties
--------------------------------------------------------------------------------

§8.1  ``eh2_dbg_assert`` 输入和 FSM 编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_dbg_assert`` 抽象 debug FSM、halt/resume handshake、DM register、
abstract command 和 DMI 输入，用 property 描述 debug 模块协议。

**关键代码** （``dv/formal/properties/eh2_dbg_assert.sv:L19-L68``）：

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

**逐段解释** ：

* 第 L19-L23 行：module import ``eh2_pkg`` 并 include 参数。
* 第 L24-L36 行：输入包括 clock/reset、per-thread ``dbg_state``、``dbg_state_en``、
  halt/resume request、debug mode、halted 和 resume ack。
* 第 L38-L55 行：输入还包括 ``dmcontrol_reg``、``dmstatus_reg``、``abstractcs_reg``、
  command 执行信号和 DMI register access 信号。
* 第 L58-L68 行：localparam 定义 FSM state，从 ``FSM_IDLE`` 到 ``FSM_RESUMING``。

**接口关系** ：

* **被调用** ：formal bind 将该 property 模块接到 debug 模块信号。
* **调用** ：SystemVerilog assertions。
* **共享状态** ：property 读取 debug FSM 和 DMI/DM register 输入。

§8.2  halt/resume 与 dmactive properties
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：formal property 检查 halt request 进入 HALTING、halted resume 进入
RESUMING、halt/resume 互斥、command done 后回到 HALTED、dmactive 关闭后回到 IDLE。

**关键代码** （``dv/formal/properties/eh2_dbg_assert.sv:L81-L143``）：

.. code-block:: systemverilog

     property p_halt_req_enters_halt_fsm;
       @(posedge clk) disable iff (~rst_l)
         (dbg_halt_req[0])
           |=>
         (fsm == FSM_HALTING);
     endproperty
     a_halt_req_enters_halt_fsm: assert property (p_halt_req_enters_halt_fsm)
       else $error("FORMAL FAIL: halt_req did not enter HALTING");
   
     // ========================================================================
     // Property 2: From HALTED, resume request transitions to RESUMING

**逐段解释** ：

* 第 L81-L88 行：``p_halt_req_enters_halt_fsm`` 要求 ``dbg_halt_req[0]`` 后 FSM 进入
  ``FSM_HALTING``。
* 第 L93-L100 行：``p_resume_from_halted`` 要求在 ``FSM_HALTED`` 且 resume request 和
  halted 为真时，下一步进入 ``FSM_RESUMING``。
* 第 L107-L112 行：``p_halt_resume_onehot`` 要求 ``dbg_halt_req[0]`` 与
  ``dbg_resume_req[0]`` 不能同时为真。
* 第 L121-L128 行：``p_cmd_done_clears_busy`` 要求进入 ``FSM_CMD_DONE`` 后回到
  ``FSM_HALTED``。
* 第 L136-L143 行：``p_dmactive_off_holds_idle`` 要求 ``dmcontrol_reg[0]`` 为 0 后 FSM
  处于 ``FSM_IDLE``。

**接口关系** ：

* **被调用** ：IFV formal run 证明。
* **调用** ：``$error``。
* **共享状态** ：读取 ``fsm``、``dbg_halt_req``、``dbg_resume_req``、``dec_tlu_dbg_halted``、
  ``dbg_state_en`` 和 ``dmcontrol_reg``。

§8.3  EBREAK decode 与顶层 debug status property
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：decode property 检查 ``ebreak`` decode 时产生 debug valid；顶层 SVA 检查
debug mode status 与内部 TLU status 一致。

**关键代码** （``dv/formal/properties/eh2_dec_assert.sv:L69-L114``）：

.. code-block:: systemverilog

     // Instruction encoding extracts
     wire [6:0]  i0_opcode = dec_i0_instr_d[6:0];
     wire [6:0]  i1_opcode = dec_i1_instr_d[6:0];
     wire [2:0]  i0_funct3 = dec_i0_instr_d[14:12];
     wire        i0_is_mret = (i0_opcode == 7'b1110011) && (i0_funct3 == 3'b000) &&
                              (dec_i0_instr_d[31:20] == 12'b001100000010);
     wire        i0_is_ebreak = (i0_opcode == 7'b1110011) && (i0_funct3 == 3'b000) &&
                                (dec_i0_instr_d[31:20] == 12'b000000000001);

**逐段解释** ：

* 第 L69-L77 行：property 文件从 ``dec_i0_instr_d`` 中解码 opcode、funct3、
  ``mret`` 和 ``ebreak``。
* 第 L108-L114 行：``p_ebreak_triggers_debug`` 要求当 i0 decode 是 ``ebreak`` 且当前
  thread 不在 debug mode 时，``dec_i0_debug_valid_d`` 为真。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L267-L277``）：

.. code-block:: systemverilog

     // =========================================================================
     // Category 8: Trace / Debug (2 assertions)
     // =========================================================================
     a_trace_valid_addr: assert property (@(posedge clk) disable iff (!rst_l)
       (!trace_rv_i_valid_ip[0][0] || !$isunknown(trace_rv_i_address_ip[0][31:0])) &&
       (!trace_rv_i_valid_ip[0][1] || !$isunknown(trace_rv_i_address_ip[0][63:32]))
     );
   
     a_debug_halt_track: assert property (@(posedge clk) disable iff (!rst_l)

**逐段解释** ：

* 第 L267-L273 行：同一 category 先检查 trace valid 时地址不为 unknown。
* 第 L275-L277 行：``a_debug_halt_track`` 要求 top-level ``o_debug_mode_status[0]``
  等于内部 ``dec.tlu.o_debug_mode_status[0]``。
* 第 L363-L368 行还定义 ``c_halt_handshake`` cover，要求 reset 释放、非 scan mode 且
  ``o_cpu_halt_ack[0]`` 不是 unknown。

**接口关系** ：

* **被调用** ：IFV formal run 证明或覆盖。
* **调用** ：SystemVerilog assertions/cover property。
* **共享状态** ：读取 decode 指令字段、TLU debug mode、trace 和 top-level debug status。

§9  参考资料
--------------------------------------------------------------------------------

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq_item.sv` — JTAG/DMI transaction。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_seq.sv` — JTAG sequence helper。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_driver.sv` — JTAG TAP 与 DMI scan driver。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/jtag_agent/eh2_jtag_intf.sv` — JTAG virtual interface。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_intf.sv` — halt/run virtual interface。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/halt_run_agent/eh2_halt_run_driver.sv` — halt/run driver。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv` — ``debug_seq``。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv` — debug test helper 与 debug test class。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_debug_basic.S` — directed EBREAK stimulus。
* :file:`/home/host/eh2-veri/dv/formal/properties/eh2_dbg_assert.sv` — debug FSM property。
* :file:`/home/host/eh2-veri/dv/formal/properties/eh2_dec_assert.sv` — EBREAK decode property。
* :file:`/home/host/eh2-veri/dv/formal/eh2_veer_sva.sv` — top-level trace/debug property。
* :ref:`appendix_b_uvm/jtag_agent` — JTAG agent 字典。
* :ref:`appendix_b_uvm/halt_run_agent` — halt/run agent 字典。
* :ref:`adr-0008` — Debug Cosim。
