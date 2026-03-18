#!/bin/bash
set -euo pipefail

# clawctl - OpenClaw Gateway instance manager (host-native, profile-based)
# Usage:
#   clawctl install          - Install OpenClaw
#   clawctl create  <name>  - Create a new profile interactively
#   clawctl onboard <name>  - Run onboard setup for a profile
#   clawctl start   <name>  - Start the gateway
#   clawctl stop    <name>  - Stop the gateway
#   clawctl restart <name>  - Restart the gateway
#   clawctl status  <name>  - Show instance status
#   clawctl logs    <name>  - Tail instance logs
#   clawctl list            - List all profiles
#   clawctl remove  <name>  - Remove a profile (stop + delete)
#   clawctl uninstall       - Uninstall OpenClaw (systemd, CLI, config)

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

prompt_input() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        read -rp "$(color_cyan "$prompt") [$(color_yellow "$default")]: " value
        echo "${value:-$default}"
    else
        while true; do
            read -rp "$(color_cyan "$prompt"): " value
            if [[ -n "$value" ]]; then
                echo "$value"
                return
            fi
            warn "This field is required."
        done
    fi
}

prompt_choice() {
    local prompt="$1" default="$2"
    shift 2
    local options=("$@")
    echo "$(color_cyan "$prompt")" >&2
    for i in "${!options[@]}"; do
        local marker=" "
        if [[ "${options[$i]}" == "$default" ]]; then
            marker="*"
        fi
        echo "  $marker $((i+1))) ${options[$i]}" >&2
    done
    local choice
    read -rp "$(color_cyan 'Choose') [$(color_yellow "$default")]: " choice
    if [[ -z "$choice" ]]; then
        echo "$default"
        return
    fi
    # If numeric, map to option
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "${options[$((choice-1))]}"
    else
        echo "$choice"
    fi
}

get_profile_dir() {
    local profile="$1"
    echo "${PROFILES_DIR}/${profile}"
}

