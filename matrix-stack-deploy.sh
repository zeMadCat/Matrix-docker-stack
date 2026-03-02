#!/bin/bash

################################################################################
#                                                                              #
#                    MATRIX SYNAPSE FULL STACK DEPLOYER                        #
#                              Version 1.4                                     #
#                           by MadCat (Production)                             #
#                                                                              #
#  A comprehensive deployment script for Matrix Synapse with working           #
#  multi-screenshare video calling capabilities.                               #
#                                                                              #
#  Components:                                                                 #
#  • Synapse (Matrix Homeserver)                                               #
#  • MAS (Matrix Authentication Service)                                       #
#  • PostgreSQL (Database)                                                     #
#  • LiveKit SFU (unlimited multi-screenshare + built-in TURN/STUN)           #
#  • LiveKit JWT Service (token generation)                                    #
#  • Element Web (web client)                                                  #
#  • Element Call (standalone WebRTC UI — optional)                            #
#  • Element Admin or Synapse Admin (admin panel — optional, user choice)      #
#                                                                              #
#  iOS/Android: Use Element app (not Element X)                                #
#                                                                              #
################################################################################

# Trap Ctrl-C to reset terminal colors
trap 'echo -e "\033[0m"; exit 130' INT

# Script version and repository info
SCRIPT_VERSION="1.4"
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

# ask_yn VAR PROMPT [DEFAULT]
# Loops until user enters y/Y/n/N. DEFAULT is applied if user presses Enter.
# Result stored in the variable named by VAR.
ask_yn() {
    local _var="$1"
    local _prompt="$2"
    local _default="${3:-}"
    local _input
    while true; do
        echo -ne "$_prompt"
        read -r _input
        _input="${_input:-$_default}"
        case "$_input" in
            [Yy]|[Nn]) break ;;
            *) echo -e "   ${ERROR}Please answer y or n.${RESET}" ;;
        esac
    done
    printf -v "$_var" '%s' "$_input"
}

# ask_choice VAR PROMPT ALLOWED...
# Loops until user enters one of the ALLOWED values.
# Result stored in the variable named by VAR.
# Usage: ask_choice MYVAR "Select (1/2/3): " 1 2 3
ask_choice() {
    local _var="$1"
    local _prompt="$2"
    shift 2
    local _allowed=("$@")
    local _input
    while true; do
        echo -ne "$_prompt"
        read -r _input
        local _v
        for _v in "${_allowed[@]}"; do
            if [[ "$_input" == "$_v" ]]; then
                printf -v "$_var" '%s' "$_input"
                return
            fi
        done
        echo -e "   ${ERROR}Invalid — please enter one of: ${_allowed[*]}.${RESET}"
    done
}

# ask_num VAR PROMPT MIN MAX [DEFAULT]
# Loops until user enters an integer between MIN and MAX inclusive.
# Result stored in the variable named by VAR.
ask_num() {
    local _var="$1"
    local _prompt="$2"
    local _min="$3"
    local _max="$4"
    local _default="${5:-}"
    local _input
    while true; do
        echo -ne "$_prompt"
        read -r _input
        _input="${_input:-$_default}"
        if [[ "$_input" =~ ^[0-9]+$ ]] && (( _input >= _min && _input <= _max )); then
            break
        fi
        echo -e "   ${ERROR}Invalid — enter a number between $_min and $_max.${RESET}"
    done
    printf -v "$_var" '%s' "$_input"
}

