#!/bin/bash

################################################################################
#                                                                              #
#                    MATRIX SYNAPSE FULL STACK DEPLOYER                        #
#                              Version 1.1                                     #
#                           by MadCat (Production)                             #
#                                                                              #
#  A comprehensive deployment script for Matrix Synapse with working           #
#  multi-screenshare video calling capabilities.                               #
#                                                                              #
#  Components:                                                                 #
#  • Synapse (Matrix Homeserver)                                               #
#  • MAS (Matrix Authentication Service)                                       #
#  • PostgreSQL (Database)                                                     #
#  • LiveKit (SFU for unlimited multi-screenshare video calls)                 #
#  • Element Call (WebRTC video conferencing)                                  #
#  • Coturn (TURN/STUN server)                                                 #
#  • Synapse Admin (Web admin panel)                                           #
#                                                                              #
#  iOS/Android: Use Element app (not Element X)                                #
#                                                                              #
################################################################################

# Trap Ctrl-C to reset terminal colors
trap 'echo -e "\033[0m"; exit 130' INT

# Script version and repository info
SCRIPT_VERSION="1.1"
GITHUB_REPO="zeMadCat/Matrix-docker-stack"
GITHUB_BRANCH="main"

################################################################################
# COLOR DEFINITIONS                                                            #
################################################################################

BANNER='\033[1;95m'                # Purple - Banner text
ACCENT='\033[1;96m'                # Cyan - Section headers
WARNING='\033[1;93m'               # Yellow - Warnings
SUCCESS='\033[1;92m'               # Green - Success messages
ERROR='\033[1;91m'                 # Red - Error messages
INFO='\033[1;97m'                  # White - Info text
PUBLIC_IP_COLOR='\033[1;94m'       # Light Blue - Public IPs
LOCAL_IP_COLOR='\033[1;93m'        # Yellow - Local IPs
DOCKER_COLOR='\033[1;34m'          # Medium Blue - Docker related
CHOICE_COLOR='\033[1;94m'          # Blue - User choices
REMOVED='\033[1;91m'               # Red - Removed items
CONTAINER_NAME='\033[1;93m'        # Yellow - Container names
NETWORK_NAME='\033[1;92m'          # Green - Network names
USER_ID_VALUE='\033[1;94m'         # Blue - User ID values
USER_ID_EXAMPLE='\033[1;94m'       # Blue - User ID examples
REGISTRATION_DISABLED='\033[1;91m' # Red - Registration disabled
REGISTRATION_ENABLED='\033[1;92m'  # Green - Registration enabled
ACCESS_NAME='\033[1;92m'           # Green - Access credential names
ACCESS_VALUE='\033[1;93m'          # Yellow - Access credential values
SECRET_NAME='\033[1;94m'           # Blue - Secret names
SECRET_VALUE='\033[1;97m'          # White - Secret values
DNS_HOSTNAME='\033[1;93m'          # Yellow - DNS hostnames
DNS_TYPE='\033[1;91m'              # Red - DNS record type
DNS_STATUS_PROXIED='\033[1;93m'    # Yellow - Proxied status
CONFIG_PATH='\033[1;93m'           # Yellow - File paths
NOTE_ICON='\033[1;93m'             # Yellow - Note icons
NOTE_TEXT='\033[1;97m'             # White - Note text
RESET='\033[0m'                    # Reset colors
CODE='\033[0;32m'                  # Dark green - code block content

################################################################################
# UI FUNCTIONS                                                                 #
################################################################################

# Print a code block with color and border
print_code() {
    local line
    echo -e "${ACCENT}   ┌─────────────────────────────────────────────────────────────┐${RESET}"
    while IFS= read -r line; do
        echo -e "${ACCENT}   │${RESET} ${CODE}${line}${RESET}"
    done
    echo -e "${ACCENT}   └─────────────────────────────────────────────────────────────┘${RESET}"
}

# Display script header with version and component info
draw_header() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│              MATRIX SYNAPSE FULL STACK DEPLOYER              │${RESET}"
    echo -e "${BANNER}│                          by MadCat                           │${RESET}"
    echo -e "${BANNER}│                                                              │${RESET}"
    echo -e "${BANNER}│                  Included Components:                        │${RESET}"
    echo -e "${BANNER}│    Synapse • MAS • LiveKit • Coturn • PostgreSQL • Sync      │${RESET}"
    echo -e "${BANNER}│           Synapse Admin • Element Call • Bridges             │${RESET}"
    echo -e "${BANNER}│                                                              │${RESET}"
    echo -e "${BANNER}│          Selectable Bridges (Discord • Telegram •            │${RESET}"
    echo -e "${BANNER}│           WhatsApp • Signal • Slack • Instagram)             │${RESET}"
    echo -e "${BANNER}│                                                              │${RESET}"
    echo -e "${BANNER}│           Dynamic • Multi-Screenshare • Easy Setup           │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    # Show version info
    echo -e "\n${INFO}Script Version: ${SUCCESS}v${SCRIPT_VERSION}${RESET}"
    
    # Check for latest version (quick, non-blocking)
    if command -v curl >/dev/null 2>&1; then
        LATEST_VERSION=$(curl -s --max-time 2 "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
        if [ -n "$LATEST_VERSION" ]; then
            compare_versions "$SCRIPT_VERSION" "$LATEST_VERSION" 2>/dev/null
            local result=$?
            if [[ $result -eq 2 ]]; then
                echo -e "${WARNING}Latest Version: v${LATEST_VERSION} ${ERROR}(Update available!)${RESET}"
            elif [[ $result -eq 0 ]]; then
                echo -e "${INFO}Latest Version: ${SUCCESS}v${LATEST_VERSION}${RESET} ✓"
            else
                echo -e "${INFO}Latest Version: v${LATEST_VERSION}${RESET}"
            fi
        fi
    fi
    echo ""
}

# Prompt user to optionally save all credentials to a file
save_credentials_prompt() {
    echo -e "\n${ACCENT}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${ACCENT}║                    SAVE CREDENTIALS TO FILE                  ║${RESET}"
    echo -e "${ACCENT}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "\n${WARNING}⚠  Security Warning:${RESET}"
    echo -e "   ${INFO}Saving credentials to a file stores sensitive passwords in plain text.${RESET}"
    echo -e "   ${INFO}Only do this on a machine you fully control. Restrict file permissions${RESET}"
    echo -e "   ${INFO}and delete the file once you have stored the credentials securely.${RESET}"
    echo ""
    echo -ne "${ACCENT}Would you like to save all credentials to a file? (y/n):${RESET} "
    read -r SAVE_CREDS
    if [[ ! "$SAVE_CREDS" =~ ^[Yy]$ ]]; then
        echo -e "   ${INFO}Credentials not saved.${RESET}"
        return
    fi

    local DEFAULT_PATH="$TARGET_DIR/credentials.txt"
    echo -e "\n${INFO}Enter the path to save credentials to.${RESET}"
    echo -e "${INFO}Edit the path below and press ENTER to confirm:${RESET}"
    echo -ne "${ACCENT}Path:${RESET} "
    # Pre-fill the input with the default path using readline
    read -r -e -i "$DEFAULT_PATH" CREDS_PATH

    # Confirm the path
    echo ""
    echo -e "${WARNING}Credentials will be saved to:${RESET}"
    echo -e "   ${CONFIG_PATH}${CREDS_PATH}${RESET}"
    echo -ne "${ACCENT}Confirm? (y/n):${RESET} "
    read -r CONFIRM_PATH
    if [[ ! "$CONFIRM_PATH" =~ ^[Yy]$ ]]; then
        echo -e "   ${INFO}Cancelled — credentials not saved.${RESET}"
        return
    fi

    # Write credentials file
    mkdir -p "$(dirname "$CREDS_PATH")"
    cat > "$CREDS_PATH" << CREDSEOF
################################################################################
# MATRIX STACK CREDENTIALS
# Generated: $(date)
# Server:    $SERVER_NAME
#
# WARNING: This file contains sensitive passwords in plain text.
#          Store securely and delete when no longer needed.
#          Restrict permissions: chmod 600 $CREDS_PATH
################################################################################

══ MATRIX ACCESS ═══════════════════════════════════════════════════════════════

  Admin User:          @$ADMIN_USER:$SERVER_NAME
  Admin Password:      $ADMIN_PASS
  Admin Panel:         http://$AUTO_LOCAL_IP:8009
  Matrix API (LAN):    http://$AUTO_LOCAL_IP:8008
  Matrix API (WAN):    https://$SUB_MATRIX.$DOMAIN
  Auth Service (LAN):  http://$AUTO_LOCAL_IP:8010
  Auth Service (WAN):  https://$SUB_MAS.$DOMAIN
  Element Web (LAN):   http://$AUTO_LOCAL_IP:8012
  Element Web (WAN):   https://$SUB_ELEMENT.$DOMAIN
  Element Call (LAN):  http://$AUTO_LOCAL_IP:8007
  Element Call (WAN):  https://$SUB_CALL.$DOMAIN

══ DATABASE ═════════════════════════════════════════════════════════════════════

  DB User:             $DB_USER
  DB Password:         $DB_PASS
  Databases:           synapse, matrix_auth, syncv3

══ INTERNAL SECRETS ═════════════════════════════════════════════════════════════

  Shared Secret:       $REG_SECRET
  MAS Secret:          $MAS_SECRET
  TURN Secret:         $TURN_SECRET
  LiveKit API Key:     $LK_API_KEY
  LiveKit API Secret:  $LK_API_SECRET
CREDSEOF

    # Append NPM credentials if applicable
    if [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "npm" && -n "$NPM_ADMIN_PASS" ]]; then
        cat >> "$CREDS_PATH" << NPMCREDSEOF

══ NGINX PROXY MANAGER ══════════════════════════════════════════════════════════

  NPM Web UI:          http://$AUTO_LOCAL_IP:81
  NPM Email:           $NPM_ADMIN_EMAIL
  NPM Password:        $NPM_ADMIN_PASS
NPMCREDSEOF
    elif [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "traefik" ]]; then
        cat >> "$CREDS_PATH" << TRAEFIKCREDSEOF

══ TRAEFIK ══════════════════════════════════════════════════════════════════════

  Dashboard:           http://$AUTO_LOCAL_IP:8080
  Static config:       $TARGET_DIR/traefik/traefik.yml
  Dynamic config:      $TARGET_DIR/traefik/dynamic.yml
TRAEFIKCREDSEOF
    elif [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "caddy" ]]; then
        cat >> "$CREDS_PATH" << CADDYCREDSEOF

══ CADDY ════════════════════════════════════════════════════════════════════════

  Admin API:           http://$AUTO_LOCAL_IP:2019
  Config file:         $TARGET_DIR/caddy/Caddyfile
CADDYCREDSEOF
    fi

    # Restrict permissions immediately
    chmod 600 "$CREDS_PATH"

    echo -e "\n${SUCCESS}✓ Credentials saved to: ${CONFIG_PATH}${CREDS_PATH}${RESET}"
    echo -e "   ${SUCCESS}✓ File permissions set to 600 (owner read/write only)${RESET}"
    echo -e "   ${WARNING}⚠  Remember to delete this file once credentials are stored securely.${RESET}"
}

