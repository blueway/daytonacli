///|
/// HTTP access to the Daytona API.
///
/// Every request carries the same default headers as the Go CLI:
/// `Authorization`, the active organization, and `X-Daytona-Source: cli`.
/// Errors are decoded into the server's `error` / `message` shape and given the
/// same re-authentication hints.

///|
/// The current API version header, used only for diagnostics.
pub let api_version_header : String = "X-Daytona-Api-Version"

///|
/// A small wrapper around one API response.
pub(all) struct ApiResponse {
  status : Int32
  body : Json
  text : String
}

///|
/// Build the headers shared by every API request.
pub fn api_headers(
  profile : Profile,
  extra : Map[String, String],
) -> Map[@http.CaseInsensitiveString, String] {
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.set(@http.CaseInsensitiveString("Accept"), "application/json")
  headers.set(@http.CaseInsensitiveString("Content-Type"), "application/json")
  headers.set(@http.CaseInsensitiveString("X-Daytona-Source"), "cli")
  headers.set(@http.CaseInsensitiveString("User-Agent"), "daytona-cli/0.1.0")
  match profile_token(profile) {
    Some(token) =>
      headers.set(
        @http.CaseInsensitiveString("Authorization"),
        "Bearer " + token,
      )
    None => ()
  }
  // The organization header only applies to OAuth sessions; API keys are
  // already scoped to one organization.
  match profile.active_org {
    Some(org) if org.length() > 0 && profile.token is Some(_) =>
      headers.set(@http.CaseInsensitiveString("X-Daytona-Organization-ID"), org)
    _ => ()
  }
  for pair in extra {
    let (key, value) = pair
    headers.set(@http.CaseInsensitiveString(key), value)
  }
  headers
}

///|
/// Send a request to the API. `path` starts with `/` and may include a query
/// string. The active profile supplies the base URL and credentials.
pub async fn api_request(
  http_method : @http.RequestMethod,
  path : String,
  body : Json?,
  extra_headers? : Map[String, String],
) -> Result[ApiResponse, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let mut profile = match active_profile(config) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  if profile_token(profile) is None {
    return Err("no valid token found, use `daytona login` to reauthenticate")
  }
  // OAuth access tokens expire; refresh shortly before they do, and persist the
  // rotated refresh token so the next process can use it too.
  if profile.key is None && token_needs_refresh(profile) {
    let refreshed = match refresh_access_token(profile) {
      Ok(token) => token
      Err(error) => return Err(error)
    }
    // A refresh can hand back the token another process already stored (see
    // `token_rotated_elsewhere`); writing that copy back could overwrite a
    // newer rotation, so it is only persisted when it differs from the file.
    let already_stored = match profile.token {
      Some(current) =>
        current.access_token == refreshed.access_token &&
        current.refresh_token == refreshed.refresh_token
      None => false
    }
    if !already_stored {
      match save_refreshed_token(profile, refreshed) {
        Ok(_) => ()
        Err(error) => return Err("failed to save the refreshed token: \{error}")
      }
    }
    profile = {
      id: profile.id,
      name: profile.name,
      url: profile.url,
      key: profile.key,
      token: Some(refreshed),
      active_org: profile.active_org,
    }
  }
  let extra = match extra_headers {
    Some(headers) => headers
    None => Map([])
  }
  let headers = api_headers(profile, extra)
  let url = trim_trailing_slash(profile.url) + path
  let (response, response_body) = try {
    match body {
      Some(json) => @http.request(url, http_method, headers, json)
      None => @http.request(url, http_method, headers, "")
    }
  } catch {
    error => return Err("failed to connect to \{url}: \{error}")
  }
  let text = response_body.text() catch { _ => "" }
  let parsed = if text.length() == 0 {
    Json::null()
  } else {
    @json.parse(text) catch {
      _ => Json::null()
    }
  }
  if response.code >= 200 && response.code < 300 {
    return Ok({ status: response.code, body: parsed, text, })
  }
  let message = api_error_message(parsed, text)
  let hint = if response.code == 401 {
    " - run `daytona login` to reauthenticate"
  } else if response.code == 403 {
    " - check that your API key has sufficient permissions for this action"
  } else {
    ""
  }
  Err(message + hint)
}

///|
/// Decode the server's error body. Falls back to the raw body when it is not
/// the documented shape.
pub fn api_error_message(body : Json, raw : String) -> String {
  let error = json_string_or_empty(body, "error")
  if error == "" {
    if raw.length() > 0 {
      raw
    } else {
      "request failed"
    }
  } else {
    match json_get(body, "message") {
      Some(String(message)) => error + ": " + message
      Some(Array(items)) => {
        let parts : Array[String] = []
        for item in items {
          match item {
            String(text) => parts.push(text)
            _ => parts.push(item.stringify())
          }
        }
        error + ": [" + parts.join(", ") + "]"
      }
      _ => error
    }
  }
}

