# `@kupas/daytona`

The npm launcher for the Daytona CLI, rewritten in MoonBit.

```sh
npm install -g @kupas/daytona
daytona login --api-key "$DAYTONA_API_KEY"
daytona create --snapshot ubuntu:24.04 --name demo
daytona list
daytona ssh demo
```

## What this package contains

A small launcher, not the binary itself. On the first `daytona` run it
downloads the prebuilt native binary for your platform from the GitHub release
and caches it. Nothing is downloaded at install time.

| Platform | Target |
| --- | --- |
| Linux x86-64 | `daytona-linux-x86_64` (static, musl) |
| Linux arm64 | `daytona-linux-aarch64` (static, musl) |
| macOS Apple silicon | `daytona-darwin-aarch64` |

The Linux builds are linked statically against musl, so they run on any
distribution regardless of its glibc version. OpenSSL is linked into the
binary too, so HTTPS keeps working without a system OpenSSL.

## Why there is no `postinstall`

This package deliberately declares **no install script**. npm 12 blocks
dependency lifecycle scripts unless the user opts in, and pnpm 12 fails a
project install with `ERR_PNPM_IGNORED_BUILDS` when a dependency declares one.
Downloading lazily from `bin/daytona.js` works under npm, pnpm, yarn, bun,
`npx`, and `--ignore-scripts`.

## Cache location

The downloaded binary is kept outside the package, so reinstalling or clearing
`node_modules` never triggers a second download:

| Platform | Path |
| --- | --- |
| Linux | `$XDG_CACHE_HOME/daytona` or `~/.cache/daytona` |
| macOS | `~/Library/Caches/daytona` |

## Environment overrides

`DAYTONA_REPO`, `DAYTONA_VERSION`, `DAYTONA_DOWNLOAD_BASE`,
`DAYTONA_CACHE_DIR`, `DAYTONA_BINARY`, `DAYTONA_FORCE_DOWNLOAD`,
`DAYTONA_SKIP_DOWNLOAD`, and `DAYTONA_NO_VERIFY` behave as described in
`lib.js`.
