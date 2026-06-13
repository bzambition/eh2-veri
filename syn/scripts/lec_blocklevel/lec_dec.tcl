set_app_var sh_continue_on_error false
source /home/host/eh2-veri/syn/scripts/lec_blocklevel/lec_common.tcl

puts "FM: R3-C block LEC dec"
set TOP eh2_dec
set_top r:/WORK/$TOP
r3c_read_impl $TOP
r3c_set_impl_top $TOP
r3c_load_svf $TOP

set rtop r:/WORK/eh2_dec
set itop i:/WORK/eh2_dec
set user_match_count 0

puts "FM: R3-C adding dec packed-struct port matches"
foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70] {
    set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_wrdata\]\[$bit\] ${itop}/dec_tlu_ic_diag_pkt\[[expr {$bit + 19}]\]
    incr user_match_count
}
foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16] {
    set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_dicawics\]\[$bit\] ${itop}/dec_tlu_ic_diag_pkt\[[expr {$bit + 2}]\]
    incr user_match_count
}
set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_rd_valid\] ${itop}/dec_tlu_ic_diag_pkt\[1\]
incr user_match_count
set_user_match ${rtop}/dec_tlu_ic_diag_pkt\[icache_wr_valid\] ${itop}/dec_tlu_ic_diag_pkt\[0\]
incr user_match_count

foreach pred {i0_predict_p_d i1_predict_p_d} {
    foreach bit [list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31] {
        set_user_match ${rtop}/${pred}\[prett\]\[$bit\] ${itop}/${pred}\[[expr {$bit + 13}]\]
        incr user_match_count
    }
    foreach bit {0 1} {
        set_user_match ${rtop}/${pred}\[hist\]\[$bit\] ${itop}/${pred}\[[expr {$bit + 11}]\]
        incr user_match_count
    }
    foreach {field idx} {
        boffset 13
        bank 10
        way 9
        ataken 8
        valid 7
        pc4 6
        misp 5
        br_error 4
        br_start_error 3
        pcall 2
        pret 1
        pja 0
    } {
        set_user_match ${rtop}/${pred}\[$field\] ${itop}/${pred}\[$idx\]
        incr user_match_count
    }
}

foreach {field idx} {
    atomic 32
    atomic64 31
    fast_int 30
    barrier 29
    lr 28
    sc 27
    dma 21
    by 20
    half 19
    word 18
    dword 17
    load 16
    store 15
    pipe 14
    unsign 13
    stack 12
    tid 11
    store_data_bypass_c1 10
    load_ldst_bypass_c1 9
    store_data_bypass_c2 8
    store_data_bypass_i0_e2_c2 7
    valid 0
} {
    set_user_match ${rtop}/lsu_p\[$field\] ${itop}/lsu_p\[$idx\]
    incr user_match_count
}
foreach bit {0 1 2 3 4} {
    set_user_match ${rtop}/lsu_p\[atomic_instr\]\[$bit\] ${itop}/lsu_p\[[expr {$bit + 22}]\]
    incr user_match_count
}
foreach bit {0 1} {
    set_user_match ${rtop}/lsu_p\[store_data_bypass_e4_c1\]\[$bit\] ${itop}/lsu_p\[[expr {$bit + 5}]\]
    incr user_match_count
    set_user_match ${rtop}/lsu_p\[store_data_bypass_e4_c2\]\[$bit\] ${itop}/lsu_p\[[expr {$bit + 3}]\]
    incr user_match_count
    set_user_match ${rtop}/lsu_p\[store_data_bypass_e4_c3\]\[$bit\] ${itop}/lsu_p\[[expr {$bit + 1}]\]
    incr user_match_count
}

foreach bit {0 1} {
    set_user_match ${rtop}/trace_rv_trace_pkt\[0\]\[trace_rv_i_valid_ip\]\[$bit\] ${itop}/trace_rv_trace_pkt\[[expr {$bit + 245}]\]
    incr user_match_count
    set_user_match ${rtop}/trace_rv_trace_pkt\[0\]\[trace_rv_i_exception_ip\]\[$bit\] ${itop}/trace_rv_trace_pkt\[[expr {$bit + 115}]\]
    incr user_match_count
    set_user_match ${rtop}/trace_rv_trace_pkt\[0\]\[trace_rv_i_interrupt_ip\]\[$bit\] ${itop}/trace_rv_trace_pkt\[[expr {$bit + 108}]\]
    incr user_match_count
}
foreach bit [list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63] {
    set_user_match ${rtop}/trace_rv_trace_pkt\[0\]\[trace_rv_i_address_ip\]\[$bit\] ${itop}/trace_rv_trace_pkt\[[expr {$bit + 117}]\]
    incr user_match_count
}

puts "FM: R3-C dec user_match_count=$user_match_count"
set match_count_fh [open $RPT_DIR/lec_dec_user_match_count.txt w]
puts $match_count_fh $user_match_count
close $match_count_fh

puts "FM: R3-C matching dec"
match

puts "FM: R3-C verifying dec"
verify
r3c_write_reports dec

puts "FM: R3-C dec complete"
exit 0
