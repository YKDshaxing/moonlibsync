// SPDX-License-Identifier: LGPL-2.1-or-later

///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 else {
    @stdio.stderr.write(
      b"native-probe usage: <roundtrip|read-missing|write-missing|fail> <path>\n",
    )
    @env.exit(64)
  }
  let mode = args[1]
  let path = args[2]
  if mode == "fail" {
    @stdio.stderr.write(b"native-probe intentional-failure\n")
    @env.exit(23)
  }
  try {
    match mode {
      "roundtrip" => {
        let sample = b"\x00\x7f\x80\xff"
        @fs.write_binary(path, sample, create_mode=CreateNew)
        let actual = @fs.read_binary(path)
        guard actual == sample else { fail("binary byte comparison failed") }
        let empty_path = path + ".empty"
        @fs.write_binary(empty_path, b"", create_mode=CreateNew)
        guard @fs.read_binary(empty_path) == b"" else {
          fail("empty byte comparison failed")
        }
        println(
          "native-probe roundtrip-ok bytes=00,7f,80,ff empty=ok path=\{path}",
        )
      }
      "read-missing" => {
        let _ = @fs.read_binary(path)
        println("native-probe unexpected-read-success")
        @env.exit(25)
      }
      "write-missing" => {
        @fs.write_binary(path, b"\x00", create_mode=CreateNew)
        println("native-probe unexpected-write-success")
        @env.exit(25)
      }
      _ => fail("unknown probe mode")
    }
  } catch {
    err => {
      @stdio.stderr.write(@utf8.encode("native-probe io-error: \{err}\n"))
      @env.exit(24)
    }
  }
}
