# Capture SignalTap data via JTAG and write to CSV.
# Run via: quartus_stp_tcl -t scripts/stp_capture.tcl <stp_file> <out_csv> [num_acquisitions]
#
# Requires the design to be programmed already (use scripts/program_fpga.tcl first).

package require ::quartus::stp

set stp_file [lindex $argv 0]
set out_file [lindex $argv 1]
set num_acq  [expr {[llength $argv] >= 3 ? [lindex $argv 2] : 1}]

if {$stp_file eq "" || $out_file eq ""} {
    puts "Usage: quartus_stp_tcl -t stp_capture.tcl <stp_file> <out_csv> \[num_acquisitions\]"
    exit 1
}

puts "Opening $stp_file ..."
open_session -name $stp_file

# List instances
set instances [get_instance_names]
puts "Instances: $instances"
if {[llength $instances] == 0} {
    puts "No SignalTap instances found in $stp_file."
    exit 1
}
set inst [lindex $instances 0]
puts "Using instance: $inst"

# Make sure JTAG hardware/device are set
set hw "DE-SoC \[USB-1\]"
set dev 2
catch { set_instance_property -name HARDWARE_NAME -value $hw -instance $inst }
catch { set_instance_property -name DEVICE_INDEX  -value $dev -instance $inst }

# Run acquisition(s)
for {set i 0} {$i < $num_acq} {incr i} {
    puts "Acquisition $i ..."
    if {[catch { run -instance $inst -signal_set signal_set_1 -trigger trigger_1 } err]} {
        puts "run failed: $err"
        break
    }
    set csv "${out_file}.${i}.csv"
    catch { write_acquisition_data -instance $inst -csv $csv -format ALL }
    puts "Wrote $csv"
}

close_session
puts "Done."
