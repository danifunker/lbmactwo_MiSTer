# Read the PWR JTAG ISSP probe: first word-write byte serialization capture.
#   quartus_stp_tcl -t scripts/read_pwr.tcl
#
# PWR layout (see rtl/ncr5380.sv / rtl/scsi.v):
#   [7:0]   byte0 the target latched (first word, even byte)
#   [15:8]  byte1 the target latched (first word, odd byte)
#   [23:16] ncr5380 intended odd byte (dma_write_low_byte)
#   [24]    dma_word_latched   [25] dma_longword_latched
#   [26]    b0_seen            [27] b1_seen
#
# Diagnosis: if byte1 == byte0 (and != intended odd byte) the low byte never
# reached the target. dma_word_latched shows whether the word path engaged.

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
if {$hw ne ""} {
    foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
}
puts "hw=$hw dev=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set pwr -1
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "PWR" || $nm eq "PWR2"} { set pwr $i; puts "found probe: $nm" }
    incr i
}
if {$pwr < 0} { puts "PWR probe not found (wrong bitstream?)"; exit 1 }

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw
set raw [expr 0x[read_probe_data -instance_index $pwr -value_in_hex]]
end_insystem_source_probe

set byte0   [expr {$raw & 0xFF}]
set byte1   [expr {($raw >> 8)  & 0xFF}]
set lowb    [expr {($raw >> 16) & 0xFF}]
set wordl   [expr {($raw >> 24) & 1}]
set longl   [expr {($raw >> 25) & 1}]
set b0seen  [expr {($raw >> 26) & 1}]
set b1seen  [expr {($raw >> 27) & 1}]

puts [format "PWR raw=0x%08X" $raw]
puts [format "  byte0 (target even) = 0x%02X" $byte0]
puts [format "  byte1 (target odd)  = 0x%02X" $byte1]
puts [format "  intended odd byte   = 0x%02X (dma_write_low_byte)" $lowb]
puts [format "  dma_word_latched=%d  dma_longword_latched=%d  b0_seen=%d b1_seen=%d" $wordl $longl $b0seen $b1seen]
if {$b0seen && $b1seen} {
    if {$byte1 == $byte0 && $byte1 != $lowb} {
        puts "  => BUG: odd byte equals even byte; low byte dropped in serialization."
    } elseif {$byte1 == $lowb} {
        puts "  => OK: odd byte matches intended low byte."
    } else {
        puts "  => odd byte matches neither even nor intended-low; investigate."
    }
} else {
    puts "  => no word write captured yet (run a write first)."
}
