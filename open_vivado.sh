#!/bin/bash

# Function to display help
show_help() {
    echo "Usage: $0 <PROJECT> <MODEL>"
    echo ""
    echo "Arguments:"
    echo "  PROJECT  - Project folder name from prj/ directory"
    echo "  MODEL    - Device model"
    echo ""
    echo "Available models:"
    echo "  Z10, Z20, Z20_14, Z20_4, Z20_250, Z20_G2, Z20_ll"
    echo ""
    echo "Available projects in prj/ directory:"

    # List available projects
    if [ -d "prj" ]; then
        if ls -1qA "prj/" 2>/dev/null | grep -q .; then
            for dir in prj/*/; do
                if [ -d "$dir" ]; then
                    dir_name=$(basename "$dir")
                    echo "  - $dir_name"
                fi
            done
        else
            echo "  (prj directory exists but is empty)"
        fi
    else
        echo "  (prj directory not found)"
    fi

    echo ""
    echo "Example:"
    echo "  $0 v0.94 Z20_250"
    echo "  $0 stream_app Z20"
    echo ""
    exit 0
}

# Show help if requested or no arguments provided
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

# Check number of arguments
if [ $# -ne 2 ]; then
    echo "Error: exactly 2 arguments required"
    echo "Use '$0 --help' for usage information"
    exit 1
fi

PROJECT="$1"
MODEL="$2"

# Check if prj directory exists
if [ ! -d "prj" ]; then
    echo "Error: prj/ directory not found in current path"
    exit 1
fi

# Check if project folder exists
if [ ! -d "prj/$PROJECT" ]; then
    echo "Error: project 'prj/$PROJECT' not found"
    echo "Available projects:"

    available_projects=()
    for dir in prj/*/; do
        if [ -d "$dir" ]; then
            dir_name=$(basename "$dir")
            available_projects+=("$dir_name")
            echo "  - $dir_name"
        fi
    done

    if [ ${#available_projects[@]} -eq 0 ]; then
        echo "  (no projects found in prj/ directory)"
    fi

    exit 1
fi

# Validate model
case "$MODEL" in
    Z10|Z20|Z20_14|Z20_4|Z20_250|Z20_G2|Z20_ll)
        # Model is valid
        ;;
    *)
        echo "Error: invalid model '$MODEL'"
        echo "Valid models: Z10, Z20, Z20_14, Z20_4, Z20_250, Z20_G2, Z20_ll"
        exit 1
        ;;
esac

# Source Vivado settings if XILINX_VIVADO is not already set
if [ -z "$XILINX_VIVADO" ]; then
    # Try to find and source settings64.sh from common Vivado installation paths
    VIVADO_SETTINGS=""
    
    # List of possible installation paths (ordered by priority)
    POSSIBLE_PATHS=(
        "/tools/Xilinx/Vivado/2025.1/settings64.sh"
        "/opt/Xilinx/Vivado/2025.1/settings64.sh"
        "/usr/local/Xilinx/Vivado/2025.1/settings64.sh"
        "$HOME/Xilinx/Vivado/2025.1/settings64.sh"
    )
    
    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -f "$path" ]; then
            VIVADO_SETTINGS="$path"
            break
        fi
    done
    
    if [ -n "$VIVADO_SETTINGS" ]; then
        echo "Sourcing $VIVADO_SETTINGS ..."
        # shellcheck source=/dev/null
        source "$VIVADO_SETTINGS"
    else
        echo "Warning: settings64.sh not found in standard locations"
        echo "Will attempt to find vivado directly or use XILINX_VIVADO if set"
    fi
fi

# Find Vivado
VIVADO_BIN=""
if [ -n "$XILINX_VIVADO" ]; then
    if [ -f "$XILINX_VIVADO/bin/vivado" ]; then
        VIVADO_BIN="$XILINX_VIVADO/bin/vivado"
    fi
fi

if [ -z "$VIVADO_BIN" ]; then
    # Try common installation paths as fallback
    COMMON_PATHS=(
        "/tools/Xilinx/Vivado/2025.1/bin/vivado"
        "/opt/Xilinx/Vivado/2025.1/bin/vivado"
        "/usr/local/Xilinx/Vivado/2025.1/bin/vivado"
        "$HOME/Xilinx/Vivado/2025.1/bin/vivado"
    )
    
    for path in "${COMMON_PATHS[@]}"; do
        if [ -f "$path" ]; then
            VIVADO_BIN="$path"
            break
        fi
    done
fi

# Check if Vivado was found
if [ -z "$VIVADO_BIN" ]; then
    echo "Error: Vivado was not found."
    echo "Set XILINX_VIVADO to your Vivado installation directory, for example:"
    echo "  export XILINX_VIVADO=/tools/Xilinx/Vivado/2025.1"
    echo ""
    echo "Or source settings64.sh manually:"
    echo "  source /path/to/Vivado/2025.1/settings64.sh"
    exit 1
fi

# Verify that vivado binary is executable
if [ ! -x "$VIVADO_BIN" ]; then
    echo "Error: Vivado binary found but not executable: $VIVADO_BIN"
    exit 1
fi

# Check if Tcl entry point exists
if [ ! -f "red_pitaya_vivado_${MODEL}.tcl" ]; then
    echo "Error: Tcl entry point \"red_pitaya_vivado_${MODEL}.tcl\" not found"
    exit 1
fi

# Run Vivado
"$VIVADO_BIN" -source "red_pitaya_vivado_${MODEL}.tcl" -tclargs "$PROJECT" DEV_MODE
exit $?
