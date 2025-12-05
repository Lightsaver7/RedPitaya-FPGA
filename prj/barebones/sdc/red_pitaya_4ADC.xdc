#
# $Id: red_pitaya_4adc.xdc 961 2014-01-21 11:40:39Z matej.oblak $
#
# @brief Red Pitaya location constraints.
#
# @Author Matej Oblak
#
# (c) Red Pitaya  http://www.redpitaya.com
#

############################################################################
# Clock constraints                                                        #
############################################################################

#NET "adc_clk" TNM_NET = "adc_clk";
#TIMESPEC TS_adc_clk = PERIOD "adc_clk" 125 MHz;


create_clock -period 8.000 -name adc_clk_01 [get_ports {adc_clk_i[0][1]}]
create_clock -period 8.000 -name adc_clk_23 [get_ports {adc_clk_i[1][1]}]

#set_input_delay -clock adc_clk_01 4.000 [get_ports {adc_dat_i[0][*]}]
#set_input_delay -clock adc_clk_23 4.000 [get_ports {adc_dat_i[1][*]}]

create_clock -period 4.000 -name rx_clk  [get_ports daisy_p_i[1]]
set_false_path -from [get_clocks par_clk]  -to [get_clocks pll_adc_clk_0]
set_false_path -from [get_clocks pll_adc_clk_0]  -to [get_clocks par_clk]

set_false_path -from [get_clocks clk_fpga_0]  -to [get_clocks adc_clk_01]
set_false_path -from [get_clocks clk_fpga_0]  -to [get_clocks adc_clk_23]
set_false_path -from [get_clocks adc_clk_01]  -to [get_clocks pll_ser_clk]
set_false_path -from [get_clocks clk_fpga_0]  -to [get_clocks pdm_clk]
set_false_path -from [get_clocks clk_fpga_0]  -to [get_clocks ser_clk_out]
set_false_path -from [get_clocks clk_fpga_0]  -to [get_clocks par_clk]
set_false_path -from [get_clocks adc_clk_01]  -to [get_clocks adc_clk_23]
set_false_path -from [get_clocks adc_clk_23]  -to [get_clocks adc_clk_01]
set_false_path -from [get_clocks clk_fpga_0]  -to [get_clocks pll_adc_clk_0]
set_false_path -from [get_clocks pll_adc_clk_0]  -to [get_clocks clk_fpga_0]
set_false_path -from [get_clocks pll_adc_clk_0] -to [get_clocks pll_adc_10mhz]
set_false_path -from [get_clocks pll_adc_10mhz] -to [get_clocks pll_adc_clk_0]

set_false_path -from [get_clocks pll_adc_clk_0] -to [get_clocks adc_clk_01]
set_false_path -from [get_clocks pll_adc_clk_1] -to [get_clocks adc_clk_01]
set_false_path -from [get_clocks pll_adc_clk_0] -to [get_clocks adc_clk_23]
set_false_path -from [get_clocks pll_adc_clk_1] -to [get_clocks adc_clk_23]

set_false_path -from [get_clocks adc_clk_01] -to [get_clocks pll_adc_clk_0]
set_false_path -from [get_clocks adc_clk_01] -to [get_clocks pll_adc_clk_1]
set_false_path -from [get_clocks adc_clk_23] -to [get_clocks pll_adc_clk_0]
set_false_path -from [get_clocks adc_clk_23] -to [get_clocks pll_adc_clk_1]

set_false_path -from [get_clocks pll_adc_clk_0] -to [get_clocks pll_adc_clk_1]
set_false_path -from [get_clocks pll_adc_clk_1] -to [get_clocks pll_adc_clk_0]
