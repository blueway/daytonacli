// Daytona CLI, rewritten in MoonBit.
//
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "kupas/daytona"

version = "0.1.3"

readme = "README.mbt.md"

repository = "https://github.com/kupas/daytona-moonbit"

license = "Apache-2.0"

keywords = [ "daytona", "sandbox", "cli", "moonbit" ]

description = "Daytona CLI: manage Daytona sandboxes, snapshots, volumes and organizations"

preferred_target = "native"

import {
  "moonbitlang/async@0.22.4",
  "moonbitlang/x@0.5.5",
}
