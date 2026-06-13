# ─── EH2 Yosys Synthesis TCL ────────────────────────────────────────────
# STATUS: OPEN-SOURCE-INCOMPATIBLE (yosys 0.55 cannot parse SV-2017)
# Target: eh2_veer (core wrapper, ~1500 lines SV, ~40 submodules)
#
# BLOCKER: yosys 0.55 cannot parse:
#   1. 'import eh2_pkg::*;' in module headers (all design modules)
#   2. '{...} struct literals in parameter defaults (eh2_param.vh)
#   sv2v pre-built binaries require GLIBC 2.27+ (system has 2.17)
#   See ADR-0013 for full analysis.
#
# INTENDED FLOW (when toolchain supports SV-2017):
#   step 1: sv2v or DC elaboration to produce flat Verilog-2001
#   step 2: yosys reads flat file
#   step 3: yosys synth -top eh2_veer
#
# For now, use commercial flow: make syn-dc (Design Compiler)
#
# This script will exit with error if run as-is.
# The old rvjtag_tap fake synthesis has been REMOVED.

puts "ERROR: yosys 0.55 cannot synthesize EH2 (SV-2017 unsupported)."
puts "See ADR-0013 and syn/README.md for details."
puts "Use commercial tool: make syn-dc"
exit 1
