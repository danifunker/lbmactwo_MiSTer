# Read the PWR2 (first-word write) and PSEL (selection/command handshake)
# JTAG ISSP probes.
#   quartus_stp_tcl -t scripts/read_pwr.tcl

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
set pwr -1
set psel -1
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "PWR" || $nm eq "PWR2"} { set pwr $i }
    if {$nm eq "PSEL"} { set psel $i }
    incr i
}

catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw
set raw 0
set sraw 0
if {$pwr  >= 0} { set raw  [expr 0x[read_probe_data -instance_index $pwr  -value_in_hex]] }
if {$psel >= 0} { set sraw [expr 0x[read_probe_data -instance_index $psel -value_in_hex]] }
end_insystem_source_probe

proc bits {v hi lo} { return [expr {($v >> $lo) & ((1 << ($hi - $lo + 1)) - 1)}] }
set phn {IDLE CMD_IN DATA_OUT DATA_IN STATUS MSG ? ?}

if {$pwr >= 0} {
    puts [format "PWR2 raw=0x%08X" $raw]
    puts [format "  target byte0=0x%02X byte1=0x%02X | intended low=0x%02X | dma_word=%d dma_long=%d b0=%d b1=%d" \
        [bits $raw 7 0] [bits $raw 15 8] [bits $raw 23 16] [bits $raw 24 24] [bits $raw 25 25] [bits $raw 26 26] [bits $raw 27 27]]
} else { puts "PWR/PWR2 not found" }

if {$psel >= 0} {
    set ph  [bits $sraw 2 0]
    set mph [bits $sraw 5 3]
    puts [format "PSEL raw=0x%08X" $sraw]
    puts [format "  phase=%s max_phase=%s | sel=%d bsy=%d req=%d ack=%d" \
        [lindex $phn $ph] [lindex $phn $mph] [bits $sraw 6 6] [bits $sraw 7 7] [bits $sraw 8 8] [bits $sraw 9 9]]
    puts [format "  reached_DATA=%d  req_while_sel=%d  cmd_bytes=%d" \
        [bits $sraw 10 10] [bits $sraw 18 11] [bits $sraw 26 19]]
    if {[bits $sraw 10 10]} {
        puts "  => command phase advanced to DATA (selection fix working)."
    } else {
        puts "  => never reached DATA (still stuck at/before command)."
    }
} else { puts "PSEL not found" }
