#!/bin/bash
set -euo pipefail

# clawctl - OpenClaw Gateway instance manager (host-native, profile-based)
# Usage:
#   clawctl setup            - Setup OpenClaw
#   clawctl create  <name>  - Create a new profile interactively
#   clawctl onboard <name>  - Run onboard setup for a profile
#   clawctl start   <name>  - Start the gateway
#   clawctl stop    <name>  - Stop the gateway
#   clawctl restart <name>  - Restart the gateway
#   clawctl status  <name>  - Show instance status
#   clawctl info    <name>  - Show profile directory info
#   clawctl logs    <name> [--follow] [--limit <n>]  - View instance logs
#   clawctl config  <name> [args...]  - Configure a profile (passthrough to openclaw)
#   clawctl sandbox <name> [args...]  - Manage sandbox (passthrough to openclaw)
#   clawctl install   <name> - Install systemd user service
#   clawctl uninstall <name> - Uninstall systemd user service
#   clawctl wechat  <name>  - Configure WeChat channel
#   clawctl list            - List all profiles
#   clawctl remove  <name>  - Remove a profile (stop + delete)
#   clawctl clean           - Clean OpenClaw (stop all, remove CLI, config)
#   clawctl upgrade         - Upgrade openclaw and plugins to latest
#   clawctl buildimage      - Build Docker image from openclaw source

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

get_service_name() {
    local profile="$1"
    echo "openclaw-gateway-${profile}"
}

has_systemd_service() {
    local service
    service=$(get_service_name "$1")
    [[ -f "$HOME/.config/systemd/user/${service}.service" ]]
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

load_profile_env() {
    local profile_dir="$1"
    if [[ -f "$profile_dir/.env" ]]; then
        set -a
        # shellcheck disable=SC1091
        source "$profile_dir/.env"
        set +a
    fi
}

# Run openclaw with OPENCLAW_HOME set to the profile directory.
# This ensures all openclaw data (config, plugins, workspace, etc.)
# lives under $PROFILES_DIR/<profile>/ instead of scattered across
# ~/.openclaw, ~/.openclaw-<profile>, etc.
run_openclaw() {
    local profile_dir="$1"
    shift
    OPENCLAW_HOME="$profile_dir" openclaw "$@"
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
    echo "$(color_green '║')   OpenClaw Gateway Profile Creator     $(color_green '║')"
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

    # 3. Gateway token
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
  }
}
EOF

    # --- profile.conf (metadata) ---
    cat > "$profile_dir/profile.conf" << EOF
NAME=${profile}
PORT=${port}
CREATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

    echo ""
    info "Profile '${profile}' created successfully!"
    echo ""
    echo "  Profile dir: $profile_dir"
    echo "  Port:        $port"
    echo ""
    echo "  Next steps:"
    echo "    1. Configure: $(color_cyan "clawctl config $profile ...")"
    echo "    2. Start:     $(color_cyan "clawctl start $profile")"
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

    # Use systemd service if available
    if has_systemd_service "$profile"; then
        local service
        service=$(get_service_name "$profile")
        info "Starting service: $service"
        systemctl --user start "$service"
        systemctl --user status "$service" --no-pager
        return
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
    load_profile_env "$profile_dir"

    local logfile="${profile_dir}/logs/gateway.log"

    info "Starting gateway for profile '$profile' on port ${port:-unknown}..."
    nohup env OPENCLAW_HOME="$profile_dir" openclaw gateway >> "$logfile" 2>&1 &
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

    # Use systemd service if available
    if has_systemd_service "$profile"; then
        local service
        service=$(get_service_name "$profile")
        info "Stopping service: $service"
        systemctl --user stop "$service"
        info "Gateway stopped."
        return
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

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    # Use systemd service if available
    if has_systemd_service "$profile"; then
        local service
        service=$(get_service_name "$profile")
        info "Restarting service: $service"
        systemctl --user restart "$service"
        systemctl --user status "$service" --no-pager
        return
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

    # Use systemd service if available
    if has_systemd_service "$profile"; then
        local service
        service=$(get_service_name "$profile")
        echo "  Mode: systemd ($service)"
        echo ""
        systemctl --user status "$service" --no-pager
    else
        echo "  Mode: manual (PID file)"
        if is_running "$profile_dir"; then
            local pid
            pid=$(get_pid "$profile_dir")
            echo "  Status: $(color_green 'running') (PID: $pid)"
        else
            echo "  Status: $(color_red 'stopped')"
            # Clean up stale pid file
            rm -f "$profile_dir/gateway.pid"
        fi
    fi
    echo ""
}

