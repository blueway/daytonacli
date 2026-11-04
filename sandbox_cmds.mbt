///|
/// Sandbox commands. The top-level shortcuts and the hidden `sandbox` group
/// share these implementations.

///|
/// Path for one sandbox.
pub fn sandbox_path(reference : String) -> String {
  "/sandbox/" + url_encode(reference)
}

///|
/// Print a sandbox's build logs from the API.
pub async fn print_build_logs(reference : String) -> Unit {
  match
    api_get("/sandbox/" + url_encode(reference) + "/build-logs?follow=false") {
    Ok(logs) =>
      match logs {
        String(text) =>
          if text.length() > 0 {
            @stdio.stdout.write(text)
            if !text.has_suffix("\n") {
              out("")
            }
          }
        _ => ()
      }
    Err(_) => ()
  }
}

///|
/// Poll a sandbox until it reaches one of the wanted states, or errors.
pub async fn await_sandbox_state(
  reference : String,
  wanted : Array[String],
  timeout_seconds : Int32,
) -> Result[Json, String] {
  let mut elapsed = 0
  while elapsed <= timeout_seconds {
    let sandbox = match api_get(sandbox_path(reference)) {
      Ok(sandbox) => sandbox
      Err(error) => return Err(error)
    }
    let state = sandbox_state(sandbox)
    if wanted.contains(state) {
      return Ok(sandbox)
    }
    if state == "error" || state == "build_failed" || state == "destroyed" {
      print_build_logs(reference)
      return Err("sandbox entered state \\{sandbox_state_label(state)}")
    }
    @async.sleep(1000)
    elapsed = elapsed + 1
  }
  Err("timed out waiting for sandbox \\{reference}")
}

