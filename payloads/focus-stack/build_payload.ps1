<#
.SYNOPSIS
  Builds the scAnt focus-stack payload from the official upstream release.

.DESCRIPTION
  Downloads PetteriAimonen/focus-stack's Windows release zip (hash-verified),
  restages it flat in the layout scAnt expects (external/focus-stack/ with
  focus-stack.exe + runtime DLLs at the root), adds the upstream MIT license,
  and zips with bsdtar. Note: the upstream zip itself contains backslash
  path separators (Compress-Archive artifact) — Expand-Archive handles it;
  our restaged zip is spec-conformant.
#>
param(
    [string]$Version = "1.5",
    [string]$Sha256 = "0104c863e1fc961cd87520c87d41c927d2968822d48fd37e76da00e1dfb6c7c9",
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "dist" }
$url = "https://github.com/PetteriAimonen/focus-stack/releases/download/$Version/focus-stack_Windows.zip"
$licUrl = "https://raw.githubusercontent.com/PetteriAimonen/focus-stack/$Version/LICENSE.md"

$work = Join-Path $env:TEMP "focus-stack-build-$([guid]::NewGuid().ToString('N'))"
$stage = Join-Path $work "stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# 1. download + verify
$zipIn = Join-Path $work "focus-stack_Windows.zip"
Invoke-WebRequest -Uri $url -OutFile $zipIn
$h = (Get-FileHash $zipIn -Algorithm SHA256).Hash.ToLower()
if ($h -ne $Sha256) { throw "focus-stack zip hash mismatch: got $h, expected $Sha256" }

# 2. extract + flatten (upstream nests everything under focus-stack\)
Expand-Archive $zipIn -DestinationPath $work
$srcDir = Join-Path $work "focus-stack"
if (-not (Test-Path "$srcDir\focus-stack.exe")) { throw "unexpected upstream zip layout" }
Copy-Item "$srcDir\*" $stage -Recurse

# 3. license + docs
Invoke-WebRequest -Uri $licUrl -OutFile (Join-Path $stage "LICENSE.md")
Copy-Item "$PSScriptRoot\README.md" $stage

# 4. SHA256SUMS + zip (bsdtar for conformant forward-slash entries)
$sums = Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $fh = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $_.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    "$fh  $rel"
}
$sums | Out-File -Encoding utf8 "$stage\SHA256SUMS.txt"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipOut = Join-Path $OutDir "scAnt-payload-focus-stack_${Version}_win64.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
tar -a -cf $zipOut -C $stage .
if ($LASTEXITCODE -ne 0) { throw "tar zip creation failed" }
Remove-Item $work -Recurse -Force

$zh = Get-FileHash $zipOut -Algorithm SHA256
Write-Host "built : $zipOut"
Write-Host "sha256: $($zh.Hash.ToLower())"
Write-Host "size  : $((Get-Item $zipOut).Length) bytes"
