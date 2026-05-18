.. _bus_axi_ahb:
.. _02_core_reference/bus_axi_ahb:

AXI4 / AHB-Lite 总线接口
================================================================================

:status: draft
:source: shared/rtl/axi4_pkg.sv; shared/rtl/axi4_intf.sv; shared/rtl/axi4_slave_mem.sv; dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv; dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv; rtl/lec_shim/eh2_veer_lec_pack.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  源码边界
--------------------------------------------------------------------------------

本章只描述当前源码树中可直接回溯的总线接口。验证平台的可观测主路径是
``core_eh2_tb_top`` 中三组 AXI4 master 端口：``lsu_axi_*``、``ifu_axi_*`` 和
``sb_axi_*``。同一个 TB 还把 ``dma_axi_*`` 输入绑为非活动值，源码注释写明该
basic testbench 没有外部 DMA master。

AHB-Lite 相关信号在 :file:`rtl/lec_shim/eh2_veer_lec_pack.sv` 的端口列表中出现。
本章不把这些 LEC shim 端口扩展成未在 TB 中实例化的行为模型，也不推断运行时
协议切换策略。

总线观测链路如下：

.. code-block:: text

   DUT AXI4 pins
      |
      |-- lsu_axi_* --> axi4_slave_mem lsu_mem --> axi4_intf lsu_axi_intf
      |                                           |
      |                                           `-- axi4_monitor --> cosim scoreboard
      |
      |-- ifu_axi_* --> axi4_slave_mem ifu_mem --> axi4_intf ifu_axi_intf
      |
      `-- sb_axi_*  --> axi4_slave_mem sb_mem  --> axi4_intf sb_axi_intf

**逐段解释** ：

* ``axi4_slave_mem`` 是 TB 中的行为内存，从 DUT 的 AXI4 master 端口接收读写。
* ``axi4_intf`` 是 UVM agent 使用的虚接口包装，它复制 DUT wires 上的 AXI4
  信号，供 monitor、driver 和协议断言访问。
* cosim scoreboard 当前只消费 LSU AXI4 monitor 送来的数据侧访问，用于把 64-bit
  beat 拆成 Spike 的 32-bit dside 通知。

**接口关系** ：

* **被调用** ：本章服务于 :ref:`tb_top`、:ref:`agent_axi4` 和
  :ref:`cosim_scoreboard` 的读者。
* **调用** ：无运行时代码调用；文档引用 SystemVerilog 接口、TB 连接和 UVM monitor。
* **共享状态** ：总线信号通过 ``core_eh2_tb_top`` 中的 wires、``axi4_intf`` 虚接口
  和 ``lsu_axi_fifo`` 进入验证组件。

§2  AXI4 常量定义
--------------------------------------------------------------------------------

§2.1  ``axi4_pkg`` 的 burst、response 与 size 编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_pkg`` 给验证平台提供 AXI4 常量。它不是 DUT 逻辑的一部分，而是
共享给 TB、agent 或工具侧代码使用的协议枚举来源。

**关键代码** （``shared/rtl/axi4_pkg.sv:L8-L33``）：

.. code-block:: systemverilog

   package axi4_pkg;
   
     // AXI4 Burst Types
     localparam [1:0] AXI_BURST_FIXED = 2'b00;
     localparam [1:0] AXI_BURST_INCR  = 2'b01;
     localparam [1:0] AXI_BURST_WRAP  = 2'b10;
   
     // AXI4 Response Codes
     localparam [1:0] AXI_RESP_OKAY   = 2'b00;
     localparam [1:0] AXI_RESP_EXOKAY = 2'b01;
     localparam [1:0] AXI_RESP_SLVERR = 2'b10;
     localparam [1:0] AXI_RESP_DECERR = 2'b11;
   
     // AXI4 Lock Types
     localparam AXI_LOCK_NORMAL    = 1'b0;
     localparam AXI_LOCK_EXCLUSIVE = 1'b1;
   
     // AXI4 Size Encoding
     localparam [2:0] AXI_SIZE_1B   = 3'b000;
     localparam [2:0] AXI_SIZE_2B   = 3'b001;
     localparam [2:0] AXI_SIZE_4B   = 3'b010;
     localparam [2:0] AXI_SIZE_8B   = 3'b011;
     localparam [2:0] AXI_SIZE_16B  = 3'b100;
     localparam [2:0] AXI_SIZE_32B  = 3'b101;
     localparam [2:0] AXI_SIZE_64B  = 3'b110;
     localparam [2:0] AXI_SIZE_128B = 3'b111;

**逐段解释** ：

* 第 L8 行：文件定义 ``axi4_pkg`` package，后续常量都在这个命名空间内。
* 第 L10-L13 行：burst 类型包含 ``FIXED``、``INCR`` 和 ``WRAP`` 三种 2-bit 编码。
* 第 L15-L19 行：response 类型包含 ``OKAY``、``EXOKAY``、``SLVERR`` 和 ``DECERR``。
  这些编码与 ``axi4_seq_item`` 中的 ``resp_type_e`` 保持同值。
* 第 L21-L23 行：lock 常量区分 normal 与 exclusive。
* 第 L25-L33 行：size 常量把 3-bit ``size`` 编码映射到 1B 到 128B。当前 TB 实例化
  的 ``DATA_WIDTH`` 是 64，因此 TB 行为内存一次 beat 的数据宽度是 8 字节。

**接口关系** ：

* **被调用** ：AXI4 共享 RTL、agent 事务类或约束可引用这些常量。
* **调用** ：无下层调用。
* **共享状态** ：只提供编译期常量，不持有运行时状态。

§2.2  cache、protection 与 outstanding 上限
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_pkg`` 还保留常见 cache/protection 编码和一个 outstanding 参数。
本章只说明这些常量存在，不推断 DUT 如何生成这些字段。

**关键代码** （``shared/rtl/axi4_pkg.sv:L35-L50``）：

.. code-block:: systemverilog

     // AXI4 Cache Encoding (common values)
     localparam [3:0] AXI_CACHE_NONCACHE_NONBUF = 4'b0000;
     localparam [3:0] AXI_CACHE_BUF_NONCACHE    = 4'b0001;
     localparam [3:0] AXI_CACHE_CACHE_NONALLOC  = 4'b0010;
     localparam [3:0] AXI_CACHE_CACHE_BUF       = 4'b0011;
   
     // AXI4 Protection Encoding
     localparam [2:0] AXI_PROT_UNPRIV    = 3'b000;
     localparam [2:0] AXI_PROT_PRIV      = 3'b001;
     localparam [2:0] AXI_PROT_SECURE    = 3'b000;
     localparam [2:0] AXI_PROT_NONSECURE = 3'b010;
     localparam [2:0] AXI_PROT_DATA      = 3'b000;
     localparam [2:0] AXI_PROT_INSTR     = 3'b100;
   
     // Maximum outstanding transactions
     localparam int MAX_OUTSTANDING = 16;

**逐段解释** ：

