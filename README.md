# 🐱 Matrix Docker Stack

> **Vibecoded** — built for personal use, shared because it works.  
> A single interactive bash script that deploys a full Matrix homeserver stack on any Linux machine with Docker.

---

## What it is

A fully interactive TUI deployment script for a self-hosted Matrix stack. Originally written for `example.com` but designed to work with any domain through a dynamic setup wizard. You answer prompts, the script builds everything.

**This is not a polished enterprise tool.** It's a personal homelab project that grew into something reusable. Use it at your own risk, and feel free to adapt it.

---

## Stack

| Service | Purpose |
|---|---|
| [Synapse](https://github.com/element-hq/synapse) | Matrix homeserver |
| [Matrix Authentication Service (MAS)](https://github.com/element-hq/matrix-authentication-service) | OIDC authentication |
| [Element Web](https://github.com/element-hq/element-web) | Web client |
| [Element Call](https://github.com/element-hq/element-call) | Voice & video calls |
| [LiveKit](https://github.com/livekit/livekit) | WebRTC SFU for calls |
| [coturn](https://github.com/coturn/coturn) | TURN/STUN server |
| [Synapse Admin](https://github.com/Awesome-Technologies/synapse-admin) | Admin UI |
| PostgreSQL | Database |
| Sliding Sync Proxy *(optional)* | Legacy client support |
| Media Repo *(optional)* | Separate media handling |

**Optional bridges** (selected during install):
Discord · Telegram · WhatsApp · Signal · Slack · Instagram

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
curl -O https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/matrix-stack-deploy.sh

# Make executable
chmod +x matrix-stack-deploy.sh

# Run
sudo ./matrix-stack-deploy.sh
```

> Requires root or sudo. The script installs Docker if not present.

---

## What the setup looks like

### Pre-install menu

```
┌──────────────────────────────────────────────────────────────┐
│              MATRIX HOMESERVER DEPLOYMENT SUITE              │
│                    by yourusername  •  v1.1                      │
└──────────────────────────────────────────────────────────────┘

 What would you like to do?

   1)  Install Matrix Stack
   2)  Update Matrix Stack
   3)  Uninstall Matrix Stack

 Choice [1-3]:
```

### Domain & subdomain configuration

```
Domain Configuration
────────────────────
Base domain (e.g. example.com): example.com

Subdomains (press Enter to accept defaults)
  Matrix Subdomain     [matrix]:
  Element Call         [call]:
  MAS (Auth)           [auth]:
  LiveKit              [livekit]:
  Element Web          [element]:
  Sliding Sync         [sync]:
```

### Reverse proxy selection

```
Reverse Proxy Setup
───────────────────
Do you already have a reverse proxy running? (y/n): n

Select proxy type:
  1)  NPM (Nginx Proxy Manager)     — web UI, recommended
  2)  Caddy                         — auto TLS, config written automatically
  3)  Traefik                       — config written automatically
  4)  Cloudflare Tunnel             — no port forwarding needed

Choice [1-4]:
```

### Optional components & bridges

```
Optional Components
───────────────────
[ ] Sliding Sync Proxy   (legacy client support)
[ ] Separate Media Repo  (offload media handling)

Bridge Selection
────────────────
Select bridges to install (space to toggle, enter to confirm)

  [ ] Discord
  [ ] Telegram
  [ ] WhatsApp
  [ ] Signal
  [ ] Slack
  [ ] Instagram
```

### DNS & port forwarding tables (generated after install)

```
═══════════════════════════ DNS RECORDS ════════════════════════════
   ┌─────────────────┬───────────┬─────────────────┬─────────────────┐
   │ HOSTNAME        │ TYPE      │ VALUE           │ STATUS          │
   ├─────────────────┼───────────┼─────────────────┼─────────────────┤
   │ @               │ A         │ 1.2.3.4         │ PROXIED         │
   │ matrix          │ A         │ 1.2.3.4         │ PROXIED         │
   │ auth            │ A         │ 1.2.3.4         │ PROXIED         │
   │ element         │ A         │ 1.2.3.4         │ PROXIED         │
   │ call            │ A         │ 1.2.3.4         │ PROXIED         │
   │ livekit         │ A         │ 1.2.3.4         │ PROXIED         │
   │ turn            │ A         │ 1.2.3.4         │ DNS ONLY        │
   └─────────────────┴───────────┴─────────────────┴─────────────────┘
```

### Step-by-step NPM guide (when NPM is selected)

The script pauses at each proxy host and shows you exactly what to configure, including copy-ready Advanced Tab nginx blocks:

```
┌──────────────────────────────────────────────────────────────┐
│               NPM SETUP - MATRIX HOMESERVER                  │
└──────────────────────────────────────────────────────────────┘

Create Proxy Host:
   Domain:     matrix.example.com
   Forward to: http://192.168.1.x:8008
   Enable:     Websockets, SSL (Force HTTPS)
   ⚠  Do NOT enable Block Exploits / ModSecurity

Advanced Tab (copy everything inside the box):
┌─────────────────────────────────────────────────────────────┐
│ proxy_hide_header Access-Control-Allow-Origin;              │
│ proxy_hide_header Access-Control-Allow-Methods;             │
│ client_max_body_size 50M;                                   │
│ ...                                                         │
└─────────────────────────────────────────────────────────────┘
```

### Deployment summary

```
╔══════════════════════════════════════════════════════════════╗
║                  DEPLOYMENT COMPLETE  ✓                      ║
╚══════════════════════════════════════════════════════════════╝

ACCESS URLS
───────────────────────────────────────────────────────────────
   Matrix API:          http://192.168.1.x:8008 (LAN) / https://matrix.example.com (WAN)
   Auth Service (MAS):  http://192.168.1.x:8010 (LAN) / https://auth.example.com (WAN)
   Element Web:         http://192.168.1.x:8012 (LAN) / https://element.example.com (WAN)
   Element Call:        https://call.example.com (via Element Web)
   Synapse Admin:       http://192.168.1.x:8009 (LAN only)

DATABASE CREDENTIALS
───────────────────────────────────────────────────────────────
   DB User:       synapse
   DB Password:   ****************
   Databases:     synapse, matrix_auth, syncv3
   Shared Secret: ********************************
```

---

## User registration

Registration through Element Web's built-in form is **disabled** — this is intentional. MAS handles all authentication via OIDC.

To register a new user:
```bash
docker exec matrix-auth mas-cli manage register-user
```
Or visit `https://auth.yourdomain.com/account/` directly.

---

## Uninstall

Run the script again and select option 3. It detects all containers, volumes, networks and directories and removes them after confirmation.

```
[!] WARNING: Existing Matrix resources detected!

   NAME                         STATUS       IMAGE
   ──────────────────────────── ──────────── ──────────────────────────────
   synapse                      an hour      synapse:latest
   matrix-auth                  an hour      matrix-authentication-service:latest
   element-web                  22 minutes   element-web:latest
   ...

Remove ALL detected Docker resources listed above? (y/n):
```

---

## Notes

- Secrets and passwords are randomly generated on each fresh install
- The script checks GitHub for updates on launch
- Caddy and Traefik configs are written automatically — no manual proxy setup needed
- NPM requires manual proxy host creation but the script walks you through each one
- `turn.yourdomain.com` should always be **DNS Only** (not proxied) in Cloudflare

---

## License

Do whatever you want with it. No warranty. Don't blame me if it breaks something.
