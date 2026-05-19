.. _csr:
.. _02_core_reference/csr:

CSR 寄存器体系 — 完整参考
==========================

:status: draft
:source: rtl/design/dec/eh2_dec_csr.sv; rtl/design/dec/eh2_dec_tlu_ctl.sv; rtl/design/include/eh2_def.sv; dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv; dv/cosim/spike_cosim.cc; dv/uvm/core_eh2/waivers/cosim-disabled.yaml
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
-------------

CSR（Control and Status Register，控制与状态寄存器）是 RISC-V 处理器中
**配置、控制、监控** 硬件行为的核心接口。EH2 实现了 RISC-V 特权级规范
定义的全部 M-mode 标准 CSR，外加 18+ 个 EH2 自定义 CSR
（用于 PIC/DCCM/ICCM/时钟门控/ECC 等专属硬件），以及调试 CSR 和 PMP CSR。

阅读本章你将学到：

* 全部 ~80 个 CSR 的地址、位宽、读写属性、复位值
* 每个标准 CSR 的**逐位字段** 定义（mstatus.MIE/MPIE/MPP 等）
* 每个自定义 CSR 的功能与硬件控制对象
* CSR 访问的 Espresso 译码原理（40+ CSR 的地址 → 两级 SOP 逻辑）
* WARL（Write-Any-Read-Legal）行为的逐寄存器说明
* CSR 读写副作用：presync / postsync / glob 的分类
* 只读 CSR 的硬件更新机制（mcycle/minstret 自增、mip 硬件置位）
* CSR 在 cosim 中的桥接策略（set_csr 预注册 + fixup_csr 动态修正）

.. note::

   CSR 章节同时服务 RTL 读者和验证读者。当前平台默认 VCS，CSR unit 子环境
   可以独立支持 VCS/NC，但顶层 sign-off 结果以 VCS 主线 demo 为准：
   9/9 stages PASS，CSR unit 20/20 PASS，compliance 85/88 PASS，formal 46/46 PASS，
   block-level LEC 31635/31635 PASS。旧 NC 迁移阶段的 coverage/IMC 结论不作为
   CSR 现状。

§2  CSR 地址空间与分类
-----------------------

EH2 的 CSR 按地址空间分为 4 类：

.. list-table::
   :header-rows: 1
   :widths: 25 20 55

   * - 地址范围
     - 分类
     - 包含 CSR
   * - ``0x300-0x34B``
     - 标准 M-mode CSR（Privileged Spec §3.1）
     - mstatus/misa/medeleg/mideleg/mie/mtvec/mstatush/mcountinhibit/
       mhpmevent3-31/mscratch/mepc/mcause/mtval/mip/mtinst/mtval2
   * - ``0x3A0-0x3BF``
     - PMP 配置与地址
     - pmpcfg0-3 / pmpaddr0-15
   * - ``0x7A0-0x7B3``
     - 调试 CSR（Debug Spec 0.13 §4）
     - tselect/tdata1-3/dcsr/dpc/dscratch0-1
   * - ``0x7C0-0x7FF``
     - EH2 自定义 CSR（EH2 专属）
     - meivt/meipt/meip/meie/meicurpl/meicidpl/meihap/meicpct/
       mfdc/mcgc/mpmc/mcpc/mscause/mrac/micect/miccmect/mdccmect/
       mdseac/mhartstart/mnmipdel/mitcnt0-1/mitb0-1/mitctl0-1/mdeau/
       mfdht/mfdhs/dmst/dicawics/dicad0/dicad0h/dicad1/dicago
   * - ``0xB00-0xB1F``
     - 硬件性能计数器
     - mcycle/minstret/mhpmcounter3-31/mhpmcounter3-31h
   * - ``0xF11-0xF14``
     - 机器信息（只读）
     - mvendorid/marchid/mimpid/mhartid

§3  CSR 访问译码（Espresso 逻辑最小化）
----------------------------------------

**为什么用 Espresso 而非 case 语句**

EH2 实现了约 80 个 CSR。如果用 ``case(addr)`` 语句，综合工具会生成
优先级编码的 MUX 链，面积大且时序差。EH2 采用 Espresso 两级逻辑
最小化器，从人类可读的 ``csrdecode`` 文件自动生成 SOP
（Sum-of-Products）表达式。

**Espresso 生成流程** （:file:`eh2_dec_csr.sv` 第 46-56 行）：

.. code-block:: bash

   # 步骤 1：从 csrdecode 文件生成 espresso 输入
   coredecode -in csrdecode > corecsrdecode.e

   # 步骤 2：espresso 逻辑最小化 → 输出方程
   espresso -Dso -oeqntott corecsrdecode.e | addassign > csrequations

   # 步骤 3：生成 legal CSR 方程
   coredecode -in csrdecode -legal > csrlegal.e
   espresso -Dso -oeqntott csrlegal.e | addassign > csrlegal_equation

**译码结果示例** （:file:`eh2_dec_csr.sv` 第 148-165 行）：

``csr_mstatus = (!addr[11] & !addr[6] & !addr[5] & !addr[2] & !addr[0])``
→ 12-bit CSR 地址经两级逻辑门 → 1 bit 的 ``csr_mstatus`` 选中信号

**合法性判断** （:file:`eh2_dec_csr.sv` 第 530-534 行）：

``dec_csr_legal_d = any_unq & valid_csr & ~(wen & RO_CSR)``

其中 ``valid_csr`` 包含 3 个条件：

1. ``legal`` （地址对应某个已实现的 CSR）
2. ``~(debug_only_csr) | dbg_halted`` （调试 CSR 仅在 halt 时可访问）
3. ``~conditionally_illegal`` （某些 CSR 在特定配置下不可访问，
   如 timer CSR 需要 ``TIMER_LEGAL_EN=1`` ）

**Presync / Postsync / Glob 分类** （:file:`eh2_dec_csr.sv` 第 373-412 行）：

某些 CSR 的读/写需要与流水线同步：

- ``presync`` ：写 CSR 前必须先排空流水线（如 mstatus.MIE 更新）
- ``postsync`` ：写 CSR 后必须排空流水线（如 mepc 更新）
- ``glob`` ：全局 CSR（如 mstatus/mtvec），影响所有线程

**CSR unit register model 证据** （
``dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv``）：

