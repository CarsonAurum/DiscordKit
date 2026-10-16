#!/usr/bin/env python3
"""Credential-free loopback HTTP/1.1 peer for the separate transport load package."""
import argparse
import json
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class LoadServer(ThreadingHTTPServer):
    """Bound the listener backlog; clients separately cap active connections."""
    request_queue_size = 512
    daemon_threads = True

    def __init__(self, *args, **kwargs):
        """Initialize bounded socket counters before the listener accepts any peer."""
        self.connection_lock = threading.RLock()
        self.accepted_connections = 0
        self.active_connections = 0
        self.peak_connections = 0
        super().__init__(*args, **kwargs)

    def get_request(self):
        """Count physical accepted sockets, including keepalive idle connections."""
        request, address = super().get_request()
        with self.connection_lock:
            self.accepted_connections += 1
            self.active_connections += 1
            self.peak_connections = max(self.peak_connections, self.active_connections)
        return request, address

    def shutdown_request(self, request):
        """Close an accepted socket before releasing its active connection count."""
        try:
            super().shutdown_request(request)
        finally:
            with self.connection_lock:
                self.active_connections -= 1

    def metrics(self):
        """Snapshot bounded aggregate counts without identity/address metric labels."""
        with self.connection_lock:
            return dict(acceptedConnections=self.accepted_connections,
                        activeConnections=self.active_connections,
                        peakConnections=self.peak_connections)


class PayloadHandler(BaseHTTPRequestHandler):
    """Serve an exact fixed payload and avoid request/identity diagnostic labels."""
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        """Return a fixed response compatible with connection reuse and empty bodies."""
        payload = self.server.payload
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Content-Type", "application/octet-stream")
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()

    def log_message(self, format, *args):
        """Suppress peer/path/header logging in both successes and failures."""


def make_server(payload_bytes):
    """Bind IPv4 loopback with a bounded payload; caller owns server shutdown."""
    if not 0 <= payload_bytes <= 1_048_576:
        raise ValueError("payload bytes outside local peer limit")
    server = LoadServer(("127.0.0.1", 0), PayloadHandler)
    server.payload = b"x" * payload_bytes
    return server


def main():
    """Publish the bound port once, then serve until the owning harness terminates."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload-bytes", type=int, required=True)
    args = parser.parse_args()
    with make_server(args.payload_bytes) as server:
        def terminate(signum, frame):
            """Publish aggregate socket evidence and exit after the owner closes its client."""
            print(json.dumps(server.metrics()), flush=True)
            raise SystemExit(0)

        signal.signal(signal.SIGTERM, terminate)
        print(server.server_port, flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
