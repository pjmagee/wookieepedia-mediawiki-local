#!/usr/bin/env bash
set -euo pipefail

MW_ROOT="/var/www/html"
DUMP_DIR="/data/dumps"
ORIG_DUMP_BASENAME="starwars_pages_current.xml"
MARKER="$DUMP_DIR/.imported"
FILTERED="$DUMP_DIR/${ORIG_DUMP_BASENAME%.xml}.filtered.xml"
SPLIT_DIR="$DUMP_DIR/split"
DB_HOST="${MW_DB_HOST:-db}"
DB_NAME="${MW_DB_NAME:-mediawiki}"
DB_USER="${MW_DB_USER:-wikiuser}"
DB_PASS="${MW_DB_PASS:-secret}"
DEFAULT_NAMESPACES="0|6|10|14|828"

log(){ echo "[loader] $*" >&2; }

wait_for_db(){
  log "Waiting for database $DB_HOST ..."
  local tries=0
  if command -v mysql >/dev/null 2>&1; then
    while ! mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e 'SELECT 1' >/dev/null 2>&1; do
      tries=$((tries+1))
      if [ $tries -ge 120 ]; then
        log "Database not reachable after 120s; aborting load."; exit 1
      fi
      sleep 1
    done
  else
    log "mysql client not found; using PHP mysqli probe"
    while ! php -r '
      $h=getenv("MW_DB_HOST")?:"db"; $u=getenv("MW_DB_USER")?:"wikiuser"; $p=getenv("MW_DB_PASS")?:"secret"; $d=getenv("MW_DB_NAME")?:"mediawiki";
      $m=@new mysqli($h,$u,$p,$d);
      exit($m && !$m->connect_errno ? 0 : 1);
    ' >/dev/null 2>&1; do
      tries=$((tries+1))
      if [ $tries -ge 120 ]; then
        log "Database not reachable after 120s (PHP probe); aborting load."; exit 1
      fi
      sleep 1
    done
  fi
  log "Database reachable"
}

ensure_core(){
  table_exists(){
    if command -v mysql >/dev/null 2>&1; then
      mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e 'SELECT 1 FROM page LIMIT 1' >/dev/null 2>&1
      return $?
    else
      php -r '
        $h=getenv("MW_DB_HOST")?:"db"; $u=getenv("MW_DB_USER")?:"wikiuser"; $p=getenv("MW_DB_PASS")?:"secret"; $d=getenv("MW_DB_NAME")?:"mediawiki";
        $m=@new mysqli($h,$u,$p,$d);
        if ($m && !$m->connect_errno) {
          $r=@$m->query("SELECT 1 FROM page LIMIT 1");
          exit($r?0:1);
        }
        exit(1);
      ' >/dev/null 2>&1
      return $?
    fi
  }

  if table_exists; then
    log "Core tables present"
    php "$MW_ROOT/maintenance/update.php" --quick --conf "$MW_ROOT/LocalSettings.php" || true
    return 0
  fi

  # Decide whether we can attempt install: only if LocalSettings is writable (not bind-mounted RO)
  if [ -w "$MW_ROOT/LocalSettings.php" ]; then
    log "Running install.php (initial schema)"
    local tmpLocal="$MW_ROOT/LocalSettings.php"
    mv "$tmpLocal" "$tmpLocal.preinstall" || true
    if php "$MW_ROOT/maintenance/install.php" \
        --dbtype mysql \
        --dbname "$DB_NAME" \
        --dbserver "$DB_HOST" \
        --dbuser "$DB_USER" \
        --dbpass "$DB_PASS" \
        --server "${MW_SERVER:-http://localhost:8080}" \
        --scriptpath "" \
        --lang "${MW_SITE_LANG:-en}" \
        --pass "${MW_ADMIN_PASS:-adminpass}" \
        "${MW_SITE_NAME:-StarWars Local}" "${MW_ADMIN_USER:-admin}"; then
      mv "$tmpLocal.preinstall" "$tmpLocal" || true
      log "Install complete"
      php "$MW_ROOT/maintenance/update.php" --quick --conf "$MW_ROOT/LocalSettings.php" || true
      return 0
    else
      log "install.php attempt failed; restoring LocalSettings and continuing to wait for external install"
      mv "$tmpLocal.preinstall" "$tmpLocal" 2>/dev/null || true
    fi
  else
    log "LocalSettings.php not writable (likely bind-mounted read-only); will wait for web container to finish install."
  fi

  # Wait for another container (web) to create schema
  local waited=0
  while ! table_exists; do
    sleep 2
    waited=$((waited+2))
    if [ $waited -ge 180 ]; then
      log "Timed out waiting for core tables after 180s"; exit 1
    fi
  done
  log "Core tables detected after wait; running update.php"
  php "$MW_ROOT/maintenance/update.php" --quick --conf "$MW_ROOT/LocalSettings.php" || true
}

