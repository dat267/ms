# AGENTS.md — ms (PowerShell CLI Wrapper)

## What this is

A single-file PowerShell CLI framework. Write your logic in `$MainPayload` (a script block with `param(...)` and body), and the `Invoke-Cli` machinery at the bottom handles everything: argument parsing, validation, interactive walkthroughs, help display, SecureString/PSCredential handling.

## Files

| File | Purpose |
|------|---------|
| `cli.ps1` | Template + machinery. Replace `$MainPayload` with your logic, keep `Invoke-Cli` at the bottom. |
| `examples/user-manager.ps1` | Full worked example exercising every supported attribute type. Its machinery is a **copy** of `cli.ps1`'s — keep them in sync (see below). |
| `check-drift.sh` | Guard that diffs the machinery section of `cli.ps1` and `examples/user-manager.ps1`. Run after any `cli.ps1` machinery change. |
| `tests.ps1` | Regression suite. Run with `pwsh -File tests.ps1` (also asserts the machinery is in sync). |
| `README.md` | User-facing docs with examples and attribute support table. |
| `LICENSE` | MIT. |

## Keeping the example in sync

`examples/user-manager.ps1` embeds a full copy of the `cli.ps1` machinery by design (the framework is "paste machinery at the bottom of one file"). After editing `cli.ps1`'s machinery, regenerate the example so it doesn't silently rot:

```bash
# keep the example's payload, replace its machinery with cli.ps1's
awk '/# ── CLI machinery/{f=1} !f' examples/user-manager.ps1 > /tmp/exp.ps1
cat /tmp/exp.ps1 > examples/user-manager.ps1
awk '/# ── CLI machinery/{f=1} f' cli.ps1 >> examples/user-manager.ps1
# verify
bash check-drift.sh   # exits 0 when in sync
```

## Essential commands

```bash
# Run with all args (silent mode)
pwsh -File cli.ps1 -Name alice -Role admin -Email a@b.com -Notify

# Run with no args (interactive walkthrough)
pwsh -File cli.ps1

# Show help
pwsh -File cli.ps1 --help

# Run tests
pwsh -File tests.ps1
```

## Architecture

### How it works

The entire framework is a single function `Invoke-Cli` in `cli.ps1` (lines 34-442). It's invoked at the bottom: `Invoke-Cli @args`.

Three modes auto-selected based on `$A.Count` (args array length):

| Mode | Trigger | Behaviour |
|------|---------|-----------|
| **Silent** | All args provided via flags | Runs immediately, no prompts |
| **Partial** | Some mandatory args missing | Fails with error listing missing parameters |
| **Full interactive** | No args at all | Walks through parameters with validation |

### Control flow (inside Invoke-Cli)

1. **Parameter metadata extraction** (lines 54-77): Uses `Get-Command` on a temporary function created from `$MainPayload`. Handles a PS bug where `[Credential()]` before `$param` makes `Parameters` return null. AST is used for default values.

2. **Help display** (lines 82-119): `-h`/`--help` prints usage with parameter info, types, flags, and `.SYNOPSIS`/`.PARAMETER` help from `$MainPayload`.

3. **Argument parsing** (lines 122-198): Custom parser (not `Invoke-Command` splatting), supporting:
   - `-Name value` (space-separated)
   - `-Name=Value` and `-Name:Value` (inline)
   - `-Switch` (flag, no value)
   - `-Switch:$false` (explicit switch value)
   - Automatic kebab-case aliases: `$RoleName` → `--role-name`
   - Negative numbers: `-Offset -10` (the parser knows `-10` is not a flag)
   - Array params: `-Names a,b,c`
   - Hard-coded whitelist of common parameters to skip (`$commonParams`)

4. **Positional binding** (lines 204-224): Positional `[Parameter(Position=N)]` params consume remaining non-flag args.

5. **Parameter set detection** (lines 227-232): Crude heuristic — picks the parameter set that has the most bound params in common.

6. **SecureString/Credential conversion** (lines 236-256): String args for `[securestring]` params get converted via `ConvertTo-SecureString`. PSCredential params prompt for password if only username provided.

