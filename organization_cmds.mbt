///|
/// Organization commands.

///|
/// Update the active profile's organization.
pub async fn set_active_organization(
  organization_id : String,
) -> Result[Unit, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  if profile.id == "env" {
    return Err("environment credentials take precedence over the config file")
  }
  let updated : Profile = {
    id: profile.id,
    name: profile.name,
    url: profile.url,
    key: profile.key,
    token: profile.token,
    active_org: Some(organization_id),
  }
  match update_profile(config, updated) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match save_config(config) {
    Ok(_) => Ok(())
    Err(error) => Err(error)
  }
}

///|
/// Print a numbered prompt and return the selected index.
async fn prompt_select(
  title : String,
  labels : Array[String],
) -> Result[Int32, String] {
  out(title)
  for index in 0..<labels.length() {
    out("  \{index + 1}. \{labels[index]}")
  }
  out("")
  @stdio.stdout.write("Enter a number: ")
  let line = @stdio.stdin.read_until("\n") catch { _ => None }
  let answer = match line {
    Some(text) => text.trim().to_owned()
    None => return Err("no selection provided")
  }
  let selected = match parse_decimal(answer) {
    Some(number) => number
    None => return Err("invalid selection")
  }
  if selected < 1 || selected > labels.length() {
    return Err("invalid selection")
  }
  Ok(selected - 1)
}

///|
/// Find a region by ID or name.
pub fn resolve_region(
  regions : Array[Json],
  identifier : String,
) -> Result[Json, String] {
  for region in regions {
    if json_string_or_empty(region, "id") == identifier ||
      json_string_or_empty(region, "name") == identifier {
      return Ok(region)
    }
  }
  Err("region \"\{identifier}\" not found")
}

