#!/usr/bin/env python3
"""Minimal HTTP echo server for SyncHttpClient / SyncToolDispatcher tests.

Dart's HttpServer runs on the event loop, which is frozen during
Process.runSync('curl', ...). This Python server runs in a separate process
and can serve curl requests while the Dart isolate is blocked.

Usage:
    python3 test_echo_server.py [port]

Prints the actual bound port to stdout (first line, flushed), then serves
until killed. Each response echoes the request method, path, headers, and
body as JSON.
"""

import http.server
import json
import sys


class EchoHandler(http.server.BaseHTTPRequestHandler):
    """Echoes request details as a JSON response."""

    def _handle(self):
        body = ""
        if self.command in ("POST", "PUT", "PATCH"):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
        response = json.dumps({
            "method": self.command,
            "path": self.path,
            "headers": {k: v for k, v in self.headers.items()},
            "body": body,
        })
        encoded = response.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    do_GET = _handle
    do_POST = _handle
    do_PUT = _handle
    do_DELETE = _handle
    do_PATCH = _handle

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = http.server.HTTPServer(("127.0.0.1", port), EchoHandler)
    actual_port = server.server_address[1]
    print(actual_port, flush=True)
    server.serve_forever()
