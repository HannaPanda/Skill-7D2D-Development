# API Reconnaissance - interrogate the real DLL, never guess

7DTD ships no modding API docs. The game's own `Assembly-CSharp.dll` **is** the spec, and it changes between versions. Before writing any C# that touches game types - or any XML that names a C# class/enum - confirm the real names, signatures and behaviour from the DLL for the installed version. This is what makes the skill self-correcting instead of drifting on stale memory.

`Mono.Cecil.dll` is already on disk (in `Mods\0_TFP_Harmony\`), so this needs no install and no game launch. Three scripts in `../scripts/`:

## 1. Discover what exists
```
pwsh scripts/dump-catalog.ps1 '<regex over FullName>'
```
e.g. `'^EAI'` (all AI tasks), `'MinEventAction'` (all buff actions), `'Explosion|Explode'`, `'^Entity'`.

## 2. Get exact signatures (to write compiling code)
```
pwsh scripts/dump-members.ps1 <TypeName> ['<methodNameRegex>'] [-Fields] [-Props]
```
Prints base-type chain + methods (with parameter types) + optionally fields/properties. If the type is an enum it prints the valid values (use this to validate any XML `*_type=` / enum attribute). Filter noisy giants: `dump-members.ps1 GameManager 'Explos|Spawn'`.

## 3. Understand HOW the game decides something
```
pwsh scripts/dump-il.ps1 <TypeName> <MethodName>
```
Reads the CIL. Use when a mechanism matters: how an XML task name maps to a class, what string format a parser accepts, whether a lookup searches other assemblies, what an enum parse rejects. Reading IL is tedious but definitive - every resolution rule in resolution-and-xml.md was derived this way.

## Workflow
1. `dump-catalog` to find the type.
2. `dump-members` for the signatures you'll call / subclass / override.
3. `dump-il` only for the one or two methods whose *behaviour* you must be sure of.
4. Write code, `dotnet build` → a clean build against the real DLL is your correctness proof for API usage (it cannot catch runtime/logic errors - those show up in the log, see below).

## Reading the runtime log
After an in-game test, grep the newest `output_log_client__*.txt` for your mod name and for `WRN`/`EXC`/`ERR`/`not found`/`Unable to find`. XML load errors and class-resolution failures land there with the exact bad value. Feed those back into a `dump-*` query, fix, restart. Append every non-obvious cause→fix you confirm to `../LEARNINGS.md`.
