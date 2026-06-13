# DC synthesis — R3-C Step 0 keep-2D experiment.
# This is a non-invasive probe for Synopsys O-2018.06-SP1 packed-array handling.

proc try_set_app_var {name value} {
    if {[catch {set_app_var $name $value} msg]} {
        puts "DC: keep2d option unsupported: $name = $value ($msg)"
        return 0
    }
    puts "DC: keep2d option set: $name = $value"
    return 1
}

proc try_set_var {name value} {
    if {[catch {set $name $value} msg]} {
        puts "DC: keep2d variable unsupported: $name = $value ($msg)"
        return 0
    }
    puts "DC: keep2d variable set: $name = $value"
    return 1
}

set TARGET_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
set GTECH_DB  /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
set_app_var target_library $TARGET_DB
set_app_var link_library [list * $GTECH_DB $TARGET_DB]
set_app_var hdlin_sverilog_std 2012
set_app_var hdlin_keep_signal_name all_ports

try_set_var verilogout_no_tri true
try_set_var verilogout_show_unconnected_pins true
try_set_app_var hdlin_unresolved_modules black_box
try_set_app_var change_names_dont_change_packed_arrays true
try_set_app_var hdlin_preserve_packed_arrays true

set BUILD_DIR /home/host/eh2-veri/syn/build
file mkdir $BUILD_DIR

suppress_message {LINT-1 LINT-28 LINT-29 LINT-31 LINT-32 LINT-33 LINT-34}
suppress_message {VER-130 VER-250 VER-318 VER-26 VER-1}
suppress_message {UID-401}
suppress_message {ELAB-902}

set_app_var search_path [concat \
    /home/host/eh2-veri/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

puts "DC: === R3-C keep2d synthesis probe ==="
puts "DC: Analyzing wrapper..."
analyze -format sverilog -work WORK $BUILD_DIR/eh2_dc_wrapper.sv

puts "DC: Elaborating eh2_veer..."
elaborate eh2_veer -work WORK
link
uniquify
check_design

create_clock -name clk -period 2.0 [get_ports clk]
set_max_fanout 32 [current_design]
set_max_transition 0.5 [current_design]

puts "DC: Starting compile_ultra..."
compile_ultra -no_autoungroup -no_boundary_optimization
puts "DC: compile_ultra done"

report_area -hierarchy > $BUILD_DIR/r3c_keep2d_area_report.txt
report_timing -max_paths 10 > $BUILD_DIR/r3c_keep2d_timing_report.txt
report_qor > $BUILD_DIR/r3c_keep2d_qor_report.txt

change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $BUILD_DIR/eh2_synth_keep2d.v

puts "DC: Netlist cells: [sizeof_collection [get_cells -hier *]]"
puts "DC: === R3-C keep2d synthesis probe complete ==="
exit 0
