#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo privileges."
  exit 1
fi

# Check if ufw and libnotify-bin are installed
if ! command -v ufw &> /dev/null || ! command -v notify-send &> /dev/null; then
    echo "UFW or libnotify-bin are not installed. Installing..."
    apt-get update
    apt-get install -y ufw libnotify-bin dbus gnome-session gnome-shell dbus-x11 notification-daemon dunst
fi

# Prompt for the path to the .ovpn file
read -p "Please enter the full path to your .ovpn file: " OVPN_FILE

if [ ! -f "$OVPN_FILE" ]; then
    echo "Error: File $OVPN_FILE not found."
    exit 1
fi

# --- Extracting data from the .ovpn file ---
VPN_SERVER_IP=$(grep -E "^remote\s" "$OVPN_FILE" | awk '{print $2}')
VPN_PORT=$(grep -E "^remote\s" "$OVPN_FILE" | awk '{print $3}')
PROTO=$(grep -E "^proto\s" "$OVPN_FILE" | awk '{print $2}')

if [ -z "$VPN_SERVER_IP" ] || [ -z "$VPN_PORT" ] || [ -z "$PROTO" ]; then
    echo "Error: Could not extract VPN server IP address, port, or protocol from the file."
    exit 1
fi

echo "Found VPN data: Server $VPN_SERVER_IP, Port $VPN_PORT, Protocol $PROTO"

ufw status | grep -q "Status: active"
if [ $? -ne 0 ]; then
    echo "UFW is not active. Activating UFW..."
    ufw enable
fi

USER_TO_ALLOW=$(sudo -E env | grep '^SUDO_USER=' | cut -d'=' -f2)
if [ -n "$USER_TO_ALLOW" ]; then

    USER_TO_ALLOW=$(who | awk '{print $1}' | head -n 1)
    echo "Sudo user detected: $USER_TO_ALLOW"
    # Check if a rule already exists to run killswitch-on.sh without a password
    if ! sudo grep -q "$USER_TO_ALLOW ALL=NOPASSWD: /usr/local/bin/killswitch-on.sh" /etc/sudoers; then
        echo "$USER_TO_ALLOW ALL=NOPASSWD: /usr/local/bin/killswitch-on.sh" | sudo tee -a /etc/sudoers > /dev/null
        echo "Rule for running killswitch-on.sh has been added."
    fi

    if ! sudo grep -q "$USER_TO_ALLOW ALL=NOPASSWD: /usr/local/bin/killswitch-off.sh" /etc/sudoers; then
        echo "$USER_TO_ALLOW ALL=NOPASSWD: /usr/local/bin/killswitch-off.sh" | sudo tee -a /etc/sudoers > /dev/null
        echo "Rule for running killswitch-off.sh has been added."
    fi

    if ! sudo grep -q "$USER_TO_ALLOW ALL=NOPASSWD: /etc/openvpn/vpn-disconnected.sh" /etc/sudoers; then
        echo "$USER_TO_ALLOW ALL=NOPASSWD: /etc/openvpn/vpn-disconnected.sh" | sudo tee -a /etc/sudoers > /dev/null
        echo "Rule for running vpn-disconnected.sh has been added."
    fi
else

    echo "Could not determine the sudo user. Sudoers rules will not be changed."

fi

# --- Creating the Kill Switch On script ---
cat > /usr/local/bin/killswitch-on.sh << EOL
#!/bin/bash
if [ "\$EUID" -ne 0 ]; then echo "Please run with sudo."; exit 1; fi

echo "Activating VPN Kill Switch..."

# Allow traffic to the VPN server
ufw allow out to $VPN_SERVER_IP port $VPN_PORT proto $PROTO
ufw allow out to $VPN_SERVER_IP port $VPN_PORT proto $PROTO
ufw allow out on tun0 from any to any
ufw allow out on wg0 from any to any

# Block all other outgoing and incoming traffic
ufw default deny outgoing
ufw default deny incoming

# Enable UFW
ufw enable

notify-send -u critical -i network-vpn "Kill Switch Activated" "All traffic, except for the VPN, is blocked."
echo "Kill Switch activated."
EOL

# --- Creating the Kill Switch Off script ---
cat > /usr/local/bin/killswitch-off.sh << EOL
#!/bin/bash
if [ "\$EUID" -ne 0 ]; then echo "Please run with sudo."; exit 1; fi

echo "Deactivating VPN Kill Switch..."
ufw default allow outgoing
ufw default allow incoming
notify-send -u critical -i network-vpn-offline "Kill Switch Deactivated"
echo "Kill Switch deactivated."
EOL

# --- Creating the VPN Disconnect Notification Script ---
cat > /etc/openvpn/vpn-disconnected.sh << EOL
#!/bin/bash
# This script is run by OpenVPN, environment variables may not be available.

# Find the active user to send a notification to their desktop
ACTIVE_USER=\$(loginctl list-sessions | awk 'NR==2 {print \$3}')

