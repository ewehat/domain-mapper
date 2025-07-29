#!/bin/sh
# ===== dev-setup.sh =====
# Скрипт для настройки среды разработки Domain Router
# Development environment setup script for Domain Router

echo "Setting up Domain Router development environment..."

# Создаем рабочую директорию для тестирования
DEV_DIR="/tmp/domain-router-dev"
TEST_DATA_DIR="$(pwd)/test-data"

# Очищаем предыдущую установку если есть
if [ -d "$DEV_DIR" ]; then
    echo "Cleaning previous development setup..."
    rm -rf "$DEV_DIR"
fi

# Создаем структуру директорий
mkdir -p "$DEV_DIR"
echo "✓ Created development directory: $DEV_DIR"

# Копируем основной скрипт
if [ -f "domain_router_main.sh" ]; then
    cp domain_router_main.sh "$DEV_DIR/domain-router.sh"
    chmod +x "$DEV_DIR/domain-router.sh"
    echo "✓ Copied main script to $DEV_DIR/domain-router.sh"
else
    echo "ERROR: domain_router_main.sh not found"
    exit 1
fi

# Копируем тестовые данные
if [ -d "$TEST_DATA_DIR" ]; then
    cp "$TEST_DATA_DIR/settings.conf" "$DEV_DIR/"
    cp "$TEST_DATA_DIR/domains.txt" "$DEV_DIR/"
    cp "$TEST_DATA_DIR/ip-cache.txt" "$DEV_DIR/"
    cp "$TEST_DATA_DIR/domain-router.log" "$DEV_DIR/"
    echo "✓ Copied test configuration files"
else
    echo "ERROR: test-data directory not found"
    exit 1
fi

# Устанавливаем безопасные права доступа
chmod 600 "$DEV_DIR/settings.conf"
chmod 644 "$DEV_DIR/domains.txt"
chmod 600 "$DEV_DIR/ip-cache.txt"
chmod 644 "$DEV_DIR/domain-router.log"

# Создаем патченую версию основного скрипта с исправленными путями
sed -e "s|SCRIPT_DIR=\"/opt/domain-router\"|SCRIPT_DIR=\"$DEV_DIR\"|g" \
    -e "s|/opt/domain-router|$DEV_DIR|g" \
    "$DEV_DIR/domain-router.sh" > "$DEV_DIR/domain-router-patched.sh"

chmod +x "$DEV_DIR/domain-router-patched.sh"

# Создаем временную модифицированную версию скрипта для разработки
cat > "$DEV_DIR/domain-router-dev.sh" << 'EOF'
#!/bin/sh
# Development wrapper for Domain Router

# Переопределяем пути для разработки
DEV_SCRIPT_DIR="/tmp/domain-router-dev"

# Выполняем патченую версию скрипта
exec "$DEV_SCRIPT_DIR/domain-router-patched.sh" "$@"
EOF

chmod +x "$DEV_DIR/domain-router-dev.sh"

echo "✓ Created development wrapper script"

# Создаем удобную символическую ссылку
ln -sf "$DEV_DIR/domain-router-dev.sh" "$DEV_DIR/dr"

echo
echo "============================================"
echo "Development environment ready!"
echo "============================================"
echo
echo "Development directory: $DEV_DIR"
echo "Main script: $DEV_DIR/domain-router-dev.sh"
echo "Quick access: $DEV_DIR/dr"
echo
echo "Test commands:"
echo "  $DEV_DIR/dr status           - Show current status"
echo "  $DEV_DIR/dr test-config      - Test configuration"
echo "  $DEV_DIR/dr add example.org  - Add test domain"
echo "  $DEV_DIR/dr update           - Update routes (stub mode)"
echo
echo "Configuration files:"
echo "  Settings: $DEV_DIR/settings.conf"
echo "  Domains:  $DEV_DIR/domains.txt"
echo "  Cache:    $DEV_DIR/ip-cache.txt"
echo "  Log:      $DEV_DIR/domain-router.log"
echo