#!/usr/bin/env python3
"""Compare `scrut test` of this port with upstream on random documents.

Documents only use commands that mean the same without a shell (absolute
program paths, POSIX quoting), so upstream (which runs them with bash) and
the port must agree byte for byte on stdout and the exit code.

    scripts/cli_oracle.py [--seed N] [--count N] [--keep]
"""

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPSTREAM = os.path.join(ROOT, ".repos/scrut/target/release/scrut")
PORT = os.path.join(ROOT, "_build/native/release/build/cmd/scrut/scrut.exe")
PRINTF = "/usr/bin/printf"
SH = "/bin/sh"

PIECES = [
    "hello", "world", "foo bar", "  indented", "trailing  ", "tab\\there",
    "x" * 90, "é", "日本語", "😀", "\\033[31mred\\033[0m", "\\001ctl",
    "a*b", "[x]", "(re)", "50%%", "back\\\\slash", "cr\\r", "\\377bad",
    "", " ", "\\t",
]


def shell_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


def printf_output(fmt):
    """What printf prints for a format without conversions (bytes)."""
    out = bytearray()
    i = 0
    b = fmt.encode()
    while i < len(b):
        c = b[i]
        if c == ord("\\") and i + 1 < len(b):
            d = chr(b[i + 1])
            simple = {"n": 10, "t": 9, "r": 13, "\\": 92, "a": 7, "b": 8,
                      "f": 12, "v": 11}
            if d in simple:
                out.append(simple[d])
                i += 2
                continue
            if d in "01234567":
                j = i + 1
                v = 0
                while j < len(b) and j < i + 4 and chr(b[j]) in "01234567":
                    v = v * 8 + b[j] - 48
                    j += 1
                out.append(v & 0xFF)
                i = j
                continue
        if c == ord("%") and i + 1 < len(b) and b[i + 1] == ord("%"):
            out.append(ord("%"))
            i += 2
            continue
        out.append(c)
        i += 1
    return bytes(out)


def random_lines(rng):
    lines = []
    for _ in range(rng.choice([0, 1, 1, 2, 3, 4, 6, 12])):
        parts = [rng.choice(PIECES) for _ in range(rng.choice([1, 1, 2]))]
        lines.append(" ".join(parts) if rng.random() < 0.3 else "".join(parts))
    return lines


def expectation_for(rng, line_bytes):
    """An expectation line for one output line (may deliberately fail)."""
    text = line_bytes.decode("utf-8", "replace")
    printable = all(ch.isprintable() or ch == "\t" for ch in text) and \
        "�" not in text
    r = rng.random()
    if r < 0.45 and printable and text.strip() == text and text:
        return text
    if r < 0.55:
        return rng.choice(["*", "*o*", "h*"]) + " (glob)"
    if r < 0.65:
        return rng.choice([".*", "h.*", "[a-z ]+", "\\w+"]) + " (re)"
    if r < 0.7:
        return rng.choice(["*", ".*"]) + rng.choice([" (glob*)", " (re+)", " (glob?)"])
    if r < 0.8:
        return rng.choice(["nope", "hello", "world", ""])
    if printable:
        return text
    return text.replace("\r", "").replace("\x1b", "")


def testcase(rng, cram):
    lines = random_lines(rng)
    eol = rng.random() < 0.8
    fmt = "\\n".join(lines) + ("\\n" if eol and lines else "")
    code = 80 if rng.random() < 0.02 else rng.choice([0, 0, 0, 0, 1, 2, 3])
    to_stderr = rng.random() < 0.15
    if code == 0 and not to_stderr and rng.random() < 0.7:
        command = f"{PRINTF} {shell_quote(fmt)}"
    else:
        redirect = " >&2" if to_stderr else ""
        script = f"printf {shell_quote(fmt)}{redirect}; exit {code}"
        command = f"{SH} -c {shell_quote(script)}"
    output = printf_output(fmt)
    out_lines = output.split(b"\n")
    if out_lines and out_lines[-1] == b"":
        out_lines.pop()
    exp = [expectation_for(rng, ln) for ln in out_lines]
    # Mutations: drop, insert, add multiline or optional lines.
    if exp and rng.random() < 0.2:
        del exp[rng.randrange(len(exp))]
    if rng.random() < 0.2:
        exp.insert(rng.randrange(len(exp) + 1), rng.choice(["extra", "* (glob*)", "x (?)"]))
    if not eol and exp and rng.random() < 0.6:
        exp[-1] = exp[-1] + " (no-eol)"
    expected_code = code if rng.random() < 0.85 else rng.choice([0, 3])
    title = rng.choice(["", "", "A title", "Ünïcode title"])
    return title, command, exp, expected_code


