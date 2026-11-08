// SPDX-License-Identifier: LGPL-2.1-or-later
// Reference test adapter only. All output paths are fresh temporary files.

///|
async fn main {
  let args = @env.args()
  guard args.length() == 5 else { @env.exit(64) }
  let basis = @fs.read_binary(args[1])
  let options : @moonlibsync.SignatureOptions = {
    block_len: @string.parse_int64(args[3]),
    strong_sum_len: @string.parse_int64(args[4]),
  }
  let result = @moonlibsync.signature(
    basis,
    options,
    @moonlibsync.Limits::default(),
  )
  @fs.write_binary(args[2], result, create_mode=CreateNew)
}
