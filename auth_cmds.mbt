///|
/// `daytona login` and `daytona logout`.

///|
/// The profile created on first login.
fn initial_profile() -> Profile {
  {
    id: "initial",
    name: "initial",
    url: default_api_url,
    key: None,
    token: None,
    active_org: None,
  }
}

///|
/// Store an API key on the active profile, creating the initial profile when
/// the config is empty.
pub async fn login_with_api_key(key : String) -> Result[Unit, String] {
  if key.length() == 0 {
    return Err("API key cannot be empty")
  }
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
    key: Some(key),
    token: None,
    active_org: profile.active_org,
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
/// Clear the stored credentials. The profile itself is kept so the endpoint
/// and active organization survive a logout.
pub async fn logout() -> Result[Unit, String] {
  let config = match load_config() {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let profile = match active_profile(config) {
    Ok(profile) => profile
    Err(error) => return Err(error)
  }
  let updated : Profile = {
    id: profile.id,
    name: profile.name,
    url: profile.url,
    key: None,
    token: None,
    active_org: profile.active_org,
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
/// `daytona login [--api-key KEY]`.
pub async fn cmd_login(args : Array[String]) -> Result[Unit, String] {
  let specs = [vflag("api-key", "")]
  let parsed = match parse_args(args, specs) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Log in to Daytona")
    out("")
    out("Usage: daytona login [--api-key KEY]")
    out("")
    out("Options:")
    out("      --api-key string   API key to use for authentication")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona login [--api-key KEY]") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let explicit_key = arg_value(parsed, "api-key")
  if explicit_key != "" {
    return store_api_key(explicit_key)
  }
  match @env.get_env_var("DAYTONA_API_KEY") {
    Some(env_key) if env_key.length() > 0 => return store_api_key(env_key)
    _ => ()
  }
  let use_browser = if stdin_is_terminal() {
    let choice = match
      prompt_select("Select Authentication Method", [
        "Login with Browser", "Set Daytona API Key",
      ]) {
      Ok(choice) => choice
      Err(error) => return Err(error)
    }
    if choice == 1 {
      let key = match prompt_api_key() {
        Ok(key) => key
        Err(error) => return Err(error)
      }
      return store_api_key(key)
    }
    true
  } else {
    true
  }
  if use_browser {
    login_with_browser()
  } else {
    Err("no authentication method selected")
  }
}

///|
/// Store an API key and report success.
async fn store_api_key(key : String) -> Result[Unit, String] {
  match login_with_api_key(key) {
    Ok(_) => {
      success("Successfully set Daytona API key!")
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// Prompt for an API key on the terminal.
async fn prompt_api_key() -> Result[String, String] {
  out("Enter your Daytona API key")
  out(
    "You can find it in the Daytona dashboard - https://app.daytona.io/dashboard",
  )
  @stdio.stdout.write("API key: ")
  let line = @stdio.stdin.read_until("\n") catch { _ => None }
  let key = match line {
    Some(text) => text.trim().to_owned()
    None => ""
  }
  if key == "" {
    return Err("API key cannot be empty")
  }
  Ok(key)
}

///|
/// `daytona logout`.
pub async fn cmd_logout(args : Array[String]) -> Result[Unit, String] {
  let parsed = match parse_args(args, []) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  if parsed.help {
    out("Logout from Daytona")
    out("")
    out("Usage: daytona logout")
    return Ok(())
  }
  match require_max_positionals(parsed, 0, "daytona logout") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match logout() {
    Ok(_) => {
      success("Successfully logged out")
      Ok(())
    }
    Err(error) => Err(error)
  }
}
