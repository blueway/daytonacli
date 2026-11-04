///|
/// Profile and configuration storage.
///
/// The on-disk format is byte-compatible with the Go CLI:
/// `~/.config/daytona/config.json` with `activeProfile` and `profiles`, where a
/// profile carries the API URL and either an API key or an OAuth token. Keeping
/// the same file means users can switch between the two CLIs without logging in
/// again.

///|
/// Stored OAuth token. Kept for profiles created by the browser login.
pub(all) struct Token {
  access_token : String
  refresh_token : String
  expires_at : String
  issuer : String?
  client_id : String?
}

///|
/// A configured Daytona endpoint and its credentials.
pub(all) struct Profile {
  id : String
  name : String
  url : String
  key : String?
  token : Token?
  active_org : String?
}

///|
/// The config file contents.
pub(all) struct Config {
  mut active_profile_id : String
  mut profiles : Array[Profile]
}

///|
/// The default API endpoint, matching the SDKs and the Go CLI.
pub let default_api_url : String = "https://app.daytona.io/api"

///|
/// The directory holding the CLI's config and cache files.
pub fn config_dir() -> String {
  let dir_override = @env.get_env_var("DAYTONA_CONFIG_DIR")
  if dir_override is Some(dir) && dir.length() > 0 {
    return dir
  }
  match platform() {
    1 =>
      match @env.get_env_var("HOME") {
        Some(home) if home.length() > 0 =>
          home + "/Library/Application Support/daytona"
        _ => "/tmp/daytona"
      }
    2 =>
      match @env.get_env_var("APPDATA") {
        Some(dir) if dir.length() > 0 => dir + "\\daytona"
        _ => "daytona"
      }
    _ =>
      match @env.get_env_var("XDG_CONFIG_HOME") {
        Some(dir) if dir.length() > 0 => dir + "/daytona"
        _ =>
          match @env.get_env_var("HOME") {
            Some(home) if home.length() > 0 => home + "/.config/daytona"
            _ => "/tmp/daytona"
          }
      }
  }
}

///|
/// Full path of the config file.
pub fn config_path() -> String {
  config_dir() + "/config.json"
}

///|
/// Build a profile with only the fields the CLI currently needs.
pub fn make_profile(
  id : String,
  name : String,
  url : String,
  key : String?,
  token : Token?,
  active_org : String?,
) -> Profile {
  { id, name, url, key, token, active_org, }
}

///|
/// The empty config written on first use.
pub fn empty_config() -> Config {
  { active_profile_id: "", profiles: [], }
}

///|
/// Decode one profile from JSON. Unknown fields from a newer Go CLI are
/// ignored rather than rejected.
pub fn profile_from_json(value : Json) -> Profile? {
  let id = json_string_or_empty(value, "id")
  if id == "" {
    return None
  }
  let name = match json_string(value, "name") {
    Some(text) => text
    None => id
  }
  let api = match json_object(value, "api") {
    Some(api) => api
    None => Json::empty_object()
  }
  let url = match json_string(api, "url") {
    Some(text) if text.length() > 0 => text
    _ => default_api_url
  }
  let key = json_nullable_string(api, "key")
  let token = match json_object(api, "token") {
    Some(token_json) => Some(token_from_json(token_json))
    None => None
  }
  let active_org = json_nullable_string(value, "activeOrganizationId")
  Some({ id, name, url, key, token, active_org, })
}

///|
/// Decode an OAuth token.
pub fn token_from_json(value : Json) -> Token {
  let access_token = json_string_or_empty(value, "accessToken")
  let refresh_token = json_string_or_empty(value, "refreshToken")
  let expires_at = json_string_or_empty(value, "expiresAt")
  let (issuer, client_id) = match json_object(value, "workos") {
    Some(workos) =>
      (
        json_nullable_string(workos, "issuer"),
        json_nullable_string(workos, "clientId"),
      )
    None => (None, None)
  }
  { access_token, refresh_token, expires_at, issuer, client_id, }
}

