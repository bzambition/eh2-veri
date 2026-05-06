# EH2 UVM Verification Platform - Top-level Makefile
#
# Targets:
#   compile    - Compile the RTL testbench
#   smoke      - Run smoke tests (basic instruction test)
#   nightly    - Run nightly regression (full test suite)
#   weekly     - Run weekly regression (full + stress)
#   signoff    - Run sign-off regression gate
#   run        - Run a single test
#   gen        - Generate riscv-dv instructions
#   cov        - Collect and merge coverage
#   clean      - Clean build artifacts
#
# Variables:
#   CONFIG     - Configuration profile (default|minimal|dual_thread)
#   SEED       - Random seed (default: 1)
#   TEST       - Test name (default: riscv_arithmetic_basic_test)
#   SIMULATOR  - Simulator: vcs|xlm|questa (default: vcs)
#   BINARY     - Pre-built test binary path
#   WAVES      - Enable waveform dump (0|1, default: 0)
#   COV        - Enable coverage (0|1, default: 0)
#   ITERATIONS - Number of iterations (default: 1)
#   PARALLEL   - Parallel test runs (default: 1)

SHELL := /bin/bash

# Source environment
-include env.mk

# Ibex-style staged entry point. When GOAL is set, `make run GOAL=...` creates
# regression metadata and delegates to dv/uvm/core_eh2/wrapper.mk.
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

# Directories
RTL_DIR      := rtl/design
SNAPSHOTS    := rtl/snapshots/default
TB_DIR       := dv/uvm/core_eh2
SHARED_DIR   := shared/rtl
COSIM_DIR    := dv/cosim
SCRIPTS_DIR  := $(TB_DIR)/scripts
DV_EXT_DIR   := $(TB_DIR)/riscv_dv_extension
RISCV_DV_DIR := vendor/google_riscv-dv

# Configuration
CONFIG      ?= default
SEED        ?= 1
TEST        ?= riscv_arithmetic_basic_test
SIMULATOR   ?= vcs
BINARY      ?=
VERBOSITY   ?= UVM_MEDIUM
TIMEOUT_NS  ?= 10000000
WAVES       ?= 0
COV         ?= 0
ITERATIONS  ?= 1
PARALLEL    ?= 1
RTL_TEST    ?= core_eh2_base_test
SIM_OPTS    ?=
GEN_OPTS    ?=
SIGNOFF_PROFILE ?= full
SIGNOFF_OUT ?= $(BUILD_DIR)/signoff
SIGNOFF_OPTS ?=
SIGNOFF_ITERATIONS ?=
SIGNOFF_QUICK_OUT = $(if $(filter command% environment%,$(origin SIGNOFF_OUT)),$(SIGNOFF_OUT),$(BUILD_DIR)/signoff_quick)
ISS         ?= spike
VERBOSE     ?= 0
SIGNATURE_ADDR ?= d0580000

# Simulator command
VCS         := vcs
XLM         := xrun
QUESTA      := questa

# Build directory
BUILD_DIR   := build
OUT_DIR     := $(BUILD_DIR)/$(TEST)_$(SEED)

# Define files from snapshot
DEFINES     := $(SNAPSHOTS)/common_defines.vh

# Filelists
RTL_F       := $(TB_DIR)/eh2_rtl.f
SHARED_F    := $(TB_DIR)/eh2_shared.f
TB_F        := $(TB_DIR)/eh2_tb.f

.PHONY: help compile compile_vcs compile_xlm run gen smoke nightly weekly \
        regress signoff signoff_quick signoff_gate clean

# -----------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------
help:
	@echo "EH2 UVM Verification Platform"
	@echo "=============================="
	@echo ""
	@echo "Build Targets:"
	@echo "  compile     - Compile RTL testbench (default: VCS)"
	@echo "  compile_vcs - Compile with VCS"
	@echo "  compile_xlm - Compile with Xcelium"
	@echo ""
	@echo "Test Targets:"
	@echo "  smoke       - Quick smoke test (1 iteration)"
	@echo "  run         - Run single test (TEST=, SEED=)"
	@echo "  nightly     - Nightly regression (~50 tests)"
	@echo "  weekly      - Weekly regression (~100 tests)"
	@echo "  signoff     - Full sign-off gate (profile=$(SIGNOFF_PROFILE))"
	@echo "  signoff_quick - Quick sign-off gate (smoke + directed)"
	@echo "  signoff_gate  - Evaluate existing sign-off results"
	@echo ""
	@echo "Utility Targets:"
	@echo "  gen         - Generate riscv-dv instructions (TEST=)"
	@echo "  regress     - Full regression via Python script"
	@echo "  cov         - Collect and merge coverage"
	@echo "  clean       - Clean build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  CONFIG      - Configuration (default|minimal|dual_thread)"
	@echo "  SEED        - Random seed (default: 1)"
	@echo "  TEST        - Test name"
	@echo "  SIMULATOR   - vcs|xlm|questa (default: vcs)"
	@echo "  BINARY      - Pre-built binary path"
	@echo "  WAVES       - Waveform dump (0|1)"
	@echo "  COV         - Coverage (0|1)"
	@echo "  ITERATIONS  - Number of iterations"
	@echo "  PARALLEL    - Parallel runs (default: 1)"
	@echo "  SIGNOFF_PROFILE - quick|cosim|nightly|full"
	@echo "  SIGNOFF_OUT - Sign-off output directory"
	@echo "  SIGNOFF_ITERATIONS - Optional sign-off iteration override"

