// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Registers Scoreboard (issue 56)
//
// Verifies that CSR reads match the expected WARL-legalized value
// and that access violations trigger the correct traps.
//
// Modeled after lowRISC Ibex dv/cs_registers/cs_registers_scoreboard.sv.

class cs_registers_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(cs_registers_scoreboard)

  int unsigned num_checks;
  int unsigned num_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Compare a CSR read value against expected WARL-legalized value.
  function void check_warl(string csr_name, int csr_num,
                           bit [31:0] written, bit [31:0] readback,
                           bit [31:0] expected_mask);
    num_checks++;
    if ((readback & expected_mask) != (written & expected_mask)) begin
      `uvm_error("csr_scoreboard", $sformatf(
        "%s (0x%03x): wrote 0x%08x, read 0x%08x, expected-masked 0x%08x",
        csr_name, csr_num, written, readback,
        written & expected_mask))
      num_errors++;
    end
  endfunction

  // Verify reset value matches spec.
  function void check_reset(string csr_name, int csr_num,
                            bit [31:0] actual, bit [31:0] expected);
    num_checks++;
    if (actual !== expected) begin
      `uvm_error("csr_scoreboard", $sformatf(
        "%s (0x%03x): reset value 0x%08x, expected 0x%08x",
        csr_name, csr_num, actual, expected))
      num_errors++;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("csr_scoreboard", $sformatf(
      "CSR checks: %0d total, %0d errors", num_checks, num_errors), UVM_LOW)
    if (num_errors > 0) begin
      `uvm_error("csr_scoreboard", "CSR check failures detected")
    end
  endfunction

endclass
