.. _tb_top:
.. _05_verification_arch/tb_top:

顶层 Testbench — 详细参考
==========================

:status: draft
:source: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv, dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
-----------------

读懂本章，你需要先知道两件事：RTL 顶层模块通过端口和外界连接，UVM testbench
通过 virtual interface 驱动和采样这些端口。如果你只懂 C 语言，先把
:ref:`getting_started` 跑通，再读本章；不要一开始就跳进 UVM class 继承树。

建议前置知识：

* 基础 SystemVerilog：``module``、``interface``、``logic``、``initial``；
* 基础 UVM：知道 ``run_test()`` 会启动 UVM test，``uvm_config_db`` 用来传对象句柄；
* :ref:`pipeline` — 理解 DUT 内部至少有 IFU/DEC/EXU/LSU 四类主要路径；
* :ref:`quickstart` — 知道 ``make smoke`` 最终会启动 ``core_eh2_tb_top``。

学完本章你能：

1. 在 :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` 中找到 DUT 实例、时钟复位和
   ``run_test()`` 入口；
2. 解释 TB top 为什么要实例化 AXI4 memory model、IRQ/JTAG/Halt-Run/trace/probe/RVFI/fcov
   等 interface；
3. 说出 ``uvm_config_db::set`` 如何把 virtual interface 传给 env 和 agent；
4. 遇到 smoke hang、mailbox 未 PASS、interface get 失败或 waveform 缺信号时，
   知道应先检查 TB top 的哪一类连接。

§1  本章导读
-------------

本章详细讲解 EH2 UVM 验证平台的**顶层 Testbench** 。
``core_eh2_tb_top.sv`` （1,155 行）是仿真世界的硬件边界——它实例化 DUT
（``eh2_veer_wrapper`` ）、3 个 AXI4 行为级内存模型、时钟/复位生成逻辑，
并通过 ``uvm_config_db::set`` 将 12 个 virtual interface 注入 UVM 组件树。
理解 TB top 的连接关系是调试任何仿真问题的前提。

阅读本章你将学到：

* TB top 的完整实例化清单（DUT + 3×AXI4 mem + 时钟复位 + UVM test）
* 12 个 virtual interface 的名称、类型、set/get 路径
* 221 行 DUT 信号连线的组织结构（``core_eh2_dut_signals.svh`` ）
* Mailbox PASS/FAIL 检测机制（地址 0xD058_0000）
* Cosim 复位重初始化流程
* Config DB 的完整 set 表（哪个 interface 在哪个 initial 块注入）

§2  模块层次（TB top 实例化树）
--------------------------------

.. code-block:: text

   core_eh2_tb_top (顶层)
   ├── dut: eh2_veer_wrapper_rvfi (DUT, 含 RVFI adapter)
   │   ├── dmi_wrapper (JTAG→DMI 桥)
   │   ├── eh2_veer (Core: IFU+DEC+EXU+LSU)
   │   ├── eh2_mem (DCCM+ICCM SRAM)
   │   ├── eh2_pic_ctrl (中断控制器)
   │   ├── eh2_dma_ctrl (DMA 控制器)
   │   └── eh2_dbg (调试控制器)
   ├── lsu_axi_slave_mem (LSU 数据存储，行为模型)
   ├── ifu_axi_slave_mem (IFU 指令存储，行为模型)
   ├── sb_axi_slave_mem (SB 系统总线存储)
   ├── 时钟生成: core_clk (100MHz) + rst_l + porst_l
   ├── 12 个 virtual interface 实例
   └── UVM test (通过 run_test() 启动)

§3  时钟与复位
---------------

.. code-block:: systemverilog

   bit core_clk;
   initial begin
     core_clk = 0;
     forever #5 core_clk = ~core_clk;  // 100MHz (10ns 周期)
   end

   // 复位序列 (在 UVM test 的 initial 块中控制):
   // 1. rst_l = 0 (10 周期低有效复位)
   // 2. rst_l = 1 (释放复位)
   // 3. 等待 DUT 稳定后启动 UVM test

§4  DUT 信号连线（``core_eh2_dut_signals.svh`` ，221 行）
----------------------------------------------------------

按功能分组声明的 ``logic`` 信号：

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - 信号组
     - 包含信号
   * - **复位/引导**
     - ``rst_l``, ``porst_l``, ``rst_vec[31:1]``
   * - **NMI**
     - ``nmi_int``, ``nmi_vec[31:1]``
   * - **JTAG 5-pin**
     - ``tck``, ``tms``, ``tdi``, ``tdo``, ``trst_n``
   * - **Trace 输出**
     - ``trace_rv_trace_pkt[N-1:0]`` （每线程的结构体）
   * - **调试控制**
     - ``mpc_debug_halt_req/ack``, ``mpc_debug_run_req/ack``, ``dbg_halt_req``, ``dbg_resume_req``
   * - **性能计数器**
     - ``exu_pmu_i0/i1_br_misp/ataken/pc4``
   * - **中断**
     - ``timer_int``, ``soft_int``, ``mexintpend``, ``pic_claimid[7:0]``, ``pic_pl[3:0]``, ``mhwakeup``
   * - **时钟使能**
     - ``dec_tlu_*_clk_override`` （8 个域的时钟 override）
   * - **AXI4 IFU**
     - ``ifu_axi_aw*``, ``ifu_axi_w*``, ``ifu_axi_b*``, ``ifu_axi_ar*``, ``ifu_axi_r*`` （完整 5 通道）
   * - **AXI4 LSU**
     - ``lsu_axi_aw*``, ``lsu_axi_w*``, ``lsu_axi_b*``, ``lsu_axi_ar*``, ``lsu_axi_r*``
   * - **AXI4 SB**
     - ``sb_axi_aw*``, ``sb_axi_w*``, ``sb_axi_b*``, ``sb_axi_ar*``, ``sb_axi_r*``
   * - **AXI4 DMA**
     - ``dma_axi_aw*``, ``dma_axi_w*``, ``dma_axi_b*``, ``dma_axi_ar*``, ``dma_axi_r*``
   * - **PIC 外部中断**
     - ``extintsrc_req[PIC_TOTAL_INT_PLUS1-1:0]`` （127 路）
   * - **PIC 内存接口**
     - ``picm_wren/rden/rdaddr/wraddr/wr_data/rd_data``

§5  Config DB 注入表
---------------------

TB top 在 ``initial`` 块中通过 ``uvm_config_db::set`` 注入以下 virtual interface：

.. list-table::
   :header-rows: 1
   :widths: 30 40 30

   * - Interface
     - 类型
     - UVM 消费者
   * - ``"*.ifu_axi_agent.*"`` → ``vif``
     - ``axi4_intf #(4)``
     - ``axi4_agent`` (IFU)
   * - ``"*.lsu_axi_agent.*"`` → ``vif``
     - ``axi4_intf #(4)``
     - ``axi4_agent`` (LSU)
   * - ``"*.sb_axi_agent.*"`` → ``vif``
     - ``axi4_intf #(4)``
     - ``axi4_agent`` (SB)
   * - ``"*.dma_axi_agent.*"`` → ``vif``
     - ``axi4_intf #(4)``
     - ``axi4_agent`` (DMA)
   * - ``"*.trace_agent.*"`` → ``vif``
     - ``eh2_trace_intf``
     - ``eh2_trace_monitor``
   * - ``"*.irq_agent.*"`` → ``vif``
     - ``eh2_irq_intf``
     - ``eh2_irq_driver/monitor``
   * - ``"*.jtag_agent.*"`` → ``vif``
     - ``eh2_jtag_intf``
     - ``eh2_jtag_driver/monitor``
   * - ``"*.halt_run_agent.*"`` → ``vif``
     - ``eh2_halt_run_intf``
     - ``eh2_halt_run_driver``
   * - ``"*.env.*"`` → ``probe_vif``
     - ``eh2_dut_probe_if``
     - ``eh2_dut_probe_monitor``
   * - ``"*.env.*"`` → ``csr_vif``
     - ``eh2_csr_if``
     - CSR access
   * - ``"*.env.*"`` → ``fcov_vif``
     - ``eh2_fcov_if``
     - Functional coverage
   * - ``"*.env.*"`` → ``rvfi_vif``
     - ``eh2_rvfi_if``
     - RVFI adapter
   * - ``"*.env.*"`` → ``instr_monitor_vif``
     - ``eh2_instr_monitor_if``
     - Instruction monitor

§6  Mailbox PASS/FAIL 判定
----------------------------

.. code-block:: systemverilog

   assign mailbox_write = lsu_axi_awvalid && lsu_axi_awready;
   assign mailbox_addr  = lsu_axi_awaddr;
   assign mailbox_data  = lsu_axi_wdata;

   always @(posedge core_clk) begin
     if (mailbox_write && mailbox_addr == 32'hD058_0000) begin
       if (mailbox_data[7:0] == 8'hFF) -> mailbox_test_pass;
       else if (mailbox_data[7:0] == 8'h01) -> mailbox_test_fail;
       else $write("%c", mailbox_data[7:0]); // 控制台输出
     end
   end

- 地址 ``0xD058_0000`` 是 EH2 的"邮箱"地址
- 写 ``0xFF`` → 测试 PASS
- 写 ``0x01`` → 测试 FAIL
- 其他值 → ASCII 字符（控制台输出，通常为测试程序打印的消息）
- 30 分钟超时保护：如果仿真在 30 分钟内未完成，强制超时

§7  Cosim 复位监控
-------------------

TB top 在 ``rst_l`` 释放时通知 cosim agent 重新初始化 Spike ISS：

1. ``rst_l`` 上升沿 → ``rst_negedge`` 事件触发
2. Cosim agent 的 ``reset()`` 被调用
3. ``riscv_cosim_init()`` DPI 函数重新初始化 Spike
4. 预注册的 28 个 EH2 自定义 CSR 重新加载
5. 测试程序重新加载到 Spike 的内存空间

§8  典型调试场景
-----------------

**场景 1：mailbox 未触发（测试 hang）**
- 检查波形：``mailbox_write`` 是否有脉冲？地址是否为 ``0xD058_0000``？
- 检查 DUT 是否卡在死循环（看 IFU 的 fetch PC 是否重复）
- 检查 cosim scoreboard 的 log：是否有未解决的 mismatch？

**场景 2：AXI4 总线超时**
- 检查 ``*_axi_*ready`` 信号是否 stuck 在 0
- 检查 AXI4 slave mem 的内部状态（``lsu_axi_slave_mem`` 是否响应）

§8  完整 DUT 端口连接表
-------------------------

以下将 :file:`core_eh2_dut_signals.svh` 中 221 行信号连线的完整内容按功能展开：

.. list-table:: DUT → TB 信号连接（部分关键信号）
   :header-rows: 1
   :widths: 30 15 55

   * - 信号
     - 方向
     - 连接目标
   * - ``rst_l``
     - TB→DUT
     - DUT 复位（低有效，10 周期脉冲）
   * - ``rst_vec[31:1]``
     - TB→DUT
     - 复位向量（启动 PC）
   * - ``nmi_int`` / ``nmi_vec[31:1]``
     - TB→DUT
     - NMI 引脚 + 向量
   * - ``tck/tms/tdi/tdo/trst_n``
     - TB↔DUT
     - JTAG 5-pin → ``dmi_wrapper``
   * - ``trace_rv_trace_pkt[N-1:0]``
     - DUT→TB
     - Trace 输出 → ``eh2_trace_intf`` → trace agent
   * - ``mpc_debug_halt_req/ack``
     - TB↔DUT
     - MPC halt 握手
   * - ``timer_int/soft_int``
     - TB→DUT
     - 定时器/软件中断
   * - ``mexintpend/pic_claimid/pic_pl``
     - DUT→TB
     - PIC 中断输出 → ``eh2_irq_intf``
   * - ``extintsrc_req[126:0]``
     - TB→DUT
     - 127 路外部中断输入
   * - ``ifu_axi_*``
     - DUT↔TB
     - IFU AXI4 → ``ifu_axi_slave_mem``
   * - ``lsu_axi_*``
     - DUT↔TB
     - LSU AXI4 → ``lsu_axi_slave_mem``
   * - ``sb_axi_*``
     - DUT↔TB
     - SB AXI4 → ``sb_axi_slave_mem``
   * - ``dma_axi_*``
     - DUT↔TB
     - DMA AXI4 → 外部 master 模型
   * - ``*_clk_override`` (8 个)
     - DUT→TB
     - 时钟门控 override（来自 mcgc CSR）

§9  仿真波形调试指南
---------------------

**关键波形信号（推荐在 Verdi/DVE 中添加到 wave window）：**

1. ``core_clk`` + ``rst_l`` ：时钟复位基准
2. ``lsu_axi_awaddr`` + ``lsu_axi_wdata`` ：Mailbox 写入检测
3. ``trace_rv_trace_pkt[0].trace_rv_i_valid_ip`` ：指令退休
4. ``dec_tlu_flush_lower_wb`` ：流水线 flush
5. ``exu_flush_final`` + ``exu_flush_path_final`` ：分支预测失误
6. ``mexintpend`` + ``dec_tlu_meicurpl`` ：中断状态
7. ``cosim_scoreboard.mismatch_count`` ：Cosim 比对错误计数

**常用 Verdi 命令：**
- ``get signals -module core_eh2_tb_top``
- ``add wave -recursive dut.veer.dec``
- ``fsdbDumpvars 0 core_eh2_tb_top``

§10  参考资料
-------------

* :ref:`env` — UVM Environment（config_db 的消费者）
* :ref:`appendix_b_uvm/tb` — TB 文件附录
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`

