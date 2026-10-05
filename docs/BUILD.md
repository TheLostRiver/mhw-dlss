# Build and provenance

## Experimental Native No AA

`src/native/` and `patches/native-no-aa.patch` add a DX12 native-copy backend, a version-checked MHWSS projection-jitter hook, menu selection and FG shutdown handling to the pinned MHWFG tree below. Build using `scripts/Build-MHWNoAA.ps1`; usage, validation limits and rollback are in [NO-AA.md](NO-AA.md). The experimental DLL is separate from the default runtime.

## MHWFG

- Upstream integration tree: https://github.com/inhm112/MHW-DLSSFrameGen
- Tested commit: `a0421ee` (`checkpoint-20260910-before-latency`)
- Configuration: `Release|x64`, `MHWFGProduction=true`
- The local build required the DirectX headers included under `external/FidelityFX-SDK/framework/cauldron/framework/libs/dxheaders/include/directx` because the installed Windows SDK did not expose the D3D12 1.2 declarations used by the tree.
- The resulting DLL is copied as `d3d12.dll`.

## SM86 frame generation

- Source/package: https://github.com/sdli1995/dlssg_for_sm86
- Tested package: 0.3.5, `version.dll`
- `MaxGeneratedFrames=5` exposes up to six total frames when Streamline/game support it.
- `Optimized=1` is the exact-output optimization tier used in the tested configuration.

## Runtime files

The `runtime/` directory contains the files used by the tested package. `MHWSS.dll` and `MHWSSLauncher.exe` are intentionally absent and must be obtained separately. Keep the notices under `docs/licenses/` with any redistribution that is legally permitted for the runtime files.
