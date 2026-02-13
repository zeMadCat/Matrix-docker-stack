#!/bin/bash

# =================================================================
# TITLE: MATRIX STACK DEPLOYER (EXPERIMENTAL)
# COMMAND: /final
# STATUS: 1:1 LOGIC | IP CONFIRMATION | BOUNDARY LOGS | COLOR MAP
# =================================================================

# --- [ 0. COLOR & UI MAPPING ] ---
BANNER='\033[1;95m'; ACCENT='\033[1;96m'; WARNING='\033[1;93m'
SUCCESS='\033[1;92m'; ERROR='\033[1;91m'; INFO='\033[1;97m'; RESET='\033[0m'

draw_header() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│              MATRIX SYNAPSE FULL STACK DEPLOYER              │"
    echo -e "└──────────────────────────────────────────────────────────────┘${RESET}"
}

main_deployment() {
    [[ $EUID -ne 0 ]] && { echo -e "${ERROR}[!] Run as root (sudo).${RESET}"; exit 1; }

    draw_header
    
    # --- [ 1. VERBOSE SELECTION ] ---
    read -p "Enable Verbose Logging? (Locked 10-line window) (y/n): " VERBOSE_CHOICE
    VERBOSE=false
    [[ "$VERBOSE_CHOICE" =~ ^[Yy]$ ]] && VERBOSE=true

    # --- [ 2. SYSTEM AUDIT ] ---
    echo -e "\n${ACCENT}>> Auditing System Environment...${RESET}"
    DOCKER_READY=false
    if command -v docker >/dev/null 2>&1; then
        echo -e "   • Docker:          ${SUCCESS}Found${RESET} ($(docker --version | awk '{print $3}' | tr -d ','))"
        DOCKER_READY=true
    fi
    if docker compose version >/dev/null 2>&1; then
        echo -e "   • Docker Compose:  ${SUCCESS}Found${RESET} ($(docker compose version | awk '{print $4}'))"
    else
        DOCKER_READY=false
    fi

    DOCKGE_FOUND=false
    if [ -n "$(docker ps -qf name=dockge 2>/dev/null)" ] || [ -d "/opt/stacks" ]; then
        echo -e "   • Dockge:          ${SUCCESS}Detected${RESET}"
        DOCKGE_FOUND=true
    fi

    # --- [ 3. NETWORK DISCOVERY & CONFIRMATION ] ---
    echo -e "\n${WARNING}>> Verifying Network Parameters...${RESET}"
    RAW_IP=$(curl -sL --max-time 5 https://api.ipify.org || curl -sL --max-time 5 https://ifconfig.me/ip)
    DETECTED_PUBLIC=$(echo "$RAW_IP" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    DETECTED_LOCAL=$(hostname -I | awk '{print $1}')
    
    echo -e "    Detected Public IP: ${SUCCESS}$DETECTED_PUBLIC${RESET}"
    echo -e "    Detected Local IP:  ${SUCCESS}$DETECTED_LOCAL${RESET}"
    read -p "Use these IPs for deployment? (y/n): " IP_CONFIRM
    
    if [[ "$IP_CONFIRM" =~ ^[Yy]$ ]]; then
        AUTO_PUBLIC_IP=$DETECTED_PUBLIC
        AUTO_LOCAL_IP=$DETECTED_LOCAL
    else
        read -p "Enter Public IP: " AUTO_PUBLIC_IP
        read -p "Enter Local IP:  " AUTO_LOCAL_IP
    fi

    CUR_DIR=$(pwd)

    # --- [ 4. WEIGHTED 3-WAY PATH SELECTION ] ---
    echo -e "\n${ACCENT}[ STEP 1 ] Infrastructure & Location${RESET}"
    if [ "$DOCKGE_FOUND" = true ]; then
        echo -e "   1) ${SUCCESS}Dockge Path (Recommended):${RESET} /opt/stacks/matrix-stack"
        echo -e "   2) Current Directory:         $CUR_DIR/matrix-stack"
        echo -e "   3) Custom Path"
        read -p "Selection (1/2/3): " PATH_SELECT
        case $PATH_SELECT in
            1) TARGET_DIR="/opt/stacks/matrix-stack" ;;
            2) TARGET_DIR="$CUR_DIR/matrix-stack" ;;
            *) read -p "Enter Full Path: " TARGET_DIR ;;
        esac
    elif [ "$DOCKER_READY" = true ]; then
        echo -e "   1) ${SUCCESS}Current Directory (Recommended):${RESET} $CUR_DIR/matrix-stack"
        echo -e "   2) Custom Path"
        read -p "Selection (1/2): " PATH_SELECT
        [[ "$PATH_SELECT" == "1" ]] && TARGET_DIR="$CUR_DIR/matrix-stack" || { read -p "Enter Full Path: " TARGET_DIR; }
    else
        read -p "Enter Deployment Path (Default /opt/matrix-stack): " TARGET_DIR
        TARGET_DIR=${TARGET_DIR:-/opt/matrix-stack}
    fi

    if [ -d "$TARGET_DIR" ]; then
        echo -e "\n${ERROR}[!] Existing Stack detected at $TARGET_DIR${RESET}"
        read -p "Completely WIPE and overwrite everything? (y/n): " OVERWRITE
        if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
            cd "$TARGET_DIR" && docker compose down -v --remove-orphans > /dev/null 2>&1
            rm -rf "$TARGET_DIR"
        else
            echo -e "${WARNING}Exiting to protect data.${RESET}"; exit 0
        fi
    fi

    mkdir -p "$TARGET_DIR/synapse" "$TARGET_DIR/postgres_data" "$TARGET_DIR/coturn" "$TARGET_DIR/livekit"

    # --- [ 5. SERVICE CONFIGURATION ] ---
    echo -e "\n${ACCENT}[ STEP 2 ] Service Configuration${RESET}"
    read -p "Base Domain (e.g., example.com): " DOMAIN
    read -p "Matrix Subdomain (e.g., matrix): " SUB_MATRIX
    read -p "Admin Username (e.g., admin): " ADMIN_USER
    
    DB_PASS=$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    ADMIN_PASS=$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
    TURN_SECRET=$(openssl rand -hex 32); REG_SECRET=$(openssl rand -hex 32)
    LK_API_KEY=$(openssl rand -hex 16); LK_API_SECRET=$(openssl rand -hex 32)

    # --- [ 6. COMPOSE GENERATION ] ---
    cat <<EOF > $TARGET_DIR/compose.yaml
