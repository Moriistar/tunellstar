#!/bin/bash

# ============================================================================
# Lena Tunnel v2.0 - Advanced VxLAN Tunnel Manager
# Developed by: Moriistar
# Channel: @ServerStar_ir
# Features: IPv4/IPv6 Support, Multi-tunnel, Load Balancing
# ============================================================================

# ---------------- DEPENDENCIES ----------------
echo "[*] Installing prerequisites..."
sudo apt update -y >/dev/null 2>&1
sudo apt install -y iproute2 net-tools grep awk sudo iputils-ping jq curl haproxy systemd >/dev/null 2>&1

# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------- GLOBAL VARIABLES ----------------
CONFIG_DIR="/etc/lena-tunnel"
TUNNEL_CONFIG="$CONFIG_DIR/tunnels.json"
SERVICE_PREFIX="lena-tunnel"
LOG_FILE="/var/log/lena-tunnel.log"

# Create config directory
mkdir -p "$CONFIG_DIR"

# ---------------- LOGGING ----------------
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------------- UTILITY FUNCTIONS ----------------
detect_ip_version() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ipv4"
    elif [[ $ip =~ ^[0-9a-fA-F:]+$ ]]; then
        echo "ipv6"
    else
        echo "unknown"
    fi
}

get_local_ip() {
    local version=$1
    if [[ "$version" == "ipv4" ]]; then
        hostname -I | awk '{print $1}'
    else
        ip -6 addr show scope global | grep -oP '(?<=inet6\s)[\da-f:]+' | head -1
    fi
}

check_tunnel_status() {
    local tunnel_name=$1
    systemctl is-active --quiet "${SERVICE_PREFIX}-${tunnel_name}.service" && echo "Active" || echo "Inactive"
}

# ---------------- MENU FUNCTIONS ----------------
show_header() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" 2>/dev/null | jq -r '.country // "Unknown"')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" 2>/dev/null | jq -r '.isp // "Unknown"')

    echo "+-----------------------------------------------------------------------------+"
    echo "| ██╗     ███████╗███╗   ██╗ █████╗     ██╗   ██╗██████╗    ██████╗        |"
    echo "| ██║     ██╔════╝████╗  ██║██╔══██╗    ██║   ██║╚════██╗  ██╔═████╗       |"
    echo "| ██║     █████╗  ██╔██╗ ██║███████║    ██║   ██║ █████╔╝  ██║██╔██║       |"
    echo "| ██║     ██╔══╝  ██║╚██╗██║██╔══██║    ╚██╗ ██╔╝██╔═══╝   ████╔╝██║       |"
    echo "| ███████╗███████╗██║ ╚████║██║  ██║     ╚████╔╝ ███████╗██╗╚██████╔╝       |"
    echo "| ╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝      ╚═══╝  ╚══════╝╚═╝ ╚═════╝        |"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "| Telegram: ${MAGENTA}@ServerStar_ir${NC} | Version: ${GREEN}2.0 Advanced${NC} | Status: ${CYAN}Enhanced${NC}"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-----------------------------------------------------------------------------+"
}

main_menu() {
    show_header
    echo -e "|${YELLOW}Main Menu - Select Option:${NC}"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "1${GREEN}►${NC} Create New Tunnel"
    echo -e "2${BLUE}►${NC} Manage Existing Tunnels"
    echo -e "3${CYAN}►${NC} Monitor Tunnels"
    echo -e "4${MAGENTA}►${NC} Advanced Settings"
    echo -e "5${RED}►${NC} Uninstall All Tunnels"
    echo -e "6${YELLOW}►${NC} Install BBR"
    echo -e "7${GREEN}►${NC} Exit"
    echo "+-----------------------------------------------------------------------------+"
}

