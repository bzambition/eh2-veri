# IFV 15.20 proof script for EH2.
#
# This intentionally uses the legacy FormalVerifier shell commands supported by
# INCISIVE152. Newer check_formal/report_cex/write_vcd commands are not
# available in this installed tool version.

puts "IFV: EH2 formal proof start"
clock -add clk -initial 0 -period 2 -width 1
assertion -add -specification
prove
assertion -summary
puts "IFV: EH2 formal proof complete"
exit
