# Read the FPU CIR-state probe (FPCS = fpu_dbg_cir_state), one shot.
#   quartus_stp_tcl -t scripts/read_fpu.tcl
# JTAG-only (zero HPS load). Run AT the SimpleText-launch hard lock to see what
# the FPU is wedged on. Layout: mc68881_top.vhd:46 + cir_dialog_state_t
# (mc68881_pkg.vhd:308). Read-only; reuses dbg_coldinit's JTAG hub.

set hw ""
foreach h [get_hardware_names] { if {[string match "DE-SoC*" $h]} { set hw $h; break } }
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
set fidx -1
set i 0
foreach inst $info {
    if {[lindex $inst 3] eq "FPCS"} { set fidx $i }
    incr i
}
if {$fidx < 0} { puts "** FPCS probe not found (is DBG_FPU build loaded?) **"; exit 1 }

start_insystem_source_probe -device_name $dev -hardware_name $hw
set v [expr 0x[read_probe_data -instance_index $fidx -value_in_hex]]
end_insystem_source_probe

set STATES {CIR_IDLE CIR_DECODE CIR_XFER_SRC CIR_XFER_SRC_WAIT CIR_XFER_SRC_WAIT2 \
    CIR_EXECUTE CIR_EXECUTE_DONE CIR_XFER_DST CIR_XFER_DST_WAIT CIR_COND_EVAL \
    CIR_COND_WAIT CIR_COND_CHECK CIR_EXCEPT_PRE CIR_EXCEPT_MID CIR_EXCEPT_POST \
    CIR_SAVE_WAIT CIR_SAVE_FORMAT CIR_SAVE_FRAME CIR_RESTORE_FORMAT CIR_RESTORE_FRAME \
    CIR_PENDING_DECODE CIR_PENDING_XFER_SRC CIR_PENDING_XFER_SRC_WAIT \
    CIR_PENDING_XFER_SRC_WAIT2 CIR_PENDING_XFER_SRC_WAIT3}
proc nm {lst i} { if {$i < [llength $lst]} { return [lindex $lst $i] } else { return "??($i)" } }

set resp     [expr {($v >> 16) & 0xFFFF}]
set state    [expr {($v >> 11) & 0x1F}]
set maxstate [expr {($v >> 6) & 0x1F}]
set opword   [expr {($v >> 5) & 1}]
set command  [expr {($v >> 4) & 1}]
set trigger  [expr {($v >> 3) & 1}]
set except   [expr {($v >> 2) & 1}]
set restfrm  [expr {($v >> 1) & 1}]
set active   [expr {$v & 1}]

puts "================ FPU CIR STATE (raw 0x[format %08X $v]) ================"
puts [format "cir_state NOW    : %-20s (%d)" [nm $STATES $state] $state]
puts [format "MAX state seen   : %-20s (%d)" [nm $STATES $maxstate] $maxstate]
puts [format "response prim    : 0x%04X  %s" $resp \
      [expr {$resp == 0x8900 ? "BUSY(come-again)" : $resp == 0x0900 ? "NULL(release)" : ""}]]
puts [format "sticky: opword=%d command=%d restore_trig=%d EXCEPT=%d RESTORE_FRAME=%d cir_active=%d" \
      $opword $command $trigger $except $restfrm $active]
puts "------------------------------------------------------------"
if {$state == 5}  { puts ">> WEDGED IN CIR_EXECUTE  => a stuck ARITH op (divrem/etc not completing)" }
if {$state == 19} { puts ">> WEDGED IN CIR_RESTORE_FRAME => stuck FRESTORE (context-switch)" }
if {$state == 17} { puts ">> WEDGED IN CIR_SAVE_FRAME    => stuck FSAVE (context-switch)" }
if {$except}      { puts ">> an exception/F-line was taken (except_seen sticky set)" }
puts "============================================================"
