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
    if {$nm eq "PSC4"} { set idx(PSC4) $i }
    if {$nm eq "PSC5"} { set idx(PSC5) $i }
    if {$nm eq "PSC6"} { set idx(PSC6) $i }
    if {$nm eq "PSC7"} { set idx(PSC7) $i }
    if {$nm eq "PSC8"} { set idx(PSC8) $i }
    if {$nm eq "PSC9"} { set idx(PSC9) $i }
    if {$nm eq "PSCA"} { set idx(PSCA) $i }
    if {$nm eq "PSCB"} { set idx(PSCB) $i }
    if {$nm eq "PSCC"} { set idx(PSCC) $i }
    incr i
}

proc decode_cmd {v} {
    set s {}
    if {$v & 0x80} {lappend s READ}
    if {$v & 0x40} {lappend s WRITE}
    if {$v & 0x20} {lappend s INQUIRY}
    if {$v & 0x10} {lappend s TEST_UNIT_READY}
    if {$v & 0x08} {lappend s READ_CAPACITY}
    if {$v & 0x04} {lappend s MODE_SENSE}
    if {$v & 0x02} {lappend s UNSUPPORTED}
    if {$v & 0x01} {lappend s REQUEST_SENSE}
    if {[llength $s] == 0} {return "(none)"}
    return [join $s ,]
}

proc decode_hs2 {v} {
    set ss  [expr {($v >> 3) & 1}]
    set rm  [expr {($v >> 2) & 1}]
    set sis [expr {($v >> 1) & 1}]
    set aim [expr {$v & 1}]
    return [format "status_sent=%d reached_MSG=%d sel_in_status=%d ack_in_msg=%d" $ss $rm $sis $aim]
}

proc decode_hs {v} {
    set mcc  [expr {($v >> 4) & 0xF}]
    set cpl  [expr {($v >> 3) & 1}]
    set aic  [expr {($v >> 2) & 1}]
    set ris  [expr {($v >> 1) & 1}]
    set ais  [expr {$v & 1}]
    return [format "max_cmd_bytes=%d cmd_cpl=%d ack_in_cmd=%d req_in_status=%d ack_in_status=%d" $mcc $cpl $aic $ris $ais]
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
    if {[info exists idx(PSC4)]} {
        set s4 [rd $idx(PSC4)]
        set hs0 [expr {$s4 & 0xFF}]
        set hs1 [expr {($s4 >> 8) & 0xFF}]
        puts "           HS t0(ID6): [decode_hs $hs0]"
        puts "           HS t1(ID5): [decode_hs $hs1]"
    }
    if {[info exists idx(PSC5)]} {
        set s5 [rd $idx(PSC5)]
        set rstc [expr {($s5 >> 8) & 0xFF}]
        set h2t0 [expr {$s5 & 0xF}]
        set h2t1 [expr {($s5 >> 4) & 0xF}]
        puts [format "           BUS_RESETS=%d" $rstc]
        puts "           CMPL t0(ID6): [decode_hs2 $h2t0]"
        puts "           CMPL t1(ID5): [decode_hs2 $h2t1]"
    }
    if {[info exists idx(PSC6)]} {
        set s6 [rd $idx(PSC6)]
        set c0 [expr {$s6 & 0xFF}]
        set c1 [expr {($s6 >> 8) & 0xFF}]
        puts [format "           UNSUPPORTED opcode: t0(ID6)=0x%02X t1(ID5)=0x%02X" $c0 $c1]
    }
    if {[info exists idx(PSC7)]} {
        set s7 [expr {[rd $idx(PSC7)] & 0xFFFF}]
        puts "           NCR live: [decode_scsi $s7]"
    }
    if {[info exists idx(PSC8)]} {
        set s8 [rd $idx(PSC8)]
        set w0 [expr {$s8 & 0xFFFF}]
        set w1 [expr {($s8 >> 16) & 0xFFFF}]
        set wc 0
        if {[info exists idx(PSC9)]} { set wc [expr {[rd $idx(PSC9)] & 0xFFFF}] }
        set sig ""
        if {$w0 == 0x4552} { set sig " (Mac DDM 'ER' OK)" }
        if {$w0 == 0x5245} { set sig " (BYTE-SWAPPED 'RE')" }
        puts [format "           DISK sd_buff: word0=0x%04X word1=0x%04X  wr_strobes=%u%s" $w0 $w1 $wc $sig]
    }
    if {[info exists idx(PSCA)]} {
        set sa [rd $idx(PSCA)]
        set iack_cnt [expr {$sa & 0xFFFF}]
        set ipl_now  [expr {($sa >> 16) & 0x7}]
        set ipl_min  [expr {($sa >> 19) & 0x7}]
        set irq_seen [expr {($sa >> 22) & 0x1}]
        set iack_lvl [expr {($sa >> 24) & 0x7}]
        # cpuIPL_n is active-low encoded: level = 7 - value (111=none, 110=lvl1...)
        set lvl_now [expr {7 - $ipl_now}]
        set lvl_max [expr {7 - $ipl_min}]
        puts [format "           IRQ: ipl_now=%d(lvl%d) highest_req=lvl%d irq_ever=%d | IACK_cycles=%u last_iack_lvl=%d" \
            $ipl_now $lvl_now $lvl_max $irq_seen $iack_cnt $iack_lvl]
    }
    if {[info exists idx(PSCB)] && [info exists idx(PSCC)]} {
        set baddr [rd $idx(PSCB)]
        set bc    [rd $idx(PSCC)]
        set bcnt  [expr {($bc >> 16) & 0xFFFF}]
        set bcap  [expr {($bc >> 6) & 0x1}]
        set bfc   [expr {$bc & 0x7}]
        puts [format "           BERR: count=%u captured=%d first_addr=0x%08X first_fc=%d" $bcnt $bcap $baddr $bfc]
    }
    after 300
}
end_insystem_source_probe
