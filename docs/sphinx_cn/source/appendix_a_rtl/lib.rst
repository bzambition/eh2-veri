.. _appendix_a_rtl_lib:
.. _appendix_a_rtl/lib:

RTL 公共库（LIB）- 详细参考
===========================

:status: draft
:source: rtl/design/lib/
:last-reviewed: 2026-05-19

§1  源码边界
------------

`rtl/design/lib/` 是 EH2 RTL 的公共库目录。它不是一个单独硬件模块，而是一组被 IFU、
DEC、EXU、LSU、顶层 wrapper 和 AXI/AHB 转换路径复用的基础单元。UVM RTL filelist
在库文件区明确列出 5 个相关文件，其中前三个用 `-v` 以 library mode 编译。

关键代码（`dv/uvm/core_eh2/eh2_rtl.f:L11-L18`）：

.. code-block:: systemverilog

   // Library files (compiled with -v = library mode, only when needed)
   -v rtl/design/lib/beh_lib.sv
   -v rtl/design/lib/eh2_lib.sv
   -v rtl/design/lib/mem_lib.sv

   // AXI/AHB converters
   rtl/design/lib/ahb_to_axi4.sv
   rtl/design/lib/axi4_to_ahb.sv

逐段解释：

* 第 L11-L14 行：`beh_lib.sv`、`eh2_lib.sv`、`mem_lib.sv` 以 `-v` 方式进入 filelist。
  这些文件提供寄存器、clock header、仲裁器、BTB hash、RAM 行为模型等可按需解析的库单元。
* 第 L16-L18 行：`ahb_to_axi4.sv` 与 `axi4_to_ahb.sv` 作为普通 RTL 文件编译。
  它们是协议转换器，不只是被按需展开的基础 primitive。

接口关系：

* 被调用：filelist 被仿真和编译脚本读取。
* 调用：本段只定义编译文件集合，不调用模块。
* 共享状态：无运行期共享状态；库单元的共享性来自多个 RTL 文件实例化同名模块。

§1.1  库目录文件分工
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：本节给出 5 个实际源文件的源码分工，避免把不存在的 `rtl/lib/` 或其它目录写入
文档。

关键代码（`rtl/design/lib/beh_lib.sv:L16-L19`，`rtl/design/lib/eh2_lib.sv:L1-L5`，
`rtl/design/lib/mem_lib.sv:L92-L97`）：

.. code-block:: systemverilog

   // all flops call the rvdff flop


   module rvdff #( parameter WIDTH=1 )

.. code-block:: systemverilog

   module eh2_btb_tag_hash #(
   `include "eh2_param.vh"
    ) (
                          input logic [pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE:pt.BTB_ADDR_HI+1] pc,
                          output logic [pt.BTB_BTAG_SIZE-1:0] hash

.. code-block:: systemverilog

   // parameterizable RAM for verilator sims
   module eh2_ram #(depth=2, width=1) (
   input logic [$clog2(depth)-1:0] ADR,
   input logic [(width-1):0] D,
   output logic [(width-1):0] Q,
    `EH2_LOCAL_RAM_TEST_IO

逐段解释：

* `beh_lib.sv:L16-L19`：文件首先说明所有 flop wrapper 都落到 `rvdff`，后续寄存器、
  enable flop、分段 flop、同步器、仲裁器、加法器、ECC、clock header 都在该文件中。
* `eh2_lib.sv:L1-L5`：EH2 专用库从 BTB tag hash 开始，依赖 `eh2_param.vh` 中的
  `pt.BTB_*` 参数。
* `mem_lib.sv:L92-L97`：内存库除了宏生成定深定宽 RAM，也有参数化 `eh2_ram`，用于
  Verilator 仿真。

接口关系：

* 被调用：各 RTL 模块通过实例化 `rvdff*`、`rvrangecheck`、`rvecc_*`、`eh2_ram`
  等库单元使用这些文件。
* 调用：库文件内部还存在层次化调用，例如 `rvdffe` 调用 `rvclkhdr` 和 `rvdff`。
* 共享状态：库单元各实例独立保存状态；没有跨实例全局寄存器。

§2  `beh_lib.sv` 寄存器基础层
-----------------------------

`beh_lib.sv` 是公共行为库中最大的文件。它将不同风格的 DFF、clock gating、仲裁、
地址计算、匹配、ECC 等组合或时序功能集中在一个文件中。

§2.1  `rvdff` - 基础 DFF
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvdff` 是基础正沿触发寄存器，带低有效异步复位。`beh_lib.sv` 注释说明所有
flop wrapper 都调用它。

关键代码（`rtl/design/lib/beh_lib.sv:L19-L42`）：

.. code-block:: systemverilog

   module rvdff #( parameter WIDTH=1 )
      (
        input logic [WIDTH-1:0] din,
        input logic           clk,
        input logic                   rst_l,

        output logic [WIDTH-1:0] dout
        );

   `ifdef RV_CLOCKGATE
      always @(posedge tb_top.clk) begin
         #0 $strobe("CG: %0t %m din %x dout %x clk %b width %d",$time,din,dout,clk,WIDTH);
      end
   `endif

      always_ff @(posedge clk or negedge rst_l) begin
         if (rst_l == 0)
           dout[WIDTH-1:0] <= 0;
         else
           dout[WIDTH-1:0] <= din[WIDTH-1:0];
      end


   endmodule

逐段解释：

* 第 L19-L26 行：模块参数 `WIDTH` 决定 `din`/`dout` 宽度。端口只有 `din`、`clk`、
  `rst_l` 和 `dout`。
* 第 L28-L32 行：若定义 `RV_CLOCKGATE`，每个 `tb_top.clk` 正沿打印当前实例名、
  输入输出、clock 和 width。该段是调试条件编译代码。
* 第 L34-L39 行：`always_ff` 对 `clk` 正沿和 `rst_l` 负沿敏感。复位为 0 时输出全 0，
  否则输出采样 `din`。

接口关系：

* 被调用：`rvdffs`、`rvdffsc`、`rvdffe`、同步器和大量 RTL 模块直接或间接调用它。
* 调用：无下层模块。
* 共享状态：每个实例只保存自己的 `dout`。

§2.2  `rvdffs` 与 `rvdffsc` - enable 和 clear wrapper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvdffs` 在输入侧用 `en` 选择新值或保持旧值；`rvdffsc` 在 `clear` 为 1 时把
输入清零，再通过 `rvdff` 保存。

关键代码（`rtl/design/lib/beh_lib.sv:L44-L73`）：

