<#
.SYNOPSIS
  Builds the scAnt shinestacker payload (patched wheel + corresponding source).

.DESCRIPTION
  Clones upstream shinestacker at the pinned SHA, applies the scAnt patches
  from patches/ (pyproject relaxation for py3.10 + headless PySide6 guard),
  builds the wheel, and packages wheel + patched-source archive + patches +
  LGPL license text. The local scAnt dev clone is NOT an input — this builds
  from upstream, reproducibly.

  LGPL-3.0 note: the source archive in the payload IS the corresponding
  source for the wheel (upstream @ pinned SHA + these patches), satisfying
  LGPL §6(d) when both ship on the same release.
#>
param(
    [string]$Sha = "fdea354652439ddc5aabcdac811a1cfcd05a2911",
    [string]$Version = "1.15.0.post1.dev5",
    [string]$PythonExe = "python",
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "dist" }
$repoUrl = "https://github.com/lucalista/shinestacker.git"

$work = Join-Path $env:TEMP "shinestacker-build-$([guid]::NewGuid().ToString('N'))"
$src = Join-Path $work "src"
New-Item -ItemType Directory -Force -Path $src | Out-Null

# 1. fetch upstream at the pinned SHA (shallow, by exact commit)
git -C $src init -q
git -C $src remote add origin $repoUrl
git -C $src fetch -q --depth 1 origin $Sha
git -C $src checkout -q FETCH_HEAD
$got = (git -C $src rev-parse HEAD).Trim()
if ($got -ne $Sha) { throw "Fetched $got, expected $Sha" }

# 2. apply scAnt patches (order matters)
Get-ChildItem "$PSScriptRoot\patches\*.patch" | Sort-Object Name | ForEach-Object {
    Write-Host "applying $($_.Name)"
    git -C $src apply --whitespace=nowarn $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "patch failed: $($_.Name)" }
}

# 3. build the wheel (version pinned; setuptools-scm cannot see tags in a
#    shallow checkout, and the patched tree is intentionally not a tag state)
$stage = Join-Path $work "stage"
New-Item -ItemType Directory -Force -Path "$stage\wheel", "$stage\source", "$stage\patches", "$stage\licenses" | Out-Null
$env:SETUPTOOLS_SCM_PRETEND_VERSION = $Version
& $PythonExe -m pip wheel --no-deps -w "$stage\wheel" $src
if ($LASTEXITCODE -ne 0) { throw "wheel build failed" }
Remove-Item Env:\SETUPTOOLS_SCM_PRETEND_VERSION

# 4. corresponding source archive (patched tree, no .git) — commit the
#    patches in the throwaway clone so git archive captures them. Scope =
#    what regenerates the wheel (build config, src, tests, docs, license);
#    upstream's examples/ and img/ sample data (~180 MB) are not part of
#    the library's corresponding source.
$srcZip = "$stage\source\shinestacker-$Version-source+scant-patches.zip"
git -C $src -c user.email="build@scant" -c user.name="scAnt payload build" commit -aqm "scAnt patches on $Sha"
git -C $src archive --format=zip -o $srcZip HEAD -- pyproject.toml LICENSE README.md src tests docs scripts
if ($LASTEXITCODE -ne 0) { throw "git archive failed" }

# 5. patches + license + docs
Copy-Item "$PSScriptRoot\patches\*.patch" "$stage\patches\"
Copy-Item "$src\LICENSE" "$stage\licenses\shinestacker-LICENSE-LGPL-3.0.txt"
Copy-Item "$PSScriptRoot\README.md" $stage

# 6. SHA256SUMS + zip
$sums = Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $fh = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $_.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    "$fh  $rel"
}
$sums | Out-File -Encoding utf8 "$stage\SHA256SUMS.txt"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipOut = Join-Path $OutDir "scAnt-payload-shinestacker_${Version}_py3-none-any.zip"
# bsdtar (in-box on Win10+) writes spec-conformant forward-slash zip entries;
# PowerShell Compress-Archive writes backslashes, which breaks non-Windows unzip
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
tar -a -cf $zipOut -C $stage .
if ($LASTEXITCODE -ne 0) { throw "tar zip creation failed" }
Remove-Item $work -Recurse -Force

$zh = Get-FileHash $zipOut -Algorithm SHA256
Write-Host "built : $zipOut"
Write-Host "sha256: $($zh.Hash.ToLower())"
Write-Host "size  : $((Get-Item $zipOut).Length) bytes"