# -----------------------------------------------------------------------
# Build directory
# -----------------------------------------------------------------------
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -----------------------------------------------------------------------
# VCS compilation
# -----------------------------------------------------------------------
compile_vcs: | $(BUILD_DIR)
	@echo "=== Compiling with VCS ==="
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
	  $(if $(wildcard $(BUILD_DIR)/libcosim.so),$(CURDIR)/$(BUILD_DIR)/libcosim.so,) \
	  -o $(BUILD_DIR)/simv \
	  -l $(BUILD_DIR)/compile.log \
	  -timescale=1ns/1ps \
	  $(if $(filter 1,$(WAVES)),-debug_access+all -kdb,) \
	  $(if $(filter 1,$(COV)),-cm line+cond+fsm+tgl+assert -cm_dir $(BUILD_DIR)/cov,)
	@echo "=== Compilation complete ==="

# -----------------------------------------------------------------------
# Co-simulation library compilation (Spike-based)
# -----------------------------------------------------------------------
SPIKE_DIR     ?= /home/host/spike-cosim
SPIKE_INSTALL ?= $(SPIKE_DIR)/install
SPIKE_CXX     ?= /home/Xilinx/Vivado/2019.1/tps/lnx64/gcc-6.2.0/bin/g++
SPIKE_CXXFLAGS ?= -std=c++17 -static-libstdc++
SPIKE_BUILD   ?= $(BUILD_DIR)/spike_objs

cosim: | $(BUILD_DIR)
	@echo "=== Building co-simulation library (Spike) ==="
	@mkdir -p $(SPIKE_BUILD)
	@# Extract Spike library objects into a single directory
	@cd $(SPIKE_BUILD) && \
	  ar x $(SPIKE_INSTALL)/lib/libriscv.a && \
	  rm -f libfdt.a libsoftfloat.a && \
	  ar x $(SPIKE_INSTALL)/lib/libdisasm.a && \
	  ar x $(SPIKE_INSTALL)/lib/libfesvr.a && \
	  ar x $(SPIKE_INSTALL)/lib/libfdt.a && \
	  ar rcs libspike_all.a *.o
	@# Compile and link
	$(SPIKE_CXX) -shared -fPIC -O2 -g \
	  -I$(COSIM_DIR) \
	  -I$(SPIKE_INSTALL)/include \
	  -I$(SPIKE_INSTALL)/include/softfloat \
	  -I$(VCS_HOME)/include \
	  $(SPIKE_CXXFLAGS) \
	  -o $(BUILD_DIR)/libcosim.so \
	  $(COSIM_DIR)/spike_cosim.cc \
	  $(COSIM_DIR)/cosim_dpi.cc \
	  -L$(SPIKE_BUILD) -lspike_all \
	  $(SPIKE_DIR)/build/libsoftfloat.a \
	  -lpthread -ldl
	@echo "=== Co-simulation library built ==="

# -----------------------------------------------------------------------
# Xcelium compilation
# -----------------------------------------------------------------------
compile_xlm: | $(BUILD_DIR)
	@echo "=== Compiling with Xcelium ==="
	cd $(BUILD_DIR) && $(XLM) -uvm -sv \
	  $(DEFINES) \
	  +incdir+$(SNAPSHOTS) \
	  +incdir+../$(TB_DIR)/common/axi4_agent \
	  +incdir+../$(TB_DIR)/common/trace_agent \
	  +incdir+../$(TB_DIR)/common/irq_agent \
	  +incdir+../$(TB_DIR)/common/jtag_agent \
	  +incdir+../$(TB_DIR)/common/cosim_agent \
	  -f ../$(RTL_F) \
	  -f ../$(SHARED_F) \
	  -f ../$(TB_F) \
	  -top core_eh2_tb_top \
	  -l compile.log \
	  $(if $(filter 1,$(COV)),-covoverwrite -covfile ../$(TB_DIR)/cov.ccf,)
	@echo "=== Compilation complete ==="

# Default compile target
compile: compile_$(SIMULATOR)

