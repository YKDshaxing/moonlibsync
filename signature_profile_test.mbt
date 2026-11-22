// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "rollsum-blake2 0x72730137 one-shot streaming manifest and prepared roundtrip" {
  let d = @moonlibsync.Limits::default()
  let opts : @moonlibsync.SignatureOptions = {
    block_len: 64L,
    strong_sum_len: 16L,
  }
  let old = Bytes::makei(4096, i => ((i * 29 + i / 64) & 0xff).to_byte())
  let new_bytes = old[0:1024].to_owned() +
    b"INSERTED-ROLLSUM-MIDDLE" +
    old[1024:3000].to_owned() +
    b"TAIL-EDIT!"

  // 1. One-shot signature_with_profile emits 0x72730137 magic
  let sig_rs = @moonlibsync.signature_with_profile(
    old,
    opts,
    @moonlibsync.SignatureProfile::RollsumBlake2,
    d,
  )
  let summary = @moonlibsync.inspect_signature(sig_rs, d)
  assert_eq(summary.magic, 0x72730137U)
  assert_eq(summary.block_len, 64L)
  assert_eq(summary.strong_sum_len, 16L)
  assert_eq(summary.record_count, 64L)

  // 2. Streaming SignatureHasher::new_with_profile matches one-shot byte-for-byte
  let hasher = @moonlibsync.SignatureHasher::new_with_profile(
    opts,
    @moonlibsync.SignatureProfile::RollsumBlake2,
    d,
  )
  let streamed_sig = @buffer.Buffer()
  let mut pos = 0
  while pos < old.length() {
    let take = if old.length() - pos < 137 { old.length() - pos } else { 137 }
    hasher.update(old[pos:pos + take])
    streamed_sig.write_bytes(hasher.take_ready())
    pos = pos + take
  }
  streamed_sig.write_bytes(hasher.finish())
  assert_eq(streamed_sig.to_bytes(), sig_rs)

  // 3. One-shot delta, prepared delta, and streaming DeltaScanner all recover new_bytes with high COPY reuse
  let delta_oneshot = @moonlibsync.delta(sig_rs, new_bytes, d)
  let prepared = @moonlibsync.prepare_signature(sig_rs, d)
  assert_eq(prepared.summary().magic, 0x72730137U)
  let delta_prepared = prepared.delta(new_bytes, d)
  assert_eq(delta_oneshot, delta_prepared)

  let scanner = @moonlibsync.DeltaScanner::new(prepared, d)
  let streamed_delta = @buffer.Buffer()
  pos = 0
  while pos < new_bytes.length() {
    let take = if new_bytes.length() - pos < 211 {
      new_bytes.length() - pos
    } else {
      211
    }
    scanner.feed(new_bytes[pos:pos + take])
    streamed_delta.write_bytes(scanner.take_ready())
    pos = pos + take
  }
  streamed_delta.write_bytes(scanner.finish())
  let delta_stream = streamed_delta.to_bytes()
  assert_eq(delta_stream, delta_oneshot)

  let ds = @moonlibsync.inspect_delta(delta_oneshot, d)
  assert_true(ds.copy_bytes >= 2880L)
  assert_eq(@moonlibsync.patch(old, delta_oneshot, d), new_bytes)

  // 4. Schema 1 BasisInfo / UpdateManifest / verified_patch work seamlessly with 0x72730137
  let info = @moonlibsync.create_basis_info(old, sig_rs, d)
  let um = @moonlibsync.create_update_manifest(
    info, sig_rs, new_bytes, delta_oneshot, d,
  )
  assert_eq(@moonlibsync.verified_patch(old, delta_oneshot, um, d), new_bytes)

  // 5. Schema 2 plan_update / apply_update work seamlessly with 0x72730137
  let plan = prepared.plan_update(
    new_bytes,
    @moonlibsync.UpdateOptions::default(),
    d,
  )
  assert_eq(plan.decision.kind, "librsync-delta")
  let tm = @moonlibsync.create_transfer_manifest(
    info,
    sig_rs,
    new_bytes,
    delta_oneshot,
    @moonlibsync.UpdateOptions::default(),
    d,
  )
  assert_eq(
    @moonlibsync.apply_update(Some(old), delta_oneshot, tm, d),
    new_bytes,
  )
}

