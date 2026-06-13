// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Hazard Test
// Runs csr_hazard_seq: back-to-back write-read pairs, 10 rounds per RW CSR.

class cs_registers_hazard_test extends uvm_test;

  `uvm_component_utils(cs_registers_hazard_test)

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
    csr_hazard_seq hz_seq;

    phase.raise_objection(this);
    @(posedge cs_registers_tb.clk);
    @(posedge cs_registers_tb.clk);

    `uvm_info("csr_hz_test", "=== EH2 CSR Hazard Test ===", UVM_LOW)

    hz_seq = csr_hazard_seq::type_id::create("hz_seq");
    hz_seq.reg_block  = env.reg_block;
    hz_seq.scoreboard = env.scoreboard;
    hz_seq.rounds = 10;
    hz_seq.start(env.sequencer);

    `uvm_info("csr_hz_test", "=== Hazard Test Complete ===", UVM_LOW)
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
    `uvm_info("csr_hz_test", $sformatf(
      "CSR HAZARD RESULT: %0d checks, %0d errors",
      total_checks, total_errors), UVM_LOW)
  endfunction

endclass