///|
/// Decode the config file. A malformed file is an error: silently replacing it
/// would discard credentials.
pub fn config_from_json(value : Json) -> Config {
  let active_profile_id = json_string_or_empty(value, "activeProfile")
  let profiles : Array[Profile] = []
  for item in json_array(value, "profiles") {
    match profile_from_json(item) {
      Some(profile) => profiles.push(profile)
      None => ()
    }
  }
  { active_profile_id, profiles, }
}

///|
/// Load the config, creating an empty file when none exists.
pub async fn load_config() -> Result[Config, String] {
  let path = config_path()
  let exists = @fs.exists(path) catch { _ => false }
  if !exists {
    let config = empty_config()
    match save_config(config) {
      Ok(_) => Ok(config)
      Err(error) => Err(error)
    }
  } else {
    let text = @fs.read_file(path) catch {
      error => return Err("could not read \{path}: \{error}")
    }
    let json = @json.parse(text.text()) catch {
      error => return Err("could not parse \{path}: \{error}")
    }
    Ok(config_from_json(json))
  }
}

///|
/// Atomically replace the config file. A concurrent reader (a second CLI
/// process, or the MCP server) sees either the old or the new file, never a
/// truncated one.
pub async fn save_config(config : Config) -> Result[Unit, String] {
  let dir = config_dir()
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    error => return Err("could not create \{dir}: \{error}")
  }
  let path = config_path()
  let temp = path + ".\{@env.now()}.tmp"
  let text = config_to_json(config).stringify(indent=2)
  @fs.write_file(temp, text, permission=0o600, create_mode=CreateOrTruncate) catch {
    error => return Err("could not write \{temp}: \{error}")
  }
  @fs.rename(temp, path, replace=true) catch {
    error => {
      let _ = @fs.remove(temp) catch { _ => () }
      return Err("could not replace \{path}: \{error}")
    }
  }
  Ok(())
}

///|
/// Serialize a profile.
pub fn profile_to_json(profile : Profile) -> Json {
  let api_pairs : Array[(String, Json)] = [("url", Json::string(profile.url))]
  match profile.key {
    Some(key) => api_pairs.push(("key", Json::string(key)))
    None => ()
  }
  match profile.token {
    Some(token) => api_pairs.push(("token", token_to_json(token)))
    None => ()
  }
  let pairs : Array[(String, Json)] = [
    ("id", Json::string(profile.id)),
    ("name", Json::string(profile.name)),
    ("api", object_of(api_pairs)),
  ]
  match profile.active_org {
    Some(org) => pairs.push(("activeOrganizationId", Json::string(org)))
    None => ()
  }
  object_of(pairs)
}

///|
/// Serialize a token.
pub fn token_to_json(token : Token) -> Json {
  let pairs : Array[(String, Json)] = [
    ("accessToken", Json::string(token.access_token)),
    ("refreshToken", Json::string(token.refresh_token)),
    ("expiresAt", Json::string(token.expires_at)),
  ]
  match (token.issuer, token.client_id) {
    (Some(issuer), Some(client_id)) =>
      pairs.push(
        (
          "workos",
          object_of([
            ("issuer", Json::string(issuer)),
            ("clientId", Json::string(client_id)),
          ]),
        ),
      )
    _ => ()
  }
  object_of(pairs)
}

///|
/// Serialize the config.
pub fn config_to_json(config : Config) -> Json {
  let profiles : Array[Json] = []
  for profile in config.profiles {
    profiles.push(profile_to_json(profile))
  }
  object_of([
    ("activeProfile", Json::string(config.active_profile_id)),
    ("profiles", Json::array(profiles)),
  ])
}

///|
/// The active profile. `DAYTONA_API_URL` plus `DAYTONA_API_KEY` wins over the
/// file, which is how CI and the SDKs are configured.
pub fn active_profile(config : Config) -> Result[Profile, String] {
  let env_url = @env.get_env_var("DAYTONA_API_URL")
  let env_key = @env.get_env_var("DAYTONA_API_KEY")
  match (env_url, env_key) {
    (Some(url), Some(key)) if url.length() > 0 && key.length() > 0 =>
      return Ok({
        id: "env",
        name: "env",
        url,
        key: Some(key),
        token: None,
        active_org: None,
      })
    _ => ()
  }
  if config.profiles.length() == 0 {
    return Err("no profiles found. Run `daytona login` to authenticate")
  }
  for profile in config.profiles {
    if profile.id == config.active_profile_id {
      return Ok(profile)
    }
  }
  Err("no active profile found. Run `daytona login` to authenticate")
}

