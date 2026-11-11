// SPDX-License-Identifier: LGPL-2.1-or-later

///|
pub(all) struct UpdateOptions {
  min_savings_bytes : Int64
}

///|
pub fn UpdateOptions::default() -> UpdateOptions {
  { min_savings_bytes: 0L, }
}

///|
pub(all) enum UpdatePayload {
  Delta(Bytes)
  Full(Bytes)
}

///|
/// Immutable local diagnostics, never serialized into the transfer manifest.
/// savings_bytes describes the selected payload (zero for Full).
pub(all) struct UpdateDecision {
  kind : String
  reason : String
  new_bytes : Int64
  delta_bytes : Int64
  payload_bytes : Int64
  savings_bytes : Int64
  min_savings_bytes : Int64
}

///|
pub(all) struct UpdatePlan {
  payload : UpdatePayload
  decision : UpdateDecision
}

///|
fn update_options(options : UpdateOptions) -> Unit raise SyncError {
  guard options.min_savings_bytes >= 0L else {
    raise InvalidOptions("min_savings_bytes")
  }
}

///|
fn update_decision(
  n : Int64,
  d : Int64,
  options : UpdateOptions,
) -> UpdateDecision {
  // Actual Bytes lengths are nonnegative Int32. Subtract only when D < N;
  // never add an arbitrary Int64 threshold to D.
  let smaller = d < n
  let savings = if smaller { n - d } else { 0L }
  let selected = smaller && savings >= options.min_savings_bytes
  {
    kind: if selected {
      "librsync-delta"
    } else {
      "full-file"
    },
    reason: if selected {
      "minimum-savings-met"
    } else if !smaller {
      "delta-not-smaller"
    } else {
      "below-minimum-savings"
    },
    new_bytes: n,
    delta_bytes: d,
    payload_bytes: if selected {
      d
    } else {
      n
    },
    savings_bytes: if selected {
      savings
    } else {
      0L
    },
    min_savings_bytes: options.min_savings_bytes,
  }
}

///|
/// Limits -> options -> ordinary delta (all errors propagate) -> selection.
/// Always generates the candidate first; Full does not waive generation budgets
/// or reduce already incurred computation, buffers or peak-memory costs.
pub fn plan_update(
  sig : Bytes,
  new : Bytes,
  options : UpdateOptions,
  limits : Limits,
) -> UpdatePlan raise SyncError {
  limits.validate()
  update_options(options)
  let candidate = delta(sig, new, limits)
  let decision = update_decision(
    new.length().to_int64(),
    candidate.length().to_int64(),
    options,
  )
  {
    payload: if decision.kind == "librsync-delta" {
      Delta(candidate)
    } else {
      Full(new)
    },
    decision,
  }
}
