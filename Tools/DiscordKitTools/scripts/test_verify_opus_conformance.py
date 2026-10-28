# File: Tools/DiscordKitTools/scripts/test_verify_opus_conformance.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic malformed official-vector framing and pinned-archive admission tests."""
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from subprocess import CompletedProcess
from verify_opus_conformance import parse_bitstream, extract_vectors, compare_references

class ConformanceAdmissionTests(unittest.TestCase):
    """Conformance evidence cannot silently omit malformed packets or admit arbitrary archives."""
    def test_big_endian_headers_and_packet_boundaries(self):
        """Keep exact unsigned ranges and full payload boundaries across successive frames."""
        data=struct.pack('>II',3,0xffffffff)+b'abc'+struct.pack('>II',1,0)+b'd'
        self.assertEqual(parse_bitstream(data),[(b'abc',0xffffffff),(b'd',0)])

    def test_rejects_missing_or_truncated_packet_data(self):
        """Reject empty input, short headers, invalid lengths and truncated payloads."""
        for data in (b'',b'abc',struct.pack('>II',0,1),struct.pack('>II',65537,1),struct.pack('>II',2,1)+b'a'):
            with self.subTest(data=data),self.assertRaises(ValueError):
                parse_bitstream(data)

    def test_archive_fingerprint_precedes_extraction(self):
        """Untrusted archive bytes fail before parsing or creating member outputs."""
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);archive=root/'bad.tar.gz';archive.write_bytes(b'not an archive')
            with self.assertRaisesRegex(ValueError,'fingerprint'):
                extract_vectors(archive,root/'out')
            self.assertFalse((root/'out').exists())

    def test_either_official_reference_can_pass_for_both_channel_layouts(self):
        """Follow upstream's either-reference rule and retain both independent comparisons."""
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);references=[root/'a.dec',root/'b.dec']
            for reference in references:
                reference.write_bytes(b'pcm')
            for channels in (1,2):
                for codes in ((0,1),(1,0),(1,1)):
                    with self.subTest(channels=channels,codes=codes):
                        responses=[CompletedProcess([],code,b'',b'comparison') for code in codes]
                        with patch('verify_opus_conformance.subprocess.run',side_effect=responses) as execute:
                            results,passed=compare_references(root/'compare',references,root/'out',channels)
                        self.assertEqual(passed,0 in codes)
                        self.assertEqual([item['exitCode'] for item in results],list(codes))
                        self.assertEqual('-s' in execute.call_args_list[0].args[0],channels==2)

if __name__ == '__main__':
    unittest.main()
