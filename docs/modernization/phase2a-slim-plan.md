# Phase 2A (slim): renderer oracles, proportionate to the renderer

Status: **approved 2026-11-01**. This is the Phase 2A record. It supersedes the paired-VM procedure in `phase2a-legacy-oracle.md`, which is retained as chronology. `phase2a-fixture-layouts.md` remains the tile-level construction sheet for the scene saves (item 5). The paired capture/comparison schemas, templates, and approval manifest have been removed. `eng/renderer-oracle.ps1` is now the slim scene validator.

## Why a slimmer plan

The code under specification is small: `DirectDraw.net` is about 770 lines of C# and `DirectDraw.AlphaBlend` about 2,200 lines of C++. The current Phase 2A apparatus (procedure, layouts, schemas, validator) is larger than that code and has produced no evidence yet. It also points the most expensive oracle, paired-VM screenshots, at the questions screenshots answer worst: clipping edges, odd widths, strides, rounding, and pixel-format variants.

This plan keeps every invariant in `README.md` and the Phase 2 exit gate in `renderer-compatibility.md`. It changes how evidence is obtained, not what must be proven.

## Oracle priority (revised)

| Rank | Source | Answers | Runs on Win11/CI |
| --- | --- | --- | --- |
| 1 | `native-vector`: the shipped native alpha DLL executed against fake surfaces | `bltAlpha`, `bltShape`, `bltColorTransform` (incl. vflip), `bltHueTransform`, night-image darkening, in every pixel mode | Yes |
| 2 | `captured-legacy-dump`: a small console harness run once in the XP VM, dumping surface memory | DirectDraw-owned behavior: `bltFast`, `blt` (incl. stretch), source color key, clip rect, `fill`, `HitTest`, polygon/box, `createBitmap` | No (run once; dumps are committed) |
| 3 | `code-derived` | Coordinate conversion, voxel traversal, season/day-night resource selection | Yes |
| 4 | `captured-official-release` scene screenshots | Integration smoke: does a whole scene still look like the shipped game | No (captured once) |

Scene screenshots move from first to last. They confirm integration; they do not specify primitives.

## Work items

### 1. Native vector harness (primary oracle)

The native routines touch a surface through only three methods: `Lock`, `Unlock`, and `GetSurfaceDesc` (checked across `DirectDraw.AlphaBlend/*.cpp`). Everything else is pointer arithmetic over locked memory.

