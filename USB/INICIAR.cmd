@echo off
title WinDeployKit - Preparacao de maquinas
color 0B

rem ---------------------------------------------------------------------------
rem  Ponto de entrada unico. Da duplo clique neste arquivo.
rem  Pede elevacao e abre o menu (scripts\Menu.ps1).
rem ---------------------------------------------------------------------------

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo.
    echo   Solicitando privilegios de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Menu.ps1"

if not "%errorlevel%"=="0" (
    echo.
    echo   O menu terminou com erro. Veja o log em C:\WinDeployKit\Logs
    echo.
    pause
)