services:
  postgres:
    container_name: synapse-db
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: "$DB_PASS"
      POSTGRES_DB: synapse
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes: [ "./postgres_data:/var/lib/postgresql/data" ]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [ matrix-net ]

  synapse:
    container_name: synapse
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    user: "991:991"
    volumes: [ "./synapse:/data" ]
    ports: [ "8008:8008" ]
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8008/_matrix/client/versions || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 300s
    networks: [ matrix-net ]

  synapse-admin:
    container_name: synapse-admin
    image: awesometechnologies/synapse-admin:latest
    restart: unless-stopped
    ports: [ "8009:80" ]
    networks: [ matrix-net ]

  coturn:
    container_name: coturn
    image: coturn/coturn:latest
    restart: unless-stopped
    ports: ["3478:3478/tcp", "3478:3478/udp", "49152-49252:49152-49252/udp"]
    volumes: [ "./coturn/turnserver.conf:/etc/turnserver.conf" ]
    networks: [ matrix-net ]

  livekit:
    container_name: livekit
    image: livekit/livekit-server:latest
    restart: unless-stopped
    command: --config /etc/livekit.yaml
    volumes: [ "./livekit/livekit.yaml:/etc/livekit.yaml" ]
    ports: [ "7880:7880", "50000-50050:50000-50050/udp" ]
    networks: [ matrix-net ]

networks:
  matrix-net:
    name: matrix-net