///|
/// The active organization configured on the active profile.
pub fn active_organization(config : Config) -> Result[String, String] {
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  match profile.active_org {
    Some(org) if org.length() > 0 => Ok(org)
    _ =>
      Err(
        "no active organization found. Run `daytona organization use` to select an organization",
      )
  }
}

///|
/// The bearer token used for API calls. API keys and access tokens are both
/// sent as bearer credentials, exactly as the Go CLI does.
pub fn profile_token(profile : Profile) -> String? {
  match profile.key {
    Some(key) if key.length() > 0 => Some(key)
    _ =>
      match profile.token {
        Some(token) if token.access_token.length() > 0 =>
          Some(token.access_token)
        _ => None
      }
  }
}

///|
/// Replace a profile by id, returning the updated config.
pub fn update_profile(
  config : Config,
  profile : Profile,
) -> Result[Unit, String] {
  let mut found = false
  for index in 0..<config.profiles.length() {
    if config.profiles[index].id == profile.id {
      config.profiles[index] = profile
      found = true
      break
    }
  }
  if !found {
    return Err("profile with id \{profile.id} not found")
  }
  Ok(())
}

///|
/// Add a profile and make it active.
pub fn add_profile(config : Config, profile : Profile) -> Unit {
  config.profiles.push(profile)
  config.active_profile_id = profile.id
}

///|
/// Format an instant as ISO-8601 UTC, used when storing token expiry.
pub fn now_iso() -> String {
  let millis = @env.now().reinterpret_as_int64()
  iso_from_seconds(millis / 1_000L)
}

///|
/// Format Unix seconds as ISO-8601 UTC.
pub fn iso_from_seconds(seconds : Int64) -> String {
  let (year, month, day, hour, minute, second) = civil_from_seconds(seconds)
  pad4(year) +
  "-" +
  pad2(month) +
  "-" +
  pad2(day) +
  "T" +
  pad2(hour) +
  ":" +
  pad2(minute) +
  ":" +
  pad2(second) +
  "Z"
}

///|
/// Two-digit zero padding.
fn pad2(value : Int64) -> String {
  if value < 10L {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
/// Four-digit zero padding.
fn pad4(value : Int64) -> String {
  let text = value.to_string()
  if value < 10L {
    "000" + text
  } else if value < 100L {
    "00" + text
  } else if value < 1000L {
    "0" + text
  } else {
    text
  }
}

///|
/// Convert Unix seconds to a civil UTC date (inverse of days_from_civil).
fn civil_from_seconds(
  seconds : Int64,
) -> (Int64, Int64, Int64, Int64, Int64, Int64) {
  let days = floor_div(seconds, 86_400L)
  let rem = seconds - days * 86_400L
  let z = days + 719_468L
  let era = floor_div(z, 146_097L)
  let doe = z - era * 146_097L
  let yoe = (doe - doe / 1460L + doe / 36_524L - doe / 146_096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  let year = if m <= 2L { y + 1L } else { y }
  let hour = rem / 3600L
  let minute = rem % 3600L / 60L
  let second = rem % 60L
  (year, m, d, hour, minute, second)
}

///|
/// Integer division rounded toward negative infinity.
fn floor_div(value : Int64, divisor : Int64) -> Int64 {
  let quotient = value / divisor
  if value % divisor != 0L && (value < 0L) != (divisor < 0L) {
    quotient - 1L
  } else {
    quotient
  }
}

///|
/// UTC timestamp in the compact `YYYYMMDDhhmmss` form used for registry tags.
pub fn now_compact_timestamp() -> String {
  let millis = @env.now().reinterpret_as_int64()
  let seconds = millis / 1_000L
  let (year, month, day, hour, minute, second) = civil_from_seconds(seconds)
  pad4(year) +
  pad2(month) +
  pad2(day) +
  pad2(hour) +
  pad2(minute) +
  pad2(second)
}
