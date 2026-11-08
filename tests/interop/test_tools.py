"""Offline Python tool checks; separate from MoonBit's 80 library tests."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from interop_cases import make_cases, fingerprint, CONFIG
from interop_wire import inspect_delta, check_contents
from interop import compare_bytes, ComparisonMismatch, scratch_directory, archive_failure


class InteropTools(unittest.TestCase):
    def test_plan_counts_and_fixed_fingerprint(self):
        cases = make_cases()
        self.assertEqual(len(cases), 496)
        self.assertEqual(fingerprint(cases), (ROOT/'tests/interop/plan.sha256').read_text().strip())
        self.assertEqual(fingerprint(cases), fingerprint(make_cases()))
        self.assertEqual(sum(c['group']=='exhaustive' for c in cases), 338)
        self.assertEqual(len({(c['old'], c['new']) for c in cases if c['group']=='exhaustive'}), 169)
        self.assertEqual(sum(c['group']=='random' for c in cases), 48)

    def test_all_handwritten_vectors_and_widths(self):
        vectors = json.loads((ROOT/'tests/fixtures/opcodes/vectors.json').read_text())['vectors']
        for v in vectors:
            data = bytes.fromhex(v['hex'])
            if v['expect']=='C':
                self.assertEqual(inspect_delta(data), [('copy', 2, 3)])
            elif v['expect']=='L':
                self.assertEqual(inspect_delta(data), [('literal', bytes.fromhex('0080'))])
            elif v['expect']=='E':
                self.assertEqual(inspect_delta(data), [])
            else:
                with self.assertRaisesRegex(ValueError, v['expect']): inspect_delta(data)

    def test_every_parameter_truncation_and_literal_span(self):
        header = bytes.fromhex('72730236')
        for size in range(4):
            with self.assertRaisesRegex(ValueError, 'TruncatedInput'): inspect_delta(header[:size])
        for op in range(0x41, 0x55):
            width = (1 << (op-0x41)) if op <= 0x44 else (1 << ((op-0x45)//4)) + (1 << ((op-0x45)%4))
            for size in range(width):
                with self.assertRaisesRegex(ValueError, 'TruncatedInput'): inspect_delta(header + bytes([op]) + bytes(size))
        for data in [header, header+b'\x02\xff', header+b'\x44'+b'\xff'*8]:
            with self.assertRaisesRegex(ValueError, 'TruncatedInput'): inspect_delta(data)

    def test_reserved_zero_end_and_trailing(self):
        header = bytes.fromhex('72730236')
        for op in range(0x55, 256):
            with self.assertRaisesRegex(ValueError, 'InvalidOpcode'): inspect_delta(header+bytes([op]))
        for data in [b'\x41\x00', b'\x45\x00\x00']:
            with self.assertRaisesRegex(ValueError, 'InvalidDelta'): inspect_delta(header+data)
        for tail in [b'\x00', header+b'\x00', b'\xff']:
            with self.assertRaisesRegex(ValueError, 'TrailingData'): inspect_delta(header+b'\x00'+tail)
        self.assertEqual(inspect_delta(header+b'\x01\x00\x00'), [('literal', b'\x00')])

    def test_content_and_actual_comparison_failure(self):
        self.assertEqual(check_contents([('copy', 1, 2), ('literal', b'!')], b'abc', b'bc!'), 2)
        for commands in [[('copy', 3, 1)], [('copy', 2**64-1, 1)], [('literal', b'bad')]]:
            with self.assertRaises(ValueError): check_contents(commands, b'abc', b'abc')
        with tempfile.TemporaryDirectory() as t:
            a, b = Path(t)/'a', Path(t)/'b'
            a.write_bytes(b'abc'); b.write_bytes(b'abd')
            with self.assertRaises(ComparisonMismatch): compare_bytes(a,b)
            b.write_bytes(b'abc'); compare_bytes(a,b)

    def test_archive_precedes_temporary_cleanup(self):
        with tempfile.TemporaryDirectory() as t:
            output = Path(t)
            report = {}
            (output/'commands.log').write_text('observed failure')
            current = None
            with self.assertRaisesRegex(RuntimeError, 'controlled'):
                with scratch_directory(output, lambda e: archive_failure(output, current, {'case':'controlled'}, report, e)) as scratch:
                    current = scratch/'case'; current.mkdir()
                    (current/'old.bin').write_bytes(b'old')
                    (current/'new.bin').write_bytes(b'new')
                    (current/'case.json').write_text('{"seed":123}')
                    raise RuntimeError('controlled tool failure')
            saved = Path(report['failure_archive'])
            self.assertFalse(current.exists())
            self.assertEqual((saved/'old.bin').read_bytes(),b'old')
            self.assertEqual((saved/'new.bin').read_bytes(),b'new')
            self.assertTrue((saved/'failure.json').is_file())
            self.assertTrue((saved/'commands.log').is_file())


if __name__ == '__main__': unittest.main()
