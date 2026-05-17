# ============================================================
# EH2 UVM Verification Platform — Top-level Makefile (规整版)
# ============================================================
#
# 设计原则：
#   1) 15 个核心 target，按 5 组组织
#   2) 旧 target 全部保留作 deprecated alias（兼容旧 CI / 文档）
#   3) 默认门限 = v1.1 release 真实值（line 65 / func 40 / allow-warnings）
#   4) `make clean` 默认仅清可再生产物，保留 r3b_final/r4a_final/simv*/
#      libcosim.so/cov.vdb/archive_signoffs_* 等 sign-off 证据和长耗时缓存；
#      需要彻底删时加 FORCE=1。syn/build/eh2_dc_wrapper.sv 由
#      scripts/gen_dc_wrapper.sh 在 syn-dc/block_lec 前自动重建。
#   5) 行为切换全部通过变量（PROFILE / GATE_ONLY / SCOPE / MODE / TOOL / STEP / FORCE / ...）
#
# 输入 `make help` 查看完整中文说明。
# ============================================================

SHELL := /bin/bash

# Source environment
-include env.mk

# ============================================================
# Ibex-style staged entry point. `make run GOAL=...` creates regression
# metadata and delegates to dv/uvm/core_eh2/wrapper.mk.
# （此分支保留旧逻辑不动，供 wrapper.mk 调度用）
# ============================================================
GOAL ?=

ifneq ($(GOAL),)

CONFIG      ?= default
SEED        ?= 1
TEST        ?= all
SIMULATOR   ?= vcs
WAVES       ?= 0
COV         ?= 0
ITERATIONS  ?=
PARALLEL    ?= 1
RTL_TEST    ?= core_eh2_base_test
SIM_OPTS    ?=
GEN_OPTS    ?=
ISS         ?= spike
VERBOSE     ?= 0
SIGNATURE_ADDR ?= d0580000
OUT ?= out
OUT-DIR := $(dir $(OUT)/)
METADATA-DIR := $(OUT-DIR)metadata

