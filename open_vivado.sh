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
    echo "  $0 firmware_v1 Z20"
    echo "  $0 test_project Z20_14"
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

    # Show available projects for better user experience
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

make project PRJ="$PROJECT" MODEL="$MODEL"