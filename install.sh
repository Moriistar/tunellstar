#!/bin/bash

# ============================================================================
# StarTunnel v3.0 - Advanced VxLAN Tunnel Manager
# Developed by: Moriistar
# Channel: @ServerStar_ir
# Features: IPv4/IPv6 Local Support, Multi-tunnel, Load Balancing, Auto-Update
# ============================================================================

# ---------------- DEPENDENCIES ----------------
echo "[*] Installing prerequisites..."
sudo apt update -y >/dev/null 2>&1
sudo apt install -y iproute2 net-tools grep awk sudo iputils-ping jq curl haproxy systemd openssl >/dev/null 2>&1

# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ---------------- GLOBAL VARIABLES ----------------
SCRIPT_VERSION="3.0"
CONFIG_DIR="/etc/star-tunnel"
TUNNEL_CONFIG="$CONFIG_DIR/tunnels.json"
HAPROXY_CONFIG="$CONFIG_DIR/haproxy.json"
SERVICE_PREFIX="star-tunnel"
LOG_FILE="/var/log/star-tunnel.log"
UPDATE_URL="https://raw.githubusercontent.com/Moriistar/tunellstar/main/install.sh"
GITHUB_API="https://api.github.com/repos/Moriistar/tunellstar/releases/latest"

# Create config directory
mkdir -p "$CONFIG_DIR"

# ---------------- LOGGING ----------------
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------------- IPv6 LOCAL ADDRESS GENERATION ----------------
generate_ipv6_local() {
    # Generate RFC 4193 compliant IPv6 local address
    local prefix="fd"
    local global_id=$(openssl rand -hex 5)
    local subnet_id="0001"
    
    # Format: fdxx:xxxx:xxxx:0001::/64
    echo "${prefix}${global_id:0:2}:${global_id:2:4}:${global_id:6:4}:${subnet_id}::/64"
}

get_ipv6_local_address() {
    local prefix=$1
    local host_id=$2
    
    # Extract network part and add host ID
    local network_part=$(echo "$prefix" | cut -d':' -f1-4)
    echo "${network_part}::${host_id}/64"
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
        ip -6 addr show scope global | grep -oP '(?&lt;=inet6\s)[\da-f:]+' | head -1 || echo "::1"
    fi
}

check_tunnel_status() {
    local tunnel_name=$1
    systemctl is-active --quiet "${SERVICE_PREFIX}-${tunnel_name}.service" && echo "Active" || echo "Inactive"
}

check_for_updates() {
    local current_version="$SCRIPT_VERSION"
    local latest_version=$(curl -s "$GITHUB_API" | jq -r '.tag_name // "3.0"' 2>/dev/null)
    
    if [[ "$latest_version" != "$current_version" ]]; then
        echo "update_available"
    else
        echo "up_to_date"
    fi
}

# ---------------- MENU FUNCTIONS ----------------
show_header() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" 2>/dev/null | jq -r '.country // "Unknown"')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" 2>/dev/null | jq -r '.isp // "Unknown"')
    UPDATE_STATUS=$(check_for_updates)

    echo "+-----------------------------------------------------------------------------+"
    echo "| ███████╗████████╗ █████╗ ██████╗     ████████╗██╗   ██╗███╗   ██╗███╗   ██╗|"
    echo "| ██╔════╝╚══██╔══╝██╔══██╗██╔══██╗    ╚══██╔══╝██║   ██║████╗  ██║████╗  ██║|"
    echo "| ███████╗   ██║   ███████║██████╔╝       ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║|"
    echo "| ╚════██║   ██║   ██╔══██║██╔══██╗       ██║   ██║   ██║██║╚██╗██║██║╚██╗██║|"
    echo "| ███████║   ██║   ██║  ██║██║  ██║       ██║   ╚██████╔╝██║ ╚████║██║ ╚████║|"
    echo "| ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝|"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "| Telegram: ${MAGENTA}@ServerStar_ir${NC} | Version: ${GREEN}$SCRIPT_VERSION Advanced${NC}"
    if [[ "$UPDATE_STATUS" == "update_available" ]]; then
        echo -e "| Status: ${YELLOW}آپدیت جدید موجود است!${NC}"
    else
        echo -e "| Status: ${GREEN}آخرین نسخه${NC}"
    fi
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
    echo -e "4${MAGENTA}►${NC} HAProxy Management"
    echo -e "5${YELLOW}►${NC} Multi-Tunnel Setup"
    echo -e "6${WHITE}►${NC} Advanced Settings"
    echo -e "7${RED}►${NC} Uninstall All Tunnels"
    echo -e "8${GREEN}►${NC} Install BBR"
    echo -e "9${CYAN}►${NC} Update System"
    echo -e "0${YELLOW}►${NC} Exit"
    echo "+-----------------------------------------------------------------------------+"
}

