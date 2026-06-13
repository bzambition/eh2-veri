# Formality LEC — RC4 Final Fix
# After the first fix (undriven signals + clock gate handling), we went from:
#   RC3: 29,397 PASS / 214 FAIL / 1,258 UNVER
#   RC4 v1: 30,675 PASS / 194 FAIL / 0 UNVER
#
# This script diagnoses the remaining 194 failing points (likely constant regs).

set BUILD_DIR /home/host/eh2-veri/syn/build

# Redirect Formality working files to a dedicated build subdir.
set RUN_DIR $BUILD_DIR/lec_rc4_final_run
file mkdir $RUN_DIR
cd $RUN_DIR
catch {set_app_var hdlin_temporary_dir $RUN_DIR}

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

puts "FM: Reading implementation netlist..."
read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
set_top i:/WORK/eh2_veer

puts "FM: Matching..."
match

puts "FM: Diagnostic: analyzing failing points..."
analyze_points -all > $BUILD_DIR/lec_rc4_diagnosis.txt

puts "FM: Verifying..."
verify

puts "FM: Reporting..."
report_status > $BUILD_DIR/lec_rc4_final_report.txt
report_failing_points -inputs unmatched > $BUILD_DIR/lec_rc4_failing_detail.rpt
report_unverified_points > $BUILD_DIR/lec_rc4_unverified_detail.rpt

puts "FM: === RC4 Final LEC Complete ==="
exit 0