7. **Interactive prompt loop** (lines 275-434): For each missing parameter, prompts based on type:
   - `[ValidateSet('a','b','c')]` → numbered menu (accepts number or choice name)
   - `[switch]` → `y/n` prompt
   - `[securestring]` → `Read-Host -AsSecureString` (masked), falls back to plain `Read-Host` when stdin is redirected
   - `[PSCredential]` → username + password prompts
   - Everything else → text input with manual validation re-prompt

   Validates: `ValidatePattern`, `ValidateLength`, `ValidateSet`, `ValidateRange`, `ValidateScript`, `ValidateNotNull`, `ValidateNotNullOrEmpty`, `ValidateCount`. Uses `AllowNull`/`AllowEmptyString`/`AllowEmptyCollection` to skip validation.

8. **Payload execution** (lines 437-441): Splats the bound parameters hash into `$MainPayload`.

### `Stop-Cli` helper (lines 42-51)

Exits the process in console/remote host sessions, returns exit code in other contexts (ISE, Pester). This avoids killing the test runner.

## Key gotchas & non-obvious patterns

- **`[Credential()]` attribute bug**: If `[Credential()]` appears before `$param` in the script block, `Get-Command` returns null for `Parameters`. The code strips it with regex before creating the temporary function (line 58-60).

- **Array args**: accept either comma-separated values (`-Names a,b,c`) or repeated flags (`-Names a -Names b`); both append to the array. See `examples/user-manager.ps1`.

- **Kebab-case aliases are automatic**: `$RoleName` becomes `--role-name` without any explicit `[Alias()]`. Explicit `[Alias()]` also gets a kebab-case variant.

- **Negative numbers**: The parser distinguishes `-10` (value) from `--flag` (switch) by checking if the token after `-` starts with a letter. `-notmatch '^--?[a-zA-Z_]'` on line 179.

- **Interactive mode enters only when `$A.Count -eq 0`** (line 234). Even one arg skips interactive mode. Partial args fail with error.

- **Interactive stdin redirection**: When `[Console]::IsInputRedirected` is true, both `SecureString` and `PSCredential` prompts use plain `Read-Host` instead of `-AsSecureString`, because `Read-Host -AsSecureString` doesn't work with piped input. (This is what makes interactive mode testable via piped stdin.)

- **Default value extraction**: Uses `$MainPayload.Ast.ParamBlock` (AST) to get default values. Falls back to text extraction if `SafeGetValue()` fails (line 73).

- **`$commonParams` whitelist** (line 55): PowerShell common parameters are explicitly excluded from `--help` display and interactive prompts. If you add a param named the same as a common parameter, it will be silently skipped.

- **Exit behavior**: In console/remote host, `Stop-Cli` calls `exit` (kills the process). In Pester or ISE, it uses `return`. This matters when writing tests.

## Testing approach

- All tests in `tests.ps1` using a custom `Assert-Output` harness (no Pester dependency).
- Non-interactive tests: `pwsh -NoProfile -File cli.ps1 -Name ...` and check stdout + exit code.
- Interactive tests: pipe input string with newlines (`$nl`) into `pwsh -File cli.ps1` (stdin redirect).
- Test patterns to follow:
  - `Assert-Output "description" { pwsh -NoProfile -File $script -Flag1 val1 } @("expected output") @("unexpected output")`
  - `Assert-Interactive "description" "input${nl}data${nl}" @("expected") @("unexpected")`
- Exit code check is implicit: `$ec -ne $ExitCode` fails the test.
- No mocking framework — all tests run the real `cli.ps1` in a subprocess.

## Style conventions

- PowerShell scripts use `#!/usr/bin/env pwsh` shebang.
- Functions use `Verb-Noun` naming (`Invoke-Cli`, `Stop-Cli`).
- Parameters use `$PascalCase`.
- Output uses `Write-Host` with `-ForegroundColor` (Green for success, Cyan for info, Yellow for warnings, Red for errors).
- Comment sections have em-dash line separators: `# ── Section name ──`.
- The `$MainPayload` script block is always at the top of the file, and `Invoke-Cli @args` is always the last line.