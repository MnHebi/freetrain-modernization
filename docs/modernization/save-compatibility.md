# Save compatibility and migration constraints

## Observed formats

The file dialog exposes:

- `.ftgd` — `BinaryFormatter`
- `.ftgt` — `SoapFormatter`

Save code writes the bytes `UC`, then serializes two consecutive objects:

1. A one-element `BGMContribution[]`; the array allows a null current BGM
2. The complete `World` object graph

Load code also recognizes an historical `BZ` header and wraps the stream in `BZip2InputStream`. The saver’s corresponding compression path is commented out in this revision.

`PluginSerializationBinder` resolves serialized type names by scanning the assemblies of loaded plugin contributions. Saves therefore depend on plugin availability and CLR type identity, not just field data.

No `.ftgd` or `.ftgt` fixture was included in the attached tree.

## Immediate compatibility freeze

Before save analysis classifies a symbol, do not rename or remove:

- `FreeTrain.Core` assembly identity
- Public namespaces and types
- Serializable type names
- Serialization-relevant fields
- Custom serialization constructors
- `GetObjectData` entry names
- Contribution and plugin IDs

## Security boundary

Preferred migration order:

1. Inspect serialization records without constructing the object graph.
2. Extract type and assembly inventories.
3. Define validated, versioned DTOs.
4. Map approved legacy records into those DTOs.

If `BinaryFormatter` or `SoapFormatter` execution is unavoidable, it must run only in an isolated migration process or VM with:

- Network disabled
- Constrained filesystem access
- No secrets
- Strict resource/time limits
- Trusted historical saves only during development
- Validated DTO output before the modern game consumes it

The modern game process must never directly deserialize legacy saves.

## New-format requirements

- Explicit magic and schema version
- Application version
- Stable plugin/contribution IDs rather than CLR names
- Required-plugin list with schema versions
- Versioned core and plugin records
- Bounded lengths/counts before allocation
- Integrity check
- Optional compression outside the object format
- Unknown plugin payload preservation policy
- Deterministic migration functions

Legacy formats become import-only. The new format is the only write format after Phase 6.

## Required fixtures

Collect both `.ftgd` and `.ftgt` examples covering:

- Empty/new world
- Developed world
- Rail-heavy world
- Finance plugins
- Compiled structure/terrain plugins
- Multiple BGM states, including null
- Missing-plugin behavior
- Historical `BZ` compression if available

Acceptance compares semantic state and continued simulation after load, not object reference identity.
