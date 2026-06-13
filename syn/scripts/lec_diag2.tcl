# LEC Diagnostic — list unmatched ports for matching fix
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

match

# Report unmatched points (first 30 ref, 30 impl)
puts "\n=== First 30 Unmatched REF Output Ports ==="
report_unmatched_points -ref -port -max 30

puts "\n=== First 30 Unmatched IMPL Output Ports ==="
report_unmatched_points -impl -port -max 30

exit 0
