#!/bin/bash

# ---------------- INSTALL DEPENDENCIES ----------------
echo "[*] Installing prerequisites (iproute2, net-tools, grep, awk, jq, curl)..."
sudo apt update -y >/dev/null 2>&1
sudo apt install -y iproute2 net-tools grep awk sudo iputils-ping jq curl haproxy >/dev/null 2>&1
sudo apt-get install -y jq
sudo apt install -y haproxy

# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

# ---------------- FUNCTIONS ----------------

check_core_status() {
    ip link show | grep -q 'vxlan' && echo "Active" || echo "Inactive"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

StarTunnel_menu() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-----------------------------------------------------------------------------+"
MAGENTA='\033[1;35m'
NC='\033[0m' # No Color

echo -e "${MAGENTA}╔═══╦════╦═══╦═══╗╔════╦╗─╔╦═╗─╔╦═══╦╗──╔╗${NC}"
echo -e "${MAGENTA}║╔═╗║╔╗╔╗║╔═╗║╔═╗║║╔╗╔╗║║─║║║╚╗║║╔══╣║──║║${NC}"
echo -e "${MAGENTA}║╚══╬╝║║╚╣║─║║╚═╝║╚╝║║╚╣║─║║╔╗╚╝║╚══╣║──║║${NC}"
echo -e "${MAGENTA}╚══╗║─║║─║╚═╝║╔╗╔╝──║║─║║─║║║╚╗║║╔══╣║─╔╣║─╔╗${NC}"
echo -e "${MAGENTA}║╚═╝║─║║─║╔═╗║║║╚╗──║║─║╚═╝║║─║║║╚══╣╚═╝║╚═╝║${NC}"
echo -e "${MAGENTA}╚═══╝─╚╝─╚╝─╚╩╝╚═╝──╚╝─╚═══╩╝─╚═╩═══╩═══╩═══╝${NC}" 
echo "+-----------------------------------------------------------------------------+"
    echo -e "| Telegram Channel : ${MAGENTA}@ServerStar_ir ${NC}| Version : ${GREEN} 1.0.2 Beta ${NC} "
    echo "+-----------------------------------------------------------------------------+"      
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "1- Install new tunnel"
    echo -e "2- Uninstall tunnel(s)"
    echo -e "3- Install BBR"
    echo -e "4- HAProxy Management"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

haproxy_menu() {
    while true; do
        clear
        echo "+-----------------------------------------------------------------------------+"
        echo "|  _____ _                       _______                                      |"
        echo "| /  ___| |                     |__   __|                                     |"
        echo "| \ \`--.| |_ __ _ _ __ ___   ___   | | ___ _ __  _ __   ___ _ __               |"
        echo "|  \`--. \ __/ _\` | '_ \` _ \ / _ \  | |/ _ \ '_ \| '_ \ / _ \ '__|             |"
        echo "| /\__/ / || (_| | | | | | |  __/  | |  __/ | | | | | |  __/ |                 |"
        echo "| \____/ \__\__,_|_| |_| |_|\___|  |_|\___|_| |_|_| |_|\___|_|    V1.0.2 Beta  |"
        echo "+-----------------------------------------------------------------------------+"
        echo -e "| Telegram Channel : ${MAGENTA}@ServerStar_ir ${NC}| Version : ${GREEN} 1.0.2 Beta ${NC} "
        echo "+-----------------------------------------------------------------------------+"
        echo -e "|${YELLOW}HAProxy Management:${NC}"
        echo "+-----------------------------------------------------------------------------+"
        echo -e "1- Install HAProxy"
        echo -e "2- Add IPs and Ports to Forward"
        echo -e "3- Clear Configurations"
        echo -e "4- Remove HAProxy Completely"
        echo -e "9- Back to Main Menu"
        echo "+-----------------------------------------------------------------------------+"
        
        read -p "Select a Number : " haproxy_choice
        
        case $haproxy_choice in
            1) install_haproxy_standalone ;;
            2) add_ip_ports ;;
            3) clear_configs ;;
            4) remove_haproxy ;;
            9) break ;;
            *) echo "Invalid option. Please try again." && sleep 1 ;;
        esac
    done
}

