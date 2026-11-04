///|
/// Small helpers shared by the command layer: string handling, JSON access,
/// time formatting and process exit.

///|
/// Exit with a specific status. Kept in one place so every command reports the
/// same way a shell expects.
extern "C" fn daytona_exit(status : Int32) -> Unit = "daytona_exit"

///|
/// Host platform: 0 = Linux/other Unix, 1 = macOS, 2 = Windows.
extern "C" fn daytona_platform() -> Int32 = "daytona_platform"

///|
/// The host platform, used where paths differ from Linux.
pub fn platform() -> Int32 {
  daytona_platform()
}

///|
/// Fill a fresh byte buffer from the operating system's random source.
#borrow(buffer)
extern "C" fn daytona_random_bytes(buffer : Bytes, length : Int32) -> Unit = "daytona_random_bytes"

///|
/// Cryptographic random bytes for OAuth state and PKCE verifiers.
pub fn random_bytes(length : Int32) -> Bytes {
  let buffer = Bytes::make(length, 0)
  daytona_random_bytes(buffer, length)
  buffer
}

///|
/// Whether a file descriptor is attached to a terminal.
extern "C" fn daytona_isatty(fd : Int32) -> Int32 = "daytona_isatty"

///|
/// True when standard input is interactive.
pub fn stdin_is_terminal() -> Bool {
  daytona_isatty(0) != 0
}

///|
/// A value that may be absent, used instead of nullable strings throughout the
/// CLI model.

///|
/// Read a string member from a JSON object.
pub fn json_string(value : Json, key : String) -> String? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
/// Read a required string member, returning "" when it is absent or not a
/// string. The API's required fields always use this shape.
pub fn json_string_or_empty(value : Json, key : String) -> String {
  match json_string(value, key) {
    Some(text) => text
    None => ""
  }
}

///|
/// Read a boolean member.
pub fn json_bool(value : Json, key : String) -> Bool? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
/// Read a number member as an integer.
pub fn json_int(value : Json, key : String) -> Int32? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Number(number, ..)) => Some(number.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Read an array member.
pub fn json_array(value : Json, key : String) -> Array[Json] {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Array(items)) => items
        _ => []
      }
    _ => []
  }
}

///|
/// Read an object member.
pub fn json_object(value : Json, key : String) -> Json? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Object(_) as object) => Some(object)
        _ => None
      }
    _ => None
  }
}

