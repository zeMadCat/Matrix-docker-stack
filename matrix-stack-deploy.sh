#!/bin/bash

# Version
gitv="1.0"
GITHUB_REPO="zeMadCat/Matrix-docker-stack"
GITHUB_BRANCH="main"

# Header
draw_header() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│              MATRIX SYNAPSE FULL STACK DEPLOYER              │${RESET}"
    echo -e "${BANNER}│                          by MadCat                           │${RESET}"
    echo -e "${BANNER}│                            v${gitv}                              │${RESET}"
    echo -e "${BANNER}│                                                              │${RESET}"
    echo -e "${BANNER}│                    Included Components:                     │${RESET}"
    echo -e "${BANNER}│                • Synapse • PostgreSQL • Coturn               │${RESET}"
    echo -e "${BANNER}│              • LiveKit • Synapse-Admin • Element Call        │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
}

# Automatic update check
check_for_updates() {
    echo -e "\n${ACCENT}>> Checking for updates from GitHub...${RESET}"
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "   ${WARNING}curl not found, skipping update check${RESET}"
        return 1
    fi
    
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
    
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "   ${WARNING}Could not check for updates. Continuing with current version.${RESET}"
        return 1
    fi
    
    if [ "$LATEST_VERSION" != "$gitv" ]; then
        echo -e "   ${INFO}Current version: v${gitv}${RESET}"
        echo -e "   ${INFO}Latest version:  v${LATEST_VERSION}${RESET}"
        echo -e "\n${WARNING}A new version (v${LATEST_VERSION}) is available!${RESET}"
        echo -ne "Update now? (y/n): "
        read -r UPDATE_CONFIRM
        
        if [[ "$UPDATE_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n${ACCENT}>> Downloading latest version...${RESET}"
            
            local backup_file="${0}.backup"
            cp "$0" "$backup_file"
            echo -e "   ${INFO}Backup created at $backup_file${RESET}"
            
            local temp_file="${0}.tmp"
            if curl -sL "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/matrix-stack-deploy.sh" -o "$temp_file"; then
                if [ -s "$temp_file" ]; then
                    mv "$temp_file" "$0"
                    chmod +x "$0"
                    echo -e "   ${SUCCESS}✓ Update successful!${RESET}"
                    echo -e "\n${INFO}Restarting with new version...${RESET}"
                    sleep 2
                    exec "$0"
                else
                    echo -e "   ${ERROR}Downloaded file is empty. Update failed.${RESET}"
                    rm -f "$temp_file"
                    return 1
                fi
            else
                echo -e "   ${ERROR}Failed to download update.${RESET}"
                rm -f "$temp_file"
                return 1
            fi
        else
            echo -e "   ${INFO}Continuing with current version.${RESET}"
        fi
    else
        echo -e "   ${SUCCESS}✓ You're running the latest version!${RESET}"
    fi
    return 0
}

# Main deployment function
main_deployment() {
    [[ $EUID -ne 0 ]] && { echo -e "${ERROR}[!] Run as root (sudo).${RESET}"; exit 1; }

    draw_header
    
    # Check for updates automatically
    check_for_updates

    # System Update & Dependencies
    echo -e "\n${ACCENT}>> Checking for system package updates...${RESET}"
    apt update 2>/dev/null > /dev/null
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
    
    if ! [[ "$UPGRADABLE" =~ ^[0-9]+$ ]]; then
        UPGRADABLE=0
    fi
    
    if [ "$UPGRADABLE" -gt 0 ]; then
        echo -e "   ${INFO}Found $UPGRADABLE package(s) that can be upgraded${RESET}"
        echo -e "   ${ACCENT}>> Updating system packages...${RESET}"
        apt upgrade -y 2>/dev/null > /dev/null
        echo -e "   ${SUCCESS}✓ System packages updated successfully${RESET}"
    else
        echo -e "   ${SUCCESS}✓ System is already up to date${RESET}"
    fi

    echo -e "\n${ACCENT}>> Installing required dependencies...${RESET}"
    local deps=("curl" "wget" "openssl" "jq")
    local coreutils_check=$(dpkg-query -W -f='${Status}' coreutils 2>/dev/null | grep -c "ok installed" || echo "0")
    local to_install=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            to_install+=("$dep")
        fi
    done
    
    if [ "$coreutils_check" -eq 0 ]; then
        to_install+=("coreutils")
    fi
    
    if [ ${#to_install[@]} -gt 0 ]; then
        echo -e "   ${INFO}Installing missing dependencies: ${to_install[*]}${RESET}"
        apt install -y "${to_install[@]}" > /dev/null 2>&1
        echo -e "   ${SUCCESS}✓ Dependencies installed${RESET}"
    else
        echo -e "   ${SUCCESS}✓ All dependencies already present${RESET}"
    fi

    # System Audit
    echo -e "\n${ACCENT}>> Auditing system environment...${RESET}"
    DOCKER_READY=false
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        echo -e "   • ${DOCKER_COLOR}Docker:${RESET}          ${SUCCESS}Found${RESET} (${DOCKER_VERSION})"
        DOCKER_READY=true
    fi

    if docker compose version >/dev/null 2>&1; then
        COMPOSE_VERSION=$(docker compose version | awk '{print $4}')
        echo -e "   • ${DOCKER_COLOR}Docker Compose:${RESET}  ${SUCCESS}Found${RESET} (${COMPOSE_VERSION})"
    else
        echo -e "   • ${DOCKER_COLOR}Docker Compose:${RESET}  ${ERROR}Not Found${RESET}"
        DOCKER_READY=false
    fi

    DOCKGE_FOUND=false
    if [ -n "$(docker ps -qf name=dockge 2>/dev/null)" ] || [ -d "/opt/stacks" ]; then
        echo -e "   • ${DOCKER_COLOR}Dockge:${RESET}          ${SUCCESS}Detected${RESET}"
        DOCKGE_FOUND=true
    else
        echo -e "   • ${DOCKER_COLOR}Dockge:${RESET}          ${INFO}Not Detected${RESET} ${WARNING}(Recommended)${RESET}"
        echo -ne "Install Dockge (includes Docker & Compose)? (y/n): "
        read -r INST_DOCKGE
        if [[ "$INST_DOCKGE" =~ ^[Yy]$ ]]; then
            curl -fsSL https://get.docker.com | sh
            mkdir -p /opt/dockge /opt/stacks
            cd /opt/dockge && curl https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml --output compose.yaml
            docker compose up -d && cd - > /dev/null
            DOCKGE_FOUND=true
            DOCKER_READY=true
        fi
    fi

    # Network Detection
    echo -e "\n${ACCENT}>> Detecting network addresses...${RESET}"
    
    if command -v curl >/dev/null 2>&1; then
        RAW_IP=$(curl -sL --max-time 5 https://api.ipify.org 2>/dev/null || curl -sL --max-time 5 https://ifconfig.me/ip 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        RAW_IP=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || wget -qO- --timeout=5 https://ifconfig.me/ip 2>/dev/null)
    fi
    
    DETECTED_PUBLIC=$(echo "$RAW_IP" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    DETECTED_LOCAL=$(hostname -I | awk '{print $1}')
    
    echo -e "   ${INFO}Public IP:${RESET} ${PUBLIC_IP_COLOR}${DETECTED_PUBLIC:-Not detected}${RESET}"
    echo -e "   ${INFO}Local IP:${RESET}  ${LOCAL_IP_COLOR}${DETECTED_LOCAL:-Not detected}${RESET}"
    
    echo -ne "Use these IPs for deployment? (y/n): "
    read -r IP_CONFIRM
    
    if [[ "$IP_CONFIRM" =~ ^[Yy]$ ]]; then
        AUTO_PUBLIC_IP=$DETECTED_PUBLIC
        AUTO_LOCAL_IP=$DETECTED_LOCAL
    else
        echo -ne "Enter Public IP: ${WARNING}"
        read -r AUTO_PUBLIC_IP
        echo -e "${RESET}"
        echo -ne "Enter Local IP: ${WARNING}"
        read -r AUTO_LOCAL_IP
        echo -e "${RESET}"
    fi

    # Conflict Check
    echo -e "\n${ACCENT}>> Checking for existing Matrix resources...${RESET}"
    
    local stack_dir=""
    if [ -d "/opt/stacks/matrix-stack" ]; then
        stack_dir="/opt/stacks/matrix-stack"
    elif [ -d "$(pwd)/matrix-stack" ]; then
        stack_dir="$(pwd)/matrix-stack"
    fi
    
    local matrix_patterns=("^synapse$" "^synapse-db$" "^synapse-admin$" "^coturn$" "^livekit$" "^element-call$")
    local found_containers=false
    local found_volumes=false
    local found_networks=false
    local containers_list=()
    local volumes_list=()
    local networks_list=()
    
    for pattern in "${matrix_patterns[@]}"; do
        while IFS= read -r container; do
            if [ -n "$container" ]; then
                local compose_project=$(docker inspect "$container" --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null)
                if [ -n "$compose_project" ] && [[ "$compose_project" == *"matrix"* ]]; then
                    found_containers=true
                    containers_list+=("$container")
                elif [[ "$container" =~ ^(synapse|synapse-db|synapse-admin|coturn|livekit|element-call)$ ]]; then
                    found_containers=true
                    containers_list+=("$container")
                fi
            fi
        done < <(docker ps -a --filter "name=$pattern" --format "{{.Names}}" 2>/dev/null)
    done
    
    local volume_patterns=("synapse" "postgres" "coturn" "livekit" "matrix" "element-call")
    for pattern in "${volume_patterns[@]}"; do
        while IFS= read -r volume; do
            if [ -n "$volume" ] && [[ "$volume" == *"$pattern"* ]]; then
                found_volumes=true
                volumes_list+=("$volume")
            fi
        done < <(docker volume ls --filter "name=$pattern" --format "{{.Name}}" 2>/dev/null)
    done
    
    while IFS= read -r network; do
        if [ -n "$network" ] && [ "$network" == "matrix-net" ]; then
            local in_use=$(docker network inspect "$network" --format '{{json .Containers}}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
            if [ "$in_use" -gt 0 ]; then
                local all_matrix=true
                local containers=$(docker network inspect "$network" --format '{{json .Containers}}' 2>/dev/null | jq -r '.[] | .Name' 2>/dev/null)
                for cont in $containers; do
                    if [[ ! "$cont" =~ ^(synapse|synapse-db|synapse-admin|coturn|livekit|element-call)$ ]]; then
                        all_matrix=false
                        break
                    fi
                done
                if [ "$all_matrix" = true ]; then
                    found_networks=true
                    networks_list+=("$network")
                fi
            else
                found_networks=true
                networks_list+=("$network")
            fi
        fi
    done < <(docker network ls --filter "name=matrix-net" --format "{{.Name}}" 2>/dev/null)
    
    if [ "$found_containers" = true ] || [ "$found_volumes" = true ] || [ "$found_networks" = true ] || [ -n "$stack_dir" ]; then
        echo -e "   ${ERROR}[!] Found existing Matrix resources:${RESET}"
        
        if [ "$found_containers" = true ]; then
            echo -e "   • Containers: ${CONTAINER_NAME}${containers_list[*]}${RESET}"
        fi
        if [ "$found_volumes" = true ]; then
            echo -e "   • Volumes: ${INFO}${volumes_list[*]}${RESET}"
        fi
        if [ "$found_networks" = true ]; then
            echo -e "   • Networks: ${NETWORK_NAME}${networks_list[*]}${RESET}"
        fi
        if [ -n "$stack_dir" ]; then
            if [[ "$stack_dir" == "/opt/stacks/"* ]]; then
                echo -e "   • Stack Directory: ${INFO}$stack_dir${RESET} ${WARNING}(Dockge Stack)${RESET}"
            else
                echo -e "   • Stack Directory: ${INFO}$stack_dir${RESET}"
            fi
        fi
        
        echo ""
        echo -ne "Stop and remove these resources to avoid conflicts? (y/n): "
        read -r CLEANUP_CONFIRM
        
        if [[ "$CLEANUP_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "   ${ACCENT}>> Cleaning up resources...${RESET}"
            for container in "${containers_list[@]}"; do
                docker stop "$container" >/dev/null 2>&1 && echo -e "      • Stopped: ${CONTAINER_NAME}$container${RESET}"
                docker rm "$container" >/dev/null 2>&1 && echo -e "      • ${REMOVED}Removed:${RESET} ${CONTAINER_NAME}$container${RESET}"
            done
            for volume in "${volumes_list[@]}"; do
                docker volume rm "$volume" >/dev/null 2>&1 && echo -e "      • ${REMOVED}Removed volume:${RESET} ${INFO}$volume${RESET}"
            done
            for network in "${networks_list[@]}"; do
                docker network rm "$network" >/dev/null 2>&1 && echo -e "      • ${REMOVED}Removed network:${RESET} ${NETWORK_NAME}$network${RESET}"
            done
            if [ -n "$stack_dir" ] && [ -d "$stack_dir" ]; then
                rm -rf "$stack_dir" && echo -e "      • ${REMOVED}Removed directory:${RESET} ${INFO}$stack_dir${RESET}"
            fi
            echo -e "   ${SUCCESS}✓ Cleanup completed${RESET}"
        fi
    else
        echo -e "   ${SUCCESS}✓ No conflicting Matrix resources found${RESET}"
    fi

    # Deployment Path
    echo -e "\n${ACCENT}>> Selecting deployment path...${RESET}"
    CUR_DIR=$(pwd)

    if [ "$DOCKGE_FOUND" = true ]; then
        echo -e "   ${CHOICE_COLOR}1)${RESET} ${SUCCESS}Dockge Path (Recommended):${RESET} /opt/stacks/matrix-stack"
        echo -e "   ${CHOICE_COLOR}2)${RESET} Current Directory:         $CUR_DIR/matrix-stack"
        echo -e "   ${CHOICE_COLOR}3)${RESET} Custom Path"
        echo -ne "Selection (1/2/3): "
        read -r PATH_SELECT
        case $PATH_SELECT in
            1) TARGET_DIR="/opt/stacks/matrix-stack" ;;
            2) TARGET_DIR="$CUR_DIR/matrix-stack" ;;
            *) echo -ne "Enter Full Path: ${WARNING}"; read -r TARGET_DIR; echo -e "${RESET}" ;;
        esac
    elif [ "$DOCKER_READY" = true ]; then
        echo -e "   ${CHOICE_COLOR}1)${RESET} ${SUCCESS}Current Directory (Recommended):${RESET} $CUR_DIR/matrix-stack"
        echo -e "   ${CHOICE_COLOR}2)${RESET} Custom Path"
        echo -ne "Selection (1/2): "
        read -r PATH_SELECT
        if [[ "$PATH_SELECT" == "1" ]]; then
            TARGET_DIR="$CUR_DIR/matrix-stack"
        else
            echo -ne "Enter Full Path: ${WARNING}"; read -r TARGET_DIR; echo -e "${RESET}"
        fi
    else
        echo -ne "Enter Deployment Path (Default /opt/matrix-stack): ${WARNING}"
        read -r TARGET_DIR
        echo -e "${RESET}"
        TARGET_DIR=${TARGET_DIR:-/opt/matrix-stack}
    fi

    if [ -d "$TARGET_DIR" ] && [ "$TARGET_DIR" != "$stack_dir" ]; then
        if [[ "$TARGET_DIR" == "/opt/stacks/"* ]]; then
            echo -e "\n${ERROR}[!] Existing Stack detected at $TARGET_DIR (Dockge Stack)${RESET}"
        elif [[ "$TARGET_DIR" == "/root/"* ]]; then
            echo -e "\n${ERROR}[!] Existing Stack detected at $TARGET_DIR (Root Path)${RESET}"
        else
            echo -e "\n${ERROR}[!] Existing Stack detected at $TARGET_DIR${RESET}"
        fi
        
        echo -ne "Completely WIPE and overwrite everything in this directory? (y/n): "
        read -r OVERWRITE
        if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
            if [ -f "$TARGET_DIR/compose.yaml" ] || [ -f "$TARGET_DIR/docker-compose.yaml" ]; then
                cd "$TARGET_DIR" && docker compose down -v --remove-orphans > /dev/null 2>&1
            fi
            rm -rf "$TARGET_DIR"
            echo -e "   ${SUCCESS}✓ Directory wiped clean${RESET}"
        else
            echo -e "${WARNING}Exiting to protect data.${RESET}"; exit 0
        fi
    fi

    mkdir -p "$TARGET_DIR/synapse" "$TARGET_DIR/postgres_data" "$TARGET_DIR/coturn" "$TARGET_DIR/livekit" "$TARGET_DIR/element-call"

    # Service Configuration
    echo -e "\n${ACCENT}>> Configuring services...${RESET}"
    
    echo -ne "Base Domain (e.g., example.com): ${WARNING}"
    read -r DOMAIN
    echo -e "${RESET}"
    echo -ne "Matrix Subdomain (e.g., matrix): ${WARNING}"
    read -r SUB_MATRIX
    echo -e "${RESET}"
    echo -ne "Element Call Subdomain (e.g., call): ${WARNING}"
    read -r SUB_CALL
    echo -e "${RESET}"
    SUB_CALL=${SUB_CALL:-call}
    
    while read -r -t 0; do read -r; done
    
    echo -e "\n${ACCENT}Server Name Configuration:${RESET}"
    echo -e "   This will appear in user IDs like ${USER_ID_EXAMPLE}@username:servername${RESET}"
    echo -e "   ${CHOICE_COLOR}1)${RESET} Use base domain (${INFO}$DOMAIN${RESET})"
    echo -e "   ${CHOICE_COLOR}2)${RESET} Use full subdomain (${INFO}$SUB_MATRIX.$DOMAIN${RESET})"
    echo -e "   ${CHOICE_COLOR}3)${RESET} Use custom server name (e.g., myserver, matrix.example.com)"
    echo -ne "Selection (1/2/3): "
    read -r SERVERNAME_SELECT
    
    case $SERVERNAME_SELECT in
        1) SERVER_NAME="$DOMAIN"
           echo -e "   ${INFO}User IDs will be: ${USER_ID_VALUE}@username:${DOMAIN}${RESET}" ;;
        2) SERVER_NAME="$SUB_MATRIX.$DOMAIN"
           echo -e "   ${INFO}User IDs will be: ${USER_ID_VALUE}@username:${SUB_MATRIX}.${DOMAIN}${RESET}" ;;
        3) echo -ne "Enter custom server name: ${WARNING}"
           read -r SERVER_NAME
           echo -e "${RESET}   ${INFO}User IDs will be: ${USER_ID_VALUE}@username:${SERVER_NAME}${RESET}" ;;
    esac
    
    echo -ne "Admin Username (e.g., admin): ${WARNING}"
    read -r ADMIN_USER
    echo -e "${RESET}"
    
    # Registration Configuration
    echo -e "\n${ACCENT}Registration Configuration:${RESET}"
    echo -e "   ${WARNING}Allow new users to register without admin approval?${RESET}"
    echo -e "   • ${SUCCESS}Enable registration (y):${RESET} Users can create accounts freely"
    echo -e "   • ${ERROR}Disable registration (n):${RESET} Only admin can create users (recommended)"
    echo -ne "Allow public registration? (default: n): "
    read -r ALLOW_REGISTRATION
    ALLOW_REGISTRATION=${ALLOW_REGISTRATION:-n}
    
    if [[ "$ALLOW_REGISTRATION" =~ ^[Yy]$ ]]; then
        ENABLE_REGISTRATION="true"
        echo -e "\n${ACCENT}Email Verification Configuration:${RESET}"
        echo -e "   ${WARNING}To prevent spam and abuse, you can require email verification for new registrations.${RESET}"
        echo -e "   • ${SUCCESS}Enable email verification (y):${RESET} Users must verify email before they can log in"
        echo -e "   • ${ERROR}Disable email verification (n):${RESET} Users can register and use immediately (less secure)"
        echo -ne "Require email verification for new users? (default: y): "
        read -r REQUIRE_EMAIL_VERIFICATION
        REQUIRE_EMAIL_VERIFICATION=${REQUIRE_EMAIL_VERIFICATION:-y}
        
        if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then
            ENABLE_REGISTRATION_WITHOUT_VERIFICATION="false"
            echo -e "   ${SUCCESS}✓ Email verification enabled - users must verify email address${RESET}"
            echo -e "   ${INFO}ℹ  Note: You'll need to configure email settings in homeserver.yaml later${RESET}"
        else
            ENABLE_REGISTRATION_WITHOUT_VERIFICATION="true"
            echo -e "   ${WARNING}⚠️  Warning: Public registration enabled without verification - consider adding captcha${RESET}"
        fi
    else
        ENABLE_REGISTRATION="false"
        ENABLE_REGISTRATION_WITHOUT_VERIFICATION="false"
        echo -e "   ${REGISTRATION_DISABLED}✓ Registration disabled - admin will create users manually${RESET}"
    fi
    
    echo -e "\n${ACCENT}Reverse Proxy Selection:${RESET}"
    echo -e "   ${CHOICE_COLOR}1)${RESET} Nginx Proxy Manager (NPM)"
    echo -e "   ${CHOICE_COLOR}2)${RESET} Nginx Proxy Manager Plus (NPM Plus)"
    echo -e "   ${CHOICE_COLOR}3)${RESET} Caddy"
    echo -e "   ${CHOICE_COLOR}4)${RESET} Traefik"
    echo -e "   ${CHOICE_COLOR}5)${RESET} Cloudflare Tunnel"
    echo -e "   ${CHOICE_COLOR}6)${RESET} Manual Setup"
    echo -ne "Selection (1-6): "
    read -r PROXY_SELECT
    
    case $PROXY_SELECT in
        1) PROXY_TYPE="npm" ;;
        2) PROXY_TYPE="npmplus" ;;
        3) PROXY_TYPE="caddy" ;;
        4) PROXY_TYPE="traefik" ;;
        5) PROXY_TYPE="cloudflare" ;;
        *) PROXY_TYPE="manual" ;;
    esac
    
    echo -e "\n${ACCENT}Admin Password Options:${RESET}"
    echo -e "   ${CHOICE_COLOR}1)${RESET} Auto-generate strong password (Recommended)"
    echo -e "   ${CHOICE_COLOR}2)${RESET} Enter custom password"
    echo -ne "Selection (1/2): "
    read -r PASS_SELECT
    
    if [[ "$PASS_SELECT" == "2" ]]; then
        while true; do
            echo -ne "Enter admin password: ${WARNING}"
            read -s ADMIN_PASS
            echo -e "${RESET}"
            echo -ne "Confirm password: ${WARNING}"
            read -s ADMIN_PASS_CONFIRM
            echo -e "${RESET}"
            if [ "$ADMIN_PASS" == "$ADMIN_PASS_CONFIRM" ] && [ ${#ADMIN_PASS} -ge 8 ]; then
                break
            else
                echo -e "${ERROR}Passwords don't match or are too short (min 8 chars). Try again.${RESET}"
            fi
        done
        PASS_IS_CUSTOM=true
    else
        ADMIN_PASS=$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        PASS_IS_CUSTOM=false
    fi

    DB_PASS=$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    TURN_SECRET=$(openssl rand -hex 32)
    REG_SECRET=$(openssl rand -hex 32)
    LK_API_KEY=$(openssl rand -hex 16)
    LK_API_SECRET=$(openssl rand -hex 32)

    # TURN LAN Configuration
    echo -e "\n${ACCENT}>> TURN Server LAN Access Configuration${RESET}"
    echo -e "   ${INFO}The TURN server can be configured to allow or block connections from:${RESET}"
    echo -e "   • Local network ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)"
    echo -e "   • Localhost (127.0.0.0/8)"
    echo -e ""
    echo -e "   ${WARNING}⚠️  Security Note:${RESET}"
    echo -e "   • ${SUCCESS}Allow LAN (y):${RESET} Useful for local testing or connecting from another computer on the same LAN"
    echo -e "   • ${ERROR}Block LAN (n):${RESET} More secure for production, prevents external users from"
    echo -e "                    accessing your local network through the TURN server"
    echo ""
    echo -ne "Allow connections from local networks? (default: n): "
    read -r TURN_LAN_ACCESS
    TURN_LAN_ACCESS=${TURN_LAN_ACCESS:-n}
    
    # Display TURN LAN access choice with appropriate color
    if [[ "$TURN_LAN_ACCESS" =~ ^[Yy]$ ]]; then
        echo -e "   ${SUCCESS}✓ TURN LAN access: ENABLED${RESET} (local networks accessible)"
    else
        echo -e "   ${ERROR}✓ TURN LAN access: DISABLED${RESET} (secure - production recommended)"
    fi

    # Generate Coturn Config
    echo -e "\n${ACCENT}>> Generating Coturn configuration...${RESET}"
    cat > "$TARGET_DIR/coturn/turnserver.conf" << 'COTURNEOF'
# Coturn TURN/STUN Server Configuration
listening-ip=0.0.0.0
relay-ip=REPLACE_LOCAL_IP
external-ip=REPLACE_PUBLIC_IP
listening-port=3478
min-port=49152
max-port=49252
use-auth-secret
static-auth-secret=REPLACE_TURN_SECRET
realm=turn.REPLACE_DOMAIN
verbose
log-file=stdout
no-multicast-peers
no-cli
no-loopback-peers
no-tcp-relay
COTURNEOF

    if [[ "$TURN_LAN_ACCESS" =~ ^[Yy]$ ]]; then
        cat >> "$TARGET_DIR/coturn/turnserver.conf" << 'COTURNLANEOF'
# LAN access is ENABLED - following rules are commented out
# denied-peer-ip=0.0.0.0-0.255.255.255
# denied-peer-ip=10.0.0.0-10.255.255.255
# denied-peer-ip=172.16.0.0-172.31.255.255
# denied-peer-ip=192.168.0.0-192.168.255.255
COTURNLANEOF
    else
        cat >> "$TARGET_DIR/coturn/turnserver.conf" << 'COTURNLANEOF'
# LAN access is DISABLED (recommended for production)
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
COTURNLANEOF
    fi

    cat >> "$TARGET_DIR/coturn/turnserver.conf" << 'COTURNEOF2'
total-quota=100
bps-capacity=0
stale-nonce=600
COTURNEOF2

    sed -i "s/REPLACE_LOCAL_IP/$AUTO_LOCAL_IP/g" "$TARGET_DIR/coturn/turnserver.conf"
    sed -i "s/REPLACE_PUBLIC_IP/$AUTO_PUBLIC_IP/g" "$TARGET_DIR/coturn/turnserver.conf"
    sed -i "s/REPLACE_TURN_SECRET/$TURN_SECRET/g" "$TARGET_DIR/coturn/turnserver.conf"
    sed -i "s/REPLACE_DOMAIN/$DOMAIN/g" "$TARGET_DIR/coturn/turnserver.conf"
    
    echo -e "   ${SUCCESS}✓ Coturn config created${RESET}"

    # Generate LiveKit Config
    echo -e "\n${ACCENT}>> Generating LiveKit configuration...${RESET}"
    cat > "$TARGET_DIR/livekit/livekit.yaml" << 'LIVEKITEOF'
# LiveKit Server Configuration
port: 7880
bind_addresses:
  - 0.0.0.0

rtc:
  port_range_start: 50000
  port_range_end: 50050
  use_external_ip: true
  udp_port: 7882

keys:
  REPLACE_LK_API_KEY: REPLACE_LK_API_SECRET

logging:
  level: info
  json: false

room:
  auto_create: true
  empty_timeout: 300
  max_participants: 100
  max_video_publishers: 50
  
limit:
  num_tracks: 10
  bytes_per_sec: 10000000

video:
  dynacast: false

turn:
  enabled: true
  servers:
    - host: turn.REPLACE_DOMAIN
      port: 3478
      protocol: udp
      username: livekit
      credential: REPLACE_TURN_SECRET
    - host: turn.REPLACE_DOMAIN
      port: 3478
      protocol: tcp
      username: livekit
      credential: REPLACE_TURN_SECRET
LIVEKITEOF

    sed -i "s/REPLACE_LK_API_KEY/$LK_API_KEY/g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s/REPLACE_LK_API_SECRET/$LK_API_SECRET/g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s/REPLACE_TURN_SECRET/$TURN_SECRET/g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s/REPLACE_DOMAIN/$DOMAIN/g" "$TARGET_DIR/livekit/livekit.yaml"
    
    echo -e "   ${SUCCESS}✓ LiveKit config created${RESET}"

    # Generate Element Call Config
    echo -e "\n${ACCENT}>> Generating Element Call configuration...${RESET}"
    cat > "$TARGET_DIR/element-call/config.json" << 'ELEMENTCALLEOF'
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://REPLACE_MATRIX_DOMAIN",
            "server_name": "REPLACE_SERVER_NAME"
        }
    },
    "features": {
        "feature_group_calls": true,
        "feature_video_rooms": true
    }
}
ELEMENTCALLEOF

    sed -i "s/REPLACE_MATRIX_DOMAIN/$SUB_MATRIX.$DOMAIN/g" "$TARGET_DIR/element-call/config.json"
    sed -i "s/REPLACE_SERVER_NAME/$SERVER_NAME/g" "$TARGET_DIR/element-call/config.json"
    echo -e "   ${SUCCESS}✓ Element Call config created${RESET}"

    # Generate Docker Compose (with Element Call)
    echo -e "\n${ACCENT}>> Generating Docker Compose configuration...${RESET}"
    cat > "$TARGET_DIR/compose.yaml" << 'COMPOSEEOF'
