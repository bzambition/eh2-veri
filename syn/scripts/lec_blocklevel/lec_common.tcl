# R3-C block-level Formality setup shared by the per-module LEC scripts.
# This flow intentionally reuses the RC4 reference wrapper and synthesized
# netlist.  No compare points are masked; each block script selects a narrower
# top before match/verify.

set EH2_ROOT /home/host/eh2-veri
set BUILD_DIR $EH2_ROOT/syn/build
set RPT_DIR $BUILD_DIR/lec_blocklevel
file mkdir $RPT_DIR

# Redirect Formality working files to a dedicated build subdir.
if {[info exists env(R3C_FM_RUN_DIR)] && $env(R3C_FM_RUN_DIR) ne ""} {
    set RUN_DIR $env(R3C_FM_RUN_DIR)
} else {
    set RUN_DIR $RPT_DIR/run/fm/shared
}
file mkdir $RUN_DIR
cd $RUN_DIR
catch {set_app_var hdlin_temporary_dir $RUN_DIR}

set R3C_SVF_PRELOADED 0

suppress_message {VER-130 VER-250 VER-26 VER-1 FMR_ELAB-147 FMR_VLOG-101}
set_app_var hdlin_sverilog_std 2012
set verification_mode relaxed
set verification_set_undriven_signals 0
set verification_clock_gate_hold_mode low

set_app_var search_path [concat \
    $RUN_DIR \
    $RPT_DIR \
    $EH2_ROOT/syn/include \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
    /home/host/Cores-VeeR-EH2/design/lib \
    [get_app_var search_path]]

puts "FM: R3-C reading technology libraries..."
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/class.db
read_db /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db

if {[info exists env(R3C_PRELOAD_SVF_FILE)] && $env(R3C_PRELOAD_SVF_FILE) ne ""} {
    if {[file exists $env(R3C_PRELOAD_SVF_FILE)]} {
        puts "FM: R3-C preloading explicit SVF guide $env(R3C_PRELOAD_SVF_FILE)"
        set_svf $env(R3C_PRELOAD_SVF_FILE)
        set R3C_SVF_PRELOADED 1
    } else {
        puts "FM: R3-C WARNING: explicit SVF guide missing: $env(R3C_PRELOAD_SVF_FILE)"
    }
} elseif {[info exists env(R3C_PRELOAD_SVF_TOP)] && $env(R3C_PRELOAD_SVF_TOP) ne ""} {
    set preload_svf $RPT_DIR/synth/$env(R3C_PRELOAD_SVF_TOP).svf
    if {[file exists $preload_svf]} {
        puts "FM: R3-C preloading block SVF guide $preload_svf"
        set_svf $preload_svf
        set R3C_SVF_PRELOADED 1
    } elseif {[file exists $EH2_ROOT/default.svf]} {
        puts "FM: R3-C WARNING: block SVF missing for $env(R3C_PRELOAD_SVF_TOP); preloading $EH2_ROOT/default.svf"
        set_svf $EH2_ROOT/default.svf
        set R3C_SVF_PRELOADED 1
    } else {
        puts "FM: R3-C WARNING: no pre-readable SVF guide available for $env(R3C_PRELOAD_SVF_TOP)"
    }
}

puts "FM: R3-C reading reference design from $BUILD_DIR/eh2_dc_wrapper.sv"
read_sverilog -r -libname WORK $BUILD_DIR/eh2_dc_wrapper.sv

proc r3c_load_svf {top} {
    global RPT_DIR EH2_ROOT R3C_SVF_PRELOADED
    if {$R3C_SVF_PRELOADED} {
        puts "FM: R3-C SVF guide already preloaded for $top"
        return
    }
    set block_svf $RPT_DIR/synth/${top}.svf
    if {[file exists $block_svf]} {
        puts "FM: R3-C loading block SVF guide $block_svf"
        if {[catch {set_svf $block_svf} msg]} {
            puts "FM: R3-C WARNING: set_svf failed for $top: $msg"
        }
    } elseif {[file exists $EH2_ROOT/default.svf]} {
        puts "FM: R3-C WARNING: block SVF missing for $top; falling back to $EH2_ROOT/default.svf"
        if {[catch {set_svf $EH2_ROOT/default.svf} msg]} {
            puts "FM: R3-C WARNING: set_svf failed for default.svf: $msg"
        }
    } else {
        puts "FM: R3-C WARNING: no SVF guide available for $top"
    }
}

proc r3c_read_impl {top} {
    global BUILD_DIR RPT_DIR env
    set block_ddc $RPT_DIR/synth/${top}.ddc
    set block_netlist $RPT_DIR/synth/${top}.v
    if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
        puts "FM: R3-C reading forced top-context implementation from $BUILD_DIR/eh2_synth.v"
        read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
    } elseif {[info exists env(R3C_FORCE_VERILOG_IMPL)] && $env(R3C_FORCE_VERILOG_IMPL) eq "1" && [file exists $block_netlist]} {
        puts "FM: R3-C reading forced standalone Verilog implementation from $block_netlist"
        read_verilog -i -libname WORK $block_netlist
    } elseif {[file exists $block_ddc]} {
        puts "FM: R3-C reading standalone block DDC implementation from $block_ddc"
        read_ddc -i -libname WORK $block_ddc
    } elseif {[file exists $block_netlist]} {
        puts "FM: R3-C reading standalone block implementation from $block_netlist"
        read_verilog -i -libname WORK $block_netlist
    } else {
        puts "FM: R3-C reading top-context implementation from $BUILD_DIR/eh2_synth.v"
        puts "FM: R3-C WARNING: no standalone block netlist found for $top"
        read_verilog -i -libname WORK $BUILD_DIR/eh2_synth.v
    }
}

proc r3c_set_impl_top {top} {
    global RPT_DIR env
    set suffixed ${top}_
    if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
        puts "FM: R3-C using forced top-context implementation top $suffixed"
        set_top i:/WORK/$suffixed
    } elseif {[file exists $RPT_DIR/synth/${top}.v]} {
        puts "FM: R3-C using standalone implementation top $top"
        set_top i:/WORK/$top
    } else {
        puts "FM: R3-C using top-context implementation top $suffixed"
        set_top i:/WORK/$suffixed
    }
}

proc r3c_write_reports {label} {
    global RPT_DIR
    puts "FM: R3-C reporting $label"
    report_status > $RPT_DIR/lec_${label}.rpt
    if {[catch {report_failing_points > $RPT_DIR/lec_${label}_failing.rpt} msg]} {
        puts "FM: R3-C report_failing_points failed for $label: $msg"
    }
    if {[catch {report_failing_points -verbose > $RPT_DIR/lec_${label}_failing_verbose.rpt} msg]} {
        puts "FM: R3-C verbose failing report unsupported for $label: $msg"
    }
    report_unverified_points > $RPT_DIR/lec_${label}_unverified.rpt
}