- Call the **shipped, pinned** `DirectDraw.AlphaBlend.dll` (SHA-256 `B8153302…F165D`). `phase1-build.md` already established that it loads in a 32-bit process on the current machine and creates `IAlphaBlender` through its own class factory without registration. No native recompilation and no historical VC++/ATL toolchain is needed, and the vectors come from the exact binary users ran.
- Write an x86 test harness (C# against the existing `Interop.DxVBLib.dll` / `Interop.DirectDrawAlphaBlendLib.dll`) with a `FakeSurface` implementing `DxVBLib.DirectDrawSurface7`: `Lock`/`GetSurfaceDesc` fill `DDSURFACEDESC2` with a pinned heap buffer of chosen width, height, pitch, and pixel format; `Unlock` is a no-op; every other member throws `NotImplementedException`. `buildNightImage` is reached through the same P/Invoke export `SurfaceLoaders.cs:65` uses.
- `dwMode` is a process-global cached on first call (`AlphaBlender.cpp:7`, `init`) and cannot be reset from outside the DLL, so run one harness process per pixel format.
- Generate vectors for 555, 565, 24-bit, and 32-bit modes. The XP screenshots only ever exercise 32-bit, so this is strictly more coverage than the current plan.
- Inputs are seeded and small: odd widths, pitch > width, every clipping edge and corner, negative destinations, color-key present/absent, color-map hits/misses, flip on/off.
- Output: committed `.bin` buffers plus one JSON index of inputs per case. Regenerate in CI and require byte equality. Divergence means the harness or the toolchain changed, not the oracle.

Source and binary are untouched; this is consistent with rules 8 and 10.

**Prototype result (2026-11-01).** `eng/native-vectors/NativeVectorProbe.cs`, built and run by `eng/native-vectors/run-probe.ps1`, verifies the hash of the shipped DLL. It loads the DLL with `LoadLibrary`, obtains `IAlphaBlender` from `DllGetClassObject`, and calls `bltAlphaFast` on Windows 11 in a 32-bit .NET Framework 4 process. No DirectDraw, `dx7vb.dll`, or COM registration is involved.

- The fake surface redeclares the 68-slot `DirectDrawSurface7` vtable with raw pointers on `GetSurfaceDesc`/`Lock`/`Unlock`, so the native `Lock(NULL, …)` calls are legal. This removed the main marshaling risk: no C++ fallback is needed.
- The DLL detected all four formats through `GetSurfaceDesc` (`GetDisplayModeName` reports 555, 565, 24-bit, 32-bit). Every call made two locks and two unlocks and returned `S_OK`. No case wrote into the guard bytes past any surface.
- Cases covered: aligned even width, odd width with padded pitch, negative destination, right/bottom overrun, and a source sub-rectangle. The source includes color-key pixels.
- In 32-bit mode the output matches byte for byte an independent restatement of the documented `(t & 0xfefefe)>>1 + (s & 0xfefefe)>>1` rule with 24-bit key masking. That confirms the harness reaches the real loop with correct geometry.
- Two complete runs produced identical SHA-256 output for all 20 cases.

**Extended harness (2026-11-01).** The probe now covers all five native routines and writes committed vectors to `fixtures/native-vectors/` (see its README). `run-probe.ps1` defaults to `Check`, which fails unless regenerated output matches those files byte for byte.

- The suite has 28 cases in each of 555, 565, 24-bit, and 32-bit, 112 vectors in all. Each routine runs over the five geometries above: `bltAlphaFast`, `bltShape`, `bltColorTransform` with and without vflip, `bltHueTransform` (plus a second set of targets), and `buildNightImage` (aligned and padded).
- `bltColorTransform` takes the color tables as raw pinned pointers, matching the IDL `[size_is] int*`. `bltHueTransform` and `buildNightImage` are called as `__cdecl` exports.
- Every case returned `S_OK`, kept Lock/Unlock balanced, left the source untouched, and wrote nothing past any surface.
- Every case changed destination pixels, so no case is a no-op. An independent check of the 32-bit aligned `bltColorTransform` vector confirmed 17/17 pixels mapped, 26/26 keyed pixels kept, and 85/85 copied.
- Corrupting one bit of one committed vector makes `Check` fail.
- `fixtures/native-vectors/.gitattributes` marks `.bin` as binary and `.json` as LF, because this checkout uses `core.autocrlf=true`.

Characterized quirks, asserted in 555 and 565:

- **A.** In `bltAlphaFast` the two-pixel path compares the whole `DWORD` with the 16-bit key. A `[key, black]` pair therefore equals the key and is skipped, so the black pixel is never blended.
- **B.** In the same path, a keyed pixel paired with any non-matching DWORD is replaced by the target pixel and then blended with itself. It loses each channel's lowest bit (`t & 0x7bde` / `t & 0xf7de`) instead of staying unchanged. A lone keyed pixel in the odd-width tail is unchanged. `bltColorTransform` builds a `doubleColorKey`, so it is not expected to share the quirk; that is not yet asserted.
- **C.** `buildNightImage` recognizes its special colors through the DLL's `RGB555`/`RGB565` macros (`AlphaBlender.h:28-29`), which shift red and green into the wrong bits. In 565 the light-color constants also overflow and are truncated to `WORD` (for example `RGB565(255,8,8)` becomes `0xF021`). The correctly packed 16-bit colors are simply darkened. In practice only the 24/32-bit paths recognize the intended colors.

Per `renderer-compatibility.md` ("do not correct surprising behavior until characterization decides"), the managed backend must reproduce A–C in 16-bit modes or record an explicit decision not to.

Still open: assertions for `bltShape`, `bltHueTransform`, and night darkening beyond the vectors themselves; the `RGBMODE_16` (unknown 16-bit mask) path, where `bltHueTransform` and `buildNightImage` return `E_NOTIMPL`; and wiring `run-probe.ps1` into CI.

### 2. XP primitive dump (DirectDraw-owned behavior)

`bltFast`, `blt`, stretch, color key, clipping, and `fill` are implemented by DirectDraw itself, not by FreeTrain code, so they need the real runtime once.

- Write a console program referencing the packaged `DirectDraw.net.dll`. It creates off-screen system-memory surfaces, runs a fixed case list (same style of inputs as item 1), reads results through `createBitmap`/locks, and writes raw buffers plus an index.
- Run it in **one** XP SP3 x86 VM against the reconstructed package, then against the official package's `DirectDraw.net.dll`, in the same snapshot. Same VM means no cross-VM environment-equivalence problem.
- Record in a single `environment.json`: XP build, CLR version, `dx8vb.dll` / `ddraw.dll` versions and hashes, display mode, VirtualBox version and graphics controller. Nothing per-file.
- Commit dumps. These become CI vectors for the managed backend.

### 3. Code-derived tests

Coordinate conversion, voxel traversal, and season/night resource selection (`Picture.cs`, `ResourceUtil.cs`, `MountainVoxel.cs`, `Time.cs`) are pure logic. Write characterization tests against the existing code directly. No oracle captures required.

### 4. Official vs reconstructed: compare the build, not screenshots

The question "is the reconstruction faithful to the shipped release?" is a build question. Answer it once with a disassembly diff (`ildasm` or an equivalent decompiler) of `FreeTrain.Core.dll`, `DirectDraw.net.dll`, and `FreeTrain.exe`, plus a byte/section comparison of `DirectDraw.AlphaBlend.dll`. Classify each difference (timestamps, MVIDs, compiler codegen, genuine source drift) in a short table. If it's clean, the reconstruction is an accepted secondary oracle, and items 1–2 need no duplication against the official package.

### 5. Scene smoke screenshots (last)

One VM, official package, 1024 x 768 x 32-bit, VirtualBox lossless PNG. Nine scenes from five hand-built saves, declared in `fixtures/renderer-oracle/catalog.json`:

| Capture | Save | Covers |
| --- | --- | --- |
| `terrain-day` | `terrain-elevation-water-v1` | Elevation, slopes, shoreline, water |
| `terrain-night` | `terrain-elevation-water-v1` | Night palette |
| `terrain-water-cut` | `terrain-elevation-water-v1` | Height cutting |
| `transport-day` | `transport-structures-v1` | Road, rail, station, bridge, 2x2 building, train |
| `transport-labels` | `transport-structures-v1` | GDI station names (review region only, never exact-compared) |
| `transport-preview` | `transport-structures-v1` | Alpha construction preview |
| `directional-day` | `directional-content-v1` | N/S/E/W platforms, trains, and occlusion in the fixed camera |
| `season-summer` | `season-summer-v1` | Summer mountain palette |
| `season-winter` | `season-winter-v1` | Winter mountain palette and winter ground chip |

**Decision (approved 2026-11-01): directional content keeps its own save and a single screenshot.** The approved draft folded directional content into `transport-day`. That doesn't fit: the directional layout uses all four edges of its 30 x 30 map, and the transport map is already full. The transport map is not to be redesigned to hold it. Keeping the scenes separate is preferred for characterization anyway:

- They exercise different behavior. `transport-day` covers roads, rail junctions, trains, bridges, structures, and layering between object types. `directional-day` covers N/S/E/W orientation, sprite selection, occlusion, and draw order in the fixed quarter view.
- Overlapping sprites in a crowded combined scene could hide the features being characterized.
- A directional regression can be diagnosed without the complexity of the full transport scene.
- It preserves the existing directional layout, designed around the four map edges, at a cost of one save and one screenshot.

The conditional four-capture split mode is dropped. If one viewport cannot show all four islands, record that in `notes` as a known limitation; do not add captures. Spring and autumn are covered by the code-derived tests on palette selection.

**Capture procedure.**

1. One XP SP3 x86 VM snapshot with the network disconnected, containing the unmodified official package. Write `fixtures/renderer-oracle/environment.json` once: XP build, CLR version, `ddraw.dll`/`dx8vb.dll` versions and SHA-256, display mode, VirtualBox version, and graphics controller.
2. Start FreeTrain from the package root and maximize the main window and the Map child. Turn off `Display station names` and `Display drawing range (debug)`, select `Always day`, and pause the Timer.
3. Build each save from `phase2a-fixture-layouts.md` §1–§3. For seasons, build the §4 terrain, advance at `Ultra` to July 1 and save `season-summer-v1`, then advance to January 1 and save `season-winter-v1`. Record the status-bar clock string each time. Never resave a save after its hash is recorded.
4. Capture each scene with the hypervisor's lossless PNG screenshot. Use the toolbar/View settings each row implies. `transport-labels` turns station names on; `transport-preview` hovers the Condo over the valid site from layouts §2 without clicking. Park the pointer outside the map except for the preview.
5. Write one sidecar `screenshots/<capture>.json` per PNG (format in `fixtures/renderer-oracle/README.md`): hashes, view state, and the exact rectangle(s) of deterministic map pixels. Excluded regions (labels, cursor) go in `reviewRegions`.
6. Restore the snapshot, reload `terrain-elevation-water-v1` without saving, and recapture `terrain-day` into `reproduction/`. That is the only repetition. Validation requires its exact regions to be pixel-identical to the primary.

Git history is the immutability mechanism: evidence lands in one commit, tagged `phase2a-evidence`. Replacing evidence is a new commit with a reason. There is no separate SHA manifest or approval state.

## Tooling

`eng/renderer-oracle.ps1` replaces the 1,110-line paired validator:

- `-Action Validate` checks the catalog, every present sidecar's save and screenshot hashes, PNG decodability, rectangle bounds, and stray files. It also exact-compares the reproduction against its primary. Missing captures are reported as pending. Add `-RequireComplete` to make pending captures a failure, for the exit gate.
- `-Action Compare -InputPath a.json -OtherInputPath b.json` reports exact differing-pixel counts per shared region, for example to compare a managed-backend render against a reference.

The paired capture/comparison schemas and templates, the approval manifest, CRC/chunk/APNG/`CgBI` checks, cross-VM environment comparison, the pointer-policy taxonomy, and the conditional directional split mode are removed.

## Dependency change

Phase 2B no longer waits for scene screenshots. Items 1, 3, and 4 can start immediately on Win11; item 2 needs one VM session; item 5 can happen in parallel and gates nothing except the scene-smoke portion of the exit gate.

## Exit gate (maps onto `renderer-compatibility.md`)

- **Every facade operation has an executable specification:** native vectors (item 1) plus XP dumps (item 2) together cover the operation list.
- **Coordinate conversion and voxel traversal have coverage:** item 3.
- **Representative scenes have provenance-tagged reference images:** item 5.
- **The managed implementation can be tested automatically:** items 1–3 run in CI with committed vectors.
- **Unknown legacy behavior is listed:** weather (only `none` is reachable in r389), dirty-region repaint sequencing, and any case the harnesses cannot reach.

## Footprint

| | Paired-VM plan | Approved plan |
| --- | --- | --- |
| Procedure docs | ~630 lines | this page |
| Validator | 1,110 lines | 188 lines |
| Schemas/templates | ~1,100 lines | none |
| VMs | 2, kept rendering-equivalent | 1 |
| PNGs | 42–54 | 10 (9 scenes + 1 reproduction) |
| Pixel modes covered | 32-bit only | 555, 565, 24, 32 |
| Runs in CI | none of the oracle | primitive vectors, dumps, code-derived tests |