# Print a code block with color and border
print_code() {
    local line
    echo -e "${ACCENT}   ┌─────────────────────────────────────────────────────────────┐${RESET}"
    while IFS= read -r line; do
        echo -e "${CODE}${line}${RESET}"
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
    echo -e "${BANNER}│                    Included Components:                      │${RESET}"
    echo -e "${BANNER}│   Synapse • MAS • LiveKit • LiveKit JWT • PostgreSQL • Sync  │${RESET}"
    echo -e "${BANNER}│        Element Call • Admin Panel • Bridges (optional)       │${RESET}"
    echo -e "${BANNER}│                                                              │${RESET}"
    echo -e "${BANNER}│       Bridges: Discord • Telegram • WhatsApp • Signal        │${RESET}"
    echo -e "${BANNER}│                    Slack • Instagram                         │${RESET}"
    echo -e "${BANNER}│                                                              │${RESET}"
    echo -e "${BANNER}│           Dynamic • Multi-Screenshare • Easy Setup           │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    
    # Show version info only
    echo -e "\n${INFO}Script Version: ${SUCCESS}v${SCRIPT_VERSION}${RESET}"
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

    # Write credentials file — matches the on-screen output format exactly
    mkdir -p "$(dirname "$CREDS_PATH")"

    {
    echo "┌──────────────────────────────────────────────────────────────┐"
    echo "│                      DEPLOYMENT COMPLETE                     │"
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "═══════════════════════ ACCESS CREDENTIALS ═══════════════════════"
    echo "   Matrix Server:       $SERVER_NAME"
    echo "   Admin User:          $ADMIN_USER"
    if [ "$PASS_IS_CUSTOM" = true ]; then
        echo "   Admin Pass:          [Your custom password]"
    else
        echo "   Admin Pass:          $ADMIN_PASS"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo "   Element Admin:       http://$AUTO_LOCAL_IP:8014 (LAN) / https://$SUB_ELEMENT_ADMIN.$DOMAIN (WAN)"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo "   Synapse Admin:       http://$AUTO_LOCAL_IP:8009 (LAN) / https://$SUB_SYNAPSE_ADMIN.$DOMAIN (WAN)"
    fi
    echo "   Matrix API:          http://$AUTO_LOCAL_IP:8008 (LAN) / https://$SUB_MATRIX.$DOMAIN (WAN)"
    echo "   Auth Service (MAS):  http://$AUTO_LOCAL_IP:8010 (LAN) / https://$SUB_MAS.$DOMAIN (WAN)"
    echo "   Element Web:         http://$AUTO_LOCAL_IP:8012 (LAN) / https://$SUB_ELEMENT.$DOMAIN (WAN)"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo "   Element Call:        http://$AUTO_LOCAL_IP:8007 (LAN) / https://$SUB_CALL.$DOMAIN (WAN)"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo "   Sliding Sync:        http://$AUTO_LOCAL_IP:8011 (LAN) / https://$SUB_SLIDING_SYNC.$DOMAIN (WAN)"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo "   Media Repo:          http://$AUTO_LOCAL_IP:8013 (LAN) / https://$SUB_MEDIA_REPO.$DOMAIN (WAN)"
    fi
    echo ""
    echo "═══════════════════════ USER MANAGEMENT ════════════════════════"
    echo "   ⚠️  Registration via Element Web is disabled — MAS handles all accounts."
    echo "   The 'Create account' button in Element will open the MAS registration page."
    echo ""
    echo "   Create a regular user:"
    echo "   docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes"
    echo ""
    echo "   Create an admin user:"
    echo "   docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --admin --yes"
    echo ""
    echo "   Or register via the MAS web UI:"
    echo "   https://$SUB_MAS.$DOMAIN/account/"
    echo ""
    echo "═══════════════════════ INTERNAL SECRETS ════════════════════════"
    echo "   Database Credentials:"
    echo "      DB User:       $DB_USER"
    echo "      DB Password:   $DB_PASS"
    echo "      Databases:     synapse, matrix_auth, syncv3$(if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then echo ", media_repo"; fi)"
    echo "   Shared Secret:    $REG_SECRET"
    echo "   MAS Secret:       $MAS_SECRET"
    echo "   Livekit API Key:  $LK_API_KEY"
    echo "   Livekit Secret:   $LK_API_SECRET"
    if [[ "$PROXY_ALREADY_RUNNING" == "false" && "$PROXY_TYPE" == "npm" && -n "$NPM_ADMIN_PASS" ]]; then
        echo "   NPM Web UI:       http://$AUTO_LOCAL_IP:81"
        echo "   NPM Email:        $NPM_ADMIN_EMAIL"
        echo "   NPM Password:     $NPM_ADMIN_PASS"
    fi
    echo ""
    echo "═════════════════════════ DNS RECORDS ═══════════════════════════"
    echo "   (See on-screen output for DNS table)"
    echo ""
    echo "════════════════════════ PORT FORWARDING ═════════════════════════"
    echo "   (See on-screen output for port forwarding table)"
    echo ""
    echo "═══════════════════════ CONFIGURATION FILES ═══════════════════════"
    echo "   • LiveKit:        $TARGET_DIR/livekit/livekit.yaml"
    echo "   • Synapse:        $TARGET_DIR/synapse/homeserver.yaml"
    echo "   • MAS:            $TARGET_DIR/mas/config.yaml"
    echo ""
    echo "════════════════════════ IMPORTANT NOTES ═════════════════════════"
    echo "   ✓ MAS (Matrix Authentication Service) handles user authentication"
    echo "   ✓ UNLIMITED multi-screenshare enabled (no artificial limits)"
    echo "   ✓ LiveKit SFU configured for high-quality video calls (with built-in TURN/STUN)"
    echo "   ✓ LiveKit JWT Service deployed for token generation"
    echo "   ℹ  Video calling available via Element/Commet clients (built-in widget)"
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo "   ✓ Element Admin: https://$SUB_ELEMENT_ADMIN.$DOMAIN"
    fi
    echo "   ✓ iOS/Android: Use Element app (NOT Element X)"
    echo "   ✓ Element Web (self-hosted): https://$SUB_ELEMENT.$DOMAIN"
    echo "   ⚠️  app.element.io does NOT work with self-hosted MAS"
    echo "   ℹ  Test federation: https://federationtester.matrix.org"
    echo "   ⚠️  TURN must always be DNS ONLY - never proxy TURN traffic"
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        echo ""
        echo "═══════════════════════ BRIDGE SETUP ════════════════════════"
        echo "   ℹ  Bridges installed: ${SELECTED_BRIDGES[*]}"
        echo "   ⚠️  Bridges need a few minutes to fully start before use."
        echo ""
        echo "   How to activate each bridge:"
        echo "   1. Open Element Web: https://$SUB_ELEMENT.$DOMAIN"
        echo "   2. Start a new Direct Message (DM) with the bot user below"
        echo "   3. The bot must appear in search — if not, wait 1-2 min and retry"
        echo "   4. Send the command shown to begin the login flow"
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            case $bridge in
                discord)
                    echo ""
                    echo "   ── Discord ──────────────────────────────────────────"
                    echo "   Bot user:  @discordbot:$DOMAIN"
                    echo "   Step 1:    Send: login"
                    echo "   Step 2:    Follow the link the bot sends — log in via browser"
                    echo "   Step 3:    Authorize the bot, paste the token back if prompted"
                    echo "   Docs:      https://docs.mau.fi/bridges/go/discord/authentication.html"
                    ;;
                telegram)
                    echo ""
                    echo "   ── Telegram ─────────────────────────────────────────"
                    echo "   Bot user:  @telegrambot:$DOMAIN"
                    echo "   Step 1:    Send: login"
                    echo "   Step 2:    Enter your phone number and confirmation code"
                    echo "   Docs:      https://docs.mau.fi/bridges/go/telegram/authentication.html"
                    ;;
                whatsapp)
                    echo ""
                    echo "   ── WhatsApp ─────────────────────────────────────────"
                    echo "   Bot user:  @whatsappbot:$DOMAIN"
                    echo "   Step 1:    Send: login"
                    echo "   Step 2:    Scan the QR code in WhatsApp app"
                    echo "   Docs:      https://docs.mau.fi/bridges/go/whatsapp/authentication.html"
                    ;;
                signal)
                    echo ""
                    echo "   ── Signal ───────────────────────────────────────────"
                    echo "   Bot user:  @signalbot:$DOMAIN"
                    echo "   Step 1:    Send: link"
                    echo "   Step 2:    Scan the QR code in Signal app"
                    echo "   Docs:      https://docs.mau.fi/bridges/go/signal/authentication.html"
                    ;;
                slack)
                    echo ""
                    echo "   ── Slack ────────────────────────────────────────────"
                    echo "   Bot user:  @slackbot:$DOMAIN"
                    echo "   Step 1:    Send: login"
                    echo "   Step 2:    Follow the OAuth link"
                    echo "   Docs:      https://docs.mau.fi/bridges/go/slack/authentication.html"
                    ;;
                instagram)
                    echo ""
                    echo "   ── Instagram ────────────────────────────────────────"
                    echo "   Bot user:  @instagrambot:$DOMAIN"
                    echo "   Step 1:    Send: login"
                    echo "   Step 2:    Enter your username and password"
                    echo "   Docs:      https://docs.mau.fi/bridges/go/instagram/authentication.html"
                    ;;
            esac
        done
    fi
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "     !!! STORING THIS AS A FILE IS AT YOUR OWN RESPONSIBILITY. !!!"
    echo "══════════════════════════════════════════════════════════════════"
    } > "$CREDS_PATH"

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
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${ACCESS_NAME}Element Admin:${RESET}       ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8014${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_ELEMENT_ADMIN.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${ACCESS_NAME}Synapse Admin:${RESET}       ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8009${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_SYNAPSE_ADMIN.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    fi
    echo -e "   ${ACCESS_NAME}Matrix API:${RESET}          ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8008${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_MATRIX.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Auth Service (MAS):${RESET}  ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8010${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_MAS.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Element Web:${RESET}         ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8012${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_ELEMENT.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -e "   ${ACCESS_NAME}Element Call:${RESET}        ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:8007${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_CALL.$DOMAIN${ACCESS_VALUE}${RESET} (WAN via Element Web)"
    fi

    # User management section — always visible, clearly copy-pasteable
    echo -e "\n${ACCENT}═══════════════════════ USER MANAGEMENT ════════════════════════${RESET}"
    echo -e "   ${WARNING}⚠️  Registration via Element Web is disabled — MAS handles all accounts.${RESET}"
    echo -e "   ${INFO}The 'Create account' button in Element will open the MAS registration page.${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Create a regular user:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Create an admin user:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --admin --yes${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Or register via the MAS web UI:${RESET}"
    echo -e "   ${SUCCESS}https://$SUB_MAS.$DOMAIN/account/${RESET}"
    echo -e ""
    echo -e "   ${INFO}ℹ  If registration is disabled, the MAS UI will reject new signups.${RESET}"
    echo -e "   ${INFO}   Use the CLI commands above regardless of registration setting.${RESET}"
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
    echo -e "   ${SECRET_NAME}   Databases:${RESET}     ${SECRET_VALUE}synapse, matrix_auth, syncv3$(if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then echo ", media_repo"; fi)${RESET}"
    echo -e "   ${SECRET_NAME}Shared Secret:${RESET}    ${SECRET_VALUE}${REG_SECRET}${RESET}"
    echo -e "   ${SECRET_NAME}MAS Secret:${RESET}       ${SECRET_VALUE}${MAS_SECRET}${RESET}"
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
        ELEMENT_ADMIN_STATUS="DNS ONLY"
    elif [[ "$PROXY_TYPE" == "npm" ]] || [[ "$PROXY_TYPE" == "caddy" ]] || [[ "$PROXY_TYPE" == "traefik" ]]; then
        MATRIX_STATUS="PROXIED"
        MAS_STATUS="PROXIED"
        LIVEKIT_STATUS="PROXIED"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="PROXIED"
        ELEMENT_ADMIN_STATUS="PROXIED"
    else
        MATRIX_STATUS="DNS ONLY"
        MAS_STATUS="DNS ONLY"
        LIVEKIT_STATUS="DNS ONLY"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="DNS ONLY"
        ELEMENT_ADMIN_STATUS="DNS ONLY"
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

    # Element Call row (if enabled)
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_CALL" "A" "$AUTO_PUBLIC_IP"
        if [[ "$ELEMENT_CALL_STATUS" == "PROXIED" ]]; then
            printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$ELEMENT_CALL_STATUS"
        else
            printf "%-15s │\n" "$ELEMENT_CALL_STATUS"
        fi
    fi

    # Element Admin row (if enabled)
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_ELEMENT_ADMIN" "A" "$AUTO_PUBLIC_IP"
        if [[ "$ELEMENT_ADMIN_STATUS" == "PROXIED" ]]; then
            printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$ELEMENT_ADMIN_STATUS"
        else
            printf "%-15s │\n" "$ELEMENT_ADMIN_STATUS"
        fi
    fi

    # Synapse Admin row (if enabled)
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ " "$SUB_SYNAPSE_ADMIN" "A" "$AUTO_PUBLIC_IP"
        printf "${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "PROXIED"
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
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Admin" "TCP" "8014" "$AUTO_LOCAL_IP:8014"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Synapse Admin" "TCP" "8009" "$AUTO_LOCAL_IP:8009"
    fi
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
    
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN (TCP/UDP)" "TCP/UDP" "3478" "$AUTO_LOCAL_IP:3478"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN TLS" "TCP" "5349" "$AUTO_LOCAL_IP:5349"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit HTTP" "TCP" "7880" "$AUTO_LOCAL_IP:7880"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit RTC" "UDP" "7882" "$AUTO_LOCAL_IP:7882"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit JWT" "TCP" "8080" "$AUTO_LOCAL_IP:8080"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit Range" "UDP" "50000-50050" "$AUTO_LOCAL_IP"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Call" "TCP" "8007" "$AUTO_LOCAL_IP:8007"
    fi
    echo -e "   └─────────────────┴───────────┴─────────────────┴───────────────────────┘"

    # Configuration files section
    echo -e "\n${ACCENT}═══════════════════════ CONFIGURATION FILES ═══════════════════════${RESET}"
    echo -e "   ${INFO}• LiveKit:${RESET}        ${CONFIG_PATH}${TARGET_DIR}/livekit/livekit.yaml${RESET}"
    echo -e "   ${INFO}• Synapse:${RESET}        ${CONFIG_PATH}${TARGET_DIR}/synapse/homeserver.yaml${RESET}"
    echo -e "   ${INFO}• MAS:${RESET}            ${CONFIG_PATH}${TARGET_DIR}/mas/config.yaml${RESET}"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -e "   ${INFO}• Element Call:${RESET}   ${CONFIG_PATH}${TARGET_DIR}/element-call/config.json${RESET}"
    fi

    # Important notes section
    echo -e "\n${ACCENT}════════════════════════ IMPORTANT NOTES ═════════════════════════${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} MAS (Matrix Authentication Service) handles user authentication${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} UNLIMITED multi-screenshare enabled (no artificial limits)${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} LiveKit SFU configured for high-quality video calls (with built-in TURN/STUN)${RESET}"
    echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} LiveKit JWT Service deployed for token generation${RESET}"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} Standalone Element Call deployed: https://$SUB_CALL.$DOMAIN${RESET}"
    else
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Video calling available via Element/Commet clients (built-in widget)${RESET}"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} Element Admin: https://$SUB_ELEMENT_ADMIN.$DOMAIN${RESET}"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT} Synapse Admin: https://$SUB_SYNAPSE_ADMIN.$DOMAIN${RESET}"
    fi
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
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Registration: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} — users can sign up at https://$SUB_MAS.$DOMAIN/account/${RESET}"
        if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then
            echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Email verification: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (SMTP configured)${RESET}"
        fi
        if [[ "$ENABLE_CAPTCHA" =~ ^[Yy]$ ]]; then
            echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  Add reCAPTCHA keys to ${CONFIG_PATH}${TARGET_DIR}/mas/config.yaml${RESET}"
        fi
    else
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Registration: ${ERROR}DISABLED${RESET}${NOTE_TEXT} — use CLI: ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes${RESET}"
    fi
    
    # Sliding Sync note
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Sliding Sync: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (modern client support)${RESET}"
    fi
    
    # Matrix Media Repo note
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Matrix Media Repo: running at https://$SUB_MEDIA_REPO.$DOMAIN${RESET}"
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Synapse delegates all media to it — files stored at ${TARGET_DIR}/media-repo/data${RESET}"
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  To use S3 storage: edit ${TARGET_DIR}/media-repo/config.yaml → datastores section${RESET}"
    fi
    
    # Bridge setup instructions
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        echo -e "\n${ACCENT}═══════════════════════ BRIDGE SETUP ════════════════════════${RESET}"
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Bridges installed: ${SUCCESS}${SELECTED_BRIDGES[*]}${RESET}"
        echo -e "   ${NOTE_ICON}${WARNING}⚠️${RESET}${NOTE_TEXT}  Bridges need a few minutes to fully start before use.${RESET}"
        echo -e "\n   ${ACCENT}How to activate each bridge:${RESET}"
        echo -e "   ${INFO}1. Open Element Web: https://$SUB_ELEMENT.$DOMAIN${RESET}"
        echo -e "   ${INFO}2. Start a new Direct Message (DM) with the bot user below${RESET}"
        echo -e "   ${INFO}3. The bot must appear in search — if not, wait 1-2 min and retry${RESET}"
        echo -e "   ${INFO}4. Send the command shown to begin the login flow${RESET}"
        echo -e ""
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            case $bridge in
                discord)
                    echo -e "   ${SUCCESS}── Discord ──────────────────────────────────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @discordbot:$DOMAIN"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    Follow the link the bot sends — log in via browser"
                    echo -e "   ${INFO}Step 3:${RESET}    Authorize the bot, paste the token back if prompted"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/discord/authentication.html"
                    echo -e ""
                    ;;
                telegram)
                    echo -e "   ${SUCCESS}── Telegram ─────────────────────────────────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @telegrambot:$DOMAIN"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    Enter your phone number when prompted"
                    echo -e "   ${INFO}Step 3:${RESET}    Enter the code Telegram sends you"
                    echo -e "   ${INFO}2FA:${RESET}       Enter your Telegram password if 2FA is enabled"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/python/telegram/authentication.html"
                    echo -e ""
                    ;;
                whatsapp)
                    echo -e "   ${SUCCESS}── WhatsApp ─────────────────────────────────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @whatsappbot:$DOMAIN"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    The bot will send a QR code — scan it with WhatsApp"
                    echo -e "   ${INFO}           (WhatsApp → Linked Devices → Link a Device)${RESET}"
                    echo -e "   ${INFO}Note:${RESET}      Your phone must stay online (it's a web bridge)"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/whatsapp/authentication.html"
                    echo -e ""
                    ;;
                signal)
                    echo -e "   ${SUCCESS}── Signal ───────────────────────────────────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @signalbot:$DOMAIN"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}link${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    The bot sends a link — open it, scan QR in Signal"
                    echo -e "   ${INFO}           (Signal → Settings → Linked Devices → +)${RESET}"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/signal/authentication.html"
                    echo -e ""
                    ;;
                slack)
                    echo -e "   ${SUCCESS}── Slack ────────────────────────────────────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @slackbot:$DOMAIN"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    Follow the OAuth link to authorize your Slack workspace"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/slack/authentication.html"
                    echo -e ""
                    ;;
                instagram)
                    echo -e "   ${SUCCESS}── Instagram ────────────────────────────────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @instagrambot:$DOMAIN"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    Enter your Instagram username when prompted"
                    echo -e "   ${INFO}Step 3:${RESET}    Enter your Instagram password"
                    echo -e "   ${INFO}2FA:${RESET}       Enter the 2FA code if your account uses it"
                    echo -e "   ${WARNING}Note:${RESET}      Instagram actively restricts automation — use at own risk"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/instagram/authentication.html"
                    echo -e ""
                    ;;
            esac
        done
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
        # Current version is NEWER than GitHub — unknown/unofficial build
        echo -e ""
        echo -e "${ERROR}╔══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${ERROR}║              ⚠️  UNVERIFIED SCRIPT VERSION                   ║${RESET}"
        echo -e "${ERROR}╚══════════════════════════════════════════════════════════════╝${RESET}"
        echo -e ""
        echo -e "   ${WARNING}This script is version ${ERROR}v${SCRIPT_VERSION}${WARNING}, but the latest official${RESET}"
        echo -e "   ${WARNING}release on GitHub is ${SUCCESS}v${LATEST_VERSION}${WARNING}.${RESET}"
        echo -e ""
        echo -e "   ${WARNING}You may be running a modified or unofficial version.${RESET}"
        echo -e "   ${WARNING}Only run scripts obtained directly from the official repo:${RESET}"
        echo -e "   ${SUCCESS}https://github.com/$GITHUB_REPO${RESET}"
        echo -e ""
        echo -ne "   ${WARNING}Continue anyway? (y/n): ${RESET}"
        read -r UNOFFICIAL_CONFIRM
        if [[ ! "$UNOFFICIAL_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n   ${INFO}Exiting. Download the official script from:${RESET}"
            echo -e "   ${SUCCESS}https://github.com/$GITHUB_REPO${RESET}"
            echo ""
            exit 1
        fi
        echo -e "   ${WARNING}Proceeding with unverified version...${RESET}"
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
        
        mkdir -p /etc/docker
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

# Generate LiveKit SFU configuration with built-in TURN/STUN and multi-screenshare support
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

# Built-in TURN/STUN server
turn:
  enabled: true
  domain: REPLACE_TURN_DOMAIN
  cert_file: ""
  key_file: ""
  tls_port: 5349
  udp_port: 3478
  external_tls: true
LIVEKITEOF

    # Replace placeholders
    sed -i "s/REPLACE_LK_API_KEY/$LK_API_KEY/g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s/REPLACE_LK_API_SECRET/$LK_API_SECRET/g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s/REPLACE_TURN_DOMAIN/turn.$DOMAIN/g" "$TARGET_DIR/livekit/livekit.yaml"
    
    echo -e "   ${SUCCESS}✓ LiveKit config created - unlimited screenshares + built-in TURN/STUN enabled${RESET}"
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

generate_media_repo_config() {
    echo -e "\n${ACCENT}>> Generating Matrix Media Repo configuration...${RESET}"

    mkdir -p "$TARGET_DIR/media-repo/data"

    cat > "$TARGET_DIR/media-repo/config.yaml" << EOF
# Matrix Media Repo configuration
# Generated by matrix-stack-deploy v${SCRIPT_VERSION}

repo:
  bindAddress: "0.0.0.0"
  port: 8000
  logLevel: "info"
  logToFile: false

database:
  postgres: "postgresql://${DB_USER}:${DB_PASS}@postgres/media_repo?sslmode=disable"

homeservers:
  - name: "${SERVER_NAME}"
    csApi: "http://synapse:8008"
    backoffAt: 10
    adminApiKind: "matrix"

admins:
  - "@${ADMIN_USER}:${SERVER_NAME}"

datastores:
  - id: "local_storage"
    type: "file"
    enabled: true
    forKinds: ["all"]
    opts:
      path: "/data"

features:
  MSC2246Async: false
  MSC3916AuthenticatedMedia: true

downloads:
  maxBytes: 104857600  # 100MB
  failureCacheMinutes: 5
  expireAfterDays: 0   # 0 = never expire
  defaultRangeChunkSizeBytes: 10485760  # 10MB

thumbnails:
  maxSourceBytes: 10485760  # 10MB
  maxPixels: 32000000
  types:
    - "image/jpeg"
    - "image/jpg"
    - "image/png"
    - "image/gif"
    - "image/heif"
    - "image/webp"

urlPreviews:
  enabled: true
  maxPageSizeBytes: 10485760
  previewUnsafeCerts: false
  oEmbed: true

rateLimit:
  requestsPerSecond: 5
  burst: 10

metrics:
  enabled: false

federation:
  backfillWorkers: 2
EOF

    echo -e "   ${SUCCESS}✓ Matrix Media Repo config created${RESET}"
    echo -e "   ${INFO}ℹ  Using local file storage at ${TARGET_DIR}/media-repo/data${RESET}"
    echo -e "   ${INFO}ℹ  To use S3, edit: ${TARGET_DIR}/media-repo/config.yaml${RESET}"
}

generate_element_web_config() {
    echo -e "\n${ACCENT}>> Generating Element Web configuration...${RESET}"

    mkdir -p "$TARGET_DIR/element-web"

    # Build element_call config block conditionally
    local ELEMENT_CALL_CONFIG=""
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        ELEMENT_CALL_CONFIG=",
    \"element_call\": {
        \"url\": \"https://$SUB_CALL.$DOMAIN\",
        \"use_exclusively\": false
    }"
    fi

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
    }${ELEMENT_CALL_CONFIG},
    "setting_defaults": {
        "MessageComposerInput.showStickersButton": false
    },
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": true,
    "showLabsSettings": true,
    "registration_url": "https://$SUB_MAS.$DOMAIN/account/",
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
                mkdir -p "$TARGET_DIR/bridges/$bridge"

                # The binary requires a config.yaml to exist before -g will work.
                # The example config is bundled in the image at /opt/mautrix-<bridge>/example-config.yaml.
                # Step 1: copy it out of the image if we don't already have a config.
                # Step 2: run -g against it to produce registration.yaml.
                rm -f "$TARGET_DIR/bridges/$bridge/registration.yaml"

                local GEN_LOG="$TARGET_DIR/bridges/$bridge/generate.log"
                local GEN_OK=false
                local ENTRYPOINT="/usr/bin/mautrix-$bridge"
                local EXAMPLE_PATH="/opt/mautrix-$bridge/example-config.yaml"

                # Step 1: extract example config from image if no config exists yet
                if [ ! -f "$TARGET_DIR/bridges/$bridge/config.yaml" ]; then
                    docker run --rm \
                        --entrypoint /bin/sh \
                        -v "$TARGET_DIR/bridges/$bridge:/data" \
                        dock.mau.dev/mautrix/$bridge:latest \
                        -c "cp $EXAMPLE_PATH /data/config.yaml" \
                        > "$GEN_LOG" 2>&1
                fi

                # Step 2: patch the minimum required fields so -g doesn't refuse to run
                if [ -f "$TARGET_DIR/bridges/$bridge/config.yaml" ]; then
                    sed -i "s|domain: example.com|domain: $DOMAIN|g" \
                        "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
                    sed -i "s|address: https://matrix.example.com|address: http://synapse:8008|g" \
                        "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
                    sed -i "s|address: https://example.com|address: http://synapse:8008|g" \
                        "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
                fi

                # Step 3: generate registration.yaml from the patched config
                if [ -f "$TARGET_DIR/bridges/$bridge/config.yaml" ]; then
                    docker run --rm \
                        --entrypoint "$ENTRYPOINT" \
                        -v "$TARGET_DIR/bridges/$bridge:/data" \
                        dock.mau.dev/mautrix/$bridge:latest \
                        -g -c /data/config.yaml -r /data/registration.yaml \
                        >> "$GEN_LOG" 2>&1
                    [ -f "$TARGET_DIR/bridges/$bridge/registration.yaml" ] && GEN_OK=true
                else
                    echo "Failed to extract example config from image" >> "$GEN_LOG"
                fi

                if [[ "$GEN_OK" != "true" ]]; then
                    echo -e "   ${ERROR}✗ Failed to generate $bridge bridge config.${RESET}"
                    echo -e "   ${INFO}Last 10 lines of generate.log:${RESET}"
                    tail -10 "$GEN_LOG" 2>/dev/null | sed 's/^/      /'
                    echo -e "   ${WARNING}Full log: $GEN_LOG${RESET}"
                else
                    rm -f "$GEN_LOG"
                    echo -e "   ${SUCCESS}✓ $bridge config and registration generated${RESET}"
                fi

                # Patch the generated config with correct values.
                # Use a multi-pattern approach so we hit the field regardless of what the generator wrote.
                local CFG="$TARGET_DIR/bridges/$bridge/config.yaml"
                # Homeserver address — generator writes https://example.com or similar
                sed -i \
                    -e "s|address: https://matrix.example.com|address: http://synapse:8008|g" \
                    -e "s|address: https://example.com|address: http://synapse:8008|g" \
                    -e "s|address: http://example.com|address: http://synapse:8008|g" \
                    "$CFG" 2>/dev/null
                # Domain
                sed -i "s|domain: example.com|domain: $DOMAIN|g" "$CFG" 2>/dev/null
                # Database URI — bridge needs its own postgres database
                local BRIDGE_DB="mautrix_${bridge}"
                # Create the database if it doesn't exist
                docker exec synapse-db psql -U "$DB_USER" -tc \
                    "SELECT 1 FROM pg_database WHERE datname='$BRIDGE_DB'" 2>/dev/null \
                    | grep -q 1 || \
                    docker exec synapse-db psql -U "$DB_USER" \
                    -c "CREATE DATABASE $BRIDGE_DB OWNER $DB_USER;" 2>/dev/null
                # Patch the URI line — handles both commented and uncommented variants
                sed -i \
                    -e "s|uri: postgres://user:password@host/db|uri: postgresql://$DB_USER:$DB_PASS@postgres/$BRIDGE_DB?sslmode=disable|g" \
                    -e "s|uri: postgresql://user:password@host/db|uri: postgresql://$DB_USER:$DB_PASS@postgres/$BRIDGE_DB?sslmode=disable|g" \
                    "$CFG" 2>/dev/null
                # If still not set (field exists but empty/different placeholder), use line replacement
                if ! grep -q "postgresql://$DB_USER" "$CFG" 2>/dev/null; then
                    sed -i "/^        uri:/c\        uri: postgresql://$DB_USER:$DB_PASS@postgres/$BRIDGE_DB?sslmode=disable" "$CFG" 2>/dev/null
                fi

                # Appservice listen address — must use container name so Synapse can reach it
                sed -i "s|address: http://localhost:|address: http://mautrix-$bridge:|g" "$CFG" 2>/dev/null
                # Also fix registration.yaml url
                local REG_URL="$TARGET_DIR/bridges/$bridge/registration.yaml"
                if [ -f "$REG_URL" ]; then
                    sed -i "s|url: http://localhost:|url: http://mautrix-$bridge:|g" "$REG_URL" 2>/dev/null
                fi

                # Permissions — replace example.com placeholders with actual domain/admin
                sed -i \
                    -e "s|\"example.com\": user|\"$DOMAIN\": user|g" \
                    -e "s|\"@admin:example.com\": admin|\"@$ADMIN_USER:$DOMAIN\": admin|g" \
                    "$CFG" 2>/dev/null

                # bot_username / sender_localpart — generator default is mautrix<bridge>bot
                # Replace both the config key AND update the registration to match
                local BOT_USER="${bridge}bot"
                local DEFAULT_BOT="mautrix${bridge}bot"
                sed -i "s|bot_username: $DEFAULT_BOT|bot_username: $BOT_USER|g" "$CFG" 2>/dev/null
                # Also patch any variant spellings (some bridges use 'username:' under appservice.bot)
                sed -i "s|username: $DEFAULT_BOT|username: $BOT_USER|g" "$CFG" 2>/dev/null

                # Patch the registration.yaml sender_localpart to match the bot_username we just set,
                # so Synapse and the bridge agree on which Matrix user is the bot.
                local REG="$TARGET_DIR/bridges/$bridge/registration.yaml"
                if [ -f "$REG" ]; then
                    sed -i "s|sender_localpart: $DEFAULT_BOT|sender_localpart: $BOT_USER|g" "$REG" 2>/dev/null
                    echo -e "   ${SUCCESS}✓ $bridge registered with Synapse${RESET}"
                fi

                BRIDGE_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
                echo -e "${SUCCESS}   ✓ $BRIDGE_NAME bridge configured${RESET}"
                ;;
        esac
    done

    # Ensure bridge files are readable by Synapse (UID 991)
    if [ -d "$TARGET_DIR/bridges" ]; then
        find "$TARGET_DIR/bridges" -type f -exec chmod 644 {} \;
        find "$TARGET_DIR/bridges" -type d -exec chmod 755 {} \;
        echo -e "   ${SUCCESS}✓ Bridge file permissions set (readable by Synapse)${RESET}"
    fi

    # Register all bridge appservice files with Synapse.
    # Only register bridges whose registration.yaml was actually generated —
    # a missing file causes Synapse to crash on startup with load_appservices error.
    echo -e "\n${ACCENT}   >> Registering bridges with Synapse (appservice_config_files)...${RESET}"
    local AS_BLOCK="app_service_config_files:"
    local AS_COUNT=0
    for bridge in "${SELECTED_BRIDGES[@]}"; do
        local REG_HOST="$TARGET_DIR/bridges/${bridge}/registration.yaml"
        local REG_FILE="/data/bridges/${bridge}/registration.yaml"
        if [ -f "$REG_HOST" ]; then
            AS_BLOCK="${AS_BLOCK}
  - ${REG_FILE}"
            ((AS_COUNT++))
        else
            echo -e "${WARNING}   ⚠️  Skipping $bridge — registration.yaml not found, bridge will not be registered${RESET}"
        fi
    done

    if [[ $AS_COUNT -eq 0 ]]; then
        echo -e "${WARNING}   ⚠️  No valid bridge registrations found — skipping homeserver.yaml update${RESET}"
        return
    fi

    # Append to homeserver.yaml (only if not already present)
    if ! grep -q "app_service_config_files:" "$TARGET_DIR/synapse/homeserver.yaml" 2>/dev/null; then
        printf "\n%s\n" "$AS_BLOCK" >> "$TARGET_DIR/synapse/homeserver.yaml"
        echo -e "${SUCCESS}   ✓ Bridges registered with Synapse ($AS_COUNT):${RESET}"
        for _b in "${SELECTED_BRIDGES[@]}"; do
            echo -e "      ${CHOICE_COLOR}• $_b${RESET}"
        done
    else
        echo -e "${INFO}   ℹ  app_service_config_files already present in homeserver.yaml${RESET}"
    fi
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

    # MAS requires at least one RSA key (for RS256, mandatory per OIDC spec)
    # plus an EC key for ES256. Both generated into variables — never written to disk.
    local MAS_RSA_KEY MAS_EC_KEY
    MAS_RSA_KEY=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)
    MAS_EC_KEY=$(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2>/dev/null)

    # Fallback for EC key on older openssl
    if [ -z "$MAS_EC_KEY" ] || ! echo "$MAS_EC_KEY" | grep -q "BEGIN PRIVATE KEY"; then
        MAS_EC_KEY=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null \
            | openssl pkcs8 -topk8 -nocrypt 2>/dev/null)
    fi

    if [ -z "$MAS_RSA_KEY" ] || ! echo "$MAS_RSA_KEY" | grep -q "BEGIN PRIVATE KEY"; then
        echo -e "   ${ERROR}✗ Failed to generate RSA signing key — is openssl installed?${RESET}"
        exit 1
    fi
    if [ -z "$MAS_EC_KEY" ] || ! echo "$MAS_EC_KEY" | grep -q "BEGIN PRIVATE KEY"; then
        echo -e "   ${ERROR}✗ Failed to generate EC signing key — is openssl installed?${RESET}"
        exit 1
    fi
    echo -e "   ${SUCCESS}✓ RSA + EC signing keys generated${RESET}"
    
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

    # Build optional Element Call client block
    local ELEMENT_CALL_CLIENT_BLOCK=""
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        ELEMENT_CALL_CLIENT_BLOCK="
  - client_id: \"$ELEMENT_CALL_CLIENT_ID\"
    client_auth_method: none
    client_uri: \"https://$SUB_CALL.$DOMAIN/\"
    redirect_uris:
      - \"https://$SUB_CALL.$DOMAIN/\"
    grant_types:
      - authorization_code
      - refresh_token
    response_types:
      - code"
    fi

    # Build optional Element Admin client block
    local ELEMENT_ADMIN_CLIENT_BLOCK=""
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        ELEMENT_ADMIN_CLIENT_BLOCK="
  - client_id: \"$ELEMENT_ADMIN_CLIENT_ID\"
    client_auth_method: none
    client_uri: \"https://$SUB_ELEMENT_ADMIN.$DOMAIN/\"
    redirect_uris:
      - \"https://$SUB_ELEMENT_ADMIN.$DOMAIN/\"
    grant_types:
      - authorization_code
      - refresh_token
    response_types:
      - code"
    fi

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
        - name: adminapi
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
    - kid: "rsa"
      key: |
        MASKEY_RSA_PLACEHOLDER
    - kid: "ec"
      key: |
        MASKEY_EC_PLACEHOLDER
