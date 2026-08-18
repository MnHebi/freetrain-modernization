# Phase 1A — legacy dependency classification

## Status and stop point

Phase 1A began as an archaeological classification pass. No game source, COM registration, machine registry value, SDK, or runtime was changed, and no dependency was downloaded or installed. A later user-supplied XP SP3 media copy satisfied the single unresolved input gate; the subsequent build integration is recorded in `phase1-build-report.md`.

The runnable-preservation baseline is the historical x86 `FreeTrain.exe` host, its managed core libraries, the 22 plugin projects in `FreeTrain_VS2008.sln`, and the packaged resources under `core/res`, `plugins`, and `doc`. The VCR plug-in was historically distributed but is runtime-optional and built through a separate managed/native toolchain; reconstructing that auxiliary toolchain is outside and non-blocking for this gate. NeoFT, experiments, report generation, and developer utilities are likewise outside the gate.

The result is:

- `DxVBLibA` was the one unmet critical binary prerequisite. It is now satisfied by an external, ignored, Microsoft-catalog-verified `dx8vb.dll`; it remains outside Git.
- The missing `.NET Framework SDKInstallRootv2.0` registry value is not a build blocker for this tree. It produces an informational `GetFrameworkSdkPath` message under MSBuild 2.0, but no repository target consumes the resulting property.
- The checked-in `DirectDraw.AlphaBlend.dll` is acceptable as a pinned preservation-baseline binary. Rebuilding it is not required to start the managed legacy baseline.

## Classification rules

| Classification | Meaning in Phase 1A |
|---|---|
| Source-build-required | FreeTrain-owned code that must be compiled from the preserved source for the baseline. A checked-in output cannot replace this build. |
| Acceptable verified binary prerequisite | External, framework, operating-system, or preserved native code that may remain binary for the baseline after identity, architecture, and integrity are recorded. |
| Generation-only tool dependency | Used only to produce a build artifact; it must not become a runtime prerequisite. |
| Noncritical | Outside the runnable-preservation baseline. Preserve it, but do not let it block the baseline. |

## Source-build-required

| Dependency or component | Evidence and Phase 1A disposition |
|---|---|
| `tools/Driver` | Builds the historical x86 `FreeTrain.exe` host and starts `MainWindow`. It must be compiled from source. |
| `core/FreeTrain.Core` | Main game and plugin contract assembly. It is intentionally a library and must be compiled from source without changing its identity. |
| `lib/Controls`, `lib/DirectDraw.net`, and `lib/DirectAudio.net` | FreeTrain-owned managed libraries. All must be compiled from source. The renderer and audio implementations remain unchanged in Phase 1. |
| 22 C# plugin projects in `FreeTrain_VS2008.sln` | These are the solution's standard compiled plugin set and must be built from source. |
| Data-only plugins and `core/res`, `plugins`, and `doc` package content | These are preserved source/package inputs. Phase 1 must reproduce their output layout rather than treating an old `bin` tree as the product. |
| Classic C# build logic | Use the repository's MSBuild 3.5 project definitions with their default `TargetFrameworkVersion` of `v2.0`. A working MSBuild host may be newer than 2.0, but the 3.5 toolset and 2.0 target contract remain fixed for the preservation build. |

`FreeTrain.Controls.csproj` has a historical wiring defect rather than a missing dependency: `src/DocHostUIHandlerImpl.cs` uses `MsHtmlHost`, the binary is checked into `extlib`, and `FreeTrain.Controls.csproj.user` records old absolute `ReferencePath` entries to `extlib`, but the project has no explicit `MsHtmlHost` reference. Phase 1B must make that reference repository-local without refactoring the control.

## Acceptable verified binary prerequisites

### Critical framework, COM, and operating-system prerequisites

