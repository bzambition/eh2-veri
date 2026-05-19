.. _riscv_dv_extension:

riscv-dv 扩展 — 架构桥接说明
================================================================================

:status: draft
:source: dv/uvm/core_eh2/riscv_dv_extension/
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  架构边界
--------------------------------------------------------------------------------

``dv/uvm/core_eh2/riscv_dv_extension/`` 是 EH2 随机指令生成流程接入本地
``vendor/google_riscv-dv`` 的目标适配目录。该目录不实例化 DUT，不驱动 UVM
interface，也不做 Spike cosim 比对；它向 generator、编译脚本、RTL 回归脚本
和 trace CSV 转换脚本提供同一组 EH2 目标信息。

本章站在验证架构视角说明这些文件如何串联。逐类、逐函数的源码字典见
:ref:`appendix_b_uvm_riscv_dv_ext`；本章只解释跨脚本数据流和架构约束。

.. code-block:: bash

   testlist.yaml / ml_testlist.yaml / cov_testlist.yaml
          |
          v
   scripts/run_instr_gen.py
          |-- --custom_target riscv_dv_extension
          |-- --testlist <per-run overlay YAML>
          |-- +uvm_set_inst_override=...eh2_asm_program_gen...
          v
   vendor/google_riscv-dv/run.py --steps gen
          |
          v
   generated assembly
          |
          v
   scripts/compile_test.py + linker script + include dirs
          |
          v
   RTL simulation + cosim policy from scripts/run_regress.py
          |
          v
   EH2 log -- eh2_log_to_trace_csv.py --> riscv-dv trace CSV

**逐段解释**：

* 第一层 YAML 是测试选择层：``testlist.yaml`` 给常规 riscv-dv 回归提供
  ``test``、``gen_test``、``gen_opts``、``rtl_test``、``sim_opts``、
  ``iterations`` 和可选 ``cosim`` 字段。
* ``scripts/run_instr_gen.py`` 不直接修改主 testlist；它读取主 testlist 的
  单个条目，合并 CLI 传入的额外 ``gen_opts``，在运行目录写出
  ``riscv_dv_testlist.yaml``，再把该 overlay 交给 riscv-dv。
* ``--custom_target`` 指向 ``riscv_dv_extension`` 后，riscv-dv 可以包含
  ``user_extension.svh``，从而注册 ``eh2_asm_program_gen`` 和 EH2 定向 stream。
* 编译阶段由 ``scripts/compile_test.py`` 完成。它把 riscv-dv 的
  ``user_extension`` include 目录和 EH2 扩展目录加入 assembly include path，
  使用 RV32IMAC 加 Zba/Zbb 的 GCC ``-march`` 编译输出 ELF/bin/hex。
* RTL 运行阶段由 ``scripts/run_regress.py`` 解释每个 testlist 条目的
  ``cosim`` 策略；没有显式禁用时默认追加 ``+enable_cosim=1``。
* ``eh2_log_to_trace_csv.py`` 是功能覆盖/trace CSV 的离线桥接脚本。它读取 EH2
  仿真日志，抽取 PC、binary、instruction、operand 和 GPR 写回，写成
  riscv-dv 工具期望的 CSV entry。

**接口关系**：

* **被调用**：``riscvdv.mk`` 的 ``instr_gen_run`` target 调用
  ``scripts/run_instr_gen.py``；回归框架调用 ``scripts/compile_test.py`` 和
  ``scripts/run_regress.py``。
* **调用**：扩展目录内 SV 类调用 riscv-dv 基类和 ``riscv_instr::get_instr``；
  Python 脚本调用 ``vendor/google_riscv-dv/run.py``、GCC、objcopy 和
  riscv-dv trace CSV helper。
* **共享状态**：``testlist.yaml`` 的 ``test`` 名称、directed stream 名称和
  ``rtl_test`` 名称必须与 generator 类、UVM test 类和回归脚本保持一致。

§2  目标能力描述
--------------------------------------------------------------------------------

§2.1  ``riscv_core_setting.sv`` — generator 看到的 EH2
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``riscv_core_setting.sv`` 把 EH2 的静态生成能力告诉 riscv-dv。它定义
XLEN、hart 数、特权级、SATP 模式、ISA group、PMP/debug 开关以及 interrupt/
exception 枚举。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L7-L27``）：

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

**逐段解释**：

* 第 L7-L10 行：目标 XLEN 为 32，整数 GPR 为 32 个；floating-point 和 vector
  GPR 数量为 0。generator 因此不会把浮点寄存器或 vector 寄存器作为目标资源。
* 第 L12-L18 行：vector 参数保留在 setting 中，但
  ``VECTOR_EXTENSION_ENABLE = 0``，所以这些宽度参数不会开启 vector 指令生成。
* 第 L20-L23 行：``NUM_HARTS = 1``、``SATP_MODE = BARE`` 和
  ``supported_privileged_mode[] = {MACHINE_MODE}`` 把随机程序限制在单 hart、
  bare address translation 和 M-mode 范围。
* 第 L25-L27 行：``unsupported_instr`` 为空，表示这里不通过显式黑名单删指令；
  ``support_unaligned_load_store`` 为 1，允许 riscv-dv 生成 unaligned load/store
  相关刺激。

**接口关系**：

* **被调用**：riscv-dv 在目标编译和 generator elaboration 时读取该 setting。
* **调用**：该文件不调用函数；它提供参数、数组和常量。
* **共享状态**：``run_instr_gen.py`` 的 ``--isa rv32imac`` 与该文件的基础 ISA
  范围共同约束生成入口；bitmanip directed stream 还有独立指令子集。

§2.2  ``supported_isa`` 与功能开关 — 静态白名单和局部禁用
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该段把 EH2 在 riscv-dv 侧公开为 RV32IMAC 加 Zba/Zbb/Zbc/Zbs，同时
记录 debug 支持、PMP/ePMP 生成开关和 interrupt vector 模式。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv:L29-L48``）：

