// SPDX-License-Identifier: Apache-2.0
// EH2 Directed Instruction Library
//
// Custom directed instruction streams for EH2-specific verification:
//   - eh2_csr_access_stream: Random CSR read/write sequences
//   - eh2_bitmanip_stream: Zba/Zbb/Zbc/Zbs instruction sequences
//   - eh2_pic_int_stream: PIC interrupt CSR manipulation
//   - eh2_debug_stream: Debug CSR access sequences
//   - eh2_atomic_stream: LR/SC atomic sequences

// ---------------------------------------------------------------------------
// CSR Access Stream
// Generates random CSR read/write/set/clear sequences for EH2 custom CSRs
// ---------------------------------------------------------------------------
class eh2_csr_access_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_csr_access_stream)

  // EH2 writable custom CSRs
  localparam bit [11:0] EH2_CUSTOM_CSRS[] = '{
    12'h7FF,  // mscause
    12'h7C0,  // mrac
    12'h7C9,  // mfdc
    12'h7F8,  // mcgc
    12'h7C6,  // mpmc
    12'h7C2,  // mcpc
    12'h7C4,  // dmst
    12'h7CE,  // mfdht
    12'h7CF,  // mfdhs
    12'h7FE,  // mnmipdel
    12'h7D2,  // mitcnt0
    12'h7D5,  // mitcnt1
    12'h7D3,  // mitb0
    12'h7D6,  // mitb1
    12'h7D4,  // mitctl0
    12'h7D7,  // mitctl1
    12'h7F0,  // micect
    12'h7F1,  // miccmect
    12'h7F2   // mdccmect
  };

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                  bit is_debug_program = 0);
    riscv_instr instr;
    int unsigned csr_idx;
    bit [11:0] csr_addr;

    repeat (10 + $urandom_range(10)) begin
      csr_idx = $urandom_range(EH2_CUSTOM_CSRS.size() - 1);
      csr_addr = EH2_CUSTOM_CSRS[csr_idx];

      // Generate CSRRW, CSRRS, or CSRRC randomly
      case ($urandom_range(2))
        0: instr = riscv_instr::get_instr(CSRRW);
        1: instr = riscv_instr::get_instr(CSRRS);
        2: instr = riscv_instr::get_instr(CSRRC);
      endcase

      instr.csr = csr_addr;
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
      instr.rd  = riscv_reg_t'($urandom_range(1, 31));
      instr_list.push_back(instr);
    end
  endfunction

endclass

// ---------------------------------------------------------------------------
// Bitmanip Instruction Stream
// Generates Zba/Zbb/Zbc/Zbs instructions
// ---------------------------------------------------------------------------
class eh2_bitmanip_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_bitmanip_stream)

  // Zba (address generation)
  localparam riscv_instr_name_t ZBA_INSTRS[] = '{
    SH1ADD, SH2ADD, SH3ADD, SLLI, SRLI
  };

  // Zbb (basic bit manipulation)
  localparam riscv_instr_name_t ZBB_INSTRS[] = '{
    ANDN, ORN, XNOR, CLZ, CTZ, CPOP,
    MAX, MAXU, MIN, MINU,
    SEXT_B, SEXT_H, ZEXT_H,
    ROL, ROR, RORI,
    ORC_B, REV8
  };

  // Zbc (carry-less multiply)
  localparam riscv_instr_name_t ZBC_INSTRS[] = '{
    CLMUL, CLMULH, CLMULR
  };

  // Zbs (single-bit operations)
  localparam riscv_instr_name_t ZBS_INSTRS[] = '{
    BCLR, BCLRI, BEXT, BEXTI,
    BINV, BINVI, BSET, BSETI
  };

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                  bit is_debug_program = 0);
    riscv_instr instr;
    riscv_instr_name_t all_bitmanip[];
    int unsigned idx;

    // Combine all bitmanip instructions
    all_bitmanip = new[ZBA_INSTRS.size() + ZBB_INSTRS.size() +
                        ZBC_INSTRS.size() + ZBS_INSTRS.size()];
    idx = 0;
    foreach (ZBA_INSTRS[i]) all_bitmanip[idx++] = ZBA_INSTRS[i];
    foreach (ZBB_INSTRS[i]) all_bitmanip[idx++] = ZBB_INSTRS[i];
    foreach (ZBC_INSTRS[i]) all_bitmanip[idx++] = ZBC_INSTRS[i];
    foreach (ZBS_INSTRS[i]) all_bitmanip[idx++] = ZBS_INSTRS[i];

    repeat (15 + $urandom_range(20)) begin
      idx = $urandom_range(all_bitmanip.size() - 1);
      instr = riscv_instr::get_instr(all_bitmanip[idx]);
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
      if (instr.has_rs2)
        instr.rs2 = riscv_reg_t'($urandom_range(1, 31));
      instr.rd = riscv_reg_t'($urandom_range(1, 31));
      instr_list.push_back(instr);
    end
  endfunction

