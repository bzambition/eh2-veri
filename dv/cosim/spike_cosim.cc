// SPDX-License-Identifier: Apache-2.0
// EH2 Spike Co-simulation Implementation
//
// Based on Ibex's spike_cosim.cc, adapted for VeeR EH2.
// Implements instruction-by-instruction comparison between DUT and Spike.

#include "spike_cosim.h"

#include <cassert>
#include <iostream>
#include <set>
#include <sstream>

#include "riscv/config.h"
#include "riscv/csrs.h"
#include "riscv/decode.h"
#include "riscv/devices.h"
#include "riscv/log_file.h"
#include "riscv/mmu.h"
#include "riscv/processor.h"
#include "riscv/simif.h"

SpikeCosim::SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                       uint32_t start_mtvec, const std::string &trace_log_path,
                       uint32_t pmp_num_regions, uint32_t pmp_granularity,
                       uint32_t mhpm_counter_num)
    : nmi_mode(false), pending_iside_error(false), insn_cnt(0) {
  FILE *log_file = nullptr;
  if (trace_log_path.length() != 0) {
    log = std::make_unique<log_file_t>(trace_log_path.c_str());
    log_file = log->get();
  }

  isa_parser = std::make_unique<isa_parser_t>(isa_string.c_str(), "MU");
  processor = std::make_unique<processor_t>(
      isa_parser.get(), DEFAULT_VARCH, this, 0, false, log_file, std::cerr);

  processor->set_pmp_num(pmp_num_regions);
  processor->set_mhpm_counter_num(mhpm_counter_num);
  processor->set_pmp_granularity(1 << (pmp_granularity + 2));

  initial_proc_setup(start_pc, start_mtvec, mhpm_counter_num);

  if (log) {
    processor->set_debug(true);
    processor->enable_log_commits();
  }
}

// Always return nullptr so all memory accesses go via mmio_load/mmio_store
char *SpikeCosim::addr_to_mem(reg_t addr) { return nullptr; }

bool SpikeCosim::mmio_load(reg_t addr, size_t len, uint8_t *bytes) {
  // Reject oversized accesses (e.g. from mem_t initialization) without DUT checking
  if (len > 8) {
    return bus.load(addr, len, bytes);
  }

  bool bus_error = !bus.load(addr, len, bytes);

  bool dut_error = false;

  // Incoming access may be an iside or dside access. Use PC to help determine
  // which. PC is 64 bits in spike, we only care about the bottom 32-bit so mask
  // off the top bits.
  uint64_t pc = processor->get_state()->pc & 0xffffffff;
  uint32_t aligned_addr = addr & 0xfffffffc;

  if (pending_iside_error && (aligned_addr == pending_iside_err_addr)) {
    // Check if the incoming access is subject to an iside error, in which case
    // assume it's an iside access and produce an error.
    pending_iside_error = false;
    dut_error = true;
  } else {
    // Spike may attempt to access up to 8-bytes from the PC when fetching, so
    // only check as a dside access when it falls outside that range
    bool in_iside_range = (addr >= pc && addr < pc + 8);

    if (!in_iside_range) {
      dut_error = (check_mem_access(false, addr, len, bytes) != kCheckMemOk);
    }
  }

  return !(bus_error || dut_error);
}

bool SpikeCosim::mmio_store(reg_t addr, size_t len, const uint8_t *bytes) {
  // Reject oversized accesses (e.g. from mem_t initialization) without DUT checking
  if (len > 8) {
    return bus.store(addr, len, bytes);
  }

  bool bus_error = !bus.store(addr, len, bytes);
  // If the RTL produced a bus error for the access, or the checking failed
  // produce a memory fault in spike.
  bool dut_error = (check_mem_access(true, addr, len, bytes) != kCheckMemOk);

  return !(bus_error || dut_error);
}

void SpikeCosim::proc_reset(unsigned id) {}

const char *SpikeCosim::get_symbol(uint64_t addr) { return nullptr; }

void SpikeCosim::add_memory(uint32_t base_addr, size_t size) {
  auto new_mem = std::make_unique<mem_t>(size);
  bus.add_device(base_addr, new_mem.get());
  mems.emplace_back(std::move(new_mem));
}

bool SpikeCosim::backdoor_write_mem(uint32_t addr, size_t len,
                                    const uint8_t *data_in) {
  return bus.store(addr, len, data_in);
}

bool SpikeCosim::backdoor_read_mem(uint32_t addr, size_t len,
                                   uint8_t *data_out) {
  return bus.load(addr, len, data_out);
}

// ---------------------------------------------------------------
// Instruction decoding helpers
// ---------------------------------------------------------------

bool SpikeCosim::pc_is_mret(uint32_t pc) {
  uint32_t insn;
  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn))) {
    return false;
  }
  return insn == 0x30200073;
}

