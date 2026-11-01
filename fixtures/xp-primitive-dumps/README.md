# XP primitive dumps

Provenance `captured-legacy-dump`: results of the DirectDraw-owned facade operations, executed once by the real runtime in the XP SP3 x86 VM through a packaged `DirectDraw.net.dll`. The program is `eng/xp-primitive-dump/XpPrimitiveDump.cs`. The runbook is item 2 of `docs/modernization/phase2a-slim-plan.md`.

**Status: pending.** No dumps have been captured yet. This page fixes the case list and format the capture will produce.

## Layout

```text
environment.json                  VM facts: OS, CLR, .NET 3.5, DirectX, VirtualBox, guest additions, video device, module versions/hashes
reconstructed/<mode>/index.json   source-built package (.artifacts/legacy-build/current/package/Debug)
reconstructed/<mode>/<id>.bin
official/<mode>/index.json        DirectDraw.net.dll + Interop.DxVBLib.dll from FreeTrain20070604.zip
official/<mode>/<id>.bin
```

`<mode>` is the desktop pixel format the surfaces inherit: `32`, `565`, `555`, or `24`.

`index.json` records the package label and the SHA-256 of `DirectDraw.net.dll`, `Interop.DxVBLib.dll`, and `DirectDraw.AlphaBlend.dll`. It also records the pixel format masks and the memory access method. For each case it records:

| Field | Meaning |
| --- | --- |
| `control` | A control case; see below. |
| `dst`, `src` | `[width, height, pitch]` of each surface. DirectDraw chooses the pitch. |
| `args`, `points`, `seeds` | Inputs. Seeds drive `System.Random` for the seeded pixel pattern. |
| `colorKey` | ARGB passed to `sourceColorKey`, whether it was set, and its packed value. |
| `color` | ARGB passed to `fill` and its packed value. |
| `clip`, `resetClip`, `clipEffective` | `clipRect` as set, whether `resetClipRect()` followed, and the getter's value afterwards. |
| `results` | `HitTest` result per point: `true`, `false`, an HRESULT, or an exception type. |
| `drawState` | The surface's dx7vb draw state before `drawBox`. |
| `error` | `none`, the HRESULT of a `COMException`, or another exception type. A DirectDraw error is characterized behavior, not a harness failure. |
| `blocks` | `[name, bytes]` for each block of `<id>.bin`, in order. |
| `changedPixels`, `changedBounds` | Destination pixels that changed, and their bounds `[x1, y1, x2, y2)`. |
| `paddingIntact` | Scanline padding still `0xA5` (raw access only, otherwise `null`). |
| `sourceUnchanged` | The source (or, for `createBitmap`, the surface) was not modified. |
| `sha256` | SHA-256 of `<id>.bin`. |

Block contents:

- A surface block is the locked memory, `pitch * height` bytes. The tool fills scanline padding with `0xA5` before the operation, so a write into the padding shows up.
- If `lpSurface` is unusable (`access: locked-pixel`), the tool reads each pixel with `GetLockedPixel` and writes `width * bpp` bytes per row instead.
- `image` and `bitmap` blocks are `Format32bppArgb`, `width * 4` bytes per row.
- Block names: `src`, `dstBefore`, and `dstAfter` for blits, fills, and draws; `surface` and `bitmap` for `createBitmap`; `image` and `surface` for `createFromImage`; and `image`, `sprite`, `dstBefore`, and `dstAfter` for `createSprite`.

Seeded surfaces use values restricted to the RGB masks. In a keyed pattern (blit sources and `HitTest`), every pixel with `(x + 3y) % 5 == 0` is the key, and each remaining pixel with `(x + 3y) % 7 == 0` is black. The key is magenta, `0xFFFF00FF`.

## Case list (50 per mode)

`cases.txt` is the committed case list, the output of `XpPrimitiveDump list`. `-Action Build` fails when the program's list drifts from it (`-WriteCaseList` accepts the change), and every dump must hold exactly these cases in this order.

The 11 cases marked `control` use plain inputs any working DirectDraw handles. Each must return no error, and each must change destination pixels; for `hitTest-key`, at least one point must return `true`. (`createBitmap` and `createFromImage` controls need only return no error.) A control that fails makes the run a harness failure. That keeps a run in which every operation failed from passing as a characterization.

A run with any harness failure writes only `<mode>.partial` for diagnosis and exits 1. A clean run renames that to `<mode>`. Every run into the same output root must see the same `environment.json`: a mismatch is a harness failure, and its facts go to `environment.mismatch.json`. So does omitting `--vbox` or `--graphics`. The geometries are those of `eng/native-vectors/NativeVectorProbe.cs`. Because DirectDraw picks the pitch, `odd-width` takes the place of the probe's chosen padding.

