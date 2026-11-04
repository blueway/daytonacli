///|
/// A small, dependency-free argument parser.
///
/// Cobra's grammar is the compatibility target: long and short flags, values
/// attached with `=` or passed as the next argument, repeated flags, `--` to
/// end option parsing, and aliases. Help and version are ordinary flags.

///|
/// One accepted flag.
pub(all) struct FlagSpec {
  long : String
  short : String
  takes_value : Bool
  repeatable : Bool
}

///|
/// Parse results.
pub(all) struct ParsedArgs {
  positionals : Array[String]
  values : Map[String, String]
  flags : Map[String, Bool]
  lists : Map[String, Array[String]]
  changed : Map[String, Bool]
  rest : Array[String]
  mut help : Bool
}

///|
/// Describe a boolean flag.
pub fn bflag(long : String, short : String) -> FlagSpec {
  { long, short, takes_value: false, repeatable: false, }
}

///|
/// Describe a flag that takes one value.
pub fn vflag(long : String, short : String) -> FlagSpec {
  { long, short, takes_value: true, repeatable: false, }
}

///|
/// Describe a repeatable flag.
pub fn lflag(long : String, short : String) -> FlagSpec {
  { long, short, takes_value: true, repeatable: true, }
}

///|
/// Find a spec by long name.
fn spec_by_long(specs : Array[FlagSpec], name : String) -> FlagSpec? {
  for spec in specs {
    if spec.long == name {
      return Some(spec)
    }
  }
  None
}

///|
/// Find a spec by short name.
fn spec_by_short(specs : Array[FlagSpec], name : String) -> FlagSpec? {
  for spec in specs {
    if spec.short == name {
      return Some(spec)
    }
  }
  None
}

///|
/// Store one flag occurrence.
fn record_value(result : ParsedArgs, spec : FlagSpec, value : String) -> Unit {
  result.changed.set(spec.long, true)
  if spec.repeatable {
    let list = result.lists.get_or_init(spec.long, () => [])
    list.push(value)
  } else {
    result.values.set(spec.long, value)
  }
}

///|
/// Parse the arguments after the command name.
pub fn parse_args(
  args : Array[String],
  specs : Array[FlagSpec],
) -> Result[ParsedArgs, String] {
  let result : ParsedArgs = {
    positionals: [],
    values: Map([]),
    flags: Map([]),
    lists: Map([]),
    changed: Map([]),
    rest: [],
    help: false,
  }
  let mut index = 0
  let mut options_done = false
  while index < args.length() {
    let arg = args[index]
    if options_done {
      result.positionals.push(arg)
      index = index + 1
      continue
    }
    if arg == "--" {
      options_done = true
      index = index + 1
      while index < args.length() {
        result.positionals.push(args[index])
        index = index + 1
      }
      break
    }
    if arg == "--help" || arg == "-h" {
      result.help = true
      index = index + 1
      continue
    }
    if arg.has_prefix("--") {
      let body = arg.exact_view(start=2, end=arg.length()).to_owned()
      let (name, inline_value) = match split_once(body, "=") {
        Some((name, value)) => (name, Some(value))
        None => (body, None)
      }
      let spec = match spec_by_long(specs, name) {
        Some(spec) => spec
        None => return Err("unknown flag: --\{name}")
      }
      if spec.takes_value {
        let value = match inline_value {
          Some(value) => value
          None => {
            if index + 1 >= args.length() {
              return Err("flag needs an argument: --\{name}")
            }
            index = index + 1
            args[index]
          }
        }
        record_value(result, spec, value)
      } else {
        if inline_value is Some(_) {
          return Err("flag does not take a value: --\{name}")
        }
        result.changed.set(spec.long, true)
        result.flags.set(spec.long, true)
      }
      index = index + 1
      continue
    }
    if arg.has_prefix("-") && arg.length() > 1 {
      let short = arg.exact_view(start=1, end=2).to_owned()
      let attached = if arg.length() > 2 {
        Some(arg.exact_view(start=2, end=arg.length()).to_owned())
      } else {
        None
      }
      let spec = match spec_by_short(specs, short) {
        Some(spec) => spec
        None => return Err("unknown flag: -\{short}")
      }
      if spec.takes_value {
        let value = match attached {
          Some(value) if value.has_prefix("=") =>
            value.exact_view(start=1, end=value.length()).to_owned()
          Some(value) => value
          None => {
            if index + 1 >= args.length() {
              return Err("flag needs an argument: -\{short}")
            }
            index = index + 1
            args[index]
          }
        }
        record_value(result, spec, value)
      } else {
        if attached is Some(_) {
          return Err("unknown flag: \{arg}")
        }
        result.changed.set(spec.long, true)
        result.flags.set(spec.long, true)
      }
      index = index + 1
      continue
    }
    result.positionals.push(arg)
    index = index + 1
  }
  Ok(result)
}

///|
/// A flag's string value, or "" when absent.
pub fn arg_value(result : ParsedArgs, name : String) -> String {
  match result.values.get(name) {
    Some(value) => value
    None => ""
  }
}

///|
/// A flag's integer value, or the supplied default.
pub fn arg_int(result : ParsedArgs, name : String, default : Int32) -> Int32 {
  match result.values.get(name) {
    Some(value) =>
      match parse_decimal(value) {
        Some(number) => number
        None => default
      }
    None => default
  }
}

///|
/// Whether a boolean flag was set.
pub fn arg_bool(result : ParsedArgs, name : String) -> Bool {
  result.flags.get(name) is Some(true)
}

///|
/// Whether a flag appeared at all, including with its default value.
pub fn arg_changed(result : ParsedArgs, name : String) -> Bool {
  result.changed.get(name) is Some(true)
}

///|
/// A repeatable flag's values, or an empty array.
pub fn arg_list(result : ParsedArgs, name : String) -> Array[String] {
  match result.lists.get(name) {
    Some(values) => values
    None => []
  }
}

///|
/// Require exactly `count` positionals.
pub fn require_positionals(
  result : ParsedArgs,
  count : Int32,
  usage : String,
) -> Result[Unit, String] {
  if result.positionals.length() != count {
    if result.positionals.length() < count {
      Err("missing argument. Usage: \{usage}")
    } else {
      Err("too many arguments. Usage: \{usage}")
    }
  } else {
    Ok(())
  }
}

///|
/// Require at least `count` positionals.
pub fn require_min_positionals(
  result : ParsedArgs,
  count : Int32,
  usage : String,
) -> Result[Unit, String] {
  if result.positionals.length() < count {
    Err("missing argument. Usage: \{usage}")
  } else {
    Ok(())
  }
}

///|
/// Require at most `count` positionals.
pub fn require_max_positionals(
  result : ParsedArgs,
  count : Int32,
  usage : String,
) -> Result[Unit, String] {
  if result.positionals.length() > count {
    Err("too many arguments. Usage: \{usage}")
  } else {
    Ok(())
  }
}

///|
/// The value of a mutually exclusive flag group: at most one may be set.
pub fn check_exclusive(
  result : ParsedArgs,
  names : Array[String],
) -> Result[Unit, String] {
  let mut seen = ""
  for name in names {
    if arg_changed(result, name) {
      if seen != "" {
        return Err("flags --\{seen} and --\{name} cannot be used together")
      }
      seen = name
    }
  }
  Ok(())
}
