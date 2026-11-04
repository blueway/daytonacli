"use strict";

// Unit tests for the launcher's platform mapping and URL construction. Run
// with `node --test` from this directory.

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const lib = require("./lib.js");

test("maps every supported Node platform-arch to a release target", () => {
  assert.equal(lib.TARGETS["linux-x64"], "linux-x86_64");
  assert.equal(lib.TARGETS["linux-arm64"], "linux-aarch64");
  assert.equal(lib.TARGETS["darwin-arm64"], "darwin-aarch64");
  assert.equal(Object.keys(lib.TARGETS).length, 3);
});

test("resolves the repository slug from package.json", () => {
  assert.equal(lib.repoSlug(), "kupas/daytona");
});

test("falls back from the pinned version to latest", () => {
  const urls = lib.downloadUrls("linux-x86_64");
  assert.equal(urls.length, 2);
  assert.match(
    urls[0],
    /^https:\/\/github\.com\/kupas\/daytona\/releases\/download\/v\d+\.\d+\.\d+\/daytona-linux-x86_64$/
  );
  assert.equal(
    urls[1],
    "https://github.com/kupas/daytona/releases/latest/download/daytona-linux-x86_64"
  );
});

test("DAYTONA_DOWNLOAD_BASE replaces both default URLs", () => {
  const saved = process.env.DAYTONA_DOWNLOAD_BASE;
  process.env.DAYTONA_DOWNLOAD_BASE = "https://mirror.example.com/daytona/";
  try {
    assert.deepEqual(lib.downloadUrls("darwin-aarch64"), [
      "https://mirror.example.com/daytona/daytona-darwin-aarch64",
    ]);
  } finally {
    if (saved === undefined) delete process.env.DAYTONA_DOWNLOAD_BASE;
    else process.env.DAYTONA_DOWNLOAD_BASE = saved;
  }
});

test("DAYTONA_VERSION wins over the package version and tolerates a v prefix", () => {
  const saved = process.env.DAYTONA_VERSION;
  process.env.DAYTONA_VERSION = "v9.9.9";
  try {
    assert.equal(lib.version(), "9.9.9");
    assert.match(lib.downloadUrls("linux-aarch64")[0], /\/v9\.9\.9\//);
  } finally {
    if (saved === undefined) delete process.env.DAYTONA_VERSION;
    else process.env.DAYTONA_VERSION = saved;
  }
});

test("the cache directory can be redirected", () => {
  const saved = process.env.DAYTONA_CACHE_DIR;
  process.env.DAYTONA_CACHE_DIR = "/tmp/daytona-test-cache";
  try {
    assert.equal(lib.cacheDir(), "/tmp/daytona-test-cache");
    assert.equal(
      lib.binaryPath("linux-x86_64"),
      path.join("/tmp/daytona-test-cache", `daytona-${lib.version()}-linux-x86_64`)
    );
  } finally {
    if (saved === undefined) delete process.env.DAYTONA_CACHE_DIR;
    else process.env.DAYTONA_CACHE_DIR = saved;
  }
});

test("DAYTONA_BINARY short-circuits every download path", async () => {
  const saved = process.env.DAYTONA_BINARY;
  process.env.DAYTONA_BINARY = "/bin/sh";
  try {
    assert.equal(await lib.ensureBinary(), "/bin/sh");
  } finally {
    if (saved === undefined) delete process.env.DAYTONA_BINARY;
    else process.env.DAYTONA_BINARY = saved;
  }
});

test("DAYTONA_BINARY pointing nowhere is a clear error", async () => {
  const saved = process.env.DAYTONA_BINARY;
  process.env.DAYTONA_BINARY = "/nonexistent/daytona";
  try {
    await assert.rejects(lib.ensureBinary(), /does not exist/);
  } finally {
    if (saved === undefined) delete process.env.DAYTONA_BINARY;
    else process.env.DAYTONA_BINARY = saved;
  }
});

test("an unsupported platform explains itself", async () => {
  const saved = process.env.DAYTONA_BINARY;
  delete process.env.DAYTONA_BINARY;
  const realPlatform = process.platform;
  const realArch = process.arch;
  try {
    Object.defineProperty(process, "platform", { value: "sunos" });
    Object.defineProperty(process, "arch", { value: "sparc" });
    await assert.rejects(lib.ensureBinary(), /does not ship a binary/);
  } finally {
    Object.defineProperty(process, "platform", { value: realPlatform });
    Object.defineProperty(process, "arch", { value: realArch });
    if (saved === undefined) delete process.env.DAYTONA_BINARY;
    else process.env.DAYTONA_BINARY = saved;
  }
});
