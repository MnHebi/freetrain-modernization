# Phase 2A: paired legacy renderer oracles

> **Superseded 2026-11-01** by `phase2a-slim-plan.md`. This document is retained as preservation chronology. Its source-derived evidence (season, night, cut, label, and controller-interaction paths) remains valid reference material. The paired-VM procedure, capture matrix, schemas, approval manifest, and validator commands below no longer apply; the schemas and manifest were removed from `fixtures/renderer-oracle/`. Follow the slim plan for new captures.

## Scope

Phase 2A records representative output from two independently identified Windows XP SP3 x86 VMs. It does not add renderer tests, replace DirectDraw, change `QuarterViewDrawer`, introduce `ManagedSurface`, or change production rendering behavior. VCR is not part of this procedure; all images are lossless full-console PNG captures made by VirtualBox.

The oracle order is strict:

1. `official-release`, provenance `captured-official-release`: the unmodified contents of `FreeTrain20070604.zip`, SHA-256 `70374a836a9f1bc28b16dd65c323fc1b21b4142f10344d19335a65690c16c23d`, are the authoritative statement of shipped behavior.
2. `reconstructed-legacy`, provenance `captured-reconstructed-legacy`: the Phase 1 source-built r389 package is a secondary oracle only after comparison with the official release and the clean-snapshot gate pass.

Other permissible Phase 2 provenance values are `native-vector`, `historical-reference`, `manually-approved`, and `code-derived`. Do not use the ambiguous value `captured-legacy` for new captures. Any classified mismatch retains the official image as authority; an unexplained mismatch prevents approval and prevents the reconstruction from serving as an oracle.

The legacy UI has one fixed quarter-view projection and no camera-rotation command. Directional coverage therefore comes from north/south/east/west **content** in a fixed view. No rotated-camera fixture is permitted.

Repository evidence behind the controllable states is:

- `core/world/Time.cs`: season is derived from the saved clock month; day is 06:00 through 17:59.
- `core/views/GlobalViewOptions.cs` and `core/framework/MainWindow.cs`: the toolbar exposes `Day and night`, `Always day`, and `Always night` modes.
- `core/views/map/MapView.cs`: height-cut choices include `None`, `Water level`, and levels relative to water.
- `core/views/QuarterViewDrawer.cs`: station names are drawn through GDI with `MS PGothic` and must not be mixed into exact world-pixel approval.
- `core/views/map/MapView.cs`: r389 assigns `NullWeatherOverlay.theInstance`; the sample `WeatherOverlayImpl` construction remains commented out. Weather has no reproducible production control in this revision.

Season coverage is statically proven by three core paths. `core/framework/graphics/Picture.cs:84-88` parses seasonal overrides and line 180 selects a loader by `Clock.season` and night mode. `core/framework/ResourceUtil.cs:103-105` selects a different ground chip in winter. `core/world/terrain/MountainVoxel.cs:181` indexes the season palette, and lines 500-504 load spring/summer/autumn/winter palettes from `core/res/mountainPalette.xml`. Six bundled plug-in manifests (farmland, fence, creek, `land.477`, ricefield, and forest) contain 50 seasonal override declarations, but they introduce payload variability. The minimum fixture therefore uses core exposed, non-flattened mountain slopes in all four seasons and a broad empty-ground area to exercise the winter ground chip. Do not add a seasonal plug-in merely to strengthen the scene unless identical relevant payload hashes are recorded for both packages.

## Fixed capture environment

Use two separate VMs with rendering-equivalent named reference states and do not change their graphics, display, or font configuration after the first approved capture:

- Guest: Windows XP SP3 x86 in both VMs; record exact product/build/service pack/architecture, installed CLR/Framework versions, DirectX runtime version, and `dx8vb.dll` version/SHA-256
- Display: 1024 x 768, 32-bit color, 96 DPI, no hypervisor scaling
- Desktop: identical Windows Classic theme, wallpaper, font smoothing; no notifications or overlapping windows
- Hypervisor: record VirtualBox version, graphics-controller model, video-memory size, 3D setting, guest display-driver name/version, and Guest Additions presence/version
- FreeTrain: one VM contains only the official release package; the other contains only the reconstructed package; launch each from its package root
- Capture mechanism: hypervisor full-console screenshot saved directly as PNG

