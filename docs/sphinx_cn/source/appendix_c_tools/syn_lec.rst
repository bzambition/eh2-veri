.. _appendix_c_tools_syn_lec:
.. _appendix_c_tools/syn_lec:

LEC 脚本源码字典
================

:status: draft
:source: syn/scripts/lec_blocklevel/lec_common.tcl
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  本章导读
--------------------------------------------------------------------------------------------------------------------------------------------

本章逐段说明 EH2 当前主线中与逻辑等价性检查（Logical Equivalence
Checking，LEC）相关的脚本。这里的 LEC 指 RTL 与综合后 netlist
之间的 Formality 等价性检查，不包含 Yosys 形式化或 IFV assertion
证明。2026-05-19 VCS 主线 sign-off 的 LEC 结果来自 block-level
Formality 流程，汇总文件为 :file:`syn/build/lec_summary.txt`。

本章覆盖 4 类源码：

* 顶层 Makefile 入口：:file:`Makefile` 与 :file:`syn/Makefile`。
* 早期 top-level Formality 尝试：:file:`syn/scripts/lec_run.tcl`、
  :file:`syn/scripts/lec_svf.tcl`、:file:`syn/scripts/lec_p0a.tcl`、
  :file:`syn/scripts/lec_rc4_fix.tcl` 等。
* block-level Formality 脚本：:file:`syn/scripts/lec_blocklevel/*.tcl`。
* LEC 汇总器：:file:`syn/scripts/lec_summary.py`。

本章不把 build 目录中的报告当作可编辑源文件。报告只作为结果证据引用，
例如当前主线的 9 个模块、``31635`` passing compare points、``0`` failing
compare points、``0`` unverified compare points，均来自
:file:`syn/build/lec_summary.txt` 与 sign-off 文档。对 ADR 的引用只使用
已存在的 :ref:`adr-0019` 和 :ref:`adr-0020`。

§2  调用入口：顶层 make 到 block-level LEC
--------------------------------------------------------------------------------------------------------------------------------------------

职责：顶层 :file:`Makefile` 只负责把用户命令转交给 :file:`syn/Makefile`；
真正的 block-level DC 综合、Formality 运行和 summary 生成都在
:file:`syn/Makefile` 中完成。

§2.1  顶层 LEC 变量与 sign-off 参数传递
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``Makefile:L111-L113, L448-L449``）：

.. code-block:: text

   LEC_KNOWN_LIMITED ?= 0
   LEC_BLOCKLEVEL ?= 0
   LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt
   ...
             $(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,) \
             $(if $(filter 1,$(LEC_BLOCKLEVEL)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),) \

逐段解释：

* 第 111 行：``LEC_KNOWN_LIMITED`` 是 sign-off 脚本的显式开关。它不会自动豁免
  LEC，只在调用者把变量设为 ``1`` 时向 Python 层传入
  ``--lec-known-limited``。
* 第 112~113 行：``LEC_BLOCKLEVEL`` 和 ``LEC_SUMMARY_PATH`` 共同决定
  sign-off 是否读取 block-level LEC summary。默认路径固定为
  :file:`syn/build/lec_summary.txt`。
* 第 448~449 行：Makefile 通过条件展开把变量翻译成
  :file:`dv/uvm/core_eh2/scripts/signoff.py` 的命令行参数。这里没有解析
  LEC 报告，只做参数转发。

接口关系：

* 被调用：用户运行 ``make signoff`` 或相关 sign-off target 时读取这些变量。
* 调用：最终调用 :file:`dv/uvm/core_eh2/scripts/signoff.py`。
* 共享状态：读取 Make 变量 ``LEC_KNOWN_LIMITED``、``LEC_BLOCKLEVEL``、
  ``LEC_SUMMARY_PATH``。

§2.2  顶层 target 转发
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``Makefile:L574-L589``）：

.. code-block:: text

   # Synthesis and LEC
   # -----------------------------------------------------------------------
   synth:
           +@$(MAKE) -C syn syn-full

   syn_yosys:
           +@$(MAKE) -C syn syn-yosys

   syn_dc:
           +@$(MAKE) -C syn syn-dc

   lec:
           +@$(MAKE) -C syn lec

   block_lec:
           +@$(MAKE) -C syn block_lec

逐段解释：

* 第 576~577 行：``synth`` 转入 :file:`syn/Makefile` 的 ``syn-full``，
  这是综合加 LEC 的组合入口。
* 第 579~583 行：``syn_yosys`` 与 ``syn_dc`` 分别转发到开源综合和
  Design Compiler 综合入口。它们不是本章的主路径，但为 LEC 提供 netlist
  来源。
* 第 585~589 行：``lec`` 与 ``block_lec`` 都通过 ``$(MAKE) -C syn`` 进入
  :file:`syn/Makefile`。当前 sign-off 使用的是 ``block_lec`` 产出的
  block-level summary。

接口关系：

* 被调用：命令行用户、CI 或 sign-off wrapper。
* 调用：:file:`syn/Makefile` 中同名 target。
* 共享状态：继承 Make 环境变量，例如 ``BLOCK_LEC_RESYNTH``。

§2.3  ``syn/Makefile:block_lec`` — R3-C 主流程
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/Makefile:L99-L137``）：

.. code-block:: text

   block_lec:
           @echo "=== R3-C Block-level LEC ==="
           @mkdir -p $(BLOCK_LEC_RPT_DIR) $(BLOCK_LEC_RPT_DIR)/synth \
             $(BLOCK_LEC_DC_RUN_DIR) $(BLOCK_LEC_FM_RUN_DIR)
           @if ! command -v dc_shell >/dev/null 2>&1; then \
                   echo "ERROR: dc_shell not found."; \
                   exit 1; \
           fi
           @if ! command -v fm_shell >/dev/null 2>&1; then \
                   echo "ERROR: fm_shell not found."; \
                   exit 1; \
           fi
           @for top in $(BLOCK_LEC_TOPS); do \
                   if [ "$(BLOCK_LEC_RESYNTH)" = "1" ] || \
                      [ ! -f "$(BLOCK_LEC_RPT_DIR)/synth/$${top}.v" ]; then \
                           echo "  DC synth: $${top}"; \
                           extra_env=""; \

逐段解释：

* 第 100~103 行：target 首先创建 block-level 报告目录、standalone block
  netlist 目录、DC run 目录和 Formality run 目录。这些都是 generated
  artifact，文档任务不得修改。
* 第 104~111 行：脚本显式检查 ``dc_shell`` 与 ``fm_shell`` 是否在
  ``PATH`` 中。如果任一工具缺失，target 直接退出，避免生成不完整报告。
* 第 112~116 行：第一个循环遍历 ``BLOCK_LEC_TOPS``。当
  ``BLOCK_LEC_RESYNTH=1`` 或 block netlist 不存在时，才重新运行 DC。
  这解释了为什么已有 :file:`syn/build/lec_blocklevel/synth/*.v` 时可以复用
  旧 netlist。

关键代码（``syn/Makefile:L117-L137``）：

.. code-block:: text

                           if [ "$${top}" = "eh2_ifu" ]; then \
                                   extra_env="R3C_SIMPLE_COMPILE=1"; \
                           fi; \
                           mkdir -p $(BLOCK_LEC_DC_RUN_DIR)/$${top}; \
                           (cd $(BLOCK_LEC_DC_RUN_DIR)/$${top} && \
                             env R3C_BLOCK_TOP=$${top} $${extra_env} dc_shell -f $(SYN_DIR)/scripts/dc_synth_block.tcl \
                               > $(BLOCK_LEC_RPT_DIR)/dc_$${top}.log 2>&1); \
                   else \
                           echo "  DC synth: $${top} (reuse existing netlist)"; \
                   fi; \
           done
           @for label in $(BLOCK_LEC_LABELS); do \
                   echo "  Formality LEC: $${label}"; \
                   mkdir -p $(BLOCK_LEC_FM_RUN_DIR)/$${label}; \
                   (cd $(BLOCK_LEC_FM_RUN_DIR)/$${label} && \
                     env R3C_FM_RUN_DIR=$(BLOCK_LEC_FM_RUN_DIR)/$${label} \
                     fm_shell -f $(SYN_DIR)/scripts/lec_blocklevel/lec_$${label}.tcl \
                       > $(BLOCK_LEC_RPT_DIR)/lec_$${label}.log 2>&1); \
           done
           @python3 $(SYN_DIR)/scripts/lec_summary.py

逐段解释：

* 第 117~119 行：``eh2_ifu`` 额外设置 ``R3C_SIMPLE_COMPILE=1``。这个变量传给
  :file:`syn/scripts/dc_synth_block.tcl`，说明 IFU block 的 DC 综合路径与普通
  block 有差异。
* 第 120~123 行：每个 block 在独立 DC run 目录下调用
  :file:`syn/scripts/dc_synth_block.tcl`，并把 log 写到
  :file:`syn/build/lec_blocklevel/dc_<top>.log`。
* 第 128~135 行：第二个循环遍历 ``BLOCK_LEC_LABELS``，为每个 label 建立独立
  Formality run 目录，并设置 ``R3C_FM_RUN_DIR``。随后执行
  :file:`syn/scripts/lec_blocklevel/lec_<label>.tcl`。
* 第 136 行：所有 block Formality 运行结束后，Python 汇总器读取
  :file:`syn/build/lec_blocklevel/lec_*.rpt` 并生成
  :file:`syn/build/lec_summary.txt`。

接口关系：

