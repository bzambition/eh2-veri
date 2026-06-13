// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Registers UVM Environment (Issue 56 — REWORKED)
//
// Wraps the uvm_reg_block, scoreboard, and sequencer.
// Sequences drive CSR DUT access via csr_dpi_pkg DPI calls.

`include "csr_dpi_imports.svh"
`include "uvm_macros.svh"

class cs_registers_env extends uvm_env;

  `uvm_component_utils(cs_registers_env)

  cs_registers_env_cfg     cfg;
  cs_registers_scoreboard  scoreboard;
  eh2_csr_reg_block        reg_block;

  uvm_sequencer #(uvm_sequence_item) sequencer;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    void'(uvm_config_db#(cs_registers_env_cfg)::get(this, "", "cfg", cfg));
    if (cfg == null) begin
      cfg = cs_registers_env_cfg::type_id::create("cfg");
      `uvm_info("csr_env", "Using default cfg", UVM_LOW)
    end

    sequencer = uvm_sequencer#(uvm_sequence_item)::type_id::create("sequencer", this);
    scoreboard = cs_registers_scoreboard::type_id::create("scoreboard", this);
    reg_block  = eh2_csr_reg_block::type_id::create("reg_block", this);
    reg_block.build();
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
  endfunction

endclass
