// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Registers Unit Test Environment Configuration (issue 56)
//
// Configuration object for the CSR registers UVM sub-environment.
// Placed into uvm_config_db by the testbench.

`include "uvm_macros.svh"
import uvm_pkg::*;

class cs_registers_env_cfg extends uvm_object;

  `uvm_object_utils(cs_registers_env_cfg)

  // Number of CSR test iterations per sequence
  int unsigned warl_iterations    = 20;
  int unsigned reset_iterations   = 1;
  int unsigned permission_iterations = 1;

  // Enable individual sequences
  bit enable_reset_seq      = 1;
  bit enable_warl_seq       = 1;
  bit enable_permission_seq = 1;

  // Test timeout in cycles
  int unsigned timeout_cycles = 1000000;

  // Verbosity
  int unsigned verbosity = UVM_MEDIUM;

  function new(string name = "cs_registers_env_cfg");
    super.new(name);
  endfunction

endclass
