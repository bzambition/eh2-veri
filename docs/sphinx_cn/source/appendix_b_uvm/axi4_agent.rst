.. _appendix_b_uvm_axi4_agent:
.. _appendix_b_uvm/axi4_agent:

AXI4 Agent 源码字典
===================

:status: draft
:source: dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 :file:`dv/uvm/core_eh2/common/axi4_agent/` 下的 AXI4 UVM agent。该 agent
既可以 passive 监视 AXI4 transaction，也可以在 LSU error injection 场景下 active
驱动 error sideband。当前 env 中实际实例化 3 个 AXI4 agent：``lsu_agent``、
``ifu_agent``、``sb_agent``。DUT 顶层存在 DMA AXI4 wire，但
:file:`dv/uvm/core_eh2/env/core_eh2_env.sv` 没有创建 ``dma_agent``。

本章覆盖 6 个源文件：

* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_agent_pkg.sv`
* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv`
* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv`
* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv`
* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_sequencer.sv`
* :file:`dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv`

§1.1  数据流总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

AXI4 monitor 从 virtual interface 采集 AW/W/B 或 AR/R 通道，并通过 analysis port
输出 ``axi4_seq_item``。cosim 只连接 LSU agent 的 analysis port；IFU 和 SB agent
在 env 中被创建并绑定 virtual interface，但不会接入 cosim scoreboard。

::

   core_eh2_tb_top.sv
      |
      +-- lsu_axi_intf --> lsu_agent.monitor.ap --> cosim_agt.dmem_port
      |
      +-- ifu_axi_intf --> ifu_agent.monitor.ap
      |
      +-- sb_axi_intf  --> sb_agent.monitor.ap

当 ``cfg.enable_axi4_error_inject`` 为真时，``lsu_agent`` 被配置为
``UVM_ACTIVE``，其 driver 通过 ``error_inject_mode``、``force_bresp`` 和
``force_rresp`` sideband 影响 slave memory 响应。

接口关系：

* 被调用：``core_eh2_env`` 在 build phase 创建 ``lsu_agent``、``ifu_agent`` 和
  ``sb_agent``。
* 调用：monitor 调用 analysis port ``ap.write(txn)``；driver 驱动 ``axi4_intf``
  sideband。
* 共享状态：virtual ``axi4_intf``、``axi4_seq_item``、``cfg.enable_axi4_error_inject``。

§2  ``axi4_agent_pkg.sv`` — package 汇入顺序
------------------------------------------------------------------------------------------------------------------------

职责：package 定义 AXI4 agent 的编译单元，并按组件依赖顺序 include sequence item、
driver、monitor、sequencer 和 agent。

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_agent_pkg.sv:L8-L18``）：

.. code-block:: systemverilog

   package axi4_agent_pkg;

     `include "uvm_macros.svh"
     import uvm_pkg::*;

     // Agent components
     `include "axi4_seq_item.sv"
     `include "axi4_driver.sv"
     `include "axi4_monitor.sv"
     `include "axi4_sequencer.sv"
     `include "axi4_agent.sv"

逐段解释：

* 第 8 行：声明 ``axi4_agent_pkg``。
* 第 10~11 行：引入 UVM 宏和 ``uvm_pkg``。
* 第 14 行：先 include ``axi4_seq_item.sv``，因为 driver、monitor 和 sequencer 都使用
  ``axi4_seq_item``。
* 第 15~18 行：driver、monitor、sequencer 先于 top-level agent include，因为
  ``axi4_agent`` 内部声明这些 component 类型。

接口关系：

* 被调用：env package 和 cosim package 通过 ``import axi4_agent_pkg::*`` 使用 AXI4
  类型。
* 调用：SystemVerilog include。
* 共享状态：无运行期状态。

§3  ``axi4_seq_item.sv`` — transaction 对象
------------------------------------------------------------------------------------------------------------------------

职责：``axi4_seq_item`` 封装一笔 AXI4 read 或 write transaction，包括地址 phase、
burst 参数、写数据/写 strobe、读数据/响应和时间戳。

§3.1  enum 与字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv:L18-L56``）：

.. code-block:: systemverilog

   class axi4_seq_item extends uvm_sequence_item;

     // Transaction type
     typedef enum bit { AXI4_READ = 0, AXI4_WRITE = 1 } tx_type_e;

     // Burst type
     typedef enum bit [1:0] {
       AXI4_BURST_FIXED = 2'b00,
       AXI4_BURST_INCR  = 2'b01,
       AXI4_BURST_WRAP  = 2'b10
     } burst_type_e;

     // Response type
     typedef enum bit [1:0] {
       AXI4_RESP_OKAY   = 2'b00,
       AXI4_RESP_EXOKAY = 2'b01,
       AXI4_RESP_SLVERR = 2'b10,
       AXI4_RESP_DECERR = 2'b11
     } resp_type_e;

     // Transaction fields
     rand tx_type_e    tx_type;

逐段解释：

* 第 18 行：transaction class 继承 ``uvm_sequence_item``。
* 第 20~21 行：``tx_type_e`` 只有 read/write 两种，read 为 0，write 为 1。
* 第 23~28 行：burst enum 覆盖 FIXED、INCR、WRAP。
* 第 30~36 行：response enum 覆盖 OKAY、EXOKAY、SLVERR、DECERR。
* 第 38~56 行：源文件随后定义 ``addr``、``id``、``len``、``size``、``burst``、
  ``data[]``、``strb[]``、``rdata[]``、``resp[]``、``start_time`` 和 ``end_time``。

接口关系：

* 被调用：driver、monitor、sequencer 和 cosim scoreboard 使用该 transaction 类型。
* 调用：无下层函数。
* 共享状态：transaction 字段由 monitor 填充、scoreboard 读取。

§3.2  UVM field automation、约束与 helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv:L58-L103``）：

.. code-block:: systemverilog

     `uvm_object_utils_begin(axi4_seq_item)
       `uvm_field_enum(tx_type_e, tx_type, UVM_ALL_ON)
       `uvm_field_int(addr, UVM_ALL_ON)
       `uvm_field_int(id, UVM_ALL_ON)
       `uvm_field_int(len, UVM_ALL_ON)
       `uvm_field_int(size, UVM_ALL_ON)
       `uvm_field_enum(burst_type_e, burst, UVM_ALL_ON)
       `uvm_field_array_int(data, UVM_ALL_ON)
       `uvm_field_array_int(strb, UVM_ALL_ON)
       `uvm_field_array_int(rdata, UVM_ALL_ON)
     `uvm_object_utils_end

     function new(string name = "axi4_seq_item");
       super.new(name);
     endfunction

     // Constraint: reasonable burst lengths
     constraint c_reasonable_len {
       len inside {[0:15]};  // Max 16 beats
     }

