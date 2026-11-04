///|
/// Snapshot commands.

///|
/// Path for one snapshot.
pub fn snapshot_path(reference : String) -> String {
  "/snapshots/" + url_encode(reference)
}

///|
/// Validate a `name:tag` image reference the way the Go CLI does.
pub fn validate_image_name(image : String) -> Result[Unit, String] {
  let parts = image.split(":").collect()
  if parts.length() != 2 {
    return Err(
      "invalid image format: must contain exactly one colon (e.g., 'ubuntu:22.04')",
    )
  }
  if parts[1] == "latest" {
    return Err("tag 'latest' not allowed, please use a specific version tag")
  }
  Ok(())
}

///|
/// Print a snapshot's build logs.
pub async fn print_snapshot_build_logs(reference : String) -> Unit {
  match
    api_get("/snapshots/" + url_encode(reference) + "/build-logs?follow=false") {
    Ok(String(text)) =>
      if text.length() > 0 {
        @stdio.stdout.write(text)
        if !text.has_suffix("\n") {
          out("")
        }
      }
    _ => ()
  }
}

///|
/// Poll a snapshot until it is active, or errors.
pub async fn await_snapshot_active(
  reference : String,
  timeout_seconds : Int32,
) -> Result[Json, String] {
  let mut elapsed = 0
  while elapsed <= timeout_seconds {
    let snapshot = match api_get(snapshot_path(reference)) {
      Ok(snapshot) => snapshot
      Err(error) => return Err(error)
    }
    let state = snapshot_state(snapshot)
    if state == "active" {
      return Ok(snapshot)
    }
    if state == "error" || state == "build_failed" || state == "removing" {
      print_snapshot_build_logs(reference)
      return Err("snapshot entered state \{snapshot_state_label(state)}")
    }
    @async.sleep(1000)
    elapsed = elapsed + 1
  }
  Err("timed out waiting for snapshot \{reference} to become active")
}

///|
/// `daytona snapshot list`.
pub async fn cmd_snapshot_list(args : Array[String]) -> Result[Unit, String] {
  let specs = [
    vflag("page", "p"),
    vflag("limit", "l"),
    vflag("source-sandbox-id", ""),
    vflag("format", ""),
  ]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("List all snapshots")
    out("")
    out("Usage: daytona snapshot list [flags]")
    out("")
    out("Flags:")
    out(
      "  -p, --page int                 Page number for pagination (default 1)",
    )
    out(
      "  -l, --limit int                Maximum number of items per page (default 100)",
    )
    out("      --source-sandbox-id string Filter by source sandbox ID")
    out("      --format string            Output format: json or yaml")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona snapshot list [flags]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let page = arg_int(parsed, "page", 1)
  let limit = arg_int(parsed, "limit", 100)
  let mut path = "/snapshots?page=\{page}&limit=\{limit}"
  if arg_changed(parsed, "source-sandbox-id") {
    path = path +
      "&sourceSandboxId=" +
      url_encode(arg_value(parsed, "source-sandbox-id"))
  }
  let response = match api_get(path) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let items = json_array(response, "items")
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(Json::array(items), format))
    return Ok(())
  }
  if items.length() == 0 {
    success("No snapshots found")
    return Ok(())
  }
  items.sort_by(fn(a, b) {
    let priority_a = snapshot_state_priority(snapshot_state(a))
    let priority_b = snapshot_state_priority(snapshot_state(b))
    if priority_a != priority_b {
      return if priority_a < priority_b { -1 } else { 1 }
    }
    let created_a = json_string_or_empty(a, "createdAt")
    let created_b = json_string_or_empty(b, "createdAt")
    if created_a > created_b {
      -1
    } else if created_a < created_b {
      1
    } else {
      0
    }
  })
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
  for snapshot in items {
    rows.push([
      json_string_or_empty(snapshot, "name"),
      snapshot_state_label(snapshot_state(snapshot)),
      snapshot_size_label(snapshot),
      created_label(snapshot, now),
    ])
  }
  out(render_table(["Snapshot", "State", "Size", "Created"], rows))
  Ok(())
}