///|
/// `daytona organization list`.
pub async fn cmd_organization_list(
  args : Array[String],
) -> Result[Unit, String] {
  let specs = [vflag("format", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("List all organizations")
    out("")
    out("Usage: daytona organization list [flags]")
    out("")
    out("Flags:")
    out("      --format string   Output format: json or yaml")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona organization list") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let response = match api_get("/organizations") {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let items = match response {
    Array(items) => items
    _ => []
  }
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(Json::array(items), format))
    return Ok(())
  }
  if items.length() == 0 {
    success("No organizations found")
    return Ok(())
  }
  items.sort_by(fn(a, b) {
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
  let active_id = match active_organization(config) {
    Ok(id) => id
    Err(_) => ""
  }
  let now = @env.now().reinterpret_as_int64()
  let rows : Array[Array[String]] = []
  for organization in items {
    let id = json_string_or_empty(organization, "id")
    let name = json_string_or_empty(organization, "name")
    rows.push([
      (if id == active_id { "*" } else { "" }) + name,
      id,
      created_label(organization, now),
    ])
  }
  out(render_table(["Name", "Id", "Created"], rows))
  Ok(())
}

///|
/// `daytona organization create`.
pub async fn cmd_organization_create(
  args : Array[String],
) -> Result[Unit, String] {
  let specs = [vflag("region", "r")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Create a new organization and set it as active")
    out("")
    out("Usage: daytona organization create [ORGANIZATION_NAME] [flags]")
    out("")
    out("Flags:")
    out(
      "  -r, --region string   Default region (id or name) for the organization",
    )
    return Ok(())
  }
  match
    require_positionals(
      parsed, 1, "daytona organization create [ORGANIZATION_NAME]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let name = parsed.positionals[0]
  let regions_response = match api_get("/shared-regions") {
    Ok(regions) => regions
    Err(error) => return Err(error)
  }
  let regions = match regions_response {
    Array(items) => items
    _ => []
  }
  let region = if arg_changed(parsed, "region") {
    match resolve_region(regions, arg_value(parsed, "region")) {
      Ok(region) => region
      Err(error) => return Err(error)
    }
  } else if regions.length() == 0 {
    return Err("no shared regions available; contact your administrator")
  } else if regions.length() == 1 {
    regions[0]
  } else {
    let labels : Array[String] = []
    for item in regions {
      labels.push(json_string_or_empty(item, "name"))
    }
    let selected = match prompt_select("Choose a Region", labels) {
      Ok(selected) => selected
      Err(error) => return Err(error)
    }
    regions[selected]
  }
  let body = json_obj([
    ("name", Json::string(name)),
    ("defaultRegionId", Json::string(json_string_or_empty(region, "id"))),
  ])
  let organization = match api_post("/organizations", body) {
    Ok(organization) => organization
    Err(error) => return Err(error)
  }
  match set_active_organization(json_string_or_empty(organization, "id")) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  out(render_info("", organization_info_fields(organization)))
  success(
    "Your organization has been created and its approval is pending\nOur team has been notified and will set up your resource quotas shortly",
  )
  Ok(())
}

///|
/// Find an organization by ID or name.
pub fn find_organization(
  organizations : Array[Json],
  reference : String,
) -> Json? {
  for organization in organizations {
    if json_string_or_empty(organization, "id") == reference ||
      json_string_or_empty(organization, "name") == reference {
      return Some(organization)
    }
  }
  None
}

///|
/// Fetch the organization list, or fail.
async fn list_organizations() -> Result[Array[Json], String] {
  match api_get("/organizations") {
    Ok(Array(items)) => Ok(items)
    Ok(_) => Err("unexpected response while listing organizations")
    Err(error) => Err(error)
  }
}

///|
/// `daytona organization use`.
pub async fn cmd_organization_use(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Set the active organization")
    out("")
    out("Usage: daytona organization use [ORGANIZATION]")
    return Ok(())
  }
  match
    require_max_positionals(
      parsed, 1, "daytona organization use [ORGANIZATION]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let organizations = match list_organizations() {
    Ok(organizations) => organizations
    Err(error) => return Err(error)
  }
  if organizations.length() == 0 {
    success("No organizations found")
    return Ok(())
  }
  let organization = if parsed.positionals.length() == 0 {
    let labels : Array[String] = []
    for item in organizations {
      labels.push(json_string_or_empty(item, "name"))
    }
    let selected = match prompt_select("Choose an Organization", labels) {
      Ok(selected) => selected
      Err(error) => return Err(error)
    }
    organizations[selected]
  } else {
    match find_organization(organizations, parsed.positionals[0]) {
      Some(organization) => organization
      None => return Err("organization \{parsed.positionals[0]} not found")
    }
  }
  match set_active_organization(json_string_or_empty(organization, "id")) {
    Ok(_) => {
      success(
        "Organization \{json_string_or_empty(organization, "name")} is now active",
      )
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// `daytona organization delete`.
pub async fn cmd_organization_delete(
  args : Array[String],
) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Delete an organization")
    out("")
    out("Usage: daytona organization delete [ORGANIZATION]")
    return Ok(())
  }
  match
    require_max_positionals(
      parsed, 1, "daytona organization delete [ORGANIZATION]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let organizations = match list_organizations() {
    Ok(organizations) => organizations
    Err(error) => return Err(error)
  }
  if organizations.length() == 0 {
    success("No organizations found")
    return Ok(())
  }
  let organization = if parsed.positionals.length() == 0 {
    let labels : Array[String] = []
    for item in organizations {
      labels.push(json_string_or_empty(item, "name"))
    }
    let selected = match prompt_select("Choose an Organization", labels) {
      Ok(selected) => selected
      Err(error) => return Err(error)
    }
    organizations[selected]
  } else {
    match find_organization(organizations, parsed.positionals[0]) {
      Some(organization) => organization
      None => return Err("organization \{parsed.positionals[0]} not found")
    }
  }
  let name = json_string_or_empty(organization, "name")
  if name == "Personal" {
    return Err("cannot delete personal organization")
  }
  let id = json_string_or_empty(organization, "id")
  match api_delete("/organizations/" + url_encode(id)) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  success("Organization \{name} has been deleted")
  let config = match load_config() {
    Ok(config) => config
    Err(_) => return Ok(())
  }
  let active_id = match active_organization(config) {
    Ok(active_id) => active_id
    Err(_) => ""
  }
  if active_id != id {
    return Ok(())
  }
  let personal = personal_organization_id(organizations)
  if personal == "" {
    return Ok(())
  }
  match set_active_organization(personal) {
    Ok(_) => Ok(())
    Err(_) => Ok(())
  }
}

///|
/// `daytona organization members`.
pub async fn cmd_organization_members(
  args : Array[String],
) -> Result[Unit, String] {
  let specs = [vflag("format", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("List members of an organization")
    out("")
    out("Usage: daytona organization members [ORGANIZATION] [flags]")
    out("")
    out("Flags:")
    out("      --format string   Output format: json or yaml")
    return Ok(())
  }
  match
    require_max_positionals(
      parsed, 1, "daytona organization members [ORGANIZATION]",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let organization_id = if parsed.positionals.length() == 0 {
    let config = match load_config() {
      Ok(config) => config
      Err(error) => return Err(error)
    }
    match active_organization(config) {
      Ok(id) => id
      Err(error) => return Err(error)
    }
  } else {
    match
      resolve_organization_id(
        match load_config() {
          Ok(config) => config
          Err(error) => return Err(error)
        },
        Some(parsed.positionals[0]),
      ) {
      Ok(id) => id
      Err(error) => return Err(error)
    }
  }
  let response = match
    api_get("/organizations/" + url_encode(organization_id) + "/users") {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let members = match response {
    Array(items) => items
    _ => []
  }
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(Json::array(members), format))
    return Ok(())
  }
  if members.length() == 0 {
    success("No members found")
    return Ok(())
  }
  members.sort_by(fn(a, b) {
    let created_a = json_string_or_empty(a, "createdAt")
    let created_b = json_string_or_empty(b, "createdAt")
    if created_a < created_b {
      -1
    } else if created_a > created_b {
      1
    } else {
      0
    }
  })
  let now = @env.now().reinterpret_as_int64()
  let rows : Array[Array[String]] = []
  for organization_member in members {
    let roles : Array[String] = []
    for role in json_array(organization_member, "assignedRoles") {
      roles.push(json_string_or_empty(role, "name"))
    }
    rows.push([
      json_string_or_empty(organization_member, "name"),
      json_string_or_empty(organization_member, "email"),
      json_string_or_empty(organization_member, "role"),
      if roles.length() == 0 {
        "-"
      } else {
        roles.join(", ")
      },
      created_label(organization_member, now),
    ])
  }
  out(render_table(["Name", "Email", "Role", "Assigned Roles", "Joined"], rows))
  Ok(())
}
