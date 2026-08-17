# Phase 1 — reproducible legacy build

## Status

Blocked at the Phase 1A local-only dependency gate. No dependency was downloaded, substituted, registered, or removed.

The managed build can be evaluated by the .NET 4.x MSBuild host using the 3.5 toolset, but this machine does not currently contain all historical build inputs. A faithful build must retain the existing DirectDraw and DirectAudio behavior during Phase 1; introducing an audio stub or managed renderer here would violate phase isolation.

## Diagnostic build findings

### MSBuild hosts

- `C:\Windows\Microsoft.NET\Framework\v3.5\MSBuild.exe` exists but fails before project evaluation with MSB4141 because the machine has an invalid MSBuild ToolsVersion 14.0 registry entry with no `MSBuildToolsPath`.
- `C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe` can evaluate the projects with `/toolsversion:3.5`.
- The .NET 2.0 MSBuild host can start. Its `GetFrameworkPaths` target reports a missing .NET Framework 2.0 SDK, but the target succeeds and no FreeTrain build target consumes the resulting SDK-directory property. Direct project invocation still cannot reproduce solution-relative post-build behavior by itself.

The repository must not repair machine-wide registry state. The build wrapper should select a working host explicitly.

The standalone .NET Framework 2.0 SDK has been removed from the blocker list. `phase1a-dependency-classification.md` records the exact task/target/property trace and proves that COM-wrapper generation uses the in-process `TypeLibConverter` rather than SDK `TlbImp.exe`.

### DirectX 7 rendering type library

- Required type-library GUID: `{E1211242-8E94-11D1-8808-00C04FC2C602}`
- Not registered on the current machine
- Local source exists at `FreeTrain/extlib/dx7vb.dll`
- File identifies itself as Microsoft DirectX for Visual Basic, version 5.1.2600.0
- Local .NET SDK `TlbImp.exe` successfully generated a 200,704-byte interop assembly in a disposable probe
- The generated wrapper includes `DxVBLib.DirectX7Class` and does not include `DirectX8Class`

This dependency can be made build-reproducible from the locally preserved DLL. Runtime activation/registration remains a separate legacy-environment requirement.

### DirectX 8 audio type library

- Required type-library GUID: `{E1211242-8E94-11D1-8808-00C04FC2C603}`
- Expected namespace: `DxVBLibA`
- Not registered on the current machine
- No `dx8vb.dll` or pre-generated `Interop.DxVBLibA.dll` is present in the supplied snapshot
- The preserved `dx7vb.dll` cannot supply `DirectX8Class` or the DirectMusic 8 interfaces used by `DirectAudio.net`

This is the primary local-only managed-build blocker. Do not work around it by disabling audio; Phase 1 must reproduce the legacy build before Phase 5 replaces audio.

### DirectShow audio type library

The system `Quartz` type library is registered and `quartz.dll` exists in both 32-bit and 64-bit Windows system directories. It is not the current primary blocker.

### Native alpha component

- Native source and VS2005-era ATL projects are present.
- Prebuilt Debug and Release copies of `DirectDraw.AlphaBlend.dll` are present.
- A pre-generated `Interop.DirectDrawAlphaBlendLib.dll` is present.
- The COM class is not registered on this machine.
- The driver registers the DLL in process immediately before starting the game.

The two checked copies are byte-identical, pinned by SHA-256, structurally match the checked IDL/interop assembly, load on the current machine in a 32-bit process, and can create `IAlphaBlender` through their own class factory without registration. The preserved binary is therefore accepted for the Phase 1 runnable-preservation baseline. Building it from source remains a separate possible later gate, not a Phase 1 blocker.

## Diagnostic-process correction

The first probes were mistakenly run in parallel against shared `obj` directories. That created a PDB file-lock error unrelated to source correctness. The generated directories were verified as untracked and removed. All future legacy builds must run serially or use project-isolated intermediate directories.

## Current blockers

| Blocker | Required resolution |
|---|---|
| Missing `DxVBLibA` type-library source or generated interop assembly | Supply a provenance-known local DirectX 8 Visual Basic type library/runtime input; do not fetch an unverified binary |
| MSBuild 3.5 host broken by machine registry | Use an explicit working host with the 3.5 toolset; do not modify global registry as part of the repository |
| `FreeTrain.Controls` depends on checked-in `MsHtmlHost.dll` through historical user-specific reference paths | Make the existing binary a repository-local build reference in Phase 1B without refactoring the control |
| No save/screenshot/runtime fixtures | Collect outside the source tree before behavioral replacement phases |

## Phase 1 implementation order

1. Obtain or identify the missing local DirectX 8 audio type-library input with provenance.
2. Generate DirectX 7/8 and Quartz interop assemblies deterministically into `.artifacts`.
3. Build managed projects serially with an explicitly selected MSBuild host/toolset.
4. Copy the pinned native-alpha binary into the package and verify its x86 registration/activation path in a controlled legacy runtime environment.
5. Build `Driver` as `FreeTrain.exe` and package resources without using the interactive `pause` path.
6. Validate output architecture, assembly identities, resource layout, and plugin loading.
7. Run a smoke test only in an environment capable of activating the legacy COM components.

## Gate

Phase 1 remains incomplete until a clean environment can produce a packaged `FreeTrain.exe` with one documented command and without silently changing renderer, audio, plugin, or save behavior.