is_running() {
    local profile_dir="$1"
    local pidfile="${profile_dir}/gateway.pid"
    if [[ -f "$pidfile" ]]; then
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_pid() {
    local profile_dir="$1"
    local pidfile="${profile_dir}/gateway.pid"
    if [[ -f "$pidfile" ]]; then
        cat "$pidfile"
    fi
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_create() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl create <name>"
        exit 1
    fi

    echo ""
    echo "$(color_green '╔══════════════════════════════════════════╗')"
    echo "$(color_green '║')   OpenClaw Gateway Profile Creator       $(color_green '║')"
    echo "$(color_green '╚══════════════════════════════════════════╝')"
    echo ""

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ -d "$profile_dir" ]] && [[ -f "$profile_dir/profile.conf" ]]; then
        warn "Profile '$profile' already exists at: $profile_dir"
        local overwrite
        read -rp "$(color_yellow 'Overwrite? (y/N): ')" overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            info "Aborted."
            exit 0
        fi
    fi

    # 2. Port
    local port
    port=$(prompt_input "Gateway port" "18789")

    # Check port conflict against existing profiles
    if [[ -d "$PROFILES_DIR" ]]; then
        for conf in "$PROFILES_DIR"/*/profile.conf; do
            [[ -f "$conf" ]] || continue
            local existing_name existing_port
            existing_name=$(grep '^NAME=' "$conf" 2>/dev/null | cut -d= -f2)
            existing_port=$(grep '^PORT=' "$conf" 2>/dev/null | cut -d= -f2)
            if [[ "$existing_port" == "$port" && "$existing_name" != "$profile" ]]; then
                error "Port ${port} is already used by profile '${existing_name}'"
                exit 1
            fi
        done
    fi

    # Check port conflict against running processes
    if lsof -iTCP:"$port" -sTCP:LISTEN -t &>/dev/null; then
        error "Port ${port} is already in use by another process"
        exit 1
    fi

    # 3. Sandbox mode
    local sandbox
    sandbox=$(prompt_choice "Sandbox mode:" "all" "off" "non-main" "all")

    # 4. Backend
    local backend
    backend=$(prompt_choice "Backend:" "docker" "docker" "openshell")

    # 5. Gateway token
    local token
    token=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p | head -c 32)

    # ─── Generate files ───────────────────────────────────────────────────────

    info "Creating profile at: $profile_dir"
    mkdir -p "$profile_dir/config/workspace"
    mkdir -p "$profile_dir/logs"

    # --- .env ---
    cat > "$profile_dir/.env" << EOF
OPENCLAW_GATEWAY_TOKEN=${token}
EOF

    # --- openclaw.json ---
    cat > "$profile_dir/config/openclaw.json" << EOF
{
  "gateway": {
    "port": ${port}
  },
  "sandbox": "${sandbox}",
  "backend": "${backend}"
}
EOF

    # --- profile.conf (metadata) ---
    cat > "$profile_dir/profile.conf" << EOF
NAME=${profile}
PORT=${port}
SANDBOX=${sandbox}
BACKEND=${backend}
CREATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

    echo ""
    info "Profile '${profile}' created successfully!"
    echo ""
    echo "  Profile dir: $profile_dir"
    echo "  Port:        $port"
    echo "  Sandbox:     $sandbox"
    echo "  Backend:     $backend"
    echo ""
    echo "  Next steps:"
    echo "    1. Start:     $(color_cyan "clawctl start $profile")"
    echo "    2. Configure: $(color_cyan "openclaw --profile $profile onboard")"
    echo ""
}

cmd_start() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl start <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found. Run 'clawctl create $profile' first."
        exit 1
    fi

    if is_running "$profile_dir"; then
        local pid
        pid=$(get_pid "$profile_dir")
        warn "Profile '$profile' is already running (PID: $pid)"
        exit 0
    fi

    # Check port conflict before starting
    local port
    port=$(grep '^PORT=' "$profile_dir/profile.conf" 2>/dev/null | cut -d= -f2)
    if [[ -n "$port" ]] && lsof -iTCP:"$port" -sTCP:LISTEN -t &>/dev/null; then
        error "Port ${port} is already in use. Cannot start."
        exit 1
    fi

    # Load environment variables
    if [[ -f "$profile_dir/.env" ]]; then
        set -a
        # shellcheck disable=SC1091
        source "$profile_dir/.env"
        set +a
    fi

    local logfile="${profile_dir}/logs/gateway.log"

    info "Starting gateway for profile '$profile' on port ${port:-unknown}..."
    nohup openclaw --profile "$profile" gateway >> "$logfile" 2>&1 &
    local pid=$!
    echo "$pid" > "$profile_dir/gateway.pid"

    # Brief wait to check if process started successfully
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        info "Gateway started (PID: $pid). Logs: $logfile"
    else
        error "Gateway failed to start. Check logs: $logfile"
        rm -f "$profile_dir/gateway.pid"
        exit 1
    fi
}

cmd_stop() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl stop <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    if ! is_running "$profile_dir"; then
        warn "Profile '$profile' is not running."
        # Clean up stale pid file
        rm -f "$profile_dir/gateway.pid"
        exit 0
    fi

    local pid
    pid=$(get_pid "$profile_dir")
    info "Stopping gateway for profile '$profile' (PID: $pid)..."
    kill "$pid" 2>/dev/null || true

    # Wait for process to exit
    local waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < 10 )); do
        sleep 1
        (( waited++ ))
    done

    if kill -0 "$pid" 2>/dev/null; then
        warn "Process did not exit gracefully, force killing..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$profile_dir/gateway.pid"
    info "Gateway stopped."
}

cmd_restart() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl restart <name>"
        exit 1
    fi

    cmd_stop "$profile"
    cmd_start "$profile"
}

cmd_status() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl status <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    local port
    port=$(grep '^PORT=' "$profile_dir/profile.conf" 2>/dev/null | cut -d= -f2)

    echo ""
    echo "Profile: $(color_cyan "$profile")"
    echo "  Path: $profile_dir"
    echo "  Port: ${port:-?}"

    if is_running "$profile_dir"; then
        local pid
        pid=$(get_pid "$profile_dir")
        echo "  Status: $(color_green 'running') (PID: $pid)"
    else
        echo "  Status: $(color_red 'stopped')"
        # Clean up stale pid file
        rm -f "$profile_dir/gateway.pid"
    fi
    echo ""
}

cmd_logs() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl logs <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    local logfile="${profile_dir}/logs/gateway.log"
    if [[ ! -f "$logfile" ]]; then
        warn "No log file found at: $logfile"
        exit 0
    fi

    tail -f "$logfile"
}

cmd_list() {
    if [[ ! -d "$PROFILES_DIR" ]]; then
        info "No profiles found."
        return
    fi

    local found=false
    echo ""
    printf "$(color_cyan '%-20s %-8s %-10s %-8s')\n" "PROFILE" "PORT" "STATUS" "PID"
    echo "────────────────────────────────────────────────────────"

    for conf in "$PROFILES_DIR"/*/profile.conf; do
        [[ -f "$conf" ]] || continue
        found=true

        local pdir
        pdir=$(dirname "$conf")
        local name port status pid_display

        name=$(grep '^NAME=' "$conf" 2>/dev/null | cut -d= -f2)
        port=$(grep '^PORT=' "$conf" 2>/dev/null | cut -d= -f2)

        if is_running "$pdir"; then
            status="$(color_green 'running')"
            pid_display=$(get_pid "$pdir")
        else
            status="$(color_red 'stopped')"
            pid_display="-"
            # Clean up stale pid file
            rm -f "$pdir/gateway.pid"
        fi

        printf "%-20s %-8s %-10b %-8s\n" "$name" "${port:-?}" "$status" "$pid_display"
    done

    if [[ "$found" == false ]]; then
        info "No profiles found."
    fi
    echo ""
}

