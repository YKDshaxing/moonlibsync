// SPDX-License-Identifier: LGPL-2.1-or-later

///|
async fn stream_compress_drive(
  in_file : @fs.File,
  in_path : String,
  in_size : Int64,
  tmp_file : @fs.File,
  out_buf : FixedArray[Byte],
  progress : ProgressReporter?,
  step_fn : (BytesView, FixedArray[Byte], Bool) -> @compress.GzipStep raise @lib.SyncError,
  summary_fn : () -> @compress.GzipSummary raise @lib.SyncError,
) -> Unit {
  stream_open_chunks(in_file, in_path, in_size, progress~, chunk => {
    let mut pos = 0
    while true {
      let step = step_fn(chunk[pos:], out_buf, false)
      pos = pos + step.consumed
      if step.produced > 0 {
        write_nonempty(tmp_file, Bytes::from_array(out_buf[0:step.produced])[:])
      }
      match step.status {
        NeedMoreOutput => continue
        NeedMoreInput => if pos >= chunk.length() { break }
        Done => break
      }
    }
  })
  while true {
    let step = step_fn(b""[:], out_buf, true)
    if step.produced > 0 {
      write_nonempty(tmp_file, Bytes::from_array(out_buf[0:step.produced])[:])
    }
    if step.status is Done {
      break
    }
  }
  let _ = summary_fn()
}

///|
async fn stream_decompress_drive(
  in_file : @fs.File,
  in_path : String,
  in_size : Int64,
  tmp_file : @fs.File,
  out_buf : FixedArray[Byte],
  progress : ProgressReporter?,
  step_fn : (BytesView, FixedArray[Byte]) -> @compress.GzipStep raise @lib.SyncError,
  finish_fn : () -> @compress.GzipSummary raise @lib.SyncError,
) -> Unit {
  stream_open_chunks(in_file, in_path, in_size, progress~, chunk => {
    let mut pos = 0
    while true {
      let step = step_fn(chunk[pos:], out_buf)
      pos = pos + step.consumed
      if step.produced > 0 {
        write_nonempty(tmp_file, Bytes::from_array(out_buf[0:step.produced])[:])
      }
      match step.status {
        NeedMoreOutput => continue
        NeedMoreInput => if pos >= chunk.length() { break }
        Done => break
      }
    }
  })
  let _ = finish_fn()
}

///|
async fn execute_compress_op(plan : Plan, output_path : String) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    let in_path = plan.inputs[0]
    let output = prepare_output(output_path)
    if plan.operation == "compress" {
      if plan.streaming {
        let in_file = open_regular_input(in_path)
        defer in_file.close()
        let in_size = check_open_regular_sized(
          in_file,
          in_path,
          limits.max_new_bytes,
        )
        let out_buf = FixedArray::make(65536, b'\x00')
        let progress = make_progress(plan, in_size)
        match plan.compress_format {
          Gzip => {
            let enc = @compress.GzipEncoder::new(
              limits.max_new_bytes,
              limits.max_output_bytes,
            )
            publish_stream(output, tmp_file => {
              stream_compress_drive(
                in_file,
                in_path,
                in_size,
                tmp_file,
                out_buf,
                progress,
                (src, dst, finish) => enc.step(src, dst, finish~),
                () => enc.summary(),
              )
            })
          }
          Zlib => {
            let enc = @compress.ZlibEncoder::new(
              limits.max_new_bytes,
              limits.max_output_bytes,
            )
            publish_stream(output, tmp_file => {
              stream_compress_drive(
                in_file,
                in_path,
                in_size,
                tmp_file,
                out_buf,
                progress,
                (src, dst, finish) => enc.step(src, dst, finish~),
                () => enc.summary(),
              )
            })
          }
          Deflate => {
            let enc = @compress.DeflateEncoder::new(
              limits.max_new_bytes,
              limits.max_output_bytes,
            )
            publish_stream(output, tmp_file => {
              stream_compress_drive(
                in_file,
                in_path,
                in_size,
                tmp_file,
                out_buf,
                progress,
                (src, dst, finish) => enc.step(src, dst, finish~),
                () => enc.summary(),
              )
            })
          }
        }
        finish_progress(progress)
      } else {
        let raw = bounded_read(in_path, limits.max_new_bytes)
        let compressed = match plan.compress_format {
          Gzip =>
            @compress.compress_gzip(
              raw[:],
              limits.max_new_bytes,
              limits.max_output_bytes,
            )
          Zlib =>
            @compress.compress_zlib(
              raw[:],
              limits.max_new_bytes,
              limits.max_output_bytes,
            )
          Deflate =>
            @compress.compress_deflate(
              raw[:],
              limits.max_new_bytes,
              limits.max_output_bytes,
            )
        }
        publish_output(output, compressed)
        emit_instant_progress(plan, raw.length().to_int64())
      }
    } else if plan.streaming {
      let in_file = open_regular_input(in_path)
      defer in_file.close()
      let in_size = check_open_regular_sized(
        in_file,
        in_path,
        limits.max_delta_bytes,
      )
      let out_buf = FixedArray::make(65536, b'\x00')
      let progress = make_progress(plan, in_size)
      match plan.compress_format {
        Gzip => {
          let dec = @compress.GzipDecoder::new(
            limits.max_delta_bytes,
            limits.max_output_bytes,
          )
          publish_stream(output, tmp_file => {
            stream_decompress_drive(
              in_file,
              in_path,
              in_size,
              tmp_file,
              out_buf,
              progress,
              (src, dst) => dec.step(src, dst),
              () => dec.finish(),
            )
          })
        }
        Zlib => {
          let dec = @compress.ZlibDecoder::new(
            limits.max_delta_bytes,
            limits.max_output_bytes,
          )
          publish_stream(output, tmp_file => {
            stream_decompress_drive(
              in_file,
              in_path,
              in_size,
              tmp_file,
              out_buf,
              progress,
              (src, dst) => dec.step(src, dst),
              () => dec.finish(),
            )
          })
        }
        Deflate => {
          let dec = @compress.DeflateDecoder::new(
            limits.max_delta_bytes,
            limits.max_output_bytes,
          )
          publish_stream(output, tmp_file => {
            stream_decompress_drive(
              in_file,
              in_path,
              in_size,
              tmp_file,
              out_buf,
              progress,
              (src, dst) => dec.step(src, dst),
              () => dec.finish(),
            )
          })
        }
      }
      finish_progress(progress)
    } else {
      let encoded = bounded_read(in_path, limits.max_delta_bytes)
      let plain = match plan.compress_format {
        Gzip =>
          @compress.decompress_gzip(
            encoded[:],
            limits.max_delta_bytes,
            limits.max_output_bytes,
          )
        Zlib =>
          @compress.decompress_zlib(
            encoded[:],
            limits.max_delta_bytes,
            limits.max_output_bytes,
          )
        Deflate =>
          @compress.decompress_deflate(
            encoded[:],
            limits.max_delta_bytes,
            limits.max_output_bytes,
          )
      }
      publish_output(output, plain)
      emit_instant_progress(plan, encoded.length().to_int64())
    }
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
