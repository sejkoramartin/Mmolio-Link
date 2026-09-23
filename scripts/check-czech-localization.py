#!/usr/bin/env python3
"""Check that Czech resources cover the upstream keys without changing format arguments."""
from collections import Counter
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    ROOT / 'xDrip/Storyboards',
    ROOT / 'xDrip Watch App/Texts',
    ROOT / 'xDrip Watch Complication/Texts',
)
ENTRY = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$', re.M)
FORMAT = re.compile(r'%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[hlLzjtq]?[a-zA-Z@%]|\\[nrt"\\]')
errors = []

def read_table(path):
    content = path.read_text()
    entries = dict(ENTRY.findall(content))
    candidate_lines = sum(bool(re.match(r'^\s*"', line)) for line in content.splitlines())
    if candidate_lines != len(ENTRY.findall(content)):
        errors.append(f'Malformed .strings entry: {path}')
    return entries

count = 0
for directory in SOURCES:
    for original in sorted((directory / 'en.lproj').glob('*.strings')):
        translated = directory / 'cs.lproj' / original.name
        if not translated.exists():
            errors.append(f'Missing Czech table: {translated}')
            continue
        en = read_table(original)
        cs = read_table(translated)
        for key, source in en.items():
            if key not in cs:
                errors.append(f'Missing Czech key: {translated}:{key}')
                continue
            if Counter(FORMAT.findall(source)) != Counter(FORMAT.findall(cs[key])):
                errors.append(f'Changed format arguments: {translated}:{key}')
            count += 1

project = (ROOT / 'xdrip.xcodeproj/project.pbxproj').read_text()
if 'developmentRegion = cs;' not in project:
    errors.append('Project development region is not Czech')
if 'knownRegions = (\n\t\t\t\tcs,\n\t\t\t\tBase,\n\t\t\t);' not in project:
    errors.append('Project still advertises other languages')
for directory in SOURCES:
    for translation in sorted((directory / 'cs.lproj').glob('*.strings')):
        if f'cs.lproj/{translation.name};' not in project:
            errors.append(f'Czech file not included in Xcode project: {translation}')

if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Czech localization covers {count} source keys in {sum(len(list((d / "cs.lproj").glob("*.strings"))) for d in SOURCES)} files.')