Give the VMs distinct immutable identifiers and roles but the same environment-equivalence group. Record each snapshot UUID/export hash. For the official package record archive filename/hash, `FreeTrain.exe` hash, and hashes of any scene-relevant plug-in payloads. For the reconstruction record Git commit, preservation build ID, package-manifest hash, executable hash, and relevant payload hashes. The established reconstructed executable SHA-256 is `6449145b79d4f7d2b287ae8a9f7465bfb5c418c58903dfd847ef6530fe423c15`.

> Legacy saves use an unsafe object serializer. Load only fixtures created in these controlled VMs or historical saves whose custody has been explicitly approved. Never deserialize an untrusted save on the host or in a modern game process.

## Minimal fixture matrix

All fixture and capture IDs below are declared in `fixtures/renderer-oracle/catalog.json`. The names are stable; if a scene must be rebuilt after approval, create a `-v2` fixture rather than changing `-v1`.

Use `phase2a-fixture-layouts.md` for coordinate-addressed ASCII tile plans, terrain-corner click schedules, object anchors, interaction endpoints, and directional framing targets. The diagrams define the intended official-VM construction; the reconstructed VM must still load the same save bytes rather than rebuild them.

| Save fixture | Capture IDs | Required coverage | Creation source |
| --- | --- | --- | --- |
| `terrain-elevation-water-v1` | `terrain-day-none`, `terrain-night-none`, `terrain-day-water-cut`, `terrain-day-underground-cut` | Flat land, stepped elevation, slopes, shoreline, water fill/color, forced day/night, water-level cut, one level below water | Manual in XP from `Empty map`, 30 x 30 x 6 |
| `transport-structures-v1` | `transport-day-neutral`, `transport-day-labels`, `transport-preview-valid`, `transport-preview-clipped`, `transport-overlay-road`, `transport-overlay-rail`, `transport-restored-full` | Roads, rail, platform/station, paused train, bridge/elevated rail, 2 x 2 building, alpha construction previews, line/shape overlays, station GDI labels, full redraw after restore | Manual in XP from `Empty map`, 30 x 30 x 6 |
| `directional-content-v1` | `directional-day-neutral`, or conditionally four declared directional IDs | Four separated N/S/E/W content variants using platform direction, straight/slope rail, and trains where placement permits; draw-order and occlusion remain visible in one or more fixed-camera viewports | Manual in XP from `Empty map`, 30 x 30 x 6 |
| `season-spring-v1` | `season-spring-day` | Exposed MountainVoxel slopes using the core spring palette at a recorded April clock time | Manual season base save |
| `season-summer-v1` | `season-summer-day` | Same core slopes using the summer palette at a recorded July clock time | Save As from season base after clock advance |
| `season-autumn-v1` | `season-autumn-day` | Same core slopes using the autumn palette at a recorded October clock time | Save As from season base after clock advance |
| `season-winter-v1` | `season-winter-day` | Same slopes using the winter palette plus visible empty ground using the core winter chip | Save As from season base after clock advance |

The default plan is 16 primary states and 5 clean-snapshot repetitions per oracle: 42 PNGs total and 16 official-versus-reconstructed comparison records. The repeat IDs are `terrain-day-none`, `terrain-night-none`, `transport-day-neutral`, `directional-day-neutral`, and `season-winter-day`.

First assess the directional scene at unscaled 1:1 view. If one viewport is adequate, set `capturePlan.directionalAlternative.adequacyDecision` to `adequate` and retain `directional-day-neutral`. If all four variants cannot be represented legibly, set `mode` to `split` and the decision to `inadequate`, then use `directional-north-day-neutral`, `directional-south-day-neutral`, `directional-east-day-neutral`, and `directional-west-day-neutral`, each with its own recorded scroll position. All four then enter the clean-repeat gate. This conditional representation has 19 primary states and 8 repetitions per oracle: 54 PNGs and 19 comparison records. It does not add a new scene category and never permits camera rotation, mirroring, or post-processing.

No historical save is required for this minimum set. There are no `.ftgd` or `.ftgt` files in the imported r389 repository. An externally supplied historical save may be added later only as a separately hashed fixture with its source archive and custody recorded; it must not silently replace one of the manual fixtures.

Weather is deliberately absent from the screenshot matrix. The only reproducible r389 state is `weather = none`. Activating the dormant sample code would change production behavior and is outside Phase 2A. This is an explicit unknown for later code-derived or managed-backend testing, not a missing operator step.

## Evidence layout and approval

