///|
/// Top-level command dispatch, mirroring the Cobra command tree of the Go CLI.

///|
/// The CLI version reported by `daytona version`.
pub fn cli_version() -> String {
  "v0.1.0"
}

///|
/// Whether a command word matches any of its aliases.
fn matches(command : String, names : Array[String]) -> Bool {
  names.contains(command)
}

///|
/// Print the root help screen.
pub async fn print_root_help() -> Unit {
  out("Command line interface for Daytona Sandboxes")
  out("")
  out("Usage:")
  out("  daytona [command]")
  out("")
  out("Available Commands:")
  out("  archive       Archive a sandbox")
  out("  autocomplete  Adds a completion script for your shell environment")
  out("  create        Create a new sandbox")
  out("  delete        Delete a sandbox")
  out("  docs          Opens the Daytona documentation in your default browser")
  out("  exec          Execute a command in a sandbox")
  out("  help          Help about any command")
  out("  info          Get sandbox information")
  out("  list          List sandboxes")
  out("  login         Log in to Daytona")
  out("  logout        Logout from Daytona")
  out("  mcp           Manage Daytona MCP Server")
  out("  organization  Manage Daytona organizations")
  out("  pause         Pause a sandbox")
  out("  preview-url   Get signed preview URL for a sandbox port")
  out("  snapshot      Manage Daytona snapshots")
  out("  ssh           SSH into a sandbox")
  out("  start         Start a sandbox")
  out("  stop          Stop a sandbox")
  out("  version       Print the version number")
  out("  volume        Manage Daytona volumes")
  out("")
  out("Flags:")
  out("  -h, --help      help for daytona")
  out("  -v, --version   Display the version of Daytona")
  out("")
  out("Use \"daytona [command] --help\" for more information about a command.")
}

///|
/// Print the help screen for a group command.
pub async fn print_group_help(
  name : String,
  description : String,
  commands : Array[(String, String)],
) -> Unit {
  out(description)
  out("")
  out("Usage:")
  out("  daytona \{name} [command]")
  out("")
  out("Available Commands:")
  for command in commands {
    out("  " + pad_right(command.0, 14) + command.1)
  }
  out("")
  out("Flags:")
  out("  -h, --help   help for \{name}")
  out("")
  out(
    "Use \"daytona \{name} [command] --help\" for more information about a command.",
  )
}

///|
/// Dispatch `daytona snapshot ...`.
async fn run_snapshot(args : Array[String]) -> Result[Unit, String] {
  if args.length() == 0 || args[0] == "--help" || args[0] == "-h" {
    print_group_help("snapshot", "Manage Daytona snapshots", [
      ("activate", "Activate a snapshot"),
      ("create", "Create a snapshot"),
      ("delete", "Delete a snapshot"),
      ("list", "List all snapshots"),
      ("push", "Push a local Docker image to Daytona"),
    ])
    return Ok(())
  }
  let command = args[0]
  let rest : Array[String] = []
  for index in 1..<args.length() {
    rest.push(args[index])
  }
  if matches(command, ["list", "ls"]) {
    return cmd_snapshot_list(rest)
  }
  if matches(command, ["create", "add", "new"]) {
    return cmd_snapshot_create(rest)
  }
  if matches(command, ["delete", "remove", "rm"]) {
    return cmd_snapshot_delete(rest)
  }
  if command == "activate" {
    return cmd_snapshot_activate(rest)
  }
  if command == "push" {
    return cmd_snapshot_push(rest)
  }
  Err("unknown command \"\{command}\" for \"daytona snapshot\"")
}

