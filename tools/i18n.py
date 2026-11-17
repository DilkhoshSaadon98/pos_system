#!/usr/bin/env python3
"""Keeps `AppText` and the three translation tables in step.

The app has one string table per language and a constant per key, and the only
thing that can go wrong is drift: a key added to English and forgotten in
Kurdish, or a constant that points at a key nobody wrote. Both fail silently at
runtime — the fallback quietly serves English — so they are checked here
instead.

    python3 tools/i18n.py check              # parity and orphans
    python3 tools/i18n.py add keys.json      # add new keys to all three

The JSON is a list of [constantName, key, english, arabic, kurdish].
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXT = ROOT / 'lib' / 'core' / 'localization' / 'app_text.dart'
TABLES = ROOT / 'lib' / 'core' / 'localization' / 'translations.dart'
LANGS = (('_en', 2), ('_ar', 3), ('_ku', 4))


def table_bounds(src: str, lang: str) -> tuple[int, int]:
    start = src.index('const Map<String, String> %s = <String, String>{' % lang)
    return start, src.index('\n};', start)


def keys_in(src: str, lang: str) -> set[str]:
    start, end = table_bounds(src, lang)
    return set(re.findall(r"^\s*'([a-z0-9_]+)':", src[start:end], re.M))


def constants() -> dict[str, str]:
    src = TEXT.read_text(encoding='utf-8')
    return {m[0]: m[1]
            for m in re.findall(r"static const String (\w+) = '([^']+)'", src)}


def check() -> int:
    src = TABLES.read_text(encoding='utf-8')
    tables = {lang: keys_in(src, lang) for lang, _ in LANGS}
    problems = 0

    en = tables['_en']
    for lang in ('_ar', '_ku'):
        missing = sorted(en - tables[lang])
        extra = sorted(tables[lang] - en)
        if missing:
            print(f'{lang}: {len(missing)} missing — {missing[:8]}')
            problems += len(missing)
        if extra:
            print(f'{lang}: {len(extra)} not in English — {extra[:8]}')
            problems += len(extra)

    consts = constants()
    orphans = sorted(name for name, key in consts.items() if key not in en)
    if orphans:
        print(f'{len(orphans)} constants point at no string — {orphans[:8]}')
        problems += len(orphans)

    print(f'{len(en)} keys, {len(consts)} constants, {problems} problems')
    return 1 if problems else 0


def add(path: str) -> int:
    rows = json.loads(Path(path).read_text(encoding='utf-8'))

    src = TEXT.read_text(encoding='utf-8')
    have = set(re.findall(r'static const String (\w+) =', src))
    fresh = [r for r in rows if r[0] not in have]
    if fresh:
        block = ''.join("  static const String %s = '%s';\n" % (r[0], r[1])
                        for r in fresh)
        TEXT.write_text(src.rstrip()[:-1] + block + '}\n', encoding='utf-8')

    src = TABLES.read_text(encoding='utf-8')
    for lang, index in LANGS:
        start, end = table_bounds(src, lang)
        body = src[start:end]
        block = ''.join("  '%s': '%s',\n" % (r[1], r[index].replace("'", r"\'"))
                        for r in rows if ("'%s':" % r[1]) not in body)
        if block:
            src = src[:end] + '\n' + block.rstrip('\n') + src[end:]
    TABLES.write_text(src, encoding='utf-8')

    print(f'{len(fresh)} constants and up to {len(rows)} strings added')
    return check()


if __name__ == '__main__':
    command = sys.argv[1] if len(sys.argv) > 1 else 'check'
    sys.exit(add(sys.argv[2]) if command == 'add' else check())