///|
test "create_reverse_delta and create_reverse_delta_auto revert new back to old" {
  let d = @moonlibsync.Limits::default()
  let v1 = Bytes::makei(8192, i => ((i * 17 + 3) & 0xff).to_byte())
  let v2 = v1[0:2048].to_owned() +
    b"UPGRADED-TO-V2-PAYLOAD" +
    v1[2100:].to_owned()

  let fwd_sig = @moonlibsync.signature(
    v1,
    { block_len: 128L, strong_sum_len: 16L, },
    d,
  )
  let fwd_delta = @moonlibsync.delta(fwd_sig, v2, d)
  let upgraded = @moonlibsync.patch(v1, fwd_delta, d)
  assert_eq(upgraded, v2)

  // Explicit options rollback
  let rev = @moonlibsync.create_reverse_delta(
    v1,
    v2,
    { block_len: 128L, strong_sum_len: 16L, },
    d,
  )
  let rev_summary = @moonlibsync.inspect_delta(rev, d)
  assert_true(rev_summary.copy_bytes >= 7680L)
  assert_eq(@moonlibsync.patch(v2, rev, d), v1)

  // Auto block-size rollback (including empty -> non-empty and non-empty -> empty)
  let rev_auto = @moonlibsync.create_reverse_delta_auto(v1, v2, d)
  assert_eq(@moonlibsync.patch(v2, rev_auto, d), v1)
  let rev_to_empty = @moonlibsync.create_reverse_delta_auto(b"", v2, d)
  assert_eq(@moonlibsync.patch(v2, rev_to_empty, d), b"")
  let rev_from_empty = @moonlibsync.create_reverse_delta_auto(v1, b"", d)
  assert_eq(@moonlibsync.patch(b"", rev_from_empty, d), v1)
}

///|
test "create_reverse_delta and auto respect asymmetric max_old_bytes and max_new_bytes" {
  let d = @moonlibsync.Limits::default()
  let small = Bytes::makei(100, i => (i & 0xff).to_byte())
  let big = Bytes::makei(500, i => ((i * 7) & 0xff).to_byte())

  // old = 100B, new = 500B with exact tight limits
  let lim1 : @moonlibsync.Limits = {
    ..d,
    max_old_bytes: 100L,
    max_new_bytes: 500L,
    max_output_bytes: 500L,
  }
  let r1 = @moonlibsync.create_reverse_delta(
    small,
    big,
    { block_len: 64L, strong_sum_len: 16L, },
    lim1,
  )
  assert_eq(@moonlibsync.patch(big, r1, { ..d, max_old_bytes: 500L, }), small)
  let r1a = @moonlibsync.create_reverse_delta_auto(small, big, lim1)
  assert_eq(@moonlibsync.patch(big, r1a, { ..d, max_old_bytes: 500L, }), small)

  // old = 500B, new = 100B with exact tight limits
  let lim2 : @moonlibsync.Limits = {
    ..d,
    max_old_bytes: 500L,
    max_new_bytes: 100L,
    max_output_bytes: 500L,
  }
  let r2 = @moonlibsync.create_reverse_delta(
    big,
    small,
    { block_len: 64L, strong_sum_len: 16L, },
    lim2,
  )
  assert_eq(@moonlibsync.patch(small, r2, { ..d, max_old_bytes: 100L, }), big)
  let r2a = @moonlibsync.create_reverse_delta_auto(big, small, lim2)
  assert_eq(@moonlibsync.patch(small, r2a, { ..d, max_old_bytes: 100L, }), big)
}
