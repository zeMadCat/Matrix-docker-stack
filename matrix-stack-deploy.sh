#!/bin/bash

################################################################################
#                                                                              #
#                    MATRIX SYNAPSE FULL STACK DEPLOYER                        #
#                                by MadCat                                     #
#                                                                              #
#  A comprehensive deployment script for Matrix Synapse with working           #
#  multi-screenshare video calling capabilities.                               #
#                                                                              #
#  Core Components:                                                            #
#  • Synapse (Matrix Homeserver)                                               #
#  • MAS (Matrix Authentication Service)                                       #
#  • PostgreSQL (Database)                                                     #
#  • LiveKit SFU (unlimited multi-screenshare + built-in TURN/STUN)            #
#  • LiveKit JWT Service (token generation)                                    #
#                                                                              #
#  Optional Components:                                                        #
#  • Element Web (web client)                                                  #
#  • Element Call (standalone WebRTC UI)                                       #
#  • Element Admin or Synapse Admin (admin panel)                              #
#  • Sliding Sync (modern client support)                                      #
#  • Matrix Media Repo (advanced media handling)                               #
#                                                                              #
#  Bridges Available:                                                          #
#  • Discord • Telegram • WhatsApp • Signal • Slack • Instagram                #
#                                                                              #
#  Features:                                                                   #
#  • Reverse Proxy guides (NPM, Caddy, Traefik, Cloudflare, Pangolin)          #
#  • Pangolin VPS auto-configuration with SSH/SCP                              #
#  • Dynamic user input based setup with cancel options                        #
#  • Storage estimation and disk space checking                                #
#  • Unlimited multi-screenshare video calls                                   #
#  • GitHub version checking with update notifications                         #
#  • Complete uninstall with resource scanning (containers, volumes, networks) #
#  • Log rotation configuration for Docker containers                          #
#  • Health checks for all services post-deployment                            #
#  • Dockge stack integration support                                          #
#  • Bridge auto-configuration with database creation                          #
#                                                                              #
################################################################################

# Trap Ctrl-C to reset terminal colors
trap 'echo -e "\033[0m"; exit 130' INT

# Script version and repository info
SCRIPT_VERSION="1.8"
GITHUB_REPO="zeMadCat/Matrix-docker-stack"
GITHUB_BRANCH="main"

# Logging setup - will be fully configured once TARGET_DIR is set
LOG_FILE=""
ENABLE_LOGGING=true

# Function to setup logging once we know the target directory
setup_logging() {
    LOG_FILE="$TARGET_DIR/matrix-stack-deployment.log"
    # Start fresh log file with timestamp
    {
        echo "================================================================================"
        echo "Matrix Stack Deployment Log"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script Version: $SCRIPT_VERSION"
        echo "================================================================================"
        echo ""
        echo "Note: Sensitive data (passwords, secrets, tokens) are automatically blurred"
        echo "with [REDACTED_*] placeholders for security."
        echo ""
    } > "$LOG_FILE"
    chmod 640 "$LOG_FILE"
}

# Function to log section headers
log_section() {
    local section="$1"
    log_message "──────────────────────────────────────────────────────────────────"
    log_message ">> $section"
    log_message "──────────────────────────────────────────────────────────────────"
}

# Function to log messages to both console and file
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local script_name="matrix-deploy"
    
    # Log to file without ANSI codes and with sensitive data blurred
    # Only proceed if log file is configured
    if [ -z "$LOG_FILE" ] || [ ! -d "$(dirname "$LOG_FILE")" ]; then
        return  # Log file not ready yet, skip silently
    fi
    
    local sanitized="$message"
    # Blur sensitive patterns - only if variables are set and non-empty
    [ -n "$ADMIN_PASS" ] && sanitized=$(echo "$sanitized" | sed "s|${ADMIN_PASS}|[REDACTED_PASSWORD]|g")
    [ -n "$DB_PASS" ] && sanitized=$(echo "$sanitized" | sed "s|${DB_PASS}|[REDACTED_DB_PASSWORD]|g")
    [ -n "$REG_SECRET" ] && sanitized=$(echo "$sanitized" | sed "s|${REG_SECRET}|[REDACTED_REG_SECRET]|g")
    [ -n "$MAS_SECRET" ] && sanitized=$(echo "$sanitized" | sed "s|${MAS_SECRET}|[REDACTED_MAS_SECRET]|g")
    [ -n "$LK_API_SECRET" ] && sanitized=$(echo "$sanitized" | sed "s|${LK_API_SECRET}|[REDACTED_LK_SECRET]|g")
    [ -n "$NPM_ADMIN_PASS" ] && sanitized=$(echo "$sanitized" | sed "s|${NPM_ADMIN_PASS}|[REDACTED_NPM_PASSWORD]|g")
    [ -n "$PANGOLIN_NEWT_SECRET" ] && sanitized=$(echo "$sanitized" | sed "s|${PANGOLIN_NEWT_SECRET}|[REDACTED_PANGOLIN_SECRET]|g")
    # Remove ANSI color codes
    sanitized=$(echo "$sanitized" | sed 's/\x1b\[[0-9;]*m//g')
    
    # syslog-style format: TIMESTAMP HOSTNAME PROGRAM[PID]: MESSAGE
    printf "[%s] %s %s[%s]: %s\n" "$timestamp" "$hostname" "$script_name" "$$" "$sanitized" >> "$LOG_FILE" 2>/dev/null || true
}

################################################################################
# COLOR DEFINITIONS                                                            #
################################################################################

BANNER='\033[1;95m'                # Purple - Banner text
ACCENT='\033[1;96m'                # Cyan - Section headers
WARNING='\033[1;93m'               # Yellow - Warnings
SUCCESS='\033[1;92m'               # Green - Success messages
ERROR='\033[1;91m'                 # Red - Error messages
INFO='\033[1;97m'                  # White - Info text
GREY='\033[1;90m'                  # Grey - Default/neutral text
ORANGE='\033[38;5;208m'            # Orange - Special operations
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

# Global installation directory (set during installation, used by other functions)
TARGET_DIR=""

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
    echo -e "${BANNER}│                         by MadCat                            │${RESET}"
    echo -e "${BANNER}├──────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${BANNER}│  CORE                │  BRIDGES                              │${RESET}"
    echo -e "${BANNER}│  ───────────         │  ───────────                          │${RESET}"
    echo -e "${BANNER}│  • Synapse           │  - Discord     - Telegram             │${RESET}"
    echo -e "${BANNER}│  • MAS               │  - WhatsApp    - Signal               │${RESET}"
    echo -e "${BANNER}│  • LiveKit           │  - Slack       - Meta (FB/Instagram)  │${RESET}"
    echo -e "${BANNER}│  • LiveKit JWT       │                                       │${RESET}"
    echo -e "${BANNER}│  • PostgreSQL        │  FEATURES                             │${RESET}"
    echo -e "${BANNER}│  • Element Call *    │  ───────────                          │${RESET}"
    echo -e "${BANNER}│  • Admin Panel *     │  • Dynamic Config                     │${RESET}"
    echo -e "${BANNER}│  • Sliding Sync *    │  • User Input Based                   │${RESET}"
    echo -e "${BANNER}│  • Media Repo *      │  • Reverse Proxy Guides               │${RESET}"
    echo -e "${BANNER}│                      │  • Pangolin VPS Support               │${RESET}"
    echo -e "${BANNER}│  * = optional        │  • Easy Setup                         │${RESET}"
    echo -e "${BANNER}│                      │  • Multi-Screenshare                  │${RESET}"
    echo -e "${BANNER}│                      │  • Multi-Stack Support                │${RESET}"
    echo -e "${BANNER}├──────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${BANNER}│                    ${WARNING}Script Version:${SUCCESS} v${SCRIPT_VERSION}${RESET}${BANNER}                      │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
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
    # Redirect stdout to file for everything below until we restore it
    exec 3>&1
    exec > "$CREDS_PATH"
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        echo -e "${BANNER}════════════════════════════════════════════════════════════════════════════════════════${RESET}"
        echo -e "${BANNER}═════════════════════════════════════ BRIDGE SETUP ═════════════════════════════════════${RESET}"
        echo -e "${BANNER}════════════════════════════════════════════════════════════════════════════════════════${RESET}"
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
                meta)
                    echo -e "   ${SUCCESS}── Meta (Facebook Messenger / Instagram) ─────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @instagrambot:$DOMAIN (Instagram) or @facebookbot:$DOMAIN (Messenger)"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    Open instagram.com or facebook.com in a private browser window"
                    echo -e "   ${INFO}Step 3:${RESET}    Open DevTools → Network tab → filter XHR → search 'graphql'"
                    echo -e "   ${INFO}Step 4:${RESET}    Log in, right-click a request → Copy as cURL → paste to bot"
                    echo -e "   ${WARNING}Note:${RESET}      Meta actively restricts automation — use at own risk"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/meta/authentication.html"
                    echo -e ""
                    ;;
            esac
        done
    fi

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

    # User management section
    echo -e "\n${ACCENT}═══════════════════════ USER MANAGEMENT ════════════════════════${RESET}"
    echo -e "   ${WARNING}⚠️  Registration via Element Web is disabled — MAS handles all accounts.${RESET}"
    echo -e "   ${INFO}The 'Create account' button in Element will open the MAS registration page.${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Create a regular user:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Create an admin user: (lowercase only)${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --admin --yes${RESET}"
    echo -e "   ${INFO}(then promote with: docker exec matrix-auth mas-cli manage promote-admin USERNAME)${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Reset forgotten password:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage set-password USERNAME 'PASSWORD' --ignore-complexity${RESET}"
    echo -e "   ${INFO}(wrap password in single quotes to avoid shell interpretation errors)${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Remove / deactivate a user:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage lock-user USERNAME --deactivate${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Or register via the MAS web UI:${RESET}"
    echo -e "   ${SUCCESS}https://$SUB_MAS.$DOMAIN/account/${RESET}"
    echo -e ""
    echo -e "   ${INFO}ℹ  If registration is disabled, the MAS UI will reject new signups.${RESET}"
    echo -e "   ${INFO}   Use the CLI commands above regardless of registration setting.${RESET}"

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
    echo -e "   ┌─────────────────┬───────────┬─────────────────┬─────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ %-15s │ %-15s │\n" "HOSTNAME" "TYPE" "VALUE" "STATUS"
    echo -e "   ├─────────────────┼───────────┼─────────────────┼─────────────────┤"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "@" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_MAS" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ %-15s │\n" "turn" "A" "$AUTO_PUBLIC_IP" "DNS ONLY"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ %-15s │\n" "$SUB_LIVEKIT" "A" "$AUTO_PUBLIC_IP" "DNS ONLY"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_CALL" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_ELEMENT_ADMIN" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_SYNAPSE_ADMIN" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_ELEMENT" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_SLIDING_SYNC" "A" "$AUTO_PUBLIC_IP" "PROXIED"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${DNS_STATUS_PROXIED}%-15s${RESET} │\n" "$SUB_MEDIA_REPO" "A" "$AUTO_PUBLIC_IP" "PROXIED"
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
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Sliding Sync" "TCP" "8011" "$AUTO_LOCAL_IP:8011"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Web" "TCP" "8012" "$AUTO_LOCAL_IP:8012"
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Media Repo" "TCP" "8013" "$AUTO_LOCAL_IP:8013"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN (TCP/UDP)" "TCP/UDP" "3478" "$AUTO_LOCAL_IP:3478"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN TLS" "TCP" "5349" "$AUTO_LOCAL_IP:5349"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit HTTP" "TCP" "7880" "$AUTO_LOCAL_IP:7880"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit RTC" "UDP" "7882" "$AUTO_LOCAL_IP:7882"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit JWT" "TCP" "8089" "$AUTO_LOCAL_IP:8089"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit Range" "UDP" "50000-50500" "$AUTO_LOCAL_IP"
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
    if [[ "$MAS_REGISTRATION" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Registration: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} — users can sign up at https://$SUB_MAS.$DOMAIN/account/${RESET}"
    else
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Registration: ${ERROR}DISABLED${RESET}${NOTE_TEXT} — use CLI: ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes${RESET}"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Sliding Sync: ${SUCCESS}ENABLED${RESET}${NOTE_TEXT} (modern client support)${RESET}"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -e "   ${NOTE_ICON}${SUCCESS}✓${RESET}${NOTE_TEXT}  Matrix Media Repo: running at https://$SUB_MEDIA_REPO.$DOMAIN${RESET}"
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  Synapse delegates all media to it — files stored at ${TARGET_DIR}/media-repo/data${RESET}"
        echo -e "   ${NOTE_ICON}${INFO}ℹ${RESET}${NOTE_TEXT}  To use S3 storage: edit ${TARGET_DIR}/media-repo/config.yaml → datastores section${RESET}"
    fi

    # SCROLL MESSAGE - Centered
    echo "══════════════════════════════════════════════════════════════════"
    echo -e "${WARNING}        SCROLL UP FOR CREDENTIALS & DNS/PORT FORWARD TABLES${RESET}"
    echo "══════════════════════════════════════════════════════════════════"
    echo ""

    # BRIDGE SETUP NOTICE - Centered
    echo -e "${WARNING}   ═${RESET}${ACCENT}          BRIDGE SETUP PRINTED ABOVE CREDENTIALS${RESET}${WARNING}          ═${RESET}"
    echo ""

    # Log rotation and final warning
    echo "══════════════════════════════════════════════════════════════════"
    echo "   ✓  Log rotation: ENABLED (logs managed automatically)"
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "     !!! SAVE THIS DATA IMMEDIATELY! NOT STORED ELSEWHERE. !!!"
    echo "══════════════════════════════════════════════════════════════════"

    # Restore stdout
    exec >&3
    exec 3>&-

    # Strip ANSI color codes from saved file, then restrict permissions
    if [ -f "$CREDS_PATH" ]; then
        sed -i 's/\x1b\[[0-9;]*m//g' "$CREDS_PATH"
        chmod 600 "$CREDS_PATH"
    fi

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
        echo -e "   ${ACCESS_NAME}Element Admin:${RESET}       ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:$PORT_ELEMENT_ADMIN${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_ELEMENT_ADMIN.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo -e "   ${ACCESS_NAME}Synapse Admin:${RESET}       ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:$PORT_SYNAPSE_ADMIN${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_SYNAPSE_ADMIN.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    fi
    echo -e "   ${ACCESS_NAME}Matrix API:${RESET}          ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:$PORT_SYNAPSE${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_MATRIX.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Auth Service (MAS):${RESET}  ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:$PORT_MAS${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_MAS.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    echo -e "   ${ACCESS_NAME}Element Web:${RESET}         ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:$PORT_ELEMENT_WEB${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_ELEMENT.$DOMAIN${ACCESS_VALUE}${RESET} (WAN)"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -e "   ${ACCESS_NAME}Element Call:${RESET}        ${ACCESS_VALUE}http://${LOCAL_IP_COLOR}$AUTO_LOCAL_IP${ACCESS_VALUE}:$PORT_ELEMENT_CALL${RESET} (LAN) / ${ACCESS_VALUE}https://${USER_ID_VALUE}$SUB_CALL.$DOMAIN${ACCESS_VALUE}${RESET} (WAN via Element Web)"
    fi

    # User management section — always visible, clearly copy-pasteable
    echo -e "\n${ACCENT}═══════════════════════ USER MANAGEMENT ════════════════════════${RESET}"
    echo -e "   ${WARNING}⚠️  Registration via Element Web is disabled — MAS handles all accounts.${RESET}"
    echo -e "   ${INFO}The 'Create account' button in Element will open the MAS registration page.${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Create a regular user:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --yes${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Create an admin user: (lowercase only)${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage register-user USERNAME --password PASSWORD --admin --yes${RESET}"
    echo -e "   ${INFO}(then promote with: docker exec matrix-auth mas-cli manage promote-admin USERNAME)${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Reset forgotten password:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage set-password USERNAME 'PASSWORD' --ignore-complexity${RESET}"
    echo -e "   ${INFO}(wrap password in single quotes to avoid shell interpretation errors)${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Remove / deactivate a user:${RESET}"
    echo -e "   ${WARNING}docker exec matrix-auth mas-cli manage lock-user USERNAME --deactivate${RESET}"
    echo -e ""
    echo -e "   ${ACCENT}Or register via the MAS web UI:${RESET}"
    echo -e "   ${SUCCESS}https://$SUB_MAS.$DOMAIN/account/${RESET}"
    echo -e ""
    echo -e "   ${INFO}ℹ  If registration is disabled, the MAS UI will reject new signups.${RESET}"
    echo -e "   ${INFO}   Use the CLI commands above regardless of registration setting.${RESET}"
    if [[ "$PROXY_ALREADY_RUNNING" == "false" ]]; then
        case "$PROXY_TYPE" in
            pangolin)
                echo -e "\n${ACCENT}═══════════════════════ PANGOLIN TUNNEL ════════════════════════${RESET}"
                echo -e "   ${ACCESS_NAME}Pangolin URL:${RESET}        ${ACCESS_VALUE}${PANGOLIN_URL}${RESET}"
                echo -e "   ${ACCESS_NAME}Newt ID:${RESET}             ${ACCESS_VALUE}${PANGOLIN_NEWT_ID}${RESET}"
                echo -e "   ${ACCESS_NAME}VPS IP (TURN):${RESET}       ${ACCESS_VALUE}${PANGOLIN_VPS_IP}${RESET}"
                echo -e "   ${INFO}ℹ  Newt container is running in your stack — no open ports required${RESET}"
                ;;
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
    if [[ "$PROXY_TYPE" == "pangolin" ]]; then
        MATRIX_STATUS="PANGOLIN"
        MAS_STATUS="PANGOLIN"
        LIVEKIT_STATUS="PANGOLIN"
        TURN_STATUS="VPS IP"
        ELEMENT_CALL_STATUS="PANGOLIN"
        ELEMENT_ADMIN_STATUS="PANGOLIN"
    elif [[ "$PROXY_TYPE" == "cloudflare" ]]; then
        MATRIX_STATUS="DNS ONLY"
        MAS_STATUS="DNS ONLY"
        LIVEKIT_STATUS="DNS ONLY"
        TURN_STATUS="DNS ONLY"
        ELEMENT_CALL_STATUS="DNS ONLY"
        ELEMENT_ADMIN_STATUS="DNS ONLY"
    elif [[ "$PROXY_TYPE" == "npm" ]] || [[ "$PROXY_TYPE" == "caddy" ]] || [[ "$PROXY_TYPE" == "traefik" ]]; then
        MATRIX_STATUS="PROXIED"
        MAS_STATUS="PROXIED"
        LIVEKIT_STATUS="DNS ONLY"
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
    if [[ "$PROXY_TYPE" == "pangolin" ]]; then
        echo -e "   ${SUCCESS}✓ No port forwarding required — Newt tunnel handles all inbound traffic${RESET}"
        echo -e "   ${INFO}ℹ  Only the VPS needs ports open: UDP/TCP 3478 and TCP 5349 for TURN (coturn)${RESET}"
    else
    echo -e "   ┌─────────────────┬───────────┬─────────────────┬───────────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ %-15s │ %-21s │\n" "SERVICE" "PROTOCOL" "PORT" "FORWARD TO"
    echo -e "   ├─────────────────┼───────────┼─────────────────┼───────────────────────┤"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Matrix Synapse" "TCP" "$PORT_SYNAPSE" "$AUTO_LOCAL_IP:$PORT_SYNAPSE"
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Admin" "TCP" "$PORT_ELEMENT_ADMIN" "$AUTO_LOCAL_IP:$PORT_ELEMENT_ADMIN"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Synapse Admin" "TCP" "$PORT_SYNAPSE_ADMIN" "$AUTO_LOCAL_IP:$PORT_SYNAPSE_ADMIN"
    fi
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "MAS Auth" "TCP" "$PORT_MAS" "$AUTO_LOCAL_IP:$PORT_MAS"

    # Add Sliding Sync if enabled
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Sliding Sync" "TCP" "$PORT_SLIDING_SYNC" "$AUTO_LOCAL_IP:$PORT_SLIDING_SYNC"
    fi

    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Web" "TCP" "$PORT_ELEMENT_WEB" "$AUTO_LOCAL_IP:$PORT_ELEMENT_WEB"

    # Add Media Repo if enabled
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Media Repo" "TCP" "$PORT_MEDIA_REPO" "$AUTO_LOCAL_IP:$PORT_MEDIA_REPO"
    fi
    
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN (TCP/UDP)" "TCP/UDP" "3478" "$AUTO_LOCAL_IP:3478"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "TURN TLS" "TCP" "5349" "$AUTO_LOCAL_IP:5349"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit HTTP" "TCP" "7880" "$AUTO_LOCAL_IP:7880"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit RTC" "UDP" "7882" "$AUTO_LOCAL_IP:7882"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit JWT" "TCP" "8089" "$AUTO_LOCAL_IP:8089"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "LiveKit Range" "UDP" "50000-50500" "$AUTO_LOCAL_IP"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ ${LOCAL_IP_COLOR}%-21s${RESET} │\n" "Element Call" "TCP" "8007" "$AUTO_LOCAL_IP:8007"
    fi
    echo -e "   └─────────────────┴───────────┴─────────────────┴───────────────────────┘"
    fi # end pangolin else block

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
        echo -e "\n${ACCENT}════════════════════════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${ACCENT}══════════════════════════════ BRIDGE SETUP ════════════════════════════════════════════${RESET}"
echo -e "${ACCENT}════════════════════════════════════════════════════════════════════════════════════════${RESET}"
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
                meta)
                    echo -e "   ${SUCCESS}── Meta (Facebook Messenger / Instagram) ─────────────${RESET}"
                    echo -e "   ${INFO}Bot user:${RESET}  @instagrambot:$DOMAIN (Instagram) or @facebookbot:$DOMAIN (Messenger)"
                    echo -e "   ${INFO}Step 1:${RESET}    Send: ${WARNING}login${RESET}"
                    echo -e "   ${INFO}Step 2:${RESET}    Open instagram.com or facebook.com in a private browser window"
                    echo -e "   ${INFO}Step 3:${RESET}    Open DevTools → Network tab → filter XHR → search 'graphql'"
                    echo -e "   ${INFO}Step 4:${RESET}    Log in, right-click a request → Copy as cURL → paste to bot"
                    echo -e "   ${WARNING}Note:${RESET}      Meta actively restricts automation — use at own risk"
                    echo -e "   ${INFO}Docs:${RESET}      https://docs.mau.fi/bridges/go/meta/authentication.html"
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
    local ver1=${1#[Vv]}
    local ver2=${2#[Vv]}
    
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
    
    # Try GitHub API first (primary source)
    echo -e "   ${INFO}Checking GitHub API for latest release...${RESET}"
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^" ]+)".*/\1/' | sed 's/^[Vv]//')
    
    # Validate API result
    if [ -n "$LATEST_VERSION" ] && [[ "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+ ]]; then
        echo -e "   ${SUCCESS}✓ Found release v${LATEST_VERSION} on GitHub${RESET}"
    else
        echo -e "   ${WARNING}⚠️  GitHub API failed, trying version.txt...${RESET}"
        
        # Robust fallback: extract ALL version numbers from version.txt and find the highest
        LATEST_VERSION=$(curl -sL "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/version.txt" 2>/dev/null | \
            grep -oE 'v[0-9]+\.[0-9]+' | \
            sed 's/^[Vv]//' | \
            sort -V | \
            tail -1)
        
        if [ -n "$LATEST_VERSION" ]; then
            echo -e "   ${SUCCESS}✓ Found highest version v${LATEST_VERSION} in version.txt${RESET}"
        else
            echo -e "   ${WARNING}⚠️  Could not determine latest version from GitHub${RESET}"
            echo -e "   ${INFO}   Continuing with local version v${SCRIPT_VERSION}${RESET}"
            return 0
        fi
    fi
    
    # Validate version format (should be numbers and dots only)
    if [ -z "$LATEST_VERSION" ] || ! [[ "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+ ]]; then
        echo -e "   ${WARNING}⚠️  Invalid version format received${RESET}"
        echo -e "   ${INFO}   Continuing with local version v${SCRIPT_VERSION}${RESET}"
        return 1
    fi
    
    echo -e "   ${INFO}Local: v${SCRIPT_VERSION} | Remote: v${LATEST_VERSION}${RESET}"
    
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
        echo -e "${ERROR}║          ⚠️⚠️⚠️   UNVERIFIED SCRIPT VERSION   ⚠️⚠️⚠️               ║${RESET}"
        echo -e "${ERROR}╚══════════════════════════════════════════════════════════════╝${RESET}"
        echo -e ""
        
        # Center the warning messages with colored version numbers
        local line1_prefix="!!! This script is version "
        local line1_version="v${SCRIPT_VERSION}"
        local line1_suffix=" !!!"
        local line1="${line1_prefix}${line1_version}${line1_suffix}"
        
        local line2_prefix="But the latest official release on GitHub is "
        local line2_version="v${LATEST_VERSION}"
        local line2_suffix="."
        local line2="${line2_prefix}${line2_version}${line2_suffix}"
        
        # Calculate padding for line1 based on total text length without colors
        local line1_length=${#line1}
        local line1_padding=$(( (60 - line1_length) / 2 ))
        printf "%*s${WARNING}%s${ERROR}%s${WARNING}%s${RESET}\n" \
            $line1_padding "" \
            "${line1_prefix}" \
            "${line1_version}" \
            "${line1_suffix}"
        
        # Calculate padding for line2 based on total text length without colors
        local line2_length=${#line2}
        local line2_padding=$(( (60 - line2_length) / 2 ))
        printf "%*s${WARNING}%s${SUCCESS}%s${WARNING}%s${RESET}\n" \
            $line2_padding "" \
            "${line2_prefix}" \
            "${line2_version}" \
            "${line2_suffix}"
        
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
    cat > /etc/logrotate.d/matrix-stack << EOF
${TARGET_DIR:-/opt/stacks/matrix-stack}/**/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
    maxsize 100M
    create 0644 root root
}
EOF

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
        mkdir -p /etc/docker
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
        
        # Restart Docker only if systemd is present and Docker is running
        if command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet docker; then
                systemctl restart docker 2>/dev/null
                echo -e "   ${INFO}ℹ  Docker configured with log rotation (max-size 100m, max-file 3) — restarted${RESET}"
            else
                echo -e "   ${INFO}ℹ  Docker log rotation config written. Docker service not running — will apply on next start.${RESET}"
            fi
        else
            echo -e "   ${INFO}ℹ  Docker log rotation config written. systemd not found — please restart Docker manually.${RESET}"
        fi
        
        return 0
    else
        echo -e "   ${ERROR}✗ Failed to configure log rotation${RESET}"
        return 1
    fi
}

# Validate config file syntax (YAML or JSON)
validate_config() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "   ${WARNING}⚠️  Config file not found: $file${RESET}"
        return 1
    fi
    
    if command -v python3 &>/dev/null; then
        if [[ "$file" =~ \.(yaml|yml)$ ]]; then
            # YAML validation
            if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
                echo -e "   ${WARNING}⚠️  YAML validation failed for $file${RESET}"
                echo -e "   ${INFO}Continuing anyway - check the file manually if needed${RESET}"
                return 1
            fi
        elif [[ "$file" =~ \.json$ ]]; then
            # JSON validation
            if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
                echo -e "   ${WARNING}⚠️  JSON validation failed for $file${RESET}"
                echo -e "   ${INFO}Continuing anyway - check the file manually if needed${RESET}"
                return 1
            fi
        fi
    else
        echo -e "   ${WARNING}⚠️  python3 not found, skipping config validation for $file${RESET}"
    fi
}

# Check if a port is in use and find the next available port in a range
find_available_port() {
    local start_port="$1"
    local max_attempts="${2:-100}"
    local port="$start_port"
    local attempts=0
    
    while (( attempts < max_attempts )); do
        if ! ss -lpn 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
        ((port++))
        ((attempts++))
    done
    
    echo ""
    return 1
}

# Check which ports are in use and determine fallback ports for NPM
check_port_conflicts() {
    local http_port=80
    local https_port=443
    local http_available=true
    local https_available=true
    
    if ss -lpn 2>/dev/null | grep -q ":80 "; then
        http_available=false
    fi
    
    if ss -lpn 2>/dev/null | grep -q ":443 "; then
        https_available=false
    fi
    
    # Return status: 0 = both free, 1 = conflicts exist
    if [ "$http_available" = true ] && [ "$https_available" = true ]; then
        return 0
    else
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
  port_range_end: 50500
  use_external_ip: false
  udp_port: 7882
  tcp_port: 7881

keys:
  "REPLACE_LK_API_KEY": "REPLACE_LK_API_SECRET"

logging:
  level: info

room:
  auto_create: true
  empty_timeout: 300

turn:
  enabled: true
  domain: REPLACE_TURN_DOMAIN
  cert_file: ""
  key_file: ""
  tls_port: 5349
  udp_port: 3478
  external_tls: true
  relay_range_start: 50000
  relay_range_end: 50500
LIVEKITEOF

    # Replace placeholders with proper escaping for sed special characters
    LK_API_KEY_ESCAPED=$(printf '%s\n' "$LK_API_KEY" | sed -e 's/[\/&]/\\&/g')
    LK_API_SECRET_ESCAPED=$(printf '%s\n' "$LK_API_SECRET" | sed -e 's/[\/&]/\\&/g')
    sed -i "s|REPLACE_LK_API_KEY|$LK_API_KEY_ESCAPED|g" "$TARGET_DIR/livekit/livekit.yaml"
    sed -i "s|REPLACE_LK_API_SECRET|$LK_API_SECRET_ESCAPED|g" "$TARGET_DIR/livekit/livekit.yaml"
    
    # Configure node_ip as CLI flag in compose for dual-stack (config-file node_ip is ignored by livekit-server)
    if [[ "$LIVEKIT_DUAL_STACK" == "true" ]]; then
        sed -i "s|command: --config /etc/livekit.yaml|command: --config /etc/livekit.yaml --node-ip $AUTO_LOCAL_IP|g" "$TARGET_DIR/compose.yaml"
    fi
    
    if [[ "$PROXY_TYPE" == "pangolin" ]]; then
        # Pangolin: TURN runs on the VPS, use its IP directly
        sed -i "s/REPLACE_TURN_DOMAIN/$PANGOLIN_VPS_IP/g" "$TARGET_DIR/livekit/livekit.yaml"
        echo -e "   ${SUCCESS}✓ LiveKit config created — TURN pointed to VPS at $PANGOLIN_VPS_IP${RESET}"
    else
        sed -i "s/REPLACE_TURN_DOMAIN/turn.$DOMAIN/g" "$TARGET_DIR/livekit/livekit.yaml"
        echo -e "   ${SUCCESS}✓ LiveKit config created - unlimited screenshares + built-in TURN/STUN enabled${RESET}"
    fi
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
    "sfu": "livekit",
    "livekit_service_url": "https://$SUB_CALL.$DOMAIN",
    "livekit_jwt_service_url": "https://$SUB_CALL.$DOMAIN"
}
EOF
    
    echo -e "   ${SUCCESS}✓ Element Call config created${RESET}"
    validate_config "$TARGET_DIR/element-call/config.json"
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
    forKinds: [ "all" ]
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
    validate_config "$TARGET_DIR/element-web/config.json"
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
            discord|telegram|whatsapp|signal|slack|meta)
                mkdir -p "$TARGET_DIR/bridges/$bridge"
                rm -f "$TARGET_DIR/bridges/$bridge/registration.yaml"

                local GEN_LOG="$TARGET_DIR/bridges/$bridge/generate.log"
                local BINARY_NAME="mautrix-$bridge"
                local IMAGE=""

                # --- Step 0: Identify Image ---
                if [ "$bridge" = "telegram" ]; then
                    # Use Python version of telegram bridge (more stable than telegramgo)
                    IMAGE="dock.mau.dev/mautrix/telegram:latest"
                    BINARY_NAME="mautrix-telegram"
                else
                    IMAGE="dock.mau.dev/mautrix/$bridge:latest"
                fi

                echo -e "\n   ${ACCENT}Configuring $bridge bridge...${RESET}"

                # --- Step 1: Find the binary inside the image ---
                local ENTRYPOINT=""
                
                # Special handling for meta bridge (different binary names)
                if [ "$bridge" = "meta" ]; then
                    # Meta bridge binary can be mautrix-meta-messenger or mautrix-meta-instagram
                    ENTRYPOINT=$(docker run --rm --entrypoint sh "$IMAGE" -c "command -v mautrix-meta-messenger 2>/dev/null || command -v mautrix-meta-instagram 2>/dev/null || command -v mautrix-meta 2>/dev/null")
                elif [ "$bridge" = "telegram" ]; then
                    # Python telegram has multiple possible binary names
                    ENTRYPOINT=$(docker run --rm --entrypoint sh "$IMAGE" -c "command -v mautrix-telegram 2>/dev/null || command -v python3 2>/dev/null || command -v python 2>/dev/null")
                else
                    ENTRYPOINT=$(docker run --rm --entrypoint sh "$IMAGE" -c "command -v $BINARY_NAME 2>/dev/null")
                fi
                
                if [ -z "$ENTRYPOINT" ]; then
                    # For Python telegram, try to find the entry script
                    if [ "$bridge" = "telegram" ]; then
                        for loc in "/usr/local/bin/mautrix-telegram" "/usr/bin/mautrix-telegram" "/app/mautrix_telegram/__main__.py" "/app/mautrix_telegram/main.py"; do
                            if docker run --rm --entrypoint sh "$IMAGE" -c "test -f $loc" 2>/dev/null; then
                                ENTRYPOINT="$loc"
                                break
                            fi
                        done
                    else
                        # Common paths for Go-based bridges
                        for loc in "/usr/bin/$BINARY_NAME" "/usr/local/bin/$BINARY_NAME" "/app/$BINARY_NAME" "/opt/mautrix-$bridge/$BINARY_NAME"; do
                            if docker run --rm --entrypoint sh "$IMAGE" -c "test -f $loc" 2>/dev/null; then
                                ENTRYPOINT="$loc"
                                break
                            fi
                        done
                    fi
                fi

                if [ -z "$ENTRYPOINT" ]; then
                    # Last resort full search
                    ENTRYPOINT=$(docker run --rm --entrypoint sh "$IMAGE" -c "find / -type f -name '$BINARY_NAME' 2>/dev/null | head -1")
                fi

                if [ -z "$ENTRYPOINT" ]; then
                    echo -e "   ${WARNING}⚠️ Could not find $BINARY_NAME in image – skipping $bridge${RESET}"
                    continue
                fi

                # --- Step 2: Obtain example-config.yaml ---
                local CONFIG_FILE="$TARGET_DIR/bridges/$bridge/config.yaml"
                local GOT_CONFIG=false
                
                # Check standard paths (Go bridges often use /pkg/connector)
                local EXAMPLE_PATHS=("/pkg/connector/example-config.yaml" "/opt/mautrix-$bridge/example-config.yaml" "/app/example-config.yaml")

                for ex_path in "${EXAMPLE_PATHS[@]}"; do
                    if docker run --rm --entrypoint sh "$IMAGE" -c "test -f $ex_path" 2>/dev/null; then
                        if docker run --rm \
                            --entrypoint /bin/sh \
                            -v "$TARGET_DIR/bridges/$bridge:/data" \
                            "$IMAGE" \
                            -c "cp $ex_path /data/config.yaml" > "$GEN_LOG" 2>&1; then
                            GOT_CONFIG=true
                            break
                        fi
                    fi
                done

                # Fallback: Download from GitHub if extraction fails
                if [ ! -f "$CONFIG_FILE" ] && [ "$GOT_CONFIG" = false ]; then
                    #echo -e "   ${INFO}Downloading example config from GitHub...${RESET}"
                    local GITHUB_URL=""
                    case $bridge in
                        discord)   GITHUB_URL="https://raw.githubusercontent.com/mautrix/discord/main/example-config.yaml" ;;
                        telegram)  GITHUB_URL="https://raw.githubusercontent.com/mautrix/telegram/master/mautrix_telegram/example-config.yaml" ;;
                        whatsapp)  GITHUB_URL="https://raw.githubusercontent.com/mautrix/whatsapp/master/pkg/connector/example-config.yaml" ;;
                        signal)    GITHUB_URL="https://raw.githubusercontent.com/mautrix/signal/master/pkg/connector/example-config.yaml" ;;
                        slack)     GITHUB_URL="https://raw.githubusercontent.com/mautrix/slack/master/pkg/connector/example-config.yaml" ;;
                        meta)      GITHUB_URL="https://raw.githubusercontent.com/mautrix/meta/master/pkg/connector/example-config.yaml" ;;
                    esac
                    curl -fsSL -o "$CONFIG_FILE" "$GITHUB_URL" 2>/dev/null && GOT_CONFIG=true
                fi

                if [ ! -f "$CONFIG_FILE" ]; then
                    echo -e "   ${WARNING}⚠️ Config file missing for $bridge – skipping${RESET}"
                    continue
                fi

                # ===== TELEGRAM-SPECIFIC CONFIGURATION =====
                if [ "$bridge" = "telegram" ]; then
                    echo -e "\n   ${ACCENT}╔══════════════════════════════════════════════════════════════╗${RESET}"
                    echo -e "   ${ACCENT}║                  TELEGRAM BRIDGE SETUP                        ║${RESET}"
                    echo -e "   ${ACCENT}╚══════════════════════════════════════════════════════════════╝${RESET}"
                    echo -e "   ${INFO}The Telegram bridge requires API credentials from Telegram.${RESET}"
                    echo -e "   ${WARNING}📱 Get your API ID and Hash at:${RESET}"
                    echo -e "   ${SUCCESS}   https://my.telegram.org/apps${RESET}"
                    echo -e "   ${INFO}   (${WARNING}Ctrl+Click${INFO} to open in your browser)${RESET}"
                    echo -e ""
                    
                    # Prompt for API credentials if not already set
                    if [ -z "$TG_API_ID" ] || [ -z "$TG_API_HASH" ]; then
                        while true; do
                            echo -ne "   ${ACCENT}Telegram API ID${RESET} (numeric): ${WARNING}"
                            read -r TG_API_ID
                            echo -e "${RESET}"
                            [[ "$TG_API_ID" =~ ^[0-9]+$ ]] && break
                            echo -e "   ${ERROR}⚠️  API ID must be a number${RESET}"
                        done
                        
                        echo -ne "   ${ACCENT}Telegram API Hash${RESET}: ${WARNING}"
                        read -r TG_API_HASH
                        echo -e "${RESET}"
                        
                        if [ ${#TG_API_HASH} -ne 32 ]; then
                            echo -e "   ${WARNING}⚠️  Warning: API Hash is usually 32 characters${RESET}"
                        fi
                    fi
                    
                    # Replace the placeholder API credentials in the config for Python version
                    # The telegram section should have api_id and api_hash
                    sed -i "/^telegram:/,/^[a-z]/s/^\(    \)api_id:.*/\1api_id: $TG_API_ID/" "$CONFIG_FILE"
                    sed -i "/^telegram:/,/^[a-z]/s/^\(    \)api_hash:.*/\1api_hash: $TG_API_HASH/" "$CONFIG_FILE"
                fi
                # ===== END TELEGRAM CONFIG =====

                # --- Step 3: Patch initial connectivity ---
                sed -i "s|domain: example.com|domain: $DOMAIN|g" "$CONFIG_FILE" 2>/dev/null
                sed -i "s|address: https://matrix.example.com|address: http://synapse:8008|g" "$CONFIG_FILE" 2>/dev/null
                sed -i "s|address: https://example.com|address: http://synapse:8008|g" "$CONFIG_FILE" 2>/dev/null

                # Ensure homeserver section is clean and correct
                sed -i '/^homeserver:/,/^[^[:space:]]/d' "$CONFIG_FILE"
                echo -e "\nhomeserver:\n    address: http://synapse:8008\n    domain: $DOMAIN" >> "$CONFIG_FILE"
                
                # Special database patching for telegram bridge
                if [ "$bridge" = "telegram" ]; then
                    local BRIDGE_DB="mautrix_${bridge}"
                    # Use PostgreSQL URI for better compatibility
                    local DB_URI="postgresql://$DB_USER:$DB_PASS@synapse-db/$BRIDGE_DB?sslmode=disable"
                    sed -i "s|database: postgres://username:password@hostname/dbname|database: $DB_URI|g" "$CONFIG_FILE"
                    sed -i "s|database: sqlite:/data.*|database: $DB_URI|g" "$CONFIG_FILE"
                    
                    # Enable MSC4190 for proper MAS compatibility with encrypted bridges
                    # This allows device management without using /login API
                    sed -i "/encryption:/,/^[a-z]/{
                        /msc4190:/d
                        /allow:/a\\        msc4190: true
                    }" "$CONFIG_FILE"
                    
                    # If encryption section doesn't exist, add it
                    if ! grep -q "^    encryption:" "$CONFIG_FILE"; then
                        cat >> "$CONFIG_FILE" << 'ENCEOF'

    encryption:
        allow: false
        default: false
        msc4190: true
        require: false
        allow_key_sharing: false
ENCEOF
                    fi
                    
                    # Ensure bridge.permissions is configured
                    if ! grep -q "^bridge:" "$CONFIG_FILE" || ! sed -n '/^bridge:/,/^[a-z]/p' "$CONFIG_FILE" | grep -q "permissions:"; then
                        # Add permissions section if missing
                        cat >> "$CONFIG_FILE" << 'PERMEOF'

bridge:
    permissions:
        "*": "relaybot"
PERMEOF
                    fi
                    
                    # Create database BEFORE registration generation (telegram needs it)
                    docker exec synapse-db psql -U "$DB_USER" -tc "SELECT 1 FROM pg_database WHERE datname='$BRIDGE_DB'" 2>/dev/null | grep -q 1 || \
                    docker exec synapse-db psql -U "$DB_USER" -c "CREATE DATABASE $BRIDGE_DB OWNER $DB_USER;" >/dev/null 2>&1
                fi

                # --- Step 4: Generate registration.yaml ---
                if [ "$bridge" = "telegram" ]; then
                    # Python telegram - invoke via sh to use python -m module syntax
                    if ! docker run --rm \
                        -v "$TARGET_DIR/bridges/$bridge:/data" \
                        "$IMAGE" \
                        sh -c "python -m mautrix_telegram -g -c /data/config.yaml -r /data/registration.yaml" >> "$GEN_LOG" 2>&1; then
                        echo -e "   ${WARNING}⚠️  Registration generation failed for $bridge${RESET}"
                        tail -5 "$GEN_LOG" | sed 's/^/      /'
                        continue
                    fi
                else
                    # Other bridges use entrypoint with -g flag
                    if ! docker run --rm \
                        --entrypoint "$ENTRYPOINT" \
                        -v "$TARGET_DIR/bridges/$bridge:/data" \
                        "$IMAGE" \
                        -g -c /data/config.yaml -r /data/registration.yaml >> "$GEN_LOG" 2>&1; then
                        echo -e "   ${WARNING}⚠️  Registration generation failed for $bridge${RESET}"
                        tail -5 "$GEN_LOG" | sed 's/^/      /'
                        continue
                    fi
                fi

                if [ ! -f "$TARGET_DIR/bridges/$bridge/registration.yaml" ]; then
                    echo -e "   ${WARNING}⚠️ Registration file not created for $bridge${RESET}"
                    continue
                fi

                # --- Step 5: Patch generated config (Database & Identity) ---
                local CFG="$TARGET_DIR/bridges/$bridge/config.yaml"
                local BRIDGE_DB="mautrix_${bridge}"

                # Setup Postgres Database
                docker exec synapse-db psql -U "$DB_USER" -tc "SELECT 1 FROM pg_database WHERE datname='$BRIDGE_DB'" 2>/dev/null | grep -q 1 || \
                docker exec synapse-db psql -U "$DB_USER" -c "CREATE DATABASE $BRIDGE_DB OWNER $DB_USER;" >/dev/null 2>&1

                # URI Patching
                sed -i -e "s|uri: postgres://.*|uri: postgresql://$DB_USER:$DB_PASS@postgres/$BRIDGE_DB?sslmode=disable|g" \
                       -e "s|uri: postgresql://.*|uri: postgresql://$DB_USER:$DB_PASS@postgres/$BRIDGE_DB?sslmode=disable|g" "$CFG" 2>/dev/null

                # Network Patching (Container to Container)
                sed -i "s|address: http://localhost:|address: http://mautrix-$bridge:|g" "$CFG" 2>/dev/null
                local REG_URL="$TARGET_DIR/bridges/$bridge/registration.yaml"
                [ -f "$REG_URL" ] && sed -i "s|url: http://localhost:|url: http://mautrix-$bridge:|g" "$REG_URL" 2>/dev/null

                # Permissions & Admin
                sed -i -e "s|\"example.com\": user|\"$DOMAIN\": user|g" \
                       -e "s|\"@admin:example.com\": admin|\"@$ADMIN_USER:$DOMAIN\": admin|g" "$CFG" 2>/dev/null

                # Bot User
                local BOT_USER="${bridge}bot"
                local DEFAULT_BOT="mautrix${bridge}bot"
                sed -i -e "s|bot_username: $DEFAULT_BOT|bot_username: $BOT_USER|g" \
                       -e "s|username: $DEFAULT_BOT|username: $BOT_USER|g" "$CFG" 2>/dev/null
                
                [ -f "$REG_URL" ] && sed -i "s|sender_localpart: $DEFAULT_BOT|sender_localpart: $BOT_USER|g" "$REG_URL" 2>/dev/null

                echo -e "   ${SUCCESS}✓ $bridge bridge configured and registered${RESET}"
                rm -f "$GEN_LOG"
                ;;
        esac
    done

    # --- Step 6: File Permissions for Synapse ---
    if [ -d "$TARGET_DIR/bridges" ]; then
        find "$TARGET_DIR/bridges" -type f -exec chmod 644 {} \;
        find "$TARGET_DIR/bridges" -type d -exec chmod 755 {} \;
        echo -e "   ${SUCCESS}✓ Bridge file permissions set${RESET}"
    fi

    # --- Step 7: Final Synapse Registration ---
    echo -e "\n${ACCENT}   >> Updating Synapse appservice list...${RESET}"
    local AS_BLOCK="app_service_config_files:"
    local AS_COUNT=0
    for bridge in "${SELECTED_BRIDGES[@]}"; do
        if [ -f "$TARGET_DIR/bridges/${bridge}/registration.yaml" ]; then
            AS_BLOCK="${AS_BLOCK}\n  - /data/bridges/${bridge}/registration.yaml"
            ((AS_COUNT++))
        fi
    done

    if [[ $AS_COUNT -gt 0 ]]; then
        if ! grep -q "app_service_config_files:" "$TARGET_DIR/synapse/homeserver.yaml" 2>/dev/null; then
            printf "\n%b\n" "$AS_BLOCK" >> "$TARGET_DIR/synapse/homeserver.yaml"
            echo -e "${SUCCESS}   ✓ $AS_COUNT bridges added to homeserver.yaml${RESET}"
        else
            echo -e "${INFO}   ℹ app_service_config_files already defined in homeserver.yaml${RESET}"
        fi
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
            npm)      
                echo -e "   ${INFO}ℹ  NPM will handle the well-known endpoint.${RESET}"
                echo -e "   ${INFO}   After deployment, configure in NPM Advanced Tab (see guide below).${RESET}"
                ;;
            caddy)    echo -e "   ${INFO}ℹ  Serve well-known via the Caddyfile config in the setup guide below.${RESET}" ;;
            traefik)  echo -e "   ${INFO}ℹ  Serve well-known via the Traefik config in the setup guide below.${RESET}" ;;
            pangolin) echo -e "   ${INFO}ℹ  Configure the base domain tunnel in Pangolin to serve well-known via the guide below.${RESET}" ;;
            *)        echo -e "   ${INFO}ℹ  Ensure your reverse proxy serves $TARGET_DIR/well-known/ at https://$DOMAIN/.well-known/matrix/${RESET}" ;;
        esac
        return
    fi

    # Check if port 80 is already in use
    if ss -lpn 2>/dev/null | grep -q ":80 "; then
        echo -e "   ${WARNING}⚠️  Port 80 is already in use. Skipping automatic nginx well-known setup.${RESET}"
        echo -e "   ${INFO}Please serve the well-known files manually.${RESET}"
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
    "org.matrix.msc4143.rtc_foci": [
        {
            "type": "livekit",
            "livekit_service_url": "https://$SUB_CALL.$DOMAIN"
        }
   ]
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
        pangolin)
            echo -e "   ${INFO}   Configure Pangolin to route $DOMAIN/.well-known/matrix/ to http://$AUTO_LOCAL_IP:80${RESET}"
            echo -e "   ${INFO}   or use the base domain tunnel with a static JSON response — see the Pangolin guide below.${RESET}"
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
  homeserver: "$DOMAIN"
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
  password_registration_email_required: $(if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then echo "true"; else echo "false"; fi)