.. code-block:: systemverilog

   // rvdff with 2:1 input mux to flop din iff sel==1
   module rvdffs #( parameter WIDTH=1 )
      (
        input logic [WIDTH-1:0] din,
        input logic             en,
        input logic           clk,
        input logic                   rst_l,
        output logic [WIDTH-1:0] dout
        );

      rvdff #(WIDTH) dffs (.din((en) ? din[WIDTH-1:0] : dout[WIDTH-1:0]), .*);

   endmodule

   // rvdff with en and clear
   module rvdffsc #( parameter WIDTH=1 )
      (

逐段解释：

* 第 L45-L55 行：`rvdffs` 不生成 clock gate；它把 `en ? din : dout` 作为 `rvdff`
  的输入，从数据路径上实现保持。
* 第 L59-L67 行：`rvdffsc` 增加 `clear` 端口。
* 第 L69-L71 行：`din_new` 先用 `{WIDTH{~clear}}` 屏蔽；若 `clear` 为 1，写入 0；
  否则按 `en` 选择 `din` 或 `dout`。

接口关系：

* 被调用：`rvdff_fpga`、`rvdffs_fpga`、`rvdffsc_fpga` 和 RTL 中需要 enable/clear 的寄存器调用。
* 调用：两者都调用 `rvdff`。
* 共享状态：本地 `dout` 由被包装的 `rvdff` 保存。

§2.3  FPGA wrapper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvdff_fpga`、`rvdffs_fpga`、`rvdffsc_fpga` 根据 `RV_FPGA_OPTIMIZE` 选择 raw clock
加 `clken` 的实现，或退回普通 wrapper。

关键代码（`rtl/design/lib/beh_lib.sv:L75-L138`）：

.. code-block:: systemverilog

   // _fpga versions
   module rvdff_fpga #( parameter WIDTH=1 )
      (
        input logic [WIDTH-1:0] din,
        input logic           clk,
        input logic           clken,
        input logic           rawclk,
        input logic           rst_l,

        output logic [WIDTH-1:0] dout
        );

   `ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dffs (.clk(rawclk), .en(clken), .*);
   `else
      rvdff #(WIDTH)  dff (.*);
   `endif

逐段解释：

* 第 L76-L91 行：`rvdff_fpga` 在 `RV_FPGA_OPTIMIZE` 下用 `rawclk` 和 `clken`
  调用 `rvdffs`，否则直接调用 `rvdff`。
* 第 L96-L112 行：`rvdffs_fpga` 在 FPGA 优化下把 enable 合成为 `clken & en`，
  否则调用普通 `rvdffs`。
* 第 L117-L136 行：`rvdffsc_fpga` 在 FPGA 优化下使用 `rvdffs`，输入为
  `din & ~clear`，enable 为 `(en | clear) & clken`；否则调用 `rvdffsc`。

接口关系：

* 被调用：AXI/AHB 桥和部分总线侧寄存器大量使用 `_fpga` wrapper。
* 调用：根据条件编译调用 `rvdff`、`rvdffs` 或 `rvdffsc`。
* 共享状态：无跨实例共享状态；`rawclk` 和 `clken` 是调用方提供的时钟控制。

§2.4  `rvdffe` - clock-gated enable flop
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvdffe` 对宽寄存器使用 clock header 生成 `l1clk`，再用 `rvdff` 采样输入。
在 FPGA 优化路径下退化为 `rvdffs`。

关键代码（`rtl/design/lib/beh_lib.sv:L241-L270`）：

.. code-block:: systemverilog

   module rvdffe #( parameter WIDTH=1, OVERRIDE=0 )
      (
        input  logic [WIDTH-1:0] din,
        input  logic           en,
        input  logic           clk,
        input  logic           rst_l,
        input  logic             scan_mode,
        output logic [WIDTH-1:0] dout
        );

      logic                      l1clk;

   `ifndef RV_PHYSICAL
      if (WIDTH >= 8 || OVERRIDE==1) begin: genblock
   `endif

   `ifdef RV_FPGA_OPTIMIZE
         rvdffs #(WIDTH) dff ( .* );
   `else
         rvclkhdr clkhdr ( .* );
         rvdff #(WIDTH) dff (.*, .clk(l1clk));

逐段解释：

* 第 L241-L249 行：`rvdffe` 端口包含 `en` 和 `scan_mode`，这与普通 `rvdff` 不同。
* 第 L253-L267 行：非 physical 编译下检查 `WIDTH >= 8`，除非 `OVERRIDE==1`。不满足时
  `$error`。
* 第 L257-L261 行：FPGA 优化时用 `rvdffs`；否则实例化 `rvclkhdr` 生成 `l1clk`，
  再将 `rvdff` 的 `clk` 端口接到 `l1clk`。

接口关系：

* 被调用：EXU、LSU、DEC 等多处寄存宽数据或控制包时使用。
* 调用：`rvclkhdr` 与 `rvdff`，或 FPGA 路径下的 `rvdffs`。
* 共享状态：`l1clk` 是实例内部时钟线；寄存状态保存在内部 `rvdff`。

§2.5  分段 enable flop：`rvdfflie`、`rvdffibie`、`rvdffppie`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些 wrapper 把宽结构体切成多个字段，让不同字段使用不同 enable 规则。EXU 的
ALU packet 和 predict packet 就使用了这类 wrapper。

关键代码（`rtl/design/lib/beh_lib.sv:L302-L342`）：

.. code-block:: systemverilog

   // format: { LEFT, EXTRA }
   // LEFT # of bits will be done with rvdffie, all else EXTRA with rvdffe
   module rvdfflie #( parameter WIDTH=16, LEFT=8 )
      (
        input  logic [WIDTH-1:0] din,
        input  logic             clk,
        input  logic             rst_l,
        input  logic             en,
        input  logic             scan_mode,
        output logic [WIDTH-1:0] dout
        );

      localparam EXTRA = WIDTH-LEFT;

      localparam LMSB = WIDTH-1;
      localparam LLSB = LMSB-LEFT+1;

逐段解释：

* 第 L302-L342 行：`rvdfflie` 将输入切成 `LEFT` 和 `EXTRA` 两段。`LEFT` 段用
  `rvdffiee`，`EXTRA` 段用 `rvdffe`。
* 第 L344-L394 行：`rvdffibie` 按 `{LEFT, PADLEFT, MIDDLE, PADRIGHT, RIGHT}` 切分。
  `MIDDLE` 的 enable 是 `en & din[PLLSB]`，`RIGHT` 的 enable 是 `en & ~din[PRLSB]`。
* 第 L447-L492 行：`rvdffppie` 按 `{LEFT, PAD, RIGHT}` 切分，`LEFT` 和 `PAD`
  使用 `den`，`RIGHT` 使用 `en`。

接口关系：

* 被调用：`eh2_exu.sv` 用 `rvdfflie` 传播 `eh2_alu_pkt_t`，用 `rvdffppie` 传播
  `eh2_predict_pkt_t`。
* 调用：`rvdffiee`、`rvdffe`、`rvdff2iee`。
* 共享状态：每个字段最终保存在其内部 flop 实例中。

§2.6  input-change enable flop：`rvdffie`、`rvdffiee`、`rvdff2ie`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些 wrapper 用 `din ^ dout` 判断输入是否变化，再决定是否打开 enable。
`rvdffiee` 还叠加外部 `en`。

关键代码（`rtl/design/lib/beh_lib.sv:L497-L555`）：

.. code-block:: systemverilog

   module rvdffie #( parameter WIDTH=1, OVERRIDE=0 )
      (
        input  logic [WIDTH-1:0] din,

        input  logic           clk,
        input  logic           rst_l,
        input  logic             scan_mode,
        output logic [WIDTH-1:0] dout
        );

      logic                      l1clk;
      logic                      en;

   `ifndef RV_PHYSICAL
      if (WIDTH >= 8 || OVERRIDE==1) begin: genblock
   `endif

         assign en = |(din ^ dout);

逐段解释：

* 第 L497-L520 行：`rvdffie` 内部 `en` 等于 `|(din ^ dout)`。输入不变时不触发
  clock-gated 更新。
* 第 L532-L555 行：`rvdffiee` 的 `final_en` 等于 `(|(din ^ dout)) & en`，即输入变化
  和外部 enable 同时为真才更新。
* 第 L568-L610 行：`rvdff2iee` 把宽度均分为 LEFT/RIGHT 两段，两段都用同一个
  `final_en`。
* 第 L613-L654 行：`rvdff2ie` 与 `rvdff2iee` 类似，但没有外部 `en` 端口。

接口关系：

* 被调用：分段 flop wrapper 以及需要减少无效切换的宽寄存器调用。
* 调用：`rvdffe` 或 FPGA 路径下的 `rvdffs`。
* 共享状态：`dout` 既是输出也是输入变化检测的一部分。

§2.7  `rvsyncss` 双级同步器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvsyncss` 和 `rvsyncss_fpga` 都使用两个串联 flop 将 `din` 同步到目标 clock 域。

关键代码（`rtl/design/lib/beh_lib.sv:L656-L686`）：

.. code-block:: systemverilog

   module rvsyncss #(parameter WIDTH = 251)
      (
        input  logic                 clk,
        input  logic                 rst_l,
        input  logic [WIDTH-1:0]     din,
        output logic [WIDTH-1:0]     dout
        );

      logic [WIDTH-1:0]              din_ff1;

      rvdff #(WIDTH) sync_ff1  (.*, .din (din[WIDTH-1:0]),     .dout(din_ff1[WIDTH-1:0]));
      rvdff #(WIDTH) sync_ff2  (.*, .din (din_ff1[WIDTH-1:0]), .dout(dout[WIDTH-1:0]));

   endmodule // rvsyncss

逐段解释：

* 第 L656-L669 行：普通同步器使用两个 `rvdff` 串联。第一级输出是 `din_ff1`，
  第二级输出是 `dout`。
* 第 L671-L686 行：FPGA 版本用 `rvdff_fpga` 两级串联，并显式连接 `gw_clk`、
  `rawclk` 和 `clken`。

接口关系：

* 被调用：需要跨 clock 域同步的控制或状态信号调用。
* 调用：`rvdff` 或 `rvdff_fpga`。
* 共享状态：`din_ff1` 是第一级同步状态，`dout` 是第二级同步状态。

§3  `beh_lib.sv` 仲裁、地址和匹配
----------------------------------

本节覆盖 `beh_lib.sv` 中的仲裁器、地址加法器、二补数、first-one、mask match 和
range check。这些单元被 DEC/EXU/LSU/总线桥等模块复用。

§3.1  `rvarbiter2` 和 `rvarbiter2_pic`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：2 路仲裁器根据 `ready[1:0]` 和 favor bit 选择 `tid`。`rvarbiter2_pic` 额外输出
favor bit。

关键代码（`rtl/design/lib/beh_lib.sv:L723-L757`）：

.. code-block:: systemverilog

   `define RV_ARBITER2          \
      assign ready0 = ~(|ready[1:0]);           \
                                                \
      assign ready1 = ready[1] ^ ready[0];      \
                                                \
      assign ready2 = ready[1] & ready[0];      \
                                                \
      assign favor_in = (ready2 & ~favor) |     \
                        (ready1 & ready[0]) |   \
                        (ready0 & favor);       \
                                                \
      // only update if 2 ready threads         \
      rvdffs #(.WIDTH(1)) favor_ff (.*, .en(shift & ready2), .clk(clk), .din(favor_in),  .dout(favor) );  \

逐段解释：

* 第 L723-L739 行：宏计算三种 ready 情况。两个请求都 ready 时，`shift & ready2`
  才更新 favor；输出 `tid` 在双 ready 时跟随旧 favor，单 ready 时选择唯一 ready 的线程。
* 第 L742-L757 行：`rvarbiter2` 声明端口和本地变量后直接展开 `RV_ARBITER2`。
* 第 L760-L776 行：`rvarbiter2_pic` 同样展开宏，但把 `favor` 作为输出端口暴露。

接口关系：

* 被调用：需要在两个线程或两个来源之间选择的模块调用。
* 调用：宏内部调用 `rvdffs` 保存 favor。
* 共享状态：每个仲裁器实例保存自己的 `favor`。

§3.2  `rvarbiter2_smt`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：SMT 仲裁器在两个线程 ready 时结合 flush、stall、LSU、mul、i0_only 和
`force_favor_flip` 决定 ready、favor 和 I0/I1 选择信号。

关键代码（`rtl/design/lib/beh_lib.sv:L812-L910`）：

.. code-block:: systemverilog

   module rvarbiter2_smt
     (
      input  logic       [1:0] flush,
      input  logic       [1:0] ready_in,
      input  logic       [1:0] lsu_in,
      input  logic       [1:0] mul_in,
      input  logic       [1:0] i0_only_in,
      input  logic       [1:0] thread_stall_in,
      input  logic             force_favor_flip,
      input  logic             shift,
      input  logic             clk,
      input  logic             rst_l,
      input  logic             scan_mode,
      output logic [1:0]       ready,

逐段解释：

* 第 L812-L829 行：接口比普通 2 路仲裁器更丰富，输入包含 flush、ready、LSU、mul、
  i0_only、thread stall、force favor flip 和 shift。
* 第 L844-L859 行：flush 先寄存为 `flush_ff`；`eff_ready_in` 立即屏蔽当前 flush、
  上周期 flush，以及双 ready 时被 stall 的线程。
* 第 L861-L880 行：只有两个线程都有效且存在 LSU/mul/i0_only 相关条件时才更新 favor。
  `force_favor_flip` 可直接翻转 favor。
* 第 L882-L896 行：两个线程同时 LSU 或同时 mul 时，未被 favor 的线程被 cancel 后写入
  `fready`。
* 第 L898-L906 行：`i0_sel_i0_t1`、`i1_sel_i1`、`i1_sel_i0` 从 `fready` 和 `favor`
  组合得到。

接口关系：

* 被调用：SMT 双线程发射或选择路径调用。
* 调用：`rvdff` 保存 flush、ready、update_favor、favor 和 fready。
* 共享状态：`favor`、`flush_ff`、`ready`、`update_favor`、`fready`。

§3.3  `rvlsadder` 与 `rvbradder`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvlsadder` 用 12 bit offset 加到 32 bit RS1；`rvbradder` 用 branch offset 加到
`pc[31:1]`。两者都把低位加法的 carry 和 offset 符号用于高位增减选择。

关键代码（`rtl/design/lib/beh_lib.sv:L913-L975`）：

.. code-block:: systemverilog

   module rvlsadder
     (
       input logic [31:0] rs1,
       input logic [11:0] offset,

       output logic [31:0] dout
       );

      logic                cout;
      logic                sign;

      logic [31:12]        rs1_inc;
      logic [31:12]        rs1_dec;

      assign {cout,dout[11:0]} = {1'b0,rs1[11:0]} + {1'b0,offset[11:0]};

逐段解释：

* 第 L913-L939 行：`rvlsadder` 先计算低 12 位和 carry，再预先计算 `rs1[31:12] + 1`
  与 `- 1`。高位输出由 offset 符号和 carry 决定。
* 第 L943-L975 行：`rvbradder` 结构相同，但低位范围由 `pt.BTB_TOFFSET_SIZE`
  决定，输入 PC 只保留 `[31:1]`。
* EXU ALU 的分支逻辑在 `eh2_exu_alu_ctl.sv:L512-L515` 调用 `rvbradder`。

接口关系：

* 被调用：LSU 地址生成路径调用 `rvlsadder`；EXU 分支路径调用 `rvbradder`。
* 调用：无下层模块。
* 共享状态：纯组合逻辑，不写寄存器。

§3.4  `rvtwoscomp` 与 first-one 查找
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvtwoscomp` 生成二补数；`rvfindfirst1` 返回从高位方向扫描的计数；
`rvfindfirst1hot` 返回从低位方向扫描的首个 one-hot。

关键代码（`rtl/design/lib/beh_lib.sv:L978-L1034`）：

.. code-block:: systemverilog

   // 2s complement circuit
   module rvtwoscomp #( parameter WIDTH=32 )
      (
        input logic [WIDTH-1:0] din,

        output logic [WIDTH-1:0] dout
        );

      logic [WIDTH-1:1]          dout_temp;   // holding for all other bits except for the lsb. LSB is always din

      genvar                     i;

      for ( i = 1; i < WIDTH; i++ )  begin : flip_after_first_one
         assign dout_temp[i] = (|din[i-1:0]) ? ~din[i] : din[i];

逐段解释：

* 第 L979-L996 行：`rvtwoscomp` 保留 bit0；从 bit1 开始，若低位已经出现 1，则反转当前 bit。
  这等价于二补数取反加一的逐位形式。
* 第 L999-L1016 行：`rvfindfirst1` 从 `WIDTH-1` 向 1 扫描。`done` 一旦遇到 1 就保持，
  `dout` 在遇到首个 1 前累加。
* 第 L1018-L1034 行：`rvfindfirst1hot` 从 bit0 向上扫描，首个 `din[i]` 为 1 且此前
  `done` 为 0 的位置输出 1。

接口关系：

* 被调用：除法器用 `rvtwoscomp` 修正符号；其它编码/选择路径可使用 first-one 查找。
* 调用：无下层模块。
* 共享状态：组合逻辑不写寄存器。

§3.5  `rvmaskandmatch`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvmaskandmatch` 根据 `masken` 在 full match 和 mask match 之间切换。注释说明它从
LSB 方向找到第一个 0 后，跳过该位置并匹配其余位。

关键代码（`rtl/design/lib/beh_lib.sv:L1036-L1060`）：

.. code-block:: systemverilog

   // mask and match function matches bits after finding the first 0 position
   // find first starting from LSB. Skip that location and match the rest of the bits
   module rvmaskandmatch #( parameter WIDTH=32 )
      (
        input  logic [WIDTH-1:0] mask,     // this will have the mask in the lower bit positions
        input  logic [WIDTH-1:0] data,     // this is what needs to be matched on the upper bits with the mask's upper bits
        input  logic             masken,   // when 1 : do mask. 0 : full match
        output logic             match
        );

      logic [WIDTH-1:0]          matchvec;
      logic                      masken_or_fullmask;

逐段解释：

* 第 L1036-L1044 行：端口定义明确 `mask`、`data`、`masken` 与 `match`。
* 第 L1049 行：`masken_or_fullmask` 只有在 `masken` 为 1 且 mask 不是全 1 时为真。
* 第 L1051-L1056 行：bit0 特殊处理；bit1 以上在低位 mask 全 1 且 mask 模式有效时
  直接匹配，否则比较 `mask[i] == data[i]`。
* 第 L1058 行：所有 `matchvec` 位都为 1 时输出 `match`。

接口关系：

* 被调用：`rtl/design/dec/eh2_dec_trigger.sv` 和 `rtl/design/lsu/eh2_lsu_trigger.sv`
  使用本模块做 trigger 数据匹配。
* 调用：无下层模块。
* 共享状态：纯组合逻辑，不写寄存器。

§3.6  `rvrangecheck`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rvrangecheck` 依据 `CCM_SADR` 与 `CCM_SIZE` 判断 32 bit 地址是否落在目标区域，
并单独输出高 4 bit region 是否一致。

关键代码（`rtl/design/lib/beh_lib.sv:L1063-L1086`）：

.. code-block:: systemverilog

   // Check if the S_ADDR <= addr < E_ADDR
   module rvrangecheck  #(CCM_SADR = 32'h0,
                          CCM_SIZE  = 128) (
      input  logic [31:0]   addr,                             // Address to be checked for range
      output logic          in_range,                            // S_ADDR <= start_addr < E_ADDR
      output logic          in_region
   );

      localparam REGION_BITS = 4;
      localparam MASK_BITS = 10 + $clog2(CCM_SIZE);

      logic [31:0]          start_addr;
      logic [3:0]           region;

逐段解释：

* 第 L1064-L1069 行：模块参数是起始地址和大小，输出 `in_range` 与 `in_region`。
* 第 L1071-L1078 行：`MASK_BITS` 由 `10 + $clog2(CCM_SIZE)` 计算；`region`
  是起始地址最高 4 bit。
* 第 L1080 行：`in_region` 只比较地址高 4 bit。
* 第 L1081-L1084 行：`CCM_SIZE == 48` 时额外要求特定位不全为 1；其它大小只比较
  `addr[31:MASK_BITS]` 和 `start_addr[31:MASK_BITS]`。

接口关系：

* 被调用：LSU 地址检查和 AHB-to-AXI 桥用它判断 DCCM、ICCM、PIC 地址范围。
* 调用：无下层模块。
* 共享状态：纯组合逻辑，不写寄存器。

§4  `beh_lib.sv` parity、ECC 与 clock header
--------------------------------------------

§4.1  parity generator/checker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`rveven_paritygen` 对输入数据做 reduction XOR；`rveven_paritycheck` 将数据
reduction XOR 与输入 parity 再异或得到 error。

关键代码（`rtl/design/lib/beh_lib.sv:L1089-L1106`）：

.. code-block:: systemverilog

   module rveven_paritygen #(WIDTH = 16)  (
                                            input  logic [WIDTH-1:0]  data_in,         // Data
                                            output logic              parity_out       // generated even parity
                                            );

      assign  parity_out =  ^(data_in[WIDTH-1:0]) ;

   endmodule  // rveven_paritygen

   module rveven_paritycheck #(WIDTH = 16)  (
                                              input  logic [WIDTH-1:0]  data_in,         // Data

逐段解释：

* 第 L1089-L1096 行：parity generator 输出 `^(data_in)`。
* 第 L1098-L1106 行：parity checker 输出 `^(data_in) ^ parity_in`。
* 这两段没有时序逻辑，输出随输入组合变化。

接口关系：

* 被调用：需要 parity 的本地存储或传输路径调用。
* 调用：无下层模块。
* 共享状态：组合逻辑不写寄存器。

§4.2  `rvecc_encode` 与 `rvecc_decode`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：32 bit ECC 编码器生成 7 bit ECC；解码器根据 `ecc_check` 标记 single/double error，
并在 single error 时通过 mask 修正 data 和 ECC。

关键代码（`rtl/design/lib/beh_lib.sv:L1108-L1167`）：

.. code-block:: systemverilog

   module rvecc_encode  (
                         input [31:0] din,
                         output [6:0] ecc_out
                         );
   logic [5:0] ecc_out_temp;

      assign ecc_out_temp[0] = din[0]^din[1]^din[3]^din[4]^din[6]^din[8]^din[10]^din[11]^din[13]^din[15]^din[17]^din[19]^din[21]^din[23]^din[25]^din[26]^din[28]^din[30];
      assign ecc_out_temp[1] = din[0]^din[2]^din[3]^din[5]^din[6]^din[9]^din[10]^din[12]^din[13]^din[16]^din[17]^din[20]^din[21]^din[24]^din[25]^din[27]^din[28]^din[31];
      assign ecc_out_temp[2] = din[1]^din[2]^din[3]^din[7]^din[8]^din[9]^din[10]^din[14]^din[15]^din[16]^din[17]^din[22]^din[23]^din[24]^din[25]^din[29]^din[30]^din[31];

逐段解释：

* 第 L1108-L1123 行：编码器先生成 6 bit `ecc_out_temp`，再把整体 parity 与 6 bit
  ECC 拼成 `ecc_out[6:0]`。
* 第 L1125-L1153 行：解码器重新计算 `ecc_check`。当 `en` 为 1 且 `ecc_check != 0`
  且 `ecc_check[6]` 为 1 时输出 single error；当 `ecc_check[6]` 为 0 时输出 double error。
* 第 L1156-L1158 行：`error_mask[i-1]` 在 syndrome 等于 `i` 时置位。
* 第 L1161-L1165 行：输入 data 和 ECC 被排成 39 bit `din_plus_parity`；single error 时
  与 `error_mask` 异或得到修正后的 data/ECC。

接口关系：

* 被调用：`rtl/design/lsu/eh2_lsu_ecc.sv` 实例化 32 bit ECC encode/decode。
* 调用：无下层模块。
* 共享状态：组合逻辑不写寄存器。

§4.3  64 bit ECC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：64 bit ECC 编码器输出 7 bit ECC；解码器只输出 `ecc_error`，不返回修正数据。

关键代码（`rtl/design/lib/beh_lib.sv:L1169-L1216`）：

.. code-block:: systemverilog

   module rvecc_encode_64  (
                         input [63:0] din,
                         output [6:0] ecc_out
                         );
     assign ecc_out[0] = din[0]^din[1]^din[3]^din[4]^din[6]^din[8]^din[10]^din[11]^din[13]^din[15]^din[17]^din[19]^din[21]^din[23]^din[25]^din[26]^din[28]^din[30]^din[32]^din[34]^din[36]^din[38]^din[40]^din[42]^din[44]^din[46]^din[48]^din[50]^din[52]^din[54]^din[56]^din[57]^din[59]^din[61]^din[63];

      assign ecc_out[1] = din[0]^din[2]^din[3]^din[5]^din[6]^din[9]^din[10]^din[12]^din[13]^din[16]^din[17]^din[20]^din[21]^din[24]^din[25]^din[27]^din[28]^din[31]^din[32]^din[35]^din[36]^din[39]^din[40]^din[43]^din[44]^din[47]^din[48]^din[51]^din[52]^din[55]^din[56]^din[58]^din[59]^din[62]^din[63];

逐段解释：

* 第 L1169-L1187 行：`rvecc_encode_64` 对 64 bit 输入直接给出 `ecc_out[0]` 到
  `ecc_out[6]` 的 XOR 方程。
* 第 L1190-L1214 行：`rvecc_decode_64` 重新计算 7 bit `ecc_check`，当 `en` 为 1
  且 syndrome 非 0 时输出 `ecc_error`。
* 第 L1214 行注释说明所有 sed_ded 情况都会记录为 DE；源码没有 64 bit 单错修正输出。

接口关系：

* 被调用：需要 64 bit ECC 检查的存储路径调用。
* 调用：无下层模块。
* 共享状态：组合逻辑不写寄存器。

§4.4  `TEC_RV_ICG`、`rvclkhdr` 与 `rvoclkhdr`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`TEC_RV_ICG` 是基本 integrated clock gate 行为模型；`rvclkhdr` 与
`rvoclkhdr` 是上层 clock header wrapper。`rvoclkhdr` 在 FPGA 优化时直接输出 `clk`。

关键代码（`rtl/design/lib/beh_lib.sv:L1218-L1274`）：

.. code-block:: systemverilog

   module `TEC_RV_ICG (
      input logic SE, EN, CK,
      output Q
      );

      logic  en_ff /*verilator clock_enable*/;
      logic  enable;

      assign      enable = EN | SE;

   `ifdef VERILATOR
      always_latch if(!CK) en_ff = enable;
   `else

逐段解释：

* 第 L1218-L1238 行：`TEC_RV_ICG` 在 clock 低电平时锁存 `EN | SE` 到 `en_ff`，
  输出 `Q = CK & en_ff`。
* 第 L1240-L1254 行：非 FPGA 优化时定义 `rvclkhdr`，其 `SE` 固定为 0，并实例化
  `TEC_RV_ICG`。
* 第 L1257-L1274 行：`rvoclkhdr` 在 FPGA 优化时 `l1clk = clk`，否则同样通过
  `TEC_RV_ICG` 生成 gated clock。

接口关系：

* 被调用：`rvdffe`、乘法器、DEC/TLU clock gating 等路径调用 clock header。
* 调用：`rvclkhdr` 和 `rvoclkhdr` 调用 `TEC_RV_ICG`。
* 共享状态：`TEC_RV_ICG` 内部 `en_ff` 锁存 enable。

§5  `eh2_lib.sv` BTB/BHT hash
-----------------------------

`eh2_lib.sv` 包含 4 个 EH2 专用 hash 模块，全部依赖 `eh2_param.vh` 中的 BTB/BHT
参数。

§5.1  BTB tag hash
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_btb_tag_hash` XOR 三段 PC bit 得到 BTB tag hash；`eh2_btb_tag_hash_fold`
XOR 两段 PC bit。

关键代码（`rtl/design/lib/eh2_lib.sv:L1-L24`）：

.. code-block:: systemverilog

   module eh2_btb_tag_hash #(
   `include "eh2_param.vh"
    ) (
                          input logic [pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE:pt.BTB_ADDR_HI+1] pc,
                          output logic [pt.BTB_BTAG_SIZE-1:0] hash
                          );

       assign hash = {(pc[pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE:pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE+1] ^
                      pc[pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE+pt.BTB_BTAG_SIZE:pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE+1] ^
                      pc[pt.BTB_ADDR_HI+pt.BTB_BTAG_SIZE:pt.BTB_ADDR_HI+1])};

