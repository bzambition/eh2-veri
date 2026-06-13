set_app_var sh_continue_on_error false
set env(R3C_PRELOAD_SVF_TOP) eh2_ifu
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C block LEC ifu"
set TOP eh2_ifu
set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

puts "FM: R3-C matching ifu before explicit packed-array matches"
match

if {[info exists env(R3C_FORCE_TOP_CONTEXT_IMPL)] && $env(R3C_FORCE_TOP_CONTEXT_IMPL) eq "1"} {
    set rtop r:/WORK/eh2_ifu_
    set itop i:/WORK/eh2_ifu_
} elseif {[file exists $RPT_DIR/synth/${TOP}.v]} {
    set rtop r:/WORK/eh2_ifu
    set itop i:/WORK/eh2_ifu
} else {
    set rtop r:/WORK/eh2_ifu
    set itop i:/WORK/eh2_ifu_
}
set user_match_count 0

puts "FM: R3-C adding IFU ic_wr_data user matches"
foreach way {0 1} {
    for {set bit 0} {$bit < 71} {incr bit} {
        set flat_idx [expr {$way * 71 + $bit}]
        set_user_match ${rtop}/ic_wr_data\[$way\]\[$bit\] ${itop}/ic_wr_data\[$flat_idx\]
        incr user_match_count
    }
}

puts "FM: R3-C adding IFU btb_rw_addr user matches"
foreach way {0 1} {
    for {set bit 1} {$bit <= 9} {incr bit} {
        set flat_idx [expr {$way * 9 + ($bit - 1)}]
        set_user_match ${rtop}/btb_rw_addr\[$way\]\[$bit\] ${itop}/btb_rw_addr\[$flat_idx\]
        incr user_match_count
    }
}

puts "FM: R3-C adding IFU btb_rw_addr_f1 user matches"
foreach way {0 1} {
    for {set bit 1} {$bit <= 9} {incr bit} {
        set flat_idx [expr {$way * 9 + ($bit - 1)}]
        set_user_match ${rtop}/btb_rw_addr_f1\[$way\]\[$bit\] ${itop}/btb_rw_addr_f1\[$flat_idx\]
        incr user_match_count
    }
}

puts "FM: R3-C adding IFU btb_sram_rd_tag_f1 user matches"
foreach way {0 1} {
    for {set bit 0} {$bit < 5} {incr bit} {
        set flat_idx [expr {$way * 5 + $bit}]
        set_user_match ${rtop}/btb_sram_rd_tag_f1\[$way\]\[$bit\] ${itop}/btb_sram_rd_tag_f1\[$flat_idx\]
        incr user_match_count
    }
}

proc r3c_ifu_add_brp_matches {rtop itop port_name user_match_count_name} {
    upvar $user_match_count_name user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[way\] ${itop}/${port_name}\[0\]
    incr user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[hist\]\[0\] ${itop}/${port_name}\[1\]
    incr user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[hist\]\[1\] ${itop}/${port_name}\[2\]
    incr user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[valid\] ${itop}/${port_name}\[3\]
    incr user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[bank\] ${itop}/${port_name}\[4\]
    incr user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[br_start_error\] ${itop}/${port_name}\[5\]
    incr user_match_count
    set_user_match ${rtop}/${port_name}\[0\]\[br_error\] ${itop}/${port_name}\[6\]
    incr user_match_count
    for {set bit 1} {$bit <= 31} {incr bit} {
        set flat_idx [expr {$bit + 6}]
        set_user_match ${rtop}/${port_name}\[0\]\[prett\]\[$bit\] ${itop}/${port_name}\[$flat_idx\]
        incr user_match_count
    }
    set_user_match ${rtop}/${port_name}\[0\]\[ret\] ${itop}/${port_name}\[38\]
    incr user_match_count
}

puts "FM: R3-C adding IFU branch packet user matches"
r3c_ifu_add_brp_matches $rtop $itop i0_brp user_match_count
r3c_ifu_add_brp_matches $rtop $itop i1_brp user_match_count

puts "FM: R3-C adding IFU FA index user matches"
foreach port_name {ifu_i0_bp_fa_index ifu_i1_bp_fa_index} {
    for {set bit 0} {$bit < 9} {incr bit} {
        set_user_match ${rtop}/${port_name}\[0\]\[$bit\] ${itop}/${port_name}\[$bit\]
        incr user_match_count
    }
}

puts "FM: R3-C ifu user_match_count=$user_match_count"
set match_count_fh [open $RPT_DIR/lec_ifu_user_match_count.txt w]
puts $match_count_fh $user_match_count
close $match_count_fh

puts "FM: R3-C matching ifu after explicit packed-array matches"
match

puts "FM: R3-C verifying ifu"
verify
r3c_write_reports ifu

puts "FM: R3-C ifu complete"
exit 0
