#!/usr/bin/env python3
"""Cheap static checks the Dart analyser would make, for when there is no SDK.

Three things only, all of which have actually broken this project's build:
a type used without the import that declares it, unbalanced brackets, and an
`AppText.` constant that does not exist.
"""
import os, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib'
DECL = re.compile(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*\s*'
                  r'(?:class|enum|mixin|extension|typedef)\s+(\w+)', re.M)
TOP = re.compile(r'^(?:const|final)\s+\w[\w<>,\s\?]*\s+(\w+)\s*=', re.M)

files = sorted(LIB.rglob('*.dart'))
text = {p: p.read_text(encoding='utf-8') for p in files}
declared = {}
for p, t in text.items():
    for n in set(DECL.findall(t)) | set(TOP.findall(t)):
        declared.setdefault(n, set()).add(p)


def targets(p, t):
    out = set()
    for m in re.findall(r"^(?:import|part)\s+'([^']+)'", t, re.M):
        if m.startswith('dart:'):
            continue
        if m.startswith('package:cashier_system_v2/'):
            out.add(LIB / m.split('/', 1)[1])
        elif not m.startswith('package:'):
            out.add(Path(os.path.normpath(p.parent / m)))
    return out


problems = 0
for p, t in text.items():
    body = re.sub(r'//[^\n]*', '', t)
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
    body = re.sub(r"r?'''.*?'''", "''", body, flags=re.S)
    body = re.sub(r"r?'(?:[^'\\\n]|\\.)*'", "''", body)
    body = re.sub(r'r?"(?:[^"\\\n]|\\.)*"', '""', body)

    visible = set(DECL.findall(t)) | set(TOP.findall(t))
    for q in targets(p, t):
        if not q.exists():
            print(f'{p.relative_to(ROOT)}: imports missing file {q.name}')
            problems += 1
            continue
        s = text.get(q, q.read_text(encoding='utf-8'))
        visible |= set(DECL.findall(s)) | set(TOP.findall(s))
        for r in targets(q, s):
            if r.exists() and ("export '" in s or 'part ' in s):
                visible |= set(DECL.findall(text.get(r, r.read_text(encoding='utf-8'))))
    for m in re.findall(r"^part of\s+'([^']+)'", t, re.M):
        q = Path(os.path.normpath(p.parent / m))
        if q.exists():
            s = text[q] if q in text else q.read_text(encoding='utf-8')
            visible |= set(DECL.findall(s))
            for r in targets(q, s):
                if r.exists():
                    visible |= set(DECL.findall(text.get(r, r.read_text(encoding='utf-8'))))

    for u in set(re.findall(r'\b([A-Z]\w+)\b', body)):
        if u not in visible and u in declared:
            where = ', '.join(sorted(str(x.relative_to(ROOT)) for x in declared[u]))
            print(f'{p.relative_to(ROOT)}: uses {u}, declared in {where}')
            problems += 1

    for open_c, close_c in (('{', '}'), ('(', ')'), ('[', ']')):
        d = body.count(open_c) - body.count(close_c)
        if d:
            print(f'{p.relative_to(ROOT)}: {abs(d)} unclosed {open_c if d > 0 else close_c}')
            problems += 1

keys = set(re.findall(r'static const String (\w+) =',
                      (LIB / 'core/localization/app_text.dart').read_text(encoding='utf-8')))
for p, t in text.items():
    for m in set(re.findall(r'\bAppText\.([a-z]\w*)', t)) - keys:
        print(f'{p.relative_to(ROOT)}: AppText.{m} does not exist')
        problems += 1

print(f'{len(files)} files, {problems} problems')
sys.exit(1 if problems else 0)
