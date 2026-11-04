///|
/// Output helpers: messages, tables, structured formats and info blocks.

///|
/// Write one line to stdout.
pub async fn out(text : String) -> Unit {
  @stdio.stdout.write(text + "\n")
}

///|
/// Write one line to stderr.
pub async fn err(text : String) -> Unit {
  @stdio.stderr.write(text + "\n")
}

///|
/// A bold success line, matching the Go CLI's spacing closely enough for
/// scripts that look for the message.
pub async fn success(text : String) -> Unit {
  out("")
  out("  " + text)
  out("")
}

///|
/// An informational line.
pub async fn info(text : String) -> Unit {
  out(" " + text)
}

///|
/// Render a table with a header row. Columns are separated by two spaces and
/// padded to the widest cell, with no outer border.
pub fn render_table(
  headers : Array[String],
  rows : Array[Array[String]],
) -> String {
  let widths : Array[Int32] = []
  for index in 0..<headers.length() {
    widths.push(headers[index].length())
  }
  for row in rows {
    for index in 0..<row.length() {
      if index < widths.length() && row[index].length() > widths[index] {
        widths[index] = row[index].length()
      }
    }
  }
  let buf = StringBuilder()
  for index in 0..<headers.length() {
    if index > 0 {
      buf.write_string("  ")
    }
    buf.write_string(pad_right(headers[index], widths[index]))
  }
  buf.write_string("\n")
  for row in rows {
    for index in 0..<headers.length() {
      if index > 0 {
        buf.write_string("  ")
      }
      let cell = if index < row.length() { row[index] } else { "" }
      buf.write_string(pad_right(cell, widths[index]))
    }
    buf.write_string("\n")
  }
  let lines : Array[String] = []
  for line in buf.to_string().split("\n") {
    lines.push(line.trim_end(chars=" ").to_owned())
  }
  lines.join("\n").trim_end(chars="\n").to_owned()
}

///|
/// Render a two-column info block. Property names are 16 columns wide, as in
/// the Go CLI.
pub fn render_info(title : String, fields : Array[(String, String)]) -> String {
  let buf = StringBuilder()
  if title != "" {
    buf.write_string("\n")
    buf.write_string(title)
    buf.write_string("\n")
  }
  for field in fields {
    let (name, value) = field
    buf.write_string(pad_right(name, 16))
    buf.write_string(value)
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
/// Structured output requested by `--format`.
pub fn format_structured(value : Json, format : String) -> String {
  if format == "yaml" {
    yaml_json(value, 0)
  } else {
    value.stringify(indent=2)
  }
}

///|
/// Minimal YAML serializer for JSON-shaped API responses. Scalars use plain
/// style unless they need quoting; arrays and objects use block style.
pub fn yaml_json(value : Json, indent : Int32) -> String {
  let buf = StringBuilder()
  yaml_write(buf, value, indent, false)
  buf.to_string().trim_end(chars="\n").to_owned()
}

///|
/// Append one YAML node. `inline` is true for array items that start with `-`.
fn yaml_write(
  buf : StringBuilder,
  value : Json,
  indent : Int32,
  inline : Bool,
) -> Unit {
  match value {
    Null => buf.write_string("null\n")
    True => buf.write_string("true\n")
    False => buf.write_string("false\n")
    Number(_, ..) => {
      buf.write_string(value.stringify())
      buf.write_string("\n")
    }
    String(text) => {
      buf.write_string(yaml_scalar(text))
      buf.write_string("\n")
    }
    Array(items) =>
      if items.length() == 0 {
        buf.write_string("[]\n")
      } else {
        for item in items {
          write_indent(buf, indent)
          buf.write_string("- ")
          match item {
            Object(fields) if fields.length() > 0 => {
              let mut first = true
              for pair in fields {
                let (key, child) = pair
                if first {
                  buf.write_string(yaml_key(key) + ":")
                  yaml_child(buf, child, indent + 2, true)
                  first = false
                } else {
                  write_indent(buf, indent + 2)
                  buf.write_string(yaml_key(key) + ":")
                  yaml_child(buf, child, indent + 4, true)
                }
              }
            }
            Array(_) => {
              buf.write_string("\n")
              yaml_write(buf, item, indent + 2, true)
            }
            _ => yaml_write(buf, item, indent + 2, true)
          }
        }
      }
    Object(fields) =>
      if fields.length() == 0 {
        buf.write_string("{}\n")
      } else {
        for pair in fields {
          let (key, child) = pair
          if !inline {
            write_indent(buf, indent)
          }
          buf.write_string(yaml_key(key) + ":")
          yaml_child(buf, child, indent, false)
        }
      }
  }
}

///|
/// Write a child value, inline for scalars and on the next line for
/// collections.
fn yaml_child(
  buf : StringBuilder,
  child : Json,
  indent : Int32,
  after_dash : Bool,
) -> Unit {
  match child {
    Array(items) if items.length() > 0 => {
      buf.write_string("\n")
      yaml_write(buf, child, indent + 2, false)
    }
    Object(fields) if fields.length() > 0 => {
      buf.write_string("\n")
      yaml_write(buf, child, indent + 2, false)
    }
    _ => {
      buf.write_string(" ")
      yaml_write(buf, child, indent, after_dash)
    }
  }
}

///|
/// Indent helper.
fn write_indent(buf : StringBuilder, indent : Int32) -> Unit {
  for _ in 0..<indent {
    buf.write_char(' ')
  }
}

///|
/// Quote a YAML key when it contains punctuation that would change its
/// meaning.
fn yaml_key(key : String) -> String {
  let mut safe = key.length() > 0
  for char in key {
    let code = char.to_int()
    if !((code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 95 ||
      code == 46) {
      safe = false
    }
  }
  if safe {
    key
  } else {
    Json::string(key).stringify()
  }
}

///|
/// Quote a YAML scalar when plain style would be ambiguous.
fn yaml_scalar(text : String) -> String {
  if text == "" {
    return "\"\""
  }
  let reserved = ["null", "true", "false", "yes", "no", "on", "off", "~"]
  if reserved.contains(text) {
    return Json::string(text).stringify()
  }
  let mut plain = true
  for char in text {
    let code = char.to_int()
    let safe = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 95 ||
      code == 46 ||
      code == 47 ||
      code == 58 ||
      code == 64 ||
      code == 32
    if !safe || char == '\n' || char == '\t' {
      plain = false
    }
  }
  if plain && !text.has_prefix(" ") && !text.has_suffix(" ") {
    text
  } else {
    Json::string(text).stringify(escape_slash=false)
  }
}
