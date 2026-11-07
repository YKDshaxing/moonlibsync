// Copyright (C) 2019 Donovan Baarda <abo@minkirri.apana.org.au>
// MoonBit scalar port: Copyright (C) 2026 MoonLibSync contributors
// SPDX-License-Identifier: LGPL-2.1-or-later
// Ported from librsync e364852674780e43d578e4239128ff7014190ed3
// src/rabinkarp.h; scalar update only, no unrolling or power tables.

///|
#warnings("-unused_field")
priv struct RabinKarp {
  mut count : Int32
  mut hash : UInt32
  mut mult : UInt32
}

///|
/// Internal operations currently consumed by whitebox tests only.
#warnings("-unused_value")
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
#warnings("-unused_value")
fn RabinKarp::update(
  self : RabinKarp,
  input : BytesView,
) -> Unit raise SyncError {
  self.check_capacity(input.length())
  for byte in input {
    self.hash = self.hash * 0x08104225U + byte.to_uint()
    self.mult = self.mult * 0x08104225U
  }
  self.count = self.count + input.length()
}

///|
/// Caller must supply the actual outgoing first byte; no window is stored.
#warnings("-unused_value")
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
#warnings("-unused_value")
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
#warnings("-unused_value")
fn RabinKarp::digest(self : RabinKarp) -> UInt32 {
  self.hash
}
