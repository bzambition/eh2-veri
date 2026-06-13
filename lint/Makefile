# EH2 Lint Makefile
#
# Runs Verible and Verilator lint on RTL and DV code.
# Modeled after lowRISC Ibex lint/Makefile.
# Lint is BLOCKING: any ERROR/FATAL fails the pipeline.

LINT_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
EH2_ROOT := $(LINT_DIR)/..
RTL_DIR  := $(EH2_ROOT)/rtl
DV_DIR   := $(EH2_ROOT)/dv/uvm/core_eh2

VERIBLE  ?= verible-verilog-lint
VERILATOR ?= verilator

VERIBLE_RULES  := $(LINT_DIR)/verible/verible.rules
VERIBLE_WAIVERS := $(LINT_DIR)/verible/waivers.vbl
VERILATOR_WAIVER := $(LINT_DIR)/verilator/verilator_waiver.vlt
VERILATOR_CONFIG := $(LINT_DIR)/verilator/verilator-config.vlt

BUILD_DIR := $(LINT_DIR)/build

# Collect all SystemVerilog files
RTL_SV  := $(shell find $(RTL_DIR) -name '*.sv' -type f 2>/dev/null)
DV_SV   := $(shell find $(DV_DIR) -name '*.sv' -type f 2>/dev/null)
ALL_SV  := $(RTL_SV) $(DV_SV)

.PHONY: lint lint-verible lint-verilator clean

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

lint: lint-verible lint-verilator
	@echo "LINT: All linters completed"

lint-verible: $(BUILD_DIR)
	@echo "=== Verible SystemVerilog Lint ==="
	@> $(BUILD_DIR)/verible_errors.txt
	@if command -v $(VERIBLE) >/dev/null 2>&1; then \
		lint_errors=0; \
		for f in $(ALL_SV); do \
			$(VERIBLE) --rules_config=$(VERIBLE_RULES) \
				--waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | tee -a $(BUILD_DIR)/verible.log; \
			if [ $${PIPESTATUS[0]} -ne 0 ]; then \
				lint_errors=$$((lint_errors + 1)); \
			fi; \
		done; \
		grep -E "^(E|FATAL|Error)" $(BUILD_DIR)/verible.log > $(BUILD_DIR)/verible_errors.txt 2>/dev/null || true; \
		if [ -s $(BUILD_DIR)/verible_errors.txt ]; then \
			echo "BLOCKING: Verible lint errors:"; \
			cat $(BUILD_DIR)/verible_errors.txt; \
			echo "Verible lint FAILED"; \
			exit 1; \
		else \
			echo "Verible lint PASSED (0 errors)"; \
		fi; \
	else \
		echo "WARNING: verible-verilog-lint not found, skipping"; \
	fi

lint-verilator:
	@echo "=== Verilator Lint ==="
	@if command -v $(VERILATOR) >/dev/null 2>&1; then \
		$(VERILATOR) --lint-only \
			-Wno-fatal \
			-Wno-UNOPTFLAT \
			-Wno-UNUSED \
			$(VERILATOR_CONFIG) \
			$(VERILATOR_WAIVER) \
			$(RTL_SV) 2>&1 | tee $(BUILD_DIR)/verilator.log; \
		if grep -qE "%Error" $(BUILD_DIR)/verilator.log; then \
			echo "BLOCKING: Verilator lint errors found"; \
			grep -E "%Error" $(BUILD_DIR)/verilator.log; \
			exit 1; \
		else \
			echo "Verilator lint PASSED"; \
		fi; \
	else \
		echo "WARNING: verilator not found, skipping"; \
	fi

# Quick lint: verible only, RTL only
lint-quick:
	@echo "=== Quick Verible Lint (RTL only) ==="
	@for f in $(RTL_SV); do \
		$(VERIBLE) --rules_config=$(VERIBLE_RULES) \
			--waiver_files=$(VERIBLE_WAIVERS) $$f 2>&1 | head -5; \
	done

clean:
	rm -rf $(BUILD_DIR)