* 第 L35-L39 行：cache 常量覆盖 non-cache/non-buffer、bufferable non-cache、
  cache non-allocate 和 cache buffer 四类编码。
* 第 L41-L47 行：protection 常量覆盖 privilege、安全域和 data/instruction 三类属性位。
* 第 L49-L50 行：``MAX_OUTSTANDING`` 固定为 16。该常量在 package 中定义，但本章未在
  TB 片段中看到直接用它限制 monitor 队列深度。

**接口关系** ：

* **被调用** ：用于协议字段构造或检查的代码可引用这些常量。
* **调用** ：无。
* **共享状态** ：无运行时状态。

§3  ``axi4_intf`` 虚接口
--------------------------------------------------------------------------------

§3.1  参数化宽度与五通道信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_intf`` 把 AXI4 五通道信号收拢成一个参数化 SystemVerilog
interface。TB 为 LSU、IFU 和 SB 各实例化一次。

**关键代码** （``shared/rtl/axi4_intf.sv:L8-L64``）：

.. code-block:: systemverilog

   interface axi4_intf #(
     parameter int ADDR_WIDTH = 32,
     parameter int DATA_WIDTH = 64,
     parameter int ID_WIDTH   = 4
   ) (
     input logic clk,
     input logic rst_n
   );
   
     // Write Address Channel
     logic [ID_WIDTH-1:0]     awid;
     logic [ADDR_WIDTH-1:0]   awaddr;
     logic [3:0]              awregion;
     logic [7:0]              awlen;
     logic [2:0]              awsize;
     logic [1:0]              awburst;
     logic                    awlock;
     logic [3:0]              awcache;
     logic [2:0]              awprot;
     logic [3:0]              awqos;
     logic                    awvalid;
     logic                    awready;

**逐段解释** ：

* 第 L8-L15 行：接口参数默认地址 32-bit、数据 64-bit、ID 4-bit，并接收 ``clk`` 与
  ``rst_n``。
* 第 L17-L29 行：写地址通道包含 ID、地址、region、len、size、burst、lock、
  cache、prot、qos 和 valid/ready 握手。
* 同一文件第 L31-L64 行继续定义写数据、写响应、读地址和读数据通道。字段命名与
  ``core_eh2_tb_top`` 中的 ``lsu_axi_*``、``ifu_axi_*``、``sb_axi_*`` wires 一一对应。

**关键代码** （``shared/rtl/axi4_intf.sv:L31-L64``）：

.. code-block:: systemverilog

     // Write Data Channel
     logic [DATA_WIDTH-1:0]   wdata;
     logic [DATA_WIDTH/8-1:0] wstrb;
     logic                    wlast;
     logic                    wvalid;
     logic                    wready;
   
     // Write Response Channel
     logic [ID_WIDTH-1:0]     bid;
     logic [1:0]              bresp;
     logic                    bvalid;
     logic                    bready;
   
     // Read Address Channel
     logic [ID_WIDTH-1:0]     arid;
     logic [ADDR_WIDTH-1:0]   araddr;
     logic [3:0]              arregion;
     logic [7:0]              arlen;
     logic [2:0]              arsize;
     logic [1:0]              arburst;
     logic                    arlock;
     logic [3:0]              arcache;
     logic [2:0]              arprot;
     logic [3:0]              arqos;
     logic                    arvalid;
     logic                    arready;

**逐段解释** ：

* 第 L31-L36 行：写数据通道宽度来自 ``DATA_WIDTH``，byte strobe 宽度来自
  ``DATA_WIDTH/8``。
* 第 L38-L42 行：写响应通道保留 ``bid``、``bresp`` 和 valid/ready。
* 第 L44-L56 行：读地址通道字段与写地址通道基本对称。
* 第 L58-L64 行：读数据通道返回 ``rid``、``rdata``、``rresp``、``rlast`` 和握手信号。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top`` 实例化该 interface，并通过
  ``uvm_config_db`` 发给 AXI4 agent。
* **调用** ：无子模块调用。
* **共享状态** ：持有当前仿真周期的 AXI4 pin 采样值和 error injection 控制位。

§3.2  error injection 控制位
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_intf`` 提供 ``error_inject_mode``、``force_bresp`` 和
``force_rresp`` 三个控制位。这些控制位由 UVM 侧驱动，``axi4_slave_mem`` 消费。

**关键代码** （``shared/rtl/axi4_intf.sv:L66-L76``）：

.. code-block:: systemverilog

     // Error injection control (driven by UVM axi4_driver, consumed by axi4_slave_mem)
     logic                    error_inject_mode;
     logic [1:0]              force_bresp;
     logic [1:0]              force_rresp;
   
     // Default: error injection inactive
     initial begin
       error_inject_mode = 1'b0;
       force_bresp       = 2'b00;
       force_rresp       = 2'b00;
     end

**逐段解释** ：

* 第 L66-L69 行：接口上直接声明 3 个非 AXI 标准信号，用于测试时强制响应码。
* 第 L71-L76 行：仿真初始值关闭 error injection，并把读写响应强制值设为 ``2'b00``。
  ``2'b00`` 与 ``AXI_RESP_OKAY`` 的编码一致。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top`` 把这些位连接到每个 ``axi4_slave_mem``。
* **调用** ：无。
* **共享状态** ：UVM driver 可写这些控制位；行为内存读取它们决定 ``bresp`` 和
  ``rresp``。

§3.3  clocking block、modport 与协议稳定性断言
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：接口为 response driver、master driver 和 monitor 分别定义 clocking
block，并在非综合区检查 valid 在 ready 前不能提前撤销。

**关键代码** （``shared/rtl/axi4_intf.sv:L78-L152``）：

.. code-block:: systemverilog

     // Clocking block for response driver (slave side)
     // Drives responses to master requests
     clocking resp_driver_cb @(posedge clk);
       default input #1 output #1;
   
       // Input: master requests
       input awid, awaddr, awregion, awlen, awsize, awburst;
       input awlock, awcache, awprot, awqos, awvalid;
       input wdata, wstrb, wlast, wvalid;
       input bready;
       input arid, araddr, arregion, arlen, arsize, arburst;
       input arlock, arcache, arprot, arqos, arvalid;
       input rready;
   
       // Output: slave responses
       output awready;
       output wready;
       output bid, bresp, bvalid;
       output arready;
       output rid, rdata, rresp, rlast, rvalid;
     endclocking

**逐段解释** ：

* 第 L78-L98 行：response driver clocking block 把 request 字段声明为 input，
  把 slave response 字段声明为 output，匹配行为内存或 slave driver 的方向。
* 第 L100-L120 行：master driver clocking block 反向定义主端 request 和从端 response。
* 第 L122-L134 行：monitor clocking block 只采样所有字段，不驱动总线。
* 第 L136-L152 行：三个 modport 分别暴露给 response、master 和 monitor 组件。

**关键代码** （``shared/rtl/axi4_intf.sv:L161-L199``）：