| Prerequisite | Local evidence | Status |
|---|---|---|
| .NET Framework 2.0 runtime/reference assemblies | Projects omit `TargetFrameworkVersion`; both the 2.0 and 3.5 `Microsoft.Common.targets` default it to `v2.0`. The local 2.0 compiler and framework assemblies are present. | Accepted OS/framework prerequisite. This does not imply a requirement for the standalone .NET 2.0 SDK. |
| Native MSBuild 3.5 host, with MSBuild 4.x as fallback | Both hosts now evaluate successfully. The stale ToolsVersion 14.0 registry entry that originally caused MSB4141 has been removed outside the repository; the preflight selects `Framework\v3.5\MSBuild.exe`, and the solution passes `ValidateSolutionConfiguration`. | Accepted build-host prerequisite for Phase 1. Repository tooling probes but never modifies machine registry state. |
| `dx7vb.dll` / `DxVBLib` | Checked-in Microsoft binary, 597,504 bytes, file version `5.1.2600.0`, SHA-256 `D69CDC170AAC0AE611ECA3BEE84E7BE346A3BA1B3C79216E13E87C8EE6CD2084`. A disposable local probe generated `Interop.DxVBLib.dll` and confirmed `DxVBLib.DirectX7Class`. | Accepted pinned binary/type-library input. Runtime activation or registration remains an environment prerequisite. |
| `DxVBLibA` DirectX 8 VB audio type library/runtime | Required type-library GUID `{E1211242-8E94-11D1-8808-00C04FC2C603}`, version 1.0, LCID 0. The external candidate is byte-identical to the supplied XP SP3 ISO copy and verifies against Microsoft-signed `SP3.CAT` and `NT5.CAT`. | Accepted external binary/type-library input. SHA-256 `19149F082F3CA68AA893ADAF0309E5E6C8EA8710C0FE2040F95E8DA5A329F846`; never tracked or globally registered. |
| `QuartzTypeLib` / DirectShow | Required GUID `{56A868B0-0AD4-11CE-B03A-0020AF0BA770}`, version 1.0, LCID 0. The type library is registered locally and `quartz.dll` is present in the Windows system directories. | Accepted Windows COM prerequisite. |
| Windows APIs used by the native alpha DLL | Its import table contains only `KERNEL32`, `USER32`, `ADVAPI32`, `ole32`, `OLEAUT32`, and `SHLWAPI`; it has no separate Visual C++ runtime import. | Accepted operating-system prerequisite. |
| `xcopy.exe` | The historical `copyresources.bat` uses it to construct the package and it is present as a Windows component. | Accepted for the preservation build; Phase 1B may wrap the copy operation noninteractively without changing package contents. |

### Checked-in managed and native binaries

| Binary | Identity and SHA-256 | Baseline role |
|---|---|---|
| `extlib/MagicLibrary.DLL` | `MagicLibrary, Version=1.7.4.0`; `1E2320AD596B1E2AB0600DE07691289B361E48BD9A2ACBBF375FD58EF0D9569E` | Critical UI prerequisite. Preserve unchanged; licensing remains an explicit later audit. |
| `extlib/SharpZipLib.dll` | `SharpZipLib, Version=0.5.0.0`; `BD895385DBF9C920D1DE1B5956ED4F677F1BDEAEC75259232518FF25CDFD38D6` | Critical save/package compatibility prerequisite. |
| `extlib/MsHtmlHost.dll` | `MsHtmlHost, Version=0.0.0.0`; `736848E24F43BC0D6CE5AEEB71FEDB640B2964748987A73955B0E4CDEA5DA82C` | Critical `FreeTrain.Controls` compile/runtime prerequisite; Phase 1 now wires it through a repository-local reference without changing control source. |
| `extlib/SHDocVw.dll` | `SHDocVw, Version=1.1.0.0`; `E58C08E7E8BF6C5CEA961622346785DC2EFB1A47DB033096C56FE65852E6D99A` | Explicit `FreeTrain.Core` reference. No source call was found, but it remains a compile input until a later cleanup phase proves removal safe. |
| `lib/DirectDraw.net/Interop.DirectDrawAlphaBlendLib.DLL` | `Interop.DirectDrawAlphaBlendLib, Version=1.0.0.0`; `8AED64C6D01444B95B419E544A01E7BD667D541B3715067D232C52ED5BA466B6` | Critical checked-in interop assembly. It references `Interop.DxVBLib, Version=1.0.0.0`. |
| `bin/Debug/DirectDraw.AlphaBlend.dll` and `bin/Release/DirectDraw.AlphaBlend.dll` | Both are the same 401,408-byte Win32 binary with SHA-256 `B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D`. | Accepted pinned native preservation binary; detailed verification follows. |
| `Microsoft.JScript`, `Microsoft.Vsa`, and standard `System.*` references | Framework assemblies resolved from the 2.0 target framework. No FreeTrain source use of JScript or VSA was found, but both are explicit project references. | Accepted framework prerequisites until Phase 8 removes demonstrably stale references. |