# Display deployment completion footer with all credentials and configuration
draw_footer() {
    echo -e "\n${SUCCESS}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${SUCCESS}│                      DEPLOYMENT COMPLETE                     │${RESET}"
    echo -e "${SUCCESS}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    # Access credentials section
    echo -e "\n${ACCENT}═══════════════════════ ACCESS CREDENTIALS ═══════════════════════${RESET}"
    echo -e "   ${ACCESS_NAME}Matrix Server:${RESET}       ${ACCESS_VALUE}${SERVER_NAME}${RESET}"
    echo -e "   ${ACCESS_NAME}Admin User:${RESET}          ${ACCESS_VALUE}${ADMIN_USER}${RESET}"
    if [ "$PASS_IS_CUSTOM" = true ]; then
        echo -e "   ${ACCESS_NAME}Admin Pass:${RESET}          ${ACCESS_VALUE}[Your custom password]${RESET}"
    else
        echo -e "   ${ACCESS_NAME}Admin Pass:${RESET}          ${ACCESS_VALUE}${ADMIN_PASS}${RESET}"
    fi
    echo -e "   ${ACCESS_NAME}Admin Panel:${RESET}         ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8009${RESET}"
    echo -e "   ${ACCESS_NAME}Matrix API:${RESET}          ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8008${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_MATRIX.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Auth Service (MAS):${RESET}  ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8010${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_MAS.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Element Web:${RESET}         ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8012${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_ELEMENT.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Element Call:${RESET}        ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8007${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_CALL.$DOMAIN${ACCESS_VALUE}${RESET} (WAN via Element Web)"

    # Proxy admin info if we deployed it
    if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
        case "$PROXY_TYPE" in
            npm)
                if [[ -n "$NPM_ADMIN_PASS" ]]; then
                    echo -e "\n${ACCENT}═══════════════════════ NPM ADMIN PANEL ════════════════════════${RESET}"
                    echo -e "   ${ACCESS_NAME}NPM Web UI:${RESET}          ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:81${RESET}"
                    echo -e "   ${ACCESS_NAME}NPM Email:${RESET}           ${ACCESS_VALUE}${NPM_ADMIN_EMAIL}${RESET}"
                    echo -e "   ${ACCESS_NAME}NPM Password:${RESET}        ${ACCESS_VALUE}${NPM_ADMIN_PASS}${RESET}"
                fi
                ;;
            caddy)
                echo -e "\n${ACCENT}═══════════════════════ CADDY PROXY ════════════════════════════${RESET}"
                echo -e "   ${ACCESS_NAME}Config file:${RESET}         ${CONFIG_PATH}$TARGET_DIR/caddy/Caddyfile${RESET}"
                echo -e "   ${ACCESS_NAME}Admin API:${RESET}           ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:2019${RESET}"
                echo -e "   ${INFO}ℹ  TLS certs are handled automatically via Let's Encrypt${RESET}"
                ;;
            traefik)
                echo -e "\n${ACCENT}═══════════════════════ TRAEFIK PROXY ══════════════════════════${RESET}"
                echo -e "   ${ACCESS_NAME}Dashboard:${RESET}           ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8080${RESET}"
                echo -e "   ${ACCESS_NAME}Static config:${RESET}       ${CONFIG_PATH}$TARGET_DIR/traefik/traefik.yml${RESET}"
                echo -e "   ${ACCESS_NAME}Dynamic config:${RESET}      ${CONFIG_PATH}$TARGET_DIR/traefik/dynamic.yml${RESET}"
                echo -e "   ${INFO}ℹ  TLS certs are handled automatically via Let's Encrypt${RESET}"
                ;;
        esac
    fi

    # Internal secrets section
    echo -e "\n${ACCENT}═══════════════════════ INTERNAL SECRETS ════════════════════════${RESET}"
    echo -e "   ${SECRET_NAME}Database Credentials:${RESET}"
    echo -e "   ${SECRET_NAME}   DB User:${RESET}       ${SECRET_VALUE}${DB_USER}${RESET}"
    echo -e "   ${SECRET_NAME}   DB Password:${RESET}   ${SECRET_VALUE}${DB_PASS}${RESET}"
    echo -e "   ${SECRET_NAME}   Databases:${RESET}     ${SECRET_VALUE}synapse, matrix_auth, syncv3${RESET}"
    echo -e "   ${SECRET_NAME}Shared Secret:${RESET}    ${SECRET_VALUE}${REG_SECRET}${RESET}"
    echo -e "   ${SECRET_NAME}MAS Secret:${RESET}       ${SECRET_VALUE}${MAS_SECRET}${RESET}"
    echo -e "   ${SECRET_NAME}TURN Secret:${RESET}      ${SECRET_VALUE}${TURN_SECRET}${RESET}"
    echo -e "   ${SECRET_NAME}Livekit API Key:${RESET}  ${SECRET_VALUE}${LK_API_KEY}${RESET}"
    echo -e "   ${SECRET_NAME}Livekit Secret:${RESET}   ${SECRET_VALUE}${LK_API_SECRET}${RESET}"

    # DNS records table
    echo -e "\n${ACCENT}═════════════════════════ DNS RECORDS ═══════════════════════════${RESET}"
    if [[ "$PROXY_TYPE" == "cloudflare" ]]; then
        MATRIX_STATUS="DNS ONLY"
        MAS_STATUS="DNS ONLY"
        LIVEKIT_STATUS="DNS ONLY"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="DNS ONLY"
    elif [[ "$PROXY_TYPE" == "npm" ]] || [[ "$PROXY_TYPE" == "caddy" ]] || [[ "$PROXY_TYPE" == "traefik" ]]; then
        MATRIX_STATUS="PROXIED"
        MAS_STATUS="PROXIED"
        LIVEKIT_STATUS="PROXIED"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="PROXIED"
    else
        MATRIX_STATUS="DNS ONLY"
        MAS_STATUS="DNS ONLY"
        LIVEKIT_STATUS="DNS ONLY"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="DNS ONLY"
    fi
    
    # Display DNS records table
    echo -e "   ┌─────────────────┬───────────┬─────────────────┬─────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ %-15s │ %-15s │\n" "HOSTNAME" "TYPE" "VALUE" "STATUS"
    echo -e "   ├─────────────────┼───────────┼─────────────────┼─────────────────┤"
    
    # Matrix row (using @ for apex)
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "@" "A" "$AUTO_PUBLIC_IP"
    if [[ "$MATRIX_STATUS" == "PROXIED" ]]; then
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$MATRIX_STATUS"
    else
        printf "%-15s │\n" "$MATRIX_STATUS"
    fi
    
    # MAS row
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_MAS" "A" "$AUTO_PUBLIC_IP"
    if [[ "$MAS_STATUS" == "PROXIED" ]]; then
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$MAS_STATUS"
    else
        printf "%-15s │\n" "$MAS_STATUS"
    fi
    
    # TURN row
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "turn" "A" "$AUTO_PUBLIC_IP"
    if [[ "$TURN_STATUS" == "PROXIED" ]]; then
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$TURN_STATUS"
    else
        printf "%-15s │\n" "$TURN_STATUS"
    fi
    
    # LiveKit row
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_LIVEKIT" "A" "$AUTO_PUBLIC_IP"
    if [[ "$LIVEKIT_STATUS" == "PROXIED" ]]; then
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$LIVEKIT_STATUS"
    else
        printf "%-15s │\n" "$LIVEKIT_STATUS"
    fi
    
    # Element Call row
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_CALL" "A" "$AUTO_PUBLIC_IP"
    if [[ "$ELEMENT_CALL_STATUS" == "PROXIED" ]]; then
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$ELEMENT_CALL_STATUS"
    else
        printf "%-15s │\n" "$ELEMENT_CALL_STATUS"
    fi

    # Element Web row
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_ELEMENT" "A" "$AUTO_PUBLIC_IP"
    printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "PROXIED"
    
    # Sliding Sync row (if enabled)
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_SLIDING_SYNC" "A" "$AUTO_PUBLIC_IP"
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "PROXIED"
    fi
    
    # Media Repo row (if enabled)
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_MEDIA_REPO" "A" "$AUTO_PUBLIC_IP"
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "PROXIED"
    fi
    
    echo -e "   └─────────────────┴───────────┴─────────────────┴─────────────────┘"

    # Port forwarding table
    echo -e "\n${ACCENT}════════════════════════ PORT FORWARDING ═════════════════════════${RESET}"
    echo -e "   ┌─────────────────┬───────────┬─────────────────┬───────────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ %-15s │ %-21s │\n" "SERVICE" "PROTOCOL" "PORT" "FORWARD TO"
    echo -e "   ├─────────────────┼───────────┼─────────────────┼───────────────────────┤"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Matrix Synapse" "TCP" "8008" "$AUTO_LOCAL_IP:8008"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Synapse Admin" "TCP" "8009" "$AUTO_LOCAL_IP:8009"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "MAS Auth" "TCP" "8010" "$AUTO_LOCAL_IP:8010"

    # Add Sliding Sync if enabled
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Sliding Sync" "TCP" "8011" "$AUTO_LOCAL_IP:8011"
    fi

    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Web" "TCP" "8012" "$AUTO_LOCAL_IP:8012"

    # Add Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Media Repo" "TCP" "8013" "$AUTO_LOCAL_IP:8013"
    fi
    
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN (TCP)" "TCP" "3478" "$AUTO_LOCAL_IP:3478"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN (UDP)" "UDP" "3478" "$AUTO_LOCAL_IP:3478"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN Range" "UDP" "49152-49252" "$AUTO_LOCAL_IP"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit HTTP" "TCP" "7880" "$AUTO_LOCAL_IP:7880"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit RTC" "UDP" "7882" "$AUTO_LOCAL_IP:7882"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit Range" "UDP" "50000-50050" "$AUTO_LOCAL_IP"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Call" "TCP" "8007" "$AUTO_LOCAL_IP:8007"
    echo -e "   └─────────────────┴───────────┴─────────────────┴───────────────────────┘"

    # Configuration files section
    echo -e "\n${ACCENT}═══════════════════════ CONFIGURATION FILES ═══════════════════════${RESET}"
    echo -e "   ${INFO}• Coturn:${RESET}         ${CONFIG_PATH}${TARGET_DIR}/coturn/turnserver.conf${RESET}"
    echo -e "   ${INFO}• LiveKit:${RESET}        ${CONFIG_PATH}${TARGET_DIR}/livekit/livekit.yaml${RESET}"
    echo -e "   ${INFO}• Synapse:${RESET}        ${CONFIG_PATH}${TARGET_DIR}/synapse/homeserver.yaml${RESET}"
    echo -e "   ${INFO}• MAS:${RESET}            ${CONFIG_PATH}${TARGET_DIR}/mas/config.yaml${RESET}"
    echo -e "   ${INFO}• Element Call:${RESET}   ${CONFIG_PATH}${TARGET_DIR}/element-call/config.json${RESET}"

    # Important notes section
    echo -e "\n${ACCENT}════════════════════════ IMPORTANT NOTES ═════════════════════════${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} MAS (Matrix Authentication Service) handles user authentication${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} UNLIMITED multi-screenshare enabled (no artificial limits)${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} LiveKit SFU configured for high-quality video calls${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} Element Call available for WebRTC video conferencing${RESET}"
    echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Element Call: Login with your admin account @$ADMIN_USERNAME:$DOMAIN${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} iOS/Android: Use Element app (NOT Element X)${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Element Web (self-hosted): https://$SUB_ELEMENT.$DOMAIN${RESET}"
    echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  app.element.io does NOT work with self-hosted MAS${RESET}"
    echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Test federation: https://federationtester.matrix.org${RESET}"
    echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  TURN must always be DNS ONLY - never proxy TURN traffic${RESET}"
    
    # Well-known note
    echo -e "\n${ACCENT}═══════════════════════ WELL-KNOWN CONFIGURATION ═══════════════════════${RESET}"
    echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Matrix discovery files are served from your base domain:${RESET}"
    echo -e "      ${CONFIG_PATH}https://$DOMAIN/.well-known/matrix/server${RESET}"
    echo -e "      ${CONFIG_PATH}https://$DOMAIN/.well-known/matrix/client${RESET}"
    echo -e ""
    echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  ${WARNING}CRITICAL:${RESET} You MUST create a proxy host in NPM for ${INFO}$DOMAIN${RESET}"
    echo -e "      ${NOTE_TEXT}This proxy host serves the JSON responses above - it does NOT forward to any backend.${RESET}"
    echo -e "      ${NOTE_TEXT}See the NPM guide for the required location blocks.${RESET}"
    echo -e ""
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Your well-known includes:${RESET}"
    echo -e "      • Homeserver: ${INFO}https://$SUB_MATRIX.$DOMAIN${RESET}"
    echo -e "      • Sliding Sync: ${INFO}https://$SUB_SLIDING_SYNC.$DOMAIN${RESET}"
    echo -e "      • LiveKit: ${INFO}https://$SUB_LIVEKIT.$DOMAIN${RESET}"
    # MAS configuration notes (no changes needed here, but ensure the well-known note above is clear)
    if [[ "$MAS_REGISTRATION" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Registration: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} via MAS${RESET}"
        if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then
            echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Email verification: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (SMTP configured)${RESET}"
        fi
        if [[ "$ENABLE_CAPTCHA" =~ ^[Yy]$ ]]; then
            echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  Add reCAPTCHA keys to ${CONFIG_PATH}${TARGET_DIR}/mas/config.yaml${RESET}"
        fi
    else
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Registration: ${ERROR}DISABLED${RESET}${NOTE_TEXT} - admin creates users via MAS${RESET}"
    fi
    
    # Sliding Sync note
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Sliding Sync: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (modern client support)${RESET}"
    fi
    
    # Matrix Media Repo note
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Matrix Media Repo: Configure storage backend in config.yaml${RESET}"
    fi
    
    # Bridge setup instructions
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        echo -e "\n${ACCENT}═══════════════════════ BRIDGE SETUP ════════════════════════${RESET}"
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Bridges installed: ${SUCCESS}${SELECTED_BRIDGES[*]}${RESET}"
        echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  To activate bridges, start a chat with the bot:${RESET}"
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            case $bridge in
                discord) echo -e "      ${SUCCESS}•${RESET} Discord: Chat with ${INFO}@discordbot:$DOMAIN${RESET} → Send ${WARNING}'login'${RESET}" ;;
                telegram) echo -e "      ${SUCCESS}•${RESET} Telegram: Chat with ${INFO}@telegrambot:$DOMAIN${RESET} → Send ${WARNING}'login'${RESET}" ;;
                whatsapp) echo -e "      ${SUCCESS}•${RESET} WhatsApp: Chat with ${INFO}@whatsappbot:$DOMAIN${RESET} → Send ${WARNING}'login'${RESET}" ;;
                signal) echo -e "      ${SUCCESS}•${RESET} Signal: Chat with ${INFO}@signalbot:$DOMAIN${RESET} → Send ${WARNING}'login'${RESET}" ;;
                slack) echo -e "      ${SUCCESS}•${RESET} Slack: Chat with ${INFO}@slackbot:$DOMAIN${RESET} → Send ${WARNING}'login'${RESET}" ;;
                instagram) echo -e "      ${SUCCESS}•${RESET} Instagram: Chat with ${INFO}@instagrambot:$DOMAIN${RESET} → Send ${WARNING}'login'${RESET}" ;;
            esac
        done
    fi
    
    # TURN LAN access status
    if [[ "$TURN_LAN_ACCESS" =~ ^[Yy]$ ]]; then
        echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  TURN LAN: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (local networks accessible)${RESET}"
    else
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  TURN LAN: ${ERROR}DISABLED${RESET}${NOTE_TEXT} (secure - recommended)${RESET}"
    fi
    
    # Log rotation status
    if [[ "$SETUP_LOG_ROTATION" =~ ^[Yy]$ ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Log rotation: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (logs managed automatically)${RESET}"
    else
        echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  Log rotation: ${ERROR}DISABLED${RESET}${NOTE_TEXT} (monitor disk space manually)${RESET}"
    fi

    # Final warning
    echo -e "\n${WARNING}══════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${WARNING}     !!! SAVE THIS DATA IMMEDIATELY! NOT STORED ELSEWHERE. !!!    ${RESET}"
    echo -e "${WARNING}══════════════════════════════════════════════════════════════════${RESET}\n"
}

################################################################################
# UTILITY FUNCTIONS                                                            #
################################################################################

# Compare semantic versions (e.g., "1.1" vs "1.0")
# Returns: 0 if equal, 1 if $1 > $2, 2 if $1 < $2
compare_versions() {
    local ver1=${1#v}
    local ver2=${2#v}
    
    IFS='.' read -ra V1 <<< "$ver1"
    IFS='.' read -ra V2 <<< "$ver2"
    
    # Compare major
    if [[ ${V1[0]} -gt ${V2[0]} ]]; then return 1
    elif [[ ${V1[0]} -lt ${V2[0]} ]]; then return 2
    fi
    
    # Compare minor
    if [[ ${V1[1]:-0} -gt ${V2[1]:-0} ]]; then return 1
    elif [[ ${V1[1]:-0} -lt ${V2[1]:-0} ]]; then return 2
    fi
    
    return 0
}

# Check for script updates from GitHub repository
check_for_updates() {
    echo -e "\n${ACCENT}>> Checking for updates from GitHub...${RESET}"
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "   ${WARNING}curl not found, skipping update check${RESET}"
        return 1
    fi
    
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
    
    # Fallback to version.txt if releases API fails
    if [ -z "$LATEST_VERSION" ] || [[ "$LATEST_VERSION" == *"404"* ]] || [[ "$LATEST_VERSION" == *"Not Found"* ]]; then
        LATEST_VERSION=$(curl -sL "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/version.txt" 2>/dev/null | tr -d '[:space:]' | sed 's/v//')
    fi
    
    # Validate version format (should be numbers and dots only)
    if [ -z "$LATEST_VERSION" ] || ! [[ "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+ ]]; then
        echo -e "   ${WARNING}Could not check for updates. Continuing with current version.${RESET}"
        return 1
    fi
    
    # Use semantic version comparison
    compare_versions "$SCRIPT_VERSION" "$LATEST_VERSION"
    local result=$?
    
    if [[ $result -eq 2 ]]; then
        # Current version is older
        echo -e "   ${INFO}Current version: v${SCRIPT_VERSION}${RESET}"
        echo -e "   ${INFO}Latest version:  v${LATEST_VERSION}${RESET}"
        echo -e "\n${WARNING}A newer version (v${LATEST_VERSION}) is available!${RESET}"
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
    elif [[ $result -eq 0 ]]; then
        echo -e "   ${SUCCESS}✓ You're running the latest version (v${SCRIPT_VERSION})!${RESET}"
    else
        # Current version is newer
        echo -e "   ${SUCCESS}✓ You're running version v${SCRIPT_VERSION}${RESET}"
    fi
    return 0
}

# Configure log rotation for Docker containers and Matrix stack
setup_log_rotation() {
    echo -e "\n${ACCENT}>> Setting up log rotation for Docker containers...${RESET}"
    
    # Create logrotate configuration for Docker containers
    cat > /etc/logrotate.d/docker-containers << 'LOGROTATEEOF'
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
    maxsize 100M
}
LOGROTATEEOF

    # Create specific configuration for Matrix stack logs
    cat > /etc/logrotate.d/matrix-stack << 'MATRIXLOGROTATEEOF'
/opt/stacks/matrix-stack/**/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
    maxsize 100M
    create 0644 root root
}
MATRIXLOGROTATEEOF

    # Configure system-wide log rotation settings
    cat > /etc/logrotate.conf << 'LOGROTATECONF'
# System-wide logrotate configuration
weekly
rotate 4
create
dateext
compress
delaycompress
notifempty
include /etc/logrotate.d

/var/log/syslog {
    rotate 7
    daily
    missingok
    notifempty
    delaycompress
    compress
    postrotate
        invoke-rc.d rsyslog rotate > /dev/null 2>&1 || true
    endscript
}

/var/log/messages {
    rotate 7
    daily
    missingok
    notifempty
    delaycompress
    compress
}
LOGROTATECONF

    # Test the configuration
    if logrotate -d /etc/logrotate.conf > /dev/null 2>&1; then
        echo -e "   ${SUCCESS}✓ Log rotation configured successfully${RESET}"
        
        # Force an immediate rotation to test
        logrotate -f /etc/logrotate.conf > /dev/null 2>&1 || true
        
        # Setup cron job for daily rotation
        cat > /etc/cron.daily/logrotate << 'CRONEOF'
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.conf
if [ $? -ne 0 ]; then
    logger -t logrotate "Log rotation failed"
fi
CRONEOF
        chmod +x /etc/cron.daily/logrotate
        
        echo -e "   ${INFO}ℹ  Daily log rotation scheduled via cron${RESET}"
        
        # Configure Docker daemon for better log handling
        if [ -f /etc/docker/daemon.json ]; then
            cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
        fi
        
        cat > /etc/docker/daemon.json << 'DOCKERDAEMONEOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
DOCKERDAEMONEOF
        
        systemctl restart docker
        echo -e "   ${INFO}ℹ  Docker configured with log rotation (max-size 100m, max-file 3)${RESET}"
        
        return 0
    else
        echo -e "   ${ERROR}✗ Failed to configure log rotation${RESET}"
        return 1
    fi
}

################################################################################
# CONFIGURATION GENERATION FUNCTIONS                                           #
################################################################################

# Generate Coturn TURN/STUN server configuration
generate_coturn_config() {
    echo -e "\n${ACCENT}>> Generating Coturn configuration...${RESET}"
    
    cat > "$TARGET_DIR/coturn/turnserver.conf" << COTURNEOF
# Coturn TURN/STUN Server Configuration
# Optimized for Matrix Synapse video calls

# Basic settings
listening-ip=0.0.0.0
relay-ip=$AUTO_LOCAL_IP
external-ip=$AUTO_PUBLIC_IP
listening-port=3478
tls-listening-port=5349
min-port=49152
max-port=49252
fingerprint
lt-cred-mech
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=turn.$DOMAIN

# Logging
verbose
log-file=stdout
no-stdout-log

# Security
no-multicast-peers
no-cli
no-loopback-peers

# Performance tuning
total-quota=100
bps-capacity=0
stale-nonce=600

# TLS settings (optional - uncomment if you have certificates)
# cert=/etc/ssl/certs/turnserver.pem
# pkey=/etc/ssl/private/turnserver.key
# dh-file=/etc/ssl/certs/dhparam.pem
# cipher-list="ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305"
COTURNEOF

    # Add LAN access restrictions if configured
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
    
    echo -e "   ${SUCCESS}✓ Coturn config created${RESET}"
}

# Generate LiveKit SFU configuration with multi-screenshare support
generate_livekit_config() {
    echo -e "\n${ACCENT}>> Generating LiveKit configuration...${RESET}"
    
    cat > "$TARGET_DIR/livekit/livekit.yaml" << 'LIVEKITEOF'
# LiveKit Server Configuration
# Correct YAML syntax - Unlimited Multi-Screenshare

port: 7880
bind_addresses:
  - 0.0.0.0

rtc:
  port_range_start: 50000
  port_range_end: 50050
  use_external_ip: true
  udp_port: 7882
  tcp_port: 7881

keys:
  REPLACE_LK_API_KEY: REPLACE_LK_API_SECRET

logging:
  level: info

room:
  auto_create: true
  empty_timeout: 300
LIVEKITEOF

    # Replace placeholders
    sed -i "s/REPLACE_LK_API_KEY/$LK_API_KEY/g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s/REPLACE_LK_API_SECRET/$LK_API_SECRET/g" "$TARGET_DIR/livekit/livekit.yaml"
    
    echo -e "   ${SUCCESS}✓ LiveKit config created - unlimited screenshares enabled${RESET}"
}

# Generate Element Call configuration
generate_element_call_config() {
    echo -e "\n${ACCENT}>> Generating Element Call configuration...${RESET}"
    
    cat > "$TARGET_DIR/element-call/config.json" << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$SUB_MATRIX.$DOMAIN",
            "server_name": "$SERVER_NAME"
        }
    },
    "auth": {
        "type": "oidc",
        "issuer": "https://$SUB_MAS.$DOMAIN/",
        "account": "https://$SUB_MAS.$DOMAIN/account",
        "client_id": "$ELEMENT_CALL_CLIENT_ID"
    },
    "features": {
        "feature_group_calls": true,
        "feature_video_rooms": true,
        "feature_disable_call_per_sender_encryption": false
    },
    "sfu": "livekit"
}
EOF
    
    echo -e "   ${SUCCESS}✓ Element Call config created${RESET}"
}