install_haproxy_standalone() {
    echo "Installing HAProxy..."
    sudo apt-get update
    sudo apt-get install -y haproxy
    echo "HAProxy installed."
    default_config
    read -p "Press Enter to continue..."
}

default_config() {
    local config_file="/etc/haproxy/haproxy.cfg"
    cat < $config_file
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
EOL
}

generate_haproxy_config() {
    local ports=($1)
    local target_ips=($2)
    local config_file="/etc/haproxy/haproxy.cfg"

    echo "Generating HAProxy configuration..."

    for port in "${ports[@]}"; do
        cat <> $config_file

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
EOL
        for i in "${!target_ips[@]}"; do
            if [ $i -eq 0 ]; then
                cat <> $config_file
    server server$(($i+1)) ${target_ips[$i]}:$port check
EOL
            else
                cat <> $config_file
    server server$(($i+1)) ${target_ips[$i]}:$port check backup
EOL
            fi
        done
    done

    echo "HAProxy configuration generated at $config_file"
}

add_ip_ports() {
    read -p "Enter the IPs to forward to (use comma , to separate multiple IPs): " user_ips
    IFS=',' read -r -a ips_array <<< "$user_ips"
    read -p "Enter the ports (use comma , to separate): " user_ports
    IFS=',' read -r -a ports_array <<< "$user_ports"
    
    default_config
    generate_haproxy_config "${ports_array[*]}" "${ips_array[*]}"

    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        echo "Restarting HAProxy service..."
        systemctl restart haproxy
        echo "HAProxy configuration updated and service restarted."
    else
        echo "HAProxy configuration is invalid. Please check the configuration file."
    fi
    read -p "Press Enter to continue..."
}

clear_configs() {
    local config_file="/etc/haproxy/haproxy.cfg"
    local backup_file="/etc/haproxy/haproxy.cfg.bak"
    
    echo "Creating a backup of the HAProxy configuration..."
    cp $config_file $backup_file

    if [ $? -ne 0 ]; then
        echo "Failed to create a backup. Aborting."
        return
    fi

    echo "Clearing IP and port configurations from HAProxy configuration..."
    default_config
    echo "Stopping HAProxy service..."
    systemctl stop haproxy
    
    if [ $? -eq 0 ]; then
        echo "HAProxy service stopped."
    else
        echo "Failed to stop HAProxy service."
    fi

    echo "Done!"
    read -p "Press Enter to continue..."
}

remove_haproxy() {
    echo "Removing HAProxy..."
    sudo apt-get remove --purge -y haproxy
    sudo apt-get autoremove -y
    echo "HAProxy removed."
    read -p "Press Enter to continue..."
}

uninstall_all_vxlan() {
    echo "[!] Deleting all VXLAN interfaces and cleaning up..."
    for i in $(ip -d link show | grep -o 'vxlan[0-9]\+'); do
        ip link del $i 2>/dev/null
    done
    rm -f /usr/local/bin/vxlan_bridge.sh /etc/ping_vxlan.sh
    systemctl disable --now vxlan-tunnel.service 2>/dev/null
    rm -f /etc/systemd/system/vxlan-tunnel.service
    systemctl daemon-reload
    echo "[+] All VXLAN tunnels deleted."
}

install_bbr() {
    echo "Running BBR script..."
    curl -fsSL https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh -o /tmp/bbr.sh
    bash /tmp/bbr.sh
    rm /tmp/bbr.sh
}

install_haproxy_and_configure() {
    echo "[*] Installing and configuring HAProxy..."
    
    # Install HAProxy if not installed
    if ! command -v haproxy &> /dev/null; then
        sudo apt-get install -y haproxy
    fi

    # Default HAProxy config file
    local CONFIG_FILE="/etc/haproxy/haproxy.cfg"
    local BACKUP_FILE="/etc/haproxy/haproxy.cfg.bak"

    # Backup old config
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

    # Write base config
    cat < "$CONFIG_FILE"
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
EOL

    read -p "Enter target IP (destination server): " target_ip
    read -p "Enter ports (comma-separated): " user_ports

    IFS=',' read -ra ports <<< "$user_ports"

    for port in "${ports[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat <> "$CONFIG_FILE"

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
    server server1 $target_ip:$port check
EOL
    done

    # Validate haproxy config
    if haproxy -c -f "$CONFIG_FILE"; then
        echo "[*] Restarting HAProxy service..."
        systemctl restart haproxy
        systemctl enable haproxy
        echo -e "${GREEN}HAProxy configured and restarted successfully.${NC}"
    else
        echo -e "${RED}Warning: HAProxy configuration is invalid!${NC}"
    fi
}

