# Phase 1D — preservation-runtime validation plan

## Status and boundary

The disposable XP runtime has launched successfully through core initialization and plug-in loading and provides a functioning DirectDraw preservation environment. The historically distributed VCR plug-in can fail independently when its auxiliary managed/native payload is absent; that optional failure does not invalidate the core runtime or block Phase 2 renderer characterization.

The validation target is a disposable, offline Windows XP Professional SP3 x86 virtual machine. Nothing in this plan requires installing or registering an obsolete DirectX, COM, or .NET component on the Windows 11 host. The VM must be snapshotted before first launch and reverted or destroyed after the evidence is exported.

This phase does not change FreeTrain source, replace DirectDraw, refactor `org.kohsuke.directdraw`, or make the legacy renderer a Windows 11/CI prerequisite. Phase 2 may now proceed using captures made in the functioning XP VM, but its automated tests must also be able to use immutable fixtures and non-legacy oracles without executing DirectDraw. Do not open or depend on the VCR plug-in when producing renderer fixtures.

## Evidence behind the plan

The plan follows these checked source and package facts:

- `tools/Driver/Driver.cs` sets `Core.installationDirectory` to the directory containing `FreeTrain.exe`, invokes `DirectDraw.AlphaBlend.dll!DllRegisterServer`, and only then constructs `MainWindow`.
- `Core.userRegistry` creates `HKCU\Software\FreeTrain`. `Core.options` loads `FreeTrain.exe.options` beside the executable, and shutdown writes that file.
- `MainWindow` reads and writes relative `layout.config`, so process current directory matters independently of `Application.ExecutablePath`.
- `ResourceUtil` first resolves system resources under `<installationDirectory>\res`.
- `PluginManager` uses `<installationDirectory>\plugins` in a packaged layout and scans its immediate child directories for `plugin.xml`. Plugin code bases are subsequently resolved relative to those manifests.
- Startup creates `DirectMusicPerformance8` before plug-in loading. Failure is caught and disables sound effects, so DirectMusic failure is degradable but fails the full preservation gate.
- Startup constructs `QuartzTypeLib.FilgraphManagerClass` after plug-in loading even when no BGM is selected. That activation is not caught by `BGMManager`; Quartz/DirectShow is therefore launch-critical.
- `MainWindow.OnLoad` creates a windowed DirectDraw object and a default `127 x 127 x 12` world, opens a map view, and starts the clock.
- Save dialogs use `.ftgd` for `BinaryFormatter` and `.ftgt` for `SoapFormatter`. Both begin with the uncompressed `UC` header.
- The completed Debug package contains 374 files, 54 immediate plug-in directories with 54 manifests, 38 core resource files, and the required managed interop assemblies. It deliberately does not contain `dx8vb.dll`.
- The accepted native alpha DLL imports only XP system DLLs (`KERNEL32`, `USER32`, `ADVAPI32`, `ole32`, `OLEAUT32`, and `SHLWAPI`); it does not create a Visual C++ redistributable prerequisite.

The package is currently at `.artifacts\legacy-build\current\package\Debug`. The package report pins the important files, including:

| File | SHA-256 |
|---|---|
| `FreeTrain.exe` | `6449145B79D4F7D2B287AE8A9F7465BFB5C418C58903DFD847EF6530FE423C15` |
| `FreeTrain.Core.dll` | `1CCE5283FF61BEE670B3AAC46446CF75D51156C9AAC7BDCB13920598C8B00129` |
| `DirectDraw.net.dll` | `EE3D8FD1282465D44F668B444C98A74112D286AF0A16E9AF7E1A296871FCD8CA` |
| `DirectAudio.net.dll` | `37A8F8B5F95B188B31E1EB61F548C151DD437B195F9D7F62EC4B6EE77A9B8D06` |
| `Interop.DxVBLib.dll` | `6B9672FA25E238200D4DEB1B62FBDF5B9A947F9DEB1EB63E9F26E581720F7039` |
| `Interop.DxVBLibA.dll` | `52CED6F07AAC1DBFE074BE8BEB6B3C80446D1C7036738A26B1BBC47F4B308496` |
| `Interop.QuartzTypeLib.dll` | `06635DCDA6D7254F26ABA08CC22FF36272AA54C5B46F44BED7DF5794939C241F` |
| `Interop.DirectDrawAlphaBlendLib.dll` | `8AED64C6D01444B95B419E544A01E7BD667D541B3715067D232C52ED5BA466B6` |
| `DirectDraw.AlphaBlend.dll` | `B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D` |

