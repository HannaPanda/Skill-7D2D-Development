# 7 Days to Die Modding Skill

A skill for [Claude Code](https://claude.com/claude-code) that develops, debugs and packages
mods for 7 Days to Die 3.x, covering both Harmony/C# DLL mods and XML config mods.

Its core principle: **the installed `Assembly-CSharp.dll` is the only authoritative spec, and it
changes between versions.** So the skill reads that DLL instead of recalling what an API looked
like. Most of the time an agent spends on a 7DTD mod bug is spent on a signature, an enum value
or a code path that was assumed rather than checked, and all three are a few seconds away from
being dumped.

## What is in here

| Path | What |
|---|---|
| `SKILL.md` | The workflow, the version-compatibility policy and the self-learning contract |
| `scripts/dump-catalog.ps1` | Find a game type by name fragment |
| `scripts/dump-members.ps1` | Signatures, fields and enum values of a type |
| `scripts/dump-il.ps1` | Read the IL of a method when a mechanism has to be certain |
| `references/api-recon.md` | How to drive the three scripts |
| `references/verified-api.md` | Copy-pasteable confirmed signatures: spawning, buffs, explosions, AI task and MinEventAction skeletons, Harmony hooks, factions |
| `references/resolution-and-xml.md` | How XML strings resolve to C# classes, AITask syntax, buffs as timers, item and recipe syntax |
| `references/environment-and-build.md` | Paths, `.csproj` template, `IModApi` entry point, MO2 nested packaging, publishing |
| `LEARNINGS.md` | Append-only record of confirmed cause-to-fix findings, newest first, each with its evidence |

`LEARNINGS.md` is the part that makes the skill improve. Every non-obvious cause and fix goes in
with the IL or log line that proves it, so the same trap is never re-derived. Entries are mostly
German, the reference files are English.

## Requirements

- A local 7 Days to Die 3.x installation. The recon scripts read `Assembly-CSharp.dll` from it,
  plus `Mono.Cecil.dll` which ships with the game under `Mods\0_TFP_Harmony\`.
- Windows PowerShell for the `dump-*` scripts.
- The .NET SDK if you want to build DLL mods. They target `net48`.

The scripts default to `C:\Steam\steamapps\common\7 Days To Die`. Point them somewhere else with
the `SDTD_DIR` environment variable:

```powershell
$env:SDTD_DIR = 'D:\SteamLibrary\steamapps\common\7 Days To Die'
```

The remaining absolute paths in `SKILL.md` and `references/environment-and-build.md` describe the
author's machine layout (MO2 modlist location, per-version game installs for the test bench).
Adjust them to yours, or ignore them if you do not use MO2.

## Installation

Clone into your personal skills folder, using the directory name `7d2d-modding`:

```bash
git clone https://github.com/HannaPanda/Skill-7D2D-Development.git ~/.claude/skills/7d2d-modding
```

On Windows that path is `%USERPROFILE%\.claude\skills\7d2d-modding`.

## Usage

The skill triggers on its own for anything involving 7DTD modding: writing or fixing a Harmony
patch, authoring entityclasses or buffs or items XML, diagnosing a mod that will not load or a
red error in the log, or building against `Assembly-CSharp`. It also triggers on any question
about how a game class, enum, XML tag or AI task actually behaves, because that is exactly the
kind of question worth answering from the DLL rather than from memory.

Invoke it by name with:

```
/7d2d-modding
```

## A note on version compatibility

The skill treats "works on 3.x" as a claim nobody can make. A mod is compatible with the builds
it was launched on, and the tested list is re-established per mod version, because any Harmony
change can invalidate all of it. Companion skill `7d2d-testbench` runs that matrix; it is not
part of this repository.
