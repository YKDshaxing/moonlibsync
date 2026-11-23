name = "YKDshaxing/moonlibsync"

version = "0.7.1"

readme = "README.md"

repository = "https://github.com/YKDshaxing/moonlibsync"

license = "LGPL-2.1-or-later"

keywords = [
  "librsync",
  "rdiff",
  "delta",
  "sync",
  "zsync",
  "patch",
  "gzip",
  "ed25519",
  "x25519",
  "cli",
]

preferred_target = "wasm-gc"

description = "Pure MoonBit librsync/rdiff binary delta library, HTTP Range (zsync) pull, delta-chain composition, directory bundles, Ed25519 quorum signing, X25519/AEAD encryption, bounded Gzip/Zlib, and 35-command Native CLI."

import {
  "moonbitstack/mooncrypt@0.4.5",
  "moonbitstack/moonbase@0.4.2",
  "moonbitstack/moondate@0.1.0",
  "moonbitstack/moonrand@0.1.0",
}