policy:
  data:
    admin_clients:
$(if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then echo "      - \"$ELEMENT_ADMIN_CLIENT_ID\""; fi)
  registration:
    enabled: $MAS_REGISTRATION
    require_email: $(if [[ "$REQUIRE_EMAIL_VERIFICATION" =~ ^[Yy]$ ]]; then echo "true"; else echo "false"; fi)
    # When require_email is false, email becomes optional on the registration form.
    # The email input field visibility depends on MAS version - newer versions may hide 
    # the field entirely when not required. If the field still appears as optional, users
    # can skip it without consequences.
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

    # Add bridge databases if any selected
    if [ ${#SELECTED_BRIDGES[@]} -gt 0 ]; then
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            cat >> "$TARGET_DIR/postgres_init/01-create-databases.sh" << EOF

# Create database for mautrix-$bridge bridge
psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" --dbname "\$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE mautrix_${bridge}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mautrix_${bridge}')\gexec
EOSQL
echo "PostgreSQL: mautrix_${bridge} database created (if needed)"
EOF
        done
    fi

    chmod +x "$TARGET_DIR/postgres_init/01-create-databases.sh"
    echo -e "   ${SUCCESS}✓ PostgreSQL init script created${RESET}"
}

# Generate Docker Compose configuration
generate_docker_compose() {
    echo -e "\n${ACCENT}>> Generating Docker Compose configuration...${RESET}"

    # Calculate derived port numbers
    local MAS_ADMIN_PORT=$((PORT_MAS + 71))

    # Generate .env file for Docker Compose to preserve variables on restart
    cat > "$TARGET_DIR/.env" << ENVEOF
PORT_SYNAPSE=$PORT_SYNAPSE
PORT_SYNAPSE_ADMIN=$PORT_SYNAPSE_ADMIN
PORT_ELEMENT_CALL=$PORT_ELEMENT_CALL
PORT_LIVEKIT=$PORT_LIVEKIT
PORT_MAS=$PORT_MAS
PORT_ELEMENT_WEB=$PORT_ELEMENT_WEB
PORT_SLIDING_SYNC=$PORT_SLIDING_SYNC
PORT_MEDIA_REPO=$PORT_MEDIA_REPO
PORT_ELEMENT_ADMIN=$PORT_ELEMENT_ADMIN
CONTAINER_SUFFIX=$CONTAINER_SUFFIX
ENVEOF

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
      test: [ "CMD-SHELL", "pg_isready -U synapse && psql -U synapse -lqt | cut -d '|' -f1 | grep -qw matrix_auth" ]
      interval: 5s
      timeout: 5s
      retries: 20
    networks: [matrix-net]
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
    ports: [ "$PORT_SYNAPSE:8008" ]
    depends_on:
      postgres:
        condition: service_healthy
      matrix-auth:
        condition: service_started
    healthcheck:
      test: [ "CMD-SHELL", "curl -f http://localhost:8008/_matrix/client/versions || exit 1" ]
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 180s
    networks: [matrix-net]
    labels:
      com.docker.compose.project: "matrix-stack"

  # LiveKit SFU Server - Multi-screenshare support + built-in TURN/STUN
  livekit:
    container_name: livekit
    image: livekit/livekit-server:latest
    restart: unless-stopped
    REPLACE_LIVEKIT_NETWORK_MODE
    command: --config /etc/livekit.yaml
    volumes: [ "./livekit/livekit.yaml:/etc/livekit.yaml:ro" ]
    REPLACE_LIVEKIT_PORTS
    REPLACE_LIVEKIT_NETWORKS
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
    ports: [ "8089:8080" ]
    depends_on: [livekit]
    networks: [matrix-net]
    labels:
      com.docker.compose.project: "matrix-stack"

  # MAS (Matrix Authentication Service) - Handles authentication
  matrix-auth:
    container_name: matrix-auth
    image: ghcr.io/element-hq/matrix-authentication-service:latest
    restart: unless-stopped
    command: server --config /config.yaml
    volumes: [ "./mas/config.yaml:/config.yaml:ro" ]
    ports: [ "$PORT_MAS:8080", "MAS_ADMIN_PORT_PLACEHOLDER:8081" ]
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      disable: true
    networks: [matrix-net]
    labels:
      com.docker.compose.project: "matrix-stack"

  # Element Web - Matrix Web Client (required for proper OIDC login flow)
  element-web:
    container_name: element-web
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes: [ "./element-web/config.json:/app/config.json:ro" ]
    ports: [ "$PORT_ELEMENT_WEB:80" ]
    networks: [matrix-net]
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
    sed -i "s/MAS_ADMIN_PORT_PLACEHOLDER/$MAS_ADMIN_PORT/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_SUB_LIVEKIT/$SUB_LIVEKIT/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_DOMAIN/$DOMAIN/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_LK_API_KEY/$LK_API_KEY/g" "$TARGET_DIR/compose.yaml"
    sed -i "s/REPLACE_LK_API_SECRET/$LK_API_SECRET/g" "$TARGET_DIR/compose.yaml"
    
    # Apply container name suffix (if PORT_OFFSET > 0)
    if [ -n "$CONTAINER_SUFFIX" ]; then
        # Replace core container names with suffix
        sed -i "s/container_name: synapse-db/container_name: synapse-db${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: synapse$/container_name: synapse${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: livekit$/container_name: livekit${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: livekit-jwt/container_name: livekit-jwt${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: matrix-auth/container_name: matrix-auth${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: element-web/container_name: element-web${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: nginx-proxy-manager/container_name: nginx-proxy-manager${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: caddy/container_name: caddy${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: traefik/container_name: traefik${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: newt/container_name: newt${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        
        # Replace optional feature container names with suffix
        sed -i "s/container_name: element-call/container_name: element-call${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: synapse-admin/container_name: synapse-admin${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: element-admin/container_name: element-admin${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: sliding-sync/container_name: sliding-sync${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: matrix-media-repo/container_name: matrix-media-repo${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/container_name: coturn/container_name: coturn${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        
        # Replace volume names with suffix
        sed -i "s/: \.\/postgres_data\//: .\/postgres_data${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/synapse\//: .\/synapse${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/livekit\//: .\/livekit${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/mas\//: .\/mas${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/element-web\//: .\/element-web${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/bridges\//: .\/bridges${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/element-call\//: .\/element-call${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/sliding-sync\//: .\/sliding-sync${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
        sed -i "s/: \.\/media-repo\//: .\/media-repo${CONTAINER_SUFFIX}\//g" "$TARGET_DIR/compose.yaml"
    fi

    # Configure LiveKit network mode and ports based on dual-stack setting
    if [[ "$LIVEKIT_DUAL_STACK" == "true" ]]; then
        # Use host network mode for both LAN and WAN access
        sed -i "s|REPLACE_LIVEKIT_NETWORK_MODE|network_mode: host|g" "$TARGET_DIR/compose.yaml"
        sed -i "s|REPLACE_LIVEKIT_PORTS||g" "$TARGET_DIR/compose.yaml"
        sed -i "s|REPLACE_LIVEKIT_NETWORKS||g" "$TARGET_DIR/compose.yaml"
    else
        # Use bridge network with explicit port mapping for LAN only
        sed -i "s|REPLACE_LIVEKIT_NETWORK_MODE||g" "$TARGET_DIR/compose.yaml"
        
        cat > /tmp/livekit_ports.txt <<PORTSEOF
    ports:
      - "$PORT_LIVEKIT:7880"
      - "$((PORT_LIVEKIT+1)):7881/tcp"
      - "$((PORT_LIVEKIT+2)):7882/udp"
      - "3478:3478/udp"
      - "3478:3478/tcp"
      - "5349:5349/tcp"
      - "50000-50500:50000-50500/udp"
PORTSEOF
        
        # Insert temp file content and remove placeholder
        sed -i '/REPLACE_LIVEKIT_PORTS/r /tmp/livekit_ports.txt' "$TARGET_DIR/compose.yaml"
        sed -i '/REPLACE_LIVEKIT_PORTS/d' "$TARGET_DIR/compose.yaml"
        rm -f /tmp/livekit_ports.txt
        
        sed -i "s|REPLACE_LIVEKIT_NETWORKS|networks: [ matrix-net ]|g" "$TARGET_DIR/compose.yaml"
    fi
    
    # Save deployment metadata for verify command
    cat > "$TARGET_DIR/.deployment-metadata" << METAEOF
# Matrix Stack Deployment Metadata - DO NOT DELETE
# Generated during installation - do not edit manually
# Created: $(date '+%Y-%m-%d %H:%M:%S')
DEPLOYMENT_LOCAL_IP="$AUTO_LOCAL_IP"
DEPLOYMENT_PUBLIC_IP="$AUTO_PUBLIC_IP"
DEPLOYMENT_DOMAIN="$DOMAIN"
DEPLOYMENT_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
DEPLOYMENT_PORT_OFFSET="$PORT_OFFSET"
DEPLOYMENT_CONTAINER_SUFFIX="$CONTAINER_SUFFIX"
PORT_SYNAPSE=$PORT_SYNAPSE
PORT_SYNAPSE_ADMIN=$PORT_SYNAPSE_ADMIN
PORT_MAS=$PORT_MAS
PORT_ELEMENT_WEB=$PORT_ELEMENT_WEB
PORT_ELEMENT_CALL=$PORT_ELEMENT_CALL
PORT_ELEMENT_ADMIN=$PORT_ELEMENT_ADMIN
PORT_SLIDING_SYNC=$PORT_SLIDING_SYNC
PORT_MEDIA_REPO=$PORT_MEDIA_REPO
PORT_LIVEKIT=$PORT_LIVEKIT
CONTAINER_SUFFIX=$CONTAINER_SUFFIX
METAEOF
    chmod 600 "$TARGET_DIR/.deployment-metadata"

    # Insert Element Admin if enabled
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        sed -i '/^networks:/i\
\
  # Element Admin Web Interface\
  element-admin:\
    container_name: element-admin\
    image: oci.element.io/element-admin:latest\
    restart: unless-stopped\
    ports: [ "$PORT_ELEMENT_ADMIN:8080" ]\
    environment:\
      SERVER_NAME: '"$SERVER_NAME"'\
    networks: [matrix-net]\
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
    ports: [ "$PORT_SYNAPSE_ADMIN:80" ]\
    networks: [matrix-net]\
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
    ports: [ "$PORT_ELEMENT_CALL:8080" ]\
    networks: [matrix-net]\
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
      SYNCV3_BINDADDR: 0.0.0.0:'"$PORT_SLIDING_SYNC"'\
      SYNCV3_DB: postgresql://'"$DB_USER"':'"$DB_PASS"'@postgres/syncv3?sslmode=disable\
    ports: [ "$PORT_SLIDING_SYNC:$PORT_SLIDING_SYNC" ]\
    depends_on:\
      postgres:\
        condition: service_healthy\
      synapse:\
        condition: service_healthy\
    networks: [matrix-net]\
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
    ports: [ "$PORT_MEDIA_REPO:8000" ]\
    environment:\
      REPO_CONFIG: /config/media-repo.yaml\
    depends_on:\
      postgres:\
        condition: service_healthy\
      synapse:\
        condition: service_healthy\
    networks: [matrix-net]\
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
                discord|telegram|whatsapp|signal|slack|meta)
                    if grep -q "mautrix-${bridge}:" "$TARGET_DIR/compose.yaml" 2>/dev/null || \
                       grep -q "container_name: matrix-bridge-${bridge}" "$TARGET_DIR/compose.yaml" 2>/dev/null; then
                        continue
                    fi
                    sed -i '/^networks:/i\
\
  # mautrix-'"$bridge"' Bridge\
  mautrix-'"$bridge"':\
    container_name: matrix-bridge-'"$bridge${CONTAINER_SUFFIX}"'\
    image: dock.mau.dev/mautrix/'"$bridge"':latest\
    restart: unless-stopped\
    volumes:\
      - ./bridges/'"$bridge"':/data\
    depends_on:\
      synapse:\
        condition: service_healthy\
      postgres:\
        condition: service_healthy\
    networks: [ '\"matrix-net${CONTAINER_SUFFIX}\"' ]\
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
        sed -i '\|^networks:|i\
\
  # Nginx Proxy Manager - Reverse proxy with web UI\
  nginx-proxy-manager:\
    container_name: nginx-proxy-manager\
    image: jc21/nginx-proxy-manager:latest\
    restart: unless-stopped\
    ports:\
      - "'"$NPM_HTTP_PORT"':80"\
      - "'"$NPM_HTTPS_PORT"':443"\
      - "81:81"\
    volumes:\
      - ./npm/data:/data\
      - ./npm/letsencrypt:/etc/letsencrypt\
    networks: [matrix-net]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
        echo -e "   ${SUCCESS}✓ Nginx Proxy Manager added to stack (ports: $NPM_HTTP_PORT:80, $NPM_HTTPS_PORT:443, 81:81)${RESET}"
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
    networks: [matrix-net]\\
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
    networks: [matrix-net]\\
    labels:\\
      com.docker.compose.project: "matrix-stack"\\
' "$TARGET_DIR/compose.yaml"
        echo -e "   ${SUCCESS}✓ Traefik added to stack${RESET}"
    fi

    # Add Newt tunnel container if Pangolin is selected
    if [[ "$PROXY_TYPE" == "pangolin" ]]; then
        sed -i '/^networks:/i\
\
  # Newt — Pangolin tunnel client (zero open ports on home server)\
  newt:\
    container_name: newt\
    image: fosrl/newt:latest\
    restart: unless-stopped\
    environment:\
      - PANGOLIN_URL='"$PANGOLIN_URL"'\
      - TUNNEL_ID='"$PANGOLIN_NEWT_ID"'\
      - TUNNEL_SECRET='"$PANGOLIN_NEWT_SECRET"'\
    networks: [matrix-net]\
    labels:\
      com.docker.compose.project: "matrix-stack"\
' "$TARGET_DIR/compose.yaml"
        echo -e "   ${SUCCESS}✓ Newt tunnel container added to stack${RESET}"
    fi
    
    # Replace network names with suffix - MUST be done LAST after all container injections
    if [ -n "$CONTAINER_SUFFIX" ]; then
        sed -i "s/networks: \\[ *matrix-net *\\]/networks: [ matrix-net${CONTAINER_SUFFIX} ]/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/- matrix-net$/- matrix-net${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/^  matrix-net:$/  matrix-net${CONTAINER_SUFFIX}:/g" "$TARGET_DIR/compose.yaml"
        sed -i "s/^    name: matrix-net$/    name: matrix-net${CONTAINER_SUFFIX}/g" "$TARGET_DIR/compose.yaml"
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

# Experimental Features
experimental_features:
  msc4186_enabled: true  # Simplified Sliding Sync (Element X support)

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
  url: wss://$SUB_LIVEKIT.$DOMAIN
  livekit_api_key: $LK_API_KEY
  livekit_api_secret: $LK_API_SECRET

# Element Call - MatrixRTC transport (MSC4143)
experimental_features:
  msc4143_enabled: true

rtc_transports:
  - type: livekit
    livekit_service_url: https://$SUB_CALL.$DOMAIN

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
    until curl -fsS -o /dev/null "http://$AUTO_LOCAL_IP:81/api/" 2>/dev/null || \
          docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^nginx-proxy-manager$" || \
          [ $TRIES -ge 60 ]; do
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
    TOKEN=$(curl -s -X POST "http://$AUTO_LOCAL_IP:81/api/tokens" \
        -H "Content-Type: application/json" \
        -d '{"identity":"admin@example.com","secret":"changeme"}' \
        | grep -o '"token":"[^" ]*"' | cut -d'"' -f4)

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
        -d "{\"email\":\"$NPM_ADMIN_EMAIL\",\"nickname\":\"Matrix Admin\",\"roles\":[\"admin\" ]}")

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
    reverse_proxy $AUTO_LOCAL_IP:$PORT_ELEMENT_CALL
    header { Access-Control-Allow-Origin * }
}
"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Element Admin
$SUB_ELEMENT_ADMIN.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_ELEMENT_ADMIN
}
"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Synapse Admin
$SUB_SYNAPSE_ADMIN.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_SYNAPSE_ADMIN
}
"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Sliding Sync Proxy
$SUB_SLIDING_SYNC.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_SLIDING_SYNC
}
"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        EXTRA_BLOCKS+="
# Matrix Media Repository
$SUB_MEDIA_REPO.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_MEDIA_REPO
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
        respond '{"m.homeserver":{"base_url":"https://$SUB_MATRIX.$DOMAIN"},"m.identity_server":{"base_url":"https://vector.im"},"m.authentication":{"issuer":"https://$SUB_MAS.$DOMAIN/","account":"https://$SUB_MAS.$DOMAIN/account"},"org.matrix.msc3575.proxy":{"url":"https://$SUB_SLIDING_SYNC.$DOMAIN"},"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://$SUB_CALL.$DOMAIN"}]}'
    }
    handle {
        redir https://$SUB_ELEMENT.$DOMAIN
    }
}

