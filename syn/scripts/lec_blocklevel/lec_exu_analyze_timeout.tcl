set_app_var sh_continue_on_error false
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C EXU graceful timeout analysis"
set verification_timeout_limit 0:3:0
set verification_effort_level Super_Low

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

puts "FM: R3-C EXU analyze user_match_count=$user_match_count"
match
verify -level 1
report_status > $RPT_DIR/lec_exu_timeout_status.rpt
report_unverified_points > $RPT_DIR/lec_exu_timeout_unverified.rpt
analyze_points -all -effort low -limit 30 > $RPT_DIR/lec_exu_timeout_analyze_points.rpt
report_analysis_results > $RPT_DIR/lec_exu_timeout_analysis_results.rpt
exit 0