逐段解释：

* 第 L1-L6 行：`eh2_btb_tag_hash` 的输入 PC 宽度由 `BTB_ADDR_HI` 和三段
  `BTB_BTAG_SIZE` 组成。
* 第 L8-L10 行：hash 是三段 PC bit 的 XOR。
* 第 L13-L24 行：fold 版本输入少一段 `BTB_BTAG_SIZE`，hash 是两段 PC bit XOR。

接口关系：

* 被调用：IFU/BTB 相关逻辑调用这些 hash 模块。
* 调用：无下层模块。
* 共享状态：纯组合逻辑，不写寄存器。

§5.2  BTB address hash
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_btb_addr_hash` 根据参数选择 fold2、SRAM 或三段 XOR 的 index hash 形式。

关键代码（`rtl/design/lib/eh2_lib.sv:L26-L55`）：

.. code-block:: systemverilog

   module eh2_btb_addr_hash  #(
   `include "eh2_param.vh"
    )(
                           input logic [pt.BTB_INDEX3_HI:pt.BTB_INDEX1_LO] pc,
                           output logic [pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] hash
                           );


   if(pt.BTB_FOLD2_INDEX_HASH) begin : fold2
      assign hash[pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] = pc[pt.BTB_INDEX1_HI:pt.BTB_INDEX1_LO] ^
                                                   pc[pt.BTB_INDEX3_HI:pt.BTB_INDEX3_LO];

