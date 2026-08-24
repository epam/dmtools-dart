#!/usr/bin/env python3
"""Scripted GitHub API fixture server for GitHubSyncTools tests.

Dart's HttpServer runs on the event loop, frozen during
`Process.runSync('curl', ...)`; this Python subprocess serves the curl
requests instead (same pattern as test/js/test_echo_server.py).

Serves canned GitHub REST/GraphQL shapes for the multi-request tool
flows (paginated comments, pending-review submit, releases, log-ZIP
redirect + download) and a generic JSON echo for everything else.

Usage:
    python3 github_fixture_server.py [port] [request_log]

Prints the bound port to stdout, appends one `METHOD path` line per
request to the request log, and mirrors the last echoed request JSON to
`<request_log>.last.json` (for asserting the final request of a flow).
"""

import http.server
import io
import json
import sys
import zipfile

FIXTURE_PR = {
    "number": 42,
    "title": "Add feature",
    "head": {"sha": "abc123def456"},
    "merged_at": None,
}

FIXTURE_PRS = [
    {"number": 1, "title": "A", "merged_at": "2024-01-01T00:00:00Z"},
    {"number": 2, "title": "B", "merged_at": None},
]

INLINE_COMMENTS = [
    {"id": 1, "path": "src/a.txt", "body": "root",
     "created": "2024-01-02T00:00:00Z", "in_reply_to_id": None},
    {"id": 2, "path": "src/a.txt", "body": "reply",
     "created": "2024-01-03T00:00:00Z", "in_reply_to_id": 1},
    {"id": 3, "path": "src/b.txt", "body": "orphan reply",
     "created": "2024-01-04T00:00:00Z", "in_reply_to_id": 99},
]

ISSUE_COMMENTS = [
    {"id": 10, "body": "issue comment",
     "created": "2024-01-01T00:00:00Z", "in_reply_to_id": None},
]

FIXTURE_RELEASES = [
    {"id": 5, "tag_name": "existing-tag", "name": "Existing Draft",
     "draft": True, "assets": [{"id": 77, "name": "report.txt"}]},
]

DIFF_TEXT = """diff --git a/src/a.txt b/src/a.txt
--- a/src/a.txt
+++ b/src/a.txt
@@ -1 +1,2 @@
-old
+new
+extra
"""


def build_zip():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("job1.txt", "step one log\n")
        zf.writestr("job2.txt", "step two log\n")
        zf.writestr("skip.bin", "not a text entry")
    return buf.getvalue()


class FixtureState(object):
    log_path = None
    last_path = None


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length).decode("utf-8", errors="replace")

    def _respond(self, code, payload, content_type="application/json"):
        if isinstance(payload, bytes):
            encoded = payload
        elif isinstance(payload, str):
            encoded = payload.encode("utf-8")
        else:
            encoded = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _record(self, body):
        if FixtureState.log_path:
            with open(FixtureState.log_path, "a") as fh:
                fh.write("%s %s\n" % (self.command, self.path))
        if FixtureState.last_path:
            with open(FixtureState.last_path, "w") as fh:
                fh.write(json.dumps({
                    "method": self.command,
                    "path": self.path,
                    "headers": {k: v for k, v in self.headers.items()},
                    "body": body,
                }))

    def _serve(self):
        body = ""
        if self.command in ("POST", "PUT", "PATCH"):
            body = self._read_body()
        path = self.path
        # Route matching ignores the query string (pagination params etc.).
        base = path.split("?")[0]
        accept = self.headers.get("Accept", "")

        # Workflow run logs: 302 redirect to the ZIP archive.
        if base.endswith("/actions/runs/55/logs"):
            self._record(body)
            self.send_response(302)
            self.send_header(
                "Location",
                "http://127.0.0.1:%d/zip" % self.server.server_address[1],
            )
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if base == "/zip":
            self._record(body)
            self._respond(200, build_zip(), "application/zip")
            return

        # PR endpoint answers a diff when asked with the diff accept header.
        is_pr_root = (
            base.startswith("/repos/o/r/pulls/42")
            and "comments" not in path
            and "merge" not in path
            and "reviews" not in path
        )
        if is_pr_root:
            self._record(body)
            if "vnd.github.diff" in accept:
                self._respond(200, DIFF_TEXT, "text/plain")
            else:
                self._respond(200, FIXTURE_PR)
            return

        if base == "/repos/o/r/pulls":
            self._record(body)
            self._respond(200, FIXTURE_PRS)
            return
        if base.endswith("/pulls/42/comments"):
            self._record(body)
            self._respond(200, INLINE_COMMENTS)
            return
        if base.endswith("/issues/42/comments"):
            self._record(body)
            self._respond(200, ISSUE_COMMENTS)
            return
        if base.endswith("/pulls/42/reviews"):
            self._record(body)
            self._respond(200, [{"id": 9, "state": "PENDING"}])
            return
        if base.endswith("/releases") and self.command == "GET":
            self._record(body)
            self._respond(200, FIXTURE_RELEASES)
            return
        if base.endswith("/releases/5/assets") and self.command == "GET":
            self._record(body)
            self._respond(200, [{"id": 77, "name": "report.txt"}])
            return

        # Uploads host prefix (custom base path keeps /uploads).
        if base.startswith("/uploads/"):
            self._record(body)
            self._respond(200, {"id": 78, "name": "report.txt",
                                "browser_download_url": "https://dl/x"})
            return

        self._record(body)
        self._respond(200, {
            "method": self.command,
            "path": path,
            "headers": {k: v for k, v in self.headers.items()},
            "body": body,
        })

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
        FixtureState.log_path = sys.argv[2]
        FixtureState.last_path = sys.argv[2] + ".last.json"
    server = http.server.HTTPServer(("127.0.0.1", port), FixtureHandler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
