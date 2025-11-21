#
# Authors: Matej Oblak, Iztok Jeras
# (C) Red Pitaya 2013-2015
#
# Red Pitaya FPGA/SoC Makefile
#
# Produces:
#   3. FPGA bit file.
#   1. FSBL (First stage bootloader) ELF binary.
#   2. Memtest (stand alone memory test) ELF binary.
#   4. Linux device tree source (dts).

PRJ   ?= v0.94
#PRJ   ?= stream_app
MODEL ?= Z20_G2
HWID  ?= ""
DEFINES ?= ""
DTS_VER ?= 2025.1
VIVADO_OPTS ?=
DL ?= dl

# build artefacts
FPGA_BIN    = prj/$(PRJ)/out/red_pitaya.bin
FSBL_ELF    = prj/$(PRJ)/sdk/fsbl.elf
MEMTEST_ELF = prj/$(PRJ)/sdk/dram_test/executable.elf
DEVICE_TREE = prj/$(PRJ)/sdk/dts/system.dts

DTREE_TAG      = xilinx_v$(DTS_VER)
DTREE_PATH_TAG = xilinx-v$(DTS_VER)
DTREE_TAR      = $(DL)/device-tree-xlnx-$(DTREE_TAG).tar.gz
DTREE_URL      = https://github.com/Xilinx/device-tree-xlnx/archive/$(DTREE_TAG).tar.gz
#DTREE_URL      = https://github.com/Xilinx/system-device-tree-xlnx/archive/$(DTREE_TAG).tar.gz
DTREE_DIR      = $(DL)/device-tree-xlnx-$(DTREE_PATH_TAG)

# Vivado from Xilinx provides IP handling, FPGA compilation
# hsi (hardware software interface) provides software integration
# both tools are run in batch mode with an option to avoid log/journal files
VIVADO = vivado -nojournal -mode batch
HSI    = hsi    -nolog -nojournal -mode batch
BOOTGEN= bootgen -image prj/$(PRJ)/out/red_pitaya.bif -arch zynq -process_bitstream bin
#HSI    = hsi    -nolog -mode batch

.PHONY: all clean project sim

all: $(FPGA_BIN) $(FSBL_ELF) $(DEVICE_TREE) $(DTREE_DIR)

# TODO: clean should go into each project
clean:
	rm -rf out .Xil .srcs sdk project sim
	rm -rf prj/$(PRJ)/out prj/$(PRJ)/.Xil prj/$(PRJ)/.srcs prj/$(PRJ)/sdk prj/$(PRJ)/project
	rm -rf prj/$(PRJ)/build
	rm -rf prj/$(PRJ)/.gen
	rm -rf prj/$(PRJ)/build-fsbl
	rm -rf $(DL)

sim:
	vivado -source red_pitaya_vivado_sim.tcl -tclargs $(PRJ) $(MODEL) $(DEFINES)

$(DL):
	mkdir -p $@

$(DTREE_TAR): | $(DL)
	curl -L $(DTREE_URL) -o $@

$(DTREE_DIR): $(DTREE_TAR)
	mkdir -p $@
	tar -zxf $< --strip-components=1 --directory=$@

a: $(DTREE_DIR)

project:
ifneq ($(HWID),"")
	vivado $(VIVADO_OPTS) -source red_pitaya_vivado_project_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) HWID=$(HWID)
else
	vivado $(VIVADO_OPTS) -source red_pitaya_vivado_project_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES)
endif

$(FPGA_BIN):
ifneq ($(HWID),"")
	$(VIVADO) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) HWID=$(HWID)
else
	$(VIVADO) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES)
endif
	./synCheck.sh

$(FSBL_ELF): $(FPGA_BIN)
	xsct red_pitaya_hsi_fsbl.tcl $(PRJ)

$(DEVICE_TREE): $(DTREE_DIR) # $(FPGA_BIN)
	xsct red_pitaya_hsi_dts.tcl  $(PRJ) DTS_VER=$(DTS_VER)

dts: $(DEVICE_TREE)
