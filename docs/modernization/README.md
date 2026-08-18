# FreeTrain modernization record

This directory records the evidence, invariants, and decisions for modernizing the locally supplied FreeTrain revision 389 snapshot.

## Baseline

- Imported snapshot commit: `20c25cfbcd91edaed65d1acc6f93c50527418158`
- Immutable annotated tag: `pristine/r389`
- Working branch: `modernization/main`
- Supplied source root: `FreeTrain/`
- Additional historical plugin collection: `PluginsExtra/`

The original source archive and official runtime release were supplied after the initial import. They remain untracked, immutable reference oracles rather than build inputs:

- `freetrain-code-r389-trunk.zip` — SHA-256 `5D5547B43548F510A6FE8F7DBB84CED202114D2F1668031E869C8A0B11ADF8A6`
- `FreeTrain20070604.zip` — SHA-256 `70374A836A9F1BC28B16DD65C323FC1B21B4142F10344D19335A65690C16C23D`

`pristine-baseline.md` records the earlier missing-input state and the deterministic file manifest generated for the imported snapshot; retain that chronology rather than rewriting the original archaeological result.

## Non-negotiable compatibility rules

1. Do not move or recreate `pristine/r389`.
2. Do not rename or remove a public type, namespace, assembly identity, contribution ID, or serialization-relevant field until save compatibility has classified it.
3. Preserve the `org.kohsuke.directdraw` API as the default compatibility facade during renderer replacement.
4. Do not require the DirectDraw renderer to run in Windows 11 CI. Renderer evidence may come from a compatible VM, extracted native algorithms, deterministic vectors, historical captures, or reviewed reference images.
5. Primitive renderer tests require exact pixel equality. Complete scenes separate deterministic world rendering from platform-sensitive text rendering.
6. Never deserialize a legacy save in the modern game process. Prefer record-level inspection without object construction; isolate unavoidable legacy deserialization.
7. Project splitting is optional and requires a demonstrated migration problem.
8. No bulk formatting, namespace cleanup, file moves, nullable conversion, analyzer-driven rewrite, or naming cleanup before the relevant subsystem is stable.
9. Preserve the complete VCR source and its managed/native build evidence. Reconstructing its historical auxiliary toolchain is preservation-only and must not block core modernization or Phase 2 renderer characterization.
10. Treat supplied historical archives and official binaries as immutable reference oracles. Record their provenance and hashes; do not substitute their compiled outputs for source-built reconstruction artifacts.

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

- `phase1-build.md` — diagnostic results, completed build/package gate, and remaining runtime boundary
- `phase1-build-report.md` — exact inputs, deterministic interop hashes, build errors, and package validation
- `phase1a-dependency-classification.md` — evidence-based dependency classes, DxVBLibA contract, .NET 2.0 SDK trace, and native-alpha binary decision
- `phase1d-dotnet35sp1-prerequisite.md` — verified Microsoft offline installer identity, signer provenance, expected CLR 2 versions, and guest-only installation gate
- `phase1d-runtime-validation.md` — disposable XP SP3 x86 runtime, COM, smoke-test, and Phase 2 capture runbook
- `eng/legacy-build-preflight.ps1` — non-mutating toolchain and dependency preflight
- `eng/legacy-build.ps1` — external-input verification, no-registration interop generation, serial x86 build, and packaging
