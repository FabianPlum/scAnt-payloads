<#
.SYNOPSIS
  Builds the scAnt env-lock payload zip (micromamba + lockfiles).

.DESCRIPTION
  Downloads the pinned micromamba release (hash-verified against
  inputs.json), copies the lockfiles from a scAnt repo checkout and the
  version-controlled docs from this directory, generates SHA256SUMS.txt,
  and zips the payload.

  Inputs:
    -ScAntRepo      path to a scAnt_pro checkout whose conda_environment/
                    holds the current conda-lock.yml + scAnt_pro-win-64.lock
    -OutDir         output directory for the zip
#>
param(
    [Parameter(Mandatory)] [string]$ScAntRepo,
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "dist" }

$mmVersion = "2.8.1-0"
$mmSha256 = "8a51f88ec02600488ea20c3acd93fbd4da6c0f03fc499aa53fd234c6749b94b0"
$mmUrl = "https://github.com/mamba-org/micromamba-releases/releases/download/$mmVersion/micromamba-win-64.exe"

$lockYml = Join-Path $ScAntRepo "conda_environment\conda-lock.yml"
$lockExplicit = Join-Path $ScAntRepo "conda_environment\scAnt_pro-win-64.lock"
foreach ($f in $lockYml, $lockExplicit) {
    if (-not (Test-Path $f)) { throw "Missing lockfile: $f" }
}

$stage = Join-Path $env:TEMP "env-lock-stage-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $stage, "$stage\licenses" | Out-Null

# 1. micromamba, hash-verified
$mmExe = Join-Path $stage "micromamba.exe"
Invoke-WebRequest -Uri $mmUrl -OutFile $mmExe
$h = (Get-FileHash $mmExe -Algorithm SHA256).Hash.ToLower()
if ($h -ne $mmSha256) { throw "micromamba hash mismatch: got $h, expected $mmSha256" }

# 2. lockfiles from the scAnt repo
Copy-Item $lockYml, $lockExplicit $stage

# 3. version-controlled docs + license
Copy-Item "$PSScriptRoot\README.md" $stage
Copy-Item "$PSScriptRoot\micromamba_LICENSE.txt" "$stage\licenses\"

# 4. per-file SHA256SUMS
$sums = Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $fh = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $_.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    "$fh  $rel"
}
$sums | Out-File -Encoding utf8 "$stage\SHA256SUMS.txt"

# 5. zip + report
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$dateVer = Get-Date -Format "yyyy.MM.dd"
$zipOut = Join-Path $OutDir "scAnt-payload-env-lock_${dateVer}_win64.zip"
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
Write-Host "Update manifest.json + inputs.json outputVersion when pinning."
