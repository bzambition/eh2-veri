# DC block-level synthesis for R3-C LEC.
# Set R3C_BLOCK_TOP to the RTL module name before invoking dc_shell.

if {![info exists env(R3C_BLOCK_TOP)] || $env(R3C_BLOCK_TOP) eq ""} {
    puts "DC: ERROR: R3C_BLOCK_TOP is not set"
    exit 1
}

set TOP $env(R3C_BLOCK_TOP)
set TARGET_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
set GTECH_DB  /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
set_app_var target_library $TARGET_DB
set_app_var link_library [list * $GTECH_DB $TARGET_DB]
set_app_var hdlin_sverilog_std 2012
set_app_var hdlin_keep_signal_name all_ports

set BUILD_DIR /home/host/eh2-veri/syn/build
set BLOCK_DIR $BUILD_DIR/lec_blocklevel/synth
file mkdir $BLOCK_DIR

# Redirect DC working files to a dedicated build subdir.
set RUN_DIR $BUILD_DIR/lec_blocklevel/run/dc/$TOP
file mkdir $RUN_DIR
cd $RUN_DIR
catch {set_app_var hdlin_temporary_dir $RUN_DIR}

set BLOCK_SVF $BLOCK_DIR/${TOP}.svf
file delete -force $BLOCK_SVF
set_svf $BLOCK_SVF

suppress_message {LINT-1 LINT-28 LINT-29 LINT-31 LINT-32 LINT-33 LINT-34}
suppress_message {VER-130 VER-250 VER-318 VER-26 VER-1}
suppress_message {UID-401}
suppress_message {ELAB-902}

set_app_var search_path [concat \
    $RUN_DIR \
    $BLOCK_DIR \
    /home/host/eh2-veri/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

puts "DC: === R3-C block synthesis: $TOP ==="
analyze -format sverilog -work WORK $BUILD_DIR/eh2_dc_wrapper.sv
elaborate $TOP -work WORK
link
uniquify
check_design

if {[info exists env(R3C_VERIFY_PRIORITY)] && $env(R3C_VERIFY_PRIORITY) eq "1"} {
    puts "DC: Setting verification priority for LEC-oriented datapath preservation"
    set_verification_priority -all -high
}

set clk_ports [get_ports clk -quiet]
if {[sizeof_collection $clk_ports] > 0} {
    create_clock -name clk -period 2.0 $clk_ports
} else {
    puts "DC: No top-level clk port found for $TOP; continuing without a clock constraint"
}

set_max_fanout 32 [current_design]
set_max_transition 0.5 [current_design]

if {[info exists env(R3C_SIMPLE_COMPILE)] && $env(R3C_SIMPLE_COMPILE) eq "1"} {
    puts "DC: Using simple compile for LEC-oriented block netlist"
    compile -map_effort medium
} else {
    compile_ultra -no_autoungroup -no_boundary_optimization
}

report_area -hierarchy > $BLOCK_DIR/${TOP}_area.rpt
report_timing -max_paths 10 > $BLOCK_DIR/${TOP}_timing.rpt
report_qor > $BLOCK_DIR/${TOP}_qor.rpt

change_names -rules verilog -hierarchy
write -format ddc -hierarchy -output $BLOCK_DIR/${TOP}.ddc
write -format verilog -hierarchy -output $BLOCK_DIR/${TOP}.v
set_svf -off

puts "DC: Wrote $BLOCK_DIR/${TOP}.v"
puts "DC: Wrote $BLOCK_DIR/${TOP}.ddc"
puts "DC: Wrote $BLOCK_SVF"
puts "DC: === R3-C block synthesis complete: $TOP ==="
exit 0
