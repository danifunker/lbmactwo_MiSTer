# Read the dbg_coldinit cold-load integrity probes (PCS0-PCS3), one shot.
#   quartus_stp_tcl -t scripts/read_coldinit.tcl
# JTAG-only: zero HPS load. See rtl/dbg_coldinit.sv for the bit layout.

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
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    foreach want {PCS0 PCS1 PCS2 PCS3} {
        if {$nm eq $want} { set idx($want) $i }
    }
    incr i
}
foreach want {PCS0 PCS1 PCS2 PCS3} {
    if {![info exists idx($want)]} { puts "MISSING probe $want"; }
}

start_insystem_source_probe -device_name $dev -hardware_name $hw
proc rd {i} { return [read_probe_data -instance_index $i -value_in_hex] }

set pcs0 [expr 0x[rd $idx(PCS0)]]
set pcs1 [expr 0x[rd $idx(PCS1)]]
set pcs2 [expr 0x[rd $idx(PCS2)]]
set pcs3 [expr 0x[rd $idx(PCS3)]]
end_insystem_source_probe -device_name $dev -hardware_name $hw

set EXPECT_SUM 0x013FFEF5
set EXPECT_WORDS 131072

set sum_ok   [expr {($pcs1 >> 31) & 1}]
set words    [expr {($pcs1 >> 12) & 0x3FFFF}]
set unlocks  [expr {($pcs1 >> 8) & 0xF}]
set mnt0     [expr {($pcs1 >> 6) & 3}]
set mnt1     [expr {($pcs1 >> 4) & 3}]
set mnt2     [expr {($pcs1 >> 2) & 3}]
set clr_done [expr {($pcs1 >> 1) & 1}]
set prdy     [expr {$pcs1 & 1}]
set t_rom    [expr {($pcs2 >> 16) & 0xFFFF}]
set t_clear  [expr {$pcs2 & 0xFFFF}]
set t_pram   [expr {($pcs3 >> 16) & 0xFFFF}]
set t_mnt0   [expr {$pcs3 & 0xFFFF}]

puts "================ COLD-LOAD INTEGRITY ================"
puts [format "ROM download sum : 0x%08X  (expect 0x%08X)  %s" \
      $pcs0 $EXPECT_SUM [expr {$pcs0 == $EXPECT_SUM ? "OK" : "** MISMATCH **"}]]
puts [format "ROM word count   : %d  (expect %d)  %s" \
      $words $EXPECT_WORDS [expr {$words == $EXPECT_WORDS ? "OK" : "** MISMATCH **"}]]
puts [format "rom_sum_ok flag  : %d" $sum_ok]
puts [format "PLL unlocks      : %d %s" $unlocks [expr {$unlocks ? "** POWER/CLOCK EVENT **" : "(none)"}]]
puts [format "mounts s0/s1/s2  : %d / %d / %d   clear_done=%d pram_ready=%d" \
      $mnt0 $mnt1 $mnt2 $clr_done $prdy]
puts "---- timeline (ms after config; 65535 = never) ----"
puts [format "rom_loaded  @ %5d ms" $t_rom]
puts [format "clear_done  @ %5d ms" $t_clear]
puts [format "pram_ready  @ %5d ms" $t_pram]
puts [format "first s0 mount @ %5d ms" $t_mnt0]
puts "====================================================="
