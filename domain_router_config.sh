#!/bin/sh
# ===== install.sh =====
# Установочный скрипт Domain Router

INSTALL_DIR="/opt/domain-router"
CRON_FILE="/opt/etc/crontab"

echo "Installing Domain Router..."

# Проверяем что Entware установлен
if [ ! -d "/opt" ]; then
    echo "ERROR: Entware not found. Please install Entware first."
    exit 1
fi

# Создаем директорию
mkdir -p "$INSTALL_DIR"

# Копируем основной скрипт
if [ -f "domain_router_main.sh" ]; then
    cp domain_router_main.sh "$INSTALL_DIR/domain-router.sh"
    chmod +x "$INSTALL_DIR/domain-router.sh"
    echo "✓ Main script installed"
else
    echo "ERROR: domain_router_main.sh not found"
    exit 1
fi

# Создаем конфигурационный файл если его нет
if [ ! -f "$INSTALL_DIR/settings.conf" ]; then
    cat > "$INSTALL_DIR/settings.conf" << 'EOF'
# Настройки Domain Router
KEENETIC_HOST="192.168.1.1"
KEENETIC_USER="admin"
KEENETIC_PASS="your_password_here"
VPN_INTERFACE="Wireguard0"
DNS_SERVERS="8.8.8.8,1.1.1.1"
EOF
    # Устанавливаем безопасные права доступа к файлу с паролями
    chmod 600 "$INSTALL_DIR/settings.conf"
    echo "✓ Configuration file created with secure permissions"
    echo "  Please edit $INSTALL_DIR/settings.conf"
else
    echo "✓ Using existing configuration"
fi

# Создаем пустой файл доменов
if [ ! -f "$INSTALL_DIR/domains.txt" ]; then
    cat > "$INSTALL_DIR/domains.txt" << 'EOF'
# Domain Router - список доменов для маршрутизации
# Один домен на строку, строки с # игнорируются
# 
# Примеры:
# youtube.com
# googlevideo.com
# facebook.com
EOF
    echo "✓ Domains file created"
else
    echo "✓ Using existing domains file"
fi

# Создаем файлы для кэша и логов
touch "$INSTALL_DIR/ip-cache.txt"
touch "$INSTALL_DIR/domain-router.log"

# Добавляем задачу в cron (ежедневное обновление в 6:00)
if [ -f "$CRON_FILE" ]; then
    # Создаем временный файл с безопасным именем
    temp_cron="/tmp/crontab.tmp.$$"
    
    # Удаляем старую задачу если есть
    grep -v "domain-router.sh update" "$CRON_FILE" > "$temp_cron"
    
    # Добавляем новую задачу
    echo "0 6 * * * $INSTALL_DIR/domain-router.sh update" >> "$temp_cron"
    
    # Проверяем, что временный файл создался корректно
    if [ -f "$temp_cron" ]; then
        mv "$temp_cron" "$CRON_FILE"
        
        # Перезапускаем cron
        /opt/etc/init.d/S10cron restart
        echo "✓ Cron job added (daily update at 6:00 AM)"
    else
        echo "! Failed to update cron file"
    fi
else
    echo "! Cron not found, manual cron setup required"
fi

# Создаем символическую ссылку для удобства
ln -sf "$INSTALL_DIR/domain-router.sh" "/opt/bin/domain-router" 2>/dev/null

echo
echo "============================================"
echo "Domain Router installed successfully!"
echo "============================================"
echo
echo "Next steps:"
echo "1. Edit configuration: $INSTALL_DIR/settings.conf"
echo "2. Add domains: domain-router add example.com"
echo "3. Check status: domain-router status"
echo
echo "Commands:"
echo "  domain-router add <domain>     - Add domain"
echo "  domain-router remove <domain>  - Remove domain"
echo "  domain-router status           - Show status"
echo "  domain-router update           - Manual update"
echo "  domain-router force-update     - Force full update"
echo "  domain-router cleanup          - Remove unused routes"
echo

# ===== uninstall.sh =====
# Скрипт удаления

cat > "$INSTALL_DIR/uninstall.sh" << 'EOF'
#!/bin/sh
# Удаление Domain Router

INSTALL_DIR="/opt/domain-router"
CRON_FILE="/opt/etc/crontab"

echo "Uninstalling Domain Router..."

# Удаляем из cron
if [ -f "$CRON_FILE" ]; then
    temp_cron="/tmp/crontab.tmp.$$"
    grep -v "domain-router.sh" "$CRON_FILE" > "$temp_cron"
    
    if [ -f "$temp_cron" ]; then
        mv "$temp_cron" "$CRON_FILE"
        /opt/etc/init.d/S10cron restart
        echo "✓ Cron job removed"
    fi
fi

# Удаляем символическую ссылку
rm -f "/opt/bin/domain-router"

# Предлагаем очистить маршруты
echo
echo "Do you want to remove all routes created by Domain Router? (y/N)"
read -r response
if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    if [ -f "$INSTALL_DIR/domain-router.sh" ]; then
        "$INSTALL_DIR/domain-router.sh" cleanup
        echo "✓ Routes cleaned up"
    fi
fi

echo
echo "Do you want to remove all configuration and data files? (y/N)" 
read -r response
if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    rm -rf "$INSTALL_DIR"
    echo "✓ All files removed"
else
    rm -f "$INSTALL_DIR/domain-router.sh"
    echo "✓ Script removed, configuration preserved"
fi

echo "Domain Router uninstalled."
EOF

chmod +x "$INSTALL_DIR/uninstall.sh"

echo "Uninstall script created: $INSTALL_DIR/uninstall.sh"