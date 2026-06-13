set_app_var sh_continue_on_error false
set env(R3C_PRELOAD_SVF_TOP) eh2_exu_alu_ctl
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C EXU sub-block LEC alu"
set TOP eh2_exu_alu_ctl
set LABEL exu_alu

set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

set rtop r:/WORK/$TOP
set itop i:/WORK/$TOP
set user_match_count 0

puts "FM: R3-C adding alu predict_p_ff packed-struct matches"
set_user_match ${rtop}/predict_p_ff\[ataken\] ${itop}/predict_p_ff\[8\]
incr user_match_count
set_user_match ${rtop}/predict_p_ff\[misp\] ${itop}/predict_p_ff\[5\]
incr user_match_count
set_user_match ${rtop}/predict_p_ff\[hist\]\[0\] ${itop}/predict_p_ff\[11\]
incr user_match_count
set_user_match ${rtop}/predict_p_ff\[hist\]\[1\] ${itop}/predict_p_ff\[12\]
incr user_match_count

puts "FM: R3-C exu_alu user_match_count=$user_match_count"
set match_count_fh [open $RPT_DIR/lec_exu_alu_user_match_count.txt w]
puts $match_count_fh $user_match_count
close $match_count_fh

puts "FM: R3-C matching $TOP"
match

puts "FM: R3-C verifying $TOP"
verify
r3c_write_reports $LABEL

puts "FM: R3-C EXU sub-block alu complete"
exit 0
