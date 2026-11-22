// Copyright (C) 2000, 2001 Martin Pool <mbp@sourcefrog.net>
// Copyright (C) 2003 Donovan Baarda <abo@minkirri.apana.org.au>
// MoonBit scalar port: Copyright (C) 2026 MoonLibSync contributors
// SPDX-License-Identifier: LGPL-2.1-or-later
// Ported from librsync e364852674780e43d578e4239128ff7014190ed3
// src/rollsum.h and src/rollsum.c (RS_BLAKE2_SIG_MAGIC 0x72730137).

///|
let rollsum_char_offset : UInt32 = 31U

///|
priv struct Rollsum {
  mut count : Int32
  mut s1 : UInt32
  mut s2 : UInt32
}

///|
/// Direct one-shot librsync Rollsum weak checksum (Adler-32 variant with offset 31).
fn rollsum_digest(input : BytesView) -> UInt32 {
  let mut s1 = 0U
  let mut s2 = 0U
  for byte in input {
    s1 = (s1 + byte.to_uint() + rollsum_char_offset) & 0xffffU
    s2 = (s2 + s1) & 0xffffU
  }
  ((s2 & 0xffffU) << 16) | (s1 & 0xffffU)
}

///|
fn Rollsum::new() -> Rollsum {
  { count: 0, s1: 0U, s2: 0U, }
}

///|
fn Rollsum::check_capacity(
  self : Rollsum,
  incoming : Int32,
) -> Unit raise SyncError {
  guard self.count >= 0 && incoming >= 0 && incoming <= 2147483647 - self.count else {
    raise IntegerOutOfRange
  }
}

///|
fn Rollsum::update(self : Rollsum, input : BytesView) -> Unit raise SyncError {
  let len = input.length()
  self.check_capacity(len)
  let mut s1 = self.s1
  let mut s2 = self.s2
  for byte in input {
    s1 = (s1 + byte.to_uint() + rollsum_char_offset) & 0xffffU
    s2 = (s2 + s1) & 0xffffU
  }
  self.s1 = s1
  self.s2 = s2
  self.count = self.count + len
}

///|
fn Rollsum::update_array(
  self : Rollsum,
  input : Array[Byte],
  start : Int32,
  len : Int32,
) -> Unit raise SyncError {
  guard start >= 0 && len >= 0 && len <= input.length() - start else {
    raise InvalidOptions("window_len")
  }
  self.check_capacity(len)
  let mut s1 = self.s1
  let mut s2 = self.s2
  for i in 0..<len {
    s1 = (s1 + input[start + i].to_uint() + rollsum_char_offset) & 0xffffU
    s2 = (s2 + s1) & 0xffffU
  }
  self.s1 = s1
  self.s2 = s2
  self.count = self.count + len
}

///|
fn Rollsum::rotate(
  self : Rollsum,
  outgoing : Byte,
  incoming : Byte,
) -> Unit raise SyncError {
  guard self.count > 0 else { raise InvalidOptions("empty_rollsum_window") }
  let out_u = outgoing.to_uint()
  let in_u = incoming.to_uint()
  let cnt = self.count.reinterpret_as_uint()
  let s1 = (self.s1 + in_u - out_u) & 0xffffU
  let s2 = (self.s2 + s1 - cnt * (out_u + rollsum_char_offset)) & 0xffffU
  self.s1 = s1
  self.s2 = s2
}

///|
fn Rollsum::rollout(self : Rollsum, outgoing : Byte) -> Unit raise SyncError {
  guard self.count > 0 else { raise InvalidOptions("empty_rollsum_window") }
  let out_c = outgoing.to_uint() + rollsum_char_offset
  let cnt = self.count.reinterpret_as_uint()
  self.s1 = (self.s1 - out_c) & 0xffffU
  self.s2 = (self.s2 - cnt * out_c) & 0xffffU
  self.count = self.count - 1
}

///|
fn Rollsum::digest(self : Rollsum) -> UInt32 {
  ((self.s2 & 0xffffU) << 16) | (self.s1 & 0xffffU)
}

///|
/// Unified weak rolling checksum supporting both RK+BLAKE2 (0x72730147) and
/// Rollsum+BLAKE2 (0x72730137) profiles without duplicating delta scanner logic.
priv enum RollingWeak {
  Rk(RabinKarp)
  Rs(Rollsum)
}

///|
fn RollingWeak::new_for_magic(magic : UInt32) -> RollingWeak {
  if magic == 0x72730137U {
    Rs(Rollsum::new())
  } else {
    Rk(RabinKarp::new())
  }
}

///|
fn RollingWeak::count(self : RollingWeak) -> Int32 {
  match self {
    Rk(w) => w.count
    Rs(w) => w.count
  }
}

///|
fn RollingWeak::update(
  self : RollingWeak,
  input : BytesView,
) -> Unit raise SyncError {
  match self {
    Rk(w) => w.update(input)
    Rs(w) => w.update(input)
  }
}

///|
fn RollingWeak::update_array(
  self : RollingWeak,
  input : Array[Byte],
  start : Int32,
  len : Int32,
) -> Unit raise SyncError {
  match self {
    Rk(w) => w.update_array(input, start, len)
    Rs(w) => w.update_array(input, start, len)
  }
}

///|
fn RollingWeak::rotate(
  self : RollingWeak,
  outgoing : Byte,
  incoming : Byte,
) -> Unit raise SyncError {
  match self {
    Rk(w) => w.rotate(outgoing, incoming)
    Rs(w) => w.rotate(outgoing, incoming)
  }
}

///|
fn RollingWeak::rollout(
  self : RollingWeak,
  outgoing : Byte,
) -> Unit raise SyncError {
  match self {
    Rk(w) => w.rollout(outgoing)
    Rs(w) => w.rollout(outgoing)
  }
}

///|
fn RollingWeak::digest(self : RollingWeak) -> UInt32 {
  match self {
    Rk(w) => w.digest()
    Rs(w) => w.digest()
  }
}
