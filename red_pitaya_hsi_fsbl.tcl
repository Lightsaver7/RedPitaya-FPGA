set prj_name [lindex $argv 0]
cd prj/$prj_name

#set path_sdk sdk

#hsi open_hw_design $path_sdk/red_pitaya.sysdef
#hsi open_hw_design $path_sdk/red_pitaya.sysdef
#hsi generate_app -hw system_0 -os standalone -proc ps7_cortexa9_0 -app zynq_fsbl -compile -sw fsbl -dir $path_sdk/fsbl

#exit

set path_sdk "sdk"
set xsa_file $path_sdk/red_pitaya.xsa
# Assumes you have an XSA file, not sysdef
set fsbl_dir $path_sdk/fsbl
set proc_name "ps7_cortexa9_0"
set platform redpitaya_platform
set domain_name "standalone_domain"
# Match your processor name in Vivado
# -------------------------------

puts "INFO: Generating FSBL application using XSA: $xsa_file"

# 1. Create a Vitis workspace if one doesn't exist (required by xsct app commands)
# This creates a workspace directory next to your script
set workspace_dir "build-fsbl"
if {[file exists $workspace_dir]} {
    file delete -force $workspace_dir
}
file mkdir $workspace_dir
setws $workspace_dir

# 2. Create the platform project using the XSA file
# The platform name is arbitrary (e.g., my_platform)
platform create -name $platform -hw $xsa_file

puts "Platform create"

domain create -name $domain_name -os standalone -proc $proc_name

platform generate

puts "Platform generate DONE"

puts "Cur dir: [pwd]"

file copy $workspace_dir/$platform/zynq_fsbl/fsbl.elf out/fsbl.elf

puts "INFO: FSBL generation and compilation complete in $workspace_dir/fsbl_app."


exit