services:
  postgres:
    container_name: synapse-db
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: REPLACE_DB_PASS
      POSTGRES_DB: synapse
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes: [ "./postgres_data:/var/lib/postgresql/data" ]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

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
    labels:
      com.docker.compose.project: "matrix-stack"

  synapse-admin:
    container_name: synapse-admin
    image: awesometechnologies/synapse-admin:latest
    restart: unless-stopped
    ports: [ "8009:80" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  coturn:
    container_name: coturn
    image: coturn/coturn:latest
    restart: unless-stopped
    ports: ["3478:3478/tcp", "3478:3478/udp", "49152-49252:49152-49252/udp"]
    volumes: [ "./coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  livekit:
    container_name: livekit
    image: livekit/livekit-server:latest
    restart: unless-stopped
    command: --config /etc/livekit.yaml
    volumes: [ "./livekit/livekit.yaml:/etc/livekit.yaml:ro" ]
    ports: [ "7880:7880", "7882:7882/udp", "50000-50050:50000-50050/udp" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  element-call:
    container_name: element-call
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes: [ "./element-call/config.json:/app/config.json:ro" ]
    ports: [ "8080:80" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

networks:
  matrix-net:
    name: matrix-net
    labels:
      com.docker.compose.project: "matrix-stack"
COMPOSEEOF

    sed -i "s/REPLACE_DB_PASS/$DB_PASS/g" "$TARGET_DIR/compose.yaml"
    echo -e "   ${SUCCESS}✓ Docker Compose config created${RESET}"

    # Generate Synapse Config
    echo -e "\n${ACCENT}>> Generating Synapse configuration...${RESET}"
    docker run --rm -v "$TARGET_DIR/synapse:/data" -e SYNAPSE_SERVER_NAME="$SERVER_NAME" -e SYNAPSE_REPORT_STATS=yes matrixdotorg/synapse:latest generate > /dev/null 2>&1
    
    cat >> "$TARGET_DIR/synapse/homeserver.yaml" << SYNAPSEEOF

# Suppress key server warning
suppress_key_server_warning: true

# Database Configuration (PostgreSQL)
database:
  name: psycopg2
  args:
    user: synapse
    password: $DB_PASS
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10

# TURN/STUN Configuration
turn_uris:
  - "turn:turn.$DOMAIN:3478?transport=udp"
  - "turn:turn.$DOMAIN:3478?transport=tcp"
turn_shared_secret: "$TURN_SECRET"
turn_user_lifetime: 86400000
turn_allow_guests: false

# Registration
enable_registration: $ENABLE_REGISTRATION
enable_registration_without_verification: $ENABLE_REGISTRATION_WITHOUT_VERIFICATION
registration_shared_secret: "$REG_SECRET"

# Rate limiting
rc_message:
  per_second: 10
  burst_count: 50
rc_registration:
  per_second: 0.17
  burst_count: 3
rc_login:
  address:
    per_second: 0.17
    burst_count: 3
  account:
    per_second: 0.17
    burst_count: 3

# Media
max_upload_size: 50M
max_image_pixels: 32M

# URL Preview
url_preview_enabled: true
url_preview_ip_range_blacklist:
  - '127.0.0.0/8'
  - '10.0.0.0/8'
  - '172.16.0.0/12'
  - '192.168.0.0/16'
  - '100.64.0.0/10'
  - '169.254.0.0/16'

# Metrics
enable_metrics: false
SYNAPSEEOF
    
    chown -R 991:991 "$TARGET_DIR/synapse"
    echo -e "   ${SUCCESS}✓ Synapse homeserver.yaml configured${RESET}"

    # Deploy Stack
    echo -e "\n${SUCCESS}>> Launching Stack...${RESET}"
    cd "$TARGET_DIR" && docker compose up -d

    echo -ne "\n${WARNING}>> Waiting for Synapse readiness (2s Polling)...${RESET}"
    TRIES=0
    until curl -sL --fail http://localhost:8008 2>/dev/null | grep -qi "It works"; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 150 ]]; then
            echo -e "\n\n${ERROR}[!] ERROR: Synapse failed to start.${RESET}"
            echo -e "${INFO}Check logs with: docker logs -f synapse${RESET}"
            exit 1
        fi
    done

    echo -e "\n${SUCCESS}>> Synapse is ONLINE. Registering Admin user...${RESET}"
    docker exec synapse register_new_matrix_user -c /data/homeserver.yaml -u "$ADMIN_USER" -p "$ADMIN_PASS" --admin http://localhost:8008
    
    # Proxy Guides
    if [[ "$PROXY_TYPE" == "npm" ]] || [[ "$PROXY_TYPE" == "npmplus" ]]; then
        echo -e "\n${ACCENT}Would you like guided setup for Nginx Proxy Manager? (y/n):${RESET} "
        read -r SHOW_GUIDE
        if [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]]; then
            clear
            echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${BANNER}│                 NGINX PROXY MANAGER SETUP GUIDE              │${RESET}"
            echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
            
            echo -e "\n${ACCENT}Create Proxy Host in NPM:${RESET}"
            echo -e "   Domain: ${INFO}$SUB_MATRIX.$DOMAIN${RESET}"
            echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:8008${RESET}"
            echo -e "   Enable: Websockets, Block Exploits, SSL (Force HTTPS)\n"
            
            echo -e "${ACCENT}Advanced Tab - Copy this:${RESET}\n"
            cat << 'NPMCONF'
client_max_body_size 50M;
proxy_read_timeout 600s;
proxy_send_timeout 600s;

location /.well-known/matrix/server {
    return 200 '{"m.server": "YOURDOMAIN:443"}';
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
}

location /.well-known/matrix/client {
    return 200 '{"m.homeserver": {"base_url": "https://YOURDOMAIN"}}';
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
}
NPMCONF
            
            echo -e "\n${WARNING}⚠️  Replace YOURDOMAIN with: ${SUCCESS}$SUB_MATRIX.$DOMAIN${RESET}\n"
            echo -e "${WARNING}Press ENTER when complete...${RESET}"
            read -r
            
            clear
            echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${BANNER}│                  NPM SETUP - LIVEKIT PROXY                   │${RESET}"
            echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
            
            echo -e "\n${ACCENT}Create Proxy Host in NPM:${RESET}"
            echo -e "   Domain: ${INFO}livekit.$DOMAIN${RESET}"
            echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:7880${RESET}"
            echo -e "   Enable: Websockets, Block Exploits, SSL (Force HTTPS)\n"
            
            echo -e "${ACCENT}Advanced Tab - Copy this:${RESET}\n"
            cat << 'LKCONF'
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 86400;
proxy_send_timeout 86400;
LKCONF
            
            echo -e "\n${SUCCESS}✓ No replacements needed${RESET}"
            echo -e "\n${WARNING}Press ENTER when complete...${RESET}"
            read -r
            
            clear
            echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${BANNER}│                NPM SETUP - ELEMENT CALL                      │${RESET}"
            echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
            
            echo -e "\n${ACCENT}Create Proxy Host in NPM:${RESET}"
            echo -e "   Domain: ${INFO}$SUB_CALL.$DOMAIN${RESET}"
            echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:8080${RESET}"
            echo -e "   Enable: Websockets, Block Exploits, SSL (Force HTTPS)\n"
            
            echo -e "\n${SUCCESS}✓ No advanced configuration needed${RESET}"
            echo -e "\n${WARNING}Press ENTER when complete...${RESET}"
            read -r
        fi
    elif [[ "$PROXY_TYPE" == "caddy" ]]; then
        echo -e "\n${ACCENT}Would you like guided setup for Caddy? (y/n):${RESET} "
        read -r SHOW_GUIDE
        if [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]]; then
            clear
            echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${BANNER}│                      CADDY SETUP GUIDE                       │${RESET}"
            echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
            
            echo -e "\n${ACCENT}Caddyfile Configuration (${INFO}/etc/caddy/Caddyfile${ACCENT}):${RESET}\n"
            cat << CADDYCONF
$SUB_MATRIX.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8008
    header {
        Access-Control-Allow-Origin *
    }
    @wellknown_server {
        path /.well-known/matrix/server
    }
    @wellknown_client {
        path /.well-known/matrix/client
    }
    handle @wellknown_server {
        resp_header Content-Type application/json
        respond '{"m.server": "$SUB_MATRIX.$DOMAIN:443"}'
    }
    handle @wellknown_client {
        resp_header Content-Type application/json
        respond '{"m.homeserver": {"base_url": "https://$SUB_MATRIX.$DOMAIN"}}'
    }
}

livekit.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:7880
    header {
        Access-Control-Allow-Origin *
    }
}

