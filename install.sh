#!/bin/bash

# STAR Tunnel - Complete Integration of HAProxy and Nebula Tunnel
# Version: 5.0.0
# Author: MrStar
# Telegram: @MoriiStar

# ========================
# GLOBAL CONFIGURATIONS
# ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
STAR_DIR="/etc/star"
OBFS4_DIR="/etc/obfs4"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
HAPROXY_BACKUP="/etc/haproxy/haproxy.cfg.bak"
NETPLAN_DIR="/etc/netplan"
CONNECTORS_DIR="/root/connectors"

# Server Info
SERVER_IP=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1")
SERVER_COUNTRY=$(curl -sS https://ipapi.co/country_name)
SERVER_ISP=$(curl -sS https://ipapi.co/org)

# ========================
# CORE FUNCTIONS
# ========================

display_banner() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
   _____ _______    _____   _____ 
  / ____|__   __|  / ____| / ____|
 | (___    | |    | |  __ | |  __ 
  \___ \   | |    | | |_ || | |_ |
  ____) |  | |    | |__| || |__| |
 |_____/   |_|     \_____| \_____|
EOF
    echo -e "${NC}"
    echo -e "${CYAN}Advanced Tunnel & Proxy Management System${NC}"
    echo -e "${YELLOW}Version: 5.0.0 | Telegram: @AminiDev${NC}"
    echo "----------------------------------------------"
    echo -e "${GREEN}Server IP: ${SERVER_IP} | Country: ${SERVER_COUNTRY} | ISP: ${SERVER_ISP}${NC}"
    echo "----------------------------------------------"
}

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}Error: This script must be run as root${NC}" && exit 1
}

