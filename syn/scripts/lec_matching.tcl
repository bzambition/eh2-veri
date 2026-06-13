# ============================================================================
# lec_matching.tcl — Formality LEC Matching Directives
# RC5 (2026-05-09)
#
# Classification of 194 unmatched output ports:
#   All 194 are BUS BIT-BLASTING: the RTL declares 2D packed arrays
#   (e.g., [1:0][70:0] ic_wr_data) that DC synthesis flattens to
#   individual bit-level ports in the netlist.  Formality cannot match
#   the bit-blasted names automatically.
#
# Buckets:
#   Bucket A: ic_wr_data          — 142 points (ICACHE_BANKS_WAY × 71 bits)
#   Bucket B: btb_rw_addr         —  18 points (2 banks × BTB_ADDR_HI:1)
#   Bucket C: btb_rw_addr_f1      —  18 points (2 banks × BTB_ADDR_HI:1)
#   Bucket D: btb_sram_rd_tag_f1  —  10 points (2 banks × BTB_BTAG_SIZE)
#   Bucket E: trace_rv_i_valid_ip —   2 points (NUM_THREADS × 2 bits)
#   Bucket F: trace_rv_i_address_ip—  2 points (NUM_THREADS × 64 bits)
#   Bucket G: trace_rv_i_exception_ip—1 point
#   Bucket H: trace_rv_i_interrupt_ip—1 point
# ============================================================================

set BUILD_DIR /home/host/eh2-veri/syn/build

suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
set_app_var hdlin_sverilog_std 2012
set verification_mode relaxed
set verification_set_undriven_signals 0

set_app_var search_path [concat \
    /home/host/eh2-veri/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
set_top r:/WORK/eh2_veer

read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
set_top i:/WORK/eh2_veer

# ============================================================================
# Step 1: Explicit user matches for 2D bus ports
#   RTL uses 2D packed arrays; netlist flattens to 1D bit-level ports.
#   set_user_match maps each RTL port to its netlist equivalent.
# ============================================================================

# --- Bucket A: ic_wr_data [pt.ICACHE_BANKS_WAY-1:0][70:0] (142 bits) ---
# RTL: output logic [pt.ICACHE_BANKS_WAY-1:0] [70:0] ic_wr_data
# Netlist: flattened to \ic_wr_data[0][0] .. \ic_wr_data[0][70]
set_user_match r:/WORK/eh2_veer/ic_wr_data \
               i:/WORK/eh2_veer/ic_wr_data

# --- Bucket B: btb_rw_addr [1:0][pt.BTB_ADDR_HI:1] (18 points) ---
set_user_match r:/WORK/eh2_veer/btb_rw_addr \
               i:/WORK/eh2_veer/btb_rw_addr

# --- Bucket C: btb_rw_addr_f1 [1:0][pt.BTB_ADDR_HI:1] (18 points) ---
set_user_match r:/WORK/eh2_veer/btb_rw_addr_f1 \
               i:/WORK/eh2_veer/btb_rw_addr_f1

# --- Bucket D: btb_sram_rd_tag_f1 [1:0][pt.BTB_BTAG_SIZE-1:0] (10 points) ---
set_user_match r:/WORK/eh2_veer/btb_sram_rd_tag_f1 \
               i:/WORK/eh2_veer/btb_sram_rd_tag_f1

# --- Bucket E: trace_rv_i_valid_ip [pt.NUM_THREADS-1:0][1:0] (2 points) ---
set_user_match r:/WORK/eh2_veer/trace_rv_i_valid_ip \
               i:/WORK/eh2_veer/trace_rv_i_valid_ip

# --- Bucket F: trace_rv_i_address_ip [pt.NUM_THREADS-1:0][63:0] (2 points) ---
set_user_match r:/WORK/eh2_veer/trace_rv_i_address_ip \
               i:/WORK/eh2_veer/trace_rv_i_address_ip

# --- Bucket G: trace_rv_i_exception_ip [pt.NUM_THREADS-1:0][1:0] (1 point) ---
set_user_match r:/WORK/eh2_veer/trace_rv_i_exception_ip \
               i:/WORK/eh2_veer/trace_rv_i_exception_ip

# --- Bucket H: trace_rv_i_interrupt_ip [pt.NUM_THREADS-1:0][1:0] (1 point) ---
set_user_match r:/WORK/eh2_veer/trace_rv_i_interrupt_ip \
               i:/WORK/eh2_veer/trace_rv_i_interrupt_ip

# ============================================================================
# Step 4: Run match + verify with the directives applied
# ============================================================================
match
verify

# Generate final report
report_status > $BUILD_DIR/lec_p0_1_final.log
report_failing_points > $BUILD_DIR/lec_p0_1_failing.rpt

exit 0
