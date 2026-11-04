///|
/// Argument parser behavior, including the grammar the Go CLI's Cobra parser
/// accepts.
test "parses long and short flags" {
  let specs = [
    @daytona.vflag("limit", "l"),
    @daytona.bflag("all", "a"),
    @daytona.lflag("env", "e"),
  ]
  let parsed = match
    @daytona.parse_args(
      ["--limit=25", "-a", "-e", "A=1", "--env", "B=2", "sandbox"],
      specs,
    ) {
    Ok(parsed) => parsed
    Err(_) => fail("expected the arguments to parse")
  }
  assert_eq(@daytona.arg_int(parsed, "limit", 0), 25)
  assert_true(@daytona.arg_bool(parsed, "all"))
  assert_eq(@daytona.arg_list(parsed, "env"), ["A=1", "B=2"])
  assert_eq(parsed.positionals, ["sandbox"])
}

///|
/// Everything after `--` is a positional, even when it starts with a dash.
test "stops option parsing at a double dash" {
  let parsed = match
    @daytona.parse_args(["demo", "--", "echo", "-n", "hi"], []) {
    Ok(parsed) => parsed
    Err(_) => fail("expected the arguments to parse")
  }
  assert_eq(parsed.positionals, ["demo", "echo", "-n", "hi"])
}

///|
/// Unknown flags and missing values are errors.
test "rejects unknown flags and missing values" {
  assert_true(@daytona.parse_args(["--nope"], []) is Err(_))
  assert_true(
    @daytona.parse_args(["--limit"], [@daytona.vflag("limit", "l")]) is Err(_),
  )
}

///|
/// The structured output formats.
test "renders deterministic yaml" {
  let value = @daytona.json_obj([
    ("name", Json::string("demo")),
    ("count", Json::number(2.0)),
    ("enabled", Json::boolean(true)),
    ("items", Json::array([Json::string("a"), Json::string("b")])),
  ])
  let expected = "name: demo\ncount: 2\nenabled: true\nitems:\n  - a\n  - b"
  assert_eq(@daytona.yaml_json(value, 0), expected)
}

///|
/// URL encoding follows RFC 3986 for the characters that appear in IDs.
test "encodes url components" {
  assert_eq(@daytona.url_encode("a b/c"), "a%20b%2Fc")
  assert_eq(@daytona.url_encode("plain-id_1.2~"), "plain-id_1.2~")
}

///|
/// The age labels used in list tables.
test "formats relative time labels" {
  let now = 1_800_000_000_000L
  assert_eq(
    @daytona.time_since_label("2027-01-15T08:00:00Z", now),
    "< 1 minute ago",
  )
  assert_eq(
    @daytona.time_since_label("2027-01-15T07:30:00Z", now),
    "30 minutes ago",
  )
  assert_eq(
    @daytona.time_since_label("2027-01-15T06:00:00Z", now),
    "2 hours ago",
  )
  assert_eq(
    @daytona.time_since_label("2027-01-10T08:00:00Z", now),
    "5 days ago",
  )
}

///|
/// State labels and priorities.
test "maps sandbox state labels" {
  assert_eq(@daytona.sandbox_state_label("pending_build"), "PENDING BUILD")
  assert_eq(@daytona.sandbox_state_label("started"), "STARTED")
  assert_eq(@daytona.sandbox_state_label("made_up"), "/")
  assert_true(
    @daytona.sandbox_state_priority("started") <
    @daytona.sandbox_state_priority("stopped"),
  )
}

///|
/// Docker image names accepted by `snapshot create --image`.
test "validates image names" {
  assert_true(@daytona.validate_image_name("ubuntu:24.04") is Ok(_))
  assert_true(@daytona.validate_image_name("ubuntu") is Err(_))
  assert_true(@daytona.validate_image_name("ubuntu:latest") is Err(_))
}

///|
/// Tables pad columns but never leave trailing whitespace.
test "renders trimmed tables" {
  let table = @daytona.render_table(["Name", "State"], [
    ["a", "STARTED"],
    ["longer", "OK"],
  ])
  assert_eq(table, "Name    State\na       STARTED\nlonger  OK")
}

///|
/// UUID detection gates the direct volume-by-id lookup.
test "recognizes canonical uuids" {
  assert_true(@daytona.looks_like_uuid("123e4567-e89b-12d3-a456-426614174000"))
  assert_false(@daytona.looks_like_uuid("123e4567e89b12d3a456426614174000"))
  assert_false(@daytona.looks_like_uuid("not-a-uuid"))
}

///|
test "decodes percent encoded urls" {
  assert_eq(@daytona.url_decode("a%20b%2Fc+d"), "a b/c d")
}

///|
test "formats unix seconds as iso" {
  assert_eq(@daytona.iso_from_seconds(0L), "1970-01-01T00:00:00Z")
  assert_eq(@daytona.iso_from_seconds(1_700_000_000L), "2023-11-14T22:13:20Z")
}
