# Phase 1 — reproducible legacy build

## Status

The Phase 1 no-registration build and packaging gate is now passed. A complete x86 Debug preservation package was produced from all 33 C# projects in `FreeTrain_VS2008.sln` using the externally supplied, Microsoft-catalog-verified `dx8vb.dll` as a build-time typelib input. See `phase1-build-report.md` for commands, hashes, error classification, and the remaining runtime-validation boundary.

The build retains the existing DirectDraw and DirectAudio behavior. No audio stub, renderer substitution, C# source modernization, COM registration, or machine registry repair was used.

The historically distributed Video Recorder plug-in is an auxiliary preservation build, not part of the 33-project primary solution gate. Its source and declared DirectShow/type-library toolchain remain preserved, but reconstructing that provenance-sensitive toolchain is non-blocking for the core build and subsequent modernization phases. The supplied official VCR binaries remain reference oracles only and must not be copied into reconstructed packages as substitutes for rebuilding them.

## Diagnostic build findings

### MSBuild hosts

- `C:\Windows\Microsoft.NET\Framework\v3.5\MSBuild.exe` and `C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe` are both currently usable; the preflight selects the native 3.5 host first.
- The original Phase 1 diagnostic run encountered MSB4141 because a stale machine-wide ToolsVersion 14.0 registry entry had no `MSBuildToolsPath`. That external registry entry has since been removed, and `FreeTrain_VS2008.sln` now passes `ValidateSolutionConfiguration` under the 3.5 host. The original error remains recorded in `phase1-build-report.md` as historical build evidence.
- The .NET 2.0 MSBuild host can start. Its `GetFrameworkPaths` target reports a missing .NET Framework 2.0 SDK, but the target succeeds and no FreeTrain build target consumes the resulting SDK-directory property. Direct project invocation still cannot reproduce solution-relative post-build behavior by itself.

The repository does not edit machine-wide registry state. The build wrapper probes the available classic hosts and selects a working host explicitly.

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
- The external `dx8vb.zip` supplies a Microsoft XP SP3 `dx8vb.dll` with SHA-256 `19149F082F3CA68AA893ADAF0309E5E6C8EA8710C0FE2040F95E8DA5A329F846`
- The DLL verifies against the Microsoft-signed XP SP3 catalogs and is byte-identical to the ISO copy
- The build wrapper stages it only under ignored `.artifacts`, without COM registration
- Deterministic conversion produces `Interop.DxVBLibA.dll` with SHA-256 `52CED6F07AAC1DBFE074BE8BEB6B3C80446D1C7036738A26B1BBC47F4B308496`
- The preserved `dx7vb.dll` cannot supply `DirectX8Class` or the DirectMusic 8 interfaces used by `DirectAudio.net`

This blocker is resolved without disabling audio. The original DLL remains an external prerequisite and is neither tracked nor included in the application package.

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

## Remaining runtime-validation boundary

| Blocker | Required resolution |
|---|---|
| DirectX 7/8 runtime COM activation and the driver's native-alpha registration path | Smoke-test the generated package only in a controlled compatible x86 runtime environment; do not mutate this Windows 11 host. |
| No save/screenshot/runtime fixtures | Collect outside the source tree before behavioral replacement phases. |

The VM-only execution, registration, smoke-test, and fixture-capture procedure is specified in `phase1d-runtime-validation.md`.

## Phase 1 implementation order

1. Completed: identify and authenticate the external DirectX 8 audio type-library input.
2. Completed: generate DirectX 7/8 and Quartz interop assemblies deterministically into `.artifacts`.
3. Completed: build all solution projects serially with an explicitly selected MSBuild host/toolset.
4. Completed for packaging: copy and re-verify the pinned native-alpha binary.
5. Completed: build `Driver` as `FreeTrain.exe` and package resources without the interactive `pause` path.
6. Completed for the build gate: validate architecture, assembly identities, required resource layout, and compiled plugin outputs.
7. Pending external environment: run a smoke test where the legacy COM components can be activated safely.

## Gate

The reproducible core build/package gate is passed: one documented command produces a packaged x86 `FreeTrain.exe` without changing renderer, audio, plugin, or save behavior. VCR auxiliary-toolchain reconstruction is an independent preservation workstream and does not reopen this gate. Live execution remains isolated from the Windows 11 host because host execution would cross the no-registration boundary.
