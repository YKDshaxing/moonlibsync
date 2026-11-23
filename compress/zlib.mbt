// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn bounded_output_cap(allowed : Int64, out_len : Int32) -> Int32 {
  let out_len_i64 = out_len.to_int64()
  let cap_i64 = if allowed < out_len_i64 { allowed + 1L } else { out_len_i64 }
  if cap_i64 > out_len_i64 {
    out_len
  } else {
    cap_i64.to_int()
  }
}

///|
fn map_zlib_error(err : @zlib.ZlibError) -> @lib.SyncError {
  match err {
    @zlib.ZlibError(kind, _) =>
      match kind {
        Truncated => @lib.SyncError::TruncatedInput
        OutputLimitExceeded(..) => @lib.SyncError::LimitExceeded
        TrailingData => @lib.SyncError::TrailingData
        InvalidArgument => @lib.SyncError::InvalidOptions("zlib_argument")
        InvalidHeader
        | DictionaryRequired
        | DictionaryMismatch
        | InvalidDeflate
        | ChecksumMismatch
        | Cancelled => @lib.SyncError::InvalidDelta
      }
  }
}

///|
fn map_flate_error(err : @flate.InflateError) -> @lib.SyncError {
  match err {
    @flate.InflateError(kind, _) =>
      match kind {
        Truncated => @lib.SyncError::TruncatedInput
        OutputLimitExceeded(..) => @lib.SyncError::LimitExceeded
        TrailingData => @lib.SyncError::TrailingData
        InvalidArgument => @lib.SyncError::InvalidOptions("deflate_argument")
        Corrupt | Cancelled => @lib.SyncError::InvalidDelta
      }
  }
}

///|
/// Bounded Sans-IO streaming RFC 1950 zlib encoder usable on Native, JS, and Wasm-GC.
pub struct ZlibEncoder {
  priv inner : @zlib.Encoder
  priv max_input : Int64
  priv max_output : Int64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut finishing : Bool
  priv mut done : Bool
  priv mut failed : Bool
}

