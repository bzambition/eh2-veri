// SPDX-License-Identifier: Apache-2.0
// EH2 Co-simulation Configuration
//
// Configuration object for the Spike co-simulation model.
// Placed into uvm_config_db by the testbench; read by the
// cosim scoreboard during build_phase.
//
// Based on ibex's core_ibex_cosim_cfg pattern, adapted for EH2.

class eh2_cosim_cfg extends uvm_object;

  `uvm_object_utils(eh2_cosim_cfg)

  // RISC-V ISA string passed to Spike (e.g. "rv32imac_zba_zbb_zbc_zbs")
  string isa_string = "rv32imac_zba_zbb_zbc_zbs";

  // Initial program counter for the cosim
  bit [31:0] start_pc = 32'h8000_0000;

  // Initial machine trap-vector base address
  bit [31:0] start_mtvec = 32'h0;

  // Number of PMP regions
  bit [31:0] pmp_num_regions = 16;

  // PMP granularity (log2 of minimum region size)
  bit [31:0] pmp_granularity = 0;

  // Number of MHPM performance counters
  bit [31:0] mhpm_counter_num = 0;

  // When set, mismatches are logged as UVM_LOW instead of UVM_FATAL
  bit relax_cosim_check = 0;

  // Path to Spike log output (empty = no log)
  string log_file = "";

  // Debug module address range
  bit [31:0] dm_start_addr = 32'h0000_0000;
  bit [31:0] dm_end_addr   = 32'h0000_0FFF;

  function new(string name = "eh2_cosim_cfg");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf(
      "eh2_cosim_cfg: isa=%s start_pc=%08x mtvec=%08x pmp=%0d relax=%0b",
      isa_string, start_pc, start_mtvec, pmp_num_regions, relax_cosim_check);
  endfunction

endclass
