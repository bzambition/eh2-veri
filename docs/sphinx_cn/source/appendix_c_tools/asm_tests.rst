.. _appendix_c_tools_asm_tests:
.. _appendix_c_tools/asm_tests:

汇编测试源码字典
================

:status: draft
:source: dv/uvm/core_eh2/tests/asm/Makefile
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
------------------------------------------------------------------------------------------------------------------------

本章说明 EH2 验证仓库中的手写 RISC-V 汇编测试。这里的对象不是
``riscv-dv`` 随机生成程序，而是 :file:`dv/uvm/core_eh2/tests/asm/`
和 :file:`tests/asm/` 下已经提交的 ``.S``、linker script、Makefile 与
testlist 绑定关系。所有行为描述均来自这些源文件：mailbox 约定、trap
处理、PMP CSR 写入、AXI4 error 注入 plusarg、NB-load 序列、以及覆盖
toggle pump 都直接在汇编或 YAML 中出现。

本章覆盖的主要源文件分为 5 类：

* :file:`dv/uvm/core_eh2/tests/asm/Makefile`：本地汇编测试构建入口。
* :file:`dv/uvm/core_eh2/tests/asm/cosim_*.S`：cosim lockstep proof
  汇编程序。
* :file:`dv/uvm/core_eh2/tests/asm/directed_*.S`：directed 汇编程序。
* :file:`dv/uvm/core_eh2/directed_tests/*.yaml`：将汇编文件注册到回归的
  testlist。
* :file:`tests/asm/*.S` 与 :file:`tests/asm/smoke.ld`：仓库根部的最小
  smoke/nop 样例。

§1.1  汇编测试数据流
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

手写汇编测试的公共行为可以从 Makefile、linker script 和 mailbox 写入序列倒推：
GCC 生成 ELF，``objdump`` 生成反汇编，``objcopy -O verilog`` 生成 hex；
仿真侧加载 hex 后，程序在通过或失败路径写 mailbox 地址 ``0xD0580000``。

::

   .S source
      |
      v
   riscv32-unknown-elf-gcc + cosim_link.ld
      |
      +--> hex/<test>.elf
      |        |
      |        +--> objdump -d --> hex/<test>.dis
      |        |
      |        +--> objcopy -O verilog --> hex/<test>.hex
      |
      v
   RTL/UVM loads program
      |
      v
   assembly writes 0xFF or 0x01 to 0xD0580000

接口关系：

