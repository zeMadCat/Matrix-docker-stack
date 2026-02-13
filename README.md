# Matrix Stack Deployer by MadCat 🐾

A straightforward, automated Bash script that deploys a complete Matrix Synapse ecosystem with all the essential components. No complex manual configuration - just run it and follow the prompts.

## What's Inside

This script sets up everything you need for a modern Matrix homeserver:

- **Synapse** - The core Matrix homeserver
- **PostgreSQL 15** - Database backend
- **Coturn** - TURN/STUN server for VoIP calls
- **LiveKit** - High-performance WebRTC server for video conferences
- **Synapse-Admin** - Web UI for user management
- **Element Call** - Video conferencing frontend

All components are containerized with Docker, making deployment clean and maintenance straightforward.

## Why Use This?

Setting up Matrix manually means juggling multiple services, permissions, and configurations. It's easy to miss something. This script handles all of that:

- Automatic network discovery (detects your public/local IPs)
- Generates secure random passwords and secrets
- Creates proper configuration files for each service
- Checks for existing Matrix resources to avoid conflicts
- Guides you through reverse proxy setup (NPM, Caddy, Traefik, Cloudflare)
- Asks about security choices (LAN access, registration, email verification)
- Optional log rotation to prevent disk space issues

## Quick Start

```bash
# Download the script
wget https://raw.githubusercontent.com/zeMadCat/Matrix-docker-stack/main/matrix-stack-deploy.sh

# Make it executable
chmod +x matrix-stack-deploy.sh

# Run as root (required for Docker and system config)
sudo ./matrix-stack-deploy.sh
```

The script is interactive - just answer the questions and let it work.

## What You'll Be Asked

The script walks you through each step clearly:

1. **System updates** - Checks and updates packages if needed
2. **Dependency installation** - Installs curl, wget, openssl, jq, logrotate
3. **Network detection** - Shows detected IPs (public/local) and asks if you want to use them
4. **Conflict check** - Looks for existing Matrix containers/volumes/networks
5. **Deployment path** - Choose where to put the stack (Dockge, current dir, or custom)
6. **Domain configuration** - Your base domain and subdomains for Matrix and Element Call
7. **Server name** - How you want user IDs to look (@username:domain or @username:subdomain.domain)
8. **Registration** - Allow public registration or keep it admin-only
9. **Email verification** - If you enable registration, choose whether to require email verification
10. **Reverse proxy** - Pick your preferred option (NPM, Caddy, Traefik, Cloudflare, or manual)
11. **Admin password** - Auto-generate or create your own
12. **TURN LAN access** - Allow/block local network access (security choice)
13. **Log rotation** - Let the script set up automatic log management

After deployment, it shows you all credentials, secrets, DNS records, and configuration file locations.

## What You Get

```
┌──────────────────────────────────────────────────────────────┐
│              MATRIX SYNAPSE FULL STACK DEPLOYER              │
│                          by MadCat                           │
│                            v1.0                              │
│                                                              │
│                    Included Components:                      │
│               • Synapse • LiveKit • Coturn                   │
│         • PostgreSQL • Synapse-Admin • Element Call          │
└──────────────────────────────────────────────────────────────┘
```

### Services and Ports

| Service | Container Name | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------------|---------|
| PostgreSQL | synapse-db | 5432 | - | Database |
| Synapse | synapse | 8008 | 8008 | Matrix homeserver |
| Synapse-Admin | synapse-admin | 80 | 8009 | Web admin UI |
| Coturn | coturn | 3478 | 3478 | TURN/STUN server |
| LiveKit | livekit | 7880 | 7880 | WebRTC server |
| Element Call | element-call | 80 | 8007 | Video calls |

### What Gets Created

- `/opt/stacks/matrix-stack/` (or your chosen path) with all configuration files
- Docker containers for each service on a shared `matrix-net` network
- PostgreSQL database with secure credentials
- Coturn TURN server with proper IP configuration
- LiveKit server ready for WebRTC
- Element Call configured to connect to your Matrix server
- Optional log rotation configuration in `/etc/logrotate.d/`

## Proxy Setup

The script can't set up your reverse proxy automatically (since it might be on another machine or in a different container), but it provides detailed guides for each option:

- **Nginx Proxy Manager** - Shows which boxes to check and what to paste in the Advanced tab
- **Caddy** - Provides a complete Caddyfile configuration
- **Traefik** - Gives you the dynamic configuration YAML
- **Cloudflare Tunnel** - Shows the tunnel config and routing commands
- **Manual** - Just tells you the forwarding addresses

## Security Notes

- Registration is **disabled by default** - you create users manually via the admin user
- If you enable registration, you're warned about spam and asked about email verification
- TURN LAN access is **disabled by default** (more secure for production)
- All passwords and secrets are randomly generated and shown only once
- The script suggests log rotation to prevent logs from filling your disk

## After Deployment

The final screen shows you everything you need:

- **Access credentials** - Your server name, admin username/password, admin panel URL
- **API endpoints** - LAN and WAN addresses for Matrix API and Element Call
- **Internal secrets** - Database passwords, shared secrets (save these!)
- **DNS records** - What A records to create and whether they should be proxied
- **Configuration files** - Where to find each service's config
- **Important notes** - Reminders about federation testing, TURN, log rotation

## Requirements

- Ubuntu/Debian (or any Debian-based Linux)
- Root access (the script checks and exits if not root)
- A domain name with DNS pointed to your server (for WAN access)
- Ports 80/443 for your reverse proxy, plus the service ports above

## Troubleshooting

**Synapse fails to start**
Check the logs: `docker logs -f synapse`

**Can't register the admin user**
Make sure Synapse is fully running (the script waits up to 5 minutes)

**Coturn isn't working**
Verify that ports 3478 and 49152-49252 are forwarded in your router/firewall

**LiveKit connections fail**
The UDP port range (50000-50050) needs to be open and forwarded

## License

MIT - Do what you want with it, just don't blame me if something breaks.

---

*This script was developed with assistance from AI tools to handle the tedious parts, but the logic, structure, and testing are all human-driven. It's meant to be practical, not perfect - if you find issues or have improvements, pull requests are welcome.*
