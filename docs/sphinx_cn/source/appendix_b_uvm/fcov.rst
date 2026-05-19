.. _appendix_b_uvm_fcov:
.. _appendix_b_uvm/fcov:

功能覆盖率接口逐段参考
======================

:status: draft
:source: dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1 文件定位与真实边界
--------------------------------------------------------------------------------

本章解释 ``dv/uvm/core_eh2/fcov/`` 下的功能覆盖率 SystemVerilog 文件。
当前实现不是 UVM coverage collector class，而是在 testbench top 中直接实例化
SystemVerilog interface，并通过层次化信号连接 DUT 内部信号。

覆盖率数据流如下：

.. code-block:: text

   core_eh2_tb_top.sv
       |
       +--> eh2_fcov_if u_fcov_if
       |       |
       |       +--> uarch_cg / csr_cg / dual_issue_cg / interrupt_cg
       |       +--> csr_warl_cg / instr_detail_cg
       |       +--> controller_fsm_cg / pipeline_state_cg
       |
       +--> eh2_pmp_fcov_if u_pmp_fcov_if
               |
               +--> active only inside generate block when PMPEnable == 1
               +--> default tb_top instantiation sets PMPEnable = 1'b0

这张图只来自当前源码：``core_eh2_tb_top.sv`` 实例化 ``u_fcov_if`` 和
``u_pmp_fcov_if``；``eh2_fcov_if.sv`` 内部声明 8 个 covergroup 实例；
``eh2_pmp_fcov_if.sv`` 的主要 covergroup 放在 ``if (PMPEnable)`` generate
块内，而当前 top 实例化参数把 ``PMPEnable`` 设为 0。

§1.1 文件清单与 filelist 编译入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``eh2_tb.f`` 把 coverage 目录加入 include path，并把 CSR 分类、通用覆盖率接口、PMP 覆盖率接口和 bind 空实现文件加入编译。

关键代码（``dv/uvm/core_eh2/eh2_tb.f:L46-L51``）：

.. code-block:: text

   // Functional coverage
   +incdir+dv/uvm/core_eh2/fcov
   dv/uvm/core_eh2/fcov/eh2_csr_categories.svh
   dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
   dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv
   dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv

逐段解释：

* 第 L46-L47 行：filelist 明确把 ``dv/uvm/core_eh2/fcov`` 作为 include 目录。
* 第 L48-L51 行：编译顺序先列出 ``eh2_csr_categories.svh``，再列出两个 interface，最后列出 ``eh2_fcov_bind.sv`` 空实现文件。
* 该片段没有把 ``cov_waivers`` package 加入 filelist；waiver package 是同目录下的辅助代码，不在这段 filelist 中出现。

接口关系：

* 被调用：仿真编译命令读取 ``eh2_tb.f``。
* 调用：不调用函数。
* 共享状态：建立 coverage 源文件的编译可见性。

§1.2 bind 文件只保留编译入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``eh2_fcov_bind.sv`` 说明当前不使用 SystemVerilog ``bind`` 做 coverage 连接，真实实例在 ``core_eh2_tb_top.sv``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv:L1-L15``）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 Functional Coverage - Bind Module
   //
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

* 第 L4-L7 行：注释说明 coverage interface 直接在 top 中实例化，原因是 EH2 层次信号跨模块引用不适合由 bind 文件统一到达。
* 第 L9-L11 行：``eh2_fcov_if`` 和 ``eh2_pmp_fcov_if`` 的创建位置是 ``core_eh2_tb_top.sv``，本文件只是 filelist 需要的空实现入口。
* 第 L13-L15 行：注释给出两个实例名 ``u_fcov_if`` 和 ``u_pmp_fcov_if``，与 top 文件中的实例名一致。

接口关系：

* 被调用：filelist 编译该文件。
* 调用：无运行时代码。
* 共享状态：不声明信号，不创建覆盖率实例。

§2 ``eh2_fcov_if`` 接口输入
--------------------------------------------------------------------------------

``eh2_fcov_if`` 是通用微架构覆盖率接口。它采样 decode、E4、TLU、LSU、IFU
PMU、debug 和 interrupt 相关信号。

§2.1 接口头与流水线输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接口头导入 ``eh2_pkg``，并声明 clock/reset、流水线 valid、decode 指令和 decode packet 输入。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L13-L37``）：

.. code-block:: systemverilog

   interface eh2_fcov_if
     import eh2_pkg::*;
   (
     input logic clk_i,
     input logic rst_l_i,

     // -- Pipeline stage valids --
     input logic        dec_ib0_valid_d,
     input logic        dec_ib1_valid_d,
     input logic        dec_i1_valid_e1,
     input logic        dec_tlu_i0_valid_e4,
     input logic        dec_tlu_i1_valid_e4,
     input logic        tlu_i0_commit_cmt,
     input logic        tlu_i1_commit_cmt,

     // -- Instruction at decode --
     input logic [31:0] dec_i0_instr_d,
     input logic [31:0] dec_i1_instr_d,
     input logic        dec_i0_pc4_d,
     input logic        dec_i1_pc4_d,

     // -- Decode packet --
     input eh2_dec_pkt_t i0_dec,
     input eh2_dec_pkt_t i1_dec,

逐段解释：

* 第 L13-L17 行：interface 导入 ``eh2_pkg``，端口包含 ``clk_i`` 和低有效复位 ``rst_l_i``。
* 第 L20-L26 行：流水线 valid 和 commit 信号覆盖 decode input buffer、E4 有效位和 commit。
* 第 L29-L36 行：I0/I1 的 32 位指令、压缩宽度指示和 ``eh2_dec_pkt_t`` decode packet 被作为覆盖分类输入。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 实例化 ``u_fcov_if`` 并连接这些端口。
* 调用：端口声明不调用函数。
* 共享状态：覆盖率函数和 covergroup 读取这些输入。

§2.2 分支、flush、stall、异常和中断输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该端口段把 E4 分支结果、flush 原因、stall 类型、异常类型和中断来源输入到覆盖率接口。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L38-L80``）：

.. code-block:: systemverilog

     // -- Branch signals --
     input logic        exu_pmu_i0_br_misp,
     input logic        exu_pmu_i0_br_ataken,
     input logic        exu_pmu_i1_br_misp,
     input logic        exu_pmu_i1_br_ataken,
     input logic        exu_i0_br_valid_e4,
     input logic        exu_i1_br_valid_e4,
     input logic        exu_i0_br_mp_e4,
     input logic        exu_i1_br_mp_e4,

     // -- Pipeline flushes --
     input logic        exu_flush_final,
     input logic        exu_i0_flush_final,
     input logic        exu_i1_flush_final,
     input logic        dec_tlu_flush_lower_wb,
     input logic        dec_tlu_flush_mp_wb,

     // -- Stall signals --
     input logic        lsu_load_stall_any,
     input logic        lsu_store_stall_any,
     input logic        lsu_amo_stall_any,
     input logic        dec_pmu_decode_stall,
     input logic        dec_pmu_presync_stall,
     input logic        dec_pmu_postsync_stall,

逐段解释：

* 第 L39-L46 行：分支覆盖需要 taken、mispredict 和 branch valid 信号，I0/I1 分别输入。
* 第 L49-L53 行：flush 相关输入用于区分 mispredict、exception 和其它 pipe flush。
* 第 L56-L62 行：stall 输入覆盖 LSU load/store/AMO、decode stall、presync、postsync 和 fetch stall；``get_stall_type()`` 按优先级读取这些信号。

接口关系：

* 被调用：``uarch_cg``、``controller_fsm_cg`` 和 ``pipeline_state_cg`` 读取这些端口。
* 调用：端口声明不调用函数。
* 共享状态：无内部写入。

§2.3 debug、privilege、LSU 与 IFU PMU 输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：尾部端口补充 debug 状态、PIC priority 相关 privilege 字段、LSU PMU 和 IFU cache PMU 事件。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L81-L97``）：

.. code-block:: systemverilog

     // -- Debug --
     input logic        dec_tlu_dbg_halted,
     input logic        dec_tlu_debug_mode,

     // -- Privilege mode (EH2: always M-mode, but check anyway) --
     input logic [3:0]  dec_tlu_meicurpl,
     input logic [3:0]  dec_tlu_meicidpl,

     // -- LSU --
     input logic        lsu_pmu_misaligned_dc3,
     input logic        lsu_pmu_load_external_dc3,
     input logic        lsu_pmu_store_external_dc3,

     // -- PMU --
     input logic        ifu_pmu_ic_miss,
     input logic        ifu_pmu_ic_hit
   );

逐段解释：

* 第 L82-L83 行：debug halted 和 debug mode 分开采样，后续 ``cp_debug_mode`` 与 ``cp_debug_halted`` 分别覆盖。
* 第 L86-L87 行：``dec_tlu_meicurpl`` 和 ``dec_tlu_meicidpl`` 被输入接口；当前 covergroup 片段没有直接使用这两个端口。
* 第 L90-L96 行：LSU misaligned/external load/store 和 IFU icache hit/miss 用于 LSU 与 cache 事件 coverpoint。

接口关系：

* 被调用：``uarch_cg``、``controller_fsm_cg``、``pipeline_state_cg`` 读取其中部分端口。
* 调用：无。
* 共享状态：端口只读。

§3 分类函数
--------------------------------------------------------------------------------

通用覆盖率接口先把 decode packet 映射成较粗粒度的枚举，再由 covergroup 引用函数返回值。

§3.1 指令类别枚举
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``instr_category_e`` 定义 I0/I1 decode packet 被归入的功能类别。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L99-L118``）：