* 被调用：本章的汇编程序由 :file:`dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
  和 :file:`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml` 注册。
* 调用：汇编程序本身不调用 C runtime；Makefile 使用 bare-metal
  ``-nostdlib -nostartfiles``。
* 共享状态：所有 pass/fail 路径共用 mailbox 地址 ``0xD0580000``。

§2  ``tests/asm/Makefile`` 构建入口
------------------------------------------------------------------------------------------------------------------------

职责：该 Makefile 定义 RISC-V 工具链前缀、目标 ISA/ABI、linker script、
输出目录和 ELF 到 HEX 的转换规则。它只把 4 个 cosim 汇编程序纳入
``all`` target，并没有自动遍历目录下所有 ``.S`` 文件。

§2.1  工具链、ISA 与 linker 变量
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/Makefile:L10-L23``）：

.. code-block:: makefile

   RISCV_PREFIX ?= /home/Riscv_Tools/bin/riscv32-unknown-elf-
   CC      = $(RISCV_PREFIX)gcc
   OBJCOPY = $(RISCV_PREFIX)objcopy
   OBJDUMP = $(RISCV_PREFIX)objdump

   ARCH    = rv32imac
   ABI     = ilp32
   LINKER  = cosim_link.ld

   CFLAGS  = -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -ffreestanding
   LDFLAGS = -T $(LINKER) -nostdlib

   OUT_DIR = hex

逐段解释：

* 第 10~13 行：工具链前缀默认指向
  ``/home/Riscv_Tools/bin/riscv32-unknown-elf-``。``gcc``、``objcopy`` 与
  ``objdump`` 都通过此前缀派生，因此外部可以通过覆盖 ``RISCV_PREFIX``
  切换工具链位置。
* 第 15~17 行：构建使用 ``rv32imac`` 与 ``ilp32``，linker script 固定为
  ``cosim_link.ld``。
* 第 19~20 行：``-nostdlib``、``-nostartfiles`` 和 ``-ffreestanding`` 表明这些
  汇编测试不依赖启动文件或标准库，入口由汇编文件中的 ``_start`` 提供。
* 第 22 行：输出目录固定为 ``hex``，后续 ELF、HEX 和 DIS 文件都写入该目录。

接口关系：

* 被调用：可由开发者在 :file:`dv/uvm/core_eh2/tests/asm/` 下执行 ``make all``。
* 调用：``gcc``、``objdump``、``objcopy``。
* 共享状态：``RISCV_PREFIX``、``ARCH``、``ABI``、``LINKER``、``OUT_DIR``。

§2.2  ``all`` target 与单测构建规则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/Makefile:L24-L42``）：

.. code-block:: makefile

   .PHONY: all clean

   all: $(OUT_DIR)/cosim_smoke.hex $(OUT_DIR)/cosim_alu.hex $(OUT_DIR)/cosim_load_store.hex $(OUT_DIR)/cosim_dual_issue.hex
           @echo "=== All tests built ==="

   $(OUT_DIR):
           mkdir -p $(OUT_DIR)

   $(OUT_DIR)/cosim_smoke.elf: cosim_smoke.S $(LINKER) | $(OUT_DIR)
           $(CC) $(CFLAGS) $(LDFLAGS) -o $@ cosim_smoke.S

   $(OUT_DIR)/cosim_alu.elf: cosim_alu.S $(LINKER) | $(OUT_DIR)
           $(CC) $(CFLAGS) $(LDFLAGS) -o $@ cosim_alu.S

   $(OUT_DIR)/cosim_load_store.elf: cosim_load_store.S $(LINKER) | $(OUT_DIR)
           $(CC) $(CFLAGS) $(LDFLAGS) -o $@ cosim_load_store.S

   $(OUT_DIR)/cosim_dual_issue.elf: cosim_dual_issue.S $(LINKER) | $(OUT_DIR)
           $(CC) $(CFLAGS) $(LDFLAGS) -o $@ cosim_dual_issue.S

逐段解释：

* 第 24 行：``all`` 与 ``clean`` 被声明为 phony target，避免同名文件影响执行。
* 第 26~27 行：``all`` 只依赖 ``cosim_smoke``、``cosim_alu``、
  ``cosim_load_store`` 和 ``cosim_dual_issue`` 的 HEX 产物；其它 ``cosim_*`` 和
  ``directed_*`` 源文件不会被该 target 自动构建。
* 第 29~30 行：``hex`` 目录通过 order-only prerequisite 创建，使单个 ELF 规则在
  输出目录不存在时仍可执行。
* 第 32~42 行：每个 ELF 规则都显式列出对应 ``.S`` 源文件和 ``cosim_link.ld``，
  并复用同一组 ``CFLAGS``、``LDFLAGS``。

接口关系：

* 被调用：``all`` 依赖 4 个 ``%.hex`` 目标。
* 调用：4 条 ELF 编译命令。
* 共享状态：``$(OUT_DIR)`` 目录和 ``$(LINKER)`` 文件。

§2.3  ELF 到 HEX/DIS 转换和清理
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/Makefile:L44-L49``）：

.. code-block:: makefile

   $(OUT_DIR)/%.hex: $(OUT_DIR)/%.elf
           $(OBJDUMP) -d $< > $(basename $@).dis
           $(OBJCOPY) -O verilog $< $@

   clean:
           rm -rf $(OUT_DIR)/*.elf $(OUT_DIR)/*.hex $(OUT_DIR)/*.dis

逐段解释：

* 第 44 行：pattern rule 将任意 ``hex/<name>.elf`` 转换为 ``hex/<name>.hex``。
* 第 45 行：``objdump -d`` 先生成同名 ``.dis`` 文件，便于人工检查程序布局和指令。
* 第 46 行：``objcopy -O verilog`` 生成仿真常用的 Verilog HEX 格式。
* 第 48~49 行：``clean`` 只删除 ``hex`` 目录下的 ``.elf``、``.hex`` 和 ``.dis``，
  不触碰源文件和 linker script。

接口关系：

* 被调用：所有 ``$(OUT_DIR)/%.hex`` 目标。
* 调用：``objdump``、``objcopy`` 和 ``rm``。
* 共享状态：``hex`` 目录中的构建产物。

§3  linker script 与入口布局
------------------------------------------------------------------------------------------------------------------------

职责：汇编测试使用两个 linker script。cosim/directed 测试使用
:file:`dv/uvm/core_eh2/tests/asm/cosim_link.ld`，仓库根部 smoke/nop 样例使用
:file:`tests/asm/smoke.ld`。两者都把入口定义为 ``_start``。

§3.1  ``cosim_link.ld`` 的单地址空间布局
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_link.ld:L5-L26``）：

.. code-block:: bash

   OUTPUT_ARCH("riscv")
   ENTRY(_start)

   SECTIONS
   {
       . = 0x80000000;
       .text : {
           *(.text.init)
           *(.text*)
       }
       .data : ALIGN(4) {
           *(.data*)
           *(.rodata*)
           *(.sdata*)
       }
       .bss : ALIGN(4) {
           *(.bss*)
           *(.sbss*)
       }
       . = ALIGN(16);
       _stack_top = .;
   }

逐段解释：

* 第 5~6 行：输出架构为 RISC-V，入口符号为 ``_start``。
* 第 10~14 行：地址计数器从 ``0x80000000`` 开始，``.text.init`` 排在普通
  ``.text`` 前面。这与 cosim 汇编源文件中统一使用 ``.section .text.init`` 对齐。
* 第 15~23 行：``.data``、``.rodata``、``.sdata``、``.bss`` 和 ``.sbss`` 都放在同一
  地址空间内，并对 data/bss 做 4 字节对齐。
* 第 24~25 行：末尾 16 字节对齐后导出 ``_stack_top``；嵌套 trap 测试会使用该符号
  初始化 ``sp``。

接口关系：

* 被调用：Makefile 的 ``LDFLAGS=-T $(LINKER)`` 和 YAML 的 ``ld_script`` 字段。
* 调用：linker section 匹配规则。
* 共享状态：``_start`` 和 ``_stack_top`` 符号。

§3.2  根部 ``smoke.ld`` 的 BOOT/RAM 分区
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``tests/asm/smoke.ld:L1-L27``）：

.. code-block:: bash

   OUTPUT_FORMAT("elf32-littleriscv")
   OUTPUT_ARCH(riscv)
   ENTRY(_start)

   MEMORY
   {
       BOOT (rxai!rw) : ORIGIN = 0x80000000, LENGTH = 4K
       RAM (wxa!ri)   : ORIGIN = 0x80001000, LENGTH = 60K
   }

   SECTIONS
   {
       .text : {
           *(.text*)
       } > BOOT

       .data : {
           *(.data*)
           *(.sdata*)
           *(.rodata*)
       } > RAM

       .bss : {
           *(.bss*)
           *(.sbss*)
       } > RAM

逐段解释：

* 第 1~3 行：根部样例也生成 little-endian RISC-V ELF，并以 ``_start`` 为入口。
* 第 5~9 行：该 linker script 显式拆分 ``BOOT`` 和 ``RAM``：``BOOT`` 从
  ``0x80000000`` 开始、长度 4 KB；``RAM`` 从 ``0x80001000`` 开始、长度 60 KB。
* 第 13~21 行：``.text`` 放入 ``BOOT``，数据类 section 放入 ``RAM``。
* 第 23~27 行：``.bss`` 放入 ``RAM``。
* 第 28~32 行：源文件随后丢弃注释、note 与 ``.eh_frame``。

接口关系：

* 被调用：根部 :file:`tests/asm/smoke.S` 与 :file:`tests/asm/nop.S` 的 ELF/HEX 样例。
* 调用：linker memory region 分配。
* 共享状态：``BOOT`` 和 ``RAM`` 地址窗口。

§4  mailbox pass/fail 协议
------------------------------------------------------------------------------------------------------------------------

职责：手写汇编测试用 mailbox 写入表达测试结论。通过路径写 ``0xFF``，失败路径写
``0x01``；cosim smoke 与根部 smoke/nop 都直接展示该约定。

§4.1  cosim smoke 的 word 写入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_smoke.S:L10-L17``）：

.. code-block:: cpp

   _start:
       // Write 0xFF to mailbox (0xD0580000) = PASS
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)

       // Loop forever (halt via debug or timeout)
   1:  j       1b

逐段解释：

* 第 10 行：程序从 ``_start`` 进入，没有 C runtime 初始化。
* 第 12~14 行：``t0`` 装载 mailbox 地址 ``0xD0580000``，``t1`` 装载 ``0xFF``，
  然后用 ``sw`` 写入 word。
* 第 17 行：写入后进入本地无限循环，退出条件由仿真侧 mailbox、debug 或 timeout
  逻辑决定。

接口关系：

* 被调用：``cosim_testlist.yaml`` 中的 ``cosim_smoke`` 条目。
* 调用：无函数调用，只执行 store 和跳转。
* 共享状态：mailbox 地址 ``0xD0580000``。

§4.2  根部 smoke/nop 的 byte 写入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``tests/asm/smoke.S:L6-L15``）：

.. code-block:: cpp

   .section .text
   .globl _start
   _start:
       // Load mailbox address
       lui   a0, 0xD0580      // a0 = 0xD0580000
       // Write 0xFF (PASS) to mailbox
       li    a1, 0xFF
       sb    a1, 0(a0)
       // Loop forever
   1:  j     1b

逐段解释：

* 第 6~8 行：根部 smoke 使用 ``.section .text``，入口仍为 ``_start``。
* 第 10 行：``lui a0, 0xD0580`` 生成 mailbox 基地址 ``0xD0580000``。
* 第 12~13 行：该样例用 ``sb`` 写入 ``0xFF``，不同于 cosim smoke 的 ``sw``。
* 第 15 行：程序进入无限循环。

接口关系：

* 被调用：根目录最小 smoke 样例。
* 调用：无函数调用。
* 共享状态：mailbox 地址 ``0xD0580000``。

§4.3  fail 路径的 ``0x01`` 写入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_alu.S:L67-L82``）：

.. code-block:: bash

   pass:
       // Write PASS to mailbox
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)
       j       done

   fail:
       // Write FAIL to mailbox
       li      t0, 0xD0580000
       li      t1, 0x01
       sw      t1, 0(t0)

   done:
       // Loop forever
   1:  j       1b

逐段解释：

* 第 67~72 行：``pass`` 标签写 ``0xFF`` 到 mailbox 后跳到 ``done``。
* 第 74~78 行：``fail`` 标签写 ``0x01`` 到同一 mailbox 地址。
* 第 80~82 行：两条路径最终都落入无限循环，避免程序继续执行到未定义区域。

接口关系：

* 被调用：``cosim_alu.S`` 中多个 ``bne`` 检查会跳到 ``fail``。
* 调用：无函数调用。
* 共享状态：``pass``、``fail`` 和 ``done`` 标签。

§5  cosim proof 汇编程序
------------------------------------------------------------------------------------------------------------------------

职责：``cosim_*.S`` 文件为 Spike lockstep 路径提供短小、确定性的 proof point。
它们覆盖初始化、ALU、load/store、dual issue、exception compare 和 atomic。
对应的 testlist 明确使用 ``core_eh2_cosim_test``。

§5.1  ``cosim_testlist.yaml`` 的 cosim 配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml:L5-L16``）：

.. code-block:: yaml

   - config: eh2_cosim
     rtl_test: core_eh2_cosim_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - test: cosim_smoke
     desc: "Cosim initialization, binary load, first Spike step, mailbox PASS"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_smoke.S
     iterations: 1

逐段解释：

* 第 5~10 行：``eh2_cosim`` 配置把 RTL test 固定为 ``core_eh2_cosim_test``，
  timeout 为 300 秒，GCC 选项禁用标准库和启动文件，linker script 指向
  ``tests/asm/cosim_link.ld``。
* 第 12~16 行：``cosim_smoke`` 复用 ``eh2_cosim`` 配置，源文件是
  ``tests/asm/cosim_smoke.S``，只运行 1 次。

接口关系：

* 被调用：回归脚本读取该 YAML 后生成编译和仿真命令。
* 调用：``core_eh2_cosim_test``、GCC 和 linker script。
* 共享状态：``config: eh2_cosim``。

§5.2  ALU deterministic 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_alu.S:L15-L43``）：

.. code-block:: bash

       // --- Immediate instructions ---
       li      x1, 0x12345678
       addi    x2, x1, 0x10        // x2 = 0x12345688
       addi    x3, x1, -1          // x3 = 0x12345677

       // --- Register-register arithmetic ---
       li      x4, 0xAAAAAAAA
       li      x5, 0x55555555
       add     x6, x4, x5          // x6 = 0xFFFFFFFF
       sub     x7, x4, x5          // x7 = 0x55555555

       // --- Bitwise operations ---
       and     x8, x4, x5          // x8 = 0x00000000
       or      x9, x4, x5          // x9 = 0xFFFFFFFF
       xor     x10, x4, x5         // x10 = 0xFFFFFFFF

       // --- Shift operations ---
       li      x11, 0x00000001
       sll     x12, x11, x11       // x12 = 0x00000002 (shift left by 1)
       li      x13, 0x80000000
       srl     x14, x13, x11       // x14 = 0x40000000 (logical right by 1)
       sra     x15, x13, x11       // x15 = 0xC0000000 (arithmetic right by 1)

       // --- Set less than ---
       li      x16, -1
       li      x17, 1
       slt     x18, x16, x17       // x18 = 1 (signed: -1 < 1)
       sltu    x19, x16, x17       // x19 = 0 (unsigned: 0xFFFFFFFF > 1)

逐段解释：

* 第 15~18 行：立即数路径使用 ``li`` 和两条 ``addi``，覆盖正偏移和 ``-1`` 偏移。
* 第 20~24 行：寄存器算术路径用 ``0xAAAAAAAA`` 与 ``0x55555555`` 作为操作数，
  生成可预测的 ``add`` 和 ``sub`` 结果。
* 第 26~29 行：bitwise 路径用同一对交错 bit pattern 检查 ``and``、``or`` 和
  ``xor``。
* 第 31~36 行：shift 路径覆盖左移、逻辑右移和算术右移，其中 ``sra`` 的输入最高位
  为 1。
* 第 38~42 行：``slt`` 与 ``sltu`` 使用 ``-1`` 和 ``1`` 区分有符号和无符号比较。

接口关系：

* 被调用：``cosim_testlist.yaml`` 的 ``cosim_alu`` 条目。
* 调用：无函数调用；结果通过后续 ``bne`` 检查。
* 共享状态：寄存器 ``x1`` 到 ``x20``。

§5.3  Load/store 与小端字节序
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_load_store.S:L11-L40``）：

.. code-block:: bash

       // --- Store operations ---
       li      t0, 0x80010000      // Test data region

       // Store word
       li      t1, 0xDEADBEEF
       sw      t1, 0(t0)

       // Store halfword
       li      t2, 0x1234
       sh      t2, 4(t0)

       // Store byte
       li      t3, 0xAB
       sb      t3, 6(t0)

       // --- Load operations (aligned) ---
       // Load word
       lw      t4, 0(t0)
       li      t5, 0xDEADBEEF
       bne     t4, t5, fail

       // Load halfword (signed)
       lh      t4, 4(t0)
       li      t5, 0x1234
       bne     t4, t5, fail

       // Load halfword unsigned
       lhu     t4, 4(t0)
       li      t5, 0x1234
       bne     t4, t5, fail

逐段解释：

* 第 11~16 行：测试数据区基地址是 ``0x80010000``，先写 word
  ``0xDEADBEEF``。
* 第 18~24 行：同一基地址附近写 halfword ``0x1234`` 和 byte ``0xAB``，覆盖
  ``sh`` 与 ``sb``。
* 第 26~30 行：``lw`` 读回 word，并用 ``bne`` 进入失败路径。
* 第 32~40 行：``lh`` 与 ``lhu`` 读同一 halfword；这里值为 ``0x1234``，有符号和
  无符号结果应一致。

接口关系：

* 被调用：``cosim_testlist.yaml`` 的 ``cosim_load_store`` 条目。
* 调用：无函数调用；依赖 LSU store/load 指令。
* 共享状态：外部 memory 测试地址 ``0x80010000``。

§5.4  Load/store 的符号扩展与 byte-addressable 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_load_store.S:L42-L83``）：

.. code-block:: bash

       // Load byte (signed)
       lb      t4, 6(t0)
       li      t5, 0xFFFFFFAB    // sign-extended 0xAB
       bne     t4, t5, fail

       // Load byte unsigned
       lbu     t4, 6(t0)
       li      t5, 0xAB
       bne     t4, t5, fail

       // --- Byte-addressable load from word ---
       // Load individual bytes from stored 0xDEADBEEF
       lbu     t4, 0(t0)         // byte 0 = 0xEF (little-endian)
       li      t5, 0xEF
       bne     t4, t5, fail

       lbu     t4, 1(t0)         // byte 1 = 0xBE
       li      t5, 0xBE
       bne     t4, t5, fail

       lbu     t4, 2(t0)         // byte 2 = 0xAD
       li      t5, 0xAD
       bne     t4, t5, fail

       lbu     t4, 3(t0)         // byte 3 = 0xDE
       li      t5, 0xDE
       bne     t4, t5, fail

逐段解释：

* 第 42~50 行：同一 byte ``0xAB`` 分别通过 ``lb`` 和 ``lbu`` 读取；``lb`` 期望
  ``0xFFFFFFAB``，``lbu`` 期望 ``0xAB``。
* 第 52~68 行：对已写入的 word ``0xDEADBEEF`` 做 4 次 byte 读取。期望顺序为
  ``0xEF``、``0xBE``、``0xAD``、``0xDE``，直接验证 little-endian 布局。
* 第 70~83 行：源文件随后还写入 ``0xFFFF8000`` 到 halfword，并通过 ``lh`` 检查
  符号扩展；再使用 register+offset 地址做 word store/load。

接口关系：

* 被调用：``cosim_load_store`` 主流程顺序执行。
* 调用：无函数调用。
* 共享状态：``t0`` 作为测试区基地址，``fail`` 作为错误出口。

§5.5  dual issue 程序顺序检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_dual_issue.S:L17-L46``）：

.. code-block:: cpp

       // --- Dual-issue pairs: independent ALU operations ---
       // Pair 1: addi + addi (independent, different dest regs)
       addi    x1, x0, 10
       addi    x2, x0, 20

       // Pair 2: add + sub (independent, different dest regs)
       li      x3, 100
       li      x4, 50
       add     x5, x3, x4       // x5 = 150
       sub     x6, x3, x4       // x6 = 50

       // Pair 3: and + or (independent)
       li      x7, 0xFF00FF00
       li      x8, 0x00FF00FF
       and     x9, x7, x8       // x9 = 0x00000000
       or      x10, x7, x8      // x10 = 0xFFFFFFFF

       // Pair 4: store + ALU (store doesn't write register)
       li      x11, 0x80010000
       li      x12, 0xCAFEBABE
       sw      x12, 0(x11)      // store
       addi    x13, x0, 42      // ALU (no dependency on store)

       // Pair 5: load + ALU (ALU doesn't depend on load result)
       lw      x14, 0(x11)      // load 0xCAFEBABE
       addi    x15, x0, 99      // ALU (independent of load)

       // Pair 6: branch + ALU (branch doesn't write register)
       // Note: branch target must be aligned for dual-issue
       beq     x0, x0, 1f

逐段解释：

* 第 17~20 行：第一组是两个互不依赖的 ``addi``，目的寄存器不同。
* 第 22~26 行：第二组先准备两个源寄存器，再连续执行 ``add`` 和 ``sub``。
* 第 28~32 行：第三组用不同 bit pattern 检查 ``and`` 与 ``or``。
* 第 34~42 行：第四、第五组把 store/load 与独立 ALU 指令相邻放置，用来覆盖
  store/load 与 ALU 相邻 retire 的程序顺序。
* 第 44~48 行：第六组放置 branch 和 branch target 后的 ALU 指令，源注释明确要求
  branch target 对齐。

接口关系：

* 被调用：``cosim_testlist.yaml`` 的 ``cosim_dual_issue`` 条目。
* 调用：无函数调用；后续通过 ``bne`` 检查结果。
* 共享状态：``x1`` 到 ``x20`` 和 memory 地址 ``0x80010000``。

§5.6  exception compare 的 trap handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_exception_compare.S:L58-L84``）：

.. code-block:: bash

   // ── Trap handler ──
   .align 4
   trap_handler:
       // Read mcause to identify exception type
       csrr    t0, mcause

       // Dispatch: expected causes are 2 and 11
       li      t1, 2     // illegal instruction
       beq     t0, t1, trap_advance
       li      t1, 11    // ECALL from M-mode
       beq     t0, t1, trap_advance

       // Unexpected exception → FAIL
       j       fail

   trap_advance:
       // Signal to main code that the handler executed
       li      x31, 0xDEAD

       // Advance mepc past the faulting instruction (all are 4-byte)
       csrr    t0, mepc
       addi    t0, t0, 4
       csrw    mepc, t0

       mret

   .option pop

逐段解释：

* 第 58~62 行：trap handler 4 字节对齐，并从 ``mcause`` 读取异常原因。
* 第 64~68 行：handler 只接受 ``mcause=2``（illegal instruction）和
  ``mcause=11``（ECALL from M-mode），两者都跳到 ``trap_advance``。
* 第 70~71 行：其它异常原因直接进入 ``fail``。
* 第 73~82 行：期望异常会把 ``x31`` 置为 ``0xDEAD``，然后把 ``mepc`` 加 4，
  通过 ``mret`` 返回主流程。

接口关系：

* 被调用：同文件主流程设置 ``mtvec`` 后执行 ``ecall`` 和两条非法编码。
* 调用：CSR 读写 ``mcause``、``mepc`` 和 ``mret``。
* 共享状态：``x31`` 是 handler 执行标志。

§5.7  atomic LR/SC 与 AMO
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_atomic_basic.S:L17-L35``）：

.. code-block:: bash

   _start:
       // ── Test 1: LR/SC lock acquire-release ──
       // EH2 atomics operate against DCCM. Avoid regular stores for setup so the
       // cosim scoreboard does not require an external AXI write notification.
       li      t0, 0xF0040000
   1:  lr.w    t1, (t0)        // Load reservation
       bne     t1, zero, 1b    // Not free, retry
       li      t2, 1
       sc.w    t3, t2, (t0)    // Try to acquire (rd=0 means success)
       bne     t3, zero, 1b    // Failed, retry

       // Verify lock was acquired (lock_word should now be 1)
       lw      t4, 0(t0)
       li      t5, 1
       bne     t4, t5, fail

       // Release lock
       amoswap.w x0, zero, (t0)

逐段解释：

* 第 17~21 行：测试从 ``_start`` 进入，原注释说明 atomic 访问 DCCM，并避免用普通
  store 做 setup；目标地址是 ``0xF0040000``。
* 第 22~26 行：``lr.w`` 读取 reservation 值，非 0 则重试；``sc.w`` 尝试写入 1，
  返回值非 0 也重试。
* 第 29~31 行：获取 lock 后用 ``lw`` 读回并确认值为 1。
* 第 34 行：释放使用 ``amoswap.w x0, zero, (t0)``，把 lock word 置回 0。

接口关系：

* 被调用：``cosim_testlist.yaml`` 的 ``cosim_atomic_basic`` 条目。
* 调用：A-extension 指令 ``lr.w``、``sc.w``、``amoswap.w``。
* 共享状态：DCCM 地址 ``0xF0040000``。

§5.8  AMO 算术/逻辑序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/cosim_atomic_basic.S:L51-L82``）：

.. code-block:: bash

       // ── Test 3: AMOADD.W ──
       li      t1, 100
       amoswap.w x0, t1, (t0)   // mem = 100
       li      t2, 25
       amoadd.w t3, t2, (t0)    // t3=100 (old), mem=125 (new)
       li      t4, 100
       bne     t3, t4, fail
       lw      t5, 0(t0)
       li      t6, 125
       bne     t5, t6, fail

       // ── Test 4: AMOXOR.W ──
       li      t1, 0x0F0F0F0F
       amoswap.w x0, t1, (t0)   // mem = 0x0F0F0F0F
       li      t2, 0xF0F0F0F0
       amoxor.w t3, t2, (t0)    // t3=0x0F0F0F0F, mem=0xFFFFFFFF
       li      t4, 0x0F0F0F0F
       bne     t3, t4, fail
       lw      t5, 0(t0)
       li      t6, 0xFFFFFFFF
       bne     t5, t6, fail

       // ── Test 5: AMOAND.W ──
       li      t1, 0xFF00FF00
       amoswap.w x0, t1, (t0)   // mem = 0xFF00FF00
       li      t2, 0x0F0F0F0F
       amoand.w t3, t2, (t0)    // t3=0xFF00FF00, mem=0x0F000F00
       li      t4, 0xFF00FF00
       bne     t3, t4, fail

逐段解释：

* 第 51~60 行：``AMOADD.W`` 前用 ``amoswap.w`` 初始化 memory 为 100；执行
  ``amoadd.w`` 后检查返回旧值 100，并检查 memory 新值 125。
* 第 62~71 行：``AMOXOR.W`` 使用 ``0x0F0F0F0F`` 与 ``0xF0F0F0F0``，期望 memory
  变为 ``0xFFFFFFFF``。
* 第 73~82 行：``AMOAND.W`` 使用 ``0xFF00FF00`` 与 ``0x0F0F0F0F``，先检查
  返回旧值；源文件第 80~82 行随后还读回 memory 并检查 ``0x0F000F00``。

接口关系：

* 被调用：``cosim_atomic_basic.S`` 的 ``_start`` 顺序执行。
* 调用：``amoswap.w``、``amoadd.w``、``amoxor.w``、``amoand.w``。
* 共享状态：``t0`` 指向同一个 DCCM atomic 目标地址。

§6  directed trap、IRQ 与 debug 程序
------------------------------------------------------------------------------------------------------------------------

职责：directed trap/debug 汇编程序用 ``mtvec``、``mcause``、``mepc`` 和
``mret`` 构造确定性异常窗口。部分条目 cosim enabled；依赖 UVM sideband 的 debug
和 PIC coverage pump 在 YAML 中标为 cosim disabled。

§6.1  basic IRQ/trap 路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_irq_basic.S:L13-L28``）：

.. code-block:: bash

   _start:
       // Set up trap handler (direct mode)
       la      t0, trap_handler
       csrw    mtvec, t0

       // Clear flag register
       li      x31, 0

       // Trigger synchronous trap via ECALL
       ecall

       // After mret, we should land here
       // Check that trap handler set our flag
       li      t0, 0xCAFE
       bne     x31, t0, fail

逐段解释：

* 第 13~16 行：主流程把 ``trap_handler`` 写入 ``mtvec``，使用 direct mode。
* 第 18~19 行：``x31`` 清零，作为 handler 是否执行的标志。
* 第 21~22 行：``ecall`` 主动触发同步 trap。
* 第 24~28 行：``mret`` 返回后检查 ``x31`` 是否被置为 ``0xCAFE``，否则进入
  ``fail``。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_irq_basic`` 条目。
* 调用：CSR 写 ``mtvec``、``ecall``、handler 中的 ``mret``。
* 共享状态：``x31`` 是 trap flag。

§6.2  nested ECALL 的两级返回
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_nested_irq.S:L72-L111``）：

.. code-block:: bash

   first_level:
       // Save mepc on stack (we need it after the nested ecall)
       csrr    t0, mepc
       addi    sp, sp, -8
       sw      t0, 0(sp)
       // Also save mstatus so nested mret works correctly
       csrr    t0, mstatus
       sw      t0, 4(sp)

       // Increment depth to 1
       li      t0, 1
       csrw    mscratch, t0

       // Advance mepc past the first ecall (so mret after second-level goes right)
       csrr    t0, mepc
       addi    t0, t0, 4
       csrw    mepc, t0

       // Trigger second-level ECALL from within the handler
       ecall

       // After second-level mret, we return here
       // Set first-level flag
       li      x31, 0xCAFE

       // Restore original mepc and mstatus from stack
       lw      t0, 0(sp)
       // mepc was the original ecall instruction; advance past it
       addi    t0, t0, 4

逐段解释：

* 第 72~79 行：一级 handler 保存 ``mepc`` 和 ``mstatus`` 到栈上，为嵌套
  ``ecall`` 后恢复上下文做准备。
* 第 81~88 行：``mscratch`` 被写成 1 作为 nesting depth，并提前把 ``mepc`` 加 4。
* 第 90~91 行：handler 内再次执行 ``ecall``，进入二级 trap。
* 第 93~100 行：二级 ``mret`` 回到一级 handler 后，一级 handler 设置 ``x31``
  并恢复原始 ``mepc`` 的下一条指令地址。
* 第 102~111 行：源文件随后恢复 ``mstatus``、回收栈空间、清 ``mscratch`` 并
  ``mret``。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_nested_irq`` 条目。
* 调用：``ecall``、CSR 读写 ``mepc``/``mstatus``/``mscratch``、``mret``。
* 共享状态：``sp``、``mscratch``、``x30``、``x31``。

§6.3  debug basic 的 EBREAK 长度处理
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_debug_basic.S:L44-L63``）：

.. code-block:: bash

   // ---- Trap handler ----
   .align 4
   trap_handler:
       // Read mcause - should be 3 (breakpoint)
       csrr    t0, mcause
       li      t1, 3
       bne     t0, t1, trap_unexpected

       // Signal to main code that handler ran
       li      x31, 0xBEEF

       // Determine instruction length at mepc to skip correctly.
       // RISC-V: if bits [1:0] of the instruction != 0b11, it's a 16-bit
       // compressed instruction; otherwise it's 32-bit.
       csrr    t0, mepc
       lhu     t1, 0(t0)          // load halfword at mepc
       andi    t2, t1, 0x3        // check bits [1:0]
       li      t3, 0x3
       bne     t2, t3, skip_2     // compressed: skip 2 bytes

逐段解释：

* 第 44~50 行：handler 只接受 ``mcause=3``，也就是 breakpoint exception。
* 第 52~53 行：handler 把 ``x31`` 写为 ``0xBEEF``，供主流程确认 EBREAK trap 已执行。
* 第 55~63 行：handler 从 ``mepc`` 读取 faulting 指令的低半字，检查 bit[1:0]；
  若不是 ``0b11``，按 compressed 指令跳到 ``skip_2``。
* 第 64~74 行：源文件随后让 32 位指令跳过 4 字节，16 位 compressed 指令跳过 2 字节，最后把
  新地址写回 ``mepc``。
* 第 77 行：源文件随后通过 ``mret`` 返回主流程。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_debug_basic`` 条目。
* 调用：``ebreak`` 触发路径、CSR 读写 ``mcause``/``mepc``。
* 共享状态：``x31`` 是 debug trap flag。

§6.4  debug halt/resume coverage stimulus
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_dbg_dret_walk.S:L12-L34``）：

.. code-block:: bash

   _start:
       la      t0, trap_handler
       csrw    mtvec, t0
       li      s0, 0

       ebreak

       li      t0, 0xDB67
       bne     s0, t0, fail

       li      t1, 64
   debug_spin:
       addi    t2, t2, 1
       xor     t3, t2, t1
       addi    t1, t1, -1
       bnez    t1, debug_spin

   pass:
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)
   done:
       j       done

逐段解释：

* 第 12~15 行：程序设置 ``mtvec`` 并清 ``s0``。
* 第 17~20 行：``ebreak`` 进入 handler，返回后要求 ``s0`` 等于 ``0xDB67``。
* 第 22~27 行：``debug_spin`` 运行 64 次递减循环，持续产生确定性执行窗口。
* 第 29~34 行：通过后写 ``0xFF`` 到 mailbox 并停在 ``done``。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_dbg_dret_walk`` 条目。
* 调用：``ebreak`` 与本文件 ``trap_handler``。
* 共享状态：``s0`` 是 breakpoint handler flag；YAML 还为该条目设置 debug plusarg。

§7  PMP directed 程序
------------------------------------------------------------------------------------------------------------------------

职责：PMP directed 程序通过 ``pmpaddr*``、``pmpcfg0``、``fence.i`` 和 trap handler
构造权限访问场景。与 PMP/ePMP cosim 边界相关的设计决策见 :ref:`adr-0009`。

§7.1  PMP smoke 的 NAPOT no-RWX 区域
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_pmp_smoke.S:L19-L39``）：

.. code-block:: bash

       // ---- Configure PMP ----
       // pmpaddr0: protect region 0x90000000-0x90001000 (4KB)
       // NAPOT encoding: addr >> 2, low bits encode size
       // For 4KB NAPOT: (base >> 2) | ((size/2 - 1) >> 2)
       // base=0x90000000, size=0x1000
       // pmpaddr = (0x90000000 >> 2) | (0x7FF) = 0x240007FF
       li      t0, 0x240007FF
       csrw    pmpaddr0, t0

       // pmpcfg0: byte 0 = L(1) | NAPOT(11) | no-RWX(000) = 0x98
       // Lock + NAPOT + no permissions = trap on any access
       li      t0, 0x98
       csrw    pmpcfg0, t0

       // Fence to ensure PMP takes effect
       fence.i

       // ---- Attempt access to protected region ----
       // This should trap with mcause=5 (load access fault) or mcause=1 (instr access fault)
       li      t0, 0x90000000
       lw      t1, 0(t0)           // Should trap!

逐段解释：

* 第 19~26 行：程序配置 ``pmpaddr0``，注释给出 4 KB NAPOT 区域
  ``0x90000000-0x90001000`` 的编码 ``0x240007FF``。
* 第 28~31 行：``pmpcfg0`` 写 ``0x98``，源注释解释为 locked、NAPOT、no-RWX。
* 第 33~34 行：``fence.i`` 用于确保 PMP 配置生效。
* 第 36~39 行：程序读取 ``0x90000000``，注释说明期望 load access fault 或
  instruction access fault。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_pmp_smoke`` 条目。
* 调用：CSR 写 ``pmpaddr0``/``pmpcfg0``、``fence.i`` 和 load 指令。
* 共享状态：``x31`` 在 handler 中被置为 ``0xDEAD``。

§7.2  PMP multi-region 的 setup/test phase
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S:L24-L49``）：

.. code-block:: bash

   _start:
       // Set up trap handler
       la      t0, trap_handler
       csrw    mtvec, t0

       // Clear all flag / tracking registers
       li      x28, 0              // setup-phase trap counter
       li      x29, 0              // phase (0=setup, 1=test)
       li      x30, 0              // per-test trap flag
       li      x31, 0              // general flag

       // ================================================================
       // PMP SETUP PHASE (x29==0: handler skips any faulting insn)
       // ================================================================

       // --- pmpaddr0: 0x90000000-0x90001000 (4KB NAPOT) ---
       li      t0, 0x240007FF
       csrw    pmpaddr0, t0

       // --- pmpaddr1: 0x91000000-0x91001000 (4KB NAPOT) ---
       li      t0, 0x244007FF
       csrw    pmpaddr1, t0

       // --- pmpaddr2: 0x92000000-0x92001000 (4KB NAPOT) ---
       li      t0, 0x248007FF
       csrw    pmpaddr2, t0

逐段解释：

* 第 24~27 行：设置 trap handler。
* 第 29~33 行：``x28`` 记录 setup trap 计数，``x29`` 记录 phase，``x30`` 是单项
  测试 trap flag，``x31`` 是 general flag。
* 第 35~38 行：注释定义 setup phase：``x29==0`` 时 handler 跳过 faulting 指令。
* 第 39~53 行：依次写 ``pmpaddr0`` 到 ``pmpaddr3``，覆盖 3 个 4 KB NAPOT region
  和一个大范围 code region；代码片段展示到 ``pmpaddr2``，后续 ``pmpaddr3`` 在源文件
  第 51~53 行。
* 第 55~58 行：``pmpcfg0`` 后续写入 ``0x9F999B98``，该 32 位值由 4 个 PMP config
  byte 组合。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_pmp_regions`` 条目。
* 调用：CSR 写 ``pmpaddr0`` 到 ``pmpaddr3``、``pmpcfg0``。
* 共享状态：``x28``、``x29``、``x30``、``x31``。

§7.3  PMP multi-region 的 probe 与 access tests
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S:L61-L112``）：

.. code-block:: cpp

       // ================================================================
       // PROBE: Did pmpaddr0 actually get written?
       // If pmpaddr CSR writes were trapped/skipped, the value won't stick.
       // ================================================================
       csrr    t0, pmpaddr0
       li      t1, 0x240007FF
       beq     t0, t1, pmp_active

       // PMP address CSR writes did not take effect — PMP not usable on
       // this EH2 configuration.  This is acceptable; report PASS.
       j       pass

   pmp_active:
       // ================================================================
       // TEST PHASE: PMP is active, validate access control.
       // ================================================================
       li      x29, 1

       // ---- Test 1: Load from region 0 — should trap (Locked, no RWX) ----
       li      t0, 0x90000800
       li      x30, 0
       lw      t1, 0(t0)
       li      t0, 0xDEAD
       bne     x30, t0, fail

       // ---- Test 2: Load from region 1 — should succeed (RW) ----
       li      t0, 0x91000800
       li      x30, 0
       lw      t1, 0(t0)

逐段解释：

* 第 61~67 行：程序读回 ``pmpaddr0``，如果值等于 ``0x240007FF`` 才进入
  ``pmp_active``。
* 第 69~71 行：如果 PMP address CSR 写入未生效，程序直接 ``j pass``；这是源代码
  明确写出的容错路径。
* 第 73~78 行：进入 test phase 后把 ``x29`` 设置为 1，改变 handler 行为。
* 第 79~84 行：region 0 访问应产生 trap，并要求 ``x30`` 被 handler 置为
  ``0xDEAD``。
* 第 86~112 行：源文件继续检查 region 1 的 load/store 成功、region 2 的 load 成功
  和 store trap。

接口关系：

* 被调用：``pmp_active`` 由 probe 分支进入。
* 调用：CSR 读 ``pmpaddr0``、load/store 指令。
* 共享状态：``x29`` 决定 handler phase，``x30`` 保存 per-test trap flag。

§7.4  PMP TOR basic
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_pmp_tor_basic.S:L9-L29``）：

.. code-block:: bash

   _start:
       la      t0, trap_handler
       csrw    mtvec, t0
       li      x31, 0

       // PMP CSR #1: pmpaddr0 = TOR entry (base=0x90000000 >> 2)
       li      t0, 0x24000000
       csrw    pmpaddr0, t0

       // PMP CSR #2: pmpaddr1 = TOR end (0x90001000 >> 2)
       li      t0, 0x24000400
       csrw    pmpaddr1, t0

       // PMP CSR #3: pmpcfg0 byte 0 = TOR(01) + R(0) = 0x08 (no read)
       li      t0, 0x08
       csrw    pmpcfg0, t0
       fence.i

       // Try read from protected region — should trap
       li      t0, 0x90000000
       lw      t1, 0(t0)

逐段解释：

* 第 9~12 行：程序设置 ``mtvec`` 并清 ``x31``。
* 第 14~20 行：``pmpaddr0`` 写 base，``pmpaddr1`` 写 end；注释给出两者都来自
  地址右移 2 位。
* 第 22~25 行：``pmpcfg0`` 写 ``0x08``，源注释标明是 TOR 且 no read，然后执行
  ``fence.i``。
* 第 27~29 行：读取 ``0x90000000``，作为受保护区域访问。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_pmp_tor_basic`` 条目。
* 调用：CSR 写 ``pmpaddr0``/``pmpaddr1``/``pmpcfg0``，load 指令。
* 共享状态：``x31`` 在 handler 中被置为 ``0xDEAD``。

§8  AXI4、LSU、DMA 与 NB-load directed 程序
------------------------------------------------------------------------------------------------------------------------

职责：这组 directed 程序将汇编内的 memory 访问与 UVM sideband 行为组合起来，覆盖
AXI4 error 注入、持续 burst、store-buffer 压力和 NB-load 结果使用。AXI4 passive
监测背景见 :ref:`adr-0002`，writeback tag 约束见 :ref:`adr-0018`。

§8.1  AXI4 error injection 的 plusarg 合同
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_axi4_error_inject.S:L1-L18``）：

.. code-block:: bash

   // SPDX-License-Identifier: Apache-2.0
   // EH2 Directed AXI4 Error Injection Test
   //
   // Verifies that AXI4 bus error responses (SLVERR/DECERR) are
   // correctly propagated to the core as load access faults (mcause=5).
   //
   // This test must be run with:
   //   +enable_axi4_error_inject=1 +axi4_error_pct=100
   // to guarantee error injection on every LSU AXI4 transaction.
   //
   // Flow:
   //   1. Set up mtvec trap handler
   //   2. Attempt a load from external memory (AXI4 bus)
   //   3. AXI4 driver injects error response -> core takes access fault
   //   4. Trap handler checks mcause==5 (load access fault)
   //   5. If correct, writes PASS to mailbox
   //
   // cosim: disabled (error injection alters bus behavior)

逐段解释：

* 第 4~5 行：测试目标是把 AXI4 ``SLVERR``/``DECERR`` 传播为 core 的
  load access fault，``mcause=5``。
* 第 7~9 行：源文件明确要求仿真 plusarg
  ``+enable_axi4_error_inject=1 +axi4_error_pct=100``，保证 LSU AXI4 transaction
  都被注入 error。
* 第 11~16 行：注释列出执行流：设置 handler、访问外部 memory、AXI4 driver 注入
  error、handler 检查 ``mcause==5``、最后写 mailbox PASS。
* 第 18 行：该测试 cosim disabled，因为 error injection 改变 bus 行为。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_axi4_error_inject`` 条目。
* 调用：UVM AXI4 error injection plusarg 和 trap handler。
* 共享状态：``x31`` 是 handler 成功标志。

§8.2  AXI4 error handler 的 ``mcause`` 分派
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_axi4_error_inject.S:L62-L99``）：

.. code-block:: bash

   // ---- Trap handler ----
   .align 4
   trap_handler:
       // Read mcause
       csrr    t0, mcause

       // Check for load access fault (mcause=5)
       li      t1, 5
       beq     t0, t1, trap_load_access_fault

       // Check for store/AMO access fault (mcause=7)
       // This can happen if error injection hits a store
       li      t1, 7
       beq     t0, t1, trap_store_access_fault

       // Unexpected trap cause
       j       trap_unexpected

   trap_load_access_fault:
       // Expected path: load access fault from AXI4 error injection
       // Set flag to signal success
       li      x31, 0xBEEF

       // Advance mepc past the faulting load (4 bytes)
       csrr    t0, mepc
       addi    t0, t0, 4
       csrw    mepc, t0

       // Return from trap
       mret

逐段解释：

* 第 62~66 行：handler 对齐后读取 ``mcause``。
* 第 68~75 行：``mcause=5`` 跳到 load access fault 路径，``mcause=7`` 跳到
  store/AMO access fault 路径。
* 第 77~78 行：其它异常原因进入 unexpected 路径。
* 第 80~91 行：load access fault 是期望路径，handler 把 ``x31`` 写为
  ``0xBEEF``，把 ``mepc`` 加 4 后 ``mret``。
* 第 93~99 行：源文件后续对 store/AMO access fault 也选择跳过 faulting 指令并返回。

接口关系：

* 被调用：主流程访问 ``0x90000000`` 后进入该 handler。
* 调用：CSR 读写 ``mcause``、``mepc``。
* 共享状态：``x31`` 和 mailbox fail path。

§8.3  DMA-like burst 的写读回环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_dma_burst.S:L12-L36``）：

.. code-block:: bash

   _start:
       la      t0, burst_buf
       li      t1, 0x1000
       li      t2, 32

   store_loop:
       sw      t1, 0(t0)
       addi    t1, t1, 3
       addi    t0, t0, 4
       addi    t2, t2, -1
       bnez    t2, store_loop

       fence

       la      t0, burst_buf
       li      t1, 0x1000
       li      t2, 32

   load_loop:
       lw      t3, 0(t0)
       bne     t3, t1, fail
       addi    t1, t1, 3
       addi    t0, t0, 4
       addi    t2, t2, -1
       bnez    t2, load_loop

逐段解释：

* 第 12~15 行：初始化 buffer 指针、起始数据 ``0x1000`` 和循环计数 32。
* 第 17~22 行：store loop 每次写一个 word，数据加 3，地址加 4，循环 32 次。
* 第 24 行：``fence`` 分隔写 burst 和读回验证。
* 第 26~36 行：load loop 从同一 buffer 读回，逐项与递增期望值比较。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_dma_burst`` 条目。
* 调用：load/store 和 ``fence``。
* 共享状态：``burst_buf`` 数据区。

§8.4  store-buffer pressure
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_lsu_stbuf_full.S:L8-L35``）：

.. code-block:: bash

   _start:
       li      t0, 0xF0040000
       li      t1, 0x55AA0000
       li      t2, 64

   store_pressure_loop:
       sw      t1, 0(t0)
       sw      t1, 4(t0)
       sw      t1, 8(t0)
       sw      t1, 12(t0)
       addi    t0, t0, 16
       addi    t1, t1, 1
       addi    t2, t2, -4
       bnez    t2, store_pressure_loop

       fence

       li      t0, 0xF0040000
       li      t1, 0x55AA0000
       li      t2, 16

   verify_loop:
       lw      t3, 0(t0)
       bne     t3, t1, fail
       addi    t0, t0, 16
       addi    t1, t1, 1
       addi    t2, t2, -1
       bnez    t2, verify_loop

逐段解释：

* 第 8~11 行：测试基地址为 ``0xF0040000``，数据从 ``0x55AA0000`` 开始，计数为 64。
* 第 13~21 行：每轮连续 4 个 ``sw``，地址推进 16 字节，数据加 1，计数减 4。
* 第 23 行：``fence`` 强制 store 序列完成后再验证。
* 第 25~35 行：验证循环按 16 字节步长只读每轮第一个 word，并检查数据递增。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_lsu_stbuf_full`` 条目。
* 调用：连续 store、``fence``、load 验证。
* 共享状态：DCCM 地址窗口 ``0xF0040000``。

§8.5  NB-load chain
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S:L11-L45``）：

.. code-block:: bash

   _start:
       // Set up data in memory
       li      t0, 0x80001000
       li      t1, 0xAABBCCDD
       sw      t1, 0(t0)
       li      t1, 0x11223344
       sw      t1, 4(t0)
       li      t1, 0x55667788
       sw      t1, 8(t0)

       // Fence to ensure stores complete
       fence

       // Three consecutive loads (non-blocking pipeline)
       lw      x1, 0(t0)           // x1 = 0xAABBCCDD
       lw      x2, 4(t0)           // x2 = 0x11223344
       lw      x3, 8(t0)           // x3 = 0x55667788

       // Use all three results in computation
       add     x4, x1, x2          // x4 = 0xBBDE0021
       add     x5, x4, x3          // x5 = 0x114477A9

       // Verify chain result
       li      x20, 0xAABBCCDD
       bne     x1, x20, fail
       li      x20, 0x11223344
       bne     x2, x20, fail
       li      x20, 0x55667788
       bne     x3, x20, fail

逐段解释：

* 第 11~19 行：程序在 ``0x80001000`` 连续写 3 个 word。
* 第 21~22 行：``fence`` 确保前面的 stores 完成。
* 第 24~27 行：连续执行 3 条 ``lw``，注释称为 non-blocking pipeline。
* 第 29~31 行：立即使用 3 个 load 结果做两级 ``add``。
* 第 33~45 行：先逐个检查 ``x1``、``x2``、``x3``，源文件随后还重新计算并检查
  ``x4`` 与 ``x5``。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_nb_load_chain`` 条目。
* 调用：store、``fence``、连续 load、dependent ALU。
* 共享状态：``x1`` 到 ``x5`` 保存 NB-load 结果链。

§9  toggle pump 程序
------------------------------------------------------------------------------------------------------------------------

职责：toggle pump 程序并不主要验证一个单一 ISA corner case，而是用确定性的寄存器、
CSR、DCCM、AXI4 data 和 multiply/divide 操作提高结构覆盖活动。YAML 中这些条目
均标为 ``cosim: disabled``。

§9.1  CSR walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_toggle_csr_walk.S:L8-L25``）：

.. code-block:: bash

   .equ CSR_MSCAUSE,      0x7FF
   .equ CSR_MRAC,         0x7C0
   .equ CSR_MFDC,         0x7F9
   .equ CSR_MCYCLE,       0xB00
   .equ CSR_MINSTRET,     0xB02
   .equ CSR_MHPMCOUNTER3, 0xB03

   _start:
       la      t4, csr_shadow

       li      t0, 0xAAAAAAAA
       csrrw   zero, mstatus, t0
       csrr    t1, mstatus
       sw      t1, 0(t4)
       li      t0, 0x55555555
       csrrw   zero, mstatus, t0
       csrr    t1, mstatus
       sw      t1, 4(t4)

逐段解释：

* 第 8~13 行：文件定义 EH2 相关 CSR 常量，包括 ``CSR_MSCAUSE``、``CSR_MRAC``、
  ``CSR_MFDC`` 和 counter CSR。
* 第 15~16 行：``csr_shadow`` 数据区地址放入 ``t4``，用于保存读回值。
* 第 18~25 行：对 ``mstatus`` 连续写 ``0xAAAAAAAA`` 和 ``0x55555555``，每次写后
  读回并保存到 ``csr_shadow``。
* 第 27~142 行：源文件按同一写读保存模式覆盖 ``mie``、``mip``、``mtvec``、
  ``mscratch``、``mepc``、``mcause``、``mtval`` 和自定义 CSR。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_toggle_csr_walk`` 条目。
* 调用：CSR 读写 ``csrrw`` 和 ``csrr``。
* 共享状态：``csr_shadow`` 数据区。

§9.2  DCCM byte/halfword/word walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S:L8-L26``）：

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

       li      t1, 0x000000FE
       sb      t1, 4(t0)
       lbu     t2, 4(t0)
       li      t3, 0xFE
       bne     t2, t3, fail
       lb      t2, 4(t0)
       li      t3, 0xFFFFFFFE
       bne     t2, t3, fail

逐段解释：

* 第 8~9 行：DCCM walk 使用基地址 ``0xF0040000``。
* 第 11~17 行：写 byte ``0x01`` 后分别用 ``lbu`` 和 ``lb`` 读回；因为符号位为 0，
  两者都应等于 ``0x01``。
* 第 19~26 行：写 byte ``0xFE`` 后，``lbu`` 期望 ``0xFE``，``lb`` 期望符号扩展
  ``0xFFFFFFFE``。
* 第 28~43 行：源文件随后进入 halfword 路径，先检查 ``0x1234``，再检查 ``0x8001`` 的有符号扩展
  ``0xFFFF8001``。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_toggle_dccm_walk`` 条目。
* 调用：byte/halfword store/load 指令。
* 共享状态：DCCM 地址 ``0xF0040000``。

§9.3  multiply/divide walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_toggle_mul_div_walk.S:L11-L28``）：

.. code-block:: bash

   _start:
       li      s0, 0

       li      t0, 7
       li      t1, 9
       mul     t2, t0, t1
       li      t3, 63
       bne     t2, t3, fail

       li      t0, 100
       li      t1, 7
       div     t2, t0, t1
       li      t3, 14
       bne     t2, t3, fail
       rem     t2, t0, t1
       li      t3, 2
       bne     t2, t3, fail

逐段解释：

* 第 11~12 行：``s0`` 初始化为 0，后续较长的 M-extension 序列会不断 XOR 进
  ``s0``。
* 第 14~18 行：先用 ``7 * 9`` 检查 ``mul`` 结果 63。
* 第 20~27 行：再用 ``100 / 7`` 检查 ``div`` 商 14 和 ``rem`` 余数 2。
* 第 29~105 行：源文件随后覆盖 ``mulh``、``mulhu``、``mulhsu``、``divu`` 和
  ``remu``，并用多组高活动操作数更新 ``s0``。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_toggle_mul_div_walk`` 条目。
* 调用：RISC-V M-extension 指令。
* 共享状态：``s0`` 保存 XOR 累积值，并在文件末尾写入 ``0xf0040000`` 后读回检查。

§9.4  AXI4 data walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/tests/asm/directed_toggle_axi4_data_walk.S:L8-L27``）：

.. code-block:: bash

   _start:
       li      t0, 0x80010000

       li      t1, 0xAAAAAAAA
       sw      t1, 0(t0)
       li      t1, 0x55555555
       sw      t1, 4(t0)
       li      t1, 0xFF00FF00
       sw      t1, 8(t0)
       li      t1, 0x00FF00FF
       sw      t1, 12(t0)
       li      t1, 0xDEADBEEF
       sw      t1, 16(t0)
       li      t1, 0xCAFEBABE
       sw      t1, 20(t0)
       li      t1, 0x00000000
       sw      t1, 24(t0)
       li      t1, 0xFFFFFFFF
       sw      t1, 28(t0)

逐段解释：

* 第 8~9 行：AXI4 data walk 使用外部 memory 地址 ``0x80010000``。
* 第 11~27 行：程序连续写入 8 个互补或高翻转 word pattern，包括
  ``0xAAAAAAAA``、``0x55555555``、``0xFF00FF00``、``0x00FF00FF``、
  ``0xDEADBEEF``、``0xCAFEBABE``、``0x00000000`` 和 ``0xFFFFFFFF``。
* 第 28~43 行：源文件随后在相同地址写入互补顺序，用来继续翻转 data bus。
* 第 45~69 行：``fence`` 后读回第 0~28 字节位置并逐项比较。

接口关系：

* 被调用：``directed_testlist.yaml`` 的 ``directed_toggle_axi4_data_walk`` 条目。
* 调用：AXI4 外部 memory store/load。
* 共享状态：外部 memory 地址 ``0x80010000``。

§10  testlist 注册关系
------------------------------------------------------------------------------------------------------------------------

职责：YAML testlist 决定哪些汇编程序进入哪些 RTL test、是否启用 cosim、以及是否附带
仿真 plusarg。文档中任何测试归类都必须能回溯到这些 YAML 条目。

§10.1  directed 基础配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L4-L23``）：

.. code-block:: yaml

   - config: eh2_directed
     rtl_test: core_eh2_base_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - config: eh2_directed_pic
     rtl_test: core_eh2_pic_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - config: eh2_directed_fetch_toggle
     rtl_test: core_eh2_fetch_toggle_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

逐段解释：

* 第 4~10 行：``eh2_directed`` 使用 ``core_eh2_base_test``，GCC 选项和
  ``cosim_link.ld`` 与 cosim testlist 保持同一类 bare-metal 设置。
* 第 11~16 行：``eh2_directed_pic`` 切换 RTL test 为 ``core_eh2_pic_test``。
* 第 18~23 行：``eh2_directed_fetch_toggle`` 切换 RTL test 为
  ``core_eh2_fetch_toggle_test``。

接口关系：

* 被调用：具体 ``- test`` 条目通过 ``config`` 字段引用这些配置。
* 调用：RTL test class 名称和 linker script。
* 共享状态：``timeout_s``、``gcc_opts``、``ld_script``、``includes``。

§10.2  directed smoke/ALU/load-store 注册
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L25-L41``）：

.. code-block:: yaml

   - test: directed_smoke
     desc: "Mailbox smoke test running through the directed-test pipeline"
     config: eh2_directed
     test_srcs: tests/asm/cosim_smoke.S
     iterations: 1

   - test: directed_alu
     desc: "Deterministic ALU directed test"
     config: eh2_directed
     test_srcs: tests/asm/cosim_alu.S
     iterations: 1

   - test: directed_load_store
     desc: "Deterministic load/store directed test"
     config: eh2_directed
     test_srcs: tests/asm/cosim_load_store.S
     iterations: 1

逐段解释：

* 第 25~29 行：``directed_smoke`` 在 directed pipeline 中复用 ``cosim_smoke.S``。
* 第 31~35 行：``directed_alu`` 复用 ``cosim_alu.S``。
* 第 37~41 行：``directed_load_store`` 复用 ``cosim_load_store.S``。

接口关系：

* 被调用：directed 回归配置读取这些条目。
* 调用：``tests/asm/cosim_smoke.S``、``cosim_alu.S``、``cosim_load_store.S``。
* 共享状态：``config: eh2_directed``。

§10.3  PMP directed 注册窗口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L101-L122``）：

.. code-block:: yaml

   - test: directed_pmp_regions
     desc: "Multi-region PMP configuration and access fault"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_regions.S
     cosim: enabled
     iterations: 1

   # ─── New PMP directed tests (PROMPT-I ───

   - test: directed_pmp_tor_basic
     desc: "PMP TOR mode basic access + out-of-bounds"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_tor_basic.S
     cosim: enabled
     iterations: 1

   - test: directed_pmp_napot_basic
     desc: "PMP NAPOT mode at 4B/16B/256B/4KB sizes"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_napot_basic.S
     cosim: enabled
     iterations: 1

逐段解释：

* 第 101~106 行：``directed_pmp_regions`` 明确 ``cosim: enabled``。
* 第 108 行：源文件有一个注释标记新的 PMP directed tests 区域；本文只按存在的
  YAML 内容解释，不推断注释之外的批次含义。
* 第 110~122 行：``directed_pmp_tor_basic`` 与 ``directed_pmp_napot_basic`` 都使用
  ``eh2_directed``，源文件分别为对应 PMP 汇编，并启用 cosim。

接口关系：

* 被调用：directed 回归中的 PMP 分组。
* 调用：PMP 汇编源文件。
* 共享状态：``cosim: enabled``。

§10.4  coverage pump 注册窗口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L222-L303``）：

.. code-block:: yaml

   # Coverage pump directed tests (Task-D)

   - test: directed_pic_state_walk
     desc: "PIC/trap claim-complete state stimulus with IRQ sideband"
     config: eh2_directed_pic
     test_srcs: tests/asm/directed_pic_state_walk.S
     sim_opts: '+enable_irq_seq=1 +enable_irq_single_seq=1 +max_interval=20'
     cosim: disabled
     iterations: 1

   - test: directed_dbg_dret_walk
     desc: "Debug halt/resume and breakpoint trap stimulus"
     config: eh2_directed
     test_srcs: tests/asm/directed_dbg_dret_walk.S
     sim_opts: '+enable_debug_seq=1 +enable_debug_single=1 +max_interval=20'
     cosim: disabled
     iterations: 1

逐段解释：

* 第 222 行：YAML 将后续条目标记为 coverage pump directed tests。
* 第 224~230 行：``directed_pic_state_walk`` 使用 ``eh2_directed_pic`` 和 IRQ
  sideband plusarg，并显式 ``cosim: disabled``。
* 第 232~238 行：``directed_dbg_dret_walk`` 使用 debug sideband plusarg，也显式
  ``cosim: disabled``。
* 第 240~303 行：同一区域还注册 ``directed_dma_burst``、``directed_ifu_bp_btb``、
  ``directed_lsu_stbuf_full``、``directed_iccm_eccerror`` 和 5 个 toggle walk 条目，
  多数同样标记 ``cosim: disabled``。

接口关系：

* 被调用：coverage pump 回归配置。
* 调用：IRQ/debug/fetch/mem error 相关 plusarg 和对应汇编源。
* 共享状态：``cosim: disabled`` 表示这些条目不走 Spike lockstep 比较。

§11  根部最小样例
------------------------------------------------------------------------------------------------------------------------

职责：:file:`tests/asm/` 下的 ``smoke.S`` 与 ``nop.S`` 是更小的 bring-up 样例。
它们使用 ``.text`` section 和 byte mailbox store，不包含 directed testlist 中的
复杂 trap/PMP/AXI4 逻辑。

§11.1  ``nop.S``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``tests/asm/nop.S:L5-L17``）：

.. code-block:: bash

   .section .text
   .globl _start
   _start:
       nop
       nop
       nop
       nop
       // Write 0xFF (PASS) to mailbox
       lui   a0, 0xD0580      // a0 = 0xD0580000
       li    a1, 0xFF
       sb    a1, 0(a0)
       // Loop forever
   1:  j     1b

逐段解释：

* 第 5~7 行：样例直接使用 ``.text``，入口为 ``_start``。
* 第 8~11 行：连续 4 条 ``nop``，用于最小取指/执行路径。
* 第 13~15 行：与 ``smoke.S`` 相同，用 ``lui`` 构造 ``0xD0580000``，用 ``sb``
  写 ``0xFF``。
* 第 17 行：进入无限循环。

接口关系：

* 被调用：根目录 bring-up 样例。
* 调用：无函数调用。
* 共享状态：mailbox 地址 ``0xD0580000``。

§12  参考资料
------------------------------------------------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0002`：AXI4 passive monitoring，是 AXI4 error 注入和外部 memory
  directed 程序的总线背景。