逐段解释：

* 第 L26-L31 行：模块输入 PC 覆盖 `BTB_INDEX3_HI` 到 `BTB_INDEX1_LO`，输出 BTB 地址位。
* 第 L34-L37 行：`pt.BTB_FOLD2_INDEX_HASH` 为真时，hash 是 index1 与 index3 两段 XOR。
* 第 L40-L46 行：非 fold2 且 `pt.BTB_USE_SRAM` 为真时，hash 高位由三段 XOR 得到，
  同时把 `pc[3]` 放入 `hash[3]`。
* 第 L48-L52 行：其它情况 hash 是 index1、index2、index3 三段 XOR。

接口关系：

* 被调用：BTB index 生成逻辑调用。
* 调用：无下层模块。
* 共享状态：参数选择在 elaboration 阶段确定。

§5.3  BHT GHR hash
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_btb_ghr_hash` 将 BTB hash 和 GHR 混合成 BHT 地址，支持两种参数配置。

关键代码（`rtl/design/lib/eh2_lib.sv:L58-L77`）：

.. code-block:: systemverilog

   module eh2_btb_ghr_hash  #(
   `include "eh2_param.vh"
    )(
                          input logic [pt.BTB_ADDR_HI:pt.BTB_ADDR_LO] hashin,
                          input logic [pt.BHT_GHR_SIZE-1:0] ghr,
                          output logic [pt.BHT_ADDR_HI:pt.BHT_ADDR_LO] hash
                          );

      if(pt.BHT_GHR_HASH_1) begin : ghrhash_cfg1
        assign hash[pt.BHT_ADDR_HI:pt.BHT_ADDR_LO] = { ghr[pt.BHT_GHR_SIZE-1:pt.BTB_INDEX1_HI-2], hashin[pt.BTB_INDEX1_HI:3]^ghr[pt.BTB_INDEX1_HI-3:0]};

