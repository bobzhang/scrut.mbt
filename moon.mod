name = "bobzhang/scrut"

version = "0.1.4"

readme = "README.md"

repository = "https://github.com/bobzhang/scrut.mbt"

license = "MIT"

keywords = [ "cli", "testing", "cram", "snapshot" ]

description = "CLI testing in Markdown and Cram files (port of facebookincubator/scrut), the engine for `moon cram`"

import {
  "moonbitlang/async@0.22.10",
  "moonbitlang/x@0.5.9",
  "moonbit-community/yaml@0.0.10",
}

preferred_target = "native"

warnings = "-implicit_impl_as_method"
