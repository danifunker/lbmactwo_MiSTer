# Sample PADR (CPU last bus address) many times and print a histogram.
# Use to characterize where the CPU is spending time during the Welcome hang.
#
#   quartus_stp_tcl -t scripts/pc_histogram.tcl

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

# Take N samples as fast as JTAG allows
set N 60
array set bucket {}
for {set s 0} {$s < $N} {incr s} {
    set adr [expr 0x[read_probe_data -instance_index $padr_idx -value_in_hex]]
    # Bucket to 256-byte regions for tight loops
    set key [format "0x%08X" [expr {$adr & 0xFFFFFF00}]]
    if {[info exists bucket($key)]} {
        incr bucket($key)
    } else {
        set bucket($key) 1
    }
}
end_insystem_source_probe

# Print sorted by count desc
puts "PC histogram over $N samples:"
set pairs {}
foreach k [array names bucket] { lappend pairs [list $bucket($k) $k] }
foreach p [lsort -decreasing -integer -index 0 $pairs] {
    puts [format "  %4d  %s..%s" [lindex $p 0] [lindex $p 1] [format "0x%08X" [expr {[expr 0x[string range [lindex $p 1] 2 end]] + 0xFF}]]]
}