///|
/// Dispatch `daytona volume ...`.
async fn run_volume(args : Array[String]) -> Result[Unit, String] {
  if args.length() == 0 || args[0] == "--help" || args[0] == "-h" {
    print_group_help("volume", "Manage Daytona volumes", [
      ("create", "Create a volume"),
      ("delete", "Delete a volume"),
      ("get", "Get volume details"),
      ("list", "List all volumes"),
      ("resolve", "Resolve a volume name to its ID"),
    ])
    return Ok(())
  }
  let command = args[0]
  let rest : Array[String] = []
  for index in 1..<args.length() {
    rest.push(args[index])
  }
  if matches(command, ["list", "ls"]) {
    return cmd_volume_list(rest)
  }
  if matches(command, ["create", "add", "new"]) {
    return cmd_volume_create(rest)
  }
  if matches(command, ["get", "info", "view", "inspect"]) {
    return cmd_volume_get(rest)
  }
  if matches(command, ["delete", "remove", "rm"]) {
    return cmd_volume_delete(rest)
  }
  if command == "resolve" {
    return cmd_volume_resolve(rest)
  }
  Err("unknown command \"\{command}\" for \"daytona volume\"")
}

///|
/// Dispatch `daytona organization ...`.
async fn run_organization(args : Array[String]) -> Result[Unit, String] {
  if args.length() == 0 || args[0] == "--help" || args[0] == "-h" {
    print_group_help("organization", "Manage Daytona organizations", [
      ("create", "Create a new organization and set it as active"),
      ("delete", "Delete an organization"),
      ("list", "List all organizations"),
      ("members", "List members of an organization"),
      ("use", "Set active organization"),
    ])
    return Ok(())
  }
  let command = args[0]
  let rest : Array[String] = []
  for index in 1..<args.length() {
    rest.push(args[index])
  }
  if matches(command, ["list", "ls"]) {
    return cmd_organization_list(rest)
  }
  if matches(command, ["create", "add", "new"]) {
    return cmd_organization_create(rest)
  }
  if matches(command, ["delete", "remove", "rm"]) {
    return cmd_organization_delete(rest)
  }
  if command == "use" {
    return cmd_organization_use(rest)
  }
  if command == "members" {
    return cmd_organization_members(rest)
  }
  Err("unknown command \"\{command}\" for \"daytona organization\"")
}

///|
/// Dispatch the hidden deprecated `daytona sandbox ...` group.
async fn run_sandbox_group(args : Array[String]) -> Result[Unit, String] {
  if args.length() == 0 || args[0] == "--help" || args[0] == "-h" {
    print_group_help("sandbox", "Commands for managing Daytona sandboxes", [
      ("archive", "Archive a sandbox"),
      ("create", "Create a new sandbox"),
      ("delete", "Delete a sandbox"),
      ("exec", "Execute a command in a sandbox"),
      ("info", "Get sandbox information"),
      ("list", "List sandboxes"),
      ("pause", "Pause a sandbox"),
      ("preview-url", "Get signed preview URL for a sandbox port"),
      ("ssh", "SSH into a sandbox"),
      ("start", "Start a sandbox"),
      ("stop", "Stop a sandbox"),
    ])
    return Ok(())
  }
  let command = args[0]
  let rest : Array[String] = []
  for index in 1..<args.length() {
    rest.push(args[index])
  }
  if matches(command, ["list", "ls"]) {
    return cmd_sandbox_list(rest)
  }
  if matches(command, ["create", "add", "new"]) {
    return cmd_sandbox_create(rest)
  }
  if matches(command, ["info", "view", "inspect"]) {
    return cmd_sandbox_info(rest)
  }
  if matches(command, ["delete", "remove", "rm"]) {
    return cmd_sandbox_delete(rest)
  }
  if command == "start" {
    return cmd_sandbox_action("start", "Started", rest)
  }
  if command == "stop" {
    return cmd_sandbox_action("stop", "Stopped", rest)
  }
  if command == "pause" {
    return cmd_sandbox_action("pause", "Paused", rest)
  }
  if command == "archive" {
    return cmd_sandbox_action("archive", "Archived", rest)
  }
  if command == "ssh" {
    return cmd_sandbox_ssh(rest)
  }
  if command == "exec" {
    return cmd_sandbox_exec(rest)
  }
  if command == "preview-url" {
    return cmd_sandbox_preview_url(rest)
  }
  Err("unknown command \"\{command}\" for \"daytona sandbox\"")
}

