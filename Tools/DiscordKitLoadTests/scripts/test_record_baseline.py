# File: Tools/DiscordKitLoadTests/scripts/test_record_baseline.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Verify offline HTTP baseline gates independently from process timing and sockets."""
import unittest
from unittest.mock import patch

from record_baseline import environment, validate_http


class HTTPBaselineTests(unittest.TestCase):
    """Exercise failure, ownership, resource and request-reduction acceptance rules."""

    def report(self):
        """Return the smallest complete successful HTTP gate input."""
        return {
            "failedRequests": 0, "cancelledRequests": 0, "activeAfterShutdown": 0,
            "queuedAfterShutdown": 0, "flightsAfterShutdown": 0, "cacheEntriesAfterShutdown": 0,
            "sampledResourceBudgetsMet": True, "rssBudgetMet": True,
            "avoidedExchanges": 10, "retryResponses": 1, "minimumIdentitySuccesses": 1,
            "refusedRequests": 0, "targetP99Met": True,
        }

    def test_normal_and_burst(self):
        """Normal gates require p99/no refusal; bursts retain resource gates with explicit refusals."""
        validate_http(self.report(), False)
        report = self.report()
        report.update(refusedRequests=100, targetP99Met=False)
        validate_http(report, True)
        with self.assertRaises(RuntimeError):
            validate_http(report, False)

    def test_rejects_failed_gates(self):
        """Each independent failure or resource-cleanup violation prevents recording a passing baseline."""
        for key, value in (
            ("failedRequests", 1), ("cancelledRequests", 1), ("activeAfterShutdown", 1),
            ("queuedAfterShutdown", 1), ("flightsAfterShutdown", 1), ("cacheEntriesAfterShutdown", 1),
            ("sampledResourceBudgetsMet", False), ("rssBudgetMet", False), ("avoidedExchanges", 0),
            ("retryResponses", 0), ("minimumIdentitySuccesses", 0),
        ):
            with self.subTest(key=key):
                report = self.report()
                report[key] = value
                with self.assertRaises(RuntimeError):
                    validate_http(report, True)

    def test_http_environment_scope(self):
        """HTTP metadata distinguishes an offline script from transport sockets and makes no quota claim."""
        with patch("record_baseline.capture", return_value="test"), patch("record_baseline.platform.system", return_value="Other"):
            context = environment("http")
        self.assertIn("zero credentials and sockets", context["peer"])
        self.assertIn("no Discord quota", context["measurementScope"])


if __name__ == "__main__":
    unittest.main()
