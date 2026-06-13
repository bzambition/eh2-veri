# DC script v3: Analyze SV RTL and elaborate eh2_veer, then dump flat Verilog for yosys
# Uses analyze -format sverilog + elaborate (DC standard flow)

set GTECH_DB /home/synopsys/syn/O-2018.06-SP1/libraries/syn/gtech.db
set_app_var target_library $GTECH_DB
set_app_var link_library [list $GTECH_DB]
set_app_var hdlin_sverilog_std 2012
set_app_var hdlin_include_directory [list \
    /home/host/Cores-VeeR-EH2/snapshots/default \
    /home/host/Cores-VeeR-EH2/design/include \
]

# Suppress common non-fatal messages
suppress_message {LINT-1 LINT-28 LINT-29 LINT-31 LINT-32 LINT-33 LINT-34}
suppress_message {VER-130 VER-131 VER-140 VER-141 VER-250 VER-318}
suppress_message {UID-401}

set WORK_DIR /home/host/eh2-veri/syn/build/DC_WORK
file mkdir $WORK_DIR

puts "DC: Analyzing RTL files..."

# Type defs (must be first)
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/snapshots/default/eh2_pdef.vh
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/include/eh2_def.sv

# Library files
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/beh_lib.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/eh2_lib.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/mem_lib.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/ahb_to_axi4.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lib/axi4_to_ahb.sv

# IFU
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_aln_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_bp_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_btb_mem.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_compress_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_iccm_mem.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_ic_mem.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_ifc_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_mem_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/ifu/eh2_ifu_tb_memread.sv

# DEC
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_csr.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_decode_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_gpr_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_ib_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_tlu_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_tlu_top.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dec/eh2_dec_trigger.sv

# EXU
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_alu_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_div_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/exu/eh2_exu_mul_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/exu/eh2_exu.sv

# LSU
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_addrcheck.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_amo.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_bus_buffer.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_bus_intf.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_clkdomain.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_dccm_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_dccm_mem.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_ecc.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_lsc_ctl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_stbuf.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/lsu/eh2_lsu_trigger.sv

# DBG
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/dbg/eh2_dbg.sv

# DMI (plain Verilog)
analyze -format verilog -work WORK /home/host/Cores-VeeR-EH2/design/dmi/dmi_jtag_to_core_sync.v
analyze -format verilog -work WORK /home/host/Cores-VeeR-EH2/design/dmi/dmi_wrapper.v
analyze -format verilog -work WORK /home/host/Cores-VeeR-EH2/design/dmi/rvjtag_tap.v

# Top-level
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/eh2_dma_ctrl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/eh2_mem.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/eh2_pic_ctrl.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/eh2_veer.sv
analyze -format sverilog -work WORK /home/host/Cores-VeeR-EH2/design/eh2_veer_wrapper.sv

puts "DC: All files analyzed. Elaborating eh2_veer..."

elaborate eh2_veer

puts "DC: Current design: [current_design]"
puts "DC: Elaboration complete. Writing flat Verilog..."

write -format verilog -hierarchy -output /home/host/eh2-veri/syn/build/eh2_golden_flat.v

puts "DC: Reporting area..."
report_area > /home/host/eh2-veri/syn/build/dc_area_report.txt

puts "DC: Done. Flat Verilog written to syn/build/eh2_golden_flat.v"
exit
