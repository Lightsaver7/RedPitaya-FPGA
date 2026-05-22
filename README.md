# Windows build

This repository can be used on Windows to open Vivado projects and run builds.

## Required software

- Xilinx Vivado for Windows
- `make`
- `gcc`
- `dtc`
- `xsct`
- a Unix-like shell such as `Git Bash`, `MSYS2`, or `WSL`

This is required because the `Makefile` uses Unix shell utilities and will not run correctly from plain `cmd.exe` alone.

## Vivado setup

It is recommended to set the following environment variable:

```bat
set XILINX_VIVADO=C:\Xilinx\Vivado\2025.1
```

The [open_vivado.bat](/home/yura/projects/a014-redpitaya/redpitaya-fpga/open_vivado.bat:1) script first looks for `vivado.bat` at `%XILINX_VIVADO%\bin\vivado.bat`, then falls back to:

```text
C:\Xilinx\Vivado\2025.1\bin\vivado.bat
```

## Supported models

- `Z10`
- `Z20`
- `Z20_14`
- `Z20_4`
- `Z20_250`
- `Z20_G2`
- `Z20_ll`

## Open a project in Vivado

From `cmd.exe` in the repository root:

```bat
open_vivado.bat v0.94 Z20_250
```

Examples:

```bat
open_vivado.bat v0.94 Z20
open_vivado.bat stream_app Z20_250
```

The script:

- checks that `prj\<PROJECT>` exists
- validates `MODEL`
- runs `red_pitaya_vivado_<MODEL>.tcl` in `DEV_MODE`

Help:

```bat
open_vivado.bat --help
```

## Build from a shell on Windows

If you use `Git Bash`, `MSYS2`, or `WSL`, you can run the `Makefile` directly.

Open the project in the GUI:

```bash
make project PRJ=v0.94 MODEL=Z20_250
```

Build the bitstream:

```bash
make PRJ=v0.94 MODEL=Z20_250
```

Build only the device tree:

```bash
make dts PRJ=v0.94 MODEL=Z20_250
```

Clean project artifacts:

```bash
make clean PRJ=v0.94
```

## Useful Make variables

- `PRJ` - project name from the `prj/` directory
- `MODEL` - target board model
- `HWID` - optional hardware ID
- `DEFINES` - additional Verilog defines
- `DTS_VER` - device-tree flow version, default is `2025.1`
- `VIVADO_OPTS` - additional Vivado arguments

Example:

```bash
make project PRJ=stream_app MODEL=Z20_250 DEFINES="FEATURE_X=1"
```

## Common issues

`Vivado was not found`

- set `XILINX_VIVADO`
- check that `vivado.bat` exists in `%XILINX_VIVADO%\bin`

`project "prj\<name>" not found`

- check the project directory name in `prj/`

`invalid model`

- use only the supported models listed above

`make`, `gcc`, `dtc`, or shell utility errors

- run the build from `Git Bash`, `MSYS2`, or `WSL`
- make sure `make`, `gcc`, `dtc`, and `xsct` are available in `PATH`
