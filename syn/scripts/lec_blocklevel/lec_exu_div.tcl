set_app_var sh_continue_on_error false
set env(R3C_PRELOAD_SVF_TOP) eh2_exu_div_ctl
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C EXU sub-block LEC div"
set TOP eh2_exu_div_ctl
set LABEL exu_div
set verification_timeout_limit 0:5:0

set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

puts "FM: R3-C matching $TOP"
match

puts "FM: R3-C verifying $TOP"
verify -level 1
r3c_write_reports $LABEL

puts "FM: R3-C EXU sub-block div complete"
exit 0
