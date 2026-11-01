# Renderer compatibility contract

## Default replacement architecture

The existing public API is the compatibility seam:

```text
QuarterViewDrawer / Sprite / bundled plugins / tools
                         |
             org.kohsuke.directdraw API
                         |
              internal backend boundary
                    /             \
       DirectDraw backend      Managed backend
          temporary               new
```

Phase 3 does not introduce a new public renderer-neutral API by default. `QuarterViewDrawer`, sprites, and bundled plugins should remain unaware of the backend change.

## API surface to preserve

Preserve the namespace and source-level behavior of:

- `DDSurfaceAllocation`
- `DirectDraw`
- `WindowedDirectDraw`
- `ColorMask`
- `Surface`
- `GDIGraphics`

Important operations include:

- Off-screen and sprite surface creation
- Surface lifetime and `size`
- `clipRect` and `resetClipRect`
- `bltFast`
- All `blt` overloads, including stretching and source color keys
- `bltAlpha`
- `bltShape`
- `bltColorTransform`, including vertical flip
- `bltHueTransform`
- Full and rectangular fill
- `sourceColorKey`
- `HitTest`
- Polygon and box drawing
- Bitmap capture and GDI copy operations
- `GDIGraphics.graphics`

Do not “correct” surprising behavior until characterization decides whether it is relied upon. For example, `HitTest` is documented as reporting an opaque pixel but currently compares equality with the color key; this is a specification question, not an early cleanup.

## COM-specific exception

`Surface.handle` exposes `DxVBLib.DirectDrawSurface7` and cannot remain meaningful in a truly DirectDraw-free implementation.

Only three main-tree consumers outside `DirectDraw.net` were found:

1. Surface-loss check in `views/map/MapView.cs`
2. Surface-loss check in `views/map/PreviewMapWindow.cs`
3. Native night-image construction in `framework/graphics/SurfaceLoaders.cs`

No bundled plugin directly accesses the property. The migration should therefore retain `handle` during dual-backend work, move those three behaviors behind facade operations, and remove the COM-typed property only at final cutover. This is the deliberate exception to aggressive API preservation.

## Phase 2 oracle policy

The legacy DirectDraw renderer is not required to run on the Windows 11 development machine or in normal CI. Acceptable evidence sources, in precedence order where they describe the same shipped world output, are:

1. `captured-official-release`: the official SourceForge release in a compatible XP VM
2. `captured-reconstructed-legacy`: the source-built r389 package, after exact comparison to the official release
3. `native-vector`: tests/vectors extracted from the original native pixel routines
4. `historical-reference`: known-good historical screenshots
5. `manually-approved`: manually reviewed reference images
6. `code-derived`: static analysis of coordinate, clipping, and traversal code

The unqualified `captured-legacy` value is deprecated for new evidence because it does not identify package authority.

Phase 2A uses two independently identified, rendering-equivalent XP SP3 x86 VMs. The official release is authoritative. The reconstruction becomes a secondary oracle only after every deterministic difference is exact or classified, no unexplained mismatch remains, and the clean-snapshot gate passes in both VMs. Renderer characterization is not gated on reconstructing VCR: use lossless VirtualBox screenshots and preserve VCR source/binaries separately.

Phase 2A's concrete fixture catalog, metadata contract, immutable-evidence workflow, and XP operator checklist are in `phase2a-legacy-oracle.md` and `fixtures/renderer-oracle/`. Phase 2A only captures and validates the legacy oracle; executable behavioral tests remain Phase 2B work.

## Test taxonomy

### Primitive tests — exact

- Pixel format conversion
- Clipping on each edge and corner
- Negative destination coordinates
- Color-key inclusion/exclusion
- Stretch and copy behavior
- Fixed half-alpha arithmetic and rounding
- Shape masks
- Color-map substitutions
- Hue transforms
- Vertical flip
- Hit testing
- Odd widths and nontrivial strides

Primitive outputs require byte-for-byte equality.

### Complete-world tests — layered

- North/south/east/west directional content variants; the checked legacy UI has a fixed quarter-view camera and no camera-rotation command
- Day/night
- Seasons
- Water and underground cuts
- Transparent voxels
- Rails, platforms, bridges, trains, and multi-voxel structures
- Controller previews and overlay stages
- Weather overlays
- Dirty-region redraw versus full redraw
- Station labels

World pixels should compare exactly where deterministic. GDI/font regions must be compared separately or masked and reviewed so text antialiasing does not hide terrain regressions.

## Phase 2 exit gate

- Every facade operation has an executable specification.
- Coordinate conversion and voxel traversal have test coverage.
- Representative scenes have provenance-tagged reference images.
- The new managed implementation can be tested automatically.
- Unknown legacy behavior is listed explicitly.

The old renderer need not execute in Windows 11 CI.