bool SpikeCosim::pc_is_debug_ebreak(uint32_t pc) {
  uint32_t dcsr = processor->get_csr(CSR_DCSR);

  // ebreak debug entry is controlled by ebreakm (bit 15) and ebreaku (bit 12).
  // If the appropriate bit of the current privilege level isn't set, ebreak
  // won't enter debug mode so return false.
  if (((processor->get_state()->prv == PRV_M) && ((dcsr & 0x1000) == 0)) ||
      ((processor->get_state()->prv == PRV_U) && ((dcsr & 0x8000) == 0))) {
    return false;
  }

  // Check for 16-bit c.ebreak
  uint16_t insn_16;
  if (!backdoor_read_mem(pc, 2, reinterpret_cast<uint8_t *>(&insn_16))) {
    return false;
  }
  if (insn_16 == 0x9002) {
    return true;
  }

  // Check for 32-bit ebreak
  uint32_t insn_32;
  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn_32))) {
    return false;
  }
  return insn_32 == 0x00100073;
}

void SpikeCosim::check_debug_ebreak(uint32_t write_reg, uint32_t pc,
                                    bool sync_trap) {
  // A debug ebreak from the DUT should not write a register and will be
  // reported as a 'sync_trap' (though doesn't act like a trap in various
  // respects).
  if (write_reg != 0) {
    std::stringstream err_str;
    err_str << "DUT executed ebreak at " << std::hex << pc
            << " but also wrote register x" << std::dec << write_reg
            << " which was unexpected";
    errors.emplace_back(err_str.str());
  }

  if (sync_trap) {
    std::stringstream err_str;
    err_str << "DUT executed ebreak into debug at " << std::hex << pc
            << " but indicated a synchronous trap, which was unexpected";
    errors.emplace_back(err_str.str());
  }
}

bool SpikeCosim::pc_is_load(uint32_t pc) {
  uint16_t insn_16;
  if (!backdoor_read_mem(pc, 2, reinterpret_cast<uint8_t *>(&insn_16))) {
    return false;
  }

  // C.LW (compressed load, register-relative)
  if ((insn_16 & 0xE003) == 0x4000) {
    return true;
  }

  // C.LWSP (compressed load, stack pointer relative)
  if ((insn_16 & 0xE003) == 0x4002) {
    uint32_t rd = (insn_16 >> 7) & 0x1F;
    return rd != 0;  // C.LWSP with rd=0 is reserved
  }

  // Check 32-bit loads: LB/LH/LW/LBU/LHU
  uint32_t insn_32;
  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn_32))) {
    return false;
  }

  if ((insn_32 & 0x7F) == 0x03) {
    uint32_t func3 = (insn_32 >> 12) & 0x7;
    // func3 = 0x3, 0x6, 0x7 are not valid load encodings
    if (func3 == 0x3 || func3 == 0x6 || func3 == 0x7) {
      return false;
    }
    return true;
  }

  return false;
}

bool SpikeCosim::pc_is_div_or_rem(uint32_t pc) {
  uint32_t insn_32;
  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn_32))) {
    return false;
  }

  if ((insn_32 & 0x7F) != 0x33) {
    return false;
  }

  uint32_t funct3 = (insn_32 >> 12) & 0x7;
  uint32_t funct7 = (insn_32 >> 25) & 0x7F;

  return funct7 == 0x01 && funct3 >= 0x4 && funct3 <= 0x7;
}

// ---------------------------------------------------------------
// Interrupt/debug handling
// ---------------------------------------------------------------

void SpikeCosim::early_interrupt_handle() {
  // Execute a spike step on the assumption an interrupt will occur so no new
  // instruction is executed just the state altered to reflect the interrupt.
  uint32_t initial_spike_pc = (processor->get_state()->pc & 0xffffffff);
  processor->step(1);

  if (processor->get_state()->last_inst_pc != PC_INVALID) {
    std::stringstream err_str;
    err_str << "Attempted step for interrupt, expecting no instruction would "
            << "be executed but saw one. PC before: " << std::hex
            << initial_spike_pc
            << " PC after: " << (processor->get_state()->pc & 0xffffffff);
    errors.emplace_back(err_str.str());
  }
}

// ---------------------------------------------------------------
// step() - Core comparison logic
// ---------------------------------------------------------------