逐段解释：

* 第 L58-L64 行：模块输入是 BTB hash 和 GHR，输出是 BHT 地址。
* 第 L66-L68 行：配置 1 把 GHR 高位和 `hashin ^ ghr` 的低位拼接成输出。
* 第 L70-L74 行：配置 2 注释保留了一种未启用表达式，实际使用的是
  `hashin[pt.BHT_GHR_SIZE+2:5] ^ ghr[pt.BHT_GHR_SIZE-1:2]` 加 `ghr[1:0]`。

接口关系：

* 被调用：IFU/BHT 地址生成路径调用。
* 调用：无下层模块。
* 共享状态：纯组合逻辑，不写寄存器。

§6  `mem_lib.sv` RAM 行为模型
-----------------------------

§6.1  RAM test IO 宏
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`EH2_LOCAL_RAM_TEST_IO` 宏集中定义 RAM wrapper 共同使用的测试端口。

关键代码（`rtl/design/lib/mem_lib.sv:L16-L29`）：

.. code-block:: systemverilog

   `define EH2_LOCAL_RAM_TEST_IO          \
   input logic WE,              \
   input logic ME,              \
   input logic CLK,             \
   input logic TEST1,           \
   input logic RME,             \
   input logic  [3:0] RM,       \
   input logic LS,              \
   input logic DS,              \
   input logic SD,              \
   input logic TEST_RNM,        \
   input logic BC1,             \
   input logic BC2,             \
   output logic ROP

逐段解释：

* 第 L16-L29 行：宏声明 WE、ME、CLK、TEST1、RME、RM、LS、DS、SD、TEST_RNM、
  BC1、BC2 和 ROP。后续 RAM 宏和 `eh2_ram` 都展开这组端口。

接口关系：

* 被调用：`EH2_RAM`、`EH2_RAM_BE` 和 `eh2_ram` 展开该宏。
* 调用：无下层模块。
* 共享状态：宏只展开端口声明。

§6.2  `EH2_RAM` 与 `EH2_RAM_BE`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：两个宏生成定深定宽 RAM 模块。`EH2_RAM` 整字写；`EH2_RAM_BE` 通过 `WEM` 做按位
写掩码。

关键代码（`rtl/design/lib/mem_lib.sv:L34-L90`）：

.. code-block:: systemverilog

   `define EH2_RAM(depth, width)              \
   module ram_``depth``x``width(               \
      input logic [$clog2(depth)-1:0] ADR,     \
      input logic [(width-1):0] D,             \
      output logic [(width-1):0] Q,            \
       `EH2_LOCAL_RAM_TEST_IO                 \
   );                                          \
   reg [(width-1):0] ram_core [(depth-1):0];   \
   `ifdef GTLSIM                               \
   integer i;                                  \
   initial begin                               \
      Q = '0;                                  \
      for (i=0; i<depth; i=i+1)                \
        ram_core[i] = '0;                      \

逐段解释：

* 第 L34-L61 行：`EH2_RAM` 生成模块名 `ram_<depth>x<width>`，内部数组是
  `ram_core[depth]`。`GTLSIM` 下初始化 Q 和全部 memory；写时 `ME && WE` 更新；
  读时 `ME && ~WE` 将 `ram_core[ADR]` 送到 Q；`ROP = ME`。
* 第 L63-L90 行：`EH2_RAM_BE` 结构相同，但输入多了 `WEM`，写入表达式是
  `D & WEM | ~WEM & ram_core[ADR]`。
* 非 `GTLSIM` 路径下，写操作同时把 Q 置为 unknown，以暴露同周期读写的不确定性。

接口关系：

* 被调用：文件 L119-L253 展开多个定深定宽 RAM 实例定义。
* 调用：宏展开后不调用下层模块。
* 共享状态：每个生成模块实例有自己的 `ram_core` 数组。

§6.3  `eh2_ram` 参数化 RAM
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_ram` 是参数化 RAM 行为模型，端口与 `EH2_RAM` 宏生成模块相同，但 depth 和
width 是模块参数。

关键代码（`rtl/design/lib/mem_lib.sv:L92-L117`）：

.. code-block:: systemverilog

   // parameterizable RAM for verilator sims
   module eh2_ram #(depth=2, width=1) (
   input logic [$clog2(depth)-1:0] ADR,
   input logic [(width-1):0] D,
   output logic [(width-1):0] Q,
    `EH2_LOCAL_RAM_TEST_IO
   );
   reg [(width-1):0] ram_core [(depth-1):0];
   `ifdef GTLSIM
   integer i;
   initial begin
      Q = '0;
      for (i=0; i<depth; i=i+1)

逐段解释：

* 第 L93-L99 行：`eh2_ram` 参数 `depth`、`width` 决定地址宽度、数据宽度和数组大小。
* 第 L100-L107 行：`GTLSIM` 下初始化输出和所有 RAM 项。
* 第 L109-L116 行：posedge `CLK` 时，`ME && WE` 写数组；非 `GTLSIM` 写时 Q 变 unknown；
  `ME && ~WE` 读数组到 Q。
* `rtl/design/lsu/eh2_lsu_dccm_mem.sv:L118` 实例化 `eh2_ram #(DCCM_INDEX_DEPTH,39)`。