///|
/// Create a bounded streaming RFC 1950 zlib encoder with compression level `0..=9` (default `6`).
pub fn ZlibEncoder::new(
  max_input : Int64,
  max_output : Int64,
  level~ : Int32 = 6,
) -> ZlibEncoder raise @lib.SyncError {
  validate_gzip_bounds(max_input, max_output)
  guard level >= 0 && level <= 9 else {
    raise @lib.SyncError::InvalidOptions("level")
  }
  {
    inner: @zlib.Encoder(level~),
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
/// Advance zlib compression over `chunk` into `out`. Pass `finish=true` at EOF;
/// if `consumed < chunk.length()`, keep calling with `chunk[consumed:]` and
/// `finish=true` until all input is consumed, then keep calling with empty
/// input while `status` is `NeedMoreOutput`.
pub fn ZlibEncoder::step(
  self : ZlibEncoder,
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
  let cap = bounded_output_cap(allowed, out.length())
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
      let rem_cap = bounded_output_cap(rem_allowed, out.length() - produced)
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
/// Return final byte statistics after `ZlibEncoder::step` has reached `Done`.
pub fn ZlibEncoder::summary(
  self : ZlibEncoder,
) -> GzipSummary raise @lib.SyncError {
  guard !self.failed else {
    raise @lib.SyncError::InvalidOptions("stream_failed")
  }
  guard self.done else { raise @lib.SyncError::TruncatedInput }
  { input_bytes: self.input_bytes, output_bytes: self.output_bytes, }
}

///|
/// Bounded Sans-IO streaming RFC 1950 zlib decoder.
/// Enforces input and output budgets incrementally (zip-bomb safe) and rejects
/// trailing data after the Adler-32 trailer.
pub struct ZlibDecoder {
  priv inner : @zlib.Decoder
  priv max_input : Int64
  priv max_output : Int64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut done : Bool
  priv mut closed : Bool
  priv mut failed : Bool
}

///|
/// Create a bounded streaming RFC 1950 zlib decoder.
pub fn ZlibDecoder::new(
  max_input : Int64,
  max_output : Int64,
) -> ZlibDecoder raise @lib.SyncError {
  validate_gzip_bounds(max_input, max_output)
  {
    inner: @zlib.Decoder(),
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
/// Advance zlib decompression over `chunk` into `out`. Fails immediately with
/// `LimitExceeded` if output exceeds `max_output` or input exceeds `max_input`,
/// and with `TrailingData` if bytes appear after the Adler-32 trailer.
pub fn ZlibDecoder::step(
  self : ZlibDecoder,
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
  let cap = bounded_output_cap(allowed, out.length())
  let res = self.inner.step(chunk, out.mut_view(start=0, end=cap)) catch {
    err => raise map_zlib_error(err)
  }
  self.input_bytes = self.input_bytes + res.consumed.to_int64()
  guard res.produced.to_int64() <= allowed else {
    raise @lib.SyncError::LimitExceeded
  }
  self.output_bytes = self.output_bytes + res.produced.to_int64()
  let status = map_flate_status(res.status)
  if status is Done {
    if res.consumed < chunk.length() || self.inner.unused_input().length() > 0 {
      raise @lib.SyncError::TrailingData
    }
    self.done = true
  }
  { consumed: res.consumed, produced: res.produced, status, }
}

///|
/// Verify end-of-stream completeness and absence of trailing data, then close.
pub fn ZlibDecoder::finish(
  self : ZlibDecoder,
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
      err => raise map_zlib_error(err)
    }
    guard end_status is @flate.Status::Done && self.inner.is_finished() else {
      raise @lib.SyncError::TruncatedInput
    }
    if self.inner.unused_input().length() > 0 {
      raise @lib.SyncError::TrailingData
    }
    self.done = true
  }
  self.closed = true
  { input_bytes: self.input_bytes, output_bytes: self.output_bytes, }
}

///|
/// One-shot bounded RFC 1950 zlib compression.
pub fn compress_zlib(
  input : BytesView,
  max_input : Int64,
  max_output : Int64,
  level~ : Int32 = 6,
) -> Bytes raise @lib.SyncError {
  let enc = ZlibEncoder::new(max_input, max_output, level~)
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
/// One-shot bounded RFC 1950 zlib decompression.
/// Rejects zip bombs (`LimitExceeded`), trailing data (`TrailingData`),
/// truncated streams (`TruncatedInput`), and corrupt headers/Adler-32 (`InvalidDelta`).
pub fn decompress_zlib(
  input : BytesView,
  max_input : Int64,
  max_output : Int64,
) -> Bytes raise @lib.SyncError {
  let dec = ZlibDecoder::new(max_input, max_output)
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

///|
/// Bounded Sans-IO streaming RFC 1951 raw DEFLATE encoder usable on Native, JS, and Wasm-GC.
pub struct DeflateEncoder {
  priv inner : @flate.IncrementalEncoder
  priv max_input : Int64
  priv max_output : Int64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut finishing : Bool
  priv mut done : Bool
  priv mut failed : Bool
}

///|
/// Create a bounded streaming RFC 1951 raw DEFLATE encoder with compression level `0..=9` (default `6`).
pub fn DeflateEncoder::new(
  max_input : Int64,
  max_output : Int64,
  level~ : Int32 = 6,
) -> DeflateEncoder raise @lib.SyncError {
  validate_gzip_bounds(max_input, max_output)
  guard level >= 0 && level <= 9 else {
    raise @lib.SyncError::InvalidOptions("level")
  }
  {
    inner: @flate.IncrementalEncoder(level~),
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
/// Advance raw DEFLATE compression over `chunk` into `out`. Pass `finish=true` at EOF;
/// if `consumed < chunk.length()`, keep calling with `chunk[consumed:]` and
/// `finish=true` until all input is consumed, then keep calling with empty
/// input while `status` is `NeedMoreOutput`.
pub fn DeflateEncoder::step(
  self : DeflateEncoder,
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
  let cap = bounded_output_cap(allowed, out.length())
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
      let rem_cap = bounded_output_cap(rem_allowed, out.length() - produced)
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
/// Return final byte statistics after `DeflateEncoder::step` has reached `Done`.
pub fn DeflateEncoder::summary(
  self : DeflateEncoder,
) -> GzipSummary raise @lib.SyncError {
  guard !self.failed else {
    raise @lib.SyncError::InvalidOptions("stream_failed")
  }
  guard self.done else { raise @lib.SyncError::TruncatedInput }
  { input_bytes: self.input_bytes, output_bytes: self.output_bytes, }
}

///|
/// Bounded Sans-IO streaming RFC 1951 raw DEFLATE decoder.
/// Enforces input and output budgets incrementally (zip-bomb safe) and rejects
/// trailing data after the final DEFLATE block.
pub struct DeflateDecoder {
  priv inner : @flate.IncrementalDecoder
  priv max_input : Int64
  priv max_output : Int64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut done : Bool
  priv mut closed : Bool
  priv mut failed : Bool
}

///|
/// Create a bounded streaming RFC 1951 raw DEFLATE decoder.
pub fn DeflateDecoder::new(
  max_input : Int64,
  max_output : Int64,
) -> DeflateDecoder raise @lib.SyncError {
  validate_gzip_bounds(max_input, max_output)
  {
    inner: @flate.IncrementalDecoder(),
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
/// Advance raw DEFLATE decompression over `chunk` into `out`. Fails immediately with
/// `LimitExceeded` if output exceeds `max_output` or input exceeds `max_input`,
/// and with `TrailingData` if bytes appear after the final DEFLATE block.
pub fn DeflateDecoder::step(
  self : DeflateDecoder,
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
  let cap = bounded_output_cap(allowed, out.length())
  let res = self.inner.step(chunk, out.mut_view(start=0, end=cap)) catch {
    err => raise map_flate_error(err)
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
pub fn DeflateDecoder::finish(
  self : DeflateDecoder,
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
    guard self.inner.is_finished() else { raise @lib.SyncError::TruncatedInput }
    self.done = true
  }
  self.closed = true
  { input_bytes: self.input_bytes, output_bytes: self.output_bytes, }
}

///|
/// One-shot bounded RFC 1951 raw DEFLATE compression.
pub fn compress_deflate(
  input : BytesView,
  max_input : Int64,
  max_output : Int64,
  level~ : Int32 = 6,
) -> Bytes raise @lib.SyncError {
  let enc = DeflateEncoder::new(max_input, max_output, level~)
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
/// One-shot bounded RFC 1951 raw DEFLATE decompression.
/// Rejects zip bombs (`LimitExceeded`), trailing data (`TrailingData`),
/// truncated streams (`TruncatedInput`), and corrupt streams (`InvalidDelta`).
pub fn decompress_deflate(
  input : BytesView,
  max_input : Int64,
  max_output : Int64,
) -> Bytes raise @lib.SyncError {
  let dec = DeflateDecoder::new(max_input, max_output)
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
