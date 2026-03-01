<div align="center">
  <img src="images/mds.png" alt="Matrix Docker Stack" width="320"/>
  <h1>Matrix Docker Stack</h1>
  <p><em>Vibecoded — built for personal use, shared because it works.</em></p>
  <p>A single interactive bash script that deploys a full Matrix homeserver stack on any Linux machine with Docker.</p>
</div>

---

> **Changelog**
>
> | Version | Date | What changed |
> |---------|------|--------------|
> | **v1.2** | 2026-03-01 | Admin panel choice (Element Admin / Synapse Admin). Replaced coturn with LiveKit TURN/STUN. Added LiveKit JWT Service. Optional services selected before domain prompts. Detailed per-bridge activation guides. Log viewer loops — Ctrl-C returns to container list. Verify shows `not installed` for optional containers. Add Bridges (option 5) auto-detects install path, works with other Docker Matrix deployments. Bridge TUI uses terminal background color. Update check now runs before the menu and offers to update; version display in header shows script version only. Health checks are now conditional — only installed services are checked; added LiveKit JWT, admin panel, and bridge checks; warnings include the correct `docker logs` command. Input validation on all y/n and numbered prompts — invalid input loops until corrected. Fixed admin password logic (variable mismatch). **Bridges fixed**: `registration.yaml` files are now registered with Synapse via `app_service_config_files` in `homeserver.yaml`, and the bridges directory is mounted into the Synapse container — previously bridges installed silently but DMs to bridge bots did nothing. **MAS signing key fixed**: now uses `openssl genpkey` with a file-based approach to guarantee a valid PKCS#8 key; invalid signing keys caused "something went wrong" on login. |
> | v1.1 | prior | Element Admin added, bridge selection improvements, fixed MAS OIDC, Caddy/Traefik auto-config |
> | v1.0 | initial | First public release |

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

- A Linux server (tested on Ubuntu 22.04/24.04, Debian 12)
- Docker + Docker Compose
- A domain with DNS access
- A reverse proxy (NPM, Caddy, Traefik, or Cloudflare Tunnel)

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
│                          by MadCat                           │
│                                                              │
│   Synapse • MAS • LiveKit • LiveKit JWT • PostgreSQL • Sync  │
│        Element Call • Admin Panel • Bridges (optional)       │
│                                                              │
│       Bridges: Discord • Telegram • WhatsApp • Signal        │
│                    Slack • Instagram                         │
└──────────────────────────────────────────────────────────────┘
Script Version: v1.2

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
  5)  Manual Setup

Choice [1-5]:
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
>> Checking bridges (allow 30-60s to connect)...
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
docker exec matrix-auth mas-cli manage register-user
```

Or visit `https://auth.yourdomain.com/account/` directly.

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
- `turn.yourdomain.com` must always be **DNS Only** — TURN is handled by LiveKit's built-in server
- Admin panel is optional — choose Element Admin (modern) or Synapse Admin (classic), or skip entirely
- The credentials file includes all URLs, config paths, secrets, and bridge activation steps
- Use Element (not Element X) on iOS/Android

---

## License

Do whatever you want with it. No warranty. Don't blame me if it breaks something.