Stage guest saves under `C:\FreeTrainOracle\staging`; do not make the repository a writable XP shared folder. Let the hypervisor write screenshots to a host staging directory such as `.artifacts/phase2a-staging`. After shutting down or reverting the guest, copy reviewed candidates into:

```text
fixtures/renderer-oracle/
  saves/<fixture-id>.ftgd
  screenshots/official-release/{primary,reproduction}/<capture-id>.png
  screenshots/reconstructed-legacy/{primary,reproduction}/<capture-id>.png
  metadata/official-release/{primary,reproduction}/<capture-id>.json
  metadata/reconstructed-legacy/{primary,reproduction}/<capture-id>.json
  comparisons/<capture-id>.json
  masks/...
  manifests/approved-files.sha256
```

Each screenshot has one metadata sidecar conforming to `capture-metadata.schema.json`. In addition to fixture, save, package, state, and screenshot hashes, it records the structured VM graphics fields, map-client rectangle and scrollbar positions, controller/overlay state, exact full-screen interaction coordinates, deterministic rectangles, GDI/font rectangles, and cursor rectangles. Each logical capture also has a `comparison-metadata.schema.json` record.

Coordinates are in full-screen PNG pixels with `(0,0)` at the screenshot's top-left. Exact regions contain only deterministic map pixels. Exclude XP desktop, window chrome, MDI background, menu/toolbar/status text, scrollbars, controller windows, cursor, station labels, and tooltips. The label capture names station-label rectangles in `gdiFontRegions` with `manual-review`; `transport-day-neutral` keeps labels off.

Pointer policy depends on interaction state and resolves the earlier contradiction:

- Neutral, label, cut, season, and redraw captures use `parked`; record the pointer coordinate and move it outside every deterministic region, or prove VirtualBox did not capture it.
- Building previews use `pointer-hover`; leave the pointer on the tile producing the preview and record its exact hotspot coordinate. Do not move it off-map.
- Road/rail pending overlays use `click-move-preview`; record both `anchor-click` and final `current-pointer`.
- Every active point lies inside the recorded map-client rectangle and is reproduced exactly in both VMs. If VirtualBox includes the cursor, declare a tight `pointerCursorRegions` mask; if it omits the cursor, record `not-captured-by-hypervisor` but retain the coordinates.

Measure at an unscaled 1:1 console using the cursor hotspot. When the cursor is absent from the PNG, measure the intended tile/overlay hotspot against the recorded map-client origin and verify it from the visible preview. Record coordinates before changing the controller.

This interaction choice is source-derived, not an operator guess. `core/controllers/structs/StructPlacementController.cs:175` updates the transparent building base on mouse move. `core/controllers/AbstractLineController.cs:168-193` (road/special line) and `core/controllers/rail/RailRoadController.cs:196-244` establish an anchor with the first click, update `currentPos` on a subsequent button-up-free mouse move, and commit on the second click. `core/views/map/MapView.cs:255-305` distinguishes scroll drag from controller clicks and dispatches controller movement only while not dragging. Therefore the required overlay capture is first click, release, then move and hold position for capture; it is not a drag gesture.

Approval is a one-way evidence operation:

1. Keep files in host staging while one oracle side is incomplete. Use exactly the same save bytes in both VMs wherever compatible; never open and resave merely to transfer them.
2. Add both primary sidecars/PNGs, required clean repetitions, and the completed comparison record with `approvalStatus = candidate`; then change the catalog capture to `candidate`.
3. Run `eng/renderer-oracle.ps1 -Action Validate`, exact-compare deterministic regions, and classify every difference. Official-release behavior has precedence; `unexplained` blocks approval.
4. Change all sidecars and the comparison record to `approved` after review.
5. Generate `manifests/approved-files.sha256` with `-Action Manifest` and validate again.
6. Commit approved evidence. Never edit an approved save, PNG, sidecar, comparison, or mask; make a versioned replacement.

The manifest contains approved saves, both capture runs, sidecars, comparisons, and masks. Validation recomputes hashes and rejects changed, missing, added, or unsealed evidence.

## XP operator checklist

### One-time setup

