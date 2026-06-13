# ─── EH2 Nangate 45nm SDC Constraints (issue 62) ───────────────────────────
# Clock period: 10 ns (100 MHz target for open-source flow).
# If targeting Nangate 45nm with a commercial tool (DC/Genus), lower to 2-5 ns.
#
# This SDC is referenced by the synthesis Makefile for timing-driven flows.
# For yosys open-source flow, constraints are applied via liberty+ABC.

# ─── Clock definition ──────────────────────────────────────────────────────
set CLK_NAME    clk
set CLK_PERIOD  10.0
set CLK_UNCERT  0.50

if {[info exists clk_port]} { set clk_port [get_ports $CLK_NAME] } \
else                        { set clk_port $CLK_NAME }

create_clock -name $CLK_NAME -period $CLK_PERIOD $clk_port
set_clock_uncertainty $CLK_UNCERT [get_clocks $CLK_NAME]

# ─── Reset: false path (asynchronous), input delay = 0 ─────────────────────
set RST_NAME rst_l
if {[sizeof_collection [get_ports -quiet $RST_NAME]] > 0} {
  set_input_delay 0.0 -clock $CLK_NAME [get_ports $RST_NAME]
  set_false_path -from [get_ports $RST_NAME]
}

# ─── Debug reset ───────────────────────────────────────────────────────────
set DBG_RST_NAME dbg_rst_l
if {[sizeof_collection [get_ports -quiet $DBG_RST_NAME]] > 0} {
  set_input_delay 0.0 -clock $CLK_NAME [get_ports $DBG_RST_NAME]
  set_false_path -from [get_ports $DBG_RST_NAME]
}

# ─── Input delays (non-clock, non-reset primary inputs) ────────────────────
# Apply 2.0 ns input delay to all remaining inputs
set all_in  [all_inputs]
set clk_in  [get_ports $CLK_NAME]
set skip_list [list $clk_in]
if {[sizeof_collection [get_ports -quiet $RST_NAME]] > 0} {
  lappend skip_list [get_ports $RST_NAME]
}
if {[sizeof_collection [get_ports -quiet $DBG_RST_NAME]] > 0} {
  lappend skip_list [get_ports $DBG_RST_NAME]
}
set other_in [remove_from_collection $all_in $skip_list]
if {[sizeof_collection $other_in] > 0} {
  set_input_delay 2.0 -clock $CLK_NAME $other_in
}

# ─── Output delays ─────────────────────────────────────────────────────────
# 2.5 ns output delay from all outputs
set all_out [all_outputs]
if {[sizeof_collection $all_out] > 0} {
  set_output_delay 2.5 -clock $CLK_NAME $all_out
}

# ─── Output load ───────────────────────────────────────────────────────────
set_load 0.05 [all_outputs]

# ─── False paths ───────────────────────────────────────────────────────────
# Asynchronous reset and NMI are not timing-critical
set NMI_NAME nmi_int
if {[sizeof_collection [get_ports -quiet $NMI_NAME]] > 0} {
  set_false_path -from [get_ports $NMI_NAME]
}

# ─── Input transition ──────────────────────────────────────────────────────
set_input_transition 0.2 $other_in

# ─── Operating conditions ──────────────────────────────────────────────────
# Nangate 45nm typical: 1.1V, 25C (if library supports OCs)
# set_operating_conditions -library NangateOpenCellLibrary NCCOM
