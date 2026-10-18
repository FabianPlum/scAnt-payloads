"""Build COLMAP for Windows without its GPL, AGPL and non-commercial parts: ``colmap-clean`` (the phase 5b build list,
E7, stage 1; ``tools/pins.toml``, ``[tools.colmap-clean]``).

The pinned COLMAP 4.1.1 (``[tools.colmap]``, upstream's Windows build) carries SiftGPU (non-commercial) and the line
segment detector LSD (AGPL-3.0), and links CGAL (GPL-3.0, with GMP and MPFR) and SuiteSparse's SPQR and CHOLMOD's
Supernodal and MatrixOps modules (GPL-2.0-or-later; ``env/README.md``, "Licences"). COLMAP itself is BSD-3-Clause and
each of those parts is optional or replaceable. This tool builds the same release from its sources without them:

- **The sources:** COLMAP's tag at its pinned commit and vcpkg at its pinned commit (COLMAP 4.1.1's own baseline,
  ``vcpkg-configuration.json``), each fetched into the cache folder (default ``C:\\vc``: vcpkg and CUDA need short
  paths), and the repository's patches (``tools/colmap_patches/*.patch``, in name order) applied to COLMAP's checkout.
  ``0001-colmap-sift-gpu-option.patch`` adds the option ``SIFT_GPU_ENABLED``: off, SiftGPU is not built or linked
  while CUDA stays for the multi-view stereo (PatchMatch), ``use_gpu`` defaults to off, and a SIFT extraction or a
  SIFT brute-force match with ``use_gpu`` on fails its option check before any image is read (no silent fall-back to
  the CPU: the run says which features it made).
- **The libraries:** vcpkg in manifest mode on COLMAP's ``vcpkg.json`` with the feature ``cuda`` alone (no ``gui``,
  ``cgal``, ``download``), the triplet ``x64-windows-scant`` (``tools/colmap_ports/triplets``: shared libraries,
  release only, the pinned compiler) and the overlay port ``tools/colmap_ports/ceres``: Ceres 2.2.0 with SuiteSparse
  as CHOLMOD's LGPL modules only (Core, Check, Cholesky, Camd, Partition) and no SuiteSparseQR, through its patch
  ``0100-suitesparse-without-spqr.patch`` (SPQR optional, ``CERES_NO_SUITESPARSE_QR``: the covariance's ``SPARSE_QR``
  takes Eigen's sparse QR; CHOLMOD's MatrixOps wrappers only where the module is built). CHOLMOD without its
  Supernodal module factorises simplicially; Ceres keeps ``SPARSE_SCHUR`` and ``SPARSE_NORMAL_CHOLESKY`` on it.
- **The configuration** (:data:`CONFIGURATION`): no GUI (no Qt, no OpenGL), no CGAL, no LSD, no SiftGPU, CUDA on
  (PatchMatch stereo), ONNX on (ALIKED features and LightGlue matching; ONNX Runtime, MIT, the archive COLMAP's CMake
  pins), no Caspar, no tests, no download at run time (``DOWNLOAD_ENABLED`` off: the model paths must be given).
- **The layout** (``<dest>/colmap-clean``, default ``tools/.cache/tools``, the layout ``tools/fetch_tools.py`` gives
  ``colmap``): ``bin/colmap.exe``, the shared libraries it loads (the closure of its import tables over COLMAP's
  install and vcpkg's, the system's and the Visual C++ runtime's left out, as upstream's build does), so none of ONNX
  Runtime's providers: its CUDA provider needs NVIDIA's cuDNN and cuBLAS, which no build ships, and ALIKED and
  LightGlue run on the processor (``use_gpu`` with them fails: the provider is not there).
  ``models/``: the pinned ONNX files (``[tools.colmap-clean.weights.*]``, fetched and checked by
  sha256, with their licences). ``licences/``: the licence of every library shipped or linked in.
  ``licence-proof.json`` (:func:`licence_proof`): the import and export tables (``dumpbin``), the build graph's
  definitions and vcpkg's installed packages, with every finding; a finding fails the build. ``manifest.json``: every
  other file and its sha256, with the sources' pins; the pin's ``manifest_sha256`` and ``executable_sha256`` name the
  build of record.

The build is not reproducible byte for byte (COLMAP and vcpkg's ports have no ``/Brepro``): a new build prints the
lines its pin would need, and the pin names the build the stage measured.

Each step is resumable: a checkout at its commit with the patches applied is kept, vcpkg skips what it has built,
Ninja what is up to date. No console window opens; every child process runs without one, below normal priority.

Run from the repository root: ``<python> tools/build_colmap.py [--cache C:\\vc] [--dest DIR] [--jobs N]``. Exit 0
when built and proven, 1 for any failure.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import tomllib
import urllib.request
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TypeVar

T = TypeVar("T")
REPO_ROOT = Path(__file__).resolve().parents[1]
PINS = REPO_ROOT / "tools" / "pins.toml"
PIN_TABLE = ("tools", "colmap-clean")
PATCHES_DIR = REPO_ROOT / "tools" / "colmap_patches"
PORTS_DIR = REPO_ROOT / "tools" / "colmap_ports"
TRIPLETS_DIR = PORTS_DIR / "triplets"
TRIPLET = "x64-windows-scant"
DEFAULT_CACHE = Path("C:/vc")
DEFAULT_DEST = REPO_ROOT / "tools" / ".cache" / "tools"
COLMAP_URL = "https://github.com/colmap/colmap.git"
VCPKG_URL = "https://github.com/microsoft/vcpkg.git"
MANIFEST_NAME = "manifest.json"
PROOF_NAME = "licence-proof.json"
PATCH_STAMP = ".scant-patches"
"""The file in COLMAP's checkout naming the commit and the patches' digest it holds, so a rerun keeps its files."""
VSWHERE = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio/Installer"
VCVARS = Path("VC/Auxiliary/Build/vcvars64.bat")
BUNDLED_CMAKE = Path("Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe")
BUNDLED_NINJA = Path("Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe")
CUDA_ROOT = Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA")
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
GIT_TIMEOUT_S = 3600.0
VCPKG_TIMEOUT_S = 6 * 3600.0
BUILD_TIMEOUT_S = 6 * 3600.0
STEP_TIMEOUT_S = 1800.0
DOWNLOAD_TIMEOUT_S = 60.0
CONFIGURATION: tuple[tuple[str, str], ...] = (
    ("CMAKE_BUILD_TYPE", "Release"),
    ("GUI_ENABLED", "OFF"),
    ("OPENGL_ENABLED", "OFF"),
    ("CGAL_ENABLED", "OFF"),
    ("LSD_ENABLED", "OFF"),
    ("SIFT_GPU_ENABLED", "OFF"),
    ("CUDA_ENABLED", "ON"),
    ("MVS_ENABLED", "ON"),
    ("ONNX_ENABLED", "ON"),
    ("FETCH_ONNX", "ON"),
    ("CASPAR_ENABLED", "OFF"),
    ("TESTS_ENABLED", "OFF"),
    ("DOWNLOAD_ENABLED", "OFF"),
    ("CCACHE_ENABLED", "OFF"),
    ("UNINSTALL_ENABLED", "OFF"),
    ("BENCHMARK_ENABLED", "OFF"),
)
"""COLMAP's CMake options (the module docstring, "The configuration"); the CUDA architectures are the pin's."""
REQUIRED_DEFINITIONS = ("COLMAP_CUDA_ENABLED", "COLMAP_ONNX_ENABLED", "COLMAP_GPU_ENABLED")
FORBIDDEN_DEFINITIONS = (
    "COLMAP_SIFT_GPU_ENABLED",
    "COLMAP_LSD_ENABLED",
    "COLMAP_CGAL_ENABLED",
    "COLMAP_GUI_ENABLED",
    "COLMAP_OPENGL_ENABLED",
    "COLMAP_DOWNLOAD_ENABLED",
)
"""The build graph's compile definitions that must (not) be there; ``build.ninja`` holds every compile command."""
FORBIDDEN_TARGETS = ("colmap_sift_gpu", "colmap_lsd", "colmap_ui")
"""Libraries that must not be in the build graph: SiftGPU, LSD and the GUI."""
FORBIDDEN_LIBRARIES: tuple[tuple[str, str], ...] = (
    ("spqr*.dll", "SuiteSparseQR (GPL-2.0-or-later)"),
    ("gmp*.dll", "GMP (CGAL's)"),
    ("mpfr*.dll", "MPFR (CGAL's)"),
    ("*cgal*.dll", "CGAL (GPL-3.0)"),
    ("*siftgpu*.dll", "SiftGPU (non-commercial)"),
    ("*sift_gpu*.dll", "SiftGPU (non-commercial)"),
    ("*lsd*.dll", "LSD (AGPL-3.0)"),
    ("qt6*.dll", "Qt (the GUI is off)"),
    ("opengl32.dll", "OpenGL (the GUI is off)"),
    ("glew32.dll", "GLEW (SiftGPU's and the GUI's)"),
    ("libcurl*.dll", "curl (downloads are off)"),
    ("cudnn*.dll", "cuDNN (NVIDIA's licence; not shipped)"),
)
"""Shared libraries no file of the build may carry or import, with the reason."""
CHOLMOD_GPL_FUNCTION = re.compile(
    r"^cholmod_(?:l_)?(?:super_(?:lsolve|ltsolve|numeric|symbolic2?)|drop|horzcat|norm_dense|norm_sparse|scale"
    r"|sdmult|ssmult|submatrix|symmetry|vertcat|rowadd(?:_mark|_solve)?|rowdel(?:_mark|_solve)?"
    r"|updown(?:_mark|_mask2?|_solve)?|gpu_(?:allocate|deallocate|end|memorysize|probe|start))$"
)
"""CHOLMOD's functions of its GPL modules: what CHOLMOD 5.3.4's ``cholmod.h`` declares under ``NSUPERNODAL``,
``NMATRIXOPS``, ``NMODIFY`` and ``CHOLMOD_HAS_CUDA`` (the GPU module); none may be exported or imported.
``cholmod_gpu_stats`` is the Check module's (LGPL-2.1-or-later), a statistics printer every build has."""
SPQR_SYMBOL = re.compile(r"SuiteSparseQR|spqr_", re.IGNORECASE)
FORBIDDEN_PORTS = ("suitesparse-spqr", "cgal", "gmp", "mpfr", "qtbase", "curl")
CHOLMOD_GPL_FEATURES = ("matrixops", "modify", "supernodal", "cuda")