bool SpikeCosim::step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
                      bool sync_trap, bool suppress_reg_write) {
  assert(write_reg < 32);

  // First check if this is an ebreak that should enter debug mode. These need
  // specific handling. When spike steps over an ebreak entering debug mode it
  // immediately steps the next instruction (first instruction of debug handler)
  // too. To deal with this, skip the rest of the function for debug ebreaks.
  if (pc_is_debug_ebreak(pc)) {
    check_debug_ebreak(write_reg, pc, sync_trap);
    return errors.size() == 0;
  }

  uint32_t initial_spike_pc;
  uint32_t suppressed_write_reg;
  uint32_t suppressed_write_reg_data;
  bool pending_sync_exception = false;

  if (suppress_reg_write) {
    if (!check_suppress_reg_write(write_reg, pc, suppressed_write_reg)) {
      return false;
    }
    suppressed_write_reg_data =
        processor->get_state()->XPR[suppressed_write_reg];
  }

  // Record current spike PC before stepping
  initial_spike_pc = (processor->get_state()->pc & 0xffffffff);
  try {
    processor->step(1);
  } catch (const std::exception &e) {
    std::stringstream err_str;
    err_str << "Spike step exception at PC " << std::hex << initial_spike_pc
            << ": " << e.what();
    errors.emplace_back(err_str.str());
    return false;
  } catch (...) {
    std::stringstream err_str;
    err_str << "Spike unknown step exception at PC " << std::hex << initial_spike_pc;
    errors.emplace_back(err_str.str());
    return false;
  }

  if (processor->get_state()->last_inst_pc == PC_INVALID) {
    if (!(processor->get_state()->mcause->read() & 0x80000000) ||
        processor->get_state()->debug_mode) {
      // Synchronous trap
      pending_sync_exception = true;
    } else {
      // Asynchronous trap - step to first instruction of ISR
      initial_spike_pc = (processor->get_state()->pc & 0xffffffff);
      try {
        processor->step(1);
      } catch (const std::exception &e) {
        std::stringstream err_str;
        err_str << "Spike ISR step exception at PC " << std::hex << initial_spike_pc
                << ": " << e.what();
        errors.emplace_back(err_str.str());
        return false;
      }

      if (processor->get_state()->last_inst_pc == PC_INVALID) {
        pending_sync_exception = true;
      }
    }

    if (pending_sync_exception) {
      if (!sync_trap) {
        std::stringstream err_str;
        err_str << "Synchronous trap was expected at ISS PC: " << std::hex
                << processor->get_state()->pc
                << " but the DUT didn't report one at PC " << pc;
        errors.emplace_back(err_str.str());
        return false;
      }

      if (!check_sync_trap(write_reg, pc, initial_spike_pc)) {
        return false;
      }

      return true;
    }
  }

  // We reached a retired instruction

  // Check for mret - handle NMI mode exit
  if (!sync_trap && pc_is_mret(pc)) {
    if (nmi_mode) {
      leave_nmi_mode();
    }
  }

  // Check for unconsumed iside error
  if (pending_iside_error) {
    std::stringstream err_str;
    err_str << "DUT generated an iside error for address: " << std::hex
            << pending_iside_err_addr << " but the ISS didn't produce one";
    errors.emplace_back(err_str.str());
    pending_iside_error = false;
    return false;
  }

  if (suppress_reg_write) {
    processor->get_state()->XPR.write(suppressed_write_reg,
                                      suppressed_write_reg_data);
  }

  if (!check_retired_instr(write_reg, write_reg_data, pc, suppress_reg_write)) {
    return false;
  }

  // Check for errors generated outside of step() (e.g. in check_mem_access())
  if (errors.size() != 0) {
    return false;
  }

  insn_cnt++;
  return true;
}

bool SpikeCosim::check_retired_instr(uint32_t write_reg,
                                     uint32_t write_reg_data, uint32_t dut_pc,
                                     bool suppress_reg_write) {
  // Check PC matches
  if ((processor->get_state()->last_inst_pc & 0xffffffff) != dut_pc) {
    std::stringstream err_str;
    err_str << "PC mismatch, DUT retired : " << std::hex << dut_pc
            << " , but the ISS retired: " << std::hex
            << (processor->get_state()->last_inst_pc & 0xffffffff);
    errors.emplace_back(err_str.str());
    return false;
  }

  // Check register writes match
  auto &reg_changes = processor->get_state()->log_reg_write;

  bool gpr_write_seen = false;

  for (auto reg_change : reg_changes) {
    // Ignore writes to x0
    if (reg_change.first == 0)
      continue;

    if ((reg_change.first & 0xf) == 0) {
      // GPR write
      assert(!gpr_write_seen);

      if (!suppress_reg_write &&
          !check_gpr_write(reg_change, write_reg, write_reg_data)) {
        return false;
      }

      gpr_write_seen = true;
    } else if ((reg_change.first & 0xf) == 4) {
      // CSR write
      on_csr_write(reg_change);
    } else {
      assert(false);
    }
  }

  if (write_reg != 0 && !gpr_write_seen) {
    std::stringstream err_str;
    err_str << "DUT wrote register x" << write_reg
            << " but a write was not expected" << std::endl;
    errors.emplace_back(err_str.str());
    return false;
  }

  if (errors.size() != 0) {
    return false;
  }

  return true;
}

bool SpikeCosim::check_sync_trap(uint32_t write_reg, uint32_t dut_pc,
                                 uint32_t initial_spike_pc) {
  if (initial_spike_pc != dut_pc) {
    std::stringstream err_str;
    err_str << "PC mismatch at synchronous trap, DUT at pc: " << std::hex
            << dut_pc << "while ISS pc is at : " << std::hex
            << initial_spike_pc;
    errors.emplace_back(err_str.str());
    return false;
  }

  if (write_reg != 0) {
    std::stringstream err_str;
    err_str << "Synchronous trap occurred at PC: " << std::hex << dut_pc
            << "but DUT wrote to register: x" << std::dec << write_reg;
    errors.emplace_back(err_str.str());
    return false;
  }

  // Handle load/store access fault - apply fixup for misaligned accesses
  if ((processor->get_state()->mcause->read() == 0x5) ||
      (processor->get_state()->mcause->read() == 0x7)) {
    misaligned_pmp_fixup(0, false);
  }

  // Handle internal NMI cause
  if (processor->get_state()->mcause->read() == 0xFFFFFFE0) {
    if (pending_dside_accesses.size() > 0) {
      pending_dside_accesses.erase(pending_dside_accesses.begin());
    }
  }

  if (errors.size() != 0) {
    return false;
  }

  return true;
}