The supplied XP ISO has SHA-256 `FD8C8D42C1581E8767217FE800BFC0D5649C0AD20D754C927D6C763E446D1927`. Its `I386\DX8VB.DL_` member was already shown to expand to the Microsoft-catalog-verified `dx8vb.dll` used for the build-time interop conversion. That DLL is an operating-system runtime component in this plan, not an application file to copy beside `FreeTrain.exe`.

## Validation environment

Use a new XP SP3 x86 VM and preserve three snapshots:

1. `xp-sp3-clean`: installation complete, network adapter disconnected, no FreeTrain files or extra runtime installed.
2. `xp-sp3-clr2`: CLR 2 runtime installed in the guest, XP DirectX/DirectShow registrations verified, display/audio settings fixed.
3. `freetrain-r389-prelaunch`: package copied to the local guest disk, integrity checked, and no FreeTrain process launched yet.

Recommended stable capture settings are one virtual CPU, 512–1024 MiB RAM, a 1024 x 768 32-bit desktop at 96 DPI, the Windows Classic theme, a fixed English locale, and an emulated XP-compatible sound device. Use the hypervisor console, not Remote Desktop, because remote display sessions can change DirectDraw availability and pixel output. Keep the network adapter disconnected. Do not install browser, sync, antivirus, or capture utilities in the oracle VM.

Use the hypervisor's default legacy 2D adapter first. Do not enable a modern 3D acceleration path merely for this test. If guest additions or a different video driver are required to obtain DirectDraw support, treat that as a distinct environment, record the exact hypervisor/driver versions, and never mix its captures with the unmodified-guest baseline.

## Minimum runtime prerequisites

| Prerequisite | Minimum purpose | Gate |
|---|---|---|
| Windows XP Professional SP3 x86 | Original 32-bit OS family, common controls, GDI/GDI+, OLE, registry, and system DirectX/DirectShow components | Launch-critical |
| .NET Framework 2.0 runtime / CLR `v2.0.50727`, x86 | `FreeTrain.exe` and core assemblies are PE32, `32BITREQ`, CLR v2 assemblies; the package readme explicitly requires .NET 2.0 | Launch-critical |
| DirectDraw 7 plus the `DxVBLib` automation type library | `org.kohsuke.directdraw.DirectDraw` activates `DirectX7Class` and creates `DirectDraw7` | Launch-critical |
| Quartz/DirectShow | `BGM` unconditionally activates `FilgraphManagerClass` during startup | Launch-critical |
| Package-local native alpha DLL and its interop assembly | `Surface` statically activates `AlphaBlenderClass`; the launcher registers this exact DLL first | Launch-critical |
| A local, writable NTFS package directory with `res` and `plugins` intact | Resource lookup, plug-in discovery, options, and docking-layout persistence | Launch-critical |
| DirectX 8 VB automation, DirectMusic, DirectSound, and an emulated sound device | `DirectMusicPerformance8.InitAudio` and sound-effect playback | Required for full preservation acceptance; launch can degrade to disabled SFX |
| DirectShow MIDI rendering and a MIDI/audio output path | Playback of the three packaged `.mid` BGM files | Required for the audio smoke scenario, not for a silent launch |

No compiler, SDK, Visual Studio, MSBuild, `TlbImp`, source `dx8vb.dll`, Visual C++ redistributable, or COM interop generator belongs in the runtime VM.

The verified external prerequisite is now the Microsoft .NET Framework 3.5 SP1 full offline installer recorded in `phase1d-dotnet35sp1-prerequisite.md`. It is staged under ignored `.artifacts`, not tracked or included in the application package. It must be installed only inside the disposable guest, and its resulting CLR 2.0 servicing level must be recorded before FreeTrain is launched. The package is broader than the minimum CLR 2 requirement but supplies the required CLR 2.0 SP2 baseline from one authenticated offline bundle.

## COM identity and registration plan

XP is 32-bit, so all registry checks use the normal `HKCR` view; there is no `Wow6432Node` split to manage.

### Microsoft components already expected from XP setup

Run these read-only checks in `xp-sp3-clr2` before copying FreeTrain:

