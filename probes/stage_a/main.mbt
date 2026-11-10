// SPDX-License-Identifier: LGPL-2.1-or-later
// Stage A public-API test adapter, not a product CLI or timing harness.

///|
async fn execute(args : Array[String]) -> Unit {
  let d = @moonlibsync.Limits::default()
  match args[1] {
    "group" => {
      // No OLD input; one prepared object for every target in this invocation.
      let sig = @fs.read_binary(args[2])
      let p = @moonlibsync.prepare_signature(sig, d)
      for i in 4..<args.length() {
        let new = @fs.read_binary(args[i])
        let one = @moonlibsync.delta(sig, new, d)
        let reused = p.delta(new, d)
        guard one == reused && p.delta(new, d) == reused else {
          abort("STAGE_A_DETERMINISM")
        }
        @fs.write_binary(
          args[3] + "/one-\{i - 4}.delta",
          one,
          create_mode=CreateNew,
        )
        @fs.write_binary(
          args[3] + "/prepared-\{i - 4}.delta",
          reused,
          create_mode=CreateNew,
        )
      }
      println(
        "prepared=1 targets=\{args.length() - 4} calls=\{2 * (args.length() - 4)}",
      )
    }
    "inspect" => {
      let s = @moonlibsync.inspect_signature(@fs.read_binary(args[2]), d)
      let bytes = @fs.read_binary(args[3])
      let v = @moonlibsync.inspect_delta(bytes, d)
      let c = @moonlibsync.check_patch(@string.parse_int64(args[4]), bytes, d)
      assert_eq(v.output_bytes, c.summary.output_bytes)
      println(
        "\{s.block_len} \{s.strong_sum_len} \{s.record_count} \{s.signature_bytes} \{v.delta_bytes} \{v.instruction_count} \{v.literal_commands} \{v.copy_commands} \{v.literal_bytes} \{v.copy_bytes} \{v.output_bytes}",
      )
    }
    "basis" => {
      let value = @moonlibsync.create_basis_info(
        @fs.read_binary(args[2]),
        @fs.read_binary(args[3]),
        d,
      )
      @fs.write_binary(
        args[4],
        @moonlibsync.encode_basis_info(value, d),
        create_mode=CreateNew,
      )
    }
    "manifest" => {
      // Sender receives INFO/SIG/NEW/DELTA only, never OLD or a basis path.
      let info = @moonlibsync.parse_basis_info(@fs.read_binary(args[2]), d)
      let value = @moonlibsync.create_update_manifest(
        info,
        @fs.read_binary(args[3]),
        @fs.read_binary(args[4]),
        @fs.read_binary(args[5]),
        d,
      )
      @fs.write_binary(
        args[6],
        @moonlibsync.encode_update_manifest(value, d),
        create_mode=CreateNew,
      )
    }
    "verified" => {
      let manifest = @moonlibsync.parse_update_manifest(
        @fs.read_binary(args[4]),
        d,
      )
      let out = @moonlibsync.verified_patch(
        @fs.read_binary(args[2]),
        @fs.read_binary(args[3]),
        manifest,
        d,
      )
      @fs.write_binary(args[5], out, create_mode=CreateNew)
    }
    _ => abort("STAGE_A_UNKNOWN_OPERATION")
  }
}

///|
async fn main {
  execute(@env.args()) catch {
    error => {
      println("STAGE_A_API_FAILURE \{error}")
      @env.exit(1)
    }
  }
}
