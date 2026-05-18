# Force CLUT[0] = white and CLUT[1] = black via JTAG override.
# Usage:
#   quartus_stp_tcl -t scripts/force_clut.tcl on    -- enable (white/black)
#   quartus_stp_tcl -t scripts/force_clut.tcl off   -- disable, use Mac's CLUT
#   quartus_stp_tcl -t scripts/force_clut.tcl c0=RRGGBB c1=RRGGBB
#                                                  -- set specific colors
set mode "off"
if {[llength $argv] >= 1} {
    set first [lindex $argv 0]
    if {$first eq "on" || $first eq "off"} { set mode $first }
}

set c0 0xFFFFFF
set c1 0x000000

# parse c0=... c1=... args
foreach arg $argv {
    if {[regexp {^c0=([0-9A-Fa-f]+)$} $arg -> hex]}  { set c0 0x$hex; set mode "on" }
    if {[regexp {^c1=([0-9A-Fa-f]+)$} $arg -> hex]}  { set c1 0x$hex; set mode "on" }
}

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
puts "hw=$hw dev=$dev mode=$mode c0=$c0 c1=$c1"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set idx_clue -1
set idx_cluf -1
set i 0
foreach inst $info {
    if {[lindex $inst 3] eq "CLUE"} { set idx_clue $i }
    if {[lindex $inst 3] eq "CLUF"} { set idx_cluf $i }
    incr i
}
if {$idx_clue < 0 || $idx_cluf < 0} {
    puts "CLUE/CLUF source probes not found (need v6+ bitstream)"
    exit 1
}
puts "CLUE idx=$idx_clue CLUF idx=$idx_cluf"

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw

if {$mode eq "off"} {
    set enable 0
} else {
    set enable 1
}

# CLUE: { enable, 7'd0, R[7:0], G[7:0], B[7:0] }
set c0_val [expr {($enable << 31) | (($c0 & 0xFFFFFF))}]
set c1_val [expr {($c1 & 0xFFFFFF)}]
set c0_bin [format "%032b" [expr {$c0_val & 0xFFFFFFFF}]]
set c1_bin [format "%032b" [expr {$c1_val & 0xFFFFFFFF}]]
puts "Writing CLUE=$c0_bin"
puts "Writing CLUF=$c1_bin"
write_source_data -instance_index $idx_clue -value $c0_bin
write_source_data -instance_index $idx_cluf -value $c1_bin
puts "Done."
