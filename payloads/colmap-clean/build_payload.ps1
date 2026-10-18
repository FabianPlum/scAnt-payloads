<#
.SYNOPSIS
  Packages the scAnt colmap-clean payload (COLMAP 4.1.1 without its GPL, AGPL
  and non-commercial parts, Windows x64) from a finished build folder.

.DESCRIPTION
  The binaries are built from source by build\tools\build_colmap.py (see
  README.md); this script only stages them. It checks the build folder
  against its pins (manifest.json's sha256, colmap.exe's sha256, and every
  file manifest.json lists), copies it unchanged, adds NOTICE.txt and
  README.md, writes SHA256SUMS.txt (every file of the archive), zips with
  bsdtar, and writes dist\SHA256SUMS.txt with the archive's own line.

  A rebuild makes different bytes (COLMAP and vcpkg's ports have no
  /Brepro): pass its -ManifestSha256 and -ExecutableSha256 (the lines
  build_colmap.py prints) and publish it under a new payload version.
#>
param(
    [Parameter(Mandatory = $true)][string]$BuildDir,
    [string]$Version = "4.1.1-1",
    [string]$ManifestSha256 = "b7906d8d3f55357d5e504fcbed077252323aa0251784cc92ae55c1c9f6c64909",
    [string]$ExecutableSha256 = "7d731548bcf20e679f1f3287c25a433c907bc9b21f453405202b7a8246094f4d",
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "dist" }
$BuildDir = (Resolve-Path $BuildDir).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }

# 1. the build folder is the one its pins name, file by file
$manifestPath = Join-Path $BuildDir "manifest.json"
$h = Get-Sha256 $manifestPath
if ($h -ne $ManifestSha256) { throw "manifest.json has sha256 $h, expected $ManifestSha256" }
$h = Get-Sha256 (Join-Path $BuildDir "bin\colmap.exe")
if ($h -ne $ExecutableSha256) { throw "bin\colmap.exe has sha256 $h, expected $ExecutableSha256" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$listed = @($manifest.files.PSObject.Properties)
foreach ($entry in $listed) {
    $h = Get-Sha256 (Join-Path $BuildDir $entry.Name)
    if ($h -ne $entry.Value) { throw "$($entry.Name) has sha256 $h, manifest.json says $($entry.Value)" }
}
$present = @(Get-ChildItem -LiteralPath $BuildDir -Recurse -File | ForEach-Object {
    $_.FullName.Substring($BuildDir.Length + 1).Replace([char]92, [char]47)
} | Where-Object { $_ -ne "manifest.json" })
$unlisted = @($present | Where-Object { -not $manifest.files.PSObject.Properties[$_] })
if ($unlisted.Count -gt 0) { throw "files manifest.json does not list: $($unlisted -join ', ')" }

# 2. stage: the build unchanged, the notices beside it
$work = Join-Path $env:TEMP "colmap-clean-payload-$([guid]::NewGuid().ToString('N'))"
$stage = Join-Path $work "stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($item in @("bin", "licences", "models", "manifest.json", "licence-proof.json")) {
    Copy-Item -LiteralPath (Join-Path $BuildDir $item) -Destination $stage -Recurse
}
Copy-Item "$PSScriptRoot\NOTICE.txt" $stage
Copy-Item "$PSScriptRoot\README.md" $stage

# 3. SHA256SUMS + zip (bsdtar for spec-conformant forward-slash entries)
$sums = Get-ChildItem $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    "$(Get-Sha256 $_.FullName)  $rel"
}
[IO.File]::WriteAllText((Join-Path $stage "SHA256SUMS.txt"), (($sums -join "`n") + "`n"), $utf8)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$name = "scAnt-payload-colmap-clean_${Version}_win64.zip"
$zipOut = Join-Path $OutDir $name
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
& "$env:SystemRoot\System32\tar.exe" -a -cf $zipOut -C $stage .
if ($LASTEXITCODE -ne 0) { throw "tar zip creation failed" }
Remove-Item $work -Recurse -Force

$zh = Get-Sha256 $zipOut
[IO.File]::WriteAllText((Join-Path $OutDir "SHA256SUMS.txt"), "$zh  $name`n", $utf8)
Write-Host "built : $zipOut"
Write-Host "sha256: $zh"
Write-Host "size  : $((Get-Item $zipOut).Length) bytes"
