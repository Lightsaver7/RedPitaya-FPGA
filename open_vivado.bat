@echo off
setlocal EnableExtensions

if "%~1"=="" goto :show_help
if /I "%~1"=="-h" goto :show_help
if /I "%~1"=="--help" goto :show_help

if not "%~3"=="" (
  echo Error: exactly 2 arguments required
  echo Use "%~nx0 --help" for usage information
  exit /b 1
)

if "%~2"=="" (
  echo Error: exactly 2 arguments required
  echo Use "%~nx0 --help" for usage information
  exit /b 1
)

set "PROJECT=%~1"
set "MODEL=%~2"

if not exist "prj" (
  echo Error: prj\ directory not found in current path
  exit /b 1
)

if not exist "prj\%PROJECT%\" (
  echo Error: project "prj\%PROJECT%" not found
  echo Available projects:
  for /d %%D in ("prj\*") do echo   - %%~nxD
  exit /b 1
)

set "VALID_MODEL="
for %%M in (Z10 Z20 Z20_14 Z20_4 Z20_250 Z20_G2 Z20_ll) do (
  if /I "%MODEL%"=="%%M" set "VALID_MODEL=1"
)

if not defined VALID_MODEL (
  echo Error: invalid model "%MODEL%"
  echo Valid models: Z10, Z20, Z20_14, Z20_4, Z20_250, Z20_G2, Z20_ll
  exit /b 1
)

set "VIVADO_BAT="
if defined XILINX_VIVADO (
  if exist "%XILINX_VIVADO%\bin\vivado.bat" (
    set "VIVADO_BAT=%XILINX_VIVADO%\bin\vivado.bat"
  )
)

if not defined VIVADO_BAT (
  if exist "C:\Xilinx\Vivado\2025.1\bin\vivado.bat" (
    set "VIVADO_BAT=C:\Xilinx\Vivado\2025.1\bin\vivado.bat"
  )
)

if not defined VIVADO_BAT (
  echo Error: Vivado was not found.
  echo Set XILINX_VIVADO to your Vivado installation directory, for example:
  echo   set XILINX_VIVADO=C:\Xilinx\Vivado\2025.1
  exit /b 1
)

if not exist "red_pitaya_vivado_%MODEL%.tcl" (
  echo Error: Tcl entry point "red_pitaya_vivado_%MODEL%.tcl" not found
  exit /b 1
)

call "%VIVADO_BAT%" -source "red_pitaya_vivado_%MODEL%.tcl" -tclargs "%PROJECT%" DEV_MODE
exit /b %ERRORLEVEL%

:show_help
echo Usage: %~nx0 ^<PROJECT^> ^<MODEL^>
echo.
echo Arguments:
echo   PROJECT  - Project folder name from prj\ directory
echo   MODEL    - Device model
echo.
echo Available models:
echo   Z10, Z20, Z20_14, Z20_4, Z20_250, Z20_G2, Z20_ll
echo.
echo Available projects in prj\ directory:
if exist "prj" (
  for /d %%D in ("prj\*") do echo   - %%~nxD
) else (
  echo   (prj directory not found)
)
echo.
echo Example:
echo   %~nx0 v0.94 Z20_250
echo   %~nx0 stream_app Z20
exit /b 0
