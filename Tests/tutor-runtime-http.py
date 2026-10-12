#!/usr/bin/env python3
"""Loopback download faults; no external requests or account credentials."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import sys, time
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        data = Path(sys.argv[1]).read_bytes()
        if self.path == '/404': self.send_error(404); return
        if self.path == '/redirect':
            self.send_response(302); self.send_header('Location', 'http://localhost:1/forbidden'); self.end_headers(); return
        if self.path == '/invalid': data = b'corrupt download'
        self.send_response(200)
        self.send_header('Content-Length', str(999999999 if self.path == '/oversize' else len(data)))
        self.end_headers()
        try:
            if self.path == '/truncated': self.wfile.write(data[:len(data)//2]); self.close_connection = True
            elif self.path == '/slow':
                for byte in data:
                    self.wfile.write(bytes([byte])); self.wfile.flush(); time.sleep(.1)
            elif self.path != '/oversize': self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[2]).write_text(str(server.server_port))
server.serve_forever()
