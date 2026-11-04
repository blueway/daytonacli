// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
/// A fixed RS256 ID token and the JWKS that verifies it. The signing key was a
/// throwaway and is not kept, so the test needs neither a network nor a secret.
let test_id_token : String = "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5IiwidHlwIjoiSldUIn0.eyJpc3MiOiJodHRwczovL2xvZ2luLmV4YW1wbGUudGVzdC8iLCJhdWQiOiJ0ZXN0LWNsaWVudCIsImV4cCI6NDEwMjQ0NDgwMCwic3ViIjoidXNlcl8xIn0.EK7lXmHVYnTcl7sFMFnq_8lTbTMM1kog9hJ3R1fJssA7qAKDQpgZ6EELyUaTg8skFYZoHlDxhwstEBHpIW-M0Xnk5AWn-asYlmAqnRcObC5aksY1JqJgrTWKnYtC__sBaoceaQtjH0uml4ef39jdlT2ceVYv8Ok9vfdQlUNUtbT39iRzHhx-cp8AY__ydxUgAPFzIwVUGMruJ5duMA6uvzcqe-htV7zxNbupOgkiVAAmclIjL7wRU445kyqteHuaIGkNh90_xyRPSZCNbEVBYHAhV89lnlxYGnflodQP5T2IAjLX8miGAnf2QmAL6XbLppQtA5otPl-EI3V6wKOZlw"

///|
let test_jwks_json : String = "{\"keys\":[{\"kty\":\"RSA\",\"kid\":\"test-key\",\"use\":\"sig\",\"alg\":\"RS256\",\"n\":\"uqx5MFVNV7P-EciYd20dpmQaQSMFPI-f1-ZZYlMJLQ0dA3fh1yZo0lIPr4YLKCWP3jaJU83pmCWSaOaGxUaNe0o4LGnPraSfRJiKYkUrAx5gDeKbZYg-uXgIr9hxmt2CfxiqzZQgsbViuU_s8BQujiURc6Y8dgF-onNn7g2Kgdd23uG-BLBLPFNb3ip3_DuVyh-7J5EXBOQE2TJTBejr79tt07rdjAvfXNSD2o-_FLXZfA6xLpEt-g8GOsLu5Ms6-B4n3j3DP_wYhUgvktBUHZY5-PiOC2iGMfAfnTQqb1c3CF_tySklrLPUfCbH1mH9H216uz-cWr1Utn5m2D8o1Q\",\"e\":\"AQAB\"}]}"

///|
let test_issuer : String = "https://login.example.test/"

///|
let test_client_id : String = "test-client"

///|
fn test_jwks() -> Json {
  @json.parse(test_jwks_json) catch {
    _ => Json::null()
  }
}

///|
test "verifies an RS256 id token" {
  assert_true(
    verify_id_token_with_jwks(
      test_id_token,
      test_jwks(),
      test_issuer,
      test_client_id,
      1_700_000_000L,
    )
    is Ok(_),
  )
}

///|
test "rejects a tampered RS256 id token" {
  let parts = split_exact(test_id_token, ".")
  let payload = parts[1]
  let tampered = parts[0] +
    "." +
    "A" +
    payload.exact_view(start=1, end=payload.length()).to_owned() +
    "." +
    parts[2]
  assert_true(
    verify_id_token_with_jwks(
      tampered,
      test_jwks(),
      test_issuer,
      test_client_id,
      1_700_000_000L,
    )
    is Err(_),
  )
}

///|
test "rejects an expired or misaddressed id token" {
  let jwks = test_jwks()
  // The token expires at 2100-01-01 (4102444800 in seconds).
  assert_true(
    verify_id_token_with_jwks(
      test_id_token, jwks, test_issuer, test_client_id, 4_102_444_800L,
    )
    is Err(_),
  )
  assert_true(
    verify_id_token_with_jwks(
      test_id_token, jwks, test_issuer, "another-client", 1_700_000_000L,
    )
    is Err(_),
  )
  assert_true(
    verify_id_token_with_jwks(
      test_id_token, jwks, "https://evil.example.test/", test_client_id, 1_700_000_000L,
    )
    is Err(_),
  )
}

///|
test "rejects an unsigned id token" {
  let parts = split_exact(test_id_token, ".")
  let header = @base64.encode(
    @encoding.encode(UTF8, "{\"alg\":\"none\",\"kid\":\"test-key\"}"),
    url_safe=true,
  )
  let unsigned = header + "." + parts[1] + ".AA"
  assert_true(
    verify_id_token_with_jwks(
      unsigned,
      test_jwks(),
      test_issuer,
      test_client_id,
      1_700_000_000L,
    )
    is Err(_),
  )
}
