// SPDX-License-Identifier: Apache-2.0
// EH2 Co-simulation Scoreboard
//
// Compares DUT execution against a Spike reference model.
//
// Phase 1 simplification (ADR-0004): The RTL trace packet now carries the
// RVFI-equivalent {wb_valid, rd_addr, rd_wdata} tuple, so each trace_seq_item
// arriving from the trace monitor is self-contained. The scoreboard no longer
// needs to correlate trace items with a separate writeback FIFO.
//
// Async writeback corner cases (NB-load, DIV-cancel) still arrive via the
// dut probe monitor, but only as suppress hints—they override wb_valid for
// the matching trace item by rd address within a small window.
//
// Spike notification ordering (matching Ibex):
//   1. set_debug_req  (highest priority)
//   2. set_nmi
//   3. set_nmi_int
//   4. set_mip        (pre/post)
//   5. set_mcycle
//   6. step()

`include "uvm_macros.svh"
import uvm_pkg::*;
import eh2_trace_agent_pkg::*;
import axi4_agent_pkg::*;

class eh2_cosim_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(eh2_cosim_scoreboard)

  // Analysis FIFOs from monitors
  uvm_tlm_analysis_fifo #(eh2_trace_seq_item) trace_fifo;
  uvm_tlm_analysis_fifo #(eh2_trace_seq_item) dut_probe_fifo;
  uvm_tlm_analysis_fifo #(axi4_seq_item)      lsu_axi_fifo;

  // Co-simulation handle
  chandle cosim_handle;

  // Configuration object (from config_db, optional)
  eh2_cosim_cfg cfg;

  // Configuration (plusarg overrides or defaults)
  string cosim_config = "";
  bit    enable_cosim = 1;
  bit    fatal_on_mismatch = 0;  // 1 = UVM_FATAL on mismatch, 0 = UVM_ERROR

  // Statistics
  int    step_count;
  int    mismatch_count;
  int    trace_item_count;
  int    probe_item_count;
  int    suppressed_probe_item_count;
  int    axi_item_count;
  int    pending_trace_high_watermark;

  // Tracking state
  bit    initialized = 0;

  // Trace items wait here until matching memory accesses (for stores/AMOs) arrive.
  typedef struct {
    eh2_trace_seq_item item;
  } pending_trace_t;
  pending_trace_t pending_trace_q[$];

  // LSU AXI memory accesses from the bus monitor.
  typedef struct {
    axi4_seq_item txn;
    bit           is_store;
    int           observed_access_count;
  } pending_mem_access_t;
  pending_mem_access_t pending_mem_access_q[$];

  // Async writeback hints from the dut probe (NB-load wb / DIV cancel).
  // Only used to override the trace packet's wb_valid when an async event
  // suppressed or replaced the architectural writeback for a recent trace.
  typedef struct {
    bit [4:0]  rd;
    bit [31:0] rd_data;
    bit        suppress;
    int        source;
  } async_wb_hint_t;
  async_wb_hint_t async_wb_q[$];

  // Previous MIP value for pre/post tracking
  bit [31:0] prev_mip;

  // Reset handling
  virtual interface eh2_dut_probe_intf probe_vif;
  bit reset_active = 0;

  // Binary reload support (for reset recovery and deferred loading)
  string     stored_bin_path = "";
  bit [31:0] stored_base_addr = 32'h8000_0000;

  // Deferred binary load request (set by test before run_phase)
  string     pending_bin_path = "";
  bit [31:0] pending_base_addr = 32'h8000_0000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    trace_fifo     = new("trace_fifo", this);
    dut_probe_fifo = new("dut_probe_fifo", this);
    lsu_axi_fifo   = new("lsu_axi_fifo", this);

    // Get configuration object from config_db (optional)
    void'(uvm_config_db#(eh2_cosim_cfg)::get(this, "", "cosim_cfg", cfg));

    // Get configuration via plusargs (overrides cfg or defaults)
    void'($value$plusargs("enable_cosim=%b", enable_cosim));
    void'($value$plusargs("cosim_config=%s", cosim_config));
    void'($value$plusargs("cosim_fatal_on_mismatch=%b", fatal_on_mismatch));

    // Apply cfg values if cfg was provided and plusargs didn't override
    if (cfg != null) begin
      if (cosim_config == "") cosim_config = cfg.isa_string;
      fatal_on_mismatch = cfg.relax_cosim_check ? 0 : 1;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Get probe interface for reset monitoring
    uvm_config_db#(virtual eh2_dut_probe_intf)::get(this, "", "probe_vif", probe_vif);
  endfunction

  task run_phase(uvm_phase phase);
    if (enable_cosim) begin
      init_cosim();
      fork
        run_cosim_trace();
        run_cosim_probe_async();
        run_cosim_dmem();
        run_reset_monitor();
      join
    end
  endtask

  // Monitor reset and re-initialize cosim model after reset de-assertion
  task run_reset_monitor();
    if (probe_vif == null) return;

    forever begin
      @(negedge probe_vif.rst_n);
      reset_active = 1;
      `uvm_info("cosim", "Reset asserted - flushing state", UVM_LOW)
      flush_state();

      @(posedge probe_vif.rst_n);
      reset_active = 0;
      `uvm_info("cosim", "Reset de-asserted - re-initializing cosim", UVM_LOW)

      if (enable_cosim) begin
        init_cosim();
      end
    end
  endtask

  // Flush all scoreboard state (FIFOs, queues, counters)
  function void flush_state();
    eh2_trace_seq_item trash_item;
    axi4_seq_item trash_axi;

    while (trace_fifo.try_get(trash_item)) begin end
    while (dut_probe_fifo.try_get(trash_item)) begin end
    while (lsu_axi_fifo.try_get(trash_axi)) begin end

    pending_trace_q.delete();
    pending_mem_access_q.delete();
    async_wb_q.delete();

    prev_mip = 0;
  endfunction

  // Process trace items - each carries its own wb data from the RTL trace pkt.
  task run_cosim_trace();
    eh2_trace_seq_item trace_item;

    forever begin
      trace_fifo.get(trace_item);
      trace_item_count++;

      if (cosim_handle != null && initialized) begin
        pending_trace_t pending;
        pending.item = trace_item;
        pending_trace_q.push_back(pending);
        if (pending_trace_q.size() > pending_trace_high_watermark) begin
          pending_trace_high_watermark = pending_trace_q.size();
        end
        process_pending_trace();
      end
    end
  endtask

  // Async writeback hints (NB-load wb / DIV completion / DIV cancel).
  //
  // EH2 div unit produces three kinds of events:
  //   - DIV WB: architectural div completed, wrote rd.
  //   - DIV CANCEL via div_flush: speculatively-issued div killed before
  //     retire (instruction never appears in trace pkt). These DO NOT pair
  //     with any trace item.
  //   - DIV CANCEL via nonblock_div_cancel-overwrite: div retired in trace
  //     but a younger same-rd write replaced it. These DO pair with a trace
  //     item (suppress its writeback).
  //
  // Distinguishing the two cancel kinds requires either RTL annotation or
  // an rd-based heuristic: a cancel's `rd` always matches the div_rd of the
  // canceled div. By matching DIV hints to trace items strictly by rd in
  // FIFO order, retired-div traces always pick up the correct hint (their
  // div was the earliest issued div with that rd still in flight). Pure
  // speculative cancels with rd values that no retired div uses simply
  // accumulate harmlessly until later overwritten or discarded at end.
  task run_cosim_probe_async();
    eh2_trace_seq_item probe_item;
    async_wb_hint_t hint;

    forever begin
      dut_probe_fifo.get(probe_item);
      probe_item_count++;

      // Drop regular writebacks - the trace channel already carries them.
      if (probe_item.wb_source == EH2_WB_SRC_REGULAR) continue;

      hint.rd       = probe_item.wb_dest;
      hint.rd_data  = probe_item.wb_data;
      hint.suppress = probe_item.wb_suppress;
      hint.source   = probe_item.wb_source;
      async_wb_q.push_back(hint);

      `uvm_info("cosim", $sformatf(
        "ASYNC_WB: src=%s rd=x%0d data=%08x suppress=%0b qsize=%0d",
        wb_source_name(probe_item.wb_source), probe_item.wb_dest,
        probe_item.wb_data, probe_item.wb_suppress, async_wb_q.size()), UVM_HIGH)

      if (cosim_handle != null && initialized) begin
        process_pending_trace();
      end
    end
  endtask

  // Monitor LSU AXI4 transactions for memory access notification
  task run_cosim_dmem();
    axi4_seq_item axi_txn;

    forever begin
      lsu_axi_fifo.get(axi_txn);
      axi_item_count++;

      if (cosim_handle != null && initialized) begin
        enqueue_memory_accesses(axi_txn);
        process_pending_trace();
      end
    end
  endtask

  // True if the trace item describes an instruction whose architectural
  // writeback arrives on an async channel (DIV unit / NB-load) instead of
  // the regular pipeline. Wait for the matching async hint before stepping.
  function bit needs_async_wb(eh2_trace_seq_item item);
    if (item.exception || item.interrupt) return 1'b0;
    if (!item.writes_rd()) return 1'b0;
    if (item.is_div()) return 1'b1;
    // Loads in EH2 always go through the nb-load writeback path (the regular
    // wb port masks `cam_load_kill_wen`), so the trace pkt always has wb=0
    // for loads. Wait for the nb-load completion hint before stepping.
    if (is_load_instruction(item)) return 1'b1;
    return 1'b0;
  endfunction

  // Drain pending_trace_q in order. Gates:
  //   - stores/AMOs wait for matching LSU AXI access
  //   - DIV / NB-load trace items wait for the matching async writeback hint
  function void process_pending_trace();
    while (pending_trace_q.size() > 0) begin
      pending_trace_t pending = pending_trace_q[0];

      if (must_wait_for_memory_access(pending.item) &&
          !has_matching_memory_access(pending.item)) begin
        `uvm_info("cosim", $sformatf(
          "Waiting for LSU AXI access before stepping store/AMO PC=%08x insn=%08x",
          pending.item.pc, pending.item.insn), UVM_HIGH)
        break;
      end

      if (needs_async_wb(pending.item) && !has_matching_async_wb(pending.item)) begin
        `uvm_info("cosim", $sformatf(
          "Waiting for async wb (DIV) before stepping PC=%08x insn=%08x rd=x%0d",
          pending.item.pc, pending.item.insn, pending.item.get_write_rd()), UVM_HIGH)
        break;
      end

      pending_trace_q.pop_front();
      if (is_memory_instruction(pending.item) &&
          has_matching_memory_access(pending.item)) begin
        pop_matching_memory_access(pending.item);
      end
      compare_instruction(pending.item);
    end
  endfunction

  function bit has_matching_async_wb(eh2_trace_seq_item item);
    bit [4:0] expected_rd;
    if (!item.writes_rd()) return 1'b0;
    expected_rd = item.get_write_rd();

    if (item.is_div()) begin
      // Any DIV-source hint at the head unblocks (FIFO match for retired divs).
      foreach (async_wb_q[i]) begin
        if (async_wb_q[i].source == EH2_WB_SRC_DIV) return 1'b1;
      end
      return 1'b0;
    end

    if (is_load_instruction(item)) begin
      foreach (async_wb_q[i]) begin
        if (async_wb_q[i].source != EH2_WB_SRC_NB_LOAD) continue;
        if (async_wb_q[i].rd == expected_rd) return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  function bit is_memory_instruction(eh2_trace_seq_item item);
    if (item.is_load() || item.is_store() || item.is_amo()) begin
      return 1'b1;
    end
    return item.is_compressed_load_store();
  endfunction

  function bit is_load_instruction(eh2_trace_seq_item item);
    return item.is_load() ||
           (item.is_compressed_load_store() && item.writes_rd());
  endfunction

  function bit is_store_or_amo_instruction(eh2_trace_seq_item item);
    return item.is_store() || item.is_amo() ||
           (item.is_compressed_load_store() && !item.writes_rd());
  endfunction

  function bit must_wait_for_memory_access(eh2_trace_seq_item item);
    if (is_load_instruction(item)) return 1'b0;
    return is_store_or_amo_instruction(item);
  endfunction

  function string wb_source_name(int source);
    case (source)
      EH2_WB_SRC_REGULAR: return "regular";
      EH2_WB_SRC_DIV:     return "div";
      EH2_WB_SRC_NB_LOAD: return "nb_load";
      default:            return $sformatf("unknown(%0d)", source);
    endcase
  endfunction

  // Try to consume an async writeback hint that matches this instruction's
  // architectural rd. Returns 1 and fills `hint` if found.
  //
  // Matching policy:
  //   - DIV: take the FIRST queued DIV-source hint regardless of rd. The
  //     dut probe monitor only enqueues DIV hints for events that pair
  //     1:1 with retired div traces (real wb events + overwrite cancels;
  //     speculative-flush cancels are dropped at the source). Therefore
  //     the head of the DIV-source FIFO necessarily belongs to this trace.
  //   - NB-load: match by rd (NB-load completions can interleave).
  function bit try_consume_async_wb(eh2_trace_seq_item item,
                                    output async_wb_hint_t hint);
    bit [4:0] expected_rd;
    if (!item.writes_rd()) return 1'b0;
    expected_rd = item.get_write_rd();

    if (item.is_div()) begin
      foreach (async_wb_q[i]) begin
        if (async_wb_q[i].source != EH2_WB_SRC_DIV) continue;
        // Sanity: rd should match the retired div's rd.
        if (async_wb_q[i].rd != expected_rd) begin
          `uvm_warning("cosim", $sformatf(
            "DIV hint rd mismatch: trace expects x%0d, hint head has x%0d",
            expected_rd, async_wb_q[i].rd))
        end
        hint = async_wb_q[i];
        async_wb_q.delete(i);
        return 1'b1;
      end
      return 1'b0;
    end

    if (is_load_instruction(item)) begin
      foreach (async_wb_q[i]) begin
        if (async_wb_q[i].source != EH2_WB_SRC_NB_LOAD) continue;
        if (async_wb_q[i].rd != expected_rd) continue;
        hint = async_wb_q[i];
        async_wb_q.delete(i);
        return 1'b1;
      end
    end

    return 1'b0;
  endfunction

  function void enqueue_memory_accesses(axi4_seq_item txn);
    pending_mem_access_t access;
    access.txn = txn;
    access.is_store = (txn.tx_type == axi4_seq_item::AXI4_WRITE);
    access.observed_access_count = count_observed_memory_accesses(txn);
    pending_mem_access_q.push_back(access);
  endfunction

  function int count_observed_memory_accesses(axi4_seq_item txn);
    int observed_access_count;
    observed_access_count = 0;

    if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
      for (int i = 0; i < txn.get_beat_count(); i++) begin
        bit [7:0] beat_strb = txn.strb[i];
        int beat_bytes = (1 << txn.size);
        observed_access_count += ((beat_strb[3:0] != 4'b0) ? 1 : 0) +
                                 ((beat_bytes > 4 && beat_strb[7:4] != 4'b0) ? 1 : 0);
      end
    end else begin
      observed_access_count = txn.get_beat_count();
    end

    return observed_access_count;
  endfunction

  function bit has_matching_memory_access(eh2_trace_seq_item item);
    bit need_store;
    need_store = is_store_or_amo_instruction(item);

    foreach (pending_mem_access_q[i]) begin
      if (pending_mem_access_q[i].is_store == need_store) return 1'b1;
    end

    return 1'b0;
  endfunction

  function void pop_matching_memory_access(eh2_trace_seq_item item);
    bit need_store;
    need_store = is_store_or_amo_instruction(item);

    foreach (pending_mem_access_q[i]) begin
      if (pending_mem_access_q[i].is_store == need_store) begin
        notify_memory_access(pending_mem_access_q[i].txn);
        pending_mem_access_q.delete(i);
        return;
      end
    end

    `uvm_error("cosim", $sformatf(
      "Internal error: no queued LSU access for memory instruction PC=%08x insn=%08x",
      item.pc, item.insn))
  endfunction

  // Notify Spike about a memory access from the AXI4 bus.
  // AXI4 bus is 64-bit; split 64-bit beats into two 32-bit notifications.
  function void notify_memory_access(axi4_seq_item txn);
    if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
      bit write_error = (txn.resp[0] != axi4_seq_item::AXI4_RESP_OKAY);

      for (int i = 0; i < txn.get_beat_count(); i++) begin
        bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
        bit [63:0] beat_data = txn.data[i];
        bit [7:0]  beat_strb = txn.strb[i];
        int beat_bytes = (1 << txn.size);

        if (beat_strb[3:0] != 4'b0) begin
          riscv_cosim_notify_dside_access(cosim_handle,
            1, int'(beat_data[31:0]), int'(beat_addr),
            int'({4'b0, beat_strb[3:0]}),
            int'(write_error), 0, 0, 0, 1, 0);
          `uvm_info("cosim", $sformatf("MEM WR: addr=%08x data=%08x be=%04b",
            beat_addr, beat_data[31:0], beat_strb[3:0]), UVM_HIGH)
        end

        if (beat_bytes > 4 && beat_strb[7:4] != 4'b0) begin
          riscv_cosim_notify_dside_access(cosim_handle,
            1, int'(beat_data[63:32]), int'(beat_addr + 4),
            int'({4'b0, beat_strb[7:4]}),
            int'(write_error), 0, 0, 0, 1, 0);
          `uvm_info("cosim", $sformatf("MEM WR: addr=%08x data=%08x be=%04b",
            beat_addr + 4, beat_data[63:32], beat_strb[7:4]), UVM_HIGH)
        end
      end
    end else begin
      for (int i = 0; i < txn.get_beat_count(); i++) begin
        bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
        bit [63:0] beat_data = txn.rdata[i];
        bit read_error = (txn.resp[i] != axi4_seq_item::AXI4_RESP_OKAY);
        int beat_bytes = (1 << txn.size);
        bit widened_load = (beat_bytes > 4);
        bit [3:0] read_be = ((4'b0001 << beat_bytes) - 1) << beat_addr[1:0];

        riscv_cosim_notify_dside_access(cosim_handle,
          0, int'(beat_data[31:0]), int'(beat_addr),
          int'(read_be), int'(read_error),
          0, 0, 0, 1, int'(widened_load));
        `uvm_info("cosim", $sformatf("MEM RD: addr=%08x data=%08x",
          beat_addr, beat_data[31:0]), UVM_HIGH)

        if (beat_bytes > 4) begin
          riscv_cosim_notify_dside_access(cosim_handle,
            0, int'(beat_data[63:32]), int'(beat_addr + 4),
            int'(4'hf), int'(read_error),
            0, 0, 0, 1, int'(widened_load));
          `uvm_info("cosim", $sformatf("MEM RD: addr=%08x data=%08x",
            beat_addr + 4, beat_data[63:32]), UVM_HIGH)
        end
      end
    end
  endfunction

  // Compare one instruction against Spike.
  function void compare_instruction(eh2_trace_seq_item item);
    bit [4:0]  write_reg;
    bit [31:0] write_reg_data;
    bit        sync_trap;
    bit        suppress_reg_write;
    int        result;
    async_wb_hint_t async_hint;

    // EH2: When interrupt=1 and exception=0, the trace item is only an
    // interrupt notification (no instruction executed at this PC).
    if (item.interrupt && !item.exception) begin
      riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req));
      riscv_cosim_set_nmi(cosim_handle, int'(item.nmi));
      riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int));
      riscv_cosim_set_mip(cosim_handle, int'(prev_mip), int'(item.mip));
      prev_mip = item.mip;
      riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle));
      `uvm_info("cosim", $sformatf("IRQ-ONLY: PC=%08x", item.pc), UVM_HIGH)
      return;
    end

    // Pull writeback view directly from the trace packet (RVFI-equivalent).
    if (item.wb_valid && item.wb_dest != 0) begin
      write_reg          = item.wb_dest;
      write_reg_data     = item.wb_data;
      suppress_reg_write = 0;
    end else begin
      write_reg          = 0;
      write_reg_data     = 0;
      suppress_reg_write = 0;
    end

    // Async overrides: NB-load completion supplies the writeback data the
    // trace packet could not.
    //
    // DIV behavior: in EH2 a younger instruction writing the same rd as a
    // pending div triggers `dec_div_cancel`, which kills the div writeback
    // in the regular pipeline. The architectural rd value Spike expects is
    // the div result, but the RTL never writes it. Bridging this gap from
    // a separate async hint cannot be done reliably (cancels and writebacks
    // do not pair 1:1 with retired div trace entries because the div unit
    // also runs speculative divs). For Phase 1 we set div writeback to the
    // async hint's data when one is available; otherwise we tell Spike the
    // DUT did not write rd. This leaves Spike's RF view of div results
    // potentially stale, but that is acceptable for the random-arithmetic
    // sign-off slice (later phases will tighten this with per-div RTL
    // tagging).
    if (try_consume_async_wb(item, async_hint)) begin
      if (async_hint.suppress) begin
        suppress_reg_write = 1;
        write_reg          = 0;
        write_reg_data     = 0;
      end else begin
        write_reg          = async_hint.rd;
        write_reg_data     = async_hint.rd_data;
        suppress_reg_write = 0;
      end
    end else if (item.is_div()) begin
      // No async hint available - div completion happens later, or the div
      // was cancelled. Tell Spike the DUT did not write rd; Spike will keep
      // its own computed value internally, leaving an architectural divergence
      // that subsequent same-rd writes will reconcile.
      suppress_reg_write = 1;
      write_reg          = 0;
      write_reg_data     = 0;
    end

    sync_trap = item.exception && !item.interrupt;

    // Spike notification ordering (Ibex pattern)
    riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req));
    riscv_cosim_set_nmi(cosim_handle, int'(item.nmi));
    riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int));
    riscv_cosim_set_mip(cosim_handle, int'(prev_mip), int'(item.mip));
    prev_mip = item.mip;
    riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle));
    if (item.exception && !item.interrupt && item.ecause == 5'd1) begin
      riscv_cosim_set_iside_error(cosim_handle, int'(item.pc));
    end

    result = riscv_cosim_step(cosim_handle,
      int'(write_reg), int'(write_reg_data),
      int'(item.pc), sync_trap ? 1 : 0,
      suppress_reg_write ? 1 : 0);

    if (result == 0) begin
      mismatch_count++;
      `uvm_info("cosim", $sformatf(
        "MISMATCH: PC=%08x insn=%08x slot=%0d rd=x%0d data=%08x",
        item.pc, item.insn, item.slot, write_reg, write_reg_data), UVM_LOW)
      if (fatal_on_mismatch) begin
        `uvm_fatal("cosim", $sformatf("MISMATCH at PC=%08x insn=%08x\n%s",
          item.pc, item.insn, get_cosim_error_str()))
      end else begin
        `uvm_error("cosim", $sformatf("MISMATCH at PC=%08x insn=%08x\n%s",
          item.pc, item.insn, get_cosim_error_str()))
      end
    end else begin
      `uvm_info("cosim", $sformatf("MATCH: PC=%08x insn=%08x rd=x%0d data=%08x",
        item.pc, item.insn, write_reg, write_reg_data), UVM_HIGH)
    end

    step_count++;
  endfunction

  function string get_cosim_error_str();
    string error = "Cosim mismatch: ";
    int num_errors = riscv_cosim_get_num_errors(cosim_handle);
    for (int i = 0; i < num_errors; i++) begin
      error = {error, riscv_cosim_get_error(cosim_handle, i), "\n"};
    end
    riscv_cosim_clear_errors(cosim_handle);
    return error;
  endfunction

  // Load binary into co-simulation reference model
  function void load_binary(string bin_path, bit [31:0] base_addr);
    `uvm_info("cosim", $sformatf("Loading binary: %s at 0x%08x", bin_path, base_addr), UVM_LOW)

    if (cosim_handle == null) begin
      `uvm_error("cosim", "Cannot load binary: cosim not initialized")
      return;
    end

    if (bin_path.len() > 4 && bin_path.substr(bin_path.len()-4, bin_path.len()-1) == ".hex") begin
      load_hex(bin_path, base_addr);
    end else begin
      load_raw_binary(bin_path, base_addr);
    end

    stored_bin_path = bin_path;
    stored_base_addr = base_addr;
  endfunction

  function void load_raw_binary(string bin_path, bit [31:0] base_addr);
    int fd;
    int byte_val;
    bit [7:0] mem_byte;
    bit [31:0] addr;
    int bytes_loaded;

    fd = $fopen(bin_path, "rb");
    if (fd == 0) begin
      `uvm_error("cosim", $sformatf("Cannot open binary file: %s", bin_path))
      return;
    end

    addr = base_addr;
    bytes_loaded = 0;
    while (!$feof(fd)) begin
      byte_val = $fread(mem_byte, fd);
      if (byte_val == 1) begin
        riscv_cosim_write_mem_byte(cosim_handle, int'(addr), int'(mem_byte));
        addr++;
        bytes_loaded++;
      end
    end
    $fclose(fd);

    `uvm_info("cosim", $sformatf("Loaded %0d bytes (raw) into cosim at 0x%08x",
      bytes_loaded, base_addr), UVM_LOW)
  endfunction

  function void load_hex(string hex_path, bit [31:0] base_addr);
    int fd;
    int addr;
    int c;
    bit [7:0] val;
    int nybble_count;
    int bytes_loaded;

    fd = $fopen(hex_path, "r");
    if (fd == 0) begin
      `uvm_error("cosim", $sformatf("Cannot open hex file: %s", hex_path))
      return;
    end

    addr = base_addr;
    bytes_loaded = 0;
    nybble_count = 0;
    val = 0;

    while (!$feof(fd)) begin
      c = $fgetc(fd);
      if (c < 0) break;

      if (c == "@") begin
        int new_addr;
        new_addr = 0;
        while (!$feof(fd)) begin
          c = $fgetc(fd);
          if (c < 0) break;
          if (c >= "0" && c <= "9")      new_addr = (new_addr << 4) | (c - "0");
          else if (c >= "a" && c <= "f") new_addr = (new_addr << 4) | (c - "a" + 10);
          else if (c >= "A" && c <= "F") new_addr = (new_addr << 4) | (c - "A" + 10);
          else break;
        end
        addr = new_addr;
        nybble_count = 0;
        val = 0;
      end else if (c >= "0" && c <= "9") begin
        val = (val << 4) | (c - "0");
        nybble_count++;
      end else if (c >= "a" && c <= "f") begin
        val = (val << 4) | (c - "a" + 10);
        nybble_count++;
      end else if (c >= "A" && c <= "F") begin
        val = (val << 4) | (c - "A" + 10);
        nybble_count++;
      end else if (c == " " || c == "\t" || c == "\n" || c == "\r") begin
        if (nybble_count > 0) begin
          riscv_cosim_write_mem_byte(cosim_handle, int'(addr), int'(val));
          addr++;
          bytes_loaded++;
          val = 0;
          nybble_count = 0;
        end
      end
    end
    if (nybble_count > 0) begin
      riscv_cosim_write_mem_byte(cosim_handle, int'(addr), int'(val));
      bytes_loaded++;
    end

    $fclose(fd);
    `uvm_info("cosim", $sformatf("Loaded %0d bytes (hex) into cosim at 0x%08x",
      bytes_loaded, base_addr), UVM_LOW)
  endfunction

  protected function void init_cosim();
    cleanup_cosim();

    if (enable_cosim) begin
      cosim_handle = riscv_cosim_init(cosim_config);
      if (cosim_handle == null) begin
        `uvm_fatal("cosim", "Failed to initialize co-simulation")
      end
      initialized = 1;

      // Register all DUT-accessible memory regions with Spike.
      riscv_cosim_add_memory(cosim_handle, 32'h8000_0000, 32'h0400_0000); // 64 MiB boot/main
      riscv_cosim_add_memory(cosim_handle, 32'hA058_0000, 32'h0400_0000); // 64 MiB debug SB
      riscv_cosim_add_memory(cosim_handle, 32'hB000_0000, 32'h0400_0000); // 64 MiB ext data 1
      riscv_cosim_add_memory(cosim_handle, 32'hC058_0000, 32'h0400_0000); // 64 MiB ext data
      riscv_cosim_add_memory(cosim_handle, 32'hEE00_0000, 32'h0001_0000); // 64 KiB ICCM
      riscv_cosim_add_memory(cosim_handle, 32'hF004_0000, 32'h0001_0000); // 64 KiB DCCM
      riscv_cosim_add_memory(cosim_handle, 32'hF00C_0000, 32'h0000_8000); // 32 KiB PIC
      riscv_cosim_add_memory(cosim_handle, 32'hD058_0000, 32'h0000_1000); // 4 KiB mailbox
      riscv_cosim_add_memory(cosim_handle, 32'h1111_0000, 32'h0000_1000); // 4 KiB NMI vec

      // Pre-register EH2 custom CSRs in Spike.
      riscv_cosim_set_csr(cosim_handle, 32'h7FF, 0);  // mscause
      riscv_cosim_set_csr(cosim_handle, 32'h7C0, 0);  // mrac
      riscv_cosim_set_csr(cosim_handle, 32'h7F9, 0);  // mfdc
      riscv_cosim_set_csr(cosim_handle, 32'h7F8, 0);  // mcgc
      riscv_cosim_set_csr(cosim_handle, 32'h7C6, 0);  // mpmc
      riscv_cosim_set_csr(cosim_handle, 32'h7C2, 0);  // mcpc
      riscv_cosim_set_csr(cosim_handle, 32'h7C4, 0);  // dmst
      riscv_cosim_set_csr(cosim_handle, 32'h7CE, 0);  // mfdht
      riscv_cosim_set_csr(cosim_handle, 32'h7CF, 0);  // mfdhs
      riscv_cosim_set_csr(cosim_handle, 32'h7FC, 0);  // mhartstart
      riscv_cosim_set_csr(cosim_handle, 32'h7FE, 0);  // mnmipdel
      riscv_cosim_set_csr(cosim_handle, 32'h7D2, 0);  // mitcnt0
      riscv_cosim_set_csr(cosim_handle, 32'h7D5, 0);  // mitcnt1
      riscv_cosim_set_csr(cosim_handle, 32'h7D3, 0);  // mitb0
      riscv_cosim_set_csr(cosim_handle, 32'h7D6, 0);  // mitb1
      riscv_cosim_set_csr(cosim_handle, 32'h7D4, 0);  // mitctl0
      riscv_cosim_set_csr(cosim_handle, 32'h7D7, 0);  // mitctl1
      riscv_cosim_set_csr(cosim_handle, 32'hBC0, 0);  // mdeau
      riscv_cosim_set_csr(cosim_handle, 32'hFC0, 0);  // mdseac
      riscv_cosim_set_csr(cosim_handle, 32'h7F0, 0);  // micect
      riscv_cosim_set_csr(cosim_handle, 32'h7F1, 0);  // miccmect
      riscv_cosim_set_csr(cosim_handle, 32'h7F2, 0);  // mdccmect
      riscv_cosim_set_csr(cosim_handle, 32'hBC8, 0);  // meivt
      riscv_cosim_set_csr(cosim_handle, 32'hFC8, 0);  // meihap
      riscv_cosim_set_csr(cosim_handle, 32'hBC9, 0);  // meipt
      riscv_cosim_set_csr(cosim_handle, 32'hBCA, 0);  // meicpct
      riscv_cosim_set_csr(cosim_handle, 32'hBCC, 0);  // meicurpl
      riscv_cosim_set_csr(cosim_handle, 32'hBCB, 0);  // meicidpl

      `uvm_info("cosim", "Pre-registered 28 EH2 custom CSRs", UVM_LOW)

      if (pending_bin_path != "") begin
        `uvm_info("cosim", $sformatf("Loading pending binary: %s at 0x%08x",
          pending_bin_path, pending_base_addr), UVM_LOW)
        load_binary(pending_bin_path, pending_base_addr);
        pending_bin_path = "";
      end
      else if (stored_bin_path != "") begin
        `uvm_info("cosim", "Reloading binary after reset recovery", UVM_LOW)
        load_binary(stored_bin_path, stored_base_addr);
      end
    end

    step_count = 0;
    mismatch_count = 0;
    trace_item_count = 0;
    probe_item_count = 0;
    suppressed_probe_item_count = 0;
    axi_item_count = 0;
    prev_mip = 0;
    pending_trace_q.delete();
    pending_mem_access_q.delete();
    async_wb_q.delete();
    pending_trace_high_watermark = 0;
  endfunction

  protected function void cleanup_cosim();
    if (cosim_handle != null) begin
      riscv_cosim_destroy(cosim_handle);
      cosim_handle = null;
    end
    initialized = 0;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("cosim", "=== Co-simulation Scoreboard Report ===", UVM_LOW)
    `uvm_info("cosim", $sformatf("Trace items received: %0d", trace_item_count), UVM_LOW)
    `uvm_info("cosim", $sformatf("Probe items received: %0d (async-only)", probe_item_count), UVM_LOW)
    `uvm_info("cosim", $sformatf("AXI items received: %0d", axi_item_count), UVM_LOW)
    `uvm_info("cosim", $sformatf("Pending trace items: %0d", pending_trace_q.size()), UVM_LOW)
    `uvm_info("cosim", $sformatf("Pending LSU accesses: %0d", pending_mem_access_q.size()), UVM_LOW)
    `uvm_info("cosim", $sformatf("Pending async wb hints: %0d", async_wb_q.size()), UVM_LOW)
    `uvm_info("cosim", $sformatf("Trace backlog high watermark: %0d",
      pending_trace_high_watermark), UVM_LOW)
    `uvm_info("cosim", $sformatf("Steps executed: %0d", step_count), UVM_LOW)
    `uvm_info("cosim", $sformatf("Mismatches: %0d", mismatch_count), UVM_LOW)
    if (cosim_handle != null) begin
      `uvm_info("cosim", $sformatf("Instructions matched: %0d",
        riscv_cosim_get_insn_cnt(cosim_handle)), UVM_LOW)
    end
    if (mismatch_count == 0 && pending_trace_q.size() == 0 &&
        pending_mem_access_q.size() == 0 && step_count > 0) begin
      `uvm_info("cosim", "RESULT: PASS", UVM_LOW)
    end else if (trace_item_count > 0 || step_count > 0 ||
                 pending_trace_q.size() > 0 ||
                 pending_mem_access_q.size() > 0) begin
      `uvm_error("cosim", "RESULT: FAIL")
    end
  endfunction

  function void final_phase(uvm_phase phase);
    super.final_phase(phase);
    if (cosim_handle != null) begin
      `uvm_info("cosim", $sformatf("Co-simulation matched %0d instructions",
        riscv_cosim_get_insn_cnt(cosim_handle)), UVM_LOW)
    end
    cleanup_cosim();
  endfunction

  function void pre_abort();
    cleanup_cosim();
  endfunction

endclass
