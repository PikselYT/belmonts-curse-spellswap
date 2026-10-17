@echo off
title Spell Swap installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