```bat
reg query "HKCR\TypeLib\{E1211242-8E94-11D1-8808-00C04FC2C602}\1.0\0\win32"
reg query "HKCR\CLSID\{E1211353-8E94-11D1-8808-00C04FC2C602}\InprocServer32"
reg query "HKCR\TypeLib\{E1211242-8E94-11D1-8808-00C04FC2C603}\1.0\0\win32"
reg query "HKCR\CLSID\{E7FF1300-96A5-11D3-AC85-00C04FC2C602}\InprocServer32"
reg query "HKCR\TypeLib\{56A868B0-0AD4-11CE-B03A-0020AF0BA770}\1.0\0\win32"
reg query "HKCR\CLSID\{E436EBB3-524F-11CE-9F53-0020AF0BA770}\InprocServer32"
```

These identify, respectively:

- `DxVBLib` 1.0 and `DxVBLib.DirectX7Class`;
- `DxVBLibA` 1.0 and `DxVBLibA.DirectX8Class`;
- `QuartzTypeLib` 1.0 and `QuartzTypeLib.FilgraphManagerClass`.

Expected servers are XP system files under `%SystemRoot%\System32`, not files in the FreeTrain directory. Record each resolved path, file version, size, and hash when the guest has a trusted hashing utility. Also save `dxdiag /t` output.

Do not call `regsvr32` for these components in the primary run if the clean XP installation already passes the probes. Do not use `regasm` on `Interop.*.dll`; those files are managed callable wrappers, not COM servers.

If a Microsoft registration is missing in the clean VM, stop the primary run and record a reproducible environment blocker. A separate repair snapshot may use only the supplied Microsoft XP media: first confirm that the required compressed member exists, expand it inside the guest, verify its metadata/hash, and then register the system DLL with guest `%SystemRoot%\System32\regsvr32.exe`. Never substitute the application-build interop assembly or an unverified download. Evidence from a repaired snapshot must be labelled separately from clean-XP evidence.

### Package-local alpha server

Before the first launch, the clean VM should not need this key:

```bat
reg query "HKCR\CLSID\{B6803A0F-671C-4730-A802-BB0C2C4BDAC4}\InprocServer32"
```

Launch `FreeTrain.exe` as a local administrator in the disposable VM. The existing driver calls `DirectDraw.AlphaBlend.dll!DllRegisterServer`; no manual registration command is part of the normal procedure. After the main window appears, verify:

```bat
reg query "HKCR\CLSID\{B6803A0F-671C-4730-A802-BB0C2C4BDAC4}\InprocServer32"
reg query "HKCR\TypeLib\{EF1510AF-E75F-4974-BE7A-A2F4E88EBFB4}\1.0\0\win32"
```

The class path must be the exact package copy at `C:\FTVM\app\r389\DirectDraw.AlphaBlend.dll`. The class is `DirectDrawAlphaBlendLib.AlphaBlenderClass`; its interface is `{2D16CEE2-F54C-425F-84A7-61692CF1D82C}`. Because registration records an absolute module path, do not move or rename the package after first launch. Starting the launcher from its final path refreshes the registration on every run.

Do not unregister the alpha server on the host. In the VM, snapshot reversion is the cleanup mechanism; it is less ambiguous than attempting partial COM cleanup.

## Package transfer, working directory, and layout

Transfer the package into the VM through read-only virtual media, then copy it to a simple guest-local ASCII path:

```bat
mkdir C:\FTVM
mkdir C:\FTVM\app
xcopy D:\Debug C:\FTVM\app\r389\ /E /I /H /K
cd /d C:\FTVM\app\r389
FreeTrain.exe
```

Replace `D:` with the read-only virtual-media drive. Do not run from the ISO, a shared folder, a UNC path, the host repository, or a path containing locale-sensitive characters.

Before launch, require `C:\FTVM\plugins` to be absent. `PluginManager` checks `<installationDirectory>\..\..\plugins` before the packaged folder; from the selected path that resolves to `C:\FTVM\plugins`. A stray directory there would silently replace the plug-in set under test.

Then compare the copied critical files byte-for-byte with the read-only medium using `fc /b`, and retain the host-generated sorted SHA-256 tree manifest. The expected package invariants are:

```text
C:\FTVM\app\r389\FreeTrain.exe
C:\FTVM\app\r389\DirectDraw.AlphaBlend.dll
C:\FTVM\app\r389\Interop.DirectDrawAlphaBlendLib.dll
C:\FTVM\app\r389\Interop.DxVBLib.dll
C:\FTVM\app\r389\Interop.DxVBLibA.dll
C:\FTVM\app\r389\Interop.QuartzTypeLib.dll
C:\FTVM\app\r389\res\...
C:\FTVM\app\r389\plugins\<54 immediate plug-in directories>\plugin.xml
```

