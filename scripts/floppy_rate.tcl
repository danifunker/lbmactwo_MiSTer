# Floppy-rate measurement helper.
# Reads PFLP and PIWM twice with a configurable gap, computes KB/s and
# compares against Snow's baseline (scratch/snow_compare/baseline.md).
#
# Usage:
#   quartus_stp_tcl -t scripts/floppy_rate.tcl [gap_seconds]
#
# Default gap = 5 seconds.

set gap_s 5
if {$argc >= 1} {
    set gap_s [lindex $argv 0]
}

# --- cable / device discovery (copied from cpu_state.tcl) ----------------
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
    foreach d [get_device_names -hardware_name $hw] {
        if {[string match "*5CSE*" $d]} { set dev $d; break }
    }
}
puts "hw=$hw dev=$dev gap=${gap_s}s"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "PFLP"} { set idx(PFLP) $i }
    if {$nm eq "PIWM"} { set idx(PIWM) $i }
    if {$nm eq "PACT"} { set idx(PACT) $i }
    incr i
}

if {![info exists idx(PFLP)]} {
    puts "ERROR: PFLP probe not found. Build may not have it."
    exit 1
}
if {![info exists idx(PIWM)]} {
    puts "ERROR: PIWM probe not found. Build may not have it."
    exit 1
}

proc rd {ix} {
    # quartus_stp_tcl's read_probe_data doesn't take -device_name /
    # -hardware_name; they're already set by the surrounding session
    # via begin_memory_edit / similar. Use the same form cpu_state.tcl
    # uses.
    return [expr 0x[read_probe_data -instance_index $ix -value_in_hex]]
}

proc sample {} {
    set fp [rd $::idx(PFLP)]
    set iw [rd $::idx(PIWM)]
    set t_us [clock microseconds]

    set miss   [expr {$fp & 0xFFFF}]
    set bytes  [expr {($fp >> 16) & 0xFFFF}]
    set armh   [expr {$iw & 0x7F}]
    set staged [expr {($iw >> 7) & 0x1}]
    set latch  [expr {($iw >> 8) & 0xFF}]
    set acks   [expr {($iw >> 16) & 0xFFFF}]

    return [list $t_us $bytes $miss $acks $latch $staged $armh]
}

proc wrap_delta {new old width} {
    set mask [expr {(1 << $width) - 1}]
    set d [expr {($new - $old) & $mask}]
    return $d
}

puts "Sampling t=0..."
set s1 [sample]
puts [format "  t=0  byte_cnt=%5u  miss=%5u  ack=%5u  latch=0x%02X  staged=%d  armH=0x%02X" \
    [lindex $s1 1] [lindex $s1 2] [lindex $s1 3] \
    [lindex $s1 4] [lindex $s1 5] [lindex $s1 6]]

after [expr {$gap_s * 1000}]

puts "Sampling t=${gap_s}s..."
set s2 [sample]
puts [format "  t=%us  byte_cnt=%5u  miss=%5u  ack=%5u  latch=0x%02X  staged=%d  armH=0x%02X" \
    $gap_s [lindex $s2 1] [lindex $s2 2] [lindex $s2 3] \
    [lindex $s2 4] [lindex $s2 5] [lindex $s2 6]]

# Delta math — counters are 16-bit wrapping
set d_byte [wrap_delta [lindex $s2 1] [lindex $s1 1] 16]
set d_miss [wrap_delta [lindex $s2 2] [lindex $s1 2] 16]
set d_ack  [wrap_delta [lindex $s2 3] [lindex $s1 3] 16]

set elapsed_us [expr {[lindex $s2 0] - [lindex $s1 0]}]
set elapsed_s  [expr {$elapsed_us / 1.0e6}]

set bytes_per_s [expr {$d_byte / $elapsed_s}]
set kb_per_s    [expr {$bytes_per_s / 1024.0}]
set ack_per_s   [expr {$d_ack  / $elapsed_s}]
set ack_kb_per_s [expr {$ack_per_s / 1024.0}]

if {$d_byte > 0} {
    set miss_pct [expr {$d_miss * 100.0 / ($d_byte + $d_miss)}]
} else {
    set miss_pct 0.0
}

puts ""
puts "================ RESULT ================"
puts [format "elapsed wall-clock      : %.3f s" $elapsed_s]
puts [format "delta byte_cnt          : %5u bytes" $d_byte]
puts [format "delta miss_cnt          : %5u" $d_miss]
puts [format "delta ack (SDRAM grants): %5u" $d_ack]
puts [format "byte rate               : %7.2f KB/s" $kb_per_s]
puts [format "SDRAM-grant rate        : %7.2f KB/s" $ack_kb_per_s]
puts [format "miss rate               : %5.1f %% (of byte+miss events)" $miss_pct]
puts ""
puts "Snow baseline targets (scratch/snow_compare/baseline.md):"
puts "  peak       : 60.29 KB/s (must hit >=58 KB/s briefly during heavy load)"
puts "  sustained  : 57.79 KB/s (must hit >=50 KB/s sustained during disk-active)"
puts "  miss rate  : ~59 % overall (informational; <5 % during tight read bursts)"
puts ""

if {$kb_per_s < 1.0 && $d_byte == 0} {
    puts "VERDICT: no bytes flowing. Either (a) drive idle / motor off / floppy not selected,"
    puts "         or (b) delivery condition failing (drive-select / _enable / readyToAdvance stuck)."
} elseif {$kb_per_s < 10.0} {
    puts "VERDICT: byte rate well below Snow baseline. Bug confirmed in floppy delivery layer."
    if {$d_ack > 0 && $ack_kb_per_s > $kb_per_s * 2} {
        puts "         SDRAM grants exceed byte delivery -> arbiter is feeding faster than"
        puts "         floppy is delivering. Bottleneck is in floppy.v / iwm fclk path."
    } elseif {$d_ack < $d_byte * 0.5} {
        puts "         SDRAM grants well below byte rate -> arbiter is starving the floppy."
        puts "         Look at sdram_arbiter.v dskReadAck path."
    }
} elseif {$kb_per_s < 30.0} {
    puts "VERDICT: byte rate is roughly half Snow's. Possible mild bottleneck."
} elseif {$kb_per_s < 50.0} {
    puts "VERDICT: byte rate below sustained Snow target but workable."
} else {
    puts "VERDICT: byte rate within healthy band. Slowness is elsewhere (HFS? sector retries?)."
}
