#!/bin/bash
set -euo pipefail

CLAWCTL_HOME="${CLAWCTL_HOME:-$HOME/.clawctl}"
PROFILES_DIR="${CLAWCTL_HOME}/profiles"

# ─── Helpers ──────────────────────────────────────────────────────────────────

color_green()  { printf '\033[0;32m%s\033[0m' "$*"; }
color_yellow() { printf '\033[0;33m%s\033[0m' "$*"; }
color_red()    { printf '\033[0;31m%s\033[0m' "$*"; }
color_cyan()   { printf '\033[0;36m%s\033[0m' "$*"; }

info()  { echo "$(color_green '[INFO]')  $*"; }
warn()  { echo "$(color_yellow '[WARN]')  $*"; }
error() { echo "$(color_red '[ERROR]') $*" >&2; }

# ─── Pre-checks ──────────────────────────────────────────────────────────────

if ! command -v npm &>/dev/null; then
    error "npm is not installed. Please install Node.js and npm first."
    exit 1
fi

# ─── Upgrade openclaw CLI ────────────────────────────────────────────────────

echo ""
echo "$(color_green '╔══════════════════════════════════════════╗')"
echo "$(color_green '║')   OpenClaw Upgrade                         $(color_green '║')"
echo "$(color_green '╚══════════════════════════════════════════╝')"
echo ""

info "[1/2] Upgrading openclaw to latest version..."

if command -v openclaw &>/dev/null; then
    local_version=$(openclaw --version 2>/dev/null || echo "unknown")
    info "  Current version: $local_version"
fi

npm install -g openclaw@latest

if command -v openclaw &>/dev/null; then
    new_version=$(openclaw --version 2>/dev/null || echo "unknown")
    info "  Upgraded to: $new_version"
fi

# ─── Upgrade @tencent-weixin/openclaw-weixin in all profiles ─────────────────

info "[2/2] Upgrading @tencent-weixin/openclaw-weixin in profiles..."

upgraded_profiles=0

if [[ -d "$PROFILES_DIR" ]]; then
    for conf in "$PROFILES_DIR"/*/profile.conf; do
        [[ -f "$conf" ]] || continue

        local profile_dir profile_name
        profile_dir=$(dirname "$conf")
        profile_name=$(grep '^NAME=' "$conf" 2>/dev/null | cut -d= -f2)

        # Check if the weixin plugin is installed in this profile
        if OPENCLAW_HOME="$profile_dir" openclaw plugins list 2>/dev/null | grep -q "openclaw-weixin"; then
            info "  Upgrading plugin in profile '${profile_name}'..."
            OPENCLAW_HOME="$profile_dir" openclaw plugins install "@tencent-weixin/openclaw-weixin@latest" || {
                warn "  Failed to upgrade plugin in profile '${profile_name}'"
                continue
            }
            ((upgraded_profiles++))
        fi
    done
fi

if [[ "$upgraded_profiles" -eq 0 ]]; then
    info "  No profiles with @tencent-weixin/openclaw-weixin found."
else
    info "  Upgraded plugin in $upgraded_profiles profile(s)."
fi

echo ""
info "Upgrade complete!"
echo ""
echo "  Note: If any gateway instances are running, restart them to use the new version:"
echo "    $(color_cyan 'clawctl restart <name>')"
echo ""
