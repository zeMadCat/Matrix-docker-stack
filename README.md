<div align="center">
  <img src="images/mds.png" alt="Matrix Docker Stack" style="width: min(450px, 100%)"/>
  <p><em>Vibecoded — built for personal use, shared because it works.</em></p>
  <p>A single interactive bash script that deploys a full Matrix homeserver stack on any Linux machine with Docker.</p>
</div>

---

> **Changelog**
>
> <details open>
> <summary><strong>v1.7</strong> — 2026-03-08</summary>
>
> - **Bridge error messages** — show log file paths and last 5 lines of output
> - **NPM port fallback** — auto-detects port conflicts, falls back to 8000/8443 if 80/443 in use
> - **Diagnostics menu** — option 7 collects system info, Docker config, logs, saves to timestamped file
> - **Bridge container deduplication** — bridges listed separately from main containers in cleanup
> - **Media Repo healthcheck** — fixed to use local IP instead of localhost; added Docker check fallback
> - **System-wide resource detection** — detects multiple Matrix installs; auto-discovers paths from running containers
> - **Selective cleanup menu** — whiptail checklist dialog to choose which installs to remove (SPACE to toggle)
> - **Container isolation** — proper mapping of containers to installations; volumes protected per install
> - **Sed fixes** — delimiter change to avoid regex errors with dynamic port variables
> - **NPM healthcheck fix** — uses local IP instead of localhost
>
> </details>
>
> <details>
> <summary><strong>v1.6</strong> — 2026-03-03</summary>
>
> - **Element X support** — `msc4186_enabled: true` added; Element X now works
> - **Caddy/Traefik guides** — step-by-step setup guides for existing installs
> - **Caddy fix** — premature reload removed; config applies correctly on start
> - **Arch Linux fixes** — IP detection and `daemon.json` write fixed
> - **LiveKit JWT port** — changed to `8089` to avoid Traefik conflict
>
> </details>
>
> <details>
> <summary><strong>v1.5</strong> — 2026-03-03</summary>
>
> - **Pangolin reverse proxy support** — new proxy option using Newt tunnel; zero open ports on home server, coturn runs on a separate VPS, guided setup included
> - **Storage check before path selection** — shows estimated disk usage (~5GB base, ~7GB with bridges) and free space per deployment path option; warns if space is low
> - **Network detection revamp** — re-detect loop with manual entry fallback; supports `back`/`b` to return to detection screen; validates both IPs are filled before continuing
> - **Cosmetic improvements** — redesigned banner with two-column layout (CORE / BRIDGES + FEATURES), version number shown inside the banner box
> - **Version detection logic updated** — version check now handles both `v` and `V` tag prefixes; fallback to `version.txt` no longer shown as an error when no GitHub Release exists; shows local vs remote version comparison
> - **NPM base domain config updated** — well-known now served inline via NPM (no nginx dependency), added `/_synapse/ess/` and `/_matrix/client/` blocks required for Element Admin; root redirects to Element Web
> - **MAS config fix** — `homeserver` now correctly uses `SERVER_NAME` instead of `DOMAIN`, fixing Element Admin auth when Matrix subdomain differs from base domain
>
> </details>
>
> <details>
> <summary><strong>v1.4</strong> — 2026-03-02</summary>
>
> Storage check before path selection — shows estimated disk usage and free space per deployment option. Script version check improvements.
>
> </details>
>
> <details>
> <summary><strong>v1.3</strong> — 2026-03-01</summary>
>
> Fixed MAS signing key (RSA + EC). Fixed all bridges: DB URI, SSL mode, container addressing, permissions. Add Bridges (option 5) is now universal — auto-detects credentials, container names, and network from any Docker Matrix deployment. Fixed user registration form missing from MAS. Fixed LiveKit JWT service env var names. Cleanup detects foreign compose project labels. Improved CLI output.
>
> </details>
>
> <details>
> <summary><strong>v1.2</strong> — 2026-03-01</summary>
>
> Admin panel choice (Element Admin / Synapse Admin). Replaced coturn with LiveKit TURN/STUN. Added LiveKit JWT Service. Optional services before domain prompts. Per-bridge activation guides. Log viewer with Ctrl-C return. Health checks conditional. Input validation on all prompts. Fixed bridges registration with Synapse. Fixed MAS signing key.
>
> </details>
>
> <details>
> <summary>v1.1 / v1.0</summary>
>
> v1.1: Element Admin, bridge selection improvements, fixed MAS OIDC, Caddy/Traefik auto-config.
> v1.0: First public release.
>
> </details>

---

## What it is