class BuildError(Exception):
    """A build that cannot go on; the message says why."""


@dataclass(frozen=True)
class Weight:
    """A model file of ``[tools.colmap-clean.weights.<name>]``: the ONNX file and its licence's text."""

    name: str
    file: str
    url: str
    sha256: str
    size_bytes: int
    licence: str
    licence_url: str
    licence_sha256: str


@dataclass(frozen=True)
class Pin:
    """``[tools.colmap-clean]`` of ``tools/pins.toml``."""

    version: str
    colmap_commit: str
    vcpkg_commit: str
    msvc: str
    cuda: str
    cuda_architectures: str
    install_dir: str
    executable: str
    weights: tuple[Weight, ...]
    manifest_sha256: str | None
    executable_sha256: str | None


@dataclass(frozen=True)
class Folders:
    """The cache folder's parts (short names: vcpkg's and CUDA's command lines grow with the paths)."""

    colmap: Path
    vcpkg: Path
    installed: Path
    buildtrees: Path
    packages: Path
    downloads: Path
    archives: Path
    registries: Path
    fetchcontent: Path
    build: Path
    install: Path
    stage: Path
    logs: Path

    @classmethod
    def under(cls, root: Path) -> Folders:
        return cls(
            colmap=root / "colmap",
            vcpkg=root / "vcpkg",
            installed=root / "installed",
            buildtrees=root / "bt",
            packages=root / "pk",
            downloads=root / "downloads",
            archives=root / "archives",
            registries=root / "registries",
            fetchcontent=root / "fc",
            build=root / "b",
            install=root / "install",
            stage=root / "stage",
            logs=root / "logs",
        )