bool SpikeCosim::check_gpr_write(const commit_log_reg_t::value_type &reg_change,
                                 uint32_t write_reg, uint32_t write_reg_data) {
  uint32_t cosim_write_reg = (reg_change.first >> 4) & 0x1f;

  if (write_reg == 0) {
    std::stringstream err_str;
    err_str << "DUT didn't write to register x" << cosim_write_reg
            << ", but a write was expected";
    errors.emplace_back(err_str.str());
    return false;
  }

  if (write_reg != cosim_write_reg) {
    std::stringstream err_str;
    err_str << "Register write index mismatch, DUT: x" << write_reg
            << " expected: x" << cosim_write_reg;
    errors.emplace_back(err_str.str());
    return false;
  }

  uint32_t cosim_write_reg_data = reg_change.second.v[0];

  if (write_reg_data != cosim_write_reg_data) {
    std::stringstream err_str;
    err_str << "Register write data mismatch to x" << cosim_write_reg
            << " DUT: " << std::hex << write_reg_data
            << " expected: " << cosim_write_reg_data;
    errors.emplace_back(err_str.str());
    return false;
  }

  return true;
}

bool SpikeCosim::check_suppress_reg_write(uint32_t write_reg, uint32_t pc,
                                          uint32_t &suppressed_write_reg) {
  if (write_reg != 0) {
    std::stringstream err_str;
    err_str << "Instruction at " << std::hex << pc
            << " indicated a suppressed register write but wrote to x"
            << std::dec << write_reg;
    errors.emplace_back(err_str.str());
    return false;
  }

  // EH2 can suppress killed loads and canceled non-blocking DIV/REM writes.
  if (!pc_is_load(pc) && !pc_is_div_or_rem(pc)) {
    std::stringstream err_str;
    err_str << "Instruction at " << std::hex << pc
            << " indicated a suppressed register write but is not a load/div";
    errors.emplace_back(err_str.str());
    return false;
  }

  // Decode the destination register from the instruction
  uint16_t insn_16;
  if (backdoor_read_mem(pc, 2, reinterpret_cast<uint8_t *>(&insn_16))) {
    // C.LW
    if ((insn_16 & 0xE003) == 0x4000) {
      suppressed_write_reg = ((insn_16 >> 2) & 0x7) + 8;
      return true;
    }
    // C.LWSP
    if ((insn_16 & 0xE003) == 0x4002) {
      suppressed_write_reg = (insn_16 >> 7) & 0x1F;
      return true;
    }
  }

  // 32-bit load
  uint32_t insn_32;
  if (backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn_32))) {
    suppressed_write_reg = (insn_32 >> 7) & 0x1F;
    return true;
  }

  return false;
}

void SpikeCosim::on_csr_write(const commit_log_reg_t::value_type &reg_change) {
  int cosim_write_csr = (reg_change.first >> 4) & 0xfff;
  uint32_t cosim_write_csr_data = reg_change.second.v[0];

  // Spike and EH2 have different WARL behaviours so after any CSR write
  // check the fields and adjust to match EH2 behaviour.
  fixup_csr(cosim_write_csr, cosim_write_csr_data);
}

void SpikeCosim::leave_nmi_mode() {
  nmi_mode = false;

  // Restore CSR status from mstack
  uint32_t mstatus = processor->get_csr(CSR_MSTATUS);
  mstatus = set_field(mstatus, MSTATUS_MPP, mstack.mpp);
  mstatus = set_field(mstatus, MSTATUS_MPIE, mstack.mpie);
  processor->put_csr(CSR_MSTATUS, mstatus);

  processor->put_csr(CSR_MEPC, mstack.epc);
  processor->put_csr(CSR_MCAUSE, mstack.cause);
}

void SpikeCosim::initial_proc_setup(uint32_t start_pc, uint32_t start_mtvec,
                                    uint32_t mhpm_counter_num) {
  processor->get_state()->pc = start_pc;
  processor->get_state()->mtvec->write(start_mtvec);

  // Set EH2 marchid
  processor->get_state()->csrmap[CSR_MARCHID] =
      std::make_shared<const_csr_t>(processor.get(), CSR_MARCHID, EH2_MARCHID);

  processor->set_mmu_capability(IMPL_MMU_SBARE);

  // Configure trigger modules
  for (int i = 0; i < processor->TM.count(); ++i) {
    processor->TM.tdata2_write(processor.get(), i, 0);
    processor->TM.tdata1_write(processor.get(), i, 0x28001048);
  }

  // Configure MHPM counters
  for (int i = 0; i < mhpm_counter_num; i++) {
    processor->get_state()->csrmap[CSR_MHPMEVENT3 + i] =
        std::make_shared<const_csr_t>(processor.get(), CSR_MHPMEVENT3 + i,
                                      1 << i);
  }

  // Initialize EH2 custom CSRs in csrmap so they can be read/written
  // These are WD/Microchip extensions not natively supported by Spike
  static const int eh2_init_csrs[] = {
    0x7FF,  // mscause
    0x7C0,  // mrac
    0x7F9,  // mfdc
    0x7F8,  // mcgc
    0x7C6,  // mpmc
    0x7C2,  // mcpc
    0x7C4,  // dmst
    0x7CE,  // mfdht
    0x7CF,  // mfdhs
    0x7FC,  // mhartstart
    0x7FE,  // mnmipdel
    0x7D2,  // mitcnt0
    0x7D5,  // mitcnt1
    0x7D3,  // mitb0
    0x7D6,  // mitb1
    0x7D4,  // mitctl0
    0x7D7,  // mitctl1
    0xBC0,  // mdeau
    0xFC0,  // mdseac
    0x7F0,  // micect
    0x7F1,  // miccmect
    0x7F2,  // mdccmect
    0xBC8,  // meivt
    0xFC8,  // meihap
    0xBC9,  // meipt
    0xBCA,  // meicpct
    0xBCC,  // meicurpl
    0xBCB,  // meicidpl
    0xFC4,  // mhartnum
  };

  for (int csr : eh2_init_csrs) {
    if (processor->get_state()->csrmap.find(csr) ==
        processor->get_state()->csrmap.end()) {
      processor->get_state()->csrmap[csr] =
          std::make_shared<basic_csr_t>(processor.get(), csr, 0);
    }
  }
}