* 被调用：顶层 ``make block_lec`` 或 ``make -C syn block_lec``。
* 调用：``dc_shell``、``fm_shell``、:file:`syn/scripts/lec_summary.py`。
* 共享状态：``BLOCK_LEC_TOPS``、``BLOCK_LEC_LABELS``、
  ``BLOCK_LEC_RESYNTH``、``R3C_FM_RUN_DIR``。

§3  早期 top-level Formality 脚本族
--------------------------------------------------------------------------------------------------------------------------------------------

职责：这些脚本以 ``eh2_veer`` 为 top，在整个设计层面比较
:file:`syn/build/eh2_dc_wrapper.sv` 与 :file:`syn/build/eh2_synth.v`。它们记录
了从 RC3 到 RC4 的尝试，但当前主线闭环路径转向
:ref:`adr-0020` 中定义的 block-level LEC。

§3.1  ``lec_run.tcl`` — 基础 top-level 骨架
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_run.tcl:L3-L14``）：

.. code-block:: text

   set BUILD_DIR /home/host/eh2-veri/syn/build

   # Redirect Formality working files to a dedicated build subdir.
   set RUN_DIR $BUILD_DIR/lec_run
   file mkdir $RUN_DIR
   cd $RUN_DIR
   catch {set_app_var hdlin_temporary_dir $RUN_DIR}

   set hdlin_error_on_elab_message false
   set verification_mode relaxed
   suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
   set_app_var hdlin_sverilog_std 2012

逐段解释：

* 第 3 行：所有 top-level 输入输出都固定到 :file:`/home/host/eh2-veri/syn/build`。
* 第 6~9 行：Formality 临时文件被放到 ``lec_run`` 子目录，避免污染调用目录。
* 第 11~14 行：脚本放宽 elaboration error 处理、设置 relaxed verification
  mode、抑制指定消息，并把 SystemVerilog 标准设为 2012。这些设置在多个
  LEC 脚本中重复出现。

关键代码（``syn/scripts/lec_run.tcl:L23-L48``）：

.. code-block:: text

   # Read class.db to resolve synth cell references
   puts "FM: Reading technology libraries..."
   read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
   read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

   # Reference (Golden RTL)
   puts "FM: Reading reference design..."
   read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
   puts "FM: Setting ref top..."
   set_top r:/WORK/eh2_veer

   # Implementation (synthesized netlist)
   puts "FM: Reading implementation netlist..."
   read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
   puts "FM: Setting impl top..."
   set_top i:/WORK/eh2_veer

   # Match and verify
   puts "FM: Starting match..."
   match
   puts "FM: Starting verify..."
   verify

   report_status > $BUILD_DIR/lec_report.txt
   puts "FM: === LEC Complete ==="
   exit 0

逐段解释：

* 第 23~26 行：先读取 Synopsys technology libraries。``class.db`` 解析综合
  cell 引用，``gtech.db`` 提供 generic technology cell。
* 第 28~32 行：reference side 使用 ``read_sverilog -r`` 读取
  :file:`eh2_dc_wrapper.sv`，并将 reference top 设为 ``r:/WORK/eh2_veer``。
* 第 34~38 行：implementation side 使用 ``read_verilog -i`` 读取综合 netlist，
  implementation top 也设为 ``eh2_veer``。
* 第 40~46 行：Formality 先 ``match`` 再 ``verify``，最后用
  ``report_status`` 写出 :file:`syn/build/lec_report.txt`。

接口关系：

* 被调用：手工 ``fm_shell -f syn/scripts/lec_run.tcl``。
* 调用：Formality 命令 ``read_db``、``read_sverilog``、``read_verilog``、
  ``match``、``verify``、``report_status``。
* 共享状态：读取 :file:`syn/build/eh2_dc_wrapper.sv` 与
  :file:`syn/build/eh2_synth.v`。

§3.2  ``lec_svf.tcl`` — SVF 引导尝试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_svf.tcl:L23-L47``）：

.. code-block:: text

   # Load SVF before reading designs to guide matching
   puts "FM: Loading SVF..."
   set_svf /home/host/eh2-veri/default.svf

   # Reference (Golden RTL)
   puts "FM: Reading reference design..."
   read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
   puts "FM: Setting ref top..."
   set_top r:/WORK/eh2_veer

   # Implementation (synthesized netlist)
   puts "FM: Reading implementation netlist..."
   read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
   puts "FM: Setting impl top..."
   set_top i:/WORK/eh2_veer

   # Match and verify — SVF guides the matching
   puts "FM: Starting match (SVF-guided)..."
   match
   puts "FM: Starting verify..."
   verify

   report_status > $BUILD_DIR/lec_p0a_svf.log
   report_failing_points > $BUILD_DIR/lec_p0a_svf_failing.rpt

逐段解释：

* 第 23~25 行：脚本在读入 reference 和 implementation 之前调用
  ``set_svf``。该位置说明 SVF 被用作 matching guide，而不是 verify 后的
  报告过滤器。
* 第 27~37 行：reference 与 implementation 的读入方式仍与
  ``lec_run.tcl`` 相同。
* 第 39~46 行：脚本额外输出 failing points 到
  :file:`syn/build/lec_p0a_svf_failing.rpt`，用于判断 SVF 是否减少
  packed-port mismatch。

接口关系：

* 被调用：手工 Formality 调试。
* 调用：``set_svf``、``match``、``verify``、``report_failing_points``。
* 共享状态：读取 :file:`/home/host/eh2-veri/default.svf`。

§3.3  ``lec_p0a.tcl`` — 用户匹配表尝试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_p0a.tcl:L32-L45``）：

.. code-block:: text

   # P0-A: User-specified port matching for 2D packed array ports
   # Maps Ref 2D indices to Impl 1D indices
   puts "FM: Setting user matches..."
   source /home/host/eh2-veri/syn/scripts/lec_user_match.tcl
   puts "FM: user_match OK"

   puts "FM: Starting match..."
   match
   puts "FM: Starting verify..."
   verify

   report_status > $BUILD_DIR/lec_p0a_final.log
   report_failing_points > $BUILD_DIR/lec_p0a_failing.rpt

逐段解释：

* 第 32~35 行：脚本把 packed-array 端口映射从主流程中拆到
  :file:`syn/scripts/lec_user_match.tcl`。这使 top-level LEC 尝试可以在同一
  读入骨架下替换 matching 策略。
* 第 38~41 行：用户匹配表加载完成后才运行 ``match`` 和 ``verify``。
* 第 43~44 行：报告输出路径与 SVF 尝试不同，便于保留多个实验结果。

接口关系：

* 被调用：手工 top-level P0-A 实验。
* 调用：``source lec_user_match.tcl``。
* 共享状态：读取 194 条 ``set_user_match`` 映射。

§3.4  ``lec_rc4_fix.tcl`` — undriven 与 clock-gate 设置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_rc4_fix.tcl:L11-L58``）：

.. code-block:: text

   # Critical: set verification mode and undriven signal handling
   set verification_mode relaxed
   # Treat undriven signals as 0 to handle tied-off ports (DC ties them low)
   set verification_set_undriven_signals 0
   ...
   # Pre-match: handle clock-gating and synthesis optimizations
   puts "FM: Configuring verification settings..."
   # Match clock gates (SNPS_CLOCK_GATE cells from DC)
   # These are structurally different from RTL clock-enable logic
   set verification_clock_gate_hold_mode low

   puts "FM: Starting match..."
   match

   puts "FM: Starting verify..."
   verify

   # Report results with full detail
   puts "FM: Generating reports..."
   report_status > $BUILD_DIR/lec_rc4_report.txt
   report_failing_points -verbose > $BUILD_DIR/lec_rc4_failing.rpt
   report_unverified_points -verbose > $BUILD_DIR/lec_rc4_unverified.rpt
   report_passing_points -summary > $BUILD_DIR/lec_rc4_passing.rpt

逐段解释：

* 第 11~14 行：脚本把 undriven signal 按 ``0`` 处理。代码注释说明这一设置面向
  DC tie-low port。
* 第 41~45 行：脚本设置 ``verification_clock_gate_hold_mode low``，面向
  Design Compiler 生成的 ``SNPS_CLOCK_GATE`` cell 与 RTL clock-enable 结构差异。
* 第 53~58 行：相比基础脚本，这里同时输出 status、verbose failing、
  verbose unverified 和 passing summary，用于定位 RC3 之后的剩余问题。

接口关系：

* 被调用：RC4 top-level Formality 调试。
* 调用：Formality verification settings 与 report 命令。
* 共享状态：仍读取 top-level wrapper 和 netlist。

§4  194 个 packed-port 匹配问题
--------------------------------------------------------------------------------------------------------------------------------------------

职责：top-level flow 的主要问题不是已知 RTL 功能差异，而是
Synopsys O-2018.06-SP1 对 2D packed array / packed struct 端口 flattening
后的自动匹配限制。这个边界由 :ref:`adr-0019` 记录，R3-C 的 closure path
由 :ref:`adr-0020` 接管。

§4.1  ``lec_matching.tcl`` 的 bucket 分类
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_matching.tcl:L1-L20``）：

