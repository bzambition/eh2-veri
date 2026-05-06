// SPDX-License-Identifier: Apache-2.0
// EH2 Sequence Library
//
// Reusable stimulus sequences for interrupt, debug, and memory response.
// Modeled after Ibex core_ibex_seq_lib.sv.
//
// Sequences:
//   core_eh2_base_seq        - Base class with interval/delay randomization
//   irq_raise_seq            - Raise multiple external interrupts
//   irq_raise_single_seq     - Raise a single interrupt
//   irq_raise_nmi_seq        - Raise NMI
//   irq_drop_seq             - Deassert all interrupts
//   debug_seq                - Debug halt/resume (stress or single)
//   fetch_enable_seq         - Toggle fetch-enable randomly

`include "uvm_macros.svh"
import uvm_pkg::*;
import eh2_irq_agent_pkg::*;
import eh2_jtag_agent_pkg::*;

// ---------------------------------------------------------------------------
// Base sequence with configurable interval and stop mechanism
// ---------------------------------------------------------------------------
class core_eh2_base_seq extends uvm_sequence;

  `uvm_object_utils(core_eh2_base_seq)

  int unsigned interval = 500;    // Max cycles between events
  int unsigned delay_min = 100;   // Min initial delay (ns)
  int unsigned delay_max = 5000;  // Max initial delay (ns)
  bit            stopped = 0;     // Stop flag

  function new(string name = "core_eh2_base_seq");
    super.new(name);
  endfunction

  // Randomized initial delay
  task rand_delay();
    int d;
    d = $urandom_range(delay_min, delay_max);
    #(d * 1ns);
  endtask

  // Randomized interval between events
  task rand_interval();
    int d;
    d = $urandom_range(1, interval);
    #(d * 10ns);
  endtask

  // Stop the sequence
  virtual task stop();
    stopped = 1;
  endtask

  // Wait for stop (non-blocking check)
  virtual task wait_for_stop();
    wait (stopped);
  endtask

endclass

// ---------------------------------------------------------------------------
// IRQ Raise Sequence - Raises multiple external interrupts
// ---------------------------------------------------------------------------
class irq_raise_seq extends core_eh2_base_seq;

  `uvm_object_utils(irq_raise_seq)

  // Virtual interface to drive interrupts
  virtual eh2_irq_intf irq_vif;

  int unsigned max_irq_id = 127;  // Max external interrupt ID
  int unsigned num_irqs = 3;      // Number of interrupts to raise per event

  function new(string name = "irq_raise_seq");
    super.new(name);
  endfunction

  virtual task body();
    int id;
    rand_delay();
    forever begin
      if (stopped) return;
      // Raise multiple random interrupts
      repeat (num_irqs) begin
        id = $urandom_range(1, max_irq_id);
        irq_vif.extintsrc_req[id] <= 1'b1;
      end
      rand_interval();
      // Drop all
      irq_vif.extintsrc_req <= '0;
      rand_interval();
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// IRQ Raise Single Sequence - Raises one interrupt at a time
// ---------------------------------------------------------------------------
class irq_raise_single_seq extends core_eh2_base_seq;

  `uvm_object_utils(irq_raise_single_seq)

  virtual eh2_irq_intf irq_vif;

  int unsigned max_irq_id = 127;

  function new(string name = "irq_raise_single_seq");
    super.new(name);
  endfunction

  virtual task body();
    int id;
    rand_delay();
    forever begin
      if (stopped) return;
      id = $urandom_range(1, max_irq_id);
      irq_vif.extintsrc_req[id] <= 1'b1;
      rand_interval();
      irq_vif.extintsrc_req[id] <= 1'b0;
      rand_interval();
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// IRQ NMI Sequence - Raises non-maskable interrupt
// ---------------------------------------------------------------------------
class irq_raise_nmi_seq extends core_eh2_base_seq;

  `uvm_object_utils(irq_raise_nmi_seq)

  virtual eh2_irq_intf irq_vif;

  function new(string name = "irq_raise_nmi_seq");
    super.new(name);
  endfunction

  virtual task body();
    rand_delay();
    forever begin
      if (stopped) return;
      irq_vif.nmi_int <= 1'b1;
      rand_interval();
      irq_vif.nmi_int <= 1'b0;
      rand_interval();
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// IRQ Drop Sequence - Deasserts all interrupts
// ---------------------------------------------------------------------------
class irq_drop_seq extends core_eh2_base_seq;

  `uvm_object_utils(irq_drop_seq)

  virtual eh2_irq_intf irq_vif;

  function new(string name = "irq_drop_seq");
    super.new(name);
  endfunction

  virtual task body();
    rand_delay();
    forever begin
      if (stopped) return;
      // Drop all interrupts
      irq_vif.extintsrc_req <= '0;
      irq_vif.timer_int <= '0;
      irq_vif.soft_int <= '0;
      irq_vif.nmi_int <= 1'b0;
      rand_interval();
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// Debug Sequence - Drives debug halt/resume via JTAG
// ---------------------------------------------------------------------------
class debug_seq extends core_eh2_base_seq;

  `uvm_object_utils(debug_seq)

  // Sequencer to send JTAG transactions
  uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr;

  bit stress_mode = 0;  // 1 = continuous, 0 = single

  function new(string name = "debug_seq");
    super.new(name);
  endfunction

  virtual task body();
    rand_delay();
    if (stress_mode) begin
      // Continuous debug halt/resume
      forever begin
        if (stopped) return;
        send_halt();
        rand_interval();
        send_resume();
        rand_interval();
      end
    end else begin
      // Single debug halt/resume
      send_halt();
      rand_interval();
      send_resume();
    end
  endtask

  virtual task send_halt();
    eh2_jtag_seq::send_write(jtag_seqr,
      eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);
  endtask

  virtual task send_resume();
    eh2_jtag_seq::send_write(jtag_seqr,
      eh2_jtag_seq_item::DMI_DMCONTROL, 32'h40000000);
  endtask

endclass

// ---------------------------------------------------------------------------
// Fetch Enable Sequence - Randomly toggles fetch-enable
// ---------------------------------------------------------------------------
class fetch_enable_seq extends core_eh2_base_seq;

  `uvm_object_utils(fetch_enable_seq)

  virtual interface fetch_enable_intf fetch_vif;

  function new(string name = "fetch_enable_seq");
    super.new(name);
  endfunction

  virtual task body();
    rand_delay();
    forever begin
      if (stopped) return;
      // Disable fetch
      if (fetch_vif != null)
        fetch_vif.fetch_enable <= 1'b0;
      rand_interval();
      // Re-enable fetch
      if (fetch_vif != null)
        fetch_vif.fetch_enable <= 1'b1;
      rand_interval();
    end
  endtask

endclass