EOF

    # Config Gen
    docker run --rm -v "$TARGET_DIR/synapse:/data" -e SYNAPSE_SERVER_NAME="$SUB_MATRIX.$DOMAIN" -e SYNAPSE_REPORT_STATS=yes matrixdotorg/synapse:latest generate > /dev/null 2>&1
    chown -R 991:991 "$TARGET_DIR/synapse"

    # --- [ 7. DEPLOY & BOUNDARY-LOCKED VERBOSE WINDOW ] ---
    echo -e "${SUCCESS}>> Launching Stack...${RESET}"
    cd "$TARGET_DIR" && docker compose up -d

    if [ "$VERBOSE" = true ]; then
        echo -e "${INFO}>> VERBOSE START [Synapse Logs]${RESET}"
        until [ "$(docker ps -a -q -f name=synapse)" ]; do sleep 1; done
        for i in {1..10}; do echo -e "${INFO}  |${RESET}"; done
        echo -e "${INFO}>> VERBOSE END${RESET}"
        
        (while true; do
            echo -ne "\033[11A"
            docker logs synapse --tail 10 2>&1 | while read logline; do
                echo -ne "\033[K"
                echo -e "${INFO}  | ${logline:0:110}${RESET}"
            done
            sleep 2
        done) &
        LOG_PID=$!
    fi

    echo -ne "\n${WARNING}>> Waiting for URL: \"It works! Synapse is running\"${RESET}"
    TRIES=0
    until $(curl -s --fail http://localhost:8008 | grep -q "It works"); do
        echo -ne "."
        sleep 5
        ((TRIES++))
        [[ $TRIES -gt 60 ]] && { [ ! -z "$LOG_PID" ] && kill $LOG_PID; exit 1; }
    done

    # --- [ KILL SWITCH ] ---
    if [ ! -z "$LOG_PID" ]; then 
        kill $LOG_PID > /dev/null 2>&1
        echo -e "\n${SUCCESS}[!] Synapse detected online. Log window closed.${RESET}"
    fi

    docker exec synapse register_new_matrix_user -c /data/homeserver.yaml -u "$ADMIN_USER" -p "$ADMIN_PASS" --admin http://localhost:8008
    draw_footer
}

draw_footer() {
    echo -e "\n${SUCCESS}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│                      DEPLOYMENT COMPLETE                     │"
    echo -e "└──────────────────────────────────────────────────────────────┘${RESET}"
    
    echo -e "${ACCENT}1. ACCESS CREDENTIALS${RESET}"
    echo -e "   Matrix Domain:   ${INFO}https://$SUB_MATRIX.$DOMAIN${RESET}"
    echo -e "   Admin User:      ${INFO}$ADMIN_USER${RESET}"
    echo -e "   Admin Pass:      ${INFO}$ADMIN_PASS${RESET}"
    echo -e "   Admin Panel:     ${INFO}http://$AUTO_LOCAL_IP:8009${RESET}"

    echo -e "\n${ACCENT}2. INTERNAL SECRETS & API KEYS${RESET}"
    echo -e "   Postgres Pass:   ${INFO}$DB_PASS${RESET}"
    echo -e "   Shared Secret:   ${INFO}$REG_SECRET${RESET}"
    echo -e "   TURN Secret:     ${INFO}$TURN_SECRET${RESET}"
    echo -e "   Livekit API Key: ${INFO}$LK_API_KEY${RESET}"
    echo -e "   Livekit Secret:  ${INFO}$LK_API_SECRET${RESET}"

    echo -e "\n${ACCENT}3. CLOUDFLARE DNS SETUP${RESET}"
    echo -e "   ┌───────────────┬───────────┬───────────────┬────────────────┐"
    echo -e "   │ HOSTNAME      │ TYPE      │ VALUE         │ PROXY STATUS   │"
    echo -e "   ├───────────────┼───────────┼───────────────┼────────────────┤"
    echo -e "   │ $SUB_MATRIX     │ A         │ $AUTO_PUBLIC_IP  │ PROXIED (ON)   │"
    echo -e "   │ turn          │ A         │ $AUTO_PUBLIC_IP  │ DNS ONLY (OFF) │"
    echo -e "   │ livekit       │ A         │ $AUTO_PUBLIC_IP  │ DNS ONLY (OFF) │"
    echo -e "   └───────────────┴───────────┴───────────────┴────────────────┘"

    echo -e "\n${ACCENT}4. NGINX PROXY MANAGER (NPM) FORWARDING${RESET}"
    echo -e "   • ${INFO}$SUB_MATRIX.$DOMAIN${RESET}  ->  ${INFO}http://$AUTO_LOCAL_IP:8008${RESET}"
    echo -e "   • ${INFO}livekit.$DOMAIN${RESET}     ->  ${INFO}http://$AUTO_LOCAL_IP:7880${RESET}"

    echo -e "\n${WARNING}[!] SAVE THIS DATA IMMEDIATELY! IT IS NOT STORED ELSEWHERE.${RESET}\n"
}

main_deployment
