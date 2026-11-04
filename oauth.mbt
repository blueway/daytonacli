///|
/// Browser login: OAuth 2.0 Authorization Code with PKCE, a loopback callback
/// server, and token refresh. The flow matches the Go CLI: the API's `/config`
/// endpoint advertises the identity provider, WorkOS is used when advertised,
/// and Auth0 is the fallback.

///|
/// The identity provider endpoints for one login.
priv struct LoginProvider {
  auth_url : String
  token_url : String
  client_id : String
  redirect_uri : String
  scope : String
  audience : String
  issuer : String
  jwks_uri : String
  workos_issuer : String?
}

///|
/// The result of one callback request.
priv enum CallbackEvent {
  CallbackCode(String)
  CallbackFailure(String)
  CallbackIgnored
}

///|
/// The callback port, matching the Go CLI's default.
fn callback_port() -> String {
  match @env.get_env_var("DAYTONA_AUTH0_CALLBACK_PORT") {
    Some(port) if port.length() > 0 => port
    _ => "3009"
  }
}

///|
/// The redirect URI registered with the identity provider.
fn callback_url() -> String {
  "http://localhost:" + callback_port() + "/callback"
}

///|
/// The API URL used for login: the active profile, or the default when no
/// profile exists yet.
async fn login_api_url() -> Result[String, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  match active_profile(config) {
    Ok(profile) => Ok(profile.url)
    Err(error) =>
      if error.has_prefix("no profiles found") {
        Ok(default_api_url)
      } else {
        Err(error)
      }
  }
}

///|
/// GET a JSON document without credentials.
async fn unauthenticated_json(url : String) -> Result[Json, String] {
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.set(@http.CaseInsensitiveString("Accept"), "application/json")
  let (response, body) = @http.request(
    url,
    @http.RequestMethod::Get,
    headers,
    "",
  ) catch {
    error => return Err("failed to connect to \{url}: \{error}")
  }
  let text = body.text() catch { _ => "" }
  let parsed = if text.length() == 0 {
    Json::null()
  } else {
    @json.parse(text) catch {
      _ => Json::null()
    }
  }
  if response.code >= 200 && response.code < 300 {
    Ok(parsed)
  } else {
    Err(oauth_error_message(parsed, text))
  }
}

///|
/// Decode an OAuth error response.
fn oauth_error_message(body : Json, raw : String) -> String {
  let error = json_string_or_empty(body, "error")
  let description = json_string_or_empty(body, "error_description")
  if error != "" && description != "" {
    error + ": " + description
  } else if error != "" {
    error
  } else if description != "" {
    description
  } else if raw.length() > 0 {
    raw
  } else {
    "authentication failed"
  }
}

///|
/// Normalize an issuer URL: add https when the scheme is missing and remove a
/// trailing slash.
fn normalize_issuer(issuer : String) -> String {
  let trimmed = issuer.trim().to_owned()
  if trimmed == "" {
    return ""
  }
  let with_scheme = if trimmed.contains("://") {
    trimmed
  } else {
    "https://" + trimmed
  }
  trim_trailing_slash(with_scheme)
}

///|
/// The origin (scheme and host) of a URL.
fn url_origin(url : String) -> String? {
  match split_once(url, "://") {
    Some((scheme, rest)) =>
      match rest.find("/") {
        Some(index) =>
          Some(scheme + "://" + rest.exact_view(start=0, end=index).to_owned())
        None => Some(scheme + "://" + rest)
      }
    None => None
  }
}

///|
/// WorkOS issuers must use TLS unless they are a local development server.
fn workos_issuer_allowed(issuer : String) -> Bool {
  match split_once(issuer, "://") {
    Some((scheme, rest)) => {
      let host = match rest.find("/") {
        Some(index) => rest.exact_view(start=0, end=index).to_owned()
        None => rest
      }
      if scheme == "https" {
        true
      } else if scheme == "http" {
        host == "localhost" || host == "127.0.0.1" || host == "[::1]"
      } else {
        false
      }
    }
    None => false
  }
}

