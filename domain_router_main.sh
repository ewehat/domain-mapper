#!/bin/sh
# Domain Router для Keenetic
# Маршрутизация по доменным именам

SCRIPT_DIR="/opt/domain-router"
DOMAINS_FILE="$SCRIPT_DIR/domains.txt"
IP_CACHE_FILE="$SCRIPT_DIR/ip-cache.txt"
SETTINGS_FILE="$SCRIPT_DIR/settings.conf"
LOG_FILE="$SCRIPT_DIR/domain-router.log"

# Загрузка настроек
load_settings() {
    if [ -f "$SETTINGS_FILE" ]; then
        # Проверяем права доступа к файлу настроек
        if [ ! -r "$SETTINGS_FILE" ]; then
            log_message "ERROR: Cannot read settings file: $SETTINGS_FILE"
            return 1
        fi
        
        # Проверяем, что файл настроек не слишком открыт (должен быть 600 или 640)
        local perms
        perms=$(stat -c "%a" "$SETTINGS_FILE" 2>/dev/null || stat -f "%A" "$SETTINGS_FILE" 2>/dev/null)
        if [ -n "$perms" ] && [ "$perms" -gt 640 ]; then
            log_message "WARNING: Settings file permissions too open: $perms. Consider chmod 600 $SETTINGS_FILE"
        fi
        
        . "$SETTINGS_FILE"
    else
        # Настройки по умолчанию
        KEENETIC_HOST="192.168.1.1"
        KEENETIC_USER="admin"
        KEENETIC_PASS=""
        VPN_INTERFACE="Wireguard0"
        DNS_SERVERS="8.8.8.8,1.1.1.1"
    fi
    
    # Проверяем обязательные настройки
    if [ -z "$KEENETIC_HOST" ] || [ -z "$KEENETIC_USER" ]; then
        log_message "ERROR: Missing required settings (KEENETIC_HOST or KEENETIC_USER)"
        return 1
    fi
    
    # Проверяем, что пароль не пустой
    if [ -z "$KEENETIC_PASS" ]; then
        log_message "WARNING: KEENETIC_PASS is empty, API requests may fail"
    fi
    
    # Проверяем, что VPN_INTERFACE указан
    if [ -z "$VPN_INTERFACE" ]; then
        log_message "ERROR: VPN_INTERFACE not specified"
        return 1
    fi
}

# Логирование
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Резолв домена в IP адреса
resolve_domain() {
    local domain="$1"
    local ips=""
    
    # Проверяем валидность домена
    if ! validate_domain "$domain"; then
        log_message "ERROR: Invalid domain format: $domain"
        return 1
    fi
    
    # Пробуем разные DNS серверы
    for dns in $(echo "$DNS_SERVERS" | tr ',' ' '); do
        # Используем nslookup с более надежным парсингом
        ips=$(nslookup "$domain" "$dns" 2>/dev/null | \
              awk '/^Address: / { 
                  if ($2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) 
                      print $2 
              }' | \
              sort -u | \
              head -10)  # Ограничиваем количество IP
        
        # Если nslookup не сработал, пробуем dig (если доступен)
        if [ -z "$ips" ] && command -v dig >/dev/null 2>&1; then
            ips=$(dig +short "$domain" @"$dns" 2>/dev/null | \
                  grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | \
                  sort -u | \
                  head -10)
        fi
        
        if [ -n "$ips" ]; then
            break
        fi
    done
    
    if [ -z "$ips" ]; then
        log_message "ERROR: Failed to resolve $domain using DNS servers: $DNS_SERVERS"
        return 1
    fi
    
    echo "$ips"
}

# Получение текущих IP для домена из кэша
get_cached_ips() {
    local domain="$1"
    if [ -f "$IP_CACHE_FILE" ]; then
        grep "$domain" "$IP_CACHE_FILE" 2>/dev/null | cut -d' ' -f1
    fi
}

