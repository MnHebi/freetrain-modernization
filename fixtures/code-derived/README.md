# Code-derived golden files

Provenance `code-derived`: output of the FreeTrain r389 logic in the Phase 1 **source-built Debug** package's `FreeTrain.Core.dll` (not the official release binaries), run by `eng/code-derived/` without DirectDraw. `provenance.txt` pins that DLL's SHA-256. `tests.txt` pins the test set. Coverage, method, and the characterized quirks are recorded under item 3 of `docs/modernization/phase2a-slim-plan.md`.

One `.txt` per golden table or sequence, LF line endings:

| File | Content |
| --- | --- |
| `draw-*.txt` | Call log of `QuarterViewDrawer.draw(Rectangle, MapOverlay)`: clip rect, then each sprite or voxel draw with its client point and `heightCutDiff` |
| `drawer-ab-to-hv.txt` | `fromABToHV` for edge and negative rectangles |
| `world-inside-border-z1.txt` | `isInsideWorld`/`isBorderOfWorld` over an 8 x 16 x 5 world (`I` inside, `b` inside and border, `.` outside) |
| `time-calendar-season.txt` | Month starts, weekdays, and season changes over one year and the rollover |
| `picture-*.txt` | `Picture` loader table per season (day/night) for code-built and XML pictures |
| `tests.txt`, `provenance.txt` | Expected test names and the source DLL hash, checked before any golden is trusted |
| `mountain-*.txt` | Season and water palettes from `res/mountainPalette.xml`, `fromHSV` samples, and the `selectColor` table (625 corner-height combinations per row, NE major to NW minor) |

```powershell
.\eng\code-derived\run-tests.ps1                 # Check: fail on any difference
.\eng\code-derived\run-tests.ps1 -Action Write   # regenerate (refused if any assertion fails)
```

Regenerate only when a test's inputs change. A Check failure with unchanged tests means the package's `FreeTrain.Core.dll` or the harness changed, not the oracle. After a rebuild that changes the DLL hash, regenerate and confirm that only `provenance.txt` changed. Any other difference in the goldens is a behavior change to review.
