#!/bin/sh
# ===== mock-api-server.sh =====
# Мок-сервер API Keenetic для тестирования
# Mock Keenetic API server for testing

PORT="${1:-8080}"
LOGFILE="/tmp/mock-api.log"

echo "Starting Mock Keenetic API Server on port $PORT..."
echo "Log file: $LOGFILE"
echo "Access URL: http://localhost:$PORT"
echo
echo "Press Ctrl+C to stop the server"

# Функция обработки запросов
handle_request() {
    local method="$1"
    local path="$2"
    local data="$3"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') $method $path" >> "$LOGFILE"
    
    case "$path" in
        "/rci/system")
            echo '{"status":"ok","model":"KN-1010","firmware":"3.7.6"}'
            ;;
        "/rci/ip/route")
            case "$method" in
                "GET")
                    echo '{"routes":[{"host":"142.250.191.142","interface":"Wireguard0"},{"host":"31.13.86.36","interface":"Wireguard0"}]}'
                    ;;
                "POST")
                    echo '{"status":"success","message":"Route added"}'
                    ;;
                "DELETE")
                    echo '{"status":"success","message":"Route removed"}'
                    ;;
            esac
            ;;
        *)
            echo '{"error":"Not found"}'
            ;;
    esac
}

# Простой HTTP сервер с использованием netcat
if command -v nc >/dev/null 2>&1; then
    echo "Using netcat for HTTP server..."
    
    while true; do
        {
            # Читаем HTTP запрос
            read -r request_line
            method=$(echo "$request_line" | cut -d' ' -f1)
            path=$(echo "$request_line" | cut -d' ' -f2)
            
            # Пропускаем заголовки
            while read -r header && [ -n "$header" ]; do
                :
            done
            
            # Генерируем ответ
            response=$(handle_request "$method" "$path" "")
            
            # Отправляем HTTP ответ
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo "Content-Length: ${#response}"
            echo "Access-Control-Allow-Origin: *"
            echo ""
            echo "$response"
        } | nc -l -p "$PORT" -q 1
        
        # Выходим если nc не поддерживает -l
        if [ $? -ne 0 ]; then
            break
        fi
    done
elif command -v python3 >/dev/null 2>&1; then
    echo "Using Python3 for HTTP server..."
    
    cat > "/tmp/mock_server_$$.py" << EOF
#!/usr/bin/env python3
import http.server
import json
import sys
from urllib.parse import urlparse

class MockKeeneticHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        with open("$LOGFILE", "a") as f:
            f.write("%s %s\\n" % (self.log_date_time_string(), format % args))
    
    def do_GET(self):
        self.handle_request("GET")
    
    def do_POST(self):
        self.handle_request("POST")
    
    def do_DELETE(self):
        self.handle_request("DELETE")
    
    def handle_request(self, method):
        path = urlparse(self.path).path
        
        responses = {
            "/rci/system": {"status": "ok", "model": "KN-1010", "firmware": "3.7.6"},
            "/rci/ip/route": {
                "GET": {"routes": [{"host": "142.250.191.142", "interface": "Wireguard0"}, {"host": "31.13.86.36", "interface": "Wireguard0"}]},
                "POST": {"status": "success", "message": "Route added"},
                "DELETE": {"status": "success", "message": "Route removed"}
            }
        }
        
        if path in responses:
            if isinstance(responses[path], dict) and method in responses[path]:
                response = responses[path][method]
            else:
                response = responses[path]
        else:
            response = {"error": "Not found"}
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

if __name__ == "__main__":
    server = http.server.HTTPServer(('', $PORT), MockKeeneticHandler)
    print(f"Mock API server running on port $PORT")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\\nShutting down server...")
        server.shutdown()
EOF
    
    python3 "/tmp/mock_server_$$.py"
    rm -f "/tmp/mock_server_$$.py"
    
elif command -v python >/dev/null 2>&1; then
    echo "Using Python2 for HTTP server..."
    
    cat > "/tmp/mock_server_$$.py" << EOF
#!/usr/bin/env python
import BaseHTTPServer
import json
import sys
import urlparse

class MockKeeneticHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        with open("$LOGFILE", "a") as f:
            f.write("%s %s\\n" % (self.log_date_time_string(), format % args))
    
    def do_GET(self):
        self.handle_request("GET")
    
    def do_POST(self):
        self.handle_request("POST")
    
    def do_DELETE(self):
        self.handle_request("DELETE")
    
    def handle_request(self, method):
        path = urlparse.urlparse(self.path).path
        
        responses = {
            "/rci/system": {"status": "ok", "model": "KN-1010", "firmware": "3.7.6"},
            "/rci/ip/route": {
                "GET": {"routes": [{"host": "142.250.191.142", "interface": "Wireguard0"}, {"host": "31.13.86.36", "interface": "Wireguard0"}]},
                "POST": {"status": "success", "message": "Route added"},
                "DELETE": {"status": "success", "message": "Route removed"}
            }
        }
        
        if path in responses:
            if isinstance(responses[path], dict) and method in responses[path]:
                response = responses[path][method]
            else:
                response = responses[path]
        else:
            response = {"error": "Not found"}
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response))

if __name__ == "__main__":
    server = BaseHTTPServer.HTTPServer(('', $PORT), MockKeeneticHandler)
    print "Mock API server running on port $PORT"
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print "\\nShutting down server..."
        server.shutdown()
EOF
    
    python "/tmp/mock_server_$$.py"
    rm -f "/tmp/mock_server_$$.py"
    
else
    echo "ERROR: No suitable HTTP server found (nc, python3, or python required)"
    echo "Please install one of: netcat-openbsd, python3, or python"
    exit 1
fi