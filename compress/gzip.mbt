// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Status returned by streaming `GzipEncoder::step` and `GzipDecoder::step`.
pub(all) enum GzipStatus {
  NeedMoreInput
  NeedMoreOutput
  Done
}

///|
/// Progress reported by a single bounded compression/decompression step.
pub(all) struct GzipStep {
  consumed : Int32
  produced : Int32
  status : GzipStatus
}

///|
/// Final input/output byte counts of a completed gzip stream.
pub(all) struct GzipSummary {
  input_bytes : Int64
  output_bytes : Int64
}

///|
fn validate_gzip_bounds(
  max_input : Int64,
  max_output : Int64,
) -> Unit raise @lib.SyncError {
  guard max_input >= 0L && max_input <= 2147483647L else {
    raise @lib.SyncError::InvalidOptions("max_input")
  }
  guard max_output >= 0L && max_output <= 2147483647L else {
    raise @lib.SyncError::InvalidOptions("max_output")
  }
}

///|
fn map_gzip_error(err : @gzip.GzipError) -> @lib.SyncError {
  match err {
    @gzip.GzipError(kind, _) =>
      match kind {
        Truncated => @lib.SyncError::TruncatedInput
        OutputLimitExceeded(..) => @lib.SyncError::LimitExceeded
        InvalidArgument => @lib.SyncError::InvalidOptions("gzip_argument")
        InvalidHeader
        | InvalidDeflate
        | ChecksumMismatch
        | LengthMismatch
        | Cancelled => @lib.SyncError::InvalidDelta
      }
  }
}

///|
fn map_flate_status(status : @flate.Status) -> GzipStatus {
  match status {
    @flate.Status::NeedMoreInput => NeedMoreInput
    @flate.Status::NeedMoreOutput => NeedMoreOutput
    @flate.Status::Done => Done
  }
}

///|
/// Bounded Sans-IO streaming RFC 1952 gzip encoder usable on Native, JS, and Wasm-GC.
pub struct GzipEncoder {
  priv inner : @gzip.Encoder
  priv max_input : Int64
  priv max_output : Int64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut finishing : Bool
  priv mut done : Bool
  priv mut failed : Bool
}

///|
/// Create a bounded streaming gzip encoder with compression level `0..=9` (default `6`).
pub fn GzipEncoder::new(
  max_input : Int64,
  max_output : Int64,
  level~ : Int32 = 6,
) -> GzipEncoder raise @lib.SyncError {
  validate_gzip_bounds(max_input, max_output)
  guard level >= 0 && level <= 9 else {
    raise @lib.SyncError::InvalidOptions("level")
  }
  {
    inner: @gzip.Encoder(level~),
    max_input,
    max_output,
    input_bytes: 0L,
    output_bytes: 0L,
    finishing: false,
    done: false,
    failed: false,
  }
}