# Matrix Homeserver
$SUB_MATRIX.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_SYNAPSE
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
    reverse_proxy $AUTO_LOCAL_IP:$PORT_MAS
    header Access-Control-Allow-Origin *
    header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With"
}

# Element Web
$SUB_ELEMENT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_ELEMENT_WEB
}

# LiveKit SFU
$SUB_LIVEKIT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_LIVEKIT
    header { Access-Control-Allow-Origin * }
}
$EXTRA_BLOCKS
CADDYEOF

    echo -e "   ${SUCCESS}✓ Caddyfile written — Caddy will load it on startup${RESET}"
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
      entryPoints: [\"websecure\" ]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    element-call:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:$PORT_ELEMENT_CALL\""
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    element-admin:
      rule: \"Host(\`$SUB_ELEMENT_ADMIN.$DOMAIN\`)\"
      service: element-admin
      entryPoints: [\"websecure\" ]
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
      entryPoints: [\"websecure\" ]
      tls:
        certResolver: letsencrypt"
        EXTRA_SERVICES+="
    synapse-admin:
      loadBalancer:
        servers:
          - url: \"http://$AUTO_LOCAL_IP:$PORT_SYNAPSE_ADMIN\""
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        EXTRA_ROUTERS+="
    sliding-sync:
      rule: \"Host(\`$SUB_SLIDING_SYNC.$DOMAIN\`)\"
      service: sliding-sync
      entryPoints: [\"websecure\" ]
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
      entryPoints: [\"websecure\" ]
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
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
      middlewares:
        - cors-headers

    matrix-auth:
      rule: "Host(\`$SUB_MAS.$DOMAIN\`)"
      service: matrix-auth
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt

    element-web:
      rule: "Host(\`$SUB_ELEMENT.$DOMAIN\`)"
      service: element-web
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt

    livekit:
      rule: "Host(\`$SUB_LIVEKIT.$DOMAIN\`)"
      service: livekit
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt

    base-domain:
      rule: "Host(\`$DOMAIN\`) && Path(\`/.well-known/matrix/server\`)"
      service: wellknown-server
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
      middlewares: [wellknown-server-resp]

    base-domain-client:
      rule: "Host(\`$DOMAIN\`) && Path(\`/.well-known/matrix/client\`)"
      service: wellknown-client
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
      middlewares: [wellknown-client-resp]
$EXTRA_ROUTERS

  services:
    matrix:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:$PORT_SYNAPSE"

    matrix-auth:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:$PORT_MAS"

    element-web:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:$PORT_ELEMENT_WEB"

    livekit:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:$PORT_LIVEKIT"

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
show_vpn_setup_guide() {
    # This will be called after IPs are detected, so we can use them
    cat << 'VPNGUIDEEOF'

╔══════════════════════════════════════════════════════════════╗
║          RUNNING MATRIX THROUGH A VPN/PROXY/TUNNEL           ║
╚══════════════════════════════════════════════════════════════╝

Federation and external access CAN work through a VPN. Here's how:

STEP 1: Identify Your External IP
────────────────────────────────
This is the IP that external Matrix servers will connect to:
  • If using VPN: Your exit node's public IP (NOT your tunnel IP)
  • If using proxy: The proxy's public IP
  • If using Wireguard: Your endpoint's IP

To find it: Go to https://ifconfig.me from your server
Or run: curl ifconfig.me

STEP 2: Set Up DNS A Records
──────────────────────────────
Your domain's DNS A records MUST point to your external IP:

VPNGUIDEEOF

    # Show actual detected IP in the guide
    echo "  matrix.yourdomain.com          A    $DETECTED_PUBLIC      (your external IP)"
    echo "  auth.yourdomain.com            A    $DETECTED_PUBLIC      (same IP)"
    echo "  element.yourdomain.com         A    $DETECTED_PUBLIC      (same IP)"
    echo "  livekit.yourdomain.com         A    $DETECTED_PUBLIC      (same IP)"
    echo "  turn.yourdomain.com            A    $DETECTED_PUBLIC      (same IP, DNS Only for TURN)"
    echo ""
    echo "NOT your VPN tunnel IP, NOT your local IP ($DETECTED_LOCAL)."
    echo ""
    
    cat << 'VPNGUIDEEOF2'
STEP 3: Configure Reverse Proxy
─────────────────────────────────
Your reverse proxy (NPM, Caddy, Traefik) must listen on ALL interfaces:
  • Nginx: Listen on 0.0.0.0:80 and 0.0.0.0:443
  • Caddy: Listen on :80 and :443 (default is all interfaces)
  • Traefik: entryPoints on 0.0.0.0:80 and 0.0.0.0:443

STEP 4: Verify Connectivity
──────────────────────────────
After setup, test that external servers can reach you:

  # From a server NOT on your network:
  nslookup matrix.yourdomain.com
  curl -I https://matrix.yourdomain.com/.well-known/matrix/server
  
  # Should return HTTP 200, not connection refused or timeout

STEP 5: Monitor Logs
──────────────────────
After deployment, check Synapse logs for federation errors:
  
  docker logs synapse | grep -i "federation\|tls\|connection"

COMMON ISSUES & FIXES
─────────────────────

Problem: "Federation not working"
Fix: Check DNS A records point to correct external IP
     Verify reverse proxy is listening on 0.0.0.0

Problem: "Connection refused from external servers"
Fix: Ensure ports 80/443 are forwarded through your VPN/proxy
     Check firewall allows incoming connections

Problem: "Certificate errors in federation"
Fix: Ensure Let's Encrypt (or your CA) can reach your domain
     .well-known files must be accessible from external IPs

VPNGUIDEEOF2
}

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
    echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:8008${RESET}"
    echo -e "   Enable:     SSL (Force HTTPS), Let's Encrypt certificate"
    echo -e "   ${NOTE_ICON}${SUCCESS}NOTE: For the base domain an Origin server certificate might be needed${RESET}\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << BASECONF
# Matrix well-known - required for client and federation discovery
location = /.well-known/matrix/server {
    default_type application/json;
    add_header Access-Control-Allow-Origin * always;
    add_header Cache-Control "no-cache" always;
    return 200 '{"m.server": "$SUB_MATRIX.$DOMAIN:443"}';
}

location = /.well-known/matrix/client {
    default_type application/json;
    add_header Access-Control-Allow-Origin * always;
    add_header Cache-Control "no-cache" always;
    return 200 '{"m.homeserver":{"base_url":"https://$SUB_MATRIX.$DOMAIN"},"m.identity_server":{"base_url":"https://vector.im"},"m.authentication":{"issuer":"https://$SUB_MAS.$DOMAIN/","account":"https://$SUB_MAS.$DOMAIN/account"},"org.matrix.msc3575.proxy":{"url":"https://$SUB_SLIDING_SYNC.$DOMAIN"},"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://$SUB_CALL.$DOMAIN"}]}';
}

# Matrix client API - required for auth_metadata and OIDC discovery (e.g. Element Admin)
location ~* ^/_matrix/client/ {
    proxy_pass http://$AUTO_LOCAL_IP:8008;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_hide_header Access-Control-Allow-Origin;
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
}

# Synapse ESS version endpoint - required for Element Admin
location ~* ^/_synapse/ess/ {
    proxy_pass http://$AUTO_LOCAL_IP:8008;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_hide_header Access-Control-Allow-Origin;
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
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
    echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:8008${RESET}"
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
    proxy_pass http://$AUTO_LOCAL_IP:$PORT_MAS;
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
    proxy_pass http://$AUTO_LOCAL_IP:8008;
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
    proxy_pass http://$AUTO_LOCAL_IP:8008;
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
    proxy_pass http://$AUTO_LOCAL_IP:8008;
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
    echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:$PORT_MAS${RESET}"
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
    echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:7880${RESET}"
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
        echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:8007${RESET}"
        echo -e "   Enable:     Websockets, SSL (Force HTTPS)"
        echo -e "   ${WARNING}⚠  Do NOT enable Block Exploits / ModSecurity — it breaks Element Call${RESET}"
        echo -e "   ${WARNING}Note: Element Call is a widget launched from Element Web — not a standalone login page${RESET}\n"
        echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
        print_code << CALLCONF
# Element Call - iframe widget, requires CORS and frame embedding
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
proxy_read_timeout 86400;
proxy_send_timeout 86400;
proxy_hide_header Access-Control-Allow-Origin;
proxy_hide_header Access-Control-Allow-Methods;
proxy_hide_header Access-Control-Allow-Headers;
add_header Access-Control-Allow-Origin * always;
add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;
add_header X-Frame-Options "ALLOWALL" always;

# Route JWT service requests to livekit-jwt on the stack
location /sfu/get {
    proxy_pass http://$AUTO_LOCAL_IP:8089;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
CALLCONF
        echo -e "\n${INFO}Verify LiveKit is configured:${RESET}"
        echo -e "   • LiveKit proxy host is set to ${INFO}$SUB_LIVEKIT.$DOMAIN${RESET}"
        echo -e "   • LiveKit forwards to ${INFO}http://$AUTO_LOCAL_IP:7880${RESET}"
        echo -e "   • LiveKit has Websockets ENABLED${RESET}"
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
    echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:$PORT_ELEMENT_WEB${RESET}"
    echo -e "   Enable:     Websockets, SSL (Force HTTPS)"
    echo -e "   ${SUCCESS}Primary client — users log in here, MAS handles OIDC, Element Call launches as widget${RESET}\n"
    echo -e "${ACCENT}Advanced Tab ${INFO}(copy everything inside the box):${RESET}"
    print_code << ELEMENTWEBCONF
# Prevent config.json being cached
location = /config.json {
    proxy_pass http://$AUTO_LOCAL_IP:$PORT_ELEMENT_WEB;
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
        echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:$PORT_ELEMENT_ADMIN${RESET}"
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
        echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:8009${RESET}"
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
        echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:$PORT_SLIDING_SYNC${RESET}"
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
        echo -e "   Forward to: ${INFO}http://$AUTO_LOCAL_IP:$PORT_MEDIA_REPO${RESET}"
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
        respond '{"m.homeserver":{"base_url":"https://$SUB_MATRIX.$DOMAIN"},"m.identity_server":{"base_url":"https://vector.im"},"m.authentication":{"issuer":"https://$SUB_MAS.$DOMAIN/","account":"https://$SUB_MAS.$DOMAIN/account"},"org.matrix.msc3575.proxy":{"url":"https://$SUB_SLIDING_SYNC.$DOMAIN"},"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://$SUB_CALL.$DOMAIN"}]}'
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
    reverse_proxy $AUTO_LOCAL_IP:$PORT_MAS
    header { Access-Control-Allow-Origin * }
}

# LiveKit SFU
$SUB_LIVEKIT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:7880
    header {
        Access-Control-Allow-Origin *
        Upgrade websocket
        Connection upgrade
    }
}

# Element Web
$SUB_ELEMENT.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_ELEMENT_WEB
}
CADDYCONF

    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo ""
        cat << CALLCONF
# Element Call
$SUB_CALL.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8007
    header { Access-Control-Allow-Origin * }
}
CALLCONF
    fi

    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << ADMINCONF
# Element Admin
$SUB_ELEMENT_ADMIN.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_ELEMENT_ADMIN
}
ADMINCONF
    fi

    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << SYNADMINCONF
# Synapse Admin
$SUB_SYNAPSE_ADMIN.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:8009
}
SYNADMINCONF
    fi

    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo ""
        cat << SLIDINGCONF
# Sliding Sync Proxy
$SUB_SLIDING_SYNC.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_SLIDING_SYNC
}
SLIDINGCONF
    fi

    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo ""
        cat << MEDIACONF
# Matrix Media Repository
$SUB_MEDIA_REPO.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:$PORT_MEDIA_REPO
}
MEDIACONF
    fi

    echo ""
    print_code << TURNCONF
# TURN (DNS only - do not proxy)
turn.$DOMAIN {
    reverse_proxy $AUTO_LOCAL_IP:3478
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
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
      middlewares:
        - wellknown-headers

    matrix:
      rule: "Host(\`$SUB_MATRIX.$DOMAIN\`)"
      service: matrix
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt

    matrix-auth:
      rule: "Host(\`$SUB_MAS.$DOMAIN\`)"
      service: matrix-auth
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt

    livekit:
      rule: "Host(\`$SUB_LIVEKIT.$DOMAIN\`)"
      service: livekit
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt

  services:
    base-domain-service:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:80"

    matrix:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8008"

    matrix-auth:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8010"

    livekit:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:7880"

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
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
# Add to services section:
    element-call:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8007"
CALLCONF
    fi

    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << ADMINCONF
# Add to routers section:
    element-admin:
      rule: "Host(\`$SUB_ELEMENT_ADMIN.$DOMAIN\`)"
      service: element-admin
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
# Add to services section:
    element-admin:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8014"
ADMINCONF
    fi

    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo ""
        cat << SYNADMINCONF
# Add to routers section:
    synapse-admin:
      rule: "Host(\`$SUB_SYNAPSE_ADMIN.$DOMAIN\`)"
      service: synapse-admin
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
# Add to services section:
    synapse-admin:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8009"
SYNADMINCONF
    fi

    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo ""
        cat << SLIDINGCONF
# Add to routers section:
    sliding-sync:
      rule: "Host(\`$SUB_SLIDING_SYNC.$DOMAIN\`)"
      service: sliding-sync
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
# Add to services section:
    sliding-sync:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8011"
SLIDINGCONF
    fi

    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo ""
        cat << MEDIACONF
# Add to routers section:
    media-repo:
      rule: "Host(\`$SUB_MEDIA_REPO.$DOMAIN\`)"
      service: media-repo
      entryPoints: [ "websecure" ]
      tls:
        certResolver: letsencrypt
# Add to services section:
    media-repo:
      loadBalancer:
        servers:
          - url: "http://$AUTO_LOCAL_IP:8013"
MEDIACONF
    fi

    echo -e "\n${ACCENT}Restart Traefik:${RESET}"
    echo -e "${INFO}docker restart traefik${RESET}\n"

    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r
}

# Display latest changelog
show_changelog() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│                        CHANGELOG                             │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e ""
    echo -e "${ACCENT}v${SCRIPT_VERSION}${RESET} — latest"
    echo -e "${INFO}────────────────────────────────────────────${RESET}"
    echo -e ""
    echo -e "  ${SUCCESS}•${RESET} Multi-stack support — install multiple independent stacks on one server"
    echo -e "  ${SUCCESS}•${RESET} Container/network name conflict detection — auto-appends -2, -3, etc."
    echo -e "  ${SUCCESS}•${RESET} Reconfigure menu — modify domain, features and bridges post-install"
    echo -e "  ${SUCCESS}•${RESET} Verify supports multi-stack — select which stacks to check via whiptail"
    echo -e "  ${SUCCESS}•${RESET} Corrupt compose.yaml auto-repair when re-adding existing bridges"
    echo -e "  ${SUCCESS}•${RESET} Cleanup whiptail shows stacks only — checkbox per stack, not per resource"
    echo -e "  ${SUCCESS}•${RESET} Element Call fixed — resolved MISSING_MATRIX_RTC_FOCUS and MISSING_MATRIX_RTC_TRANSPORT errors"
    echo -e ""
    echo -e "${ACCENT}v1.6${RESET} — 2026-03-03"
    echo -e "${INFO}────────────────────────────────────────────${RESET}"
    echo -e ""
    echo -e "  ${SUCCESS}•${RESET} Element X support — msc4186_enabled: true added to Synapse"
    echo -e "  ${SUCCESS}•${RESET} Caddy/Traefik guided setup for existing proxy installs"
    echo -e "  ${SUCCESS}•${RESET} Caddy auto-install fix — premature reload removed"
    echo -e "  ${SUCCESS}•${RESET} Arch Linux fixes — IP detection and daemon.json write"
    echo -e "  ${SUCCESS}•${RESET} LiveKit JWT port changed to 8089 (Traefik conflict fix)"
    echo -e ""
    echo -e "${ACCENT}v1.5${RESET} — 2026-03-03"
    echo -e "${INFO}────────────────────────────────────────────${RESET}"
    echo -e ""
    echo -e "  ${SUCCESS}•${RESET} Pangolin reverse proxy support (Newt tunnel, zero open ports)"
    echo -e "  ${SUCCESS}•${RESET} Storage check before path selection"
    echo -e "  ${SUCCESS}•${RESET} Network detection revamp with re-detect loop and manual fallback"
    echo -e "  ${SUCCESS}•${RESET} NPM base domain config rewrite (inline well-known, Element Admin)"
    echo -e "  ${SUCCESS}•${RESET} MAS config fix — homeserver uses SERVER_NAME not DOMAIN"
    echo -e "  ${SUCCESS}•${RESET} Version detection handles v/V tag prefixes"
    echo -e ""
    echo -e "${ACCENT}v1.4 — v1.0${RESET}"
    echo -e "${INFO}────────────────────────────────────────────${RESET}"
    echo -e ""
    echo -e "  ${TEXT_MUTED:-}See version.txt for full history${RESET}"
    echo -e ""
    echo -e "${WARNING}Press ENTER to return to menu...${RESET}"
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
    service: http://$AUTO_LOCAL_IP:8008

  - hostname: $SUB_MAS.$DOMAIN
    service: http://$AUTO_LOCAL_IP:8010

  - hostname: $SUB_ELEMENT.$DOMAIN
    service: http://$AUTO_LOCAL_IP:8012

  - hostname: $SUB_LIVEKIT.$DOMAIN
    service: http://$AUTO_LOCAL_IP:7880
CFCONF

    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_CALL.$DOMAIN"
        echo "    service: http://$AUTO_LOCAL_IP:8007"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_ELEMENT_ADMIN.$DOMAIN"
        echo "    service: http://$AUTO_LOCAL_IP:8014"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_SYNAPSE_ADMIN.$DOMAIN"
        echo "    service: http://$AUTO_LOCAL_IP:8009"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_SLIDING_SYNC.$DOMAIN"
        echo "    service: http://$AUTO_LOCAL_IP:8011"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo "  - hostname: $SUB_MEDIA_REPO.$DOMAIN"
        echo "    service: http://$AUTO_LOCAL_IP:8013"
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

# Display Pangolin setup guide
show_pangolin_guide() {
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│                   PANGOLIN SETUP GUIDE                       │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"

    echo -e "\n${ACCENT}── STEP 1: Configure tunnels in Pangolin Dashboard ──────────────${RESET}"
    echo -e "   ${INFO}Open your Pangolin dashboard: ${SUCCESS}$PANGOLIN_URL${RESET}"
    echo -e "   ${INFO}For each service below, create a new Tunnel resource pointing to:${RESET}"
    echo -e "   ${WARNING}Target: http://$AUTO_LOCAL_IP:<port>${RESET}\n"
    echo -e "   ┌─────────────────────────────────┬─────────────────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-31s${RESET} │ ${PUBLIC_IP_COLOR}%-27s${RESET} │\n" "SUBDOMAIN" "TARGET"
    echo -e "   ├─────────────────────────────────┼─────────────────────────────┤"
    printf "   │ %-31s │ %-27s │\n" "$SUB_MATRIX.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_SYNAPSE"
    printf "   │ %-31s │ %-27s │\n" "$SUB_MAS.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_MAS"
    printf "   │ %-31s │ %-27s │\n" "$SUB_LIVEKIT.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_LIVEKIT"
    printf "   │ %-31s │ %-27s │\n" "$SUB_ELEMENT.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_ELEMENT_WEB"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        printf "   │ %-31s │ %-27s │\n" "$SUB_CALL.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_ELEMENT_CALL"
    fi
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ %-31s │ %-27s │\n" "$SUB_ELEMENT_ADMIN.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_ELEMENT_ADMIN"
    fi
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        printf "   │ %-31s │ %-27s │\n" "$SUB_SYNAPSE_ADMIN.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_SYNAPSE_ADMIN"
    fi
    if [[ "$SLIDING_SYNC_ENABLED" == "true" ]]; then
        printf "   │ %-31s │ %-27s │\n" "$SUB_SLIDING_SYNC.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_SLIDING_SYNC"
    fi
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        printf "   │ %-31s │ %-27s │\n" "$SUB_MEDIA_REPO.$DOMAIN" "http://$AUTO_LOCAL_IP:$PORT_MEDIA_REPO"
    fi
    echo -e "   └─────────────────────────────────┴─────────────────────────────┘"
    echo -e "\n   ${WARNING}⚠️  Do NOT tunnel TURN traffic — coturn runs directly on the VPS.${RESET}"
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # STEP 2: coturn on VPS
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               PANGOLIN — COTURN ON VPS                       │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}── STEP 2: Deploy coturn on your VPS ($PANGOLIN_VPS_IP) ────────────${RESET}"
    echo -e "   ${INFO}SSH into your VPS and paste the following compose snippet.${RESET}"
    echo -e "   ${INFO}Save it as ${CONFIG_PATH}~/coturn/compose.yaml${INFO} then run ${WARNING}docker compose up -d${INFO}.${RESET}\n"
    echo -e "${ACCENT}   coturn compose.yaml ${INFO}(copy everything inside the box):${RESET}"
    print_code << COTURNEOF
services:
  coturn:
    container_name: coturn
    image: coturn/coturn:latest
    restart: unless-stopped
    network_mode: host
    command: >
      -n
      --log-file=stdout
      --realm=$DOMAIN
      --listening-ip=$PANGOLIN_VPS_IP
      --external-ip=$PANGOLIN_VPS_IP
      --listening-port=3478
      --tls-listening-port=5349
      --no-tls
      --no-dtls
      --lt-cred-mech
      --use-auth-secret
      --static-auth-secret=$LK_API_SECRET
      --no-loopback-peers
      --no-multicast-peers
      --cli-password=$LK_API_SECRET
