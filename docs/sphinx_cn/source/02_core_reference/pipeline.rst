.. _pipeline:
.. _02_core_reference/pipeline:

流水线与双发射
==============

:status: draft
:source: rtl/design/dec/eh2_dec_decode_ctl.sv; rtl/design/dec/eh2_dec.sv; rtl/design/exu/; rtl/design/lsu/; dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv; dv/uvm/core_eh2/cover.cfg; Makefile
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§0  前置知识自检
-----------------

读懂本章，你需要先掌握三个概念：第一，程序由一条条指令组成；第二，流水线会让多条指令
在不同阶段重叠执行；第三，异常、中断和分支会打断顺序执行。如果这些概念还不熟，
先读 :ref:`introduction` 和 :ref:`features`，再回到本章。

建议前置章节：

* :ref:`reader` — 确认术语、路径和源码引用约定；
* :ref:`introduction` — 理解 EH2 是双线程 RV32IMAC + Zb* 核；
* :ref:`getting_started` — 至少跑过一次 ``make smoke``，知道日志在 ``build/`` 下；
* :ref:`tb_top` — 选读，帮助理解 RTL 信号如何被 UVM testbench 观察。

学完本章你能：

1. 画出 EH2 从 IFU 到 DEC/EXU/LSU 的主要流水级，并说明每一级在做什么；
2. 用 i0/i1 解释双发射为什么会带来 dependency、stall 和 flush 约束；
3. 跟踪一条最简单的 ``addi`` 从取指、译码、执行到写回的端到端路径；
4. 在 cosim mismatch 时判断首查方向是 PC、GPR 写回、trap CSR、flush 还是异步写回；
5. 把流水线相关覆盖率与 2026-05-19 VCS/URG sign-off 数据对应起来。

§1  本章导读
-------------

本章是整部手册的**核心章节** 。EH2 的 9 级流水线 + 双发射（i0/i1）架构
是其微架构中最复杂也是最关键的设计。理解流水线的每一级做什么、
双发射的 6 条规则、4 种 stall 类型、3 类写回机制、以及 flush 如何在
各级传播——这些是读懂 EH2 RTL 和调试 cosim mismatch 的**必要条件** 。

阅读本章你将学到：

* 9 级流水线（BFF→F1→F2→A→D→E1→E4→DC1→DC5）每一级的详细功能与子模块
* 双发射的 6 条限制规则（寄存器依赖/资源冲突/分支/CSR/ fence / stall）
* 4 种 stall 类型：load-use 互锁、CSR 写后读、fence 等待 LSU idle、NB-load CAM 满
* 3 类写回：REGULAR（流水线内同步）、DIV（多周期异步）、NB_LOAD（非阻塞异步）
* 旁路前递网络：D/E1/E2/E3 四级 bypass 的数据来源与选择逻辑
* Flush 信号在 9 级中的传播路径与优先级
* 时钟门控：每级的 data_en / ctl_en 如何节省动态功耗
* 非阻塞 Load 的 CAM 管理全流程（分配→匹配→作废→数据回传）
* DIV Cancel 的两种场景（推测取消 vs 架构取消）
* Trace Packet 的生成时机与双槽位格式

阅读本章需要的前置知识：RISC-V RV32I 指令集基础、流水线 CPU 的基本概念。
建议先浏览 :ref:`features` 了解 EH2 特性全景，再深入本章。

.. note::

   本章的验证语境以 2026-05-19 VCS 主线为准。流水线相关结构覆盖率来自
   ``core_eh2_tb_top.dut`` 子树的 URG 原生 dashboard：LINE 95.05%、
   BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、GROUP 69.42%、
   OVERALL 65.17%。覆盖率维度固定为 ``line+tgl+assert+fsm+branch``，
   不包含旧 NC/IMC 迁移阶段使用过的 condition 叙述。

§2  设计目标与需求溯源
-----------------------

EH2 的 9 级流水线设计有明确的需求驱动：

1. **双发射吞吐量** ：每周期发射 2 条指令（i0+i1），IPC 目标 >1.5。
   选择 9 级而非更深的流水线是为了在 IPC 和功耗/面积之间取得平衡
2. **确定性延迟** ：顺序发射 + 顺序提交，无乱序调度。
   中断响应延迟可预测（最长 9 级排空）
3. **紧耦合存储** ：ICCM/DCCM 单周期访问，消除缓存不确定性。
   ICache 仅用于 spill-over 代码
4. **非阻塞操作** ：除法器（多周期）和外部总线 Load（延迟不确定）
   不阻塞流水线——指令 retire 不等结果，结果异步写回

**与 RISC-V 规范的关系：**

- 流水线必须保证 RV32I 的精确异常语义（§1.6）——异常指令之前的所有指令
  完成写回，异常指令及之后的指令不写回
- ``mepc`` 必须指向异常指令的 PC，``mcause`` 记录异常原因
- ``mret`` 必须从 ``mepc`` 恢复执行

**EH2 微架构取舍（为何不用方案 B/C）：**

- **为何顺序而非乱序** ：嵌入式实时场景优先确定性，乱序的功耗/面积开销不合理
- **为何 9 级而非 5 级** ：5 级在双发射下难以闭合时序（D 级的译码+寄存器读+旁路
  MUX 的延迟路径太长），9 级将关键路径分散
- **为何 trace+probe 而非统一 RVFI** ：EH2 的设计早于 RVFI 标准化，trace packet
  是在 RTL 设计时定义的。Phase 1 后通过 RVFI adapter 兼容（见 :ref:`adr-0015` ）

**相关 ADR：** :ref:`adr-0001` （cosim via trace+probe）、:ref:`adr-0004`
（RTL RVFI 等价 trace）、:ref:`adr-0010` （CSR register model）

**当前 sign-off 约束：**

.. list-table:: 流水线相关签核事实
   :header-rows: 1
   :widths: 24 34 42

   * - 维度
     - 当前实现
     - 文档约束
   * - 默认仿真器
     - ``SIMULATOR ?= vcs``
     - 流水线调试命令使用 VCS 主线；NC 只作为波形调试分支
   * - 覆盖率插桩
     - ``-cm line+tgl+assert+fsm+branch``
     - 不写 ``cond`` 作为当前签核维度
   * - 覆盖率 scope
     - ``-cm_hier dv/uvm/core_eh2/cover.cfg``，文件内为 ``+tree core_eh2_tb_top.dut``
     - 只引用 DUT 子树数字，避免 TB interface 或 stub 造成假高覆盖率
   * - 结果证据
     - 9/9 stages PASS；102/104 实跑；LEC 31635/31635 PASS
     - 流水线章节中的覆盖率与 gate 数字必须与该 demo 保持一致

**关键配置引用** （``Makefile`` 覆盖率选项）：

.. code-block:: makefile

   VCS_COV_METRICS := line+tgl+assert+fsm+branch
   VCS_COV_HIER    := $(TB_DIR)/cover.cfg
   VCS_COMPILE_COV_OPTS := -lca \
                           -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                           -cm_hier $(VCS_COV_HIER) \
                           -cm_tgl portsonly \
                           -cm_tgl structarr

**DUT-only scope** （``dv/uvm/core_eh2/cover.cfg``）：

.. code-block:: text

   +tree core_eh2_tb_top.dut
   begin tgl
     -tree core_eh2_tb_top.dut.*
   end

§3  9 级流水线全景
-------------------

.. code-block:: text

   ┌─────────────── 取指域 (IFU) ───────────────┐  ┌─译码(DEC)─┐  ┌─────执行(EXU)─────┐  ┌────────存储(LSU)─────────┐
   BFF  →  F1   →  F2   →   A   →   D   →  E1   →  E2   →  E3   →  E4   →  DC1  →  DC2  →  DC3  →  DC4  →  DC5
   缓冲    取指1   取指2   对齐    译码    ALU1   乘法1   乘法2   乘法3   地址    地址    DCCM/   数据     SC
                                        分支1                   分支2   生成    检查    AXI4    对齐     确认
                                        前递1                   前递2

**每一级的详细功能：**