A fully interactive TUI deployment script for a self-hosted Matrix stack. Originally written for my own domain but designed to work with any domain through a dynamic setup wizard. You answer prompts, the script builds everything.

This is not a polished enterprise tool. It's a personal homelab project that grew into something reusable. Use it at your own risk, and feel free to adapt it.

---

## Stack

| Service | Purpose |
|---|---|
| Synapse | Matrix homeserver |
| Matrix Authentication Service (MAS) | OIDC authentication |
| Element Web | Web client |
| LiveKit | WebRTC SFU with built-in TURN/STUN |
| LiveKit JWT Service | Token generation for calls |
| Element Call *(optional)* | Standalone voice & video UI |
| Element Admin *(optional, user choice)* | Modern admin panel |
| Synapse Admin *(optional, user choice)* | Classic admin panel |
| PostgreSQL | Database |
| Sliding Sync Proxy *(optional)* | Legacy client support |
| Media Repo *(optional)* | Separate media handling |

Optional bridges selected during install:
**Discord · Telegram · WhatsApp · Signal · Slack · Instagram**

---

## Requirements

- A Linux server (tested on Ubuntu 22.04/24.04, Debian 12/13)
- Docker + Docker Compose
- A domain with DNS access
- A reverse proxy (NPM, Caddy, Traefik, Cloudflare Tunnel, or Pangolin)
- **⚠️ IMPORTANT — VPN Warning**: If using a VPN, proxy, or tunnel during setup:
  - **Option 1**: Disable your VPN/proxy/tunnel while running the deployment script
  - **Option 2**: Ensure you enter your REAL PUBLIC IP (not the VPN/tunnel IP) when prompted
  - Using a VPN IP will break federation and external access to your Matrix server

---

## Download & Run

```bash
# Download
curl -O https://raw.githubusercontent.com/zeMadCat/Matrix-docker-stack/main/matrix-stack-deploy.sh

# Make executable
chmod +x matrix-stack-deploy.sh

# Run
sudo ./matrix-stack-deploy.sh
```

Requires root or sudo. The script installs Docker if not present.

---

## What the setup looks like

**Startup — update check before menu**

The script checks GitHub for a newer version before showing the menu. If one is found, it asks whether to update and restart. Otherwise it proceeds directly to the menu.

**Pre-install menu**

```
┌──────────────────────────────────────────────────────────────┐
│              MATRIX SYNAPSE FULL STACK DEPLOYER              │
│                         by MadCat                            │
├──────────────────────────────────────────────────────────────┤
│  CORE                │  BRIDGES                              │
│  ───────────         │  ───────────                          │
│  • Synapse           │  - Discord     - Telegram             │
│  • MAS               │  - WhatsApp    - Signal               │
│  • LiveKit           │  - Slack       - Instagram            │
│  • LiveKit JWT       │                                       │
│  • PostgreSQL        │  FEATURES                             │
│  • Element Call *    │  ───────────                          │
│  • Admin Panel *     │  • Dynamic Config                     │
│  • Sliding Sync *    │  • User Input Based                   │
│  • Media Repo *      │  • Reverse Proxy Guides               │
│                      │  • Pangolin VPS Support               │
│  * = optional        │  • Easy Setup                         │
│                      │  • Multi-Screenshare                  │
│                      │                                       │
├──────────────────────────────────────────────────────────────┤
│                    Script Version: v1.7                      │
└──────────────────────────────────────────────────────────────┘

 What would you like to do?

   1)  Install Matrix Stack
   2)  Update Matrix Stack
   3)  Uninstall Matrix Stack
   4)  Verify Installation
   5)  Add Bridges
   6)  View Logs

 Choice [1-6]:
```

**Optional services & admin panel selection (before domain prompts)**

```
Optional Components
───────────────────
Enable Sliding Sync Proxy? [y]:
Enable Matrix Media Repo? [n]:
Enable standalone Element Call? [n]:

Admin Panel
───────────
Enable an admin panel? [n]: y

  Choose admin panel:
  1) Element Admin (recommended) — modern UI, actively maintained by Element
  2) Synapse Admin — classic UI, widely known

  Choice [1]:
```

All prompts validate input — entering anything other than the listed options loops back with an error.

**Domain & subdomain configuration (conditional — only enabled services are asked)**

```
Domain Configuration
────────────────────
Base domain (e.g. example.com): example.com

Subdomains (press Enter to accept defaults)
  Matrix Subdomain     [matrix]:
  MAS (Auth)           [auth]:
  LiveKit              [livekit]:
  Element Web          [element]:
  Element Admin        [admin]:    ← only shown if admin panel is enabled
```

**Reverse proxy selection**

