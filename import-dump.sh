#!/usr/bin/env bash
set -euo pipefail

# Simplified single-pass importer for the Wookieepedia dump.
# Assumes one dump file placed in /data/dumps named starwars_pages_current.xml(.gz/.7z)
# Imports only the core namespaces needed to render pages locally.

DUMP_DIR="/data/dumps"
MW_ROOT="/var/www/html"
DEFAULT_NAMESPACES="0|6|10|14|828" # Main, File, Template, Category, Module

shopt -s nullglob
for f in "$DUMP_DIR"/starwars_pages_current.xml "$DUMP_DIR"/starwars_pages_current.xml.gz "$DUMP_DIR"/starwars_pages_current.xml.7z; do
  if [ -f "$f" ]; then XML_FILE="$f"; break; fi
done

if [ -z "${XML_FILE:-}" ]; then
  echo "Expected dump file starwars_pages_current.xml[.gz|.7z] not found in $DUMP_DIR" >&2
  exit 1
fi

echo "Importing $XML_FILE (namespaces: $DEFAULT_NAMESPACES)" >&2
case "$XML_FILE" in
  *.xml.7z)
    if command -v 7z >/dev/null 2>&1; then
      7z x -so "$XML_FILE" 2>/dev/null | php "$MW_ROOT"/maintenance/importDump.php --conf "$MW_ROOT"/LocalSettings.php --uploads --report=500 --namespaces="$DEFAULT_NAMESPACES" || exit 1
    else
      echo "7z not installed inside container." >&2; exit 1
    fi
    ;;
  *.xml.gz)
    gunzip -c "$XML_FILE" | php "$MW_ROOT"/maintenance/importDump.php --conf "$MW_ROOT"/LocalSettings.php --uploads --report=500 --namespaces="$DEFAULT_NAMESPACES" || exit 1
    ;;
  *.xml)
    php "$MW_ROOT"/maintenance/importDump.php --conf "$MW_ROOT"/LocalSettings.php --uploads --report=500 --namespaces="$DEFAULT_NAMESPACES" < "$XML_FILE" || exit 1
    ;;
esac

echo "Running maintenance scripts (links, categories, stats, jobs)..." >&2
php "$MW_ROOT"/maintenance/rebuildall.php --conf "$MW_ROOT"/LocalSettings.php --quiet || true
php "$MW_ROOT"/maintenance/rebuildrecentchanges.php --conf "$MW_ROOT"/LocalSettings.php || true
php "$MW_ROOT"/maintenance/initSiteStats.php --conf "$MW_ROOT"/LocalSettings.php --update || true
php "$MW_ROOT"/maintenance/runJobs.php --conf "$MW_ROOT"/LocalSettings.php --maxjobs 500 || true

# Supplemental imports: any additional small XML dumps (e.g., missing modules/templates)
EXTRA_DIR="$DUMP_DIR/extra"
if [ -d "$EXTRA_DIR" ]; then
  shopt -s nullglob
  extras=("$EXTRA_DIR"/*.xml)
  if [ ${#extras[@]} -gt 0 ]; then
    echo "Importing supplemental XML files from $EXTRA_DIR (no namespace filtering)" >&2
    for x in "${extras[@]}"; do
      echo "  -> $x" >&2
      php "$MW_ROOT"/maintenance/importDump.php --conf "$MW_ROOT"/LocalSettings.php --uploads --report=100 < "$x" || echo "Failed to import $x" >&2
    done
    php "$MW_ROOT"/maintenance/runJobs.php --conf "$MW_ROOT"/LocalSettings.php --maxjobs 200 || true
  fi
fi

echo "Import complete." >&2
touch "$DUMP_DIR/.imported" || true