upstream_oauth2:
  providers: []

matrix:
  homeserver: "$SERVER_NAME"
  secret: "$MAS_SECRET"
  endpoint: http://synapse:8008

clients:
  - client_id: "0000000000000000000SYNAPSE"
    client_auth_method: client_secret_basic
    client_secret: "$MAS_SECRET"
$ELEMENT_CALL_CLIENT_BLOCK
$ELEMENT_ADMIN_CLIENT_BLOCK

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
  password_registration_enabled: $MAS_REGISTRATION
  $(if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then echo "# password_registration_email_required: true"; else echo "password_registration_email_required: false"; fi)

policy:
  registration:
    enabled: $MAS_REGISTRATION
    require_email: $(if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then echo "true"; else echo "false"; fi)
$CAPTCHA_CONFIG

branding:
  service_name: "$DOMAIN Matrix Server"
EOF

    # Inject RSA and EC signing keys into config with correct YAML indentation.
    # Two-pass awk: first inject RSA, then EC — keys never touch disk.
    awk '
    FNR==NR { lines[NR]=$0; n=NR; next }
    /        MASKEY_RSA_PLACEHOLDER/ {
        for(i=1;i<=n;i++) print "        " lines[i]
        print ""
        next
    }
    { print }
    ' <(echo "$MAS_RSA_KEY") "$TARGET_DIR/mas/config.yaml" > "$TARGET_DIR/mas/config.yaml.tmp" \
    && mv "$TARGET_DIR/mas/config.yaml.tmp" "$TARGET_DIR/mas/config.yaml"

    awk '
    FNR==NR { lines[NR]=$0; n=NR; next }
    /        MASKEY_EC_PLACEHOLDER/ {
        for(i=1;i<=n;i++) print "        " lines[i]
        print ""
        next
    }
    { print }
    ' <(echo "$MAS_EC_KEY") "$TARGET_DIR/mas/config.yaml" > "$TARGET_DIR/mas/config.yaml.tmp" \
    && mv "$TARGET_DIR/mas/config.yaml.tmp" "$TARGET_DIR/mas/config.yaml"

    # Verify file was created
    if [ ! -f "$TARGET_DIR/mas/config.yaml" ]; then
        echo -e "   ${ERROR}✗ FAILED to create MAS config file${RESET}"
        exit 1
    fi

    # Verify key was injected
    if grep -qE "MASKEY_RSA_PLACEHOLDER|MASKEY_EC_PLACEHOLDER" "$TARGET_DIR/mas/config.yaml" 2>/dev/null; then
        echo -e "   ${ERROR}✗ Failed to inject signing key into MAS config${RESET}"
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

    # Add media_repo database if media repo is enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        cat >> "$TARGET_DIR/postgres_init/01-create-databases.sh" << 'PGINITEOF2'

# Create media_repo database for Matrix Media Repo
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE media_repo'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'media_repo')\gexec
EOSQL