$SUB_CALL.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8080
    header {
        Access-Control-Allow-Origin *
    }
}

turn.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:3478
}
CADDYCONF
            
            echo -e "\n${ACCENT}After adding the configuration, reload Caddy:${RESET}"
            echo -e "${INFO}sudo caddy reload${RESET}\n"
            
            echo -e "${WARNING}Press ENTER to continue...${RESET}"
            read -r
        fi
    elif [[ "$PROXY_TYPE" == "traefik" ]]; then
        echo -e "\n${ACCENT}Would you like guided setup for Traefik? (y/n):${RESET} "
        read -r SHOW_GUIDE
        if [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]]; then
            clear
            echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${BANNER}│                     TRAEFIK SETUP GUIDE                      │${RESET}"
            echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
            
            echo -e "\n${ACCENT}Create dynamic configuration (${INFO}/opt/traefik/dynamic.yml${ACCENT}):${RESET}\n"
            cat << TRAEFIKDYNAMIC
http:
  routers:
    matrix:
      rule: "Host(\`$SUB_MATRIX.$DOMAIN\`)"
      service: matrix
      tls:
        certResolver: letsencrypt
      middlewares:
        - matrix-headers
    livekit:
      rule: "Host(\`livekit.$DOMAIN\`)"
      service: livekit
      tls:
        certResolver: letsencrypt
    element-call:
      rule: "Host(\`$SUB_CALL.$DOMAIN\`)"
      service: element-call
      tls:
        certResolver: letsencrypt

  services:
    matrix:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8008"
    livekit:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:7880"
    element-call:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8080"

  middlewares:
    matrix-headers:
      headers:
        customResponseHeaders:
          Access-Control-Allow-Origin: "*"
