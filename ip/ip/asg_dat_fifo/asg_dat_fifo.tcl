##################################################################
# CHECK VIVADO VERSION
##################################################################

set scripts_vivado_version 2025.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
  catch {common::send_msg_id "IPS_TCL-100" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_ip_tcl to create an updated script."}
  return 1
}

##################################################################
# START
##################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source asg_dat_fifo_recreate.tcl
# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
  create_project redpitaya build -part xc7z010clg400-1
  set_property target_language Verilog [current_project]
  set_property simulator_language Mixed [current_project]
}

##################################################################
# CHECK IPs
##################################################################

set bCheckIPs 1
set bCheckIPsPassed 1
if { $bCheckIPs == 1 } {
  set list_check_ips { xilinx.com:ip:fifo_generator:13.2 }
  set list_ips_missing ""
  common::send_msg_id "IPS_TCL-1001" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

  foreach ip_vlnv $list_check_ips {
  set ip_obj [get_ipdefs -all $ip_vlnv]
  if { $ip_obj eq "" } {
    lappend list_ips_missing $ip_vlnv
    }
  }

  if { $list_ips_missing ne "" } {
    catch {common::send_msg_id "IPS_TCL-105" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
    set bCheckIPsPassed 0
  }
}

if { $bCheckIPsPassed != 1 } {
  common::send_msg_id "IPS_TCL-102" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 1
}

##################################################################
# CREATE IP asg_dat_fifo
##################################################################

set asg_dat_fifo [create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name asg_dat_fifo]

# User Parameters
set_property -dict [list \
  CONFIG.Almost_Full_Flag {false} \
  CONFIG.Enable_Safety_Circuit {true} \
  CONFIG.FIFO_Implementation_rach {Common_Clock_Distributed_RAM} \
  CONFIG.FIFO_Implementation_wach {Common_Clock_Distributed_RAM} \
  CONFIG.FIFO_Implementation_wrch {Common_Clock_Distributed_RAM} \
  CONFIG.Fifo_Implementation {Independent_Clocks_Block_RAM} \
  CONFIG.Full_Flags_Reset_Value {1} \
  CONFIG.Input_Data_Width {64} \
  CONFIG.Input_Depth {128} \
  CONFIG.Output_Data_Width {64} \
  CONFIG.Read_Data_Count {true} \
  CONFIG.Read_Data_Count_Width {7} \
  CONFIG.Use_Embedded_Registers {true} \
  CONFIG.Valid_Flag {true} \
  CONFIG.Write_Data_Count {true} \
] [get_ips asg_dat_fifo]

# Runtime Parameters
set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {0}
} $asg_dat_fifo

##################################################################
