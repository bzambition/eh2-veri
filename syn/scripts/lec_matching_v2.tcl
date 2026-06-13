# LEC matching v2 — use add_compare_rules for 2D array ports
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
# Strategy: match 2D packed array ports by specifying compare rules
#
# The RTL has output ports declared as 2D packed arrays (e.g., [1:0][70:0]).
# DC synthesis flattens these to individual bit-level ports in the netlist.
# Formality sees the RTL ports as individual bits too, but the naming may differ.
#
# We use add_compare_rules with pin_matching_rule to map per-bit.
# ============================================================================

# Try matching output ports by type rather than name for the bus ports
# This tells Formality to match RTL and netlist ports of the same width/type
set_user_match_type -type ports -ref {r:/WORK/eh2_veer/*} -impl {i:/WORK/eh2_veer/*}

match
verify

report_status > $BUILD_DIR/lec_p0_1_final.log
report_failing_points > $BUILD_DIR/lec_p0_1_failing.rpt

exit 0
