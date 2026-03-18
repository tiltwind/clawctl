#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/tiltwind/clawctl.git"
INSTALL_DIR="${clawctl_HOME:-$HOME/.clawctl}"
LINK_PATH="/usr/local/bin/clawctl"

color_green()  { printf '\033[0;32m%s\033[0m' "$*"; }
color_red()    { printf '\033[0;31m%s\033[0m' "$*"; }
color_cyan()   { printf '\033[0;36m%s\033[0m' "$*"; }

info()  { echo "$(color_green '[INFO]')  $*"; }
error() { echo "$(color_red '[ERROR]') $*" >&2; }

# ─── Pre-checks ────────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
    error "Git is not installed. Please install Git first."
    exit 1
fi

# ─── Clone or update ───────────────────────────────────────────────────────

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing installation at: $INSTALL_DIR"
    cd "$INSTALL_DIR" && git pull --ff-only
else
    if [[ -d "$INSTALL_DIR" ]]; then
        error "$INSTALL_DIR already exists but is not a git repo. Remove it first."
        exit 1
    fi
    info "Cloning clawctl to: $INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/clawctl.sh"

# ─── Create symlink ────────────────────────────────────────────────────────

info "Creating symlink: $LINK_PATH -> $INSTALL_DIR/clawctl.sh"
if [[ -L "$LINK_PATH" || -f "$LINK_PATH" ]]; then
    info "Removing existing $LINK_PATH"
    sudo rm -f "$LINK_PATH"
fi
sudo ln -s "$INSTALL_DIR/clawctl.sh" "$LINK_PATH"

# ─── Done ──────────────────────────────────────────────────────────────────

echo ""
info "Installation complete!"
echo ""
echo "  Install path: $(color_cyan "$INSTALL_DIR")"
echo "  Command:      $(color_cyan "clawctl")"
echo ""
echo "  Get started:"
echo "    clawctl help"
echo "    clawctl setup"
echo "    clawctl create mybot"
echo ""
