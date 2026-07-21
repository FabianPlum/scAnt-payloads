<#
.SYNOPSIS
  Builds the scAnt bootstrap installer (scAnt-Setup-<ver>.exe).

.DESCRIPTION
  Stages the embedded content (app tree from a scAnt_pro checkout, env-lock +
  shinestacker payload contents — hash-verified against manifest.json),
  generates build\pins.iss from the manifest, and compiles scAnt-Setup.iss
  with Inno Setup.

  -LocalPayloadDir: directory containing already-built payload zips (skips
   downloading them from the release); zips are still hash-verified.
#>
param(
    [string]$ScAntRepo = "C:\Users\Legos\dev\scAnt_pro",
    [string]$LocalPayloadDir,
    [string]$IsccPath = "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$repoRoot = Split-Path $root
$manifest = (Get-Content "$repoRoot\manifest.json" -Raw) | ConvertFrom-Json
$buildDir = Join-Path $root "build"

if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
foreach ($d in "app", "env-lock", "wheels", "eula", "third_party\shinestacker") {
    New-Item -ItemType Directory -Force (Join-Path $buildDir $d) | Out-Null
}

function Get-Component([string]$name) {
    $c = $manifest.components | Where-Object { $_.name -eq $name }
    if (-not $c) { throw "component '$name' not in manifest" }
    $c
}

function Get-PayloadZip($comp) {
    $fname = [System.IO.Path]::GetFileName(([uri]$comp.url).LocalPath)
    if ($LocalPayloadDir) { $cand = Join-Path $LocalPayloadDir $fname } else { $cand = Join-Path $env:TEMP $fname }
    if (-not (Test-Path $cand)) {
        Write-Host "downloading $($comp.name) from $($comp.url)"
        Invoke-WebRequest $comp.url -OutFile $cand
    }
    $h = (Get-FileHash $cand -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $comp.sha256) { throw "hash mismatch for $($comp.name): got $h, manifest $($comp.sha256)" }
    $cand
}

# ---- 1. app tree: tracked files at HEAD, then prune dev/legacy weight ----
Write-Host "staging app tree from $ScAntRepo (HEAD)"
$appTar = Join-Path $env:TEMP "scant-app-$([guid]::NewGuid().ToString('N')).tar"
git -C $ScAntRepo archive -o $appTar HEAD
if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
tar -xf $appTar -C (Join-Path $buildDir "app")
Remove-Item $appTar -Force

$appDir = Join-Path $buildDir "app"
# legacy Hugin/enfuse/wx suite: loose exes/dlls at external root (everything
# except exiftool + the camera DB text files); REFACTOR_PLAN marks them dropped
Get-ChildItem "$appDir\external" -File | Where-Object {
    $_.Name -notin @("exiftool.exe", "cameraMakes.txt", "cameraSensors.txt")
} | Remove-Item -Force
# focus-stack: keep exe + runtime DLLs, drop Linux AppImage + debug artifacts
Remove-Item "$appDir\external\focus-stack\focus-stack.AppImage",
            "$appDir\external\focus-stack\focus-stack.pdb",
            "$appDir\external\focus-stack\focus-stack.ilk" -Force -ErrorAction SilentlyContinue
# internal docs / legacy / tests are not part of the shipped app
foreach ($d in "docs", "legacy_scripts", "tests") {
    if (Test-Path "$appDir\$d") { Remove-Item "$appDir\$d" -Recurse -Force }
}
$appMB = [int]((Get-ChildItem $appDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "app tree staged: $appMB MB"

# provenance: record the exact app commit inside the install + for pins.iss
$appSha = (git -C $ScAntRepo rev-parse HEAD).Trim()
$appSha | Out-File -Encoding ascii "$appDir\APP_TREE_SHA.txt"
Write-Host "app tree commit: $appSha"

# installer/shortcut icon from the app tree
Copy-Item "$appDir\images\scAnt_icon.ico" (Join-Path $buildDir "scAnt_icon.ico")

# ---- 2. env-lock payload (embedded) ----
$elComp = Get-Component "env-lock"
tar -xf (Get-PayloadZip $elComp) -C (Join-Path $buildDir "env-lock")
if ($LASTEXITCODE -ne 0) { throw "env-lock extract failed" }

# ---- 3. shinestacker payload: wheel embedded + LGPL source/notices carried ----
$ssComp = Get-Component "shinestacker"
$ssx = Join-Path $env:TEMP "ssx-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force $ssx | Out-Null
tar -xf (Get-PayloadZip $ssComp) -C $ssx
Copy-Item "$ssx\wheel\*.whl" (Join-Path $buildDir "wheels")
# LGPL §6(d): the corresponding source + patches + license travel with the wheel
Copy-Item "$ssx\source", "$ssx\patches", "$ssx\licenses" (Join-Path $buildDir "third_party\shinestacker") -Recurse
Remove-Item $ssx -Recurse -Force

# micromamba license into third_party as well
Copy-Item (Join-Path $buildDir "env-lock\licenses\micromamba_LICENSE.txt") (Join-Path $buildDir "third_party")

# ---- 4. FLIR EULA text for the wizard page (no FLIR binaries embedded) ----
$flirComp = Get-Component "flir-slim"
$fx = Join-Path $env:TEMP "flirx-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force $fx | Out-Null
tar -xf (Get-PayloadZip $flirComp) -C $fx "licenses/FLIR_license.txt"
# the wizard memo renders ANSI — transcode the display copy to Windows-1252
# (every character in the EULA exists there; the payload itself stays UTF-8)
$eulaText = [System.IO.File]::ReadAllText("$fx\licenses\FLIR_license.txt", [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $buildDir "eula\FLIR_license.txt"), $eulaText, [System.Text.Encoding]::GetEncoding(1252))
Remove-Item $fx -Recurse -Force

# ---- 5. pins.iss from the manifest ----
$cc = Get-Component "colmap-cuda"
$cn = Get-Component "colmap-nocuda"
$br = Get-Component "brush"
$ssWheel = (Get-ChildItem (Join-Path $buildDir "wheels") -Filter *.whl | Select-Object -First 1).Name
$pySpinWheel = "spinnaker_python-$($flirComp.version)-cp310-cp310-win_amd64.whl"
function MB($bytes) { [int]($bytes / 1MB) }

@"
; generated by build_installer.ps1 from manifest.json (payloadSet $($manifest.payloadSet)) — do not edit
; app tree: scAnt_pro @ $appSha
#define PayloadSetVersion "$($manifest.payloadSet)"
#define AppTreeSha "$appSha"
#define FlirUrl "$($flirComp.url)"
#define FlirSha256 "$($flirComp.sha256)"
#define FlirSizeMB "$(MB $flirComp.size)"
#define ColmapCudaUrl "$($cc.url)"
#define ColmapCudaSha256 "$($cc.sha256)"
#define ColmapCudaSizeMB "$(MB $cc.size)"
#define ColmapNocudaUrl "$($cn.url)"
#define ColmapNocudaSha256 "$($cn.sha256)"
#define ColmapNocudaSizeMB "$(MB $cn.size)"
#define BrushUrl "$($br.url)"
#define BrushSha256 "$($br.sha256)"
#define BrushSizeMB "$(MB $br.size)"
#define PipPins "$((Get-Component 'env-lock').postInstall.pipPins)"
#define ShinestackerWheel "$ssWheel"
#define PySpinWheel "$pySpinWheel"
"@ | Out-File -Encoding ascii (Join-Path $buildDir "pins.iss")

# ---- 6. compile ----
if (-not (Test-Path $IsccPath)) { throw "ISCC.exe not found at $IsccPath" }
& $IsccPath /Qp (Join-Path $root "scAnt-Setup.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit $LASTEXITCODE" }

$exe = Get-ChildItem (Join-Path $root "Output") -Filter "scAnt-Setup-*.exe" | Sort-Object LastWriteTime | Select-Object -Last 1
$h = Get-FileHash $exe.FullName -Algorithm SHA256
Write-Host "built : $($exe.FullName)"
Write-Host "sha256: $($h.Hash.ToLower())"
Write-Host "size  : $([int]($exe.Length / 1MB)) MB"
