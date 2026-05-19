.. _dccm_iccm:
.. _02_core_reference/dccm_iccm:

DCCM / ICCM 紧耦合存储接口
================================================================================

:status: draft
:source: syn/include/eh2_param.vh; rtl/lec_shim/eh2_veer_lec_pack.sv; dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; dv/formal/eh2_veer_sva.sv; dv/formal/properties/eh2_lsu_assert.sv; dv/formal/properties/eh2_pmp_assert.sv; dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S; dv/uvm/core_eh2/tests/asm/directed_iccm_eccerror.S
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界
--------------------------------------------------------------------------------

本章描述当前仓库中可以直接回溯的 DCCM 与 ICCM 证据：参数文件中的容量、地址与
bank 参数；LEC shim 暴露出的 DCCM/ICCM 端口；TB top 对内部 memory packet 的
tie-off；formal property 对 DCCM/ICCM 可知性与互斥关系的检查；以及 directed ASM
对 DCCM byte/halfword/word 路径和 ICCM fetch 路径的刺激。

当前工作区没有可读取的 :file:`rtl/design/lsu/eh2_lsu_dccm_ctl.sv`、
:file:`rtl/design/lsu/eh2_lsu_ecc.sv` 或 :file:`rtl/design/eh2_mem.sv` 源文件。
因此本章不再保留旧文中无法从当前仓库直接确认的实现细节，例如 DCCM 内部控制器
流水级、ECC 更正周期的具体状态机或单周期延迟结论。

可见证据链如下：

