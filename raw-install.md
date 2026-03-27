# Raw Install (Non-Profile Mode)

Install and run OpenClaw gateway directly on the host without using clawctl profiles.

## Prerequisites

- Node.js (v18+)
- npm

## Install OpenClaw

```bash
# Install openclaw CLI globally
npm install -g openclaw

# Verify installation
openclaw --version
```

Or use the official install script:

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

> The install script will also run the onboard setup. To skip onboard, add `--no-onboard`:
>
> ```bash
> curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
> ```

## Configure

```bash
# Run onboard setup (interactive)
openclaw onboard

# Or configure manually
openclaw config set gateway.port 18789
```

## Set gateway token

```bash
export OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 16)
```

To persist the token, add it to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
echo "export OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 16)" >> ~/.bashrc
```

## Start the gateway

```bash
# Run in foreground
openclaw gateway

# Or run in background
nohup openclaw gateway >> ~/openclaw-gateway.log 2>&1 &
```

## Install WeChat Extension

### Prerequisites

- **WeChat version**: iOS 8.0.70+; Android please update to the latest version.
- OpenClaw gateway is deployed and running.

### Step 1: Get the install command

Open WeChat, go to **Me** > **Settings** > **Plugins**. If the feature is available to you, you'll see the **WeChat ClawBot** plugin. Enter the plugin page to find the dedicated terminal install command.

### Step 2: Connect to OpenClaw

Run the following command in the terminal where your OpenClaw instance is running:

```bash
npx -y @tencent-weixin/openclaw-weixin-cli@latest install
```

A QR code will be displayed in the terminal after the command runs.

### Step 3: Scan QR code to bind

Open WeChat's **Scan** feature and scan the QR code from the terminal. Tap **Confirm** on your phone. You'll receive a message from **WeChat ClawBot** in WeChat, indicating the connection is successful.

## Upgrade

```bash
# Upgrade openclaw
npm install -g openclaw@latest

# Upgrade WeChat plugin
npx -y @tencent-weixin/openclaw-weixin-cli@latest install
```

Restart the gateway after upgrading.

## Uninstall

```bash
# Uninstall openclaw CLI
npm uninstall -g openclaw

# Remove config and data
rm -rf ~/.openclaw
rm -rf ~/.config/openclaw
```

## Proxy

If your network requires a proxy to access external services (e.g., LLM APIs), set proxy environment variables before starting the gateway:

```bash
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
```