///|
/// Fetch the OIDC block advertised by the API.
async fn fetch_oidc_config(api_url : String) -> Result[Json, String] {
  let config = match
    unauthenticated_json(trim_trailing_slash(api_url) + "/config") {
    Ok(config) => config
    Err(error) =>
      return Err("failed to fetch the login configuration: \{error}")
  }
  match json_object(config, "oidc") {
    Some(oidc) => Ok(oidc)
    None =>
      Err(
        "this API does not advertise browser login; use `daytona login --api-key`",
      )
  }
}

///|
/// Fetch an OIDC discovery document.
async fn fetch_discovery(issuer : String) -> Result[Json, String] {
  let url = trim_trailing_slash(issuer) + "/.well-known/openid-configuration"
  match unauthenticated_json(url) {
    Ok(document) => Ok(document)
    Err(error) => Err("failed to discover the login provider: \{error}")
  }
}

///|
/// Resolve the provider advertised by the API.
async fn resolve_login_provider(
  api_url : String,
) -> Result[LoginProvider, String] {
  let oidc = match fetch_oidc_config(api_url) {
    Ok(oidc) => oidc
    Err(error) => return Err(error)
  }
  let provider = json_string_or_empty(oidc, "provider").to_lower()
  let cli = json_object(oidc, "cli")
  let advertised_issuer = json_string_or_empty(oidc, "issuer")
  let advertised_client = json_string_or_empty(oidc, "clientId")
  let (issuer, client_id) = match cli {
    Some(cli) =>
      if json_string_or_empty(cli, "issuer") != "" &&
        json_string_or_empty(cli, "clientId") != "" {
        (
          json_string_or_empty(cli, "issuer"),
          json_string_or_empty(cli, "clientId"),
        )
      } else {
        (advertised_issuer, advertised_client)
      }
    None => (advertised_issuer, advertised_client)
  }
  if provider == "workos" {
    let issuer = normalize_issuer(issuer)
    if !workos_issuer_allowed(issuer) {
      return Err("the WorkOS issuer must use https: \{issuer}")
    }
    let origin = match url_origin(issuer) {
      Some(origin) => origin
      None => return Err("invalid WorkOS issuer: \{issuer}")
    }
    if client_id == "" {
      return Err("the API did not advertise a WorkOS client ID")
    }
    return Ok({
      auth_url: origin + "/user_management/authorize",
      token_url: origin + "/user_management/authenticate",
      client_id,
      redirect_uri: callback_url(),
      scope: "",
      audience: "",
      issuer: "",
      jwks_uri: "",
      workos_issuer: Some(issuer),
    })
  }
  // Auth0 (or another OIDC provider). Build-time values can override the
  // advertised ones, matching the Go CLI's environment variables.
  let env_domain = @env.get_env_var("DAYTONA_AUTH0_DOMAIN")
  let env_client = @env.get_env_var("DAYTONA_AUTH0_CLIENT_ID")
  let env_audience = @env.get_env_var("DAYTONA_AUTH0_AUDIENCE")
  let issuer = match env_domain {
    Some(domain) if domain.length() > 0 => normalize_issuer(domain)
    _ => normalize_issuer(issuer)
  }
  let client_id = match env_client {
    Some(client) if client.length() > 0 => client
    _ => client_id
  }
  if issuer == "" || client_id == "" {
    return Err(
      "this API does not advertise browser login; use `daytona login --api-key`",
    )
  }
  let discovery = match fetch_discovery(issuer) {
    Ok(discovery) => discovery
    Err(error) => return Err(error)
  }
  let auth_url = json_string_or_empty(discovery, "authorization_endpoint")
  let token_url = json_string_or_empty(discovery, "token_endpoint")
  if auth_url == "" || token_url == "" {
    return Err("the login provider did not advertise authorization endpoints")
  }
  // The ID token names the issuer as the discovery document wrote it (Auth0
  // includes a trailing slash), so compare against that exact value.
  let id_token_issuer = match json_string(discovery, "issuer") {
    Some(value) if value.length() > 0 => value
    _ => issuer
  }
  Ok({
    auth_url,
    token_url,
    client_id,
    redirect_uri: callback_url(),
    scope: "openid offline_access profile",
    audience: match env_audience {
      Some(audience) => audience
      None => ""
    },
    issuer: id_token_issuer,
    jwks_uri: json_string_or_empty(discovery, "jwks_uri"),
    workos_issuer: None,
  })
}