接口关系：

* 被调用：DCCM memory 等仿真模型调用。
* 调用：无下层模块。
* 共享状态：每个实例保存自己的 `ram_core`。

§6.4  定深定宽 RAM 展开表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`mem_lib.sv` 在文件尾部展开多组 `EH2_RAM` 和 `EH2_RAM_BE`，覆盖 DCCM/ICCM/cache
等不同宽度需求。本文只说明源码中实际出现的宏展开范围，不推测每个宽度的使用者。

关键代码（`rtl/design/lib/mem_lib.sv:L119-L256`）：

.. code-block:: systemverilog

   `EH2_RAM(32768, 39)
   `EH2_RAM(16384, 39)
   `EH2_RAM(8192, 39)
   `EH2_RAM(4096, 39)
   `EH2_RAM(3072, 39)
   `EH2_RAM(2048, 39)
   `EH2_RAM(1536, 39)//need this for the 48KB DCCM option)
   `EH2_RAM(1024, 39)
   `EH2_RAM(768, 39)
   `EH2_RAM(512, 39)
   `EH2_RAM(256, 39)
   `EH2_RAM(128, 39)

逐段解释：

* 第 L119-L180 行：源码展开多个整字写 RAM，包括宽度 39、20、34、68、71、42、22、26
  等组合。
* 第 L182-L253 行：源码展开多个 byte-enable 风格 RAM，包括宽度 142、284、136、272、
  52、104、88、44、124、120、62、60 等组合。
* 第 L254-L256 行：文件最后 `undef` 三个宏，避免宏名泄漏到后续编译单元。

接口关系：

* 被调用：不同 memory wrapper 可实例化这些展开出的模块名。
* 调用：宏展开产生独立 RAM 模块。
* 共享状态：每个 RAM 实例有独立 `ram_core`。

§7  AXI/AHB 转换器
------------------

`ahb_to_axi4.sv` 和 `axi4_to_ahb.sv` 是协议转换器。二者位于 lib 目录，但不是基础
flop primitive；顶层在构建 AHB-Lite gasket 时实例化它们。

§7.1  顶层实例化位置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_veer.sv` 在 `Gen_AXI_To_AHB` generate block 中实例化多个
`axi4_to_ahb`，并在后续位置实例化 `ahb_to_axi4`。

关键代码（`rtl/design/eh2_veer.sv:L1143-L1148`，`rtl/design/eh2_veer.sv:L1327-L1329`）：

.. code-block:: systemverilog

      if (pt.BUILD_AHB_LITE == 1) begin: Gen_AXI_To_AHB

         // AXI4 -> AHB Gasket for LSU
         axi4_to_ahb #(.NUM_THREADS(pt.NUM_THREADS),
                       .TAG(pt.LSU_BUS_TAG)) lsu_axi4_to_ahb (

.. code-block:: systemverilog

         ahb_to_axi4 #(.pt(pt),
                       .TAG(pt.DMA_BUS_TAG)) sb_ahb_to_axi4 (

逐段解释：

* 第 L1143-L1148 行：当 `pt.BUILD_AHB_LITE == 1` 时，顶层生成 AXI4 到 AHB gasket。
  片段中 LSU 路径的实例参数是 `NUM_THREADS` 和 `TAG`。
* 第 L1327-L1329 行：同一顶层后续实例化 `ahb_to_axi4`，参数包含 `pt` 和
  `DMA_BUS_TAG`。

接口关系：

* 被调用：`eh2_veer.sv` 顶层实例化转换器。
* 调用：转换器内部使用 `rvdff*_fpga`、`rvclkhdr`、`rvrangecheck` 等库单元。
* 共享状态：转换器各实例保存各自 buffer、state 和响应状态。

§7.2  `axi4_to_ahb` 接口与状态集合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`axi4_to_ahb` 接收 AXI write/read channels，输出 AHB-Lite master 信号。内部状态机
包含 IDLE、CMD_RD、CMD_WR、DATA_RD、DATA_WR、DONE、STREAM_RD、STREAM_ERR_RD。

关键代码（`rtl/design/lib/axi4_to_ahb.sv:L24-L90`）：

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

逐段解释：

* 第 L24-L35 行：模块参数为 `TAG` 和 `NUM_THREADS`，输入包含 `clk`、`free_clk`、
  `bus_clk_en`、`clk_override` 与每线程 `dec_tlu_force_halt`。
* 第 L37-L70 行：AXI 写地址、写数据、写响应、读地址、读数据通道均出现在接口中。
* 第 L72-L84 行：AHB-Lite master 输出地址、burst、lock、prot、size、trans、write、
  write data，并接收 read data、ready、resp。
* 第 L88-L90 行：`state_t` 枚举列出 8 个状态，是后续 buffer 状态机的状态集合。

接口关系：

* 被调用：顶层 AHB-Lite gasket 实例化。
* 调用：内部调用 `rvdff*_fpga`、`rvclkhdr` 和 helper functions。
* 共享状态：`buf_state`、write buffer、slave buffer、AHB sampled signals。

§7.3  `axi4_to_ahb` helper functions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：三个自动函数从 AXI write strobe 推导 AHB size、address 低位和下一个 byte pointer。

关键代码（`rtl/design/lib/axi4_to_ahb.sv:L182-L222`）：

.. code-block:: systemverilog

      // Function to get the length from byte enable
      function automatic logic [1:0] get_write_size;
         input logic [7:0] byteen;

         logic [1:0]       size;

         size[1:0] = (2'b11 & {2{(byteen[7:0] == 8'hff)}}) |
                     (2'b10 & {2{((byteen[7:0] == 8'hf0) | (byteen[7:0] == 8'h0f))}}) |
                     (2'b01 & {2{((byteen[7:0] == 8'hc0) | (byteen[7:0] == 8'h30) | (byteen[7:0] == 8'h0c) | (byteen[7:0] == 8'h03))}});

         return size[1:0];

逐段解释：

* 第 L183-L193 行：`get_write_size` 根据 `byteen` 模式返回 size。全 8 bit 写返回
  `2'b11`，半宽模式返回 `2'b10`，两字节相邻模式返回 `2'b01`，其它未命中项保持 0。
