# Verify the Mac/video SDRAM read race.
# Reads the free-running contention counters:
#   MRDT = total Mac read-cycle starts
#   MRDW = Mac read starts that began while video held SDRAM (VRAM_WAIT)
# Samples twice with a delay and reports the delta ratio, which is what
# matters (free-running counters since config).
#
#   quartus_stp_tcl -t scripts/contention_check.tcl

set hw ""
foreach h [get_hardware_names] {
    if {[regexp {^DE-SoC \[USB-\d+\]$} $h]} { set hw $h; break }
}
if {$hw eq ""} { foreach h [get_hardware_names] { if {[string match "DE-SoC*" $h]} { set hw $h; break } } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
puts "hw=$hw dev=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set idx_mrdt -1
set idx_mrdw -1
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "MRDT"} { set idx_mrdt $i }
    if {$nm eq "MRDW"} { set idx_mrdw $i }
    incr i
}
if {$idx_mrdt < 0 || $idx_mrdw < 0} { puts "MRDT/MRDW probes not found (need contention bitstream)"; exit 1 }

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rd {idx} {
    set v [read_probe_data -instance_index $idx -value_in_hex]
    return [expr 0x$v]
}

set t0 [rd $idx_mrdt]
set w0 [rd $idx_mrdw]
after 1000
set t1 [rd $idx_mrdt]
set w1 [rd $idx_mrdw]

set dt [expr {$t1 - $t0}]
set dw [expr {$w1 - $w0}]
puts "cumulative: MRDT=$t1 MRDW=$w1"
puts "delta(1s):  mac_reads=$dt  reads_during_video_wait=$dw"
if {$dt > 0} {
    puts [format "contended fraction = %.2f%%" [expr {100.0*$dw/$dt}]]
} else {
    puts "no Mac reads observed in the sample window"
}
end_insystem_source_probe
