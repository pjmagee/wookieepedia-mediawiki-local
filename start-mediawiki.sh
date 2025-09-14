#!/usr/bin/env bash
set -euo pipefail

MW_ROOT="/var/www/html"
DUMP_DIR="/data/dumps"
MARKER="$DUMP_DIR/.imported"
DB_HOST="${MW_DB_HOST:-db}"
DB_NAME="${MW_DB_NAME:-mediawiki}"
DB_USER="${MW_DB_USER:-wikiuser}"
DB_PASS="${MW_DB_PASS:-secret}"

log(){ echo "[startup] $*" >&2; }

wait_for_db(){
  log "Waiting for database $DB_HOST ..."
  local tries=0
  while ! mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e 'SELECT 1' >/dev/null 2>&1; do
    tries=$((tries+1))
    if [ $tries -ge 60 ]; then
      log "Database not reachable after 60 attempts (~60s). Exiting."
      exit 1
    fi
    sleep 1
  done
  log "Database is reachable."
}

run_mw_update(){
  log "Running maintenance/update.php (schema check)" \
    && php "$MW_ROOT/maintenance/update.php" --quick --conf "$MW_ROOT/LocalSettings.php" || true
}

initial_install_if_needed(){
  # Detect if core tables exist; we use 'page' as sentinel.
  if mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e 'SELECT 1 FROM page LIMIT 1' >/dev/null 2>&1; then
    log "Core tables detected; skipping install.php"
    return 0
  fi
  log "No core tables found; running initial install.php"
  local tmpLocal="$MW_ROOT/LocalSettings.php"
  # Temporarily move our LocalSettings aside so install can generate then we restore ours.
  mv "$tmpLocal" "$tmpLocal.preinstall" || true
  php "$MW_ROOT/maintenance/install.php" \
    --dbtype mysql \
    --dbname "$DB_NAME" \
    --dbserver "$DB_HOST" \
    --dbuser "$DB_USER" \
    --dbpass "$DB_PASS" \
    --server "${MW_SERVER:-http://localhost:8080}" \
    --scriptpath "" \
    --lang "${MW_SITE_LANG:-en}" \
    --pass "${MW_ADMIN_PASS:-adminpass}" \
    "${MW_SITE_NAME:-StarWars Local}" "${MW_ADMIN_USER:-admin}" || { log "install.php failed"; mv "$tmpLocal.preinstall" "$tmpLocal" 2>/dev/null || true; return 1; }
  # Restore our curated LocalSettings
  mv "$tmpLocal.preinstall" "$tmpLocal" || true
  log "Initial install complete"
}

import_if_needed(){
  shopt -s nullglob
  local dumpFile=""
  for f in "$DUMP_DIR"/starwars_pages_current.xml*; do
    if [ -f "$f" ]; then dumpFile="$f"; break; fi
  done
  if [ -z "$dumpFile" ]; then
    log "No starwars_pages_current.xml dump present; skipping import."
    return 0
  fi
  if [ -f "$MARKER" ]; then
    log "Import marker exists; skipping import. Remove $MARKER to re-import."
    return 0
  fi
  log "Importing dump $dumpFile (inline)..."
  import-dump || { log "Import failed"; return 1; }
  log "Import complete."
}

import_extras(){
  local extra_dir="$DUMP_DIR/extra"
  [ -d "$extra_dir" ] || return 0
  shopt -s nullglob
  local imported_any=0
  for x in "$extra_dir"/*.xml; do
    [ -f "$x" ] || continue
    local marker="$x.imported"
    # Import if marker missing or file newer than marker
    if [ ! -f "$marker" ] || [ "$x" -nt "$marker" ]; then
      log "Importing supplemental $x"
      if php "$MW_ROOT"/maintenance/importDump.php --conf "$MW_ROOT"/LocalSettings.php --report=100 < "$x"; then
        php "$MW_ROOT"/maintenance/runJobs.php --conf "$MW_ROOT"/LocalSettings.php --maxjobs 100 || true
        touch "$marker" || true
        imported_any=1
      else
        log "Failed to import supplemental $x"
      fi
    fi
  done
  if [ $imported_any -eq 1 ]; then
    log "Supplemental import(s) complete"
  else
    log "No new supplemental XML files to import"
  fi
}

# Main sequence
wait_for_db
initial_install_if_needed
run_mw_update
import_if_needed
import_extras

log "Starting Apache"
exec docker-php-entrypoint apache2-foreground
