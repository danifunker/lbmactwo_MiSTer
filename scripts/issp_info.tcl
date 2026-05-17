# Just dump the ISSP instance info -- helps debug the probe-naming/index issue.
# quartus_stp_tcl -t scripts/issp_info.tcl

set hw ""
foreach h [get_hardware_names] {
    if {[string match "DE-SoC*" $h]} { set hw $h; break }
}
if {$hw eq ""} {
    set hws [get_hardware_names]
    set hw [lindex $hws 0]
}
puts "hardware = $hw"

set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSE*" $d]} { set dev $d; break }
}
if {$dev eq ""} {
    set dev [lindex [get_device_names -hardware_name $hw] 0]
}
puts "device = $dev"

start_insystem_source_probe -device_name $dev -hardware_name $hw

set list [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
puts "raw info list:"
puts "  $list"
puts ""
puts "decoded:"
set i 0
foreach inst $list {
    puts "  idx=$i length=[llength $inst]  fields=$inst"
    incr i
}

# Try reading each
puts ""
puts "single read of each probe:"
set i 0
foreach inst $list {
    if {[catch {
        set v [read_probe_data -device_name $dev -hardware_name $hw -instance_index $i]
    } err]} {
        puts "  idx=$i read ERROR: $err"
    } else {
        puts "  idx=$i value: $v"
    }
    incr i
}

end_insystem_source_probe
