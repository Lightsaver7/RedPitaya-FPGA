set prj_name [lindex $argv 0]
cd prj/$prj_name

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

set path_sdk "sdk"
set xsa_file $path_sdk/red_pitaya.xsa
set fsbl_dts_dir $path_sdk/fsbl_dts
set proc_name "ps7_cortexa9_0"
set platform redpitaya_platform
set platform_name "redpitaya_platform"
# Match your processor name in Vivado
# -------------------------------

puts "INFO: Generating FSBL DTS using XSA: $xsa_file"

createdts -hw $xsa_file -platform-name $platform_name -git-branch xlnx_rel_v$ver -overlay -out $fsbl_dts_dir

if {[file exists $path_sdk/dts/bsp]} {
    file delete -force $path_sdk/dts/bsp
}

puts "Cur dir: [pwd]"
file copy -force $path_sdk/fsbl_dts/sdk/fsbl_dts/redpitaya_platform/ps7_cortexa9_0/device_tree_domain/bsp $path_sdk/dts

exit