# ---------------- TUNNEL CREATION ----------------
create_tunnel() {
    echo -e "${GREEN}Creating New Tunnel${NC}"
    echo "========================"
    
    # Tunnel name
    read -p "Enter tunnel name: " tunnel_name
    if [[ -z "$tunnel_name" ]]; then
        tunnel_name="tunnel-$(date +%s)"
    fi
    
    # Server role selection
    echo ""
    echo "Select server role:"
    echo "1) Iran Server"
    echo "2) Kharej Server"
    read -p "Enter choice (1-2): " role_choice
    
    # IP version selection
    echo ""
    echo "Select IP version:"
    echo "1) IPv4"
    echo "2) IPv6"
    echo "3) Auto-detect"
    read -p "Enter choice (1-3): " ip_version_choice
    
    case $ip_version_choice in
        1) ip_version="ipv4";;
        2) ip_version="ipv6";;
        3) ip_version="auto";;
        *) ip_version="auto";;
    esac
    
    # Get IP addresses
    if [[ "$role_choice" == "1" ]]; then
        read -p "Enter Iran IP: " iran_ip
        read -p "Enter Kharej IP: " kharej_ip
        local_role="iran"
        local_ip=$iran_ip
        remote_ip=$kharej_ip
        vxlan_ip="30.0.0.1/24"
    else
        read -p "Enter Iran IP: " iran_ip
        read -p "Enter Kharej IP: " kharej_ip
        local_role="kharej"
        local_ip=$kharej_ip
        remote_ip=$iran_ip
        vxlan_ip="30.0.0.2/24"
    fi
    
    # Port selection
    while true; do
        read -p "Enter tunnel port (1-65535): " tunnel_port
        if [[ $tunnel_port =~ ^[0-9]+$ ]] && (( tunnel_port >= 1 && tunnel_port <= 65535 )); then
            break
        else
            echo "Invalid port. Please try again."
        fi
    done
    
    # VNI selection
    read -p "Enter VNI (default: 88): " vni
    vni=${vni:-88}
    
    # HAProxy configuration
    echo ""
    read -p "Configure HAProxy for port forwarding? (y/n): " haproxy_choice
    
    # Create tunnel configuration
    create_tunnel_config "$tunnel_name" "$local_role" "$ip_version" "$local_ip" "$remote_ip" "$tunnel_port" "$vni" "$vxlan_ip" "$haproxy_choice"
    
    # Setup tunnel
    setup_tunnel "$tunnel_name"
    
    echo -e "${GREEN}Tunnel '$tunnel_name' created successfully!${NC}"
    echo -e "${CYAN}Tunnel IP: $vxlan_ip${NC}"
    
    read -p "Press Enter to continue..."
}

create_tunnel_config() {
    local name=$1 role=$2 ip_ver=$3 local_ip=$4 remote_ip=$5 port=$6 vni=$7 vxlan_ip=$8 haproxy=$9
    
    # Initialize tunnels.json if not exists
    if [[ ! -f "$TUNNEL_CONFIG" ]]; then
        echo '{}' > "$TUNNEL_CONFIG"
    fi
    
    # Add tunnel configuration
    jq --arg name "$name" --arg role "$role" --arg ip_ver "$ip_ver" --arg local_ip "$local_ip" \
       --arg remote_ip "$remote_ip" --arg port "$port" --arg vni "$vni" --arg vxlan_ip "$vxlan_ip" \
       --arg haproxy "$haproxy" --arg status "active" --arg created "$(date -Iseconds)" \
       '.[$name] = {
           "role": $role,
           "ip_version": $ip_ver,
           "local_ip": $local_ip,
           "remote_ip": $remote_ip,
           "port": ($port | tonumber),
           "vni": ($vni | tonumber),
           "vxlan_ip": $vxlan_ip,
           "haproxy": $haproxy,
           "status": $status,
           "created": $created
       }' "$TUNNEL_CONFIG" > "$TUNNEL_CONFIG.tmp" && mv "$TUNNEL_CONFIG.tmp" "$TUNNEL_CONFIG"
}

