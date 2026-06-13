set_app_var sh_continue_on_error false
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C block LEC lsu"
set TOP eh2_lsu
set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

set rtop r:/WORK/eh2_lsu
set itop i:/WORK/eh2_lsu
set user_match_count 0

puts "FM: R3-C adding lsu lsu_error_pkt_dc3 packed-struct matches"
foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
    set_user_match ${rtop}/lsu_error_pkt_dc3\[addr\]\[$bit\] ${itop}/lsu_error_pkt_dc3\[$bit\]
    incr user_match_count
}
foreach bit {0 1 2 3} {
    set_user_match ${rtop}/lsu_error_pkt_dc3\[mscause\]\[$bit\] ${itop}/lsu_error_pkt_dc3\[[expr {$bit + 32}]\]
    incr user_match_count
}
foreach {field idx} {
    exc_type 36
    amo_valid 37
    inst_type 38
    single_ecc_error 39
    exc_valid 40
} {
    set_user_match ${rtop}/lsu_error_pkt_dc3\[$field\] ${itop}/lsu_error_pkt_dc3\[$idx\]
    incr user_match_count
}

puts "FM: R3-C adding lsu trigger_pkt_any packed-struct input matches"
foreach trig {0 1 2 3} {
    set base [expr {$trig * 38}]
    foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
        set_user_match ${rtop}/trigger_pkt_any\[0\]\[$trig\]\[tdata2\]\[$bit\] ${itop}/trigger_pkt_any\[[expr {$base + $bit}]\]
        incr user_match_count
    }
    foreach {field idx} {
        m 32
        execute 33
        load 34
        store 35
        match 36
        select 37
    } {
        set_user_match ${rtop}/trigger_pkt_any\[0\]\[$trig\]\[$field\] ${itop}/trigger_pkt_any\[[expr {$base + $idx}]\]
        incr user_match_count
    }
}

puts "FM: R3-C lsu user_match_count=$user_match_count"
set match_count_fh [open $RPT_DIR/lec_lsu_user_match_count.txt w]
puts $match_count_fh $user_match_count
close $match_count_fh

puts "FM: R3-C matching lsu"
match

puts "FM: R3-C verifying lsu"
verify
r3c_write_reports lsu

puts "FM: R3-C lsu complete"
exit 0