逐段解释：

* 第 58~68 行：UVM field automation 注册 transaction 类型、地址、ID、burst 参数、
  data/strb/rdata 数组。``resp``、``start_time`` 和 ``end_time`` 没有出现在该宏块中。
* 第 70~72 行：构造函数默认对象名是 ``axi4_seq_item``。
* 第 74~77 行：``c_reasonable_len`` 把 ``len`` 限制到 0~15，即最多 16 beats。
* 第 79~82 行：源文件随后用 ``c_valid_size`` 限制 ``size <= 3``，即最大 8 bytes per
  beat。
* 第 84~103 行：helper 包含 ``get_beat_count``、``get_beat_bytes``、
  ``get_total_bytes`` 和 ``convert2string``。

接口关系：

* 被调用：monitor 创建 item 后填字段；driver 可从 sequencer 接收 item。
* 调用：``$sformatf``。
* 共享状态：UVM field automation 覆盖的 transaction 字段。

§4  ``axi4_monitor.sv`` — 被动事务采集
------------------------------------------------------------------------------------------------------------------------

职责：monitor 从 virtual ``axi4_intf`` 采集完整 read/write transaction，并通过
``ap`` 广播给外部。write 路径在 AW 和 W 收齐后立即发布 transaction，不等待 B
handshake。

§4.1  build/connect/run phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L16-L51``）：

