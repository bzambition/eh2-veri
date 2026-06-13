// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Registers Base Test (Issue 56 — REWORKED)
//
// Runs the three canonical CSR sequences using the uvm_reg_block model
// and real DPI-based DUT access.  Produces a report.json for sign-off.
//
// Modeled after lowRISC Ibex dv/cs_registers/tests/ .

class cs_registers_test extends uvm_test;

  `uvm_component_utils(cs_registers_test)

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
    csr_reset_seq      reset_seq;
    csr_warl_seq       warl_seq;
    csr_permission_seq perm_seq;

    phase.raise_objection(this);

    // Wait for DUT reset to complete before accessing registers
    @(posedge cs_registers_tb.clk);
    @(posedge cs_registers_tb.clk);

    `uvm_info("csr_test", "=== EH2 CSR Registers Unit Test ===", UVM_LOW)
    env.reg_block.dump();

    // Phase 1: Reset value checks
    if (cfg.enable_reset_seq) begin
      reset_seq = csr_reset_seq::type_id::create("reset_seq");
      reset_seq.reg_block  = env.reg_block;
      reset_seq.scoreboard = env.scoreboard;
      `uvm_info("csr_test", "Running reset sequence...", UVM_LOW)
      reset_seq.start(env.sequencer);
    end

    // Phase 2: WARL behavior checks
    if (cfg.enable_warl_seq) begin
      warl_seq = csr_warl_seq::type_id::create("warl_seq");
      warl_seq.reg_block  = env.reg_block;
      warl_seq.scoreboard = env.scoreboard;
      warl_seq.iterations = cfg.warl_iterations;
      `uvm_info("csr_test", "Running WARL sequence...", UVM_LOW)
      warl_seq.start(env.sequencer);
    end

    // Phase 3: Access permission checks
    if (cfg.enable_permission_seq) begin
      perm_seq = csr_permission_seq::type_id::create("perm_seq");
      perm_seq.reg_block  = env.reg_block;
      perm_seq.scoreboard = env.scoreboard;
      `uvm_info("csr_test", "Running permission sequence...", UVM_LOW)
      perm_seq.start(env.sequencer);
    end

    `uvm_info("csr_test", "=== CSR Unit Test Complete ===", UVM_LOW)
    phase.drop_objection(this);
  endtask

  // Produce report.json for sign-off integration
  function void report_phase(uvm_phase phase);
    int fd;
    int total_checks;
    int total_errors;
    int num_passed;
    int num_failed;

    total_checks = env.scoreboard.num_checks;
    total_errors = env.scoreboard.num_errors;
    num_passed   = total_checks - total_errors;
    num_failed   = total_errors;

    // Write report.json for signoff.py consumption
    fd = $fopen("report.json", "w");
    if (fd) begin
      $fwrite(fd, "{\n");
      $fwrite(fd, "  \"total_time_sec\": 0.0,\n");
      $fwrite(fd, "  \"tests\": [\n");
      $fwrite(fd, "    {\"name\": \"csr_reset_seq\",    \"seed\": 1, \"type\": \"csr_unit\", \"passed\": %s, \"sim_log\": \"csr_unit_test.log\"},\n",
              (total_errors == 0) ? "true" : "false");
      $fwrite(fd, "    {\"name\": \"csr_warl_seq\",     \"seed\": 1, \"type\": \"csr_unit\", \"passed\": %s, \"sim_log\": \"csr_unit_test.log\"},\n",
              (total_errors == 0) ? "true" : "false");
      $fwrite(fd, "    {\"name\": \"csr_permission_seq\",\"seed\": 1, \"type\": \"csr_unit\", \"passed\": %s, \"sim_log\": \"csr_unit_test.log\"}\n",
              (total_errors == 0) ? "true" : "false");
      $fwrite(fd, "  ]\n");
      $fwrite(fd, "}\n");
      $fclose(fd);
      `uvm_info("csr_test", "Wrote report.json for sign-off", UVM_LOW)
    end

    if (total_errors == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED (%0d errors)", total_errors);
    end
    `uvm_info("csr_test", $sformatf(
      "CSR UNIT RESULT: %0d checks, %0d passed, %0d failed, %0d errors",
      total_checks, num_passed, num_failed, total_errors), UVM_LOW)
  endfunction

endclass
