"""Hermetic recursive/all-band shape evidence checks; no archive or native compiler needed."""
import copy
import json
import math
from pathlib import Path
import unittest
import verify_celt_shape_oracle as band
import verify_celt_shape_frame_oracle as frame


class CELTShapeVerifierTests(unittest.TestCase):
    """Check deterministic source contexts and reject false scalar/control evidence."""

    def setUp(self):
        """Load independent committed records without evaluating Swift source or invoking a codec."""
        repository=Path(__file__).resolve().parents[3]
        self.groups=[]
        for verifier in (band,frame):
            text=(repository/verifier.FIXTURE_PATH).read_text()
            records=json.loads(text.split('#"""',1)[1].split('"""#',1)[0])
            self.groups.append((verifier,[r['input'] for r in records],[r['output'] for r in records]))

    def test_official_evidence_and_contexts(self):
        """Require independently captured fixture inputs and complete comparison admission."""
        for verifier,inputs,expected in self.groups:
            self.assertEqual(inputs,verifier.fixed_cases())
            verifier.compare_results(inputs,expected,copy.deepcopy(expected))
            self.assertEqual({x['lm'] for x in inputs},set(range(4)))
            self.assertEqual({x['c'] for x in inputs},{1,2})
            self.assertEqual({x['transient'] for x in inputs},{False,True})
            self.assertEqual(len(verifier.commands(inputs).splitlines()),len(inputs))
        self.assertEqual(len(self.groups[0][1]),50)
        self.assertEqual(len(self.groups[1][1]),70)
        self.assertEqual(len(band.systematic_cases()),1008)

    def test_generated_contexts_are_bounded_and_repeatable(self):
        """Seeded branches vary reproducibly while all shift, spectrum and allocation bounds hold."""
        for verifier in (band,frame):
            values=verifier.random_cases(200,6716)
            self.assertEqual(values,verifier.random_cases(200,6716))
            self.assertNotEqual(values,verifier.random_cases(200,6717))
            for x in values:
                self.assertIn(x['lm'],range(4));self.assertIn(x['c'],(1,2))
                self.assertIn(x['spread'],range(4));self.assertTrue(0<=x['seed']<=0xffffffff)
                if verifier is band:
                    self.assertTrue(0<=x['band']<=20)
                    n=(band.BAND_EDGES[x['band']+1]-band.BAND_EDGES[x['band']])<<x['lm']
                    self.assertEqual(len(x['x']),n*x['c'])
                    self.assertTrue(0<=x['b']<=min(16383,x['remaining']+1))
                    if x['low'] is not None:self.assertEqual(len(x['low']),n)
                    self.assertTrue(0<=x['fill']<1<<((1<<x['lm']) if x['transient'] else 1))
                else:
                    self.assertTrue(0<=x['start']<x['end']<=21)
                    self.assertEqual(len(x['x']),(120<<x['lm'])*x['c'])
                    self.assertEqual(len(x['tf']),21);self.assertEqual(len(x['pulses']),21)
                    self.assertTrue(all(0<=p<=16383 for p in x['pulses']))
                    self.assertTrue(x['start']<x['coded']<=x['end'])
                    self.assertTrue(0<=x['total']<=x['bytes']*64)
                self.assertTrue(all(math.isfinite(v) for v in x['x']))
                self.assertEqual(len(verifier.commands([x]).splitlines()),1)

    def test_wrong_record_counts_rejected(self):
        """No empty, dropped or duplicated output record can pass a complete comparison."""
        for verifier,inputs,expected in self.groups:
            for values in ([],expected[:-1],expected+expected):
                with self.assertRaises(ValueError):verifier.compare_results(inputs,expected,values)

    def test_wire_control_mutations_rejected(self):
        """Every exact range, bit, seed, occupancy and frame-byte field is independently enforced."""
        for verifier,inputs,expected in self.groups:
            for key,value in expected[0].items():
                if isinstance(value,list) and key not in ('bytes','masks','decodedMasks'):continue
                if key in ('coefficients','folding','decoded','decodedFolding','antiEncoder','antiDecoder'):continue
                actual=copy.deepcopy(expected)
                if isinstance(value,list):actual[0][key][0]^=1
                else:actual[0][key]+=1
                with self.assertRaises(ValueError):verifier.compare_results(inputs,expected,actual)

    def test_corrupt_spectra_schema_and_lengths_rejected(self):
        """NaN/Inf, excessive scalar error, truncation and missing fields fail closed."""
        for verifier,inputs,expected in self.groups:
            arrays=('coefficients','folding','decoded','decodedFolding') if verifier is band else ('coefficients','decoded','antiEncoder','antiDecoder')
            for key in arrays:
                for value in (math.nan,math.inf,-math.inf,1234):
                    actual=copy.deepcopy(expected);actual[0][key][0]=value
                    with self.assertRaises(ValueError):verifier.compare_results(inputs,expected,actual)
                actual=copy.deepcopy(expected);actual[0][key].pop()
                with self.assertRaises(ValueError):verifier.compare_results(inputs,expected,actual)
            actual=copy.deepcopy(expected);del actual[0]['range']
            with self.assertRaises(ValueError):verifier.compare_results(inputs,expected,actual)

    def test_documented_float_roundoff_accepted(self):
        """Small independently rounded scalar coefficients do not weaken exact syntax checks."""
        for verifier,inputs,expected in self.groups:
            actual=copy.deepcopy(expected);actual[0]['coefficients'][0]+=1e-6
            verifier.compare_results(inputs,expected,actual)

    def test_mutually_falsified_evidence_rejected(self):
        """A fake reference matching a fake subject still violates basic observable invariants."""
        for verifier,inputs,expected in self.groups:
            for key,value in [('range',0),('bytes',[]),('seed',-1),('decoded',[42]),('decodedRange',1)]:
                false=copy.deepcopy(expected);false[0][key]=value
                with self.assertRaises(ValueError):verifier.compare_results(inputs,false,copy.deepcopy(false))


if __name__=='__main__':unittest.main()
