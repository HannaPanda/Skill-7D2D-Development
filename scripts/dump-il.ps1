<#
.SYNOPSIS
  Print the CIL instructions of one method. Use this to answer "HOW does the game
  resolve/parse/decide X?" — e.g. how XML names map to C# classes, what an enum
  parse accepts, whether a lookup searches other assemblies.
.EXAMPLE
  pwsh dump-il.ps1 EAIManager GetType
  pwsh dump-il.ps1 ReflectionHelpers GetTypeWithPrefix
.NOTES
  Reading IL beats guessing. The whole "custom class resolution" knowledge in this
  skill came from dumping EAIManager.GetType and ReflectionHelpers.GetTypeWithPrefix.
#>
param(
  [Parameter(Mandatory=$true)][string]$Type,
  [Parameter(Mandatory=$true)][string]$Method
)
$ErrorActionPreference = 'Stop'

$game = if ($env:SDTD_DIR) { $env:SDTD_DIR } else { 'C:\Steam\steamapps\common\7 Days To Die' }
$managed = Join-Path $game '7DaysToDie_Data\Managed'
Add-Type -Path (Join-Path $game 'Mods\0_TFP_Harmony\Mono.Cecil.dll')

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($managed)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $managed 'Assembly-CSharp.dll'), $rp)

$t = $asm.MainModule.Types | Where-Object { $_.Name -eq $Type -or $_.FullName -eq $Type } | Select-Object -First 1
if (-not $t) { Write-Host "NOT FOUND: $Type"; exit 1 }

foreach ($m in ($t.Methods | Where-Object { $_.Name -eq $Method })) {
    $ps = ($m.Parameters | ForEach-Object { $_.ParameterType.Name + ' ' + $_.Name }) -join ', '
    Write-Host "### $($t.Name).$($m.Name)($ps)"
    if ($m.HasBody) { foreach ($i in $m.Body.Instructions) { Write-Host ("  " + $i.ToString()) } }
    else { Write-Host "  (no body)" }
    Write-Host ""
}
