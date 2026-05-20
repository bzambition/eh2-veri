.. _appendix_b_uvm_riscv_dv_ext:
.. _appendix_b_uvm/riscv_dv_ext:

riscv-dv 扩展 — 详细参考
================================================================================

:status: draft
:source: dv/uvm/core_eh2/riscv_dv_extension/
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  文件组职责
--------------------------------------------------------------------------------

``dv/uvm/core_eh2/riscv_dv_extension/`` 是 EH2 对本地
``vendor/google_riscv-dv`` 的适配层。它不实现 DUT，也不实现 UVM agent；
它把 riscv-dv 需要的 core setting、汇编程序生成器、定向指令流、
debug ROM 覆盖、trace CSV 转换、链接地址和 testlist 统一放在一个目录。

从源文件数量看，该目录当前包含 13 个文件：

.. code-block:: text

   cov_testlist.yaml
   csr_description.yaml
   ddm_link.ld
   eh2_asm_program_gen.sv
   eh2_debug_triggers_overrides.sv
   eh2_directed_instr_lib.sv
   eh2_log_to_trace_csv.py
   ml_testlist.yaml
   riscvOVPsim.ic
   riscv_core_setting.sv
   riscv_core_setting.tpl.sv
   testlist.yaml
   user_extension.svh

**逐段解释** ：

* SV 文件定义 riscv-dv 生成侧的 EH2 行为：``riscv_core_setting.sv`` 给出
  ISA、CSR、interrupt 和 exception 能力；``eh2_asm_program_gen.sv`` 覆盖程序
  起始、结束、ECALL、NMI 和 debug ROM 片段；``eh2_directed_instr_lib.sv``
  提供 EH2 定向 stream；``eh2_debug_triggers_overrides.sv`` 专门覆盖硬件
  trigger debug ROM。
* YAML 文件定义测试入口和 CSR 描述：``testlist.yaml`` 是常规回归测试清单，
  ``ml_testlist.yaml`` 是参数密集的 ML 风格清单，``cov_testlist.yaml`` 是
  instruction functional coverage 入口，``csr_description.yaml`` 是 CSR 字段表。
* ``eh2_log_to_trace_csv.py`` 把 EH2 仿真日志转换成 riscv-dv coverage/compare
  期望的 trace CSV；``ddm_link.ld`` 和 ``riscvOVPsim.ic`` 分别给 debug module
  离散地址空间和 OVPsim ISA/CSR 行为提供配置。

数据流可以概括为：

.. code-block:: text

   YAML testlist
        |
        v
   riscv-dv generator
        |-- includes user_extension.svh
        |-- reads riscv_core_setting.sv / csr_description.yaml
        |-- may instantiate eh2_* directed stream classes
        v
   generated assembly / ELF
        |
        v
   core_eh2 RTL test
        |
        v
   EH2 simulation log ---- eh2_log_to_trace_csv.py ----> trace CSV

**接口关系** ：

* **上游输入** ：``run.py``/回归脚本从 testlist 选择 ``gen_test``、
  ``gen_opts``、``rtl_test``、``sim_opts`` 和 ``iterations``。
* **下游输出** ：riscv-dv 生成 assembly/ELF；RTL 仿真产生 log；
  ``eh2_log_to_trace_csv.py`` 生成 CSV trace。
* **共享状态** ：目录内 SV 文件依赖 riscv-dv 定义的 ``riscv_instr``、
  ``riscv_asm_program_gen``、``riscv_debug_rom_gen``、``privileged_reg_t``、
  ``riscv_instr_group_t`` 等类型；YAML 中的 stream 名称必须能在
  ``user_extension.svh`` 包含的类中解析。

§2  Core setting
--------------------------------------------------------------------------------

§2.1  ``riscv_core_setting.sv`` — 固化当前 EH2 生成能力
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该文件向 riscv-dv 描述当前 EH2 目标的 XLEN、hart 数、特权级、
ISA 扩展、CSR、interrupt 和 exception 列表。riscv-dv 根据这些数组和参数
决定哪些随机指令、CSR 访问和 coverage 分类可以生成。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L7-L48``）：

.. code-block:: systemverilog

   parameter int XLEN = 32;
   parameter int NUM_FLOAT_GPR = 0;
   parameter int NUM_GPR = 32;
   parameter int NUM_VEC_GPR = 0;

   parameter int VECTOR_EXTENSION_ENABLE = 0;
   parameter int VLEN = 512;
   parameter int ELEN = 32;
   parameter int SLEN = 32;
   parameter int VELEN = 2;
   parameter int SELEN = 8;
   parameter int MAX_LMUL = 8;

   parameter int NUM_HARTS = 1;
   parameter satp_mode_t SATP_MODE = BARE;

   privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE};

   riscv_instr_name_t unsupported_instr[] = {};

   bit support_unaligned_load_store = 1'b1;

   // EH2 supports RV32IMAC plus configuration-selected bitmanip groups.
   riscv_instr_group_t supported_isa[$] = {
     RV32I,
     RV32M,
     RV32A,
     RV32C
     ,RV32ZBA

**逐段解释** ：

* 第 7-L10 行：生成目标是 32-bit integer core；没有 floating-point GPR，也没有
  vector GPR。``NUM_GPR=32`` 使随机寄存器选择覆盖 x0-x31。
* 第 12-L18 行：vector 相关参数虽然保留给 riscv-dv 数据结构，但
  ``VECTOR_EXTENSION_ENABLE=0`` 表示当前生成目标不启用 vector 指令。
* 第 20-L23 行：``NUM_HARTS=1`` 和 ``SATP_MODE=BARE`` 把静态 setting 固化为
  单 hart、machine/bare memory model；``supported_privileged_mode`` 只列出
  ``MACHINE_MODE``。
* 第 25-L27 行：``unsupported_instr`` 为空，表示该文件不通过显式黑名单移除
  指令；unaligned load/store 通过 ``support_unaligned_load_store=1'b1`` 开启。
* 第 30 行起：``supported_isa`` 是 generator 的 ISA 白名单。这里列出 RV32I、
  RV32M、RV32A、RV32C 和 Zba/Zbb/Zbc/Zbs 组；具体 stream 是否生成某条
  bitmanip 指令，还受 ``eh2_bitmanip_stream`` 中列表约束。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L35-L48``）：

.. code-block:: systemverilog

     ,RV32ZBA
     ,RV32ZBB
     ,RV32ZBC
     ,RV32ZBS
   };

   mtvec_mode_t supported_interrupt_mode[$] = {DIRECT, VECTORED};
   int max_interrupt_vector_num = 32;

   bit support_pmp = 0;
   bit support_epmp = 0;
   bit support_debug_mode = 1;
   bit support_umode_trap = 0;
   bit support_sfence = 0;

**逐段解释** ：

* 第 35-L39 行：Zba/Zbb/Zbc/Zbs 在 core setting 中被声明为支持组。这个声明只
  影响 riscv-dv 的合法 ISA 集合，不等同于所有相关 opcode 都会被定向 stream
  选中。
* 第 41-L42 行：trap vector 支持 ``DIRECT`` 和 ``VECTORED`` 两种 ``mtvec``
  mode，向 coverage/CSR 生成侧暴露最多 32 个 interrupt vector。
* 第 44-L48 行：静态 setting 中关闭 PMP/ePMP 和 U-mode trap/sfence，打开
  debug mode。PMP/ePMP 专项 testlist 仍会通过 ``gen_opts`` 打开 PMP 相关生成
  选项；这与静态 setting 的默认值是不同层级的输入。

**接口关系** ：

* **被调用** ：riscv-dv 生成器读取该文件作为 target setting。
* **调用** ：该文件本身不调用函数；它提供参数、数组和常量列表。
* **共享状态** ：``supported_isa``、``implemented_csr``、``custom_csr``、
  ``implemented_interrupt``、``implemented_exception`` 被 generator 和 coverage
  流程消费。

§2.2  ``implemented_csr`` 与 ``custom_csr`` — CSR 生成白名单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：这两组数组把 riscv-dv 可以识别的标准 CSR 和只能用 12-bit 数值描述的
EH2 自定义 CSR 分开。标准 CSR 使用 ``privileged_reg_t`` 枚举；EH2 CSR 使用
``bit [11:0]`` 地址。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L61-L98``）：

