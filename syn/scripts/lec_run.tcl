# Formality LEC — RC3 v4: add class.db as link library

set BUILD_DIR /home/host/eh2-veri/syn/build

# Redirect Formality working files to a dedicated build subdir.
set RUN_DIR $BUILD_DIR/lec_run
file mkdir $RUN_DIR
cd $RUN_DIR
catch {set_app_var hdlin_temporary_dir $RUN_DIR}

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

# Match and verify
puts "FM: Starting match..."
match
puts "FM: Starting verify..."
verify

report_status > $BUILD_DIR/lec_report.txt
puts "FM: === LEC Complete ==="
exit 0
