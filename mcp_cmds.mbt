///|
/// The Daytona MCP server and its agent-configuration helpers.

///|
/// JSON-RPC and MCP helpers.

///|
/// Build a JSON schema property.
fn schema_string(description : String) -> Json {
  json_obj([
    ("type", Json::string("string")),
    ("description", Json::string(description)),
  ])
}

///|
/// Build a JSON schema property for a number.
fn schema_number(description : String) -> Json {
  json_obj([
    ("type", Json::string("number")),
    ("description", Json::string(description)),
  ])
}

///|
/// Build a JSON schema property for a boolean.
fn schema_bool(description : String) -> Json {
  json_obj([
    ("type", Json::string("boolean")),
    ("description", Json::string(description)),
  ])
}

///|
/// Build an object schema.
fn schema_object(
  properties : Array[(String, Json)],
  required : Array[String],
) -> Json {
  let fields : Map[String, Json] = Map([])
  for pair in properties {
    fields.set(pair.0, pair.1)
  }
  let required_values : Array[Json] = []
  for name in required {
    required_values.push(Json::string(name))
  }
  json_obj([
    ("type", Json::string("object")),
    ("properties", Json::object(fields)),
    ("required", Json::array(required_values)),
  ])
}

///|
/// Build one MCP tool definition.
fn tool_definition(
  name : String,
  description : String,
  properties : Array[(String, Json)],
  required : Array[String],
) -> Json {
  json_obj([
    ("name", Json::string(name)),
    ("description", Json::string(description)),
    ("inputSchema", schema_object(properties, required)),
  ])
}

///|
/// The tool list advertised by the server.
fn mcp_tools() -> Array[Json] {
  [
    tool_definition(
      "create_sandbox",
      "Create a new Daytona sandbox.",
      [
        (
          "id",
          schema_string(
            "Existing running sandbox ID to reuse; leave empty to create a new sandbox.",
          ),
        ),
        ("name", schema_string("Optional name for the sandbox.")),
        ("snapshot", schema_string("Snapshot to use for the sandbox.")),
        ("target", schema_string("Target region.")),
        ("user", schema_string("User associated with the sandbox.")),
        ("cpu", schema_number("CPU cores.")),
        ("gpu", schema_number("GPU units.")),
        ("memory", schema_number("Memory in MB.")),
        ("disk", schema_number("Disk space in GB.")),
        ("public", schema_bool("Make the sandbox publicly accessible.")),
        ("autoStopInterval", schema_number("Auto-stop interval in minutes.")),
        ("autoPauseInterval", schema_number("Auto-pause interval in minutes.")),
        ("ttlMinutes", schema_number("Maximum time to live in minutes.")),
        ("queueTimeout", schema_number("Runner assignment timeout in minutes.")),
        (
          "volumes",
          json_obj([
            ("type", Json::string("array")),
            ("description", Json::string("Volumes to attach.")),
          ]),
        ),
        (
          "buildInfo",
          json_obj([
            ("type", Json::string("object")),
            ("description", Json::string("Dockerfile build information.")),
          ]),
        ),
        ("networkBlockAll", schema_bool("Block all network access.")),
        ("kvm", schema_bool("Expose KVM inside the sandbox.")),
        ("networkAllowList", schema_string("Allowed IPv4 CIDR list.")),
        ("domainAllowList", schema_string("Allowed domain list.")),
        (
          "autoArchiveInterval",
          schema_number("Auto-archive interval in minutes."),
        ),
        (
          "autoDeleteInterval",
          schema_number("Auto-delete interval in minutes."),
        ),
        (
          "env",
          json_obj([
            ("type", Json::string("object")),
            ("description", Json::string("Environment variables.")),
          ]),
        ),
        (
          "labels",
          json_obj([
            ("type", Json::string("object")),
            ("description", Json::string("Sandbox labels.")),
          ]),
        ),
      ],
      [],
    ),
    tool_definition(
      "destroy_sandbox",
      "Destroy a Daytona sandbox.",
      [("id", schema_string("ID of the sandbox to destroy."))],
      ["id"],
    ),
    tool_definition("list_sandboxes", "List Daytona sandboxes.", [], []),
    tool_definition(
      "execute_command",
      "Execute a command in a running Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("command", schema_string("Command to execute.")),
        ("cwd", schema_string("Working directory.")),
        ("timeout", schema_number("Timeout in seconds.")),
      ],
      ["id", "command"],
    ),
    tool_definition(
      "preview_link",
      "Get a signed preview URL for a port in a sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("port", schema_number("Port number.")),
        ("expiresInSeconds", schema_number("URL expiration in seconds.")),
      ],
      ["id", "port"],
    ),
    tool_definition(
      "list_files",
      "List files in a directory in the Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        (
          "path",
          schema_string("Directory path (defaults to the current directory)."),
        ),
      ],
      ["id"],
    ),
    tool_definition(
      "get_file_info",
      "Get information about a file in the Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("filePath", schema_string("Path to the file.")),
      ],
      ["id", "filePath"],
    ),
    tool_definition(
      "create_folder",
      "Create a folder in the Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("folderPath", schema_string("Path of the folder to create.")),
      ],
      ["id", "folderPath"],
    ),
    tool_definition(
      "delete_file",
      "Delete a file or directory in the Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("filePath", schema_string("Path to delete.")),
        ("recursive", schema_bool("Delete directories recursively.")),
      ],
      ["id", "filePath"],
    ),
    tool_definition(
      "move_file",
      "Move or rename a file in the Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("source", schema_string("Source path.")),
        ("destination", schema_string("Destination path.")),
      ],
      ["id", "source", "destination"],
    ),
    tool_definition(
      "git_clone",
      "Clone a Git repository into the Daytona sandbox.",
      [
        ("id", schema_string("ID of the sandbox.")),
        ("url", schema_string("Repository URL.")),
        ("path", schema_string("Directory to clone into.")),
        ("branch", schema_string("Branch to clone.")),
        ("commitId", schema_string("Commit ID to clone.")),
        ("username", schema_string("Username for authentication.")),
        ("password", schema_string("Password for authentication.")),
      ],
      ["id", "url"],
    ),
  ]
}