§11  当前 VCS 主线连接语义
---------------------------

``core_eh2_tb_top`` 是 EH2 UVM 平台的硬件边界。它把上游
``eh2_veer_wrapper`` 放入仿真世界，同时提供 UVM 能消费的 virtual interface、
行为级 AXI4 memory、mailbox 结束条件、trace/RVFI sidecar 和 coverage interface。
当前主线假设是 VCS；NC/Incisive 只用于 ``make smoke|regress SIMULATOR=nc WAVES=1``
单测波形调试，不作为 sign-off 或覆盖率数据来源。

.. code-block:: text

   core_eh2_tb_top
      |
      +-- clock/reset
      +-- eh2_veer_wrapper dut
      |     +-- EH2 core
      |     +-- DMI/JTAG bridge
      |     +-- ICCM/DCCM/ICache wrapper
      |
      +-- lsu_mem / ifu_mem / sb_mem
      +-- axi4_intf: lsu / ifu / sb
      +-- trace_intf + dut_probe_intf + rvfi_intf
      +-- irq_intf + jtag_intf + halt_run_vif + fetch_en_intf
      +-- eh2_fcov_if + eh2_pmp_fcov_if
      +-- uvm_config_db::set(...)

.. list-table:: TB top 对 UVM 的接口发布
   :header-rows: 1
   :widths: 24 30 46

   * - 字段名
     - virtual interface 类型
     - 消费者
   * - ``tb_vif``
     - ``core_eh2_tb_intf``
     - base test、binary loader、mailbox/host memory helper
   * - ``vif``（``*lsu_agent*``）
     - ``axi4_intf#(`RV_LSU_BUS_TAG)``
     - LSU AXI4 monitor、cosim d-side notification
   * - ``vif``（``*ifu_agent*``）
     - ``axi4_intf#(`RV_IFU_BUS_TAG)``
     - IFU AXI4 monitor、fetch/ICache 相关观察
   * - ``vif``（``*sb_agent*``）
     - ``axi4_intf#(`RV_SB_BUS_TAG)``
     - debug system-bus AXI4 monitor
   * - ``vif``（``*trace_monitor*``）
     - ``eh2_trace_intf``
     - retire trace monitor
   * - ``probe_vif``
     - ``eh2_dut_probe_if``
     - trace monitor、DUT probe monitor、cosim scoreboard reset monitor
   * - ``irq_vif``
     - ``eh2_irq_intf``
     - IRQ agent driver
   * - ``jtag_vif``
     - ``eh2_jtag_intf``
     - JTAG agent driver
   * - ``halt_run_vif``
     - ``eh2_halt_run_intf``
     - Halt/Run agent driver 和 monitor
   * - ``fcov_vif``
     - ``eh2_fcov_if``
     - coverage-aware tests 或 debug hooks
   * - ``rvfi_vif``
     - ``eh2_rvfi_if``
     - RVFI smoke/adapter 检查路径