.. code-block:: systemverilog

   // =========================================================================
   // Instruction category classification
   // =========================================================================
   typedef enum {
     InstrCategoryALU,
     InstrCategoryMul,
     InstrCategoryDiv,
     InstrCategoryBranch,
     InstrCategoryJump,
     InstrCategoryLoad,
     InstrCategoryStore,
     InstrCategoryCSRAccess,
     InstrCategoryEBreak,
     InstrCategoryECall,
     InstrCategoryMRet,
     InstrCategoryFence,
     InstrCategoryAtomic,
     InstrCategoryIllegal,
     InstrCategoryNone
   } instr_category_e;

逐段解释：

* 第 L102-L118 行：枚举覆盖 ALU、乘除、分支、跳转、load/store、CSR、ebreak、ecall、mret、fence、atomic、illegal 和 none。
* 枚举没有逐条 ISA 指令级别条目；因此本章不把该接口描述为 opcode/funct3/funct7 级覆盖。

接口关系：

* 被调用：``get_i0_instr_category()``、``get_i1_instr_category()`` 和多个 coverpoint 引用。
* 调用：无。
* 共享状态：无。

§3.2 ``get_i0_instr_category()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数按固定优先级把 I0 decode packet 转换成 ``instr_category_e``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L121-L141``）：

.. code-block:: systemverilog

   function automatic instr_category_e get_i0_instr_category();
     if (!dec_ib0_valid_d) return InstrCategoryNone;

     // Use decode packet for classification
     if (!i0_dec.legal)     return InstrCategoryIllegal;
     if (i0_dec.ebreak)      return InstrCategoryEBreak;
     if (i0_dec.ecall)       return InstrCategoryECall;
     if (i0_dec.mret)        return InstrCategoryMRet;
     if (i0_dec.fence || i0_dec.fence_i) return InstrCategoryFence;
     if (i0_dec.condbr || i0_dec.jal)    return InstrCategoryBranch;
     if (i0_dec.csr_read || i0_dec.csr_write || i0_dec.csr_set || i0_dec.csr_clr)
       return InstrCategoryCSRAccess;
     if (i0_dec.load)        return InstrCategoryLoad;
     if (i0_dec.store)       return InstrCategoryStore;
     if (i0_dec.mul)         return InstrCategoryMul;
     if (i0_dec.div || i0_dec.rem) return InstrCategoryDiv;
     if (i0_dec.atomic)      return InstrCategoryAtomic;

     // Default: ALU (includes bitmanip)
     return InstrCategoryALU;
   endfunction

逐段解释：

* 第 L121-L122 行：I0 decode buffer 无效时直接返回 ``InstrCategoryNone``。
* 第 L125-L132 行：非法、ebreak、ecall、mret、fence、branch/jal、CSR 的判断优先于 load/store/mul/div/atomic。
* 第 L133-L137 行：load、store、mul、div/rem 和 atomic 按顺序匹配。
* 第 L140 行：前面都未匹配时归类为 ``InstrCategoryALU``。

接口关系：

* 被调用：``uarch_cg``、``dual_issue_cg``、``instr_detail_cg``、``pipeline_state_cg`` 间接或直接调用。
* 调用：不调用其它函数。
* 共享状态：读取 ``dec_ib0_valid_d`` 和 ``i0_dec``。

§3.3 ``get_i1_instr_category()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数对 I1 使用与 I0 对称的分类逻辑。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L143-L162``）：

.. code-block:: systemverilog

   // Classify I1 instruction at decode stage
   function automatic instr_category_e get_i1_instr_category();
     if (!dec_ib1_valid_d) return InstrCategoryNone;

     if (!i1_dec.legal)     return InstrCategoryIllegal;
     if (i1_dec.ebreak)      return InstrCategoryEBreak;
     if (i1_dec.ecall)       return InstrCategoryECall;
     if (i1_dec.mret)        return InstrCategoryMRet;
     if (i1_dec.fence || i1_dec.fence_i) return InstrCategoryFence;
     if (i1_dec.condbr || i1_dec.jal)    return InstrCategoryBranch;
     if (i1_dec.csr_read || i1_dec.csr_write || i1_dec.csr_set || i1_dec.csr_clr)
       return InstrCategoryCSRAccess;
     if (i1_dec.load)        return InstrCategoryLoad;
     if (i1_dec.store)       return InstrCategoryStore;
     if (i1_dec.mul)         return InstrCategoryMul;
     if (i1_dec.div || i1_dec.rem) return InstrCategoryDiv;
     if (i1_dec.atomic)      return InstrCategoryAtomic;

     return InstrCategoryALU;
   endfunction

逐段解释：

* 第 L144-L145 行：I1 decode buffer 无效时返回 ``InstrCategoryNone``。
* 第 L147-L154 行：I1 同样先处理非法、trap/return、fence、branch/jal 和 CSR 类。
* 第 L155-L161 行：其余操作依次归类为 load、store、mul、div/rem、atomic，默认 ALU。

接口关系：

* 被调用：I1 category coverpoint 和 I0/I1 cross。
* 调用：不调用其它函数。
* 共享状态：读取 ``dec_ib1_valid_d`` 和 ``i1_dec``。

§3.4 stall 类型枚举与 ``get_stall_type()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：stall 分类函数把多个 stall 输入压缩为一个 ``stall_type_e``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L167-L187``）：

.. code-block:: systemverilog

   typedef enum {
     StallTypeNone,
     StallTypeLoad,
     StallTypeStore,
     StallTypeAMO,
     StallTypeDecode,
     StallTypePresync,
     StallTypePostsync,
     StallTypeFetch
   } stall_type_e;

   function automatic stall_type_e get_stall_type();
     if (lsu_load_stall_any)    return StallTypeLoad;
     if (lsu_store_stall_any)   return StallTypeStore;
     if (lsu_amo_stall_any)     return StallTypeAMO;
     if (dec_pmu_decode_stall)  return StallTypeDecode;
     if (dec_pmu_presync_stall) return StallTypePresync;
     if (dec_pmu_postsync_stall) return StallTypePostsync;
     if (ifu_pmu_fetch_stall)   return StallTypeFetch;
     return StallTypeNone;
   endfunction

逐段解释：

* 第 L167-L176 行：stall 枚举覆盖 none、load、store、AMO、decode、presync、postsync 和 fetch。
* 第 L178-L186 行：函数按 if 语句顺序返回第一个命中的 stall 类型；因此同时多个 stall 输入为 1 时，load 优先于 store，store 优先于 AMO，以此类推。
* 第 L186 行：没有任何 stall 输入命中时返回 ``StallTypeNone``。

接口关系：

* 被调用：``uarch_cg.cp_stall_type`` 和 ``pipeline_state_cg.cp_stall``。
* 调用：无。
* 共享状态：读取多个 stall 输入端口。

§4 ``uarch_cg`` 主微架构覆盖组
--------------------------------------------------------------------------------

``uarch_cg`` 是通用覆盖率接口中的主 covergroup，按 ``posedge clk_i`` 采样。

§4.1 covergroup 头和 I0/I1 指令类别
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：covergroup 设置 per-instance 和名称，并给 I0/I1 指令类别建立 bins。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L212-L253``）：

.. code-block:: systemverilog

   covergroup uarch_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "uarch_cg";

     // -----------------------------------------------------------------------
     // Instruction categories at decode
     // -----------------------------------------------------------------------
     cp_i0_instr_category: coverpoint get_i0_instr_category() {
       bins alu         = {InstrCategoryALU};
       bins mul         = {InstrCategoryMul};
       bins div         = {InstrCategoryDiv};
       bins branch      = {InstrCategoryBranch};
       bins jump        = {InstrCategoryJump};
       bins load        = {InstrCategoryLoad};
       bins store       = {InstrCategoryStore};
       bins csr_access  = {InstrCategoryCSRAccess};
       bins ebreak      = {InstrCategoryEBreak};
       bins ecall       = {InstrCategoryECall};
       bins mret        = {InstrCategoryMRet};
       bins fence       = {InstrCategoryFence};
       bins atomic      = {InstrCategoryAtomic};
       bins illegal     = {InstrCategoryIllegal};
       ignore_bins none = {InstrCategoryNone};
     }

逐段解释：

* 第 L212-L214 行：``uarch_cg`` 每个实例独立统计，名称为 ``uarch_cg``。
* 第 L219-L234 行：I0 coverpoint 调用 ``get_i0_instr_category()``，为 ALU、mul、div、branch、jump、load、store、CSR、ebreak、ecall、mret、fence、atomic、illegal 建 bins，并忽略 none。
* I1 coverpoint 在后续 L237-L253 使用同一组类别，只是调用 ``get_i1_instr_category()``。

接口关系：

* 被调用：covergroup 实例 ``uarch_cg_inst`` 在 initial 块中创建。
* 调用：``get_i0_instr_category()`` 和 ``get_i1_instr_category()``。
* 共享状态：读取 decode packet 和 valid 输入。

§4.2 stall、branch、flush、异常和中断 coverpoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该片段覆盖 stall 类型、branch taken/mispredict、flush 原因、异常类型和中断来源。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L258-L324``）：