///|
/// Read any member.
pub fn json_get(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
/// A JSON number member.
pub fn json_number(value : Json, key : String) -> Double? {
  match json_get(value, key) {
    Some(Number(number, ..)) => Some(number)
    Some(String(text)) => {
      let parsed = Some(@json.parse(text)) catch { _ => None }
      match parsed {
        Some(Number(number, ..)) => Some(number)
        _ => None
      }
    }
    _ => None
  }
}

///|
/// A JSON string member, or `None` for JSON null and missing fields.
pub fn json_nullable_string(value : Json, key : String) -> String? {
  match json_get(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
/// Build a JSON object from key/value pairs.
pub fn object_of(pairs : Array[(String, Json)]) -> Json {
  let fields : Map[String, Json] = Map([])
  for pair in pairs {
    let (key, value) = pair
    fields.set(key, value)
  }
  Json::object(fields)
}

///|
/// Percent-encode one path segment. The API accepts IDs and names in path
/// position, and names may contain spaces or slashes, so every reserved byte is
/// escaped.
pub fn url_encode(text : String) -> String {
  let buf = StringBuilder()
  for char in text {
    let value = char.to_int()
    let safe = (value >= 48 && value <= 57) ||
      (value >= 65 && value <= 90) ||
      (value >= 97 && value <= 122) ||
      value == 45 ||
      value == 46 ||
      value == 95 ||
      value == 126
    if safe {
      buf.write_char(Int32::unsafe_to_char(value))
    } else {
      buf.write_string("%")
      buf.write_string(hex_byte(value))
    }
  }
  buf.to_string()
}

///|
/// Decode a percent-encoded URL component. Invalid escapes are kept verbatim
/// rather than failing the whole callback.
pub fn url_decode(text : String) -> String {
  let bytes : Array[Byte] = []
  let mut index = 0
  while index < text.length() {
    let char = text.get_char(index).unwrap()
    if char == '%' && index + 2 < text.length() {
      let high = hex_value(text.get_char(index + 1).unwrap())
      let low = hex_value(text.get_char(index + 2).unwrap())
      match (high, low) {
        (Some(high), Some(low)) => {
          bytes.push((high * 16 + low).to_byte())
          index = index + 3
          continue
        }
        _ => ()
      }
    }
    if char == '+' {
      bytes.push(b' ')
    } else {
      for byte in @encoding.encode(UTF8, char.to_string()) {
        bytes.push(byte)
      }
    }
    index = index + 1
  }
  @encoding.decoder(UTF8).decode_lossy(Bytes::from_array(bytes))
}

///|
/// Hex digit value.
fn hex_value(char : Char) -> Int32? {
  let code = char.to_int()
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else if code >= 65 && code <= 70 {
    Some(code - 55)
  } else if code >= 97 && code <= 102 {
    Some(code - 87)
  } else {
    None
  }
}

///|
/// Uppercase hexadecimal for one byte, two digits.
fn hex_byte(value : Int32) -> String {
  let digits = "0123456789ABCDEF"
  let high = value / 16
  let low = value % 16
  digits.exact_view(start=high, end=high + 1).to_owned() +
  digits.exact_view(start=low, end=low + 1).to_owned()
}

///|
/// Split `text` on `separator`, keeping empty fields. MoonBit's `StringView`
/// split drops trailing empty fields in some versions, so this is explicit.
pub fn split_exact(text : String, separator : String) -> Array[String] {
  let out : Array[String] = []
  let mut rest = text
  while true {
    match rest.find(separator) {
      Some(index) => {
        out.push(rest.exact_view(start=0, end=index).to_owned())
        rest = rest
          .exact_view(start=index + separator.length(), end=rest.length())
          .to_owned()
      }
      None => {
        out.push(rest)
        break
      }
    }
  }
  out
}

///|
/// Split the first occurrence of `separator` into two fields.
pub fn split_once(text : String, separator : String) -> (String, String)? {
  match text.find(separator) {
    Some(index) =>
      Some(
        (
          text.exact_view(start=0, end=index).to_owned(),
          text
          .exact_view(start=index + separator.length(), end=text.length())
          .to_owned(),
        ),
      )
    None => None
  }
}

///|
/// Parse an integer flag value.
pub fn parse_int_flag(text : String, name : String) -> Result[Int32, String] {
  match parse_decimal(text) {
    Some(value) => Ok(value)
    None => Err("invalid value for --\{name}: '\{text}' is not an integer")
  }
}

///|
/// Parse a signed decimal integer without relying on an exception-raising
/// stdlib helper, so flag validation can report its own error.
pub fn parse_decimal(text : String) -> Int32? {
  if text.length() == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  if text.get_char(0).unwrap() == '-' {
    negative = true
    index = 1
  } else if text.get_char(0).unwrap() == '+' {
    index = 1
  }
  if index >= text.length() {
    return None
  }
  let mut value = 0
  while index < text.length() {
    let char = text.get_char(index).unwrap()
    if char < '0' || char > '9' {
      return None
    }
    value = value * 10 + (char.to_int() - 48)
    index = index + 1
  }
  if negative {
    Some(-value)
  } else {
    Some(value)
  }
}

///|
/// Parse `KEY=VALUE`, the format used by `--env`, `--label` and `--volume`.
pub fn parse_pair(
  text : String,
  flag : String,
) -> Result[(String, String), String] {
  match split_once(text, "=") {
    Some((key, value)) =>
      if key == "" {
        Err("invalid value for --\{flag}: '\{text}' is missing a name")
      } else {
        Ok((key, value))
      }
    None => Err("invalid value for --\{flag}: '\{text}' must use NAME=VALUE")
  }
}

///|
/// Render an integer option as JSON.
pub fn int_json(value : Int32) -> Json {
  Json::number(value.to_double())
}

///|
/// Render ISO-8601 timestamps as a short "time since" label, matching the Go
/// CLI's `util.GetTimeSinceLabelFromString`.
pub fn time_since_label(timestamp : String, now_millis : Int64) -> String {
  match parse_iso_millis(timestamp) {
    Some(then_millis) => {
      let delta = now_millis - then_millis
      if delta < 60_000L {
        "< 1 minute ago"
      } else if delta < 3_600_000L {
        let minutes = delta / 60_000L
        if minutes == 1L {
          "1 minute ago"
        } else {
          "\{minutes} minutes ago"
        }
      } else if delta < 86_400_000L {
        let hours = delta / 3_600_000L
        if hours == 1L {
          "1 hour ago"
        } else {
          "\{hours} hours ago"
        }
      } else {
        let days = delta / 86_400_000L
        if days == 1L {
          "1 day ago"
        } else {
          "\{days} days ago"
        }
      }
    }
    None => "/"
  }
}

///|
/// Parse `YYYY-MM-DDTHH:MM:SS` (optionally with a fractional part and zone).
/// The API always emits UTC timestamps, so the zone suffix is ignored.
pub fn parse_iso_millis(timestamp : String) -> Int64? {
  if timestamp.length() < 19 {
    return None
  }
  let year = parse_digits(timestamp, 0, 4)
  let month = parse_digits(timestamp, 5, 7)
  let day = parse_digits(timestamp, 8, 10)
  let hour = parse_digits(timestamp, 11, 13)
  let minute = parse_digits(timestamp, 14, 16)
  let second = parse_digits(timestamp, 17, 19)
  match (year, month, day, hour, minute, second) {
    (Some(y), Some(mo), Some(d), Some(h), Some(mi), Some(se)) =>
      if mo < 1 || mo > 12 || d < 1 || d > 31 {
        None
      } else {
        let days = days_from_civil(y, mo, d)
        Some(
          (
            days * 86_400L +
            h.to_int64() * 3_600L +
            mi.to_int64() * 60L +
            se.to_int64()
          ) *
          1000L,
        )
      }
    _ => None
  }
}

///|
/// Parse a fixed-width decimal field.
fn parse_digits(text : String, start : Int32, end : Int32) -> Int32? {
  if end > text.length() {
    return None
  }
  let mut value = 0
  for index in start..<end {
    let code = text.get_char(index).unwrap().to_int()
    if code < 48 || code > 57 {
      return None
    }
    value = value * 10 + (code - 48)
  }
  Some(value)
}

///|
/// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's
/// algorithm), used to compare API timestamps with the current clock.
fn days_from_civil(year : Int32, month : Int32, day : Int32) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = if y >= 0 { y / 400 } else { (y - 399) / 400 }
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era.to_int64() * 146_097L + doe.to_int64() - 719_468L
}

///|
/// Terminal width, falling back to 80 columns when the size cannot be read.
pub fn terminal_width() -> Int32 {
  // The preview and CI environments rarely expose a tty. A fixed 100-column
  // table is readable in both and avoids an FFI call for one cosmetic value.
  100
}

///|
/// Pad `text` to `width` characters with spaces.
pub fn pad_right(text : String, width : Int32) -> String {
  if text.length() >= width {
    return text
  }
  let buf = StringBuilder()
  buf.write_string(text)
  for _ in 0..<(width - text.length()) {
    buf.write_char(' ')
  }
  buf.to_string()
}

///|
/// Pad `text` on the left to `width` characters with spaces.
pub fn pad_left(text : String, width : Int32) -> String {
  if text.length() >= width {
    return text
  }
  let buf = StringBuilder()
  for _ in 0..<(width - text.length()) {
    buf.write_char(' ')
  }
  buf.write_string(text)
  buf.to_string()
}

///|
/// Shorten `text` with an ellipsis when it does not fit.
pub fn truncate(text : String, width : Int32) -> String {
  if text.length() <= width {
    return text
  }
  if width <= 1 {
    return "…"
  }
  text.exact_view(start=0, end=width - 1).to_owned() + "…"
}

///|
/// Exit the process with the given status code.
pub fn exit_with(status : Int32) -> Unit {
  daytona_exit(status)
}
