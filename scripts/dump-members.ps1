<#
.SYNOPSIS
  Dump the base-type chain, methods (with parameter types), fields and properties
  of one 7DTD type — the exact signatures you need to write compiling C#.
.EXAMPLE
  pwsh dump-members.ps1 EntityAlive 'AddBuff|Health|Kill' -Fields
  pwsh dump-members.ps1 GameManager 'Explos|Spawn'
.NOTES
  MethodFilter is a regex matched against method names ('' = all). -Fields / -Props
  include fields / properties (filtered by the same regex, '.' = all of them).
#>
param(
  [Parameter(Mandatory=$true)][string]$Type,
  [string]$MethodFilter = '',
  [switch]$Fields,
  [switch]$Props
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

$chain = @(); $bt = $t.BaseType
while ($bt) { $chain += $bt.Name; try { $d = $bt.Resolve() } catch { $d = $null }; if ($d) { $bt = $d.BaseType } else { break } }
Write-Host "### $($t.FullName)  :  $($chain -join ' -> ')"

foreach ($m in ($t.Methods | Where-Object { -not $_.IsConstructor -and ($MethodFilter -eq '' -or $_.Name -match $MethodFilter) } | Sort-Object Name)) {
    $ps = ($m.Parameters | ForEach-Object { $_.ParameterType.Name + ' ' + $_.Name }) -join ', '
    $mods = ''
    if ($m.IsStatic) { $mods += 'static ' }
    if ($m.IsVirtual -and -not $m.IsFinal) { $mods += 'virtual ' }
    Write-Host ("  {0}{1} {2}({3})" -f $mods, $m.ReturnType.Name, $m.Name, $ps)
}
if ($Fields) {
    Write-Host "  -- fields --"
    foreach ($f in ($t.Fields | Where-Object { $MethodFilter -eq '' -or $MethodFilter -eq '.' -or $_.Name -match $MethodFilter } | Sort-Object Name)) {
        $st = ''; if ($f.IsStatic) { $st = 'static ' }
        Write-Host ("  .{0} : {1} [{2}]" -f $f.Name, $f.FieldType.Name, $st.Trim())
    }
}
if ($Props) {
    Write-Host "  -- properties --"
    foreach ($p in ($t.Properties | Where-Object { $MethodFilter -eq '' -or $MethodFilter -eq '.' -or $_.Name -match $MethodFilter } | Sort-Object Name)) {
        Write-Host ("  {{prop}} {0} {1}" -f $p.PropertyType.Name, $p.Name)
    }
}

# Enum values, if this type is an enum
if ($t.IsEnum) {
    Write-Host "  -- enum values --"
    foreach ($f in ($t.Fields | Where-Object { $_.IsStatic })) { Write-Host ("  {0} = {1}" -f $f.Name, $f.Constant) }
}
