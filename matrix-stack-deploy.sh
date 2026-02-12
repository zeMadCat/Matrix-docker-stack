#!/bin/bash

# =================================================================
# TITLE: MATRIX STACK DEPLOYER (AUTO-PROVISION EDITION)
# AUTHOR: MadCat (2026)
# =================================================================

# --- [ SELF-HEALING / SANITIZATION ] ---
# Force remove Windows CR characters if present
sed -i 's/\r$//' "$0" 2>/dev/null

main_deployment() {
    # Define colors early so draw_header works
    P='\033[1;95m'; C='\033[1;96m'; Y='\033[1;93m'; G='\033[1;92m'; R='\033[1;91m'; W='\033[1;97m'; NC='\033[0m'
    
    draw_header
    
    # --- [ 1. DEPENDENCY AUTO-INSTALL ] ---
    echo -e "${Y}>> Verifying System Dependencies...${NC}"
    
    for tool in curl openssl; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${R}[!] $tool is missing. Attempting auto-install...${NC}"
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y $tool
            elif command -v yum &> /dev/null; then
                sudo yum install -y $tool
            else
                echo -e "${R}Error: Could not auto-install $tool. Please install manually.${NC}"
                exit 1
            fi
        fi
    done

    # --- [ 2. SYSTEM AUDIT & DOCKGE ] ---
    DOCKGE_INSTALLED=$(docker ps -qf name=dockge 2>/dev/null)
    if [ -z "$DOCKGE_INSTALLED" ] && [ ! -d "/opt/dockge" ]; then
        echo -e "${R}[!] Dockge management interface not detected.${NC}"
        read -p "Install Dockge (includes Docker & Compose)? (y/n): " INST_DOCKGE
        if [[ "$INST_DOCKGE" =~ ^[Yy]$ ]]; then
            echo -e "${Y}>> Initializing Docker Stack...${NC}"
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            mkdir -p /opt/dockge /opt/stacks
            cd /opt/dockge && curl https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml --output compose.yaml
            docker compose up -d && cd - > /dev/null
        fi
    fi

    # --- [ 3. NETWORK DISCOVERY ] ---
    echo -e "${Y}>> Verifying Network Parameters...${NC}"
    RAW_IP=$(curl -sL --max-time 5 https://api.ipify.org || curl -sL --max-time 5 https://ifconfig.me/ip)
    AUTO_PUBLIC_IP=$(echo "$RAW_IP" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    AUTO_LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "   [+] Public IP: ${G}$AUTO_PUBLIC_IP${NC}"
    echo -e "   [+] Local IP:  ${G}$AUTO_LOCAL_IP${NC}"
    read -p "Confirm network settings? (y/n): " CONFIRM_IP
    
    if [[ "$CONFIRM_IP" =~ ^[Nn]$ ]]; then
        read -p "   Enter Public IP: " PUBLIC_IP
        read -p "   Enter Local IP:  " LOCAL_IP
    else
        PUBLIC_IP=$AUTO_PUBLIC_IP
        LOCAL_IP=$AUTO_LOCAL_IP
    fi

    # --- [ 4. INFRASTRUCTURE SELECTION ] ---
    echo -e "\n${C}[ STEP 1 ] Infrastructure Selection${NC}"
    echo -e "${W}1)${NC} NPM/Plus  ${W}2)${NC} Cloudflare  ${W}3)${NC} Caddy  ${W}4)${NC} Traefik  ${W}5)${NC} Generic"
    read -p "Select Proxy Strategy: " PROXY_CHOICE
    
    TARGET_DIR="/opt/stacks/matrix-stack"
    mkdir -p "$TARGET_DIR/synapse" "$TARGET_DIR/postgres_data" "$TARGET_DIR/coturn"

    # --- [ 5. SERVICE CONFIGURATION ] ---
    echo -e "\n${C}[ STEP 2 ] Service Configuration${NC}"
    read -p "Base Domain (e.g. domain.com): " DOMAIN
    read -p "Matrix Subdomain (e.g. matrix): " SUB_MATRIX
    read -p "PostgreSQL Password: " DB_PASS
    read -p "Admin Username: " ADMIN_USER
    read -s -p "Admin Password: " ADMIN_PASS
    echo -e "\n"

    # --- [ 6. CONFIG GENERATION ] ---
    echo -e "${Y}>> Generating Encryption Keys and Configuration...${NC}"
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
    ports:
      - "3478:3478/tcp"
      - "3478:3478/udp"
      - "49152-49252:49152-49252/udp"
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

# --- [ UI COMPONENTS ] ---

draw_header() {
    clear
    echo -e "${P}================================================================${NC}"
    echo -e "${C}             MATRIX STACK DEPLOYER BY MADCAT                  ${NC}"
    echo -e "${P}================================================================${NC}"
    echo -e "${W}  SYSTEM COMPONENTS: ${NC}${C}Synapse, Postgres, Coturn, Admin UI, Dockge${NC}"
    echo -e "${W}  SUPPORTED GATEWAYS: ${NC}${C}NPM, Cloudflare, Caddy, Traefik, Universal${NC}"
    echo -e "${P}================================================================${NC}"
}

draw_footer() {
    clear
    echo -e "${P}================================================================${NC}"
    echo -e "${G}              DEPLOYMENT SUCCESSFULLY COMPLETED                 ${NC}"
    echo -e "${P}================================================================${NC}"
    echo -e "${C}>> REVERSE PROXY CONFIGURATION:${NC}"
    case $PROXY_CHOICE in
        1) echo -e "   Target: $SUB_MATRIX.$DOMAIN -> $LOCAL_IP:8008 (Websockets: Enabled)";;
        2) echo -e "   Service: http://$LOCAL_IP:8008 (Websockets: Enabled)";;
        3) echo -e "   Caddy: reverse_proxy $LOCAL_IP:8008";;
        4) echo -e "   Traefik Rule: Host(\`$SUB_MATRIX.$DOMAIN\`)";;
        5) echo -e "   Generic: Forward X-Forwarded-For headers to $LOCAL_IP:8008";;
    esac
    echo -e "\n${P}>> FIREWALL / PORT FORWARDING:${NC}"
    echo -e "   • 80/443 (TCP)   --> Web Traffic / Federation"
    echo -e "   • 3478 (TCP/UDP) --> VoIP Signaling"
    echo -e "   • 49152-49252 (UDP) --> Media Relay (TURN)"
    echo -e "\n${Y}>> FINAL STEPS:${NC}"
    echo -e "   1. Launch Stack: ${W}cd $TARGET_DIR && docker compose up -d${NC}"
    echo -e "   2. Register Admin: ${W}docker exec -it synapse register_new_matrix_user...${NC}"
    echo -e "${P}================================================================${NC}"
}

# Execute
main_deployment