COTURNEOF
    echo -e "\n   ${SUCCESS}✓ Uses LiveKit's shared secret — no extra credentials to manage${RESET}"
    echo -e "   ${WARNING}⚠️  Open ports on the VPS firewall: UDP/TCP 3478 and TCP 5349${RESET}"
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    ##########################################################################
    # STEP 3: DNS records
    ##########################################################################
    clear
    echo -e "${BANNER}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BANNER}│               PANGOLIN — DNS RECORDS                         │${RESET}"
    echo -e "${BANNER}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo -e "\n${ACCENT}── STEP 3: DNS records ──────────────────────────────────────────${RESET}"
    echo -e "   ${INFO}Pangolin manages subdomains via its own reverse proxy.${RESET}"
    echo -e "   ${INFO}Only the TURN subdomain needs a direct DNS record pointing to the VPS.${RESET}\n"
    echo -e "   ┌─────────────────┬───────────┬─────────────────┬─────────────────┐"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ %-15s │ %-15s │\n" "HOSTNAME" "TYPE" "VALUE" "STATUS"
    echo -e "   ├─────────────────┼───────────┼─────────────────┼─────────────────┤"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${PUBLIC_IP_COLOR}%-15s${RESET} │ %-15s │\n" "turn" "A" "$PANGOLIN_VPS_IP" "DNS ONLY"
    printf "   │ ${DNS_HOSTNAME}%-15s${RESET} │ ${DNS_TYPE}%-9s${RESET} │ ${INFO}%-15s${RESET} │ %-15s │\n" "* (wildcard)" "CNAME" "pangolin" "via Pangolin"
    echo -e "   └─────────────────┴───────────┴─────────────────┴─────────────────┘"
    echo -e "\n   ${WARNING}⚠️  TURN must always be DNS ONLY — never proxy TURN traffic${RESET}"
    echo -e "${WARNING}Press ENTER to continue...${RESET}"
    read -r

    clear
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
#   SCAN_HAS_BLOCKER      – "true" if a system-service conflict was
#                           found (caller should abort / advise manual fix)
scan_and_remove_matrix_resources() {
    local extra_dir="${1:-}"
    local skip_prompt="${2:-false}"

    local STACK_PATHS=()
    
    # Use systemwide detection to find all stacks (same as uninstall)
    mapfile -t STACK_PATHS < <(find_all_matrix_stacks)
    
    # If no stacks found via systemwide detection, fall back to extra_dir if provided
    if [ ${#STACK_PATHS[@]} -eq 0 ] && [ -n "$extra_dir" ]; then
        STACK_PATHS=("$extra_dir")
    fi
    
    # If still nothing found, use hardcoded paths as last resort
    if [ ${#STACK_PATHS[@]} -eq 0 ]; then
        STACK_PATHS=(
            "/opt/stacks/matrix-stack"
            "/opt/matrix-stack"
            "$HOME/matrix-stack"
            "$(pwd)/matrix-stack"
        )
    fi

    SCAN_FOUND_RESOURCES=false
    SCAN_HAS_BLOCKER=false
    local RESOURCE_LIST=()
    
    # Track which stack directories have resources
    declare -A STACK_DIR_RESOURCES
    declare -A CONTAINER_TO_STACK  # Track which container belongs to which stack

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
            
            # Try to determine which stack directory this container belongs to
            local container_stack=""
            local container_mounts=$(docker inspect "$NAME" --format '{{range .Mounts}}{{.Source}}|{{end}}' 2>/dev/null || true)
            for stack_path in "${STACK_PATHS[@]}"; do
                if echo "$container_mounts" | grep -q "^$stack_path"; then
                    container_stack="$stack_path"
                    CONTAINER_TO_STACK[ "$NAME" ]="$container_stack"
                    break
                fi
            done
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
            STACK_DIR_RESOURCES[ "$path" ]="true"  # Track this directory
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
            # Skip if it's a known Matrix container process — not a system-level blocker
            [[ "$proc_name" == "livekit-server" || "$proc_name" == "synapse" || "$proc_name" == "coturn" ]] && continue
            SCAN_FOUND_RESOURCES=true
            HAS_PORT_CONFLICT=true
            RESOURCE_LIST+=("port|$port|${proc_name:-unknown}")
        fi
    done

    # ── Count directories ────────────────────────────────────────────────────
    local _DIR_COUNT=0
    for _e in "${RESOURCE_LIST[@]}"; do
        [[ "${_e%%|*}" == "directory" ]] && ((_DIR_COUNT++)) || true
    done

    # ── Display results ──────────────────────────────────────────────────────
    if [ "$SCAN_FOUND_RESOURCES" = true ]; then
        # If multiple stacks found, skip detailed resource display and show whiptail instead
        if [ "$_DIR_COUNT" -gt 1 ]; then
            # Multiple stacks - skip the detailed listing, will show in whiptail
            : # Continue to whiptail selection
        else
            # Single stack - show detailed resource listing
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
                        : # detected and tracked but not displayed
                        ;;
                esac
            done
            echo ""
        fi
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

    # ── Prompt and remove ────────────────────────────────────────────────────
    if [ "$skip_prompt" != "true" ]; then
        if [ "$_DIR_COUNT" -gt 1 ] && command -v whiptail &>/dev/null; then
            # Multiple stacks — whiptail showing only stack directories
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
            local -a wt_items=()
            local -a wt_keys=()
            local _wi=0
            for entry in "${RESOURCE_LIST[@]}"; do
                [[ "${entry%%|*}" == "directory" ]] || continue
                local _dp
                _dp=$(echo "$entry" | cut -d'|' -f2)
                local _dom
                _dom=$(get_stack_info "$_dp")
                local _lbl="$_dp"
                [ -n "$_dom" ] && [ "$_dom" != "unknown" ] && _lbl="$_dp | Domain: $_dom"
                wt_items+=("$_wi" "$_lbl" "OFF")
                wt_keys+=("$entry")
                ((_wi++))
            done
            unset NEWT_COLORS

            if [ ${#wt_keys[@]} -eq 0 ]; then
                echo -e "   ${SUCCESS}✓ No removable stacks found${RESET}"
                return 0
            fi

            local _sel
            _sel=$(NEWT_COLORS='
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
' whiptail --title " Select Stacks to Remove " \
                --checklist "Choose which stacks to clean up:" \
                $((${#wt_keys[@]} + 8)) 78 ${#wt_keys[@]} \
                "${wt_items[@]}" \
                3>&1 1>&2 2>&3)

            local _wt_exit=$?
            if [ $_wt_exit -ne 0 ] || [ -z "$_sel" ]; then
                echo -e "${INFO}Cleanup cancelled${RESET}"
                return 0
            fi

            # Build CLEANUP_SELECTED_INDICES from selected directory indices
            # Map back to full RESOURCE_LIST indices for the existing filter logic
            CLEANUP_RESOURCE_KEYS=("${wt_keys[@]}")
            CLEANUP_SELECTED_INDICES="${_sel//\"/}"

        else
            # Single stack — plain y/n
            echo -ne "Remove selected Docker resources listed above? (y/n): "
            read -r CLEAN_CONFIRM
            if [[ ! "$CLEAN_CONFIRM" =~ ^[Yy]$ ]]; then
                return 0
            fi

            CLEANUP_RESOURCE_KEYS=()
            for entry in "${RESOURCE_LIST[@]}"; do
                CLEANUP_RESOURCE_KEYS+=("$entry")
            done
        fi
    fi

    if true; then
        # Process whiptail selection if it was made
        if [ -n "${CLEANUP_SELECTED_INDICES:-}" ]; then
            declare -a filtered_resources
            declare -a selected_dirs

            # First pass: collect selected directories
            for idx in ${CLEANUP_SELECTED_INDICES}; do
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 0 ] && [ "$idx" -lt ${#CLEANUP_RESOURCE_KEYS[@]} ]; then
                    local entry="${CLEANUP_RESOURCE_KEYS[$idx]}"
                    local entry_type="${entry%%|*}"
                    if [ "$entry_type" = "directory" ]; then
                        local entry_dir
                        entry_dir=$(echo "$entry" | cut -d'|' -f2)
                        selected_dirs+=("$entry_dir")
                        filtered_resources+=("$entry")
                    fi
                fi
            done

            # Second pass: add ALL resources (containers, volumes, networks, bridges)
            # that belong to the selected directories
            for entry in "${RESOURCE_LIST[@]}"; do
                local etype="${entry%%|*}"
                [ "$etype" = "directory" ] && continue  # already added
                local belongs=false
                for sdir in "${selected_dirs[@]}"; do
                    local sname
                    sname=$(basename "$sdir")
                    local suffix=""
                    # detect suffix from metadata
                    [ -f "$sdir/.deployment-metadata" ] && \
                        suffix=$(grep "^CONTAINER_SUFFIX=" "$sdir/.deployment-metadata" 2>/dev/null | cut -d= -f2-)
                    case "$etype" in
                        container)
                            local cname
                            cname=$(echo "$entry" | cut -d'|' -f2)
                            # container belongs if its mounts reference this stack dir
                            if docker inspect "$cname" --format '{{range .Mounts}}{{.Source}}|{{end}}' 2>/dev/null \
                               | tr '|' '\n' | grep -q "^${sdir}"; then
                                belongs=true
                            fi
                            ;;
                        volume|network)
                            # include all — they'll be tied to this stack's containers
                            belongs=true
                            ;;
                        bridge)
                            local bridge_dir
                            bridge_dir=$(echo "$entry" | cut -d'|' -f3)
                            [[ "$bridge_dir" == "$sdir/bridges"* ]] && belongs=true
                            ;;
                        port|service)
                            belongs=true
                            ;;
                    esac
                    $belongs && break
                done
                $belongs && filtered_resources+=("$entry")
            done

            RESOURCE_LIST=("${filtered_resources[@]}")
        fi
        
        echo -e "\n${ACCENT}>> Cleaning up Matrix resources...${RESET}"
        
        # Extract selected directories from RESOURCE_LIST
        declare -a SELECTED_DIRS
        for entry in "${RESOURCE_LIST[@]}"; do
            local entry_type=$(echo "$entry" | cut -d'|' -f1)
            if [ "$entry_type" = "directory" ]; then
                local entry_dir=$(echo "$entry" | cut -d'|' -f2)
                SELECTED_DIRS+=("$entry_dir")
            fi
        done

        # Bring down the main stack cleanly first (removes network endpoints properly)
        for path in "${SELECTED_DIRS[@]}"; do
            if [ -d "$path" ]; then
                for cf in "$path/compose.yaml" "$path/docker-compose.yml"; do
                    if [ -f "$cf" ]; then
                        local _proj_name
                        _proj_name=$(basename "$path")
                        docker compose -p "$_proj_name" -f "$cf" down --remove-orphans -v 2>/dev/null || true
                        break
                    fi
                done
            fi
        done
        sleep 2

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == container\|* ]] || continue
            local cname
            cname=$(echo "$entry" | cut -d'|' -f2)
            docker stop "$cname" >/dev/null 2>&1
            docker rm   "$cname" >/dev/null 2>&1
            echo -e "   ${REMOVED}✕${RESET} ${CONTAINER_NAME}$cname${RESET}"
        done

        # Cleanup bridge directories (before removing main directory)
        local bridges_cleaned=()
        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == bridge\|* ]] || continue
            local bridge_name bridge_path
            bridge_name=$(echo "$entry" | cut -d'|' -f2)
            bridge_path=$(echo "$entry" | cut -d'|' -f3)
            rm -rf "$bridge_path" 2>/dev/null && bridges_cleaned+=("$bridge_name")
        done
        if [ ${#bridges_cleaned[@]} -gt 0 ]; then
            for bridge in "${bridges_cleaned[@]}"; do
                echo -e "   ${REMOVED}✕${RESET} ${ACCENT}$bridge${RESET} ${DOCKER_COLOR}(bridge)${RESET}"
            done
        fi

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == volume\|* ]] || continue
            local vol
            vol=$(echo "$entry" | cut -d'|' -f2)
            SHORT_VOL="${vol:0:24}..."
            docker volume rm "$vol" >/dev/null 2>&1
            echo -e "   ${REMOVED}✕${RESET} ${INFO}$SHORT_VOL${RESET} ${DOCKER_COLOR}(volume)${RESET}"
        done

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == network\|* ]] || continue
            local net
            net=$(echo "$entry" | cut -d'|' -f2)
            docker network rm "$net" 2>/dev/null || true
            echo -e "   ${REMOVED}✕${RESET} ${NETWORK_NAME}$net${RESET} ${DOCKER_COLOR}(network)${RESET}"
        done

        # Prune unused networks and system resources
        docker network prune -f >/dev/null 2>&1 || true
        docker system prune -f >/dev/null 2>&1 || true

        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" == directory\|* ]] || continue
            local dir
            dir=$(echo "$entry" | cut -d'|' -f2)
            rm -rf "$dir" && echo -e "   ${REMOVED}✕${RESET} ${CONFIG_PATH}$dir${RESET} ${DOCKER_COLOR}(directory)${RESET}" \
                || echo -e "   ${ERROR}✗ Failed to remove $dir — try: sudo rm -rf $dir${RESET}"
        done

        # Count directories in filtered RESOURCE_LIST to determine message
        local dir_count=0
        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" != directory\|* ]] && continue
            ((dir_count++))
        done
        
        # Show appropriate message based on number of stacks
        if [ "$_DIR_COUNT" -gt 1 ]; then
            echo -e "\n   ${SUCCESS}✓ All selected Matrix resources removed${RESET}"
        else
            echo -e "\n   ${SUCCESS}✓ All detected Matrix resources removed${RESET}"
        fi
        
        # Show summary of removed stacks (if any stacks were actually removed)
        declare -a removed_stacks
        for entry in "${RESOURCE_LIST[@]}"; do
            [[ "$entry" != directory\|* ]] && continue
            local dir domain
            dir=$(echo "$entry" | cut -d'|' -f2)
            removed_stacks+=("$dir")
        done
        
        if [ ${#removed_stacks[@]} -gt 0 ]; then
            echo -e "\n${ACCENT}>> Stacks successfully removed:${RESET}"
            for dir in "${removed_stacks[@]}"; do
                local domain=$(get_stack_info "$dir")
                echo -e "   ${SUCCESS}✓${RESET} $dir | Domain: $domain"
            done
        fi
    fi
}

################################################################################
# Systemwide Stack Detection & Resource Management Functions                  #
################################################################################

find_all_matrix_stacks() {
    # Find ALL Matrix stacks installed by THIS script anywhere on the system
    # Returns array of stack directories with verification
    local -a found_stacks
    local -a verified_stacks
    
    # Search locations (from most to least common)
    local search_paths=(
        "/opt/stacks"
        "/opt"
        "$HOME"
        "/srv"
        "/var/lib"
        "/home"
        "/root"
    )
    
    # Find all directories with compose.yaml (potential stacks)
    for search_path in "${search_paths[@]}"; do
        if [ -d "$search_path" ]; then
            while IFS= read -r -d '' dir; do
                # Skip if the found directory IS the search path itself
                if [ "$dir" != "$search_path" ] && [ -f "$dir/compose.yaml" ]; then
                    # Quick pre-filter: must have synapse dir or metadata to be a Matrix stack
                    if [ -d "$dir/synapse" ] || [ -f "$dir/.deployment-metadata" ]; then
                        found_stacks+=("$dir")
                    fi
                fi
            done < <(find "$search_path" -maxdepth 3 -type f -name "compose.yaml" -print0 2>/dev/null | sed -z 's|/compose.yaml||g')
        fi
    done
    
    # Verify each found stack was installed by THIS script
    for stack_path in "${found_stacks[@]}"; do
        # Must have synapse directory with homeserver.yaml
        if [ ! -d "$stack_path/synapse" ] || [ ! -f "$stack_path/synapse/homeserver.yaml" ]; then
            continue
        fi
        
        # Must have compose.yaml
        if [ ! -f "$stack_path/compose.yaml" ]; then
            continue
        fi
        
        # Must have EITHER deployment metadata OR server_name in homeserver.yaml
        if [ -f "$stack_path/.deployment-metadata" ]; then
            verified_stacks+=("$stack_path")
        elif grep -q "^server_name:" "$stack_path/synapse/homeserver.yaml" 2>/dev/null; then
            verified_stacks+=("$stack_path")
        fi
    done
    
    # Remove duplicates and sort
    declare -a unique_stacks
    declare -A seen
    for stack in "${verified_stacks[@]}"; do
        if [ -z "${seen[$stack]}" ]; then
            unique_stacks+=("$stack")
            seen[$stack]=1
        fi
    done
    
    # Return array name for caller to use
    printf '%s\n' "${unique_stacks[@]}"
}

load_stack_ports_from_containers() {
    # Load port variables from running Docker containers for a given stack directory
    # This is more reliable than reading from metadata files
    local stack_dir="$1"
    local stack_name=$(basename "$stack_dir" | tr '[:upper:]' '[:lower:]' | sed 's/-//g')
    
    # Try to get ports from running containers
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^synapse"; then
        # Extract port mappings from synapse container
        local port_mapping=$(docker port synapse 8008/tcp 2>/dev/null | cut -d: -f2)
        if [ -n "$port_mapping" ]; then
            export PORT_SYNAPSE=$port_mapping
        fi
    fi
    
    # Try other common containers
    for container in "matrix-auth" "element-web" "livekit" "livekit-jwt" "sliding-sync" "element-admin" "element-call"; do
        local ports=$(docker port "$container" 2>/dev/null | grep -oP '(?<=0.0.0.0:)\d+' | head -1)
        if [ -n "$ports" ]; then
            case "$container" in
                "matrix-auth")
                    export PORT_MAS=$ports
                    ;;
                "element-web")
                    export PORT_ELEMENT_WEB=$ports
                    ;;
                "livekit")
                    export PORT_LIVEKIT=$ports
                    ;;
                "sliding-sync")
                    export PORT_SLIDING_SYNC=$ports
                    ;;
                "element-admin")
                    export PORT_ELEMENT_ADMIN=$ports
                    ;;
                "element-call")
                    export PORT_ELEMENT_CALL=$ports
                    ;;
            esac
        fi
    done
}

parse_stack_configuration() {
    # Parse existing stack configuration from homeserver.yaml and compose.yaml
    local stack_dir="$1"

    # Parse base domain (server_name) from homeserver.yaml
    if [ -f "$stack_dir/synapse/homeserver.yaml" ]; then
        CURRENT_DOMAIN=$(grep "^server_name:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"')
    fi

    # Parse subdomains by extracting full hostnames from config files and
    # stripping the base domain to get the subdomain prefix.
    # Falls back to sensible defaults when a subdomain cannot be detected.
    CURRENT_SUB_MATRIX="matrix"
    CURRENT_SUB_MAS="auth"
    CURRENT_SUB_LIVEKIT="livekit"
    CURRENT_SUB_ELEMENT="element"
    CURRENT_SUB_CALL="call"
    CURRENT_SUB_ELEMENT_ADMIN="admin"
    CURRENT_SUB_SYNAPSE_ADMIN="admin"
    CURRENT_SUB_SLIDING_SYNC="sync"
    CURRENT_SUB_MEDIA_REPO="media"

    if [ -n "$CURRENT_DOMAIN" ]; then
        # matrix subdomain — from public_baseurl in homeserver.yaml
        local _pb
        _pb=$(grep "^public_baseurl:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"' | sed 's|https\?://||' | cut -d/ -f1)
        if [ -n "$_pb" ] && [[ "$_pb" == *".$CURRENT_DOMAIN" ]]; then
            CURRENT_SUB_MATRIX="${_pb%.$CURRENT_DOMAIN}"
        fi

        # MAS subdomain — from public_base in mas/config.yaml
        local _mas
        _mas=$(grep "public_base:" "$stack_dir/mas/config.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | sed 's|https\?://||' | cut -d/ -f1)
        if [ -n "$_mas" ] && [[ "$_mas" == *".$CURRENT_DOMAIN" ]]; then
            CURRENT_SUB_MAS="${_mas%.$CURRENT_DOMAIN}"
        fi

        # Element Web subdomain — from permalink_prefix in element-web/config.json
        local _ew
        _ew=$(grep -o '"permalink_prefix"[^,]*' "$stack_dir/element-web/config.json" 2>/dev/null | grep -oP 'https?://\K[^/"]+')
        if [ -n "$_ew" ] && [[ "$_ew" == *".$CURRENT_DOMAIN" ]]; then
            CURRENT_SUB_ELEMENT="${_ew%.$CURRENT_DOMAIN}"
        fi

        # LiveKit subdomain — from livekit url in homeserver.yaml
        local _lk
        _lk=$(grep "url: wss://" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | sed 's|wss\?://||' | cut -d/ -f1)
        if [ -n "$_lk" ] && [[ "$_lk" == *".$CURRENT_DOMAIN" ]]; then
            CURRENT_SUB_LIVEKIT="${_lk%.$CURRENT_DOMAIN}"
        fi

        # Element Call subdomain — from livekit_service_url in homeserver.yaml
        local _call
        _call=$(grep "livekit_service_url:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | sed 's|https\?://||' | cut -d/ -f1)
        if [ -n "$_call" ] && [[ "$_call" == *".$CURRENT_DOMAIN" ]]; then
            CURRENT_SUB_CALL="${_call%.$CURRENT_DOMAIN}"
        fi

        # Sliding Sync subdomain — from element-web config.json (m.proxy url)
        local _ss
        _ss=$(grep -o '"url"[^,}]*sync[^,}]*' "$stack_dir/element-web/config.json" 2>/dev/null | grep -oP 'https?://\K[^/"]+' | head -1)
        if [ -n "$_ss" ] && [[ "$_ss" == *".$CURRENT_DOMAIN" ]]; then
            CURRENT_SUB_SLIDING_SYNC="${_ss%.$CURRENT_DOMAIN}"
        fi
    fi

    # Check for installed optional features in compose.yaml
    CURRENT_FEATURES=()
    if grep -q "container_name: element-admin" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_FEATURES+=("Element Admin")
    fi
    if grep -q "container_name: element-call" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_FEATURES+=("Element Call")
    fi
    if grep -q "container_name: synapse-admin" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_FEATURES+=("Synapse Admin")
    fi
    if grep -q "container_name: matrix-media-repo" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_FEATURES+=("Media Repo")
    fi
    if grep -q "container_name: sliding-sync" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_FEATURES+=("Sliding Sync")
    fi

    # Check for installed bridges
    CURRENT_BRIDGES=()
    if grep -q "mautrix-discord:" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_BRIDGES+=("discord")
    fi
    if grep -q "mautrix-telegram:" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_BRIDGES+=("telegram")
    fi
    if grep -q "mautrix-whatsapp:" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_BRIDGES+=("whatsapp")
    fi
    if grep -q "mautrix-signal:" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_BRIDGES+=("signal")
    fi
    if grep -q "mautrix-slack:" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_BRIDGES+=("slack")
    fi
    if grep -q "mautrix-meta:" "$stack_dir/compose.yaml" 2>/dev/null; then
        CURRENT_BRIDGES+=("meta")
    fi
}

manage_features() {
    local stack_dir="$1"

    # Detect compose file path early (needed for repair and later use)
    local _compose_f=""
    for _cf in "$stack_dir/compose.yaml" "$stack_dir/docker-compose.yml" "$stack_dir/docker-compose.yaml"; do
        [ -f "$_cf" ] && _compose_f="$_cf" && break
    done
    local _compose_corrupt=false
    if [ -n "$_compose_f" ] && ! (cd "$stack_dir" && docker compose config -q 2>/dev/null); then
        _compose_corrupt=true
    fi

    # Load ports and DB info
    load_stack_ports_from_containers "$stack_dir"
    if [ -f "$stack_dir/.deployment-metadata" ]; then
        source "$stack_dir/.deployment-metadata" 2>/dev/null
    fi
    PORT_ELEMENT_ADMIN="${PORT_ELEMENT_ADMIN:-8079}"
    PORT_ELEMENT_CALL="${PORT_ELEMENT_CALL:-8089}"
    PORT_SYNAPSE_ADMIN="${PORT_SYNAPSE_ADMIN:-8088}"
    PORT_SLIDING_SYNC="${PORT_SLIDING_SYNC:-8009}"
    PORT_MEDIA_REPO="${PORT_MEDIA_REPO:-8090}"

    # Defaults for subdomains (already parsed by parse_stack_configuration)
    CURRENT_SUB_MATRIX="${CURRENT_SUB_MATRIX:-matrix}"
    CURRENT_SUB_MAS="${CURRENT_SUB_MAS:-auth}"
    CURRENT_SUB_LIVEKIT="${CURRENT_SUB_LIVEKIT:-livekit}"
    CURRENT_SUB_ELEMENT="${CURRENT_SUB_ELEMENT:-element}"
    CURRENT_SUB_CALL="${CURRENT_SUB_CALL:-call}"
    CURRENT_SUB_SLIDING_SYNC="${CURRENT_SUB_SLIDING_SYNC:-sync}"
    CURRENT_SUB_ELEMENT_ADMIN="${CURRENT_SUB_ELEMENT_ADMIN:-admin}"
    CURRENT_SUB_SYNAPSE_ADMIN="${CURRENT_SUB_SYNAPSE_ADMIN:-admin}"

    # DB creds
    local _DB_USER _DB_PASS
    _DB_USER=$(grep -A 10 "^database:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null \
        | grep "user:" | awk '{print $2}' | tr -d '"' | head -1)
    _DB_PASS=$(grep -A 10 "^database:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null \
        | grep "password:" | awk '{print $2}' | tr -d '"' | head -1)
    _DB_USER="${_DB_USER:-synapse}"

    # Sliding Sync secret
    local _SS_SECRET
    _SS_SECRET=$(docker inspect sliding-sync 2>/dev/null \
        | python3 -c "import sys,json; e=json.load(sys.stdin)[0]['Config']['Env']; print(next((x.split('=',1)[1] for x in e if x.startswith('SYNCV3_SECRET=')),'')" 2>/dev/null)
    [ -z "$_SS_SECRET" ] && _SS_SECRET=$(grep "SYNCV3_SECRET" "$stack_dir/compose.yaml" 2>/dev/null \
        | head -1 | awk -F= '{print $2}' | tr -d ' "')
    [ -z "$_SS_SECRET" ] && _SS_SECRET=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)

    # LiveKit key/secret
    local _LK_KEY _LK_SECRET
    _LK_KEY=$(grep -A5 "keys:" "$stack_dir/livekit/livekit.yaml" 2>/dev/null \
        | grep -v "^#\|keys:" | head -1 | awk '{print $1}' | tr -d ':')
    _LK_SECRET=$(grep -A5 "keys:" "$stack_dir/livekit/livekit.yaml" 2>/dev/null \
        | grep -v "^#\|keys:" | head -1 | awk '{print $2}')
    _LK_KEY="${_LK_KEY:-livekit-api-key}"
    _LK_SECRET="${_LK_SECRET:-livekit-api-secret}"

    # Network from compose
    local _NET
    _NET=$(grep "networks: \[" "$stack_dir/compose.yaml" 2>/dev/null \
        | grep -oP 'matrix-net[^\]]*' | head -1 | tr -d ' ')
    _NET="${_NET:-matrix-net}"

    # Synapse container name
    local _SYNAPSE
    _SYNAPSE=$(grep "container_name: synapse" "$stack_dir/compose.yaml" 2>/dev/null \
        | head -1 | awk '{print $2}')
    _SYNAPSE="${_SYNAPSE:-synapse}"

    # Container name suffix (e.g. "-2" for second stack)
    local _CTR_SUFFIX=""
    if grep -q "container_name: synapse-[0-9]" "$stack_dir/compose.yaml" 2>/dev/null; then
        _CTR_SUFFIX=$(grep "container_name: synapse-" "$stack_dir/compose.yaml" \
            | sed 's/.*container_name: synapse//' | grep -o '^-[0-9]*')
    fi


    # Auto-repair corrupt compose now that all variables are loaded
    if [ "$_compose_corrupt" = true ]; then
        echo -e "\n   ${WARNING}⚠  compose.yaml is corrupt — attempting auto-repair...${RESET}"
        for _svc in element-call livekit-jwt element-admin synapse-admin sliding-sync matrix-media-repo; do
            _compose_remove_svc "$_compose_f" "$_svc" 2>/dev/null || true
        done
        if (cd "$stack_dir" && docker compose config -q 2>/dev/null); then
            echo -e "   ${SUCCESS}✓ compose.yaml repaired${RESET}"
            for _feat in "${CURRENT_FEATURES[@]}"; do
                _feat_add "$stack_dir" "$_feat" "$_NET" "$_SYNAPSE" \
                    "$_DB_USER" "$_DB_PASS" "$_SS_SECRET" \
                    "$_LK_KEY" "$_LK_SECRET" "$_CTR_SUFFIX" 2>/dev/null || true
            done
            echo -e "   ${SUCCESS}✓ Features re-inserted${RESET}"
        else
            echo -e "   ${ERROR}✗ Auto-repair failed — compose.yaml may need manual inspection${RESET}"
            return 1
        fi
    fi

    # Build current feature status map
    declare -A feat_was
    feat_was["Element Admin"]=0
    feat_was["Element Call"]=0
    feat_was["Synapse Admin"]=0
    feat_was["Media Repo"]=0
    feat_was["Sliding Sync"]=0
    for f in "${CURRENT_FEATURES[@]}"; do feat_was["$f"]=1; done

    # Whiptail with bridge color scheme, currently-installed pre-checked
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
    local wt_items=()
    for f in "Element Admin" "Element Call" "Synapse Admin" "Media Repo" "Sliding Sync"; do
        local desc st
        case "$f" in
            "Element Admin") desc="Element Admin    — Matrix admin interface" ;;
            "Element Call")  desc="Element Call     — WebRTC video conferencing UI" ;;
            "Synapse Admin") desc="Synapse Admin    — Synapse server management UI" ;;
            "Media Repo")    desc="Media Repo       — Advanced media server" ;;
            "Sliding Sync")  desc="Sliding Sync     — Proxy for modern clients" ;;
        esac
        st="OFF"; [ "${feat_was[$f]}" -eq 1 ] && st="ON"
        wt_items+=("$f" "$desc" "$st")
    done

    local sel
    sel=$(whiptail --title " Manage Optional Features " \
        --checklist "Toggle features (SPACE to toggle, ENTER to confirm):" \
        17 72 5 \
        "${wt_items[@]}" \
        3>&1 1>&2 2>&3)
    local wt_exit=$?
    unset NEWT_COLORS

    if [ $wt_exit -ne 0 ]; then
        echo -e "   ${INFO}Feature management cancelled${RESET}"
        return
    fi

    # Build new status from selection
    declare -A feat_now
    feat_now["Element Admin"]=0
    feat_now["Element Call"]=0
    feat_now["Synapse Admin"]=0
    feat_now["Media Repo"]=0
    feat_now["Sliding Sync"]=0
    # whiptail returns quoted multi-word items e.g. "Element Admin" "Media Repo"
    # eval + array assignment correctly handles quoted tokens
    eval "local _sel_arr=($sel)"
    for f in "${_sel_arr[@]}"; do
        feat_now["$f"]=1
    done

    # Apply additions then removals
    local changed=false
    for f in "Element Admin" "Element Call" "Synapse Admin" "Media Repo" "Sliding Sync"; do
        if [ "${feat_was[$f]}" -eq 0 ] && [ "${feat_now[$f]}" -eq 1 ]; then
            echo -e "\n   ${SUCCESS}+ Adding: $f${RESET}"
            _feat_add "$stack_dir" "$f" "$_NET" "$_SYNAPSE" \
                "$_DB_USER" "$_DB_PASS" "$_SS_SECRET" "$_LK_KEY" "$_LK_SECRET" "$_CTR_SUFFIX"
            changed=true
        elif [ "${feat_was[$f]}" -eq 1 ] && [ "${feat_now[$f]}" -eq 0 ]; then
            echo -e "\n   ${WARNING}- Removing: $f${RESET}"
            _feat_remove "$stack_dir" "$f"
            changed=true
        fi
    done

    if [ "$changed" = true ]; then
        echo -e "\n${INFO}Applying changes...${RESET}"
        # Validate compose before attempting restart
        if ! (cd "$stack_dir" && docker compose config -q 2>/dev/null); then
            echo -e "   ${ERROR}✗ compose.yaml is corrupt — cannot restart stack${RESET}"
            echo -e "   ${WARNING}Run: Reconfigure → Add/remove bridges to repair${RESET}"
            return 1
        fi
        (
            cd "$stack_dir" || exit 1
            echo -e "   ${INFO}Stopping stack...${RESET}"
            docker compose down --remove-orphans --timeout 30
            echo -e "   ${INFO}Starting stack...${RESET}"
            docker compose up -d
        ) 2>&1 | sed 's/^/   /'
        echo -e "   ${SUCCESS}✓ Stack updated${RESET}"
        parse_stack_configuration "$stack_dir"
    else
        echo -e "\n   ${INFO}No changes made${RESET}"
    fi
}

# ── Internal: add one feature ─────────────────────────────────────────────────
_feat_add() {
    local stack_dir="$1" feature="$2" net="$3" synapse_ctr="$4"
    local db_user="$5" db_pass="$6" ss_secret="$7" lk_key="$8" lk_secret="$9"
    local sfx="${10:-}"   # container name suffix e.g. "-2"
    local compose="$stack_dir/compose.yaml"

    case "$feature" in
        "Element Admin")
            if grep -q "container_name: element-admin" "$compose" 2>/dev/null; then
                echo -e "      ${INFO}already in compose${RESET}"; return
            fi
            _compose_insert "$compose" "
  # Element Admin Web Interface
  element-admin:
    container_name: element-admin${sfx}
    image: oci.element.io/element-admin:latest
    restart: unless-stopped
    ports: [ \"${PORT_ELEMENT_ADMIN}:8080\" ]
    environment:
      SERVER_NAME: '${CURRENT_DOMAIN}'
    networks: [${net}]
    labels:
      com.docker.compose.project: \"matrix-stack\""
            echo -e "      ${SUCCESS}✓ element-admin added to compose.yaml${RESET}"
            # MAS OAuth client
            if [ -f "$stack_dir/mas/config.yaml" ] && \
               ! grep -q "element-admin-client" "$stack_dir/mas/config.yaml" 2>/dev/null; then
                printf '\n  - client_id: "element-admin-client"\n    client_auth_method: none\n    client_uri: "https://%s.%s/"\n    redirect_uris:\n      - "https://%s.%s/"\n' \
                    "$CURRENT_SUB_ELEMENT_ADMIN" "$CURRENT_DOMAIN" \
                    "$CURRENT_SUB_ELEMENT_ADMIN" "$CURRENT_DOMAIN" \
                    >> "$stack_dir/mas/config.yaml"
                echo -e "      ${SUCCESS}✓ MAS OAuth client registered${RESET}"
            fi
            ;;

        "Element Call")
            if grep -q "container_name: element-call" "$compose" 2>/dev/null; then
                echo -e "      ${INFO}already in compose${RESET}"; return
            fi
            mkdir -p "$stack_dir/element-call"
            cat > "$stack_dir/element-call/config.json" << ECJSONEOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${CURRENT_SUB_MATRIX}.${CURRENT_DOMAIN}",
            "server_name": "${CURRENT_DOMAIN}"
        },
        "m.authentication": {
            "issuer": "https://${CURRENT_SUB_MAS}.${CURRENT_DOMAIN}/",
            "account": "https://${CURRENT_SUB_MAS}.${CURRENT_DOMAIN}/account"
        }
    },
    "livekit_service_url": "https://${CURRENT_SUB_CALL}.${CURRENT_DOMAIN}",
    "livekit_jwt_service_url": "https://${CURRENT_SUB_CALL}.${CURRENT_DOMAIN}"
}
ECJSONEOF
            _compose_insert "$compose" "
  # Element Call - Standalone WebRTC Video Conferencing UI
  element-call:
    container_name: element-call${sfx}
    image: ghcr.io/element-hq/element-call:latest
    restart: unless-stopped
    volumes: [ \"./element-call/config.json:/app/config.json:ro\" ]
    ports: [ \"${PORT_ELEMENT_CALL}:8080\" ]
    networks: [${net}]
    labels:
      com.docker.compose.project: \"matrix-stack\""
            echo -e "      ${SUCCESS}✓ element-call added to compose.yaml${RESET}"
            # lk-jwt-service
            if ! grep -q "container_name: livekit-jwt" "$compose" 2>/dev/null; then
                _compose_insert "$compose" "
  # LiveKit JWT Service - Issues tokens for Element Call
  livekit-jwt:
    container_name: livekit-jwt${sfx}
    image: ghcr.io/element-hq/lk-jwt-service:latest
    restart: unless-stopped
    ports: [ \"8089:8080\" ]
    environment:
      LK_JWT_PORT: \"8080\"
      LIVEKIT_URL: wss://${CURRENT_SUB_LIVEKIT}.${CURRENT_DOMAIN}
      LIVEKIT_KEY: \"${lk_key}\"
      LIVEKIT_SECRET: \"${lk_secret}\"
    networks: [${net}]
    labels:
      com.docker.compose.project: \"matrix-stack\""
                echo -e "      ${SUCCESS}✓ livekit-jwt added to compose.yaml${RESET}"
            fi
            # MAS OAuth client
            if [ -f "$stack_dir/mas/config.yaml" ] && \
               ! grep -q "element-call-client" "$stack_dir/mas/config.yaml" 2>/dev/null; then
                printf '\n  - client_id: "element-call-client"\n    client_auth_method: none\n    client_uri: "https://%s.%s/"\n    redirect_uris:\n      - "https://%s.%s/"\n' \
                    "$CURRENT_SUB_CALL" "$CURRENT_DOMAIN" \
                    "$CURRENT_SUB_CALL" "$CURRENT_DOMAIN" \
                    >> "$stack_dir/mas/config.yaml"
                echo -e "      ${SUCCESS}✓ MAS OAuth client registered${RESET}"
            fi
            ;;

        "Synapse Admin")
            if grep -q "container_name: synapse-admin" "$compose" 2>/dev/null; then
                echo -e "      ${INFO}already in compose${RESET}"; return
            fi
            _compose_insert "$compose" "
  # Synapse Admin Web Interface
  synapse-admin:
    container_name: synapse-admin${sfx}
    image: awesometechnologies/synapse-admin:latest
    restart: unless-stopped
    ports: [ \"${PORT_SYNAPSE_ADMIN}:80\" ]
    networks: [${net}]
    labels:
      com.docker.compose.project: \"matrix-stack\""
            echo -e "      ${SUCCESS}✓ synapse-admin added to compose.yaml${RESET}"
            ;;

        "Media Repo")
            if grep -q "container_name: matrix-media-repo" "$compose" 2>/dev/null; then
                echo -e "      ${INFO}already in compose${RESET}"; return
            fi
            mkdir -p "$stack_dir/media-repo/data"
            cat > "$stack_dir/media-repo/config.yaml" << MMCFGEOF
# Matrix Media Repo config - generated by reconfigure
repo:
  bind_address: "0.0.0.0"
  port: 8000
  name: "matrix-stack-media-repo"

homeservers:
  - name: "${CURRENT_DOMAIN}"
    csApi: "https://${CURRENT_SUB_MATRIX}.${CURRENT_DOMAIN}"
    adminApiKind: "synapse"

database:
  postgres: "postgresql://${db_user}:${db_pass}@postgres/media_repo?sslmode=disable"

admins:
  - "@admin:${CURRENT_DOMAIN}"

datastores:
  - type: "file"
    id: "localfs"
    forKinds: [ "all" ]
    opts:
      path: "/data"
MMCFGEOF
            _compose_insert "$compose" "
  # Matrix Media Repository - Advanced media server
  matrix-media-repo:
    container_name: matrix-media-repo${sfx}
    image: turt2live/matrix-media-repo:latest
    restart: unless-stopped
    volumes:
      - ./media-repo/config.yaml:/config/media-repo.yaml:ro
      - ./media-repo/data:/data
    ports: [ \"${PORT_MEDIA_REPO}:8000\" ]
    environment:
      REPO_CONFIG: /config/media-repo.yaml
    depends_on:
      postgres:
        condition: service_healthy
      synapse:
        condition: service_healthy
    networks: [${net}]
    labels:
      com.docker.compose.project: \"matrix-stack\""
            echo -e "      ${SUCCESS}✓ matrix-media-repo added to compose.yaml${RESET}"
            ;;

        "Sliding Sync")
            if grep -q "container_name: sliding-sync" "$compose" 2>/dev/null; then
                echo -e "      ${INFO}already in compose${RESET}"; return
            fi
            # Create syncv3 DB
            local _pgc
            _pgc=$(docker ps --format "{{.Names}}" 2>/dev/null \
                | grep -E "postgres|synapse-db" | head -1)
            _pgc="${_pgc:-synapse-db}"
            docker exec "$_pgc" psql -U "$db_user" -tc \
                "SELECT 1 FROM pg_database WHERE datname='syncv3'" 2>/dev/null \
                | grep -q 1 || \
            docker exec "$_pgc" psql -U "$db_user" \
                -c "CREATE DATABASE syncv3 OWNER $db_user;" >/dev/null 2>&1 || true

            _compose_insert "$compose" "
  # Sliding Sync Proxy - For modern Matrix clients
  sliding-sync:
    container_name: sliding-sync${sfx}
    image: ghcr.io/matrix-org/sliding-sync:latest
    restart: unless-stopped
    environment:
      SYNCV3_SERVER: http://${synapse_ctr}:8008
      SYNCV3_SECRET: ${ss_secret}
      SYNCV3_BINDADDR: 0.0.0.0:${PORT_SLIDING_SYNC}
      SYNCV3_DB: postgresql://${db_user}:${db_pass}@postgres/syncv3?sslmode=disable
    ports: [ \"${PORT_SLIDING_SYNC}:${PORT_SLIDING_SYNC}\" ]
    depends_on:
      postgres:
        condition: service_healthy
      synapse:
        condition: service_healthy
    networks: [${net}]
    labels:
      com.docker.compose.project: \"matrix-stack\""
            echo -e "      ${SUCCESS}✓ sliding-sync added to compose.yaml${RESET}"
            # Patch element-web config.json
            if [ -f "$stack_dir/element-web/config.json" ] && \
               ! grep -q "msc3575" "$stack_dir/element-web/config.json" 2>/dev/null; then
                python3 - "$stack_dir/element-web/config.json" \
                    "${CURRENT_SUB_SLIDING_SYNC}" "${CURRENT_DOMAIN}" 2>/dev/null << 'PYEOF' || true
import sys, json
path, sub, domain = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: cfg = json.load(f)
cfg.setdefault("default_server_config", {}).setdefault(
    "org.matrix.msc3575.proxy", {})["url"] = f"https://{sub}.{domain}"
with open(path, "w") as f: json.dump(cfg, f, indent=4)
PYEOF
                echo -e "      ${SUCCESS}✓ element-web config updated with Sliding Sync URL${RESET}"
            fi
            ;;
    esac
}

# ── Internal: remove one feature ─────────────────────────────────────────────
_feat_remove() {
    local stack_dir="$1" feature="$2"
    local compose="$stack_dir/compose.yaml"

    # Detect suffix from existing compose
    local sfx=""
    if grep -q "container_name: synapse-[0-9]" "$compose" 2>/dev/null; then
        sfx=$(grep "container_name: synapse-" "$compose" \
            | sed 's/.*container_name: synapse//' | grep -o '^-[0-9]*')
    fi

    local ctr=""
    case "$feature" in
        "Element Admin")  ctr="element-admin${sfx}" ;;
        "Element Call")   ctr="element-call${sfx}" ;;
        "Synapse Admin")  ctr="synapse-admin${sfx}" ;;
        "Media Repo")     ctr="matrix-media-repo${sfx}" ;;
        "Sliding Sync")   ctr="sliding-sync${sfx}" ;;
    esac
    [ -z "$ctr" ] && return
    docker stop "$ctr" >/dev/null 2>&1 || true
    docker rm   "$ctr" >/dev/null 2>&1 || true
    _compose_remove_svc "$compose" "${ctr}"
    echo -e "      ${SUCCESS}✓ $feature removed from compose.yaml${RESET}"
    if [ "$feature" = "Element Call" ]; then
        local jwt_ctr="livekit-jwt${sfx}"
        docker stop "$jwt_ctr" >/dev/null 2>&1 || true
        docker rm   "$jwt_ctr" >/dev/null 2>&1 || true
        _compose_remove_svc "$compose" "${jwt_ctr}"
        echo -e "      ${SUCCESS}✓ livekit-jwt removed from compose.yaml${RESET}"
    fi
}

