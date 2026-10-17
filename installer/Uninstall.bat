@echo off
title Spell Swap uninstaller
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