The managed files above and the alpha DLL are not Authenticode-signed in this snapshot. Their acceptance is based on immutable-snapshot membership, recorded hashes, assembly/type-library identity, and local structural checks, not on publisher signatures.

## DxVBLibA provenance and exact expected contract

### What the repository proves

`DirectAudio.net.csproj` contains this COM identity:

- item name and expected type-library name: `DxVBLibA`
- GUID: `{E1211242-8E94-11D1-8808-00C04FC2C603}`
- version: 1.0
- LCID: 0
- wrapper selection: `tlbimp`

MSBuild's wrapper naming rule is `Interop.<type-library-name>.dll`, so the expected compile artifact is `Interop.DxVBLibA.dll`, with source namespace `DxVBLibA`. `AssemblyInfo.cs` describes `DirectAudio.net` as a “DirectMusic/DirectSound/DirectShow wrapper for .NET.” The required GUID differs only in its final digit from the checked-in DirectX 7 Visual Basic type library GUID `{E1211242-8E94-11D1-8808-00C04FC2C602}`. Together with the use of `DirectX8Class`, this is strong repository evidence that the missing input is the Microsoft DirectX 8 Visual Basic audio/DirectMusic type library. The adjacent GUID is corroborating evidence, not a substitute for binary provenance.

The immutable `pristine/r389` tree and local Git history contain neither `dx8vb.dll` nor `Interop.DxVBLibA.dll`; that archaeological finding remains unchanged. The later external input was extracted from the supplied XP SP3 ISO member `I386\DX8VB.DL_`. The expanded 1,227,264-byte Microsoft file is version `5.03.2600.5512 (xpsp.080413-0845)`, has SHA-256 `19149F082F3CA68AA893ADAF0309E5E6C8EA8710C0FE2040F95E8DA5A329F846`, and is authenticated by the ISO's Microsoft-signed catalogs. The byte-identical `dx8vb.zip` candidate is ignored and remains outside the repository.

### Source-named types that must exist

The generated assembly must expose these exact `DxVBLibA` types because they appear in `DirectAudio.net` source:

- `DirectX8Class`
- `DirectMusicLoader8`
- `DirectMusicPerformance8`
- `DirectMusicAudioPath8`
- `DirectMusicSegment8`
- `DirectMusicSegmentState8`
- `DirectSound8`
- `DMUS_AUDIOPARAMS`
- `CONST_DMUS_AUDIO`, including `DMUS_AUDIOF_ALL`
- `CONST_DMUSIC_STANDARD_AUDIO_PATH`, including `DMUS_APATH_DYNAMIC_STEREO`
- `CONST_DMUS_SEGF_FLAGS`, including `DMUS_SEGF_SECONDARY`

The minimum member surface observed at compile sites is:

| Receiver | Required member use |
|---|---|
| `DirectX8Class` | constructor, `DirectMusicLoaderCreate()`, `DirectMusicPerformanceCreate()` |
| `DirectMusicLoader8` | `LoadSegment(string)` returning `DirectMusicSegment8` |
| `DirectMusicPerformance8` | `InitAudio(...)`, `CloseDown()`, `PlaySegmentEx(...)`, `GetMusicTime()`, `GetClockTime()`, `ClockToMusicTime(...)`, `CreateAudioPath(...)`, `GetDefaultAudioPath()`, and `IsPlaying(...)` |
| `DirectMusicSegment8` | `SetStandardMidiFile()`, `GetLength()`, `Download(...)`, `Unload(...)`, `Clone(0, 0)`, `GetRepeats()`, `SetRepeats(...)`, and `GetAudioPathConfig()` |
| `DirectMusicAudioPath8` and `DirectMusicSegmentState8` | Returned/stored COM interface types released or queried by the wrapper |

This is an exact list of source-observed names and calls, not a claim that the full type library contains only these members. The accepted typelib and generated assembly expose all listed types and members. The full library contains 483 types; the required enum values are `DMUS_AUDIOF_ALL = 63`, `DMUS_APATH_DYNAMIC_STEREO = 8`, and `DMUS_SEGF_SECONDARY = 128`.

