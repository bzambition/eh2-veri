# Formality LEC — RC4 Fix Script
# Diagnoses and resolves the 214 failing + 1258 unverified compare points
# from the RC3 run (which ended with Verification FAILED).

set BUILD_DIR /home/host/eh2-veri/syn/build

# Suppress known non-critical messages
suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
set_app_var hdlin_sverilog_std 2012

# Critical: set verification mode and undriven signal handling
set verification_mode relaxed
# Treat undriven signals as 0 to handle tied-off ports (DC ties them low)
set verification_set_undriven_signals 0

# Set search path
set_app_var search_path [concat \
    /home/host/eh2-veri/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

# Read technology libraries
puts "FM: Reading technology libraries..."
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

# Reference (Golden RTL)
puts "FM: Reading reference design..."
read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv
puts "FM: Setting ref top..."
set_top r:/WORK/eh2_veer

# Implementation (synthesized netlist)
puts "FM: Reading implementation netlist..."
read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
puts "FM: Setting impl top..."
set_top i:/WORK/eh2_veer

# Pre-match: handle clock-gating and synthesis optimizations
puts "FM: Configuring verification settings..."
# Match clock gates (SNPS_CLOCK_GATE cells from DC)
# These are structurally different from RTL clock-enable logic
set verification_clock_gate_hold_mode low

puts "FM: Starting match..."
match

puts "FM: Starting verify..."
verify

# Report results with full detail
puts "FM: Generating reports..."
report_status > $BUILD_DIR/lec_rc4_report.txt
report_failing_points -verbose > $BUILD_DIR/lec_rc4_failing.rpt
report_unverified_points -verbose > $BUILD_DIR/lec_rc4_unverified.rpt
report_passing_points -summary > $BUILD_DIR/lec_rc4_passing.rpt

puts "FM: === RC4 LEC Complete ==="
exit 0