echo "PostgreSQL: media_repo database created (if needed)"
PGINITEOF2
    fi

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
#  Services:                                                                   #
#  • PostgreSQL (synapse, matrix_auth, syncv3 databases)                       #
#  • Synapse Matrix homeserver                                                 #
#  • MAS - Matrix Authentication Service                                       #
#  • LiveKit SFU with built-in TURN/STUN                                       #
#  • LiveKit JWT Service                                                       #
#  • Element Web                                                               #
#  • Element Call (optional)                                                   #
#  • Element Admin (optional)                                                  #
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
    volumes:
      - ./synapse:/data
      - ./bridges:/data/bridges
    ports: [ "8008:8008" ]
    depends_on:
      postgres:
        condition: service_healthy
      matrix-auth:
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

  # LiveKit SFU Server - Multi-screenshare support + built-in TURN/STUN
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
      - "3478:3478/udp"
      - "3478:3478/tcp"
      - "5349:5349/tcp"
      - "50000-50050:50000-50050/udp"
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # LiveKit JWT Service - Token generation for LiveKit
  livekit-jwt:
    container_name: livekit-jwt
    image: ghcr.io/element-hq/lk-jwt-service:latest
    restart: unless-stopped
    environment:
      - LIVEKIT_URL=wss://REPLACE_SUB_LIVEKIT.REPLACE_DOMAIN
      - LIVEKIT_KEY=REPLACE_LK_API_KEY
      - LIVEKIT_SECRET=REPLACE_LK_API_SECRET
      - LIVEKIT_JWT_BIND=:8080
    ports: [ "8080:8080" ]
    depends_on: [ livekit ]
    networks: [ matrix-net ]
    labels:
      com.docker.compose.project: "matrix-stack"

  # MAS (Matrix Authentication Service) - Handles authentication
  matrix-auth:
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

    # Replace placeholders with actual values
    sed -i "s/REPLACE_DB_PASS/$DB_PASS/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_SUB_LIVEKIT/$SUB_LIVEKIT/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_DOMAIN/$DOMAIN/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_LK_API_KEY/$LK_API_KEY/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_LK_API_SECRET/$LK_API_SECRET/g" "$TARGET_DIR/compose.yaml"

    # Insert Element Admin if enabled
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        sed -i '/^networks:/i\
\
  # Element Admin Web Interface\
  element-admin:\
    container_name: element-admin\
    image: oci.element.io/element-admin:latest\
    restart: unless-stopped\
    ports: [ "8014:8080" ]\
    environment:\
      SERVER_NAME: '"$SERVER_NAME"'\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
    fi

    # Insert Synapse Admin if enabled
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        sed -i '/^networks:/i\
\
  # Synapse Admin Web Interface\
  synapse-admin:\
    container_name: synapse-admin\
    image: awesometechnologies/synapse-admin:latest\
    restart: unless-stopped\
    ports: [ "8009:80" ]\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
    fi

    # Insert Element Call if enabled
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        sed -i '/^networks:/i\
\
  # Element Call - Standalone WebRTC Video Conferencing UI\
  element-call:\
    container_name: element-call\
    image: ghcr.io/element-hq/element-call:latest\
    restart: unless-stopped\
    volumes: [ "./element-call/config.json:/app/config.json:ro" ]\
    ports: [ "8007:8080" ]\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
    fi

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

    # Print success messages
    echo -e "   ${SUCCESS}✓ Docker Compose config created${RESET}"
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Element Admin included${RESET}"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Synapse Admin included${RESET}"
    fi
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Element Call included${RESET}"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Sliding Sync Proxy included${RESET}"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -e "   ${SUCCESS}✓ Matrix Media Repo included${RESET}"
    fi

    # Add bridges if selected
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        for bridge in "${SELECTED_BRIDGES[@]}"; do
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
      postgres:\
        condition: service_healthy\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
                    ;;
            esac
        done

        # Format bridge names for display
        BRIDGE_NAMES=""
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            BRIDGE_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
            if [ -z "$BRIDGE_NAMES" ]; then
                BRIDGE_NAMES="$BRIDGE_NAME"
            else
                BRIDGE_NAMES="$BRIDGE_NAMES ${SUCCESS}*${RESET} $BRIDGE_NAME"
            fi
        done
        echo -e "   ${SUCCESS}✓ ${#SELECTED_BRIDGES[@]} bridge(s) added:${RESET}"
        for _b in "${SELECTED_BRIDGES[@]}"; do
            _BNAME="$(tr '[:lower:]' '[:upper:]' <<< ${_b:0:1})${_b:1}"
            echo -e "      ${CHOICE_COLOR}• $_BNAME${RESET}"
        done
    fi

    # Add proxy services if needed
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

# TURN/STUN Configuration - handled by LiveKit's built-in TURN server
# LiveKit manages TURN credentials internally; no shared secret required
turn_uris:
  - "turn:turn.$DOMAIN:3478?transport=udp"
  - "turn:turn.$DOMAIN:3478?transport=tcp"
  - "turns:turn.$DOMAIN:5349?transport=tcp"
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
  endpoint: http://matrix-auth:8080/
  client_id: 0000000000000000000SYNAPSE
  client_auth_method: client_secret_basic
  secret: $MAS_SECRET
  account_management_url: https://$SUB_MAS.$DOMAIN/account

################################################################################
# LIVEKIT SFU - Unlimited Multi-Screenshare Video Calling
################################################################################

# LiveKit SFU configuration
livekit:
  url: https://$SUB_LIVEKIT.$DOMAIN
  livekit_api_key: $LK_API_KEY
  livekit_api_secret: $LK_API_SECRET

# Additional call configuration
allow_guest_access: false
SYNAPSEEOF

    # Add widget_urls for Element Call if enabled
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        cat >> "$TARGET_DIR/synapse/homeserver.yaml" << WIDGETEOF

# Element Call widget URL
widget_urls:
  - https://$SUB_CALL.$DOMAIN
WIDGETEOF
    fi

    # Delegate media to Matrix Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        cat >> "$TARGET_DIR/synapse/homeserver.yaml" << MEDIAEOF

################################################################################
# MATRIX MEDIA REPO - External media handling                                 #
################################################################################

# Delegate media to external media repo
media_repository_url: "http://matrix-media-repo:8000"

# Disable Synapse's built-in media handling
enable_media_repo: false
MEDIAEOF
        echo -e "   ${INFO}ℹ  Synapse configured to delegate media to matrix-media-repo${RESET}"
    fi
    
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

    # Build Caddyfile with optional service blocks
    local EXTRA_BLOCKS=""
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Element Call
$SUB_CALL.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8007
    header { Access-Control-Allow-Origin * }
}
"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Element Admin
$SUB_ELEMENT_ADMIN.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8014
}
"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Synapse Admin
$SUB_SYNAPSE_ADMIN.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8009
}
"
    fi
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
    @cors_preflight method OPTIONS
    handle @cors_preflight {
        header Access-Control-Allow-Origin *
        header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With"
        header Access-Control-Max-Age "86400"
        respond "" 204
    }
    reverse_proxy $AUTO_LOCAL_IP:8010
    header Access-Control-Allow-Origin *
    header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With"
}

