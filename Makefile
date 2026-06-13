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
BUILD_SUBDIR ?= $(BUILD_DIR)/compile_$(SIMULATOR)

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
SIMULATOR   ?= vcs
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
SIGNOFF_OUT     ?= $(BUILD_DIR)/signoff_$(SIMULATOR)
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
SIGNOFF_REPLAY_OUT ?= $(BUILD_DIR)/signoff_replay_$(SIMULATOR)

# Demo
WITH_SYNTH       ?= 1
DEMO_OUT         ?= $(BUILD_DIR)/demo_$(SIMULATOR)

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
IRUN        := irun

# Coverage 配置 — 对齐 lowRISC Ibex 工业实现
#   - 5 维度（line+tgl+assert+fsm+branch）；不收 cond/expression
#     工业实践证明 line+toggle+branch 已覆盖大部分 condition 路径，
#     cond 维度在大型设计 instrumentation 开销大且不必要。
#   - -cm_hier cover.cfg 编译时限定 dut 子树，从源头杜绝 tb_intf 等 stub 假高数字。
#   - -cm_tgl portsonly + structarr 是 Ibex 标准 toggle 配置。
#   - -cm_report noinitial 不报告 initial 块覆盖率。
#   - -cm_seqnoconst 跳过常量条件的序列采样。
VCS_COV_METRICS := line+tgl+assert+fsm+branch
VCS_COV_HIER    := $(TB_DIR)/cover.cfg
VCS_FSM_CFG     := $(TB_DIR)/cov_fsm.cfg
VCS_FSM_RESET_FILTER := $(TB_DIR)/cov_fsm_reset_filter.cfg
# `-cm_tgl structarr` 在 VCS 2018 是 LCA (Limited Customer Availability) 选项，
# 需要 `-lca` 才能启用。Ibex 工业实现使用此 toggle 配置以覆盖 struct/array 信号；
# 若 VCS license 不允许 LCA，删掉 structarr 与 -lca 两个 flag 即可（line/branch
# 维度不受影响）。
VCS_COMPILE_COV_OPTS := -lca \
                        -cm $(VCS_COV_METRICS) -cm_dir $(BUILD_SUBDIR)/cov \
                        -cm_hier $(VCS_COV_HIER) \
                        -cm_tgl portsonly \
                        -cm_tgl structarr \
                        -cm_report noinitial \
                        -cm_seqnoconst \
                        -cm_fsmcfg $(VCS_FSM_CFG) \
                        -cm_fsmresetfilter $(VCS_FSM_RESET_FILTER) \
                        -cm_fsmopt report2StateFsms+allowTmp+reportvalues+reportWait+upto64

# NC (Cadence Incisive irun) — 全面支持作为 VCS 备选 simulator。
# 同样收集覆盖率参与 sign-off；用 cov_full_nc.ccf 限定 dut-only scope
# 并启用 set_expr_coverable_*-all 让 expression cov 完整 instrument。
# VCS 是 sign-off 默认；NC 可作 cross-check 或在不便于 Verdi 时优先用 simvision/Indago。
NC_COV_CCF      := $(TB_DIR)/cov_full_nc.ccf
NC_COMPILE_COV_OPTS := -coverage all -covworkdir $(BUILD_SUBDIR)/cov_work -covoverwrite -covdut core_eh2_tb_top -covfile $(NC_COV_CCF)

# NC 显式指 UVM-1.2 源，避开默认 -uvm 预编译库的 uvm_default_report_server 可见性问题。
NC_UVM_HOME ?= /home/cadence/INCISIVE152/tools/methodology/UVM/CDNS-1.2
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
        smoke regress compliance wave_nc \
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
EH2 UVM 验证平台 — Makefile 入口说明（v1.1 规整版 / 2026-05-19 更新）
================================================================================

15 个核心 target，按 5 组组织。所有变体行为靠变量切换。
默认仿真器 = Synopsys VCS（对齐 lowRISC Ibex 工业实现，覆盖率配置见 cover.cfg）。
NC/Incisive 同时全面支持作为备选 simulator（cover.cfg 等价物：cov_full_nc.ccf），
所有 stage 与 sign-off 都可以走 NC 路径。build/<target>_<simulator>/ 隔离 VCS/NC 产物。
NC 的优势是 simvision/Indago 波形与 Cadence 工具链协同。
默认门限 = v1.1 release 真实值：line ≥ 65%, functional ≥ 40%, warnings allowed。

每个 target 统一字段：用途 / 耗时 / 依赖 / 变量 / 产出 / 示例。

──────────────────────────────────────────────────────────────────────────────
[ build/ 目录约定 ] —— per-target 岛屿原则
──────────────────────────────────────────────────────────────────────────────

每个仿真类 target 是一个"岛"。VCS 产物（simv / csrc / cov.vdb）与 NC 产物
（INCA_libs / cov_work）按 simulator 后缀隔离，路径形如 build/<target>_<simulator>/，
两个 simulator 可并行运行同一 target 而互不干扰。

  build/
  ├── libcosim.so                 共享只读 Spike DPI 库
  ├── spike_objs/                 共享 Spike 编译中间产物
  ├── r3b_final/ r4a_final/       历史 v1.1 sign-off 证据（clean 保护）
  ├── archive_signoffs_*          历史归档软链（clean 保护）
  │
  ├── compile_vcs/                make compile SIMULATOR=vcs
  ├── compile_nc/                 make compile SIMULATOR=nc
  ├── smoke_vcs/ / smoke_nc/      make smoke
  ├── regress_vcs/ / regress_nc/  make regress
  ├── signoff_vcs/ / signoff_nc/  make signoff   ★ UVM 验证主线
  ├── signoff_replay_vcs/nc/      make signoff_replay（gate-only）
  ├── demo_vcs/ / demo_nc/        make demo（含 ASIC 综合）
  └── wave_nc_<test>/             make wave_nc TEST=<name>（NC GUI 调试）

