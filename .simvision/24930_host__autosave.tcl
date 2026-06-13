
# NC-Sim Command File
# TOOL:	ncsim(64)	15.20-p001
#

set tcl_prompt1 {puts -nonewline "ncsim> "}
set tcl_prompt2 {puts -nonewline "> "}
set vlog_format %h
set vhdl_format %v
set real_precision 6
set display_unit auto
set time_unit module
set heap_garbage_size -200
set heap_garbage_time 0
set assert_report_level note
set assert_stop_level error
set autoscope yes
set assert_1164_warnings yes
set pack_assert_off {}
set severity_pack_assert_off {note warning}
set assert_output_stop_level failed
set tcl_debug_level 0
set relax_path_name 1
set vhdl_vcdmap XX01ZX01X
set intovf_severity_level ERROR
set probe_screen_format 0
set rangecnst_severity_level ERROR
set textio_severity_level ERROR
set vital_timing_checks_on 1
set vlog_code_show_force 0
set assert_count_attempts 1
set tcl_all64 false
set tcl_runerror_exit false
set assert_report_incompletes 0
set show_force 1
set force_reset_by_reinvoke 0
set tcl_relaxed_literal 0
set probe_exclude_patterns {}
set probe_packed_limit 4k
set probe_unpacked_limit 16k
set assert_internal_msg no
set svseed 1
set assert_reporting_mode 0
alias . run
alias iprof profile
alias quit exit
scope -set cdns_uvm_pkg::
stop -create -name {1:361f7564:uvm} -object cdns_uvm_pkg::cdns_uvm_data_valid -if {#cdns_uvm_pkg::uvm_break_phase == "build" && #cdns_uvm_pkg::uvm_phase_is_start == 0}
database -open -shm -into /home/host/eh2-veri/build/wave_nc_smoke/smoke_s1/waves.shm /home/host/eh2-veri/build/wave_nc_smoke/smoke_s1/waves -default
probe -create -database /home/host/eh2-veri/build/wave_nc_smoke/smoke_s1/waves core_eh2_tb_top -all -memories -depth all

simvision -input /home/host/eh2-veri/.simvision/24930_host__autosave.tcl.svcf
