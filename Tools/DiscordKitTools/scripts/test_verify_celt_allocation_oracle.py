"""Hermetic allocation evidence regressions: no compiler, archive, device or native runtime."""
import copy
import json
from pathlib import Path
import unittest
import verify_celt_allocation_oracle as verifier


class CELTAllocationVerifierTests(unittest.TestCase):
    """Check reproducible ordinary contexts and reject exact or mutually falsified evidence."""

    def setUp(self):
        """Read literal official fixtures without evaluating Swift declarations or spawning tools."""
        repository = Path(__file__).resolve().parents[3]
        text = (repository/verifier.FIXTURE_PATH).read_text()
        self.records = json.loads(text.split('#"""', 1)[1].split('"""#', 1)[0])
        self.inputs = [r['input'] for r in self.records]
        self.expected = [r['output'] for r in self.records]

    def test_fixed_contexts_cover_all_modes_trims_starts_and_reservations(self):
        """Literal inputs reproduce and independently generated outputs satisfy all bounds."""
        self.assertEqual(self.inputs, verifier.fixed_cases())
        self.assertEqual(len(self.inputs), 97)
        self.assertEqual({x['lm'] for x in self.inputs}, set(range(4)))
        self.assertEqual({x['c'] for x in self.inputs}, {1, 2})
        self.assertEqual({x['trim'] for x in self.inputs}, set(range(11)))
        self.assertEqual({x['start'] for x in self.inputs}, set(range(21)))
        self.assertTrue({-1, 0, 7, 8, 9, 15, 16, 17, 31, 32, 33, 81600}.issubset({x['total'] for x in self.inputs}))
        verifier.compare_results(self.inputs, self.expected, copy.deepcopy(self.expected))

    def test_seeded_contexts_are_repeatable_bounded_and_vary(self):
        """Generated modes/ranges/stereo decisions/boosts and unrelated bytes remain bounded."""
        cases = verifier.random_cases(500, 6716)
        self.assertEqual(cases, verifier.random_cases(500, 6716))
        self.assertNotEqual(cases, verifier.random_cases(500, 6717))
        for x in cases:
            self.assertIn(x['lm'], range(4))
            self.assertIn(x['c'], (1, 2))
            self.assertTrue(0 <= x['start'] < x['end'] <= 21)
            self.assertTrue(x['start'] <= x['intensity'] <= x['end'])
            self.assertTrue(x['start'] <= x['bandwidth'] < x['end'])
            self.assertTrue(0 <= x['total'] <= 81600)
            self.assertEqual(len(x['offsets']), 21)
            self.assertTrue(all(0 <= b <= 81600 for b in x['offsets']))
            self.assertEqual(len(x['arbitrary']), x['bytes'])
            self.assertTrue(all(0 <= b <= 255 for b in x['arbitrary']))
            self.assertEqual(len(verifier.commands([x]).splitlines()), 1)

    def test_reference_command_field_order_preserves_every_context(self):
        """Text transport carries exact C argument order, boosts and decoder bytes without shell evaluation."""
        x = self.inputs[0]
        values = list(map(int, verifier.commands([x]).decode().split()))
        self.assertEqual(values[:12], [x[k] for k in ('lm', 'c', 'start', 'end', 'trim', 'total', 'bytes', 'prefix', 'intensity')]
                         + [int(x['dual']), x['prev'], x['bandwidth']])
        self.assertEqual(values[12:33], x['offsets'])
        self.assertEqual(values[33:], x['arbitrary'])

    def test_wrong_case_counts_rejected(self):
        """Dropped/duplicated independent outputs cannot become successful evidence."""
        for actual in ([], self.expected[:-1], self.expected+self.expected):
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, self.expected, actual)

    def test_every_exact_field_rejects_mutation(self):
        """Caps, bytes and all three result/entropy snapshots enforce strict equality."""
        for key in ('caps', 'bytes'):
            actual = copy.deepcopy(self.expected)
            actual[0][key][0] += 1
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, self.expected, actual)
        for state in ('encoded', 'decoded', 'arbitrary'):
            for key in self.expected[0][state]:
                actual = copy.deepcopy(self.expected)
                old = actual[0][state][key]
                if isinstance(old, list):
                    actual[0][state][key][0] += 1
                elif type(old) is bool:
                    actual[0][state][key] = not old
                else:
                    actual[0][state][key] += 1
                with self.assertRaises(ValueError):
                    verifier.compare_results(self.inputs, self.expected, actual)

    def test_mutually_falsified_allocation_bounds_rejected(self):
        """Matching fake outputs still fail independent shapes, ranges, flags and conservation checks."""
        changes = [('shape', [-1]*21), ('shape', [100000]*21), ('fine', [9]*21),
                   ('priorities', [2]*21), ('balance', -1), ('balance', 81601),
                   ('coded', 0), ('coded', 22), ('intensity', 22), ('dual', True),
                   ('bits', 0), ('frac', 0), ('range', 0), ('range', 0x100000000)]
        for key, value in changes:
            false = copy.deepcopy(self.expected)
            false[0]['encoded'][key] = copy.deepcopy(value)
            false[0]['decoded'][key] = copy.deepcopy(value)
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, false, copy.deepcopy(false))

    def test_schema_lengths_types_and_decoder_disagreement_rejected(self):
        """Missing fields, short arrays/bytes, booleans masquerading as integers and different decode fail."""
        for key in ('caps', 'bytes'):
            false = copy.deepcopy(self.expected)
            false[0][key].pop()
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, false, copy.deepcopy(false))
        for key in ('shape', 'fine', 'priorities'):
            false = copy.deepcopy(self.expected)
            false[0]['arbitrary'][key].pop()
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, false, copy.deepcopy(false))
        for key, value in (('fine', [True]*21), ('dual', 0), ('range', True)):
            false = copy.deepcopy(self.expected)
            false[0]['arbitrary'][key] = value
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, false, copy.deepcopy(false))
        false = copy.deepcopy(self.expected)
        del false[0]['arbitrary']['range']
        with self.assertRaises(ValueError):
            verifier.compare_results(self.inputs, false, copy.deepcopy(false))
        false = copy.deepcopy(self.expected)
        false[0]['decoded']['range'] += 1
        with self.assertRaises(ValueError):
            verifier.compare_results(self.inputs, false, copy.deepcopy(false))


if __name__ == '__main__':
    unittest.main()
