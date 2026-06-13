# Formality LEC — P0-A: use set_svf to guide matching of 2D packed array ports
# SVF preserves optimization history so Formality can map bit-blasted ports

set BUILD_DIR /home/host/eh2-veri/syn/build

set hdlin_error_on_elab_message false
set verification_mode relaxed
suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
set_app_var hdlin_sverilog_std 2012

set_app_var search_path [concat \
    /home/host/eh2-veri/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

# Read class.db to resolve synth cell references
puts "FM: Reading technology libraries..."
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

# Load SVF before reading designs to guide matching
puts "FM: Loading SVF..."
set_svf /home/host/eh2-veri/default.svf

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

# Match and verify — SVF guides the matching
puts "FM: Starting match (SVF-guided)..."
match
puts "FM: Starting verify..."
verify

report_status > $BUILD_DIR/lec_p0a_svf.log
report_failing_points > $BUILD_DIR/lec_p0a_svf_failing.rpt
puts "FM: === LEC (SVF) Complete ==="
exit 0