///|
/// Extract a string argument.
fn mcp_arg_string(arguments : Json, name : String) -> String? {
  match json_get(arguments, name) {
    Some(String(value)) if value.length() > 0 => Some(value)
    _ => None
  }
}

///|
/// Extract a number argument.
fn mcp_arg_number(arguments : Json, name : String) -> Double? {
  match json_get(arguments, name) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
/// Extract a boolean argument.
fn mcp_arg_bool(arguments : Json, name : String) -> Bool? {
  match json_get(arguments, name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// Wrap text in an MCP tool result.
fn mcp_text_result(text : String, is_error : Bool) -> Json {
  json_obj([
    (
      "content",
      Json::array([
        json_obj([("type", Json::string("text")), ("text", Json::string(text))]),
      ]),
    ),
    ("isError", Json::boolean(is_error)),
  ])
}

///|
/// Build a JSON-RPC success response.
fn rpc_result(id : Json, result : Json) -> Json {
  json_obj([("jsonrpc", Json::string("2.0")), ("id", id), ("result", result)])
}

///|
/// Build a JSON-RPC error response.
fn rpc_error(id : Json, code : Int32, message : String) -> Json {
  json_obj([
    ("jsonrpc", Json::string("2.0")),
    ("id", id),
    (
      "error",
      json_obj([
        ("code", Json::number(code.to_double())),
        ("message", Json::string(message)),
      ]),
    ),
  ])
}

///|
/// Resolve a sandbox by ID, preferring the toolbox proxy URL when present.
async fn mcp_sandbox(id : String) -> Result[Json, String] {
  let sandbox = match api_get(sandbox_path(id)) {
    Ok(sandbox) => sandbox
    Err(error) => return Err(error)
  }
  match json_nullable_string(sandbox, "toolboxProxyUrl") {
    Some(url) if url.length() > 0 => Ok(sandbox)
    _ =>
      match api_get("/sandbox/" + url_encode(id) + "/toolbox-proxy-url") {
        Ok(response) => {
          let url = json_string_or_empty(response, "url")
          if url == "" {
            Ok(sandbox)
          } else {
            Ok(with_field(sandbox, "toolboxProxyUrl", Json::string(url)))
          }
        }
        Err(_) => Ok(sandbox)
      }
  }
}

///|
/// The toolbox URL for a sandbox JSON object.
fn mcp_proxy(sandbox : Json) -> Result[String, String] {
  match json_nullable_string(sandbox, "toolboxProxyUrl") {
    Some(url) if url.length() > 0 => Ok(url)
    _ => Err("sandbox has no toolbox proxy URL")
  }
}

///|
/// Execute one MCP tool call.
async fn mcp_call_tool(name : String, arguments : Json) -> Json {
  if name == "list_sandboxes" {
    return match api_get("/sandbox?limit=100") {
      Ok(response) => mcp_text_result(response.stringify(indent=2), false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "create_sandbox" {
    if mcp_arg_string(arguments, "id") is Some(existing) {
      return match api_get(sandbox_path(existing)) {
        Ok(sandbox) =>
          if sandbox_state(sandbox) == "started" {
            mcp_text_result("Reusing existing sandbox \{existing}", false)
          } else {
            mcp_text_result(
              "sandbox \{existing} not found or not running",
              true,
            )
          }
        Err(_) =>
          mcp_text_result("sandbox \{existing} not found or not running", true)
      }
    }
    let mut body = json_obj([])
    for
      pair in [
        ("name", "name"),
        ("snapshot", "snapshot"),
        ("target", "target"),
        ("user", "user"),
        ("networkAllowList", "networkAllowList"),
        ("domainAllowList", "domainAllowList"),
      ] {
      let (argument, field) = pair
      match mcp_arg_string(arguments, argument) {
        Some(value) => body = with_field(body, field, Json::string(value))
        None => ()
      }
    }
    for
      pair in [
        ("cpu", "cpu"),
        ("gpu", "gpu"),
        ("memory", "memory"),
        ("disk", "disk"),
        ("autoStopInterval", "autoStopInterval"),
        ("autoPauseInterval", "autoPauseInterval"),
        ("autoArchiveInterval", "autoArchiveInterval"),
        ("autoDeleteInterval", "autoDeleteInterval"),
        ("ttlMinutes", "ttlMinutes"),
        ("queueTimeout", "queueTimeout"),
      ] {
      let (argument, field) = pair
      match mcp_arg_number(arguments, argument) {
        Some(value) => body = with_field(body, field, Json::number(value))
        None => ()
      }
    }
    for
      pair in [
        ("public", "public"),
        ("networkBlockAll", "networkBlockAll"),
        ("kvm", "kvm"),
      ] {
      let (argument, field) = pair
      match mcp_arg_bool(arguments, argument) {
        Some(value) => body = with_field(body, field, Json::boolean(value))
        None => ()
      }
    }
    match json_get(arguments, "env") {
      Some(Object(_) as env) => body = with_field(body, "env", env)
      _ => ()
    }
    match json_get(arguments, "labels") {
      Some(Object(_) as labels) => body = with_field(body, "labels", labels)
      _ => ()
    }
    match json_get(arguments, "volumes") {
      Some(Array(_) as volumes) => body = with_field(body, "volumes", volumes)
      _ => ()
    }
    match json_get(arguments, "buildInfo") {
      Some(Object(_) as build) => body = with_field(body, "buildInfo", build)
      _ => ()
    }
    return match api_post("/sandbox", body) {
      Ok(sandbox) => mcp_text_result(sandbox.stringify(indent=2), false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "destroy_sandbox" {
    let id = match mcp_arg_string(arguments, "id") {
      Some(id) => id
      None => return mcp_text_result("id parameter is required", true)
    }
    return match api_delete(sandbox_path(id)) {
      Ok(_) => mcp_text_result("Sandbox \{id} destroyed", false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  let id = match mcp_arg_string(arguments, "id") {
    Some(id) => id
    None => return mcp_text_result("id parameter is required", true)
  }
  if name == "execute_command" {
    let command = match mcp_arg_string(arguments, "command") {
      Some(command) => command
      None => return mcp_text_result("command parameter is required", true)
    }
    let sandbox = match mcp_sandbox(id) {
      Ok(sandbox) => sandbox
      Err(error) => return mcp_text_result(error, true)
    }
    let proxy = match mcp_proxy(sandbox) {
      Ok(proxy) => proxy
      Err(error) => return mcp_text_result(error, true)
    }
    let timeout = match mcp_arg_number(arguments, "timeout") {
      Some(value) => Some(value.to_int())
      None => None
    }
    return match
      toolbox_execute(
        proxy,
        id,
        command,
        mcp_arg_string(arguments, "cwd"),
        timeout,
      ) {
      Ok(response) => mcp_text_result(response.stringify(indent=2), false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "preview_link" {
    let port = match mcp_arg_number(arguments, "port") {
      Some(port) => port.to_int()
      None => return mcp_text_result("port parameter is required", true)
    }
    let expires = match mcp_arg_number(arguments, "expiresInSeconds") {
      Some(value) => value.to_int()
      None => 3600
    }
    return match
      api_get(
        "/sandbox/" +
        url_encode(id) +
        "/ports/" +
        port.to_string() +
        "/preview-url?expiresInSeconds=" +
        expires.to_string(),
      ) {
      Ok(response) => mcp_text_result(response.stringify(indent=2), false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  // The remaining tools use the toolbox file and git APIs.
  let sandbox = match mcp_sandbox(id) {
    Ok(sandbox) => sandbox
    Err(error) => return mcp_text_result(error, true)
  }
  let proxy = match mcp_proxy(sandbox) {
    Ok(proxy) => proxy
    Err(error) => return mcp_text_result(error, true)
  }
  if name == "list_files" {
    let path = match mcp_arg_string(arguments, "path") {
      Some(path) => path
      None => "."
    }
    return match
      toolbox_request(
        @http.RequestMethod::Get,
        proxy,
        id,
        "/files",
        "?path=" + url_encode(path),
        None,
      ) {
      Ok(response) => mcp_text_result(response.stringify(indent=2), false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "get_file_info" {
    let path = match mcp_arg_string(arguments, "filePath") {
      Some(path) => path
      None => return mcp_text_result("filePath parameter is required", true)
    }
    return match
      toolbox_request(
        @http.RequestMethod::Get,
        proxy,
        id,
        "/files/info",
        "?path=" + url_encode(path),
        None,
      ) {
      Ok(response) => mcp_text_result(response.stringify(indent=2), false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "create_folder" {
    let path = match mcp_arg_string(arguments, "folderPath") {
      Some(path) => path
      None => return mcp_text_result("folderPath parameter is required", true)
    }
    let body = json_obj([("path", Json::string(path))])
    return match
      toolbox_request(
        @http.RequestMethod::Post,
        proxy,
        id,
        "/files/folder",
        "",
        Some(body),
      ) {
      Ok(_) => mcp_text_result("Created folder: \{path}", false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "delete_file" {
    let path = match mcp_arg_string(arguments, "filePath") {
      Some(path) => path
      None => return mcp_text_result("filePath parameter is required", true)
    }
    let recursive = match mcp_arg_bool(arguments, "recursive") {
      Some(value) => value
      None => false
    }
    return match
      toolbox_request(
        @http.RequestMethod::Delete,
        proxy,
        id,
        "/files",
        "?path=" +
        url_encode(path) +
        "&recursive=" +
        (if recursive { "true" } else { "false" }),
        None,
      ) {
      Ok(_) => mcp_text_result("Deleted: \{path}", false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "move_file" {
    let source = match mcp_arg_string(arguments, "source") {
      Some(source) => source
      None => return mcp_text_result("source parameter is required", true)
    }
    let destination = match mcp_arg_string(arguments, "destination") {
      Some(destination) => destination
      None => return mcp_text_result("destination parameter is required", true)
    }
    let body = json_obj([
      ("source", Json::string(source)),
      ("destination", Json::string(destination)),
    ])
    return match
      toolbox_request(
        @http.RequestMethod::Post,
        proxy,
        id,
        "/files/move",
        "",
        Some(body),
      ) {
      Ok(_) => mcp_text_result("Moved \{source} to \{destination}", false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  if name == "git_clone" {
    let url = match mcp_arg_string(arguments, "url") {
      Some(url) => url
      None => return mcp_text_result("url parameter is required", true)
    }
    let mut body = json_obj([("url", Json::string(url))])
    for
      pair in [
        ("path", "path"),
        ("branch", "branch"),
        ("commitId", "commitId"),
        ("username", "username"),
        ("password", "password"),
      ] {
      let (argument, field) = pair
      match mcp_arg_string(arguments, argument) {
        Some(value) => body = with_field(body, field, Json::string(value))
        None => ()
      }
    }
    return match
      toolbox_request(
        @http.RequestMethod::Post,
        proxy,
        id,
        "/git/clone",
        "",
        Some(body),
      ) {
      Ok(_) => mcp_text_result("Cloned repository: \{url}", false)
      Err(error) => mcp_text_result(error, true)
    }
  }
  mcp_text_result("unknown tool: \{name}", true)
}

///|
/// Dispatch `daytona mcp ...`.
pub async fn run_mcp(args : Array[String]) -> Result[Unit, String] {
  if args.length() == 0 || args[0] == "--help" || args[0] == "-h" {
    print_mcp_help()
    return Ok(())
  }
  let command = args[0]
  let rest : Array[String] = []
  for index in 1..<args.length() {
    rest.push(args[index])
  }
  if command == "config" {
    return mcp_config(rest)
  }
  if command == "init" {
    return mcp_init(rest)
  }
  if command == "start" {
    return mcp_start(rest)
  }
  Err("unknown command \"\{command}\" for \"daytona mcp\"")
}

///|
/// MCP group help.
async fn print_mcp_help() -> Unit {
  print_group_help("mcp", "Commands for managing Daytona MCP Server", [
    ("config", "Outputs JSON configuration for Daytona MCP Server"),
    ("init", "Initialize Daytona MCP Server with an agent"),
    ("start", "Start Daytona MCP Server"),
  ])
}

///|
/// The MCP log file path used in agent configurations.
fn mcp_log_path() -> String {
  let home = home_directory()
  if platform() == 2 {
    match @env.get_env_var("APPDATA") {
      Some(appdata) => appdata + "\\.daytona\\daytona-mcp.log"
      None => home + "\\.daytona\\daytona-mcp.log"
    }
  } else {
    home + "/.daytona/daytona-mcp.log"
  }
}

///|
/// The MCP server entry written into agent configs.
fn mcp_server_config() -> Json {
  let home = absolute_home()
  json_obj([
    ("command", Json::string("daytona")),
    ("args", json_obj_array_strings(["mcp", "start"])),
    (
      "env",
      json_obj([
        (
          "PATH",
          Json::string(
            home +
            ":/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
          ),
        ),
        ("HOME", Json::string(home)),
      ]),
    ),
    ("logFile", Json::string(mcp_log_path())),
  ])
}

///|
/// Absolute home path, failing back to the raw HOME value.
fn absolute_home() -> String {
  home_directory()
}

///|
/// Build a JSON array from strings.
fn json_obj_array_strings(values : Array[String]) -> Json {
  let items : Array[Json] = []
  for value in values {
    items.push(Json::string(value))
  }
  Json::array(items)
}

///|
/// `daytona mcp config`.
async fn mcp_config(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Outputs JSON configuration for Daytona MCP Server")
    out("")
    out("Usage: daytona mcp config")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona mcp config") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let config = json_obj([("daytona-mcp", mcp_server_config())])
  out(config.stringify(indent=2))
  Ok(())
}

///|
/// Agent configuration paths (config file, log file).
fn agent_paths(agent : String) -> Result[(String, String), String] {
  let home = home_directory()
  let windows = platform() == 2
  let mac = platform() == 1
  if agent == "claude" {
    if windows {
      let appdata = match @env.get_env_var("APPDATA") {
        Some(value) => value
        None => return Err("could not resolve APPDATA environment variable")
      }
      Ok(
        (
          appdata + "\\Claude\\claude_desktop_config.json",
          appdata + "\\Claude\\Logs\\daytona-mcp-server.log",
        ),
      )
    } else if mac {
      Ok(
        (
          home +
          "/Library/Application Support/Claude/claude_desktop_config.json",
          home + "/Library/Logs/Claude/daytona-mcp-server.log",
        ),
      )
    } else {
      Ok(
        (
          home + "/.config/Claude/claude_desktop_config.json",
          "/var/log/Claude/daytona-mcp-server.log",
        ),
      )
    }
  } else if agent == "cursor" {
    if windows {
      let appdata = match @env.get_env_var("APPDATA") {
        Some(value) => value
        None => return Err("could not resolve APPDATA environment variable")
      }
      Ok(
        (
          appdata + "\\.cursor\\mcp.json",
          appdata + "\\Cursor\\Logs\\daytona-mcp-server.log",
        ),
      )
    } else if mac {
      Ok(
        (
          home + "/.cursor/mcp.json",
          home + "/Library/Logs/Cursor/daytona-mcp-server.log",
        ),
      )
    } else {
      Ok((home + "/.cursor/mcp.json", "/var/log/Cursor/daytona-mcp-server.log"))
    }
  } else if agent == "windsurf" {
    if windows {
      let appdata = match @env.get_env_var("APPDATA") {
        Some(value) => value
        None => return Err("could not resolve APPDATA environment variable")
      }
      Ok(
        (
          appdata + "\\.codeium\\windsurf\\mcp_config.json",
          appdata + "\\Windsurf\\Logs\\daytona-mcp-server.log",
        ),
      )
    } else if mac {
      Ok(
        (
          home + "/.codeium/windsurf/mcp_config.json",
          home + "/Library/Logs/Windsurf/daytona-mcp-server.log",
        ),
      )
    } else {
      Ok(
        (
          home + "/.codeium/windsurf/mcp_config.json",
          "/var/log/Windsurf/daytona-mcp-server.log",
        ),
      )
    }
  } else {
    Err("agent name \{agent} is not supported")
  }
}

///|
/// `daytona mcp init AGENT`.
async fn mcp_init(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out(
      "Initialize Daytona MCP Server with an agent (claude, windsurf, cursor)",
    )
    out("")
    out("Usage: daytona mcp init [AGENT_NAME]")
    return Ok(())
  }
  match require_min_positionals(parsed, 1, "daytona mcp init [AGENT_NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let agent = parsed.positionals[0]
  let (config_path, log_path) = match agent_paths(agent) {
    Ok(paths) => paths
    Err(error) => return Err(error)
  }
  let existing = (@fs.read_file(config_path) catch { _ => "" }).text() catch {
    _ => ""
  }
  let mut root = if existing.trim() == "" {
    json_obj([])
  } else {
    let parsed = @json.parse(existing) catch {
      error => return Err("could not parse \{config_path}: \{error}")
    }
    match parsed {
      Object(_) => parsed
      _ => json_obj([])
    }
  }
  let servers : Map[String, Json] = Map([])
  match json_get(root, "mcpServers") {
    Some(Object(existing_servers)) =>
      for pair in existing_servers {
        servers.set(pair.0, pair.1)
      }
    _ => ()
  }
  let mut server = mcp_server_config()
  server = with_field(server, "logFile", Json::string(log_path))
  servers.set("daytona-mcp", server)
  root = with_field(root, "mcpServers", Json::object(servers))
  match parent_directory(config_path) {
    Some(parent) =>
      @fs.mkdir(parent, recursive=true, allow_exist=true) catch {
        _ => ()
      }
    None => ()
  }
  @fs.write_file(
    config_path,
    root.stringify(indent=4),
    permission=0o644,
    create_mode=CreateOrTruncate,
  ) catch {
    error => return Err("failed to write \{config_path}: \{error}")
  }
  Ok(())
}

///|
/// The parent directory of a path.
fn parent_directory(path : String) -> String? {
  match path.rev_find("/") {
    Some(index) if index > 0 =>
      Some(path.exact_view(start=0, end=index).to_owned())
    _ =>
      match path.rev_find("\\") {
        Some(index) if index > 1 =>
          Some(path.exact_view(start=0, end=index).to_owned())
        _ => None
      }
  }
}

///|
/// `daytona mcp start`: a stdio JSON-RPC server.
async fn mcp_start(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Start Daytona MCP Server")
    out("")
    out("Usage: daytona mcp start")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona mcp start") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  while true {
    let line = @stdio.stdin.read_until("\n") catch { _ => None }
    let raw = match line {
      Some(line) => line
      None => break
    }
    let text = raw.trim().to_owned()
    if text == "" {
      continue
    }
    let request = @json.parse(text) catch { _ => continue }
    let id = json_get(request, "id")
    let rpc_method = match json_string(request, "method") {
      Some(rpc_method) => rpc_method
      None => {
        if id is Some(id_value) {
          @stdio.stdout.write(
            rpc_error(id_value, -32600, "invalid request").stringify() + "\n",
          )
        }
        continue
      }
    }
    let mut response : Json? = None
    if rpc_method == "initialize" {
      match id {
        Some(id_value) =>
          response = Some(
            rpc_result(
              id_value,
              json_obj([
                ("protocolVersion", Json::string("2025-03-11")),
                ("capabilities", json_obj([("tools", json_obj([]))])),
                (
                  "serverInfo",
                  json_obj([
                    ("name", Json::string("daytona")),
                    ("version", Json::string("0.1.0")),
                  ]),
                ),
              ]),
            ),
          )
        None => ()
      }
    } else if rpc_method == "notifications/initialized" ||
      rpc_method == "notifications/cancelled" {
      response = None
    } else if rpc_method == "ping" {
      match id {
        Some(id_value) => response = Some(rpc_result(id_value, json_obj([])))
        None => ()
      }
    } else if rpc_method == "tools/list" {
      match id {
        Some(id_value) =>
          response = Some(
            rpc_result(
              id_value,
              json_obj([("tools", Json::array(mcp_tools()))]),
            ),
          )
        None => ()
      }
    } else if rpc_method == "tools/call" {
      let params = match json_get(request, "params") {
        Some(params) => params
        None => Json::null()
      }
      let name = json_string_or_empty(params, "name")
      let arguments = match json_get(params, "arguments") {
        Some(arguments) => arguments
        None => json_obj([])
      }
      let result = mcp_call_tool(name, arguments)
      match id {
        Some(id_value) => response = Some(rpc_result(id_value, result))
        None => ()
      }
    } else {
      match id {
        Some(id_value) =>
          response = Some(
            rpc_error(id_value, -32601, "method not found: " + rpc_method),
          )
        None => ()
      }
    }
    match response {
      Some(response) => @stdio.stdout.write(response.stringify() + "\n")
      None => ()
    }
  }
  Ok(())
}
