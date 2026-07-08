#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'hq-http-ok')
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, fmt, *args):
        pass

HTTPServer(('127.0.0.1', 18080), Handler).serve_forever()
