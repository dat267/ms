#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$passed = 0; $failed = 0

function Assert-Output {
  param([string]$Desc, [scriptblock]$Cmd, [string[]]$ShouldContain, [string[]]$ShouldNotContain, [int]$ExitCode = 0)
  $out = & $Cmd 2>&1; $ec = $LASTEXITCODE
  $text = "$out"
  if ($ec -ne $ExitCode) { Write-Host "FAIL $Desc`n  exit code: $ec (expected $ExitCode)`n  output: $text" -ForegroundColor Red; $script:failed++; return }
  foreach ($s in $ShouldContain) { if ($text -notmatch [regex]::Escape($s)) { Write-Host "FAIL $Desc`n  missing: '$s'`n  output: $text" -ForegroundColor Red; $script:failed++; return } }
  foreach ($s in $ShouldNotContain) { if ($text -match [regex]::Escape($s)) { Write-Host "FAIL $Desc`n  should not contain: '$s'`n  output: $text" -ForegroundColor Red; $script:failed++; return } }
  Write-Host "PASS $Desc" -ForegroundColor Green; $script:passed++
}

$script = Join-Path $PSScriptRoot pscli.ps1

# Non-interactive tests
Assert-Output "all args" { pwsh -NoProfile -File $script -Name alice -Role admin -Email a@b.com -Notify } `
  @("Created user 'alice'", 'Role: admin', 'Email: a@b.com', 'Notification sent') @('Interactive mode')

Assert-Output "with defaults" { pwsh -NoProfile -File $script -Name bob } `
  @("Created user 'bob'", 'Role: user') @('Interactive mode')

Assert-Output "switch only" { pwsh -NoProfile -File $script -Name test -Notify } `
  @("Created user 'test'", 'Notification sent') @('Interactive mode')

Assert-Output "--help" { pwsh -NoProfile -File $script --help } `
  @('Name', 'Role', 'Email', 'Notify', 'admin/user/viewer') @()

Assert-Output "partial args" { pwsh -NoProfile -File $script -Name bob -Role admin } `
  @("Created user 'bob'", 'Role: admin') @('Interactive mode')

# Interactive tests need separate PowerShell processes with piped stdin
function Assert-Interactive {
  param([string]$Desc, [string]$InputData, [string[]]$ShouldContain, [string[]]$ShouldNotContain)
  $out = $InputData | pwsh -NoProfile -File $script 2>&1
  $text = "$out"
  foreach ($s in $ShouldContain) { if ($text -notmatch [regex]::Escape($s)) { Write-Host "FAIL $Desc`n  missing: '$s'`n  output: $text" -ForegroundColor Red; $script:failed++; return } }
  foreach ($s in $ShouldNotContain) { if ($text -match [regex]::Escape($s)) { Write-Host "FAIL $Desc`n  should not contain: '$s'`n  output: $text" -ForegroundColor Red; $script:failed++; return } }
  Write-Host "PASS $Desc" -ForegroundColor Green; $script:passed++
}

# Build input with actual newlines
$nl = "`n"

Assert-Interactive "full walkthrough" "alice${nl}2${nl}alice@x.com${nl}y${nl}" `
  @("Created user 'alice'", 'Role: user', 'Email: alice@x.com', 'Notification sent') @()

Assert-Interactive "skip optional param" "bob${nl}1${nl}${nl}${nl}" `
  @("Created user 'bob'", 'Role: admin') @('Email: alice@x.com')

Assert-Interactive "re-prompt on invalid" "charlie${nl}3${nl}bad${nl}charlie@x.com${nl}y${nl}" `
  @("Created user 'charlie'", 'Role: viewer', 'Email: charlie@x.com', 'Notification sent') @()

Assert-Interactive "default used on empty input" "dave${nl}${nl}${nl}${nl}" `
  @("Created user 'dave'", 'Role: user') @()

Write-Host "`n=== $passed passed, $failed failed ===" -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
if ($failed) { exit 1 }