// ---------------------------------------------------------------
// set_mip() - Aligned with Ibex: delegate to Spike's interrupt logic
// ---------------------------------------------------------------

void SpikeCosim::set_mip(uint32_t pre_mip, uint32_t post_mip) {
  uint32_t old_mip = processor->get_state()->mip->read();

  processor->get_state()->mip->write_with_mask(0xffffffff, post_mip);
  processor->get_state()->mip->write_pre_val(pre_mip);

  if (processor->get_state()->debug_mode ||
      (processor->halt_request == processor_t::HR_REGULAR) ||
      (!get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MIE) &&
       processor->get_state()->prv == PRV_M)) {
    return;
  }

  uint32_t old_enabled_irq = old_mip & processor->get_state()->mie->read();
  uint32_t new_enabled_irq = pre_mip & processor->get_state()->mie->read();

  // Trigger interrupt handling if new MIP produces an enabled interrupt for
  // the first time. Use pre_mip (the MIP value at the start of the instruction)
  // to determine if an interrupt should be taken, matching Ibex behavior.
  if ((old_enabled_irq == 0) && (new_enabled_irq != 0)) {
    early_interrupt_handle();
  }
}

// ---------------------------------------------------------------
// set_nmi() - Aligned with Ibex: use Spike's native NMI mechanism
// ---------------------------------------------------------------

void SpikeCosim::set_nmi(bool nmi) {
  if (nmi && !nmi_mode && !processor->get_state()->debug_mode &&
      processor->halt_request != processor_t::HR_REGULAR) {
    processor->get_state()->nmi = true;
    nmi_mode = true;

    // Save CSR state for recoverable NMI to mstack
    mstack.mpp = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPP);
    mstack.mpie = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPIE);
    mstack.epc = processor->get_csr(CSR_MEPC);
    mstack.cause = processor->get_csr(CSR_MCAUSE);

    early_interrupt_handle();
  }
}

// ---------------------------------------------------------------
// set_nmi_int() - Sets nmi_int (distinct from nmi in Spike)
// ---------------------------------------------------------------

void SpikeCosim::set_nmi_int(bool nmi_int) {
  if (nmi_int && !nmi_mode && !processor->get_state()->debug_mode &&
      processor->halt_request != processor_t::HR_REGULAR) {
    processor->get_state()->nmi_int = true;
    nmi_mode = true;

    // Save CSR state for recoverable NMI to mstack
    mstack.mpp = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPP);
    mstack.mpie = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPIE);
    mstack.epc = processor->get_csr(CSR_MEPC);
    mstack.cause = processor->get_csr(CSR_MCAUSE);

    early_interrupt_handle();
  }
}

// ---------------------------------------------------------------
// set_debug_req() - Can both set and clear halt request
// ---------------------------------------------------------------

void SpikeCosim::set_debug_req(bool debug_req) {
  processor->halt_request =
      debug_req ? processor_t::HR_REGULAR : processor_t::HR_NONE;
}

// ---------------------------------------------------------------
// set_mcycle() - Consume DUT mcycle samples without touching Spike CSR state
// ---------------------------------------------------------------

void SpikeCosim::set_mcycle(uint64_t mcycle) {
  // EH2 samples mcycle every retired instruction to keep the same DPI
  // ordering as Ibex. This Spike build has no public no-log backdoor for
  // mcycle; writing CSR_MCYCLE/CSR_MCYCLEH from this DPI callback can enter
  // commit-log CSR side paths and crash VCS before step() performs the actual
  // architectural comparison. Treat the sample as ordering metadata and leave
  // Spike's architectural counter updates on the instruction execution path.
  (void)mcycle;
}

void SpikeCosim::set_csr(const int csr_num, const uint32_t new_val) {
  processor->put_csr(csr_num, new_val);
}

void SpikeCosim::notify_dside_access(const DSideAccessInfo &access_info) {
  assert((access_info.addr & 0x3) == 0);

  PendingMemAccess pending_access;
  pending_access.dut_access_info = access_info;
  pending_access.be_spike = 0;
  pending_dside_accesses.push_back(pending_access);
}