# -----------------------------------------------------------------------
# Run a single test
# -----------------------------------------------------------------------
run: compile
	@echo "=== Running test: $(TEST) seed=$(SEED) ==="
	@mkdir -p $(OUT_DIR)
	$(BUILD_DIR)/simv \
	  +UVM_TESTNAME=$(RTL_TEST) \
	  +bin=$(BINARY) \
	  +seed=$(SEED) \
	  +timeout_ns=$(TIMEOUT_NS) \
	  +UVM_VERBOSITY=$(VERBOSITY) \
	  $(SIM_OPTS) \
	  $(if $(filter 1,$(WAVES)),+fsdb+functions,) \
	  $(if $(filter 1,$(COV)),-cm line+cond+fsm+tgl+assert +enable_eh2_fcov=1,) \
	  -l $(OUT_DIR)/sim.log
	@echo "=== Test complete: $(TEST) ==="

# -----------------------------------------------------------------------
# Generate riscv-dv instructions
# -----------------------------------------------------------------------
gen: | $(BUILD_DIR)
	@echo "=== Generating riscv-dv instructions: $(TEST) ==="
	@mkdir -p $(OUT_DIR)
	python3 $(SCRIPTS_DIR)/run_instr_gen.py \
	  --riscv-dv-dir $(RISCV_DV_DIR) \
	  --work-dir $(OUT_DIR) \
	  --test $(TEST) \
	  --gen-opts "$(GEN_OPTS)" \
	  --seed $(SEED) \
	  --iterations $(ITERATIONS)
	@echo "=== Generation complete ==="

# -----------------------------------------------------------------------
# Smoke test: quick sanity check
# -----------------------------------------------------------------------
smoke: compile
	@echo "=== Running smoke tests ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --test riscv_arithmetic_basic_test \
	  --simulator $(SIMULATOR) \
	  --seed 1 \
	  --output $(BUILD_DIR)/smoke
	@echo "=== Smoke tests complete ==="

# -----------------------------------------------------------------------
# Nightly regression
# -----------------------------------------------------------------------
nightly: compile
	@echo "=== Running nightly regression ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --testlist $(DV_EXT_DIR)/testlist.yaml \
	  --simulator $(SIMULATOR) \
	  --iterations 1 \
	  --parallel $(PARALLEL) \
	  --output $(BUILD_DIR)/nightly
	@echo "=== Nightly regression complete ==="

# -----------------------------------------------------------------------
# Weekly regression (more iterations + stress tests)
# -----------------------------------------------------------------------
weekly: compile
	@echo "=== Running weekly regression ==="
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --testlist $(DV_EXT_DIR)/testlist.yaml \
	  --simulator $(SIMULATOR) \
	  --iterations 5 \
	  --parallel $(PARALLEL) \
	  --output $(BUILD_DIR)/weekly
	@echo "=== Weekly regression complete ==="

# -----------------------------------------------------------------------
# Full regression via Python script
# -----------------------------------------------------------------------
regress: compile
	python3 $(SCRIPTS_DIR)/run_regress.py \
	  --testlist $(DV_EXT_DIR)/testlist.yaml \
	  --simulator $(SIMULATOR) \
	  --iterations $(ITERATIONS) \
	  --parallel $(PARALLEL) \
	  --output $(BUILD_DIR)/regression

# -----------------------------------------------------------------------
# Sign-off gate
# -----------------------------------------------------------------------
signoff:
	python3 $(SCRIPTS_DIR)/signoff.py \
	  --profile $(SIGNOFF_PROFILE) \
	  --simulator $(SIMULATOR) \
	  --seed $(SEED) \
	  --parallel $(PARALLEL) \
	  --output $(SIGNOFF_OUT) \
	  $(if $(SIGNOFF_ITERATIONS),--iterations $(SIGNOFF_ITERATIONS),) \
	  $(if $(filter 1,$(COV)),--coverage --require-coverage,) \
	  $(if $(filter 1,$(WAVES)),--waves,) \
	  $(SIGNOFF_OPTS)

signoff_quick:
	$(MAKE) signoff SIGNOFF_PROFILE=quick SIGNOFF_OUT=$(SIGNOFF_QUICK_OUT)

signoff_gate:
	python3 $(SCRIPTS_DIR)/signoff.py \
	  --profile $(SIGNOFF_PROFILE) \
	  --simulator $(SIMULATOR) \
	  --output $(SIGNOFF_OUT) \
	  --gate-only \
	  $(SIGNOFF_OPTS)

# -----------------------------------------------------------------------
# Coverage
# -----------------------------------------------------------------------
cov:
	@echo "=== Collecting coverage ==="
	@if [ "$(SIMULATOR)" = "vcs" ]; then \
	  urg -dir $(BUILD_DIR)/cov/simv.vdb -report $(BUILD_DIR)/cov_report; \
	elif [ "$(SIMULATOR)" = "xlm" ]; then \
	  imc -load $(BUILD_DIR)/cov -exec $(TB_DIR)/cov_merge.tcl; \
	fi
	@echo "=== Coverage report: $(BUILD_DIR)/cov_report ==="

# -----------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned build artifacts"

endif
