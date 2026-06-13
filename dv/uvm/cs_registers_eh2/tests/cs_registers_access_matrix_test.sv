// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Access Matrix Test
// Runs csr_access_matrix_seq: CSRRW/RS/RC/RWI/RSI/RCI × 5 wdata per RW CSR.

class cs_registers_access_matrix_test extends uvm_test;

  `uvm_component_utils(cs_registers_access_matrix_test)

  cs_registers_env     env;
  cs_registers_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = cs_registers_env_cfg::type_id::create("cfg");
    uvm_config_db#(cs_registers_env_cfg)::set(this, "env*", "cfg", cfg);
    env = cs_registers_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    csr_access_matrix_seq am_seq;

    phase.raise_objection(this);
    @(posedge cs_registers_tb.clk);
    @(posedge cs_registers_tb.clk);

    `uvm_info("csr_am_test", "=== EH2 CSR Access Matrix Test ===", UVM_LOW)

    am_seq = csr_access_matrix_seq::type_id::create("am_seq");
    am_seq.reg_block  = env.reg_block;
    am_seq.scoreboard = env.scoreboard;
    am_seq.wdata_count = 5;
    am_seq.start(env.sequencer);

    `uvm_info("csr_am_test", "=== Access Matrix Test Complete ===", UVM_LOW)
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    int total_checks = env.scoreboard.num_checks;
    int total_errors = env.scoreboard.num_errors;
    if (total_errors == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED (%0d errors)", total_errors);
    end
    `uvm_info("csr_am_test", $sformatf(
      "CSR ACCESS MATRIX RESULT: %0d checks, %0d errors",
      total_checks, total_errors), UVM_LOW)
  endfunction

endclass
