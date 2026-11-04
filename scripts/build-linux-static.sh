#!/usr/bin/env bash
#
# Build a fully static Linux `daytona` with musl.
#
# A glibc build records the build machine's symbol versions, so a binary built
# on a new runner refuses to start on an older distribution
# ("GLIBC_2.38 not found"). Linking against musl statically removes the whole
# class of problem: the result runs on any Linux of the same architecture.
#
# The catch is TLS. The HTTP client loads OpenSSL with dlopen at run time, and
# a static binary has no dynamic loader, so the plain static link failed every
# API command with `TlsError("failed to load OpenSSL")`. OpenSSL is therefore
# built against musl and linked in, and `-Wl,--wrap` redirects dlopen/dlsym to
# scripts/static-openssl.c, which resolves the client's symbol names against
# that static copy.
#
# Usage:
#   scripts/build-linux-static.sh [output-path]
#
# Environment:
#   DAYTONA_OPENSSL_DIR   OpenSSL build cache (default: .cache/openssl-musl).
#                         Delete it to rebuild OpenSSL.
#   DAYTONA_MUSL_WORKDIR  scratch directory (default: a fresh temp dir)
#
# Requires: musl-tools, perl, make, curl (Debian/Ubuntu:
#   `apt-get install -y musl-tools perl make curl`).

set -euo pipefail

openssl_version="3.0.16"
openssl_sha256="57e03c50feab5d31b152af2b764f10379aecd8ee92f16c985983ce4a99f7ef86"

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/dist/daytona-linux-$(uname -m)}"
cache="${DAYTONA_OPENSSL_DIR:-$root/.cache/openssl-musl}"
work="${DAYTONA_MUSL_WORKDIR:-$(mktemp -d)}"

