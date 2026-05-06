// SPDX-License-Identifier: Apache-2.0
// EH2 PMP Functional Coverage Interface
//
// Covers PMP (Physical Memory Protection) configuration and behavior.
// Benchmarked against ibex's core_ibex_pmp_fcov_if.sv, adapted for EH2.
//
// Covergroups:
//   pmp_region_cg    - Per-region configuration coverage
//   pmp_access_cg    - PMP access check coverage (iside/dside)
//   pmp_warl_cg      - PMP WARL behavior coverage
//   pmp_epmp_cg      - ePMP (MML/MMWP/RLB) coverage
//
// Enable via: +enable_eh2_fcov=1 (requires PMPEnable=1)

interface eh2_pmp_fcov_if
  import eh2_pkg::*;
#(
  parameter bit          PMPEnable      = 1'b0,
  parameter int unsigned PMPGranularity = 0,
  parameter int unsigned PMPNumRegions  = 4
) (
  input logic clk_i,
  input logic rst_l_i,

  // PMP configuration from CSR registers
  input logic [PMPNumRegions-1:0]       pmp_cfg_lock,
  input logic [PMPNumRegions-1:0] [1:0] pmp_cfg_mode,
  input logic [PMPNumRegions-1:0]       pmp_cfg_exec,
  input logic [PMPNumRegions-1:0]       pmp_cfg_write,
  input logic [PMPNumRegions-1:0]       pmp_cfg_read,
  input logic [PMPNumRegions-1:0] [31:0] pmp_addr,

  // ePMP mseccfg
  input logic mseccfg_mml,
  input logic mseccfg_mmwp,
  input logic mseccfg_rlb,

  // PMP access check results
  input logic pmp_iside_err,
  input logic pmp_dside_err,

  // Debug mode
  input logic debug_mode,

  // Data request
  input logic data_req
);

  `include "uvm_macros.svh"

  bit en_pmp_fcov;

  initial begin
    if (PMPEnable) begin
      void'($value$plusargs("enable_eh2_fcov=%d", en_pmp_fcov));
    end else begin
      en_pmp_fcov = 1'b0;
    end
  end

  // =========================================================================
  // PMP Mode enum
  // =========================================================================
  typedef enum logic [1:0] {
    PMP_MODE_OFF   = 2'b00,
    PMP_MODE_TOR   = 2'b01,
    PMP_MODE_NA4   = 2'b10,
    PMP_MODE_NAPOT = 2'b11
  } pmp_mode_e;

  // =========================================================================
  // PMP Permission bits with MML support
  // =========================================================================
  typedef enum logic [4:0] {
    NONE        = 5'b00000,
    R           = 5'b00001,
    W           = 5'b00010,
    WR          = 5'b00011,
    X           = 5'b00100,
    XR          = 5'b00101,
    XW          = 5'b00110,
    XWR         = 5'b00111,
    L           = 5'b01000,
    LR          = 5'b01001,
    LW          = 5'b01010,
    LWR         = 5'b01011,
    LX          = 5'b01100,
    LXR         = 5'b01101,
    LXW         = 5'b01110,
    LXWR        = 5'b01111,
    MML_NONE    = 5'b10000,
    MML_RU      = 5'b10001,
    MML_WRM_RU  = 5'b10010,
    MML_WRU     = 5'b10011,
    MML_XU      = 5'b10100,
    MML_XRU     = 5'b10101,
    MML_WRM_WRU = 5'b10110,
    MML_XWRU    = 5'b10111,
    MML_L       = 5'b11000,
    MML_RM      = 5'b11001,
    MML_XM_XU   = 5'b11010,
    MML_WRM     = 5'b11011,
    MML_XM      = 5'b11100,
    MML_XRM     = 5'b11101,
    MML_XRM_XU  = 5'b11110,
    MML_RM_RU   = 5'b11111
  } pmp_priv_bits_e;

  if (PMPEnable) begin : g_pmp_fcov

    // =========================================================================
    // Per-region configuration coverage
    // =========================================================================
    for (genvar i = 0; i < PMPNumRegions; i++) begin : g_region_cg

      pmp_priv_bits_e region_priv_bits;
      assign region_priv_bits = pmp_priv_bits_e'({mseccfg_mml,
                                                   pmp_cfg_lock[i],
                                                   pmp_cfg_exec[i],
                                                   pmp_cfg_write[i],
                                                   pmp_cfg_read[i]});

      covergroup pmp_region_cg @(posedge clk_i);
        option.per_instance = 1;
        option.name = $sformatf("pmp_region_%0d_cg", i);

        // PMP mode
        cp_mode: coverpoint pmp_cfg_mode[i] {
          bins off   = {PMP_MODE_OFF};
          bins tor   = {PMP_MODE_TOR};
          bins na4   = {PMP_MODE_NA4};
          bins napot = {PMP_MODE_NAPOT};
        }

        // Permission bits (with MML encoding)
        cp_priv_bits: coverpoint region_priv_bits {
          wildcard illegal_bins illegal = {5'b0??10};
        }

        // Lock bit
        cp_lock: coverpoint pmp_cfg_lock[i] {
          bins locked   = {1};
          bins unlocked = {0};
        }

        // Mode x lock cross
        mode_lock_cross: cross cp_mode, cp_lock;

        // Mode x permission cross
        mode_priv_cross: cross cp_mode, cp_priv_bits {
          ignore_bins off_with_priv = binsof(cp_mode) intersect {PMP_MODE_OFF};
        }
      endgroup

      pmp_region_cg region_cg_inst;
      initial region_cg_inst = new();

    end : g_region_cg

    // =========================================================================
    // PMP Access Check Coverage
    // =========================================================================
    covergroup pmp_access_cg @(posedge clk_i);
      option.per_instance = 1;
      option.name = "pmp_access_cg";

      // Instruction-side PMP error
      cp_iside_err: coverpoint pmp_iside_err {
        bins no_error = {0};
        bins error    = {1};
      }

      // Data-side PMP error
      cp_dside_err: coverpoint pmp_dside_err iff (data_req) {
        bins no_error = {0};
        bins error    = {1};
      }

      // Debug mode during access
      cp_debug_mode: coverpoint debug_mode {
        bins in_debug    = {1};
        bins not_debug   = {0};
      }

      // Iside error x debug mode
      iside_debug_cross: cross cp_iside_err, cp_debug_mode;

      // Dside error x debug mode
      dside_debug_cross: cross cp_dside_err, cp_debug_mode;
    endgroup

    pmp_access_cg access_cg_inst;
    initial access_cg_inst = new();

    // =========================================================================
    // PMP WARL Behavior Coverage
    // Tracks which PMP CSRs are being written and verifies WARL compliance.
    // =========================================================================
    covergroup pmp_warl_cg @(posedge clk_i);
      option.per_instance = 1;
      option.name = "pmp_warl_cg";

      // PMP address write - NAPOT address patterns
      // In NAPOT mode, the address encodes the region size via trailing ones
      cp_napot_size: coverpoint $countones(pmp_addr[0][31:2]) iff (pmp_cfg_mode[0] == PMP_MODE_NAPOT) {
        bins size_8B    = {30};   // 8 byte region
        bins size_16B   = {29};   // 16 byte region
        bins size_32B   = {28};
        bins size_64B   = {27};
        bins size_128B  = {26};
        bins size_256B  = {25};
        bins size_512B  = {24};
        bins size_1KB   = {23};
        bins size_2KB   = {22};
        bins size_4KB   = {21};
        bins size_8KB   = {20};
        bins size_16KB  = {19};
        bins size_32KB  = {18};
        bins size_64KB  = {17};
        bins size_128KB = {16};
        bins size_256KB = {15};
        bins size_512KB = {14};
        bins size_1MB   = {13};
        bins size_2MB   = {12};
        bins size_4MB   = {11};
        bins size_8MB   = {10};
        bins size_16MB  = {9};
        bins size_32MB  = {8};
        bins size_64MB  = {7};
        bins size_128MB = {6};
        bins size_256MB = {5};
        bins size_512MB = {4};
        bins size_1GB   = {3};
        bins size_2GB   = {2};
        bins size_4GB   = {1};
      }
    endgroup

    pmp_warl_cg warl_cg_inst;
    initial warl_cg_inst = new();

    // =========================================================================
    // ePMP (MML/MMWP/RLB) Coverage
    // =========================================================================
    covergroup pmp_epmp_cg @(posedge clk_i);
      option.per_instance = 1;
      option.name = "pmp_epmp_cg";

      // MML (Machine Mode Lockdown)
      cp_mml: coverpoint mseccfg_mml {
        bins enabled  = {1};
        bins disabled = {0};
      }

      // MMWP (Machine Mode Whitelist Policy)
      cp_mmwp: coverpoint mseccfg_mmwp {
        bins enabled  = {1};
        bins disabled = {0};
      }

      // RLB (Rule Locking Bypass)
      cp_rlb: coverpoint mseccfg_rlb {
        bins enabled  = {1};
        bins disabled = {0};
      }

      // MML x MMWP cross (key ePMP policy combinations)
      mml_mmwp_cross: cross cp_mml, cp_mmwp;

      // All three ePMP bits
      epmp_config_cross: cross cp_mml, cp_mmwp, cp_rlb;

      // ePMP config x iside error
      epmp_iside_cross: cross cp_mml, cp_mmwp, pmp_iside_err;

      // ePMP config x dside error
      epmp_dside_cross: cross cp_mml, cp_mmwp, pmp_dside_err iff (data_req);
    endgroup

    pmp_epmp_cg epmp_cg_inst;
    initial epmp_cg_inst = new();

  end : g_pmp_fcov

endinterface
