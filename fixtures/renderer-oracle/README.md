# Paired renderer-oracle fixtures

This directory is the repository-side evidence store for Phase 2A. Read `docs/modernization/phase2a-legacy-oracle.md` before creating or approving an artifact.

Build the official-VM scenes from `docs/modernization/phase2a-fixture-layouts.md`. Its ASCII plans distinguish ordinary tile anchors from the terrain editor's shared-corner vertices. Do not use the plans to independently recreate the reconstructed-VM worlds; transfer the same immutable save bytes.

- `catalog.json` declares the required fixtures and capture IDs.
- `capture-metadata.schema.json` defines each official/reconstructed primary or clean-reproduction sidecar.
- `comparison-metadata.schema.json` defines official-versus-reconstructed difference records.
- `templates/` contains separate official, reconstructed, and comparison templates; templates are not evidence.
- `saves/` receives captured `.ftgd` or `.ftgt` files.
- `screenshots/<oracle>/{primary,reproduction}/` receives full-console lossless PNGs.
- `metadata/<oracle>/{primary,reproduction}/` receives one sidecar per screenshot.
- `comparisons/` receives one official-versus-reconstructed record per logical capture.
- `masks/` may receive explicitly hashed mask artifacts; rectangle-only masking needs no file.
- `manifests/approved-files.sha256` seals approved evidence.

Statuses are `planned`, `candidate`, or `approved`. Keep partial pairs in staging. A capture becomes `candidate` only when both primary oracle records, any required clean repetitions, and its comparison record exist. After approval, never edit the save, screenshot, sidecar, comparison, or mask; add a versioned fixture.

Run `.\eng\renderer-oracle.ps1 -Action Validate` from the repository root. `VerifyPng` checks structural integrity; `CompareRegions` exact-compares declared deterministic pixels between two completed sidecars. The script is read-only unless `-OutputPath` is supplied to `Catalog` or `Manifest`; those actions write only derived text, never evidence.

Legacy saves use an unsafe object serializer. Only load controlled VM-created fixtures or explicitly custody-approved historical saves; never deserialize an untrusted save on the host.
