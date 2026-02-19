#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BIN_PATH="/usr/local/bin/gbridge"
SYSTEMD_PATH="/etc/systemd/system"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root.${NC}" 
   exit 1
fi


header() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}                  GBRIDGE MANAGER                     ${NC}"
    echo -e "${CYAN}======================================================${NC}"
}

install_binary() {
    header
    if [ -f "$BIN_PATH" ]; then
        echo -e "${YELLOW}Binary already exists. Updating...${NC}"
    fi

    echo -e "${YELLOW}Select Download Source:${NC}"
    echo "1) Iran Server "
    echo "2) Global / Kharej "
    read -p "Enter choice [1-2]: " dl_choice

    if [ "$dl_choice" == "1" ]; then
        URL="http://2b2iran.ir/niggurt/gbridge"
    else
        URL="https://raw.githubusercontent.com/hoseinlolready/GBridge/refs/heads/main/core/gbridge"
    fi

    echo -e "${GREEN}Downloading...${NC}"
    
    if command -v wget >/dev/null 2>&1; then
        wget -O "$BIN_PATH" "$URL"
    else
        curl -L -o "$BIN_PATH" "$URL"
    fi

    if [ -f "$BIN_PATH" ]; then
        chmod +x "$BIN_PATH"
        echo -e "${GREEN}Success! Binary located at $BIN_PATH${NC}"
    else
        echo -e "${RED}Download failed.${NC}"
    fi
    read -p "Press Enter to continue..."
}

add_tunnel() {
    if [ ! -f "$BIN_PATH" ]; then
        echo -e "${RED}GBridge binary not found. Please run 'Update Binary' first.${NC}"
        read -p "Press Enter..."
        return
    fi

    header
    echo -e "${YELLOW}Create New Tunnel${NC}"
    read -p "Enter a unique name for this tunnel (no spaces, e.g., worker1): " tname

    tname=$(echo "$tname" | tr -cd '[:alnum:]_-')
    SERVICE_FILE="$SYSTEMD_PATH/gbridge-$tname.service"

    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${RED}A tunnel with the name '$tname' already exists!${NC}"
        read -p "Press Enter to return..."
        return
    fi

    echo -e "\n${YELLOW}Select Mode:${NC}"
    echo "1) Client"
    echo "2) Server"
    read -p "Choice: " mode_choice

    read -p "Enter Token (Password): " token
    license="XARRGQCI-TXAEMHPQ-SRYNUAAZ-CYCSSGGE"

    CMD_ARGS=""

    if [ "$mode_choice" == "1" ]; then
        read -p "Remote IP:PORT (Server): " remote
        read -p "Target IP:PORT (Local): " target
        CMD_ARGS="-mode client -remote $remote -target $target -token \"$token\" -license $license"
    else
        read -p "Listen Port (e.g. :443): " listen
        read -p "User Port (e.g. :8080): " userport
        CMD_ARGS="-mode server -listen $listen -userport $userport -token \"$token\" -license $license"
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GBridge Tunnel - $tname
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_PATH $CMD_ARGS
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}Service file created: gbridge-$tname${NC}"
    systemctl daemon-reload
    systemctl enable "gbridge-$tname"
    systemctl start "gbridge-$tname"
    
    echo -e "${GREEN}Tunnel '$tname' started successfully!${NC}"
    read -p "Press Enter to continue..."
}

manage_tunnels() {
    while true; do
        header
        echo -e "${YELLOW}Active Tunnels List:${NC}"
        
        services=($(ls $SYSTEMD_PATH/gbridge-*.service 2>/dev/null))
        
        if [ ${#services[@]} -eq 0 ]; then
            echo -e "${RED}No tunnels found.${NC}"
            read -p "Press Enter to return..."
            return
        fi

        i=1
        declare -A svc_map
        for svc in "${services[@]}"; do
            filename=$(basename "$svc")
            name=${filename#gbridge-}
            name=${name%.service}
            
            status=$(systemctl is-active "$filename")
            if [ "$status" == "active" ]; then
                color=$GREEN
            else
                color=$RED
            fi
            
            echo -e "$i) ${CYAN}$name${NC} [${color}${status}${NC}]"
            svc_map[$i]=$name
            ((i++))
        done
        
        echo -e "--------------------------------"
        echo -e "0) Back to Main Menu"
        read -p "Select tunnel to manage: " choice

        if [ "$choice" == "0" ]; then return; fi
        
        selected_name=${svc_map[$choice]}
        
        if [ -z "$selected_name" ]; then
            echo "Invalid selection."
            sleep 1
        else
            tunnel_action_menu "$selected_name"
        fi
    done
}
tunnel_action_menu() {
    local tname=$1
    local sname="gbridge-$tname"

    while true; do
        header
        echo -e "Managing Tunnel: ${CYAN}$tname${NC}"
        echo -e "Status: $(systemctl is-active $sname)"
        echo -e "--------------------------------"
        echo "1) Start"
        echo "2) Stop"
        echo "3) Restart"
        echo "4) View Logs"
        echo "5) Edit Configuration"
        echo "6) ${RED}Delete Tunnel${NC}"
        echo "0) Back"
        
        read -p "Select action: " action
        
        case $action in
            1) systemctl start $sname; echo "Started."; sleep 1 ;;
            2) systemctl stop $sname; echo "Stopped."; sleep 1 ;;
            3) systemctl restart $sname; echo "Restarted."; sleep 1 ;;
            4) 
                echo -e "${YELLOW}Press Ctrl+C to exit logs${NC}"
                journalctl -u $sname -f
                ;;
            5) 
                echo -e "${YELLOW}Opening service file in nano. Be careful!${NC}"
                read -p "Press Enter to open..."
                nano "$SYSTEMD_PATH/$sname.service"
                systemctl daemon-reload
                systemctl restart $sname
                echo "Configuration updated."
                sleep 1
                ;;
            6)
                read -p "Are you sure you want to delete '$tname'? (y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    systemctl stop $sname
                    systemctl disable $sname
                    rm "$SYSTEMD_PATH/$sname.service"
                    systemctl daemon-reload
                    echo -e "${RED}Tunnel deleted.${NC}"
                    sleep 2
                    return
                fi
                ;;
            0) return ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

while true; do
    header
    echo -e "1) ${GREEN}Add New Tunnel${NC}"
    echo -e "2) ${YELLOW}Manage Tunnels${NC} (Stop/Start/Log/Edit/Delete)"
    echo -e "3) ${CYAN}Update/Download Binary${NC}"
    echo -e "0) Exit"
    echo -e "------------------------------------------------------"
    read -p "Select Option: " opt

    case $opt in
        1) add_tunnel ;;
        2) manage_tunnels ;;
        3) install_binary ;;
        0) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
