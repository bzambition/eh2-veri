.. _functional_coverage:
.. _05_verification_arch/functional_coverage:

功能覆盖率 — 详细参考
======================

:status: draft
:source: dv/uvm/core_eh2/fcov/eh2_fcov_if.sv, dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv, dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
-------------

功能覆盖率是 UVM 验证方法学的**质量度量核心** 。它不关心"代码是否被执行过"
（那是代码覆盖率的事），而是关心"**功能点是否被验证过**"。
EH2 的功能覆盖率模型通过 SystemVerilog covergroup 定义了
300+ 个功能覆盖点（coverpoint）和 50+ 个交叉覆盖（cross），
覆盖指令集、异常、中断、CSR、PMP、调试、流水线微架构等 7 大域。

阅读本章你将学到：

* 功能覆盖率模型的整体架构：interface → bind → covergroup
* 每个 covergroup 的 coverpoint 定义与 bin 划分策略
* 交叉覆盖率（cross）的组合维度和覆盖率空洞分析方法
* PMP 覆盖率模型的独立设计
* 覆盖率收集流程：simulation → URG merge → dashboard → signoff gate
* 当前覆盖率状态与 v1.2 的提升目标

§2  覆盖率架构
---------------

.. code-block:: text

   RTL (eh2_veer)                    fcov 层
   ───────────────────────────────────────────────
   dec_ib0_valid_d  ──┐
   dec_i0_instr_d   ──┤
   i0_dec (pkt)     ──┤  bind ──► eh2_fcov_if ──► covergroup
   exu_pmu_*        ──┤           (interface)       uarch_cg
   lsu_*            ──┤           (797 行)          + pmp_cg
   interrupt_*      ──┤
   debug_*          ──┘

**三层结构：**

1. **``eh2_fcov_bind.sv``** （15 行）：SystemVerilog ``bind`` 将 coverage interface
   连接到 DUT 内部信号（hierarchical reference）。不修改 RTL
2. **``eh2_fcov_if.sv``** （797 行）：coverage interface。定义所有输入端口 +
   covergroup 采样逻辑
3. **``eh2_pmp_fcov_if.sv``** （1,461 行）：PMP 覆盖率接口。独立的 PMP 覆盖模型

§3  覆盖率域详解
-----------------

3.1  指令覆盖率（Instruction Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``instr_opcode``**

- 覆盖 RV32I/M/A/C/Zb* 的全部操作码
- bin 划分：每个 opcode 一个 bin（共 ~40 个 opcode）

**Coverpoint: ``instr_category``**

- 分类：ALU / Branch / Load / Store / CSR / MUL / DIV / AMO / FENCE / SYSTEM
- 每类一个 bin，用于高层级的覆盖率报告

**Coverpoint: ``compressed_instr``**

- 指令是否为压缩格式（16-bit vs 32-bit）
- 交叉：compressed × opcode

**Coverpoint: ``bitmanip_ops``**

- Zba/Zbb/Zbc/Zbs 各自的子操作覆盖
- CLZ/CTZ/CPOP/SEXT.B/SEXT.H/ROL/ROR/BSET/BCLR/BINV/BEXT 等

3.2  双发射覆盖率（Dual-Issue Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``dual_issue``**

- 状态：i0_only / i0_i1 / stall
- 跟踪每周期是单发射还是双发射

**Coverpoint: ``i1_stall_reason``**

- i1 不能发射的原因分类：

  - RAW 依赖 → 记分板 stall
  - 执行资源冲突（如两个乘法）
  - i0 是分支/跳转
  - i0 是 CSR 写
  - 流水线 stall

3.3  分支覆盖率（Branch Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``branch_direction``**
- Taken / Not-Taken
- 交叉：方向 × 分支类型（条件/无条件/JAL/JALR）

**Coverpoint: ``branch_mispredict``**
- 分支预测是否正确
- 交叉：btb_hit × bht_direction × actual_taken

3.4  异常覆盖率（Exception Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``exception_type``**
- 非法指令 / 断点 / ECALL / 未对齐 / 访问错误 / 页面错误
- 每个异常类型一个 bin

**Cross: ``exception_type × pipeline_stage``**
- 异常发生的流水级（D/E1/E4/DC3）
- 确保每种异常在所有可能的流水级都被触发

3.5  中断覆盖率（Interrupt Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``interrupt_type``**
- Timer / Software / External / NMI
- 每个中断类型一个 bin

**Cross: ``interrupt_type × priority_level``**
- 中断优先级 × 中断类型
- 确保不同优先级下的中断处理被覆盖

**Cross: ``interrupt × pipeline_position``**
- 中断在流水线中的发生时机（D 级前半/后半、E1 级等）

3.6  CSR 覆盖率（CSR Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``csr_address``**
- 所有 ~80 个 CSR 的地址
- 按标准/自定义/调试/PMP 分组

**Coverpoint: ``csr_access_type``**
- CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI

**Cross: ``csr_address × access_type``**
- 确保每个 CSR 的每种访问类型都被覆盖

3.7  调试覆盖率（Debug Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``debug_halt_reason``**
- External halt req / Trigger match / Single step / Reset halt

**Coverpoint: ``debug_abstract_cmd``**
- GPR read/write / CSR read/write / Memory access

3.8  流水线微架构覆盖率（Microarchitectural Coverage）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Coverpoint: ``stall_type``**
- Load-use 互锁 / Store buffer 满 / Bus buffer 满 / ECC 错误 / Presync/Postsync

**Coverpoint: ``flush_reason``**
- Branch mispredict / Exception / Interrupt / FENCE.I / Debug halt / Single step

**Coverpoint: ``forwarding_type``**
- D 级 bypass / E1/E2/E3 级 bypass / E4→DC3 store bypass

§4  PMP 覆盖率模型
-------------------

独立的 PMP 覆盖率接口（:file:`eh2_pmp_fcov_if.sv` ，1,461 行）：

**Coverpoint: ``pmp_num_regions``**
- 0/4/8/12/16 个 PMP 区域

**Coverpoint: ``pmp_match_mode``**
- NAPOT / TOR

**Coverpoint: ``pmp_permissions``**
- R / W / X / R+W / R+X / W+X / R+W+X

**Coverpoint: ``pmp_lock``**
- L 位置位后的行为（配置不可修改）

**Cross: ``pmp_num_regions × match_mode × permissions × lock``**
- 四维交叉覆盖，确保所有 PMP 配置组合被验证

§5  覆盖率收集流程
-------------------

当前主线覆盖率流完全对齐 Ibex/VCS/URG 方式：编译时使用
``-cm line+tgl+assert+fsm+branch``，用 ``cover.cfg`` 限定 ``core_eh2_tb_top.dut``
子树，回归结束后用 ``urg`` 合并/出报表。NC/IMC 不参与 sign-off 覆盖率；NC 只用于
单测波形调试。

.. code-block:: bash

   # 1. VCS 编译并插桩 5 维度覆盖率
   make compile SIMULATOR=vcs COV=1

   # 2. 跑当前 testlist，输出各 run 的 cov.vdb
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4

   # 3. 合并 VCS vdb，生成 URG 原生 dashboard
   python3 dv/uvm/core_eh2/scripts/merge_cov.py --output build/cov_merged

   # 4. full sign-off 读取 coverage dashboard 和 gate 参数
   make signoff PROFILE=full SIMULATOR=vcs COV=1

