# Windows build

This guide explains the easiest way to use this repository on Windows.

You can do two main things:

- open a project in Vivado
- run `make`-based build flows from a Unix-like shell

## 1. Requirements

### For opening a project in Vivado from `cmd.exe`

- Xilinx Vivado for Windows (`2025.1`)

### For running `make`-based builds

- Xilinx Vivado for Windows (`2025.1`)
- Xilinx Vitis for Windows (`2025.1`) for `xsct`
- `make`
- `gcc`
- `dtc`
- a Unix-like shell such as `Git Bash`, `MSYS2`, or `WSL`

The `Makefile` uses Unix shell utilities, so it will not run correctly from plain `cmd.exe` alone.

## 2. Windows PATH setup (recommended)

Add these folders to your Windows `Path` environment variable:

```text
C:\Xilinx\Vivado\2025.1\bin
C:\Xilinx\Vitis\2025.1\bin
```

After updating `Path`, close and reopen your terminal.

Verify tools are visible:

```bat
where vivado
where xsct
```

If you plan to use `make`, also verify in your Unix-like shell:

```bash
which make
which gcc
which dtc
which xsct
```

Important:

- install and verify tools in the same shell you plan to use for building
- if a tool is installed in one environment but you build in another, it may not be found

`open_vivado.bat` can still use `XILINX_VIVADO` if set, but using `Path` is the preferred setup for beginners.

## 3. Supported models

- `Z10`
- `Z20`
- `Z20_14`
- `Z20_4`
- `Z20_250`
- `Z20_G2`
- `Z20_ll`

## 4. Open a project in Vivado

From `cmd.exe` in the repository root:

```bat
open_vivado.bat v0.94 Z20_250
```

More examples:

```bat
open_vivado.bat v0.94 Z20
open_vivado.bat stream_app Z20_250
```

What `open_vivado.bat` checks:

- `prj\<PROJECT>` exists
- `MODEL` is valid
- Vivado launcher exists
- `red_pitaya_vivado_<MODEL>.tcl` exists

Then it runs:

```text
vivado -source red_pitaya_vivado_<MODEL>.tcl -tclargs <PROJECT> DEV_MODE
```

Help:

```bat
open_vivado.bat --help
```

## 5. Build from a shell on Windows

Use `Git Bash`, `MSYS2`, or `WSL`, then run commands from the repository root.

WSL warning:

- WSL is a separate Linux environment
- do not assume Windows `Path` or Windows-installed tools are automatically available in WSL
- if you build in WSL, install and verify required tools inside WSL

Open the project in Vivado GUI:

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

`'vivado' is not recognized` or `Vivado was not found`

- confirm `C:\Xilinx\Vivado\2025.1\bin` is in Windows `Path`
- run `where vivado` in a new terminal

`'xsct' is not recognized`

- confirm `C:\Xilinx\Vitis\2025.1\bin` is in Windows `Path`
- run `where xsct` in a new terminal

`make: command not found` or `No rule to make target 'project'`

- run from `Git Bash`, `MSYS2`, or `WSL` instead of plain `cmd.exe`
- run from the repository root where `Makefile` is located
- verify `make` is installed and available in `PATH`

`project "prj\<name>" not found`

- check that the project directory exists in `prj/`

`invalid model`

- use one of the supported model names listed above

`gcc`, `dtc`, or `xsct` errors during `make`

- make sure each tool is installed and available in shell `PATH`
