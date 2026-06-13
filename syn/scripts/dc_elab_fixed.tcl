# DC elaboration script v4 — fixed include path
# Target: elaborate eh2_veer, dump flat Verilog for yosys synthesis + LEC

set GTECH_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
set_app_var target_library $GTECH_DB
set_app_var link_library [list $GTECH_DB]
set_app_var hdlin_sverilog_std 2012

# Fix: set search_path so `include "eh2_param.vh"` resolves
set_app_var search_path [list \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    {*}[get_app_var search_path]]

# Suppress non-fatal noise
suppress_message {LINT-1 LINT-28 LINT-29 LINT-31 LINT-32 LINT-33 LINT-34}
suppress_message {VER-130 VER-250 VER-318}
suppress_message {UID-401}

set WORK_DIR /home/host/eh2-veri/syn/build/DC_WORK
file mkdir $WORK_DIR

puts "DC: Analyzing RTL files (corrected include path)..."

# Type defs and packages (must be first)
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/snapshots/default/eh2_pdef.vh
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/include/eh2_def.sv

# Read RTL file list
set fp [open "/home/host/eh2-veri/syn/build/eh2_rtl_dc.lst" r]
set rtl_files [list]
while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line ne "" && [string index $line 0] ne "#"} {
        lappend rtl_files $line
    }
}
close $fp

puts "DC: Analyzing [llength $rtl_files] RTL files..."
set analyzed 0
set failed 0
foreach f $rtl_files {
    if {[catch {analyze -format sverilog -work WORK $f} err]} {
        puts "  FAILED: $f"
        puts "    $err"
        incr failed
    } else {
        incr analyzed
    }
    if {$analyzed % 10 == 0} { puts "  Analyzed $analyzed/[llength $rtl_files]..." }
}
puts "DC: $analyzed analyzed, $failed failed"

if {$failed > 0} {
    puts "DC: WARNING — $failed files failed analysis. Attempting elaboration anyway."
}

puts "DC: Elaborating eh2_veer..."
if {[catch {elaborate eh2_veer -work WORK -parameters ""} err]} {
    puts "DC: Elaboration FAILED: $err"
    exit 1
}

puts "DC: Elaboration complete. Current design: [current_design]"

puts "DC: Writing flat Verilog..."
write -format verilog -output /home/host/eh2-veri/syn/build/eh2_golden_flat.v

puts "DC: Done. Checking output..."
exit 0