///|
/// Dispatch a shell completion request.
async fn run_autocomplete(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Adds a completion script for your shell environment")
    out("")
    out("Usage: daytona autocomplete [bash|zsh|fish|powershell]")
    return Ok(())
  }
  match
    require_positionals(
      parsed, 1, "daytona autocomplete [bash|zsh|fish|powershell]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let shell = parsed.positionals[0]
  match setup_autocompletion(shell) {
    Ok(profile) => {
      out("Autocomplete script generated and injected successfully.")
      out(
        "Please source your \{shell} profile to apply the changes or restart your terminal.",
      )
      out("For manual sourcing, use: source \{profile}")
      if shell == "bash" {
        out(
          "Please make sure that you have bash-completion installed in order to get full autocompletion functionality.",
        )
        out(
          "On how to install bash-completion, please refer to the following link: https://www.daytona.io/docs/tools/cli/#daytona-autocomplete",
        )
      }
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// Dispatch `daytona docs`.
async fn run_docs(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Opens the Daytona documentation in your default browser.")
    out("")
    out("Usage: daytona docs")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona docs") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let url = "https://www.daytona.io/docs/"
  out(
    "Opening the Daytona documentation in your default browser. If opening fails, you can go to \{url} manually.",
  )
  open_browser(url)
}

///|
/// Run the CLI with the process arguments.
pub async fn run_cli(args : Array[String]) -> Result[Unit, String] {
  if args.length() == 0 {
    print_root_help()
    return Ok(())
  }
  let first = args[0]
  if first == "--help" || first == "-h" {
    print_root_help()
    return Ok(())
  }
  if first == "--version" || first == "-v" || first == "version" {
    out("Daytona CLI version \{cli_version()}")
    return Ok(())
  }
  if first == "help" {
    if args.length() == 1 {
      print_root_help()
      return Ok(())
    }
    let rest : Array[String] = ["--help"]
    for index in 2..<args.length() {
      rest.push(args[index])
    }
    return run_cli([args[1]] + rest)
  }
  let rest : Array[String] = []
  for index in 1..<args.length() {
    rest.push(args[index])
  }
  if matches(first, ["login"]) {
    return cmd_login(rest)
  }
  if matches(first, ["logout"]) {
    return cmd_logout(rest)
  }
  if matches(first, ["create", "add", "new"]) {
    return cmd_sandbox_create(rest)
  }
  if matches(first, ["list", "ls"]) {
    return cmd_sandbox_list(rest)
  }
  if matches(first, ["info", "view", "inspect"]) {
    return cmd_sandbox_info(rest)
  }
  if matches(first, ["delete", "remove", "rm"]) {
    return cmd_sandbox_delete(rest)
  }
  if matches(first, ["start"]) {
    return cmd_sandbox_action("start", "Started", rest)
  }
  if matches(first, ["stop"]) {
    return cmd_sandbox_action("stop", "Stopped", rest)
  }
  if matches(first, ["pause"]) {
    return cmd_sandbox_action("pause", "Paused", rest)
  }
  if matches(first, ["archive"]) {
    return cmd_sandbox_action("archive", "Archived", rest)
  }
  if matches(first, ["ssh"]) {
    return cmd_sandbox_ssh(rest)
  }
  if matches(first, ["exec"]) {
    return cmd_sandbox_exec(rest)
  }
  if matches(first, ["preview-url"]) {
    return cmd_sandbox_preview_url(rest)
  }
  if matches(first, ["sandbox", "sandboxes"]) {
    return run_sandbox_group(rest)
  }
  if matches(first, ["snapshot", "snapshots"]) {
    return run_snapshot(rest)
  }
  if matches(first, ["volume", "volumes"]) {
    return run_volume(rest)
  }
  if matches(first, ["organization", "organizations", "org", "orgs"]) {
    return run_organization(rest)
  }
  if matches(first, ["autocomplete", "completion"]) {
    return run_autocomplete(rest)
  }
  if matches(first, ["docs", "documentation", "doc"]) {
    return run_docs(rest)
  }
  if matches(first, ["mcp"]) {
    return run_mcp(rest)
  }
  Err("unknown command \"\{first}\" for \"daytona\"")
}
