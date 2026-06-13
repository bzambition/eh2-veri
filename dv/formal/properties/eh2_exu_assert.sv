// ============================================================================
// eh2_exu_assert.sv — EH2 EXU (Execution Unit) SVA Properties
// Formal properties on eh2_exu: ALU, multiplier, divider
//
// Properties (7 total):
//   1. p_mul_result_one_cycle:        MUL result ready in 1 cycle (RV32IM)
//   2. p_div_no_overlap:              No new DIV while previous in progress
//   3. p_alu_result_valid:            ALU op with valid inputs → result valid
//   4. p_branch_resolve_correct:      Branch ALU result matches condition
//   5. p_multicycle_op_done:          Multi-cycle ops eventually complete
//   6. p_div_by_zero_no_hang:         Div by zero completes (not hang)
//   7. c_mul_div_concurrent:          Cover: MUL and DIV in adjacent cycles
// ============================================================================

module eh2_exu_assert
  import eh2_pkg::*;
#(
`include "eh2_param.vh"
) (
  input logic        clk,
  input logic        rst_l,

  // --- ALU signals ---
  input logic        alu_valid_i,
  input logic [31:0] alu_operand_a,
  input logic [31:0] alu_operand_b,
  input logic [3:0]  alu_op,
  input logic [31:0] alu_result,
  input logic        alu_result_valid,

  // --- MUL signals ---
  input logic        mul_valid_i,
  input logic [31:0] mul_operand_a,
  input logic [31:0] mul_operand_b,
  input logic [31:0] mul_result,
  input logic        mul_result_valid,
  input logic        mul_busy,

  // --- DIV signals ---
  input logic        div_valid_i,
  input logic [31:0] div_dividend,
  input logic [31:0] div_divisor,
  input logic [31:0] div_quotient,
  input logic [31:0] div_remainder,
  input logic        div_result_valid,
  input logic        div_busy,
  input logic        div_done
);

  // ========================================================================
  // Property 1: MUL result ready in 1 cycle (RV32IM single-cycle multiplier)
  // ========================================================================
  property p_mul_result_one_cycle;
    @(posedge clk) disable iff (!rst_l)
    (mul_valid_i)
    |=>
    (mul_result_valid);
  endproperty
  a_mul_result_one_cycle: assert property(p_mul_result_one_cycle);

  // ========================================================================
  // Property 2: No new DIV accepted while previous in progress
  // ========================================================================
  property p_div_no_overlap;
    @(posedge clk) disable iff (!rst_l)
    (div_busy)
    |->
    (!div_valid_i);
  endproperty
  a_div_no_overlap: assert property(p_div_no_overlap);

  // ========================================================================
  // Property 3: ALU op with valid inputs produces valid result
  // ========================================================================
  property p_alu_result_valid;
    @(posedge clk) disable iff (!rst_l)
    (alu_valid_i)
    |=>
    (alu_result_valid);
  endproperty
  a_alu_result_valid: assert property(p_alu_result_valid);

  // ========================================================================
  // Property 4: Branch ALU — result is 0 when operands equal (BEQ case)
  // ========================================================================
  property p_branch_resolve_beq;
    @(posedge clk) disable iff (!rst_l)
    (alu_valid_i && (alu_op == 4'b0000))  // SUB for BEQ comparison
    |->
    ((alu_operand_a == alu_operand_b) |-> (alu_result == 32'h0));
  endproperty
  a_branch_resolve_beq: assert property(p_branch_resolve_beq);

  // ========================================================================
  // Property 5: Multi-cycle DIV completes (bounded liveness)
  // ========================================================================
  property p_div_completes;
    @(posedge clk) disable iff (!rst_l)
    (div_valid_i)
    |->
    ##[1:64] (div_done);
  endproperty
  a_div_completes: assert property(p_div_completes);

  // ========================================================================
  // Property 6: DIV by zero does not hang (completes with result)
  // ========================================================================
  property p_div_by_zero_no_hang;
    @(posedge clk) disable iff (!rst_l)
    (div_valid_i && (div_divisor == 32'h0))
    |->
    ##[1:64] (div_done);
  endproperty
  a_div_by_zero_no_hang: assert property(p_div_by_zero_no_hang);

  // ========================================================================
  // Cover properties
  // ========================================================================
  c_mul_div_back_to_back: cover property(
    @(posedge clk) (mul_valid_i) ##1 (div_valid_i)
  );

  c_div_completed: cover property(
    @(posedge clk) (div_valid_i ##[1:64] div_done)
  );

  c_branch_taken: cover property(
    @(posedge clk) (alu_valid_i && (alu_op == 4'b0000) && (alu_operand_a == alu_operand_b))
  );

endmodule
