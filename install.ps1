# Install the external-agent skill into %USERPROFILE%\.claude\skills\ (Windows).
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 [-Force]
param([switch]$Force)
$ErrorActionPreference = 'Stop'

$Src  = Join-Path $PSScriptRoot 'external-agent'
$Dir  = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $env:USERPROFILE '.claude\skills' }
$Dest = Join-Path $Dir 'external-agent'

if (-not (Test-Path (Join-Path $Src 'SKILL.md'))) { throw "SKILL.md not found under $Src" }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
if (Test-Path $Dest) {
  if (-not $Force) { throw "$Dest already exists (re-run with -Force to replace it)" }
  Remove-Item -Recurse -Force $Dest
}
Copy-Item -Recurse $Src $Dest
Write-Host "copied to $Dest"

# The skill's script runs under bash; Claude Code on Windows uses Git Bash for its Bash tool.
# Git for Windows' default install puts only Git\cmd on PATH, so look next to git.exe too;
# System32\bash.exe is WSL, not Git Bash.
$bash = $null
if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path $env:CLAUDE_CODE_GIT_BASH_PATH)) { $bash = $env:CLAUDE_CODE_GIT_BASH_PATH }
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $bash -and $git) {
  $cand = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
  if (Test-Path $cand) { $bash = $cand }
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
