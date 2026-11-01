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

The legacy DirectDraw renderer is not required to run on the Windows 11 development machine or in normal CI. Each oracle answers a different question; precedence applies only where two describe the same output:

1. `native-vector`: the shipped `DirectDraw.AlphaBlend.dll` executed against fake surfaces on Windows 11 (`fixtures/native-vectors/`). This is authoritative for `bltAlpha`, `bltShape`, `bltColorTransform`, `bltHueTransform`, and night darkening, in every pixel mode.
2. `captured-legacy-dump`: surface-memory dumps from a console harness run once in an XP VM. This is authoritative for DirectDraw-owned behavior: `bltFast`, `blt`, stretch, color key, clipping, `fill`, `HitTest`, polygon/box, and bitmap capture.
3. `code-derived`: characterization tests of coordinate conversion, voxel traversal, and season/day-night resource selection.
4. `captured-official-release`: scene smoke screenshots of the official SourceForge release in one XP VM (`fixtures/renderer-oracle/`).
5. `historical-reference` and `manually-approved`: known-good historical screenshots and manually reviewed reference images.

A one-time build diff measures how far the source-built reconstruction drifts from the official release. It is evidence about the compared artifacts, not proof of runtime equivalence, so no Phase 2A oracle depends on it; a claim that the reconstruction renders identically needs runtime evidence. The values `captured-legacy` and `captured-reconstructed-legacy` are not used for new evidence. Renderer characterization is not gated on reconstructing VCR; preserve VCR source/binaries separately.

The approved plan, procedures, and exit-gate mapping are in `phase2a-slim-plan.md`. Native vectors and code-derived tests can start immediately; scene screenshots gate only the scene-smoke part of the exit gate.

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
