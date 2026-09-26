// Property: expectations generated from any output match that output
// (so `scrut update` makes documents pass), through the Markdown and Cram
// parsers.

///|
/// Pieces of output that exercise escaping, line handling and the syntax of
/// documents and rules.
let pieces : ReadOnlyArray[Bytes] = [
  b"a", b"b", b" ", b"\t", b"\n", b"\n", b"\r", b"\x1b", b"\x00", b"\x7f", b"\xff",
  b"\xc3\xa9", b"\xe2\x80\xa8", b"\xe2", b"*", b"?", b"(", b")", b"[", b"]", b"\\",
  b"%", b"$", b"`", b"#", b"-", b"\"", b"'", b"1", b"(glob)", b" (re)", b" (?)",
  b" (esc)", b" (no-eol)", b" (equal*)", b"()", b"> ", b">", b"$ ", b"[1]", b"[0]",
  b"```", b"````", b"# ", b"---", b"  ", b"\\x41",
]

///|
fn output_bytes(codes : Array[Int]) -> Bytes {
  let buf = Buffer()
  let n = pieces.length()
  for code in codes {
    buf.write_bytes(pieces[(code % n + n) % n])
  }
  buf.to_bytes()
}

///|
fn outcome_for(
  stdout : Bytes,
  exit_code : Int,
  format : @document.ParserType,
  escaping : @text.Escaper,
) -> @render.Outcome {
  let testcase : @document.TestCase = {
    title: "",
    shell_expression: "prog arg",
    body: Output([]),
    exit_code: None,
    line_number: 1,
    config: @config.TestCaseConfig::empty(),
  }
  let output = { ..@exec.Output::new(Code(exit_code)), stdout, }
  {
    location: None,
    output,
    testcase,
    format,
    escaping,
    result: @exec.validate(testcase, output),
  }
}

///|
fn regenerated_passes(
  codes : Array[Int],
  format : @document.ParserType,
  escaping : @text.Escaper,
) -> Bool raise {
  let stdout = output_bytes(codes)
  // Some runs fail with an exit code (another way expectations are
  // written).
  let exit_code = if codes.length() % 3 == 1 { codes.length() % 4 } else { 0 }
  let outcome = outcome_for(stdout, exit_code, format, escaping)
  let document = match format {
    Markdown => @generate.markdown_testcases([outcome], "scrut")
    Cram => @generate.cram_testcases([outcome])
  }
  let parsed = match format {
    Markdown => @document.parse_markdown(document)
    Cram => @document.parse_cram(document)
  }
  guard parsed.testcases is [testcase] else { return false }
  let output = { ..@exec.Output::new(Code(exit_code)), stdout, }
  @exec.validate(
    { ..testcase, config: @config.TestCaseConfig::empty(), },
    output,
  )
  is Ok(_)
}

///|
test "generated Markdown expectations match the output" {
  @quickcheck.check(
    (codes : Array[Int]) => regenerated_passes(codes, Markdown, Unicode),
    count=1000,
  )
  @quickcheck.check(
    (codes : Array[Int]) => regenerated_passes(codes, Markdown, Ascii),
    count=1000,
  )
}

///|
test "generated Cram expectations match the output" {
  @quickcheck.check(
    (codes : Array[Int]) => regenerated_passes(codes, Cram, Ascii),
    count=1000,
  )
}