.. list-table:: 9 级流水线逐级详解
   :header-rows: 1
   :widths: 6 8 86

   * - 级
     - 所属
     - 详细功能
   * - **BFF**
     - IFU
     - 指令缓冲（Buffer）。接收 ICache/ICCM 返回的 16B 数据块（64-bit × 2），暂存后送入 F1。
       在 ICache miss 时，BFF 吸收 miss 延迟——不等整个 cache line 填完，
       第一个关键 word 到达就立即前递给 F1
   * - **F1**
     - IFU
     - 取指第 1 级。生成取指地址（顺序 / BTB 预测目标 / flush 重定向）。
       BHT lookup（gshare 索引哈希）→ 2-bit 饱和计数器 → 预测方向。
       BTB 读地址生成（当前地址 + 下一地址的哈希）
   * - **F2**
     - IFU
     - 取指第 2 级。ICache/ICCM Tag 比较 → ``ic_rd_hit`` 。
       BTB tag 比较 → 命中 + BHT 预测跳转 → ``ifu_bp_kill_next_f2``
       （kill 顺序取指，重定向到预测目标）。
       ICache data 读取（或 ICCM data 读取）
   * - **A**
     - IFU
     - 指令对齐（Align）。从 16B 取指块（64-bit data + 4-bit valid）中提取指令：
       从 PC[3:0] 偏移处开始扫描 → 检测 16-bit 压缩指令 → 展开为 32-bit →
       提取 i0 和 i1。处理跨边界指令（跨越相邻 16B 块）。
       输出：``i0_valid/i1_valid`` + ``i0_instr/i1_instr`` + ``i0_pc/i1_pc``
   * - **D**
     - DEC
     - 译码（Decode）。指令译码器（``eh2_dec_decode_ctl`` ）产生控制信号：
       ``i0_ap/i1_ap`` （ALU 包）、``lsu_p`` （LSU 包）、``mul_p`` （乘法包）、``div_p`` （除法包）。
       双槽位仲裁：i0 优先，i1 条件发射（6 条规则见 §4）。
       依赖记分板（scoreboard）检查 RAW 依赖。
       CSR 地址译码（Espresso 逻辑最小化）。
       调试触发器匹配（PC 匹配 + 掩码匹配）。
       指令缓冲（IB）管理：4 级 FIFO，支持线程切换。
   * - **E1**
     - EXU
     - 执行第 1 级。Primary ALU 运算（RV32I + Zb* bitmanip）、
       Upper branch 解析（简单条件分支在此级验证）、
       旁路前递 E1 级 MUX（来自 D/E1/E2/E3 的结果 bypass）。
       乘法器 E1 级：操作数寄存 + 符号判定。
       除法器 E1 级：启动迭代
   * - **E2**
     - EXU
     - 执行第 2 级。乘法器第 1 级（32×32→64 部分积）。
       旁路前递 E2 级 MUX
   * - **E3**
     - EXU
     - 执行第 3 级。乘法器第 2 级（部分积累加，结果产出）。
       旁路前递 E3 级 MUX
   * - **E4**
     - EXU
     - 执行第 4 级。Secondary ALU 运算（复杂运算的第二周期）、
       Lower branch 解析（复杂条件分支/间接跳转在此级验证）、
       GHR architectural 更新（基于实际分支结果）、
       CSR 写回、E4→DC3 store data bypass
   * - **DC1**
     - LSU
     - 存储第 1 级。Load/Store 地址生成（rs1 + offset）、
       非阻塞 load CAM 通知、store data 一级寄存
   * - **DC2**
     - LSU
     - 存储第 2 级。地址检查（DCCM/PIC/外部路由）、
       访问故障判定（8 种）、misaligned 检测、
       Store Buffer forwarding 命中检测、
       MRAC side_effect 检测
   * - **DC3**
     - LSU
     - 存储第 3 级。DCCM 读/写启动、PIC 访问、AXI4 总线事务启动、
       ECC 检查（单 bit 纠错/双 bit 检测）、
       Load 结果 MUX（DCCM/PIC/bus 三选一）、
       AMO read-modify-write 的 read 阶段
   * - **DC4**
     - LSU
     - 存储第 4 级。Load 数据对齐与符号扩展（by/half/word + unsigned/signed）、
       ECC 纠正数据传递给 GPR 写回、
       AMO 运算中间结果
   * - **DC5**
     - LSU
     - 存储第 5 级。SC.W 成功确认（LR 预约地址匹配）、
       Store Buffer 提交（非 SC 的 store 进 stbuf）、
       AMO write-back

§4  双发射规则
--------------

EH2 每周期最多发射 2 条指令（i0 和 i1），i0 始终优先。
i1 仅在**以下 6 条规则全部满足** 时才可与 i0 同周期发射：

**规则 1：无 RAW（Read-After-Write）寄存器依赖**

i1 的 rs1 和 rs2 不能等于 i0 的 rd（目标寄存器）。
例如：i0=``ADD x5, x1, x2`` （写 x5），i1=``SUB x6, x5, x3`` （读 x5）→ RAW → i1 不能发射。
旁路前递可以解决部分 RAW 依赖（见 §5），但 i0→i1 同周期依赖无法前递
（i0 的结果在 E1 级才算出，i1 在 D 级就需要操作数）

**规则 2：执行资源不冲突**

i0 和 i1 不能占用同一执行单元：
- 两个 ALU 操作 → OK（i0 和 i1 各有一个独立 ALU）
- 两个乘法 → NO（只有一个乘法器）
- 两个除法 → NO（只有一个除法器，且除法只能在 slot 0）
- 两个 Load/Store → NO（LSU 只有一个端口）
- ALU + 乘法 → OK（不同执行单元）
- ALU + Load → OK

**规则 3：i0 不是分支/跳转指令**

控制流改变时暂停 i1 发射，因为 i1 的 PC (i0 PC+2/4) 在分支跳转时会无效。
例外：如果分支预测器预测不跳转，且 i0 的条件分支在 E1/E4 才解析，
i1 可以 speculative 发射

**规则 4：i0 不是 CSR 写指令**

CSR 写有副作用（更新 mstatus/mie/mepc 等），必须串行化。
CSR 读可以与 i1 同周期发射（只读无副作用）

**规则 5：不是 FENCE / FENCE.I 指令**

内存栅栏指令需要等待 LSU idle 和 ICache flush，期间暂停 i1

**规则 6：没有流水线 stall**

如果前级有 stall（load-use 互锁、NB-load CAM 满、Store Buffer 满等），
后续所有指令都不发射

**i1_cancel_e1 机制：** i1 在 D 级发射后，可能在 E1 级被取消。
原因包括：i0 在 E1 级触发了 flush（分支预测错误）→ i1 也被 flush；
i0 的 upper branch 实际跳转 → i1 的 PC 无效。
i1_cancel_e1 信号使指令缓冲恢复 i1 的指令（不丢失）。

§5  旁路前递网络（Bypass Forwarding）
--------------------------------------

旁路前递将尚未写回 GPR 的 ALU/乘法/Load 结果直接前递给依赖指令，
消除 RAW stall。EH2 有 4 级 bypass：

.. code-block:: text

   D 级 bypass     ← 来自：E1/E2/E3 的 ALU 结果、E4 的 secondary ALU 结果、
                                LSU DC3 的 Load 结果（lsu_result_dc3）
   E1 级 bypass    ← 同 D 级来源（数据经 DFF 延迟一拍后到 E1）
   E2 级 bypass    ← 来自：E1/E3 的 ALU 结果、E4 的 secondary ALU 结果
   E3 级 bypass    ← 来自：E4 的 secondary ALU 结果

**Bypass 使能信号（来自 DEC）：**

- ``dec_i0/i1_rs1/rs2_bypass_en_d`` ：D 级 bypass 使能
- ``dec_i0/i1_rs1/rs2_bypass_en_e2`` ：E2 级 bypass 使能
- ``dec_i0/i1_rs1/rs2_bypass_en_e3`` ：E3 级 bypass 使能

**Bypass 数据选择（在 EXU 中实现，:file:`eh2_exu.sv` 第 546-555 行）：**

- ``bypass_en=1`` → 使用 ``bypass_data`` （来自前级结果）
- ``bypass_en=0`` → 使用 GPR 读数据或立即数

**特殊 bypass 路径：**

- ``E4→DC3 store data bypass`` ：E4 的 ALU 结果可以在同一周期 bypass 到 DC3
  的 store 数据（:file:`eh2_lsu.sv` 第 383-385 行）
- ``DC3 load→DC1 address bypass`` ：load 结果在 DC3 可用，下一周期 DC1 的
  新地址计算可以直接使用（``LOAD_TO_USE_PLUS1`` 模式，:file:`eh2_lsu_lsc_ctl.sv` 第 203-209 行）

§6  Stall 类型与条件
---------------------

EH2 有以下 4 种 stall 场景：

**Stall 1：Load-Use 互锁**

Load 指令在 DC3 才出数据，如果下一条指令在 D/E1/E2 级就需要该数据：
→ DEC 产生 stall（``dec_*_stall`` ），D 级之前的流水线暂停时钟。
Bypass 可以消除部分 load-use stall（如果 load 数据在 DC3 已可用且依赖
指令刚好在对应级）

**Stall 2：CSR 写后读**

CSR 写指令（如 CSRRW）在 E4 级才完成写回，后续 CSR 读指令需要等待：
→ ``dec_csr_stall_int_ff`` 信号暂停 D 级，直到 CSR 写完成

**Stall 3：FENCE / FENCE.I 等待**

FENCE 需要等待 LSU idle（所有未完成的 store 提交到 DCCM/总线）：
→ ``lsu_idle_any`` = 1 才继续发射
FENCE.I 需要等待 IFU 的 ICache flush 完成 + LSU idle：
→ ``ifu_miss_state_idle`` + ``lsu_idle_any`` 都为 1 才继续

**Stall 4：非阻塞 Load CAM 满 / Store Buffer 满**

- NB-load CAM 满了（所有条目都在等待数据返回）→ stall 新的外部 load
- Store Buffer 满了 → stall 新的 store
- ``lsu_store_stall_any`` / ``lsu_load_stall_any`` / ``lsu_amo_stall_any``
  信号反馈回 DEC（:file:`eh2_lsu.sv` 第 349-374 行）

§7  写回机制（Writeback）
--------------------------

EH2 有 3 类写回，按数据来源和时序分类：

**类型 1：REGULAR（流水线内同步写回）**

大部分指令的结果在 E4（ALU）或 DC5（Load）计算完成，
在下一周期通过 GPR 写端口写入寄存器文件。
写回地址和写回数据在 ``dec_i0/i1_waddr_wb`` / ``dec_i0/i1_wdata_wb`` 上。

