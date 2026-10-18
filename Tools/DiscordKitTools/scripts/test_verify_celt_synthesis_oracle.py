"""Hermetic complete synthesis evidence validation with no compiler/archive/device/network."""
import base64
import copy
import json
from pathlib import Path
import struct
import unittest
import verify_celt_synthesis_oracle as verifier


class CELTSynthesisVerifierTests(unittest.TestCase):
    """Require complete deterministic vectors and reject nonfinite or malformed evidence."""

    def setUp(self):
        """Read exact independent float32 fixtures without interpreting Swift or running any driver."""
        repository=Path(__file__).resolve().parents[3]
        self.records=json.loads((repository/verifier.FIXTURE_PATH).read_text().split('#"""',1)[1].split('"""#',1)[0])
        self.inputs=[r['input'] for r in self.records]
        self.expected=[]
        for record in self.records:
            frames=[]
            for encoded in record['output']:
                data=base64.b64decode(encoded,validate=True)
                self.assertEqual(len(data)%4,0)
                frames.append(list(struct.unpack('<'+'f'*(len(data)//4),data)))
            self.expected.append(dict(frames=frames))

    def test_fixed_sequences_modes_durations_filters_gain_and_exponent_bounds(self):
        """Fixture inputs reproduce every mode, active-band and extreme energy domain exactly."""
        self.assertEqual(self.inputs,verifier.fixed_cases())
        self.assertEqual(len(self.inputs),26)
        frames=[f for x in self.inputs for f in x['frames']]
        self.assertEqual({f['lm'] for f in frames},set(range(4)))
        self.assertEqual({x['channels'] for x in self.inputs},{1,2})
        self.assertTrue(any(f['silence'] for f in frames))
        self.assertTrue(any(f['period']==1022 for f in frames))
        self.assertTrue(any(f['gainIndex']==7 and f['tapset']==2 for f in frames))
        stats=verifier.compare_results(self.inputs,self.expected,copy.deepcopy(self.expected))
        self.assertEqual(stats['maximumAbsoluteError'],0)
        self.assertGreater(stats['comparedSamples'],20000)
        self.assertEqual(verifier.encode_fixture(zip(self.inputs,self.expected)),self.records)

    def test_random_inputs_reproduce_bounded_domains_and_commands(self):
        """Independent random spectra/energies and frame transitions remain reproducible and bounded."""
        cases=verifier.random_cases(20,6716)
        self.assertEqual(cases,verifier.random_cases(20,6716))
        self.assertNotEqual(cases,verifier.random_cases(20,6717))
        for x in cases:
            self.assertIn(x['channels'],(1,2));self.assertTrue(1<=len(x['frames'])<=8)
            fields=verifier.commands([x]).decode().split()
            self.assertEqual(list(map(int,fields[:2])),[x['channels'],len(x['frames'])])
            offset=2
            for f in x['frames']:
                self.assertTrue(0<=f['start']<f['end']<=21)
                self.assertEqual(len(f['coefficients']),(120<<f['lm'])*x['channels'])
                self.assertEqual(len(f['energies']),21*x['channels'])
                self.assertTrue(all(abs(v)<=4 for v in f['coefficients']))
                self.assertTrue(all(abs(v)<=32768 for v in f['energies']))
                self.assertEqual(list(map(int,fields[offset:offset+8])),[int(f[k]) for k in ('lm','start','end','transient','period','gainIndex','tapset','silence')])
                offset+=8+len(f['coefficients'])+len(f['energies'])
            self.assertEqual(offset,len(fields))

    def test_wrong_sequence_frame_and_sample_counts_rejected(self):
        """Dropped/duplicated records or incomplete PCM cannot become passing evidence."""
        for actual in ([],self.expected[:-1],self.expected+self.expected):
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)
        for mutation in ('frame','sample','extra'):
            actual=copy.deepcopy(self.expected)
            if mutation=='frame':actual[0]['frames'].pop()
            elif mutation=='sample':actual[0]['frames'][0].pop()
            else:actual[0]['extra']=0
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)

    def test_outside_tolerance_and_nonfinite_samples_rejected(self):
        """All samples enforce tolerance and finite numeric types even if both outputs are forged."""
        actual=copy.deepcopy(self.expected);actual[0]['frames'][0][0]+=0.001
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)
        for value in (float('nan'),float('inf'),float('-inf'),True,'0'):
            false=copy.deepcopy(self.expected);false[0]['frames'][0][0]=value
            with self.assertRaises((ValueError,TypeError)):verifier.compare_results(self.inputs,false,copy.deepcopy(false))

    def test_within_tolerance_updates_measured_maximum(self):
        """A bounded perturbation is accepted and the report records its actual absolute error."""
        actual=copy.deepcopy(self.expected);actual[0]['frames'][0][0]+=0.000001
        stats=verifier.compare_results(self.inputs,self.expected,actual)
        self.assertAlmostEqual(stats['maximumAbsoluteError'],0.000001)


if __name__=='__main__':unittest.main()
