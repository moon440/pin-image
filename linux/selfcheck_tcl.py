#!/usr/bin/env python3
"""Proves check_tcl.py actually detects breakage, so its 'clean' verdict means something."""
import subprocess, sys, os, tempfile

CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'check_tcl.py')

CASES = [
    ('unclosed brace in proc', 'proc a {\n  set x 1\n', True),
    ('unclosed bracket', 'proc b {} {\n  set y [expr 1+2\n}\n', True),
    ('scalar splice', 'proc c {} {\n  exec convert in -resize $ {*}$geom out\n}\n', True),
    ('extra closing brace', 'proc d {} {\n  set z 1\n}}\n', True),
    ('well formed', 'proc e {f g} {\n  return [expr {$f + $g}]\n}\nputs [e 1 2]\n', False),
]

fails = 0
for name, src, should_flag in CASES:
    with tempfile.NamedTemporaryFile('w', suffix='.tcl', delete=False, encoding='utf-8') as t:
        t.write(src)
        path = t.name
    r = subprocess.run([sys.executable, CHECK, path], capture_output=True, text=True)
    os.unlink(path)
    flagged = r.returncode != 0
    ok = flagged == should_flag
    print(f'{"ok  " if ok else "FAIL"} {name}: reported {r.stdout.splitlines()[0] if r.stdout else "(no output)"}')
    if not ok:
        print('   ', r.stdout.strip().replace('\n', '\n    '))
        fails += 1
print('checker is trustworthy' if not fails else f'{fails} case(s) wrong: do not trust its verdict')
sys.exit(1 if fails else 0)
