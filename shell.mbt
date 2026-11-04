///|
/// Browser launching and shell completion setup.

///|
/// The user's home directory, or "." when HOME is unset.
pub fn home_directory() -> String {
  match @env.get_env_var("HOME") {
    Some(home) if home.length() > 0 => home
    _ => "."
  }
}

///|
/// Start a browser launcher without waiting for the browser to exit.
async fn try_launch(command : String, args : Array[String]) -> Bool {
  let pid = @process.spawn_orphan(command, args) catch { _ => -1 }
  pid > 0
}

///|
/// Open a URL in the platform's default browser. The launcher is detached so a
/// browser that stays in the foreground cannot block the caller.
pub async fn open_browser(url : String) -> Result[Unit, String] {
  let windows = platform() == 2
  let launched = if windows {
    try_launch("cmd", ["/c", "start", "", url])
  } else {
    let first = try_launch("xdg-open", [url])
    if first {
      true
    } else {
      try_launch("open", [url])
    }
  }
  if launched {
    Ok(())
  } else {
    Err("failed to open the browser")
  }
}

///|
/// The words offered by the generated completion scripts.
fn completion_words() -> String {
  "archive autocomplete create delete docs exec help info list login logout mcp organization pause preview-url sandbox snapshot ssh start stop version volume"
}

///|
/// Generate the completion script body for a shell.
pub fn completion_script(shell : String) -> String {
  let words = completion_words()
  if shell == "bash" {
    "_daytona_completion() {\n" +
    "  local cur=\"${COMP_WORDS[COMP_CWORD]}\"\n" +
    "  COMPREPLY=( $(compgen -W \"\{words}\" -- \"$cur\") )\n" +
    "}\n" +
    "complete -F _daytona_completion daytona\n"
  } else if shell == "zsh" {
    "#compdef daytona\n" +
    "_daytona() {\n" +
    "  local -a commands\n" +
    "  commands=(\{words})\n" +
    "  _describe 'command' commands\n" +
    "}\n" +
    "compdef _daytona daytona\n"
  } else if shell == "fish" {
    let buf = StringBuilder()
    for word in words.split(" ") {
      buf.write_string("complete -c daytona -f -a '\{word}'\n")
    }
    buf.to_string()
  } else if shell == "powershell" {
    "Register-ArgumentCompleter -Native -CommandName daytona -ScriptBlock {\n" +
    "  param($wordToComplete, $commandAst, $cursorPosition)\n" +
    "  @(\"" +
    words.split(" ").join("\",\"") +
    "\") | Where-Object { $_ -like \"$wordToComplete*\" } | ForEach-Object {\n" +
    "    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)\n" +
    "  }\n" +
    "}\n"
  } else {
    ""
  }
}

///|
/// Write the completion script and source it from the shell profile.
pub async fn setup_autocompletion(shell : String) -> Result[String, String] {
  let home = home_directory()
  let (script_path, profile_path, source_line) = if shell == "bash" {
    (
      home + "/.daytona.completion_script.bash",
      home + "/.bashrc",
      "\nsource \{home}/.daytona.completion_script.bash\n",
    )
  } else if shell == "zsh" {
    (
      home + "/.daytona.completion_script.zsh",
      home + "/.zshrc",
      "\nsource \{home}/.daytona.completion_script.zsh\n",
    )
  } else if shell == "fish" {
    (
      home + "/.config/fish/daytona.completion_script.fish",
      home + "/.config/fish/config.fish",
      "\nsource \{home}/.config/fish/daytona.completion_script.fish\n",
    )
  } else if shell == "powershell" {
    (
      home + "/daytona.completion_script.ps1",
      home + "/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1",
      ".\{home}/daytona.completion_script.ps1\n",
    )
  } else {
    return Err(
      "unsupported shell type. Please use bash, zsh, fish, or powershell",
    )
  }
  // Create parent directories for fish and powershell profiles.
  if shell == "fish" {
    @fs.mkdir(home + "/.config/fish", recursive=true, allow_exist=true) catch {
      _ => ()
    }
  } else if shell == "powershell" {
    @fs.mkdir(
      home + "/Documents/WindowsPowerShell",
      recursive=true,
      allow_exist=true,
    ) catch {
      _ => ()
    }
  }
  let script = completion_script(shell)
  @fs.write_file(
    script_path,
    script,
    permission=0o644,
    create_mode=CreateOrTruncate,
  ) catch {
    error => return Err("error creating completion script file: \{error}")
  }
  let existing = (@fs.read_file(profile_path) catch { _ => "" }).text() catch {
    _ => ""
  }
  if !existing.contains(source_line.trim()) {
    let combined = existing + source_line
    @fs.write_file(
      profile_path,
      combined,
      permission=0o644,
      create_mode=CreateOrTruncate,
    ) catch {
      error =>
        return Err("error writing to profile file (\{profile_path}): \{error}")
    }
  }
  Ok(profile_path)
}
