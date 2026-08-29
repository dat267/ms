#!/usr/bin/env pwsh

# ── Your script block ───────────────────────────────────────
# Example: a user-manager CLI that exercises (almost) every supported
# attribute type. Copy this file and replace $MainPayload with your own logic.
$MainPayload = {
  <#
  .SYNOPSIS
  Provision a user account, demonstrating all cli.ps1 attribute features.
  .PARAMETER Name
  Unique username (3-20 characters).
  .PARAMETER Role
  Authorization level for the account.
  .PARAMETER Email
  Contact email address (must look like an address).
  .PARAMETER Tags
  Labels for the account. Repeat the flag (-t dev -t prod) or comma-separate (-t dev,prod).
  .PARAMETER HomeDir
  Home directory. Positional: pass it without a flag.
  .PARAMETER Offset
  Signed offset, must be in range [-10, 10] (demonstrates negative numbers).
  .PARAMETER Token
  Access token; must end with the literal 'ok'.
  .PARAMETER Password
  Account password (masked entry).
  .PARAMETER Credential
  Full credentials as a PSCredential (username + password).
  .PARAMETER Notify
  Send a notification when the account is created.
  #>
  param(
    [Parameter(Mandatory)][ValidateLength(3,20)][string]$Name,
    [ValidateSet('admin','user','viewer')][string]$Role = 'user',
    [ValidatePattern('^\S+@\S+$')][string]$Email,
    [Alias('t')][ValidateCount(1,5)][string[]]$Tags,
    [Parameter(Position=0)][string]$HomeDir,
    [ValidateRange(-10,10)][int]$Offset = 0,
    [ValidateScript({ $_ -like '*ok' })][string]$Token,
    [securestring]$Password,
    [PSCredential]$Credential,
    [switch]$Notify
  )
  Write-Host "  Created user '$Name'" -ForegroundColor Green
  Write-Host "  Role: $Role" -ForegroundColor Cyan
  if ($Email) { Write-Host "  Email: $Email" -ForegroundColor Cyan }
  if ($Tags) { Write-Host "  Tags: $($Tags -join ', ')" -ForegroundColor Cyan }
  if ($HomeDir) { Write-Host "  HomeDir: $HomeDir" -ForegroundColor Cyan }
  Write-Host "  Offset: $Offset" -ForegroundColor Cyan
  if ($Token) { Write-Host "  Token: $Token" -ForegroundColor Cyan }
  if ($Password) { Write-Host "  Password set (length: $($Password.Length))" -ForegroundColor Cyan }
  if ($Credential) { Write-Host "  Credential: $($Credential.UserName)" -ForegroundColor Cyan }
  if ($Notify) { Write-Host "  Notification sent" -ForegroundColor Yellow }
}

