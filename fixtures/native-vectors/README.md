# Native renderer vectors

Provenance `native-vector`: outputs of the shipped `DirectDraw.AlphaBlend.dll` (SHA-256 `b8153302…f165d`), executed on fake heap-backed `DirectDrawSurface7` objects by `eng/native-vectors/NativeVectorProbe.cs`. No DirectDraw runtime is involved.

One directory per pixel mode (`555`, `565`, `24`, `32`). Each holds `index.json` (geometry, arguments, HRESULT, integrity flags, SHA-256 per case) and one `<id>.bin` per case: source pixels (omitted for `buildNightImage`), destination before, destination after. Each block is `pitch * height` bytes; padding bytes start as `0xA5`.

```powershell
.\eng\native-vectors\run-probe.ps1            # Check: fail unless output equals these files
.\eng\native-vectors\run-probe.ps1 -Action Write
```

Regenerate only when the case list changes. A Check failure with an unchanged case list means the harness or environment changed, not the oracle.