TRAEFIKDYNAMIC
            
            echo -e "\n${ACCENT}After adding the configuration, restart Traefik:${RESET}"
            echo -e "${INFO}docker restart traefik${RESET}\n"
            
            echo -e "${WARNING}Press ENTER to continue...${RESET}"
            read -r
        fi
    elif [[ "$PROXY_TYPE" == "cloudflare" ]]; then
        echo -e "\n${ACCENT}Would you like guided setup for Cloudflare Tunnel? (y/n):${RESET} "
        read -r SHOW_GUIDE
        if [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]]; then
            clear
            echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${BANNER}│                CLOUDFLARE TUNNEL SETUP GUIDE                 │${RESET}"
            echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
            
            echo -e "\n${ACCENT}Update tunnel config (${INFO}~/.cloudflared/config.yml${ACCENT}):${RESET}\n"
            cat << CFCONF
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: $SUB_MATRIX.$DOMAIN
    service: http://$AUTO_LOCAL_IP:8008
  - hostname: livekit.$DOMAIN
    service: http://$AUTO_LOCAL_IP:7880
  - hostname: $SUB_CALL.$DOMAIN
    service: http://$AUTO_LOCAL_IP:8080
  - hostname: turn.$DOMAIN
    service: http://$AUTO_LOCAL_IP:3478
  - service: http_status:404
