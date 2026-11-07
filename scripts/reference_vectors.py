"""Independent oracle: Python hashlib, never the MoonBit dependency under test."""

import hashlib
import sys

print(sys.version)
for data, expected in (
    (b"", "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),
    (b"abc", "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"),
):
    actual = hashlib.blake2b(data, digest_size=32).hexdigest()
    assert actual == expected
    print(f"input_hex={data.hex()} expected={expected} actual={actual}")

from strong_vectors import verify
verify()