generate_element_web_config() {
    echo -e "\n${ACCENT}>> Generating Element Web configuration...${RESET}"

    mkdir -p "$TARGET_DIR/element-web"

    cat > "$TARGET_DIR/element-web/config.json" << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$SUB_MATRIX.$DOMAIN",
            "server_name": "$SERVER_NAME"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "brand": "Element",
    "permalink_prefix": "https://$SUB_ELEMENT.$DOMAIN",
    "default_country_code": "US",
    "room_directory": {
        "servers": [ "$SERVER_NAME" ]
    },
    "features": {
        "feature_element_call_video_rooms": true,
        "feature_group_calls": true
    },
    "element_call": {
        "url": "https://$SUB_CALL.$DOMAIN",
        "use_exclusively": false
    },
    "setting_defaults": {
        "MessageComposerInput.showStickersButton": false
    },
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": true,
    "showLabsSettings": true,
    "bug_report_endpoint_url": "https://element.io/bugreports/submit"
}
EOF

    echo -e "   ${SUCCESS}✓ Element Web config created${RESET}"
}

################################################################################
# BRIDGE CONFIGURATION GENERATION                                              #
################################################################################

generate_bridge_configs() {
    if [ ${#SELECTED_BRIDGES[@]} -eq 0 ]; then
        return
    fi
    
    echo -e "\n${ACCENT}>> Generating bridge configurations...${RESET}"
    
    mkdir -p "$TARGET_DIR/bridges"
    
    for bridge in "${SELECTED_BRIDGES[@]}"; do
        case $bridge in
            discord|telegram|whatsapp|signal|slack|instagram)
                # Generate registration file (suppress output)
                mkdir -p "$TARGET_DIR/bridges/$bridge"
                docker run --rm \
                    -v "$TARGET_DIR/bridges/$bridge:/data" \
                    dock.mau.dev/mautrix/$bridge:latest \
                    /usr/bin/mautrix-$bridge -g -c /data/config.yaml -r /data/registration.yaml > /dev/null 2>&1
                
                # Update config with homeserver details
                sed -i "s|address: https://matrix.example.com|address: http://synapse:8008|g" "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
                sed -i "s|domain: example.com|domain: $DOMAIN|g" "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
                
                # Capitalize first letter for display
                BRIDGE_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
                echo -e "${SUCCESS}   ✓ $BRIDGE_NAME bridge configured${RESET}"
                ;;
        esac
    done
}

# Setup nginx to serve well-known files on the base domain
setup_nginx_wellknown() {
    echo -e "\n${ACCENT}>> Configuring local nginx for base domain well-known...${RESET}"
    echo -e "   ${INFO}Federation requires $DOMAIN/.well-known/matrix/ to be reachable.${RESET}"
    echo -e "   ${INFO}This sets up nginx on THIS machine to serve it on port 80.${RESET}"

    # Check if nginx is installed
    if ! command -v nginx &>/dev/null; then
        echo -e "   ${WARNING}⚠️  nginx not found on this machine - skipping${RESET}"
        case "$PROXY_TYPE" in
            npm)    echo -e "   ${INFO}ℹ  Serve well-known via the NPM Advanced Tab config in the setup guide below.${RESET}" ;;
            caddy)  echo -e "   ${INFO}ℹ  Serve well-known via the Caddyfile config in the setup guide below.${RESET}" ;;
            traefik)echo -e "   ${INFO}ℹ  Serve well-known via the Traefik config in the setup guide below.${RESET}" ;;
            *)      echo -e "   ${INFO}ℹ  Ensure your reverse proxy serves $TARGET_DIR/well-known/ at https://$DOMAIN/.well-known/matrix/${RESET}" ;;
        esac
        return
    fi

    cat > /etc/nginx/sites-available/matrix-wellknown << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/matrix/ {
        alias $TARGET_DIR/well-known/matrix/;
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        add_header Cache-Control "no-cache";
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINXEOF

    # Remove default site if it conflicts
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-enabled/well-known

    # Enable the new site
    ln -sf /etc/nginx/sites-available/matrix-wellknown /etc/nginx/sites-enabled/matrix-wellknown

    if nginx -t 2>/dev/null; then
        nginx -s reload 2>/dev/null
        echo -e "   ${SUCCESS}✓ nginx on this machine will serve $DOMAIN/.well-known/matrix/ on port 80${RESET}"
    else
        echo -e "   ${ERROR}✗ nginx config test failed - check /etc/nginx/sites-available/matrix-wellknown${RESET}"
    fi
}

# Generate well-known files for base domain
generate_wellknown_files() {
    echo -e "\n${ACCENT}>> Generating well-known files for base domain...${RESET}"

    # Create directory for well-known files
    mkdir -p "$TARGET_DIR/well-known/matrix"
    
    # Generate server well-known
    cat > "$TARGET_DIR/well-known/matrix/server" << EOF
{"m.server": "$SUB_MATRIX.$DOMAIN:443"}
EOF

    # Generate client well-known with all required fields
    cat > "$TARGET_DIR/well-known/matrix/client" << EOF
{
    "m.homeserver": {
        "base_url": "https://$SUB_MATRIX.$DOMAIN"
    },
    "m.identity_server": {
        "base_url": "https://vector.im"
    },
    "m.authentication": {
        "issuer": "https://$SUB_MAS.$DOMAIN/",
        "account": "https://$SUB_MAS.$DOMAIN/account"
    },
    "org.matrix.msc3575.proxy": {
        "url": "https://$SUB_SLIDING_SYNC.$DOMAIN"
    },
    "org.matrix.msc4143.rtc_focus": {
        "url": "https://$SUB_LIVEKIT.$DOMAIN"
    }
}
EOF

    echo -e "   ${SUCCESS}✓ Well-known files created in $TARGET_DIR/well-known/${RESET}"
    echo -e "   ${INFO}ℹ  These files need to be served from: https://$DOMAIN/.well-known/matrix/{server,client}${RESET}"
    case "$PROXY_TYPE" in
        npm)
            echo -e "   ${INFO}   These are already included in the NPM Advanced Tab config shown in the setup guide below.${RESET}"
            ;;
        caddy)
            echo -e "   ${INFO}   These are already included in the Caddyfile config shown in the setup guide below.${RESET}"
            ;;
        traefik)
            echo -e "   ${INFO}   These are already included in the Traefik dynamic config shown in the setup guide below.${RESET}"
            ;;
        cloudflare)
            echo -e "   ${INFO}   Cloudflare Tunnel cannot serve inline JSON — use the nginx well-known config above, or serve${RESET}"
            echo -e "   ${INFO}   the files from a lightweight web server accessible at https://$DOMAIN/.well-known/matrix/${RESET}"
            ;;
        *)
            echo -e "   ${INFO}   Configure your reverse proxy to serve these files, or point your web server root at:${RESET}"
            echo -e "   ${INFO}   $TARGET_DIR/well-known/${RESET}"
            ;;
    esac
}

# Generate MAS (Matrix Authentication Service) configuration
generate_mas_config() {
    echo -e "\n${ACCENT}>> Generating MAS (Matrix Authentication Service) configuration...${RESET}"
    
    # Ensure MAS directory exists
    mkdir -p "$TARGET_DIR/mas"

    # Generate EC signing key via openssl (MAS v1.8.0+ requires real EC/RSA keys, not hex)
    # MAS requires PKCS#8 format (BEGIN PRIVATE KEY), NOT legacy EC format (BEGIN EC PRIVATE KEY)
    MAS_EC_KEY=$(openssl ecparam -name prime256v1 -genkey 2>/dev/null | openssl pkcs8 -topk8 -nocrypt 2>/dev/null)
    if [ -z "$MAS_EC_KEY" ]; then
        echo -e "   ${ERROR}✗ Failed to generate EC key - is openssl installed?${RESET}"
        exit 1
    fi
    echo -e "   ${SUCCESS}✓ EC signing key generated${RESET}"
    
    # Build email configuration
    if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]] && [[ -n "$SMTP_HOST" ]]; then
        EMAIL_CONFIG="email:
  from: '$SMTP_FROM'
  reply_to: '$SMTP_FROM'
  transport: smtp
  hostname: $SMTP_HOST
  port: $SMTP_PORT
  mode: starttls
  username: $SMTP_USER
  password: $SMTP_PASS"
    else
        EMAIL_CONFIG="email:
  from: 'noreply@$DOMAIN'
  reply_to: 'noreply@$DOMAIN'
  transport: blackhole"
    fi
    
    # Build CAPTCHA configuration
    if [[ "$ENABLE_CAPTCHA" =~ ^[Yy]$ ]]; then
        CAPTCHA_CONFIG="  captcha:
    service: recaptcha_v2
    site_key: YOUR_RECAPTCHA_SITE_KEY_HERE
    secret_key: YOUR_RECAPTCHA_SECRET_KEY_HERE"
    else
        CAPTCHA_CONFIG="  # captcha: disabled"
    fi
    
    # Write the config with proper random ULID for Element Call
    cat > "$TARGET_DIR/mas/config.yaml" << EOF
# MAS (Matrix Authentication Service) Configuration

http:
  public_base: https://$SUB_MAS.$DOMAIN/
  trusted_proxies:
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
    - "127.0.0.1/8"
    - "::1/128"
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
        - name: assets
      binds:
        - address: "[::]:8080"
    - name: internal
      resources:
        - name: connection-info
        - name: health
      binds:
        - address: "[::]:8081"

database:
  uri: postgresql://$DB_USER:$DB_PASS@postgres/matrix_auth
  min_connections: 5
  max_connections: 10
  connect_timeout: 30
  idle_timeout: 600
  max_lifetime: 1800

secrets:
  encryption: "$MAS_ENCRYPTION_SECRET"
  keys:
    - kid: "primary"
      key: |
$(echo "$MAS_EC_KEY" | sed 's/^/        /')

upstream_oauth2:
  providers: []

matrix:
  homeserver: "$DOMAIN"
  secret: "$MAS_SECRET"
  endpoint: http://synapse:8008

clients:
  - client_id: "0000000000000000000SYNAPSE"
    client_auth_method: client_secret_basic
    client_secret: "$MAS_SECRET"

  - client_id: "$ELEMENT_CALL_CLIENT_ID"
    client_auth_method: none
    client_uri: "https://$SUB_CALL.$DOMAIN/"
    redirect_uris:
      - "https://$SUB_CALL.$DOMAIN/"
    grant_types:
      - authorization_code
      - refresh_token
    response_types:
      - code

  - client_id: "$ELEMENT_WEB_CLIENT_ID"
    client_auth_method: none
    client_uri: "https://$SUB_ELEMENT.$DOMAIN/"
    redirect_uris:
      - "https://$SUB_ELEMENT.$DOMAIN/"
    grant_types:
      - authorization_code
      - refresh_token
    response_types:
      - code

$EMAIL_CONFIG

passwords:
  enabled: true
  schemes:
    - version: 1
      algorithm: argon2id

account:
  email_change_allowed: true
  display_name_change_allowed: true
  password_change_allowed: true

policy:
  registration:
    enabled: $MAS_REGISTRATION
    require_email: $(if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then echo "true"; else echo "false"; fi)
$CAPTCHA_CONFIG

branding:
  service_name: "$DOMAIN Matrix Server"
EOF

    # Verify file was created
    if [ ! -f "$TARGET_DIR/mas/config.yaml" ]; then
        echo -e "   ${ERROR}✗ FAILED to create MAS config file${RESET}"
        exit 1
    fi

    echo -e "   ${SUCCESS}✓ MAS config created${RESET}"
    if [[ "$ENABLE_CAPTCHA" =~ ^[Yy]$ ]]; then
        echo -e "   ${WARNING}⚠️  Remember to add reCAPTCHA keys to: $TARGET_DIR/mas/config.yaml${RESET}"
    fi
}

# Generate PostgreSQL initialization script (creates syncv3 database for Sliding Sync)
generate_postgres_init() {
    echo -e "\n${ACCENT}>> Generating synapse-db (PostgreSQL) init script...${RESET}"
    
    cat > "$TARGET_DIR/postgres_init/01-create-databases.sh" << 'PGINITEOF'
#!/bin/bash
set -e

# Create syncv3 database for Sliding Sync
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE syncv3'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'syncv3')\gexec
EOSQL

echo "PostgreSQL: syncv3 database created (if needed)"

# Create matrix_auth database for MAS
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE matrix_auth'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'matrix_auth')\gexec
EOSQL

echo "PostgreSQL: matrix_auth database created (if needed)"
PGINITEOF

    chmod +x "$TARGET_DIR/postgres_init/01-create-databases.sh"
    echo -e "   ${SUCCESS}✓ PostgreSQL init script created${RESET}"
}

# Generate Docker Compose configuration
generate_docker_compose() {
    echo -e "\n${ACCENT}>> Generating Docker Compose configuration...${RESET}"
    
    cat > "$TARGET_DIR/compose.yaml" << 'COMPOSEEOF'
################################################################################
#                                                                              #
#                    MATRIX SYNAPSE STACK - DOCKER COMPOSE                     #
#                                                                              #
#  Production-ready configuration with:                                        #
#  • Three PostgreSQL databases (synapse, matrix_auth, syncv3)                 #
#  • MAS for iOS/Android native app support                                    #
#  • LiveKit SFU with multi-screenshare support                                #
#  • Element Call for WebRTC video conferencing                                #
#  • Coturn TURN/STUN server                                                   #
#  • Synapse Admin web interface                                               #
#                                                                              #
################################################################################

services:
  # PostgreSQL Database - Hosts 'synapse', 'matrix_auth', and 'syncv3' databases
  postgres:
    container_name: synapse-db
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: REPLACE_DB_PASS
      POSTGRES_DB: synapse
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
      - ./postgres_init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse && psql -U synapse -lqt | cut -d '|' -f1 | grep -qw matrix_auth"]
      interval: 5s
      timeout: 5s
      retries: 20
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # Synapse Matrix Homeserver
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
      mas:
        condition: service_started
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8008/_matrix/client/versions || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 180s
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # Synapse Admin Web Interface
  synapse-admin:
    container_name: synapse-admin
    image: awesometechnologies/synapse-admin:latest
    restart: unless-stopped
    ports: [ "8009:80" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # Coturn TURN/STUN Server
  coturn:
    container_name: coturn
    image: coturn/coturn:latest
    restart: unless-stopped
    ports: 
      - "3478:3478/tcp"
      - "3478:3478/udp"
      - "49152-49252:49152-49252/udp"
    volumes: [ "./coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # LiveKit SFU Server - Multi-screenshare support
  livekit:
    container_name: livekit
    image: livekit/livekit-server:latest
    restart: unless-stopped
    command: --config /etc/livekit.yaml
    volumes: [ "./livekit/livekit.yaml:/etc/livekit.yaml:ro" ]
    ports: 
      - "7880:7880"
      - "7881:7881/tcp"
      - "7882:7882/udp"
      - "50000-50050:50000-50050/udp"
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # Element Call - WebRTC Video Conferencing
  element-call:
    container_name: element-call
    image: ghcr.io/element-hq/element-call:latest
    restart: unless-stopped
    volumes: [ "./element-call/config.json:/app/config.json:ro" ]
    ports: [ "8007:8080" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # MAS (Matrix Authentication Service) - Handles authentication
  mas:
    container_name: matrix-auth
    image: ghcr.io/element-hq/matrix-authentication-service:latest
    restart: unless-stopped
    command: server --config /config.yaml
    volumes: [ "./mas/config.yaml:/config.yaml:ro" ]
    ports: [ "8010:8080", "8081:8081" ]
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      disable: true
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # Element Web - Matrix Web Client (required for proper OIDC login flow)
  element-web:
    container_name: element-web
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes: [ "./element-web/config.json:/app/config.json:ro" ]
    ports: [ "8012:80" ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

# Dedicated network for Matrix stack
networks:
  matrix-net:
    name: matrix-net
    labels:
      com.docker.compose.project: "matrix-stack"
COMPOSEEOF

    # Add Sliding Sync if enabled
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        sed -i '/^networks:/i\
\
  # Sliding Sync Proxy - For modern Matrix clients\
  sliding-sync:\
    container_name: sliding-sync\
    image: ghcr.io/matrix-org/sliding-sync:latest\
    restart: unless-stopped\
    environment:\
      SYNCV3_SERVER: http://synapse:8008\
      SYNCV3_SECRET: '"$SLIDING_SYNC_SECRET"'\
      SYNCV3_BINDADDR: 0.0.0.0:8011\
      SYNCV3_DB: postgresql://'"$DB_USER"':'"$DB_PASS"'@postgres/syncv3?sslmode=disable\
    ports: [ "8011:8011" ]\
    depends_on:\
      postgres:\
        condition: service_healthy\
      synapse:\
        condition: service_healthy\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
    fi
    
    # Add Matrix Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        mkdir -p "$TARGET_DIR/media-repo"
        sed -i '/^networks:/i\
\
  # Matrix Media Repository - Advanced media server\
  matrix-media-repo:\
    container_name: matrix-media-repo\
    image: turt2live/matrix-media-repo:latest\
    restart: unless-stopped\
    volumes:\
      - ./media-repo/config.yaml:/config/media-repo.yaml:ro\
      - ./media-repo/data:/data\
    ports: [ "8013:8000" ]\
    environment:\
      REPO_CONFIG: /config/media-repo.yaml\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
    fi

    # Replace database password placeholder
    sed -i "s/REPLACE_DB_PASS/$DB_PASS/g" "$TARGET_DIR/compose.yaml"
    
    # Print all success messages together
    echo -e "   ${SUCCESS}✓ Docker Compose config created${RESET}"
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Sliding Sync Proxy included${RESET}"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Matrix Media Repo included${RESET}"
    fi
    
    # Add bridges if selected
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            # Capitalize first letter for service name
            BRIDGE_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
            
            case $bridge in
                discord|telegram|whatsapp|signal|slack|instagram)
                    sed -i '/^networks:/i\
\
  # mautrix-'"$bridge"' Bridge\
  mautrix-'"$bridge"':\
    container_name: matrix-bridge-'"$bridge"'\
    image: dock.mau.dev/mautrix/'"$bridge"':latest\
    restart: unless-stopped\
    volumes:\
      - ./bridges/'"$bridge"':/data\
    depends_on:\
      synapse:\
        condition: service_healthy\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
                    ;;
            esac
        done
        
        # Format bridge names with proper capitalization
        BRIDGE_NAMES=""
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            # Capitalize first letter
            BRIDGE_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
            if [ -z "$BRIDGE_NAMES" ]; then
                BRIDGE_NAMES="$BRIDGE_NAME"
            else
                BRIDGE_NAMES="$BRIDGE_NAMES ${SUCCESS}*${RESET} $BRIDGE_NAME"
            fi
        done
        
        echo -e "   ${SUCCESS}✓ ${#SELECTED_BRIDGES[@]} bridge(s) added${RESET}"
        echo -e "     ${CHOICE_COLOR}$BRIDGE_NAMES${RESET}"
    fi

    # Add NPM to compose if user has no proxy and chose NPM
    if [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "npm" ]]; then
        sed -i '/^networks:/i\\
\\
  # Nginx Proxy Manager - Reverse proxy with web UI\\
  nginx-proxy-manager:\\
    container_name: nginx-proxy-manager\\
    image: jc21/nginx-proxy-manager:latest\\
    restart: unless-stopped\\
    ports:\\
      - "80:80"\\
      - "443:443"\\
      - "81:81"\\
    volumes:\\
      - ./npm/data:/data\\
      - ./npm/letsencrypt:/etc/letsencrypt\\
    networks: [ matrix-net ]\\
    labels:\\
      com.docker.compose.project: "matrix-stack"\\
' "$TARGET_DIR/compose.yaml"
        echo -e "   ${SUCCESS}✓ Nginx Proxy Manager added to stack${RESET}"
    fi

    if [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "caddy" ]]; then
        mkdir -p "$TARGET_DIR/caddy"
        sed -i '/^networks:/i\\
\\
  # Caddy - Automatic HTTPS reverse proxy\\
  caddy:\\
    container_name: caddy\\
    image: caddy:latest\\
    restart: unless-stopped\\
    ports:\\
      - "80:80"\\
      - "443:443"\\
      - "443:443/udp"\\
    volumes:\\
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile\\
      - ./caddy/data:/data\\
      - ./caddy/config:/config\\
    networks: [ matrix-net ]\\
    labels:\\
      com.docker.compose.project: "matrix-stack"\\
' "$TARGET_DIR/compose.yaml"
        echo -e "   ${SUCCESS}✓ Caddy added to stack${RESET}"
    fi

    if [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "traefik" ]]; then
        mkdir -p "$TARGET_DIR/traefik"
        sed -i '/^networks:/i\\
\\
  # Traefik - Dynamic reverse proxy\\
  traefik:\\
    container_name: traefik\\
    image: traefik:latest\\
    restart: unless-stopped\\
    ports:\\
      - "80:80"\\
      - "443:443"\\
      - "8080:8080"\\
    volumes:\\
      - /var/run/docker.sock:/var/run/docker.sock:ro\\
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml\\
      - ./traefik/dynamic.yml:/etc/traefik/dynamic.yml\\
      - ./traefik/acme:/etc/traefik/acme\\
    networks: [ matrix-net ]\\
    labels:\\
      com.docker.compose.project: "matrix-stack"\\
' "$TARGET_DIR/compose.yaml"
        echo -e "   ${SUCCESS}✓ Traefik added to stack${RESET}"
    fi
}

