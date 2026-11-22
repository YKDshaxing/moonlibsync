// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn crypto_error_tag_of(error : Error) -> String? {
  match error {
    @crypto.CryptoError::InvalidKey(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::InvalidKey(s)))
    @crypto.CryptoError::InvalidSignature(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::InvalidSignature(s)))
    @crypto.CryptoError::UntrustedKey(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::UntrustedKey(s)))
    @crypto.CryptoError::DigestMismatch(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::DigestMismatch(s)))
    @crypto.CryptoError::InvalidFormat(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::InvalidFormat(s)))
    @crypto.CryptoError::AuthenticationFailed =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::AuthenticationFailed))
    @crypto.CryptoError::TruncatedInput =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::TruncatedInput))
    @crypto.CryptoError::TrailingData =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::TrailingData))
    @crypto.CryptoError::LimitExceeded(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::LimitExceeded(s)))
    @crypto.CryptoError::InvalidOptions(s) =>
      Some(@crypto.crypto_error_tag(@crypto.CryptoError::InvalidOptions(s)))
    _ => None
  }
}

///|
fn trim_trailing_newline(text : String) -> String {
  let chars = text.to_array()
  let mut end = chars.length()
  if end > 0 && chars[end - 1] == '\n' {
    end = end - 1
    if end > 0 && chars[end - 1] == '\r' {
      end = end - 1
    }
  }
  let out = StringBuilder()
  for i in 0..<end {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
fn trim_trailing_newline_bytes(raw : Bytes) -> Bytes {
  let mut end = raw.length()
  if end > 0 && raw[end - 1] == b'\n' {
    end = end - 1
    if end > 0 && raw[end - 1] == b'\r' {
      end = end - 1
    }
  }
  raw[0:end].to_owned()
}

///|
async fn read_hex_key_file(path : String, field : String) -> Bytes {
  let raw = bounded_read(path, 4096L)
  guard !(raw.length() >= 3 &&
    raw[0] == b'\xef' &&
    raw[1] == b'\xbb' &&
    raw[2] == b'\xbf') else {
    raise @crypto.CryptoError::InvalidFormat(field)
  }
  let text = @utf8.decode(raw, ignore_bom=false) catch {
    _ => raise @crypto.CryptoError::InvalidFormat(field)
  }
  @crypto.decode_key_hex(trim_trailing_newline(text), 32, field)
}

///|
async fn read_public_key_file(path : String) -> Bytes {
  let key = read_hex_key_file(path, "public_key")
  @crypto.validate_public_key(key)
  key
}

///|
async fn read_passphrase_file(path : String) -> Bytes {
  let raw = bounded_read(path, 4096L)
  trim_trailing_newline_bytes(raw)
}

///|
async fn hash_file_for_crypto(
  path : String,
  max_bytes : Int64,
  progress~ : ProgressReporter? = None,
) -> @lib.FileDigest {
  let file = open_regular_input(path)
  defer file.close()
  let size = check_open_regular_sized(file, path, max_bytes)
  match progress {
    Some(p) => if p.total < 0L { p.total = size }
    None => ()
  }
  let hasher = @lib.Sha256Hasher::new(max_bytes)
  stream_open_chunks(file, path, size, progress~, chunk => hasher.update(chunk))
  hasher.finish()
}

///|
async fn load_attached_sig_and_keys(
  plan : Plan,
) -> (@crypto.PublisherSignature, Array[Bytes])? {
  match plan.verify_sig {
    None => None
    Some(sig_path) => {
      let sig_raw = bounded_read(sig_path, 8192L)
      let sig = @crypto.parse_publisher_signature(sig_raw)
      let pubkeys : Array[Bytes] = Array(capacity=plan.verify_keys.length())
      for kpath in plan.verify_keys {
        pubkeys.push(read_public_key_file(kpath))
      }
      Some((sig, pubkeys))
    }
  }
}

///|
async fn verify_attached_signature_bytes(plan : Plan, payload : Bytes) -> Unit {
  match load_attached_sig_and_keys(plan) {
    None => ()
    Some((sig, pubkeys)) => @crypto.verify_bytes(sig, pubkeys, payload)
  }
}

///|
async fn verify_attached_signature_file(
  plan : Plan,
  path : String,
  max_bytes : Int64,
) -> @lib.FileDigest? {
  match load_attached_sig_and_keys(plan) {
    None => None
    Some((sig, pubkeys)) => {
      let digest = hash_file_for_crypto(path, max_bytes)
      @crypto.verify_digest(sig, pubkeys, digest.byte_length, digest.sha256)
      Some(digest)
    }
  }
}

///|
async fn write_temp_file_synced(tmp_path : String, data : Bytes) -> Unit {
  let file = @fs.open(
    tmp_path,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o600,
  )
  let mut opened = true
  errdefer {
    if opened {
      file.close()
    }
    let _ = @fs.remove(tmp_path, allow_missing=true) catch { _ => () }
  }
  write_content(file, data)
  sync_content(file)
  file.close()
  opened = false
}

///|
async fn execute_keygen(plan : Plan, out_pub_path : String) -> Unit {
  let out_priv_path = plan.inputs[0]
  try {
    let priv_final = prepare_output(out_priv_path)
    let pub_final = prepare_output(out_pub_path)
    let same_path = if @path.sep != '/' {
      dir_ascii_lower(priv_final) == dir_ascii_lower(pub_final)
    } else {
      priv_final == pub_final
    }
    guard !same_path else {
      raise FileFailure(
        "keygen requires distinct output paths: " + out_priv_path,
      )
    }
    let seed = match @env.rand(32) {
      Some(bytes) if bytes.length() == 32 => bytes
      _ => raise FileFailure("CSPRNG randomness unavailable for keygen")
    }
    let kp = @crypto.keypair_from_seed(seed)
    let priv_data = @utf8.encode(@crypto.encode_key_hex(kp.seed) + "\n")
    let pub_data = @utf8.encode(@crypto.encode_key_hex(kp.public_key) + "\n")
    let priv_tmp = unique_temp_path(priv_final)
    let pub_tmp = unique_temp_path(pub_final)
    write_temp_file_synced(priv_tmp, priv_data)
    let mut priv_committed = false
    errdefer {
      if !priv_committed {
        let _ = @fs.remove(priv_tmp, allow_missing=true) catch { _ => () }
      } else {
        let _ = @fs.remove(priv_final, allow_missing=true) catch { _ => () }
      }
      let _ = @fs.remove(pub_tmp, allow_missing=true) catch { _ => () }
    }
    write_temp_file_synced(pub_tmp, pub_data)
    @fs.rename(priv_tmp, priv_final, replace=false)
    priv_committed = true
    @fs.rename(pub_tmp, pub_final, replace=false)
  } catch {
    error => raise wrap_stream_error(plan, out_pub_path, error)
  }
}

///|
async fn execute_sign(plan : Plan, output_path : String) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    let output = prepare_output(output_path)
    let seed = read_hex_key_file(plan.inputs[1], "private_key")
    let _ = @crypto.keypair_from_seed(seed)
    let progress = make_progress(plan, -1L)
    let digest = hash_file_for_crypto(
      plan.inputs[0],
      limits.max_new_bytes,
      progress~,
    )
    let sig = @crypto.sign_digest(seed, digest.byte_length, digest.sha256)
    let encoded = @crypto.encode_publisher_signature(sig)
    publish_output(output, encoded)
    finish_progress(progress)
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}

///|
fn format_verify_result(
  sig : @crypto.PublisherSignature,
  json : Bool,
) -> String {
  if json {
    "{\"schema_version\":1,\"command\":\"verify\",\"verified\":true,\"algorithm\":\"\{sig.algorithm}\",\"key_id\":\"\{sig.key_id}\",\"public_key\":\"\{sig.public_key_hex}\",\"payload_length\":\"\{sig.payload_length}\",\"payload_sha256\":\"\{sig.payload_sha256}\"}\n"
  } else {
    "verify\nverified: true\nalgorithm: \{sig.algorithm}\nkey_id: \{sig.key_id}\npublic_key: \{sig.public_key_hex}\npayload_length: \{sig.payload_length} bytes\npayload_sha256: \{sig.payload_sha256}\n"
  }
}

///|
async fn execute_verify(
  plan : Plan,
  json : Bool,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let limits = plan.limits
  let progress = make_progress(plan, -1L)
  let text = try {
    limits.validate()
    let sig_raw = bounded_read(plan.inputs[1], 8192L)
    let sig = @crypto.parse_publisher_signature(sig_raw)
    let pubkeys : Array[Bytes] = Array(capacity=1 + plan.verify_keys.length())
    pubkeys.push(read_public_key_file(plan.inputs[2]))
    for extra in plan.verify_keys {
      pubkeys.push(read_public_key_file(extra))
    }
    let digest = hash_file_for_crypto(
      plan.inputs[0],
      limits.max_new_bytes,
      progress~,
    )
    @crypto.verify_digest(sig, pubkeys, digest.byte_length, digest.sha256)
    format_verify_result(sig, json)
  } catch {
    error => {
      let detail = inspect_error_tag(error)
      raise FileFailure(
        "verify inputs '\{plan.inputs.join("', '")}': " + detail,
      )
    }
  }
  write_inspection(text, writer~) catch {
    error =>
      raise FileFailure(
        "stdout verify inputs '\{plan.inputs.join("', '")}': " +
        cli_error_text(error),
      )
  }
  finish_progress(progress)
}

///|
fn seal_limits_for_plan(plan : Plan) -> @crypto.SealLimits {
  let base_sl = @crypto.SealLimits::default()
  let limits = plan.limits
  if plan.operation == "seal" {
    let max_output_bytes = if plan.explicit_max_output {
      limits.max_output_bytes
    } else if limits.max_output_bytes > base_sl.max_output_bytes {
      limits.max_output_bytes
    } else {
      base_sl.max_output_bytes
    }
    { ..base_sl, max_input_bytes: limits.max_new_bytes, max_output_bytes, }
  } else {
    {
      ..base_sl,
      max_input_bytes: limits.max_delta_bytes,
      max_output_bytes: limits.max_output_bytes,
    }
  }
}

///|
async fn execute_seal_op(plan : Plan, output_path : String) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    let in_path = plan.inputs[0]
    let output = prepare_output(output_path)
    let seal_limits = seal_limits_for_plan(plan)
    if plan.operation == "seal" {
      let salt = match @env.rand(16) {
        Some(b) if b.length() == 16 => b
        _ => raise FileFailure("CSPRNG randomness unavailable for salt")
      }
      let nonce8 = match @env.rand(8) {
        Some(b) if b.length() == 8 => b
        _ => raise FileFailure("CSPRNG randomness unavailable for nonce")
      }
      let nonce_prefix = nonce8 + b"\x00\x00\x00\x00"
      let raw_key : Bytes? = match plan.key_file {
        Some(kf) => Some(read_hex_key_file(kf, "key"))
        None => None
      }
      let passphrase : Bytes? = match plan.passphrase_file {
        Some(pf) => Some(read_passphrase_file(pf))
        None => None
      }
      if plan.streaming {
        let in_file = open_regular_input(in_path)
        defer in_file.close()
        let in_size = check_open_regular_sized(
          in_file,
          in_path,
          seal_limits.max_input_bytes,
        )
        let enc = match (raw_key, passphrase) {
          (Some(k), _) =>
            @crypto.SealEncoder::new_with_key(
              k,
              salt,
              nonce_prefix,
              plan.seal_options,
              seal_limits,
            )
          (_, Some(pw)) =>
            @crypto.SealEncoder::new_with_passphrase(
              pw,
              salt,
              nonce_prefix,
              plan.seal_options,
              seal_limits,
            )
          _ => raise Usage("seal requires --key-file or --passphrase-file")
        }
        let progress = make_progress(plan, in_size)
        publish_stream(output, tmp_file => {
          write_nonempty(tmp_file, enc.take_ready()[:])
          stream_open_chunks(in_file, in_path, in_size, progress~, chunk => {
            enc.update(chunk)
            write_nonempty(tmp_file, enc.take_ready()[:])
          })
          write_nonempty(tmp_file, enc.finish()[:])
        })
        finish_progress(progress)
      } else {
        let plain = bounded_read(in_path, seal_limits.max_input_bytes)
        let sealed_bytes = match (raw_key, passphrase) {
          (Some(k), _) =>
            @crypto.seal_with_key(
              plain,
              k,
              salt,
              nonce_prefix,
              plan.seal_options,
              seal_limits,
            )
          (_, Some(pw)) =>
            @crypto.seal_with_passphrase(
              plain,
              pw,
              salt,
              nonce_prefix,
              plan.seal_options,
              seal_limits,
            )
          _ => raise Usage("seal requires --key-file or --passphrase-file")
        }
        publish_output(output, sealed_bytes)
        emit_instant_progress(plan, plain.length().to_int64())
      }
    } else {
      let raw_key : Bytes? = match plan.key_file {
        Some(kf) => Some(read_hex_key_file(kf, "key"))
        None => None
      }
      let passphrase : Bytes? = match plan.passphrase_file {
        Some(pf) => Some(read_passphrase_file(pf))
        None => None
      }
      if plan.streaming {
        let in_file = open_regular_input(in_path)
        defer in_file.close()
        let in_size = check_open_regular_sized(
          in_file,
          in_path,
          seal_limits.max_input_bytes,
        )
        let dec = match (raw_key, passphrase) {
          (Some(k), _) => @crypto.SealDecoder::new_with_key(k, seal_limits)
          (_, Some(pw)) =>
            @crypto.SealDecoder::new_with_passphrase(pw, seal_limits)
          _ => raise Usage("unseal requires --key-file or --passphrase-file")
        }
        let progress = make_progress(plan, in_size)
        publish_stream(output, tmp_file => {
          stream_open_chunks(in_file, in_path, in_size, progress~, chunk => {
            dec.feed(chunk)
            write_nonempty(tmp_file, dec.take_ready()[:])
          })
          let _ = dec.finish()
        })
        finish_progress(progress)
      } else {
        let cipher = bounded_read(in_path, seal_limits.max_input_bytes)
        let plain = match (raw_key, passphrase) {
          (Some(k), _) => @crypto.unseal_with_key(cipher, k, seal_limits)
          (_, Some(pw)) =>
            @crypto.unseal_with_passphrase(cipher, pw, seal_limits)
          _ => raise Usage("unseal requires --key-file or --passphrase-file")
        }
        publish_output(output, plain)
        emit_instant_progress(plan, cipher.length().to_int64())
      }
    }
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
