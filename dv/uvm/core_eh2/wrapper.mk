# SPDX-License-Identifier: Apache-2.0
# Ibex-style EH2 DV wrapper.

all: collect_results

.PHONY: core_config
.PHONY: instr_gen_build
.PHONY: instr_gen_run
.PHONY: compile_riscvdv_tests
.PHONY: compile_directed_tests
.PHONY: rtl_tb_compile
.PHONY: rtl_sim_run
.PHONY: check_logs
.PHONY: riscv_dv_fcov
.PHONY: merge_cov
.PHONY: collect_results
.PHONY: signoff
.PHONY: dump

SHELL := bash
PRJ_DIR ?= $(realpath ../../..)
OUT-DIR ?= $(PRJ_DIR)/out
METADATA-DIR ?= $(OUT-DIR)/metadata
SIMULATOR ?= vcs
TEST ?= all
SEED ?= 1
ITERATIONS ?=
PARALLEL ?= 1
COV ?= 0
WAVES ?= 0
SIGNOFF_PROFILE ?= full
SIGNOFF_OPTS ?=
SIGNOFF_ITERATIONS ?=

export PYTHONPATH ?= $(shell python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')

include scripts/util.mk
-include scripts/get_meta.mk

OUT-DIR := $(call get-meta,dir_out)
TESTS-DIR := $(call get-meta,dir_tests)
BUILD-DIR := $(call get-meta,dir_build)
RUN-DIR := $(call get-meta,dir_run)
METADATA-DIR := $(call get-meta,dir_metadata)

riscvdv-ts := $(call get-meta,riscvdv_tds)
directed-ts := $(call get-meta,directed_tds)

asm-stem := test.S
bin-stem := test.bin
hex-stem := test.hex
rtl-sim-logfile := rtl_sim.log
trr-stem := trr.yaml

riscvdv-dirs = $(foreach ts,$(riscvdv-ts),$(TESTS-DIR)/$(ts)/)
directed-dirs = $(foreach ts,$(directed-ts),$(TESTS-DIR)/$(ts)/)
ts-dirs := $(riscvdv-dirs) $(directed-dirs)

riscvdv-test-asms = $(addsuffix $(asm-stem),$(riscvdv-dirs))
riscvdv-test-bins = $(addsuffix $(bin-stem),$(riscvdv-dirs))
directed-test-bins = $(addsuffix $(bin-stem),$(directed-dirs))
test-bins := $(riscvdv-test-bins) $(directed-test-bins)
rtl-sim-logs = $(addsuffix $(rtl-sim-logfile),$(ts-dirs))
comp-results = $(addsuffix $(trr-stem),$(ts-dirs))

$(BUILD-DIR) $(TESTS-DIR) $(METADATA-DIR):
	@mkdir -p $@

core_config: $(METADATA-DIR)/core.config.stamp
$(METADATA-DIR)/core.config.stamp: scripts/render_config_template.py | $(BUILD-DIR) $(METADATA-DIR)
	@echo Generating EH2 riscv-dv core configuration
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/render_config_template.py \
	    --dir-metadata $(METADATA-DIR) \
	    riscv_dv_extension/riscv_core_setting.tpl.sv \
	    > riscv_dv_extension/riscv_core_setting.sv
	@touch $@

instr_gen_build: $(METADATA-DIR)/instr.gen.build.stamp
$(METADATA-DIR)/instr.gen.build.stamp: core_config scripts/build_instr_gen.py | $(BUILD-DIR)
	@echo Building randomized test generator
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/build_instr_gen.py \
	    --dir-metadata $(METADATA-DIR)
	@touch $@

instr_gen_run: $(riscvdv-test-asms)
$(riscvdv-test-asms): $(TESTS-DIR)/%/$(asm-stem): instr_gen_build scripts/run_instr_gen.py
	@echo Running randomized test generator for $*
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/run_instr_gen.py \
	    --dir-metadata $(METADATA-DIR) \
	    --test-dot-seed $*
	$(verb)cp $$(find $(@D) -name '*.S' | sort | head -n 1) $@

compile_riscvdv_tests: $(riscvdv-test-bins)
$(riscvdv-test-bins): $(TESTS-DIR)/%/$(bin-stem): $(TESTS-DIR)/%/$(asm-stem) scripts/compile_test.py
	@echo Compiling riscv-dv test $*
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/compile_test.py \
	    --dir-metadata $(METADATA-DIR) \
	    --test-dot-seed $*

compile_directed_tests: $(directed-test-bins)
$(directed-test-bins): $(TESTS-DIR)/%/$(bin-stem): scripts/compile_test.py | $(TESTS-DIR)
	@echo Compiling directed test $*
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/compile_test.py \
	    --dir-metadata $(METADATA-DIR) \
	    --test-dot-seed $*

rtl_tb_compile:
	$(verb)$(MAKE) -C $(PRJ_DIR) compile GOAL= SIMULATOR=$(SIMULATOR) COV=$(COV) WAVES=$(WAVES)

rtl_sim_run: $(rtl-sim-logs)
$(rtl-sim-logs): $(TESTS-DIR)/%/$(rtl-sim-logfile): rtl_tb_compile $(TESTS-DIR)/%/$(bin-stem) scripts/run_rtl.py
	@echo Running RTL simulation for $*
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/run_rtl.py \
	    --dir-metadata $(METADATA-DIR) \
	    --test-dot-seed $*
	$(verb)cp $(@D)/sim_$$(echo $* | sed 's/\.[0-9][0-9]*$$//')_$$(echo $* | sed 's/^.*\.//').log $@

check_logs: $(comp-results)
$(comp-results): $(TESTS-DIR)/%/$(trr-stem): $(TESTS-DIR)/%/$(rtl-sim-logfile) scripts/check_logs.py
	@echo Checking RTL log for $*
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/check_logs.py \
	    --dir-metadata $(METADATA-DIR) \
	    --test-dot-seed $*

riscv_dv_fcov:
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/get_fcov.py --dir-metadata $(METADATA-DIR) --simulator $(SIMULATOR)

merge_cov:
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/merge_cov.py --dir-metadata $(METADATA-DIR)

collect_results: $(comp-results)
	@echo Collecting regression results
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/collect_results.py \
	    --dir-metadata $(METADATA-DIR) \
	    --output-dir $(OUT-DIR)

signoff:
	$(verb)env PYTHONPATH=$(PYTHONPATH) \
	  python3 scripts/signoff.py \
	    --profile $(SIGNOFF_PROFILE) \
	    --simulator $(SIMULATOR) \
	    --seed $(SEED) \
	    --parallel $(PARALLEL) \
	    --output $(OUT-DIR)/signoff \
	    $(if $(SIGNOFF_ITERATIONS),--iterations $(SIGNOFF_ITERATIONS),) \
	    $(if $(filter 1,$(COV)),--coverage --require-coverage,) \
	    $(SIGNOFF_OPTS)

dump:
	@echo "OUT-DIR=$(OUT-DIR)"
	@echo "METADATA-DIR=$(METADATA-DIR)"
	@echo "TESTS-DIR=$(TESTS-DIR)"
	@echo "riscvdv-ts=$(riscvdv-ts)"
	@echo "directed-ts=$(directed-ts)"