def _text(table: Mapping[str, object], key: str, where: str) -> str:
    value = table.get(key)
    if not isinstance(value, str) or not value:
        raise BuildError(f"{where}: {key} must be a non-empty string")
    return value


def _optional_text(table: Mapping[str, object], key: str, where: str) -> str | None:
    return _text(table, key, where) if key in table else None


def read_pin(pins: Path = PINS) -> Pin:
    """The pin (:data:`PIN_TABLE` of ``pins``). ``BuildError`` names the first problem."""
    where = f"{pins}: [{'.'.join(PIN_TABLE)}]"
    try:
        table: object = tomllib.loads(pins.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise BuildError(f"{pins}: {error}") from error
    for key in PIN_TABLE:
        table = table.get(key) if isinstance(table, dict) else None
    if not isinstance(table, dict):
        raise BuildError(f"{where}: missing")
    weights_table = table.get("weights", {})
    if not isinstance(weights_table, dict) or not weights_table:
        raise BuildError(f"{where}: no [weights.<name>] table")
    weights = []
    for name, entry in sorted(weights_table.items()):
        if not isinstance(entry, dict):
            raise BuildError(f"{where}.weights.{name}: not a table")
        at = f"{where}.weights.{name}"
        size = entry.get("size_bytes")
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            raise BuildError(f"{at}: size_bytes must be a positive integer")
        keys = ("file", "url", "sha256", "licence", "licence_url", "licence_sha256")
        values = {key: _text(entry, key, at) for key in keys}
        weights.append(Weight(name=str(name), size_bytes=size, **values))
    return Pin(
        version=_text(table, "version", where),
        colmap_commit=_text(table, "colmap_commit", where),
        vcpkg_commit=_text(table, "vcpkg_commit", where),
        msvc=_text(table, "msvc", where),
        cuda=_text(table, "cuda", where),
        cuda_architectures=_text(table, "cuda_architectures", where),
        install_dir=_text(table, "install_dir", where),
        executable=_text(table, "executable", where),
        weights=tuple(weights),
        manifest_sha256=_optional_text(table, "manifest_sha256", where),
        executable_sha256=_optional_text(table, "executable_sha256", where),
    )


def run(
    command: Sequence[str] | str,
    *,
    log: Path | None = None,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
    timeout_s: float = STEP_TIMEOUT_S,
) -> str:
    """Runs a child process without a console window, below normal priority: its output goes to ``log`` (appended)
    when one is named, else it is returned. ``BuildError`` on a failure, naming the log."""
    shown = command if isinstance(command, str) else subprocess.list2cmdline(list(command))
    if log is not None:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a", encoding="utf-8", errors="replace") as stream:
            stream.write(f"\n$ {shown}\n")
            stream.flush()
            completed = subprocess.run(
                command,
                stdout=stream,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                cwd=cwd,
                env=None if env is None else dict(env),
                timeout=timeout_s,
                creationflags=NO_WINDOW,
                check=False,
            )
        if completed.returncode != 0:
            raise BuildError(f"{shown} failed ({completed.returncode}); its output: {log}")
        return ""
    captured = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdin=subprocess.DEVNULL,
        cwd=cwd,
        env=None if env is None else dict(env),
        timeout=timeout_s,
        creationflags=NO_WINDOW,
        check=False,
    )
    if captured.returncode != 0:
        raise BuildError(f"{shown} failed ({captured.returncode}):\n{captured.stdout}\n{captured.stderr}")
    return captured.stdout


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def patch_files(folder: Path = PATCHES_DIR) -> list[Path]:
    """The repository's patches of COLMAP, in the order they apply."""
    return sorted(folder.glob("*.patch"))


