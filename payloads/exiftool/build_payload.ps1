<#
.SYNOPSIS
  Builds the scAnt exiftool payload (Windows 64-bit, scAnt layout).

.DESCRIPTION
  Downloads the pinned official exiftool Windows zip from the exiftool
  SourceForge mirror (hash-verified), renames "exiftool(-k).exe" to
  "exiftool.exe" (upstream's documented install step), and packages
  exe + exiftool_files/ + upstream README in the layout scAnt expects
  under external/.
#>
param(
    [string]$Version = "13.59",
    [string]$Sha256 = "44b512b25af500724ba579d0a53c8fc5851628b692dd5e5d94ae4a15c2cba9ec",
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "dist" }
$url = "https://sourceforge.net/projects/exiftool/files/exiftool-${Version}_64.zip/download"

$work = Join-Path $env:TEMP "exiftool-build-$([guid]::NewGuid().ToString('N'))"
$stage = Join-Path $work "stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# 1. download + verify
$zipIn = Join-Path $work "exiftool-${Version}_64.zip"
Invoke-WebRequest -Uri $url -OutFile $zipIn -UserAgent "curl"
$h = (Get-FileHash $zipIn -Algorithm SHA256).Hash.ToLower()
if ($h -ne $Sha256) { throw "exiftool zip hash mismatch: got $h, expected $Sha256" }

# 2. extract + stage in scAnt layout
Expand-Archive $zipIn -DestinationPath $work
$srcDir = Join-Path $work "exiftool-${Version}_64"
Copy-Item (Join-Path $srcDir "exiftool(-k).exe") "$stage\exiftool.exe"
Copy-Item (Join-Path $srcDir "exiftool_files") "$stage\exiftool_files" -Recurse
Copy-Item (Join-Path $srcDir "README.txt") "$stage\README_upstream.txt"
Copy-Item "$PSScriptRoot\README.md" $stage

# 3. SHA256SUMS + zip (bsdtar for spec-conformant forward-slash entries)
$sums = Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $fh = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $_.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    "$fh  $rel"
}
$sums | Out-File -Encoding utf8 "$stage\SHA256SUMS.txt"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipOut = Join-Path $OutDir "scAnt-payload-exiftool_${Version}_win64.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
tar -a -cf $zipOut -C $stage .
if ($LASTEXITCODE -ne 0) { throw "tar zip creation failed" }
Remove-Item $work -Recurse -Force

$zh = Get-FileHash $zipOut -Algorithm SHA256
Write-Host "built : $zipOut"
Write-Host "sha256: $($zh.Hash.ToLower())"
Write-Host "size  : $((Get-Item $zipOut).Length) bytes"
