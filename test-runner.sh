#!/bin/sh
# ===== test-runner.sh =====
# Скрипт для тестирования функций Domain Router
# Test runner script for Domain Router functionality

echo "=========================================="
echo "Domain Router Test Suite"
echo "=========================================="

# Устанавливаем среду разработки
echo "Setting up development environment..."
if ! ./dev-setup.sh; then
    echo "ERROR: Failed to set up development environment"
    exit 1
fi

DEV_DIR="/tmp/domain-router-dev"
DR_CMD="$DEV_DIR/dr"

echo
echo "=========================================="
echo "Running Tests"
echo "=========================================="

# Тест 1: Проверка конфигурации
echo
echo "Test 1: Configuration validation"
echo "-----------------------------------"
if "$DR_CMD" test-config; then
    echo "✓ Configuration test passed"
else
    echo "✗ Configuration test failed"
fi

# Тест 2: Показать статус
echo
echo "Test 2: Show status"
echo "-----------------------------------"
"$DR_CMD" status

# Тест 3: Добавление нового домена
echo
echo "Test 3: Add new domain"
echo "-----------------------------------"
if "$DR_CMD" add test-domain.example.com; then
    echo "✓ Domain added successfully"
else
    echo "✗ Failed to add domain"
fi

# Тест 4: Показать статус после добавления
echo
echo "Test 4: Show status after adding domain"
echo "-----------------------------------"
"$DR_CMD" status

# Тест 5: Обновление маршрутов
echo
echo "Test 5: Update routes"
echo "-----------------------------------"
if "$DR_CMD" update; then
    echo "✓ Routes updated successfully"
else
    echo "✗ Failed to update routes"
fi

# Тест 6: Принудительное обновление
echo
echo "Test 6: Force update routes"
echo "-----------------------------------"
if "$DR_CMD" force-update; then
    echo "✓ Force update completed successfully"
else
    echo "✗ Force update failed"
fi

# Тест 7: Очистка неиспользуемых маршрутов
echo
echo "Test 7: Cleanup unused routes"
echo "-----------------------------------"
if "$DR_CMD" cleanup; then
    echo "✓ Cleanup completed successfully"
else
    echo "✗ Cleanup failed"
fi

# Тест 8: Удаление домена
echo
echo "Test 8: Remove domain"
echo "-----------------------------------"
if "$DR_CMD" remove test-domain.example.com; then
    echo "✓ Domain removed successfully"
else
    echo "✗ Failed to remove domain"
fi

# Тест 9: Финальный статус
echo
echo "Test 9: Final status check"
echo "-----------------------------------"
"$DR_CMD" status

echo
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="

# Проверяем созданные файлы
echo "Checking created files:"
for file in "$DEV_DIR/settings.conf" "$DEV_DIR/domains.txt" "$DEV_DIR/ip-cache.txt" "$DEV_DIR/domain-router.log"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing"
    fi
done

echo
echo "Log file contents (last 10 lines):"
echo "-----------------------------------"
if [ -f "$DEV_DIR/domain-router.log" ]; then
    tail -10 "$DEV_DIR/domain-router.log"
else
    echo "No log file found"
fi

echo
echo "=========================================="
echo "Test Environment Information"
echo "=========================================="
echo "Development directory: $DEV_DIR"
echo "Script location: $DR_CMD"
echo "Configuration: $DEV_DIR/settings.conf"
echo
echo "To continue testing manually, use:"
echo "  $DR_CMD <command>"
echo
echo "Available commands:"
echo "  status, test-config, add <domain>, remove <domain>"
echo "  update, force-update, cleanup"
echo