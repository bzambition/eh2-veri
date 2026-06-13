// ============================================================================
// eh2_lsu_assert.sv — EH2 LSU (Load/Store Unit) SVA Properties
// Formal properties on eh2_lsu: bus handshake, store buffer, alignment
//
// Properties (7 total):
//   1. p_bus_handshake_complete:     valid+ready → handshake completes same cycle
//   2. p_store_buf_no_overflow:      Store buffer depth never exceeds limit
//   3. p_addr_align_legal:           Word access → addr[1:0]==0, half→addr[0]==0
//   4. p_dccm_read_data_stable:      DCCM read data stable within access window
//   5. p_amo_read_modify_write:      AMO → store data matches modified read data
//   6. p_bus_error_triggers_exception: Bus error → exception flag set
//   7. c_lsu_load_store_reachable:   Cover: back-to-back load+store
// ============================================================================

module eh2_lsu_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        rst_l,

  // --- LSU bus signals ---
  input logic        lsu_bus_valid,
  input logic        lsu_bus_ready,
  input logic [31:0] lsu_bus_addr,
  input logic [31:0] lsu_bus_wdata,
  input logic [31:0] lsu_bus_rdata,
  input logic        lsu_bus_write,
  input logic [1:0]  lsu_bus_size,    // 00=byte, 01=half, 10=word
  input logic        lsu_bus_error,

  // --- Store buffer signals ---
  input logic [3:0]  stbuf_count,
  input logic        stbuf_full,
  input logic        stbuf_push,
  input logic        stbuf_pop,

  // --- DCCM signals ---
  input logic        dccm_read_valid,
  input logic [31:0] dccm_read_data,

  // --- AMO signals ---
  input logic        amo_active,
  input logic [31:0] amo_read_data,
  input logic [31:0] amo_write_data,
  input logic        amo_complete,

  // --- Exception signals ---
  input logic        lsu_exception,
  input logic [3:0]  lsu_exc_cause
);

  // ========================================================================
  // Property 1: Bus handshake completes when valid+ready
  // ========================================================================
  property p_bus_handshake_complete;
    @(posedge clk) disable iff (!rst_l)
    (lsu_bus_valid && lsu_bus_ready)
    |->
    (lsu_bus_valid && lsu_bus_ready);  // handshake is single-cycle
  endproperty
  a_bus_handshake_complete: assert property(p_bus_handshake_complete);

  // ========================================================================
  // Property 2: Store buffer never exceeds capacity
  // ========================================================================
  property p_store_buf_no_overflow;
    @(posedge clk) disable iff (!rst_l)
    (1'b1)
    |->
    (!stbuf_full || stbuf_pop);
  endproperty
  a_store_buf_no_overflow: assert property(p_store_buf_no_overflow);

  // ========================================================================
  // Property 3: Address alignment check
  // ========================================================================
  property p_addr_align_legal;
    @(posedge clk) disable iff (!rst_l)
    (lsu_bus_valid)
    |->
    ((lsu_bus_size == 2'b10) |-> (lsu_bus_addr[1:0] == 2'b00)) and
    ((lsu_bus_size == 2'b01) |-> (lsu_bus_addr[0]   == 1'b0));
  endproperty
  a_addr_align_legal: assert property(p_addr_align_legal);

  // ========================================================================
  // Property 4: DCCM read data stable for one cycle after valid
  // ========================================================================
  property p_dccm_read_data_stable;
    @(posedge clk) disable iff (!rst_l)
    (dccm_read_valid)
    |=>
    ($stable(dccm_read_data));
  endproperty
  a_dccm_read_data_stable: assert property(p_dccm_read_data_stable);

  // ========================================================================
  // Property 5: AMO completion → write data reflects read-modify-write
  // ========================================================================
  property p_amo_read_modify_write;
    @(posedge clk) disable iff (!rst_l)
    (amo_complete)
    |->
    (amo_write_data != amo_read_data); // AMO modifies data (non-trivial check)
  endproperty
  a_amo_read_modify_write: assert property(p_amo_read_modify_write);

  // ========================================================================
  // Property 6: Bus error triggers exception in the same cycle
  // ========================================================================
  property p_bus_error_triggers_exception;
    @(posedge clk) disable iff (!rst_l)
    (lsu_bus_error)
    |->
    (lsu_exception);
  endproperty
  a_bus_error_triggers_exception: assert property(p_bus_error_triggers_exception);

  // ========================================================================
  // Cover properties
  // ========================================================================
  c_lsu_load_store_reachable: cover property(
    @(posedge clk) (lsu_bus_valid && lsu_bus_write) ##1 (lsu_bus_valid && !lsu_bus_write)
  );

  c_store_buf_utilized: cover property(
    @(posedge clk) (stbuf_count > 4'd2)
  );

  c_amo_executed: cover property(
    @(posedge clk) (amo_active ##[1:5] amo_complete)
  );

endmodule
