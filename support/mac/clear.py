#!/usr/bin/env python3
"""Serve a short-lived, loopback-only page that clears Control Module browser storage."""

from __future__ import annotations

import argparse
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HOST = "127.0.0.1"
MAX_LIFETIME_SECONDS = 8.0
QUIET_PERIOD_SECONDS = 2.0

PAGE = b"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Control Module removed</title></head>
<body>
  <p>Control Module browser data was cleared. You can close this tab.</p>
  <script>
    localStorage.clear();
    sessionStorage.clear();
    if (window.caches) caches.keys().then((keys) => Promise.all(keys.map((key) => caches.delete(key))));
  </script>
</body>
</html>
"""


class CleanupHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.server.last_request_at = time.monotonic()  # type: ignore[attr-defined]
        host = self.headers.get("Host", "").partition(":")[0].lower()
        if host in {"127.0.0.1", "localhost"}:
            self.server.seen_hosts.add(host)  # type: ignore[attr-defined]
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Clear-Site-Data", '"cache", "cookies", "storage"')
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
        )
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, _format: str, *_args: object) -> None:
        return


class CleanupServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    last_request_at: float | None = None

    def __init__(self, server_address: tuple[str, int], handler: type[BaseHTTPRequestHandler]):
        self.seen_hosts: set[str] = set()
        super().__init__(server_address, handler)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    arguments = parser.parse_args()
    if not 1025 <= arguments.port <= 65535 or arguments.port == 10001:
        parser.error("port must be 1025–65535 and cannot be 10001")

    server = CleanupServer((HOST, arguments.port), CleanupHandler)
    server.timeout = 0.25
    started_at = time.monotonic()
    try:
        while time.monotonic() - started_at < MAX_LIFETIME_SECONDS:
            server.handle_request()
            if (
                server.last_request_at is not None
                and time.monotonic() - server.last_request_at >= QUIET_PERIOD_SECONDS
            ):
                break
    finally:
        server.server_close()
    if server.seen_hosts != {"127.0.0.1", "localhost"}:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