1. Restore two distinct, rendering-equivalent clean reference states and keep both network adapters disconnected. Confirm 1024 x 768, 32-bit color, 96 DPI, identical Classic desktop/font settings, and unscaled VirtualBox console output. Do not install convenience software in either oracle.
2. Create `C:\FreeTrainOracle\staging` in each guest. Record each VM/role/reference-state identifier, exact XP/CLR/DirectX versions, `dx8vb.dll` version/hash, VirtualBox version, graphics controller, VRAM, 3D setting, guest display driver/version, Guest Additions, display, DPI, theme, wallpaper, and font smoothing. Resolve a rendering-relevant mismatch before capture.
3. Put only the official package in the official VM and only the reconstruction in the reconstructed VM. Record all required package hashes. Start from each package root, maximize the main window and Map MDI child, measure the map-client rectangle, and record both scrollbar positions.
4. Open `Options...`; turn off `Display station names` and `Display drawing range (debug)`. Leave trees visible. Use the toolbar's `Always day` button.
5. Open the Timer drop-down and choose `Pause`. Keep the clock paused for every capture except while intentionally advancing a season.
6. Verify once whether VirtualBox PNG capture includes the pointer. Park it off exact regions only for `parked` states; for previews/overlays follow the recorded active-coordinate rule above. Wait for tooltips to disappear. Never use Print Screen, RDP, JPEG, clipboard conversion, or VCR.
7. Construct and save each scene once in the official VM. Shut down, hash and copy the immutable save through host staging, verify that hash in the reconstructed VM, and load without saving. Reproduce identical state, window geometry, scroll offsets, and interaction coordinates. If the reconstruction cannot load the official bytes, stop that capture pair and record the incompatibility; do not repair/resave the file.

### Terrain, elevation, water, and cuts

1. Choose `File > New Game... > Empty map`; name it `P2A terrain elevation water v1` and enter size `30 x 30 x 6`. Pause immediately and force `Always day`.
2. Open `Construction > Modify Terrain...`. Leave a broad flat center. With `Raise`, create: one isolated raised corner, a two-level plateau, a one-tile-wide ridge, and at least two diagonal slope transitions. Keep each feature separated by two flat tiles so its sprite edges are visible.
3. Select `Lower` and lower a connected 4 x 4 basin below the initial water level (`z/4`, therefore level 1 for a six-level world). Leave a stepped shoreline adjacent to the plateau.
4. Close/cancel the terrain controller. Save as `C:\FreeTrainOracle\staging\terrain-elevation-water-v1.ftgd`. Do not overwrite it after its first candidate hash is recorded.
5. With station names off, scrollbars at minimum, and height cut `View > Height Cutting > None`, capture `terrain-day-none.png`.
6. Click `Always night`, allow the map to redraw, and capture `terrain-night-none.png`. Return to `Always day`.
7. Choose the map child's `View > Height Cutting > Water level`; capture `terrain-day-water-cut.png`.
8. Choose the `-1` height-cut entry; capture `terrain-day-underground-cut.png`. Return the cut to `None` before leaving the fixture.

### Transport, structures, previews, overlays, and labels

1. Create another `Empty map`, name it `P2A transport structures v1`, size `30 x 30 x 6`; pause and force `Always day`.
2. Lay a separated road sample with the `Road Construction` command using `Two-lane road (15 sprites)` (`{7254CD19-38B1-42DB-84E3-88F9A5C88E42}`): straight, corner, T-junction, and crossing patterns.
3. Use `Rail > Lay Rail...` to make a ground loop with straight, diagonal/turn, junction, and crossing pixels. Add a station/platform using `Build station`; use `Local station 1 (L)` (`{E1C41DF8-6C9B-465d-A798-2624551AC4FD}`) and give it the ASCII name `P2A Station`.
4. Select `Bridge` from the bundled `Bridges & Tunnels` special-rail contribution (`{874B8BFD-1EF4-4828-9C5A-D0EA1049D28D}`) and span the water basin or a lowered trench. Include visible supports and at least one ground-to-elevated transition.
5. Use `Building construction` to place `Condo (2x2)` (`{9F3E82AD-2A49-4aef-954C-E872F535B3D8}`) with empty tiles on every side so its multi-voxel overlap is visible.
6. Use `Rail > Buy Trains...` to buy `FT1 Series` (`{F3604C61-D0D5-4c9c-ADD6-405610FA6250}`), then `Place trains` to put it on an unobscured straight and on/adjacent to the bridge if the controller permits. Pause, wait for all motion to stop, close every controller, and save `transport-structures-v1.ftgd`.
7. With labels off and no controller, capture `transport-day-neutral.png`.
8. Open `Options...`, turn on `Display station names`, close the dialog, and capture `transport-day-labels.png`. Turn labels off again. In its metadata, put the station text rectangle only in `gdiFontRegions`; keep a separate exact map rectangle that excludes it.
9. Open `Building construction`, select the same Condo, and hover without clicking over a valid empty 2 x 2 site. Record the full-screen pointer hotspot and capture `transport-preview-valid.png` without moving it. Repeat at the top/left clipping boundary for `transport-preview-clipped.png` with its own coordinate. Mask a captured cursor separately; cancel without placement.
10. Open `Road Construction`, click and release the initiating point, record `anchor-click`, move with no button held so the pending overlay crosses flat terrain and a slope, record `current-pointer`, and capture without moving. Cancel without the second click so nothing is committed.
11. Repeat the exact interaction recording for the pending rail overlay, capture `transport-overlay-rail.png`, then cancel without committing.
12. Minimize and restore the map MDI child (or the main window if the child cannot be minimized), wait for a complete redraw with no controller, and capture `transport-restored-full.png`. It must visually match the neutral scene within the recorded exact region.

