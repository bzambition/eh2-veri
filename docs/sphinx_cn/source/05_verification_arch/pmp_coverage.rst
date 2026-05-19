.. _pmp_coverage:
.. _05_verification_arch/pmp_coverage:

PMP 覆盖率 — 架构参考
=====================

:status: draft
:source: dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author
:commit: feeac23a7c15114f9f962beca1758834f83dbf88

§1  本章边界
------------

本章解释 ``eh2_pmp_fcov_if`` 在 EH2 UVM 平台中的 PMP/ePMP 覆盖率结构。逐段源码字典见
:ref:`appendix_b_uvm_fcov`；这里聚焦 coverage interface 的 enable 条件、testbench 默认
实例化、派生信号、主要 covergroup 分层，以及 PMP/ePMP directed test 如何在 test library
中进入运行。

本章只描述下列源码中可直接回溯的内容：

* :file:`dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv`
* :file:`dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv`
* :file:`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv`
* :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`dv/uvm/core_eh2/tests/core_eh2_test_lib.sv`
* :file:`docs/adr/0009-pmp-cosim.md`

当前 testbench 中 ``u_pmp_fcov_if`` 的参数是 ``PMPEnable(1'b0)``，PMP/ePMP 配置信号与
fault 输入均接常量 0，``debug_mode`` 接 DUT debug mode，``data_req`` 接 0。源码没有把该
实例默认接到 DUT PMP CSR 或 PMP fault 输出，因此本章不把当前默认配置描述成已采样 DUT PMP
行为。

§2  架构数据流
--------------

PMP coverage interface 是一个独立于主 ``eh2_fcov_if`` 的 coverage scaffold。它从参数
``PMPEnable`` 决定是否生成 covergroup；从 plusarg ``+enable_eh2_fcov`` 决定运行时开关字段
``en_pmp_fcov``；再从 PMP/ePMP 配置、fault、debug、data request 与 load/store 输入派生
coverpoint 输入。

::

   core_eh2_tb_top.sv
      |
      +-- eh2_fcov_if u_fcov_if        (主功能覆盖率)
      |
      `-- eh2_pmp_fcov_if u_pmp_fcov_if
             |
             +-- parameters:
             |      PMPEnable, PMPGranularity, PMPNumRegions
             |
             +-- input signals:
             |      pmp_cfg_*, pmp_addr, mseccfg_*, pmp_*_err,
             |      debug_mode, data_req, is_load
             |
             +-- derived signals:
             |      pmp_cfg_rwx, region_active, pmp_any_fault,
             |      mode_changed, lock_changed, rwx_changed
             |
             `-- if (PMPEnable) g_pmp_fcov:
                    pmp_region_cg / pmp_access_cg / pmp_epmp_cg / ...

接口关系：

* 被调用：``core_eh2_tb_top`` 实例化 ``u_pmp_fcov_if``。
* 调用：coverage interface 内部声明 covergroup、coverpoint 和 cross。
* 共享状态：``PMPEnable`` 控制 generate；``pmp_cfg_*``、``pmp_addr``、``mseccfg_*``、
  ``pmp_iside_err``、``pmp_dside_err``、``debug_mode``、``data_req``、``is_load`` 被各
  covergroup 读取。

§3  Coverage scaffold 的实例化位置
----------------------------------

职责：``eh2_fcov_bind.sv`` 不执行 bind；源码注释明确 coverage interface 直接在
``core_eh2_tb_top.sv`` 中实例化。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv:L4-L15``）：

.. code-block:: systemverilog

   // Coverage interfaces are instantiated directly in core_eh2_tb_top.sv
   // using hierarchical references to access signals across module boundaries.
   // This approach is used because EH2's module hierarchy requires cross-module
   // references that bind cannot easily reach (e.g., dut.veer.dec.decode.*).
   //
   // The eh2_fcov_if and eh2_pmp_fcov_if interfaces are created in tb_top
   // and connected via assign statements. This file exists as a compilation
   // placeholder required by the filelist.
   
   // Coverage instantiation is in core_eh2_tb_top.sv:
   //   eh2_fcov_if u_fcov_if (...);
   //   eh2_pmp_fcov_if u_pmp_fcov_if (...);

逐段解释：

* 第 4~7 行：注释说明 coverage interface 直接在 ``core_eh2_tb_top.sv`` 中实例化，因为 EH2
  层级引用需要跨模块访问，bind 文件不易覆盖这些路径。
* 第 9~11 行：``eh2_fcov_if`` 与 ``eh2_pmp_fcov_if`` 都由 top 创建，本文件只是 filelist
  需要的 compilation placeholder。
* 第 13~15 行：注释列出实例名 ``u_fcov_if`` 和 ``u_pmp_fcov_if``。

接口关系：

* 被调用：仿真 filelist 编译该文件。
* 调用：无 SystemVerilog bind 语句。
* 共享状态：无运行期状态。

§4  Testbench 默认 PMP coverage 实例
------------------------------------

职责：``core_eh2_tb_top`` 实例化 ``u_pmp_fcov_if``，但默认参数关闭 PMP coverage generate。
注释说明当前平台默认 EH2 配置不实现 PMP/ePMP。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1029-L1054``）：

.. code-block:: systemverilog

   // PMP Functional Coverage Interface Instance
   //--------------------------------------------------------------------------
   // The default EH2 configuration used by this platform does not implement
   // PMP/ePMP, but the interface is instantiated to keep the coverage scaffold
   // complete and ready for PMP-enabled configurations.
   eh2_pmp_fcov_if #(
     .PMPEnable      (1'b0),
     .PMPGranularity (0),
     .PMPNumRegions  (4)
   ) u_pmp_fcov_if (
     .clk_i          (core_clk),
     .rst_l_i        (rst_l),
     .pmp_cfg_lock   ('0),
     .pmp_cfg_mode   ('0),
     .pmp_cfg_exec   ('0),
     .pmp_cfg_write  ('0),
     .pmp_cfg_read   ('0),
     .pmp_addr       ('0),
     .mseccfg_mml    (1'b0),
     .mseccfg_mmwp   (1'b0),
     .mseccfg_rlb    (1'b0),
     .pmp_iside_err  (1'b0),
     .pmp_dside_err  (1'b0),
     .debug_mode     (dut.veer.dec.dec_tlu_debug_mode[0]),
     .data_req       (1'b0)
   );

逐段解释：

* 第 1029~1033 行：注释说明这是 PMP functional coverage interface；当前默认配置不实现
  PMP/ePMP，但保留 scaffold。
* 第 1034~1038 行：实例参数为 ``PMPEnable=1'b0``、``PMPGranularity=0``、
  ``PMPNumRegions=4``。
* 第 1039~1046 行：时钟复位接 ``core_clk``、``rst_l``；PMP 配置和地址输入全部接 0。
* 第 1047~1051 行：ePMP bits 与 PMP fault 输入全部接 0。
* 第 1052~1054 行：``debug_mode`` 接 DUT debug mode，``data_req`` 接 0；在该实例片段中没有
  ``is_load`` 具名连接。

接口关系：

* 被调用：testbench elaboration。
* 调用：``eh2_pmp_fcov_if`` 实例化。
* 共享状态：当前默认配置下 ``PMPEnable=0``，不会生成 ``g_pmp_fcov`` 内 covergroup。

§5  Interface 参数、端口与 enable 逻辑
--------------------------------------

职责：``eh2_pmp_fcov_if`` 定义 PMP coverage 的参数、输入端口和 ``en_pmp_fcov`` 初始化逻辑。
``en_pmp_fcov`` 只有在参数 ``PMPEnable`` 为 1 时才读取 ``+enable_eh2_fcov``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L25-L60``）：

.. code-block:: systemverilog

   interface eh2_pmp_fcov_if
     import eh2_pkg::*;
   #(
     parameter bit          PMPEnable      = 1'b0,
     parameter int unsigned PMPGranularity = 0,
     parameter int unsigned PMPNumRegions  = 4
   ) (
     input logic clk_i,
     input logic rst_l_i,
   
     // PMP configuration from CSR registers
     input logic [PMPNumRegions-1:0]       pmp_cfg_lock,
     input logic [PMPNumRegions-1:0] [1:0] pmp_cfg_mode,
     input logic [PMPNumRegions-1:0]       pmp_cfg_exec,
     input logic [PMPNumRegions-1:0]       pmp_cfg_write,
     input logic [PMPNumRegions-1:0]       pmp_cfg_read,
     input logic [PMPNumRegions-1:0] [31:0] pmp_addr,
   
     // ePMP mseccfg
     input logic mseccfg_mml,
     input logic mseccfg_mmwp,
     input logic mseccfg_rlb,
   
     // PMP access check results
     input logic pmp_iside_err,
     input logic pmp_dside_err,

逐段解释：

* 第 25~31 行：interface import ``eh2_pkg``，并定义 ``PMPEnable``、``PMPGranularity`` 和
  ``PMPNumRegions`` 参数。
* 第 32~33 行：覆盖率采样使用 ``clk_i`` 和低有效复位 ``rst_l_i``。
* 第 36~41 行：每个 PMP region 的 lock、mode、exec/write/read 权限和地址作为数组输入。
* 第 44~46 行：ePMP ``mseccfg`` 中的 ``mml``、``mmwp``、``rlb`` 是独立输入。
* 第 49~50 行：instruction-side 与 data-side PMP error 是 fault 覆盖的输入。

接口关系：

* 被调用：``u_pmp_fcov_if`` 实例化时绑定这些端口。
* 调用：无函数调用。
* 共享状态：端口输入被后续派生信号和 covergroup 读取。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L52-L72``）：

.. code-block:: systemverilog

     // Debug mode
     input logic debug_mode,
   
     // Data request
     input logic data_req,
   
     // Load (1) vs Store (0) cycle indicator — from LSU request phase (issue 68)
     input logic is_load
   );
   
     `include "uvm_macros.svh"
   
     bit en_pmp_fcov;
   
     initial begin
       if (PMPEnable) begin
         void'($value$plusargs("enable_eh2_fcov=%d", en_pmp_fcov));
       end else begin
         en_pmp_fcov = 1'b0;
       end
     end

逐段解释：

* 第 52~59 行：``debug_mode``、``data_req`` 和 ``is_load`` 用于 fault/debug/access-type
  覆盖。
* 第 62 行：include UVM 宏。
* 第 64 行：声明运行时 coverage enable 字段 ``en_pmp_fcov``。
* 第 66~71 行：``PMPEnable`` 为 1 时读取 ``+enable_eh2_fcov``；否则强制
  ``en_pmp_fcov=0``。
* 第 72 行：结束 initial block。

接口关系：

* 被调用：仿真 initial 时间 0 执行。
* 调用：``$value$plusargs``。
* 共享状态：``PMPEnable``、``en_pmp_fcov``。

§6  PMP mode、权限与访问类型枚举
---------------------------------

职责：interface 定义三个枚举：PMP mode、带 MML 语义的权限编码、访问类型。后续 covergroup
以这些枚举作为 coverpoint 值域。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L77-L130``）：

.. code-block:: systemverilog

   typedef enum logic [1:0] {
     PMP_MODE_OFF   = 2'b00,
     PMP_MODE_TOR   = 2'b01,
     PMP_MODE_NA4   = 2'b10,
     PMP_MODE_NAPOT = 2'b11
   } pmp_mode_e;
   
   // =========================================================================
   // PMP Permission bits with MML support
   // =========================================================================
   typedef enum logic [4:0] {
     NONE        = 5'b00000,
     R           = 5'b00001,
     W           = 5'b00010,
     WR          = 5'b00011,
     X           = 5'b00100,
     XR          = 5'b00101,
     XW          = 5'b00110,
     XWR         = 5'b00111,
     L           = 5'b01000,
     LR          = 5'b01001,

逐段解释：

* 第 77~82 行：``pmp_mode_e`` 明确定义 OFF、TOR、NA4、NAPOT 四种 mode 编码。
* 第 87~103 行：``pmp_priv_bits_e`` 前半部分覆盖普通 RWX 与 lock 组合。
* 第 104~119 行：源码继续定义 MML 相关权限组合，例如 ``MML_RU``、``MML_WRM_RU``、
  ``MML_XRM_XU`` 等。
* 第 120 行：结束 ``pmp_priv_bits_e``。

接口关系：

* 被调用：``pmp_region_cg``、``pmp_region_ext_cg``、ePMP 和 address coverage 读取这些枚举。
* 调用：无函数调用。
* 共享状态：枚举常量。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L122-L130``）：

.. code-block:: systemverilog

   // =========================================================================
   // Access type enum (for access_type coverpoints)
   // =========================================================================
   typedef enum logic [1:0] {
     ACCESS_EXEC  = 2'b00,
     ACCESS_LOAD  = 2'b01,
     ACCESS_STORE = 2'b10,
     ACCESS_NONE  = 2'b11
   } pmp_access_type_e;

逐段解释：

* 第 122~124 行：注释说明该枚举服务于 access type coverpoint。
* 第 125~130 行：访问类型分为 exec、load、store 和 none。

接口关系：

* 被调用：``inferred_access_type`` 和 ``pmp_access_type_cg``。
* 调用：无函数调用。
* 共享状态：访问类型枚举常量。

§7  派生信号：权限、active 计数与 fault
----------------------------------------

职责：interface 先把原始输入转换成 covergroup 更容易采样的派生信号，包括 ``pmp_cfg_rwx``、
``region_active``、``num_active_regions``、``inferred_access_type`` 和 ``pmp_any_fault``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L136-L173``）：

.. code-block:: systemverilog

   // Combined RWX per region (non-MML view)
   logic [PMPNumRegions-1:0] [2:0] pmp_cfg_rwx;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_rwx
     assign pmp_cfg_rwx[r] = {pmp_cfg_exec[r], pmp_cfg_write[r], pmp_cfg_read[r]};
   end
   
   // Region active: mode != OFF
   logic [PMPNumRegions-1:0] region_active;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_active
     assign region_active[r] = (pmp_cfg_mode[r] != PMP_MODE_OFF);
   end
   
   // Count of active regions
   logic [$clog2(PMPNumRegions+1)-1:0] num_active_regions;
   always_comb begin
     num_active_regions = '0;
     for (int r = 0; r < PMPNumRegions; r++) begin

逐段解释：

* 第 136~140 行：``pmp_cfg_rwx`` 按 exec/write/read 顺序拼成 3 bit 权限向量。
* 第 142~146 行：``region_active`` 在 region mode 不是 OFF 时为 1。
* 第 149~154 行：``num_active_regions`` 在 combinational block 中累加 active region 数。
* 第 155 行：结束 active 计数 block。

接口关系：

* 被调用：多区域、region extension、priority 和 ePMP region covergroup 使用。
* 调用：连续赋值和 ``always_comb``。
* 共享状态：``pmp_cfg_exec``、``pmp_cfg_write``、``pmp_cfg_read``、``pmp_cfg_mode``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L157-L173``）：

.. code-block:: systemverilog

   // Access type inference — is_load signal added (issue 68)
   // iside_err => exec access; dside_err + data_req + is_load => load; + !is_load => store
   pmp_access_type_e inferred_access_type;
   always_comb begin
     if (pmp_iside_err)
       inferred_access_type = ACCESS_EXEC;
     else if (data_req & is_load)
       inferred_access_type = ACCESS_LOAD;
     else if (data_req & ~is_load)
       inferred_access_type = ACCESS_STORE;
     else
       inferred_access_type = ACCESS_NONE;
   end
   
   // Any PMP fault occurred
   logic pmp_any_fault;
   assign pmp_any_fault = pmp_iside_err | pmp_dside_err;

逐段解释：

* 第 157~168 行：访问类型优先把 ``pmp_iside_err`` 判为 exec；否则根据 ``data_req`` 和
  ``is_load`` 区分 load/store；没有请求时为 ``ACCESS_NONE``。
* 第 172~173 行：``pmp_any_fault`` 是 instruction-side 与 data-side fault 的 OR。

接口关系：

* 被调用：``pmp_access_type_cg``、多区域和 transition covergroup 使用。
* 调用：``always_comb`` 和连续赋值。
* 共享状态：``pmp_iside_err``、``pmp_dside_err``、``data_req``、``is_load``。

§8  派生信号：前一拍状态与变化检测
------------------------------------

职责：transition coverage 需要比较当前配置与前一拍配置。interface 在时钟上升沿保存前一拍
mode、lock、RWX 和 ePMP bits，再生成 per-region change 标志。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L175-L199``）：

.. code-block:: systemverilog

   // Previous-cycle configuration (for transition coverage)
   logic [PMPNumRegions-1:0] [1:0] pmp_cfg_mode_prev;
   logic [PMPNumRegions-1:0]       pmp_cfg_lock_prev;
   logic [PMPNumRegions-1:0] [2:0] pmp_cfg_rwx_prev;
   logic                           mseccfg_mml_prev;
   logic                           mseccfg_mmwp_prev;
   logic                           mseccfg_rlb_prev;
   
   always_ff @(posedge clk_i or negedge rst_l_i) begin
     if (!rst_l_i) begin
       pmp_cfg_mode_prev <= '0;
       pmp_cfg_lock_prev <= '0;
       pmp_cfg_rwx_prev  <= '0;
       mseccfg_mml_prev  <= '0;
       mseccfg_mmwp_prev <= '0;
       mseccfg_rlb_prev  <= '0;
     end else begin
       pmp_cfg_mode_prev <= pmp_cfg_mode;
       pmp_cfg_lock_prev <= pmp_cfg_lock;
       pmp_cfg_rwx_prev  <= pmp_cfg_rwx;
       mseccfg_mml_prev  <= mseccfg_mml;
       mseccfg_mmwp_prev <= mseccfg_mmwp;
       mseccfg_rlb_prev  <= mseccfg_rlb;
     end
   end

逐段解释：

* 第 175~181 行：声明当前 coverage 需要保存的前一拍状态。
* 第 183~190 行：复位时前一拍状态全部清零。
* 第 191~198 行：非复位时把当前 PMP/ePMP 配置保存为前一拍状态。
* 第 199 行：结束 sequential block。

接口关系：

* 被调用：``pmp_cfg_transition_cg`` 读取这些 previous-cycle 字段。
* 调用：``always_ff``。
* 共享状态：``pmp_cfg_mode_prev``、``pmp_cfg_lock_prev``、``pmp_cfg_rwx_prev``、
  ``mseccfg_*_prev``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L201-L237``）：

.. code-block:: systemverilog

   // Mode changed per region
   logic [PMPNumRegions-1:0] mode_changed;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_mode_chg
     assign mode_changed[r] = (pmp_cfg_mode[r] != pmp_cfg_mode_prev[r]);
   end
   
   // Lock changed per region
   logic [PMPNumRegions-1:0] lock_changed;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_lock_chg
     assign lock_changed[r] = (pmp_cfg_lock[r] != pmp_cfg_lock_prev[r]);
   end
   
   // RWX changed per region
   logic [PMPNumRegions-1:0] rwx_changed;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_rwx_chg
     assign rwx_changed[r] = (pmp_cfg_rwx[r] != pmp_cfg_rwx_prev[r]);
   end

逐段解释：

* 第 201~205 行：``mode_changed`` 对每个 region 比较当前 mode 与前一拍 mode。
* 第 207~211 行：``lock_changed`` 对每个 region 比较当前 lock 与前一拍 lock。
* 第 213~217 行：``rwx_changed`` 对每个 region 比较当前 RWX 与前一拍 RWX。
* 第 219~223 行：源码继续生成 ``epmp_config_changed``，比较 MML、MMWP 和 RLB 当前值与前一拍。
* 第 225~237 行：源码继续统计每个 region 的 ``napot_trailing_ones``。

接口关系：

* 被调用：transition coverage 与 NAPOT size coverage。
* 调用：连续赋值和 ``always_comb``。
* 共享状态：``mode_changed``、``lock_changed``、``rwx_changed``、``napot_trailing_ones``。

§9  派生信号：地址边界与 locked active 计数
--------------------------------------------

职责：address coverage 和 multi-region coverage 使用地址对齐、地址极值、相邻 TOR、locked
active 与 locked region 数量等派生信号。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L239-L275``）：

.. code-block:: systemverilog

   // Address alignment indicators per region
   logic [PMPNumRegions-1:0] addr_4byte_aligned;
   logic [PMPNumRegions-1:0] addr_page_aligned;   // 4KB boundary
   logic [PMPNumRegions-1:0] addr_is_zero;
   logic [PMPNumRegions-1:0] addr_is_max;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_addr_align
     assign addr_4byte_aligned[r] = (pmp_addr[r][1:0] == 2'b00);
     assign addr_page_aligned[r]  = (pmp_addr[r][11:0] == 12'h000);
     assign addr_is_zero[r]       = (pmp_addr[r] == 32'h0);
     assign addr_is_max[r]        = (pmp_addr[r] == 32'hFFFFFFFF);
   end
   
   // TOR: region[i] lower bound is pmpaddr[i-1] (or 0 for region 0)
   // Adjacent TOR regions: check if region i and i+1 are both TOR
   logic [PMPNumRegions-2:0] adjacent_tor;
   for (genvar r = 0; r < PMPNumRegions-1; r++) begin : g_adj_tor
     assign adjacent_tor[r] = (pmp_cfg_mode[r]   == PMP_MODE_TOR) &&
                              (pmp_cfg_mode[r+1] == PMP_MODE_TOR);
   end

逐段解释：

* 第 239~248 行：每个 region 生成 4 byte aligned、4 KB page aligned、address zero、
  address max 四类标志。
* 第 251~257 行：``adjacent_tor`` 对相邻 region 判断二者是否都为 TOR mode。

接口关系：

* 被调用：``pmp_addr_match_cg``、``pmp_boundary_cg``、``pmp_addr_pattern_cg``。
* 调用：连续赋值。
* 共享状态：``addr_4byte_aligned``、``addr_page_aligned``、``addr_is_zero``、
  ``addr_is_max``、``adjacent_tor``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L259-L275``）：

.. code-block:: systemverilog

   // =========================================================================
   // Locked region with non-OFF mode
   // =========================================================================
   logic [PMPNumRegions-1:0] locked_and_active;
   for (genvar r = 0; r < PMPNumRegions; r++) begin : g_lock_active
     assign locked_and_active[r] = pmp_cfg_lock[r] && region_active[r];
   end
   
   // Count of locked active regions
   logic [$clog2(PMPNumRegions+1)-1:0] num_locked_regions;
   always_comb begin
     num_locked_regions = '0;
     for (int r = 0; r < PMPNumRegions; r++) begin
       num_locked_regions = num_locked_regions + {{($clog2(PMPNumRegions+1)-1){1'b0}}, locked_and_active[r]};
     end
   end

逐段解释：

* 第 262~265 行：``locked_and_active`` 只有在 lock bit 为 1 且 region active 时为 1。
* 第 268~274 行：``num_locked_regions`` 在 combinational block 中累加 locked active region 数。
* 第 275 行：结束 locked region 计数 block。

接口关系：

* 被调用：``pmp_multi_region_cg``、``pmp_region_ext_cg`` 和 ePMP region coverage。
* 调用：连续赋值和 ``always_comb``。
* 共享状态：``pmp_cfg_lock``、``region_active``、``locked_and_active``、``num_locked_regions``。

§10  ``g_pmp_fcov`` generate 条件
---------------------------------

职责：所有 PMP covergroup 都位于 ``if (PMPEnable) begin : g_pmp_fcov`` 内。``PMPEnable=0``
时，后续 covergroup 不生成。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L276-L324``）：

.. code-block:: systemverilog

   if (PMPEnable) begin : g_pmp_fcov
   
     // =========================================================================
     // Per-region configuration coverage (existing)
     // =========================================================================
     for (genvar i = 0; i < PMPNumRegions; i++) begin : g_region_cg
   
       pmp_priv_bits_e region_priv_bits;
       assign region_priv_bits = pmp_priv_bits_e'({mseccfg_mml,
                                                    pmp_cfg_lock[i],
                                                    pmp_cfg_exec[i],
                                                    pmp_cfg_write[i],
                                                    pmp_cfg_read[i]});
   
       covergroup pmp_region_cg @(posedge clk_i);
         option.per_instance = 1;
         option.name = $sformatf("pmp_region_%0d_cg", i);
   
         // PMP mode
         cp_mode: coverpoint pmp_cfg_mode[i] {
           bins off   = {PMP_MODE_OFF};
           bins tor   = {PMP_MODE_TOR};
           bins na4   = {PMP_MODE_NA4};
           bins napot = {PMP_MODE_NAPOT};

逐段解释：

* 第 276 行：``PMPEnable`` 控制整个 PMP coverage generate block。
* 第 281 行：每个 PMP region 生成一组 ``pmp_region_cg``。
* 第 283~288 行：``region_priv_bits`` 把 MML、lock、exec、write、read 拼成
  ``pmp_priv_bits_e``。
* 第 290~299 行：基础 region coverage 的第一个 coverpoint 是 ``pmp_cfg_mode[i]``，覆盖
  OFF、TOR、NA4、NAPOT。
* 第 302~323 行：源码继续覆盖 permission bits、lock，并实例化 ``region_cg_inst``。

接口关系：

* 被调用：elaboration 阶段按 ``PMPEnable`` 生成。
* 调用：covergroup 声明与 ``new``。
* 共享状态：``PMPEnable``、``PMPNumRegions``、``pmp_cfg_mode``、``pmp_cfg_*``、
  ``mseccfg_mml``。

§11  ``pmp_region_cg`` 基础 region 配置
---------------------------------------

职责：每个 region 的基础覆盖包括 mode、permission bits、lock，以及 mode/lock 和
mode/permission cross。OFF mode 下的 permission cross 被 ignore。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L302-L324``）：

.. code-block:: systemverilog

       // Permission bits (with MML encoding)
       cp_priv_bits: coverpoint region_priv_bits {
         wildcard illegal_bins illegal = {5'b0??10};
       }
   
       // Lock bit
       cp_lock: coverpoint pmp_cfg_lock[i] {
         bins locked   = {1};
         bins unlocked = {0};
       }
   
       // Mode x lock cross
       mode_lock_cross: cross cp_mode, cp_lock;
   
       // Mode x permission cross
       mode_priv_cross: cross cp_mode, cp_priv_bits {
         ignore_bins off_with_priv = binsof(cp_mode) intersect {PMP_MODE_OFF};
       }
     endgroup
   
     pmp_region_cg region_cg_inst;
     initial region_cg_inst = new();

逐段解释：

* 第 303~305 行：``cp_priv_bits`` 采样拼接后的权限枚举，并把 ``5'b0??10`` 标成 illegal bins。
* 第 308~311 行：``cp_lock`` 覆盖 lock/unlocked。
* 第 314 行：``mode_lock_cross`` 交叉 mode 与 lock。
* 第 317~319 行：``mode_priv_cross`` 交叉 mode 与权限；OFF mode 对应的权限组合被 ignore。
* 第 322~323 行：声明并创建每区域 ``pmp_region_cg`` 实例。

接口关系：

* 被调用：``g_region_cg`` 每个 genvar 实例。
* 调用：covergroup ``new``。
* 共享状态：``region_priv_bits``、``pmp_cfg_lock[i]``、``pmp_cfg_mode[i]``。

§12  ``pmp_access_cg`` fault 与 debug 覆盖
------------------------------------------

职责：``pmp_access_cg`` 覆盖 instruction-side fault、data-side fault 和 debug mode，并交叉
fault 与 debug。data-side fault coverpoint 受 ``data_req`` 约束。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L330-L360``）：

.. code-block:: systemverilog

   covergroup pmp_access_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_access_cg";
   
     // Instruction-side PMP error
     cp_iside_err: coverpoint pmp_iside_err {
       bins no_error = {0};
       bins error    = {1};
     }
   
     // Data-side PMP error
     cp_dside_err: coverpoint pmp_dside_err iff (data_req) {
       bins no_error = {0};
       bins error    = {1};
     }
   
     // Debug mode during access
     cp_debug_mode: coverpoint debug_mode {
       bins in_debug    = {1};
       bins not_debug   = {0};
     }
   
     // Iside error x debug mode
     iside_debug_cross: cross cp_iside_err, cp_debug_mode;

逐段解释：

* 第 330~332 行：声明 ``pmp_access_cg``，实例名为 ``pmp_access_cg``。
* 第 335~338 行：``cp_iside_err`` 覆盖 instruction-side 无 fault 与 fault。
* 第 341~344 行：``cp_dside_err`` 只在 ``data_req`` 为真时采样。
* 第 347~350 行：``cp_debug_mode`` 覆盖 debug mode 与非 debug mode。
* 第 353~356 行：源码交叉 iside/debug 与 dside/debug。
* 第 359~360 行：声明并创建 ``access_cg_inst``。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``pmp_iside_err``、``pmp_dside_err``、``data_req``、``debug_mode``。

§13  ``pmp_warl_cg`` NAPOT size 编码
------------------------------------

职责：``pmp_warl_cg`` 针对 region 0 的 NAPOT 模式采样 ``pmp_addr[0][31:2]`` 的
``$countones``，用 bins 表达 NAPOT size 编码。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L366-L407``）：

.. code-block:: systemverilog

   covergroup pmp_warl_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_warl_cg";
   
     // PMP address write - NAPOT address patterns
     // In NAPOT mode, the address encodes the region size via trailing ones
     cp_napot_size: coverpoint $countones(pmp_addr[0][31:2]) iff (pmp_cfg_mode[0] == PMP_MODE_NAPOT) {
       bins size_8B    = {30};   // 8 byte region
       bins size_16B   = {29};   // 16 byte region
       bins size_32B   = {28};
       bins size_64B   = {27};
       bins size_128B  = {26};
       bins size_256B  = {25};
       bins size_512B  = {24};
       bins size_1KB   = {23};
       bins size_2KB   = {22};
       bins size_4KB   = {21};
       bins size_8KB   = {20};
       bins size_16KB  = {19};
       bins size_32KB  = {18};

逐段解释：

* 第 366~368 行：声明 ``pmp_warl_cg``。
* 第 370~372 行：coverpoint 在 region 0 为 NAPOT mode 时采样 ``$countones(pmp_addr[0][31:2])``。
* 第 373~402 行：bins 从 ``size_8B`` 到 ``size_4GB``，用 countones 值区分。
* 第 404~407 行：结束 covergroup 并创建 ``warl_cg_inst``。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：``$countones``、covergroup ``new``。
* 共享状态：``pmp_addr[0]``、``pmp_cfg_mode[0]``。

§14  ``pmp_epmp_cg`` ePMP bits 与 fault cross
---------------------------------------------

职责：``pmp_epmp_cg`` 覆盖 ``mseccfg_mml``、``mseccfg_mmwp``、``mseccfg_rlb`` 三个 ePMP
policy bits，并把 MML/MMWP/RLB 与 fault 交叉。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L412-L448``）：

.. code-block:: systemverilog

   covergroup pmp_epmp_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_epmp_cg";
   
     // MML (Machine Mode Lockdown)
     cp_mml: coverpoint mseccfg_mml {
       bins enabled  = {1};
       bins disabled = {0};
     }
   
     // MMWP (Machine Mode Whitelist Policy)
     cp_mmwp: coverpoint mseccfg_mmwp {
       bins enabled  = {1};
       bins disabled = {0};
     }
   
     // RLB (Rule Locking Bypass)
     cp_rlb: coverpoint mseccfg_rlb {
       bins enabled  = {1};
       bins disabled = {0};
     }

逐段解释：

* 第 412~414 行：声明 ``pmp_epmp_cg``。
* 第 416~420 行：``cp_mml`` 覆盖 Machine Mode Lockdown enable/disable。
* 第 422~426 行：``cp_mmwp`` 覆盖 Machine Mode Whitelist Policy enable/disable。
* 第 428~432 行：``cp_rlb`` 覆盖 Rule Locking Bypass enable/disable。
* 第 434~444 行：源码继续定义 MML/MMWP cross、三 bit cross，以及 ePMP bits 与 iside/dside
  fault cross。
* 第 447~448 行：创建 ``epmp_cg_inst``。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``mseccfg_mml``、``mseccfg_mmwp``、``mseccfg_rlb``、``pmp_iside_err``、
  ``pmp_dside_err``、``data_req``。

§15  ``pmp_region_ext_cg`` 每区域扩展配置
-----------------------------------------

职责：``pmp_region_ext_cg`` 对每个 region 展开 mode、RWX、单独 R/W/X bit、lock、active
和 locked-active 覆盖，并交叉 mode/RWX/lock。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L454-L481``）：

.. code-block:: systemverilog

   for (genvar i = 0; i < PMPNumRegions; i++) begin : g_region_ext_cg
   
     covergroup pmp_region_ext_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = $sformatf("pmp_region_ext_%0d_cg", i);
   
       // -----------------------------------------------------------------
       // PMP mode per region
       // -----------------------------------------------------------------
       cp_mode: coverpoint pmp_cfg_mode[i] {
         bins off   = {PMP_MODE_OFF};
         bins tor   = {PMP_MODE_TOR};
         bins na4   = {PMP_MODE_NA4};
         bins napot = {PMP_MODE_NAPOT};
       }
   
       // RWX permission bits (non-MML, decomposed 3-bit view)
       cp_rwx: coverpoint pmp_cfg_rwx[i] {
         bins no_access  = {3'b000};
         bins read_only  = {3'b001};
         bins write_only = {3'b010};  // illegal per spec but should be covered

逐段解释：

* 第 454~458 行：每个 region 生成一个扩展 covergroup，实例名带 region index。
* 第 463~468 行：``cp_mode`` 覆盖 OFF、TOR、NA4、NAPOT。
* 第 473~481 行：``cp_rwx`` 覆盖 8 种 3 bit RWX 组合，包括源码注释标记为 illegal per spec 的
  write-only 和 write-exec。

接口关系：

* 被调用：``PMPEnable`` 为 1 时按 region 生成。
* 调用：``$sformatf``、covergroup ``new``。
* 共享状态：``pmp_cfg_mode[i]``、``pmp_cfg_rwx[i]``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L487-L554``）：

.. code-block:: systemverilog

       cp_read: coverpoint pmp_cfg_read[i] {
         bins set   = {1};
         bins clear = {0};
       }
   
       cp_write: coverpoint pmp_cfg_write[i] {
         bins set   = {1};
         bins clear = {0};
       }
   
       cp_exec: coverpoint pmp_cfg_exec[i] {
         bins set   = {1};
         bins clear = {0};
       }
   
       cp_lock: coverpoint pmp_cfg_lock[i] {
         bins locked   = {1};
         bins unlocked = {0};
       }
   
       mode_rwx_cross: cross cp_mode, cp_rwx {
         ignore_bins off_any_rwx = binsof(cp_mode) intersect {PMP_MODE_OFF};
       }

逐段解释：

* 第 487~500 行：分别覆盖 read、write、exec 三个权限 bit 的 set/clear。
* 第 505~508 行：覆盖 lock/unlocked。
* 第 514~516 行：``mode_rwx_cross`` 交叉 mode 与 RWX，并忽略 OFF mode 下的 RWX 组合。
* 第 521~533 行：源码继续交叉 mode/lock、RWX/lock 和 mode/RWX/lock，OFF mode 下 full
  cross 被 ignore。
* 第 539~554 行：源码继续覆盖 ``region_active`` 与 ``locked_and_active``，并创建实例。

接口关系：

* 被调用：``g_region_ext_cg``。
* 调用：covergroup ``new``。
* 共享状态：``pmp_cfg_read/write/exec/lock``、``region_active``、``locked_and_active``。

§16  ``pmp_access_type_cg`` access type x fault
------------------------------------------------

职责：``pmp_access_type_cg`` 使用 ``inferred_access_type`` 区分 exec/load/store，并与 any
fault、debug mode 以及 simultaneous fault 组合。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L562-L629``）：

.. code-block:: systemverilog

   covergroup pmp_access_type_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_access_type_cg";
   
     // Inferred access type
     cp_access_type: coverpoint inferred_access_type {
       bins exec  = {ACCESS_EXEC};
       bins load  = {ACCESS_LOAD};
       bins store = {ACCESS_STORE};  // enabled by is_load signal (issue 68)
       ignore_bins none = {ACCESS_NONE};
     }
   
     // Instruction-side fault
     cp_iside_fault: coverpoint pmp_iside_err {
       bins no_fault = {0};
       bins fault    = {1};
     }
   
     // Data-side fault
     cp_dside_fault: coverpoint pmp_dside_err iff (data_req) {
       bins no_fault = {0};
       bins fault    = {1};

逐段解释：

* 第 562~564 行：声明 ``pmp_access_type_cg``。
* 第 569~574 行：``cp_access_type`` 覆盖 exec/load/store，并 ignore ``ACCESS_NONE``。
* 第 579~590 行：分别覆盖 iside fault 和受 ``data_req`` 约束的 dside fault。
* 第 595~618 行：源码继续覆盖 any fault、debug mode、access/fault cross、access/debug cross
  和 access/fault/debug cross。
* 第 623~628 行：``cp_simultaneous_faults`` 覆盖 no fault、iside only、dside only 和 both faults。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``inferred_access_type``、``pmp_iside_err``、``pmp_dside_err``、``data_req``、
  ``pmp_any_fault``、``debug_mode``。

§17  ``pmp_addr_match_cg`` 与 ``pmp_multi_region_cg``
-----------------------------------------------------

职责：``pmp_addr_match_cg`` 每区域覆盖 active、地址极值、对齐和 fault；``pmp_multi_region_cg``
覆盖 active/locked region 数量和这些数量与 fault、MML、debug 的组合。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L638-L718``）：

.. code-block:: systemverilog

   for (genvar i = 0; i < PMPNumRegions; i++) begin : g_addr_match_cg
   
     covergroup pmp_addr_match_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = $sformatf("pmp_addr_match_%0d_cg", i);
   
       // Region active (mode != OFF)
       cp_active: coverpoint region_active[i] {
         bins active   = {1};
         bins inactive = {0};
       }
   
       // Address register is zero
       cp_addr_zero: coverpoint addr_is_zero[i] {
         bins zero     = {1};
         bins nonzero  = {0};
       }
   
       // Address register is max (0xFFFFFFFF)
       cp_addr_max: coverpoint addr_is_max[i] {
         bins max      = {1};
         bins not_max  = {0};

逐段解释：

* 第 638~642 行：每个 region 生成一个 address match covergroup。
* 第 647~650 行：覆盖 region active/inactive。
* 第 655~666 行：覆盖 address zero 和 max。
* 第 671~682 行：源码继续覆盖 4 byte aligned 和 page aligned。
* 第 687~699 行：源码继续交叉 active 与 iside/dside error。
* 第 704~713 行：源码继续覆盖 mode，并交叉 address zero 与 mode，OFF mode 被 ignore。
* 第 716~718 行：创建 per-region ``addr_match_cg_inst``。

接口关系：

* 被调用：``PMPEnable`` 为 1 时按 region 生成。
* 调用：``$sformatf``、covergroup ``new``。
* 共享状态：``region_active``、``addr_is_zero``、``addr_is_max``、``addr_4byte_aligned``、
  ``addr_page_aligned``、``pmp_iside_err``、``pmp_dside_err``、``pmp_cfg_mode``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L725-L807``）：

.. code-block:: systemverilog

   covergroup pmp_multi_region_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_multi_region_cg";
   
     // Number of active regions (mode != OFF)
     cp_num_active: coverpoint num_active_regions {
       bins zero  = {0};
       bins one   = {1};
       bins two   = {2};
       bins three = {3};
       bins four  = {4};
       bins more  = {[5:$]};
     }
   
     // Number of locked active regions
     cp_num_locked: coverpoint num_locked_regions {
       bins zero  = {0};
       bins one   = {1};
       bins two   = {2};
       bins three = {3};
       bins four  = {4};
       bins more  = {[5:$]};
     }

逐段解释：

* 第 725~727 行：声明 ``pmp_multi_region_cg``。
* 第 732~739 行：``cp_num_active`` 覆盖 0、1、2、3、4 和 5 以上 active region。
* 第 744~751 行：``cp_num_locked`` 覆盖 0、1、2、3、4 和 5 以上 locked active region。
* 第 756~786 行：源码继续交叉 active/locked counts 与 fault、MML、debug。
* 第 791~803 行：源码继续覆盖 all off 与 all locked。
* 第 806~807 行：创建 ``multi_region_cg_inst``。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``num_active_regions``、``num_locked_regions``、``pmp_any_fault``、
  ``mseccfg_mml``、``debug_mode``。

§18  ``pmp_boundary_cg`` 地址边界
---------------------------------

职责：``pmp_boundary_cg`` 聚焦 region 0 的地址极值、相邻 TOR、mode/address cross、
NAPOT page alignment、TOR upper bound 与地址高位 quadrant。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L813-L888``）：

.. code-block:: systemverilog

   covergroup pmp_boundary_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_boundary_cg";
   
     // Region 0 NAPOT trailing ones (region size indicator)
     // Already covered in pmp_warl_cg; here we add addr[0] extreme cases
     cp_r0_addr_zero: coverpoint addr_is_zero[0] {
       bins zero    = {1};
       bins nonzero = {0};
     }
   
     cp_r0_addr_max: coverpoint addr_is_max[0] {
       bins max     = {1};
       bins not_max = {0};
     }
   
     // TOR adjacent regions: region i and i+1 both TOR
     cp_adj_tor_01: coverpoint adjacent_tor[0] {
       bins adjacent     = {1};
       bins not_adjacent = {0};
     }

逐段解释：

* 第 813~815 行：声明 ``pmp_boundary_cg``。
* 第 821~829 行：覆盖 region 0 address zero 和 max。
* 第 834~837 行：覆盖 region 0/1 相邻 TOR 条件。
* 第 842~855 行：源码继续覆盖 region 0 mode，并交叉 address zero/max 与 mode。
* 第 860~874 行：源码继续覆盖 NAPOT page alignment 和 TOR upper bound 是否非零。
* 第 879~888 行：源码继续覆盖 ``pmp_addr[0][31:30]`` 四个地址 quadrant，并创建实例。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``addr_is_zero``、``addr_is_max``、``adjacent_tor``、``pmp_cfg_mode``、
  ``addr_page_aligned``、``pmp_addr``。

§19  ``pmp_region_prio_cg`` first-match 场景
--------------------------------------------

职责：``pmp_region_prio_cg`` 覆盖前四个 region 的 mode 组合、第一 active region 的 RWX 和
lock，以及第一 active RWX 与 fault 的 cross。源码注释说明 PMP 中最低编号匹配 region 胜出。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L890-L945``）：

.. code-block:: systemverilog

   // NEW: Region Priority / First-match Coverage
   // In PMP, the lowest-numbered matching region wins. Track scenarios
   // where multiple regions could match (all active) to verify priority.
   // =========================================================================
   covergroup pmp_region_prio_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_region_prio_cg";
   
     // Per-region mode vector (first 4 regions)
     cp_r0_mode: coverpoint pmp_cfg_mode[0] {
       bins off   = {PMP_MODE_OFF};
       bins tor   = {PMP_MODE_TOR};
       bins na4   = {PMP_MODE_NA4};
       bins napot = {PMP_MODE_NAPOT};
     }
   
     cp_r1_mode: coverpoint pmp_cfg_mode[1 % PMPNumRegions] {
       bins off   = {PMP_MODE_OFF};
       bins tor   = {PMP_MODE_TOR};

逐段解释：

* 第 890~893 行：源码注释说明该 covergroup 用于 region priority/first-match 覆盖。
* 第 895~897 行：声明 ``pmp_region_prio_cg``。
* 第 902~928 行：定义 r0、r1、r2、r3 四个 mode coverpoint；r1/r2/r3 使用
  ``% PMPNumRegions`` 索引。
* 第 934~945 行：源码交叉 r0/r1 和四个 region 的 mode，四 region 全 OFF 被 ignore。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``pmp_cfg_mode``、``PMPNumRegions``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L947-L992``）：

.. code-block:: systemverilog

   // Priority: first active region's permission
   // Which RWX does the lowest-numbered active region have?
   cp_first_active_rwx: coverpoint
       region_active[0]                           ? pmp_cfg_rwx[0] :
       region_active[1 % PMPNumRegions]           ? pmp_cfg_rwx[1 % PMPNumRegions] :
       region_active[2 % PMPNumRegions]           ? pmp_cfg_rwx[2 % PMPNumRegions] :
       region_active[3 % PMPNumRegions]           ? pmp_cfg_rwx[3 % PMPNumRegions] :
       3'b000 {
     bins no_access  = {3'b000};
     bins read_only  = {3'b001};
     bins write_only = {3'b010};
     bins read_write = {3'b011};
     bins exec_only  = {3'b100};
     bins read_exec  = {3'b101};
     bins write_exec = {3'b110};
     bins all_access = {3'b111};
   }

逐段解释：

* 第 947~956 行：``cp_first_active_rwx`` 以最低编号 active region 的 RWX 为采样值；没有
  active region 时落到 ``3'b000``。
* 第 957~965 行：覆盖 8 种 RWX 组合。
* 第 970~978 行：源码继续以同样优先级选择第一 active region 的 lock 状态。
* 第 983~988 行：源码继续定义 any fault，并交叉 first active RWX 与 fault。
* 第 991~992 行：创建 ``region_prio_cg_inst``。

接口关系：

* 被调用：``pmp_region_prio_cg``。
* 调用：条件表达式、covergroup ``new``。
* 共享状态：``region_active``、``pmp_cfg_rwx``、``pmp_cfg_lock``、``pmp_any_fault``。

§20  ``pmp_napot_per_region_cg`` 每区域 NAPOT size
--------------------------------------------------

职责：``pmp_napot_per_region_cg`` 把 region 0 的 WARL NAPOT size 覆盖扩展到每个 region。
它使用前面派生的 ``napot_trailing_ones[i]``，只在该 region 为 NAPOT mode 时采样。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L994-L1073``）：

.. code-block:: systemverilog

   for (genvar i = 0; i < PMPNumRegions; i++) begin : g_napot_per_region_cg
   
     covergroup pmp_napot_per_region_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = $sformatf("pmp_napot_region_%0d_cg", i);
   
       // NAPOT trailing ones count (region size encoding)
       // Only meaningful when mode == NAPOT
       cp_napot_trailing: coverpoint napot_trailing_ones[i]
         iff (pmp_cfg_mode[i] == PMP_MODE_NAPOT) {
         bins size_8B     = {0};    // no trailing ones => 8B
         bins size_16B    = {1};
         bins size_32B    = {2};
         bins size_64B    = {3};
         bins size_128B   = {4};
         bins size_256B   = {5};
         bins size_512B   = {6};
         bins size_1KB    = {7};
         bins size_2KB    = {8};

逐段解释：

* 第 998~1003 行：每个 region 生成一个 ``pmp_napot_per_region_cg``，名称包含 region index。
* 第 1008~1040 行：``cp_napot_trailing`` 只在该 region 为 NAPOT 时采样 trailing ones 数，bins
  从 8 B 到 4 GB，并包含 ``larger``。
* 第 1046~1051 行：源码继续覆盖 lock，并交叉 NAPOT size 与 lock。
* 第 1056~1067 行：源码继续覆盖 NAPOT mode 下的 RWX，并交叉 NAPOT size 与 RWX。
* 第 1070~1071 行：创建每 region 实例。

接口关系：

* 被调用：``PMPEnable`` 为 1 时按 region 生成。
* 调用：``$sformatf``、covergroup ``new``。
* 共享状态：``napot_trailing_ones``、``pmp_cfg_mode``、``pmp_cfg_lock``、``pmp_cfg_rwx``。

§21  ``pmp_epmp_region_cg`` ePMP x region config
-------------------------------------------------

职责：``pmp_epmp_region_cg`` 交叉 ePMP policy bits 与 region 0 mode、lock、RWX、active
region 数和 fault。该 covergroup 聚焦 ePMP policy 对 region config 语义的组合覆盖。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1079-L1124``）：

.. code-block:: systemverilog

   covergroup pmp_epmp_region_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_epmp_region_cg";
   
     // ePMP bits
     cp_mml: coverpoint mseccfg_mml {
       bins enabled  = {1};
       bins disabled = {0};
     }
   
     cp_mmwp: coverpoint mseccfg_mmwp {
       bins enabled  = {1};
       bins disabled = {0};
     }
   
     cp_rlb: coverpoint mseccfg_rlb {
       bins enabled  = {1};
       bins disabled = {0};
     }
   
     // Region 0 config under ePMP

逐段解释：

* 第 1079~1081 行：声明 ``pmp_epmp_region_cg``。
* 第 1086~1099 行：覆盖 MML、MMWP、RLB 的 enable/disable。
* 第 1104~1124 行：源码继续覆盖 region 0 mode、lock 和 RWX。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``mseccfg_mml``、``mseccfg_mmwp``、``mseccfg_rlb``、``pmp_cfg_mode[0]``、
  ``pmp_cfg_lock[0]``、``pmp_cfg_rwx[0]``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1126-L1197``）：

.. code-block:: systemverilog

     // MML x region 0 mode
     mml_r0_mode_cross: cross cp_mml, cp_r0_mode;
   
     // MML x region 0 lock
     mml_r0_lock_cross: cross cp_mml, cp_r0_lock;
   
     // MML x region 0 RWX
     mml_r0_rwx_cross: cross cp_mml, cp_r0_rwx;
   
     // MMWP x region 0 mode (whitelist policy affects matching)
     mmwp_r0_mode_cross: cross cp_mmwp, cp_r0_mode;
   
     // RLB x region 0 lock (bypass vs lock interaction)
     rlb_r0_lock_cross: cross cp_rlb, cp_r0_lock;
   
     // Full ePMP config x region 0 mode
     epmp_full_r0_mode_cross: cross cp_mml, cp_mmwp, cp_rlb, cp_r0_mode;

逐段解释：

* 第 1129~1139 行：MML 分别与 region 0 mode、lock、RWX 交叉。
* 第 1144~1149 行：MMWP 与 region 0 mode 交叉，RLB 与 region 0 lock 交叉。
* 第 1154 行：三 ePMP bits 与 region 0 mode 全交叉。
* 第 1159~1161 行：源码继续定义 MML/lock/RWX cross，且 ignore MML 关闭组合。
* 第 1166~1176 行：源码继续覆盖 active region 数，并与 MML/MMWP 交叉。
* 第 1181~1193 行：源码继续覆盖 iside/dside fault，并与 MML/MMWP/RLB 全交叉。
* 第 1196~1197 行：创建 ``epmp_region_cg_inst``。

接口关系：

* 被调用：``pmp_epmp_region_cg``。
* 调用：covergroup ``new``。
* 共享状态：``cp_mml``、``cp_mmwp``、``cp_rlb``、``cp_r0_*``、``num_active_regions``、
  ``pmp_iside_err``、``pmp_dside_err``。

§22  ``pmp_addr_pattern_cg`` 地址寄存器 bit pattern
----------------------------------------------------

职责：``pmp_addr_pattern_cg`` 覆盖 pmpaddr 的高/低 nibble、特殊 bit pattern、TOR range
有效性、低位组合和 popcount。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1203-L1295``）：

.. code-block:: systemverilog

   covergroup pmp_addr_pattern_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_addr_pattern_cg";
   
     // Region 0 address upper nibble (memory region selection)
     cp_r0_upper_nibble: coverpoint pmp_addr[0][31:28] {
       bins nibble[] = {[0:15]};
     }
   
     // Region 0 address lower nibble
     cp_r0_lower_nibble: coverpoint pmp_addr[0][3:0] {
       bins nibble[] = {[0:15]};
     }
   
     // Region 0: all zeros, all ones, alternating patterns
     cp_r0_special: coverpoint pmp_addr[0] {
       bins zero     = {32'h00000000};
       bins max      = {32'hFFFFFFFF};
       bins alt_01   = {32'h55555555};

逐段解释：

* 第 1203~1205 行：声明 ``pmp_addr_pattern_cg``。
* 第 1210~1218 行：覆盖 region 0 address 高 nibble 和低 nibble。
* 第 1224~1231 行：覆盖 region 0 address 的 zero、max、交替 bit、低半字、高半字和 default。
* 第 1237~1249 行：源码继续覆盖 region 1 upper nibble 与 special patterns。
* 第 1255~1268 行：源码继续覆盖 TOR 有效 range 和 TOR region 0 是否从 0 开始。
* 第 1274~1290 行：源码继续覆盖 region 0 低 2 bit 和 ``$countones(pmp_addr[0])``。
* 第 1294~1295 行：创建 ``addr_pattern_cg_inst``。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：``$countones``、covergroup ``new``。
* 共享状态：``pmp_addr``、``pmp_cfg_mode``、``addr_is_zero``。

§23  ``pmp_cfg_transition_cg`` 配置变化
---------------------------------------

职责：``pmp_cfg_transition_cg`` 覆盖 mode、lock、RWX 和 ePMP config 的变化，并把变化与 fault
交叉。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1302-L1365``）：

.. code-block:: systemverilog

   covergroup pmp_cfg_transition_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pmp_cfg_transition_cg";
   
     // Region 0: mode transition
     cp_r0_mode_changed: coverpoint mode_changed[0] {
       bins changed   = {1};
       bins unchanged = {0};
     }
   
     cp_r0_mode_prev: coverpoint pmp_cfg_mode_prev[0] {
       bins off   = {PMP_MODE_OFF};
       bins tor   = {PMP_MODE_TOR};
       bins na4   = {PMP_MODE_NA4};
       bins napot = {PMP_MODE_NAPOT};
     }
   
     cp_r0_mode_curr: coverpoint pmp_cfg_mode[0] {
       bins off   = {PMP_MODE_OFF};
       bins tor   = {PMP_MODE_TOR};

逐段解释：

* 第 1302~1304 行：声明 ``pmp_cfg_transition_cg``。
* 第 1309~1312 行：覆盖 region 0 mode 是否变化。
* 第 1314~1326 行：覆盖 region 0 前一拍 mode 和当前 mode。
* 第 1329~1339 行：源码继续交叉前一拍/current mode，并 ignore 四种 no-change 组合。
* 第 1344~1365 行：源码继续覆盖 lock 是否变化、前一拍 lock、当前 lock，并交叉 lock transition，
  no-change lock 组合被 ignore。

接口关系：

* 被调用：``PMPEnable`` 为 1 时创建。
* 调用：covergroup ``new``。
* 共享状态：``mode_changed``、``pmp_cfg_mode_prev``、``pmp_cfg_mode``、
  ``lock_changed``、``pmp_cfg_lock_prev``、``pmp_cfg_lock``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1367-L1457``）：

.. code-block:: systemverilog

     // Region 0: RWX transition
     cp_r0_rwx_changed: coverpoint rwx_changed[0] {
       bins changed   = {1};
       bins unchanged = {0};
     }
   
     // Lock transition attempt while locked (should be blocked without RLB)
     cp_locked_write_attempt: coverpoint (pmp_cfg_lock_prev[0] && mode_changed[0]) {
       bins write_while_locked = {1};
       bins normal             = {0};
     }
   
     // ePMP config transition
     cp_epmp_changed: coverpoint epmp_config_changed {
       bins changed   = {1};
       bins unchanged = {0};
     }
   
     cp_mml_prev: coverpoint mseccfg_mml_prev {
       bins enabled  = {1};
       bins disabled = {0};

逐段解释：

* 第 1370~1373 行：覆盖 region 0 RWX 是否变化。
* 第 1378~1381 行：覆盖 lock 已经为 1 时又出现 mode change 的写入尝试场景。
* 第 1386~1389 行：覆盖 ePMP config 是否变化。
* 第 1391~1407 行：源码继续覆盖 MML 前一拍/current，并交叉 MML transition，两个 no-change
  组合被 ignore。
* 第 1412~1419 行：源码继续把 mode、lock、RWX 变化与 any fault 交叉。
* 第 1424~1453 行：源码继续覆盖 region 1 的 mode/lock/RWX change 和多 region 同时变化数。
* 第 1456~1457 行：创建 ``cfg_transition_cg_inst``。

接口关系：

* 被调用：``pmp_cfg_transition_cg``。
* 调用：``$countones``、covergroup ``new``。
* 共享状态：``rwx_changed``、``pmp_cfg_lock_prev``、``mode_changed``、
  ``epmp_config_changed``、``mseccfg_mml_prev``、``mseccfg_mml``、``pmp_any_fault``。

§24  PMP/ePMP test classes
--------------------------

职责：test library 中存在 PMP/ePMP test class，但这些 class 只设置 timeout 与 max cycles；
没有在 class 内直接接线 ``u_pmp_fcov_if`` 或修改 ``PMPEnable`` 参数。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1173-L1228``）：

.. code-block:: systemverilog

   // 26. PMP Basic Test - Basic PMP region test
   // ---------------------------------------------------------------------------
   class core_eh2_pmp_basic_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_pmp_basic_test)
   
     function new(string name = "core_eh2_pmp_basic_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       env_cfg.timeout_ns = 64'd5_000_000_000;  // 5s
       env_cfg.max_cycles = 500_000;
     endfunction
   
   endclass

逐段解释：

* 第 1173~1176 行：声明 PMP basic test class。
* 第 1178 行：注册 UVM factory。
* 第 1180~1182 行：构造函数只调用父类构造。
* 第 1184~1188 行：build phase 只设置 ``timeout_ns`` 和 ``max_cycles``。
* 第 1193~1228 行：源码随后定义 ``core_eh2_pmp_disable_test`` 与
  ``core_eh2_pmp_random_test``，同样只设置 timeout 和 max cycles。

接口关系：

* 被调用：UVM test selection。
* 调用：``super.build_phase``。
* 共享状态：``env_cfg.timeout_ns``、``env_cfg.max_cycles``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1307-L1362``）：

.. code-block:: systemverilog

   // 33. ePMP MML Test - Machine Mode Lockdown
   // ---------------------------------------------------------------------------
   class core_eh2_epmp_mml_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_epmp_mml_test)
   
     function new(string name = "core_eh2_epmp_mml_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       env_cfg.timeout_ns = 64'd10_000_000_000;
       env_cfg.max_cycles = 500_000;
     endfunction
   
   endclass

逐段解释：

* 第 1307~1310 行：声明 ePMP MML test class。
* 第 1312 行：注册 UVM factory。
* 第 1318~1322 行：build phase 设置 10 秒 timeout 和 500000 cycle timeout。
* 第 1327~1362 行：源码随后定义 ePMP MMWP 与 RLB test，二者 build phase 也只设置 timeout
  和 max cycles。

接口关系：

* 被调用：UVM test selection。
* 调用：``super.build_phase``。
* 共享状态：``env_cfg.timeout_ns``、``env_cfg.max_cycles``。

§25  与 PMP cosim ADR 的关系
----------------------------

职责：PMP coverage interface 只做覆盖率采样；PMP/ePMP cosim closure 的模型边界由
:ref:`adr-0009` 描述。ADR 0009 与 coverage interface 是不同层面：一个描述 Spike cosim
策略，另一个描述 SystemVerilog coverage scaffold。

关键代码（``docs/adr/0009-pmp-cosim.md:L30-L36``）：

.. code-block:: markdown

   All 6 PMP tests had `cosim: disabled` removed:
   - pmp_basic: 4-region basic PMP
   - pmp_disable_all: All regions disabled (should be equivalent to no PMP)
   - pmp_random: 8 random regions
   - epmp_mml: ePMP Machine Mode Lockdown
   - epmp_mmwp: ePMP Machine Mode Whitelist Policy
   - epmp_rlb: ePMP Rule Locking Bypass

逐段解释：

* 第 30 行：ADR 记录 6 个 PMP/ePMP tests 移除 ``cosim: disabled``。
* 第 31~36 行：列出 basic、disable_all、random、MML、MMWP、RLB 六个测试名称。
* 这些测试名称与 test library 中 ``core_eh2_pmp_*`` 和 ``core_eh2_epmp_*`` 类族相对应，但
  ADR 本身不描述 coverage interface 接线。

接口关系：

* 被调用：文档交叉引用。
* 调用：无代码调用。
* 共享状态：无运行期状态。

§26  当前源码边界与验收含义
----------------------------

本页必须保留两个源码边界：

* ``eh2_pmp_fcov_if.sv`` 本身完整定义 PMP/ePMP coverage scaffold，且所有主要 covergroup 位于
  ``if (PMPEnable) begin : g_pmp_fcov`` 内。
* ``core_eh2_tb_top.sv`` 当前默认实例化使用 ``PMPEnable(1'b0)``，PMP/ePMP 配置与 fault
  信号接常量 0。除 ``debug_mode`` 外，默认实例并没有从 DUT PMP 逻辑采样实际信号。

因此，当前默认平台中的 PMP coverage 章节应被理解为 coverage scaffold 的结构说明，而不是
默认仿真中已打开的 PMP coverage 结果说明。

§27  参考资料
--------------

* :ref:`functional_coverage` — 主功能覆盖率架构说明。
* :ref:`appendix_b_uvm_fcov` — functional coverage 与 PMP coverage 源码字典。
* :ref:`adr-0009` — PMP/ePMP cosim closure 策略。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_if.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv``。
* 源文件绝对路径：``/home/host/eh2-veri/docs/adr/0009-pmp-cosim.md``。

§28  与 Ibex 工业实现对照
-------------------------

Ibex 有 ``core_ibex_pmp_fcov_if.sv`` 和 PMP directed tests，PMP 是 Ibex 安全验证面的
核心组成。EH2 当前保留 ``eh2_pmp_fcov_if`` scaffold，并在 directed/ADR 中记录 PMP/ePMP
closure 策略，但默认 TB 实例 ``PMPEnable=0``。因此 EH2 文档必须区分“coverage 模型已就绪”
与“默认配置已采样 DUT PMP 信号”这两件事。

.. list-table:: PMP coverage 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - coverage interface
     - ``core_ibex_pmp_fcov_if.sv``
     - ``eh2_pmp_fcov_if.sv``
   * - 默认采样
     - 依据 Ibex PMP 配置
     - 当前 TB 默认 ``PMPEnable=0``，scaffold 不等同于默认采样
   * - directed tests
     - ``directed_tests/*pmp*``
     - ``directed_pmp_*`` ASM 与 EH2 PMP/ePMP test classes
   * - cosim
     - RVFI/PMP sideband
     - trace/probe + Spike CSR/memory region 补偿
   * - 文档口径
     - PMP 是核心安全覆盖项
     - 明确区分 scaffold、enabled config 和 sign-off 结果

§29  Sign-off 关联
------------------

当前 2026-05-19 demo 的 GROUP 69.42% 是整体 covergroup 结果，不应被拆读为 PMP
默认采样已完整闭合。PMP/ePMP 的 sign-off 证据来自 directed tests、formal property、
cosim waiver/ADR 和未来 PMP-enabled 配置的 coverage run。若打开 ``PMPEnable`` 或把
``u_pmp_fcov_if`` 接到真实 DUT PMP 信号，应同步更新本章、coverage plan、riscv-dv
testlist 和 sign-off coverage threshold。