.. code-block:: systemverilog

   const privileged_reg_t implemented_csr[] = {
     MVENDORID,
     MARCHID,
     MIMPID,
     MHARTID,
     MSTATUS,
     MISA,
     MIE,
     MTVEC,
     MCOUNTEREN,
     MSCRATCH,
     MEPC,
     MCAUSE,
     MTVAL,
     MIP,
     MCYCLE,
     MINSTRET,
     MCYCLEH,
     MINSTRETH,
     MCOUNTINHIBIT,
     MHPMCOUNTER3,
     MHPMCOUNTER4,
     MHPMCOUNTER5,
     MHPMCOUNTER6,
     MHPMCOUNTER3H,
     MHPMCOUNTER4H,
     MHPMCOUNTER5H,

**逐段解释** ：

* 第 61-L79 行：数组前半段覆盖 ID、status、trap、counter 基础 CSR。它们都是
  riscv-dv 已知枚举，因此使用符号名而不是数值地址。
* 第 80-L92 行：``MCOUNTINHIBIT``、``MHPMCOUNTER3`` 到 ``MHPMEVENT6`` 进入
  生成白名单，允许 counter/hpm 相关 CSR 在 CSR test 或随机 CSR 写中出现。
* 第 93-L97 行：debug/trigger 相关 CSR ``DCSR``、``DPC``、``TSELECT``、
  ``TDATA1``、``TDATA2`` 也列入标准 CSR 表，供 debug stream 和 trigger 覆盖使用。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L100-L132``）：

.. code-block:: systemverilog

   // EH2 custom CSRs are generated numerically because upstream riscv-dv does not
   // define symbolic names for the VeeR/EH2 machine CSRs.
   const bit [11:0] custom_csr[] = {
     12'h7FF,  // mscause
     12'h7C0,  // mrac
     12'h7C9,  // mfdc
     12'h7F8,  // mcgc
     12'h7C6,  // mpmc
     12'h7C2,  // mcpc
     12'h7C4,  // dmst
     12'h7CE,  // mfdht
     12'h7CF,  // mfdhs
     12'hFC4,  // mhartnum
     12'h7FC,  // mhartstart
     12'h7FE,  // mnmipdel
     12'h7D2,  // mitcnt0
     12'h7D5,  // mitcnt1
     12'h7D3,  // mitb0
     12'h7D6,  // mitb1
     12'h7D4,  // mitctl0
     12'h7D7,  // mitctl1
     12'hBC0,  // mdeau
     12'hFC0,  // mdseac
     12'h7F0,  // micect
     12'h7F1,  // miccmect

**逐段解释** ：

* 第 100-L102 行：注释说明使用数值地址的原因是 upstream riscv-dv 没有定义
  VeeR/EH2 machine CSR 符号名。文档不能把这些地址改写为不存在的枚举。
* 第 103-L113 行：列表前段覆盖 ``mscause``、``mrac``、``mfdc``、``mcgc``、
  ``mpmc``、``mcpc``、``dmst``、``mfdht``、``mfdhs``、``mhartnum``、
  ``mhartstart`` 等 EH2 CSR。
* 第 114-L124 行：内部 timer、memory/error control 和 ECC threshold 类 CSR
  以地址形式进入 ``custom_csr``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L123-L132``）：

.. code-block:: systemverilog

     12'h7F0,  // micect
     12'h7F1,  // miccmect
     12'h7F2,  // mdccmect
     12'hBC8,  // meivt
     12'hFC8,  // meihap
     12'hBC9,  // meipt
     12'hBCA,  // meicpct
     12'hBCC,  // meicurpl
     12'hBCB   // meicidpl
   };

**逐段解释** ：

* 第 123-L125 行：``micect``、``miccmect``、``mdccmect`` 对应 ICache、ICCM 和
  DCCM ECC error count threshold 类 CSR。
* 第 126-L131 行：``meivt``、``meihap``、``meipt``、``meicpct``、
  ``meicurpl``、``meicidpl`` 是 PIC/external interrupt 相关 CSR，后续
  ``eh2_pic_int_stream`` 会直接使用其中多个地址。

**接口关系** ：

* **被调用** ：CSR 随机生成、CSR coverage 和 EH2 定向 CSR stream 读取这些列表。
* **调用** ：无函数调用。
* **共享状态** ：``custom_csr`` 的地址必须与 ``csr_description.yaml`` 和
  ``eh2_directed_instr_lib.sv`` 中的 CSR 地址保持一致。

§2.3  interrupt 与 exception 列表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：这两个数组给功能覆盖和异常/中断生成侧提供 EH2 当前建模的 cause 集。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L134-L152``）：

.. code-block:: systemverilog

   //-----------------------------------------------------------------------------
   // Functional coverage interrupt/exception settings
   //-----------------------------------------------------------------------------
   const interrupt_cause_t implemented_interrupt[] = {
     M_SOFTWARE_INTR,
     M_TIMER_INTR,
     M_EXTERNAL_INTR
   };

   const exception_cause_t implemented_exception[] = {
     INSTRUCTION_ACCESS_FAULT,
     ILLEGAL_INSTRUCTION,
     BREAKPOINT,
     LOAD_ADDRESS_MISALIGNED,
     LOAD_ACCESS_FAULT,
     STORE_AMO_ADDRESS_MISALIGNED,
     STORE_AMO_ACCESS_FAULT,
     ECALL_MMODE
   };

**逐段解释** ：

* 第 137-L141 行：interrupt 列表只包含 machine software、machine timer 和
  machine external 三类 cause。该列表不包含 supervisor/user cause。
* 第 143-L152 行：exception 列表覆盖 instruction access fault、illegal
  instruction、breakpoint、load/store misaligned、load/store access fault 和
  machine-mode ECALL。``eh2_exception_stream`` 生成 ECALL 与 misaligned load
  时，与这里的 cause 分类相对应。

**接口关系** ：

* **被调用** ：riscv-dv coverage 和 exception/interrupt 生成配置读取这些数组。
* **调用** ：无。
* **共享状态** ：与 ``csr_description.yaml`` 中 ``mcause``/``mip``/``mie`` 字段
  和 ``testlist.yaml`` 中 interrupt/exception 项共同定义生成边界。

§2.4  ``riscv_core_setting.tpl.sv`` — 可配置模板
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：模板文件把静态 setting 中的 hart 数、atomic 和 bitmanip 组改成
模板变量，使脚本可以从 EH2 配置生成 ``riscv_core_setting.sv``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv:L20-L49``）：

.. code-block:: systemverilog

   parameter int NUM_HARTS = {{ NUM_THREADS }};
   parameter satp_mode_t SATP_MODE = BARE;

   privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE};

   riscv_instr_name_t unsupported_instr[] = {};

   bit support_unaligned_load_store = 1'b1;

   // EH2 supports RV32IMAC plus configuration-selected bitmanip groups.
   riscv_instr_group_t supported_isa[$] = {
     RV32I,
     RV32M,
   //% if ATOMIC_ENABLE
     RV32A,
   //% endif
     RV32C
   //% if BITMANIP_ZBA
     ,RV32ZBA
   //% endif
   //% if BITMANIP_ZBB
     ,RV32ZBB
   //% endif
   //% if BITMANIP_ZBC
     ,RV32ZBC
   //% endif
   //% if BITMANIP_ZBS

**逐段解释** ：

* 第 20 行：``NUM_HARTS`` 不是固定值，而是模板变量 ``{{ NUM_THREADS }}``。
  生成脚本可以把 EH2 配置中的 thread 数传入 riscv-dv target setting。
* 第 33-L35 行：``RV32A`` 只在 ``ATOMIC_ENABLE`` 条件为真时写入
  ``supported_isa``。这与 atomic cosim 相关测试的开关解耦。
* 第 37-L48 行：Zba/Zbb/Zbc/Zbs 都受独立模板条件控制。模板使同一个 target
  描述能随 EH2 YAML 配置打开或关闭 bitmanip 子集。

**接口关系** ：

* **被调用** ：Makefile/脚本生成 ``riscv_core_setting.sv`` 时读取该模板。
* **调用** ：模板本身不调用 SV 函数。
* **共享状态** ：``NUM_THREADS``、``ATOMIC_ENABLE`` 和 ``BITMANIP_*`` 的值来自
  上游配置生成流程；输出文件由 riscv-dv generator 读取。

§3  riscv-dv user extension hook
--------------------------------------------------------------------------------

§3.1  ``user_extension.svh`` — 注册 EH2 扩展类
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 include 文件是 riscv-dv target extension 的入口。它只包含两个
EH2 SV 文件，分别提供 assembly program generator 覆盖和 directed instruction
stream 类。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/user_extension.svh:L1-L8``）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 riscv-dv User Extension Hook
   //
   // This file is included by riscv-dv to register EH2-specific
   // class overrides and directed instruction streams.

   `include "eh2_asm_program_gen.sv"
   `include "eh2_directed_instr_lib.sv"

**逐段解释** ：

* 第 1-L5 行：注释说明该文件由 riscv-dv include，用来注册 EH2-specific class
  overrides 和 directed instruction streams。
* 第 7 行：``eh2_asm_program_gen.sv`` 提供 ``eh2_asm_program_gen``，覆盖 program
  header、ECALL handler、mailbox 结束、NMI handler 和 debug ROM。
* 第 8 行：``eh2_directed_instr_lib.sv`` 提供 ``eh2_csr_access_stream``、
  ``eh2_bitmanip_stream``、``eh2_pic_int_stream`` 等 stream，供 testlist 的
  ``+directed_instr_0=...`` 选项引用。

**接口关系** ：

* **被调用** ：riscv-dv target build/include 机制读取该文件。
* **调用** ：使用 SystemVerilog preprocessor ``include`` 引入两个实现文件。
* **共享状态** ：YAML 中的 ``directed_instr`` 名称需要在这两个 include 文件
  最终可见的类中定义。

§4  ``eh2_asm_program_gen.sv``
--------------------------------------------------------------------------------

§4.1  ``eh2_asm_program_gen`` — EH2 汇编程序生成器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该类继承 ``riscv_asm_program_gen``，保留 riscv-dv 的主生成流程，
只覆盖 EH2 需要改变的 header、CSR 默认写集合、ECALL handler、mailbox 结束、
NMI 和 debug ROM 片段。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L13-L44``）：

.. code-block:: systemverilog

   class eh2_asm_program_gen extends riscv_asm_program_gen;

     `uvm_object_utils(eh2_asm_program_gen)

     function new(string name = "");
       super.new(name);
     endfunction

     // Override program generation to set EH2-specific defaults
     virtual function void gen_program();
       // Exclude CSRs that cause co-sim mismatches or are read-only
       default_include_csr_write.delete();
       // Standard M-mode CSRs
       default_include_csr_write.push_back(MSTATUS);
       default_include_csr_write.push_back(MIE);
       default_include_csr_write.push_back(MTVEC);
       default_include_csr_write.push_back(MSCRATCH);
       default_include_csr_write.push_back(MEPC);
       default_include_csr_write.push_back(MCAUSE);
       default_include_csr_write.push_back(MTVAL);
       default_include_csr_write.push_back(MCOUNTINHIBIT);
       default_include_csr_write.push_back(MEDELEG);
       default_include_csr_write.push_back(MIDELEG);
       default_include_csr_write.push_back(MIP);
       default_include_csr_write.push_back(PMPADDR0);

**逐段解释** ：

* 第 13-L19 行：类直接继承 riscv-dv 的 ``riscv_asm_program_gen``，通过
  ``uvm_object_utils`` 注册 factory，构造函数只转调 ``super.new``。
* 第 22-L24 行：``gen_program()`` 开始时清空父类默认 CSR 写集合。这样后续只把
  EH2 允许默认写入的 CSR 加回列表。
* 第 26-L41 行：函数显式加入 M-mode CSR、delegate CSR、``MIP`` 和 PMPADDR/PMPCFG
  条目。这里列入 PMP CSR 是 generator 默认写集合的一部分，不代表
  ``riscv_core_setting.sv`` 的 ``support_pmp`` 默认值被改成 1。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L37-L44``）：

.. code-block:: systemverilog

       default_include_csr_write.push_back(PMPADDR0);
       default_include_csr_write.push_back(PMPADDR1);
       default_include_csr_write.push_back(PMPADDR2);
       default_include_csr_write.push_back(PMPADDR3);
       default_include_csr_write.push_back(PMPCFG0);

       super.gen_program();
     endfunction

**逐段解释** ：

* 第 37-L41 行：PMPADDR0-3 和 PMPCFG0 被加入默认 CSR 写列表，覆盖父类
  ``default_include_csr_write`` 被清空后的集合。
* 第 43 行：函数最后调用 ``super.gen_program()``，说明 EH2 只调整前置配置，
  实际 program 生成仍由 riscv-dv 父类流程执行。

**接口关系** ：

* **被调用** ：riscv-dv 生成 assembly program 时实例化该类并调用
  ``gen_program()``。
* **调用** ：调用 ``default_include_csr_write.delete/push_back`` 和
  ``super.gen_program()``。
* **共享状态** ：读写父类成员 ``default_include_csr_write``。

§4.2  ``gen_program_header()`` — EH2 启动入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该函数生成 EH2 程序头，放置 ``.text``、``_start``、stack pointer 和
``mstatus`` 初始写入序列。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L46-L60``）：

.. code-block:: systemverilog

     // Override program header for EH2 memory map
     virtual function void gen_program_header();
       // EH2 boots from 0x8000_0000
       // Section and label setup
       instr_stream.push_back(".section .text");
       instr_stream.push_back(".global _start");
       instr_stream.push_back("_start:");

       // Initialize stack pointer to the external RAM window used by the EH2 DV linker.
       instr_stream.push_back($sformatf("li sp, 0x%08x", 32'h8200_0000));

       // Set mstatus.MIE = 1
       instr_stream.push_back("li t0, 0x8");
       instr_stream.push_back("csrw mstatus, t0");
     endfunction

**逐段解释** ：

* 第 47-L52 行：函数把 ``.section .text``、``.global _start`` 和 ``_start:``
  直接写入 ``instr_stream``，作为生成 assembly 的入口符号。
* 第 55 行：stack pointer 被初始化到 ``0x82000000``。该值来自源码中的常量，
  文档不推导额外 memory map。
* 第 58-L59 行：写 ``li t0, 0x8`` 后 ``csrw mstatus, t0``，使生成程序一开始
  写入 ``mstatus``。

**接口关系** ：

* **被调用** ：父类 program 生成流程调用 header hook。
* **调用** ：调用 ``instr_stream.push_back`` 和 ``$sformatf``。
* **共享状态** ：写父类成员 ``instr_stream``。

§4.3  ``gen_ecall_handler()`` 与 mailbox 结束
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：ECALL handler 不结束测试，而是把 ``mepc`` 增加 4 后 ``mret``。
测试结束由 mailbox 写完成：pass 写 ``0xff``，fail 写 ``0x01`` 到
``0xD0580000``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L62-L86``）：

.. code-block:: systemverilog

     // Override ECALL handler: increment MEPC+4 and mret (do not end test)
     virtual function void gen_ecall_handler(int hart);
       string instr[$];
       instr = {
         "csrr t0, mepc",
         "addi t0, t0, 4",
         "csrw mepc, t0",
         "mret"
       };
       gen_section(get_label("ecall_handler", hart), instr);
     endfunction

     virtual function void gen_program_end(int hart);
       // EH2 tests end via mailbox writes from test_done/test_fail.
     endfunction

     // Generate a single EH2 mailbox write. 0xff means pass, 0x01 means fail.
     virtual function void gen_test_end(input bit pass, ref string instr[$]);
       instr = {
         $sformatf("li t0, 0x%08x", 32'hD058_0000),
         pass ? "li t1, 0xff" : "li t1, 0x01",
         "sw t1, 0(t0)",
         "1: j 1b"
       };

**逐段解释** ：

* 第 63-L71 行：ECALL handler 由 4 条指令组成：读取 ``mepc``、加 4、写回
  ``mepc``、``mret``。随后通过 ``gen_section(get_label(...), instr)`` 生成
  hart 对应 handler section。
* 第 74-L76 行：``gen_program_end`` 是空实现入口；源码注释说明 EH2 测试通过
  ``test_done/test_fail`` 的 mailbox 写结束，不使用父类默认结束段。
* 第 79-L85 行：``gen_test_end`` 生成 mailbox 写序列。地址是 ``0xD0580000``；
  pass/fail 选择发生在三元表达式；写完后进入自旋 ``1: j 1b``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L88-L96``）：

.. code-block:: systemverilog

     // Override the upstream write_tohost/ecall ending with the EH2 mailbox.
     virtual function void gen_test_done();
       string instr[$];
       gen_test_end(1'b1, instr);
       instr_stream = {instr_stream, {format_string("test_done:", LABEL_STR_LEN)}, instr};
       instr.delete();
       gen_test_end(1'b0, instr);
       instr_stream = {instr_stream, {format_string("test_fail:", LABEL_STR_LEN)}, instr};
     endfunction

**逐段解释** ：

* 第 90-L92 行：先生成 pass 版本 mailbox 序列，并把 ``test_done:`` 标签和指令
  拼接到 ``instr_stream``。
* 第 93-L95 行：清空临时数组后生成 fail 版本 mailbox 序列，并拼接到
  ``test_fail:`` 标签之后。

**接口关系** ：

* **被调用** ：riscv-dv 生成 trap handler 和 test ending 时调用这些 hook。
* **调用** ：``gen_ecall_handler`` 调用 ``gen_section`` 和 ``get_label``；
  ``gen_test_done`` 调用 ``gen_test_end`` 与 ``format_string``。
* **共享状态** ：写 ``instr_stream``；使用父类格式常量 ``LABEL_STR_LEN``。

§4.4  ``gen_init_section()``、``init_eh2_custom_csr()`` 与 NMI/debug ROM
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：初始化段先复用父类内容，再追加 EH2 自定义 CSR 初始化、跳转到
``main``、NMI handler 和 debug ROM。NMI handler 读取 ``0x7F8`` 后 ``mret``；
debug ROM 读取 ``dcsr/dpc``，清 ``dcsr.ebreakm`` 后 ``dret``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L98-L120``）：

.. code-block:: systemverilog

     // Override init section to include test_done/test_fail labels
     virtual function void gen_init_section(int hart);
       super.gen_init_section(hart);
       init_eh2_custom_csr(hart);
       instr_stream.push_back({indent, "j main"});
       gen_nmi_handler(hart);
     endfunction

     // Initialize EH2-specific CSRs
     virtual function void init_eh2_custom_csr(int hart);
       // Enable all performance counters via mcountinhibit
       instr_stream.push_back($sformatf("# EH2 custom CSR init for hart %0d", hart));
       instr_stream.push_back("li t0, 0x0");
       instr_stream.push_back("csrw mcountinhibit, t0");

       // Configure MRAC (memory region access control)
       instr_stream.push_back("li t0, 0x1A55A5A5");  // All regions: cacheable
       instr_stream.push_back("csrw 0x7C0, t0");     // mrac

       // Set MFDC (feature disable control) - enable all features
       instr_stream.push_back("li t0, 0x0");
       instr_stream.push_back("csrw 0x7F9, t0");     // mfdc

**逐段解释** ：

* 第 99-L104 行：``gen_init_section`` 先调用 ``super.gen_init_section``，再调用
  ``init_eh2_custom_csr``，随后写入 ``j main``，最后生成 NMI handler。
* 第 107-L112 行：``init_eh2_custom_csr`` 先写注释和 ``mcountinhibit=0``，
  使生成程序初始化 counter inhibit CSR。
* 第 114-L115 行：函数将 ``0x1A55A5A5`` 写入 CSR ``0x7C0``，源码注释标为
  ``mrac``。
* 第 118-L119 行：函数将 0 写入 CSR ``0x7F9``，源码注释标为 ``mfdc``。
  文档只记录代码实际写入的地址和值，不把它改写为其他地址。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L122-L146``）：

.. code-block:: systemverilog

     // Generate NMI handler
     virtual function void gen_nmi_handler(int hart);
       instr_stream.push_back("");
       instr_stream.push_back("# NMI handler");
       instr_stream.push_back($sformatf("h%0d_nmi_handler:", hart));
       instr_stream.push_back("  # NMI - read MNMCause for info");
       instr_stream.push_back("  csrr t0, 0x7F8");     // mcgc - read for debug
       instr_stream.push_back("  # Return from NMI via mret");
       instr_stream.push_back("  mret");
     endfunction

     // Generate debug ROM section (for debug mode support)
     virtual function void gen_debug_rom(int hart);
       instr_stream.push_back("");
       instr_stream.push_back("# Debug ROM");
       instr_stream.push_back(".section .debug_rom, \"ax\"");
       instr_stream.push_back($sformatf("h%0d_debug_rom:", hart));
       instr_stream.push_back("  # Read DCSR");
       instr_stream.push_back("  csrr t0, 0x7B0");     // dcsr
       instr_stream.push_back("  # Read DPC");
       instr_stream.push_back("  csrr t1, 0x7B1");     // dpc
       instr_stream.push_back("  # Resume execution");
       instr_stream.push_back("  csrci 0x7B0, 0x4");   // Clear ebreakm in dcsr
       instr_stream.push_back("  dret");

**逐段解释** ：

* 第 123-L130 行：NMI handler 使用 hart 编号生成 ``h%0d_nmi_handler`` 标签，
  读取 CSR ``0x7F8`` 到 ``t0``，再执行 ``mret``。
* 第 134-L138 行：debug ROM 片段切换到 ``.debug_rom`` section，并生成
  ``h%0d_debug_rom`` 标签。
* 第 139-L145 行：debug ROM 读取 ``dcsr`` 和 ``dpc``，执行 ``csrci 0x7B0, 0x4``
  清除 ``dcsr`` 中的 ebreakm 位，然后 ``dret`` 返回。

**接口关系** ：

* **被调用** ：初始化段、NMI 和 debug ROM 生成 hook 由 riscv-dv program flow 调用。
* **调用** ：调用 ``super.gen_init_section``、``init_eh2_custom_csr``、
  ``gen_nmi_handler``、``instr_stream.push_back``。
* **共享状态** ：写 ``instr_stream``，使用 ``indent`` 和 hart 参数生成标签。

§5  ``eh2_directed_instr_lib.sv``
--------------------------------------------------------------------------------

§5.1  ``eh2_base_directed_stream`` — EH2 stream 共同基类
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该虚基类把 EH2 stream 的 ``gen_instr()`` 调用接到 riscv-dv 的
``post_randomize()`` 时机。没有这个桥接，子类填充 ``instr_list`` 的代码不会在
``randomize()`` 后自动执行。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L25-L46``）：

.. code-block:: systemverilog

   virtual class eh2_base_directed_stream extends riscv_directed_instr_stream;

     function new(string name = "");
       super.new(name);
     endfunction

     // Subclasses populate instr_list here. Defaults match the riscv-dv signature
     // — `no_branch=1, no_load_store=1` keeps streams architecturally inert
     // unless they explicitly opt in.
     pure virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                          bit is_debug_program = 0);

     function void post_randomize();
       gen_instr();
       if (instr_list.size() == 0) begin
         `uvm_fatal(get_full_name(),
                    "EH2 directed stream produced an empty instr_list")
       end
       super.post_randomize();
     endfunction

   endclass

**逐段解释** ：

* 第 25-L29 行：类继承 ``riscv_directed_instr_stream``，构造函数仅调用父类构造。
* 第 34-L35 行：``gen_instr`` 是 pure virtual，强制每个 EH2 子 stream 实现
  自己的指令填充逻辑。
* 第 37-L43 行：``post_randomize`` 先调用 ``gen_instr``，再检查 ``instr_list``
  是否为空。为空时使用 ``uvm_fatal`` 停止，而不是让父类在空列表上继续处理。
* 第 43 行：非空后调用 ``super.post_randomize``，保留 riscv-dv 父类设置
  atomic、label、comment 等标记的行为。

**接口关系** ：

* **被调用** ：所有 ``eh2_*_stream`` 子类在 randomize 后进入该
  ``post_randomize``。
* **调用** ：调用子类 ``gen_instr``、``uvm_fatal`` 和
  ``super.post_randomize``。
* **共享状态** ：读写父类成员 ``instr_list``。

§5.2  ``eh2_csr_access_stream`` — EH2 自定义 CSR 随机访问
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 stream 从 EH2 自定义 CSR 地址表中随机选择 CSR，生成 CSRRW/CSRRS/
CSRRC 访问序列，并为 ``rs1`` 与 ``rd`` 随机选择非零 GPR。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L52-L77``）：

.. code-block:: systemverilog

   class eh2_csr_access_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_csr_access_stream)

     // EH2 writable custom CSRs
     localparam bit [11:0] EH2_CUSTOM_CSRS[] = '{
       12'h7FF,  // mscause
       12'h7C0,  // mrac
       12'h7C9,  // mfdc
       12'h7F8,  // mcgc
       12'h7C6,  // mpmc
       12'h7C2,  // mcpc
       12'h7C4,  // dmst
       12'h7CE,  // mfdht
       12'h7CF,  // mfdhs
       12'h7FE,  // mnmipdel
       12'h7D2,  // mitcnt0
       12'h7D5,  // mitcnt1
       12'h7D3,  // mitb0
       12'h7D6,  // mitb1
       12'h7D4,  // mitctl0
       12'h7D7,  // mitctl1
       12'h7F0,  // micect
       12'h7F1,  // miccmect