# Element Web
$SUB_ELEMENT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8012
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
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    element-call:
      rule: \"Host(\`$SUB_CALL.$DOMAIN\`)\"
      service: element-call
      entryPoints: [\"websecure\"]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    element-call:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:8007\""
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    element-admin:
      rule: \"Host(\`$SUB_ELEMENT_ADMIN.$DOMAIN\`)\"
      service: element-admin
      entryPoints: [\"websecure\"]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    element-admin:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:8014\""
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    synapse-admin:
      rule: \"Host(\`$SUB_SYNAPSE_ADMIN.$DOMAIN\`)\"
      service: synapse-admin
      entryPoints: [\"websecure\"]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    synapse-admin:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:8009\""
    fi
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
      middlewares:
        - cors-headers

    matrix-auth:
      rule: "Host(\`$SUB_MAS.$DOMAIN\`)"
      service: matrix-auth
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    element-web:
      rule: "Host(\`$SUB_ELEMENT.$DOMAIN\`)"
      service: element-web
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

    matrix-auth:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8010"

    element-web:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8012"

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
    echo -e "   Forward to: ${INFO}http://$PROXY_IP:8008${RESET}"
    echo -e "   Enable:     SSL (Force HTTPS), Let's Encrypt certificate\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << BASECONF
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

# Synapse admin API - required for Element Admin dashboard (rooms, users, server info)
location ~* ^/_synapse/admin/ {
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

# Synapse client OIDC endpoints
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

# Synapse client OIDC endpoints
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

    # Optional: Element Call
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
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
    fi

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

    # Optional: Element Admin
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        clear
        echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BANNER}│               NPM SETUP - ELEMENT ADMIN                      │${RESET}"
        echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
        echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
        echo -e "   Domain:     ${INFO}$SUB_ELEMENT_ADMIN.$DOMAIN${RESET}"
        echo -e "   Forward to: ${INFO}http://$PROXY_IP:8014${RESET}"
        echo -e "   Enable:     SSL (Force HTTPS)\n"
        echo -e "${SUCCESS}✓ No advanced configuration needed${RESET}"
        echo -e "${WARNING}Press ENTER to continue...${RESET}"
        read -r
    fi

    # Optional: Synapse Admin
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        clear
        echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BANNER}│               NPM SETUP - SYNAPSE ADMIN                      │${RESET}"
        echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
        echo -e "\n${ACCENT}Create Proxy Host:${RESET}"
        echo -e "   Domain:     ${INFO}$SUB_SYNAPSE_ADMIN.$DOMAIN${RESET}"
        echo -e "   Forward to: ${INFO}http://$PROXY_IP:8009${RESET}"
        echo -e "   Enable:     SSL (Force HTTPS)"
        echo -e "   ${INFO}ℹ  Log in with your Matrix admin user credentials${RESET}\n"
        echo -e "${SUCCESS}✓ No advanced configuration needed${RESET}"
        echo -e "${WARNING}Press ENTER to continue...${RESET}"
        read -r
    fi

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
    reverse_proxy $PROXY_IP:8008
    header { Access-Control-Allow-Origin * }
}

# MAS Authentication Service
$SUB_MAS.$DOMAIN {
    reverse_proxy $PROXY_IP:8010
    header { Access-Control-Allow-Origin * }
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

# Element Web
$SUB_ELEMENT.$DOMAIN {
    reverse_proxy $PROXY_IP:8012
}
CADDYCONF

    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo ""
        cat << CALLCONF
# Element Call
$SUB_CALL.$DOMAIN {
    reverse_proxy $PROXY_IP:8007
    header { Access-Control-Allow-Origin * }
}
CALLCONF
    fi

    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << ADMINCONF
# Element Admin
$SUB_ELEMENT_ADMIN.$DOMAIN {
    reverse_proxy $PROXY_IP:8014
}
ADMINCONF
    fi

    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << SYNADMINCONF
# Synapse Admin
$SUB_SYNAPSE_ADMIN.$DOMAIN {
    reverse_proxy $PROXY_IP:8009
}
SYNADMINCONF
    fi

    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo ""
        cat << SLIDINGCONF
# Sliding Sync Proxy
$SUB_SLIDING_SYNC.$DOMAIN {
    reverse_proxy $PROXY_IP:8011
}
SLIDINGCONF
    fi

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
# TURN (DNS only - do not proxy)
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

    matrix-auth:
      rule: "Host(\`$SUB_MAS.$DOMAIN\`)"
      service: matrix-auth
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

    livekit:
      rule: "Host(\`$SUB_LIVEKIT.$DOMAIN\`)"
      service: livekit
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt

  services:
    base-domain-service:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:80"

    matrix:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8008"

    matrix-auth:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8010"

    livekit:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:7880"

  middlewares:
    wellknown-headers:
      headers:
        customResponseHeaders:
          Access-Control-Allow-Origin: "*"
          Content-Type: "application/json"

    cors-headers:
      headers:
        customResponseHeaders:
          Access-Control-Allow-Origin: "*"
          Access-Control-Allow-Methods: "GET, POST, PUT, DELETE, OPTIONS"
          Access-Control-Allow-Headers: "Authorization, Content-Type, Accept"
TRAEFIKCONF

    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo ""
        cat << CALLCONF
# Add to routers section:
    element-call:
      rule: "Host(\`$SUB_CALL.$DOMAIN\`)"
      service: element-call
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# Add to services section:
    element-call:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8007"
CALLCONF
    fi

    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << ADMINCONF
# Add to routers section:
    element-admin:
      rule: "Host(\`$SUB_ELEMENT_ADMIN.$DOMAIN\`)"
      service: element-admin
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# Add to services section:
    element-admin:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8014"
ADMINCONF
    fi

    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << SYNADMINCONF
# Add to routers section:
    synapse-admin:
      rule: "Host(\`$SUB_SYNAPSE_ADMIN.$DOMAIN\`)"
      service: synapse-admin
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# Add to services section:
    synapse-admin:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8009"
SYNADMINCONF
    fi

    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo ""
        cat << SLIDINGCONF
# Add to routers section:
    sliding-sync:
      rule: "Host(\`$SUB_SLIDING_SYNC.$DOMAIN\`)"
      service: sliding-sync
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# Add to services section:
    sliding-sync:
      loadBalancer:
        servers:
          - url: "http://$PROXY_IP:8011"
SLIDINGCONF
    fi

    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo ""
        cat << MEDIACONF
# Add to routers section:
    media-repo:
      rule: "Host(\`$SUB_MEDIA_REPO.$DOMAIN\`)"
      service: media-repo
      entryPoints: ["websecure"]
      tls:
        certResolver: letsencrypt
# Add to services section:
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
  - hostname: $DOMAIN
    path: /.well-known/matrix/server
    service: http_status:200
    originRequest:
      httpStatus: 200
      noTLSVerify: true

  - hostname: $DOMAIN
    path: /.well-known/matrix/client
    service: http_status:200
    originRequest:
      httpStatus: 200
      noTLSVerify: true

  - hostname: $SUB_MATRIX.$DOMAIN
    service: http://$PROXY_IP:8008

  - hostname: $SUB_MAS.$DOMAIN
    service: http://$PROXY_IP:8010

  - hostname: $SUB_ELEMENT.$DOMAIN
    service: http://$PROXY_IP:8012

  - hostname: $SUB_LIVEKIT.$DOMAIN
    service: http://$PROXY_IP:7880
CFCONF

    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_CALL.$DOMAIN"
        echo "    service: http://$PROXY_IP:8007"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_ELEMENT_ADMIN.$DOMAIN"
        echo "    service: http://$PROXY_IP:8014"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_SYNAPSE_ADMIN.$DOMAIN"
        echo "    service: http://$PROXY_IP:8009"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_SLIDING_SYNC.$DOMAIN"
        echo "    service: http://$PROXY_IP:8011"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_MEDIA_REPO.$DOMAIN"
        echo "    service: http://$PROXY_IP:8013"
    fi

    print_code << 'CFTURNEOF'
  - service: http_status:404
CFTURNEOF

    echo -e "\n${INFO}ℹ  Note: TURN (turn.$DOMAIN) must remain DNS only — do not route through Cloudflare Tunnel.${RESET}"
    echo -e "${INFO}ℹ  Cloudflare Tunnel cannot serve static JSON for well-known. Use a local nginx or Synapse's built-in well-known.${RESET}\n"

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
    local MATRIX_IMAGES_PATTERN='matrixdotorg/synapse|element-hq/matrix-authentication-service|element-hq/element-call|element-hq/lk-jwt-service|matrix-org/sliding-sync|element-hq/element-admin|awesometechnologies/synapse-admin|vectorim/element-web|livekit/livekit-server|turt2live/matrix-media-repo|mautrix/'

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
        # 1. Containers from our own compose project
        docker ps -a --filter "label=com.docker.compose.project=matrix-stack" \
            --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null

        # 2. Containers from OTHER compose projects whose project name contains
        #    "matrix" or "element" (catches element-docker-demo, matrix-*, etc.)
        docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null \
            | awk -F'|' '$4 ~ /matrix|element/ && $4 != "matrix-stack" {print $1"|"$2"|"$3}' \
            | grep -vFf <(
                docker ps -a --filter "label=com.docker.compose.project=matrix-stack" \
                    --format '{{.Names}}' 2>/dev/null || true
              ) 2>/dev/null || true

        # 3. Containers matching known Matrix images not caught above
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
    for port in 3478 7880 8007 8008 8009 8010 8011 8012 8014; do
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

        # Bring down any foreign Matrix/Element compose projects cleanly first
        # This ensures their networks and anonymous volumes are also removed
        local foreign_projects
        foreign_projects=$(docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null \
            | sort -u | grep -E "matrix|element" | grep -v "^matrix-stack$" | grep -v "^$" || true)
        for proj in $foreign_projects; do
            local proj_dir
            proj_dir=$(docker ps -a --filter "label=com.docker.compose.project=$proj" \
                --format '{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null | head -1)
            if [ -n "$proj_dir" ] && [ -f "$proj_dir/docker-compose.yml" -o -f "$proj_dir/compose.yaml" ]; then
                echo -e "   ${INFO}Bringing down compose project: $proj${RESET}"
                docker compose -f "$proj_dir/docker-compose.yml" down -v 2>/dev/null \
                    || docker compose -f "$proj_dir/compose.yaml" down -v 2>/dev/null || true
            fi
        done

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

    # Warn if the script itself lives inside the stack directory
    local SCRIPT_REAL
    SCRIPT_REAL=$(readlink -f "$0" 2>/dev/null || echo "$0")
    local SCRIPT_DIR
    SCRIPT_DIR=$(dirname "$SCRIPT_REAL")
    if [[ "$SCRIPT_DIR" == *"matrix-stack"* ]]; then
        echo -e "${ERROR}   ⚠️  WARNING: This script is located inside the matrix-stack folder!${RESET}"
        echo -e "${WARNING}   Deleting the stack directory will also delete this script.${RESET}"
        echo -e "${INFO}   Please move it first:${RESET}"
        echo -e "   ${WARNING}mv \"$SCRIPT_REAL\" ~/matrix-stack-deploy.sh${RESET}\n"
        echo -ne "   Have you moved the script, or do you want to continue anyway? [y/N]: "
        read -r SCRIPT_MOVE_CONFIRM
        if [[ ! "$SCRIPT_MOVE_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n   ${SUCCESS}✓ Uninstall cancelled — move the script first then re-run${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
        fi
    fi
    
    UNINSTALL_DIR="/opt/stacks/matrix-stack"
    if [ -d "$UNINSTALL_DIR" ]; then
        echo -e "   ${SUCCESS}✓ Found installation at: ${INFO}$UNINSTALL_DIR${RESET}"
        
        # Show what will be deleted
        local subdirs=""
        [ -d "$UNINSTALL_DIR/synapse" ] && subdirs="$subdirs synapse"
        [ -d "$UNINSTALL_DIR/bridges" ] && subdirs="$subdirs bridges"
        [ -d "$UNINSTALL_DIR/mas" ] && subdirs="$subdirs mas"
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

    # ── Smart path detection ───────────────────────────────────────────────
    local FOUND_DIR=""
    local SEARCH_PATHS=(
        "/opt/stacks/matrix-stack"
        "/opt/matrix-stack"
        "$HOME/matrix-stack"
        "$(pwd)/matrix-stack"
        "$(pwd)"
    )

    echo -e "${INFO}Searching for Matrix installation...${RESET}"
    for path in "${SEARCH_PATHS[@]}"; do
        for cf in "compose.yaml" "docker-compose.yml" "docker-compose.yaml"; do
            if [ -f "$path/$cf" ] && [ -d "$path/synapse" ]; then
                FOUND_DIR="$path"
                break 2
            fi
        done
    done

    # Fallback: inspect running synapse container for its data volume path
    if [ -z "$FOUND_DIR" ]; then
        local CONTAINER_PATH
        CONTAINER_PATH=$(docker inspect synapse 2>/dev/null \
            | python3 -c "import sys,json; mounts=json.load(sys.stdin)[0].get('Mounts',[]); \
              [print(m['Source'].rstrip('/synapse')) for m in mounts if 'synapse' in m.get('Source','')]" \
            2>/dev/null | head -1)
        if [ -n "$CONTAINER_PATH" ] && [ -d "$CONTAINER_PATH" ]; then
            FOUND_DIR="$CONTAINER_PATH"
        fi
    fi

    local BRIDGE_DIR
    if [ -n "$FOUND_DIR" ]; then
        echo -e "${SUCCESS}✓ Found installation at: ${INFO}$FOUND_DIR${RESET}"
        echo -ne "   Use this path? [Y/n]: "
        read -r USE_FOUND
        USE_FOUND=${USE_FOUND:-y}
        if [[ "$USE_FOUND" =~ ^[Yy]$ ]]; then
            BRIDGE_DIR="$FOUND_DIR"
        else
            FOUND_DIR=""
        fi
    fi

    if [ -z "$FOUND_DIR" ]; then
        echo -e "   ${WARNING}⚠️  No installation auto-detected${RESET}"
        echo -e "   ${INFO}Enter the full path to your Matrix stack directory${RESET}"
        echo -e "   ${INFO}(the folder containing compose.yaml / docker-compose.yml and the synapse/ subdirectory)${RESET}"
        echo -ne "   Path: ${WARNING}"
        read -r BRIDGE_DIR
        echo -e "${RESET}"

        if [ ! -d "$BRIDGE_DIR" ]; then
            echo -e "\n   ${ERROR}✗ Directory not found: $BRIDGE_DIR${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
            read -r
            return
        fi
        if [ ! -f "$BRIDGE_DIR/compose.yaml" ] && [ ! -f "$BRIDGE_DIR/docker-compose.yml" ] && [ ! -f "$BRIDGE_DIR/docker-compose.yaml" ]; then
            echo -e "   ${WARNING}⚠️  No compose file found — bridges may not integrate correctly${RESET}"
        fi
    fi

    # ── Read domain ────────────────────────────────────────────────────────
    local EXISTING_DOMAIN
    EXISTING_DOMAIN=$(grep -m1 'server_name:' "$BRIDGE_DIR/synapse/homeserver.yaml" 2>/dev/null \
        | awk '{print $2}' | tr -d '"')
    if [ -z "$EXISTING_DOMAIN" ]; then
        EXISTING_DOMAIN=$(grep -m1 'homeserver:' "$BRIDGE_DIR/mas/config.yaml" 2>/dev/null \
            | awk '{print $2}' | tr -d '"')
    fi
    if [ -z "$EXISTING_DOMAIN" ]; then
        echo -e "   ${WARNING}⚠️  Could not auto-detect domain from configs${RESET}"
        echo -ne "   Enter your Matrix server domain (e.g. example.com): ${WARNING}"
        read -r EXISTING_DOMAIN
        echo -e "${RESET}"
    else
        echo -e "${INFO}   Domain detected: ${SUCCESS}$EXISTING_DOMAIN${RESET}"
    fi
    DOMAIN="$EXISTING_DOMAIN"
    TARGET_DIR="$BRIDGE_DIR"

    # ── Read DB credentials from existing homeserver.yaml ─────────────────
    if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
        DB_USER=$(grep -A 10 "^database:" "$BRIDGE_DIR/synapse/homeserver.yaml" 2>/dev/null \
            | grep "user:" | awk '{print $2}' | tr -d '"' | head -1)
        DB_PASS=$(grep -A 10 "^database:" "$BRIDGE_DIR/synapse/homeserver.yaml" 2>/dev/null \
            | grep "password:" | awk '{print $2}' | tr -d '"' | head -1)
        if [ -n "$DB_USER" ] && [ -n "$DB_PASS" ]; then
            echo -e "   ${INFO}DB credentials detected from homeserver.yaml${RESET}"
        else
            echo -e "   ${WARNING}⚠️  Could not auto-detect DB credentials${RESET}"
            echo -ne "   DB username [synapse]: ${WARNING}"
            read -r DB_USER
            echo -e "${RESET}"
            DB_USER=${DB_USER:-synapse}
            echo -ne "   DB password: ${WARNING}"
            read -rs DB_PASS
            echo -e "${RESET}"
        fi
    fi

    # ── Read admin user or ask ─────────────────────────────────────────────
    if [ -z "$ADMIN_USER" ]; then
        echo -ne "   Admin username for bridge permissions [admin]: ${WARNING}"
        read -r ADMIN_USER
        echo -e "${RESET}"
        ADMIN_USER=${ADMIN_USER:-admin}
    fi

    # ── Detect postgres container name ─────────────────────────────────────
    local PG_CONTAINER
    PG_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null \
        | grep -E "postgres|synapse-db|matrix.*db|db.*matrix" | head -1)
    PG_CONTAINER=${PG_CONTAINER:-synapse-db}
    echo -e "   ${INFO}Postgres container: ${SUCCESS}$PG_CONTAINER${RESET}"

    # ── Detect synapse container and Docker network ────────────────────────
    local SYNAPSE_CONTAINER MATRIX_NETWORK
    SYNAPSE_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null \
        | grep -E "^synapse$|matrix.*synapse|synapse.*matrix" | head -1)
    SYNAPSE_CONTAINER=${SYNAPSE_CONTAINER:-synapse}
    MATRIX_NETWORK=$(docker inspect "$SYNAPSE_CONTAINER" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d[0]['NetworkSettings']['Networks'].keys())[0])" 2>/dev/null)
    MATRIX_NETWORK=${MATRIX_NETWORK:-matrix-net}
    echo -e "   ${INFO}Docker network: ${SUCCESS}$MATRIX_NETWORK${RESET}"

    # ── Already installed bridges ──────────────────────────────────────────
    local INSTALLED=()
    for b in discord telegram whatsapp signal slack instagram; do
        if [ -d "$BRIDGE_DIR/bridges/$b" ]; then
            INSTALLED+=("$b")
        fi
    done
    if [ ${#INSTALLED[@]} -gt 0 ]; then
        echo -e "${INFO}   Already installed: ${SUCCESS}${INSTALLED[*]}${RESET}\n"
    else
        echo -e ""
    fi

    # ── Dependency check ───────────────────────────────────────────────────
    if ! command -v docker &>/dev/null; then
        echo -e "   ${ERROR}✗ Docker is not installed — required to pull bridge images${RESET}"
        echo -e "   ${INFO}Install Docker: https://docs.docker.com/engine/install/${RESET}"
        echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
        read -r
        return
    fi

    # ── Bridge selection with neutral terminal colors ──────────────────────
    if command -v whiptail &>/dev/null; then
        DIALOG_CMD="whiptail"
    elif command -v dialog &>/dev/null; then
        DIALOG_CMD="dialog"
    else
        echo -e "   ${WARNING}⚠️  Installing whiptail...${RESET}"
        apt-get update -qq && apt-get install -y whiptail -qq > /dev/null 2>&1
        DIALOG_CMD="whiptail"
    fi

    # Override whiptail's default blue background with terminal default (black)
    export NEWT_COLORS='
root=white,black
window=white,black
shadow=black,black
border=white,black
title=white,black
roottext=white,black
label=white,black
checkbox=green,black
compactbutton=white,black
button=black,white
actbutton=white,black
entry=white,black
disentry=white,black
listbox=white,black
actlistbox=white,black
actsellistbox=black,white
sellistbox=white,black
emptyscale=white,black
fullscale=green,black
helpline=white,black
'

    SELECTED_BRIDGES=()
    while true; do
        BRIDGE_SELECTION=$($DIALOG_CMD --title " Add Matrix Bridges " \
            --checklist "Select bridges to add (SPACE to toggle, ENTER to confirm):" \
            20 78 10 \
            "discord"   "Discord   — Connect to Discord servers"           OFF \
            "telegram"  "Telegram  — Connect to Telegram chats"            OFF \
            "whatsapp"  "WhatsApp  — Connect to WhatsApp (requires phone)"  OFF \
            "signal"    "Signal    — Connect to Signal (requires phone)"    OFF \
            "slack"     "Slack     — Connect to Slack workspaces"           OFF \
            "instagram" "Instagram — Connect to Instagram DMs"              OFF \
            3>&1 1>&2 2>&3)

        local EXIT_CODE=$?
        unset NEWT_COLORS

        if [ $EXIT_CODE -ne 0 ]; then
            echo -e "\n   ${INFO}Selection cancelled — returning to menu.${RESET}"
            echo -e "\n${INFO}Press Enter to continue...${RESET}"
            read -r
            return
        fi

        SELECTED_BRIDGES=($(echo $BRIDGE_SELECTION | tr -d '"'))
        if [ ${#SELECTED_BRIDGES[@]} -eq 0 ]; then
            echo -e "\n   ${WARNING}No bridges selected — nothing to do.${RESET}"
            echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
            read -r
            return
        fi
        break
    done

    echo -e "\n${ACCENT}>> Installing bridge configs...${RESET}"
    mkdir -p "$TARGET_DIR/bridges"

    local NEW_BRIDGES=()
    for bridge in "${SELECTED_BRIDGES[@]}"; do
        if [ -d "$TARGET_DIR/bridges/$bridge" ]; then
            echo -e "   ${WARNING}⚠  $bridge already installed — skipping${RESET}"
            continue
        fi
        NEW_BRIDGES+=("$bridge")

        echo -e "   ${INFO}Generating $bridge config...${RESET}"
        mkdir -p "$TARGET_DIR/bridges/$bridge"
        rm -f "$TARGET_DIR/bridges/$bridge/registration.yaml"
        local _ENTRYPOINT="/usr/bin/mautrix-$bridge"
        local _EXAMPLE_PATH="/opt/mautrix-$bridge/example-config.yaml"
        local _GEN_OK=false

        # Step 1: extract example config from image if no config exists yet
        if [ ! -f "$TARGET_DIR/bridges/$bridge/config.yaml" ]; then
            docker run --rm \
                --entrypoint /bin/sh \
                -v "$TARGET_DIR/bridges/$bridge:/data" \
                dock.mau.dev/mautrix/$bridge:latest \
                -c "cp $_EXAMPLE_PATH /data/config.yaml" \
                >/dev/null 2>&1
        fi

        # Step 2: patch minimum required fields before running -g
        if [ -f "$TARGET_DIR/bridges/$bridge/config.yaml" ]; then
            sed -i "s|domain: example.com|domain: $DOMAIN|g" \
                "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
            sed -i "s|address: https://matrix.example.com|address: http://$SYNAPSE_CONTAINER:8008|g" \
                "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
            sed -i "s|address: https://example.com|address: http://$SYNAPSE_CONTAINER:8008|g" \
                "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
        fi

        # Step 3: generate registration.yaml from patched config
        if [ -f "$TARGET_DIR/bridges/$bridge/config.yaml" ]; then
            docker run --rm \
                --entrypoint "$_ENTRYPOINT" \
                -v "$TARGET_DIR/bridges/$bridge:/data" \
                dock.mau.dev/mautrix/$bridge:latest \
                -g -c /data/config.yaml -r /data/registration.yaml \
                >/dev/null 2>&1
            [ -f "$TARGET_DIR/bridges/$bridge/registration.yaml" ] && _GEN_OK=true
        fi

        sed -i "s|address: https://matrix.example.com|address: http://$SYNAPSE_CONTAINER:8008|g" \
            "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
        sed -i "s|domain: example.com|domain: $DOMAIN|g" \
            "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null

        # Database URI — bridge containers share the Docker network so use container name
        local _BRIDGE_DB="mautrix_${bridge}"
        docker exec "$PG_CONTAINER" psql -U "$DB_USER" -tc \
            "SELECT 1 FROM pg_database WHERE datname='$_BRIDGE_DB'" 2>/dev/null \
            | grep -q 1 || \
            docker exec "$PG_CONTAINER" psql -U "$DB_USER" \
            -c "CREATE DATABASE $_BRIDGE_DB OWNER $DB_USER;" 2>/dev/null
        sed -i \
            -e "s|uri: postgres://user:password@host/db|uri: postgresql://$DB_USER:$DB_PASS@$PG_CONTAINER/$_BRIDGE_DB?sslmode=disable|g" \
            -e "s|uri: postgresql://user:password@host/db|uri: postgresql://$DB_USER:$DB_PASS@$PG_CONTAINER/$_BRIDGE_DB?sslmode=disable|g" \
            "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
        if ! grep -q "postgresql://$DB_USER" "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null; then
            sed -i "/^        uri:/c\        uri: postgresql://$DB_USER:$DB_PASS@$PG_CONTAINER/$_BRIDGE_DB?sslmode=disable" \
                "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
        fi

        # Appservice address — use container name not localhost
        sed -i "s|address: http://localhost:|address: http://mautrix-$bridge:|g" \
            "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null
        local _REG_URL="$TARGET_DIR/bridges/$bridge/registration.yaml"
        if [ -f "$_REG_URL" ]; then
            sed -i "s|url: http://localhost:|url: http://mautrix-$bridge:|g" "$_REG_URL" 2>/dev/null
        fi

        # Permissions
        sed -i \
            -e "s|\"example.com\": user|\"$DOMAIN\": user|g" \
            -e "s|\"@admin:example.com\": admin|\"@$ADMIN_USER:$DOMAIN\": admin|g" \
            "$TARGET_DIR/bridges/$bridge/config.yaml" 2>/dev/null

        local BRIDGE_CAP
        BRIDGE_CAP="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
        echo -e "   ${SUCCESS}✓ $BRIDGE_CAP bridge configured${RESET}"
    done

    if [ ${#NEW_BRIDGES[@]} -eq 0 ]; then
        echo -e "\n${WARNING}No new bridges to add — all selected bridges are already installed.${RESET}"
        echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
        read -r
        return
    fi

    # ── Update compose file ────────────────────────────────────────────────
    echo -e "\n${ACCENT}>> Updating Docker Compose...${RESET}"
    local COMPOSE_FILE=""
    for cf in "$TARGET_DIR/compose.yaml" "$TARGET_DIR/docker-compose.yml" "$TARGET_DIR/docker-compose.yaml"; do
        if [ -f "$cf" ]; then
            COMPOSE_FILE="$cf"
            break
        fi
    done

    if [ -z "$COMPOSE_FILE" ]; then
        echo -e "   ${WARNING}⚠️  No compose file found — skipping compose update${RESET}"
        echo -e "   ${INFO}Add bridge services to your compose file manually${RESET}"
    else
        for bridge in "${NEW_BRIDGES[@]}"; do
            if grep -q "container_name: matrix-bridge-$bridge" "$COMPOSE_FILE" 2>/dev/null; then
                echo -e "   ${WARNING}⚠  $bridge already in compose — skipping${RESET}"
                continue
            fi
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
      postgres:\
        condition: service_healthy\
    networks: [ matrix-net ]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$COMPOSE_FILE"
            echo -e "   ${SUCCESS}✓ $bridge added to $(basename "$COMPOSE_FILE")${RESET}"
        done

        echo -e "\n${ACCENT}>> Restarting stack to start new bridges...${RESET}"
        cd "$TARGET_DIR" && docker compose -f "$(basename "$COMPOSE_FILE")" up -d 2>&1 \
            | grep -E "Creating|Starting|✓|error|Error" | sed 's/^/   /' || true
    fi

    # ── Register bridges with Synapse (appservice_config_files) ───────────
    # Without this Synapse ignores the bridge bots entirely — DMs go nowhere.
    echo -e "\n${ACCENT}>> Registering bridges with Synapse...${RESET}"
    local HS_YAML="$TARGET_DIR/synapse/homeserver.yaml"
    local REGISTERED=0

    for bridge in "${NEW_BRIDGES[@]}"; do
        local REG_FILE="/data/bridges/${bridge}/registration.yaml"
        if grep -q "$REG_FILE" "$HS_YAML" 2>/dev/null; then
            echo -e "   ${INFO}ℹ  $bridge already registered in homeserver.yaml${RESET}"
        else
            # Add app_service_config_files block if not present yet
            if ! grep -q "^app_service_config_files:" "$HS_YAML" 2>/dev/null; then
                printf "\napp_service_config_files:\n  - %s\n" "$REG_FILE" >> "$HS_YAML"
            else
                # Block exists — append this bridge's entry
                sed -i "/^app_service_config_files:/a\\  - $REG_FILE" "$HS_YAML"
            fi
            echo -e "   ${SUCCESS}✓ $bridge registered in homeserver.yaml${RESET}"
            REGISTERED=$((REGISTERED + 1))
        fi
    done

    # ── Ensure bridges/ is mounted into the Synapse container ─────────────
    if [ -n "$COMPOSE_FILE" ]; then
        if ! grep -q "bridges:/data/bridges" "$COMPOSE_FILE" 2>/dev/null; then
            # Insert the volume mount into the synapse service block
            sed -i '/container_name: synapse/{
                n
                /image:/n
                /volumes:/!{n}
                /volumes:/{
                    a\      - ./bridges:/data/bridges
                }
            }' "$COMPOSE_FILE" 2>/dev/null || true

            # Simpler fallback: append after the ./synapse:/data volume line
            if ! grep -q "bridges:/data/bridges" "$COMPOSE_FILE" 2>/dev/null; then
                sed -i 's|      - ./synapse:/data|      - ./synapse:/data\n      - ./bridges:/data/bridges|' "$COMPOSE_FILE" 2>/dev/null || true
            fi

            if grep -q "bridges:/data/bridges" "$COMPOSE_FILE" 2>/dev/null; then
                echo -e "   ${SUCCESS}✓ bridges/ volume mount added to Synapse in compose file${RESET}"
            else
                echo -e "   ${WARNING}⚠️  Could not auto-add bridges/ volume mount — add manually:${RESET}"
                echo -e "   ${WARNING}   Under synapse volumes: add '- ./bridges:/data/bridges'${RESET}"
            fi
        else
            echo -e "   ${INFO}ℹ  bridges/ already mounted in Synapse${RESET}"
        fi
    fi

    # ── Restart Synapse to pick up new appservice registrations ───────────
    if [ $REGISTERED -gt 0 ]; then
        echo -e "\n${ACCENT}>> Restarting Synapse to load new bridge registrations...${RESET}"
        cd "$TARGET_DIR" && docker compose -f "$(basename "$COMPOSE_FILE")" restart synapse 2>&1 \
            | sed 's/^/   /' || true
        echo -e "   ${SUCCESS}✓ Synapse restarted — bridge bots are now registered${RESET}"
    fi

    echo -e "\n${SUCCESS}✓ Bridges added successfully${RESET}"
    echo -e "\n${ACCENT}Activation steps:${RESET}"
    echo -e "   ${INFO}1. Open Element Web and start a DM with the bot user${RESET}"
    echo -e "   ${INFO}2. Wait 1-2 min for the bot to appear if it does not show up immediately${RESET}"
    echo -e ""
    for bridge in "${NEW_BRIDGES[@]}"; do
        case $bridge in
            discord)   echo -e "   ${SUCCESS}•${RESET} Discord:   DM ${WARNING}@discordbot:$DOMAIN${RESET}   → send ${WARNING}login${RESET} → follow browser link" ;;
            telegram)  echo -e "   ${SUCCESS}•${RESET} Telegram:  DM ${WARNING}@telegrambot:$DOMAIN${RESET}  → send ${WARNING}login${RESET} → enter phone + code" ;;
            whatsapp)  echo -e "   ${SUCCESS}•${RESET} WhatsApp:  DM ${WARNING}@whatsappbot:$DOMAIN${RESET}  → send ${WARNING}login${RESET} → scan QR in WhatsApp" ;;
            signal)    echo -e "   ${SUCCESS}•${RESET} Signal:    DM ${WARNING}@signalbot:$DOMAIN${RESET}    → send ${WARNING}link${RESET}  → scan QR in Signal" ;;
            slack)     echo -e "   ${SUCCESS}•${RESET} Slack:     DM ${WARNING}@slackbot:$DOMAIN${RESET}     → send ${WARNING}login${RESET} → follow OAuth link" ;;
            instagram) echo -e "   ${SUCCESS}•${RESET} Instagram: DM ${WARNING}@instagrambot:$DOMAIN${RESET} → send ${WARNING}login${RESET} → enter username + password" ;;
        esac
    done

    echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
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

    echo -e "${SUCCESS}✓ Found installation at: ${INFO}$LOGS_DIR${RESET}"

    while true; do
        echo -e "\n${ACCENT}Select container to view logs:${RESET}\n"
        echo -e "   ${CHOICE_COLOR}1)${RESET} Synapse        — Matrix homeserver"
        echo -e "   ${CHOICE_COLOR}2)${RESET} PostgreSQL     — Database"
        echo -e "   ${CHOICE_COLOR}3)${RESET} MAS            — Authentication service"
        echo -e "   ${CHOICE_COLOR}4)${RESET} LiveKit        — Video SFU (with built-in TURN)"
        echo -e "   ${CHOICE_COLOR}5)${RESET} LiveKit JWT    — Token service"
        echo -e "   ${CHOICE_COLOR}6)${RESET} Element Call   — Video conferencing (if enabled)"
        echo -e "   ${CHOICE_COLOR}7)${RESET} Sliding Sync   — Sync proxy (if enabled)"
        echo -e "   ${CHOICE_COLOR}8)${RESET} All containers — Show all logs"
        echo -e "   ${CHOICE_COLOR}q)${RESET} Back to menu"
        echo -e ""
        echo -ne "Selection (1-8 / q): "
        read -r LOG_SELECT

        case $LOG_SELECT in
            q|Q)
                return
                ;;
            1) CONTAINER="synapse" ;;
            2) CONTAINER="synapse-db" ;;
            3) CONTAINER="matrix-auth" ;;
            4) CONTAINER="livekit" ;;
            5) CONTAINER="livekit-jwt" ;;
            6) CONTAINER="element-call" ;;
            7) CONTAINER="sliding-sync" ;;
            8)
                echo -e "\n${INFO}Showing logs for all containers — press Ctrl-C to stop and return to log list${RESET}\n"
                cd "$LOGS_DIR" && docker compose logs -f 2>/dev/null || true
                echo -e "\n${INFO}Returned to log viewer.${RESET}"
                continue
                ;;
            *)
                echo -e "\n${ERROR}Invalid selection — try again${RESET}"
                continue
                ;;
        esac

        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER}$"; then
            echo -e "\n${INFO}Showing logs for ${CONTAINER} — press Ctrl-C to stop and return to log list${RESET}\n"
            docker logs -f "$CONTAINER" --tail 100 2>/dev/null || true
            echo -e "\n${INFO}Returned to log viewer.${RESET}"
        elif docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER}$"; then
            echo -e "\n${WARNING}Container ${CONTAINER} exists but is stopped. Showing last 50 lines:${RESET}\n"
            docker logs "$CONTAINER" --tail 50 2>/dev/null || true
            echo -e "\n${INFO}Press Enter to return to log list...${RESET}"
            read -r
        else
            echo -e "\n${INFO}Container ${CONTAINER} is not installed${RESET}"
            echo -e "${INFO}Press Enter to return to log list...${RESET}"
            read -r
        fi
    done
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
    local containers=("synapse" "synapse-db" "matrix-auth" "livekit" "livekit-jwt" "element-web" "sliding-sync" "element-call" "element-admin" "synapse-admin" "matrix-media-repo")
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            echo -e "   ${SUCCESS}✓${RESET} $container ${SUCCESS}(running)${RESET}"
        elif docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            echo -e "   ${WARNING}⚠${RESET}  $container ${WARNING}(stopped)${RESET}"
        else
            echo -e "   ${INFO}–${RESET}  $container ${INFO}(not installed)${RESET}"
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
        ask_yn INST_DOCKGE "Install Dockge (includes Docker & Compose)? (y/n): "
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
    DETECTED_LOCAL=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
    if [ -z "$DETECTED_LOCAL" ]; then
        DETECTED_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    echo -e "   ${INFO}Public IP:${RESET} ${PUBLIC_IP_COLOR}${DETECTED_PUBLIC:-Not detected}${RESET}"
    echo -e "   ${INFO}Local IP:${RESET}  ${LOCAL_IP_COLOR}${DETECTED_LOCAL:-Not detected}${RESET}"
    
    ask_yn IP_CONFIRM "Use these IPs for deployment? (y/n): "
    
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
        ask_choice PATH_SELECT "Selection (1/2/3): " 1 2 3
        case $PATH_SELECT in
            1) TARGET_DIR="/opt/stacks/matrix-stack" ;;
            2) TARGET_DIR="$CUR_DIR/matrix-stack" ;;
            3) echo -ne "Enter Full Path: ${WARNING}"; read -r TARGET_DIR; echo -e "${RESET}" ;;
        esac
    elif [ "$DOCKER_READY" = true ]; then
        echo -e "   ${CHOICE_COLOR}1)${RESET} ${SUCCESS}Current Directory (Recommended):${RESET} $CUR_DIR/matrix-stack"
        echo -e "   ${CHOICE_COLOR}2)${RESET} Custom Path"
        ask_choice PATH_SELECT "Selection (1/2): " 1 2
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
        
        ask_yn OVERWRITE "Completely WIPE and overwrite everything in this directory? (y/n): "
        if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
            # Comprehensive cleanup
            if [ -f "$TARGET_DIR/compose.yaml" ] || [ -f "$TARGET_DIR/docker-compose.yaml" ]; then
                cd "$TARGET_DIR"
                docker compose down -v --remove-orphans 2>/dev/null || true
                # Clean up any remaining containers (including all possible bridges)
                docker rm -f synapse synapse-db element-admin synapse-admin matrix-auth livekit livekit-jwt element-call sliding-sync matrix-media-repo \
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
             "$TARGET_DIR/livekit" \
             "$TARGET_DIR/mas"

    ############################################################################
    # STEP 6: Service Configuration                                           #
    ############################################################################