.. code-block:: text

   syn/include/eh2_param.vh
      |
      |-- DCCM_* / ICCM_* parameter values
      |
      v
   rtl/lec_shim/eh2_veer_lec_pack.sv
      |
      |-- dccm_* ports
      |-- iccm_* ports
      |
      +--> dv/formal/eh2_veer_sva.sv properties
      |
      `--> dv/uvm/core_eh2/tb/core_eh2_tb_top.sv tie-off evidence

**逐段解释** ：

* 参数文件说明当前配置下 DCCM 与 ICCM 都处于 enable 状态，并给出起始地址、
  region、bank 数和数据宽度相关参数。
* LEC shim 是当前仓库里暴露 DCCM/ICCM pin 名称最完整的源码文件。它的文件头说明该
  wrapper 只用于 LEC，不用于仿真或生产综合。
* TB top 注释说明 DUT 内部包含 ``eh2_mem``，同时 external memory packets 被绑为
  ``'0``，表示基础 UVM TB 使用内部 memories。
* formal 文件检查 DCCM/ICCM 控制信号不为 unknown，并把部分信号与内部层级引用关联。

**接口关系** ：

* **被调用** ：本章支撑 :ref:`appendix_a_rtl/mem`、:ref:`formal_flow` 和
  directed ASM 说明。
* **调用** ：无运行时代码调用；文档引用参数、端口、formal property 和 ASM。
* **共享状态** ：DCCM/ICCM 相关状态在本章可见范围内表现为参数、端口和 formal 输入。

§2  参数文件中的 DCCM 配置
--------------------------------------------------------------------------------

§2.1  DCCM bank、数据宽度与地址参数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：:file:`syn/include/eh2_param.vh` 通过 ``eh2_param_t pt`` 指定当前综合/LEC
参数。DCCM 参数集中给出 bank、width、enable、region、起始地址和 size。

**关键代码** （``syn/include/eh2_param.vh:L64-L76``）：

.. code-block:: systemverilog

       DCCM_BANK_BITS         : 7'h03         ,
       DCCM_BITS              : 9'h010        ,
       DCCM_BYTE_WIDTH        : 7'h04         ,
       DCCM_DATA_WIDTH        : 10'h020        ,
       DCCM_ECC_WIDTH         : 7'h07         ,
       DCCM_ENABLE            : 5'h01         ,
       DCCM_FDATA_WIDTH       : 10'h027        ,
       DCCM_INDEX_BITS        : 8'h0B         ,
       DCCM_NUM_BANKS         : 9'h008        ,
       DCCM_REGION            : 8'h0F         ,
       DCCM_SADR              : 36'h0F0040000  ,
       DCCM_SIZE              : 14'h0040       ,
       DCCM_WIDTH_BITS        : 6'h02         ,

**逐段解释** ：

* 第 L64-L65 行：``DCCM_BANK_BITS`` 为 ``7'h03``，``DCCM_BITS`` 为 ``9'h010``。
  LEC shim 后续用 ``pt.DCCM_BITS`` 定义 DCCM 地址端口宽度。
* 第 L66-L70 行：``DCCM_BYTE_WIDTH`` 是 ``7'h04``，``DCCM_DATA_WIDTH`` 是
  ``10'h020``，``DCCM_ECC_WIDTH`` 是 ``7'h07``，``DCCM_FDATA_WIDTH`` 是
  ``10'h027``。这些数值显示当前 DCCM full data width 比 32-bit data width 多 7 bit。
* 第 L69 行：``DCCM_ENABLE`` 为 ``5'h01``，表示当前参数打开 DCCM。
* 第 L71-L72 行：``DCCM_INDEX_BITS`` 为 ``8'h0B``，``DCCM_NUM_BANKS`` 为
  ``9'h008``。
* 第 L73-L75 行：``DCCM_REGION`` 是 ``8'h0F``，``DCCM_SADR`` 是
  ``36'h0F0040000``，``DCCM_SIZE`` 是 ``14'h0040``。
* 第 L76 行：``DCCM_WIDTH_BITS`` 为 ``6'h02``。

**接口关系** ：

* **被调用** ：``eh2_veer_lec_pack`` 通过 ``include "eh2_param.vh"`` 获得这些参数。
* **调用** ：无。
* **共享状态** ：``pt`` 参数结构在编译/elaboration 期决定端口宽度和数组维度。

§2.2  DCCM directed ASM 使用的基地址
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``directed_toggle_dccm_walk.S`` 用立即数 ``0xF0040000`` 作为 DCCM 访问基址。
该值与参数文件中的 ``DCCM_SADR`` 一致。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S:L8-L18``）：

.. code-block:: bash

   _start:
       li      t0, 0xF0040000
   
       li      t1, 0x00000001
       sb      t1, 0(t0)
       lbu     t2, 0(t0)
       li      t3, 0x01
       bne     t2, t3, fail
       lb      t2, 0(t0)
       bne     t2, t3, fail

**逐段解释** ：

* 第 L8-L9 行：测试入口把 ``t0`` 设置为 ``0xF0040000``，即 DCCM 参数文件记录的
  ``DCCM_SADR`` 低 32-bit 值。
* 第 L11-L15 行：测试向 ``0(t0)`` 写入 byte ``0x01``，再用 ``lbu`` 读取并比较。
* 第 L16-L17 行：同一地址再用 ``lb`` 读取，验证符号扩展结果仍等于 ``0x01``。

**接口关系** ：

* **被调用** ：directed testlist 或仿真脚本编译运行该 ASM。
* **调用** ：RISC-V store/load 指令访问 DCCM 地址。
* **共享状态** ：使用 mailbox 地址 ``0xD0580000`` 上报 pass/fail，见本章 §7。

§3  参数文件中的 ICCM 配置
--------------------------------------------------------------------------------

§3.1  ICCM bank、ICache 关系与地址参数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：参数文件给出 ICCM 的 bank 数、enable 位、与 ICache 的关系、region、起始
地址和 size。

**关键代码** （``syn/include/eh2_param.vh:L116-L127``）：

.. code-block:: systemverilog

       ICCM_BANK_BITS         : 7'h02         ,
       ICCM_BANK_HI           : 9'h003        ,
       ICCM_BANK_INDEX_LO     : 9'h004        ,
       ICCM_BITS              : 9'h010        ,
       ICCM_ENABLE            : 5'h01         ,
       ICCM_ICACHE            : 5'h01         ,
       ICCM_INDEX_BITS        : 8'h0C         ,
       ICCM_NUM_BANKS         : 9'h004        ,
       ICCM_ONLY              : 5'h00         ,
       ICCM_REGION            : 8'h0E         ,
       ICCM_SADR              : 36'h0EE000000  ,
       ICCM_SIZE              : 14'h0040       ,

**逐段解释** ：

* 第 L116-L119 行：ICCM bank 参数包括 ``ICCM_BANK_BITS``、``ICCM_BANK_HI``、
  ``ICCM_BANK_INDEX_LO`` 和 ``ICCM_BITS``。
* 第 L120 行：``ICCM_ENABLE`` 为 ``5'h01``，表示当前参数打开 ICCM。
* 第 L121 行：``ICCM_ICACHE`` 为 ``5'h01``。本章只记录该参数值，不推断 ICache 与
  ICCM 的运行时选择策略。
* 第 L122-L124 行：``ICCM_INDEX_BITS`` 为 ``8'h0C``，``ICCM_NUM_BANKS`` 为
  ``9'h004``，``ICCM_ONLY`` 为 ``5'h00``。
* 第 L125-L127 行：``ICCM_REGION`` 为 ``8'h0E``，``ICCM_SADR`` 为
  ``36'h0EE000000``，``ICCM_SIZE`` 为 ``14'h0040``。

**接口关系** ：

* **被调用** ：LEC shim、formal bind 和综合脚本通过同一参数结构解释 ICCM 端口宽度。
* **调用** ：无。
* **共享状态** ：编译期 ``pt`` 参数。

§3.2  ICCM directed ASM 的 fetch 刺激
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``directed_iccm_eccerror.S`` 不直接写 ICCM 地址；它通过对齐的
``iccm_probe`` 函数和 ``fence.i`` 反复激活 IFU/ICCM fetch 路径。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_iccm_eccerror.S:L12-L25``）：

.. code-block:: bash

   _start:
       la      t0, trap_handler
       csrw    mtvec, t0
       li      s0, 0
       fence.i
   
       li      t1, 32
   fetch_loop:
       jal     ra, iccm_probe
       addi    t1, t1, -1
       bnez    t1, fetch_loop
   
       li      t0, 0x1234
       bne     s0, t0, fail

**逐段解释** ：

* 第 L12-L14 行：测试把 ``trap_handler`` 地址写入 ``mtvec``。
* 第 L15-L16 行：清零 ``s0`` 后执行 ``fence.i``，使后续 instruction fetch 路径重新取指。
* 第 L18-L22 行：循环计数为 32，每轮调用 ``iccm_probe`` 并递减计数。
* 第 L24-L25 行：循环结束后要求 ``s0`` 等于 ``0x1234``，否则进入 fail。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_iccm_eccerror.S:L40-L55``）：

.. code-block:: bash

   .align 5
   iccm_probe:
       li      s0, 0x1234
       addi    s1, s1, 1
       addi    s2, s2, -1
       ret
   
   .align 4
   trap_handler:
       // If memory-error injection raises a recoverable trap, skip the faulting
       // instruction and continue.  Unexpected repeated traps will timeout rather
       // than report a false PASS.
       csrr    t0, mepc
       addi    t0, t0, 4
       csrw    mepc, t0
       mret

**逐段解释** ：

* 第 L40-L45 行：``iccm_probe`` 按 32-byte 对齐，写 ``s0=0x1234``，并更新 ``s1`` 与
  ``s2`` 后返回。
* 第 L47-L55 行：trap handler 读取 ``mepc``，加 4 后写回，再执行 ``mret``。源码注释
  说明如果 UVM 侧启用 memory-error injection，该 handler 用于跳过可恢复 faulting
  instruction。

**接口关系** ：

* **被调用** ：directed ICCM/ECC error 测试运行该 ASM。
* **调用** ：``csrw``、``fence.i``、``jal``、``mret`` 等 ISA 指令。
* **共享状态** ：``s0`` 是测试自检值；mailbox 用于最终 pass/fail。

§4  LEC shim 暴露的 DCCM/ICCM pins
--------------------------------------------------------------------------------

§4.1  LEC wrapper 的适用范围
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_veer_lec_pack`` 的文件头限定了该 wrapper 的用途：只用于 LEC，
不是仿真或生产综合 wrapper。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L1-L10``）：

.. code-block:: systemverilog

   // LEC-ONLY wrapper. Not for simulation and not for production synthesis.
   // Old Formality O-2018.06-SP1 mishandles selected 2D packed-array top ports.
   // This wrapper exposes the trace/RVFI-style outputs as 1D vectors while keeping
   // the inner eh2_veer instance unchanged.
   
   module eh2_veer_lec_pack
   import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (

**逐段解释** ：

* 第 L1 行：注释明确写出 ``LEC-ONLY``，并说明不用于 simulation 或 production synthesis。
* 第 L2-L4 行：wrapper 的目的在于绕开旧 Formality 对部分 2D packed-array top ports
  的处理问题，同时保持内部 ``eh2_veer`` 实例不变。
* 第 L6-L10 行：模块 import ``eh2_pkg::*``，并 include ``eh2_param.vh``，因此后续
  ``pt.DCCM_*`` 与 ``pt.ICCM_*`` 都来自参数文件。

**接口关系** ：

* **被调用** ：LEC/Formality 脚本可选择该 wrapper 作为比较边界。
* **调用** ：内部实例化 ``eh2_veer`` 的细节不在本片段中展开。
* **共享状态** ：共享 ``pt`` 参数结构。

§4.2  DCCM pins
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：LEC shim 把 DCCM 读写使能、lo/hi 地址、lo/hi 写数据和 lo/hi 读数据作为
module pins 暴露。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L61-L71``）：

.. code-block:: systemverilog

      output logic                           dccm_wren,
      output logic                           dccm_rden,
      output logic [pt.DCCM_BITS-1:0]        dccm_wr_addr_lo,
      output logic [pt.DCCM_BITS-1:0]        dccm_wr_addr_hi,
      output logic [pt.DCCM_BITS-1:0]        dccm_rd_addr_lo,
      output logic [pt.DCCM_BITS-1:0]        dccm_rd_addr_hi,
      output logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_wr_data_lo,
      output logic [pt.DCCM_FDATA_WIDTH-1:0] dccm_wr_data_hi,
   
      input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_rd_data_lo,
      input logic [pt.DCCM_FDATA_WIDTH-1:0]  dccm_rd_data_hi,

**逐段解释** ：

* 第 L61-L62 行：``dccm_wren`` 和 ``dccm_rden`` 是 wrapper 输出，表示内部 core 向
  DCCM memory 侧发出的写/读使能。
* 第 L63-L66 行：写地址和读地址都有 ``lo`` 与 ``hi`` 两路，宽度为
  ``pt.DCCM_BITS``。
* 第 L67-L68 行：写数据也分 ``lo`` 与 ``hi`` 两路，宽度为 ``pt.DCCM_FDATA_WIDTH``。
* 第 L70-L71 行：读数据从 memory 侧输入 wrapper，同样分 ``lo`` 与 ``hi`` 两路。

**接口关系** ：

* **被调用** ：formal/LEC wrapper 边界观察这些 pins。
* **调用** ：无下层函数调用。
* **共享状态** ：pin 宽度由 ``pt.DCCM_BITS`` 与 ``pt.DCCM_FDATA_WIDTH`` 决定。

§4.3  ICCM pins
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：LEC shim 把 ICCM 地址、ECC correction 状态、读写使能、写入大小、写数据与
读数据作为 module pins 暴露。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L73-L85``）：

.. code-block:: systemverilog

      output logic [pt.ICCM_BITS-1:1]  iccm_rw_addr,
      output logic [pt.NUM_THREADS-1:0]iccm_buf_correct_ecc_thr,
      output logic                     iccm_correction_state,
      output logic                     iccm_stop_fetch,
      output logic                     iccm_corr_scnd_fetch,
      output logic                  ifc_select_tid_f1,
      output logic                  iccm_wren,
      output logic                  iccm_rden,
      output logic [2:0]            iccm_wr_size,
      output logic [77:0]           iccm_wr_data,
   
      input  logic [63:0]           iccm_rd_data,
      input  logic [116:0]          iccm_rd_data_ecc,

**逐段解释** ：

* 第 L73 行：``iccm_rw_addr`` 是 ICCM 读写地址，宽度为 ``pt.ICCM_BITS-1:1``。
* 第 L74-L77 行：``iccm_buf_correct_ecc_thr``、``iccm_correction_state``、
  ``iccm_stop_fetch`` 和 ``iccm_corr_scnd_fetch`` 都以 ICCM correction/fetch 控制语义命名。
* 第 L78-L82 行：``ifc_select_tid_f1``、``iccm_wren``、``iccm_rden``、
  ``iccm_wr_size`` 和 ``iccm_wr_data`` 从 core 侧输出。
* 第 L84-L85 行：``iccm_rd_data`` 为 64-bit，``iccm_rd_data_ecc`` 为 117-bit，均为
  memory 侧输入。

**接口关系** ：

* **被调用** ：formal/LEC wrapper 边界观察这些 pins。
* **调用** ：无。
* **共享状态** ：pin 宽度由 ``pt.ICCM_BITS``、``pt.NUM_THREADS`` 和显式位宽决定。

§4.4  clock override 与 ECC disable pins
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：LEC shim 顶层暴露 DCCM/ICM/BTB clock override 以及 core ECC disable 控制。

**关键代码** （``rtl/lec_shim/eh2_veer_lec_pack.sv:L33-L38``）：

.. code-block:: systemverilog

      output logic                 dccm_clk_override,
      output logic                 icm_clk_override,
      output logic                 dec_tlu_core_ecc_disable,
      output logic                 btb_clk_override,
   
      output logic [pt.NUM_THREADS-1:0] dec_tlu_mhartstart,

**逐段解释** ：

* 第 L33 行：``dccm_clk_override`` 独立暴露 DCCM clock override。
* 第 L34 行：``icm_clk_override`` 以 ICM 命名暴露，覆盖 ICCM/ICache 相关 memory clock
  override 主题。
* 第 L35 行：``dec_tlu_core_ecc_disable`` 暴露 core ECC disable 控制。
* 第 L36-L38 行：``btb_clk_override`` 和 ``dec_tlu_mhartstart`` 也在同一段端口中暴露。

**接口关系** ：

* **被调用** ：formal property 检查这些 override/disable 信号不是 unknown。
* **调用** ：无。
* **共享状态** ：这些是 wrapper 输出 pins。

§5  TB top 中的内部 memory 使用方式
--------------------------------------------------------------------------------

§5.1  TB 架构注释中的 ``eh2_mem``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB top 文件头记录 DUT wrapper 内部包含 ``eh2_mem``，并在 DUT 外侧连接
AXI4 行为内存模型。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L8-L16``）：

.. code-block:: systemverilog

   // Architecture:
   //   core_eh2_tb_top
   //     +-- eh2_veer_wrapper (DUT)
   //     |     +-- dmi_wrapper (JTAG-to-DMI bridge)
   //     |     +-- eh2_veer (core)
   //     |     +-- eh2_mem (internal memory: DCCM/ICCM/ICache)
   //     +-- axi4_slave_mem (LSU memory - data)
   //     +-- axi4_slave_mem (IFU memory - instruction)
   //     +-- axi4_slave_mem (SB memory - debug system bus)

**逐段解释** ：

* 第 L8-L13 行：注释把 DUT wrapper 内部结构写成 ``dmi_wrapper``、``eh2_veer`` 和
  ``eh2_mem``，其中 ``eh2_mem`` 标注为内部 memory：DCCM/ICCM/ICache。
* 第 L14-L16 行：DUT 外侧还有三个 ``axi4_slave_mem``，分别对应 LSU data、IFU
  instruction 和 SB debug system bus。

**接口关系** ：

* **被调用** ：仿真 elaboration 使用 TB top；该片段本身是架构注释。
* **调用** ：无。
* **共享状态** ：说明内部 tightly coupled memories 与外部 AXI4 行为内存并存。

§5.2  external memory packet tie-off
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：TB top 把 DCCM、ICCM、BTB、I-cache data/tag 的 external memory packets
绑为 ``'0``，源码注释写明使用 internal memories。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L361-L372``）：

.. code-block:: systemverilog

       // Clock enables
       .lsu_bus_clk_en    (lsu_bus_clk_en),
       .ifu_bus_clk_en    (ifu_bus_clk_en),
       .dbg_bus_clk_en    (dbg_bus_clk_en),
       .dma_bus_clk_en    (dma_bus_clk_en),
   
       // External memory packets (tied off - internal memories used)
       .dccm_ext_in_pkt   ('0),
       .iccm_ext_in_pkt   ('0),
       .btb_ext_in_pkt    ('0),
       .ic_data_ext_in_pkt('0),
       .ic_tag_ext_in_pkt ('0),

**逐段解释** ：

* 第 L361-L365 行：DUT 端口接收 LSU、IFU、debug 和 DMA bus clock enable。
* 第 L367 行：注释明确说明 external memory packets 被 tied off，原因是使用 internal
  memories。
* 第 L368-L372 行：``dccm_ext_in_pkt``、``iccm_ext_in_pkt``、``btb_ext_in_pkt``、
  ``ic_data_ext_in_pkt`` 和 ``ic_tag_ext_in_pkt`` 都接 ``'0``。

**接口关系** ：

* **被调用** ：DUT wrapper 端口映射。
* **调用** ：无。
* **共享状态** ：基础 UVM TB 不通过这些 external packet 注入 memory test 控制。

§6  formal property 中的 DCCM/ICCM 检查
--------------------------------------------------------------------------------

§6.1  formal bind 模块接收的 DCCM/ICCM pins
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_veer_sva`` 接收 DCCM/ICCM pins 作为 property 输入，并在同一模块中
引用内部层级信号进行一致性检查。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L79-L95``）：

.. code-block:: systemverilog

     // DCCM
     input logic dccm_wren,
     input logic dccm_rden,
     input logic [pt.DCCM_BITS-1:0] dccm_wr_addr_lo,
   
     // ICCM
     input logic                    iccm_wren,
     input logic                    iccm_rden,
     input logic [pt.ICCM_BITS-1:1] iccm_rw_addr,
   
     // Clock overrides
     input logic dccm_clk_override,
     input logic icm_clk_override,
     input logic btb_clk_override,
   
     // ECC disable
     input logic dec_tlu_core_ecc_disable,

**逐段解释** ：

* 第 L79-L83 行：formal 模块接收 ``dccm_wren``、``dccm_rden`` 和
  ``dccm_wr_addr_lo``。
* 第 L84-L87 行：formal 模块接收 ``iccm_wren``、``iccm_rden`` 和 ``iccm_rw_addr``。
* 第 L89-L95 行：formal 模块还接收 DCCM/ICM/BTB clock override 和 ECC disable。

**接口关系** ：

* **被调用** ：formal bind/top 将 DUT pins 接入该 SVA 模块。
* **调用** ：assert property 在仿真/formal 引擎中求值。
* **共享状态** ：property 使用这些输入和内部层级引用。

§6.2  DCCM/ICCM mutual exclusion 与 known 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``eh2_veer_sva`` 的 Category 9 检查 DCCM 写读控制互斥、ICCM wrapper pins 与
内部 IFU memory control 一致，以及写地址不为 unknown。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L279-L298``）：

.. code-block:: systemverilog

     // =========================================================================
     // Category 9: DCCM/ICCM mutual exclusion (4 assertions)
     // =========================================================================
     a_dccm_wr_rd_mutex: assert property (@(posedge clk) disable iff (!rst_l)
       !(lsu.dccm_ctl.lsu_dccm_wren_spec_dc1 &&
         lsu.dccm_ctl.lsu_dccm_rden_dc1)
     );
   
     a_iccm_wr_rd_mutex: assert property (@(posedge clk) disable iff (!rst_l)
       (iccm_wren == ifu.mem_ctl.iccm_wren) &&
       (iccm_rden == ifu.mem_ctl.iccm_rden)
     );

**逐段解释** ：

* 第 L279-L284 行：``a_dccm_wr_rd_mutex`` 检查 ``lsu.dccm_ctl.lsu_dccm_wren_spec_dc1``
  与 ``lsu.dccm_ctl.lsu_dccm_rden_dc1`` 不能同时为 1。
* 第 L287-L290 行：``a_iccm_wr_rd_mutex`` 检查外部输入 ``iccm_wren/rden`` 与内部
  ``ifu.mem_ctl.iccm_wren/rden`` 一致。
* 第 L292-L298 行：``a_dccm_wr_addr_known`` 在 ``dccm_wren`` 时要求
  ``dccm_wr_addr_lo`` 不是 unknown；``a_iccm_addr_known`` 在 ``iccm_wren`` 时要求
  ``iccm_rw_addr`` 不是 unknown。

**接口关系** ：

* **被调用** ：IFV formal run 证明这些 property。
* **调用** ：SystemVerilog assertion。
* **共享状态** ：读取 DUT 内部层级 ``lsu.dccm_ctl``、``ifu.mem_ctl`` 以及 SVA 输入 pins。

§6.3  clock override 与 ECC disable known 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：formal property 检查 clock override 和 ECC disable 控制不为 unknown。

**关键代码** （``dv/formal/eh2_veer_sva.sv:L341-L358``）：

.. code-block:: systemverilog

     // =========================================================================
     // Category 13: Clock-gate override properties
     // =========================================================================
     a_dccm_clk_override_known: assert property (@(posedge clk) disable iff (!rst_l)
       !$isunknown(dccm_clk_override)
     );
   
     a_icm_clk_override_known: assert property (@(posedge clk) disable iff (!rst_l)
       !$isunknown(icm_clk_override)
     );

**逐段解释** ：

* 第 L341-L346 行：``a_dccm_clk_override_known`` 要求 ``dccm_clk_override`` 不为 unknown。
* 第 L348-L350 行：``a_icm_clk_override_known`` 要求 ``icm_clk_override`` 不为 unknown。
* 第 L352-L353 行：``a_btb_clk_override_known`` 对 BTB clock override 做同类检查。
* 第 L356-L358 行：``a_ecc_disable_known`` 要求 ``dec_tlu_core_ecc_disable`` 不为 unknown。

**接口关系** ：

* **被调用** ：formal run 证明这些 known property。
* **调用** ：SystemVerilog assertion。
* **共享状态** ：读取 SVA 输入 pins。

§6.4  LSU formal property 中的 DCCM 数据稳定性
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：独立 LSU property 文件抽象出 DCCM read valid/data 输入，并检查 valid 后一拍
读数据稳定。

**关键代码** （``dv/formal/properties/eh2_lsu_assert.sv:L39-L52``）：

.. code-block:: systemverilog

     // --- DCCM signals ---
     input logic        dccm_read_valid,
     input logic [31:0] dccm_read_data,
   
     // --- AMO signals ---
     input logic        amo_active,
     input logic [31:0] amo_read_data,
     input logic [31:0] amo_write_data,
     input logic        amo_complete,
   
     // --- Exception signals ---
     input logic        lsu_exception,
     input logic [3:0]  lsu_exc_cause

**逐段解释** ：

* 第 L39-L41 行：该 property 模块把 DCCM read valid 和 32-bit read data 作为抽象输入。
* 第 L43-L47 行：同一模块还接收 AMO 相关输入。
* 第 L49-L52 行：异常输入用于后续 bus error property。

**关键代码** （``dv/formal/properties/eh2_lsu_assert.sv:L88-L97``）：

.. code-block:: systemverilog

     // ========================================================================
     // Property 4: DCCM read data stable for one cycle after valid
     // ========================================================================
     property p_dccm_read_data_stable;
       @(posedge clk) disable iff (!rst_l)
       (dccm_read_valid)
       |=>
       ($stable(dccm_read_data));
     endproperty
     a_dccm_read_data_stable: assert property(p_dccm_read_data_stable);

**逐段解释** ：

* 第 L88-L91 行：property 名称和注释都指向 DCCM read data stable 检查。
* 第 L92-L95 行：当 ``dccm_read_valid`` 为 1，下一拍要求 ``dccm_read_data`` 稳定。
* 第 L97 行：``a_dccm_read_data_stable`` 绑定该 property。

**接口关系** ：

* **被调用** ：formal property harness 可实例化该 LSU assertion 模块。
* **调用** ：SystemVerilog assertion。
* **共享状态** ：读取抽象 LSU/DCCM 输入。

§6.5  PMP formal property 中的 DCCM region 例外
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：PMP property 文件把 DCCM/PIC internal region 与 unmapped external address
区分开，并检查 DCCM region 中的 AMO 不产生地址 fault。

**关键代码** （``dv/formal/properties/eh2_pmp_assert.sv:L61-L71``）：

.. code-block:: systemverilog

     // ========================================================================
     // Property 2: DCCM/PIC region addresses never trigger MPU fault
     // ========================================================================
     property p_internal_region_no_fault;
       @(posedge clk) disable iff (~rst_l)
         ((start_addr_in_dccm_region_dc2 || start_addr_in_pic_region_dc2) &&
           lsu_pkt_dc2_valid && !lsu_pkt_dc2_dma)
           |-> !mpu_access_fault_dc2;
     endproperty
     a_internal_region_no_fault: assert property (p_internal_region_no_fault)
       else $error("FORMAL FAIL: MPU fault in internal region");

**逐段解释** ：

* 第 L61-L68 行：当起始地址位于 DCCM 或 PIC region，且 LSU packet valid、非 DMA 时，
  property 要求 ``mpu_access_fault_dc2`` 为 0。
* 第 L70-L71 行：assert 失败时报告 ``FORMAL FAIL: MPU fault in internal region``。

**关键代码** （``dv/formal/properties/eh2_pmp_assert.sv:L86-L97``）：

.. code-block:: systemverilog

     // ========================================================================
     // Property 4: AMO in DCCM region does not cause addr fault
     //
     // AMO operations to valid DCCM addresses pass addrcheck.
     // ========================================================================
     property p_atomic_in_dccm_no_fault;
       @(posedge clk) disable iff (~rst_l)
         (lsu_pkt_dc2_valid && lsu_pkt_dc2_atomic && addr_in_dccm_dc2)
           |-> !amo_access_fault_dc2;

**逐段解释** ：

* 第 L86-L94 行：当 LSU packet valid、是 atomic 且 ``addr_in_dccm_dc2`` 为 1 时，
  property 要求 ``amo_access_fault_dc2`` 为 0。
* 第 L96-L97 行：assert 失败时报告 ``FORMAL FAIL: AMO in DCCM wrongly faulted``。

**接口关系** ：

* **被调用** ：formal property harness 使用这些 PMP assertions。
* **调用** ：SystemVerilog assertion 与 ``$error``。
* **共享状态** ：读取 DCCM/PIC region 判定、LSU packet、PMP fault 和 AMO fault 信号。

§7  directed ASM 覆盖的访问模式
--------------------------------------------------------------------------------

§7.1  DCCM byte 与 halfword 符号扩展
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``directed_toggle_dccm_walk.S`` 覆盖 byte/halfword store 后的有符号和无符号
load 行为。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S:L19-L43``）：

.. code-block:: bash

       li      t1, 0x000000FE
       sb      t1, 4(t0)
       lbu     t2, 4(t0)
       li      t3, 0xFE
       bne     t2, t3, fail
       lb      t2, 4(t0)
       li      t3, 0xFFFFFFFE
       bne     t2, t3, fail
   
       li      t1, 0x00001234
       sh      t1, 8(t0)
       lhu     t2, 8(t0)
       li      t3, 0x1234
       bne     t2, t3, fail

**逐段解释** ：

* 第 L19-L26 行：测试写入 byte ``0xFE``，``lbu`` 期望 ``0xFE``，``lb`` 期望
  ``0xFFFFFFFE``。
* 第 L28-L34 行：测试写入 halfword ``0x1234``，``lhu`` 和 ``lh`` 都期望 ``0x1234``。
* 第 L36-L43 行：测试写入 halfword ``0x8001``，``lhu`` 期望 ``0x8001``，``lh`` 期望
  ``0xFFFF8001``。

**接口关系** ：

* **被调用** ：directed regression 执行该 ASM。
* **调用** ：RISC-V ``sb``、``lb``、``lbu``、``sh``、``lh``、``lhu``。
* **共享状态** ：DCCM 地址以 ``t0`` 为基址，失败跳转到 ``fail``。

§7.2  DCCM word toggle 与 walking bit
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：同一 ASM 覆盖 word store/load、walking one 和 walking zero 模式。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S:L45-L86``）：

.. code-block:: bash

       li      t1, 0xAAAAAAAA
       sw      t1, 16(t0)
       lw      t2, 16(t0)
       bne     t2, t1, fail
       li      t1, 0x55555555
       sw      t1, 16(t0)
       lw      t2, 16(t0)
       bne     t2, t1, fail
   
       li      t1, 0xFF00FF00
       sw      t1, 20(t0)
       lw      t2, 20(t0)
       bne     t2, t1, fail

**逐段解释** ：

* 第 L45-L52 行：测试在 ``16(t0)`` 先写 ``0xAAAAAAAA`` 再写 ``0x55555555``，每次都用
  ``lw`` 比较。
* 第 L54-L61 行：测试在 ``20(t0)`` 写 ``0xFF00FF00`` 和 ``0x00FF00FF``，覆盖交错 byte
  模式。
* 第 L63-L72 行：``walk_one_loop`` 从 bit 31 开始每次减 4，写入并读回单 bit 模式。
* 第 L74-L86 行：``walk_zero_loop`` 从 bit 0 开始每次加 4，写入反相单 bit 模式并读回。

**接口关系** ：

* **被调用** ：directed regression 执行。
* **调用** ：RISC-V ``sw``、``lw``、``sll``、``not``、``bgez``、``blt``。
* **共享状态** ：``t0`` 保持 DCCM 基址，``t2`` 到 ``t5`` 用作比较寄存器。

§7.3  mailbox pass/fail
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：两个 directed ASM 都通过 mailbox 地址 ``0xD0580000`` 上报 pass/fail。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S:L98-L109``）：

.. code-block:: bash

   pass:
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)
   done:
       j       done
   
   fail:
       li      t0, 0xD0580000
       li      t1, 0x01
       sw      t1, 0(t0)
       j       done

**逐段解释** ：

* 第 L98-L101 行：pass 路径向 ``0xD0580000`` 写 ``0xFF``。
* 第 L102-L103 行：pass 后进入自旋。
* 第 L105-L109 行：fail 路径向同一地址写 ``0x01``，然后进入同一个 ``done`` 自旋。

**接口关系** ：

* **被调用** ：TB mailbox monitor 检测该地址写入。
* **调用** ：RISC-V ``sw``。
* **共享状态** ：mailbox 地址约定同时出现在 TB top 文件头注释中。

§8  参考资料
--------------------------------------------------------------------------------

* :file:`/home/host/eh2-veri/syn/include/eh2_param.vh` — 当前参数集中的 DCCM/ICCM 数值。
* :file:`/home/host/eh2-veri/rtl/lec_shim/eh2_veer_lec_pack.sv` — LEC-only wrapper 暴露的 DCCM/ICCM pins。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` — TB 中 internal memory packet tie-off 与 mailbox 约定。
* :file:`/home/host/eh2-veri/dv/formal/eh2_veer_sva.sv` — DCCM/ICCM mutual exclusion、known 和 clock override property。
* :file:`/home/host/eh2-veri/dv/formal/properties/eh2_lsu_assert.sv` — DCCM read data stable property。
* :file:`/home/host/eh2-veri/dv/formal/properties/eh2_pmp_assert.sv` — DCCM/PIC internal region 与 AMO DCCM property。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S` — DCCM byte/halfword/word directed stimulus。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_iccm_eccerror.S` — ICCM fetch/ECC error directed stimulus shell。
* :ref:`appendix_a_rtl/mem` — MEM wrapper 字典。
* :ref:`formal_flow` — IFV formal 执行流程。