# ── Compose helpers ───────────────────────────────────────────────────────────

_compose_insert() {
    # Insert a service block before the `networks:` top-level key.
    # Snippet is written to a tmpfile first to avoid shell quoting issues.
    local compose="$1"
    local snippet="$2"
    [ -f "$compose" ] || return 1
    local _tmpf
    _tmpf=$(mktemp)
    printf '%s\n' "$snippet" > "$_tmpf"
    python3 - "$compose" "$_tmpf" << 'PYEOF'
import sys
path, snippet_file = sys.argv[1], sys.argv[2]
with open(snippet_file) as sf:
    snippet = sf.read().rstrip('\n')
with open(path) as f:
    content = f.read()
import re
m = list(re.finditer(r'\nnetworks:', content))
if m:
    idx = m[-1].start()
    content = content[:idx] + '\n' + snippet + '\n' + content[idx:]
else:
    content = content.rstrip() + '\n' + snippet + '\n'
with open(path, 'w') as f:
    f.write(content)
PYEOF
    rm -f "$_tmpf"
}

_compose_remove_svc() {
    # Remove a named service block (and its preceding comment line) from compose.yaml
    local compose="$1"
    local svc="$2"
    [ -f "$compose" ] || return 0
    python3 - "$compose" "$svc" 2>/dev/null << 'PYEOF'
import sys
path, svc = sys.argv[1], sys.argv[2]
with open(path) as f:
    lines = f.readlines()
out = []
i = 0
while i < len(lines):
    line = lines[i].rstrip('\n')
    # Detect leading comment for this service
    import re
    if re.match(r'^  # ', line) and (i+1) < len(lines) and \
       re.match(r'^  ' + re.escape(svc) + r':', lines[i+1]):
        i += 1  # skip comment, fall through to service detection
    # Detect service start
    if re.match(r'^  ' + re.escape(svc) + r':', lines[i].rstrip('\n')):
        i += 1
        # Skip all 4-space-indented lines of this service
        while i < len(lines):
            l = lines[i].rstrip('\n')
            if l == '' or re.match(r'^    ', l):
                i += 1
            else:
                break
        # Consume one trailing blank line
        if i < len(lines) and lines[i].rstrip('\n') == '':
            i += 1
        continue
    out.append(lines[i])
    i += 1
with open(path, 'w') as f:
    f.writelines(out)
PYEOF
}

