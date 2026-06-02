# Read the minimal CPU-state probes (PADR/PSTA/PACT) to diagnose the hang.
# Samples a few times so we can tell if the CPU is executing or frozen.
#
#   quartus_stp_tcl -t scripts/cpu_state.tcl

# Pick the cable + device portably: prefer a DE-SoC cable (Alan's on-board
# USB-Blaster II), else fall back to any cable (e.g. a standalone "USB-Blaster
# [USB-0]"). For whichever cable, take the first device whose name matches the
# Cyclone V (5CSE). This works on any machine regardless of cable name.
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
    if {$nm eq "PSCE"} { set idx(PSCE) $i }
    if {$nm eq "PSCF"} { set idx(PSCF) $i }
    if {$nm eq "PSCG"} { set idx(PSCG) $i }
    if {$nm eq "PSCH"} { set idx(PSCH) $i }
    if {$nm eq "PADB"} { set idx(PADB) $i }
    if {$nm eq "PAD2"} { set idx(PAD2) $i }
    if {$nm eq "PAD3"} { set idx(PAD3) $i }
    if {$nm eq "PVBL"} { set idx(PVBL) $i }
    if {$nm eq "PASC"} { set idx(PASC) $i }
    if {$nm eq "PAUD"} { set idx(PAUD) $i }
    if {$nm eq "PMSE"} { set idx(PMSE) $i }
    if {$nm eq "PSLT"} { set idx(PSLT) $i }
    if {$nm eq "PADP"} { set idx(PADP) $i }
    if {$nm eq "PSRR"} { set idx(PSRR) $i }
    if {$nm eq "PSRL"} { set idx(PSRL) $i }
    if {$nm eq "PFLP"} { set idx(PFLP) $i }
    if {$nm eq "PIWM"} { set idx(PIWM) $i }
    if {$nm eq "PIOA"} { set idx(PIOA) $i }
    if {$nm eq "PIOC"} { set idx(PIOC) $i }
    if {$nm eq "PFLT"} { set idx(PFLT) $i }
    if {$nm eq "PIR1"} { set idx(PIR1) $i }
    if {$nm eq "PIR2"} { set idx(PIR2) $i }
    if {$nm eq "PIR3"} { set idx(PIR3) $i }
    if {$nm eq "PIPL"} { set idx(PIPL) $i }
    if {$nm eq "PIRQ"} { set idx(PIRQ) $i }
    if {$nm eq "PSCC"} { set idx(PSCC) $i }
    if {$nm eq "PIOH"} { set idx(PIOH) $i }
    if {$nm eq "PMEM"} { set idx(PMEM) $i }
    # Quartus truncates altsource_probe instance_id to 4 chars; PMEM2 -> MEM2.
    if {$nm eq "MEM2"} { set idx(PMEM2) $i }
    # Build #13 — IF-only PC sampler
    if {$nm eq "PIFA"} { set idx(PIFA) $i }
    if {$nm eq "PIFC"} { set idx(PIFC) $i }
    # Build #14 — FPU CIR Response/Restore confirmation probes
    if {$nm eq "PFRR"} { set idx(PFRR) $i }
    if {$nm eq "PFRW"} { set idx(PFRW) $i }
    # Build #16 — FPU CIR FSM state probe
    if {$nm eq "PFST"} { set idx(PFST) $i }
    # Build #22 — Coprocessor Control CIR ACK observability probe
    if {$nm eq "PCAK"} { set idx(PCAK) $i }
    # Build #27 — FPU detection probe (bug #6: coprocessor not installed)
    if {$nm eq "PFPD"} { set idx(PFPD) $i }
    incr i
}