关键代码（AXI4 interface 实例和 DUT 线网映射）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 602-751
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:602-751

逐段解释：

* 第 602-609 行实例化 LSU、IFU、SB 三组 AXI4 interface，并使用 DUT 实际 tag width，
  避免 ID 宽度被截断。
* 第 613-735 行将 DUT AXI4 wires 映射进 interface。UVM monitor 只看 interface，
  不直接读取 DUT wire。
* 第 738-751 行把 EH2 trace packet 映射到 ``eh2_trace_intf``，这是 cosim
  scoreboard 的退休指令主输入。

§12  Trace、RVFI 与 coverage sidecar
-------------------------------------

TB top 中 trace、RVFI 和 coverage 是并列 sidecar。trace 是当前 cosim 主路径；
RVFI adapter 用于 smoke/形式化友好的等价观察；coverage interface 使用层次引用
采样微架构信号。三者都不改变 DUT 输入输出协议。

关键代码（RVFI、coverage 和 config_db 发布）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 756-1152
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:756-1152

逐段解释：

* 第 756-819 行实例化 ``eh2_rvfi_if`` 与 ``eh2_veer_wrapper_rvfi``，把 trace/RVFI
  equivalent 信息转换为 RVFI 风格字段。
* 第 951-1038 行实例化 ``eh2_fcov_if``，直接引用 DEC/TLU/LSU/IFU 内部信号。
* 第 1041-1062 行实例化 ``eh2_pmp_fcov_if``，默认 ``PMPEnable=0``，保留 PMP-enabled
  配置的覆盖率 scaffold。
* 第 1114-1151 行通过 ``uvm_config_db`` 发布所有 virtual interface，是 env 和 agent
  能够工作的重要契约。

.. warning::

   ``uvm_config_db`` 字段名是组件间 ABI。修改 ``jtag_vif``、``halt_run_vif``、
   ``probe_vif`` 或 AXI4 ``vif`` 的路径匹配，会直接导致 agent build/connect phase
   获取 interface 失败。文档、test 和脚本应把这些字段名视为稳定接口。

§13  Mailbox 与结束条件
-----------------------

TB top 的 mailbox 监视器以 LSU AXI4 AW handshake 为地址采样点，以 WDATA bit[7:0]
作为测试状态码。``0xFF`` 表示 PASS，``0x01`` 表示 FAIL，可打印 ASCII 字节直接
输出到仿真日志。该约定服务于 directed ASM、riscv-dv 产物和 smoke 测试，避免 UVM
test 必须理解每个程序的内部控制流。

.. list-table:: Mailbox 约定
   :header-rows: 1
   :widths: 24 24 52

   * - 地址/数据
     - 行为
     - 使用场景
   * - ``0xD058_0000`` / ``0xFF``
     - 触发 ``mailbox_test_pass``
     - smoke、directed、riscv-dv 程序正常结束
   * - ``0xD058_0000`` / ``0x01``
     - 触发 ``mailbox_test_fail``
     - ASM 自检失败或异常路径故意报告失败
   * - ``0xD058_0000`` / printable byte
     - ``$write`` 字符
     - 裸机程序简易 console 输出
   * - 其他地址
     - 不触发结束条件
     - 普通 LSU store 或外设访问

关键代码（mailbox 事件和 reset）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 65-133
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:65-133

§14  与 Ibex 工业实现对照
-------------------------

Ibex 的 top-level testbench 更围绕 core、memory interface、RVFI monitor 和 cosim
agent 展开；EH2 的 TB top 需要额外承载双线程 trace packet、AXI4 LSU/IFU/SB、DMI/JTAG、
PIC、Halt/Run、RVFI adapter、PMP coverage scaffold 和 EH2 custom CSR 观察点。
两者的共同点是：都把 DUT wrapper 与 UVM env 用 virtual interface 解耦，并把 Spike
cosim 放在 UVM scoreboard 侧，而不是把 ISS 逻辑放进 RTL。

.. list-table:: TB top 对照
   :header-rows: 1
   :widths: 26 37 37

   * - 维度
     - Ibex
     - EH2
   * - DUT 入口
     - ``/home/host/ibex/dv/uvm/core_ibex/tb``
     - ``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``
   * - retire 观察
     - RVFI-centered item
     - EH2 trace packet + RVFI adapter sidecar
   * - memory 接口
     - Ibex memory response/request agent
     - LSU/IFU/SB 三组 AXI4 interface + behavioral memory
   * - debug
     - debug request 和 RVFI trap 结合
     - JTAG/DMI、Halt/Run、debug status 和 custom CSR 观察点
   * - coverage
     - Ibex 使用 core-specific cover interfaces 和 VCS coverage scope
     - EH2 使用 ``eh2_fcov_if``、``eh2_pmp_fcov_if`` 和 ``cover.cfg`` DUT-only scope

