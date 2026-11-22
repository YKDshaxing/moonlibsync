// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Cryptographic validation, authentication, format, trust and resource-limit errors.
#derive(Eq)
pub(all) suberror CryptoError {
  InvalidKey(String)
  InvalidSignature(String)
  UntrustedKey(String)
  DigestMismatch(String)
  InvalidFormat(String)
  AuthenticationFailed
  TruncatedInput
  TrailingData
  LimitExceeded(String)
  InvalidOptions(String)
}

///|
pub extend CryptoError with Eq::{equal, not_equal}

///|
/// Return a stable machine-readable diagnostic tag for a `CryptoError`.
pub fn crypto_error_tag(err : CryptoError) -> String {
  match err {
    InvalidKey(detail) => "InvalidKey:" + detail
    InvalidSignature(detail) => "InvalidSignature:" + detail
    UntrustedKey(detail) => "UntrustedKey:" + detail
    DigestMismatch(detail) => "DigestMismatch:" + detail
    InvalidFormat(detail) => "InvalidFormat:" + detail
    AuthenticationFailed => "AuthenticationFailed"
    TruncatedInput => "TruncatedInput"
    TrailingData => "TrailingData"
    LimitExceeded(detail) => "LimitExceeded:" + detail
    InvalidOptions(detail) => "InvalidOptions:" + detail
  }
}