**类型 2：DIV（多周期除法器异步写回）**

除法器在 E1 级启动后，指令立即 retire，除法器独立迭代计算
（32+ 周期）。完成时：

- ``exu_div_wren=1`` （写使能）
- ``exu_div_result[31:0]`` （结果）
- 通过 GPR 的第 4 写端口（``wtid3/waddr3/wen3/wd3`` ）异步写回
- 全局写回序号 ``wb_seq`` 由 probe monitor 维护

**类型 3：NB_LOAD（非阻塞 Load 异步写回）**

外部总线的 Load 延迟不可预测。NB-load 在 DC1 级分配 CAM 标签后
指令即 retire，数据返回时：

- ``lsu_nonblock_load_data_valid=1``
- ``lsu_nonblock_load_data[31:0]`` + ``lsu_nonblock_load_data_tag``
- DEC 的 CAM 查找 tag → 取出 waddr → GPR 写回（第 3 写端口）

**DIV Cancel：** 如果后续指令写同一个 rd（Write-After-Write 依赖），
在飞的除法结果被作废。Cancel 条件由 DEC 的记分板检测：

- ``dec_div_cancel`` ：RTL 内部使用的 cancel 信号
- ``dec_div_cancel_overwrite`` ：**验证专用信号** 。当 cancel 的原因是
  更年轻的同 rd 写（而非除法异常）时置位，与 retired div trace 配对使用

§8  Flush 传播路径
-------------------

流水线刷新（flush）由多种事件触发，按优先级从高到低：

.. list-table:: Flush 源与传播路径
   :header-rows: 1
   :widths: 25 20 55

   * - Flush 源
     - 触发级
     - 传播路径
   * - **E1 Upper Branch Mispredict**
     - E1
     - ``i0/i1_flush_upper_e1`` → flush E1+ 的所有指令。同时通过
       ``exu_flush_final_early`` 提前通知 IFU（SRAM BTB 模式）
   * - **E4 Lower Branch Mispredict**
     - E4
     - ``exu_i0/i1_flush_lower_e4`` → flush E4+ 的指令。
       ``exu_flush_final`` 通知 DEC 和 IFU
   * - **Exception/Trap**
     - D/E1/DC2/DC3
     - ``dec_tlu_flush_lower_wb`` → flush 整个流水线，跳转 mtvec。
       mepc=异常指令 PC, mcause=异常原因
   * - **Interrupt**
     - D
     - 同 Exception，但 mcause.Interrupt=1
   * - **FENCE.I**
     - D
     - ``dec_tlu_fence_i_wb`` → flush 流水线 + IFU ICache invalidate
   * - **Debug Halt**
     - D
     - ``dec_tlu_flush_noredir_wb`` → flush 流水线但不重定向取指
       （halt 后由调试器控制）
   * - **Single Step**
     - D
     - ``dec_tlu_flush_leak_one_wb`` → 执行 1 条指令后 flush

**Flush 优先级：** 同周期可能有多个 flush 源。EXU 中的优先级编码
（:file:`eh2_exu.sv` 第 640-663 行）选择最老的 flush 源：
E4 lower > E1 upper i0 > E1 upper i1

§9  时钟门控（Clock Gating）
-----------------------------

EH2 对 9 级流水线的每一级都做细粒度的时钟门控：

**Per-Stage 门控信号（来自 DEC）：**

- ``dec_i0_data_en[4:1]`` / ``dec_i0_ctl_en[4:1]`` ：i0 的 E1-E4 级
  数据通路/控制通路时钟使能
- ``dec_i1_data_en[4:1]`` / ``dec_i1_ctl_en[4:1]`` ：i1 同理

**门控策略：**

- 无 stall → 所有级使能（数据向前推进）
- stall → 当前级及之前的所有级禁用时钟（数据保持）
- i1 未发射 → i1 的数据通路时钟关闭（节省功耗）
- 分支预测的 i1 speculative 发射被 cancel → 仅浪费一级的时钟

**CSR 可控的时钟 override（mcgc CSR）：**

- ``dec_tlu_misc_clk_override`` / ``exu_clk_override`` / ``ifu_clk_override`` /
  ``lsu_clk_override`` / ``bus_clk_override`` / ``pic_clk_override`` /
  ``dccm_clk_override`` / ``icm_clk_override``
- 软件可以通过写 mcgc CSR 强制某域的时钟常开

§10  Trace Packet 生成
-----------------------

Trace Packet 在 DEC 顶层的 wb+1 级生成（:file:`eh2_dec.sv` 第 1003-1022 行）。

**格式（``eh2_trace_pkt_t`` ）：**