§15  Sign-off 关联
------------------

TB top 直接影响 2026-05-19 demo 的所有动态 stage：``smoke`` 依赖 mailbox 和 binary
预加载；``directed`` 依赖 AXI4 memory、IRQ/JTAG/Halt-Run 等 stimulus interface；
``riscvdv`` 依赖 early hex load 和 trace/cosim sidecar；``compliance`` 依赖相同的
signature/memory 通道。当前 demo 结果为 9/9 stages PASS、实跑覆盖率 102/104
(98.1%)、LEC 31635/31635 PASS。

.. tip::

   调试 TB top 问题时先区分“DUT 没有响应”和“UVM 没拿到 interface”。前者看
   ``core_clk``、``rst_l``、AXI4 handshake、mailbox；后者看 UVM build/connect
   日志中的 config_db get failure、agent active/passive 配置和 sequencer 句柄。

§16  源码锚点与维护地图
-----------------------

``core_eh2_tb_top.sv`` 很长，但维护时可以按功能锚点定位，而不是从头顺序阅读。下面的
地图把本章涉及的关键区域和维护意图列出来，便于新增 agent、修改 interface 或排查
构建错误时快速落点。

.. list-table:: ``core_eh2_tb_top.sv`` 维护地图
   :header-rows: 1
   :widths: 18 32 50

   * - 行段
     - 主题
     - 维护注意事项
   * - 1-64
     - include/import、module 声明、参数入口
     - package import 顺序影响 UVM class 和 interface 类型可见性
   * - 65-133
     - clock/reset/mailbox 基础逻辑
     - mailbox 约定必须与 ASM runtime 和 scripts log parser 保持一致
   * - 134-601
     - DUT wire 声明与 wrapper 实例
     - 新增 DUT port 时先更新 wire，再更新 interface 映射和 probe/coverage sidecar
   * - 602-751
     - AXI4 interface 映射
     - ID width、data width 和 ready/valid 方向不能由文档推断，必须对照 RTL port
   * - 756-890
     - trace/RVFI/DUT probe 映射
     - cosim 的 debug/NMI/MIP/mcycle 状态来自这里，改动后要跑 cosim smoke
   * - 893-934
     - IRQ、JTAG、Halt/Run interface
     - 主动 stimulus agent 的 pin-level 接线，字段名必须和 driver config_db 一致
   * - 951-1062
     - functional/PMP coverage interface
     - 层次引用容易随 RTL 重构失效，Sphinx literalinclude 只能证明文档引用存在
   * - 1114-1152
     - ``uvm_config_db`` 发布
     - 这是 UVM 组件 ABI，修改字段名会导致 agent build/connect failure

§17  AXI4 memory model 边界
---------------------------

TB top 中的 AXI4 memory model 是行为级从设备，不是被 AXI4 agent driver 替代的完整
UVM slave。这个边界对 cosim 很关键：LSU/IFU/SB 的 ready/valid 响应来自 memory model，
AXI4 agent 默认只做 monitor；只有 error injection 模式下，driver 才通过 sideband
影响 response error。

.. code-block:: text

   DUT LSU AXI4 --------------> axi4_slave_mem
      |                              |
      |                              +--> memory array / ready-valid response
      |
      +--> lsu_axi_intf -----------> axi4_monitor
                                      |
                                      +--> axi4_seq_item
                                      |
                                      +--> cosim scoreboard d-side notification

.. list-table:: Memory model 与 agent 的职责划分
   :header-rows: 1
   :widths: 24 38 38

   * - 行为
     - 归属
     - 验证影响
   * - AXI4 ready/valid 响应
     - TB 行为级 memory
     - 程序能取指、load/store 能完成
   * - Memory array 读写
     - TB 行为级 memory
     - mailbox、signature、external data region 可见
   * - AW/W/AR/R 采样
     - AXI4 monitor
     - 生成 ``axi4_seq_item`` 供 scoreboard 和日志使用
   * - B/R error 覆盖
     - AXI4 driver sideband
     - 负向测试触发 access fault/error path
   * - Spike d-side notify
     - cosim scoreboard
     - store/AMO architectural side effect 与 DUT 对齐

§18  Reset 与二进制加载语义
---------------------------

EH2 TB top 的 reset 不是简单地拉低 ``rst_l``。对动态验证而言，reset 至少牵涉四个
状态域：DUT 状态、行为级 memory 状态、UVM driver 输出和 Spike ISS 状态。TB top
提供 reset pin 和 probe reset 观察点；base test、driver reset phase 和 cosim
scoreboard 再分别完成各自的状态清理。

.. list-table:: Reset 相关状态域
   :header-rows: 1
   :widths: 24 36 40

   * - 状态域
     - 清理/重建位置
     - 失败表现
   * - DUT pipeline/CSR
     - ``rst_l`` / ``porst_l`` 输入
     - PC 不回 reset vector，trace 继续旧路径
   * - UVM stimulus pins
     - agent ``pre_reset_phase`` 或默认 driver 状态
     - reset 释放后第一拍残留 interrupt/halt/debug 请求
   * - Spike ISS
     - cosim scoreboard ``run_reset_monitor``
     - reset 后 PC/GPR/CSR mismatch
   * - binary image
     - base test / cosim binary loader
     - DUT 有程序但 Spike 无程序，或二者 base address 不一致
   * - coverage sampling
     - coverage interface sampling condition
     - reset 周期被误计入 functional bins

.. warning::

   调整 reset sequence 时不要只看 smoke PASS。必须至少覆盖 cosim-enabled smoke 和
   一个含 interrupt/debug 的 directed 场景，因为 Spike re-init、probe reset monitor
   和主动 agent reset 清理都只有在这些场景下才会被真正检验。

§19  Config DB 失败定位
-----------------------

``uvm_config_db`` 失败通常有三类原因：字段名不一致、路径 scope 不匹配、类型不一致。
TB top 页维护时需要把这三类分开记录，因为日志中都可能表现为 “Failed to get virtual
interface”。

.. list-table:: Config DB 失败分类
   :header-rows: 1
   :widths: 24 38 38

   * - 分类
     - 示例
     - 处理方式
   * - 字段名错误
     - 发布 ``halt_run_vif``，driver get ``vif``
     - 统一字段名；不要在 driver 中加 fallback 掩盖 ABI 漂移
   * - 类型错误
     - 发布 ``virtual eh2_irq_intf``，get ``virtual eh2_irq_intf#(...)``
     - 对齐 interface 参数化类型或使用项目已有 typedef/pattern
   * - 路径错误
     - set 到 ``*trace_monitor*``，实际组件名改变
     - 检查 env build 的 component full name
   * - 创建顺序错误
     - scoreboard build 先于 cfg set
     - cfg set 必须在 create 之前完成，见 cosim cfg 注入路径
   * - 多实例冲突
     - 多个 interface 都用 ``"*"`` 和同一字段名
     - 对多实例 agent 使用更窄 scope，例如 ``*lsu_agent*``

