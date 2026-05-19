.. _appendix_c_tools/formal_infra:
.. _appendix_c_tools_formal_infra:

形式验证基础设施源码
================================================================================

:status: draft
:source: dv/formal/Makefile; dv/formal/eh2_formal_top.sv; dv/formal/eh2_veer_sva.sv; dv/formal/ifv_filelist.f; dv/formal/scripts/ifv_prove.tcl; dv/formal/scripts/ifv_cex_dump.tcl; dv/formal/spec/sail_setup.sh; dv/formal/spec/sail_trace_check.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  总览
--------------------------------------------------------------------------------

本章解释 :file:`dv/formal/` 目录下的形式验证基础设施。它不是 property 字典；property
本体的逐条说明由 :doc:`formal_properties` 承担。本章关注的是基础设施如何把 EH2 RTL、
formal harness、SVA bind、IFV 脚本和 Sail 辅助检查串起来。

源码结构如下：

.. code-block:: text

   dv/formal/Makefile
      │
      ├─ target ifv
      │    ├─ ifv -f ifv_filelist.f +top+eh2_veer +loop_unroll_size+2048 -c
      │    └─ ifv -r +tcl+scripts/ifv_prove.tcl
      │
      ├─ target ifv_cex
      │    └─ ifv -r +tcl+scripts/ifv_cex_dump.tcl
      │
      └─ target ifv_count / ifv_clean

   ifv_filelist.f
      ├─ +define+FORMAL
      ├─ include snapshots/default + design/include + design/lib
      ├─ ifv_bootstrap.sv
      ├─ RTL design files
      └─ eh2_veer_sva.sv

   eh2_veer_sva.sv
      ├─ module eh2_veer_sva
      ├─ assumptions for reset/scan/vector stability
      ├─ structural assertions on reset, AXI, memory, debug, trace
      ├─ cover properties
      └─ bind eh2_veer eh2_veer_sva u_eh2_veer_sva (.*)

   spec/
      ├─ sail_setup.sh
      └─ sail_trace_check.py

当前 IFV 路径以 `eh2_veer` 为 top。`eh2_formal_top.sv` 仍在源码树中保存 full-core
formal testbench，但 `ifv_filelist.f` 当前实际列入的是 `ifv_bootstrap.sv`、RTL 设计文件
和 `eh2_veer_sva.sv`。这一点必须从 filelist 判断，不能只看文件名推断。

§2  Makefile 入口
--------------------------------------------------------------------------------

§2.1  变量与 IFV 编译选项
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`dv/formal/Makefile` 定义 IFV 入口、输出目录、filelist、脚本目录、top 名称和 IFV 15.20 所需的 loop unroll 参数。

关键代码（`dv/formal/Makefile:L1-L16`）：

.. code-block:: makefile

   # EH2 formal verification flow using Cadence Incisive Formal Verifier.

   SHELL := /bin/bash

   BUILD_DIR := build
   FILELIST  := ifv_filelist.f
   SCRIPTS   := scripts
   IFV       := ifv
   IFV_TOP   := eh2_veer

   # IFV 15.20 needs a high loop unroll limit for EH2 IFU/PIC generated muxes.
   # One EXU data-dependent loop still remains tool-limited and is documented in
   # known_fails.md, but this option avoids extra IFU/PIC black-boxing.
   IFV_COMPILE_OPTS := +top+$(IFV_TOP) +loop_unroll_size+2048

   .DEFAULT_GOAL := ifv

逐段解释：

* 第 3 行：强制使用 `/bin/bash`，后续 recipe 中的 shell 语义按 Bash 执行。
* 第 5-L8 行：`build` 是输出目录；`ifv_filelist.f` 是 IFV 编译 filelist；`scripts` 是 Tcl 脚本目录；`IFV` 默认命令名是 `ifv`。
* 第 9 行：`IFV_TOP` 当前是 `eh2_veer`，不是 `eh2_formal_top`。
* 第 11-L14 行：`+loop_unroll_size+2048` 是针对 IFV 15.20 的编译选项。源码注释说明 IFU/PIC generated mux 需要较高 loop unroll limit，同时仍存在一个 EXU data-dependent loop 的工具限制。
* 第 16 行：默认目标是 `ifv`，用户在 `dv/formal` 下直接运行 `make` 会进入主证明目标。

接口关系：

* 被调用：命令行 `make -C dv/formal` 或 `make -C dv/formal ifv`。
* 调用：`ifv` 命令、`ifv_filelist.f` 和 `scripts/ifv_prove.tcl`。
* 共享状态：所有输出写入 `dv/formal/build/`。

§2.2  `ifv` 与 `formal` target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`ifv` target 先做 IFV compile/elaboration，再运行 prove Tcl，最后从运行日志中提取 assertion summary。

关键代码（`dv/formal/Makefile:L18-L27`）：

.. code-block:: makefile

   .PHONY: ifv formal ifv_clean formal_clean ifv_count formal_count ifv_cex

   ifv:
           @mkdir -p $(BUILD_DIR)
           $(IFV) -f $(FILELIST) $(IFV_COMPILE_OPTS) -c -l $(BUILD_DIR)/ifv_elab.log
           $(IFV) -r +tcl+$(SCRIPTS)/ifv_prove.tcl -l $(BUILD_DIR)/ifv_run.log
           @grep -A 6 "Assertion Summary" $(BUILD_DIR)/ifv_run.log > $(BUILD_DIR)/ifv_summary.txt || true
           @cat $(BUILD_DIR)/ifv_summary.txt

   formal: ifv

逐段解释：

* 第 18 行：`ifv`、`formal`、清理、计数和 cex 相关目标都声明为 phony。
* 第 20-L22 行：`ifv` 目标创建 `build` 目录，然后用 `ifv -f ifv_filelist.f` 编译，附加 `+top+eh2_veer +loop_unroll_size+2048`，并把 elaboration 日志写入 `build/ifv_elab.log`。
* 第 23 行：第二次调用 IFV 使用 `-r +tcl+scripts/ifv_prove.tcl` 运行证明脚本，日志写入 `build/ifv_run.log`。
* 第 24-L25 行：从 `ifv_run.log` 提取 `"Assertion Summary"` 后 6 行到 `ifv_summary.txt`。`|| true` 表示即使 grep 没命中，Makefile 也继续执行并 `cat` summary 文件。
* 第 27 行：`formal` 只是 `ifv` 的别名 target。

接口关系：

* 被调用：用户或上层 sign-off flow 调用 `make -C dv/formal ifv`。
* 调用：`ifv_filelist.f`、`scripts/ifv_prove.tcl`。
* 共享状态：产生 `build/ifv_elab.log`、`build/ifv_run.log`、`build/ifv_summary.txt`。

§2.3  `ifv_cex` 诊断 target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`ifv_cex` target 调用 `ifv_cex_dump.tcl`，为已知失败 property 生成文本诊断文件数量统计。

关键代码（`dv/formal/Makefile:L29-L33`）：

.. code-block:: makefile

   ifv_cex:
           @mkdir -p $(BUILD_DIR)
           $(IFV) -r +tcl+$(SCRIPTS)/ifv_cex_dump.tcl -l $(BUILD_DIR)/ifv_cex_run.log
           @ls $(BUILD_DIR)/cex_*.txt 2>/dev/null | wc -l

逐段解释：

* 第 29-L31 行：该 target 不重新编译 filelist，只运行 IFV runtime Tcl `ifv_cex_dump.tcl`，日志写入 `build/ifv_cex_run.log`。
* 第 32 行：统计 `build/cex_*.txt` 文件数量。`2>/dev/null` 屏蔽没有 cex 文件时的 `ls` 错误。

