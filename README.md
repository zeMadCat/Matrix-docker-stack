<div align="center">
  <img src="images/mds.png" alt="Matrix Docker Stack" style="width: min(450px, 100%)"/>
  <p>A single interactive bash script that deploys a full Matrix homeserver stack on any Linux machine with Docker.</p>
</div>

---

> **Changelog**
>
> <details open>
> <summary><strong>v2.0</strong> — 2026-04-09</summary>
>
> - **Hookshot bridge** — webhooks, GitHub, GitLab, RSS/Atom feeds; generates passkey.pem, writes config.yml and registration.yml from scratch; per-proxy activation guide shown post-install; selectable at install time alongside other bridges
> - **Repair wizard** — new menu option 9; detects installed stack, shows live container status and well-known health, guided repair for: Synapse/MAS/DB, well-known, calls/LiveKit/TURN, reverse proxy, admin panel, Element Web, bridges; auto-restart with post-repair status check
> - **Migrate Well-Known** — reconfigure option 6; auto or guided mode to switch between inline proxy respond blocks and static files on disk; Caddy auto-rewrites Caddyfile and reloads; NPM generates conf snippet; three directions: inline→files, files→inline, refresh/repair
> - **NPM auto proxy-host creation** — all proxy hosts created via NPM REST API after install; Let's Encrypt or HTTP-only SSL prompt; well-known location blocks injected into base domain; waits on port 80 (reliable signal); falls back to manual guide if auth fails
> - **NPM port conflict** — detects what holds ports 80/443 (old NPM, Caddy, Traefik); offers to stop old NPM and reuse standard ports instead of forcing 8000/8443 fallback
> - **Uninstall fix** — `_delete_single_stack` rewritten: `docker compose down` as primary, then scans by compose project label + all known container names; NPM and Hookshot added to orphan scanner
> - **Orphan cleanup** — uninstall with no stack dir falls through to container scan instead of silently returning
> - **Telegram bridge** — migrated to Go rewrite; `dock.mau.dev/mautrix/telegram:latest` (main branch) is now the Go bridge; uses `/pkg/connector/example-config.yaml`, top-level `api_id`/`api_hash`, standard Go entrypoint like all other bridges
> - **MAS config guard** — removes config.yaml if it was created as a directory by a previous failed install; same guard for compose.yaml, homeserver.yaml, livekit.yaml
> - **Compose output suppressed** — `docker compose up/down` no longer prints TUI to terminal; goes to deployment log instead
> - **Caddy well-known fix** — `respond` blocks use backtick syntax; single quotes caused Caddy to return literal `'` instead of JSON (issue #12)
> - **Diagnostics hang fix** — `docker stats` timeout 15s; `docker logs` per container timeout 8s
> - **VPN guide opt-in** — long VPN guide only shown if user requests it after answering yes to VPN question
> - **DELETE / y/n separation** — cleanup uses y/n; uninstall proper still requires typing DELETE
> - **DuckDNS token** — visible input with masked confirmation (first4\*\*\*\*last4 + char count)
> - **S3 warning** — explicitly lists Google Drive, Dropbox, OneDrive, NFS, SMB as not S3-compatible
> - **NPM/NPMPlus label** — NPMPlus shown only when user has existing proxy; fresh install shows NPM only
> - **Port conflict message** — names actual detected service instead of guessing Caddy/Traefik
> - **System package upgrade** — ask before upgrading on all distros; default yes
>
> </details>
>
> <details>
> <summary><strong>v1.9</strong> — 2026-03-14</summary>
>
> - **Multi-distro support** — Debian/Ubuntu/DietPi, Arch/Manjaro and Fedora/RHEL now all supported; OS auto-detected on launch, shown in color after the header
> - **Distro-aware package manager** — `apt`, `pacman` or `dnf` used throughout; correct package names per distro for all dependencies
> - **Distro-aware Docker install** — `get-docker.sh` (Debian), `pacman` (Arch), official DNF repo (Fedora); docker group prompt on Arch/Fedora
> - **Unknown distro fallback** — 1/2/3 selection menu with a clear warning that an incorrect choice may require a full redeploy
> - **Verbose deployment log** — full run logged to `matrix-stack-deployment.log` in the stack directory; secrets redacted; ANSI color stripped; safe to share
> - **Docker detection fix** — no longer prompts to install Docker/Dockge when already present
> - **daemon.json timing fix** — Docker log limits written before the final stack restart
>
> </details>
>
> <details>
> <summary><strong>v1.8</strong> — 2026-03-09</summary>
>
> - **Multi-stack support** — install multiple independent stacks on one server; each gets its own containers, network, and ports
> - **Container & network name conflict detection** — auto-appends `-2`, `-3`, etc. when names are already in use
> - **Reconfigure menu** — modify domain, features and bridges on any installed stack post-install
> - **Verify multi-stack** — select which stack(s) to verify via whiptail; runs checks one by one
> - **Corrupt compose.yaml auto-repair** — detects and repairs duplicate service blocks when re-adding bridges
> - **Cleanup whiptail shows stacks only** — one checkbox per stack; all associated resources cleaned automatically
> - **Element Call fix** — resolved `MISSING_MATRIX_RTC_FOCUS` and `MISSING_MATRIX_RTC_TRANSPORT` errors
>
> </details>
>
> <details>
> <summary><strong>v1.7</strong> — 2026-03-08</summary>
>
> - **Bridge error messages** — show log file paths and last 5 lines of output
> - **NPM port fallback** — auto-detects port conflicts, falls back to 8000/8443 if 80/443 in use
> - **Diagnostics menu** — option 7 collects system info, Docker config, logs, saves to timestamped file
> - **System-wide resource detection** — detects multiple Matrix installs; auto-discovers paths from running containers
> - **Selective cleanup menu** — whiptail checklist to choose which installs to remove
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
> - **Pangolin reverse proxy support** — Newt tunnel; zero open ports on home server
> - **Storage check before path selection** — shows estimated disk usage and free space
> - **Network detection revamp** — re-detect loop with manual entry fallback
> - **NPM base domain config** — well-known served inline; root redirects to Element Web
> - **MAS config fix** — `homeserver` correctly uses `SERVER_NAME` instead of `DOMAIN`
>
> </details>
>
> <details>
> <summary><strong>v1.4 — v1.0</strong></summary>
>
> v1.4: Storage check. Version check improvements.
> v1.3: MAS signing key fixed. All bridges fixed. Add Bridges universal. User registration form restored.
> v1.2: Admin panel choice. LiveKit TURN/STUN. Health checks conditional. Input validation. Bridge registration fixed.
> v1.1: Element Admin, bridge improvements, MAS OIDC fix, Caddy/Traefik auto-config.
> v1.0: First public release.
>
> </details>

---

## What it is

A fully interactive TUI deployment script for a self-hosted Matrix stack. Originally written for my own domain but designed to work with any domain through a dynamic setup wizard. You answer prompts, the script builds everything.

Use it at your own risk, and feel free to adapt it.

---

## Stack

| Service | Purpose |
|---|---|
| Synapse | Matrix homeserver |
| MAS | Matrix Authentication Service (OIDC) |
| PostgreSQL | Database for Synapse and MAS |
| LiveKit SFU | WebRTC media server — unlimited screenshares, built-in TURN/STUN |
| LiveKit JWT | Token generation service for LiveKit |
| Element Web | Web client (optional) |
| Element Call | Standalone video conferencing UI (optional) |
| Element Admin | Modern admin panel (optional) |
| Synapse Admin | Classic admin panel (optional) |
| Matrix Media Repo | Advanced media handling with S3 support (optional) |

---

## Usage

```bash
curl -O https://raw.githubusercontent.com/zeMadCat/Matrix-docker-stack/main/matrix-stack-deploy.sh
chmod +x matrix-stack-deploy.sh
sudo ./matrix-stack-deploy.sh
```

---

## Menu

```
 What would you like to do?

   1)  Install       — Deploy a new Matrix stack
   2)  Update        — Pull latest images and restart the stack
   3)  Reconfigure   — Re-run config steps without deleting data
   4)  Uninstall     — Remove the Matrix stack and all data
   5)  Verify        — Check integrity of an existing installation
   6)  Logs          — View container logs for troubleshooting
   7)  Diagnostics   — Collect system info for troubleshooting
   8)  Changelog     — View latest version changelog
   9)  Repair        — Guided repair wizard for common issues

   0)  Exit
```

---

## Repair Wizard (option 9)

The repair wizard detects your installed stack, shows live container status and well-known health, then walks you through fixing specific issues:

| Area | What it does |
|---|---|
| Synapse / MAS / DB | Checks PostgreSQL health, starts stopped containers, shows last logs, verifies Synapse health endpoint |
| Well-known | Curls both endpoints, shows HTTP code and response body, provides exact proxy config for your proxy type, offers to run auto-fix migration |
| Calls (LiveKit) | Checks LiveKit/JWT containers, lists required open ports, explains TURN DNS-only requirement, VPN UDP blocking |
| Reverse proxy | Validates and reloads Caddy; shows NPM required proxy hosts; shows Traefik log command |
| Admin panel | Detects Element Admin or Synapse Admin, starts if stopped, shows required proxy entry |
| Element Web | Checks config.json base_url, auto-fixes mismatch, restarts container |
| Bridges | Lists running bridges, checks registration file and homeserver address, offers to restart all |
| Restart all | `docker compose up -d --remove-orphans` with confirmation gate |

---

## Reconfigure (option 3)

```
 Reconfiguration Options:

   1)  Modify domain
   2)  Add/remove features
   3)  Add/remove bridges

   ── Advanced ────────────────────────────────────
   4)  DuckDNS Federation Fix  — Port 8448 direct federation
   5)  Revert Media Repo       — Remove Media Repo, restore native
   6)  Migrate Well-Known      — Change where well-known is served
```

### Migrate Well-Known (option 6)

Switch how `/.well-known/matrix/{server,client}` is served without reinstalling. Two modes — **Automatic** (rewrites config files and reloads the proxy) or **Guided** (step-by-step instructions, no automatic changes).

Three directions: inline proxy respond → static files, static files → inline respond, or refresh/repair both.

> `server_name` (user IDs like `@user:example.com`) cannot be changed. This only affects where well-known is served from.

---

## Bridges

### Available bridges

| Bridge | Bot user | Command | Notes |
|---|---|---|---|
| Discord | `@discordbot:domain` | `login` | Browser OAuth |
| Telegram | `@telegrambot:domain` | `login` | Phone + SMS code |
| WhatsApp | `@whatsappbot:domain` | `login` | Scan QR |
| Signal | `@signalbot:domain` | `link` | Scan QR |
| Slack | `@slackbot:domain` | `login` | Browser OAuth |
| Meta (FB/Instagram) | `@metabot:domain` | `login` | Username + password |
| Hookshot | `@hookshot:domain` | `!hookshot help` | Webhooks, GitHub, GitLab, RSS |

### Hookshot

Hookshot connects Matrix to external services via webhooks and integrations. No external database required — uses Matrix state as its store.

**Requires two ports to be internet-reachable:**

| Port | Purpose |
|---|---|
| 9000 | Incoming webhooks (GitHub, generic webhooks, etc.) |
| 9002 | Element widget UI for managing connections |

The script shows a proxy config snippet for your proxy type (Caddy/NPM/Traefik) after install.

**Usage after install** — DM `@hookshot:yourdomain` in Element Web:

```
!hookshot help                                    — list commands
!hookshot webhook                                 — create a generic webhook URL
!hookshot feed https://example.com/feed.xml       — subscribe to RSS/Atom feed
```

GitHub/GitLab integration requires additional setup (GitHub App or GitLab webhook secret). Generic webhooks and RSS feeds work out of the box.

### Adding bridges post-install

Via **Reconfigure → Add/remove bridges** — no reinstall needed.

---

## NPM Auto-Configuration

When NPM is selected as the proxy and installed by the script, all proxy hosts are created automatically via the NPM REST API:

- Base domain with well-known JSON location blocks
- Matrix homeserver (WebSocket enabled)
- MAS authentication service
- Element Web
- LiveKit SFU (WebSocket enabled)
- Optional: Element Call, admin panels, Media Repo

SSL certificates are requested via Let's Encrypt automatically. The management UI is at `http://your-server-ip:81`.

> If NPM from a previous install is holding ports 80/443, the script detects this and offers to stop the old container and reuse standard ports.

---

## User registration

Registration through Element Web's built-in form is disabled — MAS handles all authentication via OIDC.

To register a new user:

```bash
docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes
docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --admin --yes
```

Or visit `https://auth.yourdomain.com/register` directly.

---

## Deployment Log

Every deployment writes a verbose log to `matrix-stack-deployment.log` in your stack directory. Secrets are automatically redacted and ANSI color codes stripped — safe to share publicly when asking for help.

---

## Uninstall

Run the script again and select option 4. It detects all containers, volumes, networks and directories and removes them after confirmation (type DELETE).

If the stack directory is not found, the script falls through to a container scan by image pattern and compose project label — orphaned containers from a previous install are caught and offered for removal.

> **Tip:** Keep the script outside the stack folder (`~/matrix-stack-deploy.sh`).

---

## Notes

- Secrets and passwords are randomly generated on each fresh install
- The script checks GitHub for updates on launch
- Caddy and Traefik configs are written automatically — no manual proxy setup needed
- NPM proxy hosts are created automatically via API — no manual setup needed
- `turn.yourdomain.com` must always be **DNS Only** — TURN is handled by LiveKit's built-in server
- Admin panel is optional — Element Admin (modern) or Synapse Admin (classic)
- LiveKit SFU is always deployed — voice and video calls work in Element/Element X without enabling standalone Element Call
- Matrix Media Repo requires S3-compatible object storage (Backblaze B2, Cloudflare R2, MinIO, AWS S3). Google Drive, Dropbox, OneDrive and similar file sync services are **not** S3-compatible and will not work.

---

## License

Do whatever you want with it. No warranty. Don't blame me if it breaks something.
