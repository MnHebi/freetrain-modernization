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

The legacy DirectDraw renderer is not required to run on the Windows 11 development machine or in normal CI. Acceptable evidence sources are:

1. Legacy renderer capture in a compatible VM or historical machine
2. Tests extracted from native pixel routines
3. Deterministic vectors generated from the original C++ algorithms
4. Known-good historical screenshots
5. Manually reviewed reference images
6. Static analysis of coordinate, clipping, and traversal code

Each fixture must record its origin as `captured-legacy`, `native-vector`, `historical-reference`, `manually-approved`, or `code-derived`.

The functioning disposable XP SP3 x86 runtime is the active `captured-legacy` oracle for Phase 2. Renderer characterization is not gated on reconstructing the optional VCR auxiliary build: use lossless hypervisor screenshots and the documented fixture procedure, not the VCR plug-in. Preserve the VCR source and official binaries separately as historical evidence.

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