If a named contribution is absent from the reconstructed package, stop that fixture and record the missing plug-in/package path. Do not substitute a visually similar contribution without giving the fixture a new ID and updating the catalog.

### Fixed-camera directional content

1. Create `P2A directional content v1`, `30 x 30 x 6`; pause, force `Always day`, labels off, and height cut `None`.
2. Build four separated content islands in the north, south, east, and west parts of the map. In each island, use the platform direction selector matching that island (N, S, E, or W), a straight rail approach, a slope/elevated transition where possible, a one-sided station or structure, and an FT1 train oriented/placed in the approach direction.
3. Try the same fixed quarter-view viewport and ensure tall sprites overlap background content. At 1:1 scale, record whether all four variants and their draw order are adequate. Do not rotate, mirror, or post-process.
4. Save `directional-content-v1.ftgd` and close controllers. If adequate, set the catalog decision to `adequate` and capture `directional-day-neutral.png`. If inadequate, record why, set `mode = split` and decision `inadequate`, and capture the four declared N/S/E/W IDs at fixed-camera scroll positions recorded in their metadata.

If the train placement controller cannot force all four headings while paused, retain the four rail/platform/structure variants and record exactly which train headings were achieved. That shortfall is a candidate limitation, not permission to invent camera rotation.

### Seasons

1. Create a core-only terrain scene with a broad empty-ground area and several exposed, non-flattened MountainVoxel slopes of different heights/orientations; use no trains, seasonal plug-in scenery, structures, or active controllers. Save the April state as `season-spring-v1.ftgd` and capture `season-spring-day.png` with `Always day`.
2. Use the Timer drop-down `Ultra` speed only to advance the clock. At July 1, pause, force `Always day`, save as `season-summer-v1.ftgd`, then capture `season-summer-day.png`.
3. Repeat at October 1 for `season-autumn-v1.ftgd` / `season-autumn-day.png`.
4. Repeat at January 1 of the next year for `season-winter-v1.ftgd` / `season-winter-day.png`.
5. Record the exact status-bar clock string. Month determines season; `Always day` removes night ambiguity. Verify that slopes remain exposed in every save and that broad empty ground is visible in winter. Never advance or resave a season fixture after its candidate hash is recorded.

Perform the construction steps only in the official VM. The reconstructed VM loads the exact transferred save bytes and reproduces each recorded state without saving.

### Reconstructed-VM pass

1. Restore the reconstructed VM reference state and verify every structured environment field against the official VM record before launching FreeTrain.
2. Copy in each official-created save through host staging, compute its SHA-256 in the guest, and confirm it matches the repository candidate. Load it without saving.
3. Reproduce the primary capture's map-window geometry, scroll positions, paused clock/day-night/season, cut, labels, controller state, and full-screen pointer/anchor coordinates exactly. Capture the reconstructed primary PNG.
4. If a save fails to load or a named contribution/payload is unavailable, stop that pair, retain the official evidence, and record the incompatibility. Do not resave, rebuild the scene independently, or substitute content.

### Clean-snapshot repetition in both VMs

From each VM's clean reference state, launch fresh and recapture `terrain-day-none`, `terrain-night-none`, `transport-day-neutral`, the active directional capture (all four in split mode), and `season-winter-day`. Re-copy and hash the same save bytes and reproduce the primary metadata exactly. Store these under the `reproduction` paths and exact-compare primary versus repetition within that oracle.