# ---------------- TUNNEL CREATION ----------------
create_tunnel() {
    echo -e "${GREEN}Creating New StarTunnel${NC}"
    echo "=========================="
    
    # Tunnel name
    read -p "Enter tunnel name: " tunnel_name
    if [[ -z "$tunnel_name" ]]; then
        tunnel_name="star-tunnel-$(date +%s)"
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
    echo "3) IPv4 Local (10.x.x.x)"
    echo "4) IPv6 Local (fd::/48)"
    echo "5) Auto-detect"
    read -p "Enter choice (1-5): " ip_version_choice
    
    local use_local_ip=false
    case $ip_version_choice in
        1) ip_version="ipv4";;
        2) ip_version="ipv6";;
        3) ip_version="ipv4_local"; use_local_ip=true;;
        4) ip_version="ipv6_local"; use_local_ip=true;;
        5) ip_version="auto";;
        *) ip_version="auto";;
    esac
    
    # Get IP addresses
    if [[ "$role_choice" == "1" ]]; then
        if [[ "$use_local_ip" == true ]]; then
            if [[ "$ip_version" == "ipv4_local" ]]; then
                iran_ip="10.0.0.1"
                read -p "Enter Kharej IP: " kharej_ip
                vxlan_ip="192.168.100.1/24"
            else
                # IPv6 Local
                local ipv6_prefix=$(generate_ipv6_local)
                iran_ip=$(get_ipv6_local_address "$ipv6_prefix" "1")
                read -p "Enter Kharej IP: " kharej_ip
                vxlan_ip=$(get_ipv6_local_address "$ipv6_prefix" "100")
            fi
        else
            read -p "Enter Iran IP: " iran_ip
            read -p "Enter Kharej IP: " kharej_ip
            vxlan_ip="30.0.0.1/24"
        fi
        local_role="iran"
        local_ip=$iran_ip
        remote_ip=$kharej_ip
    else
        if [[ "$use_local_ip" == true ]]; then
            if [[ "$ip_version" == "ipv4_local" ]]; then
                kharej_ip="10.0.0.2"
                read -p "Enter Iran IP: " iran_ip
                vxlan_ip="192.168.100.2/24"
            else
                # IPv6 Local
                local ipv6_prefix=$(generate_ipv6_local)
                kharej_ip=$(get_ipv6_local_address "$ipv6_prefix" "2")
                read -p "Enter Iran IP: " iran_ip
                vxlan_ip=$(get_ipv6_local_address "$ipv6_prefix" "200")
            fi
        else
            read -p "Enter Iran IP: " iran_ip
            read -p "Enter Kharej IP: " kharej_ip
            vxlan_ip="30.0.0.2/24"
        fi
        local_role="kharej"
        local_ip=$kharej_ip
        remote_ip=$iran_ip
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
    
    echo -e "${GREEN}StarTunnel '$tunnel_name' created successfully!${NC}"
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