**逐段解释** ：

* 第 52-L54 行：stream 继承 EH2 基类并注册 UVM factory。
* 第 57-L77 行：``EH2_CUSTOM_CSRS`` 是本 stream 的 CSR 地址池。它与
  ``riscv_core_setting.sv`` 的 ``custom_csr`` 有重叠，但这里只包含注释称为
  writable custom CSR 的子集。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L83-L106``）：

.. code-block:: systemverilog

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                     bit is_debug_program = 0);
       riscv_instr instr;
       int unsigned csr_idx;
       bit [11:0] csr_addr;

       repeat (10 + $urandom_range(10)) begin
         csr_idx = $urandom_range(EH2_CUSTOM_CSRS.size() - 1);
         csr_addr = EH2_CUSTOM_CSRS[csr_idx];

         // Generate CSRRW, CSRRS, or CSRRC randomly
         case ($urandom_range(2))
           0: instr = riscv_instr::get_instr(CSRRW);
           1: instr = riscv_instr::get_instr(CSRRS);
           2: instr = riscv_instr::get_instr(CSRRC);
         endcase

         instr.csr = csr_addr;
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
         instr.rd  = riscv_reg_t'($urandom_range(1, 31));
         instr_list.push_back(instr);
       end
     endfunction

**逐段解释** ：

* 第 89-L91 行：循环次数为 ``10 + $urandom_range(10)``，每次从
  ``EH2_CUSTOM_CSRS`` 随机取一个地址。
* 第 94-L98 行：CSR 指令类型在 ``CSRRW``、``CSRRS``、``CSRRC`` 三者中随机选择。
* 第 100-L104 行：函数把 CSR 地址写入 ``instr.csr``，打开 ``has_rs1``，并把
  ``rs1`` 和 ``rd`` 都限制在 x1-x31。

**接口关系** ：

* **被调用** ：testlist 中 ``+directed_instr_0=eh2_csr_access_stream,...`` 触发。
* **调用** ：调用 ``riscv_instr::get_instr`` 和 ``instr_list.push_back``。
* **共享状态** ：写 ``instr_list``；读取本类 ``EH2_CUSTOM_CSRS``。

§5.3  ``eh2_bitmanip_stream`` — bitmanip 定向指令池
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 stream 把 Zba、Zbb、Zbc、Zbs 指令池合并后随机生成 bitmanip 指令。
当前代码中 Zbc/Zbs 列表为空，Zbb 只保留 host assembler 支持的子集。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L114-L137``）：

.. code-block:: systemverilog

   class eh2_bitmanip_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_bitmanip_stream)

     // Zba (address generation)
     localparam riscv_instr_name_t ZBA_INSTRS[] = '{
       SH1ADD, SH2ADD, SH3ADD, SLLI, SRLI
     };

     // Zbb (basic bit manipulation)
     // NOTE: SEXT_B, SEXT_H, ZEXT_H, ROL, ROR, RORI, ORC_B, REV8 require GCC
     // assembler 12+ to encode. The toolchain at /home/Riscv_Tools (gcc 11.1)
     // accepts only the subset below — keep this list trimmed until the
     // toolchain is upgraded or `as -misa-spec=...` is wired up.
     localparam riscv_instr_name_t ZBB_INSTRS[] = '{
       ANDN, ORN, XNOR, CLZ, CTZ, CPOP,
       MAX, MAXU, MIN, MINU
     };

     // Zbc and Zbs are not yet supported by the host gcc 11.1 assembler. RTL
     // implements them; re-enable here once the toolchain ships zbc/zbs.
     localparam riscv_instr_name_t ZBC_INSTRS[] = '{};
     localparam riscv_instr_name_t ZBS_INSTRS[] = '{};

**逐段解释** ：

* 第 119-L121 行：Zba 池包含 ``SH1ADD``、``SH2ADD``、``SH3ADD`` 和两个 shift
  immediate 指令 ``SLLI``、``SRLI``。
* 第 124-L131 行：Zbb 池明确删减到当前工具链可编码的指令集合。源码注释说明
  ``SEXT_B``、``ROL``、``ROR`` 等需要 GCC assembler 12+，当前列表只保留
  ``ANDN``、``ORN``、``XNOR``、``CLZ``、``CTZ``、``CPOP``、``MAX``、
  ``MAXU``、``MIN``、``MINU``。
* 第 133-L136 行：Zbc 和 Zbs 池在当前代码中为空数组。虽然 core setting 声明了
  Zbc/Zbs 组，该 stream 当前不会从这两个数组产生指令。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L142-L173``）：

.. code-block:: systemverilog

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                     bit is_debug_program = 0);
       riscv_instr instr;
       riscv_instr_name_t all_bitmanip[];
       int unsigned idx;

       // Combine all bitmanip instructions
       all_bitmanip = new[ZBA_INSTRS.size() + ZBB_INSTRS.size() +
                           ZBC_INSTRS.size() + ZBS_INSTRS.size()];
       idx = 0;
       foreach (ZBA_INSTRS[i]) all_bitmanip[idx++] = ZBA_INSTRS[i];
       foreach (ZBB_INSTRS[i]) all_bitmanip[idx++] = ZBB_INSTRS[i];
       foreach (ZBC_INSTRS[i]) all_bitmanip[idx++] = ZBC_INSTRS[i];
       foreach (ZBS_INSTRS[i]) all_bitmanip[idx++] = ZBS_INSTRS[i];

       repeat (15 + $urandom_range(20)) begin
         idx = $urandom_range(all_bitmanip.size() - 1);
         instr = riscv_instr::get_instr(all_bitmanip[idx]);
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'($urandom_range(1, 31));

**逐段解释** ：

* 第 148-L155 行：函数按四个数组长度分配 ``all_bitmanip``，再用 ``foreach``
  顺序复制 Zba、Zbb、Zbc、Zbs 指令名。由于 Zbc/Zbs 当前为空，实际池来自
  Zba 和 Zbb。
* 第 157-L160 行：循环次数为 ``15 + $urandom_range(20)``；每次随机取一个
  bitmanip 指令名并通过 ``riscv_instr::get_instr`` 构造指令对象。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L160-L173``）：

.. code-block:: systemverilog

         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
         if (instr.has_rs2)
           instr.rs2 = riscv_reg_t'($urandom_range(1, 31));
         instr.rd = riscv_reg_t'($urandom_range(1, 31));
         // Shift-immediate instructions (SLLI/SRLI) need a shamt — riscv_instr
         // does not auto-populate it from ALU defaults.
         if (all_bitmanip[idx] inside {SLLI, SRLI}) begin
           instr.imm = $urandom_range(0, 31);
           instr.imm_str = $sformatf("%0d", instr.imm);
         end
         instr_list.push_back(instr);
       end
     endfunction

**逐段解释** ：

* 第 160-L164 行：``rs1`` 和 ``rd`` 取 x1-x31；当指令对象本身标记
  ``has_rs2`` 时，才填 ``rs2``。
* 第 167-L170 行：``SLLI`` 和 ``SRLI`` 需要 shift amount，代码显式设置
  ``instr.imm`` 和 ``instr.imm_str``。其他 bitmanip 指令不经过这个分支。
* 第 171 行：每条构造完成的指令进入 ``instr_list``，随后由基类
  ``post_randomize`` 交给 riscv-dv 父类继续处理。

**接口关系** ：

* **被调用** ：bitmanip 定向测试或 ``gen_opts`` 中引用该 stream 时调用。
* **调用** ：调用 ``riscv_instr::get_instr``、``$urandom_range`` 和
  ``instr_list.push_back``。
* **共享状态** ：读取四个 localparam 指令池，写 ``instr_list``。

§5.4  ``eh2_pic_int_stream`` — PIC CSR 序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 stream 生成一段固定 PIC/external interrupt CSR 操作：打开
``MIE.MEIE``，配置 ``MEIVT``、``MEIPT``、``MEICIDPL``，读取 ``MEIHAP`` 和
``MEICPCT``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L181-L214``）：

