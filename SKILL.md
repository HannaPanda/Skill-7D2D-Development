---
name: 7d2d-modding
description: >-
  Develop, debug, and package mods for 7 Days to Die 3.x (Harmony/C# DLL mods and
  XML config mods: entityclasses, items, buffs, recipes, entitygroups, XUi). Use
  this whenever the task involves 7DTD / "7 days to die" modding - writing or fixing
  a Harmony patch, a custom entity/AI task/buff/MinEventAction/item, an entityclasses
  or buffs or items XML, diagnosing a mod that won't load or a red error in the 7DTD
  log, building a mod DLL against Assembly-CSharp, or deploying into the MO2
  "Smorgasbord" modlist. Also use for any question about how a 7DTD game class,
  enum, XML tag, or AI task actually works - this skill interrogates the real game
  DLL instead of guessing. Self-learning: read and append to LEARNINGS.md.
---

# 7 Days to Die 3.x modding

A self-correcting workflow for 7DTD 3.x. The core principle: **the installed `Assembly-CSharp.dll` is the only authoritative spec, and it changes between versions - so verify against it, don't trust memory.** The skill bundles scripts to read that DLL offline, reference notes for the traps that aren't discoverable by reading signatures alone, and an append-only log so each solved problem stays solved.

## Start every session here
1. **Read `LEARNINGS.md`.** It's the running memory of confirmed cause→fix notes - check it before diagnosing anything so you don't re-derive a known trap.
2. Skim the reference that matches the task (below). Load the file only when relevant - keep context lean.

## Reference map (read on demand)
- `references/environment-and-build.md` - paths, `.csproj`, `IModApi` entry, MO2 nested-folder packaging, log locations, rebuild loop, and how to write Nexus/release **file descriptions** (edition blurb + mini changelog, never upload boilerplate). Read for any build/deploy/publish/"where is X" question.
- `references/api-recon.md` - the three `scripts/dump-*.ps1` tools and how to use them to discover types, get signatures, and read IL. Read before writing C# against game types or naming a game class/enum in XML.
- `references/resolution-and-xml.md` - how XML strings resolve to C# classes (custom AI tasks, custom MinEventActions - both need assembly-qualified names), AITask/AITarget syntax, buffs as timers, item/recipe/localization syntax. Read for any XML authoring or "my custom class is ignored" issue.
- `references/verified-api.md` - copy-pasteable confirmed signatures (spawn entity, buffs, explosion, AI-task/MinEventAction subclass skeletons, Harmony hooks, factions). Read while writing C#.

## The loop
1. **Recon** - `scripts/dump-catalog.ps1` to find a type, `dump-members.ps1` for signatures/enum values, `dump-il.ps1` when a *mechanism* must be certain. (Details in api-recon.md.) Never guess a signature or an enum value you can dump in seconds.
2. **Write** - C# per verified-api.md; XML per resolution-and-xml.md. Prefer doing timing/detonation/effects with vanilla buffs + `triggered_effect` (MP-safe, no code) and reserve C# for behaviour vanilla can't express.
3. **Build** - `dotnet build` against the real DLLs. A clean build proves API usage; it does NOT prove runtime logic.
4. **Deploy** - into the MO2 nested layout (environment-and-build.md). Restart the game (XML loads at startup).
5. **Diagnose** - grep the newest `output_log_client__*.txt` for the mod name and `WRN|EXC|ERR|not found|Unable to find`. The bad value is usually right there. Turn it into a `dump-*` query, fix, restart.
6. **Verify across versions** - a mod is never "compatible with 3.x". It is compatible with the *builds you launched it on*. Run the multi-version smoke test (below) before any release, and again whenever a new game build appears.
7. **Record** - when you confirm a non-obvious cause→fix (a load error, a resolution quirk, a wrong enum name, an API that moved), **append an entry to `LEARNINGS.md`** (newest on top, with the evidence). If it's broadly reusable, also fold it into the right reference file. This step is what makes the skill improve over time - treat it as part of "done," not optional.

## Version-compatibility policy (binding for every release)