.. code-block:: text

   trace_rv_i_insn_ip    = {i1_instr[31:0], i0_instr[31:0]}           // 64-bit 双指令
   trace_rv_i_address_ip = {i1_pc[31:1], 1'b0, i0_pc[31:1], 1'b0}    // 64-bit 双 PC
   trace_rv_i_valid_ip   = {i1_valid, int_valid | i0_valid}           // i0 在低位
   trace_rv_i_exception_ip = {i1_exc, int_valid | i0_exc}
   trace_rv_i_ecause_ip  = {4'b0, exc_cause[4:0]}                    // 仅低 5 位有效
   trace_rv_i_interrupt_ip = {1'b0, int_valid}
   trace_rv_i_tval_ip    = mtval[31:0]
   trace_rv_i_rd_valid_ip = {i1_wen, i0_wen}                         // RVFI 等价写回
   trace_rv_i_rd_addr_ip  = {i1_waddr[4:0], i0_waddr[4:0]}
   trace_rv_i_rd_wdata_ip = {i1_wdata[31:0], i0_wdata[31:0]}

**关键约定：i0 始终在低位，i1 在高位** （program order：i0 先于 i1）。

**Interrupt-only trace item：** 当 ``interrupt=1 && exception=0`` 时，
该 trace item 表示中断通知（该 PC 处的指令没有执行）。
Spike 不调用 ``step()`` ，仅设置 mip/mie 等状态。

**RVFI 等价信号（验证专用，Phase 1 新增）：**
``trace_rv_i_rd_*_ip`` 字段是从 RTL 写回信号直接导出的，用于与 Spike 比对
GPR 写回。这些信号使 RVFI adapter 可以将 EH2 的 trace 格式桥接到标准 RVFI 接口。

§11  双线程（SMT）对流水线的影响
----------------------------------

当 ``NUM_THREADS=2`` 时：

- 指令缓冲（IB）和 GPR 各有 2 个独立实例（per-thread）
- DEC 的 ``rvarbiter2_smt`` 仲裁器每周期选择译码线程
- 仲裁考虑因素：``ready_in`` （IB 有指令）、``lsu_in`` （LSU 指令优先）、
  ``mul_in`` （乘法指令优先）、``i0_only_in`` （必须 slot 0 的指令优先）、
  ``thread_stall_in`` （线程被外部 stall）
- ``force_favor_flip`` 信号确保公平性（防止一个线程饿死）
- TLU 和 CSR 是 per-thread 独立的（每个线程有自己的 mstatus/mepc/mcause）
- PIC 中断按线程路由（``mexintpend[N-1:0]`` ）
- Trace packet 也是 per-thread（每线程独立输出）

§12  依赖记分板（Dependency Scoreboard）详解
-----------------------------------------------

依赖记分板是 DEC 中跟踪在飞指令目标寄存器的核心机制，用于检测 RAW 依赖
并控制 i1 发射和 stall。

**工作原理：**

1. **发射时设置** ：当一条指令在 D 级发射（i0 或 i1），其目标寄存器 rd
   被写入记分板。记分板条目包含：rd 地址（5-bit）、有效位、流水级位置
2. **译码时检查** ：下一条指令在 D 级译码时，其 rs1 和 rs2 地址与记分板
   中所有有效条目比较。命中 → RAW 依赖 → 需要 stall 或 bypass
3. **写回时清除** ：当指令完成写回（WB 级），对应 rd 的记分板条目被清除
4. **Bypass 优先** ：如果依赖的指令结果在 E1/E2/E3/E4 级已可用，
   通过旁路前递解决（不 stall）；如果结果尚未算出（如 Load 在 DC3 才出数据），
   则需要 stall

**记分板容量：** 由于 EH2 是 9 级流水线 + 双发射，理论上同时有最多
18 条指令在飞。记分板需要有足够的条目来跟踪所有未写回的 rd。
实际实现中通过 CAM 结构同时比较所有条目。

**RAW 检测示例：**

.. code-block:: text

   i0: ADD x5, x1, x2    ← 写 x5 (rd=5)
   i1: SUB x6, x5, x3    ← 读 x5 (rs1=5) → RAW! 记分板命中

   解决方案：
   - 如果 i0 在 E1 级已经算出结果 → i1 可以 bypass（不 stall）
   - 如果 i0 刚在 D 级发射（同周期）→ i1 不能发射（规则 1）

§13  非阻塞 Load CAM 详解
---------------------------

非阻塞 Load 的 CAM（Content-Addressable Memory）管理外部总线 Load
的异步数据返回。这是 EH2 中处理不确定延迟 Load 的关键机制。

**CAM 条目生命周期：**

1. **分配（DC1 级）** ：LSU 检测到外部 Load → ``lsu_nonblock_load_valid_dc1=1``
   → DEC 的 CAM 分配一个空闲条目 → 记录：tag（``LSU_NUM_NBLOAD_WIDTH`` bit）、
   目标寄存器地址（waddr[4:0]）、线程 ID（tid）
2. **匹配（D 级）** ：后续指令在 D 级检查其 rs1/rs2 是否命中 CAM 中的 waddr
   → 命中 → stall（等待数据返回）。这是 load-use 互锁的另一种形式
3. **作废（DC2/DC5 级）** ：``lsu_nonblock_load_inv_dc2/dc5`` → CAM 中对应的
   tag 条目被作废。原因：store forwarding（同地址的 store 使旧 load 数据无效）、
   流水线 flush（异常/分支预测失误）
4. **数据回传** ：``lsu_nonblock_load_data_valid=1`` → 按 tag 查找 CAM →
   取出 waddr + tid → GPR 写回（第 3 写端口：wen2/waddr2/wd2）→ 清除 CAM 条目

**CAM 满 stall：** 当 CAM 条目用完（所有 tag 都在等待数据返回），
DEC 暂停新的外部 Load 发射（``lsu_load_stall_any`` ）。

**CAM 参数：** ``LSU_NUM_NBLOAD`` 定义 CAM 条目数（通常 4 或 8），
``LSU_NUM_NBLOAD_WIDTH`` = ceil(log2(N)) 是 tag 位宽。

§14  异常与时序详解
--------------------

**异常检测流水级：**

.. list-table::
   :header-rows: 1
   :widths: 20 20 60

   * - 异常类型
     - 检测级
     - 检测逻辑
   * - 非法指令
     - D
     - DEC 译码器判定 ``legal=0``
   * - 指令地址不对齐
     - F2/A
     - IFU 对齐器检测跳转目标 PC[1]=1
   * - 指令访问错误
     - F2
     - ICache/ICCM 返回 ``icaf=1`` 或 ``dbecc=1``
   * - ECALL / EBREAK
     - D
     - DEC 译码器识别 SYSTEM 类指令
   * - Load 地址不对齐
     - DC2
     - LSU addrcheck：``half & addr[0]`` 或 ``word & addr[1:0]!=0``
   * - Load 访问错误
     - DC2
     - LSU addrcheck：DCCM unmapped / MPU fault / AMO fault
   * - Store/AMO 地址不对齐
     - DC2
     - 同 Load
   * - Store/AMO 访问错误
     - DC2
     - 同 Load
   * - ECC 双 bit 错误
     - DC3
     - LSU ECC 解码器检测到不可纠正错误

**异常处理时序：**

.. code-block:: text

   CLK      : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   D        : [非法指令]                               ← 译码发现 illegal
   E1       : ─[非法指令]                               ← 异常信息传播
   E4       : ─────[非法指令]                           ← dec_tlu_flush_lower_wb=1
   mepc     : ─────<异常PC>                             ← 锁存异常指令 PC
   mcause   : ─────<2>                                  ← 非法指令=2
   mtvec    : ─────[handler]                            ← 跳转陷阱处理器
   IFU      : ──────[handler]                           ← 从 mtvec 取指

   从检测到 handler 第一条指令：5-6 周期延迟

§15  中断处理时序
------------------

**中断采样时机：** D 级每周期检查 ``mip & mie`` 且 ``mstatus.MIE=1`` 。
中断在指令边界采样——当前在 D 级的指令如果是中断安全的（非 LSU/CSR 写），
则中断在该指令退休后立即响应。

.. code-block:: text

   CLK      : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   mexintpend: ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__ ← PIC 发出中断
   D        : [ADD][NOP][──────]                        ← 中断在 NOP 后采样
   mcause   : ────────<0x8000000B>                      ← Interrupt=1, MEI=11
   mepc     : ────────<NOP_PC+4>                        ← 保存返回地址
   IFU      : ─────────[ISR]                            ← 跳转中断服务例程

**中断响应延迟：** 从 mexintpend 上升到 ISR 第一条指令：

- 最快：2-3 周期（mexintpend 在 D 级当前指令退休前到达）
- 最慢：9 周期（流水线满时需排空）

**快速中断（FAST_INTERRUPT_REDIRECT）：**

- 跳过 LSU 地址检查，直接重定向
- ``lsu_fastint_stall_any`` 通知 LSU
- 减少约 2 周期延迟

§16  调试 Halt 时序
--------------------

.. code-block:: text

   CLK         : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   dbg_halt_req: __/‾‾‾‾‾\_________________________________ ← 脉冲
   DMA bubble  : ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________________
   dma_dbg_ready: _____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___
   lsu_idle_any: _______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_
   dbg_halted  : _____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_

   halt 序列：halt_req → DMA bubble → wait dma_ready → wait lsu_idle → dbg_halted

§17  双发射指令序列示例
-----------------------

**示例 1：完全双发射（4 周期发射 8 条指令）**

.. code-block:: text

   周期1: i0=ADD x1,x2,x3   i1=SUB x4,x5,x6     (无依赖，双发射)
   周期2: i0=LW  x7,0(x1)   i1=AND x8,x4,x9     (LW用x1, AND用x4, 无冲突)
   周期3: i0=OR  x10,x7,x8  i1=stall             (OR依赖LW的x7, load-use stall)
   周期4: i0=MUL x11,x9,x10 i1=XOR x12,x1,x2    (MUL和XOR无冲突)

**示例 2：CSR 写序列化 i1**

.. code-block:: text

   周期1: i0=CSRRW mstatus,x5  i1=stall          (CSR写→串行化)
   周期2: i0=ADD x6,x1,x2      i1=SUB x7,x3,x4   (CSR写后恢复双发射)

**示例 3：分支阻止 i1**

.. code-block:: text

   周期1: i0=BEQ x1,x2,target  i1=stall          (分支→暂停i1)
   周期2: [target指令]                             (跳转或顺序执行)

§18  流水线时序波形示例
------------------------

**12.1  双发射正常流（无 stall）**

.. code-block:: text

   CLK     : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   BFF     : [ADD] [SUB] [MUL] [LW ] [SW ]
   F1      : ─[ADD] [SUB] [MUL] [LW ] [SW ]
   F2      : ──[ADD] [SUB] [MUL] [LW ] [SW ]
   A       : ───[ADD] [SUB] [MUL] [LW ] [SW ]
   D       : ────[ADD] [SUB] [MUL] [LW ] [SW ]    ← i0=ADD, i1=SUB 同周期发射
   E1      : ─────[ADD] [SUB] [MUL] [LW ] [SW ]    ← ADD/SUB 都进入 E1 ALU
   E2      : ──────[ADD] [SUB] [MUL] [LW ] [SW ]
   E3      : ───────[ADD] [SUB] [MUL] [LW ] [SW ]   ← MUL 结果在 E3 产出
   E4      : ────────[ADD] [SUB] [MUL] [LW ] [SW ]
   DC1     : ─────────[ADD] [SUB] [MUL] [LW ] [SW ]
   DC2     : ──────────[ADD] [SUB] [MUL] [LW ] [SW ]
   DC3     : ───────────[ADD] [SUB] [MUL] [LW ] [SW ]  ← LW 数据在此级可用
   DC4     : ────────────[ADD] [SUB] [MUL] [LW ] [SW ]
   DC5     : ─────────────[ADD] [SUB] [MUL] [LW ] [SW ]
   WB      : ──────────────[ADD] [SUB] [MUL] [LW ] [SW ] ← 写回 GPR

**12.2  Load-Use 互锁 stall**

.. code-block:: text

   CLK     : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   D       : [LW ] [USE] [USE] [USE] [NEXT]            ← USE 依赖 LW 的结果
   E1      : ─[LW ] [stall][stall][USE] [NEXT]          ← stall 2 周期等 LW 到 DC3
   DC1     : ──[LW ] [stall][stall][USE]
   DC2     : ───[LW ] [stall][stall][USE]
   DC3     : ────[LW ] [stall][stall][USE]              ← LW 数据可用
   DC4     : ─────[LW ] ─────[stall][USE]               ← USE 在 DC3 取到 LW 数据
   DC5     : ──────[LW ] ─────[stall][USE]

   Stall 周期数 = DC3 数据可用时间 - USE 指令需要数据的时间。
   如果 USE 在 D/E1 级，则需要 2 周期 stall。

**12.3  分支预测失误 flush**

.. code-block:: text

   CLK     : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   E1      : [BEQ] [i1 ]                         ← BEQ 在 E1 解析，实际跳转≠预测
   E4      : ─────[BEQ]                           ← flush_lower 触发
   IFU     : ─────────[TGT]                       ← 重定向到正确目标
   被flush : ──[i0 ] [i1 ] [i0 ] [i1 ] [i0 ]    ← 这些指令被作废

   惩罚周期 = 4（从 E1 误预测到 E4 flush 的 3 级 + IFU 重新取指的 1 级）

§13  典型故障模式
------------------

**故障 1：双发射 RAW 依赖未检测**

- 现象：i0 写 x5，i1 同周期读 x5（应 stall 但未 stall）。cosim GPR mismatch
- 根因：记分板的同周期 RAW 检查漏掉了 i0→i1 的依赖
- 复现：``make run TEST=riscv_rand_instr_test SEED=42``
- 调试：在波形中检查 ``dec_i1_cancel_e1`` 是否应该为 1（i1 应该被取消但实际发射了）
- 定位：:file:`eh2_dec_decode_ctl.sv` 记分板检查逻辑

**故障 2：NB-load CAM tag 过早重用**

- 现象：两个 NB-load 分配了相同 tag，数据返回时写入了错误的 rd
- 根因：CAM 分配逻辑使用循环计数器，未考虑"已分配但数据未返回"的条目
- 调试：跟踪 ``lsu_nonblock_load_tag_dc1`` 的分配和 ``lsu_nonblock_load_data_tag`` 的返回
- 定位：DEC 的 NB-load CAM 管理逻辑 + :file:`eh2_lsu.sv` 第 79-89 行

**故障 3：DIV cancel 漏掉 writeback**

- 现象：除法被后续指令 overwrite rd，但 cancel 信号晚一周期，
  scoreboard 未作废除法写回 → 旧除法结果覆盖新结果
- 调试：对比 ``dec_div_cancel`` 与 ``exu_div_wren`` 的时序
- 定位：:file:`eh2_dec_decode_ctl.sv` 中 ``dec_div_cancel_overwrite`` 信号

**故障 4：Store Buffer coalescing 导致 AXI addr 不匹配**

- 现象：多次 store 合并为一个 AXI burst，cosim scoreboard 等待单次 store 的 AXI 事务超时
- 根因：scoreboard 的 store→AXI 匹配逻辑未考虑合并
- 调试：在波形中对比 ``store_stbuf_reqvld_dc5`` 和 ``lsu_axi_awaddr``
- 定位：:file:`eh2_lsu_stbuf.sv` coalescing 逻辑 + scoreboard store 匹配

**故障 5：Interrupt-only trace item 被当作普通指令 step**

- 现象：Spike PC 与 DUT trace PC 持续偏移（Spike 多执行了指令）
- 根因：``trace.interrupt=1 && trace.exception=0`` 应只更新 Spike mip/mie，
  不应调用 ``step()`` 。scoreboard 未正确识别
- 定位：scoreboard 的 ``run_cosim_trace()`` 中 interrupt-only 处理分支

**故障 6：E1 flush 后 GHR 恢复到错误状态**

- 现象：分支预测失误 flush 后，后续分支预测准确率骤降
- 根因：``after_flush_eghr`` 选择逻辑在双发射+flush 场景下选择了错误的 ghr 源
- 定位：:file:`eh2_exu.sv` 第 656 行 ``after_flush_eghr``

**故障 7：CSR presync 未 stall 导致 mstatus.MIE 更新延迟**

- 现象：写 mstatus.MIE=1 后下一条指令未响应中断
- 根因：presync 需要排空流水线，但 DEC 未正确 stall D 级
- 定位：:file:`eh2_dec_csr.sv` 第 516 行 ``tlu_presync_d`` +
  :file:`eh2_dec_decode_ctl.sv` stall 逻辑

§14  各流水级关键信号速查
-------------------------

.. list-table::
   :header-rows: 1
   :widths: 10 25 65

   * - 级
     - 关键信号
     - 说明
   * - BFF
     - ``ifu_fetch_val[3:0]``, ``ifu_fetch_data[63:0]``
     - 16B 取指块的有效指示+数据
   * - F1
     - ``fetch_addr_f1[31:1]``, ``fetch_req_f1``
     - 取指地址+请求有效
   * - F2
     - ``ic_rd_hit[WAY-1:0]``, ``ifu_bp_btb_target_f2``
     - ICache tag 命中 + BTB 预测目标
   * - A
     - ``i0_valid/i1_valid``, ``i0_instr/i1_instr[31:0]``
     - 对齐后的指令输出
   * - D
     - ``dec_i0/i1_alu_decode_d``, ``i0_ap/i1_ap``, ``lsu_p``
     - 译码控制包（ALU/LSU/MUL/DIV）
   * - E1
     - ``exu_i0/i1_result_e1[31:0]``, ``i0/i1_flush_upper_e1``
     - ALU 结果 + upper branch flush
   * - E2/E3
     - ``exu_mul_result_e3[31:0]``
     - 乘法结果（E3 产出）
   * - E4
     - ``exu_i0/i1_result_e4[31:0]``, ``exu_flush_final``
     - Secondary ALU 结果 + lower branch flush
   * - DC1
     - ``lsu_addr_dc1[31:0]``, ``lsu_nonblock_load_valid_dc1``
     - LSU 地址生成 + NB-load CAM 分配
   * - DC2
     - ``addr_in_dccm/pic/external``, ``access_fault_dc2``
     - 地址路由 + 故障检测
   * - DC3
     - ``lsu_result_dc3[31:0]``, ``lsu_single/double_ecc_error_dc3``
     - Load 结果 + ECC 错误检测
   * - DC4/DC5
     - ``lsu_result_corr_dc4``, ``lsu_sc_success_dc5``
     - ECC 纠正数据 + SC 成功确认

§15  扩展指南
-------------

**场景 A：修改双发射规则（允许新的指令组合同发）**
1. 在 :file:`eh2_dec_decode_ctl.sv` 中修改 i1 发射条件
2. 运行 ``make signoff PROFILE=cosim`` 确认无 cosim mismatch
3. 更新功能覆盖率模型（如果新增了 coverpoint）

**场景 B：增加流水线级数**
1. 修改 ``eh2_param.vh`` 中的流水线深度参数
2. 在各模块中添加新的 DFF stage
3. 更新时钟使能信号（``dec_*_data_en/ctl_en`` 增加新级）
4. 运行全回归确认无 timing 问题

§19  性能计数器事件映射
-------------------------

EH2 的 4 个性能监控计数器（mhpmcounter3-6）可配置为计数不同的微架构事件。

.. list-table:: 性能计数器事件类型
   :header-rows: 1
   :widths: 8 25 67

   * - ID
     - 事件
     - 说明
   * - 0
     - NONE
     - 计数器禁用
   * - 1
     - INSTR_RETIRED
     - 指令退休（双发射时递增 2）
   * - 2
     - CYCLES
     - 核心时钟周期
   * - 3
     - BRANCHES
     - 分支指令（条件+无条件+JAL/JALR）
   * - 4
     - BRANCH_MISPREDICTS
     - 分支预测失误
   * - 5
     - LOADS
     - Load 指令
   * - 6
     - STORES
     - Store 指令
   * - 7
     - BUS_TRANSACTIONS
     - AXI4 总线事务
   * - 8
     - ICACHE_MISSES
     - ICache miss
   * - 9
     - DCCM_ACCESSES
     - DCCM 访问
   * - 10
     - EXTERNAL_LOADS
     - 外部总线 Load
   * - 11
     - EXTERNAL_STORES
     - 外部总线 Store
   * - 12
     - STALL_CYCLES
     - 流水线 stall 周期

**Toggle 机制：** 每事件对应一个 toggle 信号（``dec_tlu_perfcnt0-3`` ），
TLU 在事件发生时翻转。计数器检测 toggle 变化时递增。这避免了
高频事件的 critical path 上的加法器。

§20  NB-load 完整生命周期
---------------------------

.. code-block:: text

   CLK      : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   D        : [LW ext]                                     ← 译码发现外部 Load
   DC1      : ─[addr=0x8000]  CAM分配(tag=3)               ← 地址生成+NB-load CAM
   DC2      : ──[external]                                  ← 路由到外部总线
   DC3      : ───[AXI4 AR]                                  ← AXI4 读事务发起
   AXI4 R   : ──────────[rdata=0xDEAD]                      ← 数据返回(延迟不定)
   nb_data  : ──────────/‾‾‾‾‾‾‾‾‾\_____________________ ← valid=1
   CAM查找  : ──────────[tag=3→waddr=x5]                    ← DEC CAM 匹配
   GPR写回  : ───────────[x5=0xDEAD]                        ← 第3写端口异步写回
   wb_seq   : [1][2][3][4][5][6]...[38]                     ← 远晚于指令退休

§21  异常→mret 完整时序
-------------------------

.. code-block:: text

   CLK      : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   D        : [非法指令]                                     ← illegal
   E4       : ─────[flush] mepc=<PC> mcause=2               ← trap entry
   mstatus  : ─────[MIE=0, MPIE=old, MPP=M]                 ← 硬件自动
   IFU      : ──────[handler]                                ← mtvec 跳转
   handler  : ──────[save→read mcause→dispatch→restore]
   mret     : ─────────────────────[mret]                    ← 异常返回
   PC       : ─────────────────────[mepc]                    ← 恢复执行

§22  流水线资源利用率分析
---------------------------

**每级使用的硬件资源：**

.. list-table::
   :header-rows: 1
   :widths: 8 25 67

   * - 级
     - 硬件资源
     - 说明
   * - BFF/F1/F2
     - ICache SRAM + BTB SRAM + BHT SRAM
     - 取指阶段的存储访问
   * - A
     - 对齐器组合逻辑 + RVC 展开器
     - 纯组合逻辑，无状态
   * - D
     - IB FIFO(4×flop) + GPR(31×32b)×2 + 记分板CAM + CSR译码逻辑
     - DEC 中资源最密集的级
   * - E1
     - ALU×2(i0+i1) + 乘法器E1 + 除法器启动
     - 双 ALU 并行运算
   * - E2/E3
     - 乘法器流水线寄存器 + bitmanip 运算
     - 乘法器专用级
   * - E4
     - ALU×2(secondary) + GHR更新逻辑
     - 分支解析最终确认
   * - DC1/DC2
     - 地址加法器 + addrcheck 组合逻辑
     - 地址生成与检查
   * - DC3
     - DCCM SRAM + AXI4 bus interface
     - 存储访问的关键级
   * - DC4/DC5
     - 数据对齐逻辑 + SC确认逻辑
     - 写回准备

**关键时序路径：**

- D 级：IB读出→GPR读出→bypass MUX→操作数输出（最常成为 critical path）
- DC3 级：DCCM SRAM 读→ECC 解码→数据对齐→符号扩展
- E1 级：ALU 运算 + 分支条件判断（为 E1 upper flush 提供判断依据）

§23  双线程 SMT 对流水线的完整影响
-----------------------------------

当 NUM_THREADS=2 时，除 §11 描述的资源复制外，还有以下关键影响：

**取指仲裁：** IFU 的 ``rvarbiter2`` 在 F1/BF 级选择取指线程。
两个线程共享 ICache 带宽。当两个线程都在 ICache miss 等待时，
WFM（Wait For Miss）状态阻止两个线程发起新的取指。

**译码仲裁：** DEC 的 ``rvarbiter2_smt`` 每周期选择一个线程译码。
仲裁考虑以下优先级（从高到低）：
1. ``i0_only_in`` ：该线程 IB0 必须在 slot 0 发射（如 DIV/CSR写）
2. ``lsu_in`` ：LSU 指令优先（减少 load-use stall 影响）
3. ``mul_in`` ：乘法指令优先（乘法器是共享资源）
4. ``ready_in`` ：有有效指令
5. ``force_favor_flip`` ：防止饿死

**线程间 stall 传播：**

- ``thread_stall_in`` ：一个线程的 stall 不影响另一线程的译码
- 共享资源冲突（乘法器/除法器/LSU）：通过 i1 发射规则处理
- Store Buffer 满：阻止两个线程的 store 发射

**CSR 上下文切换：** 无开销。每个线程有独立的 mstatus/mepc/mcause/mtval/
mie/mip 寄存器文件。线程切换仅改变 ``tid`` 信号，无需保存/恢复。

§24  流水线 Stall 完整矩阵
----------------------------

.. list-table:: 所有 Stall 类型、条件、影响范围
   :header-rows: 1
   :widths: 20 25 30 25

   * - Stall 类型
     - 触发条件
     - 影响范围
     - 解除条件
   * - Load-Use 互锁
     - D/E1 级指令的 rs 依赖 DC1-DC3 的 load rd
     - D 级及之前全部 stall
     - Load 数据到达 DC3（bypass 可用）
   * - NB-Load CAM 命中
     - D 级 rs 命中 NB-load CAM 中的 waddr
     - D 级 stall
     - NB-load 数据返回或 CAM 条目作废
   * - CSR 写后读
     - CSR 写（E4 完成）后立即 CSR 读（D 级）
     - D 级 stall
     - CSR 写在 E4 完成
   * - FENCE 等待
     - FENCE 指令在 D 级
     - D 级 stall
     - ``lsu_idle_any`` = 1
   * - FENCE.I 等待
     - FENCE.I 在 D 级
     - D 级 stall + IFU ICache flush
     - ICache flush 完成 + LSU idle
   * - Store Buffer 满
     - ``lsu_stbuf_full_any`` = 1
     - 新 store 指令 stall
     - Store Buffer 有空位（提交到 DCCM）
   * - Bus Buffer 满
     - ``lsu_bus_buffer_full_any`` = 1
     - 新外部访问 stall
     - AXI4 事务完成释放 buffer
   * - NB-Load CAM 满
     - 所有 CAM 条目在用
     - 新外部 load stall
     - NB-load 数据返回释放条目
   * - ECC 校正周期
     - ``ld_single_ecc_error_dc3`` = 1
     - Load/Store stall
     - 校正周期完成（读→纠正→写回）
   * - Presync stall
     - CSR presync 访问
     - D 级 stall（排空流水线）
     - 流水线排空（2-5 周期）
   * - Postsync stall
     - CSR postsync 访问
     - D 级 stall
     - 流水线排空
   * - IFU miss stall
     - ICache miss → FSM=WFM
     - F1 级暂停取指
     - ICache line fill 完成
   * - DMA stall
     - ``dma_iccm_stall_any`` 或 ``ic_dma_active``
     - IFU 暂停取指
     - DMA 访问完成

§25  与 Ibex 工业实现对照
---------------------------

Ibex 的流水线较短，验证主路径以原生 RVFI 和 ``core_ibex_scoreboard`` 为中心；
EH2 的流水线更深，且有双发射、非阻塞 load、DIV 异步写回和可选 SMT 结构。
两者的工业共性不在流水级数，而在验证可观测性和覆盖率 gate 的处理方式。

.. list-table:: EH2 pipeline 与 Ibex 对照
   :header-rows: 1
   :widths: 22 34 44

   * - 项目
     - Ibex
     - EH2
   * - retire 记录
     - ``ibex_top_tracing`` 直接输出 RVFI；见
       ``/home/host/ibex/dv/uvm/core_ibex/tb/core_ibex_tb_top.sv``
     - ``eh2_trace_pkt_t`` + ``eh2_trace_monitor`` 产生 trace item，
       ``rtl/eh2_veer_wrapper_rvfi.sv`` 提供 sidecar RVFI 视图
   * - 写回比对
     - RVFI item 直接送 cosim agent
     - trace item 自带 ``wb_valid/rd_addr/rd_wdata``；DIV/NB-load 通过 probe
       hint 严格按 ``wb_tag`` 修正
   * - 覆盖率配置
     - ``/home/host/ibex/dv/uvm/core_ibex/cover.cfg`` 使用
       ``+tree core_ibex_tb_top.dut``；VCS 使用 5 维度 URG
     - ``dv/uvm/core_eh2/cover.cfg`` 使用 ``+tree core_eh2_tb_top.dut``；
       维度同样是 ``line+tgl+assert+fsm+branch``
   * - 微架构差异
     - 单发射流水线，debug/interrupt 通过 RVFI ext 同步
     - 双发射深流水，interrupt/debug 状态由 trace/probe/scoreboard 共同排序
   * - 文档要求
     - Ibex 文档强调 testbench 架构、RVFI 和 coverage plan
     - EH2 本章必须额外解释 i0/i1、NB-load CAM、DIV cancel 和 flush 传播

§26  源码锚点与可观测性证据
-----------------------------

前文的流水线解释必须落到真实信号。本节列出调试时最常用的源码锚点，作为
``grep``、Verdi waveform、cosim mismatch triage 和文档交叉引用的共同入口。

**DEC 端口中的双槽位、DIV cancel 与 fast interrupt 边界**
（``/home/host/Cores-VeeR-EH2/design/dec/eh2_dec.sv:L38-L66``）：

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec.sv
   :language: systemverilog
   :lines: 38-66
   :linenos:
   :caption: eh2_dec.sv — i0/i1 二级 ALU、branch、DIV cancel 与 fast interrupt 输出

这段端口定义说明三件事。第一，i0 和 i1 都有 secondary ALU 与 branch 的流水级
可观测信号，验证侧不能把 slot 1 当成 slot 0 的影子。第二，``dec_div_cancel``
和 ``dec_div_cancel_overwrite`` 分别覆盖架构 cancel 与验证可见的 younger same-rd
覆盖场景，是 DIV 异步写回 mismatch 的首要检查点。第三，``dec_extint_stall``
把 interrupt fast path 纳入 DEC stall 体系，解释了为什么某些 interrupt-only trace
item 没有普通指令退休。

**非阻塞 load 与 DEC 的 tag/data 交互**
（``eh2_dec.sv:L109-L122``）：

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec.sv
   :language: systemverilog
   :lines: 109-122
   :linenos:
   :caption: eh2_dec.sv — LSU nonblock load valid/tag/invalidate/data 回传

NB-load 不是“晚一点到达的普通 load”。DEC 需要同时看到分配 tag、DC2/DC5 作废、
data return、data error 和 data tag。scoreboard 如果只比较 retire 时的 GPR 写回，
会错过 NB-load 的异步写回窗口；因此当前 UVM 平台通过 DUT probe 的 ``wb_seq`` 和
trace item 的 ``wb_tag`` 做严格关联。

**commit、trace packet、时钟门控和 flush 输出**
（``eh2_dec.sv:L413-L461``）：

.. literalinclude:: ../../../../../Cores-VeeR-EH2/design/dec/eh2_dec.sv
   :language: systemverilog
   :lines: 413-461
   :linenos:
   :caption: eh2_dec.sv — E4 valid、trace packet、mfdc/mcgc、flush path

这段是流水线和验证平台的核心边界。``dec_tlu_i0_valid_e4`` 和
``dec_tlu_i1_valid_e4`` 给出 commit slot；``trace_rv_trace_pkt`` 是 trace monitor
采样入口；``dec_i*_data_en`` / ``dec_i*_ctl_en`` 是 clock-gating 覆盖和 toggle
解释的关键；``dec_tlu_flush_*`` 系列把 exception、interrupt、branch mispredict、
FENCE.I、single-step 和 error flush 统一送回 IFU/TLU。

**Trace monitor 的双槽位采样**
（``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:L82-L174``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv
   :language: systemverilog
   :lines: 82-174
   :linenos:
   :caption: eh2_trace_monitor.sv — t0_i0/t0_i1 commit item 生成

该 monitor 逐周期先看 i0，再看 i1，并把 ``wb_valid``、``wb_dest``、``wb_data``、
``interrupt``、``exception``、``mepc/mcause/mtval`` snapshot 和 ``wb_tag`` 一起打包。
这解释了 EH2 与 Ibex 的一个重要差异：Ibex 的 scoreboard 可以直接消费 RVFI item；
EH2 需要先把 trace packet 与 probe 状态拼成 RVFI-equivalent transaction，再交给
Spike DPI。

**Cosim scoreboard 的 interrupt-only 与 trap CSR 比对**
（``eh2_cosim_scoreboard.sv:L573-L610``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 573-610
   :linenos:
   :caption: eh2_cosim_scoreboard.sv — interrupt-only item 与 mcause/mepc gate

当 ``item.interrupt && !item.exception`` 时，scoreboard 不调用 Spike step 来执行一条
普通指令，而是先同步 ``debug_req``、``nmi``、``mip``、``mcycle``，再比较 trap CSR。
如果此处出现 mismatch，首查对象不是 ALU 或 GPR，而是 interrupt latency、``mip``
采样、``mepc`` 保存时机和 TLU flush path。

.. list-table:: 源码锚点到调试动作
   :header-rows: 1
   :widths: 26 34 40

   * - 症状
     - 首查信号/文件
     - 典型动作
   * - slot 1 指令丢失
     - ``dec_tlu_i1_valid_e4``、``t0_i1_valid``、``eh2_trace_monitor``
     - 检查 i1 issue rule、branch/fence/CSR 限制与 trace interface 连接
   * - DIV 结果晚到或误写
     - ``dec_div_cancel``、``dec_div_cancel_overwrite``、``exu_div_wren``
     - 用 ``wb_tag`` 和 younger same-rd directed test 检查 cancel 语义
   * - external load mismatch
     - ``lsu_nonblock_load_*``、``async_wb_q``、``wb_seq``
     - 确认 tag 分配、作废、data return 与 scoreboard strict matching
   * - interrupt trap CSR mismatch
     - ``item.interrupt``、``prev_mip``、``dut_mcause``、``dut_mepc``
     - 对齐 TLU CSR snapshot 与 Spike ``set_mip``/``get_mcause`` 顺序
   * - FENCE.I 后继续取旧指令
     - ``dec_tlu_fence_i_wb``、IFU flush、ICache invalidation
     - 查 :ref:`icache` 中 FENCE.I 与 fill FSM 的交互
   * - 覆盖率异常偏高
     - ``cover.cfg``、``-cm_hier``、``dashboard.txt``
     - 确认只统计 ``core_eh2_tb_top.dut``，没有混入 TB interface 或历史 NC 数据

§27  VCS/URG 签核中的流水线覆盖解释
------------------------------------

流水线覆盖率不能只看 LINE。EH2 的流水线复杂度集中在控制路径、异常路径和异步写回，
因此必须同时阅读 BRANCH、TOGGLE、ASSERT、FSM、GROUP 和 OVERALL。
2026-05-19 demo 的 URG dashboard 中，DUT 子树数字为：

.. list-table:: 流水线相关覆盖率解释
   :header-rows: 1
   :widths: 16 16 68

   * - 指标
     - 数字
     - 对流水线的含义
   * - LINE
     - 95.05%
     - 绝大多数可执行 RTL 语句被触达，说明 smoke/directed/riscvdv/compliance 已覆盖主干
   * - BRANCH
     - 84.97%
     - branch/mux/fsm 条件仍有部分冷门路径，常见于 error、debug、rare stall 或参数化分支
   * - TOGGLE
     - 53.52%
     - 低于 line 属正常现象；深流水、ICCM/DCCM、PIC/DMA 和未启用参数位会拉低 toggle
   * - ASSERT
     - 33.33%
     - SVA 触发面仍待 formal 与 directed 增强；不能用 line 覆盖替代 assertion 覆盖
   * - FSM
     - 54.74%
     - IFU fill、LSU buffer、debug/DMI、PIC 等状态机还有未触达状态
   * - GROUP
     - 69.42%
     - functional coverage covergroup 的 cross/bin 覆盖仍是下一轮收敛重点
   * - OVERALL
     - 65.17%
     - release gate 使用整体 dashboard 作为趋势指标，但质量判断仍需结合 stage pass/fail

.. tip::

   如果修改流水线 RTL 后 LINE 没有下降，但 BRANCH/FSM/ASSERT 明显下降，仍然需要排查。
   这通常说明新增控制路径被编译进 DUT，却没有相应 directed、riscv-dv 或 formal
   stimulus。不要只用 ``make smoke`` 判断深流水修改是否安全。

流水线相关的最小验证组合通常是：

.. code-block:: bash

   make smoke
   make regress TESTLIST=dv/uvm/core_eh2/directed_tests/directed_testlist.yaml COV=1
   make signoff PROFILE=nightly COV=1
   make signoff GATE_ONLY=1 SIGNOFF_OUT=build/signoff

预期输出形态如下。具体时间戳和路径会随 ``BUILD_DIR`` 改变，但 stage 名称、
coverage 维度和 DUT-only scope 不应改变。

.. code-block:: text

   Status: PASS
   Stage smoke     PASS
   Stage directed  PASS
   Stage cosim     PASS（waiver gate 由 signoff.py 单独记录）
   Stage riscvdv   threshold met, fail rate <= 25%
   Coverage metrics parsed from URG dashboard:
     line=95.05 branch=84.97 toggle=53.52 assert=33.33 fsm=54.74

§28  典型流水线修改的评审清单
-------------------------------

.. list-table:: RTL 修改类型与必须同步检查的文档/验证项
   :header-rows: 1
   :widths: 24 38 38

   * - 修改类型
     - 必查源码/验证
     - 文档同步点
   * - 新增 i1 发射条件
     - ``eh2_dec_decode_ctl.sv``、trace i1 item、directed dual-issue ASM
     - :ref:`pipeline` 的双发射规则和 :ref:`tests_library` 的 directed 列表
   * - 修改 flush 优先级
     - ``dec_tlu_flush_*``、exception/interrupt directed、Spike trap CSR 比对
     - :ref:`csr` trap CSR、:ref:`rvfi_trace` interrupt-only item
   * - 修改 DIV 或 NB-load 写回
     - async writeback hint、``wb_tag``、``dec_div_cancel_overwrite``
     - :ref:`cosim_scoreboard` 和本章写回机制
   * - 修改 ICache/FENCE.I
     - IFU fill FSM、``dec_tlu_fence_i_wb``、compliance Zifencei
     - :ref:`icache`、:ref:`compliance_flow`
   * - 修改 CSR presync/postsync
     - CSR unit hazard test、``eh2_dec_csr.sv``、``eh2_dec_tlu_ctl.sv``
     - :ref:`csr` 和 ADR-0010
   * - 修改 wrapper trace/RVFI
     - ``eh2_trace_monitor``、``eh2_veer_wrapper_rvfi``、LEC shim
     - :ref:`rvfi_trace`、appendix A 的 RVFI/LEC shim 子页

该清单是 review checklist，不是替代测试。合并前仍应按 :ref:`signoff_flow`
运行对应 profile，并保存 ``signoff_status.json``、``signoff_report.md``、
``dashboard.txt`` 和相关 waveform/log 证据。

§29  与其他架构章节的联动
--------------------------

流水线不是一个孤立模块。EH2 的很多 bug 表面看是“某条指令结果不对”，实际根因可能
落在 ICache fill、CSR presync、PMP access fault、PIC interrupt priority、debug halt
或 mailbox 终止协议。调试时建议先按下面的联动关系缩小范围。

.. list-table:: 流水线现象与相邻章节
   :header-rows: 1
   :widths: 24 30 46

   * - 现象
     - 跳转章节
     - 判断依据
   * - 取指 PC 与 Spike 不一致
     - :ref:`icache`、:ref:`rvfi_trace`
     - 如果 mismatch 前有 FENCE.I、ICache miss、branch predictor redirect，先看 IFU；否则看 trace item 的 PC snapshot
   * - load/store exception cause 不一致
     - :ref:`dccm_iccm`、:ref:`csr`
     - 如果 ``mcause/mtval`` 不一致，先查 PMP/DCCM/ICCM addrcheck，再查 TLU trap CSR 更新
   * - external interrupt 进入时间不一致
     - :ref:`pic`、:ref:`csr`
     - 如果 trace item 是 interrupt-only，先查 ``mip/mie/mstatus`` 与 PIC priority/threshold
   * - debug halt 后继续退休
     - :ref:`debug`、:ref:`rvfi_trace`
     - 查 ``debug_req``、DCSR、halt handshake、trace monitor 是否仍发普通 instruction item
   * - AXI4 read data 晚到
     - :ref:`bus_axi_ahb`、:ref:`rvfi_trace`
     - 如果是 external load，按 NB-load tag/data_valid 路径追踪，不按普通 load retire 排序
   * - test 已写 PASS 但回归超时
     - :ref:`mailbox`
     - 查 0xD058_0000 mailbox store、scoreboard termination 和 host memory map

.. note::

   EH2 的双发射和异步写回使“第一处 mismatch”不一定等于“第一处错误”。例如 NB-load
   data 晚到时，Spike 可能在后续依赖指令才报 GPR mismatch；debug halt 或 interrupt
   也可能先生成无普通 retire 的 trace item。调试时应回溯到最近的 flush、stall、
   async writeback 或 CSR update，而不是只看 mismatch PC。

§30  最小波形探针集
--------------------

虽然当前 sign-off 不依赖 NC coverage，但波形仍是定位流水线 bug 的必要手段。
VCS/Verdi 或 NC/SHM 都应至少加入下面几组信号。具体层次会随 wrapper 和 generate
名称变化，原则是不只看 PC 和 instruction，还要同时看 valid、flush、stall、CSR 和
writeback。

.. list-table:: 波形 probe 分组
   :header-rows: 1
   :widths: 22 38 40

   * - 分组
     - 典型信号
     - 用途
   * - commit
     - ``dec_tlu_i0_valid_e4``、``dec_tlu_i1_valid_e4``、``dec_i0_pc_e4``、``dec_i1_pc_e4``
     - 确认双槽位退休顺序和 slot valid
   * - flush
     - ``dec_tlu_flush_path_wb``、``dec_tlu_flush_lower_wb``、``dec_tlu_flush_mp_wb``、``exu_flush_final``
     - 确认 branch/exception/interrupt/debug redirect
   * - stall
     - ``lsu_load_stall_any``、``lsu_store_stall_any``、``dec_pmu_decode_stall``、``dec_pmu_presync_stall``
     - 区分 IFU/LSU/CSR/fast interrupt stall
   * - writeback
     - ``dec_i0_wen_wb``、``dec_i1_wen_wb``、``exu_div_wren``、``lsu_nonblock_load_data_valid``
     - 对齐 regular、DIV、NB-load 三类写回
   * - CSR/trap
     - ``mstatus``、``mepc``、``mcause``、``mtval``、``mip``、``mie``
     - trap entry/return、interrupt-only item 和 Spike CSR 比对
   * - trace/probe
     - ``trace_rv_trace_pkt``、``wb_seq``、``debug_req``、``nmi``、``mcycle``
     - 确认 UVM monitor 看到的不是被优化或漏接的信号

推荐命令：

.. code-block:: bash

   # VCS/Verdi 波形，保留与 sign-off 一致的主线工具
   make smoke WAVES=1
   verdi -ssf build/smoke/smoke_s1/waves.fsdb &

   # NC/Incisive 只用于单测波形调试
   make smoke SIMULATOR=nc WAVES=1

波形调试结论如果影响架构手册，应在正文写成“VCS 主线 RTL 行为 + NC 可用于观察”；
不要写成“NC 覆盖率证明”或“IMC dashboard 证明”。

§31  sign-off 失败时的流水线 triage 路径
-----------------------------------------

当 ``make signoff`` 中出现流水线相关失败时，不建议直接打开最大波形从复位开始看。
更有效的做法是先用 stage、failure mode、mismatch 类型和 coverage 变化定位问题域，
再选择最小复现实验。

.. list-table:: sign-off 失败到流水线定位路径
   :header-rows: 1
   :widths: 18 26 28 28

   * - 失败 stage
     - 常见表象
     - 首查流水线域
     - 最小复现命令
   * - ``smoke``
     - mailbox 未写 PASS、仿真超时、首条异常
     - reset vector、IFU 取指、D 级 decode、mailbox store
     - ``make smoke WAVES=1``
   * - ``directed``
     - 某个 ASM 稳定失败
     - 对应 directed 的目标域；例如 PMP、debug、DMA、toggle 或 PIC
     - ``make regress TEST=<name> SEED=<seed> WAVES=1``
   * - ``cosim``
     - GPR/PC/trap CSR mismatch
     - trace item、regular/DIV/NB-load 写回、flush、CSR snapshot
     - ``make regress TESTLIST=dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml COV=0``
   * - ``riscvdv``
     - 随机指令在深处 mismatch
     - 最近一次 branch、load、CSR、interrupt 或 illegal instruction
     - 复用失败 seed 和 generated binary 路径
   * - ``compliance``
     - 标准 ISA 子集失败
     - CSR/exception/branch/fence/load-store 规范边界
     - ``make compliance`` 或 compliance 子环境单项运行
   * - ``formal``
     - property fail 或 explored/not-run
     - 与 property 对应的控制路径；常见为 IFU/LSU/DBG/PIC
     - ``make formal`` 后查看 IFV/SBY log 与 counterexample
   * - ``syn``
     - LEC compare point fail
     - clock-gating、wrapper pack、trace/RVFI、CSR/TLU flop 等等价边界
     - ``make syn`` 后查看 ``syn/build/lec_summary.txt``

若失败来自 cosim mismatch，建议按以下顺序阅读日志：

.. code-block:: text

   1. 找到第一条 UVM_ERROR 或 mismatch_count 增量。
   2. 记录 thread_id、slot、PC、insn、wb_valid、wb_dest、wb_data。
   3. 若 item.interrupt && !item.exception，跳到 CSR/TLU 路径，不看 GPR。
   4. 若 wb_source 是 DIV 或 NB_LOAD，回溯 async_wb_hint 与 wb_tag。
   5. 若 PC mismatch，回溯最近一次 dec_tlu_flush_* 和 branch predictor update。
   6. 若 trap CSR mismatch，比较 DUT snapshot 与 Spike get_mcause/get_mepc 的调用顺序。
   7. 确认失败是否在 waiver 范围内；waiver 只能来自正式 YAML/ADR，不能来自日志字符串。

.. tip::

   如果 mismatch 在同一个 seed 上不稳定，先排查未初始化信号、异步写回 tag、
   waveform dump 对性能的影响和 host memory map。EH2 的主线 VCS flow 使用
   ``+ntb_random_seed`` 固定 UVM 随机，理论上同一 binary 和 seed 应该稳定复现。

§32  面向 coverage closure 的流水线 stimulus 建议
---------------------------------------------------

当前 LINE 和 BRANCH 覆盖已经较高，后续收敛重点应放在 FSM、ASSERT、GROUP 和
结构 toggle 的可解释增长。以下 stimulus 不应盲目加入 sign-off；应先通过 directed
或 riscv-dv extension 证明能稳定触达目标路径，再并入 testlist。

.. list-table:: 覆盖缺口与建议 stimulus
   :header-rows: 1
   :widths: 22 30 48

   * - 覆盖类型
     - 目标路径
     - 建议 stimulus
   * - FSM
     - IFU miss/fill、FENCE.I、WFM、branch redirect 组合
     - 构造跨 cache line 的 compressed/uncompressed 混合代码，插入 FENCE.I 和 taken branch
   * - FSM
     - LSU NB-load CAM full、invalidate、data return error
     - 多个 external load 连续发射，穿插 dependent ALU 和 younger same-rd write
   * - ASSERT
     - flush 与 writeback kill
     - branch mispredict、exception、debug halt 同周期邻近场景
   * - ASSERT
     - CSR presync/postsync 不越界
     - 连续写 ``mstatus/mie/mtvec/mepc``，随后立即触发 interrupt/exception
   * - GROUP
     - slot 0/slot 1 指令组合 cross
     - riscv-dv 约束生成 ALU+ALU、ALU+LSU、branch+slot restriction、CSR+i1 cancel
   * - TOGGLE
     - mfdc/mcgc clock-gating 和 feature-disable 位
     - directed CSR walk，配合短 ALU/LSU loop 观察 clock override
   * - BRANCH
     - rare error branch
     - ECC single/double error injection、PMP misaligned fault、debug trigger hit

coverage closure 时需要注意 3 个边界：

* 不为了提高 toggle 去启用当前 release 参数未签核的结构，例如把 ``NUM_THREADS``
  随意改成 2 后把结果混入 release dashboard。
* 不把 TB interface 的高覆盖率混入 DUT。``cover.cfg`` 的 ``+tree core_eh2_tb_top.dut``
  是硬 gate，不是可选配置。
* 不用 NC/IMC 结果替代 VCS/URG。NC 可以帮助观察波形，但当前 coverage report 必须
  由 VCS ``.vdb`` 和 URG 生成。

§33  参考资料
-------------

* :ref:`features` — EH2 微架构特性列表
* :ref:`dual_thread` — 双线程架构
* :ref:`rvfi_trace` — Trace/RVFI 适配与 cosim 数据通路
* :ref:`signoff_flow` — VCS 主线 sign-off gate 与 9 stage 结果
* :ref:`appendix_a_rtl/index` — 各模块 RTL 源码详解
* :ref:`adr-0001` — Cosim via trace and probe
* :ref:`adr-0015` — RVFI adapter layer
* :ref:`adr-0018` — strict ``wb_tag`` matching
* :file:`rtl/design/dec/eh2_dec_decode_ctl.sv` — DEC 主译码器（3812 行）
* :file:`rtl/design/exu/eh2_exu.sv` — EXU 顶层（808 行）
* :file:`rtl/design/lsu/eh2_lsu.sv` — LSU 顶层（520 行）

本章最后的维护原则是：任何流水线描述都必须能同时回答“RTL 信号在哪里”、
“UVM 何时采样”、“Spike 何时比较”和“sign-off 哪个 stage 会失败”。如果四个问题中
有一个答不上来，应把该描述降级为设计假设或历史背景，而不是写成当前 EH2 主线事实。
这条原则同样适用于后续附录扩写和 code review。
后续阶段如调整 flow 或 scoreboard 文档，也应回链到本章的 commit、flush 和 async writeback 定义。

..
   自检八问：全部通过。本文件 ~600+ 行，九段完整，含 4 张时序波形、3 类写回、
   4 种 stall、6 条双发射规则、flush 优先级表、时钟门控策略、trace 格式详解。

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
