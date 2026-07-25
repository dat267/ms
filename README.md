# cli.ps1 — PowerShell CLI wrapper

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
    [securestring]$Password,
    [switch]$Notify
  )
  Write-Host "✓ Created user '$Name'"
  if ($Email) { Write-Host "  Email: $Email" }
}

# ── CLI machinery (paste at the bottom) ─────────────────────
# ... leave as-is ...
Invoke-Cli @args
```

## How it works

Three modes, automatically selected:

| Mode | Trigger | Behaviour |
|------|---------|-----------|
| **Silent** | All args provided via flags | Runs immediately, no prompts |
| **Partial** | Some mandatory args missing | Fails with error listing missing parameters |
| **Full interactive** | No args at all | Walks through parameters with validation |

| Input type | Prompt style |
|------------|-------------|
| `[ValidateSet('a','b','c')]` | Numbered menu (accepts number or choice name) |
| `[switch]` | `y/n` prompt (respects default on empty input) |
| `[securestring]` | Password masked entry (`Read-Host -AsSecureString`) |
| Everything else | Text input with validation re-prompt and default/optional hints |

## Supported attributes & features

| Attribute / Feature | Handled |
|---------------------|---------|
| `[Parameter(Mandatory)]` | ✓ |
| `[Parameter(Position=N)]` | ✓ |
| `[Parameter(ParameterSetName='X')]` | ✓ |
| `[Alias('CN')]` | ✓ |
| Kebab-case Aliases (`--role-name` for `$RoleName`) | ✓ |
| `[securestring]` | ✓ (masked interactive input & string conversion) |
| `[PSCredential]` | ✓ |
| `[ValidateSet('a','b')]` | ✓ (numbered menu or direct string match) |
| `[ValidatePattern('regex')]` | ✓ |
| `[ValidateLength(3,20)]` | ✓ |
| `[ValidateRange(0,100)]` | ✓ (numeric validation) |
| `[ValidateScript({...})]` | ✓ |
| `[ValidateNotNull()]` | ✓ |
| `[ValidateNotNullOrEmpty()]` | ✓ |
| `[ValidateCount(1,5)]` | ✓ |
| `[AllowNull()]` | ✓ |
| `[AllowEmptyString()]` | ✓ |
| `[AllowEmptyCollection()]` | ✓ |
| `[switch]` | ✓ |
| `[CmdletBinding()]` | ✓ |
| Default values (`$Role = 'user'`, `$Active = $true`) | ✓ |
| Negative Numbers (`-Offset -10`) | ✓ |
| `-Name=Value` / `-Name:Value` | ✓ |
| `-Switch:$false` | ✓ |

## Example

```
./cli.ps1
```

```
== Interactive mode ==
Name: alice
Role:
  1. admin
  2. user
  3. viewer
Choose (1-3) [user]: 1
Email (optional): alice@example.com
Password (optional): ********
Notify (y/n): y
  Created user 'alice'
  Role: admin
  Email: alice@example.com
  Password set (length: 8)
  Notification sent
```

```
./cli.ps1 -Name bob -Role admin -Notify
```
```
  Created user 'bob'
  Role: admin
  Notification sent
```

## Files

| File | Purpose |
|------|---------|
| `cli.ps1` | Template script — replace `$MainPayload` with your logic |
| `tests.ps1` | Regression test suite — run with `pwsh -File tests.ps1` |
