# The triplet of scAnt's COLMAP build (tools/build_colmap.py): vcpkg's x64-windows-release (shared libraries, the
# shared C runtime, release only) on the pinned compiler; the CUDA toolkit is named by CUDA_PATH.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_BUILD_TYPE release)
set(VCPKG_PLATFORM_TOOLSET v143)
set(VCPKG_PLATFORM_TOOLSET_VERSION 14.44)
set(VCPKG_ENV_PASSTHROUGH CUDA_PATH)