每个 target 子目录内典型布局：
  build/<target>_<simulator>/
  ├── simv, simv.daidir/, csrc/        VCS 编译产物（SIMULATOR=vcs）
  ├── cov.vdb, cov/, cov_report/       VCS 覆盖率数据库（如 COV=1）
  ├── INCA_libs/                       NC 编译产物（SIMULATOR=nc）
  ├── cov_work/                        NC 覆盖率数据库（IMC 读，如 COV=1）
  ├── cov_merged/                      sign-off 合并覆盖率（URG/IMC 输出）
  ├── report.html / signoff_report.md  最终 sign-off 报告（仅 signoff/demo）
  ├── compile.log                      编译日志
  └── <test>_s<seed>/  或  runs/<stage>/<test>_s<seed>/
      ├── waves.fsdb / waves.shm/      如 WAVES=1（VCS=FSDB，NC=SHM 数据库）
      ├── sim_*.log
      └── result.yaml

并行安全：以下组合都可同时跑，互不干扰：
  - make signoff SIMULATOR=vcs   &  make signoff SIMULATOR=nc
  - make smoke SIMULATOR=vcs     &  make smoke SIMULATOR=nc
  - make signoff & make regress &  make smoke（三个 target 同时）
唯一共享资源：syn/build/ (DC + LEC 产物)。如同时跑两个含 synth 的 demo，
需要错开（让一个先跑完 make synth 再启另一个）。

──────────────────────────────────────────────────────────────────────────────
[ UVM 验证主线 ] —— sign-off / 复演 / 完整端到端演示
──────────────────────────────────────────────────────────────────────────────