# Check if a user was found
if [ -n "\$ACTIVE_USER" ]; then

    # Check if the Kill Switch is active (UFW should be active and blocking outgoing traffic)
    # Search for the "Default:" line in the UFW status and check if it contains "deny (outgoing)"
    if ufw status | grep 'Default:' | grep -q 'deny (outgoing)'; then
        # If Kill Switch is active
        MESSAGE="VPN connection lost. Kill Switch is ACTIVE. All traffic is blocked."
        ICON="network-error"
    else
        # If Kill Switch is NOT active
        MESSAGE="VPN connection lost. WARNING: Kill Switch is NOT active!"
        ICON="network-warning"
    fi

    # Use su to send the notification as the active user
    # The -u critical flag makes the notification more prominent
    DISPLAY=:0 su \$ACTIVE_USER -c "notify-send -u critical -i '\$ICON' '\$MESSAGE'"
fi
EOL

# --- Creating the Notification Script ---
cat > /usr/local/bin/killswitch-notify.sh << EOL
#!/bin/bash
# This script sends a notification about the Kill Switch status.

STATUS_MESSAGE="Kill Switch successfully activated."
STATUS_ICON="network-vpn"

if ! ufw status | grep -q "Status: active"; then
    STATUS_MESSAGE="Kill Switch failed to activate!"
    STATUS_ICON="network-error"
fi

# Attempt to find the logged-in user
ACTIVE_USER=\$(who | awk '{print \$1}' | head -n 1)
if [ -n "\$ACTIVE_USER" ]; then
    DISPLAY=\$(ps aux | grep -m1 -E "Xorg|wayland" | awk '{print \$12}')
    DBUS_SESSION_BUS=\$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/\$(pgrep -u \$ACTIVE_USER gnome-session | head -n 1)/environ | cut -d= -f2-)
    su \$ACTIVE_USER -c "DISPLAY=\$DISPLAY DBUS_SESSION_BUS=\$DBUS_SESSION_BUS notify-send -u critical -i \$STATUS_ICON '\$STATUS_MESSAGE'"
fi
EOL


# --- Making the scripts executable ---
chmod +x /usr/local/bin/killswitch-on.sh
chmod +x /usr/local/bin/killswitch-off.sh
chmod +x /etc/openvpn/vpn-disconnected.sh
chmod +x /usr/local/bin/killswitch-notify.sh

# --- Setting up Systemd Services ---
cat > /etc/systemd/system/killswitch.service << EOL
[Unit]
Description=Enable VPN Kill Switch on Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/killswitch-on.sh
User=root
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

cat > /etc/systemd/system/killswitch-notify.service << EOL
[Unit]
Description=Send notification about VPN Kill Switch status
After=graphical.target
Requires=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/killswitch-notify.sh

[Install]
WantedBy=default.target
EOL

# Reload and enable the services
systemctl daemon-reload
systemctl enable killswitch.service
systemctl enable killswitch-notify.service

# --- Modifying the .ovpn file ---
# Check if the line has already been added
if ! grep -q "down /etc/openvpn/vpn-disconnected.sh" "$OVPN_FILE"; then
    echo -e "\n# Run script on connection drop\ndown /etc/openvpn/vpn-disconnected.sh" >> "$OVPN_FILE"
    echo "The 'down' directive has been added to your .ovpn file to track connection drops."
fi


# --- Printing instructions ---
INSTRUCTIONS="\n\n🎉 Installation complete! 🎉\n
Three scripts have been created:
1. /usr/local/bin/killswitch-on.sh - to activate the protection.
2. /usr/local/bin/killswitch-off.sh - to deactivate the protection.
3. /etc/openvpn/vpn-disconnected.sh - to send a notification on connection drop (called automatically).

--- How to use ---
1. Reconnect to your VPN using the aforementioned '$OVPN_FILE' file, which has been modified by this script.

2. Activate the Kill Switch:
   sudo /usr/local/bin/killswitch-on.sh
   Or set up a keyboard shortcut for 'sudo /usr/local/bin/killswitch-on.sh'

3. To deactivate the protection, run:
   sudo /usr/local/bin/killswitch-off.sh
   Or set up a keyboard shortcut for 'sudo /usr/local/bin/killswitch-off.sh'

IMPORTANT: Always deactivate the Kill Switch before restarting or shutting down, otherwise you will not have internet access after the system starts.
If you forget to turn off the Kill Switch at the end of your session, simply deactivate it after restarting."

echo -e "$INSTRUCTIONS"

# --- Commented out section from original script ---

# --- Determining network parameters ---
#ACTIVE_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -n1)
#LOCAL_GATEWAY_IP=$(ip r | grep default | awk '{print $3}')
#LOCAL_NETWORK=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n1)

#if [ -z "$ACTIVE_INTERFACE" ]; then #|| [ -z "$LOCAL_NETWORK" ]
#    echo "Error: Could not determine the active network interface." #or the local network
#    exit 1
#fi

#echo "Detected network parameters: Interface $ACTIVE_INTERFACE" #, Local Network $LOCAL_NETWORK

# Allow traffic on the local network
#ufw allow out on $ACTIVE_INTERFACE to $LOCAL_NETWORK
#ufw allow in on $ACTIVE_INTERFACE from $LOCAL_NETWORK

# Allow traffic to DNS servers (example for Google DNS, can be replaced)
#ufw allow out to 8.8.8.8 port 53
#ufw allow out to 8.8.4.4 port 53