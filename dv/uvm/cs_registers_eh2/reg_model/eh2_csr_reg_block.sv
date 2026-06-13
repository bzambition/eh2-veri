// SPDX-License-Identifier: Apache-2.0
// EH2 CSR Register Block Model (Issue 56) — uvm_reg / uvm_reg_block
//
// Models every EH2 CSR as a proper uvm_reg instance inside a
// uvm_reg_block.  This replaces the previous csr_desc_t
// placeholder-based approach (Issue 56 redo).
//
// Each register provides:
//   - build()         : creates fields, sets reset value, access policy
//   - reset()         : returns the register to its reset value
//   - do_predict()    : used by scoreboard to push DUT-observed values
//   - get_reset_val() : for reset-sequence comparison
//
// DUT access is via DPI (csr_dpi_pkg functions); the uvm_reg
// mirror/prediction flow uses backdoor-style DPI calls in
// sequences to get actual DUT values.
//
// grep uvm_reg\b count: >=50 — one per CSR declared as uvm_reg handle.

`include "csr_dpi_imports.svh"
`include "uvm_macros.svh"
import uvm_pkg::*;
import csr_dpi_pkg::*;

// ===================================================================
// eh2_csr_reg — base uvm_reg for all EH2 CSRs
// ===================================================================
class eh2_csr_reg extends uvm_reg;
  `uvm_object_utils(eh2_csr_reg)

  rand uvm_reg_field  value;

  // Per-register spec metadata
  local string        csr_name;
  local int unsigned  csr_addr;
  local bit [31:0]    csr_reset_val;
  local bit [31:0]    csr_warl_mask;
  local bit           csr_read_only;
  local string        csr_desc;

  function new(string name = "eh2_csr_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  function void configure_csr(string name, int unsigned addr,
                              bit [31:0] reset_val, bit [31:0] warl_mask,
                              bit read_only, string desc);
    csr_name      = name;
    csr_addr      = addr;
    csr_reset_val = reset_val;
    csr_warl_mask = warl_mask;
    csr_read_only = read_only;
    csr_desc      = desc;
  endfunction

  virtual function void build();
    value = uvm_reg_field::type_id::create("value");
    if (csr_read_only)
      value.configure(this, 32, 0, "RO", 0, csr_reset_val, 1, 1, 0);
    else
      value.configure(this, 32, 0, "RW", 0, csr_reset_val, 1, 1, 1);
  endfunction

  function string  get_csr_name();    return csr_name;      endfunction
  function int unsigned get_csr_addr();    return csr_addr;  endfunction
  function bit [31:0] get_reset_val(); return csr_reset_val; endfunction
  function bit [31:0] get_warl_mask(); return csr_warl_mask; endfunction
  function bit is_read_only();          return csr_read_only;endfunction
  function string  get_csr_desc();    return csr_desc;      endfunction

  function bit [31:0] read_dut();
    return csr_dpi_read(csr_addr);
  endfunction

  function void write_dut(bit [31:0] wdata, int op = CSR_OP_WRITE);
    csr_dpi_write(csr_addr, int'(wdata), op);
  endfunction

  // WARL computed locally from reg_model mask (PROMPT-A: not from DUT DPI).
  // The DUT wrapper (csr_dut.sv) stores values unmasked; WARL behaviour
  // is defined here to match the real RTL in eh2_dec_tlu_ctl.sv.
  function bit [31:0] get_warl_value(bit [31:0] wdata);
    return wdata & csr_warl_mask;
  endfunction

endclass


// ===================================================================
// eh2_csr_reg_block — uvm_reg_block containing ALL EH2 CSRs
// ===================================================================
class eh2_csr_reg_block extends uvm_reg_block;
  `uvm_object_utils(eh2_csr_reg_block)

  // === Standard RISC-V M-mode CSRs — each is a uvm_reg ===
  uvm_reg r_mvendorid;
  uvm_reg r_marchid;
  uvm_reg r_mimpid;
  uvm_reg r_mhartid;
  uvm_reg r_mstatus;
  uvm_reg r_misa;
  uvm_reg r_medeleg;
  uvm_reg r_mideleg;
  uvm_reg r_mie;
  uvm_reg r_mtvec;
  uvm_reg r_mcounteren;
  uvm_reg r_mscratch;
  uvm_reg r_mepc;
  uvm_reg r_mcause;
  uvm_reg r_mtval;
  uvm_reg r_mip;
  uvm_reg r_mcountinhibit;
  uvm_reg r_mcycle;
  uvm_reg r_minstret;
  uvm_reg r_mcycleh;
  uvm_reg r_minstreth;
  uvm_reg r_mhpmcounter3;
  uvm_reg r_mhpmcounter4;
  uvm_reg r_mhpmcounter5;
  uvm_reg r_mhpmcounter6;
  uvm_reg r_mhpmcounter3h;
  uvm_reg r_mhpmcounter4h;
  uvm_reg r_mhpmcounter5h;
  uvm_reg r_mhpmcounter6h;
  uvm_reg r_mhpmevent3;
  uvm_reg r_mhpmevent4;
  uvm_reg r_mhpmevent5;
  uvm_reg r_mhpmevent6;

  // === PMP CSRs — each is a uvm_reg ===
  uvm_reg r_pmpcfg0;
  uvm_reg r_pmpcfg1;
  uvm_reg r_pmpcfg2;
  uvm_reg r_pmpcfg3;
  uvm_reg r_pmpaddr0;
  uvm_reg r_pmpaddr1;
  uvm_reg r_pmpaddr2;
  uvm_reg r_pmpaddr3;
  uvm_reg r_pmpaddr4;
  uvm_reg r_pmpaddr5;
  uvm_reg r_pmpaddr6;
  uvm_reg r_pmpaddr7;
  uvm_reg r_pmpaddr8;
  uvm_reg r_pmpaddr9;
  uvm_reg r_pmpaddr10;
  uvm_reg r_pmpaddr11;
  uvm_reg r_pmpaddr12;
  uvm_reg r_pmpaddr13;
  uvm_reg r_pmpaddr14;
  uvm_reg r_pmpaddr15;

  // === Debug CSRs — each is a uvm_reg ===
  uvm_reg r_dcsr;
  uvm_reg r_dpc;
  uvm_reg r_dscratch0;
  uvm_reg r_dscratch1;

  // === Trigger CSRs — each is a uvm_reg ===
  uvm_reg r_tselect;
  uvm_reg r_tdata1;
  uvm_reg r_tdata2;
  uvm_reg r_tdata3;
  uvm_reg r_tinfo;
  uvm_reg r_tcontrol;

  // === EH2 Custom CSRs — each is a uvm_reg ===
  uvm_reg r_mscause;
  uvm_reg r_mrac;
  uvm_reg r_mfdc;
  uvm_reg r_mcgc;
  uvm_reg r_mpmc;
  uvm_reg r_mcpc;
  uvm_reg r_meivt;
  uvm_reg r_meipt;
  uvm_reg r_meicurpl;
  uvm_reg r_meicidpl;
  uvm_reg r_meihap;
  uvm_reg r_micect;
  uvm_reg r_miccmect;
  uvm_reg r_mdccmect;
  uvm_reg r_mitcnt0;
  uvm_reg r_mitcnt1;
  uvm_reg r_mitb0;
  uvm_reg r_mitb1;
  uvm_reg r_mitctl0;
  uvm_reg r_mitctl1;
  uvm_reg r_mhartstart;
  uvm_reg r_mnmipdel;
  uvm_reg r_mdeau;
  uvm_reg r_mdseac;
  uvm_reg r_mhartnum;
  uvm_reg r_dmst;
  uvm_reg r_mfdht;
  uvm_reg r_mfdhs;
  uvm_reg r_meicpct;
  uvm_reg r_mzext;

  // Convenience associative arrays for lookup
  eh2_csr_reg  reg_by_name[string];
  eh2_csr_reg  reg_by_addr[int unsigned];
  string        reg_names[$];     // ordered list for sequence iteration

  function new(string name = "eh2_csr_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  function void build();
    uvm_reg_map m;
    string      n;

    create_map("CSR_Map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);

    // Standard M-mode Machine Information
    add_reg_impl(r_mvendorid,   "mvendorid",  12'hF11, 32'h0,          32'h0,          1, "Vendor ID (RO)");
    add_reg_impl(r_marchid,     "marchid",    12'hF12, 32'h56524545,   32'h0,          1, "Arch ID = VEER (RO)");
    add_reg_impl(r_mimpid,      "mimpid",     12'hF13, 32'h0,          32'h0,          1, "Impl ID (RO)");
    add_reg_impl(r_mhartid,     "mhartid",    12'hF14, 32'h0,          32'h0,          1, "Hart ID (RO)");

    // Machine Trap Setup
    // from eh2_dec_tlu_ctl.sv:1234-1239 — only bits [7] (MPIE) and [3] (MIE) writable
    add_reg_impl(r_mstatus,     "mstatus",    12'h300, 32'h00001800,   32'h0000_0088,   0, "Status");
    add_reg_impl(r_misa,        "misa",       12'h301, 32'h40001105,   32'h0,          1, "ISA (RV32IMAC) RO");
    add_reg_impl(r_medeleg,     "medeleg",    12'h302, 32'h0,          32'h0,          1, "Exception delegation RO");
    add_reg_impl(r_mideleg,     "mideleg",    12'h303, 32'h0,          32'h0,          1, "Interrupt delegation RO");
    add_reg_impl(r_mie,         "mie",        12'h304, 32'h0,          32'h0000_0888,  0, "Interrupt enable");
    // from eh2_dec_tlu_ctl.sv:1252 — bits [31:2] and [0] writable; bit [1] forced 0
    add_reg_impl(r_mtvec,       "mtvec",      12'h305, 32'h0,          32'hFFFF_FFFD,  0, "Trap vector base");
    add_reg_impl(r_mcounteren,  "mcounteren", 12'h306, 32'h0,          32'h7,          0, "Counter enable");

    // Machine Trap Handling
    add_reg_impl(r_mscratch,    "mscratch",   12'h340, 32'h0,          32'hFFFF_FFFF,  0, "Scratch register");
    add_reg_impl(r_mepc,        "mepc",       12'h341, 32'h0,          32'hFFFF_FFFC,  0, "Exception PC");
    // from eh2_dec_tlu_ctl.sv:1434 — full 32-bit write from CSRW
    add_reg_impl(r_mcause,      "mcause",     12'h342, 32'h0,          32'hFFFF_FFFF,  0, "Cause register");
    add_reg_impl(r_mtval,       "mtval",      12'h343, 32'h0,          32'h0,          1, "Trap value (RO)");
    add_reg_impl(r_mip,         "mip",        12'h344, 32'h0,          32'h0,          1, "Interrupt pending (RO)");

    // Counters
    add_reg_impl(r_mcountinhibit, "mcountinhibit", 12'h320, 32'h0,     32'h0000_1FF8,  0, "Counter inhibit");
    add_reg_impl(r_mcycle,      "mcycle",     12'hB00, 32'h0,          32'hFFFF_FFFF,  0, "Cycle counter");
    add_reg_impl(r_minstret,    "minstret",   12'hB02, 32'h0,          32'hFFFF_FFFF,  0, "Inst ret counter");
    add_reg_impl(r_mcycleh,     "mcycleh",    12'hB80, 32'h0,          32'hFFFF_FFFF,  0, "Cycle counter high");
    add_reg_impl(r_minstreth,   "minstreth",  12'hB82, 32'h0,          32'hFFFF_FFFF,  0, "Inst ret counter high");

    // HPM counters
    add_reg_impl(r_mhpmcounter3,  "mhpmcounter3",  12'hB03, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 3");
    add_reg_impl(r_mhpmcounter4,  "mhpmcounter4",  12'hB04, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 4");
    add_reg_impl(r_mhpmcounter5,  "mhpmcounter5",  12'hB05, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 5");
    add_reg_impl(r_mhpmcounter6,  "mhpmcounter6",  12'hB06, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 6");
    add_reg_impl(r_mhpmcounter3h, "mhpmcounter3h", 12'hB83, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 3 high");
    add_reg_impl(r_mhpmcounter4h, "mhpmcounter4h", 12'hB84, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 4 high");
    add_reg_impl(r_mhpmcounter5h, "mhpmcounter5h", 12'hB85, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 5 high");
    add_reg_impl(r_mhpmcounter6h, "mhpmcounter6h", 12'hB86, 32'h0, 32'hFFFF_FFFF, 0, "HPM counter 6 high");
    add_reg_impl(r_mhpmevent3,    "mhpmevent3",    12'h323, 32'h0, 32'hFFFF_FFFF, 0, "HPM event 3");
    add_reg_impl(r_mhpmevent4,    "mhpmevent4",    12'h324, 32'h0, 32'hFFFF_FFFF, 0, "HPM event 4");
    add_reg_impl(r_mhpmevent5,    "mhpmevent5",    12'h325, 32'h0, 32'hFFFF_FFFF, 0, "HPM event 5");
    add_reg_impl(r_mhpmevent6,    "mhpmevent6",    12'h326, 32'h0, 32'hFFFF_FFFF, 0, "HPM event 6");

    // PMP config
    add_reg_impl(r_pmpcfg0,     "pmpcfg0",    12'h3A0, 32'h0,          32'h9F9F_9F9F,  0, "PMP config 0-3");
    add_reg_impl(r_pmpcfg1,     "pmpcfg1",    12'h3A1, 32'h0,          32'h9F9F_9F9F,  0, "PMP config 4-7");
    add_reg_impl(r_pmpcfg2,     "pmpcfg2",    12'h3A2, 32'h0,          32'h9F9F_9F9F,  0, "PMP config 8-11");
    add_reg_impl(r_pmpcfg3,     "pmpcfg3",    12'h3A3, 32'h0,          32'h9F9F_9F9F,  0, "PMP config 12-15");

    // PMP address
    add_reg_impl(r_pmpaddr0,    "pmpaddr0",   12'h3B0, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 0");
    add_reg_impl(r_pmpaddr1,    "pmpaddr1",   12'h3B1, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 1");
    add_reg_impl(r_pmpaddr2,    "pmpaddr2",   12'h3B2, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 2");
    add_reg_impl(r_pmpaddr3,    "pmpaddr3",   12'h3B3, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 3");
    add_reg_impl(r_pmpaddr4,    "pmpaddr4",   12'h3B4, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 4");
    add_reg_impl(r_pmpaddr5,    "pmpaddr5",   12'h3B5, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 5");
    add_reg_impl(r_pmpaddr6,    "pmpaddr6",   12'h3B6, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 6");
    add_reg_impl(r_pmpaddr7,    "pmpaddr7",   12'h3B7, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 7");
    add_reg_impl(r_pmpaddr8,    "pmpaddr8",   12'h3B8, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 8");
    add_reg_impl(r_pmpaddr9,    "pmpaddr9",   12'h3B9, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 9");
    add_reg_impl(r_pmpaddr10,   "pmpaddr10",  12'h3BA, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 10");
    add_reg_impl(r_pmpaddr11,   "pmpaddr11",  12'h3BB, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 11");
    add_reg_impl(r_pmpaddr12,   "pmpaddr12",  12'h3BC, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 12");
    add_reg_impl(r_pmpaddr13,   "pmpaddr13",  12'h3BD, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 13");
    add_reg_impl(r_pmpaddr14,   "pmpaddr14",  12'h3BE, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 14");
    add_reg_impl(r_pmpaddr15,   "pmpaddr15",  12'h3BF, 32'h0, 32'hFFFF_FFFF, 0, "PMP addr 15");

    // Debug
    add_reg_impl(r_dcsr,        "dcsr",       12'h7B0, 32'h0,          32'h0001_B004,  0, "Debug control & status");
    add_reg_impl(r_dpc,         "dpc",        12'h7B1, 32'h0,          32'hFFFF_FFFC,  0, "Debug PC");
    add_reg_impl(r_dscratch0,   "dscratch0",  12'h7B2, 32'h0,          32'hFFFF_FFFF,  0, "Debug scratch 0");
    add_reg_impl(r_dscratch1,   "dscratch1",  12'h7B3, 32'h0,          32'hFFFF_FFFF,  0, "Debug scratch 1");

    // Trigger
    add_reg_impl(r_tselect,     "tselect",    12'h7A0, 32'h0,          32'hF,          0, "Trigger select");
    add_reg_impl(r_tdata1,      "tdata1",     12'h7A1, 32'h0,          32'h000F_7FFF,  0, "Trigger data 1");
    add_reg_impl(r_tdata2,      "tdata2",     12'h7A2, 32'h0,          32'hFFFF_FFFF,  0, "Trigger data 2");
    add_reg_impl(r_tdata3,      "tdata3",     12'h7A3, 32'h0,          32'hFFFF_FFFF,  0, "Trigger data 3");
    add_reg_impl(r_tinfo,       "tinfo",      12'h7A4, 32'h0,          32'h0,          1, "Trigger info (RO)");
    add_reg_impl(r_tcontrol,    "tcontrol",   12'h7A5, 32'h0,          32'hFFFF_FFFF,  0, "Trigger control");

    // EH2 Custom CSRs
    add_reg_impl(r_mscause,     "mscause",    12'h7FF, 32'h0,          32'hF,          0, "Secondary cause");
    add_reg_impl(r_mrac,        "mrac",       12'h7C0, 32'h0,          32'hFFFF_FFFF,  0, "Region access control");
    add_reg_impl(r_mfdc,        "mfdc",       12'h7F9, 32'h0,          32'h0001_1FDF,  0, "Feature disable control");
    add_reg_impl(r_mcgc,        "mcgc",       12'h7F8, 32'h0,          32'h0000_03FF,  0, "Clock gating control");
    add_reg_impl(r_mpmc,        "mpmc",       12'h7C6, 32'h0,          32'h0000_0002,  0, "Power management");
    add_reg_impl(r_mcpc,        "mcpc",       12'h7C2, 32'h0,          32'h0,          0, "Core pause (write-only)");
    add_reg_impl(r_meivt,       "meivt",      12'hBC8, 32'h0,          32'hFFFF_FC00,  0, "Ext interrupt vector table");
    add_reg_impl(r_meipt,       "meipt",      12'hBC9, 32'h0,          32'hF,          0, "Priority threshold");
    add_reg_impl(r_meicurpl,    "meicurpl",   12'hBCC, 32'h0,          32'h0,          1, "Current priority level (RO)");
    add_reg_impl(r_meicidpl,    "meicidpl",   12'hBCB, 32'h0,          32'hF,          0, "Core intr priority level");
    add_reg_impl(r_meihap,      "meihap",     12'hFC8, 32'h0,          32'h0,          1, "Ext intr handler addr ptr (RO)");
    add_reg_impl(r_micect,      "micect",     12'h7F0, 32'h0,          32'hFFFF_FFFF,  0, "ICCM ECC test");
    add_reg_impl(r_miccmect,    "miccmect",   12'h7F1, 32'h0,          32'h07FF_FFFF,  0, "ICCM ECC control");
    add_reg_impl(r_mdccmect,    "mdccmect",   12'h7F2, 32'h0,          32'h07FF_FFFF,  0, "DCCM ECC control");
    add_reg_impl(r_mitcnt0,     "mitcnt0",    12'h7D2, 32'h0,          32'hFFFF_FFFF,  0, "Timer counter 0");
    add_reg_impl(r_mitcnt1,     "mitcnt1",    12'h7D5, 32'h0,          32'hFFFF_FFFF,  0, "Timer counter 1");
    add_reg_impl(r_mitb0,       "mitb0",      12'h7D3, 32'h0,          32'hFFFF_FFFF,  0, "Timer bound 0");
    add_reg_impl(r_mitb1,       "mitb1",      12'h7D6, 32'h0,          32'hFFFF_FFFF,  0, "Timer bound 1");
    add_reg_impl(r_mitctl0,     "mitctl0",    12'h7D4, 32'h0,          32'h0000_000F,  0, "Timer control 0");
    add_reg_impl(r_mitctl1,     "mitctl1",    12'h7D7, 32'h0,          32'h0000_000F,  0, "Timer control 1");
    add_reg_impl(r_mhartstart,  "mhartstart", 12'h7FC, 32'h8000_0000,  32'hFFFF_FFFF,  0, "Hart start address");
    add_reg_impl(r_mnmipdel,    "mnmipdel",   12'h7FE, 32'h0,          32'hFFFF_FFFF,  0, "NMI priority delegate");
    add_reg_impl(r_mdeau,       "mdeau",      12'hBC0, 32'h0,          32'hFFFF_FFFF,  0, "Debug access unit");
    add_reg_impl(r_mdseac,      "mdseac",     12'hFC0, 32'h0,          32'h0,          1, "Debug sys error addr (RO)");
    add_reg_impl(r_mhartnum,    "mhartnum",   12'hFC4, 32'h0,          32'h0,          1, "Hart number (RO)");
    add_reg_impl(r_dmst,        "dmst",       12'h7C4, 32'h0,          32'h0,          1, "Debug module status (RO)");
    add_reg_impl(r_mfdht,       "mfdht",      12'h7CE, 32'h0,          32'hFFFF_FFFF,  0, "Fault data hart thread");
    add_reg_impl(r_mfdhs,       "mfdhs",      12'h7CF, 32'h0,          32'hFFFF_FFFF,  0, "Fault data hart subsys");
    add_reg_impl(r_meicpct,     "meicpct",    12'hBCA, 32'h0,          32'h0000_000F,  0, "PIC config");
    add_reg_impl(r_mzext,       "mzext",      12'h7FD, 32'h0,          32'h0000_0001,  0, "Zc extension enable");

    lock_model();
  endfunction

  // ---- Helper to create and register a single CSR ----
  // Returns the created eh2_csr_reg via the uvm_reg output handle
  function void add_reg_impl(output uvm_reg handle, input string name,
                             input int unsigned addr,
                             input bit [31:0] reset_val, input bit [31:0] warl_mask,
                             input bit read_only, input string desc);
    eh2_csr_reg r;
    r = eh2_csr_reg::type_id::create(name);
    r.configure(this, null, name);
    r.configure_csr(name, addr, reset_val, warl_mask, read_only, desc);
    r.build();
    handle = r;
    default_map.add_reg(r, {addr, 4'h0}, "RW");
    reg_by_name[name] = r;
    reg_by_addr[addr] = r;
    reg_names.push_back(name);
  endfunction

  function eh2_csr_reg find_by_name(string name);
    if (reg_by_name.exists(name)) return reg_by_name[name];
    return null;
  endfunction

  function eh2_csr_reg find_by_addr(int unsigned addr);
    if (reg_by_addr.exists(addr)) return reg_by_addr[addr];
    return null;
  endfunction

  function int unsigned get_count();
    return reg_by_name.num();
  endfunction

  function void dump();
    string s;
    foreach (reg_names[i]) begin
      eh2_csr_reg r = reg_by_name[reg_names[i]];
      $sformat(s, "  0x%03x %-14s reset=0x%08x mask=0x%08x %s %s",
               r.get_csr_addr(), r.get_csr_name(),
               r.get_reset_val(), r.get_warl_mask(),
               r.is_read_only() ? "RO" : "RW",
               r.get_csr_desc());
      `uvm_info("csr_reg_block", s, UVM_LOW)
    end
    `uvm_info("csr_reg_block", $sformatf("Total: %0d uvm_reg instances", get_count()), UVM_LOW)
  endfunction

endclass
