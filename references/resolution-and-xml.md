# Class Resolution & XML Syntax (the traps)

These are the rules that turn XML strings into your C# classes. Getting them subtly wrong is the #1 cause of "mod loads but my custom thing is silently ignored / throws at load." All verified by IL dumps of 3.0.1; re-verify with `dump-il` if a version bump breaks them.

## Custom AI task (referenced from entityclasses.xml)
`EAIManager.GetType(name)` matches a hardcoded switch of vanilla tasks, then falls back to a **"slow lookup": `Type.GetType("EAI" + name)`** (plain concat, no assembly search).
Consequences for YOUR task class:
- Must be in the **global namespace** and named **`EAI<X>`** (the "EAI" is prepended, so a namespace or non-EAI name breaks it).
- XML value must be **assembly-qualified without the EAI prefix**: `value="<X>,<AssemblyName>"`.
  → resolves as `Type.GetType("EAI<X>,<AssemblyName>")`.
- **No space after the comma** when the task is in the single-string multiline AITask format - the parser splits a task on the first space into `class | data`, so a space inside the qualified name corrupts it. `SeekerDetonate,MyAsm` ✓  `SeekerDetonate, MyAsm` ✗.

## Custom MinEventAction (buff `triggered_effect action=`, and other prefixed factories)
Resolved via `ReflectionHelpers.GetTypeWithPrefix("MinEventAction", name)` → effectively `Type.GetType("MinEventAction" + name)`, which searches **Assembly-CSharp only**. So a class in your DLL is invisible under its short name.
- Class named **`MinEventAction<X>`** (global namespace).
- XML must be **assembly-qualified**: `action="<X>, <AssemblyName>"` (a space after the comma is fine here - attribute value is read whole). → `Type.GetType("MinEventAction<X>, <AssemblyName>")`.
- `GetTypeWithPrefix` also handles namespaced names by inserting the prefix after the last dot; simplest is global namespace + `"<X>, <Asm>"`.
- The same helper backs other prefixed factories (requirements, some XUi controllers) - assume the same "assembly-qualify custom classes" rule and confirm with `dump-il ReflectionHelpers GetTypeWithPrefix`.

## AITask / AITarget XML syntax (entityclasses.xml)
Two accepted forms:
- **Indexed** (like `animalRabbit`): separate properties `AITask-1 value="TaskName" data="..."`, `AITask-2 …`, and `AITarget-1 …`. Redefining an index overrides the inherited one from `extends`.
- **Single multiline string**: `<property name="AITask" value="Task1 data|Task2 data|..."/>` - tasks separated by `|`, class/data split on the first space.
- Inside `data`: params separated by **`;`**, e.g. `Wander exePer=.1;lookMin=8`. Target class lists use **commas**: `class=EntityEnemy,0,EntityZombie,0` (triples of class,hearDist,seeDist for target tasks).
- **Empty `value=""` throws `Class '' not found!`** - never use it to "clear" an inherited task; just omit the line (inherited Look/Wander are harmless).

## Buffs as timers & effects (buffs.xml)
- `<duration value="1.4"/>` + triggers `onSelfBuffStart` / `onSelfBuffFinish` / `onSelfBuffUpdate` / `onSelfBuffRemove` = free, MP-safe timers.
- Detonation without custom code: `action="Explode"` (`MinEventActionExplode`) with `blast_power / block_damage / block_radius / entity_damage / entity_radius / damage_type`.
- Kill the owner after exploding: a second `action="ModifyStats" stat="Health" operation="set" value="0"`. (Vanilla suicide-exploder pattern.)
- `damage_type` takes an `EnumDamageTypes` name. **There is NO "Explosion"** - use `Special` for blasts. Always validate enum attributes with `dump-members <EnumType>`.

## Blocks: recoloring a reused vanilla model (blocks.xml)
- A `Shape="ModelEntity"` block takes its look from the **prefab's material**, not from the block atlas - the `Texture` property does nothing there.
- **`TintColor` writes `_Color` through a `MaterialPropertyBlock` - and many prefab shaders do not declare `_Color` at all**, in which case the write is a silent no-op. Verified: `Game/Entity Tint Mask` (the trap prefab) exposes `_Tint [Float]`, `_Cutoff`, `_EmissionMultiply`, `_MainTex`, `_Normal`, `_Emissive`, `_RMOM`, `_MacroAO` - no `_Color`. **On "property set, nothing happened", check `Material.HasProperty` / `Shader.GetPropertyName` before theorising about colour spaces.** Where `_Color` does exist it is an albedo *multiplier*, so it only yields the target colour on a pale albedo. World path is `BlockShapeModelEntity.OnBlockEntityTransformBeforeActivated`; `CloneModel` (held item/preview) additionally sets a `TintColor` property. Parsing is never the problem: 6-digit hex forces alpha 255, so the `a > 0` gate always passes.
- **Check which vanilla MODELS carry a property before reusing it.** All ~3300 vanilla `TintColor` blocks derive from about six prefabs authored for it (gun safes, munition boxes, hero chests) - pale albedo, so the multiply yields the colour. Nothing under `Entities/Traps`. Over a rust-brown metal albedo the result is dark mud.
- **What actually recolors a reused prefab, no Unity needed:** Harmony postfixes on `OnBlockEntityTransformBeforeActivated` (placed blocks, `_ebcd.GetRenderers()`) and `CloneModel` (`__result`), cloning the material once and setting `_MainTex`/`_BumpMap`. Read `sharedMaterials`, never `materials` (the model GameObjects are pooled); cache clone-per-source-material and keep a set of your own clone ids so a reused pooled renderer is not re-cloned. The prefab asset stays untouched, so the vanilla block keeps its look.
- **The pure-XML alternative: `Shape="New"` also takes a `Model`** (`BlockShapeNew.Init` requires one), and `shapes.xml`'s 2265 `@:Shapes/*.fbx` entries render through the **block atlas** - i.e. they honour the block's `Texture` id. Use that when a suitable mesh exists in the shape set; use ModelEntity + a DLL retexture when the vanilla silhouette matters.
- Offline recon without launching: `StreamingAssets/aa/catalog.json` lists every addressable asset path in clear text (answers "which .mat/.tga hangs off prefab X"); `aa/shaders.json` lists all 76 shaders.
- Icons are a separate path and DO tint: `CustomIcon` + `CustomIconTint` (hex).
- **Retexture all THREE slots, and log their NAMES.** Verified on the trap prefab (3.0.1): shader `Game/Entity Tint Mask`, slots `_MainTex`, **`_Normal`** (not `_BumpMap`), `_Emissive`, `_RMOM`. Setting only the albedo gives right colour / no relief / wrong gloss. `_RMOM` is a packed surface map whose channel order differs from the block atlas' `MOER` - fill it with a uniform 2×2 RGBA32 (linear, no mips). Log `Shader.GetPropertyDescription(i)` to read a packed map's channel order; the shader bundle is LZ4-compressed and no Managed DLL names these properties.