SLEEP = "/bin/sleep"
PRINTENV = "/usr/bin/printenv"


def special_testcase(rng):
    """Test cases exercising execution configuration: (config, command
    lines, expectations, exit code)."""
    kind = rng.choice(["timeout", "env", "stderr", "interpolate", "detached",
                       "wait", "continuation", "skip", "exit"])
    if kind == "timeout":
        return ["timeout: 200ms"], [f"{SLEEP} 2"], [], 0
    # A variable per test case: upstream's shell state would carry one test
    # case's variables into the next (see DIFFERENCES.md).
    var = f"VAR{rng.randrange(10**6)}"
    if kind == "env":
        value = rng.choice(["bar", "with space", "é"])
        exp = [value] if rng.random() < 0.7 else ["other"]
        return [f'environment: {{{var}: "{value}"}}'], [f"{PRINTENV} {var}"], exp, 0
    if kind == "stderr":
        script = "printf 'out\\n'; printf 'err\\n' >&2"
        stream = rng.choice(["stderr", "combined", "stdout"])
        return [f"output_stream: {stream}"], [f"{SH} -c {shell_quote(script)}"], \
            rng.choice([["err"], ["out"], ["out", "err"]]), 0
    if kind == "interpolate":
        return [f'environment: {{{var}: "bar"}}', "interpolated: true"], \
            [f"{PRINTENV} {var}"], [rng.choice([f"${var}", f"${{{var}}}", "bar", "$BAR"])], 0
    if kind == "detached":
        return ["detached: true"], [f"{SLEEP} 0.2"], [], 0
    if kind == "wait":
        return ["wait: 50ms"], [f"{PRINTF} 'waited\\n'"], ["waited"], 0
    if kind == "continuation":
        return [], [f"{PRINTF} \\", "'%s\\n' a b"], ["a", "b"], 0
    if kind == "skip":
        return ["skip_document_code: 9"], [f"{SH} -c 'exit 9'"], [], 0
    return [], [f"{SH} -c 'exit 5'"], [], rng.choice([5, 0])


def markdown_document(rng, work):
    out = []
    if rng.random() < 0.15:
        front = rng.choice([
            ["defaults: {output_stream: combined}"],
            ["total_timeout: 1s"],
            ["prepend: [common.md]"],
            ["append: [common.md]"],
            ["defaults: {environment: {FOO: \"doc\"}}"],
        ])
        out += ["---", *front, "---", ""]
        if any("common.md" in f for f in front):
            with open(os.path.join(work, "common.md"), "w") as f:
                f.write("```scrut\n$ /bin/echo common\ncommon\n```\n")
    out += ["# Generated", ""]
    for _ in range(rng.randint(1, 5)):
        if rng.random() < 0.25:
            config, lines, exp, code = special_testcase(rng)
            title = ""
        else:
            title, command, exp, code = testcase(rng, False)
            lines = [command]
            config = []
            if rng.random() < 0.1:
                config.append("output_stream: combined")
            if rng.random() < 0.05:
                config.append("keep_crlf: true")
            if rng.random() < 0.05:
                config.append("strip_ansi_escaping: true")
            if rng.random() < 0.05:
                config.append("fail_fast: true")
        if title:
            out += [title, ""]
        header = "```scrut" + (" {" + ", ".join(config) + "}" if config else "")
        out.append(header)
        out.append(f"$ {lines[0]}")
        out += [f"> {line}" for line in lines[1:]]
        out += exp
        if code:
            out.append(f"[{code}]")
        out.append("```")
        out.append("")
    return "\n".join(out) + "\n"


def cram_document(rng):
    out = ["Generated", ""]
    for _ in range(rng.randint(1, 5)):
        title, command, exp, code = testcase(rng, True)
        out.append(f"  $ {command}")
        out += ["  " + e for e in exp]
        if code:
            out.append(f"  [{code}]")
        out.append("")
    return "\n".join(out) + "\n"


