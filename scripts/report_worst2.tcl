project_open LBMacTwo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
foreach_in_collection p [get_timing_paths -setup -npaths 12 -less_than_slack 0.0] {
    set slk [get_path_info $p -slack]
    set from [get_node_info [get_path_info $p -from] -name]
    set to   [get_node_info [get_path_info $p -to] -name]
    puts "SLACK=$slk"
    puts "   FROM: $from"
    puts "   TO:   $to"
}
