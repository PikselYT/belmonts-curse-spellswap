# Builds the plugin and packs the two release zips into dist\:
#   SpellSwap-<version>.zip              easy package: installer + bundled BepInEx + plugin
#   SpellSwap-<version>-plugin-only.zip  just the plugin, laid out for extracting into the game folder
# plus SHA256SUMS.txt.
#
# Needs: .NET SDK 6+ and a game install where BepInEx has been started once (it generates the
# BepInEx\interop assemblies this project compiles against). Run:  powershell -File build.ps1
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\Castlevania Belmont's Curse\"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$BepInExUrl = "https://builds.bepinex.dev/projects/bepinex_be/789/BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.789%2B6cea286.zip"
$BepInExSha256 = "29519614d0121a3eefc9df6d61436f0c09a2c5f85b0a7d92559a135ce3055eb1"

function Get-Sha256([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLower() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

# Zip with forward-slash entry names (Compress-Archive in Windows PowerShell 5.1 writes backslashes,
# which some extractors mishandle).
function New-Zip([string]$sourceDir, [string]$zipPath) {
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    $base = (Resolve-Path $sourceDir).Path.TrimEnd('\')
    $fs = [System.IO.File]::Create($zipPath)
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $base -Recurse -File) {
            $name = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose(); $fs.Dispose() }
}

if (-not $GameDir.EndsWith("\")) { $GameDir += "\" }
if (-not (Test-Path "$($GameDir)BepInEx\interop\Assembly-CSharp.dll")) {
    throw "Assembly-CSharp.dll not found under '$($GameDir)BepInEx\interop'. Install BepInEx and start the game once, or pass -GameDir."
}

$csproj = Join-Path $root "src\SpellSwap\SpellSwap.csproj"
$version = ([xml](Get-Content $csproj)).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
Write-Host "Building Spell Swap $version ..."
dotnet build $csproj -c Release -p:Deploy=false "-p:GameDir=$($GameDir.TrimEnd('\'))"
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
$dll = Join-Path $root "src\SpellSwap\bin\Release\net6.0\SpellSwap.dll"

# BepInEx archive (cached, hash-checked)
$cache = Join-Path $root "build\cache"
New-Item -ItemType Directory -Force $cache | Out-Null
$bepZip = Join-Path $cache "BepInEx-be.789.zip"
if (-not (Test-Path $bepZip)) {
    Write-Host "Downloading BepInEx be.789 ..."
    Invoke-WebRequest -Uri $BepInExUrl -OutFile $bepZip
}
$hash = Get-Sha256 $bepZip
if ($hash -ne $BepInExSha256) { Remove-Item $bepZip; throw "BepInEx archive checksum mismatch ($hash)" }

$dist = Join-Path $root "dist"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $dist | Out-Null

# 1) easy package
$easyName = "SpellSwap-$version"
$easyStage = Join-Path $dist $easyName
New-Item -ItemType Directory -Force $easyStage | Out-Null
Copy-Item $dll $easyStage
Copy-Item "$root\installer\*" $easyStage -Recurse
Copy-Item $bepZip (Join-Path $easyStage "BepInEx-be.789.zip")
Copy-Item "$root\LICENSE", "$root\THIRD-PARTY-NOTICES.md" $easyStage
$easyZip = Join-Path $dist "$easyName.zip"
New-Zip $easyStage $easyZip

# 2) plugin-only package (extract into the game folder)
$lightName = "SpellSwap-$version-plugin-only"
$lightStage = Join-Path $dist $lightName
$pluginDir = Join-Path $lightStage "BepInEx\plugins\SpellSwap"
New-Item -ItemType Directory -Force $pluginDir | Out-Null
Copy-Item $dll $pluginDir
Copy-Item "$root\packaging\README-plugin-only.txt" (Join-Path $lightStage "README.txt")
Copy-Item "$root\LICENSE" $lightStage
$lightZip = Join-Path $dist "$lightName.zip"
New-Zip $lightStage $lightZip

# checksums
$lines = foreach ($f in @($easyZip, $lightZip)) { "{0} *{1}" -f (Get-Sha256 $f), (Split-Path -Leaf $f) }
$lines += "{0} *SpellSwap.dll (inside both zips)" -f (Get-Sha256 $dll)
Set-Content -Path (Join-Path $dist "SHA256SUMS.txt") -Value $lines -Encoding ASCII

Write-Host ""
foreach ($f in @($easyZip, $lightZip)) { Write-Host ("{0,-40} {1,6:N1} MB" -f (Split-Path -Leaf $f), ((Get-Item $f).Length / 1MB)) }
Write-Host ""
$lines | ForEach-Object { Write-Host $_ }
