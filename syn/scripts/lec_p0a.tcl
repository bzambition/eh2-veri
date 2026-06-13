# Formality LEC — P0-A Option C: set_user_match for 194 unmatched 2D ports
# Generated 2026-05-09

set BUILD_DIR /home/host/eh2-veri/syn/build

set hdlin_error_on_elab_message false
set verification_mode relaxed
suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101 FM-036}
set_app_var hdlin_sverilog_std 2012

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
puts "FM: Setting ref top..."
set_top r:/WORK/eh2_veer

puts "FM: Reading implementation netlist..."
read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
puts "FM: Setting impl top..."
set_top i:/WORK/eh2_veer

# P0-A: User-specified port matching for 2D packed array ports
# Maps Ref 2D indices to Impl 1D indices
puts "FM: Setting user matches..."
source /home/host/eh2-veri/syn/scripts/lec_user_match.tcl
puts "FM: user_match OK"

puts "FM: Starting match..."
match
puts "FM: Starting verify..."
verify

report_status > $BUILD_DIR/lec_p0a_final.log
report_failing_points > $BUILD_DIR/lec_p0a_failing.rpt
puts "FM: === LEC (P0-A) Complete ==="
exit 0
