# EH2 CSR Registers Unit Test Makefile (Issue 56 — REWORKED)
#
# Compiles and runs the stand-alone CSR UVM sub-environment with
# real DUT instantiation and DPI-based CSR read/write.
#
# Modeled after lowRISC Ibex dv/cs_registers/Makefile.
# Supports both VCS and NC/Incisive (irun); pick via SIMULATOR=vcs|nc.

EH2_ROOT   ?= $(realpath $(CURDIR)/../../..)
CSR_DIR    ?= $(CURDIR)
SIGNOFF_OUT ?=

SIMULATOR  ?= nc
SEED       ?= 1
VERBOSITY  ?= UVM_MEDIUM
OUT        ?= out

# VCS UVM paths
VCS_HOME   ?= /home/synopsys/vcs-mx/O-2018.09-1
UVM_HOME   ?= $(VCS_HOME)/etc/uvm-1.2

# NC UVM home (matches top-level Makefile)
NC_UVM_HOME ?= /home/cadence/INCISIVE152/tools/methodology/UVM/CDNS-1.2

# EH2 RTL root (must match actual Cores-VeeR-EH2 checkout)
EH2_RTL_ROOT ?= /home/host/Cores-VeeR-EH2

# Common include paths
INC_DIRS := \
	+incdir+$(CSR_DIR)/env \
	+incdir+$(CSR_DIR)/reg_model \
	+incdir+$(CSR_DIR)/reg_driver \
	+incdir+$(CSR_DIR)/tb \
	+incdir+$(CSR_DIR)/tests \
	+incdir+$(EH2_RTL_ROOT)/snapshots/default

# VCS compile flags
VCS_FLAGS  ?= \
	-sverilog \
	-full64 \
	-timescale=1ns/1ps \
	-ntb_opts uvm-1.2 \
	$(INC_DIRS)

# EH2 RTL source files needed by csr_dut wrapper
EH2_RTL_SRC := \
	$(EH2_RTL_ROOT)/snapshots/default/eh2_pdef.vh \
	$(EH2_RTL_ROOT)/design/include/eh2_def.sv \
	$(EH2_RTL_ROOT)/design/dec/eh2_dec_csr.sv

# CSR sub-environment sources
CSR_TB_SRC := \
	$(EH2_RTL_SRC) \
	$(CSR_DIR)/reg_driver/csr_dpi_pkg.sv \
	$(CSR_DIR)/env/cs_registers_env_cfg.sv \
	$(CSR_DIR)/env/cs_registers_scoreboard.sv \
	$(CSR_DIR)/reg_model/eh2_csr_reg_block.sv \
	$(CSR_DIR)/env/cs_registers_seq_lib.sv \
	$(CSR_DIR)/env/cs_registers_env.sv \
	$(CSR_DIR)/tb/csr_dut.sv \
	$(CSR_DIR)/tb/cs_registers_tb.sv \
	$(CSR_DIR)/tests/cs_registers_test.sv \
	$(CSR_DIR)/tests/cs_registers_access_matrix_test.sv \
	$(CSR_DIR)/tests/cs_registers_illegal_test.sv \
	$(CSR_DIR)/tests/cs_registers_hazard_test.sv

# Build output directory
$(OUT):
	mkdir -p $(OUT)

.PHONY: run-csr-unit run-csr-all compile sim clean help compliance

help:
	@echo "EH2 CSR Unit Test Targets:"
	@echo "  compile       - Compile the CSR testbench (SIMULATOR=vcs|nc)"
	@echo "  run-csr-unit  - Compile and run CSR unit test (single test)"
	@echo "  compliance    - Run 4 tests x 5 seeds (20 sims) for signoff"
	@echo "  clean         - Remove build artifacts"

ifeq ($(SIMULATOR),nc)

compile: $(OUT)
	@echo "=========================================================="
	@echo "Compiling EH2 CSR unit test (NC/irun)..."
	@echo "=========================================================="
	irun -64bit -uvmhome $(NC_UVM_HOME) -sv -assert -vlog_ext +.vh \
	  -timescale 1ns/1ps -errormax 500 \
	  $(INC_DIRS) \
	  $(CSR_TB_SRC) \
	  -top cs_registers_tb \
	  -elaborate -nclibdirname $(OUT)/INCA_libs -access +rwc \
	  -l $(OUT)/compile.log
	@echo "Compilation done (exit: $$?)"

sim: compile
	@echo "=== Running $(TEST) seed=$(SEED) (NC) ==="
	-irun -64bit -uvmhome $(NC_UVM_HOME) -sv -assert -vlog_ext +.vh \
	  -timescale 1ns/1ps \
	  $(INC_DIRS) \
	  $(CSR_TB_SRC) \
	  -top cs_registers_tb \
	  -nclibdirname $(OUT)/INCA_libs -access +rwc \
	  +UVM_TESTNAME=$(TEST) \
	  +UVM_VERBOSITY=$(VERBOSITY) \
	  +ntb_random_seed=$(SEED) \
	  -l $(OUT)/$(TEST)_seed$(SEED).log
	@echo "--- Simulation done (exit: $$?)"

else

compile: $(OUT)
	@echo "=========================================================="
	@echo "Compiling EH2 CSR unit test (VCS)..."
	@echo "=========================================================="
	vcs $(VCS_FLAGS) \
		$(CSR_TB_SRC) \
		-top cs_registers_tb \
		-o $(OUT)/simv \
		-l $(OUT)/compile.log
	@echo "Compilation done (exit: $$?)"

sim: compile
	@echo "=== Running $(TEST) seed=$(SEED) (VCS) ==="
	-./$(OUT)/simv \
		+UVM_TESTNAME=$(TEST) \
		+UVM_VERBOSITY=$(VERBOSITY) \
		+ntb_random_seed=$(SEED) \
		-l $(OUT)/$(TEST)_seed$(SEED).log
	@echo "--- Simulation done (exit: $$?)"

endif

run-csr-unit: TEST=cs_registers_test
run-csr-unit: sim

run-csr-all:
	$(MAKE) sim TEST=cs_registers_test SEED=1
	$(MAKE) sim TEST=cs_registers_access_matrix_test SEED=2
	$(MAKE) sim TEST=cs_registers_illegal_test SEED=3
	$(MAKE) sim TEST=cs_registers_hazard_test SEED=4

# RC6: Signoff compliance target — 4 tests x 5 seeds = 20 simulations
compliance:
	@echo "=========================================================="
	@echo "EH2 CSR Unit Signoff Compliance: 4 tests x 5 seeds"
	@echo "=========================================================="
	SIGNOFF_OUT=$(SIGNOFF_OUT) python3 $(CSR_DIR)/scripts/run_compliance.py
	@echo "CSR Unit compliance complete."

clean:
	rm -rf $(OUT) simv* csrc vc_hdrs.h *.log *.vcd *.vpd ucli.key DVEfiles urgReport INCA_libs
	rm -f report.json
	@echo "CSR unit test artifacts cleaned"
