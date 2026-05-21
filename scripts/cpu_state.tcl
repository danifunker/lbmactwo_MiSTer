# Read the minimal CPU-state probes (PADR/PSTA/PACT) to diagnose the hang.
# Samples a few times so we can tell if the CPU is executing or frozen.
#
#   quartus_stp_tcl -t scripts/cpu_state.tcl

set hw ""
foreach h [get_hardware_names] {
    if {[regexp {^DE-SoC \[USB-\d+\]$} $h]} { set hw $h; break }
}
if {$hw eq ""} { foreach h [get_hardware_names] { if {[string match "DE-SoC*" $h]} { set hw $h; break } } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
puts "hw=$hw dev=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "PADR"} { set idx(PADR) $i }
    if {$nm eq "PSTA"} { set idx(PSTA) $i }
    if {$nm eq "PACT"} { set idx(PACT) $i }
    if {$nm eq "PVID"} { set idx(PVID) $i }
    if {$nm eq "PVFC"} { set idx(PVFC) $i }
    if {$nm eq "PSCS"} { set idx(PSCS) $i }
    if {$nm eq "PSC2"} { set idx(PSC2) $i }
    if {$nm eq "PSC3"} { set idx(PSC3) $i }
    incr i
}

proc phname {p} {
    switch $p {0 {return IDLE} 1 {return CMD_IN} 2 {return DATA_OUT} 3 {return DATA_IN} 4 {return STATUS_OUT} 5 {return MSG_OUT} default {return ?}}
}

proc decode_scsi {v} {
    set oe   [expr {($v >> 15) & 1}]
    set sel  [expr {($v >> 14) & 1}]
    set bsy  [expr {($v >> 13) & 1}]
    set tbsy [expr {($v >> 11) & 0x3}]
    set tmnt [expr {($v >> 9)  & 0x3}]
    set adb  [expr {($v >> 8) & 1}]
    set data [expr {$v & 0xFF}]
    return [format "out_en=%d SEL=%d BSY=%d target_bsy=0x%X target_mounted=0x%X ICR.ADB=%d data_bus=0x%02X" \
        $oe $sel $bsy $tbsy $tmnt $adb $data]
}
if {![info exists idx(PADR)]} { puts "PADR/PSTA/PACT not found (need dbg_min bitstream)"; exit 1 }

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rd {i} { return [expr 0x[read_probe_data -instance_index $i -value_in_hex]] }

proc decode_sta {v} {
    set fc       [expr {($v >> 4)  & 0x7}]
    set as_n     [expr {($v >> 7)  & 1}]
    set rw       [expr {($v >> 8)  & 1}]
    set dtack_n  [expr {($v >> 9)  & 1}]
    set uds_n    [expr {($v >> 10) & 1}]
    set lds_n    [expr {($v >> 11) & 1}]
    set selFPU   [expr {($v >> 12) & 1}]
    set selRAM   [expr {($v >> 13) & 1}]
    set selROM   [expr {($v >> 14) & 1}]
    set selNuBus [expr {($v >> 15) & 1}]
    set ds0_n    [expr {($v >> 16) & 1}]
    set ds1_n    [expr {($v >> 17) & 1}]
    set mdv      [expr {($v >> 18) & 1}]
    return [format "FC=%d AS_n=%d RW=%d DTACK_n=%d UDS_n=%d LDS_n=%d | selFPU=%d selRAM=%d selROM=%d selNuBus=%d | fpu_dsack1_n=%d dsack0_n=%d | mac_dout_valid=%d" \
        $fc $as_n $rw $dtack_n $uds_n $lds_n $selFPU $selRAM $selROM $selNuBus $ds1_n $ds0_n $mdv]
}

for {set s 1} {$s <= 6} {incr s} {
    set adr [rd $idx(PADR)]
    set sta [rd $idx(PSTA)]
    set act [rd $idx(PACT)]
    puts [format "sample %d: PC/addr=0x%08X  AS_cycles=%u" $s $adr $act]
    puts "           [decode_sta $sta]"
    if {[info exists idx(PVID)]} {
        set vid [rd $idx(PVID)]
        set vfc [rd $idx(PVFC)]
        set ven  [expr {($vid >> 16) & 1}]
        set wrc  [expr {$vid & 0xFFFF}]
        set ftc  [expr {$vfc & 0xFFFF}]
        puts [format "           VIDEO: video_en=%d  vram_writes=%u  vram_fetches=%u" $ven $wrc $ftc]
    }
    if {[info exists idx(PSCS)]} {
        set sc [rd $idx(PSCS)]
        set rdv  [expr {$sc & 0xFFFF}]
        set sreg [expr {($sc >> 16) & 0x7F}]
        set img  [expr {($sc >> 24) & 0x3}]
        set sdrd [expr {($sc >> 26) & 0x3}]
        set sdwr [expr {($sc >> 28) & 0x3}]
        puts [format "           SCSI: last_reg_off=0x%02X last_read=0x%04X | img_mounted_seen=%d sd_rd_seen=%d sd_wr_seen=%d" \
            $sreg $rdv $img $sdrd $sdwr]
    }
    if {[info exists idx(PSC2)]} {
        set s2 [rd $idx(PSC2)]
        set hi  [expr {$s2 & 0xFFFF}]
        set ids [expr {($s2 >> 16) & 0xFF}]
        puts [format "           SCSI scanned IDs (bitmask, bit7=initiator)=0x%02X" $ids]
        puts "           NCR@ID6/5 sel: [decode_scsi $hi]"
    }
    if {[info exists idx(PSC3)]} {
        set s3 [rd $idx(PSC3)]
        set iord [expr {($s3 >> 4) & 0x3}]
        set iowr [expr {($s3 >> 2) & 0x3}]
        set ioack [expr {$s3 & 0x3}]
        set mp0  [expr {($s3 >> 6)  & 0x7}]
        set mp1  [expr {($s3 >> 10) & 0x7}]
        set iackseen [expr {($s3 >> 14) & 0x3}]
        set sackseen [expr {($s3 >> 16) & 0x3}]
        set cp0 [expr {($s3 >> 18) & 0x7}]
        set cp1 [expr {($s3 >> 21) & 0x7}]
        puts [format "           PHASE now: t0=%s t1=%s | max: t0=%s t1=%s | io_ack_seen=%d sd_ack_seen=%d" \
            [phname $cp0] [phname $cp1] [phname $mp0] [phname $mp1] $iackseen $sackseen]
    }
    after 300
}
end_insystem_source_probe