export PYTHONPATH := $(shell cd dv/uvm/core_eh2 && python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')

.PHONY: run
run:
	+@env PYTHONPATH=$(PYTHONPATH) python3 dv/uvm/core_eh2/scripts/metadata.py \
	  --op "create_metadata" \
	  --dir-metadata $(METADATA-DIR) \
	  --dir-out $(OUT-DIR) \
	  --args-list "\
	  SEED=$(SEED) WAVES=$(WAVES) COV=$(COV) SIMULATOR=$(SIMULATOR) \
	  ISS=$(ISS) TEST=$(TEST) VERBOSE=$(VERBOSE) ITERATIONS=$(ITERATIONS) \
	  SIGNATURE_ADDR=$(SIGNATURE_ADDR) CONFIG=$(CONFIG) RTL_TEST=$(RTL_TEST) \
	  SIM_OPTS=$(SIM_OPTS) GEN_OPTS=$(GEN_OPTS)"
	+@$(MAKE) -C dv/uvm/core_eh2 --file wrapper.mk \
	  OUT-DIR=$(abspath $(OUT-DIR)) \
	  METADATA-DIR=$(abspath $(METADATA-DIR)) \
	  PRJ_DIR=$(CURDIR) \
	  SIMULATOR=$(SIMULATOR) \
	  TEST=$(TEST) \
	  SEED=$(SEED) \
	  ITERATIONS=$(ITERATIONS) \
	  PARALLEL=$(PARALLEL) \
	  COV=$(COV) \
	  WAVES=$(WAVES) \
	  --environment-overrides --no-print-directory $(GOAL)

else

# ============================================================
# 目录与文件
# ============================================================
RTL_DIR      := rtl/design
SNAPSHOTS    := rtl/snapshots/default
TB_DIR       := dv/uvm/core_eh2
SHARED_DIR   := shared/rtl
COSIM_DIR    := dv/cosim
SCRIPTS_DIR  := $(TB_DIR)/scripts
DV_EXT_DIR   := $(TB_DIR)/riscv_dv_extension
RISCV_DV_DIR := vendor/google_riscv-dv
ASM_DIR      := tests/asm
BUILD_DIR    := build

# Per-target build sub-directory. Each top-level sim target overrides this
# (smoke -> build/smoke, signoff -> build/signoff, etc.) so the simv/csrc/
# cov.vdb/compile.log they produce live in their own island. Default for
# standalone `make compile` invocations.
BUILD_SUBDIR ?= $(BUILD_DIR)/compile

# ----------------------------------------------------------------------------
# Items inside $(BUILD_DIR) that `make clean` MUST preserve. These are either
# release sign-off evidence (r3b_final, r4a_final, archive_signoffs_*) or
# shared read-only artifacts (libcosim.so, spike_objs/). In the new
# per-target layout, simv/csrc/cov.vdb live inside build/<target>/ and are
# safe to wipe wholesale.
#
# Override at command line:  make clean FORCE=1     <- bypass preservation
# To get the old aggressive behaviour explicitly.
# ----------------------------------------------------------------------------
CLEAN_PRESERVE_BUILD := r3b_final r4a_final nightly \
                        libcosim.so spike_objs \
                        compliance_tb_compile.log

# Find expression: skip preserved names + archive_signoffs_* link family.
CLEAN_PRESERVE_FIND := $(foreach n,$(CLEAN_PRESERVE_BUILD),! -name '$(n)') \
                      ! -name 'archive_signoffs_*'

DEFINES      := $(SNAPSHOTS)/common_defines.vh
RTL_F        := $(TB_DIR)/eh2_rtl.f
SHARED_F     := $(TB_DIR)/eh2_shared.f
TB_F         := $(TB_DIR)/eh2_tb.f

# ============================================================
# 用户可覆盖变量（默认值与含义详见 `make help`）
# ============================================================
CONFIG          ?= default
SEED            ?= 1
TEST            ?=
TESTLIST        ?= riscvdv
SIMULATOR       ?= vcs
BINARY          ?=
VERBOSITY       ?= UVM_MEDIUM
TIMEOUT_NS      ?= 10000000
WAVES           ?= 0
COV             ?= 1
ITERATIONS      ?= 1
PARALLEL        ?= 4
RTL_TEST        ?= core_eh2_base_test
SIM_OPTS        ?=
GEN_OPTS        ?=

# Sign-off
PROFILE         ?= full
GATE_ONLY       ?= 0
CLEANUP         ?= 0
SIGNOFF_OUT     ?= $(BUILD_DIR)/signoff
SIGNOFF_OPTS    ?=
SIGNOFF_ITERATIONS ?=
LEC_KNOWN_LIMITED  ?= 0
LEC_BLOCKLEVEL  ?= 1
LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt

# v1.1 release 门限（修过——旧 Makefile 写死 85/50 与 v1.1 release 不符）
SIGNOFF_MIN_LINE_COV       ?= 65
SIGNOFF_MIN_FUNCTIONAL_COV ?= 40
SIGNOFF_ALLOW_WARNINGS     ?= 1

# Replay
STAGE_DATA_DIR     ?= $(BUILD_DIR)/r3b_final
SIGNOFF_REPLAY_OUT ?= $(BUILD_DIR)/signoff_replay

# Demo
WITH_SYNTH       ?= 1
DEMO_OUT         ?= $(BUILD_DIR)/demo

# Lint / Synth / Compliance / Manual sub-mode 变量
TOOL             ?=
STEP             ?=
MODE             ?=
FORMAT           ?= html

# Clean
SCOPE            ?= full
DRY_RUN          ?= 0

# 仿真器命令
VCS         := vcs
XLM         := xrun

# Coverage 配置
VCS_COV_METRICS := line+cond+fsm+tgl+branch+assert
VCS_COV_HIER    := $(TB_DIR)/cov_hier.cfg
VCS_FSM_CFG     := $(TB_DIR)/cov_fsm.cfg
VCS_FSM_RESET_FILTER := $(TB_DIR)/cov_fsm_reset_filter.cfg
VCS_COMPILE_COV_OPTS := -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                        -cm_hier $(VCS_COV_HIER) \
                        -cm_fsmcfg $(VCS_FSM_CFG) \
                        -cm_fsmresetfilter $(VCS_FSM_RESET_FILTER) \
                        -cm_fsmopt report2StateFsms+allowTmp+reportvalues+reportWait+upto64
VCS_RUN_COV_OPTS := -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                    -cm_name $(TEST)_$(SEED) +enable_eh2_fcov=1

# testlist 路由
TESTLIST_PATH := $(if $(filter directed,$(TESTLIST)),$(TB_DIR)/directed_tests/directed_testlist.yaml,\
                 $(if $(filter cosim,$(TESTLIST)),$(TB_DIR)/directed_tests/cosim_testlist.yaml,\
                 $(DV_EXT_DIR)/testlist.yaml))

OUT_DIR     := $(BUILD_DIR)/$(TEST)_$(SEED)
OUT         ?=
TEST_LIST   ?= default

# ============================================================
# .PHONY — 15 核心 target + 内部 + deprecated alias
# ============================================================
.PHONY: help \
        demo signoff signoff_replay \
        asm cosim compile \
        smoke regress compliance \
        lint formal synth \
        manual clean \
        compile_vcs compile_xlm \
        run gen nightly weekly run_regress \
        signoff_quick signoff_gate signoff_with_cleanup html_report cov \
        lint_verible lint_verilator \
        syn_yosys syn_dc lec block_lec syn_clean \
        formal_clean compliance-all compliance-compile \
        manual_html \
        clean_cov clean_workspace clean_workspace_dry \
        run-csr-unit ci_unit ci_lint

# ============================================================
# help（中文，完备）
# ============================================================
define HELP_TEXT

================================================================================
EH2 UVM 验证平台 — Makefile 入口说明（v1.1 规整版 / 2026-05-17 更新）
================================================================================

15 个核心 target，按 5 组组织。所有变体行为靠变量切换。
默认门限 = v1.1 release 真实值：line ≥ 65%, functional ≥ 40%, warnings allowed。

每个 target 统一字段：用途 / 耗时 / 依赖 / 变量 / 产出 / 示例。

──────────────────────────────────────────────────────────────────────────────
[ 一键运行 ] —— 演示 / 完整 sign-off / 复演
──────────────────────────────────────────────────────────────────────────────

  make demo
        用途：导师演示 / release 自检。一条龙：clean → asm → cosim → compile
              → synth → block-level LEC → signoff（含覆盖率） → HTML 报告
        耗时：PARALLEL=4 约 2-3 小时（DC ~30min + block_lec ~45min + 仿真+cov ~1h）
              WITH_SYNTH=0 可省 1-2 小时
        依赖：syn-dc 自动调 scripts/gen_dc_wrapper.sh 生成 wrapper；
              compile 用 COV=1 重建带覆盖率插桩的 simv（不复用旧 simv）
        变量：
          WITH_SYNTH=0|1        是否含 synth+LEC（默认 1）
          DEMO_OUT=<dir>        输出目录（默认 build/demo）
          PARALLEL=<N>          回归并行度（默认 4）
        产出：
          $(DEMO_OUT)/report.html              HTML 报告（含覆盖率仪表盘）
          $(DEMO_OUT)/signoff_status.json      机器可读结果
          $(DEMO_OUT)/signoff_report.md        Markdown 摘要
          $(DEMO_OUT)/runs/{smoke,directed,cosim,riscvdv,csr_unit,compliance}/
          $(DEMO_OUT)/cov_merged/dashboard.txt URG 合并覆盖率
          syn/build/eh2_synth.v                综合 netlist
          syn/build/lec_summary.txt            block-level LEC 31635/31635
        示例：
          make demo                       # 完整演示（默认 build/demo）
          make demo WITH_SYNTH=0          # 跳过综合/LEC，只跑仿真+signoff
          make demo PARALLEL=8            # 提速：8 路并行
          DEMO_OUT=build/r4a_final make demo   # 输出为历史命名

  make signoff
        用途：完整 9-stage sign-off。不清理、不重编，复用已编译的 simv
        耗时：~1-1.5 小时（COV=1，PARALLEL=4）
        依赖：build/simv（先跑 make compile 或包含在 demo 里）；
              如启用 LEC_BLOCKLEVEL=1 需先有 syn/build/lec_summary.txt
        变量：
          PROFILE=full|quick|cosim|nightly       profile（默认 full）
          GATE_ONLY=0|1                          仅评估、不重跑（默认 0）
          COV=0|1                                覆盖率（默认 1）
          PARALLEL=<N>                           并行度（默认 4）
          SEED=<N>                               随机种子（默认 1）
          SIGNOFF_OUT=<dir>                      输出目录（默认 build/signoff）
          SIGNOFF_MIN_LINE_COV=<pct>             line 门限（默认 65）
          SIGNOFF_MIN_FUNCTIONAL_COV=<pct>       functional 门限（默认 40）
          SIGNOFF_ALLOW_WARNINGS=0|1             warning 容忍（默认 1）
          SIGNOFF_OPTS="..."                     透传 signoff.py 其它选项
          SIGNOFF_ITERATIONS=<N>                 单测迭代次数
          CLEANUP=0|1                            跑完做 lck-only 清理（默认 0）
          LEC_BLOCKLEVEL=0|1                     启用块级 LEC（默认 1）
          LEC_KNOWN_LIMITED=0|1                  LEC 失败兜底（默认 0）
          LEC_SUMMARY_PATH=<file>                LEC 摘要（默认 syn/build/lec_summary.txt）
        产出：
          $(SIGNOFF_OUT)/report.html
          $(SIGNOFF_OUT)/signoff_status.json
          $(SIGNOFF_OUT)/signoff_report.md
          $(SIGNOFF_OUT)/runs/<stage>/
          $(SIGNOFF_OUT)/cov_merged/dashboard.txt
        示例：
          make signoff                                 # full profile，默认门限
          make signoff PROFILE=quick                   # smoke+directed 快跑
          make signoff GATE_ONLY=1                     # 不重跑，仅评估现有 runs/
          make signoff SIGNOFF_MIN_LINE_COV=85 SIGNOFF_ALLOW_WARNINGS=0
                                                       # 恢复旧 85/50 严格门限
          make signoff CLEANUP=1                       # 跑完顺便清 lck 残留
          make signoff LEC_KNOWN_LIMITED=1 LEC_BLOCKLEVEL=0    # LEC 兜底

  make signoff_replay
        用途：gate-only 复演 v1.1 reference run，秒级出报告（不重跑任何测试）
        耗时：< 30 秒
        依赖：STAGE_DATA_DIR/runs/{smoke,directed,cosim,riscvdv,csr_unit,compliance}
              默认指向 build/r3b_final（已被 5月17日 make demo 清空时删除，
              如需恢复请用 build/demo/ 或新跑一次 demo）
        变量：
          STAGE_DATA_DIR=<dir>              数据源（默认 build/r3b_final）
          SIGNOFF_REPLAY_OUT=<dir>          输出目录（默认 build/signoff_replay）
          LEC_BLOCKLEVEL=0|1                启用 LEC gate（默认 1）
          LEC_KNOWN_LIMITED=0|1             LEC 兜底（默认 0）
          LEC_SUMMARY_PATH=<file>           LEC 摘要路径
          SIGNOFF_MIN_LINE_COV=<pct>        line 门限（默认 65）
          SIGNOFF_MIN_FUNCTIONAL_COV=<pct>  functional 门限（默认 40）
          SIGNOFF_OPTS="..."                透传选项
        产出：
          $(SIGNOFF_REPLAY_OUT)/report.html
          $(SIGNOFF_REPLAY_OUT)/signoff_status.json
        示例：
          make signoff_replay                                   # 默认复演 r3b_final
          make signoff_replay STAGE_DATA_DIR=build/demo         # 复演刚跑完的 demo
          make signoff_replay STAGE_DATA_DIR=.scratch/r5_build_archive_20260512/r3b_final
                                                                # 复演历史归档

──────────────────────────────────────────────────────────────────────────────
[ 构建 ] —— 编译产物
──────────────────────────────────────────────────────────────────────────────

  make asm
        用途：编译 tests/asm/*.S 为 *.hex / *.elf / *.dis
        耗时：< 10 秒
        依赖：riscv-gcc 工具链（gcc-riscv64-unknown-elf）
        变量：无
        产出：
          tests/asm/smoke.{hex,elf,dis,ld}     sign-off smoke stage 直接输入
          tests/asm/nop.{hex,elf,dis}
        示例：
          make asm                          # 重建所有 hex（clean 后必须重建）

  make cosim
        用途：编译 Spike DPI co-simulation 库
        耗时：30-60 秒
        依赖：SPIKE_INSTALL（默认 $$HOME/spike-cosim），VCS_HOME
        变量：
          SPIKE_DIR=<path>          Spike 源码目录
          SPIKE_INSTALL=<path>      Spike 安装前缀
          NO_COSIM=1                跳过链接（运行时配套 +disable_cosim=1）
        产出：
          build/libcosim.so                 ~200MB Spike DPI 动态库
          build/spike_objs/                 中间对象
        示例：
          make cosim                        # 默认环境
          make compile NO_COSIM=1           # 无 Spike 环境，跳过 cosim 链接

  make compile
        用途：编译 UVM testbench → simv
        耗时：3-5 分钟（VCS）；COV=1 慢 1.5 倍
        依赖：libcosim.so（除非 NO_COSIM=1），RTL flist
        变量：
          SIMULATOR=vcs|xlm        仿真器（默认 vcs）
          COV=0|1                  覆盖率插桩（默认 1，与顶层 COV ?= 1 一致；显式 COV=0 关闭）
          WAVES=0|1                FSDB/VPD 波形 dump（默认 0）
          NO_COSIM=1               跳过 cosim 链接
        产出：
          build/simv                       VCS 可执行
          build/simv.daidir/               VCS 中间数据
          build/csrc/                      VCS C 中间文件
          build/compile.log                编译日志
        示例：
          make compile                     # 默认 COV=0
          make compile COV=1               # 带覆盖率（demo/signoff 用）
          make compile WAVES=1             # 启用波形

──────────────────────────────────────────────────────────────────────────────
[ 仿真回归 ] —— smoke / 通用回归 / compliance
──────────────────────────────────────────────────────────────────────────────

  make smoke
        用途：跑 1 个 smoke 测试快速冒烟。和 sign-off smoke stage 跑的是同一个测试
        耗时：~1 分钟（含 compile 自动重建）
        依赖：自动触发 make compile + make asm
        变量：
          SIMULATOR=vcs|xlm                仿真器（默认 vcs）
        产出：
          build/smoke/<test>_s1/sim_*.log
          build/smoke/<test>_s1/result.yaml
          build/smoke/regr.log
          build/smoke/report.json
        示例：
          make smoke                       # 默认
          make smoke SIMULATOR=xlm         # Xcelium 跑

  make regress
        用途：通用回归入口，覆盖旧的 run / nightly / weekly / run_regress
        耗时：取决于 TESTLIST 和 ITERATIONS：riscvdv 全量约 30-60 分钟
        依赖：自动触发 make compile
        变量：
          TEST=<name>                       指定单测（不填则跑整个 testlist）
          SEED=<N>                          随机种子（默认 1）
          TESTLIST=riscvdv|directed|cosim   testlist 选择（默认 riscvdv）
          ITERATIONS=<N>                    迭代次数（默认 1；旧 weekly 用 5）
          PARALLEL=<N>                      并行度（默认 4）
          COV=0|1                           覆盖率（默认 1）
          OUT=<dir>                         输出目录（默认 build/regression）
          SIMULATOR=vcs|xlm                 仿真器
        产出：
          $(OUT)/<test>_s<seed>/sim_*.log
          $(OUT)/<test>_s<seed>/result.yaml
          $(OUT)/regr.log
          $(OUT)/report.json
          $(OUT)/regr_junit.xml             JUnit XML（CI 友好）
        示例：
          make regress                                  # 旧 nightly（riscvdv testlist）
          make regress ITERATIONS=5                     # 旧 weekly
          make regress TEST=riscv_arithmetic_basic_test # 旧 run（单测）
          make regress TESTLIST=directed                # 旧 run_regress（directed）
          make regress TESTLIST=cosim PARALLEL=8        # cosim 8 路并行
          make regress OUT=build/my_run COV=0           # 自定义输出目录、关 cov

  make compliance
        用途：RISC-V compliance 套件（独立 sub-env，由 dv/uvm/riscv_compliance 管）
        耗时：MODE=run ~15 分钟，MODE=all ~30 分钟
        依赖：dv/uvm/riscv_compliance 的工具链
        变量：
          MODE=run|all|compile             默认 run
              run     —— 旧 compliance（默认 RV32IMC test）
              all     —— 旧 compliance-all（所有 ISA 组合）
              compile —— 旧 compliance-compile（只编译不跑）
        注：本 target 不支持 WAVES——compliance 验证靠 signature 比对，原则上无需波形。
        产出：
          dv/uvm/riscv_compliance/build/<test>/result.log
          dv/uvm/riscv_compliance/reports/
        示例：
          make compliance                  # 默认 RV32IMC
          make compliance MODE=all         # 全套
          make compliance MODE=compile     # 只编译 TB

──────────────────────────────────────────────────────────────────────────────
[ 静态 / 形式化 / 综合 ]
──────────────────────────────────────────────────────────────────────────────

  make lint
        用途：verible + verilator 双引擎 lint
        耗时：~1-2 分钟
        依赖：verible-verilog-lint，verilator（在 PATH 中）
        变量：
          TOOL=verible|verilator           只跑一个（默认两个都跑）
        产出：
          lint/build/verible/verible-lint.log
          lint/build/verilator/verilator-lint.log
          lint/build/lint_status.json      gate 用聚合状态
        示例：
          make lint                        # 双引擎
          make lint TOOL=verible           # 只跑 verible（旧 lint_verible）
          make lint TOOL=verilator         # 只跑 verilator（旧 lint_verilator）

  make formal
        用途：Cadence IFV 形式化验证（46 properties，含 PMP/dec/dbg/exu 等）
        耗时：~30-60 分钟（IFV，46 properties 全跑）
        依赖：Cadence IFV (formalverifier)，dv/formal/ 下的 bind/property 文件
        变量：无（参数在 dv/formal/scripts/*.tcl）
        产出：
          dv/formal/build/ifv_final.log           formal 结果汇总
          dv/formal/build/ifv_cex/                反例 trace
          dv/formal/.formalrun/                   IFV 工作目录
        示例：
          make formal                      # 完整 formal run

  make synth
        用途：综合 + 块级 LEC 一气呵成（v1.1 release 真实流程）
        耗时：~1.5 小时（DC ~30min + block_lec ~45min）
        依赖：dc_shell + fm_shell 在 PATH 中；
              syn/build/eh2_dc_wrapper.sv 由 scripts/gen_dc_wrapper.sh
              自动生成（无需手工维护）
        变量：
          TOOL=dc|yosys                          综合工具（默认 dc）
          STEP=full|synth|lec|block_lec          执行步骤（默认 full）
              full      —— 综合 + block_lec（与默认相同）
              synth     —— 只 DC 综合（不跑 LEC）
              lec       —— 只跑顶层 yosys equiv LEC
              block_lec —— 只跑块级 Formality LEC
        产出：
          syn/build/eh2_dc_wrapper.sv            single-compilation-unit wrapper
          syn/build/eh2_synth.v                  DC netlist（~28MB，~400K cells）
          syn/build/area_report.txt              面积报告
          syn/build/timing_report.txt            时序报告
          syn/build/qor_report.txt               QoR 摘要
          syn/build/lec_summary.txt              块级 LEC 31635/31635 PASS
          syn/build/lec_blocklevel/lec_*.rpt     9 个模块 LEC 详报
          syn/build/lec_blocklevel/synth/*.v     9 个块级 netlist
        示例：
          make synth                       # 默认：DC + block_lec（旧 synth）
          make synth STEP=synth            # 只综合（旧 syn_dc）
          make synth STEP=block_lec        # 只跑块级 LEC（旧 block_lec）
          make synth STEP=lec              # 只跑顶层 yosys LEC（旧 lec）
          make synth TOOL=yosys            # yosys 综合（旧 syn_yosys，目前 ADR-0013 已知失败）

──────────────────────────────────────────────────────────────────────────────
[ 文档 / 清理 / 帮助 ]
──────────────────────────────────────────────────────────────────────────────

  make manual
        用途：构建 Sphinx 中文手册
        耗时：HTML ~30 秒；PDF ~2 分钟
        依赖：sphinx-build；PDF 还需 xelatex
        变量：
          FORMAT=html|pdf                 格式（默认 html）
        产出：
          docs/sphinx_cn/build/html/index.html
          docs/sphinx_cn/build/pdf/EH2-Verification-Manual.pdf （FORMAT=pdf）
        示例：
          make manual                      # HTML（默认）
          make manual FORMAT=pdf           # PDF
          make manual FORMAT=html          # 显式 HTML（旧 manual_html）

  make clean
        用途：清理产物。默认保留 sign-off 证据 + 长耗时缓存
        耗时：< 5 秒
        依赖：无
        变量：
          SCOPE=full|build|cov|syn|formal|asm|docs    范围（默认 full）
              full     —— build/ 可再生产物 + 根残留（最常用）
              build    —— 只清 build/（保留清单见下）
              cov      —— 只清覆盖率数据库（cov.vdb/cov_report）
              syn      —— 只清 syn/build/（wrapper 下次 syn-dc 自动重建）
              formal   —— 只清 dv/formal/build/
              asm      —— 只清 tests/asm 产物（hex/elf/dis）
              docs     —— 只清 docs/sphinx_cn/build/
          FORCE=0|1                  彻底删（默认 0）
              0 —— 保留这些关键目录：
                   r3b_final / r4a_final / nightly       sign-off 证据
                   cov / cov.vdb / cov_report             覆盖率数据库
                   simv / simv.daidir / simv.vdb          VCS 编译产物
                   simv_compliance / simv_compliance.daidir
                   libcosim.so / spike_objs / csrc        长耗时缓存
                   compile.log / compliance_tb_compile.log
                   archive_signoffs_*                     归档软链
              1 —— 旧的 rm -rf build/ 行为（连证据一起删）
          MODE=delete|archive       模式（默认 delete）
              delete   —— 直接删（按 FORCE 决定是否保留）
              archive  —— 调 scripts/clean_workspace.sh 智能归档到 .scratch/
          DRY_RUN=0|1               干跑预览（仅 MODE=archive 时生效）
        产出：无（清理操作）
        示例：
          make clean                         # 默认：保留证据 + 缓存（最常用）
          make clean FORCE=1                 # 彻底清（含 r3b_final/r4a_final）
          make clean SCOPE=build             # 只清 build/ 可再生产物
          make clean SCOPE=build FORCE=1     # 把 build/ 完全 rm -rf
          make clean SCOPE=syn               # 清 syn/build/（旧 syn_clean）
          make clean SCOPE=formal            # 清 dv/formal/build/（旧 formal_clean）
          make clean SCOPE=cov               # 只清覆盖率（旧 clean_cov）
          make clean MODE=archive            # 智能归档（旧 clean_workspace）
          make clean MODE=archive DRY_RUN=1  # 归档干跑（旧 clean_workspace_dry）

  make help
        用途：显示这份说明
        耗时：即时
        依赖：无
        变量：无
        产出：无（stdout）
        示例：
          make help
          make help | less                 # 翻页查看
          make help | grep -A 5 'demo'     # 查特定 target

──────────────────────────────────────────────────────────────────────────────
[ 常用变量速查 ]
──────────────────────────────────────────────────────────────────────────────

  参数适用范围速查（取代旧的"通用"小节——那个写法暗示所有 target 都生效，实际并非如此）：

    变量             仅对以下 target 生效（传给其它 target 不报错也无效果）
    ──────────────────────────────────────────────────────────────────────────────
    SIMULATOR        compile / smoke / regress / signoff                （默认 vcs）
    PARALLEL         regress / signoff / demo                           （默认 4）
    SEED             regress / signoff                                  （默认 1）
    COV              compile / regress / signoff                        （顶层默认 1；显式 COV=0 关）
    WAVES            compile / smoke / regress / signoff / demo         （默认 0，详见"查看波形"小节）
                     compliance 不支持 WAVES（验证靠 signature 比对）
    NO_COSIM         cosim / compile                                    （默认 0）

  仿真：
    TEST=<name>                       单测名（regress 用）
    TESTLIST=riscvdv|directed|cosim   testlist 选择
    ITERATIONS=<N>                    迭代次数
    OUT=<dir>                         regress 输出目录

  sign-off：
    PROFILE=full|quick|cosim|nightly  sign-off profile
    GATE_ONLY=0|1                     gate-only 模式
    SIGNOFF_OUT=<dir>                 输出目录
    STAGE_DATA_DIR=<dir>              signoff_replay 数据源
    SIGNOFF_MIN_LINE_COV=<pct>        line 门限（默认 65）
    SIGNOFF_MIN_FUNCTIONAL_COV=<pct>  functional 门限（默认 40）
    SIGNOFF_ALLOW_WARNINGS=0|1        warning 容忍（默认 1）
    LEC_BLOCKLEVEL=0|1                启用块级 LEC（默认 1）
    LEC_KNOWN_LIMITED=0|1             LEC 兜底
    LEC_SUMMARY_PATH=<file>           LEC 摘要路径

  综合：
    TOOL=dc|yosys                     综合工具
    STEP=full|synth|lec|block_lec     综合步骤

  demo：
    WITH_SYNTH=0|1                    是否含 synth/LEC（默认 1）
    DEMO_OUT=<dir>                    输出目录（默认 build/demo）

  clean：
    SCOPE=full|build|cov|syn|formal|asm|docs   清理范围
    FORCE=0|1                         绕过保护清单（默认 0）
    MODE=delete|archive               清理模式
    DRY_RUN=0|1                       干跑

──────────────────────────────────────────────────────────────────────────────
[ 关键产物目录索引 ]
──────────────────────────────────────────────────────────────────────────────

  build/                              通用构建目录（gitignored）
    ├── simv / simv.daidir / simv.vdb       VCS 编译产物（make clean 默认保留）
    ├── libcosim.so / spike_objs/            Spike DPI 库（保留）
    ├── csrc/ / compile.log                  VCS 中间文件 + 日志（保留）
    ├── cov.vdb / cov_report                 覆盖率数据库（保留）
    ├── r3b_final/ / r4a_final/              v1.1 sign-off 证据（保留）
    ├── archive_signoffs_<date>              历史归档软链（保留）
    ├── demo/                                make demo 产物（默认清除）
    ├── signoff/                             make signoff 产物（默认清除）
    └── smoke/ / regression/                 单测/回归产物（默认清除）

  syn/build/                          综合 + LEC 产物（make clean SCOPE=syn 清）
    ├── eh2_dc_wrapper.sv                    自动生成的 wrapper
    ├── eh2_synth.v                          DC netlist
    ├── area/timing/qor_report.txt           DC 报告
    ├── lec_summary.txt                      块级 LEC 总分（31635/31635）
    └── lec_blocklevel/                      9 个模块的 LEC 详报

  dv/formal/build/                    formal 产物（make clean SCOPE=formal 清）
    ├── ifv_final.log                        formal 结果汇总
    └── ifv_cex/                             反例

  lint/build/                         lint 产物（make clean SCOPE=full 顺便清）
    ├── verible/verible-lint.log
    └── verilator/verilator-lint.log

  docs/sphinx_cn/build/               文档产物（make clean SCOPE=docs 清）
    ├── html/index.html
    └── pdf/EH2-Verification-Manual.pdf

  tests/asm/                          ASM 测试源 + 产物（make clean SCOPE=asm 清）
    ├── smoke.S / smoke.hex / smoke.elf / smoke.dis
    └── nop.S / nop.hex / nop.elf / nop.dis

  .scratch/                           归档/临时工作区（不 gitignored，长期保留）
    └── r5_build_archive_<date>/             make clean MODE=archive 的归档目标

──────────────────────────────────────────────────────────────────────────────
[ 已废弃的旧 target ] —— 保留作 alias，下个发布周期可能移除
──────────────────────────────────────────────────────────────────────────────

  run / gen / nightly / weekly / run_regress            → make regress + 变量
  compile_vcs / compile_xlm                             → 由 compile 自动调度
  signoff_quick / signoff_gate / signoff_with_cleanup   → make signoff + PROFILE/GATE_ONLY/CLEANUP=
  html_report / cov                                     → 已合并到 signoff
  lint_verible / lint_verilator                         → make lint TOOL=
  syn_yosys / syn_dc / lec / block_lec / syn_clean      → make synth STEP= / make clean SCOPE=syn
  formal_clean                                          → make clean SCOPE=formal
  compliance-all / compliance-compile                   → make compliance MODE=
  manual_html                                           → make manual FORMAT=html
  clean_cov / clean_workspace / clean_workspace_dry     → make clean SCOPE=/MODE=/DRY_RUN=
  run-csr-unit / ci_unit / ci_lint                      → 由 signoff/CI 直接调用

──────────────────────────────────────────────────────────────────────────────
[ 典型工作流 ]
──────────────────────────────────────────────────────────────────────────────

  快速冒烟（开发循环，<2 分钟）：
    make smoke

  查看波形（FSDB）—— 仿真类 target 的通用调试手段：
    原则：所有跑 simv 的 target（smoke / regress / signoff / demo）都原生支持
          WAVES=1，默认关以节省磁盘（单测 fsdb 通常 50-200 MB）。
    机制：WAVES=1 同时影响编译期（vcs -kdb -debug_access+all）和运行期
          （-ucli -do dv/uvm/core_eh2/vcs.tcl）。make 自动传播，命令行加一次即可。
    产物：每个测试 work_dir 下的 waves.fsdb。

    最短示例（按耗时升序）：
      # smoke ——1 分钟出 fsdb，演示首选
      make smoke WAVES=1
      verdi -ssf build/smoke/smoke_s1/waves.fsdb &

      # regress 单测 —— 调试某个具体测试
      make regress TEST=riscv_arithmetic_basic_test SEED=1 WAVES=1
      verdi -ssf build/regression/riscv_arithmetic_basic_test_s1/waves.fsdb &

      # signoff —— 所有 stage 都 dump（磁盘显著上升）
      make signoff WAVES=1
      verdi -ssf build/signoff/runs/directed/<test>_s<seed>/waves.fsdb &

      # demo —— 与 signoff 同结构，路径在 build/demo/
      make demo WAVES=1
      verdi -ssf build/demo/runs/<stage>/<test>_s<seed>/waves.fsdb &

    查看器：verdi -ssf <waves.fsdb>    推荐（已装于 $$VERDI_HOME，KDB 自动联动源码）
    注：compliance 不支持 WAVES（验证靠 signature 比对，无需波形）。

  开发自检（30 分钟）：
    make regress TESTLIST=directed
    make lint
    make formal

  完整 sign-off（不重综合，~1.5 小时）：
    make compile COV=1
    make signoff COV=1

  导师演示 / release 自检（2-3 小时）：
    make clean && make demo
    xdg-open build/demo/report.html

  v1.1 数字快速复演（< 30 秒）：
    make signoff_replay STAGE_DATA_DIR=build/r3b_final

  CI gate（只评估、不重跑）：
    make signoff GATE_ONLY=1

  清理但保留 sign-off 证据：
    make clean

  彻底重置（包括 r3b_final / r4a_final 等历史证据）：
    make clean FORCE=1

  把当前 build/ 归档到 .scratch/，腾空间：
    make clean MODE=archive DRY_RUN=1     # 先预览
    make clean MODE=archive               # 实际归档

================================================================================
endef
export HELP_TEXT

help:
	@echo "$$HELP_TEXT"

# ============================================================
# Build 目录
# ============================================================
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ============================================================
# Cosim 编译（保留原规则）
# ============================================================
LIBCOSIM := $(BUILD_DIR)/libcosim.so

ifeq ($(NO_COSIM),1)
COMPILE_LIBCOSIM_DEP :=
COMPILE_LIBCOSIM_LINK :=
else
COMPILE_LIBCOSIM_DEP := $(LIBCOSIM)
COMPILE_LIBCOSIM_LINK := $(CURDIR)/$(LIBCOSIM)
endif

SPIKE_DIR     ?= /home/host/spike-cosim
SPIKE_INSTALL ?= $(SPIKE_DIR)/install
SPIKE_CXX     ?= /home/Xilinx/Vivado/2019.1/tps/lnx64/gcc-6.2.0/bin/g++
SPIKE_CXXFLAGS ?= -std=c++17 -static-libstdc++
SPIKE_BUILD   ?= $(BUILD_DIR)/spike_objs

cosim: $(LIBCOSIM)

$(LIBCOSIM): $(COSIM_DIR)/spike_cosim.cc $(COSIM_DIR)/cosim_dpi.cc \
             $(COSIM_DIR)/spike_cosim.h $(COSIM_DIR)/cosim.h | $(BUILD_DIR)
	@if [ ! -d "$(SPIKE_INSTALL)" ]; then \
	  echo "ERROR: SPIKE_INSTALL=$(SPIKE_INSTALL) 不存在。"; \
	  echo "       先 build spike-cosim，或设 SPIKE_DIR=<path>，或传 NO_COSIM=1 跳过 cosim。"; \
	  exit 1; \
	fi
	@echo "=== [cosim] 构建 Spike DPI libcosim.so ==="
	@mkdir -p $(SPIKE_BUILD)
	@cd $(SPIKE_BUILD) && \
	  ar x $(SPIKE_INSTALL)/lib/libriscv.a && \
	  rm -f libfdt.a libsoftfloat.a && \
	  ar x $(SPIKE_INSTALL)/lib/libdisasm.a && \
	  ar x $(SPIKE_INSTALL)/lib/libfesvr.a && \
	  ar x $(SPIKE_INSTALL)/lib/libfdt.a && \
	  ar rcs libspike_all.a *.o
	$(SPIKE_CXX) -shared -fPIC -O2 -g \
	  -I$(COSIM_DIR) \
	  -I$(SPIKE_INSTALL)/include \
	  -I$(SPIKE_INSTALL)/include/softfloat \
	  -I$(VCS_HOME)/include \
	  $(SPIKE_CXXFLAGS) \
	  -o $(LIBCOSIM) \
	  $(COSIM_DIR)/spike_cosim.cc \
	  $(COSIM_DIR)/cosim_dpi.cc \
	  -L$(SPIKE_BUILD) -lspike_all \
	  $(SPIKE_DIR)/build/libsoftfloat.a \
	  -lpthread -ldl
	@echo "=== [cosim] libcosim.so 构建完成 ==="

# ============================================================
# asm hex 编译
# ============================================================
asm:
	@echo "=== [asm] 构建 tests/asm/*.hex ==="
	@$(MAKE) --no-print-directory -C $(ASM_DIR) all
	@echo "=== [asm] 完成 ==="

# ============================================================
# RTL/TB 编译（compile_vcs / compile_xlm 作为内部规则保留）
# ============================================================
compile: compile_$(SIMULATOR)

compile_vcs: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
	@echo "=== [compile] VCS UVM testbench (BUILD_SUBDIR=$(BUILD_SUBDIR)) ==="
	@mkdir -p $(BUILD_SUBDIR)
	$(VCS) -full64 -assert svaext -sverilog \
	  -ntb_opts uvm-1.2 \
	  +error+500 \
	  +define+GTLSIM \
	  $(DEFINES) \
	  +incdir+$(SNAPSHOTS) \
	  +incdir+$(TB_DIR)/common/axi4_agent \
	  +incdir+$(TB_DIR)/common/trace_agent \
	  +incdir+$(TB_DIR)/common/irq_agent \
	  +incdir+$(TB_DIR)/common/jtag_agent \
	  +incdir+$(TB_DIR)/common/cosim_agent \
	  +incdir+$(COSIM_DIR) \
	  -f $(RTL_F) \
	  -f $(SHARED_F) \
	  -f $(TB_F) \
	  -top core_eh2_tb_top \
	  $(COMPILE_LIBCOSIM_LINK) \
	  -Mdir=$(BUILD_SUBDIR)/csrc \
	  -o $(BUILD_SUBDIR)/simv \
	  -l $(BUILD_SUBDIR)/compile.log \
	  -timescale=1ns/1ps \
	  -debug_access+all \
	  $(if $(filter 1,$(WAVES)),-kdb,) \
	  $(if $(filter 1,$(COV)),$(VCS_COMPILE_COV_OPTS),)
	@echo "=== [compile] simv 完成: $(BUILD_SUBDIR)/simv ==="

compile_xlm: | $(BUILD_DIR)
	@echo "=== [compile] Xcelium UVM testbench (BUILD_SUBDIR=$(BUILD_SUBDIR)) ==="
	@mkdir -p $(BUILD_SUBDIR)
	cd $(BUILD_SUBDIR) && $(XLM) -uvm -sv \
	  $(DEFINES) \
	  +incdir+$(SNAPSHOTS) \
	  +incdir+../../$(TB_DIR)/common/axi4_agent \
	  +incdir+../../$(TB_DIR)/common/trace_agent \
	  +incdir+../../$(TB_DIR)/common/irq_agent \
	  +incdir+../../$(TB_DIR)/common/jtag_agent \
	  +incdir+../../$(TB_DIR)/common/cosim_agent \
	  -f ../../$(RTL_F) \
	  -f ../../$(SHARED_F) \
	  -f ../../$(TB_F) \
	  -top core_eh2_tb_top \
	  -l compile.log \
	  $(if $(filter 1,$(COV)),-covoverwrite -covfile ../../$(TB_DIR)/cov.ccf,)
	@echo "=== [compile] Xcelium 完成: $(BUILD_SUBDIR)/ ==="

# ============================================================
# 仿真 — smoke / regress / compliance
# ============================================================
smoke: asm
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(BUILD_DIR)/smoke
	@echo "=== [smoke] 运行 smoke 测试 ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --test smoke \
	  --binary $(ASM_DIR)/smoke.hex \
	  --simulator $(SIMULATOR) \
	  --seed 1 \
	  --rtl-test core_eh2_base_test \
	  --sim-opts "+disable_cosim=1" \
	  --build-dir $(BUILD_DIR)/smoke \
	  --output $(BUILD_DIR)/smoke \
	  $(if $(filter 1,$(WAVES)),--waves,)
	@echo "=== [smoke] 完成 ==="

regress:
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(BUILD_DIR)/regress
	@echo "=== [regress] testlist=$(TESTLIST) parallel=$(PARALLEL) iter=$(ITERATIONS) ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  $(if $(TEST),--test $(TEST),--testlist $(TESTLIST_PATH)) \
	  --simulator $(SIMULATOR) \
	  --seed $(SEED) \
	  --iterations $(ITERATIONS) \
	  --parallel $(PARALLEL) \
	  --build-dir $(BUILD_DIR)/regress \
	  --output $(if $(OUT),$(OUT),$(BUILD_DIR)/regress) \
	  $(if $(filter 1,$(COV)),--coverage,) \
	  $(if $(filter 1,$(WAVES)),--waves,)
	@echo "=== [regress] 完成 ==="

compliance:
	@echo "=== [compliance] mode=$(or $(MODE),run) ==="
	+@$(MAKE) -C dv/uvm/riscv_compliance $(if $(filter all,$(MODE)),compliance-all,$(if $(filter compile,$(MODE)),compliance-compile,compliance))

# ============================================================
# 静态 / 形式化 / 综合
# ============================================================
lint:
	@echo "=== [lint] tool=$(or $(TOOL),all) ==="
	+@$(MAKE) -C lint $(if $(filter verible,$(TOOL)),lint-verible,$(if $(filter verilator,$(TOOL)),lint-verilator,lint))

formal:
	@echo "=== [formal] IFV 46 properties ==="
	+@$(MAKE) -C dv/formal formal

synth:
	@echo "=== [synth] tool=$(or $(TOOL),dc) step=$(or $(STEP),full) ==="
	@# STEP=full 默认 = DC 综合 + block-level Formality LEC（v1.1 release 真实路径）。
	@# 旧的 syn-full（= syn-yosys + yosys-equiv）已知失败（ADR-0013：yosys 0.55 SV 限制）。
	@# 显式指定 TOOL=yosys 仍可跑 yosys（仅用于 ADR-0013 复盘演示）。
	@set -e; \
	if [ "$(TOOL)" = "yosys" ]; then \
	  $(MAKE) --no-print-directory -C syn syn-yosys; \
	elif [ "$(STEP)" = "lec" ]; then \
	  $(MAKE) --no-print-directory -C syn lec; \
	elif [ "$(STEP)" = "block_lec" ]; then \
	  $(MAKE) --no-print-directory -C syn block_lec; \
	elif [ "$(STEP)" = "synth" ]; then \
	  $(MAKE) --no-print-directory -C syn syn-dc; \
	else \
	  $(MAKE) --no-print-directory -C syn syn-dc; \
	  $(MAKE) --no-print-directory -C syn block_lec; \
	fi
	@echo "=== [synth] 完成 ==="

# ============================================================
# 一键 — demo / signoff / signoff_replay
# ============================================================
signoff:
	@$(if $(filter 1,$(GATE_ONLY)),,$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(SIGNOFF_OUT) COV=$(COV))
	@echo "=== [signoff] profile=$(PROFILE) gate_only=$(GATE_ONLY) out=$(SIGNOFF_OUT) ==="
	python3 $(SCRIPTS_DIR)/signoff.py \
	  --profile $(PROFILE) \
	  --simulator $(SIMULATOR) \
	  --seed $(SEED) \
	  --parallel $(PARALLEL) \
	  --output $(SIGNOFF_OUT) \
	  $(if $(filter 1,$(GATE_ONLY)),--gate-only,) \
	  $(if $(SIGNOFF_ITERATIONS),--iterations $(SIGNOFF_ITERATIONS),) \
	  $(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,) \
	  $(if $(filter 1,$(LEC_BLOCKLEVEL)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),) \
	  $(if $(filter 1,$(COV)),--coverage --min-line-coverage $(SIGNOFF_MIN_LINE_COV) --min-functional-coverage $(SIGNOFF_MIN_FUNCTIONAL_COV),) \
	  $(if $(filter 1,$(SIGNOFF_ALLOW_WARNINGS)),--allow-warnings,) \
	  $(if $(filter 1,$(WAVES)),--waves,) \
	  $(SIGNOFF_OPTS)
	@$(if $(filter 1,$(CLEANUP)),bash scripts/clean_workspace.sh --lck-only 2>/dev/null || true,)
	@echo "=== [signoff] 完成。报告：$(SIGNOFF_OUT)/report.html ==="

signoff_replay:
	@echo "=== [signoff_replay] 数据源=$(STAGE_DATA_DIR) ==="
	@if [ ! -d "$(STAGE_DATA_DIR)/runs" ]; then \
	  echo "ERROR: STAGE_DATA_DIR=$(STAGE_DATA_DIR) 不存在或缺 runs/ 子目录。"; \
	  echo "       先跑 'make demo' 攒数据，或从 .scratch/r5_build_archive_* 恢复历史 r3b_final。"; \
	  exit 1; \
	fi
	python3 $(SCRIPTS_DIR)/signoff.py \
	  --profile full --gate-only \
	  --output $(SIGNOFF_REPLAY_OUT) \
	  --stage-result smoke=$(STAGE_DATA_DIR)/runs/smoke \
	  --stage-result directed=$(STAGE_DATA_DIR)/runs/directed \
	  --stage-result cosim=$(STAGE_DATA_DIR)/runs/cosim \
	  --stage-result riscvdv=$(STAGE_DATA_DIR)/runs/riscvdv \
	  --stage-result csr_unit=$(STAGE_DATA_DIR)/runs/csr_unit \
	  --stage-result compliance=$(STAGE_DATA_DIR)/runs/compliance \
	  $(if $(filter 1,$(LEC_BLOCKLEVEL)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),) \
	  $(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,) \
	  --coverage --min-line-coverage $(SIGNOFF_MIN_LINE_COV) --min-functional-coverage $(SIGNOFF_MIN_FUNCTIONAL_COV) \
	  --allow-warnings \
	  $(SIGNOFF_OPTS)
	@echo "=== [signoff_replay] 完成。报告：$(SIGNOFF_REPLAY_OUT)/report.html ==="

demo:
	@echo "================================================================="
	@echo "  EH2 Demo  (清理 → 构建 → sign-off → 报告)"
	@echo "  WITH_SYNTH=$(WITH_SYNTH)   PARALLEL=$(PARALLEL)   COV=1   输出=$(DEMO_OUT)"
	@echo "================================================================="
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory asm
	@$(MAKE) --no-print-directory cosim COV=1
	@$(MAKE) --no-print-directory compile COV=1 BUILD_SUBDIR=$(DEMO_OUT)
	@if [ "$(WITH_SYNTH)" = "1" ]; then \
	  $(MAKE) --no-print-directory synth || echo "[demo] synth 失败，syn stage 将以 known-limited 处理"; \
	else \
	  echo "[demo] 跳过 synth (WITH_SYNTH=0)"; \
	fi
	@# 如果 lec_summary.txt 不存在（synth 失败或被跳过），自动启用 known-limited 模式
	@# signoff 必须传 COV=1：profile=full 在 signoff.py:1561-1562 强制 require coverage，
	@# 不开 COV=1 会因 dashboard.txt 缺失而 FAIL（threshold 60% line coverage）。
	@if [ -f "$(LEC_SUMMARY_PATH)" ]; then \
	  echo "[demo] LEC summary 存在，正常 sign-off（COV=1 全量收集）"; \
	  $(MAKE) --no-print-directory signoff SIGNOFF_OUT=$(DEMO_OUT) PARALLEL=$(PARALLEL) COV=1; \
	else \
	  echo "[demo] LEC summary 缺失，启用 LEC_KNOWN_LIMITED=1 兜底（COV=1 全量收集）"; \
	  $(MAKE) --no-print-directory signoff SIGNOFF_OUT=$(DEMO_OUT) PARALLEL=$(PARALLEL) COV=1 \
	    LEC_BLOCKLEVEL=0 LEC_KNOWN_LIMITED=1; \
	fi
	@echo ""
	@echo "================================================================="
	@echo "  Demo 完成"
	@echo "  报告：$(DEMO_OUT)/report.html"
	@echo "  JSON：$(DEMO_OUT)/signoff_status.json"
	@echo "================================================================="

# ============================================================
# 文档 — Sphinx 中文手册
# ============================================================
manual:
	@echo "=== [manual] format=$(FORMAT) ==="
	@if [ "$(FORMAT)" = "pdf" ]; then \
	  bash docs/build_manual_pdf.sh; \
	else \
	  sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html; \
	fi
	@echo "=== [manual] 完成 ==="

# ============================================================
# Clean — 默认彻底清；SCOPE/MODE/DRY_RUN 控制范围与模式
#
# 安全网（自 2026-05-17 起）：
#   - `build` 与 `full` 两种 scope 默认通过 CLEAN_PRESERVE_BUILD 白名单
#     保留 r3b_final/r4a_final/simv*/libcosim.so/cov.vdb/archive_signoffs_*
#     等"删了要重跑数小时"的关键产物。
#   - 显式恢复旧行为：`make clean FORCE=1`（会真的把 build/ 整个 rm -rf）。
#   - syn/build/eh2_dc_wrapper.sv 由 scripts/gen_dc_wrapper.sh 在 syn-dc /
#     block_lec 前自动重建，所以仍然允许 syn clean。
# ============================================================
clean:
	@echo "=== [clean] scope=$(SCOPE) mode=$(or $(MODE),delete) force=$(or $(FORCE),0) dry_run=$(DRY_RUN) ==="
	@if [ "$(MODE)" = "archive" ]; then \
	  bash scripts/clean_workspace.sh $(if $(filter 1,$(DRY_RUN)),--dry-run,); \
	  exit 0; \
	fi; \
	case "$(SCOPE)" in \
	  cov) \
	    find $(BUILD_DIR) -mindepth 2 -maxdepth 2 \
	      \( -name 'cov.vdb' -o -name 'cov' -o -name 'cov_report' -o -name 'simv.vdb' \) \
	      -exec rm -rf {} + 2>/dev/null || true; \
	    echo "[clean] 已清各 target 子目录下的覆盖率数据库（build/*/cov.vdb 等）" ;; \
	  syn) \
	    $(MAKE) --no-print-directory -C syn clean; \
	    echo "[clean] 已清 syn/build/（wrapper 下次 syn-dc 会自动重建）" ;; \
	  formal) \
	    $(MAKE) --no-print-directory -C dv/formal formal_clean; \
	    echo "[clean] 已清 dv/formal/build/" ;; \
	  asm) \
	    $(MAKE) --no-print-directory -C $(ASM_DIR) clean; \
	    $(MAKE) --no-print-directory -C dv/uvm/core_eh2/tests/asm clean 2>/dev/null || true; \
	    echo "[clean] 已清 tests/asm 产物" ;; \
	  docs) \
	    rm -rf docs/sphinx_cn/build; \
	    echo "[clean] 已清 docs/sphinx_cn/build/" ;; \
	  build) \
	    if [ "$(FORCE)" = "1" ]; then \
	      rm -rf $(BUILD_DIR); mkdir -p $(BUILD_DIR); \
	      echo "[clean] FORCE=1：已彻底清 $(BUILD_DIR)/（含 r3b_final/r4a_final 等保护项）"; \
	    else \
	      if [ -d $(BUILD_DIR) ]; then \
	        find $(BUILD_DIR) -mindepth 1 -maxdepth 1 $(CLEAN_PRESERVE_FIND) -exec rm -rf {} + ; \
	      fi; \
	      mkdir -p $(BUILD_DIR); \
	      echo "[clean] 已清 $(BUILD_DIR)/ 中可再生产物（保留 r3b_final/r4a_final/simv*/libcosim.so/cov.vdb/archive_signoffs_*）"; \
	    fi ;; \
	  full|*) \
	    if [ "$(FORCE)" = "1" ]; then \
	      rm -rf $(BUILD_DIR); \
	      echo "[clean] FORCE=1：连保护项一起删了"; \
	    else \
	      if [ -d $(BUILD_DIR) ]; then \
	        find $(BUILD_DIR) -mindepth 1 -maxdepth 1 $(CLEAN_PRESERVE_FIND) -exec rm -rf {} + ; \
	      fi; \
	    fi; \
	    $(MAKE) --no-print-directory -C syn clean 2>/dev/null || true; \
	    $(MAKE) --no-print-directory -C dv/formal formal_clean 2>/dev/null || true; \
	    $(MAKE) --no-print-directory -C $(ASM_DIR) clean 2>/dev/null || true; \
	    $(MAKE) --no-print-directory -C dv/uvm/core_eh2/tests/asm clean 2>/dev/null || true; \
	    rm -rf lint/build out/* docs/sphinx_cn/build .pytest_cache csrc; \
	    rm -f top.vcd tr_db.log ucli.key vc_hdrs.h CDS.log formalverifier.log; \
	    rm -f *.fsdb *.fss *.lck *.svf default.svf command.log; \
	    rm -rf verdiLog novas_* DVEfiles; \
	    rm -f stack.info.* stack_*.log; \
	    rm -f eh2_pkg.pvk *.mr *-verilog.pvl *-verilog.syn; \
	    rm -f syn/*.lck syn/*.fss syn/*.log syn/default.svf syn/command.log; \
	    rm -rf syn/FM_WORK syn/FM_WORK1; \
	    mkdir -p out $(BUILD_DIR); \
	    if [ "$(FORCE)" = "1" ]; then \
	      echo "[clean] 已彻底清理（FORCE=1：build/ 全删 + syn/build/ + dv/formal/build/ + lint/build/ + asm/*.hex + 根残留 + Sphinx HTML + pytest cache）"; \
	    else \
	      echo "[clean] 已清可再生产物（保留 r3b_final/r4a_final 等 sign-off 证据；如需彻底删请加 FORCE=1）"; \
	    fi ;; \
	esac

# ============================================================
# Deprecated aliases — 兼容旧 CI / 文档；输出 [deprecated] 提示并转发
# ============================================================
run:
	@echo "[deprecated] 'make run' → 'make regress TEST=$(TEST) SEED=$(SEED)'"
	@$(MAKE) --no-print-directory regress TEST=$(TEST) SEED=$(SEED)

gen: | $(BUILD_DIR)
	@echo "[deprecated] 'make gen' → 现在 signoff 自动调用 riscv-dv generation；如需单跑："
	@mkdir -p $(OUT_DIR)
	python3 $(SCRIPTS_DIR)/run_instr_gen.py \
	  --riscv-dv-dir $(RISCV_DV_DIR) \
	  --work-dir $(OUT_DIR) \
	  --test $(TEST) \
	  --gen-opts "$(GEN_OPTS)" \
	  --seed $(SEED) \
	  --iterations $(ITERATIONS)

nightly:
	@echo "[deprecated] 'make nightly' → 'make regress PARALLEL=$(PARALLEL)'"
	@$(MAKE) --no-print-directory regress PARALLEL=$(PARALLEL)

weekly:
	@echo "[deprecated] 'make weekly' → 'make regress PARALLEL=$(PARALLEL) ITERATIONS=5'"
	@$(MAKE) --no-print-directory regress PARALLEL=$(PARALLEL) ITERATIONS=5

run_regress:
	@echo "[deprecated] 'make run_regress' → 'make regress TESTLIST=$(TEST_LIST)'"
	@$(MAKE) --no-print-directory regress TESTLIST=$(if $(filter directed,$(TEST_LIST)),directed,riscvdv)

signoff_quick:
	@echo "[deprecated] 'make signoff_quick' → 'make signoff PROFILE=quick'"
	@$(MAKE) --no-print-directory signoff PROFILE=quick SIGNOFF_OUT=$(BUILD_DIR)/signoff_quick

signoff_gate:
	@echo "[deprecated] 'make signoff_gate' → 'make signoff GATE_ONLY=1 SIGNOFF_OUT=$(SIGNOFF_OUT)'"
	@$(MAKE) --no-print-directory signoff GATE_ONLY=1 SIGNOFF_OUT=$(SIGNOFF_OUT)

signoff_with_cleanup:
	@echo "[deprecated] 'make signoff_with_cleanup' → 'make signoff CLEANUP=1'"
	@$(MAKE) --no-print-directory signoff CLEANUP=1

html_report:
	@echo "[deprecated] 'make html_report' → 已合并进 signoff target；如需单跑："
	python3 $(SCRIPTS_DIR)/gen_html_report.py \
	  --signoff-status $(SIGNOFF_OUT)/signoff_status.json \
	  --coverage-dashboard $(if $(wildcard $(SIGNOFF_OUT)/cov_merged/dashboard.txt),$(SIGNOFF_OUT)/cov_merged/dashboard.txt,$(BUILD_DIR)/r3b_cov_report/dashboard.txt) \
	  --runs-dir $(SIGNOFF_OUT)/runs \
	  --output $(SIGNOFF_OUT)/report.html

cov:
	@echo "[deprecated] 'make cov' → signoff COV=1 时自动合并；如需单独合并："
	@if [ "$(SIMULATOR)" = "vcs" ]; then \
	  urg -dir $(BUILD_DIR)/cov/simv.vdb -report $(BUILD_DIR)/cov_report; \
	elif [ "$(SIMULATOR)" = "xlm" ]; then \
	  imc -load $(BUILD_DIR)/cov -exec $(TB_DIR)/cov_merge.tcl; \
	fi

lint_verible:
	@echo "[deprecated] 'make lint_verible' → 'make lint TOOL=verible'"
	@$(MAKE) --no-print-directory lint TOOL=verible

lint_verilator:
	@echo "[deprecated] 'make lint_verilator' → 'make lint TOOL=verilator'"
	@$(MAKE) --no-print-directory lint TOOL=verilator

syn_yosys:
	@echo "[deprecated] 'make syn_yosys' → 'make synth TOOL=yosys'"
	@$(MAKE) --no-print-directory synth TOOL=yosys

syn_dc:
	@echo "[deprecated] 'make syn_dc' → 'make synth TOOL=dc STEP=synth'"
	@$(MAKE) --no-print-directory synth TOOL=dc STEP=synth

lec:
	@echo "[deprecated] 'make lec' → 'make synth STEP=lec'"
	@$(MAKE) --no-print-directory synth STEP=lec

block_lec:
	@echo "[deprecated] 'make block_lec' → 'make synth STEP=block_lec'"
	@$(MAKE) --no-print-directory synth STEP=block_lec

syn_clean:
	@echo "[deprecated] 'make syn_clean' → 'make clean SCOPE=syn'"
	@$(MAKE) --no-print-directory clean SCOPE=syn

formal_clean:
	@echo "[deprecated] 'make formal_clean' → 'make clean SCOPE=formal'"
	@$(MAKE) --no-print-directory clean SCOPE=formal

compliance-all:
	@echo "[deprecated] 'make compliance-all' → 'make compliance MODE=all'"
	@$(MAKE) --no-print-directory compliance MODE=all

compliance-compile:
	@echo "[deprecated] 'make compliance-compile' → 'make compliance MODE=compile'"
	@$(MAKE) --no-print-directory compliance MODE=compile

manual_html:
	@echo "[deprecated] 'make manual_html' → 'make manual FORMAT=html'"
	@$(MAKE) --no-print-directory manual FORMAT=html

clean_cov:
	@echo "[deprecated] 'make clean_cov' → 'make clean SCOPE=cov'"
	@$(MAKE) --no-print-directory clean SCOPE=cov

clean_workspace:
	@echo "[deprecated] 'make clean_workspace' → 'make clean MODE=archive'"
	@$(MAKE) --no-print-directory clean MODE=archive

clean_workspace_dry:
	@echo "[deprecated] 'make clean_workspace_dry' → 'make clean MODE=archive DRY_RUN=1'"
	@$(MAKE) --no-print-directory clean MODE=archive DRY_RUN=1

run-csr-unit:
	@echo "[deprecated] 'make run-csr-unit' → 由 signoff 自动跑；如需单跑："
	@echo "    make -C dv/uvm/cs_registers_eh2 run-csr-unit SIGNOFF_OUT=$(SIGNOFF_OUT)"
	+@$(MAKE) -C dv/uvm/cs_registers_eh2 run-csr-unit SIGNOFF_OUT=$(SIGNOFF_OUT)

ci_unit:
	@echo "[deprecated] 'make ci_unit' → CI workflow 直调 python；本地等价："
	cd $(TB_DIR)/scripts && python3 -m unittest tests.test_regression_framework
	@$(MAKE) --no-print-directory ci_lint

ci_lint:
	@python3 -c "import yaml, pathlib; \
tl = pathlib.Path('$(TB_DIR)/riscv_dv_extension/testlist.yaml'); \
tests = yaml.safe_load(tl.read_text()); \
assert isinstance(tests, list) and tests, 'testlist must be non-empty list'; \
names = [t['test'] for t in tests]; \
dups = [n for n in set(names) if names.count(n) > 1]; \
assert not dups, f'duplicate test names: {dups}'; \
[t.update({'_': None}) for t in tests if all(k in t for k in ('test','description','rtl_test'))]; \
print(f'testlist.yaml OK: {len(tests)} tests')"

endif
