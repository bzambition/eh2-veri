# DC synthesis — RC3 v8: wrapper + class.db target library
# v7: elaboration succeeded (379K cells GTECH), compile_ultra failed (gtech not mappable)
# v8: use class.db (generic educational library) for technology mapping

set TARGET_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
set GTECH_DB  /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
set_app_var target_library $TARGET_DB
set_app_var link_library [list * $GTECH_DB $TARGET_DB]
set_app_var hdlin_sverilog_std 2012
set_app_var hdlin_keep_signal_name all_driving

set BUILD_DIR /home/host/eh2-veri/syn/build
file mkdir $BUILD_DIR

# Redirect DC working files to a dedicated build subdir.
set RUN_DIR $BUILD_DIR/dc_run
file mkdir $RUN_DIR
cd $RUN_DIR
catch {set_app_var hdlin_temporary_dir $RUN_DIR}

suppress_message {LINT-1 LINT-28 LINT-29 LINT-31 LINT-32 LINT-33 LINT-34}
suppress_message {VER-130 VER-250 VER-318 VER-26 VER-1}
suppress_message {UID-401}
suppress_message {ELAB-902}

set_app_var search_path [concat \
    $RUN_DIR \
    /home/host/eh2-veri/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

puts "DC: === EH2 Synthesis RC3 v8 (class.db target) ==="

puts "DC: Analyzing wrapper..."
analyze -format sverilog -work WORK $BUILD_DIR/eh2_dc_wrapper.sv
puts "DC: analyze OK"

puts "DC: Elaborating eh2_veer..."
elaborate eh2_veer -work WORK
puts "DC: elaborate OK — [current_design]"

link
puts "DC: link OK"
uniquify

check_design
puts "DC: check_design OK"

create_clock -name clk -period 2.0 [get_ports clk]
set_max_fanout 32 [current_design]
set_max_transition 0.5 [current_design]

puts "DC: Starting compile_ultra..."
compile_ultra -no_autoungroup -no_boundary_optimization
puts "DC: compile_ultra done"

report_area -hierarchy > $BUILD_DIR/area_report.txt
report_timing -max_paths 10 > $BUILD_DIR/timing_report.txt
report_qor > $BUILD_DIR/qor_report.txt

change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $BUILD_DIR/eh2_synth.v
# Note: write_svf not available in DC O-2018.06, use set_svf in Formality instead

puts "DC: Netlist cells: [sizeof_collection [get_cells -hier *]]"
puts "DC: === Synthesis Complete ==="
exit 0