关键代码（DUT-only coverage scope）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/cover.cfg
   :language: text
   :lines: 1-4
   :caption: dv/uvm/core_eh2/cover.cfg:1-4

逐段解释：

* ``+tree core_eh2_tb_top.dut`` 是编译期 scope 过滤，避免 TB interface、scoreboard
  或 stub logic 抬高 line/branch 数字。
* ``begin tgl`` 下排除 ``core_eh2_tb_top.dut.*`` 的 toggle subtree，是当前 VCS
  配置对 EH2 大型层级做出的 toggle 成本控制。其他 coverage 维度仍在 DUT 子树内统计。

关键代码（coverage interface 实例化位置）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tb/core_eh2_tb_top.sv
   :language: systemverilog
   :lines: 951-1062
   :caption: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:951-1062

§6  当前覆盖率状态（2026-05-19）
---------------------------------

.. list-table::
   :header-rows: 1
   :widths: 26 22 22 30

   * - 覆盖域
     - 当前实测
     - sign-off 语义
     - 后续关注点
   * - LINE
     - 95.05%
     - 已高于默认 line gate 65%
     - 持续防止 RTL unreachable 或 wrapper scope 漂移
   * - BRANCH
     - 84.97%
     - URG 原生结构指标
     - directed 补齐异常/中断/flush 分支
   * - TOGGLE
     - 53.52%
     - 成本受 ``cover.cfg`` toggle scope 控制
     - 关注低翻转控制信号和 debug/PIC/DMI 边界
   * - ASSERT
     - 33.33%
     - 当前作为质量观测，不单独设 release gate
     - 后续增加 SVA enable 和 formal/RTL assertion 对齐
   * - FSM
     - 54.74%
     - URG FSM report，受 VCS FSM config 影响
     - reset filter、wait state 和 debug state 覆盖
   * - GROUP
     - 69.42%
     - covergroup/function coverage；脚本参数名仍叫 functional
     - 继续补 directed/riscv-dv 对 covergroup hole 的命中
   * - OVERALL
     - 65.17%
     - URG 综合分数
     - 不替代逐维度分析

.. note::

   文档中看到 ``SIGNOFF_MIN_FUNCTIONAL_COV`` 时，应理解为历史兼容参数名。当前
   URG dashboard 的签核可见名称是 ``GROUP``，signoff parser 会把 group /
   covergroup 映射到 functional 兼容键。

§7  Covergroup 架构
-------------------

``eh2_fcov_if`` 内部按微架构域组织 covergroup。它不是独立 agent，也不通过 TLM 发送
item；采样点全部来自 TB top 的层次引用。这样做的优势是信号路径短、采样条件接近 RTL；
代价是接口与 EH2 内部层级耦合，RTL 层级改动时必须同步维护。

.. list-table:: ``eh2_fcov_if`` covergroup 分层
   :header-rows: 1
   :widths: 26 34 40

   * - covergroup
     - 主要 coverpoint
     - 验证意义
   * - ``uarch_cg``
     - instruction category、stall、branch、flush、exception、interrupt
     - 观察流水线主要状态和控制事件
   * - ``csr_cg``
     - CSR access type
     - 区分 read/write/set/clear 路径
   * - ``dual_issue_cg``
     - I0/I1 category cross
     - 覆盖 EH2 双发射组合
   * - ``interrupt_cg``
     - interrupt source、NMI、debug cross
     - 覆盖 timer/software/external/NMI/CE interrupt
   * - ``csr_warl_cg``
     - CSR address、operation cross
     - WARL 行为和 EH2 custom CSR 访问覆盖
   * - ``instr_detail_cg``
     - branch/load/store/ALU/muldiv subtype
     - 指令类型细分
   * - ``controller_fsm_cg``
     - debug、exception、interrupt、flush reason
     - 控制流状态机等价覆盖
   * - ``pipeline_state_cg``
     - pipeline utilization、commit、stall cross
     - pipe occupancy 和 stall/commit 组合

关键代码（主微架构 covergroup）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
   :language: systemverilog
   :lines: 210-409
   :caption: dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:210-409

关键代码（CSR、dual issue、interrupt 和细分 covergroup）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/fcov/eh2_fcov_if.sv
   :language: systemverilog
   :lines: 421-770
   :caption: dv/uvm/core_eh2/fcov/eh2_fcov_if.sv:421-770

§8  与 PMP coverage 的边界
--------------------------

``eh2_fcov_if`` 负责主微架构和 CSR/指令/流水线功能覆盖，``eh2_pmp_fcov_if`` 负责 PMP/ePMP
专用空间。当前默认 TB top 中 ``PMPEnable=0``，因此 PMP coverage scaffold 存在但不应
被误读为默认配置已启用 PMP 硬件。PMP directed tests 和 coverage 计划见
:ref:`pmp_coverage`。

§9  与 Ibex 工业实现对照
-------------------------

Ibex 的覆盖率流同样采用 VCS/URG 和 DUT-only hierarchy 控制。EH2 与 Ibex 的差别在于
功能覆盖对象：Ibex 更围绕单核 RVFI、memory response、interrupt/debug 和 core-specific
coverpoint；EH2 增加双线程/双发射、PIC、EH2 custom CSR、AXI4 d-side notification、
PMP/ePMP scaffold 和 RVFI adapter sidecar。

.. list-table:: Coverage flow 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - 仿真器
     - VCS 主线
     - VCS 主线，NC 只用于波形单测
   * - 覆盖率维度
     - ``line+tgl+assert+fsm+branch``
     - 同一 5 维度，不使用 condition 作为 sign-off 维度
   * - hierarchy scope
     - ``core_ibex_tb_top.dut``
     - ``core_eh2_tb_top.dut``
   * - report
     - URG 原生输出
     - URG 原生输出，零后处理 dashboard
   * - 功能覆盖对象
     - Ibex core/RVFI/memory/debug
     - EH2 dual issue、trace/probe、CSR/PIC/PMP/AXI4

§10  参考资料
--------------

* :ref:`pmp_coverage` — PMP 覆盖率详解。
* :ref:`coverage_plan` — 覆盖率规划。
* :ref:`signoff_flow` — 签核门禁和 coverage parser。
* :ref:`appendix_b_uvm_fcov` — fcov 源码字典。
* :file:`dv/uvm/core_eh2/fcov/eh2_fcov_if.sv` — 主功能覆盖率接口。
* :file:`dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv` — PMP 覆盖率接口。
* :file:`dv/uvm/core_eh2/cover.cfg` — VCS coverage hierarchy scope。

§11  覆盖项字典：主微架构域
---------------------------

本节把 ``eh2_fcov_if`` 中最关键的 coverpoint 和 cross 按验证意图展开。它不是源码逐行
复制，而是面向 coverage review 的索引：看到 URG dashboard 的 GROUP hole 时，工程师
可以先在本表定位覆盖域，再回到源码和 directed testlist 找 stimulus。

