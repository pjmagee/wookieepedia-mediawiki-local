#!/usr/bin/env python3
"""Split a MediaWiki XML dump into N separate XML files (round-robin by <page>).

Usage:
  python3 split_wiki_dump.py input.xml outdir parts
"""
import os
import sys
import xml.etree.ElementTree as ET

HEADER = b'<?xml version="1.0" encoding="utf-8"?>\n'
ROOT_OPEN = b'<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.11/" version="0.11">\n'
ROOT_CLOSE = b'</mediawiki>\n'

def open_outputs(outdir: str, parts: int):
    handles = []
    for i in range(1, parts + 1):
        path = os.path.join(outdir, f'part{i}.xml')
        f = open(path, 'wb')
        f.write(HEADER)
        f.write(ROOT_OPEN)
        handles.append(f)
    return handles

def close_outputs(handles):
    for f in handles:
        f.write(ROOT_CLOSE)
        f.close()

def split_file(input_path: str, outdir: str, parts: int):
    os.makedirs(outdir, exist_ok=True)
    for name in os.listdir(outdir):
        if name.startswith('part') and name.endswith('.xml'):
            try:
                os.remove(os.path.join(outdir, name))
            except OSError:
                pass
    ctx = ET.iterparse(input_path, events=("start", "end"))
    _, _root = next(ctx)
    outputs = open_outputs(outdir, parts)
    idx = 0
    pages = 0
    try:
        for event, elem in ctx:
            if event == 'end' and elem.tag.endswith('page'):
                outputs[idx % parts].write(ET.tostring(elem, encoding='utf-8'))
                elem.clear()
                idx += 1
                pages += 1
    finally:
        close_outputs(outputs)
    print(f"Split complete: {pages} pages into {parts} parts", file=sys.stderr)

def main():
    if len(sys.argv) != 4:
        print("Usage: python3 split_wiki_dump.py input.xml outdir parts", file=sys.stderr)
        sys.exit(1)
    input_path, outdir, parts_s = sys.argv[1:]
    try:
        parts = int(parts_s)
        if parts <= 0:
            raise ValueError
    except ValueError:
        print("parts must be positive integer", file=sys.stderr)
        sys.exit(1)
    split_file(input_path, outdir, parts)

if __name__ == '__main__':
    main()
