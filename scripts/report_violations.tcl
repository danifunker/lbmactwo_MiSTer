# Generate detailed violated-path lists from the last compile.
#   quartus_sta -t scripts/report_violations.tcl
# Writes output_files/violated_setup.txt / violated_hold.txt with the worst
# paths (summary detail: from/to node names, slack) so SDC multicycle
# patterns can be written against real node names.
project_open LBMacTwo
create_timing_netlist
read_sdc
update_timing_netlist

report_timing -setup -npaths 300 -detail summary \
    -file output_files/violated_setup.txt
report_timing -hold -npaths 100 -detail summary \
    -file output_files/violated_hold.txt

# Per-clock summaries for context
report_clock_fmax_summary -file output_files/fmax_summary.txt

delete_timing_netlist
project_close
