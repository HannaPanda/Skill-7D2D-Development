# Verified API snippets (3.0.1)

Confirmed signatures for common modding needs. Always re-confirm with `dump-members` if something doesn't compile - these reflect 3.0.1 and the game evolves.

## Spawn an entity (server-side)
```csharp
int cls = EntityClass.FromString("entityName");        // -1 if unknown
Entity e = EntityFactory.CreateEntity(cls, pos, rot);  // rot = Vector3 euler
e.SetSpawnerSource(EnumSpawnerSource.Dynamic);         // Unknown=0 Biome=1 StaticSpawner=2 Dynamic=3 Delete=4
world.SpawnEntityInWorld(e);
// world reached via: entity.world  |  GameManager.Instance.World
// alt: GameManager.Instance.RequestToSpawnEntityServer(EntityCreationData)
```

## Own texture into the opaque block atlas (no core mod)
Verified in-game 2026-07-28; full trap list in LEARNINGS (2026-07-28).
```csharp
[HarmonyPatch(typeof(TextureAtlasBlocks), nameof(TextureAtlasBlocks.LoadTextureAtlas))]
static void Postfix(TextureAtlasBlocks __instance, int _idx, MeshDescriptionCollection _tac, bool _bLoadTextures)
{
    if (!_bLoadTextures || _idx != MeshDescription.cIndexOpaque) return;   // terrain routes through here too
    MeshDescription md = _tac.Meshes[_idx];
    // md.TexDiffuse / TexNormal / TexSpecular are Texture2DArrays; null = headless.
    // 1) new Texture2DArray(w, h, depth + 1, src.graphicsFormat, TextureCreationFlags.MipChain, src.mipmapCount)
    //    + Graphics.CopyTexture(src, slice, mip, dst, slice, mip) for every slice/mip
    // 2) pre-fill the new slice from an existing one (valid data + right format), then overlay your own
    // 3) md.TexDiffuse = ...; atlas.diffuseTexture = md.TexDiffuse; (same for normal/specular)
    // 4) md.ReloadTextureArrays(false);   <- rebinds materials FROM THE ATLAS FIELDS, so step 3
    //    must come first; verify with ReferenceEquals(md.materials[0].mainTexture, yours)
    // 5) Array.Resize(ref __instance.uvMapping, n + 1); entry.index = newSlice; uv = (0,0,1,1); blockW/H = 1
    //    -> the block's "Texture" value is that uvMapping INDEX, not the slice
    // 6) release the originals with md.Unload(ref tex) - LAST, after every reference moved
}
```
**Inject LAST.** Paint frameworks (OcbCustomTextures & packs) register their slices while
`painting.xml` loads and derive their offsets from the atlas as they find it - extending it before
them makes *their* paints render *your* texture. Config order is painting.xml → blocks.xml, so run
the first injection from a `Block.LateInitAll` postfix; keep the atlas postfix for later rebuilds.
Resolve mesh and atlas live (`MeshDescription.meshes[cIndexOpaque].textureAtlas`) - that is what
`renderFace` reads. An out-of-range slice index **clamps to the last slice** instead of failing, so
every one of these mistakes shows up as "the block wears some other texture", never as an error.

Formats differ per channel (3.0.1): diffuse `RGBA_DXT1_SRGB`, normal `RGBA_DXT5_UNorm`, specular
`RGBA_DXT5_SRGB` - `Graphics.CopyTexture` needs an exact match, and a generated fill must take its
colour space from the target (`GraphicsFormatUtility.IsSRGBFormat`). Half texture quality halves the
atlas, so copy from the matching **mip** of your source, not mip 0.
```csharp
// mod bundle -> Texture2D, from C# (NOT the XML "#@modfolder:" form)
var tex = DataLoader.LoadAsset<Texture2D>("#" + mod.Path + "/Resources/x.unity3d?assetName", false);
// blocks are parsed AFTER the atlas -> assign the id from a Block.LateInitAll postfix,
// matching block.blockMaterial.id, replacing the numeric fallback in block.textureInfos[c]
```

## Buffs
```csharp
entityAlive.Buffs.AddBuff("buffName", -1, false, false, -1f);  // (_name,_instigatorId,_netSync,_fromElectrical,_buffDuration)
entityAlive.Buffs.HasBuff("buffName");
entityAlive.Buffs.RemoveBuff("buffName", -1, false);
```

