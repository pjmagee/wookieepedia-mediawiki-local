#!/usr/bin/env python3
"""Simple streaming filter for problematic content models in MediaWiki XML dumps.

By default we drop pages whose latest revision content model is in the blocked
set (interactivemap, GeoJSON) because the local minimal install does not load
the heavy mapping extensions unless explicitly enabled.

Usage:
  python3 filter_maps.py input.xml output.xml

Environment:
  FILTER_BLOCK_MODELS (optional): Comma separated list of models to drop.
    Defaults to: interactivemap,GeoJSON
"""
import os
import sys
import xml.etree.ElementTree as ET
from typing import Set


def load_blocklist() -> Set[str]:
    raw = os.environ.get("FILTER_BLOCK_MODELS", "interactivemap,GeoJSON")
    return {m.strip() for m in raw.split(',') if m.strip()}


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 filter_maps.py input.xml output.xml", file=sys.stderr)
        sys.exit(1)

    block_models = load_blocklist()
    infile, outfile = sys.argv[1], sys.argv[2]
    context = ET.iterparse(infile, events=("start", "end"))
    _, root = next(context)
    total_pages = 0
    skipped_pages = 0
    skipped_by_model = {m: 0 for m in block_models}

    with open(outfile, "wb") as out:
        out.write(b'<?xml version="1.0" encoding="utf-8"?>\n')
        out.write(b'<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.11/" version="0.11">\n')
        for event, elem in context:
            if event == "end" and elem.tag.endswith("page"):
                total_pages += 1
                skip = False
                # Find the last revision node (cheapest: take all revisions, last one wins)
                revisions = elem.findall("{*}revision")
                if revisions:
                    rev = revisions[-1]
                    model_el = rev.find("{*}model")
                    if model_el is not None and model_el.text in block_models:
                        model_name = model_el.text
                        skipped_pages += 1
                        skipped_by_model[model_name] = skipped_by_model.get(model_name, 0) + 1
                        skip = True
                if not skip:
                    out.write(ET.tostring(elem, encoding="utf-8"))
                elem.clear()
        out.write(b'</mediawiki>\n')

    kept_pages = total_pages - skipped_pages
    summary = [
        f"Filtered dump summary: total_pages={total_pages}",
        f"kept_pages={kept_pages}",
        f"skipped_pages={skipped_pages}",
    ]
    for model, count in skipped_by_model.items():
        summary.append(f"  skipped[{model}]={count}")
    print(" | ".join(summary), file=sys.stderr)

if __name__ == "__main__":
    main()
