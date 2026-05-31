# Take 300 PADR samples, bucket to 64-byte regions (catches tight loops).
# This is finer than pc_histogram.tcl (256-byte buckets) and longer.

set hw ""
foreach h [get_hardware_names] {
    if {[string match "DE-SoC*" $h]} { set hw $h; break }
}
if {$hw eq ""} {
    foreach h [get_hardware_names] {
        if {![catch {get_device_names -hardware_name $h} devs]} {
            foreach d $devs { if {[string match "*5CSE*" $d]} { set hw $h; break } }
        }
        if {$hw ne ""} break
    }
}
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set padr_idx -1; set i 0
foreach inst $info {
    if {[lindex $inst 3] eq "PADR"} { set padr_idx $i; break }
    incr i
}
catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set N 300
array set bucket {}
for {set s 0} {$s < $N} {incr s} {
    set adr [expr 0x[read_probe_data -instance_index $padr_idx -value_in_hex]]
    set key [format "0x%08X" [expr {$adr & 0xFFFFFFC0}]]
    if {[info exists bucket($key)]} { incr bucket($key) } else { set bucket($key) 1 }
}
end_insystem_source_probe

puts "PC histogram over $N samples (64-byte buckets):"
set pairs {}
foreach k [array names bucket] { lappend pairs [list $bucket($k) $k] }
set i 0
foreach p [lsort -decreasing -integer -index 0 $pairs] {
    set cnt [lindex $p 0]; set k [lindex $p 1]
    puts [format "  %4d  %s" $cnt $k]
    incr i
    if {$i >= 30} break
}
