# pscli — PowerShell CLI wrapper

One script block, one wrapper, zero boilerplate. Define your logic in `$MainPayload` with standard PowerShell attributes — the wrapper handles arg parsing, validation re-prompting, and interactive walkthroughs automatically.

## Usage

Paste the machinery block at the bottom of any `.ps1` file. Write your script block at the top.

```powershell
# ── Your script block ───────────────────────────────────────
$MainPayload = {
  param(
    [Parameter(Mandatory)][ValidateLength(3,20)][string]$Name,
    [ValidateSet('admin','user','viewer')][string]$Role = 'user',
    [ValidatePattern('^\S+@\S+$')][string]$Email,
    [switch]$Notify
  )
  Write-Host "✓ Created user '$Name'"
  if ($Email) { Write-Host "  Email: $Email" }
}

# ── CLI machinery (paste at the bottom) ─────────────────────
# ... ~100 lines, leave as-is ...
Invoke-Cli @args
```

## How it works

Three modes, automatically selected:

| Mode | Trigger | Behaviour |
|------|---------|-----------|
| **Silent** | All args provided via flags | Runs immediately, no prompts |
| **Partial** | Some mandatory args missing | Prompts only for missing ones |
| **Full interactive** | No args at all | Walks through every parameter |

| Input type | Prompt style |
|------------|-------------|
| `[ValidateSet('a','b','c')]` | Numbered menu |
| `[switch]` | `y/n` prompt (rejects anything else) |
| Everything else | Text input with validation re-prompt |

## Supported attributes

| Attribute | Handled |
|-----------|---------|
| `[Parameter(Mandatory)]` | ✓ |
| `[Parameter(Position=N)]` | ✓ |
| `[Parameter(ParameterSetName='X')]` | ✓ |
| `[Alias('CN')]` | ✓ |
| `[ValidateSet('a','b')]` | ✓ (numbered menu) |
| `[ValidatePattern('regex')]` | ✓ |
| `[ValidateLength(3,20)]` | ✓ |
| `[ValidateRange(0,100)]` | ✓ |
| `[ValidateScript({...})]` | ✓ |
| `[ValidateNotNull()]` | ✓ |
| `[ValidateNotNullOrEmpty()]` | ✓ |
| `[ValidateCount(1,5)]` | ✓ |
| `[AllowNull()]` | ✓ |
| `[AllowEmptyString()]` | ✓ |
| `[AllowEmptyCollection()]` | ✓ |
| `[switch]` | ✓ |
| `[CmdletBinding()]` | ✓ |
| Default values (`$Role = 'user'`) | ✓ |
| `-Name=Value` / `-Name:Value` | ✓ |
| `-Switch:$false` | ✓ |

## Example

```
./pscli.ps1
```

```
== Interactive mode ==
Name: alice
Role:
  1. admin
  2. user
  3. viewer
Choose (1-3): 2
Email: alice@example.com
Notify (y/n): y
✓ Created user 'alice'
  Role: user
  Email: alice@example.com
  Notification sent
```

```
./pscli.ps1 -Name bob -Role admin -Notify
```
```
✓ Created user 'bob'
  Role: admin
  Notification sent
```

## Files

| File | Purpose |
|------|---------|
| `pscli.ps1` | Template script — replace `$MainPayload` with your logic |
| `tests.ps1` | 9 regression tests — run with `pwsh -File tests.ps1` |
