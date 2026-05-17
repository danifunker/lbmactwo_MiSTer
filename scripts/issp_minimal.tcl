set hw [lindex [get_hardware_names] 0]
puts "HW: $hw"
set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSE*" $d]} { set dev $d; break }
}
puts "DEV: $dev"

# Try WITHOUT explicit start first
puts "--- Attempt 1: no start ---"
if {[catch { set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw] } err]} {
    puts "  err: $err"
} else {
    puts "  info: $info"
}

# Try with end then start
puts "--- Attempt 2: end + start + info ---"
catch { end_insystem_source_probe -device_name $dev -hardware_name $hw }
if {[catch { start_insystem_source_probe -device_name $dev -hardware_name $hw } err]} {
    puts "  start err: $err"
}
if {[catch { set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw] } err]} {
    puts "  info err: $err"
} else {
    puts "  info: $info"
}
catch { end_insystem_source_probe -device_name $dev -hardware_name $hw }
