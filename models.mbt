///|
/// Display helpers for the API's DTOs. The CLI deliberately reads JSON by field
/// name rather than generated structs: the API evolves by adding fields, and an
/// older CLI must keep working when one appears.

///|
/// The human label for a sandbox state.
pub fn sandbox_state_label(state : String) -> String {
  match state {
    "creating" => "CREATING"
    "restoring" => "RESTORING"
    "destroyed" => "DESTROYED"
    "destroying" => "DESTROYING"
    "started" => "STARTED"
    "stopped" => "STOPPED"
    "starting" => "STARTING"
    "stopping" => "STOPPING"
    "pending_build" => "PENDING BUILD"
    "building_snapshot" => "BUILDING SNAPSHOT"
    "pulling_snapshot" => "PULLING SNAPSHOT"
    "archiving" => "ARCHIVING"
    "archived" => "ARCHIVED"
    "error" => "ERROR"
    "build_failed" => "BUILD FAILED"
    "paused" => "PAUSED"
    "pausing" => "PAUSING"
    "resuming" => "RESUMING"
    "resizing" => "RESIZING"
    "snapshotting" => "SNAPSHOTTING"
    "forking" => "FORKING"
    "unknown" => "UNKNOWN"
    _ => "/"
  }
}

///|
/// The human label for a snapshot state.
pub fn snapshot_state_label(state : String) -> String {
  match state {
    "pending" => "PENDING"
    "pulling" => "PULLING"
    "active" => "ACTIVE"
    "inactive" => "INACTIVE"
    "error" => "ERROR"
    "removing" => "REMOVING"
    "build_failed" => "BUILD FAILED"
    _ => state.to_upper()
  }
}

///|
/// The human label for a volume state.
pub fn volume_state_label(state : String) -> String {
  match state {
    "creating" => "CREATING"
    "ready" => "READY"
    "error" => "ERROR"
    "deleting" => "DELETING"
    "deleted" => "DELETED"
    _ => state.to_upper()
  }
}

///|
/// State priority used when sorting sandbox lists; active operations first,
/// then running, then failures, then stopped sandboxes.
pub fn sandbox_state_priority(state : String) -> Int32 {
  match state {
    "pending_build" => 1
    "creating" => 1
    "starting" => 1
    "pulling_snapshot" => 1
    "building_snapshot" => 1
    "destroying" => 1
    "started" => 2
    "paused" => 2
    "error" => 3
    "build_failed" => 3
    "stopped" => 4
    "archived" => 4
    _ => 99
  }
}

///|
/// State priority for snapshots.
pub fn snapshot_state_priority(state : String) -> Int32 {
  match state {
    "pending" => 1
    "pulling" => 1
    "error" => 2
    "active" => 3
    "inactive" => 3
    "removing" => 4
    _ => 99
  }
}

///|
/// Format the snapshot size in GB, or "-" when the API has no size yet.
pub fn snapshot_size_label(snapshot : Json) -> String {
  match json_get(snapshot, "size") {
    Some(Number(size, ..)) => format_fixed(size, 2) + " GB"
    _ => "-"
  }
}

///|
/// Format a double with a fixed number of decimals.
pub fn format_fixed(value : Double, _decimals : Int32) -> String {
  let scale = 10.0 * 10.0
  let scaled = value * scale
  let rounded = if scaled >= 0.0 {
    (scaled + 0.5).to_int()
  } else {
    (scaled - 0.5).to_int()
  }
  let whole = rounded / 100
  let fraction = rounded % 100
  if fraction < 10 {
    "\{whole}.0\{fraction}"
  } else {
    "\{whole}.\{fraction}"
  }
}

///|
/// A sandbox's display name.
pub fn sandbox_name(sandbox : Json) -> String {
  let name = json_string_or_empty(sandbox, "name")
  if name.length() > 0 {
    name
  } else {
    json_string_or_empty(sandbox, "id")
  }
}

