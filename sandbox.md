# Docker Sandbox Setup

To run agents in a Docker sandbox, you need a sandbox image and configure the profile accordingly.

## Build or pull the sandbox image

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

## Configure Docker sandbox

Use `clawctl config` to set sandbox mode and Docker parameters. See [sandbox docs](https://docs.openclaw.ai/cli/sandbox) for full reference.

```bash
# Set sandbox mode: off | non-main | all
clawctl config mybot set agents.defaults.sandbox.mode "all"

# Set Docker sandbox image
clawctl config mybot set agents.defaults.sandbox.docker.image "openclaw-sandbox:bookworm-slim"

# Set container name prefix
clawctl config mybot set agents.defaults.sandbox.docker.containerPrefix "openclaw-sbx-"

# Set auto-prune: remove idle containers after N hours
clawctl config mybot set agents.defaults.sandbox.prune.idleHours 24

# Set auto-prune: remove containers older than N days
clawctl config mybot set agents.defaults.sandbox.prune.maxAgeDays 7

# Enable network access for sandbox containers (default: "none")
clawctl config mybot set agents.defaults.sandbox.docker.network "bridge"
```

## Sandbox mode

Control which agents run inside a Docker sandbox:

```bash
# Sandbox all agents
clawctl config mybot set agents.defaults.sandbox.mode "all"

# Only sandbox non-main agents
clawctl config mybot set agents.defaults.sandbox.mode "non-main"

# Disable sandbox
clawctl config mybot set agents.defaults.sandbox.mode "off"
```

## Sandbox image

```bash
clawctl config mybot set agents.defaults.sandbox.docker.image "openclaw-sandbox:bookworm-slim"
clawctl config mybot set agents.defaults.sandbox.docker.containerPrefix "openclaw-sbx-"
```

## Network access

By default, sandbox containers have no network access. To allow agents to access the internet:

```bash
clawctl config mybot set agents.defaults.sandbox.docker.network "bridge"
```

To disable network access again:

```bash
clawctl config mybot set agents.defaults.sandbox.docker.network "none"
```

## Auto-prune idle containers

```bash
# Remove idle containers after 24 hours
clawctl config mybot set agents.defaults.sandbox.prune.idleHours 24

# Remove containers older than 7 days
clawctl config mybot set agents.defaults.sandbox.prune.maxAgeDays 7
```

## Manage sandboxes

```bash
# Show effective sandbox configuration
clawctl sandbox mybot explain

# List all sandbox runtimes
clawctl sandbox mybot list

# Recreate sandboxes after config changes
clawctl sandbox mybot recreate --all
```