# Обновление кэша IP
update_ip_cache() {
    local ip="$1"
    local domain="$2"
    local temp_file="/tmp/ip-cache-temp-$$"
    
    # Валидация входных параметров
    if [ -z "$ip" ] || [ -z "$domain" ]; then
        log_message "ERROR: update_ip_cache called with empty parameters"
        return 1
    fi
    
    # Проверяем формат IP
    if ! echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        log_message "ERROR: Invalid IP format: $ip"
        return 1
    fi
    
    # Создаем временный файл с уникальным именем
    touch "$temp_file"
    chmod 600 "$temp_file"
    
    # Создаем кэш файл если не существует
    if [ ! -f "$IP_CACHE_FILE" ]; then
        touch "$IP_CACHE_FILE"
        chmod 600 "$IP_CACHE_FILE"
    fi
    
    # Удаляем старые записи для этого домена
    grep -v " .*\b$domain\b" "$IP_CACHE_FILE" > "$temp_file" 2>/dev/null || touch "$temp_file"
    
    # Добавляем новую запись или обновляем существующую
    if grep -q "^$ip " "$temp_file" 2>/dev/null; then
        # IP уже есть, добавляем домен к списку
        sed "s/^$ip \(.*\)/$ip \1,$domain/" "$temp_file" > "$temp_file.new"
        mv "$temp_file.new" "$temp_file"
    else
        # Новый IP
        echo "$ip $domain" >> "$temp_file"
    fi
    
    # Заменяем оригинальный файл если операция прошла успешно
    if [ -f "$temp_file" ]; then
        mv "$temp_file" "$IP_CACHE_FILE"
    else
        log_message "ERROR: Failed to update IP cache"
        rm -f "$temp_file"
        return 1
    fi
}

# Удаление домена из кэша
remove_from_cache() {
    local domain="$1"
    local temp_file="/tmp/ip-cache-temp-$$"
    
    if [ ! -f "$IP_CACHE_FILE" ]; then
        return 0
    fi
    
    touch "$temp_file"
    chmod 600 "$temp_file"
    
    # Удаляем домен из всех записей
    while IFS=' ' read -r ip domains || [ -n "$ip" ]; do
        if [ -n "$ip" ] && [ -n "$domains" ]; then
            # Удаляем домен из списка, обрабатывая различные позиции
            new_domains=$(echo "$domains" | sed -e "s/^${domain},//g" -e "s/,${domain},/,/g" -e "s/,${domain}$//g" -e "s/^${domain}$//g")
            
            # Очищаем лишние запятые
            new_domains=$(echo "$new_domains" | sed -e 's/^,\+//' -e 's/,\+$//' -e 's/,\+/,/g')
            
            # Сохраняем запись только если остались домены
            if [ -n "$new_domains" ] && [ "$new_domains" != "," ]; then
                echo "$ip $new_domains" >> "$temp_file"
            fi
        fi
    done < "$IP_CACHE_FILE"
    
    # Заменяем файл только если операция прошла успешно
    if [ -f "$temp_file" ]; then
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$IP_CACHE_FILE"
        else
            # Если файл пустой, создаем пустый кэш
            > "$IP_CACHE_FILE"
            rm -f "$temp_file"
        fi
    else
        log_message "ERROR: Failed to update cache file"
        return 1
    fi
}

# Получение текущих маршрутов из Keenetic
get_current_routes() {
    local response
    response=$(keenetic_api_request "GET" "/rci/ip/route" "")
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response" | grep -o '"host":"[^"]*"' | cut -d'"' -f4
    fi
}

# Проверка существования маршрута
route_exists() {
    local ip="$1"
    local current_routes
    current_routes=$(get_current_routes)
    
    echo "$current_routes" | grep -q "^$ip$"
}

# Безопасный HTTP запрос к Keenetic API с повторными попытками
keenetic_api_request() {
    local method="$1"
    local endpoint="$2" 
    local data="$3"
    local max_retries=3
    local retry_delay=2
    local attempt=1
    local temp_passwd_file="/tmp/.keenetic_passwd_$$"
    local response
    local exit_code
    
    # Создаем временный файл с паролем для безопасности
    echo "$KEENETIC_PASS" > "$temp_passwd_file"
    chmod 600 "$temp_passwd_file"
    
    while [ $attempt -le $max_retries ]; do
        case "$method" in
            "GET")
                response=$(wget -q --user="$KEENETIC_USER" \
                               --password-file="$temp_passwd_file" \
                               --timeout=10 \
                               -O - \
                               "http://$KEENETIC_HOST$endpoint" 2>/dev/null)
                exit_code=$?
                ;;
            "POST")
                response=$(wget -q --post-data="$data" \
                               --header="Content-Type: application/json" \
                               --user="$KEENETIC_USER" \
                               --password-file="$temp_passwd_file" \
                               --timeout=10 \
                               -O - \
                               "http://$KEENETIC_HOST$endpoint" 2>/dev/null)
                exit_code=$?
                ;;
            "DELETE")
                response=$(wget -q --method=DELETE \
                               --user="$KEENETIC_USER" \
                               --password-file="$temp_passwd_file" \
                               --post-data="$data" \
                               --header="Content-Type: application/json" \
                               --timeout=10 \
                               -O - \
                               "http://$KEENETIC_HOST$endpoint" 2>/dev/null)
                exit_code=$?
                ;;
        esac
        
        # Проверяем HTTP статус в ответе
        if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
            # Простая проверка на наличие ошибок в JSON ответе
            if echo "$response" | grep -q '"error"'; then
                log_message "ERROR: API returned error: $response"
                rm -f "$temp_passwd_file"
                return 1
            fi
            
            # Удаляем временный файл
            rm -f "$temp_passwd_file"
            echo "$response"
            return 0
        fi
        
        log_message "WARNING: API request failed (attempt $attempt/$max_retries): $method $endpoint"
        
        if [ $attempt -lt $max_retries ]; then
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    # Удаляем временный файл
    rm -f "$temp_passwd_file"
    
    log_message "ERROR: API request failed after $max_retries attempts: $method $endpoint"
    return $exit_code
}

