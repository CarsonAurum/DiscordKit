# File: Tools/DiscordKitTools/scripts/test_verify_celt_frame_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic whole-frame native evidence validation; no external compiler or codec runtime."""
import base64
import copy
import json
import math
from pathlib import Path
import struct
import unittest
from unittest.mock import patch
import verify_celt_frame_oracle as verifier


class CELTFrameVerifierTests(unittest.TestCase):
    """Falsify full PCM/range/packet evidence while retaining deterministic bounded contexts."""

    def setUp(self):
        """Read compact independent evidence and construct the comparison subject without native code."""
        path=Path(__file__).resolve().parents[3]/verifier.FIXTURE_PATH
        self.records=json.loads(path.read_text().split('#"""',1)[1].split('"""#',1)[0])
        self.inputs=[];self.native=[];self.reverse=[];self.owned=[]
        for record in self.records:
            x=copy.deepcopy(record['input'])
            for f in x['frames']:f['pcm']=self.unpack(f['pcm'])
            self.inputs.append(x)
            n=copy.deepcopy(record['output']);r=copy.deepcopy(record['encodedOutput'])
            for f in n+r:f['pcm']=self.unpack(f['pcm'])
            self.native.append(dict(frames=n));self.reverse.append(dict(frames=r))
            d=[dict(pcm=f['pcm'],range=f['range'],bits=1,transient=False,silence=False,postfilter=False) for f in n]
            e=[dict(raw=f['raw'],pcm=f['pcm'],range=f['range'],bits=1) for f in r]
            self.owned.append(dict(decoded=d,encoded=e))

    @staticmethod
    def unpack(encoded):
        """Decode complete little-endian float32 base64 while rejecting malformed compact evidence."""
        raw=base64.b64decode(encoded,validate=True)
        if len(raw)%4:raise ValueError('partial float word')
        return list(struct.unpack('<'+'f'*(len(raw)//4),raw))

    def test_full_official_evidence_and_generation(self):
        """All fixed PCM inputs reproduce and both independent directions pass full comparison."""
        self.assertEqual(self.inputs,verifier.fixed_cases())
        self.assertEqual(len(self.inputs),36)
        evidence=verifier.compare_results(self.inputs,self.native,self.owned,self.reverse)
        self.assertEqual(evidence['maximumAbsoluteError'],0)
        self.assertGreater(evidence['comparedSamples'],150000)
        self.assertEqual(verifier.fixture_records(self.inputs,self.native,self.reverse),self.records)
        self.assertEqual(len(verifier.commands(self.inputs).splitlines()),36)
        self.assertEqual(len(verifier.commands(self.inputs,self.owned).splitlines()),36)

    def test_random_contexts_repeat_and_are_bounded(self):
        """Real PCM cases remain normalized and preserve ordinary format/frame-rate bounds."""
        values=verifier.random_cases(100,6716)
        self.assertEqual(values,verifier.random_cases(100,6716))
        self.assertNotEqual(values,verifier.random_cases(100,6717))
        for x in values:
            self.assertIn(x['c'],(1,2));self.assertTrue(2<=len(x['frames'])<=6)
            for f in x['frames']:
                self.assertIn(f['n'],(120,240,480,960));self.assertIn(f['end'],(13,17,19,21))
                self.assertTrue(2<=f['bytes']<=1275);self.assertEqual(len(f['pcm']),f['n']*x['c'])
                self.assertTrue(all(math.isfinite(v) and -1<=v<=1 for v in f['pcm']))
        self.assertEqual(self.unpack(verifier.packed([0.0,1.0,-2.0])),[0.0,1.0,-2.0])
        for signal in ('tone','noise','impulse','transient','silence'):
            self.assertEqual(len(verifier.pcm_frame(120,2,0,signal)),240)

    def test_ranges_flags_bytes_and_modes_reject_mutation(self):
        """Both directions require exact arithmetic state and correctly packed bounded ordinary data."""
        for direction in ('decoded','encoded'):
            for key,value in [('range',0),('range',-1),('range',0x100000000),('range',123),('bits',0),('bits',999999)]:
                actual=copy.deepcopy(self.owned);actual[0][direction][0][key]=value
                with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
        for key,value in [('transient',1),('silence',None),('postfilter','true')]:
            actual=copy.deepcopy(self.owned);actual[0]['decoded'][0][key]=value
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
        actual=copy.deepcopy(self.owned);actual[0]['encoded'][0]['raw'][0]^=1
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
        for key,value in [('raw',[]),('raw',[999,0]),('toc',255),('range',0)]:
            native=copy.deepcopy(self.native);native[0]['frames'][0][key]=value
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,native,self.owned,self.reverse)

    def test_full_pcm_corruption_rejected(self):
        """No NaN, infinity, truncated vector or large decoded sample error can pass either direction."""
        for direction in ('decoded','encoded'):
            for value in (math.nan,math.inf,-math.inf,123):
                actual=copy.deepcopy(self.owned);actual[0][direction][0]['pcm'][0]=value
                with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
            actual=copy.deepcopy(self.owned);actual[0][direction][0]['pcm'].pop()
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
        actual=copy.deepcopy(self.owned);actual[0]['decoded'][0]['pcm']=actual[0]['decoded'][0]['pcm'].copy()
        actual[0]['decoded'][0]['pcm'][0]+=1e-7
        verifier.compare_results(self.inputs,self.native,actual,self.reverse)

    def test_missing_records_and_schema_rejected(self):
        """Dropped stream frames and undeclared output fields cannot silently narrow verification."""
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,self.owned[:-1],self.reverse)
        for direction in ('decoded','encoded'):
            actual=copy.deepcopy(self.owned);actual[0][direction].pop()
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
            actual=copy.deepcopy(self.owned);actual[0][direction][0]['extra']=0
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.native,actual,self.reverse)
        native=copy.deepcopy(self.native);native[0]['frames'][0]['extra']=0
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,native,self.owned,self.reverse)

    def test_mutually_false_evidence_still_fails_invariants(self):
        """Matching false references still violate physical range, storage and PCM shape invariants."""
        for mode in ('range','bytes','pcm'):
            n=copy.deepcopy(self.native);o=copy.deepcopy(self.owned)
            if mode=='range':n[0]['frames'][0]['range']=o[0]['decoded'][0]['range']=0
            elif mode=='bytes':n[0]['frames'][0]['raw']=[]
            else:n[0]['frames'][0]['pcm']=o[0]['decoded'][0]['pcm']=[0.0]
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,n,o,self.reverse)

    def test_official_build_failure_reports_bounded_diagnostics(self):
        """Explicit opt-in build failures preserve a useful bounded diagnostic instead of passing silently."""
        completed=type('Result',(),dict(returncode=1,stdout=b'x'*10000))()
        with patch.object(verifier.subprocess,'run',return_value=completed):
            with self.assertRaises(RuntimeError) as error:verifier.build(['make'],Path('/private/tmp'))
            self.assertLess(len(str(error.exception)),8100)
        with patch.object(verifier.subprocess,'run',return_value=type('Result',(),dict(returncode=0,stdout=b'ok'))()):
            verifier.build(['make'],Path('/private/tmp'))


if __name__=='__main__':unittest.main()
