// SPDX-License-Identifier: LGPL-2.1-or-later

///|
// Async-typed no-op is the default internal test hook.
#warnings("-unused_async")
async fn no_hook() -> Unit {
  ()
}

///|
async fn remove_owned(path : String) -> Unit {
  @fs.remove(path, allow_missing=false)
}

///|
async fn write_content(file : @fs.File, data : Bytes) -> Unit {
  file.write(data)
}

///|
async fn entry_exists(path : String) -> Bool {
  try {
    let _ = @fs.kind(path, follow_symlink=false)
    true
  } catch {
    @os_error.OsError::OsError(NotFound, ..) => false
    error => raise error
  }
}

///|
/// Resolve the actual parent; lstat the leaf, including dangling links.
/// Existing outputs also reject all aliases of an existing input by OS semantics.
async fn prepare_output(path : String) -> String {
  let absolute = @path.Path(path).resolve()
  guard !entry_exists(absolute.to_string()) else {
    raise FileFailure("output already exists: " + path)
  }
  let parent = @fs.realpath(absolute.dirname().to_string())
  guard @fs.kind(parent) is @fs.FileKind::Directory else {
    raise FileFailure("output parent is not a directory: " + path)
  }
  let leaf = absolute.basename().to_owned()
  guard leaf != "" && leaf != "." && leaf != ".." else {
    raise FileFailure("invalid output filename: " + path)
  }
  if @path.sep != '/' {
    guard !leaf.contains(":") && !leaf.has_suffix(".") && !leaf.has_suffix(" ") else {
      raise FileFailure("unsupported Windows output filename: " + path)
    }
  }
  let result = @path.Path(parent).join(@path.Path(leaf)).to_string()
  guard !entry_exists(result) else {
    raise FileFailure("output already exists: " + path)
  }
  result
}

///|
/// Same handle for kind/size/read. Allocate only the checked initial size.
/// Read at most initial_size bytes plus a one-byte EOF probe; reject changes.
async fn read_open_file(
  file : @fs.File,
  path : String,
  maximum : Int64,
  after_size~ : async () -> Unit = no_hook,
) -> Bytes {
  guard file.kind() is @fs.FileKind::Regular else {
    raise FileFailure("unsupported input kind: " + path)
  }
  let size = file.size()
  guard size >= 0L && maximum >= 0L && maximum <= 2147483647L && size <= maximum else {
    raise FileFailure(
      "ReadLimitExceeded: " + path + " size=\{size} limit=\{maximum}",
    )
  }
  after_size()
  let buffer = FixedArray::make(size.to_int(), b'\x00')
  let mut pos = 0
  while pos < buffer.length() {
    let remaining = buffer.length() - pos
    let take = if remaining < 65536 { remaining } else { 65536 }
    let count = file.read_at(
      buffer,
      position=pos.to_int64(),
      offset=pos,
      len=take,
    )
    guard count > 0 && count <= take else {
      raise FileFailure("InputChanged: short read: " + path)
    }
    pos = pos + count
  }
  let sentinel = FixedArray::make(1, b'\x00')
  guard file.read_at(sentinel, position=size, len=1) == 0 && file.size() == size else {
    raise FileFailure("InputChanged: file grew or changed size: " + path)
  }
  Bytes::from_array(buffer[:])
}

///|
async fn bounded_read(path : String, maximum : Int64) -> Bytes {
  try {
    let file = open_regular_input(path)
    defer file.close()
    read_open_file(file, path, maximum)
  } catch {
    error => raise FileFailure("read '" + path + "': \{cli_error_text(error)}")
  }
}

///|
/// Reject unsupported leaves before open (including FIFOs), then verify the
/// opened handle. This is shared by bounded content reads and metadata preflight.
async fn open_regular_input(path : String) -> @fs.File {
  guard @fs.kind(path, follow_symlink=false) is @fs.FileKind::Regular else {
    raise FileFailure("unsupported input kind or leaf symlink: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly, create_mode=OpenExisting)
  errdefer file.close()
  guard file.kind() is @fs.FileKind::Regular else {
    raise FileFailure("unsupported input kind: " + path)
  }
  file
}

///|
/// Internal hooks are only for controlled whitebox failure tests, never CLI args.
async fn publish_at(
  temporary : String,
  output : String,
  data : Bytes,
  writer~ : async (@fs.File, Bytes) -> Unit = write_content,
  syncer~ : async (@fs.File) -> Unit = sync_content,
  before_commit~ : async () -> Unit = no_hook,
  cleanup~ : async (String) -> Unit = remove_owned,
) -> Unit {
  // Outside the owned cleanup block: a failed CreateNew never grants ownership.
  let file = @fs.open(
    temporary,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o600,
  )
  let mut opened = true
  try {
    writer(file, data)
    syncer(file)
    file.close()
    opened = false
    before_commit()
    @fs.rename(temporary, output, replace=false)
  } catch {
    error => {
      if opened {
        file.close()
      }
      cleanup(temporary) catch {
        cleanup_error =>
          raise FileFailure(
            "write/commit '" +
            output +
            "': \{cli_error_text(error)}; cleanup failed '" +
            temporary +
            "': \{cli_error_text(cleanup_error)}",
          )
      }
      raise FileFailure(
        "write/commit '" + output + "': \{cli_error_text(error)}",
      )
    }
  }
}

///|
async fn publish_output(output : String, data : Bytes) -> Unit {
  let random = match @env.rand(16) {
    Some(value) => @hex.encode(value)
    None => raise FileFailure("temporary name randomness unavailable")
  }
  let parent = @path.Path(output).dirname()
  let temporary = parent
    .join(@path.Path(".moonlibsync-" + random + ".tmp"))
    .to_string()
  publish_at(temporary, output, data)
}

///|
async fn sync_content(file : @fs.File) -> Unit {
  file.sync(only_data=false)
}
