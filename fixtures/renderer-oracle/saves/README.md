# Captured saves

Place each save from `catalog.json` here as `<save>.ftgd`. Saves are immutable once their hash is recorded in a sidecar: never open and resave one; add a new `-v2` save instead.

These files use the legacy unsafe object serializer. Load only saves created in the controlled VM, never untrusted input, and never in a host or modern process.
