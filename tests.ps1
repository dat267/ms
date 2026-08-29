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

$script = Join-Path $PSScriptRoot cli.ps1
$example = Join-Path $PSScriptRoot examples/user-manager.ps1

# Non-interactive tests
Assert-Output "all args" { pwsh -NoProfile -File $script -Name alice -Role admin -Email a@b.com -Notify } `
  @("Created user 'alice'", 'Role: admin', 'Email: a@b.com', 'Notification sent') @('Interactive mode')

Assert-Output "with defaults" { pwsh -NoProfile -File $script -Name bob } `
  @("Created user 'bob'", 'Role: user') @('Interactive mode')

Assert-Output "switch only" { pwsh -NoProfile -File $script -Name test -Notify } `
  @("Created user 'test'", 'Notification sent') @('Interactive mode')

Assert-Output "--help" { pwsh -NoProfile -File $script --help } `
  @('Name', 'Role', 'Email', 'Password', 'Notify', 'admin/user/viewer') @()

Assert-Output "partial args" { pwsh -NoProfile -File $script -Name bob -Role admin } `
  @("Created user 'bob'", 'Role: admin') @('Interactive mode')

Assert-Output "securestring flag" { pwsh -NoProfile -File $script -Name alice -Password mysecret123 } `
  @("Created user 'alice'", 'Password set (length: 11)') @('Interactive mode')