say() { printf '%s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v musl-gcc >/dev/null 2>&1 ||
  die "musl-gcc not found; install musl-tools (apt-get install musl-tools)"
command -v perl >/dev/null 2>&1 ||
  die "perl not found; the OpenSSL build needs it (apt-get install perl)"

# The kernel UAPI headers (linux/*.h, asm/*.h) live in /usr/include, which is
# not on musl-gcc's default search path. Find the multiarch directory too:
# linux/mman.h includes <asm/mman.h> on some distributions.
multiarch=""
for dir in /usr/include/*-linux-gnu; do
  if [ -d "$dir" ]; then
    multiarch="$dir"
    break
  fi
done
[ -n "$multiarch" ] || die "no /usr/include/*-linux-gnu directory found"

# OpenSSL's Configure takes a target name, not just a compiler: configuring
# linux-x86_64 on an aarch64 runner leaves the x86 asm to the arm assembler.
case "$(uname -m)" in
  aarch64 | arm64) openssl_target=linux-aarch64 ;;
  *) openssl_target=linux-x86_64 ;;
esac

mkdir -p "$work"

# --- OpenSSL for musl ------------------------------------------------------
# Sources are unpacked in the cache and kept between runs; the archives are
# reused as long as they exist, so only the first build pays for OpenSSL.
ssl="$cache/openssl-$openssl_version"
if [ ! -f "$cache/libssl.a" ] || [ ! -f "$cache/libcrypto.a" ]; then
  say "daytona: building OpenSSL $openssl_version for musl (cache $cache)"
  mkdir -p "$cache"
  tarball="$cache/openssl-$openssl_version.tar.gz"
  if [ ! -f "$tarball" ]; then
    curl -fsSL -o "$tarball.part" \
      "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz"
    mv "$tarball.part" "$tarball"
  fi
  actual="$(sha256sum "$tarball" | cut -d' ' -f1)"
  if [ "$actual" != "$openssl_sha256" ]; then
    rm -f "$tarball"
    die "OpenSSL tarball checksum mismatch (got $actual)"
  fi
  rm -rf "$ssl"
  tar xzf "$tarball" -C "$cache"
  (
    cd "$ssl"
    # no-shared: static archives only. no-async: no async stack. no-comp: zlib
    # is not needed. no-tests keeps the build short. openssldir matches the
    # Debian/Ubuntu certificate layout, which is what the client verifies with.
    CC="musl-gcc -idirafter /usr/include -idirafter $multiarch" \
      ./Configure "$openssl_target" no-shared no-tests no-comp no-async \
      --prefix="$cache/install" --openssldir=/etc/ssl >"$cache/configure.log" 2>&1 ||
      die "OpenSSL configure failed; see $cache/configure.log"
    make -j"$(nproc)" >"$cache/build.log" 2>&1 ||
      die "OpenSSL build failed; see $cache/build.log"
    cp libssl.a libcrypto.a "$cache/"
  )
  say "daytona: OpenSSL is in $cache"
fi

# --- dlopen shim -----------------------------------------------------------
# The client asks for a fixed list of functions; the table is generated from
# that list so a dependency update cannot leave a silently missing symbol.
client_tls=""
for candidate in \
  "$root/.mooncakes/moonbitlang/async/src/tls/openssl.c" \
  "$HOME/.moon/lib/runtime/openssl.c"; do
  if [ -f "$candidate" ]; then
    client_tls="$candidate"
    break
  fi
done

needed="$work/openssl-needed.txt"
if [ -n "$client_tls" ]; then
  grep -v '#define' "$client_tls" |
    sed -n 's/.*IMPORT_FUNC[A-Z_]*([^,]*, *\([A-Za-z0-9_]*\),.*/\1/p' |
    sort -u >"$needed"
else
  # Without the source the client's list is unknown; fall back to every TLS
  # entry point the archives export, which only costs binary size.
  say "daytona: warning: no OpenSSL client source found; exporting all symbols"
  nm -g --defined-only "$cache/libssl.a" "$cache/libcrypto.a" 2>/dev/null |
    awk '$2 ~ /^[TW]$/ {print $3}' | sort -u >"$needed"
fi
echo "OpenSSL_version_num" >>"$needed"
sort -u -o "$needed" "$needed"
[ "$(wc -l <"$needed")" -gt 20 ] ||
  die "could not find the OpenSSL function list in the client source"

decls="$work/openssl-symbols.h"
table="$work/openssl-symbols-table.h"
defined="$work/openssl-defined.txt"
nm -g --defined-only "$cache/libssl.a" "$cache/libcrypto.a" 2>/dev/null |
  awk '$2 ~ /^[TW]$/ {print $3}' | sort -u >"$defined"
: >"$decls"
: >"$table"
while IFS= read -r name; do
  if grep -qxF "$name" "$defined"; then
    printf 'void %s(void);\n' "$name" >>"$decls"
    printf '  { "%s", (void *)&%s },\n' "$name" "$name" >>"$table"
  else
    die "OpenSSL $openssl_version does not export $name, which the TLS client needs"
  fi
done <"$needed"

musl-gcc -O2 -idirafter /usr/include -idirafter "$multiarch" -I"$work" \
  -c "$root/scripts/static-openssl.c" -o "$work/static-openssl.o"

# --- compiler driver -------------------------------------------------------
cat >"$work/daytona-musl-gcc" <<EOF
#!/bin/sh
# -idirafter keeps musl's libc headers ahead of glibc's while still making the
# kernel UAPI headers reachable; -include limits.h supplies NAME_MAX, which
# glibc's <unistd.h> provides transitively and musl's does not.
common="-idirafter /usr/include -idirafter $multiarch -include limits.h"
for arg in "\$@"; do
  if [ "\$arg" = "-c" ]; then
    # shellcheck disable=SC2086
    exec musl-gcc \$common "\$@"
  fi
done
# Link step: the static OpenSSL archives and the dlopen shim. --wrap applies to
# the references inside the MoonBit runtime and the TLS client. librt/libutil
# are not needed on this musl; libm comes from the build itself.
# shellcheck disable=SC2086
exec musl-gcc \$common "\$@" -static \\
  -Wl,--wrap=dlopen -Wl,--wrap=dlsym -Wl,--wrap=dlclose -Wl,--wrap=dlerror \\
  "$work/static-openssl.o" "$cache/libssl.a" "$cache/libcrypto.a" \\
  -lpthread -lm
EOF
chmod +x "$work/daytona-musl-gcc"
ln -sf "$(command -v ar)" "$work/ar"

# --- build -----------------------------------------------------------------
say "daytona: building a static binary (musl, workdir $work)"
cd "$root"
MOON_CC="$work/daytona-musl-gcc" MOON_AR="$work/ar" \
  moon build --target native --release

bin="$root/_build/native/release/build/cmd/daytona/daytona.exe"
[ -f "$bin" ] || die "build did not produce $bin"

mkdir -p "$(dirname "$out")"
cp "$bin" "$out"
chmod 755 "$out"

# --- verify ----------------------------------------------------------------
say "daytona: wrote $out"
info="$(file -b "$out" || true)"
say "daytona: $info"
case "$info" in
  *"statically linked"*) ;;
  *) die "$out is not statically linked" ;;
esac
if ldd "$out" >/dev/null 2>&1; then
  die "$out is a dynamic executable"
fi
# Static alone is not enough: the TLS entry points have to be inside the
# binary, or every API call would fail at run time.
if ! grep -qaF "OpenSSL 3." "$out"; then
  die "$out does not contain OpenSSL"
fi
say "daytona: verified statically linked with a built-in OpenSSL"
