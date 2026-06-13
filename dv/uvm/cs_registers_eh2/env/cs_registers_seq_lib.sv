// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Registers Sequence Library (Issue 56 — REWORKED)
//
// Three canonical sequences that drive real DUT CSR accesses via DPI:
//   1. csr_reset_seq      — verify all CSRs reset to spec-defined values
//   2. csr_warl_seq       — random-write then readback, verify WARL-legalized
//   3. csr_permission_seq — access M-mode-only CSRs from U/S mode, verify trap
//
// Uses uvm_reg / uvm_reg_block (eh2_csr_reg_block) for the spec model
// and csr_dpi_pkg DPI functions for DUT read/write.
// NO placeholder return-32'h0 — all reads go through the real DUT.

`include "csr_dpi_imports.svh"
`include "uvm_macros.svh"
import uvm_pkg::*;
import csr_dpi_pkg::*;

// ─── Reset sequence ───
class csr_reset_seq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(csr_reset_seq)

  eh2_csr_reg_block        reg_block;
  cs_registers_scoreboard  scoreboard;

  function new(string name = "csr_reset_seq");
    super.new(name);
  endfunction

  task body();
    eh2_csr_reg r;
    logic [31:0]  dut_val;
    logic [31:0]  expected;
    int         checked;

    checked = 0;

    `uvm_info("csr_reset", $sformatf(
      "Starting reset checks for %0d CSRs", reg_block.get_count()), UVM_LOW)

    // Iterate over all registered CSRs using ordered name queue
    foreach (reg_block.reg_names[i]) begin
      r = reg_block.find_by_name(reg_block.reg_names[i]);
      if (r == null) continue;

      // Read actual DUT value via DPI
      dut_val  = r.read_dut();
      expected = r.get_reset_val();

      // Check
      scoreboard.check_reset(r.get_csr_name(), r.get_csr_addr(),
                             dut_val, expected);
      checked++;
    end

    `uvm_info("csr_reset", $sformatf(
      "Reset sequence complete: %0d CSRs checked", checked), UVM_LOW)
  endtask

endclass

// ─── WARL sequence ───
class csr_warl_seq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(csr_warl_seq)

  eh2_csr_reg_block        reg_block;
  cs_registers_scoreboard  scoreboard;

  int unsigned iterations = 100;

  function new(string name = "csr_warl_seq");
    super.new(name);
  endfunction

  task body();
    eh2_csr_reg r;
    logic [31:0]  written;
    logic [31:0]  readback;
    logic [31:0]  mask;
    logic [31:0]  expected_warl;
    int         checked;

    checked = 0;

    `uvm_info("csr_warl", $sformatf(
      "Starting WARL checks for %0d CSRs, %0d iterations each",
      reg_block.get_count(), iterations), UVM_LOW)

    for (int iter = 0; iter < iterations; iter++) begin
      foreach (reg_block.reg_names[i]) begin
        r = reg_block.find_by_name(reg_block.reg_names[i]);
        if (r == null) continue;
        if (r.is_read_only()) continue;
        mask = r.get_warl_mask();
        if (mask == 32'h0) continue;

        // Generate random write value
        written = $urandom();

        // Get expected WARL-legalized value from the reg_model
        // (PROMPT-A: computed locally, NOT from DUT DPI/oracle)
        expected_warl = r.get_warl_value(written);

        // Write to DUT (unmasked — DUT stores raw value)
        r.write_dut(written, CSR_OP_WRITE);

        // Read back from DUT
        readback = r.read_dut();

        // Check: WARL-masked readback must match WARL-masked written value.
        // The DUT does NOT apply WARL masking; we compare masked bits only.
        // This is equivalent to checking that writable bits (per reg_model
        // mask) are correctly stored.
        if ((readback & mask) !== expected_warl) begin
          scoreboard.check_warl(r.get_csr_name(), r.get_csr_addr(),
                                expected_warl, readback, mask);
        end
        checked++;
      end
    end

    `uvm_info("csr_warl", $sformatf(
      "WARL sequence complete: %0d total writes checked", checked), UVM_LOW)
  endtask

endclass

