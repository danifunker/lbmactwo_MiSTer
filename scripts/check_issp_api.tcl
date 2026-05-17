package require ::quartus::insystem_source_probe
# Open with no instance — see what's available before any device is attached.
foreach c [lsort [info commands]] {
    if {[regexp {(insystem|probe|source)} $c]} { puts "ROOT: $c" }
}
foreach pkg [list ::quartus::insystem_source_probe ::quartus::jtag] {
    foreach c [info commands ${pkg}::*] { puts "$pkg: $c" }
}