# Добавление маршрута через API Keenetic
add_route() {
    local ip="$1"
    local response
    
    # Проверяем, не существует ли уже маршрут
    if route_exists "$ip"; then
        log_message "INFO: Route for $ip already exists"
        return 0
    fi
    
    # Формируем JSON для API
    local json_data="{\"host\":\"$ip\",\"interface\":\"$VPN_INTERFACE\"}"
    
    response=$(keenetic_api_request "POST" "/rci/ip/route" "$json_data")
    
    if [ $? -eq 0 ]; then
        log_message "INFO: Added route for $ip"
        return 0
    else
        log_message "ERROR: Failed to add route for $ip"
        return 1
    fi
}

# Удаление маршрута через API Keenetic
remove_route() {
    local ip="$1"
    local response
    
    # Проверяем, существует ли маршрут
    if ! route_exists "$ip"; then
        log_message "INFO: Route for $ip does not exist"
        return 0
    fi
    
    local json_data="{\"host\":\"$ip\"}"
    response=$(keenetic_api_request "DELETE" "/rci/ip/route" "$json_data")
    
    if [ $? -eq 0 ]; then
        log_message "INFO: Removed route for $ip"
        return 0
    else
        log_message "ERROR: Failed to remove route for $ip"
        return 1
    fi
}

# Обновление маршрутов для домена
update_domain_routes() {
    local domain="$1"
    local force_update="$2"
    
    log_message "INFO: Processing domain $domain"
    
    # Получаем текущие IP
    local new_ips
    new_ips=$(resolve_domain "$domain")
    
    if [ -z "$new_ips" ]; then
        return 1
    fi
    
    # Получаем старые IP из кэша
    local old_ips
    old_ips=$(get_cached_ips "$domain")
    
    # Обрабатываем новые IP
    for ip in $new_ips; do
        if [ "$force_update" = "1" ] || ! echo "$old_ips" | grep -q "$ip"; then
            update_ip_cache "$ip" "$domain"
            add_route "$ip"
        fi
    done
    
    # Удаляем старые IP, которых больше нет
    if [ -n "$old_ips" ]; then
        for ip in $old_ips; do
            if ! echo "$new_ips" | grep -q "$ip"; then
                # Проверяем, используется ли IP другими доменами
                local other_domains
                other_domains=$(grep "^$ip " "$IP_CACHE_FILE" 2>/dev/null | cut -d' ' -f2- | sed "s/\b$domain\b//g; s/,,*/,/g; s/^,*//; s/,*$//")
                
                if [ -z "$other_domains" ] || [ "$other_domains" = "," ]; then
                    remove_route "$ip"
                fi
                
                # Удаляем домен из кэша
                remove_from_cache "$domain"
            fi
        done
    fi
}