.. code-block:: systemverilog

   class axi4_monitor #(int ID_WIDTH = 4) extends uvm_monitor;

     `uvm_component_param_utils(axi4_monitor#(ID_WIDTH))

     // Virtual interface
     virtual axi4_intf#(.ID_WIDTH(ID_WIDTH)) vif;

     // Analysis port for transactions
     uvm_analysis_port #(axi4_seq_item) ap;

     // Configuration
     string agent_name = "axi4_monitor";

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       ap = new("ap", this);

逐段解释：

* 第 16~18 行：monitor 是参数化 component，参数是 ``ID_WIDTH``。
* 第 20~24 行：monitor 保存 virtual ``axi4_intf`` 和 analysis port ``ap``。
* 第 26~31 行：``agent_name`` 默认 ``axi4_monitor``，构造函数只调用父类。
* 第 33~36 行：build phase 创建 analysis port。
* 第 38~43 行：源文件随后从 ``uvm_config_db`` 获取 virtual interface；失败时只发
  ``uvm_warning``，monitor 后续会跳过采集。
* 第 45~50 行：run phase 在 ``vif`` 非空时 fork ``monitor_writes`` 和
  ``monitor_reads``。

接口关系：

* 被调用：``axi4_agent`` build phase 创建 monitor。
* 调用：``uvm_config_db::get``、``monitor_writes``、``monitor_reads``。
* 共享状态：``vif`` 和 ``ap``。

§4.2  write address phase 与 transaction 创建
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L53-L88``）：

.. code-block:: systemverilog

     // Monitor write transactions (AW -> W -> B)
     task monitor_writes();
       axi4_seq_item txn;
       bit [7:0] awlen;
       bit [2:0] awsize;
       bit [1:0] awburst;
       bit [31:0] awaddr;
       bit [3:0] awid;
       int beat_count;

       forever begin
         // Wait for AW handshake (address phase)
         @(posedge vif.clk iff (vif.awvalid && vif.awready));

         // Capture address phase
         awaddr  = vif.awaddr;
         awlen   = vif.awlen;
         awsize  = vif.awsize;
         awburst = vif.awburst;
         awid    = vif.awid;

逐段解释：

* 第 53~61 行：write monitor 声明 transaction、AW channel 字段和 beat count。
* 第 63~65 行：任务在每轮循环中等待 ``awvalid && awready`` 的时钟沿。
* 第 67~72 行：在 AW handshake 边沿采样 ``awaddr``、``awlen``、``awsize``、
  ``awburst`` 和 ``awid``。
* 第 74~82 行：源文件随后创建 ``write_txn``，设置 ``tx_type=AXI4_WRITE``、
  地址、ID、len、size、burst 和 ``start_time``。
* 第 84~88 行：beat count 为 ``awlen + 1``，并分配 ``data`` 与 ``strb`` 数组。

接口关系：

* 被调用：``monitor.run_phase`` fork。
* 调用：``axi4_seq_item::type_id::create``。
* 共享状态：``vif`` 和 ``txn``。

§4.3  W beat 收集与提前发布
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L89-L117``）：

.. code-block:: systemverilog

         // Collect W channel data beats
         for (int i = 0; i < beat_count; i++) begin
           // AW and W are independent AXI channels and EH2 can handshake both on
           // the same clock. If W is already valid on the AW sample edge, consume
           // it immediately instead of waiting for a later edge and losing the
           // beat.
           if (!(vif.wvalid && vif.wready)) begin
             @(posedge vif.clk iff (vif.wvalid && vif.wready));
           end
           txn.data[i] = vif.wdata;
           txn.strb[i] = vif.wstrb;
         end

         txn.resp = new[1];
         txn.resp[0] = axi4_seq_item::AXI4_RESP_OKAY;
         txn.end_time = $time;

         // Send to analysis port as soon as address and data are complete. EH2

逐段解释：

* 第 89~97 行：W channel 收集循环按 beat 数执行。注释说明 AW 和 W 独立，EH2 可能在
  同一时钟 handshake；若当前边沿已经 ``wvalid && wready``，monitor 立即消费。
* 第 98~100 行：每个 beat 采样 ``wdata`` 和 ``wstrb``。
* 第 102~104 行：response 数组只有 1 项，先填 ``AXI4_RESP_OKAY``，并记录
  ``end_time``。
* 第 106~110 行：源文件在地址和数据完成后立即 ``ap.write(txn)``。注释说明等待 B
  可能让 cosim scoreboard 饿死，因为 EH2 可能在 write response 可见前 retire store。
* 第 112~116 行：若 B handshake 已可见，再把 ``bresp`` 写回 ``txn.resp[0]``，但这不阻塞
  已发布 transaction。

接口关系：

* 被调用：``monitor_writes``。
* 调用：``ap.write``。
* 共享状态：``txn.data``、``txn.strb``、``txn.resp``。

§4.4  read transaction 采集
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L120-L168``）：

.. code-block:: systemverilog

     // Monitor read transactions (AR -> R)
     task monitor_reads();
       axi4_seq_item txn;
       bit [7:0] arlen;
       bit [2:0] arsize;
       bit [1:0] arburst;
       bit [31:0] araddr;
       bit [3:0] arid;
       int beat_count;

       forever begin
         // Wait for AR handshake (address phase)
         @(posedge vif.clk iff (vif.arvalid && vif.arready));

         // Capture address phase
         araddr  = vif.araddr;
         arlen   = vif.arlen;
         arsize  = vif.arsize;
         arburst = vif.arburst;

逐段解释：

* 第 120~128 行：read monitor 声明 transaction、AR channel 字段和 beat count。
* 第 130~132 行：等待 ``arvalid && arready``。
* 第 134~139 行：采样 ``araddr``、``arlen``、``arsize``、``arburst`` 和 ``arid``。
* 第 141~154 行：源文件随后创建 ``read_txn``，设置 read transaction 字段，分配
  ``rdata`` 和 ``resp`` 数组。
* 第 156~161 行：逐 beat 等待 ``rvalid && rready``，采样 ``rdata`` 和 ``rresp``。
* 第 163~167 行：全部 beat 完成后记录 ``end_time``，打印日志，并 ``ap.write(txn)``。

接口关系：

* 被调用：``monitor.run_phase`` fork。
* 调用：``axi4_seq_item::type_id::create``、``ap.write``。
* 共享状态：``txn.rdata`` 和 ``txn.resp``。

§5  ``axi4_driver.sv`` — error injection sideband
------------------------------------------------------------------------------------------------------------------------

职责：driver 不是完整 AXI4 slave，也不替换 ``axi4_slave_mem``。它在 active 模式下监听
AR/AW handshake，并通过 ``axi4_intf`` 上的 ``error_inject_mode``、``force_bresp``、
``force_rresp`` sideband 控制 response error 注入。

§5.1  driver 配置和 passive/active 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L23-L85``）：

.. code-block:: systemverilog

   class axi4_driver #(int ID_WIDTH = 4) extends uvm_driver #(axi4_seq_item);

     `uvm_component_param_utils(axi4_driver#(ID_WIDTH))

     // Virtual interface
     virtual axi4_intf#(.ID_WIDTH(ID_WIDTH)) vif;

     // Configuration
     string agent_name = "axi4_driver";
     int    rsp_delay = 0;           // Response delay in clock cycles
     bit    enable_error_inject = 0; // Enable error injection
     int    error_pct = 5;           // Error injection percentage (0-100)
     bit    enable_delay_inject = 0; // Enable random response delays
     int    min_delay = 0;           // Min response delay cycles
     int    max_delay = 10;          // Max response delay cycles

逐段解释：

* 第 23~25 行：driver 是参数化 UVM driver，sequence item 类型为 ``axi4_seq_item``。
* 第 27~28 行：driver 通过 virtual ``axi4_intf`` 访问 AXI4 channel 和 error injection
  sideband。
* 第 30~37 行：配置字段包括 ``rsp_delay``、``enable_error_inject``、``error_pct``、
  delay injection 开关以及 delay 范围。当前源码中 response delay helper 存在，但
  read/write injection task 未调用 delay helper。
* 第 39~51 行：源文件随后定义 response enum 和读写 error/total 统计计数。
* 第 57~62 行：connect phase 必须从 ``uvm_config_db`` 取得 ``vif``，失败是
  ``uvm_fatal``。
* 第 64~85 行：run phase 先清 sideband；``enable_error_inject`` 为 0 时只每拍等待，
  为 1 时 fork read/write error injection task。

接口关系：

* 被调用：``axi4_agent`` 在 active 模式下创建 driver。
* 调用：``uvm_config_db::get``、``inject_read_errors``、``inject_write_errors``。
* 共享状态：``vif.error_inject_mode``、``vif.force_bresp``、``vif.force_rresp``。

§5.2  read error injection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L87-L119``）：

.. code-block:: systemverilog

     //----------------------------------------------------------------------------
     // Read channel error injection
     //   Watch for AR handshake, decide error/okay, set sideband, wait for R
     //   completion (rlast+rvalid+rready), then clear sideband.
     //----------------------------------------------------------------------------
     task inject_read_errors();
       forever begin
         // Wait for AR handshake
         @(posedge vif.clk iff (vif.arvalid && vif.arready));

         num_read_total++;

         if (should_inject_error()) begin
           bit [1:0] err_resp = get_error_resp();
           `uvm_info(agent_name, $sformatf(
             "INJECT read error resp=%s addr=0x%08x id=%0d",
             (err_resp == RESP_SLVERR) ? "SLVERR" : "DECERR",

逐段解释：

* 第 87~91 行：注释定义 read injection 流程：等待 AR，决定 error/OK，设置 sideband，
  等待 R 完成，再清 sideband。
* 第 92~97 行：任务循环等待 ``arvalid && arready``，每次 handshake 增加
  ``num_read_total``。
* 第 99~104 行：``should_inject_error`` 为真时随机选择 response，并打印地址和 ID。
* 第 106~111 行：源文件随后置 ``error_inject_mode``、``force_rresp``，递增
  ``num_read_errors``，并等到 ``rvalid && rready && rlast``。
* 第 113~115 行：R 最后一拍完成后清 ``error_inject_mode`` 和 ``force_rresp``。

接口关系：

* 被调用：driver ``run_phase`` active 分支。
* 调用：``should_inject_error``、``get_error_resp``。
* 共享状态：read error 统计和 ``vif.force_rresp``。

§5.3  write error injection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L121-L153``）：

.. code-block:: systemverilog

     //----------------------------------------------------------------------------
     // Write channel error injection
     //   Watch for AW handshake, decide error/okay, set sideband, wait for B
     //   handshake, then clear sideband.
     //----------------------------------------------------------------------------
     task inject_write_errors();
       forever begin
         // Wait for AW handshake
         @(posedge vif.clk iff (vif.awvalid && vif.awready));

         num_write_total++;

         if (should_inject_error()) begin
           bit [1:0] err_resp = get_error_resp();
           `uvm_info(agent_name, $sformatf(
             "INJECT write error resp=%s addr=0x%08x id=%0d",
             (err_resp == RESP_SLVERR) ? "SLVERR" : "DECERR",

逐段解释：

* 第 121~125 行：注释定义 write injection 流程：等待 AW，决定 error/OK，设置 sideband，
  等待 B handshake，再清 sideband。
* 第 126~131 行：任务循环等待 ``awvalid && awready``，并递增 ``num_write_total``。
* 第 133~138 行：需要注入时选择 SLVERR 或 DECERR，并打印 AW 地址和 ID。
* 第 140~145 行：源文件随后置 ``error_inject_mode`` 和 ``force_bresp``，递增
  ``num_write_errors``，并等待 ``bvalid && bready``。
* 第 147~149 行：B handshake 后清 ``error_inject_mode`` 和 ``force_bresp``。

接口关系：

* 被调用：driver ``run_phase`` active 分支。
* 调用：``should_inject_error``、``get_error_resp``。
* 共享状态：write error 统计和 ``vif.force_bresp``。

§5.4  random helper 与 report
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv:L155-L183``）：

.. code-block:: systemverilog

     // Check if error should be injected (random)
     function bit should_inject_error();
       if (!enable_error_inject) return 0;
       return ($urandom_range(0, 99) < error_pct);
     endfunction

     // Get error response type (random SLVERR or DECERR)
     function bit [1:0] get_error_resp();
       if ($urandom_range(0, 1) == 0)
         return RESP_SLVERR;
       else
         return RESP_DECERR;
     endfunction

     // Get random delay for response
     function int get_random_delay();
       if (!enable_delay_inject) return rsp_delay;

逐段解释：

* 第 155~159 行：``should_inject_error`` 先检查 ``enable_error_inject``，再用
  ``$urandom_range(0, 99) < error_pct`` 判断是否注入。
* 第 161~167 行：``get_error_resp`` 在 SLVERR 和 DECERR 之间随机选择。
* 第 169~173 行：``get_random_delay`` 在 delay injection 关闭时返回 ``rsp_delay``，
  否则返回 ``min_delay`` 到 ``max_delay`` 的随机值。当前 read/write injection task
  未调用该函数。
* 第 175~183 行：report phase 只在 ``enable_error_inject`` 为真时打印
  ``reads=%0d/%0d writes=%0d/%0d``。

接口关系：

* 被调用：read/write injection task 和 report phase。
* 调用：``$urandom_range``。
* 共享状态：``enable_error_inject``、``error_pct``、delay 字段和统计计数。

§6  ``axi4_agent.sv`` 与 ``axi4_sequencer.sv``
------------------------------------------------------------------------------------------------------------------------

职责：top-level agent 负责创建 monitor、按 active/passive 模式创建 driver/sequencer，
并把 monitor 的 analysis port 暴露为 agent 的 ``ap``。

§6.1  sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_sequencer.sv:L7-L15``）：

.. code-block:: systemverilog

   class axi4_sequencer extends uvm_sequencer #(axi4_seq_item);

     `uvm_component_utils(axi4_sequencer)

     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

   endclass

逐段解释：

* 第 7 行：sequencer 直接继承 ``uvm_sequencer #(axi4_seq_item)``。
* 第 9 行：使用非参数化 component utils 注册。
* 第 11~13 行：构造函数只调用父类。

接口关系：

* 被调用：``axi4_agent`` 在 active 模式下创建。
* 调用：无下层函数。
* 共享状态：sequence item 类型为 ``axi4_seq_item``。

§6.2  agent build/connect phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv:L17-L59``）：

.. code-block:: systemverilog

   class axi4_agent #(int ID_WIDTH = 4) extends uvm_agent;

     `uvm_component_param_utils(axi4_agent#(ID_WIDTH))

     // Components
     axi4_driver#(ID_WIDTH) driver;
     axi4_monitor#(ID_WIDTH) monitor;
     axi4_sequencer sequencer;

     // Analysis port (from monitor)
     uvm_analysis_port #(axi4_seq_item) ap;

     // Configuration
     string agent_name = "axi4_agent";

     function new(string name, uvm_component parent);
       super.new(name, parent);

逐段解释：

* 第 17~24 行：agent 是参数化 UVM agent，持有 driver、monitor 和 sequencer。
* 第 26~30 行：``ap`` 是从 monitor 暴露出来的 analysis port，``agent_name`` 默认
  ``axi4_agent``。
* 第 36~40 行：build phase 始终创建 monitor。
* 第 42~46 行：只有 ``get_is_active() == UVM_ACTIVE`` 时才创建 driver 和 sequencer。
* 第 49~58 行：connect phase 把 ``ap`` 指向 ``monitor.ap``；active 模式下还连接
  ``driver.seq_item_port`` 到 ``sequencer.seq_item_export``。

接口关系：

* 被调用：``core_eh2_env`` 创建 LSU/IFU/SB 三个 agent。
* 调用：``axi4_monitor::type_id::create``、``axi4_driver::type_id::create``、
  ``axi4_sequencer::type_id::create``。
* 共享状态：``get_is_active`` 决定 driver/sequencer 是否存在。

§7  env 与 tb_top 连接关系
------------------------------------------------------------------------------------------------------------------------

职责：AXI4 agent 的真实实例数量、active/passive 配置和 virtual interface 绑定都来自
env 与 tb_top。旧文档中“4 个端口监视”不能直接写成“4 个 agent”，因为源码只创建
LSU/IFU/SB 三个 agent。

§7.1  env 中的 3 个 agent 声明与 active/passive 设置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L28-L85``）：

.. code-block:: systemverilog

     // AXI4 agents (passive - monitor only)
     axi4_agent#(`RV_LSU_BUS_TAG) lsu_agent;
     axi4_agent#(`RV_IFU_BUS_TAG) ifu_agent;
     axi4_agent#(`RV_SB_BUS_TAG) sb_agent;

     // Interrupt agent (active - drives interrupts)
     eh2_irq_agent irq_agent;

     // JTAG agent (active - drives debug)
     eh2_jtag_agent jtag_agent;

     // Halt/Run agent (active - drives halt/run)
     eh2_halt_run_agent halt_run_agt;

逐段解释：

* 第 28~31 行：env 声明 3 个 AXI4 agent，ID width 分别来自 ``RV_LSU_BUS_TAG``、
  ``RV_IFU_BUS_TAG`` 和 ``RV_SB_BUS_TAG``。
* 第 33~40 行：这些行之后声明 IRQ、JTAG、halt/run agent；这里没有 DMA AXI4 agent
  声明。
* 第 73~79 行：源文件随后创建 ``lsu_agent``，当 ``cfg.enable_axi4_error_inject`` 为真
  时设置 active，否则设置 passive。
* 第 81~85 行：``ifu_agent`` 和 ``sb_agent`` 都创建后设置为 ``UVM_PASSIVE``。

接口关系：

* 被调用：``core_eh2_env.build_phase``。
* 调用：``axi4_agent#(...)::type_id::create`` 和 ``uvm_config_db::set``。
* 共享状态：``cfg.enable_axi4_error_inject``。

§7.2  env connect phase 中的 LSU error injection 与 cosim 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L141-L164``）：

.. code-block:: systemverilog

     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);

       // Configure AXI4 error injection on LSU driver (driver is now built)
       if (cfg.enable_axi4_error_inject && lsu_agent.driver != null) begin
         lsu_agent.driver.enable_error_inject = 1;
         lsu_agent.driver.error_pct           = cfg.axi4_error_pct;
         `uvm_info("env", $sformatf("AXI4 error injection enabled on LSU (pct=%0d)", cfg.axi4_error_pct), UVM_LOW)
       end

       // Connect trace monitor to co-simulation agent's scoreboard
       if (cfg.enable_cosim && cosim_agt != null) begin
         trace_monitor.ap.connect(cosim_agt.scoreboard.trace_fifo.analysis_export);
       end

逐段解释：

* 第 141~148 行：connect phase 时 driver 已经 build 完成，因此 env 在这里给
  ``lsu_agent.driver`` 设置 ``enable_error_inject`` 和 ``error_pct``。
* 第 151~159 行：源文件随后连接 trace/probe monitor 到 cosim scoreboard。
* 第 161~164 行：只有 ``lsu_agent.ap`` 连接到 ``cosim_agt.dmem_port``。IFU/SB 的
  ``ap`` 没有在此处接入 cosim agent。

接口关系：

* 被调用：``core_eh2_env.connect_phase``。
* 调用：driver 字段赋值和 TLM ``connect``。
* 共享状态：``cfg.axi4_error_pct`` 和 ``cfg.enable_cosim``。

§7.3  tb_top virtual interface 实例与 config_db
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L591-L603``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // AXI4 Interface Instances (for UVM agents)
     // Use DUT's actual tag widths to avoid truncation/extension issues
     //--------------------------------------------------------------------------
     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_LSU_BUS_TAG))
       lsu_axi_intf (.clk(core_clk), .rst_n(rst_l));

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_IFU_BUS_TAG))
       ifu_axi_intf (.clk(core_clk), .rst_n(rst_l));

     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_SB_BUS_TAG))
       sb_axi_intf (.clk(core_clk), .rst_n(rst_l));

逐段解释：

* 第 591~594 行：tb_top 注释说明 AXI4 interface instance 用于 UVM agents，并使用 DUT
  实际 tag width 避免截断或扩展问题。
* 第 595~596 行：LSU interface 的 ID width 是 ``RV_LSU_BUS_TAG``。
* 第 598~599 行：IFU interface 的 ID width 是 ``RV_IFU_BUS_TAG``。
* 第 601~602 行：SB interface 的 ID width 是 ``RV_SB_BUS_TAG``。
* 第 604~715 行：源文件随后把 DUT LSU/IFU/SB AXI wires 逐项 assign 到对应 interface。

接口关系：

* 被调用：UVM config_db 把这些 virtual interface 提供给 agent。
* 调用：SystemVerilog continuous assignment。
* 共享状态：``core_clk``、``rst_l`` 和各 AXI wire。

§7.4  tb_top config_db 绑定
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1102-L1114``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // UVM Config DB Setup
     //--------------------------------------------------------------------------
     initial begin
       // Store interface references for UVM agents
       uvm_config_db#(virtual core_eh2_tb_intf)::set(null, "*", "tb_vif", tb_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_LSU_BUS_TAG)))::set(null, "*lsu_agent*", "vif", lsu_axi_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_IFU_BUS_TAG)))::set(null, "*ifu_agent*", "vif", ifu_axi_intf);
       uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_SB_BUS_TAG)))::set(null, "*sb_agent*",  "vif", sb_axi_intf);

       // Store trace and DUT probe interfaces
       uvm_config_db#(virtual eh2_trace_intf)::set(null, "*trace_monitor*", "vif", trace_intf);
       uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*dut_probe_monitor*", "vif", dut_probe_intf);

逐段解释：

* 第 1102~1107 行：initial block 开始后先绑定通用 ``tb_vif``。
* 第 1108~1110 行：分别把 ``lsu_axi_intf``、``ifu_axi_intf`` 和 ``sb_axi_intf`` 绑定到
  ``*lsu_agent*``、``*ifu_agent*``、``*sb_agent*`` 的 ``vif`` 字段。
* 第 1112~1114 行：同一 initial block 还绑定 trace monitor 和 DUT probe monitor 的
  virtual interface。

接口关系：

* 被调用：monitor/driver connect phase 的 ``uvm_config_db::get``。
* 调用：``uvm_config_db::set``。
* 共享状态：3 个 virtual AXI4 interface。

§8  与 cosim scoreboard 的接口
------------------------------------------------------------------------------------------------------------------------

职责：AXI4 agent 与 cosim scoreboard 的直接接口只有 LSU dmem path。scoreboard 使用
``axi4_seq_item`` 的 ``tx_type``、``data``、``strb``、``rdata`` 和 ``resp`` 字段来通知
Spike D-side 访问。

关键代码（``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L449-L456``）：

.. code-block:: systemverilog

     function void enqueue_memory_accesses(axi4_seq_item txn);
       pending_mem_access_t access;
       access.txn = txn;
       access.is_store = (txn.tx_type == axi4_seq_item::AXI4_WRITE);
       access.observed_access_count = count_observed_memory_accesses(txn);
       pending_mem_access_q.push_back(access);
       if (access.is_store) store_axi_delivered++;
     endfunction

逐段解释：

* 第 449~454 行：scoreboard 把 AXI4 transaction 包装成 pending memory access，并通过
  ``tx_type`` 判断是否 store。
* 第 455 行：store transaction 会递增 ``store_axi_delivered``，用于 store-buffer
  coalescing 判断。
* 第 458~562 行：源文件随后统计 observed access，并用
  ``riscv_cosim_notify_dside_access`` 把 AXI4 read/write beat 通知 Spike。

接口关系：

* 被调用：``run_cosim_dmem`` 从 ``lsu_axi_fifo`` 取到 transaction 后调用。
* 调用：``count_observed_memory_accesses``。
* 共享状态：``pending_mem_access_q`` 和 ``store_axi_delivered``。

§9  参考资料
------------------------------------------------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0002`：AXI4 passive monitoring。
* :ref:`adr-0017`：fault injection 类测试的 cosim waiver 边界。

关联章节：

* :ref:`agent_axi4`：架构层 AXI4 agent 说明。
* :ref:`appendix_b_uvm/cosim_agent`：cosim agent 如何消费 LSU AXI4 transaction。
* :doc:`env`：UVM env 中的 agent 实例化与连接。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_agent_pkg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_sequencer.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_agent.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`

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
