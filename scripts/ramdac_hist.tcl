# Dump the RAMDAC write-history ring buffer via JTAG ISSP.
# The read word is {wptr[4:0], 2'b0, entry[24:0]} = 32 bits, where
#   entry[24:20] = addr[4:0]  (port = addr[2]; low bits = lane/register)
#   entry[19:18] = uds_lds     (active byte strobes)
#   entry[17:16] = ramdac_rgb  (R/G/B phase the hardware assigned)
#   entry[15:0]  = data_in       (both byte lanes)
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

proc rgbph {n} { switch $n { 0 {return R} 1 {return G} 2 {return B} default {return ?} } }

puts "idx | a\[4:0\] | port | uds_lds | rgb | data_in | hi lo | (decoded)"
for {set e 0} {$e < 32} {incr e} {
    write_source_data -instance_index $idx_rhix -value [format "%08b" $e]
    after 5
    set v [read_probe_data -instance_index $idx_rhdt -value_in_hex]
    # v is hex of {wptr[4:0],2'b0,entry[24:0]} = 32 bits
    set val   [expr 0x$v]
    set wptr  [expr {($val >> 27) & 0x1F}]
    set entry [expr {$val & 0x1FFFFFF}]
    set alo   [expr {($entry >> 20) & 0x1F}]
    set port  [expr {($entry >> 22) & 1}]   ;# addr[2] within addr[4:0] -> bit 2 of alo -> entry bit 22
    set udsl  [expr {($entry >> 18) & 0x3}]
    set rgb   [expr {($entry >> 16) & 0x3}]
    set data  [expr {$entry & 0xFFFF}]
    set hi    [expr {($data >> 8) & 0xFF}]
    set lo    [expr {$data & 0xFF}]
    set decoded [format "%s-port %s=hi0x%02x lo0x%02x" \
        [expr {$port ? "DATA" : "ADDR"}] [rgbph $rgb] $hi $lo]
    puts [format "%2d  | 0x%02x  |  %d   |   %02b    |  %s  | 0x%04x  | %02x %02x | %s   (wptr=%d)" \
        $e $alo $port $udsl [rgbph $rgb] $data $hi $lo $decoded $wptr]
}
