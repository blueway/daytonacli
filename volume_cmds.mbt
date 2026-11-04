///|
/// Volume commands.

///|
/// Whether a string has the canonical UUID shape.
pub fn looks_like_uuid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for index in 0..<36 {
    let char = value.get_char(index).unwrap()
    let dash = index == 8 || index == 13 || index == 18 || index == 23
    let hex = (char >= '0' && char <= '9') ||
      (char >= 'a' && char <= 'f') ||
      (char >= 'A' && char <= 'F')
    if dash {
      if char != '-' {
        return false
      }
    } else if !hex {
      return false
    }
  }
  true
}

///|
/// Resolve a volume ID or name to its DTO.
pub async fn resolve_volume(reference : String) -> Result[Json, String] {
  let mut id_volume : Json? = None
  let mut id_error = ""
  if looks_like_uuid(reference) {
    match api_get("/volumes/" + url_encode(reference)) {
      Ok(volume) =>
        if volume_state(volume) != "deleted" {
          id_volume = Some(volume)
        }
      Err(error) => id_error = error
    }
  }
  let name_volume = match api_get("/volumes/by-name/" + url_encode(reference)) {
    Ok(volume) => Some(volume)
    Err(_) => None
  }
  match (id_volume, name_volume) {
    (Some(by_id), Some(by_name)) =>
      if json_string_or_empty(by_id, "id") !=
        json_string_or_empty(by_name, "id") {
        Err(
          "volume reference \"\{reference}\" matches one volume's ID and another volume's name; rename the volume to remove the ambiguity",
        )
      } else {
        Ok(by_id)
      }
    (Some(by_id), None) => Ok(by_id)
    (None, Some(by_name)) => Ok(by_name)
    (None, None) =>
      if id_error != "" {
        Err(id_error)
      } else {
        Err("volume \{reference} not found")
      }
  }
}

///|
/// `daytona volume list`.
pub async fn cmd_volume_list(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("format", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("List all volumes")
    out("")
    out("Usage: daytona volume list [flags]")
    out("")
    out("Flags:")
    out("      --format string   Output format: json or yaml")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona volume list") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let response = match api_get("/volumes") {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  let items = match response {
    Array(items) => items
    Object(_) => json_array(response, "items")
    _ => []
  }
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(Json::array(items), format))
    return Ok(())
  }
  if items.length() == 0 {
    success("No volumes found")
    return Ok(())
  }
  items.sort_by(fn(a, b) {
    let priority_a = match volume_state(a) {
      "creating" => 1
      "error" => 2
      "ready" => 3
      "deleting" => 4
      _ => 99
    }
    let priority_b = match volume_state(b) {
      "creating" => 1
      "error" => 2
      "ready" => 3
      "deleting" => 4
      _ => 99
    }
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
  for volume in items {
    rows.push([
      json_string_or_empty(volume, "name"),
      volume_state_label(volume_state(volume)),
      "-",
      created_label(volume, now),
    ])
  }
  out(render_table(["Volume", "State", "Size", "Created"], rows))
  Ok(())
}

///|
/// `daytona volume create`.
pub async fn cmd_volume_create(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("size", "s")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Create a volume")
    out("")
    out("Usage: daytona volume create [NAME] [flags]")
    out("")
    out("Flags:")
    out("  -s, --size int   Size of the volume in GB (default 10)")
    return Ok(())
  }
  match require_positionals(parsed, 1, "daytona volume create [NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let name = parsed.positionals[0]
  let body = json_obj([("name", Json::string(name))])
  let volume = match api_post("/volumes", body) {
    Ok(volume) => volume
    Err(error) => return Err(error)
  }
  let display_name = match json_string(volume, "name") {
    Some(value) if value.length() > 0 => value
    _ => name
  }
  success("Volume \{display_name} successfully created")
  Ok(())
}

///|
/// `daytona volume get`.
pub async fn cmd_volume_get(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("format", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Get volume details")
    out("")
    out("Usage: daytona volume get [VOLUME_ID_OR_NAME] [flags]")
    out("")
    out("Flags:")
    out("      --format string   Output format: json or yaml")
    return Ok(())
  }
  match
    require_positionals(parsed, 1, "daytona volume get [VOLUME_ID_OR_NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let volume = match resolve_volume(parsed.positionals[0]) {
    Ok(volume) => volume
    Err(error) => return Err(error)
  }
  let format = arg_value(parsed, "format")
  if format != "" {
    out(format_structured(volume, format))
    return Ok(())
  }
  let now = @env.now().reinterpret_as_int64()
  out(render_info("", volume_info_fields(volume, now)))
  Ok(())
}

///|
/// `daytona volume delete`.
pub async fn cmd_volume_delete(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Delete a volume")
    out("")
    out("Usage: daytona volume delete [VOLUME_ID_OR_NAME]")
    return Ok(())
  }
  match
    require_positionals(parsed, 1, "daytona volume delete [VOLUME_ID_OR_NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let reference = parsed.positionals[0]
  let volume = match resolve_volume(reference) {
    Ok(volume) => volume
    Err(error) => return Err(error)
  }
  match
    api_delete("/volumes/" + url_encode(json_string_or_empty(volume, "id"))) {
    Ok(_) => {
      success("Volume \{reference} deleted")
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// `daytona volume resolve`.
pub async fn cmd_volume_resolve(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Resolve a volume name to its ID")
    out("")
    out("Usage: daytona volume resolve [VOLUME_NAME]")
    return Ok(())
  }
  match require_positionals(parsed, 1, "daytona volume resolve [VOLUME_NAME]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let volume = match
    api_get("/volumes/by-name/" + url_encode(parsed.positionals[0])) {
    Ok(volume) => volume
    Err(error) => return Err(error)
  }
  out(json_string_or_empty(volume, "id"))
  Ok(())
}
