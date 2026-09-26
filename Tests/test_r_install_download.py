"""Exercise the real URLSession download path without launching macOS Installer."""
import http.server
import subprocess
import sys
import threading
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/must-not-follow')
            self.end_headers()
            return
        if self.path == '/must-not-follow':
            self.server.followed_redirect = True
        if self.path == '/slow':
            time.sleep(1)
        body = b'not an installer' if self.path == '/unsigned' else b'incorrect bytes'
        self.send_response(404 if self.path == '/missing' else 200)
        self.send_header('Content-Length', '999999999' if self.path == '/oversize' else str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
server.followed_redirect = False
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    for path in ['missing', 'redirect', 'oversize', 'corrupt', 'unsigned', 'slow']:
        command = [sys.argv[1], '--failure', f'http://127.0.0.1:{server.server_port}/{path}']
        if path == 'slow':
            command.append('--cancel')
        result = subprocess.run(command, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
        print(f'PASS {path}: rejected, staging cleaned, no installer opened')
    assert not server.followed_redirect
finally:
    server.shutdown()