# Generate Synapse homeserver configuration
generate_synapse_config() {
    echo -e "\n${ACCENT}>> Generating Synapse configuration...${RESET}"
    
    # Generate initial Synapse config only if it doesn't exist
    if [ ! -f "$TARGET_DIR/synapse/homeserver.yaml" ]; then
        docker run --rm \
            -v "$TARGET_DIR/synapse:/data" \
            -e SYNAPSE_SERVER_NAME="$SERVER_NAME" \
            -e SYNAPSE_REPORT_STATS=yes \
            matrixdotorg/synapse:latest generate > /dev/null 2>&1
    fi
    
# Append our custom configuration
cat >> "$TARGET_DIR/synapse/homeserver.yaml" << SYNAPSEEOF

################################################################################
# CUSTOM CONFIGURATION - Matrix Full Stack Deployment                          #
################################################################################

# Server Configuration
public_baseurl: https://$SUB_MATRIX.$DOMAIN
serve_server_wellknown: true

# Suppress key server warning
suppress_key_server_warning: true

# PostgreSQL Database Configuration
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

# TURN/STUN Configuration for NAT traversal
turn_uris:
  - "turn:turn.$DOMAIN:3478?transport=udp"
  - "turn:turn.$DOMAIN:3478?transport=tcp"
  - "turns:turn.$DOMAIN:5349?transport=tcp"
turn_shared_secret: "$TURN_SECRET"
turn_user_lifetime: 86400000
turn_allow_guests: false

# Registration DISABLED - MAS handles all authentication
enable_registration: false
enable_registration_without_verification: false
registration_shared_secret: "$REG_SECRET"

# Rate Limiting
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

# Media Configuration
max_upload_size: 50M
max_image_pixels: 32M
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

################################################################################
# MAS INTEGRATION - Matrix Authentication Service                              #
################################################################################

# Matrix Authentication Service (replaces deprecated experimental_features.msc3861)
matrix_authentication_service:
  enabled: true
  endpoint: http://mas:8080/
  client_id: 0000000000000000000SYNAPSE
  client_auth_method: client_secret_basic
  secret: $MAS_SECRET
  account_management_url: https://$SUB_MAS.$DOMAIN/account

################################################################################
# LIVEKIT SFU - Unlimited Multi-Screenshare Video Calling                     #
################################################################################

# Element Call widget configuration
widget_urls:
  - https://$SUB_CALL.$DOMAIN

# LiveKit SFU configuration (for Element Call)
livekit:
  url: https://$SUB_LIVEKIT.$DOMAIN
  livekit_api_key: $LK_API_KEY
  livekit_api_secret: $LK_API_SECRET

# Additional call configuration
allow_guest_access: false
SYNAPSEEOF
    
    # Set correct ownership
    chown -R 991:991 "$TARGET_DIR/synapse"
    echo -e "   ${SUCCESS}✓ Synapse config created with MAS and LiveKit support${RESET}"
}

################################################################################
# PROXY CONFIGURATION GUIDES                                                   #
################################################################################

# Auto-configure NPM via API after container starts
npm_autosetup() {
    echo -e "\n${ACCENT}>> Configuring Nginx Proxy Manager...${RESET}"

    # Wait for NPM API to become available (port 81)
    echo -ne "   ${INFO}Waiting for NPM to start${RESET}"
    local TRIES=0
    until curl -fsS -o /dev/null "http://localhost:81/api/" 2>/dev/null || [ $TRIES -ge 60 ]; do
        echo -ne "."
        sleep 3
        ((TRIES++))
    done
    echo ""

    if [ $TRIES -ge 60 ]; then
        echo -e "   ${WARNING}⚠️  NPM did not start in time. Configure manually at http://$AUTO_LOCAL_IP:81${RESET}"
        echo -e "   ${INFO}Default credentials: admin@example.com / changeme${RESET}"
        return 1
    fi

    echo -e "   ${SUCCESS}✓ NPM API is available${RESET}"

    # Authenticate with NPM default credentials to get a token
    local TOKEN
    TOKEN=$(curl -s -X POST "http://localhost:81/api/tokens" \
        -H "Content-Type: application/json" \
        -d '{"identity":"admin@example.com","secret":"changeme"}' \
        | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$TOKEN" ]; then
        echo -e "   ${WARNING}⚠️  Could not authenticate with NPM defaults (already configured?).${RESET}"
        echo -e "   ${INFO}If this is a fresh install, log in manually at http://$AUTO_LOCAL_IP:81${RESET}"
        return 1
    fi

    # Update the admin account with our generated credentials
    local UPDATE_RESULT
    UPDATE_RESULT=$(curl -s -X PUT "http://localhost:81/api/users/1" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$NPM_ADMIN_EMAIL\",\"nickname\":\"Matrix Admin\",\"roles\":[\"admin\"]}")

    # Set password separately
    curl -s -X PUT "http://localhost:81/api/users/1/auth" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"password\",\"current\":\"changeme\",\"secret\":\"$NPM_ADMIN_PASS\"}" \
        -o /dev/null

    echo -e "   ${SUCCESS}✓ NPM admin account configured${RESET}"
    echo -e "   ${SUCCESS}✓ Admin login: ${ACCESS_VALUE}$NPM_ADMIN_EMAIL${RESET}"
    echo -e "   ${SUCCESS}✓ Admin pass:  ${ACCESS_VALUE}$NPM_ADMIN_PASS${RESET}"
}

# Write Caddy config files and wait for container to be ready
caddy_autosetup() {
    echo -e "\n${ACCENT}>> Configuring Caddy...${RESET}"
    mkdir -p "$TARGET_DIR/caddy"

    # Build Caddyfile with sliding sync / media repo blocks if enabled
    local EXTRA_BLOCKS=""
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Sliding Sync Proxy
$SUB_SLIDING_SYNC.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8011
}
"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Matrix Media Repository
$SUB_MEDIA_REPO.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8013
}
"
    fi

    cat > "$TARGET_DIR/caddy/Caddyfile" << CADDYEOF
# BASE DOMAIN - Matrix well-known + redirect to Element Web
$DOMAIN {
    handle /.well-known/matrix/server {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond '{"m.server": "$SUB_MATRIX.$DOMAIN:443"}'
    }
    handle /.well-known/matrix/client {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond '{"m.homeserver":{"base_url":"https://$SUB_MATRIX.$DOMAIN"},"m.identity_server":{"base_url":"https://vector.im"},"m.authentication":{"issuer":"https://$SUB_MAS.$DOMAIN/","account":"https://$SUB_MAS.$DOMAIN/account"},"org.matrix.msc3575.proxy":{"url":"https://$SUB_SLIDING_SYNC.$DOMAIN"},"org.matrix.msc4143.rtc_focus":{"url":"https://$SUB_LIVEKIT.$DOMAIN"}}'
    }
    handle {
        redir https://$SUB_ELEMENT.$DOMAIN
    }
}

# Matrix Homeserver
$SUB_MATRIX.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8008
    header { Access-Control-Allow-Origin * }
}

# MAS Authentication Service
$SUB_MAS.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8010
    header { Access-Control-Allow-Origin * }
}

# Element Web
$SUB_ELEMENT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8012
}

# Element Call
$SUB_CALL.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8007
    header { Access-Control-Allow-Origin * }
}

# LiveKit SFU
$SUB_LIVEKIT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:7880
    header { Access-Control-Allow-Origin * }
}
$EXTRA_BLOCKS
CADDYEOF

    echo -e "   ${SUCCESS}✓ Caddyfile written${RESET}"

    # Wait for Caddy to start and reload
    echo -ne "   ${INFO}Waiting for Caddy to start${RESET}"
    local TRIES=0
    until curl -fsS -o /dev/null "http://localhost:2019/config/" 2>/dev/null || [ $TRIES -ge 30 ]; do
        echo -ne "."
        sleep 3
        ((TRIES++))
    done
    echo ""

    if [ $TRIES -ge 30 ]; then
        echo -e "   ${WARNING}⚠️  Caddy admin API not responding. Reload manually: docker exec caddy caddy reload --config /etc/caddy/Caddyfile${RESET}"
    else
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
            echo -e "   ${SUCCESS}✓ Caddy config reloaded — HTTPS certificates will be requested automatically${RESET}" || \
            echo -e "   ${INFO}ℹ  Caddy will apply config on next restart${RESET}"
    fi
}

# Write Traefik config files
traefik_autosetup() {
    echo -e "\n${ACCENT}>> Configuring Traefik...${RESET}"
    mkdir -p "$TARGET_DIR/traefik/acme"
    touch "$TARGET_DIR/traefik/acme/acme.json"
    chmod 600 "$TARGET_DIR/traefik/acme/acme.json"

    # Static config
    cat > "$TARGET_DIR/traefik/traefik.yml" << TRAEFIKSTATICEOF
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@$DOMAIN
      storage: /etc/traefik/acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true
TRAEFIKSTATICEOF

    # Build optional service/router entries
    local EXTRA_ROUTERS=""
    local EXTRA_SERVICES=""
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    sliding-sync:
      rule: \"Host(\`$SUB_SLIDING_SYNC.$DOMAIN\`)\"
      service: sliding-sync
      entryPoints: [\"websecure\"]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    sliding-sync:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:8011\""
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    media-repo:
      rule: \"Host(\`$SUB_MEDIA_REPO.$DOMAIN\`)\"
      service: media-repo
      entryPoints: [\"websecure\"]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    media-repo:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:8013\""
    fi

    # Dynamic config
    cat > "$TARGET_DIR/traefik/dynamic.yml" << TRAEFIKDYNEOF
http:
  routers:
    matrix:
      rule: "Host(\`$SUB_MATRIX.$DOMAIN\`)"
      service: matrix
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    mas:
      rule: "Host(\`$SUB_MAS.$DOMAIN\`)"
      service: mas
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    element-web:
      rule: "Host(\`$SUB_ELEMENT.$DOMAIN\`)"
      service: element-web
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    element-call:
      rule: "Host(\`$SUB_CALL.$DOMAIN\`)"
      service: element-call
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    livekit:
      rule: "Host(\`$SUB_LIVEKIT.$DOMAIN\`)"
      service: livekit
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    base-domain:
      rule: "Host(\`$DOMAIN\`) && Path(\`/.well-known/matrix/server\`)"
      service: wellknown-server
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
      middlewares: [wellknown-server-resp]

    base-domain-client:
      rule: "Host(\`$DOMAIN\`) && Path(\`/.well-known/matrix/client\`)"
      service: wellknown-client
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
      middlewares: [wellknown-client-resp]
$EXTRA_ROUTERS

  services:
    matrix:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8008"

    mas:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8010"

    element-web:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8012"

    element-call:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8007"

    livekit:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:7880"

    # Dummy services for well-known (response handled by middleware)
    wellknown-server:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1"

    wellknown-client:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1"
$EXTRA_SERVICES

  middlewares:
    wellknown-server-resp:
      headers:
        customResponseHeaders:
          Content-Type: "application/json"
          Access-Control-Allow-Origin: "*"
          Cache-Control: "no-cache"

    wellknown-client-resp:
      headers:
        customResponseHeaders:
          Content-Type: "application/json"
          Access-Control-Allow-Origin: "*"
          Cache-Control: "no-cache"
TRAEFIKDYNEOF

    echo -e "   ${SUCCESS}✓ traefik.yml written (static config)${RESET}"
    echo -e "   ${SUCCESS}✓ dynamic.yml written (routes + well-known)${RESET}"
    echo -e "   ${INFO}ℹ  Traefik dashboard: http://$AUTO_LOCAL_IP:8080${RESET}"
    echo -e "   ${INFO}ℹ  TLS certificates will be requested automatically via Let's Encrypt${RESET}"
}

# Display Nginx Proxy Manager setup guide
show_npm_guide() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│                 NGINX PROXY MANAGER SETUP GUIDE              │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"

    echo -e "\n${INFO}Note: NPM and NPMPlus have slightly different option names.${RESET}"
    echo -e "${INFO}• NPM: 'Block Exploits' — NPMPlus: 'ModSecurity'${RESET}"
    echo -e "${INFO}• Both: Enable SSL/TLS and Force SSL/HTTPS${RESET}\n"

    ##########################################################################
    # BASE DOMAIN
    ##########################################################################
    echo -e "\n${ACCENT}════════════════════════ BASE DOMAIN ════════════════════════════${RESET}"
    echo -e "${ACCENT}Create Proxy Host:${RESET}"
    echo -e "   Domain:     ${INFO}$DOMAIN${RESET}"
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:80${RESET}  ← port doesn't matter, location blocks override"
    echo -e "   Enable:     SSL (Force HTTPS), Let's Encrypt certificate\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << BASECONF
# Matrix well-known - required for client and federation discovery
location = /.well-known/matrix/server {
    return 200 '{"m.server": "$SUB_MATRIX.$DOMAIN:443"}';
    default_type application/json;
    add_header Access-Control-Allow-Origin * always;
    add_header Cache-Control "no-cache" always;
}

location = /.well-known/matrix/client {
    return 200 '{"m.homeserver":{"base_url":"https://$SUB_MATRIX.$DOMAIN"},"m.identity_server":{"base_url":"https://vector.im"},"m.authentication":{"issuer":"https://$SUB_MAS.$DOMAIN/","account":"https://$SUB_MAS.$DOMAIN/account"},"org.matrix.msc3575.proxy":{"url":"https://$SUB_SLIDING_SYNC.$DOMAIN"},"org.matrix.msc4143.rtc_focus":{"url":"https://$SUB_LIVEKIT.$DOMAIN"}}';
    default_type application/json;
    add_header Access-Control-Allow-Origin * always;
    add_header Cache-Control "no-cache" always;
}

# Redirect root to Element Web
location / {
    return 302 https://$SUB_ELEMENT.$DOMAIN;
}
BASECONF
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # MATRIX HOMESERVER
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               NPM SETUP - MATRIX HOMESERVER                  │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
    echo -e "   Domain:     ${INFO}$SUB_MATRIX.$DOMAIN${RESET}"
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:8008${RESET}"
    echo -e "   Enable:     Websockets, SSL (Force HTTPS)"
    echo -e "   ${WARNING}⚠  Do NOT enable Block Exploits / ModSecurity — it breaks Matrix API calls${RESET}\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << MATRIXCONF
# Strip Synapse's own CORS headers to prevent duplicates (causes browser CORS errors)
proxy_hide_header Access-Control-Allow-Origin;
proxy_hide_header Access-Control-Allow-Methods;
proxy_hide_header Access-Control-Allow-Headers;

client_max_body_size 50M;
proxy_read_timeout 600s;
proxy_send_timeout 600s;

# CRITICAL: login/logout/refresh MUST route to MAS (not Synapse) when OIDC is enabled
location ~* ^/_matrix/client/(v3|r0)/(login|logout|refresh) {
    proxy_pass http://$PROXY_IP:8010;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
}

# Synapse admin and client OIDC endpoints
location ~* ^/_synapse/client/ {
    proxy_pass http://$PROXY_IP:8008;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
}

# All other Matrix API endpoints
location ~* ^/_matrix/ {
    proxy_pass http://$PROXY_IP:8008;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
}
MATRIXCONF
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # MAS AUTH SERVICE
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               NPM SETUP - MAS AUTH SERVICE                   │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
    echo -e "   Domain:     ${INFO}$SUB_MAS.$DOMAIN${RESET}"
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:8010${RESET}"
    echo -e "   Enable:     Websockets, SSL (Force HTTPS)\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << MASCONF
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
proxy_set_header X-Forwarded-Host \$host;
proxy_set_header X-Forwarded-Port \$server_port;
proxy_read_timeout 600s;
proxy_send_timeout 600s;

# Strip upstream CORS headers to prevent duplicates
proxy_hide_header Access-Control-Allow-Origin;
proxy_hide_header Access-Control-Allow-Methods;
proxy_hide_header Access-Control-Allow-Headers;

add_header Access-Control-Allow-Origin * always;
add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
MASCONF
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # LIVEKIT
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               NPM SETUP - LIVEKIT SFU                        │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
    echo -e "   Domain:     ${INFO}$SUB_LIVEKIT.$DOMAIN${RESET}"
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:7880${RESET}"
    echo -e "   Enable:     Websockets, SSL (Force HTTPS)"
    echo -e "   ${WARNING}⚠  Do NOT enable Block Exploits / ModSecurity — breaks LiveKit WebSocket signalling${RESET}"
    echo -e "   ${INFO}ℹ  Using Cloudflare? Enable WebSockets: Network → WebSockets → On${RESET}\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << 'LKCONF'
# WebSocket upgrade required for LiveKit signalling
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_read_timeout 86400;
proxy_send_timeout 86400;
LKCONF
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # ELEMENT CALL
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               NPM SETUP - ELEMENT CALL                       │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
    echo -e "   Domain:     ${INFO}$SUB_CALL.$DOMAIN${RESET}"
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:8007${RESET}"
    echo -e "   Enable:     Websockets, SSL (Force HTTPS)"
    echo -e "   ${WARNING}⚠  Do NOT enable Block Exploits / ModSecurity — it breaks Element Call${RESET}"
    echo -e "   ${WARNING}Note: Element Call is a widget launched from Element Web — not a standalone login page${RESET}\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << 'CALLCONF'
# Element Call - iframe widget, requires CORS and frame embedding
proxy_hide_header Access-Control-Allow-Origin;
proxy_hide_header Access-Control-Allow-Methods;
proxy_hide_header Access-Control-Allow-Headers;
add_header Access-Control-Allow-Origin * always;
add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
add_header X-Frame-Options "ALLOWALL" always;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto $scheme;
CALLCONF
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # ELEMENT WEB
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               NPM SETUP - ELEMENT WEB                        │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
    echo -e "   Domain:     ${INFO}$SUB_ELEMENT.$DOMAIN${RESET}"
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:8012${RESET}"
    echo -e "   Enable:     Websockets, SSL (Force HTTPS)"
    echo -e "   ${SUCCESS}Primary client — users log in here, MAS handles OIDC, Element Call launches as widget${RESET}\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << ELEMENTWEBCONF
# Prevent config.json being cached
location = /config.json {
    proxy_pass http://$PROXY_IP:8012;
    proxy_set_header Host \$host;
    add_header Cache-Control "no-store" always;
    add_header Content-Type "application/json" always;
}
ELEMENTWEBCONF
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    # Optional: Sliding Sync
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        clear
        echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BANNER}│               NPM SETUP - SLIDING SYNC PROXY                 │${RESET}"
        echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
        echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
        echo -e "   Domain:     ${INFO}$SUB_SLIDING_SYNC.$DOMAIN${RESET}"
        echo -e "   Forward to: ${INFO}http://$PROXY_IP:8011${RESET}"
        echo -e "   Enable:     Websockets, SSL (Force HTTPS)\n"
        echo -e "${SUCCESS}✓ No advanced configuration needed${RESET}"
        echo -e "${WARNING}Press ENTER to continue...${RESET}"
        read -r
    fi

    # Optional: Matrix Media Repo
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        clear
        echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BANNER}│               NPM SETUP - MATRIX MEDIA REPO                  │${RESET}"
        echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
        echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
        echo -e "   Domain:     ${INFO}$SUB_MEDIA_REPO.$DOMAIN${RESET}"
        echo -e "   Forward to: ${INFO}http://$PROXY_IP:8013${RESET}"
        echo -e "   Enable:     Websockets, SSL (Force HTTPS)\n"
        echo -e "${SUCCESS}✓ No advanced configuration needed${RESET}"
        echo -e "${WARNING}Press ENTER to continue...${RESET}"
        read -r
    fi

    clear
}

