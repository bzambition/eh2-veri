set_app_var sh_continue_on_error false
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C EXU level-0 diagnostic"
set TOP eh2_exu
set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

set rtop r:/WORK/eh2_exu
set itop i:/WORK/eh2_exu
set user_match_count 0

foreach bit [list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
    set_user_match ${rtop}/exu_npc_e4\[0\]\[$bit\] ${itop}/exu_npc_e4\[[expr {$bit - 1}]\]
    incr user_match_count
    set_user_match ${rtop}/exu_flush_path_final\[0\]\[$bit\] ${itop}/exu_flush_path_final\[[expr {$bit - 1}]\]
    incr user_match_count
}
set_user_match ${rtop}/exu_flush_path_final_early\[0\]\[31\] ${itop}/exu_flush_path_final_early\[0\]
incr user_match_count

puts "FM: R3-C EXU level-0 user_match_count=$user_match_count"
match
verify -level 0
report_status > $RPT_DIR/lec_exu_level0.rpt
report_failing_points > $RPT_DIR/lec_exu_level0_failing.rpt
report_unverified_points > $RPT_DIR/lec_exu_level0_unverified.rpt
exit 0