接口关系：

* 被调用：调试失败 property 时运行 `make -C dv/formal ifv_cex`。
* 调用：`scripts/ifv_cex_dump.tcl`。
* 共享状态：读取当前 IFV session 状态，输出 `build/ifv_cex_run.log` 和 `build/cex_*.txt`。

§2.4  `ifv_count` 与清理 target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`ifv_count` 用 grep 统计 SVA 文件数量、assertion 标签数量和 cover 标签数量；`ifv_clean` 删除 IFV 运行产物。

关键代码（`dv/formal/Makefile:L34-L52`）：

.. code-block:: makefile

   ifv_count:
           @echo "=== IFV Property Count ==="
           @echo "SVA files: $$(ls *.sv properties/*.sv 2>/dev/null | wc -l)"
           @asserts=$$(grep -Rho '^[[:space:]]*a_[A-Za-z0-9_]*:' *.sv properties/*.sv 2>/dev/null | wc -l); \
           covers=$$(grep -Rho '^[[:space:]]*c_[A-Za-z0-9_]*:' *.sv properties/*.sv 2>/dev/null | wc -l); \
           echo "Assertions: $$asserts"; \
           echo "Covers:     $$covers"; \
           echo "Total:      $$((asserts + covers))"

   formal_count: ifv_count

   ifv_clean:
           @echo "=== Cleaning IFV artifacts ==="

逐段解释：

* 第 34-L41 行：`ifv_count` 只扫描当前目录 `*.sv` 和 `properties/*.sv`。assertion 标签必须以 `a_` 开头，cover 标签必须以 `c_` 开头，才会进入计数。
* 第 43 行：`formal_count` 是 `ifv_count` 的别名 target。
* 第 45-L50 行：`ifv_clean` 删除 `build/ifv_*.log`、`build/ifv_*.tcl`、`build/ifv_*.input`、`ifv_summary.txt`、`cex_*.txt`、`build/ifv_work` 和 `.ifv`。
* 第 52 行：`formal_clean` 是 `ifv_clean` 的别名 target。

接口关系：

* 被调用：人工检查 property 数量或清理 IFV 工作目录时运行。
* 调用：`ls`、`grep`、`wc`、`rm`。
* 共享状态：只读源文件计数；清理时删除 `dv/formal/build/` 内 IFV 产物和 `.ifv`。

§3  IFV filelist 与 bootstrap
--------------------------------------------------------------------------------

§3.1  编译宏与 include path
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`ifv_filelist.f` 给 IFV 编译器提供宏定义、include path、bootstrap、RTL 文件顺序和 SVA bind 文件。

关键代码（`dv/formal/ifv_filelist.f:L1-L14`）：

.. code-block:: text

   // IFV Filelist — EH2 Core + Formal Properties
   // RC5 (2026-05-09): Fixed bootstrap + formal_top for IFV 15.20 compatibility.
   // eh2_param.vh moved inside modules (was at file scope, causing SVNOTY).

   +define+FORMAL
   +define+RV_BUILD_AXI4
   +incdir+/home/host/Cores-VeeR-EH2/snapshots/default
   +incdir+/home/host/Cores-VeeR-EH2/design/include
   +incdir+/home/host/Cores-VeeR-EH2/design/lib
   +incdir+/home/host/eh2-veri/dv/formal/properties
   +incdir+/home/host/eh2-veri/dv/formal

   // Bootstrap: macro and type-definition files for $unit scope
   /home/host/eh2-veri/dv/formal/ifv_bootstrap.sv

逐段解释：

* 第 1-L3 行：注释记录 RC5 处理点：bootstrap 和 formal top 为 IFV 15.20 兼容而修正，`eh2_param.vh` 从文件作用域移入 module 内。
* 第 5-L6 行：定义 `FORMAL` 和 `RV_BUILD_AXI4`。`FORMAL` 使 formal-only 代码路径可见；`RV_BUILD_AXI4` 选择 AXI4 构建路径。
* 第 7-L11 行：include path 指向 VeeR EH2 snapshot、design include/lib、formal properties 和 `dv/formal` 本身。
* 第 13-L14 行：在 RTL 设计文件之前先编译 `ifv_bootstrap.sv`，为 `$unit` 作用域的宏和类型定义建立上下文。

接口关系：

* 被调用：`Makefile:ifv` 的 `ifv -f ifv_filelist.f`。
* 调用：IFV 编译器读取这些路径和文件。
* 共享状态：定义影响后续全部 RTL 与 SVA 编译。

§3.2  RTL 文件顺序与 SVA bind 文件尾部接入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：filelist 明确列出 design include/lib、DMI、debug、decode、EXU、LSU、IFU、memory、PIC、DMA 和 core top，最后追加 `eh2_veer_sva.sv`。

关键代码（`dv/formal/ifv_filelist.f:L16-L34`）：

.. code-block:: text

   // RTL design files (same as synthesis flist)
   /home/host/Cores-VeeR-EH2/design/include/eh2_def.sv
   /home/host/Cores-VeeR-EH2/design/lib/eh2_lib.sv
   /home/host/Cores-VeeR-EH2/design/lib/beh_lib.sv
   /home/host/Cores-VeeR-EH2/design/lib/mem_lib.sv
   /home/host/Cores-VeeR-EH2/design/lib/ahb_to_axi4.sv
   /home/host/Cores-VeeR-EH2/design/lib/axi4_to_ahb.sv
   /home/host/Cores-VeeR-EH2/design/dmi/dmi_wrapper.v
   /home/host/Cores-VeeR-EH2/design/dmi/dmi_jtag_to_core_sync.v
   /home/host/Cores-VeeR-EH2/design/dmi/rvjtag_tap.v
   /home/host/Cores-VeeR-EH2/design/dbg/eh2_dbg.sv
   /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_decode_ctl.sv
   /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_gpr_ctl.sv
   /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_ib_ctl.sv
   /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_tlu_ctl.sv

逐段解释：

* 第 16-L22 行：filelist 先读基础 include/lib 和 AHB/AXI bridge。
* 第 23-L26 行：随后读 DMI/JTAG 和 debug 模块。
* 第 27-L34 行：decode 子系统按控制、GPR、IB、TLU、CSR、trigger、顶层的顺序列入。

关键代码（`dv/formal/ifv_filelist.f:L51-L66`）：

.. code-block:: text

   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_aln_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_compress_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_ifc_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_bp_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_ic_mem.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_mem_ctl.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_iccm_mem.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_btb_mem.sv
   /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu.sv
   /home/host/Cores-VeeR-EH2/design/eh2_mem.sv
   /home/host/Cores-VeeR-EH2/design/eh2_pic_ctrl.sv
   /home/host/Cores-VeeR-EH2/design/eh2_dma_ctrl.sv
   /home/host/Cores-VeeR-EH2/design/eh2_veer.sv

   // SVA bind module: binds to eh2_veer using .* auto-connect (no manual port mapping)
   /home/host/eh2-veri/dv/formal/eh2_veer_sva.sv

逐段解释：

* 第 51-L59 行：IFU 子系统从 align、compress、interface control、branch prediction、I-cache memory、memory control、ICCM memory、BTB memory 到 IFU top。
* 第 60-L63 行：全局 memory、PIC、DMA 和 `eh2_veer.sv` 在 IFU/LSU 等子模块之后列入。
* 第 65-L66 行：`eh2_veer_sva.sv` 放在 RTL 后面，并用 `bind eh2_veer ... (.*)` 自动连接到 RTL top。

接口关系：

* 被调用：IFV 编译读取 filelist。
* 调用：实际 RTL 文件和 SVA bind 文件。
* 共享状态：编译顺序决定类型、package、module 和 bind target 是否可解析。

§3.3  `ifv_bootstrap.sv`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：bootstrap 文件在 filelist 前段 include `common_defines.vh` 和 `eh2_pdef.vh`，并提供一个空 module，使 IFV 编译单元具备可 elaboration 的设计元素。

关键代码（`dv/formal/ifv_bootstrap.sv:L1-L15`）：

.. code-block:: text

   // IFV Bootstrap — includes macro/type-definition files before RTL compilation.
   // eh2_pdef.vh defines the eh2_param_t packed struct type at $unit scope,
   // which all subsequent RTL modules need for their `#(include "eh2_param.vh")` blocks.
   // DO NOT include eh2_param.vh here — parameter declarations at file scope
   // (outside a module) cause ncvlog parser errors (SVNOTY, EXPSMC) that
   // cascade to every downstream RTL module.
   `include "common_defines.vh"
   `include "eh2_pdef.vh"

   // Bootstrap module provides a home for any $unit-scope items that must
   // live inside a design element.  Currently it exists only so the
   // compilation unit contains at least one module (IFV sometimes requires
   // a top-level module during -elaborate, separate from the RTL top).
   module ifv_bootstrap ();
   endmodule

逐段解释：

* 第 1-L3 行：文件说明 `eh2_pdef.vh` 提供 `eh2_param_t` packed struct type，后续 RTL module 的 `#(include "eh2_param.vh")` 需要这些类型。
* 第 4-L6 行：注释明确禁止在该文件 include `eh2_param.vh`，因为 parameter declaration 在文件作用域会触发 `SVNOTY`、`EXPSMC` 并级联到后续 RTL。
* 第 7-L8 行：实际只 include `common_defines.vh` 和 `eh2_pdef.vh`。
* 第 10-L15 行：空 `ifv_bootstrap` module 让编译单元含有一个设计元素，满足 IFV 有时对 elaboration top 的要求。

接口关系：

* 被调用：`ifv_filelist.f` 第 14 行列入。
* 调用：`common_defines.vh` 和 `eh2_pdef.vh`。
* 共享状态：提供 `$unit` 作用域宏和类型，不实例化 DUT。

§4  `eh2_formal_top.sv` full-core harness
--------------------------------------------------------------------------------

§4.1  module 参数、时钟与 reset
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_formal_top.sv` 定义一个可实例化 `eh2_veer` 的 formal testbench。它创建形式环境下的时钟和 reset，并在 module 参数区 include `eh2_param.vh`。

关键代码（`dv/formal/eh2_formal_top.sv:L15-L36`）：

.. code-block:: text

   module eh2_formal_top
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   );

       // ====================================================================
       // Clock and reset generation (free-running for formal)
       // ====================================================================
       logic clk = 0;
       logic rst_l = 0;
       logic free_clk = 0;

       always #5 clk = ~clk;
       always #3 free_clk = ~free_clk;

       // Reset sequence
       initial begin
           rst_l = 0;

逐段解释：

* 第 15-L19 行：module 导入 `eh2_pkg::*`，并在参数列表中 include `eh2_param.vh`。这和 bootstrap 注释中的要求一致：parameter declaration 必须在 module 内。
* 第 24-L29 行：定义 `clk`、`rst_l`、`free_clk`，用两个 `always` block 生成形式 testbench 时钟。
* 第 31-L36 行：reset 初值为 0，等待 10 个 `posedge clk` 后置 1。

接口关系：

* 被调用：当前 `ifv_filelist.f` 未列入该文件；它是源码树中的 full-core harness。
* 调用：后续实例化 `eh2_veer`。
* 共享状态：产生 DUT 时钟、reset 和 formal-safe 输入。

§4.2  formal-safe 输入与 AXI tie-off
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：harness 对 debug、NMI、JTAG、core id、MPC 请求等输入给定静态值，并对 LSU/IFU/SB/DMA AXI 环境做简单 tie-off。

关键代码（`dv/formal/eh2_formal_top.sv:L38-L57`）：

.. code-block:: text

       // ====================================================================
       // DUT input signals — tied to inactive/formal-safe values
       // ====================================================================
       logic         dbg_rst_l     = 1'b1;  // Debug reset inactive
       logic [31:1]  rst_vec       = 31'h40000000;
       logic         nmi_int       = 1'b0;
       logic [31:1]  nmi_vec       = '0;
       logic [31:0]  extintsrc_req = '0;
       logic         jtag_tck      = 1'b0;
       logic         jtag_tms      = 1'b0;
       logic         jtag_tdi      = 1'b0;
       logic         jtag_trst_n   = 1'b1;
       logic         jtag_tdo;
       logic         i_cpu_halt_req = 1'b0;
       logic         i_cpu_run_req  = 1'b0;
       logic [31:4]  core_id       = '0;

逐段解释：

* 第 41-L44 行：debug reset inactive，reset vector 固定为 `31'h40000000`，NMI 关闭。
* 第 45-L50 行：外部中断清零，JTAG 输入固定，`jtag_tdo` 作为输出 wire 保留。
* 第 51-L57 行：CPU halt/run request、core id 和 MPC debug/reset request 给定静态值。

关键代码（`dv/formal/eh2_formal_top.sv:L129-L138`）：

.. code-block:: text

       // Memory slave: respond to reads with X (formal value), accept writes
       assign lsu_axi_awready = 1'b1;
       assign lsu_axi_wready  = 1'b1;
       assign lsu_axi_bvalid  = 1'b0;  // No write response initially
       assign lsu_axi_arready = 1'b1;
       assign lsu_axi_rvalid  = 1'b0;  // No read data initially
       assign lsu_axi_rdata   = '0;
       assign lsu_axi_rresp   = '0;
       assign lsu_axi_rlast   = 1'b0;
       assign lsu_axi_bresp   = '0;

逐段解释：

* 第 129-L133 行：LSU write/read address/data ready 信号被置 1，write response 和 read valid 初始为 0。
* 第 135-L138 行：read data、response、last 和 bresp 都绑到 0。
* IFU、SB、DMA 也在后续代码块采用类似 tie-off，其中 DMA valid/ready 方向按外部 master 输入方式处理。

接口关系：

* 被调用：full-core harness 内部。
* 调用：无外部函数。
* 共享状态：约束 DUT 输入和外部 AXI 环境，避免 unconstrained 输入直接污染 assertions。

§4.3  DUT 实例化与 trace 信号
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：harness 实例化 `eh2_veer`，连接 trace 输出、AXI 通道、debug/JTAG/interrupt 输入和大量未使用输出。

关键代码（`dv/formal/eh2_formal_top.sv:L201-L235`）：

.. code-block:: text

       // ====================================================================
       // DUT outputs
       // ====================================================================
       logic [63:0] trace_rv_i_insn_ip;
       logic [63:0] trace_rv_i_address_ip;
       logic [1:0]  trace_rv_i_valid_ip;
       logic [1:0]  trace_rv_i_exception_ip;
       logic [4:0]  trace_rv_i_ecause_ip;
       logic [1:0]  trace_rv_i_interrupt_ip;
       logic [31:0] trace_rv_i_tval_ip;
       logic [1:0]  trace_rv_i_rd_valid_ip;
       logic [9:0]  trace_rv_i_rd_addr_ip;
       logic [63:0] trace_rv_i_rd_wdata_ip;

       // ====================================================================
       // DUT Instantiation — eh2_veer (full core, no wrapper to minimize ports)
       // ====================================================================
       eh2_veer #() u_dut (

逐段解释：

* 第 201-L213 行：harness 声明 trace instruction、address、valid、exception、ecause、interrupt、tval、rd_valid、rd_addr 和 rd_wdata 信号。
* 第 215-L218 行：DUT 实例化直接使用 `eh2_veer`，注释说明没有 wrapper，以减少端口层。

关键代码（`dv/formal/eh2_formal_top.sv:L219-L235`）：

.. code-block:: text

           .clk                    (clk),
           .rst_l                  (rst_l),
           .dbg_rst_l              (rst_l),
           .rst_vec                (rst_vec),
           .nmi_int                (nmi_int),
           .nmi_vec                (nmi_vec),
           .jtag_id                (jtag_id),
           .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
           .trace_rv_i_address_ip  (trace_rv_i_address_ip),
           .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
           .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
           .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
           .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
           .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),
           .trace_rv_i_rd_valid_ip (trace_rv_i_rd_valid_ip),
           .trace_rv_i_rd_addr_ip  (trace_rv_i_rd_addr_ip),

逐段解释：

* 第 219-L225 行：DUT 时钟、reset、reset vector、NMI、JTAG id 连接到 harness 信号。
* 第 226-L235 行：trace 端口全部接到 harness 中声明的 trace signals，供后续 assertions 或调试使用。

接口关系：

* 被调用：formal harness elaboration 时实例化。
* 调用：`eh2_veer` RTL。
* 共享状态：DUT 输出被 assertions 和 cover 读取。

§4.4  top-level assertions 与 cover
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_formal_top.sv` 中直接写了一组 top-level assertions 和 cover，用于 reset、AXI、trace、debug 的基础检查。

关键代码（`dv/formal/eh2_formal_top.sv:L441-L471`）：

.. code-block:: text

       // --- Category 1: Reset / Clock (6 assertions) ---

       // P1: core_rst_l is derived from external rst_l (active low)
       a_core_rst_active_low: assert property (@(posedge clk)
           !rst_l |-> !core_rst_l
       );

       // P2: core_rst_l follows dbg_rst_l
       a_dbg_rst_to_core: assert property (@(posedge clk)
           !dbg_rst_l |-> !core_rst_l
       );

       // P3: active_l2clk known after reset sequence
       a_active_clk_known: assert property (@(posedge clk)
           $past(rst_l, 3) && $past(rst_l, 2) |-> !$isunknown(active_l2clk)
       );

逐段解释：

* 第 441-L446 行：reset active-low property 检查 `rst_l=0` 时 `core_rst_l=0`。
* 第 448-L451 行：debug reset 对 core reset 的影响通过 `a_dbg_rst_to_core` 检查。
* 第 453-L461 行：reset 后若前 2、3 个周期都已释放 reset，则 `active_l2clk` 和 `free_l2clk` 不能是 X。
* 第 463-L471 行：`dec_tlu_mhartstart` reset 值和 `core_rst_l` no-X 分别由 P5/P6 检查。

关键代码（`dv/formal/eh2_formal_top.sv:L594-L608`）：

.. code-block:: text

       // --- Category 10: Cover properties (3 covers) ---

       c_halt_handshake: cover property (@(posedge clk) disable iff (!rst_l)
           i_cpu_halt_req[0] ##1 o_cpu_halt_ack[0]
       );

       c_axi_write_burst: cover property (@(posedge clk) disable iff (!rst_l)
           lsu_axi_awvalid && lsu_axi_awready
           ##1 lsu_axi_wvalid && lsu_axi_wready && lsu_axi_wlast
       );

       c_axi_read_burst: cover property (@(posedge clk) disable iff (!rst_l)
           lsu_axi_arvalid && lsu_axi_arready
           ##[1:8] lsu_axi_rvalid && lsu_axi_rready && lsu_axi_rlast

逐段解释：

* 第 594-L598 行：`c_halt_handshake` 要求 reset 释放后出现 halt request 到 halt ack 的可达性。
* 第 600-L603 行：`c_axi_write_burst` 覆盖一次 LSU AXI write address handshake 后的 write data handshake。
* 第 605-L608 行：`c_axi_read_burst` 覆盖 read address handshake 到 1-8 周期后的 read data handshake。

接口关系：

* 被调用：该文件被 elaboration 时直接生效。
* 调用：SVA `assert property` 和 `cover property`。
* 共享状态：读取 harness 信号和 DUT 端口输出。

§5  `eh2_veer_sva.sv` bind 模块
--------------------------------------------------------------------------------

§5.1  bind 模块端口与 `.*` 策略
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`eh2_veer_sva.sv` 定义与 `eh2_veer` 顶层端口同名的 SVA module，文件末尾用 `bind eh2_veer ... (.*)` 自动连接，避免手写端口映射。

关键代码（`dv/formal/eh2_veer_sva.sv:L1-L13`）：

.. code-block:: text

   // ============================================================================
   // eh2_veer_sva.sv — Minimal SVA assertions bound to eh2_veer
   // RC5 (2026-05-09)
   //
   // Uses bind + .* auto-connect to avoid port-mapping issues.
   // Asserts on eh2_veer's own port names — no manual port list needed.
   // ============================================================================

   module eh2_veer_sva
     import eh2_pkg::*;
   #(
   `include "eh2_param.vh"
   ) (

逐段解释：

* 第 1-L6 行：文件注释说明这是绑定到 `eh2_veer` 的最小 SVA，采用 bind + `.*`，不写手工端口映射。
* 第 9-L13 行：SVA module 同样导入 `eh2_pkg::*`，并在 module 参数区 include `eh2_param.vh`。

关键代码（`dv/formal/eh2_veer_sva.sv:L384-L385`）：

.. code-block:: text

   // Bind to the top-level eh2_veer instance
   bind eh2_veer eh2_veer_sva u_eh2_veer_sva (.*);

逐段解释：

* 第 384-L385 行：绑定目标是 module 类型 `eh2_veer`。实例名为 `u_eh2_veer_sva`，端口连接使用 `.*`，因此 SVA module 的输入名必须和 `eh2_veer` 作用域中可见信号名匹配。

接口关系：

* 被调用：`ifv_filelist.f` 最后一行列入该文件，IFV elaboration 时执行 bind。
* 调用：SVA module 的 input 直接读取 `eh2_veer` 作用域信号。
* 共享状态：不驱动 RTL，只观察和约束。

§5.2  输入 assumptions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：bind 模块先给 free inputs 加 assumptions，使证明关注 functional mode 和稳定平台输入，而不是 unconstrained 环境。

关键代码（`dv/formal/eh2_veer_sva.sv:L114-L137`）：

.. code-block:: text

     // =========================================================================
     // INPUT ASSUMPTIONS — constrain free inputs for meaningful proofs
     // =========================================================================
     // Assume dbg_rst_l tracks rst_l (debug reset tied to main reset in formal)
     a_dbg_rst_tracks_rst: assume property (@(posedge clk)
       dbg_rst_l == rst_l
     );

     // The formal top models functional operation only; scan mode forces some
     // reset logic active-high and makes the functional reset properties invalid.
     a_no_scan_mode: assume property (@(posedge clk)
       scan_mode == 1'b0
     );

逐段解释：

* 第 114-L120 行：假设 `dbg_rst_l == rst_l`，让 debug reset 跟随主 reset。
* 第 122-L126 行：假设 `scan_mode == 0`，因为该 proof set 只模型 functional operation。
* 第 128-L137 行：reset asserted 时要求 `rst_vec` 和 `nmi_vec` 稳定，避免 reset-vector properties 在 unconstrained 平台输入上证明。

接口关系：

* 被调用：IFV proof engine 在 elaboration 后读取 assumptions。
* 调用：SVA `assume property`。
* 共享状态：约束 `dbg_rst_l`、`scan_mode`、`rst_vec`、`nmi_vec` 的可取行为。

§5.3  reset、AXI 和结构性 assertions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：bind 模块的 assertions 主要检查 reset/clock、AXI 顶层端口与内部信号连接、memory mutual exclusion、trace/debug 和 no-X 条件。

关键代码（`dv/formal/eh2_veer_sva.sv:L142-L170`）：

.. code-block:: text

     // P1: external reset must force core reset in functional mode
     a_core_rst_active_low: assert property (@(posedge clk)
       (!rst_l && !scan_mode) |-> !core_rst_l
     );

     // P2: with all reset sources deasserted, core_rst_l is released
     a_core_rst_from_reset: assert property (@(posedge clk)
       (rst_l && dbg_core_rst_l && !scan_mode) |-> core_rst_l
     );

     // P3: active_l2clk settles after reset
     a_active_clk_known: assert property (@(posedge clk)
       $past(rst_l, 3) && $past(rst_l, 2) |-> !$isunknown(active_l2clk)
     );

逐段解释：

* 第 142-L145 行：functional mode 下主 reset 拉低必须拉低 `core_rst_l`。
* 第 147-L150 行：主 reset 和 debug core reset 都释放且非 scan mode 时，`core_rst_l` 应释放。
* 第 152-L160 行：reset 释放若干周期后，`active_l2clk` 和 `free_l2clk` 不能为 X。
* 第 162-L170 行：thread 0 的 `dec_tlu_mhartstart[0]` 约束为 1，`core_rst_l` 不允许 X。

关键代码（`dv/formal/eh2_veer_sva.sv:L172-L207`）：

.. code-block:: text

     // =========================================================================
     // Category 2: LSU AXI Write Address Channel (4 assertions)
     // =========================================================================
     // Hookup checks: these top-level AXI pins must remain connected to the
     // submodule signals that generate them. This catches the original IFV
     // failures where checker-facing paths were mis-declared or disconnected.
     a_lsu_awvalid_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awvalid == lsu.bus_intf.lsu_axi_awvalid
     );

     a_lsu_awaddr_stable: assert property (@(posedge clk) disable iff (!rst_l)
       lsu_axi_awaddr == lsu.bus_intf.lsu_axi_awaddr

逐段解释：

* 第 172-L177 行：注释说明这些 AXI checks 是 hookup checks，用于捕获 checker-facing path 误声明或断连。
* 第 178-L184 行：`lsu_axi_awvalid` 和 `lsu_axi_awaddr` 必须等于 `lsu.bus_intf` 中对应内部信号。
* 第 186-L192 行：`AWLEN` 和 `AWSIZE` 的取值范围分别受 8-bit 和 3-bit AXI4 规格约束。
* 第 197-L207 行：write data channel 检查 `WVALID`、`WSTRB`、`WDATA` 是否和 `lsu.bus_intf` 内部信号一致。

关键代码（`dv/formal/eh2_veer_sva.sv:L282-L313`）：

.. code-block:: text

     a_dccm_wr_rd_mutex: assert property (@(posedge clk) disable iff (!rst_l)
       !(lsu.dccm_ctl.lsu_dccm_wren_spec_dc1 &&
         lsu.dccm_ctl.lsu_dccm_rden_dc1)
     );

     a_iccm_wr_rd_mutex: assert property (@(posedge clk) disable iff (!rst_l)
       (iccm_wren == ifu.mem_ctl.iccm_wren) &&
       (iccm_rden == ifu.mem_ctl.iccm_rden)
     );

     a_dccm_wr_addr_known: assert property (@(posedge clk) disable iff (!rst_l)
       dccm_wren |-> !$isunknown(dccm_wr_addr_lo)

逐段解释：

* 第 282-L285 行：DCCM 同周期不能同时出现 speculative write enable 和 read enable。
* 第 287-L290 行：ICCM 顶层 `wren/rden` 必须等于 IFU memory control 内部信号。
* 第 292-L298 行：DCCM/ICCM write enable 有效时，对应地址不能为 X。
* 第 303-L313 行：IFU AXI 地址不能为 X，且 `AWVALID` 与 `ARVALID` 不能同时为真。

接口关系：

* 被调用：IFV `assertion -add -specification` 添加这些 properties。
* 调用：RTL hierarchy path，如 `lsu.bus_intf`、`ifu.mem_ctl`、`dma_ctrl`、`dec.tlu`。
* 共享状态：只读 RTL 信号，不写 RTL。

§5.4  cover properties
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：cover properties 是 reachability smoke checks，验证某些状态在当前约束下不是完全不可达。

关键代码（`dv/formal/eh2_veer_sva.sv:L360-L380`）：

.. code-block:: text

     // =========================================================================
     // Category 13: Cover properties (4 covers)
     // =========================================================================
     // These coverpoints are formal smoke reachability checks. Full halt/run and
     // AXI burst reachability depends on a constrained platform/test program and
     // is tracked by UVM directed tests, not by this unconstrained IFV proof.
     c_halt_handshake: cover property (@(posedge clk)
       rst_l && !scan_mode && !$isunknown(o_cpu_halt_ack[0])
     );

     c_run_handshake: cover property (@(posedge clk)
       rst_l && !scan_mode && !$isunknown(o_cpu_run_ack[0])

逐段解释：

* 第 360-L365 行：源码注释说明 cover 是 formal smoke reachability；完整 halt/run 和 AXI burst reachability 依赖受约束的平台或测试程序，不由这个 unconstrained IFV proof 负责。
* 第 366-L372 行：halt/run cover 检查 reset 释放且非 scan mode 下 ack 信号不是 X。
* 第 374-L380 行：AXI write/read cover 检查 LSU AXI valid/ready 相关信号不是 X。

接口关系：

* 被调用：IFV proof 添加 cover properties。
* 调用：SVA `cover property`。
* 共享状态：用于 coverage/reachability 报告，不改变 proof constraints。

§6  IFV Tcl 脚本
--------------------------------------------------------------------------------

§6.1  `ifv_prove.tcl`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：主证明脚本使用 IFV 15.20 支持的 legacy FormalVerifier 命令：加时钟、加入 assertions、prove、打印 summary、退出。

关键代码（`dv/formal/scripts/ifv_prove.tcl:L1-L13`）：

.. code-block:: tcl

   # IFV 15.20 proof script for EH2.
   #
   # This intentionally uses the legacy FormalVerifier shell commands supported by
   # INCISIVE152. Newer check_formal/report_cex/write_vcd commands are not
   # available in this installed tool version.

   puts "IFV: EH2 formal proof start"
   clock -add clk -initial 0 -period 2 -width 1
   assertion -add -specification
   prove
   assertion -summary
   puts "IFV: EH2 formal proof complete"
   exit

逐段解释：

* 第 1-L5 行：注释限定命令集：使用 INCISIVE152 支持的 legacy FormalVerifier shell commands，不使用 `check_formal`、`report_cex`、`write_vcd`。
* 第 7-L8 行：打印开始信息，并添加 `clk`，初始值 0，period 2，width 1。
* 第 9-L11 行：`assertion -add -specification` 添加规格中的 assertions；`prove` 执行证明；`assertion -summary` 输出 summary。
* 第 12-L13 行：打印完成信息并退出。

接口关系：

* 被调用：`Makefile:ifv` 的 `$(IFV) -r +tcl+scripts/ifv_prove.tcl`。
* 调用：IFV shell 命令。
* 共享状态：读取当前 elaborated design 和 SVA，输出 `build/ifv_run.log`。

§6.2  `ifv_cex_dump.tcl`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：诊断脚本在 IFV 15.20 不支持 `report_cex/write_vcd` 的条件下，对一组 property 逐个执行 `assertion -show ... -verbose -list`，并生成文本标记文件。

关键代码（`dv/formal/scripts/ifv_cex_dump.tcl:L1-L12`）：

.. code-block:: tcl

   # IFV 15.20 diagnostic dump for the original RC5 24 failing properties.
   #
   # The installed INCISIVE152 FormalVerifier does not implement report_cex,
   # write_vcd, set_active, or get_status. The supported replacement is
   # assertion -show <property> -verbose -list. This script emits one verbose block
   # per property and creates a build/cex_<property>.txt file documenting the
   # diagnostic source for downstream review.

   clock -add clk -initial 0 -period 2 -width 1
   assertion -add -specification
   prove

逐段解释：

* 第 1-L7 行：注释说明该脚本用于 RC5 原始 24 个 failing properties 的诊断；由于 IFV 15.20 缺少 `report_cex/write_vcd/set_active/get_status`，改用 `assertion -show`。
* 第 9-L11 行：脚本和主 prove 一样先添加 clock、加入 assertions、运行 prove。

关键代码（`dv/formal/scripts/ifv_cex_dump.tcl:L13-L38`）：

.. code-block:: tcl

   set props {
     eh2_veer.u_eh2_veer_sva.a_core_rst_active_low
     eh2_veer.u_eh2_veer_sva.a_core_rst_from_reset
     eh2_veer.u_eh2_veer_sva.a_dccm_wr_rd_mutex
     eh2_veer.u_eh2_veer_sva.a_debug_halt_track
     eh2_veer.u_eh2_veer_sva.a_dma_arvalid_stable
     eh2_veer.u_eh2_veer_sva.a_dma_awvalid_stable
     eh2_veer.u_eh2_veer_sva.a_iccm_wr_rd_mutex
     eh2_veer.u_eh2_veer_sva.a_ifu_arvalid_stable
     eh2_veer.u_eh2_veer_sva.a_ifu_awvalid_stable
     eh2_veer.u_eh2_veer_sva.a_ifu_not_both_rw
     eh2_veer.u_eh2_veer_sva.a_ifu_rvalid_accepted
     eh2_veer.u_eh2_veer_sva.a_lsu_araddr_stable
     eh2_veer.u_eh2_veer_sva.a_lsu_arvalid_stable

逐段解释：

* 第 13-L38 行：`props` 列表逐条写出待诊断 property 的层级路径，路径形式是 `eh2_veer.u_eh2_veer_sva.<property>`。
* 列表中的 property 覆盖 reset、DCCM/ICCM、debug、DMA、IFU、LSU、NMI vector、reset vector、trace valid address 等。

关键代码（`dv/formal/scripts/ifv_cex_dump.tcl:L40-L55`）：

.. code-block:: tcl

   foreach prop $props {
     set fields [split $prop "."]
     set short [lindex $fields [expr {[llength $fields] - 1}]]
     set out "build/cex_${short}.txt"
     set fh [open $out "w"]
     puts $fh "Property: $prop"
     puts $fh "Diagnostic command: assertion -show $prop -verbose -list"
     puts $fh "Note: IFV 15.20 lacks report_cex/write_vcd; see build/ifv_cex_run.log for the verbose status block."
     close $fh
     puts "=== CEX_BEGIN $short ==="
     assertion -show $prop -verbose -list
     puts "=== CEX_END $short ==="
   }

   assertion -summary
   exit

逐段解释：

* 第 40-L43 行：对每个 property 拆分层级路径，取最后一段作为短名，并构造 `build/cex_<short>.txt`。
* 第 44-L48 行：写入 property 全路径、诊断命令和 IFV 15.20 限制说明。
* 第 49-L51 行：在日志中打印 `CEX_BEGIN/CEX_END` 标记，并执行 `assertion -show <prop> -verbose -list`。
* 第 54-L55 行：最后输出 assertion summary 并退出。

接口关系：

* 被调用：`Makefile:ifv_cex`。
* 调用：IFV `assertion -show` 和文件写入命令。
* 共享状态：输出 `build/cex_*.txt` 和 `build/ifv_cex_run.log`。

§7  Sail 辅助脚本
--------------------------------------------------------------------------------

§7.1  `sail_setup.sh`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该脚本尝试 clone 并构建 `sail-riscv` RV32 C emulator；若网络、git、opam 或构建失败，则退出 0 并保留 built-in checks 路径。

关键代码（`dv/formal/spec/sail_setup.sh:L21-L38`）：

.. code-block:: bash

   set -euo pipefail

   SAIL_REPO="https://github.com/riscv/sail-riscv"
   SAIL_DIR="./sail-riscv"
   SAIL_BIN="./riscv_sim_RV32"

   echo "=== EH2 Formal: Sail-RISCV Setup ==="
   echo ""

   # Option 1: Clone and build (full integration)
   if [ ! -d "$SAIL_DIR" ]; then
       echo "[STEP 1/3] Cloning sail-riscv..."
       git clone --depth=1 "$SAIL_REPO" "$SAIL_DIR" || {
           echo "[SKIP] Unable to clone sail-riscv (no network or git unavailable)"
           echo "[INFO] Formal bridge will use built-in checks from sail_bridge.sv"
           echo "[INFO] No further action needed — architectural invariants are self-contained."
           exit 0

逐段解释：

* 第 21 行：脚本启用 `set -euo pipefail`，普通命令失败会中断。
* 第 23-L25 行：定义 upstream repo、clone 目录和最终 symlink binary 路径。
* 第 31-L38 行：如果本地没有 `sail-riscv`，尝试 shallow clone；clone 失败时打印 skip/info 并 `exit 0`，不会把 Sail 缺失变成 formal flow 失败。

关键代码（`dv/formal/spec/sail_setup.sh:L43-L67`）：

.. code-block:: bash

   echo "[STEP 2/3] Installing sail-riscv build dependencies..."
   # Dependencies: OCaml, opam, sail, z3
   command -v opam >/dev/null 2>&1 || {
       echo "[SKIP] opam not found. Cannot build sail."
       echo "[INFO] Built-in checks remain active. Install opam for full replay."
       exit 0
   }

   (cd "$SAIL_DIR" && opam install -y sail) || true

   echo "[STEP 3/3] Building sail-riscv c_emulator (RV32)..."
   (cd "$SAIL_DIR" && make c_emulator 2>&1 | tail -5) || {
       echo "[SKIP] Build failed. Dependencies may be incomplete."
       echo "[INFO] Built-in checks remain active. See sail_bridge.sv."
       exit 0

逐段解释：

* 第 43-L49 行：检查 `opam`。缺少 `opam` 时同样 `exit 0`，保留内建检查。
* 第 51 行：在 `sail-riscv` 目录执行 `opam install -y sail`，失败也被 `|| true` 吞掉。
* 第 53-L58 行：执行 `make c_emulator`，只显示最后 5 行；构建失败时打印 skip/info 并退出 0。
* 第 60-L67 行：如果生成 `c_emulator/riscv_sim_RV32`，则 symlink 到 `./riscv_sim_RV32`；否则只打印信息。

接口关系：

* 被调用：人工运行 `cd dv/formal/spec && bash sail_setup.sh`。
* 调用：`git clone`、`opam install`、`make c_emulator`、`ln -sf`。
* 共享状态：创建 `dv/formal/spec/sail-riscv/` 和 `dv/formal/spec/riscv_sim_RV32` symlink。

§7.2  `sail_trace_check.py` 解码 helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：Python checker 定义 RV32 指令编码 helper 和 `SailChecker` 状态，用于对 EH2 trace 与 Sail 模型的架构状态进行离线比较。

关键代码（`dv/formal/spec/sail_trace_check.py:L20-L67`）：

.. code-block:: python

   import argparse
   import subprocess
   import sys
   import os
   import struct

   # ---------------------------------------------------------------------------
   # RISC-V instruction encoding helpers (RV32IMCB)
   # ---------------------------------------------------------------------------
   OPCODE_MASK    = 0x7F
   FUNCT3_MASK    = 0x7000
   FUNCT7_MASK    = 0xFE000000
   RD_MASK        = 0xF80
   RS1_MASK       = 0xF8000

   OP_LUI         = 0x37

逐段解释：

* 第 20-L24 行：脚本导入 CLI、subprocess、sys、os 和 struct。当前源码中 `subprocess` 与 `struct` 被导入，但主路径没有实际调用外部 Sail binary。
* 第 29-L34 行：定义 opcode、funct、rd、rs1 mask。
* 第 35-L45 行：定义 LUI、AUIPC、JAL、JALR、BRANCH、LOAD、STORE、ALU、FENCE、SYSTEM opcode 常量。
* 第 47-L54 行：定义 SYSTEM funct3 常量。
* 第 56-L64 行：`decode_rd()`、`decode_opcode()`、`decode_funct3()` 从指令整数中取字段。
* 第 66-L67 行：`SailChecker` 类封装 trace replay 和 divergence detection。

接口关系：

* 被调用：`main()` 构造 `SailChecker`。
* 调用：纯 Python 位运算 helper。
* 共享状态：helper 无状态；`SailChecker` 保存 GPR、PC 和 `mstatus`。

§7.3  `SailChecker.step_instruction()` 与 divergence 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`step_instruction()` 在当前源码中实现了内建的简化架构语义，覆盖 LUI、AUIPC、JAL、JALR 和默认 PC+4；`check_against_eh2_trace()` 比对 PC、x0 写和 GPR 写回。

关键代码（`dv/formal/spec/sail_trace_check.py:L78-L130`，节选）：

.. code-block:: python

       def __init__(self, sail_bin):
           self.sail_bin = sail_bin
           self.gpr = [0] * 32
           self.pc = 0
           self.mstatus = 0

       def reset(self, reset_vector=0x00000000):
           """Reset sail model to match EH2 reset state."""
           self.gpr = [0] * 32
           self.pc = reset_vector
           self.mstatus = 0

       def step_instruction(self, instr):
           """Execute one instruction through sail and return (next_pc, gpr_writes)."""
           # In production, this would invoke the sail c_emulator via subprocess.
           # For the formal bridge, we simulate the architectural semantics:

逐段解释：

* 第 78-L83 行：对象保存 Sail binary 路径、32 个 GPR、PC 和 `mstatus`。
* 第 84-L89 行：`reset()` 清空 GPR，把 PC 设为 reset vector，把 `mstatus` 清零。
* 第 90-L96 行：`step_instruction()` 当前源码没有调用 `subprocess`，而是用 Python 内建语义解释部分指令。
* 第 98-L119 行：LUI/AUIPC/JAL/JALR 分别更新 GPR write 和 PC。
* 第 121-L128 行：BRANCH 当前 `pass`，ALU_IMM、ALU 和 default 路径把 PC 加 4。

关键代码（`dv/formal/spec/sail_trace_check.py:L132-L162`）：

.. code-block:: python

       def check_against_eh2_trace(self, eh2_pc, eh2_rd, eh2_wen, eh2_wdata, eh2_instr):
           """Compare EH2 trace entry against sail execution."""
           sail_next_pc, sail_gpr_write = self.step_instruction(eh2_instr)

           divergences = []

           # Check 1: PC match
           if eh2_pc != self.pc:
               divergences.append(
                   f"PC divergence: EH2={eh2_pc:#010x} SAIL={self.pc:#010x}"
               )

           # Check 2: x0 writes
           if eh2_wen and eh2_rd == 0 and eh2_wdata != 0:
               divergences.append(

逐段解释：

* 第 132-L135 行：函数先对 EH2 指令执行一次内建 step，返回 Sail next PC 和可能的 GPR 写回。
* 第 136-L142 行：PC 不一致时追加 `PC divergence` 字符串。
* 第 144-L148 行：如果 EH2 对 x0 写非零值，追加 x0 writeback violation。
* 第 150-L160 行：当 EH2 和 Sail 都有 GPR 写回时，比对 rd 和写回数据。
* 第 162 行：返回 divergences 列表，调用方可据此统计失败数。

接口关系：

* 被调用：离线 trace replay 时可逐条调用；当前 `main()` 没有实际解析 CSV 循环。
* 调用：`step_instruction()`。
* 共享状态：更新并读取 `self.pc`、`self.gpr`。

§7.4  CLI 和降级路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`main()` 解析 trace、Sail binary 和 max-instructions 参数；缺少 Sail binary 或 trace 文件时打印信息，但仍执行内建检查路径并按 divergence 计数返回。

关键代码（`dv/formal/spec/sail_trace_check.py:L165-L190`）：

.. code-block:: python

   def main():
       parser = argparse.ArgumentParser(
           description="EH2-to-Sail-RISCV trace divergence checker"
       )
       parser.add_argument("--trace", required=True, help="EH2 trace CSV file")
       parser.add_argument("--sail", default="./riscv_sim_RV32",
                           help="Path to sail-riscv c_emulator")
       parser.add_argument("--max-instructions", type=int, default=10000,
                           help="Maximum instructions to check")
       args = parser.parse_args()

       if not os.path.exists(args.sail):
           print(f"[WARN] sail-riscv binary not found at {args.sail}")
           print("[INFO] Install sail-riscv: git clone https://github.com/riscv/sail-riscv")
           print("[INFO] Build: cd sail-riscv && make c_emulator")

逐段解释：

* 第 165-L174 行：CLI 需要 `--trace`，`--sail` 默认 `./riscv_sim_RV32`，`--max-instructions` 默认 10000。
* 第 176-L182 行：如果 Sail binary 不存在，脚本只打印 warn/info，并继续运行内建 checks 路径。
* 第 184-L190 行：构造 `SailChecker` 并 reset，然后打印 trace divergence check banner。

关键代码（`dv/formal/spec/sail_trace_check.py:L192-L213`）：

.. code-block:: python

       if os.path.exists(args.trace):
           # In production: parse EH2 trace CSV and replay through sail
           # Format: pc,rd,wen,wdata,instr (one instruction per line)
           print(f"[INFO] Trace file: {args.trace}")
           print(f"[INFO] Max instructions: {args.max_instructions}")
       else:
           print(f"[WARN] Trace file not found: {args.trace}")
           print("[INFO] Built-in architectural checks active (sail_bridge.sv):")
           print("  - p_sail_regfile_x0_stability: x0 hardwired to zero")
           print("  - p_sail_exception_cause_range: cause in privileged spec range")
           print("  - p_sail_m_mode_always: M-mode only (EH2 has no U/S)")

       if total_divergences == 0:
           print("[PASS] No sail-riscv architectural divergences detected.")
       else:

逐段解释：

* 第 192-L196 行：trace 文件存在时，当前源码只打印 trace path 和 max instruction 数；注释说明生产路径会解析 `pc,rd,wen,wdata,instr` CSV。
* 第 197-L202 行：trace 文件不存在时，打印内建 architectural checks 列表，包括 x0 stability、exception cause range 和 M-mode only。
* 第 204-L209 行：根据 `total_divergences` 返回 0 或 1。当前源码没有增加该计数的循环，所以初始值 0 会走 pass 输出。
* 第 212-L213 行：脚本入口调用 `sys.exit(main())`。

接口关系：

* 被调用：人工或 CI 可运行 `python3 sail_trace_check.py --trace <csv> --sail ./riscv_sim_RV32`。
* 调用：`argparse`、`os.path.exists()`、`SailChecker`。
* 共享状态：读取文件存在性，不修改 repo 源文件。

§8  执行顺序与故障定位
--------------------------------------------------------------------------------

§8.1  主证明路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：主路径由 Makefile 驱动，两次 IFV 调用分别负责 compile/elaboration 和 prove runtime。

.. code-block:: text

   make -C dv/formal ifv
      │
      ├─ mkdir -p build
      ├─ ifv -f ifv_filelist.f +top+eh2_veer +loop_unroll_size+2048 -c
      │    ├─ read ifv_bootstrap.sv
      │    ├─ read RTL design files
      │    └─ read eh2_veer_sva.sv
      │
      ├─ ifv -r +tcl+scripts/ifv_prove.tcl
      │    ├─ clock -add clk
      │    ├─ assertion -add -specification
      │    ├─ prove
      │    └─ assertion -summary
      │
      └─ grep "Assertion Summary" build/ifv_run.log

逐段解释：

* 第一段 IFV 调用由 `Makefile:L22` 给出，负责读取 `ifv_filelist.f` 并 compile/elaborate `eh2_veer`。
* 第二段 IFV 调用由 `Makefile:L23` 给出，负责运行 `ifv_prove.tcl`。
* summary 提取由 `Makefile:L24-L25` 给出，不解析结构化 JSON，只从日志里截取文本块。

接口关系：

* 被调用：用户或上层脚本。
* 调用：Makefile、filelist、Tcl。
* 共享状态：`build/` 中的 IFV 日志是后续 sign-off 或人工检查的输入。

§8.2  CEX 诊断路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：诊断路径不改变 property 本身，只对指定 property 输出 IFV verbose block，并写入每条 property 对应的文本文件。

.. code-block:: text

   make -C dv/formal ifv_cex
      │
      ├─ ifv -r +tcl+scripts/ifv_cex_dump.tcl
      │    ├─ clock -add clk
      │    ├─ assertion -add -specification
      │    ├─ prove
      │    ├─ foreach prop in props
      │    │    ├─ build/cex_<property>.txt
      │    │    └─ assertion -show <property> -verbose -list
      │    └─ assertion -summary
      │
      └─ count build/cex_*.txt

逐段解释：

* property 列表来自 `ifv_cex_dump.tcl:L13-L38`。
* 文件写入逻辑来自 `ifv_cex_dump.tcl:L40-L48`。
* verbose status block 来自 `ifv_cex_dump.tcl:L49-L51`。

接口关系：

* 被调用：失败诊断时使用。
* 调用：IFV assertion query。
* 共享状态：`build/cex_*.txt` 记录 property 和诊断命令，详细 verbose block 在 `build/ifv_cex_run.log`。

§9  参考资料
--------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0012` — Formal verification strategy。
* :ref:`adr-0014` — Formal real runs。

关联章节：

* :ref:`formal_flow` — 形式验证执行流程。
* :doc:`formal_properties` — SVA property 源码说明。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/formal/Makefile`
* :file:`/home/host/eh2-veri/dv/formal/ifv_filelist.f`
* :file:`/home/host/eh2-veri/dv/formal/ifv_bootstrap.sv`
* :file:`/home/host/eh2-veri/dv/formal/eh2_formal_top.sv`
* :file:`/home/host/eh2-veri/dv/formal/eh2_veer_sva.sv`
* :file:`/home/host/eh2-veri/dv/formal/scripts/ifv_prove.tcl`
* :file:`/home/host/eh2-veri/dv/formal/scripts/ifv_cex_dump.tcl`
* :file:`/home/host/eh2-veri/dv/formal/spec/sail_setup.sh`
* :file:`/home/host/eh2-veri/dv/formal/spec/sail_trace_check.py`

§10  v2-9 Formal 资产审计
--------------------------------------------------------------------------------

v2-9 对 ``dv/formal`` 做一次文件级审计，目的是把 IFV、Symbiyosys、Sail 辅助脚本和
known-fails 证据放在同一页。当前 full sign-off 的 formal stage 仍以 IFV
``46/46`` PASS 为准；``*.sby`` 是开源可移植证明入口，不能把 bounded depth 结果直接写成
release gate。

.. list-table::
   :header-rows: 1
   :widths: 28 30 42

   * - 资产
     - 入口
     - 审计结论
   * - ``properties/eh2_dbg_assert.sv`` 等 7 个 property 文件
     - :ref:`appendix_c_tools/formal_properties`
     - SVA 源码解释放在 property 字典；本章只解释它们如何被 filelist/Tcl 调度。
   * - ``scripts/ifv_prove.tcl``
     - §6.1
     - 主证明脚本，负责 clock、assertion load、prove 和 summary。
   * - ``scripts/ifv_cex_dump.tcl``
     - §6.2
     - 诊断脚本，负责逐 property 输出 verbose block。
   * - ``scripts/sby_dbg.sby`` / ``sby_dec.sby`` / ``sby_pic.sby`` / ``sby_pmp.sby``
     - 本节
     - Symbiyosys bounded proof 入口，服务 portability/debug，不替代 IFV sign-off。
   * - ``known_fails.md``
     - 本节
     - 保存历史 CEX 分类、修复路径和 IFV 15.20 工具限制边界。

关键代码（``dv/formal/scripts/sby_pmp.sby:L1-L18``）：

.. literalinclude:: ../../../../dv/formal/scripts/sby_pmp.sby
   :language: text
   :lines: 1-18
   :caption: /home/host/eh2-veri/dv/formal/scripts/sby_pmp.sby:L1-L18

逐段解释：

* 第 L1-L4 行：文件头说明这是 PMP/LSU address check 的 Symbiyosys 配置，运行命令为
  ``sby -f scripts/sby_pmp.sby``。
* 第 L6-L13 行：只定义 ``prove`` task，mode 为 ``prove``，depth 为 25，engine 是
  ``smtbmc z3``。
* 第 L15-L18 行：script 阶段先定义 ``FORMAL``，再读取 EH2 include/lib 和
  ``eh2_lsu_addrcheck.sv``。

关键代码（``dv/formal/known_fails.md:L1-L12``）：

.. literalinclude:: ../../../../dv/formal/known_fails.md
   :language: text
   :lines: 1-12
   :caption: /home/host/eh2-veri/dv/formal/known_fails.md:L1-L12

逐段解释：

* 第 L1-L4 行：记录 RC5 formal diagnostic 的 baseline 和当前修复后状态，说明历史失败数
  与当前 sign-off pass 数不是同一口径。
* 第 L5-L12 行：第一个条目把 ``a_core_rst_active_low`` 的 CEX 归类为 property bug，
  并指出修复方式是用 ``!scan_mode`` gate functional reset。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从脚本、Makefile 或配置文件中找到本页讲到的真实入口。

.. code-block:: bash

   rg -n "def main|argparse|subprocess|class |target:" dv/uvm/core_eh2/scripts scripts Makefile | head -80
   rg -n "cover.cfg|cov_full_nc.ccf|rtl_simulation.yaml|eh2_configs.yaml" docs/sphinx_cn/source/appendix_e_config docs/sphinx_cn/source/appendix_f_scripts

**进阶题**：检查工具职责是否按 VCS/NC/Formal/Syn/Lint 分开，而不是混成一个流程。

.. code-block:: bash

   rg -n "urg|imc|vcs|irun|xrun|dc_shell|fm_shell|verilator|verible" docs/sphinx_cn/source/appendix_c_tools docs/sphinx_cn/source/appendix_f_scripts | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？