///|
/// Remove a trailing slash from a base URL.
pub fn trim_trailing_slash(url : String) -> String {
  let mut result = url
  while result.length() > 0 &&
        result.get_char(result.length() - 1).unwrap() == '/' {
    result = result.exact_view(start=0, end=result.length() - 1).to_owned()
  }
  result
}

///|
/// GET helper.
pub async fn api_get(path : String) -> Result[Json, String] {
  let response = match api_request(@http.RequestMethod::Get, path, None) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  Ok(response.body)
}

///|
/// GET helper with extra headers.
pub async fn api_get_with_headers(
  path : String,
  headers : Map[String, String],
) -> Result[Json, String] {
  let response = match
    api_request(@http.RequestMethod::Get, path, None, extra_headers=headers) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  Ok(response.body)
}

///|
/// POST helper.
pub async fn api_post(path : String, body : Json) -> Result[Json, String] {
  let response = match
    api_request(@http.RequestMethod::Post, path, Some(body)) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  Ok(response.body)
}

///|
/// PATCH helper.
pub async fn api_patch(path : String, body : Json) -> Result[Json, String] {
  let response = match
    api_request(@http.RequestMethod::Patch, path, Some(body)) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  Ok(response.body)
}

///|
/// DELETE helper.
pub async fn api_delete(path : String) -> Result[Json, String] {
  let response = match api_request(@http.RequestMethod::Delete, path, None) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  Ok(response.body)
}

///|
/// DELETE helper that tolerates a 404, used by the optimistic ID-then-name
/// fallback the Go CLI applies to snapshots and volumes.
pub async fn api_delete_allow_404(path : String) -> Result[Bool, String] {
  match api_request(@http.RequestMethod::Delete, path, None) {
    Ok(_) => Ok(true)
    Err(error) =>
      if error.has_prefix("not found") {
        Ok(false)
      } else {
        Err(error)
      }
  }
}

///|
/// POST with no body, used by lifecycle endpoints.
pub async fn api_post_empty(path : String) -> Result[Json, String] {
  let response = match api_request(@http.RequestMethod::Post, path, None) {
    Ok(response) => response
    Err(error) => return Err(error)
  }
  Ok(response.body)
}

///|
/// Build a paginated query string, omitting defaults only when asked.
pub fn query_string(pairs : Array[(String, String)]) -> String {
  if pairs.length() == 0 {
    return ""
  }
  let parts : Array[String] = []
  for pair in pairs {
    let (key, value) = pair
    parts.push(url_encode(key) + "=" + url_encode(value))
  }
  "?" + parts.join("&")
}

///|
/// Execute a command through the sandbox toolbox proxy.
pub async fn toolbox_execute(
  proxy_url : String,
  sandbox_id : String,
  command : String,
  cwd : String?,
  timeout : Int32?,
) -> Result[Json, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  let headers = api_headers(profile, Map([]))
  let url = trim_trailing_slash(proxy_url) +
    "/" +
    url_encode(sandbox_id) +
    "/process/execute"
  let pairs : Array[(String, Json)] = [("command", Json::string(command))]
  match cwd {
    Some(dir) if dir.length() > 0 => pairs.push(("cwd", Json::string(dir)))
    _ => ()
  }
  match timeout {
    Some(seconds) if seconds > 0 =>
      pairs.push(("timeout", Json::number(seconds.to_double())))
    _ => ()
  }
  let body = object_of(pairs)
  let (response, response_body) = @http.request(
    url,
    @http.RequestMethod::Post,
    headers,
    body,
  ) catch {
    error => return Err("failed to execute request: \{error}")
  }
  let text = response_body.text() catch { _ => "" }
  if response.code != 200 {
    return Err("request failed with status \{response.code}: \{text}")
  }
  let parsed = @json.parse(text) catch {
    error => return Err("failed to parse response: \{error}")
  }
  Ok(parsed)
}

///|
/// Call an arbitrary toolbox endpoint through the sandbox proxy.
pub async fn toolbox_request(
  http_method : @http.RequestMethod,
  proxy_url : String,
  sandbox_id : String,
  subpath : String,
  query : String,
  body : Json?,
) -> Result[Json, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  let headers = api_headers(profile, Map([]))
  let url = trim_trailing_slash(proxy_url) +
    "/" +
    url_encode(sandbox_id) +
    subpath +
    query
  let (response, response_body) = try {
    match body {
      Some(json) => @http.request(url, http_method, headers, json)
      None => @http.request(url, http_method, headers, "")
    }
  } catch {
    error => return Err("failed to execute request: \{error}")
  }
  let text = response_body.text() catch { _ => "" }
  if response.code < 200 || response.code >= 300 {
    return Err("request failed with status \{response.code}: \{text}")
  }
  if text.length() == 0 {
    return Ok(Json::null())
  }
  let parsed = @json.parse(text) catch {
    error => return Err("failed to parse response: \{error}")
  }
  Ok(parsed)
}