# Display Caddy setup guide
show_caddy_guide() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│                      CADDY SETUP GUIDE                       │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    echo -e "\n${ACCENT}Caddyfile Configuration (${INFO}/etc/caddy/Caddyfile${ACCENT}):${RESET}\n"

    print_code << CADDYCONF
# BASE DOMAIN - Serves well-known for Matrix discovery
$DOMAIN {
    # Well-known endpoints for Matrix federation and client discovery
    handle /.well-known/matrix/server {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond '{"m.server": "$SUB_MATRIX.$DOMAIN:443"}'
    }
    
    handle /.well-known/matrix/client {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond '{
            "m.homeserver": {
                "base_url": "https://$SUB_MATRIX.$DOMAIN"
            },
            "m.identity_server": {
                "base_url": "https://vector.im"
            },
            "org.matrix.msc3575.proxy": {
                "url": "https://$SUB_SLIDING_SYNC.$DOMAIN"
            },
            "org.matrix.msc4143.rtc_focus": {
                "url": "https://$SUB_LIVEKIT.$DOMAIN"
            }
        }'
    }

    # Optional: Redirect root to Element Call
    handle {
        redir https://$SUB_CALL.$DOMAIN
    }
}

# Matrix Homeserver
$SUB_MATRIX.$DOMAIN {
    reverse_proxy $PROXY_IP:8008
    header {
        Access-Control-Allow-Origin *
    }
}

# MAS Authentication Service
$SUB_MAS.$DOMAIN {
    reverse_proxy $PROXY_IP:8010
    header {
        Access-Control-Allow-Origin *
    }
}

# LiveKit SFU
$SUB_LIVEKIT.$DOMAIN {
    reverse_proxy $PROXY_IP:7880
    header {
        Access-Control-Allow-Origin *
        Upgrade websocket
        Connection upgrade
    }
}

# Element Call
$SUB_CALL.$DOMAIN {
    reverse_proxy $PROXY_IP:8007
    header {
        Access-Control-Allow-Origin *
    }
}

CADDYCONF

    # Add Sliding Sync if enabled
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo ""
        cat << SLIDINGCONF
# Sliding Sync Proxy
$SUB_SLIDING_SYNC.$DOMAIN {
    reverse_proxy $PROXY_IP:8011
}
SLIDINGCONF
    fi
    
    # Add Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo ""
        cat << MEDIACONF
# Matrix Media Repository
$SUB_MEDIA_REPO.$DOMAIN {
    reverse_proxy $PROXY_IP:8013
}
MEDIACONF
    fi
    
    echo ""
    print_code << TURNCONF
# TURN (Do not proxy - DNS only)
turn.$DOMAIN {
    reverse_proxy $PROXY_IP:3478
}
TURNCONF
    
    echo -e "\n${ACCENT}After adding the configuration, reload Caddy:${RESET}"
    echo -e "${INFO}sudo caddy reload${RESET}\n"
    
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r
}

# Display Traefik setup guide
show_traefik_guide() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│                     TRAEFIK SETUP GUIDE                      │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    echo -e "\n${ACCENT}Create dynamic configuration (${INFO}/opt/traefik/dynamic.yml${ACCENT}):${RESET}\n"
    
    print_code << TRAEFIKCONF
http:
  # Base domain router for well-known
  routers:
    base-domain:
      rule: "Host(\`$DOMAIN\`)"
      service: base-domain-service
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
      middlewares:
        - wellknown-headers

    matrix:
      rule: "Host(\`$SUB_MATRIX.$DOMAIN\`)"
      service: matrix
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    mas:
      rule: "Host(\`$SUB_MAS.$DOMAIN\`)"
      service: mas
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    livekit:
      rule: "Host(\`$SUB_LIVEKIT.$DOMAIN\`)"
      service: livekit
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    element-call:
      rule: "Host(\`$SUB_CALL.$DOMAIN\`)"
      service: element-call
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

  services:
    # Special service for base domain that returns well-known JSON
    base-domain-service:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:80"  # Dummy backend, middleware overrides
        # OR use a file server if you prefer

    matrix:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8008"

    mas:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8010"

    livekit:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:7880"

    element-call:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8007"

  middlewares:
    wellknown-headers:
      headers:
        customResponseHeaders:
          Access-Control-Allow-Origin: "*"
          Content-Type: "application/json"

    # You'll need to add file-based routing for well-known paths
    # This is typically done with a file provider or additional routers
TRAEFIKCONF

    echo -e "\n${ACCENT}Note: For well-known endpoints, you may need to add file-based routing or use a separate file provider.${RESET}\n"

    # Add Sliding Sync if enabled
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo ""
        cat << SLIDINGCONF
    sliding-sync:
      rule: "Host(\`$SUB_SLIDING_SYNC.$DOMAIN\`)"
      service: sliding-sync
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# In services section, add:
    sliding-sync:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8011"
SLIDINGCONF
    fi
    
    # Add Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo ""
        cat << MEDIACONF
    media-repo:
      rule: "Host(\`$SUB_MEDIA_REPO.$DOMAIN\`)"
      service: media-repo
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# In services section, add:
    media-repo:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8013"
MEDIACONF
    fi
    
    echo -e "\n${ACCENT}Restart Traefik:${RESET}"
    echo -e "${INFO}docker restart traefik${RESET}\n"
    
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r
}

# Display Cloudflare Tunnel setup guide
show_cloudflare_guide() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│                CLOUDFLARE TUNNEL SETUP GUIDE                 │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    echo -e "\n${ACCENT}Update tunnel config (${INFO}~/.cloudflared/config.yml${ACCENT}):${RESET}\n"
    print_code << CFCONF
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  # Base domain - serves well-known files
  - hostname: $DOMAIN
    path: /.well-known/matrix/server
    service: http_status:200
    originRequest:
      httpStatus: 200
      noTLSVerify: true
    # cloudflared will need to serve the JSON directly

  - hostname: $DOMAIN
    path: /.well-known/matrix/client
    service: http_status:200
    originRequest:
      httpStatus: 200
      noTLSVerify: true

  # Main services
  - hostname: $SUB_MATRIX.$DOMAIN
    service: http://$PROXY_IP:8008
  
  - hostname: $SUB_MAS.$DOMAIN
    service: http://$PROXY_IP:8010
  
  - hostname: $SUB_LIVEKIT.$DOMAIN
    service: http://$PROXY_IP:7880
  
  - hostname: $SUB_CALL.$DOMAIN
    service: http://$PROXY_IP:8007
CFCONF

    echo -e "\n${ACCENT}Note: Cloudflare Tunnel has limited support for serving static JSON.${RESET}"
    echo -e "${INFO}You may need to use a small web server (like nginx) on your origin to serve the well-known files.${RESET}\n"

    # Add Sliding Sync if enabled
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_SLIDING_SYNC.$DOMAIN"
        echo "    service: http://$PROXY_IP:8011"
    fi
    
    # Add Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_MEDIA_REPO.$DOMAIN"
        echo "    service: http://$PROXY_IP:8013"
    fi
    
    print_code << 'CFTURNEOF'
  - hostname: turn.$DOMAIN
    service: http://$PROXY_IP:3478
  - service: http_status:404
CFTURNEOF
    
    echo -e "\n${ACCENT}Restart tunnel:${RESET}"
    echo -e "${INFO}systemctl restart cloudflared${RESET}\n"
    
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r
}

################################################################################
# SHARED RESOURCE SCANNER / REMOVER                                            #
################################################################################

