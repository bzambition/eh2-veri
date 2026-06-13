// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Register DUT (Issue 56 / PROMPT-A) -- Thin wrapper around real RTL
//
// Instantiates the real EH2 CSR decode RTL (eh2_dec_csr) for legality
// checking and address decoding.  CSR data storage is maintained in this
// wrapper for stand-alone unit test read/write, but WARL behaviour is
// governed by the UVM reg_model (eh2_csr_reg_block), NOT by logic in
// Thin wrapper shell around real EH2 RTL; no behavioral WARL logic.
//
// RTL source: /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_csr.sv
// Interface modelled after lowRISC Ibex ibex_cs_registers.

module csr_dut #(
  parameter bit               PMPEnable        = 1,
  parameter int unsigned      PMPNumRegions    = 16,
  parameter int unsigned      PMPGranularity   = 0,
  parameter int unsigned      MHPMCounterNum   = 4,
  parameter int unsigned      MHPMCounterWidth = 40
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // CSR access interface (ibex-compatible)
  input  logic        csr_access_i,
  input  logic [11:0] csr_addr_i,
  input  logic [31:0] csr_wdata_i,
  input  logic [1:0]  csr_op_i,       // 0=read, 1=write, 2=set, 3=clear
  input  logic        csr_op_en_i,
  output logic [31:0] csr_rdata_o,
  output logic        illegal_csr_insn_o
);

  // ====================================================================
  // eh2_dec_csr instantiation -- real EH2 RTL for CSR decode + legality
  // ====================================================================
  //
  // Port binding strategy for EH2-specific signals:
  //
  // | EH2 port            | Binding          | Rationale                           |
  // |---------------------|------------------|-------------------------------------|
  // | dec_csr_rdaddr_d    | csr_addr_i       | 12-bit CSR number from UVM driver   |
  // | dec_csr_any_unq_d   | csr_access & en  | Qualifies a valid decode in pipe    |
  // | dec_csr_wen_unq_d   | csr_access & en  | Write-enable qualifier; deasserted  |
  // |                     | & (op != READ)   | for CSRRS/C with rs1=x0 (op=0)      |
  // | dec_tlu_dbg_halted  | 1'b0             | Unit test runs in M-mode.  Setting  |
  // |                     |                  | to 0 means debug-only CSRs (dcsr,   |
  // |                     |                  | dpc, dmst, trigger) report ILLEGAL  |
  // |                     |                  | which is correct for non-debug mode.|
  // | tlu_csr_pkt_d       | unconnected      | Decode packet; observation only     |
  // | tlu_presync_d       | unconnected      | Pipeline sync; not used in unit test|
  // | tlu_postsync_d      | unconnected      | Pipeline sync; not used in unit test|
  //
  // Ports NOT present in eh2_dec_csr (this is a pure decode module):
  //   - PIC interface: PIC CSR accesses go through TLU write path, not
  //     through the decoder.  Unit test accesses are direct to CSR addr.
  //   - Dual-thread interface: eh2_dec_csr is inherently per-thread but
  //     receives only address and access qualifiers.  Thread-ID tracking
  //     lives in the TLU.  This wrapper assumes single-thread (mytid=0).
  //   - clk / rst: eh2_dec_csr is purely combinational; no clock needed.

  logic                dec_csr_any_unq;
  logic                dec_csr_wen_unq;
  logic                dec_csr_legal;
  logic                tlu_presync;
  logic                tlu_postsync;

  eh2_dec_csr i_eh2_dec_csr (
    .dec_csr_rdaddr_d  (csr_addr_i),
    .dec_csr_any_unq_d (dec_csr_any_unq),
    .dec_csr_wen_unq_d (dec_csr_wen_unq),
    .dec_tlu_dbg_halted(1'b0),          // unit test: not in debug mode
    .dec_csr_legal_d   (dec_csr_legal),
    .tlu_presync_d     (tlu_presync),
    .tlu_postsync_d    (tlu_postsync),
    .tlu_csr_pkt_d     ()               // unconnected: decode packet
  );

  // Qualify access signals for the RTL decoder
  assign dec_csr_any_unq = csr_access_i & csr_op_en_i;
  assign dec_csr_wen_unq = csr_access_i & csr_op_en_i & (csr_op_i != 2'b00);

  // ====================================================================
  // CSR data storage -- sparse associative array
  // ====================================================================
  // Stores only addresses that are actually written.
  // Sparse associative array; only populated addresses consume memory.
  // WARL behaviour is NOT implemented here; it is defined in the UVM
  // reg_model (eh2_csr_reg_block).  The DUT stores exactly the value
  // written; UVM sequences compare readback against reg_model predictions.

  logic [31:0] csr_data[logic [11:0]];

  // ====================================================================
  // Read data path (always_comb because associative arrays cannot be
  // used in continuous assignments)
  // ====================================================================
  always_comb begin
    if (csr_access_i && csr_op_en_i)
      csr_rdata_o = csr_data[csr_addr_i];
    else
      csr_rdata_o = 32'h0;
  end

  // ====================================================================
  // Illegal CSR access flag -- driven by real RTL
  // ====================================================================
  assign illegal_csr_insn_o = csr_access_i && csr_op_en_i && !dec_csr_legal;

  // ====================================================================
  // Write logic -- direct store, NO WARL masking in DUT
  // ====================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Reset: clear all storage and set hardwired RO reset values
      csr_data.delete();
      csr_data[12'hF12] = 32'h56524545;  // marchid = "VEER" (RO)
      csr_data[12'h301] = 32'h40001105;  // misa = RV32IMAC (RO)
      csr_data[12'h300] = 32'h00001800;  // mstatus (MPP=3)
      csr_data[12'h7FC] = 32'h8000_0000; // mhartstart
    end else if (csr_access_i && csr_op_en_i && dec_csr_legal) begin
      case (csr_op_i)
        2'b00: ; // read -- no-op
        2'b01: csr_data[csr_addr_i] <= csr_wdata_i;                // CSRW
        2'b10: csr_data[csr_addr_i] <= csr_data[csr_addr_i] | csr_wdata_i; // CSRS
        2'b11: csr_data[csr_addr_i] <= csr_data[csr_addr_i] & ~csr_wdata_i; // CSRC
      endcase
    end
  end

  // ====================================================================
  // Hierarchical access functions (called by tb_csr_read/write in TB)
  // ====================================================================
`ifndef SYNTHESIS
  function automatic bit [31:0] dut_read(logic [11:0] addr);
    return csr_data.exists(addr) ? csr_data[addr] : 32'h0;
  endfunction

  function automatic int dut_write(logic [11:0] addr, bit [31:0] wdata, int op);
    if (!dec_csr_legal) return -1;
    if (op == 1)                    csr_data[addr] = wdata;
    else if (op == 2)               csr_data[addr] = csr_data[addr] | wdata;
    else if (op == 3)               csr_data[addr] = csr_data[addr] & ~wdata;
    return 0;
  endfunction
`endif

endmodule
