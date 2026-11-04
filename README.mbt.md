# Daytona CLI in MoonBit

A native rewrite of the [Daytona](https://www.daytona.io) command line client.
It manages sandboxes, snapshots, volumes, organizations and the MCP server, and
reads the same `config.json` as the Go CLI, so both clients can share a login.

The binary is compiled ahead of time with MoonBit's native backend. Linux
releases are linked statically against musl, so they run on any distribution
regardless of its glibc version. OpenSSL is linked in as well: a static binary
has no dynamic loader, so the HTTPS client's usual `dlopen("libssl.so.3")` is
redirected to the built-in copy (see `scripts/static-openssl.c`).

## Build

```sh
moon update
moon check --target native --deny-warn
moon test --target native
moon build --target native --release
./_build/native/release/build/cmd/daytona/daytona.exe version
```

For a fully static Linux binary:

```sh
sudo apt-get install -y musl-tools perl make curl
./scripts/build-linux-static.sh dist/daytona-linux-x86_64
```

The first run downloads and builds OpenSSL for musl (~9 MB of archives) and
keeps it in `.cache/openssl-musl`, so later builds are as fast as a normal
`moon build`. Delete that directory to pick up a new OpenSSL.

## Authenticate

```sh
daytona login                  # browser login, or choose an API key
daytona login --api-key "$DAYTONA_API_KEY"
daytona logout
```

On a terminal, `login` offers browser authentication and API-key entry. Browser
login uses OAuth 2.0 Authorization Code with PKCE and a loopback callback on
`http://localhost:3009/callback`; override the port with
`DAYTONA_AUTH0_CALLBACK_PORT`. Access tokens are refreshed automatically before
they expire. The provider is read from the API's `/config` endpoint (WorkOS when
advertised, Auth0 otherwise); `DAYTONA_AUTH0_DOMAIN`,
`DAYTONA_AUTH0_CLIENT_ID` and `DAYTONA_AUTH0_AUDIENCE` override Auth0 settings.

Credentials live in `~/.config/daytona/config.json` (or
`~/Library/Application Support/daytona` on macOS). `DAYTONA_API_URL` and
`DAYTONA_API_KEY` override the file for CI:

```sh
DAYTONA_API_URL=https://app.daytona.io/api DAYTONA_API_KEY=... daytona list
```

## Sandboxes

```sh
daytona create --snapshot ubuntu:24.04 --name demo
daytona list
daytona info demo
daytona start demo
daytona stop demo
daytona pause demo
daytona archive demo
daytona ssh demo
daytona exec demo -- uname -a
daytona preview-url demo --port 3000
daytona delete demo
daytona delete --all
```

`create` accepts `--env/-e KEY=VALUE`, `--label/-l KEY=VALUE`,
`--volume/-v VOLUME:MOUNT_PATH`, resource flags (`--cpu`, `--gpu`, `--memory`,
`--disk`), lifecycle flags (`--auto-stop`, `--auto-pause`, `--auto-archive`,
`--auto-delete`, `--ttl`, `--queue-timeout`) and `--network-block-all`,
`--network-allow-list`, `--kvm`.

The deprecated `daytona sandbox <command>` group still works as an alias.

## Snapshots

```sh
daytona snapshot list
daytona snapshot create my-image --image alpine:3.19
daytona snapshot activate my-image
daytona snapshot push local:1.0 --name my-image
daytona snapshot delete my-image
daytona snapshot delete --all
```

## Volumes

```sh
daytona volume list
daytona volume create data
daytona volume get data
daytona volume resolve data
daytona volume delete data
```

## Organizations

```sh
daytona organization list
daytona organization create acme --region us
daytona organization use acme
daytona organization members acme
daytona organization delete acme
```

## Structured output

Commands that read a resource accept `--format json|yaml`, including `list`,
`info`, `snapshot list`, `volume list`, `volume get`, `organization list` and
`organization members`.

## MCP server

```sh
daytona mcp config
daytona mcp init claude
daytona mcp start
```

`mcp start` speaks newline-delimited JSON-RPC over stdio. It exposes sandbox
lifecycle, command execution, preview links, file operations and Git clone.

## Shell completion

```sh
daytona autocomplete bash    # or zsh, fish, powershell
```

The script is written under `$HOME` and sourced from the shell profile.

## Layout

| Path | Contents |
| --- | --- |
| `cli.mbt` | root command tree and aliases |
| `oauth.mbt` | browser login, PKCE callback server and token refresh |
| `cmd/daytona/` | executable entry point |
| `cli_args.mbt` | Cobra-compatible flag parser |
| `config.mbt` | config file, profiles and tokens |
| `api.mbt` | API client, headers and toolbox proxy |
| `sandbox_cmds.mbt`, `snapshot_cmds.mbt`, `volume_cmds.mbt`, `organization_cmds.mbt` | command groups |
| `mcp_cmds.mbt` | MCP stdio server and agent configuration |
| `output.mbt` | tables, info blocks and JSON/YAML output |
| `scripts/build-linux-static.sh`, `static-openssl.c` | static release build and its dlopen shim |

## Known differences from the Go client

- Dockerfile builds (`create --dockerfile`, `snapshot create --dockerfile`) are
  rejected. Build the image locally and use `daytona snapshot push`, or pass
  `--image` to `snapshot create`.
- The MCP server exposes the sandbox, file, Git, command and preview tools.
  Computer-use tools are not included.
