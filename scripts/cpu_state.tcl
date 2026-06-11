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
    if {$nm eq "PSCW"} { set idx(PSCW) $i }
    if {$nm eq "PSNC"} { set idx(PSNC) $i }
    if {$nm eq "PSWL"} { set idx(PSWL) $i }
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
    # Build #30 — trap-vector-fetch + bus-error probe (RETIRED in #35)
    if {$nm eq "PFTR"} { set idx(PFTR) $i }
    # Build #31 — bomb-entry PC snapshot (RETIRED in #35)
    if {$nm eq "PFBE"} { set idx(PFBE) $i }
    # Build #32 — _SysError opcode (A9C9) caller PC capture (RETIRED in #35)
    if {$nm eq "PFCS"} { set idx(PFCS) $i }
    # Build #35 — bug #6 phase 2 probes
    if {$nm eq "PFOQ"} { set idx(PFOQ) $i } ;# PC of last cpGEN OpWord write
    if {$nm eq "PFOV"} { set idx(PFOV) $i } ;# last 2 OpWord values
    if {$nm eq "PFLN"} { set idx(PFLN) $i } ;# F-line vector ($B0) fetch detector (retired #37)
    # Build #37 — HWCfgFlags writes (bug #6 phase 3)
    if {$nm eq "PHWC"} { set idx(PHWC) $i }
    # Build #45 — FPU Save-CIR read + FSAVE memory write probes (bug #6 phase 4)
    if {$nm eq "PSFW"} { set idx(PSFW) $i }
    if {$nm eq "PSFM"} { set idx(PSFM) $i }
    # Build #47 — MMUType byte ($0CB1) write+read tracker (bug #6 phase 6)
    if {$nm eq "PMTY"} { set idx(PMTY) $i }
    # Build #58 — low-mem longword read probes (SDRAM-corruption diagnostic)
    if {$nm eq "PD28"} { set idx(PD28) $i }
    if {$nm eq "PD24"} { set idx(PD24) $i }
    # Build #59 — _SysError ($A9C9) instruction-fetch PC capture
    if {$nm eq "PFCS"} { set idx(PFCS) $i }
    # Build #60 — bomb-caller PC (super-IF before first entry to $40002400-$400024FF)
    if {$nm eq "PBCP"} { set idx(PBCP) $i }
    # Build #62 — F-line vector RAM read + trap-entry counter
    if {$nm eq "PVCF"} { set idx(PVCF) $i }
    if {$nm eq "PFLN"} { set idx(PFLN) $i }
    # Build #63 — F-line trap source PC (which F-line instruction triggered)
    if {$nm eq "PFTS"} { set idx(PFTS) $i }
    # Build #68 — IORB header at fixed $3A4: csCode, ioBuffer, ioReqCount, ioPosOffset
    if {$nm eq "PIRH"} { set idx(PIRH) $i }
    if {$nm eq "PIRB"} { set idx(PIRB) $i }
    if {$nm eq "PIRR"} { set idx(PIRR) $i }
    if {$nm eq "PIRP"} { set idx(PIRP) $i }
    # Build #69 — driver completion-write trap + HPS-download verifier
    if {$nm eq "PIRE"} { set idx(PIRE) $i }
    if {$nm eq "PSDH"} { set idx(PSDH) $i }
    # Build #70 — ioBuffer write snoop (bytes Mac OS receives for the last read)
    if {$nm eq "PIRD"} { set idx(PIRD) $i }
    # Build #71 — Mac OS error globals: ResErr ($A60), DskErr ($142)
    if {$nm eq "PRSR"} { set idx(PRSR) $i }
    if {$nm eq "PDSE"} { set idx(PDSE) $i }
    # Build #72 — filtered ResErr (non-zero writes only)
    if {$nm eq "PRSF"} { set idx(PRSF) $i }
    # Build #73 — F-line opcode tracker (CPU/FPU bug hypothesis)
    if {$nm eq "PFLO"} { set idx(PFLO) $i }
    if {$nm eq "PFLA"} { set idx(PFLA) $i }
    # 2026-06-10 — runaway-entry jump ring (src/dst pairs; PRNG source[3:0]
    # selects the ring slot) + freeze/classifier flags
    if {$nm eq "PRNG"} { set idx(PRNG) $i }
    if {$nm eq "PRWF"} { set idx(PRWF) $i }
    # 2026-06-10c — last two IF data words before the ring freeze
    if {$nm eq "PIFD"} { set idx(PIFD) $i }
    incr i
}

# signed 16-bit interpretation helper
proc s16 {v} { set v [expr {$v & 0xFFFF}]; if {$v >= 32768} { return [expr {$v - 65536}] }; return $v }