## Kill / health
```csharp
entityAlive.SetDead();
entityAlive.Health;            // get/set int
entityAlive.AddHealth(int);
entityAlive.Kill(DamageResponse.New(true));   // _fatal
```

## Explosion direct from C# (alternative to the Explode buff action)
```csharp
GameManager.Instance.ExplosionServer(
    Vector3 worldPos, Vector3i blockPos, Quaternion rot,
    ExplosionData data, int entityId, float delay,
    bool removeBlockAtPos, ItemValue explosionSourceItem);
// ExplosionData ctor: new ExplosionData(DynamicProperties, MinEffectController)
//   fields: BlastPower(int) BlockDamage(float) BlockRadius(float) EntityDamage(float)
//           EntityRadius(int) DamageType(EnumDamageTypes) Duration ParticleIndex BuffActions(List)
```

## Custom AI task - subclass a vanilla brain
```csharp
// global namespace, name starts with EAI. Referenced as value="Name,MyAsm" (see resolution-and-xml.md)
public class EAIName : EAIApproachAndAttackTarget {   // inherits chase/pathing to `entityTarget`
    public override void SetData(Dictionary<string,string> d) { base.SetData(d); /* read custom keys */ }
    public override void Update() { base.Update(); /* proximity/attack logic; theEntity, entityTarget */ }
}
// EAIBase gives: theEntity (EntityAlive), Init/Start/Update/Continue/CanExecute/Reset/SetData
// EntityAlive: GetAttackTarget(), attackTarget, factionId(byte), position, IsDead()
```

## Custom MinEventAction - buff-triggered logic
```csharp
// global namespace, name starts with MinEventAction. action="Name, MyAsm"
public class MinEventActionName : MinEventActionTargetedBase {
    public override bool ParseXmlAttribute(XAttribute a) {
        if (base.ParseXmlAttribute(a)) return true;
        // read your attrs; parse floats with CultureInfo.InvariantCulture (XML uses '.')
        return false;
    }
    public override void Execute(MinEventParams p) {
        EntityAlive self = p.Self;   // also: p.Other, p.Position, p.ItemValue, p.Buff
        // ...
    }
}
```

## A rebindable key AND a rebindable controller button

Both screens are built at runtime from the live action set, so a mod-created `PlayerAction`
shows up on its own - but they read **different sources**, and getting only one of them is
the default failure mode.

| Screen | Class | Source | Honours `appliesToInputType`? |
|---|---|---|---|
| Options ▸ Controls | `XUiC_OptionsControls` | `PlayerActionSet.Actions` | yes - skips `None` / `ControllerOnly` |
| Options ▸ Controller | `XUiC_OptionsController` | public field `PlayerActionsBase.ControllerRebindableActions` | **no** |

So `EAppliesToInputType.Both` buys a keyboard row only. For a gamepad row the action must
also be appended to the list:

```csharp
// PlayerActionSet.CreatePlayerAction is protected -> AccessTools.
var create = AccessTools.Method(typeof(PlayerActionSet), "CreatePlayerAction",
                                new[] { typeof(string) });
var action = (PlayerAction)create.Invoke(input, new object[] { "MyModDash" });

action.UserData = new PlayerActionData.ActionUserData(
    "inpActMyDashName", "inpActMyDashDesc",
    PlayerActionData.GroupPlayerControl,      // -> tab "Movement", group "Player movement"
    PlayerActionData.EAppliesToInputType.Both,
    true, false, false, true);                // allowRebind, allowMultiple, doNotDisplay, defaultOnStartup
action.AddDefaultBinding(new[] { Key.V });

// The controller screen's separate list. Public instance field, no reflection.
if (!input.ControllerRebindableActions.Contains(action))
    input.ControllerRebindableActions.Add(action);
```

Three traps, all confirmed on 3.0.0 / 3.0.1 / 3.1.0:

- **The set is built ~19 s before mods load** (`PlayerActionsBase..ctor` → `InitActionSet()` →
  `CreateActions()` → `CreateDefaultKeyboardBindings()` → `CreateDefaultJoystickBindings()`,
  driven by `Factory.CreateInstances`). A postfix on `CreateActions` never fires for the set
  that exists. **Create the action lazily** on first use instead, reaching the set through
  `EntityPlayerLocal.playerInput` in-game and `__instance.xui.playerUI.playerInput` from a
  prefix on each screen's `createControlsEntries`. `CreatePlayerAction` is just
  `new PlayerAction(name, this)` with no init guard, `Actions` wraps the live list, and
  `LoadData` skips unknown names - so a late action is safe. `AddPlayerAction` **throws** on a
  duplicate name, so look it up first.
