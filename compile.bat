@echo off
setlocal EnableDelayedExpansion

:: Skip pause if running non-interactively (set CI=1 before calling)
if "%CI%"=="" set "INTERACTIVE=1"

echo ========================================
echo KTPMatchHandler Plugin Compiler
echo Using KTPAMXX via WSL
echo ========================================
echo.

:: ============================================
:: Path Configuration
:: ============================================

:: KTPAMXX paths (source of truth for includes)
set "KTPAMXX_DIR=N:\Nein_\KTP Git Projects\KTPAMXX"
set "KTPAMXX_BUILD=%KTPAMXX_DIR%\obj-linux\packages\base\addons\ktpamx\scripting"
set "KTPAMXX_INCLUDES=%KTPAMXX_DIR%\plugins\include"

:: Plugin paths
set "PLUGIN_DIR=%~dp0"
set "PLUGIN_NAME=KTPMatchHandler"
set "OUTPUT_DIR=%PLUGIN_DIR%compiled"

:: Staging path (server)
set "STAGE_DIR=N:\Nein_\KTP DoD Server\dod\addons\ktpamx\plugins"

:: Temp build directory (no spaces)
set "TEMP_BUILD=/tmp/ktpbuild"

:: ============================================
:: Validation
:: ============================================

:: Check KTPAMXX build exists
if not exist "%KTPAMXX_BUILD%\amxxpc" (
    echo [ERROR] KTPAMXX Linux compiler not found!
    echo         Expected: %KTPAMXX_BUILD%\amxxpc
    echo         Please build KTPAMXX first: cd KTPAMXX ^&^& ./build_linux.sh
    if defined INTERACTIVE pause
    exit /b 1
)

:: Check includes exist
if not exist "%KTPAMXX_INCLUDES%\amxmodx.inc" (
    echo [ERROR] KTPAMXX includes not found!
    echo         Expected: %KTPAMXX_INCLUDES%
    if defined INTERACTIVE pause
    exit /b 1
)

:: Check source file exists
if not exist "%PLUGIN_DIR%%PLUGIN_NAME%.sma" (
    echo [ERROR] Source file not found: %PLUGIN_NAME%.sma
    if defined INTERACTIVE pause
    exit /b 1
)

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: ============================================
:: Convert paths to WSL format
:: ============================================

set "WSL_KTPAMXX_BUILD=%KTPAMXX_BUILD:\=/%"
set "WSL_KTPAMXX_BUILD=%WSL_KTPAMXX_BUILD:N:=/mnt/n%"

set "WSL_KTPAMXX_INCLUDES=%KTPAMXX_INCLUDES:\=/%"
set "WSL_KTPAMXX_INCLUDES=%WSL_KTPAMXX_INCLUDES:N:=/mnt/n%"

set "WSL_PLUGIN_DIR=%PLUGIN_DIR:\=/%"
set "WSL_PLUGIN_DIR=%WSL_PLUGIN_DIR:N:=/mnt/n%"

set "WSL_OUTPUT_DIR=%OUTPUT_DIR:\=/%"
set "WSL_OUTPUT_DIR=%WSL_OUTPUT_DIR:N:=/mnt/n%"

:: ============================================
:: Compile
:: ============================================

echo [INFO] Compiling %PLUGIN_NAME%.sma...
echo        Compiler: %KTPAMXX_BUILD%\amxxpc
echo        Includes: %KTPAMXX_INCLUDES%
echo.

:: Build WSL command that:
:: 1. Creates temp build directory
:: 2. Copies compiler and .so to temp
:: 3. Copies source file (converting line endings)
:: 4. Copies all includes
:: 5. Compiles
:: 6. Copies result back

set WSL_CMD=^
mkdir -p %TEMP_BUILD% ^&^& ^
cp '%WSL_KTPAMXX_BUILD%/amxxpc' %TEMP_BUILD%/ ^&^& ^
cp '%WSL_KTPAMXX_BUILD%/amxxpc32.so' %TEMP_BUILD%/ ^&^& ^
cp -r '%WSL_KTPAMXX_INCLUDES%' %TEMP_BUILD%/include ^&^& ^
sed 's/\r$//' '%WSL_PLUGIN_DIR%%PLUGIN_NAME%.sma' ^> %TEMP_BUILD%/%PLUGIN_NAME%.sma ^&^& ^
cd %TEMP_BUILD% ^&^& ^
./amxxpc %PLUGIN_NAME%.sma -i./include -o%PLUGIN_NAME%.amxx ^&^& ^
cp %PLUGIN_NAME%.amxx '%WSL_OUTPUT_DIR%/'

:: Execute via WSL
wsl bash -c "%WSL_CMD%"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================
    echo [FAILED] Compilation failed!
    echo ========================================
    if defined INTERACTIVE pause
    exit /b 1
)

:: ============================================
:: Verify Output
:: ============================================

if not exist "%OUTPUT_DIR%\%PLUGIN_NAME%.amxx" (
    echo.
    echo [ERROR] Output file not created!
    if defined INTERACTIVE pause
    exit /b 1
)

echo.
echo ========================================
echo [SUCCESS] Compilation successful!
echo ========================================
echo Output: %OUTPUT_DIR%\%PLUGIN_NAME%.amxx
echo.

:: ============================================
:: Stage to Server
:: ============================================

echo [INFO] Staging to server...
if not exist "%STAGE_DIR%" (
    echo [WARN] Stage directory does not exist: %STAGE_DIR%
    echo        Skipping staging.
) else (
    copy /Y "%OUTPUT_DIR%\%PLUGIN_NAME%.amxx" "%STAGE_DIR%\%PLUGIN_NAME%.amxx" >nul
    if !ERRORLEVEL! EQU 0 (
        echo [OK] Staged: %STAGE_DIR%\%PLUGIN_NAME%.amxx
    ) else (
        echo [WARN] Failed to stage to server
    )
)

echo.
echo Done!
if defined INTERACTIVE pause
