# Dump the RAMDAC write-history ring buffer via JTAG ISSP.
# Each entry: bit 8 = port (0=address port, 1=data port), bits 7:0 = byte.
# The read word is {wptr[4:0], 2'b0, entry[8:0]}.
#
# quartus_stp_tcl -t scripts/ramdac_hist.tcl

set hw ""
foreach h [get_hardware_names] {
    if {[regexp {^DE-SoC \[USB-\d+\]$} $h]} { set hw $h; break }
}
if {$hw eq ""} { foreach h [get_hardware_names] { if {[string match "DE-SoC*" $h]} { set hw $h; break } } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
puts "hw=$hw dev=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set idx_rhix -1
set idx_rhdt -1
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "RHIX"} { set idx_rhix $i }
    if {$nm eq "RHDT"} { set idx_rhdt $i }
    incr i
}
if {$idx_rhix < 0 || $idx_rhdt < 0} { puts "RHIX/RHDT probes not found (need v8 bitstream)"; exit 1 }

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rgb_name {seq} {
    switch $seq { 0 {return R} 1 {return G} 2 {return B} default {return ?} }
}

puts "idx | port | byte | (decoded)"
set seq 0
set slot 0
for {set e 0} {$e < 32} {incr e} {
    write_source_data -instance_index $idx_rhix -value [format "%08b" $e]
    after 5
    set v [read_probe_data -instance_index $idx_rhdt -value_in_hex]
    # v is hex of {wptr[4:0],2'b0,entry[8:0]} = 16 bits
    set val [expr 0x$v]
    set wptr [expr {($val >> 11) & 0x1F}]
    set entry [expr {$val & 0x1FF}]
    set port  [expr {($entry >> 8) & 1}]
    set byte  [expr {$entry & 0xFF}]
    if {$port == 0} {
        set decoded [format "ADDR-port: slot=0x%02x" $byte]
        set slot $byte
        set seq 0
    } else {
        set decoded [format "DATA-port: %s\[slot 0x%02x\]=0x%02x" [rgb_name $seq] $slot $byte]
        if {$seq == 2} { set seq 0; incr slot } else { incr seq }
    }
    puts [format "%2d  |  %d   | 0x%02x | %s   (wptr=%d)" $e $port $byte $decoded $wptr]
}
