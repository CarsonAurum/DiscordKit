# File: Tools/DiscordKitTools/scripts/test_verify_opus_audio_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Native-free regression checks for ordinary Opus oracle evidence validation."""
import copy
import unittest
import verify_opus_audio_oracle as oracle


class OpusAudioOracleTests(unittest.TestCase):
    """Require exhaustive policy/layout requests and reject unusable PCM/range evidence."""

    def test_request_matrix(self):
        """Both fixed output layouts cross ordinary, explicit-loss, FEC and direct-splice policies."""
        self.assertEqual(oracle.requests(), [(c, v) for c in (1, 2) for v in range(4)])

    def test_comparison_and_tolerance(self):
        """Exact ranges/counts and finite PCM within the declared tolerance are accepted."""
        streams = [{'operations': [{'action': 'loss', 'range': 0, 'pcm': [0., 0.5]}]}]
        actual = [[{'range': 0, 'pcm': [1e-7, 0.5]}]]
        self.assertEqual(oracle.compare(streams, actual), 1e-7)
        for bad in [[], [[{'range': 0, 'pcm': []}]], [[{'range': 1, 'pcm': [0., .5]}]],
                    [[{'pcm': [0., .5]}]], [[{'range': 0, 'pcm': [0., .6]}]],
                    [[{'range': 0, 'pcm': [float('nan'), .5]}]],
                    [[{'range': 0, 'pcm': [float('inf'), .5]}]]]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                oracle.compare(streams, bad)
        bad_reference = copy.deepcopy(streams)
        bad_reference[0]['operations'][0]['pcm'][0] = float('nan')
        with self.assertRaises(ValueError):
            oracle.compare(bad_reference, actual)

    def test_loss_tolerance_is_explicit_and_bounded(self):
        """PLC inherits the existing scalar CELT bound while ordinary streams keep the tighter bound."""
        stream = {'variant': 1, 'operations': [{'action': 'loss', 'range': 0, 'pcm': [0., .5]}]}
        actual = [[{'range': 0, 'pcm': [.005, .5]}]]
        self.assertEqual(oracle.compare([stream], actual), .005)
        for variant, error in [(0, .005), (1, .007)]:
            changed = copy.deepcopy(stream)
            changed['variant'] = variant
            with self.assertRaises(ValueError):
                oracle.compare([changed], [[{'range': 0, 'pcm': [error, .5]}]])

    def test_fixture_round_trip(self):
        """Generated Swift literals preserve native operation bytes, actions, PCM and ranges."""
        import base64
        import json
        fixture = {'channels': 2, 'variant': 1, 'operations': [
            {'action': 'fec', 'count': 960, 'bytes': [0, 255], 'range': 7, 'pcm': [-.1, .2]}]}
        text = oracle.fixture_text([fixture])
        literal = text.split('    "', 1)[1].split('"', 1)[0]
        self.assertEqual(json.loads(base64.b64decode(literal)), fixture)
        self.assertIn('libopus 1.6.1', text)
        self.assertIn('let opusAudioOracleFixtures: [String]', text)


if __name__ == '__main__':
    unittest.main()
