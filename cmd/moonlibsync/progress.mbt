// SPDX-License-Identifier: LGPL-2.1-or-later

///|
priv struct ProgressReporter {
  op : String
  enabled : Bool
  mut total : Int64
  mut done : Int64
  start_ms : Int64
  mut last_emit_ms : Int64
  interval_ms : Int64
  mut finished : Bool
}

///|
fn ProgressReporter::new(
  op : String,
  total : Int64,
  enabled : Bool,
  interval_ms~ : Int64 = 150L,
) -> ProgressReporter {
  if !enabled {
    {
      op,
      enabled: false,
      total,
      done: 0L,
      start_ms: 0L,
      last_emit_ms: 0L,
      interval_ms,
      finished: false,
    }
  } else {
    let now = @async.now()
    {
      op,
      enabled: true,
      total,
      done: 0L,
      start_ms: now,
      last_emit_ms: now,
      interval_ms,
      finished: false,
    }
  }
}

///|
fn make_progress(plan : Plan, total : Int64) -> ProgressReporter? {
  if plan.progress {
    Some(ProgressReporter::new(plan.operation, total, true))
  } else {
    None
  }
}

///|
fn format_rate_mib(done : Int64, elapsed_ms : Int64) -> String {
  if done <= 0L || elapsed_ms <= 0L {
    "0.00"
  } else {
    let mib_per_sec = done.to_double() *
      1000.0 /
      (elapsed_ms.to_double() * 1048576.0)
    let hundredths = (mib_per_sec * 100.0).to_int64()
    let clamped = if hundredths < 0L { 0L } else { hundredths }
    let whole = clamped / 100L
    let frac = clamped % 100L
    if frac < 10L {
      "\{whole}.0\{frac}"
    } else {
      "\{whole}.\{frac}"
    }
  }
}

///|
fn format_progress_line(
  op : String,
  done : Int64,
  total : Int64,
  elapsed_ms : Int64,
) -> String {
  let safe_done = if done < 0L { 0L } else { done }
  let safe_elapsed = if elapsed_ms < 0L { 0L } else { elapsed_ms }
  let rate = format_rate_mib(safe_done, safe_elapsed)
  if total < 0L {
    "[moonlibsync] \{op} \{safe_done} B | \{rate} MiB/s\n"
  } else {
    let eff_done = if total > 0L && safe_done > total {
      total
    } else {
      safe_done
    }
    let pct : Int64 = if total == 0L || eff_done >= total {
      100L
    } else if eff_done == 0L {
      0L
    } else {
      let raw = (eff_done.to_double() * 100.0 / total.to_double()).to_int64()
      if raw > 100L {
        100L
      } else if raw < 0L {
        0L
      } else {
        raw
      }
    }
    let eta : Int64 = if total == 0L ||
      eff_done >= total ||
      eff_done == 0L ||
      safe_elapsed == 0L {
      0L
    } else {
      let rem = total - eff_done
      let secs = rem.to_double() *
        safe_elapsed.to_double() /
        (eff_done.to_double() * 1000.0)
      if secs < 0.0 {
        0L
      } else {
        secs.to_int64()
      }
    }
    "[moonlibsync] \{op} \{eff_done}/\{total} B (\{pct}%) | \{rate} MiB/s | ETA \{eta}s\n"
  }
}

///|
async fn stderr_bytes(data : Bytes) -> Unit {
  @stdio.stderr.write(data)
}

///|
async fn ProgressReporter::advance(
  self : ProgressReporter,
  delta : Int64,
  writer~ : async (Bytes) -> Unit = stderr_bytes,
) -> Unit {
  if !self.enabled || self.finished {
    return
  }
  if delta > 0L {
    self.done = self.done + delta
  }
  let now = @async.now()
  if now - self.last_emit_ms >= self.interval_ms {
    self.last_emit_ms = now
    let line = format_progress_line(
      self.op,
      self.done,
      self.total,
      now - self.start_ms,
    )
    writer(@utf8.encode(line)) catch {
      _ => ()
    }
  }
}

///|
async fn ProgressReporter::finish(
  self : ProgressReporter,
  writer~ : async (Bytes) -> Unit = stderr_bytes,
) -> Unit {
  if !self.enabled || self.finished {
    return
  }
  self.finished = true
  if self.total < 0L || self.done > self.total {
    self.total = self.done
  }
  let now = @async.now()
  self.last_emit_ms = now
  let line = format_progress_line(
    self.op,
    self.done,
    self.total,
    now - self.start_ms,
  )
  writer(@utf8.encode(line)) catch {
    _ => ()
  }
}

///|
async fn advance_progress(progress : ProgressReporter?, delta : Int64) -> Unit {
  match progress {
    Some(p) => p.advance(delta)
    None => ()
  }
}

///|
async fn finish_progress(progress : ProgressReporter?) -> Unit {
  match progress {
    Some(p) => p.finish()
    None => ()
  }
}

///|
async fn emit_instant_progress(plan : Plan, bytes : Int64) -> Unit {
  if plan.progress {
    let p = ProgressReporter::new(plan.operation, bytes, true)
    p.done = if bytes < 0L { 0L } else { bytes }
    p.finish()
  }
}