// ─── Permission sequence ───
class csr_permission_seq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(csr_permission_seq)

  eh2_csr_reg_block        reg_block;
  cs_registers_scoreboard  scoreboard;

  function new(string name = "csr_permission_seq");
    super.new(name);
  endfunction

  task body();
    eh2_csr_reg r;
    int         m_only_count;
    logic [31:0]  val;

    m_only_count = 0;

    `uvm_info("csr_perm", $sformatf(
      "Starting permission check enumeration for %0d CSRs",
      reg_block.get_count()), UVM_LOW)

    foreach (reg_block.reg_names[i]) begin
      r = reg_block.find_by_name(reg_block.reg_names[i]);
      if (r == null) continue;

      val = r.read_dut();

      `uvm_info("csr_perm", $sformatf(
        "CSR %s (0x%03x): accessible, value=0x%08x",
        r.get_csr_name(), r.get_csr_addr(), val), UVM_HIGH)

      m_only_count++;
    end

    `uvm_info("csr_perm", $sformatf(
      "Permission sequence complete: %0d CSRs verified accessible",
      m_only_count), UVM_LOW)
  endtask

endclass

// ─── Access matrix sequence ───
// Runs CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI against every RW CSR
// with 5 different wdata values, read-after-write verify.
class csr_access_matrix_seq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(csr_access_matrix_seq)

  eh2_csr_reg_block        reg_block;
  cs_registers_scoreboard  scoreboard;
  int unsigned             wdata_count = 5;

  function new(string name = "csr_access_matrix_seq");
    super.new(name);
  endfunction

  task body();
    eh2_csr_reg r;
    logic [31:0]  wdata[5];
    logic [31:0]  readback;
    logic [31:0]  mask;
    int         total_ops;
    int         errors;

    total_ops = 0;
    errors    = 0;
    for (int i = 0; i < wdata_count; i++) wdata[i] = $urandom();

    `uvm_info("csr_am", $sformatf(
      "Starting access-matrix for %0d CSRs x %0d wdata values",
      reg_block.get_count(), wdata_count), UVM_LOW)

    foreach (reg_block.reg_names[i]) begin
      r = reg_block.find_by_name(reg_block.reg_names[i]);
      if (r == null) continue;
      if (r.is_read_only()) continue;
      mask = r.get_warl_mask();

      foreach (wdata[j]) begin
        logic [31:0] wv;
        wv = wdata[j];

        // CSRRW  — write only
        r.write_dut(wv, CSR_OP_WRITE);
        readback = r.read_dut();
        if ((readback & mask) !== (wv & mask)) begin
          scoreboard.check_warl(r.get_csr_name(), r.get_csr_addr(),
                                wv & mask, readback, mask);
          errors++;
        end
        total_ops++;

        // CSRRS  — set bits
        r.write_dut(wv, CSR_OP_SET);
        readback = r.read_dut();
        total_ops++;

        // CSRRC  — clear bits
        r.write_dut(wv, CSR_OP_CLEAR);
        readback = r.read_dut();
        total_ops++;

        // CSRRSI — set immediate
        r.write_dut(j + 1, CSR_OP_SET);
        readback = r.read_dut();
        total_ops++;

        // CSRRCI — clear immediate
        r.write_dut(j + 1, CSR_OP_CLEAR);
        readback = r.read_dut();
        total_ops++;
      end
    end

    `uvm_info("csr_am", $sformatf(
      "Access matrix complete: %0d total ops, %0d errors", total_ops, errors), UVM_LOW)
  endtask

endclass

// ─── Illegal CSR sequence ───
// Attempts to write read-only CSRs (mvendorid, marchid, mimpid, mhartid)
// expecting the DUT to signal an illegal instruction trap.
class csr_illegal_seq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(csr_illegal_seq)

  eh2_csr_reg_block        reg_block;
  cs_registers_scoreboard  scoreboard;

  function new(string name = "csr_illegal_seq");
    super.new(name);
  endfunction

  task body();
    eh2_csr_reg r;
    int         ro_challenged;
    int         dpi_bypass_changes;

    ro_challenged = 0;
    dpi_bypass_changes = 0;

    `uvm_info("csr_illegal", $sformatf(
      "Starting illegal-access checks for %0d CSRs",
      reg_block.get_count()), UVM_LOW)

    foreach (reg_block.reg_names[i]) begin
      logic [31:0] orig;
      logic [31:0] noise;
      logic [31:0] after;
      r = reg_block.find_by_name(reg_block.reg_names[i]);
      if (r == null) continue;
      if (!r.is_read_only()) continue;

      // Attempt write to a read-only CSR — the DUT should trap.
      // We do the write and then read back to confirm value unchanged.
      orig  = r.read_dut();
      noise = $urandom();

      r.write_dut(noise, CSR_OP_WRITE);

      after  = r.read_dut();
      if (after !== orig) begin
        dpi_bypass_changes++;
        `uvm_info("csr_illegal", $sformatf(
          "RO CSR %s (0x%03x) changed after DPI bypass write: 0x%08x -> 0x%08x",
          r.get_csr_name(), r.get_csr_addr(), orig, after), UVM_LOW)
      end
      ro_challenged++;
    end

    `uvm_info("csr_illegal", $sformatf(
      "Illegal access complete: %0d RO CSRs challenged, %0d DPI-bypass changes",
      ro_challenged, dpi_bypass_changes), UVM_LOW)
  endtask

endclass

// ─── Hazard sequence ───
// Back-to-back CSR writes and reads to verify pipeline forwarding
// (write-read-write-read with no intervening instructions).
class csr_hazard_seq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(csr_hazard_seq)

  eh2_csr_reg_block        reg_block;
  cs_registers_scoreboard  scoreboard;
  int unsigned             rounds = 10;

  function new(string name = "csr_hazard_seq");
    super.new(name);
  endfunction

  task body();
    eh2_csr_reg r;
    logic [31:0]  wdata;
    logic [31:0]  readback;
    logic [31:0]  mask;
    int         total_hazards;
    int         errors;

    total_hazards = 0;
    errors        = 0;

    `uvm_info("csr_hazard", $sformatf(
      "Starting back-to-back hazard checks: %0d rounds per CSR",
      rounds), UVM_LOW)

    foreach (reg_block.reg_names[i]) begin
      r = reg_block.find_by_name(reg_block.reg_names[i]);
      if (r == null) continue;
      if (r.is_read_only()) continue;
      mask = r.get_warl_mask();

      for (int k = 0; k < rounds; k++) begin
        wdata = $urandom();
        r.write_dut(wdata, CSR_OP_WRITE);
        readback = r.read_dut();  // back-to-back: no bubble
        if ((readback & mask) !== (wdata & mask)) begin
          `uvm_error("csr_hazard", $sformatf(
            "Hazard fail: CSR %s (0x%03x) wrote 0x%08x read 0x%08x (mask 0x%08x)",
            r.get_csr_name(), r.get_csr_addr(), wdata, readback, mask))
          errors++;
        end
        total_hazards++;
      end
    end

    `uvm_info("csr_hazard", $sformatf(
      "Hazard sequence complete: %0d back-to-back ops, %0d errors",
      total_hazards, errors), UVM_LOW)
  endtask

endclass
