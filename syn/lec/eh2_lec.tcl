read_verilog -sv /home/host/Cores-VeeR-EH2/snapshots/default/eh2_pdef.vh
read_verilog -sv -I/home/host/Cores-VeeR-EH2/snapshots/default -I/home/host/Cores-VeeR-EH2/design/include /home/host/Cores-VeeR-EH2/design/include/eh2_def.sv
read_verilog -sv -I/home/host/Cores-VeeR-EH2/snapshots/default /home/host/eh2-veri/syn/beh_lib_syn.sv
read_verilog -sv -I/home/host/Cores-VeeR-EH2/snapshots/default /home/host/Cores-VeeR-EH2/design/lib/mem_lib.sv
read_verilog -I/home/host/Cores-VeeR-EH2/snapshots/default /home/host/Cores-VeeR-EH2/design/dmi/dmi_jtag_to_core_sync.v /home/host/Cores-VeeR-EH2/design/dmi/dmi_wrapper.v
read_verilog -sv -I/home/host/Cores-VeeR-EH2/snapshots/default /home/host/Cores-VeeR-EH2/design/dmi/rvjtag_tap.v
prep -top rvjtag_tap
design -stash gold
design -reset
read_verilog -sv /share/simcells.v
read_verilog /home/host/eh2-veri/syn/build/eh2_synth.v
prep -top rvjtag_tap
design -stash gate
design -load gold
design -copy-from gate -as rvjtag_tap_gate rvjtag_tap
equiv_make rvjtag_tap rvjtag_tap_gate equiv
equiv_induct -seq 8 equiv
equiv_status -assert equiv
