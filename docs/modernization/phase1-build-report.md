# Phase 1 legacy build report

## Result

The no-registration Phase 1 build path produced a complete x86 Debug preservation package on 2026-08-17. The build compiled all 33 C# projects listed by `FreeTrain_VS2008.sln`, generated the three COM interop assemblies from explicit type-library files, retained the verified native alpha DLL, and reproduced the historical resource/plugin package layout.

Run it from the repository root with:

```powershell
.\eng\legacy-build.ps1 -Dx8VbArchive .\dx8vb.zip
```

The external archive, extracted `dx8vb.dll`, generated interops, logs, and package remain under the ignored `.artifacts/legacy-build/current` tree. Neither `dx8vb.dll` nor its archive is a Git input. The wrapper does not call `regsvr32`, `DllRegisterServer`, `RegisterTypeLib`, or any registry-writing API.

## Verified inputs and generated interops

| Input or output | SHA-256 |
|---|---|
| External `dx8vb.zip` | `360C874C56ADA9CA274CA64286C720DB0E229E59F5BC504CFDEB52B92BE08960` |
| Extracted Microsoft XP SP3 `dx8vb.dll` | `19149F082F3CA68AA893ADAF0309E5E6C8EA8710C0FE2040F95E8DA5A329F846` |
| Checked `dx7vb.dll` | `D69CDC170AAC0AE611ECA3BEE84E7BE346A3BA1B3C79216E13E87C8EE6CD2084` |
| Local 32-bit `quartz.dll` | `D3020B659E0A3ABEF94783163099317DED00E8761543E8013548453B735E79FB` |
| Windows SDK v6.0A `TlbImp.exe` | `955314E8012FA44AE493D14BEA4DAC144920EF062E5914B6BBCAF59A24E55186` |
| Generated `Interop.DxVBLib.dll` | `6B9672FA25E238200D4DEB1B62FBDF5B9A947F9DEB1EB63E9F26E581720F7039` |
| Generated `Interop.DxVBLibA.dll` | `52CED6F07AAC1DBFE074BE8BEB6B3C80446D1C7036738A26B1BBC47F4B308496` |
| Generated `Interop.QuartzTypeLib.dll` | `06635DCDA6D7254F26ABA08CC22FF36272AA54C5B46F44BED7DF5794939C241F` |
| Preserved/package `DirectDraw.AlphaBlend.dll` | `B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D` |

`TlbImp.exe` writes a clock-dependent PE timestamp and a random MVID even when its semantic output is unchanged. The wrapper invokes the pinned tool twice per input, replaces only those two volatile fields with values derived from the pinned input/tool/command descriptor, and requires the normalized outputs to compare byte-for-byte. It then loads the retained assembly and verifies a required type. This produced stable assembly identities and hashes while preserving the established type-library conversion semantics.

The generated `DxVBLibA` assembly is `Interop.DxVBLibA, Version=1.0.0.0`, uses namespace `DxVBLibA`, and contains `DxVBLibA.DirectX8Class`. Its source type library remains GUID `{E1211242-8E94-11D1-8808-00C04FC2C603}`, version 1.0, LCID 0, `SYS_WIN32`, with 483 types.

## Build path

The apparent solution configuration `Debug|x86` is not a complete build configuration: it has a `Build.0` entry only for `DirectAudio.net`. The complete historical graph is `Debug|Any CPU`; its principal projects already specify x86, and the wrapper pins `PlatformTarget=x86` globally.

Loading the solution file directly is impossible on this host because MSBuild's old solution wrapper enumerates a malformed machine-wide ToolsVersion 14.0 registry entry. The wrapper therefore parses the same 33 C# solution entries, orders them topologically by their `ProjectReference` edges, and invokes each project serially with the 3.5 toolset and `BuildProjectReferences=false`. It supplies `SolutionDir`, disables only the interactive post-build commands, and reproduces `copyresources.bat` noninteractively after compilation.

The historical `COMReference` items remain in their project files for the default Visual Studio path. When `LegacyInteropPath` is supplied by the wrapper, conditional ordinary references consume the generated assemblies instead. `FreeTrain.Controls` also receives the already-inventoried repository-local reference to `extlib/MsHtmlHost.dll`. No C# source or subsystem implementation changed, and `FreeTrain.Core` remains a library.

## Error classification

Two diagnostic attempts failed before the successful traversal. They have the same host-level root cause:

| Attempt/error | Classification | Disposition |
|---|---|---|
| .NET 3.5 `MSBuild.exe`: `MSB4141`, empty `MSBuildToolsPath` for registry ToolsVersion 14.0 | Environmental | Host rejected even a minimal project. No machine registry repair was attempted. |
| .NET 4.x `MSBuild.exe` loading `FreeTrain_VS2008.sln`: `MSB1025` followed by `InvalidToolsetDefinitionException` for the same registry entry | Environmental | MSBuild emitted the error twice while unwinding one failed solution load. Replaced by deterministic direct-project traversal. |

The successful 33-project traversal recorded:

| Category | Error count |
|---|---:|
| Environmental | 0 |
| Project/configuration | 0 |
| Missing dependency | 0 |
| Source/compiler incompatibility | 0 |

There were 23 nonfatal compiler warnings: CS0067 (2), CS0105 (1), CS0109 (1), CS0114 (1), CS0162 (1), CS0168 (3), CS0169 (6), CS0219 (1), CS0618 (4), CS0649 (1), and CS1717 (2). Phase 1 preserves them rather than changing legacy source.

## Package validation and stop point

The resulting Debug package contains 374 files. Its required root files include `FreeTrain.exe`, all four primary managed libraries, all three generated COM interops, `Interop.DirectDrawAlphaBlendLib.dll`, and the pinned native alpha DLL. `FreeTrain.exe`, `FreeTrain.Core.dll`, `DirectAudio.net.dll`, and `DirectDraw.net.dll` are CLR v2.0 PE32 assemblies with `32BITREQ=1`.

The original `dx8vb.dll` is intentionally not copied into the application package. It is a verified build-time typelib input and remains a legacy DirectX runtime prerequisite on the execution machine. A live smoke start was not attempted because the historical driver calls the native alpha component's `DllRegisterServer`, and DirectX 7/8 COM activation is not available on this unmodified Windows 11 host. The faithful build/package gate is passed; runtime execution remains a controlled legacy-environment validation task.
