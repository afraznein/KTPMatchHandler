@echo off
setlocal

echo ========================================
echo KTPMatchHandler Plugin Compiler
echo Using KTPAMXX 2.0
echo ========================================
echo.

:: Set compiler path
set "COMPILER=N:\Nein_\KTP\amxmodx_2_0"
set "AMXXPC=%COMPILER%\amxxpc.exe"
set "INCLUDE=%COMPILER%\include"

:: Check if compiler exists
if not exist "%AMXXPC%" (
    echo ERROR: Compiler not found at %AMXXPC%
    echo Please ensure KTPAMXX 2.0 is built and collected.
    pause
    exit /b 1
)

:: Output directory
set "OUTPUT=%~dp0compiled"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

echo Compiling KTPMatchHandler.sma...
echo.

:: Compile the plugin
"%AMXXPC%" "%~dp0KTPMatchHandler.sma" -i"%INCLUDE%" -o"%OUTPUT%\KTPMatchHandler.amxx"

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
