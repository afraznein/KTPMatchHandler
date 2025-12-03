@echo off
setlocal

echo ========================================
echo KTPMatchHandler Plugin Compiler
echo Using KTPAMXX 2.0 via WSL
echo ========================================
echo.

:: WSL paths (Windows N:\ = /mnt/n/)
set "WSL_COMPILER=/mnt/n/Nein_/KTP/amxmodx_2_0"
set "WSL_AMXXPC=%WSL_COMPILER%/amxxpc"
set "WSL_INCLUDE=%WSL_COMPILER%/include"
set "WSL_REAPI_INCLUDE=/mnt/n/Nein_/KTP Git Projects/KTPReAPI/reapi/extra/amxmodx/scripting/include"
set "WSL_REAPI_VERSION=/mnt/n/Nein_/KTP Git Projects/KTPReAPI/reapi/version"

:: Get the script directory in WSL format
set "SCRIPT_DIR=%~dp0"
:: Convert Windows path to WSL path (N:\ -> /mnt/n/)
set "SCRIPT_DIR=%SCRIPT_DIR:\=/%"
set "SCRIPT_DIR=%SCRIPT_DIR:N:=/mnt/n%"

:: Output directory (Windows path for mkdir)
set "OUTPUT=%~dp0compiled"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

:: WSL output path
set "WSL_OUTPUT=%SCRIPT_DIR%compiled"

echo Compiling KTPMatchHandler.sma via WSL...
echo.

:: Compile the plugin using WSL
:: Note: Paths with spaces need proper quoting
wsl bash -c "cd '%SCRIPT_DIR%' && '%WSL_AMXXPC%' KTPMatchHandler.sma -i'%WSL_INCLUDE%' -i'%WSL_REAPI_INCLUDE%' -i'%WSL_REAPI_VERSION%' -o'%WSL_OUTPUT%/KTPMatchHandler.amxx'"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo ========================================
    echo Output: %OUTPUT%\KTPMatchHandler.amxx
) else (
    echo.
    echo ========================================
    echo BUILD FAILED!
    echo ========================================
    echo Check the errors above.
)

echo.
pause