///|
/// Base64url without padding, as required by PKCE.
fn base64url_raw(bytes : Bytes) -> String {
  @base64.encode(bytes, url_safe=true).trim_end(chars="=").to_owned()
}

///|
/// Build the authorization URL.
fn authorization_url(
  provider : LoginProvider,
  state : String,
  challenge : String,
) -> String {
  let params : Array[(String, String)] = [
    ("response_type", "code"),
    ("client_id", provider.client_id),
    ("redirect_uri", provider.redirect_uri),
    ("state", state),
    ("code_challenge", challenge),
    ("code_challenge_method", "S256"),
  ]
  if provider.scope != "" {
    params.push(("scope", provider.scope))
  }
  if provider.audience != "" {
    params.push(("audience", provider.audience))
  }
  if provider.workos_issuer is Some(_) {
    params.push(("provider", "authkit"))
  }
  let encoded : Array[String] = []
  for pair in params {
    encoded.push(url_encode(pair.0) + "=" + url_encode(pair.1))
  }
  let separator = if provider.auth_url.contains("?") { "&" } else { "?" }
  provider.auth_url + separator + encoded.join("&")
}

///|
/// Read one query parameter from a raw query string.
fn query_param(query : String, name : String) -> String? {
  for raw_pair in query.split("&") {
    let pair = raw_pair.to_owned()
    match split_once(pair, "=") {
      Some((key, value)) =>
        if url_decode(key) == name {
          return Some(url_decode(value))
        }
      None => if url_decode(pair) == name { return Some("") }
    }
  }
  None
}

///|
/// Send a small HTML response.
async fn send_html(
  conn : @http.ServerConnection,
  status : Int32,
  reason : String,
  html : String,
) -> Unit {
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.set(@http.CaseInsensitiveString("Content-Type"), "text/html")
  conn.send_response(status, reason, extra_headers=headers)
  conn.write_string(html)
  conn.end_response()
}

///|
/// Escape text embedded in the callback page.
fn html_escape(text : String) -> String {
  let buf = StringBuilder()
  for char in text {
    match char {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&#39;")
      _ => buf.write_char(char)
    }
  }
  buf.to_string()
}

///|
/// The page shown after a successful login.
fn success_page() -> String {
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>Daytona CLI</title>" +
  "<style>body{font-family:system-ui,sans-serif;max-width:36rem;margin:4rem auto;padding:0 1rem;color:#111}" +
  "h1{font-size:1.5rem}</style></head><body><h1>Login successful</h1>" +
  "<p>You can close this window and return to the terminal.</p></body></html>"
}

///|
/// Accept one callback request and classify it.
async fn accept_callback(
  server : @http.Server,
  expected_state : String,
) -> CallbackEvent {
  let (conn, _) = server.accept() catch { _ => return CallbackIgnored }
  defer conn.close()
  let request = conn.read_request() catch { _ => return CallbackIgnored }
  let (route, query) = match split_once(request.path, "?") {
    Some((route, query)) => (route, query)
    None => (request.path, "")
  }
  if route != "/callback" {
    send_html(conn, 404, "Not Found", "<h1>Not Found</h1>")
    return CallbackIgnored
  }
  let state = match query_param(query, "state") {
    Some(state) => state
    None => ""
  }
  if state != expected_state {
    send_html(conn, 400, "Bad Request", "<h1>Invalid state</h1>")
    return CallbackFailure("invalid state parameter")
  }
  match query_param(query, "error") {
    Some(error) => {
      let description = match query_param(query, "error_description") {
        Some(description) => description
        None => ""
      }
      let message = if description == "" {
        error
      } else {
        error + ": " + description
      }
      send_html(
        conn,
        401,
        "Unauthorized",
        "<h1>Login failed</h1><p>\{html_escape(message)}</p>",
      )
      return CallbackFailure(message)
    }
    None => ()
  }
  match query_param(query, "code") {
    Some(code) if code.length() > 0 => {
      send_html(conn, 200, "OK", success_page())
      CallbackCode(code)
    }
    _ => {
      send_html(conn, 400, "Bad Request", "<h1>No code in callback</h1>")
      CallbackFailure("no code in callback")
    }
  }
}