///|
/// Parse KEY=VALUE pairs, ignoring malformed entries as the Go CLI does.
pub fn parse_pairs(values : Array[String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for value in values {
    match split_once(value, "=") {
      Some((key, item)) => result.set(key, item)
      None => ()
    }
  }
  result
}

///|
/// Convert a string map to a JSON object.
pub fn map_json(values : Map[String, String]) -> Json {
  let fields : Map[String, Json] = Map([])
  for pair in values {
    let (key, value) = pair
    fields.set(key, Json::string(value))
  }
  Json::object(fields)
}

///|
/// Build a JSON object from ordered pairs.
pub fn json_obj(pairs : Array[(String, Json)]) -> Json {
  let fields : Map[String, Json] = Map([])
  for pair in pairs {
    let (key, value) = pair
    fields.set(key, value)
  }
  Json::object(fields)
}

///|
/// Add a field to a JSON object.
pub fn with_field(object : Json, key : String, value : Json) -> Json {
  match object {
    Object(fields) => {
      let next : Map[String, Json] = Map([])
      for pair in fields {
        next.set(pair.0, pair.1)
      }
      next.set(key, value)
      Json::object(next)
    }
    _ => object
  }
}

///|
/// `daytona create` and `daytona sandbox create`.
pub async fn cmd_sandbox_create(args : Array[String]) -> Result[Unit, String] {
  let specs = [
    vflag("snapshot", ""),
    vflag("name", ""),
    vflag("user", ""),
    lflag("env", "e"),
    lflag("label", "l"),
    bflag("public", ""),
    vflag("target", ""),
    vflag("cpu", ""),
    vflag("gpu", ""),
    vflag("memory", ""),
    vflag("disk", ""),
    vflag("auto-stop", ""),
    vflag("auto-pause", ""),
    vflag("auto-archive", ""),
    vflag("auto-delete", ""),
    vflag("ttl", ""),
    vflag("queue-timeout", ""),
    lflag("volume", "v"),
    vflag("dockerfile", "f"),
    lflag("context", "c"),
    bflag("network-block-all", ""),
    bflag("kvm", ""),
    vflag("network-allow-list", ""),
  ]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Create a new sandbox")
    out("")
    out("Usage: daytona create [flags]")
    out("")
    out("Flags:")
    out("      --snapshot string       Snapshot to use for the sandbox")
    out("      --name string           Name of the sandbox")
    out("      --user string           User associated with the sandbox")
    out(
      "  -e, --env stringArray       Environment variables (format: KEY=VALUE)",
    )
    out("  -l, --label stringArray     Labels (format: KEY=VALUE)")
    out("      --public                Make sandbox publicly accessible")
    out("      --target string         Target region (eu, us)")
    out("      --cpu int               CPU cores allocated to the sandbox")
    out("      --gpu int               GPU units allocated to the sandbox")
    out("      --memory int            Memory allocated in MB")
    out("      --disk int              Disk space allocated in GB")
    out(
      "      --auto-stop int         Auto-stop interval in minutes (default 15)",
    )
    out(
      "      --auto-pause int        Auto-pause interval in minutes (default 60)",
    )
    out(
      "      --auto-archive int      Auto-archive interval in minutes (default 10080)",
    )
    out(
      "      --auto-delete int       Auto-delete interval in minutes (default -1)",
    )
    out("      --ttl int               Maximum time to live in minutes")
    out("      --queue-timeout int     Minutes to wait for runner assignment")
    out("  -v, --volume stringArray    Volumes to mount (VOLUME:MOUNT_PATH)")
    out(
      "  -f, --dockerfile string     Path to Dockerfile for the sandbox snapshot",
    )
    out(
      "  -c, --context stringArray   Files or directories for the build context",
    )
    out("      --network-block-all     Block all network access")
    out("      --kvm                   Expose KVM inside the sandbox")
    out("      --network-allow-list    Comma-separated allowed CIDR addresses")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona create [flags]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match check_exclusive(parsed, ["snapshot", "dockerfile"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match check_exclusive(parsed, ["snapshot", "context"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match check_exclusive(parsed, ["auto-stop", "auto-pause"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if arg_changed(parsed, "dockerfile") || arg_changed(parsed, "context") {
    return Err(
      "Dockerfile builds are not supported by this build; use --snapshot, or build and push the image with `daytona snapshot push`",
    )
  }
  let auto_delete = arg_int(parsed, "auto-delete", -1)
  let auto_pause = arg_int(parsed, "auto-pause", 60)
  let auto_stop = arg_int(parsed, "auto-stop", 15)
  if arg_changed(parsed, "auto-pause") {
    if auto_pause < 0 {
      return Err("auto-pause interval must be a non-negative integer")
    }
    if auto_pause > 0 && auto_delete == 0 {
      return Err(
        "ephemeral sandboxes cannot have auto-pause enabled. Set --auto-pause to 0",
      )
    }
  } else if arg_changed(parsed, "auto-stop") && auto_stop < 0 {
    return Err("auto-stop interval must be a non-negative integer")
  }
  let ttl = arg_int(parsed, "ttl", 0)
  if arg_changed(parsed, "ttl") && ttl < 0 {
    return Err("ttl must be a non-negative integer")
  }
  let queue_timeout = arg_int(parsed, "queue-timeout", 0)
  if arg_changed(parsed, "queue-timeout") && queue_timeout < 1 {
    return Err("queue-timeout must be a positive integer")
  }
  let mut body = json_obj([])
  let snapshot = arg_value(parsed, "snapshot")
  if snapshot != "" {
    body = with_field(body, "snapshot", Json::string(snapshot))
  }
  let name = arg_value(parsed, "name")
  if name != "" {
    body = with_field(body, "name", Json::string(name))
  }
  let user = arg_value(parsed, "user")
  if user != "" {
    body = with_field(body, "user", Json::string(user))
  }
  let environment = parse_pairs(arg_list(parsed, "env"))
  if environment.length() > 0 {
    body = with_field(body, "env", map_json(environment))
  }
  let labels = parse_pairs(arg_list(parsed, "label"))
  if labels.length() > 0 {
    body = with_field(body, "labels", map_json(labels))
  }
  if arg_bool(parsed, "public") {
    body = with_field(body, "public", Json::boolean(true))
  }
  let target = arg_value(parsed, "target")
  if target != "" {
    body = with_field(body, "target", Json::string(target))
  }
  for
    pair in [
      ("cpu", "cpu"),
      ("gpu", "gpu"),
      ("memory", "memory"),
      ("disk", "disk"),
    ] {
    let (flag, field) = pair
    let value = arg_int(parsed, flag, 0)
    if value > 0 {
      body = with_field(body, field, Json::number(value.to_double()))
    }
  }
  if arg_changed(parsed, "auto-pause") {
    body = with_field(
      body,
      "autoPauseInterval",
      Json::number(auto_pause.to_double()),
    )
  } else if arg_changed(parsed, "auto-stop") {
    body = with_field(
      body,
      "autoStopInterval",
      Json::number(auto_stop.to_double()),
    )
  }
  let auto_archive = arg_int(parsed, "auto-archive", 10080)
  if auto_archive >= 0 {
    body = with_field(
      body,
      "autoArchiveInterval",
      Json::number(auto_archive.to_double()),
    )
  }
  body = with_field(
    body,
    "autoDeleteInterval",
    Json::number(auto_delete.to_double()),
  )
  if arg_changed(parsed, "ttl") {
    body = with_field(body, "ttlMinutes", Json::number(ttl.to_double()))
  }
  if arg_changed(parsed, "queue-timeout") {
    body = with_field(
      body,
      "queueTimeout",
      Json::number(queue_timeout.to_double()),
    )
  }
  body = with_field(
    body,
    "networkBlockAll",
    Json::boolean(arg_bool(parsed, "network-block-all")),
  )
  body = with_field(body, "kvm", Json::boolean(arg_bool(parsed, "kvm")))
  let allow_list = arg_value(parsed, "network-allow-list")
  if allow_list != "" {
    body = with_field(body, "networkAllowList", Json::string(allow_list))
  }
  let volumes : Array[Json] = []
  for volume in arg_list(parsed, "volume") {
    match split_once(volume, ":") {
      Some((volume_id, mount_path)) =>
        volumes.push(
          json_obj([
            ("volumeId", Json::string(volume_id)),
            ("mountPath", Json::string(mount_path)),
          ]),
        )
      None => ()
    }
  }
  if volumes.length() > 0 {
    body = with_field(body, "volumes", Json::array(volumes))
  }
  let created = match api_post("/sandbox", body) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let mut sandbox = created
  if sandbox_state(created) == "pending_build" {
    sandbox = match
      await_sandbox_state(
        created_id(created),
        [
          "building_snapshot", "pulling_snapshot", "starting", "started", "error",
          "build_failed",
        ],
        900,
      ) {
      Ok(sandbox) => sandbox
      Err(error) => return Err(error)
    }
    print_build_logs(json_string_or_empty(sandbox, "id"))
  }
  let id = json_string_or_empty(sandbox, "id")
  let preview = match
    api_get("/sandbox/" + url_encode(id) + "/ports/22222/preview-url") {
    Ok(preview) => json_string_or_empty(preview, "url")
    Err(error) => return Err(error)
  }
  let display_name = sandbox_name(sandbox)
  success("Sandbox '\{display_name}' created successfully")
  info("Connect via SSH:         daytona ssh \{display_name}")
  info("Open the Web Terminal:   \{preview}")
  Ok(())
}

///|
/// Extract the id field.
pub fn created_id(value : Json) -> String {
  json_string_or_empty(value, "id")
}

///|
/// `daytona list` and `daytona sandbox list`.
pub async fn cmd_sandbox_list(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("cursor", "c"), vflag("limit", "l"), vflag("format", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("List sandboxes")
    out("")
    out("Usage: daytona list [flags]")
    out("")
    out("Flags:")
    out("  -c, --cursor string   Cursor for pagination")
    out(
      "  -l, --limit int       Maximum number of items per page (default 100)",
    )
    out("      --format string   Output format: json or yaml")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona list [flags]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let limit = arg_int(parsed, "limit", 100)
  let mut path = "/sandbox?limit=\{limit}"
  if arg_changed(parsed, "cursor") {
    path = path + "&cursor=" + url_encode(arg_value(parsed, "cursor"))
  }
  let response = match api_get(path) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let items = json_array(response, "items")
  items.sort_by(fn(a, b) {
    let priority_a = sandbox_state_priority(sandbox_state(a))
    let priority_b = sandbox_state_priority(sandbox_state(b))
    if priority_a != priority_b {
      return if priority_a < priority_b { -1 } else { 1 }
    }
    let created_a = json_string_or_empty(a, "createdAt")
    let created_b = json_string_or_empty(b, "createdAt")
    // Newest first for equal priorities.
    if created_a > created_b {
      -1
    } else if created_a < created_b {
      1
    } else {
      0
    }
  })
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(response, format))
    return Ok(())
  }
  if items.length() == 0 {
    info("No sandboxes found")
    return Ok(())
  }
  let config = match load_config() {
    Ok(config) => config
    Err(_) => {
      let empty : Config = { active_profile_id: "", profiles: [], }
      empty
    }
  }
  print_active_organization(config)
  let now = @env.now().reinterpret_as_int64()
  let rows : Array[Array[String]] = []
  for sandbox in items {
    rows.push([
      sandbox_name(sandbox),
      sandbox_state_label(sandbox_state(sandbox)),
      json_string_or_empty(sandbox, "target"),
      last_event_label(sandbox, now),
    ])
  }
  out(render_table(["Sandbox", "State", "Region", "Last Event"], rows))
  match json_nullable_string(response, "nextCursor") {
    Some(cursor) if cursor.length() > 0 => out("\nNext cursor: \{cursor}")
    _ => ()
  }
  Ok(())
}

///|
/// `daytona info` and `daytona sandbox info`.
pub async fn cmd_sandbox_info(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("format", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Show sandbox information")
    out("")
    out("Usage: daytona info [SANDBOX_ID | SANDBOX_NAME] [flags]")
    out("")
    out("Flags:")
    out("      --format string   Output format: json or yaml")
    return Ok(())
  }
  match
    require_positionals(parsed, 1, "daytona info [SANDBOX_ID | SANDBOX_NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let reference = parsed.positionals[0]
  let sandbox = match api_get(sandbox_path(reference)) {
    Ok(sandbox) => sandbox
    Err(error) => return Err(error)
  }
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(sandbox, format))
    return Ok(())
  }
  let now = @env.now().reinterpret_as_int64()
  out(render_info("", sandbox_info_fields(sandbox, now)))
  Ok(())
}

///|
/// A start/stop/pause/archive action.
pub async fn cmd_sandbox_action(
  action : String,
  past_tense : String,
  args : Array[String],
) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("\{past_tense} a sandbox")
    out("")
    out("Usage: daytona \{action} [SANDBOX_ID | SANDBOX_NAME]")
    return Ok(())
  }
  match
    require_positionals(
      parsed,
      1,
      "daytona \{action} [SANDBOX_ID | SANDBOX_NAME]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let reference = parsed.positionals[0]
  match api_post_empty("/sandbox/" + url_encode(reference) + "/\{action}") {
    Ok(_) => {
      success("Sandbox \{reference} \{past_tense.to_lower()}")
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// `daytona delete` and `daytona sandbox delete`.
pub async fn cmd_sandbox_delete(args : Array[String]) -> Result[Unit, String] {
  let specs = [bflag("all", "a")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Delete a sandbox")
    out("")
    out("Usage: daytona delete [SANDBOX_ID | SANDBOX_NAME] [flags]")
    out("")
    out("Flags:")
    out("  -a, --all   Delete all sandboxes")
    return Ok(())
  }
  match
    require_max_positionals(
      parsed, 1, "daytona delete [SANDBOX_ID | SANDBOX_NAME]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if parsed.positionals.length() == 0 {
    if !arg_bool(parsed, "all") {
      out("Delete a sandbox")
      out("")
      out("Usage: daytona delete [SANDBOX_ID | SANDBOX_NAME] [flags]")
      return Ok(())
    }
    let all : Array[Json] = []
    let mut cursor = ""
    let mut first = true
    while first || cursor != "" {
      first = false
      let mut path = "/sandbox?limit=200"
      if cursor != "" {
        path = path + "&cursor=" + url_encode(cursor)
      }
      let page = match api_get(path) {
        Ok(page) => page
        Err(error) => return Err(error)
      }
      let items = json_array(page, "items")
      for item in items {
        all.push(item)
      }
      cursor = match json_nullable_string(page, "nextCursor") {
        Some(next) => next
        None => ""
      }
    }
    if all.length() == 0 {
      success("No sandboxes to delete")
      return Ok(())
    }
    let mut deleted = 0
    for item in all {
      let id = json_string_or_empty(item, "id")
      match api_delete("/sandbox/" + url_encode(id)) {
        Ok(_) => deleted = deleted + 1
        Err(error) => out("Failed to delete sandbox \{id}: \{error}")
      }
    }
    success("Deleted \{deleted} sandboxes")
    return Ok(())
  }
  let reference = parsed.positionals[0]
  match api_delete("/sandbox/" + url_encode(reference)) {
    Ok(_) => {
      success("Sandbox \{reference} deleted")
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// Split whitespace-separated fields.
pub fn split_fields(text : String) -> Array[String] {
  let fields : Array[String] = []
  let buf = StringBuilder()
  for char in text {
    if char == ' ' || char == '\t' || char == '\n' || char == '\r' {
      if buf.to_string().length() > 0 {
        fields.push(buf.to_string())
        buf.reset()
      }
    } else {
      buf.write_char(char)
    }
  }
  if buf.to_string().length() > 0 {
    fields.push(buf.to_string())
  }
  fields
}

///|
/// `daytona ssh`.
pub async fn cmd_sandbox_ssh(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("expires", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("SSH into a sandbox")
    out("")
    out("Usage: daytona ssh [SANDBOX_ID | SANDBOX_NAME] [flags]")
    out("")
    out("Flags:")
    out(
      "      --expires int   SSH access token expiration time in minutes (default 60)",
    )
    return Ok(())
  }
  match
    require_positionals(parsed, 1, "daytona ssh [SANDBOX_ID | SANDBOX_NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let reference = parsed.positionals[0]
  let sandbox = match api_get(sandbox_path(reference)) {
    Ok(sandbox) => sandbox
    Err(error) => return Err(error)
  }
  let state = sandbox_state(sandbox)
  if state != "started" {
    return Err(
      "sandbox must be in started state to ssh (current: \{sandbox_state_label(state)})",
    )
  }
  let id = json_string_or_empty(sandbox, "id")
  let expires = arg_int(parsed, "expires", 60)
  let mut path = "/sandbox/" + url_encode(id) + "/ssh-access"
  if expires > 0 {
    path = path + "?expiresInMinutes=\{expires}"
  }
  let access = match api_post_empty(path) {
    Ok(access) => access
    Err(error) => return Err(error)
  }
  let command = json_string_or_empty(access, "sshCommand")
  let fields = split_fields(command)
  if fields.length() < 2 || fields[0] != "ssh" {
    return Err(
      "unexpected SSH command format; expected \"ssh [-p port] user@host\"",
    )
  }
  let ssh_args : Array[String] = []
  for index in 1..<fields.length() {
    ssh_args.push(fields[index])
  }
  let status = @process.run("ssh", ssh_args) catch {
    error => return Err("failed to run ssh: \{error}")
  }
  if status != 0 {
    return Err("ssh exited with status \{status}")
  }
  Ok(())
}

///|
/// Quote one argument for a POSIX shell.
pub fn shell_quote(value : String) -> String {
  if value.length() == 0 {
    return "''"
  }
  let mut safe = true
  for char in value {
    let code = char.to_int()
    let allowed = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 95 ||
      code == 46 ||
      code == 47 ||
      code == 58 ||
      code == 64 ||
      code == 43 ||
      code == 44 ||
      code == 61
    if !allowed {
      safe = false
    }
  }
  if safe {
    return value
  }
  let buf = StringBuilder()
  buf.write_char('\'')
  for char in value {
    if char == '\'' {
      buf.write_string("'\"'\"'")
    } else {
      buf.write_char(char)
    }
  }
  buf.write_char('\'')
  buf.to_string()
}

///|
/// `daytona exec`.
pub async fn cmd_sandbox_exec(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("cwd", ""), vflag("timeout", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Execute a command in a running sandbox")
    out("")
    out(
      "Usage: daytona exec [SANDBOX_ID | SANDBOX_NAME] -- [COMMAND] [ARGS...]",
    )
    out("")
    out("Flags:")
    out("      --cwd string     Working directory for command execution")
    out("      --timeout int    Command timeout in seconds (0 for no timeout)")
    return Ok(())
  }
  match
    require_min_positionals(
      parsed, 2, "daytona exec [SANDBOX_ID | SANDBOX_NAME] -- [COMMAND] [ARGS...]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let reference = parsed.positionals[0]
  let command_args : Array[String] = []
  for index in 1..<parsed.positionals.length() {
    command_args.push(parsed.positionals[index])
  }
  let sandbox = match api_get(sandbox_path(reference)) {
    Ok(sandbox) => sandbox
    Err(error) => return Err(error)
  }
  let state = sandbox_state(sandbox)
  if state != "started" {
    return Err(
      "sandbox must be in started state to execute commands (current: \{sandbox_state_label(state)})",
    )
  }
  let sandbox_id = json_string_or_empty(sandbox, "id")
  let proxy_url = match json_nullable_string(sandbox, "toolboxProxyUrl") {
    Some(url) if url.length() > 0 => url
    _ =>
      match
        api_get("/sandbox/" + url_encode(sandbox_id) + "/toolbox-proxy-url") {
        Ok(response) =>
          match json_nullable_string(response, "url") {
            Some(url) if url.length() > 0 => url
            _ => return Err("sandbox has no toolbox proxy URL")
          }
        Err(error) => return Err(error)
      }
  }
  let command = if command_args.length() == 1 {
    command_args[0]
  } else {
    let quoted : Array[String] = []
    for argument in command_args {
      quoted.push(shell_quote(argument))
    }
    quoted.join(" ")
  }
  let cwd = if arg_changed(parsed, "cwd") {
    Some(arg_value(parsed, "cwd"))
  } else {
    None
  }
  let timeout = if arg_changed(parsed, "timeout") {
    Some(arg_int(parsed, "timeout", 0))
  } else {
    None
  }
  let response = match
    toolbox_execute(proxy_url, sandbox_id, command, cwd, timeout) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let result = match json_string(response, "result") {
    Some(text) => text
    None => ""
  }
  if result.length() > 0 {
    @stdio.stdout.write(result)
  }
  let exit_code = match json_get(response, "exitCode") {
    Some(Number(code, ..)) => code.to_int()
    _ => 0
  }
  if exit_code != 0 {
    if result.length() == 0 {
      err("Command failed with exit code \{exit_code}")
    }
    exit_with(exit_code)
  }
  Ok(())
}

///|
/// `daytona preview-url`.
pub async fn cmd_sandbox_preview_url(
  args : Array[String],
) -> Result[Unit, String] {
  let specs = [vflag("port", "p"), vflag("expires", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Get a signed preview URL for a sandbox port")
    out("")
    out(
      "Usage: daytona preview-url [SANDBOX_ID | SANDBOX_NAME] --port PORT [flags]",
    )
    out("")
    out("Flags:")
    out(
      "  -p, --port int      Port number to get the preview URL for (required)",
    )
    out("      --expires int   URL expiration time in seconds (default 3600)")
    return Ok(())
  }
  match
    require_positionals(
      parsed, 1, "daytona preview-url [SANDBOX_ID | SANDBOX_NAME] --port PORT",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if !arg_changed(parsed, "port") || arg_int(parsed, "port", 0) == 0 {
    return Err("port flag is required")
  }
  let port = arg_int(parsed, "port", 0)
  let expires = arg_int(parsed, "expires", 3600)
  let reference = parsed.positionals[0]
  let preview = match
    api_get(
      "/sandbox/" +
      url_encode(reference) +
      "/ports/" +
      port.to_string() +
      "/preview-url?expiresInSeconds=" +
      expires.to_string(),
    ) {
    Ok(preview) => preview
    Err(error) => return Err(error)
  }
  out(json_string_or_empty(preview, "url"))
  Ok(())
}
