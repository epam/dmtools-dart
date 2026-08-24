#!/usr/bin/env python3
"""AI-provider-shaped echo server for AiSyncTools tests.

Dart's HttpServer runs on the event loop, which is frozen during
Process.runSync('curl', ...). This Python server runs in a separate process
and can serve curl requests while the Dart isolate is blocked.

Every response nests the request echo (method, path, headers, body) as a
JSON string under ALL provider extraction paths at once — Gemini
candidates, OpenAI/DIAL choices, Anthropic content, Ollama message, and
Bedrock output — so whichever extractor the tool under test uses, the
extracted text is the echoed request details.

Usage:
    python3 ai_echo_server.py [port]

Prints the actual bound port to stdout (first line, flushed), then serves
until killed.
"""

import http.server
import json
import sys


class AiEchoHandler(http.server.BaseHTTPRequestHandler):
    """Echoes request details inside a universal AI response envelope."""

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        echo = json.dumps({
            "method": self.command,
            "path": self.path,
            "headers": {k: v for k, v in self.headers.items()},
            "body": body,
        })
        envelope = {
            "candidates": [
                {"content": {"parts": [{"type": "text", "text": echo}]}}
            ],
            "choices": [{"message": {"role": "assistant", "content": echo}}],
            "content": [{"type": "text", "text": echo}],
            "output": {"message": {"content": [{"type": "text", "text": echo}]}},
        }
        # The Ollama extraction path reads top-level `message.content`; a
        # Bedrock response carrying `message` would be treated as an error
        # envelope (Java processResponse parity), so it is only present on
        # the Ollama endpoint.
        if self.path.startswith("/api/chat"):
            envelope["message"] = {"role": "assistant", "content": echo}
        encoded = json.dumps(envelope).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = http.server.HTTPServer(("127.0.0.1", port), AiEchoHandler)
    actual_port = server.server_address[1]
    print(actual_port, flush=True)
    server.serve_forever()