CFCONF
            
            echo -e "\n${ACCENT}Restart tunnel:${RESET}"
            echo -e "${INFO}systemctl restart cloudflared${RESET}\n"
            
            echo -e "${WARNING}Press ENTER to continue...${RESET}"
            read -r
        fi
    fi

    draw_footer
}

# Footer
draw_footer() {
    echo -e "\n${SUCCESS}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${SUCCESS}│                      DEPLOYMENT COMPLETE                     │${RESET}"
    echo -e "${SUCCESS}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    echo -e "\n${ACCENT}═══════════════════════ ACCESS CREDENTIALS ═══════════════════════${RESET}"
    echo -e "   ${ACCESS_NAME}Matrix Server:${RESET}    ${ACCESS_VALUE}${SERVER_NAME}${RESET}"
    echo -e "   ${ACCESS_NAME}Admin User:${RESET}       ${ACCESS_VALUE}${ADMIN_USER}${RESET}"
    if [ "$PASS_IS_CUSTOM" = true ]; then
        echo -e "   ${ACCESS_NAME}Admin Pass:${RESET}       ${ACCESS_VALUE}[Your custom password]${RESET}"
    else
        echo -e "   ${ACCESS_NAME}Admin Pass:${RESET}       ${ACCESS_VALUE}${ADMIN_PASS}${RESET}"
    fi
    echo -e "   ${ACCESS_NAME}Admin Panel:${RESET}      ${ACCESS_VALUE}http://$AUTO_LOCAL_IP:8009${RESET}"
    echo -e "   ${ACCESS_NAME}Matrix API (LAN):${RESET} ${ACCESS_VALUE}http://$AUTO_LOCAL_IP:8008${RESET}"
    echo -e "   ${ACCESS_NAME}Matrix API (WAN):${RESET} ${ACCESS_VALUE}https://$SUB_MATRIX.$DOMAIN${RESET}"
    echo -e "   ${ACCESS_NAME}Element Call:${RESET}     ${ACCESS_VALUE}http://$AUTO_LOCAL_IP:8080${RESET} (LAN) / https://$SUB_CALL.$DOMAIN${RESET} (WAN)"

    echo -e "\n${ACCENT}═══════════════════════ INTERNAL SECRETS ════════════════════════${RESET}"
    echo -e "   ${SECRET_NAME}Postgres Pass:${RESET}   ${SECRET_VALUE}${DB_PASS}${RESET}"
    echo -e "   ${SECRET_NAME}Shared Secret:${RESET}   ${SECRET_VALUE}${REG_SECRET}${RESET}"
    echo -e "   ${SECRET_NAME}TURN Secret:${RESET}     ${SECRET_VALUE}${TURN_SECRET}${RESET}"
    echo -e "   ${SECRET_NAME}Livekit API Key:${RESET} ${SECRET_VALUE}${LK_API_KEY}${RESET}"
    echo -e "   ${SECRET_NAME}Livekit Secret:${RESET}  ${SECRET_VALUE}${LK_API_SECRET}${RESET}"

    echo -e "\n${ACCENT}═════════════════════════ DNS RECORDS ═══════════════════════════${RESET}"
    
    if [[ "$PROXY_TYPE" == "cloudflare" ]]; then
        MATRIX_STATUS="DNS ONLY"
        LIVEKIT_STATUS="DNS ONLY"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="DNS ONLY"
    elif [[ "$PROXY_TYPE" == "npm" ]] || [[ "$PROXY_TYPE" == "npmplus" ]] || [[ "$PROXY_TYPE" == "caddy" ]] || [[ "$PROXY_TYPE" == "traefik" ]]; then
        MATRIX_STATUS="PROXIED"
        LIVEKIT_STATUS="PROXIED"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="PROXIED"
    else
        MATRIX_STATUS="DNS ONLY"
        LIVEKIT_STATUS="DNS ONLY"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="DNS ONLY"
    fi
    
    echo -e "   ┌─────────────────┬───────────┬─────────────────┬─────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ %-15s │ %-15s │\n" "HOSTNAME" "TYPE" "VALUE" "STATUS"
    echo -e "   ├─────────────────┼───────────┼─────────────────┼─────────────────┤"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_MATRIX" "A" "$AUTO_PUBLIC_IP"
    if [[ "$MATRIX_STATUS" == "PROXIED" ]]; then
        echo -e "${DNS_STATUS_PROXIED}${MATRIX_STATUS}${RESET} │"
    else
        echo -e "${MATRIX_STATUS} │"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "turn" "A" "$AUTO_PUBLIC_IP"
    if [[ "$TURN_STATUS" == "PROXIED" ]]; then
        echo -e "${DNS_STATUS_PROXIED}${TURN_STATUS}${RESET}  │"
    else
        echo -e "${TURN_STATUS} │"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "livekit" "A" "$AUTO_PUBLIC_IP"
    if [[ "$LIVEKIT_STATUS" == "PROXIED" ]]; then
        echo -e "${DNS_STATUS_PROXIED}${LIVEKIT_STATUS}${RESET}  │"
    else
        echo -e "${LIVEKIT_STATUS} │"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_CALL" "A" "$AUTO_PUBLIC_IP"
    if [[ "$ELEMENT_CALL_STATUS" == "PROXIED" ]]; then
        echo -e "${DNS_STATUS_PROXIED}${ELEMENT_CALL_STATUS}${RESET}  │"
    else
        echo -e "${ELEMENT_CALL_STATUS} │"
    fi
    echo -e "   └─────────────────┴───────────┴─────────────────┴─────────────────┘"

    echo -e "\n${ACCENT}═══════════════════════ CONFIGURATION FILES ═══════════════════════${RESET}"
    echo -e "   ${INFO}• Coturn:${RESET}   ${CONFIG_PATH}${TARGET_DIR}/coturn/turnserver.conf${RESET}"
    echo -e "   ${INFO}• LiveKit:${RESET}  ${CONFIG_PATH}${TARGET_DIR}/livekit/livekit.yaml${RESET}"
    echo -e "   ${INFO}• Synapse:${RESET}  ${CONFIG_PATH}${TARGET_DIR}/synapse/homeserver.yaml${RESET}"
    echo -e "   ${INFO}• Element Call:${RESET} ${CONFIG_PATH}${TARGET_DIR}/element-call/config.json${RESET}"

    echo -e "\n${ACCENT}════════════════════════ IMPORTANT NOTES ═════════════════════════${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} Multiple simultaneous screenshares are now supported${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} LiveKit configured with increased track limits${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} Element Call is available for video conferencing${RESET}"
    echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Test federation: https://federationtester.matrix.org${RESET}"
    echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  TURN must always be DNS ONLY - never proxy TURN traffic${RESET}"
    
    if [[ "$TURN_LAN_ACCESS" =~ ^[Yy]$ ]]; then
        echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  TURN LAN: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (local networks accessible)${RESET}"
    else
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  TURN LAN: ${ERROR}DISABLED${RESET}${NOTE_TEXT} (secure - production recommended)${RESET}"
    fi

    echo -e "\n${WARNING}══════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${WARNING}         SAVE THIS DATA IMMEDIATELY! NOT STORED ELSEWHERE.        ${RESET}"
    echo -e "${WARNING}══════════════════════════════════════════════════════════════════${RESET}\n"
}