///|
/// A sandbox's state.
pub fn sandbox_state(sandbox : Json) -> String {
  match json_string(sandbox, "state") {
    Some(state) => state
    None => "unknown"
  }
}

///|
/// A snapshot's state.
pub fn snapshot_state(snapshot : Json) -> String {
  match json_string(snapshot, "state") {
    Some(state) => state
    None => "unknown"
  }
}

///|
/// A volume's state.
pub fn volume_state(volume : Json) -> String {
  match json_string(volume, "state") {
    Some(state) => state
    None => "unknown"
  }
}

///|
/// A sandbox or snapshot's creation time as an age label.
pub fn created_label(value : Json, now_millis : Int64) -> String {
  match json_string(value, "createdAt") {
    Some(timestamp) => time_since_label(timestamp, now_millis)
    None => "/"
  }
}

///|
/// The last activity time as an age label.
pub fn last_event_label(value : Json, now_millis : Int64) -> String {
  match json_string(value, "lastActivityAt") {
    Some(timestamp) => time_since_label(timestamp, now_millis)
    None => "/"
  }
}

///|
/// The fields shown by `daytona info`.
pub fn sandbox_info_fields(
  sandbox : Json,
  now_millis : Int64,
) -> Array[(String, String)] {
  let fields : Array[(String, String)] = []
  fields.push(("ID", json_string_or_empty(sandbox, "id")))
  let state = sandbox_state(sandbox)
  fields.push(("State", sandbox_state_label(state)))
  match json_nullable_string(sandbox, "snapshot") {
    Some(snapshot) if snapshot.length() > 0 =>
      fields.push(("Snapshot", snapshot))
    _ => ()
  }
  fields.push(("Region", json_string_or_empty(sandbox, "target")))
  match json_get(sandbox, "queueTimeout") {
    Some(Number(minutes, ..)) =>
      fields.push(("Queue Timeout", "\{minutes.to_int()} minutes"))
    _ => ()
  }
  match json_nullable_string(sandbox, "queueTimedOutAt") {
    Some(timestamp) =>
      fields.push(("Queue Timed Out", time_since_label(timestamp, now_millis)))
    _ => ()
  }
  match json_nullable_string(sandbox, "spotEvictedAt") {
    Some(timestamp) =>
      fields.push(("Spot Evicted At", time_since_label(timestamp, now_millis)))
    _ => ()
  }
  match json_string(sandbox, "createdAt") {
    Some(timestamp) =>
      fields.push(("Created", time_since_label(timestamp, now_millis)))
    _ => ()
  }
  match json_string(sandbox, "lastActivityAt") {
    Some(timestamp) =>
      fields.push(("Last Event", time_since_label(timestamp, now_millis)))
    _ => ()
  }
  match json_object(sandbox, "labels") {
    Some(Json::Object(labels)) if labels.length() > 0 => {
      let pairs : Array[String] = []
      for pair in labels {
        let (key, value) = pair
        match value {
          String(text) => pairs.push(key + "=" + text)
          _ => ()
        }
      }
      fields.push(("Labels", pairs.join(", ")))
    }
    _ => ()
  }
  fields
}

///|
/// The fields shown by `daytona snapshot` info paths.
pub fn snapshot_info_fields(
  snapshot : Json,
  now_millis : Int64,
) -> Array[(String, String)] {
  let fields : Array[(String, String)] = []
  fields.push(("ID", json_string_or_empty(snapshot, "id")))
  fields.push(("Name", json_string_or_empty(snapshot, "name")))
  fields.push(("State", snapshot_state_label(snapshot_state(snapshot))))
  match json_nullable_string(snapshot, "imageName") {
    Some(image) if image.length() > 0 => fields.push(("Image", image))
    _ => ()
  }
  fields.push(("Size", snapshot_size_label(snapshot)))
  match json_get(snapshot, "cpu") {
    Some(Number(cpu, ..)) => fields.push(("CPU", cpu.to_int().to_string()))
    _ => ()
  }
  match json_get(snapshot, "mem") {
    Some(Number(mem, ..)) =>
      fields.push(("Memory", format_fixed(mem, 1) + " GB"))
    _ => ()
  }
  match json_get(snapshot, "disk") {
    Some(Number(disk, ..)) =>
      fields.push(("Disk", format_fixed(disk, 1) + " GB"))
    _ => ()
  }
  match json_string(snapshot, "createdAt") {
    Some(timestamp) =>
      fields.push(("Created", time_since_label(timestamp, now_millis)))
    _ => ()
  }
  match json_nullable_string(snapshot, "errorReason") {
    Some(reason) if reason.length() > 0 => fields.push(("Error", reason))
    _ => ()
  }
  fields
}

