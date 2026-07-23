#!/usr/bin/env pwsh

# ── Your script block ───────────────────────────────────────
$MainPayload = {
  param(
    [Parameter(Mandatory)][ValidateLength(3,20)][string]$Name,
    [ValidateSet('admin','user','viewer')][string]$Role = 'user',
    [ValidatePattern('^\S+@\S+$')][string]$Email,
    [switch]$Notify
  )
  Write-Host "  Created user '$Name'" -ForegroundColor Green
  Write-Host "  Role: $Role" -ForegroundColor Cyan
  if ($Email) { Write-Host "  Email: $Email" -ForegroundColor Cyan }
  if ($Notify) { Write-Host "  Notification sent" -ForegroundColor Yellow }
}

# ── CLI machinery (paste this at the bottom) ────────────────
function Invoke-Cli {
  param([Parameter(ValueFromRemainingArguments)][string[]]$A)
  if (!$MainPayload -or $MainPayload -isnot [scriptblock]) { Write-Host "Define `$MainPayload = { param(...) ... } first"; exit 1 }

  # Get parameter metadata via Get-Command.
  # Strip [Credential()] when before $param (PS bug: makes Parameters return null).
  # Regex only matches when followed by $ to avoid modifying string literals/comments.
  $commonParams = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','ConfirmImpact','WhatIf','Confirm')
  $tmpName = "__pscli_$([Guid]::NewGuid().ToString('N'))"
  $body = "$MainPayload"
  $body = $body -replace '\[Credential\s*\(\s*\)\]', ''
  $null = New-Item -Path "Function:" -Name $tmpName -Value ([scriptblock]::Create($body)) -Force
  $cmd = Get-Command $tmpName
  Remove-Item "Function:$tmpName" -Force
  $defaults = @{}; if ($MainPayload.Ast.ParamBlock) { $MainPayload.Ast.ParamBlock.Parameters | % { $v = $_.DefaultValue; if ($v) { $defaults[$_.Name.VariablePath.UserPath] = $v.Value } } }
  $b = @{}; $i = 0; $unknown = @(); $paramList = if ($cmd.Parameters) { @($cmd.Parameters.Values) } else { @() }; $consumed = @{}

  if ($A -contains '-h' -or $A -contains '--help') { Write-Host "`nUsage: $(Split-Path $MyInvocation.ScriptName -Leaf) [options]`n"
    $paramList | ? { $_.Name -notin $commonParams } | % {
      Write-Host "  -$($_.Name)" -NoNewline -ForegroundColor Yellow
      $flags = @()
      if ($_.Attributes | ? { $_ -is [Parameter] -and $_.Mandatory }) { $flags += 'required' }
      $_.Attributes | ? { $_ -is [ValidateSet] } | % { $flags += "$($_.ValidValues -join '/')" }
      if ($defaults[$_.Name]) { $flags += "default=$($defaults[$_.Name])" }
      if ($_.ParameterType -eq [PSCredential] -or ($_.Attributes | ? { $_ -is [System.Management.Automation.CredentialAttribute] })) { $flags += 'credential' }
      if ($_.Aliases) { $flags += "alias: $($_.Aliases -join ',')" }
      if ($flags) { Write-Host " ($($flags-join', '))" -NoNewline }; Write-Host "" }; return }
  $allNames = $paramList | % { $n = $_.Name; $n }
  $paramList | % { $_.Aliases | % { $allNames += $_ } }
  $lookupByKey = @{}; $paramList | % { $lookupByKey[$_.Name] = $_; $_.Aliases | % { $lookupByKey[$_] = $_ } }

  while ($i -lt $A.Count) {
    if ($A[$i] -match '^--?(\w[\w-]*)([:=])(.*)') { $k = $Matches[1]; $v = $Matches[3]
      $p = $lookupByKey[$k]; $consumed[$i] = $true
      if ($p) { if ($p.ParameterType -eq [switch]) { $b[$p.Name] = $v -notin '0','false','$false','no' } else { $b[$p.Name] = $v } }
      else { $unknown += "-$k" } }
    elseif ($A[$i] -match '^--?(\w[\w-]*)') { $k = $Matches[1]; $consumed[$i] = $true
      if ($k -in $allNames) { $p = $lookupByKey[$k]
        if ($p.ParameterType -eq [switch]) { $b[$p.Name] = $true }
        elseif ($i + 1 -lt $A.Count -and $A[$i+1] -notmatch '^--?') { $b[$p.Name] = $A[++$i]; $consumed[$i] = $true }
        else { Write-Host "Warning: -$k requires a value" -ForegroundColor Yellow } }
      else { $unknown += "-$k" } }
    $i++ }
  if ($unknown) { Write-Host "Warning: unknown parameter(s): $($unknown -join ', ')" -ForegroundColor Yellow }

  # Positional binding: bind remaining non-flag args to [Parameter(Position=N)] params
  $posParams = @($paramList | ? { ($_.Attributes | ? { $_ -is [Parameter] -and $_.Position -ge 0 }) } | Sort-Object { ($_.Attributes | ? { $_ -is [Parameter] } | Select-Object -First 1).Position } )
  $posValues = @(); $j = 0; while ($j -lt $A.Count) { if (!$consumed[$j] -and $A[$j] -notmatch '^--?') { $posValues += $A[$j] }; $j++ }
  $k = 0; $posParams | % { if ($k -lt $posValues.Count -and !$b.ContainsKey($_.Name)) { $b[$_.Name] = $posValues[$k]; $k++ } }

  # Determine active parameter set
  $activeSet = $null
  $boundSets = @($b.Keys | % { $paramList | ? { $_.Name -eq $_ } } | % { $_.ParameterSets } | ? { $_.Name -ne '__AllParameterSets' } | % Name)
  if ($boundSets) {
    $common = $boundSets | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
    if ($common.Count -ge $b.Count) { $activeSet = $common.Name }
  }

  $interactive = $A.Count -eq 0

  # Convert string values to PSCredential for credential params (after $interactive is set)
  $paramList | ? { $_.ParameterType -eq [PSCredential] -or ($_.Attributes | ? { $_ -is [System.Management.Automation.CredentialAttribute] }) } | % {
    if ($b.ContainsKey($_.Name) -and $b[$_.Name] -is [string]) {
      $pass = Read-Host "Password for $($b[$_.Name])" -AsSecureString
      $b[$_.Name] = [PSCredential]::new($b[$_.Name], $pass) }
    elseif (!$b.ContainsKey($_.Name) -and !$interactive -and $_.Attributes | ? { $_ -is [Parameter] -and $_.Mandatory }) {
      Write-Host "Missing required credential: $($_.Name)" -ForegroundColor Red; exit 1 } }
  $missing = if ($interactive) { @($paramList | ? { $_.Name -notin $commonParams }) }
  else { @($paramList | ? { ($_.Attributes | ? { $_ -is [Parameter] -and $_.Mandatory -and ($_.ParameterSetName -eq '__AllParameterSets' -or !$_.ParameterSetName -or $_.ParameterSetName -eq $activeSet) }) -and !$b.ContainsKey($_.Name) }) }

  if ($missing) {
    if (!$interactive) { Write-Host "Missing required: $($missing.Name -join ', ')" -ForegroundColor Red; exit 1 }
    Write-Host "`n== Interactive mode ==" -ForegroundColor Green }

  try { $missing | ? { $_.Name -notin $commonParams } | % { $p = $_
    $n = $p.Name; $d = $defaults[$n]
    $isSwitch = $p.ParameterType -eq [switch]
    $setAttr = $p.Attributes | ? { $_ -is [ValidateSet] } | Select-Object -First 1
    $vals = if ($setAttr) { @($setAttr.ValidValues) } else { $null }
    $mandatory = ($p.Attributes | ? { $_ -is [Parameter] -and $_.Mandatory }) -ne $null
    do { $ok = $true
      if ($vals) { "$($n):" | Out-Host; $i = 0; $vals | % { "  $($i+1). $_" | Out-Host; $i++ }; $c = Read-Host "Choose (1-$($vals.Count))"
        if ([string]::IsNullOrEmpty($c) -and $d -ne $null) { $b[$n] = $d }
        elseif ([string]::IsNullOrEmpty($c) -and $mandatory) { $ok = $false }
        elseif ($c -match '^[1-9]\d*$' -and [int]$c -le $vals.Count) { $b[$n] = $vals[[int]$c - 1] }
        elseif ([string]::IsNullOrEmpty($c)) { }
        else { $ok = $false } }
      elseif ($isSwitch) { $v = Read-Host "$n (y/n)"
        if ([string]::IsNullOrEmpty($v) -or $v -in 'n','no','false','0') { $b[$n] = $false }
        elseif ($v -in 'y','yes','true','1') { $b[$n] = $true }
        else { $ok = $false } }
      elseif ($p.ParameterType -eq [PSCredential]) { $u = Read-Host "$n username"
        if ([string]::IsNullOrEmpty($u)) { if ($mandatory) { $ok = $false } }
        else { $sec = Read-Host "$n password" -AsSecureString; $b[$n] = [PSCredential]::new($u, $sec) } }
      else { $v = Read-Host $(if ($d -ne $null) { "$n [$d]" } else { $n })
        if ([string]::IsNullOrEmpty($v)) { if ($d -ne $null) { $b[$n] = $d } elseif ($mandatory) { $ok = $false } }
        else { $allowNull = $p.Attributes | ? { $_ -is [System.Management.Automation.AllowNullAttribute] }
          $allowEmpty = $p.Attributes | ? { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }
          $errs = @()
          $p.Attributes | % {
            if ($_ -is [System.Management.Automation.ValidatePatternAttribute] -and $v -notmatch $_.RegexPattern) { $errs += "'$v' does not match pattern $($_.RegexPattern)" }
            if ($_ -is [System.Management.Automation.ValidateLengthAttribute] -and ("$v".Length -lt $_.MinLength -or "$v".Length -gt $_.MaxLength)) { $errs += "'$v' length ($("$v".Length)) not in [$($_.MinLength),$($_.MaxLength)]" }
            if ($_ -is [System.Management.Automation.ValidateSetAttribute] -and $v -notin $_.ValidValues) { $errs += "'$v' not in [$($_.ValidValues -join ',')]" }
            if ($_ -is [System.Management.Automation.ValidateRangeAttribute]) { $num = [double]$v; if ($num -lt $_.MinRange -or $num -gt $_.MaxRange) { $errs += "'$v' not in [$($_.MinRange),$($_.MaxRange)]" } }
            if ($_ -is [System.Management.Automation.ValidateScriptAttribute]) { $sb = $_.ScriptBlock; if (!($v | ForEach-Object { & $sb })) { $errs += "'$v' failed script validation" } }
            if ($_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] -and !$allowNull -and !$allowEmpty -and [string]::IsNullOrEmpty("$v")) { $errs += "'$v' cannot be null or empty" }
            if ($_ -is [System.Management.Automation.ValidateNotNullAttribute] -and !$allowNull -and $v -eq $null) { $errs += "'$v' cannot be null" }
            if ($_ -is [System.Management.Automation.ValidateCountAttribute]) { $c = @($v).Count; if ($c -lt $_.MinLength -or $c -gt $_.MaxLength) { $errs += "'$v' count ($c) not in [$($_.MinLength),$($_.MaxLength)]" } } }
          if ($errs) { $errs | % { Write-Host "  $_" -ForegroundColor Red }; $ok = $false } else { $b[$n] = $v } } }
    } while (!$ok) } } catch { Write-Host "Error: $_" -ForegroundColor Red; exit 1 }
  try { if ($b.Count) { & $MainPayload @b } else { & $MainPayload } } catch { Write-Host "Error: $_" -ForegroundColor Red; exit 1 }
}
Invoke-Cli @args
