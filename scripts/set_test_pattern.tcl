# Set the JTAG-controlled video test pattern selector.
# Usage:
#   quartus_stp_tcl -t scripts/set_test_pattern.tcl <0..7>
#     0 = normal VRAM scanout (Mac's framebuffer)
#     1 = 8 vertical color bars (direct RGB)
#     2 = vertical luminance gradient
#     3 = checkerboard via CLUT[0]/CLUT[1]
#     4 = solid CLUT[1] color

set value [expr {[llength $argv] >= 1 ? [lindex $argv 0] : 0}]

set hw ""
foreach h [get_hardware_names] {
    if {[regexp {^DE-SoC \[USB-\d+\]$} $h]} { set hw $h; break }
}
if {$hw eq ""} {
    foreach h [get_hardware_names] {
        if {[string match "DE-SoC*" $h]} { set hw $h; break }
    }
}
set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSE*" $d]} { set dev $d; break }
}
puts "hw=$hw dev=$dev value=$value"

# Find the source probe named VTPN
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
puts "info: $info"
set src_idx -1
set i 0
foreach inst $info {
    if {[lindex $inst 3] eq "VTPN"} { set src_idx $i; break }
    incr i
}
if {$src_idx < 0} {
    puts "VTPN source probe not found"
    exit 1
}
puts "VTPN at instance_index=$src_idx"

# Format as 8-bit binary string (source_width=8 in the probe definition).
set bin [format "%08b" $value]
puts "Writing binary: $bin"

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw
write_source_data -instance_index $src_idx -value $bin
puts "Wrote $bin to source probe VTPN (idx=$src_idx)"
