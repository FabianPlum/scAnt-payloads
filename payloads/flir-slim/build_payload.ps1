<#
.SYNOPSIS
  Reproducibly builds the scAnt slim FLIR payload zip.

.DESCRIPTION
  Stages the official Teledyne PySpin wheel, the PGRUsb3 USB3 kernel driver
  and the license documentation into the payload layout, generates
  SHA256SUMS.txt, and zips the result. All binary inputs are official
  Teledyne artifacts and are used unmodified.

  Expected inputs (defaults assume a machine with the Spinnaker SDK
  installed and the PySpin distribution zip downloaded from Teledyne):
    -WheelPath   spinnaker_python-4.2.0.88-cp310-cp310-win_amd64.whl
    -DriverDir   <SDK>\driver64\PGRUsb3  (PGRUSBCam3.inf/.sys, .cat, WdfCoInstaller)
    -PySpinZip   spinnaker_python-<ver>-cp310-cp310-win_amd64.zip
                 (source of licenses/FLIR_license.txt etc.)
    -OutDir      output directory for the zip

  NOTICE.txt, README.md and LGPL-2.1.txt are taken from this directory
  (they are the version-controlled sources of the in-archive docs).
#>
param(
    [Parameter(Mandatory)] [string]$WheelPath,
    [string]$DriverDir = "C:\Program Files\Teledyne\Spinnaker\driver64\PGRUsb3",
    [Parameter(Mandatory)] [string]$PySpinZip,
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
$payloadDocs = $PSScriptRoot
# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "dist" }

$wheelName = Split-Path $WheelPath -Leaf
if ($wheelName -notmatch "^spinnaker_python-(\d+\.\d+\.\d+\.\d+)-") {
    throw "Cannot parse wheel version from '$wheelName'"
}
$ver = $Matches[1]

$stage = Join-Path $env:TEMP "flir-slim-stage-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path "$stage\wheel", "$stage\driver", "$stage\licenses" | Out-Null

# 1. wheel
Copy-Item $WheelPath "$stage\wheel\"

# 2. driver (whole folder, unmodified)
foreach ($f in "PGRUSBCam3.inf", "PGRUSBCam3.sys", "pgrusbcam3.cat") {
    if (-not (Test-Path (Join-Path $DriverDir $f))) { throw "Missing driver file: $f in $DriverDir" }
}
Copy-Item $DriverDir "$stage\driver\PGRUsb3" -Recurse

# 3. licenses from the official PySpin distribution zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipIn = [System.IO.Compression.ZipFile]::OpenRead($PySpinZip)
try {
    $licEntries = $zipIn.Entries | Where-Object { $_.FullName -like "licenses/*" -and $_.Name }
    if (-not $licEntries) { throw "No licenses/ entries found in $PySpinZip" }
    foreach ($e in $licEntries) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, "$stage\licenses\$($e.Name)", $true)
    }
} finally { $zipIn.Dispose() }

# 4. version-controlled docs + LGPL text (wheel bundles LGPL-2.1 FFmpeg DLLs)
Copy-Item "$payloadDocs\NOTICE.txt", "$payloadDocs\README.md" $stage
Copy-Item "$payloadDocs\LGPL-2.1.txt" "$stage\licenses\"

# 5. per-file SHA256SUMS
Push-Location $stage
$sums = Get-ChildItem -Recurse -File | ForEach-Object {
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $_.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    "$h  $rel"
}
$sums | Out-File -Encoding utf8 "$stage\SHA256SUMS.txt"
Pop-Location

# 6. zip + report
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipOut = Join-Path $OutDir "scAnt-payload-flir-slim_${ver}_win64.zip"
# bsdtar (in-box on Win10+) writes spec-conformant forward-slash zip entries;
# PowerShell Compress-Archive writes backslashes, which breaks non-Windows unzip
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
tar -a -cf $zipOut -C $stage .
if ($LASTEXITCODE -ne 0) { throw "tar zip creation failed" }
Remove-Item $stage -Recurse -Force

$zh = Get-FileHash $zipOut -Algorithm SHA256
Write-Host "built : $zipOut"
Write-Host "sha256: $($zh.Hash.ToLower())"
Write-Host "size  : $((Get-Item $zipOut).Length) bytes"
Write-Host "Update manifest.json with the sha256/size above when pinning."