# ------------------------------
# UI/Theme/Color Definitions
# ------------------------------
BANNER='\033[1;95m'        # Purple
ACCENT='\033[1;96m'        # Cyan
WARNING='\033[1;93m'       # Yellow/Gold
SUCCESS='\033[1;92m'       # Green
ERROR='\033[1;91m'         # Red
INFO='\033[1;97m'          # White
PUBLIC_IP_COLOR='\033[1;94m'  # Light Blue
LOCAL_IP_COLOR='\033[1;93m'   # Yellow/Gold
DOCKER_COLOR='\033[1;34m'     # Medium Blue
CHOICE_COLOR='\033[1;92m'     # Green
REMOVED='\033[1;91m'          # Red for "Removed" text
CONTAINER_NAME='\033[1;93m'   # Yellow for container names
NETWORK_NAME='\033[1;92m'     # Green for network names
USER_ID_VALUE='\033[1;94m'    # Blue for user ID values
USER_ID_EXAMPLE='\033[1;94m'  # Blue for user ID example
REGISTRATION_DISABLED='\033[1;91m'  # Red for registration disabled
REGISTRATION_ENABLED='\033[1;92m'   # Green for registration enabled
RESET='\033[0m'               # Reset to default

# Access credentials colors
ACCESS_NAME='\033[1;92m'      # Green for names
ACCESS_VALUE='\033[1;93m'     # Yellow for values

# Internal secrets colors
SECRET_NAME='\033[1;94m'      # Blue for names
SECRET_VALUE='\033[1;97m'     # White for values

# DNS records colors
DNS_HOSTNAME='\033[1;93m'     # Yellow for hostnames
DNS_TYPE='\033[1;91m'         # Red for type
DNS_STATUS_PROXIED='\033[1;93m' # Yellow for PROXIED status

# Config files colors
CONFIG_PATH='\033[1;93m'      # Yellow for paths

# Important notes colors
NOTE_ICON='\033[1;93m'        # Yellow for icons
NOTE_TEXT='\033[1;97m'        # White for text

# Start deployment
main_deployment "$1"