cmd_logs() {
    local profile=""
    local follow=false
    local limit=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --follow|-f)
                follow=true
                shift
                ;;
            --limit|-n)
                if [[ -z "${2:-}" ]]; then
                    error "--limit requires a number"
                    exit 1
                fi
                limit="$2"
                shift 2
                ;;
            -*)
                error "Unknown option: $1"
                error "Usage: clawctl logs <name> [--follow] [--limit <n>]"
                exit 1
                ;;
            *)
                if [[ -z "$profile" ]]; then
                    profile="$1"
                else
                    error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$profile" ]]; then
        error "Usage: clawctl logs <name> [--follow] [--limit <n>]"
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
        error "No log file found at: $logfile"
        exit 1
    fi

    if [[ "$follow" == true ]]; then
        tail -f ${limit:+-n "$limit"} "$logfile"
    elif [[ -n "$limit" ]]; then
        tail -n "$limit" "$logfile"
    else
        tail -n 200 "$logfile"
    fi
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

cmd_clean() {
    echo ""
    echo "$(color_red '╔══════════════════════════════════════════╗')"
    echo "$(color_red '║')   OpenClaw Clean                       $(color_red '║')"
    echo "$(color_red '╚══════════════════════════════════════════╝')"
    echo ""
    warn "This will perform the following actions:"
    echo "  1. Stop all running gateway instances"
    echo "  2. Uninstall OpenClaw CLI (npm uninstall -g openclaw)"
    echo "  3. Remove config files (~/.openclaw, ~/.openclaw-*, ~/.config/openclaw)"
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
    rm -rf ~/.openclaw-*
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

cmd_config() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl config <name> [args...]"
        exit 1
    fi
    shift

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    load_profile_env "$profile_dir"
    run_openclaw "$profile_dir" config "$@"
}

cmd_sandbox() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl sandbox <name> [args...]"
        exit 1
    fi
    shift

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    load_profile_env "$profile_dir"
    run_openclaw "$profile_dir" sandbox "$@"
}

cmd_wechat() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl wechat <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found. Run 'clawctl create $profile' first."
        exit 1
    fi

    echo ""
    echo "$(color_green '╔══════════════════════════════════════════╗')"
    echo "$(color_green '║')   WeChat Channel Setup                 $(color_green '║')"
    echo "$(color_green '╚══════════════════════════════════════════╝')"
    echo ""

    load_profile_env "$profile_dir"

    # Step 1: Install the WeChat plugin into the profile
    info "[1/3] Installing WeChat plugin..."
    run_openclaw "$profile_dir" plugins install "@tencent-weixin/openclaw-weixin@1.0.3"

    # Step 2: Enable the plugin
    info "[2/3] Enabling WeChat plugin..."
    run_openclaw "$profile_dir" config set plugins.entries.openclaw-weixin.enabled true

    # Step 3: Restart gateway if running to pick up the new plugin
    info "[3/3] Restarting gateway..."
    if is_running "$profile_dir" || has_systemd_service "$profile"; then
        cmd_restart "$profile"
    else
        warn "Gateway is not running. Start it with: clawctl start $profile"
    fi

    echo ""
    info "WeChat channel configured for profile '$profile'!"
    echo ""
    echo "  Tips:"
    echo "    - To isolate conversations per user:"
    echo "        $(color_cyan "clawctl config $profile set agents.mode per-channel-per-peer")"
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

    load_profile_env "$profile_dir"
    info "Running onboard for profile '$profile'..."
    run_openclaw "$profile_dir" onboard
}