def patches_digest(patches: Sequence[Path]) -> str:
    """The sha256 over the patches' names and bytes (line ends as committed: ``.gitattributes`` keeps them LF)."""
    digest = hashlib.sha256()
    for patch in patches:
        name = patch.name.encode("utf-8")
        content = patch.read_bytes().replace(b"\r\n", b"\n")
        digest.update(len(name).to_bytes(8, "little") + name + len(content).to_bytes(8, "little") + content)
    return digest.hexdigest()


def checkout(url: str, commit: str, folder: Path, log: Path) -> None:
    """``folder`` holds ``url`` at ``commit``, fetched alone (no history), with line feeds as committed."""
    git = ["git", "-c", "core.autocrlf=false", "-C", str(folder)]
    if not (folder / ".git").is_dir():
        folder.mkdir(parents=True, exist_ok=True)
        run([*git, "init", "-q"], log=log)
        run([*git, "remote", "add", "origin", url], log=log)
    try:
        head = run([*git, "rev-parse", "--verify", "-q", "HEAD^{commit}"], timeout_s=60.0).strip()
    except BuildError:
        head = ""  # a fresh repository has no HEAD yet
    if head != commit:
        run([*git, "fetch", "-q", "--depth", "1", "origin", commit], log=log, timeout_s=GIT_TIMEOUT_S)
        run([*git, "checkout", "-q", "--force", commit], log=log)


def apply_patches(folder: Path, commit: str, patches: Sequence[Path], log: Path) -> str:
    """COLMAP's checkout at ``commit`` with ``patches`` applied; kept as it is when its stamp names both, so Ninja
    rebuilds nothing on a rerun. Returns the patches' digest."""
    digest = patches_digest(patches)
    stamp = folder / PATCH_STAMP
    wanted = f"{commit} {digest}\n"
    if stamp.is_file() and stamp.read_text(encoding="utf-8") == wanted:
        return digest
    git = ["git", "-c", "core.autocrlf=false", "-C", str(folder)]
    run([*git, "reset", "-q", "--hard", commit], log=log)
    run([*git, "clean", "-q", "-fdx"], log=log)
    for patch in patches:
        run([*git, "apply", "--whitespace=nowarn", str(patch)], log=log)
    stamp.write_text(wanted, encoding="utf-8")
    return digest


def find_visual_studio(msvc: str) -> Path:
    """The Visual Studio 2022 installation with the pinned toolset (``VC/Tools/MSVC/<msvc>``)."""
    vswhere = VSWHERE / "vswhere.exe"
    if not vswhere.is_file():
        raise BuildError(f"{vswhere}: not found; install Visual Studio 2022 with the C++ tools")
    listing = run([str(vswhere), "-all", "-products", "*", "-version", "[17.0,18.0)", "-property", "installationPath"])
    for line in listing.splitlines():
        root = Path(line.strip())
        if (root / "VC/Tools/MSVC" / msvc).is_dir() and (root / BUNDLED_CMAKE).is_file():
            return root
    raise BuildError(f"no Visual Studio 2022 with the toolset {msvc} and its CMake component")


def build_environment(visual_studio: Path, pin: Pin, folders: Folders, jobs: int) -> dict[str, str]:
    """The compiler's environment (``vcvars64.bat`` at the pinned toolset, read back through ``set``) with CUDA,
    vcpkg's folders and the bundled CMake and Ninja first on ``PATH``."""
    vcvars = visual_studio / VCVARS
    listing = run(f'cmd.exe /d /s /c ""{vcvars}" -vcvars_ver={pin.msvc} >nul 2>&1 && set"')
    environment = dict(os.environ)
    for line in listing.splitlines():
        name, sep, value = line.partition("=")
        if sep and name:
            environment[name] = value
    if environment.get("VCToolsVersion", "").strip() != pin.msvc:
        raise BuildError(f"{vcvars} set the toolset {environment.get('VCToolsVersion')!r}, the pin is {pin.msvc}")
    cuda = CUDA_ROOT / f"v{pin.cuda}"
    if not (cuda / "bin" / "nvcc.exe").is_file():
        raise BuildError(f"{cuda}: no CUDA {pin.cuda} toolkit")
    tools = [visual_studio / BUNDLED_CMAKE.parent, visual_studio / BUNDLED_NINJA.parent, cuda / "bin"]
    environment["PATH"] = os.pathsep.join([*map(str, tools), environment.get("PATH", "")])
    environment.update(
        {
            "CUDA_PATH": str(cuda),
            "VCPKG_ROOT": str(folders.vcpkg),
            "VCPKG_DISABLE_METRICS": "1",
            "VCPKG_DEFAULT_BINARY_CACHE": str(folders.archives),
            "X_VCPKG_REGISTRIES_CACHE": str(folders.registries),
            "VCPKG_DOWNLOADS": str(folders.downloads),
            "VCPKG_MAX_CONCURRENCY": str(jobs),
            "VCPKG_KEEP_ENV_VARS": "CUDA_PATH",
        }
    )
    return environment


