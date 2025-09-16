#!/usr/bin/env bash
set -euo pipefail

# Preprocess (filter + optional split) a MediaWiki dump for later fast loading.
# - Accepts starwars_pages_current.xml[.gz|.7z]
# - Always filters blocked content models (uses filter_maps.py)
# - Outputs filtered file: starwars_pages_current.filtered.xml
# - If SPLIT_PARTS > 1, splits filtered file into dumps/split/part*.xml
# - Writes marker .preprocessed to avoid redundant work unless --force

DUMP_DIR="/data/dumps"
ORIG="starwars_pages_current.xml"
FILTERED="$DUMP_DIR/${ORIG%.xml}.filtered.xml"
SPLIT_DIR="$DUMP_DIR/split"
MARKER="$DUMP_DIR/.preprocessed"
PARTS="${SPLIT_PARTS:-4}"

log(){ echo "[preprocess] $*" >&2; }
err(){ echo "[preprocess][ERROR] $*" >&2; exit 1; }

usage(){ cat >&2 <<EOF
Usage: preprocess-dump.sh [--force] [--parts N]
Environment:
  SPLIT_PARTS (default 4) – number of split parts (ignored if 1)
Produces:
  starwars_pages_current.filtered.xml
  split/part1.xml ... partN.xml (if parts>1)
Markers:
  .preprocessed (touch file to indicate done)
EOF
}

FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ; shift ;;
    --parts) PARTS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -f "$MARKER" ] && [ $FORCE -eq 0 ]; then
  log "Already preprocessed (marker present). Use --force to redo."; exit 0
fi

shopt -s nullglob
SRC=""
for cand in "$DUMP_DIR/$ORIG" "$DUMP_DIR/$ORIG.gz" "$DUMP_DIR/$ORIG.7z"; do
  if [ -f "$cand" ]; then SRC="$cand"; break; fi
done
[ -n "$SRC" ] || err "Dump not found (expected $ORIG[.gz|.7z]) in $DUMP_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  err "python3 required for filtering/splitting"
fi
FILTER_SCRIPT="/usr/local/bin/filter_maps.py"
[ -f "$FILTER_SCRIPT" ] || err "filter_maps.py missing"

WORK="$DUMP_DIR/tmp.unpack.xml"
case "$SRC" in
  *.xml) cp "$SRC" "$WORK" ;;
  *.xml.gz) gunzip -c "$SRC" > "$WORK" ;;
  *.xml.7z) if command -v 7z >/dev/null 2>&1; then 7z x -so "$SRC" 2>/dev/null > "$WORK"; else err "7z binary not available"; fi ;;
  *) err "Unsupported dump extension: $SRC" ;;
esac

log "Filtering -> $(basename "$FILTERED")"
python3 "$FILTER_SCRIPT" "$WORK" "$FILTERED"
rm -f "$WORK"

if [ "${PARTS}" != "1" ]; then
  if ! [[ "$PARTS" =~ ^[0-9]+$ ]] || [ "$PARTS" -le 0 ]; then err "Invalid PARTS=$PARTS"; fi
  log "Splitting filtered dump into ${PARTS} parts"
  python3 /usr/local/bin/split_wiki_dump.py "$FILTERED" "$SPLIT_DIR" "$PARTS"
else
  rm -rf "$SPLIT_DIR" 2>/dev/null || true
fi

touch "$MARKER" || true
log "Preprocessing complete."
