// SPDX-License-Identifier: LGPL-2.1-or-later
// Reference/benchmark adapter only, not a product CLI. No basis input exists.

///|
fn timed_one_shot(
  sig : Bytes,
  news : Array[Bytes],
  d : @lib.Limits,
) -> (Array[Bytes], Array[Double], Double) raise @lib.SyncError {
  let results : Array[Bytes] = []
  let times : Array[Double] = []
  let total = @bench.monotonic_clock_start()
  for new in news {
    let start = @bench.monotonic_clock_start()
    let result = @lib.delta(sig, new, d)
    let elapsed = @bench.monotonic_clock_end(start)
    results.push(result)
    times.push(elapsed)
  }
  (results, times, @bench.monotonic_clock_end(total))
}

///|
fn timed_prepared(
  sig : Bytes,
  news : Array[Bytes],
  d : @lib.Limits,
) -> (Array[Bytes], Double, Array[Double], Double) raise @lib.SyncError {
  let results : Array[Bytes] = []
  let times : Array[Double] = []
  let total = @bench.monotonic_clock_start()
  let start = @bench.monotonic_clock_start()
  let prepared = @lib.prepare_signature(sig, d)
  let preparation = @bench.monotonic_clock_end(start)
  for new in news {
    let start = @bench.monotonic_clock_start()
    let result = prepared.delta(new, d)
    let elapsed = @bench.monotonic_clock_end(start)
    results.push(result)
    times.push(elapsed)
  }
  (results, preparation, times, @bench.monotonic_clock_end(total))
}

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 5 else { @env.exit(64) }
  let mode = args[1]
  let sig = @fs.read_binary(args[2])
  let out = args[3]
  let news : Array[Bytes] = []
  for i in 4..<args.length() {
    news.push(@fs.read_binary(args[i]))
  }
  let d = @lib.Limits::default()
  if mode == "generate" {
    let prepared = @lib.prepare_signature(sig, d)
    for i in 0..<news.length() {
      let result = prepared.delta(news[i], d)
      guard result == @lib.delta(sig, news[i], d) else {
        abort("PREPARED_BYTES_MISMATCH")
      }
      @fs.write_binary(
        out + "/reused-\{i}.delta",
        result,
        create_mode=CreateNew,
      )
    }
    return
  }
  guard mode == "bench" else { @env.exit(64) }
  // Immutable benchmark policy: 2 warmups + 7 formal rounds, alternating order.
  for round in 0..<9 {
    let (a, b) = if round % 2 == 0 {
      let a = timed_one_shot(sig, news, d)
      let b = timed_prepared(sig, news, d)
      (a, b)
    } else {
      let b = timed_prepared(sig, news, d)
      let a = timed_one_shot(sig, news, d)
      (a, b)
    }
    // Validation, formatting and file I/O are OUTSIDE all measured calls/totals.
    for i in 0..<news.length() {
      guard a.0[i] == b.0[i] else { abort("PREPARED_BYTES_MISMATCH") }
      @fs.write_binary(
        out + "/one-\{round}-\{i}.delta",
        a.0[i],
        create_mode=CreateNew,
      )
      @fs.write_binary(
        out + "/prepared-\{round}-\{i}.delta",
        b.0[i],
        create_mode=CreateNew,
      )
    }
    let phase = if round < 2 { "warmup" } else { "formal" }
    let one_times = a.1.map(t => t.to_string()).join(",")
    let prepared_times = b.2.map(t => t.to_string()).join(",")
    println(
      "{\"round\":\{round},\"phase\":\"\{phase}\",\"one_generation_us\":[\{one_times}],\"one_total_us\":\{a.2},\"prepare_us\":\{b.1},\"prepared_generation_us\":[\{prepared_times}],\"prepared_total_us\":\{b.3}}",
    )
  }
}
