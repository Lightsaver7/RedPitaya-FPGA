################################################################################
# Vivado tcl script for building RedPitaya FPGA in non project mode
#
# Usage:
# vivado -mode tcl -source red_pitaya_vivado_Z10.tcl -tclargs projectname
################################################################################

set prj_name [lindex $argv 0]
set prj_defs [lindex $argv 1]
puts "Project name: $prj_name"
puts "Defines: $prj_defs"
cd prj/$prj_name
#cd prj/$::argv 0


################################################################################
# install UltraFast Design Methodology from TCL Store
################################################################################

tclapp::install -quiet ultrafast

################################################################################
# define paths
################################################################################

set path_brd ../../brd
set path_rtl rtl
set path_ip      ip
set path_ip_top  ../../ip
#set path_bd  .srcs/sources_1/bd/system
set path_bd  .gen/sources_1/bd/system/hdl
set path_sdc ../../sdc
set path_sdc_prj sdc

set path_out out
set path_sdk sdk

file mkdir $path_out
file mkdir $path_sdk

################################################################################
# list board files
################################################################################

set_param board.repoPaths [list $path_brd]
set_param iconstr.diffPairPulltype {opposite}

################################################################################
# setup an in memory project
################################################################################

set part xc7z010clg400-1

create_project -part $part -force redpitaya $prj_dir

################################################################################
# create PS BD (processing system block design)
################################################################################

# file was created from GUI using "write_bd_tcl -force ip/systemZ10.tcl"
# create PS BD
set ::gpio_width 24
set ::hp0_clk_freq 125000000
set ::hp1_clk_freq 125000000
set ::hp2_clk_freq 250000000
set ::hp3_clk_freq 250000000

source                            $path_ip/systemZ10.tcl
set_property verilog_define [concat Z10 $prj_defs] [current_fileset]

# generate SDK files
generate_target all [get_files    system.bd]
write_hwdef -force       -file    $path_sdk/red_pitaya.hwdef

################################################################################
# read files:
# 1. RTL design sources
# 2. IP database files
# 3. constraints
################################################################################

add_files -quiet                  [glob -nocomplain ../../$path_rtl/*_pkg.sv]
add_files -quiet                  [glob -nocomplain       $path_rtl/*_pkg.sv]

if {$prj_name != "pyrpl"} {
add_files                         ../../$path_rtl
add_files -fileset constrs_1      $path_sdc/red_pitaya.xdc
}

add_files                               $path_rtl
add_files                               $path_bd

set ip_files [glob -nocomplain $path_ip/*.xci]
if {$ip_files != ""} {
add_files                         $ip_files
}

if {[file isdirectory $path_ip_top/asg_dat_fifo]} {
source ${path_ip_top}/asg_dat_fifo/asg_dat_fifo.tcl
}

if {[file isdirectory $path_ip_top/sync_fifo]} {
source ${path_ip_top}/sync_fifo/sync_fifo.tcl
}

add_files -fileset constrs_1      $path_sdc_prj/red_pitaya.xdc

################################################################################
# ser parameter containing Git hash
################################################################################

set gith [exec git log -1 --format="%H"]
set_property generic "GITH=160'h$gith" [current_fileset]

################################################################################
# run synthesis
# report utilization and timing estimates
# write checkpoint design
################################################################################

update_compile_order -fileset sources_1

launch_runs synth_1
wait_on_run synth_1

set rptFiles [glob -directory ./$prj_dir/redpitaya.runs/synth_1/  *.rpt]
file copy -force $rptFiles ./$path_out/

################################################################################
# run placement and logic optimization
# report utilization and timing estimates
# write checkpoint design
################################################################################

launch_runs impl_1 -jobs 2
wait_on_run impl_1

set rptFiles [glob -directory ./$prj_dir/redpitaya.runs/impl_1/  *.rpt]
foreach file $rptFiles {
   file copy -force $file ./$path_out/
}
################################################################################
# generate a bitstream
################################################################################

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

launch_runs impl_1 -to_step write_bitstream

open_run impl_1
write_bitstream -force            $path_out/red_pitaya.bit
write_bitstream -force -bin_file  $path_out/red_pitaya


################################################################################
# generate system definition
################################################################################


write_sysdef -force      -hwdef   $path_sdk/red_pitaya.hwdef \
                         -bitfile $path_out/red_pitaya.bit \
                         -file    $path_sdk/red_pitaya.sysdef

#set_property platform.board_id "redpitaya" [current_project]
#set_property platform.name "redpitaya_platform" [current_project]
#write_hw_platform -fixed -force -file $path_sdk/red_pitaya.xsa

exit