def vcpkg_install(folders: Folders, environment: Mapping[str, str], log: Path) -> None:
    """vcpkg's libraries for COLMAP's manifest (the module docstring, "The libraries")."""
    vcpkg = folders.vcpkg / "vcpkg.exe"
    if not vcpkg.is_file():
        run(
            ["cmd.exe", "/d", "/c", str(folders.vcpkg / "bootstrap-vcpkg.bat"), "-disableMetrics"],
            log=log,
            env=environment,
        )
    for folder in (folders.archives, folders.registries, folders.downloads):
        folder.mkdir(parents=True, exist_ok=True)
    command = [
        str(vcpkg),
        "install",
        f"--x-manifest-root={folders.colmap}",
        f"--x-install-root={folders.installed}",
        f"--x-buildtrees-root={folders.buildtrees}",
        f"--x-packages-root={folders.packages}",
        f"--downloads-root={folders.downloads}",
        f"--overlay-ports={PORTS_DIR / 'ceres'}",
        f"--overlay-triplets={TRIPLETS_DIR}",
        f"--triplet={TRIPLET}",
        f"--host-triplet={TRIPLET}",
        "--x-no-default-features",
        "--x-feature=cuda",
        "--clean-buildtrees-after-build",
        "--clean-packages-after-build",
    ]
    run(command, log=log, env=environment, cwd=folders.colmap, timeout_s=VCPKG_TIMEOUT_S)


def cmake_options(pin: Pin, folders: Folders) -> list[str]:
    """COLMAP's configure line's ``-D`` options. ``CUDA::cudart``, which COLMAP links by name, is the static CUDA
    runtime, as in upstream's build: no NVIDIA library is shipped beside ``colmap.exe``."""
    cuda = CUDA_ROOT / f"v{pin.cuda}"
    options = [f"-D{name}={value}" for name, value in CONFIGURATION]
    options += [
        f"-DCMAKE_CUDA_ARCHITECTURES={pin.cuda_architectures}",
        f"-DCUDAToolkit_ROOT={cuda.as_posix()}",
        f"-DCUDA_cudart_LIBRARY={(cuda / 'lib/x64/cudart_static.lib').as_posix()}",
        f"-DCMAKE_TOOLCHAIN_FILE={(folders.vcpkg / 'scripts/buildsystems/vcpkg.cmake').as_posix()}",
        "-DVCPKG_MANIFEST_INSTALL=OFF",
        f"-DVCPKG_INSTALLED_DIR={folders.installed.as_posix()}",
        f"-DVCPKG_TARGET_TRIPLET={TRIPLET}",
        f"-DVCPKG_OVERLAY_TRIPLETS={TRIPLETS_DIR.as_posix()}",
        "-DVCPKG_APPLOCAL_DEPS=OFF",
        f"-DFETCHCONTENT_BASE_DIR={folders.fetchcontent.as_posix()}",
        f"-DCMAKE_INSTALL_PREFIX={folders.install.as_posix()}",
    ]
    return options


def build_colmap(pin: Pin, folders: Folders, environment: Mapping[str, str], jobs: int, log: Path) -> None:
    """Configures, builds and installs COLMAP into ``folders.install``."""
    cmake = "cmake.exe"
    configure = [
        cmake,
        "-S",
        str(folders.colmap),
        "-B",
        str(folders.build),
        "-G",
        "Ninja",
        *cmake_options(pin, folders),
    ]
    run(configure, log=log, env=environment, timeout_s=GIT_TIMEOUT_S)
    run(
        [cmake, "--build", str(folders.build), "--parallel", str(jobs)],
        log=log,
        env=environment,
        timeout_s=BUILD_TIMEOUT_S,
    )
    if folders.install.exists():
        shutil.rmtree(folders.install)
    run([cmake, "--install", str(folders.build)], log=log, env=environment)


# ---------------------------------------------------------------------------------------------- the import tables


def parse_dependents(text: str) -> list[str]:
    """The libraries of ``dumpbin /dependents`` output: the import and the delay-load dependencies, in order."""
    found: list[str] = []
    collecting = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.endswith("dependencies:"):
            collecting = True
            continue
        if collecting and stripped.lower().endswith(".dll"):
            found.append(stripped)
        elif collecting and stripped and stripped != "Summary":
            collecting = False
        elif stripped == "Summary":
            break
    return found


def parse_imports(text: str) -> dict[str, list[str]]:
    """The functions of ``dumpbin /imports`` output, by the library they come from (names; ``#<n>`` by ordinal)."""
    imports: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "Summary":
            break
        if line.startswith("    ") and not line.startswith("     ") and stripped.lower().endswith(".dll"):
            current = stripped
            imports.setdefault(current, [])
            continue
        if current is None or not stripped:
            continue
        by_name = re.match(r"^[0-9A-Fa-f]+\s+(\S+)$", stripped)
        by_ordinal = re.match(r"^Ordinal\s+(\d+)$", stripped)
        if by_ordinal:
            imports[current].append(f"#{by_ordinal.group(1)}")
        elif by_name and not stripped.endswith(("Table", "stamp", "reference")):
            imports[current].append(by_name.group(1))
    return imports


def parse_exports(text: str) -> list[str]:
    """The exported names of ``dumpbin /exports`` output."""
    names: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)", line)
        if match:
            names.append(match.group(1))
    return names