§20  NC 波形通道的限定用途
--------------------------

当前手册以 VCS 主线为叙述基准。NC/Incisive 的正确位置是单测波形调试入口，而不是覆盖率或
sign-off 入口。TB top 本身仍可被 NC elaborate，因此在调试波形时可以使用同一套
interface、mailbox 和 DUT wrapper，但结果不应写成 release coverage 数据。

.. code-block:: bash

   make smoke SIMULATOR=nc WAVES=1
   make regress SIMULATOR=nc WAVES=1 TESTLIST=directed_smoke

预期用途：

* 快速查看 ``rst_l``、AXI4、mailbox、trace packet 和 debug/interrupt pin。
* 排查 VCS 不便查看的单个波形场景。
* 验证某个 UVM driver 是否真的驱动了 virtual interface。

不允许的用途：

* 不用 NC/IMC 数据替代 URG dashboard。
* 不把 NC coverage 数字写入 sign-off 表。
* 不把历史 NC 迁移 bug 当作当前平台主线行为。

§21  TB top 变更后的最小回归
-----------------------------

TB top 的改动 blast radius 大。即使只是补一个 config_db 字段，也建议按下面的最小回归
组合验证连接面：

.. code-block:: bash

   make smoke SIMULATOR=vcs
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   make signoff PROFILE=smoke SIMULATOR=vcs COV=1

预期摘要应包含：

.. code-block:: text

   Status: PASS
   directed: mailbox PASS / no UVM_FATAL
   coverage: line+tgl+assert+fsm+branch collected under core_eh2_tb_top.dut

若改动触及 trace/RVFI/cosim reset，还要补跑 cosim-enabled 场景；若改动触及 AXI4
memory 或 mailbox，则要检查 ``lsu_axi_awaddr`` 与 ``lsu_axi_wdata`` 波形。TB top
不是适合“只跑编译”的文件，因为大量错误只有在 UVM build/connect phase 或运行期
handshake 中才会暴露。

§22  Early binary load 与 UVM loader
------------------------------------

TB top 支持 time 0 的 ``+bin=<path>`` early hex load。它把同一个 ``.hex`` 文件写入
LSU、IFU 和 SB 三个行为级 memory array，使 core 在 reset 释放后的第一次取指就能看到
有效指令。raw binary 仍交给 UVM loader 处理，避免在 TB top 中复制 ELF/raw 解析逻辑。

关键代码（early hex load）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 156-174
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:156-174

.. list-table:: Binary load 路径对照
   :header-rows: 1
   :widths: 24 34 42

   * - 路径
     - 触发条件
     - 用途
   * - Early hex load
     - ``+bin`` 指向 ``.hex``
     - reset 后立即取指，适合 smoke/direct hex
   * - UVM memory write helper
     - base test 通过 ``tb_intf.mem_write_req``
     - raw binary 或需要更灵活加载的 test
   * - Cosim binary loader
     - cosim agent 加载同一路径到 Spike
     - 保证 DUT 与 Spike memory image 一致
   * - Compliance signature
     - compliance flow 的 signature region
     - RISC-V compliance 结果比对

``early_bin_loaded`` 通过 ``core_eh2_tb_intf`` 暴露给 UVM test。base test 可以据此避免
重复加载同一个 hex，减少 reset 后首条 fetch 与 UVM load 之间的竞态。

§23  Safety timeout 与 UVM timeout
----------------------------------

TB top 保留 30 分钟 safety timeout，作为 UVM timeout 之外的最后保护。这不是常规失败
判定入口；正常失败应由 mailbox、scoreboard mismatch、UVM objection 或脚本 log checker
先报告。safety timeout 的价值是防止仿真在 CI 或批量回归中无限挂住。

关键代码（safety timeout）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 573-582
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:573-582

.. list-table:: 结束条件优先级
   :header-rows: 1
   :widths: 24 36 40

   * - 条件
     - 来源
     - 语义
   * - mailbox PASS
     - DUT LSU store
     - 测试程序自检通过
   * - mailbox FAIL
     - DUT LSU store
     - 测试程序自检失败
   * - cosim mismatch
     - scoreboard
     - 架构参考比对失败，优先级高于 mailbox PASS
   * - UVM fatal
     - env/agent/test
     - testbench 配置或运行期错误
   * - safety timeout
     - TB top
     - 无结束条件触发，仿真被强制停止

§24  DUT wrapper 与 RVFI adapter 的边界
----------------------------------------

TB top 当前实例化的是 EH2 wrapper，并在 sidecar 路径上提供 RVFI 风格观察。文档中需要
区分 DUT wrapper、RVFI adapter 和 trace monitor：wrapper 是被验证对象入口；trace
packet 是 EH2 原生退休输出；RVFI adapter 是验证辅助视图，不改变 DUT 行为。

.. code-block:: text

   eh2_veer_wrapper dut
      |
      +-- native EH2 trace packet
      |       |
      |       +--> eh2_trace_intf -> trace monitor -> cosim scoreboard
      |
      +-- RVFI-equivalent sidecar
              |
              +--> eh2_rvfi_if -> RVFI smoke / formal-friendly checks

.. list-table:: Trace 与 RVFI 边界
   :header-rows: 1
   :widths: 26 34 40

   * - 对象
     - 数据来源
     - 用途
   * - EH2 trace packet
     - DUT trace ports
     - cosim 主退休输入，支持双线程/双 lane
   * - DUT probe interface
     - RTL hierarchy signals
     - async writeback、debug/interrupt/reset 状态
   * - RVFI interface
     - adapter/sidecar 映射
     - RVFI smoke 和形式化友好的检查
   * - Coverage interface
     - RTL hierarchy signals
     - covergroup 采样，不进入 cosim compare

§25  DMA port tie-off
---------------------

当前 TB top 中 DMA AXI4 port 没有外部 DMA master，输入侧被 tie off。注释明确指出 DUT
输出不能再由 TB assign，否则会造成 multi-driver X。这个细节对后续 DMA directed 扩展
很重要：如果要验证 DMA，需要新增正确的 master/slave 建模，而不是删除 tie-off 后随意
驱动同一组 wire。

关键代码（DMA tie-off）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 545-571
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:545-571

.. warning::

   DMA port 当前是集成边界，不是 05 章 UVM agent 的默认 stimulus。文档后续若新增
   DMA agent，应同时更新 TB top、env、vseq、coverage 和 sign-off flow，而不能只在
   appendix 中描述一个未接入的组件。

§26  Memory model 与 mailbox 的共享性
--------------------------------------

LSU、IFU 和 SB 三个 memory model 默认使用相同的 early hex 内容，但运行中它们是三个
独立 memory array。``tb_intf.mem_write_req`` 同时写入三者，是为了让 UVM loader 写入的
程序或数据在 fetch、load/store 和 debug system-bus 三个视角都可见。这个行为简化了
裸机测试环境，但也意味着它不是一个精确 SoC memory coherency model。

