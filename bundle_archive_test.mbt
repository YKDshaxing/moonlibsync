// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "bundle archive roundtrip one-shot and 1-byte streaming including empty and zero-byte payloads" {
  let dl = @moonlibsync.DirLimits::default()
  let fl = @moonlibsync.Limits::default()
  let sha = (data : Bytes) => {
    let h = @moonlibsync.Sha256Hasher::new(fl.max_old_bytes)
    h.update(data[:])
    h.finish()
  }

  // Empty bundle archive (0 payloads)
  let empty_bundle = @moonlibsync.create_dir_bundle_manifest([], dl, fl)
  let empty_raw = @moonlibsync.encode_bundle_archive(
    empty_bundle,
    Map([]),
    dl,
    fl,
  )
  assert_true(empty_raw[0:8] == @moonlibsync.bundle_archive_magic()[:])
  let empty_dec = @moonlibsync.parse_bundle_archive(empty_raw, dl, fl)
  assert_eq(empty_dec.manifest.entries.length(), 0)
  assert_eq(empty_dec.payloads.length(), 0)

  // Mixed bundle: unchanged, 0-byte AddFull, non-empty UpdateDelta, UpdateFull, Delete
  let old_b = Bytes::makei(4096, i => ((i * 29 + 5) % 256).to_byte())
  let new_b = old_b[0:2048].to_owned() + b"ARCHIVE!" + old_b[2056:].to_owned()
  let sig_b = @moonlibsync.signature(
    old_b,
    { block_len: 512L, strong_sum_len: 32L, },
    fl,
  )
  let info_b = @moonlibsync.create_basis_info(old_b, sig_b, fl)
  let delta_b = @moonlibsync.delta(sig_b, new_b, fl)
  let um_b = @moonlibsync.create_update_manifest(
    info_b, sig_b, new_b, delta_b, fl,
  )
  let full_new = b"short-full-payload"

  let bundle = @moonlibsync.create_dir_bundle_manifest(
    [
      { path: "a/keep.bin", action: Unchanged(sha(b"keep")), },
      {
        path: "b/empty.bin",
        action: AddFull("payloads/000000.full", sha(b"")),
      },
      {
        path: "c/delta.bin",
        action: UpdateDelta("payloads/000001.delta", um_b),
      },
      {
        path: "d/full.bin",
        action: UpdateFull(
          "payloads/000002.full",
          sha(b"old-short"),
          sha(full_new),
        ),
      },
      { path: "e/drop.bin", action: Delete(sha(b"drop")), },
    ],
    dl,
    fl,
  )
  let map : Map[String, Bytes] = Map([
    ("payloads/000000.full", b""),
    ("payloads/000001.delta", delta_b),
    ("payloads/000002.full", full_new),
  ])
  let archive = @moonlibsync.encode_bundle_archive(bundle, map, dl, fl)

  // One-shot parse matches every payload
  let decoded = @moonlibsync.parse_bundle_archive(archive, dl, fl)
  assert_eq(decoded.manifest.entries.length(), 5)
  assert_eq(decoded.payloads.get("payloads/000000.full"), Some(b""))
  assert_eq(decoded.payloads.get("payloads/000001.delta"), Some(delta_b))
  assert_eq(decoded.payloads.get("payloads/000002.full"), Some(full_new))

  // 1-byte chunked Sans-IO BundleArchiveDecoder produces identical result
  let dec = @moonlibsync.BundleArchiveDecoder::new(dl, fl)
  let streamed : Map[String, Bytes] = Map([])
  let mut cur_path = ""
  let cur_buf = @buffer.Buffer()
  let mut saw_manifest = false
  for i in 0..<archive.length() {
    let slice = archive[i:i + 1]
    let mut pos = 0
    while pos < slice.length() || dec.has_pending_event() {
      let (consumed, step) = dec.step(slice[pos:])
      pos = pos + consumed
      match step {
        NeedInput => ()
        Manifest(m) => {
          saw_manifest = true
          assert_eq(m.update_delta_count, 1L)
        }
        BeginPayload(p, _) => {
          cur_path = p
          cur_buf.reset()
        }
        PayloadChunk(v) => cur_buf.write_bytesview(v)
        EndPayload(p) => {
          assert_eq(p, cur_path)
          streamed[p] = cur_buf.to_bytes()
          cur_buf.reset()
        }
      }
    }
  }
  let fin = dec.finish()
  assert_true(saw_manifest)
  assert_eq(fin.entries.length(), 5)
  assert_eq(streamed.get("payloads/000000.full"), Some(b""))
  assert_eq(streamed.get("payloads/000001.delta"), Some(delta_b))
  assert_eq(streamed.get("payloads/000002.full"), Some(full_new))
}

