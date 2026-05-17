# Try multiple end + start sequences to reclaim the session.
set hw [lindex [get_hardware_names] 0]
set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSE*" $d]} { set dev $d; break }
}
puts "HW=$hw DEV=$dev"

# Force end any active sessions
puts "--- end with device args ---"
if {[catch { end_insystem_source_probe -device_name $dev -hardware_name $hw } e]} {
    puts "  end err: $e"
} else {
    puts "  end OK"
}

puts "--- end without args ---"
if {[catch { end_insystem_source_probe } e]} { puts "  $e" } else { puts "  OK" }

puts "--- start ---"
if {[catch { start_insystem_source_probe -device_name $dev -hardware_name $hw } e]} {
    puts "  start err: $e"
} else {
    puts "  start OK"
}

puts "--- read ---"
foreach idx {0 1 2 3 4} {
    if {[catch { set v [read_probe_data -instance_index $idx -value_in_hex] } err]} {
        puts "  probe $idx: ERROR $err"
    } else {
        puts "  probe $idx: $v"
    }
}

puts "--- cleanup ---"
catch { end_insystem_source_probe -device_name $dev -hardware_name $hw }