bool SpikeCosim::is_widened_load_pair(size_t first_idx) const {
  if (first_idx + 1 >= pending_dside_accesses.size()) {
    return false;
  }

  const auto &first = pending_dside_accesses[first_idx].dut_access_info;
  const auto &second = pending_dside_accesses[first_idx + 1].dut_access_info;

  return !first.store && !second.store &&
         first.widened_load && second.widened_load &&
         !first.misaligned_first && !first.misaligned_second &&
         !second.misaligned_first && !second.misaligned_second &&
         first.be == 0xf && second.be == 0xf &&
         second.addr == first.addr + 4 &&
         first.error == second.error;
}

void SpikeCosim::set_iside_error(uint32_t addr) {
  assert((addr & 0x3) == 0);
  pending_iside_error = true;
  pending_iside_err_addr = addr & 0xfffffffc;
}

const std::vector<std::string> &SpikeCosim::get_errors() { return errors; }

void SpikeCosim::clear_errors() { errors.clear(); }

unsigned int SpikeCosim::get_insn_cnt() { return insn_cnt; }

// ---------------------------------------------------------------
// fixup_csr() - WARL fixup for EH2
// ---------------------------------------------------------------

// Misaligned PMP fixup stub - to be implemented if EH2 PMP support is needed
// When PMP is enabled, misaligned accesses that cross PMP region boundaries
// may need special handling to match EH2's behavior.
void SpikeCosim::misaligned_pmp_fixup(uint32_t addr, bool store) {
  // Stub: EH2 currently configured with 0 PMP regions
  // If PMP is enabled, implement region boundary checking here
}

void SpikeCosim::fixup_csr(int csr_num, uint32_t csr_val) {
  switch (csr_num) {
    case CSR_MSTATUS: {
      // EH2 mstatus: only M-mode, no S/U mode bits
      uint32_t mask = MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP |
                      MSTATUS_MPRV | MSTATUS_TW | MSTATUS_FS;
      reg_t new_val = csr_val & mask;
      new_val = set_field(new_val, MSTATUS_MPP, PRV_M);
      processor->put_csr(csr_num, new_val);
      break;
    }
    case CSR_MISA: {
      // EH2 misa: RV32IMAC hardwired
      reg_t new_val = 0x40001104;  // RV32IMAC
      processor->put_csr(csr_num, new_val);
      break;
    }
    case CSR_MTVEC: {
      // EH2 mtvec: MODE must be 0 (direct), BASE 256-byte aligned
      uint32_t mtvec_and_mask = 0xFFFFFF00;
      reg_t new_val = csr_val & mtvec_and_mask;
      processor->put_csr(csr_num, new_val);
      break;
    }
    case CSR_MCAUSE: {
      // WARL fixup for mcause
      // Handle internal NMI cause encoding (0xFFFFFFE0)
      uint32_t any_interrupt = csr_val & 0x80000000;
      uint32_t int_interrupt = csr_val & 0x40000000;
      reg_t new_val = (csr_val & 0x0000001f) | any_interrupt;
      if (any_interrupt && int_interrupt) {
        new_val |= 0x7fffffe0;
      }
      processor->put_csr(csr_num, new_val);
      break;
    }
    // ---------------------------------------------------------------
    // EH2 Custom CSRs - WD/Microchip extensions
    // Spike doesn't natively support these, so we add them to csrmap
    // as simple read/write registers to avoid mismatch.
    // ---------------------------------------------------------------
    default: {
      // Check if this is an EH2 custom CSR that needs to be added to csrmap
      static const std::set<int> eh2_custom_csrs = {
        0x7FF,  // mscause - secondary cause (read-only in HW, but we track it)
        0x7C0,  // mrac - region access control
        0x7F9,  // mfdc - feature disable control
        0x7F8,  // mcgc - clock gating control
        0x7C6,  // mpmc - power management
        0x7C2,  // mcpc - core pause control
        0x7C4,  // dmst - debug memory stall
        0x7CE,  // mfdht - dual-thread feature disable high
        0x7CF,  // mfdhs - dual-thread feature disable low
        0x7FC,  // mhartstart - hart start
        0x7FE,  // mnmipdel - NMI pulse delay
        0x7D2,  // mitcnt0 - internal timer count 0
        0x7D5,  // mitcnt1 - internal timer count 1
        0x7D3,  // mitb0 - internal timer bound 0
        0x7D6,  // mitb1 - internal timer bound 1
        0x7D4,  // mitctl0 - internal timer control 0
        0x7D7,  // mitctl1 - internal timer control 1
        0xBC0,  // mdeau - ECC async error
        0xFC0,  // mdseac - ECC sync error address
        0x7F0,  // micect - ICCM error count
        0x7F1,  // miccmect - ICCM multi-bit error count
        0x7F2,  // mdccmect - DCCM error count
        0xBC8,  // meivt - PIC external interrupt vector table
        0xFC8,  // meihap - PIC external interrupt handler address/priority
        0xBC9,  // meipt - PIC external interrupt priority threshold
        0xBCA,  // meicpct - PIC context preserving threshold
        0xBCC,  // meicurpl - PIC current priority level
        0xBCB,  // meicidpl - PIC core interrupt priority level
      };

      if (eh2_custom_csrs.count(csr_num)) {
        // Add to Spike's csrmap if not already present
        if (processor->get_state()->csrmap.find(csr_num) ==
            processor->get_state()->csrmap.end()) {
          processor->get_state()->csrmap[csr_num] =
              std::make_shared<basic_csr_t>(processor.get(), csr_num, 0);
        }
        // Write the value
        processor->get_state()->csrmap[csr_num]->write(csr_val);
      }
      break;
    }
  }
}