///|
test "bundle archive decoder rejects bad magic trailing bytes truncation and forged headers" {
  let dl = @moonlibsync.DirLimits::default()
  let fl = @moonlibsync.Limits::default()
  let sha = (data : Bytes) => {
    let h = @moonlibsync.Sha256Hasher::new(fl.max_old_bytes)
    h.update(data[:])
    h.finish()
  }
  let bundle = @moonlibsync.create_dir_bundle_manifest(
    [{ path: "x.bin", action: AddFull("payloads/000000.full", sha(b"hello")), }],
    dl,
    fl,
  )
  let archive = @moonlibsync.encode_bundle_archive(
    bundle,
    Map([("payloads/000000.full", b"hello")]),
    dl,
    fl,
  )

  // Bad magic -> InvalidSchema
  let bad_magic = b"BADMAGIC" + archive[8:].to_owned()
  let m_err = try {
    let _ = @moonlibsync.parse_bundle_archive(bad_magic, dl, fl)
    false
  } catch {
    @moonlibsync.ManifestError::InvalidSchema => true
    _ => false
  }
  assert_true(m_err)

  // Trailing byte -> Core(TrailingData)
  let trailing = archive + b"\x00"
  let t_err = try {
    let _ = @moonlibsync.parse_bundle_archive(trailing, dl, fl)
    false
  } catch {
    @moonlibsync.ManifestError::Core(@moonlibsync.SyncError::TrailingData) =>
      true
    _ => false
  }
  assert_true(t_err)

  // Truncated -> Core(TruncatedInput)
  let trunc = archive[0:archive.length() - 1].to_owned()
  let tr_err = try {
    let _ = @moonlibsync.parse_bundle_archive(trunc, dl, fl)
    false
  } catch {
    @moonlibsync.ManifestError::Core(@moonlibsync.SyncError::TruncatedInput) =>
      true
    _ => false
  }
  assert_true(tr_err)

  // Forged payload path inside archive -> BindingMismatch("archive_payload_path")
  let preamble = @moonlibsync.encode_bundle_archive_preamble(bundle, dl, fl)
  let wrong_hdr = @moonlibsync.encode_bundle_payload_header(
    "payloads/999999.full", 5L, dl,
  )
  let forged_path = preamble + wrong_hdr + b"hello"
  let p_err = try {
    let _ = @moonlibsync.parse_bundle_archive(forged_path, dl, fl)
    false
  } catch {
    @moonlibsync.ManifestError::BindingMismatch("archive_payload_path") => true
    _ => false
  }
  assert_true(p_err)

  // Forged payload length inside archive -> BindingMismatch("archive_payload_length")
  let wrong_len = @moonlibsync.encode_bundle_payload_header(
    "payloads/000000.full", 6L, dl,
  )
  let forged_len = preamble + wrong_len + b"hello!"
  let l_err = try {
    let _ = @moonlibsync.parse_bundle_archive(forged_len, dl, fl)
    false
  } catch {
    @moonlibsync.ManifestError::BindingMismatch("archive_payload_length") =>
      true
    _ => false
  }
  assert_true(l_err)
}