def is_system_library(name: str, system_dirs: Sequence[Path]) -> bool:
    """Windows' own libraries and the driver's (an API set, or a file of the system folders), which no build ships;
    the Visual C++ runtime among them, as upstream's build relies on it too."""
    lowered = name.lower()
    if lowered.startswith(("api-ms-win-", "ext-ms-")):
        return True
    return any((folder / name).is_file() for folder in system_dirs)


def library_closure(
    roots: Sequence[Path],
    search_dirs: Sequence[Path],
    dependents_of: Callable[[Path], list[str]],
    system: Callable[[str], bool],
) -> tuple[dict[str, Path], set[str]]:
    """The shared libraries ``roots`` load, found in ``search_dirs`` (in order) before the system's: those to ship, by
    lower-cased name, and the system's by name. ``BuildError`` names a library found nowhere."""
    shipped: dict[str, Path] = {}
    from_system: set[str] = set()
    pending = list(roots)
    seen: set[str] = {root.name.lower() for root in roots}
    while pending:
        current = pending.pop()
        for name in dependents_of(current):
            lowered = name.lower()
            if lowered in seen:
                continue
            seen.add(lowered)
            found = next((folder / name for folder in search_dirs if (folder / name).is_file()), None)
            if found is not None:
                shipped[lowered] = found
                pending.append(found)
            elif system(name):
                from_system.add(name)
            else:
                raise BuildError(f"{current.name} needs {name}, which is in none of {[str(d) for d in search_dirs]}")
    return shipped, from_system


# ---------------------------------------------------------------------------------------------- the licence proof


def forbidden_library(name: str) -> str | None:
    """The reason ``name`` may not be shipped or imported (:data:`FORBIDDEN_LIBRARIES`), or None."""
    lowered = name.lower()
    return next((reason for pattern, reason in FORBIDDEN_LIBRARIES if fnmatch.fnmatch(lowered, pattern)), None)


def read_installed_ports(status: Path) -> dict[str, set[str]]:
    """vcpkg's installed packages (``installed/vcpkg/status``), by port, with their features (``core`` included)."""
    return parse_status(status.read_text(encoding="utf-8"))


def parse_status(text: str) -> dict[str, set[str]]:
    """The installed packages of vcpkg's status file (stanzas of ``Key: value`` lines), with their features."""
    ports: dict[str, set[str]] = {}
    for stanza in re.split(r"\n\s*\n", text):
        fields = {
            key.strip(): value.strip()
            for key, sep, value in (line.partition(":") for line in stanza.splitlines())
            if sep
        }
        if "Package" in fields and fields.get("Status") == "install ok installed":
            ports.setdefault(fields["Package"], set()).add(fields.get("Feature", "core"))
    return ports


def licence_findings(
    files: Mapping[str, Mapping[str, list[str]]],
    exports: Mapping[str, list[str]],
    ports: Mapping[str, set[str]],
    build_graph: str,
) -> list[str]:
    """Every finding against the build (none for a clean one): ``files`` the import tables of each shipped file by
    its name, ``exports`` the export tables of the libraries named there, ``ports`` vcpkg's installed packages and
    ``build_graph`` COLMAP's ``build.ninja``."""
    findings: list[str] = []
    for name, imports in sorted(files.items()):
        reason = forbidden_library(name)
        if reason:
            findings.append(f"{name} is shipped: {reason}")
        for library, functions in sorted(imports.items()):
            reason = forbidden_library(library)
            if reason:
                findings.append(f"{name} imports {library}: {reason}")
            for function in functions:
                if CHOLMOD_GPL_FUNCTION.match(function) or SPQR_SYMBOL.search(function):
                    findings.append(f"{name} imports {function} from {library}: a GPL module's function")
    for library, names in sorted(exports.items()):
        findings += [f"{library} exports {f}: a GPL module's function" for f in names if CHOLMOD_GPL_FUNCTION.match(f)]
    for port in FORBIDDEN_PORTS:
        if port in ports:
            findings.append(f"vcpkg installed {port}")
    for feature in sorted(ports.get("suitesparse-cholmod", set()) & set(CHOLMOD_GPL_FEATURES)):
        findings.append(f"vcpkg installed suitesparse-cholmod[{feature}] (GPL-2.0-or-later)")
    for definition in REQUIRED_DEFINITIONS:
        if f"-D{definition}" not in build_graph:
            findings.append(f"the build graph lacks {definition}")
    for definition in FORBIDDEN_DEFINITIONS:
        if re.search(rf"-D{definition}\b", build_graph):
            findings.append(f"the build graph defines {definition}")
    for target in FORBIDDEN_TARGETS:
        if re.search(rf"\b{target}\.lib\b", build_graph):
            findings.append(f"the build graph links {target}")
    return findings


