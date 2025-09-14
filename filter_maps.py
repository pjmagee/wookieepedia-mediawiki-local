#!/usr/bin/env python3
"""
Filter out pages with content model 'interactivemap' from a MediaWiki XML dump.
Usage:
  python3 filter_maps.py input.xml output.xml
"""
import sys
import xml.etree.ElementTree as ET

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 filter_maps.py input.xml output.xml", file=sys.stderr)
        sys.exit(1)
    infile, outfile = sys.argv[1], sys.argv[2]
    context = ET.iterparse(infile, events=("start", "end"))
    _, root = next(context)
    out = open(outfile, "wb")
    out.write(b'<?xml version="1.0" encoding="utf-8"?>\n')
    out.write(b'<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.11/" version="0.11">\n')
    for event, elem in context:
        if event == "end" and elem.tag.endswith("page"):
            skip = False
            for rev in elem.findall(".//{*}revision"):
                model = rev.find("{*}model")
                if model is not None and model.text == "interactivemap":
                    skip = True
                    break
            if not skip:
                out.write(ET.tostring(elem, encoding="utf-8"))
            elem.clear()
    out.write(b'</mediawiki>\n')
    out.close()

if __name__ == "__main__":
    main()