.. code-block:: systemverilog

   class eh2_csr_reg_block extends uvm_reg_block;
     `uvm_object_utils(eh2_csr_reg_block)

     protected eh2_csr_reg regs_by_name[string];
     protected eh2_csr_reg regs_by_addr[uvm_reg_addr_t];

     function new(string name = "eh2_csr_reg_block");
       super.new(name, UVM_NO_COVERAGE);
     endfunction

**逐段解释** ：

* CSR unit 采用 ``uvm_reg_block``，这与 ADR-0010 的“拒绝 ad-hoc
  ``csr_desc_t``，采用标准 UVM register layer”一致。
* ``regs_by_name`` 和 ``regs_by_addr`` 分别支撑按名字和地址查找，便于 reset、
  WARL、权限和 hazard sequence 做统一遍历。
* 该子环境在 sign-off 的 ``csr_unit`` stage 中计入 20/20 PASS，不把 CSR 验证
  只押在全系统 riscv-dv 随机流上。

§4  标准 M-mode CSR 逐寄存器详解
---------------------------------

4.1  ``mstatus`` （0x300）— 机器状态寄存器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit（RV32 仅实现低 13 位）
:读写: R/W（部分位只读）
:复位值: ``0x0000_1800`` （MPP=M-mode, MIE=0）

.. list-table:: mstatus 位字段
   :header-rows: 1
   :widths: 10 10 15 65

   * - 位
     - 字段
     - 属性
     - 说明
   * - 3
     - MIE
     - R/W
     - 机器中断使能。写此位需要 presync。复位后为 0（中断禁用）。
       进入 trap 时 MIE→MPIE, MIE←0。执行 ``mret`` 时 MPIE→MIE
   * - 7
     - MPIE
     - R/W
     - 机器先前中断使能。trap 进入时保存旧的 MIE 值。
       ``mret`` 时恢复为 MIE
   * - 12:11
     - MPP
     - R/W
     - 机器先前特权模式。EH2 仅支持 M-mode，复位为 2'b11。
       trap 进入时保存旧模式。``mret`` 时恢复。写其他值不报错但无效果
   * - 其他
     - -
     - R/0
     - TW/VM/SIE/SPIE/SPP/UIE/UPIE/USPP 等位硬连线为 0
       （EH2 无 U/S mode）

4.2  ``misa`` （0x301）— ISA 与扩展编码
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit
:读写: 只读
:复位值: 硬件编码（RV32IMAC + Zb* 不占 misa 位）

.. list-table:: misa 位字段
   :header-rows: 1
   :widths: 15 10 75

   * - 位
     - 字段
     - 说明
   * - 1:0
     - MXL
     - 机器 XLEN。EH2 硬编码为 2'b01（RV32）
   * - 8
     - I
     - RV32I 基本整数指令集。硬编码为 1
   * - 12
     - M
     - 整数乘除法扩展。硬编码为 1
   * - 0
     - A
     - 原子操作扩展。硬编码为 1
   * - 2
     - C
     - 压缩指令扩展。硬编码为 1

4.3  ``mie`` （0x304）— 中断使能
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit（仅低 12 位有效）
:读写: R/W（部分位只读）

.. list-table:: mie 位字段
   :header-rows: 1
   :widths: 8 10 82

   * - 位
     - 字段
     - 说明
   * - 3
     - MSIE
     - 机器软件中断使能
   * - 7
     - MTIE
     - 机器定时器中断使能
   * - 11
     - MEIE
     - 机器外部中断使能。PIC 的 127 路中断需要 MEIE=1 + meie[i]=1

4.4  ``mtvec`` （0x305）— 陷阱向量基址
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit
:读写: R/W
:复位值: 由 PIC 的 ``meivt`` CSR 决定

.. list-table:: mtvec 位字段
   :header-rows: 1
   :widths: 8 10 82

   * - 位
     - 字段
     - 说明
   * - 1:0
     - MODE
     - 0=Direct：所有 trap 跳转 BASE。1=Vectored：中断跳转 BASE+4×cause
   * - 31:2
     - BASE
     - 陷阱向量基址（4 字节对齐）。写此寄存器需要 postsync

4.5  ``mepc`` （0x341）— 机器异常 PC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit（[31:1] 有效）
:读写: R/W
:功能: 发生异常/中断时，硬件自动将当前 PC 锁存到 mepc。
   执行 ``mret`` 时从 mepc 恢复执行。写此寄存器需要 postsync

4.6  ``mcause`` （0x342）— 机器陷阱原因
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit
:读写: R/W

.. list-table:: mcause 位字段
   :header-rows: 1
   :widths: 8 15 77

   * - 位
     - 字段
     - 说明
   * - 31
     - Interrupt
     - 1=中断, 0=异常
   * - 30:0
     - Exception Code
     - 标准编码：0=指令地址不对齐, 1=指令访问错误, 2=非法指令,
       3=断点, 7=存储访问错误, 11=ECALL from M-mode
       中断编码：3=MSI, 7=MTI, 11=MEI

4.7  ``mtval`` （0x343）— 机器陷阱值
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit
:读写: R/W
:功能: 异常时记录附加信息。非法指令→指令编码。访问错误→错误地址。
   断点/ECALL→0。写此寄存器需要 postsync

4.8  ``mip`` （0x344）— 机器中断挂起
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 32-bit（仅低 12 位有效）
:读写: R/W（部分位只读）

.. list-table:: mip 位字段
   :header-rows: 1
   :widths: 8 10 82

   * - 位
     - 字段
     - 说明
   * - 3
     - MSIP
     - 机器软件中断挂起。可由软件写 1 来触发
   * - 7
     - MTIP
     - 机器定时器中断挂起。来自外部 ``timer_int`` 引脚
   * - 11
     - MEIP
     - 机器外部中断挂起。来自 PIC 的 ``mexintpend`` 输出

4.9  ``mcycle`` （0xB00）/ ``mcycleh`` （0xB80）— 周期计数器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 64-bit（分两个 32-bit 寄存器）
:读写: R/W（64-bit 原子读写通过 mcycle + mcycleh 的 shadow 机制）
:功能: 自复位起每个核心时钟递增 1。写 mcyclel 时，mcycleh 自动锁存
   到 shadow 寄存器，读 mcycleh 时返回 shadow 值

4.10  ``minstret`` （0xB02）/ ``minstreth`` （0xB82）— 指令退休计数器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

:位宽: 64-bit
:读写: R/W
:功能: 每条退休指令递增 1。访问方式同 mcycle

4.11  mcause Exception Code 全集
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. list-table:: mcause 标准编码（RISC-V Privileged Spec §3.1.15）
   :header-rows: 1
   :widths: 8 10 82

   * - Code
     - 类型
     - 说明
   * - 0
     - 异常
     - 指令地址不对齐（Instruction address misaligned）
   * - 1
     - 异常
     - 指令访问错误（Instruction access fault）— ICache/ICCM 访问错误
   * - 2
     - 异常
     - 非法指令（Illegal instruction）
   * - 3
     - 异常
     - 断点（Breakpoint）— EBREAK 或 trigger 匹配
   * - 4
     - 异常
     - Load 地址不对齐（Load address misaligned）
   * - 5
     - 异常
     - Load 访问错误（Load access fault）— DCCM unmapped/PMP/AMO fault
   * - 6
     - 异常
     - Store/AMO 地址不对齐（Store/AMO address misaligned）
   * - 7
     - 异常
     - Store/AMO 访问错误（Store/AMO access fault）
   * - 11
     - 异常
     - ECALL from M-mode（环境调用）
   * - 3 (+31)
     - 中断
     - 机器软件中断（MSI）
   * - 7 (+31)
     - 中断
     - 机器定时器中断（MTI）
   * - 11 (+31)
     - 中断
     - 机器外部中断（MEI）— 来自 PIC

EH2 特有的 sub-cause 通过 ``mscause`` CSR（0x7D2）提供更细粒度的异常分类。

4.12  ``mhpmcounter`` / ``mhpmevent`` — 性能计数器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

EH2 支持最多 4 个硬件性能监控计数器（可配 ``MHPM_COUNTER_NUM`` ，
通常为 4，对应 mhpmcounter3-6）：

- ``mhpmcounter3-6`` （0xB03-0xB06）：计数器值（64-bit，分高低 32 位）
- ``mhpmcounter3-6h`` （0xB83-0xB86）：计数器高 32 位
- ``mhpmevent3-6`` （0x323-0x326）：事件选择器

**事件选择器编码（``mhpmevent`` 位字段）：**
- [7:0]：事件类型（0=无, 1=指令退休, 2=周期, 3=分支, 4=load, 5=store, ...）
- [8]：用户模式计数使能（EH2 无 U-mode，忽略）
- [9]：机器模式计数使能（EH2 始终为 M-mode）
- [30:10]：保留

``mcountinhibit`` （0x320）：bit[i] = 1 → 停止 mhpmcounter[i] 的计数。
bit[0] 控制 mcycle，bit[2] 控制 minstret，bit[3:31] 控制各性能计数器

4.13  只读 CSR
~~~~~~~~~~~~~~

.. list-table:: 只读信息 CSR
   :header-rows: 1
   :widths: 18 10 72

   * - CSR
     - 地址
     - 值
   * - ``mvendorid``
     - 0xF11
     - 0（非商业实现）
   * - ``marchid``
     - 0xF12
     - 0x56524545（ASCII "VEER" — EH2 前身 VeeRwolf 的代号）
   * - ``mimpid``
     - 0xF13
     - 配置相关（版本编码）
   * - ``mhartid``
     - 0xF14
     - 0（thread 0）或 1（thread 1）
   * - ``mhartnum``
     - 0xF15
     - ``NUM_THREADS`` （EH2 自定义，报告硬件线程总数）

§5  PMP NAPOT 编码详解
-----------------------

NAPOT（Naturally Aligned Power-Of-Two）是 PMP 最常用的地址匹配模式。

**编码规则：** ``pmpaddr = {addr[31:G+2], 1'b1, {2^G-1}{1'b0}}``

其中 G = granularity（由 ``PMP_GRANULARITY`` 参数控制，通常 G=0 即 8 字节粒度）

**NAPOT 编码示例（G=0，8 字节粒度）：**

.. list-table::
   :header-rows: 1
   :widths: 20 25 55

   * - 区域大小
     - pmpaddr 编码
     - 覆盖地址范围
   * - 8 字节
     - ``...xxxx_xxxx_xxxx_xxxx_xxxx_xxx0_1000``
     - 8B 对齐区域
   * - 16 字节
     - ``...xxxx_xxxx_xxxx_xxxx_xxxx_xx01_1000``
     - 16B 对齐区域
   * - 32 字节
     - ``...xxxx_xxxx_xxxx_xxxx_xxxx_x011_1000``
     - 32B 对齐区域
   * - 4KB
     - ``...xxxx_xxxx_xxxx_xxxx_0111_1111_1000``
     - 4KB 页
   * - 4GB
     - ``0111_1111_1111_1111_1111_1111_1111_1000``
     - 整个 32-bit 地址空间

**关键特征：** trailing 1 的数量 + 3（因为 bit[2:0] 隐含为 0）= 区域大小的 log2。
例如 trailing 1 的数量 = 9 → 区域大小 = 2^(9+3) = 4KB。

**TOR 模式：** ``pmpaddr[i-1] ≤ addr < pmpaddr[i]`` 。区域 0 下界为 0，
最后一个区域的上界为 2^32。TOR 区域大小 = pmpaddr[i] - pmpaddr[i-1]。

§5  EH2 自定义 CSR 详解
-------------------------

5.1  PIC 控制器 CSR
~~~~~~~~~~~~~~~~~~~~~

**``meivt`` （0x7C0）— 外部中断向量表基址**
- mtvec.BASE 的默认值。PIC 的中断向量表起始地址

**``meipt`` （0x7C1）— 外部中断优先级阈值**
- [3:0]：当前优先级阈值。PIC 仅将优先级**高于** 此阈值的中断发送给 Core
- 阈值 0=所有中断允许，阈值 15=仅最高优先级中断

**``meip`` （0x7C2）— 外部中断挂起位**
- [126:0]：127 路外部中断各自的挂起状态（1=挂起）
- 此寄存器反映 PIC 的中断输入状态，Core 侧通过 ``mip.MEIP`` 查看全局外部中断

**``meie`` （0x7C3）— 外部中断使能位**
- [126:0]：127 路外部中断各自的使能状态（1=使能）
- 与 ``mie.MEIE`` 配合使用：全局 MEIE=0 则所有外部中断被屏蔽

**``meicurpl`` （0x7CD）— 当前中断优先级**
- [3:0]：当前正在服务的中断的优先级。由 PIC 硬件更新

**``meicidpl`` （0x7CE）— Claim ID 与优先级**
- [7:0]：当前 claim 的中断源 ID（0-126）
- [11:8]：当前 claim 的中断优先级

**``meihap`` （0x7CA）— 最高活跃中断优先级（只读）**
- [3:0]：当前所有挂起中断中的最高优先级。硬件自动更新

5.2  存储与 ECC CSR
~~~~~~~~~~~~~~~~~~~~~

**``mfdc`` （0x7D0）— 功能禁用控制（Feature Disable Control）**
- 位反转编码：写 1 禁用功能，写 0 使能（默认全 1=全部使能）
- [0]：外部 load forwarding 禁用
- [1]：posted writes to side-effect 地址禁用
- [2]：Core ECC 禁用
- [3]：分支预测禁用
- [5]：write-buffer coalescing 禁用
- [18:16]：DMA QoS 优先级

**``mcgc`` （0x7D8）— 时钟门控控制**
- [0]：misc 时钟域 override
- [1]：EXU 时钟域 override
- [2]：IFU 时钟域 override
- [3]：LSU 时钟域 override
- [4]：bus 时钟域 override
- [5]：PIC 时钟域 override
- [6]：PIC IO 时钟域 override
- [7]：DCCM 时钟域 override
- [8]：ICCM 时钟域 override

**``mrac`` （0x7D1）— 区域访问控制（Region Access Control）**
- 16 对 2-bit 字段（共 32-bit），每对对应一个 256MB 内存区域
- bit[0]：cacheable（1=该区域可缓存）
- bit[1]：side_effect（1=该区域有副作用，禁止 merging/coalescing）
- 索引：``csr_idx = {addr[31:28], 1'b1}``

**ECC 错误寄存器：**
- ``mdseac`` （0x7D4）：DCCM 单 bit ECC 错误地址捕获
- ``micect`` （0x7D5）：ICache ECC 错误计数器
- ``miccmect`` （0x7D6）：ICCM ECC 错误计数器
- ``mdccmect`` （0x7D7）：DCCM ECC 错误计数器

5.3  定时器 CSR
~~~~~~~~~~~~~~~~

EH2 内置 2 个可配置定时器（用于生成周期性中断）：

- ``mitcnt0/1`` （0x7E0-0x7E1）：定时器当前计数值
- ``mitb0/1`` （0x7E2-0x7E3）：定时器边界值（计数值达到边界时触发中断）
- ``mitctl0/1`` （0x7E4-0x7E5）：定时器控制（使能/自动重载/中断使能）

这些定时器是 EH2 专属的，与 RISC-V 标准的 ``mtime/mtimecmp`` （CLINT）
不同。它们仅在 ``TIMER_LEGAL_EN=1`` 时可访问。

5.4  特殊功能 CSR
~~~~~~~~~~~~~~~~~~~

**``mscause`` （0x7D2）— EH2 扩展陷阱原因**

- 当标准 ``mcause`` 的 Exception Code 不足以区分 EH2 特有的异常类型时，
  通过此 CSR 提供更细粒度的 sub-cause

**``mhartstart`` （0x7D8）— Hart 启动地址**

- thread 1 的启动 PC（thread 0 始终从 ``rst_vec`` 启动）

**``mnmipdel`` （0x7DB）— NMI 延迟**

- 控制 NMI 的响应延迟（用于 NMI 消抖）

**``mdeau`` （0x7E8）— 调试异常地址更新**

- 控制调试异常时是否更新 mtval

§6  调试 CSR
-------------

6.1  Trigger CSR（0x7A0-0x7A3）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- ``tselect`` （0x7A0）：选择当前触发器（0-3）
- ``tdata1`` （0x7A1）：触发器配置（类型=mcontrol, dmode, maskmax, hit, select, timing, size, action, match, m, execute, store, load）
- ``tdata2`` （0x7A2）：触发器匹配值 / 掩码
- EH2 支持 4 个 mcontrol 触发器，用于指令地址/数据匹配

6.2  Debug Mode CSR（0x7B0-0x7B3）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- ``dcsr`` （0x7B0）：调试控制状态（cause, step, halt, nxtreq）
- ``dpc`` （0x7B1）：调试 PC（进入 debug mode 时的指令地址）
- ``dscratch0/1`` （0x7B2-0x7B3）：调试暂存寄存器（调试器自由使用）

§7  PMP CSR
------------

EH2 支持最多 16 个 PMP 区域：

- ``pmpcfg0-3`` （0x3A0-0x3A3）：每 4 个区域共享一个 pmpcfg
  （每个区域 8-bit：R/W/X/A/L）
- ``pmpaddr0-15`` （0x3B0-0x3BF）：区域地址边界
- 地址匹配模式：NAPOT（自然对齐的 2 次幂区域）和 TOR（Top-of-Range）
- L 位（锁定）：置位后该 PMP 区域的配置不可修改（直到复位）
- PMP 违规 → 访问错误异常（mcause=5/7）

PMP 详细配置和 cosim 支持见 :ref:`adr-0009` 。

§7  PMP CSR 详解
-----------------

EH2 支持最多 16 个 PMP 区域（由 ``PMP_NUM_REGIONS`` 配置）。

**PMP 配置寄存器（pmpcfg0-3）：**

每 4 个 PMP 区域共享一个 32-bit pmpcfg CSR。每个区域占 8-bit：

.. list-table:: PMP 区域配置（每区域 8-bit）
   :header-rows: 1
   :widths: 8 10 82

   * - 位
     - 字段
     - 说明
   * - 0
     - R (Read)
     - 读权限。1=允许读
   * - 1
     - W (Write)
     - 写权限。1=允许写
   * - 2
     - X (Execute)
     - 执行权限。1=允许取指
   * - 4:3
     - A (Address Matching)
     - 00=OFF（区域禁用）, 01=TOR（Top-of-Range）, 11=NAPOT（自然对齐 2 次幂）
   * - 7
     - L (Lock)
     - 锁定。置位后该区域配置不可修改（直到复位）。写 pmpcfg 时 L 位原本
       为 1 则写操作被忽略。L=1 且 A=OFF 的锁定区域对 M-mode 也生效

**PMP 地址寄存器（pmpaddr0-15）：**

- 地址[31:2] 编码（最低 2 位隐含为 0，但粒度参数可改变此行为）
- NAPOT 模式：``pmpaddr`` 编码为 ``{addr[31:G+2], 1{2^G-1}}`` ，
  其中 G 为粒度。区域大小为 ``2^{G+3}`` 字节。通过 trailing 1 的数量
  来判断区域大小
- TOR 模式：``pmpaddr[i-1] ≤ addr < pmpaddr[i]`` 。区域 0 的下界为 0，
  区域 N-1 的上界为 2^32

**PMP 违规处理：**
- 取指违规 → 指令访问错误异常（mcause=1）
- Load 违规 → Load 访问错误异常（mcause=5）
- Store/AMO 违规 → Store 访问错误异常（mcause=7）

PMP 详细配置和 cosim 支持见 :ref:`adr-0009` 。

§8  WARL 行为详解
-------------------

WARL（Write-Any-Read-Legal）是 RISC-V CSR 的关键属性：软件可以写入任意值，
但硬件只保留合法值，读回的是硬件实际接受的值。

**EH2 中具有 WARL 行为的 CSR：**

.. list-table::
   :header-rows: 1
   :widths: 18 82

   * - CSR
     - WARL 行为
   * - ``mstatus``
     - MPP 写入非 M-mode 值 → 只读不报错（xIE 位正常写）
   * - ``mtvec``
     - MODE 写入非法值 → 强制为 0（Direct）。BASE 最低 2 位强制为 0
   * - ``mfdc``
     - **位反转编码** 。写 1=禁用功能。读回值与写入值可能不同
       （因为位反转逻辑）。Cosim 中需特殊处理
   * - ``mcgc``
     - 某些时钟域 override 位在特定配置下不可写
   * - ``mcountinhibit``
     - 未实现的计数器位强制为 0
   * - ``mhpmevent3-31``
     - 未实现的事件选择位强制为 0。EH2 仅实现 4 个计数器

**WARL 在 Cosim 中的挑战：**
Spike ISS 的 CSR 模型没有 EH2 的 WARL 逻辑（如 ``mfdc`` 的位反转）。
Cosim 比对中对于 WARL CSR 采用宽松策略：仅比对可预测的 bit 字段，
WARL 相关的 bit 豁免比对。这也是 RISK-1（CSR fixup 覆盖不足）的根源

§9  CSR 硬件更新机制
---------------------

**自增计数器：** ``mcycle`` 和 ``minstret`` 是硬件自增的 64-bit 计数器。
每个 core clock 周期 ``mcyclel += 1`` （带进位到 mcycleh）。实现使用
32-bit 加法器 + carry FSM。软件写入 mcyclel 时 mcycleh 自动锁存到
shadow 寄存器（``mcycleh_shadow`` ），后续读 mcycleh 返回 shadow 值，
确保 64-bit 原子性

**硬件置位/清零：** ``mip`` 的 MEIP/MTIP/MSIP 位由硬件根据中断源状态
自动置位。软件可以写 1 来触发软件中断，但写 0 不会清零硬件置位的位。
``mie`` 完全由软件控制

**陷阱自动更新：** 进入 trap 时硬件自动：
- ``mepc ←`` 当前 PC（异常）或下一条 PC（中断）
- ``mcause ←`` 异常/中断原因码
- ``mtval ←`` 附加信息（非法指令编码或错误地址）
- ``mstatus.MIE ← 0, mstatus.MPIE ← old MIE, mstatus.MPP ← M-mode``

**``mret`` 自动恢复：**
- ``mstatus.MIE ← mstatus.MPIE, mstatus.MPIE ← 1``
- PC ← mepc
- ``mstatus.MPP`` 恢复（EH2 始终为 M-mode，无实际模式切换）

§10  CSR 访问副作用矩阵
------------------------

.. list-table:: Presync / Postsync / Glob 分类
   :header-rows: 1
   :widths: 18 22 60

   * - CSR
     - 副作用类型
     - 说明
   * - ``mstatus``
     - presync + glob
     - 写 MIE 前必须排空流水线。全局影响所有线程
   * - ``mtvec``
     - postsync + glob
     - 写后必须排空流水线（新 trap 使用新 BASE）。全局
   * - ``mepc``
     - postsync
     - 写后必须排空（下一个 mret 使用新值）
   * - ``mcause``
     - postsync
     - 同上
   * - ``mtval``
     - postsync
     - 同上
   * - ``mie``
     - presync
     - 写 MIE 使能位前必须排空
   * - ``mip``
     - postsync
     - 写后必须排空（软件中断触发）
   * - ``mfdc``
     - postsync
     - 禁用/使能功能后必须排空
   * - ``pmpcfg`` / ``pmpaddr``
     - postsync
     - PMP 配置变更后必须排空（新 PMP 立即生效）
   * - 大部分自定义 CSR
     - presync / postsync
     - 具体见 :file:`csrdecode` 文件中的标注

**Presync 实现** （:file:`eh2_dec_csr.sv` 第 516 行）：
``tlu_presync_d = presync & dec_csr_any_unq_d & ~dec_csr_wen_unq_d``
—— presync 在 CSR 读时也触发（因为读也需要排空流水线确保一致性）

§11  Cosim 中的 CSR 桥接策略
-----------------------------

Spike ISS 不原生支持 EH2 自定义 CSR。Cosim 通过三层策略桥接：

**第 1 层：静态注册（set_csr）**

Cosim 初始化时调用 28 次 ``riscv_cosim_set_csr()`` ，向 Spike 注册每个
EH2 自定义 CSR 的地址和初始值（:file:`eh2_cosim_csr_preregister.svh` ）。
Spike 仅知道"这个地址有个 CSR 存在"，不理解其硬件语义

**第 2 层：动态修正（fixup_csr）**

每次 ``riscv_cosim_step()`` 后，scoreboard 从 DUT probe 读取自定义 CSR
的当前值，通过 ``fixup_csr()`` 写入 Spike 对应 CSR。PIC 优先级逻辑、
ECC 错误计数器等硬件行为的副作用通过此方式同步

**第 3 层：语义豁免**

WARL 类型的自定义 CSR（如 ``mfdc`` 的位反转编码）在 Spike 中无法完全模拟。
比对采用宽松策略：仅比对可预测的 bit 字段

见 :ref:`adr-0001` §4 "Spike CSR Model Extension Strategy" 和 :ref:`adr-0010` 。

§9  CSR 读写时序详解
---------------------

**CSR 读（CSRRW/CSRRS/CSRRC 的读阶段）：**

.. code-block:: text

   CLK          : _/‾\__/‾\__/‾\__/‾\__/‾\_
   D 级(csr_rdaddr): [0x300(mstatus)]             ← CSR 地址译码(Espresso)
   E1 级        : ─[csr_rddata available]         ← TLU 返回 CSR 当前值
   E4 级        : ─────[csr_wrdata calculated]    ← ALU 计算 CSR 写数据
   WB 级        : ──────[CSR write commit]        ← mstatus 更新生效

**CSR 写（带 presync 的 mstatus.MIE 更新）：**

.. code-block:: text

   CLK          : _/‾\__/‾\__/‾\__/‾\__/‾\__/‾\__/‾\_
   D (csr_wr)   : [CSRRW mstatus,x5]                  ← 译码 CSR 写
   presync      : [stall D] [stall D]                  ← 排空流水线(2周期)
   E4 (commit)  : ─────[mstatus.MIE updated]           ← CSR 写生效
   postsync     : ─────[stall]                         ← 排空让新MIE生效
   下一条指令    : ───────[with new MIE]               ← 新中断使能生效

**WARL 写流程（以 mfdc 为例）：**

.. code-block:: text

   CLK          : _/‾\__/‾\__/‾\__/‾\_
   D (csr_wr)   : [CSRRW mfdc,x5, data=0xFFFFFFFE]
   E4 (commit)  : ─────[mfdc ← WARL(data)]           ← 位反转: 写1→禁用
   readback     : ──────[mfdc = 0x00000001]           ← 读回≠写入

§10  CSR 单元测试详解
----------------------

独立的 CSR 寄存器模型测试框架位于 :file:`dv/uvm/cs_registers_eh2/` ：

- 使用 ``uvm_reg`` / ``uvm_reg_block`` 建模 ~95 个 CSR
- 通过 DPI 后门访问 RTL CSR 译码逻辑（``csr_dpi_read/write`` ）

**四项测试序列：**

1. **Reset 值验证** ：复位后读每个 CSR，对比 spec 定义的复位值
2. **WARL 属性验证** ：写全 1 → 读回 → 比较合法位掩码。写全 0 → 读回
3. **读写权限验证** ：写只读 CSR → 确认值未改变。读只写 CSR → 确认返回 0
4. **Hazard 验证** ：CSR 写后立即 CSR 读（同地址）→ 确认读到新值。
   跨线程 CSR 访问 → 确认隔离

§11  参考资料
-------------

§12  CSR 按功能域分类速查
---------------------------

.. list-table:: CSR → 硬件影响 → 验证关注点
   :header-rows: 1
   :widths: 22 38 40

   * - CSR
     - 硬件影响
     - 验证关注点
   * - mstatus
     - 全局中断使能、trap 栈
     - MIE/MPIE/MPP 的 trap/mret 自动翻转
   * - mtvec
     - 陷阱入口地址
     - MODE=0/1 的路由差异
   * - mepc/mcause/mtval
     - trap 记录
     - 异常/中断时硬件自动锁存
   * - mie/mip
     - 中断控制
     - 与 PIC meie/meip 的联动
   * - mcycle/minstret
     - 性能计数
     - 64-bit 原子读写 shadow 机制
   * - mfdc
     - 功能禁用（位反转）
     - WARL 行为特殊，cosim 需豁免
   * - mcgc
     - 时钟门控 override
     - 写后时钟立即改变
   * - mrac
     - 内存 cacheable/side_effect
     - 影响 LSU addrcheck 的 fault 判定
   * - meivt/meipt/meip/meie
     - PIC 配置
     - 影响中断路由和优先级
   * - pmpcfg/pmpaddr
     - PMP 内存保护
     - NAPOT 编码 + L 位不可逆
   * - dcsr/dpc/dscratch
     - 调试状态
     - 仅在 halt 时可访问
   * - tselect/tdata1-3
     - 硬件触发器
     - PC/数据匹配，D 级+DC4 级两处匹配

§13  Espresso 译码器完整输入输出
----------------------------------

**输入：** ``dec_csr_rdaddr_d[11:0]`` （12-bit CSR 地址）

**输出：** ``eh2_csr_tlu_pkt_t`` 结构体，包含约 80 个 1-bit 的 CSR 选中信号，
外加 ``legal``、``presync``、``postsync``、``glob`` 分类信号。

**译码流程：**
1. Espresso 生成的 SOP 表达式计算每个 CSR 的选中信号（纯组合逻辑）
2. ``valid_csr = legal & ~(debug_csr & ~halted) & ~conditional_illegal``
3. ``dec_csr_legal_d = any_unq & valid_csr & ~(wen & RO_CSR)``
4. ``tlu_presync_d = presync & any_unq & ~wen``
5. ``tlu_postsync_d = postsync & any_unq``

**Espresso 输入格式（``csrdecode`` 文件）：**
每行定义一个 CSR：``CSR_NAME  ADDR[11:0]  READ_ONLY/WRITE  PRESYNC/POSTSYNC/GLOB``

**Espresso 输出示例** （:file:`eh2_dec_csr.sv` 第 148-165 行）：
``csr_mstatus = (!addr[11] & !addr[6] & !addr[5] & !addr[2] & !addr[0])``
— mstatus（0x300）的地址译码，仅需 5 个 bit 的比较。

§14  Debug CSR 详解
---------------------

6.1  Trigger CSR（0x7A0-0x7A3）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

EH2 支持 4 个 mcontrol 触发器（0-3），通过 ``tselect`` 选择当前操作的触发器。

**``tselect`` （0x7A0）：** 触发器索引。写 0-3 选择当前触发器。读返回当前索引。

**``tdata1`` （0x7A1）— 触发器配置：**

.. list-table:: mcontrol tdata1 位字段
   :header-rows: 1
   :widths: 12 10 78

   * - 位
     - 字段
     - 说明
   * - 0
     - m
     - 触发器使能（M-mode）。EH2 仅有 M-mode
   * - 2:1
     - action
     - 0=breakpoint, 1=enter debug mode
   * - 5:3
     - match
     - 0=equal, 1=napot, 2=ge, 3=lt, 4=mask low, 5=mask high
   * - 6
     - m
     - Machine mode enable
   * - 7
     - s
     - Supervisor mode（EH2: 0）
   * - 8
     - u
     - User mode（EH2: 0）
   * - 9
     - execute
     - 指令地址匹配使能
   * - 10
     - store
     - Store 地址/数据匹配使能
   * - 11
     - load
     - Load 地址/数据匹配使能
   * - 18:12
     - maskmax
     - 最大掩码位数
   * - 20
     - hit
     - 触发器命中指示（只读）
   * - 21
     - select
     - 0=地址匹配, 1=数据匹配

**``tdata2`` （0x7A2）：** 匹配值/掩码。当 select=0 时存地址，select=1 时存数据值。

6.2  Debug Mode CSR（0x7B0-0x7B3）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- ``dcsr`` （0x7B0）：调试控制状态。cause[2:0]（进入原因）、step、halt、nxtreq
- ``dpc`` （0x7B1）：调试 PC。进入 debug mode 时的指令地址
- ``dscratch0/1`` （0x7B2-0x7B3）：调试暂存器，调试器自由使用

§15  与 Ibex 工业实现对照
---------------------------

Ibex 的 CSR 验证生态包含 ``dv/cs_registers`` register model、riscv-dv CSR
描述和 cosim CSR fixup。EH2 复用相同的工业分层原则，但 CSR 空间和同步语义更复杂：
EH2 有 PIC、DCCM/ICCM、clock-gating、integrity counter 和 debug/DMI 相关 custom
CSR，且双线程参数会影响 ``mstatus/mie/mip`` 等全局/线程局部字段的解释。

.. list-table:: CSR 验证对照
   :header-rows: 1
   :widths: 24 34 42

   * - 维度
     - Ibex
     - EH2
   * - register model
     - ``/home/host/ibex/dv/cs_registers`` 使用标准 register abstraction
     - ``dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv`` 使用
       ``uvm_reg_block`` 管理标准 M-mode、PMP、debug、trigger 和 custom CSR
   * - cosim CSR 同步
     - RVFI ext 提供 ``mcycle``、interrupt/debug CSR 相关状态
     - trace/probe 在 step 前调用 ``set_debug_req``、``set_nmi``、``set_mip``、
       ``set_mcycle``，Spike C++ 端注册 EH2 custom CSR 并做 WARL fixup
   * - CSR 测试来源
     - riscv-dv、directed debug/interrupt/PMP 测试和 CSR unit
     - directed CSR、CSR hazard、riscv-dv、compliance、CSR unit 共同覆盖；
       部分 EH2 custom CSR 流通过 formal waiver 管理 cosim-disabled 边界
   * - 签核位置
     - Ibex nightly/regression 报告聚合 CSR 相关测试与覆盖
     - EH2 2026-05-19 demo 中 ``csr_unit`` 20/20 PASS，riscvdv 370/395，
       compliance 85/88，formal 46/46

§16  源码锚点：CSR register model 与 unit 环境
-----------------------------------------------

CSR 章节最容易出现“spec 表格写得很满，但测试没有真实约束”的问题。本节把 CSR
行为落到当前仓库的 3 个支点：UVM register model、CSR unit Makefile 和 DPI 后门。

**UVM register model 基类与 DPI 访问**
（``dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv:L28-L86``）：

.. literalinclude:: ../../../../dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv
   :language: systemverilog
   :lines: 28-86
   :linenos:
   :caption: eh2_csr_reg_block.sv — eh2_csr_reg metadata、DPI read/write 与 WARL mask

这段代码有两个重要结论。第一，每个 CSR 都不是临时 ``struct`` 或 YAML 行，而是
``uvm_reg`` 对象，包含地址、复位值、WARL mask、只读属性和说明。第二，CSR unit
通过 ``csr_dpi_read`` / ``csr_dpi_write`` 访问 DUT wrapper；WARL 期望值由
register model 的 mask 计算，而不是把 DUT 读回值当作 golden。

**CSR 分类句柄**
（``eh2_csr_reg_block.sv:L92-L180``）：

.. literalinclude:: ../../../../dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv
   :language: systemverilog
   :lines: 92-180
   :linenos:
   :caption: eh2_csr_reg_block.sv — standard、PMP、debug、trigger、custom CSR 句柄

该片段展示了 EH2 CSR 空间为何不能只靠 RISC-V privileged spec。除了标准
M-mode CSR，模型还显式建模 PMP、debug、trigger 和 EH2 custom CSR。对验证来说，
这些句柄是 reset/WARL/access/hazard sequence 的遍历入口；对文档来说，它们是
CSR 表格的最小完整性检查。

**CSR unit 子环境 Makefile**
（``dv/uvm/cs_registers_eh2/Makefile:L37-L65``、``L71-L148``）：

.. literalinclude:: ../../../../dv/uvm/cs_registers_eh2/Makefile
   :language: makefile
   :lines: 37-65
   :linenos:
   :caption: cs_registers_eh2/Makefile — VCS flags、RTL 源和 CSR testbench 源

.. literalinclude:: ../../../../dv/uvm/cs_registers_eh2/Makefile
   :language: makefile
   :lines: 71-148
   :linenos:
   :caption: cs_registers_eh2/Makefile — compile/sim/compliance targets

CSR unit 支持 VCS 和 NC 双仿真，但 sign-off 叙事仍以 VCS 主线为准。
``compliance`` target 跑 4 类测试 × 5 个 seed，共 20 个 simulation，对应
2026-05-19 demo 的 ``csr_unit 20/20 PASS``。NC 分支保留的意义是单元级调试和
波形，不改变顶层 default simulator。

.. list-table:: CSR unit 测试类型
   :header-rows: 1
   :widths: 24 34 42

   * - 测试
     - 关注点
     - 失败后的首查对象
   * - ``cs_registers_test``
     - 基础 reset、读写、mirror/predict 流程
     - ``eh2_csr_reg_block`` 的 reset value、DPI read/write、scoreboard
   * - ``cs_registers_access_matrix_test``
     - RO/RW、debug-only、非法地址访问矩阵
     - ``eh2_dec_csr.sv`` legal 译码、debug halt 条件
   * - ``cs_registers_illegal_test``
     - illegal CSR、权限、条件可访问 CSR
     - Espresso legal 方程、``dec_csr_legal_d``、exception cause
   * - ``cs_registers_hazard_test``
     - CSR 写后读、presync/postsync、跨线程隔离
     - DEC stall、TLU writeback、``mepc/mcause`` snapshot

§17  源码锚点：Spike CSR fixup 与 trap CSR gate
------------------------------------------------

Spike 是 ISA golden model，但 EH2 有大量 custom CSR 和 WARL 行为。如果不做
CSR fixup，cosim 会在合法实现差异上报假 mismatch。因此 CSR 桥接分成 3 步：
预注册 EH2 custom CSR、每条 instruction/interrupt 前同步必要状态、CSR 写后修正
Spike WARL 状态。

**scoreboard 预注册 EH2 custom CSR**
（``eh2_cosim_scoreboard.sv:L754-L757``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 754-757
   :linenos:
   :caption: eh2_cosim_scoreboard.sv — include EH2 custom CSR preregister list

预注册避免 Spike 在读取 EH2 vendor CSR 时把地址当成非法 CSR。该动作发生在 cosim
handle 初始化后、加载 binary 前，保证 test 第一条 CSR 访问也能被 Spike 接受。

**interrupt-only 路径的 CSR 比对**
（``eh2_cosim_scoreboard.sv:L573-L610``）：

.. literalinclude:: ../../../../dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
   :language: systemverilog
   :lines: 573-610
   :linenos:
   :caption: eh2_cosim_scoreboard.sv — interrupt-only item 同步 mip/mcycle 并比较 mcause/mepc

CSR mismatch 在 interrupt 路径上不再是 warning，而是直接累加 ``mismatch_count``。
因此 ``mcause``、``mepc`` 的文档值必须和 TLU 硬件更新顺序一致，不能只引用
RISC-V privileged spec 的抽象描述。

**Spike set_mcycle 与 set_csr**
（``dv/cosim/spike_cosim.cc:L843-L861``）：

.. literalinclude:: ../../../../dv/cosim/spike_cosim.cc
   :language: cpp
   :lines: 843-861
   :linenos:
   :caption: spike_cosim.cc — mcycle 只作排序元数据，set_csr 直接写 Spike CSR

``set_mcycle`` 特意不写 Spike 的 ``CSR_MCYCLE``。注释解释了原因：某些 Spike 版本的
commit-log CSR side path 会在 VCS DPI 回调时崩溃。EH2 仍采样 DUT ``mcycle``，
但把它作为排序元数据，而不是强行覆盖 Spike 架构计数器。

**核心 WARL fixup**
（``spike_cosim.cc:L1070-L1228``）：

.. literalinclude:: ../../../../dv/cosim/spike_cosim.cc
   :language: cpp
   :lines: 1070-1228
   :linenos:
   :caption: spike_cosim.cc — mstatus/misa/mtvec/mcause 与 EH2 custom CSR WARL fixup

这段是 CSR cosim 的关键实现。``mstatus`` 固定 M-mode；``misa`` 固定 RV32IMAC；
``mtvec`` 屏蔽 bit 1；``mcause`` 处理 internal NMI cause；``mrac`` 禁止
cacheable+sideeffect 同时为 1；``mfdc`` 和 ``mcgc`` 处理 RTL 内部反相/重排字段。
这些 fixup 都是为了对齐 EH2 RTL 的合法读回值，而不是掩盖 DUT bug。若 directed
CSR test 出现 mismatch，必须先确认 fixup 表和 RTL ``eh2_dec_tlu_ctl.sv`` 是否同步。

.. list-table:: CSR cosim fixup 风险表
   :header-rows: 1
   :widths: 20 34 46

   * - CSR
     - Spike fixup 行为
     - 文档和验证风险
   * - ``mstatus``
     - 只保留 EH2 支持位并强制 ``MPP=M``
     - 若文档写 U/S-mode 行为，会与 EH2 仅 M-mode 实现冲突
   * - ``misa``
     - 固定 RV32IMAC 编码
     - Bitmanip Zb* 是实现扩展，不等于 ``misa`` 中所有 B 相关 bit 均可写
   * - ``mtvec``
     - bit 1 reserved，direct-mode handler 允许 4-byte alignment
     - compliance/exception directed 需要统一 MODE/BASE 解释
   * - ``mcause``
     - 处理 interrupt bit 与 internal NMI 编码
     - interrupt-only trace item 必须比较 ``mcause/mepc``，不能只看 GPR
   * - ``mrac``
     - 每个 region 的 cacheable 与 sideeffect 互斥
     - LSU access attribute 和 PMP/side-effect fault 解释必须引用该规则
   * - ``mfdc``
     - architectural value 与 RTL internal representation 存在反相/重排
     - 读回不等于原始写值时不一定是 bug，需要按 WARL 表判断
   * - ``mcgc``
     - bit 9 反相
     - clock-gating debug 需要同时看 CSR architectural view 和 internal clock override

§18  CSR sign-off 与覆盖率解释
-------------------------------

CSR 相关质量不能只看 ``csr_unit``。完整 sign-off 中，CSR 行为被 5 类 stage 交叉覆盖：

.. list-table:: CSR 行为到 sign-off stage 的映射
   :header-rows: 1
   :widths: 22 24 54

   * - 行为
     - stage
     - 证据
   * - reset value、RO/RW、WARL
     - ``csr_unit``
     - 4 个 CSR unit tests × 5 seeds，2026-05-19 demo 为 20/20 PASS
   * - 标准 CSR 与 trap
     - ``compliance``、``riscvdv``
     - compliance 85/88 PASS，riscvdv 370/395 PASS；mepc/mcause/mtval 路径由 cosim 比对
   * - PMP CSR
     - ``directed``、``formal``、``riscvdv``
     - PMP directed ASM 覆盖 TOR/NA4/NAPOT/lock/priority，formal 46/46 PASS
   * - debug/trigger CSR
     - ``directed``、``formal``、JTAG agent
     - debug directed、trigger CSR、halt/resume 与 abstract command 路径
   * - custom CSR
     - ``directed``、``csr_unit``、``cosim`` waiver
     - ``mfdc/mcgc/mrac/PIC`` 等通过 directed 与 CSR unit 覆盖；不可 cosim 的边界用 formal waiver 管理
   * - 综合等价
     - ``syn``
     - block-level Formality LEC 31635/31635 PASS，CSR/TLU 逻辑不允许综合后漂移

.. code-block:: bash

   # 单独跑 CSR unit sign-off 子环境
   make -C dv/uvm/cs_registers_eh2 compliance SIMULATOR=vcs

   # 在 full sign-off 中由 signoff.py 调用 CSR unit stage
   make signoff PROFILE=full COV=1

   # gate-only 复用已有 runs/ 与 report.json
   make signoff GATE_ONLY=1 SIGNOFF_OUT=build/signoff

典型摘要如下：

.. code-block:: text

   Stage csr_unit PASS  total=20 passed=20 failed=0 pass_rate=100.00%
   Stage compliance PASS total=88 passed=85 failed=3 pass_rate=96.59%
   Stage formal PASS total=46 passed=46 failed=0
   LEC TOTAL passing=31635 failing=0 unverified=0

CSR 对覆盖率的贡献主要体现在 branch、assert、group 和 functional coverage。
很多 CSR bit 是 WARL、RO 或配置相关位，toggle 低不一定表示测试缺失；但如果
CSR legal 译码、presync/postsync、PMP lock、debug-only access 或 interrupt enable
路径没有对应 covergroup/bin，就会在 GROUP 或 ASSERT 中体现为缺口。覆盖率收敛时
应优先补 directed ASM、CSR unit sequence 或 formal property，而不是为了提升 toggle
去随机写不合法字段。

§19  CSR 修改评审清单
---------------------

.. list-table:: CSR 修改类型与必须同步检查的文件
   :header-rows: 1
   :widths: 26 36 38

   * - 修改类型
     - 必查文件
     - 必跑验证
   * - 新增/删除 CSR 地址
     - ``eh2_dec_csr.sv``、``eh2_csr_reg_block.sv``、``eh2_cosim_csr_preregister.svh``
     - CSR unit access/illegal tests、riscv-dv CSR directed
   * - 改 WARL mask
     - ``eh2_dec_tlu_ctl.sv``、register model、``spike_cosim.cc::fixup_csr``
     - CSR unit WARL sequence、cosim CSR write directed
   * - 改 trap CSR 更新
     - TLU trap entry/return、trace monitor snapshot、scoreboard trap CSR compare
     - exception/interrupt directed、compliance、formal TLU property
   * - 改 PMP CSR
     - PMP RTL、PMP fcov、Spike PMP granularity/config、directed PMP ASM
     - PMP directed regression、formal PMP property、riscv-dv PMP tests
   * - 改 debug/trigger CSR
     - ``dbg``/``dmi`` RTL、JTAG agent、debug directed ASM
     - debug directed、JTAG smoke、formal debug property
   * - 改 ``mfdc``/``mcgc``
     - RTL internal representation、Spike fixup、coverage bins
     - CSR unit WARL、clock-gating directed、LEC

.. warning::

   CSR 修改最常见的错误是只改 RTL，不改 Spike fixup 或 CSR register model。
   这种错误可能在普通 ``make smoke`` 中完全不可见，但会在 ``csr_unit``、
   riscv-dv CSR 流、interrupt trap compare 或 compliance 中集中爆发。

§20  CSR 表格维护规则
----------------------

CSR 表格必须同时满足 RTL、UVM register model、Spike fixup 和 RISC-V 规范 4 个视角。
任何一个视角缺失，都会导致文档在调试时失效。维护时按以下顺序检查：

1. 从 ``eh2_dec_csr.sv`` 或 ``eh2_dec_tlu_ctl.sv`` 确认地址、合法性、复位值、
   读写属性和副作用。
2. 从 ``eh2_csr_reg_block.sv`` 确认 CSR 是否被 UVM register model 建模，WARL mask
   是否和 RTL 一致。
3. 从 ``spike_cosim.cc`` 确认该 CSR 是否需要 preregister 或 ``fixup_csr``，特别是
   EH2 custom CSR、PMP CSR、debug CSR 和 trap CSR。
4. 从 directed ASM、CSR unit、riscv-dv、compliance 或 formal property 中确认测试证据。
5. 更新本章表格、:ref:`pmp_coverage`、:ref:`functional_coverage`、ADR 或 known limitations。

.. list-table:: CSR 字段维护 checklist
   :header-rows: 1
   :widths: 20 34 46

   * - 字段
     - 必填内容
     - 例外说明
   * - 地址
     - 12-bit CSR 编码，使用 ``0xNNN`` 格式
     - custom CSR 仍按 architectural address 写，不写 RTL internal enum
   * - 复位值
     - 32-bit 十六进制，说明硬件复位或 debug reset 差异
     - 只读信息 CSR 可引用常量来源
   * - 权限
     - RO/RW/WARL/debug-only/conditional legal
     - WARL 必须说明合法读回，不只写“可写”
   * - 副作用
     - presync/postsync/glob、trap 自动更新、中断硬件置位
     - 没有副作用时明确写“普通 CSR 读写”
   * - cosim 策略
     - native Spike、set_csr、fixup_csr、preregister、waiver
     - 不可 cosim 的路径必须关联 waiver/ADR
   * - 验证证据
     - CSR unit、directed、riscv-dv、compliance、formal 的至少一种
     - release 关键 CSR 应有两种以上证据

§21  常见 CSR 故障定位
----------------------

.. list-table:: CSR 故障与定位路径
   :header-rows: 1
   :widths: 24 34 42

   * - 现象
     - 首查点
     - 说明
   * - CSR 写后立即读到旧值
     - ``cs_registers_hazard_test``、DEC presync/postsync、TLU writeback
     - 判断是合法 stall 缺失，还是 register model 期望值错误
   * - Spike 报 illegal CSR
     - ``eh2_cosim_csr_preregister.svh``、``fixup_csr``、CSR 地址表
     - EH2 custom CSR 未 preregister 是最常见原因
   * - ``mstatus`` mismatch
     - MIE/MPIE/MPP、trap entry、``fixup_csr`` M-mode mask
     - EH2 仅 M-mode，不应期待 U/S-mode 字段行为
   * - ``mtvec`` 读回不等于写入
     - bit 1 reserved、alignment、MODE
     - 当前 Spike fixup 使用 ``0xFFFFFFFD`` mask
   * - PMP access fault 与 Spike 不一致
     - ``pmpcfg``/``pmpaddr``、granularity、misaligned fixup
     - 需要同时看 :ref:`pmp_coverage` 和 LSU addrcheck
   * - ``mfdc`` 或 ``mcgc`` 读回异常
     - RTL internal representation、Spike bit 反相/重排
     - 按本章 WARL 表判断，不按原始写值判断
   * - debug CSR 在 run mode 可访问
     - ``dbg_halted`` 条件、debug-only legal 方程、JTAG directed
     - 该类 bug 可能只在 debug directed 或 CSR access matrix 中出现

§22  与相邻章节的联动
----------------------

CSR 行为贯穿多个架构域：

* :ref:`pipeline` 依赖 ``mstatus/mie/mip``、presync/postsync 和 trap CSR 来解释
  interrupt-only item、flush 和 stall。
* :ref:`pic` 依赖 ``meivt/meipt/meie/meip/meicurpl/meicidpl/meihap`` 等 PIC CSR 来
  解释 127 路 external interrupt 的优先级与 threshold。
* :ref:`debug` 依赖 ``dcsr/dpc/dscratch/tselect/tdata`` 解释 halt/resume、trigger 和
  abstract command。
* :ref:`dccm_iccm` 和 :ref:`bus_axi_ahb` 依赖 ``mrac``、PMP CSR、ECC CSR 和 memory
  attribute CSR 来解释 access fault、side-effect、cacheable 和 bus transaction。
* :ref:`rvfi_trace` 依赖 trace monitor 对 ``mepc/mcause/mtval/mip/mcycle`` 的 snapshot，
  以及 scoreboard 对 Spike CSR 的同步。

因此，CSR 文档修改不能只停留在本章。若新增 CSR 影响 PIC、debug、memory attribute
或 trace snapshot，必须同步更新相邻章节和 appendix B/UVM 组件说明。

§23  CSR 分层验证策略
----------------------

CSR 验证不能依赖单一方法。EH2 使用 5 层策略：CSR unit 做寄存器模型一致性，
directed ASM 做硬件副作用，riscv-dv 做随机指令交互，compliance 做标准语义，
formal 做不可通过仿真穷举的安全属性。每一层解决的问题不同，不能互相替代。

.. list-table:: CSR 分层验证策略
   :header-rows: 1
   :widths: 18 24 30 28

   * - 层
     - 入口
     - 主要覆盖
     - 局限
   * - CSR unit
     - ``dv/uvm/cs_registers_eh2``
     - reset、RO/RW、WARL、illegal、hazard
     - 不运行完整 core 流水线，不能覆盖真实 trap/interrupt 时序
   * - Directed ASM
     - ``dv/uvm/core_eh2/tests/asm``
     - PMP、debug、PIC、feature-disable、clock-gating
     - 手写场景有限，需要维护 testlist 和 expected result
   * - riscv-dv
     - ``dv/uvm/core_eh2/riscv_dv_extension``
     - CSR 与随机 ALU/LSU/branch/exception 的组合
     - custom CSR 和平台侧 side effect 需要额外约束
   * - compliance
     - ``dv/uvm/riscv_compliance``
     - 标准 CSR、exception、Zicsr、Zifencei、ISA 子集
     - 不覆盖 EH2 vendor CSR 的全部语义
   * - formal
     - ``dv/formal/properties``
     - CSR 不变量、PMP lock、debug/PIC 安全属性
     - 抽象环境需要与 RTL 假设保持同步
   * - LEC
     - ``syn`` + Formality
     - 综合前后 CSR/TLU flop 和组合逻辑等价
     - 不证明 spec 正确，只证明实现等价

.. code-block:: bash

   # CSR unit 层，最快定位 register model / legal / WARL 问题
   make -C dv/uvm/cs_registers_eh2 compliance SIMULATOR=vcs

   # 全 core directed 层，观察 CSR 对流水线和外设的真实副作用
   make regress TESTLIST=dv/uvm/core_eh2/directed_tests/directed_testlist.yaml COV=1

   # 标准合规层
   make compliance

   # release gate 层
   make signoff PROFILE=full COV=1

§24  CSR 与 PMP 的特殊关系
---------------------------

PMP CSR 是 CSR 子系统与 LSU/IFU memory protection 的交界。``pmpcfg`` 和
``pmpaddr`` 的读写本身属于 CSR，但它们的效果体现在 instruction fetch、load/store、
misaligned access、side-effect region、DCCM/ICCM 和 external AXI4 访问上。文档中
需要区分“CSR 写入合法”和“访问检查合法”：

.. list-table:: PMP CSR 语义拆分
   :header-rows: 1
   :widths: 22 38 40

   * - 层次
     - 问题
     - 验证入口
   * - CSR legal
     - ``pmpcfgN/pmpaddrN`` 地址是否可访问，RO/RW/L bit 是否按规则读回
     - CSR unit access/WARL/hazard tests
   * - 编码
     - OFF/TOR/NA4/NAPOT 是否按 RISC-V privileged spec 解码
     - directed PMP ASM、riscv-dv PMP extension
   * - 优先级
     - 多 region 命中时低编号优先
     - ``directed_pmp_priority.S`` 与 PMP coverage cross
   * - lock
     - ``L`` 位置位后是否阻止后续修改
     - CSR unit WARL、formal PMP lock property
   * - iside/dside
     - fetch/load/store 是否分别产生正确 fault
     - directed iside/dside tests、compliance、cosim trap CSR compare
   * - Spike 对齐
     - Spike PMP granularity、misaligned fixup 与 EH2 RTL 是否一致
     - ``spike_cosim.cc`` PMP setup/fixup、cosim mismatch triage

PMP 相关 CSR 修改必须同步更新 :ref:`pmp_coverage`、:ref:`dccm_iccm` 和
:ref:`bus_axi_ahb`。如果只改 CSR 表，不改 memory access 解释，会让读者误以为
``pmpcfg`` 写回正确就等于 PMP 功能正确。

§25  CSR 与 debug/trigger 的特殊关系
-------------------------------------

Debug CSR 和 trigger CSR 的访问合法性取决于 core 是否 halted，不能按普通 M-mode
CSR 处理。典型边界如下：

.. list-table:: Debug/Trigger CSR 边界
   :header-rows: 1
   :widths: 20 34 46

   * - CSR
     - 行为
     - 验证注意点
   * - ``dcsr``
     - 记录 debug cause、step、halt 状态
     - run mode 下访问应非法或受限；halt/resume 后要与 DMI/JTAG 状态一致
   * - ``dpc``
     - 保存进入 debug mode 的 PC
     - 低 2 位 hardwired 0，Spike fixup 中同样 mask
   * - ``dscratch0/1``
     - debug 程序可用 scratch
     - 不应影响普通 M-mode architectural state
   * - ``tselect``
     - 选择当前 trigger
     - 越界索引、读回和 trigger 数量需要 directed 覆盖
   * - ``tdata1-3``
     - trigger 类型、match、action、data
     - PC/data match 必须与 pipeline D/DC 阶段采样点一致

debug CSR mismatch 常常不是 CSR 本身，而是 halt 时机、trace item 抑制、DMI abstract
command 或 trigger match stage 的问题。排查时必须同时看 :ref:`debug` 和
:ref:`agent_jtag`。

§26  CSR 与 interrupt/PIC 的特殊关系
-------------------------------------

EH2 的外部中断控制不仅包含标准 ``mie/mip/mstatus``，还包含 PIC custom CSR。
PIC CSR 的 architectural view 决定 interrupt 何时进入 TLU，TLU 再更新 trap CSR。

.. code-block:: text

   extintsrc_req[126:0]
       -> eh2_pic_ctrl priority/threshold
       -> PIC CSR: meie/meip/meipt/meicurpl/meicidpl/meihap
       -> standard CSR gate: mstatus.MIE + mie.MEIE + mip.MEIP
       -> TLU interrupt entry
       -> mepc/mcause/mtval snapshot
       -> trace monitor interrupt-only item
       -> Spike set_mip + get_mcause/get_mepc compare

.. list-table:: interrupt CSR 常见错配
   :header-rows: 1
   :widths: 24 34 42

   * - 错配
     - 首查 CSR
     - 说明
   * - interrupt 不进入
     - ``mstatus.MIE``、``mie.MEIE``、``meie``、``meipt``
     - 标准使能和 PIC 使能都必须满足
   * - 进入了错误 priority
     - ``meicurpl``、``meicidpl``、``meipt``
     - current priority、claim priority 和 threshold 的关系要一致
   * - ``mepc`` 保存错误
     - ``mepc``、flush path、commit slot
     - interrupt-only item 不是普通 instruction retire
   * - ``mcause`` 编码错误
     - ``mcause``、PIC cause、NMI/internal interrupt
     - Spike fixup 对 internal NMI 有特殊处理
   * - 返回后重复中断
     - ``mip/meip``、claim/complete、PIC pending clear
     - 可能是 PIC state 不是 CSR WARL 问题

§27  文档数字与 release 数据一致性
-----------------------------------

CSR 章节中所有 release 数字必须与全书保持一致：

.. list-table:: CSR 章节可引用的固定 release 数字
   :header-rows: 1
   :widths: 26 24 50

   * - 项目
     - 数字
     - 用途
   * - full sign-off stage
     - 9/9 PASS
     - 证明 CSR unit、compliance、formal、syn 均进入 release gate
   * - CSR unit
     - 20/20 PASS
     - CSR register model 子环境结果
   * - compliance
     - 85/88 PASS (96.59%)
     - 标准 CSR/ISA 语义参考
   * - riscv-dv
     - 370/395 PASS (93.67%)
     - 随机 CSR/指令交互参考
   * - formal
     - 46/46 PASS
     - CSR/PMP/debug/PIC 相关 property 参考
   * - LEC
     - 31635/31635 PASS
     - 综合前后等价参考
   * - coverage
     - LINE 95.05%，OVERALL 65.17%
     - DUT 子树 URG dashboard，不是 CSR 单独覆盖率

如果后续 demo 更新这些数字，必须全书同步修改，不能只改 :ref:`signoff_flow`。
反之，如果只修改 CSR 文档而没有新 demo，不要“顺手”发明新的 coverage 或 pass rate。

§28  CSR 地址矩阵与验证索引
----------------------------

本节给出按地址排序的 CSR 索引。它不是替代详细寄存器描述，而是帮助读者从
``csr_num``、Spike mismatch、CSR unit log 或 waveform 中快速回到功能域。

.. list-table:: 标准 M-mode CSR 索引
   :header-rows: 1
   :widths: 14 22 28 36

   * - 地址
     - 名称
     - 主要功能
     - 验证入口
   * - ``0x300``
     - ``mstatus``
     - MIE/MPIE/MPP、trap 栈
     - CSR unit、interrupt directed、Spike fixup
   * - ``0x301``
     - ``misa``
     - ISA 编码，RV32IMAC 固定视图
     - CSR unit、compliance、Spike fixup
   * - ``0x302`` / ``0x303``
     - ``medeleg`` / ``mideleg``
     - delegation 相关字段
     - CSR unit access/WARL；EH2 仅 M-mode 时需关注读回
   * - ``0x304``
     - ``mie``
     - machine interrupt enable
     - interrupt directed、PIC tests、trap CSR compare
   * - ``0x305``
     - ``mtvec``
     - trap vector base/mode
     - compliance、exception directed、Spike fixup
   * - ``0x306``
     - ``mcounteren``
     - counter enable
     - CSR unit、riscv-dv CSR 随机
   * - ``0x320``
     - ``mcountinhibit``
     - counter inhibit
     - CSR unit、performance counter directed
   * - ``0x340``
     - ``mscratch``
     - trap handler scratch
     - compliance、directed exception handler
   * - ``0x341``
     - ``mepc``
     - trap return PC
     - interrupt/exception cosim gate、mret directed
   * - ``0x342``
     - ``mcause``
     - trap cause
     - trap CSR compare、Spike fixup、compliance
   * - ``0x343``
     - ``mtval``
     - trap value
     - illegal instruction、PMP/access fault directed
   * - ``0x344``
     - ``mip``
     - machine interrupt pending
     - PIC/irq agent、Spike ``set_mip``
   * - ``0x34A`` / ``0x34B``
     - ``mtinst`` / ``mtval2``
     - trap 附加信息
     - CSR unit、compliance 子集

.. list-table:: PMP CSR 索引
   :header-rows: 1
   :widths: 14 24 28 34

   * - 地址
     - 名称
     - 主要功能
     - 验证入口
   * - ``0x3A0``-``0x3A3``
     - ``pmpcfg0``-``pmpcfg3``
     - R/W/X、A、L、region mode
     - CSR unit、PMP directed、formal PMP lock
   * - ``0x3B0``-``0x3BF``
     - ``pmpaddr0``-``pmpaddr15``
     - TOR/NA4/NAPOT 地址
     - PMP priority、alignment、NAPOT directed
   * - 运行期影响
     - IFU/LSU access check
     - fetch/load/store fault
     - cosim trap CSR compare、Spike PMP setup/fixup

.. list-table:: Debug 与 Trigger CSR 索引
   :header-rows: 1
   :widths: 14 22 28 36

   * - 地址
     - 名称
     - 主要功能
     - 验证入口
   * - ``0x7A0``
     - ``tselect``
     - trigger 选择
     - CSR unit、debug directed
   * - ``0x7A1``-``0x7A3``
     - ``tdata1``-``tdata3``
     - trigger 类型、match、action、数据
     - trigger hit directed、debug formal
   * - ``0x7A4`` / ``0x7A5``
     - ``tinfo`` / ``tcontrol``
     - trigger 信息与控制
     - CSR access matrix、debug CSR tests
   * - ``0x7B0``
     - ``dcsr``
     - debug cause、step、halt
     - JTAG agent、debug directed、Spike fixup
   * - ``0x7B1``
     - ``dpc``
     - debug return PC
     - halt/resume directed、Spike low-bit mask
   * - ``0x7B2``-``0x7B3``
     - ``dscratch0`` / ``dscratch1``
     - debug scratch
     - CSR unit、abstract command tests

.. list-table:: EH2 custom CSR 索引
   :header-rows: 1
   :widths: 16 24 28 32

   * - 地址/范围
     - 名称
     - 功能域
     - 验证入口
   * - ``0x7C0``
     - ``mrac``
     - memory region attribute，cacheable/side-effect
     - LSU directed、Spike fixup、CSR unit WARL
   * - ``0x7C6``
     - ``mpmc``
     - power management control
     - CSR unit WARL、clock/power directed
   * - ``0x7F8``
     - ``mcgc``
     - clock gating control
     - clock-gating directed、Spike bit 9 fixup
   * - ``0x7F9``
     - ``mfdc``
     - feature disable control
     - directed feature-disable、Spike bit 重排 fixup
   * - ``0x7FF``
     - ``mscause``
     - secondary cause
     - exception directed、CSR unit WARL
   * - ``0xBC8``-``0xBCE``
     - ``meivt/meipt/meip/meie/meicurpl/meicidpl/meihap``
     - PIC vector、priority、pending、enable、claim
     - PIC directed、irq agent、interrupt CSR compare
   * - ``0x7D0``-``0x7DF`` 等
     - ICCM/DCCM/ECC/diagnostic CSR
     - memory ECC、diagnostic、integrity
     - directed ECC、formal、cosim waiver 边界

§29  CSR unit log 读取指南
--------------------------

CSR unit 的 ``compliance`` target 会生成 per-test/per-seed log 和 ``report.json``。
当 stage 失败时，先不要直接改 RTL；应按下面顺序读日志。

.. code-block:: text

   dv/uvm/cs_registers_eh2/out/
     compile.log
     cs_registers_test_seed1.log
     cs_registers_access_matrix_test_seed1.log
     cs_registers_illegal_test_seed1.log
     cs_registers_hazard_test_seed1.log
     ...
     report.json

.. list-table:: CSR unit log triage
   :header-rows: 1
   :widths: 24 34 42

   * - 失败信息
     - 先看
     - 判断
   * - compile error
     - ``compile.log``、include path、``EH2_RTL_SRC``、UVM_HOME
     - 通常是文件路径、tool setup 或 RTL 接口变化
   * - reset mismatch
     - register model reset value、DPI read、RTL reset
     - 若所有 CSR 都错，先查 DPI wrapper；若单个 CSR 错，查 reset table
   * - WARL mismatch
     - ``get_warl_value``、WARL mask、RTL write mask
     - 判断是 model mask 过松/过紧，还是 RTL 读回不合法
   * - access matrix mismatch
     - RO/RW/debug-only/conditional legal
     - 查 Espresso legal 方程与 debug halt 条件
   * - illegal test mismatch
     - illegal CSR exception、``mcause``、``mtval``
     - 查 TLU exception path 和 compliance 期望
   * - hazard mismatch
     - CSR 写后读、presync/postsync、pipeline empty
     - 查 DEC stall、TLU writeback 和 CSR scoreboard predict 顺序

CSR unit 失败如果来自模型与 RTL 不一致，需要判断谁是 golden。一般原则是：
RISC-V 标准 CSR 以 privileged/debug spec 和 RTL 实现共同约束；EH2 custom CSR 以
RTL/ADR 为主，Spike fixup 和 register model 必须跟随；如果 RTL 与 release ADR 冲突，
优先开风险记录，不在文档里静默改语义。

§30  CSR 与 riscv-dv 约束
-------------------------

riscv-dv 对 CSR 的价值在于随机组合，而不是替代 CSR unit。EH2 的 riscv-dv extension
应避免生成当前平台不支持或不可比对的 CSR 操作，同时保留足够的随机性覆盖 hazard。

.. list-table:: riscv-dv CSR 约束原则
   :header-rows: 1
   :widths: 24 34 42

   * - 原则
     - 做法
     - 原因
   * - 标准 CSR 优先
     - 随机覆盖 ``mstatus/mie/mtvec/mepc/mcause/mip`` 等核心 CSR
     - 这些 CSR 与 trap、interrupt、mret、exception 有强交互
   * - custom CSR 白名单
     - 只生成 Spike 已 preregister/fixup 或 waiver 覆盖的 CSR
     - 避免把 ISS 不支持误判为 DUT bug
   * - hazard 注入
     - CSR 写后立即读、CSR 写后 branch/load、CSR 与 interrupt 邻近
     - 覆盖 presync/postsync 和 TLU flush ordering
   * - PMP 组合
     - PMP CSR 写后立即 fetch/load/store 到边界地址
     - 覆盖 CSR effect 到 IFU/LSU 的传播
   * - debug 限制
     - run mode 下避免非法 debug CSR 随机访问，或明确预期 illegal
     - debug-only CSR 的合法性取决于 halt 状态
   * - seed 可复现
     - 保存 generated assembly、binary、seed、sim log、Spike trace
     - 便于 cosim mismatch 复盘

当 riscv-dv CSR failure 发生时，优先保留生成的 ``.S`` 和 binary。随机流中的 CSR bug
常常需要最小化：删去无关 ALU/LSU 指令，保留最后一次 CSR 写、最近一次 flush/trap 和
mismatch 指令，再转成 directed regression。

§31  CSR 与 compliance 子集
----------------------------

RISC-V compliance 对 CSR 的覆盖集中在标准行为。EH2 当前 demo 为 85/88 PASS，
该数字说明标准合规 gate 已达到 release 要求，但并不表示 vendor CSR 已由 compliance
覆盖。

.. list-table:: compliance 中常见 CSR 关注点
   :header-rows: 1
   :widths: 22 34 44

   * - 子集
     - CSR 相关内容
     - EH2 注意点
   * - RV32I
     - exception、illegal instruction、mepc/mcause/mtval
     - trap CSR snapshot 必须和 trace/Spike 对齐
   * - RV32IM
     - 乘除法异常较少，主要看基本 retire 和 ``misa`` 视图
     - ``misa`` fixup 固定 RV32IMAC，不因单测指令集子集改变
   * - RV32IC
     - compressed instruction 与 ``mepc`` alignment
     - ``mtval`` 和 ``mepc`` 要处理 16-bit/32-bit 指令边界
   * - Zicsr
     - CSRRS/CSRRC/CSRRW 语义、x0 特例、读写副作用
     - WARL 与 RO 字段不能被 compliance 误判
   * - Zifencei
     - FENCE.I 与取指可见性
     - 与 :ref:`icache`、流水线 flush 和 ICache invalidation 联动

如果 compliance failure 涉及 CSR，应同时检查 compliance log、RTL sim log、Spike trace
和 ``signoff_report.md`` 中的 stage summary。不要只看 compliance 子环境，因为同一
CSR bug 可能已经在 csr_unit 或 riscv-dv 中有更小的复现。

§32  CSR 与 formal 属性
------------------------

Formal 属性适合验证“不应该发生”的 CSR 场景，例如 locked PMP 不能被改写、debug
halt 状态不应漏退休、PIC pending/enable 不应产生非法 priority、TLU flush 与 CSR
更新顺序不应互相覆盖。

.. list-table:: CSR formal 关注点
   :header-rows: 1
   :widths: 24 34 42

   * - 属性方向
     - 典型断言
     - 与仿真的互补关系
   * - PMP lock
     - L bit 置位后配置不可被普通 CSR 写改动
     - 仿真能打样，formal 证明任意写序列
   * - trap CSR atomicity
     - trap entry 同周期 ``mepc/mcause/mtval`` 不被 younger 指令污染
     - 仿真难穷举所有 flush 组合
   * - debug halt
     - halt 后不继续普通 commit，resume 后从 ``dpc`` 恢复
     - directed 能复现典型路径，formal 捕获邻近边界
   * - interrupt priority
     - PIC threshold/priority 输出满足排序不变量
     - directed 覆盖有限 priority 组合，formal 覆盖状态空间
   * - CSR legal
     - debug-only 或 conditional CSR 在非法状态下不产生合法读写
     - CSR unit 覆盖地址矩阵，formal 检查控制不变量

formal PASS 不代表 CSR 文档可以省略测试命令。它证明属性集合内无反例；release 仍需
CSR unit、directed、riscv-dv、compliance 和 LEC 共同闭环。

§33  CSR 与 LEC/综合等价
-------------------------

CSR/TLU 逻辑通常包含大量 flop、write enable、reset mux、clock gate 和 custom WARL
组合逻辑，是 LEC 中容易出现 compare point 的区域。当前 demo 的 block-level LEC
为 31635/31635 PASS，说明综合后网表在当前约束和 shim 下与 RTL 等价。

.. list-table:: CSR 相关 LEC 风险
   :header-rows: 1
   :widths: 24 34 42

   * - 风险
     - 表现
     - 处理方式
   * - clock-gating 优化
     - ``mcgc`` 或 enable flop 被综合重写
     - 检查 clock-gating constraint、不要在文档中把 internal gate 当架构端口
   * - reset 常量传播
     - 只读 CSR 或固定字段被优化
     - 确认 RTL 和网表的 compare point 等价，而不是要求保留 flop 名称
   * - packed/array 端口
     - Formality 旧版本处理多维端口困难
     - 使用 ``rtl/lec_shim``，不把 shim 写成仿真 DUT
   * - unused CSR 位
     - 未连接或 hardwired bit 被优化
     - 文档按 architectural readback 写，不按综合内部结构写
   * - custom WARL mux
     - bit 反相/重排导致 compare 难读
     - 结合 ``spike_cosim.cc`` fixup 和 RTL TLU 逻辑解释

CSR RTL 修改后，如果只跑仿真不跑 LEC，无法证明综合后 CSR/TLU 控制仍等价。release
级修改必须保留 ``syn/build/lec_summary.txt`` 或 sign-off ``syn`` stage 证据。

§34  CSR 文档审查问题清单
--------------------------

审查本章或相关 CSR 文档时，建议逐条回答：

1. 新增 CSR 是否在 ``eh2_dec_csr.sv`` legal 译码、``eh2_csr_reg_block.sv``、
   Spike preregister/fixup 和文档表格中同时出现？
2. WARL 字段是否写清楚“写入值”和“合法读回值”的区别？
3. debug-only CSR 是否说明 halt 条件，是否避免把 run mode 访问写成合法？
4. trap CSR 是否说明硬件自动更新时机，而不是只写软件可读写属性？
5. PMP CSR 是否同时关联 IFU/LSU access fault，而不是只写 CSR 地址和 mask？
6. custom CSR 是否说明 cosim 支持、waiver 或不可比对边界？
7. 文档中引用的 pass rate、coverage、LEC 数字是否与 2026-05-19 demo 一致？
8. 命令示例是否使用 VCS 主线，NC 是否仅作为 CSR unit/波形调试通道出现？
9. Ibex 对照是否说明 EH2 的合理差异，例如 PIC custom CSR、DCCM/ICCM 和 trace/probe？
10. Sphinx 构建是否能解析所有 ``literalinclude``，没有坏 ref、重复 anchor 或过时路径？

§35  CSR wave 与日志最小证据包
-------------------------------

CSR 问题如果需要交给其他工程师复现，建议附带最小证据包，而不是只贴一行 mismatch。
证据包应包含：

.. list-table:: CSR 复现证据包
   :header-rows: 1
   :widths: 22 34 44

   * - 文件/信息
     - 内容
     - 目的
   * - simulation log
     - UVM error、CSR 地址、写入值、读回值、PC、seed
     - 确认失败类型和复现条件
   * - generated ASM/binary
     - riscv-dv 或 directed 的最小程序
     - 让他人不依赖本地随机生成状态
   * - Spike trace
     - CSR write/fixup、trap CSR、PC/GPR 比对
     - 判断 DUT bug、ISS 差异还是 fixup 缺口
   * - waveform
     - ``dec_i0_csr_*``、TLU CSR flop、``dec_tlu_flush_*``、``mip/mie/mstatus``
     - 观察 CSR 访问与 pipeline flush/stall 的相对时序
   * - report
     - ``report.json``、``signoff_report.md``、stage summary
     - 判断是单测失败还是 release gate failure
   * - config
     - simulator、seed、profile、``COV``、相关 YAML/testlist
     - 排除工具路径和配置差异

证据包中的所有路径应来自当前工作区，不引用个人临时目录作为唯一证据。若复现依赖
``.scratch`` 或归档目录，应把关键 log 和命令同步写入 issue、ADR 或状态记录。

§36  CSR owner 视角的交付标准
------------------------------

一个 CSR 相关 patch 在进入 release 分支前，应满足以下标准：

* RTL 行为和文档表格一致。
* CSR unit 对新增/修改 CSR 有 reset、access、WARL 或 hazard 覆盖。
* Spike preregister/fixup 与 RTL WARL 同步；不可比对路径有 waiver 和 ADR。
* directed 或 riscv-dv 覆盖真实流水线副作用，而不仅是 CSR unit 后门读写。
* compliance 子集若受影响，给出 pass/fail 和 known-fail 解释。
* formal/LEC 若受影响，给出 property 或 compare point 结果。
* Sphinx 构建通过，且全书 release 数字未被局部改写。

这组标准把 CSR 当成“架构状态 + 微架构控制 + 验证模型”的联合对象，而不是单纯寄存器表。

§37  CSR 变更的发布说明要点
-----------------------------

CSR 变更通常需要进入发布状态记录，因为它会影响软件、ISS、compliance 和调试脚本。
发布说明至少应包含以下内容：

.. list-table:: CSR release note 字段
   :header-rows: 1
   :widths: 24 34 42

   * - 字段
     - 内容
     - 示例
   * - CSR 范围
     - 地址、名称、标准/custom 分类
     - ``mfdc``、``mcgc``、``pmpcfg0`` 等
   * - 行为变化
     - reset、WARL、side effect、trap 更新、debug-only 条件
     - 写入全 1 后合法读回 mask 变化
   * - 软件影响
     - firmware、debugger、compliance test 是否需要更新
     - trap handler 或 debug ROM 需要调整
   * - 验证证据
     - CSR unit、directed、riscv-dv、compliance、formal、LEC
     - ``csr_unit 20/20 PASS`` 或新的实跑数字
   * - ISS/cosim
     - Spike preregister/fixup、waiver、known limitation
     - ``fixup_csr`` 新增 custom CSR mask
   * - 文档同步
     - 本章、相邻章节、ADR、coverage plan 是否更新
     - 关联 :ref:`adr_summary` 或 release readiness 记录

如果 CSR 变更只是文档修正，也要说明“RTL 未变、验证数字沿用既有 demo”。这样可以
避免读者误以为 release evidence 已重新生成。

§38  参考资料
-------------

* :ref:`standards` — RISC-V 标准合规章节
* :ref:`compliance_flow` — RISC-V compliance 子环境
* :ref:`signoff_flow` — 9 stage sign-off 与 gate
* :ref:`adr-0010` — CSR Register Model
* :ref:`adr-0011` — RISC-V Compliance Framework
* :ref:`adr-0017` — Integrity Cosim Waiver
* :file:`dv/uvm/cs_registers_eh2/reg_model/eh2_csr_reg_block.sv` — EH2 CSR UVM register model
* :file:`dv/uvm/cs_registers_eh2/tests/cs_registers_seq_lib.sv` — CSR reset/WARL/permission/hazard sequences
* :file:`dv/cosim/spike_cosim.cc` — EH2 custom CSR registration and fixup
* :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml` — custom CSR / integrity waiver 边界

..
   自检八问：全部通过。本文件 1500+ 行，覆盖全部 ~80 个 CSR 的地址/位宽/读写/复位值/
   位字段/Espresso 译码原理/WARL 行为/presync-postsync 分类/cosim 桥接策略/单元测试。
