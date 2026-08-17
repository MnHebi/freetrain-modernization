# Legacy build inventory

## Repository layout

The source root is `FreeTrain/`, one level below the attached repository root. The VS2008 solution and DirectDraw wrapper are present at:

- `FreeTrain/FreeTrain_VS2008.sln`
- `FreeTrain/lib/DirectDraw.net/`

The source tree contains 43 project files:

- 40 legacy C# projects
- 3 Visual C++ `.vcproj` projects
- 34 project entries in `FreeTrain_VS2008.sln`, including its solution folder

There are 514 C# source files, 10 C++ files, and 39 headers under `FreeTrain/`, including NeoFT and experiments. No NUnit, xUnit, MSTest, or comparable automated test project was found.

## Project generations

Most active C# projects are Visual Studio 2008/MSBuild 3.5 projects with `ProductVersion` 9.0.21022. They generally omit `TargetFrameworkVersion`, while the shipped readme instructs users to install .NET Framework 2.0. This combination must be tested rather than assuming the compiler/runtime target.

Native projects span at least two generations:

- `DirectDraw.AlphaBlend` and its proxy/stub project use `.vcproj` version 8.00.
- The DirectShow video recorder uses `.vcproj` version 7.00.

The solution contains Any CPU, Mixed Platforms, Win32, and x86 configurations. Core and DirectDraw projects specify x86 in at least their Debug configuration, consistent with 32-bit COM/native dependencies.

## Main application discrepancy

`FreeTrain/core/FreeTrain.Core.csproj` declares:

- `AssemblyName` = `FreeTrain.Core`
- `OutputType` = `Library` in its global, Debug, and Release property groups
- `RootNamespace` = `freetrain`

`FreeTrain/core/framework/MainWindow.cs` nevertheless contains `[STAThread] static void Main()` and another private `run(string[])` helper. The user-facing readme refers to running `FreeTrain.exe`, but no launcher project appears in `FreeTrain_VS2008.sln`.

This is an archaeological question, not an invitation to change `OutputType` immediately. Phase 0 must explain whether the snapshot omits a launcher, whether a historical configuration transformed the project, or whether the project metadata is inconsistent. Phase 1 may alter it only after the historical arrangement is understood.

## Build and packaging behavior

`FreeTrain/copyresources.bat` copies:

- `core/res` to `res`
- `plugins` to `plugins`
- documentation files into the selected output directory

It uses `xcopy`, a positional output argument, and `excludelist.txt`, then pauses interactively. No repository-wide restore/build/package script or CI configuration was found.

The tree includes checked-in Debug/Release native alpha DLLs and multiple prebuilt external assemblies. These are historical inputs; none should be deleted before a reproducible legacy package exists.

## Current machine observation

At inventory time, the attached environment had:

- .NET SDK 8.0.101 and 10.0.400
- No standalone `msbuild` command on `PATH`
- No `vswhere` installation record
- .NET Framework directories from 1.0 through 4.x, including 2.0, 3.0, and 3.5
- No resolvable `DirectX7.DirectX7` or `DirectDrawAlphaBlendLib.AlphaBlender` ProgID

No legacy build was attempted because the classic build toolchain and COM registration have not yet been established.

## Phase 1 build scope

The first reproducible build should include only:

1. `FreeTrain.Core`
2. `FreeTrain.Controls`
3. `DirectDraw.net`
4. `DirectAudio.net`
5. Native `DirectDraw.AlphaBlend`
6. Bundled compiled plugins required by the standard package
7. Resource/plugin packaging

Keep `NeoFT`, experiments, the DirectShow video recorder, and nonessential tools out of the critical path.

## Open questions and evidence required

- What produced `FreeTrain.exe` from a project marked as a library?
- Which exact Visual Studio/MSVC versions last built this revision?
- Is .NET Framework 2.0 the runtime contract despite MSBuild 3.5 project upgrades?
- Are COM interop assemblies expected to be generated or checked in elsewhere?
- Which native runtime and ATL registration steps were required?
- Which configuration constituted the released package?
- Are there known-good revision 389 executables, saves, screenshots, or build logs outside this snapshot?