.. list-table:: ``uarch_cg`` 覆盖项
   :header-rows: 1
   :widths: 24 28 48

   * - 覆盖项
     - bins / cross
     - 验证意义
   * - ``cp_i0_instr_category``
     - ALU、MUL、DIV、BRANCH、JUMP、LOAD、STORE、CSR、EBREAK、ECALL、MRET、FENCE、ATOMIC、ILLEGAL
     - 观察 I0 decode lane 的指令类别分布，是 directed 和 riscv-dv 指令混合的基础指标
   * - ``cp_i1_instr_category``
     - 同 I0，但采样 I1 lane
     - 验证双发射第二槽位不会长期空洞，尤其关注 load/store/CSR/branch 是否进入 I1
   * - ``cp_stall_type``
     - none、load、store、AMO、decode、presync、postsync、fetch
     - 把流水线停顿分成 LSU、decode、同步和 IFU 来源
   * - ``cp_i0_branch_taken``
     - taken、not_taken
     - 观察 I0 branch outcome，配合 branch predictor directed
   * - ``cp_i1_branch_taken``
     - taken、not_taken
     - 观察 I1 branch outcome，覆盖双发射中的分支槽位
   * - ``cp_i0_branch_mispredict``
     - mispredict、correct
     - 验证 I0 branch mispredict flush 触发路径
   * - ``cp_i1_branch_mispredict``
     - mispredict、correct
     - 验证 I1 branch mispredict 与 I0 的差异化路径
   * - ``cp_flush_type``
     - mispredict、exception、other
     - 将 flush 原因分成 branch、异常和其他 pipeline flush
   * - ``cp_exception_type``
     - inst access fault、illegal、ebreak、ecall
     - 覆盖 TLU exception entry 主路径
   * - ``cp_lsu_exception``
     - load misaligned
     - 观察 LSU exception 与 trace/cosim trap 对齐
   * - ``cp_interrupt_taken``
     - external、timer、software、NMI、CE
     - 覆盖 PIC/CLINT/NMI/CE interrupt 入口
   * - ``cp_debug_mode``
     - in_debug、not_debug
     - 覆盖 debug mode level
   * - ``cp_debug_halted``
     - halted、running
     - 覆盖 halt 状态，配合 JTAG/Halt-Run directed
   * - ``cp_dual_issue``
     - dual、single
     - 验证 dual issue 是否真正发生
   * - ``cp_i0_compressed``
     - compressed、uncompressed
     - 覆盖 I0 RVC 与 32-bit 指令混合
   * - ``cp_i1_compressed``
     - compressed、uncompressed
     - 覆盖 I1 RVC 与 32-bit 指令混合
   * - ``cp_icache_hit``
     - hit
     - 观察 IFU/ICache hit 事件
   * - ``cp_icache_miss``
     - miss
     - 观察 ICache miss/fill 相关 directed 是否生效
   * - ``cp_lsu_external_load``
     - external
     - 观察 D-side external load
   * - ``cp_lsu_external_store``
     - external
     - 观察 D-side external store
   * - ``cp_lsu_misaligned``
     - misaligned
     - 观察 LSU misaligned access
   * - ``stall_cross``
     - I0 instruction category × stall type
     - 检查不同指令类型下是否触发过主要 stall 原因
   * - ``branch_cross``
     - branch taken × mispredict
     - 区分 taken/correct、taken/mispredict、not-taken/correct、not-taken/mispredict
   * - ``interrupt_debug_cross``
     - interrupt taken × debug mode
     - 观察 interrupt 与 debug mode 组合，避免 debug 下 interrupt 路径完全缺失
   * - ``dual_issue_cross``
     - dual issue × I0 category
     - 检查双发射周期中的 I0 指令类别
   * - ``exception_stall_cross``
     - exception type × stall type
     - 覆盖异常与 stall 同时存在时的控制路径
   * - ``pipe_cross``
     - I0 category × I1 category
     - 双发射组合覆盖的核心 cross
   * - ``compressed_dual_cross``
     - I0 width × I1 width × dual issue
     - 覆盖 RVC 与 dual issue 组合

§12  覆盖项字典：CSR、interrupt 与 controller
---------------------------------------------

.. list-table:: CSR 与控制覆盖项
   :header-rows: 1
   :widths: 24 28 48

   * - 覆盖项
     - bins / cross
     - 验证意义
   * - ``csr_cg.cp_csr_access_type``
     - read、write、set、clear
     - 粗粒度观察 CSR 访问类型
   * - ``csr_warl_cg.cp_csr_addr``
     - mstatus、misa、mie、mtvec、mepc、mcause、mtval、mip、mcycle、debug CSR、EH2 custom CSR
     - 观察标准和 EH2 vendor CSR 是否被写入/读取
   * - ``csr_warl_cg.cp_csr_op``
     - read、write、set、clear
     - CSR 操作类型细分
   * - ``csr_addr_op_cross``
     - CSR address × CSR op
     - 验证每类 CSR 是否覆盖多种操作
   * - ``interrupt_cg.cp_int_source``
     - ext、timer、soft、NMI、CE
     - 与 IRQ agent、PIC directed、cosim MIP 通知直接相关
   * - ``interrupt_cg.cp_nmi_type``
     - nmi、regular
     - 区分 NMI 与普通 interrupt
   * - ``cp_int_in_debug``
     - interrupt source × debug mode
     - 覆盖 debug mode 下 interrupt 到达
   * - ``controller_fsm_cg.cp_debug_state``
     - running、debug_halted、debug_active
     - 用 coverpoint 表示分布式 debug state
   * - ``controller_fsm_cg.cp_exception_entry``
     - inst access fault、illegal、ebreak、ecall
     - 控制器异常入口覆盖
   * - ``controller_fsm_cg.cp_interrupt_entry``
     - ext、timer、soft、NMI、CE
     - 控制器中断入口覆盖
   * - ``controller_fsm_cg.cp_mret``
     - mret_taken
     - 异常返回路径覆盖
   * - ``controller_fsm_cg.cp_flush_reason``
     - mispredict、exception、pipe_flush
     - flush 原因覆盖
   * - ``debug_exception_cross``
     - debug state × exception entry
     - debug 下异常组合
   * - ``debug_interrupt_cross``
     - debug state × interrupt entry
     - debug 下 interrupt 组合
   * - ``exception_flush_cross``
     - exception entry × flush reason
     - 异常与 flush 交互
   * - ``mret_debug_cross``
     - mret × debug state
     - debug mode 与 MRET 组合

§13  覆盖项字典：指令细分与流水线状态
-------------------------------------