# scan_and_remove_matrix_resources [extra_dir]
#
# Scans Docker (labels + image names) and the filesystem for all Matrix-related
# resources, displays a formatted table, then optionally removes everything
# that was found.
#
# If an extra directory path is passed as $1 it is added to the scan on top of
# the two default stack paths (/opt/stacks/matrix-stack and ./matrix-stack).
#
# Return values (via globals, readable by the caller):
#   SCAN_FOUND_RESOURCES  – "true" if anything was found, otherwise "false"
#   SCAN_HAS_BLOCKER      – "true" if a system-service or port conflict was
#                           found (caller should abort / advise manual fix)
scan_and_remove_matrix_resources() {
    local extra_dir="${1:-}"
    local skip_prompt="${2:-false}"

    # ── Paths to scan ────────────────────────────────────────────────────────
    local STACK_PATHS=(
        "/opt/stacks/matrix-stack"
        "$(pwd)/matrix-stack"
    )
    if [ -n "$extra_dir" ] && [[ ! " ${STACK_PATHS[*]} " == *" $extra_dir "* ]]; then
        STACK_PATHS+=("$extra_dir")
    fi

    SCAN_FOUND_RESOURCES=false
    SCAN_HAS_BLOCKER=false
    local RESOURCE_LIST=()

    # ── Containers ───────────────────────────────────────────────────────────
    local MATRIX_IMAGES_PATTERN='matrixdotorg/synapse|element-hq/matrix-authentication-service|element-hq/element-call|matrix-org/sliding-sync|awesometechnologies/synapse-admin|vectorim/element-web|livekit/livekit-server|coturn/coturn|turt2live/matrix-media-repo|mautrix/'

    while IFS= read -r line; do
        local NAME IMAGE STATUS
        NAME=$(echo "$line"   | cut -d'|' -f1)
        IMAGE=$(echo "$line"  | cut -d'|' -f2)
        STATUS=$(echo "$line" | cut -d'|' -f3)
        if [ -n "$NAME" ]; then
            SCAN_FOUND_RESOURCES=true
            RESOURCE_LIST+=("container|$NAME|$IMAGE|$STATUS")
        fi
    done < <(
        docker ps -a --filter "label=com.docker.compose.project=matrix-stack" \
            --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null
        docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null \
            | grep -E "$MATRIX_IMAGES_PATTERN" \
            | grep -vFf <(
                docker ps -a --filter "label=com.docker.compose.project=matrix-stack" \
                    --format '{{.Names}}' 2>/dev/null || true
              ) 2>/dev/null || true
    )

    # Collect names for downstream inspection
    local DETECTED_CONTAINER_NAMES=()
    for entry in "${RESOURCE_LIST[@]}"; do
        [[ "$entry" == container\|* ]] && DETECTED_CONTAINER_NAMES+=("$(echo "$entry" | cut -d'|' -f2)")
    done

    # ── Volumes ──────────────────────────────────────────────────────────────
    declare -A _SEEN_VOL
    while IFS= read -r vol; do
        if [ -n "$vol" ] && [ -z "${_SEEN_VOL[$vol]+x}" ]; then
            _SEEN_VOL[$vol]=1
            SCAN_FOUND_RESOURCES=true
            RESOURCE_LIST+=("volume|$vol")
        fi
    done < <(docker volume ls --filter "label=com.docker.compose.project=matrix-stack" \
        --format '{{.Name}}' 2>/dev/null || true)

    for cname in "${DETECTED_CONTAINER_NAMES[@]}"; do
        while IFS= read -r vol; do
            if [ -n "$vol" ] && [ -z "${_SEEN_VOL[$vol]+x}" ]; then
                _SEEN_VOL[$vol]=1
                SCAN_FOUND_RESOURCES=true
                RESOURCE_LIST+=("volume|$vol")
            fi
        done < <(docker inspect "$cname" \
            --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' \
            2>/dev/null || true)
    done
    unset _SEEN_VOL

    # ── Networks ─────────────────────────────────────────────────────────────
    declare -A _SEEN_NET
    while IFS= read -r net; do
        if [ -n "$net" ] && [ -z "${_SEEN_NET[$net]+x}" ]; then
            _SEEN_NET[$net]=1
            SCAN_FOUND_RESOURCES=true
            RESOURCE_LIST+=("network|$net")
        fi
    done < <(docker network ls --filter "label=com.docker.compose.project=matrix-stack" \
        --format '{{.Name}}' 2>/dev/null || true)

    for cname in "${DETECTED_CONTAINER_NAMES[@]}"; do
        while IFS= read -r net; do
            if [ -n "$net" ] && [ -z "${_SEEN_NET[$net]+x}" ] \
               && [[ "$net" != "bridge" ]] && [[ "$net" != "host" ]] && [[ "$net" != "none" ]]; then
                _SEEN_NET[$net]=1
                SCAN_FOUND_RESOURCES=true
                RESOURCE_LIST+=("network|$net")
            fi
        done < <(docker inspect "$cname" \
            --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' \
            2>/dev/null || true)
    done
    unset _SEEN_NET

    # ── Stack directories ────────────────────────────────────────────────────
    for path in "${STACK_PATHS[@]}"; do
        if [ -d "$path" ]; then
            SCAN_FOUND_RESOURCES=true
            RESOURCE_LIST+=("directory|$path")
            if [ -d "$path/bridges" ]; then
                for bridge_dir in "$path/bridges"/*/; do
                    [ -d "$bridge_dir" ] && RESOURCE_LIST+=("bridge|$(basename "$bridge_dir")|$path/bridges/$(basename "$bridge_dir")")
                done
            fi
        fi
    done

    # ── System services that conflict ────────────────────────────────────────
    local HAS_SYSTEM_SERVICE=false
    for svc in coturn turnserver; do
        if systemctl list-units --full -all 2>/dev/null | grep -q "${svc}.service"; then
            SCAN_FOUND_RESOURCES=true
            HAS_SYSTEM_SERVICE=true
            SCAN_HAS_BLOCKER=true
            RESOURCE_LIST+=("service|$svc")
        fi
    done

    # ── Port conflicts (non-Docker processes) ────────────────────────────────
    local HAS_PORT_CONFLICT=false
    for port in 3478 7880 8007 8008 8009 8010 8011 8012; do
        if ss -lpn 2>/dev/null | grep -q ":${port}" && \
           ! ss -lpn 2>/dev/null | grep ":${port}" | grep -q "docker-proxy"; then
            local proc proc_name
            proc=$(ss -lpn 2>/dev/null | grep ":${port}" | grep -v "docker-proxy" \
                   | awk '{print $NF}' | grep -oP 'pid=\K[0-9]+' | head -1)
            proc_name=""
            [ -n "$proc" ] && proc_name=$(cat /proc/$proc/comm 2>/dev/null || echo "unknown")
            SCAN_FOUND_RESOURCES=true
            HAS_PORT_CONFLICT=true
            SCAN_HAS_BLOCKER=true
            RESOURCE_LIST+=("port|$port|${proc_name:-unknown}")
        fi
    done

    # ── Display results ──────────────────────────────────────────────────────
    if [ "$SCAN_FOUND_RESOURCES" = true ]; then
        echo -e "\n${WARNING}[!] WARNING: Existing Matrix resources detected!${RESET}\n"
        printf "   ${INFO}%-28s %-12s %s${RESET}\n" "NAME" "STATUS" "IMAGE"
        printf "   ${INFO}%-28s %-12s %s${RESET}\n" "────────────────────────────" "────────────" "──────────────────────────────"

        for entry in "${RESOURCE_LIST[@]}"; do
            local TYPE
            TYPE=$(echo "$entry" | cut -d'|' -f1)
            case "$TYPE" in
                container)
                    local N I S SHORT_I SHORT_S
                    N=$(echo "$entry" | cut -d'|' -f2)
                    I=$(echo "$entry" | cut -d'|' -f3)
                    S=$(echo "$entry" | cut -d'|' -f4)
                    SHORT_I=$(echo "$I" | sed 's|.*/||')
                    SHORT_S=$(echo "$S" | sed 's/Up //' | sed 's/ (.*//' | cut -c1-10)
                    printf "   ${CONTAINER_NAME}%-28s${RESET} ${SUCCESS}%-12s${RESET} %s\n" "$N" "$SHORT_S" "$SHORT_I"
                    ;;
                volume)
                    local V
                    V=$(echo "$entry" | cut -d'|' -f2)
                    SHORT_V="${V:0:24}..."
                    printf "   ${DOCKER_COLOR}%-28s${RESET} ${WARNING}%-12s${RESET}\n" "$SHORT_V" "volume"
                    ;;
                network)
                    printf "   ${NETWORK_NAME}%-28s${RESET} ${WARNING}%-12s${RESET}\n" "$(echo "$entry" | cut -d'|' -f2)" "network"
                    ;;
                directory)
                    printf "   ${CONFIG_PATH}%-28s${RESET} ${WARNING}%-12s${RESET}\n" "$(echo "$entry" | cut -d'|' -f2)" "directory"
                    ;;
                bridge)
                    printf "   ${ACCENT}  ↳ %-25s${RESET} ${WARNING}%-12s${RESET} %s\n" "$(echo "$entry" | cut -d'|' -f2)" "bridge" "$(echo "$entry" | cut -d'|' -f3)"
                    ;;
                service)
                    printf "   ${ERROR}%-28s${RESET} ${WARNING}%-12s${RESET}\n" "$(echo "$entry" | cut -d'|' -f2)" "sys-service"
                    ;;
                port)
                    printf "   ${ERROR}%-28s${RESET} ${WARNING}%-12s${RESET} %s\n" ":$(echo "$entry" | cut -d'|' -f2)" "port-conflict" "process: $(echo "$entry" | cut -d'|' -f3)"
                    ;;
            esac
        done
        echo ""
    else
        echo -e "   ${SUCCESS}✓ No Matrix resources found${RESET}"
        return 0
    fi

    # ── Blocker: system services ─────────────────────────────────────────────
    if [ "$HAS_SYSTEM_SERVICE" = true ]; then
        echo -e "${WARNING}⚠️  System services detected — cannot be removed automatically.${RESET}"
        echo -e "${INFO}   Run these commands manually then re-run this script:${RESET}"
        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == service\|* ]] || continue
            local SVC
            SVC=$(echo "$entry" | cut -d'|' -f2)
            echo -e "   ${WARNING}sudo systemctl stop $SVC && sudo systemctl disable $SVC${RESET}"
        done
        return 0   # caller checks SCAN_HAS_BLOCKER
    fi

    # ── Blocker: port conflicts ───────────────────────────────────────────────
    if [ "$HAS_PORT_CONFLICT" = true ]; then
        echo -e "${WARNING}⚠️  Port conflicts detected — free these ports then re-run this script.${RESET}"
        echo -e "${INFO}   Identify the process:  ${WARNING}sudo lsof -i :<port>${RESET}"
        echo -e "${INFO}   Kill the process:      ${WARNING}sudo kill -9 <PID>${RESET}"
        return 0   # caller checks SCAN_HAS_BLOCKER
    fi

    # ── Prompt and remove ────────────────────────────────────────────────────
    if [ "$skip_prompt" != "true" ]; then
        echo -ne "Remove ALL detected Docker resources listed above? (y/n): "
        read -r CLEAN_CONFIRM
        if [[ ! "$CLEAN_CONFIRM" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    if true; then
        echo -e "\n${ACCENT}>> Cleaning up Matrix resources...${RESET}"

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == container\|* ]] || continue
            local cname
            cname=$(echo "$entry" | cut -d'|' -f2)
            docker stop "$cname" >/dev/null 2>&1
            docker rm   "$cname" >/dev/null 2>&1 && echo -e "   ${REMOVED}✕${RESET} ${CONTAINER_NAME}$cname${RESET}"
        done

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == volume\|* ]] || continue
            local vol
            vol=$(echo "$entry" | cut -d'|' -f2)
            SHORT_VOL="${vol:0:24}..."
            docker volume rm "$vol" >/dev/null 2>&1 && echo -e "   ${REMOVED}✕${RESET} ${INFO}$SHORT_VOL${RESET} ${DOCKER_COLOR}(volume)${RESET}"
        done

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == network\|* ]] || continue
            local net
            net=$(echo "$entry" | cut -d'|' -f2)
            docker network rm "$net" >/dev/null 2>&1 && echo -e "   ${REMOVED}✕${RESET} ${NETWORK_NAME}$net${RESET} ${DOCKER_COLOR}(network)${RESET}"
        done

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == directory\|* ]] || continue
            local dir
            dir=$(echo "$entry" | cut -d'|' -f2)
            rm -rf "$dir" && echo -e "   ${REMOVED}✕${RESET} ${CONFIG_PATH}$dir${RESET} ${DOCKER_COLOR}(directory)${RESET}"
        done

        echo -e "\n   ${SUCCESS}✓ All detected Matrix resources removed${RESET}"
    fi
}

################################################################################
# PRE-INSTALL MENU FUNCTIONS                                                   #
################################################################################

run_uninstall() {
    draw_header
    echo -e "\n${ERROR}>> Uninstall - Remove Matrix Stack${RESET}"
    echo -e "${WARNING}   ⚠️  This will PERMANENTLY DELETE all Matrix data!${RESET}\n"
    
    UNINSTALL_DIR="/opt/stacks/matrix-stack"
    if [ -d "$UNINSTALL_DIR" ]; then
        echo -e "   ${SUCCESS}✓ Found installation at: ${INFO}$UNINSTALL_DIR${RESET}"
        
        # Show what will be deleted
        local subdirs=""
        [ -d "$UNINSTALL_DIR/synapse" ] && subdirs="$subdirs synapse"
        [ -d "$UNINSTALL_DIR/bridges" ] && subdirs="$subdirs bridges"
        [ -d "$UNINSTALL_DIR/mas" ] && subdirs="$subdirs mas"
        [ -d "$UNINSTALL_DIR/coturn" ] && subdirs="$subdirs coturn"
        [ -d "$UNINSTALL_DIR/livekit" ] && subdirs="$subdirs livekit"
        if [ -n "$subdirs" ]; then
            echo -e "   ${WARNING}Contains:${RESET}$subdirs"
        fi
    else
        echo -e "   ${WARNING}⚠️  Installation not found at default path${RESET}"
        echo -e "   ${INFO}Press Enter to return to menu, or enter custom path:${RESET}"
        echo -ne "   Path: ${WARNING}"
        read -r UNINSTALL_DIR
        echo -e "${RESET}"
        
        # If empty (just pressed Enter), return to menu
        if [ -z "$UNINSTALL_DIR" ]; then
            echo -e "\n   ${SUCCESS}✓ Returning to menu${RESET}"
            sleep 1
            return
        fi
        
        if [ ! -d "$UNINSTALL_DIR" ]; then
            echo -e "\n   ${ERROR}✗ Directory not found: $UNINSTALL_DIR${RESET}"
            echo -e "   ${INFO}Uninstall cancelled.${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
        fi
    fi
    
    echo -e "\n${WARNING}   Are you sure you want to continue?${RESET}"
    echo -e "   ${INFO}1)${RESET} ${ERROR}Yes, delete everything${RESET}"
    echo -e "   ${INFO}2)${RESET} ${SUCCESS}No, cancel and return to menu${RESET}"
    echo -e ""
    echo -ne "Selection (1-2): "
    read -r UNINSTALL_CONFIRM
    
    if [[ "$UNINSTALL_CONFIRM" != "1" ]]; then
        echo -e "\n   ${SUCCESS}✓ Uninstall cancelled${RESET}"
        echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
        read -r
        return
    fi
    
    echo -ne "\n   ${WARNING}Type ${ERROR}'DELETE'${RESET} to confirm: ${ERROR}"
    read -r CONFIRM_DELETE
    echo -ne "${RESET}"
    
    if [[ "$CONFIRM_DELETE" != "DELETE" ]]; then
        echo -e "\n   ${INFO}Uninstall cancelled.${RESET}"
        return
    fi
    
    echo -e "\n${ACCENT}>> Removing Matrix Stack...${RESET}"

    scan_and_remove_matrix_resources "$UNINSTALL_DIR" "true"
    
    echo -e "\n${SUCCESS}✓ Uninstall complete${RESET}"
    echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
    read -r
}

################################################################################
# ADD BRIDGES TO EXISTING INSTALLATION                                         #
################################################################################

run_add_bridges() {
    draw_header
    echo -e "\n${ACCENT}>> Add Bridges to Existing Installation${RESET}\n"
    
    BRIDGE_DIR="/opt/stacks/matrix-stack"
    if [ ! -d "$BRIDGE_DIR" ]; then
        echo -e "   ${WARNING}⚠️  Installation not found at default path${RESET}"
        echo -ne "   Enter path to matrix-stack directory: ${WARNING}"
        read -r BRIDGE_DIR
        echo -e "${RESET}"
        
        if [ ! -d "$BRIDGE_DIR" ]; then
            echo -e "\n   ${ERROR}✗ Directory not found: $BRIDGE_DIR${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
        fi
    fi
    
    echo -e "${SUCCESS}✓ Found installation at: ${INFO}$BRIDGE_DIR${RESET}\n"
    echo -e "${INFO}This feature is coming soon!${RESET}"
    echo -e "${INFO}For now, reinstall with bridges selected during initial setup.${RESET}"
    
    echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
    read -r
}

################################################################################
# LOGS VIEWER FUNCTION                                                         #
################################################################################

run_logs() {
    draw_header
    echo -e "\n${ACCENT}>> View Container Logs${RESET}\n"
    
    LOGS_DIR="/opt/stacks/matrix-stack"
    if [ ! -d "$LOGS_DIR" ]; then
        echo -e "   ${WARNING}⚠️  Installation not found at default path${RESET}"
        echo -ne "   Enter path to matrix-stack directory: ${WARNING}"
        read -r LOGS_DIR
        echo -e "${RESET}"
        
        if [ ! -d "$LOGS_DIR" ]; then
            echo -e "\n   ${ERROR}✗ Directory not found: $LOGS_DIR${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
        fi
    fi
    
    echo -e "${SUCCESS}✓ Found installation at: ${INFO}$LOGS_DIR${RESET}\n"
    
    echo -e "${ACCENT}Select container to view logs:${RESET}\n"
    echo -e "   ${CHOICE_COLOR}1)${RESET} Synapse        — Matrix homeserver"
    echo -e "   ${CHOICE_COLOR}2)${RESET} PostgreSQL     — Database"
    echo -e "   ${CHOICE_COLOR}3)${RESET} MAS            — Authentication service"
    echo -e "   ${CHOICE_COLOR}4)${RESET} LiveKit        — Video SFU"
    echo -e "   ${CHOICE_COLOR}5)${RESET} Coturn         — TURN server"
    echo -e "   ${CHOICE_COLOR}6)${RESET} Element Call   — Video conferencing"
    echo -e "   ${CHOICE_COLOR}7)${RESET} Sliding Sync   — Sync proxy (if enabled)"
    echo -e "   ${CHOICE_COLOR}8)${RESET} All containers — Show all logs"
    echo -e ""
    echo -ne "Selection (1-8): "
    read -r LOG_SELECT
    
    case $LOG_SELECT in
        1) CONTAINER="synapse" ;;
        2) CONTAINER="synapse-db" ;;
        3) CONTAINER="matrix-auth" ;;
        4) CONTAINER="livekit" ;;
        5) CONTAINER="coturn" ;;
        6) CONTAINER="element-call" ;;
        7) CONTAINER="sliding-sync" ;;
        8) 
            echo -e "\n${INFO}Showing logs for all containers (Ctrl-C to stop)...${RESET}\n"
            cd "$LOGS_DIR" && docker compose logs -f
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
            ;;
        *)
            echo -e "\n${ERROR}Invalid selection${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
            ;;
    esac
    
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER}$"; then
        echo -e "\n${INFO}Showing logs for ${CONTAINER} (Ctrl-C to stop)...${RESET}\n"
        docker logs -f "$CONTAINER" --tail 100
    else
        echo -e "\n${ERROR}✗ Container not found or not running: $CONTAINER${RESET}"
    fi
    
    echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
    read -r
}

################################################################################
# VERIFY FUNCTION                                                              #
################################################################################

run_verify() {
    draw_header
    echo -e "\n${ACCENT}>> Verify Matrix Stack Installation${RESET}\n"
    
    VERIFY_DIR="/opt/stacks/matrix-stack"
    if [ ! -d "$VERIFY_DIR" ]; then
        echo -ne "   Enter path to matrix-stack directory: ${WARNING}"
        read -r VERIFY_DIR
        echo -e "${RESET}"
    fi
    
    if [ ! -d "$VERIFY_DIR" ]; then
        echo -e "   ${ERROR}✗ Directory not found${RESET}"
        echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
        read -r
        return
    fi
    
    echo -e "${SUCCESS}✓ Installation directory found${RESET}\n"
    
    echo -e "${ACCENT}Container Status:${RESET}"
    # Check actual container names (synapse-db not postgres)
    local containers=("synapse" "synapse-db" "matrix-auth" "livekit" "coturn" "element-call")
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            echo -e "   ${SUCCESS}✓${RESET} $container ${SUCCESS}(running)${RESET}"
        elif docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            echo -e "   ${WARNING}⚠${RESET}  $container ${WARNING}(stopped)${RESET}"
        else
            echo -e "   ${ERROR}✗${RESET} $container ${ERROR}(not found)${RESET}"
        fi
    done
    
    echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
    read -r
}

################################################################################
# MAIN DEPLOYMENT FUNCTION                                                     #
################################################################################

