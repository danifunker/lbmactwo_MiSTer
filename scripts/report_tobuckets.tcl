project_open LBMacTwo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set paths [get_timing_paths -setup -npaths 500 -less_than_slack 0.0]
array set b {}
foreach_in_collection p $paths {
    set to [get_node_info [get_path_info $p -to] -name]
    if {[string match "*exc_event_force_inexact*" $to]} { set k "exc_event_force_inexact_reg" } \
    elseif {[string match "*fp_reg_file_reg*" $to]} { set k "fp_reg_file_reg (CONVERSION CONE)" } \
    elseif {[string match "*operand_reg*" $to]} { set k "operand_reg" } \
    elseif {[string match "*cir_conv_src_reg*" $to]} { set k "cir_conv_src_reg (new stage)" } \
    else { set k "other u_fpu" }
    if {[info exists b($k)]} { incr b($k) } else { set b($k) 1 }
}
puts "==== 500 worst setup paths by TO-node ===="
foreach k [array names b] { puts [format "  %-38s %d" $k $b($k)] }
