#
# (C) Red Pitaya 2013-2025
#
# Red Pitaya FPGA/SoC Makefile
#

PRJ   ?= v0.94
MODEL ?= Z10
HWID  ?= ""
DEFINES ?= ""
DTS_VER ?= 2025.1
VIVADO_OPTS ?=
PROJECT_DIRS := $(wildcard prj/*)
PROJECT_NAMES := $(notdir $(PROJECT_DIRS))

# build artefacts
FPGA_BIN    = prj/$(PRJ)/out/red_pitaya.bin
FSBL_ELF    = prj/$(PRJ)/sdk/fsbl.elf
MEMTEST_ELF = prj/$(PRJ)/sdk/dram_test/executable.elf
DEVICE_TREE = prj/$(PRJ)/sdk/dts/system.dts


.PHONY: all project sim clean clean-all

all: $(FPGA_BIN) $(FSBL_ELF) $(DEVICE_TREE) $(DTREE_DIR)

clean-all:
	@echo "Cleaning all projects in prj/: $(PROJECT_NAMES)"
	@for project in $(PROJECT_NAMES); do \
		echo "Cleaning project: $$project"; \
		rm -rf out .Xil .srcs sdk project sim; \
		rm -rf prj/$$project/out prj/$$project/.Xil prj/$$project/.srcs prj/$$project/sdk prj/$$project/project; \
		rm -rf prj/$$project/build; \
		rm -rf prj/$$project/.gen; \
		rm -rf prj/$$project/build-fsbl; \
	done
	@echo "All projects cleaned"

clean:
	rm -rf out .Xil .srcs sdk project sim
	rm -rf prj/$(PRJ)/out prj/$(PRJ)/.Xil prj/$(PRJ)/.srcs prj/$(PRJ)/sdk prj/$(PRJ)/project
	rm -rf prj/$(PRJ)/build
	rm -rf prj/$(PRJ)/.gen
	rm -rf prj/$(PRJ)/build-fsbl

sim:
	vivado -source red_pitaya_vivado_sim.tcl -tclargs $(PRJ) $(MODEL) $(DEFINES)

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

$(DEVICE_TREE): $(FPGA_BIN)
	xsct red_pitaya_hsi_dts.tcl  $(PRJ) DTS_VER=$(DTS_VER)

dts: $(DEVICE_TREE)
