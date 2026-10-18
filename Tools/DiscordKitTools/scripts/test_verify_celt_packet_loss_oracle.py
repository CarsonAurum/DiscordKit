"""Hermetic actual compressed packet-loss evidence validation without native codecs."""
import base64
import copy
import json
from pathlib import Path
import struct
import unittest
import verify_celt_packet_loss_oracle as verifier


class CELTPacketLossVerifierTests(unittest.TestCase):
    """Check complete independent packet/PCM fixtures and strict loss-recovery evidence shape."""

    def setUp(self):
        """Decode reference float32 samples from committed opaque data without executing Swift."""
        repository=Path(__file__).resolve().parents[3]
        self.records=json.loads((repository/verifier.FIXTURE_PATH).read_text().split('#"""',1)[1].split('"""#',1)[0])
        self.inputs=verifier.fixed_cases()
        self.expected=[]
        self.actual=[]
        for record in self.records:
            expected=[];actual=[]
            for frame in record['frames']:
                data=base64.b64decode(frame['pcm'],validate=True)
                self.assertEqual(len(data)%4,0)
                pcm=list(struct.unpack('<'+'f'*(len(data)//4),data))
                expected.append(dict(packet=frame['packet'],range=frame['range'],pcm=pcm))
                actual.append(dict(range=frame['range'],pcm=pcm))
            self.expected.append(dict(frames=expected));self.actual.append(dict(frames=actual))

    def test_exact_packets_pcm_ranges_and_loss_decisions_are_complete(self):
        """Every fixture is a complete received/missing stream with exact zero loss ranges."""
        self.assertEqual(len(self.records),6)
        self.assertEqual(verifier.fixture_records(self.inputs,self.expected),self.records)
        for record,x in zip(self.records,self.inputs):
            self.assertEqual(record['channels'],x['channels'])
            self.assertEqual(len(record['frames']),len(x['frames']))
            for frame,source in zip(record['frames'],x['frames']):
                self.assertEqual((frame['n'],frame['end'],frame['lost']),(source['n'],source['end'],source['lost']))
                self.assertTrue(3<=len(frame['packet'])<=1276)
                self.assertTrue(all(type(v)is int and 0<=v<=255 for v in frame['packet']))
                if frame['lost']:self.assertEqual(frame['range'],0)
        statistics=verifier.compare_results(self.inputs,self.expected,self.actual)
        self.assertGreater(statistics['comparedSamples'],50000)
        self.assertGreater(statistics['concealedPackets'],100)
        self.assertEqual(statistics['maximumAbsoluteError'],0)

    def test_random_input_domains_and_command_serialization(self):
        """Seeded actual PCM generation has bounded dimensions and explicit withholding decisions."""
        cases=verifier.random_cases(20,6716)
        self.assertEqual(cases,verifier.random_cases(20,6716))
        self.assertNotEqual(cases,verifier.random_cases(20,6717))
        for x in cases:
            self.assertIn(x['channels'],(1,2))
            self.assertTrue(8<=len(x['frames'])<=40)
            fields=verifier.commands([x]).decode().split();offset=2
            self.assertEqual(list(map(int,fields[:2])),[x['channels'],len(x['frames'])])
            for index,frame in enumerate(x['frames']):
                self.assertIn(frame['n'],(120,240,480,960))
                self.assertIn(frame['end'],(13,17,19,21))
                if index<2:self.assertFalse(frame['lost'])
                self.assertEqual(len(frame['pcm']),frame['n']*x['channels'])
                self.assertTrue(all(-1<=value<=1 for value in frame['pcm']))
                self.assertEqual(list(map(int,fields[offset:offset+5])),[int(frame[k]) for k in ('n','end','bytes','intra','lost')])
                offset+=5+len(frame['pcm'])
            self.assertEqual(offset,len(fields))

    def test_incomplete_frames_changed_ranges_and_nonfinite_pcm_rejected(self):
        """Dropped PCM, wrong final ranges and invalid samples cannot yield passing interoperability."""
        for actual in ([],self.actual[:-1],self.actual+self.actual):
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)
        for kind in ('frame','sample','range','extra'):
            actual=copy.deepcopy(self.actual)
            if kind=='frame':actual[0]['frames'].pop()
            elif kind=='sample':actual[0]['frames'][0]['pcm'].pop()
            elif kind=='range':actual[0]['frames'][0]['range']+=1
            else:actual[0]['frames'][0]['extra']=1
            with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)
        for value in (float('nan'),float('inf'),float('-inf'),True,'0'):
            actual=copy.deepcopy(self.actual);actual[0]['frames'][0]['pcm'][0]=value
            with self.assertRaises((ValueError,TypeError)):verifier.compare_results(self.inputs,self.expected,actual)

    def test_explicit_tolerance_is_enforced_and_measured(self):
        """Small numerical differences are measured, while a gross waveform mismatch fails."""
        actual=copy.deepcopy(self.actual);actual[0]['frames'][0]['pcm'][0]+=0.00001
        statistics=verifier.compare_results(self.inputs,self.expected,actual)
        self.assertAlmostEqual(statistics['maximumAbsoluteError'],0.00001)
        self.assertGreater(statistics['maximumSequenceScaledAbsoluteError'],0)
        actual[0]['frames'][0]['pcm'][0]+=0.2
        with self.assertRaises(ValueError):verifier.compare_results(self.inputs,self.expected,actual)


if __name__=='__main__':unittest.main()