# Interactive tests need separate PowerShell processes with piped stdin.
# We use Start-Process with RedirectStandardInput so the child gets a real
# stream (reliable for many sequential Read-Host calls), and read its output.
function Assert-Interactive {
  param([string]$Desc, [string]$InputData, [string[]]$ShouldContain, [string[]]$ShouldNotContain, [string]$ScriptPath = $script)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = (Get-Command pwsh).Source
  $psi.Arguments = "-NoProfile -File `"$ScriptPath`""
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()
  $p.StandardInput.Write($InputData)
  $p.StandardInput.Close()
  $null = $p.WaitForExit()
  $text = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()

  foreach ($s in $ShouldContain) { if ($text -notmatch [regex]::Escape($s)) { Write-Host "FAIL $Desc`n  missing: '$s'`n  output: $text" -ForegroundColor Red; $script:failed++; return } }
  foreach ($s in $ShouldNotContain) { if ($text -match [regex]::Escape($s)) { Write-Host "FAIL $Desc`n  should not contain: '$s'`n  output: $text" -ForegroundColor Red; $script:failed++; return } }
  Write-Host "PASS $Desc" -ForegroundColor Green; $script:passed++
}

# Build input with actual newlines
$nl = "`n"

Assert-Interactive "full walkthrough" "alice${nl}2${nl}alice@x.com${nl}mysecret${nl}y${nl}" `
  @("Created user 'alice'", 'Role: user', 'Email: alice@x.com', 'Password set (length: 8)', 'Notification sent') @()

Assert-Interactive "skip optional param" "bob${nl}1${nl}${nl}${nl}${nl}" `
  @("Created user 'bob'", 'Role: admin') @('Email: alice@x.com')

Assert-Interactive "re-prompt on invalid" "charlie${nl}3${nl}bad${nl}charlie@x.com${nl}${nl}y${nl}" `
  @("Created user 'charlie'", 'Role: viewer', 'Email: charlie@x.com', 'Notification sent') @()

Assert-Interactive "default used on empty input" "dave${nl}${nl}${nl}${nl}${nl}" `
  @("Created user 'dave'", 'Role: user') @()

# ── Example CLI (examples/user-manager.ps1) ─────────────────
# Every supported attribute type is exercised here.
# Explicit alias + repeated flags for an array parameter
Assert-Output "example: explicit alias -t (single)" { pwsh -NoProfile -File $example -Name alice -t dev } `
  @("Created user 'alice'", 'Tags: dev') @('Interactive mode')

Assert-Output "example: repeated flags -t a -t b -t c" { pwsh -NoProfile -File $example -Name alice -t dev -t prod -t qa } `
  @("Created user 'alice'", 'Tags: dev, prod, qa') @('Interactive mode')

Assert-Output "example: comma array -t a,b" { pwsh -NoProfile -File $example -Name alice -t dev,prod } `
  @("Created user 'alice'", 'Tags: dev, prod') @('Interactive mode')

Assert-Output "example: positional HomeDir" { pwsh -NoProfile -File $example -Name bob /home/bob -Notify } `
  @("Created user 'bob'", 'HomeDir: /home/bob', 'Notification sent') @('Interactive mode')

Assert-Output "example: negative Offset" { pwsh -NoProfile -File $example -Name alice -Offset -5 } `
  @("Created user 'alice'", 'Offset: -5') @('Interactive mode')

Assert-Output "example: ValidateScript + ValidatePattern pass" { pwsh -NoProfile -File $example -Name alice -Token okok -Email a@b.com } `
  @("Created user 'alice'", 'Token: okok', 'Email: a@b.com') @('Interactive mode')

Assert-Output "example: securestring via flag" { pwsh -NoProfile -File $example -Name alice -Password secret } `
  @("Created user 'alice'", 'Password set (length: 6)') @('Interactive mode')

Assert-Output "example: switch -Notify" { pwsh -NoProfile -File $example -Name alice -Notify } `
  @("Created user 'alice'", 'Notification sent') @('Interactive mode')

# Validation failures (native PowerShell validation in silent mode).
# Stop-Cli now calls `exit` under pwsh -File, so we also assert the exit code.
Assert-Output "example: ValidateRange violation" { pwsh -NoProfile -File $example -Name alice -Offset 50 } `
  @('maximum allowed range') @("Created user") 1

Assert-Output "example: ValidateScript violation" { pwsh -NoProfile -File $example -Name alice -Token bad } `
  @('validation script for the argument') @("Created user") 1

Assert-Output "example: ValidatePattern violation" { pwsh -NoProfile -File $example -Name alice -Email nope } `
  @('does not match the') @("Created user") 1

Assert-Output "example: ValidateCount violation" { pwsh -NoProfile -File $example -Name alice -t a,b,c,d,e,f } `
  @('no more than 5') @("Created user") 1

Assert-Output "example: --help lists all params" { pwsh -NoProfile -File $example --help } `
  @('Name','Role','Email','Tags','HomeDir','Offset','Token','Password','Credential','Notify','alias: t') @()

# Interactive example tests (piped stdin via temp file)
Assert-Interactive "example: full walkthrough (incl PSCredential)" "alice${nl}1${nl}a@b.com${nl}dev,prod${nl}/home/alice${nl}-3${nl}tokok${nl}secret${nl}creduser${nl}credpass${nl}y${nl}" -ScriptPath $example `
  @("Created user 'alice'", 'Role: admin', 'Email: a@b.com', 'Tags: dev, prod', 'HomeDir: /home/alice', 'Offset: -3', 'Token: tokok', 'Password set (length: 6)', 'Credential: creduser', 'Notification sent') @()

Assert-Interactive "example: defaults and skips" "bob${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}" -ScriptPath $example `
  @("Created user 'bob'", 'Role: user', 'Offset: 0') @('Email:', 'Tags:', 'Notification sent', 'Credential:', 'HomeDir:')

Assert-Interactive "example: re-prompt on invalid ValidateSet" "charlie${nl}9${nl}1${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}${nl}" -ScriptPath $example `
  @("Created user 'charlie'", 'Role: admin', "Invalid option '9'") @()

# Drift guard: the example embeds a copy of the machinery by design (single-file
# framework). Verify its machinery section matches cli.ps1 exactly, so future
# cli.ps1 edits don't silently rot the example.
$marker = 'CLI machinery'
$cliText = Get-Content -Raw $script
$expText = Get-Content -Raw $example
$cliMach = $cliText.Substring($cliText.IndexOf($marker))
$expMach = $expText.Substring($expText.IndexOf($marker))
if ($cliMach -eq $expMach) {
  Write-Host "PASS machinery in sync (cli.ps1 <-> example)" -ForegroundColor Green; $script:passed++
} else {
  Write-Host "FAIL machinery drift: examples/user-manager.ps1 is out of sync with cli.ps1 -- regenerate it from cli.ps1" -ForegroundColor Red; $script:failed++
}

Write-Host "`n=== $passed passed, $failed failed ===" -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
if ($failed) { exit 1 }