# IPv6 firewall rules if needed
if [[ "\$VXLAN_IP" == *":"* ]]; then
    ip6tables -I INPUT 1 -p udp --dport \$PORT -j ACCEPT
    ip6tables -I INPUT 1 -s \$REMOTE_IP -j ACCEPT
    ip6tables -I INPUT 1 -s \${VXLAN_IP%/*} -j ACCEPT
fi

echo "[$(date)] StarTunnel $tunnel_name started successfully" >> "$LOG_FILE"
EOF
    
    chmod +x "/usr/local/bin/setup_${tunnel_name}.sh"
    
    # Create systemd service
    cat <<EOF > "/etc/systemd/system/${SERVICE_PREFIX}-${tunnel_name}.service"
[Unit]
Description=StarTunnel - $tunnel_name
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
echo "[$(date)] StarTunnel $tunnel_name stopped" >> "$LOG_FILE"
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
    
    log_message "StarTunnel $tunnel_name setup completed"
}

# ---------------- MULTI-TUNNEL SETUP ----------------
multi_tunnel_setup() {
    echo -e "${GREEN}Multi-Tunnel Setup${NC}"
    echo "=================="
    
    read -p "Enter number of Iran servers: " iran_count
    read -p "Enter Kharej server IP: " kharej_ip
    read -p "Enter base port (will increment): " base_port
    read -p "Enter base VNI (will increment): " base_vni
    
    echo ""
    echo "Select IP version for tunnels:"
    echo "1) IPv4"
    echo "2) IPv6"
    echo "3) IPv4 Local"
    echo "4) IPv6 Local"
    read -p "Enter choice (1-4): " ip_version_choice
    
    local use_local_ip=false
    case $ip_version_choice in
        1) ip_version="ipv4";;
        2) ip_version="ipv6";;
        3) ip_version="ipv4_local"; use_local_ip=true;;
        4) ip_version="ipv6_local"; use_local_ip=true;;
        *) ip_version="ipv4";;
    esac
    
    # Generate IPv6 prefix if needed
    local ipv6_prefix=""
    if [[ "$ip_version" == "ipv6_local" ]]; then
        ipv6_prefix=$(generate_ipv6_local)
        echo -e "${CYAN}Generated IPv6 Local Prefix: $ipv6_prefix${NC}"
    fi
    
    # Create tunnels
    for ((i=1; i<=iran_count; i++)); do
        local tunnel_name="star-multi-${i}"
        local current_port=$((base_port + i - 1))
        local current_vni=$((base_vni + i - 1))
        
        if [[ "$use_local_ip" == true ]]; then
            if [[ "$ip_version" == "ipv4_local" ]]; then
                local iran_ip="10.0.${i}.1"
                local vxlan_ip="192.168.${i}.1/24"
            else
                local iran_ip=$(get_ipv6_local_address "$ipv6_prefix" "$i")
                local vxlan_ip=$(get_ipv6_local_address "$ipv6_prefix" "$((100 + i))")
            fi
        else
            read -p "Enter Iran server $i IP: " iran_ip
            local vxlan_ip="30.${i}.0.1/24"
        fi
        
        echo "Creating tunnel $tunnel_name..."
        create_tunnel_config "$tunnel_name" "iran" "$ip_version" "$iran_ip" "$kharej_ip" "$current_port" "$current_vni" "$vxlan_ip" "y"
        setup_tunnel "$tunnel_name"
        
        echo -e "${GREEN}✓ Tunnel $tunnel_name created${NC}"
    done
    
    echo -e "${GREEN}Multi-tunnel setup completed!${NC}"
    echo "All tunnels are now active and configured."
    
    read -p "Press Enter to continue..."
}

# ---------------- HAPROXY MANAGEMENT ----------------
haproxy_menu() {
    while true; do
        show_header
        echo -e "|${YELLOW}HAProxy Management${NC}"
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1${GREEN}►${NC} Install HAProxy"
        echo -e "2${BLUE}►${NC} Configure Load Balancer"
        echo -e "3${CYAN}►${NC} Add Port Forwarding"
        echo -e "4${MAGENTA}►${NC} View HAProxy Status"
        echo -e "5${YELLOW}►${NC} View Statistics"
        echo -e "6${RED}►${NC} Clear Configuration"
        echo -e "7${WHITE}►${NC} Remove HAProxy"
        echo -e "8${GREEN}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " haproxy_choice
        
        case $haproxy_choice in
            1) install_haproxy_advanced ;;
            2) configure_load_balancer ;;
            3) add_port_forwarding ;;
            4) view_haproxy_status ;;
            5) view_haproxy_stats ;;
            6) clear_haproxy_config ;;
            7) remove_haproxy_advanced ;;
            8) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

install_haproxy_advanced() {
    echo "Installing HAProxy..."
    sudo apt-get update
    sudo apt-get install -y haproxy
    
    # Create advanced default configuration
    cat <<EOF > /etc/haproxy/haproxy.cfg
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    log 127.0.0.1:514 local0

defaults
    mode tcp
    option dontlognull
    option log-health-checks
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    timeout check 5000

# Statistics page
listen stats
    bind *:8080
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE
    stats show-desc StarTunnel HAProxy Statistics
    stats show-legends
EOF
    
    systemctl enable haproxy
    systemctl start haproxy
    
    echo -e "${GREEN}HAProxy installed and configured!${NC}"
    echo -e "${CYAN}Statistics available at: http://$(hostname -I | awk '{print $1}'):8080/stats${NC}"
    
    read -p "Press Enter to continue..."
}

configure_load_balancer() {
    echo "Configuring Load Balancer..."
    
    # Get available tunnels
    if [[ ! -f "$TUNNEL_CONFIG" ]] || [[ "$(jq 'keys | length' "$TUNNEL_CONFIG" 2>/dev/null)" == "0" ]]; then
        echo -e "${RED}No tunnels found! Please create tunnels first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "Available tunnels:"
    jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | nl
    
    read -p "Enter ports to load balance (comma-separated): " ports
    
    # Generate load balancer configuration
    local config_file="/etc/haproxy/haproxy.cfg"
    
    IFS=',' read -ra port_array <<< "$ports"
    for port in "${port_array[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat <<EOF >> $config_file

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
    balance roundrobin
    option httpchk
EOF
        
        # Add tunnel servers
        local counter=1
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
            echo "    server tunnel_$counter $vxlan_ip:$port check" >> $config_file
            ((counter++))
        done
    done
    
    # Validate and restart HAProxy
    if haproxy -c -f $config_file; then
        systemctl restart haproxy
        echo -e "${GREEN}Load balancer configured successfully!${NC}"
    else
        echo -e "${RED}Configuration failed!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

add_port_forwarding() {
    echo "Adding Port Forwarding..."
    
    read -p "Enter source port: " src_port
    read -p "Enter destination IP: " dest_ip
    read -p "Enter destination port: " dest_port
    
    cat <<EOF >> /etc/haproxy/haproxy.cfg

frontend frontend_$src_port
    bind *:$src_port
    default_backend backend_$src_port

backend backend_$src_port
    server dest_server $dest_ip:$dest_port check
EOF
    
    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        systemctl restart haproxy
        echo -e "${GREEN}Port forwarding added successfully!${NC}"
    else
        echo -e "${RED}Configuration failed!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

view_haproxy_status() {
    echo -e "${CYAN}HAProxy Status${NC}"
    echo "=============="
    
    if systemctl is-active --quiet haproxy; then
        echo -e "${GREEN}HAProxy is running${NC}"
        echo ""
        echo "Active connections:"
        netstat -tlnp | grep haproxy
    else
        echo -e "${RED}HAProxy is not running${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

view_haproxy_stats() {
    echo -e "${CYAN}HAProxy Statistics${NC}"
    echo "=================="
    
    local server_ip=$(hostname -I | awk '{print $1}')
    echo -e "Statistics URL: ${YELLOW}http://$server_ip:8080/stats${NC}"
    echo ""
    echo "You can view detailed statistics in your web browser."
    
    read -p "Press Enter to continue..."
}

clear_haproxy_config() {
    echo "Clearing HAProxy configuration..."
    
    # Backup current config
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-$(date +%s)
    
    # Reset to default configuration
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
    
    systemctl restart haproxy
    echo -e "${GREEN}HAProxy configuration cleared!${NC}"
    
    read -p "Press Enter to continue..."
}

remove_haproxy_advanced() {
    echo -e "${RED}Removing HAProxy...${NC}"
    
    read -p "Are you sure? (y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop haproxy
        systemctl disable haproxy
        apt-get remove --purge -y haproxy
        apt-get autoremove -y
        
        echo -e "${GREEN}HAProxy removed successfully!${NC}"
    else
        echo "Operation cancelled."
    fi
    
    read -p "Press Enter to continue..."
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
        
        echo -e "Active StarTunnels:"
        echo "+-----------------------------------------------------------------------------+"
        
        # List tunnels
        local counter=1
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local status=$(check_tunnel_status "$tunnel")
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local role=$(echo "$config" | jq -r '.role')
            local ip_version=$(echo "$config" | jq -r '.ip_version')
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip')
            
            if [[ "$status" == "Active" ]]; then
                echo -e "$counter) ${GREEN}$tunnel${NC} [$role/$ip_version] - $vxlan_ip (${GREEN}$status${NC})"
            else
                echo -e "$counter) ${RED}$tunnel${NC} [$role/$ip_version] - $vxlan_ip (${RED}$status${NC})"
            fi
            ((counter++))
        done
        
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1${GREEN}►${NC} Start/Stop Tunnel"
        echo -e "2${BLUE}►${NC} Delete Tunnel"
        echo -e "3${CYAN}►${NC} View Tunnel Details"
        echo -e "4${MAGENTA}►${NC} Clone Tunnel"
        echo -e "5${YELLOW}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " manage_choice
        
        case $manage_choice in
            1) toggle_tunnel ;;
            2) delete_tunnel ;;
            3) view_tunnel_details ;;
            4) clone_tunnel ;;
            5) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

clone_tunnel() {
    echo "Available tunnels:"
    jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | nl
    read -p "Enter tunnel name to clone: " source_tunnel
    
    if ! jq -e ".\"$source_tunnel\"" "$TUNNEL_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}Tunnel not found!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter new tunnel name: " new_tunnel
    read -p "Enter new VNI: " new_vni
    
    # Clone configuration
    local config=$(jq -r ".\"$source_tunnel\"" "$TUNNEL_CONFIG")
    local updated_config=$(echo "$config" | jq --arg vni "$new_vni" '.vni = ($vni | tonumber)')
    
    jq --arg name "$new_tunnel" --argjson config "$updated_config" '.[$name] = $config' "$TUNNEL_CONFIG" > "$TUNNEL_CONFIG.tmp" && mv "$TUNNEL_CONFIG.tmp" "$TUNNEL_CONFIG"
    
    setup_tunnel "$new_tunnel"
    
    echo -e "${GREEN}Tunnel cloned successfully!${NC}"
    read -p "Press Enter to continue..."
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
        echo -e "${YELLOW}StarTunnel '$tunnel_name' stopped.${NC}"
    else
        systemctl start "${SERVICE_PREFIX}-${tunnel_name}.service"
        echo -e "${GREEN}StarTunnel '$tunnel_name' started.${NC}"
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
        
        echo -e "${GREEN}StarTunnel '$tunnel_name' deleted successfully!${NC}"
        log_message "StarTunnel $tunnel_name deleted"
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
    
    echo -e "\n${CYAN}StarTunnel Details: $tunnel_name${NC}"
    echo "====================================="
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
        echo -e "|${YELLOW}StarTunnel Monitoring${NC}"
        echo "+-----------------------------------------------------------------------------+"
        
        if [[ ! -f "$TUNNEL_CONFIG" ]] || [[ "$(jq 'keys | length' "$TUNNEL_CONFIG" 2>/dev/null)" == "0" ]]; then
            echo -e "${RED}No tunnels found!${NC}"
            read -p "Press Enter to return to main menu..."
            return
        fi
        
        # Show tunnel statistics
        echo -e "${CYAN}Tunnel Status Overview:${NC}"
        echo "+-----------------------------------------------------------------------------+"
        printf "%-15s %-10s %-15s %-10s %-10s %-15s\n" "NAME" "STATUS" "VXLAN_IP" "PORT" "VNI" "IP_VERSION"
        echo "+-----------------------------------------------------------------------------+"
        
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local status=$(check_tunnel_status "$tunnel")
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
            local port=$(echo "$config" | jq -r '.port')
            local vni=$(echo "$config" | jq -r '.vni')
            local ip_version=$(echo "$config" | jq -r '.ip_version')
            
            if [[ "$status" == "Active" ]]; then
                printf "%-15s ${GREEN}%-10s${NC} %-15s %-10s %-10s %-15s\n" "$tunnel" "$status" "$vxlan_ip" "$port" "$vni" "$ip_version"
            else
                printf "%-15s ${RED}%-10s${NC} %-15s %-10s %-10s %-15s\n" "$tunnel" "$status" "$vxlan_ip" "$port" "$vni" "$ip_version"
            fi
        done
        
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1${GREEN}►${NC} Real-time Monitoring"
        echo -e "2${BLUE}►${NC} View Logs"
        echo -e "3${CYAN}►${NC} Network Statistics"
        echo -e "4${MAGENTA}►${NC} Performance Test"
        echo -e "5${YELLOW}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " monitor_choice
        
        case $monitor_choice in
            1) realtime_monitoring ;;
            2) view_logs ;;
            3) network_stats ;;
            4) performance_test ;;
            5) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

performance_test() {
    echo -e "${CYAN}Performance Test${NC}"
    echo "================"
    
    echo "Available tunnels:"
    jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | nl
    read -p "Enter tunnel name to test: " tunnel_name
    
    if ! jq -e ".\"$tunnel_name\"" "$TUNNEL_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}Tunnel not found!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    local config=$(jq -r ".\"$tunnel_name\"" "$TUNNEL_CONFIG")
    local remote_ip=$(echo "$config" | jq -r '.remote_ip')
    local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
    
    echo "Testing connectivity..."
    
    # Ping test
    echo -e "\n${YELLOW}1. Ping Test to Remote IP:${NC}"
    ping -c 4 "$remote_ip"
    
    echo -e "\n${YELLOW}2. Ping Test to VXLAN IP:${NC}"
    ping -c 4 "$vxlan_ip"
    
    # Speed test (if iperf is available)
    if command -v iperf3 &> /dev/null; then
        echo -e "\n${YELLOW}3. Speed Test Available${NC}"
        read -p "Run iperf3 speed test? (y/N): " speed_test
        if [[ "$speed_test" == "y" || "$speed_test" == "Y" ]]; then
            echo "Starting iperf3 client test..."
            iperf3 -c "$vxlan_ip" -t 10 || echo "iperf3 server not running on remote end"
        fi
    fi
    
    read -p "Press Enter to continue..."
}

realtime_monitoring() {
    echo -e "${CYAN}Real-time Monitoring (Press Ctrl+C to stop)${NC}"
    echo "=============================================="
    
    while true; do
        clear
        echo -e "${CYAN}StarTunnel - Real-time Status${NC}"
        echo "$(date)"
        echo "=============================================="
        
        jq -r 'keys[]' "$TUNNEL_CONFIG" 2>/dev/null | while read tunnel; do
            local status=$(check_tunnel_status "$tunnel")
            local config=$(jq -r ".\"$tunnel\"" "$TUNNEL_CONFIG")
            local vxlan_ip=$(echo "$config" | jq -r '.vxlan_ip' | cut -d'/' -f1)
            local vni=$(echo "$config" | jq -r '.vni')
            local ip_version=$(echo "$config" | jq -r '.ip_version')
            
            echo -e "Tunnel: ${YELLOW}$tunnel${NC}"
            echo -e "Status: $([[ "$status" == "Active" ]] && echo -e "${GREEN}$status${NC}" || echo -e "${RED}$status${NC}")"
            echo -e "VXLAN IP: $vxlan_ip"
            echo -e "IP Version: $ip_version"
            
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
            echo "----------------------------------------------"
        done
        
        sleep 3
    done
}

view_logs() {
    echo -e "${CYAN}StarTunnel Logs${NC}"
    echo "==============="
    
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
    ip route | grep -E "30\.0\.0\.|192\.168\.|10\." || echo "No tunnel routes found"
    
    # Show IPv6 routes if any
    echo -e "\n${YELLOW}IPv6 Routes:${NC}"
    ip -6 route | grep -E "fd:" || echo "No IPv6 tunnel routes found"
    
    # Show iptables rules
    echo -e "\n${YELLOW}IPv4 Firewall Rules:${NC}"
    iptables -L INPUT | grep -E "ACCEPT|udp|30\.0\.0\.|192\.168\.|10\." || echo "No specific tunnel rules found"
    
    # Show ip6tables rules
    echo -e "\n${YELLOW}IPv6 Firewall Rules:${NC}"
    ip6tables -L INPUT | grep -E "ACCEPT|udp|fd:" || echo "No specific IPv6 tunnel rules found"
    
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
        echo -e "3${CYAN}►${NC} Update StarTunnel"
        echo -e "4${MAGENTA}►${NC} System Optimization"
        echo -e "5${YELLOW}►${NC} Network Diagnostics"
        echo -e "6${WHITE}►${NC} Export Configuration"
        echo -e "7${GREEN}►${NC} Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Enter choice: " advanced_choice
        
        case $advanced_choice in
            1) backup_config ;;
            2) restore_config ;;
            3) update_script ;;
            4) system_optimization ;;
            5) network_diagnostics ;;
            6) export_config ;;
            7) return ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

backup_config() {
    local backup_file="/root/star-tunnel-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo "Creating backup..."
    tar -czf "$backup_file" -C / \
        etc/star-tunnel \
        usr/local/bin/setup_*.sh \
        usr/local/bin/cleanup_*.sh \
        etc/systemd/system/star-tunnel-*.service \
        etc/haproxy/haproxy.cfg \
        var/log/star-tunnel.log 2>/dev/null
    
    echo -e "${GREEN}Backup created: $backup_file${NC}"
    read -p "Press Enter to continue..."
}

restore_config() {
    echo "Available backup files:"
    ls -la /root/star-tunnel-backup-*.tar.gz 2>/dev/null || echo "No backup files found"
    
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
    echo "Updating StarTunnel script..."
    
    local update_status=$(check_for_updates)
    
    if [[ "$update_status" == "up_to_date" ]]; then
        echo -e "${GREEN}StarTunnel is already up to date!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${YELLOW}New version available!${NC}"
    
    # Download latest version
    if curl -fsSL "$UPDATE_URL" -o "/tmp/star-tunnel-update.sh"; then
        chmod +x "/tmp/star-tunnel-update.sh"
        
        read -p "Update downloaded. Install now? (y/N): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            # Create backup before update
            backup_config
            
            # Install update
            bash "/tmp/star-tunnel-update.sh"
            
            echo -e "${GREEN}StarTunnel updated successfully!${NC}"
        fi
        
        rm -f "/tmp/star-tunnel-update.sh"
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
    echo "4) IPv6 Optimization"
    echo "5) All Optimizations"
    
    read -p "Enter choice: " opt_choice
    
    case $opt_choice in
        1|5) install_bbr ;;
    esac
    
    if [[ "$opt_choice" == "2" || "$opt_choice" == "5" ]]; then
        echo "Optimizing network parameters..."
        cat <<EOF >> /etc/sysctl.conf
# StarTunnel Optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fastopen = 3
EOF
        sysctl -p
        echo -e "${GREEN}Network parameters optimized!${NC}"
    fi
    
    if [[ "$opt_choice" == "3" || "$opt_choice" == "5" ]]; then
        echo "Configuring firewall..."
        # Add basic firewall rules
        iptables -I INPUT -i lo -j ACCEPT
        iptables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        ip6tables -I INPUT -i lo -j ACCEPT
        ip6tables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        echo -e "${GREEN}Firewall configured!${NC}"
    fi
    
    if [[ "$opt_choice" == "4" || "$opt_choice" == "5" ]]; then
        echo "Optimizing IPv6..."
        cat <<EOF >> /etc/sysctl.conf
# IPv6 Optimizations
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 1
net.ipv6.conf.default.accept_ra = 1
EOF
        sysctl -p
        echo -e "${GREEN}IPv6 optimized!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

network_diagnostics() {
    echo -e "${CYAN}Network Diagnostics${NC}"
    echo "==================="
    
    echo "1) Test Internet Connectivity"
    echo "2) Test DNS Resolution"
    echo "3) Check Open Ports"
    echo "4) Network Interface Status"
    echo "5) Route Table Analysis"
    echo "6) Full Network Report"
    
    read -p "Enter choice: " diag_choice
    
    case $diag_choice in
        1)
            echo "Testing internet connectivity..."
            ping -c 4 8.8.8.8
            ping -c 4 google.com
            ;;
        2)
            echo "Testing DNS resolution..."
            nslookup google.com
            nslookup google.com 8.8.8.8
            ;;
        3)
            echo "Checking open ports..."
            netstat -tlnp | grep -E ":80|:443|:22|:8080"
            ;;
        4)
            echo "Network interface status..."
            ip link show
            ip addr show
            ;;
        5)
            echo "Route table analysis..."
            ip route show
            ip -6 route show
            ;;
        6)
            echo "Generating full network report..."
            echo "===================" > /tmp/network-report.txt
            echo "Network Interfaces:" >> /tmp/network-report.txt
            ip addr show >> /tmp/network-report.txt
            echo "===================" >> /tmp/network-report.txt
            echo "Routing Table:" >> /tmp/network-report.txt
            ip route show >> /tmp/network-report.txt
            echo "===================" >> /tmp/network-report.txt
            echo "Open Ports:" >> /tmp/network-report.txt
            netstat -tlnp >> /tmp/network-report.txt
            echo "Report saved to /tmp/network-report.txt"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

export_config() {
    echo "Exporting StarTunnel configuration..."
    
    local export_file="/root/star-tunnel-config-$(date +%Y%m%d-%H%M%S).json"
    
    # Create comprehensive configuration export
    jq -n --slurpfile tunnels "$TUNNEL_CONFIG" \
          --arg version "$SCRIPT_VERSION" \
          --arg exported "$(date -Iseconds)" \
          --arg hostname "$(hostname)" \
          --arg ip "$(hostname -I | awk '{print $1}')" \
          '{
              version: $version,
              exported: $exported,
              hostname: $hostname,
              server_ip: $ip,
              tunnels: $tunnels[0]
          }' > "$export_file"
    
    echo -e "${GREEN}Configuration exported to: $export_file${NC}"
    echo "This file can be imported on another server."
    
    read -p "Press Enter to continue..."
}

# ---------------- UNINSTALL ----------------
uninstall_all() {
    echo -e "${RED}WARNING: This will remove all StarTunnels and configurations!${NC}"
    read -p "Are you sure? Type 'YES' to confirm: " confirm
    
    if [[ "$confirm" == "YES" ]]; then
        echo "Removing all StarTunnels..."
        
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
        
        echo -e "${GREEN}All StarTunnels removed successfully!${NC}"
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
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    
    # Verify BBR installation
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo -e "${GREEN}BBR installed and activated successfully!${NC}"
    else
        echo -e "${RED}BBR installation failed!${NC}"
    fi
    
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
    log_message "StarTunnel v$SCRIPT_VERSION started"
    
    # Main menu loop
    while true; do
        main_menu
        read -p "Enter your choice [0-9]: " choice
        
        case $choice in
            1) create_tunnel ;;
            2) manage_tunnels ;;
            3) monitor_tunnels ;;
            4) haproxy_menu ;;
            5) multi_tunnel_setup ;;
            6) advanced_settings ;;
            7) uninstall_all ;;
            8) install_bbr ;;
            9) 
                update_script
                ;;
            0) 
                echo -e "${GREEN}Thank you for using StarTunnel v$SCRIPT_VERSION!${NC}"
                echo -e "${CYAN}Telegram: @ServerStar_ir${NC}"
                echo -e "${MAGENTA}⭐ StarTunnel - Advanced VxLAN Solution ⭐${NC}"
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