main_deployment() {
    # Require root privileges
    [[ $EUID -ne 0 ]] && { 
        echo -e "${ERROR}[!] This script must be run as root (sudo).${RESET}"
        exit 1
    }

    draw_header
    
    # Check for script updates
    check_for_updates

    ############################################################################
    # STEP 1: System Updates & Dependencies                                   #
    ############################################################################
    
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
    local deps=("curl" "wget" "openssl" "jq" "logrotate")
    local coreutils_check=$(dpkg-query -W -f='${Status}' coreutils 2>/dev/null | grep -c "ok installed" || echo "0")
    local to_install=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1 && [ "$dep" != "logrotate" ]; then
            to_install+=("$dep")
        fi
    done
    
    if ! command -v logrotate >/dev/null 2>&1 && ! dpkg-query -W -f='${Status}' logrotate 2>/dev/null | grep -q "ok installed"; then
        to_install+=("logrotate")
    fi
    
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

    ############################################################################
    # STEP 2: Docker Environment Audit                                        #
    ############################################################################
    
    echo -e "\n${ACCENT}>> Auditing Docker environment...${RESET}"
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

    ############################################################################
    # STEP 3: Network Detection                                               #
    ############################################################################
    
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

    ############################################################################
    # STEP 4: Smart Conflict Detection & Cleanup                              #
    ############################################################################

    echo -e "\n${ACCENT}>> Scanning for existing Matrix resources...${RESET}"

    scan_and_remove_matrix_resources

    if [ "$SCAN_HAS_BLOCKER" = true ]; then
        exit 1
    fi

    ############################################################################
        # STEP 5: Deployment Path Selection                                       #
    ############################################################################
    
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

    # Handle existing directory
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
            # Comprehensive cleanup
            if [ -f "$TARGET_DIR/compose.yaml" ] || [ -f "$TARGET_DIR/docker-compose.yaml" ]; then
                cd "$TARGET_DIR"
                docker compose down -v --remove-orphans 2>/dev/null || true
                # Clean up any remaining containers (including all possible bridges)
                docker rm -f synapse synapse-db synapse-admin matrix-auth coturn livekit element-call sliding-sync matrix-media-repo \
                    matrix-bridge-discord matrix-bridge-telegram matrix-bridge-whatsapp matrix-bridge-signal matrix-bridge-slack matrix-bridge-instagram 2>/dev/null || true
                # Clean up network
                docker network rm matrix-net 2>/dev/null || true
            fi
            rm -rf "$TARGET_DIR"
            echo -e "   ${SUCCESS}✓ Directory wiped clean${RESET}"
        else
            echo -e "${WARNING}Exiting to protect data.${RESET}"
            exit 0
        fi
    fi

    # Create directory structure
    mkdir -p "$TARGET_DIR/synapse" \
             "$TARGET_DIR/postgres_data" \
             "$TARGET_DIR/postgres_init" \
             "$TARGET_DIR/coturn" \
             "$TARGET_DIR/livekit" \
             "$TARGET_DIR/element-call" \
             "$TARGET_DIR/mas"

    ############################################################################
    # STEP 6: Service Configuration                                           #
    ############################################################################
    
echo -e "\n${ACCENT}>> Configuring services...${RESET}"

# Domain configuration
echo -ne "Base Domain (e.g., example.com): ${WARNING}"
read -r DOMAIN
echo -e "${RESET}"

echo ""  # Blank line before first subdomain
echo -ne "Matrix Subdomain [matrix]: ${WARNING}"
read -r SUB_MATRIX
if [ -z "$SUB_MATRIX" ]; then
    SUB_MATRIX="matrix"
    echo -ne "\033[1A\033[K"  # Move up one line and clear it
    echo -e "${RESET}Matrix Subdomain [matrix]: ${WARNING}${SUB_MATRIX}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""  # Blank line before second subdomain
echo -ne "Element Call Subdomain [call]: ${WARNING}"
read -r SUB_CALL
if [ -z "$SUB_CALL" ]; then
    SUB_CALL="call"
    echo -ne "\033[1A\033[K"  # Move up one line and clear it
    echo -e "${RESET}Element Call Subdomain [call]: ${WARNING}${SUB_CALL}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""  # Blank line before third subdomain
echo -ne "MAS (Auth) Subdomain [auth]: ${WARNING}"
read -r SUB_MAS
if [ -z "$SUB_MAS" ]; then
    SUB_MAS="auth"
    echo -ne "\033[1A\033[K"  # Move up one line and clear it
    echo -e "${RESET}MAS (Auth) Subdomain [auth]: ${WARNING}${SUB_MAS}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""  # Blank line before livekit subdomain
echo -ne "LiveKit Subdomain [livekit]: ${WARNING}"
read -r SUB_LIVEKIT
if [ -z "$SUB_LIVEKIT" ]; then
    SUB_LIVEKIT="livekit"
    echo -ne "\033[1A\033[K"
    echo -e "${RESET}LiveKit Subdomain [livekit]: ${WARNING}${SUB_LIVEKIT}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""  # Blank line before element subdomain
echo -ne "Element Web Subdomain [element]: ${WARNING}"
read -r SUB_ELEMENT
if [ -z "$SUB_ELEMENT" ]; then
    SUB_ELEMENT="element"
    echo -ne "\033[1A\033[K"  # Move up one line and clear it
    echo -e "${RESET}Element Web Subdomain [element]: ${WARNING}${SUB_ELEMENT}${RESET}"
else
    echo -ne "${RESET}"
fi

# Optional services - set automatically if enabled
SUB_SLIDING_SYNC="sync"
SUB_MEDIA_REPO="media"

# Clear input buffer
while read -r -t 0; do read -r; done

# Server name configuration
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
    
    # Admin user configuration
    echo ""
    echo -ne "Admin Username [admin]: ${WARNING}"
    read -r ADMIN_USER
    if [ -z "$ADMIN_USER" ]; then
        ADMIN_USER="admin"
        echo -ne "\033[1A\033[K"  # Move up one line and clear it
        echo -e "${RESET}Admin Username [admin]: ${WARNING}${ADMIN_USER}${RESET}"
    else
        echo -ne "${RESET}"
    fi
    
    # Admin password configuration
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
    
    # Registration configuration (for MAS)
    echo -e "\n${ACCENT}Registration & Authentication Configuration:${RESET}"
    echo -e "   ${INFO}MAS (Matrix Authentication Service) handles user registration and authentication.${RESET}"
    echo -e "   ${WARNING}Allow new users to register without admin approval?${RESET}"
    echo -e "   • ${SUCCESS}Enable registration (y):${RESET} Users can create accounts freely"
    echo -e "   • ${ERROR}Disable registration (n):${RESET} Only admin can create users (recommended)"
    echo -ne "Allow public registration? [n]: "
    read -r ALLOW_REGISTRATION
    ALLOW_REGISTRATION=${ALLOW_REGISTRATION:-n}
    
    # Initialize email/SMTP variables
    REQUIRE_EMAIL_VERIFICATION="n"
    SMTP_HOST=""
    SMTP_PORT="587"
    SMTP_USER=""
    SMTP_PASS=""
    SMTP_FROM=""
    ENABLE_CAPTCHA="n"
    
    if [[ "$ALLOW_REGISTRATION" =~ ^[Yy]$ ]]; then
        MAS_REGISTRATION="true"
        
        # Email verification (optional)
        echo -e "\n${ACCENT}Email Verification:${RESET}"
        echo -e "   ${INFO}Require email verification for new registrations?${RESET}"
        echo -e "   • ${SUCCESS}Enable (y):${RESET} Users must verify email (more secure)"
        echo -e "   • ${ERROR}Disable (n):${RESET} Users can register immediately"
        echo -ne "Require email verification? [n]: "
        read -r REQUIRE_EMAIL_VERIFICATION
        REQUIRE_EMAIL_VERIFICATION=${REQUIRE_EMAIL_VERIFICATION:-n}
        
        # SMTP configuration (only if email verification enabled)
        if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then
            echo -e "\n${ACCENT}SMTP Email Configuration:${RESET}"
            echo -e "   ${INFO}Configure SMTP to send verification emails.${RESET}"
            echo -ne "SMTP Server (e.g., smtp.gmail.com): "
            read -r SMTP_HOST
            echo -ne "SMTP Port [587]: "
            read -r SMTP_PORT_INPUT
            SMTP_PORT=${SMTP_PORT_INPUT:-587}
            echo -ne "SMTP Username: "
            read -r SMTP_USER
            echo -ne "SMTP Password: "
            read -s SMTP_PASS
            echo ""
            echo -ne "From Email Address [noreply@$DOMAIN]: "
            read -r SMTP_FROM
            SMTP_FROM=${SMTP_FROM:-noreply@$DOMAIN}
            echo -e "   ${SUCCESS}✓ SMTP configured${RESET}"
        fi
        
        # CAPTCHA configuration (only if email verification is enabled)
        if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then
            echo -e "\n${ACCENT}CAPTCHA Protection:${RESET}"
            echo -e "   ${INFO}CAPTCHA helps prevent bot registrations.${RESET}"
            echo -ne "Enable CAPTCHA? [y]: "
            read -r ENABLE_CAPTCHA
            ENABLE_CAPTCHA=${ENABLE_CAPTCHA:-y}
            
            if [[ "$ENABLE_CAPTCHA" =~ ^[Yy]$ ]]; then
                echo -e "   ${SUCCESS}✓ CAPTCHA enabled${RESET}"
                echo -e "   ${INFO}ℹ  Get reCAPTCHA keys at: https://www.google.com/recaptcha/admin${RESET}"
                echo -e "   ${INFO}ℹ  You'll add keys to MAS config after installation${RESET}"
            fi
        else
            # No email verification = no CAPTCHA needed
            ENABLE_CAPTCHA="n"
        fi
    else
        MAS_REGISTRATION="false"
        ENABLE_CAPTCHA="n"
        echo -e "   ${REGISTRATION_DISABLED}✓ Registration disabled - admin will create users via MAS${RESET}"
    fi
    
    # TURN LAN access configuration
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
    
    if [[ "$TURN_LAN_ACCESS" =~ ^[Yy]$ ]]; then
        echo -e "   ${SUCCESS}✓ TURN LAN access: ENABLED${RESET} (local networks accessible)"
    else
        echo -e "   ${ERROR}✓ TURN LAN access: DISABLED${RESET} (secure - production recommended)"
    fi
    
    # Sliding Sync Proxy
    echo -e "\n${ACCENT}Sliding Sync Proxy:${RESET}"
    echo -e "   ${INFO}Sliding Sync enables faster sync for modern Matrix clients (Element X, etc.)${RESET}"
    echo -ne "Enable Sliding Sync Proxy? [y]: "
    read -r ENABLE_SLIDING_SYNC
    ENABLE_SLIDING_SYNC=${ENABLE_SLIDING_SYNC:-y}
    
    if [[ "$ENABLE_SLIDING_SYNC" =~ ^[Yy]$ ]]; then
        SLIDING_SYNC_ENABLED="true"
        echo -e "   ${SUCCESS}✓ Sliding Sync Proxy will be added${RESET}"
    else
        SLIDING_SYNC_ENABLED="false"
        echo -e "   ${WARNING}⚠️  Some modern clients may not work optimally without Sliding Sync${RESET}"
    fi
    
    # Matrix Media Repo
    echo -e "\n${ACCENT}Matrix Media Repository:${RESET}"
    echo -e "   ${INFO}Matrix Media Repo is a highly efficient media server for Matrix${RESET}"
    echo -e "   ${INFO}Features: S3 storage, thumbnailing, advanced media management${RESET}"
    echo -ne "Enable Matrix Media Repo? [n]: "
    read -r ENABLE_MEDIA_REPO
    ENABLE_MEDIA_REPO=${ENABLE_MEDIA_REPO:-n}
    
    if [[ "$ENABLE_MEDIA_REPO" =~ ^[Yy]$ ]]; then
        MEDIA_REPO_ENABLED="true"
        echo -e "   ${SUCCESS}✓ Matrix Media Repo will be added${RESET}"
        echo -e "   ${INFO}ℹ  Configure storage backend after installation${RESET}"
    else
        MEDIA_REPO_ENABLED="false"
        echo -e "   ${INFO}Using Synapse's built-in media storage${RESET}"
    fi
    
    # Bridge Selection
    echo -e "\n${ACCENT}Matrix Bridges:${RESET}"
    echo -e "   ${INFO}Bridges connect Matrix to other chat platforms (Discord, Telegram, WhatsApp, etc.)${RESET}"
    echo -e "   ${INFO}Each bridge allows you to chat with users on that platform from Matrix${RESET}"
    echo -ne "\nWould you like to add bridges? [y/n]: "
    read -r ADD_BRIDGES
    
    SELECTED_BRIDGES=()
    
    if [[ "$ADD_BRIDGES" =~ ^[Yy]$ ]]; then
        # Check if dialog or whiptail is available
        if command -v whiptail &> /dev/null; then
            DIALOG_CMD="whiptail"
        elif command -v dialog &> /dev/null; then
            DIALOG_CMD="dialog"
        else
            echo -e "   ${WARNING}⚠️  Installing whiptail for interactive menu...${RESET}"
            apt-get update -qq && apt-get install -y whiptail -qq > /dev/null 2>&1
            DIALOG_CMD="whiptail"
        fi
        
        # Loop until user confirms or cancels
        while true; do
            # Build checklist options
            BRIDGE_SELECTION=$($DIALOG_CMD --title "Matrix Bridge Selection" \
                --checklist "Select bridges to install (SPACE to toggle, ENTER to confirm):" \
                20 78 10 \
                "discord" "Discord - Connect to Discord servers" OFF \
                "telegram" "Telegram - Connect to Telegram chats" OFF \
                "whatsapp" "WhatsApp - Connect to WhatsApp (requires phone)" OFF \
                "signal" "Signal - Connect to Signal (requires phone)" OFF \
                "slack" "Slack - Connect to Slack workspaces" OFF \
                "instagram" "Instagram - Connect to Instagram DMs" OFF \
                3>&1 1>&2 2>&3)
            
            # Check if user cancelled
            if [ $? -ne 0 ]; then
                echo -e "\n   ${INFO}Bridge selection cancelled${RESET}"
                echo -ne "   Would you like to select bridges again? [y/n]: "
                read -r RETRY_BRIDGES
                if [[ ! "$RETRY_BRIDGES" =~ ^[Yy]$ ]]; then
                    break
                fi
            else
                # Parse selected bridges
                SELECTED_BRIDGES=($(echo $BRIDGE_SELECTION | tr -d '"'))
                
                if [ ${#SELECTED_BRIDGES[@]} -eq 0 ]; then
                    echo -e "\n   ${INFO}No bridges selected${RESET}"
                else
                    echo -e "\n   ${SUCCESS}✓ Selected bridges:${RESET}"
                    for bridge in "${SELECTED_BRIDGES[@]}"; do
                        echo -e "     • $bridge"
                    done
                fi
                break
            fi
        done
    else
        echo -e "   ${INFO}No bridges will be installed${RESET}"
    fi
    
    # Do they already have a reverse proxy?
    echo -e "\n${ACCENT}Reverse Proxy Setup:${RESET}"
    echo -e "   ${CHOICE_COLOR}1)${RESET} Yes, I already have a reverse proxy running"
    echo -e "   ${CHOICE_COLOR}2)${RESET} No, I need one set up ${INFO}(type selected next)${RESET}"
    echo -ne "Selection (1/2): "
    read -r PROXY_EXISTING_SELECT
    PROXY_ALREADY_RUNNING=false
    [[ "$PROXY_EXISTING_SELECT" == "1" ]] && PROXY_ALREADY_RUNNING=true

    # Which reverse proxy?
    echo ""
    echo -e "${ACCENT}Reverse Proxy Type:${RESET}"
    echo -e "   ${CHOICE_COLOR}1)${RESET} Nginx Proxy Manager (NPM/NPMPlus)"
    echo -e "   ${CHOICE_COLOR}2)${RESET} Caddy"
    echo -e "   ${CHOICE_COLOR}3)${RESET} Traefik"
    echo -e "   ${CHOICE_COLOR}4)${RESET} Cloudflare Tunnel"
    echo -e "   ${CHOICE_COLOR}5)${RESET} Manual Setup"
    echo -ne "Selection (1-5): "
    read -r PROXY_SELECT

    case $PROXY_SELECT in
        1) PROXY_TYPE="npm" ;;
        2) PROXY_TYPE="caddy" ;;
        3) PROXY_TYPE="traefik" ;;
        4) PROXY_TYPE="cloudflare" ;;
        *) PROXY_TYPE="manual" ;;
    esac

    if [ "$PROXY_ALREADY_RUNNING" = false ] && [[ "$PROXY_TYPE" != "cloudflare" ]] && [[ "$PROXY_TYPE" != "manual" ]]; then
        echo -e "\n   ${WARNING}⚠️  This will add $PROXY_TYPE to your Docker stack and install it automatically.${RESET}"
    fi

    PROXY_IP="$AUTO_LOCAL_IP"
    
    # Generate secrets
    DB_NAME="synapse"
    DB_USER="synapse"
    DB_PASS=$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    TURN_SECRET=$(openssl rand -hex 32)
    REG_SECRET=$(openssl rand -hex 32)
    MAS_SECRET=$(openssl rand -hex 32)
    # MAS encryption secret MUST be hex, not base64
    MAS_ENCRYPTION_SECRET=$(openssl rand -hex 32)
    LK_API_KEY=$(openssl rand -hex 16)
    LK_API_SECRET=$(openssl rand -hex 32)
    
    # Function to generate a proper random ULID
    generate_ulid() {
        local ulid=""
        while [ ${#ulid} -lt 26 ]; do
            local chunk=$(openssl rand -base64 32 2>/dev/null | tr -dc '0-9A-Z' | tr -d 'ILOU')
            ulid="${ulid}${chunk}"
        done
        echo "$ulid" | cut -c1-26
    }
    
    # Generate a random ULID for Element Call (make it available globally)
    ELEMENT_CALL_CLIENT_ID=$(generate_ulid)
    ELEMENT_WEB_CLIENT_ID=$(generate_ulid)
    
    # Sliding Sync secret (if enabled)
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        SLIDING_SYNC_SECRET=$(openssl rand -hex 32)
    fi

    # NPM admin password (if auto-installing NPM)
    if [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "npm" ]]; then
        NPM_ADMIN_PASS=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)
        NPM_ADMIN_EMAIL="admin@${DOMAIN}"
    fi

    ############################################################################
    # STEP 7: Generate All Configuration Files                                #
    ############################################################################
    
    generate_coturn_config
    generate_livekit_config
    generate_element_call_config
    generate_element_web_config
    generate_bridge_configs
    generate_mas_config
    generate_postgres_init
    generate_docker_compose
    generate_synapse_config
    generate_wellknown_files
    if [ "$PROXY_ALREADY_RUNNING" = false ]; then
        setup_nginx_wellknown
    fi

    # Write proxy config files before containers start (Caddy/Traefik need them at boot)
    if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
        case "$PROXY_TYPE" in
            caddy)   caddy_autosetup ;;
            traefik) traefik_autosetup ;;
        esac
    fi

    ############################################################################
    # STEP 8: Deploy Stack                                                    #
    ############################################################################
    
    echo -e "\n${SUCCESS}>> Launching Matrix Stack...${RESET}"
    
    # Clean up any orphaned containers first
    cd "$TARGET_DIR" && docker compose down --remove-orphans 2>/dev/null || true
    
    # Start the stack
    cd "$TARGET_DIR" && docker compose up -d --quiet-pull
    
    # Brief pause for Docker networking and PostgreSQL init scripts
    # (PostgreSQL needs ~10-15s to create all 3 databases via init scripts)
    echo -e "   ${INFO}Waiting for PostgreSQL initialization...${RESET}"
    sleep 15

    ############################################################################
    # STEP 8.5: Comprehensive Health Checks                                   #
    ############################################################################
    
    echo -e "\n${ACCENT}>> Performing comprehensive health checks...${RESET}"

    # PostgreSQL health check — waits until synapse AND matrix_auth databases exist
    echo -ne "\n${WARNING}>> Checking PostgreSQL (2s polling)...${RESET}"
    TRIES=0
    until docker exec synapse-db psql -U synapse -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw matrix_auth; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 60 ]]; then
            echo -e "\n${ERROR}[!] ERROR: PostgreSQL / matrix_auth database failed to initialise.${RESET}"
            echo -e "${INFO}Check logs: docker logs synapse-db${RESET}"
            docker logs --tail 30 synapse-db 2>&1 | sed 's/^/   /'
            exit 1
        fi
    done
    echo -e "\n${SUCCESS}✓ PostgreSQL is ONLINE (synapse + matrix_auth databases ready)${RESET}"

    # MAS health check — must be confirmed before Synapse since Synapse depends on it
    echo -ne "\n${WARNING}>> Checking MAS (2s polling)...${RESET}"
    TRIES=0
    until curl -sf http://localhost:8081/health 2>/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 90 ]]; then
            echo -e "\n${ERROR}[!] ERROR: MAS failed to become healthy.${RESET}"
            echo -e "${INFO}Last 40 lines of MAS logs:${RESET}"
            docker logs --tail 40 matrix-auth 2>&1 | sed 's/^/   /'
            exit 1
        fi
    done
    echo -e "\n${SUCCESS}✓ MAS is ONLINE${RESET}"

    # Synapse health check
    echo -ne "\n${WARNING}>> Checking Synapse (2s polling)...${RESET}"
    TRIES=0
    until curl -sL --fail http://$AUTO_LOCAL_IP:8008/_matrix/client/versions 2>/dev/null | grep -q "versions"; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 150 ]]; then
            echo -e "\n${ERROR}[!] ERROR: Synapse failed to start.${RESET}"
            echo -e "${INFO}Last 40 lines of Synapse logs:${RESET}"
            docker logs --tail 40 synapse 2>&1 | sed 's/^/   /'
            exit 1
        fi
    done
    echo -e "\n${SUCCESS}✓ Synapse is ONLINE${RESET}"

    # LiveKit health check
    echo -ne "\n${WARNING}>> Checking LiveKit (2s polling)...${RESET}"
    TRIES=0
    until curl -s -f http://$AUTO_LOCAL_IP:7880 2>/dev/null >/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 30 ]]; then
            echo -e "\n${WARNING}⚠️  WARNING: LiveKit may not be ready${RESET}"
            break
        fi
    done
    if [[ $TRIES -lt 30 ]]; then
        echo -e "\n${SUCCESS}✓ LiveKit is ONLINE${RESET}"
    fi

    # Element Call health check
    echo -ne "\n${WARNING}>> Checking Element Call (2s polling)...${RESET}"
    TRIES=0
    until curl -s -f http://$AUTO_LOCAL_IP:8007 2>/dev/null >/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 30 ]]; then
            echo -e "\n${WARNING}⚠️  WARNING: Element Call may not be ready${RESET}"
            break
        fi
    done
    if [[ $TRIES -lt 30 ]]; then
        echo -e "\n${SUCCESS}✓ Element Call is ONLINE${RESET}"
    fi

    # Element Web health check
    echo -ne "\n${WARNING}>> Checking Element Web (2s polling)...${RESET}"
    TRIES=0
    until curl -s -f http://$AUTO_LOCAL_IP:8012 2>/dev/null >/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 30 ]]; then
            echo -e "\n${WARNING}⚠️  WARNING: Element Web may not be ready${RESET}"
            break
        fi
    done
    if [[ $TRIES -lt 30 ]]; then
        echo -e "\n${SUCCESS}✓ Element Web is ONLINE${RESET}"
    fi

    # Sliding Sync health check (if enabled)
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Sliding Sync (2s polling)...${RESET}"
        TRIES=0
        until (echo >/dev/tcp/localhost/8011) 2>/dev/null; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 30 ]]; then
                echo -e "\n${WARNING}⚠️  WARNING: Sliding Sync may not be ready${RESET}"
                break
            fi
        done
        if [[ $TRIES -lt 30 ]]; then
            echo -e "\n${SUCCESS}✓ Sliding Sync is ONLINE${RESET}"
        fi
    fi

    # Matrix Media Repo health check (if enabled)
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Matrix Media Repo (2s polling)...${RESET}"
        TRIES=0
        until curl -s -f http://$AUTO_LOCAL_IP:8013 2>/dev/null >/dev/null; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 30 ]]; then
                echo -e "\n${WARNING}⚠️  WARNING: Matrix Media Repo may not be ready${RESET}"
                break
            fi
        done
        if [[ $TRIES -lt 30 ]]; then
            echo -e "\n${SUCCESS}✓ Matrix Media Repo is ONLINE${RESET}"
        fi
    fi
    
    echo -e "\n${SUCCESS}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${SUCCESS}             ALL CRITICAL SERVICES ARE ONLINE               ${RESET}"
    echo -e "${SUCCESS}═══════════════════════════════════════════════════════════${RESET}"

    # Post-startup proxy configuration
    if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
        case "$PROXY_TYPE" in
            npm)
                # NPM needs API calls to create admin account after startup
                npm_autosetup
                ;;
            caddy)
                # Config was pre-written; just confirm Caddy is up
                echo -ne "\n   ${INFO}Waiting for Caddy${RESET}"
                for i in $(seq 1 15); do
                    curl -fsS -o /dev/null "http://localhost:2019/config/" 2>/dev/null && break
                    echo -ne "."; sleep 2
                done
                echo ""
                docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
                    echo -e "   ${SUCCESS}✓ Caddy running — HTTPS certificates will be requested automatically${RESET}" || \
                    echo -e "   ${INFO}ℹ  Caddy is starting — certificates will be requested shortly${RESET}"
                ;;
            traefik)
                # Config was pre-written; just confirm Traefik is up
                echo -ne "\n   ${INFO}Waiting for Traefik${RESET}"
                for i in $(seq 1 15); do
                    curl -fsS -o /dev/null "http://localhost:8080/api/overview" 2>/dev/null && break
                    echo -ne "."; sleep 2
                done
                echo ""
                echo -e "   ${SUCCESS}✓ Traefik running — dashboard: http://$AUTO_LOCAL_IP:8080${RESET}"
                echo -e "   ${SUCCESS}✓ TLS certificates will be requested automatically${RESET}"
                ;;
        esac
    fi

    ############################################################################
    # STEP 9: Create Admin User via MAS                                       #
    ############################################################################
    
    echo -e "\n${SUCCESS}>> Creating Admin user via MAS...${RESET}"
    
    # Wait for Synapse to fully initialize MAS endpoints
    echo -e "${INFO}   Waiting for Synapse MAS integration to initialize...${RESET}"
    sleep 10
    
    # Verify MAS endpoint is available in Synapse
    TRIES=0
    until docker exec synapse curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8008/_synapse/mas/health 2>/dev/null | grep -q '^2' || [ $TRIES -ge 6 ]; do
        echo -ne "."
        sleep 5
        ((TRIES++))
    done
    echo ""
    
    # MAS CLI syntax: register-user [USERNAME] --password <pass> --admin
    echo -e "${INFO}   Registering admin user...${RESET}"
    REGISTER_OUTPUT=$(docker exec matrix-auth mas-cli manage register-user "$ADMIN_USER" \
        --password "$ADMIN_PASS" \
        --admin \
        --yes \
        --ignore-password-complexity 2>&1)
    
    if echo "$REGISTER_OUTPUT" | grep -qiE "success|registered|created|user.*added"; then
        echo -e "${SUCCESS}✓ Admin user created: @$ADMIN_USER:$SERVER_NAME${RESET}"
        echo -e "${SUCCESS}✓ User has admin privileges${RESET}"
    elif echo "$REGISTER_OUTPUT" | grep -qi "already exists"; then
        echo -e "${INFO}ℹ  User already exists: @$ADMIN_USER:$SERVER_NAME${RESET}"
        # Try to ensure admin privileges
        USER_ID=$(docker exec matrix-auth mas-cli manage list-users 2>&1 | grep -A10 "$ADMIN_USER" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
        if [ -n "$USER_ID" ]; then
            echo -e "${INFO}   Ensuring admin privileges...${RESET}"
            docker exec matrix-auth mas-cli manage set-admin "$USER_ID" 2>&1 >/dev/null
            echo -e "${SUCCESS}✓ Admin privileges confirmed${RESET}"
        fi
    else
        echo -e "${ERROR}✗ Failed to register user. Output:${RESET}"
        echo "$REGISTER_OUTPUT"
        echo -e "\n${INFO}Create the admin user manually:${RESET}"
        echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user $ADMIN_USER --password YOUR_PASSWORD --admin --yes${RESET}"
        echo -e "   Or via web: ${WARNING}https://$SUB_MAS.$DOMAIN${RESET}"
    fi
    
    # Verify admin user exists
    sleep 2
    if docker exec matrix-auth mas-cli manage list-admin-users 2>&1 | grep -q "$ADMIN_USER"; then
        echo -e "${SUCCESS}✓ Verification: User exists in MAS database${RESET}"
    else
        # Try alternative method - check if user can be found via other means
        echo -e "${INFO}ℹ  User verification via list-admin-users inconclusive.${RESET}"
        echo -e "${INFO}   Testing login with credentials...${RESET}"
        
        # Test if we can get a token (this is a basic connectivity test)
        if curl -s -o /dev/null -w "%{http_code}" https://$SUB_MAS.$DOMAIN/ | grep -q "200"; then
            echo -e "${SUCCESS}✓ MAS is reachable at https://$SUB_MAS.$DOMAIN${RESET}"
            echo -e "${INFO}   Try logging in manually at: https://$SUB_MAS.$DOMAIN${RESET}"
            echo -e "${INFO}   Username: $ADMIN_USER${RESET}"
            if [ "$PASS_IS_CUSTOM" = false ]; then
                echo -e "${INFO}   Password: $ADMIN_PASS${RESET}"
            fi
        else
            echo -e "${WARNING}⚠️  MAS web interface not yet reachable${RESET}"
        fi
        
        echo -e "${INFO}   Manual check command: ${WARNING}docker exec matrix-auth mas-cli manage list-admin-users${RESET}"
    fi
    
    rm -f /tmp/mas_register.log

    ############################################################################
    # STEP 10: Display Proxy Configuration Guides                             #
    ############################################################################

    if [[ "$PROXY_TYPE" == "npm" ]]; then
        if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
            # Auto-installed: NPM is up but proxy hosts still need to be created manually
            echo -e "\n${ACCENT}NPM is running. You still need to add each proxy host in the web UI.${RESET}"
            echo -e "${ACCENT}Would you like the step-by-step guide for that now? (y/n):${RESET} "
            read -r SHOW_GUIDE
            [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_npm_guide
        else
            echo -e "\n${ACCENT}Would you like guided setup for Nginx Proxy Manager? (y/n):${RESET} "
            read -r SHOW_GUIDE
            [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_npm_guide
        fi
    elif [[ "$PROXY_TYPE" == "caddy" ]]; then
        if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
            # Auto-installed: Caddyfile was fully written — no manual steps needed
            echo -e "\n${SUCCESS}✓ Caddy config was written automatically — no manual setup required.${RESET}"
            echo -e "   ${INFO}Config location: ${CONFIG_PATH}$TARGET_DIR/caddy/Caddyfile${RESET}"
            echo -e "${ACCENT}Would you like to review the generated config? (y/n):${RESET} "
            read -r SHOW_GUIDE
            [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_caddy_guide
        else
            echo -e "\n${ACCENT}Would you like guided setup for Caddy? (y/n):${RESET} "
            read -r SHOW_GUIDE
            [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_caddy_guide
        fi
    elif [[ "$PROXY_TYPE" == "traefik" ]]; then
        if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
            # Auto-installed: traefik.yml + dynamic.yml fully written — no manual steps needed
            echo -e "\n${SUCCESS}✓ Traefik config was written automatically — no manual setup required.${RESET}"
            echo -e "   ${INFO}Static:  ${CONFIG_PATH}$TARGET_DIR/traefik/traefik.yml${RESET}"
            echo -e "   ${INFO}Dynamic: ${CONFIG_PATH}$TARGET_DIR/traefik/dynamic.yml${RESET}"
            echo -e "${ACCENT}Would you like to review the generated config? (y/n):${RESET} "
            read -r SHOW_GUIDE
            [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_traefik_guide
        else
            echo -e "\n${ACCENT}Would you like guided setup for Traefik? (y/n):${RESET} "
            read -r SHOW_GUIDE
            [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_traefik_guide
        fi
    elif [[ "$PROXY_TYPE" == "cloudflare" ]]; then
        echo -e "\n${ACCENT}Would you like guided setup for Cloudflare Tunnel? (y/n):${RESET} "
        read -r SHOW_GUIDE
        [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_cloudflare_guide
    fi

    ############################################################################
    # STEP 10: Log Rotation Configuration                                     #
    ############################################################################
    
    echo -e "\n${ACCENT}>> Log Rotation Configuration${RESET}"
    echo -e "   ${INFO}Docker containers can generate large amounts of logs that may fill up your disk.${RESET}"
    echo -e "   ${INFO}Log rotation helps manage this by automatically rotating and compressing logs.${RESET}"
    echo -e ""
    echo -e "   ${WARNING}⚠️  Recommendation: Enable log rotation to prevent disk space issues${RESET}"
    echo -e "   • ${SUCCESS}Enable log rotation (y):${RESET} Configure automatic log rotation for all containers"
    echo -e "   • ${ERROR}Disable log rotation (n):${RESET} Leave logs as-is (may fill up disk over time)"
    echo -ne "Setup log rotation to prevent disk space issues? (default: y): "
    read -r SETUP_LOG_ROTATION
    SETUP_LOG_ROTATION=${SETUP_LOG_ROTATION:-y}
    
    if [[ "$SETUP_LOG_ROTATION" =~ ^[Yy]$ ]]; then
        setup_log_rotation
    else
        echo -e "   ${WARNING}⚠️  Log rotation skipped - monitor disk space manually${RESET}"
    fi

    ############################################################################
    # STEP 11: Display Deployment Summary                                     #
    ############################################################################
    
    draw_footer
    save_credentials_prompt
}

################################################################################
# SCRIPT ENTRY POINT                                                           #
################################################################################

# Check for updates
check_for_updates

# Pre-install menu
draw_header
# Pre-install menu with loop for invalid selections
while true; do
    echo -e "\n${ACCENT}>> What would you like to do?${RESET}\n"
    echo -e "   ${INFO}1)${RESET} ${SUCCESS}Install${RESET}   — Deploy a new Matrix stack"
    echo -e "   ${INFO}2)${RESET} ${SUCCESS}Update${RESET}    — Pull latest images and restart the stack"
    echo -e "   ${INFO}3)${RESET} ${SUCCESS}Uninstall${RESET} — Remove the Matrix stack and all data"
    echo -e "   ${INFO}4)${RESET} ${SUCCESS}Verify${RESET}    — Check integrity of an existing installation"
    echo -e "   ${INFO}5)${RESET} ${SUCCESS}Bridges${RESET}   — Add or manage bridges to existing installation"
    echo -e "   ${INFO}6)${RESET} ${WARNING}Logs${RESET}      — View container logs for troubleshooting"
    echo -e ""
    echo -e "   ${INFO}0)${RESET} ${ERROR}Exit${RESET}"
    echo -e ""
    echo -ne "Selection (0-6): "
    read -r MENU_SELECT

    case $MENU_SELECT in
        0)
            echo -e "\n${INFO}Exiting...${RESET}"
            exit 0
            ;;
        1)
            # Install - Deploy new stack
            main_deployment "$1"
            break
            ;;
        2)
            draw_header
            echo -e "\n${ACCENT}>> Update - Pull latest images and restart stack${RESET}"
            UPDATE_STACK_DIR="/opt/stacks/matrix-stack"
            if [ ! -d "$UPDATE_STACK_DIR" ]; then
                echo -ne "   Enter path to matrix-stack directory: ${WARNING}"
                read -r UPDATE_STACK_DIR
                echo -e "${RESET}"
            fi
            if [ ! -f "$UPDATE_STACK_DIR/compose.yaml" ]; then
                echo -e "   ${ERROR}No compose.yaml found at $UPDATE_STACK_DIR${RESET}"
                exit 1
            fi
            echo -e "   ${INFO}Pulling latest images...${RESET}"
            cd "$UPDATE_STACK_DIR" && docker compose pull
            echo -e "   ${INFO}Restarting stack...${RESET}"
            docker compose up -d --remove-orphans
            echo -e "\n${SUCCESS}>> Update complete.${RESET}"
            exit 0
            ;;
        3)
            run_uninstall
            draw_header
            ;;
        4)
            run_verify
            draw_header
            ;;
        5)
            run_add_bridges
            draw_header
            ;;
        6)
            run_logs
            draw_header
            ;;
        *)
            # Invalid selection - loop back to menu
            echo -e "\n${ERROR}Invalid selection. Please choose 0-6.${RESET}"
            sleep 2
            draw_header
            ;;
    esac
done

################################################################################
#                         END OF SCRIPT                                        #
################################################################################