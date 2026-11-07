// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Provisional error categories. Payloads for future parsers are not yet frozen.
pub(all) suberror SyncError {
  InvalidOptions(String)
  UnsupportedSignatureProfile
  TruncatedInput
  InvalidSignature
  InvalidDelta
  InvalidOpcode
  IntegerOutOfRange
  CopyOutOfBounds
  TrailingData
  LimitExceeded
}
