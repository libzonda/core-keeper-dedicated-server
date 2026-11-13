@echo off
title Core Keeper Dedicated Server & Manager
echo ========================================================
echo   Starting Core Keeper Dedicated Server & Manager...
echo ========================================================
echo.

rem Launch the Go server daemon in the background
start "CoreKeeper Server Daemon" /min "%~dp0corekeeper-manager.exe"

rem Launch the Flutter desktop GUI
start "" "%~dp0CoreKeeperManager.exe"

echo Started Core Keeper Server Manager.