.. list-table:: 指令细分覆盖项
   :header-rows: 1
   :widths: 24 28 48

   * - 覆盖项
     - bins / cross
     - 验证意义
   * - ``dual_issue_cg.cp_i0_cat``
     - ALU、MUL、DIV、branch、jump、load、store、CSR
     - 双发射 I0 指令类别
   * - ``dual_issue_cg.cp_i1_cat``
     - ALU、MUL、DIV、branch、jump、load、store、CSR
     - 双发射 I1 指令类别
   * - ``dual_issue_cg.dual_cross``
     - I0 category × I1 category
     - 双发射组合矩阵
   * - ``instr_detail_cg.cp_branch_subtype``
     - BEQ、BNE、BGE、BLT、JAL
     - 分支细分类型
   * - ``instr_detail_cg.cp_load_subtype``
     - byte、half、word load
     - load width 覆盖
   * - ``instr_detail_cg.cp_store_subtype``
     - byte、half、word store
     - store width 覆盖
   * - ``instr_detail_cg.cp_alu_subtype``
     - add、sub、sll、srl、sra、slt、and、or、xor
     - ALU subtype 覆盖
   * - ``instr_detail_cg.cp_signed_ops``
     - signed/unsigned operand 组合
     - MUL/DIV signedness 覆盖
   * - ``instr_detail_cg.cp_muldiv_type``
     - mul、div、rem
     - M extension 细分覆盖
   * - ``instr_detail_cg.cp_sync_type``
     - presync、postsync、both
     - fence/CSR 同步类指令覆盖
   * - ``instr_detail_cg.cp_i0_width``
     - compressed、uncompressed
     - I0 指令宽度覆盖
   * - ``instr_detail_cg.cp_i0_category``
     - ALU、MUL、DIV、branch、jump、load、store、CSR
     - 指令细分域中的类别复用
   * - ``width_category_cross``
     - I0 width × I0 category
     - RVC 与指令类别组合
   * - ``pipeline_state_cg.cp_pipe_utilization``
     - both slots、i0 only、i1 only、neither
     - pipeline occupancy 覆盖
   * - ``pipeline_state_cg.cp_e4_commit``
     - dual commit、i0 only、i1 only、no commit
     - E4 commit 组合
   * - ``pipeline_state_cg.cp_stall``
     - stall type
     - pipeline state 域内复用 stall 分类
   * - ``pipeline_state_cg.cp_br_mispredict``
     - mispredict、correct
     - E4 commit 组合中的 branch miss 覆盖
   * - ``stall_pipe_cross``
     - pipe utilization × stall
     - occupancy 与 stall 交互
   * - ``commit_branch_cross``
     - E4 commit × branch mispredict
     - commit 与 branch miss 同周期组合

§14  Coverage review 方法
-------------------------

coverage review 不应只看 ``OVERALL``。建议按以下顺序审查：

1. 先确认 ``cover.cfg`` scope 是否仍是 ``core_eh2_tb_top.dut``，否则 line/branch
   数字可能混入 TB。
2. 再看 GROUP hole 是否集中在某个 covergroup，例如 ``dual_issue_cg`` 或
   ``controller_fsm_cg``。
3. 对每个 hole 找 stimulus 来源：directed ASM、riscv-dv option、IRQ/JTAG/Halt-Run
   sequence、PMP-enabled 配置或 formal property。
4. 最后判断 hole 是否应新增 directed、调整 riscv-dv constraint，还是以 waiver 记录
   为 unreachable/不适用。

.. list-table:: Coverage hole 到行动的映射
   :header-rows: 1
   :widths: 28 32 40

   * - Hole 类型
     - 常见原因
     - 行动
   * - I1 指令类别缺失
     - dual issue constraint 未命中或程序太串行
     - 增加 dual issue directed，调整 riscv-dv stream
   * - interrupt/debug cross 缺失
     - IRQ 与 debug stimulus 未重叠
     - 新增 debug-mode interrupt directed
   * - CSR address/op cross 缺失
     - CSR walk 未覆盖 set/clear 或 custom CSR
     - 扩展 ``directed_toggle_csr_walk.S`` 或 CSR unit test
   * - branch mispredict 缺失
     - predictor path 未被 directed 触发
     - 使用 IFU branch predictor directed ASM
   * - PMP bins 缺失
     - 默认 ``PMPEnable=0``
     - 使用 PMP-enabled 配置后再评估，不在默认 run 中误判
   * - ASSERT/FSM 低
     - RTL assertion/FSM report enable 或状态到达不足
     - 对照 formal property 和 VCS FSM cfg，避免仅靠随机测试补洞

§15  与脚本解析的关系
---------------------

``signoff.py`` 的 coverage parser 保留 ``functional`` 兼容键，是因为历史命令行参数和
部分旧 dashboard 使用 functional/covergroup 名称。当前文档面对用户时统一使用 URG
dashboard 名称 ``GROUP``。因此同一组数据在脚本内部可能叫 ``functional``，在报告中叫
``GROUP``；这不是两个覆盖域。

.. code-block:: text

   URG dashboard:
     GROUP 69.42%
        |
        v
   signoff parser aliases:
     group / covergroup / functional -> functional key
        |
        v
   Makefile gate:
     SIGNOFF_MIN_FUNCTIONAL_COV ?= 40

§16  典型命令与预期摘要
-----------------------

.. code-block:: bash

   make compile SIMULATOR=vcs COV=1
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   python3 dv/uvm/core_eh2/scripts/merge_cov.py --output build/cov_merged
   make signoff PROFILE=full SIMULATOR=vcs COV=1

预期摘要应使用 2026-05-19 demo 的同一组口径：

.. code-block:: text

   LINE     95.05%
   BRANCH   84.97%
   TOGGLE   53.52%
   ASSERT   33.33%
   FSM      54.74%
   GROUP    69.42%
   OVERALL  65.17%

§17  文档维护检查清单
---------------------

* 新增 covergroup 时，同步更新本章覆盖项字典和 :ref:`coverage_plan`。
* 修改 ``cover.cfg`` 时，同步更新 :ref:`build_flow`、:ref:`signoff_flow` 和
  :ref:`appendix_e_config/eh2_configs`。
* 修改 ``signoff.py`` alias 时，同步说明 GROUP/functional 兼容关系。
* 修改 TB top 层次引用时，重新跑 Sphinx，确保 literalinclude 和源码路径仍有效。
* 任何 coverage 数字更新必须全书同步：LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、
  ASSERT 33.33%、FSM 54.74%、GROUP 69.42%、OVERALL 65.17%。

§18  Coverage closure 工作流
----------------------------

Coverage closure 不是“把 OVERALL 拉高”这一件事。EH2 当前采用 VCS/URG 原生报告，review
应按源码、testlist、coverage dashboard 和 waiver 四个证据交叉确认。建议每次 closure
迭代都保存以下输入：

.. list-table:: Coverage review 输入
   :header-rows: 1
   :widths: 26 32 42

   * - 输入
     - 来源
     - 用途
   * - URG dashboard
     - ``merge_cov.py`` 输出目录
     - 查看 LINE/BRANCH/TOGGLE/ASSERT/FSM/GROUP/OVERALL
   * - Covergroup detail
     - URG group/covergroup 页面
     - 找到具体 coverpoint、bin 和 cross hole
   * - Testlist
     - directed/riscv-dv YAML
     - 判断是否已有 stimulus 但未命中，或根本缺少 test
   * - ASM / sequence
     - ``tests/asm``、``core_eh2_vseq.sv``
     - 确认 stimulus 是否真的驱动目标路径
   * - RTL hierarchy
     - ``core_eh2_tb_top.sv`` 层次引用
     - 判断 coverpoint 采样信号是否仍有效
   * - ADR / waiver
     - ``docs/adr``、waiver YAML
     - 判断 hole 是否可登记为不可达或阶段性限制

§19  Gate 与 dashboard 的关系
-----------------------------

当前 release gate 不直接把每个 coverage 维度都设成硬门槛。LINE、GROUP 等指标用于
签核可见 质量判断；BRANCH、TOGGLE、ASSERT、FSM 和 OVERALL 则提供结构性健康度。
这与 Ibex 的工业实践一致：门槛必须稳定、可解释，dashboard 则保留更多诊断维度。

