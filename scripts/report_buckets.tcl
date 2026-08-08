project_open LBMacTwo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set paths [get_timing_paths -setup -npaths 500 -less_than_slack 0.0]
set n 0
array set bucket {}
foreach_in_collection p $paths {
    incr n
    set to [get_node_info [get_path_info $p -to] -name]
    if {[string match "*u_fpu*" $to]} { set k "FPU(u_fpu)" } \
    elseif {[string match "*tg68*" $to]} { set k "CPU(tg68)" } \
    elseif {[string match "*sdram*" $to]} { set k "sdram" } \
    elseif {[string match "*arb*" $to] || [string match "*arbiter*" $to]} { set k "arbiter" } \
    elseif {[string match "*dataController*" $to]} { set k "dataController" } \
    else { set k "OTHER" }
    if {[info exists bucket($k)]} { incr bucket($k) } else { set bucket($k) 1 }
}
puts "==== TOTAL violated setup paths (capped 500): $n ===="
foreach k [array names bucket] { puts [format "  %-18s %d" $k $bucket($k)] }
puts "==== sample non-FPU violated endpoints ===="
set c 0
foreach_in_collection p $paths {
    set to [get_node_info [get_path_info $p -to] -name]
    if {![string match "*u_fpu*" $to] && $c < 15} {
        puts "  [get_path_info $p -slack]  -> $to"
        incr c
    }
}