endclass

// ---------------------------------------------------------------------------
// PIC Interrupt CSR Stream
// Manipulates PIC-related CSRs to exercise interrupt controller
// ---------------------------------------------------------------------------
class eh2_pic_int_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_pic_int_stream)

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                  bit is_debug_program = 0);
    riscv_instr instr;

    // Enable external interrupts in MIE
    instr_list.push_back(get_li_instr(MIE, 32'h0000_0800));  // MEIE bit
    instr_list.push_back(get_csr_instr(CSRRW, MIE, 5));       // Write from t0

    // Configure MEIVT (External Interrupt Vector Table)
    instr_list.push_back(get_li_instr(12'hBC8, 32'h8000_1000));
    instr_list.push_back(get_csr_instr(CSRRW, 12'hBC8, 5));

    // Set MEIPT (threshold)
    instr_list.push_back(get_li_instr(12'hBC9, 32'h0000_0001));
    instr_list.push_back(get_csr_instr(CSRRW, 12'hBC9, 5));

    // Set MEICIDPL (claim ID priority level)
    instr_list.push_back(get_li_instr(12'hBCB, 32'h0000_000F));
    instr_list.push_back(get_csr_instr(CSRRW, 12'hBCB, 5));

    // Read MEIHAP (interrupt claim)
    instr_list.push_back(get_csr_instr(CSRRS, 12'hFC8, 5));

    // Read MEICPCT (claim and priority capture)
    instr_list.push_back(get_csr_instr(CSRRS, 12'hBCA, 5));
  endfunction

  // Helper: generate LI instruction
  function riscv_instr get_li_instr(bit [11:0] csr, bit [31:0] val);
    riscv_pseudo_instr instr;
    instr = riscv_pseudo_instr::type_id::create("li_instr");
    instr.pseudo_instr_name = LI;
    instr.rd = riscv_reg_t'(5);  // t0
    instr.imm = val;
    return instr;
  endfunction

  // Helper: generate CSR instruction
  function riscv_instr get_csr_instr(riscv_instr_name_t name, bit [11:0] csr, int gpr);
    riscv_instr instr;
    instr = riscv_instr::get_instr(name);
    instr.csr = csr;
    instr.has_rs1 = 1;
    instr.rs1 = riscv_reg_t'(gpr);
    instr.rd = riscv_reg_t'(gpr);
    return instr;
  endfunction

endclass

// ---------------------------------------------------------------------------
// Debug CSR Access Stream
// Accesses debug-mode CSRs (dcsr, dpc) - requires debug mode
// ---------------------------------------------------------------------------
class eh2_debug_csr_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_debug_csr_stream)

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                  bit is_debug_program = 0);
    riscv_instr instr;

    // Read DCSR
    instr = riscv_instr::get_instr(CSRRS);
    instr.csr = 12'h7B0;  // dcsr
    instr.has_rs1 = 1;
    instr.rs1 = ZERO;
    instr.rd = riscv_reg_t'($urandom_range(1, 31));
    instr_list.push_back(instr);

    // Read DPC
    instr = riscv_instr::get_instr(CSRRS);
    instr.csr = 12'h7B1;  // dpc
    instr.has_rs1 = 1;
    instr.rs1 = ZERO;
    instr.rd = riscv_reg_t'($urandom_range(1, 31));
    instr_list.push_back(instr);

    // Write DPC
    instr = riscv_instr::get_instr(CSRRW);
    instr.csr = 12'h7B1;  // dpc
    instr.has_rs1 = 1;
    instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
    instr.rd = riscv_reg_t'($urandom_range(1, 31));
    instr_list.push_back(instr);
  endfunction

endclass

// ---------------------------------------------------------------------------
// LR/SC Atomic Stream
// Generates load-reserve / store-conditional sequences
// ---------------------------------------------------------------------------
class eh2_atomic_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_atomic_stream)

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 0, bit no_load_store = 0,
                                  bit is_debug_program = 0);
    riscv_instr instr;
    int base_reg;

    base_reg = $urandom_range(1, 28);

    repeat (5 + $urandom_range(10)) begin
      // LR.W
      instr = riscv_instr::get_instr(LR_W);
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'(base_reg);
      instr.rd = riscv_reg_t'(base_reg + 1);
      instr_list.push_back(instr);

      // Modify value (ADDI)
      instr = riscv_instr::get_instr(ADDI);
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'(base_reg + 1);
      instr.rd = riscv_reg_t'(base_reg + 2);
      instr.imm = $urandom_range(1, 16);
      instr_list.push_back(instr);

      // SC.W
      instr = riscv_instr::get_instr(SC_W);
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'(base_reg);
      instr.has_rs2 = 1;
      instr.rs2 = riscv_reg_t'(base_reg + 2);
      instr.rd = riscv_reg_t'(base_reg + 3);
      instr_list.push_back(instr);

      // Branch if SC failed (rd != 0)
      instr = riscv_instr::get_instr(BNE);
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'(base_reg + 3);
      instr.has_rs2 = 1;
      instr.rs2 = ZERO;
      instr.imm = -3 * 4;  // Branch back to LR
      instr.branch_assigned = 1;
      instr_list.push_back(instr);
    end
  endfunction

endclass

// ---------------------------------------------------------------------------
// Breakpoint Stream
// Generates EBREAK instructions to test debug mode entry
// ---------------------------------------------------------------------------
class eh2_breakpoint_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_breakpoint_stream)

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                  bit is_debug_program = 0);
    riscv_instr instr;

    // Generate a series of EBREAK instructions
    repeat (3 + $urandom_range(5)) begin
      instr = riscv_instr::get_instr(EBREAK);
      instr_list.push_back(instr);

      // Add some NOPs between breakpoints
      repeat ($urandom_range(1, 5)) begin
        instr = riscv_instr::get_instr(NOP);
        instr_list.push_back(instr);
      end
    end
  endfunction

endclass

// ---------------------------------------------------------------------------
// Exception Stream
// Generates instructions that cause various exceptions
// ---------------------------------------------------------------------------
class eh2_exception_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_exception_stream)

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 0,
                                  bit is_debug_program = 0);
    riscv_instr instr;

    // Generate ECALL
    instr = riscv_instr::get_instr(ECALL);
    instr_list.push_back(instr);

    // Generate misaligned load (if load/store allowed)
    if (!no_load_store) begin
      instr = riscv_instr::get_instr(LW);
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
      instr.rd = riscv_reg_t'($urandom_range(1, 31));
      instr.imm = 1;  // Misaligned offset
      instr_list.push_back(instr);
    end
  endfunction

endclass

// ---------------------------------------------------------------------------
// CSR Hazard Stream
// Generates back-to-back CSR accesses to test pipeline hazards
// ---------------------------------------------------------------------------
class eh2_csr_hazard_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(eh2_csr_hazard_stream)

  localparam bit [11:0] HAZARD_CSRS[] = '{
    12'h300,  // mstatus
    12'h304,  // mie
    12'h340,  // mscratch
    12'h341,  // mepc
    12'h342,  // mcause
    12'h7C0,  // mrac
    12'h7C9   // mfdc
  };

  function new(string name = "");
    super.new(name);
  endfunction

  virtual function void gen_instr(bit no_branch = 1, bit no_load_store = 1,
                                  bit is_debug_program = 0);
    riscv_instr instr;
    int unsigned csr_idx;
    bit [11:0] csr_addr;

    // Generate back-to-back CSR read-write pairs
    repeat (8 + $urandom_range(10)) begin
      csr_idx = $urandom_range(HAZARD_CSRS.size() - 1);
      csr_addr = HAZARD_CSRS[csr_idx];

      // CSRRS (read)
      instr = riscv_instr::get_instr(CSRRS);
      instr.csr = csr_addr;
      instr.has_rs1 = 1;
      instr.rs1 = ZERO;
      instr.rd = riscv_reg_t'($urandom_range(1, 31));
      instr_list.push_back(instr);

      // CSRRW (write) - creates RAW hazard with previous read
      instr = riscv_instr::get_instr(CSRRW);
      instr.csr = csr_addr;
      instr.has_rs1 = 1;
      instr.rs1 = riscv_reg_t'($urandom_range(1, 31));
      instr.rd = riscv_reg_t'($urandom_range(1, 31));
      instr_list.push_back(instr);

      // CSRRS (read again) - creates RAW hazard with previous write
      instr = riscv_instr::get_instr(CSRRS);
      instr.csr = csr_addr;
      instr.has_rs1 = 1;
      instr.rs1 = ZERO;
      instr.rd = riscv_reg_t'($urandom_range(1, 31));
      instr_list.push_back(instr);
    end
  endfunction

endclass