Always set both executable path and current directory to `C:\FTVM\app\r389`. The executable directory must be writable because the application creates or updates `FreeTrain.exe.options`; the current directory must be writable because it creates or updates `layout.config`. FreeTrain also writes per-user state below `HKCU\Software\FreeTrain`, including its installation directory, main-window state, and recently used files.

Launch without command-line arguments. The sole argument path is treated as a plug-in profile search path, not as a save file, and the checked parser does not provide a reliable normal-package profile. Open saves through **File > Open** or drag-and-drop only.

For a clean repeat, revert to `freetrain-r389-prelaunch`. If snapshot reversion is unavailable, close FreeTrain, remove only the VM copy of `FreeTrain.exe.options` and `layout.config`, remove only `HKCU\Software\FreeTrain`, and recopy the package from the read-only source. Never perform that cleanup on the host repository.

## Execution sequence and smoke scenarios

Create `C:\FTCapture\<run-id>` in the guest for logs and save fixtures. Every observation must record pass, fail, or degraded; a dialog that is dismissed is not a pass.

### RV-00 — environment and clean-state record

1. Record the VM product/version, virtual hardware, video driver, audio driver, XP edition/SP/build, locale, theme, desktop resolution/depth, DPI, and time zone.
2. Record CLR 2 installation and service-pack registry values under `HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.50727`.
3. Save `dxdiag /t C:\FTCapture\<run-id>\dxdiag.txt`.
4. Save the six Microsoft COM registry queries above and verify that `HKCU\Software\FreeTrain` and the alpha CLSID are absent or record why they are not.
5. Verify package counts and critical hashes. Record the Git commit and Phase 1 package-report hash on the host-side manifest.

Pass: all launch-critical prerequisites resolve to 32-bit XP system components; package is unchanged; the alpha class is not relied upon before the launcher runs.

### RV-01 — cold launch and registration

1. From `C:\FTVM\app\r389`, run `FreeTrain.exe` as the VM's local administrator.
2. Observe the splash/plugin-loading sequence. Do not accept any plug-in error, unhandled exception, DirectDraw error, missing-resource error, or COM activation error.
3. Confirm that the main `FreeTrain` window and `Map` child window appear and render the default blank world.
4. Immediately select **Pause** from the toolbar **Timer** drop-down before capture work.
5. Verify the alpha CLSID/type-library registration and `HKCU\Software\FreeTrain\installationDirectory`.
6. Open **File > Plugin List** and confirm 54 loaded plug-ins with no load errors.

Pass: the main map remains responsive for two minutes, redraws without corruption, and no fatal or plug-in warning appears. A `DirectAudio can not be initialized` dialog makes the launch `degraded`, not a full pass.

### RV-02 — renderer/window lifecycle

1. Pan the map by dragging, resize the map child window, and expose previously covered regions.
2. Minimize and restore the main window once, then switch away and back through the hypervisor console.
3. Toggle **Always day**, **Always night**, then **Day and night**.
4. Open **View > Height Cutting** and select **Water level**, one level above it, and **None**. Also test one mouse-wheel step in each direction.
5. Compare a stable before/after capture of the same viewport after minimize/restore.

Pass: DirectDraw surfaces restore; no black/stale rectangles, displaced blits, color-key halos, or crash appears. The fixed quarter-view camera has no rotation command, so Phase 2 must use directional scene content rather than inventing a camera-rotation requirement.

### RV-03 — plug-in resources and alpha paths

Using a fresh small world, exercise these existing UI paths without changing source:

1. Open a building-construction selector and keep a valid placement preview visible over the map; capture its translucent preview.
2. Move the preview across a map boundary and an invalid placement; capture clipping/negative-offset behavior.
3. Open rail and road construction previews to exercise shaped/color-key overlays.
4. Place terrain, a rail segment, a platform, one structure, and one land object from packaged plug-ins.
5. Include north/south/east/west-directed rails or platforms in the eventual fixture; the game has directional sprites but no rotatable camera.

Pass: previews and committed sprites draw without opaque boxes, missing colors, clipping corruption, or plug-in exceptions.

### RV-04 — save-format round trip

1. Choose **File > New Game**, select the packaged empty-game contribution, and create a named `30 x 30 x 6` world.
2. Pause the clock and make a small, documented set of changes.
3. Save it as `C:\FTCapture\<run-id>\fixtures\roundtrip.ftgd`; verify the first two bytes are `UC` and record its hash.
4. Make one visible change, reopen the `.ftgd`, and confirm the saved state replaces the changed state.
5. Save the same loaded world as `roundtrip.ftgt`, verify `UC`, close, reload it, and compare the visible state and status-bar time.

