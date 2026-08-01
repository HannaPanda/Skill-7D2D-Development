# Environment & Build (7DTD 3.x)

## Paths (this machine)
- Game: `C:\Steam\steamapps\common\7 Days To Die`
- Managed DLLs: `…\7 Days To Die\7DaysToDie_Data\Managed\` (`Assembly-CSharp.dll` = all game code)
- Harmony (ships with the game): `…\7 Days To Die\Mods\0_TFP_Harmony\` - contains `0Harmony.dll` **and `Mono.Cecil.dll`** (used by the recon scripts).
- MO2 modlist "Smorgasbord": `C:\Modlists\Smorgasbord\` - active mods under `mods\`.
- Effective game Mods folder at runtime (via MO2 VFS): `%APPDATA%\7DaysToDie\Mods\`.
- Logs: `%APPDATA%\7DaysToDie\logs\output_log_client__<date>.txt` (the main log; `WalkerSim_*.log`/`launcher.log` are side logs).
- Build: `dotnet` (SDK 10.x installed) builds `net48` fine.

## .csproj template (Harmony DLL mod)
`net48`, `AssemblyName` = your assembly (this name is what XML must assembly-qualify against - see resolution-and-xml.md). References with `<Private>false</Private>`:
`mscorlib, System, System.Core, System.Xml, System.Xml.Linq` (all from Managed), `Assembly-CSharp` (Managed), `0Harmony` (from `Mods\0_TFP_Harmony\0Harmony.dll`), `UnityEngine.CoreModule` (Managed). Add more `UnityEngine.*Module.dll` as needed.
A known-good copy lives in the Seeker Cluster mod's `_src/SeekerCluster.csproj` (scratchpad + `C:\Modlists\Smorgasbord\mods\SeekerCluster\_src\`).

## Entry point
```csharp
public class MyMod : IModApi {
    public void InitMod(Mod _modInstance) {
        new HarmonyLib.Harmony("author.modid").PatchAll(System.Reflection.Assembly.GetExecutingAssembly());
    }
}
```
Log line from your InitMod appears in the main log → confirms DLL + Harmony loaded.

## MO2 packaging (CRITICAL)
MO2 maps the *contents* of `mods\<MO2mod>\` into the game Mods folder. So the actual 7DTD mod must sit in a **nested subfolder**:
```
mods\MyMod\               <- MO2 mod (has meta.ini)
  meta.ini
  _src\                   <- source (7DTD ignores folders without ModInfo.xml)
  MyMod\                  <- the real 7DTD mod
    ModInfo.xml
    MyMod.dll
    Config\*.xml, Localization.txt
```
A flat layout deploys `ModInfo.xml` to `Mods\` directly and fails. Mirror the `Toolbelt 20 Slots` mod exactly.
The MO2 warning **"contains no esp/esm/esl and no asset directory"** is a generic Bethesda-oriented check and is EXPECTED for every 7DTD mod - ignore it.

## Publishing: file descriptions (Nexus / GitHub release)
The description on a *file* is read next to the download button. **Never ship the generator's
boilerplate** ("Automated upload from tag vX.Y.Z. Changelog: <url>") - it tells a user nothing.
Compose it in this order, and keep it plain text (Nexus file descriptions are not BBCode):

1. **What this file is**, in player terms - one or two sentences. When a mod ships variants,
   this is the *only* place a user learns which one to take, so lead with the difference and
   say "install this OR the other, not both". E.g. survival edition = "you have to find the
   ore, smelt it, craft it at the workbench"; creative/cheat edition = "craft it from 1 wood
   straight out of your backpack, for builders and testing".
2. **Install constraints** - required dependency mods, "contains a Harmony DLL → EAC off",
   "multiplayer: client + server".
3. **Mini changelog** - the current version's section only, ~6 one-line bullets, then a link
   to the full changelog. Generate it from `CHANGELOG.md` in CI rather than hand-writing it
   per release (see the Adamant repo's `Build mini changelog` step: it slices the
   `## <version>` section, folds continuation lines, strips markdown, and condenses each
   bullet to whole sentences ≤ ~180 chars; a missing section degrades to blurb + link).
   Consequence for the changelog itself: **the first sentence of each bullet must state the
   change** - the reasoning goes after it, where only repo readers see it.

The per-file blurbs belong in the workflow next to each upload step; only the changelog part
is generated.

## Publishing: the changelog on the mod PAGE (BBCode)
A mod page benefits from its own changelog section (newest version first, a `[size=3][b]X.Y.Z[/b][/size]`
block per release) - the Files tab only shows a per-file note, so a returning user otherwise
cannot tell whether an update is worth it. **Write it for players, not for modders.** This is the
user's standing preference and it is the opposite of the repo `CHANGELOG.md`, which stays
technical:
- **No engine vocabulary.** No "atlas", "slice", "uvMapping", "Harmony patch", "paint id",
  "transpiler", no class names, no log strings, no file names. If a term only means something to
  someone who has read the source, it does not belong on the mod page.
- **Say what the player notices, then what to do about it.** "Some paints from other mods showed
  the wrong texture. Nothing was saved wrong - update and restart" beats any description of the
  cause.
- **Keep the "why" only where it changes a decision** - a removed feature, a save-related risk, a
  trade-off. Then say it in plain words ("could point at the wrong texture … in bad cases that
  broke loading the world"), not in mechanism terms.
- **Reassure about saves explicitly** whenever a change could look scary ("blocks you have already
  built are unaffected").
- Three changelogs, three audiences, never copy-paste between them: `CHANGELOG.md` (repo,
  technical), the CI-generated mini changelog (Files tab, one line per bullet), the mod page
  section (players).

## Rebuild loop
1. `dotnet build _src\<name>.csproj -c Release`
2. Copy `bin\Release\<name>.dll` into the nested `…\MyMod\MyMod\` folder.
3. XML-only changes need no rebuild, but 7DTD loads XML at startup → full game restart to test either.
