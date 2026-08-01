<#
.SYNOPSIS
  List every type in the 7DTD Assembly-CSharp whose FullName matches a regex.
.EXAMPLE
  pwsh dump-catalog.ps1 '^EAI|Explosion|MinEventAction'
.NOTES
  Reads metadata via Mono.Cecil (shipped with the game's TFP Harmony) — no game
  launch, no reflection load of Unity deps. This is how you DISCOVER what exists
  before touching it. Override the game dir with $env:SDTD_DIR if it moved.
#>
param([Parameter(Mandatory=$true)][string]$Pattern)
$ErrorActionPreference = 'Stop'

$game = if ($env:SDTD_DIR) { $env:SDTD_DIR } else { 'C:\Steam\steamapps\common\7 Days To Die' }
$managed = Join-Path $game '7DaysToDie_Data\Managed'
Add-Type -Path (Join-Path $game 'Mods\0_TFP_Harmony\Mono.Cecil.dll')

$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $managed 'Assembly-CSharp.dll'))
$asm.MainModule.Types |
    Where-Object { $_.FullName -match $Pattern } |
    Sort-Object FullName |
    ForEach-Object { $_.FullName }
