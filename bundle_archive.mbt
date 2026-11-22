// SPDX-License-Identifier: LGPL-2.1-or-later

///|
let archive_magic_bytes : Bytes = b"MLSBDL01"

///|
/// Return the 8-byte deterministic container magic (`MLSBDL01`) for single-file
/// MoonLibSync directory bundle archives (`.mbundle`).
pub fn bundle_archive_magic() -> Bytes {
  archive_magic_bytes
}

///|
fn encode_u32_be(value : Int32) -> Bytes {
  let u = value.reinterpret_as_uint()
  Bytes::from_array([
    ((u >> 24) & 0xffU).to_byte(),
    ((u >> 16) & 0xffU).to_byte(),
    ((u >> 8) & 0xffU).to_byte(),
    (u & 0xffU).to_byte(),
  ])
}

///|
fn encode_u64_be(value : UInt64) -> Bytes {
  Bytes::from_array([
    ((value >> 56) & 0xffUL).to_byte(),
    ((value >> 48) & 0xffUL).to_byte(),
    ((value >> 40) & 0xffUL).to_byte(),
    ((value >> 32) & 0xffUL).to_byte(),
    ((value >> 24) & 0xffUL).to_byte(),
    ((value >> 16) & 0xffUL).to_byte(),
    ((value >> 8) & 0xffUL).to_byte(),
    (value & 0xffUL).to_byte(),
  ])
}

///|
fn decode_be_u32(buf : FixedArray[Byte]) -> UInt64 {
  (buf[0].to_uint64() << 24) |
  (buf[1].to_uint64() << 16) |
  (buf[2].to_uint64() << 8) |
  buf[3].to_uint64()
}

///|
fn decode_be_u64(buf : FixedArray[Byte]) -> UInt64 {
  (buf[0].to_uint64() << 56) |
  (buf[1].to_uint64() << 48) |
  (buf[2].to_uint64() << 40) |
  (buf[3].to_uint64() << 32) |
  (buf[4].to_uint64() << 24) |
  (buf[5].to_uint64() << 16) |
  (buf[6].to_uint64() << 8) |
  buf[7].to_uint64()
}

///|
fn bundle_expected_payload_specs(
  bundle : DirBundleManifest,
) -> Array[(String, FileDigest)] {
  let out : Array[(String, FileDigest)] = []
  for entry in bundle.entries {
    match entry.action {
      Unchanged(_) | Delete(_) | CopyFromBasis(_, _) => ()
      AddFull(path, target) => out.push((path, target))
      UpdateDelta(path, m) | UpdateDeltaFrom(_, path, m) =>
        out.push((path, m.delta))
      UpdateFull(path, _, target) => out.push((path, target))
    }
  }
  out
}

///|
/// Return the canonical ordered list of `(payload_path, expected_byte_length)`
/// entries carried by a `DirBundleManifest`.
pub fn bundle_expected_payloads(
  bundle : DirBundleManifest,
) -> Array[(String, Int64)] {
  let specs = bundle_expected_payload_specs(bundle)
  let out : Array[(String, Int64)] = Array(capacity=specs.length())
  for spec in specs {
    out.push((spec.0, spec.1.byte_length))
  }
  out
}

///|
/// Encode the deterministic `.mbundle` archive preamble:
/// `MLSBDL01 || u32_be(manifest_json_len) || manifest_json || u32_be(payload_count)`.
pub fn encode_bundle_archive_preamble(
  bundle : DirBundleManifest,
  dir_limits : DirLimits,
  limits : Limits,
) -> Bytes raise ManifestError {
  let manifest_json = encode_dir_bundle_manifest(bundle, dir_limits, limits)
  let expected = bundle_expected_payloads(bundle)
  let out = @buffer.Buffer(size_hint=16 + manifest_json.length())
  out.write_bytes(archive_magic_bytes)
  out.write_bytes(encode_u32_be(manifest_json.length()))
  out.write_bytes(manifest_json)
  out.write_bytes(encode_u32_be(expected.length()))
  out.to_bytes()
}

///|
/// Encode a single payload framing header:
/// `u32_be(path_utf8_len) || path_utf8 || u64_be(data_len)`.
pub fn encode_bundle_payload_header(
  payload_path : String,
  data_len : Int64,
  dir_limits : DirLimits,
) -> Bytes raise ManifestError {
  dir_limits.validate()
  validate_dir_path(payload_path, dir_limits)
  guard payload_path.has_prefix("payloads/") else {
    raise ManifestError::InvalidField("payload_path")
  }
  guard data_len >= 0L && data_len <= 2147483647L else {
    raise ManifestError::InvalidField("payload_length")
  }
  let path_bytes = @utf8.encode(payload_path)
  let out = @buffer.Buffer(size_hint=12 + path_bytes.length())
  out.write_bytes(encode_u32_be(path_bytes.length()))
  out.write_bytes(path_bytes)
  out.write_bytes(encode_u64_be(data_len.reinterpret_as_uint64()))
  out.to_bytes()
}

