
################################################################
# This is a generated script based on design: system
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]


################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}
   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source system_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part $::cpu_part
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name system

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES:
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
set path_ip $script_folder
# update_compile_order -fileset sources_1
set_property ip_repo_paths $::stream_app_rtl [current_project]
update_ip_catalog

if { $bCheckIPs == 1 } {
   set list_check_ips "\
         xilinx.com:ip:clk_wiz:6.0\
         xilinx.com:ip:xlconcat:2.1\
         xilinx.com:ip:processing_system7:5.5\
         redpitaya.com:user:rp_concat:1.0\
         redpitaya.com:user:rp_dac:1.0\
         redpitaya.com:user:rp_gpio:1.0\
         redpitaya.com:user:rp_oscilloscope:1.16\
         xilinx.com:ip:proc_sys_reset:5.0"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

   variable script_folder
   variable design_name

   if { $parentCell eq "" } {
      set parentCell [get_bd_cells /]
   }

   # Get object for parentCell
   set parentObj [get_bd_cells $parentCell]
   if { $parentObj == "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
      return
   }

   # Make sure parentObj is hier blk
   set parentType [get_property TYPE $parentObj]
   if { $parentType ne "hier" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
      return
   }

   # Save current instance; Restore later
   set oldCurInst [current_bd_instance .]

   # Set parent object as current
   current_bd_instance $parentObj

   source ../barebones/ip/ps7_config.tcl

   # Create instance: processing_system7, and set properties
   set processing_system7 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7 ]

   configure_ps7 $processing_system7

   set_property -dict [ list \
      CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
      CONFIG.PCW_USE_S_AXI_ACP {0} \
      CONFIG.PCW_USE_S_AXI_GP0 {0} \
      CONFIG.PCW_USE_S_AXI_GP1 {0} \
      CONFIG.PCW_USE_S_AXI_HP0 {1} \
      CONFIG.PCW_USE_S_AXI_HP1 {1} \
      CONFIG.PCW_USE_S_AXI_HP2 {1} \
      CONFIG.PCW_USE_S_AXI_HP3 {1} \
      CONFIG.PCW_S_AXI_ACP_ARUSER_VAL {31} \
      CONFIG.PCW_S_AXI_ACP_AWUSER_VAL {31} \
      CONFIG.PCW_S_AXI_ACP_ID_WIDTH {3} \
      CONFIG.PCW_S_AXI_GP0_ID_WIDTH {6} \
      CONFIG.PCW_S_AXI_GP1_ID_WIDTH {6} \
      CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
      CONFIG.PCW_S_AXI_HP0_ID_WIDTH {6} \
      CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
      CONFIG.PCW_S_AXI_HP1_ID_WIDTH {6} \
      CONFIG.PCW_S_AXI_HP2_DATA_WIDTH {64} \
      CONFIG.PCW_S_AXI_HP2_ID_WIDTH {4} \
      CONFIG.PCW_S_AXI_HP3_DATA_WIDTH {64} \
      CONFIG.PCW_S_AXI_HP3_ID_WIDTH {4} \
      CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {0} \
      CONFIG.PCW_M_AXI_GP0_ID_WIDTH {12} \
      CONFIG.PCW_M_AXI_GP0_SUPPORT_NARROW_BURST {0} \
      CONFIG.PCW_M_AXI_GP0_THREAD_ID_WIDTH {12} \
      CONFIG.PCW_M_AXI_GP1_ENABLE_STATIC_REMAP {0} \
      CONFIG.PCW_M_AXI_GP1_ID_WIDTH {12} \
      CONFIG.PCW_M_AXI_GP1_SUPPORT_NARROW_BURST {0} \
      CONFIG.PCW_M_AXI_GP1_THREAD_ID_WIDTH {12} \
      CONFIG.PCW_GP0_EN_MODIFIABLE_TXN {1} \
      CONFIG.PCW_GP0_NUM_READ_THREADS {4} \
      CONFIG.PCW_GP0_NUM_WRITE_THREADS {4} \
      CONFIG.PCW_GP1_EN_MODIFIABLE_TXN {1} \
      CONFIG.PCW_GP1_NUM_READ_THREADS {4} \
      CONFIG.PCW_GP1_NUM_WRITE_THREADS {4} \
      CONFIG.PCW_USE_M_AXI_GP0 {1} \
      CONFIG.PCW_USE_M_AXI_GP1 {0} \
      CONFIG.PCW_USE_PROC_EVENT_BUS {0} \
      CONFIG.PCW_USE_PS_SLCR_REGISTERS {0} \
      CONFIG.PCW_USE_S_AXI_ACP {0} \
      CONFIG.PCW_USE_S_AXI_GP0 {0} \
      CONFIG.PCW_USE_S_AXI_GP1 {0} \
      CONFIG.PCW_USE_DMA1 {0} \
      CONFIG.PCW_USE_DMA2 {0} \
      CONFIG.PCW_USE_DMA3 {0} \
   ] $processing_system7

   # Create interface ports
   set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

   set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]

   # Create ports
   set In10_0 [ create_bd_port -dir I -from 0 -to 0 In10_0 ]
   set In11_0 [ create_bd_port -dir I -from 0 -to 0 In11_0 ]
   set In12_0 [ create_bd_port -dir I -from 0 -to 0 In12_0 ]
   set In13_0 [ create_bd_port -dir I -from 0 -to 0 In13_0 ]
   set In1_0 [ create_bd_port -dir I -from 0 -to 0 In1_0 ]
   set In2_0 [ create_bd_port -dir I -from 0 -to 0 In2_0 ]
   set In3_0 [ create_bd_port -dir I -from 0 -to 0 In3_0 ]
   set In4_0 [ create_bd_port -dir I -from 0 -to 0 In4_0 ]
   set In5_0 [ create_bd_port -dir I -from 0 -to 0 In5_0 ]
   set In6_0 [ create_bd_port -dir I -from 0 -to 0 In6_0 ]
   set In7_0 [ create_bd_port -dir I -from 0 -to 0 In7_0 ]
   set In8_0 [ create_bd_port -dir I -from 0 -to 0 In8_0 ]
   set In9_0 [ create_bd_port -dir I -from 0 -to 0 In9_0 ]

   set gpio_n [ create_bd_port -dir IO -from 7 -to 0 gpio_n ]
   set gpio_p [ create_bd_port -dir IO -from 7 -to 0 gpio_p ]

   set loopback_sel [ create_bd_port -dir O -from 7 -to 0 loopback_sel ]

   set trig_in [ create_bd_port -dir I trig_in ]
   set trig_out [ create_bd_port -dir O trig_out ]
   set gpio_trig [ create_bd_port -dir O gpio_trig ]
   set clksel [ create_bd_port -dir O clksel ]
   set daisy_slave [ create_bd_port -dir I daisy_slave ]

   set FCLK_CLK0 [ create_bd_port -dir O -type clk FCLK_CLK0 ]
   set FCLK_CLK1 [ create_bd_port -dir O -type clk FCLK_CLK1 ]
   set FCLK_CLK2 [ create_bd_port -dir O -type clk FCLK_CLK2 ]
   set FCLK_CLK3 [ create_bd_port -dir O -type clk FCLK_CLK3 ]
   set FCLK_RESET0_N [ create_bd_port -dir O -type rst FCLK_RESET0_N ]
   set FCLK_RESET1_N [ create_bd_port -dir O -type rst FCLK_RESET1_N ]
   set FCLK_RESET2_N [ create_bd_port -dir O -type rst FCLK_RESET2_N ]
   set FCLK_RESET3_N [ create_bd_port -dir O -type rst FCLK_RESET3_N ]

   # Create instance: axi_interconnect_0, and set properties
   set axi_interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0 ]
   set_property -dict [ list \
      CONFIG.NUM_MI {1} \
      CONFIG.NUM_SI {2} \
   ] $axi_interconnect_0

   # Create instance: intr_concat, and set properties
   set intr_concat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 intr_concat ]
   set_property -dict [ list \
      CONFIG.NUM_PORTS {16} \
   ] $intr_concat

   # Create instance: rp_concat, and set properties
   set rp_concat [ create_bd_cell -type ip -vlnv redpitaya.com:user:rp_concat:1.0 rp_concat ]
   set_property -dict [ list \
      CONFIG.EVENT_SRC_NUM {5} \
      CONFIG.TRIG_SRC_NUM {6} \
   ] $rp_concat

   # Create instance: rp_oscilloscope, and set properties
   set rp_oscilloscope [ create_bd_cell -type ip -vlnv redpitaya.com:user:rp_oscilloscope:1.16 rp_oscilloscope ]
   set_property -dict [ list \
      CONFIG.ADC_DATA_BITS $::stream_app_adc_bits \
      CONFIG.ID_WIDTHS {12} \
      CONFIG.S_AXI_REG_ADDR_BITS {20} \
      CONFIG.EVENT_SRC_NUM {5} \
      CONFIG.TRIG_SRC_NUM {6} \
      CONFIG.NUM_CHANNELS $::stream_app_adc_count \
   ] $rp_oscilloscope


   # Create instance: xadc, and set properties
   set xadc [ create_bd_cell -type ip -vlnv xilinx.com:ip:xadc_wiz:3.3 xadc ]
   set_property -dict [ list \
      CONFIG.CHANNEL_ENABLE_VAUXP0_VAUXN0 {true} \
      CONFIG.CHANNEL_ENABLE_VAUXP1_VAUXN1 {true} \
      CONFIG.CHANNEL_ENABLE_VAUXP8_VAUXN8 {true} \
      CONFIG.CHANNEL_ENABLE_VAUXP9_VAUXN9 {true} \
      CONFIG.CHANNEL_ENABLE_VP_VN {true} \
      CONFIG.ENABLE_RESET {false} \
      CONFIG.EXTERNAL_MUX_CHANNEL {VP_VN} \
      CONFIG.INTERFACE_SELECTION {Enable_AXI} \
      CONFIG.SEQUENCER_MODE {Off} \
      CONFIG.SINGLE_CHANNEL_SELECTION {TEMPERATURE} \
      CONFIG.XADC_STARUP_SELECTION {independent_adc} \
   ] $xadc

   puts "Looking for board config: ./ip/boards/$::prj_board.tcl"
   puts "Current directory: [pwd]"

   set board_config_path ./ip/boards/$::prj_board.tcl

   if {[file exists $board_config_path]} {
      puts "Found board config. Sourcing: $board_config_path"
      source $board_config_path
      puts "Board config sourced successfully."
   } else {
      puts "Board configuration file not found: $board_config_path"
      return 1
   }

   set_property pfm_name "redpitaya_platform" [get_files -all {system.bd}]

   save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


common::send_gid_msg -ssname BD::TCL -id 2053 -severity "WARNING" "This Tcl script was generated from a block design that has not been validated. It is possible that design <$design_name> may result in errors during validation."
