// SPDX-License-Identifier: LGPL-2.1-or-later

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
        let enc = @compress.GzipEncoder::new(
          limits.max_new_bytes,
          limits.max_output_bytes,
        )
        let out_buf = FixedArray::make(65536, b'\x00')
        let progress = make_progress(plan, in_size)
        publish_stream(output, tmp_file => {
          stream_open_chunks(in_file, in_path, in_size, progress~, chunk => {
            let mut pos = 0
            while true {
              let step = enc.step(chunk[pos:], out_buf, finish=false)
              pos = pos + step.consumed
              if step.produced > 0 {
                write_nonempty(
                  tmp_file,
                  Bytes::from_array(out_buf[0:step.produced])[:],
                )
              }
              match step.status {
                NeedMoreOutput => continue
                NeedMoreInput => if pos >= chunk.length() { break }
                Done => break
              }
            }
          })
          while true {
            let step = enc.step(b""[:], out_buf, finish=true)
            if step.produced > 0 {
              write_nonempty(
                tmp_file,
                Bytes::from_array(out_buf[0:step.produced])[:],
              )
            }
            if step.status is Done {
              break
            }
          }
          let _ = enc.summary()
        })
        finish_progress(progress)
      } else {
        let raw = bounded_read(in_path, limits.max_new_bytes)
        let gz = @compress.compress_gzip(
          raw[:],
          limits.max_new_bytes,
          limits.max_output_bytes,
        )
        publish_output(output, gz)
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
      let dec = @compress.GzipDecoder::new(
        limits.max_delta_bytes,
        limits.max_output_bytes,
      )
      let out_buf = FixedArray::make(65536, b'\x00')
      let progress = make_progress(plan, in_size)
      publish_stream(output, tmp_file => {
        stream_open_chunks(in_file, in_path, in_size, progress~, chunk => {
          let mut pos = 0
          while true {
            let step = dec.step(chunk[pos:], out_buf)
            pos = pos + step.consumed
            if step.produced > 0 {
              write_nonempty(
                tmp_file,
                Bytes::from_array(out_buf[0:step.produced])[:],
              )
            }
            match step.status {
              NeedMoreOutput => continue
              NeedMoreInput => if pos >= chunk.length() { break }
              Done => break
            }
          }
        })
        let _ = dec.finish()
      })
      finish_progress(progress)
    } else {
      let gz = bounded_read(in_path, limits.max_delta_bytes)
      let plain = @compress.decompress_gzip(
        gz[:],
        limits.max_delta_bytes,
        limits.max_output_bytes,
      )
      publish_output(output, plain)
      emit_instant_progress(plan, gz.length().to_int64())
    }
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
