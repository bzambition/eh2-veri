set_app_var sh_continue_on_error false
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C block LEC dbg"
set TOP eh2_dbg
set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

puts "FM: R3-C matching dbg"
match

puts "FM: R3-C verifying dbg"
verify
r3c_write_reports dbg

puts "FM: R3-C dbg complete"
exit 0