///|
/// POST an application/x-www-form-urlencoded request.
async fn oauth_post_form(
  url : String,
  form : String,
) -> Result[(Int32, Json, String), String] {
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.set(
    @http.CaseInsensitiveString("Content-Type"),
    "application/x-www-form-urlencoded",
  )
  headers.set(@http.CaseInsensitiveString("Accept"), "application/json")
  headers.set(
    @http.CaseInsensitiveString("Content-Length"),
    @encoding.encode(UTF8, form).length().to_string(),
  )
  let (response, body) = @http.request(
    url,
    @http.RequestMethod::Post,
    headers,
    form,
  ) catch {
    error => return Err("failed to connect to \{url}: \{error}")
  }
  let text = body.text() catch { _ => "" }
  let parsed = if text.length() == 0 {
    Json::null()
  } else {
    @json.parse(text) catch {
      _ => Json::null()
    }
  }
  Ok((response.code, parsed, text))
}

///|
/// Decode a base64url JWT segment, adding padding when needed.
fn base64url_decode(text : String) -> Bytes? {
  let mut padded = text
  while padded.length() % 4 != 0 {
    padded = padded + "="
  }
  Some(@base64.decode(padded, url_safe=true)) catch {
    _ => None
  }
}

///|
/// Read the `exp` claim from a JWT without verifying it. The API verifies the
/// token; this only schedules the next refresh.
fn jwt_expiry_millis(token : String) -> Int64? {
  let parts = token.split(".").collect()
  if parts.length() != 3 {
    return None
  }
  let payload = match base64url_decode(parts[1].to_owned()) {
    Some(payload) => payload
    None => return None
  }
  let text = @encoding.decoder(UTF8).decode_lossy(payload)
  let parsed = Some(@json.parse(text)) catch { _ => None }
  match parsed {
    Some(claims) =>
      match json_number(claims, "exp") {
        Some(exp) => Some(exp.to_int64() * 1000L)
        None => None
      }
    None => None
  }
}

///|
/// Convert a token endpoint response into the stored token.
fn token_from_response(
  response : Json,
  provider : LoginProvider,
) -> Result[Token, String] {
  let access_token = json_string_or_empty(response, "access_token")
  if access_token == "" {
    return Err(oauth_error_message(response, response.stringify()))
  }
  let refresh_token = json_string_or_empty(response, "refresh_token")
  let expires_at = match json_number(response, "expires_in") {
    Some(seconds) if seconds > 0.0 => {
      let now = @env.now().reinterpret_as_int64() / 1_000L
      iso_from_seconds(now + seconds.to_int64())
    }
    _ =>
      match jwt_expiry_millis(access_token) {
        Some(millis) => iso_from_seconds(millis / 1000L)
        None =>
          return Err("the login provider returned a token without an expiry")
      }
  }
  Ok({
    access_token,
    refresh_token,
    expires_at,
    issuer: provider.workos_issuer,
    client_id: if provider.workos_issuer is Some(_) {
      Some(provider.client_id)
    } else {
      None
    },
  })
}

///|
/// Exchange the authorization code for tokens.
async fn exchange_code(
  provider : LoginProvider,
  code : String,
  verifier : String,
) -> Result[Token, String] {
  let form = [
    ("grant_type", "authorization_code"),
    ("code", code),
    ("client_id", provider.client_id),
    ("redirect_uri", provider.redirect_uri),
    ("code_verifier", verifier),
  ]
  let encoded : Array[String] = []
  for pair in form {
    encoded.push(url_encode(pair.0) + "=" + url_encode(pair.1))
  }
  let (status, response, raw) = match
    oauth_post_form(provider.token_url, encoded.join("&")) {
    Ok(result) => result
    Err(error) => return Err(error)
  }
  if status < 200 || status >= 300 {
    return Err(oauth_error_message(response, raw))
  }
  match verify_id_token(provider, response) {
    Ok(_) => ()
    Err(error) => return Err("failed to verify ID token: \{error}")
  }
  token_from_response(response, provider)
}

