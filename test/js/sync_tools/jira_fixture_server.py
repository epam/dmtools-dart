#!/usr/bin/env python3
"""Jira fixture server for JiraSyncTools tests.

Same constraint as test/js/test_echo_server.py: Dart's HttpServer runs on
the event loop, which is frozen during Process.runSync('curl', ...), so a
separate process must serve the requests. On top of the generic echo, it
serves canned Jira shapes the sync executors resolve against:

- GET  */issueLinkType             -> issueLinkTypes listing (Blocks/Relates)
- GET  */rest/api/latest/field     -> field listing with duplicate names
                                       (503 when the auth token contains
                                       'fieldfail', to exercise the
                                       createmeta fallback)
- GET  *fields=attachment*         -> attachment fixture ('__attached' key
                                       already owns 'doc.md')
- GET  /__last                     -> last served request "METHOD path"
- everything else                  -> echo of method/path/headers/body
"""

import http.server
import json
import sys

LAST_REQUEST = {"line": "", "body": ""}

LINK_TYPES = json.dumps({
    "issueLinkTypes": [
        {"id": "1", "name": "Blocks", "inward": "blocks",
         "outward": "is blocked by"},
        {"id": "2", "name": "Relates", "inward": "relates to",
         "outward": "relates to"},
    ]
})

FIELDS = json.dumps([
    {"id": "customfield_10001", "name": "Story Points",
     "schema": {"type": "number"}, "active": True},
    {"id": "customfield_10002", "name": "Story Points",
     "schema": {"type": "number"}, "active": True},
    {"id": "priority", "name": "Priority", "active": True},
])

CREATE_META = json.dumps({"projects": []})


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    """Serves canned Jira fixtures plus a generic echo."""

    def _respond(self, payload, status=200):
        encoded = payload.encode("utf-8") if isinstance(payload, str) \
            else payload
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _handle(self):
        if self.path == "/__last":
            self._respond(json.dumps(LAST_REQUEST))
            return
        body = ""
        if self.command in ("POST", "PUT", "PATCH"):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
        LAST_REQUEST["line"] = "%s %s" % (self.command, self.path)
        LAST_REQUEST["body"] = body
        if "/issueLinkType" in self.path:
            self._respond(LINK_TYPES)
            return
        if self.path.split("?")[0].endswith("/field"):
            auth = self.headers.get("Authorization", "")
            if "fieldfail" in auth:
                self._respond('{"errors": ["forbidden"]}', status=503)
                return
            self._respond(FIELDS)
            return
        if "fields=attachment" in self.path:
            payload = {
                "method": self.command,
                "path": self.path,
                "fields": {},
            }
            if "__attached" in self.path:
                payload["fields"]["attachment"] = [
                    {"id": 1, "name": "doc.md"}
                ]
            self._respond(json.dumps(payload))
            return
        if "/issue/createmeta" in self.path:
            self._respond(CREATE_META)
            return
        self._respond(json.dumps({
            "method": self.command,
            "path": self.path,
            "headers": {k: v for k, v in self.headers.items()},
            "body": body,
        }))

    do_GET = _handle
    do_POST = _handle
    do_PUT = _handle
    do_DELETE = _handle
    do_PATCH = _handle

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = http.server.HTTPServer(("127.0.0.1", port), FixtureHandler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
