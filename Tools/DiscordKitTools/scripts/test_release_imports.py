"""Regression coverage for fail-closed Swift import lexical admission."""

import unittest
from release_check import swift_imports


class SwiftImportTests(unittest.TestCase):
    """Exercise imports independently of manifest execution, networking and compiler availability."""

    def test_import_forms(self):
        """Include every conditional branch and scoped/backticked/Unicode module import."""
        source = '''
        @preconcurrency import Foundation
        #if os(ImaginaryOS)
        import `Forbidden`
        #else
        import struct `Scoped`.Thing
        #endif
        import /* nested /* comment */ comment */ Unicode🙂.Value
        import func Functions.call
        import `struct`
        let `import` = 1
        `import`(value)
        '''
        self.assertEqual(swift_imports(source), {"Foundation", "Forbidden", "Scoped", "Unicode🙂", "Functions", "struct"})

    def test_literal_contents_do_not_manufacture_imports(self):
        """Nested interpolation, ordinary/raw/multiline strings and regex stay complete tokens."""
        samples = [
            'let value = "import Forbidden"',
            r'let value = "\(String("import Forbidden"))"',
            r'let value = "\(f("\(g("import Forbidden"))"))"',
            'let value = """\nimport Forbidden\n"""',
            r'let value = #"\#(String("import Forbidden"))"#',
            'let value = #/ import Forbidden /#',
            'let value = /import Forbidden/',
            'let value = /[/]import Forbidden/',
            r'let value = #/\#(String("import Forbidden"))/#',
            '// import Forbidden\n/* import AlsoForbidden */',
        ]
        for sample in samples:
            with self.subTest(sample=sample):
                self.assertEqual(swift_imports(sample + '\nimport Allowed'), {"Allowed"})

    def test_division_is_not_a_regex_literal(self):
        """Ordinary slash operators cannot hide a later forbidden import or trigger false errors."""
        self.assertEqual(swift_imports('let result = first/second\nimport Forbidden'), {"Forbidden"})
        self.assertEqual(swift_imports('let result = first / second\nimport Forbidden'), {"Forbidden"})
        self.assertEqual(swift_imports('let result = first /= second\nimport Forbidden'), {"Forbidden"})

    def test_unterminated_literals_fail(self):
        """Malformed lexical structures must reject rather than erase the rest of the source."""
        for source in ['/* unterminated', '"unterminated', '#"unterminated', '#/unterminated',
                       'let value = /unterminated', r'"\(f("nested"))', 'import `Missing', 'import']:
            with self.subTest(source=source), self.assertRaises(ValueError):
                swift_imports(source)


if __name__ == '__main__':
    unittest.main()