///|
/// One-shot pure zero-IO `.mbundle` archive encoder for in-memory payloads.
/// Verifies every payload's exact byte length and SHA-256 against `bundle`.
pub fn encode_bundle_archive(
  bundle : DirBundleManifest,
  payloads : Map[String, Bytes],
  dir_limits : DirLimits,
  limits : Limits,
) -> Bytes raise ManifestError {
  let preamble = encode_bundle_archive_preamble(bundle, dir_limits, limits)
  let expected = bundle_expected_payload_specs(bundle)
  guard payloads.length() == expected.length() else {
    raise ManifestError::BindingMismatch("archive_payload_count")
  }
  let out = @buffer.Buffer(size_hint=preamble.length() + 256)
  out.write_bytes(preamble)
  for pair in expected {
    let (path, digest) = pair
    let data = match payloads.get(path) {
      Some(b) => b
      None => raise ManifestError::BindingMismatch("archive_payload_missing")
    }
    guard data.length().to_int64() == digest.byte_length else {
      raise ManifestError::BindingMismatch("archive_payload_length")
    }
    let hasher = Sha256Hasher::new(digest.byte_length)
    hasher.update(data[:])
    let actual = hasher.finish()
    guard actual.sha256 == digest.sha256 else {
      raise ManifestError::BindingMismatch("payload_sha256")
    }
    out.write_bytes(
      encode_bundle_payload_header(path, digest.byte_length, dir_limits),
    )
    out.write_bytes(data)
  }
  out.to_bytes()
}

///|
/// Sans-IO output event yielded by `BundleArchiveDecoder::step`.
pub(all) enum BundleArchiveStep {
  NeedInput
  Manifest(DirBundleManifest)
  BeginPayload(String, Int64)
  PayloadChunk(BytesView)
  EndPayload(String)
}

///|
priv enum ArchiveDecodeState {
  NeedMagic(Int32)
  NeedJsonLen(Int32)
  NeedJson(Int32)
  NeedPayloadCount(Int32)
  NeedPathLen(Int32, Int32)
  NeedPath(Int32, Int32)
  NeedDataLen(Int32, Int32)
  InPayload(Int32, UInt64)
  Done
}

///|
/// Sans-IO incremental decoder for deterministic `MLSBDL01` `.mbundle` archives.
/// Feeds cleanly from 64 KiB file reads or `GzipDecoder` output buffers without
/// buffering full payload files in memory. Enforces exact manifest/payload order,
/// exact lengths, budgets, and zero trailing data.
pub struct BundleArchiveDecoder {
  priv dir_limits : DirLimits
  priv limits : Limits
  priv mut state : ArchiveDecodeState
  priv header_buf : FixedArray[Byte]
  priv scratch : @buffer.Buffer
  priv mut manifest : DirBundleManifest?
  priv mut expected_payloads : Array[(String, FileDigest)]
  priv mut payload_hasher : Sha256Hasher?
  priv mut closed : Bool
  priv mut failed : Bool
}

///|
pub fn BundleArchiveDecoder::new(
  dir_limits : DirLimits,
  limits : Limits,
) -> BundleArchiveDecoder raise ManifestError {
  dir_limits.validate()
  manifest_limits(limits)
  {
    dir_limits,
    limits,
    state: NeedMagic(0),
    header_buf: FixedArray::make(8, b'\x00'),
    scratch: @buffer.Buffer(size_hint=256),
    manifest: None,
    expected_payloads: [],
    payload_hasher: None,
    closed: false,
    failed: false,
  }
}

///|
fn BundleArchiveDecoder::verify_finished_payload(
  self : BundleArchiveDecoder,
  idx : Int32,
) -> Unit raise ManifestError {
  match self.payload_hasher {
    Some(hasher) => {
      self.payload_hasher = None
      let actual = hasher.finish()
      let expected = self.expected_payloads[idx].1
      guard actual.byte_length == expected.byte_length else {
        raise ManifestError::BindingMismatch("archive_payload_length")
      }
      guard actual.sha256 == expected.sha256 else {
        raise ManifestError::BindingMismatch("payload_sha256")
      }
    }
    None => raise ManifestError::InvalidSchema
  }
}