///|
/// `daytona snapshot create`.
pub async fn cmd_snapshot_create(args : Array[String]) -> Result[Unit, String] {
  let specs = [
    vflag("entrypoint", "e"),
    vflag("image", "i"),
    vflag("dockerfile", "f"),
    lflag("context", "c"),
    vflag("cpu", ""),
    vflag("memory", ""),
    vflag("disk", ""),
    vflag("region", ""),
    vflag("sandbox-class", ""),
  ]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Create a snapshot")
    out("")
    out("Usage: daytona snapshot create [SNAPSHOT] [flags]")
    out("")
    out("Flags:")
    out("  -i, --image string        The image name for the snapshot")
    out("  -f, --dockerfile string   Path to Dockerfile to build")
    out("  -e, --entrypoint string   The entrypoint command for the snapshot")
    out(
      "      --cpu int             CPU cores allocated to underlying sandboxes",
    )
    out(
      "      --memory int          Memory in GB allocated to underlying sandboxes",
    )
    out(
      "      --disk int            Disk space in GB allocated to underlying sandboxes",
    )
    out(
      "      --region string       Region ID where the snapshot will be available",
    )
    out("      --sandbox-class string One of: container or linux-vm")
    return Ok(())
  }
  match require_positionals(parsed, 1, "daytona snapshot create [SNAPSHOT]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let name = parsed.positionals[0]
  match check_exclusive(parsed, ["image", "dockerfile"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match check_exclusive(parsed, ["image", "context"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match check_exclusive(parsed, ["entrypoint", "dockerfile"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match check_exclusive(parsed, ["entrypoint", "context"]) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let using_dockerfile = arg_changed(parsed, "dockerfile")
  let using_image = arg_value(parsed, "image") != ""
  if !using_dockerfile && !using_image {
    return Err("must specify either --dockerfile or --image")
  }
  if using_dockerfile {
    return Err(
      "Dockerfile builds are not supported by this build; use `daytona snapshot push` after building the image locally",
    )
  }
  let image = arg_value(parsed, "image")
  match validate_image_name(image) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let mut body = json_obj([
    ("name", Json::string(name)),
    ("imageName", Json::string(image)),
  ])
  let entrypoint = arg_value(parsed, "entrypoint")
  if entrypoint != "" {
    let parts = split_fields(entrypoint)
    let values : Array[Json] = []
    for part in parts {
      values.push(Json::string(part))
    }
    body = with_field(body, "entrypoint", Json::array(values))
  }
  for pair in [("cpu", "cpu"), ("memory", "memory"), ("disk", "disk")] {
    let (flag, field) = pair
    let value = arg_int(parsed, flag, 0)
    if value != 0 {
      body = with_field(body, field, Json::number(value.to_double()))
    }
  }
  let region = arg_value(parsed, "region")
  if region != "" {
    body = with_field(body, "regionId", Json::string(region))
  }
  let sandbox_class = arg_value(parsed, "sandbox-class")
  if sandbox_class != "" {
    if sandbox_class != "container" && sandbox_class != "linux-vm" {
      return Err(
        "invalid --sandbox-class \"\{sandbox_class}\": must be 'container' or 'linux-vm'",
      )
    }
    body = with_field(body, "sandboxClass", Json::string(sandbox_class))
  }
  match api_post("/snapshots", body) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match await_snapshot_active(name, 900) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  success("Snapshot \{name} successfully created")
  info(
    "Run 'daytona create --snapshot \{name}' to create a new sandbox using this snapshot",
  )
  Ok(())
}

///|
/// `daytona snapshot activate`.
pub async fn cmd_snapshot_activate(
  args : Array[String],
) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Activate a snapshot")
    out("")
    out("Usage: daytona snapshot activate [SNAPSHOT_ID | SNAPSHOT_NAME]")
    return Ok(())
  }
  match
    require_positionals(
      parsed, 1, "daytona snapshot activate [SNAPSHOT_ID | SNAPSHOT_NAME]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let reference = parsed.positionals[0]
  match api_post_empty(snapshot_path(reference) + "/activate") {
    Ok(_) => {
      success("Snapshot \{reference} activated")
      return Ok(())
    }
    Err(_) => ()
  }
  // The activate endpoint takes an ID; resolve a name through GET first.
  let snapshot = match api_get(snapshot_path(reference)) {
    Ok(snapshot) => snapshot
    Err(error) => return Err(error)
  }
  match
    api_post_empty(
      snapshot_path(json_string_or_empty(snapshot, "id")) + "/activate",
    ) {
    Ok(_) => {
      success("Snapshot \{reference} activated")
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// `daytona snapshot delete`.
pub async fn cmd_snapshot_delete(args : Array[String]) -> Result[Unit, String] {
  let specs = [bflag("all", "a")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Delete a snapshot")
    out("")
    out("Usage: daytona snapshot delete [SNAPSHOT_ID | SNAPSHOT_NAME] [flags]")
    out("")
    out("Flags:")
    out("  -a, --all   Delete all snapshots")
    return Ok(())
  }
  match
    require_max_positionals(
      parsed, 1, "daytona snapshot delete [SNAPSHOT_ID | SNAPSHOT_NAME]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if parsed.positionals.length() == 0 {
    if !arg_bool(parsed, "all") {
      out("Delete a snapshot")
      out("")
      out(
        "Usage: daytona snapshot delete [SNAPSHOT_ID | SNAPSHOT_NAME] [flags]",
      )
      return Ok(())
    }
    let all : Array[Json] = []
    let mut page = 1
    let mut done = false
    while !done {
      let response = match api_get("/snapshots?page=\{page}&limit=200") {
        Ok(response) => response
        Err(error) => return Err(error)
      }
      let items = json_array(response, "items")
      for item in items {
        all.push(item)
      }
      let total_pages = match json_get(response, "totalPages") {
        Some(Number(total, ..)) => total.to_int()
        _ => 1
      }
      if items.length() < 200 || page >= total_pages {
        done = true
      } else {
        page = page + 1
      }
    }
    if all.length() == 0 {
      success("No snapshots to delete")
      return Ok(())
    }
    let mut deleted = 0
    for item in all {
      let id = json_string_or_empty(item, "id")
      match api_delete(snapshot_path(id)) {
        Ok(_) => deleted = deleted + 1
        Err(error) => out("Failed to delete snapshot \{id}: \{error}")
      }
    }
    success("Deleted \{deleted} snapshots")
    return Ok(())
  }
  let reference = parsed.positionals[0]
  match api_delete(snapshot_path(reference)) {
    Ok(_) => {
      success("Snapshot \{reference} deleted")
      return Ok(())
    }
    Err(_) => ()
  }
  // Names are resolved through GET, which accepts both IDs and names.
  let snapshot = match api_get(snapshot_path(reference)) {
    Ok(snapshot) => snapshot
    Err(error) => return Err(error)
  }
  match api_delete(snapshot_path(json_string_or_empty(snapshot, "id"))) {
    Ok(_) => {
      success("Snapshot \{reference} deleted")
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// `daytona snapshot push`.
pub async fn cmd_snapshot_push(args : Array[String]) -> Result[Unit, String] {
  let specs = [
    vflag("name", "n"),
    vflag("entrypoint", "e"),
    vflag("cpu", ""),
    vflag("memory", ""),
    vflag("disk", ""),
    vflag("region", ""),
  ]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Push a local Docker image to Daytona")
    out("")
    out("Usage: daytona snapshot push [SNAPSHOT] --name NAME [flags]")
    out("")
    out("Flags:")
    out("  -n, --name string        Snapshot name (required)")
    out("  -e, --entrypoint string  Entrypoint command for the image")
    out(
      "      --cpu int            CPU cores allocated to underlying sandboxes",
    )
    out(
      "      --memory int         Memory in GB allocated to underlying sandboxes",
    )
    out(
      "      --disk int           Disk space in GB allocated to underlying sandboxes",
    )
    out(
      "      --region string      Region ID where the snapshot will be available",
    )
    return Ok(())
  }
  match
    require_positionals(
      parsed, 1, "daytona snapshot push [SNAPSHOT] --name NAME",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let source_image = parsed.positionals[0]
  match validate_image_name(source_image) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let name = arg_value(parsed, "name")
  if name == "" {
    return Err("name flag is required")
  }
  let architecture_result = @process.collect_output("docker", [
    "image", "inspect", "--format", "{{.Architecture}}", source_image,
  ]) catch {
    _ => return Err("failed to run docker; is Docker installed and on PATH?")
  }
  let architecture = match architecture_result {
    (0, stdout, _) => stdout.text().trim().to_owned()
    (_, _, stderr) => {
      let message = stderr.text().trim().to_owned()
      if message.contains("No such image") {
        return Err(
          "image '\{source_image}' not found locally. Please ensure the image exists and try again",
        )
      }
      return Err("failed to inspect image: \{message}")
    }
  }
  if architecture != "amd64" {
    return Err(
      "image '\{source_image}' is not compatible with AMD architecture",
    )
  }
  let mut path = "/docker-registry/registry-push-access"
  let region = arg_value(parsed, "region")
  if region != "" {
    path = path + "?regionId=" + url_encode(region)
  }
  let access = match api_get(path) {
    Ok(access) => access
    Err(error) => return Err(error)
  }
  let registry = json_string_or_empty(access, "registryUrl")
  let project = json_string_or_empty(access, "project")
  let username = json_string_or_empty(access, "username")
  let secret = json_string_or_empty(access, "secret")
  let (login_status, _, login_err) = @process.collect_output("docker", [
    "login", "-u", username, "-p", secret, registry,
  ]) catch {
    _ => return Err("failed to run docker login")
  }
  if login_status != 0 {
    return Err(
      "failed to log in to the transient registry: \{login_err.text().trim()}",
    )
  }
  let mut image_name = source_image
  match source_image.rev_find(":") {
    Some(index) =>
      image_name = source_image.exact_view(start=0, end=index).to_owned()
    None => ()
  }
  let timestamp = now_compact_timestamp()
  let target = registry + "/" + project + "/" + image_name + ":" + timestamp
  let (tag_status, _, tag_err) = @process.collect_output("docker", [
    "tag", source_image, target,
  ]) catch {
    _ => return Err("failed to run docker tag")
  }
  if tag_status != 0 {
    return Err("failed to tag image: \{tag_err.text().trim()}")
  }
  let push_status = @process.run("docker", ["push", target]) catch {
    _ => return Err("failed to run docker push")
  }
  if push_status != 0 {
    return Err("failed to push image")
  }
  let mut body = json_obj([
    ("name", Json::string(name)),
    ("imageName", Json::string(target)),
  ])
  let entrypoint = arg_value(parsed, "entrypoint")
  if entrypoint != "" {
    let values : Array[Json] = []
    for part in split_fields(entrypoint) {
      values.push(Json::string(part))
    }
    body = with_field(body, "entrypoint", Json::array(values))
  }
  for pair in [("cpu", "cpu"), ("memory", "memory"), ("disk", "disk")] {
    let (flag, field) = pair
    let value = arg_int(parsed, flag, 0)
    if value != 0 {
      body = with_field(body, field, Json::number(value.to_double()))
    }
  }
  if region != "" {
    body = with_field(body, "regionId", Json::string(region))
  }
  match api_post("/snapshots", body) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  success("Successfully pushed \{source_image} to Daytona")
  match await_snapshot_active(name, 900) {
    Ok(_) => {
      info(
        "Use 'daytona create --snapshot \{name}' to create a new sandbox using this snapshot",
      )
      Ok(())
    }
    Err(error) => Err(error)
  }
}