cmd_remove() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl remove <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -d "$profile_dir" ]]; then
        error "Profile '$profile' not found at: $profile_dir"
        exit 1
    fi

    # Confirm with user
    warn "This will stop and remove profile '${profile}'"
    warn "  - Stop the gateway if running"
    warn "  - Delete profile directory: $profile_dir"
    local confirm
    read -rp "$(color_red 'Are you sure? (y/N): ')" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Aborted."
        exit 0
    fi

    # Stop if running
    if is_running "$profile_dir"; then
        cmd_stop "$profile"
    fi

    # Remove profile directory
    info "Removing profile directory: $profile_dir"
    rm -rf "$profile_dir"

    info "Profile '${profile}' removed."
}

cmd_uninstall() {
    echo ""
    echo "$(color_red '╔══════════════════════════════════════════╗')"
    echo "$(color_red '║')   OpenClaw Uninstaller                    $(color_red '║')"
    echo "$(color_red '╚══════════════════════════════════════════╝')"
    echo ""
    warn "This will perform the following actions:"
    echo "  1. Stop all running gateway instances"
    echo "  2. Uninstall OpenClaw CLI (npm uninstall -g openclaw)"
    echo "  3. Remove config files (~/.openclaw, ~/.config/openclaw)"
    echo ""

    local confirm
    read -rp "$(color_red 'Are you sure you want to uninstall OpenClaw? (y/N): ')" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Aborted."
        return 0
    fi

    # Second confirmation
    read -rp "$(color_red 'This action is irreversible. Type "UNINSTALL" to confirm: ')" confirm
    if [[ "$confirm" != "UNINSTALL" ]]; then
        info "Aborted."
        return 0
    fi

    echo ""

    # STEP 1. Stop all running instances
    info "[1/3] Stopping all running gateway instances..."
    if [[ -d "$PROFILES_DIR" ]]; then
        for conf in "$PROFILES_DIR"/*/profile.conf; do
            [[ -f "$conf" ]] || continue
            local pdir
            pdir=$(dirname "$conf")
            if is_running "$pdir"; then
                local pname
                pname=$(grep '^NAME=' "$conf" 2>/dev/null | cut -d= -f2)
                info "  Stopping profile '$pname'..."
                local pid
                pid=$(get_pid "$pdir")
                kill "$pid" 2>/dev/null || true
                rm -f "$pdir/gateway.pid"
            fi
        done
    fi
    echo "  All instances stopped"

    # STEP 2. Uninstall OpenClaw CLI
    info "[2/3] Uninstalling OpenClaw CLI..."
    if command -v openclaw &>/dev/null; then
        npm uninstall -g openclaw
        echo "  openclaw uninstalled"
    else
        echo "  openclaw not installed, skipped"
    fi

    # STEP 3. Clean up config files
    info "[3/3] Cleaning up config files..."
    rm -rf ~/.openclaw
    rm -rf ~/.config/openclaw
    echo "  Config files removed"

    echo ""
    info "Uninstall complete."
    echo ""
    echo "  To also remove clawctl and all profiles:"
    echo "    sudo rm /usr/local/bin/clawctl"
    echo "    rm -rf ~/.clawctl"
    echo ""
}

cmd_onboard() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl onboard <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found. Run 'clawctl create $profile' first."
        exit 1
    fi

    info "Running onboard for profile '$profile'..."
    openclaw --profile "$profile" onboard
}

cmd_install() {
    info "Installing OpenClaw..."
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
}

cmd_help() {
    echo ""
    echo "$(color_green 'clawctl') - OpenClaw Gateway Instance Manager"
    echo ""
    echo "Usage:"
    echo "  $0 $(color_cyan 'install')            Install OpenClaw"
    echo "  $0 $(color_cyan 'create')  <name>    Create a new profile interactively"
    echo "  $0 $(color_cyan 'onboard') <name>    Run onboard setup for a profile"
    echo "  $0 $(color_cyan 'start')   <name>    Start the gateway"
    echo "  $0 $(color_cyan 'stop')    <name>    Stop the gateway"
    echo "  $0 $(color_cyan 'restart') <name>    Restart the gateway"
    echo "  $0 $(color_cyan 'status')  <name>    Show instance status"
    echo "  $0 $(color_cyan 'logs')    <name>    Tail instance logs"
    echo "  $0 $(color_cyan 'list')              List all profiles"
    echo "  $0 $(color_cyan 'remove')  <name>    Remove a profile"
    echo "  $0 $(color_cyan 'uninstall')         Uninstall OpenClaw"
    echo ""
    echo "Profiles are stored in: $PROFILES_DIR"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

command="${1:-help}"
shift || true

case "$command" in
    install)    cmd_install "$@" ;;
    create)     cmd_create "$@" ;;
    onboard)    cmd_onboard "$@" ;;
    start)      cmd_start "$@" ;;
    stop)       cmd_stop "$@" ;;
    restart)    cmd_restart "$@" ;;
    status)     cmd_status "$@" ;;
    logs)       cmd_logs "$@" ;;
    list)       cmd_list "$@" ;;
    remove)     cmd_remove "$@" ;;
    uninstall)  cmd_uninstall "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
        error "Unknown command: $command"
        cmd_help
        exit 1
        ;;
esac