def licence_proof(
    stage: Path,
    dumpbin: Callable[[str, Path], str],
    ports: Mapping[str, set[str]],
    build_graph: str,
    system_libraries: Iterable[str],
) -> dict[str, object]:
    """The proof document (the module docstring, "The layout"): each shipped file's import table, CHOLMOD's export
    table, vcpkg's packages, the system's libraries and the findings."""
    files: dict[str, dict[str, list[str]]] = {}
    for path in sorted(stage.rglob("*")):
        if path.suffix.lower() in (".exe", ".dll"):
            files[path.name] = parse_imports(dumpbin("/imports", path))
    exports = {path.name: parse_exports(dumpbin("/exports", path)) for path in sorted(stage.rglob("cholmod*.dll"))}
    findings = licence_findings(files, exports, ports, build_graph)
    return {
        "imports": {name: {lib: sorted(set(fns)) for lib, fns in sorted(imp.items())} for name, imp in files.items()},
        "cholmod_exports": {name: sorted(names) for name, names in exports.items()},
        "vcpkg_ports": {port: sorted(features) for port, features in sorted(ports.items())},
        "system_libraries": sorted(set(system_libraries), key=str.lower),
        "build_graph": {
            "defines": [d for d in (*REQUIRED_DEFINITIONS, *FORBIDDEN_DEFINITIONS) if f"-D{d}" in build_graph],
            "forbidden_targets": [t for t in FORBIDDEN_TARGETS if re.search(rf"\b{t}\.lib\b", build_graph)],
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------------------------- the layout


def fetch_file(url: str, sha256: str, size_bytes: int | None, target: Path) -> Path:
    """``target``, downloaded once and checked by its size and sha256 (a mismatch is deleted and fails)."""
    if target.is_file() and sha256_of(target) == sha256:
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    part = target.with_name(target.name + ".part")
    with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT_S) as response, part.open("wb") as stream:
        shutil.copyfileobj(response, stream, 1 << 20)
    size = part.stat().st_size
    found = sha256_of(part)
    if found != sha256 or (size_bytes is not None and size != size_bytes):
        part.unlink()
        raise BuildError(f"{url}: {size} bytes, sha256 {found}; the pin says {size_bytes} bytes, {sha256}")
    part.replace(target)
    return target


def file_manifest(folder: Path) -> dict[str, str]:
    """Every file below ``folder`` but the manifest, by its path with ``/``, and its sha256."""
    return {
        path.relative_to(folder).as_posix(): sha256_of(path)
        for path in sorted(folder.rglob("*"))
        if path.is_file() and path.name != MANIFEST_NAME
    }


def manifest_document(pin: Pin, patches: str, files: Mapping[str, str]) -> dict[str, object]:
    """``manifest.json``: what the folder was built from and every file of it. No time and no path, so the same
    files make the same bytes."""
    return {
        "name": PIN_TABLE[1],
        "colmap": {"version": pin.version, "commit": pin.colmap_commit},
        "vcpkg_commit": pin.vcpkg_commit,
        "msvc": pin.msvc,
        "cuda": pin.cuda,
        "cuda_architectures": pin.cuda_architectures,
        "patches_sha256": patches,
        "configuration": dict(CONFIGURATION),
        "files": dict(sorted(files.items())),
    }


def port_of_files(info: Path) -> dict[str, str]:
    """The port that installed each file of the triplet's ``bin/``, from vcpkg's lists (``installed/vcpkg/info``)."""
    owners: dict[str, str] = {}
    for listing in sorted(info.glob(f"*_{TRIPLET}.list")):
        port = listing.name.split("_", 1)[0]
        for line in listing.read_text(encoding="utf-8").splitlines():
            if line.lower().startswith(f"{TRIPLET}/bin/".lower()):
                owners[line.rsplit("/", 1)[1].lower()] = port
    return owners


def copy_licences(folders: Folders, shipped: Mapping[str, Path], pin: Pin, target: Path) -> None:
    """``licences/``: the copyright file of every port vcpkg installed (the shipped libraries' and the header-only
    ones compiled in: Eigen, Boost's headers), COLMAP's, the sources built into it (VLFeat, PoissonRecon, PoseLib,
    faiss), ONNX Runtime's with its notices, and the models'. A shipped library of vcpkg's without its port's
    copyright file fails."""
    target.mkdir(parents=True, exist_ok=True)
    owners = port_of_files(folders.installed / "vcpkg" / "info")
    share = folders.installed / TRIPLET / "share"
    for name, source in sorted(shipped.items()):
        if source.parent == folders.install / "bin":
            continue  # COLMAP's install: ONNX Runtime's, below
        port = owners.get(name)
        if port is None or not (share / port / "copyright").is_file():
            raise BuildError(f"{name}: no vcpkg port's copyright file names it")
    for copyright_file in sorted(share.glob("*/copyright")):
        shutil.copyfile(copyright_file, target / f"{copyright_file.parent.name}.txt")
    fixed = {
        "colmap.txt": folders.colmap / "COPYING.txt",
        "vlfeat.txt": folders.colmap / "src/thirdparty/VLFeat/LICENSE",
        "poissonrecon.txt": folders.colmap / "src/thirdparty/PoissonRecon/LICENSE",
        "poselib.txt": folders.fetchcontent / "poselib-src/LICENSE",
        "faiss.txt": folders.fetchcontent / "faiss-src/LICENSE",
        "onnxruntime.txt": folders.fetchcontent / "onnxruntime-src/LICENSE",
        "onnxruntime-third-party-notices.txt": folders.fetchcontent / "onnxruntime-src/ThirdPartyNotices.txt",
    }
    for name, source in fixed.items():
        if not source.is_file():
            raise BuildError(f"{source}: the licence of a part of the build is missing")
        shutil.copyfile(source, target / name)
    for weight in pin.weights:
        licence = folders.downloads / "weights" / weight.licence_sha256 / "LICENSE"
        fetch_file(weight.licence_url, weight.licence_sha256, None, licence)
        shutil.copyfile(licence, target / f"model-{weight.name}.txt")


def lay_out(pin: Pin, folders: Folders, dumpbin_exe: Path, patches: str, dest: Path) -> tuple[Path, dict[str, object]]:
    """Stages the folder (the module docstring, "The layout"), proves it and moves it to ``dest/<install_dir>``.
    Returns the folder and its proof."""
    stage = folders.stage / pin.install_dir
    if stage.exists():
        shutil.rmtree(stage)
    (stage / "bin").mkdir(parents=True)
    installed_bin = folders.install / "bin"
    executable = stage / pin.executable
    shutil.copyfile(installed_bin / Path(pin.executable).name, executable)

    def dumpbin(option: str, path: Path) -> str:
        return run([str(dumpbin_exe), "/nologo", option, str(path)])

    system_dirs = [Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"]
    shipped, from_system = library_closure(
        [installed_bin / Path(pin.executable).name],
        [installed_bin, folders.installed / TRIPLET / "bin"],
        lambda path: parse_dependents(dumpbin("/dependents", path)),
        lambda name: is_system_library(name, system_dirs),
    )
    for source in shipped.values():
        shutil.copyfile(source, stage / "bin" / source.name)
    models = stage / "models"
    for weight in pin.weights:
        cached = folders.downloads / "weights" / weight.sha256 / weight.file
        fetch_file(weight.url, weight.sha256, weight.size_bytes, cached)
        models.mkdir(exist_ok=True)
        shutil.copyfile(cached, models / weight.file)
    copy_licences(folders, shipped, pin, stage / "licences")
    ports = read_installed_ports(folders.installed / "vcpkg" / "status")
    build_graph = (folders.build / "build.ninja").read_text(encoding="utf-8", errors="replace")
    proof = licence_proof(stage, dumpbin, ports, build_graph, from_system)
    (stage / PROOF_NAME).write_text(json.dumps(proof, indent=1) + "\n", encoding="utf-8", newline="\n")
    if proof["findings"]:
        raise BuildError(f"the licence proof found: {proof['findings']} ({stage / PROOF_NAME})")
    manifest = manifest_document(pin, patches, file_manifest(stage))
    (stage / MANIFEST_NAME).write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8", newline="\n")
    final = dest / pin.install_dir
    if final.exists():
        shutil.rmtree(final)
    final.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(stage, final)
    return final, proof


def compare_with_pin(folder: Path, pin: Pin) -> list[str]:
    """The lines to print: the folder's digests against the pin's, and the lines the pin needs when they differ."""
    manifest = sha256_of(folder / MANIFEST_NAME)
    executable = sha256_of(folder / pin.executable)
    lines = [f"manifest sha256 {manifest}", f"executable sha256 {executable}"]
    if (pin.manifest_sha256, pin.executable_sha256) == (manifest, executable):
        return [*lines, "matches its pin"]
    table = ".".join(PIN_TABLE)
    return [
        *lines,
        f"differs from its pin: to make this the build of record, set in [{table}] of tools/pins.toml",
        f'manifest_sha256 = "{manifest}"',
        f'executable_sha256 = "{executable}"',
    ]


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE, help="the sources and the build (short path)")
    parser.add_argument("--dest", type=Path, default=DEFAULT_DEST, help="the tools folder the build is laid out in")
    parser.add_argument("--jobs", type=int, default=16, help="parallel compile jobs (vcpkg's and Ninja's)")
    return parser.parse_args(argv)


class Steps:
    """Times each step of the build, printing its name before and its duration after."""

    def __init__(self) -> None:
        self.times: list[tuple[str, float]] = []

    def run(self, name: str, action: Callable[[], T]) -> T:
        started = time.perf_counter()
        print(f"{name} ...", flush=True)
        result = action()
        self.times.append((name, time.perf_counter() - started))
        print(f"{name}: {self.times[-1][1]:.0f} s", flush=True)
        return result


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    folders = Folders.under(args.cache.resolve())
    log = folders.logs / "build_colmap.log"
    steps = Steps()
    try:
        pin = read_pin()
        visual_studio = find_visual_studio(pin.msvc)
        environment = build_environment(visual_studio, pin, folders, args.jobs)
        steps.run("checkout colmap", lambda: checkout(COLMAP_URL, pin.colmap_commit, folders.colmap, log))
        steps.run("checkout vcpkg", lambda: checkout(VCPKG_URL, pin.vcpkg_commit, folders.vcpkg, log))
        patches = steps.run("patches", lambda: apply_patches(folders.colmap, pin.colmap_commit, patch_files(), log))
        steps.run("vcpkg", lambda: vcpkg_install(folders, environment, folders.logs / "vcpkg.log"))
        steps.run("colmap", lambda: build_colmap(pin, folders, environment, args.jobs, folders.logs / "colmap.log"))
        dumpbin_exe = Path(environment["VCToolsInstallDir"]) / "bin/Hostx64/x64/dumpbin.exe"
        folder, _proof = steps.run("layout", lambda: lay_out(pin, folders, dumpbin_exe, patches, args.dest.resolve()))
        print(folder)
        for line in compare_with_pin(folder, pin):
            print(line)
        print("times: " + ", ".join(f"{name} {seconds:.0f} s" for name, seconds in steps.times))
    except BuildError as error:
        print(f"build_colmap: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