# 关键约定
# --------
# 1) 产物隔离：所有 simulator-相关的 target 输出按 simulator 后缀分目录：
#       make smoke   SIMULATOR=vcs  → build/smoke_vcs/
#       make smoke   SIMULATOR=nc   → build/smoke_nc/
#       make regress SIMULATOR=vcs  → build/regress_vcs/
#       make regress SIMULATOR=nc   → build/regress_nc/
#       make compile SIMULATOR=vcs  → build/compile_vcs/
#       make compile SIMULATOR=nc   → build/compile_nc/
#       make signoff SIMULATOR=vcs  → build/signoff_vcs/   ← UVM 验证主线
#       make signoff SIMULATOR=nc   → build/signoff_nc/
#       make demo    SIMULATOR=vcs  → build/demo_vcs/      ← 含 ASIC 综合的完整演示
#       make demo    SIMULATOR=nc   → build/demo_nc/
#    VCS 与 NC 产物互不干扰，可并行运行：`make signoff SIMULATOR=vcs` 与
#    `make signoff SIMULATOR=nc` 可同时跑。
#
# 2) signoff vs demo（重要！）
#    - signoff 是 UVM 验证主线：9-stage gate（smoke/directed/cosim/riscvdv/
#      lint/csr_unit/compliance/formal/syn），重点是 UVM regression + 覆盖率合并
#      + sign-off 门限判定。formal/syn 两个 stage 仅"读取"已有报告做 gate，
#      不会重跑工具。
#    - demo 是完整端到端演示：signoff + 显式跑 make synth（DC + block_lec）。
#      DC+LEC 与 UVM 无关，是给 signoff.syn stage 提供 lec_summary.txt 数据。
#      要跑 UVM 主线，直接用 signoff；要做 ASIC 完整演示，用 demo。
#
# 3) formal 数据：dv/formal/build/ifv_*.log 由独立的 `make formal` target 生成
#    （signoff.formal stage 只读这些报告做 gate，不自己跑 IFV）。

  make signoff                                 ★ UVM 验证主线，推荐入口
        用途：完整 9-stage sign-off（UVM regression + 覆盖率合并 + gate 判定）
        耗时：~1-1.5 小时（COV=1，PARALLEL=4）
        依赖：本 target 自动调 compile 生成编译产物
              （VCS: build/signoff_vcs/simv；NC: build/signoff_nc/INCA_libs/；
              COV=1 时带覆盖率插桩）；
              如启用 LEC_BLOCKLEVEL=1 需先有 syn/build/lec_summary.txt
              （由 `make synth` 生成，可独立预跑）
              GATE_ONLY=1 时跳过 compile，仅评估现有 runs/。
        9 stage 说明：
          smoke / directed / cosim / riscvdv / lint / csr_unit / compliance
                  ↑ 这 7 个 stage 自己跑测试 + gate
          formal / syn
                  ↑ 这 2 个 stage 仅读取 dv/formal/build/ 和 syn/build/ 已有报告做 gate
        变量：
          SIMULATOR=vcs|nc                       仿真器（默认 vcs；可与 NC 并行跑）
          PROFILE=full|quick|cosim|nightly       profile（默认 full）
          GATE_ONLY=0|1                          仅评估、不重跑（默认 0）
          COV=0|1                                覆盖率（默认 1）
          PARALLEL=<N>                           并行度（默认 4）
          SEED=<N>                               随机种子（默认 1）
          SIGNOFF_OUT=<dir>                      输出目录（默认 build/signoff_$(SIMULATOR)）
          SIGNOFF_MIN_LINE_COV=<pct>             line 门限（默认 65）
          SIGNOFF_MIN_FUNCTIONAL_COV=<pct>       functional 门限（默认 40）
          SIGNOFF_ALLOW_WARNINGS=0|1             warning 容忍（默认 1）
          SIGNOFF_OPTS="..."                     透传 signoff.py 其它选项
          SIGNOFF_ITERATIONS=<N>                 单测迭代次数
          CLEANUP=0|1                            跑完做 lck-only 清理（默认 0）
          LEC_BLOCKLEVEL=0|1                     启用块级 LEC（默认 1）
          LEC_KNOWN_LIMITED=0|1                  LEC 失败兜底（默认 0）
          LEC_SUMMARY_PATH=<file>                LEC 摘要（默认 syn/build/lec_summary.txt）
        产出（路径示例按默认 SIMULATOR=vcs；NC 时同名子目录在 signoff_nc/ 下）：
          build/signoff_vcs/simv                       VCS 编译产物（SIMULATOR=vcs）
          build/signoff_nc/INCA_libs/                  NC 编译产物（SIMULATOR=nc）
          $(SIGNOFF_OUT)/report.html                   HTML 报告
          $(SIGNOFF_OUT)/signoff_status.json           机器可读结果
          $(SIGNOFF_OUT)/signoff_report.md             Markdown 摘要
          $(SIGNOFF_OUT)/runs/<stage>/                 各 stage 运行数据
          $(SIGNOFF_OUT)/cov_merged/dashboard.txt      URG/IMC 合并覆盖率
        示例：
          make signoff                                       # VCS 主线，默认门限
          make signoff SIMULATOR=nc                          # 用 NC 跑（与 VCS 并行无冲突）
          make signoff PROFILE=quick                         # smoke+directed 快跑
          make signoff GATE_ONLY=1                           # 不重跑，仅评估现有 runs/
          make signoff SIGNOFF_MIN_LINE_COV=85 SIGNOFF_ALLOW_WARNINGS=0
                                                              # 恢复旧 85/50 严格门限
          make signoff CLEANUP=1                             # 跑完顺便清 lck 残留
          make signoff LEC_KNOWN_LIMITED=1 LEC_BLOCKLEVEL=0  # LEC 兜底
          # 双 simulator 并行跑（资源充足时）：
          make signoff SIMULATOR=vcs & make signoff SIMULATOR=nc

  make signoff_replay
        用途：gate-only 复演 v1.1 reference run，秒级出报告（不重跑任何测试）
        耗时：< 30 秒
        依赖：STAGE_DATA_DIR/runs/{smoke,directed,cosim,riscvdv,csr_unit,compliance}
              默认指向 build/r3b_final（如不存在请用 build/demo_vcs/ 或重跑 demo 生成）
        变量：
          SIMULATOR=vcs|nc                  仿真器（默认 vcs；改变输出目录后缀）
          STAGE_DATA_DIR=<dir>              数据源（默认 build/r3b_final）
          SIGNOFF_REPLAY_OUT=<dir>          输出目录（默认 build/signoff_replay_$(SIMULATOR)）
          LEC_BLOCKLEVEL=0|1                启用 LEC gate（默认 1）
          LEC_KNOWN_LIMITED=0|1             LEC 兜底（默认 0）
          LEC_SUMMARY_PATH=<file>           LEC 摘要路径
          SIGNOFF_MIN_LINE_COV=<pct>        line 门限（默认 65）
          SIGNOFF_MIN_FUNCTIONAL_COV=<pct>  functional 门限（默认 40）
          SIGNOFF_OPTS="..."                透传选项
        产出：
          $(SIGNOFF_REPLAY_OUT)/report.html               HTML 报告
          $(SIGNOFF_REPLAY_OUT)/signoff_status.json       机器可读结果
          $(SIGNOFF_REPLAY_OUT)/signoff_report.md         Markdown 摘要
        示例：
          make signoff_replay                                   # 默认复演 r3b_final
          make signoff_replay STAGE_DATA_DIR=build/demo_vcs     # 复演刚跑完的 VCS demo
          make signoff_replay STAGE_DATA_DIR=build/signoff_nc   # 复演刚跑完的 NC signoff

  make demo                                    完整端到端演示（含 ASIC 综合）
        用途：完整端到端演示 / release 自检。一条龙：clean → asm → cosim → compile
              → synth（DC + block-level LEC） → signoff → HTML 报告
        与 signoff 的区别：demo 额外跑 make synth（DC 综合 + block-level LEC），
                          DC/LEC 与 UVM 验证无关，是给 signoff.syn stage
                          提供 lec_summary.txt 数据；要跑 UVM 主线，
                          直接用 signoff，省 1.5 小时综合时间。
        耗时：PARALLEL=4 约 2-3 小时（DC ~30min + block_lec ~45min + UVM signoff ~1-1.5h）
              WITH_SYNTH=0 可省 1-2 小时（跳过 DC+LEC）
        依赖：syn-dc 自动调 scripts/gen_dc_wrapper.sh 生成 wrapper；
              compile 用 COV=1 重建带覆盖率插桩的 testbench
        变量：
          SIMULATOR=vcs|nc      仿真器（默认 vcs；NC 可同时跑，产物在 demo_nc/）
          WITH_SYNTH=0|1        是否含 synth+LEC（默认 1）
          DEMO_OUT=<dir>        输出目录（默认 build/demo_$(SIMULATOR)）
          PARALLEL=<N>          回归并行度（默认 4）
        产出（路径示例按默认 SIMULATOR=vcs；NC 时同名子目录在 demo_nc/ 下）：
          build/demo_vcs/simv                     VCS 编译产物（SIMULATOR=vcs）
          build/demo_nc/INCA_libs/                NC 编译产物（SIMULATOR=nc）
          $(DEMO_OUT)/report.html                 HTML 报告（含覆盖率仪表盘）
          $(DEMO_OUT)/signoff_status.json         机器可读结果
          $(DEMO_OUT)/signoff_report.md           Markdown 摘要
          $(DEMO_OUT)/runs/{smoke,directed,cosim,riscvdv,csr_unit,compliance}/
          $(DEMO_OUT)/cov_merged/dashboard.txt    URG/IMC 合并覆盖率
          syn/build/eh2_synth.v                   综合 netlist
          syn/build/lec_summary.txt               block-level LEC 31635/31635
        示例：
          make demo                       # 完整演示（默认 build/demo_vcs）
          make demo SIMULATOR=nc          # NC 版完整演示（build/demo_nc）
          make demo WITH_SYNTH=0          # 跳过综合/LEC，与 make signoff 等价
          make demo PARALLEL=8            # 提速：8 路并行

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
        依赖：SPIKE_INSTALL（默认 $$HOME/spike-cosim）；
              svdpi.h 头文件（自动从 NC_INSTALL=$(NC_INSTALL) 或 VCS_HOME 查找，
              可显式设 SVDPI_INCLUDE=<dir>）
        变量：
          SPIKE_DIR=<path>          Spike 源码目录
          SPIKE_INSTALL=<path>      Spike 安装前缀
          NC_INSTALL=<path>         INCISIVE 安装根（svdpi.h 来源之一）
          SVDPI_INCLUDE=<file>      显式指定 svdpi.h 路径（覆盖自动查找）
          NO_COSIM=1                跳过链接（运行时配套 +disable_cosim=1）
        产出：
          build/libcosim.so                 ~200MB Spike DPI 动态库
          build/spike_objs/                 中间对象
        示例：
          make cosim                        # 默认环境
          make compile NO_COSIM=1           # 无 Spike 环境，跳过 cosim 链接

  make compile
        用途：编译 UVM testbench（VCS: simv；NC: INCA_libs/）
        耗时：VCS ~3-5 分钟；NC irun 同量级；COV=1 慢 ~1.5 倍
        依赖：libcosim.so（除非 NO_COSIM=1），RTL flist
        变量：
          SIMULATOR=vcs|nc|xlm     仿真器（默认 vcs；NC 全面支持，含 sign-off 与覆盖率）
          COV=0|1                  覆盖率插桩（默认 1，与顶层 COV ?= 1 一致；显式 COV=0 关闭）
          WAVES=0|1                FSDB/SHM 波形 dump（默认 0）
          NO_COSIM=1               跳过 cosim 链接
        产出（默认 build/compile_$(SIMULATOR)/，VCS/NC 互不干扰）：
          $(BUILD_DIR)/compile_vcs/simv, simv.daidir/, csrc/   VCS 编译产物
          $(BUILD_DIR)/compile_vcs/cov, cov.vdb                VCS 覆盖率数据库（COV=1）
          $(BUILD_DIR)/compile_nc/INCA_libs/                   NC (irun) 编译库
          $(BUILD_DIR)/compile_nc/cov_work/                    NC 覆盖率数据库（COV=1）
          $(BUILD_DIR)/compile_$(SIMULATOR)/compile.log        编译日志
        示例：
          make compile                     # VCS（默认），COV 取顶层默认值
          make compile SIMULATOR=nc        # NC 编译
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
          SIMULATOR=vcs|nc|xlm             仿真器（默认 vcs；NC 同样支持，产物在 smoke_nc/）
          COV=0|1                          覆盖率插桩（默认 0；COV=1 时跑覆盖率收集）
          WAVES=0|1                        FSDB/SHM 波形 dump（默认 0）
        产出（默认 build/smoke_$(SIMULATOR)/）：
          $(BUILD_DIR)/smoke_vcs/simv, simv.daidir/        VCS 编译产物
          $(BUILD_DIR)/smoke_nc/INCA_libs/                 NC 编译库
          $(BUILD_DIR)/smoke_$(SIMULATOR)/<test>_s1/sim_*.log
          $(BUILD_DIR)/smoke_$(SIMULATOR)/<test>_s1/result.yaml
          $(BUILD_DIR)/smoke_$(SIMULATOR)/<test>_s1/waves.fsdb|waves.shm/   如 WAVES=1
          $(BUILD_DIR)/smoke_$(SIMULATOR)/regr.log
          $(BUILD_DIR)/smoke_$(SIMULATOR)/report.json
        示例：
          make smoke                       # VCS（默认）
          make smoke SIMULATOR=nc          # NC 跑 smoke
          make smoke WAVES=1               # 带 FSDB 波形（VCS）/ SHM（NC）
          # VCS 与 NC 同时跑互不干扰：
          make smoke SIMULATOR=vcs & make smoke SIMULATOR=nc

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
          OUT=<dir>                         输出目录（默认 build/regress_$(SIMULATOR)）
          SIMULATOR=vcs|nc|xlm              仿真器（默认 vcs；NC 同样全面支持）
        产出（默认 build/regress_$(SIMULATOR)/，OUT 显式给定时按 OUT）：
          $(OUT)/simv, simv.daidir/                 VCS 编译产物（SIMULATOR=vcs）
          $(OUT)/INCA_libs/                         NC 编译库（SIMULATOR=nc）
          $(OUT)/<test>_s<seed>/sim_*.log
          $(OUT)/<test>_s<seed>/result.yaml
          $(OUT)/<test>_s<seed>/waves.fsdb|waves.shm/  如 WAVES=1
          $(OUT)/regr.log
          $(OUT)/report.json
          $(OUT)/regr_junit.xml             JUnit XML（CI 友好）
        示例：
          make regress                                  # 旧 nightly（riscvdv testlist，VCS）
          make regress SIMULATOR=nc                     # 走 NC 路径
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

  make wave_nc TEST=<name>                     ★ NC interactive 波形调试
        用途：用 NC ncsim + SimVision GUI 实时调试单个测试（老师推荐的
              "一边仿真一边看波形"模式）。与 batch `make smoke SIMULATOR=nc
              WAVES=1` 互补：batch 跑完 dump 离线 simvision 看；wave_nc
              启动 ncsim 后挂 SimVision GUI，可以 run/stop/add wave/
              reverse run 实时操作，是 NC 工具链相比 VCS+Verdi 的核心优势。
        耗时：编译 ~5min；之后实时调试（取决于用户操作时间）
        依赖：irun (NC/Incisive)、SimVision GUI、X11 forwarding（远程 ssh
              要加 -X 或本地图形终端）
        变量：
          TEST=<name>           必填。要调试的测试 hex 名（去掉 .hex）
                                例：TEST=smoke 读 tests/asm/smoke.hex
        产出：
          build/wave_nc_<TEST>/                NC interactive 工作目录
          build/wave_nc_<TEST>/<TEST>_s1/waves.shm/   SHM 数据库（可离线再看）
        示例：
          make wave_nc TEST=smoke           # 调试 smoke
          make wave_nc TEST=nop             # 调试 nop
        交互式命令（ncsim 启动后在 SimVision 或 ncsim shell 用）：
          run 100ns                        # 前进 100ns
          add wave -position end /core_eh2_tb_top/dut/veer/exu/*
                                           # 加信号到波形窗口
          stop -name brk1 -object <signal> # 设断点
          run                              # 继续到断点
          reverse run                      # 反向调试（部分版本支持）
          quit                             # 退出

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
          SCOPE=full|build|cov|vcs|nc|syn|formal|asm|docs    范围（默认 full）
              full     —— build/ 可再生产物 + 根残留（最常用）
              build    —— 只清 build/（保留清单见下）
              cov      —— 只清覆盖率数据库（cov.vdb/cov_report/cov_work/cov_merged）
              vcs      —— 只清所有 *_vcs 子目录（保留 NC 产物）
              nc       —— 只清所有 *_nc 子目录（保留 VCS 产物）
              syn      —— 只清 syn/build/（wrapper 下次 syn-dc 自动重建）
              formal   —— 只清 dv/formal/build/
              asm      —— 只清 tests/asm 产物（hex/elf/dis）
              docs     —— 只清 docs/sphinx_cn/build/
          FORCE=0|1                  彻底删（默认 0）
              0 —— 保留这些关键目录：
                   r3b_final / r4a_final / nightly       sign-off 证据
                   simv / simv.daidir / simv.vdb          VCS 编译产物
                   cov / cov.vdb / cov_report             VCS 覆盖率数据库
                   INCA_libs / cov_work                   NC (irun) 编译产物 + 覆盖率
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
          make clean SCOPE=vcs               # 只清 *_vcs 子目录（保 NC）
          make clean SCOPE=nc                # 只清 *_nc 子目录（保 VCS）
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
    SIMULATOR        compile / smoke / regress / signoff / signoff_replay / demo
                                                                        （默认 vcs；nc/xlm 可选）
    PARALLEL         regress / signoff / demo                           （默认 4）
    SEED             regress / signoff                                  （默认 1）
    COV              compile / smoke / regress / signoff                （顶层默认 1；显式 COV=0 关）
    WAVES            compile / smoke / regress / signoff / demo         （默认 0，详见"查看波形"小节）
                     compliance 不支持 WAVES（验证靠 signature 比对）
                     wave_nc 永远开启波形（target 本身的语义）
    NO_COSIM         cosim / compile                                    （默认 0）
    TEST             regress / wave_nc                                  （wave_nc 必填）

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
    DEMO_OUT=<dir>                    输出目录（默认 build/demo_$(SIMULATOR)）

  wave_nc：
    TEST=<name>                       必填，要 GUI 调试的 hex 名（去掉 .hex）

  clean：
    SCOPE=full|build|cov|vcs|nc|syn|formal|asm|docs   清理范围
    FORCE=0|1                         绕过保护清单（默认 0）
    MODE=delete|archive               清理模式
    DRY_RUN=0|1                       干跑

──────────────────────────────────────────────────────────────────────────────
[ 关键产物目录索引 ]
──────────────────────────────────────────────────────────────────────────────

  build/                              通用构建目录（gitignored）
    ├── libcosim.so / spike_objs/            Spike DPI 库（保留）
    ├── r3b_final/ / r4a_final/              v1.1 sign-off 证据（保留）
    ├── archive_signoffs_<date>              历史归档软链（保留）
    │
    ├── compile_vcs/ / compile_nc/           make compile（默认清除）
    ├── smoke_vcs/   / smoke_nc/             make smoke
    ├── regress_vcs/ / regress_nc/           make regress
    ├── signoff_vcs/ / signoff_nc/           make signoff
    ├── signoff_replay_vcs/ / signoff_replay_nc/   make signoff_replay
    ├── demo_vcs/    / demo_nc/              make demo
    └── wave_nc_<test>/                      make wave_nc TEST=<name>

  build/<target>_<simulator>/         per-target 岛屿布局（make clean 默认清除）
    ├── simv / simv.daidir / csrc/          VCS 编译产物（SIMULATOR=vcs）
    ├── cov.vdb / cov / cov_report/         VCS 覆盖率数据库（COV=1）
    ├── INCA_libs/                          NC 编译产物（SIMULATOR=nc）
    ├── cov_work/                           NC 覆盖率数据库（COV=1）
    ├── cov_merged/                         sign-off 合并覆盖率（URG/IMC 输出）
    ├── report.html                         HTML 报告（仅 signoff/demo）
    └── compile.log                          编译日志

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

  查看波形（仿真类 target 的通用调试手段）：
    原则：所有跑仿真的 target（smoke / regress / signoff / demo）都原生支持
          WAVES=1，默认关以节省磁盘（单测 fsdb 通常 50-200 MB，shm 量级类似）。
    机制：WAVES=1 同时影响编译期与运行期：
            VCS (默认)  —— `vcs -kdb -debug_access+all` + 运行期
                          `+UVM_VERDI_TRACE=UVM_AWARE+RAL+HIER+COMPWAVE`
                          `+UVM_TR_RECORD`
                          `-ucli -do dv/uvm/core_eh2/vcs.tcl`，
                          dump FSDB 并记录 Verdi UVM Hier / component 细节。
            NC          —— irun 在 compile 时已加 `-access +rwc`；运行期
                          注入 SHM dump（dv/uvm/core_eh2/nc_waves.tcl）。
                          单测交互式调试推荐 `make wave_nc TEST=<name>`，
                          会挂 SimVision GUI 边跑边看。
          make 自动传播 WAVES=1 到编译+运行，命令行加一次即可。
    产物：每个测试 work_dir 下的 waves.fsdb (VCS) 或 waves.shm/ (NC)。

    最短示例（按耗时升序）：
      # smoke ——1 分钟出 fsdb，演示首选
      make smoke WAVES=1
      verdi -ssf build/smoke_vcs/smoke_s1/waves.fsdb &

      # smoke (NC) —— 走 SHM
      make smoke SIMULATOR=nc WAVES=1
      simvision build/smoke_nc/smoke_s1/waves.shm &

      # regress 单测 —— 调试某个具体测试
      make regress TEST=riscv_arithmetic_basic_test SEED=1 WAVES=1
      verdi -ssf build/regress_vcs/riscv_arithmetic_basic_test_s1/waves.fsdb &

      # signoff —— 所有 stage 都 dump（磁盘显著上升）
      make signoff WAVES=1
      verdi -ssf build/signoff_vcs/runs/directed/<test>_s<seed>/waves.fsdb &

      # demo —— 与 signoff 同结构
      make demo WAVES=1
      verdi -ssf build/demo_vcs/runs/<stage>/<test>_s<seed>/waves.fsdb &

      # NC 交互式调试（边仿真边看波形，无需先跑完）
      make wave_nc TEST=smoke   # 启动 ncsim + SimVision GUI

    查看器：verdi -ssf <waves.fsdb>       VCS / FSDB（推荐，KDB 自动联动源码）
            simvision <waves.shm>         NC / SHM（也可由 wave_nc 自动挂起）
    注：compliance 不支持 WAVES（验证靠 signature 比对，无需波形）。

  开发自检（30 分钟）：
    make regress TESTLIST=directed
    make lint
    make formal

  完整 sign-off（不重综合，~1.5 小时）：
    make compile COV=1
    make signoff COV=1

  完整端到端演示 / release 自检（2-3 小时）：
    make clean && make demo
    xdg-open build/demo_vcs/report.html

  v1.1 数字快速复演（< 30 秒）：
    make signoff_replay STAGE_DATA_DIR=build/r3b_final

  CI gate（只评估、不重跑）：
    make signoff GATE_ONLY=1

  双 simulator 并行（资源充足时，互不干扰）：
    make signoff SIMULATOR=vcs & make signoff SIMULATOR=nc

  清理但保留 sign-off 证据：
    make clean

  仅清 VCS / NC 一侧产物（保另一侧）：
    make clean SCOPE=vcs
    make clean SCOPE=nc

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

# DPI header (svdpi.h) lookup. NC (Cadence Incisive) is the default simulator
# so we prefer its header path; fall back to VCS for environments where only
# Synopsys is available. Override by exporting SVDPI_INCLUDE to a directory
# containing svdpi.h.
NC_INSTALL    ?= /home/cadence/INCISIVE152
SVDPI_INCLUDE ?= $(firstword \
  $(wildcard $(NC_INSTALL)/tools/include/svdpi.h) \
  $(wildcard $(VCS_HOME)/include/svdpi.h))
SVDPI_INCLUDE_DIR := $(dir $(SVDPI_INCLUDE))

cosim: $(LIBCOSIM)

$(LIBCOSIM): $(COSIM_DIR)/spike_cosim.cc $(COSIM_DIR)/cosim_dpi.cc \
             $(COSIM_DIR)/spike_cosim.h $(COSIM_DIR)/cosim.h | $(BUILD_DIR)
	@if [ ! -d "$(SPIKE_INSTALL)" ]; then \
	  echo "ERROR: SPIKE_INSTALL=$(SPIKE_INSTALL) 不存在。"; \
	  echo "       先 build spike-cosim，或设 SPIKE_DIR=<path>，或传 NO_COSIM=1 跳过 cosim。"; \
	  exit 1; \
	fi
	@if [ -z "$(SVDPI_INCLUDE)" ]; then \
	  echo "ERROR: 找不到 svdpi.h。请设置 NC_INSTALL 指向 INCISIVE 安装根，"; \
	  echo "       或设置 VCS_HOME 指向 VCS 安装根，或显式 SVDPI_INCLUDE=<dir>。"; \
	  exit 1; \
	fi
	@echo "=== [cosim] 构建 Spike DPI libcosim.so (svdpi from: $(SVDPI_INCLUDE_DIR)) ==="
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
	  -I$(SVDPI_INCLUDE_DIR) \
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
	  +define+UVM_VERDI_COMPWAVE \
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
	  -kdb \
	  $(if $(filter 1,$(COV)),$(VCS_COMPILE_COV_OPTS),)
	@echo "=== [compile] simv 完成: $(BUILD_SUBDIR)/simv ==="

compile_nc: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
	@echo "=== [compile] NC (irun) UVM testbench (BUILD_SUBDIR=$(BUILD_SUBDIR)) ==="
	@mkdir -p $(BUILD_SUBDIR)
	$(IRUN) -64bit -uvmhome $(NC_UVM_HOME) -sv -assert \
	  -vlog_ext +.vh \
	  +define+UVM_NO_DEPRECATED \
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
	  -elaborate \
	  -nclibdirname $(BUILD_SUBDIR)/INCA_libs \
	  -access +rwc \
	  -timescale 1ns/1ps \
	  -errormax 500 \
	  $(if $(COMPILE_LIBCOSIM_LINK),-sv_lib $(COMPILE_LIBCOSIM_LINK),) \
	  -l $(BUILD_SUBDIR)/compile.log \
	  $(if $(filter 1,$(COV)),$(NC_COMPILE_COV_OPTS),)
	@# NC 作为 VCS 备选 simulator，与 VCS 一样收覆盖率参与 sign-off。
	@# 覆盖率通过 cov_full_nc.ccf 限定 dut-only scope（与 cover.cfg 等价）。
	@echo "=== [compile] NC 完成: $(BUILD_SUBDIR)/INCA_libs ==="

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
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(BUILD_DIR)/smoke_$(SIMULATOR)
	@echo "=== [smoke] 运行 smoke 测试 ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --test smoke \
	  --binary $(ASM_DIR)/smoke.hex \
	  --simulator $(SIMULATOR) \
	  --seed 1 \
	  --rtl-test core_eh2_base_test \
	  --sim-opts "+disable_cosim=1" \
	  --build-dir $(BUILD_DIR)/smoke_$(SIMULATOR) \
	  --output $(BUILD_DIR)/smoke_$(SIMULATOR) \
	  $(if $(filter 1,$(COV)),--coverage,) \
	  $(if $(filter 1,$(WAVES)),--waves,)
	@echo "=== [smoke] 完成 ==="

regress:
	@$(MAKE) --no-print-directory compile BUILD_SUBDIR=$(BUILD_DIR)/regress_$(SIMULATOR)
	@echo "=== [regress] testlist=$(TESTLIST) parallel=$(PARALLEL) iter=$(ITERATIONS) ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  $(if $(TEST),--test $(TEST) --testlist $(TESTLIST_PATH),--testlist $(TESTLIST_PATH)) \
	  --simulator $(SIMULATOR) \
	  --seed $(SEED) \
	  --iterations $(ITERATIONS) \
	  --parallel $(PARALLEL) \
	  --build-dir $(BUILD_DIR)/regress_$(SIMULATOR) \
	  --output $(if $(OUT),$(OUT),$(BUILD_DIR)/regress_$(SIMULATOR)) \
	  $(if $(filter 1,$(COV)),--coverage,) \
	  $(if $(filter 1,$(WAVES)),--waves,)
	@echo "=== [regress] 完成 ==="

compliance:
	@echo "=== [compliance] mode=$(or $(MODE),run) ==="
	+@$(MAKE) -C dv/uvm/riscv_compliance $(if $(filter all,$(MODE)),compliance-all,$(if $(filter compile,$(MODE)),compliance-compile,compliance))

# ============================================================
# NC interactive waveform debug — `make wave_nc TEST=<name>`
#
# 启动 NC ncsim + SimVision GUI 实时调试单个测试（老师推荐的
# "一边仿真一边看波形"模式）。与 batch `make smoke SIMULATOR=nc WAVES=1`
# 互补：batch 模式跑完 dump 离线看；interactive 模式 ncsim 启动后挂载
# SimVision，用户可以 run/stop/add wave/reverse run 实时操作。
#
# 不收覆盖率（debug 用途），不参与 sign-off。
# ============================================================
wave_nc: asm
	@if [ -z "$(TEST)" ]; then \
	  echo "ERROR: 必须指定 TEST=<name>，例：make wave_nc TEST=smoke"; \
	  exit 1; \
	fi
	@echo "=== [wave_nc] NC interactive debug: TEST=$(TEST) ==="
	@echo "    SimVision GUI 将启动；需要 X11 forwarding 或本地图形终端。"
	@echo "    ncsim 进入交互式 shell 后，常用命令："
	@echo "      run 100ns         前进 100ns 看波形"
	@echo "      add wave ...      添加信号到 SimVision"
	@echo "      stop -name brk1   设断点"
	@echo "      quit              退出"
	@mkdir -p $(BUILD_DIR)/wave_nc_$(TEST)/$(TEST)_s1
	@# 在项目根目录跑 irun（不 cd 进子目录，否则 filelist 中的相对路径会找不到文件）。
	@# 产物路径用 $(BUILD_DIR)/wave_nc_$(TEST)/ 集中。
	@SIM_DIR=$(CURDIR)/$(BUILD_DIR)/wave_nc_$(TEST)/$(TEST)_s1 \
	  irun -64bit -uvmhome $(NC_UVM_HOME) -sv -assert \
	    -vlog_ext +.vh +define+UVM_NO_DEPRECATED +define+GTLSIM \
	    rtl/snapshots/default/common_defines.vh \
	    +incdir+rtl/snapshots/default \
	    +incdir+$(TB_DIR)/common/axi4_agent \
	    +incdir+$(TB_DIR)/common/trace_agent \
	    +incdir+$(TB_DIR)/common/irq_agent \
	    +incdir+$(TB_DIR)/common/jtag_agent \
	    +incdir+$(TB_DIR)/common/cosim_agent \
	    +incdir+dv/cosim \
	    -f $(RTL_F) -f $(SHARED_F) -f $(TB_F) \
	    -top core_eh2_tb_top \
	    -nclibdirname $(BUILD_DIR)/wave_nc_$(TEST)/INCA_libs \
	    -access +rwc -timescale 1ns/1ps -errormax 500 \
	    -sv_lib $(CURDIR)/build/libcosim.so \
	    +UVM_TESTNAME=core_eh2_base_test \
	    +bin=$(ASM_DIR)/$(TEST).hex \
	    +seed=1 +timeout_ns=10000000 \
	    -l $(BUILD_DIR)/wave_nc_$(TEST)/$(TEST)_s1/sim.log \
	    -gui \
	    -input $(TB_DIR)/nc_waves_interactive.tcl
	@echo "=== [wave_nc] 退出 ==="

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
# LEC stage flags. Default LEC_BLOCKLEVEL=1 reads syn/build/lec_summary.txt;
# if that summary is missing (no synth run yet), fall back to
# --lec-known-limited so signoff still produces a verdict (matches the
# auto-fallback already in the `demo` target).
SIGNOFF_LEC_OPTS := $(if $(filter 1,$(LEC_BLOCKLEVEL)),$(if $(wildcard $(LEC_SUMMARY_PATH)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),--lec-known-limited),$(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,))

signoff:
	@# VCS 是 sign-off 默认；NC 也可作 cross-check（覆盖率独立合并，
	@# 维度名与 VCS 同构但工具不同，参见 cover.cfg / cov_full_nc.ccf）。
	@if [ "$(SIMULATOR)" != "vcs" ] && [ "$(SIMULATOR)" != "nc" ]; then \
	  echo "ERROR: signoff 仅支持 SIMULATOR=vcs (默认) 或 SIMULATOR=nc (当前为 $(SIMULATOR))。"; \
	  exit 1; \
	fi
	@if [ "$(SIMULATOR)" = "nc" ]; then \
	  echo "[signoff] 注意：当前用 NC simulator (备选)。VCS 是 sign-off 默认。"; \
	fi
	@$(if $(filter 1,$(GATE_ONLY)),,$(MAKE) --no-print-directory asm)
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
	  $(SIGNOFF_LEC_OPTS) \
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
	  --simulator $(SIMULATOR) \
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
	  $(if $(wildcard $(STAGE_DATA_DIR)/cov_merged/dashboard.txt),--coverage-path $(STAGE_DATA_DIR)/cov_merged/dashboard.txt,) \
	  --allow-warnings \
	  $(SIGNOFF_OPTS)
	@echo "=== [signoff_replay] 完成。报告：$(SIGNOFF_REPLAY_OUT)/report.html ==="

demo:
	@# VCS 是 demo 默认；NC 也支持作为备选 simulator（数据真实工业级）。
	@if [ "$(SIMULATOR)" != "vcs" ] && [ "$(SIMULATOR)" != "nc" ]; then \
	  echo "ERROR: demo 仅支持 SIMULATOR=vcs (默认) 或 SIMULATOR=nc (当前为 $(SIMULATOR))。"; \
	  exit 1; \
	fi
	@if [ "$(SIMULATOR)" = "nc" ]; then \
	  echo "[demo] 注意：当前用 NC simulator (备选)。VCS 是 demo 默认。"; \
	fi
	@echo "================================================================="
	@echo "  EH2 Demo  (清理 → 构建 → sign-off → 报告)"
	@echo "  SIMULATOR=$(SIMULATOR)   WITH_SYNTH=$(WITH_SYNTH)   PARALLEL=$(PARALLEL)   COV=1   输出=$(DEMO_OUT)"
	@echo "================================================================="
	@# 只清自己的输出目录，保留 build/libcosim.so 和其它 target 的产物
	@# （build/smoke, build/signoff 等不受影响）。
	@rm -rf $(DEMO_OUT)
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
	  $(MAKE) --no-print-directory signoff SIMULATOR=$(SIMULATOR) SIGNOFF_OUT=$(DEMO_OUT) PARALLEL=$(PARALLEL) COV=1; \
	else \
	  echo "[demo] LEC summary 缺失，启用 LEC_KNOWN_LIMITED=1 兜底（COV=1 全量收集）"; \
	  $(MAKE) --no-print-directory signoff SIMULATOR=$(SIMULATOR) SIGNOFF_OUT=$(DEMO_OUT) PARALLEL=$(PARALLEL) COV=1 \
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
	      \( -name 'cov.vdb' -o -name 'cov' -o -name 'cov_report' -o -name 'simv.vdb' \
	         -o -name 'cov_work' -o -name 'cov_merged' \) \
	      -exec rm -rf {} + 2>/dev/null || true; \
	    echo "[clean] 已清各 target 子目录下的覆盖率数据库（VCS cov.vdb / NC cov_work / 合并产物 cov_merged）" ;; \
	  vcs) \
	    find $(BUILD_DIR) -mindepth 1 -maxdepth 1 -name '*_vcs' -exec rm -rf {} + 2>/dev/null || true; \
	    echo "[clean] 已清所有 *_vcs 子目录（保留 NC 产物）" ;; \
	  nc) \
	    find $(BUILD_DIR) -mindepth 1 -maxdepth 1 -name '*_nc' -exec rm -rf {} + 2>/dev/null || true; \
	    echo "[clean] 已清所有 *_nc 子目录（保留 VCS 产物）" ;; \
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
	    rm -f irun.log irun.history ncsim.log .simvision; \
	    rm -rf INCA_libs cov_work; \
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
