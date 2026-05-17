# Program FPGA via JTAG with the most recent .sof.
# Run via: quartus_pgm -t scripts/program_fpga.tcl
# Or directly: quartus_pgm -m JTAG -c "DE-SoC [USB-1]" -o "P;output_files/LBMacTwo.sof@2"
set hardware "DE-SoC [USB-1]"
set device_index 2
set sof_file "output_files/LBMacTwo.sof"
puts "Programming $sof_file to device @$device_index on $hardware"
exec quartus_pgm -m JTAG -c $hardware -o "P;$sof_file@$device_index" >@stdout