///|
/// Advance compression over `chunk` into `out`. Pass `finish=true` at EOF;
/// if `consumed < chunk.length()`, keep calling with `chunk[consumed:]` and
/// `finish=true` until all input is consumed, then keep calling with empty
/// input while `status` is `NeedMoreOutput`.
pub fn GzipEncoder::step(
  self : GzipEncoder,
  chunk : BytesView,
  out : FixedArray[Byte],
  finish~ : Bool = false,
) -> GzipStep raise @lib.SyncError {
  guard !self.failed else {
    raise @lib.SyncError::InvalidOptions("stream_failed")
  }
  guard !self.done else {
    raise @lib.SyncError::InvalidOptions("stream_finished")
  }
  guard out.length() > 0 else {
    raise @lib.SyncError::InvalidOptions("out_buf")
  }
  errdefer {
    self.failed = true
  }
  if self.finishing {
    guard finish && chunk.length() == 0 else {
      raise @lib.SyncError::InvalidOptions("finish_in_progress")
    }
  }
  guard chunk.length().to_int64() <= self.max_input - self.input_bytes else {
    raise @lib.SyncError::LimitExceeded
  }
  let allowed = self.max_output - self.output_bytes
  let cap_i64 = if allowed < out.length().to_int64() {
    allowed + 1L
  } else {
    out.length().to_int64()
  }
  let cap = if cap_i64 > out.length().to_int64() {
    out.length()
  } else {
    cap_i64.to_int()
  }
  if chunk.length() > 0 {
    let res = self.inner.step(
      chunk,
      out.mut_view(start=0, end=cap),
      action=@flate.DeflateAction::Continue,
    )
    self.input_bytes = self.input_bytes + res.consumed.to_int64()
    guard res.produced.to_int64() <= allowed else {
      raise @lib.SyncError::LimitExceeded
    }
    self.output_bytes = self.output_bytes + res.produced.to_int64()
    let mut produced = res.produced
    if finish && res.consumed == chunk.length() {
      self.finishing = true
      let rem_allowed = self.max_output - self.output_bytes
      let rem_cap_i64 = if rem_allowed < (out.length() - produced).to_int64() {
        rem_allowed + 1L
      } else {
        (out.length() - produced).to_int64()
      }
      let rem_cap = if rem_cap_i64 > (out.length() - produced).to_int64() {
        out.length() - produced
      } else {
        rem_cap_i64.to_int()
      }
      if rem_cap > 0 {
        let fin = self.inner.step(
          b""[:],
          out.mut_view(start=produced, end=produced + rem_cap),
          action=@flate.DeflateAction::Finish,
        )
        guard fin.produced.to_int64() <= rem_allowed else {
          raise @lib.SyncError::LimitExceeded
        }
        self.output_bytes = self.output_bytes + fin.produced.to_int64()
        produced = produced + fin.produced
        let fin_status = map_flate_status(fin.status)
        if fin_status is Done {
          self.done = true
        }
        return { consumed: res.consumed, produced, status: fin_status, }
      }
      return { consumed: res.consumed, produced, status: NeedMoreOutput, }
    }
    let status = if res.consumed < chunk.length() {
      GzipStatus::NeedMoreOutput
    } else {
      map_flate_status(res.status)
    }
    return { consumed: res.consumed, produced, status, }
  }
  if finish {
    self.finishing = true
  }
  let action = if finish {
    @flate.DeflateAction::Finish
  } else {
    @flate.DeflateAction::Continue
  }
  let res = self.inner.step(chunk, out.mut_view(start=0, end=cap), action~)
  self.input_bytes = self.input_bytes + res.consumed.to_int64()
  guard res.produced.to_int64() <= allowed else {
    raise @lib.SyncError::LimitExceeded
  }
  self.output_bytes = self.output_bytes + res.produced.to_int64()
  let status = map_flate_status(res.status)
  if status is Done {
    self.done = true
  }
  { consumed: res.consumed, produced: res.produced, status, }
}

///|
/// Return final byte statistics after `GzipEncoder::step` has reached `Done`.
pub fn GzipEncoder::summary(
  self : GzipEncoder,
) -> GzipSummary raise @lib.SyncError {
  guard !self.failed else {
    raise @lib.SyncError::InvalidOptions("stream_failed")
  }
  guard self.done else { raise @lib.SyncError::TruncatedInput }
  { input_bytes: self.input_bytes, output_bytes: self.output_bytes, }
}

///|
/// Bounded Sans-IO streaming single-member RFC 1952 gzip decoder.
/// Enforces input and output budgets incrementally (zip-bomb safe) and rejects
/// trailing data after the first complete gzip member.
pub struct GzipDecoder {
  priv inner : @gzip.Decoder
  priv max_input : Int64
  priv max_output : Int64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut done : Bool
  priv mut closed : Bool
  priv mut failed : Bool
}

///|
/// Create a bounded streaming single-member gzip decoder.
pub fn GzipDecoder::new(
  max_input : Int64,
  max_output : Int64,
) -> GzipDecoder raise @lib.SyncError {
  validate_gzip_bounds(max_input, max_output)
  {
    inner: @gzip.Decoder(),
    max_input,
    max_output,
    input_bytes: 0L,
    output_bytes: 0L,
    done: false,
    closed: false,
    failed: false,
  }
}

