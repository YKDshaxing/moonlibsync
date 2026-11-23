// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn trim_http_ows(text : String) -> String {
  let chars = text.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  let out = StringBuilder()
  for i in start..<end {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
fn parse_http_nonneg_decimal(
  raw : String,
  context : String,
) -> Int64 raise CliError {
  let text = trim_http_ows(raw)
  guard text.length() > 0 else {
    raise FileFailure("invalid empty numeric value in " + context)
  }
  let mut n = 0L
  for c in text {
    guard c >= '0' && c <= '9' else {
      raise FileFailure("invalid numeric value in " + context + ": " + text)
    }
    let digit = (c.to_int() - 48).to_int64()
    guard n <= (9223372036854775807L - digit) / 10L else {
      raise FileFailure("numeric value overflow in " + context + ": " + text)
    }
    n = n * 10L + digit
  }
  n
}

///|
fn parse_strict_canonical_nonneg_decimal(
  text : String,
  context : String,
) -> Int64 raise CliError {
  guard text.length() > 0 else {
    raise FileFailure("invalid empty numeric value in " + context)
  }
  if text.length() > 1 && text[0] == '0' {
    raise FileFailure("non-canonical leading zero in " + context + ": " + text)
  }
  let mut n = 0L
  for c in text {
    guard c >= '0' && c <= '9' else {
      raise FileFailure("invalid numeric value in " + context + ": " + text)
    }
    let digit = (c.to_int() - 48).to_int64()
    guard n <= (9223372036854775807L - digit) / 10L else {
      raise FileFailure("numeric value overflow in " + context + ": " + text)
    }
    n = n * 10L + digit
  }
  n
}

///|
fn check_identity_content_encoding(
  resp : @http.ResponseHeader,
  context : String,
) -> Unit raise CliError {
  match resp.headers.get(@http.CaseInsensitiveString("Content-Encoding")) {
    Some(ce_raw) => {
      let ce = dir_ascii_lower(trim_http_ows(ce_raw))
      guard ce == "" || ce == "identity" else {
        raise FileFailure(
          context + " unsupported Content-Encoding: " + trim_http_ows(ce_raw),
        )
      }
    }
    None => ()
  }
}

///|
let fetch_sync_http_timeout_ms : Int32 = 60000

///|
fn validate_content_range(
  header_val : String,
  start : Int64,
  length : Int64,
  target_length : Int64,
) -> Unit raise CliError {
  let trimmed = trim_http_ows(header_val)
  let end = start + length - 1L
  let expected_prefix = "bytes \{start}-\{end}/"
  guard trimmed.has_prefix(expected_prefix) else {
    raise FileFailure(
      "fetch-sync Content-Range mismatch: expected prefix '" +
      expected_prefix +
      "' got '" +
      trimmed +
      "'",
    )
  }
  let chars = trimmed.to_array()
  let prefix_len = expected_prefix.to_array().length()
  let suffix_buf = StringBuilder()
  for i in prefix_len..<chars.length() {
    suffix_buf.write_char(chars[i])
  }
  let suffix = suffix_buf.to_string()
  if suffix != "*" {
    let total = parse_strict_canonical_nonneg_decimal(
      suffix, "Content-Range total",
    )
    guard total == target_length else {
      raise FileFailure(
        "fetch-sync Content-Range total mismatch: expected=\{target_length} got=\{total}",
      )
    }
  }
}

///|
async fn http_read_bounded(
  conn : @http.ClientConnection,
  resp : @http.ResponseHeader,
  max_bytes : Int64,
  context : String,
) -> Bytes {
  match resp.headers.get(@http.CaseInsensitiveString("Content-Length")) {
    Some(cl_str) => {
      let cl = parse_http_nonneg_decimal(cl_str, context + " Content-Length")
      guard cl <= max_bytes else {
        raise FileFailure(
          "ReadLimitExceeded: " +
          context +
          " content-length=\{cl} limit=\{max_bytes}",
        )
      }
    }
    None => ()
  }
  let buf = @buffer.Buffer(capacity=4096)
  let chunk = FixedArray::make(65536, b'\x00')
  let mut total = 0L
  while true {
    let n = conn.read_into(chunk.mut_view(start=0, end=65536))
    if n <= 0 {
      break
    }
    let n64 = n.to_int64()
    guard n64 <= max_bytes - total else {
      raise FileFailure(
        "ReadLimitExceeded: " + context + " body exceeds limit=\{max_bytes}",
      )
    }
    buf.write_bytesview(Bytes::from_array(chunk[0:n])[:])
    total = total + n64
  }
  buf.to_bytes()
}

///|
async fn http_get_bounded(
  client : @http.Client,
  url : String,
  extra_headers : Map[@http.CaseInsensitiveString, String],
  max_200_bytes : Int64,
  max_206_bytes : Int64,
  context : String,
) -> (@http.ResponseHeader, Bytes) {
  @async.with_timeout(fetch_sync_http_timeout_ms, async fn() {
    let (resp, conn) = client.get_stream(url, extra_headers~)
    defer conn.close()
    if resp.code == 200 {
      check_identity_content_encoding(resp, context)
      let body = http_read_bounded(conn, resp, max_200_bytes, context)
      (resp, body)
    } else if resp.code == 206 {
      check_identity_content_encoding(resp, context)
      let body = http_read_bounded(conn, resp, max_206_bytes, context)
      (resp, body)
    } else {
      (resp, b"")
    }
  })
}

///|
async fn http_head_target_length(
  client : @http.Client,
  url : String,
  explicit_len : Int64?,
  max_target_bytes : Int64,
) -> Int64 {
  @async.with_timeout(fetch_sync_http_timeout_ms, async fn() {
    let conn = client.request_stream(@http.RequestMethod::Head, url)
    defer conn.close()
    let resp = conn.end_request()
    if resp.code == 200 {
      match resp.headers.get(@http.CaseInsensitiveString("Content-Length")) {
        Some(cl_str) => {
          let cl = parse_http_nonneg_decimal(cl_str, "HEAD Content-Length")
          guard cl <= max_target_bytes else {
            raise FileFailure(
              "ReadLimitExceeded: target content-length=\{cl} limit=\{max_target_bytes}",
            )
          }
          match explicit_len {
            Some(exp) =>
              if cl != exp {
                raise FileFailure(
                  "fetch-sync target-length mismatch: expected=\{exp} server=\{cl}",
                )
              }
            None => ()
          }
          cl
        }
        None =>
          match explicit_len {
            Some(exp) => {
              guard exp <= max_target_bytes else {
                raise FileFailure(
                  "ReadLimitExceeded: target-length=\{exp} limit=\{max_target_bytes}",
                )
              }
              exp
            }
            None =>
              raise FileFailure(
                "fetch-sync HEAD response missing Content-Length header",
              )
          }
      }
    } else if (resp.code == 405 || resp.code == 501) &&
      explicit_len is Some(exp) {
      guard exp <= max_target_bytes else {
        raise FileFailure(
          "ReadLimitExceeded: target-length=\{exp} limit=\{max_target_bytes}",
        )
      }
      exp
    } else {
      raise FileFailure("fetch-sync HEAD failed with HTTP status \{resp.code}")
    }
  })
}

///|
async fn execute_range_plan(
  plan : Plan,
  output_path : String?,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let limits = plan.limits
  let target_label = match output_path {
    Some(p) => p
    None => plan.inputs[0]
  }
  try {
    limits.validate()
    let output_opt : String? = match output_path {
      Some(p) => Some(prepare_output(p))
      None => None
    }
    let target_len = match plan.target_length {
      Some(n) => n
      None => raise Usage("missing target length for range-plan")
    }
    let sig_bytes = bounded_read(plan.inputs[0], limits.max_signature_bytes)
    let basis_bytes = bounded_read(plan.inputs[2], limits.max_old_bytes)
    let range_plan = @lib.plan_range_fetch(
      sig_bytes,
      target_len,
      basis_bytes,
      { merge_gap_bytes: plan.merge_gap_bytes, max_ranges: plan.max_ranges, },
      limits,
    )
    let encoded = @lib.encode_range_plan_json(range_plan)
    match output_opt {
      Some(out_final) => {
        publish_output(out_final, encoded)
        if plan.json {
          writer(encoded)
        }
      }
      None => writer(encoded)
    }
    emit_instant_progress(
      plan,
      sig_bytes.length().to_int64() + basis_bytes.length().to_int64(),
    )
  } catch {
    error => raise wrap_stream_error(plan, target_label, error)
  }
}

///|
async fn execute_fetch_sync(
  plan : Plan,
  output_path : String,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    let output = prepare_output(output_path)
    let verifier = load_attached_verifier(plan)
    let url = plan.inputs[0]
    let basis_path = match plan.basis_path {
      Some(p) => p
      None => raise Usage("fetch-sync requires --basis OLD")
    }
    let basis_bytes = bounded_read(basis_path, limits.max_old_bytes)
    let client = @http.Client::Client(
      headers=Map([(@http.CaseInsensitiveString("Accept-Encoding"), "identity")]),
    )
    defer client.close()
    let mut http_requests = 0L

    // Step 1: Load target_sig from local --sig file or --sig-url.
    let target_sig = match (plan.sig_file, plan.sig_url) {
      (Some(sf), None) => bounded_read(sf, limits.max_signature_bytes)
      (None, Some(surl)) => {
        http_requests = http_requests + 1L
        let (resp, body) = http_get_bounded(
          client,
          surl,
          Map([]),
          limits.max_signature_bytes,
          0L,
          "fetch-sync --sig-url",
        )
        guard resp.code == 200 else {
          raise FileFailure(
            "fetch-sync --sig-url failed with HTTP status \{resp.code}",
          )
        }
        body
      }
      _ => raise Usage("fetch-sync requires exactly one of --sig or --sig-url")
    }

    // Step 2: Determine and validate target_length via HEAD (and optional --target-length).
    let max_target_bytes = if limits.max_new_bytes < limits.max_output_bytes {
      limits.max_new_bytes
    } else {
      limits.max_output_bytes
    }
    http_requests = http_requests + 1L
    let target_length = http_head_target_length(
      client,
      url,
      plan.target_length,
      max_target_bytes,
    )

    // Step 3: Plan range fetch.
    let range_plan = @lib.plan_range_fetch(
      target_sig,
      target_length,
      basis_bytes,
      { merge_gap_bytes: plan.merge_gap_bytes, max_ranges: plan.max_ranges, },
      limits,
    )

    // Step 4: Fetch only the required byte ranges (with safe 200 full-body fallback).
    let fetched_slices : Array[Bytes] = Array(
      capacity=range_plan.ranges.length(),
    )
    let mut full_body_cache : Bytes? = None
    for r in range_plan.ranges {
      match full_body_cache {
        Some(full) => {
          let start_i = r.start.to_int()
          let end_i = (r.start + r.length).to_int()
          fetched_slices.push(full[start_i:end_i].to_owned())
        }
        None => {
          let range_spec = r.http_range_spec()
          http_requests = http_requests + 1L
          let (resp, body) = http_get_bounded(
            client,
            url,
            Map([(@http.CaseInsensitiveString("Range"), range_spec)]),
            target_length,
            r.length,
            "fetch-sync range " + range_spec,
          )
          if resp.code == 206 {
            match
              resp.headers.get(@http.CaseInsensitiveString("Content-Range")) {
              Some(cr) =>
                validate_content_range(cr, r.start, r.length, target_length)
              None =>
                raise FileFailure(
                  "fetch-sync 206 response missing Content-Range header for " +
                  range_spec,
                )
            }
            match
              resp.headers.get(@http.CaseInsensitiveString("Content-Length")) {
              Some(cl_str) => {
                let cl = parse_http_nonneg_decimal(cl_str, "206 Content-Length")
                guard cl == r.length else {
                  raise FileFailure(
                    "fetch-sync range length mismatch for " +
                    range_spec +
                    ": expected=\{r.length} header=\{cl}",
                  )
                }
              }
              None => ()
            }
            guard body.length().to_int64() == r.length else {
              raise FileFailure(
                "fetch-sync range body length mismatch for " +
                range_spec +
                ": expected=\{r.length} got=\{body.length()}",
              )
            }
            fetched_slices.push(body)
          } else if resp.code == 200 {
            guard body.length().to_int64() == target_length else {
              raise FileFailure(
                "fetch-sync 200 body length mismatch: expected=\{target_length} got=\{body.length()}",
              )
            }
            guard r.start >= 0L &&
              r.length > 0L &&
              r.start <= target_length &&
              r.length <= target_length - r.start else {
              raise @lib.SyncError::CopyOutOfBounds
            }
            full_body_cache = Some(body)
            let start_i = r.start.to_int()
            let end_i = (r.start + r.length).to_int()
            fetched_slices.push(body[start_i:end_i].to_owned())
          } else {
            raise FileFailure(
              "fetch-sync range request " +
              range_spec +
              " failed with HTTP status \{resp.code}",
            )
          }
        }
      }
    }

    // Step 5: Reconstruct target file.
    let reconstructed = @lib.apply_range_fetch(
      basis_bytes, range_plan, fetched_slices, limits,
    )
    guard reconstructed.length().to_int64() == target_length else {
      raise FileFailure("fetch-sync reconstructed length mismatch")
    }

    // Step 6: Hash and cryptographically verify BEFORE publishing output.
    let hasher = @lib.Sha256Hasher::new(limits.max_output_bytes)
    hasher.update(reconstructed[:])
    let digest = hasher.finish()
    verify_digest_with_verifier(verifier, digest)

    // Step 7: Atomic no-overwrite publication + optional JSON summary.
    publish_output(output, reconstructed)
    if plan.json {
      let json_text = "{\"schema_version\":1,\"command\":\"fetch-sync\",\"target_length\":\{range_plan.target_length},\"reused_bytes\":\{range_plan.reused_bytes},\"fetch_bytes\":\{range_plan.fetch_bytes},\"request_bytes\":\{range_plan.request_bytes},\"range_count\":\{range_plan.ranges.length()},\"http_requests\":\{http_requests},\"sha256\":\"\{digest.sha256}\"}\n"
      write_inspection(json_text, writer~)
    }
    emit_instant_progress(plan, target_length)
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}

///|
async fn execute_compose_delta(
  plan : Plan,
  output_path : String,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    let output = prepare_output(output_path)
    let deltas : Array[Bytes] = Array(capacity=plan.inputs.length())
    let mut input_total_bytes = 0L
    for p in plan.inputs {
      let d = bounded_read(p, limits.max_delta_bytes)
      input_total_bytes = input_total_bytes + d.length().to_int64()
      deltas.push(d)
    }
    let composed = @lib.compose_delta_chain(deltas, limits)
    let summary = @lib.inspect_delta(composed, limits)
    let hasher = @lib.Sha256Hasher::new(limits.max_delta_bytes)
    hasher.update(composed[:])
    let composed_digest = hasher.finish()
    publish_output(output, composed)
    if plan.json {
      let json_text = "{\"schema_version\":1,\"command\":\"compose-delta\",\"input_count\":\{deltas.length()},\"input_total_bytes\":\{input_total_bytes},\"composed_bytes\":\{composed.length()},\"output_bytes\":\{summary.output_bytes},\"copy_bytes\":\{summary.copy_bytes},\"literal_bytes\":\{summary.literal_bytes},\"instruction_count\":\{summary.instruction_count},\"sha256\":\"\{composed_digest.sha256}\"}\n"
      write_inspection(json_text, writer~)
    }
    emit_instant_progress(plan, input_total_bytes)
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
