# Install the external-agent skill into %USERPROFILE%\.claude\skills\ (Windows).
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 [-Force]
param([switch]$Force)
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty when this code is pasted or run through Invoke-Expression;
# then the current folder has to be the repository.
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.ProviderPath }
$Src  = Join-Path $Here 'external-agent'
$Dir  = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $env:USERPROFILE '.claude\skills' }
$Dest = Join-Path $Dir 'external-agent'

# -LiteralPath throughout: plain -Path treats [ ] in folder names as wildcards.
if (-not (Test-Path -LiteralPath (Join-Path $Src 'SKILL.md'))) {
  throw "external-agent\SKILL.md not found under $Here. Run the installer from the repository folder, or by its full path: powershell -ExecutionPolicy Bypass -File <repo>\install.ps1"
}
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
if (Test-Path -LiteralPath $Dest) {
  if (-not $Force) { throw "$Dest already exists (re-run with -Force to replace it)" }
  Remove-Item -LiteralPath $Dest -Recurse -Force
}
# evals\ (test cases run from the repository) is left out: Claude doesn't use it, and
# its deep paths can pass Windows PowerShell 5.1's 260-character limit.
try {
  New-Item -ItemType Directory -Path $Dest | Out-Null
  Get-ChildItem -LiteralPath $Src | Where-Object Name -ne 'evals' | Copy-Item -Destination $Dest -Recurse
} catch {
  Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction SilentlyContinue
  throw "copying to $Dest failed, nothing was installed: $($_.Exception.Message) A path over 260 characters is the usual cause: use a shorter folder, or run the installer with pwsh."
}
Write-Host "copied to $Dest"

# The skill's script runs under bash; Claude Code on Windows uses Git Bash for its Bash tool.
# Git for Windows' default install puts only Git\cmd on PATH, so look next to git.exe too;
# System32\bash.exe is WSL, not Git Bash.
$bash = $null
if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path -LiteralPath $env:CLAUDE_CODE_GIT_BASH_PATH)) { $bash = $env:CLAUDE_CODE_GIT_BASH_PATH }
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $bash -and $git) {
  $cand = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
  if (Test-Path -LiteralPath $cand) { $bash = $cand }
}
if (-not $bash) {
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notlike "$env:SystemRoot\*") { $bash = $cmd.Source }
}
if ($bash) { Write-Host "found bash ($bash)" }
else { Write-Warning 'Git Bash not found. Install Git for Windows: https://git-scm.com/download/win' }
$py = $null
foreach ($c in 'python', 'python3') {
  $cmd = Get-Command $c -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notlike '*WindowsApps*') { $py = $cmd; break }
}
if (-not $py) { Write-Warning 'Python 3 not found (the Microsoft Store alias does not count). Install from https://www.python.org/' }
foreach ($c in 'codex', 'agy') {
  if (Get-Command $c -ErrorAction SilentlyContinue) { Write-Host "found $c" }
  else { Write-Host "note: $c not on PATH (install it to use that subcontractor)" }
}
Write-Host 'Restart Claude Code to load the skill.'
