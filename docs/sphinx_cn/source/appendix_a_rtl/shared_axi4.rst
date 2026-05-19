.. _appendix_a_rtl_shared_axi4:
.. _appendix_a_rtl/shared_axi4:

AXI4 共享模块与 AXI/AHB 桥接器
===============================

:status: draft
:source: shared/rtl/; rtl/design/lib/axi4_to_ahb.sv; rtl/design/lib/ahb_to_axi4.sv
:last-reviewed: 2026-05-19

§1  源文件边界与数据流
----------------------

本章只描述当前源码中与 AXI4 共享设施和 AXI/AHB 转换相关的文件。需要区分两个边界：

* :file:`shared/rtl/` 下的 ``axi4_pkg``、``axi4_intf`` 和 ``axi4_slave_mem`` 是 UVM
  验证平台使用的共享 SystemVerilog 资源。
* :file:`rtl/design/lib/` 下的 ``axi4_to_ahb`` 和 ``ahb_to_axi4`` 是 EH2 RTL 中的桥接器，
  只在 ``pt.BUILD_AHB_LITE == 1`` 的 generate 分支内接入顶层。

当前源码中的总线相关数据流如下：

.. code-block:: text

   shared/rtl/axi4_pkg.sv
        │
        ├── constants for AXI4 encoding
        │
        ▼
   shared/rtl/axi4_intf.sv
        │
        ├── UVM monitor / driver virtual interface
        └── error_inject_mode / force_bresp / force_rresp
                  │
                  ▼
   shared/rtl/axi4_slave_mem.sv
        │
        ├── LSU / IFU / SB behavioral memory in core_eh2_tb_top
        └── byte associative mem + AXI read/write FSM

   EH2 RTL optional AHB-Lite build:

   LSU/IFU/SB AXI master ──► axi4_to_ahb ──► AHB-Lite bus
   DMA AHB slave side    ──► ahb_to_axi4 ──► DMA AXI pins

``shared/rtl`` 的三个文件由 :file:`dv/uvm/core_eh2/eh2_shared.f` 编译；桥接器由
:file:`dv/uvm/core_eh2/eh2_rtl.f` 编译，并在 :file:`rtl/design/eh2_veer.sv`
中根据 ``pt.BUILD_AHB_LITE`` 实例化。本文不会把 ``axi4_slave_mem`` 写成 RTL 桥接器，
也不会把 AHB-Lite generate 分支写成默认 AXI4 路径。

关键代码（``dv/uvm/core_eh2/eh2_shared.f:L5-L12``）：

.. code-block:: text

   // AXI4 package
   shared/rtl/axi4_pkg.sv

   // AXI4 interface
   shared/rtl/axi4_intf.sv

   // AXI4 slave memory model
   shared/rtl/axi4_slave_mem.sv

逐段解释：

* 第 L5-L6 行：共享 filelist 先编译 ``axi4_pkg.sv``，为后续组件提供 AXI4 编码常量。
* 第 L8-L9 行：``axi4_intf.sv`` 被列为独立 interface 文件，用于 TB 顶层和 UVM agent
  之间传递 virtual interface。
* 第 L11-L12 行：``axi4_slave_mem.sv`` 是共享行为级 memory model，当前 UVM TB 用它响应
  LSU、IFU 和 SB 三组 DUT AXI4 master 访问。

接口关系：

* 被调用：编译脚本读取 :file:`dv/uvm/core_eh2/eh2_shared.f` 后把三个共享文件加入仿真编译。
* 调用：filelist 不调用 SystemVerilog 逻辑，只定义编译顺序。
* 共享状态：无运行时状态；运行时状态存在于 ``axi4_intf`` 信号和 ``axi4_slave_mem.mem``。

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L16-L18``）：

.. code-block:: text

   // AXI/AHB converters
   rtl/design/lib/ahb_to_axi4.sv
   rtl/design/lib/axi4_to_ahb.sv

逐段解释：

* 第 L16-L18 行：RTL filelist 显式列出 ``ahb_to_axi4.sv`` 和 ``axi4_to_ahb.sv``。
  这两个文件属于 DUT RTL 编译输入，不属于 ``shared/rtl`` 验证侧资源。

接口关系：

* 被调用：RTL 编译读取 :file:`dv/uvm/core_eh2/eh2_rtl.f` 时编译这两个桥接器。
* 调用：filelist 不调用逻辑；桥接器实例由 ``eh2_veer`` 中的 generate 分支决定。
* 共享状态：无运行时共享状态；桥接器运行时共享 ``pt`` 参数、AXI channel 和 AHB-Lite channel。

§2  ``axi4_pkg.sv`` — AXI4 编码常量
-----------------------------------

``axi4_pkg`` 只定义常量，没有 typedef、函数或任务。旧文档中提到的
``get_beat_count()``、``get_beat_bytes()`` 和 ``get_total_bytes()`` 在当前
:file:`shared/rtl/axi4_pkg.sv` 中不存在，因此本章不保留这些函数名。

§2.1  package、burst 与 response 编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 ``axi4_pkg``，并集中定义 burst 类型和 response 编码常量。

关键代码（``shared/rtl/axi4_pkg.sv:L8-L19``）：

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

逐段解释：

* 第 L8 行：package 名为 ``axi4_pkg``，供共享 RTL 或 UVM 代码通过 ``import`` 使用。
* 第 L10-L13 行：burst 常量覆盖 ``FIXED``、``INCR``、``WRAP`` 三种 2-bit 编码。
  ``axi4_slave_mem.calc_next_addr`` 使用原始 2-bit 值判断 burst 类型，文档以这里的常量命名解释语义。
* 第 L15-L19 行：response 常量覆盖 ``OKAY``、``EXOKAY``、``SLVERR`` 和 ``DECERR``。
  ``axi4_slave_mem`` 在非 error injection 模式下返回 ``2'b00``，在 error injection 模式下使用
  ``force_bresp`` 或 ``force_rresp``。

接口关系：

* 被调用：共享编译列表首先编译该 package。
* 调用：该 package 不调用其它函数或模块。
* 共享状态：只有 ``localparam`` 常量，无可写状态。

§2.2  lock、size、cache、prot 与 outstanding 上限
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 lock、size、cache、protection 和 outstanding 相关常量，供同一 package 的使用者统一编码。

关键代码（``shared/rtl/axi4_pkg.sv:L21-L50``）：

.. code-block:: systemverilog

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

逐段解释：

* 第 L21-L23 行：lock 常量给出 normal 和 exclusive 两个编码。当前 ``axi4_intf`` 声明了
  ``awlock`` 和 ``arlock`` 信号，但 ``axi4_slave_mem`` 端口列表不包含 lock 信号。
* 第 L25-L33 行：size 常量从 1 byte 到 128 byte。``axi4_slave_mem`` 用 ``1 << size``
  计算下一 beat 地址，桥接器用 ``axi_awsize``、``axi_arsize`` 或 ``ahb_hsize`` 转换访问大小。
* 第 L35-L39 行：cache 常量只列出常用值；当前桥接器 ``axi4_to_ahb`` 不输出 AXI cache，
  ``ahb_to_axi4`` 也没有 AXI cache 端口。
* 第 L41-L47 行：protection 常量拆成 privilege、security 和 data/instruction 位含义。
  ``axi4_to_ahb`` 使用 ``axi_arprot[2]`` 生成 ``ahb_hprot`` 的低位组合。

关键代码（``shared/rtl/axi4_pkg.sv:L49-L52``）：

.. code-block:: systemverilog

     // Maximum outstanding transactions
     localparam int MAX_OUTSTANDING = 16;

   endpackage

逐段解释：

* 第 L49-L50 行：``MAX_OUTSTANDING`` 被定义为 16。该文件只定义常量，不在 package 内实现 outstanding
  计数器。
* 第 L52 行：package 结束，确认该文件没有后续函数、class 或 module 定义。

接口关系：

* 被调用：使用者可以 import ``axi4_pkg`` 获取常量。
* 调用：本节没有函数调用。
* 共享状态：全部是 ``localparam``，不会在仿真时改变。

§3  ``axi4_intf.sv`` — UVM 可见 AXI4 interface
-----------------------------------------------

``axi4_intf`` 是参数化 SystemVerilog interface。它把 AXI4 五个 channel、error injection 控制、
driver/monitor clocking block、modport 和简单握手稳定性 assertion 放在一个可通过
``uvm_config_db`` 传递的对象中。

§3.1  参数与写通道信号
~~~~~~~~~~~~~~~~~~~~~~

职责：声明 address/data/id 三个宽度参数，并定义 AW、W、B 三个写相关 channel。

关键代码（``shared/rtl/axi4_intf.sv:L8-L42``）：

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

     // Write Data Channel
     logic [DATA_WIDTH-1:0]   wdata;

逐段解释：

* 第 L8-L15 行：interface 默认地址宽度 32、数据宽度 64、ID 宽度 4，并以 ``clk`` 和
  ``rst_n`` 作为 clocking block 与 assertion 的时钟复位输入。
* 第 L17-L29 行：AW channel 包含 ID、地址、region、len、size、burst、lock、cache、prot、
  qos 以及 valid/ready。TB 顶层会把 DUT 的 LSU/IFU/SB AW 信号逐项 assign 到该 interface。
* 第 L31-L42 行开始 W/B channel 声明；``wstrb`` 宽度由 ``DATA_WIDTH/8`` 计算，保持与
  64-bit data beat 的 8-byte strobe 对齐。

关键代码（``shared/rtl/axi4_intf.sv:L31-L42``）：

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

逐段解释：

* 第 L31-L36 行：W channel 记录写数据、byte strobe、last 和 valid/ready。
  ``axi4_slave_mem.write_mem`` 只在 ``wstrb[i]`` 为 1 时写对应 byte。
* 第 L38-L42 行：B channel 记录 response ID、response code 和 valid/ready。
  error injection 模式只覆盖 ``bresp``，不改变 ``bid`` 的来源。

接口关系：

* 被调用：TB top 实例化 ``axi4_intf``，UVM monitor 和 driver 通过 virtual interface 访问这些信号。
* 调用：信号声明不调用逻辑。
* 共享状态：``aw*``、``w*``、``b*`` 是 interface 内部共享 nets。

§3.2  读通道与 error injection 控制
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 AR/R channel，并提供 ``axi4_driver`` 控制 ``axi4_slave_mem`` response 的三个辅助信号。

关键代码（``shared/rtl/axi4_intf.sv:L44-L76``）：

.. code-block:: systemverilog

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

     // Read Data Channel
     logic [ID_WIDTH-1:0]     rid;
     logic [DATA_WIDTH-1:0]   rdata;
     logic [1:0]              rresp;
     logic                    rlast;
     logic                    rvalid;
     logic                    rready;

     // Error injection control (driven by UVM axi4_driver, consumed by axi4_slave_mem)
     logic                    error_inject_mode;
     logic [1:0]              force_bresp;
     logic [1:0]              force_rresp;

逐段解释：

* 第 L44-L56 行：AR channel 与 AW channel 对称，包含 ID、地址、len、size、burst 和 valid/ready。
* 第 L58-L64 行：R channel 包含 ID、data、response、last 和 valid/ready。
  ``axi4_slave_mem`` 在读 FSM 中用 ``rd_id`` 回填 ``rid``，用 ``read_mem`` 回填 ``rdata``。
* 第 L66-L69 行：error injection 控制信号由注释明确标注为 UVM ``axi4_driver`` 驱动、
  ``axi4_slave_mem`` 消费。它们不是 AXI4 标准 channel，而是验证平台内部 sideband。

关键代码（``shared/rtl/axi4_intf.sv:L71-L76``）：

.. code-block:: systemverilog

     // Default: error injection inactive
     initial begin
       error_inject_mode = 1'b0;
       force_bresp       = 2'b00;
       force_rresp       = 2'b00;
     end

逐段解释：

* 第 L71-L76 行：仿真初始时关闭 error injection，并把强制 B/R response 设为 ``2'b00``。
  因此没有 driver 改写这些信号时，``axi4_slave_mem`` 返回 OKAY 编码。

接口关系：

* 被调用：``axi4_slave_mem`` 的 ``error_inject_mode``、``force_bresp``、``force_rresp``
  端口在 TB top 中接到对应 ``axi4_intf`` 字段。
* 调用：initial block 只初始化 interface 内部变量。
* 共享状态：``error_inject_mode``、``force_bresp``、``force_rresp`` 被 driver 和 memory model 共享。

§3.3  response driver 与 master driver clocking block
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 slave-side response driver 和 master-side driver 的输入输出方向固定到 clocking block 中。

关键代码（``shared/rtl/axi4_intf.sv:L78-L120``）：

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

     // Clocking block for master driver
     // Drives master requests
     clocking master_driver_cb @(posedge clk);
       default input #1 output #1;

逐段解释：

* 第 L78-L98 行：``resp_driver_cb`` 面向 slave response agent，采样 master 请求，驱动 ready、
  B channel 和 R channel。当前 ``axi4_slave_mem`` 不是通过这个 clocking block 实例化，
  但 UVM active driver 可以通过 interface sideband 控制 response。
* 第 L100-L103 行：``master_driver_cb`` 使用同一个 ``posedge clk``，并设置默认 input/output skew。

关键代码（``shared/rtl/axi4_intf.sv:L105-L120``）：

.. code-block:: systemverilog

       // Output: master requests
       output awid, awaddr, awregion, awlen, awsize, awburst;
       output awlock, awcache, awprot, awqos, awvalid;
       output wdata, wstrb, wlast, wvalid;
       output bready;
       output arid, araddr, arregion, arlen, arsize, arburst;
       output arlock, arcache, arprot, arqos, arvalid;
       output rready;

       // Input: slave responses
       input awready;
       input wready;
       input bid, bresp, bvalid;
       input arready;
       input rid, rdata, rresp, rlast, rvalid;
     endclocking

逐段解释：

* 第 L105-L112 行：master driver 的输出方向覆盖 AW、W、B ready、AR 和 R ready。
* 第 L114-L120 行：master driver 的输入方向覆盖 slave 返回的 ready、B response 和 R data/response。
  这与 response driver clocking block 的方向相反。

接口关系：

* 被调用：UVM driver 或 monitor 通过 virtual interface 访问 clocking block。
* 调用：clocking block 不调用任务，只定义采样和驱动方向。
* 共享状态：所有 AXI channel 信号均在 clocking block 与 interface nets 之间共享。

§3.4  monitor clocking block 与 modport
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供只采样全 channel 的 monitor 视图，并定义 response、master、monitor 三类 modport。

关键代码（``shared/rtl/axi4_intf.sv:L122-L152``）：