setup_tunnel() {
    local tunnel_name=$1
    local config=$(jq -r ".\"$tunnel_name\"" "$TUNNEL_CONFIG")
    
    if [[ "$config" == "null" ]]; then
        echo "Tunnel configuration not found!"
        return 1
    fi
    
    # Extract configuration
    local role=$(echo "$config" | jq -r '.role')
    local ip_version=$(echo "$config" | jq -r '.ip_version')
    local local_ip=$(echo "$config" | jq -r '.local_ip')
    local remote_ip=$(echo "$config" | jq -r '.remote_ip')
    local port=$(echo "$config" | jq -r '.port')
    local vni=$(echo "$config" | jq -r '.vni')
    local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip')
    local haproxy=$(echo "$config" | jq -r '.haproxy')
    
    # Detect interface
    local interface=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
    local vxlan_if="vxlan${vni}"
    
    # Create setup script
    cat <<EOF > "/usr/local/bin/setup_${tunnel_name}.sh"
#!/bin/bash

# Setup VXLAN tunnel: $tunnel_name
VNI=$vni
VXLAN_IF="$vxlan_if"
LOCAL_IP="$local_ip"
REMOTE_IP="$remote_ip"
PORT=$port
VXLAN_IP="$vxlan_ip"
INTERFACE="$interface"

# Create VXLAN interface
ip link add \$VXLAN_IF type vxlan id \$VNI local \$LOCAL_IP remote \$REMOTE_IP dev \$INTERFACE dstport \$PORT nolearning
ip addr add \$VXLAN_IP dev \$VXLAN_IF
ip link set \$VXLAN_IF up

# Add firewall rules
iptables -I INPUT 1 -p udp --dport \$PORT -j ACCEPT
iptables -I INPUT 1 -s \$REMOTE_IP -j ACCEPT
iptables -I INPUT 1 -s \${VXLAN_IP%/*} -j ACCEPT

echo "[$(date)] Tunnel $tunnel_name started successfully" >> "$LOG_FILE"
EOF
    
    chmod +x "/usr/local/bin/setup_${tunnel_name}.sh"
    
    # Create systemd service
    cat <<EOF > "/etc/systemd/system/${SERVICE_PREFIX}-${tunnel_name}.service"
[Unit]
Description=Lena Tunnel - $tunnel_name
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/setup_${tunnel_name}.sh
ExecStop=/usr/local/bin/cleanup_${tunnel_name}.sh

[Install]
WantedBy=multi-user.target
EOF
    
    # Create cleanup script
    cat <<EOF > "/usr/local/bin/cleanup_${tunnel_name}.sh"
#!/bin/bash
ip link del vxlan${vni} 2>/dev/null || true
echo "[$(date)] Tunnel $tunnel_name stopped" >> "$LOG_FILE"
EOF
    
    chmod +x "/usr/local/bin/cleanup_${tunnel_name}.sh"
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable "${SERVICE_PREFIX}-${tunnel_name}.service"
    systemctl start "${SERVICE_PREFIX}-${tunnel_name}.service"
    
    # Configure HAProxy if requested
    if [[ "$haproxy" == "y" ]]; then
        configure_haproxy "$tunnel_name"
    fi
    
    log_message "Tunnel $tunnel_name setup completed"
}

# ---------------- HAPROXY CONFIGURATION ----------------
configure_haproxy() {
    local tunnel_name=$1
    
    echo "Configuring HAProxy for tunnel: $tunnel_name"
    read -p "Enter ports for forwarding (comma-separated): " ports
    
    local config=$(jq -r ".\"$tunnel_name\"" "$TUNNEL_CONFIG")
    local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
    
    # Backup existing config
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-$(date +%s) 2>/dev/null
    
    # Create new config
    cat <<EOF > /etc/haproxy/haproxy.cfg
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode tcp
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

# Statistics page
listen stats
    bind *:8080
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

EOF
    
    # Add port configurations
    IFS=',' read -ra port_array <<< "$ports"
    for port in "${port_array[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat <<EOF >> /etc/haproxy/haproxy.cfg

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
    balance roundrobin
    server tunnel_$tunnel_name $vxlan_ip:$port check

EOF
    done
    
    # Validate and restart HAProxy
    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        systemctl restart haproxy
        systemctl enable haproxy
        echo -e "${GREEN}HAProxy configured successfully!${NC}"
        echo -e "${CYAN}Statistics available at: http://$(hostname -I | awk '{print $1}'):8080/stats${NC}"
    else
        echo -e "${RED}HAProxy configuration failed!${NC}"
    fi
}

# ---------------- TUNNEL MANAGEMENT ----------------
manage_tunnels() {
    while true; do
        show_header
        echo -e "|${YELLOW}Tunnel Management${NC}"
        echo "+-----------------------------------------------------------------------------+"
        
        if [[ ! -f "$TUNNEL_CONFIG" ]] || [[ "$(jq 'keys | length' "$TUNNEL_CONFIG" 2>/dev/null)" == "0" ]]; then
            echo -e "${RED}No tunnels found!${NC}"
            read -p "Press Enter to return to main menu..."
            return
        fi
        
        echo -e "Active Tunnels:"
        echo "+-----------------------------------------------------------------------------+"
        
        # List tunnels
        local counter=1
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local status=$(check_tunnel_status "$tunnel")
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local role=$(echo "$config" | jq -r '.role')
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip')
            
            if [[ "$status" == "Active" ]]; then
                echo -e "$counter) ${GREEN}$tunnel${NC} [$role] - $vxlan_ip (${GREEN}$status${NC})"
            else
                echo -e "$counter) ${RED}$tunnel${NC} [$role] - $vxlan_ip (${RED}$status${NC})"
            fi
            ((counter++))
        done
        
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1${GREEN}►${NC} Start/Stop Tunnel"
        echo -e "2${BLUE}►${NC} Delete Tunnel"
        echo -e "3${CYAN}►${NC} View Tunnel Details"
        echo -e "4${YELLOW}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " manage_choice
        
        case $manage_choice in
            1) toggle_tunnel ;;
            2) delete_tunnel ;;
            3) view_tunnel_details ;;
            4) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

toggle_tunnel() {
    echo "Available tunnels:"
    jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | nl
    read -p "Enter tunnel name: " tunnel_name
    
    if ! jq -e ".\"$tunnel_name\"" "$TUNNEL_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}Tunnel not found!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    local status=$(check_tunnel_status "$tunnel_name")
    
    if [[ "$status" == "Active" ]]; then
        systemctl stop "${SERVICE_PREFIX}-${tunnel_name}.service"
        echo -e "${YELLOW}Tunnel '$tunnel_name' stopped.${NC}"
    else
        systemctl start "${SERVICE_PREFIX}-${tunnel_name}.service"
        echo -e "${GREEN}Tunnel '$tunnel_name' started.${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

delete_tunnel() {
    echo "Available tunnels:"
    jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | nl
    read -p "Enter tunnel name to delete: " tunnel_name
    
    if ! jq -e ".\"$tunnel_name\"" "$TUNNEL_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}Tunnel not found!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Are you sure you want to delete tunnel '$tunnel_name'? (y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # Stop and disable service
        systemctl stop "${SERVICE_PREFIX}-${tunnel_name}.service" 2>/dev/null
        systemctl disable "${SERVICE_PREFIX}-${tunnel_name}.service" 2>/dev/null
        
        # Remove files
        rm -f "/etc/systemd/system/${SERVICE_PREFIX}-${tunnel_name}.service"
        rm -f "/usr/local/bin/setup_${tunnel_name}.sh"
        rm -f "/usr/local/bin/cleanup_${tunnel_name}.sh"
        
        # Remove from configuration
        jq "del(.\"$tunnel_name\")" "$TUNNEL_CONFIG" > "$TUNNEL_CONFIG.tmp" && mv "$TUNNEL_CONFIG.tmp" "$TUNNEL_CONFIG"
        
        systemctl daemon-reload
        
        echo -e "${GREEN}Tunnel '$tunnel_name' deleted successfully!${NC}"
        log_message "Tunnel $tunnel_name deleted"
    else
        echo "Operation cancelled."
    fi
    
    read -p "Press Enter to continue..."
}

view_tunnel_details() {
    echo "Available tunnels:"
    jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | nl
    read -p "Enter tunnel name: " tunnel_name
    
    if ! jq -e ".\"$tunnel_name\"" "$TUNNEL_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}Tunnel not found!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    local config=$(jq -r ".\"$tunnel_name\"" "$TUNNEL_CONFIG")
    local status=$(check_tunnel_status "$tunnel_name")
    
    echo -e "\n${CYAN}Tunnel Details: $tunnel_name${NC}"
    echo "================================="
    echo "Role: $(echo "$config" | jq -r '.role')"
    echo "IP Version: $(echo "$config" | jq -r '.ip_version')"
    echo "Local IP: $(echo "$config" | jq -r '.local_ip')"
    echo "Remote IP: $(echo "$config" | jq -r '.remote_ip')"
    echo "Port: $(echo "$config" | jq -r '.port')"
    echo "VNI: $(echo "$config" | jq -r '.vni')"
    echo "VXLAN IP: $(echo "$config" | jq -r '.vxlan_ip')"
    echo "HAProxy: $(echo "$config" | jq -r '.haproxy')"
    echo "Status: $status"
    echo "Created: $(echo "$config" | jq -r '.created')"
    
    read -p "Press Enter to continue..."
}

# ---------------- MONITORING ----------------
monitor_tunnels() {
    while true; do
        show_header
        echo -e "|${YELLOW}Tunnel Monitoring${NC}"
        echo "+-----------------------------------------------------------------------------+"
        
        if [[ ! -f "$TUNNEL_CONFIG" ]] || [[ "$(jq 'keys | length' "$TUNNEL_CONFIG" 2>/dev/null)" == "0" ]]; then
            echo -e "${RED}No tunnels found!${NC}"
            read -p "Press Enter to return to main menu..."
            return
        fi
        
        # Show tunnel statistics
        echo -e "${CYAN}Tunnel Status Overview:${NC}"
        echo "+-----------------------------------------------------------------------------+"
        printf "%-15s %-10s %-15s %-10s %-10s\n" "NAME" "STATUS" "VXLAN_IP" "PORT" "VNI"
        echo "+-----------------------------------------------------------------------------+"
        
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local status=$(check_tunnel_status "$tunnel")
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
            local port=$(echo "$config" | jq -r '.port')
            local vni=$(echo "$config" | jq -r '.vni')
            
            if [[ "$status" == "Active" ]]; then
                printf "%-15s ${GREEN}%-10s${NC} %-15s %-10s %-10s\n" "$tunnel" "$status" "$vxlan_ip" "$port" "$vni"
            else
                printf "%-15s ${RED}%-10s${NC} %-15s %-10s %-10s\n" "$tunnel" "$status" "$vxlan_ip" "$port" "$vni"
            fi
        done
        
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1${GREEN}►${NC} Real-time Monitoring"
        echo -e "2${BLUE}►${NC} View Logs"
        echo -e "3${CYAN}►${NC} Network Statistics"
        echo -e "4${YELLOW}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " monitor_choice
        
        case $monitor_choice in
            1) realtime_monitoring ;;
            2) view_logs ;;
            3) network_stats ;;
            4) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

realtime_monitoring() {
    echo -e "${CYAN}Real-time Monitoring (Press Ctrl+C to stop)${NC}"
    echo "==========================================="
    
    while true; do
        clear
        echo -e "${CYAN}Lena Tunnel - Real-time Status${NC}"
        echo "$(date)"
        echo "==========================================="
        
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local status=$(check_tunnel_status "$tunnel")
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
            local vni=$(echo "$config" | jq -r '.vni')
            
            echo -e "Tunnel: ${YELLOW}$tunnel${NC}"
            echo -e "Status: $([[ "$status" == "Active" ]] && echo -e "${GREEN}$status${NC}" || echo -e "${RED}$status${NC}")"
            echo -e "VXLAN IP: $vxlan_ip"
            
            if [[ "$status" == "Active" ]]; then
                # Check if interface exists and get stats
                if ip link show "vxlan${vni}" >/dev/null 2>&1; then
                    local stats=$(ip -s link show "vxlan${vni}" | grep -A2 "RX:")
                    echo -e "Interface: ${GREEN}UP${NC}"
                    echo "$stats"
                else
                    echo -e "Interface: ${RED}DOWN${NC}"
                fi
            fi
            echo "-------------------------------------------"
        done
        
        sleep 3
    done
}

view_logs() {
    echo -e "${CYAN}Tunnel Logs${NC}"
    echo "============"
    
    if [[ -f "$LOG_FILE" ]]; then
        echo "Recent log entries:"
        tail -n 50 "$LOG_FILE"
    else
        echo "No log file found."
    fi
    
    read -p "Press Enter to continue..."
}

network_stats() {
    echo -e "${CYAN}Network Statistics${NC}"
    echo "=================="
    
    # Show VXLAN interfaces
    echo -e "\n${YELLOW}VXLAN Interfaces:${NC}"
    ip -d link show type vxlan 2>/dev/null | grep -E "vxlan|inet" || echo "No VXLAN interfaces found"
    
    # Show routing table
    echo -e "\n${YELLOW}Routing Table:${NC}"
    ip route | grep -E "30\.0\.0\." || echo "No tunnel routes found"
    
    # Show iptables rules
    echo -e "\n${YELLOW}Firewall Rules:${NC}"
    iptables -L INPUT | grep -E "ACCEPT|udp|30\.0\.0\." || echo "No specific tunnel rules found"
    
    read -p "Press Enter to continue..."
}

# ---------------- ADVANCED SETTINGS ----------------
advanced_settings() {
    while true; do
        show_header
        echo -e "|${YELLOW}Advanced Settings${NC}"
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1${GREEN}►${NC} Backup Configuration"
        echo -e "2${BLUE}►${NC} Restore Configuration"
        echo -e "3${CYAN}►${NC} Update Script"
        echo -e "4${MAGENTA}►${NC} System Optimization"
        echo -e "5${YELLOW}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " advanced_choice
        
        case $advanced_choice in
            1) backup_config ;;
            2) restore_config ;;
            3) update_script ;;
            4) system_optimization ;;
            5) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

backup_config() {
    local backup_file="/root/lena-tunnel-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo "Creating backup..."
    tar -czf "$backup_file" -C / \
        etc/lena-tunnel \
        usr/local/bin/setup_*.sh \
        usr/local/bin/cleanup_*.sh \
        etc/systemd/system/lena-tunnel-*.service \
        etc/haproxy/haproxy.cfg \
        var/log/lena-tunnel.log 2>/dev/null
    
    echo -e "${GREEN}Backup created: $backup_file${NC}"
    read -p "Press Enter to continue..."
}

restore_config() {
    echo "Available backup files:"
    ls -la /root/lena-tunnel-backup-*.tar.gz 2>/dev/null || echo "No backup files found"
    
    read -p "Enter backup file path: " backup_file
    
    if [[ -f "$backup_file" ]]; then
        echo "Restoring configuration..."
        tar -xzf "$backup_file" -C /
        systemctl daemon-reload
        
        # Restart services
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            systemctl restart "${SERVICE_PREFIX}-${tunnel}.service"
        done
        
        echo -e "${GREEN}Configuration restored successfully!${NC}"
    else
        echo -e "${RED}Backup file not found!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

update_script() {
    echo "Updating Lena Tunnel script..."
    
    # Download latest version
    if curl -fsSL "https://raw.githubusercontent.com/Moriostar/tunellstar/main/install.sh" -o "/tmp/lena-update.sh"; then
        chmod +x "/tmp/lena-update.sh"
        
        read -p "Update downloaded. Install now? (y/N): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            bash "/tmp/lena-update.sh"
        fi
        
        rm -f "/tmp/lena-update.sh"
    else
        echo -e "${RED}Failed to download update!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

system_optimization() {
    echo -e "${CYAN}System Optimization${NC}"
    echo "==================="
    
    echo "1) Install BBR"
    echo "2) Optimize Network Parameters"
    echo "3) Configure Firewall"
    echo "4) All Optimizations"
    
    read -p "Enter choice: " opt_choice
    
    case $opt_choice in
        1|4) install_bbr ;;
    esac
    
    if [[ "$opt_choice" == "2" || "$opt_choice" == "4" ]]; then
        echo "Optimizing network parameters..."
        cat <<EOF >> /etc/sysctl.conf
# Lena Tunnel Optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
        sysctl -p
        echo -e "${GREEN}Network parameters optimized!${NC}"
    fi
    
    if [[ "$opt_choice" == "3" || "$opt_choice" == "4" ]]; then
        echo "Configuring firewall..."
        # Add basic firewall rules
        iptables -I INPUT -i lo -j ACCEPT
        iptables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        echo -e "${GREEN}Firewall configured!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# ---------------- UNINSTALL ----------------
uninstall_all() {
    echo -e "${RED}WARNING: This will remove all tunnels and configurations!${NC}"
    read -p "Are you sure? Type 'YES' to confirm: " confirm
    
    if [[ "$confirm" == "YES" ]]; then
        echo "Removing all tunnels..."
        
        # Stop and remove all services
        if [[ -f "$TUNNEL_CONFIG" ]]; then
            jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
                systemctl stop "${SERVICE_PREFIX}-${tunnel}.service" 2>/dev/null
                systemctl disable "${SERVICE_PREFIX}-${tunnel}.service" 2>/dev/null
                rm -f "/etc/systemd/system/${SERVICE_PREFIX}-${tunnel}.service"
                rm -f "/usr/local/bin/setup_${tunnel}.sh"
                rm -f "/usr/local/bin/cleanup_${tunnel}.sh"
            done
        fi
        
        # Remove VXLAN interfaces
        for vxlan in $(ip link show type vxlan | grep -o 'vxlan[0-9]\+'); do
            ip link del "$vxlan" 2>/dev/null
        done
        
        # Remove configuration
        rm -rf "$CONFIG_DIR"
        rm -f "$LOG_FILE"
        
        systemctl daemon-reload
        
        echo -e "${GREEN}All tunnels removed successfully!${NC}"
    else
        echo "Operation cancelled."
    fi
    
    read -p "Press Enter to continue..."
}

# ---------------- BBR INSTALLATION ----------------
install_bbr() {
    echo "Installing BBR..."
    
    # Check if BBR is already enabled
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo -e "${GREEN}BBR is already enabled!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Install BBR
    curl -fsSL https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh -o /tmp/bbr.sh
    bash /tmp/bbr.sh
    rm -f /tmp/bbr.sh
    
    read -p "Press Enter to continue..."
}

# ---------------- MAIN PROGRAM ----------------
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Create initial log entry
    log_message "Lena Tunnel v2.0 started"
    
    # Main menu loop
    while true; do
        main_menu
        read -p "Enter your choice [1-7]: " choice
        
        case $choice in
            1) create_tunnel ;;
            2) manage_tunnels ;;
            3) monitor_tunnels ;;
            4) advanced_settings ;;
            5) uninstall_all ;;
            6) install_bbr ;;
            7) 
                echo -e "${GREEN}Thank you for using Lena Tunnel v2.0!${NC}"
                echo -e "${CYAN}Telegram: @ServerStar_ir${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run main program
main "$@"