FLAG_SETS = [
    [],
    ["--absolute-line-numbers"],
    ["--max-multiline-matched-lines", "3"],
    ["-e", "ascii"],
    ["--combine-output"],
    ["--cram-compat"],
    ["--renderer", "pretty"],
    ["-r", "diff"],
    ["-r", "json"],
    ["-r", "junit"],
    ["-r", "junit", "-e", "ascii"],
]


def normalize(flags, stdout):
    """Remove what legitimately differs between runs: timings, temporary
    paths, the timestamp and upstream's TESTSHELL."""
    import json
    import re
    text = stdout.decode("utf-8", "replace")
    if "json" in flags:
        try:
            data = json.loads(text, object_pairs_hook=lambda pairs: pairs)
        except ValueError:
            return text

        def walk(v):
            if isinstance(v, list) and all(isinstance(p, tuple) for p in v) and v:
                out = []
                for k, x in v:
                    if k == "duration_ms" or k == "TESTSHELL":
                        continue
                    if k in ("TMPDIR", "CRAMTMP", "TMP", "TEMP"):
                        x = "<tmp>"
                    out.append((k, walk(x)))
                return out
            if isinstance(v, list):
                return [walk(x) for x in v]
            return v
        return repr(walk(data))
    if "junit" in flags:
        text = re.sub(r' timestamp="[^"]*"', ' timestamp="T"', text)
        text = re.sub(r' time="[^"]*"', ' time="t"', text)
    return text


def run(binary, args, cwd, color, command="test"):
    env = dict(os.environ)
    env.pop("CLICOLOR_FORCE", None)
    if color:
        env["CLICOLOR_FORCE"] = "1"
    p = subprocess.run([binary, command, *args], cwd=cwd, env=env,
                       capture_output=True, timeout=60)
    return p.returncode, p.stdout, p.stderr


UPDATE_FLAG_SETS = [
    [],
    ["--replace", "-y"],
    ["-e", "ascii"],
    ["--convert", "cram"],
    ["--convert", "markdown"],
    ["-o", ".upd"],
]


def run_update(binary, flags, name, text, work, tag, color):
    """Run `update` on a fresh copy; returns exit, stdout, stderr and the
    files the update wrote."""
    d = os.path.join(work, tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    with open(os.path.join(d, name), "w") as f:
        f.write(text)
    code, out, err = run(binary, [*flags, name], d, color, command="update")
    import re
    # Upstream logs errors with a timestamp.
    plain = re.sub(rb"\x1b\[[0-9;]*m", b"", err)
    if plain != err and b" ERROR scrut: " in plain:
        err = plain
    err = re.sub(rb"^\S+Z ERROR scrut: ", b"", err, flags=re.M)
    files = {}
    for entry in sorted(os.listdir(d)):
        with open(os.path.join(d, entry), "rb") as f:
            files[entry] = f.read()
    return code, out, err, files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--keep", action="store_true")
    opts = ap.parse_args()
    rng = random.Random(opts.seed)
    work = tempfile.mkdtemp(prefix="scrut-oracle.")
    failures = 0
    for n in range(opts.count):
        cram = rng.random() < 0.3
        name = f"doc{n}.t" if cram else f"doc{n}.md"
        text = cram_document(rng) if cram else markdown_document(rng, work)
        with open(os.path.join(work, name), "w") as f:
            f.write(text)
        color = rng.random() < 0.3
        if rng.random() < 0.3:
            flags = ["update"] + rng.choice(UPDATE_FLAG_SETS)
            expected = run_update(UPSTREAM, flags[1:], name, text, work, "u", color)
            actual = run_update(PORT, flags[1:], name, text, work, "p", color)
        else:
            flags = rng.choice(FLAG_SETS)
            code, out, _ = run(UPSTREAM, [*flags, name], work, color)
            expected = (code, normalize(flags, out))
            code, out, _ = run(PORT, [*flags, name], work, color)
            actual = (code, normalize(flags, out))
        if expected != actual:
            failures += 1
            print(f"MISMATCH {name} flags={flags} color={color}")
            if failures <= 3:
                print("--- upstream (exit %d)" % expected[0])
                print(*expected[1:], sep="\n")
                print("--- port (exit %d)" % actual[0])
                print(*actual[1:], sep="\n")
    print(f"{opts.count - failures}/{opts.count} documents agree (work dir {work})")
    if not opts.keep and failures == 0:
        shutil.rmtree(work)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