///|
/// A signing key from the provider's JWKS.
priv struct RsaSigningKey {
  modulus : @bigint.BigInt
  exponent : @bigint.BigInt
}

///|
/// Decode a base64url JWK value into a big integer.
fn base64url_bigint(text : String) -> @bigint.BigInt? {
  match base64url_decode(text) {
    Some(bytes) => Some(@bigint.BigInt::from_octets(bytes))
    None => None
  }
}

///|
/// Pick the RSA signing key named by the token's `kid`, or the first usable
/// RS256 key when the token does not name one.
fn select_signing_key(
  jwks : Json,
  kid : String?,
) -> Result[RsaSigningKey, String] {
  for key in json_array(jwks, "keys") {
    if json_string_or_empty(key, "kty") != "RSA" {
      continue
    }
    let key_id = json_string_or_empty(key, "kid")
    let kid_matches = match kid {
      Some(wanted) => key_id == wanted
      None => true
    }
    if !kid_matches {
      continue
    }
    let algorithm = json_string_or_empty(key, "alg")
    if algorithm != "" && algorithm != "RS256" {
      continue
    }
    let key_use = json_string_or_empty(key, "use")
    if key_use != "" && key_use != "sig" {
      continue
    }
    let modulus_text = json_string_or_empty(key, "n")
    let exponent_text = json_string_or_empty(key, "e")
    if modulus_text == "" || exponent_text == "" {
      continue
    }
    match (base64url_bigint(modulus_text), base64url_bigint(exponent_text)) {
      (Some(modulus), Some(exponent)) => return Ok({ modulus, exponent, })
      _ => ()
    }
  }
  Err("the provider did not publish a matching RS256 signing key")
}

///|
/// Verify an RSASSA-PKCS1-v1_5 SHA-256 signature (RS256, RFC 8017 §8.2).
/// MoonBit's BigInt supplies the modular exponentiation, so no native crypto
/// dependency is needed and the static build stays self-contained.
fn verify_rs256(
  key : RsaSigningKey,
  signature : Bytes,
  message : String,
) -> Bool {
  let key_bytes = (key.modulus.bit_length() + 7) / 8
  // A PKCS#1 v1.5 block needs at least 11 bytes of overhead plus the digest
  // prefix and the 32-byte SHA-256 hash.
  if key_bytes < 64 || signature.length() != key_bytes {
    return false
  }
  let signature_value = @bigint.BigInt::from_octets(signature)
  if signature_value.compare(key.modulus) >= 0 {
    return false
  }
  let encoded = signature_value
    .pow(key.exponent, modulus=key.modulus)
    .to_octets(length=key_bytes)
  let digest = @crypto.sha256(@encoding.encode(UTF8, message))
  let digest_info : Array[Byte] = [
    b'\x30', b'\x31', b'\x30', b'\x0d', b'\x06', b'\x09', b'\x60', b'\x86', b'\x48',
    b'\x01', b'\x65', b'\x03', b'\x04', b'\x02', b'\x01', b'\x05', b'\x00', b'\x04',
    b'\x20',
  ]
  let padding = key_bytes - digest_info.length() - digest.length() - 3
  if padding < 8 {
    return false
  }
  let expected : Array[Byte] = [b'\x00', b'\x01']
  for _ in 0..<padding {
    expected.push(b'\xff')
  }
  expected.push(b'\x00')
  for byte in digest_info {
    expected.push(byte)
  }
  for byte in digest {
    expected.push(byte)
  }
  for index in 0..<expected.length() {
    if expected[index] != encoded[index] {
      return false
    }
  }
  true
}