* :ref:`adr-0006`：atomic cosim，对应 ``cosim_atomic_basic.S`` 的 LR/SC/AMO
  proof point。
* :ref:`adr-0007`：interrupt cosim，对应 ``directed_irq_basic.S`` 和
  ``directed_nested_irq.S`` 的 trap/ECALL 场景。
* :ref:`adr-0008`：debug cosim，对应 ``directed_debug_basic.S`` 和
  ``directed_dbg_dret_walk.S`` 的 EBREAK/debug stimulus。
* :ref:`adr-0009`：PMP/ePMP cosim，对应 ``directed_pmp_*.S``。
* :ref:`adr-0017`：integrity cosim waiver，解释 fault injection 类测试保持
  cosim disabled 的边界。
* :ref:`adr-0018`：strict ``wb_tag`` matching，对应 NB-load 和 writeback 关联风险。

关联章节：

* :ref:`tests_library`：测试库总览。
* :doc:`../06_flows/scripts_reference`：脚本入口、testlist 与回归参数。
* :doc:`cosim_cpp`：Spike DPI 与 cosim C++ 侧接口。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_link.ld`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_smoke.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_alu.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_load_store.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_dual_issue.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_exception_compare.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_atomic_basic.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_irq_basic.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_nested_irq.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_debug_basic.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_dbg_dret_walk.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_smoke.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_tor_basic.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_axi4_error_inject.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_dma_burst.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_lsu_stbuf_full.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_csr_walk.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_mul_div_walk.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_axi4_data_walk.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
* :file:`/home/host/eh2-veri/tests/asm/smoke.S`
* :file:`/home/host/eh2-veri/tests/asm/nop.S`
* :file:`/home/host/eh2-veri/tests/asm/smoke.ld`