.. list-table:: Coverage 指标使用方式
   :header-rows: 1
   :widths: 22 28 50

   * - 指标
     - 当前数值
     - 使用方式
   * - LINE
     - 95.05%
     - 确认 DUT subtree 大部分 RTL 被动态执行，防止 scope 漂移
   * - BRANCH
     - 84.97%
     - 查异常、flush、debug、interrupt 控制分支缺口
   * - TOGGLE
     - 53.52%
     - 作为低翻转信号诊断，不直接等价于功能 closure
   * - ASSERT
     - 33.33%
     - 观察 assertion cover/activation 状态，结合 formal 46/46 解读
   * - FSM
     - 54.74%
     - 结合 ``cov_fsm.cfg`` 和 reset filter 看状态机路径
   * - GROUP
     - 69.42%
     - covergroup/function coverage 主指标，脚本兼容名为 functional
   * - OVERALL
     - 65.17%
     - URG 综合展示，不替代逐维度 triage

.. warning::

   不要把 TOGGLE 或 OVERALL 低于某个心理预期解释成 sign-off 失败。EH2 当前 gate
   由 ``signoff.py`` 和 Makefile 参数定义；dashboard 里的每个数值都要结合 scope、
   采样条件和测试目标解释。

§20  Directed test 到 coverage hole 的闭环
------------------------------------------

当 GROUP hole 确认为真实 stimulus 缺失时，优先补 directed ASM 或 virtual sequence，
而不是调整 coverpoint bins。下面给出典型闭环：

.. code-block:: text

   URG hole
      |
      v
   定位 covergroup / coverpoint / bin
      |
      v
   查对应 RTL 信号和 testlist
      |
      +-- 已有 test 但未命中 -> 调整 test 或 sequence 时序
      |
      +-- 无 test -> 新增 directed ASM / riscv-dv constraint
      |
      v
   跑 targeted regress + merge_cov
      |
      v
   更新 coverage_plan / 文档 / waiver

.. list-table:: 典型 hole 的优先补洞方式
   :header-rows: 1
   :widths: 28 36 36

   * - Hole
     - 优先 stimulus
     - 复核章节
   * - dual issue I0/I1 组合
     - dual-issue directed ASM、riscv-dv stream constraint
     - :ref:`dual_thread`
   * - branch mispredict
     - IFU BP/BTB directed、taken/not-taken 混合程序
     - :ref:`icache`
   * - interrupt/debug cross
     - IRQ sequence + JTAG/Halt-Run sequence 组合
     - :ref:`agent_irq`、:ref:`agent_jtag`
   * - CSR custom address/op
     - CSR walk directed、CSR unit test
     - :ref:`csr`
   * - LSU misaligned/access error
     - directed LSU exception、AXI4 error injection
     - :ref:`agent_axi4`
   * - PMP mode/permission/lock
     - PMP-enabled config + PMP directed
     - :ref:`pmp_coverage`

§21  VCS FSM 配置解读
---------------------

FSM coverage 由 VCS 识别状态机后生成，结果受 FSM 配置和 reset filter 影响。EH2 仓库中
保留 ``cov_fsm.cfg`` 和 ``cov_fsm_reset_filter.cfg``，用于控制状态机识别和 reset
期间采样过滤。文档中不要把 FSM 54.74% 简化成“状态机只验证了一半”；它需要结合具体
FSM、reset 行为和不可达状态判断。

.. list-table:: FSM review 关注点
   :header-rows: 1
   :widths: 26 34 40

   * - 关注点
     - 问题
     - 行动
   * - reset-only state
     - reset 状态被计入未覆盖或 transition 缺失
     - 检查 reset filter 是否匹配当前 RTL
   * - debug rare state
     - debug/halt/JTAG 组合未触发
     - 补 debug directed 或确认 unreachable
   * - PIC priority state
     - 外部 interrupt 优先级路径不足
     - 补 PIC state walk directed
   * - DMA/DMI low activity
     - 默认 smoke 不触发相关状态
     - 使用 DMA/DMI directed 或登记阶段性限制
   * - Tool inference drift
     - VCS 版本或 RTL 编码导致状态机识别变化
     - 比较前后 URG FSM object 列表

§22  Coverage 数据一致性规则
-----------------------------

本手册的 coverage 数字必须作为一组原子事实更新。不能只改 LINE，不改 OVERALL；也不能
在某章写 GROUP，另一章写 functional 且数值不同。当前原子数据集如下：

.. code-block:: text

   Demo timestamp: 2026-05-19 01:02
   Status: PASS
   Tests: 102/104 (98.1%)
   Stages: 9/9 PASS
   LEC: 31635/31635 PASS

   LINE     95.05%
   BRANCH   84.97%
   TOGGLE   53.52%
   ASSERT   33.33%
   FSM      54.74%
   GROUP    69.42%
   OVERALL  65.17%

更新规则：

* 只有新的完整 demo 或 full sign-off 产生后，才更新上述全书数字。
* 更新时同时搜索旧数字，避免残留交叉章节不一致。
* 如果某次局部回归覆盖率不同，只能写成“局部 run 观察”，不能覆盖 release baseline。
* ``functional`` 只作为脚本兼容键出现，用户可见 dashboard 名称写 ``GROUP``。

§23  与 Ibex coverage closure 的一致点
--------------------------------------

EH2 的 coverage closure 刻意对齐 Ibex 三个核心实践。第一，使用 VCS 编译插桩和 URG
原生合并，不自制 dashboard 后处理。第二，coverage scope 在编译期限定到 DUT subtree，
防止 TB 或 UVM 代码污染 RTL 指标。第三，功能覆盖和代码覆盖分开 review：LINE/BRANCH
看 RTL reachability，GROUP 看验证意图命中。

EH2 的合理差异也必须保留：

* EH2 是双线程、双发射，覆盖项中有 I0/I1、thread、dual issue 组合。
* EH2 使用 AXI4 LSU/IFU/SB，总线覆盖与 Ibex memory interface 不同。
* EH2 有 PIC、DMA、DMI/JTAG、EH2 custom CSR 和 PMP/ePMP scaffold。
* EH2 scoreboard 的 trace/probe/AXI 三路输入使某些 coverage hole 需要同时看内部
  probe 与外部 transaction。

这些差异是 DUT 结构导致的，不应通过“像 Ibex 一样删掉 EH2 特有覆盖项”来获得更高
GROUP 分数。

§24  Coverage bind 文件的真实角色
---------------------------------

仓库中存在 ``eh2_fcov_bind.sv``，但当前 coverage interface 实例化在
``core_eh2_tb_top.sv`` 中完成，bind 文件主要作为 filelist 中的保留入口和说明。这样写是
因为 EH2 coverage 需要跨多个内部层级采样，直接在 TB top 中实例化 interface 并连接
hierarchical reference 更可控。

关键代码（coverage bind 保留入口说明）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv
   :language: systemverilog
   :lines: 1-15
   :caption: dv/uvm/core_eh2/fcov/eh2_fcov_bind.sv:1-15

.. list-table:: Bind 与 TB top 实例化对照
   :header-rows: 1
   :widths: 26 34 40

   * - 方式
     - 当前状态
     - 影响
   * - ``bind`` 到 RTL module
     - 当前未作为主路径
     - 对深层 hierarchy 不够灵活
   * - TB top 直接实例化
     - 当前主路径
     - 容易连接多个层级信号，但与 hierarchy 耦合
   * - filelist 保留 bind 文件
     - 当前保留
     - 为后续 bind 化或工具兼容留入口