.. code-block:: systemverilog

     // AWVALID must remain asserted until AWREADY
     property aw_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       awvalid && !awready |=> awvalid;
     endproperty
     assert property (aw_valid_stable) else
       $error("AXI4: AWVALID deasserted before AWREADY");
   
     // WVALID must remain asserted until WREADY
     property w_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       wvalid && !wready |=> wvalid;
     endproperty
     assert property (w_valid_stable) else
       $error("AXI4: WVALID deasserted before WREADY");

**逐段解释** ：

* 第 L161-L167 行：如果 ``awvalid`` 已经为 1 且 ``awready`` 仍为 0，下一拍必须继续
  保持 ``awvalid``。
* 第 L169-L175 行：``wvalid`` 采用同样稳定性规则。
* 同一断言区第 L177-L199 行继续检查 ``arvalid``、``bvalid`` 和 ``rvalid``。这些断言
  位于 ``ifndef SYNTHESIS`` 与 ``pragma translate_off`` 包围区内，因此面向仿真检查。

**接口关系** ：

* **被调用** ：仿真期间 interface 实例自动执行这些 property。
* **调用** ：断言失败时调用 ``$error``。
* **共享状态** ：读取当前 interface 上的 valid/ready 和 ``rst_n``。

§4  TB top 中的 AXI4 端口连接
--------------------------------------------------------------------------------

§4.1  DUT 端口映射中的 LSU、IFU、SB 与 DMA AXI4
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``core_eh2_tb_top`` 把 DUT wrapper 的 AXI4 pins 接到 TB wires。LSU、IFU、
SB 是 DUT master 端口；DMA AXI4 在该 TB 中作为外部 master 侧输入被绑为 inactive。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L316-L347``）：

.. code-block:: systemverilog

       // DMA AXI4 (tied off - no DMA master in basic tests)
       .dma_axi_awvalid   (dma_axi_awvalid),
       .dma_axi_awready   (dma_axi_awready),
       .dma_axi_awid      (dma_axi_awid),
       .dma_axi_awaddr    (dma_axi_awaddr),
       .dma_axi_awsize    (dma_axi_awsize),
       .dma_axi_awprot    (dma_axi_awprot),
       .dma_axi_awlen     (dma_axi_awlen),
       .dma_axi_awburst   (dma_axi_awburst),
       .dma_axi_wvalid    (dma_axi_wvalid),
       .dma_axi_wready    (dma_axi_wready),
       .dma_axi_wdata     (dma_axi_wdata),
       .dma_axi_wstrb     (dma_axi_wstrb),
       .dma_axi_wlast     (dma_axi_wlast),
       .dma_axi_bvalid    (dma_axi_bvalid),
       .dma_axi_bready    (dma_axi_bready),
       .dma_axi_bresp     (dma_axi_bresp),
       .dma_axi_bid       (dma_axi_bid),
       .dma_axi_arvalid   (dma_axi_arvalid),
       .dma_axi_arready   (dma_axi_arready),
       .dma_axi_arid      (dma_axi_arid),
       .dma_axi_araddr    (dma_axi_araddr),
       .dma_axi_arsize    (dma_axi_arsize),
       .dma_axi_arprot    (dma_axi_arprot),
       .dma_axi_arlen     (dma_axi_arlen),
       .dma_axi_arburst   (dma_axi_arburst),
       .dma_axi_rvalid    (dma_axi_rvalid),
       .dma_axi_rready    (dma_axi_rready),
       .dma_axi_rid       (dma_axi_rid),
       .dma_axi_rdata     (dma_axi_rdata),

**逐段解释** ：

* 第 L316 行的源码注释明确说明 ``DMA AXI4`` 在 basic tests 中 tied off，原因是没有
  DMA master。
* 第 L317-L347 行列出 DMA AXI4 的 AW、W、B、AR、R 五通道连接名。这里仍是 DUT 端口
  映射，不代表 TB 已提供 DMA master 行为模型。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L538-L564``）：

.. code-block:: systemverilog

     // DMA port: no external DMA master — tie all inputs to inactive values.
     // OUTPUTS are driven by the DUT only (do NOT assign — that caused multi-driver X).
     // AW channel inputs
     assign dma_axi_awvalid = 1'b0;
     assign dma_axi_awid    = '0;
     assign dma_axi_awaddr  = '0;
     assign dma_axi_awsize  = '0;
     assign dma_axi_awprot  = '0;
     assign dma_axi_awlen   = '0;
     assign dma_axi_awburst = '0;
     // W channel inputs
     assign dma_axi_wvalid  = 1'b0;
     assign dma_axi_wdata   = '0;
     assign dma_axi_wstrb   = '0;
     assign dma_axi_wlast   = '0;
     // B channel input
     assign dma_axi_bready  = 1'b0;
     // AR channel inputs
     assign dma_axi_arvalid = 1'b0;
     assign dma_axi_arid    = '0;
     assign dma_axi_araddr  = '0;
     assign dma_axi_arsize  = '0;
     assign dma_axi_arprot  = '0;
     assign dma_axi_arlen   = '0;
     assign dma_axi_arburst = '0;
     // R channel input
     assign dma_axi_rready  = 1'b0;

**逐段解释** ：

* 第 L538-L539 行：TB 注释把 DMA port 的方向说清楚：外部 DMA master 不存在，因此只
  绑 DUT 输入，不驱动 DUT 输出。
* 第 L541-L547 行：DMA AW 输入全为 0，``dma_axi_awvalid`` 固定为 0。
* 第 L549-L552 行：DMA W 输入全为 0，``dma_axi_wvalid`` 固定为 0。
* 第 L554 行：``dma_axi_bready`` 固定为 0。
* 第 L556-L562 行：DMA AR 输入全为 0，``dma_axi_arvalid`` 固定为 0。
* 第 L564 行：``dma_axi_rready`` 固定为 0。

**接口关系** ：

* **被调用** ：DUT wrapper 实例化时连接这些 pins。
* **调用** ：无。
* **共享状态** ：LSU、IFU、SB wires 后续接行为内存和 UVM interface；DMA 输入在该 TB
  中固定为非活动值。

§4.2  三个 AXI4 行为内存实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB 为 LSU、IFU 和 SB 各实例化一个 ``axi4_slave_mem``，均使用 32-bit 地址、
64-bit 数据和 64 MB 默认地址空间。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L409-L450``）：

.. code-block:: systemverilog

     // LSU memory (data) - connected to LSU AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_LSU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) lsu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (lsu_axi_intf.error_inject_mode),
       .force_bresp       (lsu_axi_intf.force_bresp),
       .force_rresp       (lsu_axi_intf.force_rresp),
       .awid     (lsu_axi_awid),
       .awaddr   (lsu_axi_awaddr),
       .awlen    (lsu_axi_awlen),
       .awsize   (lsu_axi_awsize),
       .awburst  (lsu_axi_awburst),
       .awvalid  (lsu_axi_awvalid),
       .awready  (lsu_axi_awready),
       .wdata    (lsu_axi_wdata),
       .wstrb    (lsu_axi_wstrb),

**逐段解释** ：

