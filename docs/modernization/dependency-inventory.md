# Dependency inventory

## Critical runtime dependencies

| Dependency | Evidence and role | Modernization disposition |
|---|---|---|
| `dx7vb.dll` / `DxVBLib` | DirectX 7 Visual Basic COM binding used by core and `DirectDraw.net` | Retain for legacy build; replace behind the `org.kohsuke.directdraw` facade in Phase 3 |
| `DirectDraw.AlphaBlend.dll` | ATL COM server plus unmanaged hue transform; checked into Debug and Release output directories | Implement behavior in the managed backend during Phase 3; Phase 4 is its removal gate |
| `Interop.DirectDrawAlphaBlendLib` | Managed COM interop reference used by `Surface` | Remove with native alpha DLL in Phase 4 |
| `DxVBLibA` | DirectMusic/DirectSound wrapper dependency in `DirectAudio.net` | Replace behind audio contracts in Phase 5 |
| `QuartzTypeLib` | DirectShow COM dependency in `DirectAudio.net` | Replace in Phase 5 |
| `MagicLibrary.dll` | DotNet Magic UI library used by core; readme warns it is not LGPL | Preserve during behavioral work; audit license and replace late |
| `SharpZipLib.dll` | Historical compression library; loader recognizes a `BZ` header | Preserve until legacy save import is characterized; replace with platform compression only after fixtures exist |
| `SHDocVw.dll` / `AxSHDocVw.dll` | Internet Explorer/ActiveX browser interop | Identify actual UI usage; remove late |
| `MsHtmlHost.dll` | Legacy HTML host | Identify actual UI usage and provenance; remove late |
| `Microsoft.JScript` and `Microsoft.Vsa` | Referenced by the core project | Locate actual runtime use before selecting a replacement |
| `System.Runtime.Serialization.Formatters.Soap` | Implements `.ftgt` save format | Isolated import only in Phase 6; never part of the modern runtime |

## Native and auxiliary components

| Component | Status |
|---|---|
| `lib/DirectDraw.AlphaBlend` | Critical until managed renderer equivalence; old ATL source is present |
| `lib/DirectShow.VideoRecorder` | Explicitly outside the critical path |
| `lib/DirectShow.TypeLib` | Related to recorder; outside the critical path |
| `lib/DirectShow.VideoRecorder/lib/*.lib` | Checked-in historical static libraries; retain only in pristine history once recorder disposition is decided |
| `tools/Driver` and `tools/MapConstructionDriver` | Import and call `DllRegisterServer` on the alpha DLL; remove registration behavior in Phase 4 |

## Packaging/provenance requirements

Before deleting or upgrading a binary dependency, record:

- Filename and SHA-256
- Assembly/file version where readable
- Architecture
- License and redistribution evidence
- Referencing projects and call sites
- Whether source is present
- Replacement and rollback strategy

Dependency cleanup is a Phase 8 activity unless a dependency directly blocks an earlier phase.
