#!/usr/bin/env python3
"""Canned-response fixture server for the PR-review contract tests.

Dart's HttpServer runs on the event loop, frozen during
`Process.runSync('curl', ...)`; this Python subprocess serves the curl
requests instead (same pattern as test/js/test_echo_server.py and
sync_tools/github_fixture_server.py).

Unlike the scripted servers, the canned status + body come from a control
JSON file that the Dart test rewrites between fixtures, so one server
instance replays every recorded Java response (200 reviews, 422
body-required rejections, GitLab MR approval objects).

Usage:
    python3 pr_review_fixture_server.py [port] [control_json] [request_log]

Prints the bound port to stdout, re-reads the control file
`{"status": <int>, "body": <string>}` before each request, answers every
request with it, and mirrors the last request as JSON to
`<request_log>.last.json` (same convention as github_fixture_server.py).
"""

import http.server
import json
import sys


class FixtureState(object):
    control_path = None
    last_path = None


class CannedHandler(http.server.BaseHTTPRequestHandler):
    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length).decode("utf-8", errors="replace")

    def _serve(self):
        body = ""
        if self.command in ("POST", "PUT", "PATCH"):
            body = self._read_body()
        with open(FixtureState.control_path) as fh:
            canned = json.load(fh)
        if FixtureState.last_path:
            with open(FixtureState.last_path, "w") as fh:
                json.dump({
                    "method": self.command,
                    "path": self.path,
                    "headers": {k: v for k, v in self.headers.items()},
                    "body": body,
                }, fh)
        encoded = canned.get("body", "").encode("utf-8")
        self.send_response(int(canned.get("status", 200)))
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    do_GET = _serve
    do_POST = _serve
    do_PUT = _serve
    do_DELETE = _serve
    do_PATCH = _serve

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    if len(sys.argv) > 2:
        FixtureState.control_path = sys.argv[2]
    if len(sys.argv) > 3:
        FixtureState.last_path = sys.argv[3] + ".last.json"
    server = http.server.HTTPServer(("127.0.0.1", port), CannedHandler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
