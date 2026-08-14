# Read every ISSP probe present in the loaded bitstream (FPCS + PRST decks).
#   quartus_stp -t scratch/read_deck.tcl
# PRST layout (LBMacTwo.sv DBG_FPU block):
#   [31:24] n_reset assertion count since FPGA config (config+first boot = 1)
#   [22:16] latched cause at the LAST assertion, [6:0] live cause now
#   cause bits (both fields, MSB..LSB):
#     {!sys_locked, osd_reset_req, buttons[1], RESET, !clear_done,
#      pram_force_reset, !pram_ready}
# FPCS layout (mc68881_top.vhd:46):
#   [31:16] response primitive, [15:11] cir_state, [10:6] MAX state seen,
#   [2] except-seen, [1] restore-frame-seen, [0] cir_active
set hw ""
foreach h [get_hardware_names] { if {[string match "DE-SoC*" $h]} { set hw $h; break } }
set dev ""
if {$hw ne ""} {
    foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
}
puts "hw=$hw dev=$dev"
if {$dev eq ""} { puts "** no device **"; exit 1 }

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
start_insystem_source_probe -device_name $dev -hardware_name $hw
set i 0
foreach inst $info {
    set name [lindex $inst 3]
    set v [expr 0x[read_probe_data -instance_index $i -value_in_hex]]
    puts [format "%-6s = 0x%08X" $name $v]
    if {$name eq "PRST"} {
        set cnt   [expr ($v >> 24) & 0xFF]
        set last  [expr ($v >> 16) & 0x7F]
        set live  [expr $v & 0x7F]
        puts [format "  reset assertions since config: %d" $cnt]
        set names {!sys_locked osd_reset_req buttons1 RESET !clear_done pram_force_reset !pram_ready}
        set lastl {} ; set livel {}
        for {set b 0} {$b < 7} {incr b} {
            set bit [expr 6 - $b]
            if {($last >> $bit) & 1} { lappend lastl [lindex $names $b] }
            if {($live >> $bit) & 1} { lappend livel [lindex $names $b] }
        }
        puts "  cause at last assertion: [expr {[llength $lastl] ? $lastl : {none}}]"
        puts "  cause live now         : [expr {[llength $livel] ? $livel : {none}}]"
    }
    if {$name eq "FPCS"} {
        puts [format "  cir_state=%d  max_state=%d  cir_active=%d  except_seen=%d  restore_frame_seen=%d" \
            [expr ($v >> 11) & 0x1F] [expr ($v >> 6) & 0x1F] [expr $v & 1] \
            [expr ($v >> 2) & 1] [expr ($v >> 1) & 1]]
        puts [format "  response primitive = 0x%04X" [expr ($v >> 16) & 0xFFFF]]
    }
    incr i
}
end_insystem_source_probe