.. code-block:: systemverilog

     // Clocking block for monitor
     // Observes all transactions
     clocking monitor_cb @(posedge clk);
       default input #1;

       input awid, awaddr, awregion, awlen, awsize, awburst;
       input awlock, awcache, awprot, awqos, awvalid, awready;
       input wdata, wstrb, wlast, wvalid, wready;
       input bid, bresp, bvalid, bready;
       input arid, araddr, arregion, arlen, arsize, arburst;
       input arlock, arcache, arprot, arqos, arvalid, arready;
       input rid, rdata, rresp, rlast, rvalid, rready;
     endclocking

     // Modport for response agent (slave)
     modport response (
       input clk, rst_n,
       clocking resp_driver_cb
     );

逐段解释：

* 第 L122-L134 行：``monitor_cb`` 将 AW/W/B/AR/R 全部声明为 input，并同时采样 valid 与 ready。
  UVM monitor 可以用这个视图重建 read/write transaction。
* 第 L136-L140 行：``response`` modport 暴露 clock/reset 和 ``resp_driver_cb``，适合 slave-side
  response agent 使用。

关键代码（``shared/rtl/axi4_intf.sv:L142-L152``）：

.. code-block:: systemverilog

     // Modport for master agent
     modport master (
       input clk, rst_n,
       clocking master_driver_cb
     );

     // Modport for monitor
     modport monitor (
       input clk, rst_n,
       clocking monitor_cb
     );

逐段解释：

* 第 L142-L146 行：``master`` modport 暴露 ``master_driver_cb``。
* 第 L148-L152 行：``monitor`` modport 暴露只采样的 ``monitor_cb``。
  TB 当前通过 virtual ``axi4_intf`` 直接传给 UVM agent，文档中把 modport 视为 interface 提供的方向约束。

接口关系：

* 被调用：UVM 组件可选择使用完整 virtual interface 或 modport 视图。
* 调用：modport 不调用其它对象。
* 共享状态：modport 共享同一个 interface 实例内的 channel nets。

§3.5  协议稳定性 assertion
~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在非 synthesis 仿真中检查 ``VALID`` 信号在 ``READY`` 前保持有效。

关键代码（``shared/rtl/axi4_intf.sv:L158-L183``）：

.. code-block:: systemverilog

     // pragma translate_off
     `ifndef SYNTHESIS

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

     // ARVALID must remain asserted until ARREADY
     property ar_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       arvalid && !arready |=> arvalid;

逐段解释：

* 第 L158-L160 行：assertion 包在 ``translate_off`` 和 ``ifndef SYNTHESIS`` 中，限定为仿真检查。
* 第 L162-L167 行：AW valid 在 ready 到来前不得撤销，否则打印 AWVALID 错误。
* 第 L170-L175 行：W valid 使用同样的稳定性规则。
* 第 L178-L183 行：AR valid 使用同样的稳定性规则。

关键代码（``shared/rtl/axi4_intf.sv:L177-L202``）：

.. code-block:: systemverilog

     // ARVALID must remain asserted until ARREADY
     property ar_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       arvalid && !arready |=> arvalid;
     endproperty
     assert property (ar_valid_stable) else
       $error("AXI4: ARVALID deasserted before ARREADY");

     // BVALID must remain asserted until BREADY
     property b_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       bvalid && !bready |=> bvalid;
     endproperty
     assert property (b_valid_stable) else
       $error("AXI4: BVALID deasserted before BREADY");

     // RVALID must remain asserted until RREADY (or RLAST)
     property r_valid_stable;
       @(posedge clk) disable iff (!rst_n)
       rvalid && !rready |=> rvalid;
     endproperty
     assert property (r_valid_stable) else

逐段解释：

* 第 L177-L183 行：AR 检查与上一片重叠展示，便于把后续 B/R assertion 放在同一片中。
* 第 L185-L191 行：B valid 在 B ready 前保持有效，覆盖写响应通道。
* 第 L193-L199 行：R valid 在 R ready 前保持有效，覆盖读数据通道。注释提到 ``RLAST``，
  但 property 本身只检查 ``rvalid && !rready |=> rvalid``。

关键代码（``shared/rtl/axi4_intf.sv:L198-L204``）：

.. code-block:: systemverilog

     assert property (r_valid_stable) else
       $error("AXI4: RVALID deasserted before RREADY");

     `endif
     // pragma translate_on

   endinterface

逐段解释：

* 第 L198-L199 行：R valid assertion 失败时打印 ``AXI4: RVALID deasserted before RREADY``。
* 第 L201-L202 行：结束非 synthesis assertion 区域。
* 第 L204 行：interface 结束，确认该文件不包含 memory model 或桥接器逻辑。

接口关系：

* 被调用：仿真器在 ``ifndef SYNTHESIS`` 条件成立时检查这些 property。
* 调用：assertion 失败调用 ``$error``。
* 共享状态：读取 ``rst_n`` 和五个 channel 的 valid/ready 信号。

§4  ``axi4_slave_mem.sv`` — 行为级 AXI4 slave memory
----------------------------------------------------

``axi4_slave_mem`` 是验证平台行为级内存模型。它使用 byte 级 associative array 存储数据，
通过独立写 FSM 和读 FSM 响应 AXI4 事务，并提供 backdoor byte、HEX、binary 加载任务。
当前文件没有 mailbox PASS/FAIL 解析逻辑；mailbox 相关行为位于 TB 或测试基础设施的其它源码中。

§4.1  参数、error injection 与 AXI 端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明可参数化地址宽度、数据宽度、ID 宽度、内存大小和固定响应延迟，并暴露 AXI4 读写端口。

关键代码（``shared/rtl/axi4_slave_mem.sv:L8-L21``）：

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

逐段解释：

* 第 L8-L14 行：模块参数默认匹配 32-bit address、64-bit data、4-bit ID、64 MB memory 和 0-cycle
  固定响应延迟。``MEM_SIZE`` 在当前文件中作为参数声明存在，但 byte associative array 没有用它限制地址范围。
* 第 L15-L16 行：``clk`` 和 ``rst_n`` 驱动读写 FSM。
* 第 L18-L21 行：error injection 控制来自 UVM driver，打开后 B/R response 使用强制值。

关键代码（``shared/rtl/axi4_slave_mem.sv:L23-L60``）：

.. code-block:: systemverilog

     // Write Address Channel
     input  logic [ID_WIDTH-1:0]     awid,
     input  logic [ADDR_WIDTH-1:0]   awaddr,
     input  logic [7:0]              awlen,
     input  logic [2:0]              awsize,
     input  logic [1:0]              awburst,
     input  logic                    awvalid,
     output logic                    awready,

     // Write Data Channel
     input  logic [DATA_WIDTH-1:0]   wdata,
     input  logic [DATA_WIDTH/8-1:0] wstrb,
     input  logic                    wlast,
     input  logic                    wvalid,
     output logic                    wready,

     // Write Response Channel
     output logic [ID_WIDTH-1:0]     bid,
     output logic [1:0]              bresp,
     output logic                    bvalid,
     input  logic                    bready,

逐段解释：

* 第 L23-L30 行：AW channel 接收写 ID、地址、len、size、burst 和 valid，输出 ready。
* 第 L32-L37 行：W channel 接收 data、byte strobe、last 和 valid，输出 ready。
* 第 L39-L43 行：B channel 输出 ID、response、valid，接收 ready。写 FSM 在 ``wlast`` 后进入
  response 状态。

关键代码（``shared/rtl/axi4_slave_mem.sv:L45-L60``）：

.. code-block:: systemverilog

     // Read Address Channel
     input  logic [ID_WIDTH-1:0]     arid,
     input  logic [ADDR_WIDTH-1:0]   araddr,
     input  logic [7:0]              arlen,
     input  logic [2:0]              arsize,
     input  logic [1:0]              arburst,
     input  logic                    arvalid,
     output logic                    arready,

     // Read Data Channel
     output logic [ID_WIDTH-1:0]     rid,
     output logic [DATA_WIDTH-1:0]   rdata,
     output logic [1:0]              rresp,
     output logic                    rlast,
     output logic                    rvalid,
     input  logic                    rready

逐段解释：

* 第 L45-L52 行：AR channel 接收读 ID、地址、len、size、burst 和 valid，输出 ready。
* 第 L54-L60 行：R channel 输出 ID、data、response、last、valid，接收 ready。

接口关系：

* 被调用：TB top 实例化 ``lsu_mem``、``ifu_mem``、``sb_mem`` 三个 ``axi4_slave_mem``。
* 调用：端口声明不调用函数；后续 FSM 调用 ``write_mem``、``read_mem`` 和 ``calc_next_addr``。
* 共享状态：共享 clock/reset、error injection 信号、AXI channel 和内部 ``mem``。

§4.2  byte associative memory 与写状态寄存器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义 byte 级内存数组、写 FSM 状态枚举和写事务缓存寄存器。

关键代码（``shared/rtl/axi4_slave_mem.sv:L63-L85``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Memory Array
     //--------------------------------------------------------------------------
     logic [7:0] mem [bit [ADDR_WIDTH-1:0]];

     //--------------------------------------------------------------------------
     // Write Channel State Machine
     //--------------------------------------------------------------------------
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

逐段解释：

* 第 L63-L67 行：``mem`` 是以地址为 key 的 byte associative array。未写入地址在 ``read_mem`` 中返回
  ``8'h00``，而不是预先分配 64 MB 连续数组。
* 第 L71-L75 行：写 FSM 有 idle、data、response 三个状态。
* 第 L77-L85 行：写事务缓存保存 ID、地址、len、size、burst、beat 计数和 response delay 计数。
  ``wr_next_addr`` 声明存在，但当前片段中实际更新地址使用 ``wr_addr <= calc_next_addr(...)``。

接口关系：

* 被调用：写 FSM 和 backdoor/load task 读写 ``mem``。
* 调用：本节不调用任务。
* 共享状态：``mem``、``wr_state``、``wr_*`` 寄存器。

§4.3  写 FSM：地址握手、数据写入与 B response
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 AW handshake 后收集 W beats，按 ``wstrb`` 写 byte memory，并在 ``wlast`` 后返回 B response。

关键代码（``shared/rtl/axi4_slave_mem.sv:L87-L112``）：

.. code-block:: systemverilog

     // Write state machine
     always_ff @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
         wr_state     <= WR_IDLE;
         awready      <= 1'b0;
         wready       <= 1'b0;
         bvalid       <= 1'b0;
         bid          <= '0;
         bresp        <= '0;
         wr_beat_cnt  <= '0;
         wr_delay_cnt <= '0;
       end else begin
         case (wr_state)
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

逐段解释：

* 第 L87-L98 行：异步低有效 reset 将写 FSM 拉回 ``WR_IDLE``，并清空 ready/valid、ID、response、计数。
* 第 L100-L112 行：``WR_IDLE`` 拉高 ``awready``；当 ``awvalid && awready`` 成立时缓存 AW 信息，
  关闭 ``awready``，打开 ``wready``，进入 ``WR_DATA``。

关键代码（``shared/rtl/axi4_slave_mem.sv:L115-L136``）：

.. code-block:: systemverilog

           WR_DATA: begin
             if (wvalid && wready) begin
               // Write data to memory
               write_mem(wr_addr, wdata, wstrb, wr_size);

               if (wlast) begin
                 wready <= 1'b0;
                 if (RESPONSE_DELAY == 0) begin
                   bvalid <= 1'b1;
                   bid    <= wr_id;
                   bresp  <= error_inject_mode ? force_bresp : 2'b00;
                   wr_state <= WR_RESP;
                 end else begin
                   wr_delay_cnt <= RESPONSE_DELAY;
                   wr_state     <= WR_RESP;
                 end
               end else begin
                 // Calculate next address for burst
                 wr_addr      <= calc_next_addr(wr_addr, wr_size, wr_burst, wr_len);
                 wr_beat_cnt  <= wr_beat_cnt + 1;
               end
             end

逐段解释：

* 第 L115-L119 行：``WR_DATA`` 只在 ``wvalid && wready`` 时调用 ``write_mem``，写入地址为当前
  ``wr_addr``。
* 第 L120-L130 行：遇到 ``wlast`` 后停止接收写数据；如果 ``RESPONSE_DELAY == 0``，立即拉起
  ``bvalid``，``bid`` 返回 ``wr_id``，``bresp`` 在 error injection 与 OKAY 之间选择。
* 第 L131-L135 行：非 last beat 通过 ``calc_next_addr`` 更新地址，并递增 ``wr_beat_cnt``。

关键代码（``shared/rtl/axi4_slave_mem.sv:L139-L156``）：

.. code-block:: systemverilog

           WR_RESP: begin
             if (wr_delay_cnt > 0) begin
               wr_delay_cnt <= wr_delay_cnt - 1;
             end else begin
               bvalid <= 1'b1;
               bid    <= wr_id;
               bresp  <= error_inject_mode ? force_bresp : 2'b00;
               if (bready) begin
                 bvalid  <= 1'b0;
                 wr_state <= WR_IDLE;
               end
             end
           end

           default: wr_state <= WR_IDLE;
         endcase
       end
     end

逐段解释：

* 第 L139-L142 行：如果设置了 ``RESPONSE_DELAY``，``WR_RESP`` 先倒计时。
* 第 L143-L146 行：倒计时结束后输出 ``bvalid``、``bid`` 和 ``bresp``。response 选择逻辑与
  零延迟路径一致。
* 第 L146-L149 行：当 master 拉高 ``bready`` 时清掉 ``bvalid`` 并回到 ``WR_IDLE``。
* 第 L153-L156 行：default 分支回到 idle，结束写 FSM。

接口关系：

* 被调用：由 ``clk`` 驱动自动执行。
* 调用：调用 ``write_mem`` 和 ``calc_next_addr``。
* 共享状态：读写 ``wr_state``、``wr_addr``、``wr_id``、``wr_len``、``wr_size``、``wr_burst``、
  ``wr_beat_cnt``、``wr_delay_cnt``、``mem`` 和 B channel 信号。

§4.4  读状态寄存器与 AR 接收
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义读 FSM 状态，并在 AR handshake 后缓存读事务参数。

关键代码（``shared/rtl/axi4_slave_mem.sv:L161-L174``）：

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

逐段解释：

* 第 L161-L165 行：读 FSM 有 ``RD_IDLE``、``RD_DATA`` 和 ``RD_WAIT`` 三个状态。
* 第 L167-L174 行：读事务寄存器保存 ID、地址、len、size、burst、beat 计数和 delay 计数。

关键代码（``shared/rtl/axi4_slave_mem.sv:L176-L211``）：

.. code-block:: systemverilog

     // Read state machine
     always_ff @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
         rd_state     <= RD_IDLE;
         arready      <= 1'b0;
         rvalid       <= 1'b0;
         rlast        <= 1'b0;
         rid          <= '0;
         rdata        <= '0;
         rresp        <= '0;
         rd_beat_cnt  <= '0;
         rd_delay_cnt <= '0;
       end else begin
         case (rd_state)
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

逐段解释：

