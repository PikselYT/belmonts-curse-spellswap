# Spell Swap installer for Castlevania: Belmont's Curse (Windows).
# Double-click Install.bat instead of running this directly.
#
# What it does:
#   1. finds your game folder (Steam libraries) - or asks you to pick it
#   2. installs BepInEx (the mod loader) from the bundled, hash-checked archive if you do not have it yet
#   3. copies SpellSwap.dll to BepInEx\plugins\SpellSwap\
param(
    [string]$GameDir = "",
    [switch]$NoPause,
    [switch]$DryRun   # only report what would be done (used for testing)
)

$ErrorActionPreference = "Stop"
$GameName = "Castlevania Belmont's Curse"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$BepInExZip = Join-Path $Here "BepInEx-be.789.zip"
$BepInExSha256 = "29519614d0121a3eefc9df6d61436f0c09a2c5f85b0a7d92559a135ce3055eb1"

function Done([int]$code) {
    if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
    exit $code
}

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    Done 1
}

# Plain .NET instead of Get-FileHash / Expand-Archive: works on every Windows PowerShell, whatever modules are loaded.
function Get-Sha256([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLower() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Expand-ZipOverwrite([string]$zipPath, [string]$dest) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [System.IO.Path]::GetFullPath($dest)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($e in $zip.Entries) {
            $target = [System.IO.Path]::GetFullPath((Join-Path $root $e.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe path in archive: $($e.FullName)" }
            if ($e.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force $target | Out-Null; continue }
            New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
        }
    } finally { $zip.Dispose() }
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

function Find-GameDir {
    if (Test-GameDir $GameDir) { return (Resolve-Path $GameDir).Path }
    if ($GameDir) { Fail "'$GameDir' does not look like the $GameName folder (GameAssembly.dll / the .exe is missing)." }
    # installer unpacked straight into the game folder?
    if (Test-GameDir $Here) { return $Here }
    foreach ($lib in Get-SteamLibraries) {
        $candidate = Join-Path $lib "steamapps\common\$GameName"
        if (Test-GameDir $candidate) { return $candidate }
    }
    return $null
}

Write-Host ""
Write-Host "=== Spell Swap installer ===" -ForegroundColor Cyan
Write-Host ""

$game = Find-GameDir
if (-not $game) {
    Write-Host "Could not find the game automatically. Please pick the folder that contains '$GameName.exe'."
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select the $GameName folder (the one with the .exe)"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Fail "No folder selected." }
    if (-not (Test-GameDir $dlg.SelectedPath)) { Fail "That folder does not contain $GameName.exe and GameAssembly.dll." }
    $game = $dlg.SelectedPath
}
Write-Host "Game folder: $game"

if (Get-Process -Name $GameName -ErrorAction SilentlyContinue) {
    Fail "The game is running. Close it and run the installer again."
}

$plugin = Join-Path $Here "SpellSwap.dll"
if (-not (Test-Path $plugin)) { Fail "SpellSwap.dll is missing next to the installer. Extract the whole zip first." }

if ($DryRun) {
    $loader = Test-Path (Join-Path $game "BepInEx\core\BepInEx.Unity.IL2CPP.dll")
    Write-Host "[dry run] would install the plugin into '$game\BepInEx\plugins\SpellSwap'; BepInEx IL2CPP already present: $loader"
    Done 0
}

# --- BepInEx (mod loader) ---
$hasIl2cppLoader = Test-Path (Join-Path $game "BepInEx\core\BepInEx.Unity.IL2CPP.dll")
if ($hasIl2cppLoader) {
    Write-Host "BepInEx (IL2CPP) is already installed - leaving it as it is."
} else {
    if (Test-Path (Join-Path $game "BepInEx\core\BepInEx.dll")) {
        Fail "An incompatible (Mono) BepInEx is installed. Remove the BepInEx folder, winhttp.dll and doorstop_config.ini from the game folder and try again."
    }
    if (Test-Path (Join-Path $game "winhttp.dll")) {
        Fail "A winhttp.dll from another mod loader is already in the game folder. Remove it (or install BepInEx 6 IL2CPP manually) and try again."
    }
    if (-not (Test-Path $BepInExZip)) { Fail "BepInEx-be.789.zip is missing next to the installer. Extract the whole zip first." }
    $actual = Get-Sha256 $BepInExZip
    if ($actual -ne $BepInExSha256) { Fail "The bundled BepInEx archive failed its checksum (expected $BepInExSha256, got $actual). Download the release again." }
    Write-Host "Installing BepInEx 6.0.0-be.789 ..."
    Expand-ZipOverwrite $BepInExZip $game
    # marker so the uninstaller knows it may remove BepInEx too
    Set-Content -Path (Join-Path $game "BepInEx\.installed_by_spellswap") -Value "BepInEx be.789 installed by the Spell Swap installer" -Encoding ASCII
}

# --- the plugin ---
$dest = Join-Path $game "BepInEx\plugins\SpellSwap"
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item $plugin (Join-Path $dest "SpellSwap.dll") -Force
Write-Host "Installed: $dest\SpellSwap.dll"

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "Start the game from Steam. The FIRST launch is slower (1-3 minutes, the screen may look frozen)"
Write-Host "while BepInEx prepares itself. Afterwards: D-pad left/right switches spells, the left stick walks."
Done 0