install_dependencies() {
    echo -e "${YELLOW}Checking and installing dependencies...${NC}"
    
    local deps=("jq" "obfs4proxy" "haproxy" "netplan.io" "iproute2" "screen" "openssl" "curl")
    local to_install=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            to_install+=("$dep")
        fi
    done

    if [ ${#to_install[@]} -ne 0 ]; then
        apt-get update
        if ! apt-get install -y "${to_install[@]}"; then
            echo -e "${RED}Failed to install dependencies. Trying alternative approach...${NC}"
            for dep in "${to_install[@]}"; do
                if ! apt-get install -y $dep; then
                    echo -e "${RED}Critical error: Failed to install $dep${NC}"
                    exit 1
                fi
            done
        fi
    fi
    
    mkdir -p {$STAR_DIR,$OBFS4_DIR,$NETPLAN_DIR,$CONNECTORS_DIR}
}

# ========================
# TUNNEL FUNCTIONS
# ========================

configure_obfs4() {
    local cert="$OBFS4_DIR/obfs4_cert"
    local key="$OBFS4_DIR/obfs4_key"
    
    if [[ ! -f $cert || ! -f $key ]]; then
        echo -e "${YELLOW}Generating new obfs4 certificates...${NC}"
        openssl genpkey -algorithm RSA -out "$key" -pkeyopt rsa_keygen_bits:2048 || {
            echo -e "${RED}Failed to generate private key${NC}"; return 1
        }
        
        openssl req -new -x509 -key "$key" -out "$cert" -days 365 -subj "/CN=obfs4" || {
            echo -e "${RED}Failed to generate certificate${NC}"; return 1
        }
    fi
    
    cat <<EOL > "$OBFS4_DIR/obfs4.json"
{
    "transport": "obfs4",
    "bind_address": "0.0.0.0:443",
    "cert": "$cert",
    "iat-mode": "0",
    "log_level": "INFO",
    "options": {
        "node-id": "$(cat /etc/hostname)",
        "private-key": "$(cat "$key")"
    }
}
EOL
    echo -e "${GREEN}Obfs4 configuration complete${NC}"
}

start_obfs4() {
    echo -e "${YELLOW}Starting obfs4 service...${NC}"
    pkill -f obfs4proxy
    nohup obfs4proxy -logLevel INFO -enableLogging > "$STAR_DIR/obfs4.log" 2>&1 &
    [[ $? -eq 0 ]] && echo -e "${GREEN}Obfs4 started successfully${NC}" || echo -e "${RED}Failed to start obfs4${NC}"
}

create_tunnel() {
    local type=$1
    display_banner
    
    echo -e "${CYAN}Creating ${type^^} Tunnel Configuration${NC}"
    
    read -p "Enter local IP: " local_ip
    read -p "Enter remote IP: " remote_ip
    read -p "Enter IPv6 address (or 'auto' for automatic): " ipv6_input
    
    if [[ "$ipv6_input" == "auto" ]]; then
        local tunnel_num=$(find_next_tunnel_num)
        if [[ "$type" == "iran" ]]; then
            ipv6_addr="fd25:2895:dc$(printf "%02d" $tunnel_num)::1"
        else
            ipv6_addr="fd25:2895:dc$(printf "%02d" $tunnel_num)::2"
        fi
        echo -e "${YELLOW}Using automatic IPv6: ${ipv6_addr}${NC}"
    else
        ipv6_addr="$ipv6_input"
    fi
    
    local config_file="$NETPLAN_DIR/star_${type}_${tunnel_num}.yaml"
    
    cat <<EOL > "$config_file"
network:
  version: 2
  tunnels:
    tunnel_${type}_${tunnel_num}:
      mode: sit
      local: $local_ip
      remote: $remote_ip
      addresses:
        - ${ipv6_addr}/64
EOL
    
    netplan apply
    
    # Create connector script
    local connector_file="$CONNECTORS_DIR/${type}_${tunnel_num}.sh"
    if [[ "$type" == "iran" ]]; then
        echo "ping6 ${ipv6_addr%::1}::2" > "$connector_file"
    else
        echo "ping6 ${ipv6_addr%::2}::1" > "$connector_file"
    fi
    
    chmod +x "$connector_file"
    screen -dmS "star_${type}_${tunnel_num}" bash -c "$connector_file"
    
    echo -e "${GREEN}${type^^} tunnel ${tunnel_num} created successfully!${NC}"
    echo -e "${YELLOW}IPv6 Address: ${ipv6_addr}${NC}"
    echo -e "${BLUE}Connector running in screen session: star_${type}_${tunnel_num}${NC}"
}

# ========================
# HAPROXY FUNCTIONS
# ========================

setup_haproxy() {
    echo -e "${YELLOW}Configuring HAProxy...${NC}"
    
    if [[ ! -f "$HAPROXY_CFG" ]]; then
        cat <<EOL > "$HAPROXY_CFG"
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http
EOL
    fi
    
    systemctl restart haproxy
    echo -e "${GREEN}HAProxy configuration complete${NC}"
}

add_haproxy_service() {
    display_banner
    echo -e "${CYAN}Add HAProxy Service${NC}"
    
    read -p "Enter frontend port: " front_port
    read -p "Enter backend servers (IP:PORT,IP:PORT,...): " backend_servers
    
    IFS=',' read -ra servers <<< "$backend_servers"
    
    # Add frontend
    echo -e "\nfrontend star_front_$front_port" >> "$HAPROXY_CFG"
    echo "    bind *:$front_port" >> "$HAPROXY_CFG"
    echo "    default_backend star_back_$front_port" >> "$HAPROXY_CFG"
    
    # Add backend
    echo -e "\nbackend star_back_$front_port" >> "$HAPROXY_CFG"
    for i in "${!servers[@]}"; do
        local server_num=$((i+1))
        local status=""
        [[ $i -gt 0 ]] && status=" backup"
        echo "    server server$server_num ${servers[$i]} check$status" >> "$HAPROXY_CFG"
    done
    
    # Validate config
    if haproxy -c -f "$HAPROXY_CFG"; then
        systemctl restart haproxy
        echo -e "${GREEN}Service added successfully!${NC}"
    else
        echo -e "${RED}Invalid configuration! Changes not applied.${NC}"
        cp "$HAPROXY_BACKUP" "$HAPROXY_CFG"
    fi
}

# ========================
# MAIN MENU SYSTEM
# ========================

tunnel_menu() {
    while true; do
        display_banner
        echo -e "${CYAN}TUNNEL MANAGEMENT${NC}"
        echo -e "1) Create Iran Tunnel"
        echo -e "2) Create Kharej Tunnel"
        echo -e "3) List Active Tunnels"
        echo -e "4) Test Tunnel Connection"
        echo -e "5) Remove Tunnel"
        echo -e "0) Back to Main Menu"
        
        read -p "Select option: " choice
        case $choice in
            1) create_tunnel "iran" ;;
            2) create_tunnel "kharej" ;;
            3) list_tunnels ;;
            4) test_tunnel ;;
            5) remove_tunnel ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

haproxy_menu() {
    while true; do
        display_banner
        echo -e "${CYAN}HAPROXY MANAGEMENT${NC}"
        echo -e "1) Install HAProxy"
        echo -e "2) Add Load Balancing Service"
        echo -e "3) Show Current Config"
        echo -e "4) Remove Service"
        echo -e "5) Restart HAProxy"
        echo -e "0) Back to Main Menu"
        
        read -p "Select option: " choice
        case $choice in
            1) install_haproxy ;;
            2) add_haproxy_service ;;
            3) show_haproxy_config ;;
            4) remove_haproxy_service ;;
            5) systemctl restart haproxy ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

main_menu() {
    check_root
    install_dependencies
    configure_obfs4
    
    while true; do
        display_banner
        echo -e "${GREEN}MAIN MENU${NC}"
        echo -e "1) Tunnel Management"
        echo -e "2) HAProxy Management"
        echo -e "3) System Tools"
        echo -e "0) Exit"
        
        read -p "Select option: " choice
        case $choice in
            1) tunnel_menu ;;
            2) haproxy_menu ;;
            3) system_tools_menu ;;
            0) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ========================
# START THE APPLICATION
# ========================
main_menu
