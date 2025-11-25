################################################################################
# HSI tcl script for building RedPitaya DTS (device tree)
#
# Usage:
# hsi -mode tcl -source red_pitaya_hsi_dts.tcl -tclargs projectname
################################################################################


set prj_name [lindex $argv 0]
cd prj/$prj_name

set path_sdk sdk
set xsa_file $path_sdk/red_pitaya.xsa
set output_dir out/dts


set ver 2025.1

foreach item $argv {
  puts "Input arfguments: $argv"
  if {[lsearch -all $item "*DTS_VER*"] >= 0} {
    set param [split $item "="]
    if {[lindex $param 1] ne ""} {
      set ver [lindex $param 1]
    }
  }
}

puts "DTS version: $ver"
puts "Cur dir: [pwd]"

#  The old method of creating a device tree is now deprecated.
##hsi open_hw_design $xsa_file
##hsi open_hw_design $path_sdk/red_pitaya.sysdef
#hsi set_repo_path ../../dl/device-tree-xlnx-xilinx-v$ver/
#hsi create_sw_design device-tree -os device_tree -proc ps7_cortexa9_0
#hsi set_property CONFIG.kernel_version $ver [hsi get_os]
#hsi set_property CONFIG.dt_overlay true [hsi::get_os]
#hsi generate_target -dir $output_dir

#########################################################################

# New method for creating device tree, does not support overlay yet.

#sdtgen set_dt_param -xsa $xsa_file -dir $output_dir
#sdtgen set_dt_param -repo ../../dl/device-tree-xlnx-xilinx-v$ver/
#sdtgen set_dt_param -zocl enable
#sdtgen generate_sdt

#########################################################################


createdts -hw $xsa_file -platform-name redpitaya_platform -git-branch xlnx_rel_v$ver -overlay -out $output_dir

puts "INFO: Device Tree generation complete."