§25  PMP coverage enable 语义
-----------------------------

PMP coverage interface 有自己的 enable 语义：只有 ``PMPEnable`` 参数为真时，才读取
``+enable_eh2_fcov`` plusarg；默认 ``PMPEnable=0`` 时强制关闭。这个逻辑避免默认 EH2
配置下把未启用的 PMP 硬件误计为 coverage hole。

关键代码（PMP coverage enable 与派生信号）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv
   :language: systemverilog
   :lines: 25-72
   :caption: dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv:25-72

.. list-table:: PMP coverage enable 判定
   :header-rows: 1
   :widths: 24 30 46

   * - ``PMPEnable``
     - ``+enable_eh2_fcov``
     - 行为
   * - ``0``
     - 任意
     - ``en_pmp_fcov=0``，不采样 PMP coverage
   * - ``1``
     - ``0`` 或未给
     - interface 存在但不采样
   * - ``1``
     - ``1``
     - PMP coverage 采样开启

§26  Coverage waiver 的使用
---------------------------

``dv/uvm/core_eh2/fcov/cov_waivers`` 中有 coverage waiver scaffold。waiver 的正确用途是
记录已确认不可达、阶段性不适用或工具限制导致的 coverage hole；它不能用来抬高真实
URG 数字，也不能替代 directed test。

.. list-table:: Coverage waiver 分类
   :header-rows: 1
   :widths: 28 34 38

   * - 分类
     - 示例
     - 要求
   * - 架构不可达
     - 某 dual issue 组合被 EH2 issue rule 禁止
     - 引用 RTL/设计说明，说明为什么不可达
   * - 配置不适用
     - 默认 ``PMPEnable=0`` 下 PMP bins
     - 明确配置条件和退出条件
   * - 工具限制
     - VCS FSM inference 误识别
     - 保留工具版本和复现方式
   * - 阶段性缺口
     - 后续 v1.2 directed 计划
     - 必须有 issue/ADR/计划项，不得永久沉默

§27  覆盖率与测试库的对应关系
------------------------------

05 章测试库和 coverage 章节需要一起维护。新增 directed ASM 后，如果它意图关闭某个
coverage hole，应在 testlist、coverage plan 和本章 hole 映射中都能找到对应关系。

.. list-table:: Test 类型到 coverage 域
   :header-rows: 1
   :widths: 26 34 40

   * - Test 类型
     - 主要 coverage 域
     - 说明
   * - smoke
     - basic fetch/retire/mailbox
     - 证明平台可运行，不用于 closure
   * - directed toggle
     - LINE/TOGGLE/CSR/muldiv/rf
     - 补低活动 RTL 区域
   * - directed PMP
     - PMP/ePMP covergroup
     - 需要 PMP-enabled 配置才有意义
   * - directed interrupt/debug
     - interrupt/debug/controller cross
     - 关闭优先级、halt/run、trap entry hole
   * - riscv-dv
     - 指令组合、异常、CSR、随机流
     - 提供广覆盖，但对特定 hole 需要 constraint
   * - compliance
     - ISA architectural subset
     - 主要证明标准兼容，不直接追求微架构 coverage

§28  采样条件审查
-----------------

coverpoint 的 bin 设计只是第一步，采样条件同样重要。采样过宽会把 reset/无效周期计入；
采样过窄会让真实 stimulus 无法命中。审查 ``eh2_fcov_if`` 时，建议对每个 covergroup
确认以下条件：

* 是否 gated by ``rst_l`` 或有效 retire/valid 信号。
* 是否区分 I0/I1 lane 的 valid。
* 异常、中断、debug、flush 是否在 RTL 状态稳定的周期采样。
* CSR address/op 是否在 CSR 操作实际提交时采样。
* LSU/IFU 事件是否避免把 speculative 或被 flush 的操作计入功能命中。
* PMP coverage 是否尊重 ``PMPEnable`` 和 ``en_pmp_fcov``。

§29  报告中 GROUP 与代码覆盖的解释模板
--------------------------------------

在 release note 或 sign-off 邮件中，建议使用下面的解释模板，避免把 coverage 数字写成
单一“通过/失败”：

.. code-block:: text

   Coverage 使用 VCS/URG 原生报告，编译维度为 line+tgl+assert+fsm+branch，
   scope 限定到 core_eh2_tb_top.dut。2026-05-19 01:02 demo 的结果为：
   LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、
   GROUP 69.42%、OVERALL 65.17%。GROUP 对应 SystemVerilog covergroup/function
   coverage；脚本内部 functional 名称仅为兼容键。

这个模板把工具、scope、时间戳和指标名放在一起，能减少历史数据和当前数据混用的风险。

§30  维护后的验证命令
---------------------

修改 coverage 文档、covergroup 或 coverage flow 后，建议至少执行：

.. code-block:: bash

   make compile SIMULATOR=vcs COV=1
   make regress TESTLIST=directed SIMULATOR=vcs COV=1 PARALLEL=4
   python3 dv/uvm/core_eh2/scripts/merge_cov.py --output build/cov_merged
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

若只改文档，最后一条 Sphinx 构建和红线扫描即可；若改 ``eh2_fcov_if``、
``eh2_pmp_fcov_if``、``cover.cfg`` 或 ``merge_cov.py``，必须跑实际 VCS/URG coverage
链路，确认 dashboard 仍使用 5 维度且 scope 没漂移。

§31  Covergroup 新增流程
------------------------

新增 covergroup 或 coverpoint 时，推荐使用“小步闭环”流程，避免一次性加入大量 bins 后
无法判断 hole 是否来自 stimulus、采样条件还是 bin 设计。

.. code-block:: text

   1. 选定验证意图
   2. 找到稳定采样信号和 valid 条件
   3. 新增最小 coverpoint
   4. 写一个 directed 或定位已有 test
   5. VCS COV 运行并确认 bin 命中
   6. 再增加 cross / ignore_bins / waiver
   7. 更新文档、coverage_plan 和 testlist 注释

.. list-table:: 新增 covergroup 审查点
   :header-rows: 1
   :widths: 28 34 38

   * - 审查点
     - 问题
     - 期望
   * - 验证意图
     - 这个 bin 证明什么？
     - 能对应到架构或微架构风险
   * - 采样条件
     - reset/flush/speculative 周期是否排除？
     - 只在有效事件周期采样
   * - Bin 数量
     - 是否过度组合导致不可收敛？
     - 先覆盖关键类别，再扩展 cross
   * - Ignore/illegal bins
     - 是否有 RTL 规则禁止的组合？
     - 用注释和 ADR/设计说明支撑
   * - Directed test
     - 是否有最小 stimulus 证明可命中？
     - 至少一个 targeted test
   * - Ibex 对照
     - 是否复用了合理方法论？
     - 不复制 Ibex 单核假设

§32  ``ignore_bins`` 与 waiver 的边界
--------------------------------------

``ignore_bins`` 是 covergroup 设计的一部分，表示某些组合在该 coverage model 中不应统计；
waiver 是 review 阶段对已生成 hole 的解释。二者不能混用。若组合由 ISA、EH2 issue rule
或配置参数确定为不可达，优先在 covergroup 中用 ``ignore_bins`` 或条件化采样表达；若
是阶段性缺口或工具限制，则用 waiver 记录。