.. code-block:: systemverilog

     cp_stall_type: coverpoint get_stall_type() {
       bins none     = {StallTypeNone};
       bins load     = {StallTypeLoad};
       bins store    = {StallTypeStore};
       bins amo      = {StallTypeAMO};
       bins decode   = {StallTypeDecode};
       bins presync  = {StallTypePresync};
       bins postsync = {StallTypePostsync};
       bins fetch    = {StallTypeFetch};
     }

     cp_i0_branch_taken: coverpoint exu_pmu_i0_br_ataken iff (exu_i0_br_valid_e4) {
       bins taken    = {1};
       bins not_taken = {0};
     }

     cp_i0_branch_mispredict: coverpoint exu_pmu_i0_br_misp iff (exu_i0_br_valid_e4) {
       bins mispredict = {1};
       bins correct    = {0};
     }

     cp_flush_type: coverpoint 1 {
       bins mispredict = {1} iff (dec_tlu_flush_mp_wb);
       bins exception  = {1} iff (dec_tlu_flush_lower_wb && !dec_tlu_flush_mp_wb);

逐段解释：

* 第 L258-L267 行：stall coverpoint 直接引用 ``get_stall_type()`` 的返回值，并为每个枚举值建 bin。
* 第 L272-L289 行：I0/I1 branch taken 和 mispredict 都通过 ``iff (exu_i*_br_valid_e4)`` 限定采样窗口；代码片段展示 I0，源文件对 I1 有对称 coverpoint。
* 第 L295-L299 行：flush coverpoint 使用常量 1 和多个 ``iff`` 条件，把 flush 分成 mispredict、exception 和 other。
* 第 L304-L324 行：异常和中断 coverpoint 也使用 ``iff`` 条件，异常覆盖 inst access fault、illegal、ebreak、ecall，中断覆盖 external、timer、software、NMI 和 CE interrupt。

接口关系：

* 被调用：``uarch_cg`` 每个时钟采样。
* 调用：``get_stall_type()``。
* 共享状态：读取 branch、flush、exception、interrupt 输入。

§4.3 debug、dual issue、compressed、cache 和 LSU coverpoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该片段覆盖 debug 状态、双发射、压缩指令宽度、IFU icache 事件和 LSU external/misaligned 事件。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L329-L384``）：

.. code-block:: systemverilog

     cp_debug_mode: coverpoint dec_tlu_debug_mode {
       bins in_debug    = {1};
       bins not_debug   = {0};
     }

     cp_debug_halted: coverpoint dec_tlu_dbg_halted {
       bins halted     = {1};
       bins running    = {0};
     }

     cp_dual_issue: coverpoint (dec_tlu_i0_valid_e4 && dec_tlu_i1_valid_e4) {
       bins dual  = {1};
       bins single = {0};
     }

     cp_i0_compressed: coverpoint dec_i0_pc4_d {
       bins compressed     = {0};
       bins uncompressed   = {1};
     }

     cp_icache_hit: coverpoint ifu_pmu_ic_hit {
       bins hit  = {1};
     }

逐段解释：

* 第 L329-L337 行：debug mode 和 halted 分成两个 coverpoint，分别统计 ``dec_tlu_debug_mode`` 与 ``dec_tlu_dbg_halted``。
* 第 L342-L345 行：双发射覆盖用 E4 的 I0/I1 valid 同时为 1 来判断 dual，否则进入 single bin。
* 第 L350-L358 行：I0/I1 compressed coverpoint 使用 ``dec_i*_pc4_d``，0 归为 compressed，1 归为 uncompressed。
* 第 L363-L384 行：IFU icache hit/miss、LSU external load/store、LSU misaligned 都是单 bit 事件 bin。

接口关系：

* 被调用：``uarch_cg`` 采样。
* 调用：无。
* 共享状态：读取 debug、valid、pc4、IFU PMU、LSU PMU 输入。

§4.4 ``uarch_cg`` cross
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：主 covergroup 的 cross 把指令类别、stall、branch、interrupt/debug、dual-issue、exception 和 compressed 组合起来。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L386-L416``）：

.. code-block:: systemverilog

     // Instruction category x stall type
     stall_cross: cross cp_i0_instr_category, cp_stall_type {
       ignore_bins illegal_stall = binsof(cp_i0_instr_category.illegal);
     }

     // Branch taken x mispredict
     branch_cross: cross cp_i0_branch_taken, cp_i0_branch_mispredict;

     // Interrupt x debug mode
     interrupt_debug_cross: cross cp_interrupt_taken, cp_debug_mode;

     // Dual-issue x I0 category
     dual_issue_cross: cross cp_dual_issue, cp_i0_instr_category;

     // Exception x stall
     exception_stall_cross: cross cp_exception_type, cp_stall_type;

     // I0 x I1 instruction categories (for dual-issue coverage)
     pipe_cross: cross cp_i0_instr_category, cp_i1_instr_category {
       // Only meaningful when both pipes are active
       ignore_bins i1_empty = binsof(cp_i1_instr_category) intersect {InstrCategoryNone};
     }

逐段解释：

* 第 L391-L393 行：``stall_cross`` 交叉 I0 指令类别和 stall 类型，并忽略 illegal 指令类别相关 stall bin。
* 第 L396-L405 行：branch taken/mispredict、interrupt/debug、dual-issue/I0 category、exception/stall 分别形成 cross。
* 第 L408-L411 行：``pipe_cross`` 交叉 I0/I1 指令类别，并忽略 I1 none。
* 第 L414 行：``compressed_dual_cross`` 交叉 I0 compressed、I1 compressed 和 dual issue。

接口关系：

* 被调用：``uarch_cg`` 内部自动采样。
* 调用：无函数调用。
* 共享状态：依赖本 covergroup 内的 coverpoint。

§5 其它通用 covergroup
--------------------------------------------------------------------------------

除 ``uarch_cg`` 外，``eh2_fcov_if`` 还声明 CSR、dual-issue、interrupt、CSR WARL、指令细分、controller FSM 和 pipeline state 覆盖组。

§5.1 ``csr_cg`` 基础 CSR 操作覆盖
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``csr_cg`` 只覆盖 I0 decode packet 中 CSR read/write/set/clear 四类操作。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L421-L432``）：

.. code-block:: systemverilog

   covergroup csr_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "csr_cg";

     // CSR access type
     cp_csr_access_type: coverpoint 1 {
       bins read  = {1} iff (i0_dec.csr_read);
       bins write = {1} iff (i0_dec.csr_write);
       bins set   = {1} iff (i0_dec.csr_set);
       bins clear = {1} iff (i0_dec.csr_clr);
     }
   endgroup

逐段解释：

* 第 L421-L423 行：covergroup 名称是 ``csr_cg``。
* 第 L426-L430 行：coverpoint 的采样表达式是常量 1，四个 bins 分别由 ``i0_dec.csr_read``、``csr_write``、``csr_set``、``csr_clr`` 条件启用。

接口关系：

* 被调用：``csr_cg_inst`` 在 initial 块创建后按 clock 采样。
* 调用：无。
* 共享状态：读取 ``i0_dec`` 的 CSR 字段。

§5.2 ``dual_issue_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``dual_issue_cg`` 单独统计 I0/I1 指令类别组合，补充 ``uarch_cg.pipe_cross``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L437-L468``）：

.. code-block:: systemverilog

   covergroup dual_issue_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "dual_issue_cg";

     // Dual-issue combinations
     cp_i0_cat: coverpoint get_i0_instr_category() {
       bins alu    = {InstrCategoryALU};
       bins mul    = {InstrCategoryMul};
       bins div    = {InstrCategoryDiv};
       bins branch = {InstrCategoryBranch};
       bins jump   = {InstrCategoryJump};
       bins load   = {InstrCategoryLoad};
       bins store  = {InstrCategoryStore};
       bins csr    = {InstrCategoryCSRAccess};
       ignore_bins none = {InstrCategoryNone};
     }

     cp_i1_cat: coverpoint get_i1_instr_category() {
       bins alu    = {InstrCategoryALU};

逐段解释：

* 第 L437-L439 行：covergroup 名称为 ``dual_issue_cg``。
* 第 L442-L452 行：I0 类别覆盖 ALU、mul、div、branch、jump、load、store、CSR，并忽略 none。
* 第 L454-L464 行：I1 使用同样的类别集合。
* 第 L467 行：``dual_cross`` 交叉 I0 和 I1 类别。

接口关系：

* 被调用：``dual_issue_cg_inst`` 创建后按 clock 采样。
* 调用：``get_i0_instr_category()``、``get_i1_instr_category()``。
* 共享状态：读取 I0/I1 decode packet。

§5.3 ``interrupt_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``interrupt_cg`` 细化中断来源、NMI/regular 分类，并交叉中断来源与 debug mode。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L473-L494``）：

.. code-block:: systemverilog

   covergroup interrupt_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "interrupt_cg";

     // Interrupt source
     cp_int_source: coverpoint 1 iff (interrupt_valid) {
       bins ext_int    = {1} iff (take_ext_int);
       bins timer_int  = {1} iff (take_timer_int);
       bins soft_int   = {1} iff (take_soft_int);
       bins nmi        = {1} iff (take_nmi);
       bins ce_int     = {1} iff (take_ce_int);
     }

     // NMI vs regular interrupt
     cp_nmi_type: coverpoint take_nmi iff (interrupt_valid) {
       bins nmi     = {1};
       bins regular = {0};
     }

     // Interrupt during debug mode
     cp_int_in_debug: cross cp_int_source, dec_tlu_debug_mode;
   endgroup

逐段解释：

* 第 L478-L484 行：中断来源 coverpoint 只在 ``interrupt_valid`` 时采样，并按 external、timer、software、NMI、CE interrupt 分 bin。
* 第 L487-L490 行：``cp_nmi_type`` 用 ``take_nmi`` 区分 NMI 和 regular interrupt。
* 第 L493 行：``cp_int_in_debug`` 直接交叉 ``cp_int_source`` 与 ``dec_tlu_debug_mode``。

接口关系：

* 被调用：``interrupt_cg_inst`` 创建后按 clock 采样。
* 调用：无。
* 共享状态：读取 interrupt 输入和 debug mode 输入。

§5.4 ``csr_warl_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``csr_warl_cg`` 记录 CSR 地址 bins 与 CSR 操作类型，并交叉二者。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L501-L557``）：

.. code-block:: systemverilog

   covergroup csr_warl_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "csr_warl_cg";

     // CSR write address coverage - which CSR is being written
     cp_csr_addr: coverpoint i0_dec.csr_clr ? 12'hFFF :
                             i0_dec.csr_set ? 12'hFFF :
                             i0_dec.csr_write ? 12'hFFF :
                             i0_dec.csr_read ? 12'hFFF : 12'h000
       iff (i0_dec.csr_read || i0_dec.csr_write || i0_dec.csr_set || i0_dec.csr_clr) {
       // Standard RISC-V CSRs
       bins mstatus   = {12'h300};
       bins misa      = {12'h301};
       bins mie       = {12'h304};
       bins mtvec     = {12'h305};
       bins mscratch  = {12'h340};
       bins mepc      = {12'h341};
       bins mcause    = {12'h342};
       bins mtval     = {12'h343};

逐段解释：

* 第 L501-L503 行：covergroup 名称为 ``csr_warl_cg``。
* 第 L506-L510 行：``cp_csr_addr`` 的表达式在 CSR read/write/set/clear 时返回 ``12'hFFF``，否则返回 ``12'h000``；bins 列表则列出标准、EH2 自定义和 debug CSR 地址。
* 第 L546-L553 行：``cp_csr_op`` 按 read、write、set、clear 建 bins。
* 第 L556 行：``csr_addr_op_cross`` 交叉 CSR 地址和操作类型。

接口关系：

* 被调用：``csr_warl_cg_inst`` 创建后按 clock 采样。
* 调用：无。
* 共享状态：读取 ``i0_dec`` CSR 字段。

§5.5 ``instr_detail_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``instr_detail_cg`` 细化 I0 的 branch/load/store/ALU/mul-div/sync/width 组合。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L563-L654``）：

.. code-block:: systemverilog

   covergroup instr_detail_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "instr_detail_cg";

     // Branch subtypes
     cp_branch_subtype: coverpoint 1 iff (dec_ib0_valid_d && (i0_dec.condbr || i0_dec.jal)) {
       bins beq  = {1} iff (i0_dec.beq);
       bins bne  = {1} iff (i0_dec.bne);
       bins bge  = {1} iff (i0_dec.bge);
       bins blt  = {1} iff (i0_dec.blt);
       bins jal  = {1} iff (i0_dec.jal);
     }

     // Load subtypes
     cp_load_subtype: coverpoint 1 iff (dec_ib0_valid_d && i0_dec.load) {
       bins byte_load  = {1} iff (i0_dec.by);
       bins half_load  = {1} iff (i0_dec.half);
       bins word_load  = {1} iff (i0_dec.word);
     }

逐段解释：

* 第 L563-L565 行：covergroup 名称为 ``instr_detail_cg``。
* 第 L568-L574 行：branch subtype 覆盖 beq、bne、bge、blt 和 jal。
* 第 L577-L588 行：load/store subtype 以 ``by``、``half``、``word`` 字段分 byte、half、word。
* 第 L591-L609 行：ALU subtype 在排除 load/store/mul/div/branch/CSR/debug/trap/fence 后，按 add、sub、shift、compare、logic 操作建 bins。
* 第 L612-L653 行：后续 coverpoint 覆盖 signed operands、mul/div/rem、presync/postsync、I0 width，并交叉 width 与 I0 category。

接口关系：

* 被调用：``instr_detail_cg_inst`` 创建后按 clock 采样。
* 调用：``get_i0_instr_category()``。
* 共享状态：读取 ``dec_ib0_valid_d``、``dec_i0_pc4_d`` 和 ``i0_dec``。

§5.6 ``controller_fsm_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该 covergroup 不采样单一 RTL FSM 编码，而是用 debug、exception、interrupt、mret 和 flush 信号描述控制状态转换场景。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L664-L715``）：

.. code-block:: systemverilog

   covergroup controller_fsm_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "controller_fsm_cg";

     // Debug state machine
     cp_debug_state: coverpoint 1 {
       bins running       = {1} iff (!dec_tlu_debug_mode && !dec_tlu_dbg_halted);
       bins debug_halted  = {1} iff (dec_tlu_debug_mode && dec_tlu_dbg_halted);
       bins debug_active  = {1} iff (dec_tlu_debug_mode && !dec_tlu_dbg_halted);
     }

     // Exception entry type
     cp_exception_entry: coverpoint 1 iff (i0_exception_valid_e4) {
       bins inst_acc_fault = {1} iff (inst_acc_e4);
       bins illegal_instr  = {1} iff (illegal_e4);
       bins ebreak         = {1} iff (ebreak_e4);
       bins ecall          = {1} iff (ecall_e4);
     }

逐段解释：

* 第 L664-L672 行：debug state 由 ``dec_tlu_debug_mode`` 和 ``dec_tlu_dbg_halted`` 组合成 running、debug_halted、debug_active。
* 第 L676-L690 行：exception entry 和 interrupt entry 分别按异常/中断来源建 bins。
* 第 L693-L701 行：``cp_mret`` 统计 ``mret_e4``，``cp_flush_reason`` 区分 mispredict、exception 和 pipe_flush。
* 第 L705-L714 行：cross 覆盖 debug/exception、debug/interrupt、exception/flush、mret/debug 组合。

接口关系：

* 被调用：``controller_fsm_cg_inst`` 创建后按 clock 采样。
* 调用：无。
* 共享状态：读取 debug、exception、interrupt、mret 和 flush 输入。

§5.7 ``pipeline_state_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``pipeline_state_cg`` 覆盖 decode slot 使用率、commit 组合、stall 类型和 I0 branch mispredict。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L721-L764``）：

.. code-block:: systemverilog

   covergroup pipeline_state_cg @(posedge clk_i);
     option.per_instance = 1;
     option.name = "pipeline_state_cg";

     // Pipeline slot utilization
     cp_pipe_utilization: coverpoint 1 {
       bins both_slots_valid = {1} iff (dec_ib0_valid_d && dec_ib1_valid_d);
       bins only_i0_valid    = {1} iff (dec_ib0_valid_d && !dec_ib1_valid_d);
       bins only_i1_valid    = {1} iff (!dec_ib0_valid_d && dec_ib1_valid_d);
       bins neither_valid    = {1} iff (!dec_ib0_valid_d && !dec_ib1_valid_d);
     }

     // E4 stage commit
     cp_e4_commit: coverpoint 1 {
       bins dual_commit  = {1} iff (tlu_i0_commit_cmt && tlu_i1_commit_cmt);
       bins i0_only      = {1} iff (tlu_i0_commit_cmt && !tlu_i1_commit_cmt);
       bins i1_only      = {1} iff (!tlu_i0_commit_cmt && tlu_i1_commit_cmt);

逐段解释：

* 第 L721-L730 行：slot 使用率覆盖 both、I0 only、I1 only、neither 四种组合。
* 第 L734-L739 行：commit coverpoint 覆盖 dual commit、I0 only、I1 only 和 no commit。
* 第 L742-L756 行：stall 和 branch mispredict coverpoint 复用 ``get_stall_type()`` 和 I0 branch valid 条件。
* 第 L760-L763 行：``stall_pipe_cross`` 交叉 slot 使用率与 stall，``commit_branch_cross`` 交叉 commit 与 branch mispredict。

接口关系：

* 被调用：``pipeline_state_cg_inst`` 创建后按 clock 采样。
* 调用：``get_stall_type()``。
* 共享状态：读取 valid、commit、stall、branch 输入。

§5.8 coverage enable 与实例化
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接口读取 ``+enable_eh2_fcov`` plusarg 到 ``fcov_en``，并创建 8 个 covergroup 实例。

关键代码（``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:L766-L795``）：

.. code-block:: systemverilog

   // =========================================================================
   // Coverage enable and instantiation
   // =========================================================================
   logic fcov_en;

   initial begin
     fcov_en = 0;
     if ($test$plusargs("enable_eh2_fcov"))
       fcov_en = 1;
   end

   uarch_cg         uarch_cg_inst;
   csr_cg           csr_cg_inst;
   dual_issue_cg    dual_issue_cg_inst;
   interrupt_cg     interrupt_cg_inst;
   csr_warl_cg      csr_warl_cg_inst;
   instr_detail_cg  instr_detail_cg_inst;
   controller_fsm_cg controller_fsm_cg_inst;
   pipeline_state_cg pipeline_state_cg_inst;

逐段解释：

* 第 L769-L775 行：``fcov_en`` 根据 ``$test$plusargs("enable_eh2_fcov")`` 设置，但当前文件中的 covergroup 声明没有用 ``iff (fcov_en)`` 包裹采样。
* 第 L777-L784 行：声明 8 个 covergroup 实例句柄。
* 第 L786-L795 行：initial 块调用 ``new()`` 创建所有 8 个实例。

接口关系：

* 被调用：interface 实例 elaboration 后执行 initial 块。
* 调用：``$test$plusargs`` 和各 covergroup ``new()``。
* 共享状态：写 ``fcov_en`` 和 covergroup 实例句柄。

§6 ``core_eh2_tb_top.sv`` 中的通用覆盖率实例
--------------------------------------------------------------------------------

``u_fcov_if`` 在 testbench top 中直接实例化，端口连接到 ``dut.veer`` 层次信号。

§6.1 实例头与 pipeline/decode 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：top 把 clock/reset、pipeline valid、指令和 decode packet 接到 ``u_fcov_if``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L941-L965``）：

.. code-block:: systemverilog

   //--------------------------------------------------------------------------
   // Functional Coverage Interface Instance
   //--------------------------------------------------------------------------
   eh2_fcov_if u_fcov_if (
     .clk_i                    (core_clk),
     .rst_l_i                  (rst_l),

     // Pipeline valids (from eh2_dec internal signals)
     .dec_ib0_valid_d          (dut.veer.dec.dec_ib0_valid_d),
     .dec_ib1_valid_d          (dut.veer.dec.dec_ib1_valid_d),
     .dec_i1_valid_e1          (dut.veer.dec.dec_i1_valid_e1),
     .dec_tlu_i0_valid_e4      (dut.veer.dec.tlu.tlumt[0].tlu.dec_tlu_i0_valid_e4),
     .dec_tlu_i1_valid_e4      (dut.veer.dec.tlu.tlumt[0].tlu.dec_tlu_i1_valid_e4),
     .tlu_i0_commit_cmt        (dut.veer.dec.tlu.tlumt[0].tlu.tlu_i0_commit_cmt),
     .tlu_i1_commit_cmt        (dut.veer.dec.tlu.tlumt[0].tlu.tlu_i1_commit_cmt),

     // Instructions at decode
     .dec_i0_instr_d            (dut.veer.dec.dec_i0_instr_d),
     .dec_i1_instr_d            (dut.veer.dec.dec_i1_instr_d),

逐段解释：

* 第 L944-L946 行：``u_fcov_if`` 使用 ``core_clk`` 和 ``rst_l``。
* 第 L949-L955 行：pipeline valid 和 commit 信号来自 ``dut.veer.dec`` 以及 ``dut.veer.dec.tlu.tlumt[0].tlu``。
* 第 L958-L965 行：I0/I1 decode 指令和 decode packet 直接连接到 ``dut.veer.dec`` 与 ``dut.veer.dec.decode`` 层次路径。

接口关系：

* 被调用：testbench top elaboration 创建 interface 实例。
* 调用：无函数调用。
* 共享状态：把 DUT 层次信号作为 coverage interface 输入。

§6.2 branch、flush、stall、exception 与 interrupt 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该实例段把 E4 和 TLU 内部信号连接给 coverage interface。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L967-L1008``）：

.. code-block:: systemverilog

     // Branch signals (inputs to TLU)
     .exu_pmu_i0_br_misp        (dut.veer.dec.tlu.tlumt[0].tlu.exu_pmu_i0_br_misp),
     .exu_pmu_i0_br_ataken      (dut.veer.dec.tlu.tlumt[0].tlu.exu_pmu_i0_br_ataken),
     .exu_pmu_i1_br_misp        (dut.veer.dec.tlu.tlumt[0].tlu.exu_pmu_i1_br_misp),
     .exu_pmu_i1_br_ataken      (dut.veer.dec.tlu.tlumt[0].tlu.exu_pmu_i1_br_ataken),
     .exu_i0_br_valid_e4        (dut.veer.dec.exu_i0_br_valid_e4),
     .exu_i1_br_valid_e4        (dut.veer.dec.exu_i1_br_valid_e4),
     .exu_i0_br_mp_e4           (dut.veer.dec.tlu.tlumt[0].tlu.exu_i0_br_mp_e4),
     .exu_i1_br_mp_e4           (dut.veer.dec.exu_i1_br_mp_e4),

     // Flushes (inputs to decode, outputs of TLU)
     .exu_flush_final           (dut.veer.dec.exu_flush_final[0]),
     .exu_i0_flush_final        (dut.veer.dec.exu_i0_flush_final[0]),
     .exu_i1_flush_final        (dut.veer.dec.exu_i1_flush_final[0]),
     .dec_tlu_flush_lower_wb    (dut.veer.dec.dec_tlu_flush_lower_wb[0]),

逐段解释：

* 第 L968-L975 行：branch PMU、branch valid 和 branch mispredict 路径来自 TLU 或 EXU 层次信号。
* 第 L978-L982 行：flush 相关信号覆盖 EXU final flush 和 TLU lower/mp writeback flush。
* 第 L985-L991 行：stall 输入来自 LSU 顶层数组和 TLU 内部 PMU stall 信号。
* 第 L994-L1008 行：异常和中断输入来自 TLU 内部信号，包括 external、timer、soft、NMI、CE interrupt。

接口关系：

* 被调用：``u_fcov_if`` 实例端口连接。
* 调用：无。
* 共享状态：DUT 层次信号驱动 coverage interface。

§6.3 debug、PIC、LSU 和 IFU PMU 连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：尾部端口连接 debug、PIC priority、LSU PMU 和 IFU PMU 信号。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1010-L1026``）：

.. code-block:: systemverilog

     // Debug (decode output)
     .dec_tlu_dbg_halted        (dut.veer.dec.dec_tlu_dbg_halted[0]),
     .dec_tlu_debug_mode        (dut.veer.dec.dec_tlu_debug_mode[0]),

     // PIC (TLU internal)
     .dec_tlu_meicurpl          (dut.veer.dec.tlu.tlumt[0].tlu.tlu_meicurpl),
     .dec_tlu_meicidpl          (dut.veer.dec.tlu.tlumt[0].tlu.meicidpl[3:0]),

     // LSU PMU (inputs to TLU)
     .lsu_pmu_misaligned_dc3    (dut.veer.lsu_pmu_misaligned_dc3[0]),
     .lsu_pmu_load_external_dc3 (dut.veer.dec.tlu.tlumt[0].tlu.lsu_pmu_load_external_dc3),
     .lsu_pmu_store_external_dc3(dut.veer.dec.tlu.tlumt[0].tlu.lsu_pmu_store_external_dc3),

     // Cache PMU (inputs to TLU)
     .ifu_pmu_ic_miss           (dut.veer.dec.tlu.tlumt[0].tlu.ifu_pmu_ic_miss),
     .ifu_pmu_ic_hit            (dut.veer.dec.tlu.tlumt[0].tlu.ifu_pmu_ic_hit)
   );

逐段解释：

* 第 L1011-L1012 行：debug halted 和 debug mode 从 decode 输出连接。
* 第 L1015-L1016 行：PIC 相关 priority 信号从 TLU 内部连接。
* 第 L1019-L1025 行：LSU misaligned/external access 和 IFU icache hit/miss 接入 coverage interface。

接口关系：

* 被调用：``u_fcov_if`` 实例端口连接。
* 调用：无。
* 共享状态：DUT 层次信号驱动 coverage interface。

§6.4 ``fcov_vif`` config_db 发布
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：top 把 ``u_fcov_if`` 发布到 UVM config_db，键名为 ``fcov_vif``。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1131-L1136``）：

.. code-block:: systemverilog

     // Store fetch enable interface
     uvm_config_db#(virtual fetch_enable_intf)::set(null, "*", "fetch_vif", fetch_en_intf);

     // Store functional coverage interface
     uvm_config_db#(virtual eh2_fcov_if)::set(null, "*", "fcov_vif", u_fcov_if);

逐段解释：

* 第 L1131-L1132 行：fetch-enable interface 以 ``fetch_vif`` 键发布，与虚拟序列章节中的 fetch sequence 相关。
* 第 L1134-L1135 行：``u_fcov_if`` 以 ``fcov_vif`` 键发布。当前 ``core_eh2_env.sv`` 没有创建独立 coverage collector 消费该键。

接口关系：

* 被调用：top 的 initial config_db setup。
* 调用：``uvm_config_db::set()``。
* 共享状态：写 UVM config_db。

§7 CSR 分类头文件
--------------------------------------------------------------------------------

``eh2_csr_categories.svh`` 定义 CSR 地址宏。当前 ``eh2_fcov_if.sv`` 没有 include 或展开这些宏，但 filelist 会编译该头文件。

§7.1 CSR 分类宏
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该头文件把只读 CSR、debug CSR、性能计数 CSR 和 EH2 自定义 CSR 分组成宏。

关键代码（``dv/uvm/core_eh2/fcov/eh2_csr_categories.svh:L6-L24``）：

.. code-block:: systemverilog

   // CSRs that are read-only or not meaningful for write testing
   `define EH2_READ_ONLY_CSRS \
     12'hF11, /* mvendorid */ \
     12'hF12, /* marchid */ \
     12'hF13, /* mimpid */ \
     12'hF14, /* mhartid */ \
     12'hFC0, /* mdseac */ \
     12'hFC8, /* meihap */ \
     12'hFC4  /* mhartnum */

   // CSRs only accessible in debug mode
   `define EH2_DEBUG_CSRS \
     12'h7B0, /* dcsr */ \
     12'h7B1, /* dpc */ \
     12'h7C8, /* dicawics */ \
     12'h7C9, /* dicad0 */ \
     12'h7CC, /* dicad0h */ \
     12'h7CA, /* dicad1 */ \
     12'h7CB  /* dicago */

逐段解释：

* 第 L7-L14 行：``EH2_READ_ONLY_CSRS`` 列出 vendor/hart/implementation 以及部分 EH2 CSR 地址。
* 第 L17-L24 行：``EH2_DEBUG_CSRS`` 列出 debug mode 相关 CSR 地址，包括 ``dcsr``、``dpc`` 和 debug cache 相关 CSR。
* 第 L27-L55 行继续定义 ``EH2_PERF_COUNTER_CSRS`` 与 ``EH2_CUSTOM_CSRS``；这些宏用于覆盖率过滤或分类时的地址集合。

接口关系：

* 被调用：filelist 编译该头文件；当前通用覆盖率 interface 未直接引用宏名。
* 调用：无。
* 共享状态：提供预处理宏。

§8 PMP 覆盖率接口边界
--------------------------------------------------------------------------------

``eh2_pmp_fcov_if`` 是 PMP/ePMP 专用覆盖率接口。它的 coverage 生成块受参数
``PMPEnable`` 控制。

§8.1 参数、端口和 enable plusarg
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接口参数定义 PMP 是否启用、粒度和区域数；initial 块只有在 ``PMPEnable`` 为 1 时读取 ``enable_eh2_fcov``。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L25-L72``）：

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

逐段解释：

* 第 L25-L31 行：默认 ``PMPEnable`` 为 0，``PMPGranularity`` 为 0，``PMPNumRegions`` 为 4。
* 第 L35-L41 行：PMP 配置端口按区域数组输入 lock、mode、exec、write、read 和 address。
* 第 L43-L60 行：接口还输入 ePMP ``mseccfg`` 位、PMP iside/dside fault、debug mode、data request 和 ``is_load``。
* 第 L66-L72 行：``PMPEnable`` 为 1 时才读取 ``+enable_eh2_fcov``；否则 ``en_pmp_fcov`` 固定为 0。

接口关系：

* 被调用：``core_eh2_tb_top.sv`` 实例化 ``u_pmp_fcov_if``。
* 调用：``$value$plusargs``。
* 共享状态：写 ``en_pmp_fcov``。

§8.2 PMP mode、permission 和 access type 枚举
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：PMP 覆盖率接口用枚举表达 PMP mode、权限组合和访问类型。

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

逐段解释：

* 第 L77-L82 行：PMP mode 枚举覆盖 OFF、TOR、NA4、NAPOT。
* 第 L87-L120 行：``pmp_priv_bits_e`` 用 5 bit 编码权限组合，包含普通 RWX/lock 组合和 MML 相关组合。
* 第 L125-L130 行：``pmp_access_type_e`` 覆盖 exec、load、store、none。

接口关系：

* 被调用：PMP covergroup 的 coverpoint bins 使用这些枚举。
* 调用：无。
* 共享状态：无。

§8.3 派生信号：RWX、active 区域与访问类型
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：接口把原始 PMP 配置端口组合成覆盖率更容易采样的派生信号。

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
       num_active_regions = num_active_regions + {{($clog2(PMPNumRegions+1)-1){1'b0}}, region_active[r]};

逐段解释：

* 第 L137-L140 行：``pmp_cfg_rwx`` 把 exec/write/read 三个 bit 合成 3 bit 权限向量。
* 第 L143-L146 行：``region_active`` 在 mode 不等于 ``PMP_MODE_OFF`` 时为 1。
* 第 L149-L155 行：``num_active_regions`` 在 ``always_comb`` 中累加 active 区域数量。
* 第 L159-L169 行：``inferred_access_type`` 优先把 iside fault 归为 exec；data request 且 ``is_load`` 为 1 归为 load，data request 且 ``is_load`` 为 0 归为 store，否则 none。
* 第 L172-L173 行：``pmp_any_fault`` 是 iside 和 dside fault 的 OR。

接口关系：

* 被调用：PMP access type、多区域、priority 和 ePMP covergroup 读取。
* 调用：无。
* 共享状态：读取 PMP 输入端口，写派生 logic。

§8.4 前一拍状态、地址形态和 locked active
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该片段保存前一拍配置，用于 transition covergroup；同时派生地址对齐、极值和 locked active 数量。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L183-L237``）：

.. code-block:: systemverilog

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

* 第 L183-L199 行：前一拍 mode、lock、RWX、MML/MMWP/RLB 在 reset 时清零，否则每拍更新为当前配置。
* 第 L202-L223 行：``mode_changed``、``lock_changed``、``rwx_changed`` 和 ``epmp_config_changed`` 比较当前值与前一拍值。
* 第 L226-L237 行：``napot_trailing_ones`` 对每个区域统计 ``pmp_addr`` 从低位开始连续为 1 的 bit 数，用于 NAPOT size 覆盖。

接口关系：

* 被调用：``pmp_cfg_transition_cg`` 和 NAPOT covergroup 读取。
* 调用：无。
* 共享状态：写前一拍寄存器和变化标志。

§8.5 地址对齐、TOR 邻接和锁定区域计数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该片段为边界、地址匹配和多区域覆盖派生地址与锁定状态。

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

逐段解释：

* 第 L240-L249 行：每个区域派生 4 字节对齐、4 KB 对齐、地址为 0、地址为 ``32'hFFFFFFFF`` 四类指示。
* 第 L253-L257 行：``adjacent_tor`` 在相邻两个区域 mode 都是 TOR 时为 1。
* 第 L262-L265 行：``locked_and_active`` 同时要求 lock 为 1 且 region active。
* 第 L268-L274 行：``num_locked_regions`` 累加 locked active 区域数量。

接口关系：

* 被调用：地址匹配、边界、多区域和 transition covergroup 读取。
* 调用：无。
* 共享状态：读取 PMP 输入，写派生 logic。

§9 PMP 基础 covergroup
--------------------------------------------------------------------------------

所有 PMP covergroup 都位于 ``if (PMPEnable) begin : g_pmp_fcov`` generate 块内。

§9.1 ``g_pmp_fcov`` generate 条件与每区域基础配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：只有 ``PMPEnable`` 为 1 时，才生成 PMP coverage；每个区域都有 ``pmp_region_cg``。

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

逐段解释：

* 第 L276 行：PMP coverage 受 ``PMPEnable`` generate 条件控制。
* 第 L281-L288 行：每个区域生成 ``region_priv_bits``，把 MML、lock、exec、write、read 拼成 ``pmp_priv_bits_e``。
* 第 L290-L320 行：``pmp_region_cg`` 覆盖 mode、permission bits、lock，并交叉 mode/lock 与 mode/permission；OFF mode 下的 permission cross 被 ignore。
* 第 L322-L323 行：每个区域实例化一个 ``region_cg_inst``。

接口关系：

* 被调用：PMPEnable 为 1 时 elaboration 生成。
* 调用：``$sformatf``、covergroup ``new()``。
* 共享状态：读取 per-region PMP 配置。

§9.2 ``pmp_access_cg`` fault 与 debug 组合
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``pmp_access_cg`` 覆盖 iside/dside fault 和 debug mode，并交叉 fault 与 debug。

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

逐段解释：

* 第 L330-L332 行：covergroup 名称为 ``pmp_access_cg``。
* 第 L335-L344 行：iside fault 无条件采样；dside fault 只在 ``data_req`` 时采样。
* 第 L347-L350 行：debug mode 覆盖 in_debug 和 not_debug。
* 第 L353-L356 行：分别交叉 iside fault/debug 和 dside fault/debug。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``access_cg_inst``。
* 调用：covergroup ``new()``。
* 共享状态：读取 fault、data_req 和 debug mode 输入。

§9.3 ``pmp_warl_cg`` 与 ``pmp_epmp_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``pmp_warl_cg`` 覆盖 region 0 NAPOT size 编码；``pmp_epmp_cg`` 覆盖 MML/MMWP/RLB 组合及其 fault cross。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L366-L445``）：

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

逐段解释：

* 第 L366-L403 行：``pmp_warl_cg`` 只在 region 0 mode 为 NAPOT 时采样 ``$countones(pmp_addr[0][31:2])``，bins 从 8 B 到 4 GB。
* 第 L412-L432 行：``pmp_epmp_cg`` 分别覆盖 ``mseccfg_mml``、``mseccfg_mmwp`` 和 ``mseccfg_rlb``。
* 第 L435-L444 行：ePMP covergroup 交叉 MML/MMWP、MML/MMWP/RLB、ePMP config 与 iside fault、ePMP config 与 dside fault。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``warl_cg_inst`` 和 ``epmp_cg_inst``。
* 调用：``$countones``、covergroup ``new()``。
* 共享状态：读取 ``pmp_addr[0]``、``pmp_cfg_mode[0]``、ePMP bits 和 fault 输入。

§10 PMP 扩展 covergroup
--------------------------------------------------------------------------------

后半部分 PMP 文件扩展了每区域配置、访问类型、地址匹配、多区域、边界、priority、NAPOT、ePMP/region、地址模式和 transition 覆盖。

§10.1 ``pmp_region_ext_cg`` 每区域扩展配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该 covergroup 为每个区域覆盖 mode、RWX、单 bit 权限、lock、active、locked_active 及关键 cross。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L454-L556``）：

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

         // -----------------------------------------------------------------
         // RWX permission bits (non-MML, decomposed 3-bit view)
         // -----------------------------------------------------------------

逐段解释：

* 第 L454-L458 行：每个 PMP 区域生成一个 ``pmp_region_ext_cg``，名称带区域号。
* 第 L463-L508 行：coverpoint 覆盖 region mode、3 bit RWX、read/write/exec 单 bit、lock bit。
* 第 L514-L533 行：交叉 mode/RWX、mode/lock、RWX/lock、mode/RWX/lock，并在 mode OFF 时忽略若干组合。
* 第 L539-L550 行：``cp_active`` 和 ``cp_locked_active`` 覆盖区域是否 active、是否 locked 且 active。

接口关系：

* 被调用：PMPEnable 为 1 时按区域生成。
* 调用：``$sformatf``、covergroup ``new()``。
* 共享状态：读取 per-region PMP 配置和派生信号。

§10.2 ``pmp_access_type_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该 covergroup 交叉推断访问类型、fault 和 debug mode。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L562-L632``）：

.. code-block:: systemverilog

     covergroup pmp_access_type_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = "pmp_access_type_cg";

       // -----------------------------------------------------------------
       // Inferred access type
       // -----------------------------------------------------------------
       cp_access_type: coverpoint inferred_access_type {
         bins exec  = {ACCESS_EXEC};
         bins load  = {ACCESS_LOAD};
         bins store = {ACCESS_STORE};  // enabled by is_load signal (issue 68)
         ignore_bins none = {ACCESS_NONE};
       }

       // -----------------------------------------------------------------
       // Instruction-side fault
       // -----------------------------------------------------------------
       cp_iside_fault: coverpoint pmp_iside_err {
         bins no_fault = {0};

逐段解释：

* 第 L562-L574 行：访问类型 coverpoint 使用 ``inferred_access_type``，覆盖 exec、load、store，并忽略 none。
* 第 L579-L598 行：分别覆盖 iside fault、dside fault 和 any fault。
* 第 L603-L618 行：交叉 access/fault、access/debug、access/fault/debug。
* 第 L623-L628 行：``cp_simultaneous_faults`` 覆盖 no fault、iside only、dside only、both faults 四种组合。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``access_type_cg_inst``。
* 调用：covergroup ``new()``。
* 共享状态：读取 ``inferred_access_type``、fault、debug。

§10.3 ``pmp_addr_match_cg`` 与 ``pmp_multi_region_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：地址匹配覆盖按区域采样 active、地址极值/对齐和 fault；多区域覆盖统计 active/locked 区域数量及其与 fault、MML、debug 的组合。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L638-L807``）：

.. code-block:: systemverilog

     for (genvar i = 0; i < PMPNumRegions; i++) begin : g_addr_match_cg

       covergroup pmp_addr_match_cg @(posedge clk_i);
         option.per_instance = 1;
         option.name = $sformatf("pmp_addr_match_%0d_cg", i);

         // -----------------------------------------------------------------
         // Region active (mode != OFF)
         // -----------------------------------------------------------------
         cp_active: coverpoint region_active[i] {
           bins active   = {1};
           bins inactive = {0};
         }

         // -----------------------------------------------------------------
         // Address register is zero
         // -----------------------------------------------------------------
         cp_addr_zero: coverpoint addr_is_zero[i] {
           bins zero     = {1};

逐段解释：

* 第 L638-L642 行：每个区域生成 ``pmp_addr_match_cg``，实例名带区域号。
* 第 L647-L713 行：按区域覆盖 active、addr zero、addr max、4 字节对齐、page 对齐、iside/dside fault、mode，并交叉 active/fault 和 addr boundary/mode。
* 第 L725-L804 行：``pmp_multi_region_cg`` 覆盖 active 区域数、locked 区域数、any fault、MML、debug、all off 和 all locked。
* 第 L761-L786 行：多区域 covergroup 交叉 active count/fault、locked count/fault、active count/MML、active count/debug。

接口关系：

* 被调用：PMPEnable 为 1 时按区域或单实例创建。
* 调用：``$sformatf``、covergroup ``new()``。
* 共享状态：读取地址派生信号、active/locked 计数、fault、MML、debug。

§10.4 ``pmp_boundary_cg`` 与 ``pmp_region_prio_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：边界覆盖关注 region 0 地址极值、TOR 邻接、page alignment 和地址 quadrant；priority 覆盖前 4 个区域的 mode 组合和 first active region 属性。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L813-L989``）：

.. code-block:: systemverilog

     covergroup pmp_boundary_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = "pmp_boundary_cg";

       // -----------------------------------------------------------------
       // Region 0 NAPOT trailing ones (region size indicator)
       // Already covered in pmp_warl_cg; here we add addr[0] extreme cases
       // -----------------------------------------------------------------
       cp_r0_addr_zero: coverpoint addr_is_zero[0] {
         bins zero    = {1};
         bins nonzero = {0};
       }

       cp_r0_addr_max: coverpoint addr_is_max[0] {
         bins max     = {1};
         bins not_max = {0};
       }

逐段解释：

* 第 L813-L884 行：``pmp_boundary_cg`` 覆盖 region 0 地址为 0、为 max、相邻 TOR、region 0 mode、addr/mode cross、NAPOT page alignment、TOR region 0 upper bound 是否非零和地址高 2 bit quadrant。
* 第 L895-L945 行：``pmp_region_prio_cg`` 覆盖 r0-r3 mode，并交叉 r0/r1 mode 和四区域 mode 组合；全 OFF 组合被 ignore。
* 第 L951-L988 行：priority covergroup 推导 first active region 的 RWX 与 lock，并交叉 first active RWX 与 any fault。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``boundary_cg_inst`` 和 ``region_prio_cg_inst``。
* 调用：covergroup ``new()``。
* 共享状态：读取 region 0 地址、前 4 个区域 mode/RWX/lock、fault。

§10.5 ``pmp_napot_per_region_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该 covergroup 将 NAPOT size 覆盖从 region 0 扩展到每个区域，并交叉 lock 与 RWX。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L998-L1073``）：

.. code-block:: systemverilog

     for (genvar i = 0; i < PMPNumRegions; i++) begin : g_napot_per_region_cg

       covergroup pmp_napot_per_region_cg @(posedge clk_i);
         option.per_instance = 1;
         option.name = $sformatf("pmp_napot_region_%0d_cg", i);

         // -----------------------------------------------------------------
         // NAPOT trailing ones count (region size encoding)
         // Only meaningful when mode == NAPOT
         // -----------------------------------------------------------------
         cp_napot_trailing: coverpoint napot_trailing_ones[i]
           iff (pmp_cfg_mode[i] == PMP_MODE_NAPOT) {
           bins size_8B     = {0};    // no trailing ones => 8B
           bins size_16B    = {1};
           bins size_32B    = {2};

逐段解释：

* 第 L998-L1003 行：每个区域生成一个 ``pmp_napot_per_region_cg``。
* 第 L1008-L1040 行：``cp_napot_trailing`` 只在 mode 为 NAPOT 时采样 trailing ones 计数，bins 从 8 B 到 4 GB，并包含 ``larger``。
* 第 L1046-L1067 行：同一 covergroup 覆盖 lock、RWX，并交叉 NAPOT size/lock 和 NAPOT size/RWX。

接口关系：

* 被调用：PMPEnable 为 1 时按区域创建。
* 调用：``$sformatf``、covergroup ``new()``。
* 共享状态：读取 ``napot_trailing_ones``、PMP mode、lock、RWX。

§10.6 ``pmp_epmp_region_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该 covergroup 交叉 ePMP policy bit 与 region 0 配置、active 区域数和 fault。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1079-L1197``）：

.. code-block:: systemverilog

     covergroup pmp_epmp_region_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = "pmp_epmp_region_cg";

       // -----------------------------------------------------------------
       // ePMP bits
       // -----------------------------------------------------------------
       cp_mml: coverpoint mseccfg_mml {
         bins enabled  = {1};
         bins disabled = {0};
       }

       cp_mmwp: coverpoint mseccfg_mmwp {
         bins enabled  = {1};
         bins disabled = {0};
       }

逐段解释：

* 第 L1079-L1099 行：先覆盖 MML、MMWP、RLB 三个 ePMP bit。
* 第 L1104-L1124 行：覆盖 region 0 mode、lock 和 RWX。
* 第 L1129-L1161 行：交叉 MML/region 0 mode、MML/region 0 lock、MML/region 0 RWX、MMWP/region 0 mode、RLB/region 0 lock、完整 ePMP config/region 0 mode、MML/lock/RWX。
* 第 L1166-L1193 行：覆盖 active 区域数量、iside/dside fault，并交叉 MML/MMWP/RLB 与 fault。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``epmp_region_cg_inst``。
* 调用：covergroup ``new()``。
* 共享状态：读取 ePMP bits、region 0 配置、active 区域数和 fault。

§10.7 ``pmp_addr_pattern_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该 covergroup 覆盖 PMP address register 的 nibble、特殊模式、TOR 有效范围和 popcount。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1203-L1295``）：

.. code-block:: systemverilog

     covergroup pmp_addr_pattern_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = "pmp_addr_pattern_cg";

       // -----------------------------------------------------------------
       // Region 0 address upper nibble (memory region selection)
       // -----------------------------------------------------------------
       cp_r0_upper_nibble: coverpoint pmp_addr[0][31:28] {
         bins nibble[] = {[0:15]};
       }

       // -----------------------------------------------------------------
       // Region 0 address lower nibble
       // -----------------------------------------------------------------
       cp_r0_lower_nibble: coverpoint pmp_addr[0][3:0] {
         bins nibble[] = {[0:15]};
       }

逐段解释：

* 第 L1203-L1219 行：region 0 地址高 nibble 和低 nibble 都覆盖 0 到 15。
* 第 L1224-L1231 行：region 0 特殊地址覆盖 zero、max、交替 bit、low half、hi half 和 default。
* 第 L1237-L1259 行：region 1 地址高 nibble、特殊地址和 TOR valid range 被覆盖。
* 第 L1264-L1291 行：region 0 TOR from zero、低 2 bit 和 popcount 分桶被覆盖。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``addr_pattern_cg_inst``。
* 调用：``$countones``。
* 共享状态：读取 ``pmp_addr`` 和 ``pmp_cfg_mode``。

§10.8 ``pmp_cfg_transition_cg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：transition covergroup 比较当前 PMP/ePMP 配置与上一拍配置，覆盖 mode、lock、RWX 和 MML 变化。

关键代码（``dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:L1302-L1457``）：

.. code-block:: systemverilog

     covergroup pmp_cfg_transition_cg @(posedge clk_i);
       option.per_instance = 1;
       option.name = "pmp_cfg_transition_cg";

       // -----------------------------------------------------------------
       // Region 0: mode transition
       // -----------------------------------------------------------------
       cp_r0_mode_changed: coverpoint mode_changed[0] {
         bins changed   = {1};
         bins unchanged = {0};
       }

       cp_r0_mode_prev: coverpoint pmp_cfg_mode_prev[0] {
         bins off   = {PMP_MODE_OFF};
         bins tor   = {PMP_MODE_TOR};
         bins na4   = {PMP_MODE_NA4};

逐段解释：

* 第 L1302-L1326 行：covergroup 先覆盖 region 0 mode 是否变化，以及前一拍/当前拍 mode。
* 第 L1329-L1339 行：``r0_mode_transition`` 交叉前后 mode，并 ignore 四种未变化组合。
* 第 L1344-L1365 行：lock transition 覆盖 changed/unchanged、prev/current，并 ignore lock 未变化组合。
* 第 L1370-L1419 行：覆盖 RWX 变化、locked write attempt、ePMP config 变化、MML 前后状态、MML transition，以及 config change 与 fault 的 cross。
* 第 L1424-L1453 行：region 1 的 mode/lock/RWX 变化和多区域同时 mode change 计数也被覆盖。

接口关系：

* 被调用：PMPEnable 为 1 时创建 ``cfg_transition_cg_inst``。
* 调用：``$countones``。
* 共享状态：读取当前与前一拍 PMP/ePMP 配置、fault。

§11 ``core_eh2_tb_top.sv`` 中的 PMP 覆盖率实例
--------------------------------------------------------------------------------

当前 top 实例化 PMP coverage scaffold，但把 PMP 相关输入接常量 0，且 ``PMPEnable`` 为 0。

§11.1 PMP 实例参数和端口连接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：top 创建 ``u_pmp_fcov_if``，但默认配置表示当前平台不实现 PMP/ePMP。

关键代码（``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1028-L1054``）：

.. code-block:: systemverilog

   //--------------------------------------------------------------------------
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

逐段解释：

* 第 L1031-L1033 行：注释说明当前平台默认配置不实现 PMP/ePMP，但保留 interface scaffold。
* 第 L1034-L1038 行：实例参数设置 ``PMPEnable`` 为 ``1'b0``、``PMPGranularity`` 为 0、``PMPNumRegions`` 为 4。
* 第 L1039-L1053 行：PMP 配置、ePMP bits、fault、data request 多数接常量 0，debug mode 接 ``dut.veer.dec.dec_tlu_debug_mode[0]``。

接口关系：

* 被调用：testbench top elaboration 创建该 interface。
* 调用：无。
* 共享状态：当前配置下不会生成 ``g_pmp_fcov`` 内的 covergroup。

§12 Coverage waiver package
--------------------------------------------------------------------------------

``cov_waivers`` 目录保存 waiver YAML 和一个 SystemVerilog package。该 package 提供加载、查询和打印 waiver 的函数。

§12.1 waiver 数据结构和全局存储
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``cov_waiver_t`` 保存 waiver 元数据，``waivers`` associative array 以 coverage point 字符串为 key。

关键代码（``dv/uvm/core_eh2/fcov/cov_waivers/eh2_cov_waiver_pkg.sv:L13-L32``）：

.. code-block:: systemverilog

   package eh2_cov_waiver_pkg;

     // =========================================================================
     // Waiver data structure
     // =========================================================================
     typedef struct {
       string name;             // Human-readable description
       string coverage_point;   // covergroup.coverpoint_or_cross
       string reason;           // Technical justification
       string author;           // Approver
       string date;             // YYYY-MM-DD
       string ticket;           // Tracking issue (may be empty)
       string status;           // "active" | "superseded" | "withdrawn"
     } cov_waiver_t;

     // =========================================================================
     // Global waiver store
     // =========================================================================
     // Associative array keyed by coverage_point string for O(1) lookup.
     cov_waiver_t waivers[string];

逐段解释：

* 第 L13 行：package 名称为 ``eh2_cov_waiver_pkg``。
* 第 L18-L26 行：struct 字段覆盖 name、coverage_point、reason、author、date、ticket、status。
* 第 L31-L32 行：全局 associative array ``waivers`` 以 coverage point 字符串索引。

接口关系：

* 被调用：导入该 package 的 testbench 或工具代码可调用函数。
* 调用：无。
* 共享状态：``waivers`` 被加载函数写入，被查询函数读取。

§12.2 ``load_waiver_file()`` 简单 YAML 解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数逐行读取单个 YAML waiver 文件，只解析 ``waiver:`` 块中的 ``key: value`` 行。

关键代码（``dv/uvm/core_eh2/fcov/cov_waivers/eh2_cov_waiver_pkg.sv:L67-L145``）：

.. code-block:: systemverilog

   function automatic void load_waiver_file(string filepath);
     int         fd;
     string      line;
     bit         in_waiver;
     cov_waiver_t w;
     string      key, val;
     int         colon_pos;

     fd = $fopen(filepath, "r");
     if (fd == 0) begin
       $display("[cov_waiver] WARNING: cannot open %0s", filepath);
       return;
     end

     // Initialize struct
     w.name           = "";
     w.coverage_point = "";
     w.reason         = "";

逐段解释：

* 第 L67-L79 行：函数打开文件，失败时打印 warning 并返回。
* 第 L81-L90 行：初始化 ``cov_waiver_t``，默认 ``status`` 为 ``active``，``in_waiver`` 为 0。
* 第 L92-L134 行：循环读文件，trim 行，跳过注释/空行，遇到 ``waiver:`` 后解析 ``key: value``。
* 第 L137-L144 行：关闭文件；只有 ``coverage_point`` 非空且 ``status`` 为 ``active`` 时才写入 ``waivers``。

接口关系：

* 被调用：``load_waiver_filelist()`` 或外部 testbench 可调用。
* 调用：``$fopen``、``$fgets``、``$fclose``、``str_trim()``、``str_find()``、``$display``。
* 共享状态：写 ``waivers``。

§12.3 查询、打印和字符串工具
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：查询函数只检查 associative array；字符串工具实现 trim 与字符查找。

关键代码（``dv/uvm/core_eh2/fcov/cov_waivers/eh2_cov_waiver_pkg.sv:L174-L256``）：

.. code-block:: systemverilog

   // Returns 1 if the given coverage point has an active waiver.
   // =========================================================================
   function automatic bit is_waived(string coverage_point);
     return waivers.exists(coverage_point);
   endfunction

   // =========================================================================
   // get_waiver
   //
   // Returns the waiver struct for a given coverage point.
   // Returns an empty struct if not found.
   // =========================================================================
   function automatic cov_waiver_t get_waiver(string coverage_point);
     cov_waiver_t empty;
     if (waivers.exists(coverage_point))
       return waivers[coverage_point];

逐段解释：

* 第 L179-L181 行：``is_waived()`` 直接返回 ``waivers.exists(coverage_point)``。
* 第 L189-L201 行：``get_waiver()`` 命中时返回存储的 struct，未命中时返回字段为空的 struct。
* 第 L208-L224 行：``print_waivers()`` 遍历 ``waivers`` 并打印 coverage point、name、reason、author 和 date。
* 第 L231-L256 行：``str_trim()`` 去掉首尾空白，``str_find()`` 线性扫描字符位置，未找到返回 -1。

接口关系：

* 被调用：外部 waiver 应用逻辑可调用。
* 调用：``waivers.exists``、``$display``。
* 共享状态：读取 ``waivers``。

§12.4 YAML waiver 实例
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：当前目录中有两个实际 waiver YAML 和一个 example YAML；actual YAML 的 coverage point 分别指向 ``uarch_cg.stall_cross`` 和 ``interrupt_cg.cp_int_in_debug``。

关键代码（``dv/uvm/core_eh2/fcov/cov_waivers/dual_issue_presync_stall_cross_waiver.yaml:L7-L28``）：

.. code-block:: yaml

   waiver:
     name: "Dual-issue with presync stall is extremely rare"
     coverage_point: "uarch_cg.stall_cross"
     reason: >
       A presync stall (dec_pmu_presync_stall) is generated by CSR
       read/write/set/clear instructions that require pipeline
       serialization before execution.  In the EH2 dual-issue pipeline,
       CSR instructions are only ever issued on pipe 0 (I0), and the
       presync stall blocks I1 from issuing in the same cycle.  The
       cross of dual-issue categories with StallTypePresync is therefore
       architecturally gated: when a presync stall is active, dual-issue
       is suppressed by design.  The few remaining theoretical
       combinations (e.g., non-CSR I0 with presync from a previous

逐段解释：

* 第 L7-L9 行：waiver 名称是 "Dual-issue with presync stall is extremely rare"，覆盖点是 ``uarch_cg.stall_cross``。
* 第 L10-L24 行：reason 说明 presync stall 与 dual-issue 的组合被 pipeline 序列化约束阻挡。
* 第 L25-L28 行：author 为 ``eh2-verification``，日期为 ``2026-05-05``，状态为 ``active``。
* ``nmi_during_debug_cross_waiver.yaml`` 的 coverage point 是 ``interrupt_cg.cp_int_in_debug``，状态同样为 ``active``。

接口关系：

* 被调用：``load_waiver_file()`` 可读取该 YAML。
* 调用：YAML 文件本身不调用代码。
* 共享状态：被加载后写入 waiver package 的 ``waivers``。

§13 与签核数字的关系
--------------------------------------------------------------------------------

当前文件解释覆盖率实现，同时固定引用 2026-05-19 01:02 VCS 主线 demo
的 sign-off 证据，避免读者把接口 covergroup 定义误读为最终 gate。该次
demo 使用 ``-cm line+tgl+assert+fsm+branch`` 五维覆盖率、编译时
``cover.cfg`` DUT-only scope 和 URG 原生 dashboard，结果为 LINE 95.05%、
BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、GROUP
69.42%、OVERALL 65.17%。功能覆盖率实跑口径为 102/104（98.1%），
sign-off 9/9 stage PASS；riscv-dv 370/395（93.67%）、compliance
85/88（96.59%）、directed 40/40（100%）、formal 46/46（100%），
block-level LEC 为 31635/31635 PASS。

.. warning::

   本章不再引用历史迁移期间的临时 coverage 数字。当前权威口径是
   VCS ``simv.vdb`` 加 URG 原生报告，NC 仅用于 ``SIMULATOR=nc WAVES=1``
   单测波形调试。

§14 参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`functional_coverage`、:ref:`pmp_coverage`
* 关联章节：:doc:`tb`、:doc:`tests`
* 关联 ADR：:ref:`adr-0009`、:ref:`adr-0010`
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_if.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/eh2_csr_categories.svh``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/cov_waivers/eh2_cov_waiver_pkg.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/cov_waivers/dual_issue_presync_stall_cross_waiver.yaml``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/fcov/cov_waivers/nmi_during_debug_cross_waiver.yaml``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/eh2_tb.f``
