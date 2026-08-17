# Pristine revision 389 baseline

## Imported material

The attached directory contained two top-level trees:

- `FreeTrain/` — source, bundled plugins, tools, documentation, binary dependencies, and generated/build artifacts
- `PluginsExtra/` — 228 additional historical plugin manifests and their assets

The complete supplied tree contains 3,950 files totaling 147,819,767 bytes before Git metadata or modernization documents are added.

## Git baseline

The complete supplied tree was committed without adding an ignore file or changing source content:

- Commit: `20c25cfbcd91edaed65d1acc6f93c50527418158`
- Git tree: `19c2acdeee1912b3ac50aebcd9200d1659325e6c`
- Annotated tag: `pristine/r389`
- Modernization branch: `modernization/main`

The tag identifies the archaeological reference. It must never be moved, deleted, or recreated as part of normal modernization work.

## SHA-256 status

The original source archive was not included beside the extracted tree. Its SHA-256 is therefore **unknown** and must not be inferred from the extracted directory.

`pristine-r389-files.sha256` is a generated SHA-256 manifest of the 3,950 files preserved by `pristine/r389`. It verifies the imported content but is not an archive checksum. The SHA-256 of that canonical UTF-8/LF manifest is `909b67618119934dd2e8ebe5ebd9edd1d972029d084ad2be3b4a846f7144971a`.

Run the verifier from the repository root:

```powershell
pwsh -File eng/verify-pristine-baseline.ps1
```

If the original archive is later supplied, record its unmodified SHA-256 here as a separate value and do not replace the imported-tree manifest.

## Line-ending preservation

The pristine snapshot was staged with `core.autocrlf=false`. Git blobs therefore contain the supplied working-tree bytes rather than a line-ending-normalized import.
