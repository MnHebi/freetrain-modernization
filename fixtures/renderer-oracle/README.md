# Scene smoke references

Repository-side evidence for Phase 2A item 5. Read `docs/modernization/phase2a-slim-plan.md` before adding anything. Build saves from `docs/modernization/phase2a-fixture-layouts.md`.

- `catalog.json` declares the saves, the nine captures, and the one reproduction.
- `environment.json` records the single capture VM once (written with the first capture).
- `saves/<save>.ftgd` holds each save, never resaved after its hash is recorded.
- `screenshots/<capture>.png` + `screenshots/<capture>.json` hold the primary PNG and its sidecar.
- `reproduction/<capture>.png` + `reproduction/<capture>.json` hold the fresh-snapshot recapture.

## Sidecar

```json
{
  "captureId": "terrain-day",
  "save": "terrain-elevation-water-v1",
  "saveSha256": "<64 hex>",
  "screenshotSha256": "<64 hex>",
  "clock": "<status-bar clock string>",
  "view": {
    "dayNight": "always-day",
    "heightCut": "none",
    "stationNames": false,
    "controller": "none",
    "scroll": { "x": 0, "y": 0 },
    "pointer": { "x": 1000, "y": 740 }
  },
  "exactRegions": [ { "id": "map", "x": 0, "y": 0, "width": 0, "height": 0 } ],
  "reviewRegions": [],
  "notes": ""
}
```

Coordinates are full-screen PNG pixels with `(0,0)` at the top left. `exactRegions` contain only deterministic map pixels: no window chrome, scrollbars, labels, tooltips, or cursor. `reviewRegions` name what is excluded and reviewed by eye, such as station labels or a captured cursor. Region IDs must be unique within a sidecar. `Compare` matches regions by ID.

## Environment

`environment.json` is one flat object with non-empty string values for `guest`, `clr`, `ddrawVersion`, `ddrawSha256`, `dx8vbVersion`, `dx8vbSha256`, `virtualBox`, `graphicsController`, and `displayMode`.

## Validation

```powershell
.\eng\renderer-oracle.ps1                       # Validate; missing captures are pending
.\eng\renderer-oracle.ps1 -RequireComplete      # exit gate: every capture present
.\eng\renderer-oracle.ps1 -Action Compare -InputPath <a.json> -OtherInputPath <b.json>
```

Git is the immutability mechanism. Evidence lands in one commit tagged `phase2a-evidence`. Replace evidence only with a new commit that says why.

Legacy saves use an unsafe object serializer. Load only saves created in the controlled VM, never untrusted input, and never in a host or modern process.
