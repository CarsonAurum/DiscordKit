"""Deterministic validation of Gateway evidence accounting without executing workloads."""
import unittest

from record_gateway_baseline import validate_gateway


class GatewayBaselineTests(unittest.TestCase):
    """The recorder rejects missing lifecycle work and resource-retention regressions."""

    def report(self, burst=False):
        """Construct the smallest accounting report accepted by the release recorder."""
        return {"selectedShards": 4, "deliveredDispatches": 100, "targetDispatches": 100,
                "identifies": 4, "resumes": 4, "startupStormAdmitted": 4,
                "startupStormOffered": 40 if burst else 8, "peakOwnedConnections": 4,
                "ownedConnectionsAfterShutdown": 0, "leasesAfterShutdown": 0,
                "sampledPeakQueuedEvents": 16, "configuredMaximumQueuedEvents": 128,
                "configuredMaximumQueuedBytes": 262_144, "heartbeats": 4, "heartbeatACKs": 4,
                "controlDelay": {"sampleCount": 4}, "eventLag": {"sampleCount": 100}}

    def test_normal_and_burst(self):
        """Both offered-storm policies retain the same four actual startup admissions."""
        for burst in (False, True):
            validate_gateway(self.report(burst), burst)

    def test_invariants(self):
        """Lost dispatches, missing Resume, multiplied allowance and retained leases fail closed."""
        for key, value in (("deliveredDispatches", 99), ("resumes", 3), ("identifies", 5),
                           ("startupStormAdmitted", 5), ("peakOwnedConnections", 5),
                           ("ownedConnectionsAfterShutdown", 1), ("leasesAfterShutdown", 1),
                           ("sampledPeakQueuedEvents", 33), ("heartbeatACKs", 0)):
            report = self.report()
            report[key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                validate_gateway(report, False)

    def test_sample_bound(self):
        """Large workloads retain exactly the first 4,096 event latency observations."""
        report = self.report()
        report.update(targetDispatches=100_000, deliveredDispatches=100_000,
                      eventLag={"sampleCount": 4_096})
        validate_gateway(report, False)
        report["eventLag"]["sampleCount"] = 100_000
        with self.assertRaises(RuntimeError):
            validate_gateway(report, False)


if __name__ == "__main__":
    unittest.main()
