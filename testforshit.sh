#!/bin/bash

USER_TO_ALLOW=$(who | awk '{print $1}' | head -n 1)
USER_ID=$(id -u "$USER_TO_ALLOW")
echo "$USER_TO_ALLOW"

# Функция для выполнения gsettings с правильным окружением
run_gsettings() {
    sudo -u "$USER_TO_ALLOW" \
        DISPLAY=:0 \
        XDG_RUNTIME_DIR="/run/user/$USER_ID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
        "$@"
}

echo "=== Setting up shortcuts ==="

# Получаем текущий список шорткатов
current=$(run_gsettings gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
echo "Current shortcuts: $current"

# Проверяем существующие шорткаты только в текущем списке
skip_on=0
skip_off=0

if [ "$current" != "@as []" ] && [ "$current" != "[]" ]; then
    echo "Checking existing shortcuts for duplicates..."
    
    # Извлекаем пути из списка и проверяем каждый
    for path in $(echo "$current" | grep -o "'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom[0-9]*/'"); do
        clean_path=$(echo "$path" | sed "s/'//g")
        
        # Проверяем name этого конкретного шортката
        name=$(run_gsettings gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$clean_path" name 2>/dev/null)
        
        if [ "$name" = "'Killswitch On'" ]; then
            echo "Found existing 'Killswitch On' shortcut at $clean_path"
            skip_on=1
        elif [ "$name" = "'Killswitch Off'" ]; then
            echo "Found existing 'Killswitch Off' shortcut at $clean_path"
            skip_off=1
        fi
    done
fi

# Если оба шортката уже существуют, выходим
if [ "$skip_on" -eq 1 ] && [ "$skip_off" -eq 1 ]; then
    echo "Both Killswitch shortcuts already exist. Skipping creation."
    echo "Shortcuts processed."
    exit 0
fi

# Определяем следующий доступный индекс
if [ "$current" = "@as []" ] || [ "$current" = "[]" ]; then
    index=0
else
    highest=$(echo "$current" | grep -o 'custom[0-9]\+' | grep -o '[0-9]\+' | sort -n | tail -1)
    if [ -z "$highest" ]; then
        index=0
    else
        index=$((highest + 1))
    fi
fi

echo "Starting with index: $index"

# Строим новый список шорткатов
new_paths=""
shortcut1_index=""
shortcut2_index=""

if [ "$skip_on" -eq 0 ]; then
    shortcut1_index=$index
    new_paths="'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}/'"
    index=$((index + 1))
fi

if [ "$skip_off" -eq 0 ]; then
    shortcut2_index=$index
    if [ -n "$new_paths" ]; then
        new_paths="$new_paths, '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}/'"
    else
        new_paths="'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}/'"
    fi
fi

# Создаем финальный список
if [ "$current" = "@as []" ] || [ "$current" = "[]" ]; then
    new_list="[$new_paths]"
else
    existing=$(echo "$current" | sed 's/@as //' | sed 's/^\[//' | sed 's/\]$//')
    if [ -n "$existing" ]; then
        new_list="[$existing, $new_paths]"
    else
        new_list="[$new_paths]"
    fi
fi

echo "New shortcuts list: $new_list"

# Устанавливаем список и создаем шорткаты
if [ -n "$new_paths" ]; then
    echo "Setting shortcuts list..."
    run_gsettings gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list"
    
    if [ $? -eq 0 ]; then
        echo "List updated successfully"
        sleep 1
        
        # Создаем Killswitch On shortcut
        if [ "$skip_on" -eq 0 ] && [ -n "$shortcut1_index" ]; then
            echo "Creating Killswitch On shortcut at index $shortcut1_index..."
            run_gsettings gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${shortcut1_index}/" name "Killswitch On"
            run_gsettings gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${shortcut1_index}/" command "sudo /usr/local/bin/killswitch-on.sh"
            run_gsettings gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${shortcut1_index}/" binding "<Control><Super>n"
            echo "✅ Killswitch On created: Ctrl+Super+N"
        fi
        
        # Создаем Killswitch Off shortcut
        if [ "$skip_off" -eq 0 ] && [ -n "$shortcut2_index" ]; then
            echo "Creating Killswitch Off shortcut at index $shortcut2_index..."
            run_gsettings gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${shortcut2_index}/" name "Killswitch Off"
            run_gsettings gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${shortcut2_index}/" command "sudo /usr/local/bin/killswitch-off.sh"
            run_gsettings gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${shortcut2_index}/" binding "<Control><Super>f"
            echo "✅ Killswitch Off created: Ctrl+Super+F"
        fi
        
        # Проверяем результат
        sleep 1
        echo "Final verification:"
        final_shortcuts=$(run_gsettings gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        echo "Final shortcuts: $final_shortcuts"
        
    else
        echo "❌ Error: Failed to set shortcuts list"
    fi
else
    echo "No new shortcuts to create."
fi

echo "Shortcuts processed."