///|
/// Whether the `aud` claim names this client, as a string or an array.
fn audience_contains(claims : Json, client_id : String) -> Bool {
  match json_get(claims, "aud") {
    Some(String(audience)) => audience == client_id
    Some(Array(items)) => {
      for item in items {
        match item {
          String(audience) => if audience == client_id { return true }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Check the claims that bind an ID token to this login: issuer, audience and
/// expiry. The signature is checked separately.
fn verify_id_token_claims(
  claims : Json,
  issuer : String,
  client_id : String,
  now_seconds : Int64,
) -> Result[Unit, String] {
  let token_issuer = json_string_or_empty(claims, "iss")
  if token_issuer != issuer {
    return Err("the ID token was issued by \{token_issuer}, expected \{issuer}")
  }
  if !audience_contains(claims, client_id) {
    return Err("the ID token is not intended for this CLI")
  }
  let expires = match json_number(claims, "exp") {
    Some(expires) => expires
    None => return Err("the ID token has no expiry")
  }
  if now_seconds.to_double() >= expires {
    return Err("the ID token has expired")
  }
  Ok(())
}

///|
/// Verify an ID token against a JWKS document. Only RS256 is accepted, matching
/// Auth0; `none` and the HMAC algorithms are rejected outright.
fn verify_id_token_with_jwks(
  id_token : String,
  jwks : Json,
  issuer : String,
  client_id : String,
  now_seconds : Int64,
) -> Result[Unit, String] {
  let parts = split_exact(id_token, ".")
  if parts.length() != 3 {
    return Err("the ID token is not a JWT")
  }
  let header_bytes = match base64url_decode(parts[0]) {
    Some(bytes) => bytes
    None => return Err("could not decode the ID token header")
  }
  let header_text = @encoding.decoder(UTF8).decode_lossy(header_bytes)
  let parsed_header = Some(@json.parse(header_text)) catch { _ => None }
  let header = match parsed_header {
    Some(header) => header
    None => return Err("could not parse the ID token header")
  }
  let algorithm = json_string_or_empty(header, "alg")
  if algorithm != "RS256" {
    return Err("unsupported ID token algorithm: \{algorithm}")
  }
  let key = match
    select_signing_key(jwks, json_nullable_string(header, "kid")) {
    Ok(key) => key
    Err(error) => return Err(error)
  }
  let signature = match base64url_decode(parts[2]) {
    Some(signature) => signature
    None => return Err("could not decode the ID token signature")
  }
  // The signature covers the token's original header and payload segments,
  // not their re-encoded forms.
  if !verify_rs256(key, signature, parts[0] + "." + parts[1]) {
    return Err("the ID token signature is invalid")
  }
  let payload_bytes = match base64url_decode(parts[1]) {
    Some(bytes) => bytes
    None => return Err("could not decode the ID token claims")
  }
  let claims_text = @encoding.decoder(UTF8).decode_lossy(payload_bytes)
  let parsed_claims = Some(@json.parse(claims_text)) catch { _ => None }
  let claims = match parsed_claims {
    Some(claims) => claims
    None => return Err("could not parse the ID token claims")
  }
  verify_id_token_claims(claims, issuer, client_id, now_seconds)
}

///|
/// Verify the ID token returned by an Auth0 token exchange. WorkOS answers with
/// an access token only and leaves validation to the API, so it is skipped.
async fn verify_id_token(
  provider : LoginProvider,
  response : Json,
) -> Result[Unit, String] {
  if provider.workos_issuer is Some(_) {
    return Ok(())
  }
  let id_token = json_string_or_empty(response, "id_token")
  if id_token == "" {
    return Err("no id_token in token response")
  }
  if provider.issuer == "" || provider.jwks_uri == "" {
    return Err(
      "the login provider did not advertise the ID token issuer and signing keys",
    )
  }
  let jwks = match unauthenticated_json(provider.jwks_uri) {
    Ok(jwks) => jwks
    Err(error) =>
      return Err("failed to fetch the ID token signing keys: \{error}")
  }
  let now = @env.now().reinterpret_as_int64() / 1_000L
  verify_id_token_with_jwks(
    id_token,
    jwks,
    provider.issuer,
    provider.client_id,
    now,
  )
}

///|
/// Store a browser-login token on the active profile, creating the initial
/// profile when the config is empty.
async fn login_with_token(token : Token) -> Result[Profile, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let profile = match active_profile(config) {
    Ok(profile) =>
      if profile.id == "env" {
        return Err(
          "DAYTONA_API_KEY and DAYTONA_API_URL are set; environment credentials take precedence over the config file",
        )
      } else {
        profile
      }
    Err(error) =>
      if error.has_prefix("no profiles found") {
        let profile = initial_profile()
        add_profile(config, profile)
        profile
      } else {
        return Err(error)
      }
  }
  let updated : Profile = {
    id: profile.id,
    name: profile.name,
    url: profile.url,
    key: None,
    token: Some(token),
    active_org: profile.active_org,
  }
  match update_profile(config, updated) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match save_config(config) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(updated)
}

///|
/// After login, keep the stored organization when the user is still a member,
/// otherwise select the personal organization.
async fn select_organization_after_login(
  profile : Profile,
) -> Result[Unit, String] {
  let organizations = match api_get("/organizations") {
    Ok(Array(items)) => items
    Ok(_) => return Err("unexpected response while listing organizations")
    Err(error) => return Err(error)
  }
  let mut selected = personal_organization_id(organizations)
  match profile.active_org {
    Some(stored) if stored.length() > 0 =>
      for organization in organizations {
        if json_string_or_empty(organization, "id") == stored {
          selected = stored
          break
        }
      }
    _ => ()
  }
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let updated : Profile = {
    id: profile.id,
    name: profile.name,
    url: profile.url,
    key: profile.key,
    token: profile.token,
    active_org: Some(selected),
  }
  match update_profile(config, updated) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  save_config(config)
}

///|
/// Run the browser login flow.
pub async fn login_with_browser() -> Result[Unit, String] {
  let api_url = match login_api_url() {
    Ok(url) => url
    Err(error) => return Err(error)
  }
  let provider = match resolve_login_provider(api_url) {
    Ok(provider) => provider
    Err(error) => return Err(error)
  }
  let state = @base64.encode(random_bytes(32), url_safe=true)
  let verifier = base64url_raw(random_bytes(32))
  let challenge = base64url_raw(
    Bytes::from_iter(@crypto.sha256(@encoding.encode(UTF8, verifier)).iter()),
  )
  let auth_url = authorization_url(provider, state, challenge)
  let port = match parse_decimal(callback_port()) {
    Some(port) if port > 0 && port < 65536 => port
    _ => return Err("invalid DAYTONA_AUTH0_CALLBACK_PORT")
  }
  let addr = @socket.Addr::parse("[::]:\{port}") catch {
    _ => return Err("invalid callback address")
  }
  let server = @http.Server(addr, reuse_addr=true) catch {
    error =>
      return Err(
        "failed to start the login callback server on port \{port}: \{error}",
      )
  }
  info("Opening the browser for authentication ...")
  info("")
  info("If opening fails, visit:")
  info("")
  out(auth_url)
  match open_browser(auth_url) {
    Ok(_) => ()
    Err(_) => ()
  }
  let mut code : String? = None
  let mut failure : String? = None
  while code is None && failure is None {
    match accept_callback(server, state) {
      CallbackCode(value) => code = Some(value)
      CallbackFailure(message) => failure = Some(message)
      CallbackIgnored => ()
    }
  }
  server.close()
  match failure {
    Some(message) => return Err("authentication failed: \{message}")
    None => ()
  }
  let code = match code {
    Some(code) => code
    None => return Err("authentication failed: no code in callback")
  }
  let token = match exchange_code(provider, code, verifier) {
    Ok(token) => token
    Err(error) => return Err("failed to exchange token: \{error}")
  }
  let profile = match login_with_token(token) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  match select_organization_after_login(profile) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  success("Successfully logged in!")
  Ok(())
}

///|
/// Whether the stored access token expires within five minutes.
pub fn token_needs_refresh(profile : Profile) -> Bool {
  let token = match profile.token {
    Some(token) => token
    None => return false
  }
  let expires = match parse_iso_millis(token.expires_at) {
    Some(expires) => expires
    None => return false
  }
  let now = @env.now().reinterpret_as_int64()
  now + 300_000L >= expires
}

///|
/// The token another process stored while this one was refreshing. Daytona
/// processes share the config file and WorkOS rotates refresh tokens: when
/// another process (for example the MCP server) refreshed first, this one's
/// refresh token is already spent and fails with `invalid_grant`, while the
/// stored replacement is still valid.
async fn token_rotated_elsewhere(spent_refresh_token : String) -> Token? {
  let config = match load_config() {
    Ok(config) => config
    Err(_) => return None
  }
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(_) => return None
  }
  match profile.token {
    Some(token) if token.access_token.length() > 0 &&
      token.refresh_token != spent_refresh_token => Some(token)
    _ => None
  }
}

///|
/// Refresh an OAuth access token. WorkOS rotates refresh tokens, so the
/// returned token replaces the stored one.
pub async fn refresh_access_token(profile : Profile) -> Result[Token, String] {
  let token = match profile.token {
    Some(token) => token
    None =>
      return Err("no valid token found, use `daytona login` to reauthenticate")
  }
  if token.refresh_token == "" {
    return Err("session expired, use `daytona login` to reauthenticate")
  }
  let provider = match (token.issuer, token.client_id) {
    (Some(issuer), Some(client_id)) if issuer.length() > 0 &&
      client_id.length() > 0 => {
      let origin = match url_origin(issuer) {
        Some(origin) => origin
        None => return Err("invalid stored WorkOS issuer")
      }
      {
        auth_url: origin + "/user_management/authorize",
        token_url: origin + "/user_management/authenticate",
        client_id,
        redirect_uri: callback_url(),
        scope: "",
        audience: "",
        issuer: "",
        jwks_uri: "",
        workos_issuer: Some(issuer),
      }
    }
    _ => {
      let api_url = match login_api_url() {
        Ok(url) => url
        Err(error) => return Err(error)
      }
      match resolve_login_provider(api_url) {
        Ok(provider) => provider
        Err(error) => return Err(error)
      }
    }
  }
  let form = [
    ("grant_type", "refresh_token"),
    ("refresh_token", token.refresh_token),
    ("client_id", provider.client_id),
  ]
  let encoded : Array[String] = []
  for pair in form {
    encoded.push(url_encode(pair.0) + "=" + url_encode(pair.1))
  }
  let (status, response, raw) = match
    oauth_post_form(provider.token_url, encoded.join("&")) {
    Ok(result) => result
    Err(error) => return Err(error)
  }
  if status < 200 || status >= 300 {
    let message = oauth_error_message(response, raw)
    if message.contains("invalid_grant") {
      match token_rotated_elsewhere(token.refresh_token) {
        Some(rotated) => return Ok(rotated)
        None => return Err("use `daytona login` to reauthenticate: \{message}")
      }
    }
    return Err("failed to refresh the access token, please retry: \{message}")
  }
  let refreshed = match token_from_response(response, provider) {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  // Providers that do not rotate refresh tokens may omit the field.
  if refreshed.refresh_token == "" {
    Ok({
      access_token: refreshed.access_token,
      refresh_token: token.refresh_token,
      expires_at: refreshed.expires_at,
      issuer: refreshed.issuer,
      client_id: refreshed.client_id,
    })
  } else {
    Ok(refreshed)
  }
}

///|
/// Persist a refreshed token on the active profile.
pub async fn save_refreshed_token(
  profile : Profile,
  token : Token,
) -> Result[Unit, String] {
  if profile.id == "env" {
    return Ok(())
  }
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let updated : Profile = {
    id: profile.id,
    name: profile.name,
    url: profile.url,
    key: profile.key,
    token: Some(token),
    active_org: profile.active_org,
  }
  match update_profile(config, updated) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  save_config(config)
}