find_dump(){
  shopt -s nullglob
  for f in "$DUMP_DIR/${ORIG_DUMP_BASENAME}" "$DUMP_DIR/${ORIG_DUMP_BASENAME}.gz" "$DUMP_DIR/${ORIG_DUMP_BASENAME}.7z"; do
    [ -f "$f" ] && echo "$f" && return 0
  done
  return 1
}

maybe_filter(){
  # If a preprocessed filtered file already exists, reuse it.
  if [ -f "$FILTERED" ]; then
    log "Using existing filtered dump $(basename "$FILTERED")"
    echo "$FILTERED"; return 0
  fi
  local src="$1"
  local filter_script="/usr/local/bin/filter_maps.py"
  if [ ! -f "$filter_script" ]; then
    log "Filter script missing ($filter_script). Aborting."; exit 1
  fi
  log "Filtering blocked content models -> $FILTERED"
  if [[ "$src" == *.gz ]]; then
    gunzip -c "$src" > "$DUMP_DIR/unpacked.xml"
    python3 "$filter_script" "$DUMP_DIR/unpacked.xml" "$FILTERED"
    rm -f "$DUMP_DIR/unpacked.xml"
  elif [[ "$src" == *.7z ]]; then
    7z x -so "$src" 2>/dev/null > "$DUMP_DIR/unpacked.xml"
    python3 "$filter_script" "$DUMP_DIR/unpacked.xml" "$FILTERED"
    rm -f "$DUMP_DIR/unpacked.xml"
  else
    python3 "$filter_script" "$src" "$FILTERED"
  fi
  echo "$FILTERED"
}

import_file(){
  local src="$1"
  php "$MW_ROOT/maintenance/importDump.php" --conf "$MW_ROOT/LocalSettings.php" --uploads --report=500 --namespaces="$DEFAULT_NAMESPACES" < "$src" || {
    log "Import failed for $src"; return 1; }
}

import_dump(){
  # If split parts exist, import them in parallel
  if ls "$SPLIT_DIR"/part*.xml >/dev/null 2>&1; then
    log "Found pre-split parts in $SPLIT_DIR - importing in parallel"
    local pids=()
    local parts=()
    for p in "$SPLIT_DIR"/part*.xml; do
      parts+=("$p")
      (
        log "[part $(basename "$p")] starting import"
        if import_file "$p"; then
          log "[part $(basename "$p")] completed successfully"
        else
          log "[part $(basename "$p")] FAILED"
          exit 1
        fi
      ) &
      pids+=("$!")
    done
    local fail=0
    for i in "${!pids[@]}"; do
      local pid=${pids[$i]}
      local fname=$(basename "${parts[$i]}")
      if ! wait "$pid"; then
        log "Import failed for part $fname (pid=$pid)"
        fail=1
      fi
    done
    if [ $fail -ne 0 ]; then
      log "One or more part imports failed"; return 1
    fi
    log "All split parts imported successfully"
    return 0
  fi
  local src="$1"
  log "Importing single file $(basename "$src")"
  case "$src" in
    *.xml) import_file "$src" ;;
    *.xml.gz) gunzip -c "$src" | php "$MW_ROOT/maintenance/importDump.php" --conf "$MW_ROOT/LocalSettings.php" --uploads --report=500 --namespaces="$DEFAULT_NAMESPACES" || exit 1 ;;
    *.xml.7z) 7z x -so "$src" 2>/dev/null | php "$MW_ROOT/maintenance/importDump.php" --conf "$MW_ROOT/LocalSettings.php" --uploads --report=500 --namespaces="$DEFAULT_NAMESPACES" || exit 1 ;;
    *) log "Unsupported dump extension for $src"; exit 1 ;;
  esac
}