### Candidate acceptance test

The supplied candidate passed the following acceptance test before entering the build:

1. Record origin, filename, byte length, SHA-256, file/product version, architecture, signature status, and redistribution basis.
2. Load its type library without registering it and verify GUID `{E1211242-8E94-11D1-8808-00C04FC2C603}`, version 1.0, and LCID 0.
3. Generate or inspect `Interop.DxVBLibA.dll` and verify every source-named type and member above.
4. A 32-bit, no-registration class-factory probe loaded the DLL and created `DirectX8Class` successfully.
5. `DirectAudio.net` and the complete solution project graph built without stubbing or disabling audio.

The checked-in `dx7vb.dll` fails this acceptance test: its generated wrapper contains `DirectX7Class` and no `DirectX8Class`.

## Exact .NET 2.0 SDK trace

The missing SDK message can now be classified precisely:

1. `PrepareForBuild` depends on `GetFrameworkPaths` in both the 2.0 and 3.5 `Microsoft.Common.targets`.
2. Under the 2.0 targets, `GetFrameworkPaths` runs the `GetFrameworkSdkPath` MSBuild task.
3. That task calls `ToolLocationHelper.GetPathToDotNetFrameworkSdk` for framework version 2.0. When it cannot find `HKLM\SOFTWARE\Microsoft\.NETFramework\SDKInstallRootv2.0`, it logs the observed “Could not locate the .NET Framework SDK” message and returns success.
4. The task would populate `TargetFrameworkSDKDirectory` and `_TargetFrameworkSDKDirectoryItem`; `FrameworkSDKDir` is derived from the item.
5. Neither the repository nor the imported 2.0/3.5 common targets consumes `$(TargetFrameworkSDKDirectory)` or `$(FrameworkSDKDir)` in this build path.