- **`CreateDefaultJoystickBindings` calls `Clear()` on `ControllerRebindableActions`** before
  refilling it, and it runs again on "Reset to defaults" in the controller options. Postfix it
  and re-append, or the row silently disappears until the next restart.
- **Patch each screen separately.** `XUiC_OptionsControls` and `XUiC_OptionsController` are
  sibling *overrides*; patching `XUiC_OptionsControlsBase.createControlsEntries` fires for
  neither.

Sizing and placement: the controller window has four binding tabs of `rows="22"` entries and
assigns `entries[i].Action = i < list.Count ? list[i] : null`, so an over-long list is
truncated **silently**; vanilla leaves plenty of room. An action in `GroupPlayerControl`
(tab key `inpTabPlayerControl`) is re-filed by that screen into **On Foot**.

Default gamepad binding: don't. Extracting the `InputControlType` constants from
`PlayerActionsLocal.CreateDefaultJoystickBindings` leaves only `DPadRight` (14) free on a
standard pad, so any default steals something the player did not ask about.

⚠ InControl serialises bindings **by action name**, keyboard and controller alike - renaming
the action resets every user's bindings.

⚠ None of this is smoke-testable. `-batchmode -nographics` runs no XUi and no input, so a
headless pass proves only that the Harmony targets still exist. The row and the keypress need
a GUI run.

## Harmony hooks that proved useful
```csharp
[HarmonyPatch(typeof(Inventory), "PUBLIC_SLOTS", MethodType.Getter)]       // toolbelt size
[HarmonyPatch(typeof(GameManager), "ExplosionServer")]                     // react to an explosion; filter by
//   Postfix(GameManager __instance, Vector3 _worldPos, ItemValue _itemValueExplosionSource)
//   compare _itemValueExplosionSource.ItemClass == ItemClass.GetItemClass("myItem", false)
```

## Player files & user-visible messages
```csharp
// Where player-supplied files belong. Honours -UserDataFolder (verified in a test run);
// GetUserGameDataDir() is literally GetDefaultUserGameDataPath(""). Do NOT use its Mods\
// subfolder - the game scans that for mods.
string dir = Path.Combine(GameIO.GetUserGameDataDir(), "MYMOD");

// Tell the player something went wrong, without building any UI. Static, 3 overloads.
GameManager.ShowTooltip(EntityPlayerLocal player, string text, string arg,
                        string alertSound, ToolTipEvent handler,
                        bool showImmediately, bool pinTooltip, float timeout);
// -> XUiC_PopupToolTip.QueueTooltip -> QueueTooltipInternal, which does
//    Localization.Get(text, false, null) then String.Format(text, args)
//    => pass a localization key and let {0} carry the detail.
EntityPlayerLocal p = world.GetPrimaryPlayer();   // virtual, on World
```

## WAV parsing (custom audio without an asset bundle)
```csharp
// Walk the RIFF chunks - the header is NOT a fixed 44 bytes; encoders insert LIST/INFO
// between 'fmt ' and 'data'. Chunks are word aligned: pos = body + size + (size & 1).
// fmt : +0 format(u16) +2 channels +4 sampleRate +14 bits
// WAVE_FORMAT_EXTENSIBLE (0xFFFE) IS PCM: the real code is the first 2 bytes of the
// SubFormat GUID at fmt+24 (chunk size >= 40). Rejecting 0xFFFE rejects ordinary files.
AudioClip c = AudioClip.Create(name, total / channels, channels, sampleRate, false);
c.SetData(samples, 0);   // Create wants samples PER CHANNEL, SetData the interleaved array
// Magic bytes worth naming in an error message: "ID3"/FF Ex = MP3, "OggS", "fLaC",
// "FORM" = AIFF, "ftyp" at offset 4 = MP4/M4A, 1A 45 DF A3 = Matroska, "PK" = ZIP.
```

## Factions & targeting
```csharp
FactionManager fm = ...;
fm.CreateFaction(name, playerFaction, icon);
fm.SetRelationship(byte myFaction, byte targetFaction, sbyte modification);
fm.GetRelationshipTier(EntityAlive a, EntityAlive b);
// Hunting hostiles is driven by the AITarget CLASS filter (SetNearestEntityAsTarget class=EntityEnemy,...),
// independent of faction. Faction controls who attacks whom.
```
