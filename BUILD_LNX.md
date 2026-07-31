# Linux / Unix-like build

This guide explains the standard FPGA flow in Linux or any Unix-like shell (`bash`, `zsh`, `Git Bash`, `MSYS2`, `WSL`).

You can do two main things:

- open a project in Vivado
- run `make`-based builds

## 1. Requirements

- Xilinx Vivado `2025.1`
- `make`
- `gcc`
- `dtc`
- `xsct`

## 2. Prepare Vivado environment

On Linux, the usual setup is:

```bash
source ~/Xilinx/2025.1/Vivado/settings64.sh
```

You can also set:

```bash
export XILINX_VIVADO=~/Xilinx/Vivado/2025.1
```

Quick checks:

```bash
which vivado
which xsct
which make
which gcc
which dtc
```

## 3. Supported models

- `Z10`
- `Z20`
- `Z20_14`
- `Z20_4`
- `Z20_250`
- `Z20_G2`
- `Z20_ll`

## 4. Open a project in Vivado

From a Unix-like shell in the repository root:

```bash
./open_vivado.sh v0.94 Z20_250
```

More examples:

```bash
./open_vivado.sh v0.94 Z10
./open_vivado.sh stream_app Z20_250
```

What `open_vivado.sh` checks:

- `prj/<PROJECT>` exists
- `MODEL` is valid
- Vivado environment/executable is available
- `red_pitaya_vivado_<MODEL>.tcl` exists

Then it runs:

```text
vivado -source red_pitaya_vivado_<MODEL>.tcl -tclargs <PROJECT> DEV_MODE
```

Help:

```bash
./open_vivado.sh --help
```

## 5. Build with `make`

Open project in Vivado GUI:

```bash
make project PRJ=v0.94 MODEL=Z20_250
```

Build bitstream:

```bash
make PRJ=v0.94 MODEL=Z20_250
```

Build only device tree:

```bash
make dts PRJ=v0.94 MODEL=Z20_250
```

Clean generated project files:

```bash
make clean PRJ=v0.94
```

## 6. Useful `make` variables

- `PRJ` - project name from `prj/`
- `MODEL` - target board model
- `HWID` - optional hardware ID
- `DEFINES` - additional Verilog defines
- `DTS_VER` - device-tree flow version (default `2025.1`)
- `VIVADO_OPTS` - extra Vivado arguments

Example:

```bash
make project PRJ=stream_app MODEL=Z20_250 DEFINES="FEATURE_X=1"
```

## 7. Common issues

`Vivado was not found`

- source `settings64.sh`
- or set `XILINX_VIVADO`
- verify `vivado` is in `PATH` using `which vivado`

`xsct` not found

- make sure Vitis is installed
- verify `xsct` is in `PATH` using `which xsct`

`project "prj/<name>" not found`

- check the project directory name in `prj/`

`invalid model`

- use one of the supported model names listed above

`make`, `gcc`, or `dtc` errors

- verify tools are installed and available in `PATH`
