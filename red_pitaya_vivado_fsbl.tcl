################################################################################
# Vivado tcl script for building RedPitaya FPGA in non project mode
#
# Usage:
# vivado -mode tcl -source red_pitaya_vivado_Z10.tcl -tclargs projectname
################################################################################


puts "Input arfguments: $argv"
foreach item $argv {
   if {[lsearch -all $item "*MODEL*"] >= 0} {
      set list [split $item "="]
      set board_cpu_model [lindex $list 1]
      puts "Board CPU model: $board_cpu_model"
   }

   if {[lsearch -all $item "*RAM*"] >= 0} {
      set list [split $item "="]
      set board_ram_size [lindex $list 1]
      puts "Board RAM size: $board_ram_size"
   }
}

set prj_top "red_pitaya_top"
set prj_dir "build"

cd prj/fsbl


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
# set path_ip_top  ../../ip
# set path_bd  $prj_dir/redpitaya.gen/sources_1/bd/system/hdl
# set path_bd_src  $prj_dir/redpitaya.srcs/sources_1/bd/system
# set path_sdc ../../sdc
# set path_sdc_prj sdc

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

if {$board_cpu_model != "Z10"} {
   set part xc7z010clg400-1
   set ::cpu_part xc7z010clg400-1
   set ::gpio_width 24
}

if {$board_cpu_model != "Z20"} {
   set part xc7z020clg400-1
   set ::cpu_part xc7z020clg400-1
   set ::gpio_width 33
}

if {$board_ram_size != "512"} {
   set part xc7z010clg400-1
   set ::ram_bit "16 Bits"

}

if {$board_ram_size != "1024"} {
   set part xc7z020clg400-1
   set ::ram_bit "32 Bits"
}

create_project -part $part -force redpitaya $prj_dir

################################################################################
# create PS BD (processing system block design)
################################################################################

# file was created from GUI using "write_bd_tcl -force ip/systemZ10.tcl"
# create PS BD
set ::hp0_clk_freq 125000000
set ::hp1_clk_freq 125000000
set ::hp2_clk_freq 250000000
set ::hp3_clk_freq 250000000

source  $path_ip/system.tcl
# set_property verilog_define [concat Z10 $prj_defs] [current_fileset]

# generate SDK files
# generate_target all [get_files system.bd]
# make_wrapper -files [get_files *.bd] -top

#write_hwdef -force       -file    $path_sdk/red_pitaya.hwdef


################################################################################
# read files:
# 1. RTL design sources
# 2. IP database files
# 3. constraints
################################################################################

add_files -quiet                  [glob -nocomplain ../../$path_rtl/*_pkg.sv]
add_files -quiet                  [glob -nocomplain       $path_rtl/*_pkg.sv]

add_files                         ../../$path_rtl
# add_files -fileset constrs_1      $path_sdc/red_pitaya.xdc

add_files                         $path_rtl
# add_files                         $path_bd

# set ip_files [glob -nocomplain $path_ip/*.xci]
# if {$ip_files != ""} {
# add_files                         $ip_files
# }

# if {[file isdirectory $path_ip_top/asg_dat_fifo]} {
# source ${path_ip_top}/asg_dat_fifo/asg_dat_fifo.tcl
# }

# if {[file isdirectory $path_ip_top/sync_fifo]} {
# source ${path_ip_top}/sync_fifo/sync_fifo.tcl
# }

# add_files -fileset constrs_1      $path_sdc_prj/red_pitaya.xdc

################################################################################
# ser parameter containing Git hash
################################################################################

set gith [exec git log -1 --format="%H"]
set_property generic "GITH=160'h$gith" [current_fileset]
set_property top $prj_top [current_fileset]

puts "GIT = $gith"

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
# generate system definition
################################################################################


set_property platform.default_output_type "sd_card" [current_project]
set_property platform.board_id "redpitaya" [current_project]
set_property platform.name "redpitaya_platform" [current_project]

write_hw_platform -fixed -force -file $path_sdk/red_pitaya.xsa

exit