.. code-block:: systemverilog

   class eh2_pic_int_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_pic_int_stream)

     function new(string name = "");
       super.new(name);
     endfunction

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                     bit is_debug_program = 0);
       riscv_instr instr;

       // Enable external interrupts in MIE
       instr_list.push_back(get_li_instr(MIE, 32'h0000_0800));  // MEIE bit
       instr_list.push_back(get_csr_instr(CSRRW, MIE, 5));       // Write from t0

       // Configure MEIVT (External Interrupt Vector Table)
       instr_list.push_back(get_li_instr(12'hBC8, 32'h8000_1000));
       instr_list.push_back(get_csr_instr(CSRRW, 12'hBC8, 5));

       // Set MEIPT (threshold)
       instr_list.push_back(get_li_instr(12'hBC9, 32'h0000_0001));
       instr_list.push_back(get_csr_instr(CSRRW, 12'hBC9, 5));

**逐段解释** ：

* 第 181-L190 行：类继承 EH2 基类并实现 ``gen_instr``；局部变量 ``instr`` 在这段
  代码中声明但未直接使用。
* 第 194-L195 行：先生成 ``li`` 把 ``0x00000800`` 放入 t0，再生成对 ``MIE`` 的
  ``CSRRW``，用于写 MEIE bit。
* 第 198-L203 行：同样使用 ``li`` 加 ``CSRRW`` 的模式配置 ``MEIVT`` 地址
  ``0xBC8`` 和 ``MEIPT`` 地址 ``0xBC9``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L205-L236``）：

.. code-block:: systemverilog

       // Set MEICIDPL (claim ID priority level)
       instr_list.push_back(get_li_instr(12'hBCB, 32'h0000_000F));
       instr_list.push_back(get_csr_instr(CSRRW, 12'hBCB, 5));

       // Read MEIHAP (interrupt claim)
       instr_list.push_back(get_csr_instr(CSRRS, 12'hFC8, 5));

       // Read MEICPCT (claim and priority capture)
       instr_list.push_back(get_csr_instr(CSRRS, 12'hBCA, 5));
     endfunction

     // Helper: generate LI instruction
     function riscv_instr get_li_instr(bit [11:0] csr, bit [31:0] val);
       riscv_pseudo_instr instr;
       instr = riscv_pseudo_instr::type_id::create("li_instr");
       instr.pseudo_instr_name = LI;
       instr.rd = riscv_reg_t'(5);  // t0
       instr.imm = val;
       instr.imm_str = $sformatf("0x%0h", val);
       return instr;
     endfunction

**逐段解释** ：

* 第 206-L213 行：``MEICIDPL`` 使用 ``0x0000000F`` 写入；``MEIHAP`` 和
  ``MEICPCT`` 通过 ``CSRRS`` 读取，地址分别为 ``0xFC8`` 和 ``0xBCA``。
* 第 217-L225 行：``get_li_instr`` 创建 ``riscv_pseudo_instr``，固定目标寄存器为
  x5（注释标为 t0），立即数来自参数 ``val``，并填充 ``imm_str``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L227-L236``）：

.. code-block:: systemverilog

     // Helper: generate CSR instruction
     function riscv_instr get_csr_instr(riscv_instr_name_t name, bit [11:0] csr, int gpr);
       riscv_instr instr;
       instr = riscv_instr::get_instr(name);
       instr.csr = csr;
       instr.has_rs1 = 1;
       instr.rs1 = riscv_reg_t'(gpr);
       instr.rd = riscv_reg_t'(gpr);
       return instr;
     endfunction

**逐段解释** ：

* 第 228-L235 行：``get_csr_instr`` 使用传入的 CSR 指令名构造对象，写入
  ``csr``，打开 ``has_rs1``，并把 ``rs1`` 与 ``rd`` 都设成同一个 GPR 编号。
  ``eh2_pic_int_stream`` 调用时传入的 GPR 是 5。

**接口关系** ：

* **被调用** ：interrupt 相关 testlist 通过 ``eh2_pic_int_stream`` 触发。
* **调用** ：调用本类 ``get_li_instr``、``get_csr_instr``、
  ``riscv_pseudo_instr::type_id::create``、``riscv_instr::get_instr``。
* **共享状态** ：写 ``instr_list``；CSR 地址与 ``csr_description.yaml`` 的 PIC
  CSR 条目对应。

§5.5  debug、atomic、breakpoint、exception 和 CSR hazard streams
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：这些 stream 分别覆盖 debug CSR 读写、LR/SC 序列、EBREAK 序列、
exception 序列和连续 CSR hazard 序列。它们共享 ``eh2_base_directed_stream``
的 post-randomize 桥接。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L244-L279``）：

.. code-block:: systemverilog

   class eh2_debug_csr_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_debug_csr_stream)

     function new(string name = "");
       super.new(name);
     endfunction

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                     bit is_debug_program = 0);
       riscv_instr instr;

       // Read DCSR
       instr = riscv_instr::get_instr(CSRRS);
       instr.csr = 12'h7B0;  // dcsr
       instr.has_rs1 = 1;
       instr.rs1 = ZERO;
       instr.rd = riscv_reg_t'($urandom_range(1, 31));
       instr_list.push_back(instr);

       // Read DPC
       instr = riscv_instr::get_instr(CSRRS);
       instr.csr = 12'h7B1;  // dpc
       instr.has_rs1 = 1;

**逐段解释** ：

* 第 244-L253 行：debug CSR stream 继承 EH2 基类并实现 ``gen_instr``。
* 第 257-L262 行：第一条指令为 ``CSRRS`` 读取 ``dcsr`` 地址 ``0x7B0``，``rs1``
  使用 ``ZERO``，``rd`` 随机选 x1-x31。
* 第 265 行起：第二条同样使用 ``CSRRS`` 读取 ``dpc`` 地址 ``0x7B1``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L264-L279``）：

.. code-block:: systemverilog

       // Read DPC
       instr = riscv_instr::get_instr(CSRRS);
       instr.csr = 12'h7B1;  // dpc
       instr.has_rs1 = 1;
       instr.rs1 = ZERO;
       instr.rd = riscv_reg_t'($urandom_range(1, 31));
       instr_list.push_back(instr);

       // Write DPC
       instr = riscv_instr::get_instr(CSRRW);
       instr.csr = 12'h7B1;  // dpc
       instr.has_rs1 = 1;
       instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
       instr.rd = riscv_reg_t'($urandom_range(1, 31));
       instr_list.push_back(instr);
     endfunction

**逐段解释** ：

* 第 265-L270 行：读取 ``dpc`` 时仍使用 ``ZERO`` 作为 ``rs1``，因此它是读操作。
* 第 273-L278 行：写 ``dpc`` 时切换到 ``CSRRW``，``rs1`` 和 ``rd`` 都随机取
  x1-x31。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L287-L332``）：

.. code-block:: systemverilog

   class eh2_atomic_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_atomic_stream)

     function new(string name = "");
       super.new(name);
     endfunction

     virtual function void gen_instr(bit no_branch = 0, bit no_load_store = 0,
                                     bit is_debug_program = 0);
       riscv_instr instr;
       int base_reg;

       base_reg = $urandom_range(1, 28);

       repeat (5 + $urandom_range(10)) begin
         // LR.W
         instr = riscv_instr::get_instr(LR_W);
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'(base_reg);
         instr.rd = riscv_reg_t'(base_reg + 1);
         instr_list.push_back(instr);

**逐段解释** ：

* 第 295-L300 行：atomic stream 允许 branch 和 load/store（两个默认参数都为 0），
  并把 ``base_reg`` 随机限制在 1 到 28，给后续 ``base_reg+3`` 留出寄存器范围。
* 第 302-L308 行：每轮先生成 ``LR_W``，``rs1`` 是 base register，``rd`` 是
  ``base_reg+1``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L310-L330``）：

.. code-block:: systemverilog

         // Modify value (ADDI)
         instr = riscv_instr::get_instr(ADDI);
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'(base_reg + 1);
         instr.rd = riscv_reg_t'(base_reg + 2);
         instr.imm = $urandom_range(1, 16);
         instr.imm_str = $sformatf("%0d", instr.imm);
         instr_list.push_back(instr);

         // SC.W
         instr = riscv_instr::get_instr(SC_W);
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'(base_reg);
         instr.has_rs2 = 1;
         instr.rs2 = riscv_reg_t'(base_reg + 2);
         instr.rd = riscv_reg_t'(base_reg + 3);
         instr_list.push_back(instr);
         // (Originally followed by a BNE retry loop — removed because riscv-dv
         // emits BNE immediates as unresolved labels which the linker rejects.

**逐段解释** ：

* 第 311-L317 行：``ADDI`` 读取 ``base_reg+1``，写 ``base_reg+2``，立即数随机为
  1 到 16，并同步填充字符串形式 ``imm_str``。
* 第 320-L326 行：``SC_W`` 使用 base register 作为地址寄存器，``base_reg+2``
  作为 store data register，``base_reg+3`` 接收 SC.W 成功/失败结果。
* 第 327-L330 行：源码注释说明原先跟随的 ``BNE`` retry loop 被移除，因为
  riscv-dv 会把 ``BNE`` immediate 生成为 linker 拒绝的 unresolved label。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L340-L397``）：

.. code-block:: systemverilog

   class eh2_breakpoint_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_breakpoint_stream)

     function new(string name = "");
       super.new(name);
     endfunction

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                     bit is_debug_program = 0);
       riscv_instr instr;

       // Generate a series of EBREAK instructions
       repeat (3 + $urandom_range(5)) begin
         instr = riscv_instr::get_instr(EBREAK);
         instr_list.push_back(instr);

         // Add some NOPs between breakpoints

**逐段解释** ：

* 第 340-L349 行：breakpoint stream 继承基类并默认禁止 branch/load/store。
* 第 353-L355 行：循环次数为 ``3 + $urandom_range(5)``，每轮先插入一条
  ``EBREAK``。
* 第 358 行起：每条 ``EBREAK`` 后插入若干 ``NOP``，用于在 breakpoint 之间拉开
  指令距离。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L357-L397``）：

.. code-block:: systemverilog

         // Add some NOPs between breakpoints
         repeat ($urandom_range(1, 5)) begin
           instr = riscv_instr::get_instr(NOP);
           instr_list.push_back(instr);
         end
       end
     endfunction

   endclass

   // ---------------------------------------------------------------------------
   // Exception Stream
   // Generates instructions that cause various exceptions
   // ---------------------------------------------------------------------------
   class eh2_exception_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_exception_stream)

     function new(string name = "");
       super.new(name);
     endfunction

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 0,

**逐段解释** ：

* 第 358-L361 行：``NOP`` 数量为 ``$urandom_range(1, 5)``，每条都通过
  ``riscv_instr::get_instr(NOP)`` 构造并进入 ``instr_list``。
* 第 371-L379 行：exception stream 允许 load/store（``no_load_store=0``），
  为后续可选 misaligned load 留出条件。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L379-L397``）：

.. code-block:: systemverilog

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 0,
                                     bit is_debug_program = 0);
       riscv_instr instr;

       // Generate ECALL
       instr = riscv_instr::get_instr(ECALL);
       instr_list.push_back(instr);

       // Generate misaligned load (if load/store allowed)
       if (!no_load_store) begin
         instr = riscv_instr::get_instr(LW);
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
         instr.rd = riscv_reg_t'($urandom_range(1, 31));
         instr.imm = 1;  // Misaligned offset
         instr.imm_str = $sformatf("%0d", instr.imm);
         instr_list.push_back(instr);
       end

**逐段解释** ：

* 第 383-L385 行：exception stream 总是先插入一条 ``ECALL``。
* 第 388-L395 行：当 ``no_load_store`` 为 0 时，stream 追加 ``LW``，随机选择
  ``rs1`` 和 ``rd``，并把 immediate 固定为 1，源码注释称为 misaligned offset。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L405-L458``）：

.. code-block:: systemverilog

   class eh2_csr_hazard_stream extends eh2_base_directed_stream;

     `uvm_object_utils(eh2_csr_hazard_stream)

     localparam bit [11:0] HAZARD_CSRS[] = '{
       12'h300,  // mstatus
       12'h304,  // mie
       12'h340,  // mscratch
       12'h341,  // mepc
       12'h342,  // mcause
       12'h7C0,  // mrac
       12'h7C9   // mfdc
     };

     function new(string name = "");
       super.new(name);
     endfunction

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,

**逐段解释** ：

* 第 405-L417 行：hazard stream 的 CSR 池包含 ``mstatus``、``mie``、
  ``mscratch``、``mepc``、``mcause``、``mrac``、``mfdc``。前 5 个是标准
  M-mode CSR，后 2 个是 EH2 自定义 CSR。
* 第 423 行起：该 stream 默认禁止 branch/load/store，只构造连续 CSR 访问。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L423-L458``）：

.. code-block:: systemverilog

     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                     bit is_debug_program = 0);
       riscv_instr instr;
       int unsigned csr_idx;
       bit [11:0] csr_addr;

       // Generate back-to-back CSR read-write pairs
       repeat (8 + $urandom_range(10)) begin
         csr_idx = $urandom_range(HAZARD_CSRS.size() - 1);
         csr_addr = HAZARD_CSRS[csr_idx];

         // CSRRS (read)
         instr = riscv_instr::get_instr(CSRRS);
         instr.csr = csr_addr;
         instr.has_rs1 = 1;
         instr.rs1 = ZERO;
         instr.rd = riscv_reg_t'($urandom_range(1, 31));
         instr_list.push_back(instr);

**逐段解释** ：

* 第 430-L432 行：循环次数为 ``8 + $urandom_range(10)``，每轮从
  ``HAZARD_CSRS`` 中随机选择一个 CSR。
* 第 435-L440 行：第一条 ``CSRRS`` 使用 ``ZERO`` 作为 ``rs1`` 读取 CSR，``rd``
  随机取 x1-x31。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L442-L458``）：

.. code-block:: systemverilog

         // CSRRW (write) - creates RAW hazard with previous read
         instr = riscv_instr::get_instr(CSRRW);
         instr.csr = csr_addr;
         instr.has_rs1 = 1;
         instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
         instr.rd = riscv_reg_t'($urandom_range(1, 31));
         instr_list.push_back(instr);

         // CSRRS (read again) - creates RAW hazard with previous write
         instr = riscv_instr::get_instr(CSRRS);
         instr.csr = csr_addr;
         instr.has_rs1 = 1;
         instr.rs1 = ZERO;
         instr.rd = riscv_reg_t'($urandom_range(1, 31));
         instr_list.push_back(instr);

**逐段解释** ：

* 第 443-L448 行：第二条 ``CSRRW`` 写同一个 CSR，``rs1`` 和 ``rd`` 随机取
  x1-x31。源码注释将它标为与前一读形成 RAW hazard。
* 第 451-L456 行：第三条再读同一个 CSR，源码注释将它标为与前一写形成 RAW
  hazard。

**接口关系** ：

* **被调用** ：debug、atomic、breakpoint、exception、CSR hazard testlist 项通过
  ``+directed_instr`` 或对应 generator 选项触发这些 stream。
* **调用** ：调用 ``riscv_instr::get_instr``、``$urandom_range``、
  ``instr_list.push_back``。
* **共享状态** ：每个 stream 写父类 ``instr_list``；CSR 地址与 core setting 和
  CSR YAML 共用同一数值空间。

§6  ``eh2_debug_triggers_overrides.sv``
--------------------------------------------------------------------------------

§6.1  ``eh2_hardware_triggers_debug_rom_gen`` — trigger debug ROM
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该类继承 ``riscv_debug_rom_gen``，为硬件 trigger 测试生成一段 debug
ROM。ROM 读取 ``DCSR.cause``，按 EBREAK、TRIGGER、HALTREQ 三类 cause 进入不同
分支，并在末尾跳转到 ``debug_end`` 执行 ``dret``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L11-L29``）：

.. code-block:: systemverilog

   class eh2_hardware_triggers_debug_rom_gen extends riscv_debug_rom_gen;

     `uvm_object_utils(eh2_hardware_triggers_debug_rom_gen)
     `uvm_object_new

     int unsigned eh2_trigger_idx = 0; // See [DbgHwBreakNum]

     virtual function void gen_program();
       string instr[$];

       // Don't save off GPRs (ie. this WILL modify program flow).
       // We want to capture a register value (gpr[1]) from the directed_instr_streams
       // in main() that contains the address for our next trigger.
       // This works in tandem with the breakpoint directed stream which stores the
       // address of the instruction to trigger on in a fixed register, then executes
       // an EBREAK to enter debug mode via dcsr.ebreakm=1.  The debug ROM code then
       // sets up the breakpoint trigger to this address, and returns, allowing main
       // to continue executing until we hit the trigger.

**逐段解释** ：

* 第 11-L16 行：类继承 ``riscv_debug_rom_gen``，注册 factory，并把
  ``eh2_trigger_idx`` 初始化为 0。
* 第 18-L20 行：``gen_program`` 使用字符串数组 ``instr`` 构造 debug ROM 指令。
* 第 21-L29 行：源码注释说明该 ROM 不保存 GPR，会修改 program flow；它依赖
  directed stream 在 main 中把下一次 trigger 地址放入固定寄存器。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L41-L65``）：

.. code-block:: systemverilog

       instr = {// Check DCSR.cause (DCSR[8:6]) to branch to the next block of code.
                $sformatf("csrr x%0d,   0x%0x",        cfg.scratch_reg, DCSR),
                $sformatf("slli x%0d,    x%0d,  0x17", cfg.scratch_reg, cfg.scratch_reg),
                $sformatf("srli x%0d,    x%0d,  0x1d", cfg.scratch_reg, cfg.scratch_reg),
                $sformatf("li   x%0d,     0x1",        cfg.gpr[0]), // EBREAK = 1
                $sformatf("beq  x%0d,    x%0d,  1f",   cfg.scratch_reg, cfg.gpr[0]),
                $sformatf("li   x%0d,     0x2",        cfg.gpr[0]), // TRIGGER = 2
                $sformatf("beq  x%0d,    x%0d,  2f",   cfg.scratch_reg, cfg.gpr[0]),
                $sformatf("li   x%0d,     0x3",        cfg.gpr[0]), // HALTREQ = 3
                $sformatf("beq  x%0d,    x%0d,  3f",   cfg.scratch_reg, cfg.gpr[0]),

                // DCSR.cause == EBREAK
                "1: nop",
                // The breakpoint directed stream inserts EBREAKs such that cfg.gpr[1]
                // now contains the address of the next trigger.
                // Enable the trigger and set to this address.
                $sformatf("csrrwi  zero, 0x%0x, %0d",  TSELECT, eh2_trigger_idx),
                $sformatf("csrrw   zero, 0x%0x, x0",   TDATA1),

**逐段解释** ：

* 第 41-L44 行：ROM 读取 ``DCSR`` 到 scratch register，再通过左移/右移提取
  ``DCSR[8:6]`` cause。
* 第 45-L50 行：cause 分别与 1、2、3 比较，并跳转到 label ``1f``、``2f``、
  ``3f``。源码注释标明 1 是 EBREAK，2 是 TRIGGER，3 是 HALTREQ。
* 第 53-L60 行：EBREAK 分支选择 trigger index，先清 ``TDATA1``，再把
  ``cfg.gpr[1]`` 写入 ``TDATA2``，最后写 ``TDATA1`` 使能 trigger。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L59-L83``）：

.. code-block:: systemverilog

                $sformatf("csrrw   zero, 0x%0x, x%0d", TDATA2, cfg.gpr[1]),
                $sformatf("csrrwi  zero, 0x%0x, 5",    TDATA1),
                // Increment the PC + 4 (EBREAK does not do this for you.)
                $sformatf("csrr   x%0d, 0x%0x",    cfg.gpr[0], DPC),
                $sformatf("addi   x%0d,  x%0d, 4", cfg.gpr[0], cfg.gpr[0]),
                $sformatf("csrw  0x%0x,  x%0d",    DPC, cfg.gpr[0]),
                "j 4f",

                // DCSR.cause == TRIGGER
                "2: nop",
                // Disable the trigger until the next breakpoint is known.
                $sformatf("csrrwi  zero, 0x%0x, %0d", TSELECT, eh2_trigger_idx),
                $sformatf("csrrw   zero, 0x%0x, x0",  TDATA1),
                $sformatf("csrrw   zero, 0x%0x, x0",  TDATA2),
                "j 4f",

                // DCSR.cause == HALTREQ
                "3: nop",
                // Use this once near the start of the test to configure ebreakm to
                // enter debug mode.
                // Set DCSR.ebreakm (DCSR[15]) = 1
                $sformatf("li      x%0d, 0x8000", cfg.scratch_reg),

**逐段解释** ：

* 第 61-L64 行：EBREAK 分支读取 ``DPC``，加 4 后写回。源码注释说明 EBREAK 不会
  自动完成这个 PC 增量。
* 第 68-L73 行：TRIGGER 分支重新选择 trigger index，并把 ``TDATA1`` 和
  ``TDATA2`` 清为 x0，直到下一个 breakpoint 地址已知。
* 第 76-L81 行：HALTREQ 分支生成 ``0x8000`` 并用 ``csrs DCSR`` 设置
  ``DCSR.ebreakm``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L80-L98``）：

.. code-block:: systemverilog

                $sformatf("li      x%0d, 0x8000", cfg.scratch_reg),
                $sformatf("csrs   0x%0x,  x%0d",  DCSR, cfg.scratch_reg),

                "4: nop"
                };

       debug_main = {instr,
                     $sformatf("la   x%0d, debug_end", cfg.scratch_reg),
                     $sformatf("jalr x0,   x%0d, 0",   cfg.scratch_reg)
                     };
       format_section(debug_main);
       gen_section($sformatf("%0sdebug_rom", hart_prefix(hart)), debug_main);

       debug_end = {dret};
       format_section(debug_end);
       gen_section($sformatf("%0sdebug_end", hart_prefix(hart)), debug_end);

       gen_debug_exception_handler();

**逐段解释** ：

* 第 83-L88 行：所有分支落到 label 4 后，ROM 追加 ``la debug_end`` 和
  ``jalr``，跳到 ``debug_end``。
* 第 90-L95 行：``format_section`` 格式化 ``debug_main`` 和 ``debug_end``，
  ``gen_section`` 生成 hart 前缀对应的 section。
* 第 97 行：最后调用 ``gen_debug_exception_handler`` 生成 debug mode 异常处理段。

**接口关系** ：

* **被调用** ：硬件 trigger 相关生成器覆盖 debug ROM 时调用。
* **调用** ：调用 ``format_section``、``gen_section``、``hart_prefix``、
  ``gen_debug_exception_handler``。
* **共享状态** ：读 ``cfg.scratch_reg``、``cfg.gpr``、``hart``、``DCSR``、
  ``TSELECT``、``TDATA1``、``TDATA2``、``DPC`` 和父类 ``debug_main``/
  ``debug_end``。

§6.2  debug exception 与 generator override
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：debug exception handler 直接跳到 ``test_fail``。另一个类
``eh2_hardware_triggers_asm_program_gen`` 覆盖 ``gen_debug_rom``，把父类 debug
ROM 替换成 ``eh2_hardware_triggers_debug_rom_gen``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L101-L128``）：

.. code-block:: systemverilog

     // If we get an exception in debug_mode, fail the test immediately.
     // (something has gone wrong with our stimulus generation)
     virtual function void gen_debug_exception_handler();
       string instr[$];
       instr = {$sformatf("la   x%0d, test_fail", cfg.scratch_reg),
                $sformatf("jalr x1,   x%0d, 0",   cfg.scratch_reg)};
       format_section(instr);
       gen_section($sformatf("%0sdebug_exception", hart_prefix(hart)), instr);
     endfunction

   endclass

   class eh2_hardware_triggers_asm_program_gen extends eh2_asm_program_gen;

     `uvm_object_utils(eh2_hardware_triggers_asm_program_gen)
     `uvm_object_new

     // Same implementation as the parent class, except substitute for our custom
     // debug ROM class.
     virtual function void gen_debug_rom(int hart);
       `uvm_info(`gfn, "Creating debug ROM", UVM_LOW)
       debug_rom = eh2_hardware_triggers_debug_rom_gen::

**逐段解释** ：

* 第 103-L108 行：debug exception handler 生成 ``la test_fail`` 和 ``jalr``，
  然后用 hart 前缀生成 ``debug_exception`` section。
* 第 113-L120 行：``eh2_hardware_triggers_asm_program_gen`` 继承
  ``eh2_asm_program_gen``，只覆盖 debug ROM 生成，不重写前文的 header、mailbox
  或 NMI 逻辑。
* 第 121 行：覆盖函数打印 UVM info，说明即将创建 debug ROM。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L121-L144``）：

.. code-block:: systemverilog

       `uvm_info(`gfn, "Creating debug ROM", UVM_LOW)
       debug_rom = eh2_hardware_triggers_debug_rom_gen::
                   type_id::create("debug_rom", , {"uvm_test_top", ".", `gfn});
       debug_rom.cfg = cfg;
       debug_rom.hart = hart;
       debug_rom.gen_program();
       instr_stream = {instr_stream, debug_rom.instr_stream};
     endfunction

   endclass


   class eh2_hardware_triggers_illegal_instr extends riscv_illegal_instr;

     `uvm_object_utils(eh2_hardware_triggers_illegal_instr)
     `uvm_object_new

     // Make it super-obvious where the illegal instructions are in the assembly.
     function void post_randomize();
       super.post_randomize();
       comment = "INVALID";

**逐段解释** ：

* 第 122-L127 行：函数通过 factory 创建 ``eh2_hardware_triggers_debug_rom_gen``，
  传入 ``cfg`` 和 ``hart``，调用 ``gen_program``，再把 debug ROM 的
  ``instr_stream`` 拼接到当前 ``instr_stream``。
* 第 133-L141 行：``eh2_hardware_triggers_illegal_instr`` 继承
  ``riscv_illegal_instr``，在 ``post_randomize`` 调用父类后把注释字段设为
  ``INVALID``。

**接口关系** ：

* **被调用** ：硬件 trigger 测试选择该 asm program generator 或 illegal instr
  override 时触发。
* **调用** ：调用 UVM factory ``type_id::create``、``debug_rom.gen_program``、
  ``super.post_randomize``。
* **共享状态** ：写 ``debug_rom``、``instr_stream`` 和 illegal instruction 的
  ``comment``。

§7  ``eh2_log_to_trace_csv.py``
--------------------------------------------------------------------------------

§7.1  模块导入与正则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该脚本把 EH2 仿真日志转换为 riscv-dv 标准 trace CSV。脚本临时把
``vendor/google_riscv-dv/scripts`` 放进 ``sys.path``，导入 CSV writer 和工具函数后
恢复原 ``sys.path``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L8-L33``）：

.. code-block:: python

   import argparse
   import os
   import re
   import sys

   _EH2_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__),
                                              '../../../..'))
   _DV_SCRIPTS = os.path.join(_EH2_ROOT, 'vendor/google_riscv-dv/scripts')
   _OLD_SYS_PATH = sys.path

   # Import riscv_trace_csv and lib from _DV_SCRIPTS before putting sys.path back
   # as it started.
   try:
       sys.path.insert(0, _DV_SCRIPTS)

       from riscv_trace_csv import (RiscvInstructionTraceCsv,
                                    RiscvInstructionTraceEntry,
                                    get_imm_hex_val)
       from lib import RET_FATAL, gpr_to_abi, sint_to_hex, convert_pseudo_instr
       import logging
       logger = logging.getLogger(__name__)

   finally:
       sys.path = _OLD_SYS_PATH

   from test_run_result import Failure_Modes

**逐段解释** ：

* 第 8-L15 行：脚本计算 EH2 repo 根目录和 riscv-dv scripts 目录。路径从当前文件
  所在目录向上四级，再拼接 ``vendor/google_riscv-dv/scripts``。
* 第 16-L31 行：脚本保存旧 ``sys.path``，临时插入 riscv-dv scripts 目录并导入
  ``RiscvInstructionTraceCsv``、``RiscvInstructionTraceEntry``、
  ``get_imm_hex_val``、``RET_FATAL``、``gpr_to_abi``、``sint_to_hex``、
  ``convert_pseudo_instr``。``finally`` 中恢复 ``sys.path``。
* 第 33 行：``Failure_Modes`` 从本地 ``test_run_result`` 导入，用于 UVM log
  pass/fail 分类。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L35-L45``）：

.. code-block:: python

   # EH2 trace line format:
   #   <time> <cycle> <pc> <binary> <instr> <operands...>
   # Example:
   #   1234  567  80000080  00a00093  li      ra,10
   INSTR_RE = \
       re.compile(r"^\s*(?P<time>\d+)\s+(?P<cycle>\d+)\s+(?P<pc>[0-9a-f]+)\s+"
                  r"(?P<bin>[0-9a-f]+)\s+(?P<instr>\S+\s+\S+)\s*")
   RD_RE = re.compile(r"(x(?P<rd>[1-9]\d*)=0x(?P<rd_val>[0-9a-f]+))")
   ADDR_RE = re.compile(r"(?P<rd>[a-z0-9]+?),"
                        r"(?P<imm>[\-0-9]+?)"
                        r"\((?P<rs1>[a-z0-9]+)\)")

**逐段解释** ：

* 第 39-L41 行：``INSTR_RE`` 捕获 time、cycle、pc、binary 和 instruction 字符串。
  instruction 捕获使用 ``\S+\s+\S+``，要求 mnemonic 后至少有一个 operand 字段。
* 第 42 行：``RD_RE`` 捕获 ``x<rd>=0x<rd_val>`` 形式的 GPR 写回。x0 不匹配，
  因为寄存器编号正则从 ``[1-9]`` 开始。
* 第 43-L45 行：``ADDR_RE`` 捕获 ``rd,imm(rs1)`` 形式，用于 load/store operand
  展开。

**接口关系** ：

* **被调用** ：CLI ``main``、回归脚本或 coverage 流程调用该模块。
* **调用** ：导入 riscv-dv 的 CSV writer、pseudo instruction 转换和 ABI 寄存器映射。
* **共享状态** ：临时修改 ``sys.path``；正则常量被后续函数读取。

§7.2  ``_process_eh2_sim_log_fd()`` 与 ``process_eh2_sim_log()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：前者处理已打开的 log/csv 文件对象，逐行提取 instruction trace；
后者处理路径、打开文件并在日志不存在或没有 instruction 时抛出异常。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L48-L93``）：

.. code-block:: python

   def _process_eh2_sim_log_fd(log_fd, csv_fd, full_trace=True):
       """Process EH2 simulation log.

       Reads from log_fd, which should be a file object containing a trace from an
       EH2 simulation. Writes in a standard CSV format to csv_fd, which should be
       a file object opened for writing.

       If full_trace is true, this dumps information about operands, replacing
       absolute branch destinations with offsets relative to the current pc.

       """
       instr_cnt = 0

       trace_csv = RiscvInstructionTraceCsv(csv_fd)
       trace_csv.start_new_trace()

       trace_entry = None

       for line in log_fd:
           if re.search("ecall", line):
               break

**逐段解释** ：

* 第 48-L58 行：docstring 说明输入是 EH2 仿真 trace 文件对象，输出是标准 CSV
  文件对象；``full_trace`` 为真时会展开 operand，并把 branch destination 转为
  相对当前 PC 的 offset。
* 第 59-L63 行：初始化 instruction 计数，创建 ``RiscvInstructionTraceCsv``，
  并调用 ``start_new_trace``。
* 第 66-L68 行：逐行扫描 log；一旦行内包含 ``ecall``，函数停止处理后续 trace。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L70-L93``）：

.. code-block:: python

           # Extract instruction information
           m = INSTR_RE.search(line)
           if m is None:
               continue

           instr_cnt += 1
           # Write the extracted instruction to a csv buffer
           trace_entry = RiscvInstructionTraceEntry()
           trace_entry.instr_str = m.group("instr")
           trace_entry.instr = m.group("instr").split()[0]
           trace_entry.pc = m.group("pc")
           trace_entry.binary = m.group("bin")
           if full_trace:
               expand_trace_entry(trace_entry, m.group("instr").split()[1])

           c = RD_RE.search(line)
           if c:
               abi_name = gpr_to_abi("x{}".format(c.group("rd")))
               gpr_entry = "{}:{}".format(abi_name, c.group("rd_val"))
               trace_entry.gpr.append(gpr_entry)

           trace_csv.write_trace_entry(trace_entry)

       return instr_cnt

**逐段解释** ：

* 第 71-L74 行：只有匹配 ``INSTR_RE`` 的行才进入转换；不匹配的 log 行被跳过。
* 第 75-L83 行：函数创建 ``RiscvInstructionTraceEntry``，填入原始 instruction
  字符串、mnemonic、PC 和 binary。``full_trace`` 为真时调用
  ``expand_trace_entry`` 展开 operand。
* 第 85-L89 行：如果行内匹配 GPR 写回，脚本把 x 寄存器名转为 ABI 名，并以
  ``abi:value`` 形式追加到 ``trace_entry.gpr``。
* 第 91-L93 行：每条 entry 写入 CSV，函数返回处理到的 instruction 数。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L96-L115``）：

.. code-block:: python

   def process_eh2_sim_log(eh2_log, csv, full_trace=1):
       """Process EH2 simulation log.

       Extract instruction and affected register information from EH2 simulation
       log and save to a standard CSV format.
       """
       logging.info("Processing EH2 log : %s" % eh2_log)
       try:
           with open(eh2_log, "r") as log_fd, open(csv, "w") as csv_fd:
               count = _process_eh2_sim_log_fd(log_fd, csv_fd,
                                               True if full_trace else False)
       except FileNotFoundError:
           raise RuntimeError("Logfile %s not found" % eh2_log)

       logging.info("Processed instruction count : %d" % count)
       if not count:
           raise RuntimeError("No instructions in logfile: %s" % eh2_log)

       logging.info("CSV saved to : %s" % csv)

**逐段解释** ：

* 第 102-L106 行：包装函数打开 log 和 CSV 路径，再把文件对象传给
  ``_process_eh2_sim_log_fd``。``full_trace`` 被转换成布尔值。
* 第 107-L108 行：log 路径不存在时抛出 ``RuntimeError``。
* 第 110-L112 行：如果处理条数为 0，同样抛出 ``RuntimeError``，避免静默生成空 CSV。
* 第 114 行：成功写入后记录 CSV 路径日志。

**接口关系** ：

* **被调用** ：``main`` 调用底层 FD 函数；其他 Python 流程可以直接调用
  ``process_eh2_sim_log``。
* **调用** ：``_process_eh2_sim_log_fd`` 调用 ``expand_trace_entry``、
  ``gpr_to_abi``、``trace_csv.write_trace_entry``；包装函数调用 ``open``。
* **共享状态** ：读取模块级正则和 riscv-dv helper。

§7.3  operand 展开和 immediate 处理
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：这些函数把 raw x 寄存器 operand 转成 ABI 名称，把 pseudo instruction
转成 riscv-dv coverage 期望的形式，并将 branch/jump 绝对目标转换为 PC-relative
offset。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L117-L165``）：

.. code-block:: python

   def convert_operands_to_abi(operand_str):
       """Convert the operand string to use ABI register naming.

       At this stage in the conversion of the EH2 log to CSV format, the operand
       string is in this format:
           "x6,x6,1000".
       This function converts the register names to their ABI equivalents as shown
       below:
           "t1,t1,1000".
       This step is needed for the RISC-DV functional coverage step, as it assumes
       that all operand registers already follow the ABI naming scheme.

       Args:
           operand_str : A string of the operands for a given instruction

**逐段解释** ：

* 第 117-L128 行：docstring 明确输入形如 ``x6,x6,1000``，输出形如
  ``t1,t1,1000``；转换原因是 RISC-DV functional coverage 假设 operand 已采用
  ABI register naming。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L136-L165``）：

.. code-block:: python

       operand_list = operand_str.split(",")
       for i in range(len(operand_list)):
           converted_op = gpr_to_abi(operand_list[i])
           if converted_op != "na":
               operand_list[i] = converted_op
       return ",".join(operand_list)


   def expand_trace_entry(trace, operands):
       '''Expands a CSV trace entry for a single instruction.

       Operands are added to the CSV entry, converting from the raw
       register naming scheme (x0, x1, etc...) to ABI naming (a1, s1, etc...).

       '''
       operands = process_imm(trace.instr, trace.pc, operands)
       trace.instr, operands = \
           convert_pseudo_instr(trace.instr, operands, trace.binary)

       # process any instructions of the form:
       # <instr> <reg> <imm>(<reg>)

**逐段解释** ：

* 第 136-L141 行：函数按逗号拆分 operand；逐项调用 ``gpr_to_abi``。返回值不是
  ``na`` 时替换原 operand。
* 第 151-L153 行：``expand_trace_entry`` 先调用 ``process_imm``，再调用
  ``convert_pseudo_instr``，因此 immediate 规范化发生在 pseudo instruction
  转换之前。
* 第 155-L157 行：函数随后查找 ``rd,imm(rs1)`` 形式的地址 operand。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L157-L181``）：

.. code-block:: python

       n = ADDR_RE.search(operands)
       if n:
           trace.imm = get_imm_hex_val(n.group("imm"))
           operands = ','.join([n.group("rd"), n.group("rs1"), n.group("imm")])

       # Convert the operands into ABI format for the function coverage flow,
       # and store them into the CSV trace entry.
       trace.operand = convert_operands_to_abi(operands)


   def process_imm(instr_name, pc, operands):
       """Process imm to follow RISC-V standard convention"""
       if instr_name not in ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu', 'c.beqz',
                             'c.bnez', 'beqz', 'bnez', 'bgez', 'bltz', 'blez',
                             'bgtz', 'c.j', 'j', 'c.jal', 'jal']:
           return operands

**逐段解释** ：

* 第 157-L160 行：若 operand 符合 address 形式，脚本将 immediate 写入
  ``trace.imm``，并把 operand 重新排成 ``rd,rs1,imm``。
* 第 164 行：最终 operand 写入 trace 前统一经过 ``convert_operands_to_abi``。
* 第 169-L172 行：``process_imm`` 只处理 branch/jump 指令集合；非分支跳转指令
  原样返回 operand。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L174-L181``）：

.. code-block:: python

       idx = operands.rfind(',')
       if idx == -1:
           imm = operands
           return str(sint_to_hex(int(imm, 16) - int(pc, 16)))

       imm = operands[idx + 1:]
       imm = str(sint_to_hex(int(imm, 16) - int(pc, 16)))
       return operands[0:idx + 1] + imm

**逐段解释** ：

* 第 174-L177 行：如果 operand 中没有逗号，整个 operand 被视为目标地址，
  转为 ``target - pc`` 的 signed hex。
* 第 179-L181 行：如果有逗号，函数只取最后一个逗号后的字段作为目标地址，
  转为 PC-relative offset 后拼回原 operand 前缀。

**接口关系** ：

* **被调用** ：``_process_eh2_sim_log_fd`` 通过 ``expand_trace_entry`` 调用这些函数。
* **调用** ：调用 riscv-dv helper ``gpr_to_abi``、``convert_pseudo_instr``、
  ``get_imm_hex_val`` 和 ``sint_to_hex``。
* **共享状态** ：读取 ``ADDR_RE`` 和分支/跳转 mnemonic 列表。

§7.4  ``check_eh2_uvm_log()`` 与 CLI
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：``check_eh2_uvm_log`` 扫描 UVM log，按 pass/fail/error 关键行返回
``(passed, log_out, failure_mode)``。``main`` 提供 ``--log``、``--csv`` 和
``--full_trace`` 参数。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L184-L236``）：

.. code-block:: python

   def check_eh2_uvm_log(uvm_log):
       """Process EH2 UVM simulation log.

       Process the UVM simulation log produced by the test to check for
       correctness, reports failure if an explicit error or failure is seen in the
       log or there's no explicit pass.

       Args:
         uvm_log:   the uvm simulation log

       Returns:
         A tuple of (passed, log_out).
         `passed` indicates whether the test passed or failed based on the log.
         `log_out` a list of relevant lines from the log that may indicate the
         source of the failure, if `passed` is true it will be empty.

**逐段解释** ：

* 第 184-L199 行：docstring 说明函数读取 UVM 仿真 log，根据显式 error/failure 或
  缺少 pass 判断测试状态，并返回 pass 标志和相关 log 行。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L201-L256``）：

.. code-block:: python

       passed = False
       failed = False

       error_linenum = None
       error_line = None
       log_out = []
       failure_mode = Failure_Modes.NONE

       with open(uvm_log, "r") as log:
           # Simulation log has report summary at the end, which references
           # 'UVM_ERROR' which can cause false failures. The summary appears after
           # the test result so ignore any lines after the test result is seen for
           # 'UVM_ERROR' checking. If the loop terminated immediately when a test
           # result was seen it would miss issues where the test result is
           # (erroneously) repeated multiple times with different results.
           test_result_seen = False

**逐段解释** ：

* 第 201-L207 行：函数初始化 pass/fail 标志、错误位置、输出摘要和
  ``Failure_Modes.NONE``。
* 第 209-L216 行：读取 log 时设置 ``test_result_seen``。注释说明 UVM summary
  可能在测试结果后再次出现 ``UVM_ERROR`` 字样，因此 error 检查只在结果出现前有效。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L218-L256``）：

.. code-block:: python

           for linenum, line in enumerate(log, 1):
               if ('UVM_ERROR' in line or
                   'UVM_FATAL' in line or
                   'Error' in line) \
                       and not test_result_seen:
                   error_linenum = linenum
                   error_line = line
                   failed = True

               if 'RISC-V UVM TEST PASSED' in line:
                   test_result_seen = True
                   passed = True

               if 'RISC-V UVM TEST FAILED' in line:
                   test_result_seen = True
                   failed = True
                   break

**逐段解释** ：

* 第 218-L225 行：在测试结果出现前，如果行包含 ``UVM_ERROR``、``UVM_FATAL`` 或
  ``Error``，函数记录错误行号和内容，并设置 ``failed``。
* 第 227-L229 行：出现 ``RISC-V UVM TEST PASSED`` 时设置 ``test_result_seen`` 和
  ``passed``。
* 第 231-L234 行：出现 ``RISC-V UVM TEST FAILED`` 时设置 failed 并退出循环。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L236-L256``）：

.. code-block:: python

           if failed:
               # If we saw PASSED and FAILED, that's a bit odd. But we should treat
               # the test as having failed.
               passed = False
               # If we know where the line marking the error is ... :
               # - Extract a useful subset of log lines for a short summary of the
               #   error (-5, +5 lines around the detected error line above)
               if error_linenum is not None:
                   log.seek(0)  # Needed to enumerate() over the log a second time.
                   log_out = ["{0}{1}: {2}".format(
                                   "[E] " if (linenum == error_linenum) else "    ",
                                   linenum, line.strip())
                              for linenum, line in enumerate(log, 1)
                              if linenum in range(error_linenum-5, error_linenum+5)]

**逐段解释** ：

* 第 236-L239 行：只要 ``failed`` 为真，``passed`` 会被强制清零，即使之前已经
  看见 pass 行。
* 第 243-L249 行：如果记录了错误行号，函数重新 seek 到文件开头，提取错误行
  前后约 5 行，并在错误行前加 ``[E]`` 标记。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L251-L283``）：

.. code-block:: python

               if ('Test failed due to wall-clock timeout.' in error_line):
                   failure_mode = Failure_Modes.TIMEOUT
               else:
                   failure_mode = Failure_Modes.LOG_ERROR

       return (passed, log_out, failure_mode)


   def main():
       parser = argparse.ArgumentParser()
       parser.add_argument("--log",
                           help="Input EH2 simulation log (default: stdin)",
                           type=argparse.FileType('r'),
                           default=sys.stdin)
       parser.add_argument("--csv",

**逐段解释** ：

* 第 251-L254 行：错误行包含 wall-clock timeout 文本时，failure mode 为
  ``TIMEOUT``；其他错误统一为 ``LOG_ERROR``。
* 第 256 行：函数返回三元组 ``passed``、``log_out``、``failure_mode``。
* 第 259-L266 行：CLI 创建 argparse parser，并定义 ``--log`` 和 ``--csv``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L265-L283``）：

.. code-block:: python

       parser.add_argument("--csv",
                           help="Output trace csv file (default: stdout)",
                           type=argparse.FileType('w'),
                           default=sys.stdout)
       parser.add_argument("--full_trace", type=int, default=1,
                           help="Enable full log trace")

       args = parser.parse_args()

       _process_eh2_sim_log_fd(args.log, args.csv,
                               True if args.full_trace else False)


   if __name__ == "__main__":
       try:
           main()
       except RuntimeError as err:
           sys.stderr.write('Error: {}\n'.format(err))
           sys.exit(RET_FATAL)

**逐段解释** ：

* 第 265-L270 行：``--csv`` 默认 stdout，``--full_trace`` 是 int 参数，默认 1。
* 第 272-L275 行：CLI 直接调用 ``_process_eh2_sim_log_fd``，传入 argparse 打开的
  文件对象。
* 第 278-L283 行：脚本入口捕获 ``RuntimeError``，向 stderr 写 ``Error: ...``，
  并以 riscv-dv 的 ``RET_FATAL`` 退出。

**接口关系** ：

* **被调用** ：回归结果检查可调用 ``check_eh2_uvm_log``；命令行执行脚本调用
  ``main``。
* **调用** ：调用 ``argparse``、``_process_eh2_sim_log_fd`` 和 ``sys.exit``。
* **共享状态** ：读取 ``Failure_Modes``、``RET_FATAL``。

§8  链接脚本与 OVPsim 配置
--------------------------------------------------------------------------------

§8.1  ``ddm_link.ld`` — discrete debug module 地址布局
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 linker script 把普通 test program 放入 ``main`` memory，把
``.debug_module`` 和 ``.dm_scratch`` 放入 ``dm`` memory。源码注释说明它用于
``+discrete_debug_module=1`` 的离散 debug module 场景。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ddm_link.ld:L17-L27``）：

.. code-block:: bash

   OUTPUT_ARCH( "riscv" )
   ENTRY(_start)

   MEMORY
   {
     main : ORIGIN = 0x80000000, LENGTH = 0x100000
     dm   : ORIGIN = 0x1A110000, LENGTH = 0x1000
   }

   _dm_scratch_len = 0x100;

**逐段解释** ：

* 第 17-L18 行：输出架构是 ``riscv``，入口符号是 ``_start``，与
  ``gen_program_header`` 生成的 ``_start:`` 标签对应。
* 第 20-L24 行：``main`` memory 从 ``0x80000000`` 开始，长度 ``0x100000``；
  ``dm`` memory 从 ``0x1A110000`` 开始，长度 ``0x1000``。
* 第 26 行：debug module scratch 区长度为 ``0x100``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ddm_link.ld:L28-L68``）：

.. code-block:: bash

   SECTIONS
   {
     .text : {
       *(.text)
       . = ALIGN(0x1000);
     } >main
     .tohost : {
       . = ALIGN(4);
       *(.tohost)
       . = ALIGN(0x1000);
     } >main
     .page_table : {
       *(.page_table)
     } >main
     .data : {
       *(.data)
     } >main
     .user_stack : {

**逐段解释** ：

* 第 30-L38 行：``.text`` 和 ``.tohost`` 都映射到 ``main``，并做页/字对齐。
* 第 39-L47 行：``.page_table``、``.data``、``.user_stack`` 继续映射到
  ``main``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ddm_link.ld:L48-L68``）：

.. code-block:: bash

     .kernel_data : {
       *(.kernel_data)
     } >main
     .kernel_stack : {
       *(.kernel_stack)
     } >main
     .bss : {
       *(.bss)
     } >main

     _end = .;

     .debug_module : {
       *(.debug_module)
     } >dm
     .dm_scratch : {
       . = ALIGN(4);
       . = . + _dm_scratch_len ;
       . = ALIGN(4);
       } >dm =0
   }

**逐段解释** ：

* 第 48-L56 行：``.kernel_data``、``.kernel_stack`` 和 ``.bss`` 也放入
  ``main``。
* 第 58 行：``_end`` 记录 main 区当前地址。
* 第 60-L67 行：``.debug_module`` 和 ``.dm_scratch`` 放入 ``dm``；
  ``.dm_scratch`` 先 4 字节对齐，再预留 ``_dm_scratch_len``，最后以填充值 0
  结束 section。

**接口关系** ：

* **被调用** ：debug/discrete debug module 相关 ELF link 流程使用该脚本。
* **调用** ：linker script 不调用函数。
* **共享状态** ：入口符号 ``_start`` 由 ``eh2_asm_program_gen`` 生成；
  ``.debug_module`` section 由 debug 生成逻辑产生。

§8.2  ``riscvOVPsim.ic`` — OVPsim ISA 与 CSR 行为配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该配置文件把 OVPsim 目标设置为 RV32IMAC，并打开 Zba/Zbb/Zbc/Zbs
扩展、unaligned、mtvec mask、reset address、WFI 行为和 32-bit address space。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscvOVPsim.ic:L1-L25``）：

.. code-block:: bash

   # riscvOVPsim configuration file for EH2 (VeeR) core
   # Converted from YAML and adapted for RV32IMAC + Zba/Zbb/Zbc/Zbs
   --variant RV32IMAC
   --override riscvOVPsim/cpu/add_Extensions=Zba+Zbb+Zbc+Zbs
   --override riscvOVPsim/cpu/misa_MXL=1
   --override riscvOVPsim/cpu/misa_MXL_mask=0x0 # 0
   --override riscvOVPsim/cpu/misa_Extensions_mask=0x0 # 0
   --override riscvOVPsim/cpu/unaligned=T
   --override riscvOVPsim/cpu/mtvec_mask=0xffffff03
   --override riscvOVPsim/cpu/tvec_align=256
   --override riscvOVPsim/cpu/user_version=2.3
   --override riscvOVPsim/cpu/priv_version=1.11
   --override riscvOVPsim/cpu/mvendorid=0
   --override riscvOVPsim/cpu/marchid=0
   --override riscvOVPsim/cpu/mimpid=0
   --override riscvOVPsim/cpu/mhartid=0
   --override riscvOVPsim/cpu/cycle_undefined=F
   --override riscvOVPsim/cpu/instret_undefined=F
   --override riscvOVPsim/cpu/time_undefined=F
   --override riscvOVPsim/cpu/reset_address=0x80000000
   --override riscvOVPsim/cpu/simulateexceptions=T
   --override riscvOVPsim/cpu/defaultsemihost=F
   --override riscvOVPsim/cpu/wfi_is_nop=T
   --override riscvOVPsim/cpu/tval_ii_code=T
   --addressbits 32

**逐段解释** ：

* 第 3-L4 行：base variant 是 ``RV32IMAC``，额外 extension 字符串为
  ``Zba+Zbb+Zbc+Zbs``。
* 第 5-L10 行：MXL、misa mask、unaligned 和 ``mtvec`` 相关行为通过
  ``--override`` 设置。
* 第 11-L16 行：user/priv spec version 和 vendor/arch/imp/hart ID 都在配置中
  显式设置。
* 第 17-L25 行：cycle/instret/time 不设为 undefined；reset address 是
  ``0x80000000``；``simulateexceptions`` 打开，``defaultsemihost`` 关闭，
  ``wfi_is_nop`` 打开，地址宽度为 32。

**接口关系** ：

* **被调用** ：OVPsim/ISS 相关流程读取该配置。
* **调用** ：配置文件不调用函数。
* **共享状态** ：ISA 扩展、unaligned 和 reset address 与 core setting、
  linker script 和 generated assembly header 保持同一地址/能力语义。

§9  YAML testlist
--------------------------------------------------------------------------------

§9.1  ``testlist.yaml`` — 常规回归清单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该文件列出 riscv-dv/RTL 回归测试项。每个条目以 ``test`` 命名，并可
包含 ``description``、``gen_test``、``gen_opts``、``rtl_test``、``sim_opts``、
``test_srcs``、``cosim``、``iterations`` 和 ``skip_in_signoff``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L1-L37``）：

.. code-block:: yaml

   - test: riscv_arithmetic_basic_test
     description: Basic arithmetic instruction test
     gen_test: riscv_instr_base_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +no_csr_instr=1

       '
     rtl_test: core_eh2_base_test
     iterations: 10
   - test: riscv_random_instr_test
     description: Random instruction mix test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=20000 +boot_mode=m +enable_interrupt=1 +enable_nested_interrupt=1

       '
     rtl_test: core_eh2_base_test
     sim_opts: '+max_cycles=2000000 +timeout_ns=200000000

**逐段解释** ：

* 第 1-L8 行：``riscv_arithmetic_basic_test`` 使用 ``riscv_instr_base_test``，
  生成参数包括 ``+instr_cnt=10000``、``+boot_mode=m`` 和 ``+no_csr_instr=1``，
  RTL test 是 ``core_eh2_base_test``，迭代数 10。
* 第 9-L19 行：``riscv_random_instr_test`` 使用 ``riscv_rand_instr_test``，
  开启 interrupt 和 nested interrupt 生成，并设置 RTL 最大 cycle/timeout。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L28-L53``）：

.. code-block:: yaml

   - test: riscv_csr_test
     description: CSR read/write test
     gen_test: riscv_instr_base_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_csr_write=1 +directed_instr_0=eh2_csr_access_stream,10

       '
     rtl_test: core_eh2_base_test
     cosim: disabled
     iterations: 5
     skip_in_signoff: true
   - test: riscv_load_store_test
     description: Load/store instruction test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=15000 +boot_mode=m +directed_instr_0=riscv_load_store_rand_instr_stream,30

       '
     rtl_test: core_eh2_base_test
     iterations: 10

**逐段解释** ：

* 第 28-L37 行：CSR 测试显式开启 ``+enable_csr_write=1``，并注入
  ``eh2_csr_access_stream``。该条目标记 ``cosim: disabled`` 且
  ``skip_in_signoff: true``。
* 第 38-L53 行：load/store 测试使用 riscv-dv 内建
  ``riscv_load_store_rand_instr_stream``，迭代数 10。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L63-L105``）：

.. code-block:: yaml

   - test: riscv_bitmanip_test
     description: Bitmanip extension test — bounded EH2 bitmanip directed proof (R3-B)
     test_srcs: tests/asm/cosim_bitmanip.S
     rtl_test: core_eh2_base_test
     sim_opts: '+max_cycles=2000000 +timeout_ns=200000000

       '
     iterations: 10

   - test: riscv_bitmanip_full_test
     description: Bitmanip full intensity — bounded EH2 bitmanip directed proof (R3-B)
     test_srcs: tests/asm/cosim_bitmanip.S
     rtl_test: core_eh2_base_test
     sim_opts: '+max_cycles=2000000 +timeout_ns=200000000

       '

**逐段解释** ：

* 第 63-L70 行：``riscv_bitmanip_test`` 不是通过 ``gen_test`` 生成，而是直接使用
  ``tests/asm/cosim_bitmanip.S``，RTL test 为 ``core_eh2_base_test``。
* 第 72-L79 行：``riscv_bitmanip_full_test`` 使用同一个 assembly 源和相同
  sim timeout 设置，但迭代数为 5。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L81-L116``）：

.. code-block:: yaml

   - test: riscv_bitmanip_balanced_test
     description: Bitmanip balanced intensity — bounded EH2 bitmanip directed proof (R3-B)
     test_srcs: tests/asm/cosim_bitmanip.S
     rtl_test: core_eh2_base_test
     sim_opts: '+max_cycles=2000000 +timeout_ns=200000000

       '
     iterations: 5

   - test: riscv_bitmanip_otearlgrey_test
     description: Bitmanip OT EARLGREY closure — bounded EH2 bitmanip directed proof (R3-B)
     test_srcs: tests/asm/cosim_bitmanip.S
     rtl_test: core_eh2_base_test

**逐段解释** ：

* 第 81-L88 行：balanced bitmanip 项仍使用 ``cosim_bitmanip.S``，迭代数 5。
* 第 90-L97 行：OT EARLGREY closure 项同样使用 ``cosim_bitmanip.S``，通过命名
  区分覆盖意图，代码层面的入口仍是同一个 assembly。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L98-L127``）：

.. code-block:: yaml

   - test: riscv_amo_test
     description: Atomic LR/SC test — bounded directed AMO proof (R3-B)
     test_srcs: tests/asm/cosim_atomic_basic.S
     rtl_test: core_eh2_base_test
     sim_opts: '+max_cycles=2000000 +timeout_ns=200000000

       '
     iterations: 5
   - test: riscv_interrupt_test
     description: Random interrupt test — cosim enabled (issue 53 interrupt cosim)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=20000 +boot_mode=m +enable_interrupt=1 +enable_nested_interrupt=1 +directed_instr_0=eh2_pic_int_stream,5

       '
     rtl_test: core_eh2_base_test

**逐段解释** ：

* 第 98-L105 行：atomic 测试使用手写 ``tests/asm/cosim_atomic_basic.S``，不是
  ``eh2_atomic_stream``。
* 第 106-L116 行：interrupt 测试使用 ``riscv_rand_instr_test``，开启
  ``+enable_interrupt=1``、``+enable_nested_interrupt=1``，并注入
  ``eh2_pic_int_stream``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L128-L160``）：

.. code-block:: yaml

   - test: riscv_debug_test
     description: Debug mode entry/exit test — cosim enabled (issue 54)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m

       '
     rtl_test: core_eh2_base_test
     sim_opts: '+enable_debug_seq=1 +max_interval=1000

       '
     iterations: 5
   - test: riscv_debug_csr_test
     description: Debug CSR access test — cosim enabled (issue 54)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=5000 +boot_mode=m +directed_instr_0=eh2_debug_csr_stream,5

**逐段解释** ：

* 第 128-L138 行：debug entry/exit 测试在 RTL 仿真侧打开 ``+enable_debug_seq=1``
  并设置 ``+max_interval=1000``。
* 第 139-L149 行：debug CSR 测试通过 ``+directed_instr_0=eh2_debug_csr_stream,5``
  注入 debug CSR stream，并同样打开 debug sequence。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L169-L202``）：

.. code-block:: yaml

   - test: riscv_exception_test
     description: Exception handling test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_illegal_instruction=1 +enable_ebreak=1 +enable_unaligned_load_store=1

       '
     rtl_test: core_eh2_base_test
     iterations: 5
   - test: riscv_breakpoint_test
     description: Breakpoint instruction test — bounded directed ebreak proof (R3-B)
     test_srcs: tests/asm/directed_debug_basic.S
     rtl_test: core_eh2_base_test
     sim_opts: '+enable_debug_seq=1 +max_interval=1000 +max_cycles=2000000 +timeout_ns=200000000

**逐段解释** ：

* 第 169-L176 行：exception test 打开 illegal instruction、EBREAK 和 unaligned
  load/store 生成。
* 第 177-L184 行：breakpoint test 使用手写 ``tests/asm/directed_debug_basic.S``，
  并在仿真侧打开 debug sequence 与 timeout 限制。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L185-L226``）：

.. code-block:: yaml

   - test: riscv_csr_hazard_test
     description: CSR pipeline hazard test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +directed_instr_0=eh2_csr_hazard_stream,15

       '
     rtl_test: core_eh2_base_test
     cosim: disabled
     iterations: 5
     skip_in_signoff: true
   - test: riscv_exception_stream_test
     description: Directed exception stream test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=5000 +boot_mode=m +directed_instr_0=eh2_exception_stream,10

**逐段解释** ：

* 第 185-L194 行：CSR hazard test 注入 ``eh2_csr_hazard_stream``，但该条目标记
  ``cosim: disabled`` 和 ``skip_in_signoff: true``。
* 第 195-L202 行：exception stream test 注入 ``eh2_exception_stream``，迭代数 3。
* 第 203-L226 行：PMP basic、disable-all 和 random 项通过 ``+enable_pmp=1``、
  ``+pmp_num_regions`` 等 ``gen_opts`` 进入 PMP 专项 RTL test。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L298-L336``）：

.. code-block:: yaml

   - test: riscv_rf_addr_intg_test
     description: Register file address integrity fault injection (issue 61)
     gen_test: riscv_instr_base_test
     gen_opts: '+instr_cnt=5000 +boot_mode=m

       '
     rtl_test: core_eh2_rf_addr_intg_test
     cosim: rtl_only
     iterations: 3

   - test: riscv_ram_intg_test
     description: DCCM/ICCM RAM ECC/parity integrity test (issue 61)
     gen_test: riscv_instr_base_test
     gen_opts: '+instr_cnt=5000 +boot_mode=m

**逐段解释** ：

* 第 298-L306 行：register file address integrity 项使用
  ``core_eh2_rf_addr_intg_test``，并标记 ``cosim: rtl_only``。
* 第 308-L336 行：RAM、ICache 和 generic memory integrity 相关项同样使用
  ``cosim: rtl_only``，表示这些条目走 RTL-only 边界。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L338-L389``）：

.. code-block:: yaml

   - test: riscv_debug_wfi_test
     description: Debug request during WFI instruction — cosim enabled (issue 54)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_wfi=1

       '
     rtl_test: core_eh2_debug_wfi_test
     sim_opts: '+enable_debug_seq=1

       '
     iterations: 5
   - test: riscv_debug_during_csr_test
     description: Debug request during CSR access — cosim enabled (issue 54)

**逐段解释** ：

* 第 338-L348 行：debug during WFI 项打开 ``+enable_wfi=1``，RTL test 为
  ``core_eh2_debug_wfi_test``，仿真侧打开 debug sequence。
* 第 349-L389 行：debug/IRQ during CSR、WFI 和 nested IRQ 等条目通过不同
  ``rtl_test`` 与 ``sim_opts`` 组合覆盖 debug 与 interrupt 交互。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L401-L455``）：

.. code-block:: yaml

   - test: riscv_irq_in_debug_test
     description: Interrupt during debug mode — cosim enabled (issues 53, 54)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_interrupt=1

       '
     rtl_test: core_eh2_irq_in_debug_test
     sim_opts: '+enable_irq_seq=1 +enable_debug_seq=1

       '
     iterations: 5
   - test: riscv_debug_in_irq_test
     description: Debug request during IRQ handler — cosim enabled (issues 53, 54)

**逐段解释** ：

* 第 401-L411 行：interrupt during debug 使用 ``core_eh2_irq_in_debug_test``，
  同时打开 ``+enable_irq_seq=1`` 和 ``+enable_debug_seq=1``。
* 第 412-L455 行：debug in IRQ、DRET、debug ebreakm/u、single debug pulse
  分别用相应 RTL test 和 debug plusarg 组合覆盖 debug 入口/返回场景。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L472-L555``）：

.. code-block:: yaml

   - test: riscv_jump_stress_test
     description: Stress back-to-back jump instruction test
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=8000 +boot_mode=m +directed_instr_0=riscv_jal_instr,20

       '
     rtl_test: core_eh2_base_test
     cosim: enabled
     iterations: 10

   - test: riscv_debug_triggers_test
     description: Hardware breakpoint trigger test with directed breakpoint sequence — cosim enabled (issue 54)

**逐段解释** ：

* 第 472-L480 行：jump stress test 注入 riscv-dv 内建 ``riscv_jal_instr``，
  并显式标记 ``cosim: enabled``。
* 第 482-L493 行：debug triggers test 注入 ``eh2_breakpoint_stream``，RTL test 为
  ``core_eh2_single_debug_pulse_test``，仿真侧打开 ``+enable_debug_seq=1``。
* 第 495-L555 行：文件末尾继续列出 debug stress、debug branch/jump、
  debug CSR entry、assorted trap/interrupt/debug 和 PMP out-of-bounds。最后一项
  ``riscv_pmp_out_of_bounds_test`` 的 ``iterations`` 为 50。

**接口关系** ：

* **被调用** ：回归脚本读取该 YAML，按 ``test`` 条目生成 riscv-dv 程序和 RTL
  仿真命令。
* **调用** ：YAML 不调用函数，但 ``gen_opts`` 中引用 SV stream 类名。
* **共享状态** ：``rtl_test`` 名称对应 UVM test；``test_srcs`` 对应 assembly；
  ``directed_instr`` 名称对应 ``user_extension.svh`` 包含的类。

§9.2  ``cov_testlist.yaml`` — instruction coverage 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该文件只定义两个 coverage 测试。二者都关闭 ISS、GCC 和 post compare，
因为它们从 CSV trace 采样 coverage，而不是生成可执行随机程序再比较 ISS。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/cov_testlist.yaml:L1-L18``）：

.. code-block:: yaml

   - test: riscv_instr_cov_debug_test
     description: >
       Functional coverage debug test, this is not a functional test to the core.
     iterations: 1
     gen_test: riscv_instr_cov_debug_test
     no_iss: 1
     no_gcc: 1
     no_post_compare: 1

   - test: riscv_instr_cov_test
     description: >
       Parse the instruction information from the CSV trace log, sample functional
       coverage from the instruction trace.
     iterations: 1
     gen_test: riscv_instr_cov_test
     no_iss: 1
     no_gcc: 1
     no_post_compare: 1

**逐段解释** ：

* 第 1-L8 行：debug coverage test 的描述明确说它不是 core functional test；
  ``iterations`` 为 1，``no_iss/no_gcc/no_post_compare`` 全部为 1。
* 第 10-L18 行：普通 instruction coverage test 从 CSV trace 解析 instruction
  information 并采样 functional coverage，同样关闭 ISS、GCC 和 post compare。

**接口关系** ：

* **被调用** ：coverage flow 读取该 YAML。
* **调用** ：YAML 不调用函数；``gen_test`` 名称由 riscv-dv coverage test 实现解析。
* **共享状态** ：依赖 ``eh2_log_to_trace_csv.py`` 或等价流程产出的 CSV trace。

§9.3  ``ml_testlist.yaml`` — 参数密集回归项
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该文件定义 5 个 ML 风格条目，集中展开 riscv-dv 的大量 generator
开关。与常规 testlist 相比，它显式写出 directed stream 名称、频率、debug/IRQ
plusarg、GCC 选项和 no-post-compare 边界。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml:L62-L119``）：

.. code-block:: yaml

   - test: riscv_rand_test
     description: >
       Random test with all useful knobs
     gen_opts: >
       +instr_cnt=10000
       +num_of_sub_program=5
       +enable_write_pmp_csr=1
       +illegal_instr_ratio=5
       +hint_instr_ratio=5
       +no_ebreak=0
       +no_dret=0
       +no_wfi=0
       +set_mstatus_tw=0
       +no_branch_jump=0
       +no_csr_instr=0

**逐段解释** ：

* 第 62-L65 行：``riscv_rand_test`` 的描述是 “Random test with all useful
  knobs”，使用 folded scalar 写长 ``gen_opts``。
* 第 66-L77 行：前半段 generator 选项设置 instruction count、sub-program 数、
  PMP CSR 写、illegal/hint ratio，并允许 EBREAK、DRET、WFI、branch/jump 和 CSR
  instruction。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml:L78-L119``）：

.. code-block:: yaml

       +fix_sp=0
       +enable_illegal_csr_instruction=0
       +enable_access_invalid_csr_level=0
       +enable_misaligned_instr=0
       +enable_dummy_csr_write=0
       +no_data_page=0
       +no_directed_instr=0
       +no_fence=0
       +enable_unaligned_load_store=1
       +disable_compressed_instr=0
       +randomize_csr=0
       +enable_b_extension=1
       +enable_bitmanip_groups=zbb,zb_tmp,zbt,zbs,zbp,zbf,zbe,zbc,zbr
       +boot_mode=m
       +stream_name_0=riscv_load_store_rand_instr_stream
       +stream_freq_0=4

**逐段解释** ：

* 第 78-L90 行：继续设置 stack pointer、illegal CSR、data page、fence、
  unaligned、compressed、CSR randomization、B extension 和 bitmanip group。
* 第 91-L113 行：该条目列出 11 个 riscv-dv 内建 stream 名称和频率，频率均为 4。
* 第 113-L119 行：条目迭代数为 1，关闭 ISS 和 post compare，GCC 选项包含
  ``-mno-strict-align``，RTL test 是 ``core_eh2_reset_test``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml:L150-L218``）：

.. code-block:: yaml

   - test: riscv_rand_debug_test
     description: >
       Random debug test with all useful knobs
     gen_opts: >
       +require_signature_addr=1
       +gen_debug_section=1
       +num_debug_sub_program=1
       +enable_ebreak_in_debug_rom=0
       +set_dcsr_ebreak=0
       +enable_debug_single_step=1
       +instr_cnt=10000
       +num_of_sub_program=5
       +enable_write_pmp_csr=1

**逐段解释** ：

* 第 150-L160 行：debug ML 条目要求 signature address、生成 debug section、
  debug sub-program 数为 1，打开 debug single step。
* 第 161-L184 行：该条目继续继承随机测试的大量开关，但把
  ``illegal_instr_ratio`` 设为 0，并设置 ``+no_ebreak=1``、``+no_dret=1``。
* 第 213-L218 行：``sim_opts`` 包含 ``+require_signature_addr=1``、
  ``+max_interval=100000``、``+enable_debug_seq=1``，RTL test 是
  ``core_eh2_debug_intr_basic_test``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml:L241-L308``）：

.. code-block:: yaml

   - test: riscv_rand_irq_test
     description: >
       Random test with all useful knobs
     gen_opts: >
       +require_signature_addr=1
       +enable_interrupt=1
       +enable_timer_irq=1
       +enable_nested_interrupt=1
       +instr_cnt=10000
       +enable_write_pmp_csr=1
       +num_of_sub_program=5
       +illegal_instr_ratio=0
       +hint_instr_ratio=5

**逐段解释** ：

* 第 241-L249 行：IRQ ML 条目要求 signature address，打开 interrupt、timer IRQ
  和 nested interrupt。
* 第 250-L297 行：其余 generator 选项包含 PMP CSR 写、sub-program、hint ratio、
  WFI、CSR、unaligned、bitmanip 和 stream 频率。
* 第 302-L307 行：``sim_opts`` 打开 ``+require_signature_addr=1``、
  ``+enable_irq_single_seq=1``、关闭 multiple IRQ seq，并打开 nested IRQ；
  RTL test 是 ``core_eh2_nested_irq_test``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml:L330-L405``）：

.. code-block:: yaml

   - test: riscv_rand_mem_error_test
     description: >
       Randomly insert memory bus errors in both IMEM and DMEM.
     gen_opts: >
       +instr_cnt=10000
       +num_of_sub_program=5
       +require_signature_addr=1
       +enable_write_pmp_csr=1
       +illegal_instr_ratio=0
       +hint_instr_ratio=5
       +no_ebreak=1
       +no_dret=1
       +no_wfi=1

**逐段解释** ：

* 第 330-L342 行：memory error ML 条目描述为随机插入 IMEM 和 DMEM bus error；
  它要求 signature address，关闭 EBREAK、DRET 和 WFI。
* 第 343-L390 行：其余选项包括 branch/CSR/load-store/bitmanip/stream 配置；
  RTL test 是 ``core_eh2_mem_error_test``，``sim_opts`` 只列出
  ``+require_signature_addr=1``。
* 第 399-L405 行：``riscv_csr_test`` 条目不展开 generator 参数；它使用
  ``core_eh2_csr_test``，关闭 ISS 和 post compare，迭代数 1。

**接口关系** ：

* **被调用** ：ML/参数探索类回归读取该 YAML。
* **调用** ：YAML 不调用函数；stream 名称由 riscv-dv generator 解析。
* **共享状态** ：``rtl_test`` 依赖 UVM test library；``gcc_opts``、``sim_opts``
  和 ``gen_opts`` 共同决定生成与仿真边界。

§10  ``csr_description.yaml``
--------------------------------------------------------------------------------

§10.1  标准 M-mode CSR 字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该 YAML 为 riscv-dv CSR test generation 描述 CSR 地址、字段、访问类型
和文字说明。它不是 RTL 寄存器实现，只是 generator/coverage 使用的 CSR 描述表。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L1-L39``）：

.. code-block:: yaml

   # SPDX-License-Identifier: Apache-2.0
   # EH2 CSR Description for riscv-dv
   #
   # Describes CSR fields for riscv-dv's CSR test generation.
   # Format: each CSR has address, name, and field descriptions.
   # Fields use [msb:lsb] or [bit] notation with type (R/W, RO, WARL, WLRL).

   # ---------------------------------------------------------------------------
   # Standard M-mode CSRs
   # ---------------------------------------------------------------------------
   - csr: mstatus
     address: 0x300
     description: "Machine status register"
     fields:
       - field: [3:0]

**逐段解释** ：

* 第 1-L6 行：文件头说明用途是 riscv-dv CSR test generation；字段格式使用
  ``[msb:lsb]`` 或 ``[bit]``，并带访问类型。
* 第 11-L18 行：``mstatus`` 地址为 ``0x300``，字段 ``mie`` 覆盖 ``[3:0]``，
  类型为 ``R/W``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L15-L39``）：

.. code-block:: yaml

       - field: [3:0]
         name: mie
         type: R/W
         description: "Machine interrupt enable (only bit 0 used, others 0)"
       - field: [7:4]
         name: mpie
         type: R/W
         description: "Machine previous interrupt enable"
       - field: [12:11]
         name: mpp
         type: RO
         description: "Machine previous privilege (hardwired to 3)"

   - csr: misa
     address: 0x301
     description: "ISA and extensions"
     fields:
       - field: [31:30]
         name: mxl
         type: RO

**逐段解释** ：

* 第 15-L26 行：``mstatus`` 描述 ``mie``、``mpie`` 和 ``mpp`` 字段；``mpp`` 类型
  是 ``RO``，描述中标明 hardwired to 3。
* 第 28-L39 行：``misa`` 地址 ``0x301``，字段包括 ``mxl`` 和 ``extensions``，
  二者类型均为 ``RO``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L41-L81``）：

.. code-block:: yaml

   - csr: mie
     address: 0x304
     description: "Machine interrupt enable"
     fields:
       - field: [0]
         name: msie
         type: R/W
         description: "Software interrupt enable"
       - field: [1]
         name: mtie
         type: R/W
         description: "Timer interrupt enable"
       - field: [2]
         name: meie
         type: R/W

**逐段解释** ：

* 第 41-L68 行：``mie`` 地址 ``0x304``，字段覆盖 software、timer、external、
  internal timer 和 correctable error interrupt enable。
* 第 70-L81 行：``mtvec`` 地址 ``0x305``，字段 ``base`` 是 ``[31:2]``，``mode``
  是 ``[1:0]``，二者类型都为 ``WARL``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L83-L120``）：

.. code-block:: yaml

   - csr: mcountinhibit
     address: 0x320
     description: "Counter inhibit register"
     fields:
       - field: [0]
         name: cy
         type: R/W
         description: "Inhibit mcycle"
       - field: [2]
         name: ir
         type: R/W
         description: "Inhibit minstret"
       - field: [6:3]
         name: hpm3to6
         type: R/W

**逐段解释** ：

* 第 83-L98 行：``mcountinhibit`` 描述 cycle、instret 和 hpm3-6 的 inhibit 位。
* 第 100-L120 行：``mscratch`` 和 ``mepc`` 条目描述 scratch register 和 exception
  PC；``mepc`` 的 bit 0 单独标为 ``RO`` always 0。

**接口关系** ：

* **被调用** ：riscv-dv CSR generator/coverage 读取该 YAML。
* **调用** ：YAML 不调用函数。
* **共享状态** ：CSR 地址必须与 ``riscv_core_setting.sv`` 的 implemented/custom
  CSR 列表一致。

§10.2  ID、counter、debug 和 trigger CSR
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：该段覆盖只读 ID CSR、counter CSR、debug CSR 和 trigger CSR 字段。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L171-L239``）：

.. code-block:: yaml

   # ---------------------------------------------------------------------------
   # Read-only ID CSRs
   # ---------------------------------------------------------------------------
   - csr: mvendorid
     address: 0xF11
     description: "Vendor ID"
     fields:
       - field: [31:0]
         name: mvendorid
         type: RO

   - csr: marchid
     address: 0xF12
     description: "Architecture ID"

**逐段解释** ：

* 第 174-L204 行：``mvendorid``、``marchid``、``mimpid``、``mhartid`` 都是
  32-bit RO 字段。
* 第 209-L239 行：``mcycle``、``mcycleh``、``minstret``、``minstreth`` 是
  32-bit R/W counter 字段。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L241-L279``）：

.. code-block:: yaml

   # ---------------------------------------------------------------------------
   # Debug CSRs (only accessible in debug halt mode)
   # ---------------------------------------------------------------------------
   - csr: dcsr
     address: 0x7B0
     description: "Debug control and status"
     fields:
       - field: [31:28]
         name: xdebugver
         type: RO
         description: "Debug spec version (4 = 0.13)"
       - field: [15]
         name: ebreakm
         type: R/W
         description: "EBREAK enters debug mode in M-mode"

**逐段解释** ：

* 第 244-L255 行：``dcsr`` 地址 ``0x7B0``，字段包括 ``xdebugver`` 和
  ``ebreakm``。
* 第 256-L279 行：同一 ``dcsr`` 条目继续描述 ``stepie``、``stopcount``、
  ``cause``、``nmip``、``step``、``prv``。``cause`` 类型为 RO，描述中列出
  step/halt/ebreak/trigger 编码。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L281-L315``）：

.. code-block:: yaml

   - csr: dpc
     address: 0x7B1
     description: "Debug PC"
     fields:
       - field: [31:0]
         name: dpc
         type: R/W

   # ---------------------------------------------------------------------------
   # Trigger CSRs
   # ---------------------------------------------------------------------------
   - csr: mtsel
     address: 0x7A0
     description: "Trigger select"

**逐段解释** ：

* 第 281-L287 行：``dpc`` 地址 ``0x7B1``，32-bit R/W。
* 第 292-L315 行：trigger CSR 条目 ``mtsel``、``mtdata1``、``mtdata2`` 分别位于
  ``0x7A0``、``0x7A1``、``0x7A2``，字段均为 32-bit R/W。

**接口关系** ：

* **被调用** ：debug CSR stream、trigger debug ROM 和 CSR generator 使用这些地址。
* **调用** ：YAML 不调用函数。
* **共享状态** ：``dcsr``/``dpc`` 地址与 ``eh2_debug_csr_stream`` 和 debug ROM 中
  的 ``0x7B0``/``0x7B1`` 一致。

§10.3  EH2 custom CSR、timer、ECC 与 PIC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：文件后半段描述 EH2 自定义 machine CSR、internal timer、ECC/error 和
PIC interrupt CSR。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L316-L358``）：

.. code-block:: yaml

   # ---------------------------------------------------------------------------
   # WD/Microchip custom CSRs
   # ---------------------------------------------------------------------------
   - csr: mscause
     address: 0x7FF
     description: "Machine secondary exception cause"
     fields:
       - field: [31:0]
         name: mscause
         type: R/W

   - csr: mrac
     address: 0x7C0
     description: "Region access control"

**逐段解释** ：

* 第 319-L333 行：``mscause`` 和 ``mrac`` 是 32-bit R/W custom CSR。
* 第 335-L349 行：``mfdc`` 和 ``mcgc`` 也是 32-bit R/W。
* 第 351-L358 行：``mpmc`` 地址 ``0x7C6``，字段类型为 ``R0W1``，不同于前面
  的 R/W 条目。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L359-L408``）：

.. code-block:: yaml

   # ---------------------------------------------------------------------------
   # Internal timer CSRs
   # ---------------------------------------------------------------------------
   - csr: mitcnt0
     address: 0x7D2
     description: "Internal timer 0 counter"
     fields:
       - field: [31:0]
         name: mitcnt0
         type: R/W

   - csr: mitb0
     address: 0x7D3
     description: "Internal timer 0 bound"

**逐段解释** ：

* 第 362-L384 行：timer 0 的 ``mitcnt0``、``mitb0``、``mitctl0`` 分别是 counter、
  bound 和 control，均为 32-bit R/W。
* 第 386-L408 行：timer 1 的 ``mitcnt1``、``mitb1``、``mitctl1`` 同样都是
  32-bit R/W。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L410-L435``）：

.. code-block:: yaml

   # ---------------------------------------------------------------------------
   # ECC/error CSRs
   # ---------------------------------------------------------------------------
   - csr: micect
     address: 0x7F0
     description: "ICache ECC error count threshold"
     fields:
       - field: [31:0]
         name: micect
         type: R/W

   - csr: miccmect
     address: 0x7F1
     description: "ICCM ECC error count threshold"

**逐段解释** ：

* 第 413-L419 行：``micect`` 地址 ``0x7F0``，描述为 ICache ECC error count
  threshold。
* 第 421-L435 行：``miccmect`` 和 ``mdccmect`` 分别对应 ICCM 和 DCCM ECC error
  count threshold，字段都是 32-bit R/W。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml:L437-L487``）：

.. code-block:: yaml

   # ---------------------------------------------------------------------------
   # PIC interrupt CSRs
   # ---------------------------------------------------------------------------
   - csr: meivt
     address: 0xBC8
     description: "External Interrupt Vector Table base"
     fields:
       - field: [31:10]
         name: base
         type: R/W
         description: "Vector table base address"

   - csr: meihap
     address: 0xFC8

**逐段解释** ：

* 第 440-L447 行：``meivt`` 地址 ``0xBC8``，字段 ``base`` 覆盖 ``[31:10]``。
* 第 449-L455 行：``meihap`` 地址 ``0xFC8``，32-bit RO。
* 第 457-L487 行：``meipt``、``meicpct``、``meicurpl``、``meicidpl`` 描述 PIC
  threshold、claim/capture、current priority level 和 claim ID priority level。

**接口关系** ：

* **被调用** ：CSR generator、coverage 和 PIC directed stream 使用这些条目。
* **调用** ：YAML 不调用函数。
* **共享状态** ：PIC 地址与 ``eh2_pic_int_stream`` 的 ``0xBC8``、``0xFC8``、
  ``0xBC9``、``0xBCA``、``0xBCB`` 一致。

§11  交叉关系与边界
--------------------------------------------------------------------------------

§11.1  本目录与 UVM/flow 的关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：riscv-dv 扩展目录位于生成侧和仿真侧之间。它不驱动 DUT pin，也不消费
UVM monitor transaction；它通过生成程序、testlist、plusarg 和 trace CSV 转换
影响 UVM 回归。

**关键关系** ：

* ``testlist.yaml`` 的 ``rtl_test`` 字段必须能在 UVM test library 中找到对应
  class 或 test 名称。
* ``gen_opts`` 中的 ``+directed_instr_0=eh2_*`` 依赖 ``user_extension.svh``
  include 的 ``eh2_directed_instr_lib.sv``。
* ``sim_opts`` 中的 ``+enable_irq_seq=1``、``+enable_debug_seq=1``、
  ``+enable_debug_single=1`` 等 plusarg 由 UVM sequence/test 消费；本目录只
  声明这些 option 字符串。
* ``eh2_log_to_trace_csv.py`` 处理 RTL 仿真 log，产出 riscv-dv coverage/compare
  所需 CSV。

§11.2  与 ADR 的关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责** ：本章只根据源代码解释实现。ADR 用来定位相关 verification decision，
不是为源代码中不存在的行为补充假设。

* :ref:`adr-0006` 对应 atomic 相关边界；本目录中可回溯到
  ``eh2_atomic_stream``、``riscv_amo_test`` 和 ``cosim_atomic_basic.S`` 入口。
* :ref:`adr-0007` 对应 interrupt cosim；本目录中可回溯到
  ``eh2_pic_int_stream``、interrupt testlist 项和 PIC CSR 描述。
* :ref:`adr-0008` 对应 debug cosim；本目录中可回溯到 debug CSR stream、
  debug ROM、DRET/EBREAK/debug testlist 项。
* :ref:`adr-0009` 对应 PMP/ePMP cosim；本目录中可回溯到 PMP/ePMP testlist 项
  和 ``gen_opts`` 中的 PMP 开关。
* :ref:`adr-0010` 对应 CSR register model；本目录中可回溯到
  ``csr_description.yaml``、``implemented_csr``、``custom_csr`` 和 CSR stream。
* :ref:`adr-0011` 对应 compliance framework；本目录中的 riscv-dv 随机/coverage
  入口与 compliance 是相邻验证入口，但本文不把 compliance 数字写入本目录实现。

§12  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`riscv_dv_extension`、:ref:`appendix_b_uvm_tests`、
  :ref:`appendix_b_uvm_vseq`。
* 关联 ADR：:ref:`adr-0006`、:ref:`adr-0007`、:ref:`adr-0008`、
  :ref:`adr-0009`、:ref:`adr-0010`、:ref:`adr-0011`。
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/user_extension.svh``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/ddm_link.ld``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscvOVPsim.ic``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/cov_testlist.yaml``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml``
* 源文件绝对路径：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml``

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

§13  v2-17 源码片段闭环：EH2 riscv-dv 扩展核心文件
--------------------------------------------------------------------------------

本节补齐 riscv-dv 扩展中四个核心源文件的 ``literalinclude``。前文已经把每个
class、override、directed stream 和 trace CSV parser 分段解释；这里保留较长但可
构建的片段，让源码审计能确认这些资产确实有渲染级代码证据。

.. literalinclude:: ../../../../dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv
   :language: systemverilog
   :lines: 1-148
   :linenos:
   :caption: dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L1-L148

逐段精读：L13-L44 定义 EH2 program generator 与 mailbox 地址；L46-L86 生成
header、trap vector 和 ECALL 入口；L88-L146 生成 test done、debug ROM 和 NMI
handler，使随机程序能按 EH2 TB mailbox 协议退出。

.. literalinclude:: ../../../../dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv
   :language: systemverilog
   :lines: 1-180
   :linenos:
   :caption: dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L1-L180

逐段精读：L1-L46 建立 directed instruction library 的基础类与 CSR helper；
L52-L137 覆盖 interrupt、debug 和 CSR access stream 的早期实现；L142-L180 开始
PMP/ePMP 相关 stream。完整文件后续段落已逐类解释。

.. literalinclude:: ../../../../dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv
   :language: systemverilog
   :lines: 1-144
   :linenos:
   :caption: dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L1-L144

逐段精读：L1-L29 引入 debug trigger override 的 class 关系；L41-L98 生成 trigger
setup、debug entry 和 resume 相关汇编；L101-L144 把 hardware trigger program
generator 绑定到 EH2 debug ROM 生成策略。

.. literalinclude:: ../../../../dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py
   :language: python
   :lines: 1-120
   :linenos:
   :caption: dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L1-L120

逐段精读：L1-L33 定义脚本用途、CSV 字段和 trace 正则；L35-L93 解析 EH2 retire
日志、寄存器写回和异常字段；L96-L120 开始输出 CSV 记录。后续 compare/CLI 路径
在前文 §7 已逐段说明。

§14  v2-18 ``eh2_directed_instr_lib.sv`` 全文段落级精读
--------------------------------------------------------------------------------

``eh2_directed_instr_lib.sv`` 是 EH2 riscv-dv 定向 stream 的集中定义文件。v2-17
只引用到 L180，覆盖了基类、CSR、bitmanip 和 PIC stream 的开头；v2-18 补齐全文，
确保 atomic、breakpoint、exception 和 CSR hazard stream 没有被遗漏。

.. literalinclude:: ../../../../dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:全文

逐段精读：

* L1-L46：``eh2_base_directed_stream`` 定义 EH2 directed stream 的公共约束、构造函数
  和 ``post_randomize``。所有派生 stream 都通过它接入 riscv-dv instruction list。
* L52-L112：``eh2_csr_access_stream`` 生成 EH2 CSR read/write/set/clear 序列，覆盖
  machine/debug/PMP 相关 CSR 的基本访问。
* L114-L179：``eh2_bitmanip_stream`` 生成 Zb* 指令组合，补随机流在短回归中难以稳定命中
  的 bitmanip corner。
* L181-L238：``eh2_pic_int_stream`` 生成 PIC/interrupt 相关 CSR 和 helper instruction，
  包含 ``get_li_instr``、``get_csr_instr`` 等局部构造函数。
* L244-L281：``eh2_debug_csr_stream`` 生成 debug CSR 和 debug entry 相关序列，服务
  debug cosim、DRET/EBREAK 和 trigger 场景。
* L287-L334：``eh2_atomic_stream`` 生成 LR/SC/AMO 场景，配合 directed assembly 和
  cosim scoreboard 验证 memory side effect。
* L340-L365：``eh2_breakpoint_stream`` 生成 breakpoint/trigger 类随机定向序列，
  关注 debug entry 和 PC 捕获。
* L371-L399：``eh2_exception_stream`` 生成异常触发指令，覆盖 illegal/trap 类路径。
* L405-L460：``eh2_csr_hazard_stream`` 生成 back-to-back CSR hazard 序列，验证 CSR
  forwarding、serialization 和 pipeline hazard 行为。

§15  v2-19 ``eh2_log_to_trace_csv.py`` 全文段落级精读
--------------------------------------------------------------------------------

``eh2_log_to_trace_csv.py`` 负责把 EH2 仿真日志转换成 riscv-dv 可消费的 trace CSV。
v2-17 只纳入了 L1-L120，本节补齐全文，尤其是 ABI operand 转换、branch immediate
处理、UVM log checker 和 CLI 入口，避免读者只看到 retire 正则而漏掉比较前的规范化。

.. literalinclude:: ../../../../dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:全文

逐段精读：

* L1-L20：脚本头、import 和 riscv-dv script path 注入。该段把仓库根目录下的
  ``vendor/google_riscv-dv/scripts`` 加入 ``sys.path``，以复用官方 trace CSV helper。
* L21-L47：CSV 字段、默认 full trace、retire trace 正则和寄存器/operand 正则。
  ``INSTR_RE`` 是 EH2 日志格式到 CSV 的第一道契约，字段包含 time、cycle、PC、binary、
  instruction、operand 和可选 comment。
* L48-L95：``_process_eh2_sim_log_fd``。函数逐行扫描仿真日志，跳过 ecall 行，匹配
  retire 记录，解析 rd writeback、输出 full trace 或简化 trace，并累计 instruction count。
* L96-L115：``process_eh2_sim_log``。该 wrapper 负责打开输入/输出文件、写 CSV header、
  调用底层解析函数，并在零指令时抛异常，避免空 trace 被误认为通过。
* L117-L142：``convert_operands_to_abi``。函数把 ``xN`` register 名改成 ABI 名，
  让 EH2 trace 与 riscv-dv/spike trace 使用同一 operand 表示。
* L144-L181：``expand_trace_entry`` 和 ``process_imm``。前者展开 trace operand，
  后者把 branch/jump immediate 从绝对 PC 语义转换为 riscv-dv 期望的 offset 语义。
* L184-L258：``check_eh2_uvm_log``。该函数读取 UVM log，识别 UVM error/fatal、显式
  PASS/FAIL、timeout 和上下文行，返回 passed、log_out、failure_mode 三元组，供外部
  regression 或比较脚本分类失败。
* L259-L278：CLI ``main``。参数包括 ``--log``、``--csv`` 和 ``--full_trace``，执行路径
  只做日志到 CSV 的转换；是否运行 Spike 或 compare 由上层 riscv-dv flow 决定。
