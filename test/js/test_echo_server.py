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
import urllib.parse


class EchoHandler(http.server.BaseHTTPRequestHandler):
    """Echoes request details as a JSON response."""

    DELETE_LOG = []

    def _send(self, encoded, content_type="application/json"):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _handle(self):
        body = ""
        if self.command in ("POST", "PUT", "PATCH"):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
        if self.command == "DELETE":
            EchoHandler.DELETE_LOG.append(self.path)
        payload = {
            "method": self.command,
            "path": self.path,
            "headers": {k: v for k, v in self.headers.items()},
            "body": body,
        }
        # JS source fixture for the URL-jsPath tests: serves an agent script
        # (with the action() contract) as plain text so the loader can eval
        # it — mirrors a raw.githubusercontent.com fetch.
        if self.path.startswith("/script.js"):
            encoded = b'function action(params) { return "from-url"; }'
            self._send(encoded, "text/javascript")
            return
        # Recorded DELETE paths, so tests can assert which deletions the
        # client performed against this server instance.
        if self.path == "/__delete_log":
            self._send(json.dumps(EchoHandler.DELETE_LOG).encode("utf-8"))
            return
        # ADO build-timeline stub for the pipeline-logs tests (build 12):
        # the timeline answers mixed record types (Stage records are skipped
        # by the client; the Test task carries no log id). Other build ids
        # keep the bare echo payload (no records).
        if "/build/builds/12/timeline" in self.path:
            payload["records"] = [
                {"type": "Stage", "name": "Build stage", "log": {"id": 1}},
                {"type": "Task", "name": "Build", "log": {"id": 5}},
                {"type": "Task", "name": "Test", "log": {"id": 0}},
            ]
        # ADO build-log stub: raw text lines (not JSON) like the real
        # /build/builds/{id}/logs/{logId} endpoint.
        elif "/logs/" in self.path:
            self._send(b"log-line-1\nlog-line-2\nlog-line-3", "text/plain")
            return
        # GitLab MR-list fixture: a state=all listing answers a JSON array
        # so the client-side closed/merged filter runs.
        elif self.command == "GET" and "/merge_requests?state=all" in self.path:
            self._send(json.dumps([
                {"iid": 1, "state": "merged"},
                {"iid": 2, "state": "opened"},
            ]).encode("utf-8"))
            return
        # GitLab release-asset fixtures: the release links and the generic
        # packages listings answer JSON arrays (matching the uploaded asset
        # name / the queried package name+version).
        elif self.command == "GET" and "/assets/links" in self.path:
            self._send(json.dumps([
                {"id": 41, "name": "app.zip"}
            ]).encode("utf-8"))
            return
        elif (self.command == "GET" and "/packages?" in self.path
              and "package_type=generic" in self.path):
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            self._send(json.dumps([
                {
                    "id": 9,
                    "name": query.get("package_name", [""])[0],
                    "version": query.get("package_version", [""])[0],
                }
            ]).encode("utf-8"))
            return
        # Confluence content fixtures: a page GET (777) answers a page
        # object and a child listing (99) answers a results array, both
        # with storage bodies, so the format=markdown conversion runs.
        elif (self.command == "GET"
              and "/wiki/rest/api/content/777" in self.path
              and "/child/" not in self.path):
            payload.clear()
            payload["id"] = "777"
            payload["body"] = {
                "storage": {
                    "value": "<p>hi</p>",
                    "representation": "storage",
                }
            }
        elif self.command == "GET" and "/wiki/rest/api/content/99/child/page" in self.path:
            payload.clear()
            payload["results"] = [
                {
                    "id": "901",
                    "body": {
                        "storage": {
                            "value": "<p>child</p>",
                            "representation": "storage",
                        }
                    },
                }
            ]
        elif (self.command == "GET" and "/pipelines?" in self.path
              and urllib.parse.parse_qs(
                  urllib.parse.urlparse(self.path).query
              ).get("per_page") == ["2"]):
            # GitLab pipelines pagination fixture: full pages of two runs
            # so the client's per_page/maxResults walk is exercised.
            self._send(json.dumps([{"id": 1}, {"id": 2}]).encode("utf-8"))
            return
        # ADO stub shapes for the WIQL two-step regression test: the WIQL
        # POST answers id/url stubs, the ids= detail GET answers full items
        # (mirrors the real dev.azure.com response envelopes).
        if "/wit/wiql" in self.path:
            payload["workItems"] = [{"id": 7, "url": "stub://7"}]
        elif "/wit/workitems" in self.path and "ids=" in self.path:
            payload["count"] = 1
            payload["value"] = [
                {"id": 7, "fields": {"System.Title": "T"}}
            ]
        # Jira label-fetch fixture: a normal ?fields=labels GET answers the
        # ticket's current labels; __jira_fail=1 marks the GET as a transient
        # 5xx (regression guard: a failed fetch must abort, never PUT an
        # empty set).
        elif "fields=labels" in self.path:
            if "__jira_fail" in self.path:
                encoded = b'{"errors": ["transient"]}'
                self.send_response(503)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)
                return
            payload["fields"] = {"labels": ["existing"]}
        response = json.dumps(payload)
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