## Blocks: what a player gets back (blocks.xml)
- **Getting the BLOCK itself back needs `CanPickup`.** `Block.PickupOrDrop` bails unless `CanPickup`, or `forcePickup`, or `PassiveEffects.BlockPickup` (173) evaluates `> 0` against `block.Tags`. Vanilla grants that effect only for tags `Mine1`-`Mine4` (four landmine blocks, Perception trap perk). A custom block without `CanPickup` and without those tags can never be picked up whole.
- **`drop event="Harvest" count="N"` is a BASE value.** The player-mining path is `ItemActionMelee.checkHarvesting` (reads `block.itemsToDrop[Harvest]`) → `GameUtils.HarvestOnAttack` → `collectHarvestedItem`, which applies tool/perk bonuses and `XUiM_Recipes.HarvestingOutputModifier` (the world's harvest-abundance setting). Document it as "one back", not "exactly one".
- `Block.DropItemsOnEvent` is **not** that path - its only callers are `BlockModelTree.dropItems`, `EntityFallingBlock(s).OnUpdateEntity` and `GameManager.ExplodeGroupFrameUpdate`.
- Standard harvest tag for building blocks: `tag="allHarvest,perkJunkMiner"` (692 vanilla uses).

## Items / recipes / localization
- Thrown explosive: `Action0 class="ThrowAway"` + a `<property class="Explosion">` block (`BlockDamage/EntityDamage/RadiusBlocks/RadiusEntities/BlastPower/ParticleIndex`). `Extends="thrownGrenadeContact"` gives throw + ExplodeOnHit for free.
- Recipe: `<recipe name=".." craft_area="workbench" tags="workbenchCrafting"><ingredient .../></recipe>` - omit the `learnable` tag to make it craftable from the start (no perk/schematic gate).
- Localization.txt is CSV: `Key,File,Type,UsedInMainMenu,NoTranslate,english,german` - item name key = item name, description key = `<itemname>Desc`.
- **A mod's file MUST be `<mod>/Config/Localization.csv`** - `Localization.LoadPatchDictionaries` tests exactly that name; a `.txt` is silently ignored. Set `UsedInMainMenu=x` for anything visible before a world loads (Gears menus count).
- **A line break is the two characters `\n`, never a real newline.** The reader is line based, so an embedded newline - which a correct CSV writer would quote - breaks the row. Vanilla `Data/Config/Localization.csv`: 1399 rows use `\n`, none use a multi-line field; `Localization.WriteCsv` converts both ways on save. Commas must be quoted (RFC-4180) - generate the file, don't hand-edit it.
- **`Localization.Get(key, caseInsensitive, language)` returns the KEY itself when it is unknown** (`LocalizationChecks` on ⇒ prefixed `UL_`). So an API that "takes a localization key" also accepts raw text - it just looks wrong in check mode.

## Gears (mod settings manager) - XML surface
- `ModSettings.xml` lives in the **mod root**, not `Config/`; the mod is keyed by `ModInfo.xml`'s `<Name>`.
- **Exactly five control types exist, and none of them is a text field:** `Slider`, `Switch`, `Selector`, `ColorSelector`, `ControlBinding` (`I*GlobalSetting` in `GearsAPI.dll`, plus World variants of the first three). Anything free-form (a path, a name) needs a convention outside the menu.
- Selector syntax: `<Selector name=".." displayKey=".." tooltipKey=".." defaultValue=".." wrap="true"><Property type="arrayValues" allowedValues="A,B,C" /></Selector>`.
- **`allowedValues` are NOT localized** - Gears calls `Localization.Get` only for display names and tooltips. Explain the values in the tooltip.
- **Successful settings parsing is not logged.** The cheap positive proof is Gears' saved state at `<UserDataFolder>/Gears/ModSettings.xml`, which lists every setting it accepted - visible after a headless run.
