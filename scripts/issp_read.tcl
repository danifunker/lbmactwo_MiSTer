# Read all ISSP probes via JTAG, dump as hex.
# Run from project root:
#   quartus_stp_tcl -t scripts/issp_read.tcl
# Optionally pass num_samples to poll repeatedly:
#   quartus_stp_tcl -t scripts/issp_read.tcl 20

package require ::quartus::insystem_source_probe

set num_samples [expr {[llength $argv] >= 1 ? [lindex $argv 0] : 1}]
set delay_ms    [expr {[llength $argv] >= 2 ? [lindex $argv 1] : 250}]

set hw "DE-SoC \[USB-1\]"
set dev_index 2

set hardwares [get_hardware_names]
set match ""
foreach h $hardwares {
    if {[string match "DE-SoC*" $h]} { set match $h; break }
}
if {$match eq ""} {
    puts "No DE-SoC JTAG hardware found.  Available: $hardwares"
    exit 1
}
set hw $match
puts "Using JTAG hardware: $hw"

set devices [get_device_names -hardware_name $hw]
puts "Devices: $devices"
set dev ""
foreach d $devices {
    if {[string match "*5CSE*" $d]} { set dev $d; break }
}
if {$dev eq ""} { set dev [lindex $devices 0] }
puts "Using device: $dev"

start_insystem_source_probe -device_name $dev -hardware_name $hw

set instances [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
puts "ISSP instance info (raw):"
puts "  $instances"
puts "ISSP count: [llength $instances]"

# Build a flat list of usable instance indices.  Try field 0 of each inst,
# falling back to the loop counter.
set inst_idxs {}
set inst_names {}
set i 0
foreach inst $instances {
    set idx_val $i
    set name "probe"
    catch { set idx_val [lindex $inst 0] }
    if {[llength $inst] >= 4} { catch { set name [lindex $inst 3] } }
    lappend inst_idxs  $idx_val
    lappend inst_names $name
    incr i
}
puts "Resolved indices: $inst_idxs"
puts "Resolved names:   $inst_names"

proc sample_all {dev hw idxs names tag} {
    puts "------ Sample $tag ------"
    set n [llength $idxs]
    for {set j 0} {$j < $n} {incr j} {
        set idx  [lindex $idxs  $j]
        set name [lindex $names $j]
        if {[catch {
            set val [read_probe_data -device_name $dev -hardware_name $hw -instance_index $idx]
        } err]} {
            puts "  probe $idx ($name): ERROR $err"
        } else {
            puts "  probe $idx ($name): $val"
        }
    }
}

for {set i 0} {$i < $num_samples} {incr i} {
    sample_all $dev $hw $inst_idxs $inst_names $i
    if {$num_samples > 1 && $i < $num_samples - 1} {
        after $delay_ms
    }
}

end_insystem_source_probe