* 第 L176-L188 行：reset 清空读 FSM、AR ready、R valid/last、R ID/data/response 和计数器。
* 第 L190-L199 行：``RD_IDLE`` 拉高 ``arready``；AR handshake 后缓存 ``arid``、``araddr``、
  ``arlen``、``arsize`` 和 ``arburst``。
* 第 L200-L211 行开始处理零延迟和非零延迟路径，下一节继续解释。

接口关系：

* 被调用：由 ``clk`` 驱动自动执行。
* 调用：接收阶段尚未调用 ``read_mem``，零延迟分支会在下一片调用。
* 共享状态：``rd_state``、``arready``、``rd_*`` 和 R channel 寄存器。

§4.5  读 FSM：延迟、R beat 与 burst 地址
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 ``RESPONSE_DELAY`` 发送第一个 R beat，并在每次 ``rvalid && rready`` 后推进 burst。

关键代码（``shared/rtl/axi4_slave_mem.sv:L200-L224``）：

.. code-block:: systemverilog

               if (RESPONSE_DELAY == 0) begin
                 rvalid <= 1'b1;
                 rdata  <= read_mem(araddr, arsize);
                 rlast  <= (arlen == 0);
                 rid    <= arid;
                 rresp  <= error_inject_mode ? force_rresp : 2'b00;
                 rd_state <= RD_DATA;
               end else begin
                 rd_delay_cnt <= RESPONSE_DELAY;
                 rd_state     <= RD_WAIT;
               end
             end
           end

           RD_WAIT: begin
             if (rd_delay_cnt > 0) begin
               rd_delay_cnt <= rd_delay_cnt - 1;
             end else begin
               rvalid   <= 1'b1;
               rdata    <= read_mem(rd_addr, rd_size);
               rlast    <= (rd_len == 0);
               rid      <= rd_id;
               rresp    <= error_inject_mode ? force_rresp : 2'b00;
               rd_state <= RD_DATA;

逐段解释：

* 第 L200-L206 行：零延迟读在 AR handshake 后立即设置 ``rvalid``，调用 ``read_mem`` 读取
  ``araddr``，并根据 ``arlen == 0`` 设置 single-beat 的 ``rlast``。
* 第 L207-L210 行：非零延迟读进入 ``RD_WAIT`` 并加载 ``rd_delay_cnt``。
* 第 L214-L224 行：``RD_WAIT`` 倒计时结束后调用 ``read_mem(rd_addr, rd_size)``，设置 R channel
  和 response，再进入 ``RD_DATA``。

关键代码（``shared/rtl/axi4_slave_mem.sv:L227-L248``）：

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
               end
             end
           end

           default: rd_state <= RD_IDLE;
         endcase
       end
     end

逐段解释：

* 第 L227-L233 行：当当前 R beat 被接受且 ``rd_beat_cnt == rd_len`` 时，清 ``rvalid`` 和
  ``rlast``，回到 ``RD_IDLE``。
* 第 L234-L241 行：非最后 beat 先计算下一地址、递增 beat 计数，再为下一拍准备 ``rdata``、
  ``rlast`` 和 ``rid``。源码中 ``rdata <= read_mem(rd_addr, rd_size)`` 读取的是赋值前的
  ``rd_addr`` 值，这是非阻塞赋值语义下需要注意的实现细节。
* 第 L245-L248 行：default 分支回到 idle，结束读 FSM。

接口关系：

* 被调用：由 ``clk`` 驱动自动执行。
* 调用：调用 ``read_mem`` 和 ``calc_next_addr``。
* 共享状态：读写 ``rd_addr``、``rd_beat_cnt``、``rd_delay_cnt`` 和 R channel 信号。

§4.6  ``write_mem`` 与 ``read_mem`` — byte 级访问
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：按 byte strobe 写入 byte associative array，并在未初始化地址读出 0。

关键代码（``shared/rtl/axi4_slave_mem.sv:L253-L264``）：

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

逐段解释：

* 第 L253-L258 行：``write_mem`` 输入地址、data、strobe 和 size。当前任务签名接收 ``size``，
  但任务体没有使用 ``size``。
* 第 L259-L263 行：循环覆盖一个 data beat 的所有 byte lane；只有 ``strb[i]`` 为 1 的 byte
  被写到 ``mem[addr + i]``。
* 第 L264 行：任务结束，不返回状态，也不检查地址范围。

关键代码（``shared/rtl/axi4_slave_mem.sv:L266-L279``）：

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

逐段解释：

* 第 L266-L270 行：``read_mem`` 返回一个 data beat 宽度的数据，并把本地 ``data`` 初始化为 0。
  当前函数签名接收 ``size``，函数体没有使用 ``size`` 限制读取 byte 数。
* 第 L272-L277 行：每个 byte lane 单独检查 ``mem.exists(addr + i)``；不存在则返回 0。
* 第 L278-L279 行：返回拼好的 ``data``。

接口关系：

* 被调用：写 FSM 调用 ``write_mem``；读 FSM 调用 ``read_mem``。
* 调用：两个 helper 都不调用其它任务。
* 共享状态：读写 ``mem``。

§4.7  ``calc_next_addr`` — burst 地址推进
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 ``size`` 和 ``burst`` 计算下一 beat 地址，支持 FIXED、INCR 和 WRAP。

关键代码（``shared/rtl/axi4_slave_mem.sv:L284-L315``）：

.. code-block:: systemverilog

     function automatic logic [ADDR_WIDTH-1:0] calc_next_addr(
       input logic [ADDR_WIDTH-1:0] addr,
       input logic [2:0]            size,
       input logic [1:0]            burst,
       input logic [7:0]            len
     );
       logic [ADDR_WIDTH-1:0] next_addr;
       int unsigned bytes;
       int unsigned wrap_boundary;

       bytes = 1 << size;

       case (burst)
         2'b00: begin  // FIXED
           next_addr = addr;
         end
         2'b01: begin  // INCR
           next_addr = addr + bytes;
         end
         2'b10: begin  // WRAP
           wrap_boundary = bytes * (len + 1);
           next_addr = addr + bytes;
           // Check for wrap
           if ((next_addr % wrap_boundary) == 0) begin

逐段解释：

* 第 L284-L292 行：函数输入当前地址、size、burst 和 len，声明 ``next_addr``、``bytes``、
  ``wrap_boundary``。
* 第 L294 行：每个 beat 的 byte 数用 ``1 << size`` 计算。
* 第 L296-L302 行：``2'b00`` 保持地址不变，``2'b01`` 地址加 ``bytes``。
* 第 L303-L307 行：``2'b10`` 计算 wrap boundary，并先按 INCR 方式加 ``bytes``。

关键代码（``shared/rtl/axi4_slave_mem.sv:L303-L315``）：

.. code-block:: systemverilog

         2'b10: begin  // WRAP
           wrap_boundary = bytes * (len + 1);
           next_addr = addr + bytes;
           // Check for wrap
           if ((next_addr % wrap_boundary) == 0) begin
             next_addr = next_addr - wrap_boundary;
           end
         end
         default: next_addr = addr + bytes;
       endcase

       return next_addr;
     endfunction

逐段解释：

* 第 L303-L310 行：WRAP 分支在 ``next_addr`` 到达 wrap boundary 的整数倍时减去 ``wrap_boundary``。
* 第 L311 行：未知 burst 编码按 ``addr + bytes`` 处理。
* 第 L314-L315 行：返回计算结果。

接口关系：

* 被调用：写 FSM 的非 last beat 和读 FSM 的非 last beat 调用该函数。
* 调用：该函数不调用其它 helper。
* 共享状态：无；全部基于输入计算。

§4.8  backdoor byte 与文件加载任务
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供测试加载用的 backdoor 单 byte 读写、HEX 文本加载、binary 数组加载和清空内存任务。

关键代码（``shared/rtl/axi4_slave_mem.sv:L321-L338``）：

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

逐段解释：

* 第 L321-L327 行：``backdoor_write_byte`` 直接写 ``mem[addr]``，不走 AXI handshake。
* 第 L329-L338 行：``backdoor_read_byte`` 直接读取 ``mem``；地址不存在时返回 ``8'h00``。

关键代码（``shared/rtl/axi4_slave_mem.sv:L341-L366``）：

.. code-block:: systemverilog

     // Load HEX file into memory
     task load_hex(input string hex_file);
       int fd;
       int fgets_status;
       int scan_status;
       string line;
       logic [ADDR_WIDTH-1:0] addr;
       logic [7:0] data;

       fd = $fopen(hex_file, "r");
       if (fd == 0) begin
         $error("Failed to open HEX file: %s", hex_file);
         return;
       end

       while (!$feof(fd)) begin
         line = "";
         fgets_status = $fgets(line, fd);
         if (fgets_status == 0) begin
           continue;
         end
         // Parse hex line (simplified - assumes @address format)
         if (line.len() > 0 && line[0] == "@") begin
           scan_status = $sscanf(line, "@%h", addr);
           if (scan_status != 1) begin

逐段解释：

* 第 L341-L348 行：``load_hex`` 声明文件句柄、解析状态、当前行、地址和单 byte data。
* 第 L349-L353 行：用 ``$fopen`` 打开 HEX 文件；失败时 ``$error`` 并返回。
* 第 L355-L366 行：逐行读取；以 ``@`` 开头的行被解析为地址，解析失败时报告 malformed address。

关键代码（``shared/rtl/axi4_slave_mem.sv:L361-L380``）：

.. code-block:: systemverilog

         // Parse hex line (simplified - assumes @address format)
         if (line.len() > 0 && line[0] == "@") begin
           scan_status = $sscanf(line, "@%h", addr);
           if (scan_status != 1) begin
             $error("Malformed HEX address line in %s: %s", hex_file, line);
           end
         end else if (line.len() > 0) begin
           scan_status = $sscanf(line, "%h", data);
           if (scan_status == 1) begin
             mem[addr] = data;
             addr = addr + 1;
           end else begin
             $error("Malformed HEX data line in %s: %s", hex_file, line);
           end
         end
       end

       $fclose(fd);
       $display("Loaded HEX file: %s", hex_file);
     endtask

逐段解释：

* 第 L361-L366 行：地址行必须匹配 ``@%h``。
* 第 L367-L374 行：非空数据行按 ``%h`` 解析为 byte；解析成功后写 ``mem[addr]`` 并递增地址，
  解析失败时报告 malformed data。
* 第 L378-L380 行：关闭文件并打印加载完成消息。

关键代码（``shared/rtl/axi4_slave_mem.sv:L382-L396``）：

.. code-block:: systemverilog

     // Load binary data into memory at specified address
     task load_binary(
       input logic [ADDR_WIDTH-1:0] base_addr,
       input logic [7:0] data[],
       input int size
     );
       for (int i = 0; i < size; i++) begin
         mem[base_addr + i] = data[i];
       end
     endtask

     // Clear memory
     task clear_memory();
       mem.delete();
     endtask

逐段解释：

* 第 L382-L391 行：``load_binary`` 把输入 byte 数组从 ``base_addr`` 开始逐 byte 写入 ``mem``。
* 第 L393-L396 行：``clear_memory`` 调用 associative array 的 ``delete`` 清空全部内容。

接口关系：

* 被调用：测试加载路径可通过层次引用调用这些 backdoor task。
* 调用：``load_hex`` 调用 ``$fopen``、``$fgets``、``$sscanf``、``$fclose``、``$display`` 和 ``$error``。
* 共享状态：全部任务读写 ``mem``。

§5  TB 顶层连接：三组 memory、三组 interface、DMA tie-off
---------------------------------------------------------