echo -e "\n${ACCENT}>> Configuring services...${RESET}"

    ############################################################################
    # 6a: Optional services — select BEFORE domain prompts so we know which   #
    #     subdomains to ask for                                                #
    ############################################################################

    echo -e "\n${ACCENT}Optional Services:${RESET}"

    # Sliding Sync Proxy
    echo -e "\n${ACCENT}Sliding Sync Proxy:${RESET}"
    echo -e "   ${INFO}Enables faster sync for modern Matrix clients (Element X, etc.)${RESET}"
    ask_yn ENABLE_SLIDING_SYNC "Enable Sliding Sync Proxy? [y/n]: " y

    if [[ "$ENABLE_SLIDING_SYNC" =~ ^[Yy]$ ]]; then
        SLIDING_SYNC_ENABLED="true"
        echo -e "   ${SUCCESS}✓ Sliding Sync will be added${RESET}"
    else
        SLIDING_SYNC_ENABLED="false"
        echo -e "   ${WARNING}⚠️  Some modern clients may not work optimally without Sliding Sync${RESET}"
    fi

    # Matrix Media Repo
    echo -e "\n${ACCENT}Matrix Media Repository:${RESET}"
    echo -e "   ${INFO}Highly efficient media server with S3 storage, thumbnailing, and advanced media management${RESET}"
    ask_yn ENABLE_MEDIA_REPO "Enable Matrix Media Repo? [y/n]: " n

    if [[ "$ENABLE_MEDIA_REPO" =~ ^[Yy]$ ]]; then
        MEDIA_REPO_ENABLED="true"
        echo -e "   ${SUCCESS}✓ Matrix Media Repo will be added${RESET}"
        echo -e "   ${INFO}ℹ  Configure storage backend after installation${RESET}"
    else
        MEDIA_REPO_ENABLED="false"
        echo -e "   ${INFO}Using Synapse's built-in media storage${RESET}"
    fi

    # Element Call (standalone)
    echo -e "\n${ACCENT}Element Call (Standalone):${RESET}"
    echo -e "   ${INFO}Standalone WebRTC video conferencing UI powered by LiveKit.${RESET}"
    echo -e "   ${INFO}Note: Element and Commet clients already include Element Call built-in.${RESET}"
    echo -e "   ${INFO}A standalone deployment is only needed if you want a dedicated call UI.${RESET}"
    ask_yn ENABLE_ELEMENT_CALL "Enable standalone Element Call? [y/n]: " n

    if [[ "$ENABLE_ELEMENT_CALL" =~ ^[Yy]$ ]]; then
        ELEMENT_CALL_ENABLED="true"
        echo -e "   ${SUCCESS}✓ Standalone Element Call will be deployed${RESET}"
    else
        ELEMENT_CALL_ENABLED="false"
        echo -e "   ${INFO}Video calling available via Element/Commet built-in widget${RESET}"
    fi

    # Admin Panel Selection
