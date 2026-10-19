@echo off
REM ===========================================================================
REM  build-check.bat - offline syntax/type check of the ERC C++ plugin.
REM
REM  Compiles the plugin sources against the MOCK SKSE headers in mock-sdk\ so
REM  typos, type errors and missing symbols are caught WITHOUT the real SDK.
REM  This produces .obj files only (no DLL, no link) and proves nothing about
REM  runtime behaviour - you still build against the real SKSE SDK for shipping.
REM ===========================================================================
setlocal

set "VSDIR=C:\Program Files\Microsoft Visual Studio\2022\Community"
if not exist "%VSDIR%\Common7\Tools\VsDevCmd.bat" (
    echo [check] Visual Studio 2022 Community not found.
    exit /b 2
)

call "%VSDIR%\Common7\Tools\VsDevCmd.bat" -arch=x64 -no_logo >nul 2>&1
if errorlevel 1 (
    echo [check] Failed to initialise the MSVC environment.
    exit /b 2
)

cd /d "%~dp0.."
if not exist "validation\out" mkdir "validation\out"

echo [check] Compiling ERC sources against mock SDK...
cl /nologo /std:c++17 /EHsc /W3 /D_CRT_SECURE_NO_WARNINGS /c /I include /I validation\mock-sdk ^
   src\ERCPlugin.cpp src\ERCNatives.cpp src\ERCMain.cpp /Fo:validation\out\

if errorlevel 1 (
    echo [check] COMPILE FAILED
    exit /b 1
)

echo [check] COMPILE OK
exit /b 0
