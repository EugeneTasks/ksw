#!/bin/bash

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

# If both shortcuts exist, exit
if [ "$skip_on" -eq 1 ] && [ "$skip_off" -eq 1 ]; then
    echo "Both shortcuts already exist. Nothing to do."
    exit 0
fi

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

echo "Shortcuts processed."