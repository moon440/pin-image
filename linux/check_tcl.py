#!/usr/bin/env python3
"""Brace/bracket/quote balance check for a Tcl file, plus the obvious mistakes.

`tclsh` is not on this machine, so this is what verification I can honestly do:
`info complete` semantics approximated in Python, catching the class of error that
hand-written Tcl actually produces (unbalanced braces, stray $ on a splice, wrong
argument list splicing).
"""
import re, sys

def incomplete(line):
    """True when a logical line is not finished: unbalanced {} [] or quotes."""
    depth = {'{': 0, '[': 0}
    i = 0
    while i < len(line):
        c = line[i]
        if c == '\\':
            i += 2
            continue
        if c == '#' and depth['{'] == 0 and depth['['] == 0 and i and line[i-1] in ' \t\n':
            break
        if c in '{[':
            depth[c] += 1
        elif c == '}':
            depth['{'] -= 1
            if depth['{'] < 0:
                return 'extra }'
        elif c == ']':
            depth['['] -= 1
            if depth['['] < 0:
                return 'extra ]'
        elif c == '"':
            j = i + 1
            while j < len(line) and line[j] != '"':
                j += 2 if line[j] == '\\' else 1
            if j >= len(line):
                return 'unterminated quote'
            i = j
        i += 1
    if depth['{'] != 0:
        return f'{depth["{"]} unclosed {{"'
    if depth['['] != 0:
        return f'{depth["["]} unclosed ['
    return None


def main(path):
    src = open(path, encoding='utf-8').read()
    problems = []
    logical, start, buf = '', 1, []
    for n, raw in enumerate(src.splitlines(), 1):
        line = raw.rstrip()
        if not line.strip():
            continue
        buf.append(line)
        logical = ' '.join(buf)
        err = incomplete(logical)
        if err:
            continue                      # statement continues
        # statement is complete; check it
        body = logical.strip()
        if re.search(r'\$\s*\{\*\}', body) or '$ {*}' in body:
            problems.append((start, 'splicing a scalar: "$ {*}" should be "{$var *}" style'))
        if re.search(r'(?<![\w\[{])\$\{?\*\}', body):
            problems.append((start, 'stray {*} splice'))
        if body.startswith('proc ') and '{' in body and not incomplete(body + '}'):
            pass
        buf, start = [], n + 1
    if buf:
        problems.append((start, f'unterminated statement at end of file: {incomplete(" ".join(buf))}'))

    # The "undeclared variable" idea was dropped: in Tcl a set, foreach or regexp
    # match creates a local anywhere, and approximating that from regex was
    # producing false positives. Brace balance and argument splicing are the
    # checks worth trusting here; real verification needs a box with Tk on it.

    print(f'{path}: {len(problems)} issue(s)')
    for line, msg in problems:
        print(f'  line {line}: {msg}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'pin.tcl'))