.. code-block:: text

   # ============================================================================
   # lec_matching.tcl — Formality LEC Matching Directives
   # RC5 (2026-05-09)
   #
   # Classification of 194 unmatched output ports:
   #   All 194 are BUS BIT-BLASTING: the RTL declares 2D packed arrays
   #   (e.g., [1:0][70:0] ic_wr_data) that DC synthesis flattens to
   #   individual bit-level ports in the netlist.  Formality cannot match
   #   the bit-blasted names automatically.
   #
   # Buckets:
   #   Bucket A: ic_wr_data          — 142 points (ICACHE_BANKS_WAY × 71 bits)
   #   Bucket B: btb_rw_addr         —  18 points (2 banks × BTB_ADDR_HI:1)
   #   Bucket C: btb_rw_addr_f1      —  18 points (2 banks × BTB_ADDR_HI:1)
   #   Bucket D: btb_sram_rd_tag_f1  —  10 points (2 banks × BTB_BTAG_SIZE)
   #   Bucket E: trace_rv_i_valid_ip —   2 points (NUM_THREADS × 2 bits)
   #   Bucket F: trace_rv_i_address_ip—  2 points (NUM_THREADS × 64 bits)
   #   Bucket G: trace_rv_i_exception_ip—1 point
   #   Bucket H: trace_rv_i_interrupt_ip—1 point

逐段解释：

* 第 5~9 行：注释直接给出 root cause：RTL 使用 2D packed array，DC 综合后
  netlist 变成 bit-level port，Formality 无法自动匹配 flatten 后的名字。
* 第 11~19 行：194 个点被分到 8 个 bucket。最大 bucket 是 ``ic_wr_data``，
  共 142 点；BTB 地址和 trace 端口构成剩余点。
* 这些数字与 :ref:`adr-0019` 的 root cause 描述一致。文档不能把它们改写成
  RTL bug，也不能把它们描述成已用 ``set_dont_verify_points`` 豁免。

接口关系：

* 被调用：top-level matching 实验。
* 调用：后续 ``set_user_match``、``match``、``verify``。
* 共享状态：匹配对象是 ``r:/WORK/eh2_veer`` 与 ``i:/WORK/eh2_veer``。

§4.2  粗粒度 ``set_user_match`` 尝试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_matching.tcl:L51-L83``）：

.. code-block:: text

   # --- Bucket A: ic_wr_data [pt.ICACHE_BANKS_WAY-1:0][70:0] (142 bits) ---
   # RTL: output logic [pt.ICACHE_BANKS_WAY-1:0] [70:0] ic_wr_data
   # Netlist: flattened to \ic_wr_data[0][0] .. \ic_wr_data[0][70]
   set_user_match r:/WORK/eh2_veer/ic_wr_data \
                  i:/WORK/eh2_veer/ic_wr_data

   # --- Bucket B: btb_rw_addr [1:0][pt.BTB_ADDR_HI:1] (18 points) ---
   set_user_match r:/WORK/eh2_veer/btb_rw_addr \
                  i:/WORK/eh2_veer/btb_rw_addr

   # --- Bucket C: btb_rw_addr_f1 [1:0][pt.BTB_ADDR_HI:1] (18 points) ---
   set_user_match r:/WORK/eh2_veer/btb_rw_addr_f1 \
                  i:/WORK/eh2_veer/btb_rw_addr_f1

   # --- Bucket D: btb_sram_rd_tag_f1 [1:0][pt.BTB_BTAG_SIZE-1:0] (10 points) ---
   set_user_match r:/WORK/eh2_veer/btb_sram_rd_tag_f1 \
                  i:/WORK/eh2_veer/btb_sram_rd_tag_f1

逐段解释：

* 第 51~55 行：``ic_wr_data`` 是 2 个 way、每个 71 bit 的 packed array。脚本先
  试图按端口整体建立 reference 与 implementation 的用户匹配。
* 第 57~67 行：BTB 相关的 3 个 packed array 也使用整体端口匹配。
* 这段是 matching directive，不是 waiver。它告诉 Formality 如何配对比较点，
  但不删除比较点。

接口关系：

* 被调用：``lec_matching.tcl`` 主流程内部。
* 调用：Formality ``set_user_match``。
* 共享状态：依赖 Formality elaborated design 中的端口名。

§4.3  逐 bit ``lec_user_match.tcl`` 映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_user_match.tcl:L1-L24``）：

.. code-block:: text

   # P0-A: Auto-generated set_user_match for 194 failing LEC compare points
   # Maps 2D packed-array Ref ports to 1D flattened Impl ports
   # Formula: linear(i,j) = (i-d1_min)*sub_w + (j-d2_min)

   suppress_message {VER-130 VER-250}

   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][1] i:/WORK/eh2_veer/btb_rw_addr[0]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][2] i:/WORK/eh2_veer/btb_rw_addr[1]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][3] i:/WORK/eh2_veer/btb_rw_addr[2]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][4] i:/WORK/eh2_veer/btb_rw_addr[3]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][5] i:/WORK/eh2_veer/btb_rw_addr[4]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][6] i:/WORK/eh2_veer/btb_rw_addr[5]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][7] i:/WORK/eh2_veer/btb_rw_addr[6]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][8] i:/WORK/eh2_veer/btb_rw_addr[7]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[0][9] i:/WORK/eh2_veer/btb_rw_addr[8]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][1] i:/WORK/eh2_veer/btb_rw_addr[9]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][2] i:/WORK/eh2_veer/btb_rw_addr[10]
   set_user_match r:/WORK/eh2_veer/btb_rw_addr[1][3] i:/WORK/eh2_veer/btb_rw_addr[11]

逐段解释：

* 第 1~3 行：文件说明它是自动生成的 194 点映射，并给出 flatten 公式：
  ``linear(i,j) = (i-d1_min)*sub_w + (j-d2_min)``。
* 第 7~15 行：``btb_rw_addr[0][1]`` 到 ``btb_rw_addr[0][9]`` 被映射到
  implementation 的 bit ``0`` 到 ``8``。
* 第 16~18 行：第二个 bank 从 implementation bit ``9`` 开始。这与公式中
  以 bank 宽度为 stride 的线性化一致。

关键代码（``syn/scripts/lec_user_match.tcl:L195-L200``）：

.. code-block:: text

   set_user_match r:/WORK/eh2_veer/trace_rv_i_address_ip[0][0] i:/WORK/eh2_veer/trace_rv_i_address_ip[0]
   set_user_match r:/WORK/eh2_veer/trace_rv_i_address_ip[0][32] i:/WORK/eh2_veer/trace_rv_i_address_ip[32]
   set_user_match r:/WORK/eh2_veer/trace_rv_i_exception_ip[0][0] i:/WORK/eh2_veer/trace_rv_i_exception_ip[0]
   set_user_match r:/WORK/eh2_veer/trace_rv_i_interrupt_ip[0][1] i:/WORK/eh2_veer/trace_rv_i_interrupt_ip[1]
   set_user_match r:/WORK/eh2_veer/trace_rv_i_valid_ip[0][0] i:/WORK/eh2_veer/trace_rv_i_valid_ip[0]
   set_user_match r:/WORK/eh2_veer/trace_rv_i_valid_ip[0][1] i:/WORK/eh2_veer/trace_rv_i_valid_ip[1]

逐段解释：

* 第 195~196 行：trace address 只列出需要映射的具体 bit，不是把 64 bit 全部
  展开。文档只能按文件中的条目描述，不能推断缺失 bit 也被映射。
* 第 197~200 行：exception、interrupt 和 valid trace 端口分别映射到 flatten
  后的 implementation bit。

接口关系：

* 被调用：``lec_p0a.tcl`` 第 35 行通过 ``source`` 读取。
* 调用：Formality ``set_user_match``。
* 共享状态：读写 Formality session 中的 compare point matching 规则。

§5  R3-C block-level 公共框架
--------------------------------------------------------------------------------------------------------------------------------------------

职责：:file:`syn/scripts/lec_blocklevel/lec_common.tcl` 是所有 R3-C block
LEC 脚本共享的框架。每个 block 脚本只负责选择 top、添加必要
``set_user_match``、执行 ``match`` 与 ``verify``；输入读取、SVF 加载和报告写出
由公共过程处理。

§5.1  全局路径与 Formality 设置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L6-L28``）：

.. code-block:: text

   set EH2_ROOT /home/host/eh2-veri
   set BUILD_DIR $EH2_ROOT/syn/build
   set RPT_DIR $BUILD_DIR/lec_blocklevel
   file mkdir $RPT_DIR

   # Redirect Formality working files to a dedicated build subdir.
   if {[info exists env(R3C_FM_RUN_DIR)] && $env(R3C_FM_RUN_DIR) ne ""} {
       set RUN_DIR $env(R3C_FM_RUN_DIR)
   } else {
       set RUN_DIR $RPT_DIR/run/fm/shared
   }
   file mkdir $RUN_DIR
   cd $RUN_DIR
   catch {set_app_var hdlin_temporary_dir $RUN_DIR}

   set R3C_SVF_PRELOADED 0

   suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
   set_app_var hdlin_sverilog_std 2012
   set verification_mode relaxed
   set verification_set_undriven_signals 0
   set verification_clock_gate_hold_mode low

逐段解释：

* 第 6~9 行：公共脚本定义仓库根、综合 build 目录、block-level 报告目录，并确保
  报告目录存在。
* 第 12~19 行：如果外部设置了 ``R3C_FM_RUN_DIR``，就使用每个 label 独立的
  Formality run 目录；否则使用 shared fallback 目录。
* 第 21 行：``R3C_SVF_PRELOADED`` 是脚本内部状态，用于避免重复加载 SVF。
* 第 23~28 行：公共设置包含消息抑制、SystemVerilog 2012、relaxed mode、
  undriven signal 处理和 clock-gate hold mode。每个 block 继承这些设置。

接口关系：