# Build #35 — classify F-line OpWord (second word of F-line instruction).
proc opword_class {ow} {
    if {$ow == 0} { return "(none)" }
    set top3 [expr {($ow >> 13) & 0x7}]
    if {[expr {$ow & 0xE000}] == 0x0000} { return "cpGEN" }
    if {[expr {$ow & 0xC000}] == 0x4000} { return "cpDBcc/cpScc/cpTRAPcc" }
    if {[expr {$ow & 0xC000}] == 0x8000} { return "cpBcc.W" }
    if {[expr {$ow & 0xC000}] == 0xC000} { return "cpBcc.L" }
    return "?"
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
        set regnum [expr {($sreg >> 4) & 0x7}]
        set regnm "?"
        switch $regnum {
            0 {set regnm "CDR(data)"} 1 {set regnm "ICR"} 2 {set regnm "MR"}
            3 {set regnm "TCR"} 4 {set regnm "CSR(bus-status)"} 5 {set regnm "BSR(dma-status)"}
            6 {set regnm "IDR(input-data)"} 7 {set regnm "RESET-IRQ"}
        }
        puts [format "           SCSI-RD: last_reg_off=0x%02X (reg %u = %s) value=0x%04X | img_seen=%d sd_rd_seen=%d sd_wr_seen=%d" \
            $sreg $regnum $regnm $rdv $img $sdrd $sdwr]
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
        # 2026-06-10c: [27:26]=empty-CD phase[1:0], [25]=phase[2], [24]=REQ
        set ecreq [expr {($s3 >> 24) & 0x1}]
        set ecph  [expr {((($s3 >> 25) & 0x1) << 2) | (($s3 >> 26) & 0x3)}]
        puts [format "           PHASE now: t0=%s t1=%s | max: t0=%s t1=%s | io_ack_seen=%d sd_ack_seen=%d" \
            [phname $cp0] [phname $cp1] [phname $mp0] [phname $mp1] $iackseen $sackseen]
        puts [format "           EMPTY-CD(ID3): phase=%s req=%u" [phname $ecph] $ecreq]
        if {$ecph != 0} {
            puts "                 => the fake CD-ROM target is BUSY. If it stays in DATA_OUT with req=1"
            puts "                    while the Mac polls BSR, that is the alloc-length over-serve wedge."
        }
    }
    if {[info exists idx(PSCW)]} {
        set w [rd $idx(PSCW)]
        set dc   [expr {$w & 0xFFFF}]
        set wph  [expr {($w >> 16) & 0x7}]
        set dcpl [expr {($w >> 19) & 0x1}]
        set iowr [expr {($w >> 20) & 0x1}]
        set ioack [expr {($w >> 21) & 0x1}]
        set iobusy [expr {($w >> 22) & 0x1}]
        set sbsel [expr {($w >> 23) & 0x1}]
        set cwr  [expr {($w >> 24) & 0x1}]
        set tlen [expr {($w >> 25) & 0x3F}]
        set req  [expr {($w >> 31) & 0x1}]
        set blk  [expr {$dc >> 9}]
        # NOTE: the ncr5380 mux shows whichever target is in DATA_IN and
        # DEFAULTS TO TARGET 1 (ID5) when neither is — the OSD-mounted disk
        # normally lands on t1, so the idle snapshot is usually the real disk.
        puts [format "           WR-STALL disk(muxed,idle=t1/ID5): phase=%s data_cnt=%u (block %u/%u of tlen=%u)  cmd_write=%u" \
            [phname $wph] $dc $blk [expr {$tlen>0?$tlen-1:0}] $tlen $cwr]
        puts [format "                 io_wr=%u io_ack=%u io_busy=%u sd_buff_sel=%u dc9=%u req=%u data_complete=%u" \
            $iowr $ioack $iobusy $sbsel [expr {($dc>>9)&1}] $req $dcpl]
        if {$cwr==1 && $wph==3 && $iobusy==1} {
            puts "                 => STALLED in WRITE DATA phase waiting for HPS block-flush ack (io_busy held)."
            puts "                    If sd_buff_sel==dc9 the double-buffer desynced; if io_wr stuck=1 the HPS never acked."
        } elseif {$cwr==1 && $wph==4} {
            puts "                 => stalled at STATUS_OUT (last-block flush / completion)."
        } elseif {$cwr==1 && $wph<3} {
            puts "                 => write stuck BEFORE data phase (command-phase issue)."
        }
    }
    if {[info exists idx(PSNC)]} {
        set n [rd $idx(PSNC)]
        set dreq    [expr {$n & 0x1}]
        set sreq    [expr {($n >> 1) & 0x1}]
        set sack    [expr {($n >> 2) & 0x1}]
        set dmaen   [expr {($n >> 3) & 0x1}]
        set dmaack  [expr {($n >> 4) & 0x1}]
        set ackbusy [expr {($n >> 5) & 0x1}]
        set holdoff [expr {($n >> 6) & 0x7}]
        set mrdma   [expr {($n >> 9) & 0x1}]
        set pmatch  [expr {($n >> 10) & 0x1}]
        set wordl   [expr {($n >> 11) & 0x1}]
        set longl   [expr {($n >> 12) & 0x1}]
        set long2nd [expr {($n >> 13) & 0x1}]
        set tcr     [expr {($n >> 14) & 0xF}]
        set wrcnt   [expr {($n >> 18) & 0x3FFF}]
        set bytes_lw [expr {$wrcnt*4}]
        set bytes_w  [expr {$wrcnt*2}]
        puts [format "           NCR-DMA: dreq=%u scsi_req=%u scsi_ack=%u | dma_en=%u dma_ack=%u dma_ack_busy=%u holdoff=%u" \
            $dreq $sreq $sack $dmaen $dmaack $ackbusy $holdoff]
        puts [format "                 mr_dma_mode=%u pmatch=%u word_l=%u long_l=%u long2nd=%u tcr=0x%X  dma_rw_count=%u (rd+wr DACK pulses; =%u B word / %u B longword)" \
            $mrdma $pmatch $wordl $longl $long2nd $tcr $wrcnt $bytes_w $bytes_lw]
        if {$sreq==1 && $dreq==0 && $dmaen==0} {
            puts "                 => DREQ stopped because dma_en=0: the Mac CLEARED DMA mode (MR_DMA_MODE)"
            puts "                    mid-transfer while the target still wants data — chunk re-arm / phase-mismatch IRQ."
        } elseif {$sreq==1 && $dreq==0 && $ackbusy==1} {
            puts "                 => DREQ stopped because dma_ack_busy=1 STUCK (holdoff=$holdoff) — longword-write ACK sequencing bug."
        } elseif {$sreq==1 && $dreq==0 && $pmatch==0} {
            puts "                 => phase mismatch (pmatch=0): tcr expected phase != actual bus phase."
        }
    }
    if {[info exists idx(PSWL)]} {
        set wl [rd $idx(PSWL)]
        set blindwr  [expr {$wl & 0xFF}]
        set dmaen2   [expr {($wl >> 8) & 1}]
        set pmatch2  [expr {($wl >> 9) & 1}]
        set dreq2    [expr {($wl >> 10) & 1}]
        set eodma    [expr {($wl >> 11) & 1}]
        set armed    [expr {($wl >> 12) & 1}]
        set irqlatch [expr {($wl >> 13) & 1}]
        set reqdrops [expr {($wl >> 16) & 0xFFFF}]
        puts [format "           IRQ-MACHINE: irq_latch=%u dma_armed=%u eodma=%u dreq=%u pmatch=%u dma_en=%u | blind_wr(low8)=%u req_drop=%u" \
            $irqlatch $armed $eodma $dreq2 $pmatch2 $dmaen2 $blindwr $reqdrops]
        if {$irqlatch} {
            puts "                 => 5380 IRQ LATCHED (phase-mismatch fired) — VIA2 CB2 flag should be set; if the"
            puts "                    Mac still spins, it is not reading VIA2 IFR or the CB2 polarity/edge is wrong."
        } elseif {$armed} {
            puts "                 => DMA armed, no mismatch yet — transfer still in progress (or stalled mid-data)."
        }
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
    # Build #68 — IORB header at the fixed $3A4 Params region (.Sony IORB).
    # PIRH=csCode, PIRB=ioBuffer, PIRR=ioReqCount, PIRP=ioPosOffset.
    # These probes capture OS WRITES to the IORB fields, so they hold the
    # parameters of the LATEST _Read/_Write request at $3A4 — which during
    # the Welcome hang IS the wedged operation's parameters.
    if {[info exists idx(PIRH)]} {
        set ph [rd $idx(PIRH)]
        set cs [expr {($ph >> 16) & 0xFFFF}]
        set cn [expr {$ph & 0xFFFF}]
        set csname "(unknown)"
        switch -- $cs {
            0      {set csname "(no write yet)"}
            1      {set csname "cmdRead (.Sony async read)"}
            2      {set csname "cmdWrite (.Sony async write)"}
            5      {set csname "KillIO"}
            6      {set csname "Verify"}
            7      {set csname "Format/Eject"}
            8      {set csname "DriveStatus"}
            21     {set csname "DriveInfo"}
            23     {set csname "TrackCacheControl"}
            68     {set csname "FormatVerify"}
            88     {set csname "DriveStatus (0x58)"}
        }
        puts [format "           IORB-CS: \$3BE csCode=0x%04X (%d) %s  wr_cnt(wrap16)=%u" \
            $cs $cs $csname $cn]
    }
    if {[info exists idx(PIRB)]} {
        set pb [rd $idx(PIRB)]
        set hi [expr {($pb >> 16) & 0xFFFF}]
        set lo [expr {$pb & 0xFFFF}]
        set full [expr {($hi << 16) | $lo}]
        puts [format "           IORB-BUF: \$3C4 ioBuffer = 0x%08X (hi=0x%04X lo=0x%04X)" \
            $full $hi $lo]
    }
    if {[info exists idx(PIRR)]} {
        set pr [rd $idx(PIRR)]
        set hi [expr {($pr >> 16) & 0xFFFF}]
        set lo [expr {$pr & 0xFFFF}]
        set full [expr {($hi << 16) | $lo}]
        # ioReqCount is a longword byte count; typical floppy reads = 512 bytes/sector
        set hint ""
        if {$full == 512}      { set hint "  (= one sector)" }
        if {$full == 1024}     { set hint "  (= two sectors)" }
        if {$full == 0x200}    { set hint "  (= 512 = one sector)" }
        if {$full > 0 && $full <= 0x10000} { set hint "  (small read)" }
        puts [format "           IORB-REQ: \$3C8 ioReqCount = 0x%08X (%u bytes)%s" \
            $full $full $hint]
    }
    if {[info exists idx(PIRP)]} {
        set pp [rd $idx(PIRP)]
        set hi [expr {($pp >> 16) & 0xFFFF}]
        set lo [expr {$pp & 0xFFFF}]
        set full [expr {($hi << 16) | $lo}]
        # For 800K Sony floppy: total bytes = 819200 = 0xC8000
        # Track/side/sector decomposition assumes 12 sectors/track on tracks 0-15.
        set total 819200
        set hint ""
        if {$full == 0}                 { set hint "  (boot block / track 0 sector 0)" }
        if {$full >= 0 && $full < 0x400} { set hint [format "  (boot blocks, byte %d)" $full] }
        if {$full > $total}             { set hint "  (BEYOND 800K disk size!)" }
        # Sector-block estimate (just for orientation, assumes side-interleaved layout)
        if {$full > 0 && $full <= $total} {
            set sec_no [expr {$full / 512}]
            set sec_off [expr {$full % 512}]
            set hint [format "%s  (sector %u offset %u, ~%.1f%% of disk)" \
                $hint $sec_no $sec_off [expr {100.0 * $full / $total}]]
        }
        puts [format "           IORB-POS: \$3D2 ioPosOffset = 0x%08X (%u)%s" \
            $full $full $hint]
    }
    # Build #69 — driver completion-write capture (non-$0001 writes to ioResult)
    if {[info exists idx(PIRE)]} {
        set pe [rd $idx(PIRE)]
        set ev [expr {($pe >> 16) & 0xFFFF}]
        set ec [expr {$pe & 0xFFFF}]
        set sigv $ev
        if {$sigv >= 32768} { set sigv [expr {$sigv - 65536}] }
        set errname "(unknown)"
        switch -- $sigv {
            0      {set errname "noErr (success)"}
            -36    {set errname "ioErr (generic I/O)"}
            -50    {set errname "paramErr"}
            -66    {set errname "noNybErr (no GCR transitions)"}
            -67    {set errname "noAdrMkErr (no addr mark)"}
            -68    {set errname "dataVerErr (read-verify failed)"}
            -69    {set errname "badCksmErr (addr mark checksum wrong)"}
            -70    {set errname "badBtSlpErr (trailer bytes wrong)"}
            -80    {set errname "seekErr (track mismatch)"}
            -81    {set errname "sectNFErr (sector not found)"}
        }
        puts [format "           IOR-ERR: completion @ \$3B4: non-\$0001 wr_cnt(wrap16)=%u  last=0x%04X (%d) %s" \
            $ec $ev $sigv $errname]
        if {$ec == 0} {
            puts "                 cnt=0 => driver NEVER completes (writes only \$0001 = in-progress)"
        }
    }
    # Build #70 — ioBuffer write snoop: first 4 bytes of last completed read
    # land in the buffer at PIRB's captured address. For Boot712.dsk sector
    # 529 (the t=360s wedge target) the expected bytes are 5F 22 52 08.
    if {[info exists idx(PIRD)]} {
        set pd [rd $idx(PIRD)]
        set w0 [expr {$pd & 0xFFFF}]
        set w1 [expr {($pd >> 16) & 0xFFFF}]
        set b0 [expr {($w0 >> 8) & 0xFF}]
        set b1 [expr {$w0 & 0xFF}]
        set b2 [expr {($w1 >> 8) & 0xFF}]
        set b3 [expr {$w1 & 0xFF}]
        set hint ""
        # Boot712.dsk byte 0..3 (boot block) = 4C 4B 60 00 ("LK" + offset)
        if {$w0 == 0x4C4B} { set hint "  (LK = boot signature - reading sector 0)" }
        # Boot712.dsk bytes at sector 529 ($42200) = 5F 22 52 08
        if {$w0 == 0x5F22 && $w1 == 0x5208} { set hint "  (matches sector 529 expected)" }
        if {$w0 == 0x0000 && $w1 == 0x0000} { set hint "  (all-zero — buffer empty/uninit)" }
        puts [format "           BUF-RD: ioBuffer first 4 bytes = %02X %02X %02X %02X  (word0=0x%04X word1=0x%04X)%s" \
            $b0 $b1 $b2 $b3 $w0 $w1 $hint]
    }
    # Build #73 — F-line opcode tracker (CPU/FPU hypothesis test)
    if {[info exists idx(PFLO)] && [info exists idx(PFLA)]} {
        set po [rd $idx(PFLO)]
        set pa [rd $idx(PFLA)]
        set op [expr {($po >> 16) & 0xFFFF}]
        set cnt [expr {$po & 0xFFFF}]
        # Classify F-line opcode by high byte
        set opclass "(unknown)"
        set hi [expr {($op >> 8) & 0xFF}]
        if {$hi == 0xF0 || $hi == 0xF1} { set opclass "cpGEN (FPU math)" }
        if {$hi == 0xF2} { set opclass "FBcc.W (conditional branch)" }
        if {$hi == 0xF3} { set opclass "FBcc.L (long branch)" }
        if {$hi >= 0xF4 && $hi <= 0xF7} { set opclass "cpSAVE/RESTORE or cache" }
        if {$hi >= 0xF8 && $hi <= 0xFB} { set opclass "MMU op (68030)" }
        puts [format "           F-line: op=0x%04X (%s) at PC=0x%08X  fetch_cnt(wrap16)=%u" \
            $op $opclass $pa $cnt]
        if {$cnt == 0} {
            puts "                 cnt=0 => Mac OS NEVER executed an F-line opcode."
            puts "                          CPU/FPU hypothesis REJECTED for this boot."
        } else {
            puts [format "                 cnt>0 => %u F-line opcodes fetched." $cnt]
            puts "                          Each one goes through cp_idle_resp;"
            puts "                          if its FPU response doesn't match the 4 supported"
            puts "                          patterns, trap_1111 fires (F-line trap)."
            puts "                          Hypothesis CONFIRMED if PRSF shows specific errors"
            puts "                          (e.g., fnfErr/eofErr from corrupted state)."
        }
    }
    # Build #71 — Mac OS error globals
    if {[info exists idx(PRSR)]} {
        set pr [rd $idx(PRSR)]
        set ev [expr {($pr >> 16) & 0xFFFF}]
        set ec [expr {$pr & 0xFFFF}]
        set sigv $ev
        if {$sigv >= 32768} { set sigv [expr {$sigv - 65536}] }
        set errname "(unknown)"
        switch -- $sigv {
            0      {set errname "noErr (success)"}
            -39    {set errname "eofErr"}
            -49    {set errname "opWrErr (file already open)"}
            -50    {set errname "paramErr"}
            -108   {set errname "memFullErr"}
            -109   {set errname "nilHandleErr"}
            -110   {set errname "memAdrErr"}
            -111   {set errname "memWZErr"}
            -188   {set errname "resourceInMemory"}
            -189   {set errname "writingPastEnd"}
            -190   {set errname "inputOutOfBounds"}
            -191   {set errname "resNotFound"}
            -192   {set errname "resFNotFound (file not found!)"}
            -193   {set errname "addResFailed"}
            -194   {set errname "addRefFailed"}
            -195   {set errname "rmvResFailed"}
            -196   {set errname "rmvRefFailed"}
            -197   {set errname "resAttrErr"}
            -198   {set errname "mapReadErr"}
            -199   {set errname "CantDecompress"}
        }
        puts [format "           Mac-ResErr: \$A60 write_cnt(wrap16)=%u  last=0x%04X (%d) %s" \
            $ec $ev $sigv $errname]
        if {$ec == 0} {
            puts "                 cnt=0 => OS hasn't touched ResErr; resource manager not exercised"
        }
    }
    # Build #72 — filtered ResErr: captures only NON-ZERO writes (actual error events).
    if {[info exists idx(PRSF)]} {
        set pf [rd $idx(PRSF)]
        set ev [expr {($pf >> 16) & 0xFFFF}]
        set ec [expr {$pf & 0xFFFF}]
        set sigv $ev
        if {$sigv >= 32768} { set sigv [expr {$sigv - 65536}] }
        set errname "(unknown)"
        switch -- $sigv {
            -39    {set errname "eofErr"}
            -43    {set errname "fnfErr (file not found!)"}
            -49    {set errname "opWrErr (file already open)"}
            -50    {set errname "paramErr"}
            -53    {set errname "extFSErr (external file system)"}
            -108   {set errname "memFullErr"}
            -109   {set errname "nilHandleErr"}
            -110   {set errname "memAdrErr"}
            -111   {set errname "memWZErr"}
            -188   {set errname "resourceInMemory"}
            -189   {set errname "writingPastEnd"}
            -190   {set errname "inputOutOfBounds"}
            -191   {set errname "resNotFound"}
            -192   {set errname "resFNotFound (file not found!)"}
            -193   {set errname "addResFailed"}
            -197   {set errname "resAttrErr"}
            -198   {set errname "mapReadErr"}
            -199   {set errname "CantDecompress"}
        }
        puts [format "           Mac-ResErrFilt: \$A60 NON-ZERO writes wr_cnt(wrap16)=%u  last=0x%04X (%d) %s" \
            $ec $ev $sigv $errname]
        if {$ec == 0} {
            puts "                 cnt=0 => ResErr NEVER went non-zero => no Resource Manager error in this run"
            puts "                          (bomb path is NOT HOpenResFile; check FSMakeFSSpec or earlier)"
        } else {
            puts [format "                 cnt>0 => Resource Manager DID encounter an error (%d %s)" $sigv $errname]
        }
    }
    if {[info exists idx(PDSE)]} {
        set pd [rd $idx(PDSE)]
        set ev [expr {($pd >> 16) & 0xFFFF}]
        set ec [expr {$pd & 0xFFFF}]
        set sigv $ev
        if {$sigv >= 32768} { set sigv [expr {$sigv - 65536}] }
        set errname "(unknown)"
        switch -- $sigv {
            0      {set errname "noErr (success)"}
            -36    {set errname "ioErr"}
            -66    {set errname "noNybErr"}
            -67    {set errname "noAdrMkErr"}
            -68    {set errname "dataVerErr"}
            -69    {set errname "badCksmErr"}
            -70    {set errname "badBtSlpErr"}
            -80    {set errname "seekErr"}
            -81    {set errname "sectNFErr"}
        }
        puts [format "           Mac-DskErr: \$142 write_cnt(wrap16)=%u  last=0x%04X (%d) %s" \
            $ec $ev $sigv $errname]
    }
    # Build #69 — HPS download verifier: first 4 bytes of F1 floppy download
    if {[info exists idx(PSDH)]} {
        set ph [rd $idx(PSDH)]
        set w0 [expr {$ph & 0xFFFF}]
        set w1 [expr {($ph >> 16) & 0xFFFF}]
        set b0 [expr {($w0 >> 8) & 0xFF}]
        set b1 [expr {$w0 & 0xFF}]
        set b2 [expr {($w1 >> 8) & 0xFF}]
        set b3 [expr {$w1 & 0xFF}]
        set hint ""
        if {$w0 == 0x4C4B} { set hint "  (\"LK\" boot signature = HFS bootable)" }
        if {$w0 == 0x0000 && $w1 == 0x0000} { set hint "  (all-zero — download likely never started)" }
        puts [format "           HPS-DL: F1 bytes 0..3 = %02X %02X %02X %02X  (word0=0x%04X word1=0x%04X)%s" \
            $b0 $b1 $b2 $b3 $w0 $w1 $hint]
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
        # FPU detection probe (build #28, bug #6). Counts FPU CIR-space bus
        # cycles by shape to diagnose "coprocessor not installed" dialog.
        # Build #28: [7:0] now counts Condition CIR writes (FBcc/FNOP),
        # replacing Save-CIR reads (which build #27 already confirmed work).
        set fd [rd $idx(PFPD)]
        set total_cyc   [expr {($fd >> 24) & 0xFF}]
        set last_low    [expr {($fd >> 16) & 0xFF}]
        set periph_cnt  [expr {($fd >> 8)  & 0xFF}]
        set cond_wr_cnt [expr {$fd & 0xFF}]
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
        puts [format "           FPU-DET: total(sat8)=%u  last_addr=\$%02X (%s)  cpGEN-shape(sat8)=%u  Cond-wr(sat8)=%u" \
            $total_cyc $last_low $reg_name $periph_cnt $cond_wr_cnt]
        if {$total_cyc == 0} {
            puts "                    PFPD=0 => CPU never touched FPU space. Bug is upstream:"
            puts "                              ROM TestForFPU may not be running, OR address decode at"
            puts "                              \$00022000-\$00023FFF (LBMacTwo.sv:472) is broken."
        } elseif {$cond_wr_cnt == 0} {
            puts "                    Cond-wr=0 => no Condition CIR writes ever happened. The OS NEVER"
            puts "                              issued an FBcc/FNOP/FScc/FDBcc/FTRAPcc. This rules out"
            puts "                              the supermario Universal.a-style FNOP F-line detection."
            puts "                              Either the OS uses a different detection path, OR FNOP"
            puts "                              never reached the FPU because the F-line trap fired upstream."
        } elseif {$periph_cnt == 0} {
            puts "                    cpGEN-shape=0 but Cond-wr>0 => only FBcc-style ops, no cpSAVE/cpRESTORE."
        } else {
            puts "                    Cond-wr>0 and cpGEN-shape>0 => FBcc protocol DID run (likely FNOP"
            puts "                              detection). Check PFRR last_resp to see what Response value"
            puts "                              the FPU returned; non-NULL/non-BUSY/non-exception triggers"
            puts "                              TG68 cp_cond_eval/cp_idle_resp F-line fall-through."
        }
    }
    if {[info exists idx(PHWC)]} {
        # Build #37 — HWCfgFlags ($0B22) write tracker.
        set hw [rd $idx(PHWC)]
        set hw_pc_low24 [expr {($hw >> 8) & 0xFFFFFF}]
        set hw_bit4     [expr {($hw >> 7) & 0x1}]
        set hw_count    [expr {$hw & 0x7F}]
        # Infer high byte from value: ROM is $4xxxxxxx, RAM is $00xxxxxx.
        if {$hw_pc_low24 >= 0x1000} {
            set hw_pc [expr {0x40000000 | $hw_pc_low24}]
            set hw_zone "ROM"
        } else {
            set hw_pc [expr {0x00000000 | $hw_pc_low24}]
            set hw_zone "RAM"
        }
        puts [format "           FPU-HWC: writes=%u  last_writer_pc=0x%08X (%s)  last_bit4(hwCbFPU)=%d" \
            $hw_count $hw_pc $hw_zone $hw_bit4]
        if {$hw_count == 0} {
            puts "                    HWCfgFlags \$0B22 never written. Either ROM doesn't write the high byte"
            puts "                              (writes via word access at \$0B22-low-half), or the bus probe"
            puts "                              doesn't catch FC=5 accesses to this addr."
        } elseif {$hw_bit4 == 0} {
            puts "                    hwCbFPU(bit4)=0 at last write => FPU bit CLEARED."
            puts "                              Disassemble at last_writer_pc to find who cleared it."
            puts "                              This is the bomb path's source: Gestalt(FPU) returns gestaltNoFPU=0,"
            puts "                              SystemError(dsNoFPU=90) follows."
        } else {
            puts "                    hwCbFPU(bit4)=1 at last write => FPU bit STILL SET."
            puts "                              Bomb path uses a DIFFERENT detection than HWCfgFlags. Look for"
            puts "                              code that does its own FPU probe (FNOP, FMOVE, FSAVE inspection)"
            puts "                              and bombs on result independent of HWCfgFlags."
        }
    }
    if {[info exists idx(PSFW)]} {
        # Build #45 — FPU Save-CIR read capture (bug #6 phase 4).
        set sw [rd $idx(PSFW)]
        set sw_val   [expr {($sw >> 16) & 0xFFFF}]
        set sw_pclo  [expr {($sw >> 8) & 0xFF}]
        set sw_count [expr {$sw & 0xFF}]
        puts [format "           FPU-SFW: save_cir_reads(sat8)=%u  last_value=0x%04X  last_pc_lo=0x%02X" \
            $sw_count $sw_val $sw_pclo]
        if {$sw_count == 0} {
            puts "                    save_cir_reads=0 => CPU never read Save CIR. CIR_SAVE_FORMAT never"
            puts "                              reached, OR CPU bus access didn't hit FPU. Check PFST FSM trace."
        } elseif {$sw_val == 0x1F18} {
            puts "                    last_value=0x1F18 => FPU is delivering the correct IDLE 881 format word."
            puts "                              If the bomb still fires, the byte path FPU->memory is OK but"
            puts "                              memory->Mac OS read is being corrupted, OR Mac OS checks a"
            puts "                              different memory location."
        } elseif {$sw_val == 0x0000} {
            puts "                    last_value=0x0000 => FPU delivered NULL frame format word."
            puts "                              CIR_SAVE_WAIT took the NULL branch — fpu_initialized_reg='0'"
            puts "                              or frame_format_word_reg never updated."
        } elseif {$sw_val == 0x1FB4} {
            puts "                    last_value=0x1FB4 => FPU delivered BUSY 881 format word."
            puts "                              CIR_SAVE_WAIT took the busy='1' branch — ALU was busy at"
            puts "                              FSAVE time. Investigate why busy lingers."
        } else {
            puts [format "                    last_value=0x%04X => UNEXPECTED. Neither IDLE (0x1F18), BUSY" $sw_val]
            puts "                              (0x1FB4), NULL (0x0000), nor 882 IDLE (0x3F38). Something is"
            puts "                              corrupting the format word — investigate d_out_reg latch."
        }
    }
    if {[info exists idx(PSFM)]} {
        # Build #46 — FPU FSAVE format-word write capture (bug #6 phase 5).
        set sm [rd $idx(PSFM)]
        set sm_addr_lo  [expr {($sm >> 16) & 0xFFFF}]
        set sm_1f18_cnt [expr {($sm >> 8) & 0xFF}]
        set sm_any_cnt  [expr {$sm & 0xFF}]
        puts [format "           FPU-SFM: stack_writes(sat8)=%u  \$1F18_writes(sat8)=%u  last_\$1F18_addr_lo=0x%04X" \
            $sm_any_cnt $sm_1f18_cnt $sm_addr_lo]
        if {$sm_any_cnt == 0} {
            puts "                    stack_writes=0 => no CPU writes near user-mode stack \$003FF000-FFFF."
            puts "                              Probe filter never matched — A7 may be elsewhere."
        } elseif {$sm_1f18_cnt == 0} {
            puts "                    \$1F18 NEVER written to stack!"
            puts "                              FPU delivers 0x1F18 (per PSFW) but it never reaches memory."
            puts "                              The corruption is in the TG68 cp_save_fmt -> data_write_tmp"
            puts "                              -> bus path. Investigate data_write_muxin / data_write_mux"
            puts "                              for word writes during cp_save_wr_mem."
        } elseif {$sm_addr_lo == 0xFBBC} {
            puts "                    \$1F18 written at \$003FFBBC (matches Snow's A7_post)."
            puts "                              The format word IS reaching the right memory slot. Mac OS"
            puts "                              must be reading from a different address, OR there's a later"
            puts "                              write that overwrites \$1F18 before Mac OS reads it."
        } else {
            puts [format "                    \$1F18 written at \$003F%04X (NOT \$003FFBBC where Snow puts it)." $sm_addr_lo]
            puts "                              Format word reaches memory but at wrong address. A7 differs"
            puts "                              from Snow's \$003FFBD8 at FSAVE entry — investigate why."
        }
    }
    if {[info exists idx(PMTY)]} {
        # Build #57 — \$00000D28 trap-pointer writer capture.
        # Snow has \$0D28=\$40806486 (ROM pointer). LBMacTwo has \$00008CD8
        # (string-area pointer). Catches the bad write.
        set pkt [rd $idx(PMTY)]
        set hword [expr {($pkt >> 16) & 0xFFFF}]
        set pclo  [expr {$pkt & 0xFFFF}]
        puts [format "           FPU-MTY: \$0D28 last_write_hword=0x%04X  writer_pc_lo16=0x%04X" $hword $pclo]
        if {$hword == 0x0000} {
            puts "                    Written high word=\$0000 — caller wrote bad value (\$0000 8CD8)."
            puts "                              The source code intentionally wrote a string pointer here."
        } elseif {$hword == 0x4080} {
            puts "                    Written high word=\$4080 — caller wrote correct ROM ptr (\$4080 6486),"
            puts "                              but read returns wrong (\$0000 8CD8). SDRAM corruption."
        } elseif {$hword == 0} {
            puts "                    No write to \$0D28 captured yet."
        } else {
            puts [format "                    Written high word=0x%04X — unexpected. Disassemble at writer_pc_lo." $hword]
        }
        # Legacy build #47/50 MMUType decode blocks retired — PMTY layout
        # changed to $0D28 writer tracking in build #57. The old mt_wval/mt_rcnt
        # variables don't exist anymore; this block (was disabled behind `if {0}`)
        # crashed the script at the elseif because TCL eagerly evaluates the
        # elseif expressions. Removed entirely.
    }
    if {[info exists idx(PD28)]} {
        # Build #58 — longword read of \$00000D28. Step 1 of SDRAM-corruption
        # diagnostic. Known bad: should read Snow's \$40806486, observed \$00008CD8.
        set pd28 [rd $idx(PD28)]
        set pd28_hi [expr {($pd28 >> 16) & 0xFFFF}]
        set pd28_lo [expr {$pd28 & 0xFFFF}]
        puts [format "           SDR-D28: \$00000D28 longword = 0x%04X%04X  (Snow = 0x40806486)" $pd28_hi $pd28_lo]
        if {$pd28 == 0x40806486} {
            puts "                    MATCH Snow! \$0D28 reads CORRECT. Earlier corruption may have"
            puts "                              been transient or already fixed. Investigate sequencing."
        } elseif {$pd28 == 0x00008CD8} {
            puts "                    CONFIRMED bad value \$00008CD8. Trap dispatcher will jump into"
            puts "                              error-string area at \$8CD8 -> SystemError(90) bomb."
        } elseif {$pd28 == 0} {
            puts "                    No read of \$0D28 captured yet (CPU hasn't read it, or bomb"
            puts "                              fired before the dispatcher read fired)."
        } else {
            puts [format "                    UNEXPECTED value 0x%08X — neither Snow's good ptr nor the" $pd28]
            puts "                              previously-observed bad value. Different bug path."
        }
    }
    if {[info exists idx(PD24)]} {
        # Build #58 — longword read of \$00000D24. Step 1 systemic-vs-specific test.
        # Snow says \$00000D24 = \$000028FC.
        set pd24 [rd $idx(PD24)]
        set pd24_hi [expr {($pd24 >> 16) & 0xFFFF}]
        set pd24_lo [expr {$pd24 & 0xFFFF}]
        puts [format "           SDR-D24: \$00000D24 longword = 0x%04X%04X  (Snow = 0x000028FC)" $pd24_hi $pd24_lo]
        if {$pd24 == 0x000028FC} {
            puts "                    MATCH Snow! Corruption is SPECIFIC to \$0D28 (not systemic across"
            puts "                              low-mem longwords). Next: search for aliasing or for"
            puts "                              extra software writers of \$0D28 with value \$00008CD8."
        } elseif {$pd24 == 0} {
            puts "                    No read of \$0D24 captured yet — CPU hasn't read this addr in"
            puts "                              the observed window. Probe filter may not fit boot path."
        } else {
            puts [format "                    NOT Snow's value. SDRAM corruption is SYSTEMIC for low-mem"]
            puts "                              longwords, not specific to \$0D28. Most likely cause: SDRAM"
            puts "                              controller addr-stability bug — sdram.v samples \`addr\`"
            puts "                              both at T=0 (row) and T=3 (col) without latching, so any"
            puts "                              addr change between those two states corrupts writes."
        }
    }
    if {[info exists idx(PVCF)]} {
        # Build #62 — F-line vector RAM longword read (\$0000_00B0).
        # Latches both halves of the longword as the CPU reads them during
        # F-line exception entry. Snow reference: the runtime F-line handler
        # is usually patched to a ROM address in \$4000_DXXX range.
        set vcf [rd $idx(PVCF)]
        set vcf_hi [expr {($vcf >> 16) & 0xFFFF}]
        set vcf_lo [expr {$vcf & 0xFFFF}]
        set vcf_full [expr {($vcf_hi << 16) | $vcf_lo}]
        puts [format "           FPU-VCF: F-line vector at \$0000_00B0 longword = 0x%04X%04X (handler PC)" $vcf_hi $vcf_lo]
        if {$vcf == 0} {
            puts "                    No vector read seen yet (CPU hasn't taken an F-line trap in observed window)."
        } elseif {$vcf_full >= 0x40000000 && $vcf_full < 0x40100000} {
            puts [format "                    Handler in ROM at \$%08X. Disassemble boot0.rom there to see what runs on F-line." $vcf_full]
        } elseif {$vcf_full < 0x00400000} {
            puts [format "                    Handler in RAM at \$%08X (System file or boot-time patch)." $vcf_full]
        } else {
            puts [format "                    Handler at unusual address \$%08X — verify probe wiring." $vcf_full]
        }
    }
    if {[info exists idx(PFTS)]} {
        # Build #64 — F-line trap source PC, NON-STICKY: captures the LAST
        # F-line vector fetch's preceding super-IF PC. The bomb dialog
        # reads the LAST exception frame from the supervisor stack, so the
        # last F-line PC is more bomb-relevant than the first (build #63
        # captured the first at \$40803778 = FNOP detection prefetch).
        set ft [rd $idx(PFTS)]
        puts [format "           FPU-FLT: F-line trap source PC (last) = 0x%08X" $ft]
        if {$ft == 0} {
            puts "                    No F-line trap yet captured (PFLN count probably also 0)."
        } elseif {$ft >= 0x40000000} {
            puts [format "                    ROM PC. Disassemble boot0.rom near \$%08X to find the F-line instruction." $ft]
        } else {
            puts [format "                    RAM PC \$%08X — System file code. The Finder or a Mac OS extension issued the failing F-line." $ft]
        }
    }
    if {[info exists idx(PFLN)]} {
        # Build #62 — F-line vector-fetch (\$00B0/\$00B2) entry counter.
        # Prior session noted count=8 across boot. Re-verify now that bomb
        # mechanism is identified as F-line driven.
        set fln [rd $idx(PFLN)]
        set fln_count [expr {($fln >> 24) & 0xFF}]
        set fln_din   [expr {$fln & 0xFFFF}]
        puts [format "           FPU-FLN: F-line vector reads(sat8)=%u  last_din=0x%04X" $fln_count $fln_din]
        if {$fln_count == 0} {
            puts "                    No F-line vector fetch seen. F-line trap is NOT firing in this build."
            puts "                              The bomb path uses some other mechanism (not F-line directly)."
        } else {
            puts [format "                    F-line trap fired %u time(s). Compare to good-boot reference (prior session: 8)." $fln_count]
        }
    }
    if {[info exists idx(PBCP)]} {
        # Build #60 — bomb-caller PC capture. Sticky-locks the supervisor-IF
        # PC immediately before the FIRST entry into the bomb-dialog range
        # (\$40002400-\$400024FF). That's the JSR/JMP/Bxx instruction that
        # invoked the bomb. If PC == 0, no bomb-range entry has been seen
        # (boot still pre-bomb, or bomb path uses an addr range outside
        # the filter).
        set bcp [rd $idx(PBCP)]
        puts [format "           FPU-BCP: bomb-caller_pc=0x%08X" $bcp]
        if {$bcp == 0} {
            puts "                    No bomb-range entry seen — either pre-bomb sample, or the bomb"
            puts "                              dialog code lives at an addr range outside \$40002400-\$400024FF."
        } elseif {$bcp >= 0x40000000} {
            puts "                    ROM caller. Disassemble boot0.rom around this PC. The instruction"
            puts "                              there should be a JSR/JMP/Bxx whose target is in the bomb"
            puts "                              dialog range — that's how the bomb gets invoked."
        } else {
            puts "                    RAM caller — System file code (per project_bug6_session2 memory,"
            puts "                              hypothesized at PC~\$00014070). Disassemble RAM at this PC"
            puts "                              from the booted System file."
        }
    }
    if {[info exists idx(PFCS)]} {
        # Build #59 — _SysError (\$A9C9) instruction-fetch capture.
        # Layout: [31:8] = pfcs_last_pc[31:8]
        #         [7]    = pfcs_last_pc[7]   (bit-7 of PC for ROM/RAM check)
        #         [6:0]  = sat-7 count of \$A9C9 fetches.
        # Note: low 7 bits of PC are dropped (resolution = 128 bytes). A-trap
        # PCs are word-aligned so PC LSB is always 0; this still identifies
        # the calling routine.
        set pfcs [rd $idx(PFCS)]
        set fc_pc_hi24 [expr {($pfcs >> 8) & 0xFFFFFF}]
        set fc_pc_b7   [expr {($pfcs >> 7) & 0x1}]
        set fc_count   [expr {$pfcs & 0x7F}]
        set fc_pc_approx [expr {($fc_pc_hi24 << 8) | ($fc_pc_b7 << 7)}]
        puts [format "           FPU-FCS: _SysError(\$A9C9) fetch_pc≈0x%08X  count(sat7)=%u" \
            $fc_pc_approx $fc_count]
        if {$fc_count == 0} {
            puts "                    No \$A9C9 fetch captured yet. Bomb path either hasn't reached the"
            puts "                              _SysError A-trap or uses a different mechanism (direct JSR to"
            puts "                              bomb dialog code in ROM, bypassing the A-trap)."
        } elseif {$fc_pc_approx >= 0x40000000} {
            puts "                    ROM caller. Disassemble boot0.rom near this PC to find which ROM"
            puts "                              routine invokes _SysError. Likely a trampoline; trace back"
            puts "                              to who called THAT routine (look at the supervisor stack)."
        } else {
            puts "                    RAM caller — System file code. Disassemble boot0.rom + boot disk's"
            puts "                              System file at this RAM PC. This is the actual bomb-causing"
            puts "                              routine (per project_bug6_session2 memory: hypothesized at"
            puts "                              PC~\$00014070)."
        }
    }
    if {[info exists idx(PFLN)]} {
        # Build #35 — F-line vector fetch detector + berr counter (replaces PFTR).
        set ln [rd $idx(PFLN)]
        set ln_count    [expr {($ln >> 24) & 0xFF}]
        set ln_berr_cnt [expr {($ln >> 16) & 0xFF}]
        set ln_last_din [expr {$ln & 0xFFFF}]
        puts [format "           FPU-LFL: line_f_vec_reads(sat8)=%u  berr(sat8)=%u  last_handler_lo16=0x%04X" \
            $ln_count $ln_berr_cnt $ln_last_din]
        if {$ln_count == 0} {
            puts "                    line_f_vec_reads=0 => F-line trap entry never fired. Bomb is NOT via"
            puts "                              the F-line exception path. (For Sys 6 dsLineFErr expect>0.)"
        } else {
            puts "                    line_f_vec_reads>0 => F-line exception fired. last_handler_lo16 is the"
            puts "                              low 16 bits of the handler address (read from \$B0/\$B2)."
            puts "                              Compare across rounds: count delta around bomb visibility"
            puts "                              tells us the F-line trap is the bomb mechanism."
        }
    }
    if {[info exists idx(PFOQ)]} {
        # Build #35 — PC of last OpWord write (F-line instruction site).
        set opword_pc [rd $idx(PFOQ)]
        puts [format "           FPU-OPQ: last_opword_pc=0x%08X" $opword_pc]
        if {$opword_pc == 0} {
            puts "                    last_opword_pc=0 => no OpWord write seen yet (no cpGEN/cpSAVE/cpRESTORE)."
        } else {
            puts "                    Disassemble at this PC. Should be an F-line instruction (opword 1111xxxx)."
            puts "                              If RAM (\$00xxxxxx), it's a System-file-installed handler doing FPU work."
            puts "                              If ROM (\$4xxxxxxx), it's the Mac II startup ROM (TestForFPU or FPU init)."
        }
    }
    if {[info exists idx(PFOV)]} {
        # Build #35 — last 2 OpWord values.
        set ov [rd $idx(PFOV)]
        set opw_last [expr {($ov >> 16) & 0xFFFF}]
        set opw_prev [expr {$ov & 0xFFFF}]
        set cls_last [opword_class $opw_last]
        set cls_prev [opword_class $opw_prev]
        puts [format "           FPU-OPV: last_opword=0x%04X (%s)  prev_opword=0x%04X (%s)" \
            $opw_last $cls_last $opw_prev $cls_prev]
        if {$opw_last == 0} {
            puts "                    No OpWord written. Either FPU never reached or only FBcc was issued"
            puts "                              (FBcc writes Condition CIR, not OpWord CIR — see PFPD Cond-wr)."
        }
    }
    if {[info exists idx(PFRR)] && [info exists idx(PFRW)]} {
        # Build #35 — PFRR upgraded: FBcc vs prim Response read tracking.
        set rr [rd $idx(PFRR)]
        set rw [rd $idx(PFRW)]
        set last_resp     [expr {($rr >> 16) & 0xFFFF}]
        set last_was_fbcc [expr {($rr >> 15) & 0x1}]
        set prim_rd_cnt   [expr {($rr >> 8)  & 0x7F}]
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
        if {$last_resp == 0x0000} { set prim_hint "all zeros (FBF cond_word OR uninitialized)" }
        if {$last_was_fbcc} {
            set path_hint "FBcc cond_word"
        } else {
            set path_hint "prim path"
        }
        puts [format "           FPU-CIR Response \$22000: last=0x%04X (%s) %s | prim_rd_cnt(sat7)=%u ctrl_wr_cnt(wrap8)=%u" \
            $last_resp $path_hint $prim_hint $prim_rd_cnt $ctrl_wr_cnt]
        puts [format "           FPU-CIR Restore  \$22006: last=0x%04X | wr_cnt(wrap8)=%u opw_wr_cnt(wrap8)=%u" \
            $last_rest $rest_wr_cnt $opw_wr_cnt]
        if {$prim_rd_cnt == 0 && $opw_wr_cnt > 0} {
            puts "                 NOTE: opw_wr_cnt>0 but prim_rd_cnt=0 => CPU never reads Response for cpGEN/SAVE/RESTORE."
            puts "                       That's a TG68 protocol bug — every cpGEN-class write must be followed by a Response read."
        }
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
    if {[info exists idx(PRNG)] && [info exists idx(PRWF)]} {
        # Runaway/primal-fault ring, build #2 (2026-06-10b). PRWF layout:
        #   [31] frozen  [30:16] wild_entry_cnt  [15:8] stub_entry_cnt
        #   [7:5] oldest jump-pair slot/2 (0..5)  [4:3] oldest write slot
        #   [2] freeze_cause (1=wild >=1MB, 0=recovery-stub window)
        #   [1] iack_recent  [0] armed
        set wf [rd $idx(PRWF)]
        set frozen   [expr {($wf >> 31) & 1}]
        set wcnt     [expr {($wf >> 16) & 0x7FFF}]
        set scnt     [expr {($wf >> 8) & 0xFF}]
        set oldpair  [expr {($wf >> 5) & 0x7}]
        set oldwr    [expr {($wf >> 3) & 0x3}]
        set fcause   [expr {($wf >> 2) & 1}]
        set iackr    [expr {($wf >> 1) & 1}]
        set armed    [expr {$wf & 1}]
        puts [format "           RUNAWAY: frozen=%d armed=%d wild_entries=%u stub_entries=%u freeze_cause=%s iack_recent=%d" \
            $frozen $armed $wcnt $scnt [expr {$fcause ? "WILD>=1MB" : "STUB-WINDOW"}] $iackr]
        if {$frozen} {
            # 6 {src -> dst} jump pairs, oldest first (slots 0-11); LAST pair
            # = the jump that tripped the freeze. For a stub-window freeze:
            # src = the FAULTING PC, dst = recovery_stub_vN -> vector N.
            puts "           RUNAWAY jump ring (oldest -> newest; LAST pair = freeze trigger):"
            for {set p 0} {$p < 6} {incr p} {
                set slot [expr {(($oldpair + $p) % 6) * 2}]
                write_source_data -instance_index $idx(PRNG) -value [format "%X" $slot] -value_in_hex
                set src [rd $idx(PRNG)]
                write_source_data -instance_index $idx(PRNG) -value [format "%X" [expr {$slot + 1}]] -value_in_hex
                set dst [rd $idx(PRNG)]
                if {$src == 0 && $dst == 0} { continue }
                set delta [expr {$dst - $src}]
                set note ""
                # Map dst into the recovery-stub table (bench .hda a21bcdd1):
                # stubs at 0x40F3A + 14*k, order v2..v9, v11..v15, v32..v47.
                if {$dst >= 0x40F3A && $dst < 0x410D0} {
                    set k [expr {($dst - 0x40F3A) / 14}]
                    set vecs {2 3 4 5 6 7 8 9 11 12 13 14 15 \
                              32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47}
                    set vnames(2)  "bus error"
                    set vnames(3)  "address error"
                    set vnames(4)  "illegal instruction"
                    set vnames(5)  "zero divide"
                    set vnames(6)  "CHK"
                    set vnames(7)  "TRAPV"
                    set vnames(8)  "privilege violation"
                    set vnames(9)  "trace"
                    set vnames(11) "Line-F / coprocessor"
                    if {$k >= 0 && $k < [llength $vecs]} {
                        set v [lindex $vecs $k]
                        set nm2 [expr {[info exists vnames($v)] ? $vnames($v) : "TRAP #[expr {$v - 32}]"}]
                        set note [format "  <== recovery_stub_v%d (%s) -- src IS the FAULTING PC" $v $nm2]
                    }
                }
                # recovery.s landmarks — hda 33b6fc9c (stray-trap-fixed bench;
                # stub table unchanged from a21bcdd1)
                if {$dst == 0x410D0} { set note "  <== recovery_core (trap dispatch)" }
                if {$dst == 0x41122} { set note "  <== recovery_longjmp" }
                if {$dst == 0x411B0} { set note "  <== .resume (longjmp landed)" }
                puts [format "             pair %d: src=0x%08X -> dst=0x%08X  (delta %+d)%s" \
                    $p $src $dst $delta $note]
            }
            # Last-4 supervisor-data WRITE addresses before the freeze
            # (slots 12-15): exception-frame pushes cluster near the SSP;
            # $50Fxxxxx = DACK/IO writes from the pseudo-DMA loop.
            puts "           last-4 FC5 writes before freeze (oldest -> newest):"
            for {set p 0} {$p < 4} {incr p} {
                set slot [expr {12 + (($oldwr + $p) % 4)}]
                write_source_data -instance_index $idx(PRNG) -value [format "%X" $slot] -value_in_hex
                set wa [rd $idx(PRNG)]
                puts [format "             wr %d: 0x%08X" $p $wa]
            }
            if {[info exists idx(PIFD)]} {
                set ifd [rd $idx(PIFD)]
                set ifd_prev [expr {($ifd >> 16) & 0xFFFF}]
                set ifd_last [expr {$ifd & 0xFFFF}]
                puts [format "           last IF data before freeze: prev=0x%04X last=0x%04X" \
                    $ifd_prev $ifd_last]
                puts "                 (last should be the trapped opcode. 0xFFFA = the ROM"
                puts "                  DBF's own displacement word => fetch-stream DESYNC if it"
                puts "                  matches ROM content at the ring-src address; a word that"
                puts "                  does NOT match memory there => fetch DATA corruption.)"
            }
        } else {
            puts "           RUNAWAY: not frozen yet (no stub entry / wild IF since arming) -- reproduce, then re-read"
        }
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