.. list-table:: ``ignore_bins`` vs waiver
   :header-rows: 1
   :widths: 26 34 40

   * - 机制
     - 使用时机
     - 例子
   * - ``ignore_bins``
     - coverage model 设计时
     - issue rule 禁止的 dual issue 组合
   * - ``illegal_bins``
     - 不应发生且发生即代表错误
     - CSR op 编码非法但被采样
   * - waiver
     - review 后登记例外
     - PMP disabled 配置下的 PMP hole
   * - directed 补洞
     - stimulus 缺失但可达
     - debug interrupt overlap 未命中

§33  Coverage 与 LEC/SYN 的关系
-------------------------------

动态 coverage 不能证明综合后网表等价，LEC 也不能证明所有功能点被动态测试。2026-05-19
demo 同时给出 coverage 和 LEC 数据：coverage dashboard 显示 LINE 95.05%、GROUP
69.42%、OVERALL 65.17%；LEC 显示 31635/31635 PASS。二者分别支撑“动态验证覆盖了哪些
RTL/功能”和“综合变换是否保持等价”。

.. list-table:: Coverage 与 LEC 分工
   :header-rows: 1
   :widths: 26 34 40

   * - 维度
     - Coverage
     - LEC
   * - 对象
     - RTL 仿真和 covergroup
     - RTL vs gate/block netlist
   * - 工具
     - VCS/URG
     - Formality
   * - 输出
     - LINE/BRANCH/TOGGLE/ASSERT/FSM/GROUP/OVERALL
     - compare points pass/fail
   * - 当前数据
     - OVERALL 65.17%
     - 31635/31635 PASS
   * - 不能替代
     - 不能证明综合等价
     - 不能证明 stimulus 覆盖充分

§34  Coverage 数字常见误读
---------------------------

.. list-table:: 常见误读与纠正
   :header-rows: 1
   :widths: 34 66

   * - 误读
     - 纠正
   * - “LINE 高就代表功能验证充分”
     - LINE 只说明代码被执行，功能意图要看 GROUP、directed 和 cosim。
   * - “TOGGLE 低说明 release 失败”
     - TOGGLE 是诊断指标，受 scope、低功耗/静态配置和 debug/PIC/DMA 活动影响。
   * - “ASSERT 33.33% 表示 assertion 失败”
     - ASSERT coverage 表示 assertion/cover activation，不等价于 assertion pass/fail。
   * - “GROUP 就是脚本里的另一个 coverage”
     - GROUP 是 URG dashboard 名称；脚本 ``functional`` 是兼容键。
   * - “OVERALL 可以单独做 gate”
     - OVERALL 混合多个维度，review 必须回到逐维度和具体 hole。
   * - “NC 波形 run 的覆盖率也能用于 sign-off”
     - 当前 sign-off coverage 只使用 VCS/URG 主线。

§35  本章维护结论
-----------------

功能覆盖率章节的核心任务是把“验证意图”与“工具数字”连接起来。EH2 当前 coverage flow
已经回到 VCS/URG 主线，使用 5 维度编译插桩、DUT-only scope 和 URG 原生 dashboard。
后续维护要避免两类错误：一是把历史 NC/IMC 数据或旧 condition 维度带回当前口径；二是
只追逐 OVERALL，而不分析 GROUP hole、test stimulus 和 RTL 可达性。正确的 closure
应同时给出数字、hole 解释、补洞计划和 waiver/ADR 证据。

§36  Coverage review 会议模板
------------------------------

正式 review 建议按固定模板记录，避免每次只截图 dashboard。模板如下：

.. code-block:: text

   Run: <date/time, git sha, simulator>
   Command: make signoff PROFILE=full SIMULATOR=vcs COV=1
   Scope: core_eh2_tb_top.dut
   Metrics: LINE/BRANCH/TOGGLE/ASSERT/FSM/GROUP/OVERALL
   New holes:
     - <covergroup.coverpoint.bin>
     - root cause: stimulus missing / unreachable / tool / config
     - action: directed / riscv-dv constraint / ignore_bins / waiver
   Regressions:
     - <metric delta and suspected change>
   Decision:
     - accept / add test / add waiver / block release

.. list-table:: Review 角色
   :header-rows: 1
   :widths: 26 34 40

   * - 角色
     - 关注点
     - 输出
   * - RTL owner
     - hole 是否设计不可达
     - 设计解释或 RTL 修复建议
   * - DV owner
     - stimulus 是否充分
     - directed/riscv-dv/sequence 计划
   * - Flow owner
     - VCS/URG/scope 是否正确
     - 工具或脚本修复
   * - Sign-off owner
     - gate/waiver 是否可接受
     - release 决策记录

§37  Coverage regression triage
-------------------------------

覆盖率下降不一定是功能退化，也可能是 scope 修正、testlist 变化、随机 seed 分布或工具版本
变化。triage 时先判断是“真实少跑了路径”，还是“统计口径变化”。

.. list-table:: Coverage regression 分类
   :header-rows: 1
   :widths: 28 34 38

   * - 分类
     - 现象
     - 处理
   * - Scope 变化
     - LINE/BRANCH 大幅跳变
     - 比较 ``cover.cfg`` 和 VCS compile log
   * - Testlist 变化
     - GROUP 局部 covergroup 降低
     - 对比 YAML、seed 和 enabled tests
   * - RTL 重构
     - LINE/FSM object 增减
     - 分析新增 unreachable 或状态机识别变化
   * - Stimulus 退化
     - 特定 bins 从 hit 变 miss
     - bisect directed/riscv-dv change
   * - Tool 版本变化
     - FSM/ASSERT 变化明显
     - 保存 VCS/URG 版本和 dashboard diff

§38  Coverage 与风险登记
-------------------------

不是所有 coverage hole 都要立即阻断 release，但每个重要 hole 都要进入风险登记或计划。
``07_decisions/risk_register.rst`` 应引用本章的 hole 分类，说明风险、影响、缓解措施和
退出条件。

.. list-table:: Hole 到风险登记
   :header-rows: 1
   :widths: 28 34 38

   * - Hole
     - 风险
     - 缓解
   * - debug interrupt cross
     - debug 下 interrupt 优先级未动态覆盖
     - debug directed + cosim compare
   * - PMP disabled bins
     - 默认配置无法证明 PMP 行为
     - PMP-enabled profile + formal/PMP directed
   * - DMA low toggle
     - DMA 边界动态活动不足
     - DMA directed 或明确 out-of-scope
   * - FSM rare state
     - 状态机异常路径未触达
     - directed 或 formal property
   * - custom CSR op cross
     - CSR WARL 行为覆盖不足
     - CSR unit test + directed CSR walk

§39  Checklist：coverage flow 修改
----------------------------------

修改 coverage flow 前后，检查：

* ``Makefile`` 和 ``rtl_simulation.yaml`` 中 VCS coverage option 保持 5 维度。
* ``cover.cfg`` 仍使用 ``core_eh2_tb_top.dut`` scope。
* ``merge_cov.py`` 仍调用 URG 原生合并，不做自定义 dashboard 合成。
* ``signoff.py`` 的 GROUP/functional alias 与文档一致。
* 05、06、07 和 appendix E/F 中的 coverage 数字同步。
* NC/Incisive 仍只作为波形调试入口。
* Sphinx 文档和 VCS/URG 实跑数据都已验证。

