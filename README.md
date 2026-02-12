# Matrix Stack Deployer by MadCat 🐾

A high-performance, automated Bash utility designed to deploy a fully-featured **Matrix Synapse** ecosystem in minutes. This script handles everything from system dependencies and network discovery to secure configuration generation and reverse proxy guidance.

---

## 🚀 Overview
Deploying a Matrix homeserver manually can be error-prone due to complex permission requirements and interlocking components. The **Matrix Stack Deployer** automates this process into a guided, interactive experience, ensuring your stack is secure and production-ready.

### 📦 System Components
* **Homeserver:** Matrix Synapse (Latest)
* **Database:** PostgreSQL 15 (Alpine)
* **VOIP/Video:** Coturn (TURN/STUN)
* **Management:** Synapse-Admin UI & Dockge (Stack Manager)
* **Security:** Automated OpenSSL secret generation and permission hardening

### 🌐 Supported Gateways
The script generates specific configuration snippets and logic for:
* **Nginx Proxy Manager (NPM / NPM Plus)**
* **Cloudflare Tunnels (Argo)**
* **Caddy & Traefik**
* **Universal/Generic Reverse Proxies** (Headers & Timeout guidance)

---

## 🛠️ Installation

### Quick Start
Run the following command on a fresh Ubuntu/Debian/Docker-compatible Linux instance:

```bash
chmod +x matrix_deploy.sh
./matrix_deploy.sh