///|
/// Advance decompression over `chunk` into `out`. Fails immediately with
/// `LimitExceeded` if output exceeds `max_output` or input exceeds `max_input`,
/// and with `TrailingData` if bytes appear after the single gzip member trailer.
pub fn GzipDecoder::step(
  self : GzipDecoder,
  chunk : BytesView,
  out : FixedArray[Byte],
) -> GzipStep raise @lib.SyncError {
  guard !self.closed else {
    raise @lib.SyncError::InvalidOptions("stream_finished")
  }
  guard !self.failed else {
    raise @lib.SyncError::InvalidOptions("stream_failed")
  }
  guard out.length() > 0 else {
    raise @lib.SyncError::InvalidOptions("out_buf")
  }
  errdefer {
    self.failed = true
  }
  if self.done {
    if chunk.length() > 0 {
      raise @lib.SyncError::TrailingData
    }
    return { consumed: 0, produced: 0, status: Done, }
  }
  guard chunk.length().to_int64() <= self.max_input - self.input_bytes else {
    raise @lib.SyncError::LimitExceeded
  }
  let allowed = self.max_output - self.output_bytes
  let cap_i64 = if allowed < out.length().to_int64() {
    allowed + 1L
  } else {
    out.length().to_int64()
  }
  let cap = if cap_i64 > out.length().to_int64() {
    out.length()
  } else {
    cap_i64.to_int()
  }
  let res = self.inner.step(chunk, out.mut_view(start=0, end=cap)) catch {
    err => raise map_gzip_error(err)
  }
  self.input_bytes = self.input_bytes + res.consumed.to_int64()
  guard res.produced.to_int64() <= allowed else {
    raise @lib.SyncError::LimitExceeded
  }
  self.output_bytes = self.output_bytes + res.produced.to_int64()
  let status = map_flate_status(res.status)
  if status is Done {
    if res.consumed < chunk.length() {
      raise @lib.SyncError::TrailingData
    }
    self.done = true
  }
  { consumed: res.consumed, produced: res.produced, status, }
}

///|
/// Verify end-of-stream completeness and absence of trailing data, then close.
pub fn GzipDecoder::finish(
  self : GzipDecoder,
) -> GzipSummary raise @lib.SyncError {
  guard !self.closed else {
    raise @lib.SyncError::InvalidOptions("stream_finished")
  }
  guard !self.failed else {
    raise @lib.SyncError::InvalidOptions("stream_failed")
  }
  errdefer {
    self.failed = true
  }
  if !self.done {
    let end_status = self.inner.check_end() catch {
      err => raise map_gzip_error(err)
    }
    guard end_status is @flate.Status::Done && self.inner.is_finished() else {
      raise @lib.SyncError::TruncatedInput
    }
    self.done = true
  }
  self.closed = true
  { input_bytes: self.input_bytes, output_bytes: self.output_bytes, }
}

///|
/// One-shot bounded RFC 1952 gzip compression.
pub fn compress_gzip(
  input : BytesView,
  max_input : Int64,
  max_output : Int64,
  level~ : Int32 = 6,
) -> Bytes raise @lib.SyncError {
  let enc = GzipEncoder::new(max_input, max_output, level~)
  let out_buf = FixedArray::make(65536, b'\x00')
  let result = @buffer.Buffer(capacity=256)
  let mut pos = 0
  while pos < input.length() {
    let step = enc.step(input[pos:], out_buf, finish=false)
    pos = pos + step.consumed
    if step.produced > 0 {
      result.write_bytesview(Bytes::from_array(out_buf[0:step.produced])[:])
    }
    if step.status is Done {
      break
    }
  }
  while true {
    let step = enc.step(b""[:], out_buf, finish=true)
    if step.produced > 0 {
      result.write_bytesview(Bytes::from_array(out_buf[0:step.produced])[:])
    }
    if step.status is Done {
      break
    }
  }
  let _ = enc.summary()
  result.to_bytes()
}

///|
/// One-shot bounded single-member RFC 1952 gzip decompression.
/// Rejects zip bombs (`LimitExceeded`), trailing data (`TrailingData`),
/// truncated streams (`TruncatedInput`), and corrupt headers/CRCs (`InvalidDelta`).
pub fn decompress_gzip(
  input : BytesView,
  max_input : Int64,
  max_output : Int64,
) -> Bytes raise @lib.SyncError {
  let dec = GzipDecoder::new(max_input, max_output)
  let out_buf = FixedArray::make(65536, b'\x00')
  let result = @buffer.Buffer(capacity=256)
  let mut pos = 0
  while true {
    let step = dec.step(input[pos:], out_buf)
    pos = pos + step.consumed
    if step.produced > 0 {
      result.write_bytesview(Bytes::from_array(out_buf[0:step.produced])[:])
    }
    match step.status {
      NeedMoreOutput => continue
      NeedMoreInput => if pos >= input.length() { break }
      Done => break
    }
  }
  let _ = dec.finish()
  result.to_bytes()
}