# signed 16-bit interpretation helper
proc s16 {v} { set v [expr {$v & 0xFFFF}]; if {$v >= 32768} { return [expr {$v - 65536}] }; return $v }

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
    if {[info exists idx(PVBL)]} {
        set vb [rd $idx(PVBL)]
        set ackc [expr {$vb & 0xFFFF}]
        set irqc [expr {($vb >> 16) & 0x7FFF}]
        set vblen [expr {($vb >> 31) & 1}]
        puts [format "           CARD: vbl_irq_enabled=%d  vbl_irq_count=%u  bus_acks=%u" $vblen $irqc $ackc]
    }
    if {[info exists idx(PASC)]} {
        set pa [rd $idx(PASC)]
        set ascwr  [expr {$pa & 0xFFFF}]
        set ascirq [expr {($pa >> 16) & 0xFFFF}]
        puts [format "           ASC: refill_irqs=%u  cpu_writes=%u  (irqs>>writes => FIFO underrun)" $ascirq $ascwr]
    }
    if {[info exists idx(PAUD)]} {
        set au [rd $idx(PAUD)]
        set amin [s16 [expr {$au & 0xFFFF}]]
        set amax [s16 [expr {($au >> 16) & 0xFFFF}]]
        puts [format "           AUDIO: left_sample_min=%d  left_sample_max=%d  (range over run)" $amin $amax]
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
        puts [format "           LAST opcode: t0(ID6)=0x%02X t1(ID5)=0x%02X" $c0 $c1]
    }
    if {[info exists idx(PSC7)]} {
        set s7 [expr {[rd $idx(PSC7)] & 0xFFFF}]
        puts "           NCR live: [decode_scsi $s7]"
    }
    if {[info exists idx(PSC8)]} {
        set s8 [rd $idx(PSC8)]
        set w0 [expr {$s8 & 0xFFFF}]
        set wc [expr {($s8 >> 16) & 0xFFFF}]
        puts [format "           DISK sd_buff: word0=0x%04X  wr_strobes=%u" $w0 $wc]
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
        set blast [rd $idx(PSCB)]
        set bc    [rd $idx(PSCC)]
        set bcnt  [expr {($bc >> 16) & 0xFFFF}]
        set sseen [expr {($bc >> 7) & 0x1}]
        set sfc   [expr {($bc >> 4) & 0x7}]
        set lfc   [expr {$bc & 0x7}]
        set bsusp 0
        if {[info exists idx(PSCD)]} { set bsusp [rd $idx(PSCD)] }
        puts [format "           BERR: count=%u | last_addr=0x%08X(fc%d) | susp_nonslot=%d susp_addr=0x%08X(fc%d)" \
            $bcnt $blast $lfc $sseen $bsusp $sfc]
    }
    if {[info exists idx(PSCE)]} {
        set se [rd $idx(PSCE)]
        set s6a [expr {$se & 0xFF}]
        set s6o [expr {($se >> 8) & 0xFF}]
        set s5a [expr {($se >> 16) & 0xFF}]
        set s5o [expr {($se >> 24) & 0xFF}]
        puts [format "           RESEL: ID6 attempts=%u ok=%u | ID5 attempts=%u ok=%u (ok<attempts => disk re-selection FAILING)" \
            $s6a $s6o $s5a $s5o]
    }
    if {[info exists idx(PSCF)]} {
        set sf [rd $idx(PSCF)]
        set rseen [expr {($sf >> 24) & 0xFF}]
        set ph0r  [expr {($sf >> 8)  & 0x7}]
        set ph1r  [expr {($sf >> 11) & 0x7}]
        set iordr [expr {($sf >> 4)  & 0x3}]
        set iowrr [expr {($sf >> 2)  & 0x3}]
        puts [format "           RST-SNAP: resets_seen=%u | at last reset: phase t0=%s t1=%s io_rd=%d io_wr=%d" \
            $rseen [phname $ph0r] [phname $ph1r] $iordr $iowrr]
    }
    if {[info exists idx(PSCG)] && [info exists idx(PSCH)]} {
        set i1 [rd $idx(PSCG)]
        set i0 [rd $idx(PSCH)]
        set vnote ""
        if {$i1 == 0}    { set vnote " <- video decl ROM NOT loaded!" }
        if {$i1 > 0 && $i1 < 6144} { set vnote " <- looks like wrong/small ROM (Toby=4096?)" }
        if {$i1 >= 6144} { set vnote " <- Hi-Res decl ROM loaded OK" }
        puts [format "           ROMLOAD: boot0(sys idx0)=%u writes | boot1(video decl idx1)=%u writes%s" $i0 $i1 $vnote]
    }
    if {[info exists idx(PADB)]} {
        set ad [rd $idx(PADB)]
        set cmd_byte  [expr {$ad & 0xFF}]
        set adb_st    [expr {($ad >> 8) & 0x3}]
        set cmd_valid [expr {($ad >> 10) & 1}]
        set cmd_proc  [expr {($ad >> 11) & 1}]
        set listen    [expr {($ad >> 12) & 1}]
        set din_str   [expr {($ad >> 13) & 1}]
        set dout_str  [expr {($ad >> 14) & 1}]
        set adb_int   [expr {($ad >> 15) & 1}]
        set sr_shadow [expr {($ad >> 16) & 0xFF}]
        set sr_pend   [expr {($ad >> 24) & 1}]
        set sr_ack    [expr {($ad >> 25) & 1}]
        set sr_done   [expr {($ad >> 26) & 1}]
        set sr_active [expr {($ad >> 27) & 1}]
        set shift_dir [expr {($ad >> 28) & 1}]
        set acr_mode  [expr {($ad >> 29) & 0x7}]
        set stname    [lindex {COMMAND DATA1 DATA2 IDLE} $adb_st]
        puts [format "           ADB: st=%s cmd_byte=0x%02X cmd_valid=%d cmd_proc=%d listen=%d _int=%d | din_str=%d dout_str=%d" \
            $stname $cmd_byte $cmd_valid $cmd_proc $listen $adb_int $din_str $dout_str]
        puts [format "           VIA1-SR: acr_mode=%d shift_dir=%d sr_active=%d sr_out(pending=%d ack=%d done=%d) sr_shadow=0x%02X" \
            $acr_mode $shift_dir $sr_active $sr_pend $sr_ack $sr_done $sr_shadow]
    }
    if {[info exists idx(PAD2)]} {
        set a2 [rd $idx(PAD2)]
        set din_cnt  [expr {$a2 & 0xFFF}]
        set dout_cnt [expr {($a2 >> 12) & 0xFFF}]
        set pend_cnt [expr {($a2 >> 24) & 0xFF}]
        puts [format "           ADB counts: din_strobe=%u dout_strobe=%u sr_out_pending=%u" $din_cnt $dout_cnt $pend_cnt]
    }
    if {[info exists idx(PAD3)]} {
        set a3 [rd $idx(PAD3)]
        set shtimer  [expr {$a3 & 0x1FFFF}]
        set cplcnt   [expr {($a3 >> 17) & 0x7FFF}]
        puts [format "           SHIFT-IN: via1_shift_timer=%u  sr_ext_complete_count=%u" $shtimer $cplcnt]
    }
    if {[info exists idx(PMSE)]} {
        set pm [rd $idx(PMSE)]
        set mhe   [expr {$pm & 0xFFFF}]
        set ps2m  [expr {($pm >> 16) & 0xFFFF}]
        puts [format "           MOUSE: ps2m24_toggles=%u  mouse_has_event_pulses=%u" $ps2m $mhe]
    }
    if {[info exists idx(PSLT)]} {
        set sl [rd $idx(PSLT)]
        set last_reg  [expr {$sl & 0xFFFF}]
        set cnt_148   [expr {($sl >> 16) & 0xFF}]
        set cnt_13c   [expr {($sl >> 24) & 0x7F}]
        set sticky    [expr {($sl >> 31) & 0x1}]
        puts [format "           SLOT-E REG: last_reg=0x%04X wr_0x0148=%u(sat255) wr_0x013C=%u(sat127) sticky_148=%d" \
            $last_reg $cnt_148 $cnt_13c $sticky]
    }
    if {[info exists idx(PADP)]} {
        set pp [rd $idx(PADP)]
        set kbd_poll   [expr {$pp & 0xFF}]
        set mouse_poll [expr {($pp >> 8) & 0xFF}]
        set lastp      [expr {($pp >> 16) & 0xFF}]
        set lastc      [expr {($pp >> 24) & 0xFF}]
        puts [format "           ADB POLL: last_cmd=0x%02X prev_distinct=0x%02X mouse_polls(0x3C)=%u(sat255) kbd_polls(0x2C)=%u(sat255)" \
            $lastc $lastp $mouse_poll $kbd_poll]
    }
    if {[info exists idx(PSRR)]} {
        set rr [rd $idx(PSRR)]
        set r0 [expr {$rr & 0xFF}]
        set r1 [expr {($rr >> 8) & 0xFF}]
        set r2 [expr {($rr >> 16) & 0xFF}]
        set r3 [expr {($rr >> 24) & 0xFF}]
        puts [format "           SR READ seq (newest->oldest): %02X %02X %02X %02X" $r0 $r1 $r2 $r3]
    }
    if {[info exists idx(PSRL)]} {
        set ll [rd $idx(PSRL)]
        set l0 [expr {$ll & 0xFF}]
        set l1 [expr {($ll >> 8) & 0xFF}]
        set l2 [expr {($ll >> 16) & 0xFF}]
        set l3 [expr {($ll >> 24) & 0xFF}]
        puts [format "           SR LOAD seq (newest->oldest): %02X %02X %02X %02X" $l0 $l1 $l2 $l3]
    }
    if {[info exists idx(PFLP)]} {
        set fp [rd $idx(PFLP)]
        set miss  [expr {$fp & 0xFFFF}]
        set bytes [expr {($fp >> 16) & 0xFFFF}]
        puts [format "           FLP: byte_cnt=%u  slot_miss_cnt=%u  (miss>0 + bytes stalled => SDRAM-feed starving the IWM byte slot)" $bytes $miss]
    }
    if {[info exists idx(PIWM)]} {
        set iw [rd $idx(PIWM)]
        set armh  [expr {$iw & 0x7F}]
        set staged [expr {($iw >> 7) & 0x1}]
        set latch [expr {($iw >> 8) & 0xFF}]
        set acks  [expr {($iw >> 16) & 0xFFFF}]
        set latch_bit7 [expr {($latch >> 7) & 0x1}]
        puts [format "           IWM: sdram_grants=%u  readDataLatch=0x%02X(bit7=%d/byte_avail)  staged=%d  armDelayHi=0x%02X" \
            $acks $latch $latch_bit7 $staged $armh]
    }
    if {[info exists idx(PIOA)]} {
        set io [rd $idx(PIOA)]
        set iorb [expr {$io - 0x10}]
        puts [format "           IORB: last (a0+0x10) seen after IOWait fetch = 0x%08X -> IORB at 0x%08X" \
            $io $iorb]
    }
    if {[info exists idx(PIOC)]} {
        set ic [rd $idx(PIOC)]
        set iters [expr {$ic & 0xFFFF}]
        puts [format "           IOWait: iter_cnt(wrap16)=%u (growing => IOWait actively polling)" $iters]
    }
    if {[info exists idx(PFLT)]} {
        set ft [rd $idx(PFLT)]
        set steps [expr {$ft & 0xFFFF}]
        set armh  [expr {($ft >> 16) & 0x7F}]
        set side  [expr {($ft >> 23) & 0x1}]
        set trk   [expr {($ft >> 24) & 0x7F}]
        set staged [expr {($ft >> 31) & 0x1}]
        puts [format "           FLT: driveTrack=%u(0x%02X) side=%u  step_cnt(wrap16)=%u  staged=%d  armDelayHi=0x%02X" \
            $trk $trk $side $steps $staged $armh]
    }
    if {[info exists idx(PIR1)]} {
        set i1 [rd $idx(PIR1)]
        set cnt [expr {$i1 & 0xFFFF}]
        set val [expr {($i1 >> 16) & 0xFFFF}]
        puts [format "           IOR: \$3B4 write_cnt(wrap16)=%u  last_value=0x%04X  (cnt=0 => ioResult NEVER set; cnt>0 => driver completes)" \
            $cnt $val]
    }
    if {[info exists idx(PIR2)]} {
        # PIR2 watches the address PIOA most recently captured (the
        # CURRENTLY-polled IORB's ioResult, whatever address it is at).
        set i2  [rd $idx(PIR2)]
        set cnt [expr {$i2 & 0xFFFF}]
        set val [expr {($i2 >> 16) & 0xFFFF}]
        # Re-read PIOA so the printed address matches what PIR2 is tracking
        # right now (PIOA may have shifted since the PIR1/PFLT/etc reads
        # above, but they are tied together by the same iowait_data_addr).
        set dynaddr 0
        set dynior  0
        if {[info exists idx(PIOA)]} {
            set dynaddr [rd $idx(PIOA)]
            set dynior  [expr {$dynaddr - 0x10}]
        }
        puts [format "           IOR2: dyn ioResult @ 0x%08X (IORB 0x%08X) write_cnt(wrap16)=%u  last_value=0x%04X" \
            $dynaddr $dynior $cnt $val]
        puts "                 cnt=0 (delta) over a 1-min soak => driver for THIS IORB never IODone's; identify via ioRefNum @ IORB+0x18"
        puts "                 cnt>0 + growing                  => driver IS completing; hang is deeper than IOWait spin"
    }
    if {[info exists idx(PIR3)]} {
        # PIR3: CPU reads at (iowait_data_addr + 0x08) = IORB+0x18 = ioRefNum.
        set i3 [rd $idx(PIR3)]
        set rcnt [expr {$i3 & 0xFFFF}]
        set rval [expr {($i3 >> 16) & 0xFFFF}]
        # Refnum is signed 16-bit
        set rsig $rval
        if {$rsig >= 32768} { set rsig [expr {$rsig - 65536}] }
        set drvname "(unknown)"
        switch -- $rsig {
            -33 {set drvname ".Sony (floppy)"}
            -34 {set drvname ".Print"}
            -35 {set drvname ".Sound (early)"}
            -36 {set drvname ".Sound"}
            -37 {set drvname ".MPP (AppleTalk)"}
            -38 {set drvname ".SCSI"}
            -39 {set drvname ".ATP (AppleTalk)"}
            -50 {set drvname "AppleTalk async"}
            -51 {set drvname "AppleTalk sync"}
            -67 {set drvname ".XPP"}
            0   {set drvname "(no read seen yet)"}
        }
        puts [format "           IOR3: refnum_rd_cnt(wrap16)=%u  last_value=0x%04X (%d) => %s" \
            $rcnt $rval $rsig $drvname]
        if {$rcnt == 0} {
            puts "                 cnt=0 => OS hasn't re-fetched ioRefNum within current iowait_data_addr window"
        }
    }
    if {[info exists idx(PIPL)]} {
        set pi  [rd $idx(PIPL)]
        set cyc [expr {$pi & 0xFFFF}]
        set llv [expr {($pi >> 16) & 0x7}]
        set iac [expr {($pi >> 20) & 0xFF}]
        set bm  [expr {($pi >> 24) & 0xFF}]
        set bms ""
        for {set b 1} {$b <= 7} {incr b} {
            if {$bm & (1 << $b)} { lappend bms "lvl$b" }
        }
        if {$bms eq ""} { set bmstr "(none)" } else { set bmstr [join $bms ,] }
        # Map Mac II IRQ levels back to source
        set src ""
        switch -- $llv {
            1 {set src " (VIA1)"}
            2 {set src " (VIA2)"}
            4 {set src " (SCC)"}
            6 {set src " (NMI)"}
        }
        puts [format "           IRQ: ipl_active_cyc(wrap16)=%u iack_cnt(wrap8)=%u last_iack_lvl=%d%s levels_seen=%s" \
            $cyc $iac $llv $src $bmstr]
        if {$cyc == 0 && $iac == 0} {
            puts "                 NO peripheral asserts ANY IRQ. Hang upstream of IRQ delivery (peripheral RTL side)."
        } elseif {$iac == 0} {
            puts "                 IRQs asserted but never IACK'd. CPU masking via SR or interrupt priority logic broken."
        }
    }
    if {[info exists idx(PIRQ)]} {
        set qq [rd $idx(PIRQ)]
        set scc_c  [expr {($qq >> 8)  & 0xFF}]
        set via2_c [expr {($qq >> 16) & 0xFF}]
        set via1_c [expr {($qq >> 24) & 0xFF}]
        puts [format "           IRQ-SRC: via1_cnt(wrap8)=%u  via2_cnt(wrap8)=%u  scc_cnt(wrap8)=%u" \
            $via1_c $via2_c $scc_c]
        if {$via1_c == 0 && $via2_c == 0 && $scc_c == 0} {
            puts "                 ALL three IRQ sources frozen at 0 -- they share a sample window; investigate the encoder."
        }
    }
    if {[info exists idx(PSCC)]} {
        set ss [rd $idx(PSCC)]
        set lowaddr [expr {$ss & 0xFF}]
        set rdc     [expr {($ss >> 8)  & 0xFF}]
        set wrc     [expr {($ss >> 16) & 0xFF}]
        set scc_ev  [expr {($ss >> 31) & 0x1}]
        set asc_ev  [expr {($ss >> 30) & 0x1}]
        puts [format "           SCC-ACC: ever=%d (asc_ever=%d) | wr_cnt(wrap8)=%u  rd_cnt(wrap8)=%u  last_addr_low=0x%02X" \
            $scc_ev $asc_ev $wrc $rdc $lowaddr]
        if {$scc_ev == 0} {
            puts "                 selectSCC NEVER asserted -- the OS hasn't touched SCC at all. Likely XPRAM/SPValid pushed boot past AppleTalk init or ROM probe skipped it."
        } elseif {$wrc == 0} {
            puts "                 SCC reads but no writes -- OS is polling SCC waiting for status that never changes (e.g. RR0 RX_AVAIL)."
        }
    }
    if {[info exists idx(PIOH)]} {
        set oo [rd $idx(PIOH)]
        set iwm  [expr {$oo & 0xFF}]
        set asc  [expr {($oo >> 8)  & 0xFF}]
        set via2 [expr {($oo >> 16) & 0xFF}]
        set via1 [expr {($oo >> 24) & 0xFF}]
        puts [format "           PER-IO: via1(wrap8)=%u  via2(wrap8)=%u  asc(wrap8)=%u  iwm(wrap8)=%u" \
            $via1 $via2 $asc $iwm]
    }
    if {[info exists idx(PFST)]} {
        # FPU CIR FSM state (build #16). Layout in dbg_min comment.
        set st [rd $idx(PFST)]
        set resp_prim   [expr {($st >> 16) & 0xFFFF}]
        set cur_state   [expr {($st >> 11) & 0x1F}]
        set max_state   [expr {($st >> 6)  & 0x1F}]
        set opword_seen [expr {($st >> 5)  & 0x1}]
        set cmd_seen    [expr {($st >> 4)  & 0x1}]
        set trig_seen   [expr {($st >> 3)  & 0x1}]
        set exc_seen    [expr {($st >> 2)  & 0x1}]
        set frame_seen  [expr {($st >> 1)  & 0x1}]
        set cir_act     [expr {$st & 0x1}]
        set state_names [list IDLE DECODE XFER_SRC XFER_SRC_WAIT XFER_SRC_WAIT2 \
            EXECUTE EXEC_DONE XFER_DST XFER_DST_WAIT COND_EVAL COND_WAIT COND_CHECK \
            EXCEPT_PRE EXCEPT_MID EXCEPT_POST SAVE_WAIT SAVE_FORMAT SAVE_FRAME \
            RESTORE_FORMAT RESTORE_FRAME PEND_DECODE PEND_XFER_SRC PEND_WAIT PEND_WAIT2 PEND_WAIT3]
        set cur_name "?"
        set max_name "?"
        if {$cur_state < [llength $state_names]} { set cur_name [lindex $state_names $cur_state] }
        if {$max_state < [llength $state_names]} { set max_name [lindex $state_names $max_state] }
        puts [format "           FPU-FSM: state=%s(%d) max_seen=%s(%d) resp_prim=0x%04X | opword_seen=%d cmd_seen=%d trigger_seen=%d exc_seen=%d frame_seen=%d active=%d" \
            $cur_name $cur_state $max_name $max_state $resp_prim \
            $opword_seen $cmd_seen $trig_seen $exc_seen $frame_seen $cir_act]
        if {$max_state == 0} {
            puts "                 max=IDLE => CPU never wrote opword to OPSEL CIR. cpRESTORE protocol not initiated through standard path."
        } elseif {$max_state >= 12 && $max_state <= 14} {
            puts "                 max=EXCEPT_* => FORMAT word was invalid; FSM took the exception path."
        } elseif {$frame_seen == 1} {
            puts "                 RESTORE_FRAME reached => build #15 fix's path IS exercised. Check PFRR/PFRW for word transfers."
        } elseif {$max_state == 18} {
            puts "                 max=RESTORE_FORMAT => FORMAT word never arrived (cir_restore_trigger?) OR fw was unrecognized."
        }
    }
    if {[info exists idx(PCAK)]} {
        # Control CIR ACK observability (build #22). Watches the bus for
        # writes to $00022002 (Control CIR) and records count + bit-0
        # sub-count + last data word.
        set ck [rd $idx(PCAK)]
        set total_cnt [expr {($ck >> 24) & 0xFF}]
        set ack_cnt   [expr {($ck >> 16) & 0xFF}]
        set last_din  [expr {$ck & 0xFFFF}]
        set bit0      [expr {$last_din & 0x1}]
        puts [format "           FPU-ACK: total_writes(sat8)=%u  ack_writes(sat8)=%u  last_din=0x%04X (bit0=%d)" \
            $total_cnt $ack_cnt $last_din $bit0]
        if {$total_cnt == 0} {
            puts "                 PCAK=0 => CPU never wrote Control CIR (\$22002)."
            puts "                          cp_except_ack/cp_except_trap path is NOT firing — verify exception"
            puts "                          primitive decode in cp_idle_resp actually matches what the FPU returns."
        } elseif {$ack_cnt == 0} {
            puts [format "                 ack_cnt=0 but total=%u => write reaches FPU with bit 0 = 0." $total_cnt]
            puts "                          data_write_tmp clause for cp_except_ack isn't winning the mux —"
            puts "                          something later in the IF-ELSIF chain is overriding to 0x0422 (sndOPC)."
        } else {
            puts [format "                 ack_cnt=%u => bit 0 = 1 reached FPU. Now check PFST current state:" $ack_cnt]
            puts "                          if STILL EXCEPT_PRE(12), FPU-side ACK gate (cir_mode_reg=1?) is blocking;"
            puts "                          if IDLE, protocol works and the wedge has a different root."
        }
    }
    if {[info exists idx(PFPD)]} {
        # FPU detection probe (build #27, bug #6). Counts FPU CIR-space bus
        # cycles by shape to diagnose "coprocessor not installed" dialog.
        set fd [rd $idx(PFPD)]
        set total_cyc   [expr {($fd >> 24) & 0xFF}]
        set last_low    [expr {($fd >> 16) & 0xFF}]
        set periph_cnt  [expr {($fd >> 8)  & 0xFF}]
        set save_rd_cnt [expr {$fd & 0xFF}]
        set reg_name "?"
        switch -- $last_low {
            0x00 { set reg_name "Response (cpGEN read)" }
            0x02 { set reg_name "Control (ACK)" }
            0x04 { set reg_name "Save CIR (cpSAVE format)" }
            0x06 { set reg_name "Restore CIR (cpRESTORE format)" }
            0x08 { set reg_name "Op Word (cpGEN)" }
            0x0A { set reg_name "Command Word (cpGEN)" }
            0x0E { set reg_name "Condition (cpScc/cpDBcc/cpTRAPcc/cpBcc)" }
            0x10 { set reg_name "Operand" }
            0x14 { set reg_name "Register Select" }
            0x18 { set reg_name "Instruction Address" }
            0x1C { set reg_name "Operand Address" }
            default { set reg_name [format "?(\$%02X)" $last_low] }
        }
        puts [format "           FPU-DET: total(sat8)=%u  last_addr=\$%02X (%s)  cpGEN-shape(sat8)=%u  Save-rd(sat8)=%u" \
            $total_cyc $last_low $reg_name $periph_cnt $save_rd_cnt]
        if {$total_cyc == 0} {
            puts "                    PFPD=0 => CPU never touched FPU space. Bug is upstream:"
            puts "                              ROM Universal.a's TestForFPU may not be running, OR address"
            puts "                              decode at \$00022000-\$00023FFF (LBMacTwo.sv:472) is broken."
        } elseif {$periph_cnt == 0} {
            puts "                    cpGEN-shape=0 => OS only reads Response/Save/Restore, never writes"
            puts "                              OpWord/Command — meaning no real FPU instruction reaches the"
            puts "                              CIR write path. Likely HWCfgFlags FPU bit cleared at boot:"
            puts "                              Universal.a TestForFPU's FNOP took the F-line trap (FPU did"
            puts "                              not return clean Response). Inspect what our FPU returns on"
            puts "                              Response CIR after an OpWord/Command write (PFRR last_resp)."
        } elseif {$save_rd_cnt == 0} {
            puts "                    Save-rd=0 => OS never read Save CIR. FSAVE protocol path untouched"
            puts "                              this boot; bug #1 fix isn't being exercised. Bomb origin is"
            puts "                              some OTHER FPU instruction the FPU doesn't service."
        } else {
            puts "                    cpGEN-shape and Save-rd both grow => CIR traffic is healthy."
            puts "                              The dialog is from a specific op path. Check PFRR/PFST for"
            puts "                              what response shape preceded the trap, and PFST max_seen."
        }
    }
    if {[info exists idx(PFRR)] && [info exists idx(PFRW)]} {
        # FPU CIR Response/Restore probes (build #14). Confirms the FRESTORE
        # CIR-protocol hang found by build #13.
        set rr [rd $idx(PFRR)]
        set rw [rd $idx(PFRW)]
        set last_resp     [expr {($rr >> 16) & 0xFFFF}]
        set resp_rd_cnt   [expr {($rr >> 8)  & 0xFF}]
        set ctrl_wr_cnt   [expr {$rr & 0xFF}]
        set last_rest     [expr {($rw >> 16) & 0xFFFF}]
        set rest_wr_cnt   [expr {($rw >> 8)  & 0xFF}]
        set opw_wr_cnt    [expr {$rw & 0xFF}]
        # CA bit (15) = "Come Again" / busy semantics in 68881 CIR.
        set ca_bit [expr {($last_resp >> 15) & 1}]
        set prim_hint "?"
        if {$last_resp == 0x0900} { set prim_hint "NULL/release (ready)" }
        if {$last_resp == 0x8900} { set prim_hint "BUSY (come again)" }
        if {$last_resp == 0x8000} { set prim_hint "CA=1 + low byte 0x00 (non-standard BUSY-like)" }
        if {$last_resp == 0x0000} { set prim_hint "all zeros (no read yet or odd state)" }
        puts [format "           FPU-CIR Response \$22000: last=0x%04X (CA=%d) %s | rd_cnt(wrap8)=%u ctrl_wr_cnt(wrap8)=%u" \
            $last_resp $ca_bit $prim_hint $resp_rd_cnt $ctrl_wr_cnt]
        puts [format "           FPU-CIR Restore  \$22006: last=0x%04X | wr_cnt(wrap8)=%u opw_wr_cnt(wrap8)=%u" \
            $last_rest $rest_wr_cnt $opw_wr_cnt]
        if {$ca_bit == 1 && $rest_wr_cnt > 0} {
            puts "                 CONFIRMED: CA=1 forever + Restore writes ongoing => FRESTORE protocol stalled in FPU."
        }
    }
    if {[info exists idx(PIFA)] && [info exists idx(PIFC)]} {
        # IF-only PC sampler (build #13). PIFA latches cpuAddr on a real
        # instruction-fetch bus cycle (AS-edge, RW=1, FC=2|6). PADR is
        # every-clock and is polluted by write residue ($22006 hammered).
        # PIFA tells us where the loop body actually executes.
        set ifa [rd $idx(PIFA)]
        set ifc [rd $idx(PIFC)]
        set total [expr {$ifc & 0xFF}]
        set user  [expr {($ifc >> 8) & 0xFF}]
        set super [expr {($ifc >> 16) & 0xFF}]
        puts [format "           IF-PC: last_IF_addr=0x%08X  IFcycles(wrap8)=%u (user=%u super=%u)" \
            $ifa $total $user $super]
        # Rapid burst: read PIFA 20 times in quick succession to sample
        # the IF stream. ~50us per JTAG read, so 20 reads ~= 1ms of
        # CPU activity = ~1000 IF cycles randomly sampled.
        set seen {}
        for {set k 0} {$k < 20} {incr k} {
            lappend seen [format "0x%08X" [rd $idx(PIFA)]]
        }
        puts [format "           IF-PC burst: %s" [join $seen " "]]
    }
    if {[info exists idx(PMEM)] && [info exists idx(PMEM2)]} {
        set m1 [rd $idx(PMEM)]
        set m2 [rd $idx(PMEM2)]
        set w0 [expr {($m1 >> 16) & 0xFFFF}]
        set w1 [expr {$m1         & 0xFFFF}]
        set w2 [expr {($m2 >> 16) & 0xFFFF}]
        set w3 [expr {$m2         & 0xFFFF}]
        puts [format "           CODE@22000: %04X %04X %04X %04X" $w0 $w1 $w2 $w3]
        # Mini 68k disasm hints for the first word
        if {$w0 != 0} {
            set op_hi [expr {($w0 >> 12) & 0xF}]
            set hint  ""
            switch -- $op_hi {
                0x0 { set hint "MOVEP/Bit/Immediate" }
                0x1 { set hint "MOVE.B" }
                0x2 { set hint "MOVE.L" }
                0x3 { set hint "MOVE.W" }
                0x4 { set hint "Miscellaneous (CLR/NEG/JMP/JSR/LEA/EXT/MOVEM/RTE/RTS/etc.)" }
                0x5 { set hint "ADDQ/SUBQ/Scc/DBcc" }
                0x6 { set hint "Bcc/BSR/BRA" }
                0x7 { set hint "MOVEQ" }
                0x8 { set hint "OR/DIV/SBCD" }
                0x9 { set hint "SUB/SUBX/SUBA" }
                0xA { set hint "(unassigned — A-line trap, used for OS calls!)" }
                0xB { set hint "EOR/CMPM/CMP/CMPA" }
                0xC { set hint "AND/MUL/ABCD/EXG" }
                0xD { set hint "ADD/ADDX/ADDA" }
                0xE { set hint "Shifts/Rotates" }
                0xF { set hint "(unassigned — F-line trap, used for FPU/coprocessor!)" }
            }
            puts [format "                       w0=0x%04X => %s" $w0 $hint]
        }
        if {$w0 == 0 && $w1 == 0 && $w2 == 0 && $w3 == 0} {
            puts "                       all zeros -- the trigger never fired. The CPU isn't reading these addresses. Loop is elsewhere."
        }
    }
    after 300
}
end_insystem_source_probe