///|
/// Whether an immediate zero-input transition (`EndPayload`) is pending.
/// Callers should loop while `pos < chunk.length() || decoder.has_pending_event()`.
pub fn BundleArchiveDecoder::has_pending_event(
  self : BundleArchiveDecoder,
) -> Bool {
  self.state is InPayload(_, 0UL)
}

///|
/// Advance archive decoding over `chunk`, returning `(consumed, step)`.
pub fn BundleArchiveDecoder::step(
  self : BundleArchiveDecoder,
  chunk : BytesView,
) -> (Int32, BundleArchiveStep) raise ManifestError {
  guard !self.closed else {
    raise ManifestError::Core(InvalidOptions("stream_finished"))
  }
  guard !self.failed else {
    raise ManifestError::Core(InvalidOptions("stream_failed"))
  }
  errdefer {
    self.failed = true
  }
  match self.state {
    InPayload(idx, 0UL) => {
      self.verify_finished_payload(idx)
      let path = self.expected_payloads[idx].0
      let next_idx = idx + 1
      self.state = if next_idx == self.expected_payloads.length() {
        Done
      } else {
        NeedPathLen(next_idx, 0)
      }
      return (0, EndPayload(path))
    }
    _ => ()
  }
  let mut pos = 0
  while pos < chunk.length() {
    match self.state {
      NeedMagic(have) => {
        let need = 8 - have
        let avail = chunk.length() - pos
        let take = if avail < need { avail } else { need }
        for i in 0..<take {
          self.header_buf[have + i] = chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == 8 {
          for j in 0..<8 {
            guard self.header_buf[j] == archive_magic_bytes[j] else {
              raise ManifestError::InvalidSchema
            }
          }
          self.state = NeedJsonLen(0)
        } else {
          self.state = NeedMagic(next_have)
        }
      }
      NeedJsonLen(have) => {
        let need = 4 - have
        let avail = chunk.length() - pos
        let take = if avail < need { avail } else { need }
        for i in 0..<take {
          self.header_buf[have + i] = chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == 4 {
          let json_len = decode_be_u32(self.header_buf)
          let max_json = bundle_json_budget(self.dir_limits).reinterpret_as_uint64()
          guard json_len > 0UL && json_len <= max_json else {
            if json_len == 0UL {
              raise ManifestError::InvalidSchema
            } else {
              raise ManifestError::ResourceLimit("bundle_bytes")
            }
          }
          self.scratch.reset()
          self.state = NeedJson(json_len.to_int())
        } else {
          self.state = NeedJsonLen(next_have)
        }
      }
      NeedJson(rem) => {
        let avail = chunk.length() - pos
        let take = if avail < rem { avail } else { rem }
        self.scratch.write_bytesview(chunk[pos:pos + take])
        pos = pos + take
        let left = rem - take
        if left == 0 {
          let raw_json = self.scratch.to_bytes()
          self.scratch.reset()
          let parsed = parse_dir_bundle_manifest(
            raw_json,
            self.dir_limits,
            self.limits,
          )
          self.manifest = Some(parsed)
          self.expected_payloads = bundle_expected_payload_specs(parsed)
          self.state = NeedPayloadCount(0)
        } else {
          self.state = NeedJson(left)
        }
      }
      NeedPayloadCount(have) => {
        let need = 4 - have
        let avail = chunk.length() - pos
        let take = if avail < need { avail } else { need }
        for i in 0..<take {
          self.header_buf[have + i] = chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == 4 {
          let count = decode_be_u32(self.header_buf)
          guard count == self.expected_payloads.length().to_uint64() else {
            raise ManifestError::BindingMismatch("archive_payload_count")
          }
          self.state = if self.expected_payloads.length() == 0 {
            Done
          } else {
            NeedPathLen(0, 0)
          }
          match self.manifest {
            Some(m) => return (pos, Manifest(m))
            None => raise ManifestError::InvalidSchema
          }
        } else {
          self.state = NeedPayloadCount(next_have)
        }
      }
      NeedPathLen(idx, have) => {
        let need = 4 - have
        let avail = chunk.length() - pos
        let take = if avail < need { avail } else { need }
        for i in 0..<take {
          self.header_buf[have + i] = chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == 4 {
          let path_len = decode_be_u32(self.header_buf)
          let max_path = self.dir_limits.max_path_bytes.reinterpret_as_uint64()
          guard path_len > 0UL && path_len <= max_path else {
            if path_len == 0UL {
              raise ManifestError::InvalidField("payload_path")
            } else {
              raise ManifestError::ResourceLimit("path_bytes")
            }
          }
          self.scratch.reset()
          self.state = NeedPath(idx, path_len.to_int())
        } else {
          self.state = NeedPathLen(idx, next_have)
        }
      }
      NeedPath(idx, rem) => {
        let avail = chunk.length() - pos
        let take = if avail < rem { avail } else { rem }
        self.scratch.write_bytesview(chunk[pos:pos + take])
        pos = pos + take
        let left = rem - take
        if left == 0 {
          let path_bytes = self.scratch.to_bytes()
          self.scratch.reset()
          let path = @utf8.decode(path_bytes, ignore_bom=false) catch {
            _ => raise ManifestError::InvalidUtf8
          }
          guard path == self.expected_payloads[idx].0 else {
            raise ManifestError::BindingMismatch("archive_payload_path")
          }
          self.state = NeedDataLen(idx, 0)
        } else {
          self.state = NeedPath(idx, left)
        }
      }
      NeedDataLen(idx, have) => {
        let need = 8 - have
        let avail = chunk.length() - pos
        let take = if avail < need { avail } else { need }
        for i in 0..<take {
          self.header_buf[have + i] = chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == 8 {
          let data_len = decode_be_u64(self.header_buf)
          let expected_len = self.expected_payloads[idx].1.byte_length
          guard data_len == expected_len.reinterpret_as_uint64() else {
            raise ManifestError::BindingMismatch("archive_payload_length")
          }
          let hasher = Sha256Hasher::new(expected_len)
          self.payload_hasher = Some(hasher)
          self.state = InPayload(idx, data_len)
          return (
            pos,
            BeginPayload(self.expected_payloads[idx].0, expected_len),
          )
        } else {
          self.state = NeedDataLen(idx, next_have)
        }
      }
      InPayload(idx, rem) => {
        if rem == 0UL {
          self.verify_finished_payload(idx)
          let path = self.expected_payloads[idx].0
          let next_idx = idx + 1
          self.state = if next_idx == self.expected_payloads.length() {
            Done
          } else {
            NeedPathLen(next_idx, 0)
          }
          return (pos, EndPayload(path))
        }
        let avail = (chunk.length() - pos).to_uint64()
        let max_step = if rem < 65536UL { rem } else { 65536UL }
        let take_u64 = if avail < max_step { avail } else { max_step }
        let take = take_u64.to_int()
        let view = chunk[pos:pos + take]
        match self.payload_hasher {
          Some(hasher) => hasher.update(view)
          None => raise ManifestError::InvalidSchema
        }
        pos = pos + take
        self.state = InPayload(idx, rem - take_u64)
        return (pos, PayloadChunk(view))
      }
      Done => raise ManifestError::Core(TrailingData)
    }
  }
  (pos, NeedInput)
}

///|
/// Verify all expected payloads completed with zero trailing bytes and return the manifest.
pub fn BundleArchiveDecoder::finish(
  self : BundleArchiveDecoder,
) -> DirBundleManifest raise ManifestError {
  guard !self.closed else {
    raise ManifestError::Core(InvalidOptions("stream_finished"))
  }
  guard !self.failed else {
    raise ManifestError::Core(InvalidOptions("stream_failed"))
  }
  guard self.state is Done else {
    self.failed = true
    raise ManifestError::Core(TruncatedInput)
  }
  self.closed = true
  match self.manifest {
    Some(m) => m
    None => raise ManifestError::InvalidSchema
  }
}

///|
pub(all) struct DecodedBundleArchive {
  manifest : DirBundleManifest
  payloads : Map[String, Bytes]
}

///|
/// One-shot pure zero-IO parser for `.mbundle` archives built on `BundleArchiveDecoder`.
pub fn parse_bundle_archive(
  input : Bytes,
  dir_limits : DirLimits,
  limits : Limits,
) -> DecodedBundleArchive raise ManifestError {
  let dec = BundleArchiveDecoder::new(dir_limits, limits)
  let payloads : Map[String, Bytes] = Map([])
  let mut active_path = ""
  let cur_buf = @buffer.Buffer(size_hint=256)
  let mut pos = 0
  while pos < input.length() || dec.has_pending_event() {
    let (consumed, step) = dec.step(input[pos:])
    pos = pos + consumed
    match step {
      NeedInput => ()
      Manifest(_) => ()
      BeginPayload(path, _) => {
        active_path = path
        cur_buf.reset()
      }
      PayloadChunk(view) => cur_buf.write_bytesview(view)
      EndPayload(path) => {
        guard path == active_path else { raise ManifestError::InvalidSchema }
        payloads[path] = cur_buf.to_bytes()
        cur_buf.reset()
      }
    }
  }
  let manifest = dec.finish()
  { manifest, payloads, }
}
