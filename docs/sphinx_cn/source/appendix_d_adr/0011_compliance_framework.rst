.. _adr-0011:

ADR-0011: RISC-V Compliance Framework
========================================

:status: Accepted
:source: docs/adr/0011-compliance-framework.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：EH2 需要一套 RISC-V 合规验证框架以确保核心正确实现了 RISC-V ISA 规范。
框架运行标准 RISC-V 合规测试套件，捕获签名输出并与黄金参考输出逐字节比较。两台
主机上有两个上游合规框架可用：``riscv-compliance`` （原始的 Imperas/Codasip 合规
框架，每指令测试）和 ``riscv-tests`` （官方 RISC-V ISA 测试）。

**决策** ：使用 **riscv-compliance** 作为主框架，覆盖 rv32i、rv32im、rv32imc、
rv32Zicsr、rv32Zifencei。使用该框架的测试源文件和参考输出，但使用 EH2 自己的
device 文件（linker script、startup code、compliance I/O headers）编译。
riscv-tests 仓库作为未来扩展的回退方案。

**签名比较策略** ：逐字节比较，绝不放松。合规测试将结果写入 ``.signature`` 数据段，
测试结束时 ``RV_COMPLIANCE_HALT`` 将 begin/end 签名地址写入 EH2 合规邮箱
（``0xD0580004`` / ``0xD0580008`` ），然后通过写 ``0xD0580000`` 触发签名 dump。
testbench 从 AXI4 slave memory 读取签名范围并输出 ``SIGNATURE: XXXXXXXX`` 行到
stdout。Python runner（``scripts/run_compliance.py`` ）解析这些行并将每个 32-bit
字与参考文件逐字节比较。任何字节差异 = FAIL，不允许模糊匹配。

**Testbench 架构** ：提供两种 TB 选项。``core_eh2_tb_top`` （完整 UVM TB）可通过
``+bin=`` 运行合规 hex 文件。``eh2_compliance_tb`` （独立合规 TB）无 UVM 依赖，
内置 signature monitor，Verilator 就绪。两者都实例化 ``eh2_veer_wrapper`` ，连接
AXI4 slave memory，监控 ``0xD0580000`` 邮箱。

**后果** ：sign-off 流程中的自动化关卡——``full`` profile 包含 ``compliance`` stage。
可立即捕获 ISA 回退（错误的 ALU 结果、误解码指令）。逐字节 diff 意味着不会漏过签名
损坏。Device files 按 ISA 独立，允许 ISA-specific startup/link 差异。不过合规测试
需要完整的 simv 构建（每测试运行约 30--60 秒）。已知失败套件（rv32Zicsr、
rv32Zifencei）仍运行签名比较但可能合法失败，这些作为后续闭合跟踪项。合规 stage
默认仅运行 rv32i/rv32im/rv32imc，Z-extensions 需要显式 ``--isa`` 标志。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - RISC-V compliance 子环境
     - :file:`docs/adr/0011-*`
   * - 代码路径 1
     - :file:`dv/uvm/riscv_compliance/Makefile`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/riscv_compliance/tb`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/riscv_compliance/scripts`
     - 当前仓库实际文件


签核与边界
----------

当前 compliance stage 实跑 85/88（96.59%），签名比较仍是逐字节严格模式。该 stage 与 riscv-dv 随机测试互补，重点覆盖标准 ISA compliance 输入空间。

统一签核口径为 2026-05-19 01:02 VCS 主线 demo：``9/9`` stages PASS，实跑覆盖率
``102/104`` （98.1%），LEC ``31635/31635`` PASS。覆盖率由 VCS ``simv.vdb``
经 URG 原生 dashboard 生成，编译时 :file:`dv/uvm/core_eh2/cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，指标为 ``line+tgl+assert+fsm+branch`` 五维，
不包含 cond 维度。NC/Incisive 是完整备选 simulator，可运行 smoke、regress、sign-off、demo 与覆盖率 cross-check；默认 release 参考仍为 VCS/URG。

参考章节
--------

* :ref:`adr_summary`
* :ref:`signoff_flow`
* :ref:`appendix_b_uvm/index`
* :ref:`appendix_c_tools/index`
