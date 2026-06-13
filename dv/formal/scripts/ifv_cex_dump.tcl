# IFV 15.20 diagnostic dump for the original RC5 24 failing properties.
#
# The installed INCISIVE152 FormalVerifier does not implement report_cex,
# write_vcd, set_active, or get_status. The supported replacement is
# assertion -show <property> -verbose -list. This script emits one verbose block
# per property and creates a build/cex_<property>.txt file documenting the
# diagnostic source for downstream review.

clock -add clk -initial 0 -period 2 -width 1
assertion -add -specification
prove

set props {
  eh2_veer.u_eh2_veer_sva.a_core_rst_active_low
  eh2_veer.u_eh2_veer_sva.a_core_rst_from_reset
  eh2_veer.u_eh2_veer_sva.a_dccm_wr_rd_mutex
  eh2_veer.u_eh2_veer_sva.a_debug_halt_track
  eh2_veer.u_eh2_veer_sva.a_dma_arvalid_stable
  eh2_veer.u_eh2_veer_sva.a_dma_awvalid_stable
  eh2_veer.u_eh2_veer_sva.a_iccm_wr_rd_mutex
  eh2_veer.u_eh2_veer_sva.a_ifu_arvalid_stable
  eh2_veer.u_eh2_veer_sva.a_ifu_awvalid_stable
  eh2_veer.u_eh2_veer_sva.a_ifu_not_both_rw
  eh2_veer.u_eh2_veer_sva.a_ifu_rvalid_accepted
  eh2_veer.u_eh2_veer_sva.a_lsu_araddr_stable
  eh2_veer.u_eh2_veer_sva.a_lsu_arvalid_stable
  eh2_veer.u_eh2_veer_sva.a_lsu_awaddr_stable
  eh2_veer.u_eh2_veer_sva.a_lsu_awvalid_stable
  eh2_veer.u_eh2_veer_sva.a_lsu_bvalid_accepted
  eh2_veer.u_eh2_veer_sva.a_lsu_rvalid_accepted
  eh2_veer.u_eh2_veer_sva.a_lsu_wdata_stable
  eh2_veer.u_eh2_veer_sva.a_lsu_wstrb_active
  eh2_veer.u_eh2_veer_sva.a_lsu_wvalid_stable
  eh2_veer.u_eh2_veer_sva.a_mhartstart_reset
  eh2_veer.u_eh2_veer_sva.a_nmi_vec_stable
  eh2_veer.u_eh2_veer_sva.a_rst_vec_stable_during_reset
  eh2_veer.u_eh2_veer_sva.a_trace_valid_addr
}

foreach prop $props {
  set fields [split $prop "."]
  set short [lindex $fields [expr {[llength $fields] - 1}]]
  set out "build/cex_${short}.txt"
  set fh [open $out "w"]
  puts $fh "Property: $prop"
  puts $fh "Diagnostic command: assertion -show $prop -verbose -list"
  puts $fh "Note: IFV 15.20 lacks report_cex/write_vcd; see build/ifv_cex_run.log for the verbose status block."
  close $fh
  puts "=== CEX_BEGIN $short ==="
  assertion -show $prop -verbose -list
  puts "=== CEX_END $short ==="
}

assertion -summary
exit
