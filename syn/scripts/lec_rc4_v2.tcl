# Formality LEC — R3-C Step 0 keep-2D netlist experiment.

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

puts "FM: Reading technology libraries..."
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

puts "FM: Reading reference design..."
read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
set_top r:/WORK/eh2_veer

puts "FM: Reading keep2d implementation netlist..."
read_verilog -i -libname WORK $BUILD_DIR/eh2_synth_keep2d.v
set_top i:/WORK/eh2_veer

puts "FM: Matching..."
match

puts "FM: Verifying..."
verify

puts "FM: Reporting..."
report_status > $BUILD_DIR/r3c_lec_keep2d_report.txt
report_failing_points -inputs unmatched > $BUILD_DIR/r3c_lec_keep2d_failing.rpt
report_unverified_points > $BUILD_DIR/r3c_lec_keep2d_unverified.rpt

puts "FM: === R3-C keep2d LEC complete ==="
exit 0
