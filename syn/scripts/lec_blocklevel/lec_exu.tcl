set_app_var sh_continue_on_error false
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C block LEC exu"
set TOP eh2_exu
set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

set rtop r:/WORK/eh2_exu
set itop i:/WORK/eh2_exu
set user_match_count 0

puts "FM: R3-C adding exu exu_npc_e4 packed-array matches"
foreach bit [list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
    set_user_match ${rtop}/exu_npc_e4\[0\]\[$bit\] ${itop}/exu_npc_e4\[[expr {$bit - 1}]\]
    incr user_match_count
    set_user_match ${rtop}/exu_flush_path_final\[0\]\[$bit\] ${itop}/exu_flush_path_final\[[expr {$bit - 1}]\]
    incr user_match_count
}
set_user_match ${rtop}/exu_flush_path_final_early\[0\]\[31\] ${itop}/exu_flush_path_final_early\[0\]
incr user_match_count

puts "FM: R3-C exu user_match_count=$user_match_count"
set match_count_fh [open $RPT_DIR/lec_exu_user_match_count.txt w]
puts $match_count_fh $user_match_count
close $match_count_fh

puts "FM: R3-C matching exu"
match

puts "FM: R3-C verifying exu"
verify -level 1
r3c_write_reports exu

puts "FM: R3-C exu complete"
exit 0