A direct `GetFrameworkPaths` run with the 2.0 host completed with `Build succeeded`, zero warnings, and zero errors after printing the SDK message. With the selected 4.x host and 3.5 toolset, the 3.5 task instead finds `C:\Program Files\Microsoft SDKs\Windows\v6.0A\`.

The COM-reference target is not the missing link:

- `ResolveComReferences` invokes the `ResolveComReference` MSBuild task.
- Disassembly of both the 2.0 and 3.5 `Microsoft.Build.Tasks` implementation shows `TlbReference.GenerateWrapper` calling `System.Runtime.InteropServices.TypeLibConverter.ConvertTypeLibToAssembly` in-process.
- It does not launch `TlbImp.exe` and it does not consume either SDK-directory property.

`GenerateSerializationAssemblies` can invoke the SDK `SGen` tool, but its condition is false here: no project sets `GenerateSerializationAssemblies=On`, and no `WebReferenceUrl` item makes the default `Auto` mode active. It therefore does not create a hidden SDK requirement.

Conclusion: there is no tool, target, or property in the actual FreeTrain build that requires a standalone .NET 2.0 SDK. The exact source of the message is `GetFrameworkSdkPath`; the output properties are informational for this tree. `SDKInstallRootv2.0` is reclassified as noncritical, and no historical SDK should be installed to address it.

## Native alpha binary decision

The checked-in alpha binary is sufficient for the Phase 1 runnable-preservation baseline without rebuilding it, subject to the normal x86 COM-registration/runtime conditions.

Evidence:

- Debug and Release copies are byte-identical and pinned by the SHA-256 above.
- PE format is `COFF-i386`, address size 32-bit, with a 2005-09-03 PE timestamp and linker version 7.10. The linker version suggests a Visual C++ 7.1-era build even though the preserved project was later upgraded to `.vcproj` version 8.00.
- The export table contains all seven expected entry points: `DllCanUnloadNow`, `DllGetClassObject`, `DllRegisterServer`, `DllUnregisterServer`, `buildNightImage`, `GetDisplayModeName`, and `bltHueTransform`.
- The embedded Win32 type library loads without registration and reports `DirectDrawAlphaBlendLib`, GUID `{EF1510AF-E75F-4974-BE7A-A2F4E88EBFB4}`, version 1.0, LCID 0.
- The embedded interface is `IAlphaBlender`, IID `{2D16CEE2-F54C-425F-84A7-61692CF1D82C}`, with DISPIDs 1, 2, and 3 for `bltAlphaFast`, `bltShape`, and `bltColorTransform`. The coclass is `AlphaBlender`, CLSID `{B6803A0F-671C-4730-A802-BB0C2C4BDAC4}`.
- The checked interop assembly exposes the same interface, coclass, DISPIDs, and DirectDraw-surface parameter types.
- A non-registering 32-bit probe loaded the DLL on the current machine, resolved all seven exports, obtained its class factory through `DllGetClassObject`, and successfully created `IAlphaBlender` with HRESULT `0x00000000`.
- The native project is not part of `FreeTrain_VS2008.sln`; the historical managed solution already expects the DLL to exist in `bin/Debug` and `bin/Release`.

Limits of this decision:

- The DLL is unsigned and has no file-version resource; the hash is the preservation identity.
- `Driver.cs` calls `DllRegisterServer` in-process and discards its HRESULT because the P/Invoke is declared `void`. Registration writes `HKCR` and may require a controlled/elevated x86 environment. Phase 1B must test this without changing the launcher yet.
- Loading and direct COM activation do not establish renderer correctness. Pixel behavior remains a Phase 2 specification task.
- A pinned binary satisfies the runnable-preservation baseline, not an eventual all-native-source build policy. If such a policy is adopted, the VC++/ATL/MIDL toolchain becomes a later gate.

## Generation-only tool dependencies

| Tool or generated artifact | Classification evidence |
|---|---|
| MSBuild `ResolveComReference` / runtime `TypeLibConverter` | In-process generator for `Interop.DxVBLib.dll`, `Interop.DxVBLibA.dll`, and the Quartz interop assembly. The task is generation-only; its generated wrappers are compile inputs and runtime-copy outputs, not separately installed COM runtimes. |
| Windows SDK v6.0A `TlbImp.exe` 3.5.30729.1 | Available local tool that successfully generated the DirectX 7 wrapper in a disposable probe. It is an explicit deterministic-generation option, not a runtime prerequisite and not required by `ResolveComReference` itself. |
| `tools/XmlPP.exe`, `tools/XmlCombiner`, and external `msxsl` | Used by `report/*.bat` to generate reports. `XmlPP.exe` is checked in; `msxsl` is not present locally. This toolchain is generation-only and outside the runnable game baseline. |
| `AxImp` for NeoFT browser controls | NeoFT contains an ActiveX wrapper reference, but NeoFT is outside the baseline. Do not install an SDK merely to generate it during Phase 1. |

## Noncritical dependencies

| Dependency or component | Reason it must not block Phase 1 |
|---|---|
| Standalone .NET Framework 2.0 SDK and `SDKInstallRootv2.0` | The exact trace above proves the property is not consumed by this build. |
| VCBuild/Visual C++ 7.1 or 8.0, ATL, and MIDL for `DirectDraw.AlphaBlend` | The verified native DLL is accepted for the preservation baseline and the native project is outside the managed solution. These tools become relevant only to a later native-from-source gate. |
| `DirectDraw.AlphaBlendPS.vcproj` | No proxy/stub binary is used by the checked runnable layout; the in-process automation interface works through the main DLL. |
| `lib/DirectShow.VideoRecorder`, `lib/DirectShow.TypeLib`, `plugins/org.kohsuke.freetrain.tools.vcr`, and their `.lib`/interop files | VCR was historically distributed, but it is runtime-optional and absent from `FreeTrain_VS2008.sln`. Preserve all source, generated-input evidence, and official reference binaries. Reconstruct its auxiliary VC++/MIDL/TlbImp/IL toolchain independently if provenance-known historical tools become available; do not block the core build or modernization on that work. |
| `NeoFT`, `experiments`, and their `AxSHDocVw.dll` dependency | Separate historical branches/experiments, not the r389 runnable package. |
| Developer utilities (`ColorDiff`, `GUIDGen`, `PicturePreviewer`, `TrainListBuilder`, `XmlCombiner`, and `MapConstructionDriver`) | Useful auxiliary programs, but not dependencies of `FreeTrain.exe` or its standard plugin package. |

## Phase 1A gate

The original Phase 1A stop condition is resolved: the provenance-known `DxVBLibA` candidate passed the acceptance test without downloading or installing a historical SDK/runtime. Phase 1B's reproducible build/package work is complete; controlled runtime smoke validation remains separate.
