"""Hermetic adaptive verifier tests; no native compiler, archive, network or device access."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import verify_celt_adaptive_oracle as verifier


class CELTAdaptiveVerifierTests(unittest.TestCase):
    """Require explicit adaptive selection, reproducible inputs and fail-closed evidence ownership."""

    def test_driver_selects_adaptive_and_rejects_helper_drift(self):
        """No changed or duplicated anchor can silently leave the encoder on fixed analysis."""
        source = verifier.adaptive_driver()
        self.assertIn('analysisPolicy:.adaptive', source)
        self.assertIn('if r.isTransient{ownTransientFrames += 1}', source)
        self.assertIn('ownTransientFrames:ownTransientFrames', source)
        original = verifier.frame.SWIFT_DRIVER
        for invalid in (original.replace('endBand:f.end);ownDecoder=', 'changed'),
                        original + '\nendBand:f.end);ownDecoder='):
            with patch.object(verifier.frame, 'SWIFT_DRIVER', invalid):
                with self.assertRaises(ValueError):
                    verifier.adaptive_driver()

    def test_fixture_inputs_cover_transient_formats(self):
        """All six independent streams retain exact durations, channels and silence/onset structure."""
        values = verifier.fixture_inputs()
        self.assertEqual(values, verifier.fixture_inputs())
        self.assertEqual(len(values), 6)
        self.assertEqual({(value['frames'][0]['n'], value['c']) for value in values},
                         {(size, channels) for size in (240, 480, 960) for channels in (1, 2)})
        for value in values:
            self.assertEqual(len(value['frames']), 5)
            self.assertFalse(any(value['frames'][0]['pcm']))
            self.assertTrue(any(value['frames'][1]['pcm']))
            self.assertTrue(any(value['frames'][-1]['pcm']))
            for frame in value['frames']:
                self.assertEqual(frame['bytes'], 160)
                self.assertEqual(frame['end'], 21)
                self.assertEqual(len(frame['pcm']), frame['n'] * value['c'])
                self.assertTrue(all(-1 <= sample <= 1 for sample in frame['pcm']))

    def test_fixture_check_is_nonwriting_until_requested(self):
        """Missing/different fixtures fail without mutation; explicit regeneration is byte-stable."""
        records = [dict(input=dict(c=1, frames=[]), encodedOutput=[])]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'fixture.swift'
            with self.assertRaises(ValueError):
                verifier.check_fixture(path, records)
            self.assertFalse(path.exists())
            verifier.check_fixture(path, records, write=True)
            original = path.read_bytes()
            verifier.check_fixture(path, copy.deepcopy(records))
            self.assertEqual(path.read_bytes(), original)
            with self.assertRaises(ValueError):
                verifier.check_fixture(path, records + records)
            self.assertEqual(path.read_bytes(), original)
            verifier.check_fixture(path, records + records, write=True)
            self.assertNotEqual(path.read_bytes(), original)

    def test_snapshot_isolated_and_source_drift_rejected(self):
        """Compiled copies remain immutable while live edits/deletions prevent publishing stale evidence."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / 'repo'
            name = 'Sources/Codec.swift'
            source = repository / name
            source.parent.mkdir(parents=True)
            source.write_text('struct Original {}\n')
            with patch.object(verifier.frame, 'OWNED_PATHS', (name,)):
                snapshot, fingerprints = verifier.snapshot_owned(repository, root)
            self.assertEqual((snapshot / name).read_text(), source.read_text())
            verifier.require_unchanged_sources(repository, fingerprints)
            source.write_text('struct Changed {}\n')
            with self.assertRaises(ValueError):
                verifier.require_unchanged_sources(repository, fingerprints)
            self.assertEqual((snapshot / name).read_text(), 'struct Original {}\n')
            source.unlink()
            with self.assertRaises(ValueError):
                verifier.require_unchanged_sources(repository, fingerprints)

    def test_snapshot_detects_change_during_copy(self):
        """A file changed between initial fingerprinting and copying never supplies mixed source evidence."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / 'repo'
            name = 'Sources/Codec.swift'
            source = repository / name
            source.parent.mkdir(parents=True)
            source.write_text('old')
            original_copy = verifier.shutil.copyfile
            def changed_copy(incoming, outgoing):
                """Simulate one concurrent source mutation immediately before the bounded copy."""
                incoming.write_text('new')
                return original_copy(incoming, outgoing)
            with patch.object(verifier.frame, 'OWNED_PATHS', (name,)), \
                    patch.object(verifier.shutil, 'copyfile', changed_copy):
                with self.assertRaises(ValueError):
                    verifier.snapshot_owned(repository, root)

    def test_transient_telemetry_requires_bounded_integer_counts(self):
        """Missing, boolean, negative and excessive counters cannot inflate adaptive-path evidence."""
        inputs = [dict(frames=[{}, {}]), dict(frames=[{}])]
        self.assertEqual(verifier.owned_transient_count(inputs,
                         [dict(ownTransientFrames=2), dict(ownTransientFrames=0)]), 2)
        for count in (None, True, -1, 3, 1.0, '1'):
            with self.assertRaises(ValueError):
                verifier.owned_transient_count(inputs,
                    [dict(ownTransientFrames=count), dict(ownTransientFrames=0)])
        with self.assertRaises(ValueError):
            verifier.owned_transient_count(inputs, [])


if __name__ == '__main__':
    unittest.main()