post_maintenance(){
  log "Running post-import maintenance tasks"
  php "$MW_ROOT/maintenance/rebuildall.php" --conf "$MW_ROOT/LocalSettings.php" --quiet || true
  php "$MW_ROOT/maintenance/rebuildrecentchanges.php" --conf "$MW_ROOT/LocalSettings.php" || true
  php "$MW_ROOT/maintenance/initSiteStats.php" --conf "$MW_ROOT/LocalSettings.php" --update || true
  php "$MW_ROOT/maintenance/runJobs.php" --conf "$MW_ROOT/LocalSettings.php" --maxjobs 500 || true
}

import_supplemental(){
  local extra_dir="$DUMP_DIR/extra"
  [ -d "$extra_dir" ] || { log "No supplemental directory"; return 0; }
  shopt -s nullglob
  local any=0
  for x in "$extra_dir"/*.xml; do
    [ -f "$x" ] || continue
    local marker="$x.imported"
    if [ ! -f "$marker" ] || [ "$x" -nt "$marker" ]; then
      log "Supplemental import: $x"
      if php "$MW_ROOT/maintenance/importDump.php" --conf "$MW_ROOT/LocalSettings.php" --report=100 < "$x"; then
        touch "$marker" || true
        any=1
      else
        log "Failed supplemental $x"
      fi
    fi
  done
  [ $any -eq 1 ] && log "Supplemental imports complete" || log "No new supplemental imports"
}

main(){
  local EXTRA_ONLY=${EXTRA_ONLY:-0}
  for arg in "$@"; do
    case "$arg" in
      --extra-only) EXTRA_ONLY=1 ; shift ;;
    esac
  done

  if [ "$EXTRA_ONLY" = "1" ]; then
    log "Extra-only mode: importing only supplemental dumps (skipping main dump)"
    wait_for_db
    ensure_core
    import_supplemental
    post_maintenance
    log "Extra-only supplemental import complete."
    return 0
  fi

  if [ -f "$MARKER" ]; then
    log "Marker exists ($MARKER); nothing to do. Remove it to re-run full import. Exiting."; return 0
  fi
  # If split parts already exist we don't need python3 or 7z in this container.
  if ls "$SPLIT_DIR"/part*.xml >/dev/null 2>&1; then
    log "Pre-split parts detected; skipping filter tooling checks"
  else
    # If filtered file exists we can also skip python unless we still need to decompress 7z
    if [ -f "$FILTERED" ]; then
      log "Filtered file present; will import it directly if no parts"
    else
      if ! command -v python3 >/dev/null 2>&1; then
        log "python3 not found and no pre-filtered file/parts. Aborting."; exit 1
      fi
      if ls "$DUMP_DIR"/${ORIG_DUMP_BASENAME}.7z >/dev/null 2>&1; then
        if ! command -v 7z >/dev/null 2>&1; then
          log "7z archive present but 7z binary missing. Decompress externally or preprocess first."; exit 1
        fi
      fi
    fi
  fi
  wait_for_db
  ensure_core
  local dump
  if ls "$SPLIT_DIR"/part*.xml >/dev/null 2>&1; then
    dump="$FILTERED" # for logging context only
    import_dump "$dump"
  else
    if [ -f "$FILTERED" ]; then
      dump="$FILTERED"
      import_dump "$dump"
    else
      if ! dump=$(find_dump); then
        log "Dump file not found (expected $ORIG_DUMP_BASENAME[.gz|.7z])"; exit 1
      fi
      dump=$(maybe_filter "$dump")
      import_dump "$dump"
    fi
  fi
  import_supplemental
  post_maintenance
  touch "$MARKER" || true
  log "All done. Marker created."
}

main "$@"
