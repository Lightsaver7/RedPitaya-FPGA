#
# (C) Red Pitaya 2013-2025
#
# Red Pitaya FPGA/SoC Makefile
#

PRJ   ?= v0.94
MODEL ?= Z10
FPGA_VERSION ?= z10_125
RAM   ?= 512
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
XSA 		= prj/$(PRJ)/sdk/red_pitaya.xsa

DEVICETREE_UB_PATH = prj/fsbl/sdk/dts
DEVICETREE_UB =  prj/fsbl/out/devicetree_uboot.dtb
DEVICETREE_UB_PATCH = prj/fsbl/dts

VIVADO = vivado -nojournal -mode batch

.PHONY: all project sim clean clean-all

all: $(FPGA_BIN) $(DEVICE_TREE) $(DTREE_DIR)

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
	vivado $(VIVADO_OPTS) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) HWID=$(HWID) DEV_MODE
else
	vivado $(VIVADO_OPTS) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) DEV_MODE
endif

$(FPGA_BIN):
ifneq ($(HWID),"")
	$(VIVADO) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) HWID=$(HWID)
else
	$(VIVADO) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES)
endif
	./synCheck.sh $(PRJ)

$(XSA): $(FPGA_BIN)

$(FSBL_ELF): $(XSA)
	xsct red_pitaya_hsi_fsbl.tcl $(PRJ)

ifeq ($(PRJ),barebones)
    ifeq ($(FPGA_VERSION),z20_250_1_0)
        DTS_PATH := dts_250
    else ifeq ($(FPGA_VERSION),z20_250)
        DTS_PATH := dts_250
    else ifeq ($(FPGA_VERSION),z20_250a)
        DTS_PATH := dts_250a
    else
        DTS_PATH := dts
    endif
endif

$(DEVICE_TREE): $(XSA)
	xsct red_pitaya_hsi_dts.tcl  $(PRJ) DTS_VER=$(DTS_VER) MODEL=$(MODEL)

ifeq ($(PRJ),barebones)
	cp -rf prj/$(PRJ)/dts prj/$(PRJ)/sdk
	cp -f prj/$(PRJ)/sdk/dts/system-top.dts prj/$(PRJ)/sdk/dts/system-top.dts.tmp
	cat prj/$(PRJ)/sdk/dts/fpga.dts >> prj/$(PRJ)/sdk/dts/system-top.dts.tmp
	gcc -I dts/$(DTS_PATH) -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o prj/$(PRJ)/sdk/dts/system-top.dts.full.tmp prj/$(PRJ)/sdk/dts/system-top.dts.tmp
	dtc -@ -I dts -O dtb -o prj/$(PRJ)/out/dts/dtraw.dtb -i dts/$(DTS_PATH) prj/$(PRJ)/sdk/dts/system-top.dts.full.tmp
	dtc -I dtb -O dts --sort -o prj/$(PRJ)/out/dts/dtraw.dtbs prj/$(PRJ)/out/dts/dtraw.dtb
	dtc dts/$(DTS_PATH)/led-system.dtso -I dts -O dtb -o prj/$(PRJ)/out/dts/led-system.dtbo
endif

	PL_PATH=prj/$(PRJ)/out/dts/out/dts/redpitaya_platform/ps7_cortexa9_0/device_tree_domain/bsp/pl.dtsi; \
    echo "Path to pl.dtsi:  $$PL_PATH"; \
	if [ -f "$$PL_PATH" ]; then \
		sed -i 's/.bin/fpga.bin/g' $$PL_PATH; \
		grep -qxF '/include/ "pl_patch.dtsi"' $$PL_PATH || echo '/include/ "pl_patch.dtsi"' >> $$PL_PATH; \
		dtc -I dts -O dtb -i prj/$(PRJ)/dts -o prj/$(PRJ)/out/fpga.dtbo $$PL_PATH; \
		dtc -I dtb -O dts --sort -o prj/$(PRJ)/out/fpga.dtso prj/$(PRJ)/out/fpga.dtbo; \
    else \
        echo "Missing pl.dtsi [SKIP]"; \
    fi


dts: $(DEVICE_TREE)

fsbl: fsbl_dts

fsbl_build:
	$(VIVADO) -source red_pitaya_vivado_fsbl.tcl -tclargs MODEL=$(MODEL) RAM=$(RAM) DTS_VER=$(DTS_VER)
	xsct red_pitaya_hsi_fsbl.tcl fsbl

fsbl_dts: fsbl_build
	echo $@
	xsct red_pitaya_hsi_fsbl_dts.tcl fsbl
	grep -qxF '/include/ "redpitaya.dtsi"' $(DEVICETREE_UB_PATH)/system-top.dts || echo '/include/ "redpitaya.dtsi"' >> $(DEVICETREE_UB_PATH)/system-top.dts;
	gcc -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o $(DEVICETREE_UB_PATH)/system-top.dts.tmp $(DEVICETREE_UB_PATH)/system-top.dts
	dtc -@ -I dts -O dtb -i $(DEVICETREE_UB_PATCH) -o $(DEVICETREE_UB) $(DEVICETREE_UB_PATH)/system-top.dts.tmp