* 被调用：所有 :file:`syn/scripts/lec_blocklevel/lec_*.tcl` 通过 ``source`` 调用。
* 调用：Formality app vars。
* 共享状态：``EH2_ROOT``、``BUILD_DIR``、``RPT_DIR``、``RUN_DIR``、
  ``R3C_SVF_PRELOADED``。

§5.2  search path、library 与 reference 读入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L29-L67``）：

.. code-block:: text

   set_app_var search_path [concat \
       $RUN_DIR \
       $RPT_DIR \
       $EH2_ROOT/syn/include \
       /home/host/Cores-VeeR-EH2/snapshots/default \
       /home/host/Cores-VeeR-EH2/design/include \
       /home/host/Cores-VeeR-EH2/design/lib \
       [get_app_var search_path]]

   puts "FM: R3-C reading technology libraries..."
   read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
   read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
   ...
   puts "FM: R3-C reading reference design from $BUILD_DIR/eh2_dc_wrapper.sv"
   read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv

逐段解释：

* 第 29~36 行：search path 包括 run 目录、报告目录、仓库内 include、EH2 snapshot
  与上游 design include/lib。block 脚本不重复设置这些路径。
* 第 38~40 行：公共脚本读取 Synopsys ``class.db`` 和 ``gtech.db``。
* 第 65~67 行：所有 block 的 reference side 都从同一个
  :file:`syn/build/eh2_dc_wrapper.sv` 读入。具体 block top 由各 block 脚本后续
  调用 ``set_top r:/WORK/$TOP`` 决定。

接口关系：

* 被调用：公共脚本加载阶段。
* 调用：``read_db``、``read_sverilog -r``。
* 共享状态：Formality search path 与 ``WORK`` library。

§5.3  SVF 预载与延迟加载
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L42-L63``）：

.. code-block:: text

   if {[info exists env(R3C_PRELOAD_SVF_FILE)] && $env(R3C_PRELOAD_SVF_FILE) ne ""} {
       if {[file exists $env(R3C_PRELOAD_SVF_FILE)]} {
           puts "FM: R3-C preloading explicit SVF guide $env(R3C_PRELOAD_SVF_FILE)"
           set_svf $env(R3C_PRELOAD_SVF_FILE)
           set R3C_SVF_PRELOADED 1
       } else {
           puts "FM: R3-C WARNING: explicit SVF guide missing: $env(R3C_PRELOAD_SVF_FILE)"
       }
   } elseif {[info exists env(R3C_PRELOAD_SVF_TOP)] && $env(R3C_PRELOAD_SVF_TOP) ne ""} {
       set preload_svf $RPT_DIR/synth/$env(R3C_PRELOAD_SVF_TOP).svf
       if {[file exists $preload_svf]} {
           puts "FM: R3-C preloading block SVF guide $preload_svf"
           set_svf $preload_svf
           set R3C_SVF_PRELOADED 1

逐段解释：

* 第 42~49 行：如果调用者提供 ``R3C_PRELOAD_SVF_FILE``，公共脚本优先加载这个
  明确路径。文件缺失时只打印 warning，不伪造 SVF。
* 第 50~55 行：如果提供 ``R3C_PRELOAD_SVF_TOP``，脚本从
  :file:`syn/build/lec_blocklevel/synth/<top>.svf` 查找 block SVF。
* 这段体现 :ref:`adr-0020` 中的做法：block-level flow 依赖 DC 生成的 block
  SVF 来保留 datapath guidance。

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L68-L88``）：

.. code-block:: text

   proc r3c_load_svf {top} {
       global RPT_DIR EH2_ROOT R3C_SVF_PRELOADED
       if {$R3C_SVF_PRELOADED} {
           puts "FM: R3-C SVF guide already preloaded for $top"
           return
       }
       set block_svf $RPT_DIR/synth/${top}.svf
       if {[file exists $block_svf]} {
           puts "FM: R3-C loading block SVF guide $block_svf"
           if {[catch {set_svf $block_svf} msg]} {
               puts "FM: R3-C WARNING: set_svf failed for $top: $msg"
           }

逐段解释：

* 第 68~73 行：``r3c_load_svf`` 先检查 SVF 是否已预载，避免同一 session 中重复
  ``set_svf``。
* 第 74~79 行：当 block SVF 存在时加载它；如果 ``set_svf`` 失败，错误被捕获并
  打印 warning。
* 第 80~87 行（未在片段中全部展示）：公共过程在 block SVF 缺失时尝试
  :file:`default.svf`，再缺失则打印 warning。它不会生成或修改 SVF 文件。

接口关系：

* 被调用：各 block 脚本在 implementation top 设置后调用。
* 调用：Formality ``set_svf``。
* 共享状态：``R3C_SVF_PRELOADED``、``RPT_DIR``、``EH2_ROOT``。

§5.4  implementation 读入与 top 选择
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L90-L126``）：

.. code-block:: text

   proc r3c_read_impl {top} {
       global BUILD_DIR RPT_DIR env
       set block_ddc $RPT_DIR/synth/${top}.ddc
       set block_netlist $RPT_DIR/synth/${top}.v
       if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
           puts "FM: R3-C reading forced top-context implementation from $BUILD_DIR/eh2_synth.v"
           read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
       } elseif {[info exists env(R3C_FORCE_VERILOG_IMPL)] && $env(R3C_FORCE_VERILOG_IMPL) eq "1" && [file exists $block_netlist]} {
           puts "FM: R3-C reading forced standalone Verilog implementation from $block_netlist"
           read_verilog -i -libname WORK $block_netlist
       } elseif {[file exists $block_ddc]} {
           puts "FM: R3-C reading standalone block DDC implementation from $block_ddc"

逐段解释：

* 第 90~93 行：implementation 可以来自 standalone block DDC、standalone block
  Verilog，或 top-context :file:`eh2_synth.v`。
* 第 94~96 行：``R3C_FORCE_TOP_CONTEXT_IMPL=1`` 强制读取全局 netlist。
* 第 97~105 行：如果强制 Verilog 且 block netlist 存在，则读 Verilog；否则优先读
  block DDC，再退到 block Verilog。
* 第 106~110 行（未在片段中全部展示）：当 standalone block netlist 不存在时，
  退回读取 top-context implementation。

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L113-L126``）：

.. code-block:: text

   proc r3c_set_impl_top {top} {
       global RPT_DIR env
       set suffixed ${top}_
       if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
           puts "FM: R3-C using forced top-context implementation top $suffixed"
           set_top i:/WORK/$suffixed
       } elseif {[file exists $RPT_DIR/synth/${top}.v]} {
           puts "FM: R3-C using standalone implementation top $top"
           set_top i:/WORK/$top
       } else {
           puts "FM: R3-C using top-context implementation top $suffixed"
           set_top i:/WORK/$suffixed
       }
   }

逐段解释：

* 第 115 行：top-context implementation 的模块名使用 ``${top}_`` 后缀。
* 第 116~118 行：强制 top-context 时直接选择 suffixed implementation top。
* 第 119~121 行：standalone block Verilog 存在时，implementation top 使用原始
  ``$top``。
* 第 122~124 行：否则回到 top-context suffixed top。

接口关系：

* 被调用：各 block 脚本。
* 调用：``read_ddc``、``read_verilog -i``、``set_top i:/WORK/...``。
* 共享状态：``R3C_FORCE_TOP_CONTEXT_IMPL``、``R3C_FORCE_VERILOG_IMPL``。

§5.5  report 写出过程
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_common.tcl:L128-L138``）：

.. code-block:: text

   proc r3c_write_reports {label} {
       global RPT_DIR
       puts "FM: R3-C reporting $label"
       report_status > $RPT_DIR/lec_${label}.rpt
       if {[catch {report_failing_points > $RPT_DIR/lec_${label}_failing.rpt} msg]} {
           puts "FM: R3-C report_failing_points failed for $label: $msg"
       }
       if {[catch {report_failing_points -verbose > $RPT_DIR/lec_${label}_failing_verbose.rpt} msg]} {
           puts "FM: R3-C verbose failing report unsupported for $label: $msg"
       }
       report_unverified_points > $RPT_DIR/lec_${label}_unverified.rpt
   }

逐段解释：

* 第 131 行：每个 block 的主 status 报告固定命名为
  :file:`lec_<label>.rpt`。这是 :file:`lec_summary.py` 的输入。
* 第 132~137 行：failing report 和 verbose failing report 使用 ``catch`` 包裹。
  某些 Formality 版本不支持 verbose 参数时，流程打印 message 而不是中断。
* 第 138 行：unverified points 单独写入 :file:`lec_<label>_unverified.rpt`。

接口关系：

* 被调用：每个 block 脚本在 ``verify`` 后调用。
* 调用：Formality report 命令。
* 共享状态：``RPT_DIR`` 与传入的 ``label``。

§6  普通 block 脚本模板
--------------------------------------------------------------------------------------------------------------------------------------------

职责：``dbg``、``dma``、``pic`` 等 block 没有额外 packed-struct 映射逻辑，
它们展示了 R3-C block LEC 的最小闭环。

§6.1  ``lec_dbg.tcl`` — 最小闭环
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_dbg.tcl:L1-L18``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

   puts "FM: R3-C block LEC dbg"
   set TOP eh2_dbg
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP

   puts "FM: R3-C matching dbg"
   match

   puts "FM: R3-C verifying dbg"
   verify
   r3c_write_reports dbg

逐段解释：

* 第 1 行：``sh_continue_on_error`` 设为 ``false``，Formality 命令出错时不继续
  静默执行。
* 第 2 行：公共框架先读取 reference design、technology library 和公共设置。
* 第 5~9 行：脚本选择 reference top ``eh2_dbg``，再读入 implementation、设置
  implementation top、加载 SVF。
* 第 11~16 行：按 ``match``、``verify``、``r3c_write_reports dbg`` 的顺序完成
  block LEC。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 label 循环。
* 调用：``lec_common.tcl`` 中的 3 个过程。
* 共享状态：``TOP=eh2_dbg`` 与报告 label ``dbg``。

§6.2  ``lec_dma.tcl`` 与 ``lec_pic.tcl`` — 同构脚本
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_dma.tcl:L4-L16``）：

.. code-block:: text

   puts "FM: R3-C block LEC dma"
   set TOP eh2_dma_ctrl
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP

   puts "FM: R3-C matching dma"
   match

   puts "FM: R3-C verifying dma"
   verify
   r3c_write_reports dma

逐段解释：

* 第 4~9 行：DMA block 的 top 是 ``eh2_dma_ctrl``，报告 label 是 ``dma``。
* 第 11~16 行：执行顺序与 ``lec_dbg.tcl`` 相同，没有额外 user match。

关键代码（``syn/scripts/lec_blocklevel/lec_pic.tcl:L4-L16``）：

.. code-block:: text

   puts "FM: R3-C block LEC pic"
   set TOP eh2_pic_ctrl
   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP

   puts "FM: R3-C matching pic"
   match

   puts "FM: R3-C verifying pic"
   verify
   r3c_write_reports pic

逐段解释：

* 第 4~9 行：PIC block 的 top 是 ``eh2_pic_ctrl``，报告 label 是 ``pic``。
* 第 11~16 行：PIC 脚本也只依赖公共框架和 Formality 基本命令，不添加
  ``set_user_match``。

接口关系：

* 被调用：``syn/Makefile:block_lec``。
* 调用：``r3c_read_impl``、``r3c_set_impl_top``、``r3c_load_svf``、
  ``r3c_write_reports``。
* 共享状态：每个脚本的 ``TOP`` 与 label。

§7  带显式 packed/struct match 的 block
--------------------------------------------------------------------------------------------------------------------------------------------

职责：``dec``、``ifu``、``lsu`` 的端口包含 packed struct 或 2D packed
array。脚本用明确的 ``set_user_match`` 把 reference 字段映射到 implementation
flatten 后的 bit index。

§7.1  ``lec_dec.tcl`` — 诊断包与预测包映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_dec.tcl:L15-L28``）：

.. code-block:: text

   puts "FM: R3-C adding dec packed-struct port matches"
   foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39] {
       set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_wrdata\]\[$bit\] ${itop}/dec_tlu_ic_diag_pkt\[[expr {$bit + 19}]\]
       incr user_match_count
   }
   foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16] {
       set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_dicawics\]\[$bit\] ${itop}/dec_tlu_ic_diag_pkt\[[expr {$bit + 2}]\]
       incr user_match_count
   }
   set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_rd_valid\] ${itop}/dec_tlu_ic_diag_pkt\[1\]
   incr user_match_count
   set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_wr_valid\] ${itop}/dec_tlu_ic_diag_pkt\[0\]