.. list-table:: 三个 memory model
   :header-rows: 1
   :widths: 24 30 46

   * - Memory
     - 连接端口
     - 验证用途
   * - ``lsu_mem``
     - LSU AXI4
     - load/store、mailbox、signature、external data
   * - ``ifu_mem``
     - IFU AXI4
     - instruction fetch、ICache fill
   * - ``sb_mem``
     - debug system bus AXI4
     - debug/DMI system-bus 访问

如果未来要验证真实 SoC memory hierarchy，例如 IFU/LSU/SB 共享一致性、wait-state 或
不同 address region 权限，应替换或扩展 memory model，而不是继续依赖三份 array 同步
写入的简化假设。

§27  TB top 与 Sphinx literalinclude 维护
-----------------------------------------

本章大量使用 ``literalinclude`` 指向真实 SystemVerilog 文件。修改源码行号后，Sphinx
仍会构建成功，但片段可能不再覆盖想说明的逻辑。因此维护流程中除了构建，还要快速人工
查看片段上下文，确认 caption 的行号仍对应主题。

.. code-block:: bash

   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html
   rg -n 'literalinclude:: .*core_eh2_tb_top.sv' docs/sphinx_cn/source/05_verification_arch/tb_top.rst
   wc -l dv/uvm/core_eh2/tb/core_eh2_tb_top.sv

TB top 当前源码为 1,161 行。若源码大规模重排，建议优先更新本章以下片段：mailbox/reset、
AXI4 interface、RVFI/coverage/config_db、early binary load、DMA tie-off 和 safety
timeout。这些片段覆盖了 UVM 平台最关键的硬件边界契约。

§28  DUT 信号声明文件的角色
----------------------------

``core_eh2_dut_signals.svh`` 把顶层 wire/logic 声明从 TB top 主体中拆出。这样做不是为了
抽象，而是为了让 DUT wrapper 的大端口表、AXI4 五通道、trace、debug、interrupt 和 DMA
信号保持可维护。该文件被 TB top include 后，所有信号仍属于 ``core_eh2_tb_top`` 作用域。

关键代码（信号声明文件开头）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh
   :language: systemverilog
   :lines: 1-80
   :caption: dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:1-80

.. list-table:: 信号声明分组
   :header-rows: 1
   :widths: 24 34 42

   * - 分组
     - 典型信号
     - 用途
   * - Reset/NMI
     - ``reset_vector``、``nmi_vector``、``nmi_int``
     - 启动向量和 NMI stimulus
   * - JTAG
     - ``jtag_tck/tms/tdi/tdo/trst_n``
     - JTAG agent 与 DMI bridge
   * - Trace
     - ``trace_rv_i_*``
     - retire trace、cosim、RVFI sidecar
   * - Debug/Control
     - ``o_debug_mode_status``、``mpc_debug_*``
     - debug/halt/run agent 和 probe
   * - Interrupts
     - ``timer_int``、``soft_int``、``extintsrc_req``
     - IRQ agent、PIC、TLU interrupt path
   * - AXI4 LSU/IFU/SB/DMA
     - ``*_axi_aw*``、``*_axi_w*``、``*_axi_ar*``、``*_axi_r*``
     - DUT wrapper、memory model、AXI4 agent interface

§29  DUT wrapper 端口连接审查
-----------------------------

EH2 wrapper 端口表很大，审查时建议按通道分块，而不是逐行看是否“长得相似”。尤其是
AXI4 五通道，valid/ready 方向、ID width 和 data/strobe width 一旦接错，可能表现为
mailbox timeout、cosim memory mismatch 或 X-propagation。

关键代码（DUT wrapper 实例 AXI4 片段）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 180-240
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:180-240

.. list-table:: Wrapper 端口审查点
   :header-rows: 1
   :widths: 28 34 38

   * - 端口组
     - 审查点
     - 失败表现
   * - Trace
     - instruction/address/valid/exception lane 对齐
     - trace PC 或 rd_data 错位
   * - LSU AXI4
     - AW/W/B/AR/R 五通道方向与宽度
     - load/store hang 或 mailbox 不触发
   * - IFU AXI4
     - AR/R 取指路径和 ID width
     - reset 后无 fetch 或 ICache miss 卡住
   * - SB AXI4
     - debug system-bus 访问路径
     - JTAG/DMI debug memory access 失败
   * - DMA AXI4
     - 输入 tie-off 与输出不多驱动
     - X-propagation 或 compile/elab warning
   * - Debug/Halt
     - request/ack/status 数组与 thread index
     - halt/run directed 不稳定

§30  Mailbox 与 console 输出细节
--------------------------------

mailbox monitor 对可打印 ASCII 字节使用 ``$write``，而不是 UVM report。这样裸机 ASM
可以用同一个地址输出短日志，不需要 UART 或复杂外设模型。该机制简单但有约束：只有
LSU AW handshake 被用作 mailbox write 触发，若 W channel 与 AW channel 在复杂场景下
错位，需要确认 ``mailbox_data`` 是否对应同一个 transaction。

.. list-table:: Mailbox 调试细节
   :header-rows: 1
   :widths: 26 34 40

   * - 现象
     - 检查
     - 说明
   * - 打印字符乱码
     - ``lsu_axi_wdata[7:0]`` 与 AW 地址同周期关系
     - 当前 monitor 简化假设 AW/W 对齐
   * - PASS 未触发
     - ``mailbox_addr`` 是否等于 ``0xD0580000``
     - linker/runtime 地址可能错误
   * - FAIL 触发
     - ASM 自检路径和异常 handler
     - 程序主动报告失败，不是 TB top 失败
   * - 无任何 mailbox 写
     - IFU fetch、reset vector、LSU store
     - 程序可能未启动或卡死
   * - console 输出但无 PASS
     - 程序打印后未写 ``0xFF``
     - runtime end marker 缺失

§31  与上游 RTL clone 的边界
-----------------------------

EH2 DUT 来自 `/home/host/Cores-VeeR-EH2/` 上游 clone；验证平台在本仓库中用 wrapper、
RVFI sidecar、UVM TB top 和脚本把它接入 sign-off flow。TB top 文档只描述验证平台的
连接与观测，不改写上游 RTL 的设计意图。若发现 wrapper port、RTL 参数或 hierarchy
与文档不一致，应更新文档和验证 glue；不要为了文档一致性修改刚通过验证的 RTL。

.. list-table:: 本仓库与上游 RTL 边界
   :header-rows: 1
   :widths: 28 34 38

   * - 对象
     - 归属
     - 文档处理
   * - ``eh2_veer`` 内部实现
     - 上游 RTL
     - 在 02 章和 appendix A 解释
   * - ``eh2_veer_wrapper``
     - 上游/集成 wrapper
     - TB top 按端口连接解释
   * - ``eh2_veer_wrapper_rvfi``
     - 本仓库验证 glue
     - RVFI sidecar 章节解释
   * - UVM agents/env/tests
     - 本仓库
     - 05 章和 appendix B 解释
   * - scripts/signoff
     - 本仓库
     - 06 章和 appendix F 解释