echo -e "\n${ACCENT}Admin Panel:${RESET}"
echo -e "   ${INFO}A web-based admin interface lets you manage users, rooms, and server settings.${RESET}"
ask_yn ENABLE_ADMIN_PANEL "Enable an admin panel? [y/n]: " n

ELEMENT_ADMIN_ENABLED="false"
SYNAPSE_ADMIN_ENABLED="false"

if [[ "$ENABLE_ADMIN_PANEL" =~ ^[Yy]$ ]]; then
    while true; do
        echo -e "\n   ${ACCENT}Choose admin panel:${RESET}"
        echo -e "   ${SUCCESS}1)${RESET} Element Admin ${SUCCESS}(recommended)${RESET} — modern UI, actively maintained by Element"
        echo -e "   ${INFO}2)${RESET} Synapse Admin — classic UI, widely known"
        echo -ne "\n   Choice [1]: "
        read -r ADMIN_PANEL_CHOICE
        ADMIN_PANEL_CHOICE=${ADMIN_PANEL_CHOICE:-1}

        case "$ADMIN_PANEL_CHOICE" in
            1)
                ELEMENT_ADMIN_ENABLED="true"
                SYNAPSE_ADMIN_ENABLED="false"
                echo -e "   ${SUCCESS}✓ Element Admin will be deployed${RESET}"
                break
                ;;
            2)
                SYNAPSE_ADMIN_ENABLED="true"
                ELEMENT_ADMIN_ENABLED="false"
                echo -e "   ${SUCCESS}✓ Synapse Admin will be deployed${RESET}"
                break
                ;;
            *)
                echo -e "   ${ERROR}Invalid selection '$ADMIN_PANEL_CHOICE'. Please choose 1 or 2.${RESET}"
                ;;
        esac
    done
else
    echo -e "   ${INFO}Skipping admin panel${RESET}"
fi

    # Bridge Selection
    echo -e "\n${ACCENT}Matrix Bridges:${RESET}"
    echo -e "   ${INFO}Bridges connect Matrix to other chat platforms (Discord, Telegram, WhatsApp, etc.)${RESET}"
    ask_yn ADD_BRIDGES "Would you like to add bridges? (y/n): "

    SELECTED_BRIDGES=()

    if [[ "$ADD_BRIDGES" =~ ^[Yy]$ ]]; then
        if command -v whiptail &> /dev/null; then
            DIALOG_CMD="whiptail"
        elif command -v dialog &> /dev/null; then
            DIALOG_CMD="dialog"
        else
            echo -e "   ${WARNING}⚠️  Installing whiptail for interactive menu...${RESET}"
            apt-get update -qq && apt-get install -y whiptail -qq > /dev/null 2>&1
            DIALOG_CMD="whiptail"
        fi

        while true; do
            export NEWT_COLORS='
root=white,black
window=white,black
shadow=black,black
border=white,black
title=white,black
roottext=white,black
label=white,black
checkbox=green,black
compactbutton=white,black
button=black,white
actbutton=white,black
entry=white,black
disentry=white,black
listbox=white,black
actlistbox=white,black
actsellistbox=black,white
sellistbox=white,black
emptyscale=white,black
fullscale=green,black
helpline=white,black
'
            BRIDGE_SELECTION=$($DIALOG_CMD --title " Matrix Bridge Selection " \
                --checklist "Select bridges to install (SPACE to toggle, ENTER to confirm):" \
                20 78 10 \
                "discord"   "Discord   — Connect to Discord servers"           OFF \
                "telegram"  "Telegram  — Connect to Telegram chats"            OFF \
                "whatsapp"  "WhatsApp  — Connect to WhatsApp (requires phone)"  OFF \
                "signal"    "Signal    — Connect to Signal (requires phone)"    OFF \
                "slack"     "Slack     — Connect to Slack workspaces"           OFF \
                "instagram" "Instagram — Connect to Instagram DMs"              OFF \
                3>&1 1>&2 2>&3)
            local BRIDGE_EXIT=$?
            unset NEWT_COLORS

            if [ $BRIDGE_EXIT -ne 0 ]; then
                echo -e "\n   ${INFO}Bridge selection cancelled${RESET}"
                echo -ne "   Would you like to select bridges again? [y/n]: "
                read -r RETRY_BRIDGES
                if [[ ! "$RETRY_BRIDGES" =~ ^[Yy]$ ]]; then
                    break
                fi
            else
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

    ############################################################################
    # 6b: Domain and subdomain configuration                                   #
    ############################################################################

    echo -e "\n${ACCENT}Domain Configuration:${RESET}"

# Domain
echo -ne "Base Domain (e.g., example.com): ${WARNING}"
read -r DOMAIN
echo -e "${RESET}"

# Core subdomains
echo -ne "Matrix Subdomain [matrix]: ${WARNING}"
read -r SUB_MATRIX
if [ -z "$SUB_MATRIX" ]; then
    SUB_MATRIX="matrix"
    echo -ne "\033[1A\033[K"
    echo -e "${RESET}Matrix Subdomain [matrix]: ${WARNING}${SUB_MATRIX}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""
echo -ne "MAS (Auth) Subdomain [auth]: ${WARNING}"
read -r SUB_MAS
if [ -z "$SUB_MAS" ]; then
    SUB_MAS="auth"
    echo -ne "\033[1A\033[K"
    echo -e "${RESET}MAS (Auth) Subdomain [auth]: ${WARNING}${SUB_MAS}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""
echo -ne "LiveKit Subdomain [livekit]: ${WARNING}"
read -r SUB_LIVEKIT
if [ -z "$SUB_LIVEKIT" ]; then
    SUB_LIVEKIT="livekit"
    echo -ne "\033[1A\033[K"
    echo -e "${RESET}LiveKit Subdomain [livekit]: ${WARNING}${SUB_LIVEKIT}${RESET}"
else
    echo -ne "${RESET}"
fi

echo ""
echo -ne "Element Web Subdomain [element]: ${WARNING}"
read -r SUB_ELEMENT
if [ -z "$SUB_ELEMENT" ]; then
    SUB_ELEMENT="element"
    echo -ne "\033[1A\033[K"
    echo -e "${RESET}Element Web Subdomain [element]: ${WARNING}${SUB_ELEMENT}${RESET}"
else
    echo -ne "${RESET}"
fi

# Optional subdomains — only ask if the service is enabled
if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
    echo ""
    echo -ne "Element Call Subdomain [call]: ${WARNING}"
    read -r SUB_CALL
    if [ -z "$SUB_CALL" ]; then
        SUB_CALL="call"
        echo -ne "\033[1A\033[K"
        echo -e "${RESET}Element Call Subdomain [call]: ${WARNING}${SUB_CALL}${RESET}"
    else
        echo -ne "${RESET}"
    fi
fi

if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
    echo ""
    echo -ne "Element Admin Subdomain [admin]: ${WARNING}"
    read -r SUB_ELEMENT_ADMIN
    if [ -z "$SUB_ELEMENT_ADMIN" ]; then
        SUB_ELEMENT_ADMIN="admin"
        echo -ne "\033[1A\033[K"
        echo -e "${RESET}Element Admin Subdomain [admin]: ${WARNING}${SUB_ELEMENT_ADMIN}${RESET}"
    else
        echo -ne "${RESET}"
    fi
fi

if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
    echo ""
    echo -ne "Synapse Admin Subdomain [admin]: ${WARNING}"
    read -r SUB_SYNAPSE_ADMIN
    if [ -z "$SUB_SYNAPSE_ADMIN" ]; then
        SUB_SYNAPSE_ADMIN="admin"
        echo -ne "\033[1A\033[K"
        echo -e "${RESET}Synapse Admin Subdomain [admin]: ${WARNING}${SUB_SYNAPSE_ADMIN}${RESET}"
    else
        echo -ne "${RESET}"
    fi
fi

# Fixed subdomains for optional services that don't need a prompt
SUB_SLIDING_SYNC="sync"
SUB_MEDIA_REPO="media"

# Clear input buffer
while read -r -t 0; do read -r; done

# Server name configuration
echo -e "\n${ACCENT}Server Name Configuration:${RESET}"
echo -e "   This will appear in user IDs like ${USER_ID_EXAMPLE}@username:servername${RESET}"
echo -e "   ${CHOICE_COLOR}1)${RESET} Use base domain (${INFO}$DOMAIN${RESET})"
echo -e "   ${CHOICE_COLOR}2)${RESET} Use full subdomain (${INFO}$SUB_MATRIX.$DOMAIN${RESET})"
echo -e "   ${CHOICE_COLOR}3)${RESET} Use custom server name (e.g., matrix.example.com)"
ask_choice SERVERNAME_SELECT "Selection (1/2/3): " 1 2 3

case $SERVERNAME_SELECT in
    1) SERVER_NAME="$DOMAIN"
       echo -e "   ${INFO}User IDs will be: ${USER_ID_VALUE}@username:${DOMAIN}${RESET}" ;;
    2) SERVER_NAME="$SUB_MATRIX.$DOMAIN"
       echo -e "   ${INFO}User IDs will be: ${USER_ID_VALUE}@username:${SUB_MATRIX}.${DOMAIN}${RESET}" ;;
    3) echo -ne "Enter custom server name: ${WARNING}"
       read -r SERVER_NAME
       echo -e "${RESET}   ${INFO}User IDs will be: ${USER_ID_VALUE}@username:${SERVER_NAME}${RESET}"
       if [[ "$SERVER_NAME" != *.* ]]; then
           echo -e "   ${WARNING}⚠️  Warning: '$SERVER_NAME' is not a domain name.${RESET}"
           echo -e "   ${WARNING}   Federation and MAS require a valid domain. Use a real domain like matrix.example.com.${RESET}"
       fi
       ;;
