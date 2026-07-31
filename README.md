# redpitaya-fpga

This repository contains FPGA projects for the Red Pitaya platform.

It includes:

- project-specific sources in `prj/`
- shared RTL/IP/constraints used by multiple projects
- scripts and Makefile-based build flows

## Quick start (beginners)

1. Install Vivado `2025.1`.
2. Choose a project name from `prj/` (for example `v0.94`).
3. Choose a target `MODEL` (for example `Z10` or `Z20_250`).
4. Open the project with `open_vivado.bat` (Windows) or `open_vivado.sh` (Linux/Unix-like).
5. Build with `make PRJ=<project> MODEL=<model>`.

Examples (each line is a separate build command):

```bash
./open_vivado.sh v0.94 Z10
make clean PRJ=v0.94
make PRJ=v0.94 MODEL=Z10
```

Detailed platform guides:

- Windows: [BUILD_WIN.md](/BUILD_WIN.md)
- Linux / Unix-like: [BUILD_LNX.md](/BUILD_LNX.md)

## Key concepts

`PRJ`

- selects the project directory under `prj/`
- must exactly match a folder name, for example `v0.94`, `stream_app`, `logic`, or `barebones`

`MODEL`

- selects the hardware variant
- must match an available `red_pitaya_vivado_<MODEL>.tcl` script

During project open/build, Vivado combines:

- shared sources from the repository root
- project-local files from `prj/<PRJ>/`

## Repository structure

- `prj/` - project definitions and project-local overrides
- `rtl/` - shared RTL modules
- `ip/` - shared IP and helper sources
- `sdc/` - shared constraints
- `dts/` - shared device-tree-related files
- `tbn/` - shared testbench environment
- `doc/` - documentation

Typical subdirectories inside one project (`prj/<PRJ>/`) are:

- `rtl` - project RTL modules
- `ip` - block design Tcl and project IP/PS configuration
- `sdc` - project-specific constraints
- `dts` and variants such as `dts_250`, `dts_4ch` - project device-tree data
- `tbn` - project testbenches
- `out`, `build`, `sdk`, `.Xil`, `sim` - generated artifacts

## Open and build commands

Open project in Vivado:

```bash
./open_vivado.sh v0.94 Z20_250
```

or on Windows:

```bat
open_vivado.bat v0.94 Z20_250
```

Build commands (each line is a separate build command):

```bash
make project PRJ=v0.94 MODEL=Z20_250
make PRJ=v0.94 MODEL=Z20_250
make dts PRJ=v0.94 MODEL=Z20_250
make clean PRJ=v0.94
```

## Working with projects

When creating a new project:

- create a new folder under `prj/`; that folder name becomes `PRJ`
- use `prj/barebones` as a starting template
- keep project-local files in that project folder
- normally include `rtl`, `ip`, and `dts`
- add `sdc` if custom constraints are needed
- add `tbn` if project-specific tests are needed

The `prj/<PRJ>/ip` directory is usually created by exporting Tcl from Vivado or by copying/adapting a template such as `prj/barebones/ip`.

When modifying an existing project:

- keep project-specific edits inside `prj/<PRJ>/...`
- treat root shared modules (`rtl/`, `ip/`, `sdc/`) carefully because multiple projects may depend on them
- reopen or rebuild with the same `PRJ` and `MODEL` to verify changes
