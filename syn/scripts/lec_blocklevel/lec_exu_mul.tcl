set_app_var sh_continue_on_error false
set env(R3C_PRELOAD_SVF_TOP) eh2_exu_mul_ctl
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C EXU sub-block LEC mul"
set TOP eh2_exu_mul_ctl
set LABEL exu_mul
if {[info exists env(R3C_REPORT_LABEL)] && $env(R3C_REPORT_LABEL) ne ""} {
    set LABEL $env(R3C_REPORT_LABEL)
}
set verification_timeout_limit 0:5:0
set verification_datapath_effort_level High
if {[info exists env(R3C_FM_STRATEGY)] && $env(R3C_FM_STRATEGY) ne ""} {
    puts "FM: R3-C using MUL alternate strategy $env(R3C_FM_STRATEGY)"
    set_app_var verification_alternate_strategy $env(R3C_FM_STRATEGY)
}
if {[info exists env(R3C_FM_PASSING_MODE)] && $env(R3C_FM_PASSING_MODE) ne ""} {
    puts "FM: R3-C using MUL passing mode $env(R3C_FM_PASSING_MODE)"
    set_app_var verification_passing_mode $env(R3C_FM_PASSING_MODE)
}

set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

puts "FM: R3-C matching $TOP"
match

puts "FM: R3-C verifying $TOP"
verify -level 1
r3c_write_reports $LABEL

puts "FM: R3-C EXU sub-block mul complete"
exit 0