* 第 L409-L415 行：``lsu_mem`` 连接 LSU AXI4 master 端口，参数为 32-bit 地址、
  64-bit 数据、``RV_LSU_BUS_TAG`` ID 宽度和 64 MB memory size。
* 第 L416-L420 行：内存实例使用 ``core_clk``、``rst_l``，并从 ``lsu_axi_intf`` 读取
  error injection 控制位。
* 第 L421-L450 行：LSU AXI4 五通道 wires 接入该行为内存。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L452-L536``）：

.. code-block:: systemverilog

     // IFU memory (instruction) - connected to IFU AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_IFU_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) ifu_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (ifu_axi_intf.error_inject_mode),
       .force_bresp       (ifu_axi_intf.force_bresp),
       .force_rresp       (ifu_axi_intf.force_rresp),
       .awid     (ifu_axi_awid),
       .awaddr   (ifu_axi_awaddr),
       .awlen    (ifu_axi_awlen),
       .awsize   (ifu_axi_awsize),
       .awburst  (ifu_axi_awburst),
       .awvalid  (ifu_axi_awvalid),
       .awready  (ifu_axi_awready),

**逐段解释** ：

* 第 L452-L458 行：``ifu_mem`` 连接 IFU AXI4 master 端口，ID 宽度为
  ``RV_IFU_BUS_TAG``。
* 第 L459-L463 行：IFU 内存同样从 ``ifu_axi_intf`` 读取 error injection 控制位。
* 第 L464-L493 行：IFU 的 AW/W/B/AR/R wires 接入该内存。
* 第 L495-L536 行：``sb_mem`` 连接 SB AXI4 master 端口，ID 宽度为 ``RV_SB_BUS_TAG``，
  并使用 ``sb_axi_intf`` 的 error injection 控制位。

**接口关系** ：

* **被调用** ：仿真 elaboration 时实例化。
* **调用** ：行为内存内部执行读写状态机、``write_mem``、``read_mem`` 和
  ``calc_next_addr``。
* **共享状态** ：三个内存实例各自持有独立的 associative byte memory。

§4.3  UVM AXI4 interface 实例与 wire 镜像
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB 把 DUT wires 镜像到三个 ``axi4_intf`` 实例上，供 UVM agent 通过虚接口
采样。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L592-L602``）：

