# Spell Swap uninstaller. Double-click Uninstall.bat instead of running this directly.
param(
    [string]$GameDir = "",
    [switch]$NoPause,
    [switch]$RemoveBepInEx   # also remove BepInEx without asking (only if the Spell Swap installer put it there)
)

$ErrorActionPreference = "Stop"
$GameName = "Castlevania Belmont's Curse"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Done([int]$code) {
    if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
    exit $code
}

function Test-GameDir($dir) {
    return $dir -and (Test-Path (Join-Path $dir "GameAssembly.dll")) -and (Test-Path (Join-Path $dir "$GameName.exe"))
}

function Get-SteamLibraries {
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($n in 'SteamPath', 'InstallPath') { if ($p.$n) { $roots += $p.$n } }
        } catch { }
    }
    foreach ($e in ${env:ProgramFiles(x86)}, $env:ProgramFiles) { if ($e) { $roots += (Join-Path $e 'Steam') } }
    $libs = @()
    foreach ($r in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path $r)) { continue }
        $libs += $r
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += $m.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    return $libs | Where-Object { Test-Path $_ } | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique
}

$game = $null
if (Test-GameDir $GameDir) { $game = (Resolve-Path $GameDir).Path }
elseif (Test-GameDir $Here) { $game = $Here }
else {
    foreach ($lib in Get-SteamLibraries) {
        $c = Join-Path $lib "steamapps\common\$GameName"
        if (Test-GameDir $c) { $game = $c; break }
    }
}
if (-not $game) {
    Write-Host "[ERROR] Could not find the game folder. Run: Uninstall.bat `"<path to the game folder>`"" -ForegroundColor Red
    Done 1
}
if (Get-Process -Name $GameName -ErrorAction SilentlyContinue) {
    Write-Host "[ERROR] The game is running. Close it and run the uninstaller again." -ForegroundColor Red
    Done 1
}

Write-Host ""
Write-Host "=== Spell Swap uninstaller ===" -ForegroundColor Cyan
Write-Host "Game folder: $game"

$plugin = Join-Path $game "BepInEx\plugins\SpellSwap"
if (Test-Path $plugin) { Remove-Item $plugin -Recurse -Force; Write-Host "Removed the plugin." } else { Write-Host "The plugin was not installed." }
$cfg = Join-Path $game "BepInEx\config\pikselyt.belmontscurse.spellswap.cfg"
if (Test-Path $cfg) { Remove-Item $cfg -Force; Write-Host "Removed its config file." }

$marker = Join-Path $game "BepInEx\.installed_by_spellswap"
if (Test-Path $marker) {
    $answer = if ($RemoveBepInEx) { "y" } else { Read-Host "BepInEx was installed by this installer. Remove it too? (y/N)" }
    if ($answer -match '^[yY]') {
        foreach ($item in 'winhttp.dll', 'doorstop_config.ini', '.doorstop_version', 'changelog.txt', 'BepInEx', 'dotnet') {
            $p = Join-Path $game $item
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }
        Write-Host "Removed BepInEx."
    } else {
        Write-Host "Left BepInEx in place (the game still runs fine with it)."
    }
} else {
    Write-Host "BepInEx itself was not touched."
}
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Done 0
