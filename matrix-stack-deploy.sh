#!/bin/bash

# =================================================================
# TITLE: MATRIX STACK DEPLOYER
# AUTHOR: MadCat (2026)
# =================================================================

main_deployment() {
    draw_header
    
    # --- [ 1. SYSTEM AUDIT & DOCKGE ] ---
    echo -e "${WARNING}>> Auditing System Environment...${RESET}"
    DOCKGE_INSTALLED=$(docker ps -qf name=dockge 2>/dev/null)
    if [ -z "$DOCKGE_INSTALLED" ] && [ ! -d "/opt/dockge" ]; then
        echo -e "${ERROR}[!] Dockge management interface not detected.${RESET}"
        read -p "Install Dockge (includes Docker & Compose)? (y/n): " INST_DOCKGE
        if [[ "$INST_DOCKGE" =~ ^[Yy]$ ]]; then
            echo -e "${WARNING}>> Initializing Docker Stack...${RESET}"
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            mkdir -p /opt/dockge /opt/stacks
            cd /opt/dockge && curl https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml --output compose.yaml
            docker compose up -d && cd - > /dev/null
        fi
    fi

    # --- [ 2. NETWORK DISCOVERY ] ---
    echo -e "${WARNING}>> Verifying Network Parameters...${RESET}"
    RAW_IP=$(curl -sL --max-time 5 https://api.ipify.org || curl -sL --max-time 5 https://ifconfig.me/ip)
    AUTO_PUBLIC_IP=$(echo "$RAW_IP" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    AUTO_LOCAL_IP=$(hostname -I | awk '{print $1}')
    echo -e "   [+] Public IP: ${SUCCESS}$AUTO_PUBLIC_IP${RESET}"
    echo -e "   [+] Local IP:  ${SUCCESS}$AUTO_LOCAL_IP${RESET}"
    read -p "Confirm network settings? (y/n): " CONFIRM_IP
    [[ "$CONFIRM_IP" =~ ^[Nn]$ ]] && read -p "Enter Public IP: " PUBLIC_IP && read -p "Enter Local IP: " LOCAL_IP || { PUBLIC_IP=$AUTO_PUBLIC_IP; LOCAL_IP=$AUTO_LOCAL_IP; }

    # --- [ 3. PROXY & PATH ] ---
    echo -e "\n${ACCENT}[ STEP 1 ] Infrastructure Selection${RESET}"
    echo -e "${INFO}1)${RESET} NPM/Plus  ${INFO}2)${RESET} Cloudflare  ${INFO}3)${RESET} Caddy  ${INFO}4)${RESET} Traefik  ${INFO}5)${RESET} Generic"
    read -p "Select Proxy Strategy: " PROXY_CHOICE
    TARGET_DIR="/opt/stacks/matrix-stack"
    mkdir -p "$TARGET_DIR/synapse" "$TARGET_DIR/postgres_data" "$TARGET_DIR/coturn"

    # --- [ 4. CREDENTIALS ] ---
    echo -e "\n${ACCENT}[ STEP 2 ] Service Configuration${RESET}"
    read -p "Base Domain (e.g. domain.com): " DOMAIN
    read -p "Matrix Subdomain (e.g. matrix): " SUB_MATRIX
    read -p "PostgreSQL Password: " DB_PASS
    read -p "Admin Username: " ADMIN_USER
    read -s -p "Admin Password: " ADMIN_PASS
    echo -e "\n"

    # --- [ 5. CONFIG GENERATION ] ---
    echo -e "${WARNING}>> Generating Encryption Keys and Configuration...${RESET}"
    TURN_SECRET=$(openssl rand -hex 32)
    REG_SECRET=$(openssl rand -hex 32)

    cat <<EOF > $TARGET_DIR/compose.yaml
services:
  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    environment: [ "POSTGRES_USER=synapse", "POSTGRES_PASSWORD=$DB_PASS", "POSTGRES_DB=synapse" ]
    volumes: [ "./postgres_data:/var/lib/postgresql/data" ]
    networks: [ matrix-net ]
  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    volumes: [ "./synapse:/data" ]
    ports: [ "8008:8008" ]
    depends_on: [ postgres ]
    networks: [ matrix-net ]
  synapse-admin:
    image: awesometechnologies/synapse-admin:latest
    ports: [ "8009:80" ]
    networks: [ matrix-net ]
  coturn:
    image: coturn/coturn:latest
    restart: unless-stopped
    ports: [ "3478:3478/tcp", "3478:3478/udp", "49152-49252:49152-49252/udp" ]
    volumes: [ "./coturn/turnserver.conf:/etc/coturn/turnserver.conf" ]
    networks: [ matrix-net ]
networks:
  matrix-net:
    name: matrix-net
EOF

    cat <<EOF > $TARGET_DIR/synapse/homeserver.yaml
server_name: "$DOMAIN"
public_baseurl: "https://$SUB_MATRIX.$DOMAIN"
database: { name: psycopg2, args: { user: synapse, password: "$DB_PASS", database: synapse, host: postgres } }
trusted_proxies: [ "$LOCAL_IP", "127.0.0.1", "172.16.0.0/12" ]
enable_registration: true
turn_uris: ["turn:$DOMAIN:3478?transport=udp", "turn:$DOMAIN:3478?transport=tcp"]
turn_shared_secret: "$TURN_SECRET"
registration_shared_secret: "$REG_SECRET"
macaroon_secret_key: "$(openssl rand -hex 32)"
form_secret: "$(openssl rand -hex 32)"
EOF

    cat <<EOF > $TARGET_DIR/coturn/turnserver.conf
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=$DOMAIN
external-ip=$PUBLIC_IP
EOF

    sudo chown -R 991:991 "$TARGET_DIR/synapse"
    sudo chown -R 70:70 "$TARGET_DIR/postgres_data"

    draw_footer
}

# --- [ UI & THEME ENGINE ] ---

draw_header() {
    clear
    echo -e "${BANNER}================================================================${RESET}"
    echo -e "${ACCENT}             MATRIX STACK DEPLOYER BY MADCAT                  ${RESET}"
    echo -e "${BANNER}================================================================${RESET}"
    echo -e "${INFO}  INCLUDES: ${RESET}${ACCENT}Synapse, Postgres, Coturn, Admin UI, Dockge${RESET}"
    echo -e "${INFO}  PROXIES:  ${RESET}${ACCENT}NPM, Cloudflare, Caddy, Traefik, Universal${RESET}"
    echo -e "${BANNER}================================================================${RESET}"
}

draw_footer() {
    clear
    echo -e "${BANNER}================================================================${RESET}"
    echo -e "${SUCCESS}              DEPLOYMENT SUCCESSFULLY COMPLETED                 ${RESET}"
    echo -e "${BANNER}================================================================${RESET}"
    
    echo -e "${ACCENT}>> REVERSE PROXY CONFIGURATION:${RESET}"
    case $PROXY_CHOICE in
        1) echo -e "   Target: $SUB_MATRIX.$DOMAIN -> $LOCAL_IP:8008 (Websockets: Enabled)";;
        2) echo -e "   Service: http://$LOCAL_IP:8008 (Websockets: Enabled)";;
        3) echo -e "   Caddy: reverse_proxy $LOCAL_IP:8008";;
        4) echo -e "   Traefik Rule: Host(\`$SUB_MATRIX.$DOMAIN\`)";;
        5) echo -e "   Generic: Forward X-Forwarded-For headers to $LOCAL_IP:8008";;
    esac

    echo -e "\n${BANNER}>> FIREWALL / PORT FORWARDING:${RESET}"
    echo -e "   • 80/443 (TCP)   --> Web Traffic / Federation"
    echo -e "   • 3478 (TCP/UDP) --> VoIP Signaling"
    echo -e "   • 49152-49252 (UDP) --> Media Relay (TURN)"

    echo -e "\n${WARNING}>> FINAL STEPS:${RESET}"
    echo -e "   1. Launch Stack: ${INFO}cd $TARGET_DIR && docker compose up -d${RESET}"
    echo -e "   2. Register Admin: ${INFO}docker exec -it synapse register_new_matrix_user...${RESET}"
    echo -e "${BANNER}================================================================${RESET}"
}

# --- [ COLOR THEME BOX ] ---
BANNER='\033[1;95m'   # Pink
ACCENT='\033[1;96m'   # Cyan
WARNING='\033[1;93m'  # Yellow
SUCCESS='\033[1;92m'  # Green
ERROR='\033[1;91m'    # Red
INFO='\033[1;97m'     # White
RESET='\033[0m'       # Reset

# Execute Application
main_deployment