# ── CLI machinery (paste this at the bottom) ────────────────
function Invoke-Cli {
  param([Parameter(ValueFromRemainingArguments)][string[]]$A)
  if (!$MainPayload -or $MainPayload -isnot [scriptblock]) {
    return Stop-Cli "Define `$MainPayload = { param(...) ... } first"
  }

  # Helper to exit/return without killing interactive sessions.
  # In a real console or remote host the script is the process entry point, so
  # terminating with the exit code is correct (this is what makes `pwsh -File`
  # return a non-zero code on error). In non-console hosts (e.g. ISE) we must not
  # kill the host, so we return instead.
  function Stop-Cli {
    param([string]$Message, [int]$ExitCode = 1)
    if ($Message) { Write-Host $Message -ForegroundColor Red }
    $global:LASTEXITCODE = $ExitCode
    if ($Host.Name -match 'ConsoleHost|ServerRemoteHost') {
      exit $ExitCode
    } else {
      return $ExitCode
    }
  }

  # Get parameter metadata via Get-Command.
  # Strip [Credential()] when before $param (PS bug: makes Parameters return null).
  $commonParams = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','ConfirmImpact','WhatIf','Confirm')
  $tmpName = "__pscli_$([Guid]::NewGuid().ToString('N'))"
  $sbText = "$MainPayload"
  if ($sbText -match '\[Credential\s*\(\s*\)\]') {
    $cleanText = $sbText -replace '\[Credential\s*\(\s*\)\]', ''
    $null = Set-Item -Path "Function:$tmpName" -Value ([scriptblock]::Create($cleanText)) -Force
  } else {
    $null = Set-Item -Path "Function:$tmpName" -Value $MainPayload -Force
  }
  $cmd = Get-Command $tmpName
  Remove-Item "Function:$tmpName" -Force -ErrorAction SilentlyContinue

  # Extract parameter default values safely from AST
  $defaults = @{}
  if ($MainPayload.Ast.ParamBlock) {
    $MainPayload.Ast.ParamBlock.Parameters | ForEach-Object {
      $v = $_.DefaultValue
      if ($v) {
        $val = try { $v.SafeGetValue() } catch { $v.Extent.Text.Trim() }
        $defaults[$_.Name.VariablePath.UserPath] = $val
      }
    }
  }

  $paramList = if ($cmd.Parameters) { @($cmd.Parameters.Values) } else { @() }
  
  # Help display (-h / --help)
  if ($A -contains '-h' -or $A -contains '--help') {
    $scriptName = if ($MyInvocation.ScriptName) { Split-Path $MyInvocation.ScriptName -Leaf } else { 'cli.ps1' }
    $cbh = try { if ($MainPayload.Ast.GetHelpContent) { $MainPayload.Ast.GetHelpContent() } } catch { $null }
    $helpParams = if ($cbh -and $cbh.Parameters) { $cbh.Parameters } else { @{} }

    Write-Host "`nUsage: $scriptName [options]`n" -ForegroundColor Cyan
    if ($cbh -and $cbh.Synopsis) {
      Write-Host "$($cbh.Synopsis)`n" -ForegroundColor Gray
    }

    $paramList | Where-Object { $_.Name -notin $commonParams } | ForEach-Object {
      $p = $_
      $typeName = $p.ParameterType.Name
      if ($typeName -eq 'SwitchParameter') { $typeName = 'switch' }

      Write-Host "  -$($p.Name)" -NoNewline -ForegroundColor Yellow
      Write-Host " <$typeName>" -NoNewline -ForegroundColor DarkGray

      $flags = @()
      if ($p.Attributes | Where-Object { $_ -is [Parameter] -and $_.Mandatory }) { $flags += 'required' }
      $p.Attributes | Where-Object { $_ -is [ValidateSet] } | ForEach-Object { $flags += "$($_.ValidValues -join '/')" }
      if ($defaults.ContainsKey($p.Name)) { $flags += "default=$($defaults[$p.Name])" }
      if ($p.ParameterType -eq [PSCredential] -or ($p.Attributes | Where-Object { $_ -is [System.Management.Automation.CredentialAttribute] })) { $flags += 'credential' }
      if ($p.ParameterType -eq [securestring]) { $flags += 'securestring' }
      if ($p.Aliases) { $flags += "alias: $($p.Aliases -join ',')" }

      if ($flags) { Write-Host " ($($flags -join ', '))" -NoNewline -ForegroundColor DarkCyan }

      $paramHelpKey = $p.Name.ToUpper()
      if ($helpParams.ContainsKey($paramHelpKey)) {
        Write-Host "`n    $($helpParams[$paramHelpKey].Trim())" -ForegroundColor Gray
      } else {
        Write-Host ""
      }
    }
    Write-Host ""
    return
  }

  # Build lookup dictionaries including kebab-case aliases
  $allNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $lookupByKey = @{}
  $paramList | ForEach-Object {
    $p = $_
    $n = $p.Name
    [void]$allNames.Add($n)
    $lookupByKey[$n] = $p

    # Automatic kebab-case alias (e.g. RoleName -> role-name)
    $kebab = ($n -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLower()
    if ($kebab -ne $n.ToLower()) {
      [void]$allNames.Add($kebab)
      $lookupByKey[$kebab] = $p
    }

    $p.Aliases | ForEach-Object {
      [void]$allNames.Add($_)
      $lookupByKey[$_] = $p
      $aliasKebab = ($_ -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLower()
      [void]$allNames.Add($aliasKebab)
      $lookupByKey[$aliasKebab] = $p
    }
  }

  $b = @{}
  $i = 0
  $unknown = @()
  $consumed = @{}

  # Parse command line options
  while ($i -lt $A.Count) {
    if ($A[$i] -match '^--?(\w[\w-]*)([:=])(.*)') {
      $k = $Matches[1]; $v = $Matches[3]
      $p = $lookupByKey[$k]
      $consumed[$i] = $true
      if ($p) {
        if ($p.ParameterType -eq [switch]) {
          $b[$p.Name] = $v -notin '0','false','$false','no'
        } elseif ($p.ParameterType.IsArray) {
          $items = @($v -split ',')
          if ($b.ContainsKey($p.Name)) { $b[$p.Name] += $items } else { $b[$p.Name] = $items }
        } else {
          $b[$p.Name] = $v
        }
      } else {
        $unknown += "-$k"
      }
    }
    elseif ($A[$i] -match '^--?([a-zA-Z_][\w-]*)') {
      $k = $Matches[1]
      $consumed[$i] = $true
      if ($lookupByKey.ContainsKey($k)) {
        $p = $lookupByKey[$k]
        if ($p.ParameterType -eq [switch]) {
          $b[$p.Name] = $true
        }
        # Note: -notmatch '^--?[a-zA-Z_]' ensures negative numbers like -10 are treated as values, not flags!
        elseif ($i + 1 -lt $A.Count -and $A[$i+1] -notmatch '^--?[a-zA-Z_]') {
          $val = $A[++$i]
          $consumed[$i] = $true
          if ($p.ParameterType.IsArray) {
            $items = @($val -split ',')
            if ($b.ContainsKey($p.Name)) { $b[$p.Name] += $items } else { $b[$p.Name] = $items }
          } else {
            $b[$p.Name] = $val
          }
        }
        else {
          Write-Host "Warning: -$k requires a value" -ForegroundColor Yellow
        }
      }
      else {
        $unknown += "-$k"
      }
    }
    $i++
  }

  if ($unknown) {
    Write-Host "Warning: unknown parameter(s): $($unknown -join ', ')" -ForegroundColor Yellow
  }

  # Positional argument binding
  $posParams = @($paramList | Where-Object { ($_.Attributes | Where-Object { $_ -is [Parameter] -and $_.Position -ge 0 }) } | Sort-Object { ($_.Attributes | Where-Object { $_ -is [Parameter] } | Select-Object -First 1).Position })
  $posValues = @()
  $j = 0
  while ($j -lt $A.Count) {
    if (!$consumed[$j] -and $A[$j] -notmatch '^--?[a-zA-Z_]') { $posValues += $A[$j] }
    $j++
  }
  $k = 0
  $posParams | ForEach-Object {
    if ($k -lt $posValues.Count -and !$b.ContainsKey($_.Name)) {
      $p = $_
      if ($p.ParameterType.IsArray) {
        $b[$p.Name] = @($posValues[$k..($posValues.Count-1)])
        $k = $posValues.Count
      } else {
        $b[$p.Name] = $posValues[$k]
        $k++
      }
    }
  }

  # Active parameter set determination
  $activeSet = $null
  $boundSets = @($b.Keys | ForEach-Object { $paramName = $_; $paramList | Where-Object { $_.Name -eq $paramName } } | ForEach-Object { $_.ParameterSets } | Where-Object { $_.Name -ne '__AllParameterSets' } | ForEach-Object Name)
  if ($boundSets) {
    $common = $boundSets | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
    if ($common.Count -ge $b.Count) { $activeSet = $common.Name }
  }

  $interactive = $A.Count -eq 0

  # Convert string arguments to SecureString if parameter type is SecureString
  $paramList | Where-Object { $_.ParameterType -eq [securestring] } | ForEach-Object {
    $p = $_
    if ($b.ContainsKey($p.Name) -and $b[$p.Name] -is [string]) {
      $b[$p.Name] = ConvertTo-SecureString $b[$p.Name] -AsPlainText -Force
    }
  }

  # Credential binding for PSCredential parameters
  $paramList | Where-Object { $_.ParameterType -eq [PSCredential] -or ($_.Attributes | Where-Object { $_ -is [System.Management.Automation.CredentialAttribute] }) } | ForEach-Object {
    $p = $_
    if ($b.ContainsKey($p.Name) -and $b[$p.Name] -is [string]) {
      if ($Host.UI -and $Host.UI.ReadLine) {
        $pass = Read-Host "Password for $($b[$p.Name])" -AsSecureString
        $b[$p.Name] = [PSCredential]::new($b[$p.Name], $pass)
      }
    }
    elseif (!$b.ContainsKey($p.Name) -and !$interactive -and ($p.Attributes | Where-Object { $_ -is [Parameter] -and $_.Mandatory })) {
      return Stop-Cli "Missing required credential: $($p.Name)"
    }
  }

  # Identify missing parameters
  $missing = if ($interactive) {
    @($paramList | Where-Object { $_.Name -notin $commonParams })
  } else {
    @($paramList | Where-Object {
      ($_.Attributes | Where-Object { $_ -is [Parameter] -and $_.Mandatory -and ($_.ParameterSetName -eq '__AllParameterSets' -or !$_.ParameterSetName -or $_.ParameterSetName -eq $activeSet) }) -and !$b.ContainsKey($_.Name)
    })
  }

  if ($missing) {
    if (!$interactive) {
      return Stop-Cli "Missing required parameter(s): $($missing.Name -join ', ')"
    }
    Write-Host "== Interactive mode ==" -ForegroundColor Green
  }

  # Interactive prompt loop
  try {
    $missing | Where-Object { $_.Name -notin $commonParams } | ForEach-Object {
      $p = $_
      $n = $p.Name
      $d = $defaults[$n]
      $isSwitch = $p.ParameterType -eq [switch]
      $isArray = $p.ParameterType.IsArray
      $setAttr = $p.Attributes | Where-Object { $_ -is [ValidateSet] } | Select-Object -First 1
      $vals = if ($setAttr) { @($setAttr.ValidValues) } else { $null }
      $mandatory = ($p.Attributes | Where-Object { $_ -is [Parameter] -and $_.Mandatory }) -ne $null

      do {
        $ok = $true

        # 1. ValidateSet Parameters
        if ($vals) {
          "$($n):" | Out-Host
          $idx = 0
          $vals | ForEach-Object { "  $($idx+1). $_" | Out-Host; $idx++ }
          $promptMsg = if ($d -ne $null) { "Choose (1-$($vals.Count)) [$d]" } else { "Choose (1-$($vals.Count))" }
          $c = Read-Host $promptMsg

          if ([string]::IsNullOrEmpty($c)) {
            if ($d -ne $null) { $b[$n] = $d }
            elseif ($mandatory) { $ok = $false; Write-Host "  Value is required." -ForegroundColor Red }
          }
          elseif ($c -match '^[1-9]\d*$' -and [int]$c -le $vals.Count) {
            $b[$n] = $vals[[int]$c - 1]
          }
          else {
            $matchedVal = $vals | Where-Object { $_ -eq $c } | Select-Object -First 1
            if ($matchedVal) {
              $b[$n] = $matchedVal
            } else {
              Write-Host "  Invalid option '$c'. Choose a number (1-$($vals.Count)) or option name ($($vals -join '/'))" -ForegroundColor Red
              $ok = $false
            }
          }
        }
        # 2. Switch Parameters
        elseif ($isSwitch) {
          $defaultHint = if ($d -eq $true) { " [Y/n]" } elseif ($d -eq $false) { " [y/N]" } else { " (y/n)" }
          $v = Read-Host "$n$defaultHint"
          if ([string]::IsNullOrEmpty($v)) {
            if ($d -ne $null) { $b[$n] = [bool]$d } else { $b[$n] = $false }
          }
          elseif ($v -in 'y','yes','true','1') { $b[$n] = $true }
          elseif ($v -in 'n','no','false','0') { $b[$n] = $false }
          else {
            Write-Host "  Please enter y or n." -ForegroundColor Red
            $ok = $false
          }
        }
        # 3. SecureString Parameters
        elseif ($p.ParameterType -eq [securestring]) {
          $promptLabel = if ($d -ne $null) { "$n [$d]" } elseif (!$mandatory) { "$n (optional)" } else { $n }
          if ([Console]::IsInputRedirected) {
            $rawInput = Read-Host $promptLabel
            if (![string]::IsNullOrEmpty($rawInput)) {
              $b[$n] = ConvertTo-SecureString $rawInput -AsPlainText -Force
            } elseif ($d -ne $null) {
              $b[$n] = if ($d -is [securestring]) { $d } else { ConvertTo-SecureString "$d" -AsPlainText -Force }
            } elseif ($mandatory) {
              $ok = $false; Write-Host "  Value is required." -ForegroundColor Red
            }
          } else {
            $sec = Read-Host $promptLabel -AsSecureString
            if ($sec.Length -eq 0) {
              if ($d -ne $null) {
                $b[$n] = if ($d -is [securestring]) { $d } else { ConvertTo-SecureString "$d" -AsPlainText -Force }
              } elseif ($mandatory) {
                $ok = $false; Write-Host "  Value is required." -ForegroundColor Red
              }
            } else {
              $b[$n] = $sec
            }
          }
        }
        # 4. PSCredential Parameters
        elseif ($p.ParameterType -eq [PSCredential] -or ($p.Attributes | Where-Object { $_ -is [System.Management.Automation.CredentialAttribute] })) {
          $u = Read-Host "$n username"
          if ([string]::IsNullOrEmpty($u)) {
            if ($mandatory) { $ok = $false; Write-Host "  Username is required." -ForegroundColor Red }
          } else {
            if ([Console]::IsInputRedirected) {
              $rawPass = Read-Host "$n password"
              $sec = if ([string]::IsNullOrEmpty($rawPass)) { [securestring]::new() } else { ConvertTo-SecureString $rawPass -AsPlainText -Force }
            } else {
              $sec = Read-Host "$n password" -AsSecureString
            }
            $b[$n] = [PSCredential]::new($u, $sec)
          }
        }
        # 5. General Input Parameters
        else {
          $promptLabel = if ($d -ne $null) { "$n [$d]" } elseif (!$mandatory) { "$n (optional)" } else { $n }
          $v = Read-Host $promptLabel

          if ([string]::IsNullOrEmpty($v)) {
            if ($d -ne $null) { $b[$n] = $d }
            elseif ($mandatory) { $ok = $false; Write-Host "  Value is required." -ForegroundColor Red }
          }
          else {
            $valToBind = if ($isArray) { @($v -split ',') } else { $v }
            $allowNull = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowNullAttribute] }
            $allowEmpty = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }
            $errs = @()

            $p.Attributes | ForEach-Object {
              try {
                if ($_ -is [System.Management.Automation.ValidatePatternAttribute] -and $v -notmatch $_.RegexPattern) {
                  $errs += "'$v' does not match pattern $($_.RegexPattern)"
                }
                if ($_ -is [System.Management.Automation.ValidateLengthAttribute] -and ("$v".Length -lt $_.MinLength -or "$v".Length -gt $_.MaxLength)) {
                  $errs += "'$v' length ($("$v".Length)) not in range [$($_.MinLength),$($_.MaxLength)]"
                }
                if ($_ -is [System.Management.Automation.ValidateSetAttribute] -and $v -notin $_.ValidValues) {
                  $errs += "'$v' not in valid set [$($_.ValidValues -join ',')]"
                }
                if ($_ -is [System.Management.Automation.ValidateRangeAttribute]) {
                  if ($v -notmatch '^-?\d+(\.\d+)?$') {
                    $errs += "'$v' is not a valid number"
                  } else {
                    $num = [double]$v
                    if ($num -lt $_.MinRange -or $num -gt $_.MaxRange) {
                      $errs += "'$v' not in range [$($_.MinRange),$($_.MaxRange)]"
                    }
                  }
                }
                if ($_ -is [System.Management.Automation.ValidateScriptAttribute]) {
                  $sb = $_.ScriptBlock
                  $res = $false
                  try { $res = [bool]($v | ForEach-Object { & $sb }) } catch { $errs += "Validation script exception: $_"; $res = $false }
                  if (!$res -and !$errs) { $errs += "'$v' failed script validation" }
                }
                if ($_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] -and !$allowNull -and !$allowEmpty -and [string]::IsNullOrEmpty("$v")) {
                  $errs += "Value cannot be null or empty"
                }
                if ($_ -is [System.Management.Automation.ValidateNotNullAttribute] -and !$allowNull -and $v -eq $null) {
                  $errs += "Value cannot be null"
                }
                if ($_ -is [System.Management.Automation.ValidateCountAttribute]) {
                  $cnt = @($valToBind).Count
                  if ($cnt -lt $_.MinLength -or $cnt -gt $_.MaxLength) {
                    $errs += "Count ($cnt) not in range [$($_.MinLength),$($_.MaxLength)]"
                  }
                }
              } catch {
                $errs += "Validation error: $_"
              }
            }

            if ($errs) {
              $errs | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
              $ok = $false
            } else {
              $b[$n] = $valToBind
            }
          }
        }
      } while (!$ok)
    }
  } catch {
    return Stop-Cli "Error during interactive input: $_"
  }

  # Payload execution
  try {
    if ($b.Count) { & $MainPayload @b } else { & $MainPayload }
  } catch {
    return Stop-Cli "Error: $_"
  }
}

Invoke-Cli @args
