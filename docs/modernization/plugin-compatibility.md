# Plugin compatibility policy

## Inventory

- 54 bundled `plugin.xml` manifests under `FreeTrain/plugins`
- 23 bundled plugin C# projects
- 228 additional manifests under `PluginsExtra`
- `PluginsExtra` is primarily data/assets: no C# or C++ source was found and only one DLL was found

## Compatibility contracts

Plugins depend on four distinct contracts:

1. Manifest XML structure and contribution IDs
2. Public FreeTrain types, namespaces, and assembly identities
3. CLR type identity used by legacy save serialization
4. Rendering types exposed through `org.kohsuke.directdraw`

Compatibility claims must identify which contract and tier they cover.

## Tiers

### Tier A — bundled plugins with source

Must build and work. Source-level `org.kohsuke.directdraw` compatibility is mandatory during renderer replacement.

### Tier B — third-party plugins with source

Recompilation and documented migration are supported. Exact historical binary loading is not required.

### Tier C — historical binary-only plugins

Best effort. Unchanged binary loading under current .NET is not guaranteed. Any compatibility shim must be justified by known real plugins rather than hypothetical binaries.

### Tier D — plugins represented in legacy saves

Handled by the save importer independently of runtime binary compatibility. Stable plugin and contribution IDs are more important than loading the old assembly in the modern game.

## Immediate freeze

Until Phase 6 classifies persistence impact, do not rename or remove:

- Public types or namespaces
- Assembly names
- Contribution IDs
- Manifest class/codebase values
- Serializable fields
- Serialization constructors or `GetObjectData` keys

## Verification matrix

For each Tier A plugin, record:

- Manifest ID and dependencies
- Data-only versus compiled
- Referenced assemblies
- Renderer API use
- Serializable types
- Save fixture coverage
- Build result
- Runtime load result

Tier B–D plugins are added to the matrix as representative samples become available.
