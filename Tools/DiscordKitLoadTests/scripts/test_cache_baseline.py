"""Validate exact local cache/recovery evidence without running performance work."""
import unittest

from record_cache_baseline import validate_cache


class CacheBaselineTests(unittest.TestCase):
    """Reports cannot hide lost work, multiplied retention or incomplete cleanup."""

    def report(self, burst=False):
        """Construct a coherent two-round/two-scope report with separate actual RSS."""
        return {"configuredRounds": 2, "completedRounds": 2, "selectedScopes": 2,
                "workingSetKeysPerScope": 20, "offeredRefreshCalls": 256 if burst else 64,
                "completedRefreshCalls": 32, "actualLoaderCalls": 4,
                "capacityRefusals": 224 if burst else 32, "coalescedReads": 28,
                "evictions": 16, "expirations": 64, "recoveryReads": 4,
                "healthyBroadcastDeliveries": 6, "slowSubscriberResynchronizations": 2,
                "maximumEntries": 32, "peakEntries": 32,
                "maximumAccountedBytes": 131_072, "peakAccountedBytes": 32_000,
                "peakRefreshes": 1, "peakWaiters": 8, "peakBufferedEvents": 2,
                "durationSeconds": 0.1, "afterShutdown": {"peakRSSBytes": 1_000_000},
                "checkpoints": [{"completedRounds": 0, "elapsedSeconds": 0, "entries": 0, "accountedBytes": 0,
                                 "process": {"peakRSSBytes": 1_000_000}},
                                {"completedRounds": 2, "elapsedSeconds": 0.1, "entries": 0, "accountedBytes": 0,
                                 "process": {"peakRSSBytes": 1_000_000}}],
                "entriesAfterShutdown": 0, "refreshesAfterShutdown": 0, "waitersAfterShutdown": 0,
                "subscriptionsAfterShutdown": 0, "bufferedEventsAfterShutdown": 0}

    def test_both_offered_storms_preserve_one_loader_per_scope_round(self):
        """Normal and burst modes change refusals while preserving eight-to-one completed-read reduction."""
        for burst in (False, True):
            validate_cache(self.report(burst), burst)

    def test_lost_work_and_exceeded_resource_limits_are_rejected(self):
        """Every work, bounds, timing and ownership gate rejects a concrete counter regression."""
        for key, value in (("configuredRounds", 0), ("completedRounds", 1), ("selectedScopes", 3),
                           ("workingSetKeysPerScope", 21), ("offeredRefreshCalls", 63),
                           ("completedRefreshCalls", 31), ("actualLoaderCalls", 5), ("capacityRefusals", 31),
                           ("coalescedReads", 27), ("evictions", 15), ("expirations", 63), ("recoveryReads", 3),
                           ("healthyBroadcastDeliveries", 5), ("slowSubscriberResynchronizations", 1),
                           ("maximumEntries", 33), ("peakEntries", 33), ("maximumAccountedBytes", 1),
                           ("peakAccountedBytes", 131_073), ("peakAccountedBytes", 0),
                           ("peakRefreshes", 2), ("peakWaiters", 9), ("peakBufferedEvents", 3),
                           ("durationSeconds", 0), ("entriesAfterShutdown", 1), ("refreshesAfterShutdown", 1),
                           ("waitersAfterShutdown", 1), ("subscriptionsAfterShutdown", 1),
                           ("bufferedEventsAfterShutdown", 1), ("afterShutdown", {"peakRSSBytes": 0})):
            report = self.report()
            report[key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                validate_cache(report, False)

    def test_duration_and_checkpoint_evidence(self):
        """Duration runs need actual elapsed time and a bounded coherent initial/final history."""
        report = self.report()
        report["configuredDurationSeconds"] = 1
        with self.assertRaises(RuntimeError):
            validate_cache(report, False)
        report["durationSeconds"] = 1
        report["checkpoints"][-1]["elapsedSeconds"] = 1
        validate_cache(report, False)
        for samples in ([], report["checkpoints"] * 61,
                        [{"completedRounds": 1, "elapsedSeconds": 0, "entries": 0, "accountedBytes": 0}, report["checkpoints"][-1]]):
            report["checkpoints"] = samples
            with self.assertRaises(RuntimeError):
                validate_cache(report, False)

    def test_checkpoint_history_cannot_hide_resource_or_time_regressions(self):
        """Every retained checkpoint needs positive actual RSS, monotonic work and coherent cleanup."""
        for key, value in (("accountedBytes", -1), ("accountedBytes", 1), ("entries", -1),
                           ("elapsedSeconds", 0.09), ("elapsedSeconds", float("nan")),
                           ("completedRounds", 3), ("process", {"peakRSSBytes": 0})):
            report = self.report()
            report["checkpoints"][-1][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                validate_cache(report, False)
        report = self.report()
        report["checkpoints"].insert(1, {"completedRounds": 3, "elapsedSeconds": 0.05, "entries": 0,
                                         "accountedBytes": 0, "process": {"peakRSSBytes": 1_000_000}})
        with self.assertRaises(RuntimeError):
            validate_cache(report, False)


if __name__ == "__main__":
    unittest.main()
