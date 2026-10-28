# File: Tools/DiscordKitTools/scripts/test_verify_celt_plc_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic loss-concealment oracle evidence checks; no compiler/archive/network is required."""
import base64
import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest
import verify_celt_plc_oracle as verifier


class CELTConcealmentVerifierTests(unittest.TestCase):
    """Require complete PCM and exact loss-state evidence for independently generated vectors."""

    def setUp(self):
        """Load every reference float32 sample directly from the committed opaque vectors."""
        repository=Path(__file__).resolve().parents[3]
        self.records=json.loads((repository/verifier.FIXTURE_PATH).read_text().split('#"""',1)[1].split('"""#',1)[0])
        self.inputs=[record['input'] for record in self.records]
        self.expected=[]
        for record in self.records:
            frames=[]
            for frame in record['output']:
                data=base64.b64decode(frame['pcm'],validate=True)
                self.assertEqual(len(data)%4,0)
                frames.append({**frame,'pcm':list(struct.unpack('<'+'f'*(len(data)//4),data))})
            self.expected.append(dict(frames=frames))

    def test_fixed_sequences_cover_periodic_noise_recovery_and_exact_metadata(self):
        """The fixed vectors reproduce all durations/channels and cover both PLC branches."""
        self.assertEqual(self.inputs,verifier.fixed_cases())
        self.assertEqual(len(self.inputs),14)
        self.assertEqual({x['channels'] for x in self.inputs},{1,2})
        frames=[frame for x in self.inputs for frame in x['frames']]
        self.assertEqual({frame['lm'] for frame in frames},set(range(4)))
        self.assertTrue(any(frame['lost'] and frame['start']==17 for frame in frames))
        self.assertTrue(any(frame['period'] for frame in frames))
        statistics=verifier.compare_results(self.inputs,self.expected,copy.deepcopy(self.expected))
        self.assertGreater(statistics['periodicFrames'],100)
        self.assertGreater(statistics['noiseFrames'],10)
        self.assertGreater(statistics['comparedSamples'],100000)
        self.assertEqual(statistics['maximumAbsoluteError'],0)
        self.assertEqual(verifier.fixture_records(self.inputs,self.expected),self.records)

    def test_random_streams_and_independent_wire_inputs_are_reproducible(self):
        """Every random stream remains bounded and its serialized fields preserve explicit decisions."""
        inputs=verifier.random_cases(20,6716)
        self.assertEqual(inputs,verifier.random_cases(20,6716))
        self.assertNotEqual(inputs,verifier.random_cases(20,6717))
        for x in inputs:
            self.assertIn(x['channels'],(1,2))
            self.assertTrue(6<=len(x['frames'])<=30)
            fields=verifier.commands([x]).decode().split()
            self.assertEqual(list(map(int,fields[:2])),[x['channels'],len(x['frames'])])
            offset=2
            for frame in x['frames']:
                self.assertTrue(0<=frame['start']<frame['end']<=21)
                self.assertEqual(len(frame['coefficients']),(120<<frame['lm'])*x['channels'])
                self.assertEqual(len(frame['energies']),21*x['channels'])
                self.assertTrue(all(abs(v)<=4 for v in frame['coefficients']))
                self.assertEqual(list(map(int,fields[offset:offset+11])),[int(frame[k]) for k in ('lm','start','end','transient','period','gainIndex','tapset','silence','lost','force','seed')])
                offset+=11+len(frame['coefficients'])+len(frame['energies'])
            self.assertEqual(offset,len(fields))

    def test_missing_frames_samples_and_exact_loss_fields_fail(self):
        """No dropped output or changed seed/lag/path/envelope can count as passing evidence."""
        for candidate in ([],self.expected[:-1],self.expected+self.expected):
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,candidate)
        for key in ('pcm','energies','seed','duration','noise','pitch','frame'):
            candidate=copy.deepcopy(self.expected)
            if key=='frame':candidate[0]['frames'].pop()
            elif key in ('pcm','energies'):candidate[0]['frames'][3][key].pop()
            elif key=='noise':candidate[0]['frames'][3][key]=not candidate[0]['frames'][3][key]
            else:candidate[0]['frames'][3][key]+=1
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,candidate)

    def test_nonfinite_nonnumeric_or_outside_tolerance_pcm_fails(self):
        """Every sample must be finite and numeric even if both reference and owned data are forged."""
        for value in (float('nan'),float('inf'),float('-inf'),True,'0'):
            candidate=copy.deepcopy(self.expected)
            candidate[0]['frames'][3]['pcm'][0]=value
            with self.assertRaises((ValueError,TypeError)):verifier.compare_results(self.inputs,candidate,copy.deepcopy(candidate))
        candidate=copy.deepcopy(self.expected)
        candidate[0]['frames'][3]['pcm'][0]+=0.1
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,candidate)
        candidate=copy.deepcopy(self.expected)
        candidate[0]['frames'][3]['pcm'][0]+=0.00001
        statistics=verifier.compare_results(self.inputs,self.expected,candidate)
        self.assertAlmostEqual(statistics['maximumAbsoluteError'],0.00001)
        self.assertGreater(statistics['maximumSequenceScaledAbsoluteError'],0)

    def test_compiled_source_snapshots_remain_exact_and_report_drift(self):
        """Source changes cannot change compiled snapshots or silently acquire a passing current hash."""
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary);repository=directory/'repository'
            original=repository/'Sources/Example.swift';original.parent.mkdir(parents=True)
            original.write_bytes(b'let example = 1\n')
            snapshots,fingerprints=verifier.snapshot_sources(repository,directory/'snapshot',('Sources/Example.swift',))
            self.assertEqual(len(snapshots),1)
            self.assertEqual(snapshots[0].read_bytes(),original.read_bytes())
            self.assertEqual(verifier.source_drift(repository,fingerprints),{})
            original.write_bytes(b'let example = 2\n')
            self.assertEqual(snapshots[0].read_bytes(),b'let example = 1\n')
            self.assertEqual(verifier.source_drift(repository,fingerprints),{'Sources/Example.swift':verifier.digest(original)})
            original.unlink()
            with self.assertRaises(FileNotFoundError):verifier.source_drift(repository,fingerprints)
            with self.assertRaises(FileNotFoundError):verifier.snapshot_sources(repository,directory/'missing',('Sources/Missing.swift',))


if __name__=='__main__':unittest.main()