manage_bridges() {
    local stack_dir="$1"
    local DOMAIN="$CURRENT_DOMAIN"

    # DB credentials
    local DB_USER DB_PASS
    DB_USER=$(grep -A 10 "^database:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null \
        | grep "user:" | awk '{print $2}' | tr -d '"' | head -1)
    DB_PASS=$(grep -A 10 "^database:" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null \
        | grep "password:" | awk '{print $2}' | tr -d '"' | head -1)
    DB_USER="${DB_USER:-synapse}"
    if [ -z "$DB_PASS" ]; then
        echo -ne "   DB password: ${WARNING}"
        read -rs DB_PASS; echo -e "${RESET}"
    fi

    # Admin user
    local ADMIN_USER
    ADMIN_USER=$(grep "admin" "$stack_dir/synapse/homeserver.yaml" 2>/dev/null \
        | grep "@" | head -1 | grep -oP '@\K[^:]+' || true)
    ADMIN_USER="${ADMIN_USER:-admin}"

    # Postgres container
    local PG_CONTAINER
    PG_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null \
        | grep -E "postgres|synapse-db" | head -1)
    PG_CONTAINER="${PG_CONTAINER:-synapse-db}"

    # Synapse container + network — read from this stack's compose, not global docker ps
    local SYNAPSE_CONTAINER MATRIX_NETWORK
    SYNAPSE_CONTAINER=$(grep "container_name: synapse" "$COMPOSE_FILE" 2>/dev/null \
        | grep -v "synapse-db\|synapse-admin" | head -1 | awk '{print $2}')
    SYNAPSE_CONTAINER="${SYNAPSE_CONTAINER:-synapse}"
    MATRIX_NETWORK=$(grep "container_name: synapse" "$COMPOSE_FILE" 2>/dev/null \
        | grep -v "synapse-db\|synapse-admin" | head -1 | awk '{print $2}' | xargs -I{} \
        docker inspect {} --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null | head -1)
    # Fallback: read from compose networks section
    [ -z "$MATRIX_NETWORK" ] && MATRIX_NETWORK=$(grep "networks: \[" "$COMPOSE_FILE" 2>/dev/null \
        | grep -oP 'matrix-net[^\]]*' | head -1 | tr -d ' ')
    MATRIX_NETWORK="${MATRIX_NETWORK:-matrix-net}"

    # Compose file + suffix detection
    local COMPOSE_FILE=""
    for cf in "$stack_dir/compose.yaml" "$stack_dir/docker-compose.yml" \
              "$stack_dir/docker-compose.yaml"; do
        [ -f "$cf" ] && COMPOSE_FILE="$cf" && break
    done

    local EXISTING_SUFFIX=""
    if grep -q "container_name: synapse-[0-9]" "$COMPOSE_FILE" 2>/dev/null; then
        EXISTING_SUFFIX=$(grep "container_name: synapse-" "$COMPOSE_FILE" \
            | sed 's/.*synapse//' | grep -o '^-[0-9]*')
    fi

    # Build current bridge status (lowercase keys)
    declare -A bwas
    for b in discord telegram whatsapp signal slack meta; do bwas[$b]=0; done
    for b in "${CURRENT_BRIDGES[@]}"; do bwas[$b]=1; done

    # Whiptail — bridge color scheme, pre-check installed
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
    local BRIDGE_SEL
    BRIDGE_SEL=$(whiptail --title " Manage Matrix Bridges " \
        --checklist "Toggle bridges (SPACE to toggle, ENTER to confirm):" \
        20 78 6 \
        "discord"  "Discord   -- Connect to Discord servers"              "$([ ${bwas[discord]}  -eq 1 ] && echo ON || echo OFF)" \
        "telegram" "Telegram  -- Connect to Telegram chats"               "$([ ${bwas[telegram]} -eq 1 ] && echo ON || echo OFF)" \
        "whatsapp" "WhatsApp  -- Connect to WhatsApp (requires phone)"    "$([ ${bwas[whatsapp]} -eq 1 ] && echo ON || echo OFF)" \
        "signal"   "Signal    -- Connect to Signal (requires phone)"      "$([ ${bwas[signal]}   -eq 1 ] && echo ON || echo OFF)" \
        "slack"    "Slack     -- Connect to Slack workspaces"             "$([ ${bwas[slack]}    -eq 1 ] && echo ON || echo OFF)" \
        "meta"     "Meta      -- Connect to Facebook Messenger/Instagram" "$([ ${bwas[meta]}     -eq 1 ] && echo ON || echo OFF)" \
        3>&1 1>&2 2>&3)
    local EX=$?
    unset NEWT_COLORS
    [ $EX -ne 0 ] && echo -e "\n   ${INFO}Bridge management cancelled${RESET}" && return

    declare -A bnow
    for b in discord telegram whatsapp signal slack meta; do bnow[$b]=0; done
    for b in $(echo "$BRIDGE_SEL" | tr -d '"'); do bnow[$b]=1; done

    local TO_ADD=() TO_REMOVE=()
    for b in discord telegram whatsapp signal slack meta; do
        [ "${bwas[$b]}" -eq 0 ] && [ "${bnow[$b]}" -eq 1 ] && TO_ADD+=("$b")
        [ "${bwas[$b]}" -eq 1 ] && [ "${bnow[$b]}" -eq 0 ] && TO_REMOVE+=("$b")
    done

    [ ${#TO_ADD[@]} -eq 0 ] && [ ${#TO_REMOVE[@]} -eq 0 ] && \
        echo -e "\n   ${INFO}No changes made${RESET}" && return

    # ── Remove bridges ──────────────────────────────────────────────────────
    local NEED_SYNAPSE_RESTART=0
    if [ ${#TO_REMOVE[@]} -gt 0 ]; then
        echo -e "\n${ACCENT}>> Removing bridges...${RESET}"
        for bridge in "${TO_REMOVE[@]}"; do
            local ctr="matrix-bridge-${bridge}${EXISTING_SUFFIX}"
            echo -e "   ${WARNING}- Removing: $bridge${RESET}"
            docker stop "$ctr" >/dev/null 2>&1 || true
            docker rm   "$ctr" >/dev/null 2>&1 || true
            # Remove service from compose
            if [ -n "$COMPOSE_FILE" ]; then
                _compose_remove_svc "$COMPOSE_FILE" "mautrix-${bridge}"
            fi
            # Remove appservice registration
            local HS_YAML="$stack_dir/synapse/homeserver.yaml"
            sed -i "\|/data/bridges/${bridge}/registration.yaml|d" "$HS_YAML" 2>/dev/null || true
            echo -e "      ${SUCCESS}✓ $bridge bridge removed${RESET}"
            NEED_SYNAPSE_RESTART=1
        done
    fi

    # ── Add bridges ─────────────────────────────────────────────────────────
    if [ ${#TO_ADD[@]} -gt 0 ]; then
        echo -e "\n${ACCENT}>> Installing bridge configs...${RESET}"
        mkdir -p "$stack_dir/bridges"

        local NEW_BRIDGES=()
        for bridge in "${TO_ADD[@]}"; do
            # Skip if already installed on disk
            if [ -d "$stack_dir/bridges/$bridge" ] && \
               [ -f "$stack_dir/bridges/$bridge/registration.yaml" ]; then
                echo -e "   ${WARNING}⚠  $bridge already configured — re-registering${RESET}"
            fi

            echo -e "   ${INFO}Generating $bridge config...${RESET}"
            mkdir -p "$stack_dir/bridges/$bridge"
            rm -f "$stack_dir/bridges/$bridge/registration.yaml"

            local _BINARY="/usr/bin/mautrix-$bridge"

            # Step 1: extract example config
            if [ ! -f "$stack_dir/bridges/$bridge/config.yaml" ]; then
                if [ "$bridge" = "telegram" ]; then
                    docker run --rm \
                        --entrypoint /bin/sh \
                        -v "$stack_dir/bridges/$bridge:/data" \
                        "dock.mau.dev/mautrix/telegram:latest" \
                        -c "python -m mautrix_telegram -g -c /data/config.yaml --no-update 2>/dev/null; \
                            [ -f /data/config.yaml ] || cp /opt/mautrix-telegram/example-config.yaml /data/config.yaml" \
                        >/dev/null 2>&1 || true
                else
                    docker run --rm \
                        --entrypoint /bin/sh \
                        -v "$stack_dir/bridges/$bridge:/data" \
                        "dock.mau.dev/mautrix/$bridge:latest" \
                        -c "cp /opt/mautrix-$bridge/example-config.yaml /data/config.yaml" \
                        >/dev/null 2>&1 || true
                fi
            fi

            # Step 2: patch minimum required fields
            if [ -f "$stack_dir/bridges/$bridge/config.yaml" ]; then
                sed -i "s|domain: example.com|domain: $DOMAIN|g" \
                    "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
                sed -i "s|address: https://matrix.example.com|address: http://$SYNAPSE_CONTAINER:8008|g" \
                    "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
                sed -i "s|address: https://example.com|address: http://$SYNAPSE_CONTAINER:8008|g" \
                    "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
            fi

            # Step 3: generate registration.yaml
            if [ -f "$stack_dir/bridges/$bridge/config.yaml" ]; then
                if [ "$bridge" = "telegram" ]; then
                    docker run --rm \
                        -v "$stack_dir/bridges/$bridge:/data" \
                        "dock.mau.dev/mautrix/telegram:latest" \
                        python -m mautrix_telegram -g -c /data/config.yaml -r /data/registration.yaml \
                        >/dev/null 2>&1 || true
                else
                    docker run --rm \
                        --entrypoint "$_BINARY" \
                        -v "$stack_dir/bridges/$bridge:/data" \
                        "dock.mau.dev/mautrix/$bridge:latest" \
                        -g -c /data/config.yaml -r /data/registration.yaml \
                        >/dev/null 2>&1 || true
                fi
            fi

            # Step 4: patch DB, permissions, appservice address
            local _BRIDGE_DB="mautrix_${bridge}"
            # Create DB
            docker exec "$PG_CONTAINER" psql -U "$DB_USER" -tc \
                "SELECT 1 FROM pg_database WHERE datname='$_BRIDGE_DB'" 2>/dev/null \
                | grep -q 1 || \
            docker exec "$PG_CONTAINER" psql -U "$DB_USER" \
                -c "CREATE DATABASE $_BRIDGE_DB OWNER $DB_USER;" >/dev/null 2>&1 || true

            if [ -f "$stack_dir/bridges/$bridge/config.yaml" ]; then
                sed -i \
                    -e "s|uri: postgres://user:password@host/db|uri: postgresql://$DB_USER:$DB_PASS@$PG_CONTAINER/$_BRIDGE_DB?sslmode=disable|g" \
                    -e "s|uri: postgresql://user:password@host/db|uri: postgresql://$DB_USER:$DB_PASS@$PG_CONTAINER/$_BRIDGE_DB?sslmode=disable|g" \
                    "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
                grep -q "postgresql://$DB_USER" "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || \
                    sed -i "/^        uri:/c\\        uri: postgresql://$DB_USER:$DB_PASS@$PG_CONTAINER/$_BRIDGE_DB?sslmode=disable" \
                        "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
                sed -i \
                    -e "s|\"example.com\": user|\"$DOMAIN\": user|g" \
                    -e "s|\"@admin:example.com\": admin|\"@$ADMIN_USER:$DOMAIN\": admin|g" \
                    "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
                sed -i "s|address: http://localhost:|address: http://mautrix-$bridge:|g" \
                    "$stack_dir/bridges/$bridge/config.yaml" 2>/dev/null || true
            fi
            if [ -f "$stack_dir/bridges/$bridge/registration.yaml" ]; then
                sed -i "s|url: http://localhost:|url: http://mautrix-$bridge:|g" \
                    "$stack_dir/bridges/$bridge/registration.yaml" 2>/dev/null || true
            fi

            local BCAP
            BCAP="$(tr '[:lower:]' '[:upper:]' <<< ${bridge:0:1})${bridge:1}"
            echo -e "   ${SUCCESS}✓ $BCAP bridge configured${RESET}"
            NEW_BRIDGES+=("$bridge")
        done

        # ── Update compose ──────────────────────────────────────────────
        if [ ${#NEW_BRIDGES[@]} -gt 0 ]; then
            echo -e "\n${ACCENT}>> Updating Docker Compose...${RESET}"
            if [ -z "$COMPOSE_FILE" ]; then
                echo -e "   ${WARNING}⚠  No compose file found${RESET}"
            else
                for bridge in "${NEW_BRIDGES[@]}"; do
                    if grep -q "mautrix-${bridge}:" "$COMPOSE_FILE" 2>/dev/null || \
                       grep -q "container_name: matrix-bridge-${bridge}" "$COMPOSE_FILE" 2>/dev/null; then
                        # Already present — check if compose is valid; if corrupt, repair it
                        if _validate_compose "$(dirname "$COMPOSE_FILE")" 2>/dev/null; then
                            echo -e "   ${INFO}⚠  $bridge already in compose -- skipping${RESET}"
                            continue
                        else
                            echo -e "   ${WARNING}⚠  $bridge in compose but compose is corrupt — repairing...${RESET}"
                            _compose_remove_svc "$COMPOSE_FILE" "mautrix-${bridge}"
                            # fall through to re-insert below
                        fi
                    fi
                    _compose_insert "$COMPOSE_FILE" "
  # mautrix-${bridge} Bridge
  mautrix-${bridge}:
    container_name: matrix-bridge-${bridge}${EXISTING_SUFFIX}
    image: dock.mau.dev/mautrix/${bridge}:latest
    restart: unless-stopped
    volumes:
      - ./bridges/${bridge}:/data
    depends_on:
      synapse:
        condition: service_healthy
      postgres:
        condition: service_healthy
    networks: [ ${MATRIX_NETWORK} ]
    labels:
      com.docker.compose.project: \"matrix-stack\""
                    echo -e "   ${SUCCESS}✓ $bridge added to $(basename "$COMPOSE_FILE")${RESET}"
                done
            fi

            # ── Register with Synapse ───────────────────────────────────
            echo -e "\n${ACCENT}>> Registering bridges with Synapse...${RESET}"
            local HS_YAML="$stack_dir/synapse/homeserver.yaml"
            for bridge in "${NEW_BRIDGES[@]}"; do
                local REG_FILE="/data/bridges/${bridge}/registration.yaml"
                if grep -q "$REG_FILE" "$HS_YAML" 2>/dev/null; then
                    echo -e "   ${INFO}i  $bridge already registered${RESET}"
                else
                    if ! grep -q "^app_service_config_files:" "$HS_YAML" 2>/dev/null; then
                        printf "\napp_service_config_files:\n  - %s\n" "$REG_FILE" >> "$HS_YAML"
                    else
                        sed -i "/^app_service_config_files:/a\\  - $REG_FILE" "$HS_YAML"
                    fi
                    echo -e "   ${SUCCESS}✓ $bridge registered in homeserver.yaml${RESET}"
                    NEED_SYNAPSE_RESTART=$((NEED_SYNAPSE_RESTART + 1))
                fi
            done

            # ── Ensure bridges/ mounted in Synapse ──────────────────────
            if [ -n "$COMPOSE_FILE" ]; then
                if ! grep -q "bridges:/data/bridges" "$COMPOSE_FILE" 2>/dev/null; then
                    sed -i 's|      - ./synapse:/data|      - ./synapse:/data\n      - ./bridges:/data/bridges|' \
                        "$COMPOSE_FILE" 2>/dev/null || true
                    grep -q "bridges:/data/bridges" "$COMPOSE_FILE" 2>/dev/null && \
                        echo -e "   ${SUCCESS}✓ bridges/ volume mount added to Synapse${RESET}" || \
                        echo -e "   ${WARNING}⚠  Add '- ./bridges:/data/bridges' under synapse volumes manually${RESET}"
                else
                    echo -e "   ${INFO}i  bridges/ already mounted in Synapse${RESET}"
                fi
            fi

            # ── Start new bridge containers ─────────────────────────────
            if [ -n "$COMPOSE_FILE" ]; then
                echo -e "\n${ACCENT}>> Starting new bridge containers...${RESET}"
                cd "$stack_dir" && docker compose -f "$(basename "$COMPOSE_FILE")" up -d 2>&1 \
                    | grep -E "Creating|Starting|error|Error" | sed 's/^/   /' || true
            fi
        fi
    fi

    # ── Restart Synapse if registrations changed ────────────────────────────
    if [ "$NEED_SYNAPSE_RESTART" -gt 0 ] && [ -n "$COMPOSE_FILE" ]; then
        echo -e "\n${ACCENT}>> Restarting Synapse to apply bridge registrations...${RESET}"
        cd "$stack_dir" && docker compose -f "$(basename "$COMPOSE_FILE")" restart synapse 2>&1 \
            | sed 's/^/   /' || true
        echo -e "   ${SUCCESS}✓ Synapse restarted${RESET}"
    fi

    parse_stack_configuration "$stack_dir"

    if [ ${#TO_ADD[@]} -gt 0 ]; then
        echo -e "\n${SUCCESS}✓ Bridges added successfully${RESET}"
        echo -e "\n${ACCENT}Activation steps:${RESET}"
        echo -e "   ${INFO}1. Open Element Web and DM the bridge bot${RESET}"
        echo -e "   ${INFO}2. Wait 1-2 min for the bot to appear if needed${RESET}\n"
        for bridge in "${TO_ADD[@]}"; do
            case $bridge in
                discord)  echo -e "   ${SUCCESS}>${RESET} Discord:   DM ${WARNING}@discordbot:$DOMAIN${RESET}   -> login" ;;
                telegram) echo -e "   ${SUCCESS}>${RESET} Telegram:  DM ${WARNING}@telegrambot:$DOMAIN${RESET}  -> login" ;;
                whatsapp) echo -e "   ${SUCCESS}>${RESET} WhatsApp:  DM ${WARNING}@whatsappbot:$DOMAIN${RESET}  -> login -> scan QR" ;;
                signal)   echo -e "   ${SUCCESS}>${RESET} Signal:    DM ${WARNING}@signalbot:$DOMAIN${RESET}    -> link -> scan QR" ;;
                slack)    echo -e "   ${SUCCESS}>${RESET} Slack:     DM ${WARNING}@slackbot:$DOMAIN${RESET}     -> login" ;;
                meta)     echo -e "   ${SUCCESS}>${RESET} Meta:      DM ${WARNING}@instagrambot:$DOMAIN${RESET} or ${WARNING}@facebookbot:$DOMAIN${RESET} -> login" ;;
            esac
        done
    fi
    [ ${#TO_REMOVE[@]} -gt 0 ] && echo -e "\n${SUCCESS}✓ Bridges removed successfully${RESET}"
}

manage_domain() {
    local stack_dir="$1"

    # Ensure subdomains populated
    CURRENT_SUB_MATRIX="${CURRENT_SUB_MATRIX:-matrix}"
    CURRENT_SUB_MAS="${CURRENT_SUB_MAS:-auth}"
    CURRENT_SUB_ELEMENT="${CURRENT_SUB_ELEMENT:-element}"
    CURRENT_SUB_LIVEKIT="${CURRENT_SUB_LIVEKIT:-livekit}"
    CURRENT_SUB_CALL="${CURRENT_SUB_CALL:-call}"
    CURRENT_SUB_SLIDING_SYNC="${CURRENT_SUB_SLIDING_SYNC:-sync}"
    CURRENT_SUB_ELEMENT_ADMIN="${CURRENT_SUB_ELEMENT_ADMIN:-admin}"
    CURRENT_SUB_SYNAPSE_ADMIN="${CURRENT_SUB_SYNAPSE_ADMIN:-admin}"
    CURRENT_SUB_MEDIA_REPO="${CURRENT_SUB_MEDIA_REPO:-media}"

    echo -e "\n${ACCENT}>> Domain Management${RESET}"
    echo -e "   ${WARNING}NOTE: After changing domains, update your reverse proxy and DNS records!${RESET}\n"

    # ── Base domain ────────────────────────────────────────────────────────
    echo -ne "Base Domain [${CURRENT_DOMAIN}]: "; echo -ne "${WARNING}"
    read -r _new_domain
    if [ -z "$_new_domain" ]; then
        _new_domain="$CURRENT_DOMAIN"
        echo -ne "\033[1A\033[K"
        echo -e "Base Domain [${CURRENT_DOMAIN}]: ${WARNING}${_new_domain}${RESET}"
    else
        echo -ne "${RESET}"
    fi

    # ── Core subdomains (always ask) ───────────────────────────────────────
    echo ""
    echo -ne "Matrix Subdomain [${CURRENT_SUB_MATRIX}]: "; echo -ne "${WARNING}"
    read -r _v
    if [ -z "$_v" ]; then
        _v="$CURRENT_SUB_MATRIX"
        echo -ne "\033[1A\033[K"
        echo -e "Matrix Subdomain [${CURRENT_SUB_MATRIX}]: ${WARNING}${_v}${RESET}"
    else echo -ne "${RESET}"; fi
    local new_sub_matrix="$_v"

    echo ""
    echo -ne "MAS (Auth) Subdomain [${CURRENT_SUB_MAS}]: "; echo -ne "${WARNING}"
    read -r _v
    if [ -z "$_v" ]; then
        _v="$CURRENT_SUB_MAS"
        echo -ne "\033[1A\033[K"
        echo -e "MAS (Auth) Subdomain [${CURRENT_SUB_MAS}]: ${WARNING}${_v}${RESET}"
    else echo -ne "${RESET}"; fi
    local new_sub_mas="$_v"

    echo ""
    echo -ne "Element Web Subdomain [${CURRENT_SUB_ELEMENT}]: "; echo -ne "${WARNING}"
    read -r _v
    if [ -z "$_v" ]; then
        _v="$CURRENT_SUB_ELEMENT"
        echo -ne "\033[1A\033[K"
        echo -e "Element Web Subdomain [${CURRENT_SUB_ELEMENT}]: ${WARNING}${_v}${RESET}"
    else echo -ne "${RESET}"; fi
    local new_sub_element="$_v"

    echo ""
    echo -ne "LiveKit Subdomain [${CURRENT_SUB_LIVEKIT}]: "; echo -ne "${WARNING}"
    read -r _v
    if [ -z "$_v" ]; then
        _v="$CURRENT_SUB_LIVEKIT"
        echo -ne "\033[1A\033[K"
        echo -e "LiveKit Subdomain [${CURRENT_SUB_LIVEKIT}]: ${WARNING}${_v}${RESET}"
    else echo -ne "${RESET}"; fi
    local new_sub_livekit="$_v"

    # ── Optional subdomains — only ask if service is installed ─────────────
    local new_sub_call="$CURRENT_SUB_CALL"
    local new_sub_ea="$CURRENT_SUB_ELEMENT_ADMIN"
    local new_sub_sa="$CURRENT_SUB_SYNAPSE_ADMIN"
    local new_sub_sync="$CURRENT_SUB_SLIDING_SYNC"
    local new_sub_media="$CURRENT_SUB_MEDIA_REPO"

    # Element Call installed?
    if grep -q "container_name: element-call" "$stack_dir/compose.yaml" 2>/dev/null; then
        echo ""
        echo -ne "Element Call Subdomain [${CURRENT_SUB_CALL}]: "; echo -ne "${WARNING}"
        read -r _v
        if [ -z "$_v" ]; then
            _v="$CURRENT_SUB_CALL"
            echo -ne "\033[1A\033[K"
            echo -e "Element Call Subdomain [${CURRENT_SUB_CALL}]: ${WARNING}${_v}${RESET}"
        else echo -ne "${RESET}"; fi
        new_sub_call="$_v"
    fi

    # Element Admin installed?
    if grep -q "container_name: element-admin" "$stack_dir/compose.yaml" 2>/dev/null; then
        echo ""
        echo -ne "Element Admin Subdomain [${CURRENT_SUB_ELEMENT_ADMIN}]: "; echo -ne "${WARNING}"
        read -r _v
        if [ -z "$_v" ]; then
            _v="$CURRENT_SUB_ELEMENT_ADMIN"
            echo -ne "\033[1A\033[K"
            echo -e "Element Admin Subdomain [${CURRENT_SUB_ELEMENT_ADMIN}]: ${WARNING}${_v}${RESET}"
        else echo -ne "${RESET}"; fi
        new_sub_ea="$_v"
    fi

    # Synapse Admin installed?
    if grep -q "container_name: synapse-admin" "$stack_dir/compose.yaml" 2>/dev/null; then
        echo ""
        echo -ne "Synapse Admin Subdomain [${CURRENT_SUB_SYNAPSE_ADMIN}]: "; echo -ne "${WARNING}"
        read -r _v
        if [ -z "$_v" ]; then
            _v="$CURRENT_SUB_SYNAPSE_ADMIN"
            echo -ne "\033[1A\033[K"
            echo -e "Synapse Admin Subdomain [${CURRENT_SUB_SYNAPSE_ADMIN}]: ${WARNING}${_v}${RESET}"
        else echo -ne "${RESET}"; fi
        new_sub_sa="$_v"
    fi

    # Sliding Sync installed?
    if grep -q "container_name: sliding-sync" "$stack_dir/compose.yaml" 2>/dev/null; then
        echo ""
        echo -ne "Sliding Sync Subdomain [${CURRENT_SUB_SLIDING_SYNC}]: "; echo -ne "${WARNING}"
        read -r _v
        if [ -z "$_v" ]; then
            _v="$CURRENT_SUB_SLIDING_SYNC"
            echo -ne "\033[1A\033[K"
            echo -e "Sliding Sync Subdomain [${CURRENT_SUB_SLIDING_SYNC}]: ${WARNING}${_v}${RESET}"
        else echo -ne "${RESET}"; fi
        new_sub_sync="$_v"
    fi

    # Media Repo installed?
    if grep -q "container_name: matrix-media-repo" "$stack_dir/compose.yaml" 2>/dev/null; then
        echo ""
        echo -ne "Media Repo Subdomain [${CURRENT_SUB_MEDIA_REPO}]: "; echo -ne "${WARNING}"
        read -r _v
        if [ -z "$_v" ]; then
            _v="$CURRENT_SUB_MEDIA_REPO"
            echo -ne "\033[1A\033[K"
            echo -e "Media Repo Subdomain [${CURRENT_SUB_MEDIA_REPO}]: ${WARNING}${_v}${RESET}"
        else echo -ne "${RESET}"; fi
        new_sub_media="$_v"
    fi

    # Check if anything changed
    if [ "$_new_domain"    = "$CURRENT_DOMAIN" ] \
    && [ "$new_sub_matrix" = "$CURRENT_SUB_MATRIX" ] \
    && [ "$new_sub_mas"    = "$CURRENT_SUB_MAS" ] \
    && [ "$new_sub_element"= "$CURRENT_SUB_ELEMENT" ] \
    && [ "$new_sub_livekit"= "$CURRENT_SUB_LIVEKIT" ] \
    && [ "$new_sub_call"   = "$CURRENT_SUB_CALL" ] \
    && [ "$new_sub_ea"     = "$CURRENT_SUB_ELEMENT_ADMIN" ] \
    && [ "$new_sub_sa"     = "$CURRENT_SUB_SYNAPSE_ADMIN" ] \
    && [ "$new_sub_sync"   = "$CURRENT_SUB_SLIDING_SYNC" ] \
    && [ "$new_sub_media"  = "$CURRENT_SUB_MEDIA_REPO" ]; then
        echo -e "\n   ${INFO}No changes made${RESET}"
        return
    fi

    echo -e "\n${ACCENT}>> Applying domain/subdomain changes...${RESET}\n"

    # sed helper: replace all old subdomain.domain combos then bare domain
    _dom_sed() {
        local file="$1"
        [ -f "$file" ] || return
        # Replace each old subdomain.olddomain with new subdomain.newdomain
        sed -i "s|${CURRENT_SUB_MATRIX}\.${CURRENT_DOMAIN}|${new_sub_matrix}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_MAS}\.${CURRENT_DOMAIN}|${new_sub_mas}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_ELEMENT}\.${CURRENT_DOMAIN}|${new_sub_element}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_LIVEKIT}\.${CURRENT_DOMAIN}|${new_sub_livekit}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_CALL}\.${CURRENT_DOMAIN}|${new_sub_call}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_SLIDING_SYNC}\.${CURRENT_DOMAIN}|${new_sub_sync}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_ELEMENT_ADMIN}\.${CURRENT_DOMAIN}|${new_sub_ea}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_SYNAPSE_ADMIN}\.${CURRENT_DOMAIN}|${new_sub_sa}.${_new_domain}|g" "$file" 2>/dev/null
        sed -i "s|${CURRENT_SUB_MEDIA_REPO}\.${CURRENT_DOMAIN}|${new_sub_media}.${_new_domain}|g" "$file" 2>/dev/null
        # Replace bare old domain last
        sed -i "s|${CURRENT_DOMAIN}|${_new_domain}|g" "$file" 2>/dev/null
    }

    local restart_ctrs=()

    # homeserver.yaml
    if [ -f "$stack_dir/synapse/homeserver.yaml" ]; then
        _dom_sed "$stack_dir/synapse/homeserver.yaml"
        sed -i "s|^server_name:.*|server_name: ${_new_domain}|" \
            "$stack_dir/synapse/homeserver.yaml" 2>/dev/null || true
        sed -i "s|^public_baseurl:.*|public_baseurl: https://${new_sub_matrix}.${_new_domain}|" \
            "$stack_dir/synapse/homeserver.yaml" 2>/dev/null || true
        echo -e "   ${SUCCESS}✓ synapse/homeserver.yaml${RESET}"
        restart_ctrs+=("synapse")
    fi

    # mas/config.yaml
    if [ -f "$stack_dir/mas/config.yaml" ]; then
        _dom_sed "$stack_dir/mas/config.yaml"
        sed -i "s|^  public_base:.*|  public_base: https://${new_sub_mas}.${_new_domain}/|" \
            "$stack_dir/mas/config.yaml" 2>/dev/null || true
        echo -e "   ${SUCCESS}✓ mas/config.yaml${RESET}"
        restart_ctrs+=("matrix-auth")
    fi

    # element-web/config.json
    if [ -f "$stack_dir/element-web/config.json" ]; then
        _dom_sed "$stack_dir/element-web/config.json"
        echo -e "   ${SUCCESS}✓ element-web/config.json${RESET}"
        restart_ctrs+=("element-web")
    fi

    # element-call/config.json
    if [ -f "$stack_dir/element-call/config.json" ]; then
        _dom_sed "$stack_dir/element-call/config.json"
        echo -e "   ${SUCCESS}✓ element-call/config.json${RESET}"
        restart_ctrs+=("element-call")
    fi

    # livekit/livekit.yaml
    if [ -f "$stack_dir/livekit/livekit.yaml" ]; then
        _dom_sed "$stack_dir/livekit/livekit.yaml"
        echo -e "   ${SUCCESS}✓ livekit/livekit.yaml${RESET}"
        restart_ctrs+=("livekit" "livekit-jwt")
    fi

    # compose.yaml
    if [ -f "$stack_dir/compose.yaml" ]; then
        _dom_sed "$stack_dir/compose.yaml"
        echo -e "   ${SUCCESS}✓ compose.yaml${RESET}"
    fi

    # .deployment-metadata
    if [ -f "$stack_dir/.deployment-metadata" ]; then
        sed -i "s|^DEPLOYMENT_DOMAIN=.*|DEPLOYMENT_DOMAIN=${_new_domain}|" \
            "$stack_dir/.deployment-metadata" 2>/dev/null || true
        _dom_sed "$stack_dir/.deployment-metadata"
        echo -e "   ${SUCCESS}✓ .deployment-metadata${RESET}"
    fi

    # bridge configs
    for bridge_dir in "$stack_dir"/bridges/*/; do
        if [ -d "$bridge_dir" ] && [ -f "$bridge_dir/config.yaml" ]; then
            _dom_sed "$bridge_dir/config.yaml"
            echo -e "   ${SUCCESS}✓ bridges/$(basename "$bridge_dir")/config.yaml${RESET}"
            restart_ctrs+=("matrix-bridge-$(basename "$bridge_dir")")
        fi
    done

    # Restart affected containers
    echo -e "\n${INFO}Restarting affected containers...${RESET}"
    declare -A _seen
    for ctr in "${restart_ctrs[@]}"; do
        [ -n "${_seen[$ctr]+x}" ] && continue; _seen[$ctr]=1
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${ctr}$"; then
            docker restart "$ctr" 2>/dev/null && \
                echo -e "   ${SUCCESS}✓ restarted: $ctr${RESET}" || \
                echo -e "   ${WARNING}⚠  could not restart: $ctr (may not be running)${RESET}"
        fi
    done

    echo -e "\n${WARNING}>> IMPORTANT: Update your reverse proxy and DNS!${RESET}"
    echo -e "   New endpoints:\n"
    printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_matrix}.${_new_domain}"  "(Synapse)"
    printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_mas}.${_new_domain}"     "(MAS / Auth)"
    printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_element}.${_new_domain}" "(Element Web)"
    printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_livekit}.${_new_domain}" "(LiveKit)"
    grep -q "container_name: element-call"   "$stack_dir/compose.yaml" 2>/dev/null && \
        printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_call}.${_new_domain}"    "(Element Call)"
    grep -q "container_name: element-admin"  "$stack_dir/compose.yaml" 2>/dev/null && \
        printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_ea}.${_new_domain}"      "(Element Admin)"
    grep -q "container_name: synapse-admin"  "$stack_dir/compose.yaml" 2>/dev/null && \
        printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_sa}.${_new_domain}"      "(Synapse Admin)"
    grep -q "container_name: sliding-sync"   "$stack_dir/compose.yaml" 2>/dev/null && \
        printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_sync}.${_new_domain}"    "(Sliding Sync)"
    grep -q "container_name: matrix-media-repo" "$stack_dir/compose.yaml" 2>/dev/null && \
        printf "   ${SUCCESS}%-42s${RESET} %s\n" "${new_sub_media}.${_new_domain}"   "(Media Repo)"
    echo ""

    echo -e "${SUCCESS}✓ Domain updated: ${CURRENT_DOMAIN} -> ${_new_domain}${RESET}"

    # Update globals
    CURRENT_DOMAIN="$_new_domain"
    CURRENT_SUB_MATRIX="$new_sub_matrix"
    CURRENT_SUB_MAS="$new_sub_mas"
    CURRENT_SUB_ELEMENT="$new_sub_element"
    CURRENT_SUB_LIVEKIT="$new_sub_livekit"
    CURRENT_SUB_CALL="$new_sub_call"
    CURRENT_SUB_ELEMENT_ADMIN="$new_sub_ea"
    CURRENT_SUB_SYNAPSE_ADMIN="$new_sub_sa"
    CURRENT_SUB_SLIDING_SYNC="$new_sub_sync"
    CURRENT_SUB_MEDIA_REPO="$new_sub_media"
}










get_stack_resources() {
    local stack_path="$1"
    local container_suffix=""

    if [ -f "$stack_path/.deployment-metadata" ]; then
        container_suffix=$(grep "^CONTAINER_SUFFIX=" "$stack_path/.deployment-metadata" \
            | head -1 | cut -d= -f2-)
    fi

    # Fall back to detecting from compose.yaml container names
    if [ -z "$container_suffix" ] && [ -f "$stack_path/compose.yaml" ]; then
        container_suffix=$(grep "container_name: synapse-[0-9]" "$stack_path/compose.yaml" \
            | head -1 | sed 's/.*synapse//' | grep -o -- '-[0-9]*' || true)
    fi

    echo "$container_suffix"
}

get_stack_info() {
    # Get domain and other info from stack metadata or config
    local stack_path="$1"
    local domain=""
    
    # Try metadata first
    if [ -f "$stack_path/.deployment-metadata" ]; then
        source "$stack_path/.deployment-metadata"
        domain="${DEPLOYMENT_DOMAIN:-unknown}"
    fi
    
    # Fall back to homeserver.yaml
    if [ -z "$domain" ] && [ -f "$stack_path/synapse/homeserver.yaml" ]; then
        domain=$(grep "^server_name:" "$stack_path/synapse/homeserver.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"')
    fi
    
    echo "$domain"
}

_delete_single_stack() {
    local stack_path="$1"
    local stack_name=$(basename "$stack_path")
    local suffix=$(get_stack_resources "$stack_path")
    
    echo -e "${ACCENT}Processing: $stack_name${RESET}"
    
    # Get container suffix for resource cleanup
    local container_base_name=$(echo "$stack_name" | tr '[:upper:]' '[:lower:]' | sed 's/-//g')
    
    # Stop and remove containers
    echo -e "   ${INFO}Stopping and removing containers...${RESET}"
    
    # Find and remove containers related to this stack
    local containers_removed=0
    if [ -n "$suffix" ]; then
        # Stack with suffix - remove containers with exact suffix
        for container in $(docker ps -aq --filter "name=$container_base_name" 2>/dev/null); do
            local container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|^/||')
            if [[ "$container_name" == *"$suffix" ]] || [[ "$container_name" == "$container_base_name$suffix"* ]]; then
                docker rm -f "$container" 2>/dev/null && ((containers_removed++))
            fi
        done
    else
        # Stack without suffix - remove non-suffixed containers
        for container in $(docker ps -aq --filter "name=^${container_base_name}" 2>/dev/null); do
            local container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|^/||')
            # Only remove if it doesn't have a suffix (no dash-number at the end)
            if [[ ! "$container_name" =~ -[0-9]+$ ]]; then
                docker rm -f "$container" 2>/dev/null && ((containers_removed++))
            fi
        done
    fi
    
    echo -e "      Removed ${WARNING}$containers_removed${RESET} container(s)"
    
    # Remove volumes
    echo -e "   ${INFO}Removing volumes...${RESET}"
    local volumes_removed=0
    local network_suffix="${suffix:-}"
    
    # Remove volumes associated with this stack
    for volume in $(docker volume ls -q 2>/dev/null); do
        if [[ "$volume" == *"$stack_name"* ]] || [[ "$volume" == *"$container_base_name$network_suffix"* ]]; then
            docker volume rm "$volume" 2>/dev/null && ((volumes_removed++))
        fi
    done
    
    echo -e "      Removed ${WARNING}$volumes_removed${RESET} volume(s)"
    
    # Remove networks
    echo -e "   ${INFO}Removing networks...${RESET}"
    local networks_removed=0
    local network_name="matrix-net${network_suffix}"
    
    if docker network ls --filter "name=$network_name" 2>/dev/null | grep -q "$network_name"; then
        docker network rm "$network_name" 2>/dev/null && ((networks_removed++))
    fi
    
    echo -e "      Removed ${WARNING}$networks_removed${RESET} network(s)"
    
    # Remove directory
    echo -e "   ${INFO}Removing stack directory...${RESET}"
    if rm -rf "$stack_path" 2>/dev/null; then
        echo -e "      Removed directory: ${WARNING}$stack_path${RESET}"
    else
        echo -e "      ${ERROR}✗ Could not remove directory (may need sudo)${RESET}"
    fi
    
    echo -e "   ${SUCCESS}✓ Stack deletion complete${RESET}\n"
}

################################################################################
# PRE-INSTALL MENU FUNCTIONS                                                   #
################################################################################

run_uninstall() {
    draw_header
    echo -e "\n${ERROR}>> Uninstall - Remove Matrix Stack(s)${RESET}"
    echo -e "${WARNING}   ⚠️  This will PERMANENTLY DELETE selected Matrix data!${RESET}\n"

    # Warn if the script itself lives inside a stack directory
    local SCRIPT_REAL
    SCRIPT_REAL=$(readlink -f "$0" 2>/dev/null || echo "$0")
    local SCRIPT_DIR
    SCRIPT_DIR=$(dirname "$SCRIPT_REAL")
    if [[ "$SCRIPT_DIR" == *"matrix-stack"* ]] || [[ "$SCRIPT_DIR" == *"matrix-"* ]]; then
        echo -e "${ERROR}   ⚠️  WARNING: This script is located inside a matrix-stack folder!${RESET}"
        echo -e "${WARNING}   Deleting the stack directory will also delete this script.${RESET}"
        echo -e "${INFO}   Please move it first:${RESET}"
        echo -e "   ${WARNING}mv \"$SCRIPT_REAL\" ~/matrix-stack-deploy.sh${RESET}\n"
        echo -ne "   Have you moved the script, or do you want to continue anyway? [y/N]: "
        read -r SCRIPT_MOVE_CONFIRM
        if [[ ! "$SCRIPT_MOVE_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n   ${SUCCESS}✓ Uninstall cancelled — move the script first then re-run${RESET}"
            sleep 2
            return
        fi
    fi
    
    # Find all stacks systemwide
    echo -e "${INFO}Scanning system for all Matrix stacks...${RESET}\n"
    mapfile -t ALL_STACKS < <(find_all_matrix_stacks)
    
    # Clean up empty elements from mapfile
    ALL_STACKS=( "${ALL_STACKS[@]}" )  # This is a no-op but ensures proper array handling
    # Remove empty strings
    local -a cleaned_stacks=()
    for stack in "${ALL_STACKS[@]}"; do
        if [ -n "$stack" ]; then
            cleaned_stacks+=("$stack")
        fi
    done
    ALL_STACKS=("${cleaned_stacks[@]}")
    
    if [ ${#ALL_STACKS[@]} -eq 0 ]; then
        echo -e "${WARNING}No resources found.${RESET}"
        echo -ne "Press Enter to return to main menu: "
        read -r
        return
    fi
    
    # If only one stack found, proceed directly
    if [ ${#ALL_STACKS[@]} -eq 1 ]; then
        local stack_path="${ALL_STACKS[0]}"
        local domain=$(get_stack_info "$stack_path")
        local suffix=$(get_stack_resources "$stack_path")
        
        echo -e "${INFO}Found 1 installation:${RESET}"
        echo -e "   Path: ${WARNING}$stack_path${RESET}"
        echo -e "   Domain: ${WARNING}$domain${RESET}"
        [ -n "$suffix" ] && echo -e "   Container Suffix: ${WARNING}$suffix${RESET}"
        
        echo -e "\n${WARNING}Are you sure you want to DELETE this stack?${RESET}"
        echo -e "   ${INFO}1)${RESET} ${ERROR}Yes, delete it${RESET}"
        echo -e "   ${INFO}2)${RESET} ${SUCCESS}No, cancel${RESET}"
        echo -ne "\nSelection (1-2): "
        read -r choice
        
        if [[ "$choice" != "1" ]]; then
            echo -e "\n${SUCCESS}✓ Uninstall cancelled${RESET}"
            return
        fi
        
        STACKS_TO_DELETE=("$stack_path")
    else
        # Multiple stacks found - use whiptail for selection
        if ! command -v whiptail &> /dev/null; then
            echo -e "${WARNING}Installing whiptail for selection menu...${RESET}"
            apt-get update -qq && apt-get install -y whiptail -qq > /dev/null 2>&1
        fi
        
        echo -e "${INFO}Found ${#ALL_STACKS[@]} installations. Select which ones to delete:${RESET}"
        echo -e "${INFO}(Use SPACE to toggle, ENTER to confirm)\n${RESET}"
        
        # Apply whiptail color scheme (same as bridge selection)
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
actsellistbox=white,black
scrollbar=white,black
acttitle=white,black
sellistbox=white,black'
        
        # Build whiptail menu items
        local -a whiptail_items=()
        for i in "${!ALL_STACKS[@]}"; do
            local stack_path="${ALL_STACKS[$i]}"
            local domain=$(get_stack_info "$stack_path")
            local suffix=$(get_stack_resources "$stack_path")
            local label="$stack_path | Domain: $domain"
            whiptail_items+=("$i" "$label" "OFF")
            whiptail_items+=("$i" "$label" "OFF")
        done
        
        # Show whiptail checklist
        local selected_indices
        selected_indices=$(NEWT_COLORS='
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
' whiptail --title "Select Stacks to Delete" \
            --checklist "Select installations to DELETE (SPACE to toggle, ENTER to confirm):\n\n⚠️  WARNING: This cannot be undone!" \
            25 100 ${#ALL_STACKS[@]} \
            "${whiptail_items[@]}" \
            3>&1 1>&2 2>&3)
        
        local exit_code=$?
        unset NEWT_COLORS
        
        if [ $exit_code -ne 0 ]; then
            echo -e "\n${SUCCESS}✓ Uninstall cancelled${RESET}"
            return
        fi
        
        # Process selected indices
        declare -a STACKS_TO_DELETE
        for idx in $selected_indices; do
            # Whiptail returns indices as quoted strings, need to handle them properly
            if [[ "$idx" =~ ^[0-9]+$ ]]; then
                STACKS_TO_DELETE+=("${ALL_STACKS[$idx]}")
            fi
        done
        
        if [ ${#STACKS_TO_DELETE[@]} -eq 0 ]; then
            echo -e "\n${INFO}No stacks selected for deletion${RESET}"
            return
        fi
        
        # Show summary and confirmation
        echo -e "\n${ERROR}Will DELETE the following stacks:${RESET}"
        for stack in "${STACKS_TO_DELETE[@]}"; do
            local domain=$(get_stack_info "$stack")
            echo -e "   ${WARNING}• $stack${RESET} (Domain: $domain)"
        done
        
        echo -e "\n${WARNING}Are you absolutely sure?${RESET}"
        echo -e "   ${INFO}1)${RESET} ${ERROR}Yes, delete all selected${RESET}"
        echo -e "   ${INFO}2)${RESET} ${SUCCESS}No, cancel${RESET}"
        echo -ne "\nSelection (1-2): "
        read -r choice
        
        if [[ "$choice" != "1" ]]; then
            echo -e "\n${SUCCESS}✓ Uninstall cancelled${RESET}"
            return
        fi
    fi
    
    # Final confirmation with DELETE keyword
    echo -ne "\n${ERROR}Type 'DELETE' to confirm permanent deletion:${RESET} ${ERROR}"
    read -r CONFIRM_DELETE
    echo -ne "${RESET}"
    
    if [[ "$CONFIRM_DELETE" != "DELETE" ]]; then
        echo -e "\n${INFO}Uninstall cancelled.${RESET}"
        return
    fi
    
    # Proceed with deletion
    echo -e "\n${ACCENT}>> Removing selected Matrix Stacks...${RESET}\n"
    
    for stack_path in "${STACKS_TO_DELETE[@]}"; do
        _delete_single_stack "$stack_path"
    done
    
    echo -e "\n${SUCCESS}✓ Uninstall complete${RESET}"
    echo -e "${INFO}Remaining stacks (if any) were not deleted${RESET}"
}

_delete_single_stack() {
    local stack_path="$1"
    local stack_name=$(basename "$stack_path")
    local suffix=$(get_stack_resources "$stack_path")
    
    echo -e "${ACCENT}Processing: $stack_name${RESET}"
    
    # Get container suffix for resource cleanup
    local container_base_name=$(echo "$stack_name" | tr '[:upper:]' '[:lower:]' | sed 's/-//g')
    
    # Stop and remove containers
    echo -e "   ${INFO}Stopping and removing containers...${RESET}"
    
    # Find and remove containers related to this stack
    local containers_removed=0
    if [ -n "$suffix" ]; then
        # Stack with suffix - remove containers with exact suffix
        for container in $(docker ps -aq --filter "name=$container_base_name" 2>/dev/null); do
            local container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|^/||')
            if [[ "$container_name" == *"$suffix" ]] || [[ "$container_name" == "$container_base_name$suffix"* ]]; then
                docker rm -f "$container" 2>/dev/null && ((containers_removed++))
            fi
        done
    else
        # Stack without suffix - remove non-suffixed containers
        for container in $(docker ps -aq --filter "name=^${container_base_name}" 2>/dev/null); do
            local container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|^/||')
            # Only remove if it doesn't have a suffix (no dash-number at the end)
            if [[ ! "$container_name" =~ -[0-9]+$ ]]; then
                docker rm -f "$container" 2>/dev/null && ((containers_removed++))
            fi
        done
    fi
    
    echo -e "      Removed ${WARNING}$containers_removed${RESET} container(s)"
    
    # Remove volumes
    echo -e "   ${INFO}Removing volumes...${RESET}"
    local volumes_removed=0
    local network_suffix="${suffix:-}"
    
    # Remove volumes associated with this stack
    for volume in $(docker volume ls -q 2>/dev/null); do
        if [[ "$volume" == *"$stack_name"* ]] || [[ "$volume" == *"$container_base_name$network_suffix"* ]]; then
            docker volume rm "$volume" 2>/dev/null && ((volumes_removed++))
        fi
    done
    
    echo -e "      Removed ${WARNING}$volumes_removed${RESET} volume(s)"
    
    # Remove networks
    echo -e "   ${INFO}Removing networks...${RESET}"
    local networks_removed=0
    local network_name="matrix-net${network_suffix}"
    
    if docker network ls --filter "name=$network_name" 2>/dev/null | grep -q "$network_name"; then
        docker network rm "$network_name" 2>/dev/null && ((networks_removed++))
    fi
    
    echo -e "      Removed ${WARNING}$networks_removed${RESET} network(s)"
    
    # Remove directory
    echo -e "   ${INFO}Removing stack directory...${RESET}"
    if rm -rf "$stack_path" 2>/dev/null; then
        echo -e "      Removed directory: ${WARNING}$stack_path${RESET}"
    else
        echo -e "      ${ERROR}✗ Could not remove directory (may need sudo)${RESET}"
    fi
    
    echo -e "   ${SUCCESS}✓ Stack deletion complete${RESET}\n"
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
    for b in discord telegram whatsapp signal slack meta; do
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
            "meta"      "Meta      — Connect to Facebook Messenger / Instagram" OFF \
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
        # Note: databases are now created in PostgreSQL init script, not here.
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
        # Detect existing CONTAINER_SUFFIX from compose file (if any)
        local EXISTING_SUFFIX=""
        if grep -q "container_name: synapse-" "$COMPOSE_FILE" 2>/dev/null; then
            # Extract suffix from existing container name (e.g., "synapse-2" -> "-2")
            EXISTING_SUFFIX=$(grep "container_name: synapse-" "$COMPOSE_FILE" | sed 's/.*container_name: synapse//' | sed 's/[^0-9-].*//')
            if [ -n "$EXISTING_SUFFIX" ] && [ "$EXISTING_SUFFIX" != "db" ]; then
                EXISTING_SUFFIX=$(echo "$EXISTING_SUFFIX" | grep -o '^-[0-9]*')
            else
                EXISTING_SUFFIX=""
            fi
        fi
        # Detect existing network suffix
        local EXISTING_NET_SUFFIX=""
        if grep -q "networks: \[ matrix-net-" "$COMPOSE_FILE" 2>/dev/null; then
            EXISTING_NET_SUFFIX=$(grep "networks: \[ matrix-net" "$COMPOSE_FILE" | head -1 | sed 's/.*matrix-net//' | sed 's/.*\(-[0-9]*\).*/\1/')
        fi
        
        for bridge in "${NEW_BRIDGES[@]}"; do
            if grep -q "container_name: matrix-bridge-$bridge" "$COMPOSE_FILE" 2>/dev/null || \
               grep -q "mautrix-${bridge}:" "$COMPOSE_FILE" 2>/dev/null; then
                if _validate_compose "$(dirname "$COMPOSE_FILE")" 2>/dev/null; then
                    echo -e "   ${WARNING}⚠  $bridge already in compose — skipping${RESET}"
                    continue
                else
                    echo -e "   ${WARNING}⚠  $bridge in compose but corrupt — repairing...${RESET}"
                    _compose_remove_svc "$COMPOSE_FILE" "mautrix-${bridge}"
                    # fall through to re-insert
                fi
            fi
            sed -i '/^networks:/i\
\
  # mautrix-'"$bridge"' Bridge\
  mautrix-'"$bridge"':\
    container_name: matrix-bridge-'"$bridge${EXISTING_SUFFIX}"'\
    image: dock.mau.dev/mautrix/'"$bridge"':latest\
    restart: unless-stopped\
    volumes:\
      - ./bridges/'"$bridge"':/data\
    depends_on:\
      synapse:\
        condition: service_healthy\
      postgres:\
        condition: service_healthy\
    networks: [ '"matrix-net${EXISTING_NET_SUFFIX}"' ]\
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
            meta) echo -e "   ${SUCCESS}•${RESET} Meta: DM ${WARNING}@instagrambot:$DOMAIN${RESET} or ${WARNING}@facebookbot:$DOMAIN${RESET} → send ${WARNING}login${RESET} → paste browser cookies" ;;
        esac
    done

    echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
    read -r
}

################################################################################
# DIAGNOSTICS FUNCTION                                                         #
################################################################################

run_diagnostics() {
    draw_header
    echo -e "\n${ACCENT}>> Collect System Diagnostics${RESET}\n"

    local DIAG_DIR=""
    # Try to determine installation path
    if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
        DIAG_DIR="$TARGET_DIR"
        echo -e "${INFO}Using installation path from session: ${SUCCESS}$DIAG_DIR${RESET}"
    else
        # Attempt to detect from running synapse container
        local container_path
        container_path=$(docker inspect synapse 2>/dev/null | python3 -c "import sys,json; mounts=json.load(sys.stdin)[0].get('Mounts',[]); [print(m['Source'].rstrip('/synapse')) for m in mounts if 'synapse' in m.get('Source','')]" 2>/dev/null | head -1)
        if [ -n "$container_path" ] && [ -d "$container_path" ]; then
            DIAG_DIR="$container_path"
            echo -e "${INFO}Detected installation path from container: ${SUCCESS}$DIAG_DIR${RESET}"
        else
            # Check common paths
            for p in "/opt/stacks/matrix-stack" "/opt/matrix-stack" "$HOME/matrix-stack" "$(pwd)/matrix-stack"; do
                if [ -d "$p" ] && [ -f "$p/compose.yaml" -o -f "$p/docker-compose.yml" ]; then
                    DIAG_DIR="$p"
                    echo -e "${INFO}Found installation at common path: ${SUCCESS}$DIAG_DIR${RESET}"
                    break
                fi
            done
        fi
    fi

    if [ -z "$DIAG_DIR" ]; then
        echo -e "${WARNING}⚠️  Could not auto-detect installation path.${RESET}"
        echo -ne "Enter path to matrix-stack directory (or leave empty to skip config files): ${WARNING}"
        read -r DIAG_DIR
        echo -e "${RESET}"
        if [ -n "$DIAG_DIR" ] && [ ! -d "$DIAG_DIR" ]; then
            echo -e "   ${WARNING}Directory not found. Proceeding without config files.${RESET}"
            DIAG_DIR=""
        fi
    fi

    echo -e "${ACCENT}Collecting diagnostics (this may take a few seconds)...${RESET}"
    echo -e "${INFO} this will include:${RESET}"
    echo

    # Collect data
    echo -e "${WARNING}- Docker versions${RESET}"
    echo -e "${WARNING}- Container lists${RESET}"
    echo -e "${WARNING}- Log tails (last 20 lines for each container)${RESET}"
    echo -e "${WARNING}- Configuration file snippets${RESET}"
    echo -e "${WARNING}- Network details${RESET}"
    echo
    local diag_data=""
    diag_data+="=== Matrix Stack Diagnostics ===\n"
    diag_data+="Generated: $(date)\n"
    diag_data+="Script version: $SCRIPT_VERSION\n"
    diag_data+="Installation path: ${DIAG_DIR:-Not found}\n\n"

    diag_data+="--- Docker version ---\n"
    diag_data+="$(docker --version 2>&1)\n"
    diag_data+="--- Docker Compose version ---\n"
    diag_data+="$(docker compose version 2>&1)\n\n"

    diag_data+="--- All containers ---\n"
    diag_data+="$(docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1)\n\n"

    # List of possible container names to check
    local possible_containers=(
        "synapse" "synapse-db" "matrix-auth" "livekit" "livekit-jwt" "element-web"
        "element-call" "sliding-sync" "matrix-media-repo" "element-admin" "synapse-admin"
        "matrix-bridge-discord" "matrix-bridge-telegram" "matrix-bridge-whatsapp"
        "matrix-bridge-signal" "matrix-bridge-slack" "matrix-bridge-meta"
    )

    diag_data+="--- Last 20 lines of logs for key containers ---\n"
    for c in "${possible_containers[@]}"; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^$c$"; then
            diag_data+=">>> $c\n"
            diag_data+="$(docker logs --tail 20 "$c" 2>&1)\n\n"
        fi
    done

    if [ -n "$DIAG_DIR" ] && [ -d "$DIAG_DIR" ]; then
        diag_data+="--- Configuration files (first 20 lines) ---\n"
        for f in "$DIAG_DIR/synapse/homeserver.yaml" "$DIAG_DIR/mas/config.yaml" "$DIAG_DIR/livekit/livekit.yaml" "$DIAG_DIR/element-web/config.json"; do
            if [ -f "$f" ]; then
                diag_data+=">>> $f\n"
                diag_data+="$(head -20 "$f" 2>&1)\n\n"
            fi
        done
        # Compose file
        if [ -f "$DIAG_DIR/compose.yaml" ]; then
            diag_data+=">>> $DIAG_DIR/compose.yaml (first 50 lines)\n"
            diag_data+="$(head -50 "$DIAG_DIR/compose.yaml" 2>&1)\n\n"
        elif [ -f "$DIAG_DIR/docker-compose.yml" ]; then
            diag_data+=">>> $DIAG_DIR/docker-compose.yml (first 50 lines)\n"
            diag_data+="$(head -50 "$DIAG_DIR/docker-compose.yml" 2>&1)\n\n"
        fi
    fi

    diag_data+="--- Docker network matrix-net ---\n"
    diag_data+="$(docker network inspect matrix-net 2>&1)\n\n"

    echo -e "${SUCCESS}Diagnostics collected.${RESET}\n"

    # Ask to save
    ask_yn SAVE_DIAG "Save diagnostics to a file? (y/n): " y
    if [[ "$SAVE_DIAG" =~ ^[Yy]$ ]]; then
        local default_path="${DIAG_DIR:-$PWD}/matrix-diagnostics-$(date +%Y%m%d-%H%M%S).txt"
        while true; do
            echo -ne "Enter path to save diagnostics: "
            read -r -e -i "$default_path" DIAG_PATH
            echo -e "\n${WARNING}Diagnostics will be saved to: ${CONFIG_PATH}${DIAG_PATH}${RESET}"
            ask_yn CONFIRM_PATH "Confirm? (y/n): "
            if [[ "$CONFIRM_PATH" =~ ^[Yy]$ ]]; then
                break
            fi
            default_path="$DIAG_PATH"
        done

        mkdir -p "$(dirname "$DIAG_PATH")"
        echo -e "$diag_data" > "$DIAG_PATH"
        chmod 600 "$DIAG_PATH"
        echo -e "${SUCCESS}✓ Diagnostics saved to: ${CONFIG_PATH}${DIAG_PATH}${RESET}"
        echo -e "   ${WARNING}⚠️  This file may contain sensitive information. Handle with care.${RESET}"
    fi

    echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
    read -r
}


################################################################################
# LOGS VIEWER FUNCTION                                                         #
################################################################################

run_logs() {
    draw_header
    echo -e "\n${ACCENT}>> View Container Logs${RESET}\n"

    LOGS_DIR="${TARGET_DIR:-/opt/stacks/matrix-stack}"
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

    # ── Discover installed stacks ────────────────────────────────────────────
    local all_stacks=()
    local _search_dirs=("/opt/stacks" "$HOME/stacks" "/srv/matrix")
    for _sd in "${_search_dirs[@]}"; do
        [ -d "$_sd" ] || continue
        while IFS= read -r -d '' _sp; do
            [ -f "$_sp/compose.yaml" ] || [ -f "$_sp/docker-compose.yml" ] || continue
            grep -q "synapse" "$_sp/compose.yaml" "$_sp/docker-compose.yml" 2>/dev/null || continue
            all_stacks+=("$_sp")
        done < <(find "$_sd" -maxdepth 2 -name "compose.yaml" -o -name "docker-compose.yml" 2>/dev/null             | xargs -I{} dirname {} | sort -u | tr '\n' '\0')
    done

    local verify_dirs=()
    if [ ${#all_stacks[@]} -eq 0 ]; then
        # No auto-detected stacks — ask manually
        local _manual
        echo -ne "   Enter path to matrix-stack directory: "; echo -ne "${WARNING}"
        read -r _manual
        echo -ne "${RESET}"
        verify_dirs+=("$_manual")
    elif [ ${#all_stacks[@]} -eq 1 ]; then
        verify_dirs=("${all_stacks[0]}")
    else
        # Multiple stacks — whiptail selector
        if ! command -v whiptail &>/dev/null; then
            apt-get update -qq && apt-get install -y whiptail -qq >/dev/null 2>&1
        fi
        local _wt_items=()
        for _i in "${!all_stacks[@]}"; do
            local _dom
            _dom=$(get_stack_info "${all_stacks[$_i]}")
            _wt_items+=("$_i" "${all_stacks[$_i]} | Domain: $_dom" "OFF")
        done
        local _sel
        _sel=$(NEWT_COLORS='
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
' whiptail --title " Select Stacks to Verify " \
            --checklist "Choose which stack(s) to verify:" \
            $((${#all_stacks[@]} + 8)) 100 ${#all_stacks[@]} \
            "${_wt_items[@]}" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] || [ -z "$_sel" ] && { echo -e "${INFO}Verify cancelled${RESET}"; return; }
        for _idx in $(echo "$_sel" | tr -d '"'); do
            verify_dirs+=("${all_stacks[$_idx]}")
        done
    fi

    # ── Run verification for each selected stack ─────────────────────────────
    for VERIFY_DIR in "${verify_dirs[@]}"; do
        [ -d "$VERIFY_DIR" ] || { echo -e "   ${ERROR}✗ Not found: $VERIFY_DIR${RESET}"; continue; }
        echo -e "\n${ACCENT}── Verifying: ${WARNING}$(basename "$VERIFY_DIR")${RESET} ${ACCENT}(${VERIFY_DIR})${RESET}"
    
    # Try to detect configuration from files
    local DOMAIN=""
    local LOCAL_IP=""
    local PORT_OFFSET=0
    local METADATA_FOUND=false
    
    # First priority: Read from deployment metadata file (most accurate)
    if [ -f "$VERIFY_DIR/.deployment-metadata" ]; then
        source "$VERIFY_DIR/.deployment-metadata"
        LOCAL_IP="$DEPLOYMENT_LOCAL_IP"
        DOMAIN="$DEPLOYMENT_DOMAIN"
        PORT_OFFSET="$DEPLOYMENT_PORT_OFFSET"
        METADATA_FOUND=true
    fi
    
    # Fallback: Detect domain from synapse config
    if [ -z "$DOMAIN" ] && [ -f "$VERIFY_DIR/synapse/homeserver.yaml" ]; then
        DOMAIN=$(grep "server_name:" "$VERIFY_DIR/synapse/homeserver.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"')
    fi
    
    # Fallback: Try to detect local IP from proxy configs (if metadata not found)
    if [ -z "$LOCAL_IP" ]; then
        if [ -f "$VERIFY_DIR/caddy/Caddyfile" ]; then
            LOCAL_IP=$(grep -oP 'reverse_proxy \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$VERIFY_DIR/caddy/Caddyfile" 2>/dev/null | head -1)
        fi
        
        if [ -z "$LOCAL_IP" ] && [ -f "$VERIFY_DIR/traefik/dynamic.yml" ]; then
            LOCAL_IP=$(grep -oP 'http://\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$VERIFY_DIR/traefik/dynamic.yml" 2>/dev/null | head -1)
        fi
        
        if [ -z "$LOCAL_IP" ] && [ -f "$VERIFY_DIR/npm-wellknown.conf" ]; then
            LOCAL_IP=$(grep -oP 'proxy_pass http://\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$VERIFY_DIR/npm-wellknown.conf" 2>/dev/null | head -1)
        fi
        
        # Try to detect from homeserver.yaml if no proxy found (no proxy deployed in stack)
        if [ -z "$LOCAL_IP" ] && [ -f "$VERIFY_DIR/synapse/homeserver.yaml" ]; then
            # Look for bind_addresses or listeners that specify the IP
            LOCAL_IP=$(grep -A 3 "listeners:" "$VERIFY_DIR/synapse/homeserver.yaml" 2>/dev/null | grep -oP 'bind_addresses:\s*\n\s*-\s*\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
    fi
    
    # Fallback: Try to get from docker container network
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(docker inspect synapse 2>/dev/null | grep -A 5 '"Networks"' | grep "Gateway" | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
    fi
    
    # Last resort: Get host IP from running synapse container
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(docker exec synapse hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # Fallback to localhost if nothing else works
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP="127.0.0.1"
    fi
    
    # Calculate ports from standard defaults (assuming offset 0)
    local PORT_SYNAPSE=$((8008 + PORT_OFFSET))
    local PORT_SYNAPSE_ADMIN=$((8009 + PORT_OFFSET))
    local PORT_ELEMENT_CALL=$((8007 + PORT_OFFSET))
    local PORT_LIVEKIT=$((7880 + PORT_OFFSET))
    local PORT_MAS=$((8010 + PORT_OFFSET))
    local PORT_ELEMENT_WEB=$((8012 + PORT_OFFSET))
    local PORT_SLIDING_SYNC=$((8011 + PORT_OFFSET))
    local PORT_MEDIA_REPO=$((8013 + PORT_OFFSET))
    local PORT_ELEMENT_ADMIN=$((8014 + PORT_OFFSET))
    
    echo -e "${ACCENT}Container Status:${RESET}"
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
    
    echo -e "\n${ACCENT}Running Services & Access URLs:${RESET}\n"
    
    # Only display table and metadata if any services are running
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -qE "synapse|matrix-auth|element-web|livekit|element-call|synapse-admin|element-admin|sliding-sync|matrix-media-repo"; then
        # Build simple 3-column table without internal separators, centered text
        echo -e "   ${DNS_HOSTNAME}┌──────────────────────────┬──────────────────────────────────┬──────────────────────────────────────┐${RESET}"
        printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} %-30s ${DNS_HOSTNAME}  │${RESET} %-36s${DNS_HOSTNAME} │${RESET}\n" "Service" "Local Access" "WAN Access  "
        echo -e "   ${DNS_HOSTNAME}├──────────────────────────┼──────────────────────────────────┼──────────────────────────────────────┤${RESET}"
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^synapse$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Synapse" \
                "http://$LOCAL_IP:$PORT_SYNAPSE" \
                "https://${SUB_MATRIX:-matrix}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^matrix-auth$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "MAS Auth" \
                "http://$LOCAL_IP:$PORT_MAS" \
                "https://${SUB_MAS:-auth}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^element-web$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Element Web" \
                "http://$LOCAL_IP:$PORT_ELEMENT_WEB" \
                "https://${SUB_ELEMENT:-element}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^livekit$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "LiveKit SFU" \
                "http://$LOCAL_IP:$PORT_LIVEKIT" \
                "https://${SUB_LIVEKIT:-livekit}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^element-call$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Element Call" \
                "http://$LOCAL_IP:$PORT_ELEMENT_CALL" \
                "https://${SUB_CALL:-call}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^synapse-admin$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Synapse Admin" \
                "http://$LOCAL_IP:$PORT_SYNAPSE_ADMIN" \
                "https://${SUB_SYNAPSE_ADMIN:-admin}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^element-admin$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Element Admin" \
                "http://$LOCAL_IP:$PORT_ELEMENT_ADMIN" \
                "https://${SUB_ELEMENT_ADMIN:-admin}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^sliding-sync$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Sliding Sync" \
                "http://$LOCAL_IP:$PORT_SLIDING_SYNC" \
                "https://${SUB_SLIDING_SYNC:-sync}.$DOMAIN"
        fi
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^matrix-media-repo$"; then
            printf "   ${DNS_HOSTNAME}│${RESET} %-24s ${DNS_HOSTNAME}│${RESET} ${LOCAL_IP_COLOR}%-30s${RESET} ${DNS_HOSTNAME}  │${RESET} ${USER_ID_VALUE}%-36s${RESET}${DNS_HOSTNAME} │${RESET}\n" \
                "Media Repo" \
                "http://$LOCAL_IP:$PORT_MEDIA_REPO" \
                "https://${SUB_MEDIA_REPO:-media}.$DOMAIN"
        fi
        
        echo -e "   ${DNS_HOSTNAME}└──────────────────────────┴──────────────────────────────────┴──────────────────────────────────────┘${RESET}"
        echo ""
    fi

    done

    echo -e "${INFO}Press Enter to return to menu or Ctrl-C to exit...${RESET}"
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
    
    # Initialize NPM port variables (will be updated if port conflicts detected)
    NPM_HTTP_PORT=80
    NPM_HTTPS_PORT=443
    NPM_MGMT_PORT=81

    draw_header
    
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
    local deps=("curl" "wget" "openssl" "jq" "python3" "logrotate")
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
    
    # Check if user is behind a VPN/proxy/tunnel
    ask_yn USER_HAS_VPN "Are you behind a VPN, proxy, or tunnel? (y/n): "
    
    if command -v curl >/dev/null 2>&1; then
        RAW_IP=$(curl -sL --max-time 5 https://api.ipify.org 2>/dev/null || curl -sL --max-time 5 https://ifconfig.me/ip 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        RAW_IP=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || wget -qO- --timeout=5 https://ifconfig.me/ip 2>/dev/null)
    fi
    
    DETECTED_PUBLIC=$(echo "$RAW_IP" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    DETECTED_LOCAL=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1)
    [[ -z "$DETECTED_LOCAL" ]] && DETECTED_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$DETECTED_LOCAL" ]] && DETECTED_LOCAL=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
    
    # Now show VPN guide AFTER IPs are detected
    if [[ "$USER_HAS_VPN" =~ ^[Yy]$ ]]; then
        show_vpn_setup_guide
        echo -e "\n${WARNING}⚠️  Important:${RESET}"
        echo -e "   ${INFO}• You can still deploy through a VPN${RESET}"
        echo -e "   ${INFO}• Federation and external access WILL work IF:${RESET}"
        echo -e "   ${INFO}  1. You know your REAL external IP (VPN exit node IP)${RESET}"
        echo -e "   ${INFO}  2. Your DNS A records point to this external IP${RESET}"
        echo -e "   ${INFO}  3. Your reverse proxy listens on this external IP${RESET}"
        echo -e ""
    else
        echo -e "   ${SUCCESS}✓ No VPN detected, proceeding with normal setup${RESET}"
        echo -e ""
    fi
    
    echo -e "\n${WARNING}⚠️  IMPORTANT: Use Correct IP${RESET}"
    echo -e "   ${INFO}Enter the IP that EXTERNAL servers see (not your VPN tunnel IP)${RESET}"
    echo -e "   ${INFO}This is typically your ISP's IP, exit node IP, or proxy IP${RESET}"
    echo -e ""
    
    echo -e "   ${INFO}Detected External IP:${RESET} ${PUBLIC_IP_COLOR}${DETECTED_PUBLIC:-Not detected}${RESET}"
    echo -e "   ${INFO}Detected Local IP:${RESET}   ${LOCAL_IP_COLOR}${DETECTED_LOCAL:-Not detected}${RESET}"
    
    if [[ "$USER_HAS_VPN" =~ ^[Yy]$ ]]; then
        echo -e "   ${WARNING}(If external IP looks private like 10.x or 172.x, you're still behind VPN)${RESET}"
    fi
    echo -e ""
    
    # If automatic detection failed, ask manually
    if [ -z "$DETECTED_PUBLIC" ] || [ -z "$DETECTED_LOCAL" ]; then
        echo -e "\n${WARNING}⚠️  Automatic IP detection failed.${RESET}"
        echo -ne "Enter Public IP manually: ${WARNING}"
        read -r AUTO_PUBLIC_IP
        echo -e "${RESET}"
        echo -ne "Enter Local IP manually: ${WARNING}"
        read -r AUTO_LOCAL_IP
        echo -e "${RESET}"
    else
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

    echo -e "\n${ACCENT}>> Checking storage availability...${RESET}"

    # Function to convert bytes to human readable
    bytes_to_human() {
        local bytes=$1
        if [ $bytes -lt 1024 ]; then
            echo "${bytes}B"
        elif [ $bytes -lt 1048576 ]; then
            echo "$(( (bytes + 512) / 1024 ))KB"
        elif [ $bytes -lt 1073741824 ]; then
            echo "$(( (bytes + 524288) / 1048576 ))MB"
        else
            echo "$(( (bytes + 536870912) / 1073741824 ))GB"
        fi
    }

    # Calculate estimated storage needed (based on typical usage)
    ESTIMATED_STORAGE=5368709120  # 5GB in bytes (conservative estimate)
    echo -e "   ${INFO}Estimated storage needed:${RESET} ${WARNING}$(bytes_to_human $ESTIMATED_STORAGE)${RESET} (for base installation)"
    echo -e "   ${INFO}Media storage will grow with usage${RESET}"
    echo ""

    # Get storage info for root filesystem
    ROOT_STATS=$(df -k / | tail -1)
    ROOT_AVAIL_KB=$(echo "$ROOT_STATS" | awk '{print $4}')
    ROOT_AVAIL_BYTES=$((ROOT_AVAIL_KB * 1024))
    ROOT_TOTAL_KB=$(echo "$ROOT_STATS" | awk '{print $2}')
    ROOT_TOTAL_BYTES=$((ROOT_TOTAL_KB * 1024))
    ROOT_USED_PERCENT=$(echo "$ROOT_STATS" | awk '{print $5}' | tr -d '%')

    echo -e "   ${INFO}Root filesystem (/):${RESET}"
    echo -e "      ${SUCCESS}Total:${RESET}  $(bytes_to_human $ROOT_TOTAL_BYTES)"
    echo -e "      ${SUCCESS}Free:${RESET}   ${WARNING}$(bytes_to_human $ROOT_AVAIL_BYTES)${RESET}"
    echo -e "      ${SUCCESS}Used:${RESET}   $ROOT_USED_PERCENT%"

    # Warning if free space is low
    if [ $ROOT_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
        echo -e "\n   ${WARNING}⚠️  WARNING: Free space may be insufficient for base installation!${RESET}"
        echo -e "   ${WARNING}   Recommended: at least $(bytes_to_human $ESTIMATED_STORAGE) free${RESET}"
    fi

    echo -e "\n${ACCENT}>> Selecting deployment path...${RESET}"
    CUR_DIR=$(pwd)

    if [ "$DOCKGE_FOUND" = true ]; then
        echo -e "\n   ${INFO}Storage for each option:${RESET}"

        # Check Dockge path
        DOCKGE_STATS=$(df -k "/opt/stacks" 2>/dev/null | tail -1)
        if [ -n "$DOCKGE_STATS" ]; then
            DOCKGE_AVAIL_KB=$(echo "$DOCKGE_STATS" | awk '{print $4}')
            DOCKGE_AVAIL_BYTES=$((DOCKGE_AVAIL_KB * 1024))
            echo -e "      ${CHOICE_COLOR}1)${RESET} Dockge Path:       ${SUCCESS}$(bytes_to_human $DOCKGE_AVAIL_BYTES) free${RESET}"
        else
            echo -e "      ${CHOICE_COLOR}1)${RESET} Dockge Path:       ${WARNING}Unable to check${RESET}"
        fi

        # Check current directory
        CUR_STATS=$(df -k "$CUR_DIR" | tail -1)
        CUR_AVAIL_KB=$(echo "$CUR_STATS" | awk '{print $4}')
        CUR_AVAIL_BYTES=$((CUR_AVAIL_KB * 1024))
        echo -e "      ${CHOICE_COLOR}2)${RESET} Current Directory: ${SUCCESS}$(bytes_to_human $CUR_AVAIL_BYTES) free${RESET}"
        echo -e "      ${CHOICE_COLOR}3)${RESET} Custom Path"

        ask_choice PATH_SELECT "Selection (1/2/3): " 1 2 3
        case $PATH_SELECT in
            1) TARGET_DIR="/opt/stacks/matrix-stack" ;;
            2) TARGET_DIR="$CUR_DIR/matrix-stack" ;;
            3)
                while true; do
                    echo -ne "Enter Full Path: ${WARNING}"
                    read -r TARGET_DIR
                    echo -e "${RESET}"
                    if [ -d "$TARGET_DIR" ]; then
                        CUSTOM_STATS=$(df -k "$TARGET_DIR" | tail -1)
                        CUSTOM_AVAIL_KB=$(echo "$CUSTOM_STATS" | awk '{print $4}')
                        CUSTOM_AVAIL_BYTES=$((CUSTOM_AVAIL_KB * 1024))
                        echo -e "   ${INFO}Free space at $TARGET_DIR: ${WARNING}$(bytes_to_human $CUSTOM_AVAIL_BYTES)${RESET}"
                        if [ $CUSTOM_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
                            echo -e "   ${WARNING}⚠️  Warning: Low free space!${RESET}"
                            ask_yn CONTINUE_ANYWAY "Continue anyway? (y/n): "
                            if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                                echo -e "   ${INFO}Please choose another path.${RESET}"
                                continue
                            fi
                        fi
                        break
                    else
                        PARENT_DIR=$(dirname "$TARGET_DIR")
                        if [ -d "$PARENT_DIR" ]; then
                            PARENT_STATS=$(df -k "$PARENT_DIR" | tail -1)
                            PARENT_AVAIL_KB=$(echo "$PARENT_STATS" | awk '{print $4}')
                            PARENT_AVAIL_BYTES=$((PARENT_AVAIL_KB * 1024))
                            echo -e "   ${INFO}Free space on $PARENT_DIR: ${WARNING}$(bytes_to_human $PARENT_AVAIL_BYTES)${RESET}"
                            if [ $PARENT_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
                                echo -e "   ${WARNING}⚠️  Warning: Low free space on parent directory!${RESET}"
                                ask_yn CONTINUE_ANYWAY "Continue anyway? (y/n): "
                                if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                                    echo -e "   ${INFO}Please choose another path.${RESET}"
                                    continue
                                fi
                            fi
                        fi
                        break
                    fi
                done
                ;;
        esac
    elif [ "$DOCKER_READY" = true ]; then
        echo -e "\n   ${INFO}Storage for each option:${RESET}"

        CUR_STATS=$(df -k "$CUR_DIR" | tail -1)
        CUR_AVAIL_KB=$(echo "$CUR_STATS" | awk '{print $4}')
        CUR_AVAIL_BYTES=$((CUR_AVAIL_KB * 1024))
        echo -e "      ${CHOICE_COLOR}1)${RESET} Current Directory: ${SUCCESS}$(bytes_to_human $CUR_AVAIL_BYTES) free${RESET}"
        echo -e "      ${CHOICE_COLOR}2)${RESET} Custom Path"

        ask_choice PATH_SELECT "Selection (1/2): " 1 2
        if [[ "$PATH_SELECT" == "1" ]]; then
            TARGET_DIR="$CUR_DIR/matrix-stack"
        else
            while true; do
                echo -ne "Enter Full Path: ${WARNING}"
                read -r TARGET_DIR
                echo -e "${RESET}"
                if [ -d "$TARGET_DIR" ]; then
                    CUSTOM_STATS=$(df -k "$TARGET_DIR" | tail -1)
                    CUSTOM_AVAIL_KB=$(echo "$CUSTOM_STATS" | awk '{print $4}')
                    CUSTOM_AVAIL_BYTES=$((CUSTOM_AVAIL_KB * 1024))
                    echo -e "   ${INFO}Free space at $TARGET_DIR: ${WARNING}$(bytes_to_human $CUSTOM_AVAIL_BYTES)${RESET}"
                    if [ $CUSTOM_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
                        echo -e "   ${WARNING}⚠️  Warning: Low free space!${RESET}"
                        ask_yn CONTINUE_ANYWAY "Continue anyway? (y/n): "
                        if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                            echo -e "   ${INFO}Please choose another path.${RESET}"
                            continue
                        fi
                    fi
                    break
                else
                    PARENT_DIR=$(dirname "$TARGET_DIR")
                    if [ -d "$PARENT_DIR" ]; then
                        PARENT_STATS=$(df -k "$PARENT_DIR" | tail -1)
                        PARENT_AVAIL_KB=$(echo "$PARENT_STATS" | awk '{print $4}')
                        PARENT_AVAIL_BYTES=$((PARENT_AVAIL_KB * 1024))
                        echo -e "   ${INFO}Free space on $PARENT_DIR: ${WARNING}$(bytes_to_human $PARENT_AVAIL_BYTES)${RESET}"
                        if [ $PARENT_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
                            echo -e "   ${WARNING}⚠️  Warning: Low free space on parent directory!${RESET}"
                            ask_yn CONTINUE_ANYWAY "Continue anyway? (y/n): "
                            if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                                echo -e "   ${INFO}Please choose another path.${RESET}"
                                continue
                            fi
                        fi
                    fi
                    break
                fi
            done
        fi
    else
        while true; do
            echo -ne "Enter Deployment Path (Default /opt/matrix-stack): ${WARNING}"
            read -r TARGET_DIR
            echo -e "${RESET}"
            TARGET_DIR=${TARGET_DIR:-/opt/matrix-stack}
            if [ -d "$TARGET_DIR" ]; then
                CUSTOM_STATS=$(df -k "$TARGET_DIR" | tail -1)
                CUSTOM_AVAIL_KB=$(echo "$CUSTOM_STATS" | awk '{print $4}')
                CUSTOM_AVAIL_BYTES=$((CUSTOM_AVAIL_KB * 1024))
                echo -e "   ${INFO}Free space at $TARGET_DIR: ${WARNING}$(bytes_to_human $CUSTOM_AVAIL_BYTES)${RESET}"
                if [ $CUSTOM_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
                    echo -e "   ${WARNING}⚠️  Warning: Low free space!${RESET}"
                    ask_yn CONTINUE_ANYWAY "Continue anyway? (y/n): "
                    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                        echo -e "   ${INFO}Please choose another path.${RESET}"
                        continue
                    fi
                fi
                break
            else
                PARENT_DIR=$(dirname "$TARGET_DIR")
                if [ -d "$PARENT_DIR" ]; then
                    PARENT_STATS=$(df -k "$PARENT_DIR" | tail -1)
                    PARENT_AVAIL_KB=$(echo "$PARENT_STATS" | awk '{print $4}')
                    PARENT_AVAIL_BYTES=$((PARENT_AVAIL_KB * 1024))
                    echo -e "   ${INFO}Free space on $PARENT_DIR: ${WARNING}$(bytes_to_human $PARENT_AVAIL_BYTES)${RESET}"
                    if [ $PARENT_AVAIL_BYTES -lt $ESTIMATED_STORAGE ]; then
                        echo -e "   ${WARNING}⚠️  Warning: Low free space on parent directory!${RESET}"
                        ask_yn CONTINUE_ANYWAY "Continue anyway? (y/n): "
                        if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                            echo -e "   ${INFO}Please choose another path.${RESET}"
                            continue
                        fi
                    fi
                fi
                break
            fi
        done
    fi

    # Handle existing directory
    if [ -d "$TARGET_DIR" ] && [ "$TARGET_DIR" != "$stack_dir" ]; then
        rm -rf "$TARGET_DIR"
    fi
    
    # Create base directory FIRST before setting up logging
    mkdir -p "$TARGET_DIR"
    
    # Setup comprehensive logging now that TARGET_DIR exists
    setup_logging
    log_message "═════════════════════════════════════════════════════════════════════"
    log_message "Matrix Stack Deployment Started"
    log_message "Target Directory: $TARGET_DIR"
    log_message "═════════════════════════════════════════════════════════════════════"

    # Redirect all subsequent output to both console and log file
    # This captures the entire deployment process
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)

    # Create remaining directory structure
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
        
        # LAN/WAN access for LiveKit
        echo -e "\n${ACCENT}LiveKit Network Access:${RESET}"
        echo -e "   ${INFO}Configure whether calls work on LAN only or both LAN + WAN (remote users).${RESET}"
        ask_yn LIVEKIT_LAN_WAN "Enable both LAN and WAN access (dual-stack)? [y/n]: " n
        
        if [[ "$LIVEKIT_LAN_WAN" =~ ^[Yy]$ ]]; then
            LIVEKIT_DUAL_STACK="true"
            echo -e "   ${SUCCESS}✓ LiveKit configured for LAN + WAN (using host network mode)${RESET}"
        else
            LIVEKIT_DUAL_STACK="false"
            echo -e "   ${INFO}LiveKit configured for LAN access only${RESET}"
        fi
    else
        ELEMENT_CALL_ENABLED="false"
        LIVEKIT_DUAL_STACK="false"
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
                --checklist "Select bridges to install (SPACE to toggle, ENTER to confirm):\n\nNote: Telegram temporarily unavailable (Go version pending)" \
                23 78 10 \
                "discord"   "Discord   — Connect to Discord servers"           OFF \
                "whatsapp"  "WhatsApp  — Connect to WhatsApp (requires phone)"  OFF \
                "signal"    "Signal    — Connect to Signal (requires phone)"    OFF \
                "slack"     "Slack     — Connect to Slack workspaces"           OFF \
                "meta"      "Meta      — Connect to Facebook Messenger / Instagram" OFF \
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
    
    echo -e "\n${INFO}📝 Note: Telegram bridge temporarily unavailable${RESET}"
    echo -e "   ${INFO}The Python version has compatibility issues with Synapse + MAS.${RESET}"
    echo -e "   ${INFO}Telegram bridge will be re-added when the Go version is officially released.${RESET}"

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

    # ──────────────────────────────────────────────────────────────────────────────
    # Port Conflict Detection & Unified Fallback
    # ──────────────────────────────────────────────────────────────────────────────
    echo -e "\n${ACCENT}Port Configuration:${RESET}"
    
    # Function to check if a port is available
    is_port_available() {
        local port=$1
        # Port is available if not in use OR only used by docker-proxy
        ! ss -lpn 2>/dev/null | grep -q ":${port} " || \
        ss -lpn 2>/dev/null | grep ":${port} " | grep -q "docker-proxy"
    }

    # Function to check if container names (with suffix) are available
    # All container names used across the full compose template
    _ALL_CONTAINER_NAMES=(
        "synapse" "synapse-db" "matrix-auth"
        "element-web" "livekit" "livekit-jwt"
        "element-call" "element-admin" "synapse-admin"
        "sliding-sync" "matrix-media-repo"
        "nginx-proxy-manager" "caddy" "traefik" "newt" "coturn"
    )

    # Check if all container names (with suffix) and network name are free
    is_name_set_available() {
        local suffix="$1"
        local _ec
        _ec=$(docker ps -a --format "{{.Names}}" 2>/dev/null)
        local _en
        _en=$(docker network ls --format "{{.Name}}" 2>/dev/null)
        local name
        for name in "${_ALL_CONTAINER_NAMES[@]}"; do
            echo "$_ec" | grep -q "^${name}${suffix}$" && return 1
        done
        echo "$_en" | grep -q "^matrix-net${suffix}$" && return 1
        return 0
    }

    # Check if all ports (with offset) are free
    check_port_set() {
        local offset=$1
        is_port_available $((8008 + offset)) && \
        is_port_available $((8009 + offset)) && \
        is_port_available $((8007 + offset)) && \
        is_port_available $((7880 + offset)) && \
        is_port_available $((8010 + offset)) && \
        is_port_available $((8012 + offset)) && \
        is_port_available $((8011 + offset)) && \
        is_port_available $((8013 + offset)) && \
        is_port_available $((8014 + offset))
    }

    # Find lowest free port offset
    PORT_OFFSET=0
    while [ $PORT_OFFSET -lt 100 ]; do
        check_port_set $PORT_OFFSET && break
        PORT_OFFSET=$((PORT_OFFSET + 1))
    done

    # Find lowest free name/network slot (independent of port offset)
    NAME_OFFSET=0
    while [ $NAME_OFFSET -lt 100 ]; do
        local _ns=""
        [ "$NAME_OFFSET" -gt 0 ] && _ns="-${NAME_OFFSET}"
        is_name_set_available "$_ns" && break
        NAME_OFFSET=$((NAME_OFFSET + 1))
    done

    # Use whichever is higher so both ports AND names are conflict-free
    if [ "$NAME_OFFSET" -gt "$PORT_OFFSET" ]; then
        PORT_OFFSET=$NAME_OFFSET
    fi

    # Calculate final ports for all services
    PORT_SYNAPSE=$((8008 + PORT_OFFSET))
    PORT_SYNAPSE_ADMIN=$((8009 + PORT_OFFSET))
    PORT_ELEMENT_CALL=$((8007 + PORT_OFFSET))
    PORT_LIVEKIT=$((7880 + PORT_OFFSET))
    PORT_MAS=$((8010 + PORT_OFFSET))
    PORT_ELEMENT_WEB=$((8012 + PORT_OFFSET))
    PORT_SLIDING_SYNC=$((8011 + PORT_OFFSET))
    PORT_MEDIA_REPO=$((8013 + PORT_OFFSET))
    PORT_ELEMENT_ADMIN=$((8014 + PORT_OFFSET))
    
    # Generate container name suffix based on port offset
    # If using default ports (offset 0), no suffix. Otherwise, use "-<offset>"
    if [ $PORT_OFFSET -eq 0 ]; then
        CONTAINER_SUFFIX=""
    else
        CONTAINER_SUFFIX="-${PORT_OFFSET}"
    fi
    
    # Display configuration
    if [ $PORT_OFFSET -eq 0 ]; then
        echo -e "   ${SUCCESS}✓ Using standard ports and container names${RESET}"
        echo -e "      Synapse: ${WARNING}$PORT_SYNAPSE${RESET}"
        echo -e "      MAS: ${WARNING}$PORT_MAS${RESET}"
        echo -e "      Element Web: ${WARNING}$PORT_ELEMENT_WEB${RESET}"
        echo -e "      Synapse Admin: ${WARNING}$PORT_SYNAPSE_ADMIN${RESET}"
        echo -e "      Element Call: ${WARNING}$PORT_ELEMENT_CALL${RESET}"
        echo -e "      Sliding Sync: ${WARNING}$PORT_SLIDING_SYNC${RESET}"
        echo -e "      Media Repo: ${WARNING}$PORT_MEDIA_REPO${RESET}"
        echo -e "      Element Admin: ${WARNING}$PORT_ELEMENT_ADMIN${RESET}"
        echo -e "      LiveKit: ${WARNING}$PORT_LIVEKIT${RESET}"
    elif [ $PORT_OFFSET -lt 100 ]; then
        echo -e "   ${WARNING}⚠️  Ports occupied. Shifting all ports +$PORT_OFFSET and using container suffix '$CONTAINER_SUFFIX'${RESET}"
        echo -e "      Synapse: ${WARNING}$PORT_SYNAPSE${RESET} (was 8008)"
        echo -e "      MAS: ${WARNING}$PORT_MAS${RESET} (was 8010)"
        echo -e "      Element Web: ${WARNING}$PORT_ELEMENT_WEB${RESET} (was 8012)"
        echo -e "      Synapse Admin: ${WARNING}$PORT_SYNAPSE_ADMIN${RESET} (was 8009)"
        echo -e "      Element Call: ${WARNING}$PORT_ELEMENT_CALL${RESET} (was 8007)"
        echo -e "      Sliding Sync: ${WARNING}$PORT_SLIDING_SYNC${RESET} (was 8011)"
        echo -e "      Media Repo: ${WARNING}$PORT_MEDIA_REPO${RESET} (was 8013)"
        echo -e "      Element Admin: ${WARNING}$PORT_ELEMENT_ADMIN${RESET} (was 8014)"
        echo -e "      LiveKit: ${WARNING}$PORT_LIVEKIT${RESET} (was 7880)"
        echo -e "   ${INFO}Container names will be appended with: ${WARNING}${CONTAINER_SUFFIX}${RESET}"
    else
        echo -e "\n${ERROR}✗ Could not find available ports or container names (tried offsets 0-99)${RESET}"
        echo -e "${INFO}Free conflicting ports and try again.${RESET}"
        exit 1
    fi

    # Admin user configuration
    echo ""
    echo -e "   ${WARNING}⚠️  Username must be lowercase only (a-z and numbers, no uppercase or spaces).${RESET}"
    while true; do
        echo -ne "Admin Username [admin]: ${WARNING}"
        read -r ADMIN_USER
        if [ -z "$ADMIN_USER" ]; then
            ADMIN_USER="admin"
            echo -ne "\033[1A\033[K"
            echo -e "${RESET}Admin Username [admin]: ${WARNING}${ADMIN_USER}${RESET}"
            break
        elif [[ "$ADMIN_USER" =~ [A-Z] ]]; then
            echo -e "${RESET}   ${ERROR}Username must not contain uppercase letters. Try again.${RESET}"
        else
            echo -ne "${RESET}"
            break
        fi
    done

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
echo -e "   ${CHOICE_COLOR}5)${RESET} Pangolin (Newt tunnel — no open ports needed)"
echo -e "   ${CHOICE_COLOR}6)${RESET} Manual Setup"
ask_choice PROXY_SELECT "Selection (1-6): " 1 2 3 4 5 6

case $PROXY_SELECT in
    1) PROXY_TYPE="npm" ;;
    2) PROXY_TYPE="caddy" ;;
    3) PROXY_TYPE="traefik" ;;
    4) PROXY_TYPE="cloudflare" ;;
    5) PROXY_TYPE="pangolin" ;;
    *) PROXY_TYPE="manual" ;;
esac

if [ "$PROXY_ALREADY_RUNNING" = false ] && [[ "$PROXY_TYPE" != "cloudflare" ]] && [[ "$PROXY_TYPE" != "manual" ]] && [[ "$PROXY_TYPE" != "pangolin" ]]; then
    echo -e "\n   ${WARNING}⚠️  This will add $PROXY_TYPE to your Docker stack and install it automatically.${RESET}"
fi

# Port conflict detection for NPM
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_MGMT_PORT=81

if [[ "$PROXY_TYPE" == "npm" && "$PROXY_ALREADY_RUNNING" == "false" ]]; then
    echo -e "\n${ACCENT}>> Checking for port conflicts...${RESET}"
    
    http_in_use=false
    https_in_use=false
    
    if ss -lpn 2>/dev/null | grep -q ":80 "; then
        http_in_use=true
        echo -e "   ${WARNING}⚠️  Port 80 is in use (Caddy, Traefik, or other service detected)${RESET}"
    fi
    
    if ss -lpn 2>/dev/null | grep -q ":443 "; then
        https_in_use=true
        echo -e "   ${WARNING}⚠️  Port 443 is in use (Caddy, Traefik, or other service detected)${RESET}"
    fi
    
    # If ports are in use, find fallbacks
    if [ "$http_in_use" = true ] || [ "$https_in_use" = true ]; then
        echo -e "   ${INFO}NPM will use fallback ports to avoid conflicts.${RESET}"
        
        if [ "$http_in_use" = true ]; then
            NPM_HTTP_PORT=$(find_available_port 8000)
            if [ -z "$NPM_HTTP_PORT" ]; then
                echo -e "   ${ERROR}✗ Could not find available port starting from 8000${RESET}"
                exit 1
            fi
            echo -e "   ${SUCCESS}✓ NPM HTTP → port ${NPM_HTTP_PORT}${RESET}"
        fi
        
        if [ "$https_in_use" = true ]; then
            NPM_HTTPS_PORT=$(find_available_port 8443)
            if [ -z "$NPM_HTTPS_PORT" ]; then
                echo -e "   ${ERROR}✗ Could not find available port starting from 8443${RESET}"
                exit 1
            fi
            echo -e "   ${SUCCESS}✓ NPM HTTPS → port ${NPM_HTTPS_PORT}${RESET}"
        fi
        
        echo -e "   ${INFO}Management UI still runs on port 81 (http://$AUTO_LOCAL_IP:81)${RESET}"
        echo -e "   ${WARNING}⚠️  Note: You'll need your proxy (Caddy/Traefik) to forward external traffic to these ports.${RESET}"
    else
        echo -e "   ${SUCCESS}✓ Ports 80 and 443 are available — NPM will use standard ports${RESET}"
    fi
fi

# Pangolin-specific configuration
if [[ "$PROXY_TYPE" == "pangolin" ]]; then
    echo -e "\n${ACCENT}Pangolin Configuration:${RESET}"
    echo -e "   ${INFO}Pangolin uses a Newt tunnel so your home server needs zero open ports.${RESET}"
    echo -e "   ${INFO}TURN/coturn will run on a separate VPS with a public IP.${RESET}"
    echo ""
    echo -ne "Pangolin Dashboard URL (e.g. https://pangolin.example.com): ${WARNING}"
    read -r PANGOLIN_URL
    echo -e "${RESET}"
    # Strip trailing slash
    PANGOLIN_URL="${PANGOLIN_URL%/}"

    echo -ne "Newt Tunnel ID: ${WARNING}"
    read -r PANGOLIN_NEWT_ID
    echo -e "${RESET}"

    echo -ne "Newt Tunnel Secret: ${WARNING}"
    read -r PANGOLIN_NEWT_SECRET
    echo -e "${RESET}"

    echo -ne "VPS Public IP (for coturn / TURN): ${WARNING}"
    read -r PANGOLIN_VPS_IP
    echo -e "${RESET}"

    echo -e "   ${SUCCESS}✓ Pangolin config collected — Newt container will be added to your stack${RESET}"
    echo -e "   ${SUCCESS}✓ LiveKit TURN will point to your VPS at ${PANGOLIN_VPS_IP}${RESET}"
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
    if [ "$PROXY_ALREADY_RUNNING" = false ] && [[ "$PROXY_TYPE" != "pangolin" ]]; then
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
    
    # Export all port variables for docker-compose
    export PORT_SYNAPSE PORT_SYNAPSE_ADMIN PORT_ELEMENT_CALL PORT_LIVEKIT
    export PORT_MAS PORT_ELEMENT_WEB PORT_SLIDING_SYNC PORT_MEDIA_REPO PORT_ELEMENT_ADMIN
    export CONTAINER_SUFFIX
    
    # Clean up any orphaned containers first
    cd "$TARGET_DIR" && docker compose down --remove-orphans 2>/dev/null || true
    
    cd "$TARGET_DIR" && docker compose up -d </dev/tty >/dev/tty 2>/dev/tty
    
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
    # Note: Databases are now created in PostgreSQL init script, so this loop is removed.
    # for bridge in "${SELECTED_BRIDGES[@]}"; do ... done  # removed

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
    until curl -sL --fail "http://$AUTO_LOCAL_IP:$PORT_SYNAPSE/_matrix/client/versions" 2>/dev/null | grep -q "versions"; do
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
    until curl -s -f "http://$AUTO_LOCAL_IP:$PORT_LIVEKIT" 2>/dev/null >/dev/null; do
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
    until curl -s -f "http://$AUTO_LOCAL_IP:8089" 2>/dev/null >/dev/null || \
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
        until curl -s -f "http://$AUTO_LOCAL_IP:$PORT_ELEMENT_CALL" 2>/dev/null >/dev/null; do
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
        until curl -s -f "http://$AUTO_LOCAL_IP:8013/_matrix/media/v3/config" 2>/dev/null >/dev/null || \
              curl -s -f "http://$AUTO_LOCAL_IP:8013/" 2>/dev/null >/dev/null || \
              docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^matrix-media-repo$"; do
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
        until curl -s -f "http://$AUTO_LOCAL_IP:$PORT_SYNAPSE_ADMIN" 2>/dev/null >/dev/null; do
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
    elif [[ "$PROXY_TYPE" == "pangolin" ]]; then
        echo -e "\n${ACCENT}Would you like the Pangolin setup guide? (y/n):${RESET} "
        read -r SHOW_GUIDE
        [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]] && show_pangolin_guide
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
# RECONFIGURE STACK - Re-run config steps without cleaning up data              #
################################################################################

################################################################################
# Parse existing config from synapse config file                              #
################################################################################
parse_existing_config() {
    local config_file="$1/data/homeserver.yaml"
    local mas_config="$1/data/mas.yaml"
    
    # Parse from synapse homeserver.yaml
    if [ -f "$config_file" ]; then
        # Extract domain/server name
        DOMAIN=$(grep "^server_name:" "$config_file" | awk '{print $2}' | tr -d '"')
        SERVER_NAME="$DOMAIN"
        
        # Extract admin user
        ADMIN_USER=$(grep "^admin_user:" "$config_file" | awk '{print $2}' | tr -d '"' | sed 's/@.*//')
    fi
    
    # Parse from mas.yaml if exists
    if [ -f "$mas_config" ]; then
        # Extract MAS-related settings if needed
        :
    fi
    
    # Check for enabled features from compose file
    if [ -f "$1/compose.yaml" ]; then
        if grep -q "element-call:" "$1/compose.yaml"; then
            ELEMENT_CALL_ENABLED="true"
        else
            ELEMENT_CALL_ENABLED="false"
        fi
        
        if grep -q "media-repo:" "$1/compose.yaml"; then
            MEDIA_REPO_ENABLED="true"
        else
            MEDIA_REPO_ENABLED="false"
        fi
        
        # Check for admin panels
        if grep -q "element-admin:" "$1/compose.yaml"; then
            ELEMENT_ADMIN_ENABLED="true"
        else
            ELEMENT_ADMIN_ENABLED="false"
        fi
        
        if grep -q "synapse-admin:" "$1/compose.yaml"; then
            SYNAPSE_ADMIN_ENABLED="true"
        else
            SYNAPSE_ADMIN_ENABLED="false"
        fi
        
        # Check for bridges
        SELECTED_BRIDGES=()
        for bridge in discord whatsapp signal slack meta telegram; do
            if grep -q "mautrix-$bridge:" "$1/compose.yaml" || grep -q "matrix-$bridge:" "$1/compose.yaml"; then
                SELECTED_BRIDGES+=("$bridge")
            fi
        done
    fi
}

################################################################################
# Show and manage installed features/bridges                                  #
################################################################################
show_installed_features() {
    echo -e "\n${ACCENT}>> Currently Installed Features${RESET}\n"
    
    echo -e "   ${INFO}Core Services:${RESET}"
    echo -e "     • Synapse (Matrix Homeserver) - Always Enabled"
    echo -e "     • MAS (Authentication) - Always Enabled"
    echo -e "     • LiveKit (Video Calls) - Always Enabled"
    echo -e "     • PostgreSQL (Database) - Always Enabled"
    
    echo -e "\n   ${INFO}Optional Features:${RESET}"
    if [[ "$ELEMENT_CALL_ENABLED" == "true" ]]; then
        echo -e "     ${SUCCESS}✓${RESET} Element Call (WebRTC Calls)"
    else
        echo -e "     ✗ Element Call (WebRTC Calls)"
    fi
    
    if [[ "$ELEMENT_ADMIN_ENABLED" == "true" ]]; then
        echo -e "     ${SUCCESS}✓${RESET} Element Admin (Admin Panel)"
    else
        echo -e "     ✗ Element Admin (Admin Panel)"
    fi
    
    if [[ "$SYNAPSE_ADMIN_ENABLED" == "true" ]]; then
        echo -e "     ${SUCCESS}✓${RESET} Synapse Admin (Admin Panel)"
    else
        echo -e "     ✗ Synapse Admin (Admin Panel)"
    fi
    
    if [[ "$MEDIA_REPO_ENABLED" == "true" ]]; then
        echo -e "     ${SUCCESS}✓${RESET} Media Repo (Advanced Media Handling)"
    else
        echo -e "     ✗ Media Repo (Advanced Media Handling)"
    fi
    
    echo -e "\n   ${INFO}Installed Bridges:${RESET}"
    if [ ${#SELECTED_BRIDGES[@]} -eq 0 ]; then
        echo -e "     • None installed"
    else
        for bridge in "${SELECTED_BRIDGES[@]}"; do
            echo -e "     ${SUCCESS}✓${RESET} ${bridge^}"
        done
    fi
}

################################################################################
# Remove/delete features from config                                          #
################################################################################
manage_features_removal() {
    echo -e "\n${ACCENT}>> Manage Features and Bridges${RESET}"
    
    while true; do
        echo -e "\n${INFO}What would you like to do?${RESET}"
        echo -e "   ${CHOICE_COLOR}1)${RESET} Remove an optional feature"
        echo -e "   ${CHOICE_COLOR}2)${RESET} Remove a bridge"
        echo -e "   ${CHOICE_COLOR}3)${RESET} Skip (keep all features)"
        echo ""
        echo -ne "Selection (1/2/3): ${CHOICE_COLOR}"
        read -r feature_choice
        echo -e "${RESET}"
        
        case "$feature_choice" in
            1)
                echo -e "${INFO}Available features to remove:${RESET}"
                local feat_options=()
                [ "$ELEMENT_CALL_ENABLED" = "true" ] && feat_options+=("Element Call")
                [ "$ELEMENT_ADMIN_ENABLED" = "true" ] && feat_options+=("Element Admin")
                [ "$SYNAPSE_ADMIN_ENABLED" = "true" ] && feat_options+=("Synapse Admin")
                [ "$MEDIA_REPO_ENABLED" = "true" ] && feat_options+=("Media Repo")
                
                if [ ${#feat_options[@]} -eq 0 ]; then
                    echo -e "   ${INFO}No optional features to remove${RESET}"
                else
                    for i in "${!feat_options[@]}"; do
                        echo -e "   ${CHOICE_COLOR}$((i+1)))${RESET} ${feat_options[$i]}"
                    done
                    echo -ne "\nSelect feature to remove (1-${#feat_options[@]}): ${CHOICE_COLOR}"
                    read -r feat_sel
                    echo -e "${RESET}"
                    
                    if [[ "$feat_sel" =~ ^[0-9]+$ ]] && [ "$feat_sel" -ge 1 ] && [ "$feat_sel" -le ${#feat_options[@]} ]; then
                        case "${feat_options[$((feat_sel-1))]}" in
                            "Element Call") ELEMENT_CALL_ENABLED="false"; echo -e "${SUCCESS}✓ Element Call will be removed${RESET}" ;;
                            "Element Admin") ELEMENT_ADMIN_ENABLED="false"; echo -e "${SUCCESS}✓ Element Admin will be removed${RESET}" ;;
                            "Synapse Admin") SYNAPSE_ADMIN_ENABLED="false"; echo -e "${SUCCESS}✓ Synapse Admin will be removed${RESET}" ;;
                            "Media Repo") MEDIA_REPO_ENABLED="false"; echo -e "${SUCCESS}✓ Media Repo will be removed${RESET}" ;;
                        esac
                    else
                        echo -e "${ERROR}Invalid selection${RESET}"
                    fi
                fi
                ;;
            2)
                if [ ${#SELECTED_BRIDGES[@]} -eq 0 ]; then
                    echo -e "${INFO}No bridges installed to remove${RESET}"
                else
                    echo -e "${INFO}Installed bridges:${RESET}"
                    for i in "${!SELECTED_BRIDGES[@]}"; do
                        echo -e "   ${CHOICE_COLOR}$((i+1)))${RESET} ${SELECTED_BRIDGES[$i]^}"
                    done
                    echo -ne "\nSelect bridge to remove (1-${#SELECTED_BRIDGES[@]}): ${CHOICE_COLOR}"
                    read -r bridge_sel
                    echo -e "${RESET}"
                    
                    if [[ "$bridge_sel" =~ ^[0-9]+$ ]] && [ "$bridge_sel" -ge 1 ] && [ "$bridge_sel" -le ${#SELECTED_BRIDGES[@]} ]; then
                        removed_bridge="${SELECTED_BRIDGES[$((bridge_sel-1))]}"
                        SELECTED_BRIDGES=("${SELECTED_BRIDGES[@]:0:bridge_sel-1}" "${SELECTED_BRIDGES[@]:bridge_sel}")
                        echo -e "${SUCCESS}✓ ${removed_bridge^} will be removed${RESET}"
                    else
                        echo -e "${ERROR}Invalid selection${RESET}"
                    fi
                fi
                ;;
            3)
                echo -e "${INFO}Keeping all features and bridges${RESET}"
                break
                ;;
            *)
                echo -e "${ERROR}Invalid selection${RESET}"
                ;;
        esac
    done
}

# Note: Helper functions moved to before run_uninstall for proper function ordering

reconfigure_stack() {
    draw_header
    echo -e "\n${ACCENT}>> Reconfigure - Re-run configuration steps${RESET}"
    
    # Find all stacks
    local -a all_stacks
    mapfile -t all_stacks < <(find_all_matrix_stacks)
    
    # Clean up empty elements from mapfile
    cleaned_stacks=()
    for stack in "${all_stacks[@]}"; do
        if [ -n "$stack" ]; then
            cleaned_stacks+=("$stack")
        fi
    done
    all_stacks=("${cleaned_stacks[@]}")
    
    if [ ${#all_stacks[@]} -eq 0 ]; then
        echo -e "${WARNING}No resources found.${RESET}"
        echo -ne "Press Enter to return to main menu: "
        read -r
        return
    elif [ ${#all_stacks[@]} -eq 1 ]; then
        # Single stack - reconfigure it directly
        RECONFIG_STACK_DIR="${all_stacks[0]}"

        while true; do
            load_stack_ports_from_containers "$RECONFIG_STACK_DIR"
            parse_stack_configuration "$RECONFIG_STACK_DIR"

            echo -e "\n${ACCENT}>> Reconfiguring: $(basename "$RECONFIG_STACK_DIR")${RESET}"
            echo -e "   ${INFO}Domain: $CURRENT_DOMAIN${RESET}"

            if [ ${#CURRENT_FEATURES[@]} -gt 0 ]; then
                echo -e "   ${SUCCESS}Features installed:${RESET}"
                for feature in "${CURRENT_FEATURES[@]}"; do echo -e "      \u2713 $feature"; done
            else
                echo -e "   ${INFO}No optional features installed${RESET}"
            fi

            if [ ${#CURRENT_BRIDGES[@]} -gt 0 ]; then
                echo -e "   ${SUCCESS}Bridges installed:${RESET}"
                for bridge in "${CURRENT_BRIDGES[@]}"; do echo -e "      \u2713 $bridge"; done
            else
                echo -e "   ${INFO}No bridges installed${RESET}"
            fi

            echo -e "\n${ACCENT}>> Reconfiguration Options:${RESET}\n"
            echo -e "   ${INFO}1)${RESET} Modify domain"
            echo -e "   ${INFO}2)${RESET} Add/remove features"
            echo -e "   ${INFO}3)${RESET} Add/remove bridges"
            echo -e "   ${INFO}0)${RESET} Done"
            echo -ne "\nSelect option (0-3): ${CHOICE_COLOR}"
            read -r reconfig_choice
            echo -e "${RESET}"

            case "$reconfig_choice" in
                1) manage_domain   "$RECONFIG_STACK_DIR" ;;
                2) manage_features "$RECONFIG_STACK_DIR" ;;
                3) manage_bridges  "$RECONFIG_STACK_DIR" ;;
                0) break ;;
                *) echo -e "   ${ERROR}Invalid selection${RESET}" ;;
            esac
        done

        echo -e "\n${SUCCESS}\u2713 Reconfiguration for $(basename $RECONFIG_STACK_DIR) complete${RESET}"
    elif [ ${#all_stacks[@]} -gt 1 ]; then
        # Multiple stacks found - show whiptail checklist for selection
        if ! command -v whiptail &> /dev/null; then
            echo -e "${WARNING}Installing whiptail for selection menu...${RESET}"
            apt-get update -qq && apt-get install -y whiptail -qq > /dev/null 2>&1
        fi
        
        # Build whiptail checklist
        local whiptail_items=()
        for i in "${!all_stacks[@]}"; do
            local _sp="${all_stacks[$i]}"
            local _dom
            _dom=$(get_stack_info "$_sp")
            whiptail_items+=("$i" "$_sp | Domain: $_dom" "OFF")
        done

        local selected_indices
        selected_indices=$(NEWT_COLORS='
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
' whiptail --title " Select Stack to Reconfigure " \
            --checklist "Choose which stack(s) to reconfigure:" \
            15 100 ${#all_stacks[@]} \
            "${whiptail_items[@]}" \
            3>&1 1>&2 2>&3)

        local _wt_exit=$?
        if [ $_wt_exit -ne 0 ] || [ -z "$selected_indices" ]; then
            echo -e "${INFO}Reconfigure cancelled${RESET}"
            return
        fi

        for idx in $selected_indices; do
            idx="${idx//\"/}"
            RECONFIG_STACK_DIR="${all_stacks[$idx]}"

            while true; do
                load_stack_ports_from_containers "$RECONFIG_STACK_DIR"
                parse_stack_configuration "$RECONFIG_STACK_DIR"

                echo -e "\n${ACCENT}>> Reconfiguring: $(basename \"$RECONFIG_STACK_DIR\")${RESET}"
                echo -e "   ${INFO}Domain: $CURRENT_DOMAIN${RESET}"

                if [ ${#CURRENT_FEATURES[@]} -gt 0 ]; then
                    echo -e "   ${SUCCESS}Features installed:${RESET}"
                    for feature in "${CURRENT_FEATURES[@]}"; do echo -e "      \u2713 $feature"; done
                else
                    echo -e "   ${INFO}No optional features installed${RESET}"
                fi

                if [ ${#CURRENT_BRIDGES[@]} -gt 0 ]; then
                    echo -e "   ${SUCCESS}Bridges installed:${RESET}"
                    for bridge in "${CURRENT_BRIDGES[@]}"; do echo -e "      \u2713 $bridge"; done
                else
                    echo -e "   ${INFO}No bridges installed${RESET}"
                fi

                echo -e "\n${ACCENT}>> Reconfiguration Options:${RESET}\n"
                echo -e "   ${INFO}1)${RESET} Modify domain"
                echo -e "   ${INFO}2)${RESET} Add/remove features"
                echo -e "   ${INFO}3)${RESET} Add/remove bridges"
                echo -e "   ${INFO}0)${RESET} Done"
                echo -ne "\nSelect option (0-3): ${CHOICE_COLOR}"
                read -r reconfig_choice
                echo -e "${RESET}"

                case "$reconfig_choice" in
                    1) manage_domain   "$RECONFIG_STACK_DIR" ;;
                    2) manage_features "$RECONFIG_STACK_DIR" ;;
                    3) manage_bridges  "$RECONFIG_STACK_DIR" ;;
                    0) break ;;
                    *) echo -e "   ${ERROR}Invalid selection${RESET}" ;;
                esac
            done

            echo -e "\n${SUCCESS}\u2713 Reconfiguration for $(basename \"$RECONFIG_STACK_DIR\") complete${RESET}"
        done
    
    fi
    echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
    read -r
}



_validate_compose() {
    local dir="$1"
    local err
    err=$(cd "$dir" && docker compose config -q 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "   ${ERROR}compose.yaml is corrupt:${RESET}"
        echo "$err" | grep -oP "line [0-9]+: .+" | head -3 | sed 's/^/      /'
        echo -e "   ${WARNING}Repair: Reconfigure -> Add/remove bridges${RESET}"
        return 1
    fi
    return 0
}

################################################################################

# Run update check before showing anything else
check_for_updates

# Pre-install menu
draw_header
# Pre-install menu with loop for invalid selections
while true; do
    echo -e "\n${ACCENT}>> What would you like to do?${RESET}\n"
    echo -e "   ${INFO}1)${RESET} ${SUCCESS}Install${RESET}       — Deploy a new Matrix stack"
    echo -e "   ${INFO}2)${RESET} ${SUCCESS}Update${RESET}        — Pull latest images and restart the stack"
    echo -e "   ${INFO}3)${RESET} ${ORANGE}Reconfigure${RESET}   — Re-run config steps without deleting data"
    echo -e "   ${INFO}4)${RESET} ${SUCCESS}Uninstall${RESET}     — Remove the Matrix stack and all data"
    echo -e "   ${INFO}5)${RESET} ${SUCCESS}Verify${RESET}        — Check integrity of an existing installation"
    echo -e "   ${INFO}6)${RESET} ${ACCENT}Logs${RESET}          — View container logs for troubleshooting"
    echo -e "   ${INFO}7)${RESET} ${BANNER}Diagnostics${RESET}   — Collect system info for troubleshooting"
    echo -e "   ${INFO}8)${RESET} ${CODE}Changelog${RESET}     — View latest version changelog"
    echo -e ""
    echo -e "   ${INFO}0)${RESET} ${ERROR}Exit${RESET}"
    echo -e ""
    ask_choice MENU_SELECT "Selection (0-8): " 0 1 2 3 4 5 6 7 8

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
            
            # Find all stacks
            mapfile -t all_stacks < <(find_all_matrix_stacks)
            
            # Clean up empty elements from mapfile
            cleaned_stacks=()
            for stack in "${all_stacks[@]}"; do
                if [ -n "$stack" ]; then
                    cleaned_stacks+=("$stack")
                fi
            done
            all_stacks=("${cleaned_stacks[@]}")
            
            if [ ${#all_stacks[@]} -eq 0 ]; then
                # No stacks found
                echo -e "${WARNING}No resources found.${RESET}"
                echo -ne "Press Enter to return to main menu: "
                read -r
                draw_header
                continue
            elif [ ${#all_stacks[@]} -eq 1 ]; then
                # Single stack found - update it directly
                UPDATE_STACK_DIR="${all_stacks[0]}"
                
                if [ -f "$UPDATE_STACK_DIR/compose.yaml" ]; then
                    # Load ports from running containers (more reliable than metadata file)
                    load_stack_ports_from_containers "$UPDATE_STACK_DIR"
                    
                    echo -e "   ${INFO}Updating stack: $UPDATE_STACK_DIR${RESET}"
                    _validate_compose "$UPDATE_STACK_DIR" || { echo -e "\n${INFO}Press Enter to return to menu...${RESET}"; read -r; draw_header; continue 2; }
                    cd "$UPDATE_STACK_DIR"
                    echo -e "   ${INFO}Pulling latest images...${RESET}"
                    docker compose pull
                    echo -e "   ${INFO}Restarting stack...${RESET}"
                    docker compose up -d --remove-orphans
                    echo -e "\n${SUCCESS}>> Update complete for $(basename $UPDATE_STACK_DIR)${RESET}"
                else
                    echo -e "   ${ERROR}No compose.yaml found at $UPDATE_STACK_DIR${RESET}"
                fi
            elif [ ${#all_stacks[@]} -gt 1 ]; then
                # Multiple stacks found - show whiptail checklist for selection
                if ! command -v whiptail &> /dev/null; then
                    echo -e "${WARNING}Installing whiptail for selection menu...${RESET}"
                    apt-get update -qq && apt-get install -y whiptail -qq > /dev/null 2>&1
                fi
                
                echo -e "${INFO}Found ${#all_stacks[@]} installations. Select which to update:${RESET}\n"
                
                # Build whiptail checklist
                whiptail_items=()
                for i in "${!all_stacks[@]}"; do
                    stack_path="${all_stacks[$i]}"
                    domain=$(get_stack_info "$stack_path")
                    suffix=$(get_stack_resources "$stack_path")
                    label="$stack_path | Domain: $domain"
                    whiptail_items+=("$i" "$label" "OFF")
                done
                
                # Show whiptail checklist (allows multiple selections)
                selected_indices=$(NEWT_COLORS='
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
' whiptail --title "Select Stacks to Update" \
                    --checklist "Choose which stacks to update:" \
                    15 100 ${#all_stacks[@]} \
                    "${whiptail_items[@]}" \
                    3>&1 1>&2 2>&3)
                
                exit_code=$?
                if [ $exit_code -ne 0 ] || [ -z "$selected_indices" ]; then
                    echo -e "${INFO}Update cancelled${RESET}"
                else
                    # Parse selected indices and update each one
                    for idx in $selected_indices; do
                        # Remove quotes from whiptail output
                        idx=${idx%\"}
                        idx=${idx#\"}
                        
                        UPDATE_STACK_DIR="${all_stacks[$idx]}"
                        
                        if [ -f "$UPDATE_STACK_DIR/compose.yaml" ]; then
                            # Load ports from running containers (more reliable than metadata file)
                            load_stack_ports_from_containers "$UPDATE_STACK_DIR"
                            
                            echo -e "   ${INFO}Updating: $(basename $UPDATE_STACK_DIR)${RESET}"
                            cd "$UPDATE_STACK_DIR"
                            _validate_compose "$UPDATE_STACK_DIR" || { cd - >/dev/null 2>&1; continue; }
                            echo -e "      ${INFO}Pulling latest images...${RESET}"
                            docker compose pull
                            echo -e "      ${INFO}Restarting...${RESET}"
                            docker compose up -d --remove-orphans
                            echo -e "      ${SUCCESS}✓ Complete${RESET}\n"
                        else
                            echo -e "      ${ERROR}✗ No compose.yaml found${RESET}\n"
                        fi
                    done
                    echo -e "${SUCCESS}>> Update complete${RESET}"
                fi
            fi
            echo -e "\n${INFO}Press Enter to return to menu...${RESET}"
            read -r
            draw_header
            ;;
        3)
            reconfigure_stack
            draw_header
            ;;
        4)
            run_uninstall
            draw_header
            ;;
        5)
            run_verify
            draw_header
            ;;
        6)
            run_logs
            draw_header
            ;;
        7)
            run_diagnostics
            draw_header
            ;;
        8)
            show_changelog
            draw_header
            ;;
    esac
done

################################################################################
#                         END OF SCRIPT                                        #
################################################################################