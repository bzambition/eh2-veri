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

.PHONY: ifv formal ifv_clean formal_clean ifv_count formal_count ifv_cex

ifv:
	@mkdir -p $(BUILD_DIR)
	$(IFV) -f $(FILELIST) $(IFV_COMPILE_OPTS) -c -l $(BUILD_DIR)/ifv_elab.log
	$(IFV) -r +tcl+$(SCRIPTS)/ifv_prove.tcl -l $(BUILD_DIR)/ifv_run.log
	@grep -A 6 "Assertion Summary" $(BUILD_DIR)/ifv_run.log > $(BUILD_DIR)/ifv_summary.txt || true
	@cat $(BUILD_DIR)/ifv_summary.txt

formal: ifv

ifv_cex:
	@mkdir -p $(BUILD_DIR)
	$(IFV) -r +tcl+$(SCRIPTS)/ifv_cex_dump.tcl -l $(BUILD_DIR)/ifv_cex_run.log
	@ls $(BUILD_DIR)/cex_*.txt 2>/dev/null | wc -l

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
	@rm -f $(BUILD_DIR)/ifv_*.log $(BUILD_DIR)/ifv_*.tcl $(BUILD_DIR)/ifv_*.input
	@rm -f $(BUILD_DIR)/ifv_summary.txt $(BUILD_DIR)/cex_*.txt
	@rm -rf $(BUILD_DIR)/ifv_work .ifv
	@echo "=== Clean complete ==="

formal_clean: ifv_clean