Pass: both format paths save and reload in the legacy runtime without exception or missing-contribution warnings. Treat all legacy saves as trusted test data: never feed arbitrary files to these unsafe formatters.

### RV-05 — audio

1. The cold launch must not show the DirectAudio-disabled dialog. Confirm **Configure > Sound Effects > On** is enabled.
2. Choose **Configure > Music > Pioneers** to play packaged `plugins\org.kohsuke.freetrain.music\map.mid`, then select **Silence**.
3. For full SFX validation, use a fixture containing a scheduled train and select one packaged departure bell; observe a complete departure/bell cycle.
4. Record audible/not audible, error dialogs, and the guest audio device/driver. If the hypervisor supports lossless guest-audio capture, store it as supplementary evidence; do not substitute audio presence for screenshot checks.

Pass: DirectMusic initializes, packaged MIDI starts/stops, and one DirectMusic sound effect plays. MIDI-only success does not prove the DirectMusic SFX path because BGM uses Quartz while SFX uses `DxVBLibA`.

### RV-06 — clean relaunch

Close FreeTrain normally, verify `FreeTrain.exe.options` and `layout.config` were written beside/from the package root as expected, then relaunch from the same working directory. Confirm the package still loads, the alpha registration still points to the same DLL, and no new plug-in error appears.

## Phase 2 fixture preparation

### Fixture set

Create fixtures through the unmodified XP application UI; do not synthesize them with a modern serializer.

| Fixture | Purpose |
|---|---|
| `empty-30x30x6.ftgd` | Minimal deterministic paused world; resource, ground/water, height-cut, day/night, pan, and redraw reference |
| `mixed-renderer.ftgd` | Terrain slopes, water edge, rails, platforms, directional objects, train, structures, land objects, and spaced empty margins for clipping/preview captures |
| `mixed-renderer.ftgt` | SOAP-format save of the same legacy world for Phase 6 evidence; not a separate pixel oracle unless it reloads identically |
| `audio-departure.ftgd` | Train/schedule/departure-bell setup for repeatable DirectMusic validation |

Author `mixed-renderer.ftgd` once, pause immediately, save, close, reload, and capture only from the reloaded file. Keep both map scrollbars at their minimum for canonical captures and place the scene accordingly. Record the exact status-bar date/time, viewport position, height-cut level, day/night mode, selected controller, and every contribution name/ID used. Do not rely on random development or on waiting a variable number of ticks.

The scene should deliberately cover legacy operations identified in `renderer-compatibility.md`: color key, regular and stretched blits, half-alpha placement previews, shaped overlays, color-mapped and hue-transformed sprites, vertical-flip variants, clipping at viewport edges, odd-width images, station labels, controller overlays, height cuts, and full versus dirty redraw. Where the UI exposes no direct primitive, preserve the world-level capture now and create a code-derived/native-vector primitive oracle in Phase 2.

### Capture matrix

At minimum, collect these lossless references from the same reloaded `mixed-renderer.ftgd`:

| Capture ID | State |
|---|---|
| `scene-day-none` | Paused, **Always day**, height cut **None**, neutral controller |
| `scene-night-none` | Same viewport, **Always night**, height cut **None** |
| `scene-day-water-cut` | Same viewport, **Always day**, height cut **Water level** |
| `scene-alpha-valid` | Valid structure placement preview visible |
| `scene-alpha-clipped` | Same preview partially beyond viewport/map edge |
| `scene-shape-preview` | Rail or road placement overlay visible |
| `scene-restored` | Same neutral viewport after minimize/restore |
| `scene-resized-full-redraw` | Documented client size after resize and complete redraw |

Capture directional content in one scene where possible. Do not label captures as camera rotations: the checked UI has no camera-rotation operation.

### Screenshot procedure

1. Revert to the prelaunch snapshot, launch from the package root, load the selected trusted fixture through **File > Open**, and pause the timer.
2. Set the desktop, window/client size, docking layout, viewport scroll position, height cut, day/night mode, and controller exactly as recorded.
3. Move the mouse cursor outside the map client area. Wait for two visually unchanged frames; do not advance the game clock.
4. Use the hypervisor console's lossless full-frame PNG capture. Do not use RDP, JPEG, clipboard conversion, host display scaling, or the bundled Video Recorder plug-in. Opening that plug-in introduces additional DirectShow/native registration paths that are outside this baseline.
5. Preserve the original full guest-frame PNG unchanged. If Phase 2 needs a map-client crop, create it as a separate derived file and record the integer crop rectangle. Never resize, color-correct, or recompress the oracle.
6. Record SHA-256 for the fixture, raw PNG, derived crop, package manifest, and environment report after export to the host.
7. Mark window chrome, GDI text, caret, and station-name regions as platform-sensitive masks. Keep an unmasked source image. Exact equality remains required for deterministic sprite/map pixels; masks are not permission to hide renderer differences.

