# Happy-mac-reboot differential readout (dbg_wedge PRGR sources 0-5 + 13-15).
#   quartus_stp -t scripts/read_reboot_diag.tcl
# Method (MacLCii docs/handoff_cold_boot_reboot_2026-06-15.md): probes are
# cumulative PER FPGA CONFIG — each load_core is a fresh attempt. Classify the
# boot by screen (desktop/? = success, reboot/SadMac = miss), then read:
#   GOOD boot : bus_resets=1, init_entries=2, trail_frozen=0
#   MISS      : bus_resets=2+, init_entries=3+, trail_frozen=1 -> PRT1/PRT2 =
#               the driver abort path (disassemble at those ROM offsets)
# PSCW says how far the aborted transaction got on the target side.
# NOTE: write_source_data parses the value as HEX — always format %x.
set hw ""
set want "USB-Blaster"
if {[info exists ::env(MISTER_JTAG_CABLE)]} { set want $::env(MISTER_JTAG_CABLE) }
foreach h [get_hardware_names] { if {[string match "*$want*" $h]} { set hw $h; break } }
if {$hw eq ""} { puts "NO JTAG CABLE matching $want"; exit 1 }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
puts "hw=$hw dev=$dev"
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    foreach w {PADR PSTA PACT PFST PRGR} { if {$nm eq $w} { set idx($w) $i } }
    incr i
}
start_insystem_source_probe -device_name $dev -hardware_name $hw
proc rd {i} { return [expr 0x[read_probe_data -instance_index $i -value_in_hex]] }
proc prgr {pidx field} {
    write_source_data -instance_index $pidx -value [format %x $field]
    read_probe_data -instance_index $pidx -value_in_hex
    return [expr 0x[read_probe_data -instance_index $pidx -value_in_hex]]
}
set p $idx(PRGR)

puts "==== live CPU (3 samples) ===="
for {set s 1} {$s <= 3} {incr s} {
    puts [format "PC=0x%08X AS_cyc=%u" [rd $idx(PADR)] [rd $idx(PACT)]]
}

puts "==== reboot differential ===="
set prc [prgr $p 0]
set busrst  [expr {($prc >> 24) & 0xFF}]
set inits   [expr {($prc >> 16) & 0xFF}]
set frozen  [expr {$prc & 1}]
puts [format "SCSI bus resets   = %u   (good boot = 1)" $busrst]
puts [format "ROM init entries  = %u   (good cold boot baseline = 2)" $inits]
puts [format "trail frozen      = %u   (1 => a 2nd bus reset happened)" $frozen]
puts [format "PRT1 PC @ 2nd rst = 0x%06X   <- the abort caller (disassemble this)" [expr {[prgr $p 1] & 0xFFFFFF}]]
puts [format "PRT2 fetch before = 0x%06X" [expr {[prgr $p 2] & 0xFFFFFF}]]
puts [format "PRT3 init entry   = 0x%06X   (latest move #\$2700,sr)" [expr {[prgr $p 3] & 0xFFFFFF}]]

puts "==== PSCW target-side window (state at/since the 1st bus reset) ===="
set w [prgr $p 4]
set phn {IDLE CMD_IN DATA_OUT DATA_IN STATUS_OUT MESSAGE_OUT ph6 ph7}
puts [format "valid=%u  maxphase(at 1st rst)=%s  read_done=%u  sel_seen=%u" \
    [expr {($w>>31)&1}] [lindex $phn [expr {($w>>28)&7}]] [expr {($w>>27)&1}] [expr {($w>>26)&1}]]
puts [format "target reset_count=%u  last_opcode=0x%02X  live: maxphase=%s read_done=%u" \
    [expr {($w>>19)&0x7F}] [expr {($w>>11)&0xFF}] [lindex $phn [expr {($w>>8)&7}]] [expr {($w>>7)&1}]]

puts "==== hardware reset? ===="
puts [format "_cpuReset falls = %u   (LCII baseline: 0 -> reboot is software re-entry)" [expr {[prgr $p 5] & 0xFFFF}]]

puts "==== fault-vector recorder ===="
set lva [prgr $p 13]
set vname [format "offset 0x%X" $lva]
switch $lva {
    8  {set vname "BUS ERROR (vec 2)"}
    12 {set vname "ADDRESS ERROR (vec 3)"}
    16 {set vname "ILLEGAL INSTRUCTION (vec 4)"}
    44 {set vname "F-LINE (vec 11)"}
    0  {set vname "(none recorded)"}
}
puts [format "last vector = %s   faulting PC = 0x%08X   count = %u" \
    $vname [prgr $p 14] [expr {[prgr $p 15] & 0xFFFF}]]
end_insystem_source_probe