**Test each mod release against several game versions, and name only the versions actually tested.** "Should work on 3.x" is not a claim this project makes - users read a compatibility list as a promise, and the two things that break silently on a new build are exactly the ones a quick look won't catch: a Harmony patch whose target signature moved, and an XML attribute the engine stopped honouring.

Rules:
- The tested list is **per mod version**, re-established for each release. A version tested for 1.2.1 says nothing about 1.3.0.
- A version counts as tested only after it was **launched with the mod installed and the log checked** - not because the XML looks harmless.
- State the list in **every** place the user sees: README, Nexus mod-page description, Nexus file descriptions, GitHub release body. In the Adamant repo these are fed from the single `TESTED_VERSIONS` env var in `.github/workflows/release.yml` plus the README/bbcode text - keep all of them in sync.
- Pure XML changes are the cheap case and *may* be accepted across versions on a smoke test alone. **Any DLL/Harmony change invalidates the whole list** and requires re-testing every version you intend to name.
- **⚠ All of the above is the default, not a veto. The mod author has the last word on how much testing is enough**, and may publish a version as tested on a partial check - no hedging clause in the README, the Nexus page or the release body. A typical case: a mechanism verified end to end on one build while the other builds only get the log evidence, because the code behind it is byte-identical across them.
  **For an agent this cuts one way only.** State the gap once, concretely (which version, which check, what the report will therefore say), then carry out the decision - no second attempt to relitigate it, no softened wording smuggled into the docs, and never that judgement call made on your own. Removing an evidence pattern so a report turns green stays forbidden: that bends the instrument instead of overruling it.

### The test bench
**Use the `7d2d-testbench` skill for anything involving a test run** - it owns the workflow, the rules and the command reference. Short version: the bench is a program now (`tb.exe` on the PATH, `Testbench.Gui.exe` for interactive use), source at `%USERPROFILE%\7D2D-Testbench`, data at `E:\7DTD-Testbench\`, one game install per version under `E:\Games\7DTD-<version>`.

- `tb run --mod <fragment> --profile matrix --json` - every configured version **headless** (`-batchmode -nographics -dedicated`, the fallback path in TFP's own `startdedicated.bat`, since no `7DaysToDieServer.exe` ships with the client), checked for mod load, Harmony patches, XML problems, `ERR`/`EXC`.
- `tb report --mod <fragment> --json` - the matrix plus the `TESTED_VERSIONS` line, and per version the reason a version does not count yet.
- `tb doctor --json` - the answer to "why did that not work", before searching logs.
- The old `Invoke-SmokeTest.ps1` / `Invoke-TestMatrix.ps1` / `Start-Gui.ps1` are **retired**. They survive under `legacy/` in the repo as the parity reference and still contain two known silent bugs; do not run them.

Two limits to state honestly rather than paper over:
- **Headless does not cover anything graphical.** `TextureAtlasBlocks.LoadTextureAtlas` never runs under `-nographics`, so a texture/atlas patch needs one GUI run per version on top.
- **GamePrefs are shared.** 7DTD stores options as Unity PlayerPrefs in `HKCU\Software\The Fun Pimps\7 Days To Die` - outside the `-UserDataFolder`, shared by every install, not redirectable by any launch argument. A fresh test build rewrites them with its defaults and silently clobbers the live game's tuned graphics settings. Every script here exports the key before the run and imports it back afterwards; anything new that launches the game must do the same.

## Self-learning contract
`LEARNINGS.md` is append-only working memory; the `references/` files are the distilled, cleaned-up knowledge. New finding → log it immediately with evidence; when a logged finding generalizes, promote it into a reference and keep the log entry as the dated record. If a note ever conflicts with the live DLL (after a game update), re-run the relevant `dump-*` and correct the note rather than trusting it.

## Scope & safety
Covers mods for the user's own game/modlist: Harmony patches, custom entities/AI/buffs/items/recipes, XML config, XUi, and debugging load/runtime errors. Not for cheating on multiplayer servers you don't own or circumventing anti-cheat on others' servers.

## Known project context
The user runs the MO2 "Smorgasbord" modlist and has custom mods (e.g. Toolbelt-20, and the in-progress **Cluster Seeker**). Mirror the existing mods' structure and build setup rather than inventing new conventions. Cross-reference the user's memory files (`7d2d-*`) for project state.