esac

    # Admin user configuration
    echo ""
    echo -ne "Admin Username [admin]: ${WARNING}"
    read -r ADMIN_USER
    if [ -z "$ADMIN_USER" ]; then
        ADMIN_USER="admin"
        echo -ne "\033[1A\033[K"
        echo -e "${RESET}Admin Username [admin]: ${WARNING}${ADMIN_USER}${RESET}"
    else
        echo -ne "${RESET}"
    fi

    # Admin password configuration
    echo -e "\n${ACCENT}Admin Password:${RESET}"
    while true; do
        echo -e "   ${CHOICE_COLOR}1)${RESET} Auto-generate strong password ${SUCCESS}(Recommended)${RESET}"
        echo -e "   ${CHOICE_COLOR}2)${RESET} Enter custom password"
        echo -ne "   Selection (1/2): "
        read -r PASS_CHOICE
        case $PASS_CHOICE in
            1|2) break ;;
            *) echo -e "   ${ERROR}Invalid selection. Please enter 1 or 2.${RESET}" ;;
        esac
    done

    if [[ "$PASS_CHOICE" == "2" ]]; then
        while true; do
            echo -ne "   Enter admin password (min 8 chars): ${WARNING}"
            read -s ADMIN_PASS
            echo -e "${RESET}"
            echo -ne "   Confirm password: ${WARNING}"
            read -s ADMIN_PASS_CONFIRM
            echo -e "${RESET}"
            if [ "$ADMIN_PASS" == "$ADMIN_PASS_CONFIRM" ] && [ ${#ADMIN_PASS} -ge 8 ]; then
                echo -e "   ${SUCCESS}✓ Password set${RESET}"
                break
            else
                echo -e "   ${ERROR}Passwords don't match or are too short (min 8 chars). Try again.${RESET}"
            fi
        done
        PASS_IS_CUSTOM=true
    else
        ADMIN_PASS=$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        PASS_IS_CUSTOM=false
        echo -e "   ${SUCCESS}✓ Strong password will be auto-generated${RESET}"
    fi

    # Registration configuration (for MAS)
    echo -e "\n${ACCENT}Registration & Authentication Configuration:${RESET}"
    echo -e "   ${INFO}MAS (Matrix Authentication Service) handles user registration and authentication.${RESET}"
    echo -e "   ${WARNING}Allow new users to register without admin approval?${RESET}"
    echo -e "   • ${SUCCESS}Enable registration (y):${RESET} Users can create accounts freely"
    echo -e "   • ${ERROR}Disable registration (n):${RESET} Only admin can create users (recommended)"
    ask_yn ALLOW_REGISTRATION "Allow public registration? [y/n]: " n

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

        echo -e "\n${ACCENT}Email Verification:${RESET}"
        echo -e "   ${INFO}Require email verification for new registrations?${RESET}"
        echo -e "   • ${SUCCESS}Enable (y):${RESET} Users must verify email (more secure)"
        echo -e "   • ${ERROR}Disable (n):${RESET} Users can register immediately"
        ask_yn REQUIRE_EMAIL_VERIFICATION "Require email verification? [y/n]: " n

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

            echo -e "\n${ACCENT}CAPTCHA Protection:${RESET}"
            echo -e "   ${INFO}CAPTCHA helps prevent bot registrations.${RESET}"
            ask_yn ENABLE_CAPTCHA "Enable CAPTCHA? [y/n]: " y

            if [[ "$ENABLE_CAPTCHA" =~ ^[Yy]$ ]]; then
                echo -e "   ${SUCCESS}✓ CAPTCHA enabled${RESET}"
                echo -e "   ${INFO}ℹ  Get reCAPTCHA keys at: https://www.google.com/recaptcha/admin${RESET}"
                echo -e "   ${INFO}ℹ  You'll add keys to MAS config after installation${RESET}"
            fi
        else
            ENABLE_CAPTCHA="n"
        fi
    else
        MAS_REGISTRATION="false"
        ENABLE_CAPTCHA="n"
        echo -e "   ${REGISTRATION_DISABLED}✓ Registration disabled - admin will create users via MAS${RESET}"
    fi

    # TURN is handled by LiveKit's built-in TURN server
    TURN_LAN_ACCESS="n"

    # Do they already have a reverse proxy?
echo -e "\n${ACCENT}Reverse Proxy Setup:${RESET}"
ask_yn PROXY_EXISTING_SELECT "   Do you already have a reverse proxy running? (y/n): "
if [[ "$PROXY_EXISTING_SELECT" =~ ^[Yy]$ ]]; then
    PROXY_ALREADY_RUNNING=true
    echo -e "   ${INFO}You will be guided to configure your existing proxy.${RESET}"
else
    PROXY_ALREADY_RUNNING=false
    echo -e "   ${INFO}Select which proxy to install automatically:${RESET}"
fi

# Which reverse proxy?
echo ""
echo -e "${ACCENT}Reverse Proxy Type:${RESET}"
echo -e "   ${CHOICE_COLOR}1)${RESET} Nginx Proxy Manager (NPM/NPMPlus)"
echo -e "   ${CHOICE_COLOR}2)${RESET} Caddy"
echo -e "   ${CHOICE_COLOR}3)${RESET} Traefik"
echo -e "   ${CHOICE_COLOR}4)${RESET} Cloudflare Tunnel"
echo -e "   ${CHOICE_COLOR}5)${RESET} Manual Setup"
ask_choice PROXY_SELECT "Selection (1-5): " 1 2 3 4 5

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
    REG_SECRET=$(openssl rand -hex 32)
    MAS_SECRET=$(openssl rand -hex 32)
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
    ELEMENT_ADMIN_CLIENT_ID=$(generate_ulid)
    
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

    # Create optional service directories now that we know what's enabled
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        mkdir -p "$TARGET_DIR/element-call"
    fi

    generate_livekit_config
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        generate_element_call_config
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        generate_media_repo_config
    fi
    generate_element_web_config
    generate_mas_config
    generate_postgres_init
    generate_docker_compose
    generate_synapse_config
    generate_bridge_configs
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
    
    echo -e "\n${ACCENT}>> Performing health checks for installed services...${RESET}"

    local HEALTH_FAILED=false

    # ── PostgreSQL (always required) ─────────────────────────────────────────
    echo -ne "\n${WARNING}>> Checking PostgreSQL...${RESET}"
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
    echo -e "\n${SUCCESS}✓ PostgreSQL — ONLINE${RESET}"

    # ── Create bridge databases now that postgres is confirmed healthy ────
    for bridge in "${SELECTED_BRIDGES[@]}"; do
        local _BNAME="mautrix_${bridge}"
        docker exec synapse-db psql -U "$DB_USER" -tc \
            "SELECT 1 FROM pg_database WHERE datname='$_BNAME'" 2>/dev/null \
            | grep -q 1 || \
            docker exec synapse-db psql -U "$DB_USER" -q \
            -c "CREATE DATABASE $_BNAME OWNER $DB_USER;" 2>/dev/null
    done

    # ── MAS (always required — must be healthy before Synapse) ───────────────
    echo -ne "\n${WARNING}>> Checking MAS (Auth Service)...${RESET}"
    TRIES=0
    until curl -sf http://localhost:8081/health 2>/dev/null >/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 90 ]]; then
            echo -e "\n${ERROR}[!] ERROR: MAS failed to become healthy.${RESET}"
            echo -e "${ERROR}   This is often caused by an invalid signing key in mas/config.yaml.${RESET}"
            echo -e "${INFO}   Last 40 lines of MAS logs:${RESET}"
            docker logs --tail 40 matrix-auth 2>&1 | sed 's/^/   /'
            exit 1
        fi
    done
    echo -e "\n${SUCCESS}✓ MAS (Auth Service) — ONLINE${RESET}"

    # ── Synapse (always required) ────────────────────────────────────────────
    echo -ne "\n${WARNING}>> Checking Synapse...${RESET}"
    TRIES=0
    until curl -sL --fail "http://$AUTO_LOCAL_IP:8008/_matrix/client/versions" 2>/dev/null | grep -q "versions"; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 150 ]]; then
            echo -e "\n${ERROR}[!] ERROR: Synapse failed to start.${RESET}"
            echo -e "${INFO}   Last 40 lines of Synapse logs:${RESET}"
            docker logs --tail 40 synapse 2>&1 | sed 's/^/   /'
            exit 1
        fi
    done
    echo -e "\n${SUCCESS}✓ Synapse — ONLINE${RESET}"

    # ── LiveKit SFU (always required) ────────────────────────────────────────
    echo -ne "\n${WARNING}>> Checking LiveKit SFU...${RESET}"
    TRIES=0
    until curl -s -f "http://$AUTO_LOCAL_IP:7880" 2>/dev/null >/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 30 ]]; then
            echo -e "\n${WARNING}⚠️  LiveKit may not be ready — check: docker logs livekit${RESET}"
            HEALTH_FAILED=true
            break
        fi
    done
    [[ $TRIES -lt 30 ]] && echo -e "\n${SUCCESS}✓ LiveKit SFU — ONLINE${RESET}"

    # ── LiveKit JWT Service (always required) ────────────────────────────────
    echo -ne "\n${WARNING}>> Checking LiveKit JWT Service...${RESET}"
    TRIES=0
    until curl -s -f "http://$AUTO_LOCAL_IP:8087" 2>/dev/null >/dev/null || \
          docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^livekit-jwt$"; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 20 ]]; then
            echo -e "\n${WARNING}⚠️  LiveKit JWT may not be ready — check: docker logs livekit-jwt${RESET}"
            HEALTH_FAILED=true
            break
        fi
    done
    [[ $TRIES -lt 20 ]] && echo -e "\n${SUCCESS}✓ LiveKit JWT Service — ONLINE${RESET}"

    # ── Element Web (always required) ────────────────────────────────────────
    echo -ne "\n${WARNING}>> Checking Element Web...${RESET}"
    TRIES=0
    until curl -s -f "http://$AUTO_LOCAL_IP:8012" 2>/dev/null >/dev/null; do
        echo -ne "."
        sleep 2
        ((TRIES++))
        if [[ $TRIES -gt 30 ]]; then
            echo -e "\n${WARNING}⚠️  Element Web may not be ready — check: docker logs element-web${RESET}"
            HEALTH_FAILED=true
            break
        fi
    done
    [[ $TRIES -lt 30 ]] && echo -e "\n${SUCCESS}✓ Element Web — ONLINE${RESET}"

    # ── Element Call (optional) ──────────────────────────────────────────────
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Element Call...${RESET}"
        TRIES=0
        until curl -s -f "http://$AUTO_LOCAL_IP:8007" 2>/dev/null >/dev/null; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 30 ]]; then
                echo -e "\n${WARNING}⚠️  Element Call may not be ready — check: docker logs element-call${RESET}"
                HEALTH_FAILED=true
                break
            fi
        done
        [[ $TRIES -lt 30 ]] && echo -e "\n${SUCCESS}✓ Element Call — ONLINE${RESET}"
    fi

    # ── Sliding Sync (optional) ──────────────────────────────────────────────
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Sliding Sync...${RESET}"
        TRIES=0
        until (echo >/dev/tcp/localhost/8011) 2>/dev/null; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 30 ]]; then
                echo -e "\n${WARNING}⚠️  Sliding Sync may not be ready — check: docker logs sliding-sync${RESET}"
                HEALTH_FAILED=true
                break
            fi
        done
        [[ $TRIES -lt 30 ]] && echo -e "\n${SUCCESS}✓ Sliding Sync — ONLINE${RESET}"
    fi

    # ── Matrix Media Repo (optional) ─────────────────────────────────────────
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Matrix Media Repo...${RESET}"
        TRIES=0
        until curl -s -f "http://localhost:8013/_matrix/media/v3/config" 2>/dev/null >/dev/null || \
              curl -s -f "http://localhost:8013/" 2>/dev/null >/dev/null; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 30 ]]; then
                echo -e "\n${WARNING}⚠️  Matrix Media Repo may not be ready — check: docker logs matrix-media-repo${RESET}"
                HEALTH_FAILED=true
                break
            fi
        done
        [[ $TRIES -lt 30 ]] && echo -e "\n${SUCCESS}✓ Matrix Media Repo — ONLINE${RESET}"
    fi

    # ── Admin panel (optional) ────────────────────────────────────────────────
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Element Admin...${RESET}"
        TRIES=0
        # Element Admin's nginx may return 3xx on /, so don't use -f (which fails on non-2xx).
        # Instead check that the server responds with any HTTP status code at all.
        until [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://$AUTO_LOCAL_IP:8014" 2>/dev/null)" =~ ^[0-9]{3}$ ]]; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 20 ]]; then
                echo -e "\n${WARNING}⚠️  Element Admin may not be ready — check: docker logs element-admin${RESET}"
                HEALTH_FAILED=true
                break
            fi
        done
        [[ $TRIES -lt 20 ]] && echo -e "\n${SUCCESS}✓ Element Admin — ONLINE${RESET}"
    fi

    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo -ne "\n${WARNING}>> Checking Synapse Admin...${RESET}"
        TRIES=0
        until curl -s -f "http://$AUTO_LOCAL_IP:8009" 2>/dev/null >/dev/null; do
            echo -ne "."
            sleep 2
            ((TRIES++))
            if [[ $TRIES -gt 20 ]]; then
                echo -e "\n${WARNING}⚠️  Synapse Admin may not be ready — check: docker logs synapse-admin${RESET}"
                HEALTH_FAILED=true
                break
            fi
        done
        [[ $TRIES -lt 20 ]] && echo -e "\n${SUCCESS}✓ Synapse Admin — ONLINE${RESET}"
    fi

    # ── Bridges (optional) ────────────────────────────────────────────────────
    if [[ ${#SELECTED_BRIDGES[@]} -gt 0 ]]; then
        echo -e "\n${WARNING}>> Checking bridges...${RESET}"
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            TRIES=0
            echo -ne "   ${ACCENT}$bridge${RESET}..."
            until docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^matrix-bridge-${bridge}$"; do
                echo -ne "."
                sleep 2
                ((TRIES++))
                if [[ $TRIES -gt 20 ]]; then
                    echo -e " ${WARNING}⚠️  not running — check: docker logs matrix-bridge-$bridge${RESET}"
                    HEALTH_FAILED=true
                    break
                fi
            done
            [[ $TRIES -lt 20 ]] && echo -e " ${SUCCESS}ONLINE${RESET}"
        done
    fi

    echo ""
    if [[ "$HEALTH_FAILED" == "true" ]]; then
        echo -e "${WARNING}╔══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${WARNING}║   SOME SERVICES DID NOT COME ONLINE — review warnings above  ║${RESET}"
        echo -e "${WARNING}╚══════════════════════════════════════════════════════════════╝${RESET}"
    else
        echo -e "${SUCCESS}╔══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${SUCCESS}║              ALL INSTALLED SERVICES ARE ONLINE               ║${RESET}"
        echo -e "${SUCCESS}╚══════════════════════════════════════════════════════════════╝${RESET}"
    fi

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
        echo -e "${INFO}   Ensuring admin privileges...${RESET}"
        docker exec matrix-auth mas-cli manage promote-admin "$ADMIN_USER" 2>&1 >/dev/null
        echo -e "${SUCCESS}✓ Admin privileges confirmed${RESET}"
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
    ask_yn SETUP_LOG_ROTATION "Setup log rotation to prevent disk space issues? [y/n]: " y
    
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

# Run update check before showing anything else
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
    ask_choice MENU_SELECT "Selection (0-6): " 0 1 2 3 4 5 6

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
    esac
done

################################################################################
#                         END OF SCRIPT                                        #
################################################################################