// ---------------------------------------------------------------
// check_mem_access() - Memory access comparison
// ---------------------------------------------------------------

SpikeCosim::check_mem_result_e SpikeCosim::check_mem_access(
    bool store, uint32_t addr, size_t len, const uint8_t *bytes) {
  assert(len >= 1 && len <= 4);
  // Expect that no spike memory accesses cross a 32-bit boundary
  assert(((addr + (len - 1)) & 0xfffffffc) == (addr & 0xfffffffc));

  std::string iss_action = store ? "store" : "load";

  // Check if there are any pending DUT accesses to check against
  if (pending_dside_accesses.size() == 0) {
    // EH2 can satisfy a load internally without an external AXI transaction,
    // for example through store-buffer forwarding. The architectural GPR
    // writeback is still checked by step(), so only stores require a pending
    // D-side notification here.
    if (!store) {
      return kCheckMemOk;
    }

    std::stringstream err_str;
    err_str << "ISS generated " << iss_action << " at address " << std::hex
            << addr << " but no DUT memory access was pending";
    errors.emplace_back(err_str.str());
    return kCheckMemCheckFailed;
  }

  size_t pending_access_idx = 0;
  if (!store && is_widened_load_pair(0)) {
    for (size_t idx = 0; idx < 2; ++idx) {
      const auto &candidate_info = pending_dside_accesses[idx].dut_access_info;
      if ((addr & 0xfffffffc) == candidate_info.addr) {
        pending_access_idx = idx;
        break;
      }
    }
  }

  auto &top_pending_access = pending_dside_accesses[pending_access_idx];
  auto &top_pending_access_info = top_pending_access.dut_access_info;

  std::string dut_action = top_pending_access_info.store ? "store" : "load";

  // Check for an address match
  uint32_t aligned_addr = addr & 0xfffffffc;
  if (aligned_addr != top_pending_access_info.addr) {
    std::stringstream err_str;
    err_str << "DUT generated " << dut_action << " at address " << std::hex
            << top_pending_access_info.addr << " but " << iss_action
            << " at address " << aligned_addr << " was expected";
    errors.emplace_back(err_str.str());
    return kCheckMemCheckFailed;
  }

  // Check access type match
  if (store != top_pending_access_info.store) {
    std::stringstream err_str;
    err_str << "DUT generated " << dut_action << " at addr " << std::hex
            << top_pending_access_info.addr << " but a " << iss_action
            << " was expected";
    errors.emplace_back(err_str.str());
    return kCheckMemCheckFailed;
  }

  // Calculate bytes within aligned 32-bit word that spike has accessed
  uint32_t expected_be = ((1 << len) - 1) << (addr & 0x3);

  bool pending_access_done = false;
  bool misaligned = top_pending_access_info.misaligned_first ||
                    top_pending_access_info.misaligned_second;

  if (misaligned) {
    if ((expected_be & top_pending_access.be_spike) != 0) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " and expected BE "
              << expected_be << " has been seen twice, so far seen "
              << top_pending_access.be_spike;
      errors.emplace_back(err_str.str());
      return kCheckMemCheckFailed;
    }

    if ((expected_be & ~top_pending_access_info.be) != 0) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " but expected BE "
              << expected_be << " has other bytes enabled";
      errors.emplace_back(err_str.str());
      return kCheckMemCheckFailed;
    }

    top_pending_access.be_spike |= expected_be;

    if (top_pending_access.be_spike == top_pending_access_info.be) {
      pending_access_done = true;
    }
  } else {
    // Ibex's memory interface reports byte enables at architectural access
    // width. EH2 observes AXI reads after LSU widening, so a load can legally
    // return a full aligned word for a byte/halfword architectural access.
    // Stores must remain exact because WSTRB represents the committed bytes.
    if (store && expected_be != top_pending_access_info.be) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " but BE " << expected_be
              << " was expected";
      errors.emplace_back(err_str.str());
      return kCheckMemCheckFailed;
    }

    if (!store && ((expected_be & ~top_pending_access_info.be) != 0)) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " but expected BE "
              << expected_be << " was not fully covered";
      errors.emplace_back(err_str.str());
      return kCheckMemCheckFailed;
    }

    pending_access_done = true;
  }

  // Check data
  if (store || !top_pending_access_info.error) {
    uint32_t expected_data = 0;
    for (size_t i = 0; i < len; ++i) {
      expected_data |= bytes[i] << (i * 8);
    }
    expected_data <<= (addr & 0x3) * 8;

    uint32_t expected_be_bits = (((uint64_t)1 << (len * 8)) - 1)
                                << ((addr & 0x3) * 8);
    uint32_t masked_dut_data = top_pending_access_info.data & expected_be_bits;

    if (expected_data != masked_dut_data) {
      std::stringstream err_str;
      err_str << "DUT generated " << iss_action << " at address " << std::hex
              << top_pending_access_info.addr << " with data "
              << masked_dut_data << " but data " << expected_data
              << " was expected with byte mask " << expected_be;
      errors.emplace_back(err_str.str());
      return kCheckMemCheckFailed;
    }
  }

  bool pending_access_error = top_pending_access_info.error;

  if (pending_access_error && misaligned) {
    if (top_pending_access_info.misaligned_first &&
        ((top_pending_access_info.be & 0x8) != 0)) {
      if ((pending_dside_accesses.size() < 2) ||
          !pending_dside_accesses[1].dut_access_info.misaligned_second) {
        std::stringstream err_str;
        err_str << "DUT generated first half of misaligned " << iss_action
                << " at address " << std::hex << top_pending_access_info.addr
                << " but second half was expected and not seen";
        errors.emplace_back(err_str.str());
        return kCheckMemCheckFailed;
      }

      if (!pending_dside_accesses[1].dut_access_info.error) {
        std::stringstream err_str;
        err_str << "DUT generated first half of misaligned " << iss_action
                << " at address " << std::hex << top_pending_access_info.addr
                << " with error but second half had no error";
        errors.emplace_back(err_str.str());
        return kCheckMemCheckFailed;
      }

      // Verify second-half address is first-half + 4
      if (pending_dside_accesses[1].dut_access_info.addr !=
          top_pending_access_info.addr + 4) {
        std::stringstream err_str;
        err_str << "DUT generated first half of misaligned " << iss_action
                << " at address " << std::hex << top_pending_access_info.addr
                << " but second half address was "
                << pending_dside_accesses[1].dut_access_info.addr
                << " (expected " << (top_pending_access_info.addr + 4) << ")";
        errors.emplace_back(err_str.str());
        return kCheckMemCheckFailed;
      }
    }

    // For misaligned accesses with error: first half should always be removed
    // (pending_access_done was already set by the byte-enable check above).
    // Only second half needs explicit check since it's the last part.
    if (top_pending_access_info.misaligned_second) {
      pending_access_done = true;
    }
  }

  if (pending_access_done) {
    if (pending_access_error) {
      if (!store && is_widened_load_pair(0)) {
        pending_dside_accesses.erase(pending_dside_accesses.begin(),
                                     pending_dside_accesses.begin() + 2);
      } else {
        pending_dside_accesses.erase(pending_dside_accesses.begin() +
                                     pending_access_idx);
      }
      return kCheckMemBusError;
    }

    if (!store && is_widened_load_pair(0)) {
      pending_dside_accesses.erase(pending_dside_accesses.begin(),
                                   pending_dside_accesses.begin() + 2);
    } else {
      pending_dside_accesses.erase(pending_dside_accesses.begin() +
                                   pending_access_idx);
    }
  }

  return kCheckMemOk;
}