# Основная функция обновления всех доменов
update_all_domains() {
    local force_update="$1"
    local domains_count=0
    local success_count=0
    local error_count=0
    
    if [ ! -f "$DOMAINS_FILE" ]; then
        log_message "ERROR: Domains file not found: $DOMAINS_FILE"
        echo "ERROR: Domains file not found: $DOMAINS_FILE" >&2
        return 1
    fi
    
    # Подсчитываем количество доменов
    domains_count=$(grep -v "^#" "$DOMAINS_FILE" | grep -v "^$" | wc -l)
    
    if [ "$domains_count" -eq 0 ]; then
        log_message "INFO: No domains configured"
        echo "No domains configured"
        return 0
    fi
    
    log_message "INFO: Starting domain routes update for $domains_count domains"
    echo "Processing $domains_count domains..."
    
    while IFS= read -r domain; do
        # Пропускаем пустые строки и комментарии
        case "$domain" in
            ""|\#*) continue ;;
        esac
        
        echo "Processing: $domain"
        if update_domain_routes "$domain" "$force_update"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done < "$DOMAINS_FILE"
    
    log_message "INFO: Domain routes update completed. Success: $success_count, Errors: $error_count"
    echo "Update completed. Success: $success_count, Errors: $error_count"
    
    if [ "$error_count" -gt 0 ]; then
        return 1
    fi
}

