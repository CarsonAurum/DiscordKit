# File: Tools/DiscordKitTools/scripts/test_verify_celt_header_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic side-information evidence tests; no network/compiler/device/reference archive."""
import copy
import json
from pathlib import Path
import unittest
import verify_celt_header_oracle as verifier


class CELTHeaderVerifierTests(unittest.TestCase):
    """Require exact independent evidence and reject falsified schemas/metadata/entropy."""

    def setUp(self):
        """Read committed literal reference JSON without interpreting Swift or spawning processes."""
        repository=Path(__file__).resolve().parents[3]
        self.records=json.loads((repository/verifier.FIXTURE_PATH).read_text().split('#"""',1)[1].split('"""#',1)[0])
        self.inputs=[r['input'] for r in self.records]
        self.expected=[r['output'] for r in self.records]

    def test_fixed_contexts_modes_prefixes_tiny_budgets_and_trim(self):
        """Fixtures reproduce all LM/channels/trim domains and silence/minimum frame boundaries."""
        self.assertEqual(self.inputs,verifier.fixed_cases())
        self.assertEqual(len(self.inputs),78)
        self.assertEqual({x['lm'] for x in self.inputs},set(range(4)))
        self.assertEqual({x['c'] for x in self.inputs},{1,2})
        self.assertEqual({x['trim'] for x in self.inputs},set(range(11)))
        self.assertTrue(set(range(9)).issubset({x['bytes'] for x in self.inputs}))
        self.assertTrue(any(x['period']==1022 and x['gainIndex']==7 and x['tapset']==2 for x in self.inputs))
        verifier.compare_results(self.inputs,self.expected,copy.deepcopy(self.expected))

    def test_reproducible_random_input_and_command_fields(self):
        """Independent frames and explicit syntax stay bounded and transport preserves every field."""
        cases=verifier.random_cases(100,6716)
        self.assertEqual(cases,verifier.random_cases(100,6716))
        self.assertNotEqual(cases,verifier.random_cases(100,6717))
        for x in cases:
            self.assertTrue(0<=x['start']<x['end']<=21)
            self.assertEqual(len(x['arbitrary']),x['bytes'])
            self.assertTrue(all(0<=v<=255 for v in x['arbitrary']))
            values=list(map(int,verifier.commands([x]).decode().split()))
            self.assertEqual(values[:7],[x[k] for k in ('lm','c','start','end','bytes','preceding','coarse')])
            self.assertEqual(values[15:36],list(map(int,x['tf'])))
            self.assertEqual(values[36:57],x['boosts'])
            self.assertEqual(values[57:],x['arbitrary'])

    def test_upstream_regions_reject_missing_ambiguous_and_changed_markers(self):
        """The verifier extracts verbatim bounded source and never silently rewrites drifted APIs."""
        self.assertEqual(verifier.region('beforeSTARTinsideENDafter','START','END'),'STARTinside')
        for source,start,end in [('abc','START','END'),('STARToneSTARTtwoEND','START','END'),('STARTwithoutend','START','END')]:
            with self.assertRaises(ValueError):verifier.region(source,start,end)

    def test_case_counts_and_every_exact_field(self):
        """Dropped results and mutations of fields, arrays or bytes cannot produce successful evidence."""
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,self.expected[:-1])
        for kind in ('encoded','decoded','arbitrary'):
            for part in ('prefix','suffix'):
                for field,value in self.expected[0][kind][part].items():
                    actual=copy.deepcopy(self.expected)
                    if isinstance(value,list):actual[0][kind][part][field][0]+=1
                    elif type(value)is bool:actual[0][kind][part][field]=not value
                    else:actual[0][kind][part][field]+=1
                    with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)
        actual=copy.deepcopy(self.expected);actual[0]['bytes'][0]^=1
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)

    def test_matching_false_entropy_prefix_and_suffix_bounds(self):
        """Matching forged outputs still fail independent probability-range and metadata constraints."""
        for part,key,value in [('prefix','bits',0),('prefix','frac',0),('prefix','range',0),
                               ('prefix','period',14),('prefix','gainIndex',8),('prefix','tapset',3),
                               ('suffix','tf',[4]*21),('suffix','offsets',[-1]*21),('suffix','spread',4),
                               ('suffix','trim',11),('suffix','allocation',100000),('suffix','anti',True)]:
            false=copy.deepcopy(self.expected)
            for kind in ('encoded','decoded'):false[0][kind][part][key]=copy.deepcopy(value)
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,false,copy.deepcopy(false))

    def test_matching_false_schema_silence_and_inactive_bands(self):
        """Silence must terminate, inactive bands stay zero, and shortened arrays/bytes fail."""
        for field in ('bytes',):
            false=copy.deepcopy(self.expected);false[0][field].pop()
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,false,copy.deepcopy(false))
        for field in ('tf','offsets'):
            false=copy.deepcopy(self.expected)
            for kind in ('encoded','decoded'):false[0][kind]['suffix'][field].pop()
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,false,copy.deepcopy(false))
        false=copy.deepcopy(self.expected)
        for kind in ('encoded','decoded'):false[0][kind]['prefix']['silence']=True
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,false,copy.deepcopy(false))
        index=next(i for i,x in enumerate(self.inputs) if x['start']>0)
        false=copy.deepcopy(self.expected)
        for kind in ('encoded','decoded'):false[index][kind]['suffix']['offsets'][0]=1
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,false,copy.deepcopy(false))


if __name__=='__main__':unittest.main()
