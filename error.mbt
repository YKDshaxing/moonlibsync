// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Core librsync format, option, range and resource-limit error categories.
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