///|
/// The fields shown by `daytona volume get`.
pub fn volume_info_fields(
  volume : Json,
  now_millis : Int64,
) -> Array[(String, String)] {
  let fields : Array[(String, String)] = []
  fields.push(("ID", json_string_or_empty(volume, "id")))
  fields.push(("Name", json_string_or_empty(volume, "name")))
  fields.push(("State", volume_state_label(volume_state(volume))))
  fields.push(("Created", created_label(volume, now_millis)))
  match json_nullable_string(volume, "lastUsedAt") {
    Some(timestamp) if timestamp.length() > 0 =>
      fields.push(("Last Used", time_since_label(timestamp, now_millis)))
    _ => ()
  }
  match json_nullable_string(volume, "errorReason") {
    Some(reason) if reason.length() > 0 => fields.push(("Error", reason))
    _ => ()
  }
  fields
}

///|
/// The fields shown for an organization.
pub fn organization_info_fields(organization : Json) -> Array[(String, String)] {
  let fields : Array[(String, String)] = []
  fields.push(("ID", json_string_or_empty(organization, "id")))
  fields.push(("Name", json_string_or_empty(organization, "name")))
  fields.push(
    (
      "Personal",
      if json_bool(organization, "personal") is Some(true) {
        "yes"
      } else {
        "no"
      },
    ),
  )
  match json_nullable_string(organization, "defaultRegionId") {
    Some(region) if region.length() > 0 =>
      fields.push(("Default Region", region))
    _ => ()
  }
  fields
}

///|
/// Print the active organization line used by the list commands.
pub async fn print_active_organization(config : Config) -> Unit {
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(_) => return
  }
  // API-key profiles have no user identity, so the Go CLI suppresses the line.
  if profile.key is Some(_) && profile.token is None {
    return
  }
  match profile.active_org {
    Some(org) if org.length() > 0 =>
      match api_get("/organizations/" + url_encode(org)) {
        Ok(organization) =>
          info(
            "Active organization: " + json_string_or_empty(organization, "name"),
          )
        Err(_) => ()
      }
    _ => ()
  }
}

///|
/// Resolve an organization argument to an ID: a name, an ID, or the active
/// organization.
pub async fn resolve_organization_id(
  config : Config,
  argument : String?,
) -> Result[String, String] {
  match argument {
    None =>
      match active_organization(config) {
        Ok(org) => Ok(org)
        Err(error) => Err(error)
      }
    Some(reference) => {
      let organizations = match api_get("/organizations") {
        Ok(Json::Array(items)) => items
        Ok(_) => return Err("unexpected response while listing organizations")
        Err(error) => return Err(error)
      }
      for organization in organizations {
        let id = json_string_or_empty(organization, "id")
        let name = json_string_or_empty(organization, "name")
        if id == reference || name == reference {
          return Ok(id)
        }
      }
      Err("organization \{reference} not found")
    }
  }
}

///|
/// Find the personal organization in a list.
pub fn personal_organization_id(organizations : Array[Json]) -> String {
  for organization in organizations {
    if json_bool(organization, "personal") is Some(true) {
      return json_string_or_empty(organization, "id")
    }
  }
  ""
}
