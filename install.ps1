# pi-config — bootstrap (Windows PowerShell)
#
# Copies this repo's pi configuration into place:
#   extensions, settings, plan-mode, npm packages, skills, shared MCP config.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipNpm -SkipSkills

[CmdletBinding()]
param(
  [switch]$SkipNpm,
  [switch]$SkipSkills,
  [switch]$SkipMcp,
  [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot

function Info($m) { Write-Host "  $m" }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }

function Backup-IfExists($path) {
  if ((Test-Path $path) -and -not $NoBackup) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item $path "$path.bak-$stamp" -Force
    Info "backed up existing -> $(Split-Path $path -Leaf).bak-$stamp"
  }
}

# --- resolve target dirs ------------------------------------------------------
$PiDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HOME '.pi\agent' }
$AgentsSkills = Join-Path $HOME '.agents\skills'
$SharedMcp = Join-Path $HOME '.config\mcp\mcp.json'

Write-Host "pi-config installer" -ForegroundColor Green
Info "target pi dir : $PiDir"
Info "skills dir    : $AgentsSkills"

New-Item -ItemType Directory -Force -Path $PiDir, (Join-Path $PiDir 'npm'), $AgentsSkills | Out-Null

# --- 1. settings / plan-mode --------------------------------------------------
Step 'settings + plan-mode'
Backup-IfExists (Join-Path $PiDir 'settings.json')
Copy-Item (Join-Path $Repo 'agent\settings.json') (Join-Path $PiDir 'settings.json') -Force
Copy-Item (Join-Path $Repo 'agent\pi-plan-mode.json') (Join-Path $PiDir 'pi-plan-mode.json') -Force
Info 'settings.json, pi-plan-mode.json'

# --- 2. extensions ------------------------------------------------------------
Step 'custom extensions'
$extDir = Join-Path $PiDir 'extensions'
New-Item -ItemType Directory -Force -Path $extDir | Out-Null
Get-ChildItem (Join-Path $Repo 'agent\extensions\*.ts') | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $extDir $_.Name) -Force
  Info $_.Name
}

# --- 3. npm packages ----------------------------------------------------------
Step 'npm packages'
Copy-Item (Join-Path $Repo 'agent\npm\package.json') (Join-Path $PiDir 'npm\package.json') -Force
Copy-Item (Join-Path $Repo 'agent\npm\package-lock.json') (Join-Path $PiDir 'npm\package-lock.json') -Force
if ($SkipNpm) {
  Warn 'skipped (run: cd $env:PI_CODING_AGENT_DIR\npm; npm ci)'
} else {
  Push-Location (Join-Path $PiDir 'npm')
  try {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
      Info 'running npm ci (exact versions from lockfile)...'
      npm ci --no-audit --no-fund
      if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
    } else {
      Warn 'npm not found; falling back to: pi update --extensions'
      pi update --extensions
    }
  } finally { Pop-Location }
}

# pi resolves extension imports through <pidir>\node_modules -> <pidir>\npm\node_modules
Step 'node_modules link'
$link = Join-Path $PiDir 'node_modules'
$target = Join-Path $PiDir 'npm\node_modules'
if (Test-Path $link) {
  Info 'node_modules already present'
} else {
  cmd /c mklink /J "$link" "$target" | Out-Null
  Info "junction created: $link -> $target"
}

# --- 4. skills ----------------------------------------------------------------
Step 'skills'
Copy-Item (Join-Path $Repo 'skills\amazon-flipkart-scraping') $AgentsSkills -Recurse -Force
Info 'amazon-flipkart-scraping (vendored)'
if ($SkipSkills) {
  Warn 'third-party skills skipped'
} else {
  Write-Host '  Third-party skills are installed from source (interactive prompt may appear):' -ForegroundColor Yellow
  @(
    'npx skills add vercel-labs/skills',
    'npx skills add mattpocock/skills',
    'npx skills add leonxlnx/taste-skill',
    'npx skills add coreyhaines31/marketingskills',
    'npx skills add jakubkrehel/skills',
    'npx skills add emilkowalski/skills'
  ) | ForEach-Object { Write-Host "    $_" }
}

# --- 5. shared MCP config -----------------------------------------------------
if (-not $SkipMcp) {
  Step 'shared MCP config'
  New-Item -ItemType Directory -Force -Path (Split-Path $SharedMcp) | Out-Null
  Backup-IfExists $SharedMcp
  Copy-Item (Join-Path $Repo 'config\mcp.json') $SharedMcp -Force
  Info $SharedMcp
}

Write-Host "`nDone." -ForegroundColor Green
Write-Host 'Restart pi. Auth (auth.json) is NOT provided by this repo — run /login or set provider API keys.' -ForegroundColor Yellow
Write-Host 'If the Prism model provider is expected, add it to models.json separately (excluded from this repo).' -ForegroundColor Yellow
