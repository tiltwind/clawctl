# clawctl

OpenClaw Gateway instance manager. Create and manage multiple OpenClaw gateway instances on the host using profiles.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/tiltwind/clawctl/main/install.sh | bash
```

## Prerequisites

- OpenClaw CLI installed (`npm install -g openclaw`)
- Node.js runtime

## Usage

```
clawctl <command> <name>
```

### Commands

| Command | Description |
|---|---|
| `clawctl setup` | Setup OpenClaw |
| `clawctl create <name>` | Create a new profile interactively |
| `clawctl onboard <name>` | Run onboard setup for a profile |
| `clawctl install <name>` | Install systemd user service for a profile |
| `clawctl uninstall <name>` | Uninstall systemd user service |
| `clawctl start <name>` | Start the gateway |
| `clawctl stop <name>` | Stop the gateway |
| `clawctl restart <name>` | Restart the gateway |
| `clawctl status <name>` | Show instance status |
| `clawctl logs <name>` | Tail instance logs |
| `clawctl list` | List all profiles and their status |
| `clawctl remove <name>` | Remove a profile (stop + delete) |
| `clawctl clean` | Clean OpenClaw (stop all, remove CLI, config) |
| `clawctl help` | Show help |

### Create options

During `clawctl create`, you will be prompted for:

| Option | Choices | Default | Description |
|---|---|---|---|
| Port | any | `18789` | Gateway listen port |
| Sandbox | `off`, `non-main`, `all` | `all` | Sandbox mode ([docs](https://docs.openclaw.ai/gateway/sandboxing)) |
| Backend | `docker`, `openshell` | `docker` | Execution backend |

### Quick start

```bash
# 1. Setup OpenClaw
clawctl setup

# 2. Create a profile (interactive prompts for port, sandbox, backend)
clawctl create mybot

# 3. Run onboard setup
clawctl onboard mybot

# 4. Start the gateway
clawctl start mybot

# 5. Check status
clawctl status mybot
```

### Multiple instances

```bash
# Create multiple profiles with different ports
clawctl create bot1    # port 18789
clawctl create bot2    # port 18790

# Start all
clawctl start bot1
clawctl start bot2

# List all instances
clawctl list
```

### Profile directory structure

Each profile is stored under `~/.clawctl/profiles/<name>/`:

```
~/.clawctl/profiles/mybot/
├── config/
│   ├── openclaw.json       # OpenClaw configuration
│   └── workspace/          # Workspace data
├── logs/
│   └── gateway.log         # Gateway log output
├── .env                    # Environment variables (token, etc.)
├── profile.conf            # Profile metadata (name, port, created)
└── gateway.pid             # PID file (when running)
```

## Update

Re-run the install command to update:

```bash
curl -fsSL https://raw.githubusercontent.com/tiltwind/clawctl/main/install.sh | bash
```

## Uninstall clawctl

```bash
sudo rm /usr/local/bin/clawctl
rm -rf ~/.clawctl
```
