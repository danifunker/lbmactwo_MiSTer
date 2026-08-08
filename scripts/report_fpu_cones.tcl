project_open LBMacTwo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set paths [get_timing_paths -setup -npaths 3000 -less_than_slack 0.0]
array set cnt {}; array set worst {}
set n 0
foreach_in_collection p $paths {
    incr n
    set to [get_node_info [get_path_info $p -to] -name]
    set s [get_path_info $p -slack]
    # strip bit index + ~DUPLICATE to group by register name
    regsub {\[[0-9]+\].*$} $to "" base
    regsub {~.*$} $base "" base
    regsub {^.*\|} $base "" leaf
    if {[info exists cnt($leaf)]} { incr cnt($leaf) } else { set cnt($leaf) 1; set worst($leaf) $s }
    if {$s < $worst($leaf)} { set worst($leaf) $s }
}
puts "==== TOTAL violated setup paths (<0, cap 3000): $n ===="
puts "==== by destination register (count | worst slack) ===="
foreach k [lsort -command {apply {{a b} {expr {$::cnt($b) - $::cnt($a)}}}} [array names cnt]] {
    puts [format "  %-44s %5d   worst=%.3f" $k $cnt($k) $worst($k)]
}
