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
| `clawctl logs <name>` | View instance logs (`--follow`, `--limit <n>`) |
| `clawctl config <name> [args...]` | Configure a profile (passthrough to openclaw) |
| `clawctl sandbox <name> [args...]` | Manage sandbox (explain, list, recreate, etc.) |
| `clawctl buildimage` | Build Docker image from openclaw source |
| `clawctl list` | List all profiles and their status |
| `clawctl remove <name>` | Remove a profile (stop + delete) |
| `clawctl clean` | Clean OpenClaw (stop all, remove CLI, config) |
| `clawctl help` | Show help |

### Quick start

```bash
# 1. Setup OpenClaw
clawctl setup

# 2. Create a profile
clawctl create mybot

# 3. Configure sandbox, backend, etc.
clawctl config mybot ...

# 4. Run onboard setup
clawctl onboard mybot

# 5. Start the gateway
clawctl start mybot

# 6. Check status
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

## Docker sandbox setup

To run agents in a Docker sandbox, you need a sandbox image and configure the profile accordingly.

### Build or pull the sandbox image

**Option 1: Build from source**

```bash
clawctl buildimage
```

This will clone/update the [openclaw](https://github.com/openclaw/openclaw) repo, checkout the latest stable tag, and let you choose a Dockerfile to build.

**Option 2: Pull a pre-built image**

```bash
docker pull openclaw-sandbox:latest
docker tag openclaw-sandbox:latest openclaw-sandbox:bookworm-slim
```

### Configure Docker sandbox

Use `clawctl config` to set sandbox mode and Docker parameters. See [sandbox docs](https://docs.openclaw.ai/cli/sandbox) for full reference.

```bash
# Set sandbox mode: off | non-main | all
clawctl config mybot set sandbox "all"

# Set Docker sandbox image
clawctl config mybot set agents.defaults.sandbox.docker.image "openclaw-sandbox:bookworm-slim"

# Set container name prefix
clawctl config mybot set agents.defaults.sandbox.docker.containerPrefix "openclaw-sbx-"

# Set auto-prune: remove idle containers after N hours
clawctl config mybot set agents.defaults.sandbox.prune.idleHours 24

# Set auto-prune: remove containers older than N days
clawctl config mybot set agents.defaults.sandbox.prune.maxAgeDays 7
```

### Manage sandboxes

```bash
# Show effective sandbox configuration
clawctl sandbox mybot explain

# List all sandbox runtimes
clawctl sandbox mybot list

# Recreate sandboxes after config changes
clawctl sandbox mybot recreate --all
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