.. code-block:: systemverilog

     // AXI4 Interface Instances (for UVM agents)
     // Use DUT's actual tag widths to avoid truncation/extension issues
     //--------------------------------------------------------------------------
     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_LSU_BUS_TAG))
       lsu_axi_intf (.clk(core_clk), .rst_n(rst_l));
   
     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_IFU_BUS_TAG))
       ifu_axi_intf (.clk(core_clk), .rst_n(rst_l));
   
     axi4_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(`RV_SB_BUS_TAG))
       sb_axi_intf (.clk(core_clk), .rst_n(rst_l));

**逐段解释** ：

* 第 L592-L594 行：源码注释说明 interface 用于 UVM agents，并使用 DUT 实际 tag
  宽度避免截断或扩展问题。
* 第 L595-L602 行：LSU、IFU、SB 三个 interface 都是 32-bit 地址、64-bit 数据，ID
  宽度分别来自对应宏。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L604-L644``）：

.. code-block:: systemverilog

     // Connect interface signals to DUT wires
     // LSU interface
     assign lsu_axi_intf.awvalid  = lsu_axi_awvalid;
     assign lsu_axi_intf.awready  = lsu_axi_awready;
     assign lsu_axi_intf.awid     = lsu_axi_awid;
     assign lsu_axi_intf.awaddr   = lsu_axi_awaddr;
     assign lsu_axi_intf.awlen    = lsu_axi_awlen;
     assign lsu_axi_intf.awsize   = lsu_axi_awsize;
     assign lsu_axi_intf.awburst  = lsu_axi_awburst;
     assign lsu_axi_intf.awlock   = lsu_axi_awlock;
     assign lsu_axi_intf.awcache  = lsu_axi_awcache;
     assign lsu_axi_intf.awprot   = lsu_axi_awprot;
     assign lsu_axi_intf.awregion = lsu_axi_awregion;
     assign lsu_axi_intf.awqos    = lsu_axi_awqos;
     assign lsu_axi_intf.wvalid   = lsu_axi_wvalid;
     assign lsu_axi_intf.wready   = lsu_axi_wready;
     assign lsu_axi_intf.wdata    = lsu_axi_wdata;
     assign lsu_axi_intf.wstrb    = lsu_axi_wstrb;
     assign lsu_axi_intf.wlast    = lsu_axi_wlast;
     assign lsu_axi_intf.bvalid   = lsu_axi_bvalid;

**逐段解释** ：

* 第 L604-L606 行：LSU interface 开始镜像 DUT wires。
* 第 L606-L617 行：LSU AW 通道字段逐个赋给 ``lsu_axi_intf``。
* 第 L618-L626 行：LSU W/B 通道字段逐个赋给 ``lsu_axi_intf``。
* 第 L627-L644 行：LSU AR/R 通道字段逐个赋给 ``lsu_axi_intf``。
* 第 L646-L685 行和第 L687-L726 行采用相同模式，分别镜像 IFU 和 SB wires。

**接口关系** ：

* **被调用** ：UVM AXI4 monitor 通过 config DB 取得这些 interface。
* **调用** ：无。
* **共享状态** ：interface 是 DUT pin 的镜像；它不是另一个 bus master。

§4.4  LSU bus probe 到 RVFI converter
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB 从 LSU AXI4 wires 派生一组简化 bus probe，提供给
``eh2_veer_wrapper_rvfi``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L752-L793``）：

.. code-block:: systemverilog

     // LSU bus valid signal (derived from AXI4 LSU transactions)
     //--------------------------------------------------------------------------
     logic lsu_bus_valid;
     logic [31:0] lsu_bus_addr;
     logic [31:0] lsu_bus_rdata;
     logic [31:0] lsu_bus_wdata;
     logic [3:0]  lsu_bus_wmask;
     logic        lsu_bus_write;
   
     assign lsu_bus_valid = (lsu_axi_awvalid && lsu_axi_awready) || (lsu_axi_arvalid && lsu_axi_arready) || (lsu_axi_wvalid && lsu_axi_wready) || (lsu_axi_rvalid && lsu_axi_rready);
     assign lsu_bus_addr  = lsu_axi_awvalid ? lsu_axi_awaddr : lsu_axi_araddr;
     assign lsu_bus_rdata = lsu_axi_rdata[31:0];
     assign lsu_bus_wdata = lsu_axi_wdata[31:0];
     assign lsu_bus_wmask = lsu_axi_wstrb[3:0];
     assign lsu_bus_write = lsu_axi_awvalid && lsu_axi_awready;

**逐段解释** ：

* 第 L754-L759 行：TB 声明简化 probe 字段：valid、addr、rdata、wdata、wmask 和 write。
* 第 L761 行：任一 LSU AW、AR、W、R handshake 出现时，``lsu_bus_valid`` 为 1。
* 第 L762 行：地址从 AW 或 AR 中选择；表达式只判断 ``lsu_axi_awvalid``，没有同时检查
  ``awready``。
* 第 L763-L765 行：RVFI converter 只接收 32-bit 低半数据和 4-bit 低半 strobe。
* 第 L766 行：``lsu_bus_write`` 只在 AW handshake 时为 1。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L771-L793``）：

.. code-block:: systemverilog

     eh2_veer_wrapper_rvfi u_rvfi_converter (
       .clk              (core_clk),
       .rst_n            (rst_l),
   
       // Trace inputs from DUT
       .trace_insn       (trace_rv_i_insn_ip[0]),
       .trace_address    (trace_rv_i_address_ip[0]),
       .trace_valid      (trace_rv_i_valid_ip[0]),
       .trace_exception  (trace_rv_i_exception_ip[0]),
       .trace_ecause     (trace_rv_i_ecause_ip[0]),
       .trace_interrupt  (trace_rv_i_interrupt_ip[0]),
       .trace_tval       (trace_rv_i_tval_ip[0]),
       .trace_rd_valid   (trace_rv_i_rd_valid_ip[0]),
       .trace_rd_addr    (trace_rv_i_rd_addr_ip[0]),
       .trace_rd_wdata   (trace_rv_i_rd_wdata_ip[0]),
   
       // LSU bus inputs
       .lsu_bus_valid    (lsu_bus_valid),
       .lsu_bus_addr     (lsu_bus_addr),
       .lsu_bus_rdata    (lsu_bus_rdata),
       .lsu_bus_wdata    (lsu_bus_wdata),
       .lsu_bus_wmask    (lsu_bus_wmask),
       .lsu_bus_write    (lsu_bus_write),

**逐段解释** ：

* 第 L771-L786 行：RVFI converter 同时接收 trace pkt 相关字段。
* 第 L787-L793 行：简化 LSU bus probe 接入 converter。这里的 probe 用于 RVFI 生成，
  不等同于 UVM AXI4 monitor 的完整事务对象。

**接口关系** ：

* **被调用** ：RVFI converter 实例读取这些 probe。
* **调用** ：无。
* **共享状态** ：probe 直接由 LSU AXI4 wires 组合生成。

§5  ``axi4_slave_mem`` 行为模型
--------------------------------------------------------------------------------

§5.1  模块参数、端口和 byte-addressable memory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_slave_mem`` 是 TB 的 AXI4 slave 行为内存，响应 DUT master 端口的读写。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L8-L67``）：

.. code-block:: systemverilog

   module axi4_slave_mem #(
     parameter int ADDR_WIDTH    = 32,
     parameter int DATA_WIDTH    = 64,
     parameter int ID_WIDTH      = 4,
     parameter int MEM_SIZE      = 64 * 1024 * 1024,  // 64MB default
     parameter int RESPONSE_DELAY = 0                  // Fixed response delay in cycles
   ) (
     input  logic clk,
     input  logic rst_n,
   
     // Error injection control (from UVM driver)
     input  logic        error_inject_mode,  // 1 = use forced resp values
     input  logic [1:0]  force_bresp,        // Forced write response (when error_inject_mode=1)
     input  logic [1:0]  force_rresp,        // Forced read response  (when error_inject_mode=1)

**逐段解释** ：

* 第 L8-L14 行：模块参数默认地址 32-bit、数据 64-bit、ID 4-bit、memory size 64 MB、
  response delay 0 cycle。
* 第 L15-L21 行：端口包含 clock/reset 和 error injection 控制输入。
* 第 L23-L60 行继续列出 AXI4 AW、W、B、AR、R 五通道端口。
* 第 L66 行：内部存储是 ``logic [7:0] mem [bit [ADDR_WIDTH-1:0]]``，即按地址索引的
  byte associative array。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top`` 三次实例化。
* **调用** ：内部任务 ``write_mem``、函数 ``read_mem``、``calc_next_addr``。
* **共享状态** ：``mem`` associative array 保存当前行为内存内容。

§5.2  write state machine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：写状态机按 AW、W、B 三阶段处理写事务，并在 ``wlast`` 后产生写响应。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L71-L156``）：

.. code-block:: systemverilog

     typedef enum logic [1:0] {
       WR_IDLE,
       WR_DATA,
       WR_RESP
     } wr_state_e;
   
     wr_state_e wr_state;
     logic [ID_WIDTH-1:0]     wr_id;
     logic [ADDR_WIDTH-1:0]   wr_addr;
     logic [7:0]              wr_len;
     logic [2:0]              wr_size;
     logic [1:0]              wr_burst;
     logic [7:0]              wr_beat_cnt;
     logic [ADDR_WIDTH-1:0]   wr_next_addr;
     logic [RESPONSE_DELAY:0] wr_delay_cnt;

**逐段解释** ：

* 第 L71-L75 行：写路径有 ``WR_IDLE``、``WR_DATA`` 和 ``WR_RESP`` 三个状态。
* 第 L77-L85 行：状态机保存 AW 阶段采样到的 ID、地址、长度、size、burst、beat 计数
  和 response delay 计数。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L100-L150``）：

.. code-block:: systemverilog

         WR_IDLE: begin
           awready <= 1'b1;
           if (awvalid && awready) begin
             wr_id       <= awid;
             wr_addr     <= awaddr;
             wr_len      <= awlen;
             wr_size     <= awsize;
             wr_burst    <= awburst;
             wr_beat_cnt <= '0;
             awready     <= 1'b0;
             wready      <= 1'b1;
             wr_state    <= WR_DATA;
           end
         end
   
         WR_DATA: begin
           if (wvalid && wready) begin
             // Write data to memory
             write_mem(wr_addr, wdata, wstrb, wr_size);

**逐段解释** ：

* 第 L100-L112 行：``WR_IDLE`` 拉高 ``awready``；AW handshake 后保存地址阶段字段，
  关闭 ``awready``，打开 ``wready``，进入 ``WR_DATA``。
* 第 L115-L118 行：``WR_DATA`` 在 W handshake 时调用 ``write_mem``。写入哪些 byte
  由 ``wstrb`` 决定。
* 第 L120-L130 行：``wlast`` 到来后关闭 ``wready``；如果 ``RESPONSE_DELAY`` 为 0，
  立即产生 ``bvalid``、``bid`` 和 ``bresp``，否则进入带延迟的 response 流程。
* 第 L131-L135 行：非最后 beat 时，状态机用 ``calc_next_addr`` 计算下一 beat 地址，
  并递增 ``wr_beat_cnt``。
* 第 L139-L150 行：``WR_RESP`` 等待 delay 计数归零后驱动 ``bvalid``；当 ``bready`` 为
  1 时回到 ``WR_IDLE``。

**接口关系** ：

* **被调用** ：DUT LSU/IFU/SB 写事务触发该状态机。
* **调用** ：``write_mem`` 和 ``calc_next_addr``。
* **共享状态** ：写入 ``mem``，并根据 ``error_inject_mode`` 选择 ``force_bresp`` 或
  ``2'b00``。

§5.3  read state machine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：读状态机按 AR、R 两类通道处理读事务，支持多 beat 返回和可配置 response
delay。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L161-L247``）：

.. code-block:: systemverilog

     typedef enum logic [1:0] {
       RD_IDLE,
       RD_DATA,
       RD_WAIT
     } rd_state_e;
   
     rd_state_e rd_state;
     logic [ID_WIDTH-1:0]     rd_id;
     logic [ADDR_WIDTH-1:0]   rd_addr;
     logic [7:0]              rd_len;
     logic [2:0]              rd_size;
     logic [1:0]              rd_burst;
     logic [7:0]              rd_beat_cnt;
     logic [RESPONSE_DELAY:0] rd_delay_cnt;

**逐段解释** ：

* 第 L161-L165 行：读路径有 ``RD_IDLE``、``RD_DATA`` 和 ``RD_WAIT`` 三个状态。
* 第 L167-L174 行：状态机保存 AR 阶段采样到的 ID、地址、长度、size、burst、beat
  计数和 delay 计数。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L190-L223``）：

.. code-block:: systemverilog

         RD_IDLE: begin
           arready <= 1'b1;
           if (arvalid && arready) begin
             rd_id       <= arid;
             rd_addr     <= araddr;
             rd_len      <= arlen;
             rd_size     <= arsize;
             rd_burst    <= arburst;
             rd_beat_cnt <= '0;
             arready     <= 1'b0;
             if (RESPONSE_DELAY == 0) begin
               rvalid <= 1'b1;
               rdata  <= read_mem(araddr, arsize);
               rlast  <= (arlen == 0);
               rid    <= arid;
               rresp  <= error_inject_mode ? force_rresp : 2'b00;
               rd_state <= RD_DATA;

**逐段解释** ：

* 第 L190-L199 行：``RD_IDLE`` 拉高 ``arready``；AR handshake 后保存读地址阶段字段。
* 第 L200-L206 行：无 delay 时立即拉高 ``rvalid``，从 ``read_mem`` 取数据，设置
  ``rlast``、``rid``、``rresp`` 并进入 ``RD_DATA``。
* 第 L207-L223 行：有 delay 时进入 ``RD_WAIT``，delay 结束后生成第一拍 R 数据。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L227-L241``）：

.. code-block:: systemverilog

         RD_DATA: begin
           if (rvalid && rready) begin
             if (rd_beat_cnt == rd_len) begin
               // Last beat
               rvalid    <= 1'b0;
               rlast     <= 1'b0;
               rd_state  <= RD_IDLE;
             end else begin
               // More beats to come
               rd_addr     <= calc_next_addr(rd_addr, rd_size, rd_burst, rd_len);
               rd_beat_cnt <= rd_beat_cnt + 1;
               rdata       <= read_mem(rd_addr, rd_size);
               rlast       <= (rd_beat_cnt + 1 == rd_len);
               rid         <= rd_id;

**逐段解释** ：

* 第 L227-L233 行：当当前 beat 已是最后一拍时，状态机撤销 ``rvalid`` 与 ``rlast``，
  回到 ``RD_IDLE``。
* 第 L234-L241 行：非最后 beat 时，状态机计算下一地址、递增 beat 计数并准备下一拍
  ``rdata``。这里的 ``rdata <= read_mem(rd_addr, rd_size)`` 使用当前 ``rd_addr`` 表达式，
  与同一 always block 中对 ``rd_addr`` 的非阻塞赋值同时出现。

**接口关系** ：

* **被调用** ：DUT LSU/IFU/SB 读事务触发该状态机。
* **调用** ：``read_mem`` 和 ``calc_next_addr``。
* **共享状态** ：读取 ``mem``，并根据 ``error_inject_mode`` 选择 ``force_rresp`` 或
  ``2'b00``。

§5.4  byte 写入、未初始化读取与 burst 地址更新
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：内存访问 helper 定义了 byte strobe 写入、未初始化 byte 返回 0，以及
``FIXED``、``INCR``、``WRAP`` 三种 burst 地址更新方式。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L253-L315``）：

.. code-block:: systemverilog

     task write_mem(
       input logic [ADDR_WIDTH-1:0] addr,
       input logic [DATA_WIDTH-1:0] data,
       input logic [DATA_WIDTH/8-1:0] strb,
       input logic [2:0] size
     );
       for (int i = 0; i < DATA_WIDTH/8; i++) begin
         if (strb[i]) begin
           mem[addr + i] = data[i*8 +: 8];
         end
       end
     endtask

**逐段解释** ：

* 第 L253-L258 行：``write_mem`` 接收地址、数据、strobe 和 size。当前函数体没有使用
  ``size`` 参数。
* 第 L259-L263 行：循环覆盖 ``DATA_WIDTH/8`` 个 byte；只有对应 ``strb[i]`` 为 1 时，
  才把 ``data`` 的第 ``i`` 个 byte 写到 ``mem[addr+i]``。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L266-L315``）：

.. code-block:: systemverilog

     function automatic logic [DATA_WIDTH-1:0] read_mem(
       input logic [ADDR_WIDTH-1:0] addr,
       input logic [2:0] size
     );
       logic [DATA_WIDTH-1:0] data;
       data = '0;
       for (int i = 0; i < DATA_WIDTH/8; i++) begin
         if (mem.exists(addr + i))
           data[i*8 +: 8] = mem[addr + i];
         else
           data[i*8 +: 8] = 8'h00;  // Return 0 for uninitialized
       end
       return data;
     endfunction

**逐段解释** ：

* 第 L266-L270 行：``read_mem`` 返回一个 ``DATA_WIDTH`` 宽数据，并接收 ``size`` 参数。
  当前函数体没有使用 ``size`` 参数。
* 第 L271-L278 行：读取每个 byte；如果 associative array 中不存在该地址，返回
  ``8'h00``。
* 第 L284-L315 行的 ``calc_next_addr`` 根据 ``size`` 计算 ``bytes = 1 << size``；
  ``FIXED`` 保持地址不变，``INCR`` 地址加 ``bytes``，``WRAP`` 在 wrap boundary 上回绕。

**接口关系** ：

* **被调用** ：写状态机调用 ``write_mem``；读状态机调用 ``read_mem``；读写状态机都调用
  ``calc_next_addr``。
* **调用** ：无下层模块。
* **共享状态** ：读写 ``mem`` associative array。

§5.5  backdoor 与 HEX 加载
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：行为内存提供 byte 级 backdoor 读写和简化 HEX 文件加载，用于测试加载。

**关键代码** （``shared/rtl/axi4_slave_mem.sv:L321-L379``）：

.. code-block:: systemverilog

     // Write a single byte via backdoor
     task backdoor_write_byte(
       input logic [ADDR_WIDTH-1:0] addr,
       input logic [7:0] data
     );
       mem[addr] = data;
     endtask
   
     // Read a single byte via backdoor
     task backdoor_read_byte(
       input  logic [ADDR_WIDTH-1:0] addr,
       output logic [7:0] data
     );
       if (mem.exists(addr))
         data = mem[addr];
       else
         data = 8'h00;
     endtask

**逐段解释** ：

* 第 L321-L327 行：``backdoor_write_byte`` 直接写入 ``mem[addr]``。
* 第 L329-L338 行：``backdoor_read_byte`` 读取 ``mem[addr]``；地址不存在时返回
  ``8'h00``。
* 第 L340-L379 行：``load_hex`` 用 ``$fopen`` 打开文件，识别 ``@address`` 行和数据行，
  按 byte 写入 ``mem``，并在格式错误时调用 ``$error``。

**接口关系** ：

* **被调用** ：测试加载或 TB helper 可调用这些 task。
* **调用** ：``$fopen``、``$fgets``、``$sscanf``、``$fclose`` 和 ``$display``。
* **共享状态** ：直接读写 ``mem``。

§6  AXI4 UVM 事务与 monitor
--------------------------------------------------------------------------------

§6.1  ``axi4_seq_item`` 事务字段与约束
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_seq_item`` 是 UVM 侧的 AXI4 transaction class，用于 monitor、driver
和 sequencer 之间传递完整事务。

**关键代码** （``dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv:L18-L52``）：

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

**逐段解释** ：

* 第 L18-L21 行：事务类型只有 ``AXI4_READ`` 和 ``AXI4_WRITE``。
* 第 L23-L28 行：burst 枚举与 ``axi4_pkg`` 中的 ``FIXED``、``INCR``、``WRAP`` 编码相同。
* 第 L30-L36 行：response 枚举与 ``axi4_pkg`` 的 response 编码相同。
* 第 L38-L52 行：事务字段包含 ``addr``、``id``、``len``、``size``、``burst``、
  写数据数组、写 strobe 数组、读数据数组和 response 数组。

**关键代码** （``dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv:L74-L97``）：

.. code-block:: systemverilog

     // Constraint: reasonable burst lengths
     constraint c_reasonable_len {
       len inside {[0:15]};  // Max 16 beats
     }
   
     // Constraint: size <= 8 bytes
     constraint c_valid_size {
       size <= 3;  // 8 bytes max
     }
   
     // Get beat count
     function int get_beat_count();
       return len + 1;
     endfunction

**逐段解释** ：

* 第 L74-L77 行：随机事务约束 ``len`` 在 0 到 15 之间，对应最多 16 beat。
* 第 L79-L82 行：随机事务约束 ``size <= 3``，即每 beat 最多 8 字节。
* 第 L84-L97 行：helper 根据 ``len`` 和 ``size`` 计算 beat 数、每 beat 字节数和总字节数。

**接口关系** ：

* **被调用** ：``axi4_monitor`` 创建该对象，cosim scoreboard 消费 LSU 对象。
* **调用** ：无外部模块调用。
* **共享状态** ：对象字段保存单笔 AXI4 transaction。

§6.2  monitor 并行采集读写事务
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``axi4_monitor`` 从虚接口观察 AXI4 事务。它用两个并行线程分别采集写事务和
读事务，再通过 analysis port 发布 ``axi4_seq_item``。

**关键代码** （``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L33-L51``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       ap = new("ap", this);
     endfunction
   
     function void connect_phase(uvm_phase phase);
       super.connect_phase(phase);
       if (!uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(ID_WIDTH)))::get(this, "", "vif", vif)) begin
         `uvm_warning(agent_name, "Could not get virtual interface - monitor disabled")
       end
     endfunction
   
     task run_phase(uvm_phase phase);
       if (vif == null) return;  // No interface - skip monitoring
       fork
         monitor_writes();
         monitor_reads();
       join
     endtask

**逐段解释** ：

* 第 L33-L36 行：monitor 创建 ``ap`` analysis port。
* 第 L38-L43 行：monitor 从 ``uvm_config_db`` 获取 ``vif``；获取失败时报告 warning，
  但不 fatal。
* 第 L45-L51 行：``run_phase`` 在 ``vif`` 非空时 fork 出 ``monitor_writes`` 和
  ``monitor_reads`` 两个线程。这里是异步采集路径，应按读写通道并行理解。

**关键代码** （``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L63-L110``）：

.. code-block:: systemverilog

       forever begin
         // Wait for AW handshake (address phase)
         @(posedge vif.clk iff (vif.awvalid && vif.awready));
   
         // Capture address phase
         awaddr  = vif.awaddr;
         awlen   = vif.awlen;
         awsize  = vif.awsize;
         awburst = vif.awburst;
         awid    = vif.awid;
   
         // Create transaction
         txn = axi4_seq_item::type_id::create("write_txn");
         txn.tx_type    = axi4_seq_item::AXI4_WRITE;
         txn.addr       = awaddr;
         txn.id         = awid;
         txn.len        = awlen;

**逐段解释** ：

* 第 L63-L65 行：写 monitor 等待 AW handshake。
* 第 L67-L72 行：采样地址阶段字段。
* 第 L74-L82 行：创建 ``write_txn``，填入事务类型、地址、ID、len、size、burst 和
  ``start_time``。
* 第 L84-L100 行：按 ``awlen + 1`` 分配数组并采集每个 W beat。源码特别处理 AW 与 W
  同拍 handshake 的场景，避免错过已经有效的 W beat。
* 第 L102-L110 行：写事务默认 response 先设为 ``OKAY``，然后在地址和数据完整后立即
  ``ap.write(txn)``。源码注释说明这里不等待 B handshake，以免 cosim scoreboard 被饿住。

**关键代码** （``dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv:L112-L168``）：

.. code-block:: systemverilog

         // Drain the response channel when it is observable. The transaction has
         // already been published, so do not block reset or early test completion.
         if (vif.bvalid && vif.bready) begin
           txn.resp[0] = axi4_seq_item::resp_type_e'(vif.bresp);
         end
       end
     endtask
   
     // Monitor read transactions (AR -> R)
     task monitor_reads();
       axi4_seq_item txn;
       bit [7:0] arlen;
       bit [2:0] arsize;
       bit [1:0] arburst;

**逐段解释** ：

* 第 L112-L116 行：写 monitor 在事务发布后 opportunistic 地读取 B response。如果 B
  handshake 尚不可见，已发布事务仍保留默认 ``OKAY``。
* 第 L120-L132 行：读 monitor 等待 AR handshake。
* 第 L134-L149 行：读 monitor 采样地址阶段并创建 ``read_txn``。
* 第 L151-L160 行：读 monitor 按 ``arlen + 1`` 分配 ``rdata`` 和 ``resp`` 数组，
  再逐拍等待 R handshake。
* 第 L163-L167 行：读事务采集完成后通过 ``ap.write(txn)`` 发布。

**接口关系** ：

* **被调用** ：AXI4 agent 的 run phase 调用 monitor run phase。
* **调用** ：``uvm_config_db::get``、``axi4_seq_item::type_id::create`` 和
  ``uvm_analysis_port::write``。
* **共享状态** ：读取 ``axi4_intf``；发布的 transaction 进入 subscriber，例如 cosim
  scoreboard。

§6.3  LSU AXI4 到 cosim scoreboard 的数据侧通知
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：cosim scoreboard 从 LSU AXI4 FIFO 读取 transaction，先排队为待匹配 memory
access，再在 trace pkt 需要时通知 Spike。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L260-L274``）：

.. code-block:: systemverilog

     // Monitor LSU AXI4 transactions for memory access notification
     task run_cosim_dmem();
       axi4_seq_item axi_txn;
   
       forever begin
         lsu_axi_fifo.get(axi_txn);
         axi_item_count++;
   
         if (cosim_handle != null && initialized) begin
           enqueue_memory_accesses(axi_txn);
           // Try to unblock both threads
           process_pending_trace(0);
           process_pending_trace(1);
         end
       end
     endtask

**逐段解释** ：

* 第 L260-L265 行：``run_cosim_dmem`` 永久等待 ``lsu_axi_fifo`` 中的 transaction。
* 第 L266 行：每收到一笔 LSU AXI4 transaction 就递增 ``axi_item_count``。
* 第 L268-L273 行：只有 ``cosim_handle`` 非空且 scoreboard 已初始化时，才把 transaction
  送入 memory access 队列，并尝试唤醒两个 thread 的 pending trace 处理。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L449-L474``）：

.. code-block:: systemverilog

     function void enqueue_memory_accesses(axi4_seq_item txn);
       pending_mem_access_t access;
       access.txn = txn;
       access.is_store = (txn.tx_type == axi4_seq_item::AXI4_WRITE);
       access.observed_access_count = count_observed_memory_accesses(txn);
       pending_mem_access_q.push_back(access);
       if (access.is_store) store_axi_delivered++;
     endfunction
   
     function int count_observed_memory_accesses(axi4_seq_item txn);
       int observed_access_count;
       observed_access_count = 0;

**逐段解释** ：

* 第 L449-L456 行：scoreboard 把 AXI4 transaction 包装成 ``pending_mem_access_t``，
  写事务标记为 store，并推入 ``pending_mem_access_q``。store 还会递增
  ``store_axi_delivered``。
* 第 L458-L474 行：写事务按每 beat 的 strobe 统计低半 32-bit 和高半 32-bit 是否有访问；
  读事务按 beat 数统计访问数。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L506-L562``）：

.. code-block:: systemverilog

     // Notify Spike about a memory access from the AXI4 bus.
     // AXI4 bus is 64-bit; split 64-bit beats into two 32-bit notifications.
     function void notify_memory_access(int tid, axi4_seq_item txn);
       if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
         bit write_error = (txn.resp[0] != axi4_seq_item::AXI4_RESP_OKAY);
   
         for (int i = 0; i < txn.get_beat_count(); i++) begin
           bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
           bit [63:0] beat_data = txn.data[i];
           bit [7:0]  beat_strb = txn.strb[i];
           int beat_bytes = (1 << txn.size);

**逐段解释** ：

* 第 L506-L508 行：源码注释明确说明 AXI4 bus 是 64-bit，scoreboard 会拆成两个
  32-bit 通知。
* 第 L509-L535 行：写事务逐 beat 处理；低半 ``strb[3:0]`` 非零时通知地址
  ``beat_addr``，高半 ``strb[7:4]`` 非零且 beat 超过 4 字节时通知 ``beat_addr + 4``。
* 第 L536-L562 行：读事务逐 beat 处理，先通知低半 32-bit；如果 beat 超过 4 字节，
  再通知高半 32-bit，并把 ``widened_load`` 传给 DPI。

**接口关系** ：

* **被调用** ：``process_pending_trace`` 在 trace pkt 与 memory access 匹配后调用
  ``pop_matching_memory_access``，再调用 ``notify_memory_access``。
* **调用** ：``riscv_cosim_notify_dside_access`` DPI。
* **共享状态** ：读写 ``pending_mem_access_q``、``store_axi_delivered`` 和
  ``axi_item_count``。

§7  AHB-Lite 端口的源码证据
--------------------------------------------------------------------------------

§7.1  LEC shim 中的 AHB 命名端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_veer_lec_pack`` 端口列表同时暴露 AXI4 和 AHB 命名端口，用于 LEC 包装。
本节只列出源码证据，不把它解释为当前 UVM TB 的 AHB 行为模型。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L295-L346``）：

.. code-block:: systemverilog

      output logic [31:0]           haddr,
      output logic [2:0]            hburst,
      output logic                  hmastlock,
      output logic [3:0]            hprot,
      output logic [2:0]            hsize,
      output logic [1:0]            htrans,
      output logic                  hwrite,
   
      input  logic [63:0]           hrdata,
      input  logic                  hready,
      input  logic                  hresp,
   
      output logic [31:0]          lsu_haddr,
      output logic [2:0]           lsu_hburst,
      output logic                 lsu_hmastlock,
      output logic [3:0]           lsu_hprot,
      output logic [2:0]           lsu_hsize,

**逐段解释** ：

* 第 L295-L305 行：通用 AHB 命名端口包括 ``haddr``、``hburst``、``hmastlock``、
  ``hprot``、``hsize``、``htrans``、``hwrite``、``hrdata``、``hready`` 和 ``hresp``。
* 第 L307-L318 行：LSU AHB 命名端口包含地址、burst、lock、prot、size、trans、write、
  write data，以及 read data、ready、resp 输入。
* 第 L320-L331 行：SB AHB 命名端口与 LSU AHB 命名端口结构相同。
* 第 L333-L346 行：DMA AHB 命名端口以输入侧 request 和输出侧 response 的形式出现。

**接口关系** ：

* **被调用** ：LEC shim 作为形式等价包装层暴露这些 pins。
* **调用** ：无。
* **共享状态** ：这些是 module 端口，不持有状态。

§8  参考资料
--------------------------------------------------------------------------------

* :file:`/home/host/eh2-veri/shared/rtl/axi4_pkg.sv` — AXI4 常量 package。
* :file:`/home/host/eh2-veri/shared/rtl/axi4_intf.sv` — AXI4 虚接口、clocking block 和仿真断言。
* :file:`/home/host/eh2-veri/shared/rtl/axi4_slave_mem.sv` — TB AXI4 slave 行为内存。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` — DUT pins、行为内存和 UVM interface 连接。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_seq_item.sv` — AXI4 UVM transaction。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv` — AXI4 UVM monitor。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv` — LSU AXI4 到 Spike dside 通知路径。
* :file:`/home/host/eh2-veri/rtl/lec_shim/eh2_veer_lec_pack.sv` — LEC shim 中的 AXI4/AHB 端口列表。
* :ref:`appendix_a_rtl/shared_axi4` — AXI4 共享 RTL 字典。
* :ref:`agent_axi4` — UVM AXI4 agent 架构。
* :ref:`cosim_scoreboard` — cosim scoreboard 的 AXI4 消费路径。