.. code-block:: systemverilog

   // EH2 supports RV32IMAC plus configuration-selected bitmanip groups.
   riscv_instr_group_t supported_isa[$] = {
     RV32I,
     RV32M,
     RV32A,
     RV32C
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

**逐段解释**：

* 第 L30-L39 行：``supported_isa`` 列出 RV32I、RV32M、RV32A、RV32C 和四个
  bitmanip group。这里是 riscv-dv 的目标能力白名单，不等同于每个 test 都会
  生成这些 group。
* 第 L41-L42 行：``mtvec`` 支持 ``DIRECT`` 和 ``VECTORED`` 两类模式，最大
  interrupt vector 数写成 32。
* 第 L44-L48 行：PMP/ePMP 在 core setting 默认关闭，debug mode 开启，U-mode
  trap 和 ``sfence`` 关闭。PMP/ePMP test 仍可在 testlist 的 ``gen_opts`` 中写
  ``+enable_pmp=1``，但静态 setting 本身记录的是默认状态。

**接口关系**：

* **被调用**：riscv-dv 根据 ``supported_isa`` 和 feature bit 决定可生成的
  instruction/CSR 组合。
* **调用**：无函数调用。
* **共享状态**：``eh2_bitmanip_stream`` 的 Zbc/Zbs 列表为空，说明 testlist 中
  使用 directed assembly 的 bitmanip 覆盖不能只由 ``supported_isa`` 推导。

§2.3  CSR、interrupt 和 exception 列表 — coverage 分类输入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该文件列出标准 M-mode/debug/trigger CSR 和 EH2 custom CSR 地址，并
给 riscv-dv coverage 侧提供 interrupt/exception 分类。

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

**逐段解释**：

* 第 L61-L80 行：``implemented_csr`` 先列出机器模式 ID、status、interrupt、
  trap、counter 和 counter inhibit CSR。这些枚举来自 riscv-dv 的
  ``privileged_reg_t``。
* 第 L81-L98 行：数组后半段继续列出 ``MHPMCOUNTER3`` 到 ``MHPMEVENT6``、
  ``DCSR``、``DPC``、``TSELECT``、``TDATA1`` 和 ``TDATA2``。debug 和 trigger
  CSR 因此在 generator 侧是已实现资源。

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

**逐段解释**：

* 第 L100-L102 行：注释说明 EH2 custom CSR 用 12-bit 数字地址表示，因为
  upstream riscv-dv 没有这些 VeeR/EH2 机器 CSR 的符号枚举。
* 第 L103-L120 行：数组前半段覆盖 ``mscause``、``mrac``、``mfdc``、``mcgc``、
  ``mpmc``、``mcpc``、``dmst``、debug/halt 相关 CSR 和内部 timer CSR。
* 第 L121-L132 行：数组后半段覆盖 error/PIC 相关 CSR，包括 ``mdeau``、
  ``mdseac``、``micect``、``miccmect``、``mdccmect``、``meivt``、``meihap``、
  ``meipt``、``meicpct``、``meicurpl`` 和 ``meicidpl``。

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

**逐段解释**：

* 第 L137-L141 行：interrupt coverage 侧只列出 software、timer 和 external 三类
  machine interrupt。
* 第 L143-L152 行：exception 列表覆盖 instruction access fault、illegal、
  breakpoint、load/store address misaligned、load/store access fault 和
  M-mode ``ECALL``。这解释了为何 directed exception stream 只需要制造
  ``ECALL`` 和 misaligned load 就能触达其中一部分分类。

**接口关系**：

* **被调用**：riscv-dv generator 和 coverage 代码读取这些 CSR/原因列表。
* **调用**：无函数调用。
* **共享状态**：``csr_description.yaml`` 对同一批 CSR 提供字段级描述；
  ``eh2_csr_access_stream`` 和 ``eh2_pic_int_stream`` 直接使用这些 custom CSR
  地址中的子集。

§3  汇编程序生成覆盖
--------------------------------------------------------------------------------

§3.1  ``user_extension.svh`` — custom target 入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``user_extension.svh`` 是 riscv-dv custom target 的 include 入口。
``run_instr_gen.py`` 检测到该文件存在后追加 ``--custom_target``，riscv-dv 再
通过这个 hook 编译 EH2 的 program generator 和 directed stream。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/user_extension.svh:L1-L8``）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 riscv-dv User Extension Hook
   //
   // This file is included by riscv-dv to register EH2-specific
   // class overrides and directed instruction streams.
   
   `include "eh2_asm_program_gen.sv"
   `include "eh2_directed_instr_lib.sv"

**逐段解释**：

* 第 L1-L5 行：文件头说明该文件由 riscv-dv include，用于注册 EH2 特定 class
  override 和 directed instruction stream。
* 第 L7-L8 行：实际 include 只有两个文件：``eh2_asm_program_gen.sv`` 和
  ``eh2_directed_instr_lib.sv``。硬件 trigger override 文件不在此处直接 include。

**接口关系**：

* **被调用**：``run_instr_gen.py`` 通过 ``--custom_target`` 让 riscv-dv 查找该
  hook。
* **调用**：SystemVerilog 预处理器 include 两个 EH2 SV 文件。
* **共享状态**：testlist 中 ``+directed_instr_0=eh2_*`` 的类名必须来自这些
  include 后可见的 class。

§3.2  ``run_instr_gen.py`` — 程序生成器 override 的命令来源
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：脚本在 generator 命令行追加 EH2 mailbox 签名地址和
``eh2_asm_program_gen`` 的 UVM instance override，使 riscv-dv 生成的程序按
EH2 启动、结束和 CSR 初始化规则写入 assembly。

**关键代码** （``dv/uvm/core_eh2/scripts/run_instr_gen.py:L21-L35``）：

.. code-block:: python

   SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
   DV_DIR = os.path.dirname(SCRIPT_DIR)
   EXT_DIR = os.path.join(DV_DIR, "riscv_dv_extension")
   DEFAULT_TESTLIST = os.path.join(EXT_DIR, "testlist.yaml")
   EH2_SIGNATURE_ADDR = "d0580000"
   
   
   def build_sim_opts() -> str:
       """Build riscv-dv generator simulator plusargs for EH2 customizations."""
       return " ".join([
           "+uvm_set_inst_override=riscv_asm_program_gen,"
           "eh2_asm_program_gen,uvm_test_top.asm_gen",
           "+require_signature_addr=1",
           f"+signature_addr={EH2_SIGNATURE_ADDR}",
       ])

**逐段解释**：

* 第 L21-L24 行：脚本从自身位置推导 DV 目录和扩展目录，默认 testlist 固定为
  ``riscv_dv_extension/testlist.yaml``。
* 第 L25 行：``EH2_SIGNATURE_ADDR`` 是字符串 ``d0580000``。该地址与
  ``eh2_asm_program_gen.sv`` 中 mailbox 地址 ``32'hD058_0000`` 对应。
* 第 L28-L35 行：``build_sim_opts()`` 返回四个 riscv-dv simulator plusarg：
  instance override、要求签名地址和具体签名地址。override 目标实例路径是
  ``uvm_test_top.asm_gen``。

**接口关系**：

* **被调用**：``run_instr_gen()`` 在构建 ``cmd`` 时调用 ``build_sim_opts()``。
* **调用**：无外部 subprocess 调用；它只拼接字符串。
* **共享状态**：``EH2_SIGNATURE_ADDR`` 必须与 program generator 的 mailbox
  写入地址一致，否则 generator 侧和 RTL 侧结束条件会分叉。

§3.3  ``eh2_asm_program_gen`` — 启动、ECALL 和 mailbox
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该 class 覆盖 riscv-dv 默认 program generator，使生成程序从 EH2
期望的 text/start 形态进入，使用 mailbox 写 pass/fail，并把 ``ECALL`` 处理成
返回主程序的 trap handler。

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

**逐段解释**：

* 第 L13-L19 行：class 继承自 ``riscv_asm_program_gen``，并注册 UVM object
  factory。``new()`` 只调用父类构造函数，没有本地成员初始化。
* 第 L22-L24 行：``gen_program()`` 先清空 ``default_include_csr_write``。这使
  EH2 选择显式白名单，而不是沿用 riscv-dv 默认 CSR 写入集合。
* 第 L26-L43 行：函数把 M-mode CSR、PMP CSR 和部分 delegation/pending CSR
  push 回白名单，最后调用 ``super.gen_program()``。因此具体程序结构仍由
  riscv-dv 父类生成，EH2 只改写输入集合。

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

**逐段解释**：

* 第 L47-L52 行：程序头写入 ``.section .text``、``.global _start`` 和
  ``_start:``，为 linker 和 RTL boot 入口提供符号。
* 第 L55 行：stack pointer 初始化为 ``0x8200_0000``，该值直接写入 assembly。
* 第 L58-L59 行：程序把 ``0x8`` 写入 ``mstatus``，即设置 MIE bit。这里没有
  读取旧 ``mstatus`` 后做 bit set，而是直接 ``csrw``。

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

**逐段解释**：

* 第 L63-L71 行：``gen_ecall_handler()`` 生成四条指令：读 ``mepc``、加 4、写回
  ``mepc``、``mret``。这使 ``ECALL`` 后继续执行下一条指令。
* 第 L74-L76 行：``gen_program_end()`` 为空，注释说明 EH2 test 结束由
  ``test_done``/``test_fail`` mailbox 写入完成，而不是父类默认结尾。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv:L78-L96``）：

.. code-block:: systemverilog

     // Generate a single EH2 mailbox write. 0xff means pass, 0x01 means fail.
     virtual function void gen_test_end(input bit pass, ref string instr[$]);
       instr = {
         $sformatf("li t0, 0x%08x", 32'hD058_0000),
         pass ? "li t1, 0xff" : "li t1, 0x01",
         "sw t1, 0(t0)",
         "1: j 1b"
       };
     endfunction
   
     // Override the upstream write_tohost/ecall ending with the EH2 mailbox.
     virtual function void gen_test_done();

**逐段解释**：

* 第 L79-L85 行：``gen_test_end()`` 生成 mailbox 写序列。``pass`` 为 1 时写
  ``0xff``，否则写 ``0x01``；写入地址固定为 ``32'hD058_0000``，之后进入
  ``1: j 1b`` 自旋。
* 第 L89-L96 行：``gen_test_done()`` 先生成 ``test_done:`` 标签和 pass 序列，
  再生成 ``test_fail:`` 标签和 fail 序列。父类默认 ``write_tohost``/``ecall``
  结束路径被 EH2 mailbox 结束路径取代。

**接口关系**：

* **被调用**：``run_instr_gen.py`` 通过 UVM instance override 选中该 class。
* **调用**：调用 ``super.gen_program()``、``gen_section()``、``get_label()`` 和
  ``format_string()``。
* **共享状态**：mailbox 地址与 ``run_instr_gen.py`` 的 signature address 共享；
  CSR 白名单与 ``riscv_core_setting.sv`` 的 implemented/custom CSR 列表共同决定
  CSR 类随机刺激范围。

§3.4  初始化、NMI 和 debug ROM — 生成程序中的固定片段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：初始化段在父类 init 后追加 EH2 custom CSR 初始化、跳转到 ``main`` 和
NMI handler；debug ROM 覆盖则生成一个最小 DCSR/DPC 读取和 ``dret`` 返回片段。

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

**逐段解释**：

* 第 L99-L104 行：``gen_init_section()`` 先运行父类 init，再调用
  ``init_eh2_custom_csr()``，然后插入 ``j main``，最后生成 NMI handler。
* 第 L107-L112 行：``init_eh2_custom_csr()`` 把 ``0`` 写入 ``mcountinhibit``。
* 第 L114-L115 行：函数把 ``0x1A55A5A5`` 写入 CSR ``0x7C0``，源注释标记为
  ``mrac``。
* 第 L118-L119 行：函数还准备把 ``0`` 写入 CSR ``0x7F9``。源代码注释写
  ``mfdc``，但 ``riscv_core_setting.sv`` 中 ``mfdc`` 地址列为 ``12'h7C9``；
  本章只记录代码事实，不改写源代码含义。

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

**逐段解释**：

* 第 L123-L131 行：NMI handler 以 ``h<hart>_nmi_handler`` 命名，读取 CSR
  ``0x7F8`` 后执行 ``mret``。源注释把 ``0x7F8`` 标为 ``mcgc``。
* 第 L134-L146 行：debug ROM 段写入 ``.section .debug_rom, "ax"``，读取
  ``DCSR`` 和 ``DPC``，执行 ``csrci 0x7B0, 0x4`` 清除 ``dcsr`` 中的位，然后
  ``dret`` 返回。

**接口关系**：

* **被调用**：riscv-dv 父类生成初始化、NMI 和 debug ROM 时触发这些 override。
* **调用**：``gen_init_section()`` 调用父类 init、本地 CSR init 和 NMI handler。
* **共享状态**：debug ROM 地址布置由 linker/section 名称和仿真加载路径共同决定；
  CSR 地址必须与 ``riscv_core_setting.sv`` 和 ``csr_description.yaml`` 的字段表一致。

§4  定向指令流
--------------------------------------------------------------------------------

§4.1  ``eh2_base_directed_stream`` — 所有 EH2 stream 的生成钩子
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：EH2 directed stream 把实际指令填充放在 ``gen_instr()`` 中；基类覆盖
``post_randomize()``，保证 riscv-dv randomize 后先 materialize 指令，再让父类
设置 label/comment/atomic 标记。

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

**逐段解释**：

* 第 L25-L35 行：基类继承 ``riscv_directed_instr_stream``，并声明纯虚函数
  ``gen_instr()``。默认参数与 riscv-dv signature 一致：branch 和 load/store 默认
  不主动开启。
* 第 L37-L43 行：``post_randomize()`` 先调用 ``gen_instr()``，然后检查
  ``instr_list`` 非空。空列表直接触发 ``uvm_fatal``。
* 第 L43 行：父类 ``post_randomize()`` 仍会执行，因此 EH2 只改变指令 materialize
  时机，不绕开 riscv-dv 父类对 stream 的后处理。

**接口关系**：

* **被调用**：所有 ``eh2_*_stream`` 子类继承该基类；riscv-dv 在 directed stream
  randomize 后调用 ``post_randomize()``。
* **调用**：调用子类 ``gen_instr()`` 和父类 ``post_randomize()``。
* **共享状态**：``instr_list`` 是 riscv-dv directed stream 的共享输出队列。

§4.2  CSR 与 bitmanip stream — 地址白名单和工具链边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``eh2_csr_access_stream`` 生成 EH2 custom CSR 访问；``eh2_bitmanip_stream``
在当前工具链可接受的 Zba/Zbb 子集上生成 bitmanip 指令。

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

**逐段解释**：

* 第 L52-L57 行：class 注册为 UVM object，并定义 ``EH2_CUSTOM_CSRS`` 常量数组。
* 第 L58-L77 行：数组列出 writable custom CSR 子集，覆盖 secondary cause、
  memory region、feature disable、clock gating、timer 和 ECC/error threshold
  相关 CSR。该列表比 ``riscv_core_setting.sv`` 的 ``custom_csr`` 更窄。

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

**逐段解释**：

* 第 L89-L92 行：每次 repeat 从 ``EH2_CUSTOM_CSRS`` 中随机选择一个 CSR 地址；
  repeat 次数是 ``10 + $urandom_range(10)``。
* 第 L94-L98 行：每条 CSR 指令在 ``CSRRW``、``CSRRS`` 和 ``CSRRC`` 中随机选择。
* 第 L100-L104 行：指令写入 CSR 地址，启用 ``rs1``，随机选择 ``rs1`` 和 ``rd``
  为 x1-x31，最后 push 到 ``instr_list``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L118-L137``）：

.. code-block:: systemverilog

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

**逐段解释**：

* 第 L119-L121 行：Zba 列表包含 ``SH1ADD``、``SH2ADD``、``SH3ADD``、``SLLI`` 和
  ``SRLI``。
* 第 L123-L131 行：Zbb 列表保留 ``ANDN``、``ORN``、``XNOR``、``CLZ``、``CTZ``、
  ``CPOP``、``MAX``、``MAXU``、``MIN`` 和 ``MINU``。源注释说明其他 Zbb 指令因
  GCC 11.1 assembler 支持边界未列入。
* 第 L133-L137 行：``ZBC_INSTRS`` 和 ``ZBS_INSTRS`` 是空数组。虽然 core setting
  公开了 Zbc/Zbs group，该 directed stream 当前不直接生成对应指令。

**接口关系**：

* **被调用**：testlist 中的 ``+directed_instr_0=eh2_csr_access_stream,10`` 和
  其他 directed stream plusarg 通过 riscv-dv 调用这些 class。
* **调用**：调用 ``riscv_instr::get_instr()`` 和 ``$urandom_range``。
* **共享状态**：CSR 地址与 ``riscv_core_setting.sv``、``csr_description.yaml``
  共享；bitmanip 列表与 ``compile_test.py`` 的 ``-march=rv32imac_zba_zbb``
  工具链边界共享。

§4.3  PIC、debug、atomic 和 exception stream — 专项刺激入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：这些 stream 把 interrupt、debug CSR、LR/SC、breakpoint、exception 和
CSR hazard 作为 testlist 可选择的 directed stream 名称暴露给 generator。

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

**逐段解释**：

* 第 L181-L190 行：``eh2_pic_int_stream`` 继承 EH2 基类，``gen_instr()`` 默认不
  生成 branch/load/store。
* 第 L193-L195 行：stream 先把 ``0x0000_0800`` 装入 t0，并用 ``CSRRW`` 写
  ``MIE``，源注释把它标为 MEIE bit。
* 第 L197-L214 行：stream 继续写 ``MEIVT``、``MEIPT`` 和 ``MEICIDPL``，并读取
  ``MEIHAP``、``MEICPCT``。这些 CSR 地址来自 EH2 PIC custom CSR 空间。

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

**逐段解释**：

* 第 L244-L253 行：debug CSR stream 只声明本地 ``riscv_instr``，不引入 branch 或
  load/store。
* 第 L256-L262 行：第一条指令用 ``CSRRS`` 读取 ``DCSR`` 地址 ``12'h7B0``，
  ``rs1`` 设为 ``ZERO``，``rd`` 随机选择 x1-x31。
* 第 L264-L278 行：后续代码用相同方式读取 ``DPC`` 地址 ``12'h7B1``，再生成一条
  ``CSRRW`` 写 ``DPC`` 的指令。

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

**逐段解释**：

* 第 L295-L300 行：atomic stream 显式把 ``no_branch`` 和 ``no_load_store`` 默认值
  设为 0，表示该 stream 会生成 load/store 类原子访存；base register 在 x1-x28
  内选择，给后续 ``base_reg + 3`` 留出寄存器空间。
* 第 L302-L326 行：每轮生成 ``LR_W``、``ADDI`` 和 ``SC_W`` 三条指令。``LR_W``
  读 ``base_reg``，``ADDI`` 修改 load-reserve 的结果，``SC_W`` 把修改值写回。
* 第 L327-L330 行：源注释说明原本的 ``BNE`` retry loop 被移除，因为 riscv-dv
  生成的 ``BNE`` immediate 是未解析 label，会被 linker 拒绝。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:L371-L397``）：

.. code-block:: systemverilog

   class eh2_exception_stream extends eh2_base_directed_stream;
   
     `uvm_object_utils(eh2_exception_stream)
   
     function new(string name = "");
       super.new(name);
     endfunction
   
     virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 0,
                                     bit is_debug_program = 0);
       riscv_instr instr;
   
       // Generate ECALL
       instr = riscv_instr::get_instr(ECALL);
       instr_list.push_back(instr);
   
       // Generate misaligned load (if load/store allowed)
       if (!no_load_store) begin

**逐段解释**：

* 第 L379-L385 行：exception stream 默认允许 load/store，先无条件 push 一条
  ``ECALL``。
* 第 L388-L395 行：当 ``no_load_store`` 为 0 时，stream 再生成一条 ``LW``，
  随机选择 ``rs1`` 和 ``rd``，把 immediate 设为 ``1``。源注释把这个 immediate
  标为 misaligned offset。

**接口关系**：

* **被调用**：testlist 通过 ``+directed_instr_0=eh2_pic_int_stream,5``、
  ``eh2_debug_csr_stream``、``eh2_exception_stream`` 和 ``eh2_csr_hazard_stream``
  等名称选择 stream。
* **调用**：调用 ``get_li_instr()``、``get_csr_instr()`` 和
  ``riscv_instr::get_instr()``。
* **共享状态**：interrupt/debug/PMP cosim 行为还依赖 scoreboard 和 Spike 侧 ADR：
  :ref:`adr-0006`、:ref:`adr-0007`、:ref:`adr-0008`、:ref:`adr-0009` 和
  :ref:`adr-0017`。

§5  hardware trigger debug override
--------------------------------------------------------------------------------

§5.1  ``eh2_hardware_triggers_debug_rom_gen`` — 根据 ``DCSR.cause`` 分派
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该 override 为 hardware trigger 测试生成定制 debug ROM。ROM 读取
``DCSR.cause``，分别处理 EBREAK、TRIGGER 和 HALTREQ 三类 debug entry cause。

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

**逐段解释**：

* 第 L11-L16 行：class 继承 ``riscv_debug_rom_gen``，注册 UVM object，并把
  ``eh2_trigger_idx`` 初始化为 0。
* 第 L18-L20 行：``gen_program()`` 声明本地 instruction string 队列。
* 第 L21-L29 行：源注释明确说明该 ROM 不保存 GPR，且会修改程序流；它依赖
  directed stream 把下一次 trigger 地址放在 ``cfg.gpr[1]``。

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

**逐段解释**：

* 第 L41-L44 行：ROM 读取 ``DCSR`` 到 ``cfg.scratch_reg``，左移 0x17 再右移
  0x1d，抽取 ``DCSR[8:6]``。
* 第 L45-L50 行：代码依次把 ``cfg.gpr[0]`` 设为 1、2、3，并用 ``beq`` 分派到
  ``1f``、``2f`` 和 ``3f``，源注释分别标为 EBREAK、TRIGGER 和 HALTREQ。
* 第 L52-L65 行：EBREAK 分支开始于 ``1: nop``，后续会配置 trigger 并把 ``DPC``
  加 4。

§5.2  trigger 设置、清除和异常失败路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：EBREAK 分支写 ``TSELECT``、``TDATA1`` 和 ``TDATA2`` 设置 trigger；
TRIGGER 分支清除 trigger；HALTREQ 分支设置 ``DCSR.ebreakm``。debug mode 内出现
异常时跳转到 ``test_fail``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv:L57-L83``）：

.. code-block:: systemverilog

                $sformatf("csrrwi  zero, 0x%0x, %0d",  TSELECT, eh2_trigger_idx),
                $sformatf("csrrw   zero, 0x%0x, x0",   TDATA1),
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

**逐段解释**：

* 第 L57-L60 行：EBREAK 分支选择 trigger index，先清 ``TDATA1``，再把
  ``cfg.gpr[1]`` 写入 ``TDATA2``，最后写 ``TDATA1=5`` 启用 trigger 配置。
* 第 L61-L65 行：EBREAK 不自动推进 ``DPC``，所以代码读取 ``DPC``、加 4、写回
  ``DPC``，然后跳到公共出口 ``4f``。
* 第 L67-L73 行：TRIGGER 分支选择同一 trigger index，并把 ``TDATA1``/``TDATA2``
  清零，再跳到公共出口。
* 第 L75-L83 行：HALTREQ 分支起始于 ``3: nop``，后续代码会设置
  ``DCSR.ebreakm``。

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

**逐段解释**：

* 第 L103-L109 行：debug exception handler 生成两条指令：加载 ``test_fail`` 地址到
  scratch register，再 ``jalr`` 跳转。源注释要求 debug mode 中出现异常立即失败。
* 第 L113-L128 行：``eh2_hardware_triggers_asm_program_gen`` 继承
  ``eh2_asm_program_gen``，只替换 debug ROM class。``gen_debug_rom()`` 创建
  ``eh2_hardware_triggers_debug_rom_gen``，设置 ``cfg`` 和 ``hart``，生成 program
  后把其 ``instr_stream`` 拼入当前 program。

**接口关系**：

* **被调用**：硬件 trigger 测试在选择对应 generator override 时使用这些 class。
* **调用**：调用 ``format_section()``、``gen_section()``、``hart_prefix()`` 和
  自定义 debug ROM ``gen_program()``。
* **共享状态**：``test_fail`` 标签来自 ``eh2_asm_program_gen::gen_test_done()``；
  ``DCSR``、``TSELECT``、``TDATA1``、``TDATA2`` 和 ``DPC`` 枚举来自 riscv-dv。

§6  testlist 与 cosim 策略
--------------------------------------------------------------------------------

§6.1  ``testlist.yaml`` — 常规回归入口字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``testlist.yaml`` 给回归脚本提供 riscv-dv 生成测试、手写 assembly 测试、
RTL UVM test、仿真 plusarg、迭代次数和 cosim 策略。旧文档中的
``no_cosim: true`` 字段在当前文件中不存在。

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
   
       '
     iterations: 20
   - test: riscv_rand_jump_test

**逐段解释**：

* 第 L1-L8 行：``riscv_arithmetic_basic_test`` 使用 ``riscv_instr_base_test`` 作为
  generator test，``gen_opts`` 指定 ``+instr_cnt=10000``、``+boot_mode=m`` 和
  ``+no_csr_instr=1``，RTL test 为 ``core_eh2_base_test``，迭代 10 次。
* 第 L9-L19 行：``riscv_random_instr_test`` 使用 ``riscv_rand_instr_test``，
  开启 interrupt 和 nested interrupt 生成，并设置 RTL 最大 cycle/timeout。
* 第 L28-L37 行：``riscv_csr_test`` 显式写 ``cosim: disabled`` 和
  ``skip_in_signoff: true``。这是当前文件中实际存在的禁用语法。

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
     iterations: 5

**逐段解释**：

* 第 L63-L70 行：``riscv_bitmanip_test`` 使用 ``test_srcs`` 指向
  ``tests/asm/cosim_bitmanip.S``，不是 ``gen_test`` 随机生成入口。
* 第 L72-L88 行：``riscv_bitmanip_full_test`` 和
  ``riscv_bitmanip_balanced_test`` 也复用同一手写 assembly，并分别设置迭代 5 次。
* 第 L90-L105 行：``riscv_bitmanip_otearlgrey_test`` 和 ``riscv_amo_test`` 继续使用
  ``test_srcs`` 手写 assembly 路径；``riscv_amo_test`` 指向
  ``tests/asm/cosim_atomic_basic.S``。

**接口关系**：

* **被调用**：``run_regress.py``、``run_instr_gen.py``、``metadata.py`` 和 signoff
  脚本读取该 YAML。
* **调用**：YAML 不调用函数；字段被 Python 脚本解释。
* **共享状态**：``test`` 名称生成 ``TEST.SEED`` 目录；``rtl_test`` 名称传给 RTL
  simulation；``test_srcs`` 指向手写 assembly 文件。

§6.2  interrupt/debug/PMP/integrity 分类 — 从 YAML 到 plusarg
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：YAML 通过 ``gen_opts`` 和 ``sim_opts`` 把 interrupt、debug、PMP/ePMP 和
integrity 类测试分流给 generator 与 RTL UVM test。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L106-L149``）：

.. code-block:: yaml

   - test: riscv_interrupt_test
     description: Random interrupt test — cosim enabled (issue 53 interrupt cosim)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=20000 +boot_mode=m +enable_interrupt=1 +enable_nested_interrupt=1 +directed_instr_0=eh2_pic_int_stream,5
   
       '
     rtl_test: core_eh2_base_test
     sim_opts: '+enable_irq_seq=1 +max_interval=500
   
       '
     iterations: 15
   - test: riscv_irq_single_test
     description: Single interrupt test — cosim enabled (issue 53)
     gen_test: riscv_rand_instr_test

**逐段解释**：

* 第 L106-L116 行：``riscv_interrupt_test`` 同时在 generator 侧开启 interrupt 和
  nested interrupt，并注入 ``eh2_pic_int_stream``；RTL 侧 ``sim_opts`` 开启
  ``+enable_irq_seq=1``，并设置 ``+max_interval=500``。
* 第 L117-L127 行：``riscv_irq_single_test`` 也开启 generator interrupt，但 RTL
  侧改用 ``+enable_irq_single_seq=1`` 和较小的 ``+max_interval=200``。
* 第 L128-L149 行：debug 类条目使用 ``+enable_debug_seq=1``，``riscv_debug_csr_test``
  还通过 ``+directed_instr_0=eh2_debug_csr_stream,5`` 注入 debug CSR stream。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L203-L288``）：

.. code-block:: yaml

   - test: riscv_pmp_basic_test
     description: Basic PMP region test — cosim enabled (issue 55 PMP fixup)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_pmp=1 +pmp_num_regions=4 +pmp_granularity=0
   
       '
     rtl_test: core_eh2_pmp_basic_test
     iterations: 5
   - test: riscv_pmp_disable_all_test
     description: Disable all PMP regions test — cosim enabled (issue 55)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=5000 +boot_mode=m +enable_pmp=1 +pmp_num_regions=0
   
       '
     rtl_test: core_eh2_pmp_disable_test

**逐段解释**：

* 第 L203-L226 行：PMP 基础、disable-all 和 random 条目都在 ``gen_opts`` 中写入
  ``+enable_pmp=1``，并分别选择 4、0、8 个 PMP region；RTL test 使用
  ``core_eh2_pmp_*``。
* 第 L265-L288 行：ePMP 条目 ``riscv_epmp_mml_test``、
  ``riscv_epmp_mmwp_test`` 和 ``riscv_epmp_rlb_test`` 同样开启 PMP，并设置
  ``+pmp_num_regions=8``。
* 第 L227-L296 行：PC/RF/memory error 注入条目使用各自 ``core_eh2_*_test``。
  这些条目没有在该代码片段中显式写 ``cosim`` 字段。

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

**逐段解释**：

* 第 L298-L306 行：``riscv_rf_addr_intg_test`` 使用 ``cosim: rtl_only``，不是
  ``cosim: disabled``。``run_regress.py`` 会把 ``rtl_only`` 归入禁用 cosim 的值。
* 第 L308-L336 行：``riscv_ram_intg_test``、``riscv_icache_intg_test`` 和
  ``riscv_mem_intg_error_test`` 也写 ``cosim: rtl_only``。这些条目与
  :ref:`adr-0017` 的 integrity cosim waiver 边界相关。

**接口关系**：

* **被调用**：``run_regress.py`` 的 ``build_sim_opts()`` 解释 ``cosim`` 字段。
* **调用**：YAML 不调用函数。
* **共享状态**：``sim_opts`` 中的 ``+enable_irq_seq``、``+enable_debug_seq`` 和
  RTL test 名称必须与 UVM test/sequence 实现匹配。

§6.3  ``run_regress.py`` — cosim 字段的实际解释
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``run_regress.py`` 合并 YAML 与 CLI 的 ``sim_opts``，并在没有手动指定
``+enable_cosim`` 或 ``+disable_cosim`` 时，根据 testlist 的 ``cosim`` 字段追加
最终 cosim plusarg。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L118-L140``）：

.. code-block:: python

   def build_sim_opts(test_entry: dict, cli_sim_opts: str = "") -> str:
       """Merge testlist/CLI sim options and enforce per-test cosim policy."""
       pieces = []
       entry_opts = test_entry.get("sim_opts", "")
       if entry_opts:
           pieces.append(str(entry_opts).replace("\n", " ").strip())
       if cli_sim_opts:
           pieces.append(cli_sim_opts.replace("\n", " ").strip())
   
       cosim = str(test_entry.get("cosim", "enabled")).lower()
       joined = " ".join(piece for piece in pieces if piece).strip()
   
       has_cosim_plusarg = (
           "+enable_cosim=" in joined or
           "+disable_cosim=" in joined
       )
       if not has_cosim_plusarg:

**逐段解释**：

* 第 L118-L126 行：函数先把 testlist 中的 ``sim_opts`` 和 CLI 传入的
  ``cli_sim_opts`` 归一化为单行字符串，并按顺序加入 ``pieces``。
* 第 L127-L128 行：``cosim`` 字段缺省为 ``enabled``，再转成小写。
* 第 L130-L133 行：如果用户已经在 ``sim_opts`` 中手动写了 ``+enable_cosim=`` 或
  ``+disable_cosim=``，后续逻辑不会再追加自动策略。

**关键代码** （``dv/uvm/core_eh2/scripts/run_regress.py:L134-L140``）：

.. code-block:: python

       if not has_cosim_plusarg:
           if cosim in ("disabled", "disable", "false", "0", "no", "rtl_only"):
               pieces.append("+disable_cosim=1")
           else:
               pieces.append("+enable_cosim=1")
   
       return " ".join(piece for piece in pieces if piece).strip()

**逐段解释**：

* 第 L134-L136 行：没有显式 plusarg 时，``disabled``、``disable``、``false``、
  ``0``、``no`` 和 ``rtl_only`` 都会追加 ``+disable_cosim=1``。
* 第 L137-L138 行：其他值，包括字段缺省的 ``enabled``，都会追加
  ``+enable_cosim=1``。
* 第 L140 行：函数返回合并后的仿真 plusarg 字符串。由此可见，当前流程没有
  ``no_cosim: true`` 这种字段解释路径。

**接口关系**：

* **被调用**：``run_single_test()`` 在构建仿真命令前调用该函数。
* **调用**：仅执行字符串处理，无外部命令。
* **共享状态**：testlist 中 ``cosim`` 字段和手动 ``sim_opts`` plusarg 共同决定
  RTL 仿真是否启用 cosim scoreboard。

§7  生成与编译脚本路径
--------------------------------------------------------------------------------

§7.1  overlay testlist — 保持主 YAML 不变
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``run_instr_gen.py`` 读取主 testlist 单个条目，强制本次生成
``iterations=1``，合并基础 ``gen_opts`` 和 metadata/CLI 额外选项，写出 per-run
overlay YAML。

**关键代码** （``dv/uvm/core_eh2/scripts/run_instr_gen.py:L38-L68``）：

.. code-block:: python

   def load_test_entry(testlist_path: str, test_name: str) -> dict:
       """Load one EH2 test entry for riscv-dv."""
       with open(testlist_path, "r", encoding="utf-8") as f:
           entries = yaml.safe_load(f)
   
       for entry in entries:
           if entry.get("test") == test_name:
               return dict(entry)
   
       raise KeyError(f"Test {test_name} not found in {testlist_path}")
   
   
   def write_overlay_testlist(work_dir: str, test_name: str,
                              extra_gen_opts: str = "") -> str:
       """Create a per-run testlist that carries CLI generator plusargs."""
       entry = load_test_entry(DEFAULT_TESTLIST, test_name)
       entry["iterations"] = 1

**逐段解释**：

* 第 L38-L47 行：``load_test_entry()`` 用 ``yaml.safe_load`` 读取 YAML list，按
  ``test`` 字段匹配条目，返回该条目的 copy；找不到时抛 ``KeyError``。
* 第 L50-L54 行：``write_overlay_testlist()`` 总是从 ``DEFAULT_TESTLIST`` 读取条目，
  并把本次 overlay 的 ``iterations`` 改为 1。
* 第 L56-L68 行：函数 strip YAML folded scalar 的换行，将基础 ``gen_opts`` 与额外
  ``gen_opts`` 拼接，再把单条 entry 写入 ``work_dir/riscv_dv_testlist.yaml``。

**接口关系**：

* **被调用**：``run_instr_gen()`` 在构造 riscv-dv 命令前调用
  ``write_overlay_testlist()``。
* **调用**：调用 ``load_test_entry()``、``yaml.safe_dump()``。
* **共享状态**：主 ``testlist.yaml`` 不被修改；每个 ``TEST.SEED`` 的 generator
  输入由 overlay 文件记录。

§7.2  ``run_instr_gen()`` — riscv-dv 命令构造
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该函数构造并运行 ``vendor/google_riscv-dv/run.py``，只执行
``--steps gen``，生成 assembly 后把 stdout/stderr 写到 ``<test>_gen.log``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_instr_gen.py:L87-L116``）：

.. code-block:: python

       riscv_dv_dir = os.path.abspath(riscv_dv_dir)
       work_dir = os.path.abspath(work_dir)
       os.makedirs(work_dir, exist_ok=True)
   
       # riscv-dv run.py command
       riscv_dv_run = os.path.join(riscv_dv_dir, "run.py")
       if not os.path.exists(riscv_dv_run):
           print(f"Error: riscv-dv run.py not found at {riscv_dv_run}")
           return False
   
       testlist_path = write_overlay_testlist(work_dir, test_name, gen_opts)
   
       cmd = [
           sys.executable, riscv_dv_run,
           "--test", test_name,
           "--target", "rv32imc",
           "-o", work_dir,
           "--steps", "gen",
           "--seed", str(seed),
           "--iterations", str(iterations),
           "--isa", "rv32imac",
           "--mabi", "ilp32",
           "--testlist", testlist_path,
           "--sim_opts", build_sim_opts(),
       ]

**逐段解释**：

* 第 L87-L95 行：路径转绝对路径后，函数检查 ``run.py`` 是否存在；不存在时直接
  返回 ``False``。
* 第 L97 行：函数先写 overlay testlist，再把 overlay 路径传给 riscv-dv。
* 第 L99-L111 行：命令固定使用 ``--target rv32imc``、``--steps gen``、
  ``--isa rv32imac`` 和 ``--mabi ilp32``，并传入 seed、iterations、输出目录和
  EH2 ``--sim_opts``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_instr_gen.py:L113-L139``）：

.. code-block:: python

       # Add custom extension
       if os.path.exists(os.path.join(EXT_DIR, "user_extension.svh")):
           cmd.extend(["--custom_target", EXT_DIR])
   
       print(f"Running instruction generator: {' '.join(cmd)}")
   
       try:
           result = subprocess.run(
               cmd,
               stdout=subprocess.PIPE,
               stderr=subprocess.STDOUT,
               timeout=600,
               cwd=work_dir
           )
   
           output = result.stdout.decode("utf-8", errors="replace")
           log_path = os.path.join(work_dir, f"{test_name}_gen.log")

**逐段解释**：

* 第 L113-L116 行：只有当 ``user_extension.svh`` 存在时才追加 ``--custom_target``。
* 第 L119-L126 行：``subprocess.run`` 在 ``work_dir`` 中执行，捕获 stdout/stderr，
  timeout 为 600 秒。
* 第 L128-L139 行：输出写入 ``<test>_gen.log``；返回码非 0 时打印失败并返回
  ``False``，成功时返回 ``True``。

**接口关系**：

* **被调用**：``run_from_metadata()`` 和 CLI ``main()`` 调用该函数。
* **调用**：调用 ``write_overlay_testlist()``、``build_sim_opts()`` 和
  ``subprocess.run()``。
* **共享状态**：``work_dir`` 是 generator 输出目录，也是后续 compile 阶段查找
  assembly 的目录。

§7.3  ``compile_test.py`` — include 目录与 ISA 编译边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：编译脚本从 metadata 或命令行找到 assembly，用 riscv32 GCC 生成 ELF/bin，
可选生成 VMA-addressed hex。它把 riscv-dv 和 EH2 扩展目录加入 include path。

**关键代码** （``dv/uvm/core_eh2/scripts/compile_test.py:L179-L187``）：

.. code-block:: python

   def default_include_dirs(riscv_dv_dir: str = "") -> list:
       """Return include dirs needed by riscv-dv generated assembly."""
       include_dirs = []
       resolved_riscv_dv_dir = resolve_riscv_dv_dir(riscv_dv_dir)
       if resolved_riscv_dv_dir:
           _append_existing_dir(
               include_dirs, os.path.join(resolved_riscv_dv_dir, "user_extension"))
       _append_existing_dir(include_dirs, EXT_DIR)
       return include_dirs

**逐段解释**：

* 第 L179-L183 行：函数先解析 riscv-dv root，找到后加入其
  ``user_extension`` 目录。
* 第 L186-L187 行：函数再追加 EH2 ``EXT_DIR``。因此 riscv-dv 生成 assembly 和
  EH2 custom include 都可被 GCC 找到。

**关键代码** （``dv/uvm/core_eh2/scripts/compile_test.py:L268-L318``）：

.. code-block:: python

   def compile_assembly(asm_path: str, bin_path: str, linker_script: str,
                        gcc_prefix: str = "riscv32-unknown-elf",
                        include_dirs: list = None,
                        riscv_dv_dir: str = "",
                        hex_path: str = "") -> bool:
       """
       Compile RISC-V assembly to binary.
       """
       bin_dir = os.path.dirname(bin_path)
       if bin_dir:
           os.makedirs(bin_dir, exist_ok=True)
   
       gcc = f"{gcc_prefix}-gcc"
       objcopy = f"{gcc_prefix}-objcopy"
   
       # Object file path
       obj_path = bin_path.replace(".bin", ".o")
       elf_path = bin_path.replace(".bin", ".elf")

**逐段解释**：

* 第 L268-L272 行：函数参数包含 assembly 输入、binary 输出、linker script、
  GCC prefix、额外 include 目录、riscv-dv root 和可选 hex path。
* 第 L285-L291 行：函数创建输出目录，并由 ``gcc_prefix`` 推导 ``gcc`` 和
  ``objcopy`` 命令名。
* 第 L293-L295 行：函数推导 object 和 ELF 路径，随后删除 ``obj_path`` 变量；
  实际编译流程直接产出 ELF。

**关键代码** （``dv/uvm/core_eh2/scripts/compile_test.py:L297-L318``）：

.. code-block:: python

       compile_include_dirs = default_include_dirs(riscv_dv_dir)
       for include_dir in include_dirs or []:
           _append_existing_dir(compile_include_dirs, include_dir)
       include_opts = [f"-I{include_dir}" for include_dir in compile_include_dirs]
   
       # Compile assembly to object
       # rv32imac base + zba/zbb bitmanip subsets supported by host gcc 11.1.
       # zbc/zbs need gcc 12+; re-add when the toolchain is upgraded.
       compile_cmd = [
           gcc,
           "-march=rv32imac_zba_zbb",
           "-mabi=ilp32",
           "-static",
           "-mcmodel=medany",
           "-fvisibility=hidden",
           "-nostdlib",
           "-nostartfiles",
           *include_opts,
           "-T", linker_script,

**逐段解释**：

* 第 L297-L300 行：默认 include 目录和调用方传入的 include 目录合并为
  ``-I`` 选项，且 ``_append_existing_dir`` 会去重并跳过不存在目录。
* 第 L303-L304 行：源注释明确当前 host GCC 11.1 只支持 RV32IMAC 加 Zba/Zbb
  bitmanip 子集；Zbc/Zbs 等待工具链支持后再重新加入。
* 第 L305-L318 行：GCC 命令使用 ``-march=rv32imac_zba_zbb``、``-mabi=ilp32``、
  ``-nostdlib``、``-nostartfiles``，并通过 ``-T`` 指定 linker script。

**接口关系**：

* **被调用**：``compile_from_metadata()`` 调用 ``compile_assembly()``。
* **调用**：调用 GCC、objcopy 和本地 ``write_vma_hex_from_elf()``。
* **共享状态**：``-march`` 与 ``eh2_bitmanip_stream`` 的 Zba/Zbb 子集一致；linker
  script 决定 ``_start``、``.debug_module``、``.signature`` 等 section 的地址。

§8  trace CSV 与 coverage 入口
--------------------------------------------------------------------------------

§8.1  ``eh2_log_to_trace_csv.py`` — EH2 log 到 riscv-dv CSV
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该脚本把 EH2 仿真日志行解析成 riscv-dv ``RiscvInstructionTraceEntry``，
用于后续 functional coverage 或 trace 处理。

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

**逐段解释**：

* 第 L8-L11 行：脚本只依赖标准库 ``argparse``、``os``、``re`` 和 ``sys``。
* 第 L13-L16 行：``_EH2_ROOT`` 从当前脚本目录向上四级推导，``_DV_SCRIPTS`` 指向
  ``vendor/google_riscv-dv/scripts``。
* 第 L20-L31 行：脚本临时把 riscv-dv scripts 目录插入 ``sys.path``，导入
  ``RiscvInstructionTraceCsv``、``RiscvInstructionTraceEntry``、
  ``get_imm_hex_val`` 和 helper 后恢复原 ``sys.path``。

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

**逐段解释**：

* 第 L35-L38 行：注释给出 EH2 trace 行格式和示例：time、cycle、PC、binary、
  instruction 和 operands。
* 第 L39-L41 行：``INSTR_RE`` 提取 ``time``、``cycle``、``pc``、``bin`` 和
  ``instr``。其中 ``instr`` pattern 是两个非空字段拼接，覆盖 mnemonic 加 operand
  字符串的基本形态。
* 第 L42-L45 行：``RD_RE`` 提取 ``xN=0x...`` 写回，``ADDR_RE`` 识别
  ``rd,imm(rs1)`` 形态。

§8.2  log parser 主循环 — 截止 ECALL 并写 CSV entry
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：主解析函数逐行扫描日志，遇到 ``ecall`` 停止；匹配 trace 行后构造 CSV
entry，并在 full trace 模式下展开 operand。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L48-L93``）：

.. code-block:: python

   def _process_eh2_sim_log_fd(log_fd, csv_fd, full_trace=True):
       """Process EH2 simulation log.
   
       Reads from log_fd, which should be a file object containing a trace from an
       EH2 simulation. Writes in a standard CSV format to csv_fd, which should be
       a file object opened for writing.
       """
       instr_cnt = 0
   
       trace_csv = RiscvInstructionTraceCsv(csv_fd)
       trace_csv.start_new_trace()
   
       trace_entry = None
   
       for line in log_fd:
           if re.search("ecall", line):

**逐段解释**：

* 第 L48-L58 行：docstring 明确输入是 EH2 simulation trace file object，输出是
  标准 CSV file object；``full_trace`` 控制是否展开 operand。
* 第 L59-L63 行：函数初始化 instruction count，创建
  ``RiscvInstructionTraceCsv`` 并调用 ``start_new_trace()``。
* 第 L66-L68 行：循环读取日志行，遇到包含 ``ecall`` 的行立即 ``break``。这使
  ``ECALL`` 之后的日志不会进入 CSV。

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

**逐段解释**：

* 第 L71-L75 行：不匹配 ``INSTR_RE`` 的日志行被跳过；匹配行使
  ``instr_cnt`` 加 1。
* 第 L77-L83 行：函数创建 ``RiscvInstructionTraceEntry``，填入原始 instruction
  字符串、mnemonic、PC 和 binary；full trace 模式下调用 ``expand_trace_entry()``。
* 第 L85-L89 行：如果日志行含 GPR 写回，脚本用 ``gpr_to_abi()`` 把 ``xN`` 转成
  ABI 名称，再写入 ``trace_entry.gpr``。
* 第 L91-L93 行：entry 写入 CSV，并返回处理过的 instruction 数。

**接口关系**：

* **被调用**：``process_eh2_sim_log()`` 和 CLI ``main()`` 调用该内部函数。
* **调用**：调用 riscv-dv CSV writer、``expand_trace_entry()``、``gpr_to_abi()``。
* **共享状态**：CSV 字段格式由 ``vendor/google_riscv-dv/scripts`` 中的
  ``riscv_trace_csv`` 定义。

§8.3  operand 与 immediate 处理 — ABI 名称和 branch offset
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：展开 trace entry 时，脚本把 GPR operand 转为 ABI 名称，把 load/store
address operand 拆成 ``rd,rs1,imm``，并把 branch/jump 绝对目标转换成相对 PC 的
immediate。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L117-L165``）：

.. code-block:: python

   def convert_operands_to_abi(operand_str):
       """Convert the operand string to use ABI register naming.
       """
       operand_list = operand_str.split(",")
       for i in range(len(operand_list)):
           converted_op = gpr_to_abi(operand_list[i])
           if converted_op != "na":
               operand_list[i] = converted_op
       return ",".join(operand_list)
   
   
   def expand_trace_entry(trace, operands):
       '''Expands a CSV trace entry for a single instruction.
   
       Operands are added to the CSV entry, converting from the raw

**逐段解释**：

* 第 L117-L141 行：``convert_operands_to_abi()`` 以逗号分割 operand；每个字段用
  ``gpr_to_abi()`` 尝试转换，返回值不是 ``na`` 时替换为 ABI 名称。
* 第 L144-L150 行：``expand_trace_entry()`` 的 docstring 明确目标是给 CSV entry
  添加 operand，并把 raw register name 转为 ABI naming。
* 第 L151-L154 行：函数先调用 ``process_imm()``，再用 riscv-dv helper
  ``convert_pseudo_instr()`` 把 pseudo instruction 转换成标准 instruction/operand。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L155-L181``）：

.. code-block:: python

       # process any instructions of the form:
       # <instr> <reg> <imm>(<reg>)
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

**逐段解释**：

* 第 L155-L160 行：当 operand 符合 ``rd,imm(rs1)`` 形式时，脚本把 immediate 写入
  ``trace.imm``，并把 operand 改写为 ``rd,rs1,imm``。
* 第 L162-L165 行：最终 operand 统一经过 ``convert_operands_to_abi()``，写入
  ``trace.operand``。
* 第 L167-L181 行：``process_imm()`` 只处理 branch/jump 类 instruction；它把目标
  immediate 减去当前 PC，返回 RISC-V trace 约定下的相对 immediate。

**接口关系**：

* **被调用**：``_process_eh2_sim_log_fd()`` 调用 ``expand_trace_entry()``。
* **调用**：调用 riscv-dv helper ``get_imm_hex_val``、``convert_pseudo_instr``、
  ``sint_to_hex`` 和 ``gpr_to_abi``。
* **共享状态**：functional coverage flow 假定 operand 已使用 ABI register naming；
  该假定写在源代码注释中。

§8.4  UVM log pass/fail 检查与 CLI
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：同一脚本还提供 UVM log pass/fail 检查函数和命令行入口。检查函数在看到
test result 后继续防止重复 PASS/FAIL，CLI 则把 ``--log``、``--csv`` 和
``--full_trace`` 暴露给用户。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L184-L256``）：

.. code-block:: python

   def check_eh2_uvm_log(uvm_log):
       """Process EH2 UVM simulation log.
       """
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

**逐段解释**：

* 第 L184-L207 行：函数初始化 ``passed``、``failed``、错误行号、错误行文本、
  摘要输出和 ``Failure_Modes.NONE``。
* 第 L209-L216 行：函数读取 UVM log，并用 ``test_result_seen`` 标记已经看到测试
  结果。源注释说明 UVM summary 可能包含 ``UVM_ERROR`` 字样，不能在结果后继续把它
  当作失败来源。
* 第 L218-L256 行：循环中在结果前检测 ``UVM_ERROR``、``UVM_FATAL`` 或 ``Error``；
  看到 ``RISC-V UVM TEST PASSED`` 设置 passed，看到 ``RISC-V UVM TEST FAILED``
  设置 failed 并退出。失败时提取错误行前后各约 5 行作为摘要，并把 wall-clock
  timeout 映射成 ``Failure_Modes.TIMEOUT``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py:L259-L283``）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser()
       parser.add_argument("--log",
                           help="Input EH2 simulation log (default: stdin)",
                           type=argparse.FileType('r'),
                           default=sys.stdin)
       parser.add_argument("--csv",
                           help="Output trace csv file (default: stdout)",
                           type=argparse.FileType('w'),
                           default=sys.stdout)
       parser.add_argument("--full_trace", type=int, default=1,
                           help="Enable full log trace")
   
       args = parser.parse_args()
   
       _process_eh2_sim_log_fd(args.log, args.csv,

**逐段解释**：

* 第 L259-L270 行：CLI 支持 ``--log``、``--csv`` 和 ``--full_trace``；默认从
  stdin 读、向 stdout 写，full trace 默认开启。
* 第 L272-L275 行：入口把 parsed file object 传给 ``_process_eh2_sim_log_fd()``。
* 第 L278-L283 行：脚本作为 main 执行时捕获 ``RuntimeError``，向 stderr 写
  ``Error: ...``，并以 riscv-dv ``RET_FATAL`` 退出。

**接口关系**：

* **被调用**：命令行直接调用 ``main()``；其他 Python 代码可调用
  ``process_eh2_sim_log()`` 或 ``check_eh2_uvm_log()``。
* **调用**：调用 ``argparse``、``_process_eh2_sim_log_fd()`` 和
  ``Failure_Modes``。
* **共享状态**：log 中 PASS/FAIL 字符串必须与 UVM testbench 输出保持一致。

§9  链接地址与功能覆盖 testlist
--------------------------------------------------------------------------------

§9.1  ``ddm_link.ld`` — discrete debug module 地址空间
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该 linker script 把常规程序段放在 main memory，把 ``.debug_module`` 和
``.dm_scratch`` 放到离散 debug module 地址窗口。

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

**逐段解释**：

* 第 L17-L18 行：输出架构为 ``riscv``，入口为 ``_start``，与
  ``eh2_asm_program_gen`` 的 ``_start:`` 标签对应。
* 第 L20-L24 行：``main`` memory 从 ``0x80000000`` 开始，长度 ``0x100000``；
  ``dm`` memory 从 ``0x1A110000`` 开始，长度 ``0x1000``。
* 第 L26 行：``_dm_scratch_len`` 固定为 ``0x100``。

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

**逐段解释**：

* 第 L30-L57 行：``.text``、``.tohost``、``.page_table``、``.data``、
  ``.user_stack``、``.kernel_data``、``.kernel_stack`` 和 ``.bss`` 都映射到
  ``main``。
* 第 L58-L62 行：``_end`` 记录当前位置，``.debug_module`` 映射到 ``dm``。
* 第 L63-L67 行：``.dm_scratch`` 在 ``dm`` 中 4-byte 对齐，预留
  ``_dm_scratch_len`` 字节，并用 ``=0`` 填充。

**接口关系**：

* **被调用**：编译 directed debug/module 测试时可通过 test entry 的 linker script
  字段选择该文件。
* **调用**：linker script 不调用代码。
* **共享状态**：``_start``、``.debug_module`` 和 debug ROM 生成逻辑共享 section
  名称和地址约定。

§9.2  coverage 和 ML testlist — 非常规运行入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``cov_testlist.yaml`` 为 riscv-dv instruction functional coverage 提供
两个不跑 ISS/GCC/post-compare 的入口；``ml_testlist.yaml`` 提供参数密集的随机
配置集合。

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

**逐段解释**：

* 第 L1-L8 行：``riscv_instr_cov_debug_test`` 标明不是 core functional test，
  迭代 1 次，并禁用 ISS、GCC 和 post compare。
* 第 L10-L18 行：``riscv_instr_cov_test`` 描述为从 CSV trace log 解析 instruction
  信息并采样 functional coverage，同样禁用 ISS、GCC 和 post compare。

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
       +fix_sp=0
       +enable_illegal_csr_instruction=0
       +enable_access_invalid_csr_level=0

**逐段解释**：

* 第 L62-L90 行：``riscv_rand_test`` 展开大量 generator knob，包括 instruction
  数、sub-program 数、PMP CSR 写入、illegal/hint 比例、``no_wfi``、``no_csr_instr``
  和 bitmanip group 配置。
* 第 L91-L113 行：同一条目配置 11 个 stream 名称和频率，覆盖 load/store、loop、
  hazard、memory region、jump 和 numeric corner stream。
* 第 L114-L119 行：该条目设置 ``no_iss: 1``、``gcc_opts: -mno-strict-align``、
  ``gen_test: riscv_ml_test``、``rtl_test: core_eh2_reset_test`` 和
  ``no_post_compare: 1``。

**接口关系**：

* **被调用**：coverage 或 ML 风格流程显式选择这些 YAML 时使用。
* **调用**：YAML 不调用函数。
* **共享状态**：coverage YAML 依赖 ``eh2_log_to_trace_csv.py`` 生成的 trace CSV；
  ML YAML 中 stream 名称来自 riscv-dv 内置 stream 和 EH2 custom stream。

§10  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`appendix_b_uvm_riscv_dv_ext`、:ref:`agent_trace`、
  :ref:`cosim_scoreboard`、:ref:`pmp_coverage`、:doc:`../06_flows/regression_flow`、
  :doc:`../06_flows/build_flow`。
* 关联 ADR：:ref:`adr-0006`、:ref:`adr-0007`、:ref:`adr-0008`、
  :ref:`adr-0009`、:ref:`adr-0010`、:ref:`adr-0017`。
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/user_extension.svh``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/cov_testlist.yaml``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/ddm_link.ld``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_instr_gen.py``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_regress.py``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/scripts/compile_test.py``

§11  与 Ibex 工业实现对照
--------------------------------------------------------------------------------

Ibex 的 riscv-dv extension 是 EH2 的直接工业参照：二者都通过 target 目录提供
``riscv_core_setting.sv``、user extension、directed instruction library 和 testlist
YAML，再由脚本生成 ASM、编译 ELF/HEX 并交给 RTL 回归。EH2 的差异主要来自 VeeR EH2
ISA/CSR/interrupt/debug/PMP surface：默认 ISA 字符串包含 ``rv32imac`` 与 bitmanip
Zb*，并需要处理双线程、EH2 custom CSR、PIC 和 trace/probe cosim waiver。

.. list-table:: riscv-dv extension 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - 目录
     - ``/home/host/ibex/dv/uvm/core_ibex/riscv_dv_extension``
     - ``dv/uvm/core_eh2/riscv_dv_extension``
   * - core setting
     - Ibex CSR/interrupt/debug 配置
     - EH2 ISA、custom CSR、PIC/debug/PMP 约束
   * - testlist
     - Ibex random/directed/template
     - EH2 random、directed mix、cosim waiver 标记和 ML/cov 辅助 YAML
   * - trace compare
     - Ibex RVFI/ISS compare
     - EH2 trace/probe/Spike DPI compare
   * - sign-off 数字
     - Ibex 由 core_ibex regression metadata 统计
     - 2026-05-19 demo：370/395 (93.67%)

§12  Sign-off 关联
--------------------------------------------------------------------------------

riscv-dv extension 是当前随机验证主力。2026-05-19 VCS demo 中 riscv-dv stage 为
370/395 (93.67%)，受 25% fail-rate ceiling、cosim-disabled waiver 和 testlist
``skip_in_signoff`` 规则约束。修改 generator option、testlist iteration、CSR 约束或
trace CSV 转换后，应同步检查 ``dv/uvm/core_eh2/waivers/cosim-disabled.yaml``、
``signoff.py`` waiver gate 和 ``ibex_capability_matrix`` 中的对照口径。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