# Валидация конфигурации
validate_configuration() {
    local errors=0
    
    # Проверяем обязательные настройки
    if [ -z "$KEENETIC_HOST" ]; then
        log_message "ERROR: KEENETIC_HOST not set"
        echo "ERROR: KEENETIC_HOST not set" >&2
        errors=$((errors + 1))
    fi
    
    if [ -z "$KEENETIC_USER" ]; then
        log_message "ERROR: KEENETIC_USER not set"
        echo "ERROR: KEENETIC_USER not set" >&2
        errors=$((errors + 1))
    fi
    
    if [ -z "$KEENETIC_PASS" ]; then
        log_message "WARNING: KEENETIC_PASS is empty"
        echo "WARNING: KEENETIC_PASS is empty" >&2
    fi
    
    if [ -z "$VPN_INTERFACE" ]; then
        log_message "ERROR: VPN_INTERFACE not set"
        echo "ERROR: VPN_INTERFACE not set" >&2
        errors=$((errors + 1))
    fi
    
    if [ -z "$DNS_SERVERS" ]; then
        log_message "WARNING: DNS_SERVERS not set, using default"
        DNS_SERVERS="8.8.8.8,1.1.1.1"
    fi
    
    # Проверяем доступность необходимых команд
    if ! command -v wget >/dev/null 2>&1; then
        log_message "ERROR: wget command not found"
        echo "ERROR: wget command not found" >&2
        errors=$((errors + 1))
    fi
    
    if ! command -v nslookup >/dev/null 2>&1 && ! command -v dig >/dev/null 2>&1; then
        log_message "ERROR: Neither nslookup nor dig found"
        echo "ERROR: Neither nslookup nor dig found" >&2
        errors=$((errors + 1))
    fi
    
    # Проверяем доступность директорий
    if [ ! -d "$SCRIPT_DIR" ]; then
        log_message "ERROR: Script directory not found: $SCRIPT_DIR"
        echo "ERROR: Script directory not found: $SCRIPT_DIR" >&2
        errors=$((errors + 1))
    fi
    
    return $errors
}
validate_domain() {
    local domain="$1"
    
    # Проверка на пустоту
    if [ -z "$domain" ]; then
        return 1
    fi
    
    # Проверка длины домена (до 253 символов)
    if [ ${#domain} -gt 253 ]; then
        return 1
    fi
    
    # Проверка на минимальную длину (домен должен содержать хотя бы одну точку для FQDN)
    if [ ${#domain} -lt 3 ]; then
        return 1
    fi
    
    # Проверка базового формата домена
    # Домен не может начинаться или заканчиваться точкой или тире
    case "$domain" in
        .*|*.|*-|-*|*..*|*--*) return 1 ;;
    esac
    
    # Проверка на допустимые символы и структуру
    # Домен должен содержать хотя бы одну точку и состоять из допустимых символов
    echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'
}

# Добавление нового домена
add_domain() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        echo "Usage: $0 add <domain>"
        return 1
    fi
    
    # Валидация домена
    if ! validate_domain "$domain"; then
        echo "ERROR: Invalid domain name: $domain"
        return 1
    fi
    
    # Проверяем, не добавлен ли уже домен
    if [ -f "$DOMAINS_FILE" ] && grep -q "^$domain$" "$DOMAINS_FILE"; then
        echo "Domain $domain already exists"
        return 1
    fi
    
    # Добавляем домен
    echo "$domain" >> "$DOMAINS_FILE"
    echo "Domain $domain added"
    
    # Сразу обновляем маршруты для этого домена
    update_domain_routes "$domain" "1"
}

# Удаление домена
remove_domain() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        echo "Usage: $0 remove <domain>"
        return 1
    fi
    
    if [ ! -f "$DOMAINS_FILE" ]; then
        echo "Domains file not found"
        return 1
    fi
    
    # Удаляем домен из файла
    local temp_domains="/tmp/domains-temp-$$"
    grep -v "^$domain$" "$DOMAINS_FILE" > "$temp_domains"
    mv "$temp_domains" "$DOMAINS_FILE"
    
    # Удаляем из кэша и маршрутов
    remove_from_cache "$domain"
    
    # Проверяем и удаляем неиспользуемые маршруты
    if [ -f "$IP_CACHE_FILE" ]; then
        while IFS=' ' read -r ip domains; do
            if [ -n "$ip" ] && [ -z "$domains" ]; then
                remove_route "$ip"
            fi
        done < "$IP_CACHE_FILE"
    fi
    
    echo "Domain $domain removed"
    log_message "INFO: Domain $domain removed"
}

# Очистка неиспользуемых маршрутов
cleanup_unused_routes() {
    log_message "INFO: Starting cleanup of unused routes"
    
    if [ ! -f "$IP_CACHE_FILE" ]; then
        return
    fi
    
    # Получаем все IP из кэша
    local cached_ips
    cached_ips=$(cut -d' ' -f1 "$IP_CACHE_FILE" | sort -u)
    
    # Получаем текущие маршруты из роутера
    local current_routes
    current_routes=$(get_current_routes)
    
    # Удаляем маршруты, которых нет в кэше
    for route_ip in $current_routes; do
        if ! echo "$cached_ips" | grep -q "^$route_ip$"; then
            log_message "INFO: Removing unused route $route_ip"
            remove_route "$route_ip"
        fi
    done
}

# Показать статус системы
show_status() {
    echo "=== Domain Router Status ==="
    echo
    
    if [ -f "$DOMAINS_FILE" ]; then
        echo "Configured domains:"
        cat "$DOMAINS_FILE" | grep -v "^#" | grep -v "^$"
    else
        echo "No domains configured"
    fi
    
    echo
    if [ -f "$IP_CACHE_FILE" ]; then
        echo "Cached IP mappings:"
        while IFS=' ' read -r ip domains; do
            if [ -n "$ip" ] && [ -n "$domains" ]; then
                echo "  $ip -> $domains"
            fi
        done < "$IP_CACHE_FILE"
    else
        echo "No cached mappings"
    fi
    
    echo
    echo "Current routes in Keenetic:"
    local current_routes
    current_routes=$(get_current_routes)
    if [ -n "$current_routes" ]; then
        for route_ip in $current_routes; do
            echo "  $route_ip -> $VPN_INTERFACE"
        done
    else
        echo "  No active routes"
    fi
}

# Основная логика
main() {
    # Загружаем настройки, прерываем выполнение при ошибке
    if ! load_settings; then
        echo "ERROR: Failed to load settings. Check $SETTINGS_FILE" >&2
        exit 1
    fi
    
    # Проверяем конфигурацию только для команд, которые требуют доступа к API
    case "$1" in
        "update"|"add"|"remove"|"force-update"|"cleanup"|"test-config")
            if ! validate_configuration; then
                echo "ERROR: Configuration validation failed" >&2
                exit 1
            fi
            ;;
    esac
    
    case "$1" in
        "update")
            update_all_domains "$2"
            ;;
        "add")
            add_domain "$2"
            ;;
        "remove")
            remove_domain "$2"
            ;;
        "status")
            show_status
            ;;
        "force-update")
            update_all_domains "1"
            ;;
        "cleanup")
            cleanup_unused_routes
            ;;
        "test-config")
            echo "Testing configuration..."
            if validate_configuration; then
                echo "✓ Configuration is valid"
                # Test API connectivity
                echo "Testing API connectivity..."
                if keenetic_api_request "GET" "/rci/system" "" >/dev/null; then
                    echo "✓ API connection successful"
                else
                    echo "✗ API connection failed"
                    exit 1
                fi
            else
                echo "✗ Configuration validation failed"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {update|add|remove|status|force-update|cleanup|test-config} [domain]"
            echo "Commands:"
            echo "  update          - Update routes for all domains"
            echo "  add <domain>    - Add new domain"
            echo "  remove <domain> - Remove domain"
            echo "  status          - Show current status"
            echo "  force-update    - Force update all routes"
            echo "  cleanup         - Remove unused routes"
            echo "  test-config     - Test configuration and API connectivity"
            exit 1
            ;;
    esac
}

main "$@"