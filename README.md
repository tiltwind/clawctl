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
| `clawctl wechat <name>` | Configure WeChat channel (install plugin, QR login) |
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

## Common configurations

Use `clawctl config <name> set <key> <value>` to configure a profile. Below are frequently used settings.

### Proxy

If your network requires a proxy to access external services (e.g., LLM APIs), add proxy environment variables to the profile's `.env` file:

```bash
# ~/.clawctl/profiles/mybot/.env
OPENCLAW_GATEWAY_TOKEN=your-token
https_proxy=http://127.0.0.1:7890
http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890
```


### Agent mode

Isolate conversations per user/channel (useful for multi-user scenarios like WeChat):

```bash
clawctl config mybot set agents.mode per-channel-per-peer
```

### Network access (sandbox)

By default, sandbox containers have no network access. To allow agents to access the internet:

```bash
clawctl config mybot set agents.defaults.sandbox.docker.network "bridge"
```

To disable network access again:

```bash
clawctl config mybot set agents.defaults.sandbox.docker.network "none"
```

### Gateway port

The port is set during `clawctl create`, but you can change it manually:

```bash
clawctl config mybot set gateway.port 18800
```

> **Tip:** Run `clawctl config mybot get` to view the current configuration. For the full config reference, see the [openclaw docs](https://docs.openclaw.ai/cli/sandbox).

## Docker sandbox setup

See [sandbox.md](sandbox.md) for Docker sandbox configuration, including image setup, sandbox mode, network access, auto-prune, and sandbox management.

## WeChat channel setup

Connect your OpenClaw gateway to WeChat so you can chat with AI directly in WeChat.

```bash
clawctl wechat mybot
```

This will:
1. Install the `@tencent-weixin/openclaw-weixin` plugin into the profile
2. Enable the plugin in your profile config
3. Restart the gateway to load the plugin

```bash
# Isolate conversations per WeChat user
clawctl config mybot set agents.mode per-channel-per-peer
```

> **Note:** Group chat is not supported — only private/DM conversations work. Streaming output is not available; responses arrive as complete messages.

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