```
Reverse Proxy Setup
───────────────────
Do you already have a reverse proxy running? (y/n): n

Select proxy type:
  1)  NPM (Nginx Proxy Manager)     — web UI, recommended
  2)  Caddy                         — auto TLS, config written automatically
  3)  Traefik                       — config written automatically
  4)  Cloudflare Tunnel             — no port forwarding needed
  5)  Pangolin                      — Newt tunnel, zero open ports
  6)  Manual Setup

Choice [1-6]:
```

**Health checks (conditional — only installed services)**

```
>> Performing health checks for installed services...

>> Checking PostgreSQL...
✓ PostgreSQL — ONLINE (synapse + matrix_auth databases ready)
>> Checking MAS (Auth Service)...
✓ MAS (Auth Service) — ONLINE
>> Checking Synapse...
✓ Synapse — ONLINE
>> Checking LiveKit SFU...
✓ LiveKit SFU — ONLINE (TURN/STUN ready on :3478)
>> Checking LiveKit JWT Service...
✓ LiveKit JWT Service — ONLINE
>> Checking Element Web...
✓ Element Web — ONLINE
>> Checking bridges...
   discord... running
   telegram... running

╔══════════════════════════════════════════════════════════════╗
║              ALL INSTALLED SERVICES ARE ONLINE               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## Bridges

### Why bridges need proper registration

Bridges are Matrix Application Services. For Synapse to know a bridge bot exists, the bridge's `registration.yaml` must be listed under `app_service_config_files` in `homeserver.yaml`. Without this, DMs to the bridge bot are silently ignored — typing `login` to the bot does nothing, no error is shown.

The script handles this automatically. For each selected bridge it:
1. Generates `config.yaml` and `registration.yaml` via the bridge container
2. Writes `app_service_config_files` entries into `homeserver.yaml`
3. Mounts `./bridges:/data/bridges` into the Synapse container

### Adding bridges post-install

Bridges can be added at any time via **option 5** in the main menu — no reinstall needed.

The script auto-detects your Matrix installation by scanning common paths and inspecting running containers. **This also works with other Docker-based Matrix deployments**, not just installs done with this script.

**Requirements for non-native deployments:**
- A `compose.yaml`, `docker-compose.yml`, or `docker-compose.yaml` in the stack root
- A `synapse/homeserver.yaml` file (used to read your domain and append appservice entries)
- Docker available and the `synapse` container running

> If your stack uses a Docker network name other than `matrix-net`, you may need to manually update the network entry in the bridge service block the script adds to your compose file.

### Activation (after stack is running)

Open Element Web and start a Direct Message with the bridge bot. The bot must appear in search — wait 1–2 minutes if it doesn't show immediately.

| Bridge | Bot user | Command | Auth method |
|---|---|---|---|
| Discord | `@discordbot:yourdomain` | `login` | Browser OAuth link |
| Telegram | `@telegrambot:yourdomain` | `login` | Phone number + SMS code |
| WhatsApp | `@whatsappbot:yourdomain` | `login` | Scan QR in WhatsApp → Linked Devices |
| Signal | `@signalbot:yourdomain` | `link` | Scan QR in Signal → Linked Devices |
| Slack | `@slackbot:yourdomain` | `login` | Browser OAuth link |
| Instagram | `@instagrambot:yourdomain` | `login` | Username + password |

---

## User registration

Registration through Element Web's built-in form is disabled — this is intentional. MAS handles all authentication via OIDC.

To register a new user:

```bash
docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes
docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --admin --yes
```

Or visit `https://auth.yourdomain.com/register` directly.

---

## Uninstall

Run the script again and select option 3. It detects all containers, volumes, networks and directories and removes them after confirmation.

> **Tip:** Keep the script outside the stack folder (`~/matrix-stack-deploy.sh`) — the uninstall option will warn you if it detects the script is inside the directory it is about to delete.

---

## Notes

- Secrets and passwords are randomly generated on each fresh install
- The script checks GitHub for updates on launch — runs before the menu, offers to update and restart
- Caddy and Traefik configs are written automatically — no manual proxy setup needed
- NPM requires manual proxy host creation but the script walks you through each one
- `turn.yourdomain.com` must always be **DNS Only** — TURN is handled by LiveKit's built-in server (or coturn on a VPS when using Pangolin)
- Admin panel is optional — choose Element Admin (modern) or Synapse Admin (classic), or skip entirely
- The credentials file includes all URLs, config paths, secrets, and bridge activation steps
- Use Element or Element X on iOS/Android

---

## License

Do whatever you want with it. No warranty. Don't blame me if it breaks something.