逐段解释：

* 第 15~19 行：``icache_wrdata`` 字段从 reference 的结构字段映射到 implementation
  的 ``dec_tlu_ic_diag_pkt[bit+19]``。脚本为每个 bit 增加
  ``user_match_count``。
* 第 20~23 行：``icache_dicawics`` 从 bit ``0`` 到 ``16`` 映射到 implementation
  的 bit ``2`` 到 ``18``。
* 第 24~27 行：``icache_rd_valid`` 和 ``icache_wr_valid`` 分别映射到 flattened
  bit ``1`` 和 ``0``。

关键代码（``syn/scripts/lec_blocklevel/lec_dec.tcl:L29-L55``）：

.. code-block:: text

   foreach pred {i0_predict_p_d i1_predict_p_d} {
       foreach bit [list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28] {
           set_user_match ${rtop}/${pred}\[prett\]\[$bit\] ${itop}/${pred}\[[expr {$bit + 13}]\]
           incr user_match_count
       }
       foreach bit {0 1} {
           set_user_match ${rtop}/${pred}\[hist\]\[$bit\] ${itop}/${pred}\[[expr {$bit + 11}]\]
           incr user_match_count
       }
       foreach {field idx} {
           boffset 13
           bank 10
           way 9
           ataken 8
           valid 7
           pc4 6

逐段解释：

* 第 29 行：同一套预测包映射同时应用于 ``i0_predict_p_d`` 和
  ``i1_predict_p_d``。
* 第 30~33 行：``prett`` 数组字段从 reference bit 映射到 implementation 的
  ``bit+13`` 位置。
* 第 34~37 行：``hist[0]`` 和 ``hist[1]`` 映射到 ``11`` 和 ``12``。
* 第 38 行之后：脚本用 ``foreach {field idx}`` 列出标量字段到 flattened index
  的映射，例如 ``boffset`` 到 ``13``、``bank`` 到 ``10``。

关键代码（``syn/scripts/lec_blocklevel/lec_dec.tcl:L57-L83``）：

.. code-block:: text

   foreach {field idx} {
       atomic 32
       atomic64 31
       fast_int 30
       barrier 29
       lr 28
       sc 27
       dma 21
       by 20
       half 19
       word 18
       dword 17
       load 16
       store 15
       pipe 14
       unsign 13
       stack 12
       tid 11
       store_data_bypass_c1 10
       load_ldst_bypass_c1 9
       store_data_bypass_c2 8
       store_data_bypass_i0_e2_c2 7
       valid 0
   } {
       set_user_match ${rtop}/lsu_p\[$field\] ${itop}/lsu_p\[$idx\]
       incr user_match_count
   }

逐段解释：

* 第 57~80 行：``lsu_p`` packed struct 的每个字段被映射到指定 flattened bit。
* 第 81~82 行：映射执行时使用 ``set_user_match``，并增加
  ``user_match_count``。
* 字段顺序来自脚本，不在文档中重新排序，避免引入与源文件不一致的解释。

关键代码（``syn/scripts/lec_blocklevel/lec_dec.tcl:L110-L123``）：

.. code-block:: text

   puts "FM: R3-C dec user_match_count=$user_match_count"
   set match_count_fh [open $RPT_DIR/lec_dec_user_match_count.txt w]
   puts $match_count_fh $user_match_count
   close $match_count_fh

   puts "FM: R3-C matching dec"
   match

   puts "FM: R3-C verifying dec"
   verify
   r3c_write_reports dec

   puts "FM: R3-C dec complete"
   exit 0

逐段解释：

* 第 110~113 行：DEC 脚本把显式 user match 数量写入
  :file:`lec_dec_user_match_count.txt`，用于审计匹配规则数量。
* 第 115~120 行：所有映射建立后才执行 ``match``、``verify`` 与 report 写出。
* 第 122~123 行：脚本打印完成信息并退出。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 ``dec`` label。
* 调用：公共框架、Formality ``set_user_match``。
* 共享状态：``rtop``、``itop``、``user_match_count``、``RPT_DIR``。

§7.2  ``lec_ifu.tcl`` — IFU 2D array 与 branch packet 映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_ifu.tcl:L27-L61``）：

.. code-block:: text

   puts "FM: R3-C adding IFU ic_wr_data user matches"
   foreach way {0 1} {
       for {set bit 0} {$bit < 71} {incr bit} {
           set flat_idx [expr {$way * 71 + $bit}]
           set_user_match ${rtop}/ic_wr_data\[$way\]\[$bit\] ${itop}/ic_wr_data\[$flat_idx\]
           incr user_match_count
       }
   }

   puts "FM: R3-C adding IFU btb_rw_addr user matches"
   foreach way {0 1} {
       for {set bit 1} {$bit <= 9} {incr bit} {
           set flat_idx [expr {$way * 9 + ($bit - 1)}]
           set_user_match ${rtop}/btb_rw_addr\[$way\]\[$bit\] ${itop}/btb_rw_addr\[$flat_idx\]
           incr user_match_count
       }
   }

逐段解释：

* 第 27~34 行：``ic_wr_data`` 的 flatten index 为 ``way * 71 + bit``。两个 way
  各 71 bit，共覆盖 142 个映射。
* 第 36~43 行：``btb_rw_addr`` 的 bit index 从 ``1`` 到 ``9``，flatten index 为
  ``way * 9 + (bit - 1)``。
* 第 45~61 行（未在片段中全部展示）：``btb_rw_addr_f1`` 与
  ``btb_sram_rd_tag_f1`` 使用同样的双层循环结构。

关键代码（``syn/scripts/lec_blocklevel/lec_ifu.tcl:L63-L90``）：

.. code-block:: text

   proc r3c_ifu_add_brp_matches {rtop itop port_name user_match_count_name} {
       upvar $user_match_count_name user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[way\] ${itop}/${port_name}\[0\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[hist\]\[0\] ${itop}/${port_name}\[1\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[hist\]\[1\] ${itop}/${port_name}\[2\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[valid\] ${itop}/${port_name}\[3\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[bank\] ${itop}/${port_name}\[4\]
       incr user_match_count
       set_user_match ${rtop}/${port_name}\[0\]\[br_start_error\] ${itop}/${port_name}\[5\]

逐段解释：

* 第 63~64 行：过程通过 ``upvar`` 访问调用方的 ``user_match_count``，使过程内部
  也能累计映射数量。
* 第 65~75 行：branch prediction packet 的标量字段按固定 flattened index
  映射，包括 ``way``、``hist``、``valid``、``bank``、``br_start_error``。
* 第 79~85 行（未在片段中全部展示）：``prett`` 字段通过循环映射，``ret`` 字段
  映射到 index ``38``。
* 第 88~90 行：调用该过程两次，分别处理 ``i0_brp`` 与 ``i1_brp``。

关键代码（``syn/scripts/lec_blocklevel/lec_ifu.tcl:L100-L113``）：

.. code-block:: text

   puts "FM: R3-C ifu user_match_count=$user_match_count"
   set match_count_fh [open $RPT_DIR/lec_ifu_user_match_count.txt w]
   puts $match_count_fh $user_match_count
   close $match_count_fh

   puts "FM: R3-C matching ifu after explicit packed-array matches"
   match

   puts "FM: R3-C verifying ifu"
   verify
   r3c_write_reports ifu

   puts "FM: R3-C ifu complete"
   exit 0

逐段解释：

* 第 100~103 行：IFU 也写出 user match 数量，用于审计显式匹配覆盖范围。
* 第 105~110 行：脚本在显式 packed-array matches 之后再次 ``match``，再
  ``verify`` 并写出 ``ifu`` 报告。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 ``ifu`` label。
* 调用：``r3c_ifu_add_brp_matches`` 与公共框架过程。
* 共享状态：``R3C_PRELOAD_SVF_TOP=eh2_ifu``、``rtop``、``itop``。

§7.3  ``lec_lsu.tcl`` — LSU error packet 与 trigger packet 映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_lsu.tcl:L13-L32``）：

.. code-block:: text

   puts "FM: R3-C adding lsu lsu_error_pkt_dc3 packed-struct matches"
   foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17] {
       set_user_match ${rtop}/lsu_error_pkt_dc3\[addr\]\[$bit\] ${itop}/lsu_error_pkt_dc3\[$bit\]
       incr user_match_count
   }
   foreach bit {0 1 2 3} {
       set_user_match ${rtop}/lsu_error_pkt_dc3\[mscause\]\[$bit\] ${itop}/lsu_error_pkt_dc3\[[expr {$bit + 32}]\]
       incr user_match_count
   }
   foreach {field idx} {
       exc_type 36
       amo_valid 37
       inst_type 38

逐段解释：

* 第 13~17 行：``lsu_error_pkt_dc3[addr]`` 按 bit 映射到 implementation 的同名
  flattened vector index。源文件实际循环覆盖 0 到 31，片段只展示前半段。
* 第 18~21 行：``mscause`` 字段映射到 implementation index ``32`` 到 ``35``。
* 第 22 行之后：标量字段通过 ``foreach {field idx}`` 映射到 index ``36`` 以后。

关键代码（``syn/scripts/lec_blocklevel/lec_lsu.tcl:L35-L57``）：

.. code-block:: text

   puts "FM: R3-C adding lsu trigger_pkt_any packed-struct input matches"
   foreach trig {0 1 2 3} {
       set base [expr {$trig * 38}]
       foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13] {
           set_user_match ${rtop}/trigger_pkt_any\[0\]\[$trig\]\[tdata2\]\[$bit\] ${itop}/trigger_pkt_any\[[expr {$base + $bit}]\]
           incr user_match_count
       }
       foreach {field idx} {
           m 32
           execute 33
           load 34
           store 35
           match 36
           select 37
       } {
           set_user_match ${rtop}/trigger_pkt_any\[0\]\[$trig\]\[$field\] ${itop}/trigger_pkt_any\[[expr {$base + $idx}]\]

逐段解释：

* 第 36~37 行：每个 trigger entry 的 flattened base 是 ``trig * 38``。
* 第 38~41 行：``tdata2`` 字段按 ``base + bit`` 映射。源文件实际循环覆盖 bit
  ``0`` 到 ``31``，这里截取前 14 个 bit。
* 第 42~49 行：``m``、``execute``、``load``、``store``、``match``、``select``
  映射到每个 trigger entry 内的 index ``32`` 到 ``37``。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 ``lsu`` label。
* 调用：Formality ``set_user_match``。
* 共享状态：``user_match_count`` 与 ``RPT_DIR``。

§8  EXU 拆分策略
--------------------------------------------------------------------------------------------------------------------------------------------

职责：:ref:`adr-0020` 记录了单体 ``eh2_exu`` 在该 Formality 版本下的
verify 难点。R3-C 使用 ``eh2_exu_alu_ctl``、``eh2_exu_mul_ctl``、
``eh2_exu_div_ctl`` 的子块报告替代 monolithic ``eh2_exu`` 进入 summary total。

§8.1  ``lec_exu.tcl`` — 单体 EXU 尝试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_exu.tcl:L10-L38``）：

.. code-block:: text

   set rtop r:/WORK/eh2_exu
   set itop i:/WORK/eh2_exu
   set user_match_count 0

   puts "FM: R3-C adding exu exu_npc_e4 packed-array matches"
   foreach bit [list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15] {
       set_user_match ${rtop}/exu_npc_e4\[0\]\[$bit\] ${itop}/exu_npc_e4\[[expr {$bit - 1}]\]
       incr user_match_count
       set_user_match ${rtop}/exu_flush_path_final\[0\]\[$bit\] ${itop}/exu_flush_path_final\[[expr {$bit - 1}]\]
       incr user_match_count
   }
   set_user_match ${rtop}/exu_flush_path_final_early\[0\]\[31\] ${itop}/exu_flush_path_final_early\[0\]
   incr user_match_count
   ...
   verify -level 1
   r3c_write_reports exu

逐段解释：

* 第 10~12 行：单体 EXU 的 reference 和 implementation top 都是 ``eh2_exu``。
* 第 15~21 行：``exu_npc_e4`` 与 ``exu_flush_path_final`` 从 packed index
  ``[0][bit]`` 映射到 flattened ``[bit-1]``。源文件循环覆盖 bit ``1`` 到 ``31``，
  片段截取到 ``15``。
* 第 22~23 行：``exu_flush_path_final_early[0][31]`` 映射到 implementation
  index ``0``。
* 第 36~37 行：verify 使用 ``-level 1``，说明该脚本不是普通 ``verify`` 默认调用。

接口关系：

* 被调用：诊断或历史 block-level 尝试。
* 调用：公共框架、``set_user_match``、``verify -level 1``。
* 共享状态：报告 label ``exu``。

§8.2  ``lec_exu_alu.tcl`` — ALU 子块
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_exu_alu.tcl:L1-L38``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_exu_alu_ctl
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

   puts "FM: R3-C EXU sub-block LEC alu"
   set TOP eh2_exu_alu_ctl
   set LABEL exu_alu
   ...
   puts "FM: R3-C adding alu predict_p_ff packed-struct matches"
   set_user_match ${rtop}/predict_p_ff\[ataken\] ${itop}/predict_p_ff\[8\]
   incr user_match_count
   set_user_match ${rtop}/predict_p_ff\[misp\] ${itop}/predict_p_ff\[5\]
   incr user_match_count
   set_user_match ${rtop}/predict_p_ff\[hist\]\[0\] ${itop}/predict_p_ff\[11\]
   incr user_match_count
   set_user_match ${rtop}/predict_p_ff\[hist\]\[1\] ${itop}/predict_p_ff\[12\]
   incr user_match_count

逐段解释：

* 第 2 行：ALU 子块预载 ``eh2_exu_alu_ctl`` 的 SVF。
* 第 5~7 行：Formality top 是 ``eh2_exu_alu_ctl``，summary label 是
  ``exu_alu``。
* 第 14~21 行：脚本只显式映射 ``predict_p_ff`` 中 4 个字段：
  ``ataken``、``misp``、``hist[0]``、``hist[1]``。
* 第 31~36 行（未在片段中展示）：映射后执行 ``match``、``verify`` 并调用
  ``r3c_write_reports exu_alu``。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 ``exu_alu`` label。
* 调用：公共框架与 ``set_user_match``。
* 共享状态：``R3C_PRELOAD_SVF_TOP=eh2_exu_alu_ctl``。

§8.3  ``lec_exu_mul.tcl`` 与 ``lec_exu_div.tcl`` — datapath 子块
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_exu_mul.tcl:L1-L36``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_exu_mul_ctl
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

   puts "FM: R3-C EXU sub-block LEC mul"
   set TOP eh2_exu_mul_ctl
   set LABEL exu_mul
   if {[info exists env(R3C_REPORT_LABEL)] && $env(R3C_REPORT_LABEL) ne ""} {
       set LABEL $env(R3C_REPORT_LABEL)
   }
   set verification_timeout_limit 0:5:0
   set verification_datapath_effort_level High
   if {[info exists env(R3C_FM_STRATEGY)] && $env(R3C_FM_STRATEGY) ne ""} {
       puts "FM: R3-C using MUL alternate strategy $env(R3C_FM_STRATEGY)"
       set_app_var verification_alternate_strategy $env(R3C_FM_STRATEGY)
   }

逐段解释：

* 第 2 行：MUL 子块预载 ``eh2_exu_mul_ctl`` 的 SVF。
* 第 6~10 行：默认报告 label 是 ``exu_mul``，但可通过
  ``R3C_REPORT_LABEL`` 覆盖。
* 第 11~12 行：MUL 设置 5 分钟 timeout 和 High datapath effort。
* 第 13~16 行：调用者可用 ``R3C_FM_STRATEGY`` 传入 Formality alternate strategy。

关键代码（``syn/scripts/lec_blocklevel/lec_exu_div.tcl:L1-L24``）：

.. code-block:: text

   set_app_var sh_continue_on_error false
   set env(R3C_PRELOAD_SVF_TOP) eh2_exu_div_ctl
   source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

   puts "FM: R3-C EXU sub-block LEC div"
   set TOP eh2_exu_div_ctl
   set LABEL exu_div
   set verification_timeout_limit 0:5:0

   set_top r:/WORK/$TOP
   r3c_read_impl $TOP
   r3c_set_impl_top $TOP
   r3c_load_svf $TOP

   puts "FM: R3-C matching $TOP"
   match

   puts "FM: R3-C verifying $TOP"
   verify -level 1
   r3c_write_reports $LABEL

逐段解释：

* 第 2 行：DIV 子块预载 ``eh2_exu_div_ctl`` 的 SVF。
* 第 6~8 行：DIV 的 summary label 是 ``exu_div``，timeout 同样为 5 分钟。
* 第 15~20 行：DIV 使用 ``match``、``verify -level 1``，然后写出
  ``exu_div`` 报告。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 的 ``exu_mul`` 和 ``exu_div`` label。
* 调用：公共框架、Formality strategy app vars、``verify -level 1``。
* 共享状态：``R3C_PRELOAD_SVF_TOP``、``R3C_REPORT_LABEL``、
  ``R3C_FM_STRATEGY``、``R3C_FM_PASSING_MODE``。

§9  诊断脚本
--------------------------------------------------------------------------------------------------------------------------------------------

职责：诊断脚本生成 failing、unmatched、analysis report，用于定位问题；
它们不是 release total 的汇总入口。release total 由
:file:`syn/scripts/lec_summary.py` 读取 block-level ``lec_<label>.rpt`` 得出。

§9.1  top-level 诊断脚本
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_diag.tcl:L27-L36``）：

.. code-block:: text

   match
   verify

   # Get failing points with correct syntax for O-2018.06
   report_failing_points > $BUILD_DIR/lec_failing.rpt

   # Automated analysis of failure causes
   analyze_points -all > $BUILD_DIR/lec_analyze.rpt

   report_status > $BUILD_DIR/lec_status.rpt

逐段解释：

* 第 27~28 行：诊断脚本仍运行 ``match`` 与 ``verify``，因此报告基于 Formality
  session 状态。
* 第 31 行：failing points 写入 :file:`syn/build/lec_failing.rpt`。
* 第 34 行：``analyze_points -all`` 输出 automated root-cause analysis。
* 第 36 行：status 另写 :file:`syn/build/lec_status.rpt`。

关键代码（``syn/scripts/lec_diag2.tcl:L27-L34``）：

.. code-block:: text

   # Report unmatched points (first 30 ref, 30 impl)
   puts "\n=== First 30 Unmatched REF Output Ports ==="
   report_unmatched_points -ref -port -max 30

   puts "\n=== First 30 Unmatched IMPL Output Ports ==="
   report_unmatched_points -impl -port -max 30

   exit 0

逐段解释：

* 第 28~29 行：脚本输出 reference 侧前 30 个 unmatched output ports。
* 第 31~32 行：脚本输出 implementation 侧前 30 个 unmatched output ports。
* 该脚本直接打印到 Formality log，没有写 summary 文件。

接口关系：

* 被调用：手工调试。
* 调用：``report_failing_points``、``analyze_points``、
  ``report_unmatched_points``。
* 共享状态：top-level Formality session。

§9.2  EXU 与 LSU block 诊断
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_blocklevel/lec_exu_match_diag.tcl:L24-L27``）：

.. code-block:: text

   match
   report_matched_points -last > $RPT_DIR/lec_exu_matched_last.rpt
   report_unmatched_points > $RPT_DIR/lec_exu_unmatched_points.rpt
   report_status > $RPT_DIR/lec_exu_match_status.rpt

逐段解释：

* 第 24 行：脚本只运行 matching，不执行完整 verify。
* 第 25~27 行：输出最近 matched points、unmatched points 和 match status，
  用于检查 EXU 映射是否干净。

关键代码（``syn/scripts/lec_blocklevel/lec_lsu_analyze.tcl:L55-L58``）：

.. code-block:: text

   match
   verify
   analyze_points -failing -effort low -limit 20 > $RPT_DIR/lec_lsu_analyze_points.rpt
   report_analysis_results > $RPT_DIR/lec_lsu_analysis_results.rpt

逐段解释：

* 第 55~56 行：LSU analysis 先完整执行 ``match`` 与 ``verify``。
* 第 57 行：只分析 failing points，effort 为 low，limit 为 20。
* 第 58 行：analysis result 单独写入 :file:`lec_lsu_analysis_results.rpt`。

接口关系：

* 被调用：手工 block-level 调试。
* 调用：Formality analysis/report 命令。
* 共享状态：``RPT_DIR`` 和各 block 的 user match 设置。

§10  ``lec_summary.py`` 汇总器
--------------------------------------------------------------------------------------------------------------------------------------------

职责：:file:`syn/scripts/lec_summary.py` 只解析真实 Formality 输出，不修改
tool output。它负责把 block-level ``lec_*.rpt`` 汇总成
:file:`syn/build/lec_summary.txt`，并在 EXU 子块报告存在时替代单体 EXU。

§10.1  模块清单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_summary.py:L9-L27``）：

.. code-block:: python

   SYN_ROOT = Path(__file__).resolve().parents[1]
   BUILD = SYN_ROOT / "build" / "lec_blocklevel"
   OUT = SYN_ROOT / "build" / "lec_summary.txt"

   BASE_MODULES = [
       ("eh2_dec", "dec"),
       ("eh2_lsu", "lsu"),
       ("eh2_pic_ctrl", "pic"),
       ("eh2_dma_ctrl", "dma"),
       ("eh2_dbg", "dbg"),
       ("eh2_ifu", "ifu"),
   ]

   EXU_SUBMODULES = [
       ("eh2_exu_alu_ctl", "exu_alu"),
       ("eh2_exu_mul_ctl", "exu_mul"),
       ("eh2_exu_div_ctl", "exu_div"),
   ]

逐段解释：

* 第 9~11 行：脚本从自身路径推导 :file:`syn/` 根目录、block-level report 目录和
  summary 输出路径。
* 第 13~20 行：基础模块包括 ``eh2_dec``、``eh2_lsu``、``eh2_pic_ctrl``、
  ``eh2_dma_ctrl``、``eh2_dbg``、``eh2_ifu``。
* 第 22~26 行：EXU 不以单体 ``eh2_exu`` 进入最终 total，而是拆成 ALU、MUL、DIV
  3 个子模块。

接口关系：

* 被调用：``syn/Makefile:block_lec`` 第 136 行。
* 调用：Python ``Path`` 与正则解析。
* 共享状态：读取 :file:`syn/build/lec_blocklevel`。

§10.2  ``parse_module()`` — 单模块报告解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_summary.py:L34-L63``）：

.. code-block:: python

   def parse_module(label):
       rpt = BUILD / f"lec_{label}.rpt"
       timeout_rpt = BUILD / f"lec_{label}_timeout_status.rpt"
       log = BUILD / f"lec_{label}.log"
       if not rpt.exists():
           return {
               "passing": 0,
               "failing": 0,
               "unverified": 0,
               "status": "MISSING",
               "note": "report missing",
           }

       source_rpt = rpt
       if timeout_rpt.exists() and timeout_rpt.stat().st_mtime > rpt.stat().st_mtime:
           source_rpt = timeout_rpt

       text = source_rpt.read_text(encoding="utf-8", errors="replace")
       passing = _extract_int(r"(\d+)\s+Passing compare points", text)
       failing = _extract_int(r"(\d+)\s+Failing compare points", text)

逐段解释：

* 第 35~37 行：每个 label 对应主 report、timeout status report 和 log。
* 第 38~45 行：主 report 不存在时返回 ``MISSING``，并把计数设为 0。
* 第 47~49 行：如果 timeout status report 比主 report 更新，则以 timeout report
  为解析源。
* 第 51~54 行：脚本用正则提取 passing、failing、unverified compare points。

关键代码（``syn/scripts/lec_summary.py:L56-L90``）：

.. code-block:: python

   if "Verification SUCCEEDED" in text and failing == 0 and unverified == 0:
       status = "PASS"
   elif "Verification FAILED" in text:
       status = "FAIL"
   elif "Verification INCONCLUSIVE" in text:
       status = "INCONCLUSIVE"
   else:
       status = "UNKNOWN"

   note = ""
   if source_rpt == timeout_rpt:
       note = "graceful timeout status"
   if log.exists():
       log_text = log.read_text(encoding="utf-8", errors="replace")
       if "Process terminated by kill" in log_text or "Received Signal 15" in log_text:
           if source_rpt == timeout_rpt:
               status = "INCONCLUSIVE"

逐段解释：

* 第 56~63 行：只有 report 文本包含 ``Verification SUCCEEDED`` 且 failing /
  unverified 都为 0 时，status 才是 ``PASS``。
* 第 65~67 行：使用 timeout report 时，note 设置为 ``graceful timeout status``。
* 第 68~74 行：如果 log 显示进程被 kill 或收到 signal 15，脚本根据 report 来源
  判断 status 是 ``INCONCLUSIVE`` 还是 ``TIMEOUT``。
* 第 79~82 行（未在片段中展示）：log 中出现 standalone DDC 或 standalone
  Verilog 读入信息时，note 会记录 implementation 来源。

接口关系：

* 被调用：``main()`` 对每个 module label 调用。
* 调用：``_extract_int()``、``Path.read_text()``、``Path.stat()``。
* 共享状态：读取 ``BUILD`` 下 report 和 log。

§10.3  ``main()`` — EXU 替代与 total 计算
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/scripts/lec_summary.py:L93-L120``）：

.. code-block:: python

   def main():
       rows = []
       total_passing = total_failing = total_unverified = 0

       exu_decomposed = all((BUILD / f"lec_{label}.rpt").exists() for _module, label in EXU_SUBMODULES)
       modules = [BASE_MODULES[0]]
       if exu_decomposed:
           modules.extend(EXU_SUBMODULES)
       else:
           modules.append(("eh2_exu", "exu"))
       modules.extend(BASE_MODULES[1:])

       for module, label in modules:
           data = parse_module(label)
           if label in ("exu_alu", "exu_mul", "exu_div"):
               data["note"] = "EXU sub-block decomposition"
           rows.append((module, label, data))

逐段解释：

* 第 97 行：只要 ``exu_alu``、``exu_mul``、``exu_div`` 3 个 report 都存在，
  ``exu_decomposed`` 就为真。
* 第 98~103 行：summary 总是先放 ``eh2_dec``；如果 EXU 子块齐全，则加入 3 个
  EXU 子块，否则退回单体 ``eh2_exu``；最后追加其余基础模块。
* 第 105~109 行：每个模块调用 ``parse_module``，并为 EXU 子块设置固定 note。

关键代码（``syn/scripts/lec_summary.py:L110-L159``）：

.. code-block:: python

       total_passing += int(data["passing"])
       total_failing += int(data["failing"])
       total_unverified += int(data["unverified"])

   if total_failing == 0 and total_unverified == 0:
       total_status = "PASS"
   elif total_failing < 30 and total_unverified == 0:
       total_status = "PARTIAL_PASS_LT30"
   else:
       total_status = "INCOMPLETE"
   ...
   OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
   print(OUT)
   print("\n".join(lines))

逐段解释：

* 第 110~112 行：total 是每个 row 的 passing、failing、unverified 数值求和。
* 第 114~119 行：只有 total failing 和 total unverified 都为 0，total status 才是
  ``PASS``。如果 failing 小于 30 且 unverified 为 0，则是
  ``PARTIAL_PASS_LT30``；其他情况是 ``INCOMPLETE``。
* 第 157~159 行：脚本把 markdown table 写入 :file:`syn/build/lec_summary.txt`，
  同时打印输出路径和正文。

接口关系：

* 被调用：脚本入口 ``if __name__ == "__main__"``。
* 调用：``parse_module()`` 与 ``OUT.write_text()``。
* 共享状态：``BASE_MODULES``、``EXU_SUBMODULES``、``BUILD``、``OUT``。

§11  签核数字与非 waiver 边界
--------------------------------------------------------------------------------------------------------------------------------------------

职责：LEC 数字必须从真实工具汇总中读取，不从源码注释或人工叙述推导。
当前 sign-off 结果为 ``31635/31635``，对应 9 个 block-level 模块。

§11.1  ``syn/build/lec_summary.txt`` 的结果表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/build/lec_summary.txt``）：

.. code-block:: text

   | Module | Passing | Failing | Unverified | Status | Note |
   |---|---:|---:|---:|---|---|
   | eh2_dec | 7160 | 0 | 0 | PASS | standalone DDC |
   | eh2_exu_alu_ctl | 294 | 0 | 0 | PASS | EXU sub-block decomposition |
   | eh2_exu_mul_ctl | 272 | 0 | 0 | PASS | EXU sub-block decomposition |
   | eh2_exu_div_ctl | 181 | 0 | 0 | PASS | EXU sub-block decomposition |
   | eh2_lsu | 3565 | 0 | 0 | PASS | standalone DDC |
   | eh2_pic_ctrl | 1573 | 0 | 0 | PASS | standalone DDC |
   | eh2_dma_ctrl | 967 | 0 | 0 | PASS | standalone DDC |
   | eh2_dbg | 571 | 0 | 0 | PASS | standalone DDC |
   | eh2_ifu | 17052 | 0 | 0 | PASS | standalone DDC |
   | TOTAL | 31635 | 0 | 0 | PASS | real tool output only |

逐段解释：

* ``eh2_dec``、``eh2_lsu``、``eh2_pic_ctrl``、``eh2_dma_ctrl``、``eh2_dbg``、
  ``eh2_ifu`` 来自基础 block 列表。
* ``eh2_exu_alu_ctl``、``eh2_exu_mul_ctl``、``eh2_exu_div_ctl`` 来自 EXU 子块
  decomposition，并替代单体 ``eh2_exu`` 进入 total。
* ``TOTAL`` 行给出 ``31635`` passing、``0`` failing、``0`` unverified 和
  ``PASS``。这就是当前文档中允许引用的 LEC sign-off 数字。

接口关系：

* 被调用：sign-off collector 通过 ``--lec-blocklevel --lec-summary-path`` 读取。
* 调用：无；这是生成报告。
* 共享状态：由 :file:`syn/scripts/lec_summary.py` 生成。

§11.2  非 waiver 边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``syn/build/lec_summary.txt``）：

.. code-block:: text

   Notes:
   - Reports are parsed from syn/build/lec_blocklevel/lec_*.rpt.
   - When lec_exu_alu/mul/div reports exist, they replace the older monolithic lec_exu result in TOTAL.
   - If a newer lec_<module>_timeout_status.rpt exists, it is used to avoid stale failed counts after a graceful timeout run.
   - TIMEOUT means the latest log was killed by timeout; the numeric counts come from the last completed report for that module.
   - A clean-match timeout means matching completed with 0 unmatched compare points, but verification did not finish.
   - No set_dont_verify_points waiver is used by this summary.

逐段解释：

* 第 1 条说明 summary 只解析 :file:`syn/build/lec_blocklevel/lec_*.rpt`，不解析手写
  markdown 或人工表格。
* 第 2 条说明 EXU 子块替代单体 EXU 的 total 规则，与
  :file:`syn/scripts/lec_summary.py` 第 97~103 行一致。
* 第 3~5 条说明 timeout report 的优先级与状态含义。
* 第 6 条是 release 边界：summary 未使用 ``set_dont_verify_points`` waiver。

接口关系：

* 被调用：release 文档、sign-off 状态页和本章引用。
* 调用：无。
* 共享状态：必须与 :ref:`adr-0020` 的 non-waiving 约束保持一致。

§12  常见误读与排查路径
--------------------------------------------------------------------------------------------------------------------------------------------

职责：把 LEC 失败或超时分清为工具匹配问题、block-level 收敛问题、report
缺失问题，避免把不同阶段的脚本结果混为一个 sign-off 结论。

§12.1  top-level failure 不等于 block-level release failure
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``lec_run.tcl``、``lec_svf.tcl``、``lec_p0a.tcl``、``lec_rc4_fix.tcl`` 都是
top-level ``eh2_veer`` 尝试。:ref:`adr-0019` 记录了 O-2018.06-SP1 的
packed-port limitation；:ref:`adr-0020` 记录了选择 block-level closure
path。阅读报告时应先确认它来自：

* :file:`syn/build/lec_report.txt` 或 :file:`syn/build/lec_rc4_report.txt`：
  top-level 实验报告。
* :file:`syn/build/lec_blocklevel/lec_<label>.rpt`：block-level Formality 报告。
* :file:`syn/build/lec_summary.txt`：当前 sign-off 读取的汇总报告。

§12.2  report missing 的处理边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

如果 :file:`lec_summary.py` 找不到某个 :file:`lec_<label>.rpt`，它返回
``status="MISSING"``、三项计数为 0，并写出 ``note="report missing"``。这不是
PASS。正确处理路径是重新运行 ``make -C syn block_lec`` 或检查对应
``fm_shell`` log，而不是手工补写 summary。

§12.3  timeout 与 inconclusive 的处理边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``lec_summary.py`` 在 log 中发现 ``Process terminated by kill`` 或
``Received Signal 15`` 时，会根据 timeout status report 是否更新来设置
``INCONCLUSIVE`` 或 ``TIMEOUT``。这说明脚本把"最近 run 被杀掉"与"最后完成报告
中的数字"分开处理。文档引用 release 数字时必须以当前
:file:`syn/build/lec_summary.txt` 的最终表格为准。

§13  参考资料
--------------------------------------------------------------------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0019` — 记录 Synopsys O-2018.06-SP1 top-level LEC packed-port
  工具限制。
* :ref:`adr-0020` — 记录 R3-C block-level LEC closure path 与 EXU 子块替代。

关联章节：

* :doc:`../06_flows/lec_flow` — LEC 流程入口说明。
* :doc:`syn_nangate` — Design Compiler / Nangate 相关脚本字典。
* :doc:`syn_yosys` — Yosys 综合脚本字典。

源文件绝对路径：

* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/syn/Makefile`
* :file:`/home/host/eh2-veri/syn/scripts/lec_run.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_svf.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_p0a.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_rc4_fix.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_matching.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_user_match.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_dec.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_ifu.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_lsu.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu_alu.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu_mul.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_exu_div.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_dbg.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_dma.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_pic.tcl`
* :file:`/home/host/eh2-veri/syn/scripts/lec_summary.py`
* :file:`/home/host/eh2-veri/docs/adr/0019-lec-tool-version-limitation.md`
* :file:`/home/host/eh2-veri/docs/adr/0020-blocklevel-lec.md`

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
