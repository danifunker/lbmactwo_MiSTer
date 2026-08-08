# Focused reader for the 5-probe dbg_wedge build (PADR/PSTA/PACT/PFLO/PFST).
# Standalone (does NOT need PFLA like cpu_state.tcl's F-line block does).
#   quartus_stp_tcl -t scripts/read_wedge.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "*USB-Blaster*" $h] || [string match "DE-SoC*" $h]} { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
puts "hw=$hw dev=$dev"
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    foreach w {PADR PSTA PACT PFLO PFST} { if {$nm eq $w} { set idx($w) $i } }
    incr i
}
foreach w {PADR PSTA PACT PFLO PFST} { if {![info exists idx($w)]} { puts "MISSING $w" } }
start_insystem_source_probe -device_name $dev -hardware_name $hw
proc rd {i} { return [expr 0x[read_probe_data -instance_index $i -value_in_hex]] }
proc fcn {fc} { switch $fc {1 {return userData} 2 {return userProg} 5 {return supvData} 6 {return supvProg} 7 {return cpuSpace} default {return "fc$fc"}} }
for {set s 1} {$s <= 6} {incr s} {
    set adr [rd $idx(PADR)]
    set sta [rd $idx(PSTA)]
    set act [rd $idx(PACT)]
    set flo [rd $idx(PFLO)]
    set fst [rd $idx(PFST)]
    set fc   [expr {($sta >> 4) & 0x7}]
    set asn  [expr {($sta >> 7) & 1}]
    set rw   [expr {($sta >> 8) & 1}]
    set dtk  [expr {($sta >> 9) & 1}]
    set sfpu [expr {($sta >> 12) & 1}]
    set sram [expr {($sta >> 13) & 1}]
    set srom [expr {($sta >> 14) & 1}]
    set snub [expr {($sta >> 15) & 1}]
    set mdv  [expr {($sta >> 18) & 1}]
    set op   [expr {($flo >> 16) & 0xFFFF}]
    set cnt  [expr {$flo & 0xFFFF}]
    set fsm  [expr {$fst & 0xFF}]
    set maxst [expr {($fst >> 8) & 0xFF}]
    set prim [expr {($fst >> 16) & 0xFFFF}]
    puts [format "s%d PC=0x%08X AS_cyc=%u | %s AS_n=%d RW=%d DTACK_n=%d selFPU=%d selRAM=%d selROM=%d selNuBus=%d mdv=%d" \
        $s $adr $act [fcn $fc] $asn $rw $dtk $sfpu $sram $srom $snub $mdv]
    puts [format "     F-line: last_op=0x%04X fetch_cnt(wrap16)=%u | FPU-FSM state=%d max=%d resp_prim=0x%04X" \
        $op $cnt $fsm $maxst $prim]
}
end_insystem_source_probe
