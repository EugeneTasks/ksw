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
ACTIVE_USER=$(loginctl list-sessions | awk 'NR==2 {print $3}')
    
if [ -n "\$ACTIVE_USER" ]; then
    # Check Kill Switch status
    if sudo ufw status verbose | grep -q "Default:.*deny (incoming).*deny (outgoing)"; then
        MESSAGE="Kill Switch is ACTIVE. All traffic is blocked."
        ICON="network-warning"
    else
        MESSAGE="WARNING: Kill Switch is NOT active!"
        ICON="network-warning"
    fi
    DISPLAY=:0 su \$ACTIVE_USER -c "notify-send -u critical -i '\$ICON' '\$MESSAGE'"
    # Log the notification
    LOG_FILE="/var/log/killswitch-notify.log"
    echo "$(date): Notification sent to user \$ACTIVE_USER" >> \$LOG_FILE
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
RemainAfterExit=no

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

USER_TO_ALLOW=$(who | awk '{print $1}' | head -n 1)
echo "$USER_TO_ALLOW"

# --- Adding shortcuts for the scripts ---
# Check if a shortcut with the specified name already exists
shortcut_exists() {
    local shortcut_name="$1"
    local path="$2"
    sudo -u "$USER_TO_ALLOW" gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$path" name 2>/dev/null | grep -q "$shortcut_name"
}

# Get the current list of custom shortcuts for the specified user
current_shortcuts=$(sudo -u "$USER_TO_ALLOW" gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)

# Remove @as prefix and clean the format
current_shortcuts=$(echo "$current_shortcuts" | sed 's/@as //')

# Flags to check the existence of shortcuts
skip_on=0
skip_off=0

# Check if "Killswitch On" or "Killswitch Off" already exists
if ! echo "$current_shortcuts" | grep -q "^\[\]$"; then
    for path in $(echo "$current_shortcuts" | grep -o "'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom[0-9]*/'"); do
        # Remove quotes from path
        clean_path=$(echo "$path" | sed "s/'//g")
        if shortcut_exists "Killswitch On" "$clean_path"; then
            echo "Shortcut 'Killswitch On' already exists. Skipping creation."
            skip_on=1
        fi
        if shortcut_exists "Killswitch Off" "$clean_path"; then
            echo "Shortcut 'Killswitch Off' already exists. Skipping creation."
            skip_off=1
        fi
    done
fi

# If both shortcuts exist, skip creation
if [ "$skip_on" -eq 1 ] && [ "$skip_off" -eq 1 ]; then
    echo "Both shortcuts already exist. Skipping shortcuts creation."
else
    # Determine the index for the next shortcut
    if echo "$current_shortcuts" | grep -q "^\[\]$"; then
        index=0
    else
        index=$(echo "$current_shortcuts" | grep -o "custom[0-9]*" | grep -o "[0-9]*" | sort -n | tail -n 1)
        if [ -z "$index" ]; then
            index=0
        else
            index=$((index + 1))
        fi
    fi

    # Paths for the two new shortcuts
    new_shortcut1="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$index/"
    new_shortcut2="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$((index + 1))/"

    # Build the updated shortcuts array
    shortcuts_to_add=""

    if [ "$skip_on" -eq 0 ]; then
        shortcuts_to_add="'$new_shortcut1'"
    fi

    if [ "$skip_off" -eq 0 ]; then
        if [ -n "$shortcuts_to_add" ]; then
            shortcuts_to_add="$shortcuts_to_add, '$new_shortcut2'"
        else
            shortcuts_to_add="'$new_shortcut2'"
        fi
    fi

    # Combine with existing shortcuts
    if echo "$current_shortcuts" | grep -q "^\[\]$"; then
        # Array is empty
        updated_shortcuts="[$shortcuts_to_add]"
    else
        # Array has existing items
        # Remove the closing bracket and add new shortcuts
        existing_items=$(echo "$current_shortcuts" | sed 's/^\[//' | sed 's/\]$//')
        if [ -n "$shortcuts_to_add" ]; then
            updated_shortcuts="[$existing_items, $shortcuts_to_add]"
        else
            updated_shortcuts="$current_shortcuts"
        fi
    fi

    # Print updated_shortcuts for debugging
    echo "Updated shortcuts: $updated_shortcuts"

    # Apply the updated shortcuts array for the specified user
    sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_shortcuts"

    # Add the first shortcut (Killswitch On) if it does not exist
    if [ "$skip_on" -eq 0 ]; then
        sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$new_shortcut1" name 'Killswitch On'
        sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$new_shortcut1" command "sudo /usr/local/bin/killswitch-on.sh"
        sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$new_shortcut1" binding '<Control><Super>n'
        echo "Shortcut 'Killswitch On' created: Ctrl+Super+N"
    fi

    # Add the second shortcut (Killswitch Off) if it does not exist
    if [ "$skip_off" -eq 0 ]; then
        sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$new_shortcut2" name 'Killswitch Off'
        sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$new_shortcut2" command "sudo /usr/local/bin/killswitch-off.sh"
        sudo -u "$USER_TO_ALLOW" gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$new_shortcut2" binding '<Control><Super>f'
        echo "Shortcut 'Killswitch Off' created: Ctrl+Super+F"
    fi

    # Verification - show the final state
    echo "Final shortcuts list:"
    sudo -u "$USER_TO_ALLOW" gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings
fi

# Completion message, main script can continue executing
echo "Shortcuts processed."

# --- Printing instructions ---
INSTRUCTIONS="\n\n🎉 Installation complete! 🎉\n
Five scripts have been created:
1. /usr/local/bin/killswitch-on.sh - to activate the protection.
2. /usr/local/bin/killswitch-off.sh - to deactivate the protection.
3. /usr/local/bin/killswitch-notify.sh - to send a notification about the Kill Switch status.
4. /etc/openvpn/vpn-disconnected.sh - to send a notification on connection drop (called automatically).
5. Systemd services have been created to run the Kill Switch on boot and send notifications (killswitch.service, killswitch-notify.service).

Two services have been created:
1. /etc/systemd/system/killswitch.service - to enable the Kill Switch on boot.
2. /etc/systemd/system/killswitch-notify.service - to send notifications about the Kill Switch status after boot.

Three rules have been added to the sudoers file to allow the user to run the scripts without a password:
$USER_TO_ALLOW ALL=NOPASSWD: /usr/local/bin/killswitch-on.sh
$USER_TO_ALLOW ALL=NOPASSWD: /usr/local/bin/killswitch-off.sh
$USER_TO_ALLOW ALL=NOPASSWD: /etc/openvpn/vpn-disconnected.sh

Added down directive to your .ovpn file to track connection drops:
1. down /etc/openvpn/vpn-disconnected.sh

Added shortcuts for the scripts:
1. Killswitch On: Ctrl+Super+N
2. Killswitch Off: Ctrl+Super+F

--- How to use ---
1. Reconnect to your VPN using the aforementioned '$OVPN_FILE' file, which has been modified by this script.

2. Activate the Kill Switch:
   sudo /usr/local/bin/killswitch-on.sh
   Or use a keyboard shortcut: ctrl+Super+N

3. To deactivate the protection, run:
   sudo /usr/local/bin/killswitch-off.sh
   Or use a keyboard shortcut: ctrl+Super+F

IMPORTANT: If you don't have a internet connection after restarting your computer, deactivate the Kill Switch first."

echo -e "$INSTRUCTIONS"
