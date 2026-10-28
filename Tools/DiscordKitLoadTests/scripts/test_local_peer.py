# File: Tools/DiscordKitLoadTests/scripts/test_local_peer.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Deterministic HTTP framing and validation checks for the local load peer."""
import http.client
import threading
import unittest
from local_peer import make_server


class LocalPeerTests(unittest.TestCase):
    """Verify empty/nonempty framing, keepalive reuse, and fixed payload bounds."""

    def test_payload_and_reuse(self):
        """Two requests on one connection return exactly the configured body."""
        for size in (0, 1024):
            with self.subTest(size=size), make_server(size) as server:
                worker = threading.Thread(target=server.serve_forever)
                worker.start()
                connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
                try:
                    for _ in range(2):
                        connection.request("GET", "/payload")
                        response = connection.getresponse()
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.read(), b"x" * size)
                    self.assertEqual(server.metrics(), dict(acceptedConnections=1, activeConnections=1, peakConnections=1))
                finally:
                    connection.close()
                    server.shutdown()
                    worker.join()

    def test_invalid_limits(self):
        """Negative and oversized payloads fail before binding any listener."""
        for size in (-1, 1_048_577):
            with self.assertRaises(ValueError):
                make_server(size)


if __name__ == "__main__":
    unittest.main()