| Geometry | dst | src | dest | source rect |
| --- | --- | --- | --- | --- |
| `aligned` | 16x8 | 16x8 | (0, 0) | (0, 0)-(16, 8) |
| `odd-width` | 17x9 | 13x7 | (2, 1) | (0, 0)-(13, 7) |
| `negative-dest` | 16x8 | 12x6 | (-3, -2) | (0, 0)-(12, 6) |
| `overrun` | 16x8 | 12x6 | (9, 5) | (0, 0)-(12, 6) |
| `sub-rect` | 16x8 | 12x6 | (1, 1) | (3, 2)-(10, 5) |

| Cases | Facade call | What varies |
| --- | --- | --- |
| `bltFast-key-<geometry>` (5), `bltFast-nokey-{aligned,sub-rect}` | `bltFast(x, y, src, rect)`: always `DDBLTFAST_SRCCOLORKEY`, no managed clipping | Source key set or never set |
| `blt-key-<geometry>` (5), `blt-nokey-{aligned,negative-dest,overrun}` | `blt(Point, src, Point, Size)`: `Util.clip`, `DDBLT_KEYSRC` when keyed | Keying, clipping by the surface |
| `blt-key-truncated-aligned` | as above | Key `0xFFFA03FA`, which packs to magenta in 16-bit only |
| `blt-clip-{inner,beyond-surface,disjoint,reset}-aligned`, `blt-clip-inner-negative-dest` | `clipRect` set to (3,2,7,3), (-5,-5,100,100), (20,20,4,4); `resetClipRect()` | Setter intersection, empty clip, reset |
| `bltStretch-{up2x,down,odd,key-up2x,negative-dest,overrun,mirror,clip-up2x}` | `blt(dx1, dy1, dx2, dy2, src, sx1, sy1, sx2, sy2)` | Stretch ratio, keying, and the 1:1 source adjustment that `Util.clip` applies even when stretching. `mirror` passes dx1 > dx2. |
| `fill-whole-{odd,white,dim,clip}` | `fill(Color)` (fills the clip rect) | `0xFF874321` (low bits in every channel), white, `0xFF080408` (zero in 16-bit), inner clip |
| `fillRect-{inner,negative,overrun,outside,clip}` | `fill(Rectangle, Color)` | Rect intersected with the clip; `outside` makes it inverted |
| `hitTest-key`, `hitTest-nokey` | `HitTest(x, y)` at 12 points, including `x == width`, `y == height`, and negatives | Key set (compares with the key) or not (compares with 0) |
| `drawPolygon-{diamond,negative,overrun}` | `drawPolygon` (GDI `Polygon`, default DC pen and brush) | Isometric diamond, off the top-left, off the bottom-right |
| `drawBox-{inner,negative,overrun}` | `drawBox(Rectangle)` (dx7vb `DrawBox`, default draw state) | Same three placements |
| `createBitmap-{aligned,odd}` | `createBitmap()` (GetDC + BitBlt into a 32bppArgb `Bitmap`) | Even and odd width |
| `createFromImage-odd` | `DirectDraw.createFromImage` (GDI+ `DrawImage` into the surface DC) | Seeded opaque 17x9 image |
| `createSprite-blt` | `DirectDraw.createSprite`, then `blt(Point(-2, 1), sprite)` | Key taken from the image's top-left pixel |

The `blt` overloads `blt(Point, src)` and `blt(Point, src, Rectangle)` share the private `blt(RECT, src, RECT)` with the cases above, so they are not repeated.

## Checks

```powershell
.\eng\xp-primitive-dump\xp-primitive-dump.ps1 -Action Verify                       # integrity of this tree
.\eng\xp-primitive-dump\xp-primitive-dump.ps1 -Action Check -OtherPath <fresh>     # this tree vs a fresh run
.\eng\xp-primitive-dump\xp-primitive-dump.ps1 -Action Check `
    -Path fixtures\xp-primitive-dumps\reconstructed -OtherPath fixtures\xp-primitive-dumps\official
```

Both actions check every dump: its case list against `cases.txt`, its directory name against its `pixelMode`, block sizes, SHA-256 values, stray files, and leftover `.partial` directories.

- `Verify` is for this whole tree. It also requires `reconstructed\32` and `official\32`, the same set of modes for both packages, nothing else at the root, and an `environment.json`. That file must have every field filled in (operator fields not `unrecorded`), a CLR 2 version, and hashed `ddraw.dll`, `dx7vb.dll`, and `gdiplus.dll`.
- `Check` then requires both trees to hold the same dumps, the same pixel format, and identical case records. Package hashes are allowed to differ. For each case that differs, it reports the first differing block and byte offset.
