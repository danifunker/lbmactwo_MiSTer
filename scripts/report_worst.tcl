project_open LBMacTwo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
puts "==== WORST 25 SETUP PATHS (slow corner, slack<0) ===="
report_timing -setup -npaths 25 -less_than_slack 0.0 -detail summary -stdout
