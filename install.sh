#!/usr/bin/env bash
# pi-config — bootstrap (macOS / Linux / WSL)
#
# Copies this repo's pi configuration into place:
#   extensions, settings, plan-mode, npm packages, skills, shared MCP config.
#
# Usage:
#   ./install.sh            # full install
#   ./install.sh --skip-npm # skip package install

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_NPM=0
SKIP_SKILLS=0
SKIP_MCP=0
for arg in "$@"; do
  case "$arg" in
    --skip-npm) SKIP_NPM=1 ;;
    --skip-skills) SKIP_SKILLS=1 ;;
    --skip-mcp) SKIP_MCP=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$1"; }

backup() {
  local f="$1"
  if [ -e "$f" ]; then
    cp "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
    info "backed up existing $(basename "$f")"
  fi
}

PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
AGENTS_SKILLS="$HOME/.agents/skills"
SHARED_MCP="$HOME/.config/mcp/mcp.json"

printf '\033[32mpi-config installer\033[0m\n'
info "target pi dir : $PI_DIR"
info "skills dir    : $AGENTS_SKILLS"

mkdir -p "$PI_DIR/extensions" "$PI_DIR/npm" "$AGENTS_SKILLS"

step 'settings + plan-mode'
backup "$PI_DIR/settings.json"
cp "$REPO/agent/settings.json" "$PI_DIR/settings.json"
cp "$REPO/agent/pi-plan-mode.json" "$PI_DIR/pi-plan-mode.json"
info 'settings.json, pi-plan-mode.json'

step 'custom extensions'
for f in "$REPO/agent/extensions/"*.ts; do
  cp "$f" "$PI_DIR/extensions/"
  info "$(basename "$f")"
done

step 'npm packages'
cp "$REPO/agent/npm/package.json" "$PI_DIR/npm/package.json"
cp "$REPO/agent/npm/package-lock.json" "$PI_DIR/npm/package-lock.json"
if [ "$SKIP_NPM" -eq 1 ]; then
  warn "skipped (run: cd \"$PI_DIR/npm\" && npm ci)"
elif command -v npm >/dev/null 2>&1; then
  info 'running npm ci (exact versions from lockfile)...'
  (cd "$PI_DIR/npm" && npm ci --no-audit --no-fund)
else
  warn 'npm not found; falling back to: pi update --extensions'
  pi update --extensions
fi

step 'node_modules link'
if [ -e "$PI_DIR/node_modules" ]; then
  info 'node_modules already present'
else
  ln -s "$PI_DIR/npm/node_modules" "$PI_DIR/node_modules"
  info "symlink created: $PI_DIR/node_modules -> $PI_DIR/npm/node_modules"
fi

step 'skills'
cp -R "$REPO/skills/amazon-flipkart-scraping" "$AGENTS_SKILLS/"
info 'amazon-flipkart-scraping (vendored)'
if [ "$SKIP_SKILLS" -eq 0 ]; then
  warn 'third-party skills are installed from source (interactive prompt may appear):'
  printf '%s\n' \
    'npx skills add vercel-labs/skills' \
    'npx skills add mattpocock/skills' \
    'npx skills add leonxlnx/taste-skill' \
    'npx skills add coreyhaines31/marketingskills' \
    'npx skills add jakubkrehel/skills' \
    'npx skills add emilkowalski/skills'
fi

if [ "$SKIP_MCP" -eq 0 ]; then
  step 'shared MCP config'
  mkdir -p "$(dirname "$SHARED_MCP")"
  backup "$SHARED_MCP"
  cp "$REPO/config/mcp.json" "$SHARED_MCP"
  info "$SHARED_MCP"
fi

printf '\n\033[32mDone.\033[0m\n'
printf '\033[33mRestart pi. Auth (auth.json) is NOT provided by this repo — run /login or set provider API keys.\033[0m\n'
printf '\033[33mIf the Prism model provider is expected, add it to models.json separately (excluded from this repo).\033[0m\n'