* 第 L196-L207 行：`get_write_addr` 根据 `byteen` 返回地址低 3 位，用于把非全宽写映射到
  AHB 地址偏移。
* 第 L210-L222 行：`get_nxtbyte_ptr` 从当前 byte pointer 起扫描 `byteen`，找到下一个
  需要传输的 byte 位置。

接口关系：

* 被调用：`axi4_to_ahb` 状态机和 buffer 输入组合逻辑调用这些函数。
* 调用：无下层函数。
* 共享状态：自动函数不保存状态。

§7.4  `axi4_to_ahb` 写缓冲与响应通道
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：AXI 写地址和写数据可以分开到达，模块用 write buffer 等待两者齐备后形成
`master_valid`。AXI B/R 响应由 slave buffer 和 AHB 返回信息生成。

关键代码（`rtl/design/lib/axi4_to_ahb.sv:L231-L260`）：

.. code-block:: systemverilog

      // Write buffer
      assign wrbuf_en       = axi_awvalid & axi_awready & master_ready;
      assign wrbuf_data_en  = axi_wvalid & axi_wready & master_ready;
      assign wrbuf_cmd_sent = master_valid & master_ready & (master_opc[2:1] == 2'b01);
      assign wrbuf_rst      = (wrbuf_cmd_sent & ~wrbuf_en) | dec_tlu_force_halt_bus[wrbuf_tag[TAG-1]];

      assign axi_awready = ~(wrbuf_vld & ~wrbuf_cmd_sent) & master_ready;
      assign axi_wready  = ~(wrbuf_data_vld & ~wrbuf_cmd_sent) & master_ready;
      assign axi_arready = ~(wrbuf_vld & wrbuf_data_vld) & master_ready;
      assign axi_rlast   = 1'b1;

逐段解释：

* 第 L232-L235 行：write address 和 write data 分别写入 buffer；当 master command 已发送且没有新
  AW 写入，或对应线程 force halt 时，write buffer reset。
* 第 L237-L240 行：AW/W/AR ready 都受 buffer 是否占用和 `master_ready` 控制；读响应
  `axi_rlast` 固定为 1。
* 第 L242-L249 行：`wr_cmd_vld` 要求 write address 和 data 都有效；写命令优先形成
  `master_*`，否则使用 AXI AR 输入形成 read command。
* 第 L252-L260 行：AXI B/R 响应由 `slave_valid`、`slave_ready`、`slave_opc`、
  `slave_tag` 和 `slave_rdata` 组合生成。

接口关系：

* 被调用：AXI master 侧握手驱动该逻辑。
* 调用：无下层模块；buffer flops 在 L415-L446 保存状态。
* 共享状态：`wrbuf_vld`、`wrbuf_data_vld`、`wrbuf_tag/size/addr/data/byteen`。

§7.5  `axi4_to_ahb` buffer 状态机
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：状态机把 AXI read/write command 转为 AHB transaction，并处理 stream read、write
拆分、AHB error、DONE 响应等路径。

关键代码（`rtl/design/lib/axi4_to_ahb.sv:L262-L380`）：

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

逐段解释：

* 第 L263-L280 行：`always_comb` 先给所有控制输出默认值，避免状态分支遗漏赋值。
* 第 L282-L295 行：IDLE 状态接受新 master command，按 opcode 进入 CMD_WR 或 CMD_RD，
  同时写 buffer 并产生首个 AHB `HTRANS=NONSEQ`。
* 第 L296-L329 行：CMD_RD 和 STREAM_RD/STREAM_ERR_RD 处理读命令、流式读和读错误路径。
* 第 L330-L372 行：DATA_RD、CMD_WR、DATA_WR 处理读返回、写 beat 推进、byte pointer 更新和
  命令完成判定。
* 第 L373-L378 行：DONE 状态等待 slave side ready，并产生 `slave_valid_pre`。

接口关系：

* 被调用：`buf_state`、AHB sampled signals、master/slave ready 控制状态转移。
* 调用：`get_nxtbyte_ptr` 用于写拆分 byte pointer。
* 共享状态：`buf_state` 在 L425 的 `buf_state_ff` 中保存。

§7.6  `axi4_to_ahb` AHB 输出、寄存器和 clock header
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：状态机输出经组合逻辑生成 AHB 信号，再通过多个 `_fpga` wrapper 保存 buffer、
AHB sampled signals 和响应信息；最后用 clock header 生成 bus/buffer/data clock。

关键代码（`rtl/design/lib/axi4_to_ahb.sv:L382-L461`）：

.. code-block:: systemverilog

      assign buf_rst              = dec_tlu_force_halt_bus[buf_tag[TAG-1]];
      assign cmd_done_rst         = slave_valid_pre;
      assign buf_addr_in[31:3]    = master_addr[31:3];
      assign buf_addr_in[2:0]     = (buf_aligned_in & (master_opc[2:1] == 2'b01)) ? get_write_addr(master_byteen[7:0]) : master_addr[2:0];
      assign buf_tag_in[TAG-1:0]  = master_tag[TAG-1:0];
      assign buf_byteen_in[7:0]   = wrbuf_byteen[7:0];
      assign buf_data_in[63:0]    = (buf_state == DATA_RD) ? ahb_hrdata_q[63:0] : master_wdata[63:0];
      assign buf_size_in[1:0]     = (buf_aligned_in & (master_size[1:0] == 2'b11) & (master_opc[2:1] == 2'b01)) ? get_write_size(master_byteen[7:0]) : master_size[1:0];

逐段解释：

* 第 L382-L394 行：buffer 输入组合逻辑计算地址低位、tag、byte enable、data、size 和
  aligned 标志。
* 第 L397-L404 行：AHB 输出由 bypass 或 buffer 状态选择，`ahb_hburst` 固定为 0，
  `ahb_hmastlock` 固定为 0，`ahb_hprot` 由常量和 `axi_arprot[2]` 组成。
* 第 L406-L412 行：slave response 数据在 error 时返回 `last_bus_addr` 复制值，否则返回
  buffer data 或当前 AHB read data。
* 第 L415-L446 行：write buffer、transaction buffer、slave buffer、command done、
  AHB sampled signals 均通过 `rvdff*_fpga` 或 `rvdffe` 保存。
* 第 L450-L461 行：clock enable 由 `bus_clk_en`、buffer 写入、slave buffer 写入、
  `clk_override` 和状态决定；非 FPGA 优化时用 `rvclkhdr` 生成 clock。

接口关系：

* 被调用：状态机和 AXI/AHB handshake 驱动本段。
* 调用：`get_write_addr`、`get_write_size`、`rvdff*_fpga`、`rvdffe`、`rvclkhdr`。
* 共享状态：多个 buffer 和 sampled AHB 信号共同构成转换器时序状态。

§7.7  `ahb_to_axi4` 接口与状态机
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`ahb_to_axi4` 接收 AHB-Lite slave 侧请求，生成 AXI4 master 侧请求。状态机包含
IDLE、WR、RD、PEND。

关键代码（`rtl/design/lib/ahb_to_axi4.sv:L23-L166`）：

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

逐段解释：

* 第 L23-L35 行：模块导入 EH2 package，参数包含 `TAG` 和 `eh2_param.vh`。
* 第 L37-L73 行：AXI master 侧写地址、写数据、写响应、读地址、读数据通道全部在端口中。
* 第 L75-L89 行：AHB-Lite slave 侧输入请求，输出 read data、readyout 和 response。
* 第 L95-L100 行：状态枚举包括 IDLE、WR、RD、PEND。
* 第 L136-L164 行：状态机 IDLE 接受 AHB transaction；WR 等待 command buffer 可用；
  RD 发读 command；PEND 等待 AXI read data 返回并缓存 read data/error。
* 第 L166 行：`state_reg` 用 `rvdffs_fpga` 保存 `buf_state`。

接口关系：

* 被调用：`eh2_veer.sv` 的 AHB-Lite gasket 实例化本模块。
* 调用：`rvdff*_fpga`、`rvdffe`、`rvrangecheck`、`rvclkhdr`。
* 共享状态：`buf_state`、command buffer、AHB sampled signals、read data buffer。

§7.8  `ahb_to_axi4` 错误检查、地址范围和 AXI 输出
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：AHB-to-AXI 桥在发送 AXI command 前检查 DCCM、ICCM、PIC 地址范围、访问 size
和对齐，并把 command buffer 映射到 AXI AW/W/AR 通道。

关键代码（`rtl/design/lib/ahb_to_axi4.sv:L180-L271`）：

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

* 第 L180-L188 行：`ahb_hresp` 覆盖非 DCCM/ICCM 请求、ICCM 或 DCCM 写 size 不合规、
  halfword/word/doubleword 未对齐、read ECC error，以及上一拍 error 延续。
* 第 L191-L200 行：read data、read error、HRESP、HREADY、HTRANS、HSIZE、HWRITE、HADDR
  被 `_fpga` wrapper 采样。
* 第 L202-L234 行：DCCM、ICCM、PIC 地址范围用 `rvrangecheck` 判断；DCCM/ICCM 受
  `pt.DCCM_ENABLE` 和 `pt.ICCM_ENABLE` 条件控制。
* 第 L237-L245 行：command buffer 保存 valid、write、size、wstrb、addr 和 wdata。
* 第 L247-L271 行：AXI AW/W/AR/R ready 信号由 command buffer 映射。写 data 和写地址
  同时有效，读请求使用 AR 通道，B/R ready 固定为 1。

接口关系：

* 被调用：AHB-Lite slave 请求和 AXI 返回驱动本段。
* 调用：`rvrangecheck`、`rvdff*_fpga`、`rvdffe`。
* 共享状态：command buffer 和 sampled AHB signals。

§7.9  `ahb_to_axi4` clock header 与断言
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：桥根据 bus enable、AHB address enable 和 read data buffer enable 生成本地 clock；
在 `RV_ASSERT_ON` 下检查 AHB error protocol。

关键代码（`rtl/design/lib/ahb_to_axi4.sv:L273-L296`）：

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

逐段解释：

* 第 L274-L275 行：地址 clock enable 只在 AHB ready 且 transaction 有效时打开；
  read data buffer clock enable 由 `buf_rdata_en` 控制。
* 第 L277-L285 行：FPGA 优化时本地 clock 置 0；非 FPGA 路径实例化 3 个 `rvclkhdr`。
* 第 L287-L294 行：`RV_ASSERT_ON` 下声明并断言 AHB error protocol：`ahb_hready & ahb_hresp`
  应由上一拍 `~ahb_hready & ahb_hresp` 领先。

接口关系：

* 被调用：桥内部状态机和 AHB handshake 驱动 enable。
* 调用：`rvclkhdr`。
* 共享状态：clock header 内部锁存 enable。

§8  调用关系速查
----------------

本节列出从源码检索到的典型调用关系，便于从使用点回到库单元。

* `rvdff`、`rvdffe`、`rvdfflie`、`rvdffppie`：DEC、EXU、LSU、debug 和总线桥广泛使用。
* `rvbradder`：`rtl/design/exu/eh2_exu_alu_ctl.sv:L512-L515` 调用，用于 branch target。
* `rvmaskandmatch`：`rtl/design/dec/eh2_dec_trigger.sv:L51-L52` 和
  `rtl/design/lsu/eh2_lsu_trigger.sv:L75` 调用。
* `rvrangecheck`：`rtl/design/lsu/eh2_lsu_addrcheck.sv:L89-L128` 和
  `rtl/design/lib/ahb_to_axi4.sv:L202-L234` 调用。
* `rvecc_encode`、`rvecc_decode`：`rtl/design/lsu/eh2_lsu_ecc.sv:L144-L179` 调用。
* `eh2_ram`：`rtl/design/lsu/eh2_lsu_dccm_mem.sv:L118` 调用。
* `axi4_to_ahb`、`ahb_to_axi4`：`rtl/design/eh2_veer.sv:L1143-L1329` 在 AHB-Lite gasket
  中调用。

§9  Lib 常见失败模式与排查
--------------------------

library 模块是全设计复用最多的一层。问题常见于“症状在 DEC/LSU/EXU，根因在库单元
参数或 clock/reset wrapper”。排查时先确认是行为库、FPGA wrapper、ECC/rangecheck，
还是 AXI/AHB bridge。

.. list-table:: lib 失败模式
   :header-rows: 1
   :widths: 24 32 28 16

   * - 现象
     - 可能根因
     - 排查命令
     - 阅读入口
   * - compile 找不到 ``rvdffe`` 或 ``rvclkhdr``
     - ``-v`` library mode 文件未进入 filelist，或编译顺序被改
     - ``sed -n '1,25p' dv/uvm/core_eh2/eh2_rtl.f``
     - 本章 §1 与 :ref:`appendix_a_rtl/index`
   * - reset 后寄存器不是预期初值
     - 使用了 ``rvdff`` / ``rvdffs`` / ``rvdffsc`` 中不同 reset/set wrapper
     - ``rg -n "rvdff[s|sc]* #|rvdff.*rst_l" /home/host/Cores-VeeR-EH2/design``
     - 本章 §2
   * - DCCM/ICCM 地址范围判断错
     - ``rvrangecheck`` 参数或 ``pt.*_SADR`` / size 配置漂移
     - ``rg -n "rvrangecheck|DCCM_SADR|ICCM_SADR" /home/host/Cores-VeeR-EH2/design``
     - 本章 §4 与 :ref:`appendix_a_rtl/lsu`
   * - ECC 注入后 syndrome 与预期不同
     - 32-bit/64-bit encode/decode 模块选错或 data/parity 位拼接错
     - ``rg -n "rvecc_encode|rvecc_decode|ecc" /home/host/Cores-VeeR-EH2/design``
     - 本章 §5 与 :ref:`appendix_a_rtl/mem`
   * - AHB-Lite gasket 响应 error
     - ``ahb_to_axi4`` 对 size/alignment/range 的 HRESP 条件命中
     - ``rg -n "ahb_hresp|rvrangecheck" /home/host/Cores-VeeR-EH2/design/lib/ahb_to_axi4.sv``
     - 本章 §7.8
   * - AXI 到 AHB 读写卡住
     - ``axi4_to_ahb`` 或 ``ahb_to_axi4`` command buffer valid/ready 未释放
     - ``rg -n "buf_state|cmd|ready|valid" /home/host/Cores-VeeR-EH2/design/lib/*axi*.sv``
     - 本章 §7 与 :ref:`appendix_a_rtl/shared_axi4`

§10  参考资料
-------------

* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/lib/beh_lib.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/lib/eh2_lib.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/lib/mem_lib.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/lib/axi4_to_ahb.sv`
* 源文件绝对路径：:file:`/home/host/eh2-veri/rtl/design/lib/ahb_to_axi4.sv`
* filelist 绝对路径：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* 顶层实例绝对路径：:file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* 关联章节：:doc:`exu`
* 关联章节：:doc:`lsu`
* 关联章节：:doc:`dec`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
