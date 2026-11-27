@echo off
setlocal
cd /d "%~dp0\.."

if exist "%LOCALAPPDATA%\Programs\gleam\gleam.exe" set "PATH=%LOCALAPPDATA%\Programs\gleam;%PATH%"
if exist "%LOCALAPPDATA%\Programs\erlang\bin\erl.exe" set "PATH=%LOCALAPPDATA%\Programs\erlang\bin;%PATH%"

if "%PORT%"=="" set "PORT=3000"
if "%SEED_DATA%"=="" set "SEED_DATA=true"

echo Starting Banking Transactions API (Gleam + Wisp) on http://localhost:%PORT% (SEED_DATA=%SEED_DATA%)...
gleam run