§32  变更影响矩阵
-----------------

TB top 改动应按影响面决定验证范围：

.. list-table:: TB top 改动影响矩阵
   :header-rows: 1
   :widths: 28 36 36

   * - 改动
     - 影响
     - 建议验证
   * - ``uvm_config_db`` 字段
     - agent build/connect
     - smoke + UVM build log + 相关 agent directed
   * - AXI4 interface 映射
     - IFU/LSU/SB transaction 和 cosim
     - smoke + directed + store/AMO cosim
   * - Mailbox
     - 所有 bare-metal test 结束条件
     - smoke、directed、riscv-dv smoke
   * - Trace/probe
     - cosim、RVFI、coverage
     - cosim smoke、RVFI smoke、coverage compile
   * - IRQ/JTAG/Halt-Run
     - active stimulus agent
     - 对应 directed + waveform spot check
   * - Coverage interface
     - GROUP/FSM/line dashboard
     - VCS COV compile + merge_cov
   * - Reset/safety timeout
     - 全平台运行稳定性
     - reset directed + long smoke

§33  本章维护结论
-----------------

TB top 是 EH2 UVM 平台的硬件边界，也是大多数动态 stage 的共同依赖。它的文档必须保持
“连接事实优先”：先说明真实源码如何实例化 DUT、memory、interface 和 config_db，再解释
这些连接如何服务 cosim、coverage 和 sign-off。只要 TB top 的接口契约稳定，env/agent/
scoreboard 的问题就能被定位到各自章节；一旦 TB top 契约漂移，后续所有组件都会出现
难以归因的连锁失败。

§34  端口级 smoke triage
------------------------

当 ``make smoke SIMULATOR=vcs`` 失败时，TB top 是第一层 triage。推荐按“时钟复位、
取指、退休、mailbox、UVM 报告”顺序定位，而不是直接跳到 scoreboard。这样可以把
硬件连接问题和 test/scoreboard 问题分开。

.. list-table:: Smoke triage 顺序
   :header-rows: 1
   :widths: 24 34 42

   * - 步骤
     - 观察
     - 结论
   * - 时钟复位
     - ``core_clk`` 翻转，``porst_l`` / ``rst_l`` 释放
     - 不成立时先查 TB initial/reset
   * - reset vector
     - ``reset_vector=0x80000000``
     - 错误会导致 IFU 从错误区域取指
   * - IFU AXI4
     - ``ifu_axi_arvalid`` / ``ifu_axi_rvalid``
     - 无活动说明未开始取指或 memory 未响应
   * - Trace retire
     - ``trace_rv_i_valid_ip`` 有效
     - 无退休说明 core 卡在 fetch/decode/exception
   * - LSU mailbox
     - ``lsu_axi_awaddr=0xD0580000``
     - 程序到达结束 marker
   * - UVM report
     - no fatal、mailbox PASS、scoreboard PASS
     - 平台级 smoke 通过

§35  TB top 与 compliance 子环境
---------------------------------

RISC-V compliance 子环境复用 TB top 的 memory、mailbox/signature 和 DUT wrapper 连接，
但它的 pass/fail 语义不同于普通 directed：compliance 更关注 signature 与标准期望的
匹配。TB top 文档仍要描述共同硬件边界，具体 compliance flow 见 :ref:`compliance_flow`。

.. list-table:: Compliance 复用点
   :header-rows: 1
   :widths: 26 34 40

   * - 复用点
     - TB top 角色
     - Compliance 影响
   * - Program memory
     - IFU/LSU/SB memory model
     - compliance ELF/HEX 可执行
   * - Signature region
     - LSU memory 可读写
     - 标准测试输出结果
   * - Reset vector
     - ``0x80000000``
     - 与 linker/startup 一致
   * - Interrupt/debug pins
     - 默认保持静默或由 test 控制
     - 避免干扰 ISA compliance
   * - Coverage sidecar
     - 可开 VCS COV
     - compliance stage 可贡献部分 coverage

§36  TB top 与 CI 的关系
-------------------------

CI 中 TB top 的失败常表现为编译/elaboration、UVM build fatal 或 smoke timeout。因为
TB top 包含 package import、interface 实例、DUT wrapper、大量 hierarchical reference
和 config_db 发布，所以它同时受 RTL、UVM 和脚本 filelist 影响。

.. list-table:: CI 失败分类
   :header-rows: 1
   :widths: 28 34 38

   * - 失败阶段
     - 常见原因
     - 处理
   * - compile
     - package/import/interface 类型不可见
     - 查 filelist 和 package include 顺序
   * - elaboration
     - DUT port 或 parameter 不匹配
     - 查 wrapper 与 TB top 端口表
   * - UVM build
     - config_db get 失败
     - 查字段名、scope 和 agent 创建路径
   * - run timeout
     - reset/fetch/mailbox/cosim hang
     - 按 smoke triage 顺序定位
   * - coverage merge
     - vdb 或 scope 不一致
     - 查 VCS ``-cm`` 和 ``cover.cfg``

§37  Checklist：提交前人工复核
------------------------------

TB top 或本章文档变更提交前，人工复核以下条目：

* ``core_eh2_tb_top.sv`` literalinclude 片段能覆盖对应主题。
* 所有 virtual interface 字段名与 driver/monitor ``get`` 字段一致。
* mailbox 地址、PASS/FAIL 数据和最新 demo 数据未漂移。
* NC/Incisive 被描述为完整备选 simulator；VCS 仍是默认 release 参考。
* coverage 口径仍是 VCS/URG 5 维度、DUT-only scope；NC 口径需标明 ``cov_full_nc.ccf`` / IMC。
* Ibex 对照只比较方法论，不把 Ibex memory interface 写成 EH2 AXI4。
* Sphinx build 无 warning。

§38  与 waveform 调试脚本的配合
--------------------------------------------------------------------------------

TB top 是波形调试时最稳定的锚点。无论使用 VCS+DVE/Verdi 还是 NC/SimVision，首先应把
``core_eh2_tb_top``、``dut``、AXI4 interface、mailbox 和 trace/probe sidecar 加入波形。
这样可以在不进入 UVM class 层级的情况下，确认硬件连接是否正确。

.. list-table:: 推荐波形层级
   :header-rows: 1
   :widths: 28 34 38

   * - 层级/信号
     - 观察目的
     - 典型失败
   * - ``core_clk`` / ``rst_l``
     - 基准时序
     - reset 未释放或时钟停止
   * - ``dut``
     - DUT wrapper 与内部层级
     - RTL X、flush、stall、exception
   * - ``lsu_axi_*``
     - mailbox、load/store、signature
     - LSU handshake 卡住
   * - ``ifu_axi_*``
     - fetch、ICache fill
     - reset 后无取指
   * - ``sb_axi_*``
     - debug system-bus
     - JTAG/DMI 后无 SB 访问
   * - ``trace_rv_i_*``
     - retire trace
     - cosim 无 step 或 PC 错位
   * - ``dut_probe_intf``
     - debug/interrupt/async writeback
     - Spike state 通知不一致

