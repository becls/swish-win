@echo off

:: Visual Studio 2017 Enterprise
set BATDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\2017\Enterprise\Common7\Tools
if exist "%BATDIR%\VsDevCmd.bat" goto found

:: Visual Studio 2017 Professional
set BATDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\2017\Professional\Common7\Tools
if exist "%BATDIR%\VsDevCmd.bat" goto found

:: Visual Studio 2017 Community
set BATDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\2017\Community\Common7\Tools
if exist "%BATDIR%\VsDevCmd.bat" goto found

echo Visual Studio 2017 must be installed.
exit 1

:found

:: Clear environment variables that we might otherwise inherit
set INCLUDE=
set LIB=
set LIBPATH=

:: Visual Studio 2017's vcvarsall.bat changes the directory to %USERPROFILE%\Source if the directory exists. See https://developercommunity.visualstudio.com/content/problem/26780/vsdevcmdbat-changes-the-current-working-directory.html
set VSCMD_START_DIR=%CD%
call "%BATDIR%\VsDevCmd.bat" > nul
%*
