// SPDX-License-Identifier: Apache-2.0
// EH2 Spike Co-simulation Implementation
//
// Concrete implementation of the Cosim abstract class using Spike
// as the reference model for EH2 verification.
// Based on Ibex's spike_cosim.cc pattern, adapted for EH2.

#ifndef EH2_SPIKE_COSIM_H
#define EH2_SPIKE_COSIM_H

#include <cstdint>
#include <deque>
#include <memory>
#include <string>
#include <vector>

#include "cosim.h"
#include "riscv/devices.h"
#include "riscv/isa_parser.h"
#include "riscv/log_file.h"
#include "riscv/processor.h"
#include "riscv/simif.h"

// EH2 marchid value (VeeR EH2)
#define EH2_MARCHID 0x56524545  // "VEER" in ASCII

class SpikeCosim : public simif_t, public Cosim {
public:
  SpikeCosim(const std::string &isa_string, uint32_t start_pc,
             uint32_t start_mtvec, const std::string &trace_log_path,
             uint32_t pmp_num_regions, uint32_t pmp_granularity,
             uint32_t mhpm_counter_num);

  // simif_t implementation
  virtual char *addr_to_mem(reg_t addr) override;
  virtual bool mmio_load(reg_t addr, size_t len, uint8_t *bytes) override;
  virtual bool mmio_store(reg_t addr, size_t len,
                          const uint8_t *bytes) override;
  virtual void proc_reset(unsigned id) override;
  virtual const char *get_symbol(uint64_t addr) override;

  // Cosim implementation
  void add_memory(uint32_t base_addr, size_t size) override;
  bool backdoor_write_mem(uint32_t addr, size_t len,
                          const uint8_t *data_in) override;
  bool backdoor_read_mem(uint32_t addr, size_t len, uint8_t *data_out) override;
  bool step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
            bool sync_trap, bool suppress_reg_write) override;

  void set_mip(uint32_t pre_mip, uint32_t post_mip) override;
  void set_nmi(bool nmi) override;
  void set_nmi_int(bool nmi_int) override;
  void set_debug_req(bool debug_req) override;
  void set_mcycle(uint64_t mcycle) override;
  void set_csr(const int csr_num, const uint32_t new_val) override;
  void notify_dside_access(const DSideAccessInfo &access_info) override;
  void set_iside_error(uint32_t addr) override;
  const std::vector<std::string> &get_errors() override;
  void clear_errors() override;
  unsigned int get_insn_cnt() override;

  // Trap CSR queries (RISK-9)
  uint32_t get_mcause() override;
  uint32_t get_mepc() override;
  uint32_t get_mtvec() override;

private:
  // Spike processor and ISA
  std::unique_ptr<isa_parser_t> isa_parser;
  std::unique_ptr<processor_t> processor;
  std::unique_ptr<log_file_t> log;

  // Memory bus
  bus_t bus;
  std::vector<std::unique_ptr<mem_t>> mems;

  // Error tracking
  std::vector<std::string> errors;

  // NMI state
  bool nmi_mode;

  // Pending dside accesses from DUT
  struct PendingMemAccess {
    DSideAccessInfo dut_access_info;
    uint32_t be_spike;
  };
  std::vector<PendingMemAccess> pending_dside_accesses;

  // Pending iside error
  bool pending_iside_error;
  uint32_t pending_iside_err_addr;

  // Mstack for NMI handling
  typedef struct {
    uint8_t mpp;
    bool mpie;
    uint32_t epc;
    uint32_t cause;
  } mstack_t;
  mstack_t mstack;

  // Instruction count
  unsigned int insn_cnt;

  // Internal methods
  void initial_proc_setup(uint32_t start_pc, uint32_t start_mtvec,
                          uint32_t mhpm_counter_num);
  void fixup_csr(int csr_num, uint32_t csr_val);
  void misaligned_pmp_fixup(uint32_t addr, bool store);
  bool check_retired_instr(uint32_t write_reg, uint32_t write_reg_data,
                           uint32_t dut_pc, bool suppress_reg_write);
  bool check_sync_trap(uint32_t write_reg, uint32_t pc,
                       uint32_t initial_spike_pc);
  bool check_gpr_write(const commit_log_reg_t::value_type &reg_change,
                       uint32_t write_reg, uint32_t write_reg_data);
  bool check_suppress_reg_write(uint32_t write_reg, uint32_t pc,
                                uint32_t &suppressed_write_reg);
  void on_csr_write(const commit_log_reg_t::value_type &reg_change);
  void leave_nmi_mode();

  // Interrupt/debug handling (Ibex-aligned)
  void early_interrupt_handle();
  bool pc_is_mret(uint32_t pc);
  bool pc_is_debug_ebreak(uint32_t pc);
  void check_debug_ebreak(uint32_t write_reg, uint32_t pc, bool sync_trap);
  bool pc_is_load(uint32_t pc);
  bool pc_is_div_or_rem(uint32_t pc);
  bool is_widened_load_pair(size_t first_idx) const;

  enum check_mem_result_e {
    kCheckMemOk,
    kCheckMemCheckFailed,
    kCheckMemBusError
  };
  check_mem_result_e check_mem_access(bool store, uint32_t addr, size_t len,
                                      const uint8_t *bytes);
};

#endif // EH2_SPIKE_COSIM_H
