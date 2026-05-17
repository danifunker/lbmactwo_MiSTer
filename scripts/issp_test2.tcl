# Test: just call get_info + read_probe_data, no start.
set hw [lindex [get_hardware_names] 0]
set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSE*" $d]} { set dev $d; break }
}
puts "HW=$hw DEV=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
puts "info: $info"

set idx 0
foreach inst $info {
    set name [lindex $inst 3]
    if {[catch { set v [read_probe_data -instance_index $idx -value_in_hex] } err]} {
        puts "  probe $idx ($name): ERROR $err"
    } else {
        puts "  probe $idx ($name): $v"
    }
    incr idx
}