# ---------------- MAIN ----------------
check_root

while true; do
    StarTunnel_menu
    read -p "Enter your choice [1-4]: " main_action
    case $main_action in
        1)
            break
            ;;
        2)
            uninstall_all_vxlan
            read -p "Press Enter to return to menu..."
            ;;
        3)
            install_bbr
            read -p "Press Enter to return to menu..."
            ;;
        4)
            haproxy_menu
            ;;
        *)
            echo "[x] Invalid option. Try again."
            sleep 1
            ;;
    esac
done

# Check if ip command is available
if ! command -v ip >/dev/null 2>&1; then
    echo "[x] iproute2 is not installed. Aborting."
    exit 1
fi

# ------------- VARIABLES --------------
VNI=88
VXLAN_IF="vxlan${VNI}"

# --------- Choose Server Role ----------
echo "Choose server role:"
echo "1- Iran"
echo "2- Kharej"
read -p "Enter choice (1/2): " role_choice

if [[ "$role_choice" == "1" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    # Ask about HAProxy usage
    while true; do
        read -p "Do you want to use HAProxy for port forwarding? (y/n): " haproxy_choice
        case $haproxy_choice in
            [Yy]|[Yy][Ee][Ss])
                install_haproxy_and_configure
                break
                ;;
            [Nn]|[Nn][Oo])
                echo "Continuing without HAProxy..."
                break
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done

    VXLAN_IP="30.0.0.1/24"
    REMOTE_IP=$KHAREJ_IP
    
    ipv4_local=$(hostname -I | awk '{print $1}')
    echo "IRAN Server setup complete."
    echo -e "####################################"
    echo -e "# Your IPv4 :                      #"
    echo -e "#  30.0.0.1                        #"
    echo -e "####################################"

elif [[ "$role_choice" == "2" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    # Ask about HAProxy usage
    while true; do
        read -p "Do you want to use HAProxy for port forwarding? (y/n): " haproxy_choice
        case $haproxy_choice in
            [Yy]|[Yy][Ee][Ss])
                install_haproxy_and_configure
                break
                ;;
            [Nn]|[Nn][Oo])
                echo "Continuing without HAProxy..."
                break
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done

    VXLAN_IP="30.0.0.2/24"
    REMOTE_IP=$IRAN_IP
    
    ipv4_local=$(hostname -I | awk '{print $1}')
    echo "Kharej Server setup complete."
    echo -e "####################################"
    echo -e "# Your IPv4 :                      #"
    echo -e "#  30.0.0.2                        #"
    echo -e "####################################"

else
    echo "[x] Invalid role selected."
    exit 1
fi

# Detect default interface
INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
echo "Detected main interface: $INTERFACE"

# ------------ Setup VXLAN --------------
echo "[+] Creating VXLAN interface..."
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning

echo "[+] Assigning IP $VXLAN_IP to $VXLAN_IF"
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up

echo "[+] Adding iptables rules"
iptables -I INPUT 1 -p udp --dport $DSTPORT -j ACCEPT
iptables -I INPUT 1 -s $REMOTE_IP -j ACCEPT
iptables -I INPUT 1 -s ${VXLAN_IP%/*} -j ACCEPT

# ---------------- CREATE SYSTEMD SERVICE ----------------
echo "[+] Creating systemd service for VXLAN..."

cat < /usr/local/bin/vxlan_bridge.sh
#!/bin/bash
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up
EOF

chmod +x /usr/local/bin/vxlan_bridge.sh

cat < /etc/systemd/system/vxlan-tunnel.service
[Unit]
Description=VXLAN Tunnel Interface
After=network.target

[Service]
ExecStart=/usr/local/bin/vxlan_bridge.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/vxlan-tunnel.service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vxlan-tunnel.service
systemctl start vxlan-tunnel.service

echo -e "\n${GREEN}[✓] VXLAN tunnel service enabled to run on boot.${NC}"
echo "[✓] StarTunnel setup completed successfully."
