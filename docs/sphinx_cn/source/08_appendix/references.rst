.. _references:

参考资料索引
============

:status: draft
:source: README.md; docs/PROJECT_STATUS.md; docs/adr/INDEX.md; docs/dir-conventions.md; docs/requirements-docs.txt; docs/sphinx_cn/source/glossary.rst; docs/sphinx_cn/source/architecture.rst; dv/cosim/*; dv/uvm/core_eh2/riscv_dv_extension/*; lint/*; syn/*
:last-reviewed: 2026-05-16
:commit: bddb61be0a5bc43140245c8f5617c25925eacf3d

§1  本章边界
------------

**职责** ：本章把 EH2 验证平台使用到的规范、工具、参考平台和内部证据源组织成可追溯索引。每个条目优先给出仓库内落点，再说明它对应的外部概念。

**非职责** ：本章不维护外部网页链接清单，不把外部网页当成 release ground truth。sign-off 数字、ADR 编号、coverage 数字和限制项均以本仓库证据文件为准。

**关键代码**  （``README.md:L510-L523``）：

.. code-block:: bash

   ## Citation

   When referring to this platform in reports, cite the release artifact and the
   relevant ADR or manual section.

   For release status, cite `docs/PROJECT_STATUS.md`.

   For design decisions, cite the relevant ADR file under `docs/adr/`.

   For sign-off numbers, cite `build/r4a_final/signoff_status.json` rather than a
   copied table.

**逐段解释** ：

* 第 L510-L513 行：README 要求在报告中引用 release artifact、相关 ADR 或手册章节。
* 第 L515 行：release status 的引用源是 :file:`docs/PROJECT_STATUS.md`。
* 第 L517 行：设计决策引用 :file:`docs/adr/` 下的 ADR 文件。
* 第 L519-L523 行：sign-off 数字应引用 :file:`build/r4a_final/signoff_status.json`，而不是复制表格。

**接口关系** ：

* **被调用** ：报告、手册引用、release 审查。
* **调用** ：PROJECT_STATUS、ADR、sign-off JSON。
* **共享状态** ：引用顺序、release artifact、ADR 文件。

§2  内部权威证据源
------------------

**职责** ：列出当前状态读取入口，作为外部资料之前的第一层参考。

**关键代码**  （``docs/PROJECT_STATUS.md:L190-L208``）：

.. code-block:: bash

   ## Documentation Map

   Read these files for current status:

   | Document | Purpose |
   |---|---|
   | `README.md` | external onboarding and command entry point |
   | `CONTEXT.md` | project assumptions and domain context |
   | `docs/PROJECT_STATUS.md` | this one-page status dashboard |
   | `docs/release-notes-v1.1.md` | v1.0.2 GA to v1.1 release delta |
   | `docs/release-notes-v1.0.2-GA.md` | coverage and LEC GA baseline |
   | `docs/signoff-gates.md` | sign-off gate semantics |
   | `docs/dir-conventions.md` | generated artifact placement policy |
   | `docs/adr/INDEX.md` | canonical ADR list |
   | `docs/sphinx_cn/source/overview.rst` | manual overview |
   | `docs/sphinx_cn/source/architecture.rst` | manual architecture chapter |

**逐段解释** ：

* 第 L190-L193 行：PROJECT_STATUS 显式给出“当前状态”阅读入口。
* 第 L196-L203 行：README、CONTEXT、PROJECT_STATUS、release notes、sign-off gates、dir conventions 和 ADR index 是当前状态相关的内部文档。
* 第 L204-L208 行：Sphinx overview、architecture、quickstart 和 directory_layout 是手册入口。外部资料必须通过这些内部文档落到本仓库语境里。

**接口关系** ：

* **被调用** ：本文 §3-§15 的参考分组。
* **调用** ：README、CONTEXT、PROJECT_STATUS、release notes、ADR index 和 Sphinx 手册。
* **共享状态** ：current status documentation map。

§3  ADR 索引
------------

**职责** ：说明架构决策引用必须以 ADR 0001-0020 为 canonical 编号空间。

**关键代码**  （``docs/adr/INDEX.md:L1-L20``）：

.. code-block:: bash

   # ADR Index

   Date: 2026-05-12

   This file is the canonical index for EH2 verification platform architecture
   decision records.

   The ADR filenames are uniquely numbered from `0001` through `0020`.

   The historical audit called out duplicate ADR numbers in earlier drafts
   (`0008`, `0010`, and `0014`). The current file set no longer has duplicate
   filename prefixes:

   ```text
   0001 0002 0003 0004 0005 0006 0007 0008 0009 0010
   0011 0012 0013 0014 0015 0016 0017 0018 0019 0020
   ```

   Use the filename number as canonical when a legacy heading or older release note
   uses an earlier draft number.

**逐段解释** ：

* 第 L1-L6 行：ADR index 是 architecture decision records 的 canonical index。
* 第 L8 行：当前 ADR 文件名编号范围是 0001 到 0020。
* 第 L10-L17 行：早期重复编号已被修复，当前文件前缀没有重复。
* 第 L19-L20 行：历史 heading 或 release note 出现旧编号时，以文件名编号为 canonical。

**接口关系** ：

* **被调用** ：所有 ADR 编号引用、architecture_decisions、risk register 和 release notes。
* **调用** ：:file:`docs/adr/0001-*.md` 到 :file:`docs/adr/0020-*.md`。
* **共享状态** ：ADR 0001-0020 编号空间。

§4  ADR topic map
-----------------

**职责** ：把外部概念映射到本仓库 ADR 主题，避免把外部规范名称直接当成本仓库决策。

**关键代码**  （``docs/adr/INDEX.md:L47-L84``）：

.. code-block:: bash

   ## Topic Map

   Cosim data path:

   - ADR-0001: trace plus probe data path.
   - ADR-0004: retire trace fields.
   - ADR-0018: strict writeback tag matching.

   Bus and memory behavior:

   - ADR-0002: AXI4 passive monitoring.
   - ADR-0005: EH2 wider WSTRB handling.

   ISA and architectural comparison:

   - ADR-0006: atomic cosim.
   - ADR-0007: interrupt cosim.
   - ADR-0008: debug cosim.
   - ADR-0009: PMP/ePMP cosim.
   - ADR-0010: CSR model.
   - ADR-0017: integrity waiver boundary.

**逐段解释** ：

* 第 L47-L53 行：cosim data path 由 trace/probe、retire trace fields 和 strict writeback tag 三组 ADR 支撑。
* 第 L55-L58 行：AXI4 passive monitoring 与 wider WSTRB handling 属于 bus/memory behavior。
* 第 L60-L67 行：ISA 和 architectural comparison 覆盖 atomic、interrupt、debug、PMP/ePMP、CSR model 和 integrity waiver boundary。
* 后续 L69-L84 还把 formal/RVFI、synthesis/LEC、release integration 分组；本章在参考资料节使用这些组名。

**接口关系** ：

* **被调用** ：本文 §9-§13 的外部概念分组。
* **调用** ：ADR 0001、0002、0004、0005、0006、0007、0008、0009、0010、0017、0018。
* **共享状态** ：topic map 与 ADR 编号。

§5  RISC-V ISA 与 EH2 支持范围
-------------------------------

**职责** ：说明 RISC-V 规范类参考资料在本仓库中的落点：EH2 是 RV32IMAC 处理器，相关 ISA 行为由 directed/riscv-dv/compliance/cosim 共同验证。

**关键代码**  （``README.md:L20-L33``）：

.. code-block:: bash

   ## Project Scope

   VeeR EH2 is a 32-bit RISC-V processor core with RV32IMAC support, EH2-specific
   custom CSRs, tightly coupled memories, programmable interrupt control, debug
   logic, AXI/AHB-facing integration points, and a dual-thread-capable
   microarchitecture.

   This platform verifies the EH2 core through:

   - UVM testbench infrastructure under `dv/uvm/core_eh2`;
   - Spike DPI cosim under `dv/cosim`;
   - directed assembly tests under `dv/uvm/core_eh2/tests/asm`;
   - riscv-dv integration under `dv/uvm/core_eh2/riscv_dv_extension`;

**逐段解释** ：

* 第 L20-L25 行：EH2 被描述为 32-bit RISC-V 处理器，支持 RV32IMAC，同时包含 EH2-specific custom CSRs、tightly coupled memories、PIC、debug、AXI/AHB integration 和 dual-thread-capable microarchitecture。
* 第 L27-L33 行：ISA 相关验证落在 UVM、Spike DPI、directed ASM 和 riscv-dv extension。

**接口关系** ：

* **被调用** ：overview、architecture、tests library、compliance flow。
* **调用** ：``dv/uvm/core_eh2``、``dv/cosim``、ASM tests、riscv-dv extension。
* **共享状态** ：RV32IMAC、EH2 custom CSRs、directed/riscv-dv/cosim/compliance 验证边界。

§6  RISC-V toolchain 与 Spike
-----------------------------

**职责** ：说明 RISC-V toolchain 和 Spike 在本仓库里的环境变量、安装位置和引用方式。

**关键代码**  （``README.md:L413-L438``）：

.. code-block:: bash

   The full platform assumes access to commercial EDA tools and a RISC-V software
   toolchain.

   Required for full sign-off:

   - Synopsys VCS for SystemVerilog simulation;
   - Synopsys Design Compiler for synthesis inputs used by the LEC flow;
   - Synopsys Formality for block-level LEC;
   - Cadence IFV 15.20 for the v1.1 formal proof evidence;
   - Spike built with the EH2 cosim DPI integration;
   - `riscv32-unknown-elf-gcc`;
   - `riscv32-unknown-elf-objcopy`;
   - Python 3;
   - `pyyaml`;
   - GNU Make.

**逐段解释** ：

* 第 L413-L416 行：full platform 需要 commercial EDA tools 和 RISC-V software toolchain。
* 第 L418-L421 行：VCS、Design Compiler、Formality 和 Cadence IFV 分别服务 simulation、synthesis input、block-level LEC 和 formal proof evidence。
* 第 L422-L427 行：Spike、RISC-V GCC/objcopy、Python、pyyaml 和 GNU Make 是 full sign-off 的软件依赖。

**接口关系** ：

* **被调用** ：quickstart、system requirements、sign-off flow。
* **调用** ：VCS、DC、Formality、IFV、Spike、GCC、objcopy、Python、pyyaml、Make。
* **共享状态** ：toolchain 依赖列表。

**关键代码**  （``README.md:L429-L438``）：

.. code-block:: bash

   Common environment variables:

   | Variable | Meaning |
   |---|---|
   | `RV_ROOT` | Upstream VeeR EH2 RTL root |
   | `EH2_VERIF_ROOT` | This repository root |
   | `GCC_PREFIX` | RISC-V bare-metal compiler prefix |
   | `RISCV_DV_ROOT` | riscv-dv checkout or submodule path |
   | `SPIKE_INSTALL` | Spike cosim installation prefix |
   | `SIMULATOR` | Simulation backend, normally `vcs` |

**逐段解释** ：

* 第 L429-L438 行：RISC-V toolchain、riscv-dv 和 Spike 的路径通过 ``GCC_PREFIX``、``RISCV_DV_ROOT``、``SPIKE_INSTALL`` 进入流程。
* ``RV_ROOT`` 指向上游 VeeR EH2 RTL root，``EH2_VERIF_ROOT`` 指向本仓库根目录。

**接口关系** ：

* **被调用** ：env setup、Makefile、scripts。
* **调用** ：环境变量读取逻辑。
* **共享状态** ：``RV_ROOT``、``GCC_PREFIX``、``RISCV_DV_ROOT``、``SPIKE_INSTALL``、``SIMULATOR``。

§7  Spike DPI 本地落点
----------------------

**职责** ：说明 Spike 不是本手册中的抽象外链，而是通过 ``dv/cosim`` 和安装前缀进入 EH2 cosim。

**关键代码**  （``docs/sphinx_cn/source/glossary.rst:L258-L261``）：

.. code-block:: bash

   Spike DPI
     Spike RISC-V ISS 通过 SystemVerilog DPI 暴露的接口集合。
     ``dv/cosim/spike_cosim.cc`` 实现。Spike 上游来自
     ``/home/host/spike-cosim/`` 。

**逐段解释** ：

* 第 L258-L259 行：术语表把 Spike DPI 定义为 Spike RISC-V ISS 通过 SystemVerilog DPI 暴露的接口集合。
* 第 L260-L261 行：本仓库实现落点是 :file:`dv/cosim/spike_cosim.cc`，上游来自 ``/home/host/spike-cosim/``。

**接口关系** ：

* **被调用** ：cosim scoreboard、cosim C++ 附录、architecture。
* **调用** ：Spike cosim 安装和 C++ DPI 实现。
* **共享状态** ：``dv/cosim/spike_cosim.cc``、``/home/host/spike-cosim``。

**关键代码** （当前工作树 ``find dv/cosim -maxdepth 1 -type f | sort``）：

.. code-block:: bash

   dv/cosim/cosim.h
   dv/cosim/cosim_dpi.cc
   dv/cosim/cosim_dpi.svh
   dv/cosim/spike_cosim.cc
   dv/cosim/spike_cosim.h

**逐段解释** ：

* 第 L1-L2 行：``cosim.h`` 和 ``cosim_dpi.cc`` 是 cosim DPI 的 C/C++ 入口。
* 第 L3 行：``cosim_dpi.svh`` 是 SystemVerilog 侧 DPI 声明。
* 第 L4-L5 行：``spike_cosim.cc`` 和 ``spike_cosim.h`` 是 Spike 适配层。

**接口关系** ：

* **被调用** ：UVM cosim agent package 与 DPI shared library build。
* **调用** ：Spike ISS C++ API。
* **共享状态** ：DPI header、SVH、Spike adapter。

§8  riscv-dv 参考
-----------------

**职责** ：说明 riscv-dv 作为外部参考工具时，在 EH2 仓库中的集成方式和配置文件位置。

**关键代码**  （``docs/sphinx_cn/source/architecture.rst:L191-L207``）：

.. code-block:: bash

   riscv-dv 集成
   ------------------------------------------------------------------------------------------

   平台不 fork riscv-dv，而是以 git submodule 形式锁定到
   ``vendor/google_riscv-dv/`` 。集成点全部集中在
   ``dv/uvm/core_eh2/riscv_dv_extension/`` ：

   .. list-table::
      :header-rows: 1
      :widths: 32 68

      * - 文件
        - 职责
      * - ``testlist.yaml``
        - 43 个 riscv-dv entry，其中 11 个 ``skip_in_signoff`` ；每个 entry
          指定 ``rtl_test``、``gen_opts``、``sim_opts``、``cosim`` 等策略字段

**逐段解释** ：

* 第 L191-L196 行：architecture 文档明确平台不 fork riscv-dv，而是锁定到 ``vendor/google_riscv-dv``，EH2 集中扩展位于 ``dv/uvm/core_eh2/riscv_dv_extension``。
* 第 L198-L207 行：``testlist.yaml`` 是 riscv-dv entry 的策略文件，包含 ``rtl_test``、``gen_opts``、``sim_opts``、``cosim`` 等字段。

**接口关系** ：

* **被调用** ：riscv-dv flow、regression flow、sign-off riscvdv stage。
* **调用** ：vendor riscv-dv 和 EH2 extension。
* **共享状态** ：``vendor/google_riscv-dv``、``riscv_dv_extension``、testlist 字段。

**关键代码** （当前工作树 ``find dv/uvm/core_eh2/riscv_dv_extension -maxdepth 1 -type f | sort`` 摘要）：

.. code-block:: bash

   dv/uvm/core_eh2/riscv_dv_extension/cov_testlist.yaml
   dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml
   dv/uvm/core_eh2/riscv_dv_extension/ddm_link.ld
   dv/uvm/core_eh2/riscv_dv_extension/eh2_asm_program_gen.sv
   dv/uvm/core_eh2/riscv_dv_extension/eh2_debug_triggers_overrides.sv
   dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv
   dv/uvm/core_eh2/riscv_dv_extension/eh2_log_to_trace_csv.py
   dv/uvm/core_eh2/riscv_dv_extension/ml_testlist.yaml
   dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv
   dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml

**逐段解释** ：

* 第 L1-L3 行：coverage testlist、CSR description 和 linker script 是 riscv-dv 生成/编译相关配置。
* 第 L4-L7 行：EH2 assembly program generator、debug trigger override、directed instruction library 和 log-to-trace converter 承载 EH2 定制行为。
* 第 L8-L10 行：ML testlist、core setting 和主 testlist 共同定义 riscv-dv 配置表面。

**接口关系** ：

* **被调用** ：instruction generation、riscv-dv regression、coverage collection。
* **调用** ：riscv-dv vendor 代码、EH2 UVM tests 和 scripts。
* **共享状态** ：testlist、core setting、CSR description、EH2 stream overrides。

§9  AXI4 与总线协议参考
------------------------

**职责** ：说明 AXI4 参考资料在 EH2 验证平台中落到 AXI4 passive monitoring 和 shared RTL 上。

**关键代码**  （``docs/adr/INDEX.md:L55-L58``）：

.. code-block:: bash

   Bus and memory behavior:

   - ADR-0002: AXI4 passive monitoring.
   - ADR-0005: EH2 wider WSTRB handling.

**逐段解释** ：

* 第 L55-L58 行：ADR topic map 将 AXI4 passive monitoring 和 wider WSTRB handling 归入 bus/memory behavior。
* AXI4 协议本身是外部总线规范；在本仓库中，它的验证决策落到 :ref:`adr-0002` 和 :ref:`adr-0005`。

**接口关系** ：

* **被调用** ：AXI4 agent、shared RTL、cosim memory notification、LEC/synthesis flow。
* **调用** ：:file:`shared/rtl/axi4_pkg.sv`、:file:`shared/rtl/axi4_intf.sv`、:file:`shared/rtl/axi4_slave_mem.sv`。
* **共享状态** ：AXI4 passive monitoring、WSTRB 行为。

§10  UVM 与 SystemVerilog 参考
------------------------------

**职责** ：说明 UVM/SystemVerilog 参考资料在本仓库中对应的目录和工具，而不是只列规范名。

**关键代码**  （``README.md:L3-L10``）：

.. code-block:: bash

   EH2 Verification Platform is a UVM, cosim, coverage, formal, and sign-off
   environment for the VeeR EH2 RISC-V core.

   This repository is not a marketing wrapper around a few smoke tests. It is a
   release-oriented verification workspace that collects RTL simulation,
   Spike-based instruction lockstep, directed assembly, riscv-dv stimulus,
   coverage, CSR unit checks, RISC-V compliance, lint, formal proof, and
   block-level LEC into one sign-off record.

**逐段解释** ：

* 第 L3-L4 行：README 将平台定义为 UVM、cosim、coverage、formal 和 sign-off environment。
* 第 L6-L10 行：SystemVerilog/UVM 相关内容不仅是 testbench，还包括 RTL simulation、Spike lockstep、directed ASM、riscv-dv、coverage、CSR unit、compliance、lint、formal 和 LEC。

**接口关系** ：

* **被调用** ：UVM 类字典、testbench、functional coverage、flow 文档。
* **调用** ：VCS/SystemVerilog/UVM 编译和仿真。
* **共享状态** ：UVM testbench、coverage、formal proof、LEC。

§11  lint 工具参考
------------------

**职责** ：说明 Verible 与 Verilator 参考资料在本仓库中的配置文件位置。

**关键代码** （当前工作树 ``find lint -maxdepth 2 -type f | sort``）：

.. code-block:: bash

   lint/Makefile
   lint/README.md
   lint/verible/verible.rules
   lint/verible/waivers.vbl
   lint/verilator/verilator-config.vlt
   lint/verilator/verilator_waiver.vlt

**逐段解释** ：

* 第 L1-L2 行：lint 有独立 Makefile 和 README。
* 第 L3-L4 行：Verible 规则和 waiver 位于 ``lint/verible``。
* 第 L5-L6 行：Verilator 配置和 waiver 位于 ``lint/verilator``。

**接口关系** ：

* **被调用** ：lint flow、sign-off lint stage。
* **调用** ：Verible 和 Verilator。
* **共享状态** ：lint rules、waivers、tool config。

§12  synthesis 与 LEC 工具参考
-------------------------------

**职责** ：说明 Yosys、Design Compiler、Formality 等工具参考资料在本仓库中的脚本落点。

**关键代码** （当前工作树 ``find syn -maxdepth 2 -type f | sort`` 摘要）：

.. code-block:: bash

   syn/Makefile
   syn/README.md
   syn/lec/eh2_lec.tcl
   syn/nangate/eh2_nangate.sdc
   syn/scripts/dc_elab_fixed.tcl
   syn/scripts/dc_elaborate_flat.tcl
   syn/scripts/dc_synth.tcl
   syn/scripts/dc_synth_block.tcl
   syn/scripts/lec_rc4_final.tcl
   syn/scripts/lec_run.tcl
   syn/scripts/lec_summary.py
   syn/yosys/eh2_synth.tcl

**逐段解释** ：

* 第 L1-L4 行：syn 顶层包含 Makefile、README、LEC TCL 和 Nangate SDC。
* 第 L5-L8 行：Design Compiler 相关 TCL 脚本位于 ``syn/scripts``。
* 第 L9-L11 行：Formality/LEC run 和 summary 脚本也位于 ``syn/scripts``。
* 第 L12 行：Yosys 脚本位于 ``syn/yosys``。

**接口关系** ：

* **被调用** ：synthesis flow、LEC flow、sign-off syn stage。
* **调用** ：Yosys、Design Compiler、Formality、Nangate SDC。
* **共享状态** ：synthesis scripts、LEC scripts、summary parser。

§13  Ibex 参考平台边界
----------------------

**职责** ：说明 lowRISC Ibex 是方法论参考，不是 EH2 行为 ground truth。

**关键代码**  （``README.md:L38-L41``）：

.. code-block:: bash

   The platform is modeled after the lowRISC Ibex verification flow, but it is not
   a line-for-line port. EH2 has different bus topology, trace behavior, CSR
   surface, debug topology, memory error paths, and multi-thread support, so the
   verification architecture is adapted around EH2-specific contracts.

**逐段解释** ：

* 第 L38-L39 行：README 明确 EH2 平台借鉴 lowRISC Ibex verification flow，但不是逐行移植。
* 第 L39-L41 行：EH2 与 Ibex 在 bus topology、trace behavior、CSR surface、debug topology、memory error paths 和 multi-thread support 上不同，因此验证架构围绕 EH2-specific contracts 适配。

**接口关系** ：

* **被调用** ：Ibex capability matrix、architecture、verification overview。
* **调用** ：本地 Ibex checkout 只作为对照参考。
* **共享状态** ：Ibex reference flow 与 EH2-specific contracts 的边界。

**关键代码** （当前环境 ``find /home/host/ibex -maxdepth 2 -type d`` 摘要）：

.. code-block:: bash

   /home/host/ibex/dv/cosim
   /home/host/ibex/dv/cs_registers
   /home/host/ibex/dv/formal
   /home/host/ibex/dv/riscv_compliance
   /home/host/ibex/dv/uvm
   /home/host/ibex/lint
   /home/host/ibex/rtl
   /home/host/ibex/shared/rtl
   /home/host/ibex/syn
   /home/host/ibex/vendor/google_riscv-dv
   /home/host/ibex/vendor/riscv-isa-sim

**逐段解释** ：

* 第 L1-L5 行：Ibex 本地 checkout 具备 cosim、CSR registers、formal、riscv compliance 和 UVM 验证目录。
* 第 L6-L9 行：Ibex 也有 lint、RTL、shared RTL 和 synthesis 目录。
* 第 L10-L11 行：Ibex vendor 下包含 google_riscv-dv 和 riscv-isa-sim；EH2 使用这些目录作为能力对标参考时，仍以 EH2 当前源码为最终证据。

**接口关系** ：

* **被调用** ：:ref:`ibex_capability_matrix`。
* **调用** ：本地 ``/home/host/ibex`` checkout。
* **共享状态** ：参考平台目录，而非 EH2 release ground truth。

§14  docs build 参考
--------------------

**职责** ：说明 Sphinx/rinohtype 等文档构建依赖的本地记录位置。

**关键代码**  （``docs/requirements-docs.txt:L1-L6``）：

.. code-block:: bash

   # EH2 UVM 验证平台中文手册依赖
   # 安装：pip install --user -r docs/requirements-docs.txt
   # Python 推荐 3.10+（rinohtype 0.5.x 在 3.6 importlib_metadata 上有兼容问题）

   sphinx>=7.0
   rinohtype>=0.5.5

**逐段解释** ：

* 第 L1-L3 行：该文件说明中文手册依赖和安装方式，并推荐 Python 3.10+。
* 第 L5-L6 行：文档依赖包含 Sphinx 和 rinohtype。

**接口关系** ：

* **被调用** ：manual build、PDF build。
* **调用** ：Python packaging。
* **共享状态** ：Sphinx、rinohtype、Python 版本建议。

§15  工具产物与报告引用
------------------------

**职责** ：说明引用工具报告时应引用正式输出目录，而不是根目录残留或人工复制内容。

**关键代码**  （``docs/dir-conventions.md:L1-L13``）：

.. code-block:: bash

   # EH2 目录与工具产物规范

   本文档定义 EH2 验证平台中 EDA 工具产物的落盘位置、清理方式和排查规则。
   目标是让仓库根目录保持干净，同时保留可复现 sign-off、覆盖率和 LEC 结果。

   ## 基本原则

   1. 仓库根目录只放源码、脚本、文档和少量顶层配置。
   2. 可再生的大文件统一进入 `build/`、`syn/build/` 或对应子系统的 build 目录。
   3. EDA 工具默认在当前工作目录生成的文件，必须通过脚本切换工作目录或显式输出路径收敛。
   4. `build/r3b_final/` 是 v1.0.2 GA 交付物，不纳入自动清理。
   5. `syn/build/lec_summary.txt` 是 R3-C/D LEC 闭环摘要，不纳入自动清理。
   6. `.gitignore` 负责避免误提交，`scripts/clean_workspace.sh` 负责回收根目录残留。

**逐段解释** ：

* 第 L1-L4 行：dir conventions 负责 EDA 工具产物落盘、清理和排查规则，目标是保持根目录干净并保留可复现 sign-off、coverage 和 LEC。
* 第 L8-L13 行：源码/脚本/文档留在仓库根；大文件进入 ``build``、``syn/build`` 或子系统 build；``build/r3b_final`` 和 ``syn/build/lec_summary.txt`` 是保留证据。

**接口关系** ：

* **被调用** ：release 状态引用、clean workspace、目录速查。
* **调用** ：``scripts/clean_workspace.sh``。
* **共享状态** ：build 目录、syn/build、release 工件保留策略。

§16  参考资料使用规则
----------------------

**职责** ：把本章的引用规则固化为可执行顺序，避免直接从外部网页复制当前状态。

**关键代码** （本章规则化读取顺序）：

.. code-block:: bash

   git rev-parse HEAD
   sed -n '1,80p' README.md
   sed -n '190,208p' docs/PROJECT_STATUS.md
   sed -n '1,105p' docs/adr/INDEX.md
   find dv/cosim -maxdepth 1 -type f | sort
   find dv/uvm/core_eh2/riscv_dv_extension -maxdepth 1 -type f | sort
   find lint syn -maxdepth 2 -type f | sort
   sed -n '1,160p' docs/dir-conventions.md

**逐段解释** ：

* 第 1 行：先记录 commit，保证引用和行号绑定到源版本。
* 第 2-L4 行：先读 README、PROJECT_STATUS 和 ADR index，建立内部 ground truth。
* 第 5-L7 行：再读 cosim、riscv-dv、lint、syn 的本地文件集合，确认工具集成点存在。
* 第 8 行：最后读目录和工具产物规范，确定哪些报告可引用、哪些目录不可编辑。

**接口关系** ：

* **被调用** ：手册维护和审查抽检。
* **调用** ：git、sed、find。
* **共享状态** ：commit、内部证据源、工具集成点。

参考资料
--------

* :file:`/home/host/eh2-veri/README.md` — 项目范围、工具依赖、第三方组件和 citation 规则。
* :file:`/home/host/eh2-veri/docs/PROJECT_STATUS.md` — 当前 release 状态、documentation map 和版本演进。
* :file:`/home/host/eh2-veri/docs/adr/INDEX.md` — ADR 0001-0020 canonical index 和 topic map。
* :file:`/home/host/eh2-veri/docs/dir-conventions.md` — EDA 工具产物落盘与清理规范。
* :file:`/home/host/eh2-veri/docs/requirements-docs.txt` — Sphinx/rinohtype 文档构建依赖。
* :file:`/home/host/eh2-veri/dv/cosim` — Spike DPI cosim 本地实现目录。
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension` — riscv-dv EH2 集成目录。
* :file:`/home/host/eh2-veri/lint` — Verible/Verilator lint 配置目录。
* :file:`/home/host/eh2-veri/syn` — synthesis、Yosys、Nangate、LEC 脚本目录。
* :file:`/home/host/ibex` — lowRISC Ibex 本地参考 checkout，仅作对照参考。
* :ref:`adr-0002` — AXI4 passive monitoring。
* :ref:`adr-0005` — EH2 wider WSTRB handling。
* :ref:`adr-0011` — compliance framework。
* :ref:`adr-0012` — formal strategy。
* :ref:`adr-0013` — synthesis toolchain。
* :ref:`adr-0020` — block-level LEC。