§40  Checklist：covergroup 修改
-------------------------------

修改 ``eh2_fcov_if`` 或 ``eh2_pmp_fcov_if`` 前后，检查：

* covergroup 名称、coverpoint 名称和文档字典同步。
* 采样条件避开 reset 和无效周期。
* 新增 bins 有至少一个 test 或明确 waiver/ignore 策略。
* cross 数量不会造成不可收敛的 closure 负担。
* PMP coverage 尊重 ``PMPEnable``。
* directed/riscv-dv testlist 已记录新增覆盖意图。
* URG GROUP 结果能定位到新增 covergroup。

§41  Release 摘要中的 coverage 口径
-----------------------------------

对外发布 coverage 摘要时，建议固定写法，避免把局部 run、历史 NC 迁移数据和当前 VCS
主线 demo 混在一起。

.. code-block:: text

   Coverage was collected with Synopsys VCS using -cm line+tgl+assert+fsm+branch.
   The compile-time scope is restricted by cover.cfg to core_eh2_tb_top.dut, and
   reports are generated by native URG merge/dashboard. The 2026-05-19 01:02
   demo reported LINE 95.05%, BRANCH 84.97%, TOGGLE 53.52%, ASSERT 33.33%,
   FSM 54.74%, GROUP 69.42%, and OVERALL 65.17%.

中文摘要：

.. code-block:: text

   覆盖率由 VCS 以 line+tgl+assert+fsm+branch 五维度插桩收集，cover.cfg 在编译期
   限定 core_eh2_tb_top.dut 子树，报告由 URG 原生合并生成。2026-05-19 01:02
   demo 结果为 LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、
   FSM 54.74%、GROUP 69.42%、OVERALL 65.17%。

§42  Coverage issue 关闭条件
-----------------------------

coverage issue 不能只以“数字变高了”关闭。建议至少满足以下条件之一：

* 新增 directed/riscv-dv stimulus 后，目标 bin/cross 在 URG 中命中。
* 经 RTL owner 确认不可达，并在 covergroup 中加入 ``ignore_bins`` 或在 waiver 中记录。
* 配置不适用，例如 PMP disabled，对应 hole 已关联配置条件和退出计划。
* 工具识别问题已通过 VCS/URG 版本、最小复现和 waiver 记录。
* 指标下降是 scope 修正或 RTL 重构导致，并有新 baseline 说明。

关闭记录应包含：run 时间、git SHA、命令、dashboard 路径、目标 coverpoint、处理方式和
后续动作。

§43  与 appendix 的分工
-----------------------

本章解释 coverage 架构、数据口径和 review 方法；逐文件逐 covergroup 的源码字典应放在
``appendix_b_uvm``，工具命令细节放在 ``appendix_c_tools`` 和 ``appendix_f_scripts``。
这样 05 章保持架构层可读，附录负责更深的源码/工具细节。

.. list-table:: Coverage 文档分工
   :header-rows: 1
   :widths: 28 34 38

   * - 章节
     - 内容
     - 读者
   * - 本章
     - coverage 架构、指标、review、Ibex 对照
     - DV owner、sign-off reviewer
   * - :ref:`pmp_coverage`
     - PMP/ePMP 专用 coverage
     - PMP feature owner
   * - :ref:`coverage_plan`
     - closure 计划和风险
     - release/sign-off owner
   * - ``appendix_b_uvm``
     - covergroup 源码字典
     - 维护 ``eh2_fcov_if`` 的工程师
   * - ``appendix_c_tools``
     - VCS/URG 工具手册
     - flow/tool owner
   * - ``appendix_f_scripts``
     - ``merge_cov.py`` / ``signoff.py`` 解析
     - script owner

§44  Coverage baseline 版本化
------------------------------

coverage baseline 应随 release 或重要 sign-off run 版本化。baseline 记录不只是数字，还
包括工具版本、命令、scope、testlist、waiver 和 git SHA。没有这些上下文，数字变化无法
判断是设计质量变化、测试变化还是工具口径变化。

.. list-table:: Baseline 记录字段
   :header-rows: 1
   :widths: 28 34 38

   * - 字段
     - 示例
     - 用途
   * - Timestamp
     - ``2026-05-19 01:02``
     - 与文档数字对应
   * - Git SHA
     - 当前验证平台 commit
     - 复现源码状态
   * - Simulator
     - VCS
     - 对齐主线工具
   * - Coverage opts
     - ``line+tgl+assert+fsm+branch``
     - 防止维度漂移
   * - Scope
     - ``core_eh2_tb_top.dut``
     - 防止 TB 污染
   * - Test summary
     - ``102/104 (98.1%)``
     - 解释 coverage 输入质量
   * - Waiver
     - cosim/coverage waiver 文件
     - 解释例外

§45  Dashboard diff 方法
------------------------

对比两个 coverage run 时，建议从粗到细：

1. 先比较总测试数量、通过率和 stage 是否一致。
2. 比较 coverage opts 和 ``cover.cfg`` 是否完全一致。
3. 比较 LINE/BRANCH/GROUP 的大幅变化。
4. 进入 URG detail，定位具体 module、covergroup 或 bin。
5. 回到 testlist/seed，判断 stimulus 是否变化。
6. 只有确认口径一致后，才把差异归因于 RTL 或测试质量。

.. list-table:: Diff 结论模板
   :header-rows: 1
   :widths: 32 68

   * - 结论
     - 证据
   * - Scope drift
     - ``cover.cfg`` 或 compile log 不同
   * - Test drift
     - testlist/seed/pass rate 不同
   * - RTL drift
     - module line/branch object 变化
   * - Stimulus regression
     - 同一 coverpoint bin 从 hit 变 miss
   * - Tool drift
     - VCS/URG 版本或 FSM object list 变化

§46  Coverage 与文档链接
------------------------

每个重要 coverage 域都应能链接到对应设计或验证章节，便于 review 时从数字跳到背景：

.. list-table:: Coverage 域到文档链接
   :header-rows: 1
   :widths: 28 34 38

   * - Coverage 域
     - 设计章节
     - 验证章节
   * - dual issue
     - :ref:`dual_thread`
     - :ref:`tests_library`
   * - IFU/branch
     - :ref:`icache`
     - :ref:`agent_trace`
   * - LSU/load-store
     - :ref:`bus_axi_ahb`
     - :ref:`agent_axi4`
   * - CSR
     - :ref:`csr`
     - :ref:`tests_library`
   * - interrupt/PIC
     - :ref:`pic`
     - :ref:`agent_irq`
   * - debug
     - :ref:`debug`
     - :ref:`agent_jtag`
   * - PMP
     - :ref:`csr`
     - :ref:`pmp_coverage`

§47  最终维护摘要
-----------------

本页达到阶段 5 完成标准时，应满足：覆盖率架构、当前数据、VCS/URG flow、cover.cfg
scope、covergroup 字典、PMP 边界、Ibex 对照、review 方法和 issue 关闭条件都可在本页
找到；所有数字与 2026-05-19 demo 保持一致；没有把 NC/IMC 或旧 condition 维度写成
当前 sign-off 事实。后续维护时，任何覆盖率数字变更都必须全书同步并附带新的可复现
baseline。
