"""Hermetic coverage for the encoder policy verifier; no compiler, archive or device access."""
import copy
import math
from pathlib import Path
import struct
import tempfile
import unittest
import wave

from verify_opus_encoder_policy import compare_native, fec_dtx_cases, native_commands, percentile, quality, signal, validate_fec_recovery, validate_owned, wav_signal


class EncoderPolicyVerifierTests(unittest.TestCase):
    """Check diagnostic math and ensure missing/nonfinite/mismatched evidence cannot pass."""

    def test_signal_features_and_reproducibility(self):
        """Both channels remain normalized, distinct and repeatable, including actual silent gaps."""
        for kind in ('speech', 'music', 'dtx'):
            frames = signal(kind, 2, 20)
            self.assertEqual(frames, signal(kind, 2, 20))
            self.assertEqual(len(frames), 20)
            self.assertTrue(all(len(frame) == 1920 for frame in frames))
            self.assertTrue(all(math.isfinite(v) and abs(v) <= 1 for frame in frames for v in frame))
            self.assertNotEqual(frames[0][::2], frames[0][1::2])
            self.assertFalse(any(frames[-1]))
            if kind == 'dtx':
                self.assertFalse(any(frames[8]))
                self.assertTrue(any(frames[12]))
        for invalid in [('unknown', 1, 20), ('speech', 3, 20), ('music', 1, 301), ('speech', 1, 0)]:
            with self.assertRaises(ValueError):
                signal(*invalid)

    def test_nearest_rank_and_rejected_measurements(self):
        """A single slow outlier remains visible in a small measured p99 sample."""
        self.assertEqual(percentile(list(range(1, 61)), .99), 60)
        self.assertEqual(percentile([2, 1, 3, 4], .5), 2)
        for values, quantile in [([], .99), ([1], 0), ([1], 1.1), ([-1], .5), ([float('nan')], .5), ([float('inf')], .99)]:
            with self.assertRaises(ValueError):
                percentile(values, quantile)

    def test_quality_recovers_delay_without_gain_fitting(self):
        """A known nonperiodic delayed stream aligns; attenuation still lowers the unscaled SNR."""
        source = [value for frame in signal('music', 1, 12) for value in frame]
        delayed = [0.0] * 120 + source[:-120]
        result = quality(source, delayed, 1)
        self.assertEqual(result['delaySamples'], 120)
        self.assertGreater(result['snrDB'], 100)
        attenuated = quality(source, [v * .5 for v in delayed], 1)
        self.assertAlmostEqual(attenuated['snrDB'], 20 * math.log10(2), places=5)
        self.assertEqual(attenuated['clippedSampleCount'], 0)
        with self.assertRaises(ValueError):
            quality(source, delayed[:-1], 1)
        delayed[0] = float('nan')
        with self.assertRaises(ValueError):
            quality(source, delayed, 1)

    def test_independent_comparison_fails_closed(self):
        """Missing frames, range mismatch, malformed dimensions and NaN are never evidence of success."""
        case = dict(channels=1, dtx=False, frames=[[0.0] * 960])
        packet = dict(bytes=[248], pcm=[0.1] * 960, range=12)
        cases, owned, native = [case], [[packet]], [[copy.deepcopy(packet)]]
        self.assertEqual(compare_native(cases, owned, native), 0)
        self.assertEqual(native_commands(cases, owned), b'1 1\n0 1 248\n')
        for mutation in ('range', 'pcm', 'nan', 'tolerance', 'missing'):
            changed = copy.deepcopy(native)
            if mutation == 'range':
                changed[0][0]['range'] += 1
            elif mutation == 'pcm':
                changed[0][0]['pcm'].pop()
            elif mutation == 'nan':
                changed[0][0]['pcm'][0] = float('nan')
            elif mutation == 'tolerance':
                changed[0][0]['pcm'][0] += .001
            else:
                changed[0].clear()
            with self.assertRaises(ValueError):
                compare_native(cases, owned, changed)
        with self.assertRaises(ValueError):
            native_commands(cases, [])

    def test_packet_budget_and_dtx_refresh_admission(self):
        """Suppression must be real, bounded by 400ms, with ordinary refreshes inside the allocation."""
        packet = dict(bytes=[248, 1, 2], budget=3, dtx=False, transmit=True)
        suppressed = dict(bytes=[248], budget=3, dtx=True, transmit=False)
        case = dict(rate=1200, dtx=True, frames=[[]] * 22)
        packets = [packet] + [suppressed] * 19 + [packet, suppressed]
        validate_owned([case], [packets])
        for invalid in [packets[:-1], [suppressed] * 22,
                        [dict(packet, budget=4)] * 22, [dict(packet, bytes=[])] * 22,
                        [dict(suppressed, transmit=True)] * 22, [packet] * 22]:
            with self.assertRaises(ValueError):
                validate_owned([case], [invalid])
        with self.assertRaises(ValueError):
            validate_owned([case], [])

    def test_fec_dtx_cases_keep_bounded_format_and_signal(self):
        """Four additional formats retain the original DTX signal and explicit finite LBRR budgets."""
        cases = fec_dtx_cases()
        self.assertEqual({(case['mode'], case['channels']) for case in cases},
                         {('silk', 1), ('silk', 2), ('hybrid', 1), ('hybrid', 2)})
        self.assertEqual(len(cases), 4)
        for case in cases:
            self.assertIs(case['fec'], True)
            self.assertIs(case['dtx'], True)
            self.assertEqual(case['kind'], 'fec-dtx')
            self.assertEqual(case['rate'], 256_000 if case['channels'] == 1 else 384_000)
            self.assertLessEqual(case['rate'] // 400, 1276)
            self.assertEqual(case['frames'], signal('dtx', case['channels']))
            self.assertFalse(any(case['frames'][10]) or any(case['frames'][51]))
            self.assertTrue(any(case['frames'][2]) and any(case['frames'][52]))

    def test_fec_recovery_selected_lbrr_plc_and_operation_provenance(self):
        """Recovery cannot pass with absent LBRR, reordered/missing frames or substituted packet bytes."""
        case = dict(mode='silk', channels=1, fec=True, dtx=True, frames=[[]] * 60)
        ordinary = []
        for index in range(60):
            suppressed = 10 <= index <= 51 and index not in (29, 49)
            ordinary.append(dict(bytes=[72] if suppressed else [72, index + 1, 2],
                                 dtx=suppressed, transmit=not suppressed))
        recovered = []
        for index in range(60):
            recovering = index in (2, 10, 52)
            packet_index = index + 1 if recovering else index
            recovered.append(dict(ordinary[packet_index], sourceIndex=index, packetIndex=packet_index,
                                  recovering=recovering, selectedLBRR=index in (2, 52)))
        summary = validate_fec_recovery(case, ordinary, recovered)
        self.assertEqual(summary['selectedLBRRRecoveries'], 2)
        self.assertEqual(summary['suppressedPLCRecoveries'], 1)
        self.assertEqual(summary['missingSourceFrames'], [2, 10, 52])
        wire = native_commands([case], [recovered]).splitlines()
        self.assertEqual(wire[0], b'1 60')
        self.assertEqual(wire[3], b'1 3 72 4 2')
        self.assertEqual(wire[4], b'0 3 72 4 2')
        self.assertEqual(wire[11], b'1 1 72')
        for index, key, value in [(2, 'selectedLBRR', False), (52, 'selectedLBRR', False),
                                  (10, 'selectedLBRR', True), (3, 'recovering', True),
                                  (2, 'sourceIndex', 3), (52, 'packetIndex', 52),
                                  (52, 'bytes', [72, 1, 2]), (10, 'dtx', False)]:
            changed = copy.deepcopy(recovered)
            changed[index][key] = value
            with self.assertRaises(ValueError):
                validate_fec_recovery(case, ordinary, changed)
        for changed in [recovered[:-1], recovered + recovered[:1]]:
            with self.assertRaises(ValueError):
                validate_fec_recovery(case, ordinary, changed)
        for key, value in [('fec', False), ('dtx', False), ('mode', 'celt'), ('frames', [[]] * 59)]:
            with self.assertRaises(ValueError):
                validate_fec_recovery(dict(case, **{key: value}), ordinary, recovered)
        for index, dtx, transmit in [(10, False, True), (11, False, True), (51, False, True),
                                     (2, True, False), (3, True, False), (52, True, False), (53, True, False)]:
            changed = copy.deepcopy(ordinary)
            changed[index].update(dtx=dtx, transmit=transmit)
            replay = copy.deepcopy(recovered)
            for packet in replay:
                if packet['packetIndex'] == index:
                    packet['dtx'] = dtx
            with self.assertRaises(ValueError):
                validate_fec_recovery(case, changed, replay)

    def test_recovered_native_lbrr_must_be_independently_confirmed(self):
        """Native packet inspection must agree with selected LBRR; omitted flags cannot imply recovery."""
        case = dict(channels=1, frames=[[]])
        packet = dict(pcm=[0.1] * 960, range=12, recovering=True, selectedLBRR=True)
        expected = dict(pcm=[0.1] * 960, range=12, lbrr=True)
        self.assertEqual(compare_native([case], [[packet]], [[expected]]), 0)
        for invalid in [dict(expected, lbrr=False), dict(expected, lbrr=1),
                        {key: value for key, value in expected.items() if key != 'lbrr'}]:
            with self.assertRaises(ValueError):
                compare_native([case], [[packet]], [[invalid]])
        packet['selectedLBRR'] = False
        expected['lbrr'] = False
        self.assertEqual(compare_native([case], [[packet]], [[expected]]), 0)

    def test_external_wav_bounds_and_tail(self):
        """External excerpts retain signed extrema/channel order and reject unsupported or truncated input."""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'input.wav'
            for channels, rate, count in [(1, 48000, 12), (2, 48000, 12), (1, 44100, 12), (1, 48000, 11)]:
                with wave.open(str(path), 'wb') as audio:
                    audio.setparams((channels, 2, rate, 0, 'NONE', 'not compressed'))
                    audio.writeframes(struct.pack('<hh', -32768, 32767) * (count * 960 * channels // 2))
                if rate != 48000 or count < 12:
                    with self.assertRaises(ValueError):
                        wav_signal(path)
                else:
                    actual_channels, frames = wav_signal(path)
                    self.assertEqual(actual_channels, channels)
                    self.assertEqual(len(frames), 15)
                    self.assertEqual(frames[0][:2], [-1, 32767 / 32768])
                    self.assertFalse(any(frames[-1]))
            path.write_bytes(path.read_bytes()[:-30])
            with self.assertRaises(ValueError):
                wav_signal(path)