cmd_install_service() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl install <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found. Run 'clawctl create $profile' first."
        exit 1
    fi

    load_profile_env "$profile_dir"
    info "Installing systemd service for profile '$profile'..."
    run_openclaw "$profile_dir" gateway install
}

cmd_uninstall_service() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl uninstall <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")
    load_profile_env "$profile_dir"
    info "Uninstalling systemd service for profile '$profile'..."
    run_openclaw "$profile_dir" gateway uninstall
}

cmd_setup() {
    info "Setting up OpenClaw..."
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
}

cmd_buildimage() {
    local src_dir="${CLAWCTL_HOME}/openclaw-src"
    local repo_url="https://github.com/openclaw/openclaw.git"

    # Clone or update the repo
    if [[ -d "$src_dir/.git" ]]; then
        info "Updating openclaw source..."
        git -C "$src_dir" fetch --tags --force
        git -C "$src_dir" fetch --prune
    else
        info "Cloning openclaw source..."
        mkdir -p "$(dirname "$src_dir")"
        git clone "$repo_url" "$src_dir"
    fi

    # Find latest non-beta release tag (semver: vX.Y.Z without beta/alpha/rc suffix)
    local latest_tag
    latest_tag=$(git -C "$src_dir" tag -l 'v*' \
        | grep -v -iE '(alpha|beta|rc)' \
        | sort -V \
        | tail -n 1)

    if [[ -z "$latest_tag" ]]; then
        error "No stable release tag found."
        exit 1
    fi

    info "Checking out latest stable tag: $latest_tag"
    git -C "$src_dir" checkout "$latest_tag" --quiet

    # List Dockerfiles in root directory
    local dockerfiles=()
    while IFS= read -r -d '' f; do
        dockerfiles+=("$(basename "$f")")
    done < <(find "$src_dir" -maxdepth 1 -name 'Dockerfile*' -print0 | sort -z)

    if [[ ${#dockerfiles[@]} -eq 0 ]]; then
        error "No Dockerfile found in $src_dir"
        exit 1
    fi

    echo ""
    echo "$(color_cyan 'Available Dockerfiles:')"
    for i in "${!dockerfiles[@]}"; do
        echo "  $((i+1))) ${dockerfiles[$i]}"
    done
    echo ""

    local choice
    read -rp "$(color_cyan 'Choose Dockerfile to build') [1]: " choice
    choice="${choice:-1}"

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#dockerfiles[@]} )); then
        error "Invalid choice: $choice"
        exit 1
    fi

    local selected="${dockerfiles[$((choice-1))]}"
    local image_name="openclaw:${latest_tag}"

    # If not the default Dockerfile, append a suffix to the image name
    if [[ "$selected" != "Dockerfile" ]]; then
        local suffix="${selected#Dockerfile.}"
        image_name="openclaw-${suffix}:${latest_tag}"
    fi

    echo ""
    info "Building image '${image_name}' from ${selected}..."
    docker build -t "$image_name" -f "$src_dir/$selected" "$src_dir"

    echo ""
    info "Image '${image_name}' built successfully!"
}

cmd_info() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        error "Usage: clawctl info <name>"
        exit 1
    fi

    local profile_dir
    profile_dir=$(get_profile_dir "$profile")

    if [[ ! -f "$profile_dir/profile.conf" ]]; then
        error "Profile '$profile' not found."
        exit 1
    fi

    local port created
    port=$(grep '^PORT=' "$profile_dir/profile.conf" 2>/dev/null | cut -d= -f2)
    created=$(grep '^CREATED=' "$profile_dir/profile.conf" 2>/dev/null | cut -d= -f2)

    echo ""
    echo "Profile: $(color_cyan "$profile")"
    echo ""
    echo "  $(color_cyan 'Profile dir:')    $profile_dir"
    echo "  $(color_cyan 'Config dir:')     $profile_dir/config"
    echo "  $(color_cyan 'Log dir:')        $profile_dir/logs"
    echo "  $(color_cyan 'Extensions dir:') $profile_dir/.openclaw/extensions"
    echo "  $(color_cyan 'Port:')           ${port:-?}"
    echo "  $(color_cyan 'Created:')        ${created:-?}"
    echo ""

    # List directory contents
    echo "$(color_cyan 'Directory structure:')"
    if command -v tree &>/dev/null; then
        tree -L 2 --dirsfirst "$profile_dir"
    else
        ls -laR "$profile_dir" 2>/dev/null | head -60
    fi
    echo ""
}

cmd_upgrade() {
    bash "$CLAWCTL_HOME/upgrade.sh"
}

cmd_help() {
    echo ""
    echo "$(color_green 'clawctl') - OpenClaw Gateway Instance Manager"
    echo ""
    echo "Usage:"
    echo "  $0 $(color_cyan 'setup')              Setup OpenClaw"
    echo "  $0 $(color_cyan 'create')    <name>  Create a new profile interactively"
    echo "  $0 $(color_cyan 'onboard')   <name>  Run onboard setup for a profile"
    echo "  $0 $(color_cyan 'install')   <name>  Install systemd user service"
    echo "  $0 $(color_cyan 'uninstall') <name>  Uninstall systemd user service"
    echo "  $0 $(color_cyan 'start')     <name>  Start the gateway"
    echo "  $0 $(color_cyan 'stop')      <name>  Stop the gateway"
    echo "  $0 $(color_cyan 'restart')   <name>  Restart the gateway"
    echo "  $0 $(color_cyan 'status')    <name>  Show instance status"
    echo "  $0 $(color_cyan 'info')      <name>  Show profile directory info"
    echo "  $0 $(color_cyan 'logs')      <name> [--follow] [--limit <n>]  View instance logs"
    echo "  $0 $(color_cyan 'config')    <name> [args...]  Configure a profile"
    echo "  $0 $(color_cyan 'sandbox')   <name> [args...]  Manage sandbox"
    echo "  $0 $(color_cyan 'wechat')    <name>  Configure WeChat channel"
    echo "  $0 $(color_cyan 'list')              List all profiles"
    echo "  $0 $(color_cyan 'remove')    <name>  Remove a profile"
    echo "  $0 $(color_cyan 'clean')             Clean OpenClaw (stop all, remove CLI, config)"
    echo "  $0 $(color_cyan 'upgrade')           Upgrade openclaw and plugins to latest"
    echo "  $0 $(color_cyan 'buildimage')        Build Docker image from openclaw source"
    echo ""
    echo "Profiles are stored in: $PROFILES_DIR"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

command="${1:-help}"
shift || true

case "$command" in
    setup)      cmd_setup "$@" ;;
    create)     cmd_create "$@" ;;
    onboard)    cmd_onboard "$@" ;;
    install)    cmd_install_service "$@" ;;
    uninstall)  cmd_uninstall_service "$@" ;;
    start)      cmd_start "$@" ;;
    stop)       cmd_stop "$@" ;;
    restart)    cmd_restart "$@" ;;
    status)     cmd_status "$@" ;;
    info)       cmd_info "$@" ;;
    logs)       cmd_logs "$@" ;;
    config)     cmd_config "$@" ;;
    sandbox)    cmd_sandbox "$@" ;;
    wechat)     cmd_wechat "$@" ;;
    list)       cmd_list "$@" ;;
    remove)     cmd_remove "$@" ;;
    clean)      cmd_clean "$@" ;;
    upgrade)    cmd_upgrade "$@" ;;
    buildimage) cmd_buildimage "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
        error "Unknown command: $command"
        cmd_help
        exit 1
        ;;
esac