Recommended artifact layout, kept outside tracked source:

```text
.artifacts/phase1d-capture/<run-id>/
  environment/
    dxdiag.txt
    registry-before.txt
    registry-after.txt
    vm.txt
  package/
    package-tree.sha256
  fixtures/
    empty-30x30x6.ftgd
    mixed-renderer.ftgd
    mixed-renderer.ftgt
    audio-departure.ftgd
  screenshots/raw/
    <capture-id>__1024x768x32.png
  screenshots/crops/
    <capture-id>__map-client.png
  manifest.json
  observations.md
```

Each `manifest.json` capture entry must contain at least:

```json
{
  "captureId": "scene-day-none",
  "oracleOrigin": "captured-legacy",
  "fixture": "mixed-renderer.ftgd",
  "fixtureSha256": "<sha256>",
  "packageCommit": "<git-commit>",
  "packageTreeSha256": "<manifest-sha256>",
  "vmSnapshot": "freetrain-r389-prelaunch",
  "os": "Windows XP Professional SP3 x86",
  "hypervisor": "<product-and-version>",
  "videoDriver": "<name-and-version>",
  "desktop": "1024x768x32@96dpi",
  "locale": "<locale>",
  "clock": "<status-bar-value>",
  "timer": "paused",
  "nightMode": "AlwaysDay",
  "heightCut": "None",
  "viewport": { "scrollX": 0, "scrollY": 0 },
  "windowClient": { "width": 0, "height": 0 },
  "controller": null,
  "rawPngSha256": "<sha256>",
  "crop": { "x": 0, "y": 0, "width": 0, "height": 0 },
  "masks": [],
  "steps": ["ordered manual actions"],
  "notes": ""
}
```

Raw fixtures and screenshots become immutable Phase 2 inputs after review. Derived expected images may be added separately, but their provenance must remain `captured-legacy`; do not silently replace them with output from the compatibility renderer.

## Failure recording and stop rules

For every failure, record the exact scenario, dialog text/stack trace, HRESULT if present, guest event-log entry, COM query result, package hashes, and whether the failure reproduces after reverting to `freetrain-r389-prelaunch`.

Classify it as:

- `environmental`: hypervisor/video/audio limitation, absent CLR/runtime, permissions, or damaged XP registration;
- `package/layout`: missing/wrong-hash file, wrong current directory, moved alpha DLL, or malformed plug-in tree;
- `legacy-runtime behavior`: reproducible exception or corruption with verified environment and package;
- `capture nondeterminism`: clock, animation, GDI/font, cursor, window geometry, or display pipeline changed between frames.

Stop rather than repair the host when:

- a prerequisite would require host installation or registration;
- a clean XP system component is missing and only an unverified binary is available;
- DirectDraw works only through RDP or a capture path that changes its output;
- the package would need a source change or subsystem substitution to launch;
- a legacy fixture cannot be reproduced from recorded UI steps.

## Phase 1D acceptance gate

Phase 1D passes only when an unmodified, hash-verified package in a disposable XP SP3 x86 VM:

1. launches from the packaged root with no fatal core or required-plug-in errors; an independently recorded VCR load failure is permitted;
2. registers and activates the checked native alpha DLL only inside that VM;
3. creates and redraws the map through DirectDraw after minimize/restore and height/day-night changes;
4. loads every required packaged plug-in; VCR remains historically distributed but runtime-optional;
5. saves and reloads trusted `.ftgd` and `.ftgt` fixtures;
6. initializes DirectMusic/DirectSound, plays one packaged BGM and one SFX for the full-preservation result;
7. produces provenance-complete, lossless Phase 2 fixture/capture artifacts; and
8. is reverted or destroyed without any XP-era component being registered on Windows 11.

If launch and rendering pass but audio degrades, record a runnable-but-degraded preservation result and keep the audio portion of Phase 1D open. VCR auxiliary-build reconstruction is preservation-only and non-blocking. Phase 2 renderer characterization may proceed from the functioning XP runtime; Phase 3 replacement remains gated on review of the resulting capture corpus.
