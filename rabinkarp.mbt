// Copyright (C) 2019 Donovan Baarda <abo@minkirri.apana.org.au>
// MoonBit scalar port: Copyright (C) 2026 MoonLibSync contributors
// SPDX-License-Identifier: LGPL-2.1-or-later
// Ported from librsync e364852674780e43d578e4239128ff7014190ed3
// src/rabinkarp.h; scalar update only, no unrolling or power tables.

///|
priv struct RabinKarp {
  mut count : Int32
  mut hash : UInt32
  mut mult : UInt32
}

///|
fn rk_pow_mult(exponent : Int32) -> UInt32 {
  let mut base = 0x08104225U
  let mut result = 1U
  let mut e = exponent
  while e > 0 {
    if (e & 1) != 0 {
      result = result * base
    }
    e = e >> 1
    if e > 0 {
      base = base * base
    }
  }
  result
}

///|
/// Direct one-shot weak checksum without multiplier tracking or state allocation.
fn rabinkarp_digest(input : BytesView) -> UInt32 {
  let mut hash = 1U
  for byte in input {
    hash = hash * 0x08104225U + byte.to_uint()
  }
  hash
}

///|
fn RabinKarp::new() -> RabinKarp {
  { count: 0, hash: 1U, mult: 1U, }
}

///|
/// Capacity is checked independently from modular checksum arithmetic.
fn RabinKarp::check_capacity(
  self : RabinKarp,
  incoming : Int32,
) -> Unit raise SyncError {
  guard self.count >= 0 && incoming >= 0 && incoming <= 2147483647 - self.count else {
    raise IntegerOutOfRange
  }
}

///|
#warnings("-unused_value")
fn RabinKarp::rollin(self : RabinKarp, incoming : Byte) -> Unit raise SyncError {
  self.check_capacity(1)
  self.hash = self.hash * 0x08104225U + incoming.to_uint()
  self.count = self.count + 1
  self.mult = self.mult * 0x08104225U
}

///|
/// Preflight the entire batch before modifying any state.
/// Advances mult once via O(log n) exponentiation instead of multiplying per byte.
fn RabinKarp::update(
  self : RabinKarp,
  input : BytesView,
) -> Unit raise SyncError {
  let len = input.length()
  self.check_capacity(len)
  let mut hash = self.hash
  for byte in input {
    hash = hash * 0x08104225U + byte.to_uint()
  }
  self.hash = hash
  if len > 0 {
    self.mult = self.mult * rk_pow_mult(len)
    self.count = self.count + len
  }
}

///|
/// Caller must supply the actual outgoing first byte; no window is stored.
fn RabinKarp::rotate(
  self : RabinKarp,
  outgoing : Byte,
  incoming : Byte,
) -> Unit raise SyncError {
  guard self.count > 0 else { raise InvalidOptions("empty_rabinkarp_window") }
  self.hash = self.hash * 0x08104225U +
    incoming.to_uint() -
    self.mult * (outgoing.to_uint() + 0x08104224U)
}

///|
/// EOF shortening uses the newly reduced multiplier.
fn RabinKarp::rollout(
  self : RabinKarp,
  outgoing : Byte,
) -> Unit raise SyncError {
  guard self.count > 0 else { raise InvalidOptions("empty_rabinkarp_window") }
  self.count = self.count - 1
  self.mult = self.mult * 0x98f009adU
  self.hash = self.hash - self.mult * (outgoing.to_uint() + 0x08104224U)
}

///|
fn RabinKarp::digest(self : RabinKarp) -> UInt32 {
  self.hash
}