// ---------------------------------------------------------------
// Factory function - called by DPI bridge
// ---------------------------------------------------------------

extern "C" void *riscv_cosim_init(const char *config) {
  // Parse config string: "isa=<ISA>;pc=<PC>;mtvec=<MTVEC>;pmp_regions=<N>;"
  //                       "pmp_granularity=<G>;mhpm_counters=<N>;trace=<PATH>"
  std::string config_str(config);
  std::string isa_string = "rv32imac";
  uint32_t start_pc = 0;
  uint32_t start_mtvec = 0;
  uint32_t pmp_num_regions = 0;
  uint32_t pmp_granularity = 0;
  uint32_t mhpm_counter_num = 0;
  std::string trace_log_path;

  // Simple config parser
  size_t pos = 0;
  while (pos < config_str.length()) {
    size_t eq_pos = config_str.find('=', pos);
    if (eq_pos == std::string::npos) break;

    size_t semi_pos = config_str.find(';', eq_pos);
    if (semi_pos == std::string::npos) semi_pos = config_str.length();

    std::string key = config_str.substr(pos, eq_pos - pos);
    std::string val = config_str.substr(eq_pos + 1, semi_pos - eq_pos - 1);

    if (key == "isa") isa_string = val;
    else if (key == "pc") start_pc = strtoul(val.c_str(), nullptr, 0);
    else if (key == "mtvec") start_mtvec = strtoul(val.c_str(), nullptr, 0);
    else if (key == "pmp_regions") pmp_num_regions = strtoul(val.c_str(), nullptr, 0);
    else if (key == "pmp_granularity") pmp_granularity = strtoul(val.c_str(), nullptr, 0);
    else if (key == "mhpm_counters") mhpm_counter_num = strtoul(val.c_str(), nullptr, 0);
    else if (key == "trace") trace_log_path = val;

    pos = semi_pos + 1;
  }

  SpikeCosim *cosim = new SpikeCosim(
      isa_string, start_pc, start_mtvec, trace_log_path,
      pmp_num_regions, pmp_granularity, mhpm_counter_num);

  // SpikeCosim inherits simif_t first and Cosim second. Return the adjusted
  // Cosim subobject pointer because every DPI wrapper casts the chandle back to
  // Cosim*. Returning the raw SpikeCosim* would make the wrapper read the
  // simif_t vtable as a Cosim vtable and can crash on virtual calls.
  return static_cast<void *>(static_cast<Cosim *>(cosim));
}