§39  与 filelist 的耦合
--------------------------------------------------------------------------------

TB top 依赖多个 package、interface 和 include 文件。filelist 顺序如果改变，可能在不同
simulator 上表现不同：VCS 通常更宽容，NC elaboration 对未引用 package 更敏感。因此
``import core_eh2_test_pkg::*`` 被保留在 TB top 顶部，用于确保 test/sequences factory
registration 在 elaboration 阶段可见。

.. list-table:: Filelist 依赖
   :header-rows: 1
   :widths: 30 34 36

   * - 依赖
     - 用途
     - 错误表现
   * - ``uvm_macros.svh`` / ``uvm_pkg``
     - UVM component/object macro
     - compile 期宏或类型不可见
   * - ``core_eh2_test_pkg``
     - test class factory registration
     - run-time “test not found”
   * - AXI4 interface/memory model
     - LSU/IFU/SB bus 建模
     - interface 类型或 module 不可见
   * - IRQ/JTAG/Halt-Run interface
     - active stimulus pins
     - config_db 类型不匹配
   * - trace/probe/RVFI/fcov interface
     - cosim 和 coverage sidecar
     - monitor 或 coverage compile 失败
   * - DUT wrapper filelist
     - ``eh2_veer_wrapper`` 可见
     - elaboration 找不到 DUT module

§40  Release 文档中的 TB top 摘要模板
--------------------------------------------------------------------------------

在 release note 或 sign-off 报告中引用 TB top 时，建议使用下面的简短模板，避免每次重新
解释平台边界：

.. code-block:: text

   EH2 UVM TB top instantiates eh2_veer_wrapper, three AXI4 slave memories
   (LSU/IFU/SB), IRQ/JTAG/Halt-Run/trace/probe/RVFI/fcov interfaces, mailbox
   PASS/FAIL detection at 0xD0580000, and UVM config_db publication. Dynamic
   sign-off uses VCS as the default release reference; NC is a full alternate
   simulator for cross-checks and SHM/SimVision waveform debug.

中文报告中可写为：

.. code-block:: text

   TB top 负责 EH2 DUT、三组 AXI4 memory、主动 stimulus interface、trace/probe/RVFI
   sidecar、coverage interface 和 mailbox 结束条件。当前默认 release 数据来自
   VCS/URG；NC/Incisive 作为完整备选 simulator，可用于 cross-check 和 SHM/SimVision
   波形排查。

§41  本章完成标准
--------------------------------------------------------------------------------

本章满足阶段 5 的完成标准应同时具备：

* 顶部元数据为 2026-05-19，作者为 ``GPT-doc-author``。
* 所有关键行为都有真实源码片段：mailbox/reset、AXI4 映射、coverage/config_db、
  early binary load、DMA tie-off、safety timeout。
* 命令和工具口径与当前平台一致：VCS 主线、URG coverage、NC 单测波形。
* 与 Ibex 对照说明方法论一致和 EH2 差异。
* Sphinx 构建无 warning，红线扫描无旧事实命中。

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

§42  v2-56 ``core_eh2_dut_signals.svh`` 全文行段级精读
--------------------------------------------------------------------------------

``dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh`` 是 ``core_eh2_tb_top.sv`` 的信号声明片段。
它把 reset、NMI、JTAG、trace/debug/control、interrupt、clock-enable 以及 4 组 AXI4 端口集中
声明出来，再由 TB top 连接到 DUT wrapper、AXI memory model、trace/probe sidecar、coverage 和
cosim 监控路径。该文件本身不实例化组件，但决定 TB top 中所有跨模块连线的名字、位宽和方向语义。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tb/core_eh2_dut_signals.svh:全文

逐段精读：

* L1-L4：reset/NMI 基础入口。``reset_vector`` 和 ``nmi_vector`` 提供取指起点与 NMI trap
  入口地址，``nmi_int`` 是 TB 可驱动的非屏蔽中断输入。
* L6-L12：JTAG 信号组。TCK/TMS/TDI/TRST/TDO 和 ``jtag_id`` 共同服务 debug/JTAG agent，
  后续 debug directed test 通过这组 pin 进入 DMI/debug module 路径。
* L14-L26：trace 与 verification-only writeback view。前半段导出每线程、双 lane 的指令、
  地址、valid、exception、ecause、interrupt 和 tval；后半段补出 RVFI-equivalent 的 rd valid、
  rd addr 和 rd data，使 cosim/trace monitor 能在双发射场景中对齐 I0/I1 写回。
* L27-L40：debug/control 状态与请求应答。``o_debug_mode_status``、halt/run ack/status、
  ``mpc_debug_*``、``mpc_reset_run_req``、``debug_brkpt_status``、``dec_tlu_mhartstart`` 和
  ``i_cpu_run_req`` 共同覆盖 debug mode、halt/run 协议和 hart start 状态。
* L41-L57：performance counter、中断和 bus clock enable。``dec_tlu_perfcnt0`` 到
  ``dec_tlu_perfcnt3`` 给性能事件观察路径使用；timer/software/external interrupt 连接中断 stimulus；
  LSU/IFU/debug/DMA bus clock enable 则用于 AXI 端口时钟门控观察。
* L58-L100：LSU AXI4 端口。该段完整声明 AW/W/B/AR/R 五个 channel，ID 宽度取
  ``RV_LSU_BUS_TAG``，数据宽度为 64 bit，地址为 32 bit。load/store、AMO、bus error injection 和
  DCCM/MMIO 外部访问都从这组端口进入 memory model 或错误注入逻辑。
* L101-L142：IFU AXI4 端口。信号形态与 LSU 基本一致，但 ID 宽度取 ``RV_IFU_BUS_TAG``。
  指令 fetch、ICCM/ICache miss、instruction bus error 和取指侧 PMP/fault 观察最终都落在这组
  read-dominant AXI 线上。
* L144-L185：SB/debug AXI4 端口。``sb_axi_*`` 使用 ``RV_SB_BUS_TAG``，承载 debug system bus
  访问。JTAG/debug 测试通过该端口观察或修改 memory-mapped 状态，因此它与 debug module、memory
  model 和 scoreboard 都存在间接耦合。
* L187-L220：DMA AXI4 端口。该文件声明完整 DMA master 端口，但当前 TB top 将 DMA path tie-off，
  用来固定 DUT wrapper 的端口连接边界。保留完整 AW/W/B/AR/R channel 能避免 wrapper 变化时隐藏
  未连接端口，也为后续 DMA directed test 留出接口面。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 通过 include 引入这些信号声明。
* 调用：无独立调用逻辑；信号随后被 DUT wrapper、AXI memory、JTAG/IRQ/Halt-Run agent、
  trace/probe/RVFI/fcov interface 和 cosim monitor 引用。
* 共享状态：``RV_NUM_THREADS``、``RV_*_BUS_TAG``、``RV_PIC_TOTAL_INT`` 等宏必须与 EH2
  RTL/TB filelist 中的配置一致；否则最先暴露为 elaboration 位宽或端口连接错误。
