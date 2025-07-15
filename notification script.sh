# --- Creating the Interactive VPN Monitor Script ---
cat > /usr/local/bin/vpn-monitor.sh << 'EOL'
#!/bin/bash

CHECK_HOST="1.1.1.1"
TUN_INTERFACE="tun0"
CHECK_INTERVAL=5      
PAUSE_MINUTES=5       
SNOOZE_MINUTES=1      

STATE_FILE="/run/user/$(id -u)/vpn_monitor.state"

mkdir -p "/run/user/$(id -u)"
echo 0 > "$STATE_FILE"
LAST_STATE="UP"

echo "Служба мониторинга VPN запущена. Интерфейс: $TUN_INTERFACE, Хост: $CHECK_HOST"

while true; do
    # 1. ПРОВЕРКА СОЕДИНЕНИЯ
    if ping -c 1 -W 3 -I "$TUN_INTERFACE" "$CHECK_HOST" > /dev/null 2>&1; then
        # Соединение есть
        if [ "$LAST_STATE" = "DOWN" ]; then
            echo "$(date): Соединение восстановлено."
            notify-send -i network-transmit-receive "VPN Монитор" "Соединение восстановлено"
            echo 0 > "$STATE_FILE"
        fi
        LAST_STATE="UP"
    else
        # Соединения нет
        SNOOZE_UNTIL=$(cat "$STATE_FILE")
        CURRENT_TIME=$(date +%s)

        if [ "$CURRENT_TIME" -gt "$SNOOZE_UNTIL" ]; then
            if [ "$LAST_STATE" = "UP" ]; then
                 echo "$(date): Соединение потеряно! Отправка уведомления."
            else
                 echo "$(date): Соединение все еще отсутствует. Повторная отправка уведомления."
            fi

            # 2. ОТПРАВКА ИНТЕРАКТИВНОГО УВЕДОМЛЕНИЯ
            ACTION=$(notify-send -u critical -t 15000 \
                --action="pause=Пауза на $PAUSE_MINUTES мин" \
                --action="snooze=Напомнить через $SNOOZE_MINUTES мин" \
                "VPN Соединение Потеряно!" \
                "Нет ответа от $CHECK_HOST через $TUN_INTERFACE." 2>/dev/null)

            # 3. ОБРАБОТКА ДЕЙСТВИЯ ПОЛЬЗОВАТЕЛЯ
            case "$ACTION" in
                "pause")
                    NEW_SNOOZE_TIME=$((CURRENT_TIME + PAUSE_MINUTES * 60))
                    echo "$NEW_SNOOZE_TIME" > "$STATE_FILE"
                    echo "Уведомления на паузе на $PAUSE_MINUTES минут."
                    ;;
                "snooze")
                    NEW_SNOOZE_TIME=$((CURRENT_TIME + SNOOZE_MINUTES * 60))
                    echo "$NEW_SNOOZE_TIME" > "$STATE_FILE"
                    echo "Уведомление отложено на $SNOOZE_MINUTES минуту."
                    ;;
                *)
                    # Пользователь закрыл уведомление. Ставим короткую паузу по умолчанию.
                    NEW_SNOOZE_TIME=$((CURRENT_TIME + 60))
                    echo "$NEW_SNOOZE_TIME" > "$STATE_FILE"
                    ;;
            esac
        else
            : # Находимся в режиме "паузы", ничего не делаем
        fi
        LAST_STATE="DOWN"
    fi

    sleep "$CHECK_INTERVAL"
done
EOL