当前 :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` 实例化三组 ``axi4_slave_mem``：
``lsu_mem``、``ifu_mem``、``sb_mem``。同一文件创建三组 ``axi4_intf`` 并注入给 UVM agent。
DMA AXI 输入在当前 TB 中被 tie 到 inactive 值，没有实例化 ``dma_mem``。

§5.1  ``lsu_mem`` — 数据 AXI4 memory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 LSU AXI4 master channel 接到行为级 ``axi4_slave_mem``，并把 error injection sideband
接到 ``lsu_axi_intf``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L409-L420``）：

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

逐段解释：

* 第 L409-L415 行：``lsu_mem`` 参数使用 32-bit 地址、64-bit 数据、``RV_LSU_BUS_TAG`` ID 宽度和
  64 MB memory size。
* 第 L416-L420 行：clock/reset 来自 ``core_clk`` 和 ``rst_l``；error injection sideband 来自
  ``lsu_axi_intf``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L421-L450``）：

.. code-block:: systemverilog

       .awid     (lsu_axi_awid),
       .awaddr   (lsu_axi_awaddr),
       .awlen    (lsu_axi_awlen),
       .awsize   (lsu_axi_awsize),
       .awburst  (lsu_axi_awburst),
       .awvalid  (lsu_axi_awvalid),
       .awready  (lsu_axi_awready),
       .wdata    (lsu_axi_wdata),
       .wstrb    (lsu_axi_wstrb),
       .wlast    (lsu_axi_wlast),
       .wvalid   (lsu_axi_wvalid),
       .wready   (lsu_axi_wready),
       .bid      (lsu_axi_bid),
       .bresp    (lsu_axi_bresp),
       .bvalid   (lsu_axi_bvalid),
       .bready   (lsu_axi_bready),
       .arid     (lsu_axi_arid),
       .araddr   (lsu_axi_araddr),
       .arlen    (lsu_axi_arlen),
       .arsize   (lsu_axi_arsize),
       .arburst  (lsu_axi_arburst),
       .arvalid  (lsu_axi_arvalid),
       .arready  (lsu_axi_arready),
       .rid      (lsu_axi_rid),
       .rdata    (lsu_axi_rdata),
       .rresp    (lsu_axi_rresp),
       .rlast    (lsu_axi_rlast),
       .rvalid   (lsu_axi_rvalid),
       .rready   (lsu_axi_rready)
     );

逐段解释：

* 第 L421-L436 行：LSU AW/W/B channel 全部连接到同名前缀 ``lsu_axi_*`` 信号。
* 第 L437-L449 行：LSU AR/R channel 连接到同名前缀 ``lsu_axi_*`` 信号。
* 第 L450 行：``lsu_mem`` 实例结束；该实例是 AXI4 slave memory，而 DUT LSU 是 AXI4 master。

接口关系：

* 被调用：TB top 在 elaboration 时实例化 ``lsu_mem``。
* 调用：``lsu_mem`` 内部调用自身 FSM 和 helper task。
* 共享状态：``lsu_axi_*`` channel、``lsu_axi_intf`` error injection 字段、``core_clk``、``rst_l``。

§5.2  ``ifu_mem`` 与 ``sb_mem`` — 指令与调试系统总线 memory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：以同样模式为 IFU 和 SB AXI4 master 连接行为级 memory。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L452-L493``）：

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
       .wdata    (ifu_axi_wdata),
       .wstrb    (ifu_axi_wstrb),
       .wlast    (ifu_axi_wlast),
       .wvalid   (ifu_axi_wvalid),
       .wready   (ifu_axi_wready),

逐段解释：

* 第 L452-L458 行：``ifu_mem`` 参数使用 IFU bus tag，实例名为 ``ifu_mem``。
* 第 L459-L463 行：IFU memory 的 error injection sideband 来自 ``ifu_axi_intf``。
* 第 L464-L493 行：片段展示 IFU AW/W 与部分 B/AR/R channel 连接模式，后续端口继续按
  ``ifu_axi_*`` 前缀连接。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L495-L536``）：

.. code-block:: systemverilog

     // SB memory (debug system bus) - connected to SB AXI4 master port
     axi4_slave_mem #(
       .ADDR_WIDTH (32),
       .DATA_WIDTH (64),
       .ID_WIDTH   (`RV_SB_BUS_TAG),
       .MEM_SIZE   (64 * 1024 * 1024)
     ) sb_mem (
       .clk      (core_clk),
       .rst_n    (rst_l),
       .error_inject_mode (sb_axi_intf.error_inject_mode),
       .force_bresp       (sb_axi_intf.force_bresp),
       .force_rresp       (sb_axi_intf.force_rresp),
       .awid     (sb_axi_awid),
       .awaddr   (sb_axi_awaddr),
       .awlen    (sb_axi_awlen),
       .awsize   (sb_axi_awsize),
       .awburst  (sb_axi_awburst),
       .awvalid  (sb_axi_awvalid),
       .awready  (sb_axi_awready),
       .wdata    (sb_axi_wdata),
       .wstrb    (sb_axi_wstrb),
       .wlast    (sb_axi_wlast),
       .wvalid   (sb_axi_wvalid),
       .wready   (sb_axi_wready),

逐段解释：

* 第 L495-L501 行：``sb_mem`` 参数使用 SB bus tag，实例名为 ``sb_mem``。
* 第 L502-L506 行：SB memory 的 error injection sideband 来自 ``sb_axi_intf``。
* 第 L507-L536 行：片段展示 SB AW/W 与部分 B/AR/R channel 连接模式，后续端口继续按
  ``sb_axi_*`` 前缀连接。

接口关系：

* 被调用：TB top 实例化 ``ifu_mem`` 和 ``sb_mem``。
* 调用：两个实例内部调用 ``axi4_slave_mem`` 的读写 FSM。
* 共享状态：``ifu_axi_*``、``sb_axi_*`` channel 和对应 ``axi4_intf`` error injection 字段。

§5.3  DMA AXI 输入 tie-off
~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明当前 TB 没有外部 DMA AXI master memory 实例，而是把 DMA AXI 输入侧固定为 inactive。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L538-L564``）：

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

逐段解释：

* 第 L538-L539 行：注释说明 DMA port 当前没有外部 DMA master，并提醒 DUT output 不应被 TB 再 assign。
* 第 L541-L547 行：DMA AW 输入全部 tie 到 inactive 或 0。
* 第 L549-L554 行：DMA W 输入和 B ready tie 到 inactive 或 0。
* 第 L556-L564 行：DMA AR 输入和 R ready tie 到 inactive 或 0。

接口关系：

* 被调用：这些 continuous assign 在 TB top 中直接驱动 DMA 输入侧。
* 调用：不调用任务或模块。
* 共享状态：``dma_axi_*`` 输入信号。

§5.4  ``axi4_intf`` 实例与 UVM config_db
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 LSU、IFU、SB 三组 AXI4 总线创建 UVM 可见 interface，并通过 config_db 注入对应 agent。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L591-L602``）：

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

* 第 L591-L594 行：TB 注释说明这些 interface 供 UVM agent 使用，并使用 DUT 实际 tag 宽度。
* 第 L595-L602 行：分别创建 ``lsu_axi_intf``、``ifu_axi_intf``、``sb_axi_intf``，三者 clock/reset
  均接 ``core_clk`` 和 ``rst_l``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1102-L1110``）：

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

逐段解释：

* 第 L1102-L1107 行：initial block 注入通用 ``tb_vif``。
* 第 L1108-L1110 行：三组 AXI4 virtual interface 分别注入到匹配 ``*lsu_agent*``、
  ``*ifu_agent*``、``*sb_agent*`` 的 UVM 组件路径。当前片段没有 ``dma_agent`` 注入。

接口关系：

* 被调用：UVM agent build phase 通过 ``uvm_config_db::get`` 取回 virtual interface。
* 调用：TB top 调用 ``uvm_config_db::set``。
* 共享状态：``lsu_axi_intf``、``ifu_axi_intf``、``sb_axi_intf``。

§5.5  ADR-0002 与当前源码的对齐方式
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：说明 ADR 记录了 AXI4 passive monitoring 的设计决策，但本章以当前源码为准描述实例数量。

关键代码（``docs/adr/0002-axi4-passive-monitoring.md:L10-L16``）：

.. code-block:: text

   ## 决策

   - **AXI4 agent 设为 passive 模式**：仅监视器，不驱动
   - **TB top 实例化 4 个 `axi4_slave_mem`** 行为级模型（独立内存区，地址空间预映射）
   - monitor 把 AW/AR 与 W/R/B 通道按事务关联，发出 `axi4_seq_item`（包含 burst 全部 beats）
   - LSU 通道挂到 cosim agent 的 `dmem_port`，给 Spike 通知内存访问

逐段解释：

* 第 L12 行：ADR-0002 的决策要求 AXI4 agent 处于 passive 模式。
* 第 L13 行：ADR 文本写的是 4 个 ``axi4_slave_mem``。
* 第 L14-L15 行：ADR 还定义 monitor 事务关联和 LSU 到 cosim ``dmem_port`` 的方向。

当前源码核对：

* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` 第 L409、L452、L495 行分别实例化
  ``lsu_mem``、``ifu_mem``、``sb_mem``。
* 同一文件第 L538-L564 行把 DMA AXI 输入 tie 到 inactive 值。
* 因此本章描述当前源码时使用「三组 ``axi4_slave_mem`` 加 DMA tie-off」，并在参考资料中保留
  :ref:`adr-0002` 作为设计决策来源。

接口关系：

* 被调用：ADR 不参与编译；它约束文档和 review 时的设计背景。
* 调用：无。
* 共享状态：无运行时状态。

§6  ``eh2_veer`` 中的 AHB-Lite generate 分支
--------------------------------------------

当 ``pt.BUILD_AHB_LITE == 1`` 时，``eh2_veer`` 实例化三组 ``axi4_to_ahb``，把 LSU、IFU、SB
的 AXI master 侧转换到 AHB-Lite；还实例化一组 ``ahb_to_axi4``，把 DMA AHB slave 侧转换到
DMA AXI pins。该逻辑属于 DUT RTL，不属于 ``shared/rtl``。

§6.1  generate 条件与 LSU ``axi4_to_ahb``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 AHB-Lite build 中为 LSU 端口创建 AXI4 到 AHB-Lite 桥。

关键代码（``rtl/design/eh2_veer.sv:L1143-L1172``）：

.. code-block:: systemverilog

      if (pt.BUILD_AHB_LITE == 1) begin: Gen_AXI_To_AHB

         // AXI4 -> AHB Gasket for LSU
         axi4_to_ahb #(.NUM_THREADS(pt.NUM_THREADS),
                       .TAG(pt.LSU_BUS_TAG)) lsu_axi4_to_ahb (
            .clk(free_l2clk),
            .free_clk(free_clk),
            .rst_l(core_rst_l),
            .clk_override(dec_tlu_bus_clk_override),
            .bus_clk_en(lsu_bus_clk_en),
            .dec_tlu_force_halt(dec_tlu_force_halt),

            // AXI Write Channels
            .axi_awvalid(lsu_axi_awvalid),
            .axi_awready(lsu_axi_awready_ahb),
            .axi_awid(lsu_axi_awid[pt.LSU_BUS_TAG-1:0]),
            .axi_awaddr(lsu_axi_awaddr[31:0]),
            .axi_awsize(lsu_axi_awsize[2:0]),
            .axi_awprot(lsu_axi_awprot[2:0]),

            .axi_wvalid(lsu_axi_wvalid),
            .axi_wready(lsu_axi_wready_ahb),
            .axi_wdata(lsu_axi_wdata[63:0]),
            .axi_wstrb(lsu_axi_wstrb[7:0]),
            .axi_wlast(lsu_axi_wlast),

逐段解释：

* 第 L1143 行：所有桥接器都在 ``pt.BUILD_AHB_LITE == 1`` 条件下生成。
* 第 L1145-L1147 行：LSU 桥实例名为 ``lsu_axi4_to_ahb``，参数 ``NUM_THREADS`` 和
  ``TAG`` 分别来自 ``pt.NUM_THREADS``、``pt.LSU_BUS_TAG``。
* 第 L1148-L1153 行：LSU 桥使用 ``free_l2clk``、``free_clk``、``core_rst_l``、bus clock override、
  ``lsu_bus_clk_en`` 和 ``dec_tlu_force_halt``。
* 第 L1155-L1172 行：片段展示 LSU AXI 写地址、写数据和写 response 的连接。

关键代码（``rtl/design/eh2_veer.sv:L1174-L1204``）：

.. code-block:: systemverilog

            // AXI Read Channels
            .axi_arvalid(lsu_axi_arvalid),
            .axi_arready(lsu_axi_arready_ahb),
            .axi_arid(lsu_axi_arid[pt.LSU_BUS_TAG-1:0]),
            .axi_araddr(lsu_axi_araddr[31:0]),
            .axi_arsize(lsu_axi_arsize[2:0]),
            .axi_arprot(lsu_axi_arprot[2:0]),

            .axi_rvalid(lsu_axi_rvalid_ahb),
            .axi_rready(lsu_axi_rready),
            .axi_rid(lsu_axi_rid_ahb[pt.LSU_BUS_TAG-1:0]),
            .axi_rdata(lsu_axi_rdata_ahb[63:0]),
            .axi_rresp(lsu_axi_rresp_ahb[1:0]),
            .axi_rlast(lsu_axi_rlast_ahb),

            // AHB-LITE signals
            .ahb_haddr(lsu_haddr[31:0]),
            .ahb_hburst(lsu_hburst),
            .ahb_hmastlock(lsu_hmastlock),
            .ahb_hprot(lsu_hprot[3:0]),
            .ahb_hsize(lsu_hsize[2:0]),
            .ahb_htrans(lsu_htrans[1:0]),
            .ahb_hwrite(lsu_hwrite),
            .ahb_hwdata(lsu_hwdata[63:0]),

            .ahb_hrdata(lsu_hrdata[63:0]),
            .ahb_hready(lsu_hready),
            .ahb_hresp(lsu_hresp),

            .*
         );

逐段解释：

* 第 L1174-L1187 行：LSU AXI read channel 连接到 ``*_ahb`` 后缀的中间 response 信号。
* 第 L1189-L1201 行：AHB-Lite 输出和输入连接到 ``lsu_h*`` 信号。
* 第 L1203-L1204 行：``.*`` 补齐同名端口，实例结束。

接口关系：

* 被调用：``eh2_veer`` generate 分支实例化 ``axi4_to_ahb``。
* 调用：桥接器内部调用 helper function，并驱动 AHB-Lite channel。
* 共享状态：``pt.BUILD_AHB_LITE``、LSU AXI 信号、LSU AHB-Lite 信号。

§6.2  IFU 与 SB ``axi4_to_ahb`` 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在同一 generate 分支中为 IFU 和 SB 端口实例化 AXI4 到 AHB-Lite 桥。

关键代码（``rtl/design/eh2_veer.sv:L1206-L1263``）：

.. code-block:: systemverilog

         axi4_to_ahb #(.NUM_THREADS(pt.NUM_THREADS),
                       .TAG(pt.IFU_BUS_TAG)) ifu_axi4_to_ahb (
            .clk(free_l2clk),
            .free_clk(free_clk),
            .rst_l(core_rst_l),
            .clk_override(dec_tlu_bus_clk_override),
            .bus_clk_en(ifu_bus_clk_en),
            .dec_tlu_force_halt(dec_tlu_force_halt),

             // AHB-Lite signals
            .ahb_haddr(haddr[31:0]),
            .ahb_hburst(hburst),
            .ahb_hmastlock(hmastlock),
            .ahb_hprot(hprot[3:0]),
            .ahb_hsize(hsize[2:0]),
            .ahb_htrans(htrans[1:0]),
            .ahb_hwrite(hwrite),
            .ahb_hwdata(hwdata_nc[63:0]),

            .ahb_hrdata(hrdata[63:0]),
            .ahb_hready(hready),
            .ahb_hresp(hresp),

逐段解释：

* 第 L1206-L1207 行：IFU 桥实例名为 ``ifu_axi4_to_ahb``，``TAG`` 使用 ``pt.IFU_BUS_TAG``。
* 第 L1208-L1213 行：IFU 桥使用 core reset 和 IFU bus clock enable。
* 第 L1215-L1227 行：IFU 的 AHB-Lite 侧连接到 ``haddr``、``hburst``、``hprot``、``hsize``、
  ``htrans``、``hwrite``、``hwdata_nc``、``hrdata``、``hready`` 和 ``hresp``。

关键代码（``rtl/design/eh2_veer.sv:L1265-L1324``）：

.. code-block:: systemverilog

         // AXI4 -> AHB Gasket for System Bus
         axi4_to_ahb #(.NUM_THREADS(pt.NUM_THREADS),
                       .TAG(pt.SB_BUS_TAG)) sb_axi4_to_ahb (
            .clk_override(dec_tlu_bus_clk_override),
            .rst_l(dbg_rst_l),
            .clk(free_l2clk),
            .free_clk(free_clk),
            .bus_clk_en(dbg_bus_clk_en),
            .dec_tlu_force_halt({pt.NUM_THREADS{1'b0}}),

            // AXI Write Channels
            .axi_awvalid(sb_axi_awvalid),
            .axi_awready(sb_axi_awready_ahb),
            .axi_awid(sb_axi_awid[pt.SB_BUS_TAG-1:0]),
            .axi_awaddr(sb_axi_awaddr[31:0]),
            .axi_awsize(sb_axi_awsize[2:0]),
            .axi_awprot(sb_axi_awprot[2:0]),

            .axi_wvalid(sb_axi_wvalid),
            .axi_wready(sb_axi_wready_ahb),
            .axi_wdata(sb_axi_wdata[63:0]),
            .axi_wstrb(sb_axi_wstrb[7:0]),
            .axi_wlast(sb_axi_wlast),

逐段解释：

* 第 L1265-L1267 行：SB 桥实例名为 ``sb_axi4_to_ahb``，``TAG`` 使用 ``pt.SB_BUS_TAG``。
* 第 L1268-L1273 行：SB 桥 reset 使用 ``dbg_rst_l``，clock enable 使用 ``dbg_bus_clk_en``，
  ``dec_tlu_force_halt`` 被固定为 ``{pt.NUM_THREADS{1'b0}}``。
* 第 L1275-L1324 行：片段展示 SB AXI 写侧连接；同一实例后续还连接读侧和 ``sb_h*`` AHB-Lite 侧。

接口关系：

* 被调用：``eh2_veer`` generate 分支实例化 IFU 和 SB 两个 ``axi4_to_ahb``。
* 调用：实例内部使用 ``axi4_to_ahb`` 的 FSM。
* 共享状态：IFU/SB AXI channel 和对应 AHB-Lite channel。

§6.3  DMA ``ahb_to_axi4`` 实例与 final AXI mux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 AHB-Lite build 中把 DMA AHB slave 侧转换回 DMA AXI pins，并在 final assignment 中选择 AHB 分支或原 AXI 分支。

关键代码（``rtl/design/eh2_veer.sv:L1326-L1387``）：

.. code-block:: systemverilog

         //AHB -> AXI4 Gasket for DMA
         ahb_to_axi4 #(.pt(pt),
                       .TAG(pt.DMA_BUS_TAG)) dma_ahb_to_axi4 (
            .clk_override(dec_tlu_bus_clk_override),
            .rst_l(core_rst_l),
            .clk(free_l2clk),
            .bus_clk_en(dma_bus_clk_en),

            // AXI Write Channels
            .axi_awvalid(dma_axi_awvalid_ahb),
            .axi_awready(dma_axi_awready),
            .axi_awid(dma_axi_awid_ahb[pt.DMA_BUS_TAG-1:0]),
            .axi_awaddr(dma_axi_awaddr_ahb[31:0]),
            .axi_awsize(dma_axi_awsize_ahb[2:0]),
            .axi_awprot(dma_axi_awprot_ahb[2:0]),
            .axi_awlen(dma_axi_awlen_ahb[7:0]),
            .axi_awburst(dma_axi_awburst_ahb[1:0]),

            .axi_wvalid(dma_axi_wvalid_ahb),
            .axi_wready(dma_axi_wready),
            .axi_wdata(dma_axi_wdata_ahb[63:0]),
            .axi_wstrb(dma_axi_wstrb_ahb[7:0]),

逐段解释：

* 第 L1326-L1328 行：DMA 桥方向与 LSU/IFU/SB 相反，实例名为 ``dma_ahb_to_axi4``。
* 第 L1329-L1332 行：DMA 桥使用 core reset、``free_l2clk`` 和 ``dma_bus_clk_en``。
* 第 L1334-L1348 行：DMA AXI 写侧输出使用 ``*_ahb`` 中间信号，再接到顶层 DMA AXI pins。

关键代码（``rtl/design/eh2_veer.sv:L1371-L1387``）：

.. code-block:: systemverilog

             // AHB signals
            .ahb_haddr(dma_haddr[31:0]),
            .ahb_hburst(dma_hburst),
            .ahb_hmastlock(dma_hmastlock),
            .ahb_hprot(dma_hprot[3:0]),
            .ahb_hsize(dma_hsize[2:0]),
            .ahb_htrans(dma_htrans[1:0]),
            .ahb_hwrite(dma_hwrite),
            .ahb_hwdata(dma_hwdata[63:0]),

            .ahb_hrdata(dma_hrdata[63:0]),
            .ahb_hreadyout(dma_hreadyout),
            .ahb_hresp(dma_hresp),
            .ahb_hreadyin(dma_hreadyin),
            .ahb_hsel(dma_hsel),
            .*
         );

逐段解释：

* 第 L1371-L1379 行：DMA AHB input side 包括地址、burst、lock、prot、size、trans、write 和 write data。
* 第 L1381-L1385 行：DMA AHB output side 包括 read data、readyout、response、readyin 和 select。
* 第 L1386-L1387 行：``.*`` 补齐同名端口并结束实例。

关键代码（``rtl/design/eh2_veer.sv:L1391-L1403``）：

.. code-block:: systemverilog

      // Drive the final AXI inputs
      assign lsu_axi_awready_int                 = pt.BUILD_AHB_LITE ? lsu_axi_awready_ahb : lsu_axi_awready;
      assign lsu_axi_wready_int                  = pt.BUILD_AHB_LITE ? lsu_axi_wready_ahb : lsu_axi_wready;
      assign lsu_axi_bvalid_int                  = pt.BUILD_AHB_LITE ? lsu_axi_bvalid_ahb : lsu_axi_bvalid;
      assign lsu_axi_bready_int                  = pt.BUILD_AHB_LITE ? lsu_axi_bready_ahb : lsu_axi_bready;
      assign lsu_axi_bresp_int[1:0]              = pt.BUILD_AHB_LITE ? lsu_axi_bresp_ahb[1:0] : lsu_axi_bresp[1:0];
      assign lsu_axi_bid_int[pt.LSU_BUS_TAG-1:0] = pt.BUILD_AHB_LITE ? lsu_axi_bid_ahb[pt.LSU_BUS_TAG-1:0] : lsu_axi_bid[pt.LSU_BUS_TAG-1:0];
      assign lsu_axi_arready_int                 = pt.BUILD_AHB_LITE ? lsu_axi_arready_ahb : lsu_axi_arready;
      assign lsu_axi_rvalid_int                  = pt.BUILD_AHB_LITE ? lsu_axi_rvalid_ahb : lsu_axi_rvalid;
      assign lsu_axi_rid_int[pt.LSU_BUS_TAG-1:0] = pt.BUILD_AHB_LITE ? lsu_axi_rid_ahb[pt.LSU_BUS_TAG-1:0] : lsu_axi_rid[pt.LSU_BUS_TAG-1:0];
      assign lsu_axi_rdata_int[63:0]             = pt.BUILD_AHB_LITE ? lsu_axi_rdata_ahb[63:0] : lsu_axi_rdata[63:0];
      assign lsu_axi_rresp_int[1:0]              = pt.BUILD_AHB_LITE ? lsu_axi_rresp_ahb[1:0] : lsu_axi_rresp[1:0];
      assign lsu_axi_rlast_int                   = pt.BUILD_AHB_LITE ? lsu_axi_rlast_ahb : lsu_axi_rlast;

逐段解释：

* 第 L1391-L1403 行：final AXI inputs 使用 ``pt.BUILD_AHB_LITE`` 选择 ``*_ahb`` 桥接分支或原始 AXI
  分支。片段展示 LSU 侧，IFU/SB/DMA 后续代码沿用同类 mux 结构。

接口关系：

* 被调用：``eh2_veer`` continuous assignment 在 elaboration 后持续驱动内部 AXI mux 信号。
* 调用：不调用任务或函数。
* 共享状态：``pt.BUILD_AHB_LITE``、``*_ahb`` 中间信号和原始 AXI pins。

§7  ``axi4_to_ahb.sv`` — AXI4 master 到 AHB-Lite master
-------------------------------------------------------

``axi4_to_ahb`` 接收 AXI4 master 请求，生成 AHB-Lite master 请求，再把 AHB-Lite response
转换回 AXI B/R response。该桥包含一个写缓冲、一个命令/数据 buffer、streaming read 状态和
AHB protocol assertion。

§7.1  模块参数、AXI 输入输出与 AHB-Lite 端口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 ``TAG``、``NUM_THREADS`` 参数和 AXI/AHB-Lite 两侧端口。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L24-L55``）：

.. code-block:: systemverilog

   module axi4_to_ahb
   import eh2_pkg::*;
   #(parameter TAG  = 1,
               NUM_THREADS = 1) (

      input                   clk,
      input                   free_clk,
      input                   rst_l,
      input                   scan_mode,
      input                   bus_clk_en,
      input                   clk_override,
      input [NUM_THREADS-1:0] dec_tlu_force_halt,

      // AXI signals
      // AXI Write Channels
      input  logic            axi_awvalid,
      output logic            axi_awready,
      input  logic [TAG-1:0]  axi_awid,
      input  logic [31:0]     axi_awaddr,
      input  logic [2:0]      axi_awsize,
      input  logic [2:0]      axi_awprot,

      input  logic            axi_wvalid,
      output logic            axi_wready,
      input  logic [63:0]     axi_wdata,
      input  logic [7:0]      axi_wstrb,
      input  logic            axi_wlast,

      output logic            axi_bvalid,

逐段解释：

* 第 L24-L27 行：模块导入 ``eh2_pkg::*``，参数 ``TAG`` 控制 AXI ID 宽度，``NUM_THREADS`` 控制
  force halt 向量宽度。
* 第 L29-L35 行：clock/reset、scan、bus clock enable、clock override 和 ``dec_tlu_force_halt`` 输入。
* 第 L39-L55 行：AXI 写地址、写数据和写 response 端口。该桥只声明 ``axi_awsize`` 和
  ``axi_awprot``，没有 AW len/burst 端口。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L57-L85``）：

.. code-block:: systemverilog

      // AXI Read Channels
      input  logic            axi_arvalid,
      output logic            axi_arready,
      input  logic [TAG-1:0]  axi_arid,
      input  logic [31:0]     axi_araddr,
      input  logic [2:0]      axi_arsize,
      input  logic [2:0]      axi_arprot,

      output logic            axi_rvalid,
      input  logic            axi_rready,
      output logic [TAG-1:0]  axi_rid,
      output logic [63:0]     axi_rdata,
      output logic [1:0]      axi_rresp,
      output logic            axi_rlast,

      // AHB-Lite signals
      output logic [31:0]     ahb_haddr,       // ahb bus address
      output logic [2:0]      ahb_hburst,      // tied to 0
      output logic            ahb_hmastlock,   // tied to 0
      output logic [3:0]      ahb_hprot,       // tied to 4'b0011
      output logic [2:0]      ahb_hsize,       // size of bus transaction (possible values 0,1,2,3)
      output logic [1:0]      ahb_htrans,      // Transaction type (possible values 0,2 only right now)
      output logic            ahb_hwrite,      // ahb bus write
      output logic [63:0]     ahb_hwdata,      // ahb bus write data

逐段解释：

* 第 L57-L70 行：AXI read address 和 read data/response 端口。``axi_rlast`` 在后续组合逻辑中固定为 1。
* 第 L72-L80 行：AHB-Lite master 输出包括 address、burst、lock、prot、size、trans、write 和 write data。
* 第 L82-L85 行：AHB-Lite slave 返回 read data、ready 和 response。

接口关系：

* 被调用：``eh2_veer`` 的 LSU、IFU、SB generate 实例调用该模块。
* 调用：模块内部调用 ``get_write_size``、``get_write_addr``、``get_nxtbyte_ptr``。
* 共享状态：AXI channel、AHB-Lite channel、clock/reset 和 force halt 信号。

§7.2  状态枚举与写 strobe helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义内部 FSM 状态，并把 AXI ``wstrb`` 转换成 AHB size 和低地址偏移。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L88-L91``）：

.. code-block:: systemverilog

      localparam ID   = 1;
      localparam PRTY = 1;
      typedef enum logic [2:0] {IDLE=3'b000, CMD_RD=3'b001, CMD_WR=3'b010, DATA_RD=3'b011, DATA_WR=3'b100, DONE=3'b101, STREAM_RD=3'b110, STREAM_ERR_RD=3'b111} state_t;
      state_t buf_state, buf_nxtstate;

逐段解释：

* 第 L88-L89 行：``ID`` 和 ``PRTY`` localparam 被定义为 1。当前片段后续未展示其使用。
* 第 L90-L91 行：主 FSM 包含 idle、读命令、写命令、读数据、写数据、done、streaming read 和
  streaming read error 八个状态。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L182-L193``）：

.. code-block:: systemverilog

      // Function to get the length from byte enable
      function automatic logic [1:0] get_write_size;
         input logic [7:0] byteen;

         logic [1:0]       size;

         size[1:0] = (2'b11 & {2{(byteen[7:0] == 8'hff)}}) |
                     (2'b10 & {2{((byteen[7:0] == 8'hf0) | (byteen[7:0] == 8'h0f))}}) |
                     (2'b01 & {2{((byteen[7:0] == 8'hc0) | (byteen[7:0] == 8'h30) | (byteen[7:0] == 8'h0c) | (byteen[7:0] == 8'h03))}});

         return size[1:0];
      endfunction // get_write_size

逐段解释：

* 第 L182-L186 行：``get_write_size`` 输入 8-bit byte enable，返回 2-bit size。
* 第 L188-L190 行：``8'hff`` 映射为 doubleword size，``8'hf0`` 或 ``8'h0f`` 映射为 word size，
  相邻 2-byte strobe 映射为 halfword size。
* 第 L192-L193 行：返回 ``size`` 并结束函数。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L195-L222``）：

.. code-block:: systemverilog

      // Function to get the length from byte enable
      function automatic logic [2:0] get_write_addr;
         input logic [7:0] byteen;

         logic [2:0]       addr;

         addr[2:0] = (3'h0 & {3{((byteen[7:0] == 8'hff) | (byteen[7:0] == 8'h0f) | (byteen[7:0] == 8'h03))}}) |
                     (3'h2 & {3{(byteen[7:0] == 8'h0c)}})                                                     |
                     (3'h4 & {3{((byteen[7:0] == 8'hf0) | (byteen[7:0] == 8'h03))}})                          |
                     (3'h6 & {3{(byteen[7:0] == 8'hc0)}});

         return addr[2:0];
      endfunction // get_write_addr

      // Function to get the next byte pointer
      function automatic logic [2:0] get_nxtbyte_ptr (logic [2:0] current_byte_ptr, logic [7:0] byteen, logic get_next);
         logic [2:0] start_ptr;

逐段解释：

* 第 L195-L207 行：``get_write_addr`` 根据 byte enable 选择 AHB 地址低 3 位，用于从 64-bit
  AXI strobe 中找到本次 AHB 写的起始 byte。
* 第 L209-L222 行：``get_nxtbyte_ptr`` 从当前 byte pointer 开始扫描下一个 enabled byte，
  写拆分状态机用它推进 byte lane。

接口关系：

* 被调用：FSM 和 buffer 输入组合逻辑调用这些 helper。
* 调用：helper 不调用其它任务。
* 共享状态：无，全基于输入组合计算。

§7.3  force halt 同步与 AXI ready/response 组合逻辑
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 ``dec_tlu_force_halt`` 同步到 bus clock 域，并根据内部 buffer 状态生成 AXI ready 和 B/R response。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L224-L260``）：

.. code-block:: systemverilog

      for (genvar i=0; i<NUM_THREADS; i++) begin
      // Create bus synchronized version of force halt
         assign dec_tlu_force_halt_bus[i] = dec_tlu_force_halt[i] | dec_tlu_force_halt_bus_q[i];
         assign dec_tlu_force_halt_bus_ns[i] = ~bus_clk_en & dec_tlu_force_halt_bus[i];
         rvdff  #(.WIDTH(1)) force_halt_busff(.din(dec_tlu_force_halt_bus_ns[i]), .dout(dec_tlu_force_halt_bus_q[i]), .clk(free_clk), .*);
      end

      // Write buffer
      assign wrbuf_en       = axi_awvalid & axi_awready & master_ready;
      assign wrbuf_data_en  = axi_wvalid & axi_wready & master_ready;
      assign wrbuf_cmd_sent = master_valid & master_ready & (master_opc[2:1] == 2'b01);
      assign wrbuf_rst      = (wrbuf_cmd_sent & ~wrbuf_en) | dec_tlu_force_halt_bus[wrbuf_tag[TAG-1]];

      assign axi_awready = ~(wrbuf_vld & ~wrbuf_cmd_sent) & master_ready;
      assign axi_wready  = ~(wrbuf_data_vld & ~wrbuf_cmd_sent) & master_ready;
      assign axi_arready = ~(wrbuf_vld & wrbuf_data_vld) & master_ready;
      assign axi_rlast   = 1'b1;

      assign wr_cmd_vld          = (wrbuf_vld & wrbuf_data_vld);

逐段解释：

* 第 L224-L229 行：每个 thread 的 force halt 通过 ``rvdff`` 在 ``free_clk`` 上保持，直到 bus clock enable
  重新允许前进。
* 第 L231-L236 行：写 buffer 分别捕获 AW 和 W，有写命令发出且没有新 AW 时清 buffer；force halt 也可清对应 tag。
* 第 L237-L240 行：AXI ready 取决于 buffer 是否空、命令是否已发出以及 ``master_ready``；``axi_rlast`` 固定为 1。
* 第 L242-L260 行：根据写 buffer 或 AR channel 形成 master command，并把 slave response 转换为 AXI B/R channel。

接口关系：

* 被调用：组合 assign 持续驱动 AXI ready/response。
* 调用：实例化 ``rvdff``。
* 共享状态：``wrbuf_*``、``master_*``、``slave_*``、``dec_tlu_force_halt_bus*``。

§7.4  主 FSM：IDLE、读命令与 streaming read
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：控制 AXI 命令进入 AHB-Lite transaction，并优化连续读命令的 streaming 路径。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L262-L306``）：

.. code-block:: systemverilog

    // FIFO state machine
      always_comb begin
         buf_nxtstate   = IDLE;
         buf_state_en   = 1'b0;
         buf_wr_en      = 1'b0;
         buf_data_wr_en = 1'b0;
         slvbuf_error_in   = 1'b0;
         slvbuf_error_en   = 1'b0;
         buf_write_in   = 1'b0;
         cmd_done       = 1'b0;
         trxn_done      = 1'b0;
         buf_cmd_byte_ptr_en = 1'b0;
         buf_cmd_byte_ptr[2:0] = '0;
         slave_valid_pre   = 1'b0;
         master_ready   = 1'b0;
         ahb_htrans[1:0]  = 2'b0;
         slvbuf_wr_en     = 1'b0;
         bypass_en        = 1'b0;
         rd_bypass_idle   = 1'b0;

         case (buf_state)
            IDLE: begin
                     master_ready   = 1'b1;
                     buf_write_in = (master_opc[2:1] == 2'b01);
                     buf_nxtstate = buf_write_in ? CMD_WR : CMD_RD;

逐段解释：

* 第 L262-L280 行：组合 FSM 先给所有控制信号默认值，避免保留上一状态组合输出。
* 第 L282-L295 行：``IDLE`` 接受 master command，判断读写方向，写入 buffer，设置 byte pointer，
  并可在同一拍发起 AHB ``NONSEQ``。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L296-L321``）：

.. code-block:: systemverilog

            CMD_RD: begin
                     buf_nxtstate    = (master_valid & (master_opc[2:0] == 3'b000))? STREAM_RD : DATA_RD;
                     buf_state_en    = ahb_hready_q & (ahb_htrans_q[1:0] != 2'b0) & ~ahb_hwrite_q;
                     cmd_done        = buf_state_en & ~master_valid;
                     slvbuf_wr_en    = buf_state_en;
                     master_ready  = buf_state_en & (buf_nxtstate == STREAM_RD);
                     buf_wr_en       = master_ready;
                     bypass_en       = master_ready & master_valid;
                     buf_cmd_byte_ptr[2:0] = bypass_en ? master_addr[2:0] : buf_addr[2:0];
                     ahb_htrans[1:0] = 2'b10 & {2{~buf_state_en | bypass_en}};
            end
            STREAM_RD: begin
                     master_ready  =  (ahb_hready_q & ~ahb_hresp_q) & ~(master_valid & master_opc[2:1] == 2'b01);
                     buf_wr_en       = (master_valid & master_ready & (master_opc[2:0] == 3'b000)); // update the fifo if we are streaming the read commands
                     buf_nxtstate    = ahb_hresp_q ? STREAM_ERR_RD : (buf_wr_en ? STREAM_RD : DATA_RD);            // assuming that the master accpets the slave response right away.
                     buf_state_en    = (ahb_hready_q | ahb_hresp_q);
                     buf_data_wr_en  = buf_state_en;
                     slvbuf_error_in = ahb_hresp_q;
                     slvbuf_error_en = buf_state_en;

逐段解释：

* 第 L296-L306 行：``CMD_RD`` 在 AHB ready 且上一 transaction 是读时推进；如果有新的读 command，
  转入 ``STREAM_RD`` 并允许 bypass。
* 第 L307-L321 行：``STREAM_RD`` 在 AHB ready 且无 error 时继续接受连续读；遇到 AHB response error
  转入 ``STREAM_ERR_RD``，并把 error 写入 slave buffer。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L322-L338``）：

.. code-block:: systemverilog

            STREAM_ERR_RD: begin
                     buf_nxtstate = DATA_RD;
                     buf_state_en = ahb_hready_q & (ahb_htrans_q[1:0] != 2'b0) & ~ahb_hwrite_q;
                     slave_valid_pre = buf_state_en;
                     slvbuf_wr_en   = buf_state_en;     // Overwrite slvbuf with buffer
                     buf_cmd_byte_ptr[2:0] = buf_addr[2:0];
                     ahb_htrans[1:0] = 2'b10 & {2{~buf_state_en}};
            end
            DATA_RD: begin
                     buf_nxtstate   = DONE;
                     buf_state_en   = (ahb_hready_q | ahb_hresp_q);
                     buf_data_wr_en = buf_state_en;
                     slvbuf_error_in= ahb_hresp_q;
                     slvbuf_error_en= buf_state_en;
                     slvbuf_wr_en   = buf_state_en;

逐段解释：

* 第 L322-L329 行：``STREAM_ERR_RD`` 用当前 buffer 覆盖 slave buffer，并继续输出 AHB trans 直到状态推进。
* 第 L330-L338 行：``DATA_RD`` 在 AHB ready 或 error 时捕获 read data/error，并转向 ``DONE``。

接口关系：

* 被调用：主 FSM 每个组合求值周期执行。
* 调用：``IDLE`` 和读状态调用 ``get_nxtbyte_ptr``。
* 共享状态：``buf_state``、``buf_*``、``slvbuf_*``、``ahb_htrans``、``master_ready``。

§7.5  主 FSM：写命令、写数据与 DONE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 AXI 64-bit write strobe 拆成 AHB-Lite 写 transaction，并在完成或 error 后返回 AXI response。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L339-L380``）：

.. code-block:: systemverilog

            CMD_WR: begin
                     buf_nxtstate = DATA_WR;
                     trxn_done    = ahb_hready_q & ahb_hwrite_q & (ahb_htrans_q[1:0] != 2'b0);
                     buf_state_en = trxn_done;
                     buf_cmd_byte_ptr_en = buf_state_en;
                     slvbuf_wr_en    = buf_state_en;
                     buf_cmd_byte_ptr    = trxn_done ? get_nxtbyte_ptr(buf_cmd_byte_ptrQ[2:0],buf_byteen[7:0],1'b1) : buf_cmd_byte_ptrQ;
                     cmd_done            = trxn_done & (buf_aligned | (buf_cmd_byte_ptrQ == 3'b111) |
                                                        (buf_byteen[get_nxtbyte_ptr(buf_cmd_byte_ptrQ[2:0],buf_byteen[7:0],1'b1)] == 1'b0));
                     ahb_htrans[1:0] = {2{~(cmd_done | cmd_doneQ)}} & 2'b10;
            end
            DATA_WR: begin
                     buf_state_en = (cmd_doneQ & ahb_hready_q) | ahb_hresp_q;
                     master_ready = buf_state_en & ~ahb_hresp_q & slave_ready;   // Ready to accept new command if current command done and no error
                     buf_nxtstate = (ahb_hresp_q | ~slave_ready) ? DONE :
                                     ((master_valid & master_ready) ? ((master_opc[2:1] == 2'b01) ? CMD_WR : CMD_RD) : IDLE);
                     slvbuf_error_in = ahb_hresp_q;

逐段解释：

* 第 L339-L349 行：``CMD_WR`` 等待 AHB write transaction 完成，推进 byte pointer，并根据对齐和 strobe 判断命令是否完成。
* 第 L350-L357 行：``DATA_WR`` 在命令完成或 AHB error 后决定进入 ``DONE``、新写、读命令或 idle。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L358-L380``）：

.. code-block:: systemverilog

                     buf_write_in = (master_opc[2:1] == 2'b01);
                     buf_wr_en = buf_state_en & ((buf_nxtstate == CMD_WR) | (buf_nxtstate == CMD_RD));
                     buf_data_wr_en = buf_wr_en;

                     cmd_done     = (ahb_hresp_q | (ahb_hready_q & (ahb_htrans_q[1:0] != 2'b0) &
                                    ((buf_cmd_byte_ptrQ == 3'b111) | (buf_byteen[get_nxtbyte_ptr(buf_cmd_byte_ptrQ[2:0],buf_byteen[7:0],1'b1)] == 1'b0))));
                     bypass_en       = buf_state_en & buf_write_in & (buf_nxtstate == CMD_WR);   // Only bypass for writes for the time being
                     ahb_htrans[1:0] = {2{(~(cmd_done | cmd_doneQ) | bypass_en)}} & 2'b10;
                     slave_valid_pre  = buf_state_en & (buf_nxtstate != DONE);

                     trxn_done = ahb_hready_q & ahb_hwrite_q & (ahb_htrans_q[1:0] != 2'b0);
                     buf_cmd_byte_ptr_en = trxn_done | bypass_en;
                     buf_cmd_byte_ptr = bypass_en ? get_nxtbyte_ptr(3'b0,buf_byteen_in[7:0],1'b0) :
                                                    trxn_done ? get_nxtbyte_ptr(buf_cmd_byte_ptrQ[2:0],buf_byteen[7:0],1'b1) : buf_cmd_byte_ptrQ;
               end
            DONE: begin
                     buf_nxtstate = IDLE;
                     buf_state_en = slave_ready;
                     slvbuf_error_en = 1'b1;
                     slave_valid_pre = 1'b1;
            end
         endcase

逐段解释：

* 第 L358-L365 行：``DATA_WR`` 根据下一状态决定是否写 buffer，并在未完成或 bypass 时继续输出 AHB trans。
* 第 L366-L371 行：更新 ``slave_valid_pre``、transaction done 和 byte pointer。
* 第 L373-L378 行：``DONE`` 等待 ``slave_ready``，继续输出 response，并在 ready 后回到 idle。
* 第 L379-L380 行：case 结束。

接口关系：

* 被调用：主 FSM 每个组合求值周期执行。
* 调用：多次调用 ``get_nxtbyte_ptr``。
* 共享状态：``buf_cmd_byte_ptrQ``、``buf_byteen``、``cmd_doneQ``、``slave_ready``、``ahb_hresp_q``。

§7.6  AHB-Lite 信号生成与 response 转换
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把内部 buffer 转成 AHB-Lite 输出，并把 AHB error 转换为 AXI response 和 read data。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L382-L410``）：

.. code-block:: systemverilog

      assign buf_rst              = dec_tlu_force_halt_bus[buf_tag[TAG-1]];
      assign cmd_done_rst         = slave_valid_pre;
      assign buf_addr_in[31:3]    = master_addr[31:3];
      assign buf_addr_in[2:0]     = (buf_aligned_in & (master_opc[2:1] == 2'b01)) ? get_write_addr(master_byteen[7:0]) : master_addr[2:0];
      assign buf_tag_in[TAG-1:0]  = master_tag[TAG-1:0];
      assign buf_byteen_in[7:0]   = wrbuf_byteen[7:0];
      assign buf_data_in[63:0]    = (buf_state == DATA_RD) ? ahb_hrdata_q[63:0] : master_wdata[63:0];
      assign buf_size_in[1:0]     = (buf_aligned_in & (master_size[1:0] == 2'b11) & (master_opc[2:1] == 2'b01)) ? get_write_size(master_byteen[7:0]) : master_size[1:0];
      assign buf_aligned_in       = (master_opc[2:0] == 3'b0)    |   // reads are always aligned since they are either DW or sideeffects
                                    (master_size[1:0] == 2'b0) |  (master_size[1:0] == 2'b01) | (master_size[1:0] == 2'b10) | // Always aligned for Byte/HW/Word since they can be only for non-idempotent. IFU/SB are always aligned
                                    ((master_size[1:0] == 2'b11) &
                                     ((master_byteen[7:0] == 8'h3)  | (master_byteen[7:0] == 8'hc)   | (master_byteen[7:0] == 8'h30) | (master_byteen[7:0] == 8'hc0) |
                                      (master_byteen[7:0] == 8'hf)  | (master_byteen[7:0] == 8'hf0)  | (master_byteen[7:0] == 8'hff)));

逐段解释：

* 第 L382-L389 行：buffer 输入从 master command、write buffer 和 AHB read data 中选择。
* 第 L390-L394 行：``buf_aligned_in`` 判断读或 byte/halfword/word 以及若干 doubleword strobe 模式是否对齐。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L396-L410``）：

.. code-block:: systemverilog

      // Generate the ahb signals
      assign ahb_haddr[31:0] = bypass_en ? {master_addr[31:3],buf_cmd_byte_ptr[2:0]}  : {buf_addr[31:3],buf_cmd_byte_ptr[2:0]};
      assign ahb_hsize[2:0]  = {3{ahb_htrans[1]}} & (bypass_en ? {1'b0, ({2{buf_aligned_in}} & buf_size_in[1:0])} :
                                           {1'b0, ({2{buf_aligned}} & buf_size[1:0])});   // Send the full size for aligned trxn
      assign ahb_hburst[2:0] = 3'b0;
      assign ahb_hmastlock   = 1'b0;
      assign ahb_hprot[3:0]  = {3'b001,~axi_arprot[2]};
      assign ahb_hwrite      = bypass_en ? (master_opc[2:1] == 2'b01) : buf_write;
      assign ahb_hwdata[63:0] = buf_data[63:0];

      assign slave_valid          = slave_valid_pre;// & (~slvbuf_posted_write | slvbuf_error);
      assign slave_opc[3:2]       = slvbuf_write ? 2'b11 : 2'b00;
      assign slave_opc[1:0]       = {2{slvbuf_error}} & 2'b10;
      assign slave_rdata[63:0]    = slvbuf_error ? {2{last_bus_addr[31:0]}} : ((buf_state == DONE) ? buf_data[63:0] : ahb_hrdata_q[63:0]);
      assign slave_tag[TAG-1:0]   = slvbuf_tag[TAG-1:0];

逐段解释：

* 第 L396-L404 行：AHB address、size、burst、lock、prot、write 和 write data 从 buffer 或 bypass
  command 生成。
* 第 L406-L410 行：slave response 以 ``slvbuf_write`` 和 ``slvbuf_error`` 编码成 AXI B/R response
  所需的 ``slave_opc``、``slave_rdata`` 和 ``slave_tag``。

接口关系：

* 被调用：组合 assign 持续驱动 AHB-Lite 和 AXI response 中间信号。
* 调用：调用 ``get_write_addr`` 和 ``get_write_size``。
* 共享状态：``buf_*``、``master_*``、``slvbuf_*``、``ahb_*``。

§7.7  flops、clock gating 与 assertion
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 EH2 library flop 保存写 buffer、主 buffer、slave buffer 和 AHB sampled 信号，并在 assertion 开启时检查 AHB 协议。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L415-L446``）：

.. code-block:: systemverilog

      rvdffsc_fpga #(.WIDTH(1))   wrbuf_vldff     (.din(1'b1),              .dout(wrbuf_vld),          .en(wrbuf_en),      .clear(wrbuf_rst), .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffsc_fpga #(.WIDTH(1))   wrbuf_data_vldff(.din(1'b1),              .dout(wrbuf_data_vld),     .en(wrbuf_data_en), .clear(wrbuf_rst), .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga  #(.WIDTH(TAG)) wrbuf_tagff     (.din(axi_awid[TAG-1:0]), .dout(wrbuf_tag[TAG-1:0]), .en(wrbuf_en),                         .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga  #(.WIDTH(3))   wrbuf_sizeff    (.din(axi_awsize[2:0]),   .dout(wrbuf_size[2:0]),    .en(wrbuf_en),                         .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffe       #(.WIDTH(32))  wrbuf_addrff    (.din(axi_awaddr[31:0]),  .dout(wrbuf_addr[31:0]),   .en(wrbuf_en & bus_clk_en),            .clk(clk), .*);
      rvdffe       #(.WIDTH(64))  wrbuf_dataff    (.din(axi_wdata[63:0]),   .dout(wrbuf_data[63:0]),   .en(wrbuf_data_en & bus_clk_en),       .clk(clk), .*);
      rvdffs_fpga  #(.WIDTH(8))   wrbuf_byteenff  (.din(axi_wstrb[7:0]),    .dout(wrbuf_byteen[7:0]),  .en(wrbuf_data_en),                    .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);

      rvdffs_fpga #(.WIDTH(32))   last_bus_addrff (.din(ahb_haddr[31:0]),   .dout(last_bus_addr[31:0]), .en(last_addr_en), .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);

逐段解释：

* 第 L415-L421 行：写 buffer 保存 AW ID、size、addr 以及 W data/strobe，并用 ``wrbuf_rst`` 清 valid。
* 第 L423 行：``last_bus_addr`` 保存最后一次 AHB write 地址，用于 error response data。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L448-L461``）：

.. code-block:: systemverilog

      // Clock headers
      // clock enables for ahbm addr/data
      assign buf_clken       = bus_clk_en & (buf_wr_en | slvbuf_wr_en | clk_override);
      assign ahbm_data_clken = bus_clk_en & ((buf_state != IDLE) | clk_override);

   `ifdef RV_FPGA_OPTIMIZE
      assign bus_clk = 1'b0;
      assign buf_clk = 1'b0;
      assign ahbm_data_clk = 1'b0;
   `else
      rvclkhdr bus_cgc       (.en(bus_clk_en),      .l1clk(bus_clk),       .*);
      rvclkhdr buf_cgc       (.en(buf_clken),       .l1clk(buf_clk), .*);
      rvclkhdr ahbm_data_cgc (.en(ahbm_data_clken), .l1clk(ahbm_data_clk), .*);
   `endif

逐段解释：

* 第 L448-L451 行：``buf_clken`` 和 ``ahbm_data_clken`` 由 bus enable、状态和 override 组成。
* 第 L453-L461 行：FPGA optimize 分支把 gated clock 置 0；普通分支实例化三个 ``rvclkhdr``。

关键代码（``rtl/design/lib/axi4_to_ahb.sv:L463-L478``）：

.. code-block:: systemverilog

   `ifdef RV_ASSERT_ON
      property ahb_trxn_aligned;
        @(posedge ahbm_clk) ahb_htrans[1]  |-> ((ahb_hsize[2:0] == 3'h0)                              |
                                           ((ahb_hsize[2:0] == 3'h1) & (ahb_haddr[0] == 1'b0))   |
                                           ((ahb_hsize[2:0] == 3'h2) & (ahb_haddr[1:0] == 2'b0)) |
                                           ((ahb_hsize[2:0] == 3'h3) & (ahb_haddr[2:0] == 3'b0)));
      endproperty
      assert_ahb_trxn_aligned: assert property (ahb_trxn_aligned) else
        $display("Assertion ahb_trxn_aligned failed: ahb_htrans=2'h%h, ahb_hsize=3'h%h, ahb_haddr=32'h%h",ahb_htrans[1:0], ahb_hsize[2:0], ahb_haddr[31:0]);

      property ahb_error_protocol;
         @(posedge ahbm_clk) (ahb_hready & ahb_hresp) |-> (~$past(ahb_hready) & $past(ahb_hresp));
      endproperty

逐段解释：

* 第 L463-L471 行：``ahb_trxn_aligned`` 检查 AHB transfer 的 size 与低地址位对齐。
* 第 L473-L478 行：``ahb_error_protocol`` 检查 ``hready`` 与 ``hresp`` 的错误响应时序。

接口关系：

* 被调用：flop 和 clock header 实例在硬件 elaboration 中存在；assertion 在 ``RV_ASSERT_ON`` 下启用。
* 调用：实例化 ``rvdffsc_fpga``、``rvdffs_fpga``、``rvdffe``、``rvclkhdr``。
* 共享状态：buffer 寄存器、clock enable、AHB sampled 信号。

§8  ``ahb_to_axi4.sv`` — AHB-Lite slave 到 AXI4 master
------------------------------------------------------

``ahb_to_axi4`` 接收 AHB-Lite 侧访问，生成 single-beat AXI4 read/write command。源码中该桥还做
DCCM、ICCM、PIC 范围检查和访问大小/对齐错误判断，用 ``ahb_hresp`` 向 AHB 侧返回错误。

§8.1  模块参数与端口方向
~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 ``TAG`` 和 ``eh2_param.vh`` 参数，并暴露 AXI master 输出与 AHB-Lite slave 输入输出。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L23-L52``）：

.. code-block:: systemverilog

   module ahb_to_axi4
   import eh2_pkg::*;
   #(
      TAG = 1,
      `include "eh2_param.vh"
   )
   //   ,TAG  = 1)
   (
      input                   clk,
      input                   rst_l,
      input                   scan_mode,
      input                   bus_clk_en,
      input                   clk_override,

      // AXI signals
      // AXI Write Channels
      output logic            axi_awvalid,
      input  logic            axi_awready,
      output logic [TAG-1:0]  axi_awid,
      output logic [31:0]     axi_awaddr,
      output logic [2:0]      axi_awsize,
      output logic [2:0]      axi_awprot,
      output logic [7:0]      axi_awlen,
      output logic [1:0]      axi_awburst,

      output logic            axi_wvalid,
      input  logic            axi_wready,
      output logic [63:0]     axi_wdata,
      output logic [7:0]      axi_wstrb,
      output logic            axi_wlast,

逐段解释：

* 第 L23-L28 行：模块导入 ``eh2_pkg::*``，参数包含 ``TAG`` 和 ``eh2_param.vh`` 展开的 ``pt``。
* 第 L31-L35 行：clock/reset、scan、bus clock enable 和 clock override 输入。
* 第 L39-L52 行：AXI write address 和 write data 由该桥输出，ready 由外部 AXI slave 返回。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L54-L90``）：

.. code-block:: systemverilog

      input  logic            axi_bvalid,
      output logic            axi_bready,
      input  logic [1:0]      axi_bresp,
      input  logic [TAG-1:0]  axi_bid,

      // AXI Read Channels
      output logic            axi_arvalid,
      input  logic            axi_arready,
      output logic [TAG-1:0]  axi_arid,
      output logic [31:0]     axi_araddr,
      output logic [2:0]      axi_arsize,
      output logic [2:0]      axi_arprot,
      output logic [7:0]      axi_arlen,
      output logic [1:0]      axi_arburst,

      input  logic            axi_rvalid,
      output logic            axi_rready,
      input  logic [TAG-1:0]  axi_rid,
      input  logic [63:0]     axi_rdata,
      input  logic [1:0]      axi_rresp,

      // AHB-Lite signals
      input logic [31:0]      ahb_haddr,     // ahb bus address
      input logic [2:0]       ahb_hburst,    // tied to 0
      input logic             ahb_hmastlock, // tied to 0
      input logic [3:0]       ahb_hprot,     // tied to 4'b0011
      input logic [2:0]       ahb_hsize,     // size of bus transaction (possible values 0,1,2,3)

逐段解释：

* 第 L54-L57 行：AXI B response 由外部返回，该桥把 ``axi_bready`` 固定为 ready。
* 第 L60-L73 行：AXI read address 由该桥输出，R response 由外部返回。
* 第 L75-L90 行：AHB-Lite side 是 slave 方向：地址、控制和写数据为输入，read data、readyout、
  response 为输出。

接口关系：

* 被调用：``eh2_veer`` 的 ``dma_ahb_to_axi4`` 实例调用该模块。
* 调用：模块内部实例化 range check 和 EH2 library flops。
* 共享状态：AHB-Lite side、AXI side、``pt`` 参数。

§8.2  状态机与 command buffer 装载
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 ``IDLE``、``WR``、``RD``、``PEND`` 四状态控制 AHB blocking 访问和 AXI command buffer。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L93-L164``）：

.. code-block:: systemverilog

      logic [7:0]       master_wstrb;

    typedef enum logic [1:0] {   IDLE   = 2'b00,    // Nothing in the buffer. No commands yet recieved
                                 WR     = 2'b01,    // Write Command recieved
                                 RD     = 2'b10,    // Read Command recieved
                                 PEND   = 2'b11     // Waiting on Read Data from core
                               } state_t;
      state_t      buf_state, buf_nxtstate;
      logic        buf_state_en;

      // Buffer signals (one entry buffer)
      logic                    buf_read_error_in, buf_read_error;
      logic [63:0]             buf_rdata;

      logic                    ahb_hready;
      logic                    ahb_hready_q;

逐段解释：

* 第 L93 行：``master_wstrb`` 是从 AHB size/address 转换出的 AXI write strobe。
* 第 L95-L100 行：FSM 有 idle、write、read、pending read data 四个状态。
* 第 L103-L114 行：buffer 保存 read data、read error 和采样后的 AHB 控制信号。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L135-L164``）：

.. code-block:: systemverilog

   // FSM to control the bus states and when to block the hready and load the command buffer
      always_comb begin
         buf_nxtstate      = IDLE;
         buf_state_en      = 1'b0;
         buf_rdata_en      = 1'b0;              // signal to load the buffer when the core sends read data back
         buf_read_error_in = 1'b0;              // signal indicating that an error came back with the read from the core
         cmdbuf_wr_en      = 1'b0;              // all clear from the gasket to load the buffer with the command for reads, command/dat for writes
         case (buf_state)
            IDLE: begin  // No commands recieved
                     buf_nxtstate      = ahb_hwrite ? WR : RD;
                     buf_state_en      = ahb_hready & ahb_htrans[1] & ahb_hsel;                 // only transition on a valid hrtans
             end
            WR: begin // Write command recieved last cycle
                     buf_nxtstate      = (ahb_hresp | (ahb_htrans[1:0] == 2'b0) | ~ahb_hsel) ? IDLE : ahb_hwrite  ? WR : RD;
                     buf_state_en      = (~cmdbuf_full | ahb_hresp) ;
                     cmdbuf_wr_en      = ~cmdbuf_full & ~(ahb_hresp | ((ahb_htrans[1:0] == 2'b01) & ahb_hsel));   // Dont send command to the buffer in case of an error or when the master is not ready with the data now.

逐段解释：

* 第 L135-L141 行：组合 FSM 默认回到 idle，并清 read data enable、read error 和 command buffer write enable。
* 第 L143-L146 行：``IDLE`` 在 ``ahb_hready & ahb_htrans[1] & ahb_hsel`` 时接受有效 AHB transfer，
  根据 ``ahb_hwrite`` 进入 ``WR`` 或 ``RD``。
* 第 L147-L150 行：``WR`` 在 command buffer 未满且无错误时写 command buffer；遇到 error、
  idle transfer 或未选中时回 idle。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L152-L164``）：

.. code-block:: systemverilog

            RD: begin // Read command recieved last cycle.
                    buf_nxtstate      = ahb_hresp ? IDLE :PEND;                                       // If error go to idle, else wait for read data
                    buf_state_en      = (~cmdbuf_full | ahb_hresp);                                   // only when command can go, or if its an error
                    cmdbuf_wr_en      = ~ahb_hresp & ~cmdbuf_full;                                    // send command only when no error
            end
            PEND: begin // Read Command has been sent. Waiting on Data.
                    buf_nxtstate      = IDLE;                                                          // go back for next command and present data next cycle
                    buf_state_en      = axi_rvalid & ~cmdbuf_write;                                    // read data is back
                    buf_rdata_en      = buf_state_en;                                                  // buffer the read data coming back from core
                    buf_read_error_in = buf_state_en & |axi_rresp[1:0];                                // buffer error flag if return has Error ( ECC )
            end
        endcase
      end // always_comb begin

逐段解释：

* 第 L152-L156 行：``RD`` 无 AHB error 且 command buffer 未满时发送读 command，然后进入 ``PEND``。
* 第 L157-L162 行：``PEND`` 等待 ``axi_rvalid``，捕获 read data，并把非零 ``axi_rresp`` 转成
  ``buf_read_error``。
* 第 L163-L164 行：case 和组合块结束。

接口关系：

* 被调用：组合 FSM 持续根据 AHB/AXI handshake 计算下一状态。
* 调用：不调用函数。
* 共享状态：``buf_state``、``cmdbuf_*``、``axi_rvalid``、``axi_rresp``、``ahb_hresp``。

§8.3  write strobe、AHB ready/resp 与错误条件
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 AHB size/address 生成 AXI strobe，并根据范围、大小、对齐和 read error 生成 AHB response。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L168-L188``）：

.. code-block:: systemverilog

      assign master_wstrb[7:0]   = ({8{ahb_hsize_q[2:0] == 3'b0}}  & (8'b1    << ahb_haddr_q[2:0])) |
                                   ({8{ahb_hsize_q[2:0] == 3'b1}}  & (8'b11   << ahb_haddr_q[2:0])) |
                                   ({8{ahb_hsize_q[2:0] == 3'b10}} & (8'b1111 << ahb_haddr_q[2:0])) |
                                   ({8{ahb_hsize_q[2:0] == 3'b11}} & 8'b1111_1111);

      // AHB signals
      assign ahb_hreadyout       = ahb_hresp ? (ahb_hresp_q & ~ahb_hready_q) :
                                            ((~cmdbuf_full | (buf_state == IDLE)) & ~(buf_state == RD | buf_state == PEND)  & ~buf_read_error);

      assign ahb_hready          = ahb_hreadyout & ahb_hreadyin;
      assign ahb_htrans_in[1:0]  = {2{ahb_hsel}} & ahb_htrans[1:0];
      assign ahb_hrdata[63:0]    = buf_rdata[63:0];
      assign ahb_hresp        = ((ahb_htrans_q[1:0] != 2'b0) & (buf_state != IDLE)  &

逐段解释：

* 第 L168-L171 行：``master_wstrb`` 按 AHB size 和地址低 3 位生成 byte/halfword/word/doubleword strobe。
* 第 L173-L178 行：``ahb_hreadyout`` 在 command buffer 可接受、非 RD/PEND 且无 read error 时拉高；
  ``ahb_hready`` 还需要 ``ahb_hreadyin``。
* 第 L179-L180 行：read data 直接来自 ``buf_rdata``，``ahb_hresp`` 组合表达式从第 L180 行开始。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L180-L188``）：

.. code-block:: systemverilog

      assign ahb_hresp        = ((ahb_htrans_q[1:0] != 2'b0) & (buf_state != IDLE)  &

                                ((~(ahb_addr_in_dccm | ahb_addr_in_iccm)) |                                                                                   // request not for ICCM or DCCM
                                ((ahb_addr_in_iccm | (ahb_addr_in_dccm &  ahb_hwrite_q)) & ~((ahb_hsize_q[1:0] == 2'b10) | (ahb_hsize_q[1:0] == 2'b11))) |    // ICCM Rd/Wr OR DCCM Wr not the right size
                                ((ahb_hsize_q[2:0] == 3'h1) & ahb_haddr_q[0])   |                                                                             // HW size but unaligned
                                ((ahb_hsize_q[2:0] == 3'h2) & (|ahb_haddr_q[1:0])) |                                                                          // W size but unaligned
                                ((ahb_hsize_q[2:0] == 3'h3) & (|ahb_haddr_q[2:0])))) |                                                                        // DW size but unaligned
                                buf_read_error |                                                                                                              // Read ECC error
                                (ahb_hresp_q & ~ahb_hready_q);

逐段解释：

* 第 L180-L183 行：有效 AHB transfer 且状态非 idle 时，如果地址不在 DCCM 或 ICCM 范围内，则生成 error。
  该 expression 没有把 PIC range 纳入允许条件。
* 第 L183-L186 行：ICCM 读写或 DCCM 写要求 size 为 word 或 doubleword；halfword/word/doubleword
  访问还分别检查低地址位对齐。
* 第 L187-L188 行：AXI read response 中的 error 和上一拍未完成的 AHB error 也会拉高 ``ahb_hresp``。

接口关系：

* 被调用：组合 assign 持续驱动 AHB response。
* 调用：不调用函数。
* 共享状态：``ahb_addr_in_dccm``、``ahb_addr_in_iccm``、``buf_read_error``、``cmdbuf_full``。

§8.4  DCCM、ICCM、PIC range check
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：实例化 DCCM、ICCM 和 PIC 范围检查逻辑；当前 error expression 只使用 DCCM/ICCM in-range 信号。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L202-L234``）：

.. code-block:: systemverilog

      // Address check  dccm
      if (pt.DCCM_ENABLE == 1) begin: GenDCCM
         rvrangecheck #(.CCM_SADR(pt.DCCM_SADR),
                        .CCM_SIZE(pt.DCCM_SIZE)) addr_dccm_rangecheck (
            .addr(ahb_haddr_q[31:0]),
            .in_range(ahb_addr_in_dccm),
            .in_region(ahb_addr_in_dccm_region_nc)
         );
      end else begin: GenNoDCCM
         assign ahb_addr_in_dccm = '0;
         assign ahb_addr_in_dccm_region_nc = '0;
      end

      // Address check  iccm
      if (pt.ICCM_ENABLE == 1) begin: GenICCM
         rvrangecheck #(.CCM_SADR(pt.ICCM_SADR),
                        .CCM_SIZE(pt.ICCM_SIZE)) addr_iccm_rangecheck (
            .addr(ahb_haddr_q[31:0]),
            .in_range(ahb_addr_in_iccm),

逐段解释：

* 第 L202-L213 行：DCCM range check 只在 ``pt.DCCM_ENABLE == 1`` 时实例化，否则将 in-range 和 in-region
  信号置 0。
* 第 L215-L221 行：ICCM range check 使用 ``pt.ICCM_SADR`` 和 ``pt.ICCM_SIZE``。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L216-L234``）：

.. code-block:: systemverilog

      if (pt.ICCM_ENABLE == 1) begin: GenICCM
         rvrangecheck #(.CCM_SADR(pt.ICCM_SADR),
                        .CCM_SIZE(pt.ICCM_SIZE)) addr_iccm_rangecheck (
            .addr(ahb_haddr_q[31:0]),
            .in_range(ahb_addr_in_iccm),
            .in_region(ahb_addr_in_iccm_region_nc)
         );
      end else begin: GenNoICCM
         assign ahb_addr_in_iccm = '0;
         assign ahb_addr_in_iccm_region_nc = '0;
      end

      // PIC memory address check
      rvrangecheck #(.CCM_SADR(pt.PIC_BASE_ADDR),
                     .CCM_SIZE(pt.PIC_SIZE)) addr_pic_rangecheck (
         .addr(ahb_haddr_q[31:0]),
         .in_range(ahb_addr_in_pic),
         .in_region(ahb_addr_in_pic_region_nc)
      );

逐段解释：

* 第 L216-L226 行：ICCM disabled 时同样把 in-range 和 in-region 置 0。
* 第 L228-L234 行：PIC range check 始终实例化，输出 ``ahb_addr_in_pic`` 和
  ``ahb_addr_in_pic_region_nc``。当前 ``ahb_hresp`` 组合表达式未使用 ``ahb_addr_in_pic``。

接口关系：

* 被调用：``ahb_to_axi4`` 内部 generate 和实例化调用 ``rvrangecheck``。
* 调用：实例化 ``rvrangecheck``。
* 共享状态：``pt.DCCM_*``、``pt.ICCM_*``、``pt.PIC_*`` 和 ``ahb_haddr_q``。

§8.5  command buffer 与 AXI channel 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 AHB command 缓存在一项 command buffer 中，并生成 single-beat AXI AW/W 或 AR。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L236-L245``）：

.. code-block:: systemverilog

      // Command Buffer - Holding for the commands to be sent for the AXI. It will be converted to the AXI signals.
      assign cmdbuf_rst         = (((axi_awvalid & axi_awready) | (axi_arvalid & axi_arready)) & ~cmdbuf_wr_en) | (ahb_hresp & ~cmdbuf_write);
      assign cmdbuf_full        = (cmdbuf_vld & ~((axi_awvalid & axi_awready) | (axi_arvalid & axi_arready)));

      rvdffsc_fpga #(.WIDTH(1))  cmdbuf_vldff      (.din(1'b1),              .dout(cmdbuf_vld),         .en(cmdbuf_wr_en), .clear(cmdbuf_rst), .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga  #(.WIDTH(1))  cmdbuf_writeff    (.din(ahb_hwrite_q),      .dout(cmdbuf_write),       .en(cmdbuf_wr_en),                     .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga  #(.WIDTH(2))  cmdbuf_sizeff     (.din(ahb_hsize_q[1:0]),  .dout(cmdbuf_size[1:0]),   .en(cmdbuf_wr_en),                     .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffs_fpga  #(.WIDTH(8))  cmdbuf_wstrbff    (.din(master_wstrb[7:0]), .dout(cmdbuf_wstrb[7:0]),  .en(cmdbuf_wr_en),                     .clk(bus_clk), .clken(bus_clk_en), .rawclk(clk), .*);
      rvdffe       #(.WIDTH(32)) cmdbuf_addrff     (.din(ahb_haddr_q[31:0]), .dout(cmdbuf_addr[31:0]),  .en(cmdbuf_wr_en & bus_clk_en),        .clk(clk), .*);
      rvdffe       #(.WIDTH(64)) cmdbuf_wdataff    (.din(ahb_hwdata[63:0]),  .dout(cmdbuf_wdata[63:0]), .en(cmdbuf_wr_en & bus_clk_en),        .clk(clk), .*);

逐段解释：

* 第 L236-L238 行：command buffer 在 AXI AW/AR handshake 后清空；如果 AHB response error 且不是 write command，
  也会清 buffer。``cmdbuf_full`` 表示 valid 但尚未被 AXI 接收。
* 第 L240-L245 行：buffer 保存 valid、write、size、wstrb、addr 和 write data。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L247-L271``）：

.. code-block:: systemverilog

      // AXI Write Command Channel
      assign axi_awvalid           = cmdbuf_vld & cmdbuf_write;
      assign axi_awid[TAG-1:0]     = '0;
      assign axi_awaddr[31:0]      = cmdbuf_addr[31:0];
      assign axi_awsize[2:0]       = {1'b0, cmdbuf_size[1:0]};
      assign axi_awprot[2:0]       = 3'b0;
      assign axi_awlen[7:0]        = '0;
      assign axi_awburst[1:0]      = 2'b01;
      // AXI Write Data Channel - This is tied to the command channel as we only write the command buffer once we have the data.
      assign axi_wvalid            = cmdbuf_vld & cmdbuf_write;
      assign axi_wdata[63:0]       = cmdbuf_wdata[63:0];
      assign axi_wstrb[7:0]        = cmdbuf_wstrb[7:0];
      assign axi_wlast             = 1'b1;
     // AXI Write Response - Always ready. AHB does not require a write response.
      assign axi_bready            = 1'b1;
      // AXI Read Channels
      assign axi_arvalid           = cmdbuf_vld & ~cmdbuf_write;
      assign axi_arid[TAG-1:0]     = '0;
      assign axi_araddr[31:0]      = cmdbuf_addr[31:0];
      assign axi_arsize[2:0]       = {1'b0, cmdbuf_size[1:0]};

逐段解释：

* 第 L247-L254 行：AXI AW 使用 command buffer 地址和 size；``axi_awlen`` 固定 0，
  ``axi_awburst`` 固定 ``2'b01``。
* 第 L255-L261 行：AXI W 与 AW 同时 valid，``axi_wlast`` 固定 1，``axi_bready`` 固定 1。
* 第 L262-L271 行：AXI AR 使用 command buffer 地址和 size；R channel ready 固定 1。

接口关系：

* 被调用：组合 assign 驱动 AXI channel。
* 调用：实例化 EH2 flop primitive。
* 共享状态：``cmdbuf_*``、``axi_*``、``ahb_*``。

§8.6  clock header 与 AHB error assertion
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 bus、AHB address 和 read-data buffer 生成 gated clock，并在 assertion 开启时检查 AHB error protocol。

关键代码（``rtl/design/lib/ahb_to_axi4.sv:L273-L294``）：

.. code-block:: systemverilog

      // Clock header logic
      assign ahb_addr_clk_en = bus_clk_en & (ahb_hready & ahb_htrans[1]);
      assign buf_rdata_clk_en    = bus_clk_en & buf_rdata_en;

   `ifdef RV_FPGA_OPTIMIZE
      assign bus_clk = 1'b0;
      assign ahb_addr_clk = 1'b0;
      assign buf_rdata_clk = 1'b0;
   `else
      rvclkhdr bus_cgc       (.en(bus_clk_en),       .l1clk(bus_clk),       .*);
      rvclkhdr ahb_addr_cgc  (.en(ahb_addr_clk_en),  .l1clk(ahb_addr_clk),  .*);
      rvclkhdr buf_rdata_cgc (.en(buf_rdata_clk_en), .l1clk(buf_rdata_clk), .*);
   `endif

   `ifdef RV_ASSERT_ON
      property ahb_error_protocol;
         @(posedge bus_clk) (ahb_hready & ahb_hresp) |-> (~$past(ahb_hready) & $past(ahb_hresp));
      endproperty
      assert_ahb_error_protocol: assert property (ahb_error_protocol) else
         $display("Bus Error with hReady isn't preceded with Bus Error without hready");

   `endif

逐段解释：

* 第 L273-L275 行：AHB address clock enable 在有效 AHB transfer 时打开，read-data buffer clock enable
  在 ``buf_rdata_en`` 时打开。
* 第 L277-L285 行：FPGA optimize 分支将 gated clocks 置 0；普通分支实例化三组 ``rvclkhdr``。
* 第 L287-L294 行：``RV_ASSERT_ON`` 下检查 AHB error response 时序：``hready & hresp`` 需要由上一拍
  ``!hready & hresp`` 先导。

接口关系：

* 被调用：clock header 和 assertion 在模块 elaboration 中存在。
* 调用：实例化 ``rvclkhdr``，assertion 失败调用 ``$display``。
* 共享状态：``bus_clk_en``、``ahb_hready``、``ahb_htrans``、``buf_rdata_en``、``ahb_hresp``。

§9  参考资料
------------

* 关联 ADR：:ref:`adr-0002`。
* 关联章节：:ref:`agent_axi4`、:ref:`appendix_b_uvm/axi4_agent`、:ref:`appendix_b_uvm/tb`、
  :ref:`appendix_a_rtl_dma`、:ref:`appendix_a_rtl_mem`。
* 源文件：:file:`/home/host/eh2-veri/shared/rtl/axi4_pkg.sv`。
* 源文件：:file:`/home/host/eh2-veri/shared/rtl/axi4_intf.sv`。
* 源文件：:file:`/home/host/eh2-veri/shared/rtl/axi4_slave_mem.sv`。
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_shared.f`。
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`。
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`。
* 源文件：:file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`。
* 源文件：:file:`/home/host/eh2-veri/rtl/design/lib/axi4_to_ahb.sv`。
* 源文件：:file:`/home/host/eh2-veri/rtl/design/lib/ahb_to_axi4.sv`。
* 源文件：:file:`/home/host/eh2-veri/docs/adr/0002-axi4-passive-monitoring.md`。

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