## Host-side validation commands

From the repository root:

```powershell
# Validate the plan now, and all candidate/approved evidence after capture.
.\eng\renderer-oracle.ps1 -Action Validate

# Check a staged PNG before adding its metadata.
.\eng\renderer-oracle.ps1 -Action VerifyPng `
  -InputPath .artifacts/phase2a-staging/terrain-day-none.png

# Exact-compare identically declared deterministic regions. Use this for
# official vs reconstructed and primary vs clean-snapshot repetition.
.\eng\renderer-oracle.ps1 -Action CompareRegions `
  -InputPath fixtures/renderer-oracle/metadata/official-release/primary/terrain-day-none.json `
  -OtherInputPath fixtures/renderer-oracle/metadata/reconstructed-legacy/primary/terrain-day-none.json

# Produce a sorted screenshot catalog without altering evidence.
.\eng\renderer-oracle.ps1 -Action Catalog `
  -OutputPath .artifacts/phase2a-screenshot-catalog.json

# Seal all approved evidence in a deterministic SHA-256 manifest.
.\eng\renderer-oracle.ps1 -Action Manifest `
  -OutputPath fixtures/renderer-oracle/manifests/approved-files.sha256

# Re-run after sealing; this also detects accidental modifications.
.\eng\renderer-oracle.ps1 -Action Validate
```

The tool checks save/screenshot hashes, package/oracle provenance, structured VM graphics metadata, cross-VM rendering-environment equality, identical state/viewport/interaction coordinates and regions, PNG signature/chunks/CRCs/IHDR/IEND, absence of APNG or nonstandard `CgBI`, rectangle bounds, pointer rules, pair classifications, clean repetitions, uncatalogued evidence, and the approved manifest. `CompareRegions` reports exact decoded-pixel ARGB difference counts for each deterministic rectangle; copy those results into the pair-comparison record and classify every nonzero result.

## States not yet reproducible deterministically

- Weather other than `none`: production `MapView` uses `NullWeatherOverlay`; there is no active control or serialized weather state.
- Cross-package save/resource incompatibility: none is currently proven. If the reconstructed package cannot load the exact official-created save or lacks a named payload, that capture pair remains incomplete; do not resave or substitute content.
- All four paused train headings may depend on placement-controller behavior. The fixed content islands remain required; record missing headings instead of rotating the camera.
- One viewport may not show all four directional variants adequately. The catalog's declared fixed-camera four-capture alternative is permitted only after recording the single-view inadequacy.
- Exact season minute matching is operator-sensitive at `Ultra` speed. The saved clock string and hash make each result reproducible, while forced-day mode isolates palette behavior.
- Dirty-region repaint sequences cannot be proven from one screenshot. Phase 2A captures neutral and restored/full-redraw endpoints; executable sequencing belongs to Phase 2B.

## Phase 2A exit gate

Phase 2A is complete when:

1. Both independently identified VMs have an approved primary image/sidecar for every active capture ID, using the same immutable save bytes and identical recorded state, viewport, and interaction coordinates.
2. Official archive/executable and reconstructed commit/build/package hashes are complete. XP/CLR/DirectX and `dx8vb.dll`, VirtualBox controller/VRAM/3D, guest driver/Additions, display, and desktop metadata are structured and rendering-equivalent across the pair.
3. Every PNG passes hash, structural, CRC, and dimension checks. Each capture has an exact region, and GDI/font and captured-cursor regions are masked/reviewed separately.
4. Official-vs-reconstructed exact comparison is recorded for every logical capture. Every mismatch is classified, the official release retains precedence, and no approved record contains an unexplained difference; only then is reconstruction an accepted secondary oracle.
5. Day/night, four core season palettes plus the winter ground chip, terrain/water/cuts, transport/structures/trains, active previews/overlays with coordinates, fixed-camera directional content, labels, and restored redraw are approved. Weather remains explicitly unsupported.
6. Clean-snapshot loads in both VMs reproduce `terrain-day-none`, `terrain-night-none`, `transport-day-neutral`, the active directional capture(s), and `season-winter-day` byte-for-byte within deterministic regions.
7. `manifests/approved-files.sha256` exactly seals approved saves, primary/reproduction PNGs, sidecars, comparison records, and masks. Approved originals are never edited.

Passing this gate authorizes Phase 2B specification/tests. It does not authorize renderer replacement.
