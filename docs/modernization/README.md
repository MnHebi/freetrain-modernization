# FreeTrain modernization record

This directory records the evidence, invariants, and decisions for modernizing the locally supplied FreeTrain revision 389 snapshot.

## Baseline

- Imported snapshot commit: `20c25cfbcd91edaed65d1acc6f93c50527418158`
- Immutable annotated tag: `pristine/r389`
- Working branch: `modernization/main`
- Supplied source root: `FreeTrain/`
- Additional historical plugin collection: `PluginsExtra/`

The original archive was not present in the attached workspace, so an archive SHA-256 could not be recorded. `pristine-baseline.md` distinguishes this missing input from the deterministic file manifest generated for the imported snapshot.

## Non-negotiable compatibility rules

1. Do not move or recreate `pristine/r389`.
2. Do not rename or remove a public type, namespace, assembly identity, contribution ID, or serialization-relevant field until save compatibility has classified it.
3. Preserve the `org.kohsuke.directdraw` API as the default compatibility facade during renderer replacement.
4. Do not require the DirectDraw renderer to run in Windows 11 CI. Renderer evidence may come from a compatible VM, extracted native algorithms, deterministic vectors, historical captures, or reviewed reference images.
5. Primitive renderer tests require exact pixel equality. Complete scenes separate deterministic world rendering from platform-sensitive text rendering.
6. Never deserialize a legacy save in the modern game process. Prefer record-level inspection without object construction; isolate unavoidable legacy deserialization.
7. Project splitting is optional and requires a demonstrated migration problem.
8. No bulk formatting, namespace cleanup, file moves, nullable conversion, analyzer-driven rewrite, or naming cleanup before the relevant subsystem is stable.

## Phase order

0. Archaeological/build inventory
1. Modern reproducible legacy build
2. Renderer behavioral specification and tests
3. DirectDraw-free renderer behind the existing facade
4. Native alpha DLL removal gate
5. Audio modernization
6. Save compatibility and serialization migration
7. SDK-style/current .NET migration
8. Old dependency removal and cleanup

## Phase 0 documents

- `pristine-baseline.md` — snapshot provenance and verification
- `legacy-build-inventory.md` — projects, build topology, runtime assumptions, and open questions
- `dependency-inventory.md` — managed, native, and COM dependencies
- `renderer-compatibility.md` — facade boundary, behavioral oracles, and test taxonomy
- `plugin-compatibility.md` — compatibility contracts and tiers
- `save-compatibility.md` — legacy format evidence and security constraints

## Phase 1 documents

- `phase1-build.md` — diagnostic results, local-only blockers, and build order
- `phase1a-dependency-classification.md` — evidence-based dependency classes, DxVBLibA contract, .NET 2.0 SDK trace, and native-alpha binary decision
- `eng/legacy-build-preflight.ps1` — non-mutating toolchain and dependency preflight
